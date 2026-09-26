#!/usr/bin/env python3
"""Review all reachable history before a push; never upload or print matched data."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import time
import zipfile

POLICY = '.publication-policy.json'
REVIEW_FIELDS = ('sources_and_comments', 'fixture_provenance', 'identities_and_messages',
                 'archive_contents', 'github_refs_prs_releases_artifacts_lfs_actions',
                 'user_authorized_operations')


class Blocked(Exception):
    pass


def require(condition, reason):
    if not condition:
        raise Blocked(reason)


def git(root, *args, data=None):
    env = {**os.environ, 'GIT_NO_REPLACE_OBJECTS': '1'}
    result = subprocess.run(['git', '-C', str(root), *args], input=data,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    require(result.returncode == 0, 'Git inspection failed (details withheld)')
    return result.stdout


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, sort_keys=True, ensure_ascii=False, indent=2) + '\n').encode()


def private_write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.tmp')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(encoded(value))
    temporary.chmod(0o600)
    temporary.replace(path)


def common(root):
    return Path(git(root, 'rev-parse', '--path-format=absolute', '--git-common-dir').decode().strip())


def policy_for(root):
    return json.loads((root / POLICY).read_text())


def scan(data, policy):
    """A supplementary detector, never a substitute for reading source and output."""
    content = data.decode('utf-8', errors='ignore')
    emails = re.findall(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}', content)
    require(all(address in policy['emails'] for address in emails if address not in policy.get('text_emails', [])), 'Unapproved email detected')
    patterns = (
        r'/(?:Users|home)/[A-Za-z0-9_.\-]+/',
        r'(?i)\b(?:mbp|macbook|slab)[a-z0-9_\-]*-(?:20\d\d|ws\d+)\b',
        r'-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----',
        r'\bgh[pousr]_[A-Za-z0-9]{30,}\b',
        r'\bgithub_pat_[A-Za-z0-9_]{50,}\b',
        r'\bAKIA[A-Z0-9]{16}\b',
        r'https://git-lfs.' + r'github.com/spec/v1',
    )
    require(not any(re.search(pattern, content) for pattern in patterns),
            'Sensitive pattern or unaudited LFS content detected')


def public_path(name):
    parts = PurePosixPath(name).parts
    require(name and not name.startswith('/') and "\\" not in name and
            '..' not in parts, 'Unsafe public path')
    forbidden = {'.git', '.env', '.DS_Store', '__MACOSX', 'archive',
                 'WORKLOG.md', 'AGENTS.local.md', 'practice-progress.json',
                 'key-frequency.json', 'key-frequency.html'}
    require(not any(p in forbidden or p.startswith('.env.') or re.fullmatch(r'practice-progress(?:-v[0-9]+)?\.json', p) or p.endswith(('.log', '.vil'))
                    for p in parts), 'Private working material cannot be published')


def check_index(root, message=None):
    """Inspect the index, including partially staged files, before creating history."""
    policy = json.loads(git(root, 'show', ':' + POLICY))
    previous = json.loads(git(root, 'show', 'HEAD:' + POLICY))
    for field in ('root', 'repository', 'authors', 'emails', 'text_emails'):
        require(policy.get(field) == previous.get(field),
                'Public identity policy changed; a separate explicit review is required')
    for role in ('GIT_AUTHOR_IDENT', 'GIT_COMMITTER_IDENT'):
        identity = git(root, 'var', role).decode().strip()
        match = re.fullmatch(r'(.*?) <([^>]+)> .*', identity)
        require(match and match[1] in policy['authors'] and match[2] in policy['emails'],
                'Unapproved commit identity')
    count = 0
    for entry in git(root, 'ls-files', '--stage', '-z').split(b'\0'):
        if not entry:
            continue
        metadata, raw_path = entry.split(b'\t', 1)
        mode, oid, stage = metadata.decode().split()
        name = raw_path.decode('utf-8')
        public_path(name)
        require(stage == '0' and mode in ('100644', '100755'), 'Unmerged or non-regular staged file')
        require(name in policy['paths'], 'Unlisted staged path; review its provenance first')
        value = git(root, 'cat-file', 'blob', oid)
        require(len(value) <= 2 * 1024 * 1024 and b'\0' not in value, 'Unexpected staged binary or size')
        value.decode('utf-8')
        scan(value, policy)
        count += 1
    if message is not None:
        scan(Path(message).read_bytes(), policy)
    return count


def inspect_asset(path, policy):
    require(path.is_file() and not path.is_symlink(), 'Artifact must be a regular file')
    require(path.stat().st_size <= 200 * 1024 * 1024, 'Artifact exceeds review size limit')
    data = path.read_bytes()
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            names = set()
            size = 0
            for member in archive.infolist():
                name = member.filename
                public_path(name.rstrip('/'))
                parts = PurePosixPath(name).parts
                require(name and not name.startswith('/') and '\\' not in name and
                        '..' not in parts and name not in names, 'Unsafe archive entry')
                names.add(name)
                require(not any(p in ('.git', 'archive', 'WORKLOG.md', 'AGENTS.local.md') for p in parts),
                        'Private working material in archive')
                mode = member.external_attr >> 16
                require(not stat.S_ISLNK(mode), 'Archive symlinks are not permitted')
                size += member.file_size
                require(size <= 200 * 1024 * 1024, 'Expanded archive exceeds review size limit')
                if member.is_dir():
                    continue
                value = archive.read(member)
                require(not zipfile.is_zipfile(__import__('io').BytesIO(value)), 'Nested archives require separate review')
                scan(value, policy)
                if b'\0' in value:
                    for offset in (0, 1):
                        for encoding in ('utf-16-le', 'utf-16-be'):
                            scan(value[offset:].decode(encoding, errors='ignore').encode(), policy)
                    require(name in policy.get('binary_archive_members', []),
                            'Unlisted binary archive member')
    else:
        require(b'\0' not in data, 'Binary assets must be in an inspected archive')
        scan(data, policy)
    return sha(data)


def audit(root, files=()):
    require(not git(root, 'status', '--porcelain').strip(), 'Commit reviewed changes before auditing')
    base = common(root)
    require(not (base / 'objects/info/alternates').exists() and
            not (base / 'info/grafts').exists(), 'Shared or grafted object history is forbidden')
    require(git(root, 'rev-parse', '--is-shallow-repository').strip() == b'false', 'Full history required')
    refs = dict(line.split(' ', 1) for line in git(root, 'for-each-ref',
                '--format=%(refname) %(objectname)').decode().splitlines())
    require(not any(ref.startswith('refs/replace/') for ref in refs), 'Replace refs are forbidden')
    require(not os.environ.get('GIT_NAMESPACE') and not os.environ.get('GIT_ALTERNATE_OBJECT_DIRECTORIES'),
            'Alternate Git namespace or object directories are forbidden')
    refs['HEAD'] = git(root, 'rev-parse', 'HEAD').decode().strip()
    policy = policy_for(root)
    scan('\n'.join(refs).encode(), policy)
    tips = sorted(set(refs.values()))
    for tip in tips:
        git(root, 'rev-parse', '--verify', tip + '^{commit}')
    roots = set(git(root, 'rev-list', '--max-parents=0', *tips).decode().splitlines())
    require(roots == {policy['root']}, 'Foreign or private history detected')
    commits = git(root, 'rev-list', *tips).decode().splitlines()
    allowed = set(policy['paths'])
    blobs = set()
    for commit in commits:
        raw = git(root, 'cat-file', 'commit', commit)
        scan(raw, policy)
        for role in (b'author', b'committer'):
            match = re.search(rb'^' + role + rb' (.*?) <([^>]+)> ', raw, re.M)
            require(match is not None and match[1].decode() in policy['authors'] and
                    match[2].decode() in policy['emails'], 'Unapproved commit identity')
        for entry in git(root, 'ls-tree', '-rz', '--full-tree', commit).split(b'\0'):
            if not entry:
                continue
            metadata, raw_path = entry.split(b'\t', 1)
            mode, kind, oid = metadata.decode().split()
            path = raw_path.decode()
            public_path(path)
            require(path in allowed, 'Unlisted path exists in reachable history')
            require(mode in ('100644', '100755') and kind == 'blob', 'Symlink or submodule in source')
            blobs.add(oid)
    for oid in blobs:
        value = git(root, 'cat-file', 'blob', oid)
        require(len(value) <= 2 * 1024 * 1024 and b'\0' not in value, 'Unexpected binary or large source blob')
        value.decode('utf-8')
        scan(value, policy)
    objects = git(root, 'rev-list', '--objects', '--no-object-names', *tips).decode().splitlines()
    for oid in objects:
        if git(root, 'cat-file', '-t', oid).strip() == b'tag':
            raw = git(root, 'cat-file', 'tag', oid)
            scan(raw, policy)
            match = re.search(rb'^tagger (.*?) <([^>]+)> ', raw, re.M)
            require(match is not None and match[1].decode() in policy['authors'] and
                    match[2].decode() in policy['emails'], 'Unapproved tag identity')
    asset_hashes = {str(Path(path).resolve()): inspect_asset(Path(path), policy) for path in files}
    snapshot = {'refs': refs, 'objects': sorted(objects), 'policy': sha(encoded(policy)),
                'guard': sha(Path(__file__).read_bytes()), 'assets': asset_hashes}
    return {'fingerprint': sha(encoded(snapshot)), 'snapshot': snapshot,
            'counts': {'commits': len(commits), 'blobs': len(blobs), 'refs': len(refs) - 1}}


def repository_id(full_name):
    result = subprocess.run(['gh', 'api', '--hostname', 'github.com', 'repos/' + full_name,
                             '--jq', '.id'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    require(result.returncode == 0 and result.stdout.strip().isdigit(),
            'Cannot verify GitHub repository identity')
    return int(result.stdout)


def destination(url, full_name):
    return url in ('https://github.com/' + full_name, 'https://github.com/' + full_name + '.git',
                   'git@github.com:' + full_name + '.git', 'ssh://git@github.com/' + full_name + '.git')


def install(root, repo_id=None):
    report = audit(root)
    policy = policy_for(root)
    if repo_id is not None:
        require(repo_id > 0 and repository_id(policy['repository']) == repo_id, 'Repository ID mismatch')
    directory = common(root) / 'publication-guard'
    directory.mkdir(mode=0o700, exist_ok=True)
    directory.chmod(0o700)
    (directory / 'guard.py').write_bytes(Path(__file__).read_bytes())
    (directory / 'guard.py').chmod(0o700)
    trust = {'repository': policy['repository'], 'repository_id': repo_id,
             'root': policy['root'], 'policy': report['snapshot']['policy'],
             'guard': report['snapshot']['guard']}
    private_write(directory / 'trust.json', trust)
    hooks = directory / 'hooks'
    hooks.mkdir(exist_ok=True)
    hook = hooks / 'pre-push'
    hook.write_text('#!/bin/sh\nexec python3 "$(git rev-parse --path-format=absolute --git-common-dir)/publication-guard/guard.py" pre-push "$@"\n')
    hook.chmod(0o700)
    for name, command in [('pre-commit', 'check-index'), ('commit-msg', 'check-message')]:
        local_hook = hooks / name
        local_hook.write_text('#!/bin/sh\nexec python3 "$(git rev-parse --path-format=absolute --git-common-dir)/publication-guard/guard.py" ' + command + ' "$@"\n')
        local_hook.chmod(0o700)
    git(root, 'config', '--local', 'core.hooksPath', str(hooks))
    git(root, 'config', '--local', 'user.useConfigOnly', 'true')
    return trust


def trust_for(root, report):
    directory = common(root) / 'publication-guard'
    require((directory / 'trust.json').is_file(), 'Install the local publication gate first')
    trust = json.loads((directory / 'trust.json').read_text())
    policy = policy_for(root)
    require(trust['root'] == policy['root'] and trust['repository'] == policy['repository'] and
            trust['policy'] == report['snapshot']['policy'] and trust['guard'] == report['snapshot']['guard'],
            'Guard or policy changed; review and reinstall the gate')
    require(trust['repository_id'] is not None, 'Gate is locked until the new repository ID is pinned')
    require(repository_id(trust['repository']) == trust['repository_id'], 'Destination repository was replaced')
    return directory, trust


def authorize(root, report_path, evidence_path, refs, operations, files):
    report = audit(root, files)
    prior = json.loads(Path(report_path).read_text())
    require(prior['fingerprint'] == report['fingerprint'], 'Audit is stale')
    directory, trust = trust_for(root, report)
    evidence = json.loads(Path(evidence_path).read_text())
    require(evidence.get('fingerprint') == report['fingerprint'] and
            all(evidence.get(field) is True for field in REVIEW_FIELDS), 'Content review or authorization is incomplete')
    selected = {}
    for ref in refs:
        require(ref.startswith('refs/heads/codex/') or ref.startswith('refs/tags/v'), 'Unapproved push ref')
        require(ref in report['snapshot']['refs'], 'Push ref is absent from audit')
        selected[ref] = report['snapshot']['refs'][ref]
    require(operations and set(operations) <= {'push', 'pr', 'release', 'pages'}, 'Explicit operations required')
    require('push' not in operations or bool(selected), 'Select exact push refs')
    receipt = {'fingerprint': report['fingerprint'], 'trust': sha(encoded(trust)),
               'evidence': sha(Path(evidence_path).read_bytes()), 'refs': selected,
               'operations': operations, 'files': list(report['snapshot']['assets']),
               'expires': time.time() + 24 * 3600}
    private_write(directory / 'receipt.json', receipt)


def approved(root, operation):
    directory = common(root) / 'publication-guard'
    require((directory / 'receipt.json').is_file(), 'No reviewed publication authorization')
    receipt = json.loads((directory / 'receipt.json').read_text())
    require(time.time() < receipt['expires'] and operation in receipt['operations'], 'Authorization expired or operation absent')
    report = audit(root, receipt['files'])
    _, trust = trust_for(root, report)
    require(receipt['trust'] == sha(encoded(trust)) and receipt['fingerprint'] == report['fingerprint'],
            'History, refs, policy or artifacts changed since review')
    return receipt, trust


def pre_push(root, url, updates):
    receipt, trust = approved(root, 'push')
    require(destination(url, trust['repository']), 'Unapproved push URL')
    for line in updates.splitlines():
        local_ref, local_sha, remote_ref, remote_sha = line.split()
        require(local_ref == remote_ref and receipt['refs'].get(local_ref) == local_sha,
                'Push does not match exact reviewed refs; main, deletion and alias pushes are blocked')
        if set(remote_sha) != {'0'}:
            if remote_ref.startswith('refs/tags/'):
                require(remote_sha == local_sha, 'Tag replacement is blocked')
            else:
                result = subprocess.run(['git', '-C', str(root), 'merge-base', '--is-ancestor', remote_sha, local_sha],
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                require(result.returncode == 0, 'Non-fast-forward push is blocked')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('check-index')
    message = commands.add_parser('check-message')
    message.add_argument('path')
    assets = commands.add_parser('check-assets')
    assets.add_argument('--file', action='append', required=True)
    check = commands.add_parser('audit')
    check.add_argument('--report', required=True)
    check.add_argument('--file', action='append', default=[])
    setup = commands.add_parser('install')
    setup.add_argument('--repository-id', type=int)
    review = commands.add_parser('authorize')
    for name in ('report', 'evidence'):
        review.add_argument('--' + name, required=True)
    for name in ('ref', 'operation', 'file'):
        review.add_argument('--' + name, action='append', default=[])
    hook = commands.add_parser('pre-push')
    hook.add_argument('remote')
    hook.add_argument('url')
    upload = commands.add_parser('check-upload')
    upload.add_argument('--operation', choices=('pr', 'release', 'pages'), required=True)
    upload.add_argument('--file', action='append', required=True)
    args = parser.parse_args()
    root = Path(git(Path.cwd(), 'rev-parse', '--show-toplevel').decode().strip())
    if args.command in ('check-index', 'check-message'):
        count = check_index(root, args.path if args.command == 'check-message' else None)
        print(f'Public index and identities checked: {count} files')
    elif args.command == 'check-assets':
        for path in args.file:
            inspect_asset(Path(path), policy_for(root))
        print(f'Public artifact contents checked: {len(args.file)} files; upload not authorized')
    elif args.command == 'audit':
        report = audit(root, args.file)
        private_write(Path(args.report), report)
        print(json.dumps({'fingerprint': report['fingerprint'], 'counts': report['counts']}))
    elif args.command == 'install':
        install(root, args.repository_id)
        print('Local gate installed; a separate, current review receipt is required for publication.')
    elif args.command == 'authorize':
        authorize(root, args.report, args.evidence, args.ref, args.operation, args.file)
        print('Review receipt created for the specified operations, refs and files (24 hours).')
    elif args.command == 'pre-push':
        pre_push(root, args.url, sys.stdin.read())
    else:
        receipt, _ = approved(root, args.operation)
        require(all(str(Path(path).resolve()) in receipt['files'] for path in args.file), 'Unreviewed upload file')
        print('Exact files match the reviewed authorization; no upload performed.')


if __name__ == '__main__':
    try:
        main()
    except (Blocked, ValueError, KeyError, OSError, zipfile.BadZipFile) as error:
        message = str(error) if isinstance(error, Blocked) else 'Inspection failed; no publication permitted'
        print('BLOCKED: ' + message, file=sys.stderr)
        sys.exit(1)

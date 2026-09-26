#!/usr/bin/env python3
"""Synthetic Git/ZIP cases; no real contacts, input records or device data."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

location = Path(__file__).with_name('publication_guard.py')
spec = importlib.util.spec_from_file_location('publication_guard', location)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)
IDENTITY = 'maintainer' + '@' + 'users.noreply.github.com'


class PublicationGuardTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / 'source'
        self.root.mkdir()
        self.env = {**os.environ, 'GIT_CONFIG_GLOBAL': os.devnull, 'GIT_CONFIG_NOSYSTEM': '1',
                    'GIT_AUTHOR_NAME': 'Public Maintainer', 'GIT_AUTHOR_EMAIL': IDENTITY,
                    'GIT_COMMITTER_NAME': 'Public Maintainer', 'GIT_COMMITTER_EMAIL': IDENTITY}
        self.environment = patch.dict(os.environ, self.env)
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.run_git('init', '-b', 'codex/candidate')
        (self.root / 'README.md').write_text('Synthetic product source\n')
        self.commit()
        base = self.run_git('rev-parse', 'HEAD').strip()
        self.policy = {'repository': 'example/project', 'root': base,
                       'authors': ['Public Maintainer'], 'emails': [IDENTITY],
                       'paths': ['README.md', 'note.md', guard.POLICY]}
        (self.root / guard.POLICY).write_text(json.dumps(self.policy))
        self.commit()

    def run_git(self, *args, data=None):
        return subprocess.check_output(['git', '-C', str(self.root), '-c', 'commit.gpgsign=false',
                                        *args], env=os.environ, input=data, text=True, stderr=subprocess.DEVNULL)

    def commit(self):
        self.run_git('add', '-A')
        self.run_git('commit', '-m', 'Synthetic review fixture')

    def authorize(self, files=()):
        with patch.object(guard, 'repository_id', return_value=123):
            guard.install(self.root, 123)
            report = guard.audit(self.root, files)
            report_path = Path(self.temporary.name) / 'report.json'
            evidence_path = Path(self.temporary.name) / 'review.json'
            report_path.write_text(json.dumps(report))
            evidence_path.write_text(json.dumps({'fingerprint': report['fingerprint'],
                                                **{field: True for field in guard.REVIEW_FIELDS}}))
            guard.authorize(self.root, report_path, evidence_path, ['refs/heads/codex/candidate'],
                            ['push', 'release'], files)
        return report

    def test_index_rejects_staged_contact_even_when_worktree_is_cleaned(self):
        (self.root / 'note.md').write_text('private' + '@' + 'example.org')
        self.run_git('add', 'note.md')
        (self.root / 'note.md').write_text('Safe working copy')
        with self.assertRaisesRegex(guard.Blocked, 'email'):
            guard.check_index(self.root)

    def test_index_blocks_private_paths_even_if_added_to_allowlist(self):
        self.policy['paths'].append('WORKLOG.md')
        (self.root / guard.POLICY).write_text(json.dumps(self.policy))
        (self.root / 'WORKLOG.md').write_text('Synthetic record')
        self.run_git('add', '-A')
        with self.assertRaisesRegex(guard.Blocked, 'Private working'):
            guard.check_index(self.root)

    def test_all_progress_store_versions_are_private_assets(self):
        for name in ['practice-progress.json', 'practice-progress-v2.json', 'practice-progress-v99.json']:
            with self.subTest(name=name), self.assertRaisesRegex(guard.Blocked, 'Private working'):
                guard.public_path('Resources/' + name)

    def test_index_prevents_broadening_contact_allowlist(self):
        self.policy['emails'].append('private' + '@' + 'example.org')
        (self.root / guard.POLICY).write_text(json.dumps(self.policy))
        self.run_git('add', '-A')
        with self.assertRaisesRegex(guard.Blocked, 'identity policy'):
            guard.check_index(self.root)

    def test_installed_hooks_block_commit_and_message_before_history(self):
        guard.install(self.root)
        head = self.run_git('rev-parse', 'HEAD')
        (self.root / 'README.md').write_text('private' + '@' + 'example.org')
        self.run_git('add', '-A')
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_git('commit', '-m', 'Synthetic fixture')
        self.assertEqual(self.run_git('rev-parse', 'HEAD'), head)
        (self.root / 'README.md').write_text('Safe synthetic source')
        self.run_git('add', '-A')
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_git('commit', '-m', 'private' + '@' + 'example.org')
        self.assertEqual(self.run_git('rev-parse', 'HEAD'), head)
        self.run_git('commit', '-m', 'Safe synthetic message')

    def test_nested_archive_is_not_silently_skipped(self):
        import io
        inner = io.BytesIO()
        with zipfile.ZipFile(inner, 'w') as archive:
            archive.writestr('data.txt', 'Synthetic')
        asset = Path(self.temporary.name) / 'outer.zip'
        with zipfile.ZipFile(asset, 'w') as archive:
            archive.writestr('inner.zip', inner.getvalue())
        with self.assertRaisesRegex(guard.Blocked, 'Nested'):
            guard.inspect_asset(asset, self.policy)

    def test_utf16_contact_in_allowed_executable_is_blocked(self):
        asset = Path(self.temporary.name) / 'app.zip'
        self.policy['binary_archive_members'] = ['Product.app/Contents/MacOS/Product']
        with zipfile.ZipFile(asset, 'w') as archive:
            archive.writestr('Product.app/Contents/MacOS/Product',
                             ('private' + '@' + 'example.org').encode('utf-16-le'))
        with self.assertRaisesRegex(guard.Blocked, 'email'):
            guard.inspect_asset(asset, self.policy)

    def test_reviewed_history_passes(self):
        self.assertEqual(guard.audit(self.root)['counts']['commits'], 2)

    def test_deleted_contact_remains_blocked_in_history(self):
        (self.root / 'note.md').write_text('private' + '@' + 'example.org')
        self.commit()
        (self.root / 'note.md').unlink()
        self.commit()
        with self.assertRaisesRegex(guard.Blocked, 'email'):
            guard.audit(self.root)

    def test_unlisted_path_is_blocked(self):
        (self.root / 'unreviewed.txt').write_text('Synthetic contents')
        self.commit()
        with self.assertRaisesRegex(guard.Blocked, 'Unlisted path'):
            guard.audit(self.root)

    def test_foreign_root_on_other_ref_is_blocked(self):
        tree = self.run_git('rev-parse', 'HEAD^{tree}').strip()
        foreign = self.run_git('commit-tree', tree, data='Synthetic unrelated root\n').strip()
        self.run_git('update-ref', 'refs/heads/codex/foreign', foreign)
        with self.assertRaisesRegex(guard.Blocked, 'Foreign'):
            guard.audit(self.root)

    def test_commit_contact_is_checked(self):
        (self.root / 'README.md').write_text('Updated synthetic source')
        with patch.dict(os.environ, {'GIT_COMMITTER_EMAIL': 'private' + '@' + 'example.org'}):
            self.commit()
        with self.assertRaisesRegex(guard.Blocked, 'email'):
            guard.audit(self.root)

    def test_missing_receipt_blocks_push(self):
        guard.install(self.root)
        with self.assertRaisesRegex(guard.Blocked, 'No reviewed'):
            guard.pre_push(self.root, 'https://github.com/example/project.git', '')

    def test_installed_hook_blocks_an_actual_unreviewed_push(self):
        guard.install(self.root)
        target = Path(self.temporary.name) / 'destination.git'
        subprocess.run(['git', 'init', '--bare', str(target)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        result = subprocess.run(['git', '-C', str(self.root), 'push', str(target),
                                 'refs/heads/codex/candidate'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'No reviewed publication authorization', result.stderr)
        self.assertEqual(subprocess.run(['git', '--git-dir', str(target), 'for-each-ref'],
                                        stdout=subprocess.PIPE, check=True).stdout, b'')

    def test_unpinned_install_is_locked(self):
        report = guard.audit(self.root)
        guard.install(self.root)
        with self.assertRaisesRegex(guard.Blocked, 'locked'):
            guard.trust_for(self.root, report)

    def test_review_allows_only_exact_ref_and_destination(self):
        self.authorize()
        head = self.run_git('rev-parse', 'HEAD').strip()
        update = 'refs/heads/codex/candidate ' + head + ' refs/heads/codex/candidate ' + '0' * 40
        with patch.object(guard, 'repository_id', return_value=123):
            guard.pre_push(self.root, 'https://github.com/example/project.git', update)
            with self.assertRaisesRegex(guard.Blocked, 'URL'):
                guard.pre_push(self.root, 'https://github.com/example/other.git', update)
            with self.assertRaisesRegex(guard.Blocked, 'exact reviewed'):
                guard.pre_push(self.root, 'https://github.com/example/project.git',
                               update.replace(' refs/heads/codex/candidate ', ' refs/heads/main '))
        with patch.object(guard, 'repository_id', return_value=456):
            with self.assertRaisesRegex(guard.Blocked, 'replaced'):
                guard.pre_push(self.root, 'https://github.com/example/project.git', update)

    def test_new_commit_invalidates_receipt(self):
        self.authorize()
        (self.root / 'README.md').write_text('Changed source')
        self.commit()
        with patch.object(guard, 'repository_id', return_value=123):
            with self.assertRaisesRegex(guard.Blocked, 'changed since review'):
                guard.approved(self.root, 'push')

    def test_new_tag_invalidates_receipt(self):
        self.authorize()
        self.run_git('tag', 'v0.1.0')
        with patch.object(guard, 'repository_id', return_value=123):
            with self.assertRaisesRegex(guard.Blocked, 'changed since review'):
                guard.approved(self.root, 'push')

    def test_changed_artifact_invalidates_receipt(self):
        asset = Path(self.temporary.name) / 'release.md'
        asset.write_text('Reviewed product description')
        self.authorize([asset])
        asset.write_text('Changed product description')
        with patch.object(guard, 'repository_id', return_value=123):
            with self.assertRaisesRegex(guard.Blocked, 'changed since review'):
                guard.approved(self.root, 'release')

    def test_zip_traversal_and_contact_are_blocked(self):
        asset = Path(self.temporary.name) / 'artifact.zip'
        with zipfile.ZipFile(asset, 'w') as archive:
            archive.writestr('../escape.txt', 'Synthetic')
        with self.assertRaisesRegex(guard.Blocked, 'Unsafe (?:archive|public)'):
            guard.inspect_asset(asset, self.policy)
        with zipfile.ZipFile(asset, 'w') as archive:
            archive.writestr('README.md', 'private' + '@' + 'example.org')
        with self.assertRaisesRegex(guard.Blocked, 'email'):
            guard.inspect_asset(asset, self.policy)

    def test_no_force_update(self):
        self.authorize()
        head = self.run_git('rev-parse', 'HEAD').strip()
        unknown = 'f' * 40
        with patch.object(guard, 'repository_id', return_value=123):
            with self.assertRaisesRegex(guard.Blocked, 'Non-fast-forward'):
                guard.pre_push(self.root, 'https://github.com/example/project.git',
                               f'refs/heads/codex/candidate {head} refs/heads/codex/candidate {unknown}')

    def test_policy_change_cannot_reuse_trust(self):
        self.authorize()
        self.policy['paths'].append('another.txt')
        (self.root / guard.POLICY).write_text(json.dumps(self.policy))
        self.commit()
        with patch.object(guard, 'repository_id', return_value=123):
            with self.assertRaisesRegex(guard.Blocked, 'reinstall'):
                guard.approved(self.root, 'push')


if __name__ == '__main__':
    unittest.main()

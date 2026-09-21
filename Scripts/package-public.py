#!/usr/bin/env python3
"""Build an ad-hoc local candidate from a clean commit. Never install or upload."""
import hashlib
import json
import os
import plistlib
import re
import subprocess
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
def run(*args, **kwargs):
    return subprocess.run(args, cwd=root, check=True, **kwargs)
def output(*args):
    return subprocess.check_output(args, cwd=root, text=True).strip()
if output('git', 'status', '--porcelain'):
    raise SystemExit('Commit and review public sources before packaging')
run('python3', 'Scripts/check-public.py')
revision = output('git', 'rev-parse', 'HEAD')
run('./Scripts/build-app.sh', env={**os.environ, 'CODESIGN_IDENTITY': '-', 'CONFIGURATION': 'release'})
app = root / 'build/WKRPublic.app'
binary = app / 'Contents/MacOS/WKRPublic'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
architecture = output('/usr/bin/lipo', '-archs', str(binary))
if not re.fullmatch('[a-zA-Z0-9_ ]+', architecture):
    raise SystemExit('Unexpected architecture')
# Compiler remapping plus stripping must have removed local developer paths.
if re.search(rb'/Users/[^/\x00\s]+/|/home/[^/\x00\s]+/', binary.read_bytes()):
    raise SystemExit('Local home path found in distribution executable')
# Keep each reviewed candidate separate from older archives.
out = root / 'build/distribution' / info['WKRReleaseVersion']
out.mkdir(parents=True, exist_ok=True)
name = 'WKR-macOS-' + info['WKRReleaseVersion'] + '-' + architecture.replace(' ', '-') + '-adhoc.zip'
files = [(p, str(p.relative_to(app.parent))) for p in sorted(app.rglob('*')) if p.is_file()]
for name_in_repo in ['README.md', 'LICENSE', 'AGENTS.md', 'Scripts/README.md']:
    files.append((root / name_in_repo, name_in_repo))
files.extend((p, str(p.relative_to(root))) for p in sorted((root / 'docs').glob('*.md')))
with zipfile.ZipFile(out / name, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path, entry in files:
        if path.is_symlink():
            raise SystemExit('Unexpected symlink in distribution')
        header = zipfile.ZipInfo(entry, (2026, 9, 21, 0, 0, 0))
        header.compress_type = zipfile.ZIP_DEFLATED
        header.external_attr = (0o100755 if path == binary else 0o100644) << 16
        archive.writestr(header, path.read_bytes())
upstream = json.loads((root / 'Resources/upstream-manifest.json').read_text())
manifest = {'repository': 'https://github.com/yuhkis/wkr-macos', 'revision': revision,
    'appVersion': info['WKRReleaseVersion'], 'build': info['CFBundleVersion'],
    'bundleIdentifier': info['CFBundleIdentifier'], 'architecture': architecture,
    'layoutVersion': upstream['layoutVersion'], 'layoutRevision': upstream['revision'],
    'practiceVersion': upstream['practiceVersion'], 'signing': 'ad-hoc', 'notarized': False,
    'archive': name, 'sha256': hashlib.sha256((out / name).read_bytes()).hexdigest()}
(out / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
checks = [manifest['sha256'] + '  ' + name,
    hashlib.sha256((out / 'manifest.json').read_bytes()).hexdigest() + '  manifest.json']
(out / 'SHA256SUMS').write_text('\n'.join(checks) + '\n')
print('\n'.join(checks))

#!/usr/bin/env python3
"""Check the frozen v1 source manifest and its public logging boundary."""
import hashlib,json,re
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'Legacy/wkr-macos-v1'
manifest=json.loads((root/'archive-source.json').read_text())
assert manifest['archiveVersion']=='0.7.0-archive.1' and manifest['layoutVersion']=='1.1.0'
for name,expected in manifest['files'].items():
    path=root/name
    assert not path.is_symlink() and path.is_file(),name
    assert hashlib.sha256(path.read_bytes()).hexdigest()==expected,('archive source changed',name)
source='\n'.join(p.read_text() for p in (root/'Sources').rglob('*.swift'))
for forbidden in ['state=reset reason=', 'pending-flushed reason=', 'pending-released reason=',
                  'unicode-injection-skipped reason=', 'english-fallback state=', 'summary transformed=',
                  'frontmost-application id=', 'input-source id=', 'decision.result.stateCode.rawValue, privacy:']:
    assert forbidden not in source, 'per-event or identifying log remains'
assert 'private var engineLease: EngineLease?' in source
assert 'io.github.yuhkis.wkr-macos.v1-archive' in source
print('Frozen v1 source hashes and public boundary passed')

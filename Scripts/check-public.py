#!/usr/bin/env python3
"""Check current Public sources/resources. This is not a Git-history audit."""
import argparse
import hashlib
import json
import plistlib
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--allow-uncommitted', action='store_true', help='Only for local development before pinning upstream')
args = parser.parse_args()
def require(condition, message):
    if not condition:
        raise SystemExit(message)

manifest = json.loads((root / 'Resources/upstream-manifest.json').read_text())
revision = manifest['revision']
require(bool(re.fullmatch('[0-9a-f]{40}', revision)) or
        args.allow_uncommitted and revision == 'uncommitted', 'Pin a committed public layout before distribution')
require(manifest['upstream'] == 'https://github.com/yuhkis/wkr-layout', 'Unexpected upstream')
for source, expected in manifest['files'].items():
    if source == 'data/layout-v2.json':
        destination = 'Resources/Layout/layout-v2.json'
    elif source.startswith('practice/') and source != 'practice/lessons.json':
        destination = 'Resources/Practice/' + source.split('/', 1)[1]
    elif source == 'LICENSE':
        destination = 'Resources/Practice/LICENSE'
    else:
        continue
    require(hashlib.sha256((root / destination).read_bytes()).hexdigest() == expected,
            'Bundled resource differs: ' + destination)

info = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
require(info['CFBundleIdentifier'] == 'io.github.yuhkis.wkr-macos.public', 'Unexpected public identity')
require(info['CFBundleExecutable'] == 'WKRPublic', 'Unexpected executable identity')
require(info['WKRLayoutVersion'] == manifest['layoutVersion'] and info['WKRPracticeVersion'] == manifest['practiceVersion'], 'Bundle layout/practice versions differ')
version_source = (root / 'Sources/WKRMacOS/AppVersion.swift').read_text()
require('"' + info['WKRReleaseVersion'] + '"' in version_source, 'App version differs')
layout_source = (root / 'Sources/WKRCore/WKRLayout.swift').read_text()
require('"' + revision + '"' in layout_source, 'Compiled layout pin differs')
require('"' + manifest['layoutVersion'] + '"' in layout_source, 'Compiled layout version differs')
practice = (root / 'Resources/Practice/data.js').read_text()
require('"layoutSHA256":"' + manifest['files']['data/layout-v2.json'] + '"' in practice, 'Practice layout differs')
require('"practiceVersion":"' + manifest['practiceVersion'] + '"' in practice, 'Practice version differs')

# Reject the removed Private implementation across all runtime sources, not
# merely the menu. Tests and docs intentionally name unsupported settings.
forbidden = re.compile(r'Detailed(?:Key)?Log|KeyPairTiming|RulePair(?:Count|Recorder|Report)|ShiftEnter(?:Attribution|Window)|RSftEnter|PracticePagePath|PracticeLimitMinutes|completedRuleIDs|IOHIDManager|IOHIDDevice|URLSession|NSURLConnection')
for directory in ['Sources', 'Resources/Practice']:
    for path in (root / directory).rglob('*'):
        if path.suffix not in {'.swift', '.js', '.html', '.css'}:
            continue
        require(not forbidden.search(path.read_text()), 'Removed Private/network implementation in ' + str(path.relative_to(root)))

config = (root / 'Sources/WKRMacOS/AppConfiguration.swift').read_text()
supported = {'--practice-only', '--help', '--version', '--print-input-source',
    '--key-frequency-report', '--key-frequency-reset', '--key-frequency-archive',
    '--key-frequency', '--key-frequency-retention', '--key-frequency-store',
    '--key-frequency-report-output', '--output', '--vil', '--open', '--input-source-id',
    '--input-mode-id', '--mode', '--exclude-app', '--english-fallback', '--symbol-layer',
    '--request-permissions', '--allow-unverified-optimistic'}
require(set(re.findall(r'"(--[a-z][a-z-]*)"', config)) == supported, 'CLI changed: review public allowlist')
defaults = set(re.findall(r'static let \w+DefaultsKey = "([^"]+)"', config))
require(defaults == {'EnglishFallbackTrigger', 'SymbolLayer', 'KeyFrequencyLog', 'KeyFrequencyRetentionDays', 'VialKeymapPath'}, 'Defaults changed: review public allowlist')
require('case nil, "off"' in config, 'Key frequency default must remain off')
require('unsupportedOption' in config, 'Unknown long options must fail closed')
recorder = (root / 'Sources/WKRMacOS/KeyFrequencyRecorder.swift').read_text()
require('io.github.yuhkis.wkr-macos.public' in recorder and 'ioQueue.async' in recorder, 'Storage boundary changed')
bridge = (root / 'Sources/WKRMacOS/PracticeWindowController.swift').read_text()
require('.nonPersistent()' in bridge and '["load","save","delete"]' in bridge and 'message.frameInfo.isMainFrame' in bridge, 'Practice bridge changed: review required')
require("connect-src 'none'" in (root / 'Resources/Practice/index.html').read_text(), 'Practice must be offline')
print('Public boundary, independent versions, resource hashes and ' + str(len(supported)) + ' CLI options checked')

#!/usr/bin/env python3
"""Dependency-free checks for this repo's fixed local plugin contract."""
import json, plistlib, re
from pathlib import Path
root = Path(__file__).resolve().parent.parent
p = root / 'plugins/quota-companion'
j = json.loads((p / '.codex-plugin/plugin.json').read_text())
version = plistlib.loads((root / 'Packaging/Info.plist').read_bytes())['CFBundleShortVersionString']
assert j['name'] == p.name == 'quota-companion'
assert j['version'] == version and j['license'] == 'MIT'
assert j['skills'] == './skills/' and j['mcpServers'] == './.mcp.json'
for key in ['composerIcon','logo']:
    path = p / j['interface'][key]
    assert path.is_file() and not path.is_symlink()
for path in j['interface'].get('screenshots', []):
    assert (p/path).is_file()
mcp=json.loads((p/'.mcp.json').read_text())
assert mcp == {'mcpServers': {'quota-companion': {'command':'./bin/quota-companion-mcp','args':[],'cwd':'.'}}}
skill=(p/'skills/quota-companion/SKILL.md').read_text()
assert skill.startswith('---\nname: quota-companion\ndescription: ') and skill.count('\n---\n') == 1
for name in ['get_quota_status','show_companion','collapse_companion','open_companion_settings']:
    assert name in skill and name in (root/'Sources/QuotaCompanionMCP/main.swift').read_text()
market=json.loads((root/'.agents/plugins/marketplace.json').read_text())
assert market['name']=='quota-companion-dev'
assert market['plugins'][0]['source']=={'source':'local','path':'./plugins/quota-companion'}
for f in p.rglob('*'):
    assert not f.is_symlink()
print('Plugin manifest, skill, local marketplace, image references, version and four-tool contract passed.')

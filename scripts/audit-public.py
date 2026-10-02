#!/usr/bin/env python3
"""Scan all public paths AND every reachable Git blob; prints paths, never matched secrets."""
import argparse, hashlib, json, re, struct, subprocess
from pathlib import Path
root = Path(__file__).resolve().parent.parent
ALLOWED_ROOT = {'Package.swift','LICENSE','README.md','SECURITY.md','THIRD_PARTY_NOTICES.md','.gitignore'}
ALLOWED_DIR = {'Sources','Tests','Packaging','scripts','docs','plugins'}
BLOCKED_PARTS = {'.env','.DS_Store','output','screenshots','Characters','Backgrounds','Mascots','auth.json','config.toml','quota-snapshot.json','threshold-state.json'}
patterns = [
 re.compile(rb'/' + rb'Users/[^\s/]+/'), re.compile(rb'/' + rb'Volumes/[^/\s]+/'),
 re.compile(rb'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
 re.compile(rb'(?:gh[pousr]_|github_pat_|sk-proj-)[A-Za-z0-9_\-]{16,}'),
 re.compile(rb'\b[A-Za-z0-9._%+-]+@(?!example\.(?:com|org))[^\s"<>]+\.[A-Za-z]{2,}\b'),
]
def allowed(path):
 p=Path(path)
 return (path in ALLOWED_ROOT or p.parts[0] in ALLOWED_DIR or path=='.agents/plugins/marketplace.json') and not any(x in BLOCKED_PARTS or x.startswith('._') for x in p.parts) and 'bin' not in p.parts

def scan(path, data):
 assert allowed(path), f'Unapproved path: {path}'
 if path.endswith('.png'):
  assert data[:8]==b'\x89PNG\r\n\x1a\n', path
  i=8
  while i<len(data):
   length=struct.unpack('>I',data[i:i+4])[0]; kind=data[i+4:i+8]
   assert kind not in [b'eXIf',b'tEXt',b'zTXt',b'iTXt'], f'Unreviewed image metadata: {path}'
   i+=length+12
 else:
  data.decode('utf-8')
  if path == 'Tests/QuotaCompanionAppTests/Speech215Tests.swift':
   # Deliberately invalid URL-userinfo fixture, not an email or real credential.
   data = data.replace(b'https://key' + b'@api.minimax.cn/v1/t2a_v2', b'https://invalid-userinfo-fixture.test')
  assert not any(p.search(data) for p in patterns), f'Sensitive content candidate: {path}'

def git(*args): return subprocess.check_output(['git','-C',str(root),*args])
parser=argparse.ArgumentParser();parser.add_argument('--history',action='store_true');args=parser.parse_args()
tracked=git('ls-files','-z').decode().split('\0') if (root/'.git').exists() else []
paths=[p for p in tracked if p] or [str(p.relative_to(root)) for p in root.rglob('*') if p.is_file() and not any(x in {'.git','.build','.build-universal','dist','work'} for x in p.relative_to(root).parts)]
for path in paths:
 p=root/path;assert not p.is_symlink(), f'Symlink: {path}';scan(path,p.read_bytes())
blobs=set()
if args.history:
 for commit in git('rev-list','--all').decode().splitlines():
  for entry in git('ls-tree','-rz',commit).split(b'\0'):
   if not entry: continue
   head,path=entry.split(b'\t',1);mode,kind,oid=head.decode().split();path=path.decode()
   assert mode in ['100644','100755'], f'Non-regular history entry: {path}'
   scan(path,git('cat-file','blob',oid));blobs.add(oid)
print(json.dumps({'files_scanned':len(paths),'history_blobs_scanned':len(blobs),'result':'passed'}))

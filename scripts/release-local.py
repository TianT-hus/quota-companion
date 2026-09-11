#!/usr/bin/env python3
"""Build only a clean local commit. No upload, install or running-app changes."""
import hashlib, json, os, plistlib, shutil, subprocess, tarfile
from pathlib import Path
root=Path(__file__).resolve().parent.parent

def run(*args,**kw): return subprocess.run(args,check=True,**kw)
def capture(*args): return subprocess.check_output(args,text=True).strip()
assert not capture('git','-C',str(root),'status','--porcelain'), 'Commit every intended public change first'
commit=capture('git','-C',str(root),'rev-parse','HEAD')
run('python3',str(root/'scripts/audit-public.py'),'--history')
info=plistlib.loads((root/'Packaging/Info.plist').read_bytes());version=info['CFBundleShortVersionString'];build=info['CFBundleVersion']
work=root/'work'/('release-'+commit[:12]); work.mkdir(parents=True,exist_ok=False)
archive=work/'source.tar';run('git','-C',str(root),'archive','--format=tar','-o',str(archive),commit)
checkout=work/'checkout';checkout.mkdir()
with tarfile.open(archive) as t: t.extractall(checkout)
run(str(checkout/'scripts/validate.sh'))
run(str(checkout/'scripts/package-app.sh'),'release')
identity=os.environ.get('DEVELOPER_ID_APPLICATION','-')
status='adhoc-test' if identity=='-' else 'developer-id-unnotarized'
name=f'quota-companion-{version}-build{build}-{status}'
out=root/'dist'/(name+'-'+commit[:12]);out.mkdir(parents=True,exist_ok=False)
app=checkout/'dist/额度水滴 Dev.app'
run('ditto','--norsrc',str(app),str(out/app.name))
app=out/app.name
helper=app/'Contents/Resources/PluginMarketplace/plugins/quota-companion/bin/quota-companion-mcp'
for binary in [app/'Contents/MacOS/额度水滴-Dev',helper]:
 run('lipo',str(binary),'-verify_arch','arm64','x86_64')
 strings=capture('strings','-a',str(binary))
 # Published machine code must not reveal the builder's personal source paths.
 assert '/Users/' not in strings and '/Volumes/' not in strings, 'Private build path embedded in binary'
run('codesign','--verify','--deep','--strict',str(app))
run('ditto','--norsrc','-c','-k','--keepParent',str(app),str(out/(name+'-macos-universal.zip')))
run('ditto','--norsrc','-c','-k','--keepParent',str(app/'Contents/Resources/PluginMarketplace'),str(out/(name+'-plugin-universal.zip')))
run('git','-C',str(root),'archive','--format=zip','--prefix=quota-companion/','-o',str(out/(name+'-source.zip')),commit)
record={'commit':commit,'version':version,'build':build,'architectures':['arm64','x86_64'],'signing':status,'notarized':False,'clean_commit_build':True,'swift':capture('swift','--version'),'xcode':capture('xcodebuild','-version')}
(out/'BUILD-INFO.json').write_text(json.dumps(record,indent=2)+'\n')
files=sorted([*out.glob('*.zip'),out/'BUILD-INFO.json'])
(out/'SHA256SUMS').write_text(''.join(hashlib.sha256(f.read_bytes()).hexdigest()+'  '+f.name+'\n' for f in files))
assert not capture('git','-C',str(root),'status','--porcelain'), 'Build modified source checkout'
print(out)

#!/usr/bin/env python3
"""Package exactly three public products from a clean reviewed commit; never install."""
import argparse,hashlib,io,json,os,plistlib,subprocess,zipfile
from pathlib import Path
from publication_guard import audit,inspect_asset,policy_for
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--product',choices=['all','v1','v2','practice'],default='all');a=p.parse_args()
audit(root)
subprocess.run(['python3','Scripts/check-public.py'],cwd=root,check=True)
subprocess.run(['python3','Scripts/check-v1-archive.py'],cwd=root,check=True)
revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
for flavor,app_name in [('v1','WKRV1'),('v2','WKRPublic'),('practice','WakaraPractice')]:
    if a.product not in ('all',flavor):continue
    subprocess.run(['./Scripts/build-app.sh'],cwd=root,env={**os.environ,'WKR_BUILD_FLAVOR':flavor,'CODESIGN_IDENTITY':'-','CONFIGURATION':'release'},check=True)
    app=root/'build'/(app_name+'.app');info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    binary=app/'Contents/MacOS'/app_name
    arch=subprocess.check_output(['/usr/bin/lipo','-archs',str(binary)],text=True).strip()
    if arch!='arm64':raise SystemExit('The initial binary release is Apple Silicon only')
    expected={f'Contents/MacOS/{app_name}','Contents/Info.plist','Contents/_CodeSignature/CodeResources','Contents/Resources/LICENSE'}
    if flavor!='v1':
        expected|={'Contents/Resources/upstream-manifest.json','Contents/Resources/Layout/layout-v2.json'}
        expected|={'Contents/Resources/Practice/'+n for n in ['index.html','style.css','data.js','core.js','engine.js','app.js','VERSION','README.md','LICENSE']}
    files={str(p.relative_to(app)):p for p in app.rglob('*') if p.is_file()}
    if set(files)!=expected or any(p.is_symlink() for p in app.rglob('*')):raise SystemExit('Unexpected app bundle contents')
    buffer=io.BytesIO()
    with zipfile.ZipFile(buffer,'w',zipfile.ZIP_DEFLATED) as z:
        for name,path in sorted(files.items()):
            header=zipfile.ZipInfo(app.name+'/'+name,(2026,9,22,0,0,0));header.compress_type=zipfile.ZIP_DEFLATED
            header.external_attr=(0o100755 if path==binary else 0o100644)<<16;z.writestr(header,path.read_bytes())
        for name,path in [('LICENSE',root/'LICENSE'),('INSTALL.md',root/'docs/distribution.md')]:
            header=zipfile.ZipInfo(name,(2026,9,22,0,0,0));header.compress_type=zipfile.ZIP_DEFLATED;header.external_attr=0o100644<<16;z.writestr(header,path.read_bytes())
    name=f'{app_name}-{info["WKRReleaseVersion"]}-arm64-adhoc.zip'
    out=root/'build/distribution'/info['WKRReleaseVersion']/revision;out.mkdir(parents=True,exist_ok=True)
    def put(path,data):
        if path.exists() and path.read_bytes()!=data:raise SystemExit('Candidate differs; refusing overwrite')
        path.write_bytes(data)
    put(out/name,buffer.getvalue());inspect_asset(out/name,policy_for(root))
    manifest={'repository':'https://github.com/yuhkis/wkr-macos','revision':revision,'product':flavor,
        'appVersion':info['WKRReleaseVersion'],'layoutVersion':info['WKRLayoutVersion'],
        'practiceVersion':info.get('WKRPracticeVersion'),'bundleIdentifier':info['CFBundleIdentifier'],
        'architecture':arch,'signing':'ad-hoc','notarized':False,'archive':name,
        'sha256':hashlib.sha256(buffer.getvalue()).hexdigest(),
        'files':{n:hashlib.sha256(p.read_bytes()).hexdigest() for n,p in files.items()}}
    put(out/'manifest.json',(json.dumps(manifest,indent=2)+'\n').encode())
    put(out/'SHA256SUMS',(manifest['sha256']+'  '+name+'\n'+hashlib.sha256((out/'manifest.json').read_bytes()).hexdigest()+'  manifest.json\n').encode())
    print(json.dumps({k:manifest[k] for k in ['product','appVersion','sha256']}))

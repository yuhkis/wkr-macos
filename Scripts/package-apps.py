#!/usr/bin/env python3
"""Package exactly three public products as disk images from a clean reviewed commit; never install or upload.

CODESIGN_IDENTITY names the project's self-signed release certificate (its name or
SHA-1; the SHA-1 is pinned in Scripts/release-certificate-leaf.sha1). Unset, the apps
and disk images are signed ad hoc: enough for CI and a rehearsal, not for a release.
"""
import argparse,hashlib,json,os,plistlib,re,shutil,subprocess,sys,tempfile,time
from pathlib import Path
from publication_guard import audit,inspect_asset,policy_for
root=Path(__file__).resolve().parents[1]
pinned_file=root/'Scripts/release-certificate-leaf.sha1'
p=argparse.ArgumentParser();p.add_argument('--product',choices=['all','v1','v2','practice'],default='all');a=p.parse_args()

def fail(reason):raise SystemExit('Package refused: '+reason)
def run(*args,**kw):return subprocess.run(list(args),check=True,**kw)
def output(*args):return subprocess.run(list(args),check=True,capture_output=True,text=True)

identity=os.environ.get('CODESIGN_IDENTITY','')
if identity=='-':identity=''
pinned=re.sub(r'[\s:]','',pinned_file.read_text()).upper()
if not re.fullmatch(r'[0-9A-F]{40}',pinned):fail(f'{pinned_file.name} does not hold one SHA-1 fingerprint')

audit(root)
run('python3','Scripts/check-public.py',cwd=root)
run('python3','Scripts/check-v1-archive.py',cwd=root)
revision=output('git','rev-parse','HEAD').stdout.strip()

def leaf_sha1(path):
    """The SHA-1 of the certificate that signed path, or None for an ad-hoc signature."""
    with tempfile.TemporaryDirectory() as directory:
        subprocess.run(['codesign','-d','--extract-certificates='+directory+'/c',str(path)],capture_output=True)
        leaf=Path(directory)/'c0'
        return hashlib.sha1(leaf.read_bytes()).hexdigest().upper() if leaf.exists() else None

def check_signature(path,kind):
    """Release: the pinned certificate is the leaf and the designated requirement; ad hoc: no certificate."""
    details=output('codesign','-d','--verbose=4',str(path)).stderr
    leaf=leaf_sha1(path)
    if not identity:
        if 'Signature=adhoc' not in details.splitlines() or leaf:fail(f'the {kind} is not signed ad hoc')
        return
    if leaf!=pinned:fail(f'the {kind} is not signed with the certificate in {pinned_file.name}')
    if kind=='app':
        if not re.search(r'flags=0x[0-9a-f]*\(.*runtime',details):fail('the app is not signed with the hardened runtime')
        signed=output('codesign','-d','-r-',str(path));requirement=signed.stdout+signed.stderr
        if f'certificate leaf = h"{pinned.lower()}"' not in requirement.lower():fail('the designated requirement does not name the release certificate')

def file_hashes(app):
    return {str(f.relative_to(app)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(app.rglob('*')) if f.is_file()}

def detach(mount):
    for _ in range(10):
        if subprocess.run(['hdiutil','detach',str(mount)],capture_output=True).returncode==0:return
        time.sleep(1)
    subprocess.run(['hdiutil','detach','-force',str(mount)],capture_output=True)

signing='release' if identity else 'adhoc'
for flavor,app_name in [('v1','WKRV1'),('v2','WKRPublic'),('practice','WakaraPractice')]:
    if a.product not in ('all',flavor):continue
    run('./Scripts/build-app.sh',cwd=root,env={**os.environ,'WKR_BUILD_FLAVOR':flavor,'CODESIGN_IDENTITY':identity or '-','CONFIGURATION':'release'})
    app=root/'build'/(app_name+'.app');info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    binary=app/'Contents/MacOS'/app_name
    arch=output('/usr/bin/lipo','-archs',str(binary)).stdout.strip()
    if arch!='arm64':fail('the initial binary release is Apple Silicon only')
    expected={f'Contents/MacOS/{app_name}','Contents/Info.plist','Contents/_CodeSignature/CodeResources','Contents/Resources/LICENSE'}
    if flavor!='v1':
        expected|={'Contents/Resources/upstream-manifest.json','Contents/Resources/Layout/layout-v2.json'}
        expected|={'Contents/Resources/Practice/'+n for n in ['index.html','style.css','data.js','core.js','engine.js','app.js','VERSION','README.md','LICENSE']}
    files=file_hashes(app)
    if set(files)!=expected or any(f.is_symlink() for f in app.rglob('*')):fail('unexpected app bundle contents')
    check_signature(app,'app')

    version=info['WKRReleaseVersion']
    # No spaces: GitHub turns a space in an asset name into a dot, which breaks `shasum -c`.
    name=f'{app_name}-{version}-arm64'+('' if identity else '-adhoc')+'.dmg'
    out=root/'build/distribution'/version/revision/signing
    if out.exists() and any(out.iterdir()):
        fail(f'{out.relative_to(root)} already holds a candidate. A disk image is not byte-for-byte reproducible, so it is never overwritten; move the old one aside first')
    out.mkdir(parents=True,exist_ok=True)
    image=out/name
    with tempfile.TemporaryDirectory() as directory:
        stage=Path(directory)/'image';stage.mkdir()
        run('ditto',str(app),str(stage/app.name))
        os.symlink('/Applications',stage/'Applications')
        shutil.copyfile(root/'LICENSE',stage/'LICENSE')
        shutil.copyfile(root/'docs/distribution.md',stage/'INSTALL.md')
        run('hdiutil','create','-quiet','-volname',app_name,'-srcfolder',str(stage),'-fs','HFS+','-format','UDZO','-imagekey','zlib-level=9',str(image))
    if identity:run('codesign','--force','--timestamp','--sign',identity,str(image))
    else:run('codesign','--force','--sign','-',str(image))
    run('codesign','--verify','--strict','--verbose=2',str(image))
    check_signature(image,'disk image')

    with tempfile.TemporaryDirectory() as directory:
        mount=Path(directory)/'mount';mount.mkdir()
        run('hdiutil','attach','-quiet','-readonly','-nobrowse','-noautoopen','-mountpoint',str(mount),str(image))
        try:
            top={e.name for e in mount.iterdir()}-{'.fseventsd','.Trashes','.HFS+ Private Directory Data\r'}
            if top!={app.name,'Applications','LICENSE','INSTALL.md'}:fail('the disk image holds more or less than the app, the Applications link, LICENSE and INSTALL.md')
            if os.readlink(mount/'Applications')!='/Applications':fail('the Applications link points elsewhere')
            mounted=mount/app.name
            if file_hashes(mounted)!=files:fail('the app in the disk image differs from the inspected build')
            run('codesign','--verify','--deep','--strict','--verbose=2',str(mounted))
            check_signature(mounted,'app')
        finally:detach(mount)
    inspect_asset(image,policy_for(root))

    data=image.read_bytes()
    manifest={'repository':'https://github.com/yuhkis/wkr-macos','revision':revision,'product':flavor,
        'appVersion':version,'layoutVersion':info['WKRLayoutVersion'],
        'practiceVersion':info.get('WKRPracticeVersion'),'bundleIdentifier':info['CFBundleIdentifier'],
        'architecture':arch,'signing':'self-signed release certificate' if identity else 'ad-hoc',
        'certificateSHA1':pinned if identity else None,'notarized':False,'archive':name,
        'sha256':hashlib.sha256(data).hexdigest(),'files':files}
    (out/'manifest.json').write_bytes((json.dumps(manifest,indent=2)+'\n').encode())
    (out/'SHA256SUMS').write_bytes((manifest['sha256']+'  '+name+'\n'+hashlib.sha256((out/'manifest.json').read_bytes()).hexdigest()+'  manifest.json\n').encode())
    run('shasum','-a','256','-c','SHA256SUMS',cwd=out)
    print(json.dumps({k:manifest[k] for k in ['product','appVersion','signing','archive','sha256']}),flush=True)
    if not identity:print('Signed ad hoc: not for distribution. Set CODESIGN_IDENTITY to the release certificate.',file=sys.stderr)

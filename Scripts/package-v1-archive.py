#!/usr/bin/env python3
"""Package the reviewed v1 source, without apps, Git history or build output."""
import hashlib,io,json,subprocess,zipfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
def git(*args):return subprocess.check_output(['git','-C',str(root),*args],text=True).strip()
assert not git('status','--porcelain'), 'Commit the reviewed source before packaging'
subprocess.run(['python3',str(root/'Scripts/check-v1-archive.py')],check=True)
revision=git('rev-parse','HEAD');base=root/'Legacy/wkr-macos-v1'
frozen=json.loads((base/'archive-source.json').read_text())
names=sorted([*frozen['files'],'archive-source.json'])
tracked=git('ls-files','Legacy/wkr-macos-v1').splitlines()
assert sorted(p.removeprefix('Legacy/wkr-macos-v1/') for p in tracked)==names
buffer=io.BytesIO()
with zipfile.ZipFile(buffer,'w',zipfile.ZIP_DEFLATED) as z:
    for name in names:
        entry=zipfile.ZipInfo(name,(2026,9,21,0,0,0));entry.compress_type=zipfile.ZIP_DEFLATED
        entry.external_attr=(0o100755 if name.endswith('.sh') else 0o100644)<<16
        z.writestr(entry,(base/name).read_bytes())
archive='WKR-macOS-0.7.0-archive.1-source.zip'
metadata={'archiveVersion':'0.7.0-archive.1','basedOnAppVersion':'0.7.0','layoutVersion':'1.1.0',
          'layoutTag':'v1.1.0-archive.1','revision':revision,'files':{name:hashlib.sha256((base/name).read_bytes()).hexdigest() for name in names}}
payload={archive:buffer.getvalue(),'manifest.json':(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n').encode()}
payload['SHA256SUMS']=''.join(hashlib.sha256(data).hexdigest()+'  '+name+'\n' for name,data in payload.items()).encode()
out=root/'build/distribution/0.7.0-archive.1'/revision;out.mkdir(parents=True,exist_ok=True)
for name,data in payload.items():
    path=out/name
    if path.exists():assert path.read_bytes()==data, 'Refuse to overwrite a different artifact'
    else:path.write_bytes(data)
print(json.dumps({'revision':revision,'files':len(names),'sha256':{name:hashlib.sha256(data).hexdigest() for name,data in payload.items()}},indent=2))

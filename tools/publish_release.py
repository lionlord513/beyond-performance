"""Validate an already tested release; publish only with explicit --publish.

No credential is printed or written to disk. Uses an existing GH_TOKEN /
GITHUB_TOKEN or Git Credential Manager entry, with interactive prompts disabled.
The GitHub connector lacks repository creation and release upload operations.
"""
from pathlib import Path
import argparse, hashlib, json, os, re, subprocess, sys, urllib.error, urllib.parse, urllib.request, zipfile

ROOT=Path(__file__).resolve().parents[1]
REPOSITORY='lionlord513/beyond-performance'
REMOTE='https://github.com/'+REPOSITORY+'.git'

def sha(path):
    with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def git(*args):
    env={**os.environ,'GIT_TERMINAL_PROMPT':'0','GCM_INTERACTIVE':'Never'}
    result=subprocess.run(['git','-C',str(ROOT),*args],capture_output=True,text=True,env=env)
    if result.returncode:raise RuntimeError('Git operation failed: '+result.stderr.strip())
    return result.stdout.strip()

def validate(output):
    meta=json.loads((ROOT/'mod/BeyondPerformance/bmm.json').read_text(encoding='utf-8-sig'))
    version=meta['Version'];assert re.fullmatch(r'\d+\.\d+\.\d+',version),'Invalid version'
    assert meta['Update']['Repository']==REPOSITORY,'Wrong repository in package metadata'
    main=(ROOT/'mod/BeyondPerformance/Scripts/main.lua').read_text(encoding='utf-8-sig')
    assert re.search(r"\bversion\s*=\s*['\"]"+re.escape(version)+r"['\"]",main),'Runtime and release version differ'
    names=[f'BeyondPerformance-{version}-{kind}.zip' for kind in ('standalone','mod-only','source')]
    files=[output/name for name in names]+[output/'bmm-mod.json',output/'SHA256SUMS.txt']
    assert all(p.is_file() and not p.is_symlink() for p in files),'Release artifacts missing or linked'
    receipt=json.loads((output/'validation.json').read_text())
    required={'lua54','native-ownership','installer-fixtures','bmm-1.0.8-roundtrip'}
    assert receipt['version']==version and required<=set(receipt['checks']),'Required artifact checks not recorded'
    assert all(receipt['sha256'].get(p.name)==sha(p) for p in files),'An artifact changed after validation'
    manifest=json.loads(files[3].read_text())
    assert manifest['version']==version and manifest['asset']==names[0],'Feed selects another package'
    assert manifest['sha256']==sha(files[0]) and manifest['size']==files[0].stat().st_size,'Feed digest/size mismatch'
    expected_url=f'https://github.com/{REPOSITORY}/releases/download/v{version}/{names[0]}'
    assert manifest['url']==expected_url,'Feed URL mismatch'
    sums=dict((name,digest) for digest,name in (line.split(maxsplit=1) for line in files[4].read_text().splitlines()))
    assert all(sums.get(p.name)==sha(p) for p in files[:3]),'Release checksum mismatch'
    payloads=[]
    for path in files[:2]:
        with zipfile.ZipFile(path) as z:
            assert z.testzip() is None,'Corrupt archive'
            packaged=json.loads(z.read('BeyondPerformance/bmm.json'))
            assert packaged==meta,'Package/source metadata differ'
            records=json.loads(z.read('package-manifest.json'))['modFiles']
            payload={entry['path']:entry['sha256'] for entry in records}
            for entry in records:
                data=z.read('BeyondPerformance/'+entry['path'])
                assert hashlib.sha256(data).hexdigest()==entry['sha256'] and len(data)==entry['bytes'],'Bad package member'
                if entry['path']!='bmm.json':
                    assert (ROOT/'mod/BeyondPerformance'/entry['path']).read_bytes()==data,'Packaged code differs from reviewed source'
            payloads.append(payload)
    assert payloads[0]==payloads[1],'Standalone and mod-only mod payloads differ'
    with zipfile.ZipFile(files[2]) as z:
        assert z.testzip() is None,'Corrupt source archive'
        for name in z.namelist():
            if name.endswith('/'):continue
            local=(ROOT/name).resolve()
            assert local.is_relative_to(ROOT.resolve()),'Unsafe source archive path'
            assert local.is_file() and local.read_bytes()==z.read(name),'Source archive is stale: '+name
    return version,files,manifest

def credential():
    token=os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
    if token:return token
    env={**os.environ,'GIT_TERMINAL_PROMPT':'0','GCM_INTERACTIVE':'Never'}
    result=subprocess.run(['git','credential','fill'],input='protocol=https\nhost=github.com\n\n',
        capture_output=True,text=True,env=env)
    if result.returncode:raise RuntimeError('No existing GitHub credential available; no interactive login was opened.')
    fields=dict(line.split('=',1) for line in result.stdout.splitlines() if '=' in line)
    if not fields.get('password'):raise RuntimeError('GitHub credential is unavailable.')
    return fields['password']

def request(token,path,method='GET',data=None,binary=False):
    url=path if path.startswith('https://uploads.github.com/') else 'https://api.github.com'+path
    headers={'Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28',
        'User-Agent':'BeyondPerformance-Release','Authorization':'Bearer '+token}
    body=data if binary else (json.dumps(data).encode() if data is not None else None)
    if body is not None:headers['Content-Type']='application/octet-stream' if binary else 'application/json'
    try:
        with urllib.request.urlopen(urllib.request.Request(url,data=body,headers=headers,method=method),timeout=120) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code==404 and method=='GET':return None
        # Never include request headers or credential helper output in an exception.
        raise RuntimeError(f'GitHub {method} failed with HTTP {error.code}: {path.split("?")[0]}') from None

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--artifacts',type=Path,required=True)
    ap.add_argument('--publish',action='store_true',help='Create public repository if absent, push clean main, upload and publish release')
    ap.add_argument('--manager',type=Path,help='Actual BMM executable, required when publishing for anonymous post-release verification')
    a=ap.parse_args();output=a.artifacts.resolve()
    version,files,manifest=validate(output)
    print(json.dumps({'repository':REPOSITORY,'version':version,'files':[{ 'name':p.name,'bytes':p.stat().st_size,'sha256':sha(p)} for p in files]},indent=2))
    if not a.publish:
        print('Validation only. No repository, branch, tag, or release was changed.');return
    if not a.manager or not a.manager.is_file():ap.error('--manager must name the tested BMM executable when publishing')
    if git('rev-parse','--show-toplevel').replace('\\','/').lower()!=ROOT.as_posix().lower():raise RuntimeError('Use a dedicated Git repository rooted at this project.')
    if git('status','--porcelain'):raise RuntimeError('Commit the reviewed source before publishing; working tree must be clean.')
    if git('branch','--show-current')!='main':raise RuntimeError('Publish only a reviewed main branch.')
    head=git('rev-parse','HEAD')
    token=credential()
    if request(token,'/user').get('login')!='lionlord513':raise RuntimeError('Authenticated account differs from intended repository owner.')
    repo=request(token,'/repos/'+REPOSITORY)
    if repo is None:
        repo=request(token,'/user/repos','POST',{'name':'beyond-performance','private':False,
            'description':'Standalone performance controls and measurements for Drive Beyond Horizons.','auto_init':False})
    if repo.get('private') or repo.get('archived'):raise RuntimeError('BMM anonymous updates require the intended active public repository.')
    if request(token,f'/repos/{REPOSITORY}/releases/tags/v{version}') is not None:raise RuntimeError('Release already exists; never overwrite a published version.')
    remotes=git('remote').splitlines()
    if 'origin' in remotes:
        if git('remote','get-url','origin')!=REMOTE:raise RuntimeError('Existing origin points at another repository.')
    else:git('remote','add','origin',REMOTE)
    git('push','-u','origin','HEAD:main')
    notes='\n'.join(manifest['notes'])+'\n\nInstall with the included PowerShell installer or use Add mod ZIP in Beyond Mod Manager.\n\nSee README.md and MEASUREMENTS.md for test conditions and limitations.'
    release=request(token,f'/repos/{REPOSITORY}/releases','POST',{'tag_name':'v'+version,'target_commitish':head,
        'name':'Beyond Performance '+version,'body':notes,'draft':True,'prerelease':False})
    upload=release['upload_url'].split('{')[0]
    for file in files:
        asset=request(token,upload+'?name='+urllib.parse.quote(file.name),'POST',file.read_bytes(),True)
        if asset.get('size')!=file.stat().st_size or asset.get('digest')!='sha256:'+sha(file):
            raise RuntimeError('Uploaded digest/size mismatch; release remains a draft for inspection.')
        print('Verified upload:',file.name)
    published=request(token,f'/repos/{REPOSITORY}/releases/{release["id"]}','PATCH',{'draft':False,'make_latest':'true'})
    print('Published:',published['html_url'])
    # This invokes the shipped manager update code with NO token or authenticated HTTP.
    env={k:v for k,v in os.environ.items() if k not in ('GH_TOKEN','GITHUB_TOKEN')}
    subprocess.run([sys.executable,str(ROOT/'tests/test_bmm.py'),'--manager',str(a.manager.resolve()),
        '--artifacts',str(output),'--online'],check=True,env=env)

if __name__=='__main__':main()

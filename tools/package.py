"""Build Beyond Performance packages using Python's standard library only.

Example: python tools/package.py --runtime-source <game/Binaries/Win64> --output <outputs>
Use --mod-only for an existing UE4SS installation, --stage-only to inspect without
creating a ZIP, and --source-zip to also archive this project's source.
"""
from pathlib import Path
import argparse, datetime, hashlib, json, os, re, shutil, zipfile

ROOT=Path(__file__).resolve().parents[1]
RUNTIME_FILES=('dwmapi.dll','ue4ss/UE4SS.dll','ue4ss/UE4SS-settings.ini','ue4ss/LICENSE')
EXPECTED_RUNTIME={
    'dwmapi.dll':'0c407a52fd6666a0cea61035878a4f637ea19882b44634e33f4a9a4a45a98ebe',
    'ue4ss/UE4SS.dll':'e14657eec1c3fb08d1d0e4d5b24f69a9343cd06359e1af27ae6c9c84c5f010cf',
}

def sha(path):
    with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def put(path,text):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(text,encoding='utf-8',newline='\n')

def copy_file(origin,target):
    if origin.is_symlink():raise ValueError(f'Linked source is unsupported: {origin}')
    target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(origin,target)

def source_files(root):
    for p in sorted(root.rglob('*')):
        if p.is_symlink():raise ValueError(f'Linked source is unsupported: {p}')
        if p.is_file():yield p

def sanitized_runtime_settings(path):
    section='';lines=[]
    forced={('overrides','modsfolderpath'):'',('overrides','controllingmodstxt'):'',('debug','consoleenabled'):'0',('debug','guiconsoleenabled'):'0',('debug','guiconsolevisible'):'0',('general','enableautoreloadingluamods'):'0',('objectdumper','loadallassetsbeforedumpingobjects'):'0',('cxxheadergenerator','loadallassetsbeforegeneratingcxxheaders'):'0'}
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        heading=re.match(r'^\s*\[([^]]+)\]',line)
        if heading:section=heading.group(1).lower()
        setting=re.match(r'^\s*([+\-\w]+)\s*=',line)
        if setting:
            key=setting.group(1).lower()
            if section=='overrides' and key.lstrip('+-')=='modsfolderpaths':continue
            if (section,key) in forced:line=setting.group(1)+' = '+forced[section,key]
        lines.append(line)
    return '\n'.join(lines)+'\n'

def package_mod(source,stage,version):
    records=[]
    for p in source_files(source):
        rel=p.relative_to(source).as_posix()
        # Persistent machine state and runtime captures never enter releases.
        if rel.startswith(('state/','captures/','benchmarks/')) or p.name.startswith('benchmark-') or p.name in {'settings.ini','settings.ini.bak','settings.ini.tmp','.beyond-performance-install.json'}:continue
        if p.suffix.lower() in {'.pdb','.tmp','.log','.dmp','.pyc','.lib','.exp','.obj','.exe'} or '__pycache__' in p.parts:continue
        if rel=='bmm.json':continue # Write one version-matched manifest below.
        target=stage/'BeyondPerformance'/rel;copy_file(p,target)
        records.append({'path':rel,'sha256':sha(target),'bytes':target.stat().st_size})
    marker=stage/'BeyondPerformance/enabled.txt'
    if not marker.exists():put(marker,'')
    if not any(r['path']=='enabled.txt' for r in records):records.append({'path':'enabled.txt','sha256':sha(marker),'bytes':0})
    meta=json.loads((ROOT/'mod/BeyondPerformance/bmm.json').read_text(encoding='utf-8-sig'))
    meta['Version']=version
    target=stage/'BeyondPerformance/bmm.json';put(target,json.dumps(meta,indent=2)+'\n')
    records.append({'path':'bmm.json','sha256':sha(target),'bytes':target.stat().st_size})
    if not (stage/'BeyondPerformance/Scripts/main.lua').is_file():raise ValueError('Mod entry point Scripts/main.lua is missing; finish the source before packaging.')
    if (stage/'BeyondPerformance/Scripts/attachments.lua').is_file() and not (stage/'BeyondPerformance/native/BeyondPerformanceNative.dll').is_file():raise ValueError('Build native/BeyondPerformanceNative.dll with build-native.ps1 before packaging.')
    return sorted(records,key=lambda r:r['path'])

def release_metadata(out,version):
    """BMM reads release assets anonymously; every selected ZIP is hash/size bound."""
    asset=out/f'BeyondPerformance-{version}-standalone.zip'
    if asset.is_file():
        with zipfile.ZipFile(asset) as z:
            meta=json.loads(z.read('BeyondPerformance/bmm.json'))
        repo=meta['Update']['Repository']
        manifest={'schema':1,'version':version,'released':datetime.date.today().isoformat(),
            'channel':meta['Channel'],'origin':'GitHub','asset':asset.name,
            'size':asset.stat().st_size,'sha256':sha(asset),
            'url':f'https://github.com/{repo}/releases/download/v{version}/{asset.name}',
            'notes':[meta['Changelog']]}
        put(out/'bmm-mod.json',json.dumps(manifest,indent=2)+'\n')
    archives=sorted(out.glob(f'BeyondPerformance-{version}-*.zip'))
    put(out/'SHA256SUMS.txt',''.join(f'{sha(p)}  {p.name}\n' for p in archives))

def archive(stage,destination):
    if destination.exists():raise FileExistsError(destination)
    temp=destination.with_suffix('.zip.tmp')
    with zipfile.ZipFile(temp,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for p in source_files(stage):z.write(p,p.relative_to(stage).as_posix())
    with zipfile.ZipFile(temp) as z:
        if z.testzip():raise ValueError('ZIP integrity failed')
        if len(z.namelist())!=len(set(n.casefold() for n in z.namelist())):raise ValueError('Duplicate ZIP path')
    temp.replace(destination)

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--version',default='1.1.0')
    ap.add_argument('--output',type=Path,default=ROOT/'build')
    ap.add_argument('--runtime-source',type=Path,default=Path(os.environ.get('ProgramFiles(x86)',r'C:\Program Files (x86)'))/'Steam/steamapps/common/Drive Beyond Horizons/DriveBeyondHorizons/Binaries/Win64')
    ap.add_argument('--mod-source',type=Path,default=ROOT/'mod/BeyondPerformance')
    ap.add_argument('--mod-only',action='store_true')
    ap.add_argument('--stage-only',action='store_true')
    ap.add_argument('--source-zip',action='store_true')
    a=ap.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+',a.version):ap.error('Version must be numeric MAJOR.MINOR.PATCH for BMM updates')
    out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
    name=f'BeyondPerformance-{a.version}-'+('mod-only' if a.mod_only else 'standalone')
    stage=out/name
    if stage.exists():raise FileExistsError(f'Staging folder already exists: {stage}; choose a new output directory')
    stage.mkdir()
    modfiles=package_mod(a.mod_source.resolve(),stage,a.version)
    for name_script in ('Install.ps1','Uninstall.ps1','Common.ps1'):copy_file(ROOT/'tools'/name_script,stage/name_script)
    for doc in ('README.md','README.txt','MEASUREMENTS.md','MEASUREMENTS.txt','CHANGELOG.md','INSTALLATION.txt','LICENSE.txt'):
        if (ROOT/doc).is_file():copy_file(ROOT/doc,stage/doc)
    if (ROOT/'docs').is_dir():
        for p in source_files(ROOT/'docs'):copy_file(p,stage/'docs'/p.relative_to(ROOT/'docs'))
    runtime=[]
    if not a.mod_only:
        for rel in RUNTIME_FILES:
            origin=a.runtime_source/rel
            if not origin.is_file():raise FileNotFoundError(f'Tested runtime file missing: {origin}')
            if rel in EXPECTED_RUNTIME and sha(origin)!=EXPECTED_RUNTIME[rel]:raise ValueError(f'Runtime fingerprint differs from tested UE4SS 8f7b2ca3: {origin}')
            target=stage/'Runtime'/rel
            if rel=='ue4ss/UE4SS-settings.ini':put(target,sanitized_runtime_settings(origin))
            else:copy_file(origin,target)
            runtime.append({'path':rel,'sha256':sha(target),'bytes':target.stat().st_size})
        license_text=(stage/'Runtime/ue4ss/LICENSE').read_text(encoding='utf-8-sig')
        if 'MIT License' not in license_text or 'Copyright (c) 2022 Narknon' not in license_text:raise ValueError('Expected UE4SS redistribution license absent')
        copy_file(stage/'Runtime/ue4ss/LICENSE',stage/'UE4SS-LICENSE.txt')
    notice='''THIRD-PARTY RUNTIME NOTICE

Beyond Performance is independent of Beyond Apocalypse, Beyond Tuning,
Beyond Detours, MixTape Maker and every other gameplay mod. UE4SS is its
shared mod loader, not a dependency on any of those mods.

The standalone package contains the tested, unmodified installed UE4SS
loader pair: UE4SS v3.0.1 Beta #0, Git SHA 8f7b2ca3, Win64 shipping build.
Its new-install settings remove machine-specific mod paths, disable debug
consoles and automatic Lua reloading, and leave asset-dump preloading off.
The mod-only package contains no loader binaries. The source project is
UE4SS-RE/RE-UE4SS: https://github.com/UE4SS-RE/RE-UE4SS
The package does not claim to reproduce the upstream binary build.

UE4SS and its bundled proxy are distributed with the accompanying MIT
license, Copyright (c) 2022 Narknon, copied verbatim into UE4SS-LICENSE.txt
and Runtime/ue4ss/LICENSE when the runtime is bundled. SHA256 fingerprints
are listed in package-manifest.json and SHA256SUMS.txt.

Existing loader files and UE4SS settings are never overwritten by the
installer. Missing files are installed only from the checked bundle.
No game executable, PDB, game content, save data, or other mod is included.
'''
    put(stage/'RUNTIME-NOTICE.txt',notice)
    manifest={'schema':1,'product':'BeyondPerformance','version':a.version,'gameBuildTested':'26437602','runtimeTested':'UE4SS 3.0.1 Beta #0 / Git 8f7b2ca3','modFiles':modfiles,'runtimeFiles':runtime}
    put(stage/'package-manifest.json',json.dumps(manifest,indent=2)+'\n')
    put(stage/'SHA256SUMS.txt',''.join(f'{sha(p)}  {p.relative_to(stage).as_posix()}\n' for p in source_files(stage)))
    if a.stage_only:print(f'Staged: {stage}');return
    destination=out/(name+'.zip');archive(stage,destination)
    print(f'{destination}\nSHA256 {sha(destination)}')
    if a.source_zip:
        src=out/f'BeyondPerformance-{a.version}-source'
        if src.exists():raise FileExistsError(src)
        src.mkdir()
        for folder in ('mod','tools','tests','native','docs'):
            if not (ROOT/folder).exists():continue
            for p in source_files(ROOT/folder):
                rel=p.relative_to(ROOT)
                if '__pycache__' in rel.parts or p.suffix.lower() in {'.pyc','.pdb','.log','.dmp','.obj','.lib','.exp','.exe'}:continue
                if 'state' in rel.parts or p.name.startswith('benchmark-') or p.name in {'settings.ini','settings.ini.bak','settings.ini.tmp'}:continue
                copy_file(p,src/rel)
        for doc in ('README.md','README.txt','MEASUREMENTS.md','MEASUREMENTS.txt','CHANGELOG.md','INSTALLATION.txt','LICENSE.txt'):
            if (ROOT/doc).is_file():copy_file(ROOT/doc,src/doc)
        if (ROOT/'build-native.ps1').is_file():copy_file(ROOT/'build-native.ps1',src/'build-native.ps1')
        source_zip=out/f'BeyondPerformance-{a.version}-source.zip';archive(src,source_zip)
        print(f'{source_zip}\nSHA256 {sha(source_zip)}')
    release_metadata(out,a.version)

if __name__=='__main__':main()

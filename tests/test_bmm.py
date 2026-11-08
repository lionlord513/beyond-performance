"""Exercise a real BMM executable's public API using disposable, non-game fixtures."""
from pathlib import Path
import argparse, json, os, shutil, subprocess, sys, tempfile

ROOT=Path(__file__).resolve().parents[1]

def run(args):
    p=subprocess.run([str(x) for x in args],capture_output=True,text=True)
    if p.returncode:raise RuntimeError(p.stdout+p.stderr)
    return p.stdout

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--manager',type=Path,required=True,help='Shipped Beyond Mod Manager.exe (tested 1.0.8)')
    ap.add_argument('--artifacts',type=Path,help='Existing final package directory, otherwise build current source')
    ap.add_argument('--online',action='store_true',help='After publication, verify anonymous discovery/download/install too')
    a=ap.parse_args()
    # BMM targets .NET Framework with MAX_PATH limits; fixture journals need room.
    work=Path(tempfile.mkdtemp(prefix='bp-bmm-'))
    version=json.loads((ROOT/'mod/BeyondPerformance/bmm.json').read_text())['Version']
    output=a.artifacts.resolve() if a.artifacts else work/'packages'
    if not a.artifacts:
        for extra in ([],['--mod-only']):
            print(run([sys.executable,ROOT/'tools/package.py','--version',version,'--output',output]+extra),end='')
    oldsource=work/'old/BeyondPerformance';(oldsource/'Scripts').mkdir(parents=True)
    (oldsource/'Scripts/main.lua').write_text('-- old fixture; never executed\n')
    (oldsource/'Scripts/obsolete.lua').write_text('-- old fixture code\n')
    run([sys.executable,ROOT/'tools/package.py','--version','1.0.0','--mod-only','--mod-source',oldsource,'--output',work/'oldpackage'])
    manager=work/'Beyond Mod Manager.exe';shutil.copy2(a.manager.resolve(),manager)
    csc=Path(os.environ.get('WINDIR',r'C:\Windows'))/'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    exe=work/'BmmRoundtrip.exe'
    run([csc,'/nologo','/target:exe','/optimize+','/out:'+str(exe),'/reference:'+str(manager),
         '/reference:System.Web.Extensions.dll',ROOT/'tests/BmmRoundtrip.cs'])
    args=[exe,work/'fixtures',output/f'BeyondPerformance-{version}-standalone.zip',output/f'BeyondPerformance-{version}-mod-only.zip',
          work/'oldpackage/BeyondPerformance-1.0.0-mod-only.zip',output/'bmm-mod.json',output/'SHA256SUMS.txt']
    if a.online:args.append('--online')
    result=run(args);print(result,end='')
    (work/'results.txt').write_text(result,encoding='utf-8')
    evidence=ROOT/'work/bmm-results.txt';evidence.parent.mkdir(exist_ok=True)
    evidence.write_text('Fixture: '+str(work)+'\n'+result,encoding='utf-8')
    print('Evidence:',work/'results.txt')

if __name__=='__main__':main()

"""Exercise installers only in disposable fixtures; never launch the game."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,sys,uuid

ROOT=Path(__file__).resolve().parents[1]
RUN=ROOT.parent/'it'/uuid.uuid4().hex[:4]
PS=shutil.which(os.environ.get('BP_TEST_SHELL','powershell.exe')) or shutil.which('pwsh')
assert PS,'PowerShell unavailable'
RUN.mkdir(parents=True)
source=RUN/'fixture source/BeyondPerformance';(source/'Scripts').mkdir(parents=True)
(source/'Scripts/main.lua').write_text('return {version="installer-fixture"}\n')
(source/'native').mkdir(parents=True);(source/'native/BeyondPerformanceNative.dll').write_bytes(b'fixture never executed')
results=[]

def build(out,modonly=False):
    args=[sys.executable,str(ROOT/'tools/package.py'),'--mod-source',str(source),'--output',str(RUN/out),'--stage-only']
    if modonly:args.append('--mod-only')
    p=subprocess.run(args,capture_output=True,text=True)
    assert p.returncode==0,p.stdout+p.stderr
    return next((RUN/out).glob('BeyondPerformance-*'))

games=0
def game(name):
    global games
    games+=1
    root=RUN/f'g {games}';binary=root/'DriveBeyondHorizons/Binaries/Win64';binary.mkdir(parents=True)
    (binary/'DriveBeyondHorizons-Win64-Shipping.exe').write_bytes(b'fixture, not executable')
    return root,binary

def run(package,script,root,good=True):
    p=subprocess.run([PS,'-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(package/script),'-GamePath',str(root)],capture_output=True,text=True)
    if good:assert p.returncode==0,p.stdout+p.stderr
    else:assert p.returncode!=0,'Expected refusal: '+p.stdout+p.stderr
    return p.stdout+p.stderr

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def tree(root):return {p.relative_to(root).as_posix():digest(p) for p in root.rglob('*') if p.is_file()}
def record(name):results.append({'test':name,'passed':True});print('PASS',name,flush=True)

standalone=build('standalone package with spaces')
modonly=build('mod only package',True)

root,binary=game('Fresh Game with spaces')
run(standalone,'Install.ps1',root)
mod=binary/'ue4ss/Mods/BeyondPerformance'
assert (mod/'Scripts/main.lua').read_bytes()==(source/'Scripts/main.lua').read_bytes()
assert (mod/'enabled.txt').is_file() and (binary/'dwmapi.dll').is_file() and (binary/'ue4ss/UE4SS.dll').is_file()
assert not (binary/'ue4ss/Mods/mods.txt').exists()
record('fresh standalone installation into path containing spaces')

# Upgrade the same fixture; prove persistent files and every non-owned file stay byte-exact.
(mod/'settings.ini').write_text('shadowBudget=false\n')
(mod/'benchmark-personal.csv').write_text('private capture\n')
(mod/'state').mkdir();(mod/'state/user.json').write_text('{"keep":true}')
(mod/'Scripts/stale.lua').write_text('old code')
(mod/'assets').mkdir();(mod/'assets/obsolete.txt').write_text('old asset')
(mod/'native/obsolete.dll').write_text('old binary')
(mod/'Scripts/main.lua').write_text('old main')
other=binary/'ue4ss/Mods/Other Mod';other.mkdir();(other/'keep.lua').write_text('do not change')
listfile=binary/'ue4ss/Mods/mods.txt';listfile.write_text('Other Mod : 1\nBeyondPerformance : 1\n')
settings=binary/'ue4ss/UE4SS-settings.ini';settings.write_text('[Overrides]\nModsFolderPath =\nControllingModsTxt =\n; sentinel\n')
unchanged={p:digest(p) for p in [binary/'dwmapi.dll',binary/'ue4ss/UE4SS.dll',listfile,settings,other/'keep.lua']}
run(standalone,'Install.ps1',root)
assert (mod/'settings.ini').read_text()=='shadowBudget=false\n'
assert (mod/'benchmark-personal.csv').read_text()=='private capture\n'
assert (mod/'state/user.json').read_text()=='{"keep":true}'
assert not (mod/'Scripts/stale.lua').exists() and not (mod/'assets/obsolete.txt').exists() and not (mod/'native/obsolete.dll').exists()
assert all(digest(p)==h for p,h in unchanged.items())
backups=list((binary/'BeyondPerformance-backups').glob('install-*/BeyondPerformance'))
assert len(backups)==1 and (backups[0]/'Scripts/stale.lua').read_text()=='old code'
record('upgrade preserves settings/captures/other mods/loader/mod list; backs up old code')

run(standalone,'Uninstall.ps1',root)
assert not mod.exists() and all(digest(p)==h for p,h in unchanged.items())
uninstalls=list((binary/'BeyondPerformance-backups').glob('uninstall-*/BeyondPerformance'))
assert len(uninstalls)==1 and (uninstalls[0]/'settings.ini').read_text()=='shadowBudget=false\n'
record('uninstall removes only active own folder and retains backup/settings/shared loader')

root2,binary2=game('Missing loader')
before=tree(binary2);run(modonly,'Install.ps1',root2,False);assert tree(binary2)==before
record('mod-only refuses missing loader before writes')

root3,binary3=game('Existing custom loader')
(binary3/'ue4ss/Mods').mkdir(parents=True)
(binary3/'dwmapi.dll').write_bytes(b'existing proxy')
(binary3/'ue4ss/UE4SS.dll').write_bytes(b'existing loader')
(binary3/'ue4ss/UE4SS-settings.ini').write_text('[Debug]\nConsoleEnabled=0\n')
(binary3/'ue4ss/Mods/mods.txt').write_text('MyMod : 1\n')
before=tree(binary3);run(modonly,'Install.ps1',root3)
assert all(digest(binary3/p)==h for p,h in before.items())
record('mod-only preserves existing unknown loader and mod list byte-for-byte')

root4,binary4=game('Incomplete different runtime')
(binary4/'dwmapi.dll').write_bytes(b'unknown half pair')
before=tree(binary4);run(standalone,'Install.ps1',root4,False);assert tree(binary4)==before
record('incomplete mismatched runtime refused before writes')

root5,binary5=game('Tampered package target')
tampered=standalone/'BeyondPerformance/Scripts/main.lua';original=tampered.read_bytes()
try:
    tampered.write_bytes(b'tampered')
    before=tree(binary5);run(standalone,'Install.ps1',root5,False);assert tree(binary5)==before
finally:tampered.write_bytes(original)
record('package corruption refused before writes')

root6,binary6=game('Explicit disable')
(binary6/'ue4ss/Mods').mkdir(parents=True);(binary6/'ue4ss/Mods/mods.txt').write_text('BeyondPerformance : 0\n')
before=tree(binary6);run(standalone,'Install.ps1',root6,False);assert tree(binary6)==before
record('explicit disabled mod-list entry retained; no silent activation')

root7,binary7=game('Custom configured loader path')
(binary7/'ue4ss').mkdir();(binary7/'ue4ss/UE4SS-settings.ini').write_text('[Overrides]\nModsFolderPath = D:/CustomMods\n')
before=tree(binary7);run(standalone,'Install.ps1',root7,False);assert tree(binary7)==before
record('custom loader destination refused before writing to wrong mod folder')

# Read-only running-process guard check against the active real installation.
guard=RUN/'check-running-guard.ps1'
guard.write_text("param([string]$Common)\n. $Common\n$layout=Get-GameLayout ''\ntry { Assert-GameStopped $layout; Write-Host 'NO_RUNNING_INSTANCE'; exit 3 } catch { if ($_.Exception.Message -match 'Close Drive Beyond Horizons') { Write-Host 'REFUSED_RUNNING'; exit 0 }; throw }\n")
p=subprocess.run([PS,'-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(guard),'-Common',str(standalone/'Common.ps1')],capture_output=True,text=True)
if p.returncode==0 and 'REFUSED_RUNNING' in p.stdout:record('running selected game refused using read-only process inspection')
elif p.returncode==3:results.append({'test':'running selected game refusal','passed':None,'reason':'No running selected game at time of test'})
else:raise AssertionError(p.stdout+p.stderr)

(RUN/'results.json').write_text(json.dumps({'fixture_root':str(RUN),'tests':results},indent=2))
print('RESULTS',RUN/'results.json',flush=True)

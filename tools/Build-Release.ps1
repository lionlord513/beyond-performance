param(
 [string]$Python='python', [string]$Zig='zig', [string]$LupaPath='',
 [Parameter(Mandatory)][string]$Manager,
 [string]$RuntimeSource='', [string]$Output=''
)
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
$metadata=Get-Content -LiteralPath (Join-Path $project 'mod\BeyondPerformance\bmm.json') -Raw | ConvertFrom-Json
$version=[string]$metadata.Version
if(-not $Output){$Output=Join-Path $project "build\$version"}
$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a new output directory so old artifacts cannot enter the release.'}
function Tool([string]$Exe,[string[]]$Arguments){& $Exe @Arguments;if($LASTEXITCODE){throw "$Exe failed with exit code $LASTEXITCODE"}}
Push-Location $project
try {
 Tool 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',"$project\build-native.ps1",'-Zig',$Zig)
 $luaArgs=@("$project\tests\run.py");if($LupaPath){$luaArgs+=@('--lupa-path',$LupaPath)}
 Tool $Python $luaArgs
 $scratch=Join-Path $project ('work\release-tests-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
 New-Item -ItemType Directory -Path $scratch | Out-Null
 Tool $Zig @('cc','-target','x86_64-windows-gnu','-O2','-Wall','-Wextra',"$project\native\test_attachments.c",'-o',"$scratch\native-tests.exe")
 Tool "$scratch\native-tests.exe" @("$scratch\native-fixture")
 Tool $Python @("$project\tools\test_install.py")
 $package=@("$project\tools\package.py",'--version',$version,'--output',$Output)
 if($RuntimeSource){$package+=@('--runtime-source',$RuntimeSource)}
 Tool $Python ($package+@('--source-zip'))
 Tool $Python ($package+@('--mod-only'))
 Tool $Python @("$project\tests\test_bmm.py",'--manager',$Manager,'--artifacts',$Output)
 $hashes=@{};Get-ChildItem -LiteralPath $Output -File | Where-Object {$_.Extension -eq '.zip' -or $_.Name -in @('bmm-mod.json','SHA256SUMS.txt')} | ForEach-Object {$hashes[$_.Name]=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
 $receipt=@{version=$version;createdUtc=[DateTime]::UtcNow.ToString('o');checks=@('lua54','native-ownership','installer-fixtures','bmm-1.0.8-roundtrip');managerSha256=(Get-FileHash -LiteralPath $Manager).Hash.ToLowerInvariant();sha256=$hashes}
 [IO.File]::WriteAllText((Join-Path $Output 'validation.json'),($receipt|ConvertTo-Json -Depth 4)+[Environment]::NewLine)
 Write-Output "Validated release artifacts: $Output"
 Write-Output 'Publication is a separate explicit invocation of tools/publish_release.py --publish.'
} finally {Pop-Location}

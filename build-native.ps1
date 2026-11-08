param([string]$Zig='zig')
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
 New-Item -ItemType Directory -Force 'mod\BeyondPerformance\native' | Out-Null
 & $Zig cc -target x86_64-windows-gnu -O2 -Wall -Wextra -shared native/attachments.c -o mod/BeyondPerformance/native/BeyondPerformanceNative.dll
 if($LASTEXITCODE -ne 0){throw 'Beyond Performance native build failed'}
 Get-FileHash -Algorithm SHA256 -LiteralPath 'mod\BeyondPerformance\native\BeyondPerformanceNative.dll'
} finally {Pop-Location}

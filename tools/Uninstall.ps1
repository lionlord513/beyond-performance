[CmdletBinding()]
param([string]$GamePath)
. (Join-Path $PSScriptRoot 'Common.ps1')
$layout = Get-GameLayout $GamePath
Assert-GameStopped $layout
if (-not (Test-Path -LiteralPath $layout.Mod)) { Write-Host 'Beyond Performance is not installed in this game folder.'; exit 0 }
Assert-NoLinks $layout.Mod -Recurse
$transaction = New-BackupPath $layout 'uninstall'
$source = Assert-Within $layout.Mod $layout.Mods
$backup = Assert-Within (Join-Path $transaction 'BeyondPerformance') $transaction
Assert-GameStopped $layout
Move-Item -LiteralPath $source -Destination $backup
Write-Host 'Beyond Performance removed from the active Mods folder.'
Write-Host "Its settings, benchmarks and code remain backed up at $backup"
Write-Host 'The shared loader, mods.txt, other mods, native settings and saves were not changed.'

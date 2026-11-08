Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Within([string]$Path, [string]$Root) {
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes intended folder: $full" }
    return $full
}

function Assert-NoLinks([string]$Path, [switch]$Recurse) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked folders/files are not supported by this installer: $Path" }
    if ($Recurse -and $item.PSIsContainer) {
        foreach ($child in Get-ChildItem -LiteralPath $Path -Force -Recurse) {
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked folders/files are not supported: $($child.FullName)" }
        }
    }
}

function Get-GameLayout([string]$GamePath) {
    if ([string]::IsNullOrWhiteSpace($GamePath)) { $GamePath = Join-Path ${env:ProgramFiles(x86)} 'Steam\steamapps\common\Drive Beyond Horizons' }
    $root = [IO.Path]::GetFullPath($GamePath).TrimEnd('\')
    $bin = Join-Path $root 'DriveBeyondHorizons\Binaries\Win64'
    if (Test-Path -LiteralPath (Join-Path $root 'DriveBeyondHorizons-Win64-Shipping.exe') -PathType Leaf) { $bin = $root }
    $exe = Join-Path $bin 'DriveBeyondHorizons-Win64-Shipping.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'GamePath must be the Drive Beyond Horizons game folder (or its Binaries\Win64 folder).' }
    $cursor = Get-Item -LiteralPath $bin -Force
    while ($null -ne $cursor) {
        if ($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked game path is unsupported: $($cursor.FullName)" }
        $cursor = $cursor.Parent
    }
    $ue = Join-Path $bin 'ue4ss'; $mods = Join-Path $ue 'Mods'
    foreach ($dir in @($ue, $mods)) { Assert-NoLinks $dir }
    return @{ Root=$root; Bin=$bin; Exe=$exe; Ue=$ue; Mods=$mods; Mod=(Join-Path $mods 'BeyondPerformance'); Backups=(Join-Path $bin 'BeyondPerformance-backups') }
}

function Assert-GameStopped($Layout) {
    foreach ($process in @(Get-Process -Name 'DriveBeyondHorizons-Win64-Shipping','DriveBeyondHorizons' -ErrorAction SilentlyContinue)) {
        try { $path = $process.Path } catch { throw 'Cannot inspect a running DBH process. Close every DBH instance before installing.' }
        if ([string]::IsNullOrWhiteSpace($path)) { throw 'Cannot inspect a running DBH process. Close every DBH instance before installing.' }
        $full = [IO.Path]::GetFullPath($path)
        $selected = [IO.Path]::GetFullPath($Layout.Exe)
        $wrapper = Join-Path $Layout.Root 'DriveBeyondHorizons.exe'
        if ($full.Equals($selected,[StringComparison]::OrdinalIgnoreCase) -or $full.Equals($wrapper,[StringComparison]::OrdinalIgnoreCase)) {
            throw "Close Drive Beyond Horizons before changing this installation (PID $($process.Id))."
        }
    }
}

function Get-SafeChild([string]$Root,[string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or $Relative -match '(^[/\\]|:|[\x00-\x1f])') { throw 'Invalid package relative path.' }
    foreach ($part in ($Relative -split '[/\\]')) {
        if ($part -eq '' -or $part -eq '.' -or $part -eq '..') { throw 'Invalid package relative path.' }
    }
    return Assert-Within (Join-Path $Root $Relative) $Root
}

function File-Hash([string]$Path) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-','').ToLowerInvariant() }
    finally { $stream.Dispose(); $algorithm.Dispose() }
}

function Assert-LoaderLayout($Layout) {
    $settings = Join-Path $Layout.Ue 'UE4SS-settings.ini'
    if (Test-Path -LiteralPath $settings -PathType Leaf) {
        Assert-NoLinks $settings
        foreach ($line in Get-Content -LiteralPath $settings) {
            if ($line -match '^\s*(ModsFolderPath|ControllingModsTxt)\s*=\s*([^;\s].*)$') {
                throw 'A custom UE4SS mod folder/list is configured. Use the documented manual install into that configured folder; no settings were changed.'
            }
        }
    }
    $list = Join-Path $Layout.Mods 'mods.txt'
    if (Test-Path -LiteralPath $list -PathType Leaf) {
        Assert-NoLinks $list
        $state = $null
        foreach ($line in Get-Content -LiteralPath $list) { if ($line -match '^\s*BeyondPerformance\s*:\s*([01])') { $state = $Matches[1] } }
        if ($state -eq '0') { throw 'mods.txt explicitly disables BeyondPerformance. Enable its existing entry yourself before installing; this installer never changes mods.txt.' }
    }
}

function New-BackupPath($Layout,[string]$Kind) {
    Assert-NoLinks $Layout.Backups
    [IO.Directory]::CreateDirectory($Layout.Backups) | Out-Null
    $name = $Kind + '-' + (Get-Date -Format 'yyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,4)
    $path = Assert-Within (Join-Path $Layout.Backups $name) $Layout.Backups
    [IO.Directory]::CreateDirectory($path) | Out-Null
    return $path
}

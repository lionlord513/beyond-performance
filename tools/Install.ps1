[CmdletBinding()]
param([string]$GamePath)
. (Join-Path $PSScriptRoot 'Common.ps1')

$layout = Get-GameLayout $GamePath
Assert-GameStopped $layout
Assert-LoaderLayout $layout
Assert-NoLinks $layout.Mod -Recurse
$source = Join-Path $PSScriptRoot 'BeyondPerformance'
$runtime = Join-Path $PSScriptRoot 'Runtime'
$manifestPath = Join-Path $PSScriptRoot 'package-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Extract the complete package before running Install.ps1.' }
Assert-NoLinks $source -Recurse
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.product -ne 'BeyondPerformance' -or $manifest.schema -ne 1) { throw 'Unsupported package manifest.' }
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($file in $manifest.modFiles) {
    $path = Get-SafeChild $source $file.path
    if (-not $seen.Add([string]$file.path)) { throw 'Duplicate package path.' }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (File-Hash $path) -ne $file.sha256) { throw "Package integrity check failed: $($file.path)" }
}
if (-not $seen.Contains('Scripts/main.lua') -or -not $seen.Contains('enabled.txt')) { throw 'Package lacks its entry point or enable marker.' }

# Inspect all runtime requirements before making any game-directory writes.
$needed = @(); $existingCore = @{}
foreach ($relative in @('dwmapi.dll','ue4ss/UE4SS.dll')) {
    $target = Get-SafeChild $layout.Bin $relative
    Assert-NoLinks $target
    $existingCore[$relative] = Test-Path -LiteralPath $target -PathType Leaf
}
if (-not $existingCore['ue4ss/UE4SS.dll'] -and (Test-Path -LiteralPath (Join-Path $layout.Bin 'UE4SS.dll'))) { throw 'An alternate UE4SS layout exists. Install the mod manually into its configured Mods folder.' }
foreach ($file in $manifest.runtimeFiles) {
    $origin = Get-SafeChild $runtime $file.path
    $target = Get-SafeChild $layout.Bin $file.path
    Assert-NoLinks $origin; Assert-NoLinks $target
    if (-not (Test-Path -LiteralPath $origin -PathType Leaf) -or (File-Hash $origin) -ne $file.sha256) { throw "Runtime package integrity check failed: $($file.path)" }
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { $needed += @{Source=$origin; Target=$target; Hash=$file.sha256} }
}
if ($manifest.runtimeFiles.Count -eq 0 -and (-not $existingCore['dwmapi.dll'] -or -not $existingCore['ue4ss/UE4SS.dll'])) { throw 'UE4SS is missing. Use the standalone package, or install the tested UE4SS loader first.' }
if ($existingCore['dwmapi.dll'] -xor $existingCore['ue4ss/UE4SS.dll']) {
    foreach ($file in $manifest.runtimeFiles) {
        if ($existingCore.ContainsKey($file.path) -and $existingCore[$file.path] -and (File-Hash (Get-SafeChild $layout.Bin $file.path)) -ne $file.sha256) {
            throw 'An incomplete, different loader already exists. It was left untouched; repair that runtime before installing this mod.'
        }
    }
}
foreach ($file in $manifest.runtimeFiles) {
    if ($existingCore.ContainsKey($file.path) -and $existingCore[$file.path] -and (File-Hash (Get-SafeChild $layout.Bin $file.path)) -ne $file.sha256) {
        Write-Warning 'Existing UE4SS differs from the tested bundle. It will be preserved; check the startup log for Beyond Performance compatibility.'
        break
    }
}

$transaction = New-BackupPath $layout 'install'
$stage = Assert-Within (Join-Path $transaction 'new') $transaction
$backup = Assert-Within (Join-Path $transaction 'BeyondPerformance') $transaction
[IO.Directory]::CreateDirectory($stage) | Out-Null
$movedOld = $false; $committed = $false; $createdRuntime = @()
try {
    # Retain own preferences, benchmarks and other data, while replacing owned
    # code directories in the staged copy. No sibling mod is read or modified.
    if (Test-Path -LiteralPath $layout.Mod -PathType Container) {
        foreach ($item in Get-ChildItem -LiteralPath $layout.Mod -Force) { Copy-Item -LiteralPath $item.FullName -Destination $stage -Recurse -Force }
        foreach ($owned in @('Scripts','assets','native','dlls','bin')) {
            $oldCode = Assert-Within (Join-Path $stage $owned) $stage
            if (Test-Path -LiteralPath $oldCode) { Assert-NoLinks $oldCode -Recurse; Remove-Item -LiteralPath $oldCode -Recurse -Force }
        }
    }
    foreach ($file in $manifest.modFiles) {
        $origin = Get-SafeChild $source $file.path; $target = Get-SafeChild $stage $file.path
        $retain = $file.path -match '^(state|config|captures|benchmarks)/' -or $file.path -match '^[^/]+\.(ini|cfg)(\.(bak|tmp))?$' -or $file.path -match '^benchmark-'
        if ($retain -and (Test-Path -LiteralPath $target -PathType Leaf)) { continue }
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
        [IO.File]::Copy($origin,$target,$true)
    }
    [IO.File]::WriteAllText((Join-Path $stage '.beyond-performance-install.json'), ($manifest | ConvertTo-Json -Depth 8))
    Assert-GameStopped $layout
    foreach ($file in $needed) {
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($file.Target)) | Out-Null
        if (-not (Test-Path -LiteralPath $file.Target)) {
            [IO.File]::Copy($file.Source,$file.Target,$false); $createdRuntime += $file
        }
    }
    [IO.Directory]::CreateDirectory($layout.Mods) | Out-Null
    $checkedMod = Assert-Within $layout.Mod $layout.Mods
    if (Test-Path -LiteralPath $checkedMod) { Assert-NoLinks $checkedMod -Recurse; Move-Item -LiteralPath $checkedMod -Destination $backup; $movedOld = $true }
    Move-Item -LiteralPath $stage -Destination $checkedMod
    $committed = $true
    Write-Host "Installed Beyond Performance $($manifest.version) at $checkedMod"
    if ($movedOld) { Write-Host "Previous Beyond Performance, including settings, backed up at $backup" }
    Write-Host 'Start the game, load gameplay, then press F10. Other mods, mods.txt, existing loader/settings and game saves were not changed.'
} catch {
    $failure = $_
    if (-not $committed) {
        if ($movedOld -and -not (Test-Path -LiteralPath $layout.Mod)) { Move-Item -LiteralPath $backup -Destination (Assert-Within $layout.Mod $layout.Mods) }
        foreach ($file in $createdRuntime) {
            if ((Test-Path -LiteralPath $file.Target -PathType Leaf) -and (File-Hash $file.Target) -eq $file.Hash) { Remove-Item -LiteralPath (Assert-Within $file.Target $layout.Bin) -Force }
        }
    }
    throw $failure
}

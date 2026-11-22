[CmdletBinding()]
param(
    [ValidateSet('Release', 'Dev')]
    [string]$Mode = 'Release'
)

$ErrorActionPreference = 'Stop'
$addonName = 'ProvisionsRestock'
$manifestName = "$addonName.toc"
$manifest = Join-Path $PSScriptRoot $manifestName
$manifestLines = Get-Content -LiteralPath $manifest
$runtime = @($manifestLines | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') })
$expected = @('Data.lua', 'Merchant.lua', 'Planner.lua', 'UI.lua', "$addonName.lua")
if ($runtime.Count -ne $expected.Count -or (Compare-Object $expected $runtime -CaseSensitive)) {
    throw "$manifestName must contain the five public Lua files."
}
foreach ($file in $runtime) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file) -PathType Leaf)) {
        throw "Missing runtime file $file."
    }
}

function New-BuildDirectory {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $directory = Get-Item -LiteralPath $Path -Force
        if (-not $directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Expected a local build directory at $Path."
        }
    } else {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Assert-LocalBuildFile {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $file = Get-Item -LiteralPath $Path -Force
        if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Expected a local build file at $Path."
        }
    }
}

$output = Join-Path $PSScriptRoot 'build'
New-BuildDirectory $output

if ($Mode -eq 'Dev') {
    $devRoot = Join-Path $output 'Dev'
    $stage = Join-Path $devRoot $addonName
    New-BuildDirectory $devRoot
    New-BuildDirectory $stage
    $devFiles = $runtime + 'DevProfiles.lua'
    $expectedStage = $devFiles + $manifestName
    $extra = @(Get-ChildItem -LiteralPath $stage -Force | Where-Object { $_.Name -cnotin $expectedStage })
    if ($extra.Count -gt 0) {
        throw "Unexpected files in $stage. Move them out before rebuilding."
    }
    foreach ($file in $expectedStage) {
        Assert-LocalBuildFile (Join-Path $stage $file)
    }
    foreach ($file in $devFiles) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $stage $file) -Force
    }

    $devManifest = @($manifestLines | ForEach-Object {
        if ($_ -match '^## Title:') { "$_ (Dev)" } else { $_ }
    }) + 'DevProfiles.lua'
    [IO.File]::WriteAllLines((Join-Path $stage $manifestName), [string[]]$devManifest)
    Write-Output $stage
    return
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = Join-Path $output "$addonName.zip"
Assert-LocalBuildFile $archive
$temporary = Join-Path $output ("$addonName-{0}.tmp" -f [guid]::NewGuid().ToString('N'))
try {
    $zip = [IO.Compression.ZipFile]::Open($temporary, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in @($manifestName) + $runtime) {
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, (Join-Path $PSScriptRoot $file), "$addonName/$file"
            ) | Out-Null
        }
    } finally {
        $zip.Dispose()
    }
    Move-Item -LiteralPath $temporary -Destination $archive -Force
} finally {
    if (Test-Path -LiteralPath $temporary) {
        Remove-Item -LiteralPath $temporary -Force
    }
}
Write-Output $archive

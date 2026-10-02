#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'AIArtToPSD.dproj')) -or
    -not (Test-Path -LiteralPath (Join-Path $repoRoot 'Source') -PathType Container)) {
    throw 'Run this tool from the AIArtToPSD project.'
}

function Assert-WorkspacePath([string]$Path) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the workspace: $fullPath"
    }
    # Check ancestors too, so a junction cannot redirect a deletion elsewhere.
    $ancestor = $fullPath
    while ($ancestor.Length -ge $repoRoot.Length) {
        $item = Get-Item -LiteralPath $ancestor -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Linked paths are excluded from cleanup: $ancestor"
        }
        if ($ancestor -eq $repoRoot) { break }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
}

$relativePaths = @('Tests\output', 'Analysis\results\previews',
    'Analysis\results\samples.json', 'AIArtToPSD.rsm', 'AIArtToPSD.map', 'AIArtToPSD.tds')
foreach ($parent in @('', 'Tests', 'Tools')) {
    foreach ($build in @('Win32', 'Win64', 'Debug', 'Release')) {
        $relativePaths += if ($parent) { Join-Path $parent $build } else { $build }
    }
}
foreach ($parent in @('Analysis', 'Source', 'Sample', 'Tests', 'Tools')) {
    $base = Join-Path $repoRoot $parent
    if (Test-Path -LiteralPath $base -PathType Container) {
        Assert-WorkspacePath $base
        $relativePaths += @(Get-ChildItem -LiteralPath $base -Directory -Recurse -Force |
            Where-Object Name -EQ '__pycache__' |
            ForEach-Object { [IO.Path]::GetRelativePath($repoRoot, $_.FullName) })
    }
}
foreach ($parent in @('Tests', 'Tools')) {
    $base = Join-Path $repoRoot $parent
    if (Test-Path -LiteralPath $base -PathType Container) {
        $relativePaths += @(Get-ChildItem -LiteralPath $base -File -Filter '*.res' |
            ForEach-Object { [IO.Path]::GetRelativePath($repoRoot, $_.FullName) })
    }
}
$exchange = Join-Path $repoRoot 'Exchange'
if (Test-Path -LiteralPath $exchange -PathType Container) {
    Assert-WorkspacePath $exchange
    $relativePaths += @(Get-ChildItem -LiteralPath $exchange -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'cancelled') -PathType Leaf } |
        ForEach-Object { [IO.Path]::GetRelativePath($repoRoot, $_.FullName) })
}

# Validate every target before deleting any; omit children of another target.
$targets = [Collections.Generic.List[object]]::new()
foreach ($relative in ($relativePaths | Sort-Object -Unique | Sort-Object Length)) {
    $fullPath = [IO.Path]::GetFullPath((Join-Path $repoRoot $relative))
    if (-not (Test-Path -LiteralPath $fullPath)) { continue }
    if (@($targets | Where-Object {
        $fullPath.StartsWith($_.FullPath + '\', [StringComparison]::OrdinalIgnoreCase)
    }).Count) { continue }
    Assert-WorkspacePath $fullPath
    $item = Get-Item -LiteralPath $fullPath -Force
    $contents = if ($item.PSIsContainer) {
        @(Get-ChildItem -LiteralPath $fullPath -Recurse -Force)
    } else { @($item) }
    if (@($contents | Where-Object {
        $_.Attributes -band [IO.FileAttributes]::ReparsePoint
    }).Count) { throw "Linked path in cleanup target: $fullPath" }
    $files = @($contents | Where-Object { -not $_.PSIsContainer })
    $targets.Add([PSCustomObject]@{
        Path = $relative
        Files = $files.Count
        Bytes = ($files | Measure-Object Length -Sum).Sum
        FullPath = $fullPath
        IsDirectory = $item.PSIsContainer
    })
}

$targets | Select-Object Path, Files, @{Name='MiB'; Expression={ [Math]::Round($_.Bytes / 1MB, 2) }}
$totalFiles = ($targets | Measure-Object Files -Sum).Sum
$totalMiB = [Math]::Round(($targets | Measure-Object Bytes -Sum).Sum / 1MB, 2)
Write-Host "Candidates: $totalFiles files, $totalMiB MiB."
if (-not $Apply) {
    Write-Host 'Preview only. Use -Apply to delete these generated files.'
    return
}
foreach ($target in $targets) {
    Assert-WorkspacePath $target.FullPath
    if ($target.Path.StartsWith('Exchange\', [StringComparison]::OrdinalIgnoreCase) -and
        -not (Test-Path -LiteralPath (Join-Path $target.FullPath 'cancelled') -PathType Leaf)) {
        throw "Job is no longer cancelled: $($target.Path)"
    }
    if ($PSCmdlet.ShouldProcess($target.FullPath, 'Delete generated work files')) {
        if ($target.IsDirectory) {
            Remove-Item -LiteralPath $target.FullPath -Recurse -Force
        } else {
            Remove-Item -LiteralPath $target.FullPath -Force
        }
    }
}

# PowerShell 7. Source-specific, lossless split using application sourceBounds.
$ErrorActionPreference = 'Stop'
$jobDirectory = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path 'Exchange/{837E50DB-FAB5-4BC8-80F6-892098A2A079}'
$request = Get-Content -LiteralPath (Join-Path $jobDirectory 'request.json') -Raw | ConvertFrom-Json
if (Test-Path -LiteralPath (Join-Path $jobDirectory 'result.json')) { throw 'Result already exists' }
$base = @($request.layers | Where-Object name -eq 'ベース（目・眉・口消去済み）')
if ($base.Count -ne 1 -or -not $base[0].visible -or $base[0].hasMask) { throw 'Unexpected base layer' }
$base = $base[0]
if ($base.opacity -ne 255 -or $base.bounds.left -ne 0 -or $base.bounds.top -ne 0 -or $base.bounds.right -ne 1024 -or $base.bounds.bottom -ne 1536) { throw 'Unexpected geometry or opacity' }
$source = @($request.assets | Where-Object assetId -eq $base.assetId)
if ($source.Count -ne 1 -or $source[0].sha256 -ne 'd45b63fe4fd85a55a43e08877090617705aafc325e86182f66f4b275d15824b6') { throw 'Reviewed source differs' }
$source = $source[0]
$inputPath = Join-Path $jobDirectory $source.path
if ((Get-FileHash -LiteralPath $inputPath).Hash.ToLowerInvariant() -ne $source.sha256) { throw 'Input hash mismatch' }
Copy-Item -LiteralPath $inputPath -Destination (Join-Path $jobDirectory 'images/base_source.png')
$asset = @{assetId='base-split-source';path='images/base_source.png';sha256=$source.sha256;width=1024;height=1536;pixelFormat='RGBA8';colorSpace='sRGB'}
$groupId = [guid]::NewGuid().ToString('B')
$operations = @(
    @{op='add_group';layerId=$groupId;parentId=$base.parentId;beforeLayerId=$base.layerId;name='頭部・体分離（原寸・確認用）';visible=$true;opacity=255}
)
foreach ($part in @(
    @{name='頭部ベース（髪・顔・首上部）';top=0;bottom=274},
    @{name='体（首下部・衣装・手足）';top=274;bottom=1536}
)) {
    $rect = @{left=0;top=$part.top;right=1024;bottom=$part.bottom}
    $operations += @{op='add_layer';layerId=[guid]::NewGuid().ToString('B');parentId=$groupId;beforeLayerId='';name=$part.name;visible=$true;opacity=255;assetId=$asset.assetId;sourceBounds=$rect;bounds=$rect;trimTransparent=$true}
}
$operations += @{op='set_attributes';layerId=$base.layerId;visible=$false;opacity=$base.opacity}
$result = [ordered]@{schemaVersion=$request.schemaVersion;requestId=$request.requestId;jobId=$request.jobId;documentId=$request.documentId;ifRevision=$request.ifRevision;assets=@($asset);operations=$operations}
$json = $result | ConvertTo-Json -Depth 16
$json | Set-Content -LiteralPath (Join-Path $jobDirectory 'result.json.tmp') -Encoding utf8
Move-Item -LiteralPath (Join-Path $jobDirectory 'result.json.tmp') -Destination (Join-Path $jobDirectory 'result.json')
$json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'result.json') -Encoding utf8
Write-Output 'Prepared 2 original-scale image layers and 1 group; original base will be hidden.'

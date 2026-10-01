# PowerShell 7. Import one generated body pose after visual comparison.
$ErrorActionPreference = 'Stop'
$export = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'export.json') -Raw | ConvertFrom-Json
$directory = $export.data.directory
$request = Get-Content -LiteralPath (Join-Path $directory 'request.json') -Raw | ConvertFrom-Json
if (Test-Path -LiteralPath (Join-Path $directory 'result.json')) { throw 'Result exists' }
$body = @($request.layers | Where-Object name -eq '体（首下部・衣装・手足）')
if ($body.Count -ne 1 -or -not $body[0].visible -or $body[0].hasMask -or $body[0].opacity -ne 255) { throw 'Unexpected body' }
$body = $body[0]
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'body_pose_generated.png') -Destination (Join-Path $directory 'images/body_pose_generated.png')
$asset = @{assetId='body-pose-01';path='images/body_pose_generated.png';sha256=(Get-FileHash -LiteralPath (Join-Path $directory 'images/body_pose_generated.png')).Hash.ToLowerInvariant();width=1097;height=1434;pixelFormat='RGBA8';colorSpace='sRGB'}
$operations = @(
    @{op='add_layer';layerId=[guid]::NewGuid().ToString('B');parentId=$body.parentId;beforeLayerId=$body.layerId;name='体差分01（画面左手を腰に・確認用）';visible=$true;opacity=255;assetId=$asset.assetId;bounds=@{left=67;top=274;right=1012;bottom=1510};resample=$true;trimTransparent=$true},
    @{op='set_attributes';layerId=$body.layerId;visible=$false;opacity=$body.opacity}
)
$result = [ordered]@{schemaVersion=$request.schemaVersion;requestId=$request.requestId;jobId=$request.jobId;documentId=$request.documentId;ifRevision=$request.ifRevision;assets=@($asset);operations=$operations}
$json = $result | ConvertTo-Json -Depth 16
$json | Set-Content -LiteralPath (Join-Path $directory 'result.json.tmp') -Encoding utf8
Move-Item -LiteralPath (Join-Path $directory 'result.json.tmp') -Destination (Join-Path $directory 'result.json')
$json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'result.json') -Encoding utf8
Write-Output 'Prepared one body variant. Head and existing facial layers are untouched.'

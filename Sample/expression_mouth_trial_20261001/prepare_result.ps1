# PowerShell 7. App crops, resamples and places the generated expression.
$ErrorActionPreference='Stop'
$export=Get-Content (Join-Path $PSScriptRoot 'export.json') -Raw|ConvertFrom-Json
$directory=$export.data.directory
$request=Get-Content (Join-Path $directory 'request.json') -Raw|ConvertFrom-Json
if(Test-Path (Join-Path $directory 'result.json')){throw 'Result exists'}
$mouth=@($request.layers|Where-Object name -eq '口（元画素）')
if($mouth.Count -ne 1){throw 'Expected one original mouth'}
$file=Join-Path $directory 'images/mouth_open_generated.png'
Copy-Item (Join-Path $PSScriptRoot 'mouth_open_generated.png') $file
$asset=@{assetId='mouth-open';path='images/mouth_open_generated.png';width=1774;height=887;sha256=(Get-FileHash $file).Hash.ToLowerInvariant();pixelFormat='RGBA8';colorSpace='sRGB'}
$operations=@(
    @{op='set_attributes';layerId=$mouth[0].layerId;visible=$false;opacity=$mouth[0].opacity},
    @{op='add_layer';layerId=[guid]::NewGuid().ToString('B');parentId=$mouth[0].parentId;beforeLayerId=$mouth[0].layerId;name='口差分（少し開く・試験）';visible=$true;opacity=255;assetId=$asset.assetId;resample=$true;trimTransparent=$true;sourceBounds=@{left=668;top=372;right=1106;bottom=529};bounds=@{left=496;top=218;right=529;bottom=230}}
)
$result=[ordered]@{schemaVersion=1;requestId=$request.requestId;jobId=$request.jobId;documentId=$request.documentId;ifRevision=$request.ifRevision;assets=@($asset);operations=$operations}
$json=$result|ConvertTo-Json -Depth 12
$json|Set-Content (Join-Path $directory 'result.json.tmp') -Encoding utf8
Move-Item (Join-Path $directory 'result.json.tmp') (Join-Path $directory 'result.json')
$json|Set-Content (Join-Path $PSScriptRoot 'result.json') -Encoding utf8

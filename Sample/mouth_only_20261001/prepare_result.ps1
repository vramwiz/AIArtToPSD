$ErrorActionPreference='Stop'
$export=Get-Content (Join-Path $PSScriptRoot 'export.json') -Raw|ConvertFrom-Json
$directory=$export.data.directory
$request=Get-Content (Join-Path $directory 'request.json') -Raw|ConvertFrom-Json
if(Test-Path (Join-Path $directory 'result.json')){throw 'Result exists'}
$mouth=@($request.layers|Where-Object name -eq '口（元画素）')
if($mouth.Count -ne 1){throw 'Expected one mouth layer'}
if($mouth[0].bounds.left -ne 495 -or $mouth[0].bounds.top -ne 215 -or $mouth[0].bounds.right -ne 540 -or $mouth[0].bounds.bottom -ne 232){throw 'Mouth position changed'}
$file=Join-Path $directory 'images/mouth_only.png'
Copy-Item (Join-Path $PSScriptRoot 'mouth_only.png') $file
$asset=@{assetId='mouth-only';path='images/mouth_only.png';width=45;height=17;sha256=(Get-FileHash $file).Hash.ToLowerInvariant();pixelFormat='RGBA8';colorSpace='sRGB'}
$result=[ordered]@{schemaVersion=1;requestId=$request.requestId;jobId=$request.jobId;documentId=$request.documentId;ifRevision=$request.ifRevision;assets=@($asset);operations=@(@{op='replace_layer';layerId=$mouth[0].layerId;assetId=$asset.assetId;bounds=$mouth[0].bounds})}
$json=$result|ConvertTo-Json -Depth 12
$json|Set-Content (Join-Path $directory 'result.json.tmp') -Encoding utf8
Move-Item (Join-Path $directory 'result.json.tmp') (Join-Path $directory 'result.json')
$json|Set-Content (Join-Path $PSScriptRoot 'result.json') -Encoding utf8

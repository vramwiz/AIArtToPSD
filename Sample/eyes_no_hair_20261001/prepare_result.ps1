$ErrorActionPreference='Stop'
$export=Get-Content (Join-Path $PSScriptRoot 'export.json') -Raw|ConvertFrom-Json
$directory=$export.data.directory
$request=Get-Content (Join-Path $directory 'request.json') -Raw|ConvertFrom-Json
if(Test-Path (Join-Path $directory 'result.json')){throw 'Result exists'}
$eye=@($request.layers|Where-Object name -eq '目（両目・元画素）')
if($eye.Count -ne 1){throw 'Expected one paired-eye layer'}
if($eye[0].bounds.left -ne 439 -or $eye[0].bounds.top -ne 153 -or $eye[0].bounds.right -ne 572 -or $eye[0].bounds.bottom -ne 199){throw 'Eye position changed'}
$file=Join-Path $directory 'images/eyes_no_hair.png'
Copy-Item (Join-Path $PSScriptRoot 'eyes_no_hair.png') $file
$asset=@{assetId='eyes-no-hair';path='images/eyes_no_hair.png';width=133;height=46;sha256=(Get-FileHash $file).Hash.ToLowerInvariant();pixelFormat='RGBA8';colorSpace='sRGB'}
$result=[ordered]@{schemaVersion=1;requestId=$request.requestId;jobId=$request.jobId;documentId=$request.documentId;ifRevision=$request.ifRevision;assets=@($asset);operations=@(@{op='replace_layer';layerId=$eye[0].layerId;assetId=$asset.assetId;bounds=$eye[0].bounds})}
$json=$result|ConvertTo-Json -Depth 12
$json|Set-Content (Join-Path $directory 'result.json.tmp') -Encoding utf8
Move-Item (Join-Path $directory 'result.json.tmp') (Join-Path $directory 'result.json')
$json|Set-Content (Join-Path $PSScriptRoot 'result.json') -Encoding utf8

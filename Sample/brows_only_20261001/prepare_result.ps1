$ErrorActionPreference='Stop'
$export=Get-Content (Join-Path $PSScriptRoot 'export.json') -Raw|ConvertFrom-Json
$directory=$export.data.directory
$request=Get-Content (Join-Path $directory 'request.json') -Raw|ConvertFrom-Json
if(Test-Path (Join-Path $directory 'result.json')){throw 'Result exists'}
$eye=@($request.layers|Where-Object name -eq '眉（両眉・元画素）')
if($eye.Count -ne 1){throw 'Expected one paired-brow layer'}
if($eye[0].bounds.left -ne 449 -or $eye[0].bounds.top -ne 134 -or $eye[0].bounds.right -ne 558 -or $eye[0].bounds.bottom -ne 153){throw 'Brow position changed'}
$file=Join-Path $directory 'images/brows_only.png'
Copy-Item (Join-Path $PSScriptRoot 'brows_only.png') $file
$asset=@{assetId='brows-only';path='images/brows_only.png';width=109;height=19;sha256=(Get-FileHash $file).Hash.ToLowerInvariant();pixelFormat='RGBA8';colorSpace='sRGB'}
$result=[ordered]@{schemaVersion=1;requestId=$request.requestId;jobId=$request.jobId;documentId=$request.documentId;ifRevision=$request.ifRevision;assets=@($asset);operations=@(@{op='replace_layer';layerId=$eye[0].layerId;assetId=$asset.assetId;bounds=$eye[0].bounds})}
$json=$result|ConvertTo-Json -Depth 12
$json|Set-Content (Join-Path $directory 'result.json.tmp') -Encoding utf8
Move-Item (Join-Path $directory 'result.json.tmp') (Join-Path $directory 'result.json')
$json|Set-Content (Join-Path $PSScriptRoot 'result.json') -Encoding utf8

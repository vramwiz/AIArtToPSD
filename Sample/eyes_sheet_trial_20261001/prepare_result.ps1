# PowerShell 7. Recorded trial, not a reusable manifest for other documents.
$ErrorActionPreference='Stop'
$export=Get-Content (Join-Path $PSScriptRoot 'export.json') -Raw|ConvertFrom-Json
$directory=$export.data.directory
$request=Get-Content (Join-Path $directory 'request.json') -Raw|ConvertFrom-Json
if(Test-Path (Join-Path $directory 'result.json')){throw 'Result exists'}
$previous=@($request.layers|Where-Object name -eq '目（両目・元画素）')
if($previous.Count -ne 1 -or -not $previous[0].visible){throw 'Expected one visible original eye pair'}
$measurements=Get-Content (Join-Path $PSScriptRoot 'measurements.json') -Raw|ConvertFrom-Json
if($measurements.Count -ne 6){throw 'Expected six paired-eye cells'}
$file=Join-Path $directory 'images/eyes_sheet.png'
Copy-Item (Join-Path $PSScriptRoot 'eyes_sheet.png') $file
$asset=@{assetId='eyes-sheet';path='images/eyes_sheet.png';width=1536;height=1024;sha256=(Get-FileHash $file).Hash.ToLowerInvariant();pixelFormat='RGBA8';colorSpace='sRGB'}
$groupId=[guid]::NewGuid().ToString('B')
$operations=@(
    @{op='set_attributes';layerId=$previous[0].layerId;visible=$false;opacity=$previous[0].opacity},
    @{op='add_group';layerId=$groupId;parentId=$previous[0].parentId;beforeLayerId=$previous[0].layerId;name='目差分6種（両目・確認用）';visible=$true;opacity=255}
)
foreach($m in $measurements){
    $operations+=@{op='add_layer';layerId=[guid]::NewGuid().ToString('B');parentId=$groupId;beforeLayerId='';name=('{0:00} {1}' -f ($m.index+1),$m.label);visible=($m.index -eq 1);opacity=255;assetId=$asset.assetId;sourceBounds=$m.sourceBounds;bounds=$m.bounds;resample=$true;trimTransparent=$true}
}
$result=[ordered]@{schemaVersion=$request.schemaVersion;requestId=$request.requestId;jobId=$request.jobId;documentId=$request.documentId;ifRevision=$request.ifRevision;assets=@($asset);operations=$operations}
$json=$result|ConvertTo-Json -Depth 12
$json|Set-Content (Join-Path $directory 'result.json.tmp') -Encoding utf8
Move-Item (Join-Path $directory 'result.json.tmp') (Join-Path $directory 'result.json')
$json|Set-Content (Join-Path $PSScriptRoot 'result.json') -Encoding utf8

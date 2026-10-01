# Only prepares the exchange manifest. The app copies/crops the original pixels.
$ErrorActionPreference='Stop'
$directory=(Get-Content (Join-Path $PSScriptRoot 'exchange/job-directory.txt') -Raw).Trim()
$request=Get-Content (Join-Path $directory 'request.json') -Raw|ConvertFrom-Json
if(Test-Path (Join-Path $directory 'result.json')){throw 'Result already issued'}
$source=@($request.assets|Where-Object assetId -eq 'source-1')[0]
if((Get-FileHash (Join-Path $PSScriptRoot '../character_neutral.png')).Hash -ne '58ECE460E16D10BEBA67AA0B239C6E7075200C73DD6AFDAC6135F6C9BB1FFF07'){throw 'Source differs from reviewed image'}
$basePath=Join-Path $directory 'images/base.png'
Copy-Item (Join-Path $PSScriptRoot '../ai_separation_check_20261001/base_no_glow_v2.png') $basePath
$base=@{assetId='skin-base';path='images/base.png';width=1024;height=1536;sha256=(Get-FileHash $basePath).Hash.ToLowerInvariant();pixelFormat='RGBA8';colorSpace='sRGB'}
$group=[guid]::NewGuid().ToString('B')
$original=$request.layers[0].layerId
$ops=@(
    @{op='set_attributes';layerId=$original;visible=$false;opacity=255},
    @{op='rename_layer';layerId=$original;name='元画像（比較用）'},
    @{op='add_group';layerId=$group;parentId='';beforeLayerId=$original;name='矩形分離（元画素・拡縮なし）';visible=$true;opacity=255}
)
$parts=@(
    @{name='目（両目・元画素）';left=439;top=153;right=572;bottom=199},
    @{name='眉（両眉・元画素）';left=449;top=134;right=558;bottom=153},
    @{name='口（元画素）';left=495;top=215;right=540;bottom=232}
)
foreach($part in $parts){
    $bounds=@{left=$part.left;top=$part.top;right=$part.right;bottom=$part.bottom}
    $ops+=@{op='add_layer';layerId=[guid]::NewGuid().ToString('B');parentId=$group;beforeLayerId='';name=$part.name;visible=$true;opacity=255;assetId=$source.assetId;sourceBounds=$bounds;bounds=$bounds}
}
$ops+=@{op='add_layer';layerId=[guid]::NewGuid().ToString('B');parentId=$group;beforeLayerId='';name='ベース（目・眉・口消去済み）';visible=$true;opacity=255;assetId='skin-base';bounds=@{left=0;top=0;right=1024;bottom=1536}}
$result=[ordered]@{schemaVersion=1;requestId=$request.requestId;jobId=$request.jobId;documentId=$request.documentId;ifRevision=$request.ifRevision;assets=@($source,$base);operations=$ops}
$json=$result|ConvertTo-Json -Depth 12
$json|Set-Content (Join-Path $directory 'result.json.tmp') -Encoding utf8
Move-Item (Join-Path $directory 'result.json.tmp') (Join-Path $directory 'result.json')
$json|Set-Content (Join-Path $PSScriptRoot 'result.json') -Encoding utf8

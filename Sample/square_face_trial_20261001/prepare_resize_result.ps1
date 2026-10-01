# PowerShell 7. Only build a manifest. All pixel resampling is performed by AIArtToPSD.
$ErrorActionPreference='Stop'
$export=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'resize-export.json') -Raw|ConvertFrom-Json
$directory=$export.data.directory
$request=Get-Content -LiteralPath (Join-Path $directory 'request.json') -Raw|ConvertFrom-Json
if(Test-Path -LiteralPath (Join-Path $directory 'result.json')){throw 'Issued result already exists'}
$group=[guid]::NewGuid().ToString('B')
$roots=@($request.layers|Where-Object parentId -eq '')
$operations=@($roots|ForEach-Object {@{op='set_attributes';layerId=$_.layerId;visible=$false;opacity=$_.opacity}})
$operations+=@{op='add_group';layerId=$group;name='サイズ補正（眉・口65％）';parentId='';beforeLayerId=$roots[0].layerId;visible=$true;opacity=255}
$parts=@(
    @{name='眉（両眉一組・約65％）';match='眉（両眉一組・AI試験）';resize=$true;left=180;top=55;width=666;height=998},
    @{name='目（許容済み・両目一組）';match='目（両目一組・AI試験）';resize=$false;left=0;top=0;width=1024;height=1536},
    @{name='口（約65％・位置補正）';match='口（AI試験）';resize=$true;left=186;top=74;width=666;height=998},
    @{name='ベース（肌補完・光除去）';match='ベース（肌補完・光除去）';resize=$false;left=0;top=0;width=1024;height=1536}
)
$assets=@()
foreach($part in $parts){
    $layer=@($request.layers|Where-Object name -eq $part.match)
    if($layer.Count -ne 1){throw ('Expected unique layer: '+$part.match)}
    $asset=@($request.assets|Where-Object assetId -eq $layer[0].assetId)
    if($asset.Count -ne 1){throw 'Missing source asset'}
    $assets+=$asset[0]
    $operations+=@{op='add_layer';layerId=[guid]::NewGuid().ToString('B');name=$part.name;parentId=$group;beforeLayerId='';visible=$true;opacity=255;assetId=$asset[0].assetId;resample=$part.resize;trimTransparent=$part.resize;bounds=@{left=$part.left;top=$part.top;right=($part.left+$part.width);bottom=($part.top+$part.height)}}
}
$result=[ordered]@{schemaVersion=1;requestId=$request.requestId;jobId=$request.jobId;documentId=$request.documentId;ifRevision=$request.ifRevision;assets=$assets;operations=$operations}
$json=$result|ConvertTo-Json -Depth 12
$json|Set-Content -LiteralPath (Join-Path $directory 'result.json.tmp') -Encoding utf8
Move-Item -LiteralPath (Join-Path $directory 'result.json.tmp') -Destination (Join-Path $directory 'result.json')
$json|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'resize-result.json') -Encoding utf8
$directory

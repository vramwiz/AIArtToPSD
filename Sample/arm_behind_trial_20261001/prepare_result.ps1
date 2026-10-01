# PowerShell 7. Put a new right arm behind the fixed torso.
$ErrorActionPreference='Stop'
$export=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'export.json') -Raw|ConvertFrom-Json
$directory=$export.data.directory
$request=Get-Content -LiteralPath (Join-Path $directory 'request.json') -Raw|ConvertFrom-Json
if(Test-Path -LiteralPath (Join-Path $directory 'result.json')){throw 'Result exists'}
function Find-Layer([string]$Name){
 $matches=@($request.layers|Where-Object name -eq $Name)
 if($matches.Count -ne 1){throw "Layer is not unique: $Name"}
 return $matches[0]
}
$torso=Find-Layer '固定素体（首・胴体・衣装／手足なし）'
$frontArms=Find-Layer '右腕（画面左・一つずつ表示）'
$leg=Find-Layer '右脚（画面左・見えている範囲）'
if(-not $torso.visible -or $torso.parentId -ne $leg.parentId -or $torso.parentId -ne $frontArms.parentId){throw 'Unexpected layer arrangement'}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'arm_behind_generated.png') -Destination (Join-Path $directory 'images/arm_behind_generated.png')
$asset=@{assetId='right-arm-behind';path='images/arm_behind_generated.png';sha256=(Get-FileHash -LiteralPath (Join-Path $directory 'images/arm_behind_generated.png')).Hash.ToLowerInvariant();width=1254;height=1254;pixelFormat='RGBA8';colorSpace='sRGB'}
$ops=@(
 @{op='add_layer';layerId=[guid]::NewGuid().ToString('B');parentId=$torso.parentId;beforeLayerId=$leg.layerId;name='03 右腕を後ろに回す（素体の背面・確認用）';visible=$true;opacity=255;assetId=$asset.assetId;sourceBounds=@{left=216;top=32;right=610;bottom=762};bounds=@{left=350;top=286;right=551;bottom=659};resample=$true;trimTransparent=$true}
)
if($frontArms.visible){$ops+=@{op='set_attributes';layerId=$frontArms.layerId;visible=$false;opacity=$frontArms.opacity}}
$result=[ordered]@{schemaVersion=$request.schemaVersion;requestId=$request.requestId;jobId=$request.jobId;documentId=$request.documentId;ifRevision=$request.ifRevision;assets=@($asset);operations=$ops}
$json=$result|ConvertTo-Json -Depth 16
$json|Set-Content -LiteralPath (Join-Path $directory 'result.json.tmp') -Encoding utf8
Move-Item -LiteralPath (Join-Path $directory 'result.json.tmp') -Destination (Join-Path $directory 'result.json')
$json|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'result.json') -Encoding utf8
Write-Output 'Prepared one arm below fixed torso, above legs. Front right-arm group will be hidden.'

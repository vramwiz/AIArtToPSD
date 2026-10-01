# PowerShell 7. Add a coordinated whole-body pose under the existing head.
$ErrorActionPreference='Stop'
$export=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'export.json') -Raw|ConvertFrom-Json
$directory=$export.data.directory
$request=Get-Content -LiteralPath (Join-Path $directory 'request.json') -Raw|ConvertFrom-Json
if(Test-Path -LiteralPath (Join-Path $directory 'result.json')){throw 'Result exists'}
function Find-Layer([string]$Name){
 $ls=@($request.layers|Where-Object name -eq $Name)
 if($ls.Count -ne 1){throw "Ambiguous layer: $Name"}
 return $ls[0]
}
$head=Find-Layer '頭部ベース（髪・顔・首上部）'
$parts=Find-Layer '案2 素体＋手足（確認用）'
if($head.parentId -ne $parts.parentId){throw 'Unexpected hierarchy'}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'pose_generated.png') -Destination (Join-Path $directory 'images/pose_generated.png')
$asset=@{assetId='whole-body-pose';path='images/pose_generated.png';sha256=(Get-FileHash -LiteralPath (Join-Path $directory 'images/pose_generated.png')).Hash.ToLowerInvariant();width=1097;height=1434;pixelFormat='RGBA8';colorSpace='sRGB'}
$ops=@(
 @{op='add_layer';layerId=[guid]::NewGuid().ToString('B');parentId=$head.parentId;beforeLayerId=$parts.layerId;name='体差分02（全身連動・首位置合わせ・確認用）';visible=$true;opacity=255;assetId=$asset.assetId;bounds=@{left=54;top=274;right=959;bottom=1457};resample=$true;trimTransparent=$true}
)
foreach($name in @('案2 素体＋手足（確認用）','体差分01（画面左手を腰に・確認用）','体（首下部・衣装・手足）')){
 $l=Find-Layer $name
 if($l.visible){$ops+=@{op='set_attributes';layerId=$l.layerId;visible=$false;opacity=$l.opacity}}
}
if(-not $head.visible){$ops+=@{op='set_attributes';layerId=$head.layerId;visible=$true;opacity=$head.opacity}}
$result=[ordered]@{schemaVersion=$request.schemaVersion;requestId=$request.requestId;jobId=$request.jobId;documentId=$request.documentId;ifRevision=$request.ifRevision;assets=@($asset);operations=$ops}
$json=$result|ConvertTo-Json -Depth 16
$json|Set-Content -LiteralPath (Join-Path $directory 'result.json.tmp') -Encoding utf8
Move-Item -LiteralPath (Join-Path $directory 'result.json.tmp') -Destination (Join-Path $directory 'result.json')
$json|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'result.json') -Encoding utf8
Write-Output 'Prepared coordinated body pose with existing head shown for neck comparison.'

# PowerShell 7. Add fixed torso and independent limbs, keeping current layers.
$ErrorActionPreference='Stop'
$export=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'export.json') -Raw|ConvertFrom-Json
$directory=$export.data.directory
$request=Get-Content -LiteralPath (Join-Path $directory 'request.json') -Raw|ConvertFrom-Json
if(Test-Path -LiteralPath (Join-Path $directory 'result.json')){throw 'Result already exists'}
$body=@($request.layers|Where-Object name -eq '体（首下部・衣装・手足）')
$pose=@($request.layers|Where-Object name -eq '体差分01（画面左手を腰に・確認用）')
if($body.Count -ne 1 -or $pose.Count -ne 1){throw 'Source layers ambiguous'}
$body=$body[0]; $pose=$pose[0]
$partition=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'partition_verification.json') -Raw|ConvertFrom-Json
$source=@($request.assets|Where-Object assetId -eq $body.assetId)[0]
$posedSource=@($request.assets|Where-Object assetId -eq $pose.assetId)[0]
if($source.sha256 -ne $partition.source_sha256 -or $posedSource.sha256 -ne $partition.accepted_pose_sha256){throw 'Reviewed source differs'}
$group=[guid]::NewGuid().ToString('B')
$armGroup=[guid]::NewGuid().ToString('B')
$ops=@(
 @{op='add_group';layerId=$group;parentId=$body.parentId;beforeLayerId=$pose.layerId;name='案2 素体＋手足（確認用）';visible=$true;opacity=255},
 @{op='add_group';layerId=$armGroup;parentId=$group;beforeLayerId='';name='右腕（画面左・一つずつ表示）';visible=$true;opacity=255}
)
$assets=@()
foreach($part in @(
 @{file='right_arm_hip';name='02 腰に当てる（案1から腕のみ再利用）';parent=$armGroup;visible=$true},
 @{file='right_arm_original';name='01 下ろす（元画素）';parent=$armGroup;visible=$false},
 @{file='left_arm_original';name='左腕（画面右・元画素）';parent=$group;visible=$true},
 @{file='torso';name='固定素体（首・胴体・衣装／手足なし）';parent=$group;visible=$true},
 @{file='right_leg_original';name='右脚（画面左・見えている範囲）';parent=$group;visible=$true},
 @{file='left_leg_original';name='左脚（画面右・見えている範囲）';parent=$group;visible=$true}
)){
 $file=$part.file+'.png'
 Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $directory ('images/'+$file))
 $assets+=@{assetId=$part.file;path=('images/'+$file);sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $file)).Hash.ToLowerInvariant();width=1024;height=1536;pixelFormat='RGBA8';colorSpace='sRGB'}
 $ops+=@{op='add_layer';layerId=[guid]::NewGuid().ToString('B');parentId=$part.parent;beforeLayerId='';name=$part.name;visible=$part.visible;opacity=255;assetId=$part.file;bounds=@{left=0;top=0;right=1024;bottom=1536};trimTransparent=$true}
}
# Avoid overlaying whole-body layers if their current visibility is enabled.
foreach($whole in @($body,$pose)){
 if($whole.visible){$ops+=@{op='set_attributes';layerId=$whole.layerId;visible=$false;opacity=$whole.opacity}}
}
$result=[ordered]@{schemaVersion=$request.schemaVersion;requestId=$request.requestId;jobId=$request.jobId;documentId=$request.documentId;ifRevision=$request.ifRevision;assets=@($assets);operations=@($ops)}
$json=$result|ConvertTo-Json -Depth 16
$json|Set-Content -LiteralPath (Join-Path $directory 'result.json.tmp') -Encoding utf8
Move-Item -LiteralPath (Join-Path $directory 'result.json.tmp') -Destination (Join-Path $directory 'result.json')
$json|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'result.json') -Encoding utf8
Write-Output 'Prepared fixed torso, four original limbs, one alternate arm, and two groups.'

# PowerShell 7. Verify only the two intended layers changed, then save the review snapshot.
$ErrorActionPreference='Stop'
$before=Get-Content (Join-Path $PSScriptRoot 'before_request.json') -Raw|ConvertFrom-Json
$e=Get-Content (Join-Path $PSScriptRoot 'final-export.json') -Raw|ConvertFrom-Json
$after=Get-Content (Join-Path $e.data.directory 'request.json') -Raw|ConvertFrom-Json
$face=@($before.layers|Where-Object name -eq '顔・耳・首（髪を除去・元画素）')[0];$front=@($before.layers|Where-Object name -eq '前髪・横髪（元画素）')[0]
if($before.documentId -ne $after.documentId -or $before.layers.Count -ne $after.layers.Count){throw 'Unexpected document or layer count'}
$unchanged=0
foreach($old in $before.layers){
 $new=@($after.layers|Where-Object layerId -eq $old.layerId);if($new.Count -ne 1){throw 'Missing layer'};$new=$new[0]
 $target=$old.layerId -in @($face.layerId,$front.layerId)
 foreach($prop in @('name','parentId','visible','opacity','bounds','hasMask','kind','prefix','flip')){
  if($target -and $prop -in @('name','bounds')){continue}
  $expected=$old.$prop;if($old.layerId -eq $face.layerId -and $prop -eq 'visible'){$expected=$true}
  if(($expected|ConvertTo-Json -Compress) -cne ($new.$prop|ConvertTo-Json -Compress)){throw "Unexpected change $($old.name) $prop"}
 }
 if($old.kind -eq 'image' -and !$target){
  $a=@($before.assets|Where-Object assetId -eq $old.assetId)[0];$b=@($after.assets|Where-Object assetId -eq $new.assetId)[0]
  if($a.sha256 -ne $b.sha256){throw "Changed non-target image $($old.name)"};$unchanged++
 }
}
$items=@()
foreach($item in @(@{id=$face.layerId;key='skin'},@{id=$front.layerId;key='front'})){
 $l=@($after.layers|Where-Object layerId -eq $item.id)[0];$a=@($after.assets|Where-Object assetId -eq $l.assetId)[0]
 Copy-Item (Join-Path $e.data.directory $a.path) (Join-Path $PSScriptRoot ($item.key+'_final_app.png'))
 $items+=@{key=$item.key;bounds=$l.bounds;asset=$a;layerId=$l.layerId;name=$l.name}
}
$items|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot 'final_parts.json') -Encoding utf8
$psd=Join-Path $PSScriptRoot 'face_foundation_review.psd';if(Test-Path $psd){throw 'Do not overwrite review'}
Copy-Item (Join-Path $e.data.directory 'snapshot.psd') $psd
Copy-Item (Join-Path $e.data.directory 'preview.png') (Join-Path $PSScriptRoot 'preview.png')
Copy-Item (Join-Path $e.data.directory 'request.json') (Join-Path $PSScriptRoot 'final_request.json')
@{date='2026-10-02';status='replaced_verified_awaiting_user_review';documentId=$after.documentId;revision=$after.ifRevision;unchangedOtherImages=$unchanged;totalImages=@($after.layers|Where-Object kind -eq 'image').Count;totalGroups=@($after.layers|Where-Object kind -eq 'group').Count;skinVisible=$true;psdSha256=(Get-FileHash $psd).Hash.ToLowerInvariant();preflight=(Get-Content (Join-Path $PSScriptRoot 'preflight.json') -Raw|ConvertFrom-Json);edge=(Get-Content (Join-Path $PSScriptRoot 'edge_refinement.json') -Raw|ConvertFrom-Json)}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot 'verification.json') -Encoding utf8
Write-Output "Verified $unchanged unchanged non-target images and all non-target properties. Review PSD saved."

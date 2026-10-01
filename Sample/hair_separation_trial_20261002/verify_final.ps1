# PowerShell 7. Final preservation verification and non-overwriting PSD snapshot.
$ErrorActionPreference='Stop'
$before=Get-Content (Join-Path $PSScriptRoot 'before_request.json') -Raw|ConvertFrom-Json
$initial=Get-Content (Join-Path $PSScriptRoot 'after_request.json') -Raw|ConvertFrom-Json
$ex=Get-Content (Join-Path $PSScriptRoot 'final-export.json') -Raw|ConvertFrom-Json
$after=Get-Content (Join-Path $ex.data.directory 'request.json') -Raw|ConvertFrom-Json
$ctx=Get-Content (Join-Path $PSScriptRoot 'context.json') -Raw|ConvertFrom-Json
if($after.documentId -ne $ctx.documentId -or $after.ifRevision -ne '2'){throw 'Unexpected final document'}
$checked=0
foreach($old in $before.layers){
 $new=@($after.layers|Where-Object layerId -eq $old.layerId)
 if($new.Count -ne 1){throw 'Missing original layer'};$new=$new[0]
 foreach($prop in @('name','parentId','visible','opacity','bounds','hasMask','kind','prefix','flip')){
  $expected=$old.$prop;if($prop -eq 'visible' -and $old.layerId -eq $ctx.originalHead){$expected=$false}
  if(($expected|ConvertTo-Json -Compress) -cne ($new.$prop|ConvertTo-Json -Compress)){throw "Changed original property: $($old.name) $prop"}
 }
 if($old.kind -eq 'image'){
  $a=@($before.assets|Where-Object assetId -eq $old.assetId)[0];$b=@($after.assets|Where-Object assetId -eq $new.assetId)[0]
  if($a.sha256 -ne $b.sha256){throw "Changed original image $($old.name)"};$checked++
 }
}
foreach($p in $ctx.layers.PSObject.Properties){
 $old=@($initial.layers|Where-Object layerId -eq $p.Value)[0];$new=@($after.layers|Where-Object layerId -eq $p.Value)[0]
 $a=@($initial.assets|Where-Object assetId -eq $old.assetId)[0];$b=@($after.assets|Where-Object assetId -eq $new.assetId)[0]
 if($a.sha256 -ne $b.sha256){throw 'New layer changed after display switch'}
}
$group=@($after.layers|Where-Object layerId -eq $ctx.group)[0]
if(!$group.visible){throw 'New group not visible'}
$psd=Join-Path $PSScriptRoot 'hair_separation_review.psd'
if(Test-Path -LiteralPath $psd){throw 'Preserve existing review PSD'}
Copy-Item -LiteralPath (Join-Path $ex.data.directory 'snapshot.psd') -Destination $psd
Copy-Item -LiteralPath (Join-Path $ex.data.directory 'request.json') -Destination (Join-Path $PSScriptRoot 'final_request.json')
Copy-Item -LiteralPath (Join-Path $ex.data.directory 'preview.png') -Destination (Join-Path $PSScriptRoot 'preview.png')
@{status='imported_verified_awaiting_user_visual_review';date='2026-10-02';documentId=$after.documentId;revision=$after.ifRevision;originalImagesUnchanged=$checked;originalAttributes='Only original head visibility changed to false';images=@($after.layers|Where-Object kind -eq 'image').Count;groups=@($after.layers|Where-Object kind -eq 'group').Count;psdSha256=(Get-FileHash $psd).Hash.ToLowerInvariant();pixelVerification=(Get-Content (Join-Path $PSScriptRoot 'pixel_verification.json') -Raw|ConvertFrom-Json)}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot 'verification.json') -Encoding utf8
Write-Output "Final verification passed: $checked original images preserved; review PSD copied."

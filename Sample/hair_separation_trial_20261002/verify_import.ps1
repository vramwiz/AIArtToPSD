# PowerShell 7. Verify original layers and copy application outputs for pixel review.
$ErrorActionPreference='Stop'
$before=Get-Content (Join-Path $PSScriptRoot 'before_request.json') -Raw|ConvertFrom-Json
$ex=Get-Content (Join-Path $PSScriptRoot 'after-export.json') -Raw|ConvertFrom-Json
$after=Get-Content (Join-Path $ex.data.directory 'request.json') -Raw|ConvertFrom-Json
$ctx=Get-Content (Join-Path $PSScriptRoot 'context.json') -Raw|ConvertFrom-Json
$checked=0
foreach($old in $before.layers){
 $new=@($after.layers|Where-Object layerId -eq $old.layerId)
 if($new.Count -ne 1){throw 'Missing original layer'};$new=$new[0]
 foreach($prop in @('name','parentId','visible','opacity','bounds','hasMask','kind','prefix','flip')){
  if(($old.$prop|ConvertTo-Json -Compress) -cne ($new.$prop|ConvertTo-Json -Compress)){throw "Changed original property: $($old.name) $prop"}
 }
 if($old.kind -eq 'image'){
  $a=@($before.assets|Where-Object assetId -eq $old.assetId)[0];$b=@($after.assets|Where-Object assetId -eq $new.assetId)[0]
  if($a.sha256 -ne $b.sha256){throw "Changed original image $($old.name)"};$checked++
 }
}
$out=@()
foreach($p in $ctx.layers.PSObject.Properties){
 $l=@($after.layers|Where-Object layerId -eq $p.Value)[0];$a=@($after.assets|Where-Object assetId -eq $l.assetId)[0]
 $file=$p.Name+'_app.png';Copy-Item -LiteralPath (Join-Path $ex.data.directory $a.path) -Destination (Join-Path $PSScriptRoot $file)
 $out+=@{key=$p.Name;file=$file;bounds=$l.bounds;width=$a.width;height=$a.height;sha256=$a.sha256}
}
$out|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot 'app_parts.json') -Encoding utf8
Copy-Item -LiteralPath (Join-Path $ex.data.directory 'request.json') -Destination (Join-Path $PSScriptRoot 'after_request.json')
$beforePreview=Join-Path (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path ('Exchange/'+$before.jobId)) 'preview.png'
$samePreview=(Get-FileHash -LiteralPath $beforePreview).Hash -eq (Get-FileHash -LiteralPath (Join-Path $ex.data.directory 'preview.png')).Hash
if(!$samePreview){throw 'Hidden-group import changed preview'}
@{originalImagesUnchanged=$checked;originalLayerAttributesUnchanged=$before.layers.Count;hiddenImportPreviewUnchanged=$samePreview;images=@($after.layers|Where-Object kind -eq 'image').Count;groups=@($after.layers|Where-Object kind -eq 'group').Count;revision=$after.ifRevision}|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot 'preservation_verification.json') -Encoding utf8
Write-Output "Verified $checked original images and all original properties; hidden import preview unchanged."

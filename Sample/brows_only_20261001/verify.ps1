$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$export=Get-Content (Join-Path $PSScriptRoot 'draft-export.json') -Raw -Encoding UTF8|ConvertFrom-Json
$before=Get-Content (Join-Path $export.data.directory 'request.json') -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content (Join-Path $PSScriptRoot 'native_layers.json') -Raw -Encoding UTF8|ConvertFrom-Json
$unchanged=@()
if($before.layers.Count -ne $after.layers.Count){throw 'Layer count changed'}
for($i=0;$i -lt $before.layers.Count;$i++){
    $a=$before.layers[$i];$b=$after.layers[$i]
    if(($a|ConvertTo-Json -Depth 10 -Compress) -ne ($b|ConvertTo-Json -Depth 10 -Compress)){throw 'Layer metadata changed'}
    if($a.kind -eq 'image' -and $a.assetId -ne 'source-2'){
        $old=$before.assets|Where-Object assetId -eq $a.assetId
        $new=$after.assets|Where-Object assetId -eq $b.assetId
        if($old.sha256 -ne $new.sha256){throw 'Non-brow image changed'}
        $unchanged+=$a.name
    }
}
$source=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot '../character_neutral.png'))
$eyes=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'brows_only.png'))
$kept=0;$changed=0;$transparent=0
for($y=0;$y -lt 19;$y++){for($x=0;$x -lt 109;$x++){
    $p=$eyes.GetPixel($x,$y)
    if($p.A -eq 0){$transparent++}else{
        $kept++
        if($p.ToArgb() -ne $source.GetPixel(($x+449),($y+134)).ToArgb()){$changed++}
    }
}}
if($changed -ne 0 -or $kept -ne 82){throw 'Retained brow pixels differ'}
$report=@{unchangedImageLayers=$unchanged;allLayerMetadataUnchanged=$true;retainedSourcePixels=$kept;changedRetainedPixels=$changed;transparentPixels=$transparent;bounds=@{left=449;top=134;right=558;bottom=153}}
$report|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot 'verification.json') -Encoding UTF8
$snapshot=Get-Content (Join-Path $PSScriptRoot 'snapshot-response.json') -Raw -Encoding UTF8|ConvertFrom-Json
$actual=$after.assets|Where-Object assetId -eq 'source-2'
$actualEyes=[Drawing.Bitmap]::FromFile((Join-Path $snapshot.data.directory $actual.path))
if($actualEyes.Width -ne 109 -or $actualEyes.Height -ne 19){throw 'App brow size differs'}
for($y=0;$y -lt 19;$y++){for($x=0;$x -lt 109;$x++){
    if($actualEyes.GetPixel($x,$y).ToArgb() -ne $eyes.GetPixel($x,$y).ToArgb()){throw 'App output differs'}
}}
$preview=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'native_preview.png'))
$review=[Drawing.Bitmap]::new(480,320)
$g=[Drawing.Graphics]::FromImage($review);$g.Clear([Drawing.Color]::White)
$g.DrawImage($preview,[Drawing.Rectangle]::new(0,0,480,320),380,110,240,160,[Drawing.GraphicsUnit]::Pixel)
$review.Save((Join-Path $PSScriptRoot 'face_review.png'),[Drawing.Imaging.ImageFormat]::Png)
$g.Dispose();$review.Dispose();$preview.Dispose();$actualEyes.Dispose();$eyes.Dispose();$source.Dispose()
$report|ConvertTo-Json -Depth 8

$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$export=Get-Content (Join-Path $PSScriptRoot 'export.json') -Raw -Encoding UTF8|ConvertFrom-Json
$before=Get-Content (Join-Path $export.data.directory 'request.json') -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content (Join-Path $PSScriptRoot 'native_layers.json') -Raw -Encoding UTF8|ConvertFrom-Json
$unchanged=@()
if($before.layers.Count -ne $after.layers.Count){throw 'Layer count changed'}
for($i=0;$i -lt $before.layers.Count;$i++){
    $a=$before.layers[$i];$b=$after.layers[$i]
    if(($a|ConvertTo-Json -Depth 10 -Compress) -ne ($b|ConvertTo-Json -Depth 10 -Compress)){throw 'Layer metadata changed'}
    if($a.kind -eq 'image' -and $a.assetId -ne 'source-3'){
        $old=$before.assets|Where-Object assetId -eq $a.assetId
        $new=$after.assets|Where-Object assetId -eq $b.assetId
        if($old.sha256 -ne $new.sha256){throw 'Non-mouth image changed'}
        $unchanged+=$a.name
    }
}
$source=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot '../character_neutral.png'))
$mouth=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'mouth_only.png'))
$kept=0;$changed=0;$transparent=0
for($y=0;$y -lt 17;$y++){for($x=0;$x -lt 45;$x++){
    $p=$mouth.GetPixel($x,$y)
    if($p.A -eq 0){$transparent++}else{
        $kept++
        if($p.ToArgb() -ne $source.GetPixel(($x+495),($y+215)).ToArgb()){$changed++}
    }
}}
if($changed -ne 0 -or $kept -ne 105){throw 'Retained mouth pixels differ'}
$report=@{unchangedImageLayers=$unchanged;allLayerMetadataUnchanged=$true;retainedSourcePixels=$kept;changedRetainedPixels=$changed;transparentPixels=$transparent;bounds=@{left=495;top=215;right=540;bottom=232}}
$report|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot 'verification.json') -Encoding UTF8
$snapshot=Get-Content (Join-Path $PSScriptRoot 'snapshot-response.json') -Raw -Encoding UTF8|ConvertFrom-Json
$actual=$after.assets|Where-Object assetId -eq 'source-3'
$actualMouth=[Drawing.Bitmap]::FromFile((Join-Path $snapshot.data.directory $actual.path))
if($actualMouth.Width -ne 45 -or $actualMouth.Height -ne 17){throw 'App mouth size differs'}
for($y=0;$y -lt 17;$y++){for($x=0;$x -lt 45;$x++){
    if($actualMouth.GetPixel($x,$y).ToArgb() -ne $mouth.GetPixel($x,$y).ToArgb()){throw 'App output differs'}
}}
$preview=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'native_preview.png'))
$review=[Drawing.Bitmap]::new(480,320)
$g=[Drawing.Graphics]::FromImage($review);$g.Clear([Drawing.Color]::White)
$g.DrawImage($preview,[Drawing.Rectangle]::new(0,0,480,320),380,110,240,160,[Drawing.GraphicsUnit]::Pixel)
$review.Save((Join-Path $PSScriptRoot 'face_review.png'),[Drawing.Imaging.ImageFormat]::Png)
$g.Dispose();$review.Dispose();$preview.Dispose();$actualMouth.Dispose();$mouth.Dispose();$source.Dispose()
$report|ConvertTo-Json -Depth 8

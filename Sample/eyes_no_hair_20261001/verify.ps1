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
    if($a.kind -eq 'image' -and $a.assetId -ne 'source-1'){
        $old=$before.assets|Where-Object assetId -eq $a.assetId
        $new=$after.assets|Where-Object assetId -eq $b.assetId
        if($old.sha256 -ne $new.sha256){throw 'Non-eye image changed'}
        $unchanged+=$a.name
    }
}
$source=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot '../character_neutral.png'))
$eyes=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'eyes_no_hair.png'))
$kept=0;$changed=0;$transparent=0
for($y=0;$y -lt 46;$y++){for($x=0;$x -lt 133;$x++){
    $p=$eyes.GetPixel($x,$y)
    if($p.A -eq 0){$transparent++}else{
        $kept++
        if($p.ToArgb() -ne $source.GetPixel(($x+439),($y+153)).ToArgb()){$changed++}
    }
}}
if($changed -ne 0 -or $kept -ne 2341){throw 'Retained eye pixels differ'}
$report=@{unchangedImageLayers=$unchanged;allLayerMetadataUnchanged=$true;retainedSourcePixels=$kept;changedRetainedPixels=$changed;transparentPixels=$transparent;bounds=@{left=439;top=153;right=572;bottom=199}}
$report|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot 'verification.json') -Encoding UTF8
$snapshot=Get-Content (Join-Path $PSScriptRoot 'snapshot-response.json') -Raw -Encoding UTF8|ConvertFrom-Json
$actual=$after.assets|Where-Object assetId -eq 'source-1'
$actualEyes=[Drawing.Bitmap]::FromFile((Join-Path $snapshot.data.directory $actual.path))
if($actualEyes.Width -ne 133 -or $actualEyes.Height -ne 46){throw 'App eye size differs'}
for($y=0;$y -lt 46;$y++){for($x=0;$x -lt 133;$x++){
    if($actualEyes.GetPixel($x,$y).ToArgb() -ne $eyes.GetPixel($x,$y).ToArgb()){throw 'App output differs'}
}}
$preview=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'native_preview.png'))
$review=[Drawing.Bitmap]::new(480,320)
$g=[Drawing.Graphics]::FromImage($review);$g.Clear([Drawing.Color]::White)
$g.DrawImage($preview,[Drawing.Rectangle]::new(0,0,480,320),380,110,240,160,[Drawing.GraphicsUnit]::Pixel)
$review.Save((Join-Path $PSScriptRoot 'face_review.png'),[Drawing.Imaging.ImageFormat]::Png)
$g.Dispose();$review.Dispose();$preview.Dispose();$actualEyes.Dispose();$eyes.Dispose();$source.Dispose()
$report|ConvertTo-Json -Depth 8

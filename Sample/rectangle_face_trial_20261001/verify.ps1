# Windows PowerShell 5.1. Read-only check and diagnostic preview.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$source=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot '../character_neutral.png'))
$request=Get-Content (Join-Path $PSScriptRoot 'native_layers.json') -Raw -Encoding UTF8|ConvertFrom-Json
$checks=@()
foreach($layer in $request.layers|Where-Object {$_.name -match '元画素' -and $_.kind -eq 'image'}){
    $img=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot ($layer.assetId+'.png')))
    $changed=0
    for($y=0;$y -lt $img.Height;$y++){for($x=0;$x -lt $img.Width;$x++){
        if($img.GetPixel($x,$y).ToArgb() -ne $source.GetPixel(($x+$layer.bounds.left),($y+$layer.bounds.top)).ToArgb()){$changed++}
    }}
    $checks+=@{name=$layer.name;width=$img.Width;height=$img.Height;bounds=$layer.bounds;changedPixels=$changed}
    $img.Dispose()
    if($changed -ne 0){throw 'Original pixels were altered'}
}
if($checks.Count -ne 3){throw 'Expected three original-pixel parts'}
$checks|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot 'verification.json') -Encoding UTF8
$preview=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'native_preview.png'))
$base=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'source-4.png'))
$review=[Drawing.Bitmap]::new(1440,362)
$g=[Drawing.Graphics]::FromImage($review)
$g.Clear([Drawing.Color]::White)
$font=[Drawing.Font]::new('Segoe UI',14)
$labels=@('SOURCE','APP: RECTANGLE PARTS','BASE ONLY')
$panels=@($source,$preview,$base)
for($i=0;$i -lt 3;$i++){
    $x=$i*480
    $g.DrawString($labels[$i],$font,[Drawing.Brushes]::Black,($x+8),8)
    $g.DrawImage($panels[$i],[Drawing.Rectangle]::new($x,42,480,320),380,110,240,160,[Drawing.GraphicsUnit]::Pixel)
}
$review.Save((Join-Path $PSScriptRoot 'face_comparison.png'),[Drawing.Imaging.ImageFormat]::Png)
$g.Dispose();$font.Dispose();$review.Dispose();$preview.Dispose();$base.Dispose();$source.Dispose()
$checks|ConvertTo-Json -Depth 8

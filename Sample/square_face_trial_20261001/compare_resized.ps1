# Windows PowerShell 5.1. Diagnostic comparison only; app performs production transforms.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$paths = @('..\character_neutral.png','..\ai_face_review_20261001\composite_review.png','native_resized_preview.png')
$imgs = @($paths | ForEach-Object { [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot $_)) })
$review = [System.Drawing.Bitmap]::new(1440,362)
$g = [System.Drawing.Graphics]::FromImage($review)
$g.Clear([System.Drawing.Color]::White)
$font = [System.Drawing.Font]::new('Segoe UI',14)
$labels = @('SOURCE','AI BEFORE RESIZE','APP: BROWS + MOUTH 65%')
for($i=0;$i -lt 3;$i++) {
    $x=$i*480
    $g.DrawString($labels[$i],$font,[System.Drawing.Brushes]::Black,($x+8),8)
    for($cy=0;$cy -lt 320;$cy+=16) { for($cx=0;$cx -lt 480;$cx+=16) {
        $brush=if((($cx/16+$cy/16)%2)-eq 0){[System.Drawing.Brushes]::White}else{[System.Drawing.Brushes]::LightGray}
        $g.FillRectangle($brush,($x+$cx),(42+$cy),16,16)
    }}
    $g.DrawImage($imgs[$i],[System.Drawing.Rectangle]::new($x,42,480,320),380,110,240,160,[System.Drawing.GraphicsUnit]::Pixel)
}
$review.Save((Join-Path $PSScriptRoot 'resized_face_comparison.png'),[System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose();$font.Dispose();$review.Dispose()
foreach($img in $imgs){$img.Dispose()}
foreach($name in @('face_square_source.png','base_square.png','eyes_square_rejected.png')) {
    $img=[System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot $name))
    Write-Output "$name $($img.Width)x$($img.Height)"
    $img.Dispose()
}

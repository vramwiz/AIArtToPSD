# Windows PowerShell 5.1; diagnostic source-over rendering at original coordinates only.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$paths = @('..\character_neutral.png','..\ai_separation_check_20261001\base_no_glow_v2.png','..\ai_separation_check_20261001\eyes_pair.png','brows_pair.png','mouth.png')
$imgs = @($paths | ForEach-Object { [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot $_)) })
$composite = [System.Drawing.Bitmap]::new(1024,1536)
$cg = [System.Drawing.Graphics]::FromImage($composite)
$cg.Clear([System.Drawing.Color]::Transparent)
foreach($i in @(1,4,2,3)) { $cg.DrawImageUnscaled($imgs[$i],0,0) }
$cg.Dispose()
$composite.Save((Join-Path $PSScriptRoot 'composite_review.png'),[System.Drawing.Imaging.ImageFormat]::Png)
$review = [System.Drawing.Bitmap]::new(1440,724)
$g = [System.Drawing.Graphics]::FromImage($review)
$g.Clear([System.Drawing.Color]::FromArgb(220,220,220))
$font = [System.Drawing.Font]::new('Segoe UI',14)
$labels = @('SOURCE','AI FACE: ALL LAYERS','SKIN-FILLED BASE','BOTH EYES','BOTH BROWS','MOUTH')
$panels = @($imgs[0],$composite,$imgs[1],$imgs[2],$imgs[3],$imgs[4])
for($i=0;$i -lt 6;$i++) {
    $x=($i%3)*480; $y=[int][Math]::Floor($i/3)*362
    $g.FillRectangle([System.Drawing.Brushes]::White,$x,$y,480,42)
    $g.DrawString($labels[$i],$font,[System.Drawing.Brushes]::Black,($x+8),($y+8))
    for($cy=0;$cy -lt 320;$cy+=16) { for($cx=0;$cx -lt 480;$cx+=16) {
        $brush=if((($cx/16+$cy/16)%2)-eq 0){[System.Drawing.Brushes]::White}else{[System.Drawing.Brushes]::LightGray}
        $g.FillRectangle($brush,($x+$cx),($y+42+$cy),16,16)
    }}
    $g.DrawImage($panels[$i],[System.Drawing.Rectangle]::new($x,($y+42),480,320),380,110,240,160,[System.Drawing.GraphicsUnit]::Pixel)
}
$review.Save((Join-Path $PSScriptRoot 'face_review.png'),[System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose();$font.Dispose();$review.Dispose();$composite.Dispose()
foreach($img in $imgs){$img.Dispose()}

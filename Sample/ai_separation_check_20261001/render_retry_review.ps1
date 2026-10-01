# Diagnostic alpha-compositing preview only. Does not modify any source or layer asset.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$canvas = [System.Drawing.Bitmap]::new(1536,810)
$g = [System.Drawing.Graphics]::FromImage($canvas)
$font = [System.Drawing.Font]::new('Segoe UI',15)
$light = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(235,235,235))
$dark = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(190,190,190))
$g.Clear([System.Drawing.Color]::White)
$names = @('SOURCE', 'FIRST BASE', 'RETRY: REMOVE GLOW')
$paths = @('..\character_neutral.png','base_generated.png','base_no_glow_v2.png')
for ($i=0; $i -lt 3; $i++) {
    $g.DrawString($names[$i],$font,[System.Drawing.Brushes]::Black,($i*512+12),8)
    for ($y=42; $y -lt 810; $y+=16) {
        for ($x=0; $x -lt 512; $x+=16) {
            $brush = if ((($x/16 + ($y-42)/16) % 2) -eq 0) { $light } else { $dark }
            $g.FillRectangle($brush,($i*512+$x),$y,16,16)
        }
    }
    $inputImage = [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot $paths[$i]))
    $g.DrawImage($inputImage,[System.Drawing.Rectangle]::new(($i*512),42,512,768))
    $inputImage.Dispose()
}
$canvas.Save((Join-Path $PSScriptRoot 'retry_alpha_review.png'),[System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $canvas.Dispose(); $font.Dispose(); $light.Dispose(); $dark.Dispose()

# Diagnostic close-ups: standard source-over rendering at (0,0), with no alignment correction.
$source = [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot '..\character_neutral.png'))
$base = [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot 'base_no_glow_v2.png'))
$eye = [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot 'eye_left_v2_rejected.png'))
$composite = [System.Drawing.Bitmap]::new(1024,1536)
$cg = [System.Drawing.Graphics]::FromImage($composite)
$cg.Clear([System.Drawing.Color]::Transparent)
$cg.DrawImageUnscaled($base,0,0)
$cg.DrawImageUnscaled($eye,0,0)
$cg.Dispose()
$review = [System.Drawing.Bitmap]::new(1440,382)
$rg = [System.Drawing.Graphics]::FromImage($review)
$rg.Clear([System.Drawing.Color]::FromArgb(220,220,220))
$rf = [System.Drawing.Font]::new('Segoe UI',15)
$panels = @($source,$base,$composite)
$labels = @('SOURCE','CLEANED BASE','BASE + RETRY EYE (NO ADJUSTMENT)')
for($i=0;$i -lt 3;$i++) {
    $rg.DrawString($labels[$i],$rf,[System.Drawing.Brushes]::Black,($i*480+8),8)
    $rg.DrawImage($panels[$i],[System.Drawing.Rectangle]::new(($i*480),42,480,340),380,110,240,170,[System.Drawing.GraphicsUnit]::Pixel)
}
$review.Save((Join-Path $PSScriptRoot 'retry_face_review.png'),[System.Drawing.Imaging.ImageFormat]::Png)
$rg.Dispose(); $review.Dispose(); $rf.Dispose(); $source.Dispose(); $base.Dispose(); $eye.Dispose(); $composite.Dispose()

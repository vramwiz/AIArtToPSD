# Windows PowerShell 5.1. Original visible brow pixels only, no redraw or resizing.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
if((Get-FileHash (Join-Path $PSScriptRoot '../character_neutral.png')).Hash -ne '58ECE460E16D10BEBA67AA0B239C6E7075200C73DD6AFDAC6135F6C9BB1FFF07'){throw 'Source differs from reviewed image'}
$source=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot '../character_neutral.png'))
$left=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot '../face_trial_20261001/brow_left_mask.png'))
$right=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot '../face_trial_20261001/brow_right_mask.png'))
$out=[Drawing.Bitmap]::new(109,19,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
$kept=0
for($y=0;$y -lt 19;$y++){for($x=0;$x -lt 109;$x++){
    $sx=$x+449;$sy=$y+134
    if($left.GetPixel($sx,$sy).R -gt 0 -or $right.GetPixel($sx,$sy).R -gt 0){
        $p=$source.GetPixel($sx,$sy)
        # Within the reviewed brow outlines, exclude blue-gray hair and light skin/shadow.
        if($sx -lt 500 -and $p.B -gt $p.R){continue}
        if(($sx -ge 540 -and $sy -lt 140) -or ($sx -le 469 -and $sy -lt 148)){continue}
        if($sx -ge 500 -and ($sx -le 518 -or $sx -ge 547)){continue}
        # Left visible fragments: omit the surrounding lighter shadow pixels.
        if($sx -lt 500 -and (($p.R+$p.G+$p.B)/3) -ge 155){continue}
        $out.SetPixel($x,$y,$p);$kept++
    }
}}
$out.Save((Join-Path $PSScriptRoot 'brows_only.png'),[Drawing.Imaging.ImageFormat]::Png)
$review=[Drawing.Bitmap]::new(1090,460)
$g=[Drawing.Graphics]::FromImage($review);$g.Clear([Drawing.Color]::White)
$g.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::Half
$g.DrawImage($source,[Drawing.Rectangle]::new(0,0,1090,190),449,134,109,19,[Drawing.GraphicsUnit]::Pixel)
for($y=240;$y -lt 430;$y+=10){for($x=0;$x -lt 1090;$x+=10){
    $b=if((($x/10+($y-240)/10)%2)-eq 0){[Drawing.Brushes]::White}else{[Drawing.Brushes]::LightGray}
    $g.FillRectangle($b,$x,$y,10,10)
}}
$g.DrawImage($out,[Drawing.Rectangle]::new(0,240,1090,190),0,0,109,19,[Drawing.GraphicsUnit]::Pixel)
$review.Save((Join-Path $PSScriptRoot 'brows_review.png'),[Drawing.Imaging.ImageFormat]::Png)
$g.Dispose();$review.Dispose();$out.Dispose();$source.Dispose();$left.Dispose();$right.Dispose()
Write-Output "Retained original brow pixels: $kept"

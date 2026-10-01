# Windows PowerShell 5.1. Preserve original pixels; retain only the reviewed eye outlines.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
if((Get-FileHash (Join-Path $PSScriptRoot '../character_neutral.png')).Hash -ne '58ECE460E16D10BEBA67AA0B239C6E7075200C73DD6AFDAC6135F6C9BB1FFF07'){throw 'Source differs from reviewed image'}
$source=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot '../character_neutral.png'))
$left=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot '../face_trial_20261001/eye_left_mask.png'))
$right=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot '../face_trial_20261001/eye_right_mask.png'))
$out=[Drawing.Bitmap]::new(133,46,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
$kept=0; $removedHair=0
for($y=0;$y -lt 46;$y++){for($x=0;$x -lt 133;$x++){
    $sx=$x+439; $sy=$y+153
    if($left.GetPixel($sx,$sy).R -gt 0 -or $right.GetPixel($sx,$sy).R -gt 0){
        $pixel=$source.GetPixel($sx,$sy)
        # Source-specific hair contact zones, outside both irises. Do not key blue globally.
        $hairContact=($sx -le 453) -or ($sx -ge 563) -or (($sx -ge 485) -and ($sx -le 497) -and ($sy -le 174))
        if($hairContact -and ($pixel.B -gt $pixel.R)){$removedHair++;continue}
        $out.SetPixel($x,$y,$pixel); $kept++
    }
}}
$out.Save((Join-Path $PSScriptRoot 'eyes_no_hair.png'),[Drawing.Imaging.ImageFormat]::Png)
$review=[Drawing.Bitmap]::new(1064,824)
$g=[Drawing.Graphics]::FromImage($review)
$g.Clear([Drawing.Color]::White)
$g.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::Half
$g.DrawImage($source,[Drawing.Rectangle]::new(0,0,1064,368),439,153,133,46,[Drawing.GraphicsUnit]::Pixel)
for($y=408;$y -lt 776;$y+=16){for($x=0;$x -lt 1064;$x+=16){
    $b=if((($x/16+($y-408)/16)%2)-eq 0){[Drawing.Brushes]::White}else{[Drawing.Brushes]::LightGray}
    $g.FillRectangle($b,$x,$y,16,16)
}}
$g.DrawImage($out,[Drawing.Rectangle]::new(0,408,1064,368),0,0,133,46,[Drawing.GraphicsUnit]::Pixel)
$review.Save((Join-Path $PSScriptRoot 'eyes_review.png'),[Drawing.Imaging.ImageFormat]::Png)
$g.Dispose();$review.Dispose();$out.Dispose();$source.Dispose();$left.Dispose();$right.Dispose()
Write-Output "Kept original pixels: $kept; removed hair-contact pixels: $removedHair"

# Windows PowerShell 5.1. Keep the original mouth pixels; clear surrounding skin.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
if((Get-FileHash (Join-Path $PSScriptRoot '../character_neutral.png')).Hash -ne '58ECE460E16D10BEBA67AA0B239C6E7075200C73DD6AFDAC6135F6C9BB1FFF07'){throw 'Source differs from reviewed image'}
$source=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot '../character_neutral.png'))
$mask=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot '../face_trial_20261001/mouth_mask.png'))
$out=[Drawing.Bitmap]::new(45,17,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
$kept=0
for($y=0;$y -lt 17;$y++){for($x=0;$x -lt 45;$x++){
    $sx=$x+495;$sy=$y+215
    if($mask.GetPixel($sx,$sy).R -gt 0){
        $p=$source.GetPixel($sx,$sy)
        # Source-specific lip color and the small pale highlight inside the mouth.
        $lip=($p.G -lt 215 -and ($p.R-$p.G) -gt 15)
        $highlight=($sx -ge 511 -and $sx -le 515 -and $sy -ge 223 -and $sy -le 225)
        if(-not ($lip -or $highlight)){continue}
        $out.SetPixel($x,$y,$p);$kept++
    }
}}
# Keep the original interior between the left/right lip contour on each row.
# Pale pixels within the mouth must not become accidental transparent holes.
for($y=0;$y -lt 17;$y++){
    $first=45;$last=-1
    for($x=0;$x -lt 45;$x++){if($out.GetPixel($x,$y).A -gt 0){$first=[Math]::Min($first,$x);$last=$x}}
    for($x=$first;$x -le $last;$x++){
        if($out.GetPixel($x,$y).A -eq 0){$out.SetPixel($x,$y,$source.GetPixel(($x+495),($y+215)));$kept++}
    }
}
$out.Save((Join-Path $PSScriptRoot 'mouth_only.png'),[Drawing.Imaging.ImageFormat]::Png)
$review=[Drawing.Bitmap]::new(900,760)
$g=[Drawing.Graphics]::FromImage($review);$g.Clear([Drawing.Color]::White)
$g.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::Half
$g.DrawImage($source,[Drawing.Rectangle]::new(0,0,900,340),495,215,45,17,[Drawing.GraphicsUnit]::Pixel)
for($y=400;$y -lt 740;$y+=20){for($x=0;$x -lt 900;$x+=20){
    $brush=if((($x/20+($y-400)/20)%2)-eq 0){[Drawing.Brushes]::White}else{[Drawing.Brushes]::LightGray}
    $g.FillRectangle($brush,$x,$y,20,20)
}}
$g.DrawImage($out,[Drawing.Rectangle]::new(0,400,900,340),0,0,45,17,[Drawing.GraphicsUnit]::Pixel)
$review.Save((Join-Path $PSScriptRoot 'mouth_review.png'),[Drawing.Imaging.ImageFormat]::Png)
$g.Dispose();$review.Dispose();$out.Dispose();$source.Dispose();$mask.Dispose()
Write-Output "Retained original mouth pixels: $kept"

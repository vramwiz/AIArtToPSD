# Windows PowerShell 5.1. Diagnostic rendering and measurement only; never modifies image assets.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
public static class PairStats {
    public static object Measure(string path,int minX,int maxX) {
        using(var b=new Bitmap(path)) {
            int count=0,x0=b.Width,y0=b.Height,x1=-1,y1=-1,solid=0,outside=0;
            long sx=0,sy=0;
            for(int y=0;y<b.Height;y++) for(int x=minX;x<Math.Min(maxX,b.Width);x++) {
                var c=b.GetPixel(x,y);
                if(c.A>0) count++;
                if(c.A<=128) continue;
                solid++;sx+=x;sy+=y;
                x0=Math.Min(x0,x);x1=Math.Max(x1,x);y0=Math.Min(y0,y);y1=Math.Max(y1,y);
                if(x<430 || x>=580 || y<140 || y>=210) outside++;
            }
            return new {width=b.Width,height=b.Height,alphaPositive=count,alphaAbove128=solid,
                bboxAbove128=new[]{x0,y0,x1,y1},alphaSupportCentroid=solid==0?null:new[]{(double)sx/solid,(double)sy/solid},outsideEyePairRegionAbove128=outside};
        }
    }
}
'@
$measurements = [ordered]@{}
foreach($entry in @(@('pair_left','eyes_pair.png',0,510),@('pair_right','eyes_pair.png',510,1024),@('previous_single_left','eye_left_v2_rejected.png',0,1024),@('original_left_reference','..\face_trial_20261001\eye_left.png',0,1024),@('original_right_reference','..\face_trial_20261001\eye_right.png',0,1024))) {
    $path = Join-Path $PSScriptRoot $entry[1]
    $measurements[$entry[0]] = [ordered]@{sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;stats=[PairStats]::Measure($path,$entry[2],$entry[3])}
}
$measurements | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'eyes_pair_verification.json') -Encoding UTF8
$measurements | ConvertTo-Json -Depth 8 -Compress
$source = [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot '..\character_neutral.png'))
$base = [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot 'base_no_glow_v2.png'))
$pair = [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot 'eyes_pair.png'))
$single = [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot 'eye_left_v2_rejected.png'))
$composites = @()
foreach($layer in @($single,$pair)) {
    $b = [System.Drawing.Bitmap]::new(1024,1536)
    $bg = [System.Drawing.Graphics]::FromImage($b)
    $bg.Clear([System.Drawing.Color]::Transparent)
    $bg.DrawImageUnscaled($base,0,0)
    $bg.DrawImageUnscaled($layer,0,0)
    $bg.Dispose()
    $composites += $b
}
$review = [System.Drawing.Bitmap]::new(1440,724)
$g = [System.Drawing.Graphics]::FromImage($review)
$g.Clear([System.Drawing.Color]::FromArgb(224,224,224))
$font = [System.Drawing.Font]::new('Segoe UI',14)
$labels = @('SOURCE','PREVIOUS SINGLE EYE','BOTH EYES TOGETHER','PAIR ON LIGHT BACKGROUND','PAIR ON DARK BACKGROUND','PAIR ON CHECKERBOARD')
for($i=0;$i -lt 6;$i++) {
    $x=($i%3)*480; $y=[int][Math]::Floor($i/3)*362
    $g.FillRectangle([System.Drawing.Brushes]::White,$x,$y,480,42)
    $g.DrawString($labels[$i],$font,[System.Drawing.Brushes]::Black,($x+8),($y+8))
    if($i -eq 3) {$g.FillRectangle([System.Drawing.Brushes]::White,$x,($y+42),480,320)}
    if($i -eq 4) {$g.FillRectangle([System.Drawing.Brushes]::Black,$x,($y+42),480,320)}
    if($i -eq 5) {
        for($cy=0;$cy -lt 320;$cy+=16) { for($cx=0;$cx -lt 480;$cx+=16) {
            $brush=if((($cx/16+$cy/16)%2)-eq 0){[System.Drawing.Brushes]::White}else{[System.Drawing.Brushes]::LightGray}
            $g.FillRectangle($brush,($x+$cx),($y+42+$cy),16,16)
        }}
    }
    $img = if($i -eq 0){$source}elseif($i -eq 1){$composites[0]}elseif($i -eq 2){$composites[1]}else{$pair}
    $g.DrawImage($img,[System.Drawing.Rectangle]::new($x,($y+42),480,320),380,110,240,160,[System.Drawing.GraphicsUnit]::Pixel)
}
$review.Save((Join-Path $PSScriptRoot 'eyes_pair_review.png'),[System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose();$font.Dispose();$review.Dispose();$source.Dispose();$base.Dispose();$pair.Dispose();$single.Dispose()
foreach($b in $composites){$b.Dispose()}

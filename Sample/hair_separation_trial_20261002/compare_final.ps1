# Windows PowerShell 5.1. Compare actual application composites.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
public static class CompositeCompare {
 public static string Check(Bitmap a,Bitmap b) {
  int changed=0,outside=0,maxRgb=0,maxAlpha=0;long sum=0;
  for(int y=0;y<a.Height;y++)for(int x=0;x<a.Width;x++){
   Color p=a.GetPixel(x,y),q=b.GetPixel(x,y);
   if(p.ToArgb()==q.ToArgb())continue;changed++;
   if(x<366||x>=638||y<19||y>=274)outside++;
   int d=Math.Max(Math.Abs(p.R-q.R),Math.Max(Math.Abs(p.G-q.G),Math.Abs(p.B-q.B)));maxRgb=Math.Max(maxRgb,d);sum+=d;maxAlpha=Math.Max(maxAlpha,Math.Abs(p.A-q.A));
  }
  if(outside!=0)throw new Exception("Unexpected composite change outside head");
  return "{\"changedPixels\":"+changed+",\"changesOutsideHead\":"+outside+",\"maxRGBDelta\":"+maxRgb+",\"maxAlphaDelta\":"+maxAlpha+",\"meanMaxRGBDeltaAmongChanged\":"+(changed>0?(double)sum/changed:0).ToString(System.Globalization.CultureInfo.InvariantCulture)+"}";
 }
}
'@
$a=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot '../../Exchange/{5B3C025E-B05C-42FD-8943-E017B6F8F9ED}/preview.png'))
$b=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'preview.png'))
$json=[CompositeCompare]::Check($a,$b)
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'composite_verification.json'),$json,[Text.UTF8Encoding]::new($false))
$json
$out=[Drawing.Bitmap]::new(1088,1100);$g=[Drawing.Graphics]::FromImage($out);$g.Clear([Drawing.Color]::White)
$g.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::NearestNeighbor;$g.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::Half
$font=[Drawing.Font]::new('Arial',14)
for($row=0;$row -lt 2;$row++){for($col=0;$col -lt 2;$col++){
 $l=$col*544;$t=$row*550;$img=if($col -eq 0){$a}else{$b};$title=if($col -eq 0){'Before'}else{'Actual app result'}
 $g.DrawString($title,$font,[Drawing.Brushes]::Black,($l+8),($t+4))
 if($row -eq 1){$g.FillRectangle([Drawing.Brushes]::DarkSlateGray,$l,($t+30),544,510)}
 $g.DrawImage($img,[Drawing.Rectangle]::new($l,($t+30),544,510),366,19,272,255,[Drawing.GraphicsUnit]::Pixel)
}}
$out.Save((Join-Path $PSScriptRoot 'app_comparison.png'),[Drawing.Imaging.ImageFormat]::Png)
$g.Dispose();$out.Dispose();$a.Dispose();$b.Dispose();$font.Dispose()

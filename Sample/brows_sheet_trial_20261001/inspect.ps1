# Windows PowerShell 5.1. Alpha analysis and diagnostic preview; source remains untouched.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
public static class EyeScan {
  public static int[] Scan(Bitmap im,int l,int t,int r,int b,int threshold) {
    int x0=r,y0=b,x1=l,y1=t,n=0;
    for(int y=t;y<b;y++) for(int x=l;x<r;x++) if(im.GetPixel(x,y).A>threshold){
      x0=Math.Min(x0,x);y0=Math.Min(y0,y);x1=Math.Max(x1,x+1);y1=Math.Max(y1,y+1);n++;
    }
    return new int[]{x0,y0,x1,y1,n};
  }
}
'@
$im=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'brows_sheet.png'))
$review=[Drawing.Bitmap]::new($im.Width,$im.Height)
$g=[Drawing.Graphics]::FromImage($review)
for($y=0;$y -lt $im.Height;$y+=24){for($x=0;$x -lt $im.Width;$x+=24){
    $brush=if((($x/24+$y/24)%2)-eq 0){[Drawing.Brushes]::White}else{[Drawing.Brushes]::LightGray}
    $g.FillRectangle($brush,$x,$y,24,24)
}}
$g.DrawImageUnscaled($im,0,0)
$review.Save((Join-Path $PSScriptRoot 'sheet_review.png'),[Drawing.Imaging.ImageFormat]::Png)
$g.Dispose();$review.Dispose()
$data=@()
for($i=0;$i -lt 8;$i++){
    $l=[int][Math]::Floor(($i%2)*$im.Width/2);$r=[int][Math]::Floor(($i%2+1)*$im.Width/2)
    $row=[int][Math]::Floor($i/2);$t=[int][Math]::Floor($row*$im.Height/4);$b=[int][Math]::Floor(($row+1)*$im.Height/4)
    $scans=@();foreach($a in @(0,16,127,239)){$box=[EyeScan]::Scan($im,$l,$t,$r,$b,$a);$scans+=@{threshold=$a;box=@($box[0..3]);count=$box[4]}}
    $data+=@{index=$i;cell=@{left=$l;top=$t;right=$r;bottom=$b};alphaScans=$scans}
}
$data|ConvertTo-Json -Depth 10|Set-Content (Join-Path $PSScriptRoot 'alpha_measurements.json') -Encoding UTF8
"Image: $($im.Width)x$($im.Height)"
$data|ConvertTo-Json -Depth 10
$original=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot '../brows_only_20261001/brows_only.png'))
'Original alpha>16 bounds: '+([EyeScan]::Scan($original,0,0,$original.Width,$original.Height,16)-join ',')
$original.Dispose();$im.Dispose()

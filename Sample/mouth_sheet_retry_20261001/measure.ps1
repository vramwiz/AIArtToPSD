# Windows PowerShell 5.1. Read-only analysis; application does production resampling.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
public static class SheetMeasure {
  public static int[] Scan(Bitmap image,int l,int t,int r,int b,int threshold) {
    int x0=r,y0=b,x1=l,y1=t,n=0;
    for(int y=t;y<b;y++) for(int x=l;x<r;x++) if(image.GetPixel(x,y).A>threshold) {
      x0=Math.Min(x0,x);y0=Math.Min(y0,y);x1=Math.Max(x1,x+1);y1=Math.Max(y1,y+1);n++;
    }
    return new int[]{x0,y0,x1,y1,n};
  }
}
'@
$image=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'mouth_sheet.png'))
if($image.Width -ne 1254 -or $image.Height -ne 1254){throw 'Recalculate cells for actual dimensions'}
$states=@('closed','half','open','a','i','u','e','o','n')
$parts=@();$scale=47.0/278.0
for($i=0;$i -lt 9;$i++){
    $col=$i%3;$row=[int][Math]::Floor($i/3);$l=$col*418;$t=$row*418
    $b=[SheetMeasure]::Scan($image,$l,$t,($l+418),($t+418),16)
    if($b[4] -eq 0){throw 'Empty cell'}
    $source=@{left=($l+70);top=($t+70);right=($l+348);bottom=($t+348)}
    if($b[0] -lt $source.left -or $b[1] -lt $source.top -or $b[2] -gt $source.right -or $b[3] -gt $source.bottom){throw 'Visible sprite exceeds common crop'}
    $cx=($b[0]+$b[2])/2.0;$cy=($b[1]+$b[3])/2.0
    $dx=[int][Math]::Floor(512.5-($cx-$source.left)*$scale+0.5)
    $dy=[int][Math]::Floor(223.5-($cy-$source.top)*$scale+0.5)
    $parts+=@{index=$i;state=$states[$i];sourceBounds=$source;visibleBounds=@{left=$b[0];top=$b[1];right=$b[2];bottom=$b[3]};visiblePixels=$b[4];scale=$scale;bounds=@{left=$dx;top=$dy;right=($dx+47);bottom=($dy+47)}}
}
$parts|ConvertTo-Json -Depth 10|Set-Content (Join-Path $PSScriptRoot 'measurements.json') -Encoding UTF8
$parts|ForEach-Object{[PSCustomObject]@{state=$_.state;width=($_.visibleBounds.right-$_.visibleBounds.left);height=($_.visibleBounds.bottom-$_.visibleBounds.top);destLeft=$_.bounds.left;destTop=$_.bounds.top;scale=$_.scale}}|Format-Table
$image.Dispose()

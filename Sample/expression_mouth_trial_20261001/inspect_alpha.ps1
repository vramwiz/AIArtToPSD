# Windows PowerShell 5.1; read-only alpha inspection, no production pixel editing.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
public static class AlphaInspect {
  public static int[] Bounds(Bitmap image, int threshold) {
    int left=image.Width,top=image.Height,right=0,bottom=0,count=0;
    for(int y=0;y<image.Height;y++) for(int x=0;x<image.Width;x++) {
      if(image.GetPixel(x,y).A<=threshold) continue;
      count++; left=Math.Min(left,x);top=Math.Min(top,y);right=Math.Max(right,x+1);bottom=Math.Max(bottom,y+1);
    }
    return new int[]{left,top,right,bottom,count};
  }
}
'@
$reports=@()
foreach($file in @('mouth_open_generated.png','../mouth_only_20261001/mouth_only.png')){
    $image=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot $file))
    $bounds=@()
    foreach($threshold in @(0,16,128)){
        $b=[AlphaInspect]::Bounds($image,$threshold)
        $bounds+=@{threshold=$threshold;left=$b[0];top=$b[1];right=$b[2];bottom=$b[3];count=$b[4]}
    }
    $reports+=@{file=$file;width=$image.Width;height=$image.Height;alpha=$bounds}
    $image.Dispose()
}
$reports|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot 'alpha.json') -Encoding UTF8
$reports|ConvertTo-Json -Depth 8

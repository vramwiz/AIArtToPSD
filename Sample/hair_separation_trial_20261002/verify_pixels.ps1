# Windows PowerShell 5.1. Pixel integrity check for the actual application outputs.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
public static class HairVerify {
 public static string Check(Bitmap src,Bitmap front,Bitmap face,Bitmap rear,Bitmap fill){
  int mismatch=0,overlap=0,missing=0,minCore=255,fillOutside=0,copied=0;
  for(int y=0;y<255;y++)for(int x=0;x<272;x++){
   Color p=src.GetPixel(x,y);Color[] parts={front.GetPixel(x,y),face.GetPixel(x,y),rear.GetPixel(x,y)};int n=0;
   foreach(Color v in parts)if(v.A>0){n++;copied++;if(v.ToArgb()!=p.ToArgb())mismatch++;}
   if(n>1)overlap++;if(p.A>0&&n!=1)missing++;
   if(fill.GetPixel(x,y).A>0&&p.A==0)fillOutside++;
   if(x>115&&x<185&&y>100&&y<210)minCore=Math.Min(minCore,fill.GetPixel(x,y).A);
  }
  if(mismatch!=0||overlap!=0||missing!=0||minCore<240)throw new Exception("Pixel integrity or continuous core failed: mismatch="+mismatch+", overlap="+overlap+", missing="+missing+", minCore="+minCore);
  return "{\"originalPixelMismatches\":"+mismatch+",\"originalPixelOverlap\":"+overlap+",\"originalPixelsMissing\":"+missing+",\"copiedOriginalPixels\":"+copied+",\"completedRearCoreMinAlpha\":"+minCore+",\"fillPixelsOutsideOriginalAlpha\":"+fillOutside+"}";
 }
}
'@
$parts=Get-Content (Join-Path $PSScriptRoot 'app_parts.json') -Raw -Encoding UTF8|ConvertFrom-Json
function FullPart($key){
 $p=@($parts|Where-Object key -eq $key)[0];$src=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot $p.file));$dst=[Drawing.Bitmap]::new(272,255)
 for($y=0;$y -lt $src.Height;$y++){for($x=0;$x -lt $src.Width;$x++){$dst.SetPixel(($x+$p.bounds.left-366),($y+$p.bounds.top-19),$src.GetPixel($x,$y))}}
 $src.Dispose();return ,$dst
}
$src=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'head_source.png'))
$front=FullPart 'front';$face=FullPart 'face';$rear=FullPart 'rear-visible';$fill=FullPart 'rear-fill'
$json=[HairVerify]::Check($src,$front,$face,$rear,$fill)
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'pixel_verification.json'),$json,[Text.UTF8Encoding]::new($false))
$json
foreach($b in @($src,$front,$face,$rear,$fill)){$b.Dispose()}

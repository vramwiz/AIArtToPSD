# Windows PowerShell 5.1. Compare direct pixels, then flood-fill transparent exterior to detect holes.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Collections.Generic;
public static class FoundationCheck {
 public static int Compare(Bitmap expected,Bitmap crop,int ox,int oy){int errors=0;for(int y=0;y<255;y++)for(int x=0;x<272;x++){Color e=expected.GetPixel(x,y);int cx=x-ox,cy=y-oy;Color a=cx<0||cy<0||cx>=crop.Width||cy>=crop.Height?Color.Transparent:crop.GetPixel(cx,cy);if((e.A>0||a.A>0)&&e.ToArgb()!=a.ToArgb())errors++;}return errors;}
 public static int Holes(Bitmap b){int w=b.Width,h=b.Height;bool[,] seen=new bool[w,h];Queue<Point> q=new Queue<Point>();
  for(int y=0;y<h;y++)for(int x=0;x<w;x++)if((x==0||x==w-1||y==0||y==h-1)&&b.GetPixel(x,y).A<128){q.Enqueue(new Point(x,y));seen[x,y]=true;}
  int[] dx={-1,1,0,0,-1,-1,1,1},dy={0,0,-1,1,-1,1,-1,1};while(q.Count>0){Point p=q.Dequeue();for(int k=0;k<8;k++){int x=p.X+dx[k],y=p.Y+dy[k];if(x<0||y<0||x>=w||y>=h||seen[x,y]||b.GetPixel(x,y).A>=128)continue;seen[x,y]=true;q.Enqueue(new Point(x,y));}}
  int holes=0;for(int y=0;y<h;y++)for(int x=0;x<w;x++)if(!seen[x,y]&&b.GetPixel(x,y).A<128){holes++;Console.WriteLine("Enclosed low-alpha pixel in cropped skin: "+x+","+y+" alpha="+b.GetPixel(x,y).A);}return holes;
 }
}
'@
$parts=Get-Content (Join-Path $PSScriptRoot 'final_parts.json') -Raw -Encoding UTF8|ConvertFrom-Json
$checks=@()
foreach($p in $parts){$f=if($p.key -eq 'skin'){'face_completed.png'}else{'front_edge_refined.png'};$expected=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot $f));$actual=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot ($p.key+'_final_app.png')));$n=[FoundationCheck]::Compare($expected,$actual,($p.bounds.left-366),($p.bounds.top-19));if($n -ne 0){throw 'App output mismatch'};$hole=if($p.key -eq 'skin'){[FoundationCheck]::Holes($actual)}else{$null};$checks+=@{part=$p.key;pixelMismatches=$n;enclosedTransparentPixels=$hole};$expected.Dispose();$actual.Dispose()}
$checks|ConvertTo-Json -Depth 5|Set-Content (Join-Path $PSScriptRoot 'app_pixel_verification.json') -Encoding UTF8
$checks|ConvertTo-Json -Depth 5

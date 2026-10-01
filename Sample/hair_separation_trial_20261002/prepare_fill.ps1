# Windows PowerShell 5.1. Preserve generated pixels and alpha; application performs resampling.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
public static class HairFill {
 public static void Run(string dir) {
  using(Bitmap src=new Bitmap(System.IO.Path.Combine(dir,"head_source.png")))
  using(Bitmap face=new Bitmap(System.IO.Path.Combine(dir,"face_neck_original.png")))
  using(Bitmap front=new Bitmap(System.IO.Path.Combine(dir,"front_hair_original.png")))
  using(Bitmap gen=new Bitmap(System.IO.Path.Combine(dir,"rear_hair_generated.png")))
  using(Bitmap output=new Bitmap(gen.Width,gen.Height,PixelFormat.Format32bppArgb))
  using(Bitmap mask=new Bitmap(272,255,PixelFormat.Format32bppArgb)) {
   bool[,] use=new bool[272,255];int n=0;
   for(int y=2;y<249;y++)for(int x=2;x<270;x++){
    // Restrict generated pixels to the occluded interior, plus a one-pixel overlap under the preserved rear hair.
    if(y < 28+0.0035*(x-145)*(x-145))continue;
    bool inside=true;for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++)if(src.GetPixel(x+dx,y+dy).A<200)inside=false;
    if(!inside)continue;
    bool hidden=false;for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++)if(face.GetPixel(x+dx,y+dy).A>0||front.GetPixel(x+dx,y+dy).A>0)hidden=true;
    if(hidden){use[x,y]=true;mask.SetPixel(x,y,Color.White);n++;}
   }
   long visible=0,transparent=0;int minAlpha=255;
   for(int y=0;y<gen.Height;y++)for(int x=0;x<gen.Width;x++){
    int nx=Math.Min(271,(int)((x+0.5)*272/gen.Width));int ny=Math.Min(254,(int)((y+0.5)*255/gen.Height));
    Color p=gen.GetPixel(x,y);if(p.A==0)transparent++;
    if(use[nx,ny]){output.SetPixel(x,y,p);if(p.A>0)visible++;if(nx>115&&nx<185&&ny>100&&ny<210)minAlpha=Math.Min(minAlpha,p.A);}
   }
   Console.WriteLine("Diagnostic: mask="+n+", visible="+visible+", middleMin="+minAlpha+", transparent="+transparent);
   if(transparent==0||visible==0||minAlpha<240)throw new Exception("Generated transparency or central interior failed validation");
   output.Save(System.IO.Path.Combine(dir,"rear_hair_hidden_fill.png"));mask.Save(System.IO.Path.Combine(dir,"hidden_fill_mask.png"));
   Console.WriteLine("Mask native pixels="+n+", generated fill pixels="+visible+", middle minimum alpha="+minAlpha+", original transparent pixels="+transparent);
  }
 }
}
'@
[HairFill]::Run($PSScriptRoot)

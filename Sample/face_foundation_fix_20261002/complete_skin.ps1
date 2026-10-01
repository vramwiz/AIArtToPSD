# Windows PowerShell 5.1. Combine generated scalp with the existing lower face, without resampling.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
public static class SkinFoundation {
 static Color At(Bitmap b,int x,int y){return x<0||y<0||x>=b.Width||y>=b.Height?Color.Transparent:b.GetPixel(x,y);}
 public static void Run(string dir,int gx,int gy){
  using(Bitmap oldCrop=new Bitmap(System.IO.Path.Combine(dir,"face_before.png")))
  using(Bitmap genCrop=new Bitmap(System.IO.Path.Combine(dir,"skin_resampled_app.png")))
  using(Bitmap old=new Bitmap(272,255,PixelFormat.Format32bppArgb))
  using(Bitmap gen=new Bitmap(272,255,PixelFormat.Format32bppArgb))
  using(Bitmap result=new Bitmap(272,255,PixelFormat.Format32bppArgb)){
   for(int y=0;y<255;y++)for(int x=0;x<272;x++){
    old.SetPixel(x,y,At(oldCrop,x-74,y-87));gen.SetPixel(x,y,At(genCrop,x-gx,y-gy));
   }
   int lowerChanges=0,skinAdded=0,holes=0;
   for(int y=0;y<255;y++)for(int x=0;x<272;x++){
    Color o=old.GetPixel(x,y),g=gen.GetPixel(x,y),p;
    if(y>=200)p=o;
    else if(y<180)p=g;
    else{
     double w=(y-180)/20.0;w=w*w*(3-2*w);
     if(o.A==0){
      double edge=Math.Max(0.0,Math.Min(1.0,(200-y)/10.0));
      p=Color.FromArgb((int)Math.Round(g.A*edge),g.R,g.G,g.B);
     }else if(g.A==0){p=o;}
     else{
      p=Color.FromArgb((int)Math.Round(g.A*(1-w)+o.A*w),(int)Math.Round(g.R*(1-w)+o.R*w),(int)Math.Round(g.G*(1-w)+o.G*w),(int)Math.Round(g.B*(1-w)+o.B*w));
     }
    }
    // Preserve the original small nose feature and blend its surrounding plain skin.
    double noseDistance=Math.Sqrt((x-145)*(x-145)+(y-180)*(y-180));
    if(noseDistance<12 && o.A>240 && p.A>240){double w=Math.Max(0,Math.Min(1,(12-noseDistance)/4));p=Color.FromArgb(p.A,(int)Math.Round(p.R*(1-w)+o.R*w),(int)Math.Round(p.G*(1-w)+o.G*w),(int)Math.Round(p.B*(1-w)+o.B*w));}
    result.SetPixel(x,y,p);if(y>=200&&p.ToArgb()!=o.ToArgb())lowerChanges++;
    if(o.A==0&&p.A>128)skinAdded++;
   }
   // Two original white chin highlights were incorrectly excluded by the prior warm-skin classifier.
   using(Bitmap reference=new Bitmap(System.IO.Path.Combine(dir,"head_reference.png"))){
    foreach(Point q in new Point[]{new Point(164,225),new Point(161,227)}){
     if(result.GetPixel(q.X,q.Y).A!=0||reference.GetPixel(q.X,q.Y).A<240)throw new Exception("Unexpected chin highlight source");
     result.SetPixel(q.X,q.Y,reference.GetPixel(q.X,q.Y));
    }
   }
   // The central scalp-to-face region must not contain transparent gaps.
   for(int y=65;y<210;y++)for(int x=115;x<180;x++)if(result.GetPixel(x,y).A<240)holes++;
   if(lowerChanges!=0||holes!=0)throw new Exception("Lower-face preservation or scalp continuity failed");
   result.Save(System.IO.Path.Combine(dir,"face_completed.png"));old.Save(System.IO.Path.Combine(dir,"face_before_canvas.png"));gen.Save(System.IO.Path.Combine(dir,"generated_canvas.png"));
   System.IO.File.WriteAllText(System.IO.Path.Combine(dir,"preflight.json"),"{\"lowerFaceStartCanvasY\":219,\"lowerFaceRGBAMismatchesBeforeHighlightRestoration\":"+lowerChanges+",\"restoredOriginalChinHighlightPixels\":2,\"addedOpaqueSkinPixels\":"+skinAdded+",\"centralScalpFaceLowAlphaPixels\":"+holes+"}");
   using(Bitmap review=new Bitmap(1088,550))using(Graphics graphics=Graphics.FromImage(review))using(Font f=new Font("Arial",14)){
    graphics.Clear(Color.White);graphics.InterpolationMode=System.Drawing.Drawing2D.InterpolationMode.NearestNeighbor;graphics.PixelOffsetMode=System.Drawing.Drawing2D.PixelOffsetMode.Half;
    Bitmap[] imgs={old,result};string[] titles={"Before: missing forehead","Corrected: continuous skin foundation"};
    for(int i=0;i<2;i++){int l=i*544;graphics.DrawString(titles[i],f,Brushes.Black,l+8,5);for(int y=0;y<510;y+=16)for(int x=0;x<544;x+=16)graphics.FillRectangle(((x/16+y/16)%2==0)?Brushes.LightGray:Brushes.White,l+x,y+30,16,16);graphics.DrawImage(imgs[i],new Rectangle(l,30,544,510),0,0,272,255,GraphicsUnit.Pixel);}
    review.Save(System.IO.Path.Combine(dir,"skin_review.png"));
   }
  }
 }
}
'@
$l=Get-Content (Join-Path $PSScriptRoot 'resampled_layer.json') -Raw -Encoding UTF8|ConvertFrom-Json
[SkinFoundation]::Run($PSScriptRoot,($l.bounds.left-366),($l.bounds.top-19))
Get-Content (Join-Path $PSScriptRoot 'preflight.json') -Raw

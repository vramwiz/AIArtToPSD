#requires -Version 7.0
param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing.Common,System.Drawing.Primitives,System.Private.Windows.GdiPlus,System.Private.Windows.Core -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.IO;
public static class BlondeFaceAssets {
  static Bitmap Resize(Bitmap source, Rectangle crop, int width, int height) {
    Bitmap output = new Bitmap(width,height,PixelFormat.Format32bppArgb);
    using(Graphics graphics=Graphics.FromImage(output)) {
      graphics.CompositingMode=CompositingMode.SourceCopy;
      graphics.InterpolationMode=InterpolationMode.HighQualityBicubic;
      graphics.PixelOffsetMode=PixelOffsetMode.HighQuality;
      graphics.DrawImage(source,new Rectangle(0,0,width,height),crop,GraphicsUnit.Pixel);
    }
    return output;
  }
  static double Weight(int x,int y,Rectangle region) {
    if(!region.Contains(x,y)) return 0;
    double edge=Math.Min(Math.Min(x-region.Left+0.5,region.Right-x-0.5),Math.Min(y-region.Top+0.5,region.Bottom-y-0.5));
    return Math.Min(1.0,edge/2.0);
  }
  static void Part(Bitmap original,Bitmap features,string name,Rectangle crop,Rectangle bounds,string directory) {
    using(Bitmap mask=Resize(features,crop,bounds.Width,bounds.Height))
    using(Bitmap output=new Bitmap(bounds.Width,bounds.Height,PixelFormat.Format32bppArgb)) {
      for(int y=0;y<bounds.Height;y++) for(int x=0;x<bounds.Width;x++) {
        Color source=original.GetPixel(bounds.Left+x,bounds.Top+y);
        int alpha=mask.GetPixel(x,y).A;
        if(alpha<2) alpha=0;
        if(name=="brows") alpha=alpha<8 ? 0 : Math.Min(255,alpha*2);
        if(name=="mouth") alpha=alpha<2 ? 0 : Math.Min(255,alpha*6);
        output.SetPixel(x,y,Color.FromArgb(alpha,source.R,source.G,source.B));
      }
      output.Save(Path.Combine(directory,name+".png"),ImageFormat.Png);
    }
  }
  public static void Build(string root) {
    string directory=Path.Combine(root,"prepared"); Directory.CreateDirectory(directory);
    using(Bitmap original=new Bitmap(Path.Combine(root,"original.png")))
    using(Bitmap generated=new Bitmap(Path.Combine(root,"generated-base.png")))
    using(Bitmap features=new Bitmap(Path.Combine(root,"generated-features.png")))
    using(Bitmap skin=Resize(generated,new Rectangle(0,0,generated.Width,generated.Height),original.Width,original.Height))
    using(Bitmap output=new Bitmap(original.Width,original.Height,PixelFormat.Format32bppArgb)) {
      Rectangle[] regions={new Rectangle(296,166,61,47),new Rectangle(388,166,60,47),new Rectangle(297,142,59,25),new Rectangle(386,141,57,26),new Rectangle(356,231,32,14)};
      for(int y=0;y<original.Height;y++) for(int x=0;x<original.Width;x++) {
        Color source=original.GetPixel(x,y); double weight=0;
        foreach(Rectangle region in regions) weight=Math.Max(weight,Weight(x,y,region));
        if(weight==0) output.SetPixel(x,y,Color.FromArgb(255,source.R,source.G,source.B));
        else {
          Color fill=skin.GetPixel(x,y);
          output.SetPixel(x,y,Color.FromArgb(255,(int)Math.Round(source.R*(1-weight)+fill.R*weight),(int)Math.Round(source.G*(1-weight)+fill.G*weight),(int)Math.Round(source.B*(1-weight)+fill.B*weight)));
        }
      }
      output.Save(Path.Combine(directory,"base.png"),ImageFormat.Png);
      Part(original,features,"eyes",new Rectangle(327,263,289,77),new Rectangle(293,167,155,41),directory);
      Part(original,features,"brows",new Rectangle(351,216,239,27),new Rectangle(299,142,140,24),directory);
      Part(original,features,"mouth",new Rectangle(449,388,47,13),new Rectangle(358,233,28,10),directory);
    }
  }
}
'@
[BlondeFaceAssets]::Build($Root)
Get-ChildItem -LiteralPath (Join-Path $Root 'prepared') -Filter '*.png' | Select-Object Name,Length

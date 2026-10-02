#requires -Version 7.0
param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing.Common,System.Drawing.Primitives,System.Private.Windows.GdiPlus,System.Private.Windows.Core -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
public static class ExpressionAssets {
  static Bitmap sheet, prepared, face;
  public static void Begin(string root,string kind) {
    sheet=new Bitmap(Path.Combine(root,"generated-"+kind+".png"));
    prepared=new Bitmap(sheet.Width,sheet.Height,PixelFormat.Format32bppArgb);
    face=new Bitmap(Path.Combine(root,"input-base.png"));
    for(int y=0;y<sheet.Height;y++) for(int x=0;x<sheet.Width;x++) {
      Color p=sheet.GetPixel(x,y); int a=p.A;
      if(a<=(kind=="brows"?15:1)) a=0;
      prepared.SetPixel(x,y,Color.FromArgb(a,p.R,p.G,p.B));
    }
  }
  public static void HairOcclusion(int l,int t,int r,int b,int dl,int dt,int dr,int db) {
    for(int y=t;y<b;y++) for(int x=l;x<r;x++) {
      int xx=dl+(int)((x-l+0.5)*(dr-dl)/(r-l));
      int yy=dt+(int)((y-t+0.5)*(db-dt)/(b-t));
      Color p=prepared.GetPixel(x,y);
      Color skin=face.GetPixel(xx,yy);
      // Character-specific blonde hair / pink skin discrimination in the brow ROI.
      bool exposedSkin=skin.R>150 && skin.G>125 && skin.R-skin.G>=12 && skin.G-skin.B<18;
      if(!exposedSkin) prepared.SetPixel(x,y,Color.FromArgb(0,p.R,p.G,p.B));
    }
  }
  static Bitmap Area(Rectangle crop,int dw,int dh) {
    Bitmap output=new Bitmap(dw,dh,PixelFormat.Format32bppArgb);
    double sx=(double)crop.Width/dw,sy=(double)crop.Height/dh;
    for(int y=0;y<dh;y++) for(int x=0;x<dw;x++) {
      double x0=crop.Left+x*sx,x1=crop.Left+(x+1)*sx;
      double y0=crop.Top+y*sy,y1=crop.Top+(y+1)*sy;
      double a=0,red=0,green=0,blue=0;
      for(int yy=(int)Math.Floor(y0);yy<(int)Math.Ceiling(y1);yy++)
        for(int xx=(int)Math.Floor(x0);xx<(int)Math.Ceiling(x1);xx++) {
          double weight=(Math.Min(x1,xx+1.0)-Math.Max(x0,xx))*(Math.Min(y1,yy+1.0)-Math.Max(y0,yy))/(sx*sy);
          Color p=prepared.GetPixel(xx,yy); double alpha=p.A*weight;
          a+=alpha; red+=p.R*alpha; green+=p.G*alpha; blue+=p.B*alpha;
        }
      int aa=Math.Max(0,Math.Min(255,(int)Math.Round(a)));
      if(aa>0) output.SetPixel(x,y,Color.FromArgb(aa,(int)Math.Round(red/a),(int)Math.Round(green/a),(int)Math.Round(blue/a)));
    }
    return output;
  }
  public static void Part(string filename,int l,int t,int r,int b,int width,int height) {
    using(Bitmap part=Area(new Rectangle(l,t,r-l,b-t),width,height)) part.Save(filename,ImageFormat.Png);
  }
  public static void End(string filename) {
    prepared.Save(filename,ImageFormat.Png);prepared.Dispose();sheet.Dispose();face.Dispose();
  }
  public static Bitmap Foundation(string root,string kind) {
    Bitmap canvas=new Bitmap(Path.Combine(root,"input-base.png"));
    using(Graphics g=Graphics.FromImage(canvas)) {
      foreach(string key in new string[]{"mouth","brows","eyes"}) {
        if(kind==key || (kind=="mouths" && key=="mouth")) continue;
        int x=key=="mouth"?358:key=="eyes"?293:299;
        int y=key=="mouth"?233:key=="eyes"?167:142;
        using(Bitmap part=new Bitmap(Path.Combine(root,"input-"+key+".png"))) g.DrawImageUnscaled(part,x,y);
      }
    }
    return canvas;
  }
  public static void Review(string root,string kind,string[] labels,string[] files,int[] left,int[] top) {
    int columns=3,rows=(files.Length+columns-1)/columns;
    using(Bitmap output=new Bitmap(1200,rows*370))
    using(Graphics g=Graphics.FromImage(output))
    using(Font font=new Font("Yu Gothic UI",16))
    using(Bitmap foundation=Foundation(root,kind)) {
      g.Clear(Color.FromArgb(225,225,225));
      for(int i=0;i<files.Length;i++) {
        using(Bitmap canvas=(Bitmap)foundation.Clone())
        using(Graphics cg=Graphics.FromImage(canvas))
        using(Bitmap part=new Bitmap(files[i])) {
          cg.DrawImageUnscaled(part,left[i],top[i]);
          int x=(i%columns)*400,y=(i/columns)*370;
          g.DrawString(labels[i],font,Brushes.Black,x+12,y+6);
          g.InterpolationMode=InterpolationMode.NearestNeighbor;
          g.DrawImage(canvas,new Rectangle(x,y+35,400,330),new Rectangle(270,120,200,165),GraphicsUnit.Pixel);
        }
      }
      output.Save(Path.Combine(root,kind+"-draft-review.png"),ImageFormat.Png);
    }
  }
}
'@
$layout=Get-Content -LiteralPath (Join-Path $Root 'layout.json') -Raw|ConvertFrom-Json
$preparedDir=Join-Path $Root 'prepared'
New-Item -ItemType Directory -Path $preparedDir -Force|Out-Null
foreach($kind in @('mouths','eyes','brows')){
 [ExpressionAssets]::Begin($Root,$kind)
 $cells=@($layout|Where-Object kind -eq $kind)
 foreach($cell in $cells){
  $s=$cell.sourceBounds;$b=$cell.bounds
  if($kind -eq 'brows'){[ExpressionAssets]::HairOcclusion($s[0],$s[1],$s[2],$s[3],$b[0],$b[1],$b[2],$b[3])}
  [ExpressionAssets]::Part((Join-Path $preparedDir $cell.file),$s[0],$s[1],$s[2],$s[3],($b[2]-$b[0]),($b[3]-$b[1]))
 }
 [ExpressionAssets]::End((Join-Path $Root ('prepared-'+$kind+'.png')))
 $key=if($kind -eq 'mouths'){'mouth'}else{$kind}
 $labels=@('00 原画')+@($cells|Where-Object importGenerated|ForEach-Object {('{0:00} {1}' -f ($_.index+1),$_.label)})
 $files=@((Join-Path $Root ('input-'+$key+'.png')))+@($cells|Where-Object importGenerated|ForEach-Object {Join-Path $preparedDir $_.file})
 $x=if($kind -eq 'mouths'){358}elseif($kind -eq 'eyes'){293}else{299}
 $y=if($kind -eq 'mouths'){233}elseif($kind -eq 'eyes'){167}else{142}
 $left=@($x)+@($cells|Where-Object importGenerated|ForEach-Object {$_.bounds[0]})
 $top=@($y)+@($cells|Where-Object importGenerated|ForEach-Object {$_.bounds[1]})
 [ExpressionAssets]::Review($Root,$kind,[string[]]$labels,[string[]]$files,[int[]]$left,[int[]]$top)
}
Get-ChildItem -LiteralPath $preparedDir -Filter '*.png'|Select-Object Name,Length

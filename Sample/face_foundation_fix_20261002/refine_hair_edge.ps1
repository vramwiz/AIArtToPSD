# Windows PowerShell 5.1. Source-specific edge matting, limited to the existing bangs/skin boundary.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
public static class BangEdge {
 static Color At(Bitmap b,int x,int y){return x<0||y<0||x>=b.Width||y>=b.Height?Color.Transparent:b.GetPixel(x,y);}
 static int Dist(Bitmap mask,int x,int y,int radius){int d=radius+1;for(int yy=-radius;yy<=radius;yy++)for(int xx=-radius;xx<=radius;xx++)if(At(mask,x+xx,y+yy).A>0)d=Math.Min(d,Math.Max(Math.Abs(xx),Math.Abs(yy)));return d;}
 static int Byte(double d){return Math.Max(0,Math.Min(255,(int)Math.Round(d)));}
 public static void Run(string dir){
  using(Bitmap src=new Bitmap(System.IO.Path.Combine(dir,"head_reference.png")))
  using(Bitmap front=new Bitmap(System.IO.Path.Combine(dir,"front_before_canvas.png")))
  using(Bitmap skin=new Bitmap(System.IO.Path.Combine(dir,"face_before_canvas.png")))
  using(Bitmap result=(Bitmap)front.Clone()){
   int[,] ds=new int[272,255],df=new int[272,255];
   for(int y=65;y<195;y++)for(int x=55;x<235;x++){ds[x,y]=Dist(skin,x,y,4);df[x,y]=Dist(front,x,y,4);}
   int edited=0,added=0;
   for(int y=75;y<185;y++)for(int x=65;x<228;x++){
    Color prev=front.GetPixel(x,y),c=src.GetPixel(x,y);
    if(!((prev.A>0&&ds[x,y]<=3)||(skin.GetPixel(x,y).A>0&&df[x,y]<=2)))continue;
    Color background=Color.Empty,foreground=Color.Empty;int bd=10000,fd=10000;
    for(int dy=-12;dy<=12;dy++)for(int dx=-12;dx<=12;dx++){
     int nx=x+dx,ny=y+dy;if(nx<55||nx>=235||ny<65||ny>=195)continue;
     Color s=skin.GetPixel(nx,ny),f=front.GetPixel(nx,ny);int distance=dx*dx+dy*dy;
     if(s.A>240&&s.R-s.B>35&&s.R>180&&df[nx,ny]>=4&&distance<bd){background=s;bd=distance;}
     if(f.A>240&&f.B>=f.R&&ds[nx,ny]>=2&&distance<fd){foreground=f;fd=distance;}
    }
    if(background.IsEmpty||foreground.IsEmpty)continue;
    double bg=background.R-background.B,fg=foreground.R-foreground.B;
    double coverage=Math.Max(0,Math.Min(1,(bg-(c.R-c.B))/(bg-fg)));
    Color p;
    if(coverage<0.04)p=Color.Transparent;
    else if(coverage>=0.98)p=c;
    else p=Color.FromArgb(Byte(c.A*coverage),Byte((c.R-(1-coverage)*background.R)/coverage),Byte((c.G-(1-coverage)*background.G)/coverage),Byte((c.B-(1-coverage)*background.B)/coverage));
    result.SetPixel(x,y,p);if(p.ToArgb()!=prev.ToArgb()){edited++;if(prev.A==0&&p.A>0)added++;}
   }
   result.Save(System.IO.Path.Combine(dir,"front_edge_refined.png"));
   System.IO.File.WriteAllText(System.IO.Path.Combine(dir,"edge_refinement.json"),"{\"changedBoundaryPixels\":"+edited+",\"recoveredHairEdgePixels\":"+added+",\"scope\":\"Only skin/front boundary within head-local x=65..227, y=75..184\"}");
  }
 }
}
'@
$e=Get-Content (Join-Path $PSScriptRoot 'export.json') -Raw -Encoding UTF8|ConvertFrom-Json
$r=Get-Content (Join-Path $e.data.directory 'request.json') -Raw -Encoding UTF8|ConvertFrom-Json
$l=@($r.layers|Where-Object name -eq '前髪・横髪（元画素）')[0];$a=@($r.assets|Where-Object assetId -eq $l.assetId)[0]
$crop=[Drawing.Bitmap]::FromFile((Join-Path $e.data.directory $a.path));$b=[Drawing.Bitmap]::new(272,255)
for($y=0;$y -lt $crop.Height;$y++){for($x=0;$x -lt $crop.Width;$x++){$b.SetPixel(($x+$l.bounds.left-366),($y+$l.bounds.top-19),$crop.GetPixel($x,$y))}}
$b.Save((Join-Path $PSScriptRoot 'front_before_canvas.png'),[Drawing.Imaging.ImageFormat]::Png);$b.Dispose();$crop.Dispose()
[BangEdge]::Run($PSScriptRoot)
Get-Content (Join-Path $PSScriptRoot 'edge_refinement.json') -Raw

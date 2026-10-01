# Windows PowerShell 5.1. Source-specific original-pixel partition; no resampling.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Collections.Generic;
public static class HairPartition {
 public static void Run(string folder) {
  using(Bitmap src=new Bitmap(System.IO.Path.Combine(folder,"head_source.png")))
  using(Bitmap face=new Bitmap(272,255,PixelFormat.Format32bppArgb))
  using(Bitmap front=new Bitmap(272,255,PixelFormat.Format32bppArgb))
  using(Bitmap rear=new Bitmap(272,255,PixelFormat.Format32bppArgb))
  using(Bitmap labels=new Bitmap(272,255,PixelFormat.Format32bppArgb))
  using(GraphicsPath path=new GraphicsPath()) {
   // Boundary follows the visible side-lock flow. Coordinates are specific to this head crop.
   path.AddPolygon(new Point[]{new Point(0,0),new Point(272,0),new Point(272,210),
    new Point(250,215),new Point(253,197),new Point(247,181),new Point(241,159),
    new Point(238,179),new Point(232,192),new Point(224,206),new Point(215,216),
    new Point(207,219),new Point(215,201),new Point(217,181),new Point(205,184),
    new Point(196,196),new Point(181,205),new Point(105,205),new Point(90,199),
    new Point(78,184),new Point(68,173),new Point(64,185),new Point(66,203),
    new Point(73,219),new Point(84,235),new Point(73,230),new Point(59,217),
    new Point(51,199),new Point(46,177),new Point(42,199),new Point(38,212),
    new Point(35,225),new Point(29,216),new Point(27,205),new Point(18,207),new Point(0,207)});
   int[] count=new int[3]; int mismatch=0;
   for(int y=0;y<255;y++)for(int x=0;x<272;x++) {
    Color p=src.GetPixel(x,y);if(p.A==0)continue;
    // Warm skin, including shaded ear/neck outlines, versus blue-gray hair. No other images may reuse this test.
    bool skin=(p.R-p.B>4 && p.R-p.G>0 && x>60 && x<232 && y>77);
    int k=skin?0:(path.IsVisible(x+0.5f,y+0.5f)?1:2);
    Bitmap dst=k==0?face:(k==1?front:rear);dst.SetPixel(x,y,p);count[k]++;
    labels.SetPixel(x,y,k==0?Color.FromArgb(p.A,255,180,130):(k==1?Color.FromArgb(p.A,75,170,255):Color.FromArgb(p.A,170,80,210)));
    if(dst.GetPixel(x,y).ToArgb()!=p.ToArgb())mismatch++;
   }
   bool[,] seen=new bool[272,255];
   for(int sy=0;sy<255;sy++)for(int sx=0;sx<272;sx++){
    if(seen[sx,sy]||front.GetPixel(sx,sy).A==0)continue;
    var queue=new Queue<Point>();var points=new List<Point>();queue.Enqueue(new Point(sx,sy));seen[sx,sy]=true;
    int minX=sx,maxX=sx,minY=sy,maxY=sy;
    while(queue.Count>0){Point q=queue.Dequeue();points.Add(q);minX=Math.Min(minX,q.X);maxX=Math.Max(maxX,q.X);minY=Math.Min(minY,q.Y);maxY=Math.Max(maxY,q.Y);
     for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){int x=q.X+dx,y=q.Y+dy;if(x<0||y<0||x>=272||y>=255||seen[x,y]||front.GetPixel(x,y).A==0)continue;seen[x,y]=true;queue.Enqueue(new Point(x,y));}
    }
    if(points.Count<100 && minX>75 && maxX<210 && minY>170){
     foreach(Point q in points){Color p=front.GetPixel(q.X,q.Y);face.SetPixel(q.X,q.Y,p);front.SetPixel(q.X,q.Y,Color.Transparent);labels.SetPixel(q.X,q.Y,Color.FromArgb(p.A,255,180,130));count[0]++;count[1]--;}
     Console.WriteLine("Face contour reassigned: "+points.Count+" pixels at "+minX+","+minY+" to "+maxX+","+maxY);
    }
   }
   face.Save(System.IO.Path.Combine(folder,"face_neck_original.png"));
   front.Save(System.IO.Path.Combine(folder,"front_hair_original.png"));
   rear.Save(System.IO.Path.Combine(folder,"rear_hair_visible_original.png"));
   labels.Save(System.IO.Path.Combine(folder,"partition_labels.png"));
   Console.WriteLine("face="+count[0]+" front="+count[1]+" rear="+count[2]+" copied-pixel mismatch="+mismatch);
   using(Bitmap review=new Bitmap(1088,1070))using(Graphics g=Graphics.FromImage(review)) {
    g.Clear(Color.White);g.InterpolationMode=InterpolationMode.NearestNeighbor;g.PixelOffsetMode=PixelOffsetMode.Half;
    Bitmap[] parts={src,front,face,rear};string[] titles={"Input", "Front hair (original pixels)","Face / neck (original pixels)","Visible rear hair (original pixels)"};
    using(Font font=new Font("Arial",14))for(int i=0;i<4;i++){
     int l=i%2*544,t=i/2*535;g.DrawString(titles[i],font,Brushes.Black,l+8,t+4);
     for(int yy=0;yy<510;yy+=16)for(int xx=0;xx<544;xx+=16)g.FillRectangle(((xx/16+yy/16)%2==0)?Brushes.LightGray:Brushes.White,l+xx,t+25+yy,16,16);
     g.DrawImage(parts[i],new Rectangle(l,t+25,544,510),0,0,272,255,GraphicsUnit.Pixel);
    }
    review.Save(System.IO.Path.Combine(folder,"partition_review.png"));
   }
  }
 }
}
'@
[HairPartition]::Run($PSScriptRoot)

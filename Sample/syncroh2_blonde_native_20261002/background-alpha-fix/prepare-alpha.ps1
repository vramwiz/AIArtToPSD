#requires -Version 7.0
param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing.Common,System.Drawing.Primitives,System.Private.Windows.GdiPlus,System.Private.Windows.Core,System.Collections -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
public static class BlondeBackgroundAlpha {
  public static void Build(string root) {
    string dir=Path.Combine(root,"background-alpha-fix");
    using(Bitmap source=new Bitmap(Path.Combine(root,"prepared","base.png")))
    using(Bitmap generated=new Bitmap(Path.Combine(dir,"generated-cutout.png")))
    using(Bitmap mask=new Bitmap(source.Width,source.Height,PixelFormat.Format32bppArgb))
    using(Bitmap output=new Bitmap(source.Width,source.Height,PixelFormat.Format32bppArgb)) {
      using(Graphics g=Graphics.FromImage(mask)) {
        g.CompositingMode=CompositingMode.SourceCopy;
        g.InterpolationMode=InterpolationMode.HighQualityBicubic;
        g.PixelOffsetMode=PixelOffsetMode.HighQuality;
        g.DrawImage(generated,new Rectangle(0,0,mask.Width,mask.Height));
      }
      int w=source.Width,h=source.Height,n=w*h;
      Color[] pixels=new Color[n]; bool[] white=new bool[n],visited=new bool[n],bg=new bool[n];
      for(int y=0;y<h;y++) for(int x=0;x<w;x++) {
        int p=y*w+x; Color c=source.GetPixel(x,y); pixels[p]=c;
        white[p]=c.R>=250 && c.G>=250 && c.B>=250;
      }
      Queue<int> queue=new Queue<int>(); List<int> region=new List<int>();
      List<string> report=new List<string>(); report.Add("count,left,top,right,bottom,predicted_fraction,removed");
      int[] dx={-1,1,0,0},dy={0,0,-1,1};
      for(int start=0;start<n;start++) {
        if(!white[start] || visited[start]) continue;
        region.Clear(); queue.Enqueue(start); visited[start]=true;
        bool border=false; int predictedBackground=0,rl=w,rt=h,rr=0,rb=0;
        while(queue.Count>0) {
          int p=queue.Dequeue(),x=p%w,y=p/w; region.Add(p);
          rl=Math.Min(rl,x); rt=Math.Min(rt,y); rr=Math.Max(rr,x+1); rb=Math.Max(rb,y+1);
          if(x==0 || y==0 || x==w-1 || y==h-1) border=true;
          if(mask.GetPixel(x,y).A<8) predictedBackground++;
          for(int d=0;d<4;d++) {
            int xx=x+dx[d],yy=y+dy[d];
            if(xx<0 || yy<0 || xx>=w || yy>=h) continue;
            int next=yy*w+xx;
            if(white[next] && !visited[next]) { visited[next]=true; queue.Enqueue(next); }
          }
        }
        // Interior white garments are protected by the generated character mask.
        // These two enclosed curl gaps were confirmed against the original illustration.
        bool curlGap=(rl==191 && rt==401 && rr==197 && rb==427)
          || (rl==545 && rt==396 && rr==551 && rb==428);
        bool remove=border || curlGap || (region.Count>=4 && predictedBackground>=region.Count*0.75);
        if(region.Count>=8) report.Add(String.Format(System.Globalization.CultureInfo.InvariantCulture,"{0},{1},{2},{3},{4},{5},{6}",region.Count,rl,rt,rr,rb,(double)predictedBackground/region.Count,remove));
        if(remove) foreach(int p in region) bg[p]=true;
      }
      for(int y=0;y<h;y++) for(int x=0;x<w;x++) {
        int p=y*w+x; Color c=pixels[p]; int alpha=bg[p]?0:255;
        if(!bg[p]) {
          bool edge=false;
          for(int yy=Math.Max(0,y-1);yy<=Math.Min(h-1,y+1);yy++)
            for(int xx=Math.Max(0,x-1);xx<=Math.Min(w-1,x+1);xx++) edge|=bg[yy*w+xx];
          // Refine only the bright matte edge, preserving opaque character interiors.
          int minimum=Math.Min(c.R,Math.Min(c.G,c.B));
          if(edge && minimum>229) alpha=Math.Min(255,(255-minimum)*10);
        }
        int red=c.R,green=c.G,blue=c.B;
        if(alpha>0 && alpha<255) {
          // Remove the original white matte from the antialiased edge only.
          red=Math.Max(0,Math.Min(255,(red*255-255*(255-alpha)+alpha/2)/alpha));
          green=Math.Max(0,Math.Min(255,(green*255-255*(255-alpha)+alpha/2)/alpha));
          blue=Math.Max(0,Math.Min(255,(blue*255-255*(255-alpha)+alpha/2)/alpha));
        }
        output.SetPixel(x,y,Color.FromArgb(alpha,red,green,blue));
      }
      output.Save(Path.Combine(dir,"base-transparent.png"),ImageFormat.Png);
      File.WriteAllLines(Path.Combine(dir,"white-regions.csv"),report);
    }
  }
}
'@
[BlondeBackgroundAlpha]::Build($Root)

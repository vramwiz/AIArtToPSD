# Windows PowerShell 5.1. Read-only pixel measurements; no image editing.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
public static class FeatureSize {
    public static object Measure(string path,int minX,int maxX,int threshold) {
        using(var b=new Bitmap(path)) {
            int count=0,x0=b.Width,y0=b.Height,x1=-1,y1=-1;
            for(int y=0;y<b.Height;y++) for(int x=minX;x<Math.Min(maxX,b.Width);x++) {
                if(b.GetPixel(x,y).A<=threshold) continue;
                count++;x0=Math.Min(x0,x);x1=Math.Max(x1,x);y0=Math.Min(y0,y);y1=Math.Max(y1,y);
            }
            return new {threshold=threshold,count=count,bboxInclusive=new[]{x0,y0,x1,y1},
                width=count>0?x1-x0+1:0,height=count>0?y1-y0+1:0,
                bboxCenter=new[]{(x0+x1)/2.0,(y0+y1)/2.0}};
        }
    }
}
'@
$report = [ordered]@{method='Alpha support bounds. Original references are previous source-pixel cutouts including approximate margins, not exact semantic feature bounds.';parts=[ordered]@{}}
foreach($entry in @(
    @('mouth_original_reference','..\face_trial_20261001\mouth.png',0,1024),
    @('mouth_generated','mouth.png',0,1024),
    @('brow_left_original_visible_reference','..\face_trial_20261001\brow_left.png',0,1024),
    @('brow_right_original_visible_reference','..\face_trial_20261001\brow_right.png',0,1024),
    @('brow_left_generated','brows_pair.png',0,500),
    @('brow_right_generated','brows_pair.png',500,1024)
)) {
    $path = Join-Path $PSScriptRoot $entry[1]
    $report.parts[$entry[0]] = @([FeatureSize]::Measure($path,$entry[2],$entry[3],16),[FeatureSize]::Measure($path,$entry[2],$entry[3],128))
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'feature_sizes.json') -Encoding UTF8
$report | ConvertTo-Json -Depth 8 -Compress

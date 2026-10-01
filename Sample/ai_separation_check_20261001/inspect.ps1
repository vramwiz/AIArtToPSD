param([switch]$IncludeRetry, [string]$ReportName = 'verification.json')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
# Run with Windows PowerShell 5.1 (powershell.exe), using .NET Framework System.Drawing.
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
public static class LayerCheck20261001 {
    public static object Stats(string path) {
        using (var b = new Bitmap(path)) {
            int[] limits = {0,16,128,240};
            var rows = new object[limits.Length];
            for (int i=0;i<limits.Length;i++) {
                int count=0, outside=0, x0=b.Width,y0=b.Height,x1=-1,y1=-1;
                for(int y=0;y<b.Height;y++) for(int x=0;x<b.Width;x++) {
                    if(b.GetPixel(x,y).A<=limits[i]) continue;
                    count++; x0=Math.Min(x0,x);y0=Math.Min(y0,y);x1=Math.Max(x1,x);y1=Math.Max(y1,y);
                    if(x<430 || x>=505 || y<150 || y>=215) outside++;
                }
                rows[i]=new {alphaGreaterThan=limits[i],count=count,bboxInclusive=new[]{x0,y0,x1,y1},outsideGenerousEyeRegion=outside};
            }
            int[,] points={{400,180},{420,180},{500,180},{470,130},{470,230},{470,180},{540,170},{511,222}};
            var samples=new object[points.GetLength(0)];
            for(int i=0;i<points.GetLength(0);i++) {
                int x=points[i,0],y=points[i,1]; var c=b.GetPixel(x,y);
                samples[i]=new {x=x,y=y,rgba=new[]{(int)c.R,(int)c.G,(int)c.B,(int)c.A}};
            }
            return new {width=b.Width,height=b.Height,alpha=rows,samples=samples};
        }
    }
}
'@
$root = $PSScriptRoot
$files = [ordered]@{
    source = Join-Path $root '..\character_neutral.png'
    base_generated = Join-Path $root 'base_generated.png'
    eye_left_rejected = Join-Path $root 'eye_left_rejected.png'
    previous_eye_cutout_reference_only = Join-Path $root '..\face_trial_20261001\eye_left.png'
}
$results = [ordered]@{}
if ($IncludeRetry) {
    $files['base_no_glow_v2'] = Join-Path $root 'base_no_glow_v2.png'
    $files['eye_left_v2_rejected'] = Join-Path $root 'eye_left_v2_rejected.png'
}
foreach ($entry in $files.GetEnumerator()) {
    $results[$entry.Key] = [ordered]@{
        sha256 = (Get-FileHash -LiteralPath $entry.Value -Algorithm SHA256).Hash
        stats = [LayerCheck20261001]::Stats($entry.Value)
    }
}
$results | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $root $ReportName) -Encoding UTF8
foreach ($entry in $results.GetEnumerator()) {
    [pscustomobject]@{name=$entry.Key; alpha=$entry.Value.stats.alpha} | ConvertTo-Json -Depth 6 -Compress
}

# Windows PowerShell 5.1. Character-specific alpha masking; app does final resampling.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
public static class BrowMask {
 public static int Copy(Bitmap src,Bitmap dst,Bitmap mask,int l,int t) {
  int kept=0;
  for(int y=0;y<160;y++) for(int x=0;x<540;x++) {
   Color p=src.GetPixel(l+x,t+y);
   if(mask.GetPixel(x/5,y/5).A>0){dst.SetPixel(l+x,t+y,p);if(p.A>16)kept++;}
  }
  return kept;
 }
}
'@
$export=Get-Content (Join-Path $PSScriptRoot 'export.json') -Raw -Encoding UTF8|ConvertFrom-Json
$request=Get-Content (Join-Path $export.data.directory 'request.json') -Raw -Encoding UTF8|ConvertFrom-Json
$brow=@($request.layers|Where-Object name -eq '眉（両眉・元画素）')
if($brow.Count -ne 1 -or -not $brow[0].visible){throw 'Expected visible original brows'}
function Read-Layer($layer){
 $asset=$request.assets|Where-Object assetId -eq $layer.assetId
 return [Drawing.Bitmap]::FromFile((Join-Path $export.data.directory $asset.path))
}
$baseLayer=@($request.layers|Where-Object name -eq 'ベース（目・眉・口消去済み）')
if($baseLayer.Count -ne 1){throw 'Expected one approved base'}
$base=Read-Layer $baseLayer[0]
$mask=[Drawing.Bitmap]::new(108,32,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
for($y=0;$y -lt 32;$y++){for($x=0;$x -lt 108;$x++){
 $p=$base.GetPixel(($x+450),($y+129))
 # This blue-gray hair / warm skin discrimination applies ONLY to this approved base and small ROI.
 if($p.R -gt 145 -and ($p.R-$p.B) -gt 15 -and ($p.R-$p.G) -gt 5){$mask.SetPixel($x,$y,[Drawing.Color]::White)}
}}
$mask.Save((Join-Path $PSScriptRoot 'brow_visibility_mask.png'),[Drawing.Imaging.ImageFormat]::Png)
$base.Dispose()
$scans=Get-Content (Join-Path $PSScriptRoot 'alpha_measurements.json') -Raw -Encoding UTF8|ConvertFrom-Json
$states=@('normal','joy','anger','sadness','pleasure','troubled','screen_left_raised','screen_right_raised')
$labels=@('通常','喜','怒','哀','楽','困る','画面左上げ','画面右上げ')
# One baseline for both cells in each row, preserving their expression-related vertical differences.
$rowAnchors=@(163,403,639,857)
$sheet=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'brows_sheet.png'))
$masked=[Drawing.Bitmap]::new($sheet.Width,$sheet.Height,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
$measurements=@()
for($i=0;$i -lt 8;$i++){
 $b=$scans[$i].alphaScans|Where-Object threshold -eq 16
 $cx=($b.box[0]+$b.box[2])/2.0;$row=[int][Math]::Floor($i/2)
 $l=[int][Math]::Floor($cx-270+0.5);$t=$rowAnchors[$row]-80
 $source=@{left=$l;top=$t;right=($l+540);bottom=($t+160)}
 if($b.box[0] -lt $l -or $b.box[1] -lt $t -or $b.box[2] -gt $source.right -or $b.box[3] -gt $source.bottom){throw 'Brow exceeds crop'}
 $kept=[BrowMask]::Copy($sheet,$masked,$mask,$l,$t)
 if($kept -eq 0){throw 'Brow entirely hidden'}
 $measurements+=@{index=$i;state=$states[$i];label=$labels[$i];scale=0.2;sourceBounds=$source;bounds=@{left=450;top=129;right=558;bottom=161};rowAnchorY=$rowAnchors[$row];targetAnchor=@{x=504;y=145};visibleBoundsBeforeMask=$b.box;visiblePixelsBeforeMask=$b.count;visiblePixelsAfterMask=$kept}
}
$masked.Save((Join-Path $PSScriptRoot 'brows_sheet_masked.png'),[Drawing.Imaging.ImageFormat]::Png)
$measurements|ConvertTo-Json -Depth 10|Set-Content (Join-Path $PSScriptRoot 'measurements.json') -Encoding UTF8
$foundation=[Drawing.Bitmap]::new(1024,1536)
$fg=[Drawing.Graphics]::FromImage($foundation);$fg.Clear([Drawing.Color]::Transparent)
$layers=@($request.layers|Where-Object {$_.kind -eq 'image' -and $_.visible -and $_.layerId -ne $brow[0].layerId})
[array]::Reverse($layers)
foreach($layer in $layers){
 if($layer.hasMask -or $layer.opacity -ne 255){throw 'Unsupported diagnostic layer'}
 $img=Read-Layer $layer;$fg.DrawImageUnscaled($img,[int]$layer.bounds.left,[int]$layer.bounds.top);$img.Dispose()
}
$eyeGroup=@($request.layers|Where-Object name -eq '目差分6種（両目・確認用）')
$visibleEyes=@($request.layers|Where-Object {$_.kind -eq 'image' -and $_.visible -and ($_.parentId -eq $eyeGroup[0].layerId -or $_.name -eq '目（両目・元画素）')})
$referenceId=''
if($visibleEyes.Count -eq 0){
 $reference=@($request.layers|Where-Object {$_.parentId -eq $eyeGroup[0].layerId -and $_.name -eq '01 通常'})
 if($reference.Count -ne 1){throw 'Missing diagnostic eye reference'}
 $referenceId=$reference[0].layerId
 $img=Read-Layer $reference[0];$fg.DrawImageUnscaled($img,[int]$reference[0].bounds.left,[int]$reference[0].bounds.top);$img.Dispose()
}
$fg.Dispose()
@{diagnosticOnlyEyeLayerId=$referenceId;actualEyeVisibilityChanged=$false;maskCanvasBounds=@{left=450;top=129;right=558;bottom=161}}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $PSScriptRoot 'review_context.json') -Encoding UTF8
$review=[Drawing.Bitmap]::new(960,1408)
$rg=[Drawing.Graphics]::FromImage($review);$rg.Clear([Drawing.Color]::White)
$font=[Drawing.Font]::new('Yu Gothic UI',16)
foreach($m in $measurements){
 $canvas=$foundation.Clone();$cg=[Drawing.Graphics]::FromImage($canvas)
 $cg.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
 $cg.DrawImage($masked,[Drawing.Rectangle]::new(450,129,108,32),[int]$m.sourceBounds.left,[int]$m.sourceBounds.top,540,160,[Drawing.GraphicsUnit]::Pixel);$cg.Dispose()
 $x=($m.index%2)*480;$y=[int][Math]::Floor($m.index/2)*352
 $rg.DrawString(('{0:00} {1}' -f ($m.index+1),$m.label),$font,[Drawing.Brushes]::Black,($x+12),($y+4))
 $rg.DrawImage($canvas,[Drawing.Rectangle]::new($x,($y+32),480,320),380,110,240,160,[Drawing.GraphicsUnit]::Pixel);$canvas.Dispose()
}
$review.Save((Join-Path $PSScriptRoot 'draft_comparison.png'),[Drawing.Imaging.ImageFormat]::Png)
$rg.Dispose();$review.Dispose();$font.Dispose();$sheet.Dispose();$masked.Dispose();$foundation.Dispose();$mask.Dispose()
$measurements|ForEach-Object {[PSCustomObject]@{state=$_.state;before=$_.visiblePixelsBeforeMask;after=$_.visiblePixelsAfterMask}}|Format-Table

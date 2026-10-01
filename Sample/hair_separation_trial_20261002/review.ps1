# Windows PowerShell 5.1. Compose application-resampled output without further resizing.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$parts=Get-Content (Join-Path $PSScriptRoot 'app_parts.json') -Raw -Encoding UTF8|ConvertFrom-Json
function FullPart($key){
 $p=@($parts|Where-Object key -eq $key)[0]
 $src=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot $p.file));$dst=[Drawing.Bitmap]::new(272,255)
 $g=[Drawing.Graphics]::FromImage($dst);$g.CompositingMode=[Drawing.Drawing2D.CompositingMode]::SourceCopy
 $g.DrawImageUnscaled($src,($p.bounds.left-366),($p.bounds.top-19));$g.Dispose();$src.Dispose();return ,$dst
}
$front=FullPart 'front';$face=FullPart 'face';$visible=FullPart 'rear-visible';$fill=FullPart 'rear-fill'
$rear=[Drawing.Bitmap]::new(272,255);$g=[Drawing.Graphics]::FromImage($rear);$g.DrawImageUnscaled($fill,0,0);$g.DrawImageUnscaled($visible,0,0);$g.Dispose()
$head=$rear.Clone();$g=[Drawing.Graphics]::FromImage($head);$g.DrawImageUnscaled($face,0,0);$g.DrawImageUnscaled($front,0,0);$g.Dispose()
$source=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'head_source.png'))
$rear.Save((Join-Path $PSScriptRoot 'rear_completed_app.png'),[Drawing.Imaging.ImageFormat]::Png)
$head.Save((Join-Path $PSScriptRoot 'recomposed_head_app.png'),[Drawing.Imaging.ImageFormat]::Png)
$review=[Drawing.Bitmap]::new(1088,1100);$g=[Drawing.Graphics]::FromImage($review);$g.Clear([Drawing.Color]::White)
$g.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::NearestNeighbor;$g.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::Half
$font=[Drawing.Font]::new('Arial',14)
$imgs=@($source,$head,$rear,$front);$titles=@('Before','Separated + completed (app outputs)','Rear hair only: visible + completed','Front / side hair only')
for($i=0;$i -lt 4;$i++){
 $l=($i%2)*544;$t=[int][Math]::Floor($i/2)*550
 $g.DrawString($titles[$i],$font,[Drawing.Brushes]::Black,($l+8),($t+5))
 for($y=0;$y -lt 510;$y+=16){for($x=0;$x -lt 544;$x+=16){$br=if((($x/16+$y/16)%2) -eq 0){[Drawing.Brushes]::LightGray}else{[Drawing.Brushes]::White};$g.FillRectangle($br,($l+$x),($t+32+$y),16,16)}}
 $g.DrawImage($imgs[$i],[Drawing.Rectangle]::new($l,($t+32),544,510),0,0,272,255,[Drawing.GraphicsUnit]::Pixel)
}
$review.Save((Join-Path $PSScriptRoot 'hair_review.png'),[Drawing.Imaging.ImageFormat]::Png)
$g.Dispose();$review.Dispose();$font.Dispose()
foreach($b in @($source,$head,$rear,$front,$face,$visible,$fill)){$b.Dispose()}

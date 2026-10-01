# Windows PowerShell 5.1. Diagnostic only: compose hair normally and translated over the completed skin.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$e=Get-Content (Join-Path $PSScriptRoot 'export.json') -Raw -Encoding UTF8|ConvertFrom-Json
$r=Get-Content (Join-Path $e.data.directory 'request.json') -Raw -Encoding UTF8|ConvertFrom-Json
function DrawLayer($graphics,$id,$dx=0,$dy=0){
 $l=@($r.layers|Where-Object layerId -eq $id)[0];$a=@($r.assets|Where-Object assetId -eq $l.assetId)[0];$img=[Drawing.Bitmap]::FromFile((Join-Path $e.data.directory $a.path))
 $graphics.DrawImageUnscaled($img,($l.bounds.left-366+$dx),($l.bounds.top-19+$dy));$img.Dispose()
}
$ctx=Get-Content (Join-Path $PSScriptRoot '../hair_separation_trial_20261002/context.json') -Raw -Encoding UTF8|ConvertFrom-Json
$skin=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'face_completed.png'))
$old=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'face_before_canvas.png'))
$images=@();$titles=@('Before (skin shown for comparison)','Corrected + original hair','Corrected skin alone','Bangs moved 20px right (diagnostic)')
for($i=0;$i -lt 4;$i++){
 $b=[Drawing.Bitmap]::new(272,255);$g=[Drawing.Graphics]::FromImage($b)
 if($i -ne 2){DrawLayer $g $ctx.layers.'rear-fill';DrawLayer $g $ctx.layers.'rear-visible'}
 $face=if($i -eq 0){$old}else{$skin};$g.DrawImageUnscaled($face,0,0)
 if($i -ne 2){$dx=if($i -eq 3){20}else{0};if($i -eq 0){DrawLayer $g $ctx.layers.front $dx 0}else{$f=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'front_edge_refined.png'));$g.DrawImageUnscaled($f,$dx,0);$f.Dispose()}}
 $g.Dispose();$images+=,$b
}
$out=[Drawing.Bitmap]::new(1088,1100);$g=[Drawing.Graphics]::FromImage($out);$g.Clear([Drawing.Color]::White);$font=[Drawing.Font]::new('Arial',14)
$g.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::NearestNeighbor;$g.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::Half
for($i=0;$i -lt 4;$i++){$l=($i%2)*544;$t=[int][Math]::Floor($i/2)*550;$g.DrawString($titles[$i],$font,[Drawing.Brushes]::Black,($l+8),($t+5));for($y=0;$y -lt 510;$y+=16){for($x=0;$x -lt 544;$x+=16){$br=if((($x/16+$y/16)%2) -eq 0){[Drawing.Brushes]::LightGray}else{[Drawing.Brushes]::White};$g.FillRectangle($br,($l+$x),($t+30+$y),16,16)}};$g.DrawImage($images[$i],[Drawing.Rectangle]::new($l,($t+30),544,510),0,0,272,255,[Drawing.GraphicsUnit]::Pixel)}
$out.Save((Join-Path $PSScriptRoot 'foundation_review.png'),[Drawing.Imaging.ImageFormat]::Png)
$g.Dispose();$out.Dispose();$font.Dispose();$skin.Dispose();$old.Dispose();foreach($b in $images){$b.Dispose()}

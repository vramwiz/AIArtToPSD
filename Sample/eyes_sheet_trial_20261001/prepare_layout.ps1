# Windows PowerShell 5.1. Record paired-eye placement and draw a diagnostic draft.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$export=Get-Content (Join-Path $PSScriptRoot 'export.json') -Raw -Encoding UTF8|ConvertFrom-Json
$request=Get-Content (Join-Path $export.data.directory 'request.json') -Raw -Encoding UTF8|ConvertFrom-Json
$eye=@($request.layers|Where-Object name -eq '目（両目・元画素）')
if($eye.Count -ne 1 -or -not $eye[0].visible){throw 'Expected original paired eyes'}
$scans=Get-Content (Join-Path $PSScriptRoot 'alpha_measurements.json') -Raw -Encoding UTF8|ConvertFrom-Json
$states=@('normal','closed','half','happy_closed','nearly_closed','wide')
$labels=@('通常','閉じ','半開き','笑顔閉じ','ほぼ閉じ','見開き')
# Estimated common eye-corner baseline per pair from visual inspection of this sheet.
# Both eyes move together; individual eye geometry is not altered.
$anchorsY=@(217,229,526,540,839,815)
$measurements=@()
for($i=0;$i -lt 6;$i++){
    $b=$scans[$i].alphaScans|Where-Object threshold -eq 16
    $cx=($b.box[0]+$b.box[2])/2.0
    $l=[int][Math]::Floor($cx-320+0.5);$t=$anchorsY[$i]-110
    $source=@{left=$l;top=$t;right=($l+640);bottom=($t+220)}
    if($b.box[0] -lt $l -or $b.box[1] -lt $t -or $b.box[2] -gt $source.right -or $b.box[3] -gt $source.bottom){throw 'Meaningful pixels exceed crop'}
    $measurements+=@{index=$i;state=$states[$i];label=$labels[$i];scale=0.2;sourceBounds=$source;bounds=@{left=443;top=152;right=571;bottom=196};anchor=@{x=$cx;y=$anchorsY[$i];targetX=507;targetY=174};visibleBounds=$b.box}
}
$measurements|ConvertTo-Json -Depth 10|Set-Content (Join-Path $PSScriptRoot 'measurements.json') -Encoding UTF8
$foundation=[Drawing.Bitmap]::new(1024,1536)
$fg=[Drawing.Graphics]::FromImage($foundation);$fg.Clear([Drawing.Color]::Transparent)
$layers=@($request.layers|Where-Object {$_.kind -eq 'image' -and $_.visible -and $_.layerId -ne $eye[0].layerId})
[array]::Reverse($layers)
foreach($layer in $layers){
    if($layer.hasMask -or $layer.opacity -ne 255){throw 'Unexpected masked/translucent layer'}
    $asset=$request.assets|Where-Object assetId -eq $layer.assetId
    $img=[Drawing.Bitmap]::FromFile((Join-Path $export.data.directory $asset.path))
    $fg.DrawImageUnscaled($img,[int]$layer.bounds.left,[int]$layer.bounds.top);$img.Dispose()
}
$fg.Dispose()
$sheet=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'eyes_sheet.png'))
$review=[Drawing.Bitmap]::new(960,1056)
$rg=[Drawing.Graphics]::FromImage($review);$rg.Clear([Drawing.Color]::White)
$font=[Drawing.Font]::new('Yu Gothic UI',16)
foreach($m in $measurements){
    $canvas=$foundation.Clone();$cg=[Drawing.Graphics]::FromImage($canvas)
    $cg.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $cg.DrawImage($sheet,[Drawing.Rectangle]::new(443,152,128,44),[int]$m.sourceBounds.left,[int]$m.sourceBounds.top,640,220,[Drawing.GraphicsUnit]::Pixel)
    $cg.Dispose()
    $x=($m.index%2)*480;$y=[int][Math]::Floor($m.index/2)*352
    $rg.DrawString(('{0:00} {1}' -f ($m.index+1),$m.label),$font,[Drawing.Brushes]::Black,($x+12),($y+4))
    $rg.DrawImage($canvas,[Drawing.Rectangle]::new($x,($y+32),480,320),380,110,240,160,[Drawing.GraphicsUnit]::Pixel)
    $canvas.Dispose()
}
$review.Save((Join-Path $PSScriptRoot 'draft_comparison.png'),[Drawing.Imaging.ImageFormat]::Png)
$rg.Dispose();$review.Dispose();$font.Dispose();$sheet.Dispose();$foundation.Dispose()
'Six paired-eye layouts ready; draft uses GDI+ scaling, final scaling belongs to the app.'

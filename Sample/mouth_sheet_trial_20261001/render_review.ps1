# Windows PowerShell 5.1. Diagnostic composition only; no production edits or imports.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$sheet=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'mouth_sheet_rejected.png'))
$review=[Drawing.Bitmap]::new(960,1056)
$g=[Drawing.Graphics]::FromImage($review)
$g.Clear([Drawing.Color]::White)
$font=[Drawing.Font]::new('Segoe UI',14)
$labels=@('1 CLOSED - requested','2 HALF-OPEN','3 OPEN','4 A','5 I','6 U','7 E','8 O','9 N - closed requested')
for($i=0;$i -lt 9;$i++){
    $col=$i%3;$row=[int][Math]::Floor($i/3);$dx=$col*320;$dy=$row*352
    $g.DrawString($labels[$i],$font,[Drawing.Brushes]::Black,($dx+6),($dy+5))
    for($y=0;$y -lt 320;$y+=16){for($x=0;$x -lt 320;$x+=16){
        $brush=if((($x/16+$y/16)%2)-eq 0){[Drawing.Brushes]::White}else{[Drawing.Brushes]::LightGray}
        $g.FillRectangle($brush,($dx+$x),($dy+32+$y),16,16)
    }}
    $sx=[int][Math]::Floor($col*$sheet.Width/3);$sy=[int][Math]::Floor($row*$sheet.Height/3)
    $sw=[int][Math]::Floor(($col+1)*$sheet.Width/3)-$sx;$sh=[int][Math]::Floor(($row+1)*$sheet.Height/3)-$sy
    $g.DrawImage($sheet,[Drawing.Rectangle]::new($dx,($dy+32),320,320),$sx,$sy,$sw,$sh,[Drawing.GraphicsUnit]::Pixel)
}
$review.Save((Join-Path $PSScriptRoot 'sheet_review.png'),[Drawing.Imaging.ImageFormat]::Png)
Write-Output "Generated image dimensions: $($sheet.Width)x$($sheet.Height)"
$g.Dispose();$font.Dispose();$review.Dispose();$sheet.Dispose()

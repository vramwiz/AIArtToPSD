$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$src=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'head_source.png'))
$out=[Drawing.Bitmap]::new(1088,1020)
$g=[Drawing.Graphics]::FromImage($out)
$g.Clear([Drawing.Color]::White)
$g.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::Half
$g.DrawImage($src,[Drawing.Rectangle]::new(0,0,1088,1020),0,0,272,255,[Drawing.GraphicsUnit]::Pixel)
$pen=[Drawing.Pen]::new([Drawing.Color]::FromArgb(110,0,160,70),1)
$font=[Drawing.Font]::new('Arial',11)
for($x=0;$x -lt 272;$x+=20){$g.DrawLine($pen,$x*4,0,$x*4,1020);$g.DrawString("$x",$font,[Drawing.Brushes]::Red,$x*4,0)}
for($y=20;$y -lt 255;$y+=20){$g.DrawLine($pen,0,$y*4,1088,$y*4);$g.DrawString("$y",$font,[Drawing.Brushes]::Red,0,$y*4)}
$out.Save((Join-Path $PSScriptRoot 'head_grid.png'),[Drawing.Imaging.ImageFormat]::Png)
$g.Dispose();$src.Dispose();$out.Dispose()
$src=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'rear_hair_generated.png'))
@{width=$src.Width;height=$src.Height;pixelFormat=$src.PixelFormat.ToString()}|ConvertTo-Json
$src.Dispose()

# Windows PowerShell 5.1. Read app-produced assets; compose diagnostic previews only.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$export=Get-Content (Join-Path $PSScriptRoot 'export.json') -Raw -Encoding UTF8|ConvertFrom-Json
$before=Get-Content (Join-Path $export.data.directory 'request.json') -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content (Join-Path $PSScriptRoot 'native_layers.json') -Raw -Encoding UTF8|ConvertFrom-Json
$manifest=Get-Content (Join-Path $PSScriptRoot 'result.json') -Raw -Encoding UTF8|ConvertFrom-Json
$snapshot=Get-Content (Join-Path $PSScriptRoot 'snapshot-response.json') -Raw -Encoding UTF8|ConvertFrom-Json
$measurements=Get-Content (Join-Path $PSScriptRoot 'measurements.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($after.layers.Count -ne $before.layers.Count+7){throw 'Unexpected layer count'}
$unchanged=@()
foreach($a in $before.layers){
    $matches=@($after.layers|Where-Object layerId -eq $a.layerId)
    if($matches.Count -ne 1){throw 'Original layer lost'}
    $b=$matches[0]
    foreach($key in @('parentId','name','displayName','prefix','flip','opacity','bounds','hasMask','kind')){
        if(($a.$key|ConvertTo-Json -Compress) -ne ($b.$key|ConvertTo-Json -Compress)){throw "Original metadata changed: $key"}
    }
    if($a.layerId -eq $manifest.operations[0].layerId){if($b.visible){throw 'Original eyes should be hidden'}}
    elseif($a.visible -ne $b.visible){throw 'Unrelated visibility changed'}
    if($a.kind -eq 'image'){
        $old=$before.assets|Where-Object assetId -eq $a.assetId
        $new=$after.assets|Where-Object assetId -eq $b.assetId
        if($old.sha256 -ne $new.sha256){throw 'Original layer pixels changed'}
        $unchanged+=$a.name
    }
}
$oldIds=@($before.layers.layerId)
if((@($after.layers|Where-Object {$_.layerId -in $oldIds}).layerId -join ',') -ne ($oldIds -join ',')){throw 'Original order changed'}
$group=$after.layers|Where-Object layerId -eq $manifest.operations[1].layerId
if(-not $group.visible){throw 'New group hidden'}
$children=@($after.layers|Where-Object parentId -eq $group.layerId)
if($children.Count -ne 6 -or @($children|Where-Object visible).Count -ne 1 -or -not $children[1].visible){throw 'Unexpected candidate visibility'}
$layerDir=Join-Path $PSScriptRoot 'layers'
New-Item -ItemType Directory -Path $layerDir -Force|Out-Null
function Read-Layer($layer){
    $asset=$after.assets|Where-Object assetId -eq $layer.assetId
    return [Drawing.Bitmap]::FromFile((Join-Path $snapshot.data.directory $asset.path))
}
$foundation=[Drawing.Bitmap]::new(1024,1536)
$fg=[Drawing.Graphics]::FromImage($foundation)
$fg.Clear([Drawing.Color]::Transparent)
$fixed=@($after.layers|Where-Object {$_.kind -eq 'image' -and $_.visible -and $_.parentId -ne $group.layerId})
[array]::Reverse($fixed)
foreach($layer in $fixed){
    if($layer.opacity -ne 255 -or $layer.hasMask){throw 'Diagnostic requires plain layers'}
    $img=Read-Layer $layer
    $fg.DrawImageUnscaled($img,[int]$layer.bounds.left,[int]$layer.bounds.top)
    $img.Dispose()
}
$fg.Dispose()
$review=[Drawing.Bitmap]::new(960,1056)
$rg=[Drawing.Graphics]::FromImage($review)
$rg.Clear([Drawing.Color]::White)
$rg.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$rg.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::Half
$font=[Drawing.Font]::new('Yu Gothic UI',16)
$rows=@()
for($i=0;$i -lt 6;$i++){
    $layer=$children[$i]
    $asset=$after.assets|Where-Object assetId -eq $layer.assetId
    $path=Join-Path $snapshot.data.directory $asset.path
    Copy-Item $path (Join-Path $layerDir ($measurements[$i].state+'.png')) -Force
    if((Get-FileHash $path).Hash.ToLowerInvariant() -ne $asset.sha256){throw 'Export hash mismatch'}
    $img=Read-Layer $layer
    if($img.Width -ne $asset.width -or $img.Height -ne $asset.height){throw 'Asset size mismatch'}
    $count=0;$minX=$img.Width;$minY=$img.Height;$maxX=-1;$maxY=-1
    for($y=0;$y -lt $img.Height;$y++){for($x=0;$x -lt $img.Width;$x++){
        if($img.GetPixel($x,$y).A -gt 16){$count++;$minX=[Math]::Min($minX,$x);$minY=[Math]::Min($minY,$y);$maxX=[Math]::Max($maxX,$x);$maxY=[Math]::Max($maxY,$y)}
    }}
    if($count -eq 0){throw 'Eyes disappeared'}
    $rows+=@{state=$measurements[$i].state;name=$layer.name;bounds=$layer.bounds;width=$img.Width;height=$img.Height;visiblePixels=$count;visibleWidth=($maxX-$minX+1);visibleHeight=($maxY-$minY+1);visibleCenterX=($layer.bounds.left+($minX+$maxX+1)/2.0);visibleCenterY=($layer.bounds.top+($minY+$maxY+1)/2.0)}
    $canvas=$foundation.Clone()
    $cg=[Drawing.Graphics]::FromImage($canvas)
    $cg.DrawImageUnscaled($img,[int]$layer.bounds.left,[int]$layer.bounds.top)
    $cg.Dispose();$img.Dispose()
    $tx=($i%2)*480;$ty=[int][Math]::Floor($i/2)*352
    $rg.DrawString($layer.name,$font,[Drawing.Brushes]::Black,($tx+12),($ty+4))
    $rg.DrawImage($canvas,[Drawing.Rectangle]::new($tx,($ty+32),480,320),380,110,240,160,[Drawing.GraphicsUnit]::Pixel)
    $canvas.Dispose()
}
$review.Save((Join-Path $PSScriptRoot 'face_comparison.png'),[Drawing.Imaging.ImageFormat]::Png)
$font.Dispose();$rg.Dispose();$review.Dispose();$foundation.Dispose()
$acceptance='pending'
$feedbackPath=Join-Path $PSScriptRoot 'learning_record.json'
if(Test-Path $feedbackPath){$acceptance=(Get-Content $feedbackPath -Raw -Encoding UTF8|ConvertFrom-Json).manualVisualAcceptance}
$report=@{unchangedOriginalImageLayers=$unchanged;originalOrderPreserved=$true;addedGroups=1;addedEyeLayers=6;defaultVisible='closed';commonScale=0.2;eyes=$rows;manualVisualAcceptance=$acceptance}
$report|ConvertTo-Json -Depth 10|Set-Content (Join-Path $PSScriptRoot 'verification.json') -Encoding UTF8
$rows|ForEach-Object {[PSCustomObject]$_}|Format-Table state,width,height,visibleWidth,visibleHeight,visiblePixels,visibleCenterX,visibleCenterY

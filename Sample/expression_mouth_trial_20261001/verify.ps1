# Windows PowerShell 5.1. Compare exported app state; draw only diagnostic previews.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$export=Get-Content (Join-Path $PSScriptRoot 'export.json') -Raw -Encoding UTF8|ConvertFrom-Json
$before=Get-Content (Join-Path $export.data.directory 'request.json') -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content (Join-Path $PSScriptRoot 'native_layers.json') -Raw -Encoding UTF8|ConvertFrom-Json
$manifest=Get-Content (Join-Path $PSScriptRoot 'result.json') -Raw -Encoding UTF8|ConvertFrom-Json
$oldMouthId=$manifest.operations[0].layerId
$newMouthId=$manifest.operations[1].layerId
if($after.layers.Count -ne $before.layers.Count+1){throw 'Unexpected layer count'}
$unchanged=@()
foreach($a in $before.layers){
    $matches=@($after.layers|Where-Object layerId -eq $a.layerId)
    if($matches.Count -ne 1){throw 'Original layer lost'}
    $b=$matches[0]
    foreach($key in @('parentId','name','displayName','prefix','flip','opacity','bounds','hasMask','kind')){
        if(($a.$key|ConvertTo-Json -Compress) -ne ($b.$key|ConvertTo-Json -Compress)){throw "Original metadata changed: $key"}
    }
    if($a.layerId -eq $oldMouthId){if($b.visible){throw 'Original mouth should be hidden'}}
    elseif($a.visible -ne $b.visible){throw 'Unrelated visibility changed'}
    if($a.kind -eq 'image'){
        $old=$before.assets|Where-Object assetId -eq $a.assetId
        $new=$after.assets|Where-Object assetId -eq $b.assetId
        if($old.sha256 -ne $new.sha256){throw 'Original layer pixels changed'}
        $unchanged+=$a.name
    }
}
$newLayer=$after.layers|Where-Object layerId -eq $newMouthId
if(-not $newLayer.visible){throw 'Expression not visible'}
$snapshot=Get-Content (Join-Path $PSScriptRoot 'snapshot-response.json') -Raw -Encoding UTF8|ConvertFrom-Json
$newAsset=$after.assets|Where-Object assetId -eq $newLayer.assetId
Copy-Item (Join-Path $snapshot.data.directory $newAsset.path) (Join-Path $PSScriptRoot 'mouth_open_app.png') -Force
$report=@{unchangedOriginalImageLayers=$unchanged;originalMouthHidden=$true;addedLayers=1;newMouthBounds=$newLayer.bounds;newMouthWidth=$newAsset.width;newMouthHeight=$newAsset.height;manualVisualAcceptance='pending'}
$report|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot 'verification.json') -Encoding UTF8
$images=@([Drawing.Bitmap]::FromFile((Join-Path $export.data.directory 'preview.png')),[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'native_preview.png')))
$review=[Drawing.Bitmap]::new(960,362)
$g=[Drawing.Graphics]::FromImage($review);$g.Clear([Drawing.Color]::White)
$font=[Drawing.Font]::new('Segoe UI',14)
$labels=@('ORIGINAL MOUTH','EXPRESSION: SLIGHTLY OPEN')
for($i=0;$i -lt 2;$i++){
    $x=$i*480
    $g.DrawString($labels[$i],$font,[Drawing.Brushes]::Black,($x+8),8)
    $g.DrawImage($images[$i],[Drawing.Rectangle]::new($x,42,480,320),380,110,240,160,[Drawing.GraphicsUnit]::Pixel)
}
$review.Save((Join-Path $PSScriptRoot 'face_comparison.png'),[Drawing.Imaging.ImageFormat]::Png)
$g.Dispose();$font.Dispose();$review.Dispose();foreach($img in $images){$img.Dispose()}
$report|ConvertTo-Json -Depth 8

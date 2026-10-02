#requires -Version 7.0
param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Directory)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$request=Get-Content -LiteralPath (Join-Path $Directory 'request.json') -Raw | ConvertFrom-Json
if($request.canvas.width -ne 752 -or $request.canvas.height -ne 1344){throw 'Unexpected canvas'}
$targets=@($request.layers | Where-Object { $_.kind -eq 'image' -and $_.name -eq 'original' })
if($targets.Count -ne 1){throw 'Original layer is not unique'}
$source=$targets[0]
$definitions=@(
  @{assetId='eyes';name='両目（原画画素）';left=293;top=167;right=448;bottom=208},
  @{assetId='brows';name='両眉（原画画素）';left=299;top=142;right=439;bottom=166},
  @{assetId='mouth';name='口（原画画素）';left=358;top=233;right=386;bottom=243},
  @{assetId='base';name='ベース（目眉口を肌・髪で補完）';left=0;top=0;right=752;bottom=1344}
)
$assets=@()
foreach($definition in $definitions){
  $id=$definition.assetId
  $path=Join-Path $Directory ('images\'+$id+'.png')
  Copy-Item -LiteralPath (Join-Path $Root ('prepared\'+$id+'.png')) -Destination $path
  $bitmap=[Drawing.Bitmap]::FromFile($path)
  try { $width=$bitmap.Width; $height=$bitmap.Height } finally { $bitmap.Dispose() }
  if($width -ne ($definition.right-$definition.left) -or $height -ne ($definition.bottom-$definition.top)){throw 'PNG size mismatch'}
  $assets+=@{assetId=$id;path=('images/'+$id+'.png');sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();width=$width;height=$height;pixelFormat='RGBA8';colorSpace='sRGB'}
}
$groupId=[guid]::NewGuid().ToString('B')
$operations=@(
  @{op='rename_layer';layerId=$source.layerId;name='元画像（比較用・原寸）'},
  @{op='set_attributes';layerId=$source.layerId;visible=$false;opacity=$source.opacity},
  @{op='add_group';layerId=$groupId;name='顔パーツ分離（確認用）';parentId='';beforeLayerId=$source.layerId;visible=$true;opacity=255}
)
foreach($definition in $definitions){
  $operations+=@{op='add_layer';layerId=[guid]::NewGuid().ToString('B');name=$definition.name;parentId=$groupId;beforeLayerId='';visible=$true;opacity=255;assetId=$definition.assetId;bounds=@{left=$definition.left;top=$definition.top;right=$definition.right;bottom=$definition.bottom}}
}
$result=[ordered]@{schemaVersion=$request.schemaVersion;requestId=$request.requestId;jobId=$request.jobId;documentId=$request.documentId;ifRevision=$request.ifRevision;assets=$assets;operations=$operations}
$target=Join-Path $Directory 'result.json'
if(Test-Path -LiteralPath $target){throw 'Do not overwrite an existing result'}
$temporary=Join-Path $Directory 'result.json.tmp'
[IO.File]::WriteAllText($temporary,($result|ConvertTo-Json -Depth 32),[Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporary -Destination $target
$result|ConvertTo-Json -Depth 32|Set-Content -LiteralPath (Join-Path $Root 'face-result.json') -Encoding utf8
Write-Output $target

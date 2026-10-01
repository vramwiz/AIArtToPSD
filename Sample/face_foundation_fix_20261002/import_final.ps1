# PowerShell 7. Replace completed skin and the narrow corrected bang edge.
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$e=Get-Content (Join-Path $PSScriptRoot 'resample-export.json') -Raw|ConvertFrom-Json
$r=Get-Content (Join-Path $e.data.directory 'request.json') -Raw|ConvertFrom-Json
$face=@($r.layers|Where-Object name -eq '顔・耳・首（髪を除去・元画素）');$front=@($r.layers|Where-Object name -eq '前髪・横髪（元画素）')
if($face.Count -ne 1 -or $front.Count -ne 1){throw 'Ambiguous targets'};$face=$face[0];$front=$front[0]
$arg=@{jobId=$r.jobId}|ConvertTo-Json -Compress
$s=& (Join-Path $root 'Tools/Send-ArtCommand.ps1') -PipeName $r.pipeName -Command status -ArgsJson $arg|ConvertFrom-Json
if(!$s.ok -or $s.data.job.stale -or $s.data.documentId -ne $r.documentId -or $s.data.revision -ne $r.ifRevision){throw 'Document changed'}
$assets=@();$ops=@()
foreach($item in @(@{id='skin-final';file='face_completed.png';target=$face;name='顔・耳・首（額・頭部補完済み）'},@{id='front-final';file='front_edge_refined.png';target=$front;name='前髪・横髪（肌境界補正）'})){
 $src=Join-Path $PSScriptRoot $item.file;Copy-Item $src (Join-Path $e.data.directory ('images/'+$item.file))
 $assets+=@{assetId=$item.id;path=('images/'+$item.file);sha256=(Get-FileHash $src).Hash.ToLowerInvariant();width=272;height=255;pixelFormat='RGBA8';colorSpace='sRGB'}
 $ops+=@{op='replace_layer';layerId=$item.target.layerId;assetId=$item.id;trimTransparent=$true;bounds=@{left=366;top=19;right=638;bottom=274}}
 $ops+=@{op='rename_layer';layerId=$item.target.layerId;name=$item.name}
}
$ops+=@{op='set_attributes';layerId=$face.layerId;visible=$true;opacity=$face.opacity}
$result=@{schemaVersion=1;requestId=$r.requestId;jobId=$r.jobId;documentId=$r.documentId;ifRevision=$r.ifRevision;assets=$assets;operations=$ops}
$rp=Join-Path $e.data.directory 'result.json';if(Test-Path $rp){throw 'Result exists'}
$result|ConvertTo-Json -Depth 12|Set-Content $rp -Encoding utf8;Copy-Item $rp (Join-Path $PSScriptRoot 'result.json')
& (Join-Path $root 'Tools/Send-ArtCommand.ps1') -PipeName $r.pipeName -Command import -ArgsJson $arg -TimeoutMs 60000|Tee-Object (Join-Path $PSScriptRoot 'import-response.json')

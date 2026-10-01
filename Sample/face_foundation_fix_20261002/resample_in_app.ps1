# PowerShell 7. Target is already hidden; use it to obtain application-resampled skin before final compositing.
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$e=Get-Content (Join-Path $PSScriptRoot 'export.json') -Raw|ConvertFrom-Json
$r=Get-Content (Join-Path $e.data.directory 'request.json') -Raw|ConvertFrom-Json
$target=@($r.layers|Where-Object name -eq '顔・耳・首（髪を除去・元画素）')
if($target.Count -ne 1 -or $target[0].visible -or $target[0].hasMask){throw 'Expected unique hidden face target'};$target=$target[0]
$argsJson=@{jobId=$r.jobId}|ConvertTo-Json -Compress
$s=& (Join-Path $root 'Tools/Send-ArtCommand.ps1') -PipeName $r.pipeName -Command status -ArgsJson $argsJson|ConvertFrom-Json
if(!$s.ok -or $s.data.job.stale -or $s.data.documentId -ne $r.documentId -or $s.data.revision -ne $r.ifRevision){throw 'Document changed'}
$src=Join-Path $PSScriptRoot 'skin_generated.png';Copy-Item $src (Join-Path $e.data.directory 'images/skin_generated.png')
$asset=@{assetId='completed-skin';path='images/skin_generated.png';sha256=(Get-FileHash $src).Hash.ToLowerInvariant();width=1295;height=1214;pixelFormat='RGBA8';colorSpace='sRGB'}
$result=@{schemaVersion=1;requestId=$r.requestId;jobId=$r.jobId;documentId=$r.documentId;ifRevision=$r.ifRevision;assets=@($asset);operations=@(@{op='replace_layer';layerId=$target.layerId;assetId='completed-skin';resample=$true;trimTransparent=$true;bounds=@{left=374;top=34;right=646;bottom=289}})}
$rp=Join-Path $e.data.directory 'result.json';if(Test-Path $rp){throw 'Result exists'}
$result|ConvertTo-Json -Depth 12|Set-Content $rp -Encoding utf8
Copy-Item $rp (Join-Path $PSScriptRoot 'resample-result.json')
& (Join-Path $root 'Tools/Send-ArtCommand.ps1') -PipeName $r.pipeName -Command import -ArgsJson $argsJson -TimeoutMs 60000|Tee-Object (Join-Path $PSScriptRoot 'resample-import.json')

# PowerShell 7. The new group starts hidden until its application output is verified.
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$job=Join-Path $root 'Exchange/{5B3C025E-B05C-42FD-8943-E017B6F8F9ED}'
$r=Get-Content -LiteralPath (Join-Path $job 'request.json') -Raw|ConvertFrom-Json
$head=@($r.layers|Where-Object name -eq '頭部ベース（髪・顔・首上部）')
if($head.Count -ne 1 -or !$head[0].visible -or $head[0].hasMask){throw 'Unexpected head'}
$head=$head[0]
$a=@($r.assets|Where-Object assetId -eq $head.assetId)[0]
if($a.sha256 -ne (Get-FileHash (Join-Path $PSScriptRoot 'head_source.png')).Hash.ToLowerInvariant()){throw 'Source mismatch'}
$gid=[guid]::NewGuid().ToString('B');$rear=[guid]::NewGuid().ToString('B')
$ops=@(@{op='add_group';layerId=$gid;parentId=$head.parentId;beforeLayerId=$head.layerId;name='髪分離・後ろ髪補完（確認用）';visible=$false;opacity=255})
$assets=@();$ids=@{}
$specs=@(
 @{file='front_hair_original.png';name='前髪・横髪（元画素）';id='front';parent=$gid;width=272;height=255},
 @{file='face_neck_original.png';name='顔・耳・首（髪を除去・元画素）';id='face';parent=$gid;width=272;height=255},
 @{file='rear_hair_visible_original.png';name='後ろ髪・見えていた部分（元画素）';id='rear-visible';parent=$rear;width=272;height=255},
 @{file='rear_hair_hidden_fill.png';name='後ろ髪・隠れていた部分（生成補完）';id='rear-fill';parent=$rear;width=1295;height=1214}
)
foreach($s in $specs){
 if($s.id -eq 'rear-visible'){$ops+=@{op='add_group';layerId=$rear;parentId=$gid;beforeLayerId='';name='後ろ髪（元画素＋不可視部分補完）';visible=$true;opacity=255}}
 $src=Join-Path $PSScriptRoot $s.file;$dest=Join-Path $job ('images/'+$s.file)
 Copy-Item -LiteralPath $src -Destination $dest
 $assets+=@{assetId=$s.id;path=('images/'+$s.file);sha256=(Get-FileHash $dest).Hash.ToLowerInvariant();width=$s.width;height=$s.height;pixelFormat='RGBA8';colorSpace='sRGB'}
 $id=[guid]::NewGuid().ToString('B');$ids[$s.id]=$id
 $o=@{op='add_layer';layerId=$id;parentId=$s.parent;beforeLayerId='';name=$s.name;visible=$true;opacity=255;assetId=$s.id;bounds=$head.bounds;trimTransparent=$true}
 if($s.id -eq 'rear-fill'){$o.resample=$true}
 $ops+=$o
}
$result=@{schemaVersion=$r.schemaVersion;requestId=$r.requestId;jobId=$r.jobId;documentId=$r.documentId;ifRevision=$r.ifRevision;assets=$assets;operations=$ops}
$resultPath=Join-Path $job 'result.json'
if(Test-Path -LiteralPath $resultPath){throw 'Result already exists'}
$result|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $resultPath -Encoding utf8
Copy-Item -LiteralPath $resultPath -Destination (Join-Path $PSScriptRoot 'result.json')
@{group=$gid;rearGroup=$rear;layers=$ids;originalHead=$head.layerId;documentId=$r.documentId;jobId=$r.jobId;pipeName=$r.pipeName}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $PSScriptRoot 'context.json') -Encoding utf8
Write-Output 'Prepared four images and two groups, hidden for initial validation.'

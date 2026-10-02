#requires -Version 7.0
param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
$job=(Get-Content -LiteralPath (Join-Path $Root 'job-directory.txt') -Raw).Trim()
$request=Get-Content -LiteralPath (Join-Path $job 'request.json') -Raw|ConvertFrom-Json
$layout=Get-Content -LiteralPath (Join-Path $Root 'layout.json') -Raw|ConvertFrom-Json
if(Test-Path -LiteralPath (Join-Path $job 'result.json')){throw 'Result already exists; use a new export.'}
$parent=@($request.layers|Where-Object name -eq '顔パーツ分離（確認用）')
if($parent.Count -ne 1 -or $parent[0].kind -ne 'group'){throw 'Face parent is not unique.'}
$parent=$parent[0]
$assets=@();$operations=@();$manifest=@()
foreach($kind in @('eyes','brows','mouths')){
 $label=if($kind -eq 'eyes'){'両目'}elseif($kind -eq 'brows'){'両眉'}else{'口'}
 $key=if($kind -eq 'mouths'){'mouth'}else{$kind}
 $original=@($request.layers|Where-Object name -eq ($label+'（原画画素）'))
 if($original.Count -ne 1 -or $original[0].hasMask -or $original[0].parentId -ne $parent.layerId){throw 'Original part mismatch.'}
 $original=$original[0]
 $source=@($request.assets|Where-Object assetId -eq $original.assetId)[0]
 $sheetFilename=Join-Path $Root ('prepared-'+$kind+'.png')
 $sheetName=$kind+'-sheet.png';$originalName=$key+'-original.png'
 Copy-Item -LiteralPath $sheetFilename -Destination (Join-Path $job ('images/'+$sheetName))
 Copy-Item -LiteralPath (Join-Path $job $source.path) -Destination (Join-Path $job ('images/'+$originalName))
 $sheetSize=if($kind -eq 'mouths'){@(1254,1254)}else{@(1536,1024)}
 $assets+=@{assetId=$kind+'-sheet';path='images/'+$sheetName;sha256=(Get-FileHash -LiteralPath $sheetFilename -Algorithm SHA256).Hash.ToLowerInvariant();width=$sheetSize[0];height=$sheetSize[1];pixelFormat='RGBA8';colorSpace='sRGB'}
 $assets+=@{assetId=$key+'-original';path='images/'+$originalName;sha256=(Get-FileHash -LiteralPath (Join-Path $job ('images/'+$originalName)) -Algorithm SHA256).Hash.ToLowerInvariant();width=$source.width;height=$source.height;pixelFormat='RGBA8';colorSpace='sRGB'}
 $group=[guid]::NewGuid().ToString('B')
 $operations+=@{op='add_group';layerId=$group;parentId=$parent.layerId;beforeLayerId=$original.layerId;name=$label+'（表情切替）';visible=$true;opacity=255}
 $originalCopy=[guid]::NewGuid().ToString('B');$copyName='*00 '+$label+'（原画）'
 $operations+=@{op='add_layer';layerId=$originalCopy;parentId=$group;beforeLayerId='';name=$copyName;visible=$true;opacity=255;assetId=$key+'-original';bounds=$original.bounds}
 $manifest+=@{name=$copyName;layerId=$originalCopy;groupId=$group;kind=$kind;original=$true;sourceLayerId=$original.layerId;file='input-'+$key+'.png';bounds=$original.bounds;visible=$true}
 foreach($cell in @($layout|Where-Object {$_.kind -eq $kind -and $_.importGenerated})){
  $s=$cell.sourceBounds;$b=$cell.bounds
  $number=if($kind -eq 'mouths'){$cell.index+1}else{$cell.index}
  $name='*'+('{0:00} {1} {2}' -f $number,$label,$cell.label)
  $id=[guid]::NewGuid().ToString('B')
  $bounds=@{left=$b[0];top=$b[1];right=$b[2];bottom=$b[3]}
  $operations+=@{op='add_layer';layerId=$id;parentId=$group;beforeLayerId='';name=$name;visible=$false;opacity=255;assetId=$kind+'-sheet';sourceBounds=@{left=$s[0];top=$s[1];right=$s[2];bottom=$s[3]};bounds=$bounds;resample=$true}
  $manifest+=@{name=$name;layerId=$id;groupId=$group;kind=$kind;original=$false;file='prepared/'+$cell.file;bounds=$bounds;sourceBounds=$s;scale=$cell.scale;visible=$false}
 }
 $operations+=@{op='set_attributes';layerId=$original.layerId;visible=$false;opacity=$original.opacity}
}
$result=[ordered]@{schemaVersion=$request.schemaVersion;requestId=$request.requestId;jobId=$request.jobId;documentId=$request.documentId;ifRevision=[string]$request.ifRevision;assets=$assets;operations=$operations}
$json=$result|ConvertTo-Json -Depth 25
[IO.File]::WriteAllText((Join-Path $job 'result.json.tmp'),$json,[Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath (Join-Path $job 'result.json.tmp') -Destination (Join-Path $job 'result.json')
Copy-Item -LiteralPath (Join-Path $job 'result.json') -Destination (Join-Path $Root 'result.json')
$manifest|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $Root 'manifest.json') -Encoding utf8
[pscustomobject]@{assets=$assets.Count;operations=$operations.Count;generated=@($manifest|Where-Object {-not $_.original}).Count;originalCopies=@($manifest|Where-Object original).Count;jobId=$request.jobId}|ConvertTo-Json

# PowerShell 7. Package generated PNGs unchanged; no image separation, masking, resizing or alignment.
$ErrorActionPreference = 'Stop'
$export = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'export-response.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$jobDirectory = $export.data.directory
$request = Get-Content -LiteralPath (Join-Path $jobDirectory 'request.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($request.canvas.width -ne 1024 -or $request.canvas.height -ne 1536 -or $request.layers.Count -ne 1) { throw 'Unexpected source document' }
if (Test-Path -LiteralPath (Join-Path $jobDirectory 'result.json')) { throw 'Result already exists; do not modify an issued batch' }
$parts = @(
    @{id='brows-pair';name='眉（両眉一組・AI試験）';source='brows_pair.png'},
    @{id='eyes-pair';name='目（両目一組・AI試験）';source='..\ai_separation_check_20261001\eyes_pair.png'},
    @{id='mouth';name='口（AI試験）';source='mouth.png'},
    @{id='base';name='ベース（肌補完・光除去）';source='..\ai_separation_check_20261001\base_no_glow_v2.png'}
)
$imagesDirectory = Join-Path $jobDirectory 'images'
New-Item -ItemType Directory -Path $imagesDirectory -Force | Out-Null
$originalId = $request.layers[0].layerId
$groupId = [guid]::NewGuid().ToString('B')
$operations = @(
    @{op='set_attributes';layerId=$originalId;visible=$false;opacity=255},
    @{op='rename_layer';layerId=$originalId;name='元画像（比較用）'},
    @{op='add_group';layerId=$groupId;name='AI表情分離（確認用）';parentId='';beforeLayerId=$originalId;visible=$true;opacity=255}
)
$assets = @()
Add-Type -AssemblyName System.Drawing
foreach ($part in $parts) {
    $inputPath = Join-Path $PSScriptRoot $part.source
    $png = [System.Drawing.Image]::FromFile($inputPath)
    try { if($png.Width -ne 1024 -or $png.Height -ne 1536) { throw 'Unexpected PNG dimensions' } } finally { $png.Dispose() }
    $outputPath = Join-Path $imagesDirectory ($part.id+'.png')
    Copy-Item -LiteralPath $inputPath -Destination $outputPath
    $hash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($hash -ne (Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash.ToLowerInvariant()) { throw 'Copy hash mismatch' }
    $assets += @{assetId=$part.id;path=('images/'+$part.id+'.png');sha256=$hash;width=1024;height=1536;pixelFormat='RGBA8';colorSpace='sRGB'}
    $operations += @{op='add_layer';layerId=[guid]::NewGuid().ToString('B');name=$part.name;parentId=$groupId;beforeLayerId='';visible=$true;opacity=255;assetId=$part.id;bounds=@{left=0;top=0;right=1024;bottom=1536}}
}
$result = [ordered]@{schemaVersion=1;requestId=$request.requestId;jobId=$request.jobId;documentId=$request.documentId;ifRevision=$request.ifRevision;assets=$assets;operations=$operations}
$json = $result | ConvertTo-Json -Depth 15
$temporaryResult = Join-Path $jobDirectory 'result.json.tmp'
$json | Set-Content -LiteralPath $temporaryResult -Encoding utf8
Move-Item -LiteralPath $temporaryResult -Destination (Join-Path $jobDirectory 'result.json')
$json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'result-submitted.json') -Encoding utf8
$jobDirectory | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'job-directory.txt') -Encoding utf8
[pscustomobject]@{jobId=$request.jobId;directory=$jobDirectory;assets=$assets;groupId=$groupId} | ConvertTo-Json -Depth 8

#requires -Version 7.0
param([Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$ProcessId)
$ErrorActionPreference='Stop'
$route=Join-Path $PSScriptRoot 'Invoke-ArtRoute.ps1'
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Value,[string]$Label){if(-not $Value){throw $Label};$checks.Add($Label)}
function Request([string]$Command,[hashtable]$Arguments=@{},[string]$Id=([guid]::NewGuid().ToString())){
    $inputObject=[ordered]@{command=$Command;args=$Arguments;requestId=$Id}
    (& $route -ProcessId $ProcessId -Client dot -InputJson ($inputObject|ConvertTo-Json -Depth 32 -Compress) -TimeoutMs 60000)|ConvertFrom-Json
}
function Send([string]$Command,[hashtable]$Arguments=@{},[string]$Id=([guid]::NewGuid().ToString())){
    $reply=Request $Command $Arguments $Id
    if(-not $reply.ok){throw $reply.error.message};$reply.data
}
function Manifest($Job,$Assets,$Operations){
    @{schemaVersion=1;requestId=$Job.jobId;jobId=$Job.jobId;documentId=$Job.documentId;ifRevision=$Job.ifRevision;assets=@($Assets);operations=@($Operations)}
}
$initial=Send 'status'
if($initial.assemblyVersion -ne 1){throw 'Build the main project with assemblyVersion=1 first'}
if($initial.documentId){throw 'Use an already running empty application instance; existing documents are preserved'}
$root=Join-Path (Split-Path $PSScriptRoot -Parent) ('Tests/output/Assembly/'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($root)
try{
    $newId=[guid]::NewGuid().ToString()
    $newArgs=@{width=1024;height=1536;documentId='';ifRevision='0'}
    $blank=Send 'new-document' $newArgs $newId
    Check ($blank.width -eq 1024 -and $blank.height -eq 1536 -and $blank.layerCount -eq 0) 'Exact empty canvas created without placeholder layers'
    $repeat=Send 'new-document' $newArgs $newId
    Check ($repeat.documentId -eq $blank.documentId) 'new-document request retry does not recreate the canvas'
    $different=$newArgs.Clone();$different.width=1025
    Check (-not (Request 'new-document' $different $newId).ok) 'Successful request ID cannot carry changed content'
    Check (-not (Request 'new-document' @{width=1024;height=1536;documentId=$blank.documentId;ifRevision=$blank.revision}).ok) 'Unsaved canvas cannot be silently discarded'
    $bad=Send 'export' @{prompt='Synthetic rollback fixture only'}
    $badOps=@(
        @{op='add_group';layerId=[guid]::NewGuid().ToString('B');name='must roll back';parentId='';beforeLayerId='';visible=$true;opacity=255},
        @{op='rename_layer';layerId='missing';name='fail'}
    )
    $rejected=Request 'import' @{jobId=$bad.jobId;result=(Manifest $bad @() $badOps)}
    $afterBad=Send 'document'
    Check (-not $rejected.ok -and $afterBad.layerCount -eq 0 -and $afterBad.revision -eq $blank.revision) 'Partially valid inline batch rolls back all layer changes'
    $job=Send 'export' @{prompt='Synthetic 11-layer accordion API acceptance; no real materials'}
    $recovery=Get-Content -LiteralPath (Join-Path $job.directory 'recovery.json') -Raw -Encoding utf8|ConvertFrom-Json
    Check $recovery.emptyCanvas 'Empty document exchange has an explicit recoverable canvas snapshot'
    Add-Type -AssemblyName System.Drawing
    $assets=[Collections.Generic.List[object]]::new();$hashes=@{};$layerIds=@{}
    $names=@('background','R0','R1','R2','B0','B1','B2','C0','C1','C2','belt')
    for($i=0;$i -lt $names.Count;$i++){
        $name=$names[$i];$path=Join-Path $root ($name+'.png')
        $bitmap=[Drawing.Bitmap]::new(1024,1536,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics=[Drawing.Graphics]::FromImage($bitmap)
        try{
            $alpha=if($i -eq 0){255}else{128}
            $color=[Drawing.Color]::FromArgb($alpha,($i*17)%256,($i*29)%256,($i*43)%256)
            $graphics.Clear($color);$bitmap.Save($path,[Drawing.Imaging.ImageFormat]::Png)
        }finally{$graphics.Dispose();$bitmap.Dispose()}
        $decoded=[Drawing.Bitmap]::new($path)
        try{$pixel=$decoded.GetPixel(0,0)}finally{$decoded.Dispose()}
        $rgba=[byte[]]::new(1024*1536*4)
        for($p=0;$p -lt $rgba.Length;$p+=4){$rgba[$p]=$pixel.R;$rgba[$p+1]=$pixel.G;$rgba[$p+2]=$pixel.B;$rgba[$p+3]=$pixel.A}
        $hashes[$name]=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($rgba)).ToLowerInvariant()
        $received=& (Join-Path $PSScriptRoot 'Send-ArtImage.ps1') -PipeName $initial.pipeName -JobId $job.jobId -InputPng $path -FileName ($name+'.png') -Client dot
        $assets.Add(@{assetId=$name;path=$received.path;sha256=$received.sha256;width=1024;height=1536;pixelFormat='RGBA8';colorSpace='sRGB'})
        $layerIds[$name]=[guid]::NewGuid().ToString('B')
    }
    $right=[guid]::NewGuid().ToString('B');$left=[guid]::NewGuid().ToString('B')
    $operations=[Collections.Generic.List[object]]::new()
    $operations.Add(@{op='add_group';layerId=$right;name='right';parentId='';beforeLayerId='';visible=$true;opacity=255})
    $operations.Add(@{op='add_group';layerId=$left;name='left';parentId='';beforeLayerId='';visible=$true;opacity=255})
    foreach($name in $names){
        $parent='';$display=$name;$before=''
        if($name -match '^R[0-2]$'){$parent=$right;$display='*'+$name}
        if($name -match '^[BC][0-2]$'){$parent=$left;$display='*'+$name}
        if($name -eq 'belt'){$before=$right}
        $operations.Add(@{op='add_layer';layerId=$layerIds[$name];name=$display;parentId=$parent;beforeLayerId=$before;visible=($name -in @('background','R1','B1','belt'));opacity=255;assetId=$name;bounds=@{left=0;top=0;right=1024;bottom=1536}})
    }
    # Reposition background to the bottom using insertion order when constructing the batch.
    $background=$operations[2];$operations.RemoveAt(2);$operations.Add($background)
    $result=Manifest $job $assets.ToArray() $operations.ToArray()
    $importId=[guid]::NewGuid().ToString()
    Check ((Send 'import' @{jobId=$job.jobId;result=$result} $importId).state -eq 'completed') 'Eleven full-canvas images register through pipe-only manifest and PNG transfer'
    $document=Send 'document' @{includePixelHashes=$true}
    Check ($document.layerCount -eq 13) 'Exactly eleven image layers plus two exclusive groups exist'
    foreach($name in $names){
        $layer=@($document.layers|Where-Object layerId -eq $layerIds[$name])[0]
        Check ($layer.pixelSha256 -eq $hashes[$name] -and $layer.bounds.left -eq 0 -and $layer.bounds.top -eq 0 -and $layer.bounds.right -eq 1024 -and $layer.bounds.bottom -eq 1536) ('Original RGBA and canvas coordinates retained: '+$name)
    }
    $visible=@($document.layers|Where-Object{ $_.kind -eq 'image' -and $_.visible })
    Check ($visible.Count -eq 4 -and $visible.name -contains '*B1' -and $visible.name -contains '*R1' -and $visible.name -contains 'background' -and $visible.name -contains 'belt') 'Initial selection is background plus R1 plus B1 plus belt'
    $null=Send 'import' @{jobId=$job.jobId;result=$result} $importId
    Check ((Send 'document').revision -eq $document.revision) 'Successful import retry does not duplicate layers'
    $preview=& (Join-Path $PSScriptRoot 'Receive-ArtPreview.ps1') -PipeName $initial.pipeName -DocumentId $document.documentId -Revision $document.revision -OutputPng (Join-Path $root 'preview.png') -Client dot
    Check ($preview.width -eq 1024 -and $preview.height -eq 1536) 'PNG preview downloads by bounded chunks and passes SHA256 validation'
    $saved=Send 'save' @{documentId=$document.documentId;ifRevision=$document.revision;fileName=(Join-Path $root 'synthetic-accordion.psd')}
    Check (-not $saved.modified -and $saved.layerCount -eq 13) 'PSD is published under a new name and reloaded'
    $persisted=Send 'document' @{includePixelHashes=$true}
    foreach($name in $names){$display=if($name -match '^[RBC][0-2]$'){'*'+$name}else{$name};$layer=@($persisted.layers|Where-Object name -eq $display)[0];Check ($layer.pixelSha256 -eq $hashes[$name]) ('Saved PSD retains RGBA: '+$name)}
    $verification=[ordered]@{passed=$true;checks=$checks;testRoot=$root;newApplicationStarted=$false;syntheticOnly=$true;imageLayerCount=11;groupCount=2}
    [IO.File]::WriteAllText((Join-Path $root 'verification.json'),($verification|ConvertTo-Json -Depth 16));$verification|ConvertTo-Json -Depth 16
}catch{[IO.File]::WriteAllText((Join-Path $root 'failure.json'),(@{error=$_.Exception.Message;checks=$checks}|ConvertTo-Json -Depth 16));throw}

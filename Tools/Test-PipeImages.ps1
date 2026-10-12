#requires -Version 7.0
param([ValidateSet('Debug','Release')][string]$Configuration='Debug',
    [string]$RepositoryRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$root=Join-Path $RepositoryRoot ('Win64\Validation\ImageTransfer\'+$Configuration+'-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
[IO.Directory]::CreateDirectory($root)|Out-Null
$source=Join-Path $root 'source.png'
$bitmap=[Drawing.Bitmap]::new(128,128,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
$random=[Random]::new(731)
try {
    for($y=0;$y -lt 128;$y++){for($x=0;$x -lt 128;$x++){
        $bitmap.SetPixel($x,$y,[Drawing.Color]::FromArgb($random.Next(256),$random.Next(256),$random.Next(256),$random.Next(256)))
    }}
    $bitmap.Save($source,[Drawing.Imaging.ImageFormat]::Png)
} finally {$bitmap.Dispose()}
$bytes=[IO.File]::ReadAllBytes($source)
$hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
$sender=Join-Path $RepositoryRoot 'Tools\Send-ArtCommand.ps1'
$sendImage=Join-Path $RepositoryRoot 'Tools\Send-ArtImage.ps1'
$checks=[Collections.Generic.List[string]]::new()
$pipeName=$null; $app=$null
function Check([bool]$Value,[string]$Label){if(-not $Value){throw $Label};$checks.Add($Label)}
function Send-Art([string]$Command,[hashtable]$Arguments=@{}) {
    $raw=& $sender -PipeName $script:pipeName -Command $Command -ArgsJson ($Arguments|ConvertTo-Json -Compress -Depth 20) -TimeoutMs 30000
    ($raw|ConvertFrom-Json).data
}
function Reject([string]$Command,[hashtable]$Arguments,[string]$Pattern) {
    $message=$null
    try {$null=Send-Art $Command $Arguments} catch {$message=$_.Exception.Message}
    Check ($null -ne $message -and $message -like ('*'+$Pattern+'*')) ('Reject '+$Command+': '+$Pattern)
}
function Begin-Image([string]$Name,[string]$Sha=$hash,[int]$Size=$bytes.Length,[int]$Width=128,[int]$Height=128) {
    $id=[guid]::NewGuid().ToString('B')
    Send-Art 'image-begin' @{transferId=$id;jobId=$script:job.jobId;fileName=$Name;sha256=$Sha;sizeBytes=$Size;width=$Width;height=$Height}
}
function Chunks([string]$Id,[byte[]]$Data) {
    for($offset=0;$offset -lt $Data.Length;$offset+=12288){
        $count=[Math]::Min(12288,$Data.Length-$offset)
        $null=Send-Art 'image-chunk' @{transferId=$Id;offset=$offset;dataBase64=[Convert]::ToBase64String($Data,$offset,$count)}
    }
}
try {
    $history=Join-Path $root 'history'; [IO.Directory]::CreateDirectory($history)|Out-Null
    $oldHistory=$env:AIARTTOPSD_HISTORY_DIR; $env:AIARTTOPSD_HISTORY_DIR=$history
    try {$app=Start-Process -FilePath (Join-Path $RepositoryRoot ('Win64\'+$Configuration+'\AIArtToPSD.exe')) -ArgumentList ('"'+$source+'"') -WindowStyle Hidden -PassThru}
    finally {$env:AIARTTOPSD_HISTORY_DIR=$oldHistory}
    $deadline=[DateTime]::UtcNow.AddSeconds(20)
    while(-not $pipeName -and [DateTime]::UtcNow -lt $deadline){
        $folder=Join-Path $env:LOCALAPPDATA 'AIArtToPSD\pipes'
        if(Test-Path -LiteralPath $folder){foreach($file in Get-ChildItem -LiteralPath $folder -Filter '*.json'){
            $endpoint=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json
            if($endpoint.pid -eq $app.Id){$pipeName=$endpoint.pipeName;break}
        }}
        if(-not $pipeName){Start-Sleep -Milliseconds 100}
    }
    Check ([bool]$pipeName) 'Own test pipe found'
    $status=Send-Art 'status'
    Check ($status.canEdit -and $status.modified) 'PNG command-line startup opens editable new document'
    Check ($status.commands -contains 'image-begin' -and $status.commands -contains 'image-commit') 'Transfer commands advertised'
    $before=Send-Art 'document' @{limit=32;includePixelHashes=$true}
    $job=Send-Art 'export' @{prompt='Synthetic PNG transfer test only'}
    $request=Get-Content -LiteralPath (Join-Path $job.directory 'request.json') -Raw|ConvertFrom-Json
    $base=@{transferId=[guid]::NewGuid().ToString('B');jobId=$job.jobId;fileName='received.png';sha256=$hash;sizeBytes=$bytes.Length;width=128;height=128}
    $begin=Send-Art 'image-begin' $base; $again=Send-Art 'image-begin' $base
    Check ($begin.transferId -eq $again.transferId -and $again.receivedBytes -eq 0) 'Repeated begin returns same transfer'
    $changed=$base.Clone(); $changed.fileName='different.png'
    Reject 'image-begin' $changed 'different metadata'
    $bad=$base.Clone(); $bad.transferId=[guid]::NewGuid().ToString('B'); $bad.fileName='../escape.png'
    Reject 'image-begin' $bad 'basename'
    $bad.fileName='CON.png'; Reject 'image-begin' $bad 'Reserved'
    $bad.fileName='huge.png'; $bad.sizeBytes=33554433; Reject 'image-begin' $bad 'size limit'
    $bad.sizeBytes=$bytes.Length; $bad.sha256='bad'; Reject 'image-begin' $bad 'SHA256'
    $bad.sha256=$hash; $bad.jobId='unknown'; Reject 'image-begin' $bad 'jobId'
    Reject 'image-chunk' @{transferId=$begin.transferId;offset=1;dataBase64=[Convert]::ToBase64String($bytes,0,100)} 'offset/size'
    Reject 'image-chunk' @{transferId=$begin.transferId;offset=0;dataBase64='!!!!'} 'base64'
    Reject 'image-chunk' @{transferId=$begin.transferId;offset=0;dataBase64=[Convert]::ToBase64String([byte[]]::new(12289))} 'size limit'
    $partial=Send-Art 'image-chunk' @{transferId=$begin.transferId;offset=0;dataBase64=[Convert]::ToBase64String($bytes,0,100)}
    $duplicate=Send-Art 'image-chunk' @{transferId=$begin.transferId;offset=0;dataBase64=[Convert]::ToBase64String($bytes,0,100)}
    Check ($partial.receivedBytes -eq 100 -and $duplicate.receivedBytes -eq 100) 'Identical chunk retry is idempotent'
    $different=[byte[]]::new(100);[Array]::Copy($bytes,$different,100);$different[20]=$different[20]-bxor 1
    Reject 'image-chunk' @{transferId=$begin.transferId;offset=0;dataBase64=[Convert]::ToBase64String($different)} 'retry differs'
    Reject 'image-chunk' @{transferId=$begin.transferId;offset=50;dataBase64=[Convert]::ToBase64String($bytes,50,100)} 'partly overlaps'
    Reject 'image-commit' @{transferId=$begin.transferId} 'incomplete'
    Check (-not(Test-Path -LiteralPath (Join-Path $job.directory 'images\received.png'))) 'Partial data is not published as PNG'
    $saved=& $sendImage -PipeName $pipeName -JobId $job.jobId -InputPng $source -FileName 'received.png' -TransferId ([guid]$begin.transferId)
    Check ($saved.state -eq 'committed' -and $saved.receivedBytes -eq $bytes.Length) 'Client resumes transfer and commits all bytes'
    $received=Join-Path $job.directory $saved.path
    Check ((Get-FileHash -LiteralPath $received -Algorithm SHA256).Hash.ToLowerInvariant() -eq $hash) 'Committed file SHA256 equals source'
    Check (((Get-Item -LiteralPath $received).Attributes -band [IO.FileAttributes]::Temporary) -eq 0) 'Committed PNG is a normal durable file'
    $repeat=Send-Art 'image-commit' @{transferId=$begin.transferId}; Check ($repeat.state -eq 'committed') 'Repeated commit is idempotent'
    $collision=$base.Clone();$collision.transferId=[guid]::NewGuid().ToString('B');Reject 'image-begin' $collision 'already exists'
    $quota1=Begin-Image 'quota-1.png' $hash 33554432
    $quota2=Begin-Image 'quota-2.png' $hash 33554432
    $overQuota=$base.Clone();$overQuota.transferId=[guid]::NewGuid().ToString('B');$overQuota.fileName='quota-3.png'
    Reject 'image-begin' $overQuota 'total byte limit'
    $null=Send-Art 'image-abort' @{transferId=$quota1.transferId};$null=Send-Art 'image-abort' @{transferId=$quota2.transferId}
    $limited=[Collections.Generic.List[object]]::new()
    for($i=0;$i -lt 16;$i++){$limited.Add((Begin-Image ('limit-'+$i+'.png') $hash 64))}
    $overCount=$base.Clone();$overCount.transferId=[guid]::NewGuid().ToString('B');$overCount.fileName='limit-over.png'
    Reject 'image-begin' $overCount 'count limit'
    foreach($receipt in $limited){$null=Send-Art 'image-abort' @{transferId=$receipt.transferId}}
    Check (@(Get-ChildItem -LiteralPath (Join-Path $job.directory 'images') -Filter '*.part' -Force).Count -eq 0) 'Aborting quota/count fixtures releases private files'
    $wrong=Begin-Image 'wrong-hash.png' ('0'*64);Chunks $wrong.transferId $bytes
    Reject 'image-commit' @{transferId=$wrong.transferId} 'SHA256 mismatch'
    Check ((Send-Art 'image-status' @{transferId=$wrong.transferId}).state -eq 'failed') 'Wrong hash marks transfer failed'
    Check (-not(Test-Path -LiteralPath (Join-Path $job.directory 'images\wrong-hash.png'))) 'Wrong hash never publishes final file'
    $invalid=[byte[]]::new(64);$invalidHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($invalid)).ToLowerInvariant()
    $invalidBegin=Begin-Image 'invalid.png' $invalidHash 64;Chunks $invalidBegin.transferId $invalid
    Reject 'image-commit' @{transferId=$invalidBegin.transferId} 'PNG'
    $wrongDimensions=Begin-Image 'wrong-dimensions.png' $hash $bytes.Length 127 128;Chunks $wrongDimensions.transferId $bytes
    Reject 'image-commit' @{transferId=$wrongDimensions.transferId} 'dimensions mismatch'
    $abort=Begin-Image 'abort.png';$null=Send-Art 'image-abort' @{transferId=$abort.transferId}
    Check ((Send-Art 'image-abort' @{transferId=$abort.transferId}).state -eq 'aborted') 'Abort retry returns aborted state'
    Reject 'image-chunk' @{transferId=$abort.transferId;offset=0;dataBase64=[Convert]::ToBase64String($bytes,0,100)} 'not receiving'
    $race=Begin-Image 'race.png';Chunks $race.transferId $bytes
    [IO.File]::WriteAllText((Join-Path $job.directory 'images\race.png'),'existing fixture')
    Reject 'image-commit' @{transferId=$race.transferId} 'exists'
    Check ([IO.File]::ReadAllText((Join-Path $job.directory 'images\race.png')) -eq 'existing fixture') 'Destination race does not overwrite existing data'
    $after=Send-Art 'document' @{limit=32;includePixelHashes=$true}
    Check ($after.documentId -eq $before.documentId -and $after.revision -eq $before.revision -and $after.layers[0].pixelSha256 -eq $before.layers[0].pixelSha256) 'Receive commands do not edit document or revision'
    Check (@(Get-ChildItem -LiteralPath (Join-Path $job.directory 'images') -Filter '*.part' -Force).Count -eq 0) 'Abort and failed commit remove incomplete files'
    $asset=@{assetId='received';path=$saved.path;sha256=$hash;width=128;height=128;pixelFormat='RGBA8';colorSpace='sRGB'}
    $operation=@{op='add_layer';layerId=[guid]::NewGuid().ToString('B');name='received synthetic';parentId='';beforeLayerId='';visible=$true;opacity=255;assetId='received';bounds=@{left=0;top=0;right=128;bottom=128}}
    $result=@{schemaVersion=$request.schemaVersion;jobId=$request.jobId;requestId=$request.requestId;documentId=$request.documentId;ifRevision=$request.ifRevision;assets=@($asset);operations=@($operation)}
    [IO.File]::WriteAllText((Join-Path $job.directory 'result.json'),($result|ConvertTo-Json -Depth 16),[Text.UTF8Encoding]::new($false))
    $null=Send-Art 'import' @{jobId=$job.jobId};$imported=Send-Art 'document' @{includePixelHashes=$true;limit=32}
    Check ($imported.layerCount -eq 2 -and $imported.layers[0].pixelSha256 -eq $imported.layers[1].pixelSha256) 'Received PNG imports with identical RGBA'
    $cancelJob=Send-Art 'export' @{prompt='Cancellation cleanup only'};$mainJob=$job;$job=$cancelJob
    $cancelTransfer=Begin-Image 'cancelled.png';$null=Send-Art 'cancel' @{jobId=$cancelJob.jobId}
    Check ((Send-Art 'image-status' @{transferId=$cancelTransfer.transferId}).state -eq 'aborted') 'Job cancellation aborts unfinished receipt'
    $job=$mainJob
    $cleanupJob=Send-Art 'export' @{prompt='Save cleanup only'};$job=$cleanupJob
    $cleanupTransfer=Begin-Image 'unfinished-before-save.png'
    Check (@(Get-ChildItem -LiteralPath (Join-Path $cleanupJob.directory 'images') -Filter '*.part' -Force).Count -eq 1) 'Unfinished transfer remains private'
    $savedPsd=Join-Path $root 'received.psd'
    $null=Send-Art 'save' @{documentId=$imported.documentId;ifRevision=$imported.revision;fileName=$savedPsd}
    $reload=Send-Art 'document' @{includePixelHashes=$true;limit=32}
    Check (@(Get-ChildItem -LiteralPath (Join-Path $cleanupJob.directory 'images') -Filter '*.part' -Force).Count -eq 0) 'Document save/reset cleans unfinished transfers'
    Check (-not $reload.modified -and $reload.layerCount -eq 2 -and $reload.layers[0].pixelSha256 -eq $imported.layers[0].pixelSha256 -and $reload.layers[1].pixelSha256 -eq $imported.layers[1].pixelSha256) 'Pipe PSD save and reload retain received pixels'
    Check ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -eq $hash) 'Original synthetic PNG remains unchanged'
    $shutdownJob=Send-Art 'export' @{prompt='Shutdown cleanup only'};$job=$shutdownJob
    $shutdownTransfer=Begin-Image 'unfinished-before-shutdown.png'
    Check (@(Get-ChildItem -LiteralPath (Join-Path $shutdownJob.directory 'images') -Filter '*.part' -Force).Count -eq 1) 'Shutdown fixture has private unfinished file'
    Check ($app.CloseMainWindow()) 'Own clean test app accepts shutdown'
    $app.WaitForExit(5000)|Out-Null
    Check ($app.HasExited -and @(Get-ChildItem -LiteralPath (Join-Path $shutdownJob.directory 'images') -Filter '*.part' -Force).Count -eq 0) 'Normal app shutdown removes unfinished transfer'
    $verification=[ordered]@{passed=$true;configuration=$Configuration;checks=$checks;checkCount=$checks.Count;testRoot=$root;source=$source;sourceSha256=$hash;received=$received;receivedSha256=$hash;fileBytes=$bytes.Length;savedPsd=$savedPsd;cloudToWizTransferVerified=$false}
    [IO.File]::WriteAllText((Join-Path $root 'verification.json'),($verification|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    $verification|ConvertTo-Json -Depth 12
} catch {
    [IO.File]::WriteAllText((Join-Path $root 'failure.json'),(@{error=$_.Exception.Message;checks=$checks}|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    throw
} finally {
    if($app){
        $app.Refresh()
        if(-not $app.HasExited){
            try {if($pipeName -and -not (Send-Art 'status').modified){$app.CloseMainWindow()|Out-Null;$app.WaitForExit(2000)|Out-Null}} catch {}
            $app.Refresh()
            if(-not $app.HasExited){Stop-Process -Id $app.Id}
        }
    }
}

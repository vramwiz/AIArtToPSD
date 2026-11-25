#requires -Version 7.0
param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Win64/Release/AIArtToPSD.exe'),
    [switch]$KeepOpen
)
$ErrorActionPreference = 'Stop'
$root = Join-Path (Split-Path $PSScriptRoot -Parent) ('Tests/output/ArtRoute/' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($root)
$localData = Join-Path $root 'localappdata'
$endpointDirectory = Join-Path $localData 'AIArtToPSD/pipes'
$route = Join-Path $PSScriptRoot 'Invoke-ArtRoute.ps1'
$sender = Join-Path $PSScriptRoot 'Send-ArtCommand.ps1'
$checks = [Collections.Generic.List[string]]::new()
$app = $null; $passed = $false
function Check([bool]$Condition, [string]$Label) {
    if (-not $Condition) { throw $Label }
    $checks.Add($Label)
}
function Invoke-Route([string]$Command, [hashtable]$Arguments = @{}, [string]$Client = 'dot') {
    $json = @{command=$Command;args=$Arguments;requestId=[guid]::NewGuid().ToString()} | ConvertTo-Json -Depth 32 -Compress
    $raw = & $route -InputJson $json -ProcessId $app.Id -Client $Client -EndpointDirectory $endpointDirectory -TimeoutMs 10000
    $reply = $raw | ConvertFrom-Json
    if (-not $reply.ok) { throw $reply.error.message }
    Check ($reply.client -eq $Client) ('Application identifies ' + $Client + ' caller')
    Check ($reply.requestId.StartsWith($Client + ':')) ('Response correlates ' + $Client + ' request')
    $reply.data
}
function Write-Result($Job, $Operations, $Assets = @()) {
    $request = Get-Content -LiteralPath (Join-Path $Job.directory 'request.json') -Raw -Encoding utf8 | ConvertFrom-Json
    $manifest = @{schemaVersion=1;requestId=$request.requestId;jobId=$request.jobId;documentId=$request.documentId;ifRevision=$request.ifRevision;assets=@($Assets);operations=@($Operations)}
    $file = Join-Path $Job.directory 'result.json'
    if (Test-Path -LiteralPath $file) { throw 'Test result already exists' }
    [IO.File]::WriteAllText($file, ($manifest | ConvertTo-Json -Depth 32), [Text.UTF8Encoding]::new($false))
}
try {
    Add-Type -AssemblyName System.Drawing
    $source = Join-Path $root 'synthetic.png'
    $bitmap = [Drawing.Bitmap]::new(8,8)
    try {
        for ($y=0;$y -lt 8;$y++) { for ($x=0;$x -lt 8;$x++) { $bitmap.SetPixel($x,$y,[Drawing.Color]::FromArgb(255,30,90,150)) } }
        $bitmap.Save($source,[Drawing.Imaging.ImageFormat]::Png)
    } finally { $bitmap.Dispose() }
    $sourceHash = (Get-FileHash -LiteralPath $source).Hash
    $previousLocal = $env:LOCALAPPDATA; $previousHistory = $env:AIARTTOPSD_HISTORY_DIR
    try {
        $env:LOCALAPPDATA = $localData; $env:AIARTTOPSD_HISTORY_DIR = Join-Path $root 'history'
        $app = Start-Process -FilePath $Executable -ArgumentList ('"'+$source+'"') -WindowStyle Hidden -PassThru
    } finally { $env:LOCALAPPDATA = $previousLocal; $env:AIARTTOPSD_HISTORY_DIR = $previousHistory }
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    $endpoint = $null
    while (-not $endpoint -and [DateTime]::UtcNow -lt $deadline) {
        foreach ($file in @(Get-ChildItem -LiteralPath $endpointDirectory -Filter '*.json' -ErrorAction SilentlyContinue)) {
            $candidate = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            if ($candidate.pid -eq $app.Id) { $endpoint = $candidate; break }
        }
        if (-not $endpoint) { $app.Refresh(); if ($app.HasExited) { throw 'Test app exited before endpoint creation' }; Start-Sleep -Milliseconds 100 }
    }
    Check ([bool]$endpoint) 'Own isolated application endpoint found'
    $status = Invoke-Route 'status'
    Check ($status.clientRoutingVersion -eq 1 -and $status.supportedClients -contains 'dot') 'Built main application advertises native client routing'
    Check ($status.canEdit -and $status.modified) 'dot status reaches editable synthetic PNG document'
    $before = Invoke-Route 'document' @{includePixelHashes=$true}
    [IO.File]::WriteAllText((Join-Path $root 'dot-document-before.json'),($before | ConvertTo-Json -Depth 32))
    $fileInput = Join-Path $root 'status-input.json'
    [IO.File]::WriteAllText($fileInput,'{"command":"status","args":{},"requestId":"file-probe"}')
    $fileReply = (& $route -InputFile $fileInput -EndpointDirectory $endpointDirectory) | ConvertFrom-Json
    Check ($fileReply.ok -and $fileReply.requestId -eq 'dot:file-probe') 'JSON file input and single endpoint discovery work'
    $refused = (& $route -InputJson '{"command":"undo","args":{}}' -EndpointDirectory $endpointDirectory) | ConvertFrom-Json
    Check (-not $refused.ok -and $refused.error.message -like 'ProcessId is required*') 'Mutation without explicit process is refused'
    $duplicate = (& $route -InputJson '{"command":"status","command":"undo","args":{}}' -ProcessId $app.Id -EndpointDirectory $endpointDirectory) | ConvertFrom-Json
    Check (-not $duplicate.ok -and $duplicate.error.message -eq 'Duplicate JSON field') 'Duplicate JSON fields are refused before connecting'
    $missing = (& $route -ProcessId 2147483647 -EndpointDirectory $endpointDirectory) | ConvertFrom-Json
    Check (-not $missing.ok -and $missing.error.message -like '*found 0*') 'Nonexistent process is refused without selecting another app'
    # A stale descriptor is ignored; two live descriptors are ambiguous and must be refused.
    $staleFile = Join-Path $endpointDirectory 'stale-test.json'
    [IO.File]::WriteAllText($staleFile,'{"schemaVersion":1,"pid":2147483647,"pipeName":"old"}')
    $withStale = (& $route -EndpointDirectory $endpointDirectory) | ConvertFrom-Json
    Check $withStale.ok 'Stale endpoint descriptor is ignored'
    Remove-Item -LiteralPath $staleFile
    $extraFile = Join-Path $endpointDirectory 'duplicate-test.json'
    [IO.File]::WriteAllText($extraFile,($endpoint | ConvertTo-Json))
    try {
        $ambiguous = (& $route -EndpointDirectory $endpointDirectory) | ConvertFrom-Json
        Check (-not $ambiguous.ok -and $ambiguous.error.message -like '*found 2*') 'Ambiguous live endpoints are refused'
    } finally { Remove-Item -LiteralPath $extraFile }
    $bad = (& $route -InputJson '{"command":"image-status","args":{"transferId":"missing"}}' -ProcessId $app.Id -EndpointDirectory $endpointDirectory) | ConvertFrom-Json
    Check (-not $bad.ok -and $bad.error.code -eq 'command_failed') 'Application error returns one structured JSON response'
    $legacy = (& $sender -PipeName $endpoint.pipeName -Command status) | ConvertFrom-Json
    Check ($legacy.ok -and $legacy.client -eq 'codex' -and $legacy.requestId -notlike '*:*' -and $legacy.data.documentId -eq $before.documentId) 'Unmodified legacy invocation is treated as Codex and reaches same document'
    # Start two real clients together; the single-instance server must serialize them.
    $dotJob = Start-ThreadJob -ScriptBlock { param($tool,$ownerId,$folder) & $tool -ProcessId $ownerId -EndpointDirectory $folder -TimeoutMs 10000 } -ArgumentList $route,$app.Id,$endpointDirectory
    $codexJob = Start-ThreadJob -ScriptBlock { param($tool,$pipe) & $tool -PipeName $pipe -Command status -TimeoutMs 10000 } -ArgumentList $sender,$endpoint.pipeName
    try {
        $null = @($dotJob,$codexJob) | Wait-Job -Timeout 20
        $dotReply = (Receive-Job $dotJob -ErrorAction Stop) | ConvertFrom-Json
        $codexReply = (Receive-Job $codexJob -ErrorAction Stop) | ConvertFrom-Json
        Check ($dotReply.ok -and $codexReply.ok -and $dotReply.client -eq 'dot' -and $codexReply.client -eq 'codex' -and $dotReply.data.documentId -eq $codexReply.data.documentId) 'Concurrent dot and legacy Codex status calls both complete with native identification on same app'
    } finally { @($dotJob,$codexJob) | Remove-Job -Force }
    $job = Invoke-Route 'export' @{prompt='dot synthetic registration test; preserve original pixels'}
    $rival = Invoke-Route 'export' @{prompt='Codex competing snapshot for stale revision test'} 'codex'
    Check ($job.client -eq 'dot' -and $rival.client -eq 'codex') 'Application assigns distinct job owners'
    $issued = Get-Content -LiteralPath (Join-Path $job.directory 'request.json') -Raw -Encoding utf8 | ConvertFrom-Json
    $jobConnection = Get-Content -LiteralPath (Join-Path $job.directory 'connection.json') -Raw -Encoding utf8 | ConvertFrom-Json
    Check ($issued.client -eq 'dot' -and $jobConnection.client -eq 'dot' -and $jobConnection.clientRoutingVersion -eq 1) 'Job request and reconnect descriptor preserve dot ownership'
    $dotStatus = Invoke-Route 'status'
    Check ($dotStatus.job.jobId -eq $job.jobId) 'dot status defaults to its own latest job'
    $codexStatus = Invoke-Route 'status' @{} 'codex'
    Check ($codexStatus.job.jobId -eq $rival.jobId) 'Codex status defaults to its own latest job'
    $foreignJson = @{command='cancel';args=@{jobId=$job.jobId}} | ConvertTo-Json -Compress
    $foreign = (& $route -InputJson $foreignJson -ProcessId $app.Id -Client codex -EndpointDirectory $endpointDirectory) | ConvertFrom-Json
    Check (-not $foreign.ok -and $foreign.error.message -like 'Job belongs to another client:*') 'Codex cannot cancel a dot job'
    $assetPath = Join-Path $job.directory 'images/part.png'
    $received = & (Join-Path $PSScriptRoot 'Send-ArtImage.ps1') -PipeName $endpoint.pipeName -JobId $job.jobId -InputPng $source -FileName 'part.png' -Client dot
    Check ($received.state -eq 'committed' -and (Get-FileHash -LiteralPath $assetPath).Hash -eq $sourceHash) 'dot image transfer commits the unchanged synthetic PNG'
    $foreignTransfer = @{command='image-abort';args=@{transferId=$received.transferId}} | ConvertTo-Json -Compress
    $foreign = (& $route -InputJson $foreignTransfer -ProcessId $app.Id -Client codex -EndpointDirectory $endpointDirectory) | ConvertFrom-Json
    Check (-not $foreign.ok -and $foreign.error.message -like 'Job belongs to another client:*') 'Codex cannot modify a dot image receipt'
    $asset = @{assetId='part';path='images/part.png';sha256=$sourceHash.ToLowerInvariant();width=8;height=8;pixelFormat='RGBA8';colorSpace='sRGB'}
    $groupId=[guid]::NewGuid().ToString('B'); $layerId=[guid]::NewGuid().ToString('B')
    $ops = @(
        @{op='add_group';layerId=$groupId;name='dot通信試験';parentId='';beforeLayerId='';visible=$true;opacity=255},
        @{op='add_layer';layerId=$layerId;name='試験パーツ';parentId=$groupId;beforeLayerId='';visible=$true;opacity=255;assetId='part';bounds=@{left=0;top=0;right=8;bottom=8}}
    )
    Write-Result $job $ops @($asset)
    Write-Result $rival @(@{op='rename_layer';layerId=$before.layers[0].layerId;name='must not apply'})
    $imported = Invoke-Route 'import' @{jobId=$job.jobId}
    Check ($imported.state -eq 'completed') 'dot registers group and PNG layer through existing import'
    $missingRevision = (& $route -InputJson '{"command":"undo","args":{}}' -ProcessId $app.Id -EndpointDirectory $endpointDirectory) | ConvertFrom-Json
    Check (-not $missingRevision.ok) 'dot undo without inspected document revision is refused'
    $added = Invoke-Route 'document' @{includePixelHashes=$true}
    Check ($added.layerCount -eq 3 -and $added.layers[0].pixelSha256 -eq $before.layers[0].pixelSha256) 'Registration preserves original image and adds exactly two nodes'
    $part = @($added.layers | Where-Object layerId -eq $layerId)[0]
    Check ($part.parentId -eq $groupId -and $part.pixelSha256 -eq $before.layers[0].pixelSha256) 'Registered part hierarchy and RGBA hash match synthetic PNG'
    $again = Invoke-Route 'import' @{jobId=$job.jobId}
    Check ((Invoke-Route 'document').revision -eq $added.revision) 'Identical import retry does not apply twice'
    $staleJson = @{command='import';args=@{jobId=$rival.jobId};requestId='stale-rival'} | ConvertTo-Json -Compress
    $stale = (& $route -InputJson $staleJson -ProcessId $app.Id -Client codex -EndpointDirectory $endpointDirectory) | ConvertFrom-Json
    Check (-not $stale.ok -and $stale.error.message -like '*文書が変更*' -and (Invoke-Route 'document').revision -eq $added.revision) 'Competing older Codex result is refused by revision validation without modifying document'
    [IO.File]::WriteAllText((Join-Path $root 'stale-response.json'),($stale | ConvertTo-Json -Depth 16))
    $historyState = Invoke-Route 'document'
    $null = Invoke-Route 'undo' @{documentId=$historyState.documentId;ifRevision=$historyState.revision}
    Check ((Invoke-Route 'document').layerCount -eq 1) 'Undo removes only the synthetic registration'
    $historyState = Invoke-Route 'document'
    $null = Invoke-Route 'redo' @{documentId=$historyState.documentId;ifRevision=$historyState.revision}
    Check ((Invoke-Route 'document').layerCount -eq 3) 'Redo restores synthetic registration'
    $current = Invoke-Route 'document'
    $savedPath = Join-Path $root 'dot-route-test.psd'
    $saved = Invoke-Route 'save' @{documentId=$current.documentId;ifRevision=$current.revision;fileName=$savedPath}
    Check (-not $saved.modified -and $saved.layerCount -eq 3) 'New-name PSD save reloads registered layers'
    Check ((Get-FileHash -LiteralPath $source).Hash -eq $sourceHash) 'Synthetic source PNG remains unchanged'
    $probe = (& $route -ProcessId $app.Id -EndpointDirectory $endpointDirectory) | ConvertFrom-Json
    [IO.File]::WriteAllText((Join-Path $root 'dot-status-response.json'),($probe | ConvertTo-Json -Depth 32))
    $passed = $true
    $result = [ordered]@{passed=$true;checks=$checks;checkCount=$checks.Count;testRoot=$root;executable=$Executable;executableSha256=(Get-FileHash -LiteralPath $Executable).Hash;pid=$app.Id;pipeName=$endpoint.pipeName;endpointDirectory=$endpointDirectory;savedPsd=$savedPath;keptOpen=[bool]$KeepOpen}
    [IO.File]::WriteAllText((Join-Path $root 'verification.json'),($result | ConvertTo-Json -Depth 32))
    $result | ConvertTo-Json -Depth 32
} catch {
    [IO.File]::WriteAllText((Join-Path $root 'failure.json'),(@{error=$_.Exception.Message;checks=$checks} | ConvertTo-Json -Depth 16))
    throw
} finally {
    if ($app -and -not ($passed -and $KeepOpen)) {
        $app.Refresh()
        if (-not $app.HasExited) {
            if ($passed) { $null=$app.CloseMainWindow(); $null=$app.WaitForExit(3000) }
            $app.Refresh(); if (-not $app.HasExited) { Stop-Process -Id $app.Id }
        }
    }
}

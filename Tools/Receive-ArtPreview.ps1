#requires -Version 7.0
param(
    [Parameter(Mandatory)][string]$PipeName,
    [Parameter(Mandatory)][string]$DocumentId,
    [Parameter(Mandatory)][string]$Revision,
    [Parameter(Mandatory)][string]$OutputPng,
    [ValidateSet('codex','dot')][string]$Client='dot'
)
$ErrorActionPreference='Stop'
$sender=Join-Path $PSScriptRoot 'Send-ArtCommand.ps1'
$destination=[IO.Path]::GetFullPath($OutputPng)
if(Test-Path -LiteralPath $destination){throw 'Preview destination already exists'}
if(-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($destination))){throw 'Preview parent directory is missing'}
function Send-Preview([string]$Command,[hashtable]$Arguments){
    $raw=& $sender -PipeName $PipeName -Command $Command -Client $Client -ArgsJson ($Arguments|ConvertTo-Json -Depth 16 -Compress) -TimeoutMs 60000
    ($raw|ConvertFrom-Json).data
}
$receipt=Send-Preview 'preview' @{documentId=$DocumentId;ifRevision=$Revision}
if($receipt.sizeBytes -lt 1 -or $receipt.sizeBytes -gt 33554432){throw 'Invalid preview size'}
$temporary=$destination+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
$output=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{
    $offset=0
    while($offset -lt $receipt.sizeBytes){
        $chunk=Send-Preview 'preview-read' @{previewId=$receipt.previewId;offset=$offset;count=12288}
        $bytes=[Convert]::FromBase64String($chunk.dataBase64)
        if($chunk.offset -ne $offset -or $chunk.count -ne $bytes.Length -or $bytes.Length -lt 1 -or $bytes.Length -gt 12288 -or $chunk.sha256 -ne $receipt.sha256){throw 'Invalid preview chunk acknowledgement'}
        if($offset+$bytes.Length -gt $receipt.sizeBytes){throw 'Preview exceeds announced size'}
        $output.Write($bytes,0,$bytes.Length);$offset+=$bytes.Length
    }
    $output.Flush($true);$output.Dispose()
    if((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToLowerInvariant() -ne $receipt.sha256){throw 'Preview SHA256 mismatch'}
    [IO.File]::Move($temporary,$destination)
    [ordered]@{previewId=$receipt.previewId;fileName=$destination;documentId=$receipt.documentId;revision=$receipt.revision;width=$receipt.width;height=$receipt.height;sha256=$receipt.sha256;pixelSha256=$receipt.pixelSha256}
}finally{$output.Dispose();if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary}}

#requires -Version 7.0
param(
    [Parameter(Mandatory=$true)][string]$PipeName,
    [Parameter(Mandatory=$true)][string]$JobId,
    [Parameter(Mandatory=$true)][string]$InputPng,
    [string]$FileName,
    [guid]$TransferId=[guid]::NewGuid()
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$source=[IO.Path]::GetFullPath($InputPng)
$sender=Join-Path $PSScriptRoot 'Send-ArtCommand.ps1'
if(-not $FileName){$FileName='received-'+$TransferId.ToString('N')+'.png'}
function Send-ImageCommand([string]$Command,[hashtable]$Arguments) {
    $response=& $sender -PipeName $PipeName -Command $Command -ArgsJson ($Arguments|ConvertTo-Json -Compress -Depth 16) -TimeoutMs 30000
    $reply=$response|ConvertFrom-Json
    if(-not $reply.ok){throw $reply.error.message}
    $reply.data
}
$stream=[IO.File]::Open($source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try {
    if($stream.Length -lt 24 -or $stream.Length -gt 33554432){throw 'PNG file must be 24 bytes to 32 MiB.'}
    $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant()
    $stream.Position=0
    $image=[Drawing.Image]::FromStream($stream,$false,$true)
    try {$width=$image.Width; $height=$image.Height} finally {$image.Dispose()}
    $stream.Position=0
    $receipt=Send-ImageCommand 'image-begin' @{transferId=$TransferId.ToString('B');jobId=$JobId;fileName=$FileName;sizeBytes=[int]$stream.Length;sha256=$hash;width=$width;height=$height}
    if($receipt.state -eq 'committed'){return $receipt}
    if($receipt.state -ne 'receiving'){throw 'Transfer cannot be resumed; begin a new transfer.'}
    $buffer=[byte[]]::new([int]$receipt.maxChunkBytes)
    $offset=[int]$receipt.receivedBytes
    $stream.Position=$offset
    while($offset -lt $stream.Length) {
        $count=$stream.Read($buffer,0,[Math]::Min($buffer.Length,[int]($stream.Length-$offset)))
        if($count -le 0){throw 'Unexpected source EOF.'}
        $chunk=Send-ImageCommand 'image-chunk' @{transferId=$TransferId.ToString('B');offset=$offset;dataBase64=[Convert]::ToBase64String($buffer,0,$count)}
        if([int]$chunk.receivedBytes -ne $offset+$count){throw 'Chunk acknowledgement offset differs.'}
        $offset+=$count
    }
    $saved=Send-ImageCommand 'image-commit' @{transferId=$TransferId.ToString('B')}
    if($saved.state -ne 'committed' -or $saved.sha256 -ne $hash -or $saved.receivedBytes -ne $stream.Length){throw 'Image commit verification failed.'}
    $saved
} finally {$stream.Dispose()}
# On an uncertain connection failure the transfer is retained for 15 minutes.
# Retry with the same TransferId and metadata to resume from acknowledged bytes.

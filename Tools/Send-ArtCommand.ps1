#requires -Version 7.0
param(
    [Parameter(Mandatory=$true)][string]$PipeName,
    [Parameter(Mandatory=$true)][ValidateSet('status','export','import','progress','cancel','undo','redo','recover')][string]$Command,
    [string]$ArgsJson = '{}',
    [ValidateRange(1,60000)][int]$TimeoutMs = 5000
)
$ErrorActionPreference = 'Stop'
$arguments = ConvertFrom-Json -InputObject $ArgsJson -AsHashtable
if ($arguments -isnot [System.Collections.IDictionary]) { throw 'ArgsJson must be a JSON object' }
$envelope = @{ schemaVersion=1; requestId=[guid]::NewGuid().ToString(); command=$Command; args=$arguments }
$payload = [Text.Encoding]::UTF8.GetBytes(($envelope | ConvertTo-Json -Depth 32 -Compress))
if ($payload.Length -gt 60000) { throw 'Command exceeds 60000 UTF-8 bytes' }
$client = [IO.Pipes.NamedPipeClientStream]::new('.', $PipeName, [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::Asynchronous)
try {
    $client.Connect($TimeoutMs)
    $client.ReadMode = [IO.Pipes.PipeTransmissionMode]::Message
    $write = $client.WriteAsync($payload,0,$payload.Length)
    if (-not $write.Wait($TimeoutMs)) { throw 'Pipe write timed out' }
    $buffer = [byte[]]::new(65536)
    $read = $client.ReadAsync($buffer,0,$buffer.Length)
    if (-not $read.Wait($TimeoutMs)) { throw 'Pipe response timed out' }
    $received = $read.GetAwaiter().GetResult()
    if (($received -eq 0) -or (-not $client.IsMessageComplete)) { throw 'Incomplete pipe response' }
    $response = [Text.Encoding]::UTF8.GetString($buffer,0,$received) | ConvertFrom-Json
    if ($response.requestId -ne $envelope.requestId) { throw 'Response requestId mismatch' }
    $response | ConvertTo-Json -Depth 32
    if (-not $response.ok) { throw $response.error.message }
} finally {
    $client.Dispose()
}




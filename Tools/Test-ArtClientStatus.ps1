#requires -Version 7.0
param([Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$ProcessId)
$ErrorActionPreference = 'Stop'
$route = Join-Path $PSScriptRoot 'Invoke-ArtRoute.ps1'
$dot = (& $route -ProcessId $ProcessId -Client dot -InputJson '{"command":"status","args":{},"requestId":"native-dot-check"}') | ConvertFrom-Json
if (-not $dot.ok -or $dot.client -ne 'dot' -or $dot.data.clientRoutingVersion -ne 1) {
    if (-not $dot.ok) { throw ('dot status failed: ' + $dot.error.message) }
    throw 'Updated main application did not identify the dot request'
}
$codex = (& $route -ProcessId $ProcessId -Client codex -InputJson '{"command":"status","args":{},"requestId":"native-codex-check"}') | ConvertFrom-Json
if (-not $codex.ok -or $codex.client -ne 'codex' -or $codex.data.documentId -ne $dot.data.documentId) {
    if (-not $codex.ok) { throw ('Codex status failed: ' + $codex.error.message) }
    throw 'Codex and dot did not reach the same application document'
}
$legacy = (& (Join-Path $PSScriptRoot 'Send-ArtCommand.ps1') -PipeName $dot.data.pipeName -Command status) | ConvertFrom-Json
if (-not $legacy.ok -or $legacy.client -ne 'codex' -or $legacy.data.documentId -ne $dot.data.documentId) {
    throw 'Legacy Codex request failed'
}
foreach ($name in @('codex','dot')) {
    $contact = @($legacy.data.clients | Where-Object client -eq $name)
    if ($contact.Count -ne 1 -or -not $contact[0].seen) { throw ('Missing native client contact: ' + $name) }
}
[ordered]@{passed=$true;readOnly=$true;pid=$ProcessId;pipeName=$dot.data.pipeName;dotRequestId=$dot.requestId;codexRequestId=$codex.requestId;legacyRequestId=$legacy.requestId;clients=$legacy.data.clients} | ConvertTo-Json -Depth 16

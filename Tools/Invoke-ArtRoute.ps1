#requires -Version 7.0
[CmdletBinding(DefaultParameterSetName='Json')]
param(
    [Parameter(ParameterSetName='Json')][string]$InputJson = '{"command":"status","args":{}}',
    [Parameter(Mandatory,ParameterSetName='File')][string]$InputFile,
    [ValidateRange(1,2147483647)][int]$ProcessId,
    [string]$EndpointDirectory,
    [ValidateSet('dot','codex')][string]$Client = 'dot',
    [ValidateRange(1,60000)][int]$TimeoutMs = 5000
)
$ErrorActionPreference = 'Stop'
$requestId = $Client + ':' + [guid]::NewGuid().ToString()
try {
    if ($PSCmdlet.ParameterSetName -eq 'File') {
        $InputJson = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $InputFile).Path, [Text.Encoding]::UTF8)
    }
    # JsonDocument also lets us reject duplicate fields, before ConvertFrom-Json collapses them.
    $parsed = [Text.Json.JsonDocument]::Parse($InputJson)
    try {
        function Test-UniqueFields($Element, [int]$Depth = 0) {
            if ($Depth -gt 32) { throw 'JSON nesting limit' }
            if ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
                $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                foreach ($field in $Element.EnumerateObject()) {
                    if (-not $names.Add($field.Name)) { throw 'Duplicate JSON field' }
                    Test-UniqueFields $field.Value ($Depth + 1)
                }
            } elseif ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
                foreach ($item in $Element.EnumerateArray()) { Test-UniqueFields $item ($Depth + 1) }
            }
        }
        Test-UniqueFields $parsed.RootElement
    } finally { $parsed.Dispose() }
    $inputObject = ConvertFrom-Json -InputObject $InputJson -AsHashtable
    if ($inputObject -isnot [Collections.IDictionary]) { throw 'Input must be a JSON object' }
    foreach ($key in $inputObject.Keys) {
        if ($key -cnotin @('command','args','requestId')) { throw ('Unknown input field: ' + $key) }
    }
    if ($inputObject.command -isnot [string] -or $inputObject.args -isnot [Collections.IDictionary]) {
        throw 'command string and args object are required'
    }
    if ($inputObject.Contains('requestId')) {
        if ($inputObject.requestId -isnot [string] -or $inputObject.requestId -notmatch '^[A-Za-z0-9._:-]{1,120}$') {
            throw 'requestId must be 1-120 ASCII letters, digits, dot, underscore, colon or hyphen'
        }
        $requestId = $Client + ':' + $inputObject.requestId
    }
    $readOnly = $inputObject.command -cin @('status','document','image-status','preview-read')
    if (-not $readOnly -and -not $PSBoundParameters.ContainsKey('ProcessId')) {
        throw 'ProcessId is required for commands that can change application or job state'
    }
    # AppContainer rewrites LOCALAPPDATA. Also inspect this user's normal profile,
    # but never treat an unverified descriptor as permission to connect.
    if ($PSBoundParameters.ContainsKey('EndpointDirectory')) {
        $endpointDirectories = @($EndpointDirectory)
    } else {
        $endpointDirectories = @(
            (Join-Path $env:LOCALAPPDATA 'AIArtToPSD/pipes')
            (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'AIArtToPSD/pipes')
            (Join-Path $env:USERPROFILE 'AppData/Local/AIArtToPSD/pipes')
        ) | Sort-Object -Unique
    }
    $unverifiedPids = [Collections.Generic.List[int]]::new()
    $endpoints = @(Get-ChildItem -LiteralPath $endpointDirectories -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $endpoint = Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8 | ConvertFrom-Json
            $expectedPrefix = 'AIArtToPSD.' + $endpoint.pid + '.'
            if ($endpoint.schemaVersion -ne 1 -or $endpoint.pipeName -isnot [string] -or
                -not $endpoint.pipeName.StartsWith($expectedPrefix, [StringComparison]::Ordinal) -or
                $endpoint.pipeName -notmatch '^AIArtToPSD\.[0-9]+\.\{[0-9A-Fa-f-]{36}\}$' -or
                ($PSBoundParameters.ContainsKey('ProcessId') -and $endpoint.pid -ne $ProcessId)) { return }
            try { $owner = Get-Process -Id $endpoint.pid -ErrorAction Stop }
            catch { $unverifiedPids.Add([int]$endpoint.pid); return }
            if ($owner.ProcessName -ceq 'AIArtToPSD') { $endpoint }
        } catch { Write-Verbose ('Ignored stale/invalid endpoint: ' + $_.Exception.Message) }
    })
    if ($unverifiedPids.Count -gt 0) {
        Write-Verbose ('Unverified endpoint PID(s): ' + (($unverifiedPids | Sort-Object -Unique) -join ', '))
        if ($endpoints.Count -eq 0) {
            throw ('Connection descriptor found for PID(s) ' + (($unverifiedPids | Sort-Object -Unique) -join ', ') +
                ', but their processes cannot be verified. They may be stale or outside this execution scope. Use the approved normal-user execution route to verify; do not change pipe access rights.')
        }
    }
    if ($endpoints.Count -ne 1) {
        throw ('Expected one live app endpoint; found ' + $endpoints.Count + '. Specify ProcessId after checking the intended document.')
    }
    if ($Client -eq 'dot' -and ($endpoints[0].clientRoutingVersion -ne 1 -or $endpoints[0].supportedClients -cnotcontains 'dot')) {
        throw 'Application does not advertise dot client routing. Build and start the updated AIArtToPSD main project.'
    }
    $reply = & (Join-Path $PSScriptRoot 'Send-ArtCommand.ps1') -PipeName $endpoints[0].pipeName `
        -Command $inputObject.command -ArgsJson ($inputObject.args | ConvertTo-Json -Depth 32 -Compress) `
        -RequestId $requestId -Client $Client -TimeoutMs $TimeoutMs -NoThrowOnCommandError
    $reply
    if (-not ($reply | ConvertFrom-Json).ok) { exit 1 }
    exit 0
} catch {
    [ordered]@{schemaVersion=1;requestId=$requestId;ok=$false;error=@{code='route_failed';message=$_.Exception.Message}} | ConvertTo-Json -Depth 8
    exit 1
}

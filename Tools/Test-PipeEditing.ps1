#requires -Version 7.0
param(
    [string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent),
    [ValidateSet('Debug','Release')][string]$Configuration = 'Debug',
    [string]$InputPsd = 'C:\Users\zan12\Documents\SYNC_MusicStudio\Characters\PSD\東北きりたん_立ち絵.psd',
    [switch]$KeepOpen
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
if (-not ('ArtPreviewVerification' -as [type])) {
    $previewReferences = @([Drawing.Bitmap].Assembly.Location, [Drawing.Rectangle].Assembly.Location,
        [Runtime.InteropServices.Marshal].Assembly.Location, (Join-Path $PSHOME 'System.Runtime.dll'))
    $previewReferences += @(Get-ChildItem -LiteralPath $PSHOME -Filter 'System.Private.Windows*.dll' | ForEach-Object FullName)
    Add-Type -ReferencedAssemblies $previewReferences -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class ArtPreviewVerification {
    public static bool OutsideMarkerUnchanged(string beforePath, string afterPath) {
        using (var before = new Bitmap(beforePath))
        using (var after = new Bitmap(afterPath)) {
            if (before.Width != after.Width || before.Height != after.Height) return false;
            var rectangle = new Rectangle(0, 0, before.Width, before.Height);
            var first = before.LockBits(rectangle, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            var second = after.LockBits(rectangle, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try {
                var firstRow = new byte[before.Width * 4];
                var secondRow = new byte[before.Width * 4];
                for (int y = 0; y < before.Height; y++) {
                    Marshal.Copy(IntPtr.Add(first.Scan0, y * first.Stride), firstRow, 0, firstRow.Length);
                    Marshal.Copy(IntPtr.Add(second.Scan0, y * second.Stride), secondRow, 0, secondRow.Length);
                    int start = y < 16 ? 16 * 4 : 0;
                    for (int x = start; x < firstRow.Length; x++)
                        if (firstRow[x] != secondRow[x]) return false;
                }
                return true;
            } finally { before.UnlockBits(first); after.UnlockBits(second); }
        }
    }
}
"@
}
$testRoot = Join-Path $RepositoryRoot ('Win64\Validation\PipeAutomation\' + $Configuration + '-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
[void][IO.Directory]::CreateDirectory($testRoot)
$sourceHash = (Get-FileHash -LiteralPath $InputPsd -Algorithm SHA256).Hash
$inputCopy = Join-Path $testRoot 'input-copy.psd'
[IO.File]::Copy($InputPsd,$inputCopy,$false)
$historyRoot = Join-Path $testRoot 'history'
[void][IO.Directory]::CreateDirectory($historyRoot)
$sender = Join-Path $RepositoryRoot 'Tools\Send-ArtCommand.ps1'
$executable = Join-Path $RepositoryRoot ('Win64\' + $Configuration + '\AIArtToPSD.exe')
$checks = [Collections.Generic.List[string]]::new()
$pipeName = $null
$application = $null
function Assert-Check([bool]$Condition,[string]$Label) {
    if (-not $Condition) { throw $Label }
    $checks.Add($Label)
}
function Send-Art([string]$Command,[hashtable]$Arguments=@{}) {
    $raw = & $sender -PipeName $script:pipeName -Command $Command -ArgsJson ($Arguments | ConvertTo-Json -Depth 32 -Compress) -TimeoutMs 60000
    $reply = $raw | ConvertFrom-Json
    if (-not $reply.ok) { throw $reply.error.message }
    $reply.data
}
function Get-Document {
    $page = Send-Art 'document' @{offset=0;limit=32;includePixelHashes=$true}
    $layers = [Collections.Generic.List[object]]::new()
    foreach ($layer in $page.layers) { $layers.Add($layer) }
    while ($page.hasMore) {
        $next = Send-Art 'document' @{offset=$layers.Count;limit=32;includePixelHashes=$true}
        if ($next.documentId -ne $page.documentId -or $next.revision -ne $page.revision) { throw 'Document changed while paging' }
        foreach ($layer in $next.layers) { $layers.Add($layer) }
        $page = $next
    }
    $page.layers = $layers.ToArray()
    $page
}
function Expect-Rejection([string]$Command,[hashtable]$Arguments,[string]$Message) {
    $rejected = $false
    try { $null = Send-Art $Command $Arguments }
    catch { if ($_.Exception.Message -notlike ('*'+$Message+'*')) { throw }; $rejected = $true }
    Assert-Check $rejected ('Refused: '+$Message)
}
function Write-Asset([string]$Directory,[string]$Name,[Drawing.Color]$Color) {
    [void][IO.Directory]::CreateDirectory((Join-Path $Directory 'images'))
    $path = Join-Path $Directory ('images\'+$Name+'.png')
    $bitmap = [Drawing.Bitmap]::new(16,16,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try { for($y=0;$y -lt 16;$y++){for($x=0;$x -lt 16;$x++){$bitmap.SetPixel($x,$y,$Color)}}; $bitmap.Save($path,[Drawing.Imaging.ImageFormat]::Png) }
    finally { $bitmap.Dispose() }
    $rgba = [byte[]]::new(16*16*4)
    for($i=0;$i -lt $rgba.Length;$i+=4){$rgba[$i]=$Color.R;$rgba[$i+1]=$Color.G;$rgba[$i+2]=$Color.B;$rgba[$i+3]=$Color.A}
    @{
        assetId=$Name;path=('images/'+$Name+'.png');sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        width=16;height=16;pixelFormat='RGBA8';colorSpace='sRGB'
        expectedPixels=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($rgba)).ToLowerInvariant()
    }
}
function Import-Operations($Job,$Asset,$Operations) {
    $request = Get-Content -LiteralPath (Join-Path $Job.directory 'request.json') -Raw -Encoding utf8 | ConvertFrom-Json
    $result = [ordered]@{
        schemaVersion=$request.schemaVersion;requestId=$request.requestId;jobId=$request.jobId
        documentId=$request.documentId;ifRevision=$request.ifRevision
        assets=@(@{assetId=$Asset.assetId;path=$Asset.path;sha256=$Asset.sha256;width=$Asset.width;height=$Asset.height;pixelFormat=$Asset.pixelFormat;colorSpace=$Asset.colorSpace})
        operations=@($Operations)
    }
    $path = Join-Path $Job.directory 'result.json'
    if (Test-Path -LiteralPath $path) { throw 'Existing result is preserved' }
    [IO.File]::WriteAllText($path,($result | ConvertTo-Json -Depth 32),[Text.UTF8Encoding]::new($false))
    $imported = Send-Art 'import' @{jobId=$Job.jobId}
    Assert-Check ($imported.state -eq 'completed') 'Import completed'
}
function Check-Preview([string]$Path,[Drawing.Color]$Color,[string]$Label) {
    $bitmap = [Drawing.Bitmap]::new($Path)
    try { $pixel=$bitmap.GetPixel(5,5); Assert-Check ($pixel.ToArgb() -eq $Color.ToArgb()) $Label }
    finally { $bitmap.Dispose() }
}
try {
    $priorHistory = $env:AIARTTOPSD_HISTORY_DIR
    try {
        $env:AIARTTOPSD_HISTORY_DIR = $historyRoot
        $application = Start-Process -FilePath $executable -ArgumentList ('"'+$inputCopy+'"') -WorkingDirectory (Split-Path $executable -Parent) -WindowStyle Hidden -PassThru
    } finally { $env:AIARTTOPSD_HISTORY_DIR = $priorHistory }
    $endpointRoot = Join-Path $env:LOCALAPPDATA 'AIArtToPSD\pipes'
    for($attempt=0;$attempt -lt 100;$attempt++) {
        foreach($endpointFile in @(Get-ChildItem -LiteralPath $endpointRoot -File -Filter '*.json' -ErrorAction SilentlyContinue)) {
            $endpoint = Get-Content -LiteralPath $endpointFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json
            if ($endpoint.pid -eq $application.Id) { $pipeName=$endpoint.pipeName; break }
        }
        if($pipeName){break}
        $application.Refresh();if($application.HasExited){throw 'Test application exited before endpoint creation'}
        Start-Sleep -Milliseconds 100
    }
    Assert-Check (-not [string]::IsNullOrWhiteSpace($pipeName)) 'Fresh endpoint belongs to launched application'
    $status = Send-Art 'status'
    Assert-Check ($status.canEdit -and $status.documentId -and -not $status.modified) 'Source copy is editable and initially unchanged'
    $before = Get-Document
    Assert-Check ($before.fileName -eq $inputCopy -and $before.layers.Count -eq $before.layerCount) 'Document paging returns all layers from the test copy'
    [IO.File]::WriteAllText((Join-Path $testRoot 'document-before.json'),($before | ConvertTo-Json -Depth 32),[Text.UTF8Encoding]::new($false))
    Expect-Rejection 'save' @{documentId=$before.documentId;ifRevision=([bigint]$before.revision+1).ToString();fileName=(Join-Path $testRoot 'stale-rejected.psd')} 'Stale revision'
    Expect-Rejection 'save' @{documentId=$before.documentId;ifRevision=$before.revision;fileName=$inputCopy} 'Destination already exists'
    $groupId=[guid]::NewGuid().ToString('B');$layerId=[guid]::NewGuid().ToString('B')
    $firstRoot=@($before.layers | Where-Object parentId -eq '')[0]
    $job = Send-Art 'export' @{prompt='Isolated pipe validation: add a red test marker; preserve all existing layers.'}
    $red = Write-Asset $job.directory 'test-red' ([Drawing.Color]::FromArgb(255,255,0,0))
    $bounds=@{left=0;top=0;right=16;bottom=16}
    $operations=@(
        @{op='add_group';layerId=$groupId;name='PIPE_TEST';parentId='';beforeLayerId=$firstRoot.layerId;visible=$true;opacity=255},
        @{op='add_layer';layerId=$layerId;name='test-marker';parentId=$groupId;beforeLayerId='';visible=$true;opacity=255;assetId=$red.assetId;bounds=$bounds}
    )
    Import-Operations $job $red $operations
    $added = Get-Document
    Assert-Check ($added.layerCount -eq $before.layerCount+2) 'Added group and image layer through the pipe exchange'
    Assert-Check (@($added.layers|Where-Object layerId -eq $layerId)[0].pixelSha256 -eq $red.expectedPixels) 'Added image RGBA matches the supplied red PNG'
    $redJob = Send-Art 'export' @{prompt='Read-only verification of the added marker.'}
    Check-Preview (Join-Path $redJob.directory 'preview.png') ([Drawing.Color]::FromArgb(255,255,0,0)) 'Rendered preview contains the red marker'
    $blue = Write-Asset $redJob.directory 'test-blue' ([Drawing.Color]::FromArgb(255,0,128,255))
    Import-Operations $redJob $blue @(@{op='replace_layer';layerId=$layerId;assetId=$blue.assetId;bounds=$bounds})
    $replaced = Get-Document
    Assert-Check (@($replaced.layers|Where-Object layerId -eq $layerId)[0].pixelSha256 -eq $blue.expectedPixels) 'Replaced image RGBA matches the supplied blue PNG'
    foreach($layer in @($before.layers|Where-Object kind -eq 'image')) {
        $current=@($replaced.layers|Where-Object layerId -eq $layer.layerId)
        Assert-Check ($current.Count -eq 1 -and $current[0].pixelSha256 -eq $layer.pixelSha256) ('Original image unchanged: '+$layer.layerId)
    }
    $null = Send-Art 'undo'
    $undone=Get-Document
    Assert-Check (@($undone.layers|Where-Object layerId -eq $layerId)[0].pixelSha256 -eq $red.expectedPixels) 'Undo restores the previous red pixels'
    $null = Send-Art 'redo'
    $redone=Get-Document
    Assert-Check (@($redone.layers|Where-Object layerId -eq $layerId)[0].pixelSha256 -eq $blue.expectedPixels) 'Redo restores the blue pixels'
    $blueJob = Send-Art 'export' @{prompt='Read-only verification of the replaced marker.'}
    $previewPath=Join-Path $blueJob.directory 'preview.png'
    Check-Preview $previewPath ([Drawing.Color]::FromArgb(255,0,128,255)) 'Rendered preview contains the replacement blue marker'
    Assert-Check ([ArtPreviewVerification]::OutsideMarkerUnchanged((Join-Path $job.directory 'preview.png'),$previewPath)) 'Rendered RGBA outside the test marker is unchanged'
    $savedPath=Join-Path $testRoot 'pipe-edited.psd'
    $null=Send-Art 'save' @{documentId=$redone.documentId;ifRevision=$redone.revision;fileName=$savedPath}
    $saved=Get-Document
    Assert-Check (-not $saved.modified -and $saved.fileName -eq $savedPath -and $saved.layerCount -eq $before.layerCount+2) 'PSD saved and reloaded with all layers'
    Assert-Check (@($saved.layers|Where-Object name -eq 'test-marker')[0].pixelSha256 -eq $blue.expectedPixels) 'Saved PSD retains the replacement image pixels'
    $oldImages=@($before.layers|Where-Object kind -eq 'image'|ForEach-Object{$_.name+'|'+$_.pixelSha256})
    $savedImages=@($saved.layers|Where-Object{ $_.kind -eq 'image' -and $_.name -ne 'test-marker'}|ForEach-Object{$_.name+'|'+$_.pixelSha256})
    Assert-Check (($oldImages-join "`n") -ceq ($savedImages-join "`n")) 'Saved PSD retains all original image pixels and relative order'
    Expect-Rejection 'save' @{documentId=$saved.documentId;ifRevision=$saved.revision;fileName=$savedPath} 'Destination already exists'
    Assert-Check ((Get-FileHash -LiteralPath $InputPsd -Algorithm SHA256).Hash -eq $sourceHash) 'Original vocal PSD unchanged'
    Assert-Check ((Get-FileHash -LiteralPath $inputCopy -Algorithm SHA256).Hash -eq $sourceHash) 'Input test copy unchanged'
    [IO.File]::WriteAllText((Join-Path $testRoot 'document-saved.json'),($saved|ConvertTo-Json -Depth 32),[Text.UTF8Encoding]::new($false))
    $result=[ordered]@{passed=$true;configuration=$Configuration;checkCount=$checks.Count;checks=$checks;pid=$application.Id;pipeName=$pipeName;testRoot=$testRoot;sourcePsd=$InputPsd;sourceSha256=$sourceHash;inputCopy=$inputCopy;savedPsd=$savedPath;savedSha256=(Get-FileHash -LiteralPath $savedPath -Algorithm SHA256).Hash;preview=$previewPath;originalLayerCount=$before.layerCount;savedLayerCount=$saved.layerCount;sourceUnchanged=$true}
    [IO.File]::WriteAllText((Join-Path $testRoot 'verification.json'),($result|ConvertTo-Json -Depth 32),[Text.UTF8Encoding]::new($false))
    $result | ConvertTo-Json -Depth 32
} catch {
    $failure=[ordered]@{passed=$false;error=$_.Exception.Message;checks=$checks;testRoot=$testRoot;pid=if($application){$application.Id}else{$null};pipeName=$pipeName}
    [IO.File]::WriteAllText((Join-Path $testRoot 'verification.json'),($failure|ConvertTo-Json -Depth 32),[Text.UTF8Encoding]::new($false))
    throw
} finally {
    if($application -and -not $KeepOpen -and $pipeName) {
        try {
            $final=Send-Art 'status'
            if(-not $final.modified) {
                $application.Refresh()
                if(-not $application.HasExited){
                    if(-not $application.CloseMainWindow()){Stop-Process -Id $application.Id -ErrorAction Stop}
                }
            }
        } catch { Write-Warning 'Test instance retained; no existing user application was closed.' }
    }
}

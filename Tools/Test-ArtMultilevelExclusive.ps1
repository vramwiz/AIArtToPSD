#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][int]$ProcessId)
$ErrorActionPreference='Stop'
$initialRaw=& (Join-Path $PSScriptRoot 'Invoke-ArtRoute.ps1') -ProcessId $ProcessId -InputJson '{"command":"status","args":{}}'
$initialReply=$initialRaw|ConvertFrom-Json
if(-not$initialReply.ok){throw $initialReply.error.message};$initial=$initialReply.data
if($initial.exclusiveSelectionVersion-lt2){throw 'Rebuild and start the updated AIArtToPSD.dpr (exclusiveSelectionVersion=2) first'}
if($initial.busy -or $initial.modified -or $initial.documentId){throw 'Use a dedicated already-running empty app; current documents are preserved'}
$pipeName=$initial.pipeName;$sender=Join-Path $PSScriptRoot 'Send-ArtCommand.ps1'
$root=Join-Path (Split-Path $PSScriptRoot -Parent) ('Tests/output/MultilevelExclusive/'+[guid]::NewGuid().ToString('N'))
if(Test-Path -LiteralPath $root){throw 'Test output already exists'};$null=[IO.Directory]::CreateDirectory($root)
function Send([string]$Command,[hashtable]$Arguments=@{}){
    $raw=& $sender -PipeName $pipeName -Command $Command -Client dot -ArgsJson ($Arguments|ConvertTo-Json -Depth 32 -Compress) -RequestId ('dot:multilevel-'+[guid]::NewGuid().ToString('N')) -TimeoutMs 60000 -NoThrowOnCommandError
    $reply=$raw|ConvertFrom-Json;if(-not$reply.ok){throw ($reply.error.code+': '+$reply.error.message)};$reply.data
}
function Check([bool]$Value,[string]$Text){if(-not$Value){throw $Text}}
function Result-For($Job,$Operations,$Assets=@()){@{schemaVersion=1;requestId=$Job.jobId;jobId=$Job.jobId;documentId=$Job.documentId;ifRevision=$Job.ifRevision;assets=@($Assets);operations=@($Operations)}}
function Document{Send 'document' @{includePixelHashes=$true;limit=64}}
function Flags($Doc){$map=@{};foreach($layer in $Doc.layers){$map[$layer.layerId]=[bool]$layer.visible};$map}
function Select-Part([string]$Id){
    $job=Send 'export' @{prompt='Synthetic nested exclusive selection regression only'}
    $null=Send 'import' @{jobId=$job.jobId;result=(Result-For $job @(@{op='select_part';layerId=$Id}))}
    Document
}
function Stable($Doc,[bool]$IncludeVisibility){
    $byId=@{};foreach($layer in $Doc.layers){$byId[$layer.layerId]=$layer}
    @($Doc.layers|ForEach-Object{
        $layer=$_;$path=[Collections.Generic.List[string]]::new();$path.Add($layer.name);$parent=$layer.parentId
        while($parent){$p=$byId[$parent];$path.Insert(0,$p.name);$parent=$p.parentId}
        $item=[ordered]@{path=$path.ToArray();kind=$layer.kind;index=$layer.index;bounds=$layer.bounds;opacity=$layer.opacity;pixelSha256=$layer.pixelSha256}
        if($IncludeVisibility){$item.visible=$layer.visible};$item
    })|ConvertTo-Json -Depth 32 -Compress
}
function Independent($Doc){
    $f=Flags $Doc
    Check ($f['left'] -and $f['left-b'] -and $f['left-1'] -and -not$f['left-0']) 'Same-name left branch changed'
    Check ($f['right-foot'] -and $f['rf-0'] -and -not$f['rf-1'] -and $f['left-foot'] -and $f['lf-0'] -and -not$f['lf-1']) 'Independent feet changed'
    Check ($f['fixed']) 'Fixed layer hidden'
}
$blank=Send 'new-document' @{width=4;height=4;documentId='';ifRevision='0'}
$job=Send 'export' @{prompt='Synthetic 4x4 nested exclusive selection fixture; no user images'}
Add-Type -AssemblyName System.Drawing
$assets=[Collections.Generic.List[object]]::new()
foreach($name in @('red','blue')){
    $png=Join-Path $root ($name+'.png');$bitmap=[Drawing.Bitmap]::new(2,2)
    try{
        $color=if($name-eq'red'){[Drawing.Color]::Red}else{[Drawing.Color]::Blue}
        for($y=0;$y-lt2;$y++){for($x=0;$x-lt2;$x++){$bitmap.SetPixel($x,$y,$color)}}
        $bitmap.Save($png,[Drawing.Imaging.ImageFormat]::Png)
    }finally{$bitmap.Dispose()}
    $receipt=& (Join-Path $PSScriptRoot 'Send-ArtImage.ps1') -PipeName $pipeName -JobId $job.jobId -InputPng $png -FileName ($name+'.png') -Client dot
    $assets.Add(@{assetId=$name;path=$receipt.path;sha256=$receipt.sha256;width=2;height=2;pixelFormat='RGBA8';colorSpace='sRGB'})
}
$ops=[Collections.Generic.List[object]]::new()
function Add-FixtureGroup([string]$Id,[string]$Name,[string]$Parent,[bool]$Visible){$ops.Add(@{op='add_group';layerId=$Id;name=$Name;parentId=$Parent;beforeLayerId='';visible=$Visible;opacity=255})}
function Image-Layer([string]$Id,[string]$Name,[string]$Parent,[bool]$Visible,[string]$Asset,[int]$X=2,[int]$Y=2){$ops.Add(@{op='add_layer';layerId=$Id;name=$Name;parentId=$Parent;beforeLayerId='';visible=$Visible;opacity=255;assetId=$Asset;bounds=@{left=$X;top=$Y;right=$X+2;bottom=$Y+2}})}
Add-FixtureGroup 'actor' 'actor' '' $false
Add-FixtureGroup 'right' '右手' 'actor' $false
Image-Layer 'idle' '*IDLE' 'right' $true 'red'
Add-FixtureGroup 'a' '*A' 'right' $false
Image-Layer 'a-0' '*0' 'a' $true 'red';Image-Layer 'a-1' '*1' 'a' $false 'blue'
Add-FixtureGroup 'b' '*B' 'right' $false
Add-FixtureGroup 'wrapper' 'wrapper' 'b' $false
Add-FixtureGroup 'near' '*near' 'wrapper' $false;Add-FixtureGroup 'far' '*far' 'wrapper' $true
Image-Layer 'near-0' '*0' 'near' $true 'red';Image-Layer 'near-1' '*1' 'near' $false 'blue'
Image-Layer 'far-0' '*0' 'far' $true 'red';Image-Layer 'far-1' '*1' 'far' $false 'blue'
Add-FixtureGroup 'left' '左手' 'actor' $true;Add-FixtureGroup 'left-b' '*B' 'left' $true
Image-Layer 'left-0' '*0' 'left-b' $false 'red' 0 2;Image-Layer 'left-1' '*1' 'left-b' $true 'blue' 0 2
Add-FixtureGroup 'right-foot' '右足' 'actor' $true;Image-Layer 'rf-0' '*0' 'right-foot' $true 'red' 2 0;Image-Layer 'rf-1' '*1' 'right-foot' $false 'blue' 2 0
Add-FixtureGroup 'left-foot' '左足' 'actor' $true;Image-Layer 'lf-0' '*0' 'left-foot' $true 'red' 0 0;Image-Layer 'lf-1' '*1' 'left-foot' $false 'blue' 0 0
Image-Layer 'fixed' 'BODY' '' $true 'red' 0 0
$null=Send 'import' @{jobId=$job.jobId;result=(Result-For $job $ops.ToArray() $assets.ToArray())}
$before=Document;$metadata=Stable $before $false
$beforePreview=Send 'preview' @{documentId=$before.documentId;ifRevision=$before.revision}
$selected=Select-Part 'near-1';$f=Flags $selected
Check ($f.actor -and $f.right -and $f.b -and $f.wrapper -and $f.near -and $f['near-1']) 'Selected hidden deep branch not visible'
Check (-not$f.idle -and -not$f.a -and -not$f.far -and -not$f['near-0']) 'Other pattern/variant/phase still visible'
Independent $selected;Check ((Stable $selected $false)-ceq$metadata) 'Selection changed original pixels or structure'
$selectedPreview=Send 'preview' @{documentId=$selected.documentId;ifRevision=$selected.revision}
Check ($selectedPreview.pixelSha256-cne$beforePreview.pixelSha256) 'Activating the hidden branch did not change actual rendering'
$idle=Select-Part 'idle';$f=Flags $idle;Check ($f.idle -and -not$f.a -and -not$f.b) 'IDLE switch failed';Independent $idle
$other=Select-Part 'a-1';$f=Flags $other;Check ($f.a -and $f['a-1'] -and -not$f['a-0'] -and -not$f.b -and -not$f.idle) 'Cross-pattern child switch failed';Independent $other
$selected=Select-Part 'near-1';Independent $selected;Check ((Stable $selected $false)-ceq$metadata) 'Repeated switching changed pixels/structure'
$stable=Stable $selected $true;$preview=Send 'preview' @{documentId=$selected.documentId;ifRevision=$selected.revision}
$saved=Send 'save' @{documentId=$selected.documentId;ifRevision=$selected.revision;fileName=(Join-Path $root 'synthetic-selected.psd')}
Check ($saved.documentId-cne$selected.documentId) 'Save did not establish a new loaded baseline'
$null=Send 'open' @{fileName=$saved.fileName;documentId=$saved.documentId;ifRevision=$saved.revision;limit=1}
$reloaded=Document;Check (-not$reloaded.modified -and (Stable $reloaded $true)-ceq$stable) 'Save/reload changed layer state or pixels'
$afterPreview=Send 'preview' @{documentId=$reloaded.documentId;ifRevision=$reloaded.revision};Check ($afterPreview.pixelSha256-ceq$preview.pixelSha256) 'Save/reload changed composition'
$result=[ordered]@{passed=$true;processId=$ProcessId;exclusiveSelectionVersion=$initial.exclusiveSelectionVersion;output=$root;syntheticPsd=$saved.fileName;layerCount=$reloaded.layerCount;hiddenAncestorsSelected=$true;nestedSiblingExclusion=$true;idleAndCrossPatternSwitch=$true;independentPartsAndFixedPreserved=$true;pixelsAndStructurePreserved=$true;saveReloadExact=$true;modified=$reloaded.modified}
[IO.File]::WriteAllText((Join-Path $root 'summary.json'),($result|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false));$result|ConvertTo-Json -Depth 8

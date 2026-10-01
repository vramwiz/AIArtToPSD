unit ArtExchange;

interface
uses System.SysUtils, System.Generics.Collections, System.JSON, ArtDocument;
type
  TArtExchangeJob = class
  public
    Id, Directory, DocumentId, AppliedHash: string;
    Revision: UInt64;
    State,MessageText,PromptText: string;
    Progress: Integer;
    WorkspaceSize: Integer;
    WorkspaceBounds: TArtBounds;
    WorkspaceLayerId: string;
  end;
  TArtExchange = class
  private
    FJobs: TObjectDictionary<string,TArtExchangeJob>;
    FPipeName: string;
  public
    constructor Create;
    destructor Destroy; override;
    property PipeName: string read FPipeName write FPipeName;
    procedure ClearJobs;
    function LoadRecovery(const Directory: string; out Job: TArtExchangeJob): TArtDocument;
    procedure RegisterRecovered(Job: TArtExchangeJob);
    procedure WriteJobConnection(Job: TArtExchangeJob);
    procedure CancelJob(const Id: string);
    function FindJob(const Id: string): TArtExchangeJob;
    procedure NotifyJob(Document: TArtDocument; const Id,State,MessageText: string; Progress: Integer);
    function ExportJob(Document: TArtDocument; const Prompt,Root: string; Workspace: TJSONObject = nil): string;
    function PrepareResult(Document: TArtDocument; const FileName: string;
      out Job: TArtExchangeJob; out Digest: string): TArtDocument;
    procedure CommitResult(Job: TArtExchangeJob; const Digest: string);
  end;

implementation
uses System.Classes, System.IOUtils, System.Hash, Winapi.Windows,
  ArtPng, ArtPsd, ArtParts, ArtLayerName, ArtRasterTransform;
const MAX_JSON = 1048576; MAX_ASSETS = 128; MAX_OPERATIONS = 256;
  MAX_ASSET_BYTES = 134217728;

function NewId: string;
var G: TGUID;
begin CreateGUID(G); Result := GUIDToString(G); end;
function Obj(Value: TJSONValue): TJSONObject;
begin
  if not (Value is TJSONObject) then raise EArtFormat.Create('JSON object expected');
  Result := TJSONObject(Value);
end;
function Field(O: TJSONObject; const Name: string): TJSONValue;
begin
  Result := O.GetValue(Name);
  if Result=nil then raise EArtFormat.Create('Missing JSON field: '+Name);
end;
function Str(O: TJSONObject; const Name: string): string;
var V: TJSONValue;
begin
  V := Field(O,Name);
  if not (V is TJSONString) then raise EArtFormat.Create('JSON string expected: '+Name);
  Result := V.Value;
end;
function Num(O: TJSONObject; const Name: string; LowValue,HighValue: Integer): Integer;
var V: TJSONValue;
begin
  V := Field(O,Name);
  if not (V is TJSONNumber) or not TryStrToInt(V.Value,Result) or
    (Result<LowValue) or (Result>HighValue) then raise EArtFormat.Create('Invalid integer: '+Name);
end;
function Bool(O: TJSONObject; const Name: string): Boolean;
var V: TJSONValue;
begin
  V := Field(O,Name);
  if not (V is TJSONBool) then raise EArtFormat.Create('JSON boolean expected: '+Name);
  Result := TJSONBool(V).AsBoolean;
end;
function Arr(O: TJSONObject; const Name: string): TJSONArray;
var V: TJSONValue;
begin
  V := Field(O,Name);
  if not (V is TJSONArray) then raise EArtFormat.Create('JSON array expected: '+Name);
  Result := TJSONArray(V);
end;
procedure AddNum(O: TJSONObject; const Name: string; Value: Integer);
begin O.AddPair(Name,TJSONNumber.Create(Value)); end;
procedure AddBool(O: TJSONObject; const Name: string; Value: Boolean);
begin O.AddPair(Name,TJSONBool.Create(Value)); end;
function BoundsJson(const Bounds: TArtBounds): TJSONObject;
begin
  Result := TJSONObject.Create;
  AddNum(Result,'left',Bounds.Left); AddNum(Result,'top',Bounds.Top);
  AddNum(Result,'right',Bounds.Right); AddNum(Result,'bottom',Bounds.Bottom);
end;
function ReadBounds(O: TJSONObject): TArtBounds;
begin
  Result := TArtBounds.Create(Num(O,'left',-30000,30000),Num(O,'top',-30000,30000),
    Num(O,'right',-30000,60000),Num(O,'bottom',-30000,60000));
  PixelByteCount(Result.Width,Result.Height,4);
end;
procedure ReadWorkspace(Document: TArtDocument; O: TJSONObject; Job: TArtExchangeJob);
var Layer: TArtLayer;
begin
  Job.WorkspaceSize := Num(O,'size',1,4096);
  Job.WorkspaceBounds := ReadBounds(Obj(Field(O,'bounds')));
  if (Job.WorkspaceBounds.Width<1) or (Job.WorkspaceBounds.Width<>Job.WorkspaceBounds.Height) or
    (Job.WorkspaceBounds.Left<0) or (Job.WorkspaceBounds.Top<0) or
    (Job.WorkspaceBounds.Right>Document.Width) or (Job.WorkspaceBounds.Bottom>Document.Height) then
    raise EArtFormat.Create('Workspace must be a square inside the document');
  PixelByteCount(Job.WorkspaceSize,Job.WorkspaceSize,4);
  Job.WorkspaceLayerId := Str(O,'sourceLayerId');
  if Job.WorkspaceLayerId<>'' then begin
    Layer := Document.FindLayer(Job.WorkspaceLayerId);
    if (Layer=nil) or (Layer.Kind<>alkImage) then raise EArtFormat.Create('Workspace source layer not found');
    if Layer.HasMask or (Layer.Clipping<>0) then raise EArtFormat.Create('Masked workspace source is not supported');
  end;
end;
procedure RejectLinks(const Path: string);
var Current,Parent: string; Attributes: Cardinal;
begin
  Current := TPath.GetFullPath(Path);
  repeat
    Attributes := GetFileAttributes(PChar(Current));
    if (Attributes<>INVALID_FILE_ATTRIBUTES) and ((Attributes and FILE_ATTRIBUTE_REPARSE_POINT)<>0) then
      raise EArtFormat.Create('Links and junctions are not allowed in AI exchange paths');
    Parent := ExtractFileDir(Current);
    if (Parent='') or SameText(Parent,Current) then Break;
    Current := Parent;
  until False;
end;
function AssetPath(const Directory,Relative: string): string;
var Base: string;
begin
  if (Relative='') or TPath.IsPathRooted(Relative) or (Pos(':',Relative)>0) then raise EArtFormat.Create('Relative asset path required');
  Base := IncludeTrailingPathDelimiter(TPath.GetFullPath(Directory));
  Result := TPath.GetFullPath(TPath.Combine(Base,Relative));
  if not SameText(Copy(Result,1,Length(Base)),Base) then raise EArtFormat.Create('Asset path escapes job directory');
  if not SameText(TPath.GetExtension(Result),'.png') then raise EArtFormat.Create('PNG asset required');
  RejectLinks(Result);
end;
function FileHash(const FileName: string): string;
var Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
  try Result := LowerCase(THashSHA2.GetHashString(Stream)); finally Stream.Free; end;
end;
procedure CheckUniqueKeys(Value: TJSONValue; Depth: Integer);
var O: TJSONObject; A: TJSONArray; Keys: TDictionary<string,Boolean>; Pair: TJSONPair;
begin
  if Depth>64 then raise EArtFormat.Create('JSON nesting limit exceeded');
  if Value is TJSONObject then begin
    O := TJSONObject(Value); Keys := TDictionary<string,Boolean>.Create;
    try
      for Pair in O do begin
        if Keys.ContainsKey(Pair.JsonString.Value) then raise EArtFormat.Create('Duplicate JSON field');
        Keys.Add(Pair.JsonString.Value,True); CheckUniqueKeys(Pair.JsonValue,Depth+1);
      end;
    finally Keys.Free; end;
  end else if Value is TJSONArray then begin
    A := TJSONArray(Value); for var V in A do CheckUniqueKeys(V,Depth+1);
  end;
end;

function ReadExchangeJson(const FileName: string): TJSONValue;
var S: TFileStream; B: TBytes;
begin
  RejectLinks(FileName); S := TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
  try
    if (S.Size<2) or (S.Size>MAX_JSON) then raise EArtFormat.Create('Recovery JSON size limit');
    SetLength(B,Integer(S.Size)); S.ReadBuffer(B[0],Length(B));
    Result := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(B));
    try CheckUniqueKeys(Result,0); Obj(Result); except Result.Free; raise; end;
  finally S.Free; end;
end;
procedure TArtExchange.WriteJobConnection(Job: TArtExchangeJob);
var Info: TJSONObject; Path: string;
begin
  if FPipeName='' then Exit;
  Info := TJSONObject.Create;
  try
    AddNum(Info,'schemaVersion',1); Info.AddPair('pipeName',FPipeName); Info.AddPair('jobId',Job.Id);
    Path := TPath.Combine(Job.Directory,'connection.json');
    TFile.WriteAllText(Path+'.tmp',Info.ToJSON,TEncoding.UTF8);
    if not MoveFileEx(PChar(Path+'.tmp'),PChar(Path),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
  finally Info.Free; end;
end;
procedure TArtExchange.RegisterRecovered(Job: TArtExchangeJob);
begin FJobs.Add(Job.Id,Job); end;
procedure TArtExchange.CancelJob(const Id: string);
var Job: TArtExchangeJob;
begin
  Job := FindJob(Id);
  if Job.State='completed' then raise EArtFormat.Create('Result already applied; use Undo');
  // Persist cancellation before accepting it so restart cannot revive the result.
  TFile.WriteAllText(TPath.Combine(Job.Directory,'cancelled.tmp'),Job.Id,TEncoding.UTF8);
  if not FileExists(TPath.Combine(Job.Directory,'cancelled')) then
    TFile.Move(TPath.Combine(Job.Directory,'cancelled.tmp'),TPath.Combine(Job.Directory,'cancelled'));
  Job.State := 'cancelled'; Job.MessageText := '以後の結果取込を停止';
end;
function TArtExchange.LoadRecovery(const Directory: string; out Job: TArtExchangeJob): TArtDocument;
var RecoveryValue,RequestValue: TJSONValue; Recovery,Request,Meta: TJSONObject;
    Layers: TJSONArray; Index: Integer; Path,Base: string; Version: UInt64; Lock: TFileStream;
    Ids: TDictionary<string,Boolean>;
  procedure RestoreIds(List: TList<TArtLayer>; const Parent: string; Depth: Integer);
  var Id: string;
  begin
    if Depth>128 then raise EArtFormat.Create('Recovery layer depth');
    for var L in List do begin
      if Index>=Layers.Count then raise EArtFormat.Create('Recovery layer count');
      Meta := Obj(Layers[Index]); Inc(Index); Id := Str(Meta,'layerId');
      if (Id='') or Ids.ContainsKey(Id) then raise EArtFormat.Create('Recovery duplicate layer ID');
      Ids.Add(Id,True);
      if (Str(Meta,'parentId')<>Parent) or (Str(Meta,'name')<>L.Name) or
        (Bool(Meta,'visible')<>L.Visible) or (Num(Meta,'opacity',0,255)<>L.Opacity) then
        raise EArtFormat.Create('Recovery layer metadata mismatch');
      if ((L.Kind=alkGroup) and (Str(Meta,'kind')<>'group')) or
        ((L.Kind=alkImage) and (Str(Meta,'kind')<>'image')) then raise EArtFormat.Create('Recovery layer kind');
      if L.Kind=alkImage then begin
        var Bounds := ReadBounds(Obj(Field(Meta,'bounds')));
        if (Bounds.Left<>L.Bounds.Left) or (Bounds.Top<>L.Bounds.Top) or
          (Bounds.Right<>L.Bounds.Right) or (Bounds.Bottom<>L.Bounds.Bottom) then raise EArtFormat.Create('Recovery bounds');
      end;
      L.Id := Id; RestoreIds(L.Children,Id,Depth+1);
    end;
  end;
begin
  Result := nil; Job := nil; RecoveryValue := nil; RequestValue := nil;
  Base := TPath.GetFullPath(Directory); RejectLinks(Base); Ids := TDictionary<string,Boolean>.Create;
  try
    try
    RecoveryValue := ReadExchangeJson(TPath.Combine(Base,'recovery.json')); Recovery := Obj(RecoveryValue);
    if Num(Recovery,'schemaVersion',1,1)<>1 then raise EArtFormat.Create('Recovery schema');
    Path := TPath.Combine(Base,'request.json');
    if FileHash(Path)<>Str(Recovery,'requestSha256') then raise EArtFormat.Create('Recovery request hash mismatch');
    RequestValue := ReadExchangeJson(Path); Request := Obj(RequestValue);
    if Num(Request,'schemaVersion',1,1)<>1 then raise EArtFormat.Create('Request schema');
    if Str(Request,'requestId')<>Str(Request,'jobId') then raise EArtFormat.Create('Recovery request ID');
    Path := TPath.Combine(Base,'snapshot.psd'); RejectLinks(Path);
    Lock := TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if Lock.Size>ART_MAX_BYTES then raise EArtFormat.Create('Recovery PSD size limit');
      if LowerCase(THashSHA2.GetHashString(Lock))<>Str(Recovery,'snapshotSha256') then raise EArtFormat.Create('Recovery snapshot hash mismatch');
      Result := ReadPsd(Path);
    finally Lock.Free; end;
    Meta := Obj(Field(Request,'canvas'));
    if (Result.Width<>Num(Meta,'width',1,30000)) or (Result.Height<>Num(Meta,'height',1,30000)) then raise EArtFormat.Create('Recovery canvas');
    Layers := Arr(Request,'layers'); Index := 0; RestoreIds(Result.Roots,'',0);
    if Index<>Layers.Count then raise EArtFormat.Create('Recovery layer count');
    if not TryStrToUInt64(Str(Request,'ifRevision'),Version) or (Version=High(UInt64)) then raise EArtFormat.Create('Recovery revision');
    Result.SessionId := Str(Request,'documentId'); if Result.SessionId='' then raise EArtFormat.Create('Recovery document ID');
    Result.Revision := Version; RenderPsdLayers(Result);
    Job := TArtExchangeJob.Create; Job.Id := Str(Request,'jobId'); Job.Directory := Base;
    if Request.GetValue('workspace')<>nil then ReadWorkspace(Result,Obj(Field(Request,'workspace')),Job);
    if Job.Id<>ExtractFileName(Base) then raise EArtFormat.Create('Recovery directory ID mismatch');
    Job.PromptText := Str(Request,'prompt'); Job.DocumentId := Result.SessionId; Job.Revision := Result.Revision; Job.State := 'queued';
    if FileExists(TPath.Combine(Base,'result.json')) then Job.State := 'ready';
    if FileExists(TPath.Combine(Base,'cancelled')) then Job.State := 'cancelled';
    except Result.Free; Job.Free; Job := nil; raise; end;
  finally Ids.Free; RecoveryValue.Free; RequestValue.Free; end;
end;
constructor TArtExchange.Create;
begin inherited; FJobs := TObjectDictionary<string,TArtExchangeJob>.Create([doOwnsValues]); end;
destructor TArtExchange.Destroy;
begin FJobs.Free; inherited; end;

procedure TArtExchange.ClearJobs;
begin FJobs.Clear; end;

function TArtExchange.FindJob(const Id: string): TArtExchangeJob;
begin
  if not FJobs.TryGetValue(Id,Result) then raise EArtFormat.Create('Unknown or expired jobId');
end;
procedure TArtExchange.NotifyJob(Document: TArtDocument; const Id,State,MessageText: string; Progress: Integer);
var Job: TArtExchangeJob;
begin
  Job := FindJob(Id);
  if (Document=nil) or (Document.SessionId<>Job.DocumentId) or (Document.Revision<>Job.Revision) then
    raise EArtFormat.Create('Job document has changed');
  if (Job.State='completed') or (Job.State='cancelled') then raise EArtFormat.Create('Job already finished');
  if (State<>'running') and (State<>'ready') and (State<>'failed') and (State<>'cancelled') then
    raise EArtFormat.Create('Invalid job state');
  if (Progress<0) or (Progress>100) or (Length(MessageText)>1000) then raise EArtFormat.Create('Invalid job progress');
  if State='cancelled' then begin CancelJob(Id); Exit; end;
  Job.State := State; Job.Progress := Progress; Job.MessageText := MessageText;
end;
function TArtExchange.ExportJob(Document: TArtDocument; const Prompt,Root: string; Workspace: TJSONObject): string;
var Job: TArtExchangeJob; Request,Canvas,LayerJson,Asset,Recovery: TJSONObject;
    Layers,Assets,Supported: TJSONArray; ImageDirectory,ImagePath,SelectedId: string;
    Pixels: TBytes; Counter: Integer; Ready: Boolean;
    WorkspacePixels: TBytes; WorkspaceLayer: TArtLayer; SourceRect: TArtBounds;
  procedure ExportLayers(List: TList<TArtLayer>; const ParentId: string; Depth: Integer);
  var L: TArtLayer; Parts: TArtLayerNameParts;
  begin
    if Depth>128 then raise EArtFormat.Create('Layer depth limit');
    for L in List do begin
      LayerJson := TJSONObject.Create; Layers.AddElement(LayerJson);
      LayerJson.AddPair('layerId',L.Id); LayerJson.AddPair('parentId',ParentId);
      LayerJson.AddPair('name',L.Name); Parts := ParseLayerName(L.Name);
      LayerJson.AddPair('displayName',Parts.DisplayName); LayerJson.AddPair('prefix',Parts.Prefix); LayerJson.AddPair('flip',Parts.Suffix);
      AddBool(LayerJson,'visible',L.Visible); AddNum(LayerJson,'opacity',L.Opacity);
      LayerJson.AddPair('bounds',BoundsJson(L.Bounds)); AddBool(LayerJson,'hasMask',L.HasMask);
      if L.Kind=alkGroup then LayerJson.AddPair('kind','group')
      else begin
        LayerJson.AddPair('kind','image'); Inc(Counter);
        SelectedId := 'source-'+IntToStr(Counter); ImagePath := TPath.Combine(ImageDirectory,SelectedId+'.png');
        // Empty layers have no PNG; they remain in the metadata.
        if (L.Bounds.Width>0) and (L.Bounds.Height>0) then begin
          WriteRgbaPng(ImagePath,L.Bounds.Width,L.Bounds.Height,L.Pixels);
          Asset := TJSONObject.Create; Assets.AddElement(Asset); Asset.AddPair('assetId',SelectedId);
          Asset.AddPair('path','input/'+SelectedId+'.png'); Asset.AddPair('sha256',FileHash(ImagePath));
          AddNum(Asset,'width',L.Bounds.Width); AddNum(Asset,'height',L.Bounds.Height);
          Asset.AddPair('pixelFormat','RGBA8'); Asset.AddPair('colorSpace','sRGB'); LayerJson.AddPair('assetId',SelectedId);
        end;
      end;
      ExportLayers(L.Children,L.Id,Depth+1);
    end;
  end;
begin
  if Document=nil then raise EArtFormat.Create('文書を開いてください。');
  if Trim(Prompt)='' then raise EArtFormat.Create('AIへの指示を入力してください。');
  if Length(Prompt)>16000 then raise EArtFormat.Create('AI指示が長すぎます。');
  Pixels := RenderPsdLayers(Document);
  Job := TArtExchangeJob.Create; Request := TJSONObject.Create; Ready := False;
  try
    if Workspace<>nil then ReadWorkspace(Document,Workspace,Job);
    Job.State := 'queued'; Job.Progress := 0; Job.PromptText := Prompt;
    Job.Id := NewId; Job.DocumentId := Document.SessionId; Job.Revision := Document.Revision;
    Job.Directory := TPath.GetFullPath(TPath.Combine(Root,Job.Id)); RejectLinks(Job.Directory);
    ForceDirectories(Job.Directory); ImageDirectory := TPath.Combine(Job.Directory,'input'); ForceDirectories(ImageDirectory);
    ForceDirectories(TPath.Combine(Job.Directory,'images'));
    if FPipeName<>'' then Request.AddPair('pipeName',FPipeName);
    AddNum(Request,'schemaVersion',1); Request.AddPair('jobId',Job.Id); Request.AddPair('requestId',Job.Id);
    Request.AddPair('documentId',Job.DocumentId); Request.AddPair('ifRevision',UIntToStr(Job.Revision)); Request.AddPair('prompt',Prompt);
    Canvas := TJSONObject.Create; Request.AddPair('canvas',Canvas); AddNum(Canvas,'width',Document.Width); AddNum(Canvas,'height',Document.Height);
    Request.AddPair('layerOrder','topmost-first'); Request.AddPair('preview','preview.png');
    Supported := TJSONArray.Create; Request.AddPair('supportedOperations',Supported);
    for var Operation in ['add_group','add_layer','replace_layer','rename_layer','set_attributes','select_part'] do Supported.Add(Operation);
    Layers := TJSONArray.Create; Request.AddPair('layers',Layers); Assets := TJSONArray.Create; Request.AddPair('assets',Assets);
    Counter := 0; ExportLayers(Document.Roots,'',0);
    if Workspace<>nil then begin
      SourceRect := Job.WorkspaceBounds;
      if Job.WorkspaceLayerId='' then
        WorkspacePixels := ResampleRgba(Pixels,Document.Width,Document.Height,SourceRect,Job.WorkspaceSize,Job.WorkspaceSize)
      else begin
        WorkspaceLayer := Document.FindLayer(Job.WorkspaceLayerId);
        Dec(SourceRect.Left,WorkspaceLayer.Bounds.Left); Dec(SourceRect.Right,WorkspaceLayer.Bounds.Left);
        Dec(SourceRect.Top,WorkspaceLayer.Bounds.Top); Dec(SourceRect.Bottom,WorkspaceLayer.Bounds.Top);
        WorkspacePixels := ResampleRgba(WorkspaceLayer.Pixels,WorkspaceLayer.Bounds.Width,WorkspaceLayer.Bounds.Height,
          SourceRect,Job.WorkspaceSize,Job.WorkspaceSize);
      end;
      ImagePath := TPath.Combine(ImageDirectory,'workspace-source.png');
      WriteRgbaPng(ImagePath,Job.WorkspaceSize,Job.WorkspaceSize,WorkspacePixels);
      Canvas := TJSONObject.Create; Request.AddPair('workspace',Canvas);
      Canvas.AddPair('sourceLayerId',Job.WorkspaceLayerId); Canvas.AddPair('assetId','workspace-source');
      AddNum(Canvas,'size',Job.WorkspaceSize); Canvas.AddPair('bounds',BoundsJson(Job.WorkspaceBounds));
      Canvas.AddPair('mapping','canvas = bounds.origin + workspace * bounds.width / size');
      Asset := TJSONObject.Create; Assets.AddElement(Asset); Asset.AddPair('assetId','workspace-source');
      Asset.AddPair('path','input/workspace-source.png'); Asset.AddPair('sha256',FileHash(ImagePath));
      AddNum(Asset,'width',Job.WorkspaceSize); AddNum(Asset,'height',Job.WorkspaceSize);
      Asset.AddPair('pixelFormat','RGBA8'); Asset.AddPair('colorSpace','sRGB');
    end;
    WriteRgbaPng(TPath.Combine(Job.Directory,'preview.png'),Document.Width,Document.Height,Pixels);
    if Length(TEncoding.UTF8.GetBytes(Request.ToJSON))>MAX_JSON then raise EArtFormat.Create('Request metadata exceeds recovery limit');
    TFile.WriteAllText(TPath.Combine(Job.Directory,'request.json.tmp'),Request.ToJSON,TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(Job.Directory,'instructions.txt'),
      'Read request.json and preview.png. Write generated 8-bit RGBA PNGs into images/. '+
      'Use stable layer IDs; preserve framing. Write schemaVersion=1, requestId, jobId, documentId and ifRevision exactly as issued. '+
      'result.json must contain assets and operations arrays. Each asset needs assetId, relative path, SHA-256, width, height, pixelFormat=RGBA8, colorSpace=sRGB. '+
      'Supported operations: add_group (layerId,name,parentId,beforeLayerId,visible,opacity); add_layer (same + assetId,bounds); '+
      'replace_layer (layerId,assetId,bounds); rename_layer (layerId,name); set_attributes (layerId,visible,opacity); select_part (layerId). '+
      'add_layer/replace_layer optionally accept resample=true, sourceBounds (rectangle in the original asset), trimTransparent=true. '+
      'Always supply the unchanged original generated asset when readjusting; never repeatedly resize a previously reduced PNG. '+
      'If request.workspace exists, edit its workspace-source PNG at the issued square size. '+
      'Set coordinateSpace=workspace on image operations; their bounds use that square, and the app maps them back to the canvas. '+
      'Keep paired eyes in one layer. Do not recenter any generated part or change the shared square framing. '+
      'Use empty parentId/beforeLayerId for root/append. Finish all PNGs first, write result.json.tmp then rename to result.json. '+
      'Read connection.json for the current pipeName (read it again after reconnect/restart). If pipeName is present, send message-mode UTF-8 JSON commands: schemaVersion=1, requestId, command, args. '+
      'Commands: status (args {} or jobId); progress (jobId,state=running/ready/failed,progress=0..100,message); import (jobId); cancel (jobId). '+
      'Poll status before publishing/importing: cancelled or an expired job must not be applied. '+
      'This is file exchange; no cloud API is invoked by the application.',TEncoding.UTF8);
    // Save the complete pre-AI document for explicit restart recovery.
    ImagePath := TPath.Combine(Job.Directory,'snapshot.psd');
    if Length(Document.SourceBytes)=0 then WriteNewPsd(Document,ImagePath,pcRle)
    else begin
      try SaveLayerPropertiesPsd(Document,ImagePath);
      except on E: EArtFormat do SaveImageCompositionPsd(Document,ImagePath); end;
    end;
    Recovery := TJSONObject.Create;
    try
      AddNum(Recovery,'schemaVersion',1); Recovery.AddPair('snapshotSha256',FileHash(ImagePath));
      Recovery.AddPair('requestSha256',FileHash(TPath.Combine(Job.Directory,'request.json.tmp')));
      TFile.WriteAllText(TPath.Combine(Job.Directory,'recovery.json.tmp'),Recovery.ToJSON,TEncoding.UTF8);
      TFile.Move(TPath.Combine(Job.Directory,'recovery.json.tmp'),TPath.Combine(Job.Directory,'recovery.json'));
    finally Recovery.Free; end;
    WriteJobConnection(Job);
    // request.json is the ready marker: publish only after every input is complete.
    TFile.Move(TPath.Combine(Job.Directory,'request.json.tmp'),TPath.Combine(Job.Directory,'request.json'));
    Result := Job.Directory; FJobs.Add(Job.Id,Job); Ready := True;
  finally
    Request.Free; if not Ready then Job.Free;
  end;
end;

function TArtExchange.PrepareResult(Document: TArtDocument; const FileName: string;
  out Job: TArtExchangeJob; out Digest: string): TArtDocument;
var Stream: TFileStream; Bytes: TBytes; Value: TJSONValue; Manifest,A,O,B: TJSONObject;
    Assets,Operations: TJSONArray; Data: TDictionary<string,TArtPngData>;
    Image: TArtPngData; AssetId,Path,Op,Id,ParentId,BeforeId,Name: string;
    L,Parent,Before: TArtLayer; List: TList<TArtLayer>; Bounds: TArtBounds;
    Total: Int64; Current: TArtDocument; Version: UInt64; Applied: Boolean;
  function Target(const Id: string): TArtLayer;
  begin
    Result := Current.FindLayer(Id); if Result=nil then raise EArtFormat.Create('Unknown layerId: '+Id);
  end;
  function ImageFor(const Id: string): TArtPngData;
  begin if not Data.TryGetValue(Id,Result) then raise EArtFormat.Create('Unknown assetId: '+Id); end;
  procedure SetImage(Layer: TArtLayer; const Img: TArtPngData; const R: TArtBounds);
  var DX,DY: Integer; SourceRect,DestRect,TrimRect: TArtBounds;
      Resize,Trim,IsWorkspace: Boolean; NewPixels: TBytes;
  begin
    if Layer.Kind<>alkImage then raise EArtFormat.Create('Image layer required');
    SourceRect := TArtBounds.Create(0,0,Img.Width,Img.Height);
    if O.GetValue('sourceBounds')<>nil then SourceRect := ReadBounds(Obj(Field(O,'sourceBounds')));
    if (SourceRect.Width<1) or (SourceRect.Height<1) or (SourceRect.Left<0) or (SourceRect.Top<0) or
      (SourceRect.Right>Img.Width) or (SourceRect.Bottom>Img.Height) then raise EArtFormat.Create('Source bounds outside PNG');
    Resize := False; Trim := False; IsWorkspace := False;
    if O.GetValue('resample')<>nil then Resize := Bool(O,'resample');
    if O.GetValue('trimTransparent')<>nil then Trim := Bool(O,'trimTransparent');
    if O.GetValue('coordinateSpace')<>nil then begin
      if Str(O,'coordinateSpace')='workspace' then IsWorkspace := True
      else if Str(O,'coordinateSpace')<>'canvas' then raise EArtFormat.Create('Unknown coordinate space');
    end;
    if not Resize and ((R.Width<>SourceRect.Width) or (R.Height<>SourceRect.Height)) then
      raise EArtFormat.Create('Image bounds do not match PNG; resample=true required');
    DestRect := R;
    if IsWorkspace then begin
      if Job.WorkspaceSize=0 then raise EArtFormat.Create('No square workspace was issued');
      DestRect := MapSquareBounds(R,Job.WorkspaceBounds,Job.WorkspaceSize); Resize := True;
    end;
    if (DestRect.Width<1) or (DestRect.Height<1) then raise EArtFormat.Create('Empty destination bounds');
    if Layer.HasMask and (Resize or Trim or (O.GetValue('sourceBounds')<>nil)) then
      raise EArtFormat.Create('Resize/crop of masked layers is not supported');
    Inc(Total,PixelByteCount(DestRect.Width,DestRect.Height,4));
    if Total>MAX_ASSET_BYTES then raise EArtFormat.Create('AI transformed image memory limit');
    if Resize or (O.GetValue('sourceBounds')<>nil) then
      NewPixels := ResampleRgba(Img.Pixels,Img.Width,Img.Height,SourceRect,DestRect.Width,DestRect.Height)
    else NewPixels := Img.Pixels;
    if Trim then begin
      TrimRect := AlphaBounds(NewPixels,DestRect.Width,DestRect.Height);
      if TrimRect.Width=0 then raise EArtFormat.Create('Cannot trim an empty image');
      NewPixels := ResampleRgba(NewPixels,DestRect.Width,DestRect.Height,TrimRect,TrimRect.Width,TrimRect.Height);
      DestRect := TArtBounds.Create(DestRect.Left+TrimRect.Left,DestRect.Top+TrimRect.Top,
        DestRect.Left+TrimRect.Right,DestRect.Top+TrimRect.Bottom);
    end;
    DX := DestRect.Left-Layer.Bounds.Left; DY := DestRect.Top-Layer.Bounds.Top;
    if Layer.HasMask then begin
      Inc(Layer.MaskBounds.Left,DX); Inc(Layer.MaskBounds.Right,DX); Inc(Layer.MaskBounds.Top,DY); Inc(Layer.MaskBounds.Bottom,DY);
    end;
    Layer.Pixels := NewPixels; Layer.Bounds := DestRect;
  end;
begin
  Job := nil; Digest := ''; Current := nil; Value := nil;
  if Document=nil then raise EArtFormat.Create('文書を開いてください。');
  RejectLinks(FileName);
  Stream := TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size<2) or (Stream.Size>MAX_JSON) then raise EArtFormat.Create('Result JSON size limit');
    Digest := LowerCase(THashSHA2.GetHashString(Stream)); Stream.Position := 0;
    SetLength(Bytes,Integer(Stream.Size)); Stream.ReadBuffer(Bytes[0],Length(Bytes));
  finally Stream.Free; end;
  Data := TDictionary<string,TArtPngData>.Create;
  try
    Value := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(Bytes)); CheckUniqueKeys(Value,0); Manifest := Obj(Value);
    if Num(Manifest,'schemaVersion',1,1)<>1 then raise EArtFormat.Create('Unsupported schema version');
    if not FJobs.TryGetValue(Str(Manifest,'jobId'),Job) then raise EArtFormat.Create('Unknown or expired jobId');
    if not SameText(TPath.GetFullPath(FileName),TPath.Combine(Job.Directory,'result.json')) then raise EArtFormat.Create('Result must be the issued job result.json');
    if (Str(Manifest,'requestId')<>Job.Id) or (Str(Manifest,'documentId')<>Job.DocumentId) or (Document.SessionId<>Job.DocumentId) then
      raise EArtFormat.Create('Document or request does not match this job');
    if not TryStrToUInt64(Str(Manifest,'ifRevision'),Version) or (Version<>Job.Revision) then raise EArtFormat.Create('Invalid job revision');
    Applied := Job.AppliedHash<>'';
    if Applied then begin
      if Job.AppliedHash<>Digest then raise EArtFormat.Create('Same requestId with different result content');
      Exit(nil); // Successful repeat is a read-only acknowledgement, never a second mutation.
    end;
    if Job.State='cancelled' then raise EArtFormat.Create('Job was cancelled');
    if Document.Revision<>Job.Revision then raise EArtFormat.Create('文書が変更されています。新しいAIジョブを書き出してください。');
    Assets := Arr(Manifest,'assets'); Operations := Arr(Manifest,'operations');
    if (Assets.Count>MAX_ASSETS) or (Operations.Count<1) or (Operations.Count>MAX_OPERATIONS) then raise EArtFormat.Create('AI batch item limit');
    Total := 0;
    for var Item in Assets do begin
      A := Obj(Item); AssetId := Str(A,'assetId'); if (AssetId='') or Data.ContainsKey(AssetId) then raise EArtFormat.Create('Duplicate or empty assetId');
      if (Str(A,'pixelFormat')<>'RGBA8') or (Str(A,'colorSpace')<>'sRGB') then raise EArtFormat.Create('Unsupported asset format');
      Inc(Total,PixelByteCount(Num(A,'width',1,30000),Num(A,'height',1,30000),4));
      if Total>MAX_ASSET_BYTES then raise EArtFormat.Create('AI image memory limit');
      Path := AssetPath(Job.Directory,Str(A,'path'));
      Stream := TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
      try
        if Stream.Size>MAX_ASSET_BYTES then raise EArtFormat.Create('AI PNG file limit');
        if LowerCase(THashSHA2.GetHashString(Stream))<>LowerCase(Str(A,'sha256')) then raise EArtFormat.Create('PNG hash mismatch');
        Image := ReadPng(Path);
      finally Stream.Free; end;
      if (Image.Width<>Num(A,'width',1,30000)) or (Image.Height<>Num(A,'height',1,30000)) then raise EArtFormat.Create('PNG dimensions mismatch');
      Data.Add(AssetId,Image);
    end;
    Current := Document.Clone;
    for var Item in Operations do begin
      O := Obj(Item); Op := Str(O,'op'); Id := Str(O,'layerId');
      if (Id='') or (Length(Id)>128) then raise EArtFormat.Create('Invalid layerId');
      if (Op='add_group') or (Op='add_layer') then begin
        if Current.FindLayer(Id)<>nil then raise EArtFormat.Create('Duplicate layerId');
        Name := Str(O,'name'); if (Trim(Name)='') or (Length(Name)>255) then raise EArtFormat.Create('Invalid layer name');
        ParentId := Str(O,'parentId'); BeforeId := Str(O,'beforeLayerId'); Parent := nil;
        if ParentId<>'' then Parent := Target(ParentId);
        if (Parent<>nil) and (Parent.Kind<>alkGroup) then raise EArtFormat.Create('Parent must be a group');
        if Parent=nil then List := Current.Roots else List := Parent.Children;
        Before := nil; if BeforeId<>'' then begin Before := Target(BeforeId); if not List.Contains(Before) then raise EArtFormat.Create('beforeLayerId has different parent'); end;
        if Op='add_group' then L := Current.AddLayer(alkGroup,Name,TArtBounds.Create(0,0,0,0),Parent)
        else begin
          Image := ImageFor(Str(O,'assetId')); B := Obj(Field(O,'bounds')); Bounds := ReadBounds(B);
          L := Current.AddLayer(alkImage,Name,Bounds,Parent); SetImage(L,Image,Bounds);
        end;
        L.Id := Id; L.Visible := Bool(O,'visible'); L.Opacity := Num(O,'opacity',0,255);
        if Before<>nil then begin List.Remove(L); List.Insert(List.IndexOf(Before),L); end;
      end else if Op='replace_layer' then begin
        L := Target(Id); Image := ImageFor(Str(O,'assetId')); SetImage(L,Image,ReadBounds(Obj(Field(O,'bounds'))));
      end else if Op='rename_layer' then begin
        L := Target(Id); Name := Str(O,'name'); if (Trim(Name)='') or (Length(Name)>255) then raise EArtFormat.Create('Invalid layer name'); L.Name := Name;
      end else if Op='set_attributes' then begin
        L := Target(Id); L.Visible := Bool(O,'visible'); L.Opacity := Num(O,'opacity',0,255);
      end else if Op='select_part' then SelectExclusive(Current,Target(Id))
      else raise EArtFormat.Create('Unsupported operation: '+Op);
    end;
    RenderPsdLayers(Current); Current.Changed;
    Result := Current; Current := nil;
  finally Current.Free; Data.Free; Value.Free; end;
end;
procedure TArtExchange.CommitResult(Job: TArtExchangeJob; const Digest: string);
begin Job.AppliedHash := Digest; Job.State := 'completed'; Job.Progress := 100; Job.MessageText := ''; end;
end.

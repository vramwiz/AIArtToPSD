unit ArtPipeImages;

interface
uses System.SysUtils, System.Classes, System.JSON, System.Generics.Collections, Winapi.Windows,
  ArtDocument, ArtExchange;
const
  ART_IMAGE_CHUNK_BYTES = 12288;
  ART_IMAGE_FILE_BYTES = 33554432;
  ART_IMAGE_TOTAL_BYTES = 67108864;
  ART_IMAGE_TRANSFERS = 16;
  ART_IMAGE_RECEIPTS = 64;
  ART_IMAGE_IDLE_MS = 900000;
type
  TArtImageReceipt = class
  public
    Id,JobId,FileName,Directory,TempPath,FinalPath,Sha256,State: string;
    Size,Received,Width,Height: Integer;
    Touched: UInt64;
    Stream: THandleStream;
    FileHandle: THandle;
    destructor Destroy; override;
    procedure Stop(const NewState: string);
  end;
  TArtPipeImages = class
  private
    FTransfers: TObjectDictionary<string,TArtImageReceipt>;
    procedure Expire;
    function ReceiptJson(Receipt: TArtImageReceipt): TJSONObject;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure AbortJob(const JobId: string);
    function Execute(const Command: string; Args: TJSONObject;
      Exchange: TArtExchange; Document: TArtDocument): TJSONObject;
  end;

implementation
uses System.IOUtils, System.Hash, System.NetEncoding,
  ArtPipeProtocol, ArtPng;

procedure CheckPath(const Path: string);
var Current,Parent: string; Attributes: Cardinal;
begin
  Current := TPath.GetFullPath(Path);
  repeat
    Attributes := GetFileAttributes(PChar(Current));
    if (Attributes<>INVALID_FILE_ATTRIBUTES) and
      ((Attributes and FILE_ATTRIBUTE_REPARSE_POINT)<>0) then
      raise EArtFormat.Create('Image transfer links and junctions are not allowed');
    Parent := ExtractFileDir(Current);
    if (Parent='') or SameText(Parent,Current) then Break;
    Current := Parent;
  until False;
end;

function TransferId(Args: TJSONObject): string;
var Id: TGUID;
begin
  try Id := StringToGUID(CommandString(Args,'transferId'));
  except on EConvertError do raise EArtFormat.Create('GUID transferId required'); end;
  Result := GUIDToString(Id);
end;

procedure ValidateName(const Name: string);
var Stem: string;
begin
  if (Length(Name)<5) or (Length(Name)>120) or not SameText(ExtractFileExt(Name),'.png') or
    not CharInSet(Name[1],['a'..'z','A'..'Z','0'..'9']) or (Pos('..',Name)>0) then
    raise EArtFormat.Create('Simple new PNG basename required');
  for var C in Name do if not CharInSet(C,['a'..'z','A'..'Z','0'..'9','-','_','.']) then
    raise EArtFormat.Create('Simple new PNG basename required');
  Stem := UpperCase(Copy(Name,1,Pos('.',Name)-1));
  if (Stem='CON') or (Stem='PRN') or (Stem='AUX') or (Stem='NUL') or
    ((Length(Stem)=4) and ((Copy(Stem,1,3)='COM') or (Copy(Stem,1,3)='LPT')) and
    CharInSet(Stem[4],['1'..'9'])) then raise EArtFormat.Create('Reserved PNG basename');
end;

procedure ValidateHash(const Hash: string);
begin
  if Length(Hash)<>64 then raise EArtFormat.Create('SHA256 must have 64 hex characters');
  for var C in Hash do if not CharInSet(C,['0'..'9','a'..'f','A'..'F']) then
    raise EArtFormat.Create('SHA256 must have 64 hex characters');
end;

function ChunkBytes(Args: TJSONObject): TBytes;
var Text: string; Encoding: TBase64Encoding;
begin
  Text := CommandString(Args,'dataBase64');
  if (Length(Text)=0) or (Length(Text)>ART_IMAGE_CHUNK_BYTES div 3*4) or
    (Length(Text) mod 4<>0) then raise EArtFormat.Create('Image chunk base64 size limit');
  for var C in Text do if not CharInSet(C,['a'..'z','A'..'Z','0'..'9','+','/','=']) then
    raise EArtFormat.Create('Canonical base64 required');
  Encoding := TBase64Encoding.Create(0);
  try
    try Result := Encoding.DecodeStringToBytes(Text);
    except on Exception do raise EArtFormat.Create('Canonical base64 required'); end;
    if (Length(Result)=0) or (Length(Result)>ART_IMAGE_CHUNK_BYTES) or
      (Encoding.EncodeBytesToString(Result)<>Text) then raise EArtFormat.Create('Canonical base64 required');
  finally Encoding.Free; end;
end;

destructor TArtImageReceipt.Destroy;
begin Stop('aborted'); inherited; end;
procedure TArtImageReceipt.Stop(const NewState: string);
begin
  FreeAndNil(Stream);
  if FileHandle<>0 then begin CloseHandle(FileHandle); FileHandle := 0; end;
  if (TempPath<>'') and FileExists(TempPath) then
    if not DeleteFile(PChar(TempPath)) then RaiseLastOSError;
  TempPath := ''; State := NewState;
end;

constructor TArtPipeImages.Create;
begin inherited; FTransfers := TObjectDictionary<string,TArtImageReceipt>.Create([doOwnsValues]); end;
destructor TArtPipeImages.Destroy;
begin FTransfers.Free; inherited; end;
procedure TArtPipeImages.Clear;
begin FTransfers.Clear; end;
procedure TArtPipeImages.AbortJob(const JobId: string);
begin
  for var R in FTransfers.Values do
    if (R.JobId=JobId) and (R.State='receiving') then R.Stop('aborted');
end;
procedure TArtPipeImages.Expire;
var Ids: TArray<string>; NowTick: UInt64;
begin
  NowTick := GetTickCount64; Ids := FTransfers.Keys.ToArray;
  for var Id in Ids do
    if NowTick-FTransfers[Id].Touched>=ART_IMAGE_IDLE_MS then FTransfers.Remove(Id);
end;
function TArtPipeImages.ReceiptJson(Receipt: TArtImageReceipt): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('transferId',Receipt.Id); Result.AddPair('jobId',Receipt.JobId);
  Result.AddPair('state',Receipt.State); Result.AddPair('path','images/'+Receipt.FileName);
  Result.AddPair('sizeBytes',TJSONNumber.Create(Receipt.Size));
  Result.AddPair('receivedBytes',TJSONNumber.Create(Receipt.Received));
  Result.AddPair('sha256',Receipt.Sha256);
  Result.AddPair('width',TJSONNumber.Create(Receipt.Width)); Result.AddPair('height',TJSONNumber.Create(Receipt.Height));
  Result.AddPair('maxChunkBytes',TJSONNumber.Create(ART_IMAGE_CHUNK_BYTES));
end;

function TArtPipeImages.Execute(const Command: string; Args: TJSONObject;
  Exchange: TArtExchange; Document: TArtDocument): TJSONObject;
var Id,Name,Hash,JobId,Directory: string; R,Existing: TArtImageReceipt;
  Job: TArtExchangeJob; Size,Width,Height,Offset,Active: Integer; Total: Int64;
  Bytes,Previous: TBytes; G: TGUID; Handle: THandle; Image: TArtPngData;
  Validation: THandleStream;
  procedure CheckJob;
  begin
    Job := Exchange.FindJob(JobId);
    if (Job.State='cancelled') or (Job.State='completed') or
      (Document=nil) or (Document.SessionId<>Job.DocumentId) or (Document.Revision<>Job.Revision) then
      raise EArtFormat.Create('Image transfer job is cancelled, completed or stale');
  end;
begin
  Expire; Id := TransferId(Args); R := nil;
  if Command='image-begin' then begin
    JobId := CommandString(Args,'jobId'); CheckJob;
    Name := CommandString(Args,'fileName'); ValidateName(Name);
    Hash := LowerCase(CommandString(Args,'sha256')); ValidateHash(Hash);
    Size := CommandInteger(Args,'sizeBytes'); Width := CommandInteger(Args,'width'); Height := CommandInteger(Args,'height');
    if (Size<24) or (Size>ART_IMAGE_FILE_BYTES) or (Width<1) or (Height<1) or
      (Width>30000) or (Height>30000) then raise EArtFormat.Create('Image transfer size limit');
    PixelByteCount(Width,Height,4);
    if FTransfers.TryGetValue(Id,Existing) then begin
      if (Existing.JobId<>JobId) or (Existing.FileName<>Name) or (Existing.Sha256<>Hash) or
        (Existing.Size<>Size) or (Existing.Width<>Width) or (Existing.Height<>Height) then
        raise EArtFormat.Create('transferId already has different metadata');
      Existing.Touched := GetTickCount64; Exit(ReceiptJson(Existing));
    end;
    if FTransfers.Count>=ART_IMAGE_RECEIPTS then raise EArtFormat.Create('Image transfer receipt limit');
    Directory := TPath.GetFullPath(TPath.Combine(Job.Directory,'images')); CheckPath(Directory);
    if not DirectoryExists(Directory) then raise EArtFormat.Create('Issued job images directory is missing');
    Total := Size; Active := 0;
    for Existing in FTransfers.Values do begin
      if (Existing.State='receiving') then begin Inc(Total,Existing.Size); Inc(Active); end;
      if (Existing.State='receiving') and SameText(Existing.Directory,Directory) and SameText(Existing.FileName,Name) then
        raise EArtFormat.Create('PNG destination already reserved');
    end;
    if Active>=ART_IMAGE_TRANSFERS then raise EArtFormat.Create('Image transfer count limit');
    if Total>ART_IMAGE_TOTAL_BYTES then raise EArtFormat.Create('Image transfer total byte limit');
    R := TArtImageReceipt.Create;
    try
      R.Id := Id; R.JobId := JobId; R.FileName := Name; R.Directory := Directory;
      R.FinalPath := TPath.Combine(Directory,Name); CheckPath(R.FinalPath);
      if FileExists(R.FinalPath) or DirectoryExists(R.FinalPath) then raise EArtFormat.Create('PNG destination already exists');
      CreateGUID(G); R.TempPath := TPath.Combine(Directory,'.pipe-'+GUIDToString(G)+'.part');
      Handle := CreateFile(PChar(R.TempPath),GENERIC_READ or GENERIC_WRITE,0,nil,CREATE_NEW,
        FILE_ATTRIBUTE_NORMAL,0);
      if Handle=INVALID_HANDLE_VALUE then begin R.TempPath := ''; RaiseLastOSError; end;
      R.FileHandle := Handle; R.Stream := THandleStream.Create(Handle);
      R.Size := Size; R.Width := Width; R.Height := Height; R.Sha256 := Hash;
      R.State := 'receiving'; R.Touched := GetTickCount64;
      FTransfers.Add(Id,R);
    except R.Free; raise; end;
    Exit(ReceiptJson(R));
  end;
  if not FTransfers.TryGetValue(Id,R) then raise EArtFormat.Create('Unknown or expired transferId');
  R.Touched := GetTickCount64;
  if Command='image-status' then Exit(ReceiptJson(R));
  if Command='image-abort' then begin
    if R.State='receiving' then R.Stop('aborted');
    Exit(ReceiptJson(R));
  end;
  if (Command='image-commit') and (R.State='committed') then Exit(ReceiptJson(R));
  if R.State<>'receiving' then raise EArtFormat.Create('Image transfer is not receiving');
  JobId := R.JobId; CheckJob; CheckPath(R.Directory); CheckPath(R.TempPath);
  if Command='image-chunk' then begin
    Offset := CommandInteger(Args,'offset'); Bytes := ChunkBytes(Args);
    if (Offset<0) or (Offset>R.Received) or (Int64(Offset)+Length(Bytes)>R.Size) then
      raise EArtFormat.Create('Image chunk offset/size does not match');
    if Offset<R.Received then begin
      if Int64(Offset)+Length(Bytes)>R.Received then raise EArtFormat.Create('Image chunk partly overlaps received bytes');
      SetLength(Previous,Length(Bytes)); R.Stream.Position := Offset;
      try R.Stream.ReadBuffer(Previous[0],Length(Previous));
      finally R.Stream.Position := R.Received; end;
      if not CompareMem(@Previous[0],@Bytes[0],Length(Bytes)) then raise EArtFormat.Create('Image chunk retry differs from received bytes');
    end else begin
      try
        R.Stream.Position := R.Received;
        R.Stream.WriteBuffer(Bytes[0],Length(Bytes)); Inc(R.Received,Length(Bytes));
      except R.Stop('failed'); raise; end;
    end;
    Exit(ReceiptJson(R));
  end;
  if Command<>'image-commit' then raise EArtFormat.Create('Unknown image command');
  if R.Received<>R.Size then raise EArtFormat.Create('Image transfer is incomplete');
  try
    if not FlushFileBuffers(R.Stream.Handle) then RaiseLastOSError;
    FreeAndNil(R.Stream); CloseHandle(R.FileHandle); R.FileHandle := 0;
    // Hold a write-denying, rename-compatible read handle through hash/PNG
    // validation and publication, so the validated bytes cannot change.
    Handle := CreateFile(PChar(R.TempPath),GENERIC_READ,FILE_SHARE_READ or FILE_SHARE_DELETE,
      nil,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,0);
    if Handle=INVALID_HANDLE_VALUE then RaiseLastOSError;
    Validation := nil;
    try
      Validation := THandleStream.Create(Handle);
      if Validation.Size<>R.Size then raise EArtFormat.Create('Image transfer file size changed');
      Hash := LowerCase(THashSHA2.GetHashString(Validation));
      if Hash<>R.Sha256 then raise EArtFormat.Create('Image transfer SHA256 mismatch');
      Image := ReadPng(R.TempPath);
      if (Image.Width<>R.Width) or (Image.Height<>R.Height) then raise EArtFormat.Create('Image transfer PNG dimensions mismatch');
      CheckPath(R.Directory); CheckPath(R.FinalPath);
      if FileExists(R.FinalPath) or DirectoryExists(R.FinalPath) then raise EArtFormat.Create('PNG destination already exists');
      if not MoveFileEx(PChar(R.TempPath),PChar(R.FinalPath),MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
      R.TempPath := ''; R.State := 'committed';
    finally Validation.Free; CloseHandle(Handle); end;
  except R.Stop('failed'); raise; end;
  Result := ReceiptJson(R);
end;
end.

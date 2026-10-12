program ExclusiveImportSmoke;
{$APPTYPE CONSOLE}

uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  System.Generics.Collections,
  ArtDocument in '..\Source\Core\ArtDocument.pas',
  ArtParts in '..\Source\Core\ArtParts.pas',
  ArtLayerName in '..\Source\Core\ArtLayerName.pas',
  ArtPng in '..\Source\Persistence\PNG\ArtPng.pas',
  ArtPsd in '..\Source\Persistence\PSD\ArtPsd.pas',
  ArtExchange in '..\Source\Integrations\AIExchange\ArtExchange.pas';

var D,C: TArtDocument; E: TArtExchange; Request,Response: TJSONObject;
  Operations: TJSONArray; Root,Path,Digest: string; Job: TArtExchangeJob;
  Count,CaseCount: Integer;

procedure Check(Value: Boolean; const MessageText: string);
begin
  Inc(Count);
  if not Value then raise Exception.Create(MessageText);
end;

function AddLayer(const Id,Name: string; Kind: TArtLayerKind;
  Parent: TArtLayer; Visible: Boolean): TArtLayer;
begin
  if Kind=alkGroup then Result := D.AddLayer(Kind,Name,TArtBounds.Create(0,0,0,0),Parent)
  else begin
    Result := D.AddLayer(Kind,Name,TArtBounds.Create(0,0,2,2),Parent);
    SetLength(Result.Pixels,16);
    for var I := 0 to 15 do Result.Pixels[I] := 255;
  end;
  Result.Id := Id; Result.Visible := Visible;
end;

procedure Fixture;
var Eyes,Mouth,Nested: TArtLayer;
begin
  D := TArtDocument.Create; D.Width := 2; D.Height := 2;
  AddLayer('root-normal','normal root',alkImage,nil,True);
  Eyes := AddLayer('eyes','eyes',alkGroup,nil,True);
  AddLayer('eyes-1','*first',alkImage,Eyes,True);
  AddLayer('eyes-2','*second',alkImage,Eyes,False);
  AddLayer('normal-on','normal on',alkImage,Eyes,True);
  AddLayer('normal-off','normal off',alkImage,Eyes,False);
  AddLayer('mixed-on','*!mixed',alkImage,Eyes,True);
  AddLayer('double-on','**double',alkImage,Eyes,True);
  Nested := AddLayer('nested','nested',alkGroup,Eyes,True);
  AddLayer('nested-1','*first',alkImage,Nested,True);
  AddLayer('nested-2','*second',alkImage,Nested,False);
  Mouth := AddLayer('mouth','mouth',alkGroup,nil,True);
  AddLayer('mouth-1','*first',alkImage,Mouth,True);
  AddLayer('mouth-2','*second',alkImage,Mouth,False);
  AddLayer('root-1','*group first',alkGroup,nil,True);
  AddLayer('root-2','*group second',alkGroup,nil,False);
  ValidateExclusiveSelections(D);
end;

function Snapshot(Document: TArtDocument): string;
var Meta: TJSONObject; Layers: TJSONArray;
  procedure Capture(List: TList<TArtLayer>; const ParentId: string);
  var Layer: TJSONObject; Hash: THashSHA2;
  begin
    for var L in List do begin
      Layer := TJSONObject.Create; Layers.AddElement(Layer);
      Layer.AddPair('id',L.Id); Layer.AddPair('parentId',ParentId); Layer.AddPair('name',L.Name);
      Layer.AddPair('kind',TJSONNumber.Create(Ord(L.Kind)));
      Layer.AddPair('visible',TJSONBool.Create(L.Visible));
      Layer.AddPair('opacity',TJSONNumber.Create(L.Opacity));
      Layer.AddPair('left',TJSONNumber.Create(L.Bounds.Left));
      Layer.AddPair('top',TJSONNumber.Create(L.Bounds.Top));
      Layer.AddPair('right',TJSONNumber.Create(L.Bounds.Right));
      Layer.AddPair('bottom',TJSONNumber.Create(L.Bounds.Bottom));
      Hash := THashSHA2.Create; Hash.Update(L.Pixels);
      Layer.AddPair('pixelSha256',Hash.HashAsString);
      Capture(L.Children,L.Id);
    end;
  end;
begin
  Meta := TJSONObject.Create;
  try
    Meta.AddPair('documentId',Document.SessionId); Meta.AddPair('revision',UIntToStr(Document.Revision));
    Meta.AddPair('width',TJSONNumber.Create(Document.Width));
    Meta.AddPair('height',TJSONNumber.Create(Document.Height));
    Layers := TJSONArray.Create; Meta.AddPair('layers',Layers); Capture(Document.Roots,'');
    Result := Meta.ToJSON;
  finally Meta.Free; end;
end;

procedure StartJob;
begin
  Path := E.ExportJob(D,'exclusive import fixture',Root);
  Request := TJSONObject.ParseJSONValue(TFile.ReadAllText(TPath.Combine(Path,'request.json'))) as TJSONObject;
  Response := TJSONObject.Create;
  for var Key in ['schemaVersion','jobId','requestId','documentId','ifRevision'] do
    Response.AddPair(Key,Request.GetValue(Key).Clone as TJSONValue);
  Response.AddPair('assets',TJSONArray.Create);
  Operations := TJSONArray.Create; Response.AddPair('operations',Operations);
end;

function Operation(const Op,Id: string): TJSONObject;
begin
  Result := TJSONObject.Create; Operations.AddElement(Result);
  Result.AddPair('op',Op); Result.AddPair('layerId',Id);
end;

procedure Attributes(const Id: string; Visible: Boolean; Opacity: Byte = 255);
var OperationJson: TJSONObject;
begin
  OperationJson := Operation('set_attributes',Id);
  OperationJson.AddPair('visible',TJSONBool.Create(Visible));
  OperationJson.AddPair('opacity',TJSONNumber.Create(Opacity));
end;

procedure Rename(const Id,Name: string);
begin Operation('rename_layer',Id).AddPair('name',Name); end;

procedure AddOperation(const Op,Name,ParentId: string; Visible: Boolean);
var OperationJson: TJSONObject;
begin
  OperationJson := Operation(Op,'added'); OperationJson.AddPair('name',Name);
  OperationJson.AddPair('parentId',ParentId); OperationJson.AddPair('beforeLayerId','');
  OperationJson.AddPair('visible',TJSONBool.Create(Visible));
  OperationJson.AddPair('opacity',TJSONNumber.Create(255));
  if Op='add_layer' then begin
    Response.RemovePair('assets').Free;
    Response.AddPair('assets',Request.GetValue('assets').Clone as TJSONValue);
    OperationJson.AddPair('assetId','source-1');
    OperationJson.AddPair('bounds',TJSONObject.ParseJSONValue('{"left":0,"top":0,"right":2,"bottom":2}'));
  end;
end;

procedure WriteResult;
begin TFile.WriteAllText(TPath.Combine(Path,'result.json'),Response.ToJSON,TEncoding.UTF8); end;

procedure Reject(const ErrorText,ParentId: string; TestCase: Integer);
var Before,State,AppliedHash,MessageText: string; Rejected: Boolean; OriginalJob: TArtExchangeJob;
begin
  Before := Snapshot(D); OriginalJob := E.FindJob(Request.GetValue('jobId').Value);
  State := OriginalJob.State; AppliedHash := OriginalJob.AppliedHash;
  WriteResult; Rejected := False; MessageText := ''; C := nil;
  try C := E.PrepareResult(D,TPath.Combine(Path,'result.json'),Job,Digest);
  except on X: EArtFormat do begin Rejected := True; MessageText := X.Message; end; end;
  C.Free; C := nil;
  Check(Rejected,'Conflicting/invalid batch accepted: '+IntToStr(TestCase));
  Check(Pos(ErrorText,MessageText)>0,'Wrong rejection reason: '+MessageText);
  if ErrorText='Exclusive selection conflict:' then
    Check(Pos('parentId="'+ParentId+'"',MessageText)>0,'Conflict parent not identified: '+MessageText);
  Check(Snapshot(D)=Before,'Rejected batch mutated source tree, pixels or revision');
  Check((OriginalJob.State=State) and (OriginalJob.AppliedHash=AppliedHash),'Rejected batch committed the job');
  TFile.WriteAllText(TPath.Combine(Path,'expected-rejection.txt'),MessageText,TEncoding.UTF8);
end;

procedure Accept(TestCase: Integer);
var Before: string;
begin
  Before := Snapshot(D); WriteResult;
  C := E.PrepareResult(D,TPath.Combine(Path,'result.json'),Job,Digest);
  Check(C<>nil,'Valid batch returned no candidate');
  Check(Snapshot(D)=Before,'Valid preparation mutated source');
  Check((C.SessionId=D.SessionId) and (C.Revision=D.Revision+1),'Batch changed identity or incremented revision more than once');
  ValidateExclusiveSelections(C);
  Check(C.FindLayer('normal-off').Visible=False,'Normal hidden sibling switched');
  if TestCase<>25 then Check(C.FindLayer('normal-on').Visible,'Normal visible sibling switched');
  Check(C.FindLayer('mixed-on').Visible and C.FindLayer('double-on').Visible,'Chained prefixes treated as exclusive');
  Check(C.FindLayer('nested-1').Visible and not C.FindLayer('nested-2').Visible,'Nested group switched');
  Check(C.FindLayer('root-1').Visible and not C.FindLayer('root-2').Visible,'Other root selection switched');
  if TestCase<>21 then Check(C.FindLayer('mouth-1').Visible and not C.FindLayer('mouth-2').Visible,'Different parent switched');
  case TestCase of
    10,11,14,21,22,28: Check(not C.FindLayer('eyes-1').Visible and C.FindLayer('eyes-2').Visible,'Requested selection lost');
    12: Check(C.FindLayer('eyes-1').Visible and not C.FindLayer('eyes-2').Visible,'Later explicit selection lost');
    15: Check(not C.FindLayer('eyes-1').Visible and not C.FindLayer('eyes-2').Visible,'Zero selection rejected/changed');
    16: Check(C.FindLayer('added').Visible,'Normal added sibling hidden');
    17,18: Check(not C.FindLayer('added').Visible,'Hidden added alternative enabled');
    19: Check((C.FindLayer('normal-off').Name='*renamed') and not C.FindLayer('normal-off').Visible,'Hidden rename failed');
    20: Check(C.FindLayer('eyes-1').Visible and not C.FindLayer('eyes-2').Visible,'Prefix chain affected selection');
    23: Check((C.FindLayer('eyes-1').Name='plain first') and C.FindLayer('eyes-1').Visible and C.FindLayer('eyes-2').Visible,'Final rename not applied');
    25: Check(not C.FindLayer('normal-on').Visible,'Explicit ordinary attribute update lost');
    29: Check((C.FindLayer('eyes-2').Name='plain second') and C.FindLayer('eyes-2').Visible and not C.FindLayer('eyes-1').Visible,'Final selected rename failed');
  end;
  if TestCase=21 then begin
    Check(not C.FindLayer('mouth-1').Visible and C.FindLayer('mouth-2').Visible,'Second parent selection lost');
    WriteNewPsd(C,TPath.Combine(Path,'selection-combination.psd'),pcRle);
    var Reloaded := ReadPsd(TPath.Combine(Path,'selection-combination.psd'));
    try
      ValidateExclusiveSelections(Reloaded);
      Check((not Reloaded.Roots[1].Children[0].Visible) and Reloaded.Roots[1].Children[1].Visible,'Saved first selection lost');
      Check((not Reloaded.Roots[2].Children[0].Visible) and Reloaded.Roots[2].Children[1].Visible,'Saved second selection lost');
    finally Reloaded.Free; end;
  end;
  C.Free; C := nil;
end;

procedure RunCase(TestCase: Integer);
var ExpectedError,ParentId: string;
begin
  Inc(CaseCount); Fixture; Request := nil; Response := nil; C := nil;
  try
    if TestCase in [6,22] then D.FindLayer('eyes-2').Visible := True;
    if TestCase=24 then D.FindLayer('nested-2').Visible := True;
    StartJob; ExpectedError := ''; ParentId := 'eyes';
    case TestCase of
      0: Attributes('eyes-2',True);
      1: begin Attributes('eyes',False); Attributes('eyes-2',True); end;
      2: Attributes('eyes-2',True,0);
      3: AddOperation('add_layer','*new','eyes',True);
      4: AddOperation('add_group','*new group','eyes',True);
      5: Rename('normal-on','*renamed');
      6: Rename('root-normal','other normal root');
      7: begin Attributes('root-2',True); ParentId := ''; end;
      8: begin Attributes('nested-2',True); ParentId := 'nested'; end;
      9: begin Operation('select_part','normal-on'); ExpectedError := '排他選択 (*)'; end;
      10: begin Attributes('eyes-2',True); Attributes('eyes-1',False); end;
      11: begin Attributes('eyes-1',False); Attributes('eyes-2',True); end;
      12: begin Attributes('eyes-2',True); Operation('select_part','eyes-1'); end;
      13: begin Operation('select_part','eyes-2'); Attributes('eyes-1',True); end;
      14: begin Operation('select_part','eyes-1'); Operation('select_part','eyes-2'); end;
      15: Attributes('eyes-1',False);
      16: AddOperation('add_layer','normal added','eyes',True);
      17: AddOperation('add_layer','*hidden added','eyes',False);
      18: AddOperation('add_group','*hidden group','eyes',False);
      19: Rename('normal-off','*renamed');
      20: begin Rename('normal-on','*!renamed mixed'); Operation('select_part','eyes-1'); end;
      21: begin Operation('select_part','eyes-2'); Operation('select_part','mouth-2'); end;
      22: Operation('select_part','eyes-2');
      23: begin Attributes('eyes-2',True); Rename('eyes-1','plain first'); end;
      24: begin Operation('select_part','eyes-2'); ParentId := 'nested'; end;
      25: Attributes('normal-on',False,123);
      26: begin Operation('select_part','missing'); ExpectedError := 'Unknown layerId:'; end;
      27: begin Rename('eyes-1','plain first'); Operation('select_part','eyes-1'); ExpectedError := '排他選択 (*)'; end;
      28: begin Attributes('eyes-2',True); AddOperation('add_layer','normal added','eyes',True); Attributes('eyes-1',False); end;
      29: begin Operation('select_part','eyes-2'); Rename('eyes-2','plain second'); end;
      30: begin AddOperation('add_group','*root added','',True); ParentId := ''; end;
    end;
    if TestCase in [0..9,13,24,26,27,30] then begin
      if ExpectedError='' then ExpectedError := 'Exclusive selection conflict:';
      Reject(ExpectedError,ParentId,TestCase);
    end else Accept(TestCase);
  finally C.Free; Response.Free; Request.Free; D.Free; D := nil; end;
end;

begin
  try
    if ParamCount<>1 then raise Exception.Create('Usage: ExclusiveImportSmoke OUTPUT_DIRECTORY');
    Root := TPath.GetFullPath(ParamStr(1)); E := TArtExchange.Create;
    try
      for var TestCase := 0 to 30 do RunCase(TestCase);
      Writeln('PASS: ',Count,' exclusive import assertions across ',CaseCount,' cases');
    finally E.Free; end;
  except on X: Exception do begin Writeln(X.ClassName,': ',X.Message); Halt(1); end; end;
end.

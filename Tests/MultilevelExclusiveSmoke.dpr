program MultilevelExclusiveSmoke;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  System.Generics.Collections,
  ArtDocument in '..\Source\Core\ArtDocument.pas',
  ArtParts in '..\Source\Core\ArtParts.pas',
  ArtLayerName in '..\Source\Core\ArtLayerName.pas',
  ArtPng in '..\Source\Persistence\PNG\ArtPng.pas',
  ArtPsd in '..\Source\Persistence\PSD\ArtPsd.pas',
  ArtExchange in '..\Source\Integrations\AIExchange\ArtExchange.pas';

var D: TArtDocument; Output: string; Checks: Integer;
procedure Check(Value: Boolean; const Text: string);
begin Inc(Checks); if not Value then raise Exception.Create(Text); end;
function Layer(Document: TArtDocument; const Id: string): TArtLayer;
begin Result := Document.FindLayer(Id); if Result=nil then raise Exception.Create('Missing fixture layer: '+Id); end;
function Add(const Id,Name: string; Parent: TArtLayer; Group,Visible: Boolean): TArtLayer;
begin
  if Group then Result := D.AddLayer(alkGroup,Name,TArtBounds.Create(0,0,0,0),Parent)
  else begin
    Result := D.AddLayer(alkImage,Name,TArtBounds.Create(1,1,2,2),Parent);
    Result.Pixels := TBytes.Create(Byte(Length(Id)*7),50,100,255);
  end;
  Result.Id := Id; Result.Visible := Visible;
end;
procedure Fixture;
var Actor,Right,Left,Foot,A,B,Near,Far: TArtLayer;
begin
  D := TArtDocument.Create; D.Width := 4; D.Height := 3;
  Actor := Add('fixed-on','BODY',nil,False,True); Actor.Bounds := TArtBounds.Create(0,0,1,1);
  Add('fixed-off','hidden fixed',nil,False,False);
  Actor := Add('actor','actor',nil,True,False);
  Right := Add('right','右手',Actor,True,False);
  Add('idle','*IDLE',Right,False,True);
  A := Add('a','*A',Right,True,False);
  Add('a-0','*0',A,False,True); Add('a-1','*1',A,False,False);
  B := Add('b','*B',Right,True,False);
  Near := Add('near','*near',B,True,False); Far := Add('far','*far',B,True,True);
  Add('near-0','*0',Near,False,True); Add('near-1','*1',Near,False,False);
  Add('far-0','*0',Far,False,True); Add('far-1','*1',Far,False,False);
  Add('overlay','sleeve',Right,False,True); Add('forced','!foreground',Right,False,True);
  Add('legacy-mixed','*!mixed',Right,False,True); Add('legacy-double','**double',Right,False,True);
  Left := Add('left','左手',Actor,True,True); B := Add('left-b','*B',Left,True,True);
  Add('left-0','*0',B,False,False); Add('left-1','*1',B,False,True);
  Foot := Add('right-foot','右足',Actor,True,True); Add('right-foot-0','*0',Foot,False,True); Add('right-foot-1','*1',Foot,False,False);
  Foot := Add('left-foot','左足',Actor,True,True); Add('left-foot-0','*0',Foot,False,True); Add('left-foot-1','*1',Foot,False,False);
  ValidateExclusiveSelections(D);
end;
function Snapshot(Document: TArtDocument; IncludeVisibility: Boolean): string;
var Items: TJSONArray;
  procedure Visit(List: TList<TArtLayer>; const ParentId: string);
  var Item: TJSONObject; Hash: THashSHA2;
  begin
    for var L in List do begin
      Item := TJSONObject.Create; Items.AddElement(Item);
      Item.AddPair('id',L.Id); Item.AddPair('parent',ParentId); Item.AddPair('name',L.Name);
      Item.AddPair('kind',TJSONNumber.Create(Ord(L.Kind))); Item.AddPair('opacity',TJSONNumber.Create(L.Opacity));
      Item.AddPair('left',TJSONNumber.Create(L.Bounds.Left)); Item.AddPair('top',TJSONNumber.Create(L.Bounds.Top));
      Item.AddPair('right',TJSONNumber.Create(L.Bounds.Right)); Item.AddPair('bottom',TJSONNumber.Create(L.Bounds.Bottom));
      if IncludeVisibility then Item.AddPair('visible',TJSONBool.Create(L.Visible));
      Hash := THashSHA2.Create; Hash.Update(L.Pixels); Item.AddPair('rgba',Hash.HashAsString);
      Visit(L.Children,L.Id);
    end;
  end;
begin
  Items := TJSONArray.Create;
  try Visit(Document.Roots,''); Result := Items.ToJSON; finally Items.Free; end;
end;
procedure Independent(Document: TArtDocument);
begin
  Check(Layer(Document,'left').Visible and Layer(Document,'left-b').Visible and Layer(Document,'left-1').Visible,'Same-name left branch changed');
  Check(not Layer(Document,'left-0').Visible,'Left phase changed');
  Check(Layer(Document,'right-foot-0').Visible and not Layer(Document,'right-foot-1').Visible,'Right foot changed');
  Check(Layer(Document,'left-foot-0').Visible and not Layer(Document,'left-foot-1').Visible,'Left foot changed');
  Check(Layer(Document,'fixed-on').Visible and not Layer(Document,'fixed-off').Visible,'Root fixed layers changed');
  Check(Layer(Document,'overlay').Visible and Layer(Document,'forced').Visible,'Nonexclusive/forced foreground changed');
  Check(Layer(Document,'legacy-mixed').Visible and Layer(Document,'legacy-double').Visible,'Ambiguous legacy prefixes changed');
end;
procedure AssertDeep(Document: TArtDocument);
begin
  Check(Layer(Document,'actor').Visible and Layer(Document,'right').Visible,'Hidden nonexclusive ancestors were not shown');
  Check(Layer(Document,'b').Visible and Layer(Document,'near').Visible and Layer(Document,'near-1').Visible,'Deep selected branch missing');
  Check(not Layer(Document,'idle').Visible and not Layer(Document,'a').Visible,'Other top-level pattern/IDLE remains visible');
  Check(not Layer(Document,'far').Visible and not Layer(Document,'near-0').Visible,'Other nested pattern/phase remains visible');
  Independent(Document); ValidateExclusiveSelections(Document);
end;
procedure SameTree(A,B: TArtLayer);
begin
  Check((A.Kind=B.Kind) and (A.Name=B.Name) and (A.Visible=B.Visible) and (A.Opacity=B.Opacity) and
    (A.BlendKey=B.BlendKey) and CompareMem(@A.Bounds,@B.Bounds,SizeOf(TArtBounds)), 'Saved layer properties differ');
  Check(Length(A.Pixels)=Length(B.Pixels),'Saved pixel size differs');
  if Length(A.Pixels)>0 then Check(CompareMem(@A.Pixels[0],@B.Pixels[0],Length(A.Pixels)),'Saved RGBA differs');
  Check(A.Children.Count=B.Children.Count,'Saved hierarchy differs');
  for var I := 0 to A.Children.Count-1 do SameTree(A.Children[I],B.Children[I]);
end;
procedure SavedRoundtrip(Document: TArtDocument; const Name: string);
var Saved: TArtDocument; BeforePixels,AfterPixels: TBytes;
begin
  WriteNewPsd(Document,TPath.Combine(Output,Name),pcRle); Saved := ReadPsd(TPath.Combine(Output,Name));
  try
    Check((Document.Width=Saved.Width) and (Document.Height=Saved.Height),'Saved canvas differs');
    Check(Document.Roots.Count=Saved.Roots.Count,'Saved root count differs');
    for var I := 0 to Document.Roots.Count-1 do SameTree(Document.Roots[I],Saved.Roots[I]);
    BeforePixels := RenderPsdLayers(Document); AfterPixels := RenderPsdLayers(Saved);
    Check((Length(BeforePixels)=Length(AfterPixels)) and CompareMem(@BeforePixels[0],@AfterPixels[0],Length(BeforePixels)),'Saved/reloaded composition differs');
    ValidateExclusiveSelections(Saved);
  finally Saved.Free; end;
end;
procedure CoreCases;
var Before,Metadata: string; Version: UInt64; Foreign: TArtLayer; Rejected: Boolean;
begin
  Fixture;
  try
    Metadata := Snapshot(D,False); Version := D.Revision;
    SelectExclusive(D,Layer(D,'near-1')); AssertDeep(D);
    Check(Snapshot(D,False)=Metadata,'Selection changed pixels, names, positions, order or opacity');
    Check(D.Revision=Version,'Core visibility primitive changed revision itself');
    Before := Snapshot(D,True); SelectExclusive(D,Layer(D,'near-1')); Check(Snapshot(D,True)=Before,'Repeat selection not idempotent');
    SelectExclusive(D,Layer(D,'idle')); Check(Layer(D,'idle').Visible and not Layer(D,'a').Visible and not Layer(D,'b').Visible,'Group-to-IDLE switch failed'); Independent(D);
    SelectExclusive(D,Layer(D,'a-1')); Check(Layer(D,'a').Visible and Layer(D,'a-1').Visible and not Layer(D,'a-0').Visible,'IDLE-to-other-pattern child switch failed');
    Check(not Layer(D,'idle').Visible and not Layer(D,'b').Visible,'Old group/IDLE not excluded'); Independent(D);
    SelectExclusive(D,Layer(D,'near-1')); AssertDeep(D); SavedRoundtrip(D,'selected.psd');
    Before := Snapshot(D,True); Foreign := TArtLayer.Create;
    try
      Foreign.Name := '*1'; Foreign.Id := 'near-1'; Rejected := False;
      try SelectExclusive(D,Foreign); except on E: EArtFormat do Rejected := True; end;
      Check(Rejected and (Snapshot(D,True)=Before),'Foreign same-ID layer mutated document');
      Rejected := False; try SelectExclusive(nil,Layer(D,'near-1')); except on E: EArtFormat do Rejected := True; end;
      Check(Rejected and (Snapshot(D,True)=Before),'Nil document mutated source');
      Rejected := False; try SelectExclusive(D,Layer(D,'fixed-on')); except on E: EArtFormat do Rejected := True; end;
      Check(Rejected and (Snapshot(D,True)=Before),'Nonexclusive target accepted');
    finally Foreign.Free; end;
  finally D.Free; end;
end;
procedure RootAndDepthCases;
var A,B,Fixed,L: TArtLayer; Before: string; Rejected: Boolean;
begin
  D := TArtDocument.Create; D.Width := 4; D.Height := 3;
  try
    A := Add('actor-a','*actor A',nil,True,False); B := Add('actor-b','*actor B',nil,True,True);
    Fixed := Add('fixed','HUD',nil,False,True); L := Add('child','*0',A,False,False);
    SelectExclusive(D,L); Check(A.Visible and L.Visible and not B.Visible and Fixed.Visible,'Root exclusive ancestor selection failed');
  finally D.Free; end;
  D := TArtDocument.Create; D.Width := 4; D.Height := 3;
  try
    A := nil;
    for var I := 0 to 129 do A := Add('deep-'+IntToStr(I),'*level',A,True,False);
    L := Add('too-deep','*0',A,False,False); Before := Snapshot(D,True); Rejected := False;
    try SelectExclusive(D,L); except on E: EArtFormat do Rejected := True; end;
    Check(Rejected and (Snapshot(D,True)=Before),'Depth failure partially changed visibility');
  finally D.Free; end;
end;
procedure ImportCase;
var Exchange: TArtExchange; Request,Response,Op: TJSONObject; Operations: TJSONArray;
    Directory,Digest,Before: string; Candidate: TArtDocument; Job: TArtExchangeJob; Rejected: Boolean;
begin
  Fixture; Exchange := TArtExchange.Create;
  try
    Directory := Exchange.ExportJob(D,'synthetic multi-level select_part regression',TPath.Combine(Output,'exchange'),nil,'dot');
    Request := TJSONObject.ParseJSONValue(TFile.ReadAllText(TPath.Combine(Directory,'request.json'))) as TJSONObject;
    Response := TJSONObject.Create;
    try
      for var Key in ['schemaVersion','jobId','requestId','documentId','ifRevision'] do Response.AddPair(Key,Request.GetValue(Key).Clone as TJSONValue);
      Response.AddPair('assets',TJSONArray.Create); Operations := TJSONArray.Create; Response.AddPair('operations',Operations);
      Op := TJSONObject.Create; Operations.AddElement(Op); Op.AddPair('op','select_part'); Op.AddPair('layerId','near-1');
      TFile.WriteAllText(TPath.Combine(Directory,'result.json'),Response.ToJSON,TEncoding.UTF8);
      Before := Snapshot(D,True); Candidate := Exchange.PrepareResult(D,TPath.Combine(Directory,'result.json'),Job,Digest);
      try
        Check(Candidate<>nil,'Pipe/import selection produced no candidate'); AssertDeep(Candidate);
        Check(Snapshot(D,True)=Before,'Import preparation mutated original document');
        Check((Candidate.SessionId=D.SessionId) and (Candidate.Revision=D.Revision+1),'Import revision/identity contract changed');
        SavedRoundtrip(Candidate,'import-selected.psd');
      finally Candidate.Free; end;
      // A later invalid operation must roll back the whole cloned selection batch.
      Op := TJSONObject.Create; Operations.AddElement(Op); Op.AddPair('op','select_part'); Op.AddPair('layerId','not-a-layer');
      TFile.WriteAllText(TPath.Combine(Directory,'result.json'),Response.ToJSON,TEncoding.UTF8);
      Candidate := nil; Rejected := False;
      try Candidate := Exchange.PrepareResult(D,TPath.Combine(Directory,'result.json'),Job,Digest);
      except on E: EArtFormat do Rejected := True; end;
      Candidate.Free;
      Check(Rejected and (Snapshot(D,True)=Before),'Failed later selection partially changed original document');
    finally Request.Free; Response.Free; end;
  finally Exchange.Free; D.Free; end;
end;
begin
  try
    if ParamCount<>1 then raise Exception.Create('Usage: MultilevelExclusiveSmoke NEW_OUTPUT_DIRECTORY');
    Output := TPath.GetFullPath(ParamStr(1));
    if TDirectory.Exists(Output) or TFile.Exists(Output) then raise Exception.Create('Output directory must not exist');
    ForceDirectories(Output);
    Check(ART_EXCLUSIVE_SELECTION_VERSION=2,'Wrong selection version');
    CoreCases; RootAndDepthCases; ImportCase;
    Writeln('PASS: ',Checks,' assertions; deep selection, hidden ancestors, IDLE, independent branches, import and PSD reload');
  except on E: Exception do begin Writeln(E.ClassName,': ',E.Message); Halt(1); end; end;
end.

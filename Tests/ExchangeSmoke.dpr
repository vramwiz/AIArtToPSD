program ExchangeSmoke;
{$APPTYPE CONSOLE}

uses System.Generics.Collections, System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  ArtDocument in '..\Source\Core\ArtDocument.pas',
  ArtParts in '..\Source\Core\ArtParts.pas',
  ArtLayerName in '..\Source\Core\ArtLayerName.pas',
  ArtPng in '..\Source\Persistence\PNG\ArtPng.pas',
  ArtPsd in '..\Source\Persistence\PSD\ArtPsd.pas',
  ArtExchange in '..\Source\Integrations\AIExchange\ArtExchange.pas';
var D,C: TArtDocument; E: TArtExchange; L: TArtLayer;
  Request,Response,O: TJSONObject; Ops: TJSONArray; Job: TArtExchangeJob;
  Root,Path,Digest: string; Count: Integer; Failed: Boolean;
procedure Check(B: Boolean; const S: string);
begin Inc(Count); if not B then raise Exception.Create(S); end;
procedure StartJob;
begin
  Path := E.ExportJob(D,'表情差分を作成',Root);
  Request := TJSONObject.ParseJSONValue(TFile.ReadAllText(TPath.Combine(Path,'request.json'))) as TJSONObject;
  Response := TJSONObject.Create;
  for var Key in ['schemaVersion','jobId','requestId','documentId','ifRevision'] do
    Response.AddPair(Key,Request.GetValue(Key).Clone as TJSONValue);
  Response.AddPair('assets',TJSONArray.Create);
  Ops := TJSONArray.Create; Response.AddPair('operations',Ops);
end;
procedure RenameOp(const Id,Name: string);
var O: TJSONObject;
begin O := TJSONObject.Create; O.AddPair('op','rename_layer'); O.AddPair('layerId',Id); O.AddPair('name',Name); Ops.AddElement(O); end;
procedure WriteResult;
begin TFile.WriteAllText(TPath.Combine(Path,'result.json'),Response.ToJSON,TEncoding.UTF8); end;
procedure EndJob;
begin Request.Free; Response.Free; end;
procedure ReplaceField(A: TJSONObject; const Key,Value: string);
begin A.RemovePair(Key).Free; A.AddPair(Key,Value); end;
procedure ExpectRejected(const LabelText: string);
var Before: string; Revision: UInt64;
begin
  Before := D.Roots[0].Name; Revision := D.Revision; WriteResult; Failed := False;
  try C := E.PrepareResult(D,TPath.Combine(Path,'result.json'),Job,Digest); C.Free;
  except on EArtFormat do Failed := True; end;
  Check(Failed,LabelText); Check((D.Roots[0].Name=Before) and (D.Revision=Revision),'Rejected result mutated source');
end;
procedure UseAssets;
begin Response.RemovePair('assets').Free; Response.AddPair('assets',Request.GetValue('assets').Clone as TJSONValue); end;
function Operation(const Op,Id: string): TJSONObject;
begin Result := TJSONObject.Create; Ops.AddElement(Result); Result.AddPair('op',Op); Result.AddPair('layerId',Id); end;
function HashFile(const FileName: string): string;
var S: TFileStream;
begin
  S := TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
  try Result := THashSHA2.GetHashString(S); finally S.Free; end;
end;
procedure RunAdditionalTests;
var A,G,N: TArtLayer; Asset: TJSONObject; Pixels: TBytes; Version: UInt64;
begin
  // A single transaction exercises dependent IDs, hierarchy, ordering, replacement,
  // attributes and exclusive selection together, followed by a PSD round trip.
  StartJob;
  try
    UseAssets;
    O := Operation('add_group','face'); O.AddPair('name','表情'); O.AddPair('parentId',''); O.AddPair('beforeLayerId',D.Roots[0].Id);
    O.AddPair('visible',TJSONBool.Create(True)); O.AddPair('opacity',TJSONNumber.Create(255));
    for var Id in ['neutral','smile'] do begin
      O := Operation('add_layer',Id); O.AddPair('name','*'+string(Id)); O.AddPair('parentId','face'); O.AddPair('beforeLayerId','');
      O.AddPair('visible',TJSONBool.Create(True)); O.AddPair('opacity',TJSONNumber.Create(255)); O.AddPair('assetId','source-1');
      O.AddPair('bounds',TJSONObject.ParseJSONValue('{"left":0,"top":0,"right":2,"bottom":2}'));
    end;
    O := Operation('replace_layer',D.Roots[0].Id); O.AddPair('assetId','source-1');
    O.AddPair('bounds',TJSONObject.ParseJSONValue('{"left":-1,"top":1,"right":1,"bottom":3}'));
    O := Operation('set_attributes',D.Roots[0].Id); O.AddPair('visible',TJSONBool.Create(False)); O.AddPair('opacity',TJSONNumber.Create(123));
    O := Operation('select_part','smile');
    Version := D.Revision; Pixels := RenderPsdLayers(D); WriteResult;
    C := E.PrepareResult(D,TPath.Combine(Path,'result.json'),Job,Digest);
    try
      G := C.FindLayer('face'); A := C.FindLayer('neutral'); N := C.FindLayer('smile');
      Check(C.Roots[0]=G,'beforeLayerId ordering lost'); Check(G.Children.Count=2,'Group children lost');
      Check(not A.Visible and N.Visible,'Exclusive selection failed');
      Check(C.Roots[1].Opacity=123,'Attributes lost'); Check(not C.Roots[1].Visible,'Visibility lost');
      Check((C.Roots[1].Bounds.Left=-1) and (C.Roots[1].Bounds.Top=1),'Replacement placement lost');
      Check(D.Revision=Version,'Preparation changed revision');
      Check(Length(RenderPsdLayers(C))=Length(Pixels),'Canvas changed');
      WriteNewPsd(C,TPath.Combine(Path,'all_operations.psd'),pcRle);
    finally C.Free; end;
    C := ReadPsd(TPath.Combine(Path,'all_operations.psd'));
    try Check((C.Roots.Count=2) and (C.Roots[0].Children.Count=2),'PSD hierarchy lost');
      Check(C.Roots[0].Children[1].Name='*smile','PSD name lost');
    finally C.Free; end;
  finally EndJob; end;
  for var TestCase := 0 to 10 do begin
    StartJob;
    try
      RenameOp(D.Roots[0].Id,'失敗前の変更');
      case TestCase of
        0: ReplaceField(Response,'documentId','foreign');
        1: ReplaceField(Response,'requestId','foreign');
        2: ReplaceField(Response,'jobId','foreign');
        3: Response.AddPair('jobId','duplicate');
        4: begin O := Operation('add_group',D.Roots[0].Id); O.AddPair('name','duplicate'); end;
        5: begin O := Operation('select_part','unknown'); end;
        6: begin O := Operation('set_attributes',D.Roots[0].Id); O.AddPair('visible',TJSONBool.Create(True)); O.AddPair('opacity',TJSONNumber.Create(256)); end;
        7: begin O := Operation('delete_layer',D.Roots[0].Id); end;
        8: begin O := Operation('add_group','bad-parent'); O.AddPair('name','group'); O.AddPair('parentId',D.Roots[0].Id); O.AddPair('beforeLayerId',''); end;
        9: begin O := Operation('rename_layer',D.Roots[0].Id); O.AddPair('name',''); end;
        10: begin O := Operation('replace_layer',D.Roots[0].Id); O.AddPair('assetId','missing'); end;
      end;
      ExpectRejected('Invalid metadata/operation accepted '+IntToStr(TestCase));
    finally EndJob; end;
  end;
  for var TestCase := 0 to 6 do begin
    StartJob;
    try
      UseAssets; Asset := (Response.GetValue('assets') as TJSONArray).Items[0] as TJSONObject;
      RenameOp(D.Roots[0].Id,'画像検証後');
      case TestCase of
        0: ReplaceField(Asset,'sha256',StringOfChar('0',64));
        1: ReplaceField(Asset,'path','../outside.png');
        2: ReplaceField(Asset,'path',TPath.Combine(Path,'input/source-1.png'));
        3: ReplaceField(Asset,'path','input/source-1.jpg');
        4: ReplaceField(Asset,'pixelFormat','RGB16');
        5: begin Asset.RemovePair('width').Free; Asset.AddPair('width',TJSONNumber.Create(3)); end;
        6: begin TFile.WriteAllText(TPath.Combine(Path,'input/source-1.png'),'broken PNG',TEncoding.UTF8);
             ReplaceField(Asset,'sha256',HashFile(TPath.Combine(Path,'input/source-1.png'))); end;
      end;
      ExpectRejected('Invalid asset accepted '+IntToStr(TestCase));
    finally EndJob; end;
  end;
end;

begin
  try
    if ParamCount<>1 then raise Exception.Create('Usage: ExchangeSmoke OUTPUT_DIRECTORY');
    Root := TPath.GetFullPath(ParamStr(1));
    E := TArtExchange.Create; D := TArtDocument.Create;
    try
      D.Width := 2; D.Height := 2; L := D.AddLayer(alkImage,'*元画像',TArtBounds.Create(0,0,2,2));
      SetLength(L.Pixels,16); for var I := 0 to 15 do L.Pixels[I] := 255;
      L.Pixels[4] := 40; L.Pixels[5] := 70; L.Pixels[6] := 90; L.Pixels[7] := 128;
      StartJob;
      try
        Check(FileExists(TPath.Combine(Path,'preview.png')),'Preview missing');
        Check(FileExists(TPath.Combine(Path,'input/source-1.png')),'Source PNG missing');
        RenameOp(L.Id,'*変更'); WriteResult;
        C := E.PrepareResult(D,TPath.Combine(Path,'result.json'),Job,Digest);
        Check(D.Roots[0].Name='*元画像','Preparation mutated source');
        Check(C.Roots[0].Name='*変更','Rename failed');
        Check((C.SessionId=D.SessionId) and (C.Revision=D.Revision+1),'Identity or revision lost');
        D.Free; D := C; E.CommitResult(Job,Digest);
        C := E.PrepareResult(D,TPath.Combine(Path,'result.json'),Job,Digest);
        Check(C=nil,'Repeat applied twice');
        RenameOp(D.Roots[0].Id,'別内容'); WriteResult; Failed := False;
        try C := E.PrepareResult(D,TPath.Combine(Path,'result.json'),Job,Digest); C.Free;
        except on EArtFormat do Failed := True; end;
        Check(Failed,'Changed repeat accepted');
      finally EndJob; end;
      StartJob;
      try
        RenameOp(D.Roots[0].Id,'途中変更'); RenameOp('missing','失敗'); WriteResult; Failed := False;
        try C := E.PrepareResult(D,TPath.Combine(Path,'result.json'),Job,Digest); C.Free;
        except on EArtFormat do Failed := True; end;
        Check(Failed,'Invalid batch accepted'); Check(D.Roots[0].Name='*変更','Failed batch mutated source');
      finally EndJob; end;
      StartJob;
      try
        RenameOp(D.Roots[0].Id,'古い結果'); WriteResult; D.Changed; Failed := False;
        try C := E.PrepareResult(D,TPath.Combine(Path,'result.json'),Job,Digest); C.Free;
        except on EArtFormat do Failed := True; end;
        Check(Failed,'Stale result accepted');
      finally EndJob; end;
      StartJob;
      try
        Response.RemovePair('assets').Free;
        Response.AddPair('assets',Request.GetValue('assets').Clone as TJSONValue);
        O := TJSONObject.Create; Ops.AddElement(O);
        O.AddPair('op','add_layer'); O.AddPair('layerId','generated'); O.AddPair('name','*追加');
        O.AddPair('parentId',''); O.AddPair('beforeLayerId',''); O.AddPair('visible',TJSONBool.Create(True));
        O.AddPair('opacity',TJSONNumber.Create(255)); O.AddPair('assetId','source-1');
        O.AddPair('bounds',TJSONObject.ParseJSONValue('{"left":0,"top":0,"right":2,"bottom":2}'));
        WriteResult; C := E.PrepareResult(D,TPath.Combine(Path,'result.json'),Job,Digest);
        try
          Check(C.Roots.Count=2,'PNG layer not added');
          Check(C.FindLayer('generated').Pixels[0]=255,'PNG pixels lost');
          Check((C.FindLayer('generated').Pixels[4]=40) and (C.FindLayer('generated').Pixels[7]=128),'PNG color or alpha lost');
          WriteNewPsd(C,TPath.Combine(Path,'roundtrip.psd'));
        finally C.Free; end;
        C := ReadPsd(TPath.Combine(Path,'roundtrip.psd'));
        try Check(C.Roots.Count=2,'PSD save lost added layer'); finally C.Free; end;

      finally EndJob; end;
      RunAdditionalTests;
      L := D.Roots[0]; L.HasMask := True; L.MaskBounds := TArtBounds.Create(0,0,2,2);
      L.MaskDefault := 255; L.MaskPixels := TBytes.Create(255,128,0,255);
      StartJob;
      try
        UseAssets; O := Operation('replace_layer',L.Id); O.AddPair('assetId','source-1');
        O.AddPair('bounds',TJSONObject.ParseJSONValue('{"left":3,"top":4,"right":5,"bottom":6}'));
        WriteResult; C := E.PrepareResult(D,TPath.Combine(Path,'result.json'),Job,Digest);
        try
          Check(C.Roots[0].HasMask,'Replacement dropped mask');
          Check((C.Roots[0].MaskBounds.Left=3) and (C.Roots[0].MaskBounds.Top=4),'Replacement failed to move mask');
          Check((C.Roots[0].MaskPixels[1]=128) and (D.Roots[0].MaskBounds.Left=0),'Replacement mutated mask source');
          WriteNewPsd(C,TPath.Combine(Path,'mask_replaced.psd'),pcRle);
        finally C.Free; end;
        E.ClearJobs; ExpectRejected('Cleared job still accepted');
      finally EndJob; end;
      Writeln('PASS: ',Count,' exchange assertions');
    finally D.Free; E.Free; end;
  except on X: Exception do begin Writeln(X.ClassName,': ',X.Message); Halt(1); end; end;
end.


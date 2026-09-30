program PsdRoundTrip;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.NetEncoding,
  System.Generics.Collections,
  ArtDocument in '..\Source\Core\ArtDocument.pas',
  ArtPsd in '..\Source\Persistence\PSD\ArtPsd.pas';

var OutputDir, SampleDir: string; Assertions: Integer;

procedure Check(Value: Boolean; const MessageText: string);
begin
  Inc(Assertions);
  if not Value then raise Exception.Create(MessageText);
end;

procedure FillPixels(L: TArtLayer);
var I, C: Integer;
begin
  SetLength(L.Pixels, PixelByteCount(L.Bounds.Width,L.Bounds.Height,4));
  for I := 0 to Length(L.Pixels) div 4-1 do begin
    for C := 0 to 2 do L.Pixels[I*4+C] := Byte((I*31+C*73) mod 256);
    L.Pixels[I*4+3] := Byte((I mod 5)*63);
  end;
end;

function MakeDocument(Nested: Boolean): TArtDocument;
var L, G, G2: TArtLayer;
begin
  Result := TArtDocument.Create;
  Result.Width := 7; Result.Height := 5;
  if not Nested then begin
    L := Result.AddLayer(alkImage,'単独😀',TArtBounds.Create(0,0,7,5)); FillPixels(L);
  end else begin
    L := Result.AddLayer(alkImage,'前景・半透明',TArtBounds.Create(-1,-1,3,2));
    FillPixels(L); L.Opacity := 128;
    G := Result.AddLayer(alkGroup,'!顔',TArtBounds.Create(0,0,0,0)); G.SectionType := 2;
    G2 := Result.AddLayer(alkGroup,'*通常',TArtBounds.Create(0,0,0,0),G);
    L := Result.AddLayer(alkImage,'口😀',TArtBounds.Create(2,1,5,4),G2); FillPixels(L);
    L := Result.AddLayer(alkImage,'非表示',TArtBounds.Create(1,0,4,3),G); FillPixels(L); L.Visible := False;
    Result.AddLayer(alkGroup,'空グループ',TArtBounds.Create(0,0,0,0),G);
    L := Result.AddLayer(alkImage,'後景',TArtBounds.Create(0,0,7,5)); FillPixels(L);
  end;
end;

function LayerJson(L: TArtLayer): TJSONObject;
var B, Children: TJSONArray; Child: TArtLayer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name',L.Name);
  Result.AddPair('kind',TJSONNumber.Create(Ord(L.Kind)));
  Result.AddPair('visible',TJSONBool.Create(L.Visible));
  Result.AddPair('opacity',TJSONNumber.Create(L.Opacity));
  B := TJSONArray.Create;
  B.Add(L.Bounds.Left); B.Add(L.Bounds.Top); B.Add(L.Bounds.Right); B.Add(L.Bounds.Bottom);
  Result.AddPair('bounds',B);
  Result.AddPair('has_mask',TJSONBool.Create(L.HasMask));
  if L.HasMask then begin
    B := TJSONArray.Create;
    B.Add(L.MaskBounds.Left); B.Add(L.MaskBounds.Top); B.Add(L.MaskBounds.Right); B.Add(L.MaskBounds.Bottom);
    Result.AddPair('mask_bounds',B);
    Result.AddPair('mask_default',TJSONNumber.Create(L.MaskDefault));
    Result.AddPair('mask_disabled',TJSONBool.Create(L.MaskDisabled));
    Result.AddPair('mask_invert',TJSONBool.Create(L.MaskInvert));
    Result.AddPair('mask_pixels_base64',TNetEncoding.Base64.EncodeBytesToString(L.MaskPixels));
  end;
  Result.AddPair('pixels_base64',TNetEncoding.Base64.EncodeBytesToString(L.Pixels));
  Children := TJSONArray.Create;
  for Child in L.Children do Children.AddElement(LayerJson(Child));
  Result.AddPair('children',Children);
end;

function DocumentJson(D: TArtDocument; const FileName: string): TJSONObject;
var L: TArtLayer; Layers: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file',FileName);
  Result.AddPair('width',TJSONNumber.Create(D.Width));
  Result.AddPair('height',TJSONNumber.Create(D.Height));
  Result.AddPair('render_rgba_base64',TNetEncoding.Base64.EncodeBytesToString(D.RenderRGBA));
  Layers := TJSONArray.Create;
  for L in D.Roots do Layers.AddElement(LayerJson(L));
  Result.AddPair('layers',Layers);
end;

procedure CompareLayers(A, B: TList<TArtLayer>);
var I: Integer; L, R: TArtLayer;
begin
  Check(A.Count=B.Count,'Layer count mismatch');
  for I := 0 to A.Count-1 do begin
    L := A[I]; R := B[I];
    Check(L.Name=R.Name,'Unicode layer name mismatch');
    Check(L.Kind=R.Kind,'Layer kind mismatch');
    Check(L.HasMask=R.HasMask,'Mask presence mismatch');
    if L.HasMask then begin
      Check(CompareMem(@L.MaskBounds,@R.MaskBounds,SizeOf(TArtBounds)),'Mask bounds mismatch');
      Check((L.MaskDefault=R.MaskDefault) and (L.MaskDisabled=R.MaskDisabled) and
        (L.MaskInvert=R.MaskInvert),'Mask attributes mismatch');
      Check(Length(L.MaskPixels)=Length(R.MaskPixels),'Mask pixel size mismatch');
      if Length(L.MaskPixels)>0 then Check(CompareMem(@L.MaskPixels[0],@R.MaskPixels[0],Length(L.MaskPixels)),
        'Mask pixels mismatch');
    end;
    if L.Kind=alkImage then begin
      Check(CompareMem(@L.Bounds,@R.Bounds,SizeOf(TArtBounds)),'Layer bounds mismatch');
      Check(Length(L.Pixels)=Length(R.Pixels),'Pixel length mismatch');
      if Length(L.Pixels)>0 then Check(CompareMem(@L.Pixels[0],@R.Pixels[0],Length(L.Pixels)),'Layer pixels mismatch');
    end;
    Check((L.Visible=R.Visible) and (L.Opacity=R.Opacity),'Layer properties mismatch');
    CompareLayers(L.Children,R.Children);
  end;
end;

procedure TestGenerated(Manifest: TJSONArray; Nested: Boolean; const Name: string; Compression: TPsdCompression = pcRaw);
var D, R: TArtDocument; FileName: string;
begin
  D := MakeDocument(Nested);
  try
    FileName := TPath.Combine(OutputDir,Name);
    WriteNewPsd(D,FileName,Compression);
    R := ReadPsd(FileName);
    try
      Check((R.Width=D.Width) and (R.Height=D.Height),'Canvas mismatch');
      Check(R.MergedHasTransparency,'Merged transparency flag lost');
      CompareLayers(D.Roots,R.Roots);
      Manifest.AddElement(DocumentJson(D,Name));
    finally R.Free; end;
  finally D.Free; end;
end;

procedure TestSamples;
const Names: array[0..6] of string = ('layer_test.psd','sample.psd','sampleyh.psd',
  'sampleyh63.psd','sampleyh63x255.psd','sample_alpha.psd','aiueo.psd');
  Counts: array[0..6] of Integer = (0,1,1,1,1,4,24);
var I: Integer; D: TArtDocument; A,B: TBytes; Saved: string;
begin
  for I := 0 to High(Names) do begin
    D := ReadPsd(TPath.Combine(SampleDir,Names[I]));
    try
      Check(D.SourceRecordCount=Counts[I],'Sample record count: '+Names[I]);
      Saved := TPath.Combine(OutputDir,'preserved_'+Names[I]);
      SaveUnchangedPsd(D,Saved);
      A := TFile.ReadAllBytes(TPath.Combine(SampleDir,Names[I])); B := TFile.ReadAllBytes(Saved);
      Check((Length(A)=Length(B)) and CompareMem(@A[0],@B[0],Length(A)),'Archive not byte identical');
      if I=1 then begin
        Check(D.Roots.Count=1,'Single sample layer omitted');
        Check(D.Roots[0].Bounds.Left=35,'Sample coordinate mismatch');
      end;
      if I=6 then begin
        Check((D.Roots.Count=3) and (D.Roots[0].Name='!eye'),'aiueo root hierarchy mismatch');
        Check((D.Roots[0].Children[0].Name='*1') and
          (D.Roots[0].Children[0].Children.Count=2),'aiueo nested hierarchy mismatch');
      end;
    finally D.Free; end;
  end;
end;

procedure TestRleEdges;
var D,R: TArtDocument; L: TArtLayer; I,C: Integer; RawName,RleName: string; Raised: Boolean; Bytes: TBytes;
begin
  D := TArtDocument.Create;
  try
    D.Width := 513; D.Height := 3;
    L := D.AddLayer(alkImage,'PackBits boundaries',TArtBounds.Create(0,0,513,3));
    SetLength(L.Pixels,513*3*4);
    for I := 0 to 513*3-1 do
      for C := 0 to 3 do begin
        if I div 513 = 0 then L.Pixels[I*4+C] := 17
        else if I div 513 = 1 then L.Pixels[I*4+C] := Byte(I mod 256)
        else L.Pixels[I*4+C] := Byte((I div 2) mod 256);
      end;
    RawName := TPath.Combine(OutputDir,'edges_raw.psd');
    RleName := TPath.Combine(OutputDir,'edges_rle.psd');
    WriteNewPsd(D,RawName,pcRaw); WriteNewPsd(D,RleName,pcRle);
    R := ReadPsd(RleName);
    try
      CompareLayers(D.Roots,R.Roots);
      SaveUnchangedPsd(R,TPath.Combine(OutputDir,'edges_preserved.psd'));
      R.Roots[0].Pixels[0] := R.Roots[0].Pixels[0] xor 1;
      Raised := False;
      try SaveUnchangedPsd(R,TPath.Combine(OutputDir,'edges_preserved.psd'));
      except on E: EArtFormat do Raised := True; end;
      Check(Raised,'Changed pixels silently archived');
      Bytes := TFile.ReadAllBytes(TPath.Combine(OutputDir,'edges_preserved.psd'));
      Check((Length(Bytes)=Length(R.SourceBytes)) and CompareMem(@Bytes[0],@R.SourceBytes[0],Length(Bytes)),
        'Rejected edit damaged output');
      R.Roots[0].Pixels[0] := R.Roots[0].Pixels[0] xor 1;
      R.Roots[0].Name := 'changed'; Raised := False;
      try SaveUnchangedPsd(R,TPath.Combine(OutputDir,'edges_preserved.psd'));
      except on E: EArtFormat do Raised := True; end;
      Check(Raised,'Changed name silently archived');
    finally R.Free; end;
    R := ReadPsd(RawName);
    try
      Bytes := TFile.ReadAllBytes(RleName);
      Check(Length(Bytes)<Length(R.SourceBytes),'Repeated rows did not compress');
    finally R.Free; end;
  finally D.Free; end;
end;

function ResourceFixture(const Data: TBytes; ResourceId: Word): TBytes;
const Resource: array[0..27] of Byte = ($38,$42,$49,$4D,$03,$ED,0,0,0,0,0,$10,
  0,$48,0,0,0,1,0,1,0,$48,0,0,0,1,0,1);
var I: Integer;
begin
  // Generated fixtures have empty color mode and resources: resource length at 30.
  SetLength(Result,Length(Data)+Length(Resource));
  Move(Data[0],Result[0],34); Result[33] := Length(Resource);
  for I := 0 to High(Resource) do Result[34+I] := Resource[I];
  Result[38] := Byte(ResourceId shr 8); Result[39] := Byte(ResourceId and $FF);
  Move(Data[34],Result[34+Length(Resource)],Length(Data)-34);
end;

procedure TestEdited(Manifest: TJSONArray);
var D,R,Fresh: TArtDocument; Input,Name: string; Data,Before: TBytes; Raised: Boolean;
    L: TArtLayer; Mode,I: Integer;
begin
  Input := TPath.Combine(OutputDir,'edit_source.psd');
  Data := ResourceFixture(TFile.ReadAllBytes(TPath.Combine(OutputDir,'nested.psd')),1005);
  // Preserve an otherwise uninterpreted flag bit and non-sequential layer IDs.
  Data[124] := Data[124] or 1; // First four-channel record flags in this fixed fixture layout.
  for I := 0 to Length(Data)-16 do
    if (Data[I]=$38) and (Data[I+1]=$42) and (Data[I+2]=$49) and (Data[I+3]=$4D) and
      (Data[I+4]=$6C) and (Data[I+5]=$79) and (Data[I+6]=$69) and (Data[I+7]=$64) then
      Data[I+15] := Data[I+15]+40;
  TFile.WriteAllBytes(Input,Data);
  D := ReadPsd(Input); Fresh := MakeDocument(True);
  try
    D.Roots[0].Name := '編集後の長い名前😀'; Fresh.Roots[0].Name := D.Roots[0].Name;
    D.Roots[0].Opacity := 73; Fresh.Roots[0].Opacity := 73;
    D.Roots[0].Bounds := TArtBounds.Create(-2,0,2,3); Fresh.Roots[0].Bounds := D.Roots[0].Bounds;
    D.Roots[0].Pixels[0] := 229; Fresh.Roots[0].Pixels[0] := 229;
    D.Roots[1].Name := '!編集済み'; Fresh.Roots[1].Name := D.Roots[1].Name;
    D.Roots[1].Children[1].Visible := True; Fresh.Roots[1].Children[1].Visible := True;
    L := D.Roots[1].Children[0].Children[0];
    L.Bounds := TArtBounds.Create(0,0,2,2); FillPixels(L);
    L := Fresh.Roots[1].Children[0].Children[0];
    L.Bounds := TArtBounds.Create(0,0,2,2); FillPixels(L);
    Before := Copy(D.SourceBytes);
    for Mode := 0 to 1 do begin
      if Mode=0 then Name := 'edited_raw.psd' else Name := 'edited_rle.psd';
      SaveEditedPsd(D,TPath.Combine(OutputDir,Name),TPsdCompression(Mode));
      R := ReadPsd(TPath.Combine(OutputDir,Name));
      try
        CompareLayers(D.Roots,R.Roots);
        Check((R.SourceRecordCount=D.SourceRecordCount) and R.MergedHasTransparency,'Edited structure flags');
        Check(CompareMem(@R.SourceBytes[34],@Before[34],28),'Resolution resource changed');
        SaveUnchangedPsd(R,TPath.Combine(OutputDir,'edited_copy.psd'));
        Manifest.AddElement(DocumentJson(Fresh,Name));
      finally R.Free; end;
    end;
    Check((Length(D.SourceBytes)=Length(Before)) and CompareMem(@D.SourceBytes[0],@Before[0],Length(Before)),
      'Edited save changed source archive');
    Name := TPath.Combine(OutputDir,'edit_protected.fixture');
    TFile.WriteAllBytes(Name,TBytes.Create(11,22,33));
    D.Roots.Exchange(0,2); Raised := False;
    try SaveEditedPsd(D,Name); except on E: EArtFormat do Raised := True; end;
    Check(Raised,'Reordered tree accepted'); D.Roots.Exchange(0,2);
    D.Roots[0].BlendKey := 'mul '; Raised := False;
    try SaveEditedPsd(D,Name); except on E: EArtFormat do Raised := True; end;
    Check(Raised,'Changed blend accepted'); D.Roots[0].BlendKey := 'norm';
    D.Width := D.Width+1; Raised := False;
    try SaveEditedPsd(D,Name); except on E: EArtFormat do Raised := True; end;
    Check(Raised,'Changed canvas accepted'); D.Width := D.Width-1;
    D.MergedPlanes[0][0] := D.MergedPlanes[0][0] xor 1; Raised := False;
    try SaveEditedPsd(D,Name); except on E: EArtFormat do Raised := True; end;
    Check(Raised,'Modified derived composite accepted');
    D.MergedPlanes[0][0] := D.MergedPlanes[0][0] xor 1;
    D.Roots[1].Children.Add(D.Roots[1]); Raised := False;
    try SaveEditedPsd(D,Name); except on E: EArtFormat do Raised := True; end;
    Check(Raised,'Cyclic group accepted'); D.Roots[1].Children.Delete(D.Roots[1].Children.Count-1);
    Data := TFile.ReadAllBytes(Name);
    Check((Length(Data)=3) and (Data[0]=11) and (Data[2]=33),'Rejected edit damaged destination');
  finally D.Free; Fresh.Free; end;
  Data := ResourceFixture(TFile.ReadAllBytes(TPath.Combine(OutputDir,'nested.psd')),1039);
  Input := TPath.Combine(OutputDir,'edit_blocked_source.psd');
  TFile.WriteAllBytes(Input,Data); D := ReadPsd(Input);
  try
    D.Roots[0].Name := 'blocked'; Raised := False;
    try SaveEditedPsd(D,Name); except on E: EArtFormat do Raised := True; end;
    Check(Raised,'Unimplemented ICC resource allowed');
  finally D.Free; end;
  Data := TFile.ReadAllBytes(TPath.Combine(OutputDir,'nested.psd'));
  for I := 0 to Length(Data)-16 do
    if (Data[I]=$38) and (Data[I+1]=$42) and (Data[I+2]=$49) and (Data[I+3]=$4D) and
      (Data[I+4]=$6C) and (Data[I+5]=$79) and (Data[I+6]=$69) and (Data[I+7]=$64) then begin
      Data[I+4] := $78; Data[I+5] := $78; Data[I+6] := $78; Data[I+7] := $78; Break;
    end;
  TFile.WriteAllBytes(Input,Data); D := ReadPsd(Input);
  try
    D.Roots[0].Name := 'unknown tag'; Raised := False;
    try SaveEditedPsd(D,Name); except on E: EArtFormat do Raised := True; end;
    Check(Raised,'Unknown dependent tag allowed');
    Data := TFile.ReadAllBytes(Name);
    Check((Length(Data)=3) and (Data[0]=11) and (Data[2]=33),'Metadata rejection damaged destination');
  finally D.Free; end;

end;

procedure TestMasks(Manifest: TJSONArray);
const NormalAlpha: array[0..9] of Byte = (0,25,50,100,0,100,50,0,100,0);
  InvertedAlpha: array[0..9] of Byte = (100,75,50,0,0,0,50,100,0,0);
var D,R: TArtDocument; L: TArtLayer; Pixels,Data,Protected: TBytes;
    I,Mode: Integer; Name,Source,Destination: string; Raised: Boolean;
begin
  D := TArtDocument.Create;
  try
    D.Width := 5; D.Height := 2;
    L := D.AddLayer(alkImage,'マスク画像',TArtBounds.Create(-1,0,4,2));
    SetLength(L.Pixels,5*2*4);
    for I := 0 to 9 do begin L.Pixels[I*4] := 200; L.Pixels[I*4+1] := 80;
      L.Pixels[I*4+2] := 30; L.Pixels[I*4+3] := 200; end;
    L.Opacity := 128; L.HasMask := True; L.MaskBounds := TArtBounds.Create(0,0,3,2);
    L.MaskDefault := 255; L.MaskPixels := TBytes.Create(0,64,128,255,128,0);
    Pixels := D.RenderRGBA;
    for I := 0 to 9 do Check(Pixels[I*4+3]=NormalAlpha[I],'Analytic mask alpha');
    L.MaskInvert := True; Pixels := D.RenderRGBA;
    for I := 0 to 9 do Check(Pixels[I*4+3]=InvertedAlpha[I],'Analytic inverted mask alpha');
    L.MaskInvert := False; L.MaskDisabled := True; Pixels := D.RenderRGBA;
    for I := 0 to 9 do
      if I mod 5=4 then Check(Pixels[I*4+3]=0,'Outside image bounds')
      else Check(Pixels[I*4+3]=100,'Disabled mask should not attenuate');
    L.MaskDisabled := False;
    for Mode := 0 to 1 do begin
      if Mode=0 then Name := 'mask_raw.psd' else Name := 'mask_rle.psd';
      Source := TPath.Combine(OutputDir,Name); WriteNewPsd(D,Source,TPsdCompression(Mode));
      Manifest.AddElement(DocumentJson(D,Name)); R := ReadPsd(Source);
      try
        CompareLayers(D.Roots,R.Roots);
        Check(R.Unsupported.Count=0,'Supported mask marked unsupported');
        SaveUnchangedPsd(R,TPath.Combine(OutputDir,'mask_copy.psd'));
        R.Roots[0].MaskPixels[1] := 201;
        R.Roots[0].MaskBounds := TArtBounds.Create(-1,0,2,2);
        R.Roots[0].MaskDefault := 0; R.Roots[0].MaskInvert := True;
        L.MaskPixels[1] := 201; L.MaskBounds := R.Roots[0].MaskBounds;
        L.MaskDefault := 0; L.MaskInvert := True;
        if Mode=0 then Name := 'mask_edited_raw.psd' else Name := 'mask_edited_rle.psd';
        SaveEditedPsd(R,TPath.Combine(OutputDir,Name),TPsdCompression(Mode));
        Manifest.AddElement(DocumentJson(D,Name));
        L.MaskPixels[1] := 64; L.MaskBounds := TArtBounds.Create(0,0,3,2);
        L.MaskDefault := 255; L.MaskInvert := False;
        R.Roots[0].MaskPixels := nil; Raised := False;
        Destination := TPath.Combine(OutputDir,'mask_protected.fixture');
        TFile.WriteAllBytes(Destination,TBytes.Create(7,8,9));
        try SaveEditedPsd(R,Destination); except on E: EArtFormat do Raised := True; end;
        Check(Raised,'Invalid mask pixels accepted');
        Protected := TFile.ReadAllBytes(Destination);
        Check((Length(Protected)=3) and (Protected[0]=7),'Invalid mask save damaged destination');
      finally R.Free; end;
    end;
    // A relative-position flag cannot silently use absolute-coordinate rendering.
    Data := TFile.ReadAllBytes(TPath.Combine(OutputDir,'mask_raw.psd'));
    Data[129] := Data[129] or 1;
    Source := TPath.Combine(OutputDir,'mask_relative.fixture'); TFile.WriteAllBytes(Source,Data);
    R := ReadPsd(Source);
    try
      Check(R.Unsupported.Count>0,'Relative mask flags accepted as supported');
      Raised := False;
      try SaveEditedPsd(R,Destination); except on E: EArtFormat do Raised := True; end;
      Check(Raised,'Relative mask edited save accepted');
      SaveUnchangedPsd(R,TPath.Combine(OutputDir,'mask_relative_copy.psd'));
    finally R.Free; end;
  finally D.Free; end;
end;

procedure TestRealMasks;
var D: TArtDocument; Entries: TJSONArray; E: TJSONObject; B: TJSONArray;
    Count: Integer; Name,Source: string;
  procedure Visit(List: TList<TArtLayer>);
  var L: TArtLayer;
  begin
    for L in List do begin
      if L.HasMask and (L.Kind=alkImage) then begin
        Inc(Count); Check(Length(L.MaskPixels)=PixelByteCount(L.MaskBounds.Width,L.MaskBounds.Height,1),
          'Real mask size mismatch');
        Name := Format('real_mask_%d.bin',[L.SourceIndex]);
        TFile.WriteAllBytes(TPath.Combine(OutputDir,Name),L.MaskPixels);
        E := TJSONObject.Create; E.AddPair('file',Name);
        E.AddPair('source_index',TJSONNumber.Create(L.SourceIndex));
        B := TJSONArray.Create; B.Add(L.MaskBounds.Left); B.Add(L.MaskBounds.Top);
        B.Add(L.MaskBounds.Right); B.Add(L.MaskBounds.Bottom); E.AddPair('bounds',B);
        E.AddPair('default',TJSONNumber.Create(L.MaskDefault));
        Entries.AddElement(E);
      end;
      Visit(L.Children);
    end;
  end;
var Report: TJSONObject;
begin
  Source := TPath.Combine(SampleDir,'むにさが\東北きりたん_立ち絵素材.psd');
  D := ReadPsd(Source); Entries := TJSONArray.Create; Report := TJSONObject.Create;
  try
    Count := 0; Visit(D.Roots); Check(Count=24,'Real sample image mask count');
    Report.AddPair('source',Source); Report.AddPair('masks',Entries); Entries := nil;
    TFile.WriteAllText(TPath.Combine(OutputDir,'real_masks.json'),Report.ToJSON,TEncoding.UTF8);
  finally Entries.Free; Report.Free; D.Free; end;
end;

procedure TestFailurePreservation;
var D, Before: TArtDocument; Data, Original: TBytes; I: Integer; Raised: Boolean;
    BadName, SaveName: string;
begin
  D := MakeDocument(False); Before := D;
  Original := TFile.ReadAllBytes(TPath.Combine(OutputDir,'single.psd'));
  BadName := TPath.Combine(OutputDir,'invalid.fixture');
  try
    for I := 0 to 4 do begin
      Data := Copy(Original);
      case I of
        0: SetLength(Data,Length(Data)-1);
        1: Data[0] := 0;
        2: Data[5] := 2;
        3: Data[23] := 16;
        4: begin Data[26]:=$FF; Data[27]:=$FF; Data[28]:=$FF; Data[29]:=$FF; end;
      end;
      TFile.WriteAllBytes(BadName,Data); Raised := False;
      try LoadPsd(D,BadName); except on E: EArtFormat do Raised := True; end;
      Check(Raised,'Malformed PSD accepted');
      Check(D=Before,'Failed load replaced active document');
      Check(D.Roots[0].Name='単独😀','Failed load changed active data');
    end;
    SaveName := TPath.Combine(OutputDir,'protected.fixture');
    TFile.WriteAllBytes(SaveName,TBytes.Create(1,2,3));
    D.Roots[0].BlendKey := 'mul '; Raised := False;
    try WriteNewPsd(D,SaveName); except on E: EArtFormat do Raised := True; end;
    Check(Raised,'Unsupported rendering saved');
    Data := TFile.ReadAllBytes(SaveName);
    Check((Length(Data)=3) and (Data[0]=1) and (Data[2]=3),'Failed save damaged destination');
    D.Roots[0].BlendKey := 'norm';
    D.Roots[0].Children.Add(D.Roots[0]); Raised := False;
    try WriteNewPsd(D,SaveName); except on E: EArtFormat do Raised := True; end;
    Check(Raised,'Invalid tree accepted');
    D.Roots[0].Children.Clear;
  finally D.Free; end;
end;

var Manifest: TJSONArray;
begin
  try
    if ParamCount<>2 then raise Exception.Create('Usage: PsdRoundTrip SAMPLE_DIRECTORY OUTPUT_DIRECTORY');
    SampleDir := ParamStr(1); OutputDir := TPath.GetFullPath(ParamStr(2));
    if SameText(TPath.GetFullPath(SampleDir),OutputDir) then raise Exception.Create('Output must be separate from samples');
    ForceDirectories(OutputDir);
    Manifest := TJSONArray.Create;
    try
      TestGenerated(Manifest,False,'single.psd');
      TestGenerated(Manifest,True,'nested.psd');
      TestGenerated(Manifest,False,'single_rle.psd',pcRle);
      TestGenerated(Manifest,True,'nested_rle.psd',pcRle);
      TestRleEdges; TestSamples; TestFailurePreservation; TestEdited(Manifest); TestMasks(Manifest); TestRealMasks;
      TFile.WriteAllText(TPath.Combine(OutputDir,'expected.json'),Manifest.ToJSON,TEncoding.UTF8);
    finally Manifest.Free; end;
    Writeln('PASS: ',Assertions,' assertions; generated PSDs and 7 original samples checked.');
  except
    on E: Exception do begin Writeln(E.ClassName,': ',E.Message); Halt(1); end;
  end;
end.

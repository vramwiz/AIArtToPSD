program PsdCompatibilitySmoke;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.IOUtils,
  ArtDocument in '..\Source\Core\ArtDocument.pas',
  ArtPsd in '..\Source\Persistence\PSD\ArtPsd.pas';

var OutputDir: string; Assertions: Integer;

procedure Check(Value: Boolean; const Text: string);
begin
  Inc(Assertions);
  if not Value then raise Exception.Create(Text);
end;

function Output(const Name: string): string;
begin Result := TPath.Combine(OutputDir,Name); end;

procedure CheckSameTree(A,B: TArtLayer);
var I: Integer;
begin
  Check((A.Kind=B.Kind) and (A.Name=B.Name) and
    (A.Visible=B.Visible) and (A.Opacity=B.Opacity) and
    (A.BlendKey=B.BlendKey) and (A.SectionType=B.SectionType) and
    CompareMem(@A.Bounds,@B.Bounds,SizeOf(TArtBounds)), 'Layer metadata changed');
  Check(Length(A.Pixels)=Length(B.Pixels),'Pixel length changed');
  if Length(A.Pixels)>0 then
    Check(CompareMem(@A.Pixels[0],@B.Pixels[0],Length(A.Pixels)),'Layer pixels changed');
  Check(A.Children.Count=B.Children.Count,'Hierarchy changed');
  for I := 0 to A.Children.Count-1 do CheckSameTree(A.Children[I],B.Children[I]);
end;

procedure CheckSaved(D: TArtDocument; const Name: string);
var Saved: TArtDocument; I: Integer; A,B: TBytes;
begin
  Saved := ReadPsd(Output(Name));
  try
    Check((D.Width=Saved.Width) and (D.Height=Saved.Height),'Canvas changed');
    Check(D.Roots.Count=Saved.Roots.Count,'Root count changed');
    for I := 0 to D.Roots.Count-1 do CheckSameTree(D.Roots[I],Saved.Roots[I]);
    A := RenderPsdLayers(D); B := RenderPsdLayers(Saved);
    Check((Length(A)=Length(B)) and CompareMem(@A[0],@B[0],Length(A)), 'Composite changed');
  finally Saved.Free; end;
end;

procedure TestGenerated;
var D: TArtDocument; G,N,L: TArtLayer; Compression: TPsdCompression; Name: string;
begin
  D := TArtDocument.Create;
  try
    D.Width := 7; D.Height := 5;
    G := D.AddLayer(alkGroup,'Folder',TArtBounds.Create(0,0,0,0));
    N := D.AddLayer(alkGroup,'Nested',TArtBounds.Create(0,0,0,0),G);
    L := D.AddLayer(alkImage,'Pixels',TArtBounds.Create(1,2,3,4),N);
    L.Pixels := TBytes.Create(20,30,40,255,70,80,90,128,1,2,3,0,255,0,0,255);
    D.AddLayer(alkGroup,'Empty',TArtBounds.Create(0,0,0,0),G);
    for Compression := Low(TPsdCompression) to High(TPsdCompression) do begin
      Name := 'new_'+IntToStr(Ord(Compression))+'.psd';
      WriteNewPsd(D,Output(Name),Compression); CheckSaved(D,Name);
    end;
  finally D.Free; end;
  D := ReadPsd(Output('new_1.psd'));
  try
    SaveUnchangedPsd(D,Output('unchanged.psd')); CheckSaved(D,'unchanged.psd');
    D.Roots[0].Name := 'Renamed'; D.Roots[0].Visible := False;
    SaveLayerPropertiesPsd(D,Output('properties.psd')); CheckSaved(D,'properties.psd');
    D.Roots[0].Children[0].Children[0].Pixels[0] := 44;
    SaveEditedPsd(D,Output('edited.psd')); CheckSaved(D,'edited.psd');
    L := D.AddLayer(alkImage,'Inserted',TArtBounds.Create(0,0,1,1));
    L.Pixels := TBytes.Create(0,255,0,255);
    SaveImageCompositionPsd(D,Output('composition.psd')); CheckSaved(D,'composition.psd');
  finally D.Free; end;
end;

procedure TestLegacy(const Source: string);
var D: TArtDocument;
begin
  D := ReadPsd(Source);
  try
    SaveUnchangedPsd(D,Output('legacy_unchanged.psd')); CheckSaved(D,'legacy_unchanged.psd');
    D.Roots[0].Name := D.Roots[0].Name+'_renamed';
    SaveLayerPropertiesPsd(D,Output('legacy_properties.psd')); CheckSaved(D,'legacy_properties.psd');
    SaveImageCompositionPsd(D,Output('legacy_composition.psd')); CheckSaved(D,'legacy_composition.psd');
  finally D.Free; end;
end;

begin
  try
    if ParamCount<>2 then raise Exception.Create('Usage: PsdCompatibilitySmoke OUTPUT_DIRECTORY LEGACY_PSD');
    OutputDir := TPath.GetFullPath(ParamStr(1)); ForceDirectories(OutputDir);
    TestGenerated; TestLegacy(ParamStr(2));
    Writeln('PASS: ',Assertions,' assertions; all PSD save paths and legacy folders checked.');
  except on E: Exception do begin Writeln(E.ClassName,': ',E.Message); Halt(1); end; end;
end.

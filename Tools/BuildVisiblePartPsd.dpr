program BuildVisiblePartPsd;
{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils,
  ArtDocument in '..\Source\Core\ArtDocument.pas',
  ArtPng in '..\Source\Persistence\PNG\ArtPng.pas',
  ArtPsd in '..\Source\Persistence\PSD\ArtPsd.pas';

var
  Document, Reloaded: TArtDocument;
  Original, Part, Remainder: TArtPngData;
  Layer: TArtLayer;
  Rendered, RoundTrip: TBytes;
  OutputPath: string;
  VisibleDifferences, AlphaDifferences: Integer;

procedure AddImage(const Name: string; const Image: TArtPngData;
  Visible: Boolean);
begin
  if (Image.Width <> Original.Width) or (Image.Height <> Original.Height) then
    raise Exception.Create('Layer canvas dimensions differ from source');
  Layer := Document.AddLayer(alkImage, Name,
    TArtBounds.Create(0, 0, Image.Width, Image.Height));
  Layer.Pixels := Image.Pixels;
  Layer.Visible := Visible;
end;

procedure CheckPixels(const Actual: TBytes);
begin
  VisibleDifferences := 0;
  AlphaDifferences := 0;
  if Length(Actual) <> Length(Original.Pixels) then
    raise Exception.Create('Composite size differs from source');
  for var P := 0 to Length(Actual) div 4 - 1 do begin
    if Actual[P * 4 + 3] <> Original.Pixels[P * 4 + 3] then
      Inc(AlphaDifferences);
    if Original.Pixels[P * 4 + 3] <> 0 then
      for var C := 0 to 3 do
        if Actual[P * 4 + C] <> Original.Pixels[P * 4 + C] then begin
          Inc(VisibleDifferences);
          Break;
        end;
  end;
  if (VisibleDifferences <> 0) or (AlphaDifferences <> 0) then
    raise Exception.CreateFmt('Composite mismatch: visible=%d alpha=%d',
      [VisibleDifferences, AlphaDifferences]);
end;

begin
  try
    if ParamCount <> 4 then
      raise Exception.Create('Usage: BuildVisiblePartPsd SOURCE.png PART.png REMAINDER.png OUTPUT.psd');
    OutputPath := TPath.GetFullPath(ParamStr(4));
    if TFile.Exists(OutputPath) then
      raise Exception.Create('Output already exists; choose a new filename');
    Original := ReadPng(ParamStr(1));
    Part := ReadPng(ParamStr(2));
    Remainder := ReadPng(ParamStr(3));
    Document := TArtDocument.Create;
    try
      Document.Width := Original.Width;
      Document.Height := Original.Height;
      AddImage('前髪（可視部・試験）', Part, True);
      AddImage('残り（未分離・補完なし）', Remainder, True);
      AddImage('元画像（比較用）', Original, False);
      Rendered := Document.RenderRGBA;
      CheckPixels(Rendered);
      WriteNewPsd(Document, OutputPath, pcRle);
      Reloaded := ReadPsd(OutputPath);
      try
        if (Reloaded.Roots.Count <> 3) or not Reloaded.Roots[0].Visible or
          not Reloaded.Roots[1].Visible or Reloaded.Roots[2].Visible then
          raise Exception.Create('PSD round trip changed layer structure');
        RoundTrip := RenderPsdLayers(Reloaded);
        CheckPixels(RoundTrip);
        WriteRgbaPng(TPath.ChangeExtension(OutputPath, '.rendered.png'),
          Reloaded.Width, Reloaded.Height, RoundTrip);
        Reloaded.Roots[1].Visible := False;
        WriteRgbaPng(TPath.ChangeExtension(OutputPath, '.front-only.png'),
          Reloaded.Width, Reloaded.Height, RenderPsdLayers(Reloaded));
        Writeln('PSD saved and reloaded with application persistence code.');
        Writeln('Layers: front hair / remainder / hidden original.');
        Writeln('Visible RGBA changed pixels: ', VisibleDifferences);
        Writeln('Alpha changed pixels: ', AlphaDifferences);
      finally
        Reloaded.Free;
      end;
    finally
      Document.Free;
    end;
  except
    on E: Exception do begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.

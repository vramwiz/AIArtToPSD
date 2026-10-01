program PrepareExchangeJob;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.IOUtils,
  ArtDocument in '..\Source\Core\ArtDocument.pas',
  ArtPng in '..\Source\Persistence\PNG\ArtPng.pas',
  ArtPsd in '..\Source\Persistence\PSD\ArtPsd.pas',
  ArtParts in '..\Source\Core\ArtParts.pas',
  ArtLayerName in '..\Source\Core\ArtLayerName.pas',
  ArtExchange in '..\Source\Integrations\AIExchange\ArtExchange.pas';
var
  Document: TArtDocument;
  Exchange: TArtExchange;
  Image: TArtPngData;
  Layer: TArtLayer;
  Directory, Root: string;
begin
  try
    if ParamCount <> 2 then
      raise Exception.Create('Usage: PrepareExchangeJob SOURCE.png OUTPUT_ROOT');
    Root := TPath.GetFullPath(ParamStr(2));
    Image := ReadPng(ParamStr(1));
    Document := TArtDocument.Create;
    Exchange := TArtExchange.Create;
    try
      Document.Width := Image.Width;
      Document.Height := Image.Height;
      Layer := Document.AddLayer(alkImage, '元画像',
        TArtBounds.Create(0, 0, Image.Width, Image.Height));
      Layer.Pixels := Image.Pixels;
      Directory := Exchange.ExportJob(Document,
        '顔の左右の目・見えている眉・口の元画素分離試験。髪と隠れ部分の生成は行わない。', Root);
      TFile.WriteAllText(TPath.Combine(Root, 'job-directory.txt'),
        Directory, TEncoding.UTF8);
      Writeln('Exchange recovery job prepared.');
    finally
      Exchange.Free;
      Document.Free;
    end;
  except
    on E: Exception do begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.

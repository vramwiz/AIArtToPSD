program AIArtToPSD;

uses
  System.SysUtils,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.Themes,
  Vcl.Styles,
  PipeServerTThread in 'Source\Lib\Pipe\PipeServerTThread.pas',
  HorizontalTrackBarRenderer in 'Source\Lib\UI\HorizontalTrackBar\HorizontalTrackBarRenderer.pas',
  HorizontalTrackBarControl in 'Source\Lib\UI\HorizontalTrackBar\HorizontalTrackBarControl.pas',
  ArtFileHistory in 'Source\Shell\ArtFileHistory.pas',
  VerticalScrollBarControl in 'Source\Lib\UI\VerticalScrollBar\VerticalScrollBarControl.pas',
  ArtLayerName in 'Source\Core\ArtLayerName.pas',
  ArtLayerList in 'Source\Shell\ArtLayerList.pas',
  ArtDocument in 'Source\Core\ArtDocument.pas',
  ArtPng in 'Source\Persistence\PNG\ArtPng.pas',
  ArtPsd in 'Source\Persistence\PSD\ArtPsd.pas',
  AIArtToPSDMainForm in 'Source\Shell\AIArtToPSDMainForm.pas' {MainForm};

{$R *.res}

begin
  Application.Initialize;
  TStyleManager.TrySetStyle('Windows Modern Dark');
  Application.MainFormOnTaskbar := True;
  Application.Title := 'AI立ち絵メーカー';
  Application.CreateForm(TMainForm, MainForm);
  if (ParamCount=1) and FileExists(ParamStr(1)) then
    try MainForm.OpenPsdFile(ParamStr(1));
    except on E: Exception do ShowMessage('PSDを開けませんでした。'+sLineBreak+E.Message); end;
  Application.Run;
end.

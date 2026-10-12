program SampleLayerTrial;
{$APPTYPE CONSOLE}
uses System.JSON, System.Math, System.Types, System.SysUtils, System.Classes, System.IOUtils, Vcl.Controls, Vcl.Forms, Vcl.Graphics, Vcl.Themes, Vcl.Styles, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Menus,
  Winapi.Windows, Winapi.Messages,
  HorizontalTrackBarRenderer in '..\Source\Lib\UI\HorizontalTrackBar\HorizontalTrackBarRenderer.pas',
  HorizontalTrackBarControl in '..\Source\Lib\UI\HorizontalTrackBar\HorizontalTrackBarControl.pas',
  ArtFileHistory in '..\Source\Shell\ArtFileHistory.pas',
  VerticalScrollBarControl in '..\Source\Lib\UI\VerticalScrollBar\VerticalScrollBarControl.pas',
  PipeServerTThread in '..\Source\Lib\Pipe\PipeServerTThread.pas',
  ArtUndo in '..\Source\Editor\ArtUndo.pas',
  ArtPipeBridge in '..\Source\Integrations\Pipe\ArtPipeBridge.pas',
  ArtPipeProtocol in '..\Source\Integrations\Pipe\ArtPipeProtocol.pas',
  ArtExchange in '..\Source\Integrations\AIExchange\ArtExchange.pas',
  ArtParts in '..\Source\Core\ArtParts.pas',
  DarkComboBox in '..\Source\Lib\UI\DarkComboBox\DarkComboBox.pas',
  ArtLayerName in '..\Source\Core\ArtLayerName.pas',
  ArtLayerList in '..\Source\Shell\ArtLayerList.pas',
  ArtDocument in '..\Source\Core\ArtDocument.pas',
  ArtPng in '..\Source\Persistence\PNG\ArtPng.pas',
  ArtPsd in '..\Source\Persistence\PSD\ArtPsd.pas',
  AIArtToPSDMainForm in '..\Source\Shell\AIArtToPSDMainForm.pas';
{$R ..\AIArtToPSD.res}
var F: TMainForm; Output,JobPath: string;
begin
  try
    Application.Initialize;
    Output := ExpandFileName(ParamStr(2)); ForceDirectories(Output);
    F := TMainForm.CreateWithHistory(nil,TPath.Combine(Output,'history'));
    try
      if ParamStr(1)='export' then begin
        F.NewFromPng(ExpandFileName('Sample/character_neutral.png'));
        JobPath := F.ExportAiJob('Sampleの画像を背景、頭部（髪と顔）、体と服の3レイヤーに分解。AI補完を含む試作。元画像は非表示で保持。',TPath.Combine(Output,'exchange'));
        TFile.WriteAllText(TPath.Combine(Output,'job_path.txt'),JobPath,TEncoding.UTF8);
        Writeln(JobPath);
      end else begin
        JobPath := TFile.ReadAllText(TPath.Combine(Output,'job_path.txt'),TEncoding.UTF8);
        F.RecoverAiJob(JobPath);
        F.ImportAiResult(TPath.Combine(JobPath,'result.json'));
        F.SavePsdFile(TPath.Combine(Output,'character_layers_trial_v2.psd'));
        WriteRgbaPng(TPath.Combine(Output,'composite_v2.png'),F.Document.Width,F.Document.Height,RenderPsdLayers(F.Document));
        Writeln('Saved ',F.Document.Roots.Count,' layers');
      end;
    finally F.Free; end;
  except on E: Exception do begin Writeln(E.Message); Halt(1); end; end;
end.
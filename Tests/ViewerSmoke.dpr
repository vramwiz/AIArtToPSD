program ViewerSmoke;
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
type TPaintAccess = class(TPaintBox);
var F: TMainForm; R,S: TRect; P: TPoint; Handled: Boolean; Rev: Int64;
    B: Vcl.Graphics.TBitmap; Output: string; I: Integer;
procedure Check(Value: Boolean; const Name: string);
begin if not Value then raise Exception.Create(Name); Writeln('PASS: '+Name); end;
begin
  try
    Application.Initialize; Output := ExpandFileName(ParamStr(1)); ForceDirectories(Output);
    F := TMainForm.CreateWithHistory(nil,Output);
    try
      F.Show; Application.ProcessMessages;
      F.OpenPsdFile(ExpandFileName('Tests/output/preserved_aiueo.psd'));
      Application.ProcessMessages;
      Check(F.Menu.Items.Count=1,'file menu only');
      Check(F.PromptControl.ReadOnly,'conversation is read only');
      Check(not F.LayerList.EditEnabled,'layer list is read only');
      for I := 0 to F.LayerList.RowCount-1 do Check(F.LayerList.SliderAt(I)=nil,'no opacity slider');
      R := F.PreviewBounds; Rev := F.Document.Revision;
      P := F.PreviewControl.ClientToScreen(Point(F.PreviewControl.Width div 2,F.PreviewControl.Height div 2));
      Handled := False; F.OnMouseWheel(F,[],120,P,Handled);
      S := F.PreviewBounds;
      Check(Handled and (S.Width>R.Width),'wheel zoom in');
      F.OnMouseWheel(F,[],-120,P,Handled);
      Check(Abs(F.PreviewBounds.Width-R.Width)<=1,'wheel zoom out');
      TPaintAccess(F.PreviewControl).OnMouseDown(F,mbLeft,[],80,80);
      TPaintAccess(F.PreviewControl).OnMouseMove(F,[ssLeft],140,110);
      TPaintAccess(F.PreviewControl).OnMouseUp(F,mbLeft,[],140,110);
      S := F.PreviewBounds;
      Check((S.Left=R.Left+60) and (S.Top=R.Top+30),'drag pans view');
      F.LayerList.Selected := F.Document.Roots[0];
      Check((F.Document.Revision=Rev) and not F.Modified,'view operations preserve document');
      F.SavePsdFile(TPath.Combine(Output,'viewer_saved.psd'));
      Check((F.PreviewBounds.Left=S.Left) and (F.PreviewBounds.Width=S.Width),'save preserves view');
      B := F.GetFormImage; try B.SaveToFile(TPath.Combine(Output,'viewer.bmp')); finally B.Free; end;
    finally F.Free; end;
  except on E: Exception do begin Writeln(E.Message); Halt(1); end; end;
end.
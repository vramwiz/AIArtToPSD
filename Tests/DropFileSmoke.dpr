program DropFileSmoke;
{$APPTYPE CONSOLE}
uses System.JSON, System.Math, System.Types, System.SysUtils, System.Classes, System.IOUtils, Vcl.Controls, Vcl.Forms, Vcl.Graphics, Vcl.Themes, Vcl.Styles, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Menus,
  Winapi.Windows, Winapi.Messages, Winapi.ShellAPI,
  HorizontalTrackBarRenderer in '..\Source\Lib\UI\HorizontalTrackBar\HorizontalTrackBarRenderer.pas',
  HorizontalTrackBarControl in '..\Source\Lib\UI\HorizontalTrackBar\HorizontalTrackBarControl.pas',
  DropFile in '..\Source\Lib\DropFile\DropFile.pas',
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
type
  PDropHeader = ^TDropHeader;
  TDropHeader = record
    pFiles: DWORD;
    pt: TPoint;
    fNC, fWide: BOOL;
  end;
  TDialogCloser = class
    Timer: TTimer;
    Count: Integer;
    procedure Tick(Sender: TObject);
  end;

procedure TDialogCloser.Tick(Sender: TObject);
var I: Integer;
begin
  for I := 0 to Screen.FormCount-1 do
    if fsModal in Screen.Forms[I].FormState then
    begin
      Inc(Count); Timer.Enabled := False;
      Screen.Forms[I].ModalResult := mrCancel;
      Exit;
    end;
end;

procedure Check(Value: Boolean; const Name: string);
begin
  if not Value then raise Exception.Create(Name);
  Writeln('PASS: '+Name);
end;

procedure SendDrop(Target: TWinControl; const Files: array of string);
var H: HGLOBAL; Header: PDropHeader; Text: string; FileName: string;
begin
  Text := '';
  for FileName in Files do Text := Text+FileName+#0;
  Text := Text+#0;
  H := GlobalAlloc(GHND,SizeOf(TDropHeader)+NativeUInt(Length(Text)*SizeOf(Char)));
  if H=0 then RaiseLastOSError;
  Header := GlobalLock(H);
  if Header=nil then begin GlobalFree(H); RaiseLastOSError; end;
  Header.pFiles := SizeOf(TDropHeader); Header.fWide := True;
  Move(PChar(Text)^,PByte(Header)[SizeOf(TDropHeader)],Length(Text)*SizeOf(Char));
  GlobalUnlock(H);
  // TDropFile owns the HDROP and calls DragFinish, including rejected drops.
  SendMessage(Target.Handle,WM_DROPFILES,WPARAM(H),0);
end;

procedure MakePsd(const Path: string);
var D: TArtDocument; L: TArtLayer;
begin
  D := TArtDocument.Create;
  try
    D.Width := 2; D.Height := 2;
    L := D.AddLayer(alkImage,'drop test',TArtBounds.Create(0,0,2,2));
    L.Pixels := TBytes.Create(255,0,0,255,0,255,0,255,0,0,255,255,255,255,255,255);
    WriteNewPsd(D,Path);
  finally D.Free; end;
end;

var F: TMainForm; Before: TArtDocument; Closer: TDialogCloser;
    Output,First,Second,Bad,HistoryDir: string; History: TArtFileHistory;
begin
  try
    Application.Initialize; UseLatestCommonDialogs := False;
    Output := ExpandFileName(ParamStr(1)); ForceDirectories(Output);
    First := TPath.Combine(Output,'日本語 ドロップ.PSD');
    Second := TPath.Combine(Output,'second.psd'); Bad := TPath.Combine(Output,'broken.psd');
    HistoryDir := TPath.Combine(Output,TGUID.NewGuid.ToString);
    MakePsd(First); MakePsd(Second); TFile.WriteAllText(Bad,'not a PSD');
    F := TMainForm.CreateWithHistory(nil,HistoryDir);
    Closer := TDialogCloser.Create;
    try
      Closer.Timer := TTimer.Create(nil); Closer.Timer.Enabled := False;
      Closer.Timer.Interval := 50; Closer.Timer.OnTimer := Closer.Tick;
      Check((GetWindowLongPtr(F.Handle,GWL_EXSTYLE) and WS_EX_ACCEPTFILES)<>0,'form accepts shell drops');
      SendDrop(F.PreviewControl.Parent,[First]);
      Check((F.Document<>nil) and not F.Modified,'preview drop opens PSD');
      Check((F.FileHistory.Files.Count=1) and (F.FileHistory.Files[0]=First),'Unicode PSD added to history');
      Before := F.Document;
      SendDrop(F,['ignored.png']);
      Check((F.Document=Before) and (F.FileHistory.Files.Count=1),'non-PSD ignored');
      SendDrop(F.LayerList,['ignored.txt',Second,First]);
      Check((F.FileHistory.Files.Count=2) and (F.FileHistory.Files[0]=Second),'first PSD in batch opens from layer list');
      Check(F.Menu.Items[0].Items[4].Items[0].Hint=Second,'recent menu refreshed');
      SendDrop(F.PromptControl,[First]);
      Check((F.FileHistory.Files.Count=2) and (F.FileHistory.Files[0]=First),'prompt drop promotes history without duplicates');
      Before := F.Document; Closer.Timer.Enabled := True;
      SendDrop(F,[Bad]);
      Check((Closer.Count=1) and (F.Document=Before) and not F.Modified,'failed drop preserves document');
      Check((F.FileHistory.Files.Count=2) and (F.FileHistory.Files.IndexOf(Bad)<0),'failed PSD not added to history');
      F.LayerList.Selected := F.Document.Roots[0];
      F.ApplySelectedLayer('modified',False,255);
      Before := F.Document; Closer.Timer.Enabled := True;
      SendDrop(F.PreviewControl.Parent,[Second]);
      Check((Closer.Count=2) and (F.Document=Before) and F.Modified,'cancelled unsaved confirmation preserves edits');
      Check(F.FileHistory.Files[0]=First,'cancelled drop does not update history');
      History := TArtFileHistory.Create(HistoryDir);
      try Check((History.Files.Count=2) and (History.Files[0]=First),'drop history persisted');
      finally History.Free; end;
    finally
      Closer.Timer.Free; Closer.Free; F.Free;
    end;
  except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); Halt(1); end; end;
end.

program UiSmoke;
{$APPTYPE CONSOLE}
uses System.Math, System.Types, System.SysUtils, System.Classes, System.IOUtils, Vcl.Controls, Vcl.Forms, Vcl.Graphics, Vcl.Themes, Vcl.Styles, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Menus,
  Winapi.Windows, Winapi.Messages,
  HorizontalTrackBarRenderer in '..\Source\Lib\UI\HorizontalTrackBar\HorizontalTrackBarRenderer.pas',
  HorizontalTrackBarControl in '..\Source\Lib\UI\HorizontalTrackBar\HorizontalTrackBarControl.pas',
  ArtFileHistory in '..\Source\Shell\ArtFileHistory.pas',
  VerticalScrollBarControl in '..\Source\Lib\UI\VerticalScrollBar\VerticalScrollBarControl.pas',
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
  TTrackBarAccess = class(THorizontalTrackBarControl);
  TLayerListAccess = class(TArtLayerList);
  TDialogCapture = class
    Dialog: TCommonDialog;
    FileName: string;
    Saved: Boolean;
    Timer: TTimer;
    procedure Tick(Sender: TObject);
    procedure Capture(A: TCommonDialog; const Path: string);
  end;
function CaptureWindow(W: HWND; DC: HDC; Flags: Cardinal): BOOL; stdcall; external 'user32.dll' name 'PrintWindow';
procedure TDialogCapture.Tick(Sender: TObject);
var W: HWND; R: TRect; B: Vcl.Graphics.TBitmap;
begin
  if Dialog.Handle=0 then Exit;
  Timer.Enabled := False; W := GetAncestor(Dialog.Handle,GA_ROOT);
  GetWindowRect(W,R); B := Vcl.Graphics.TBitmap.Create;
  try
    B.SetSize(R.Right-R.Left,R.Bottom-R.Top);
    Saved := CaptureWindow(W,B.Canvas.Handle,0);
    if Saved then B.SaveToFile(FileName);
  finally B.Free; end;
  PostMessage(W,WM_CLOSE,0,0);
end;
procedure TDialogCapture.Capture(A: TCommonDialog; const Path: string);
begin
  Dialog := A; FileName := Path; Saved := False;
  Timer := TTimer.Create(nil);
  try
    Timer.Interval := 1000; Timer.OnTimer := Tick; Timer.Enabled := True;
    A.Execute;
  finally Timer.Free; end;
end;
var F: TMainForm; D,Before: TArtDocument; B: Vcl.Graphics.TBitmap; Input,Output,Sample: string;
    History: TArtFileHistory; DeepList: TArtLayerList; G: TArtLayer;
    PngImage: TArtPngData; LayerCount: Integer; SavedLayer: TArtLayer; DragScale: Double;
    Capture: TDialogCapture; A,C: TBytes; Count: Integer; Raised: Boolean;
procedure Check(Value: Boolean; const Msg: string);
begin Inc(Count); if not Value then raise Exception.Create(Msg); end;
procedure TestLayerNames;
const Prefixes: array[0..2] of string = ('','*','!');
  Suffixes: array[0..3] of string = ('',':flipx',':flipy',':flipxy');
var I,J: Integer; Original: string; Parts: TArtLayerNameParts; Bad: Boolean;
begin
  for I := 0 to 2 do
    for J := 0 to 3 do begin
      Original := Prefixes[I]+'名前😀'+Suffixes[J]; Parts := ParseLayerName(Original);
      Check(Parts.DisplayName='名前😀','Editor exposes modifiers');
      Check(RenameLayerDisplay(Original,'再編集')=Prefixes[I]+'再編集'+Suffixes[J],'Rename lost modifiers');
      Check(SetLayerPrefix(Original,'!')='!名前😀'+Suffixes[J],'Prefix exclusivity');
      Check(SetLayerFlip(Original,':flipy')=Prefixes[I]+'名前😀:flipy','Flip exclusivity');
    end;
  Bad := False;
  try RenameLayerDisplay('*名前:flipx','!別名'); except on E: EArtFormat do Bad := True; end;
  Check(Bad,'Inline editor can inject prefix');
  Bad := False;
  try RenameLayerDisplay('!名前:flipy','別名:flipxy'); except on E: EArtFormat do Bad := True; end;
  Check(Bad,'Inline editor can inject suffix');
end;
begin
  try
    if ParamCount<>2 then raise Exception.Create('Usage: UiSmoke OUTPUT_DIRECTORY SAMPLE_DIRECTORY');
    Output := TPath.GetFullPath(ParamStr(1)); Sample := TPath.GetFullPath(ParamStr(2));
    TestLayerNames;
    ForceDirectories(TPath.Combine(Output,'history_migration'));
    TFile.WriteAllText(TPath.Combine(Output,'history_migration\history.ini'),
      '[Opened]'+sLineBreak+'0='+TPath.Combine(Output,'nested.psd')+sLineBreak+
      '[Saved]'+sLineBreak+'0='+TPath.Combine(Output,'ui_edited.psd')+sLineBreak+
      '1='+TPath.Combine(Output,'nested.psd')+sLineBreak,TEncoding.UTF8);
    History := TArtFileHistory.Create(TPath.Combine(Output,'history_migration'));
    try
      Check(History.Files.Count=2,'Legacy history migration lost files or retained duplicates');
      History.AddFile(TPath.Combine(Output,'ui_edited.psd'));
      Check(History.Files[0]=TPath.Combine(Output,'ui_edited.psd'),'Unified history did not promote most recent file');
      Check(History.Files.Count=2,'Unified history duplicated existing file');
    finally History.Free; end;
    Application.Initialize;
    Check(TStyleManager.TrySetStyle('Windows Modern Dark'),'Dark style resource missing');
    F := TMainForm.CreateWithHistory(nil,TPath.Combine(Output,'history_ui'));
    try
      Input := TPath.Combine(Output,'nested.psd'); F.OpenPsdFile(Input);
      Check(F.Menu.Items[0].Count=9,'File menu operations missing');
      Check(F.LayerList.Parent.Left>F.ClientWidth div 2,'Layer panel not on right');
      Check(F.Document<>nil,'No document'); Check(F.LayerList.RowCount=7,'Wrong tree count');
      Check(F.CanEdit,'Generated PSD cannot edit'); Check(not F.Modified,'Loaded document dirty');
      F.LayerList.Selected := F.LayerList.LayerAt(0);
      F.ApplySelectedLayer('画面で編集😀',False,73);
      Check(F.Modified,'UI edit did not mark dirty'); Check(not F.Document.Roots[0].Visible,'UI visibility not changed');
      Before := F.Document; Raised := False;
      try F.OpenPsdFile(TPath.Combine(Output,'invalid.fixture')); except on E: EArtFormat do Raised := True; end;
      Check(Raised,'Corrupt UI load accepted'); Check(F.Document=Before,'Corrupt load changed document');
      Check(F.Modified,'Corrupt load discarded dirty state');
      F.SavePsdFile(TPath.Combine(Output,'ui_edited.psd'));
      Check(not F.Modified,'Successful UI save did not establish baseline');
      D := ReadPsd(TPath.Combine(Output,'ui_edited.psd'));
      try Check(D.Roots[0].Name='画面で編集😀','Saved UI name');
        Check((not D.Roots[0].Visible) and (D.Roots[0].Opacity=73),'Saved UI attributes'); finally D.Free; end;
      F.ApplySelectedLayer('再編集',True,200); F.SavePsdFile(TPath.Combine(Output,'ui_edited_again.psd'));
      Check(not F.Modified,'Second save baseline');
      F.ApplySelectedLayer('メニュー保存',True,180);
      F.Menu.Items[0].Items[3].Click;
      Check(not F.Modified,'File menu overwrite save failed');
      F.Show; Application.ProcessMessages;
      F.ApplySelectedLayer('*元名:flipxy',True,180);
      F.LayerList.BeginRename;
      Check(F.LayerList.NameEditor.Visible,'Inline editor missing');
      Check(F.LayerList.NameEditor.Text='元名','Inline editor exposes protected modifiers');
      F.LayerList.NameEditor.Text := '新しい名前'; F.LayerList.NameEditor.Perform(WM_KEYDOWN,VK_RETURN,0);
      Check(F.Document.Roots[0].Name='*新しい名前:flipxy','Inline rename lost modifiers');
      F.LayerList.BeginRename; F.LayerList.NameEditor.Text := '破棄'; F.LayerList.NameEditor.Perform(WM_KEYDOWN,VK_ESCAPE,0);
      Check(F.Document.Roots[0].Name='*新しい名前:flipxy','Cancelled rename committed');
      F.LayerList.ModifierMenu.Items[1].Click;
      Check(F.Document.Roots[0].Name='!新しい名前:flipxy','Star and bang coexist');
      F.LayerList.ModifierMenu.Items[1].Click;
      Check(F.Document.Roots[0].Name='新しい名前:flipxy','Bang toggle off');
      F.LayerList.ModifierMenu.Items[4].Click;
      Check(F.Document.Roots[0].Name='新しい名前:flipx','Multiple flip suffixes');
      F.LayerList.ModifierMenu.Items[3].Click;
      Check(F.Document.Roots[0].Name='新しい名前','Flip toggle none');
      TLayerListAccess(F.LayerList).MouseDown(mbLeft,[],18,45);
      Check(not F.Document.Roots[0].Visible,'Eye click did not hide layer');
      TLayerListAccess(F.LayerList).MouseDown(mbLeft,[],18,45);
      Check(F.Document.Roots[0].Visible,'Eye click did not show layer');
      Check(F.LayerList.SliderAt(0)<>nil,'Row opacity slider absent');
      F.LayerList.SliderAt(0).Position := 127;
      Check(F.Document.Roots[0].Opacity=127,'Row slider did not change opacity');
      Check(not F.LayerList.SliderAt(1).Enabled,'Group opacity must remain unsupported');
      F.LayerList.SliderAt(3).Position := 64;
      Check(F.LayerList.Selected=F.LayerList.LayerAt(3),'Slider did not select target layer');
      Check(F.LayerList.LayerAt(3).Opacity=64,'Nonselected row slider lost its new value');
      F.LayerList.ScrollBy(1000);
      Check(F.LayerList.ScrollBar.Position>0,'Custom scroll did not move');
      F.LayerList.ScrollBy(-1000);
      Check(F.LayerList.ScrollBar.Position=0,'Custom scroll origin');
      TLayerListAccess(F.LayerList).DoMouseWheel([], -120, Point(0,0));
      Check(F.LayerList.ScrollBar.Position>0,'Wheel did not scroll list');
      TLayerListAccess(F.LayerList).DoMouseWheel([], 120, Point(0,0));
      Check(F.LayerList.ScrollBar.Position=0,'Wheel upward did not restore origin');
      TTrackBarAccess(F.LayerList.SliderAt(0)).DoMouseWheel([], -120, Point(0,0));
      Check(F.LayerList.ScrollBar.Position>0,'Wheel over slider did not scroll list');
      Check(F.LayerList.LayerAt(0).Opacity=127,'Wheel over slider unexpectedly changed opacity');
      F.LayerList.ScrollBy(-1000);
      F.SavePsdFile(TPath.Combine(Output,'ui_layerlist_edited.psd'));
      Check(F.Document.Roots[0].Opacity=127,'Saved row opacity did not survive reload');
      Check(F.LayerList.LayerAt(3).Opacity=64,'Saved child opacity did not survive reload');
      Check(F.FileHistory.Files[0]=TPath.Combine(Output,'ui_layerlist_edited.psd'),'Saved history latest order');
      Check(F.FileHistory.Files.IndexOf(TPath.Combine(Output,'invalid.fixture'))<0,'Failed open recorded in history');
      History := TArtFileHistory.Create(F.FileHistory.Directory);
      try
        Check(History.Files[0]=F.FileHistory.Files[0],'History did not persist saved files');
        Check(History.Files[0]=F.FileHistory.Files[0],'History did not persist opened files');
      finally History.Free; end;
      F.Menu.Items[0].Items[6].Items[0].Click;
      Check(not F.Modified,'History menu open dirtied document');
      Check(F.FileHistory.Files[0]=TPath.Combine(Output,'ui_layerlist_edited.psd'),'History menu did not open saved path');
      History := TArtFileHistory.Create('');
      try Check(History.Directory=TPath.Combine(TPath.GetDocumentsPath,'AIArtToPSD'),'Default history directory');
      finally History.Free; end;
      D := TArtDocument.Create; DeepList := TArtLayerList.Create(nil);
      try
        G := D.AddLayer(alkGroup,'第一階層',TArtBounds.Create(0,0,0,0));
        G := D.AddLayer(alkGroup,'第二階層',TArtBounds.Create(0,0,0,0),G);
        G := D.AddLayer(alkGroup,'第三階層',TArtBounds.Create(0,0,0,0),G);
        D.AddLayer(alkImage,'内側の画像',TArtBounds.Create(0,0,1,1),G);
        DeepList.SetRoots(D.Roots);
        Check(DeepList.RowCount=3,'Initial hierarchy expanded deeper than two levels');
      finally DeepList.Free; D.Free; end;
      F.Show; Application.ProcessMessages;
      B := Vcl.Graphics.TBitmap.Create;
      try B.SetSize(F.ClientWidth,F.ClientHeight); F.PaintTo(B.Canvas,0,0);
        B.SaveToFile(TPath.Combine(Output,'ui_preview.bmp')); finally B.Free; end;
      Capture := TDialogCapture.Create;
      try
        F.OpenDialog.InitialDir := Output; F.OpenDialog.FileName := '';
        Capture.Capture(F.OpenDialog,TPath.Combine(Output,'ui_open_dialog_final.bmp'));
        Check(Capture.Saved,'Final open dialog capture failed');
        F.SaveDialog.InitialDir := Output; F.SaveDialog.FileName := '確認.psd';
        Capture.Capture(F.SaveDialog,TPath.Combine(Output,'ui_save_dialog_final.bmp'));
        Check(Capture.Saved,'Final save dialog capture failed');
      finally Capture.Free; end;
      F.OpenPsdFile(TPath.Combine(Sample,'aiueo.psd'));
      Check(F.CanEdit,'Real aiueo PSD still disables all editing');
      Check(F.LayerList.EditEnabled,'Real PSD controls disabled');
      A := RenderPsdLayers(F.Document);
      TFile.WriteAllBytes(TPath.Combine(Output,'aiueo_initial.rgba'),A);
      TLayerListAccess(F.LayerList).MouseDown(mbLeft,[],18,45);
      Check(not F.Document.Roots[0].Visible,'Real PSD eye did not hide');
      C := RenderPsdLayers(F.Document);
      Check(not CompareMem(@A[0],@C[0],Length(A)),'Real PSD hide did not alter preview');
      TLayerListAccess(F.LayerList).MouseDown(mbLeft,[],18,45);
      Check(F.Document.Roots[0].Visible,'Real PSD eye did not show');
      Check(F.LayerList.LayerAt(0).Kind=alkGroup,'Real fixture first row must be normal group');
      Check(F.LayerList.LayerAt(1).Kind=alkGroup,'Real fixture second row must be nested group');
      Check(F.LayerList.LayerAt(2).Kind=alkImage,'Real fixture third row must be image');
      F.LayerList.SliderAt(0).Position := 96;
      Check(F.Document.Roots[0].Opacity=96,'Real PSD image opacity unchanged');
      C := RenderPsdLayers(F.Document);
      Check(not CompareMem(@A[0],@C[0],Length(A)),'Real PSD opacity did not alter preview');
      Check(F.LayerList.SliderAt(1).Enabled,'Normal group opacity remains disabled');
      F.LayerList.SliderAt(1).Position := 128;
      Check(F.LayerList.LayerAt(1).Opacity=128,'Normal group opacity did not change');
      F.LayerList.SliderAt(2).Position := 160;
      Check(F.LayerList.LayerAt(2).Opacity=160,'Real image opacity did not change');
      F.SavePsdFile(TPath.Combine(Output,'aiueo_ui_edited.psd'));
      Check(F.Document.Roots[0].Opacity=96,'Real PSD save lost image opacity');
      Check(F.LayerList.LayerAt(1).Opacity=128,'Real PSD save lost group opacity');
      Check(F.LayerList.LayerAt(2).Opacity=160,'Real PSD save lost image opacity');
      Check(not F.Modified,'Real PSD save did not reset modified state');
      F.LayerList.Selected := F.LayerList.LayerAt(0); F.LayerList.BeginRename;
      F.LayerList.NameEditor.Text := '背景再編集'; F.LayerList.FinishRename(True);
      F.SavePsdFile(TPath.Combine(Output,'aiueo_ui_renamed.psd'));
      Check(ParseLayerName(F.Document.Roots[0].Name).DisplayName='背景再編集','Real PSD rename did not survive preserved save');
      F.Show; Application.ProcessMessages;
      B := Vcl.Graphics.TBitmap.Create;
      try B.SetSize(F.ClientWidth,F.ClientHeight); F.PaintTo(B.Canvas,0,0);
        B.SaveToFile(TPath.Combine(Output,'ui_aiueo_preview.bmp')); finally B.Free; end;
      TLayerListAccess(F.LayerList).MouseDown(mbLeft,[],18,45);
      F.SavePsdFile(TPath.Combine(Output,'aiueo_ui_hidden.psd'));
      Check(not F.Document.Roots[0].Visible,'Real PSD save lost hidden state');
      Check(F.Document.Roots[0].Opacity=96,'Real PSD hidden save lost opacity');
      // Stage 11: PNG-only creation -> add -> move -> replace -> save/reopen.
      for var PngName in ['素材ベース.png','追加パーツ.png','置換.png','palette.png','palette2.png','mono.png'] do begin
        PngImage := ReadPng(TPath.Combine(Output,PngName));
        TFile.WriteAllBytes(TPath.Combine(Output,PngName+'.rgba'),PngImage.Pixels);
        Check(Length(PngImage.Pixels)=PngImage.Width*PngImage.Height*4,'PNG RGBA dimensions');
      end;
      F.NewFromPng(TPath.Combine(Output,'素材ベース.png'));
      Check((F.Document.Width=32) and (F.Document.Height=24),'PNG new canvas size');
      Check(F.Modified and F.CanEdit,'PNG new document state');
      PngImage := ReadPng(TPath.Combine(Output,'素材ベース.png'));
      Check(CompareMem(@F.Document.Roots[0].Pixels[0],@PngImage.Pixels[0],Length(PngImage.Pixels)),'PNG new pixels altered');
      Before := F.Document; Raised := False;
      try F.NewFromPng(TPath.Combine(Output,'bad_png.fixture')); except on E: Exception do Raised := True; end;
      Check(Raised and (F.Document=Before),'Invalid PNG replaced current document');
      Raised := False;
      try F.ImportPngFile(TPath.Combine(Output,'huge_png.fixture')); except on E: Exception do Raised := True; end;
      Check(Raised and (F.Document.Roots.Count=1),'Oversized PNG mutated document');
      F.ImportPngFile(TPath.Combine(Output,'追加パーツ.png'));
      Check(F.Document.Roots.Count=2,'PNG layer not added');
      Check(F.LayerList.Selected=F.Document.Roots[0],'PNG layer not added above selection');
      F.ApplySelectedLayer('*パーツ:flipxy',True,191);
      F.MoveSelectedLayer(-2,3);
      Check((F.LayerList.Selected.Bounds.Left=-2) and (F.LayerList.Selected.Bounds.Top=3),'Negative PNG position');
      F.ReplaceSelectedPng(TPath.Combine(Output,'置換.png'));
      Check((F.LayerList.Selected.Bounds.Width=9) and (F.LayerList.Selected.Bounds.Height=6),'PNG replacement size');
      Check((F.LayerList.Selected.Name='*パーツ:flipxy') and (F.LayerList.Selected.Opacity=191),'PNG replacement lost name/modifiers/opacity');
      Check((F.LayerList.Selected.Bounds.Left=-2) and (F.LayerList.Selected.Bounds.Top=3),'Replacement reset position');
      DragScale := Min(F.PreviewControl.Width/F.Document.Width,F.PreviewControl.Height/F.Document.Height);
      F.PreviewControl.OnMouseDown(F.PreviewControl,mbLeft,[],F.PreviewControl.Width div 2,F.PreviewControl.Height div 2);
      F.PreviewControl.OnMouseMove(F.PreviewControl,[ssLeft],F.PreviewControl.Width div 2+Round(3*DragScale),F.PreviewControl.Height div 2+Round(2*DragScale));
      Check(F.LayerList.Selected.Bounds.Left=-2,'Drag committed before mouse release');
      F.PreviewControl.OnMouseUp(F.PreviewControl,mbLeft,[],F.PreviewControl.Width div 2+Round(3*DragScale),F.PreviewControl.Height div 2+Round(2*DragScale));
      Check((F.LayerList.Selected.Bounds.Left=1) and (F.LayerList.Selected.Bounds.Top=5),'Preview drag did not place image');
      F.MoveSelectedLayer(-2,3);
      Raised := False; SavedLayer := F.LayerList.Selected;
      try F.ReplaceSelectedPng(TPath.Combine(Output,'bad_png.fixture')); except on E: Exception do Raised := True; end;
      Check(Raised and (SavedLayer.Bounds.Width=9),'Bad replacement mutated selected image');
      F.SavePsdFile(TPath.Combine(Output,'png_workflow.psd'));
      Check(not F.Modified,'New PNG PSD save baseline');
      Check((F.Document.Roots.Count=2) and (F.Document.Roots[0].Name='*パーツ:flipxy'),'New PNG PSD reopened hierarchy');
      Check(F.Document.Roots[0].Bounds.Left=-2,'New PNG PSD reopened position');
      F.ImportPngFile(TPath.Combine(Output,'追加パーツ.png'));
      F.MoveSelectedLayer(11,8); F.SavePsdFile(TPath.Combine(Output,'png_workflow_added.psd'));
      Check(F.Document.Roots.Count=3,'Adding after first save did not persist');
      Check(F.Document.Roots[0].Bounds.Left=11,'Second save lost added placement');
      F.LayerList.Selected := F.Document.Roots[0]; F.ReplaceSelectedPng(TPath.Combine(Output,'置換.png'));
      F.MoveSelectedLayer(12,9); F.SavePsdFile(TPath.Combine(Output,'png_workflow_replaced.psd'));
      Check((F.Document.Roots[0].Bounds.Left=12) and (F.Document.Roots[0].Bounds.Width=9),'Replacement after saved baseline failed');
      // Preserve the real archive while inserting a new PNG inside its selected group.
      F.OpenPsdFile(TPath.Combine(Sample,'aiueo.psd'));
      LayerCount := F.LayerList.RowCount;
      F.ImportPngFile(TPath.Combine(Output,'追加パーツ.png'));
      Check(F.LayerList.RowCount=LayerCount+1,'Real PSD PNG insertion count');
      Check(F.Document.Roots[0].Children.Contains(F.LayerList.Selected),'PNG not inserted into selected group');
      F.ApplySelectedLayer('!追加素材:flipy',True,173); F.MoveSelectedLayer(5,6);
      TFile.WriteAllBytes(TPath.Combine(Output,'protected_stage11.fixture'),TBytes.Create(17,23,41));
      SavedLayer := F.Document.Roots[0].Children.Last;
      F.Document.Roots[0].Children.Remove(SavedLayer); Raised := False;
      try
        try SaveImageCompositionPsd(F.Document,TPath.Combine(Output,'protected_stage11.fixture'));
        except on E: EArtFormat do Raised := True; end;
      finally F.Document.Roots[0].Children.Add(SavedLayer); end;
      Check(Raised,'Imported source layer removal was accepted');
      A := TFile.ReadAllBytes(TPath.Combine(Output,'protected_stage11.fixture'));
      Check((Length(A)=3) and (A[0]=17) and (A[1]=23) and (A[2]=41),'Failed composition overwrote destination');
      F.SavePsdFile(TPath.Combine(Output,'aiueo_png_added.psd'));
      Check(F.Document.Roots[0].Children[0].Name='!追加素材:flipy','Real PSD new PNG not saved');
      F.LayerList.Selected := F.Document.Roots[0].Children[0]; F.ReplaceSelectedPng(TPath.Combine(Output,'置換.png'));
      F.MoveSelectedLayer(8,9); F.SavePsdFile(TPath.Combine(Output,'aiueo_png_replaced.psd'));
      Check((F.Document.Roots[0].Children[0].Bounds.Left=8) and (F.Document.Roots[0].Children[0].Bounds.Width=9),'Real PSD PNG replacement save failed');
      Check(F.Document.Roots[0].Children[0].Opacity=173,'Real PSD PNG replacement changed opacity');
      Check(F.LayerList.Selected=F.Document.Roots[0].Children[0],'Save lost selected imported image');
      F.Show; Application.ProcessMessages;
      B := Vcl.Graphics.TBitmap.Create;
      try B.SetSize(F.ClientWidth,F.ClientHeight); F.PaintTo(B.Canvas,0,0);
        B.SaveToFile(TPath.Combine(Output,'ui_png_workflow.bmp')); finally B.Free; end;
      // Stage 12: independent exclusive families, nested expressions and preserved group insertion.
      F.NewFromPng(TPath.Combine(Output,'素材ベース.png'));
      F.CreateGroup('表情',False); G := F.LayerList.Selected;
      Check((G.Kind=alkGroup) and (G.Name='表情'),'Expression container missing');
      F.CreateGroup('通常',True); SavedLayer := F.LayerList.Selected;
      F.ImportPngFile(TPath.Combine(Output,'追加パーツ.png'));
      F.LayerList.Selected := G; F.CreateGroup('喜',True);
      Check(not F.LayerList.Selected.Visible,'New alternative overlapped active expression');
      F.ImportPngFile(TPath.Combine(Output,'置換.png'));
      F.SelectPart(G.Children[0]);
      Check(G.Children[0].Visible and not SavedLayer.Visible,'Expression selection not exclusive');
      Check(G.Children[0].Children[0].Visible and SavedLayer.Children[0].Visible,'Switch mutated nested image visibility');
      F.SelectPart(SavedLayer);
      Check(SavedLayer.Visible and not G.Children[0].Visible,'Switch back failed');
      F.LayerList.Selected := F.Document.Roots.Last; F.CreateGroup('手',False);
      F.ImportPngFile(TPath.Combine(Output,'追加パーツ.png')); F.ApplySelectedLayer('*開く',True,255);
      F.LayerList.Selected := F.Document.Roots[1];
      F.ImportPngFile(TPath.Combine(Output,'置換.png')); F.ApplySelectedLayer('*握る',True,255);
      Check(not F.Document.Roots[1].Children[1].Visible,'Image parts overlapped');
      Check(SavedLayer.Visible,'Other family changed');
      Check(F.PartGroupControl.Items.Count=2,'Part selectors missing families');
      // Drive the same dropdown event used by the UI.
      F.PartGroupControl.ItemIndex := 1; F.PartGroupControl.OnChange(F.PartGroupControl);
      F.PartChoiceControl.ItemIndex := 1; F.PartChoiceControl.OnChange(F.PartChoiceControl);
      Check(F.Document.Roots[1].Children[1].Visible and not F.Document.Roots[1].Children[0].Visible,'Dropdown did not switch');
      F.LayerList.Selected := F.Document.Roots.Last; F.ApplySelectedLayer('!ベース',True,255);
      Check(F.LayerList.Selected.Visible,'Unrelated base visibility changed');
      // Invalid rendering rolls all sibling visibility back.
      G := F.Document.Roots[1]; G.Children[0].BlendKey := 'mul '; Raised := False;
      try F.SelectPart(G.Children[0]); except on E: EArtFormat do Raised := True; end;
      Check(Raised and G.Children[1].Visible and not G.Children[0].Visible,'Failed switch lost previous state');
      G.Children[0].BlendKey := 'norm';
      F.SavePsdFile(TPath.Combine(Output,'parts_new.psd'));
      Check(not F.Modified,'Expression save baseline');
      Check((F.Document.Roots[0].Children.Count=2) and (F.Document.Roots[0].Children[1].Name='*通常'),'Expression hierarchy lost');
      F.SelectPart(F.Document.Roots[0].Children[0]); F.SavePsdFile(TPath.Combine(Output,'parts_switched.psd'));
      Check(F.Document.Roots[0].Children[0].Visible and not F.Document.Roots[0].Children[1].Visible,'Saved expression state lost');
      F.Show; Application.ProcessMessages; B := Vcl.Graphics.TBitmap.Create;
      try B.SetSize(F.ClientWidth,F.ClientHeight); F.PaintTo(B.Canvas,0,0); B.SaveToFile(TPath.Combine(Output,'ui_parts.bmp')); finally B.Free; end;
      // Insert paired new group records into an imported archive, then save again.
      F.OpenPsdFile(TPath.Combine(Sample,'aiueo.psd'));
      F.CreateGroup('追加表情',False); F.CreateGroup('通常',True);
      F.ImportPngFile(TPath.Combine(Output,'追加パーツ.png'));
      F.SavePsdFile(TPath.Combine(Output,'aiueo_parts.psd'));
      Check(F.Document.Roots[0].Children[0].Kind=alkGroup,'Imported group insertion lost');
      Check(F.Document.Roots[0].Children[0].Children[0].Name='*通常','Imported alternative group lost');
      F.LayerList.Selected := F.Document.Roots[0].Children[0]; F.CreateGroup('喜',True);
      F.ImportPngFile(TPath.Combine(Output,'置換.png'));
      F.SelectPart(F.Document.Roots[0].Children[0].Children[0]);
      F.SavePsdFile(TPath.Combine(Output,'aiueo_parts_switched.psd'));
      Check(F.Document.Roots[0].Children[0].Children[0].Visible and not F.Document.Roots[0].Children[0].Children[1].Visible,'Imported nested switch save failed');
      F.OpenPsdFile(TPath.Combine(Sample,'layer_test.psd'));
      Check(not F.CanEdit,'Layerless original should be view-only');
      Check(F.LayerList.RowCount=0,'Layerless tree not empty');
      F.SavePsdFile(TPath.Combine(Output,'ui_original_copy.psd'));
      A := TFile.ReadAllBytes(TPath.Combine(Sample,'layer_test.psd'));
      C := TFile.ReadAllBytes(TPath.Combine(Output,'ui_original_copy.psd'));
      Check((Length(A)=Length(C)) and CompareMem(@A[0],@C[0],Length(A)),'Original UI save not byte identical');
      F.Menu.Items[0].Items[5].Click;
      Check(F.Document=nil,'File menu close retained document');
      Check(not F.Menu.Items[0].Items[3].Enabled,'Save enabled without document');
    finally F.Free; end;
    Writeln('PASS: ',Count,' UI assertions');
  except on E: Exception do begin Writeln(E.ClassName,': ',E.Message); Halt(1); end; end;
end.


unit AIArtToPSDMainForm;

interface

uses System.Types, System.Classes, System.SysUtils, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, 
  Vcl.Dialogs, Vcl.Menus, Vcl.Samples.Spin, Vcl.Graphics, ArtDocument, ArtLayerList, ArtFileHistory;

type
  TMainForm = class(TForm)
  private
    FDocument: TArtDocument;
    FFileName: string;
    FModified: Boolean;
    FTree: TArtLayerList;
    FPaint: TPaintBox;
    FBitmap: Vcl.Graphics.TBitmap;
    FStatus: TLabel;
    FHistory: TArtFileHistory;
    FHistoryMenu: TMenuItem;
    FLoadingSaved: Boolean;
    FSave, FSaveAs, FClose: TMenuItem;
    FOpenDialog: TOpenDialog;
    FSaveDialog: TSaveDialog;
    FCanEdit: Boolean;
    FPngDialog: TOpenDialog;
    FImportItem, FReplaceItem, FPositionItem: TMenuItem;
    FX,FY: TSpinEdit;
    FPositionApply: TButton;
    FDragging: Boolean;
    FDragStart: TPoint;
    FDragX,FDragY,FDragDX,FDragDY: Integer;
    procedure NewPngClick(Sender: TObject);
    procedure ImportPngClick(Sender: TObject);
    procedure ReplacePngClick(Sender: TObject);
    procedure PositionClick(Sender: TObject);
    procedure PreviewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
    procedure PreviewMouseMove(Sender: TObject; Shift: TShiftState; X,Y: Integer);
    procedure PreviewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
    function PreviewRect: TRect;
    procedure HistoryClick(Sender: TObject);
    procedure RebuildHistory;
    procedure LayerAttributes(Sender: TObject; Layer: TArtLayer; Visible: Boolean; Opacity: Byte);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure ExitClick(Sender: TObject);
    procedure TreeChange(Sender: TObject);
    procedure LayerRename(Sender: TObject; Layer: TArtLayer; const Name: string);
    procedure PaintPreview(Sender: TObject);
    procedure CheckClose(Sender: TObject; var CanClose: Boolean);
    function ConfirmDiscard: Boolean;
    function RenderEditable: TBytes;
    procedure SetPreview(const RGBA: TBytes);
    procedure UpdateStatus;
    procedure RebuildTree;
  public
    constructor Create(AOwner: TComponent); override;
    constructor CreateWithHistory(AOwner: TComponent; const HistoryDirectory: string);
    property FileHistory: TArtFileHistory read FHistory;
    destructor Destroy; override;
    procedure NewFromPng(const FileName: string);
    procedure ImportPngFile(const FileName: string);
    procedure ReplaceSelectedPng(const FileName: string);
    procedure MoveSelectedLayer(X,Y: Integer);
    procedure OpenPsdFile(const FileName: string);
    procedure SavePsdFile(const FileName: string);
    procedure ApplySelectedLayer(const Name: string; Visible: Boolean; Opacity: Byte);
    property OpenDialog: TOpenDialog read FOpenDialog;
    property SaveDialog: TSaveDialog read FSaveDialog;
    property Document: TArtDocument read FDocument;
    property LayerList: TArtLayerList read FTree;
    property PreviewControl: TPaintBox read FPaint;
    property Modified: Boolean read FModified;
    property CanEdit: Boolean read FCanEdit;
  end;

var MainForm: TMainForm;

implementation

uses System.Math, System.IOUtils, System.UITypes, Winapi.Windows, ArtPsd, ArtPng, ArtLayerName;

{$R *.dfm}
type TArtPaintBoxAccess = class(TPaintBox);

constructor TMainForm.Create(AOwner: TComponent);
begin CreateWithHistory(AOwner,''); end;
constructor TMainForm.CreateWithHistory(AOwner: TComponent; const HistoryDirectory: string);
var RightPanel, StatusPanel, PositionPanel: TPanel; FileMenu, LayerMenu, Item: TMenuItem; LabelControl: TLabel;
    Splitter: TSplitter;
begin
  inherited Create(AOwner);
  FHistory := TArtFileHistory.Create(HistoryDirectory);
  FBitmap := Vcl.Graphics.TBitmap.Create;
  Menu := TMainMenu.Create(Self);
  FileMenu := TMenuItem.Create(Self); FileMenu.Caption := 'ファイル(&F)'; Menu.Items.Add(FileMenu);
  Item := TMenuItem.Create(Self); Item.Caption := '開く(&O)...'; Item.ShortCut := TextToShortCut('Ctrl+O');
  Item.OnClick := OpenClick; FileMenu.Add(Item);
  FSave := TMenuItem.Create(Self); FSave.Caption := '上書き保存(&S)'; FSave.ShortCut := TextToShortCut('Ctrl+S');
  FSave.OnClick := SaveClick; FSave.Enabled := False; FileMenu.Add(FSave);
  FSaveAs := TMenuItem.Create(Self); FSaveAs.Caption := '名前を付けて保存(&A)...';
  FSaveAs.ShortCut := TextToShortCut('Ctrl+Shift+S'); FSaveAs.OnClick := SaveAsClick;
  FSaveAs.Enabled := False; FileMenu.Add(FSaveAs);
  FClose := TMenuItem.Create(Self); FClose.Caption := '閉じる(&C)'; FClose.ShortCut := TextToShortCut('Ctrl+W');
  FClose.OnClick := CloseClick; FClose.Enabled := False; FileMenu.Add(FClose);
  Item := TMenuItem.Create(Self); Item.Caption := '-'; FileMenu.Add(Item);
  Item := TMenuItem.Create(Self); Item.Caption := '終了(&X)'; Item.OnClick := ExitClick; FileMenu.Add(Item);
  FHistoryMenu := TMenuItem.Create(Self); FHistoryMenu.Caption := '履歴(&H)'; FileMenu.Insert(4,FHistoryMenu);
  Item := TMenuItem.Create(Self); Item.Caption := 'PNGから新規作成(&N)...'; Item.ShortCut := TextToShortCut('Ctrl+N'); Item.OnClick := NewPngClick; FileMenu.Insert(1,Item);
  FImportItem := TMenuItem.Create(Self); FImportItem.Caption := 'PNGをレイヤーとして追加(&I)...'; FImportItem.ShortCut := TextToShortCut('Ctrl+I'); FImportItem.OnClick := ImportPngClick; FileMenu.Insert(2,FImportItem);
  LayerMenu := TMenuItem.Create(Self); LayerMenu.Caption := 'レイヤー(&L)'; Menu.Items.Add(LayerMenu);
  FReplaceItem := TMenuItem.Create(Self); FReplaceItem.Caption := '選択画像をPNGで置換(&R)...'; FReplaceItem.OnClick := ReplacePngClick; FReplaceItem.Enabled := False; LayerMenu.Add(FReplaceItem);
  FPositionItem := TMenuItem.Create(Self); FPositionItem.Caption := '配置座標を入力(&P)'; FPositionItem.OnClick := PositionClick; FPositionItem.Enabled := False; LayerMenu.Add(FPositionItem);
  RebuildHistory;
  StatusPanel := TPanel.Create(Self); StatusPanel.Parent := Self;
  StatusPanel.Align := alBottom; StatusPanel.Height := 75;
  FStatus := TLabel.Create(Self); FStatus.Parent := StatusPanel;
  FStatus.Align := alClient; FStatus.WordWrap := True; FStatus.Layout := tlCenter;
  FStatus.Caption := 'PSDを開くと、レイヤー階層と画像を表示します。';
  RightPanel := TPanel.Create(Self); RightPanel.Parent := Self; RightPanel.Align := alRight; RightPanel.Left := ClientWidth-420; RightPanel.Width := 420;
  PositionPanel := TPanel.Create(Self); PositionPanel.Parent := RightPanel; PositionPanel.Align := alBottom; PositionPanel.Height := 58;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := PositionPanel; LabelControl.SetBounds(8,7,30,18); LabelControl.Caption := 'X';
  FX := TSpinEdit.Create(Self); FX.Parent := PositionPanel; FX.SetBounds(25,4,95,26); FX.MinValue := -30000; FX.MaxValue := 30000; FX.Enabled := False;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := PositionPanel; LabelControl.SetBounds(128,7,25,18); LabelControl.Caption := 'Y';
  FY := TSpinEdit.Create(Self); FY.Parent := PositionPanel; FY.SetBounds(145,4,95,26); FY.MinValue := -30000; FY.MaxValue := 30000; FY.Enabled := False;
  FPositionApply := TButton.Create(Self); FPositionApply.Parent := PositionPanel; FPositionApply.SetBounds(250,3,95,28); FPositionApply.Caption := '配置を適用'; FPositionApply.Enabled := False; FPositionApply.OnClick := PositionClick;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := PositionPanel; LabelControl.SetBounds(8,34,400,18); LabelControl.Caption := '選択画像をプレビュー上でドラッグして配置できます。';
  FTree := TArtLayerList.Create(Self); FTree.Parent := RightPanel; FTree.Align := alClient;
  FTree.OnSelect := TreeChange; FTree.OnRename := LayerRename; FTree.OnAttributes := LayerAttributes;
  Splitter := TSplitter.Create(Self); Splitter.Parent := Self; Splitter.Align := alRight; Splitter.Left := ClientWidth-424;
  FPaint := TPaintBox.Create(Self); FPaint.Parent := Self; FPaint.Align := alClient;
  FPaint.OnPaint := PaintPreview; FPaint.OnMouseDown := PreviewMouseDown; FPaint.OnMouseMove := PreviewMouseMove; FPaint.OnMouseUp := PreviewMouseUp;
  FOpenDialog := TOpenDialog.Create(Self); FOpenDialog.Filter := 'Photoshop PSD (*.psd)|*.psd';
  FOpenDialog.Options := [ofFileMustExist,ofPathMustExist,ofEnableSizing,ofNoChangeDir];
  FSaveDialog := TSaveDialog.Create(Self); FSaveDialog.Filter := FOpenDialog.Filter;
  FSaveDialog.DefaultExt := 'psd'; FSaveDialog.Options := [ofOverwritePrompt,ofPathMustExist,ofEnableSizing,ofNoChangeDir];
  FPngDialog := TOpenDialog.Create(Self); FPngDialog.Filter := 'PNG画像 (*.png)|*.png'; FPngDialog.Options := [ofFileMustExist,ofPathMustExist,ofEnableSizing,ofNoChangeDir];
  OnCloseQuery := CheckClose;
end;

destructor TMainForm.Destroy;
begin
  if FTree<>nil then begin FTree.OnSelect := nil; FTree.SetRoots(nil); end;
  FDocument.Free; FBitmap.Free; FHistory.Free;
  inherited;
end;

function TMainForm.ConfirmDiscard: Boolean;
begin
  Result := not FModified;
  if not Result then
    case MessageDlg('変更を保存してから続けますか？'+sLineBreak+'「いいえ」は変更を破棄します。',mtConfirmation,[mbYes,mbNo,mbCancel],0) of
      mrYes: begin SaveClick(Self); Result := not FModified; end;
      mrNo: Result := True;
    else Result := False; end;
end;

procedure TMainForm.CheckClose(Sender: TObject; var CanClose: Boolean);
begin CanClose := ConfirmDiscard; end;

function TMainForm.RenderEditable: TBytes;
begin Result := RenderPsdLayers(FDocument); end;

procedure TMainForm.SetPreview(const RGBA: TBytes);
var X,Y,P,C,Base,A,Value: Integer; Row: PByte;
begin
  FBitmap.PixelFormat := pf32bit; FBitmap.SetSize(FDocument.Width,FDocument.Height);
  for Y := 0 to FDocument.Height-1 do begin
    Row := FBitmap.ScanLine[Y];
    for X := 0 to FDocument.Width-1 do begin
      P := (Y*FDocument.Width+X)*4; A := RGBA[P+3];
      if ((X div 12+Y div 12) mod 2)=0 then Base := 225 else Base := 175;
      for C := 0 to 2 do begin
        Value := (RGBA[P+C]*A+Base*(255-A)+127) div 255;
        Row[X*4+2-C] := Value;
      end;
      Row[X*4+3] := 255;
    end;
  end;
  FPaint.Invalidate;
end;

procedure TMainForm.NewFromPng(const FileName: string);
var Image: TArtPngData; NewDoc,Old: TArtDocument; L: TArtLayer; RGBA: TBytes;
begin
  Image := ReadPng(FileName); NewDoc := TArtDocument.Create;
  try
    NewDoc.Width := Image.Width; NewDoc.Height := Image.Height;
    L := NewDoc.AddLayer(alkImage,ChangeFileExt(ExtractFileName(FileName),''),TArtBounds.Create(0,0,Image.Width,Image.Height)); L.Pixels := Image.Pixels;
    RGBA := NewDoc.RenderRGBA;
  except NewDoc.Free; raise; end;
  Old := FDocument; FDocument := NewDoc;
  try SetPreview(RGBA); except FDocument := Old; NewDoc.Free; raise; end;
  FTree.SetRoots(nil); Old.Free; FFileName := ''; FModified := True; FCanEdit := True;
  FSave.Enabled := True; FSaveAs.Enabled := True; FClose.Enabled := True; RebuildTree; UpdateStatus;
end;
procedure TMainForm.ImportPngFile(const FileName: string);
var Image: TArtPngData; Parent,Selected,L: TArtLayer; List: TList<TArtLayer>; Index: Integer;
  function Find(List: TList<TArtLayer>; Target: TArtLayer; out Parent: TArtLayer): Boolean;
  var Item: TArtLayer;
  begin
    Result := False;
    for Item in List do begin
      if Item.Children.Contains(Target) then begin Parent := Item; Exit(True); end;
      if Find(Item.Children,Target,Parent) then Exit(True);
    end;
  end;
begin
  if FDocument=nil then begin NewFromPng(FileName); Exit; end;
  if not FCanEdit then raise EArtFormat.Create('この文書へのPNG追加は未対応です。');
  FTree.FinishRename(True); Image := ReadPng(FileName); Selected := FTree.Selected; Parent := nil;
  if Selected<>nil then begin
    if Selected.Kind=alkGroup then Parent := Selected else Find(FDocument.Roots,Selected,Parent);
  end;
  if Parent=nil then List := FDocument.Roots else List := Parent.Children;
  Index := List.IndexOf(Selected); if Index<0 then Index := 0;
  L := FDocument.AddLayer(alkImage,ChangeFileExt(ExtractFileName(FileName),''),TArtBounds.Create(0,0,Image.Width,Image.Height),Parent);
  L.Pixels := Image.Pixels; List.Remove(L); List.Insert(Index,L);
  try SetPreview(RenderEditable);
  except FDocument.RemoveNewLayer(L); raise; end;
  FModified := True; RebuildTree; FTree.Selected := L; FTree.RevealSelected; UpdateStatus;
end;
procedure TMainForm.ReplaceSelectedPng(const FileName: string);
var Image: TArtPngData; L: TArtLayer; OldPixels: TBytes; OldBounds,NewBounds: TArtBounds;
begin
  if not FCanEdit or (FTree.Selected=nil) or (FTree.Selected.Kind<>alkImage) then raise EArtFormat.Create('置換する画像レイヤーを選択してください。');
  FTree.FinishRename(True); Image := ReadPng(FileName); L := FTree.Selected;
  OldPixels := L.Pixels; OldBounds := L.Bounds;
  NewBounds := TArtBounds.Create(OldBounds.Left,OldBounds.Top,OldBounds.Left+Image.Width,OldBounds.Top+Image.Height);
  L.Pixels := Image.Pixels; L.Bounds := NewBounds;
  try SetPreview(RenderEditable);
  except L.Pixels := OldPixels; L.Bounds := OldBounds; raise; end;
  FModified := True; FTree.RefreshImages; TreeChange(Self); UpdateStatus;
end;
procedure TMainForm.MoveSelectedLayer(X,Y: Integer);
var L: TArtLayer; OldBounds,OldMask,NewBounds,NewMask: TArtBounds; DX,DY: Integer;
begin
  if not FCanEdit or (FTree.Selected=nil) or (FTree.Selected.Kind<>alkImage) then raise EArtFormat.Create('配置する画像レイヤーを選択してください。');
  if (X<-30000) or (X>30000) or (Y<-30000) or (Y>30000) then raise EArtFormat.Create('配置座標は-30000～30000です。');
  L := FTree.Selected; OldBounds := L.Bounds; OldMask := L.MaskBounds;
  if (OldBounds.Left=X) and (OldBounds.Top=Y) then Exit;
  DX := X-OldBounds.Left; DY := Y-OldBounds.Top;
  NewBounds := TArtBounds.Create(X,Y,X+OldBounds.Width,Y+OldBounds.Height); NewMask := OldMask;
  if L.HasMask then NewMask := TArtBounds.Create(OldMask.Left+DX,OldMask.Top+DY,OldMask.Right+DX,OldMask.Bottom+DY);
  L.Bounds := NewBounds; L.MaskBounds := NewMask;
  try SetPreview(RenderEditable);
  except L.Bounds := OldBounds; L.MaskBounds := OldMask; raise; end;
  FModified := True; TreeChange(Self); UpdateStatus;
end;
procedure TMainForm.NewPngClick(Sender: TObject);
begin
  if not ConfirmDiscard then Exit;
  if FPngDialog.Execute then try NewFromPng(FPngDialog.FileName); except on E: Exception do MessageDlg(E.Message,mtError,[mbOK],0); end;
end;
procedure TMainForm.ImportPngClick(Sender: TObject);
begin
  if FPngDialog.Execute then try ImportPngFile(FPngDialog.FileName); except on E: Exception do MessageDlg(E.Message,mtError,[mbOK],0); end;
end;
procedure TMainForm.ReplacePngClick(Sender: TObject);
begin
  if FPngDialog.Execute then try ReplaceSelectedPng(FPngDialog.FileName); except on E: Exception do MessageDlg(E.Message,mtError,[mbOK],0); end;
end;
procedure TMainForm.PositionClick(Sender: TObject);
begin
  if Sender=FPositionItem then begin FX.SetFocus; FX.SelectAll; Exit; end;
  try MoveSelectedLayer(FX.Value,FY.Value); except on E: Exception do MessageDlg(E.Message,mtError,[mbOK],0); end;
end;

procedure TMainForm.OpenPsdFile(const FileName: string);
var NewDoc,OldDoc: TArtDocument; RGBA: TBytes; P,C,A,Value: Integer; NewCanEdit: Boolean;
begin
  Screen.Cursor := crHourGlass;
  try
    NewDoc := ReadPsd(FileName); OldDoc := FDocument; FDocument := NewDoc;
    try
      NewCanEdit := True;
      try RGBA := RenderEditable; except on E: EArtFormat do begin
        NewCanEdit := False;
        SetLength(RGBA,PixelByteCount(NewDoc.Width,NewDoc.Height,4));
        for P := 0 to Length(RGBA) div 4-1 do begin
          A := 255;
          if NewDoc.MergedHasTransparency and (Length(NewDoc.MergedPlanes)>=4) then A := NewDoc.MergedPlanes[3][P];
          for C := 0 to 2 do begin
            Value := NewDoc.MergedPlanes[C][P];
            if A=0 then Value := 0
            else if A<255 then Value := EnsureRange((Value*255-255*(255-A)+A div 2) div A,0,255);
            RGBA[P*4+C] := Value;
          end;
          RGBA[P*4+3] := A;
        end;
      end; end;
      SetPreview(RGBA);
    except FDocument := OldDoc; NewDoc.Free; raise; end;
    // Nodes hold document pointers: clear them before releasing the previous document.
    FTree.SetRoots(nil); OldDoc.Free; FFileName := TPath.GetFullPath(FileName);
    FCanEdit := NewCanEdit; FModified := False; FSave.Enabled := True; FSaveAs.Enabled := True; FClose.Enabled := True;
    RebuildTree; UpdateStatus;
    if not FLoadingSaved then begin
      try FHistory.AddFile(FFileName); except on E: Exception do FStatus.Caption := FStatus.Caption+sLineBreak+'履歴保存失敗: '+E.Message; end;
      RebuildHistory;
    end;
  finally Screen.Cursor := crDefault; end;
end;

procedure TMainForm.RebuildTree;
begin FTree.EditEnabled := FCanEdit; FTree.SetRoots(FDocument.Roots); end;

procedure TMainForm.TreeChange(Sender: TObject);
var L: TArtLayer; CanImage: Boolean;
begin
  L := FTree.Selected; CanImage := FCanEdit and (L<>nil) and (L.Kind=alkImage);
  FReplaceItem.Enabled := CanImage; FPositionItem.Enabled := CanImage; FX.Enabled := CanImage; FY.Enabled := CanImage; FPositionApply.Enabled := CanImage;
  FImportItem.Enabled := (FDocument=nil) or FCanEdit;
  if CanImage then begin FX.Value := L.Bounds.Left; FY.Value := L.Bounds.Top; end;
  if FPaint<>nil then begin TArtPaintBoxAccess(FPaint).MouseCapture := False; FPaint.Invalidate; end; FDragging := False;
end;
procedure TMainForm.LayerAttributes(Sender: TObject; Layer: TArtLayer; Visible: Boolean; Opacity: Byte);
begin
  if Layer<>FTree.Selected then raise EArtFormat.Create('Selection changed during attributes edit');
  ApplySelectedLayer(Layer.Name,Visible,Opacity);
end;
procedure TMainForm.RebuildHistory;
  procedure Populate(Menu: TMenuItem; List: TStringList);
  var I: Integer; Item: TMenuItem;
  begin
    Menu.Clear;
    for I := 0 to List.Count-1 do begin
      Item := TMenuItem.Create(Self); Item.Caption := StringReplace(List[I],'&','&&',[rfReplaceAll]);
      Item.Hint := List[I]; Item.OnClick := HistoryClick; Menu.Add(Item);
    end;
    if Menu.Count=0 then begin
      Item := TMenuItem.Create(Self); Item.Caption := '（履歴なし）'; Item.Enabled := False; Menu.Add(Item);
    end;
  end;
begin Populate(FHistoryMenu,FHistory.Files); end;
procedure TMainForm.HistoryClick(Sender: TObject);
var FileName: string;
begin
  FileName := TMenuItem(Sender).Hint;
  if not ConfirmDiscard then Exit;
  try OpenPsdFile(FileName);
  except on E: Exception do MessageDlg('PSDを開けませんでした。'+sLineBreak+E.Message,mtError,[mbOK],0); end;
end;

procedure TMainForm.LayerRename(Sender: TObject; Layer: TArtLayer; const Name: string);
begin
  if Layer<>FTree.Selected then raise EArtFormat.Create('Selection changed during rename');
  ApplySelectedLayer(Name,Layer.Visible,Layer.Opacity); TreeChange(Self);
end;

procedure TMainForm.ApplySelectedLayer(const Name: string; Visible: Boolean; Opacity: Byte);
var L: TArtLayer; OldName: string; OldVisible: Boolean; OldOpacity: Byte; Pixels: TBytes;
begin
  if not FCanEdit or (FTree.Selected=nil) then raise EArtFormat.Create('このPSDは表示・変更なし保存のみ対応しています。');
  L := FTree.Selected; OldName := L.Name; OldVisible := L.Visible; OldOpacity := L.Opacity;
  if (Name=OldName) and (Visible=OldVisible) and (Opacity=OldOpacity) then Exit;
  L.Name := Name; L.Visible := Visible; L.Opacity := Opacity;
  try Pixels := RenderEditable; SetPreview(Pixels);
  except L.Name := OldName; L.Visible := OldVisible; L.Opacity := OldOpacity; raise; end;
  FModified := True;
  FTree.RefreshLayerNames;
  UpdateStatus;
end;

procedure TMainForm.UpdateStatus;
var Mode,Star: string;
begin
  if FModified then Star := ' *' else Star := '';
  if FFileName='' then Caption := 'AI立ち絵メーカー - 新規文書'+Star
  else Caption := 'AI立ち絵メーカー - '+ExtractFileName(FFileName)+Star;
  if FCanEdit then Mode := '編集プレビュー：PNG追加・置換、画像の配置、名前・表示・不透明度を変更できます。'
  else Mode := '元の合成画像：編集非対応。変更なしの別名保存ができます。 '+FDocument.Unsupported.Text;
  FStatus.Caption := Format('%d × %d  /  %dレイヤー  %s',[FDocument.Width,FDocument.Height,FTree.RowCount,Mode]);
  FStatus.Hint := FStatus.Caption; FStatus.ShowHint := True;
end;

procedure TMainForm.SavePsdFile(const FileName: string);
var Path: TArray<Integer>; Selected: TArtLayer; List: TList<TArtLayer>; Index: Integer;
  function FindPath(List: TList<TArtLayer>): Boolean;
  var I: Integer;
  begin
    Result := False;
    for I := 0 to List.Count-1 do begin
      SetLength(Path,Length(Path)+1); Path[High(Path)] := I;
      if (List[I]=Selected) or FindPath(List[I].Children) then Exit(True);
      SetLength(Path,Length(Path)-1);
    end;
  end;
begin
  if FDocument=nil then raise EArtFormat.Create('PSDを開いてください。');
  FTree.FinishRename(True); Selected := FTree.Selected; FindPath(FDocument.Roots);
  Screen.Cursor := crHourGlass;
  try
    if Length(FDocument.SourceBytes)=0 then WriteNewPsd(FDocument,FileName,pcRle)
    else if FModified then begin
      try SaveLayerPropertiesPsd(FDocument,FileName);
      except on E: EArtFormat do SaveImageCompositionPsd(FDocument,FileName); end;
    end
    else SaveUnchangedPsd(FDocument,FileName);
  finally Screen.Cursor := crDefault; end;
  // Reload the successful save to establish the new source baseline.
  FLoadingSaved := True;
  try OpenPsdFile(FileName); finally FLoadingSaved := False; end;
  Selected := nil; List := FDocument.Roots;
  for Index in Path do begin
    if (Index<0) or (Index>=List.Count) then begin Selected := nil; Break; end;
    Selected := List[Index]; List := Selected.Children;
  end;
  if Selected<>nil then begin FTree.Selected := Selected; FTree.RevealSelected; end;
  try FHistory.AddFile(FFileName); except on E: Exception do FStatus.Caption := FStatus.Caption+sLineBreak+'履歴保存失敗: '+E.Message; end;
  RebuildHistory;
end;

procedure TMainForm.OpenClick(Sender: TObject);
begin
  if not ConfirmDiscard then Exit;
  if FOpenDialog.Execute then
    try OpenPsdFile(FOpenDialog.FileName); except on E: Exception do MessageDlg('PSDを開けませんでした。'+sLineBreak+E.Message,mtError,[mbOK],0); end;
end;

procedure TMainForm.SaveClick(Sender: TObject);
begin
  if FDocument=nil then Exit;
  if FFileName='' then begin SaveAsClick(Sender); Exit; end;
  try SavePsdFile(FFileName);
  except on E: Exception do MessageDlg('保存できませんでした。'+sLineBreak+E.Message,mtError,[mbOK],0); end;
end;

procedure TMainForm.CloseClick(Sender: TObject);
begin
  if not ConfirmDiscard then Exit;
  FCanEdit := False; FTree.SetRoots(nil); FreeAndNil(FDocument);
  FBitmap.SetSize(0,0); FPaint.Invalidate; FFileName := ''; FModified := False;
  FSave.Enabled := False; FSaveAs.Enabled := False; FClose.Enabled := False;
  TreeChange(Self); Caption := 'AI立ち絵メーカー';
  FStatus.Caption := 'ファイル → 開く でPSDを選択してください。'; FStatus.Hint := '';
end;

procedure TMainForm.ExitClick(Sender: TObject);
begin Close; end;

procedure TMainForm.SaveAsClick(Sender: TObject);
begin
  if FFileName='' then FSaveDialog.FileName := '立ち絵.psd'
  else FSaveDialog.FileName := ChangeFileExt(ExtractFileName(FFileName),'')+'_編集.psd';
  if FSaveDialog.Execute then
    try SavePsdFile(FSaveDialog.FileName); except on E: Exception do MessageDlg('保存できませんでした。'+sLineBreak+E.Message,mtError,[mbOK],0); end;
end;

function TMainForm.PreviewRect: TRect;
var Scale: Double; W,H: Integer;
begin
  Result := Rect(0,0,0,0); if FBitmap.Empty then Exit;
  Scale := Min(FPaint.Width/FBitmap.Width,FPaint.Height/FBitmap.Height);
  W := Max(1,Round(FBitmap.Width*Scale)); H := Max(1,Round(FBitmap.Height*Scale));
  Result := Rect((FPaint.Width-W) div 2,(FPaint.Height-H) div 2,(FPaint.Width+W) div 2,(FPaint.Height+H) div 2);
end;
procedure TMainForm.PreviewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
var L: TArtLayer; R: TRect;
begin
  L := FTree.Selected; if (Button<>mbLeft) or not FCanEdit or (L=nil) or (L.Kind<>alkImage) then Exit;
  R := PreviewRect; if not PtInRect(R,Point(X,Y)) then Exit;
  FTree.FinishRename(True); FDragStart := Point(X,Y); FDragX := L.Bounds.Left; FDragY := L.Bounds.Top;
  FDragDX := 0; FDragDY := 0; FDragging := True; TArtPaintBoxAccess(FPaint).MouseCapture := True;
end;
procedure TMainForm.PreviewMouseMove(Sender: TObject; Shift: TShiftState; X,Y: Integer);
var R: TRect;
begin
  if not FDragging then Exit; R := PreviewRect; if (R.Width<=0) or (R.Height<=0) then Exit;
  FDragDX := Round((X-FDragStart.X)*FDocument.Width/R.Width); FDragDY := Round((Y-FDragStart.Y)*FDocument.Height/R.Height); FPaint.Invalidate;
end;
procedure TMainForm.PreviewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin
  if (Button<>mbLeft) or not FDragging then Exit;
  PreviewMouseMove(Sender,Shift,X,Y); FDragging := False; TArtPaintBoxAccess(FPaint).MouseCapture := False;
  try MoveSelectedLayer(EnsureRange(FDragX+FDragDX,-30000,30000),EnsureRange(FDragY+FDragDY,-30000,30000));
  except on E: Exception do MessageDlg(E.Message,mtError,[mbOK],0); end;
  FPaint.Invalidate;
end;

procedure TMainForm.PaintPreview(Sender: TObject);
var Scale: Double; W,H,X,Y,DX,DY: Integer; L: TArtLayer; R: TRect;
begin
  FPaint.Canvas.Brush.Color := clGray; FPaint.Canvas.FillRect(FPaint.ClientRect);
  if FBitmap.Empty then Exit;
  Scale := Min(FPaint.Width/FBitmap.Width,FPaint.Height/FBitmap.Height);
  W := Max(1,Round(FBitmap.Width*Scale)); H := Max(1,Round(FBitmap.Height*Scale));
  X := (FPaint.Width-W) div 2; Y := (FPaint.Height-H) div 2;
  FPaint.Canvas.StretchDraw(Rect(X,Y,X+W,Y+H),FBitmap);
  L := FTree.Selected;
  if FCanEdit and (L<>nil) and (L.Kind=alkImage) then begin
    DX := 0; DY := 0; if FDragging then begin DX := FDragDX; DY := FDragDY; end;
    R := Rect(X+Round((L.Bounds.Left+DX)*Scale),Y+Round((L.Bounds.Top+DY)*Scale),X+Round((L.Bounds.Right+DX)*Scale),Y+Round((L.Bounds.Bottom+DY)*Scale));
    FPaint.Canvas.Brush.Style := bsClear; FPaint.Canvas.Pen.Color := $FFD080; FPaint.Canvas.Pen.Style := psDash; FPaint.Canvas.Rectangle(R); FPaint.Canvas.Pen.Style := psSolid; FPaint.Canvas.Brush.Style := bsSolid;
  end;
end;

end.

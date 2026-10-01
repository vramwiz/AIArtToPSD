unit AIArtToPSDMainForm;

interface

uses System.Types, System.Classes, System.SysUtils, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Dialogs, Vcl.Menus, Vcl.Samples.Spin, Vcl.Graphics, ArtDocument, ArtLayerList, ArtFileHistory, DarkComboBox, ArtExchange, ArtUndo, ArtPipeBridge, ArtPipeProtocol, System.JSON;

type
  TMainForm = class(TForm)
  private
    FExchange: TArtExchange;
    FUndo: TArtUndo;
    FPipe: TArtPipeBridge;
    FProtocol: TArtPipeProtocol;
    FCurrentJobId,FOperation: string;
    FBusy: Boolean;
    FActivity: TLabel;
    FCancelAi: TButton;
    FUndoItem,FRedoItem: TMenuItem;
    FPrompt: TMemo;
    FJobPath: TEdit;
    FExportAi, FImportAi: TButton;
    FResultDialog,FRecoveryDialog: TOpenDialog;
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
    FPartGroup, FPartChoice: TDarkComboBox;
    FGroupItem: TMenuItem;
    FUpdatingParts: Boolean;
    FZoom, FPanX, FPanY: Double;
    FDragging: Boolean;
    FDragStart: TPoint;
    procedure PreviewWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    function DispatchCommand(const Command: string; Args: TJSONObject): TJSONObject;
    function JobJson(Job: TArtExchangeJob): TJSONObject;
    procedure UpdateActivity;
    procedure BeginOperation(const Name: string);
    procedure EndOperation;
    procedure BeginEdit;
    procedure CommitEdit;
    procedure RestoreEdit(Redo: Boolean);
    procedure UndoClick(Sender: TObject);
    procedure RedoClick(Sender: TObject);
    procedure CancelAiClick(Sender: TObject);
    procedure RecoverAiClick(Sender: TObject);
    procedure ResetAiJobs;
    procedure ExportAiClick(Sender: TObject);
    procedure ImportAiClick(Sender: TObject);
    procedure UpdateParts;
    procedure PartGroupChange(Sender: TObject);
    procedure PartChoiceChange(Sender: TObject);
    procedure GroupClick(Sender: TObject);
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
    function ExportAiJob(const Prompt,Root: string; Workspace: TJSONObject = nil): string;
    function PipeName: string;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    procedure Undo;
    procedure Redo;
    procedure CancelAiJob(const Id: string);
    property Busy: Boolean read FBusy;
    property ActivityControl: TLabel read FActivity;
    procedure ImportAiResult(const FileName: string);
    procedure RecoverAiJob(const Directory: string);
    property PromptControl: TMemo read FPrompt;
    property AiJobPathControl: TEdit read FJobPath;
    procedure CreateGroup(const Name: string; Exclusive: Boolean);
    procedure SelectPart(Layer: TArtLayer);
    property PartGroupControl: TDarkComboBox read FPartGroup;
    property PartChoiceControl: TDarkComboBox read FPartChoice;
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
    property PreviewBounds: TRect read PreviewRect;
    property Modified: Boolean read FModified;
    property CanEdit: Boolean read FCanEdit;
  end;

var MainForm: TMainForm;

implementation

uses System.Math, System.IOUtils, System.UITypes, Winapi.Windows, ArtPsd, ArtPng, ArtLayerName, ArtParts;

{$R *.dfm}
type
  TArtPaintBoxAccess = class(TPaintBox);
  TArtPreviewPaintBox = class(TPaintBox)
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TArtPreviewPaintBox.Create(AOwner: TComponent);
begin
  inherited;
  // PaintPreview covers every pixel; avoid erasing the background before it.
  ControlStyle := ControlStyle+[csOpaque];
end;

function TMainForm.PipeName: string;
begin if FPipe=nil then Result := '' else Result := FPipe.Name; end;
function TMainForm.CanUndo: Boolean;
begin Result := not FBusy and FCanEdit and FUndo.CanUndo; end;
function TMainForm.CanRedo: Boolean;
begin Result := not FBusy and FCanEdit and FUndo.CanRedo; end;
procedure TMainForm.BeginEdit;
var Id: string;
begin
  Id := ''; if FTree.Selected<>nil then Id := FTree.Selected.Id;
  FUndo.BeginEdit(FDocument,Id,FModified);
end;
procedure TMainForm.CommitEdit;
begin FUndo.CommitEdit; end;
procedure TMainForm.RestoreEdit(Redo: Boolean);
var Target,Current: TArtEditState; Candidate,Old: TArtDocument; Pixels: TBytes; L: TArtLayer; Selection: string;
begin
  if FBusy or not FCanEdit then raise EArtFormat.Create('今は元に戻せません。');
  FTree.FinishRename(True); Target := FUndo.Peek(Redo);
  Candidate := Target.Document.Clone; Current := nil;
  try
    // Restoring old content must never reuse an old revision number.
    Candidate.Revision := FDocument.Revision; Candidate.Changed;
    Pixels := RenderPsdLayers(Candidate); Selection := '';
    if FTree.Selected<>nil then Selection := FTree.Selected.Id;
    Current := TArtEditState.Create(FDocument,Selection,FModified);
  except Candidate.Free; Current.Free; raise; end;
  Old := FDocument; FDocument := Candidate;
  try SetPreview(Pixels); except FDocument := Old; Candidate.Free; Current.Free; raise; end;
  FTree.SetRoots(nil); Old.Free; FModified := Target.Modified; Selection := Target.SelectedId;
  FUndo.CommitRestore(Current,Redo); ResetAiJobs; RebuildTree;
  L := FDocument.FindLayer(Selection); if L<>nil then begin FTree.Selected := L; FTree.RevealSelected; end;
  UpdateStatus;
end;
procedure TMainForm.Undo;
begin RestoreEdit(False); end;
procedure TMainForm.Redo;
begin RestoreEdit(True); end;
procedure TMainForm.UndoClick(Sender: TObject);
begin try Undo; except on E: Exception do MessageDlg(E.Message,mtError,[mbOK],0); end; end;
procedure TMainForm.RedoClick(Sender: TObject);
begin try Redo; except on E: Exception do MessageDlg(E.Message,mtError,[mbOK],0); end; end;
procedure TMainForm.BeginOperation(const Name: string);
begin
  if FBusy then raise EArtFormat.Create('別の処理を実行中です。');
  FBusy := True; FOperation := Name; Screen.Cursor := crHourGlass;
  UpdateActivity; FActivity.Update;
end;
procedure TMainForm.EndOperation;
begin FBusy := False; FOperation := ''; Screen.Cursor := crDefault; UpdateActivity; end;
procedure TMainForm.UpdateActivity;
var Job: TArtExchangeJob; StateText: string;
begin
  if FTree<>nil then FTree.VisibilityEnabled := not FBusy and FCanEdit and (FDocument<>nil);
  if FActivity=nil then Exit;
  StateText := '待機中';
  if FBusy then StateText := FOperation
  else if FCurrentJobId<>'' then begin
    Job := FExchange.FindJob(FCurrentJobId);
    if Job.State='queued' then StateText := 'AI生成待ち'
    else if Job.State='running' then StateText := 'AI生成中'
    else if Job.State='ready' then StateText := '生成完了・取込待ち'
    else if Job.State='failed' then StateText := 'AI処理失敗'
    else if Job.State='cancelled' then StateText := 'AI処理を中止しました'
    else StateText := '取込完了';
    if (Job.State<>'completed') and (Job.State<>'cancelled') and (FDocument<>nil) and (FDocument.Revision<>Job.Revision) then StateText := '文書が変更されています・新しいAIジョブを書き出してください';
    StateText := StateText+Format(' (%d%%) %s',[Job.Progress,Job.MessageText]);
  end;
  if (FPrompt<>nil) and (FActivity.Caption<>StateText) then FPrompt.Lines.Add('AI: '+StateText);
  FActivity.Caption := StateText;
  FActivity.Hint := '接続先: \\.\pipe\'+PipeName; FActivity.ShowHint := True;
  if FUndoItem<>nil then FUndoItem.Enabled := CanUndo;
  if FRedoItem<>nil then FRedoItem.Enabled := CanRedo;
  if FCancelAi<>nil then begin
    FCancelAi.Enabled := not FBusy and (FCurrentJobId<>'');
    if FCancelAi.Enabled then begin
      Job := FExchange.FindJob(FCurrentJobId);
      FCancelAi.Enabled := (Job.State<>'completed') and (Job.State<>'cancelled');
    end;
  end;
end;
procedure TMainForm.CancelAiJob(const Id: string);
var Job: TArtExchangeJob;
begin
  if FBusy then raise EArtFormat.Create('処理中です。');
  Job := FExchange.FindJob(Id);
  // Cancellation also works after local edits have made the result stale.
  if Job.State='completed' then raise EArtFormat.Create('取り込み済みです。Undoで戻してください。');
  FExchange.CancelJob(Id); UpdateActivity;
end;
procedure TMainForm.CancelAiClick(Sender: TObject);
begin try CancelAiJob(FCurrentJobId); except on E: Exception do MessageDlg(E.Message,mtError,[mbOK],0); end; end;
function TMainForm.JobJson(Job: TArtExchangeJob): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jobId',Job.Id); Result.AddPair('directory',Job.Directory); Result.AddPair('state',Job.State);
  Result.AddPair('progress',TJSONNumber.Create(Job.Progress)); Result.AddPair('message',Job.MessageText);
  Result.AddPair('documentId',Job.DocumentId); Result.AddPair('ifRevision',UIntToStr(Job.Revision));
  Result.AddPair('stale',TJSONBool.Create((Job.State<>'completed') and ((FDocument=nil) or (FDocument.SessionId<>Job.DocumentId) or (FDocument.Revision<>Job.Revision))));
end;
function TMainForm.DispatchCommand(const Command: string; Args: TJSONObject): TJSONObject;
var Id,Path: string; Job: TArtExchangeJob;
begin
  if FBusy then raise EArtFormat.Create('Application is busy');
  if Command='status' then begin
    Result := TJSONObject.Create;
    Result.AddPair('pipeName',PipeName); Result.AddPair('busy',TJSONBool.Create(FBusy));
    Result.AddPair('canUndo',TJSONBool.Create(CanUndo)); Result.AddPair('canRedo',TJSONBool.Create(CanRedo));
    Result.AddPair('modified',TJSONBool.Create(FModified)); Result.AddPair('canEdit',TJSONBool.Create(FCanEdit));
    if FDocument<>nil then begin Result.AddPair('documentId',FDocument.SessionId); Result.AddPair('revision',UIntToStr(FDocument.Revision)); end;
    Id := FCurrentJobId; if Args.GetValue('jobId')<>nil then Id := CommandString(Args,'jobId');
    if Id<>'' then begin
      try Result.AddPair('job',JobJson(FExchange.FindJob(Id)));
      except Result.Free; raise; end;
    end;
    Exit;
  end;
  if Command='export' then begin
    if (Args.GetValue('workspace')<>nil) and not (Args.GetValue('workspace') is TJSONObject) then
      raise EArtFormat.Create('Workspace object expected');
    Path := ExportAiJob(CommandString(Args,'prompt'),TPath.Combine(ExtractFilePath(ParamStr(0)),'Exchange'),
      TJSONObject(Args.GetValue('workspace')));
    Exit(JobJson(FExchange.FindJob(ExtractFileName(Path))));
  end;
  if Command='recover' then begin
    if FModified then raise EArtFormat.Create('Save or discard the current document before recovery');
    RecoverAiJob(CommandString(Args,'directory')); Exit(JobJson(FExchange.FindJob(FCurrentJobId)));
  end;
  if Command='undo' then begin Undo; Exit(TJSONObject.Create); end;
  if Command='redo' then begin Redo; Exit(TJSONObject.Create); end;
  Id := CommandString(Args,'jobId'); Job := FExchange.FindJob(Id);
  if Command='import' then ImportAiResult(TPath.Combine(Job.Directory,'result.json'))
  else if Command='progress' then FExchange.NotifyJob(FDocument,Id,CommandString(Args,'state'),CommandString(Args,'message'),CommandInteger(Args,'progress'))
  else if Command='cancel' then CancelAiJob(Id)
  else raise EArtFormat.Create('Unknown command: '+Command);
  UpdateActivity; Result := JobJson(Job);
end;
constructor TMainForm.Create(AOwner: TComponent);
begin CreateWithHistory(AOwner,''); end;
constructor TMainForm.CreateWithHistory(AOwner: TComponent; const HistoryDirectory: string);
var RightPanel, StatusPanel, PositionPanel, PartsPanel, AiPanel, AiButtons, PreviewPanel: TPanel; FileMenu, LayerMenu, Item: TMenuItem; LabelControl: TLabel;
    Splitter: TSplitter; EditMenu: TMenuItem;
begin
  inherited Create(AOwner);
  FHistory := TArtFileHistory.Create(HistoryDirectory);
  FExchange := TArtExchange.Create; FUndo := TArtUndo.Create;
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
  Item := TMenuItem.Create(Self); Item.Caption := 'PNGから新規作成(&N)...'; Item.ShortCut := TextToShortCut('Ctrl+N'); Item.OnClick := NewPngClick;
  FImportItem := TMenuItem.Create(Self); FImportItem.Caption := 'PNGをレイヤーとして追加(&I)...'; FImportItem.ShortCut := TextToShortCut('Ctrl+I'); FImportItem.OnClick := ImportPngClick;
  LayerMenu := TMenuItem.Create(Self); LayerMenu.Caption := 'レイヤー(&L)';
  FReplaceItem := TMenuItem.Create(Self); FReplaceItem.Caption := '選択画像をPNGで置換(&R)...'; FReplaceItem.OnClick := ReplacePngClick; FReplaceItem.Enabled := False; LayerMenu.Add(FReplaceItem);
  FPositionItem := TMenuItem.Create(Self); FPositionItem.Caption := '配置座標を入力(&P)'; FPositionItem.OnClick := PositionClick; FPositionItem.Enabled := False; LayerMenu.Add(FPositionItem);
  FGroupItem := TMenuItem.Create(Self); FGroupItem.Caption := 'グループを作成(&G)...'; FGroupItem.OnClick := GroupClick; FGroupItem.Enabled := False; LayerMenu.Add(FGroupItem);
  EditMenu := TMenuItem.Create(Self); EditMenu.Caption := '編集(&E)';
  FUndoItem := TMenuItem.Create(Self); FUndoItem.Caption := '元に戻す(&U)'; FUndoItem.ShortCut := TextToShortCut('Ctrl+Z'); FUndoItem.OnClick := UndoClick; FUndoItem.Enabled := False; EditMenu.Add(FUndoItem);
  FRedoItem := TMenuItem.Create(Self); FRedoItem.Caption := 'やり直す(&R)'; FRedoItem.ShortCut := TextToShortCut('Ctrl+Y'); FRedoItem.OnClick := RedoClick; FRedoItem.Enabled := False; EditMenu.Add(FRedoItem);
  Item := TMenuItem.Create(Self); Item.Caption := 'AIジョブを再開...'; Item.OnClick := RecoverAiClick;
  RebuildHistory;
  // Keep legacy API control objects for existing integration callers; hide their panels.
  // The visible UI consists only of preview, read-only layers and the AI transcript.
  StatusPanel := TPanel.Create(Self); StatusPanel.Parent := Self; StatusPanel.Visible := False;
  StatusPanel.Align := alNone; StatusPanel.Height := 75;
  FStatus := TLabel.Create(Self); FStatus.Parent := StatusPanel;
  FStatus.Align := alClient; FStatus.WordWrap := True; FStatus.Layout := tlCenter;
  FStatus.Caption := 'PSDを開くと、レイヤー階層と画像を表示します。';
  FActivity := TLabel.Create(Self); FActivity.Parent := StatusPanel; FActivity.Align := alBottom; FActivity.Height := 20;
  AiPanel := TPanel.Create(Self); AiPanel.Parent := Self; AiPanel.Align := alBottom; AiPanel.Height := 148;
  FJobPath := TEdit.Create(Self);  FJobPath.Align := alBottom; FJobPath.ReadOnly := True; FJobPath.Text := 'AIジョブのフォルダーがここに表示されます。';
  LabelControl := TLabel.Create(Self); LabelControl.Parent := AiPanel; LabelControl.Align := alTop; LabelControl.Caption := 'AIとのやりとり';
  AiButtons := TPanel.Create(Self); AiButtons.Parent := Self; AiButtons.Visible := False;  AiButtons.Align := alNone; AiButtons.Width := 194;
  FExportAi := TButton.Create(Self); FExportAi.Parent := AiButtons; FExportAi.SetBounds(8,6,176,28); FExportAi.Caption := 'AI向けに書き出す'; FExportAi.OnClick := ExportAiClick; FExportAi.Enabled := False;
  FImportAi := TButton.Create(Self); FImportAi.Parent := AiButtons; FImportAi.SetBounds(8,40,176,28); FImportAi.Caption := '生成結果を取り込む'; FImportAi.OnClick := ImportAiClick; FImportAi.Enabled := False;
  FCancelAi := TButton.Create(Self); FCancelAi.Parent := AiButtons; FCancelAi.SetBounds(8,74,176,28); FCancelAi.Caption := 'AI処理を中止'; FCancelAi.OnClick := CancelAiClick; FCancelAi.Enabled := False;
  FPrompt := TMemo.Create(Self); FPrompt.Parent := AiPanel; FPrompt.Align := alClient; FPrompt.ScrollBars := ssVertical; FPrompt.MaxLength := 16000;
  FPrompt.ReadOnly := True; FPrompt.Text := 'Codexからの指示を待っています。';
  RightPanel := TPanel.Create(Self); RightPanel.Parent := Self; RightPanel.Align := alRight; RightPanel.Left := ClientWidth-420; RightPanel.Width := 420;
  PositionPanel := TPanel.Create(Self); PositionPanel.Parent := Self; PositionPanel.Visible := False;  PositionPanel.Align := alNone; PositionPanel.Height := 58;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := PositionPanel; LabelControl.SetBounds(8,7,30,18); LabelControl.Caption := 'X';
  FX := TSpinEdit.Create(Self); FX.Parent := PositionPanel; FX.SetBounds(25,4,95,26); FX.MinValue := -30000; FX.MaxValue := 30000; FX.Enabled := False;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := PositionPanel; LabelControl.SetBounds(128,7,25,18); LabelControl.Caption := 'Y';
  FY := TSpinEdit.Create(Self); FY.Parent := PositionPanel; FY.SetBounds(145,4,95,26); FY.MinValue := -30000; FY.MaxValue := 30000; FY.Enabled := False;
  FPositionApply := TButton.Create(Self); FPositionApply.Parent := PositionPanel; FPositionApply.SetBounds(250,3,95,28); FPositionApply.Caption := '配置を適用'; FPositionApply.Enabled := False; FPositionApply.OnClick := PositionClick;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := PositionPanel; LabelControl.SetBounds(8,34,400,18); LabelControl.Caption := '選択画像をプレビュー上でドラッグして配置できます。';
  PartsPanel := TPanel.Create(Self); PartsPanel.Parent := Self; PartsPanel.Visible := False;  PartsPanel.Align := alNone; PartsPanel.Height := 96;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := PartsPanel; LabelControl.SetBounds(8,4,360,20); LabelControl.Caption := '表情・パーツ切替（* 排他選択）';
  FPartGroup := TDarkComboBox.Create(Self); FPartGroup.Parent := PartsPanel; FPartGroup.SetBounds(8,26,400,28); FPartGroup.Anchors := [akLeft,akTop,akRight]; FPartGroup.OnChange := PartGroupChange; FPartGroup.Enabled := False;
  FPartChoice := TDarkComboBox.Create(Self); FPartChoice.Parent := PartsPanel; FPartChoice.SetBounds(8,59,400,28); FPartChoice.Anchors := [akLeft,akTop,akRight]; FPartChoice.OnChange := PartChoiceChange; FPartChoice.Enabled := False;
  FTree := TArtLayerList.Create(Self); FTree.Parent := RightPanel; FTree.Align := alClient;
  FTree.OnSelect := TreeChange; FTree.OnRename := LayerRename; FTree.OnAttributes := LayerAttributes;
  Splitter := TSplitter.Create(Self); Splitter.Parent := Self; Splitter.Align := alRight; Splitter.Left := ClientWidth-424;
  // Buffer only the viewer so background and scaled image appear in one frame.
  PreviewPanel := TPanel.Create(Self); PreviewPanel.Parent := Self;
  PreviewPanel.Align := alClient; PreviewPanel.BevelOuter := bvNone;
  PreviewPanel.ParentBackground := False; PreviewPanel.Color := clGray;
  PreviewPanel.DoubleBuffered := True;
  FPaint := TArtPreviewPaintBox.Create(Self); FPaint.Parent := PreviewPanel; FPaint.Align := alClient;
  FPaint.OnPaint := PaintPreview; FPaint.OnMouseDown := PreviewMouseDown; FPaint.OnMouseMove := PreviewMouseMove; FPaint.OnMouseUp := PreviewMouseUp;
  FOpenDialog := TOpenDialog.Create(Self); FOpenDialog.Filter := 'PSD・PNG (*.psd;*.png)|*.psd;*.png';
  FOpenDialog.Options := [ofFileMustExist,ofPathMustExist,ofEnableSizing,ofNoChangeDir];
  FSaveDialog := TSaveDialog.Create(Self); FSaveDialog.Filter := 'Photoshop PSD (*.psd)|*.psd';
  FSaveDialog.DefaultExt := 'psd'; FSaveDialog.Options := [ofOverwritePrompt,ofPathMustExist,ofEnableSizing,ofNoChangeDir];
  FPngDialog := TOpenDialog.Create(Self); FPngDialog.Filter := 'PNG画像 (*.png)|*.png'; FPngDialog.Options := [ofFileMustExist,ofPathMustExist,ofEnableSizing,ofNoChangeDir];
  FPngDialog.InitialDir := TPath.Combine(ExtractFilePath(ParamStr(0)),'Sample');
  FResultDialog := TOpenDialog.Create(Self); FResultDialog.Filter := 'AI生成結果 (result.json)|result.json'; FResultDialog.Options := [ofFileMustExist,ofPathMustExist,ofEnableSizing,ofNoChangeDir];
  FRecoveryDialog := TOpenDialog.Create(Self); FRecoveryDialog.Filter := 'AI再開情報 (recovery.json)|recovery.json'; FRecoveryDialog.Options := [ofFileMustExist,ofPathMustExist,ofEnableSizing,ofNoChangeDir];
  FZoom := 1; OnMouseWheel := PreviewWheel;
  OnCloseQuery := CheckClose;
  FProtocol := TArtPipeProtocol.Create(DispatchCommand); FPipe := TArtPipeBridge.Create(FProtocol.Handle);
  FExchange.PipeName := FPipe.Name; UpdateActivity;
end;

destructor TMainForm.Destroy;
begin
  FPipe.Free; FProtocol.Free; FUndo.Free;
  if FTree<>nil then begin FTree.OnSelect := nil; FTree.SetRoots(nil); end;
  FDocument.Free; FBitmap.Free; FHistory.Free; FExchange.Free;
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
  FZoom := 1; FPanX := 0; FPanY := 0;
  Image := ReadPng(FileName); NewDoc := TArtDocument.Create;
  try
    NewDoc.Width := Image.Width; NewDoc.Height := Image.Height;
    L := NewDoc.AddLayer(alkImage,ChangeFileExt(ExtractFileName(FileName),''),TArtBounds.Create(0,0,Image.Width,Image.Height)); L.Pixels := Image.Pixels;
    RGBA := NewDoc.RenderRGBA;
  except NewDoc.Free; raise; end;
  Old := FDocument; FDocument := NewDoc;
  try SetPreview(RGBA); except FDocument := Old; NewDoc.Free; raise; end;
  FUndo.Clear; ResetAiJobs; FTree.SetRoots(nil); Old.Free; FFileName := ''; FDocument.Changed; FModified := True; FCanEdit := True;
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
  BeginEdit; L := FDocument.AddLayer(alkImage,ChangeFileExt(ExtractFileName(FileName),''),TArtBounds.Create(0,0,Image.Width,Image.Height),Parent);
  L.Pixels := Image.Pixels; List.Remove(L); List.Insert(Index,L);
  try SetPreview(RenderEditable);
  except FDocument.RemoveNewLayer(L); raise; end;
  FDocument.Changed; CommitEdit; FModified := True; RebuildTree; FTree.Selected := L; FTree.RevealSelected; UpdateStatus;
end;
procedure TMainForm.ReplaceSelectedPng(const FileName: string);
var Image: TArtPngData; L: TArtLayer; OldPixels: TBytes; OldBounds,NewBounds: TArtBounds;
begin
  if not FCanEdit or (FTree.Selected=nil) or (FTree.Selected.Kind<>alkImage) then raise EArtFormat.Create('置換する画像レイヤーを選択してください。');
  FTree.FinishRename(True); Image := ReadPng(FileName); L := FTree.Selected;
  OldPixels := L.Pixels; OldBounds := L.Bounds;
  NewBounds := TArtBounds.Create(OldBounds.Left,OldBounds.Top,OldBounds.Left+Image.Width,OldBounds.Top+Image.Height);
  BeginEdit; L.Pixels := Image.Pixels; L.Bounds := NewBounds;
  try SetPreview(RenderEditable);
  except L.Pixels := OldPixels; L.Bounds := OldBounds; raise; end;
  FDocument.Changed; CommitEdit; FModified := True; FTree.RefreshImages; TreeChange(Self); UpdateStatus;
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
  BeginEdit; L.Bounds := NewBounds; L.MaskBounds := NewMask;
  try SetPreview(RenderEditable);
  except L.Bounds := OldBounds; L.MaskBounds := OldMask; raise; end;
  FDocument.Changed; CommitEdit; FModified := True; TreeChange(Self); UpdateStatus;
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
    FUndo.Clear; ResetAiJobs; FTree.SetRoots(nil); OldDoc.Free; FFileName := TPath.GetFullPath(FileName);
    FCanEdit := NewCanEdit; FModified := False; FSave.Enabled := True; FSaveAs.Enabled := True; FClose.Enabled := True;
    RebuildTree; UpdateStatus;
    if not FLoadingSaved then begin
      FZoom := 1; FPanX := 0; FPanY := 0; FPaint.Invalidate;
      try FHistory.AddFile(FFileName); except on E: Exception do FStatus.Caption := FStatus.Caption+sLineBreak+'履歴保存失敗: '+E.Message; end;
      RebuildHistory;
    end;
  finally Screen.Cursor := crDefault; end;
end;

procedure TMainForm.RebuildTree;
begin FTree.EditEnabled := False; FTree.SetRoots(FDocument.Roots); end;

procedure TMainForm.TreeChange(Sender: TObject);
var L: TArtLayer; CanImage: Boolean;
begin
  L := FTree.Selected; CanImage := FCanEdit and (L<>nil) and (L.Kind=alkImage);
  FReplaceItem.Enabled := CanImage; FPositionItem.Enabled := CanImage; FX.Enabled := CanImage; FY.Enabled := CanImage; FPositionApply.Enabled := CanImage;
  FImportItem.Enabled := (FDocument=nil) or FCanEdit;
  FGroupItem.Enabled := FCanEdit and (FDocument<>nil);
  FExportAi.Enabled := FCanEdit and (FDocument<>nil); FImportAi.Enabled := FExportAi.Enabled;
  UpdateParts; UpdateActivity;
  if CanImage then begin FX.Value := L.Bounds.Left; FY.Value := L.Bounds.Top; end;
  if FPaint<>nil then begin TArtPaintBoxAccess(FPaint).MouseCapture := False; FPaint.Cursor := crDefault; FPaint.Invalidate; end; FDragging := False;
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
var L: TArtLayer; OldName: string; OldOpacity: Byte; States: TDictionary<TArtLayer,Boolean>; Pair: TPair<TArtLayer,Boolean>; Changed: Boolean;
  procedure Snapshot(List: TList<TArtLayer>);
  var Item: TArtLayer;
  begin for Item in List do begin States.Add(Item,Item.Visible); Snapshot(Item.Children); end; end;
begin
  if not FCanEdit or (FTree.Selected=nil) then raise EArtFormat.Create('このPSDは表示・変更なし保存のみ対応しています。');
  L := FTree.Selected; OldName := L.Name; OldOpacity := L.Opacity;
  States := TDictionary<TArtLayer,Boolean>.Create;
  try
    Snapshot(FDocument.Roots); BeginEdit; L.Name := Name; L.Visible := Visible; L.Opacity := Opacity;
    try
      if IsExclusive(L) and L.Visible then SelectExclusive(FDocument,L);
      Changed := (OldName<>Name) or (OldOpacity<>Opacity);
      for Pair in States do Changed := Changed or (Pair.Key.Visible<>Pair.Value);
      if not Changed then Exit;
      SetPreview(RenderEditable);
    except
      L.Name := OldName; L.Opacity := OldOpacity;
      for Pair in States do Pair.Key.Visible := Pair.Value;
      raise;
    end;
    FDocument.Changed; CommitEdit; FModified := True; FTree.RefreshLayerNames; UpdateParts; UpdateStatus;
  finally States.Free; end;
end;

procedure TMainForm.SelectPart(Layer: TArtLayer);
var Previous: TArtLayer;
begin
  if not FCanEdit then raise EArtFormat.Create('この文書の切替は未対応です。');
  LayerSiblings(FDocument,Layer);
  if not IsExclusive(Layer) then raise EArtFormat.Create('排他選択 (*) を設定してください。');
  FTree.FinishRename(True); Previous := FTree.Selected; FTree.Selected := Layer;
  try ApplySelectedLayer(Layer.Name,True,Layer.Opacity);
  except FTree.Selected := Previous; raise; end;
  FTree.RevealSelected;
end;

procedure TMainForm.RecoverAiClick(Sender: TObject);
begin
  if not ConfirmDiscard then Exit;
  FRecoveryDialog.FileName := 'recovery.json';
  if FRecoveryDialog.Execute then
    try RecoverAiJob(ExtractFilePath(FRecoveryDialog.FileName));
    except on E: Exception do MessageDlg('AIジョブを再開できませんでした。'+sLineBreak+E.Message,mtError,[mbOK],0); end;
end;
procedure TMainForm.RecoverAiJob(const Directory: string);
var Candidate,Old: TArtDocument; Job: TArtExchangeJob; Pixels: TBytes;
begin
  BeginOperation('AIジョブの再開中');
  try
    Candidate := FExchange.LoadRecovery(ExcludeTrailingPathDelimiter(Directory),Job);
    try Pixels := RenderPsdLayers(Candidate); FExchange.WriteJobConnection(Job); except Candidate.Free; Job.Free; raise; end;
    Old := FDocument; FDocument := Candidate;
    try SetPreview(Pixels); except FDocument := Old; Candidate.Free; Job.Free; raise; end;
    FUndo.Clear; ResetAiJobs; FTree.SetRoots(nil); Old.Free;
    FZoom := 1; FPanX := 0; FPanY := 0; FPaint.Invalidate;
    FExchange.RegisterRecovered(Job); FCurrentJobId := Job.Id; FJobPath.Text := Job.Directory;
    FJobPath.Hint := Job.Directory; FJobPath.ShowHint := True;
    FPrompt.Lines.Add('Codex: '+Job.PromptText); FFileName := ''; FModified := True; FCanEdit := True;
    FSave.Enabled := True; FSaveAs.Enabled := True; FClose.Enabled := True;
    RebuildTree; UpdateStatus;
  finally EndOperation; end;
end;
procedure TMainForm.ResetAiJobs;
begin
  FCurrentJobId := ''; FExchange.ClearJobs; FJobPath.Text := 'AIジョブのフォルダーがここに表示されます。';
  FJobPath.Hint := ''; FJobPath.ShowHint := False; UpdateActivity;
end;

function TMainForm.ExportAiJob(const Prompt,Root: string; Workspace: TJSONObject): string;
begin
  if not FCanEdit then raise EArtFormat.Create('編集対応文書を開いてください。');
  FPrompt.Lines.Add('Codex: '+Prompt);
  FTree.FinishRename(True); BeginOperation('AI向け書出し中');
  try Result := FExchange.ExportJob(FDocument,Prompt,Root,Workspace); FCurrentJobId := ExtractFileName(Result);
  finally EndOperation; end;
  FJobPath.Text := Result; FJobPath.Hint := Result; FJobPath.ShowHint := True;
end;
procedure TMainForm.ImportAiResult(const FileName: string);
var Candidate,Old: TArtDocument; Job: TArtExchangeJob; Digest,SelectedId: string; L: TArtLayer; Pixels: TBytes;
begin
  if not FCanEdit then raise EArtFormat.Create('編集対応文書を開いてください。');
  FTree.FinishRename(True); BeginOperation('生成結果の検証・取込中');
  try
  Candidate := FExchange.PrepareResult(FDocument,FileName,Job,Digest);
  if Candidate=nil then begin UpdateStatus; FStatus.Caption := FStatus.Caption+sLineBreak+'この生成結果は既に取り込み済みです。'; Exit; end;
  SelectedId := ''; if FTree.Selected<>nil then SelectedId := FTree.Selected.Id;
  try Pixels := RenderPsdLayers(Candidate); except Candidate.Free; raise; end;
  try BeginEdit; except Candidate.Free; raise; end;
  Old := FDocument; FDocument := Candidate;
  try SetPreview(Pixels); except FDocument := Old; Candidate.Free; raise; end;
  FTree.SetRoots(nil); Old.Free; CommitEdit; FModified := True;
  FExchange.CommitResult(Job,Digest); RebuildTree;
  L := FDocument.FindLayer(SelectedId); if L<>nil then begin FTree.Selected := L; FTree.RevealSelected; end;
  UpdateStatus; FStatus.Caption := FStatus.Caption+sLineBreak+'生成結果を取り込みました。PSDを保存して確定してください。';
  finally EndOperation; end;
end;
procedure TMainForm.ExportAiClick(Sender: TObject);
begin
  try ExportAiJob(FPrompt.Text,TPath.Combine(ExtractFilePath(ParamStr(0)),'Exchange'));
  except on E: Exception do MessageDlg('AI向けの書き出しに失敗しました。'+sLineBreak+E.Message,mtError,[mbOK],0); end;
end;
procedure TMainForm.ImportAiClick(Sender: TObject);
begin
  if DirectoryExists(FJobPath.Text) then FResultDialog.InitialDir := FJobPath.Text;
  FResultDialog.FileName := 'result.json';
  if FResultDialog.Execute then
    try ImportAiResult(FResultDialog.FileName);
    except on E: Exception do MessageDlg('生成結果を取り込めませんでした。'+sLineBreak+E.Message,mtError,[mbOK],0); end;
end;

procedure TMainForm.UpdateParts;
var Previous: TObject;
  procedure Collect(List: TList<TArtLayer>; Parent: TArtLayer; const Path: string);
  var L: TArtLayer; HasParts: Boolean; Caption: string;
  begin
    HasParts := False; for L in List do HasParts := HasParts or IsExclusive(L);
    if HasParts then FPartGroup.Items.AddObject(Path,Parent);
    for L in List do if L.Kind=alkGroup then begin
      Caption := ParseLayerName(L.Name).DisplayName;
      if Parent<>nil then Caption := Path+' / '+Caption;
      Collect(L.Children,L,Caption);
    end;
  end;
begin
  if (FPartGroup=nil) or FUpdatingParts then Exit;
  FUpdatingParts := True;
  try
    Previous := nil;
    if FPartGroup.ItemIndex>=0 then Previous := FPartGroup.Items.Objects[FPartGroup.ItemIndex];
    FPartGroup.Items.Clear;
    if FDocument<>nil then Collect(FDocument.Roots,nil,'文書直下');
    FPartGroup.ItemIndex := FPartGroup.Items.IndexOfObject(Previous);
    if (FPartGroup.ItemIndex<0) and (FPartGroup.Items.Count>0) then FPartGroup.ItemIndex := 0;
    FPartGroup.Enabled := FCanEdit and (FPartGroup.Items.Count>0);
    PartGroupChange(Self);
  finally FUpdatingParts := False; end;
end;
procedure TMainForm.PartGroupChange(Sender: TObject);
var Parent,L: TArtLayer; List: TList<TArtLayer>; Active,VisibleCount: Integer;
begin
  FPartChoice.Items.Clear; Active := -1; VisibleCount := 0;
  if (FDocument<>nil) and (FPartGroup.ItemIndex>=0) then begin
    Parent := TArtLayer(FPartGroup.Items.Objects[FPartGroup.ItemIndex]);
    if Parent=nil then List := FDocument.Roots else List := Parent.Children;
    for L in List do if IsExclusive(L) then begin
      FPartChoice.Items.AddObject(ParseLayerName(L.Name).DisplayName,L);
      if L.Visible then begin Active := FPartChoice.Items.Count-1; Inc(VisibleCount); end;
    end;
  end;
  if VisibleCount<>1 then Active := -1;
  FPartChoice.ItemIndex := Active; FPartChoice.Enabled := FCanEdit and (FPartChoice.Items.Count>0);
  FPartChoice.Hint := '選択すると同じ親の * パーツを1つだけ表示します。親が非表示なら目アイコンで表示してください。'; FPartChoice.ShowHint := True;
end;
procedure TMainForm.PartChoiceChange(Sender: TObject);
var L: TArtLayer;
begin
  if FUpdatingParts or (FPartChoice.ItemIndex<0) then Exit;
  L := TArtLayer(FPartChoice.Items.Objects[FPartChoice.ItemIndex]);
  try SelectPart(L); except on E: Exception do begin UpdateParts; MessageDlg(E.Message,mtError,[mbOK],0); end; end;
end;
procedure TMainForm.CreateGroup(const Name: string; Exclusive: Boolean);
var Parent,Selected,L: TArtLayer; List: TList<TArtLayer>; Index: Integer; GroupName: string;
begin
  if not FCanEdit or (FDocument=nil) then raise EArtFormat.Create('編集できる文書を開いてください。');
  GroupName := RenameLayerDisplay('',Name); if Exclusive then GroupName := SetLayerPrefix(GroupName,'*');
  FTree.FinishRename(True); Selected := FTree.Selected; Parent := nil; List := FDocument.Roots;
  if Selected<>nil then begin
    if Selected.Kind=alkGroup then begin Parent := Selected; List := Parent.Children; end
    else List := LayerSiblings(FDocument,Selected);
  end;
  Index := List.IndexOf(Selected); if Index<0 then Index := 0;
  BeginEdit; L := FDocument.AddLayer(alkGroup,GroupName,TArtBounds.Create(0,0,0,0),Parent);
  FDocument.Roots.Remove(L); if Parent<>nil then Parent.Children.Remove(L);
  List.Insert(Index,L);
  if Exclusive then begin
    for var Sibling in List do if (Sibling<>L) and IsExclusive(Sibling) and Sibling.Visible then L.Visible := False;
  end;
  try SetPreview(RenderEditable); except FDocument.RemoveNewLayer(L); raise; end;
  FDocument.Changed; CommitEdit; FModified := True; RebuildTree; FTree.Selected := L; FTree.RevealSelected; UpdateStatus;
end;
procedure TMainForm.GroupClick(Sender: TObject);
var Name: string; Exclusive: Boolean; Answer: Integer;
begin
  Name := '表情'; if not InputQuery('グループ作成','グループ名',Name) then Exit;
  Answer := MessageDlg('表情・パーツの差分として排他選択 (*) を設定しますか？',mtConfirmation,[mbYes,mbNo,mbCancel],0);
  if Answer=mrCancel then Exit; Exclusive := Answer=mrYes;
  try CreateGroup(Name,Exclusive); except on E: Exception do MessageDlg(E.Message,mtError,[mbOK],0); end;
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
  FStatus.Hint := FStatus.Caption; FStatus.ShowHint := True; UpdateActivity;
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
    try if SameText(ExtractFileExt(FOpenDialog.FileName),'.png') then NewFromPng(FOpenDialog.FileName) else OpenPsdFile(FOpenDialog.FileName); except on E: Exception do MessageDlg('PSDを開けませんでした。'+sLineBreak+E.Message,mtError,[mbOK],0); end;
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
  FUndo.Clear; ResetAiJobs; FCanEdit := False; FTree.SetRoots(nil); FreeAndNil(FDocument);
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
var Scale: Double; W,H,X,Y: Integer;
begin
  Result := Rect(0,0,0,0); if FBitmap.Empty then Exit;
  Scale := Min(FPaint.Width/FBitmap.Width,FPaint.Height/FBitmap.Height)*FZoom;
  W := Max(1,Round(FBitmap.Width*Scale)); H := Max(1,Round(FBitmap.Height*Scale));
  X := Round((FPaint.Width-W)/2+FPanX); Y := Round((FPaint.Height-H)/2+FPanY);
  Result := Rect(X,Y,X+W,Y+H);
end;
procedure TMainForm.PreviewWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var P: TPoint; Ratio,NewZoom: Double;
begin
  P := FPaint.ScreenToClient(MousePos);
  if FBitmap.Empty or not PtInRect(FPaint.ClientRect,P) then Exit;
  NewZoom := EnsureRange(FZoom*Power(1.15,WheelDelta/120),0.05,32.0);
  Ratio := NewZoom/FZoom;
  FPanX := P.X-FPaint.Width/2+(FPaint.Width/2+FPanX-P.X)*Ratio;
  FPanY := P.Y-FPaint.Height/2+(FPaint.Height/2+FPanY-P.Y)*Ratio;
  FZoom := NewZoom; Handled := True; FPaint.Invalidate;
end;
procedure TMainForm.PreviewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin
  if (Button<>mbLeft) or FBitmap.Empty then Exit;
  FDragStart := Point(X,Y); FDragging := True;
  TArtPaintBoxAccess(FPaint).MouseCapture := True; FPaint.Cursor := crSizeAll;
end;
procedure TMainForm.PreviewMouseMove(Sender: TObject; Shift: TShiftState; X,Y: Integer);
begin
  if not FDragging then Exit;
  FPanX := FPanX+X-FDragStart.X; FPanY := FPanY+Y-FDragStart.Y;
  FDragStart := Point(X,Y); FPaint.Invalidate;
end;
procedure TMainForm.PreviewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin
  if (Button<>mbLeft) or not FDragging then Exit;
  PreviewMouseMove(Sender,Shift,X,Y); FDragging := False;
  TArtPaintBoxAccess(FPaint).MouseCapture := False; FPaint.Cursor := crDefault;
end;
procedure TMainForm.PaintPreview(Sender: TObject);
begin
  FPaint.Canvas.Brush.Color := clGray; FPaint.Canvas.FillRect(FPaint.ClientRect);
  if not FBitmap.Empty then FPaint.Canvas.StretchDraw(PreviewRect,FBitmap);
end;

end.

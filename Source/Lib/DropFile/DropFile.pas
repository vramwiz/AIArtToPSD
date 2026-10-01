unit DropFile;

{
  Unit Name   : DropFile
  Description: 任意の VCL コントロール（TWinControl）に対して、外部アプリ（主にエクスプローラー）からの
               ファイル ドラッグ＆ドロップ（WM_DROPFILES）を受け取れるようにするユニットです。

               方式は DragAcceptFiles / WM_DROPFILES を使用します（OLE/COM の IDropTarget ではありません）。
               そのため「ファイル/フォルダのパス」を簡単に受け取る用途に向きます。

  Author     : vramwiz
  Created    : 2025-07-10
  Updated    : 2026-03-04

  Usage      :
    (旧互換：イベント方式)
      Drop := TDropFile.Create;
      Drop.OnDropReceived := DropEvent;
      Drop.Attach(Edit1);

    (新方式：コールバック方式：プラグイン/グローバル設計向け)
      Drop := TDropFile.Create;
      Drop.Attach(RootPanel, FrameSyncroh2.DropFiles);

    ※ Callback を指定した場合は Callback が優先されます。
       Callback=nil の場合は従来通り OnDropReceived（イベント）で通知します。

  Features   :
    - 複数ファイル/フォルダの同時ドロップに対応
    - Attach/Detach で任意のコントロールへ付け外し可能
    - 内部で Control.WindowProc を差し替え、WM_DROPFILES をフック

  Notes      :
    - ドロップ対象は TWinControl を継承している必要があります。
    - OLE ドラッグ（テキスト/独自形式など）には非対応です（必要なら別実装）。
    - WM_DROPFILES を処理した場合、二重処理回避のため OriginalWndProc は呼びません。
}

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.ShellAPI,
  System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Controls;

type
  // 旧互換：method of object イベント（従来通り）
  TDropFileEvent = procedure(Sender: TObject; Control: TWinControl; const FileNames: TArray<string>) of object;

  // 新方式：コールバック（イベントを持ちたくない場合向け）
  TDropFileCallback = procedure(Control: TWinControl; const FileNames: TArray<string>) of object;

  // さらに必要なら（グローバル関数等）こちらも使えるようにしておく
  TDropFileProc = procedure(Control: TWinControl; const FileNames: TArray<string>);

type
  TDropTargetInfo = class
  public
    Control: TWinControl;
    OriginalWndProc: TWndMethod;

    constructor Create(AControl: TWinControl; AEvent: TDropFileEvent; ACallback: TDropFileCallback; AProc: TDropFileProc);
    procedure CustomWndProc(var Msg: TMessage);

  private
    FEvent: TDropFileEvent;
    FCallback: TDropFileCallback;
    FProc: TDropFileProc;
  end;

  TDropFile = class
  private
    FTargets: TObjectList<TDropTargetInfo>;
    FOnDropReceived: TDropFileEvent;

    function FindTarget(Control: TWinControl): TDropTargetInfo;
    procedure Log(const S: string);

  public
    constructor Create;
    destructor Destroy; override;

    // 旧互換
    procedure Attach(Control: TWinControl); overload;

    // 新：Frame等のメソッドに渡す（method of object）
    procedure Attach(Control: TWinControl; Callback: TDropFileCallback); overload;

    // 新：グローバル関数などに渡す（通常のprocedure）
    procedure Attach(Control: TWinControl; Proc: TDropFileProc); overload;

    procedure Detach(Control: TWinControl);

    // 旧互換：Attach(Control) で使用される
    property OnDropReceived: TDropFileEvent read FOnDropReceived write FOnDropReceived;
  end;

implementation

{ TDropTargetInfo }

constructor TDropTargetInfo.Create(AControl: TWinControl; AEvent: TDropFileEvent; ACallback: TDropFileCallback; AProc: TDropFileProc);
begin
  inherited Create;
  Control := AControl;
  OriginalWndProc := Control.WindowProc;

  FEvent := AEvent;
  FCallback := ACallback;
  FProc := AProc;
end;

procedure TDropTargetInfo.CustomWndProc(var Msg: TMessage);
var
  DropMsg: TWMDropFiles absolute Msg;
  Count, I, Len: Integer;
  Files: TArray<string>;
  Buf: array[0..MAX_PATH] of Char;
begin
  if Msg.Msg = WM_DROPFILES then
  begin
    Count := DragQueryFile(DropMsg.Drop, $FFFFFFFF, nil, 0);
    SetLength(Files, Count);

    for I := 0 to Count - 1 do
    begin
      Len := DragQueryFile(DropMsg.Drop, I, nil, 0);
      if Len <= High(Buf) then
      begin
        DragQueryFile(DropMsg.Drop, I, Buf, MAX_PATH);
        Files[I] := Buf;
      end
      else
      begin
        // パスが極端に長い場合は都度確保（念のため）
        SetLength(Files[I], Len);
        DragQueryFile(DropMsg.Drop, I, PChar(Files[I]), Len + 1);
      end;
    end;

    DragFinish(DropMsg.Drop);

    // 優先順位：Proc → Callback → Event（旧互換）
    if Assigned(FProc) then
      FProc(Control, Files)
    else if Assigned(FCallback) then
      FCallback(Control, Files)
    else if Assigned(FEvent) then
      FEvent(nil, Control, Files);

    // WM_DROPFILES はここで完結させる（OriginalWndProc に渡すと二重処理の恐れ）
    Exit;
  end;

  OriginalWndProc(Msg);
end;

{ TDropFile }

constructor TDropFile.Create;
begin
  inherited Create;
  FTargets := TObjectList<TDropTargetInfo>.Create(True);
end;

destructor TDropFile.Destroy;
begin
  while FTargets.Count > 0 do
    Detach(FTargets[0].Control);

  FTargets.Free;
  inherited;
end;

function TDropFile.FindTarget(Control: TWinControl): TDropTargetInfo;
var
  Info: TDropTargetInfo;
begin
  for Info in FTargets do
    if Info.Control = Control then
      Exit(Info);
  Result := nil;
end;

procedure TDropFile.Attach(Control: TWinControl);
var
  Info: TDropTargetInfo;
begin
  if not Assigned(Control) then Exit;
  if Assigned(FindTarget(Control)) then Exit;

  // 旧互換：OnDropReceived を内部に渡す
  Info := TDropTargetInfo.Create(Control, FOnDropReceived, nil, nil);
  Control.WindowProc := Info.CustomWndProc;
  DragAcceptFiles(Control.Handle, True);

  FTargets.Add(Info);
  Log('Attached(Event): ' + Control.Name);
end;

procedure TDropFile.Attach(Control: TWinControl; Callback: TDropFileCallback);
var
  Info: TDropTargetInfo;
begin
  if not Assigned(Control) then Exit;
  if Assigned(FindTarget(Control)) then Exit;

  // Callback が nil の場合は旧互換（Event）で動作させる
  if not Assigned(Callback) then
  begin
    Attach(Control);
    Exit;
  end;

  Info := TDropTargetInfo.Create(Control, nil, Callback, nil);
  Control.WindowProc := Info.CustomWndProc;
  DragAcceptFiles(Control.Handle, True);

  FTargets.Add(Info);
  Log('Attached(Callback): ' + Control.Name);
end;

procedure TDropFile.Attach(Control: TWinControl; Proc: TDropFileProc);
var
  Info: TDropTargetInfo;
begin
  if not Assigned(Control) then Exit;
  if Assigned(FindTarget(Control)) then Exit;

  // Proc が nil の場合は旧互換（Event）で動作させる
  if not Assigned(Proc) then
  begin
    Attach(Control);
    Exit;
  end;

  Info := TDropTargetInfo.Create(Control, nil, nil, Proc);
  Control.WindowProc := Info.CustomWndProc;
  DragAcceptFiles(Control.Handle, True);

  FTargets.Add(Info);
  Log('Attached(Proc): ' + Control.Name);
end;

procedure TDropFile.Detach(Control: TWinControl);
var
  ControlHandle: HWND;
  Info: TDropTargetInfo;
begin
  Info := FindTarget(Control);
  if not Assigned(Info) then Exit;

  Control.WindowProc := Info.OriginalWndProc;

  // The host can destroy its HWND before the VCL object during shutdown.
  // Reading Handle in that state calls HandleNeeded and attempts to recreate
  // the child window with an invalid parent.  Only detach an existing HWND.
  if Control.HandleAllocated then
  begin
    ControlHandle := Control.Handle;
    if IsWindow(ControlHandle) then
      DragAcceptFiles(ControlHandle, False);
  end;

  FTargets.Remove(Info);
  Log('Detached: ' + Control.Name);
end;

procedure TDropFile.Log(const S: string);
begin
  {$IFDEF DEBUG}
  OutputDebugString(PChar('[TDropFile] ' + S));
  {$ENDIF}
end;

end.

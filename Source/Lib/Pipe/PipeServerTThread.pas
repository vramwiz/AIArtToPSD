unit PipeServerTThread;

interface

uses
  Winapi.Windows, System.Classes, System.SysUtils,Winapi.Messages;

const
  WM_PIPE_NOTIFY = WM_USER + 100;

type
  TPipeServerState = (psConnectWait, psReceive, psTerminating);

type
  TPipeServerConfig = record
    PipeName: string;
    BufferSize: Cardinal;
    Timeout: Cardinal;
    MaxInstances: Cardinal;
    IsDuplex: Boolean;
  end;

type
  TPipeServerTThreadReceiveEvent = procedure(Sender: TObject; const ReceivedStr: string; var SendStr: string) of object;

type
  TPipeServerTThread = class(TThread)
  private
    FState: TPipeServerState;
    FConfig: TPipeServerConfig;

    FRecvText: string;
    FSendText: string;

    FPipeHandle: THandle;
    FOnReceive: TPipeServerTThreadReceiveEvent;

    FMainWnd: HWND;
    FEventHandle: THandle;

    procedure Connect;
    procedure Receive;
    procedure PipeFinalize;
    procedure PipeClose;
    function PipeOpen(const Config: TPipeServerConfig): THandle;
  protected
    procedure DoReceive(const ReceivedStr: string; var SendStr: string);
    procedure Execute; override;
  public
    constructor Create(const PipeName: string; BufferSize: Cardinal; IsDuplex: Boolean; Timeout: Cardinal; MaxInstances: Cardinal; MainWnd: HWND);
    destructor Destroy; override;
    procedure ProcessMainThread;
    procedure ReleaseWait;
    property OnReceive: TPipeServerTThreadReceiveEvent read FOnReceive write FOnReceive;
  end;

implementation

constructor TPipeServerTThread.Create(const PipeName: string; BufferSize: Cardinal; IsDuplex: Boolean; Timeout, MaxInstances: Cardinal; MainWnd: HWND);
begin
  inherited Create(False);

  FConfig.PipeName := PipeName;
  FConfig.BufferSize := BufferSize;
  FConfig.IsDuplex := IsDuplex;
  FConfig.Timeout := Timeout;
  FConfig.MaxInstances := MaxInstances;

  FMainWnd := MainWnd;
  FEventHandle := CreateEvent(nil, False, False, nil);

  FPipeHandle := INVALID_HANDLE_VALUE;
  FState := psConnectWait;
  FreeOnTerminate := False;
end;

destructor TPipeServerTThread.Destroy;
begin
  if FEventHandle <> 0 then CloseHandle(FEventHandle);
  inherited;
end;

function TPipeServerTThread.PipeOpen(const Config: TPipeServerConfig): THandle;
var
  OpenMode, PipeMode: DWORD;
  FullName: string;
begin
  if Config.IsDuplex then OpenMode := PIPE_ACCESS_DUPLEX else OpenMode := PIPE_ACCESS_INBOUND;
  PipeMode := PIPE_TYPE_MESSAGE or PIPE_READMODE_MESSAGE or PIPE_WAIT;
  FullName := '\\.\pipe\' + Config.PipeName;
  Result := CreateNamedPipe(PChar(FullName), OpenMode, PipeMode,
    Config.MaxInstances, Config.BufferSize, Config.BufferSize, 0, nil);
end;

procedure TPipeServerTThread.ProcessMainThread;
begin
  try
    if Assigned(FOnReceive) then
      FOnReceive(Self, FRecvText, FSendText);
  finally
    SetEvent(FEventHandle); // ← スレッド再開
  end;
end;


procedure TPipeServerTThread.PipeClose;
begin
  if FPipeHandle <> INVALID_HANDLE_VALUE then begin
    DisconnectNamedPipe(FPipeHandle);
    CloseHandle(FPipeHandle);
    FPipeHandle := INVALID_HANDLE_VALUE;
  end;
end;

procedure TPipeServerTThread.PipeFinalize;
begin
  PipeClose;
end;

procedure TPipeServerTThread.Connect;
var
  Ok: BOOL;
  Err: DWORD;
begin
  PipeClose;
  FPipeHandle := PipeOpen(FConfig);
  if FPipeHandle = INVALID_HANDLE_VALUE then begin Sleep(50); Exit; end;

  Ok := ConnectNamedPipe(FPipeHandle, nil);
  if Ok then begin FState := psReceive; Exit; end;

  Err := GetLastError;
  if Err = ERROR_PIPE_CONNECTED then begin FState := psReceive; Exit; end;

  PipeClose;
  Sleep(50);
end;

procedure TPipeServerTThread.DoReceive(const ReceivedStr: string; var SendStr: string);
var
  WaitRes: DWORD;
begin
  FRecvText := ReceivedStr;
  FSendText := '';

  ResetEvent(FEventHandle);
  PostMessage(FMainWnd, WM_PIPE_NOTIFY, WPARAM(Self), 0);

  while not Terminated do
  begin
    WaitRes := WaitForSingleObject(FEventHandle, 50);
    if WaitRes = WAIT_OBJECT_0 then Break;
  end;

  if Terminated then
  begin
    SendStr := ''; // 停止時は空返信など
    Exit;
  end;

  SendStr := FSendText;
end;


procedure TPipeServerTThread.Receive;
var
  BytesRead, BytesWritten: DWORD;
  Ok: BOOL;
  Buf: TBytes;
  ReceivedStr: string;
  SendStr: string;
  SendBytes: TBytes;
begin
  SetLength(Buf, FConfig.BufferSize);
  BytesRead := 0;

  Ok := ReadFile(FPipeHandle, Buf[0], Length(Buf), BytesRead, nil);
  if (not Ok) or (BytesRead = 0) then begin PipeClose; FState := psConnectWait; Exit; end;

  ReceivedStr := TEncoding.UTF8.GetString(Buf, 0, BytesRead);
  SendStr := '';
  DoReceive(ReceivedStr, SendStr);

  if FConfig.IsDuplex then
  begin
    SendBytes := TEncoding.UTF8.GetBytes(SendStr);
    BytesWritten := 0;
    WriteFile(FPipeHandle, Pointer(SendBytes)^, Length(SendBytes), BytesWritten, nil);
    FlushFileBuffers(FPipeHandle);
  end;
end;

procedure TPipeServerTThread.ReleaseWait;
begin
  if FEventHandle <> 0 then SetEvent(FEventHandle);
end;


procedure TPipeServerTThread.Execute;
begin
  while not Terminated do
  begin
    if Terminated then Break;
    case FState of
      psConnectWait: Connect;
      psReceive: Receive;
    else
      Sleep(10);
    end;
  end;
  PipeFinalize;
end;

end.


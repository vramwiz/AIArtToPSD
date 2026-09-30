unit ArtPipeBridge;
interface
uses Winapi.Windows, Winapi.Messages, System.Classes, System.SysUtils, PipeServerTThread;
type
  TArtPipeRequest = procedure(const Request: string; out Response: string) of object;
  TArtPipeBridge = class
  private
    FServer: TPipeServerTThread;
    FWindow: HWND;
    FName,FConnectionFile: string;
    FStopping: Boolean;
    FOnRequest: TArtPipeRequest;
    procedure WindowProc(var Message: TMessage);
    procedure Receive(Sender: TObject; const Request: string; var Response: string);
  public
    constructor Create(Handler: TArtPipeRequest);
    destructor Destroy; override;
    property Name: string read FName;
    property ConnectionFile: string read FConnectionFile;
  end;
implementation
uses System.IOUtils, System.JSON;
type
  // The reused constructor starts its thread before initializing its fields.
  // Delay Execute through a subclass; the transport implementation stays unchanged.
  TArtPipeWorker = class(TPipeServerTThread)
  private
    FReady: LongInt;
  protected
    procedure Execute; override;
  public
    procedure MarkReady;
  end;
procedure TArtPipeWorker.MarkReady;
begin InterlockedExchange(FReady,1); end;
procedure TArtPipeWorker.Execute;
begin
  while not Terminated and (InterlockedCompareExchange(FReady,0,0)=0) do Sleep(1);
  if not Terminated then inherited Execute;
end;
constructor TArtPipeBridge.Create(Handler: TArtPipeRequest);
var G: TGUID; Directory: string; Info: TJSONObject;
begin
  inherited Create; CreateGUID(G);
  FName := 'AIArtToPSD.'+IntToStr(GetCurrentProcessId)+'.'+GUIDToString(G);
  FOnRequest := Handler; FWindow := AllocateHWnd(WindowProc);
  // Reuse the existing message-mode UTF-8 transport without modification.
  FServer := TArtPipeWorker.Create(FName,65536,True,1000,1,FWindow);
  FServer.OnReceive := Receive;
  Directory := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'),'AIArtToPSD\pipes'); ForceDirectories(Directory);
  FConnectionFile := TPath.Combine(Directory,FName+'.json'); Info := TJSONObject.Create;
  try
    Info.AddPair('schemaVersion',TJSONNumber.Create(1)); Info.AddPair('pid',TJSONNumber.Create(GetCurrentProcessId));
    Info.AddPair('pipeName',FName);
    TFile.WriteAllText(FConnectionFile+'.tmp',Info.ToJSON,TEncoding.UTF8);
    TFile.Move(FConnectionFile+'.tmp',FConnectionFile);
  finally Info.Free; end;
  TArtPipeWorker(FServer).MarkReady;
end;
destructor TArtPipeBridge.Destroy;
begin
  FStopping := True;
  if FServer<>nil then begin
    FServer.Terminate; FServer.ReleaseWait;
    // Cancel blocking connect/read/write/flush on the worker, before destroying its event.
    while WaitForSingleObject(FServer.Handle,10)=WAIT_TIMEOUT do begin
      CancelSynchronousIo(FServer.Handle); FServer.ReleaseWait;
    end;
    FServer.Free;
  end;
  if FWindow<>0 then DeallocateHWnd(FWindow);
  try if (FConnectionFile<>'') and FileExists(FConnectionFile) then TFile.Delete(FConnectionFile); except end;
  inherited;
end;
procedure TArtPipeBridge.WindowProc(var Message: TMessage);
begin
  if (Message.Msg=WM_PIPE_NOTIFY) and (FServer<>nil) and (Message.WParam=WPARAM(FServer)) then begin
    if FStopping then FServer.ReleaseWait else FServer.ProcessMainThread;
    Message.Result := 0;
  end else Message.Result := DefWindowProc(FWindow,Message.Msg,Message.WParam,Message.LParam);
end;
procedure TArtPipeBridge.Receive(Sender: TObject; const Request: string; var Response: string);
begin
  if Assigned(FOnRequest) then FOnRequest(Request,Response)
  else Response := '{"ok":false,"error":"Server unavailable"}';
end;
end.

program Stage14Smoke;
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
type
  TCommandClient = class(TThread)
  private
    FPipe,FRequest: string;
  protected
    procedure Execute; override;
  public
    Reply,ErrorText: string;
    constructor Create(const Pipe,Request: string);
  end;
constructor TCommandClient.Create(const Pipe,Request: string);
begin inherited Create(True); FreeOnTerminate := False; FPipe := Pipe; FRequest := Request; end;
procedure OSCheck(Value: Boolean);
begin if not Value then RaiseLastOSError; end;
procedure TCommandClient.Execute;
var H: THandle; Buffer,Payload: TBytes; ReadCount,Written,Mode: DWORD; Deadline: UInt64;
begin
  H := INVALID_HANDLE_VALUE;
  try
    try
      Deadline := GetTickCount64+5000;
      repeat
        H := CreateFile(PChar('\\.\pipe\'+FPipe),GENERIC_READ or GENERIC_WRITE,0,nil,OPEN_EXISTING,0,0);
        if H<>INVALID_HANDLE_VALUE then Break;
        if GetTickCount64>Deadline then raise Exception.Create('Client connection timed out');
        Sleep(5);
      until Terminated;
      if H=INVALID_HANDLE_VALUE then Exit;
      Mode := PIPE_READMODE_MESSAGE; OSCheck(SetNamedPipeHandleState(H,Mode,nil,nil));
      Payload := TEncoding.UTF8.GetBytes(FRequest); OSCheck(WriteFile(H,Payload[0],Length(Payload),Written,nil));
      if Written<>DWORD(Length(Payload)) then raise Exception.Create('Incomplete request');
      SetLength(Buffer,65536); OSCheck(ReadFile(H,Buffer[0],Length(Buffer),ReadCount,nil));
      Reply := TEncoding.UTF8.GetString(Buffer,0,ReadCount);
    except on E: Exception do ErrorText := E.Message; end;
  finally if H<>INVALID_HANDLE_VALUE then CloseHandle(H); end;
end;
var F: TMainForm; Output,JobPath,JobId,LayerId,OriginalName,Endpoint,Name,CancelledPath,RecoveryPath,RecoveryId,OldPipe: string;
  Pixels: TBytes; Count: Integer; Reply,Request,Manifest,Op: TJSONObject;
  Ops: TJSONArray; Before: TArtDocument; Rev,Started: UInt64; Raised: Boolean;
  H: THandle; ShutdownPayload: TBytes; Written: DWORD; B: Vcl.Graphics.TBitmap;
procedure Check(Value: Boolean; const Msg: string);
begin Inc(Count); if not Value then raise Exception.Create(Msg); end;
function SendRaw(const Text: string): TJSONObject;
var Client: TCommandClient; Deadline: UInt64;
begin
  Client := TCommandClient.Create(F.PipeName,Text); Client.Start; Deadline := GetTickCount64+10000;
  try
    while WaitForSingleObject(Client.Handle,0)=WAIT_TIMEOUT do begin
      Application.ProcessMessages; Sleep(1);
      if GetTickCount64>Deadline then begin Client.Terminate; CancelSynchronousIo(Client.Handle); raise Exception.Create('Response timeout'); end;
    end;
    if Client.ErrorText<>'' then raise Exception.Create(Client.ErrorText);
    Result := TJSONObject.ParseJSONValue(Client.Reply) as TJSONObject;
    if Result=nil then raise Exception.Create('Invalid response JSON');
  finally Client.Free; end;
end;
function Send(const Command,Args: string; Success: Boolean=True): TJSONObject;
var Text: TJSONObject;
begin
  Text := TJSONObject.Create;
  try
    Text.AddPair('schemaVersion',TJSONNumber.Create(1)); Text.AddPair('requestId','test-'+IntToStr(Count));
    Text.AddPair('command',Command); Text.AddPair('args',TJSONObject.ParseJSONValue(Args));
    Result := SendRaw(Text.ToJSON);
    Check(Result.GetValue<Boolean>('ok')=Success,'Unexpected command result: '+Command+' '+Result.ToJSON);
    Check(Result.GetValue<string>('requestId')=Text.GetValue<string>('requestId'),'Correlation lost');
  finally Text.Free; end;
end;
procedure ExportJob;
begin
  Reply := Send('export','{"prompt":"表情を変更"}');
  try
    JobPath := Reply.GetValue<TJSONObject>('data').GetValue<string>('directory');
    JobId := Reply.GetValue<TJSONObject>('data').GetValue<string>('jobId');
    Check(Reply.GetValue<TJSONObject>('data').GetValue<string>('state')='queued','Export state');
  finally Reply.Free; end;
end;
function JobArgs(const Extra: string=''): string;
begin Result := '{"jobId":"'+JobId+'"'+Extra+'}'; end;
procedure WriteResult;
begin
  Request := TJSONObject.ParseJSONValue(TFile.ReadAllText(TPath.Combine(JobPath,'request.json'))) as TJSONObject;
  Manifest := TJSONObject.Create;
  try
    for var Key in ['schemaVersion','requestId','jobId','documentId','ifRevision'] do Manifest.AddPair(Key,Request.GetValue(Key).Clone as TJSONValue);
    Manifest.AddPair('assets',TJSONArray.Create); Ops := TJSONArray.Create; Manifest.AddPair('operations',Ops);
    Op := TJSONObject.Create; Ops.AddElement(Op); Op.AddPair('op','rename_layer'); Op.AddPair('layerId',F.Document.Roots[0].Id); Op.AddPair('name','*AI結果:flipx');
    TFile.WriteAllText(TPath.Combine(JobPath,'result.json'),Manifest.ToJSON,TEncoding.UTF8);
  finally Request.Free; Manifest.Free; end;
end;
procedure CheckRecoveryProcess;
var Startup: TStartupInfo; Process: TProcessInformation; CommandLine: string; Deadline: UInt64; Code: DWORD;
begin
  ZeroMemory(@Startup,SizeOf(Startup)); Startup.cb := SizeOf(Startup);
  ZeroMemory(@Process,SizeOf(Process));
  CommandLine := '"'+ParamStr(0)+'" "'+Output+'" --recover-only "'+RecoveryPath+'"'; UniqueString(CommandLine);
  OSCheck(CreateProcess(nil,PChar(CommandLine),nil,nil,True,CREATE_NO_WINDOW,nil,nil,Startup,Process));
  try
    Deadline := GetTickCount64+10000;
    while WaitForSingleObject(Process.hProcess,10)=WAIT_TIMEOUT do begin
      Application.ProcessMessages;
      if GetTickCount64>Deadline then begin TerminateProcess(Process.hProcess,1); raise Exception.Create('Recovery child timed out'); end;
    end;
    OSCheck(GetExitCodeProcess(Process.hProcess,Code)); Check(Code=0,'Separate-process recovery failed');
    Check(FileExists(TPath.Combine(Output,'recovered_child.psd')),'Recovery child did not save');
  finally CloseHandle(Process.hThread); CloseHandle(Process.hProcess); end;
end;
function ConnectIdle(const Pipe: string): THandle;
var Deadline: UInt64;
begin
  Deadline := GetTickCount64+3000;
  repeat
    Result := CreateFile(PChar('\\.\pipe\'+Pipe),GENERIC_READ or GENERIC_WRITE,0,nil,OPEN_EXISTING,0,0);
    if Result<>INVALID_HANDLE_VALUE then Exit;
    if GetTickCount64>Deadline then raise Exception.Create('Idle connection timeout');
    Sleep(5);
  until False;
end;
begin
  try
    if (ParamCount=3) and (ParamStr(2)='--real-recovery') then begin
      Output := TPath.GetFullPath(ParamStr(1)); ForceDirectories(Output); Application.Initialize;
      F := TMainForm.CreateWithHistory(nil,TPath.Combine(Output,'real_history')); Before := nil;
      try
        F.OpenPsdFile(ParamStr(3)); Check(F.CanEdit,'Real PSD not editable'); Before := F.Document.Clone;
        Pixels := RenderPsdLayers(F.Document); LayerId := F.Document.Roots[0].Id;
        JobPath := F.ExportAiJob('実PSDジョブ復帰',TPath.Combine(Output,'real_jobs'));
        F.RecoverAiJob(JobPath); Check(F.Document.SourceRecordCount=Before.SourceRecordCount,'Real recovery source records');
        Check(F.Document.FindLayer(LayerId)<>nil,'Real recovery stable ID');
        Check(F.Document.Roots.Count=Before.Roots.Count,'Real recovery roots');
        var RestoredPixels := RenderPsdLayers(F.Document);
        Check((Length(Pixels)=Length(RestoredPixels)) and CompareMem(@Pixels[0],@RestoredPixels[0],Length(Pixels)),'Real recovery rendered pixels');
        F.ApplySelectedLayer('再開PSDテスト',True,128); F.Undo;
        Check(F.Document.Roots[0].Name=Before.Roots[0].Name,'Real recovery Undo name'); F.Redo;
        F.SavePsdFile(TPath.Combine(Output,'real_recovered.psd')); Check(not F.Modified,'Real recovery save');
      finally Before.Free; F.Free; end;
      Writeln('PASS: ',Count,' real PSD recovery assertions'); Exit;
    end;
    if (ParamCount=3) and (ParamStr(2)='--recover-only') then begin
      Application.Initialize; F := TMainForm.CreateWithHistory(nil,TPath.Combine(ParamStr(1),'child_history'));
      try
        F.RecoverAiJob(ParamStr(3)); Check(F.Document.Roots[0].Children.Count=1,'Child recovery hierarchy');
        F.ImportAiResult(TPath.Combine(ParamStr(3),'result.json')); Check(F.Document.Roots[0].Name='*AI結果:flipx','Child recovered result');
        F.SavePsdFile(TPath.Combine(ParamStr(1),'recovered_child.psd'));
      finally F.Free; end;
      Writeln('PASS: ',Count,' child-process recovery assertions'); Exit;
    end;
    if ParamCount<>1 then raise Exception.Create('Usage: Stage14Smoke OUTPUT_DIRECTORY');
    Output := TPath.GetFullPath(ParamStr(1)); ForceDirectories(Output);
    SetLength(Pixels,16*16*4); for var I := 0 to High(Pixels) do Pixels[I] := 255;
    WriteRgbaPng(TPath.Combine(Output,'source.png'),16,16,Pixels);
    Application.Initialize; Check(TStyleManager.TrySetStyle('Windows Modern Dark'),'Style missing');
    F := TMainForm.CreateWithHistory(nil,TPath.Combine(Output,'history'));
    try
      F.NewFromPng(TPath.Combine(Output,'source.png')); F.SavePsdFile(TPath.Combine(Output,'initial.psd'));
      OriginalName := F.Document.Roots[0].Name; LayerId := F.Document.Roots[0].Id;
      Check(not F.CanUndo and not F.CanRedo,'New baseline has history'); Rev := F.Document.Revision;
      F.ApplySelectedLayer('変更',False,128); Check(F.CanUndo,'Edit not recorded'); F.Undo;
      Check((F.Document.Roots[0].Name=OriginalName) and F.Document.Roots[0].Visible,'Undo attributes');
      Check(not F.Modified and F.CanRedo,'Undo clean state'); Check(F.Document.Revision>Rev,'Undo reused revision');
      Check(F.LayerList.Selected.Id=LayerId,'Undo selection');
      F.ApplySelectedLayer(OriginalName,True,255); Check(F.CanRedo,'No-op cleared redo');
      F.Redo; Check(F.Modified and (F.Document.Roots[0].Opacity=128),'Redo attributes');
      F.Undo; F.MoveSelectedLayer(2,3); Check(not F.CanRedo,'Branch kept redo'); F.Undo;
      Check((F.Document.Roots[0].Bounds.Left=0) and (F.Document.Roots[0].Bounds.Top=0),'Undo position');
      F.ImportPngFile(TPath.Combine(Output,'source.png')); Check(F.Document.Roots.Count=2,'PNG add'); F.Undo;
      Check(F.Document.Roots.Count=1,'Undo PNG add'); F.Redo; Check(F.Document.Roots.Count=2,'Redo PNG add'); F.Undo;
      F.CreateGroup('表情',False); Check(F.Document.Roots[0].Kind=alkGroup,'Group create'); F.Undo;
      Check(F.Document.Roots.Count=1,'Undo group');
      Pixels[0] := 90; Pixels[3] := 128; WriteRgbaPng(TPath.Combine(Output,'replacement.png'),16,16,Pixels);
      F.ReplaceSelectedPng(TPath.Combine(Output,'replacement.png'));
      Check(F.Document.Roots[0].Pixels[0]=90,'PNG replacement'); F.Undo;
      Check(F.Document.Roots[0].Pixels[0]=255,'Undo PNG replacement'); F.Redo;
      Check(F.Document.Roots[0].Pixels[3]=128,'Redo PNG alpha'); F.Undo;
      F.ImportPngFile(TPath.Combine(Output,'source.png')); F.ApplySelectedLayer('*a',True,255);
      F.LayerList.Selected := F.Document.Roots[1]; F.ApplySelectedLayer('*b',True,255);
      F.SelectPart(F.Document.Roots[0]); Check(F.Document.Roots[0].Visible and not F.Document.Roots[1].Visible,'Part switch');
      F.Undo; Check(not F.Document.Roots[0].Visible and F.Document.Roots[1].Visible,'Undo part selection');
      F.Redo; Check(F.Document.Roots[0].Visible and not F.Document.Roots[1].Visible,'Redo part selection');
      // Return to the one-layer baseline before the independent bound/pipe tests.
      F.OpenPsdFile(TPath.Combine(Output,'initial.psd'));
      F.SavePsdFile(TPath.Combine(Output,'baseline.psd')); Check(not F.CanUndo and not F.CanRedo,'Save retained history');
      Raised := False; try F.ImportPngFile(TPath.Combine(Output,'missing.png')); except on Exception do Raised := True; end;
      Check(Raised and not F.CanUndo,'Failed edit created history');
      for var I := 1 to 20 do F.MoveSelectedLayer(I,0);
      for var I := 1 to 16 do F.Undo;
      Check(F.Document.Roots[0].Bounds.Left=4,'Undo bound or contents'); Check(not F.CanUndo,'Undo bound exceeded');
      for var I := 1 to 16 do F.Redo;
      Check(F.Document.Roots[0].Bounds.Left=20,'Redo sequence');
      F.MoveSelectedLayer(0,0); F.SavePsdFile(TPath.Combine(Output,'pipe_baseline.psd'));
      Endpoint := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'),'AIArtToPSD\pipes\'+F.PipeName+'.json');
      Check(FileExists(Endpoint),'Endpoint discovery file missing');
      Reply := Send('status','{}');
      try Check(Reply.GetValue<TJSONObject>('data').GetValue<string>('pipeName')=F.PipeName,'Wrong endpoint'); finally Reply.Free; end;
      ExportJob; Check(FileExists(TPath.Combine(JobPath,'request.json')),'Export incomplete');
      Reply := Send('progress',JobArgs(',"state":"running","progress":33,"message":"生成中"')); Reply.Free;
      Check(Pos('33%',F.ActivityControl.Caption)>0,'Progress not visible');
      Reply := Send('progress',JobArgs(',"state":"ready","progress":100,"message":"完成"')); Reply.Free;
      WriteResult; Before := F.Document;
      Reply := Send('cancel',JobArgs); Reply.Free; CancelledPath := JobPath;
      Reply := Send('import',JobArgs,False); Reply.Free;
      Check((F.Document=Before) and not F.Modified and not F.Busy,'Cancelled import changed state');
      ExportJob;
      Reply := Send('import',JobArgs,False); Reply.Free; Check(not F.Busy,'Failure retained busy state');
      Reply := Send('progress',JobArgs(',"state":"failed","progress":0,"message":"生成失敗"')); Reply.Free;
      Check(Pos('失敗',F.ActivityControl.Caption)>0,'Failure not visible');
      WriteResult; Reply := Send('import',JobArgs); Reply.Free;
      Check(F.Modified and F.CanUndo and (F.Document.Roots[0].Name='*AI結果:flipx'),'Pipe import');
      Before := F.Document; Reply := Send('import',JobArgs); Reply.Free; Check(F.Document=Before,'Pipe repeated mutation');
      Reply := Send('progress',JobArgs(',"state":"running","progress":50,"message":"遅延"'),False); Reply.Free;
      Reply := Send('undo','{}'); Reply.Free;
      Check(F.Document.Roots[0].Name=OriginalName,'AI batch undo'); Check(not F.Modified,'AI undo baseline');
      Reply := Send('import',JobArgs,False); Reply.Free;
      Reply := Send('redo','{}'); Reply.Free; Check(F.Document.Roots[0].Name='*AI結果:flipx','AI batch redo');
      Reply := Send('status','{"jobId":"unknown"}',False); Reply.Free;
      Reply := SendRaw('{broken'); try Check(not Reply.GetValue<Boolean>('ok'),'Malformed JSON accepted'); finally Reply.Free; end;
      Reply := SendRaw('{"schemaVersion":1,"requestId":"a","requestId":"b","command":"status","args":{}}');
      try Check(not Reply.GetValue<Boolean>('ok'),'Duplicate field accepted'); finally Reply.Free; end;
      Reply := SendRaw(StringOfChar(' ',30001)); try Check(not Reply.GetValue<Boolean>('ok'),'Oversize command accepted'); finally Reply.Free; end;
      Reply := Send('status','{}'); Reply.Free;
      F.CreateGroup('表情',False); F.ImportPngFile(TPath.Combine(Output,'replacement.png'));
      ExportJob; WriteResult; RecoveryPath := JobPath; RecoveryId := F.Document.Roots[0].Id; OldPipe := F.PipeName;
      F.Show; Application.ProcessMessages; B := F.GetFormImage;
      try B.SaveToFile(TPath.Combine(Output,'stage14_ui.bmp')); finally B.Free; end;
    finally F.Free; end;
    Check(not FileExists(Endpoint),'Shutdown retained endpoint');
    CheckRecoveryProcess;
    F := TMainForm.CreateWithHistory(nil,TPath.Combine(Output,'recovery_history'));
    try
      Request := TJSONObject.Create;
      try Request.AddPair('directory',RecoveryPath); Reply := Send('recover',Request.ToJSON); Reply.Free;
      finally Request.Free; end;
      Check(F.PipeName<>OldPipe,'Restart retained old endpoint');
      Check((F.Document.Roots.Count=2) and (F.Document.Roots[0].Children.Count=1),'Recovery hierarchy');
      Check(F.Document.Roots[0].Id=RecoveryId,'Recovery stable IDs');
      Check(F.Modified and not F.CanUndo and not F.Busy,'Recovery state');
      Check(Pos('表情を変更',F.PromptControl.Text)>0,'Recovery prompt');
      Request := TJSONObject.Create;
      try Request.AddPair('directory',RecoveryPath); Reply := Send('recover',Request.ToJSON,False); Reply.Free;
      finally Request.Free; end;
      Check(F.Document.Roots[0].Id=RecoveryId,'Rejected remote recovery replaced dirty document');
      Reply := TJSONObject.ParseJSONValue(TFile.ReadAllText(TPath.Combine(RecoveryPath,'connection.json'))) as TJSONObject;
      try Check(Reply.GetValue<string>('pipeName')=F.PipeName,'Recovery worker endpoint not updated'); finally Reply.Free; end;
      F.ImportAiResult(TPath.Combine(RecoveryPath,'result.json'));
      Check(F.Document.Roots[0].Name='*AI結果:flipx','Recovered result rejected');
      F.Undo; Check(F.Document.Roots[0].Name='表情','Recovery undo'); F.Redo;
      F.SavePsdFile(TPath.Combine(Output,'recovered.psd')); Check(not F.Modified,'Recovery save');
      // Tampered metadata must preserve the open document and clear the busy state.
      TFile.WriteAllText(TPath.Combine(RecoveryPath,'request.json'),'{}',TEncoding.UTF8);
      Before := F.Document; Raised := False;
      try F.RecoverAiJob(RecoveryPath); except on EArtFormat do Raised := True; end;
      Check(Raised and (F.Document=Before) and not F.Busy,'Failed recovery changed document');
      F.RecoverAiJob(CancelledPath); Before := F.Document; Raised := False;
      try F.ImportAiResult(TPath.Combine(CancelledPath,'result.json')); except on EArtFormat do Raised := True; end;
      Check(Raised and (F.Document=Before),'Restart revived cancelled job');
      TFile.WriteAllBytes(TPath.Combine(CancelledPath,'snapshot.psd'),TBytes.Create(1,2,3));
      Raised := False; try F.RecoverAiJob(CancelledPath); except on EArtFormat do Raised := True; end;
      Check(Raised and (F.Document=Before) and not F.Busy,'Snapshot hash rejection changed document');
    finally F.Free; end;
    // Terminate workers while blocked in ConnectNamedPipe and ReadFile.
    for var I := 1 to 9 do begin
      F := TMainForm.CreateWithHistory(nil,TPath.Combine(Output,'lifecycle')); Name := F.PipeName;
      if I mod 3<>0 then H := ConnectIdle(Name) else H := INVALID_HANDLE_VALUE;
      if I mod 3=2 then begin
        // Leave the client connected without reading its response (FlushFileBuffers wait).
        ShutdownPayload := TEncoding.UTF8.GetBytes('{"schemaVersion":1,"requestId":"stop","command":"status","args":{}}');
        OSCheck(WriteFile(H,ShutdownPayload[0],Length(ShutdownPayload),Written,nil));
        Sleep(20); Application.ProcessMessages;
      end;
      Sleep(20); Started := GetTickCount64; F.Free;
      if H<>INVALID_HANDLE_VALUE then CloseHandle(H);
      Check(GetTickCount64-Started<2000,'Shutdown blocked');
    end;
    Writeln('PASS: ',Count,' stage 14 assertions');
  except on E: Exception do begin Writeln(E.ClassName,': ',E.Message); Halt(1); end; end;
end.

program ClientProtocolSmoke;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.JSON,
  ArtDocument in '..\Source\Core\ArtDocument.pas',
  ArtPipeProtocol in '..\Source\Integrations\Pipe\ArtPipeProtocol.pas';
type
  TFixture = class
    Protocol: TArtPipeProtocol;
    Calls: Integer;
    function Dispatch(const Command: string; Args: TJSONObject): TJSONObject;
  end;
procedure Check(Value: Boolean; const MessageText: string);
begin if not Value then raise Exception.Create(MessageText); end;
function TFixture.Dispatch(const Command: string; Args: TJSONObject): TJSONObject;
var Nested: string; Reply: TJSONObject;
begin
  Inc(Calls);
  if Command='fail' then raise Exception.Create('fixture failure');
  if Command='commit-fail' then begin
    Protocol.MarkCommitted;
    raise Exception.Create('fixture failure after publication');
  end;
  if Command='nested' then begin
    Protocol.Handle('{"schemaVersion":1,"requestId":"inner","client":"dot","command":"status","args":{}}',Nested);
    Reply := TJSONObject.ParseJSONValue(Nested) as TJSONObject;
    try
      Check(Reply.GetValue('ok').Value='false','Nested request was accepted');
      Check(Protocol.CurrentClient='codex','Nested request changed active client');
      Check(Protocol.CurrentRequestId='outer','Nested request changed active request ID');
    finally Reply.Free; end;
  end;
  Result := TJSONObject.Create; Result.AddPair('caller',Protocol.CurrentClient);
end;
procedure Send(F: TFixture; const Request,Client: string; ExpectedOk: Boolean);
var Raw: string; Reply: TJSONObject;
begin
  F.Protocol.Handle(Request,Raw);
  Reply := TJSONObject.ParseJSONValue(Raw) as TJSONObject;
  try
    Check((Reply.GetValue('ok').Value='true')=ExpectedOk,'Unexpected request outcome');
    Check(Reply.GetValue('client').Value=Client,'Unexpected response client');
    if Pos('"command":"commit-fail"',Request)>0 then
      Check(TJSONObject(Reply.GetValue('error')).GetValue('code').Value='command_committed',
        'Published failure was not identified');
    Check(not F.Protocol.Handling,'Active request was not released');
  finally Reply.Free; end;
end;
var F: TFixture; Contacts: TJSONArray;
begin
  try
    F := TFixture.Create;
    try
      F.Protocol := TArtPipeProtocol.Create(F.Dispatch);
      try
        Send(F,'{"schemaVersion":1,"requestId":"legacy","command":"status","args":{}}','codex',True);
        Send(F,'{"schemaVersion":1,"requestId":"dot-1","client":"dot","command":"status","args":{}}','dot',True);
        Send(F,'{"schemaVersion":1,"requestId":"bad","client":"other","command":"status","args":{}}','other',False);
        Check(F.Calls=2,'Invalid client reached dispatch');
        Send(F,'{"schemaVersion":1,"requestId":"failed","client":"dot","command":"fail","args":{}}','dot',False);
        Contacts := F.Protocol.ClientsJson;
        try
          Check(TJSONObject(Contacts[1]).GetValue('state').Value='failed','Failure contact was not recorded');
          Check(TJSONObject(Contacts[0]).GetValue('requestId').Value='legacy','dot overwrote Codex contact');
        finally Contacts.Free; end;
        Send(F,'{"schemaVersion":1,"requestId":"outer","command":"nested","args":{}}','codex',True);
        Check(F.Calls=4,'Reentrant request reached dispatch');
        Send(F,'{"schemaVersion":1,"requestId":"mutation","client":"dot","command":"increment","args":{}}','dot',True);
        Send(F,'{"client":"dot","command":"increment","args":{},"requestId":"mutation","schemaVersion":1}','dot',True);
        Check(F.Calls=5,'Same request was applied twice after JSON key reordering');
        Send(F,'{"schemaVersion":1,"requestId":"mutation","client":"dot","command":"increment","args":{"different":true}}','dot',False);
        Check(F.Calls=5,'Changed content reused a successful request ID');
        Send(F,'{"schemaVersion":1,"requestId":"open-once","client":"dot","command":"open","args":{"fileName":"fixture.psd"}}','dot',True);
        Send(F,'{"schemaVersion":1,"requestId":"open-once","client":"dot","command":"open","args":{"fileName":"fixture.psd"}}','dot',True);
        Check(F.Calls=6,'PSD open was applied twice');
        Send(F,'{"schemaVersion":1,"requestId":"published","command":"commit-fail","args":{}}','codex',False);
        Send(F,'{"schemaVersion":1,"requestId":"published","command":"commit-fail","args":{}}','codex',False);
        Check(F.Calls=7,'Published mutation was retried after an error');
        Contacts := F.Protocol.ClientsJson;
        try Check(TJSONObject(Contacts[0]).GetValue('state').Value='failed','Committed error replay lost failure state');
        finally Contacts.Free; end;
      finally F.Protocol.Free; end;
    finally F.Free; end;
    Writeln('PASS: legacy, dot, invalid client, failure, reentrancy and committed replay cases');
  except on E: Exception do begin Writeln(E.ClassName,': ',E.Message); Halt(1); end; end;
end.

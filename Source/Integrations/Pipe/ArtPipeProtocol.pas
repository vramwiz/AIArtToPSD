unit ArtPipeProtocol;
interface
uses System.SysUtils, System.JSON;
type
  TArtCommandHandler = function(const Command: string; Args: TJSONObject): TJSONObject of object;
  TArtPipeProtocol = class
  private
    FHandler: TArtCommandHandler;
  public
    constructor Create(Handler: TArtCommandHandler);
    procedure Handle(const Request: string; out Response: string);
  end;
function CommandString(Args: TJSONObject; const Key: string): string;
function CommandInteger(Args: TJSONObject; const Key: string): Integer;
implementation
uses System.Classes, System.Generics.Collections, ArtDocument;
function CommandString(Args: TJSONObject; const Key: string): string;
var V: TJSONValue;
begin
  V := Args.GetValue(Key);
  if not (V is TJSONString) then raise EArtFormat.Create('String required: '+Key);
  Result := V.Value;
end;
function CommandInteger(Args: TJSONObject; const Key: string): Integer;
var V: TJSONValue;
begin
  V := Args.GetValue(Key);
  if not (V is TJSONNumber) or not TryStrToInt(V.Value,Result) then raise EArtFormat.Create('Integer required: '+Key);
end;
procedure ValidateKeys(V: TJSONValue; Depth: Integer);
var Names: TDictionary<string,Boolean>;
begin
  if Depth>32 then raise EArtFormat.Create('Command nesting limit');
  if V is TJSONObject then begin
    Names := TDictionary<string,Boolean>.Create;
    try
      for var Pair in TJSONObject(V) do begin
        if Names.ContainsKey(Pair.JsonString.Value) then raise EArtFormat.Create('Duplicate command field');
        Names.Add(Pair.JsonString.Value,True); ValidateKeys(Pair.JsonValue,Depth+1);
      end;
    finally Names.Free; end;
  end else if V is TJSONArray then for var Item in TJSONArray(V) do ValidateKeys(Item,Depth+1);
end;
constructor TArtPipeProtocol.Create(Handler: TArtCommandHandler);
begin inherited Create; FHandler := Handler; end;
procedure TArtPipeProtocol.Handle(const Request: string; out Response: string);
var Value: TJSONValue; Envelope,Reply,Data,Error: TJSONObject; RequestId,Command: string;
begin
  Value := nil; Reply := TJSONObject.Create; RequestId := '';
  try
    Reply.AddPair('schemaVersion',TJSONNumber.Create(1));
    try
      if (Length(Request)<2) or (Length(Request)>30000) or (Length(TEncoding.UTF8.GetBytes(Request))>60000) then raise EArtFormat.Create('Command size limit');
      Value := TJSONObject.ParseJSONValue(Request); ValidateKeys(Value,0);
      if not (Value is TJSONObject) then raise EArtFormat.Create('Command object required');
      Envelope := TJSONObject(Value);
      if CommandInteger(Envelope,'schemaVersion')<>1 then raise EArtFormat.Create('Unsupported command schema');
      RequestId := CommandString(Envelope,'requestId');
      if (RequestId='') or (Length(RequestId)>128) then raise EArtFormat.Create('Invalid requestId');
      Command := CommandString(Envelope,'command');
      if not (Envelope.GetValue('args') is TJSONObject) then raise EArtFormat.Create('args object required');
      Data := FHandler(Command,TJSONObject(Envelope.GetValue('args')));
      Reply.AddPair('ok',TJSONBool.Create(True)); Reply.AddPair('data',Data);
    except on E: Exception do begin
      Reply.AddPair('ok',TJSONBool.Create(False)); Error := TJSONObject.Create;
      Error.AddPair('code','command_failed'); Error.AddPair('message',E.Message); Reply.AddPair('error',Error);
    end; end;
    Reply.AddPair('requestId',RequestId); Response := Reply.ToJSON;
  finally Value.Free; Reply.Free; end;
end;
end.

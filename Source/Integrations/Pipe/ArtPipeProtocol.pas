unit ArtPipeProtocol;
interface
uses System.SysUtils, System.JSON, System.Classes, System.Generics.Collections;
type
  TArtClientContact = record
    Seen: Boolean;
    LastSeenUtc: TDateTime;
    RequestId,Command,State: string;
  end;
  TArtCommandHandler = function(const Command: string; Args: TJSONObject): TJSONObject of object;
  TArtCachedReply = record
    RequestHash,Response: string;
    Succeeded: Boolean;
  end;
  TArtPipeProtocol = class
  private
    FHandler: TArtCommandHandler;
    FClient,FRequestId: string;
    FHandling,FMutationCommitted: Boolean;
    FCodex,FDot: TArtClientContact;
    FOnActivity: TNotifyEvent;
    FReplies: TDictionary<string,TArtCachedReply>;
    FReplyOrder: TQueue<string>;
    procedure RecordContact(const Client,RequestId,Command,State: string);
  public
    constructor Create(Handler: TArtCommandHandler);
    destructor Destroy; override;
    procedure Handle(const Request: string; out Response: string);
    // Cache an error too if a mutation was already published before a later failure.
    procedure MarkCommitted;
    function ClientsJson: TJSONArray;
    function ContactText(const Client: string): string;
    property CurrentClient: string read FClient;
    property CurrentRequestId: string read FRequestId;
    property Handling: Boolean read FHandling;
    property OnActivity: TNotifyEvent read FOnActivity write FOnActivity;
  end;
function CommandString(Args: TJSONObject; const Key: string): string;
function CommandInteger(Args: TJSONObject; const Key: string): Integer;
implementation
uses System.DateUtils, System.Hash, ArtDocument;
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
begin
  inherited Create; FHandler := Handler;
  FReplies := TDictionary<string,TArtCachedReply>.Create;
  FReplyOrder := TQueue<string>.Create;
end;
destructor TArtPipeProtocol.Destroy;
begin FReplyOrder.Free; FReplies.Free; inherited; end;
function CanonicalCommand(Value: TJSONValue): string;
var Names: TStringList; Key: TJSONString; First: Boolean;
begin
  if Value is TJSONObject then begin
    Names := TStringList.Create;
    try
      Names.CaseSensitive := True; Names.Sorted := True;
      for var Pair in TJSONObject(Value) do Names.Add(Pair.JsonString.Value);
      Result := '{'; First := True;
      for var Name in Names do begin
        if not First then Result := Result+','; First := False;
        Key := TJSONString.Create(Name);
        try Result := Result+Key.ToJSON+':'+CanonicalCommand(TJSONObject(Value).GetValue(Name));
        finally Key.Free; end;
      end;
      Result := Result+'}';
    finally Names.Free; end;
  end else if Value is TJSONArray then begin
    Result := '['; First := True;
    for var Item in TJSONArray(Value) do begin
      if not First then Result := Result+','; First := False;
      Result := Result+CanonicalCommand(Item);
    end;
    Result := Result+']';
  end else Result := Value.ToJSON;
end;
procedure TArtPipeProtocol.MarkCommitted;
begin if FHandling then FMutationCommitted := True; end;
procedure TArtPipeProtocol.RecordContact(const Client,RequestId,Command,State: string);
var Contact: TArtClientContact;
begin
  Contact.Seen := True; Contact.LastSeenUtc := TTimeZone.Local.ToUniversalTime(Now);
  Contact.RequestId := RequestId; Contact.Command := Command; Contact.State := State;
  if Client='dot' then FDot := Contact else FCodex := Contact;
end;
function TArtPipeProtocol.ClientsJson: TJSONArray;
  procedure Add(const Name: string; const Contact: TArtClientContact);
  var O: TJSONObject;
  begin
    O := TJSONObject.Create; Result.AddElement(O);
    O.AddPair('client',Name); O.AddPair('seen',TJSONBool.Create(Contact.Seen));
    if Contact.Seen then begin
      O.AddPair('lastSeenUtc',DateToISO8601(Contact.LastSeenUtc,True));
      O.AddPair('requestId',Contact.RequestId); O.AddPair('command',Contact.Command);
      O.AddPair('state',Contact.State);
    end;
  end;
begin Result := TJSONArray.Create; Add('codex',FCodex); Add('dot',FDot); end;
function TArtPipeProtocol.ContactText(const Client: string): string;
var Contact: TArtClientContact; StateText: string;
begin
  if Client='dot' then Contact := FDot else Contact := FCodex;
  if not Contact.Seen then Exit('未受信');
  StateText := '処理中';
  if Contact.State='succeeded' then StateText := '完了'
  else if Contact.State='failed' then StateText := '失敗';
  Result := '最終受信 '+FormatDateTime('hh:nn:ss',Contact.LastSeenUtc)+' UTC / '+StateText;
end;
procedure TArtPipeProtocol.Handle(const Request: string; out Response: string);
var Value: TJSONValue; Envelope,Reply,Data,Error: TJSONObject; RequestId,Command,Client: string;
    Started,Succeeded,Cacheable: Boolean; CacheKey,RequestHash: string; Cached: TArtCachedReply;
begin
  Value := nil; Reply := TJSONObject.Create; RequestId := ''; Client := '';
  Started := False; Succeeded := False;
  Cacheable := False;
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
      // Legacy schema-1 callers omit client and retain the Codex route.
      Client := 'codex';
      if Envelope.GetValue('client')<>nil then Client := CommandString(Envelope,'client');
      if (Client<>'codex') and (Client<>'dot') then raise EArtFormat.Create('Unsupported client');
      if FHandling then raise EArtFormat.Create('Another AI request is being processed');
      FClient := Client; FRequestId := RequestId; FHandling := True; Started := True;
      FMutationCommitted := False;
      RecordContact(Client,RequestId,Command,'processing');
      Cacheable := (Command<>'status') and (Command<>'document') and
        (Command<>'image-status') and (Command<>'preview') and (Command<>'preview-read');
      if Cacheable then begin
        CacheKey := Client+':'+RequestId; RequestHash := THashSHA2.GetHashString(CanonicalCommand(Envelope));
        if FReplies.TryGetValue(CacheKey,Cached) then begin
          if Cached.RequestHash<>RequestHash then raise EArtFormat.Create('requestId reused with different command content');
          Response := Cached.Response; Succeeded := Cached.Succeeded; Exit;
        end;
      end;
      Data := FHandler(Command,TJSONObject(Envelope.GetValue('args')));
      Reply.AddPair('ok',TJSONBool.Create(True)); Reply.AddPair('data',Data);
      Succeeded := True;
    except on E: Exception do begin
      Reply.AddPair('ok',TJSONBool.Create(False)); Error := TJSONObject.Create;
      if Started and FMutationCommitted then Error.AddPair('code','command_committed')
      else Error.AddPair('code','command_failed');
      Error.AddPair('message',E.Message); Reply.AddPair('error',Error);
    end; end;
    Reply.AddPair('requestId',RequestId); Reply.AddPair('client',Client); Response := Reply.ToJSON;
    if (Succeeded or (Started and FMutationCommitted)) and Cacheable then begin
      Cached.RequestHash := RequestHash; Cached.Response := Response;
      Cached.Succeeded := Succeeded;
      while FReplyOrder.Count>=64 do FReplies.Remove(FReplyOrder.Dequeue);
      FReplies.Add(CacheKey,Cached); FReplyOrder.Enqueue(CacheKey);
    end;
  finally
    if Started then begin
      FHandling := False;
      if Succeeded then RecordContact(Client,RequestId,Command,'succeeded')
      else RecordContact(Client,RequestId,Command,'failed');
    end;
    Value.Free; Reply.Free;
    if Started and Assigned(FOnActivity) then FOnActivity(Self);
  end;
end;
end.

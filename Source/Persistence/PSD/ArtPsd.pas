unit ArtPsd;

interface

uses System.SysUtils, ArtDocument;

function ReadPsd(const FileName: string): TArtDocument;
function RenderPsdLayers(Document: TArtDocument): TBytes;
procedure SaveImageCompositionPsd(Document: TArtDocument; const FileName: string);
procedure SaveLayerPropertiesPsd(Document: TArtDocument; const FileName: string);
procedure LoadPsd(var Document: TArtDocument; const FileName: string);
type TPsdCompression = (pcRaw, pcRle);
procedure WriteNewPsd(Document: TArtDocument; const FileName: string;
  Compression: TPsdCompression = pcRaw);
procedure SaveUnchangedPsd(Document: TArtDocument; const FileName: string);
procedure SaveEditedPsd(Document: TArtDocument; const FileName: string;
  Compression: TPsdCompression = pcRle);

implementation

uses
  System.Classes, System.IOUtils, System.Generics.Collections, Winapi.Windows;

type
  TReader = class
  private
    FData: TBytes;
  public
    Position, Limit: Integer;
    constructor Create(const Data: TBytes; Start, Finish: Integer);
    function U8: Byte;
    function U16: Word;
    function U32: Cardinal;
    function I16: SmallInt;
    function I32: Integer;
    function Bytes(Count: Integer): TBytes;
    function FourCC: AnsiString;
    procedure Skip(Count: Int64);
    function Block(Count: Cardinal): TReader;
    procedure CheckZeroTail;
  end;
  TChannel = record
    Id: SmallInt;
    Size: Cardinal;
  end;
  TChannels = TArray<TChannel>;
  TWriter = class(TMemoryStream)
    procedure U8(Value: Byte);
    procedure U16(Value: Word);
    procedure U32(Value: Cardinal);
    procedure FourCC(const Value: AnsiString);
    procedure Bytes(const Value: TBytes);
    procedure Block(Value: TMemoryStream);
    procedure Pad(Alignment: Integer; Start: Int64);
  end;

constructor TReader.Create(const Data: TBytes; Start, Finish: Integer);
begin
  inherited Create;
  FData := Data; Position := Start; Limit := Finish;
  if (Start < 0) or (Finish < Start) or (Finish > Length(Data)) then
    raise EArtFormat.Create('Invalid PSD reader bounds');
end;

procedure TReader.Skip(Count: Int64);
begin
  if (Count < 0) or (Count > Int64(Limit) - Position) then
    raise EArtFormat.CreateFmt('PSD boundary exceeded at %d', [Position]);
  Inc(Position, Integer(Count));
end;

function TReader.Bytes(Count: Integer): TBytes;
var Start: Integer;
begin
  Start := Position; Skip(Count);
  Result := Copy(FData, Start, Count);
end;

function TReader.U8: Byte;
begin
  Skip(1); Result := FData[Position-1];
end;

function TReader.U16: Word;
var A: Word;
begin A := U8; Result := (A shl 8) or U8; end;

function TReader.U32: Cardinal;
var A: Cardinal;
begin A := U16; Result := (A shl 16) or U16; end;

function TReader.I16: SmallInt;
var V: Word;
begin V := U16; Move(V, Result, 2); end;

function TReader.I32: Integer;
var V: Cardinal;
begin V := U32; Move(V, Result, 4); end;

function TReader.FourCC: AnsiString;
var I: Integer;
begin
  SetLength(Result, 4);
  for I := 1 to 4 do Result[I] := AnsiChar(U8);
end;

function TReader.Block(Count: Cardinal): TReader;
var Start: Integer;
begin
  Start := Position; Skip(Count);
  Result := TReader.Create(FData, Start, Position);
end;

procedure TReader.CheckZeroTail;
begin
  while Position < Limit do
    if U8 <> 0 then raise EArtFormat.Create('Nonzero padding');
end;

procedure TWriter.U8(Value: Byte);
begin WriteBuffer(Value, 1); end;

procedure TWriter.U16(Value: Word);
begin U8(Byte(Value shr 8)); U8(Byte(Value and $FF)); end;

procedure TWriter.U32(Value: Cardinal);
begin U16(Word(Value shr 16)); U16(Word(Value and $FFFF)); end;

procedure TWriter.FourCC(const Value: AnsiString);
begin
  if Length(Value) <> 4 then raise EArtFormat.Create('Invalid four-character key');
  WriteBuffer(Value[1], 4);
end;

procedure TWriter.Bytes(const Value: TBytes);
begin if Length(Value) <> 0 then WriteBuffer(Value[0], Length(Value)); end;

procedure TWriter.Block(Value: TMemoryStream);
begin
  if UInt64(Value.Size) > High(Cardinal) then raise EArtFormat.Create('PSD block too large');
  U32(Cardinal(Value.Size));
  if Value.Size <> 0 then WriteBuffer(Value.Memory^, Value.Size);
end;

procedure TWriter.Pad(Alignment: Integer; Start: Int64);
begin while (Position - Start) mod Alignment <> 0 do U8(0); end;

procedure Unsupported(D: TArtDocument; const Reason: string);
begin if D.Unsupported.IndexOf(Reason) < 0 then D.Unsupported.Add(Reason); end;

function SameLayerMask(A,B: TArtLayer): Boolean;
begin
  Result := (A.HasMask=B.HasMask) and (A.MaskDisabled=B.MaskDisabled) and
    (A.MaskInvert=B.MaskInvert) and (A.MaskDefault=B.MaskDefault) and
    CompareMem(@A.MaskBounds,@B.MaskBounds,SizeOf(TArtBounds)) and
    (Length(A.MaskPixels)=Length(B.MaskPixels));
  if Result and (Length(A.MaskPixels)>0) then
    Result := CompareMem(@A.MaskPixels[0],@B.MaskPixels[0],Length(A.MaskPixels));
end;

procedure ReadTags(R: TReader; Layer: TArtLayer; D: TArtDocument; Alignment: Integer);
var Sig, Key: AnsiString; B: TReader; N, Chars: Cardinal; S: string; I: Integer;
begin
  while R.Limit - R.Position >= 12 do begin
    Sig := R.FourCC;
    if (Sig <> '8BIM') and (Sig <> '8B64') then raise EArtFormat.Create('Invalid additional-info signature');
    Key := R.FourCC; N := R.U32; B := R.Block(N);
    try
      if Assigned(Layer) and (Key = 'luni') then begin
        Chars := B.U32;
        if UInt64(Chars) * 2 > UInt64(B.Limit - B.Position) then raise EArtFormat.Create('Invalid Unicode name length');
        SetLength(S, Chars);
        for I := 1 to Length(S) do S[I] := Char(B.U16);
        Layer.Name := S;
      end else if Assigned(Layer) and ((Key = 'lsct') or (Key = 'lsdk')) then begin
        Layer.SectionType := B.U32;
        case Layer.SectionType of
          0: Layer.Kind := alkImage;
          1,2: Layer.Kind := alkGroup;
          3: Layer.Kind := alkDivider;
        else raise EArtFormat.Create('Unknown group section type'); end;
      end else if Assigned(Layer) and ((Key='knko') or (Key='infx') or (Key='clbl')) then begin
        if N<>4 then Unsupported(D,'Extended compositing metadata: '+string(Key))
        else begin
          Chars := B.U8;
          B.CheckZeroTail;
          if ((Key='clbl') and (Chars<>1)) or ((Key<>'clbl') and (Chars<>0)) then
            Unsupported(D,'Special compositing metadata: '+string(Key));
        end;
      end else if (Key <> 'lyid') then Unsupported(D, 'Additional info retained in archive: ' + string(Key));
    finally B.Free; end;
    if Alignment > 1 then R.Skip((Alignment - (Int64(N) mod Alignment)) mod Alignment);
  end;
  R.CheckZeroTail;
end;

function ReadLayer(R: TReader; D: TArtDocument; Index: Integer; out Channels: TChannels): TArtLayer;
var L: TArtLayer; E, B: TReader; I, J, N, LengthByte: Integer; V: Cardinal; Legacy: TBytes;
    Encoding: TEncoding; Flags: Byte;
begin
  L := D.NewUnattachedLayer;
  L.SourceIndex := Index;
  L.Bounds.Top := R.I32; L.Bounds.Left := R.I32;
  L.Bounds.Bottom := R.I32; L.Bounds.Right := R.I32;
  PixelByteCount(L.Bounds.Width, L.Bounds.Height, 4);
  N := R.U16;
  if N > 56 then raise EArtFormat.Create('Too many layer channels');
  SetLength(Channels, N);
  for I := 0 to N-1 do begin
    Channels[I].Id := R.I16; Channels[I].Size := R.U32;
    for J := 0 to I-1 do
      if Channels[J].Id = Channels[I].Id then raise EArtFormat.Create('Duplicate layer channel ID');
  end;
  if R.FourCC <> '8BIM' then raise EArtFormat.Create('Invalid layer blend signature');
  L.BlendKey := R.FourCC; L.Opacity := R.U8; L.Clipping := R.U8;
  L.Visible := (R.U8 and 2) = 0;
  if R.U8 <> 0 then raise EArtFormat.Create('Nonzero layer reserved byte');
  V := R.U32; E := R.Block(V);
  try
    V := E.U32; B := E.Block(V);
    try
      if V=20 then begin
        L.MaskBounds.Top := B.I32; L.MaskBounds.Left := B.I32;
        L.MaskBounds.Bottom := B.I32; L.MaskBounds.Right := B.I32;
        PixelByteCount(L.MaskBounds.Width,L.MaskBounds.Height,1);
        L.MaskDefault := B.U8; Flags := B.U8;
        L.MaskDisabled := (Flags and 2)<>0; L.MaskInvert := (Flags and 4)<>0;
        if ((Flags and $F9)<>0) or ((L.MaskDefault<>0) and (L.MaskDefault<>255)) then
          Unsupported(D,'Mask flags/default not implemented')
        else L.HasMask := True;
        B.CheckZeroTail;
      end else if V<>0 then Unsupported(D,'Extended layer mask not implemented');
    finally B.Free; end;
    V := E.U32; B := E.Block(V);
    try
      Flags := 0;
      if V mod 8<>0 then Flags := 1;
      while B.Limit-B.Position>=4 do if B.U32<>$0000FFFF then Flags := 1;
      B.Skip(B.Limit-B.Position);
      if Flags<>0 then Unsupported(D,'Non-default layer blending ranges');
    finally B.Free; end;
    LengthByte := E.U8; Legacy := E.Bytes(LengthByte);
    E.Skip((4 - ((LengthByte+1) mod 4)) mod 4);
    Encoding := TEncoding.GetEncoding(932);
    try L.Name := Encoding.GetString(Legacy); finally Encoding.Free; end;
    ReadTags(E, L, D, 1);
  finally E.Free; end;
  if L.HasMask and (L.Kind<>alkImage) then Unsupported(D,'Group mask rendering not implemented');
  if L.Clipping <> 0 then Unsupported(D, 'Clipping rendering not implemented');
  if ((L.Kind = alkImage) and (L.BlendKey <> 'norm')) or
    ((L.Kind = alkGroup) and (L.BlendKey <> 'norm') and ((L.BlendKey <> 'pass') or (L.Opacity <> 255))) then
    Unsupported(D, 'Blend/group rendering not implemented: ' + string(L.BlendKey));
  Result := L;
end;

function DecodePlane(R: TReader; Width, Height: Integer): TBytes;
var Compression: Word; Sizes: TArray<Word>; Y, X, N, Count, I, P: Integer;
    Row: TReader; Value: Byte;
begin
  SetLength(Result, PixelByteCount(Width, Height, 1));
  Compression := R.U16;
  case Compression of
    0: Result := R.Bytes(Length(Result));
    1: begin
      SetLength(Sizes, Height);
      for Y := 0 to Height-1 do Sizes[Y] := R.U16;
      for Y := 0 to Height-1 do begin
        Row := R.Block(Sizes[Y]); X := 0;
        try
          while Row.Position < Row.Limit do begin
            N := Row.U8;
            if N = 128 then Continue;
            if N < 128 then Count := N+1 else Count := 257-N;
            if X + Count > Width then raise EArtFormat.Create('PackBits row overflow');
            P := Y * Width + X;
            if N < 128 then
              for I := 0 to Count-1 do Result[P+I] := Row.U8
            else begin
              Value := Row.U8;
              for I := 0 to Count-1 do Result[P+I] := Value;
            end;
            Inc(X, Count);
          end;
          if X <> Width then raise EArtFormat.Create('PackBits row underflow');
        finally Row.Free; end;
      end;
    end;
  else raise EArtFormat.CreateFmt('Unsupported PSD compression %d', [Compression]); end;
  if R.Position <> R.Limit then raise EArtFormat.Create('Channel length mismatch');
end;

procedure BuildTree(D: TArtDocument; const Records: TArray<TArtLayer>);
var Stack: TStack<TArtLayer>; L, Parent: TArtLayer; I: Integer;
begin
  Stack := TStack<TArtLayer>.Create;
  try
    for I := High(Records) downto 0 do begin
      L := Records[I];
      if L.Kind = alkDivider then begin
        if Stack.Count = 0 then raise EArtFormat.Create('Unmatched PSD group divider');
        Stack.Pop; Continue;
      end;
      if Stack.Count = 0 then D.Roots.Add(L)
      else begin Parent := Stack.Peek; Parent.Children.Add(L); end;
      if L.Kind = alkGroup then begin
        if Stack.Count >= 128 then raise EArtFormat.Create('Group nesting too deep');
        Stack.Push(L);
      end;
    end;
    if Stack.Count <> 0 then raise EArtFormat.Create('Unclosed PSD group');
  finally Stack.Free; end;
end;

procedure ReadMerged(R: TReader; D: TArtDocument; Channels: Integer);
var Compression: Word; C, Y, I, DataStart, EncodedSize: Integer;
    Sizes: TArray<Word>; B: TReader; Synthetic: TWriter; Data: TBytes;
begin
  Compression := R.U16;
  SetLength(D.MergedPlanes, Channels);
  case Compression of
    0: for C := 0 to Channels-1 do D.MergedPlanes[C] := R.Bytes(PixelByteCount(D.Width,D.Height,1));
    1: begin
      SetLength(Sizes, D.Height * Channels);
      for I := 0 to High(Sizes) do Sizes[I] := R.U16;
      for C := 0 to Channels-1 do begin
        EncodedSize := 0;
        for Y := 0 to D.Height-1 do Inc(EncodedSize, Sizes[C*D.Height+Y]);
        DataStart := R.Position; B := R.Block(EncodedSize);
        Synthetic := TWriter.Create;
        try
          Synthetic.U16(1);
          for Y := 0 to D.Height-1 do Synthetic.U16(Sizes[C*D.Height+Y]);
          Data := B.Bytes(EncodedSize); Synthetic.Bytes(Data);
          SetLength(Data, Synthetic.Size); Move(Synthetic.Memory^, Data[0], Length(Data));
          FreeAndNil(B); B := TReader.Create(Data,0,Length(Data));
          D.MergedPlanes[C] := DecodePlane(B,D.Width,D.Height);
        finally B.Free; Synthetic.Free; end;
        if R.Position <> DataStart + EncodedSize then raise EArtFormat.Create('Merged channel positioning failed');
      end;
    end;
  else raise EArtFormat.Create('Merged image compression not implemented'); end;
  if R.Position <> R.Limit then Unsupported(D, 'Unexplained PSD trailing data retained in archive');
end;

function ReadPsd(const FileName: string): TArtDocument;
var D: TArtDocument; R, B, Info, CReader: TReader;
    FS: TFileStream; Data, Plane: TBytes;
    Channels, I, J, P, ColorIndex, Count, SignedCount: Integer;
    ChannelLists: TArray<TChannels>; Records: TArray<TArtLayer>;
    L: TArtLayer; V: Cardinal; Budget: Int64;
begin
  FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    if (FS.Size < 26) or (FS.Size > ART_MAX_BYTES) then raise EArtFormat.Create('PSD file size limit');
    SetLength(Data, FS.Size); FS.ReadBuffer(Data[0], Length(Data));
  finally FS.Free; end;
  D := TArtDocument.Create;
  R := TReader.Create(Data,0,Length(Data));
  try
    try
      D.SourceBytes := Data;
      if R.FourCC <> '8BPS' then raise EArtFormat.Create('Not a PSD file');
      if R.U16 <> 1 then raise EArtFormat.Create('Only PSD version 1 implemented');
      for I := 1 to 6 do if R.U8 <> 0 then raise EArtFormat.Create('Invalid PSD reserved bytes');
      Channels := R.U16;
      if (Channels < 3) or (Channels > 56) then raise EArtFormat.Create('Invalid RGB channel count');
      V := R.U32; if (V < 1) or (V > 30000) then raise EArtFormat.Create('Invalid canvas height'); D.Height := Integer(V);
      V := R.U32; if (V < 1) or (V > 30000) then raise EArtFormat.Create('Invalid canvas width'); D.Width := Integer(V);
      PixelByteCount(D.Width,D.Height,Channels);
      if R.U16 <> 8 then raise EArtFormat.Create('Only 8-bit PSD implemented');
      if R.U16 <> 3 then raise EArtFormat.Create('Only RGB PSD implemented');
      V := R.U32; R.Skip(V);
      if V <> 0 then Unsupported(D,'RGB color-mode payload retained');
      V := R.U32; R.Skip(V);
      if V <> 0 then Unsupported(D,'Image resources retained in source archive');
      V := R.U32; B := R.Block(V);
      try
        Budget := Length(Data) + Int64(D.Width)*D.Height*Channels;
        if Budget > ART_MAX_BYTES then raise EArtFormat.Create('PSD decoded memory limit');
        if V <> 0 then begin
          V := B.U32; Info := B.Block(V);
          try
            if V <> 0 then begin
              SignedCount := Info.I16; D.MergedHasTransparency := SignedCount < 0;
              Count := Abs(SignedCount); D.SourceRecordCount := Count;
              SetLength(Records,Count); SetLength(ChannelLists,Count);
              for I := 0 to Count-1 do Records[I] := ReadLayer(Info,D,I,ChannelLists[I]);
              for I := 0 to Count-1 do begin
                L := Records[I];
                if L.Kind = alkImage then begin
                  Inc(Budget, PixelByteCount(L.Bounds.Width,L.Bounds.Height,4));
                  if Budget > ART_MAX_BYTES then raise EArtFormat.Create('Document image budget exceeded');
                  SetLength(L.Pixels,PixelByteCount(L.Bounds.Width,L.Bounds.Height,4));
                  for P := 0 to Length(L.Pixels) div 4-1 do L.Pixels[P*4+3] := 255;
                end;
                for J := 0 to High(ChannelLists[I]) do begin
                  CReader := Info.Block(ChannelLists[I][J].Size);
                  try
                    ColorIndex := ChannelLists[I][J].Id;
                    if ColorIndex = -1 then ColorIndex := 3
                    else if ColorIndex > 2 then ColorIndex := -1;
                    if (L.Kind=alkImage) and L.HasMask and (ChannelLists[I][J].Id=-2) then begin
                      Inc(Budget,PixelByteCount(L.MaskBounds.Width,L.MaskBounds.Height,1));
                      if Budget>ART_MAX_BYTES then raise EArtFormat.Create('Mask image budget exceeded');
                      L.MaskPixels := DecodePlane(CReader,L.MaskBounds.Width,L.MaskBounds.Height);
                    end else if (L.Kind = alkImage) and (ColorIndex >= 0) and (ColorIndex <= 3) then begin
                      Plane := DecodePlane(CReader,L.Bounds.Width,L.Bounds.Height);
                      for P := 0 to High(Plane) do L.Pixels[P*4+ColorIndex] := Plane[P];
                    end else if ChannelLists[I][J].Id < -1 then Unsupported(D,'Mask channel retained without rendering')
                    else if ChannelLists[I][J].Id > 2 then Unsupported(D,'Additional layer channel retained');
                  finally CReader.Free; end;
                end;
              end;
              for I := 0 to Count-1 do
                if Records[I].HasMask and (Records[I].Kind=alkImage) then begin
                  ColorIndex := 0;
                  for J := 0 to High(ChannelLists[I]) do
                    if ChannelLists[I][J].Id=-2 then Inc(ColorIndex);
                  if (ColorIndex<>1) or
                    (Length(Records[I].MaskPixels)<>PixelByteCount(Records[I].MaskBounds.Width,Records[I].MaskBounds.Height,1)) then
                    raise EArtFormat.Create('Missing mask channel data');
                end;
              Info.CheckZeroTail;
              BuildTree(D,Records);
            end;
          finally Info.Free; end;
          if B.Limit - B.Position >= 4 then begin
            V := B.U32; B.Skip(V);
            if V <> 0 then Unsupported(D,'Global mask retained');
          end;
          ReadTags(B,nil,D,4);
        end;
      finally B.Free; end;
      ReadMerged(R,D,Channels);
      Result := D;
    except D.Free; raise; end;
  finally R.Free; end;
end;

function RenderPsdLayers(Document: TArtDocument): TBytes;
var Snapshot: TArtDocument; Reason: string;
  procedure CopyLayers(List: TList<TArtLayer>; Parent: TArtLayer);
  var L,N: TArtLayer;
  begin
    for L in List do begin
      N := Snapshot.AddLayer(L.Kind,L.Name,L.Bounds,Parent);
      N.Pixels := L.Pixels; N.Visible := L.Visible; N.Opacity := L.Opacity;
      N.BlendKey := L.BlendKey; N.Clipping := L.Clipping; N.SectionType := L.SectionType;
      N.HasMask := L.HasMask; N.MaskBounds := L.MaskBounds; N.MaskDefault := L.MaskDefault;
      N.MaskDisabled := L.MaskDisabled; N.MaskInvert := L.MaskInvert; N.MaskPixels := L.MaskPixels;
      CopyLayers(L.Children,N);
    end;
  end;
begin
  for Reason in Document.Unsupported do
    if (Reason<>'Image resources retained in source archive') and
       (Reason<>'Additional info retained in archive: lspf') and
       (Reason<>'Additional info retained in archive: lclr') and
       (Reason<>'Additional info retained in archive: lyvr') and
       (Reason<>'Global mask retained') and
       (Reason<>'Additional info retained in archive: Patt') and
       (Reason<>'Additional info retained in archive: FMsk') then raise EArtFormat.Create(Reason);
  Snapshot := TArtDocument.Create;
  try
    Snapshot.Width := Document.Width; Snapshot.Height := Document.Height;
    CopyLayers(Document.Roots,nil); Result := Snapshot.RenderRGBA;
  finally Snapshot.Free; end;
end;

procedure LoadPsd(var Document: TArtDocument; const FileName: string);
var NewDocument, OldDocument: TArtDocument;
begin
  NewDocument := ReadPsd(FileName);
  OldDocument := Document; Document := NewDocument; OldDocument.Free;
end;

procedure WriteUnicodeTag(W: TWriter; const Name: string);
var Data: TWriter; I: Integer;
begin
  Data := TWriter.Create;
  try
    Data.U32(Length(Name));
    for I := 1 to Length(Name) do Data.U16(Ord(Name[I]));
    W.FourCC('8BIM'); W.FourCC('luni'); W.Block(Data);
  finally Data.Free; end;
end;

function EncodePlane(const Pixels: TBytes; Width, Height, Channel: Integer;
  Compression: TPsdCompression; Stride: Integer = 4): TBytes;
var W, Rows: TWriter; Sizes: TArray<Word>; Y, X, I, Run, Start, N: Integer;
    function Value(Col: Integer): Byte;
    begin Result := Pixels[(Y*Width+Col)*Stride+Channel]; end;
begin
  W := TWriter.Create; Rows := TWriter.Create;
  try
    W.U16(Ord(Compression));
    if Compression = pcRaw then begin
      for I := 0 to Width*Height-1 do W.U8(Pixels[I*Stride+Channel]);
    end else begin
      SetLength(Sizes,Height);
      for Y := 0 to Height-1 do begin
        Start := Rows.Position; X := 0;
        while X < Width do begin
          Run := 1;
          while (Run < 128) and (X+Run < Width) and (Value(X)=Value(X+Run)) do Inc(Run);
          if Run >= 3 then begin
            Rows.U8(257-Run); Rows.U8(Value(X)); Inc(X,Run);
          end else begin
            I := X; Inc(X,Run);
            while (X < Width) and (X-I < 128) do begin
              Run := 1;
              while (Run < 3) and (X+Run < Width) and (Value(X)=Value(X+Run)) do Inc(Run);
              if Run >= 3 then Break;
              Inc(X);
            end;
            N := X-I; Rows.U8(N-1);
            while I < X do begin Rows.U8(Value(I)); Inc(I); end;
          end;
        end;
        if Rows.Position-Start > High(Word) then raise EArtFormat.Create('RLE row too long');
        Sizes[Y] := Word(Rows.Position-Start);
      end;
      for Y := 0 to Height-1 do W.U16(Sizes[Y]);
      if Rows.Size > 0 then W.WriteBuffer(Rows.Memory^,Rows.Size);
    end;
    SetLength(Result,W.Size);
    if W.Size > 0 then Move(W.Memory^,Result[0],W.Size);
  finally W.Free; Rows.Free; end;
end;

procedure WriteMaskBlock(W: TWriter; L: TArtLayer; Divider: Boolean);
var F: Byte;
begin
  if Divider or not L.HasMask then begin W.U32(0); Exit; end;
  W.U32(20); W.U32(Cardinal(L.MaskBounds.Top)); W.U32(Cardinal(L.MaskBounds.Left));
  W.U32(Cardinal(L.MaskBounds.Bottom)); W.U32(Cardinal(L.MaskBounds.Right));
  W.U8(L.MaskDefault); F := 0;
  if L.MaskDisabled then F := F or 2;
  if L.MaskInvert then F := F or 4;
  W.U8(F); W.U16(0);
end;

procedure WriteRecord(W: TWriter; L: TArtLayer; Divider: Boolean; Id: Cardinal; const Channels: TArray<TBytes>);
var E: TWriter; Count, C: Integer; Typ: Cardinal; Bounds: TArtBounds;
begin
  Bounds := L.Bounds;
  Count := 0;
  if not Divider and (L.Kind = alkImage) then Count := Length(Channels)
  else Bounds := TArtBounds.Create(0,0,0,0);
  W.U32(Cardinal(Bounds.Top)); W.U32(Cardinal(Bounds.Left));
  W.U32(Cardinal(Bounds.Bottom)); W.U32(Cardinal(Bounds.Right));
  W.U16(Count);
  for C := 0 to Count-1 do begin
    if C = 3 then W.U16($FFFF) else if C=4 then W.U16($FFFE) else W.U16(C);
    W.U32(Length(Channels[C]));
  end;
  W.FourCC('8BIM');
  if Divider then W.FourCC('norm') else W.FourCC(L.BlendKey);
  if Divider then W.U8(255) else W.U8(L.Opacity);
  W.U8(0);
  if Divider or not L.Visible then W.U8(2) else W.U8(0);
  W.U8(0);
  E := TWriter.Create;
  try
    WriteMaskBlock(E,L,Divider); E.U32(0); // No blending ranges.
    E.U8(0); E.U8(0); E.U8(0); E.U8(0); // Empty legacy name, padded to 4.
    if Divider then WriteUnicodeTag(E,'</Layer group>') else WriteUnicodeTag(E,L.Name);
    E.FourCC('8BIM'); E.FourCC('lyid'); E.U32(4); E.U32(Id);
    if Divider or (L.Kind = alkGroup) then begin
      if Divider then Typ := 3 else if L.SectionType = 2 then Typ := 2 else Typ := 1;
      E.FourCC('8BIM'); E.FourCC('lsct'); E.U32(4); E.U32(Typ);
    end;
    W.Block(E);
  finally E.Free; end;
end;

procedure WriteNewPsd(Document: TArtDocument; const FileName: string;
  Compression: TPsdCompression);
var Output, Info, LayerMask: TWriter;
    Records: TList<TArtLayer>; Dividers: TList<Boolean>; L: TArtLayer;
    I, C, P, Y: Integer; Composite: TBytes;
    Encoded: TArray<TArray<TBytes>>; Merged: TArray<TBytes>; A, Value: Integer;
    TempName, Destination: string; G: TGUID; Check: TArtDocument;
  procedure Flatten(List: TList<TArtLayer>);
  var I: Integer; L: TArtLayer;
  begin
    for I := List.Count-1 downto 0 do begin
      L := List[I];
      if L.Kind = alkGroup then begin
        Records.Add(L); Dividers.Add(True); Flatten(L.Children);
      end;
      Records.Add(L); Dividers.Add(False);
    end;
  end;
begin
  Document.ValidateForNewSave;
  Composite := Document.RenderRGBA;
  Records := TList<TArtLayer>.Create; Dividers := TList<Boolean>.Create;
  Output := TWriter.Create; Info := TWriter.Create; LayerMask := TWriter.Create;
  TempName := '';
  try
    Flatten(Document.Roots);
    Info.U16(Word($10000 - Records.Count)); // First merged alpha is document transparency.
    SetLength(Encoded,Records.Count);
    for I := 0 to Records.Count-1 do begin
      L := Records[I];
      if Dividers[I] or (L.Kind <> alkImage) then Continue;
      SetLength(Encoded[I],4+Ord(L.HasMask));
      for C := 0 to 3 do Encoded[I][C] := EncodePlane(L.Pixels,L.Bounds.Width,L.Bounds.Height,C,Compression);
      if L.HasMask then Encoded[I][4] := EncodePlane(L.MaskPixels,L.MaskBounds.Width,L.MaskBounds.Height,0,Compression,1);
    end;
    for I := 0 to Records.Count-1 do WriteRecord(Info,Records[I],Dividers[I],I+1,Encoded[I]);
    for I := 0 to Records.Count-1 do begin
      L := Records[I];
      if Dividers[I] or (L.Kind <> alkImage) then Continue;
      for C := 0 to High(Encoded[I]) do begin
        Info.Bytes(Encoded[I][C]);
      end;
    end;
    Info.Pad(2,0);
    LayerMask.Block(Info); LayerMask.U32(0);
    Output.FourCC('8BPS'); Output.U16(1);
    for I := 1 to 6 do Output.U8(0);
    Output.U16(4); Output.U32(Document.Height); Output.U32(Document.Width);
    Output.U16(8); Output.U16(3); Output.U32(0); Output.U32(0);
    Output.Block(LayerMask);
    // Merged RGB is white-matted; alpha is a separate plane.
    for P := 0 to Length(Composite) div 4-1 do begin
      A := Composite[P*4+3];
      for C := 0 to 2 do begin
        Value := (Composite[P*4+C]*A + 255*(255-A) + 127) div 255;
        Composite[P*4+C] := Value;
      end;
    end;
    SetLength(Merged,4);
    for C := 0 to 3 do Merged[C] := EncodePlane(Composite,Document.Width,Document.Height,C,Compression);
    Output.U16(Ord(Compression));
    if Compression = pcRle then
      for C := 0 to 3 do
        for Y := 0 to Document.Height-1 do begin
          Output.U8(Merged[C][2+Y*2]); Output.U8(Merged[C][3+Y*2]);
        end;
    for C := 0 to 3 do begin
      if Compression = pcRle then P := 2+Document.Height*2 else P := 2;
      if Length(Merged[C]) > P then Output.WriteBuffer(Merged[C][P],Length(Merged[C])-P);
    end;
    Destination := TPath.GetFullPath(FileName);
    CreateGUID(G); TempName := Destination + '.' + GUIDToString(G) + '.tmp';
    Output.SaveToFile(TempName);
    Check := ReadPsd(TempName);
    try
      if (Check.Width <> Document.Width) or (Check.Height <> Document.Height) or
         (Check.SourceRecordCount <> Records.Count) then raise EArtFormat.Create('PSD write verification failed');
    finally Check.Free; end;
    if not MoveFileEx(PChar(TempName),PChar(Destination),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
      RaiseLastOSError;
    TempName := '';
  finally
    if (TempName <> '') and TFile.Exists(TempName) then TFile.Delete(TempName);
    Output.Free; Info.Free; LayerMask.Free; Records.Free; Dividers.Free;
  end;
end;

procedure SaveUnchangedPsd(Document: TArtDocument; const FileName: string);
var Original: TArtDocument; TempName, Destination: string; G: TGUID;
    I: Integer;
  function SameBytes(const A,B: TBytes): Boolean;
  begin
    Result := Length(A)=Length(B);
    if Result and (Length(A)>0) then Result := CompareMem(@A[0],@B[0],Length(A));
  end;
  procedure CompareLayers(A,B: TList<TArtLayer>; Depth: Integer);
  var J: Integer; L,R: TArtLayer;
  begin
    if (Depth>128) or (A.Count<>B.Count) then raise EArtFormat.Create('Edited PSD requires preservation-aware rebuild');
    for J := 0 to A.Count-1 do begin
      L := A[J]; R := B[J];
      if (L=nil) or (L.Name<>R.Name) or (L.Kind<>R.Kind) or
        not CompareMem(@L.Bounds,@R.Bounds,SizeOf(TArtBounds)) or
        (L.Visible<>R.Visible) or (L.Opacity<>R.Opacity) or
        (L.BlendKey<>R.BlendKey) or (L.Clipping<>R.Clipping) or
        (L.SectionType<>R.SectionType) or (L.SourceIndex<>R.SourceIndex) or
        not SameLayerMask(L,R) or not SameBytes(L.Pixels,R.Pixels) then
        raise EArtFormat.Create('Edited PSD requires preservation-aware rebuild');
      CompareLayers(L.Children,R.Children,Depth+1);
    end;
  end;
begin
  if Length(Document.SourceBytes)=0 then raise EArtFormat.Create('No source archive');
  Destination := TPath.GetFullPath(FileName);
  CreateGUID(G); TempName := Destination+'.'+GUIDToString(G)+'.tmp';
  try
    TFile.WriteAllBytes(TempName,Document.SourceBytes);
    Original := ReadPsd(TempName);
    try
      if (Document.Width<>Original.Width) or (Document.Height<>Original.Height) or
        (Document.SourceRecordCount<>Original.SourceRecordCount) or
        (Document.MergedHasTransparency<>Original.MergedHasTransparency) or
        (Length(Document.MergedPlanes)<>Length(Original.MergedPlanes)) or
        (Document.Unsupported.Text<>Original.Unsupported.Text) then
        raise EArtFormat.Create('Edited PSD requires preservation-aware rebuild');
      CompareLayers(Document.Roots,Original.Roots,0);
      for I := 0 to High(Document.MergedPlanes) do
        if not SameBytes(Document.MergedPlanes[I],Original.MergedPlanes[I]) then
          raise EArtFormat.Create('Edited merged image cannot be archived unchanged');
    finally Original.Free; end;
    if not MoveFileEx(PChar(TempName),PChar(Destination),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
    TempName := '';
  finally
    if (TempName<>'') and TFile.Exists(TempName) then TFile.Delete(TempName);
  end;
end;

type
  TArchiveRecord = record
    Header, Extra: TBytes;
    Flags: Byte;
    Channels: TChannels;
    Layer: TArtLayer;
  end;
  TArchiveRecords = TArray<TArchiveRecord>;

procedure SplitArchive(const Data: TBytes; out Prefix, Tail, ChannelData, Merged: TBytes;
  out Records: TArchiveRecords; Parsed: TArtDocument);
var R,B,Info,E: TReader; V: Cardinal; I,Start,N: Integer;
begin
  R := TReader.Create(Data,0,Length(Data));
  try
    R.Skip(26); V := R.U32; R.Skip(V); V := R.U32; R.Skip(V);
    Prefix := Copy(Data,0,R.Position);
    V := R.U32; B := R.Block(V);
    try
      V := B.U32; Info := B.Block(V);
      try
        N := Abs(Info.I16); SetLength(Records,N);
        for I := 0 to N-1 do begin
          Start := Info.Position;
          Records[I].Layer := ReadLayer(Info,Parsed,I,Records[I].Channels);
          E := TReader.Create(Data,Start,Info.Position);
          try
            E.Skip(18+Length(Records[I].Channels)*6+10);
            Records[I].Flags := E.U8; E.Skip(1);
            Records[I].Header := Copy(Data,Start,E.Position-Start);
            V := E.U32; Records[I].Extra := E.Bytes(V);
          finally E.Free; end;
        end;
        ChannelData := Info.Bytes(Info.Limit-Info.Position);
      finally Info.Free; end;
      Tail := B.Bytes(B.Limit-B.Position);
    finally B.Free; end;
    Merged := R.Bytes(R.Limit-R.Position);
  finally R.Free; end;
end;

function UpdatedExtra(const Original: TBytes; const Name: string; Changed: Boolean): TBytes;
var R: TReader; W: TWriter; V: Cardinal; Start,N: Integer; Key: AnsiString;
    Found: Boolean;
begin
  if not Changed then Exit(Copy(Original));
  R := TReader.Create(Original,0,Length(Original)); W := TWriter.Create;
  try
    V := R.U32; R.Skip(V); V := R.U32; R.Skip(V);
    // Update the fallback name too; Unicode is the authoritative full name.
    Start := R.Position; N := R.U8; R.Skip(N); R.Skip((4-(N+1) mod 4) mod 4);
    W.Bytes(Copy(Original,0,Start));
    W.U32(0); // Empty, four-byte-aligned legacy Pascal name.
    Found := False;
    while R.Limit-R.Position >= 12 do begin
      Start := R.Position; R.FourCC; Key := R.FourCC; V := R.U32; R.Skip(V);
      if Key = 'luni' then begin
        if Found then raise EArtFormat.Create('Duplicate Unicode name tag');
        WriteUnicodeTag(W,Name); Found := True;
      end else W.Bytes(Copy(Original,Start,R.Position-Start));
    end;
    if not Found then WriteUnicodeTag(W,Name);
    W.Bytes(R.Bytes(R.Limit-R.Position));
    SetLength(Result,W.Size);
    if W.Size>0 then Move(W.Memory^,Result[0],W.Size);
  finally R.Free; W.Free; end;
end;

procedure SaveImageCompositionPsd(Document: TArtDocument; const FileName: string);
var Old,Editable,ParsedOld,ParsedNew,Checked: TArtDocument;
    OriginalRecords,GeneratedRecords: TArchiveRecords;
    Prefix,Tail,Channels,Merged,NP,NT,NC,NM,Extra,Generated,Header: TBytes;
    OldData,NewData: TArray<TBytes>; Layers: TList<TArtLayer>; Dividers: TList<Boolean>;
    DividerMap: TDictionary<Integer,Integer>; Stack: TList<Integer>; Seen: TDictionary<Integer,Boolean>;
    Info,LayerMask,Output,Data: TWriter;
    I,Index,Offset: Integer; MaxId: Cardinal; L: TArtLayer;
    SourceTemp,GeneratedTemp,TempName,Destination: string; G: TGUID;
  procedure CopyTree(List: TList<TArtLayer>; Parent: TArtLayer; Depth: Integer);
  var L,N: TArtLayer;
  begin
    if Depth>128 then raise EArtFormat.Create('Hierarchy too deep');
    for L in List do begin
      N := Editable.AddLayer(L.Kind,L.Name,L.Bounds,Parent);
      N.Visible := L.Visible; N.Opacity := L.Opacity; N.BlendKey := L.BlendKey; N.Clipping := L.Clipping; N.SectionType := L.SectionType;
      N.Pixels := L.Pixels; N.HasMask := L.HasMask; N.MaskBounds := L.MaskBounds; N.MaskDefault := L.MaskDefault;
      N.MaskDisabled := L.MaskDisabled; N.MaskInvert := L.MaskInvert; N.MaskPixels := L.MaskPixels;
      CopyTree(L.Children,N,Depth+1);
    end;
  end;
  procedure Flatten(List: TList<TArtLayer>);
  var I: Integer; L: TArtLayer;
  begin
    for I := List.Count-1 downto 0 do begin
      L := List[I];
      if L.Kind=alkGroup then begin Layers.Add(L); Dividers.Add(True); Flatten(L.Children); end;
      Layers.Add(L); Dividers.Add(False);
    end;
  end;
  function ChannelSlices(const Records: TArchiveRecords; const Bytes: TBytes): TArray<TBytes>;
  var I,J,Offset,Size: Integer;
  begin
    SetLength(Result,Length(Records)); Offset := 0;
    for I := 0 to High(Records) do begin
      Size := 0;
      for J := 0 to High(Records[I].Channels) do Inc(Size,Records[I].Channels[J].Size);
      if Size>Length(Bytes)-Offset then raise EArtFormat.Create('Channel slices exceed archive');
      Result[I] := Copy(Bytes,Offset,Size); Inc(Offset,Size);
    end;
  end;
  function SetNewId(const Extra: TBytes): TBytes;
  var R: TReader; Start,V: Integer; Key: AnsiString; W: TWriter;
  begin
    R := TReader.Create(Extra,0,Length(Extra)); W := TWriter.Create;
    try
      V := R.U32; R.Skip(V); V := R.U32; R.Skip(V); V := R.U8; R.Skip(V); R.Skip((4-(V+1) mod 4) mod 4);
      W.Bytes(Copy(Extra,0,R.Position));
      while R.Limit-R.Position>=12 do begin
        Start := R.Position; R.FourCC; Key := R.FourCC; V := R.U32;
        if (Key='lyid') and (V=4) then begin
          R.Skip(4); if MaxId=High(Cardinal) then raise EArtFormat.Create('No free layer ID'); Inc(MaxId); W.FourCC('8BIM'); W.FourCC('lyid'); W.U32(4); W.U32(MaxId);
        end else begin R.Skip(V); W.Bytes(Copy(Extra,Start,R.Position-Start)); end;
      end;
      W.Bytes(R.Bytes(R.Limit-R.Position)); SetLength(Result,W.Size); Move(W.Memory^,Result[0],W.Size);
    finally R.Free; W.Free; end;
  end;
  procedure Verify(List,Other: TList<TArtLayer>);
  var I: Integer; A,B: TArtLayer;
  begin
    if List.Count<>Other.Count then raise EArtFormat.Create('Composition hierarchy verification failed');
    for I := 0 to List.Count-1 do begin
      A := List[I]; B := Other[I];
      if (A.Name<>B.Name) or (A.Kind<>B.Kind) or (A.Visible<>B.Visible) or (A.Opacity<>B.Opacity) or
         (A.BlendKey<>B.BlendKey) or not CompareMem(@A.Bounds,@B.Bounds,SizeOf(TArtBounds)) or
         not SameLayerMask(A,B) or (Length(A.Pixels)<>Length(B.Pixels)) then raise EArtFormat.Create('Composition layer verification failed');
      if (Length(A.Pixels)>0) and not CompareMem(@A.Pixels[0],@B.Pixels[0],Length(A.Pixels)) then raise EArtFormat.Create('Composition pixels verification failed');
      Verify(A.Children,B.Children);
    end;
  end;
begin
  if Length(Document.SourceBytes)=0 then begin WriteNewPsd(Document,FileName,pcRle); Exit; end;
  RenderPsdLayers(Document); // Reject unsupported rendering without discarding source data.
  Destination := TPath.GetFullPath(FileName); CreateGUID(G);
  TempName := Destination+'.'+GUIDToString(G)+'.tmp'; SourceTemp := TempName+'.source'; GeneratedTemp := TempName+'.generated';
  Old := nil; Editable := nil; ParsedOld := nil; ParsedNew := nil;
  Layers := TList<TArtLayer>.Create; Dividers := TList<Boolean>.Create; Stack := TList<Integer>.Create;
  DividerMap := TDictionary<Integer,Integer>.Create; Seen := TDictionary<Integer,Boolean>.Create;
  Info := TWriter.Create; LayerMask := TWriter.Create; Output := TWriter.Create; Data := TWriter.Create;
  try
    TFile.WriteAllBytes(SourceTemp,Document.SourceBytes); Old := ReadPsd(SourceTemp);
    RenderPsdLayers(Old);
    if (Old.Unsupported.Text<>Document.Unsupported.Text) or (Old.SourceRecordCount<>Document.SourceRecordCount) then raise EArtFormat.Create('Source metadata changed');
    if (Old.Width<>Document.Width) or (Old.Height<>Document.Height) then raise EArtFormat.Create('Canvas change is not supported in imported composition');
    ParsedOld := TArtDocument.Create;
    SplitArchive(Document.SourceBytes,Prefix,Tail,Channels,Merged,OriginalRecords,ParsedOld);
    OldData := ChannelSlices(OriginalRecords,Channels); MaxId := 0;
    for I := 0 to High(OriginalRecords) do begin
      if OriginalRecords[I].Layer.Kind=alkDivider then Stack.Add(I)
      else if OriginalRecords[I].Layer.Kind=alkGroup then begin
        if Stack.Count=0 then raise EArtFormat.Create('Missing original group divider');
        DividerMap.Add(I,Stack.Last); Stack.Delete(Stack.Count-1);
      end;
      // Allocate new numeric layer IDs beyond all source IDs.
      var R := TReader.Create(OriginalRecords[I].Extra,0,Length(OriginalRecords[I].Extra));
      try
        var V := R.U32; R.Skip(V); V := R.U32; R.Skip(V); V := R.U8; R.Skip(V); R.Skip((4-(V+1) mod 4) mod 4);
        while R.Limit-R.Position>=12 do begin
          R.FourCC; var Key := R.FourCC; V := R.U32;
          if (Key='lyid') and (V=4) then begin var Id := R.U32; if Id>MaxId then MaxId := Id; end else R.Skip(V);
        end;
      finally R.Free; end;
    end;
    Editable := TArtDocument.Create; Editable.Width := Document.Width; Editable.Height := Document.Height;
    CopyTree(Document.Roots,nil,0); WriteNewPsd(Editable,GeneratedTemp,pcRle);
    Generated := TFile.ReadAllBytes(GeneratedTemp); ParsedNew := TArtDocument.Create;
    SplitArchive(Generated,NP,NT,NC,NM,GeneratedRecords,ParsedNew); NewData := ChannelSlices(GeneratedRecords,NC);
    Flatten(Document.Roots);
    if Layers.Count<>Length(GeneratedRecords) then raise EArtFormat.Create('Flattened record mismatch');
    Info.U16(Word(65536-Layers.Count));
    for I := 0 to Layers.Count-1 do begin
      L := Layers[I]; Index := L.SourceIndex;
      if Index>=0 then begin
        if (Index>=Length(OriginalRecords)) or (OriginalRecords[Index].Layer.Kind<>L.Kind) or
           (OriginalRecords[Index].Layer.BlendKey<>L.BlendKey) or (OriginalRecords[Index].Layer.Clipping<>L.Clipping) then
          raise EArtFormat.Create('Original layer identity changed');
        if Dividers[I] then Index := DividerMap[L.SourceIndex];
        if Seen.ContainsKey(Index) then raise EArtFormat.Create('Repeated source record'); Seen.Add(Index,True);
        Header := Copy(GeneratedRecords[I].Header);
        Extra := UpdatedExtra(OriginalRecords[Index].Extra,L.Name,not Dividers[I] and (L.Name<>OriginalRecords[Index].Layer.Name));
        if L.HasMask and not Dividers[I] then begin
          var R := TReader.Create(Extra,0,Length(Extra));
          try var V := R.U32; R.Skip(V); Extra := R.Bytes(R.Limit-R.Position); finally R.Free; end;
          R := TReader.Create(GeneratedRecords[I].Extra,0,Length(GeneratedRecords[I].Extra));
          try var V := R.U32; R.Skip(V); Extra := Copy(GeneratedRecords[I].Extra,0,R.Position)+Extra; finally R.Free; end;
        end;
        // Preserve group channel payloads, which the renderer does not replace.
        if L.Kind=alkGroup then begin Header := Copy(OriginalRecords[Index].Header); Data.Bytes(OldData[Index]); end
        else Data.Bytes(NewData[I]);
        Offset := Length(Header)-4;
        if not Dividers[I] then Header[Offset] := L.Opacity;
        Header[Offset+2] := OriginalRecords[Index].Flags and $FD;
        if Dividers[I] or not L.Visible then Header[Offset+2] := Header[Offset+2] or 2;
      end else begin
        if L.Kind<>alkImage then raise EArtFormat.Create('Only image insertion supported');
        Header := GeneratedRecords[I].Header; Extra := SetNewId(GeneratedRecords[I].Extra); Data.Bytes(NewData[I]);
      end;
      Info.Bytes(Header); Info.U32(Length(Extra)); Info.Bytes(Extra);
    end;
    if Seen.Count<>Length(OriginalRecords) then raise EArtFormat.Create('Removing imported layers is not supported');
    Info.CopyFrom(Data,0); Info.Pad(2,0);
    LayerMask.Block(Info); LayerMask.Bytes(Tail);
    Prefix[12] := 0; Prefix[13] := 4;
    Output.Bytes(Prefix); Output.Block(LayerMask); Output.Bytes(NM); Output.SaveToFile(TempName);
    ParsedNew.Free; ParsedNew := ReadPsd(GeneratedTemp);
    Checked := ReadPsd(TempName);
    try Verify(Document.Roots,Checked.Roots);
      for I := 0 to High(Checked.MergedPlanes) do
        if (Length(Checked.MergedPlanes[I])<>Length(ParsedNew.MergedPlanes[I])) or
           not CompareMem(@Checked.MergedPlanes[I][0],@ParsedNew.MergedPlanes[I][0],Length(Checked.MergedPlanes[I])) then raise EArtFormat.Create('Composite mismatch');
    finally Checked.Free; end;
    if not MoveFileEx(PChar(TempName),PChar(Destination),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
    TempName := '';
  finally
    if (TempName<>'') and TFile.Exists(TempName) then TFile.Delete(TempName);
    if TFile.Exists(SourceTemp) then TFile.Delete(SourceTemp); if TFile.Exists(GeneratedTemp) then TFile.Delete(GeneratedTemp);
    Data.Free; Output.Free; LayerMask.Free; Info.Free; Seen.Free; DividerMap.Free; Stack.Free; Dividers.Free; Layers.Free;
    ParsedNew.Free; ParsedOld.Free; Editable.Free; Old.Free;
  end;
end;

procedure SaveLayerPropertiesPsd(Document: TArtDocument; const FileName: string);
var Original,Parsed,Checked: TArtDocument; Map: TDictionary<Integer,TArtLayer>;
    Records: TArchiveRecords; Prefix,Tail,Channels,Merged,RGBA,Extra: TBytes;
    Info,LayerMask,Output: TWriter; Planes: TArray<TBytes>;
    I,C,Y,P,A,Offset: Integer; L: TArtLayer; Destination,TempName,SourceTemp: string; G: TGUID;
  function SameBytes(const A,B: TBytes): Boolean;
  begin
    Result := Length(A)=Length(B);
    if Result and (Length(A)>0) then Result := CompareMem(@A[0],@B[0],Length(A));
  end;
  procedure CheckTree(List,Old: TList<TArtLayer>; Verify: Boolean; Depth: Integer);
  var J: Integer; N,O: TArtLayer;
  begin
    if (Depth>128) or (List.Count<>Old.Count) then raise EArtFormat.Create('Properties save requires original hierarchy');
    for J := 0 to List.Count-1 do begin
      N := List[J]; O := Old[J];
      if (N.Kind<>O.Kind) or (N.SourceIndex<>O.SourceIndex) or (N.BlendKey<>O.BlendKey) or
         (N.Clipping<>O.Clipping) or (N.SectionType<>O.SectionType) or
         not CompareMem(@N.Bounds,@O.Bounds,SizeOf(TArtBounds)) or
         not SameLayerMask(N,O) or not SameBytes(N.Pixels,O.Pixels) then
        raise EArtFormat.Create('Properties save cannot change pixels or structural data');
      if Verify then begin
        if (N.Name<>O.Name) or (N.Visible<>O.Visible) or (N.Opacity<>O.Opacity) then
          raise EArtFormat.Create('Properties save verification failed');
      end else begin
        if Map.ContainsKey(N.SourceIndex) then raise EArtFormat.Create('Repeated source layer');
        Map.Add(N.SourceIndex,N);
      end;
      CheckTree(N.Children,O.Children,Verify,Depth+1);
    end;
  end;
begin
  if Length(Document.SourceBytes)=0 then raise EArtFormat.Create('No original PSD archive');
  RGBA := RenderPsdLayers(Document);
  if (Length(Document.MergedPlanes)<3) or (Length(Document.MergedPlanes)>4) or
     ((Length(Document.MergedPlanes)=4) and not Document.MergedHasTransparency) then
    raise EArtFormat.Create('Properties save requires RGB or RGB/transparency composite');
  Destination := TPath.GetFullPath(FileName); CreateGUID(G);
  TempName := Destination+'.'+GUIDToString(G)+'.tmp'; SourceTemp := TempName+'.source';
  Original := nil; Parsed := nil; Map := TDictionary<Integer,TArtLayer>.Create;
  Info := TWriter.Create; LayerMask := TWriter.Create; Output := TWriter.Create;
  try
    TFile.WriteAllBytes(SourceTemp,Document.SourceBytes); Original := ReadPsd(SourceTemp);
    if (Document.Width<>Original.Width) or (Document.Height<>Original.Height) or
       (Document.SourceRecordCount<>Original.SourceRecordCount) or
       (Document.Unsupported.Text<>Original.Unsupported.Text) or
       (Document.MergedHasTransparency<>Original.MergedHasTransparency) or
       (Length(Document.MergedPlanes)<>Length(Original.MergedPlanes)) then
      raise EArtFormat.Create('Properties save cannot change source metadata');
    for I := 0 to High(Document.MergedPlanes) do
      if not SameBytes(Document.MergedPlanes[I],Original.MergedPlanes[I]) then
        raise EArtFormat.Create('Properties save cannot change original merged planes');
    CheckTree(Document.Roots,Original.Roots,False,0);
    Parsed := TArtDocument.Create;
    SplitArchive(Document.SourceBytes,Prefix,Tail,Channels,Merged,Records,Parsed);
    if Document.MergedHasTransparency then Info.U16(Word(65536-Length(Records))) else Info.U16(Length(Records));
    for I := 0 to High(Records) do begin
      if Map.TryGetValue(I,L) then begin
        Offset := Length(Records[I].Header)-4;
        Records[I].Header[Offset] := L.Opacity;
        Records[I].Header[Offset+2] := Records[I].Header[Offset+2] and $FD;
        if not L.Visible then Records[I].Header[Offset+2] := Records[I].Header[Offset+2] or 2;
        Extra := UpdatedExtra(Records[I].Extra,L.Name,L.Name<>Records[I].Layer.Name);
      end else Extra := Records[I].Extra;
      Info.Bytes(Records[I].Header); Info.U32(Length(Extra)); Info.Bytes(Extra);
    end;
    Info.Bytes(Channels); Info.Pad(2,0); LayerMask.Block(Info); LayerMask.Bytes(Tail);
    Output.Bytes(Prefix); Output.Block(LayerMask);
    for P := 0 to Length(RGBA) div 4-1 do begin
      A := RGBA[P*4+3];
      for C := 0 to 2 do RGBA[P*4+C] := (RGBA[P*4+C]*A+255*(255-A)+127) div 255;
    end;
    SetLength(Planes,Length(Document.MergedPlanes));
    for C := 0 to High(Planes) do Planes[C] := EncodePlane(RGBA,Document.Width,Document.Height,C,pcRle);
    Output.U16(1);
    for C := 0 to High(Planes) do
      for Y := 0 to Document.Height-1 do begin Output.U8(Planes[C][2+Y*2]); Output.U8(Planes[C][3+Y*2]); end;
    for C := 0 to High(Planes) do begin
      Offset := 2+Document.Height*2;
      if Length(Planes[C])>Offset then Output.WriteBuffer(Planes[C][Offset],Length(Planes[C])-Offset);
    end;
    Output.SaveToFile(TempName); Checked := ReadPsd(TempName);
    try
      CheckTree(Document.Roots,Checked.Roots,True,0);
      if (Checked.Width<>Document.Width) or (Checked.Height<>Document.Height) or
         (Checked.Unsupported.Text<>Original.Unsupported.Text) then raise EArtFormat.Create('Source metadata preservation failed');
      for C := 0 to High(Planes) do
        for P := 0 to Document.Width*Document.Height-1 do
          if Checked.MergedPlanes[C][P]<>RGBA[P*4+C] then raise EArtFormat.Create('Composite verification failed');
    finally Checked.Free; end;
    if not MoveFileEx(PChar(TempName),PChar(Destination),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
    TempName := '';
  finally
    if (TempName<>'') and TFile.Exists(TempName) then TFile.Delete(TempName);
    if TFile.Exists(SourceTemp) then TFile.Delete(SourceTemp);
    Output.Free; LayerMask.Free; Info.Free; Map.Free; Parsed.Free; Original.Free;
  end;
end;

procedure CheckEditableExtra(const Data: TBytes);
var R,B: TReader; V,N: Cardinal; K: AnsiString; Seen: TList<AnsiString>; I: Integer;
begin
  R := TReader.Create(Data,0,Length(Data)); Seen := TList<AnsiString>.Create;
  try
    V := R.U32; if (V<>0) and (V<>20) then raise EArtFormat.Create('Extended mask blocks edited save'); R.Skip(V);
    V := R.U32; if V<>0 then raise EArtFormat.Create('Blending ranges block edited save');
    I := R.U8; R.Skip(I); R.Skip((4-(I+1) mod 4) mod 4);
    while R.Limit-R.Position>=12 do begin
      if R.FourCC<>'8BIM' then raise EArtFormat.Create('Nonstandard tag signature blocks edited save');
      K := R.FourCC; V := R.U32; B := R.Block(V);
      try
        if Seen.Contains(K) then raise EArtFormat.Create('Duplicate additional tag blocks edited save');
        Seen.Add(K);
        if K='luni' then begin
          N := B.U32;
          if UInt64(N)*2+4<>V then raise EArtFormat.Create('Extended Unicode tag blocks edited save');
        end else if (K='lyid') or (K='lsct') or (K='lsdk') then begin
          if V<>4 then raise EArtFormat.Create('Extended layer metadata blocks edited save');
        end else raise EArtFormat.Create('Unknown tag blocks edited save: '+string(K));
      finally B.Free; end;
    end;
    R.CheckZeroTail;
  finally R.Free; Seen.Free; end;
end;

procedure SaveEditedPsd(Document: TArtDocument; const FileName: string;
  Compression: TPsdCompression);
var Original, Editable, ParsedOld, ParsedNew, Checked: TArtDocument;
    OldRecords, NewRecords: TArchiveRecords;
    Prefix, Tail, Channels, Merged, Generated: TBytes;
    NewPrefix, NewTail, NewChannels, NewMerged, Extra: TBytes;
    Info, LayerMask, Output: TWriter;
    SourceTemp, GeneratedTemp, TempName, Destination: string; G: TGUID;
    Map: TDictionary<Integer,TArtLayer>; I,J,FlagIndex: Integer; R,B: TReader; V: Cardinal;
  function SameBytes(const A,C: TBytes): Boolean;
  begin
    Result := Length(A)=Length(C);
    if Result and (Length(A)>0) then Result := CompareMem(@A[0],@C[0],Length(A));
  end;
  procedure CopyTree(A,C: TList<TArtLayer>; Parent: TArtLayer; Depth: Integer);
  var K: Integer; L,O,N: TArtLayer;
  begin
    if (Depth>128) or (A.Count<>C.Count) then raise EArtFormat.Create('Layer structure changes not supported');
    for K := 0 to A.Count-1 do begin
      L := A[K]; O := C[K];
      if (L=nil) or (L.Kind<>O.Kind) or (L.SourceIndex<>O.SourceIndex) or
        Map.ContainsKey(L.SourceIndex) or (L.BlendKey<>O.BlendKey) or
        (L.Clipping<>O.Clipping) or (L.SectionType<>O.SectionType) then
        raise EArtFormat.Create('Layer structure or unsupported attribute changed');
      if (L.Kind=alkGroup) and not CompareMem(@L.Bounds,@O.Bounds,SizeOf(TArtBounds)) then
        raise EArtFormat.Create('Group bounds changes not supported');
      Map.Add(L.SourceIndex,L);
      N := Editable.AddLayer(L.Kind,L.Name,L.Bounds,Parent);
      if L.HasMask<>O.HasMask then raise EArtFormat.Create('Adding/removing imported masks not yet supported');
      N.HasMask := L.HasMask; N.MaskBounds := L.MaskBounds; N.MaskDefault := L.MaskDefault;
      N.MaskDisabled := L.MaskDisabled; N.MaskInvert := L.MaskInvert; N.MaskPixels := Copy(L.MaskPixels);
      N.Pixels := Copy(L.Pixels); N.Visible := L.Visible; N.Opacity := L.Opacity;
      N.BlendKey := L.BlendKey; N.Clipping := L.Clipping; N.SectionType := L.SectionType;
      CopyTree(L.Children,O.Children,N,Depth+1);
    end;
  end;
  procedure VerifyTree(A,C: TList<TArtLayer>);
  var K: Integer; L,O: TArtLayer;
  begin
    if A.Count<>C.Count then raise EArtFormat.Create('Saved hierarchy mismatch');
    for K := 0 to A.Count-1 do begin
      L := A[K]; O := C[K];
      if (L.Name<>O.Name) or (L.Kind<>O.Kind) or (L.Visible<>O.Visible) or
        (L.Opacity<>O.Opacity) or not CompareMem(@L.Bounds,@O.Bounds,SizeOf(TArtBounds)) or
        not SameLayerMask(L,O) or not SameBytes(L.Pixels,O.Pixels) then raise EArtFormat.Create('Saved layer mismatch');
      VerifyTree(L.Children,O.Children);
    end;
  end;
begin
  if Length(Document.SourceBytes)=0 then raise EArtFormat.Create('No source archive');
  Destination := TPath.GetFullPath(FileName); CreateGUID(G);
  TempName := Destination+'.'+GUIDToString(G)+'.tmp';
  SourceTemp := TempName+'.source'; GeneratedTemp := TempName+'.generated';
  Original := nil; Editable := nil; ParsedOld := nil; ParsedNew := nil;
  Map := TDictionary<Integer,TArtLayer>.Create;
  Info := TWriter.Create; LayerMask := TWriter.Create; Output := TWriter.Create;
  try
    TFile.WriteAllBytes(SourceTemp,Document.SourceBytes); Original := ReadPsd(SourceTemp);
    for I := 0 to Original.Unsupported.Count-1 do
      if Original.Unsupported[I]<>'Image resources retained in source archive' then
        raise EArtFormat.Create('Edited save blocked: '+Original.Unsupported[I]);
    if (Document.Width<>Original.Width) or (Document.Height<>Original.Height) or
      (Document.SourceRecordCount<>Original.SourceRecordCount) or
      (Document.MergedHasTransparency<>Original.MergedHasTransparency) or
      (Document.Unsupported.Text<>Original.Unsupported.Text) or
      (Length(Document.MergedPlanes)<>Length(Original.MergedPlanes)) then
      raise EArtFormat.Create('Canvas or source-derived metadata changed');
    for I := 0 to High(Document.MergedPlanes) do
      if not SameBytes(Document.MergedPlanes[I],Original.MergedPlanes[I]) then
        raise EArtFormat.Create('Merged planes are derived data; edit layer pixels instead');
    // Only resolution metadata has verified independence from edited pixels/attributes.
    R := TReader.Create(Document.SourceBytes,26,Length(Document.SourceBytes));
    try
      V := R.U32; R.Skip(V); V := R.U32; B := R.Block(V);
      try
        while B.Position<B.Limit do begin
          if B.FourCC<>'8BIM' then raise EArtFormat.Create('Invalid resource signature');
          J := B.U16;
          I := B.U8; B.Skip(I); B.Skip((2-(I+1) mod 2) mod 2);
          V := B.U32;
          if (J<>1005) or (V<>16) then raise EArtFormat.CreateFmt('Resource %d blocks edited save',[J]);
          B.Skip(V); B.Skip(V mod 2);
        end;
      finally B.Free; end;
    finally R.Free; end;
    Editable := TArtDocument.Create; Editable.Width := Document.Width; Editable.Height := Document.Height;
    CopyTree(Document.Roots,Original.Roots,nil,0); Editable.ValidateForNewSave;
    ParsedOld := TArtDocument.Create;
    SplitArchive(Document.SourceBytes,Prefix,Tail,Channels,Merged,OldRecords,ParsedOld);
    if (Original.SourceRecordCount<1) or (Length(Original.MergedPlanes)<>4) or
      not Original.MergedHasTransparency then raise EArtFormat.Create('Edited save requires four merged channels with transparency');
    if Length(Tail)<4 then raise EArtFormat.Create('Missing global-mask length');
    for I := 0 to High(Tail) do
      if Tail[I]<>0 then raise EArtFormat.Create('Outer metadata blocks edited save');
    for I := 0 to High(OldRecords) do begin
      CheckEditableExtra(OldRecords[I].Extra);
      if OldRecords[I].Layer.Kind=alkImage then begin
        if Length(OldRecords[I].Channels)<>4+Ord(OldRecords[I].Layer.HasMask) then raise EArtFormat.Create('Unsupported image channel count');
        for J := 0 to High(OldRecords[I].Channels) do
          if ((J=4) and (OldRecords[I].Channels[J].Id<>-2)) or ((J<3) and (OldRecords[I].Channels[J].Id<>J)) or
            ((J=3) and (OldRecords[I].Channels[J].Id<>-1)) then
            raise EArtFormat.Create('Image channel order not yet supported for edited save');
        if (OldRecords[I].Flags and 16)<>0 then raise EArtFormat.Create('Pixel-irrelevant image record not editable');
      end else if Length(OldRecords[I].Channels)<>0 then
        raise EArtFormat.Create('Group channels not yet supported for edited save');
    end;
    WriteNewPsd(Editable,GeneratedTemp,Compression); Generated := TFile.ReadAllBytes(GeneratedTemp);
    ParsedNew := TArtDocument.Create;
    SplitArchive(Generated,NewPrefix,NewTail,NewChannels,NewMerged,NewRecords,ParsedNew);
    if Length(NewRecords)<>Length(OldRecords) then raise EArtFormat.Create('Record count changed');
    Info.U16(Word($10000-Length(NewRecords)));
    for I := 0 to High(NewRecords) do begin
      FlagIndex := Length(NewRecords[I].Header)-2;
      NewRecords[I].Header[FlagIndex] := (OldRecords[I].Flags and $FD) or
        (NewRecords[I].Header[FlagIndex] and 2);
      if Map.ContainsKey(I) then
        Extra := UpdatedExtra(OldRecords[I].Extra,Map[I].Name,Map[I].Name<>OldRecords[I].Layer.Name)
      else Extra := Copy(OldRecords[I].Extra);
      if Map.ContainsKey(I) and Map[I].HasMask then begin
        // Replace only the mask block; keep all remaining source extra tags.
        R := TReader.Create(Extra,0,Length(Extra));
        try V := R.U32; R.Skip(V); Extra := R.Bytes(R.Limit-R.Position); finally R.Free; end;
        B := TReader.Create(NewRecords[I].Extra,0,Length(NewRecords[I].Extra));
        try V := B.U32; B.Skip(V); Extra := Copy(NewRecords[I].Extra,0,B.Position)+Extra; finally B.Free; end;
      end;
      Info.Bytes(NewRecords[I].Header); Info.U32(Length(Extra)); Info.Bytes(Extra);
    end;
    Info.Bytes(NewChannels); Info.Pad(2,0);
    LayerMask.Block(Info); LayerMask.Bytes(Tail);
    Output.Bytes(Prefix); Output.Block(LayerMask); Output.Bytes(NewMerged);
    Output.SaveToFile(TempName); Checked := ReadPsd(TempName);
    try
      VerifyTree(Document.Roots,Checked.Roots);
      ParsedNew.Width := Document.Width; ParsedNew.Height := Document.Height;
      R := TReader.Create(Generated,0,Length(Generated));
      try
        R.Skip(26); V := R.U32; R.Skip(V); V := R.U32; R.Skip(V); V := R.U32; R.Skip(V);
        ReadMerged(R,ParsedNew,4);
      finally R.Free; end;
      if Length(Checked.MergedPlanes)<>4 then raise EArtFormat.Create('Saved merged channel count mismatch');
      for I := 0 to 3 do
        if not SameBytes(Checked.MergedPlanes[I],ParsedNew.MergedPlanes[I]) then
          raise EArtFormat.Create('Saved merged pixels mismatch');
    finally Checked.Free; end;
    if not MoveFileEx(PChar(TempName),PChar(Destination),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
    TempName := '';
  finally
    Original.Free; Editable.Free; ParsedOld.Free; ParsedNew.Free; Map.Free;
    Info.Free; LayerMask.Free; Output.Free;
    if (TempName<>'') and TFile.Exists(TempName) then TFile.Delete(TempName);
    if TFile.Exists(SourceTemp) then TFile.Delete(SourceTemp);
    if TFile.Exists(GeneratedTemp) then TFile.Delete(GeneratedTemp);
  end;
end;

end.

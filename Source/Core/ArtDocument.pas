unit ArtDocument;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  EArtFormat = class(Exception);
  TArtLayerKind = (alkImage, alkGroup, alkDivider);
  TArtBounds = record
    Left, Top, Right, Bottom: Integer;
    class function Create(ALeft, ATop, ARight, ABottom: Integer): TArtBounds; static;
    function Width: Integer;
    function Height: Integer;
  end;
  TArtLayer = class
  public
    Id, Name: string;
    Kind: TArtLayerKind;
    Bounds: TArtBounds;
    HasMask, MaskDisabled, MaskInvert: Boolean;
    MaskBounds: TArtBounds; // Absolute canvas coordinates; separate from image bounds.
    MaskDefault: Byte;
    MaskPixels: TBytes; // Top-down single-channel coverage.
    Pixels: TBytes; // Top-down, straight-alpha RGBA8. Never VCL pixel storage.
    Children: TList<TArtLayer>; // Non-owning, topmost first.
    Visible: Boolean;
    Opacity: Byte;
    BlendKey: AnsiString;
    Clipping: Byte;
    SectionType: Cardinal;
    SourceIndex: Integer;
    constructor Create;
    destructor Destroy; override;
  end;
  TArtDocument = class
  private
    FOwnedLayers: TObjectList<TArtLayer>;
  public
    SessionId: string;
    Revision: UInt64;
    Width, Height: Integer;
    Roots: TList<TArtLayer>; // Non-owning, topmost first.
    SourceBytes: TBytes; // Owned archive; independent of original file lifetime.
    MergedPlanes: TArray<TBytes>;
    MergedHasTransparency: Boolean;
    SourceRecordCount: Integer;
    Unsupported: TStringList;
    constructor Create;
    destructor Destroy; override;
    function AddLayer(AKind: TArtLayerKind; const AName: string;
      const ABounds: TArtBounds; Parent: TArtLayer = nil): TArtLayer;
    function NewUnattachedLayer: TArtLayer;
    procedure RemoveNewLayer(Layer: TArtLayer);
    function Clone: TArtDocument;
    function FindLayer(const LayerId: string): TArtLayer;
    procedure Changed;
    procedure ValidateForNewSave;
    function RenderRGBA: TBytes;
  end;

const
  ART_MAX_PIXELS = 16000000; // Initial allocation limit, not PSD format limit.
  ART_MAX_BYTES = 536870912;

function PixelByteCount(Width, Height, Channels: Integer): Integer;

implementation

uses System.Math;

function PixelByteCount(Width, Height, Channels: Integer): Integer;
var N: Int64;
begin
  if (Width < 0) or (Height < 0) or (Channels < 1) then
    raise EArtFormat.Create('Negative image dimensions');
  N := Int64(Width) * Height;
  if (N > ART_MAX_PIXELS) or (N * Channels > ART_MAX_BYTES) then
    raise EArtFormat.Create('Image allocation limit exceeded');
  Result := Integer(N * Channels);
end;

class function TArtBounds.Create(ALeft, ATop, ARight, ABottom: Integer): TArtBounds;
begin
  Result.Left := ALeft; Result.Top := ATop;
  Result.Right := ARight; Result.Bottom := ABottom;
end;

function TArtBounds.Width: Integer;
var N: Int64;
begin
  N := Int64(Right) - Left;
  if (N < 0) or (N > High(Integer)) then raise EArtFormat.Create('Invalid layer width');
  Result := Integer(N);
end;

function TArtBounds.Height: Integer;
var N: Int64;
begin
  N := Int64(Bottom) - Top;
  if (N < 0) or (N > High(Integer)) then raise EArtFormat.Create('Invalid layer height');
  Result := Integer(N);
end;

constructor TArtLayer.Create;
var G: TGUID;
begin
  inherited;
  CreateGUID(G); Id := GUIDToString(G);
  Children := TList<TArtLayer>.Create;
  Visible := True; Opacity := 255; BlendKey := 'norm'; SourceIndex := -1;
end;

destructor TArtLayer.Destroy;
begin
  Children.Free;
  inherited;
end;

constructor TArtDocument.Create;
var G: TGUID;
begin
  inherited;
  CreateGUID(G); SessionId := GUIDToString(G); Revision := 0;
  FOwnedLayers := TObjectList<TArtLayer>.Create(True);
  Roots := TList<TArtLayer>.Create;
  Unsupported := TStringList.Create;
end;

destructor TArtDocument.Destroy;
begin
  Unsupported.Free; Roots.Free; FOwnedLayers.Free;
  inherited;
end;

function TArtDocument.NewUnattachedLayer: TArtLayer;
begin
  Result := TArtLayer.Create;
  FOwnedLayers.Add(Result);
end;

function TArtDocument.AddLayer(AKind: TArtLayerKind; const AName: string;
  const ABounds: TArtBounds; Parent: TArtLayer): TArtLayer;
begin
  if Assigned(Parent) and ((Parent.Kind <> alkGroup) or not FOwnedLayers.Contains(Parent)) then
    raise EArtFormat.Create('Invalid parent');
  Result := NewUnattachedLayer;
  Result.Kind := AKind; Result.Name := AName; Result.Bounds := ABounds;
  if AKind = alkGroup then begin Result.BlendKey := 'pass'; Result.SectionType := 1; end;
  if Assigned(Parent) then Parent.Children.Add(Result) else Roots.Add(Result);
end;

procedure TArtDocument.RemoveNewLayer(Layer: TArtLayer);
  procedure Detach(List: TList<TArtLayer>);
  var L: TArtLayer;
  begin
    List.Remove(Layer);
    for L in List do Detach(L.Children);
  end;
begin
  if (Layer=nil) or (Layer.SourceIndex<>-1) or (Layer.Children.Count<>0) then raise EArtFormat.Create('Only new leaf rollback supported');
  Detach(Roots); FOwnedLayers.Remove(Layer);
end;

procedure TArtDocument.Changed;
begin
  if Revision=High(UInt64) then raise EArtFormat.Create('Document revision exhausted');
  Inc(Revision);
end;
function TArtDocument.FindLayer(const LayerId: string): TArtLayer;
var L: TArtLayer;
begin
  Result := nil;
  for L in FOwnedLayers do if L.Id=LayerId then Exit(L);
end;
function TArtDocument.Clone: TArtDocument;
  procedure CopyTree(List: TList<TArtLayer>; Parent: TArtLayer);
  var L,N: TArtLayer;
  begin
    for L in List do begin
      N := Result.AddLayer(L.Kind,L.Name,L.Bounds,Parent);
      N.Id := L.Id; N.Visible := L.Visible; N.Opacity := L.Opacity;
      N.BlendKey := L.BlendKey; N.Clipping := L.Clipping; N.SectionType := L.SectionType; N.SourceIndex := L.SourceIndex;
      // Pixel arrays are immutable assets: replacements assign a new array.
      N.Pixels := L.Pixels; N.HasMask := L.HasMask; N.MaskBounds := L.MaskBounds;
      N.MaskDefault := L.MaskDefault; N.MaskDisabled := L.MaskDisabled; N.MaskInvert := L.MaskInvert; N.MaskPixels := L.MaskPixels;
      CopyTree(L.Children,N);
    end;
  end;
begin
  Result := TArtDocument.Create;
  try
    Result.SessionId := SessionId; Result.Revision := Revision; Result.Width := Width; Result.Height := Height;
    Result.SourceBytes := SourceBytes; Result.SourceRecordCount := SourceRecordCount;
    Result.MergedPlanes := MergedPlanes; Result.MergedHasTransparency := MergedHasTransparency;
    Result.Unsupported.Assign(Unsupported); CopyTree(Roots,nil);
  except Result.Free; raise; end;
end;

procedure TArtDocument.ValidateForNewSave;
var Seen: TDictionary<TArtLayer, Boolean>; Records: Integer;
  procedure Visit(List: TList<TArtLayer>; Depth: Integer);
  var L: TArtLayer;
  begin
    if Depth > 128 then raise EArtFormat.Create('Group depth limit exceeded');
    for L in List do begin
      if (L = nil) or not FOwnedLayers.Contains(L) or Seen.ContainsKey(L) then
        raise EArtFormat.Create('Invalid, repeated or cyclic layer reference');
      Seen.Add(L, True);
      if L.Kind = alkDivider then raise EArtFormat.Create('Divider in editable tree');
      Inc(Records);
      if L.HasMask then begin
        if L.Kind<>alkImage then raise EArtFormat.Create('Group masks not yet implemented');
        if (L.MaskDefault<>0) and (L.MaskDefault<>255) then raise EArtFormat.Create('Invalid mask default');
        if Length(L.MaskPixels)<>PixelByteCount(L.MaskBounds.Width,L.MaskBounds.Height,1) then
          raise EArtFormat.Create('Mask pixel buffer size mismatch');
      end else if Length(L.MaskPixels)<>0 then raise EArtFormat.Create('Mask pixels without mask');
      if (L.Clipping <> 0) then raise EArtFormat.Create('Clipping rendering not implemented');
      if L.Kind = alkImage then begin
        if L.BlendKey <> 'norm' then raise EArtFormat.Create('Only normal image blending implemented');
        if L.Children.Count <> 0 then raise EArtFormat.Create('Image layer has children');
        if Length(L.Pixels) <> PixelByteCount(L.Bounds.Width, L.Bounds.Height, 4) then
          raise EArtFormat.Create('Layer pixel buffer size mismatch');
      end else begin
        if (L.BlendKey <> 'norm') and ((L.BlendKey <> 'pass') or (L.Opacity <> 255)) then
          raise EArtFormat.Create('Only normal or full-opacity pass-through groups implemented');
        Inc(Records); Visit(L.Children, Depth + 1);
      end;
      if Records > 32767 then raise EArtFormat.Create('Too many PSD layer records');
    end;
  end;
begin
  if (Width < 1) or (Height < 1) or (Width > 30000) or (Height > 30000) then
    raise EArtFormat.Create('Invalid PSD canvas');
  PixelByteCount(Width, Height, 4);
  if Length(SourceBytes) <> 0 then
    raise EArtFormat.Create('Re-encoding imported PSD is disabled until source-information preservation is implemented');
  if Unsupported.Count <> 0 then raise EArtFormat.Create('Unsupported source information');
  if Roots.Count = 0 then raise EArtFormat.Create('A new PSD requires at least one layer');
  Seen := TDictionary<TArtLayer, Boolean>.Create;
  try
    Records := 0; Visit(Roots, 0);
  finally Seen.Free; end;
end;

function TArtDocument.RenderRGBA: TBytes;
var Output: TBytes;
  procedure Draw(List: TList<TArtLayer>; var Target: TBytes; Depth: Integer);
  var I, X, Y, P, Q, C, MaskValue: Integer; L: TArtLayer;
      SX, SY, MX, MY: Int64; SA, DA, OA, Value: Double; Group: TBytes;
  begin
    for I := List.Count - 1 downto 0 do begin
      L := List[I];
      if not L.Visible then Continue;
      if L.Kind = alkGroup then begin
        if L.BlendKey='pass' then Draw(L.Children,Target,Depth+1)
        else begin
          if Int64(Depth+1)*Length(Target)>ART_MAX_BYTES then raise EArtFormat.Create('Group composite memory limit');
          SetLength(Group,Length(Target)); if Length(Group)>0 then FillChar(Group[0],Length(Group),0);
          Draw(L.Children,Group,Depth+1);
          for Q := 0 to Length(Target) div 4-1 do begin
            P := Q*4; SA := Group[P+3]/255.0*L.Opacity/255.0; DA := Target[P+3]/255.0;
            OA := SA+DA*(1-SA); if OA<=0 then Continue;
            for C := 0 to 2 do Target[P+C] := EnsureRange(Round((Group[P+C]*SA+Target[P+C]*DA*(1-SA))/OA),0,255);
            Target[P+3] := EnsureRange(Round(OA*255),0,255);
          end;
          Group := nil;
        end;
        Continue;
      end;
      for Y := 0 to L.Bounds.Height - 1 do begin
        SY := Int64(L.Bounds.Top) + Y;
        if (SY < 0) or (SY >= Height) then Continue;
        for X := 0 to L.Bounds.Width - 1 do begin
          SX := Int64(L.Bounds.Left) + X;
          if (SX < 0) or (SX >= Width) then Continue;
          P := (Y * L.Bounds.Width + X) * 4;
          Q := (Integer(SY) * Width + Integer(SX)) * 4;
          SA := (L.Pixels[P+3] / 255.0) * (L.Opacity / 255.0);
          if L.HasMask and not L.MaskDisabled then begin
            MX := SX-L.MaskBounds.Left; MY := SY-L.MaskBounds.Top;
            MaskValue := L.MaskDefault;
            if (MX>=0) and (MY>=0) and (MX<L.MaskBounds.Width) and (MY<L.MaskBounds.Height) then
              MaskValue := L.MaskPixels[Integer(MY)*L.MaskBounds.Width+Integer(MX)];
            if L.MaskInvert then MaskValue := 255-MaskValue;
            SA := SA*(MaskValue/255.0);
          end;
          DA := Target[Q+3] / 255.0;
          OA := SA + DA * (1 - SA);
          if OA <= 0 then Continue;
          for C := 0 to 2 do begin
            Value := (L.Pixels[P+C] * SA + Target[Q+C] * DA * (1-SA)) / OA;
            Target[Q+C] := Byte(EnsureRange(Round(Value), 0, 255));
          end;
          Target[Q+3] := Byte(EnsureRange(Round(OA * 255), 0, 255));
        end;
      end;
    end;
  end;
begin
  ValidateForNewSave;
  SetLength(Output, PixelByteCount(Width, Height, 4));
  Draw(Roots,Output,0);
  Result := Output;
end;

end.

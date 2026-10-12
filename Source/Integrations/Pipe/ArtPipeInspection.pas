unit ArtPipeInspection;

interface

uses System.JSON, ArtDocument;

// 文書は変更せず、上から順の階層・座標と任意の画素ハッシュを返す。
// ページ単位で返すため、名前付きパイプのメッセージ上限を超えない。
function InspectArtDocument(Document: TArtDocument; Args: TJSONObject;
  const FileName, SelectedLayerId: string; CanEdit, Modified: Boolean): TJSONObject;

implementation

uses System.SysUtils, System.Classes, System.Hash, System.Generics.Collections,
  ArtPipeProtocol;

function InspectArtDocument(Document: TArtDocument; Args: TJSONObject;
  const FileName, SelectedLayerId: string; CanEdit, Modified: Boolean): TJSONObject;
var Layers: TJSONArray; Offset, Limit, Count: Integer; IncludeHashes: Boolean;
  function BoundsJson(const Bounds: TArtBounds): TJSONObject;
  begin
    Result := TJSONObject.Create;
    Result.AddPair('left', TJSONNumber.Create(Bounds.Left));
    Result.AddPair('top', TJSONNumber.Create(Bounds.Top));
    Result.AddPair('right', TJSONNumber.Create(Bounds.Right));
    Result.AddPair('bottom', TJSONNumber.Create(Bounds.Bottom));
  end;
  procedure AddLayers(List: TList<TArtLayer>; const ParentId: string; Depth: Integer);
  var Layer: TArtLayer; Item: TJSONObject; Index: Integer;
  begin
    if Depth > 128 then raise EArtFormat.Create('Layer tree depth limit');
    for Index := 0 to List.Count - 1 do begin
      Layer := List[Index];
      if (Count >= Offset) and (Count - Offset < Limit) then begin
        Item := TJSONObject.Create; Layers.AddElement(Item);
        Item.AddPair('layerId', Layer.Id); Item.AddPair('parentId', ParentId);
        Item.AddPair('name', Layer.Name); Item.AddPair('index', TJSONNumber.Create(Index));
        if Layer.Kind = alkGroup then Item.AddPair('kind', 'group')
        else if Layer.Kind = alkImage then Item.AddPair('kind', 'image')
        else Item.AddPair('kind', 'divider');
        Item.AddPair('visible', TJSONBool.Create(Layer.Visible));
        Item.AddPair('opacity', TJSONNumber.Create(Layer.Opacity));
        Item.AddPair('bounds', BoundsJson(Layer.Bounds));
        Item.AddPair('hasMask', TJSONBool.Create(Layer.HasMask));
        if Layer.HasMask then Item.AddPair('maskBounds', BoundsJson(Layer.MaskBounds));
        if IncludeHashes and (Layer.Kind = alkImage) then begin
          var Hash := THashSHA2.Create; Hash.Update(Layer.Pixels);
          Item.AddPair('pixelSha256', LowerCase(Hash.HashAsString));
        end;
      end;
      Inc(Count); AddLayers(Layer.Children, Layer.Id, Depth + 1);
    end;
  end;
begin
  if Document = nil then raise EArtFormat.Create('No PSD is open');
  Offset := 0; Limit := 64; IncludeHashes := False;
  if Args.GetValue('offset') <> nil then Offset := CommandInteger(Args, 'offset');
  if Args.GetValue('limit') <> nil then Limit := CommandInteger(Args, 'limit');
  if (Offset < 0) or (Limit < 1) or (Limit > 64) then
    raise EArtFormat.Create('offset must be nonnegative; limit must be between 1 and 64');
  if Args.GetValue('includePixelHashes') <> nil then begin
    if not (Args.GetValue('includePixelHashes') is TJSONBool) then
      raise EArtFormat.Create('Boolean required: includePixelHashes');
    IncludeHashes := TJSONBool(Args.GetValue('includePixelHashes')).AsBoolean;
  end;
  Result := TJSONObject.Create;
  try
    Result.AddPair('documentId', Document.SessionId);
    Result.AddPair('revision', UIntToStr(Document.Revision));
    Result.AddPair('fileName', FileName); Result.AddPair('selectedLayerId', SelectedLayerId);
    Result.AddPair('canEdit', TJSONBool.Create(CanEdit));
    Result.AddPair('modified', TJSONBool.Create(Modified));
    Result.AddPair('width', TJSONNumber.Create(Document.Width));
    Result.AddPair('height', TJSONNumber.Create(Document.Height));
    Result.AddPair('layerOrder', 'topmost-first-depth-first');
    Result.AddPair('offset', TJSONNumber.Create(Offset));
    Result.AddPair('limit', TJSONNumber.Create(Limit));
    Layers := TJSONArray.Create; Result.AddPair('layers', Layers);
    Count := 0; AddLayers(Document.Roots, '', 0);
    Result.AddPair('layerCount', TJSONNumber.Create(Count));
    Result.AddPair('hasMore', TJSONBool.Create(Offset + Layers.Count < Count));
    if Length(TEncoding.UTF8.GetBytes(Result.ToJSON)) > 58000 then
      raise EArtFormat.Create('Document page exceeds pipe limit; use a smaller limit');
  except Result.Free; raise; end;
end;

end.

unit ArtParts;
interface
uses System.Generics.Collections, ArtDocument;
function LayerSiblings(Document: TArtDocument; Layer: TArtLayer): TList<TArtLayer>;
function IsExclusive(Layer: TArtLayer): Boolean;
function IsForced(Layer: TArtLayer): Boolean;
procedure SelectExclusive(Document: TArtDocument; Layer: TArtLayer);
implementation
uses System.SysUtils, ArtLayerName;
function IsExclusive(Layer: TArtLayer): Boolean;
begin Result := (Layer<>nil) and (ParseLayerName(Layer.Name).Prefix='*'); end;
function IsForced(Layer: TArtLayer): Boolean;
begin Result := (Layer<>nil) and (ParseLayerName(Layer.Name).Prefix='!'); end;
function LayerSiblings(Document: TArtDocument; Layer: TArtLayer): TList<TArtLayer>;
  function Find(List: TList<TArtLayer>): TList<TArtLayer>;
  var L: TArtLayer;
  begin
    if List.Contains(Layer) then Exit(List);
    for L in List do begin Result := Find(L.Children); if Result<>nil then Exit; end;
    Result := nil;
  end;
begin
  Result := nil; if (Document<>nil) and (Layer<>nil) then Result := Find(Document.Roots);
  if Result=nil then raise EArtFormat.Create('文書内のレイヤーを選択してください。');
end;
procedure SelectExclusive(Document: TArtDocument; Layer: TArtLayer);
var L: TArtLayer; List: TList<TArtLayer>;
begin
  if not IsExclusive(Layer) then raise EArtFormat.Create('排他選択 (*) を設定してください。');
  List := LayerSiblings(Document,Layer);
  for L in List do if IsExclusive(L) then L.Visible := L=Layer;
end;
end.

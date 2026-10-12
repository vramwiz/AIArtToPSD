unit ArtParts;
interface
uses System.Generics.Collections, ArtDocument;
function LayerSiblings(Document: TArtDocument; Layer: TArtLayer): TList<TArtLayer>;
function IsExclusive(Layer: TArtLayer): Boolean;
function IsForced(Layer: TArtLayer): Boolean;
procedure SelectExclusive(Document: TArtDocument; Layer: TArtLayer);
procedure ValidateExclusiveSelections(Document: TArtDocument);
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
procedure ValidateExclusiveSelections(Document: TArtDocument);
  procedure Validate(List: TList<TArtLayer>; const ParentId: string; Depth: Integer);
  var First: TArtLayer;
  begin
    if Depth>128 then raise EArtFormat.Create('Layer depth limit');
    First := nil;
    for var L in List do
      if IsExclusive(L) and L.Visible then begin
        if First<>nil then
          raise EArtFormat.CreateFmt(
            'Exclusive selection conflict: parentId="%s", layerIds="%s","%s". Use select_part or turn a sibling off.',
            [ParentId,First.Id,L.Id]);
        First := L;
      end;
    for var L in List do Validate(L.Children,L.Id,Depth+1);
  end;
begin
  if Document=nil then raise EArtFormat.Create('文書を開いてください。');
  Validate(Document.Roots,'',0);
end;
end.

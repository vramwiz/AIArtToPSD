unit ArtParts;
interface
uses System.Generics.Collections, ArtDocument;
const ART_EXCLUSIVE_SELECTION_VERSION = 2;
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
var Current,Sibling: TArtLayer; Siblings,Path: TList<TArtLayer>;
  function FindPath(List: TList<TArtLayer>; Depth: Integer): Boolean;
  var Item: TArtLayer;
  begin
    if Depth>128 then raise EArtFormat.Create('Layer depth limit');
    for Item in List do begin
      Path.Add(Item);
      if Item=Layer then Exit(True);
      if Item.Children.Count>0 then
        if FindPath(Item.Children,Depth+1) then Exit(True);
      Path.Delete(Path.Count-1);
    end;
    Result := False;
  end;
begin
  if not IsExclusive(Layer) then raise EArtFormat.Create('排他選択 (*) を設定してください。');
  Path := TList<TArtLayer>.Create;
  try
    // Resolve the complete path before changing visibility. A foreign layer or
    // invalid depth must not partially select its apparent ancestors.
    if Document=nil then raise EArtFormat.Create('No current document');
    if not FindPath(Document.Roots,0) then
      raise EArtFormat.Create('Layer is not in the current document');
    Siblings := Document.Roots;
    for Current in Path do begin
      // Exclusivity is local to the actual parent, never a name-based search.
      // Nonexclusive containers, fixed siblings and other body parts stay intact.
      if IsExclusive(Current) then
        for Sibling in Siblings do
          if IsExclusive(Sibling) then Sibling.Visible := Sibling=Current;
      Current.Visible := True;
      Siblings := Current.Children;
    end;
  finally Path.Free; end;
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

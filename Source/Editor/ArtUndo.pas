unit ArtUndo;
interface
uses System.Generics.Collections, ArtDocument;
type
  TArtEditState = class
  public
    Document: TArtDocument;
    SelectedId: string;
    Modified: Boolean;
    constructor Create(Source: TArtDocument; const Selection: string; Dirty: Boolean);
    destructor Destroy; override;
  end;
  TArtUndo = class
  private
    FUndo,FRedo: TObjectList<TArtEditState>;
    FPending: TArtEditState;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure BeginEdit(Source: TArtDocument; const Selection: string; Dirty: Boolean);
    procedure CommitEdit;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    function Peek(Redo: Boolean): TArtEditState;
    procedure CommitRestore(Current: TArtEditState; Redo: Boolean);
  end;
implementation
uses System.SysUtils;
constructor TArtEditState.Create(Source: TArtDocument; const Selection: string; Dirty: Boolean);
begin inherited Create; Document := Source.Clone; SelectedId := Selection; Modified := Dirty; end;
destructor TArtEditState.Destroy;
begin Document.Free; inherited; end;
constructor TArtUndo.Create;
begin inherited; FUndo := TObjectList<TArtEditState>.Create(True); FRedo := TObjectList<TArtEditState>.Create(True); end;
destructor TArtUndo.Destroy;
begin FPending.Free; FUndo.Free; FRedo.Free; inherited; end;
procedure TArtUndo.Clear;
begin FreeAndNil(FPending); FUndo.Clear; FRedo.Clear; end;
procedure TArtUndo.BeginEdit(Source: TArtDocument; const Selection: string; Dirty: Boolean);
begin FreeAndNil(FPending); FPending := TArtEditState.Create(Source,Selection,Dirty); end;
procedure TArtUndo.CommitEdit;
begin
  if FPending=nil then Exit;
  FUndo.Add(FPending); FPending := nil; FRedo.Clear;
  while FUndo.Count>16 do FUndo.Delete(0);
end;
function TArtUndo.CanUndo: Boolean;
begin Result := FUndo.Count>0; end;
function TArtUndo.CanRedo: Boolean;
begin Result := FRedo.Count>0; end;
function TArtUndo.Peek(Redo: Boolean): TArtEditState;
var List: TObjectList<TArtEditState>;
begin
  if Redo then List := FRedo else List := FUndo;
  if List.Count=0 then raise EArtFormat.Create('戻せる操作がありません。');
  Result := List.Last;
end;
procedure TArtUndo.CommitRestore(Current: TArtEditState; Redo: Boolean);
var Source,Target: TObjectList<TArtEditState>;
begin
  if Redo then begin Source := FRedo; Target := FUndo; end
  else begin Source := FUndo; Target := FRedo; end;
  Target.Add(Current); Source.Delete(Source.Count-1); FreeAndNil(FPending);
end;
end.

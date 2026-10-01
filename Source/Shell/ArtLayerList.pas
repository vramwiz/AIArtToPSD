unit ArtLayerList;
interface
uses System.Classes, System.Types, System.Generics.Collections, Vcl.Controls,
  Vcl.Graphics, Vcl.StdCtrls, Vcl.Menus, ArtDocument, VerticalScrollBarControl, HorizontalTrackBarControl;
type
  TArtLayerRenameEvent = procedure(Sender: TObject; Layer: TArtLayer; const Name: string) of object;
  TArtLayerAttributesEvent = procedure(Sender: TObject; Layer: TArtLayer; Visible: Boolean; Opacity: Byte) of object;
  TArtLayerList = class(TCustomControl)
  private
    FLayers: TList<TArtLayer>;
    FDepths: TList<Integer>;
    FCollapsed: TDictionary<TArtLayer,Boolean>;
    FThumbs: TObjectDictionary<TArtLayer,Vcl.Graphics.TBitmap>;
    FSliders: TObjectList<THorizontalTrackBarControl>;
    FSyncing: Boolean;
    FOnAttributes: TArtLayerAttributesEvent;
    FRoots: TList<TArtLayer>;
    FSelected: TArtLayer;
    FScroll: TVerticalScrollBarControl;
    FEditor: TEdit;
    FEditing: TArtLayer;
    FOriginalName: string;
    FEditEnabled, FVisibilityEnabled, FFinishing: Boolean;
    FOnSelect: TNotifyEvent;
    FOnRename: TArtLayerRenameEvent;
    FPopup: TPopupMenu;
    FStar, FForce: TMenuItem;
    FFlips: array[0..3] of TMenuItem;
    procedure SyncSliders;
    procedure SliderChanged(Sender: TObject);
    procedure SliderWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure SetEditEnabled(Value: Boolean);
    procedure ScrollChanged(Sender: TObject);
    procedure EditorKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditorExit(Sender: TObject);
    procedure PrefixClick(Sender: TObject);
    procedure FlipClick(Sender: TObject);
    procedure PopupOpening(Sender: TObject);
    procedure SetSelected(Value: TArtLayer);
    procedure RefreshRows;
    function NameRect(Index: Integer): TRect;
    function Thumbnail(Layer: TArtLayer): Vcl.Graphics.TBitmap;
    procedure SendRename(const Name: string);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetRoots(Value: TList<TArtLayer>);
    procedure RefreshLayerNames;
    procedure RefreshImages;
    procedure RevealSelected;
    procedure BeginRename;
    procedure FinishRename(Commit: Boolean);
    procedure ScrollBy(Delta: Integer);
    function RowCount: Integer;
    function LayerAt(Index: Integer): TArtLayer;
    property Selected: TArtLayer read FSelected write SetSelected;
    property EditEnabled: Boolean read FEditEnabled write SetEditEnabled;
    property VisibilityEnabled: Boolean read FVisibilityEnabled write FVisibilityEnabled;
    property OnAttributes: TArtLayerAttributesEvent read FOnAttributes write FOnAttributes;
    function SliderAt(Index: Integer): THorizontalTrackBarControl;
    property NameEditor: TEdit read FEditor;
    property ScrollBar: TVerticalScrollBarControl read FScroll;
    property ModifierMenu: TPopupMenu read FPopup;
    property OnSelect: TNotifyEvent read FOnSelect write FOnSelect;
    property OnRename: TArtLayerRenameEvent read FOnRename write FOnRename;
  end;
implementation
uses System.SysUtils, System.Math, System.UITypes, Winapi.Windows, Vcl.Dialogs, ArtLayerName;
const ROW_HEIGHT=82; GAP=6; LIST_PADDING=8; INDENT=8; THUMB_W=96; THUMB_H=54;
constructor TArtLayerList.Create(AOwner: TComponent);
var I: Integer; Item: TMenuItem;
const Captions: array[0..3] of string = ('反転指定なし','左右反転時 (:flipx)','上下反転時 (:flipy)','両方向反転時 (:flipxy)');
begin
  inherited; DoubleBuffered := True; TabStop := True;
  ControlStyle := ControlStyle+[csOpaque,csDoubleClicks]; StyleElements := [];
  Font.Name := 'Yu Gothic UI'; Font.Size := 10;
  FLayers := TList<TArtLayer>.Create; FDepths := TList<Integer>.Create;
  FCollapsed := TDictionary<TArtLayer,Boolean>.Create;
  FThumbs := TObjectDictionary<TArtLayer,Vcl.Graphics.TBitmap>.Create([doOwnsValues]);
  FSliders := TObjectList<THorizontalTrackBarControl>.Create(True);
  FScroll := TVerticalScrollBarControl.Create(Self); FScroll.Parent := Self; FScroll.Align := alRight;
  FScroll.OnChange := ScrollChanged; FScroll.SmallChange := ROW_HEIGHT+GAP;
  FEditor := TEdit.Create(Self); FEditor.Parent := Self; FEditor.Visible := False;
  FEditor.OnKeyDown := EditorKey; FEditor.OnExit := EditorExit;
  FPopup := TPopupMenu.Create(Self); FPopup.OnPopup := PopupOpening;
  FStar := TMenuItem.Create(Self); FStar.Caption := '* 排他選択'; FStar.OnClick := PrefixClick; FPopup.Items.Add(FStar);
  FForce := TMenuItem.Create(Self); FForce.Caption := '! 強制表示'; FForce.OnClick := PrefixClick; FPopup.Items.Add(FForce);
  Item := TMenuItem.Create(Self); Item.Caption := '-'; FPopup.Items.Add(Item);
  for I := 0 to 3 do begin
    FFlips[I] := TMenuItem.Create(Self); FFlips[I].Caption := Captions[I]; FFlips[I].Tag := I;
    FFlips[I].OnClick := FlipClick; FFlips[I].RadioItem := True; FFlips[I].GroupIndex := 1;
    FPopup.Items.Add(FFlips[I]);
  end;
end;
destructor TArtLayerList.Destroy;
begin
  FEditor.OnExit := nil; FSliders.Free; FThumbs.Free; FCollapsed.Free; FDepths.Free; FLayers.Free; inherited;
end;
function TArtLayerList.RowCount: Integer;
begin Result := FLayers.Count; end;
function TArtLayerList.LayerAt(Index: Integer): TArtLayer;
begin Result := FLayers[Index]; end;
procedure TArtLayerList.SetRoots(Value: TList<TArtLayer>);
  procedure CollapseDeep(List: TList<TArtLayer>; Depth: Integer);
  var L: TArtLayer;
  begin
    for L in List do begin
      if (L.Kind=alkGroup) and (Depth>=2) then FCollapsed.AddOrSetValue(L,True);
      CollapseDeep(L.Children,Depth+1);
    end;
  end;
begin
  FinishRename(False); FSelected := nil; FRoots := Value;
  FCollapsed.Clear; if Value<>nil then CollapseDeep(Value,0); FThumbs.Clear; FScroll.Position := 0; RefreshRows;
  if FLayers.Count>0 then Selected := FLayers[0]
  else if Assigned(FOnSelect) then FOnSelect(Self);
end;
procedure TArtLayerList.RefreshRows;
  procedure Add(List: TList<TArtLayer>; Depth: Integer);
  var L: TArtLayer;
  begin
    for L in List do begin
      FLayers.Add(L); FDepths.Add(Depth);
      if not FCollapsed.ContainsKey(L) then Add(L.Children,Depth+1);
    end;
  end;
begin
  FLayers.Clear; FDepths.Clear;
  if Assigned(FRoots) then Add(FRoots,0);
  FScroll.SetRange(Max(0,FLayers.Count*(ROW_HEIGHT+GAP)+LIST_PADDING*2-Height),Max(1,Height));
  FScroll.LargeChange := Max(1,Height); SyncSliders; Invalidate;
end;
procedure TArtLayerList.RevealSelected;
var Index,Y: Integer;
  function ExpandParents(List: TList<TArtLayer>): Boolean;
  var L: TArtLayer;
  begin
    Result := False;
    for L in List do begin
      if L=FSelected then Exit(True);
      if ExpandParents(L.Children) then begin FCollapsed.Remove(L); Exit(True); end;
    end;
  end;
begin
  if (FSelected=nil) or (FRoots=nil) then Exit;
  ExpandParents(FRoots); RefreshRows; Index := FLayers.IndexOf(FSelected); if (Index<0) or (Height<ROW_HEIGHT) then Exit;
  Y := LIST_PADDING+Index*(ROW_HEIGHT+GAP);
  if Y<FScroll.Position then FScroll.Position := Y
  else if Y+ROW_HEIGHT>FScroll.Position+Height then FScroll.Position := Y+ROW_HEIGHT-Height;
end;
procedure TArtLayerList.RefreshImages;
begin FThumbs.Clear; RefreshRows; end;
procedure TArtLayerList.RefreshLayerNames;
begin SyncSliders; Invalidate; end;
procedure TArtLayerList.Resize;
begin inherited; if FScroll<>nil then begin FinishRename(False); RefreshRows; end; end;
procedure TArtLayerList.ScrollChanged(Sender: TObject);
begin FinishRename(False); SyncSliders; Invalidate; end;
procedure TArtLayerList.ScrollBy(Delta: Integer);
begin FScroll.Position := FScroll.Position+Delta; end;
function TArtLayerList.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin ScrollBy(-MulDiv(WheelDelta,ROW_HEIGHT+GAP,120)); Result := True; end;
procedure TArtLayerList.SetSelected(Value: TArtLayer);
begin
  if Value=FSelected then Exit;
  FinishRename(True); FSelected := Value; SyncSliders; Invalidate;
  if Assigned(FOnSelect) then FOnSelect(Self);
end;
function TArtLayerList.NameRect(Index: Integer): TRect;
var Y,X: Integer;
begin
  Y := LIST_PADDING+Index*(ROW_HEIGHT+GAP)-FScroll.Position;
  X := LIST_PADDING+Min(FDepths[Index],6)*INDENT+46+THUMB_W+10;
  Result := Rect(X,Y+10,Width-FScroll.Width-LIST_PADDING-48,Y+38);
end;
procedure TArtLayerList.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
var Index,LeftEdge: Integer; P: TPoint; L: TArtLayer;
begin
  inherited; if CanFocus then SetFocus; Index := (Y+FScroll.Position-LIST_PADDING) div (ROW_HEIGHT+GAP);
  if (Y+FScroll.Position<LIST_PADDING) or (Index<0) or (Index>=FLayers.Count) then Exit;
  if ((Y+FScroll.Position-LIST_PADDING) mod (ROW_HEIGHT+GAP)>=ROW_HEIGHT) then Exit;
  L := FLayers[Index]; Selected := L;
  if (Button=mbLeft) and (X>=LIST_PADDING) and (X<LIST_PADDING+26) then begin
    if (FEditEnabled or FVisibilityEnabled) and Assigned(FOnAttributes) then
      try FOnAttributes(Self,L,not L.Visible,L.Opacity);
      except on E: Exception do MessageDlg(E.Message,mtError,[mbOK],0); end;
    SyncSliders; Invalidate; Exit;
  end;
  LeftEdge := LIST_PADDING+26+Min(FDepths[Index],6)*INDENT;
  if (Button=mbLeft) and (X>=LeftEdge) and (X<LeftEdge+18) and (L.Kind=alkGroup) then begin
    if FCollapsed.ContainsKey(L) then FCollapsed.Remove(L) else FCollapsed.Add(L,True);
    RefreshRows;
  end;
  if (Button=mbRight) and FEditEnabled then begin
    FinishRename(True); P := ClientToScreen(Point(X,Y)); FPopup.Popup(P.X,P.Y);
  end;
end;
procedure TArtLayerList.DblClick;
var P: TPoint; Index: Integer;
begin
  inherited; P := ScreenToClient(Mouse.CursorPos); Index := FLayers.IndexOf(FSelected);
  if (Index>=0) and PtInRect(NameRect(Index),P) then BeginRename;
end;
procedure TArtLayerList.BeginRename;
var R: TRect; Index: Integer;
begin
  if not FEditEnabled or (FSelected=nil) then Exit;
  FinishRename(False); Index := FLayers.IndexOf(FSelected); if Index<0 then Exit;
  R := NameRect(Index);
  FEditing := FSelected; FOriginalName := FSelected.Name;
  FEditor.SetBounds(R.Left,R.Top,Max(40,R.Width),26);
  FEditor.Text := ParseLayerName(FOriginalName).DisplayName;
  FEditor.Visible := True; FEditor.SetFocus; FEditor.SelectAll;
end;
procedure TArtLayerList.FinishRename(Commit: Boolean);
var NewName: string;
begin
  if (FEditor=nil) or FFinishing or not FEditor.Visible then Exit;
  FFinishing := True;
  try
    if Commit then begin
      NewName := RenameLayerDisplay(FOriginalName,FEditor.Text);
      if NewName<>FEditing.Name then SendRename(NewName);
    end;
    FEditor.Visible := False; FEditing := nil;
  finally FFinishing := False; end;
end;
procedure TArtLayerList.EditorKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  try
    if Key=VK_RETURN then begin FinishRename(True); Key := 0; end
    else if Key=VK_ESCAPE then begin FinishRename(False); Key := 0; end;
  except on E: Exception do begin MessageDlg(E.Message,mtError,[mbOK],0); FEditor.SetFocus; end; end;
end;
procedure TArtLayerList.EditorExit(Sender: TObject);
begin
  try FinishRename(True);
  except on E: Exception do begin MessageDlg(E.Message,mtError,[mbOK],0); FinishRename(False); end; end;
end;
procedure TArtLayerList.SendRename(const Name: string);
begin
  if not FEditEnabled or (FSelected=nil) then Exit;
  if Assigned(FOnRename) then FOnRename(Self,FSelected,Name);
  Invalidate;
end;
procedure TArtLayerList.PopupOpening(Sender: TObject);
var Parts: TArtLayerNameParts; I: Integer;
const Suffixes: array[0..3] of string = ('',':flipx',':flipy',':flipxy');
begin
  if FSelected=nil then Exit;
  Parts := ParseLayerName(FSelected.Name);
  FStar.Checked := Parts.Prefix='*'; FForce.Checked := Parts.Prefix='!';
  FStar.Enabled := FEditEnabled; FForce.Enabled := FEditEnabled;
  for I := 0 to 3 do begin FFlips[I].Enabled := FEditEnabled; FFlips[I].Checked := Parts.Suffix=Suffixes[I]; end;
end;
procedure TArtLayerList.PrefixClick(Sender: TObject);
var Prefix: string;
begin
  if FSelected=nil then Exit;
  if Sender=FStar then Prefix := '*' else Prefix := '!';
  if ParseLayerName(FSelected.Name).Prefix=Prefix then Prefix := '';
  try SendRename(SetLayerPrefix(FSelected.Name,Prefix));
  except on E: Exception do MessageDlg(E.Message,mtError,[mbOK],0); end;
end;
procedure TArtLayerList.FlipClick(Sender: TObject);
const Suffixes: array[0..3] of string = ('',':flipx',':flipy',':flipxy');
begin
  if FSelected=nil then Exit;
  try SendRename(SetLayerFlip(FSelected.Name,Suffixes[TMenuItem(Sender).Tag]));
  except on E: Exception do MessageDlg(E.Message,mtError,[mbOK],0); end;
end;
procedure TArtLayerList.SetEditEnabled(Value: Boolean);
begin FEditEnabled := Value; if FSliders<>nil then SyncSliders; end;
function TArtLayerList.SliderAt(Index: Integer): THorizontalTrackBarControl;
var Slider: THorizontalTrackBarControl;
begin
  Result := nil;
  for Slider in FSliders do if Slider.Visible and (Slider.Tag=Index) then Exit(Slider);
end;
procedure TArtLayerList.SyncSliders;
var I,Y,N: Integer; R: TRect; Slider: THorizontalTrackBarControl;
begin
  if FSliders=nil then Exit;
  if not FEditEnabled then begin for Slider in FSliders do Slider.Visible := False; Exit; end;
  FSyncing := True;
  try
    N := 0;
    for I := 0 to FLayers.Count-1 do begin
      Y := LIST_PADDING+I*(ROW_HEIGHT+GAP)-FScroll.Position;
      if (Y+70<=0) or (Y+42>=Height) then Continue;
      if N=FSliders.Count then begin
        Slider := THorizontalTrackBarControl.Create(Self); Slider.Parent := Self;
        Slider.SetRange(0,255); Slider.ShowTicks := False; Slider.WheelChangesPosition := False;
        Slider.OnChange := SliderChanged; Slider.OnMouseWheel := SliderWheel;
        FSliders.Add(Slider);
      end;
      Slider := FSliders[N]; Inc(N); R := NameRect(I);
      Slider.Tag := I; Slider.SetBounds(R.Left,Y+42,Max(30,Width-FScroll.Width-LIST_PADDING-5-R.Left),28);
      Slider.BackgroundColor := $272727;
      if FLayers[I]=FSelected then Slider.BackgroundColor := $865E24;
      Slider.Position := FLayers[I].Opacity;
      Slider.Enabled := FEditEnabled and ((FLayers[I].Kind=alkImage) or ((FLayers[I].Kind=alkGroup) and (FLayers[I].BlendKey='norm')));
      Slider.Hint := '不透明度 '+IntToStr(Round(FLayers[I].Opacity*100/255))+'%'; Slider.ShowHint := True;
      Slider.Visible := True;
    end;
    for I := N to FSliders.Count-1 do FSliders[I].Visible := False;
  finally FSyncing := False; end;
end;
procedure TArtLayerList.SliderWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin Handled := DoMouseWheel(Shift,WheelDelta,MousePos); end;
procedure TArtLayerList.SliderChanged(Sender: TObject);
var Slider: THorizontalTrackBarControl; L: TArtLayer; Value: Byte;
begin
  if FSyncing or not FEditEnabled then Exit;
  Slider := THorizontalTrackBarControl(Sender);
  if (Slider.Tag<0) or (Slider.Tag>=FLayers.Count) then Exit;
  L := FLayers[Slider.Tag]; Value := Slider.Position; Selected := L;
  if Assigned(FOnAttributes) then
    try FOnAttributes(Self,L,L.Visible,Value);
    except on E: Exception do MessageDlg(E.Message,mtError,[mbOK],0); end;
  SyncSliders; Invalidate;
end;
function TArtLayerList.Thumbnail(Layer: TArtLayer): Vcl.Graphics.TBitmap;
var X,Y,P,A,C,V,SX,SY,W,H: Integer; Row: PByte;
begin
  if FThumbs.TryGetValue(Layer,Result) then Exit;
  Result := Vcl.Graphics.TBitmap.Create; Result.PixelFormat := pf32bit; Result.SetSize(THUMB_W,THUMB_H);
  W := Layer.Bounds.Width; H := Layer.Bounds.Height;
  for Y := 0 to THUMB_H-1 do begin
    Row := Result.ScanLine[Y];
    for X := 0 to THUMB_W-1 do begin
      if (X div 6+Y div 6) mod 2=0 then V := 195 else V := 145;
      for C := 0 to 2 do Row[X*4+C] := V;
      Row[X*4+3] := 255;
    end;
  end;
  if (Layer.Kind=alkImage) and (W>0) and (H>0) and (Length(Layer.Pixels)=W*H*4) then begin
    if W/THUMB_W>H/THUMB_H then begin SX := THUMB_W; SY := Max(1,Round(H*THUMB_W/W)); end
    else begin SY := THUMB_H; SX := Max(1,Round(W*THUMB_H/H)); end;
    for Y := 0 to SY-1 do begin
      Row := Result.ScanLine[Y+(THUMB_H-SY) div 2];
      for X := 0 to SX-1 do begin
        P := ((Y*H div SY)*W+X*W div SX)*4; A := Layer.Pixels[P+3];
        for C := 0 to 2 do begin
          V := Row[(X+(THUMB_W-SX) div 2)*4+2-C];
          Row[(X+(THUMB_W-SX) div 2)*4+2-C] := (Layer.Pixels[P+C]*A+V*(255-A)+127) div 255;
        end;
      end;
    end;
  end else begin
    Result.Canvas.Brush.Color := $4080C0;
    Result.Canvas.RoundRect(22,15,75,42,4,4);
  end;
  FThumbs.Add(Layer,Result);
end;
procedure TArtLayerList.Paint;
var I,Y,X: Integer; R,N: TRect; L: TArtLayer; Parts: TArtLayerNameParts; Info: string;
begin
  Canvas.Brush.Color := $1A1A1A; Canvas.FillRect(ClientRect); Canvas.Font.Assign(Font);
  for I := 0 to FLayers.Count-1 do begin
    Y := LIST_PADDING+I*(ROW_HEIGHT+GAP)-FScroll.Position;
    if Y+ROW_HEIGHT<0 then Continue;
    if Y>Height then Break;
    L := FLayers[I]; X := LIST_PADDING+26+Min(FDepths[I],6)*INDENT;
    R := Rect(LIST_PADDING,Y,Width-FScroll.Width-LIST_PADDING,Y+ROW_HEIGHT);
    if L=FSelected then Canvas.Brush.Color := $865E24 else Canvas.Brush.Color := $272727;
    Canvas.Pen.Color := $424242; Canvas.Rectangle(R);
    Canvas.Pen.Color := $D8D8D8; Canvas.Brush.Style := bsClear;
    if L.Visible then begin
      Canvas.Ellipse(LIST_PADDING+4,Y+31,LIST_PADDING+22,Y+44);
      Canvas.Brush.Style := bsSolid; Canvas.Brush.Color := $D8D8D8;
      Canvas.Ellipse(LIST_PADDING+10,Y+34,LIST_PADDING+16,Y+41);
    end else begin
      Canvas.Pen.Color := $777777;
      Canvas.MoveTo(LIST_PADDING+4,Y+42); Canvas.LineTo(LIST_PADDING+22,Y+33);
    end;
    Canvas.Brush.Style := bsClear; Canvas.Font.Color := $E6E6E6;
    if L.Kind=alkGroup then begin
      if FCollapsed.ContainsKey(L) then Canvas.TextOut(X+3,Y+32,'▶') else Canvas.TextOut(X+3,Y+32,'▼');
    end;
    Canvas.Draw(X+20,Y+(ROW_HEIGHT-THUMB_H) div 2,Thumbnail(L));
    Parts := ParseLayerName(L.Name); N := NameRect(I);
    Info := Parts.Prefix+Parts.DisplayName+Parts.Suffix;
    DrawText(Canvas.Handle,PChar(Info),-1,N,DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
    N.Left := N.Right+3; N.Right := Width-FScroll.Width-LIST_PADDING-4;
    Info := IntToStr(Round(L.Opacity*100/255))+'%';
    Canvas.Font.Color := $B8B8B8;
    DrawText(Canvas.Handle,PChar(Info),-1,N,DT_SINGLELINE or DT_VCENTER or DT_RIGHT or DT_NOPREFIX);
    Canvas.Brush.Style := bsSolid;
  end;
end;
end.

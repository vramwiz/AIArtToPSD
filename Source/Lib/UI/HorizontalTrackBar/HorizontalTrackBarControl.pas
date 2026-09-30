// Windows標準TRACKBARへ依存せず、任意の配色で描画できる汎用横型トラックバー。
unit HorizontalTrackBarControl;

interface

uses System.Classes, System.Types, Winapi.Messages, Vcl.Controls, Vcl.Graphics;

type
  THorizontalTrackBarControl = class(TCustomControl)
  private
    FBackgroundColor: TColor;
    FChannelColor: TColor;
    FDisabledColor: TColor;
    FDragging: Boolean;
    FFillColor: TColor;
    FFrequency: Integer;
    FLargeChange: Integer;
    FMaximum: Integer;
    FMinimum: Integer;
    FOnChange: TNotifyEvent;
    FPosition: Integer;
    FShowTicks: Boolean;
    FSmallChange: Integer;
    FThumbBorderColor: TColor;
    FThumbColor: TColor;
    FTickColor: TColor;
    FWheelChangesPosition: Boolean;
    procedure CMEnabledChanged(var Message: TMessage);
      message CM_ENABLEDCHANGED;
    procedure CMFocusChanged(var Message: TCMFocusChanged);
      message CM_FOCUSCHANGED;
    function PositionToX: Integer;
    function SnapPosition(Value: Integer): Integer;
    procedure SetBackgroundColor(Value: TColor);
    procedure SetChannelColor(Value: TColor);
    procedure SetDisabledColor(Value: TColor);
    procedure SetFillColor(Value: TColor);
    procedure SetFrequency(Value: Integer);
    procedure SetLargeChange(Value: Integer);
    procedure SetMaximum(Value: Integer);
    procedure SetMinimum(Value: Integer);
    procedure SetPosition(Value: Integer);
    procedure SetShowTicks(Value: Boolean);
    procedure SetSmallChange(Value: Integer);
    procedure SetThumbBorderColor(Value: TColor);
    procedure SetThumbColor(Value: TColor);
    procedure SetTickColor(Value: TColor);
    function TrackBounds: TRect;
    function XToPosition(X: Integer): Integer;
  protected
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure Paint; override;
  public
    // キーボード、マウス、ホイール操作に対応する横型トラックバーを既定値で生成する。
    constructor Create(AOwner: TComponent); override;
    // 最小値と最大値を同時に更新し、現在位置を新しい範囲内へ補正する。
    procedure SetRange(AMinimum, AMaximum: Integer);
  published
    property Align;
    property AlignWithMargins;
    property Anchors;
    property BackgroundColor: TColor read FBackgroundColor
      write SetBackgroundColor;
    property ChannelColor: TColor read FChannelColor write SetChannelColor;
    property DisabledColor: TColor read FDisabledColor write SetDisabledColor;
    property Enabled;
    property FillColor: TColor read FFillColor write SetFillColor;
    property Frequency: Integer read FFrequency write SetFrequency default 10;
    property Hint;
    property LargeChange: Integer read FLargeChange write SetLargeChange
      default 10;
    property Maximum: Integer read FMaximum write SetMaximum default 100;
    property Minimum: Integer read FMinimum write SetMinimum default 0;
    property Position: Integer read FPosition write SetPosition default 0;
    property ShowHint;
    property ShowTicks: Boolean read FShowTicks write SetShowTicks default True;
    property SmallChange: Integer read FSmallChange write SetSmallChange
      default 1;
    property TabOrder;
    property TabStop default True;
    property ThumbBorderColor: TColor read FThumbBorderColor
      write SetThumbBorderColor;
    property ThumbColor: TColor read FThumbColor write SetThumbColor;
    property TickColor: TColor read FTickColor write SetTickColor;
    property Visible;
    property WheelChangesPosition: Boolean read FWheelChangesPosition
      write FWheelChangesPosition default True;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnEnter;
    property OnExit;
    property OnKeyDown;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnMouseWheel;
  end;

implementation

uses System.Math, Winapi.Windows, HorizontalTrackBarRenderer;

function TrackScale(Value, PPI: Integer): Integer;
begin
  Result := MulDiv(Value, PPI, 96);
end;

constructor THorizontalTrackBarControl.Create(AOwner: TComponent);
begin
  inherited;
  ControlStyle := ControlStyle + [csOpaque, csClickEvents, csCaptureMouse];
  DoubleBuffered := True;
  Cursor := crHandPoint;
  Height := 40;
  TabStop := True;
  FBackgroundColor := TColor($001E1E1E);
  FChannelColor := TColor($00505050);
  FDisabledColor := TColor($00808080);
  FFillColor := TColor($00FF6666);
  FFrequency := 10;
  FLargeChange := 10;
  FMaximum := 100;
  FMinimum := 0;
  FShowTicks := True;
  FSmallChange := 1;
  FThumbBorderColor := TColor($00DCDCDC);
  FThumbColor := TColor($003A3A3A);
  FTickColor := TColor($00808080);
  FWheelChangesPosition := True;
end;

procedure THorizontalTrackBarControl.CMEnabledChanged(var Message: TMessage);
begin
  inherited;
  Invalidate;
end;

procedure THorizontalTrackBarControl.CMFocusChanged(
  var Message: TCMFocusChanged);
begin
  inherited;
  Invalidate;
end;

function THorizontalTrackBarControl.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := Enabled and FWheelChangesPosition and (WheelDelta <> 0);
  if Result then
  begin
    if WheelDelta > 0 then
      Position := FPosition + FSmallChange
    else
      Position := FPosition - FSmallChange;
  end
  else
    Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
end;

procedure THorizontalTrackBarControl.KeyDown(var Key: Word;
  Shift: TShiftState);
begin
  if Enabled then
    case Key of
      VK_LEFT, VK_DOWN: Position := FPosition - FSmallChange;
      VK_RIGHT, VK_UP: Position := FPosition + FSmallChange;
      VK_PRIOR: Position := FPosition + FLargeChange;
      VK_NEXT: Position := FPosition - FLargeChange;
      VK_HOME: Position := FMinimum;
      VK_END: Position := FMaximum;
    else
      inherited;
      Exit;
    end
  else
  begin
    inherited;
    Exit;
  end;
  Key := 0;
end;

procedure THorizontalTrackBarControl.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if not Enabled or (Button <> mbLeft) then
    Exit;
  if CanFocus then
    SetFocus;
  FDragging := True;
  MouseCapture := True;
  Position := XToPosition(X);
end;

procedure THorizontalTrackBarControl.MouseMove(Shift: TShiftState;
  X, Y: Integer);
begin
  inherited;
  if FDragging and Enabled then
    Position := XToPosition(X);
end;

procedure THorizontalTrackBarControl.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  FDragging := False;
  MouseCapture := False;
end;

procedure THorizontalTrackBarControl.Paint;
var
  State: THorizontalTrackBarRenderState;
begin
  State.BackgroundColor := FBackgroundColor;
  State.ChannelColor := FChannelColor;
  State.ClientRect := ClientRect;
  State.DisabledColor := FDisabledColor;
  State.Enabled := Enabled;
  State.FillColor := FFillColor;
  State.Focused := Focused;
  State.Frequency := FFrequency;
  State.Maximum := FMaximum;
  State.Minimum := FMinimum;
  State.PPI := CurrentPPI;
  State.ShowTicks := FShowTicks;
  State.ThumbBorderColor := FThumbBorderColor;
  State.ThumbColor := FThumbColor;
  State.ThumbX := PositionToX;
  State.TickColor := FTickColor;
  State.TrackRect := TrackBounds;
  DrawHorizontalTrackBar(Canvas, State);
end;

function THorizontalTrackBarControl.PositionToX: Integer;
var
  Track: TRect;
begin
  Track := TrackBounds;
  if FMaximum <= FMinimum then
    Exit(Track.Left);
  Result := Track.Left + MulDiv(FPosition - FMinimum, Track.Width,
    FMaximum - FMinimum);
end;

procedure THorizontalTrackBarControl.SetBackgroundColor(Value: TColor);
begin
  if FBackgroundColor = Value then Exit;
  FBackgroundColor := Value;
  Invalidate;
end;

procedure THorizontalTrackBarControl.SetChannelColor(Value: TColor);
begin
  if FChannelColor = Value then Exit;
  FChannelColor := Value;
  Invalidate;
end;

procedure THorizontalTrackBarControl.SetDisabledColor(Value: TColor);
begin
  if FDisabledColor = Value then Exit;
  FDisabledColor := Value;
  Invalidate;
end;

procedure THorizontalTrackBarControl.SetFillColor(Value: TColor);
begin
  if FFillColor = Value then Exit;
  FFillColor := Value;
  Invalidate;
end;

procedure THorizontalTrackBarControl.SetFrequency(Value: Integer);
begin
  Value := Max(Value, 1);
  if FFrequency = Value then Exit;
  FFrequency := Value;
  Invalidate;
end;

procedure THorizontalTrackBarControl.SetLargeChange(Value: Integer);
begin
  FLargeChange := Max(Value, 1);
end;

procedure THorizontalTrackBarControl.SetMaximum(Value: Integer);
begin
  if Value < FMinimum then Value := FMinimum;
  if FMaximum = Value then Exit;
  FMaximum := Value;
  SetPosition(FPosition);
  Invalidate;
end;

procedure THorizontalTrackBarControl.SetMinimum(Value: Integer);
begin
  if Value > FMaximum then Value := FMaximum;
  if FMinimum = Value then Exit;
  FMinimum := Value;
  SetPosition(FPosition);
  Invalidate;
end;

procedure THorizontalTrackBarControl.SetPosition(Value: Integer);
var
  NewPosition: Integer;
begin
  NewPosition := EnsureRange(SnapPosition(Value), FMinimum, FMaximum);
  if FPosition = NewPosition then Exit;
  FPosition := NewPosition;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure THorizontalTrackBarControl.SetRange(AMinimum, AMaximum: Integer);
begin
  if AMaximum < AMinimum then
    AMaximum := AMinimum;
  FMinimum := AMinimum;
  FMaximum := AMaximum;
  SetPosition(FPosition);
  Invalidate;
end;

procedure THorizontalTrackBarControl.SetShowTicks(Value: Boolean);
begin
  if FShowTicks = Value then Exit;
  FShowTicks := Value;
  Invalidate;
end;

procedure THorizontalTrackBarControl.SetSmallChange(Value: Integer);
begin
  FSmallChange := Max(Value, 1);
  SetPosition(FPosition);
end;

procedure THorizontalTrackBarControl.SetThumbBorderColor(Value: TColor);
begin
  if FThumbBorderColor = Value then Exit;
  FThumbBorderColor := Value;
  Invalidate;
end;

procedure THorizontalTrackBarControl.SetThumbColor(Value: TColor);
begin
  if FThumbColor = Value then Exit;
  FThumbColor := Value;
  Invalidate;
end;

procedure THorizontalTrackBarControl.SetTickColor(Value: TColor);
begin
  if FTickColor = Value then Exit;
  FTickColor := Value;
  Invalidate;
end;

function THorizontalTrackBarControl.SnapPosition(Value: Integer): Integer;
begin
  if FSmallChange <= 1 then
    Exit(Value);
  Result := FMinimum + Round((Value - FMinimum) / FSmallChange) *
    FSmallChange;
end;

function THorizontalTrackBarControl.TrackBounds: TRect;
var
  HorizontalMargin: Integer;
begin
  HorizontalMargin := TrackScale(8, CurrentPPI);
  Result.Left := HorizontalMargin;
  Result.Right := Max(ClientWidth - HorizontalMargin, Result.Left);
  Result.Top := TrackScale(13, CurrentPPI);
  Result.Bottom := Result.Top;
end;

function THorizontalTrackBarControl.XToPosition(X: Integer): Integer;
var
  Track: TRect;
begin
  Track := TrackBounds;
  if (Track.Width <= 0) or (FMaximum <= FMinimum) then
    Exit(FMinimum);
  Result := FMinimum + MulDiv(EnsureRange(X, Track.Left, Track.Right) -
    Track.Left, FMaximum - FMinimum, Track.Width);
  Result := SnapPosition(Result);
end;

end.

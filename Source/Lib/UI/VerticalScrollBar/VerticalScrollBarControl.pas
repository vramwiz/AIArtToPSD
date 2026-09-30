// Windows標準SCROLLBARへ依存せず、暗色UIに合わせて描画する縦スクロールバー。
unit VerticalScrollBarControl;

interface

uses
  System.Classes, System.Types, Winapi.Messages, Vcl.Controls, Vcl.Graphics;

type
  TVerticalScrollBarControl = class(TCustomControl)
  private
    FBackgroundColor: TColor;
    FDragging: Boolean;
    FDragOffset: Integer;
    FLargeChange: Integer;
    FMaximum: Integer;
    FOnChange: TNotifyEvent;
    FPageSize: Integer;
    FPosition: Integer;
    FSmallChange: Integer;
    FThumbBorderColor: TColor;
    FThumbColor: TColor;
    FTrackColor: TColor;
    procedure CMEnabledChanged(var Message: TMessage);
      message CM_ENABLEDCHANGED;
    function ThumbRect: TRect;
    function TrackRect: TRect;
    procedure SetBackgroundColor(Value: TColor);
    procedure SetMaximum(Value: Integer);
    procedure SetPageSize(Value: Integer);
    procedure SetPosition(Value: Integer);
    procedure SetThumbBorderColor(Value: TColor);
    procedure SetThumbColor(Value: TColor);
    procedure SetTrackColor(Value: TColor);
    function ThumbTopToPosition(ThumbTop: Integer): Integer;
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
    constructor Create(AOwner: TComponent); override;
    // 最大スクロール量と表示領域をまとめて更新する。
    procedure SetRange(AMaximum, APageSize: Integer);
  published
    property Align;
    property Anchors;
    property BackgroundColor: TColor read FBackgroundColor
      write SetBackgroundColor;
    property Enabled;
    property LargeChange: Integer read FLargeChange write FLargeChange;
    property Maximum: Integer read FMaximum write SetMaximum default 0;
    property PageSize: Integer read FPageSize write SetPageSize default 1;
    property Position: Integer read FPosition write SetPosition default 0;
    property SmallChange: Integer read FSmallChange write FSmallChange;
    property TabOrder;
    property TabStop default True;
    property ThumbBorderColor: TColor read FThumbBorderColor
      write SetThumbBorderColor;
    property ThumbColor: TColor read FThumbColor write SetThumbColor;
    property TrackColor: TColor read FTrackColor write SetTrackColor;
    property Visible;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnEnter;
    property OnExit;
  end;

implementation

uses
  System.Math, Winapi.Windows;

const
  MINIMUM_THUMB_HEIGHT = 24;
  TRACK_MARGIN = 2;

function ScrollBarScale(Value, PPI: Integer): Integer;
begin
  Result := MulDiv(Value, PPI, 96);
end;

constructor TVerticalScrollBarControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque, csClickEvents, csCaptureMouse];
  DoubleBuffered := True;
  Width := 14;
  TabStop := True;
  FBackgroundColor := TColor($00212121);
  FLargeChange := 100;
  FPageSize := 1;
  FSmallChange := 20;
  FThumbBorderColor := TColor($00666666);
  FThumbColor := TColor($00585858);
  FTrackColor := TColor($002D2D2D);
end;

procedure TVerticalScrollBarControl.CMEnabledChanged(var Message: TMessage);
begin
  inherited;
  Invalidate;
end;

function TVerticalScrollBarControl.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := Enabled and (FMaximum > 0) and (WheelDelta <> 0);
  if Result then
    Position := FPosition - MulDiv(WheelDelta, Max(FSmallChange, 1),
      WHEEL_DELTA)
  else
    Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
end;

procedure TVerticalScrollBarControl.KeyDown(var Key: Word;
  Shift: TShiftState);
begin
  if Enabled then
    case Key of
      VK_UP: Position := FPosition - Max(FSmallChange, 1);
      VK_DOWN: Position := FPosition + Max(FSmallChange, 1);
      VK_PRIOR: Position := FPosition - Max(FLargeChange, 1);
      VK_NEXT: Position := FPosition + Max(FLargeChange, 1);
      VK_HOME: Position := 0;
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

procedure TVerticalScrollBarControl.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Thumb: TRect;
begin
  inherited;
  if not Enabled or (Button <> mbLeft) or (FMaximum <= 0) then
    Exit;
  if CanFocus then
    SetFocus;
  Thumb := ThumbRect;
  if PtInRect(Thumb, Point(X, Y)) then
  begin
    FDragging := True;
    FDragOffset := Y - Thumb.Top;
    MouseCapture := True;
  end
  else if Y < Thumb.Top then
    Position := FPosition - Max(FLargeChange, 1)
  else
    Position := FPosition + Max(FLargeChange, 1);
end;

procedure TVerticalScrollBarControl.MouseMove(Shift: TShiftState;
  X, Y: Integer);
begin
  inherited;
  if FDragging and Enabled then
    Position := ThumbTopToPosition(Y - FDragOffset);
end;

procedure TVerticalScrollBarControl.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  FDragging := False;
  MouseCapture := False;
end;

procedure TVerticalScrollBarControl.Paint;
var
  Thumb: TRect;
  Track: TRect;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBackgroundColor;
  Canvas.FillRect(ClientRect);
  Track := TrackRect;
  Canvas.Brush.Color := FTrackColor;
  Canvas.Pen.Style := psClear;
  Canvas.RoundRect(Track.Left, Track.Top, Track.Right, Track.Bottom,
    ScrollBarScale(5, CurrentPPI), ScrollBarScale(5, CurrentPPI));
  if FMaximum <= 0 then
    Exit;
  Thumb := ThumbRect;
  if Enabled then
    Canvas.Brush.Color := FThumbColor
  else
    Canvas.Brush.Color := FTrackColor;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := FThumbBorderColor;
  Canvas.RoundRect(Thumb.Left, Thumb.Top, Thumb.Right, Thumb.Bottom,
    ScrollBarScale(5, CurrentPPI), ScrollBarScale(5, CurrentPPI));
end;

procedure TVerticalScrollBarControl.SetBackgroundColor(Value: TColor);
begin
  if FBackgroundColor = Value then
    Exit;
  FBackgroundColor := Value;
  Invalidate;
end;

procedure TVerticalScrollBarControl.SetMaximum(Value: Integer);
begin
  Value := Max(Value, 0);
  if FMaximum = Value then
    Exit;
  FMaximum := Value;
  SetPosition(FPosition);
  Invalidate;
end;

procedure TVerticalScrollBarControl.SetPageSize(Value: Integer);
begin
  Value := Max(Value, 1);
  if FPageSize = Value then
    Exit;
  FPageSize := Value;
  Invalidate;
end;

procedure TVerticalScrollBarControl.SetPosition(Value: Integer);
begin
  Value := EnsureRange(Value, 0, FMaximum);
  if FPosition = Value then
    Exit;
  FPosition := Value;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TVerticalScrollBarControl.SetRange(AMaximum,
  APageSize: Integer);
begin
  FMaximum := Max(AMaximum, 0);
  FPageSize := Max(APageSize, 1);
  SetPosition(FPosition);
  Invalidate;
end;

procedure TVerticalScrollBarControl.SetThumbBorderColor(Value: TColor);
begin
  if FThumbBorderColor = Value then
    Exit;
  FThumbBorderColor := Value;
  Invalidate;
end;

procedure TVerticalScrollBarControl.SetThumbColor(Value: TColor);
begin
  if FThumbColor = Value then
    Exit;
  FThumbColor := Value;
  Invalidate;
end;

procedure TVerticalScrollBarControl.SetTrackColor(Value: TColor);
begin
  if FTrackColor = Value then
    Exit;
  FTrackColor := Value;
  Invalidate;
end;

function TVerticalScrollBarControl.ThumbRect: TRect;
var
  ThumbHeight: Integer;
  ThumbTop: Integer;
  Track: TRect;
  Travel: Integer;
begin
  Track := TrackRect;
  if FMaximum <= 0 then
    Exit(Track);
  ThumbHeight := Max(ScrollBarScale(MINIMUM_THUMB_HEIGHT, CurrentPPI),
    MulDiv(Track.Height, FPageSize, FPageSize + FMaximum));
  ThumbHeight := Min(ThumbHeight, Track.Height);
  Travel := Max(Track.Height - ThumbHeight, 0);
  if Travel = 0 then
    ThumbTop := Track.Top
  else
    ThumbTop := Track.Top + MulDiv(FPosition, Travel, FMaximum);
  Result := Rect(Track.Left, ThumbTop, Track.Right,
    ThumbTop + ThumbHeight);
end;

function TVerticalScrollBarControl.ThumbTopToPosition(
  ThumbTop: Integer): Integer;
var
  Thumb: TRect;
  Track: TRect;
  Travel: Integer;
begin
  Track := TrackRect;
  Thumb := ThumbRect;
  Travel := Track.Height - Thumb.Height;
  if (Travel <= 0) or (FMaximum <= 0) then
    Exit(0);
  ThumbTop := EnsureRange(ThumbTop, Track.Top, Track.Top + Travel);
  Result := MulDiv(ThumbTop - Track.Top, FMaximum, Travel);
end;

function TVerticalScrollBarControl.TrackRect: TRect;
var
  Margin: Integer;
begin
  Margin := ScrollBarScale(TRACK_MARGIN, CurrentPPI);
  Result := Rect(Margin, Margin, Max(ClientWidth - Margin, Margin),
    Max(ClientHeight - Margin, Margin));
end;

end.

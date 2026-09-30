// Selection-only combo: native navigation, common dark text/chrome and DPI metrics.
unit DarkComboBox;
interface
uses System.Classes, System.Types, Vcl.StdCtrls, Vcl.Controls, Winapi.Messages;
type
  TDarkComboBox = class(TComboBox)
  private
    FUpdatingMetrics: Boolean;
    procedure UpdateMetrics;
    procedure PaintClosed;
    procedure WMPaint(var Message: TWMPaint); message WM_PAINT;
    procedure CMFontChanged(var Message: TMessage); message CM_FONTCHANGED;
    procedure CMEnabledChanged(var Message: TMessage); message CM_ENABLEDCHANGED;
  protected
    procedure CreateWnd; override;
    procedure ChangeScale(M,D: Integer; isDpiChange: Boolean); override;
    procedure DrawItem(Index: Integer; Rect: TRect; State: TOwnerDrawState); override;
    procedure Change; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;
implementation
uses Winapi.Windows, Winapi.UxTheme, Vcl.Graphics, System.Math;
constructor TDarkComboBox.Create(AOwner: TComponent);
begin
  inherited;
  Style := csOwnerDrawFixed;
  StyleElements := [];
  ParentColor := False; Color := $00303030;
  ParentFont := False; Font.Name := 'Segoe UI'; Font.Size := 10; Font.Color := $00EEEEEE;
  DropDownCount := 8; Width := 200;
end;
procedure TDarkComboBox.CreateWnd;
begin
  inherited;
  SetWindowTheme(Handle,'','');
  UpdateMetrics;
end;
procedure TDarkComboBox.UpdateMetrics;
var DC: HDC; Old: HGDIOBJ; Metric: TTextMetric; H: Integer;
begin
  if FUpdatingMetrics or not HandleAllocated then Exit;
  FUpdatingMetrics := True;
  try
    DC := GetDC(Handle);
    try
      Old := SelectObject(DC,Font.Handle);
      try GetTextMetrics(DC,Metric); finally SelectObject(DC,Old); end;
    finally ReleaseDC(Handle,DC); end;
    H := Max(MulDiv(24,CurrentPPI,96),Metric.tmHeight+MulDiv(8,CurrentPPI,96));
    ItemHeight := H;
    SendMessage(Handle,CB_SETITEMHEIGHT,WPARAM(-1),H);
    Invalidate;
  finally FUpdatingMetrics := False; end;
end;
procedure TDarkComboBox.CMFontChanged(var Message: TMessage);
begin inherited; UpdateMetrics; end;
procedure TDarkComboBox.CMEnabledChanged(var Message: TMessage);
begin inherited; Invalidate; end;
procedure TDarkComboBox.ChangeScale(M,D: Integer; isDpiChange: Boolean);
begin inherited; UpdateMetrics; end;
procedure TDarkComboBox.Change;
begin inherited; Invalidate; end;
procedure TDarkComboBox.DrawItem(Index: Integer; Rect: TRect; State: TOwnerDrawState);
var TextRect: TRect; S: string; OldFont: HGDIOBJ;
begin
  Canvas.Font.Assign(Font); Canvas.Brush.Style := bsSolid;
  if odSelected in State then Canvas.Brush.Color := $00613F20
  else Canvas.Brush.Color := Color;
  Canvas.Font.Color := $00EEEEEE;
  if not Enabled or (odDisabled in State) then Canvas.Font.Color := $00808080;
  Canvas.FillRect(Rect);
  if (Index>=0) and (Index<Items.Count) then S := Items[Index] else S := '';
  TextRect := Rect; InflateRect(TextRect,-MulDiv(8,CurrentPPI,96),0);
  SetBkMode(Canvas.Handle,TRANSPARENT);
  OldFont := SelectObject(Canvas.Handle,Canvas.Font.Handle);
  try
    SetTextColor(Canvas.Handle,ColorToRGB(Canvas.Font.Color));
    DrawText(Canvas.Handle,PChar(S),Length(S),TextRect,
      DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
  finally SelectObject(Canvas.Handle,OldFont); end;
  if odFocused in State then Canvas.DrawFocusRect(Rect);
end;
procedure TDarkComboBox.PaintClosed;
var C: TCanvas; DC: HDC; R,TextRect: TRect; X,Y,A: Integer;
    S: string; OldFont: HGDIOBJ;
begin
  DC := GetDC(Handle); C := TCanvas.Create;
  try
    C.Handle := DC; R := ClientRect;
    C.Brush.Color := Color; C.FillRect(R);
    C.Pen.Color := $00606060;
    if Focused then C.Pen.Color := $00D69C4A;
    C.Brush.Style := bsClear; C.Rectangle(R);
    C.Font.Assign(Font); C.Font.Color := $00EEEEEE;
    if not Enabled then C.Font.Color := $00808080;
    TextRect := R; InflateRect(TextRect,-MulDiv(8,CurrentPPI,96),0);
    Dec(TextRect.Right,MulDiv(24,CurrentPPI,96));
    if ItemIndex>=0 then S := Items[ItemIndex] else S := TextHint;
    SetBkMode(DC,TRANSPARENT);
    OldFont := SelectObject(DC,C.Font.Handle);
    try
      SetTextColor(DC,ColorToRGB(C.Font.Color));
      DrawText(DC,PChar(S),Length(S),TextRect,
        DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
    finally SelectObject(DC,OldFont); end;
    X := R.Right-MulDiv(14,CurrentPPI,96); Y := R.Height div 2;
    A := Max(2,MulDiv(4,CurrentPPI,96));
    C.Pen.Color := C.Font.Color;
    C.MoveTo(X-A,Y-2); C.LineTo(X,Y+2); C.LineTo(X+A,Y-2);
  finally C.Handle := 0; C.Free; ReleaseDC(Handle,DC); end;
end;
procedure TDarkComboBox.WMPaint(var Message: TWMPaint);
begin inherited; PaintClosed; end;
end.

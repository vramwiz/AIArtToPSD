// 横型トラックバーの状態を受け取り、VCL Canvasへ外観だけを描画する。
unit HorizontalTrackBarRenderer;

interface

uses
  System.Types,
  Vcl.Graphics;

type
  THorizontalTrackBarRenderState = record
    BackgroundColor: TColor;  // コントロール全面の背景色。
    ChannelColor: TColor;     // 未選択範囲のチャンネル色。
    ClientRect: TRect;        // 背景とフォーカス枠を描くクライアント領域。
    DisabledColor: TColor;    // 無効時のチャンネル、つまみ、目盛り色。
    Enabled: Boolean;         // 有効時の配色を使うかを示す。
    FillColor: TColor;        // 最小値から現在位置までの選択範囲色。
    Focused: Boolean;         // キーボードフォーカス枠を表示するかを示す。
    Frequency: Integer;       // 目盛り同士の値間隔。1未満は描画時に1として扱う。
    Maximum: Integer;         // 値範囲の上限。
    Minimum: Integer;         // 値範囲の下限。
    PPI: Integer;             // 寸法を96 DPI基準から拡大する描画先DPI。
    ShowTicks: Boolean;       // 目盛りを描画するかを示す。
    ThumbBorderColor: TColor; // つまみの輪郭色。
    ThumbColor: TColor;       // 有効時のつまみ内部色。
    ThumbX: Integer;          // クライアント座標でのつまみ中心X。
    TickColor: TColor;        // 有効時の目盛り色。
    TrackRect: TRect;         // チャンネルの左右範囲と中心Yを表す領域。
  end;

// Stateだけを参照して描画し、CanvasやStateの所有権と状態を変更しない。
procedure DrawHorizontalTrackBar(Canvas: TCanvas;
  const State: THorizontalTrackBarRenderState);

implementation

uses
  System.Math,
  Winapi.Windows;

function Scale(Value, PPI: Integer): Integer;
begin
  Result := MulDiv(Value, PPI, 96);
end;

procedure DrawHorizontalTrackBar(Canvas: TCanvas;
  const State: THorizontalTrackBarRenderState);
var
  ActiveColor: TColor;
  ChannelRect, FocusRect, ThumbRect: TRect;
  ChannelY, FrequencyValue, ThumbRadius, Tick, TickX: Integer;
begin
  Canvas.Brush.Color := State.BackgroundColor;
  Canvas.FillRect(State.ClientRect);
  ChannelY := State.TrackRect.Top;
  ChannelRect := Rect(State.TrackRect.Left, ChannelY - Scale(2, State.PPI),
    State.TrackRect.Right, ChannelY + Scale(2, State.PPI) + 1);
  Canvas.Brush.Color := State.ChannelColor;
  Canvas.Pen.Style := psClear;
  Canvas.Rectangle(ChannelRect);

  if State.Enabled then ActiveColor := State.FillColor
  else ActiveColor := State.DisabledColor;
  Canvas.Brush.Color := ActiveColor;
  Canvas.Rectangle(Rect(ChannelRect.Left, ChannelRect.Top, State.ThumbX,
    ChannelRect.Bottom));

  if State.ShowTicks then
  begin
    FrequencyValue := Max(State.Frequency, 1);
    Tick := State.Minimum;
    Canvas.Pen.Style := psSolid;
    Canvas.Pen.Color := State.TickColor;
    while Tick <= State.Maximum do
    begin
      if State.Maximum > State.Minimum then
        TickX := State.TrackRect.Left + MulDiv(Tick - State.Minimum,
          State.TrackRect.Width, State.Maximum - State.Minimum)
      else
        TickX := State.TrackRect.Left;
      Canvas.MoveTo(TickX, ChannelY + Scale(7, State.PPI));
      Canvas.LineTo(TickX, ChannelY + Scale(11, State.PPI));
      if Tick > State.Maximum - FrequencyValue then Break;
      Inc(Tick, FrequencyValue);
    end;
  end;

  ThumbRadius := Scale(6, State.PPI);
  ThumbRect := Rect(State.ThumbX - ThumbRadius, ChannelY - ThumbRadius,
    State.ThumbX + ThumbRadius + 1, ChannelY + ThumbRadius + 1);
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := Max(Scale(2, State.PPI), 1);
  if State.Enabled then
  begin
    Canvas.Brush.Color := State.ThumbColor;
    Canvas.Pen.Color := State.ThumbBorderColor;
  end
  else
  begin
    Canvas.Brush.Color := State.BackgroundColor;
    Canvas.Pen.Color := State.DisabledColor;
  end;
  Canvas.Ellipse(ThumbRect);
  Canvas.Pen.Width := 1;

  if State.Focused and State.Enabled then
  begin
    FocusRect := State.ClientRect;
    InflateRect(FocusRect, -1, -1);
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := State.FillColor;
    Canvas.DrawFocusRect(FocusRect);
  end;
end;

end.

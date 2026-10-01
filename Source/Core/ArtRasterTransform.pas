unit ArtRasterTransform;

interface

uses System.SysUtils, ArtDocument;

// Rectangular preparation/placement only; no semantic segmentation or inpainting.
function ResampleRgba(const Pixels: TBytes; Width,Height: Integer;
  const Source: TArtBounds; DestWidth,DestHeight: Integer): TBytes;
function AlphaBounds(const Pixels: TBytes; Width,Height: Integer): TArtBounds;
function MapSquareBounds(const Local,CanvasSquare: TArtBounds; WorkingSize: Integer): TArtBounds;

implementation

uses System.Math;

type
  TTap = record Index: Integer; Weight: Double; end;
  TWeights = TArray<TArray<TTap>>;

function Weights(Start,SourceSize,DestSize: Integer): TWeights;
var D,I,First,Last,N: Integer; Scale,A,B,P,W: Double;
begin
  Result := nil; SetLength(Result,DestSize); Scale := SourceSize/DestSize;
  for D := 0 to DestSize-1 do begin
    if Scale>=1 then begin
      A := Start+D*Scale; B := Start+(D+1)*Scale;
      First := Floor(A); Last := Ceil(B)-1;
      SetLength(Result[D],Last-First+1); N := 0;
      for I := First to Last do begin
        W := (Min(B,I+1.0)-Max(A,I*1.0))/Scale;
        Result[D][N].Index := I; Result[D][N].Weight := W; Inc(N);
      end;
    end else begin
      P := Start+(D+0.5)*Scale-0.5; First := Floor(P); W := P-First;
      SetLength(Result[D],2);
      Result[D][0].Index := EnsureRange(First,Start,Start+SourceSize-1);
      Result[D][0].Weight := 1-W;
      Result[D][1].Index := EnsureRange(First+1,Start,Start+SourceSize-1);
      Result[D][1].Weight := W;
    end;
  end;
end;

function ResampleRgba(const Pixels: TBytes; Width,Height: Integer;
  const Source: TArtBounds; DestWidth,DestHeight: Integer): TBytes;
var WX,WY: TWeights; Row: TArray<Double>; X,Y,SX,SY,P,Q,C: Integer;
    TX,TY: TTap; W,A: Double;
begin
  if (Width<1) or (Height<1) or (Length(Pixels)<>PixelByteCount(Width,Height,4)) then
    raise EArtFormat.Create('Invalid source raster');
  if (Source.Width<1) or (Source.Height<1) or (DestWidth<1) or (DestHeight<1) then
    raise EArtFormat.Create('Empty resize rectangle');
  PixelByteCount(Source.Width,Source.Height,4);
  if (Source.Left < -30000) or (Source.Top < -30000) or
    (Source.Right>60000) or (Source.Bottom>60000) then raise EArtFormat.Create('Resize rectangle limit');
  SetLength(Result,PixelByteCount(DestWidth,DestHeight,4));
  // Exact copy at 1:1, including original alpha and hidden RGB; outside is transparent.
  if (Source.Width=DestWidth) and (Source.Height=DestHeight) then begin
    for Y := 0 to DestHeight-1 do begin
      SY := Source.Top+Y; if (SY<0) or (SY>=Height) then Continue;
      for X := 0 to DestWidth-1 do begin
        SX := Source.Left+X; if (SX<0) or (SX>=Width) then Continue;
        Move(Pixels[(SY*Width+SX)*4],Result[(Y*DestWidth+X)*4],4);
      end;
    end;
    Exit;
  end;
  WX := Weights(Source.Left,Source.Width,DestWidth);
  WY := Weights(Source.Top,Source.Height,DestHeight);
  SetLength(Row,Width*4);
  // Separable area reduction / bilinear enlargement in premultiplied alpha.
  // Transparent RGB never contributes color to a visible output pixel.
  for Y := 0 to DestHeight-1 do begin
    FillChar(Row[0],Length(Row)*SizeOf(Double),0);
    for TY in WY[Y] do begin
      SY := TY.Index; if (SY<0) or (SY>=Height) then Continue;
      for SX := Max(0,Source.Left) to Min(Width,Source.Right)-1 do begin
        P := (SY*Width+SX)*4; Q := SX*4;
        A := Pixels[P+3]*TY.Weight;
        for C := 0 to 2 do Row[Q+C] := Row[Q+C]+Pixels[P+C]*A;
        Row[Q+3] := Row[Q+3]+A;
      end;
    end;
    for X := 0 to DestWidth-1 do begin
      var Values: array[0..3] of Double;
      FillChar(Values,SizeOf(Values),0);
      for TX in WX[X] do begin
        SX := TX.Index; if (SX<0) or (SX>=Width) then Continue;
        W := TX.Weight; Q := SX*4;
        for C := 0 to 3 do Values[C] := Values[C]+Row[Q+C]*W;
      end;
      P := (Y*DestWidth+X)*4;
      Result[P+3] := EnsureRange(Round(Values[3]),0,255);
      if Result[P+3]>0 then
        for C := 0 to 2 do Result[P+C] := EnsureRange(Round(Values[C]/Values[3]),0,255);
    end;
  end;
end;

function AlphaBounds(const Pixels: TBytes; Width,Height: Integer): TArtBounds;
var X,Y: Integer;
begin
  if Length(Pixels)<>PixelByteCount(Width,Height,4) then raise EArtFormat.Create('Invalid alpha raster');
  Result := TArtBounds.Create(Width,Height,0,0);
  for Y := 0 to Height-1 do for X := 0 to Width-1 do
    if Pixels[(Y*Width+X)*4+3]<>0 then begin
      Result.Left := Min(Result.Left,X); Result.Top := Min(Result.Top,Y);
      Result.Right := Max(Result.Right,X+1); Result.Bottom := Max(Result.Bottom,Y+1);
    end;
  if Result.Right=0 then Result := TArtBounds.Create(0,0,0,0);
end;

function MapSquareBounds(const Local,CanvasSquare: TArtBounds; WorkingSize: Integer): TArtBounds;
  function Edge(V,Origin: Integer): Integer;
  begin
    // Shared edge rounding keeps adjacent workspace parts aligned.
    Result := Origin+Floor(V*(CanvasSquare.Width/WorkingSize)+0.5);
  end;
begin
  if (WorkingSize<1) or (WorkingSize>4096) or (CanvasSquare.Width<1) or
    (CanvasSquare.Width<>CanvasSquare.Height) or (Local.Width<1) or (Local.Height<1) then
    raise EArtFormat.Create('Invalid square coordinate frame');
  if (Local.Left<0) or (Local.Top<0) or (Local.Right>WorkingSize) or (Local.Bottom>WorkingSize) then
    raise EArtFormat.Create('Workspace bounds outside square');
  Result := TArtBounds.Create(Edge(Local.Left,CanvasSquare.Left),Edge(Local.Top,CanvasSquare.Top),
    Edge(Local.Right,CanvasSquare.Left),Edge(Local.Bottom,CanvasSquare.Top));
  if (Result.Width<1) or (Result.Height<1) then raise EArtFormat.Create('Mapped part is smaller than one pixel');
end;

end.

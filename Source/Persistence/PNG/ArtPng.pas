unit ArtPng;
interface
uses System.SysUtils;
type TArtPngData = record Width,Height: Integer; Pixels: TBytes; end;
function ReadPng(const FileName: string): TArtPngData;
procedure WriteRgbaPng(const FileName: string; Width,Height: Integer; const Pixels: TBytes);
implementation
uses System.Classes, Winapi.Windows, Vcl.Imaging.pngimage, ArtDocument;
function ReadPng(const FileName: string): TArtPngData;
var Png: TPngImage; Stream: TFileStream; Header: array[0..23] of Byte;
    X,Y,P,Bits,Index,Color: Integer; Palette: TChunkPLTE; Entry: TRGBQuad; Alpha,Row: PByte; TRNS: TChunktRNS;
  function BE(Offset: Integer): Cardinal;
  begin Result := Cardinal(Header[Offset]) shl 24 or Cardinal(Header[Offset+1]) shl 16 or Cardinal(Header[Offset+2]) shl 8 or Header[Offset+3]; end;
begin
  Stream := TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size<24) or (Stream.Size>ART_MAX_BYTES) then raise EArtFormat.Create('PNGサイズが範囲外です。');
    Stream.ReadBuffer(Header,24);
    if (BE(0)<>$89504E47) or (BE(4)<>$0D0A1A0A) or (BE(8)<>13) or (BE(12)<>$49484452) then raise EArtFormat.Create('PNG形式ではありません。');
    if (BE(16)=0) or (BE(20)=0) or (BE(16)>30000) or (BE(20)>30000) then raise EArtFormat.Create('PNG寸法が範囲外です。');
    Result.Width := BE(16); Result.Height := BE(20);
    SetLength(Result.Pixels,PixelByteCount(Result.Width,Result.Height,4));
    Png := TPngImage.Create;
    try
      Stream.Position := 0; Png.LoadFromStream(Stream);
      if Png.Header.BitDepth=16 then raise EArtFormat.Create('16bit PNGは未対応です。8bit PNGへ変換してください。');
      if (Png.Header.ColorType=COLOR_GRAYSCALE) and (Png.Header.BitDepth=2) then raise EArtFormat.Create('2bitグレースケールPNGは未対応です。8bit PNGへ変換してください。');
      TRNS := TChunktRNS(Png.Chunks.FindChunk(TChunktRNS));
      Palette := TChunkPLTE(Png.Chunks.FindChunk(TChunkPLTE));
      Bits := Png.Header.BitDepth; if Bits=2 then Bits := 4;
      for Y := 0 to Result.Height-1 do begin
        Alpha := PByte(Png.AlphaScanline[Y]); Row := Png.Scanline[Y];
        for X := 0 to Result.Width-1 do begin
          P := (Y*Result.Width+X)*4; Color := Png.Pixels[X,Y];
          if Palette<>nil then begin
            Index := (Row[X*Bits div 8] shr (8-Bits-(X*Bits mod 8))) and ((1 shl Bits)-1);
            Entry := Palette.Item[Index]; Color := RGB(Entry.rgbRed,Entry.rgbGreen,Entry.rgbBlue);
          end;
          Result.Pixels[P] := GetRValue(Color); Result.Pixels[P+1] := GetGValue(Color); Result.Pixels[P+2] := GetBValue(Color);
          Result.Pixels[P+3] := 255;
          if Alpha<>nil then Result.Pixels[P+3] := Alpha[X]
          else if (TRNS<>nil) and (Png.Header.ColorType=COLOR_PALETTE) then begin
            Index := (Row[X*Bits div 8] shr (8-Bits-(X*Bits mod 8))) and ((1 shl Bits)-1);
            Result.Pixels[P+3] := TRNS.PaletteValues[Index];
          end else if (TRNS<>nil) and (Color=Integer(Png.TransparentColor)) then Result.Pixels[P+3] := 0;
        end;
      end;
    finally Png.Free; end;
  finally Stream.Free; end;
end;
procedure WriteRgbaPng(const FileName: string; Width,Height: Integer; const Pixels: TBytes);
var Png: TPngImage; X,Y,P: Integer; Row,Alpha: PByte;
begin
  if (Width<1) or (Height<1) or (Length(Pixels)<>PixelByteCount(Width,Height,4)) then raise EArtFormat.Create('Invalid PNG export image');
  Png := TPngImage.CreateBlank(COLOR_RGBALPHA,8,Width,Height);
  try
    for Y := 0 to Height-1 do begin
      Row := Png.Scanline[Y]; Alpha := PByte(Png.AlphaScanline[Y]);
      for X := 0 to Width-1 do begin
        P := (Y*Width+X)*4; Row[X*3] := Pixels[P+2]; Row[X*3+1] := Pixels[P+1]; Row[X*3+2] := Pixels[P]; Alpha[X] := Pixels[P+3];
      end;
    end;
    Png.SaveToFile(FileName);
  finally Png.Free; end;
end;
end.

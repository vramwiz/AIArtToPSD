program VisibilitySmoke;
{$APPTYPE CONSOLE}
uses System.JSON, System.Math, System.Types, System.SysUtils, System.Classes, System.IOUtils, Vcl.Controls, Vcl.Forms, Vcl.Graphics, Vcl.Themes, Vcl.Styles, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Menus,
  Winapi.Windows, Winapi.Messages,
  HorizontalTrackBarRenderer in '..\Source\Lib\UI\HorizontalTrackBar\HorizontalTrackBarRenderer.pas',
  HorizontalTrackBarControl in '..\Source\Lib\UI\HorizontalTrackBar\HorizontalTrackBarControl.pas',
  ArtFileHistory in '..\Source\Shell\ArtFileHistory.pas',
  VerticalScrollBarControl in '..\Source\Lib\UI\VerticalScrollBar\VerticalScrollBarControl.pas',
  PipeServerTThread in '..\Source\Lib\Pipe\PipeServerTThread.pas',
  ArtUndo in '..\Source\Editor\ArtUndo.pas',
  ArtPipeBridge in '..\Source\Integrations\Pipe\ArtPipeBridge.pas',
  ArtPipeProtocol in '..\Source\Integrations\Pipe\ArtPipeProtocol.pas',
  ArtExchange in '..\Source\Integrations\AIExchange\ArtExchange.pas',
  ArtParts in '..\Source\Core\ArtParts.pas',
  DarkComboBox in '..\Source\Lib\UI\DarkComboBox\DarkComboBox.pas',
  ArtLayerName in '..\Source\Core\ArtLayerName.pas',
  ArtLayerList in '..\Source\Shell\ArtLayerList.pas',
  ArtDocument in '..\Source\Core\ArtDocument.pas',
  ArtPng in '..\Source\Persistence\PNG\ArtPng.pas',
  ArtPsd in '..\Source\Persistence\PSD\ArtPsd.pas',
  AIArtToPSDMainForm in '..\Source\Shell\AIArtToPSDMainForm.pas';
{$R ..\AIArtToPSD.res}
type TLayerListAccess = class(TArtLayerList);
var F: TMainForm; Source: TArtPngData; Pixels: TBytes;
    Request,ResultJson,Op: TJSONObject; Operations: TJSONArray;
    Output,JobPath: string; Count,VisibleCount: Integer;
procedure Check(Value: Boolean; const Msg: string);
begin Inc(Count); if not Value then raise Exception.Create(Msg); end;
procedure ClickEye(Layer: TArtLayer);
var Index: Integer;
begin
  F.LayerList.Selected := Layer; F.LayerList.RevealSelected;
  Index := 0;
  while (Index<F.LayerList.RowCount) and (F.LayerList.LayerAt(Index)<>Layer) do Inc(Index);
  Check(Index<F.LayerList.RowCount,'Layer row missing');
  TLayerListAccess(F.LayerList).MouseDown(mbLeft,[],18,8+Index*88+37-F.LayerList.ScrollBar.Position);
end;
function AlphaCount(const Data: TBytes): Integer;
begin Result := 0; for var P := 0 to Length(Data) div 4-1 do if Data[P*4+3]<>0 then Inc(Result); end;
function MatchesSource(const Data: TBytes): Boolean;
begin
  Result := Length(Data)=Length(Source.Pixels); if not Result then Exit;
  for var P := 0 to Length(Data) div 4-1 do begin
    if Data[P*4+3]<>Source.Pixels[P*4+3] then Exit(False);
    if Source.Pixels[P*4+3]<>0 then
      for var C := 0 to 2 do if Data[P*4+C]<>Source.Pixels[P*4+C] then Exit(False);
  end;
end;
procedure CheckViewPermissions;
begin
  Check(not F.LayerList.EditEnabled,'Read-only list enabled name/opacity editing');
  Check(F.LayerList.VisibilityEnabled,'Read-only list disabled eye icons');
  F.LayerList.BeginRename;
  Check(not F.LayerList.NameEditor.Visible,'Read-only list opened name editor');
  Check(F.LayerList.SliderAt(0)=nil,'Read-only list displayed opacity slider');
end;
begin
  try
    if ParamCount<>3 then raise Exception.Create('Usage: VisibilitySmoke OUTPUT_DIRECTORY FACE.psd SOURCE.png');
    Output := TPath.GetFullPath(ParamStr(1)); ForceDirectories(Output);
    Source := ReadPng(ParamStr(3));
    Application.Initialize; Check(TStyleManager.TrySetStyle('Windows Modern Dark'),'Style missing');
    F := TMainForm.CreateWithHistory(nil,TPath.Combine(Output,'history'));
    try
      F.Show; Application.ProcessMessages;
      F.NewFromPng(ParamStr(3)); CheckViewPermissions;
      ClickEye(F.Document.Roots[0]);
      Check(not F.Document.Roots[0].Visible,'PNG eye click failed to hide');
      Check(AlphaCount(RenderPsdLayers(F.Document))=0,'Hidden PNG still rendered');
      Check(F.CanUndo,'Eye click was not undoable');
      F.Undo; Check(F.Document.Roots[0].Visible and MatchesSource(RenderPsdLayers(F.Document)),'Undo failed to restore image');
      F.Redo; Check(not F.Document.Roots[0].Visible,'Redo failed to hide image');
      ClickEye(F.Document.Roots[0]); Check(MatchesSource(RenderPsdLayers(F.Document)),'Eye click failed to show image');
      F.PromptControl.Text := 'Visibility regression after AI import';
      JobPath := F.ExportAiJob(F.PromptControl.Text,TPath.Combine(Output,'exchange'));
      Request := TJSONObject.ParseJSONValue(TFile.ReadAllText(TPath.Combine(JobPath,'request.json'))) as TJSONObject;
      ResultJson := TJSONObject.Create;
      try
        for var Key in ['schemaVersion','jobId','requestId','documentId','ifRevision'] do
          ResultJson.AddPair(Key,Request.GetValue(Key).Clone as TJSONValue);
        ResultJson.AddPair('assets',TJSONArray.Create); Operations := TJSONArray.Create; ResultJson.AddPair('operations',Operations);
        Op := TJSONObject.Create; Operations.AddElement(Op); Op.AddPair('op','rename_layer');
        Op.AddPair('layerId',F.Document.Roots[0].Id); Op.AddPair('name','取込後');
        TFile.WriteAllText(TPath.Combine(JobPath,'result.json'),ResultJson.ToJSON,TEncoding.UTF8);
        F.ImportAiResult(TPath.Combine(JobPath,'result.json')); CheckViewPermissions;
        ClickEye(F.Document.Roots[0]); Check(AlphaCount(RenderPsdLayers(F.Document))=0,'Post-import eye click failed');
      finally ResultJson.Free; Request.Free; end;
      F.OpenPsdFile(ParamStr(2)); CheckViewPermissions;
      Check(F.Document.Roots.Count=3,'Unexpected face PSD roots');
      Check(F.Document.Roots[0].Children.Count=5,'Facial parts not grouped separately');
      Check(not F.Document.Roots[2].Visible,'Reference source is visible over separated parts');
      Check(MatchesSource(RenderPsdLayers(F.Document)),'Face PSD composite differs from source');
      ClickEye(F.Document.Roots[0]);
      Check(not F.Document.Roots[0].Visible,'Group eye click failed');
      Check(not MatchesSource(RenderPsdLayers(F.Document)),'Hidden facial group did not change composite');
      F.Undo; Check(F.Document.Roots[0].Visible,'Group undo failed');
      ClickEye(F.Document.Roots[1]);
      Check(not F.Document.Roots[1].Visible,'Scrolled remainder eye click failed');
      Pixels := RenderPsdLayers(F.Document); VisibleCount := AlphaCount(Pixels);
      Check((VisibleCount>2000) and (VisibleCount<4000),'Isolated parts include body/full image or omit eyes');
      for var P := 0 to Length(Pixels) div 4-1 do
        if Pixels[P*4+3]<>0 then
          if (P mod Source.Width<440) or (P mod Source.Width>570) or
            (P div Source.Width<135) or (P div Source.Width>230) then
            raise Exception.Create('Isolated face parts contain pixels outside face');
      Check(True,'Only facial regions visible');
      WriteRgbaPng(TPath.Combine(Output,'face_parts_only.png'),Source.Width,Source.Height,Pixels);
      for var I := 1 to F.Document.Roots[0].Children.Count-1 do ClickEye(F.Document.Roots[0].Children[I]);
      Pixels := RenderPsdLayers(F.Document);
      Check(AlphaCount(Pixels)=1278,'Isolated left eye includes other facial parts');
      WriteRgbaPng(TPath.Combine(Output,'eye_left_only.png'),Source.Width,Source.Height,Pixels);
      F.SavePsdFile(TPath.Combine(Output,'visibility_saved.psd')); CheckViewPermissions;
      ClickEye(F.Document.Roots[0].Children[0]);
      Check(AlphaCount(RenderPsdLayers(F.Document))=0,'Saved PSD eye click failed');
      Check(F.Modified and F.CanUndo,'Saved visibility change not recorded');
      F.Undo; Check(AlphaCount(RenderPsdLayers(F.Document))=1278,'Saved PSD undo failed');
    finally F.Free; end;
    Writeln('PASS: ',Count,' visibility assertions; isolated face pixels=',VisibleCount);
  except on E: Exception do begin Writeln(E.ClassName,': ',E.Message); Halt(1); end; end;
end.

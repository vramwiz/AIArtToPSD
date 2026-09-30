program ExchangeUiSmoke;
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
var F: TMainForm; Request,Response,O: TJSONObject; Ops: TJSONArray;
  Output,JobPath,Id,OldId: string; Pixels: TBytes; Count: Integer; Before: TArtDocument;
  Failed: Boolean; B: Vcl.Graphics.TBitmap;
procedure Check(Value: Boolean; const Msg: string);
begin Inc(Count); if not Value then raise Exception.Create(Msg); end;
procedure StartJob;
begin
  JobPath := F.ExportAiJob(F.PromptControl.Text,TPath.Combine(Output,'exchange'));
  Request := TJSONObject.ParseJSONValue(TFile.ReadAllText(TPath.Combine(JobPath,'request.json'))) as TJSONObject;
  Response := TJSONObject.Create;
  for var Key in ['schemaVersion','jobId','requestId','documentId','ifRevision'] do
    Response.AddPair(Key,Request.GetValue(Key).Clone as TJSONValue);
  Response.AddPair('assets',TJSONArray.Create); Ops := TJSONArray.Create; Response.AddPair('operations',Ops);
end;
procedure Rename(const LayerId,Name: string);
begin
  O := TJSONObject.Create; Ops.AddElement(O); O.AddPair('op','rename_layer'); O.AddPair('layerId',LayerId); O.AddPair('name',Name);
end;
procedure ResultFile;
begin TFile.WriteAllText(TPath.Combine(JobPath,'result.json'),Response.ToJSON,TEncoding.UTF8); end;
procedure EndJob;
begin Request.Free; Response.Free; end;
begin
  try
    if ParamCount<>1 then raise Exception.Create('Usage: ExchangeUiSmoke OUTPUT_DIRECTORY');
    Output := TPath.GetFullPath(ParamStr(1)); ForceDirectories(Output);
    SetLength(Pixels,64*64*4); for var I := 0 to 64*64-1 do begin
      Pixels[I*4] := 200; Pixels[I*4+1] := 100; Pixels[I*4+2] := 60; Pixels[I*4+3] := 255;
    end;
    WriteRgbaPng(TPath.Combine(Output,'source.png'),64,64,Pixels);
    Application.Initialize; Check(TStyleManager.TrySetStyle('Windows Modern Dark'),'Style missing');
    F := TMainForm.CreateWithHistory(nil,TPath.Combine(Output,'history'));
    try
      Failed := False;
      try F.ExportAiJob('test',Output); except on EArtFormat do Failed := True; end;
      Check(Failed,'Empty document accepted');
      F.NewFromPng(TPath.Combine(Output,'source.png'));
      F.LayerList.Selected := F.Document.Roots[0]; Id := F.LayerList.Selected.Id;
      F.PromptControl.Text := '表情を作成';
      StartJob;
      try
        Check(not FileExists(TPath.Combine(JobPath,'request.json.tmp')),'Request not finalized');
        Check(FileExists(TPath.Combine(JobPath,'instructions.txt')),'Instructions missing');
        Rename(Id,'*差分:flipx'); ResultFile; F.ImportAiResult(TPath.Combine(JobPath,'result.json'));
        Check(F.AiJobPathControl.Text=JobPath,'Import lost job directory'); Check(F.Modified,'Import not marked dirty'); Check(F.LayerList.Selected.Id=Id,'Selection lost');
        Check(F.Document.Roots[0].Name='*差分:flipx','UI result missing');
        Before := F.Document; F.ImportAiResult(TPath.Combine(JobPath,'result.json'));
        Check(F.Document=Before,'Duplicate replaced document'); Check(F.AiJobPathControl.Text=JobPath,'Repeat lost job directory');
      finally EndJob; end;
      StartJob;
      try
        Before := F.Document; Rename(Id,'途中変更'); Rename('missing','invalid'); ResultFile;
        Failed := False; try F.ImportAiResult(TPath.Combine(JobPath,'result.json')); except on EArtFormat do Failed := True; end;
        Check(Failed,'Invalid UI batch accepted'); Check(F.Document=Before,'Failure replaced document');
        Check(F.Document.Roots[0].Name='*差分:flipx','Failure changed name'); Check(F.LayerList.Selected.Id=Id,'Failure lost selection');
      finally EndJob; end;
      F.SavePsdFile(TPath.Combine(Output,'saved.psd'));
      Check(not DirectoryExists(F.AiJobPathControl.Text),'Save retained obsolete job path'); Check(not F.Modified,'Save left dirty state'); Check(F.CanEdit,'Saved document not editable');
      Id := F.Document.Roots[0].Id;
      StartJob;
      try
        Rename(Id,'保存後の変更'); ResultFile; F.ImportAiResult(TPath.Combine(JobPath,'result.json'));
        Check(F.Modified and (F.Document.Roots[0].Name='保存後の変更'),'Post-save import failed');
      finally EndJob; end;
      StartJob;
      try
        Rename(Id,'古い結果'); ResultFile; F.MoveSelectedLayer(1,1); Before := F.Document;
        Failed := False; try F.ImportAiResult(TPath.Combine(JobPath,'result.json')); except on EArtFormat do Failed := True; end;
        Check(Failed and (F.Document=Before),'Edited document accepted stale result');
      finally EndJob; end;
      F.SavePsdFile(TPath.Combine(Output,'saved_again.psd'));
      OldId := F.Document.SessionId;
      StartJob;
      try
        Rename(F.Document.Roots[0].Id,'別文書の結果'); ResultFile;
        F.NewFromPng(TPath.Combine(Output,'source.png')); Before := F.Document;
        Check(F.Document.SessionId<>OldId,'New document retained identity'); Check(not DirectoryExists(F.AiJobPathControl.Text),'New document retained obsolete job path');
        Failed := False; try F.ImportAiResult(TPath.Combine(JobPath,'result.json')); except on EArtFormat do Failed := True; end;
        Check(Failed and (F.Document=Before),'Other document accepted result');
      finally EndJob; end;
      F.Show; Application.ProcessMessages;
      B := F.GetFormImage;
      try B.SaveToFile(TPath.Combine(Output,'exchange_ui.bmp')); finally B.Free; end;
      Check(F.PromptControl.Visible,'Prompt hidden');
    finally F.Free; end;
    Writeln('PASS: ',Count,' exchange UI assertions');
  except on E: Exception do begin Writeln(E.ClassName,': ',E.Message); Halt(1); end; end;
end.

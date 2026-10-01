program TransformSmoke;
{$APPTYPE CONSOLE}
uses System.JSON, System.Math, System.Types, System.SysUtils, System.Classes, System.IOUtils, Vcl.Controls, Vcl.Forms, Vcl.Graphics, Vcl.Themes, Vcl.Styles, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Menus,
  Winapi.Windows, Winapi.Messages,
  HorizontalTrackBarRenderer in '..\Source\Lib\UI\HorizontalTrackBar\HorizontalTrackBarRenderer.pas',
  HorizontalTrackBarControl in '..\Source\Lib\UI\HorizontalTrackBar\HorizontalTrackBarControl.pas',
  DropFile in '..\Source\Lib\DropFile\DropFile.pas',
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
  ArtRasterTransform in '..\Source\Core\ArtRasterTransform.pas',
  ArtPng in '..\Source\Persistence\PNG\ArtPng.pas',
  ArtPsd in '..\Source\Persistence\PSD\ArtPsd.pas',
  AIArtToPSDMainForm in '..\Source\Shell\AIArtToPSDMainForm.pas';
{$R ..\AIArtToPSD.res}
var F: TMainForm; Count: Integer; Root,Path,Id: string;
    Request,Response,Op,Workspace: TJSONObject; Ops: TJSONArray;
    P,Q: TBytes; B: TArtBounds; Before: TArtDocument; Failed: Boolean; Image: TArtPngData;

procedure Check(Value: Boolean; const MessageText: string);
begin Inc(Count); if not Value then raise Exception.Create(MessageText); end;
function J(const Text: string): TJSONObject;
begin Result := TJSONObject.ParseJSONValue(Text) as TJSONObject; end;
procedure StartJob(WithWorkspace: Boolean);
begin
  Workspace := nil;
  if WithWorkspace then begin
    Workspace := J('{"size":16,"bounds":{"left":2,"top":2,"right":6,"bottom":6}}');
    Workspace.AddPair('sourceLayerId',Id);
  end;
  try Path := F.ExportAiJob('Transform integration',Root,Workspace); finally Workspace.Free; end;
  Request := J(TFile.ReadAllText(TPath.Combine(Path,'request.json')));
  Response := TJSONObject.Create;
  for var Key in ['schemaVersion','requestId','jobId','documentId','ifRevision'] do
    Response.AddPair(Key,Request.GetValue(Key).Clone as TJSONValue);
  Response.AddPair('assets',Request.GetValue('assets').Clone as TJSONValue);
  Ops := TJSONArray.Create; Response.AddPair('operations',Ops);
end;
procedure EndJob;
begin Request.Free; Response.Free; end;
procedure Publish;
begin TFile.WriteAllText(TPath.Combine(Path,'result.json'),Response.ToJSON,TEncoding.UTF8); end;
procedure Reject(const MessageText: string);
begin
  Publish; Before := F.Document; Failed := False;
  try F.ImportAiResult(TPath.Combine(Path,'result.json')); except on EArtFormat do Failed := True; end;
  Check(Failed,MessageText); Check(F.Document=Before,'Failure changed live document'); Check(not F.Busy,'Failure left busy state');
end;
procedure CoreTests;
begin
  P := TBytes.Create(255,0,0,255,0,0,255,0);
  Q := ResampleRgba(P,2,1,TArtBounds.Create(0,0,2,1),1,1);
  Check((Q[0]=255) and (Q[1]=0) and (Q[2]=0) and (Q[3]=128),'Transparent blue contaminated reduction');
  Q := ResampleRgba(P,2,1,TArtBounds.Create(0,0,2,1),4,1);
  Check((Q[4]=255) and (Q[6]=0) and (Q[7]=191),'Premultiplied enlargement failed');
  Q := ResampleRgba(P,2,1,TArtBounds.Create(-1,0,3,1),4,1);
  Check((Q[3]=0) and (Q[4]=255) and (Q[8+2]=255) and (Q[15]=0),'Padded 1:1 copy failed');
  Q := ResampleRgba(P,2,1,TArtBounds.Create(0,0,2,1),2,1);
  Check(CompareMem(@P[0],@Q[0],Length(P)),'Identity changed hidden RGB');
  B := AlphaBounds(P,2,1); Check((B.Left=0) and (B.Right=1) and (B.Bottom=1),'Alpha trim bounds');
  B := MapSquareBounds(TArtBounds.Create(0,0,1024,1024),TArtBounds.Create(380,16,636,272),1024);
  Check((B.Left=380) and (B.Right=636) and (B.Bottom=272),'Square frame map failed');
  B := MapSquareBounds(TArtBounds.Create(512,512,768,768),TArtBounds.Create(380,16,636,272),1024);
  Check((B.Left=508) and (B.Top=144) and (B.Width=64),'Part mapping failed');
  Failed := False;
  try B := MapSquareBounds(TArtBounds.Create(-1,0,1024,1024),TArtBounds.Create(0,0,256,256),1024);
  except on EArtFormat do Failed := True; end;
  Check(Failed,'Out-of-frame mapping accepted');
end;
begin
  try
    if ParamCount<>1 then raise Exception.Create('Usage: TransformSmoke OUTPUT_DIRECTORY');
    Root := TPath.GetFullPath(ParamStr(1)); ForceDirectories(Root); CoreTests;
    Application.Initialize;
    F := TMainForm.CreateWithHistory(nil,TPath.Combine(Root,'history'));
    try
      SetLength(P,8*8*4); FillChar(P[0],Length(P),0);
      P[(4*8+3)*4] := 255; P[(4*8+3)*4+3] := 255;
      P[2] := 255; // Hidden blue must not become a fringe.
      WriteRgbaPng(TPath.Combine(Root,'source.png'),8,8,P);
      F.NewFromPng(TPath.Combine(Root,'source.png')); Id := F.Document.Roots[0].Id;
      StartJob(True);
      try
        Check(Request.GetValue('workspace')<>nil,'Workspace metadata missing');
        Image := ReadPng(TPath.Combine(Path,'input/workspace-source.png'));
        Check((Image.Width=16) and (Image.Height=16),'Workspace export size');
        Op := J('{"op":"add_layer","layerId":"mapped","name":"Mapped","parentId":"","beforeLayerId":"","visible":true,"opacity":255,"assetId":"workspace-source","coordinateSpace":"workspace","bounds":{"left":0,"top":0,"right":16,"bottom":16}}'); Ops.AddElement(Op);
        Publish; F.ImportAiResult(TPath.Combine(Path,'result.json'));
        B := F.Document.FindLayer('mapped').Bounds;
        Check((B.Left=2) and (B.Top=2) and (B.Width=4) and (B.Height=4),'Workspace placement');
        Check(F.CanUndo and F.Modified,'Transform missing undo/dirty state');
        F.Undo; Check(F.Document.FindLayer('mapped')=nil,'Undo workspace transform');
        F.Redo; Check(F.Document.FindLayer('mapped')<>nil,'Redo workspace transform');
        F.SavePsdFile(TPath.Combine(Root,'workspace.psd'));
        Check((F.Document.Roots[1].Bounds.Left=2) and (F.Document.Roots[1].Bounds.Width=4),'PSD transform round trip');
        F.RecoverAiJob(Path); // Recovered job must retain its common square mapping.
        F.ImportAiResult(TPath.Combine(Path,'result.json'));
        Check(F.Document.FindLayer('mapped').Bounds.Top=2,'Recovered workspace mapping');
      finally EndJob; end;
      StartJob(False);
      try
        Op := J('{"op":"add_layer","layerId":"scaled","name":"Scaled","parentId":"","beforeLayerId":"","visible":true,"opacity":255,"assetId":"source-1","resample":true,"trimTransparent":true,"sourceBounds":{"left":2,"top":2,"right":6,"bottom":6},"bounds":{"left":5,"top":6,"right":7,"bottom":8}}'); Ops.AddElement(Op);
        Publish; F.ImportAiResult(TPath.Combine(Path,'result.json'));
        B := F.Document.FindLayer('scaled').Bounds;
        Check((B.Left=5) and (B.Top=7) and (B.Width=1) and (B.Height=1),'Crop/resize/trim moved opaque pixel');
        Q := F.Document.FindLayer('scaled').Pixels;
        Check((Q[0]=255) and (Q[2]=0) and (Q[3]=64),'Area reduction incorrect');
        Check(CompareMem(@P[0],@F.Document.FindLayer(Id).Pixels[0],Length(P)),'Source layer modified');
        F.Undo; Check(F.Document.FindLayer('scaled')=nil,'Undo resized part');
        F.Redo; Check(F.Document.FindLayer('scaled').Pixels[3]=64,'Redo resized part');
      finally EndJob; end;
      // Re-adjust from the ORIGINAL source asset, not from the 1-pixel result.
      StartJob(False);
      try
        Op := J('{"op":"replace_layer","layerId":"scaled","assetId":"source-1","resample":true,"sourceBounds":{"left":2,"top":2,"right":6,"bottom":6},"bounds":{"left":2,"top":2,"right":6,"bottom":6}}'); Ops.AddElement(Op);
        Publish; F.ImportAiResult(TPath.Combine(Path,'result.json'));
        Q := F.Document.FindLayer('scaled').Pixels;
        Check((Length(Q)=64) and (Q[(2*4+1)*4+3]=255),'Readjustment reused reduced pixels');
        F.SavePsdFile(TPath.Combine(Root,'resized.psd')); Id := F.Document.Roots[0].Id;
        Check(F.Document.Roots[2].Bounds.Width=4,'PSD resized layer width');
      finally EndJob; end;
      for var CaseNo := 0 to 6 do begin
        StartJob(False);
        try
          Op := J('{"op":"add_layer","layerId":"bad","name":"Bad","parentId":"","beforeLayerId":"","visible":true,"opacity":255,"assetId":"source-1","bounds":{"left":0,"top":0,"right":2,"bottom":2}}'); Ops.AddElement(Op);
          case CaseNo of
            0: ; // Mismatched PNG dimensions still rejected without explicit opt-in.
            1: begin Op.AddPair('resample',TJSONBool.Create(True)); Op.AddPair('sourceBounds',J('{"left":-1,"top":0,"right":8,"bottom":8}')); end;
            2: begin Op.AddPair('resample',TJSONBool.Create(True)); Op.AddPair('coordinateSpace','workspace'); end;
            3: Op.AddPair('coordinateSpace','unknown');
            4: begin Op.AddPair('resample',TJSONBool.Create(True)); Op.RemovePair('bounds').Free; Op.AddPair('bounds',J('{"left":0,"top":0,"right":0,"bottom":2}')); end;
            5: begin Op.AddPair('resample',TJSONBool.Create(True)); Op.AddPair('sourceBounds',J('{"left":0,"top":0,"right":2,"bottom":2}')); Op.AddPair('trimTransparent',TJSONBool.Create(True)); end;
            6: Op.AddPair('resample','true');
          end;
          Reject('Invalid transform accepted '+IntToStr(CaseNo));
        finally EndJob; end;
      end;
      Workspace := J('{"sourceLayerId":"","size":16,"bounds":{"left":0,"top":0,"right":4,"bottom":3}}');
      try
        Before := F.Document; Failed := False;
        try F.ExportAiJob('bad square',Root,Workspace); except on EArtFormat do Failed := True; end;
        Check(Failed and (F.Document=Before) and not F.Busy,'Invalid workspace export mutated document');
      finally Workspace.Free; end;
    finally F.Free; end;
    Writeln('PASS: ',Count,' transform assertions');
  except on E: Exception do begin Writeln(E.ClassName,': ',E.Message); Halt(1); end; end;
end.

program PipeFileOperationsSmoke;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.Classes, System.IOUtils,
  ArtDocument in '..\Source\Core\ArtDocument.pas',
  ArtPsd in '..\Source\Persistence\PSD\ArtPsd.pas',
  ArtPipeFileOps in '..\Source\Integrations\Pipe\ArtPipeFileOps.pas';

procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); end;

var OutputDir,Target,Other,OriginalHash,WrongHash,ChangedHash: string;
    D,Saved: TArtDocument; L: TArtLayer; Lock: TFileStream; Failed: Boolean;
begin
  try
    if ParamCount<>1 then raise Exception.Create('Usage: PipeFileOperationsSmoke NEW_OUTPUT_DIRECTORY');
    OutputDir := TPath.GetFullPath(ParamStr(1));
    if TDirectory.Exists(OutputDir) or TFile.Exists(OutputDir) then
      raise Exception.Create('Output directory must not exist');
    TDirectory.CreateDirectory(OutputDir);
    Target := TPath.Combine(OutputDir,'fixture.psd'); Other := TPath.Combine(OutputDir,'other.psd');
    D := TArtDocument.Create;
    try
      D.Width := 7; D.Height := 5;
      L := D.AddLayer(alkImage,'Pixels',TArtBounds.Create(1,2,3,4));
      L.Pixels := TBytes.Create(20,30,40,255,70,80,90,128,1,2,3,0,255,0,0,255);
      SaveArtPipePsd(D,Target,'',True,'');
      OriginalHash := ArtPipeFileSha256(Target);
      Failed := False;
      try SaveArtPipePsd(D,Target,'',True,''); except on E: Exception do Failed := True; end;
      Check(Failed,'Existing destination accepted without overwrite');
      Check(ArtPipeFileSha256(Target)=OriginalHash,'Default rejection changed destination');
    finally D.Free; end;
    D := ReadPsd(Target);
    try
      Check(ArtPipeDocumentSha256(D)=OriginalHash,'Loaded source hash differs');
      D.Roots[0].Name := '*Renamed'; D.Roots[0].Visible := False;
      WrongHash := StringOfChar('0',64);
      Failed := False;
      try SaveArtPipePsd(D,Target,Target,True,WrongHash); except on E: Exception do Failed := True; end;
      Check(Failed,'Wrong source hash accepted');
      Failed := False;
      try SaveArtPipePsd(D,Target,Other,True,OriginalHash); except on E: Exception do Failed := True; end;
      Check(Failed,'Overwrite accepted for a different open source path');
      // A changed disk baseline must be rejected even if the open source still matches.
      TFile.AppendAllText(Target,'external-change',TEncoding.ASCII);
      ChangedHash := ArtPipeFileSha256(Target);
      Failed := False;
      try SaveArtPipePsd(D,Target,Target,True,OriginalHash); except on E: Exception do Failed := True; end;
      Check(Failed,'Changed destination hash accepted');
      Check(ArtPipeFileSha256(Target)=ChangedHash,'Rejected overwrite changed external bytes');
      TFile.WriteAllBytes(Target,D.SourceBytes); // Our isolated fixture only.
      Lock := TFileStream.Create(Target,fmOpenRead or fmShareExclusive);
      try
        Failed := False;
        try SaveArtPipePsd(D,Target,Target,True,OriginalHash); except on E: Exception do Failed := True; end;
        Check(Failed,'Locked destination accepted');
      finally Lock.Free; end;
      Check(ArtPipeFileSha256(Target)=OriginalHash,'Rejected overwrite changed destination');
      SaveArtPipePsd(D,Target,Target,True,OriginalHash);
      Saved := ReadPsd(Target);
      try
        Check((Saved.Width=D.Width) and (Saved.Height=D.Height),'Canvas changed');
        Check((Saved.Roots.Count=1) and (Saved.Roots[0].Name='*Renamed') and
          not Saved.Roots[0].Visible,'Layer metadata was not saved');
        Check(CompareMem(@Saved.Roots[0].Bounds,@D.Roots[0].Bounds,SizeOf(TArtBounds)),'Bounds changed');
        Check((Length(Saved.Roots[0].Pixels)=Length(D.Roots[0].Pixels)) and
          CompareMem(@Saved.Roots[0].Pixels[0],@D.Roots[0].Pixels[0],Length(D.Roots[0].Pixels)),
          'Layer RGBA changed');
      finally Saved.Free; end;
      Failed := False;
      try SaveArtPipePsd(D,Target,Target,True,OriginalHash); except on E: Exception do Failed := True; end;
      Check(Failed,'Old baseline accepted after a successful overwrite');
      Check(Length(TDirectory.GetFiles(OutputDir,'*.pipe.tmp.psd'))=0,'Staging file leaked');
    finally D.Free; end;
    Writeln('PASS: new-only, guarded overwrite, external change, lock, stale baseline, RGBA and staging cleanup');
  except on E: Exception do begin Writeln(E.ClassName,': ',E.Message); Halt(1); end; end;
end.

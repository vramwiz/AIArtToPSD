unit ArtPipeFileOps;

// Existing pipe only: stage/validate a PSD, then publish without changing Document.
// An empty expected hash means new-only; overwrite is limited to the open source path.
interface

uses ArtDocument;

procedure SaveArtPipePsd(Document: TArtDocument; const FileName, SourceFileName: string;
  Modified: Boolean; const ExpectedFileSha256: string);
function ArtPipeFileSha256(const FileName: string): string;
function ArtPipeDocumentSha256(Document: TArtDocument): string;

implementation

uses System.SysUtils, System.Classes, System.IOUtils, System.Hash, Winapi.Windows,
  ArtPsd;

function ArtPipeFileSha256(const FileName: string): string;
var Input: TFileStream;
begin
  Input := TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
  try Result := LowerCase(THashSHA2.GetHashString(Input));
  finally Input.Free; end;
end;

function ArtPipeDocumentSha256(Document: TArtDocument): string;
var Hash: THashSHA2;
begin
  if Document=nil then raise EArtFormat.Create('No PSD is open');
  Hash := THashSHA2.Create; Hash.Update(Document.SourceBytes);
  Result := LowerCase(Hash.HashAsString);
end;

procedure SaveArtPipePsd(Document: TArtDocument; const FileName, SourceFileName: string;
  Modified: Boolean; const ExpectedFileSha256: string);
var Target,Source,TempPath: string; Overwrite,OwnsTemp: Boolean; G: TGUID;
    StageHandle: THandle;
    Original,FlushStream: TFileStream; Validated: TArtDocument;
begin
  if Document=nil then raise EArtFormat.Create('No PSD is open');
  Target := TPath.GetFullPath(FileName);
  if not SameText(ExtractFileExt(Target),'.psd') then raise EArtFormat.Create('PSD destination required');
  if not TDirectory.Exists(ExtractFilePath(Target)) then raise EArtFormat.Create('Destination directory is missing');
  if TDirectory.Exists(Target) then raise EArtFormat.Create('PSD destination is a directory');
  Overwrite := ExpectedFileSha256<>'';
  Original := nil; TempPath := ''; OwnsTemp := False;
  try
    if Overwrite then begin
      if Length(ExpectedFileSha256)<>64 then raise EArtFormat.Create('expectedFileSha256 must contain 64 hexadecimal characters');
      for var C in ExpectedFileSha256 do
        if not CharInSet(C,['0'..'9','a'..'f','A'..'F']) then
          raise EArtFormat.Create('expectedFileSha256 must contain 64 hexadecimal characters');
      if SourceFileName='' then raise EArtFormat.Create('Overwrite requires an existing open PSD path');
      Source := TPath.GetFullPath(SourceFileName);
      if not SameText(Target,Source) then raise EArtFormat.Create('Overwrite is limited to the currently open PSD path');
      if not SameText(ArtPipeDocumentSha256(Document),ExpectedFileSha256) then
        raise EArtFormat.Create('Open PSD source SHA256 differs; reopen the target before overwrite');
      if not TFile.Exists(Target) then raise EArtFormat.Create('Overwrite destination no longer exists');
      // Hold a deny-write lock while checking and staging; never truncate the original.
      Original := TFileStream.Create(Target,fmOpenRead or fmShareDenyWrite);
      if not SameText(THashSHA2.GetHashString(Original),ExpectedFileSha256) then
        raise EArtFormat.Create('Destination SHA256 changed; inspect the file before retrying');
    end else if TFile.Exists(Target) then
      raise EArtFormat.Create('Destination already exists; choose a new PSD path or explicitly request overwrite');
    CreateGUID(G); TempPath := Target+'.'+GUIDToString(G)+'.pipe.tmp.psd';
    StageHandle := CreateFile(PChar(TempPath),GENERIC_READ or GENERIC_WRITE,0,nil,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,0);
    if StageHandle=INVALID_HANDLE_VALUE then RaiseLastOSError;
    OwnsTemp := True; CloseHandle(StageHandle);
    if Length(Document.SourceBytes)=0 then WriteNewPsd(Document,TempPath,pcRle)
    else if Modified then begin
      try SaveLayerPropertiesPsd(Document,TempPath);
      except on E: EArtFormat do SaveImageCompositionPsd(Document,TempPath); end;
    end else SaveUnchangedPsd(Document,TempPath);
    Validated := ReadPsd(TempPath);
    try
      if (Validated.Width<>Document.Width) or (Validated.Height<>Document.Height) then
        raise EArtFormat.Create('Staged PSD canvas mismatch');
    finally Validated.Free; end;
    FlushStream := TFileStream.Create(TempPath,fmOpenReadWrite or fmShareExclusive);
    try if not FlushFileBuffers(FlushStream.Handle) then RaiseLastOSError;
    finally FlushStream.Free; end;
    if Overwrite then begin
      // Windows replacement requires releasing the source handle. ReplaceFile keeps
      // existing destination metadata; failure is reported without a delete/rename fallback.
      FreeAndNil(Original);
      if not Winapi.Windows.ReplaceFile(PChar(Target),PChar(TempPath),nil,0,nil,nil) then
        RaiseLastOSError;
    end else if not MoveFileEx(PChar(TempPath),PChar(Target),MOVEFILE_WRITE_THROUGH) then
      RaiseLastOSError;
    TempPath := '';
  finally
    Original.Free;
    // Only our newly created staging file is eligible for cleanup.
    if OwnsTemp and (TempPath<>'') and TFile.Exists(TempPath) then TFile.Delete(TempPath);
  end;
end;

end.

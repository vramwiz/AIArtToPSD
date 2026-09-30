unit ArtFileHistory;
interface
uses System.Classes;
type
  TArtFileHistory = class
  private
    FDirectory: string;
    FFiles: TStringList;

    procedure Persist;
  public
    constructor Create(const Directory: string);
    destructor Destroy; override;
    procedure AddFile(const FileName: string);
    property Files: TStringList read FFiles;
    property Directory: string read FDirectory;
  end;
implementation
uses System.SysUtils, System.IOUtils, System.IniFiles, Winapi.Windows;
constructor TArtFileHistory.Create(const Directory: string);
var Ini: TMemIniFile; I: Integer; Value: string; Migrated: Boolean;
  procedure Include(const Section: string; Index: Integer);
  begin
    Value := Ini.ReadString(Section,IntToStr(Index),'');
    if (Value<>'') and (FFiles.IndexOf(Value)<0) and (FFiles.Count<20) then FFiles.Add(Value);
  end;
begin
  inherited Create;
  FFiles := TStringList.Create; FFiles.CaseSensitive := False;
  FDirectory := Directory;
  if FDirectory='' then FDirectory := TPath.Combine(TPath.GetDocumentsPath,'AIArtToPSD');
  ForceDirectories(FDirectory);
  Ini := TMemIniFile.Create(TPath.Combine(FDirectory,'history.ini'),TEncoding.UTF8);
  try
    Migrated := not Ini.SectionExists('Recent') and (Ini.SectionExists('Opened') or Ini.SectionExists('Saved'));
    if Migrated then
      for I := 0 to 19 do begin Include('Opened',I); Include('Saved',I); end
    else for I := 0 to 19 do Include('Recent',I);
  finally Ini.Free; end;
  if Migrated then Persist;
end;
destructor TArtFileHistory.Destroy;
begin FFiles.Free; inherited; end;
procedure TArtFileHistory.AddFile(const FileName: string);
var Path: string; I: Integer;
begin
  Path := TPath.GetFullPath(FileName); I := FFiles.IndexOf(Path);
  if I>=0 then FFiles.Delete(I);
  FFiles.Insert(0,Path); while FFiles.Count>20 do FFiles.Delete(FFiles.Count-1);
  Persist;
end;
procedure TArtFileHistory.Persist;
var Ini: TMemIniFile; TempName,FileName: string; I: Integer;
begin
  ForceDirectories(FDirectory);
  FileName := TPath.Combine(FDirectory,'history.ini'); TempName := FileName+'.tmp';
  Ini := TMemIniFile.Create(TempName,TEncoding.UTF8);
  try
    Ini.Clear;
    for I := 0 to FFiles.Count-1 do Ini.WriteString('Recent',IntToStr(I),FFiles[I]);
    Ini.UpdateFile;
  finally Ini.Free; end;
  if not MoveFileEx(PChar(TempName),PChar(FileName),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
end;
end.

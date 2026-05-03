unit uRepoSettings;

// Persistente Repo-Settings fuer die Branch-Changes-Analyse.
//
// Datei: %APPDATA%\StaticCodeAnalyser\repo.ini
//
// [Repo]
// BaseBranch=develop          ; leer = auto (origin/HEAD -> main -> master)
// IncludeWorkingTree=1        ; 1 = uncommitted Aenderungen mit, 0 = nur committed
//
// [Paths]
// GitExe=C:\custom\git.exe    ; leer = auto (PATH + Tortoise-Hints)
// SvnExe=C:\custom\svn.exe
//
// Aenderungen wirken beim naechsten Klick auf "Branch-Changes".

interface

uses
  System.SysUtils, System.Classes, System.IniFiles;

type
  TRepoSettings = class
  private
    FBaseBranch        : string;
    FIncludeWorkingTree: Boolean;
    FGitExePath        : string;
    FSvnExePath        : string;
    FConfigPath        : string;
  public
    constructor Create;

    // Laedt aus repo.ini. Wenn die Datei nicht existiert, wird sie mit
    // einem dokumentierten Default-Inhalt angelegt.
    procedure Load;
    // Speichert aktuelle Werte in repo.ini (legt Verzeichnis bei Bedarf an).
    procedure Save;
    procedure EnsureConfigExists;

    function ConfigFilePath: string;

    // '' bedeutet auto-detect (origin/HEAD, dann main, dann master).
    property BaseBranch: string read FBaseBranch write FBaseBranch;
    // True (Default): committed Branch-Diff + uncommitted Working Tree;
    // False: nur committed.
    property IncludeWorkingTree: Boolean read FIncludeWorkingTree
                                         write FIncludeWorkingTree;
    // '' bedeutet auto-detect via PATH/Tortoise-Hints.
    property GitExePath: string read FGitExePath write FGitExePath;
    property SvnExePath: string read FSvnExePath write FSvnExePath;
  end;

implementation

uses
  uIgnoreList;

const
  DEFAULT_INI_CONTENT =
    '; Static Code Analysis Tool for Delphi - Repo-Settings'#13#10 +
    '; Wirkt auf den "Branch-Changes"-Button.'#13#10 +
    ''#13#10 +
    '[Repo]'#13#10 +
    '; Vergleichs-Branch fuer "git diff <base>...HEAD".'#13#10 +
    '; Leer lassen fuer Auto-Detect (origin/HEAD -> main -> master).'#13#10 +
    '; Beispiele: develop, release/2024.1, origin/main'#13#10 +
    'BaseBranch='#13#10 +
    ''#13#10 +
    '; Uncommitted Working-Tree-Aenderungen einbeziehen?'#13#10 +
    '; 1 = ja (Default - typisch fuer Pre-Commit-Check)'#13#10 +
    '; 0 = nur committed Aenderungen'#13#10 +
    'IncludeWorkingTree=1'#13#10 +
    ''#13#10 +
    '[Paths]'#13#10 +
    '; Vollstaendige Pfade falls git/svn nicht im PATH und nicht im'#13#10 +
    '; Standard-Tortoise-Pfad liegen. Sonst leer lassen.'#13#10 +
    'GitExe='#13#10 +
    'SvnExe='#13#10;

constructor TRepoSettings.Create;
begin
  inherited;
  FBaseBranch         := '';
  FIncludeWorkingTree := True;
  FGitExePath         := '';
  FSvnExePath         := '';
  FConfigPath         := '';
end;

function TRepoSettings.ConfigFilePath: string;
begin
  if FConfigPath <> '' then Exit(FConfigPath);
  // Liegt im selben Verzeichnis wie ignore.txt (= %APPDATA%\StaticCodeAnalyser\).
  FConfigPath := TIgnoreList.ConfigDir + 'repo.ini';
  Result := FConfigPath;
end;

procedure TRepoSettings.EnsureConfigExists;
var
  Path, Dir: string;
  SL       : TStringList;
begin
  Path := ConfigFilePath;
  if FileExists(Path) then Exit;
  Dir := ExtractFilePath(Path);
  if (Dir <> '') and not DirectoryExists(Dir) then
    try ForceDirectories(Dir); except Exit; end;
  SL := TStringList.Create;
  try
    SL.Text := DEFAULT_INI_CONTENT;
    try SL.SaveToFile(Path, TEncoding.UTF8); except end;
  finally
    SL.Free;
  end;
end;

procedure TRepoSettings.Load;
var
  Ini: TIniFile;
begin
  EnsureConfigExists;
  Ini := TIniFile.Create(ConfigFilePath);
  try
    FBaseBranch         := Trim(Ini.ReadString('Repo',  'BaseBranch',         ''));
    FIncludeWorkingTree :=      Ini.ReadBool  ('Repo',  'IncludeWorkingTree', True);
    FGitExePath         := Trim(Ini.ReadString('Paths', 'GitExe',             ''));
    FSvnExePath         := Trim(Ini.ReadString('Paths', 'SvnExe',             ''));
  finally
    Ini.Free;
  end;
end;

procedure TRepoSettings.Save;
var
  Ini: TIniFile;
begin
  EnsureConfigExists;
  Ini := TIniFile.Create(ConfigFilePath);
  try
    Ini.WriteString('Repo',  'BaseBranch',         FBaseBranch);
    Ini.WriteBool  ('Repo',  'IncludeWorkingTree', FIncludeWorkingTree);
    Ini.WriteString('Paths', 'GitExe',             FGitExePath);
    Ini.WriteString('Paths', 'SvnExe',             FSvnExePath);
  finally
    Ini.Free;
  end;
end;

end.

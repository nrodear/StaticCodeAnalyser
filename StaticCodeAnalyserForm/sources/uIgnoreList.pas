unit uIgnoreList;

// Ignore-Liste fuer Dateien, die NICHT analysiert werden sollen.
//
// Format der Datei (eine Zeile pro Muster):
//   # Kommentar
//   <leer>             - ignoriert
//   <name>             - exakter Datei-Name (case-insensitive)
//   <muster>           - Glob mit * und ? (System.Masks)
//   <verzeichnis>/     - kompletter Pfad enthaelt diesen Verzeichnis-Namen
//
// Default-Pfad: %APPDATA%\StaticCodeAnalyser\ignore.txt
// Wenn nicht vorhanden, wird eine Default-Datei mit Beispielen erstellt.

interface

uses
  System.SysUtils, System.Classes, System.Masks, System.IOUtils;

type
  TIgnoreList = class
  private
    FPatterns  : TStringList; // bereinigt: nur Muster, kein Kommentar/leer
    FDirParts  : TStringList; // Muster mit / am Ende: Verzeichnis-Match
    FConfigPath: string;
    // Wenn True (default), werden DUnit/DUnitX-Tests + Test-Projekte
    // automatisch ausgeschlossen ohne dass der User Patterns pflegen muss.
    FSkipTests : Boolean;
    procedure ApplyLine(const RawLine: string);
    // Built-in Erkennung typischer Test-Datei-Namen und -Verzeichnisse.
    function IsTestPath(const FileName: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    // Standard-Datei laden (oder mit Defaults anlegen).
    procedure LoadDefault;
    // Aus angegebener Datei laden. Datei darf fehlen (= leere Liste).
    procedure LoadFromFile(const APath: string);

    // Prueft ob eine Datei (voller Pfad oder nur Name) ignoriert werden soll.
    function IsIgnored(const FileName: string): Boolean;

    function ConfigFilePath: string;
    function PatternCount: Integer;

    // Toggle fuer den eingebauten Test-Filter. UI-Checkbox bindet hierauf.
    property SkipTests: Boolean read FSkipTests write FSkipTests;

    // Erstellt die Default-Datei mit Beispielen falls nicht vorhanden.
    procedure EnsureConfigExists;

    // Gemeinsames Konfig-Verzeichnis fuer alle Tool-Dateien (Log, Ignore, ...)
    // Default: %APPDATA%\StaticCodeAnalyser\
    class function ConfigDir: string; static;
    // Voller Pfad zur Diagnose-Log-Datei innerhalb von ConfigDir.
    class function LogFilePath: string; static;
  end;

implementation

const
  // Default-Inhalt der Ignore-Datei beim ersten Aufruf
  DEFAULT_FILE_CONTENT =
    '# Static Code Analyser - Ignore-Liste'#13#10 +
    '# Eine Zeile pro Muster. # am Anfang = Kommentar, leere Zeilen erlaubt.'#13#10 +
    '#'#13#10 +
    '# Beispiele:'#13#10 +
    '#   MeineUnit.pas        - exakter Datei-Name'#13#10 +
    '#   *_TLB.pas            - Glob mit Wildcard'#13#10 +
    '#   *Generated*.pas      - alles mit "Generated" im Namen'#13#10 +
    '#   tests/               - Pfad enthaelt /tests/'#13#10 +
    '#'#13#10 +
    '# Generierte / nicht zu analysierende Dateien:'#13#10 +
    '*_TLB.pas'#13#10 +
    '*.dproj.pas'#13#10 +
    ''#13#10 +
    '# Test-Verzeichnisse (optional aktivieren):'#13#10 +
    '# tests/'#13#10;

constructor TIgnoreList.Create;
begin
  inherited;
  FPatterns := TStringList.Create;
  FPatterns.CaseSensitive := False;
  FDirParts := TStringList.Create;
  FDirParts.CaseSensitive := False;
  FConfigPath := '';
  // Tests standardmaessig ausschliessen - Detektoren wie LongMethod schlagen
  // bei Test-Fixtures oft an, ohne dass die Tests "schlechter Code" sind.
  FSkipTests := True;
end;

destructor TIgnoreList.Destroy;
begin
  FPatterns.Free;
  FDirParts.Free;
  inherited;
end;

class function TIgnoreList.ConfigDir: string;
// Gemeinsames Verzeichnis fuer Ignore-Liste UND Log-Datei.
// %APPDATA%\StaticCodeAnalyser\  (Fallback: %TEMP%\StaticCodeAnalyser\)
var
  AppData: string;
begin
  AppData := GetEnvironmentVariable('APPDATA');
  if AppData = '' then
    AppData := TPath.GetTempPath;
  Result := IncludeTrailingPathDelimiter(AppData) + 'StaticCodeAnalyser' +
            PathDelim;
end;

class function TIgnoreList.LogFilePath: string;
begin
  Result := ConfigDir + 'StaticCodeAnalyser_scan.log';
end;

function TIgnoreList.ConfigFilePath: string;
begin
  if FConfigPath <> '' then Exit(FConfigPath);
  FConfigPath := ConfigDir + 'ignore.txt';
  Result := FConfigPath;
end;

procedure TIgnoreList.EnsureConfigExists;
var
  Path, Dir: string;
  SL: TStringList;
begin
  Path := ConfigFilePath;
  if FileExists(Path) then Exit;
  Dir := ExtractFilePath(Path);
  if (Dir <> '') and not DirectoryExists(Dir) then
    try ForceDirectories(Dir); except Exit; end;
  SL := TStringList.Create;
  try
    SL.Text := DEFAULT_FILE_CONTENT;
    try SL.SaveToFile(Path, TEncoding.UTF8); except end;
  finally
    SL.Free;
  end;
end;

procedure TIgnoreList.ApplyLine(const RawLine: string);
var
  Line: string;
begin
  Line := Trim(RawLine);
  if Line = '' then Exit;
  if Line.StartsWith('#') then Exit;

  // Verzeichnis-Match wenn Muster mit / oder \ endet
  if Line.EndsWith('/') or Line.EndsWith('\') then
  begin
    Line := Copy(Line, 1, Length(Line) - 1);
    if Line <> '' then
      FDirParts.Add(Line.Replace('\', '/').ToLower);
  end
  else
    FPatterns.Add(Line);
end;

procedure TIgnoreList.LoadDefault;
begin
  EnsureConfigExists;
  LoadFromFile(ConfigFilePath);
end;

procedure TIgnoreList.LoadFromFile(const APath: string);
var
  SL: TStringList;
  S : string;
begin
  FPatterns.Clear;
  FDirParts.Clear;
  if not FileExists(APath) then Exit;

  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(APath, TEncoding.UTF8);
    except
      try SL.LoadFromFile(APath); except Exit; end;
    end;
    for S in SL do
      ApplyLine(S);
  finally
    SL.Free;
  end;
end;

function TIgnoreList.IsTestPath(const FileName: string): Boolean;
// Erkennt typische DUnit/DUnitX-Test-Namensschemata. Konservativ gehalten,
// damit normale Dateien mit "test" im Namen NICHT versehentlich rausfliegen.
const
  // Strikte Datei-Glob-Patterns - matcht den Basisnamen.
  TEST_FILE_PATTERNS: array[0..6] of string = (
    'uTest*.pas',         // u-Praefix Konvention: uTestFoo.pas
    '*_Test.pas',         // Snake-Case: foo_Test.pas
    '*_Tests.pas',        // Snake-Case Plural: foo_Tests.pas
    '*TestSuite*.pas',    // explizite Test-Suite
    'TestProject*.dpr',   // DUnitX-Standard-Runner-Projekt
    'TestProject*.dpk',
    '*Tests.dpr'          // generische Test-Runner-Projekte
  );
  // Verzeichnis-Substring (normalisiert mit /), case-insensitive.
  TEST_DIR_PARTS: array[0..4] of string = (
    'test',          // Singular: /test/, oft fuer einzelne Test-Suites
    'tests',         // Plural: /tests/
    'unittest',
    'unittests',
    'dunit-tests'
  );
var
  Bare, FullLow : string;
  Pat, DirPart  : string;
begin
  Result := False;
  if FileName = '' then Exit;

  Bare    := ExtractFileName(FileName);
  FullLow := FileName.Replace('\', '/').ToLower;

  for DirPart in TEST_DIR_PARTS do
    if Pos('/' + DirPart + '/', FullLow) > 0 then Exit(True);

  for Pat in TEST_FILE_PATTERNS do
    if MatchesMask(Bare, Pat) then Exit(True);
end;

function TIgnoreList.IsIgnored(const FileName: string): Boolean;
var
  Bare, FullLow: string;
  P, DirPart   : string;
begin
  Result := False;
  if FileName = '' then Exit;

  Bare    := ExtractFileName(FileName);
  FullLow := FileName.Replace('\', '/').ToLower;

  // Verzeichnis-Patterns: substring-Suche im normalisierten Pfad
  for DirPart in FDirParts do
    if Pos('/' + DirPart + '/', FullLow) > 0 then Exit(True);

  // Datei-Patterns: glob-Match gegen den Basis-Namen
  for P in FPatterns do
    if MatchesMask(Bare, P) then Exit(True);

  // Built-in Test-Filter (nur wenn aktiv).
  if FSkipTests and IsTestPath(FileName) then Exit(True);
end;

function TIgnoreList.PatternCount: Integer;
begin
  Result := FPatterns.Count + FDirParts.Count;
end;

end.

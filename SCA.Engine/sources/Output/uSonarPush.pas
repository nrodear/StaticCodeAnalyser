unit uSonarPush;

// Helper fuer den "Send to Sonar"-Workflow aus dem IDE-Plugin und der UI.
//
// Es gibt zwei Modi:
//   1. Bulk-Export: alle aktuell sichtbaren Findings als EINE
//      Generic-Issue-JSON nach <out>/sca-findings.json (oder vom User
//      gewaehlter Pfad). Dasselbe was --sonar-export im CLI macht.
//   2. Per-Issue-Push: ausgewaehlte Findings einzeln in
//      <project>\.sonar\external\<hash>.json schreiben. Sonar-Scanner
//      sammelt alle .json-Files im Pfad automatisch ueber
//      sonar.externalIssuesReportPaths=.sonar/external/.
//
// In beiden Faellen schreibt diese Unit nur Dateien - HTTP-Push an die
// Sonar-API laeuft separat ueber sonar-scanner. Direct-API-Push (POST
// /api/issues/add) ist Sonar-seitig fuer externe Tools nicht supported.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uMethodd12;

const
  SONAR_EXTERNAL_SUBDIR = '.sonar\external';

type
  TSonarPush = class
  public
    // Bulk: alle Findings als ein Generic-Issue-Report. Wenn OutFile leer
    // ist, wird FOutDir\sca-findings.json verwendet. Liefert den Pfad
    // der geschriebenen Datei.
    class function WriteBulk(const Findings: TObjectList<TLeakFinding>;
      const BaseDir, OutFile: string): string; static;

    // Pro Finding eine kleine .json. ProjectDir bekommt
    // .sonar\external\<rule>-<file>-<line>-<hash>.json. Verzeichnis wird
    // bei Bedarf angelegt. Liefert Anzahl der geschriebenen Files.
    class function WriteIndividual(const Findings: array of TLeakFinding;
      const BaseDir, ProjectDir: string): Integer; static;

    // Liefert den .sonar\external-Ordner unter ProjectDir und legt ihn
    // bei Bedarf an.
    class function EnsureExternalDir(const ProjectDir: string): string; static;
  end;

implementation

uses
  System.IOUtils, System.Hash, System.NetEncoding,
  uExportSonarGeneric;

class function TSonarPush.WriteBulk(const Findings: TObjectList<TLeakFinding>;
  const BaseDir, OutFile: string): string;
var
  Target : string;
begin
  if OutFile <> '' then Target := OutFile
  else Target := IncludeTrailingPathDelimiter(GetCurrentDir) + 'sca-findings.json';
  ForceDirectories(ExtractFilePath(Target));
  TSonarGenericWriter.WriteFile(Target, Findings, BaseDir);
  Result := Target;
end;

class function TSonarPush.EnsureExternalDir(const ProjectDir: string): string;
begin
  if ProjectDir = '' then
    Result := IncludeTrailingPathDelimiter(GetCurrentDir) + SONAR_EXTERNAL_SUBDIR
  else
    Result := IncludeTrailingPathDelimiter(ProjectDir) + SONAR_EXTERNAL_SUBDIR;
  ForceDirectories(Result);
end;

function MakeFileSafe(const S: string): string;
const
  BAD: array[0..8] of Char = ('\','/',':','*','?','"','<','>','|');
var
  C : Char;
begin
  Result := S;
  for C in BAD do
    Result := StringReplace(Result, C, '_', [rfReplaceAll]);
  if Length(Result) > 80 then
    Result := Copy(Result, 1, 80);
end;

class function TSonarPush.WriteIndividual(const Findings: array of TLeakFinding;
  const BaseDir, ProjectDir: string): Integer;
var
  Dir, Stem, OutPath : string;
  F  : TLeakFinding;
  L  : TObjectList<TLeakFinding>;
  Hash : string;
  Cnt  : Integer;
begin
  Cnt := 0;
  Dir := EnsureExternalDir(ProjectDir);
  for F in Findings do
  begin
    L := TObjectList<TLeakFinding>.Create(False); // borrowed refs
    try
      L.Add(F);
      Hash := Copy(THashSHA2.GetHashString(
        F.FileName + '|' + F.LineNumber + '|' + F.MissingVar), 1, 8);
      Stem := MakeFileSafe(Format('%s-%s-L%s-%s',
        [F.SeverityText, ExtractFileName(F.FileName), F.LineNumber, Hash]));
      OutPath := IncludeTrailingPathDelimiter(Dir) + Stem + '.json';
      TSonarGenericWriter.WriteFile(OutPath, L, BaseDir);
      Inc(Cnt);
    finally
      L.Free;
    end;
  end;
  Result := Cnt;
end;

end.

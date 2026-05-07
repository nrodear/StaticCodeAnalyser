unit uSCAConsts;

interface

uses
  System.Classes, SysUtils;

var
  Flags: Byte;

  // LeakyClasses ist die Laufzeit-Liste aller Klassen, die der MemoryLeak-
  // Detektor (TLeakDetector2) trackt. Vorher als statisches Array - jetzt
  // dynamische TStringList, damit:
  //   * keine Index-Counter beim Hinzufuegen
  //   * zur Laufzeit erweiterbar (z.B. aus analyser.ini Custom-Eintraege)
  //
  // Wird in initialization befuellt mit den Default-Klassen, in finalization
  // freigegeben. Aufrufer koennen .Add('TFDQuery') nutzen um Custom-Klassen
  // zu registrieren.
  LeakyClasses: TStringList = nil;

  // Auto-Discovery-Flag: wenn True, scannt der Analyzer pro Datei das AST
  // auf 'class(...)' Deklarationen und ergaenzt LeakyClasses um Custom-
  // Klassen die NICHT von TForm/TFrame/TComponent/TInterfacedObject erben.
  // Wird vom Aufrufer gesetzt (z.B. UI aus RepoSettings.AutoDiscoverClasses).
  AutoDiscoverCustomClasses: Boolean = False;

  // Globale Exclude-Liste: Klassen die der MemoryLeak-Detektor NICHT melden
  // soll, auch wenn sie in LeakyClasses landen wuerden. Wird vom Aufrufer
  // (RepoSettings.RegisterToLeakyClasses) befuellt - Discovery & Detector
  // konsultieren sie vor jedem Add/Match. Damit greifen ExcludeLeakyClasses
  // auch gegen Auto-Discovery-Treffer.
  LeakyClassExcludes: TStringList = nil;

  // Discovery-Sammler fuer den aktuellen Lauf. Beide Listen werden nach
  // Abschluss der Analyse von TRepoSettings in LeakyClassesDiscover.log
  // geschrieben (Kuratierungs-Hilfe; INI bleibt unangetastet).
  //
  //   DiscoveredClasses        - Klassen mit Konstruktor/Destruktor oder
  //                              Create-Aufruf in der eigenen Unit
  //                              -> echte Instanzen, leak-relevant.
  //   DiscoveredStaticClasses  - keine Hinweise auf Instanziierung
  //                              -> wahrscheinlich Utility-Klassen mit
  //                              nur class methods, vermutlich nicht zu
  //                              pruefen. Im .log auskommentiert (fuer
  //                              den User als Hinweis).
  DiscoveredClasses       : TStringList = nil;
  DiscoveredStaticClasses : TStringList = nil;

  // Detektor-Schwellwerte. Werden vom RepoSettings beim Analyse-Start
  // gesetzt (TRepoSettings.ApplyDetectorThresholds). Default-Werte spiegeln
  // die alten hardcoded Konstanten - wenn die INI keine Eintraege hat,
  // bleibt das Verhalten exakt wie vorher.
  DetectorMaxBodyLines     : Integer = 50;     // uLongMethod
  DetectorMaxStatements    : Integer = 30;     // uLongMethod sek. Schwelle
  DetectorMaxParams        : Integer = 5;      // uLongParamList
  DetectorMaxNesting       : Integer = 4;      // uDeepNesting (>4 = Fund)
  DetectorMinBlockLines    : Integer = 8;      // uDuplicateBlock
  DetectorMaxFileBytes     : Integer = 5 * 1024 * 1024;  // uStaticAnalyzer2

  // Trivial-Liste fuer uMagicNumbers - Zahlen die NICHT als Magic-Number
  // gemeldet werden. Default: 0,1,2,-1,10,100. INI-Override moeglich.
  // Stringliste damit Vergleich mit den geparsten Zahlen-Strings ohne
  // Konversion klappt.
  DetectorMagicTrivials    : TStringList = nil;

type
  // Schweregrad eines Befundes - drei Stufen:
  //   lsError   - sichere Bugs / Sicherheitsluecken (Crash, Datenleak)
  //   lsWarning - wahrscheinliche Bugs / riskante Muster
  //   lsHint    - Code-Smells / Stilfragen (kein Bug, nur Wartbarkeit)
  TLeakSeverity = (
    lsError,
    lsWarning,
    lsHint
  );

  // Art des Befundes
  TFindingKind = (
    fkMemoryLeak,       // Speicherleck (uLeakDetector2)
    fkEmptyExcept,      // Leerer except-Block (verschluckt Exceptions)
    fkSQLInjection,     // SQL-String per '+' konkateniert (Injection-Risiko)
    fkHardcodedSecret,  // Passwort/Token als Stringliteral im Code
    fkFormatMismatch,   // Format()-Platzhalter ≠ Argument-Anzahl
    fkFileReadError,    // Datei konnte nicht gelesen / geparst werden
    fkUnusedUses,       // Uses-Eintrag moeglicherweise ungenutzt
    fkNilDeref,         // Zugriff auf Variable die nil sein kann
    fkMissingFinally,   // .Create ohne schuetzenden try/finally-Block
    fkDivByZero,        // Division durch Variable/Ausdruck der 0 sein koennte
    fkDeadCode,         // Toter Code nach Exit / raise
    fkLongMethod,       // Methode laenger als N Zeilen
    fkLongParamList,    // Methode hat zu viele Parameter
    fkMagicNumber,      // Zahlenliteral ohne Konstante
    fkDuplicateString,  // String-Literal an mehreren Stellen
    fkHardcodedPath,    // Pfad-Literal im Code (C:\ oder UNC)
    fkDebugOutput,      // WriteLn/ShowMessage in Produktion
    fkDeepNesting,      // Zu tiefe Verschachtelung
    fkTodoComment,      // TODO/FIXME/HACK/XXX im Kommentar
    fkEmptyMethod,      // Methodenrumpf ohne Anweisungen
    fkDuplicateBlock    // mehrere identische Code-Blocks (>=8 Zeilen)
  );

  // SonarQube-aehnliche Kategorisierung der Befunde:
  //   ftBug             - falsches Verhalten (Crash, falsches Ergebnis)
  //   ftCodeSmell       - Wartbarkeit / Lesbarkeit, kein Bug
  //   ftVulnerability   - Sicherheitsluecke
  //   ftSecurityHotspot - sicherheitsrelevant, im Einzelfall pruefen
  //   ftCodeDuplication - kopierter / nicht extrahierter Code
  //   ftFileError       - Sonderfall: Parser/IO-Fehler, kein Code-Befund
  TFindingType = (
    ftBug,
    ftCodeSmell,
    ftVulnerability,
    ftSecurityHotspot,
    ftCodeDuplication,
    ftFileError
  );

  // Pro-Kind-Metadaten: Name-Token (fuer Export, Suppression-Marker,
  // Claude-Prompt) plus die SonarQube-Kategorisierung. Single source
  // of truth - vorher waren diese Mappings in 4 Units (uMethodd12,
  // uExport, uClaudePrompt, uSuppression) als case-Statements
  // dupliziert und konnten gegeneinander driften.
  // Index = TFindingKind ordinal -> O(1)-Lookup.
  TFindingKindMeta = record
    Name        : string;       // 'MemoryLeak' (canonical token)
    FindingType : TFindingType; // Sonar-Kategorie
  end;

  TConsts = record
    class function GetLeakyClasses: TStringList; static;
  end;

const
  // Reihenfolge MUSS exakt mit TFindingKind uebereinstimmen.
  // Beim Hinzufuegen eines neuen TFindingKind: hier nachpflegen, dann
  // den eigentlichen Detektor in TStaticAnalyzer2.RunAllDetectors
  // registrieren - das sind die einzigen zwei Stellen.
  KIND_META: array[TFindingKind] of TFindingKindMeta = (
    (Name: 'MemoryLeak';      FindingType: ftBug),              // fkMemoryLeak
    (Name: 'EmptyExcept';     FindingType: ftCodeSmell),        // fkEmptyExcept
    (Name: 'SQLInjection';    FindingType: ftVulnerability),    // fkSQLInjection
    (Name: 'HardcodedSecret'; FindingType: ftVulnerability),    // fkHardcodedSecret
    (Name: 'FormatMismatch';  FindingType: ftBug),              // fkFormatMismatch
    (Name: 'FileReadError';   FindingType: ftFileError),        // fkFileReadError
    (Name: 'UnusedUses';      FindingType: ftCodeSmell),        // fkUnusedUses
    (Name: 'NilDeref';        FindingType: ftBug),              // fkNilDeref
    (Name: 'MissingFinally';  FindingType: ftCodeSmell),        // fkMissingFinally
    (Name: 'DivByZero';       FindingType: ftBug),              // fkDivByZero
    (Name: 'DeadCode';        FindingType: ftCodeSmell),        // fkDeadCode
    (Name: 'LongMethod';      FindingType: ftCodeSmell),        // fkLongMethod
    (Name: 'LongParamList';   FindingType: ftCodeSmell),        // fkLongParamList
    (Name: 'MagicNumber';     FindingType: ftCodeSmell),        // fkMagicNumber
    (Name: 'DuplicateString'; FindingType: ftCodeDuplication),  // fkDuplicateString
    (Name: 'HardcodedPath';   FindingType: ftSecurityHotspot),  // fkHardcodedPath
    (Name: 'DebugOutput';     FindingType: ftCodeSmell),        // fkDebugOutput
    (Name: 'DeepNesting';     FindingType: ftCodeSmell),        // fkDeepNesting
    (Name: 'TodoComment';     FindingType: ftCodeSmell),        // fkTodoComment
    (Name: 'EmptyMethod';     FindingType: ftCodeSmell),        // fkEmptyMethod
    (Name: 'DuplicateBlock';  FindingType: ftCodeDuplication)   // fkDuplicateBlock
  );

// Convenience-Wrapper - delegieren auf KIND_META.
function KindName(K: TFindingKind): string;
function KindFindingType(K: TFindingKind): TFindingType;
// Reverse-Lookup ueber Name (case-insensitive). Liefert False bei
// unbekanntem Namen; Kind ist dann undefiniert.
function KindFromName(const Name: string; out K: TFindingKind): Boolean;

type
  TSectionFlag = record
  const
    FLAG_NONE = $00;     // 00000000
    FLAG_Unit = $01;     // 00000001
    FLAG_interface = $02;// 00000010
    FLAG_uses = $04;     // 00000100
    FLAG_type = $08;     // 00001000
    FLAG_method = $10;   // 00010000
    FLAG_var = $20;      // 00100000
    FLAG_ignore = $40;   // 01000000     !!!!!!!!!!!!!
    FLAG_implementation = $80; // 10000000
    FLAG_ALL = $FF; // 11111111 (Alle Bits gesetzt)
  end;

implementation

{ ---- KIND_META Helpers ---- }

function KindName(K: TFindingKind): string;
begin
  Result := KIND_META[K].Name;
end;

function KindFindingType(K: TFindingKind): TFindingType;
begin
  Result := KIND_META[K].FindingType;
end;

function KindFromName(const Name: string; out K: TFindingKind): Boolean;
var
  Trimmed : string;
  Kk      : TFindingKind;
begin
  Trimmed := Trim(Name);
  for Kk := Low(TFindingKind) to High(TFindingKind) do
    if SameText(Trimmed, KIND_META[Kk].Name) then
    begin
      K := Kk;
      Exit(True);
    end;
  Result := False;
end;

{ TConsts }

// Liefert eine KOPIE der aktuellen Liste (Aufrufer freigibt).
// Vorher: kopierte das fixe Array; jetzt: kopiert die Live-StringList.
class function TConsts.GetLeakyClasses: TStringList;
begin
  Result := TStringList.Create;
  Result.CaseSensitive := False;
  if Assigned(LeakyClasses) then
    Result.AddStrings(LeakyClasses);
end;

procedure InitDefaultLeakyClasses;
const
  DEFAULTS: array of string = [
    'TStringList', 'TList', 'TObjectList',
    'TDictionary', 'TObjectDictionary',
    'TStringBuilder',
    'TOracleQuery', 'TOracleSession',
    'TQuery', 'TSQLQuery', 'TKSQLQuery',
    'TFileStream', 'TMemoryStream', 'TStringStream', 'TResourceStream',
    'TBitmap', 'TFont',
    'TThread', 'TComponent', 'TDataSet',
    'TSocket', 'TRegistry',
    'TXMLDocument', 'THTTPClient',
    'TTimer', 'TIniFile', 'TMemIniFile',
    'TStreamReader', 'TStreamWriter', 'TZipFile'
  ];
begin
  LeakyClasses := TStringList.Create;
  LeakyClasses.CaseSensitive := False;
  LeakyClasses.Sorted        := True;
  LeakyClasses.Duplicates    := dupIgnore;
  LeakyClasses.AddStrings(DEFAULTS);

  LeakyClassExcludes := TStringList.Create;
  LeakyClassExcludes.CaseSensitive := False;
  LeakyClassExcludes.Sorted        := True;
  LeakyClassExcludes.Duplicates    := dupIgnore;

  DiscoveredClasses := TStringList.Create;
  DiscoveredClasses.CaseSensitive := False;
  DiscoveredClasses.Sorted        := True;
  DiscoveredClasses.Duplicates    := dupIgnore;

  DiscoveredStaticClasses := TStringList.Create;
  DiscoveredStaticClasses.CaseSensitive := False;
  DiscoveredStaticClasses.Sorted        := True;
  DiscoveredStaticClasses.Duplicates    := dupIgnore;

  // Default-Trivial-Liste fuer uMagicNumbers.
  DetectorMagicTrivials := TStringList.Create;
  DetectorMagicTrivials.CaseSensitive := False;
  DetectorMagicTrivials.Sorted        := True;
  DetectorMagicTrivials.Duplicates    := dupIgnore;
  DetectorMagicTrivials.AddStrings(['0', '1', '2', '-1', '10', '100']);
end;

initialization
  InitDefaultLeakyClasses;

finalization
  if Assigned(LeakyClasses) then
    FreeAndNil(LeakyClasses);
  if Assigned(LeakyClassExcludes) then
    FreeAndNil(LeakyClassExcludes);
  if Assigned(DiscoveredClasses) then
    FreeAndNil(DiscoveredClasses);
  if Assigned(DiscoveredStaticClasses) then
    FreeAndNil(DiscoveredStaticClasses);
  if Assigned(DetectorMagicTrivials) then
    FreeAndNil(DetectorMagicTrivials);

end.

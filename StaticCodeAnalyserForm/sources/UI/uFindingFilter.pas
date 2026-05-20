unit uFindingFilter;

// Filter- und Sortier-Logik fuer die Befund-Liste der Analyser-UI.
//
// Vorher inline in TAnalyserFrame.ApplyFilter (~180 Zeilen) - jetzt
// extrahiert in zwei zustandslose Klassen:
//   * TFindingFilter.Matches  - Predicate (Severity/Kind/Type/Search)
//   * TFindingSorter.Sort     - Spalten-basierte Sortierung mit
//                               deterministischer Sekundaer-Sortierung.
//
// Die UI-spezifische Grid-Befuellung und Statusbar-Aktualisierung
// bleiben in der Frame - diese Unit kennt weder TStringGrid noch
// die Combo-Controls.
//
// Enthaelt auch die TFilterMode/TTypeFilter-Enums die bisher in
// uIDEAnalyserForm.pas lebten (mit dem Filter wandern auch die Typen).

interface

uses
  System.Generics.Collections,
  uMethodd12,        // TLeakFinding
  uSCAConsts;        // TFindingKind, TFindingType, TLeakSeverity

type
  // Welche Befund-Auswahl die Combo "Filter" zeigt.
  // Schweregrad-Gruppen + ein Eintrag pro Detektor-Kind.
  TFilterMode = (fmAll,
                 // Schweregrad-Gruppen
                 fmErrors, fmWarnings, fmHints,
                 // Fehler-Detektoren
                 fmMemoryLeak,
                 fmSQLInjection, fmHardcodedSecret, fmFormatMismatch,
                 fmNilDeref, fmDivByZero,
                 // Visibility (single-file)
                 fmCanBeUnitPrivate, fmCanBeStrictPrivate,
                 fmCanBeProtected, fmUnusedPublicMember,
                 // Korrektheits-Detektoren (neue Generation)
                 fmUnusedLocalVar, fmUnusedParameter, fmTautologicalBoolExpr,
                 // DFM Phase 4
                 fmDfmMasterDetailUnlinked, fmDfmDataModuleSplitHint,
                 // mORMot2 Real-World-Review Bugs
                 fmSqlDangerousStatement, fmFormatLocaleHint,
                 // Warnungs-Detektoren
                 fmEmptyExcept, fmMissingFinally, fmDeadCode,
                 fmUnusedUses, fmDebugOutput, fmHardcodedPath,
                 fmFileReadError,
                 // Hinweis-Detektoren
                 fmLongMethod, fmLongParamList, fmMagicNumber,
                 fmDuplicateString, fmDeepNesting,
                 fmTodoComment, fmEmptyMethod, fmDuplicateBlock,
                 fmCyclomaticComplexity,
                 // Concurrency-Familie (SCA108+)
                 fmSynchronizeInDestructor, fmLockWithoutTryFinally,
                 // SonarDelphi-Migration (SCA120-131)
                 fmMissingRaise, fmRoutineResultUnassigned,
                 fmReRaiseException, fmCastAndFree,
                 fmInstanceInvokedConstructor, fmInheritedMethodEmpty,
                 fmNilComparison, fmRaisingRawException,
                 fmDateFormatSettings, fmUnicodeToAnsiCast,
                 fmCharToCharPointerCast, fmIfThenShortCircuit,
                 // Sonar-50 Critical (SCA132-137)
                 fmExceptionTooGeneral, fmRaiseOutsideExcept,
                 fmUseAfterFree, fmAbstractNotImpl,
                 fmLeakInConstructor, fmIntegerOverflow);

  // Zweiter Filter (orthogonal zu Schweregrad): Sonar-Typ-Kategorie.
  TTypeFilter = (tfAll, tfBug, tfCodeSmell, tfVulnerability,
                 tfSecurityHotspot, tfCodeDuplication);

  // Filter-Eingabe: alle drei Kriterien zusammen.
  // SearchLow: bereits getrimmt + lowercased (der Aufrufer macht das einmal,
  // der Predicate-Aufruf bleibt billig).
  TFindingFilterCriteria = record
    Mode       : TFilterMode;
    TypeFilter : TTypeFilter;
    SearchLow  : string;
  end;

  // Sort-Konfiguration. Column = -1 -> keine Sortierung, Liste bleibt
  // in der Original-Reihenfolge (FAllFindings).
  // BaseDir wird fuer relative Datei-Schluessel benutzt damit die
  // Sortierung mit dem im Grid angezeigten Pfad uebereinstimmt.
  TFindingSortConfig = record
    Column     : Integer;
    Descending : Boolean;
    BaseDir    : string;
  end;

  TFindingFilter = class
  public
    // True wenn F unter Criteria im Grid erscheinen soll.
    class function Matches(const F: TLeakFinding;
      const C: TFindingFilterCriteria): Boolean; static;
  end;

  TFindingSorter = class
  public
    // In-place Sort. Bei Column < 0 keine Aenderung.
    class procedure Sort(List: TList<TLeakFinding>;
      const Config: TFindingSortConfig); static;
  end;

implementation

uses
  System.SysUtils, System.Generics.Defaults,
  uAnalyserTypes;    // SeverityFromText, TFindingSeverity

// Such-Schluesselworte pro Kind. Enthaelt sowohl die englische als auch
// die deutsche Bezeichnung damit der User unabhaengig von der UI-Sprache
// nach dem fuehlenden Begriff suchen kann (z.B. 'Memory' oder
// 'Speicherleck' findet beides Memory-Leaks).
function KindSearchKeywords(Kind: TFindingKind): string;
begin
  case Kind of
    fkMemoryLeak       : Result := 'memory leak speicherleck';
    fkCanBeUnitPrivate : Result := 'private unit encapsulation visibility kapselung sichtbarkeit';
    fkCanBeStrictPrivate: Result := 'strict private class encapsulation visibility kapselung klasse';
    fkCanBeProtected   : Result := 'protected encapsulation visibility kapselung subclass';
    fkUnusedPublicMember : Result := 'unused public api dead api ungenutzt';
    fkUnusedLocalVar   : Result := 'unused local variable lokale ungenutzt';
    fkUnusedParameter  : Result := 'unused parameter parameter ungenutzt';
    fkTautologicalBoolExpr : Result := 'tautological boolean copy paste lhs rhs identical';
    fkDfmMasterDetailUnlinked : Result := 'master detail unlinked cross join cartesian masterfields';
    fkDfmDataModuleSplitHint  : Result := 'datamodule split refactor aggregate db';
    fkSqlDangerousStatement   : Result := 'sql dangerous update delete truncate without where alle';
    fkFormatLocaleHint        : Result := 'format locale tformatsettings decimal komma punkt';
    fkSynchronizeInDestructor : Result := 'synchronize destructor deadlock thread concurrency';
    fkLockWithoutTryFinally   : Result := 'lock critical section monitor concurrency try finally exception';
    fkEmptyExcept      : Result := 'empty except leer verschluckt';
    fkSQLInjection     : Result := 'sql injection einschleusung';
    fkHardcodedSecret  : Result := 'hardcoded secret password token kennwort';
    fkFormatMismatch   : Result := 'format mismatch platzhalter';
    fkFileReadError    : Result := 'read error lesefehler parser';
    fkUnusedUses       : Result := 'unused uses ungenutzt';
    fkNilDeref         : Result := 'nil dereference null';
    fkMissingFinally   : Result := 'missing finally fehlend';
    fkDivByZero        : Result := 'div divide by zero teilung null';
    fkDeadCode         : Result := 'dead unreachable code toter';
    fkLongMethod       : Result := 'long method lange methode';
    fkLongParamList    : Result := 'long parameter list parameterliste';
    fkMagicNumber      : Result := 'magic number magische zahl';
    fkDuplicateString  : Result := 'duplicate string doppelte';
    fkHardcodedPath    : Result := 'hardcoded path pfad';
    fkDebugOutput      : Result := 'debug output writeln showmessage ausgabe';
    fkDeepNesting      : Result := 'deep nesting tiefe verschachtelung';
    fkCyclomaticComplexity : Result := 'cyclomatic complexity mccabe komplexitaet verzweigung';
    fkTodoComment      : Result := 'todo fixme hack xxx kommentar comment';
    fkEmptyMethod      : Result := 'empty method leere methode';
    fkDuplicateBlock   : Result := 'duplicate block doppelter';
    // SonarDelphi-Migration (SCA120-131)
    fkMissingRaise               : Result := 'missing raise exception create fehlt';
    fkRoutineResultUnassigned    : Result := 'result unassigned function rueckgabe nicht zugewiesen';
    fkReRaiseException           : Result := 'reraise exception stack trace stacktrace verloren';
    fkCastAndFree                : Result := 'cast free destroy redundant typumwandlung';
    fkInstanceInvokedConstructor : Result := 'instance invoked constructor create new auf objekt';
    fkInheritedMethodEmpty       : Result := 'inherited empty leer override leeres';
    fkNilComparison              : Result := 'nil comparison assigned vergleich null';
    fkRaisingRawException        : Result := 'raising raw exception basisklasse base';
    fkDateFormatSettings         : Result := 'date format settings locale strtodate strtofloat';
    fkUnicodeToAnsiCast          : Result := 'unicode ansi cast utf8 encoding datenverlust';
    fkCharToCharPointerCast      : Result := 'char pchar pointer cast codepoint adresse';
    fkIfThenShortCircuit         : Result := 'ifthen short circuit math strutils kurzschluss';
    // Sonar-50 Critical (SCA132-137)
    fkExceptionTooGeneral        : Result := 'exception too general base basisklasse fanger handler catch';
    fkRaiseOutsideExcept         : Result := 'raise outside except bare nackt access violation av';
    fkUseAfterFree               : Result := 'use after free dangling pointer benutzt nach freigabe';
    fkAbstractNotImpl            : Result := 'abstract not implemented eabstracterror nicht ueberschrieben override';
    fkLeakInConstructor          : Result := 'leak constructor raise field create exception partial init';
    fkIntegerOverflow            : Result := 'integer overflow int64 multiplication ueberlauf product cast';
  else
    Result := '';
  end;
end;

// ---------------------------------------------------------------------------
// TFindingFilter
// ---------------------------------------------------------------------------
class function TFindingFilter.Matches(const F: TLeakFinding;
  const C: TFindingFilterCriteria): Boolean;
var
  Sev         : TFindingSeverity;
  fileNameLow : string;
begin
  // 1) Schweregrad-/Kind-Filter - direkter Enum-Pfad, kein String-Roundtrip
  Sev := SeverityFromKindLevel(F.Kind, F.Severity);
  case C.Mode of
    fmErrors:          Result := Sev = fsError;
    fmWarnings:        Result := Sev = fsWarning;
    fmHints:           Result := Sev = fsHint;
    fmMemoryLeak:      Result := F.Kind = fkMemoryLeak;
    fmCanBeUnitPrivate:    Result := F.Kind = fkCanBeUnitPrivate;
    fmCanBeStrictPrivate:  Result := F.Kind = fkCanBeStrictPrivate;
    fmCanBeProtected:      Result := F.Kind = fkCanBeProtected;
    fmUnusedPublicMember:  Result := F.Kind = fkUnusedPublicMember;
    fmUnusedLocalVar:      Result := F.Kind = fkUnusedLocalVar;
    fmUnusedParameter:     Result := F.Kind = fkUnusedParameter;
    fmTautologicalBoolExpr:Result := F.Kind = fkTautologicalBoolExpr;
    fmDfmMasterDetailUnlinked: Result := F.Kind = fkDfmMasterDetailUnlinked;
    fmDfmDataModuleSplitHint:  Result := F.Kind = fkDfmDataModuleSplitHint;
    fmSqlDangerousStatement:   Result := F.Kind = fkSqlDangerousStatement;
    fmFormatLocaleHint:        Result := F.Kind = fkFormatLocaleHint;
    fmSynchronizeInDestructor: Result := F.Kind = fkSynchronizeInDestructor;
    fmLockWithoutTryFinally:   Result := F.Kind = fkLockWithoutTryFinally;
    fmEmptyExcept:     Result := F.Kind = fkEmptyExcept;
    fmSQLInjection:    Result := F.Kind = fkSQLInjection;
    fmHardcodedSecret: Result := F.Kind = fkHardcodedSecret;
    fmFormatMismatch:  Result := F.Kind = fkFormatMismatch;
    fmFileReadError:   Result := F.Kind = fkFileReadError;
    fmUnusedUses:      Result := F.Kind = fkUnusedUses;
    fmNilDeref:        Result := F.Kind = fkNilDeref;
    fmMissingFinally:  Result := F.Kind = fkMissingFinally;
    fmDivByZero:       Result := F.Kind = fkDivByZero;
    fmDeadCode:        Result := F.Kind = fkDeadCode;
    fmLongMethod:      Result := F.Kind = fkLongMethod;
    fmLongParamList:   Result := F.Kind = fkLongParamList;
    fmMagicNumber:     Result := F.Kind = fkMagicNumber;
    fmDuplicateString: Result := F.Kind = fkDuplicateString;
    fmDuplicateBlock:  Result := F.Kind = fkDuplicateBlock;
    fmHardcodedPath:   Result := F.Kind = fkHardcodedPath;
    fmDebugOutput:     Result := F.Kind = fkDebugOutput;
    fmDeepNesting:     Result := F.Kind = fkDeepNesting;
    fmCyclomaticComplexity: Result := F.Kind = fkCyclomaticComplexity;
    fmTodoComment:     Result := F.Kind = fkTodoComment;
    fmEmptyMethod:     Result := F.Kind = fkEmptyMethod;
    // SonarDelphi-Migration (SCA120-131)
    fmMissingRaise:              Result := F.Kind = fkMissingRaise;
    fmRoutineResultUnassigned:   Result := F.Kind = fkRoutineResultUnassigned;
    fmReRaiseException:          Result := F.Kind = fkReRaiseException;
    fmCastAndFree:               Result := F.Kind = fkCastAndFree;
    fmInstanceInvokedConstructor:Result := F.Kind = fkInstanceInvokedConstructor;
    fmInheritedMethodEmpty:      Result := F.Kind = fkInheritedMethodEmpty;
    fmNilComparison:             Result := F.Kind = fkNilComparison;
    fmRaisingRawException:       Result := F.Kind = fkRaisingRawException;
    fmDateFormatSettings:        Result := F.Kind = fkDateFormatSettings;
    fmUnicodeToAnsiCast:         Result := F.Kind = fkUnicodeToAnsiCast;
    fmCharToCharPointerCast:     Result := F.Kind = fkCharToCharPointerCast;
    fmIfThenShortCircuit:        Result := F.Kind = fkIfThenShortCircuit;
    // Sonar-50 Critical (SCA132-137)
    fmExceptionTooGeneral:       Result := F.Kind = fkExceptionTooGeneral;
    fmRaiseOutsideExcept:        Result := F.Kind = fkRaiseOutsideExcept;
    fmUseAfterFree:              Result := F.Kind = fkUseAfterFree;
    fmAbstractNotImpl:           Result := F.Kind = fkAbstractNotImpl;
    fmLeakInConstructor:         Result := F.Kind = fkLeakInConstructor;
    fmIntegerOverflow:           Result := F.Kind = fkIntegerOverflow;
  else
    Result := True;   // fmAll
  end;
  if not Result then Exit;

  // 2) Type-Filter (orthogonal)
  case C.TypeFilter of
    tfBug             : if F.FindingType <> ftBug             then Exit(False);
    tfCodeSmell       : if F.FindingType <> ftCodeSmell       then Exit(False);
    tfVulnerability   : if F.FindingType <> ftVulnerability   then Exit(False);
    tfSecurityHotspot : if F.FindingType <> ftSecurityHotspot then Exit(False);
    tfCodeDuplication : if F.FindingType <> ftCodeDuplication then Exit(False);
    tfAll             : ; // alle Typen passen
  end;

  // 3) Suche - matcht gegen alle sichtbaren Grid-Spalten und zusaetzlich
  //    gegen Kind-Schluesselworte (DE + EN). Damit findet "Memory" alle
  //    Memory-Leaks, "TStringList" alle Befunde wo der Klassenname im
  //    Methoden- oder Variablennamen steckt, "Bug" alle ftBug-Befunde.
  if C.SearchLow <> '' then
  begin
    fileNameLow := ExtractFileName(F.FileName).ToLower;
    if (Pos(C.SearchLow, fileNameLow)                 = 0) and
       (Pos(C.SearchLow, F.FileName.ToLower)          = 0) and
       (Pos(C.SearchLow, F.MethodName.ToLower)        = 0) and
       (Pos(C.SearchLow, F.LineNumber.ToLower)        = 0) and
       (Pos(C.SearchLow, F.TypeText.ToLower)          = 0) and
       (Pos(C.SearchLow, F.MissingVar.ToLower)        = 0) and
       (Pos(C.SearchLow, F.SeverityText.ToLower)      = 0) and
       (Pos(C.SearchLow, KindSearchKeywords(F.Kind))  = 0) then
      Exit(False);
  end;

  Result := True;
end;

// ---------------------------------------------------------------------------
// TFindingSorter
// ---------------------------------------------------------------------------

// Severity-Rang fuer die Sortierung der "Schweregrad"-Spalte.
// Reihenfolge: Error < Warning < Hint < FileError < Unknown.
function SeverityRank(const Sev: string): Integer;
begin
  case SeverityFromText(Sev) of
    fsError:     Result := 0;
    fsWarning:   Result := 1;
    fsHint:      Result := 2;
    fsFileError: Result := 3;
  else
    Result := 4;
  end;
end;

// Datei-Sortier-Schluessel - relativ zur BaseDir wenn moeglich,
// sonst Basename. Damit sortiert die Spalte wie im Grid sichtbar.
function FileKey(const F: TLeakFinding; const BaseDir: string): string;
begin
  if BaseDir <> '' then
    Result := ExtractRelativePath(IncludeTrailingPathDelimiter(BaseDir),
                                  F.FileName)
  else
    Result := ExtractFileName(F.FileName);
end;

class procedure TFindingSorter.Sort(List: TList<TLeakFinding>;
  const Config: TFindingSortConfig);
var
  CapturedCfg: TFindingSortConfig;
begin
  if Config.Column < 0 then Exit;

  // Capture per Wert in lokale Var, damit der anonyme Vergleicher
  // nicht den Param-Const-Slot referenziert (lebt nur fuer die
  // Methode, nicht fuer die Closure).
  CapturedCfg := Config;
  List.Sort(TComparer<TLeakFinding>.Construct(
    function(const A, B: TLeakFinding): Integer
    var
      SA, SB: string;
    begin
      case CapturedCfg.Column of
        0: Result := CompareText(FileKey(A, CapturedCfg.BaseDir),
                                 FileKey(B, CapturedCfg.BaseDir));
        1: Result := CompareText(A.MethodName, B.MethodName);
        2: Result := StrToIntDef(A.LineNumber, 0)
                   - StrToIntDef(B.LineNumber, 0);
        3: Result := CompareText(A.TypeText, B.TypeText);
        4: Result := CompareText(A.MissingVar, B.MissingVar);
        5: Result := SeverityRank(A.SeverityText)
                   - SeverityRank(B.SeverityText);
      else
        Result := 0;
      end;
      if CapturedCfg.Descending then Result := -Result;

      // Sekundaer-Sortierung (immer aufsteigend) damit Reihenfolge
      // bei gleichem Primaerschluessel deterministisch ist.
      if Result = 0 then
      begin
        SA := FileKey(A, CapturedCfg.BaseDir);
        SB := FileKey(B, CapturedCfg.BaseDir);
        Result := CompareText(SA, SB);
        if Result = 0 then
          Result := StrToIntDef(A.LineNumber, 0)
                  - StrToIntDef(B.LineNumber, 0);
      end;
    end));
end;

end.

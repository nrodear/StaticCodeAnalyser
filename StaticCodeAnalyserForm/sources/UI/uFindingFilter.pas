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
  // fmDetectorReview ist ein Spezial-Modus: Matches selbst kennt ihn nicht,
  // weil er stateful ist (ein Sample pro Kind ueber die ganze Liste). Die
  // ApplyFilter-Methode in den Forms behandelt ihn ueber einen separaten
  // Branch und ruft Matches gar nicht erst auf - siehe Kommentar dort.
  TFilterMode = (fmAll,
                 // Spezial: Detector-Review-Stichprobe (1 zufaelliger Befund
                 // pro Detector-Kind, ueber die gesamte Liste).
                 fmDetectorReview,
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
                 fmLeakInConstructor, fmIntegerOverflow,
                 fmGodClass, fmFreeWithoutNil, fmMultipleExit,
                 fmLargeClass, fmUnsortedUses, fmMissingUnitHeader,
                 fmFloatEquality, fmExceptInDestructor, fmBooleanParam,
                 fmUnusedPrivateMethod, fmCanBeClassMethod, fmMissingOverride,
                 fmBoolAlwaysTrue, fmConstantReturn, fmHardcodedString,
                 // P6-Nachzug: alle bisher uebersprungenen fk-Kinds bekommen
                 // ihren fm-Filter (DFM-Cluster + SonarDelphi-Migration +
                 // diverse Sonar-Naming/Formatting-Detektoren).
                 fmAssertMessage, fmAssignedAndAssignedNil, fmAvoidOut,
                 fmBeginEndRequired, fmCaseStatementSize,
                 fmClassPerFile, fmCommentedOutCode, fmConcatToFormat,
                 fmConsecutiveSection, fmConsecutiveVisibility,
                 fmConstructorWithoutInherited, fmDestructorWithoutInherited,
                 fmDfmActionMismatch, fmDfmCircularDataSource,
                 fmDfmCrossFormCoupling, fmDfmDbInUiForm, fmDfmDeadEvent,
                 fmDfmDefaultName, fmDfmDuplicateBinding,
                 fmDfmEmptyBoundEvent, fmDfmFieldTypeMismatch,
                 fmDfmForbiddenClass, fmDfmGodHandler,
                 fmDfmHardcodedCaption, fmDfmHardcodedDbCreds,
                 fmDfmLayerViolation, fmDfmOrphanHandler,
                 fmDfmRequiredFieldNotVisible, fmDfmRequiredFieldUnbound,
                 fmDfmSchemaMismatch, fmDfmSqlFromUserInput,
                 fmDfmTabOrderConflict, fmDigitGrouping,
                 fmDisabledTlsVerification, fmEmptyArgumentList,
                 fmEmptyBlock, fmEmptyFile, fmEmptyFinallyBlock,
                 fmEmptyInterface, fmEmptyVisibilitySection,
                 fmExceptOnException, fmExceptionName,
                 fmExplicitTObjectInheritance, fmFieldByNameInLoop,
                 fmFieldName, fmFreeAndNilHint, fmGotoStatement,
                 fmGroupedDeclaration, fmHttpInsteadOfHttps,
                 fmIfElseBegin, fmInlineAssembly, fmInterfaceName,
                 fmLegacyInitializationSection, fmLengthUnderflow,
                 fmLocalConstantName, fmLowercaseKeyword, fmMethodName,
                 fmNestedRoutine, fmNestedTry, fmParamByNameInLoop,
                 fmPointerName, fmPublicField, fmPublicMemberWithoutDoc,
                 fmRedundantBoolean, fmRedundantConditional,
                 fmRedundantJump, fmRedundantParentheses,
                 fmReversedForRange, fmSelfAssignment,
                 fmStringConcatInLoop, fmSuperfluousSemicolon,
                 fmTThreadDestroyWithoutTerminate, fmTabulationCharacter,
                 fmThreadResumeDeprecated, fmTooLongLine,
                 fmTrailingCommaArgList, fmTrailingWhitespace,
                 fmTwiceInheritedCalls, fmTypeName,
                 fmUnitLevelKeywordIndent, fmVirtualCallInCtor,
                 fmWithStatement,
                 // mORMot-Cluster (SCA153-155)
                 fmUnpairedLock, fmMoveSizeOfPointer,
                 fmWithMultipleTargets,
                 // mORMot-Cluster Phase 2 (SCA156-158)
                 fmGetMemWithoutFreeMem, fmSetLengthAppendInLoop,
                 fmPointerArithmeticOnString,
                 // mORMot-Cluster Phase 3 (SCA159-161)
                 fmEmptyOnHandler, fmStringFromPointer,
                 fmPointerSubtraction);

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
    fkGodClass                   : Result := 'god class methods fields gott zu viele single responsibility';
    fkFreeWithoutNil             : Result := 'free without nil dangling pointer freeandnil';
    fkMultipleExit               : Result := 'multiple exit return points pfad ausgang';
    fkLargeClass                 : Result := 'large class lines zu lang aufteilen';
    fkUnsortedUses               : Result := 'unsorted uses alphabetical sortierung reihenfolge';
    fkMissingUnitHeader          : Result := 'missing unit header comment kommentar beschreibung';
    fkFloatEquality              : Result := 'float equality double single ieee rounding rundung gleichheit';
    fkExceptInDestructor         : Result := 'exception destructor cleanup destroy aufraeumen';
    fkBooleanParam               : Result := 'boolean parameter flag branching steuerflag';
    fkUnusedPrivateMethod        : Result := 'unused private method ungenutzt totcode dead';
    fkCanBeClassMethod           : Result := 'class method static self klassenmethode';
    fkMissingOverride            : Result := 'override missing virtual w1010 polymorphie';
    fkBoolAlwaysTrue             : Result := 'always true false boolean length tautologie';
    fkConstantReturn             : Result := 'constant return same value literal konstante';
    fkHardcodedString            : Result := 'hardcoded string caption hint text resourcestring i18n';
    // P6-Nachzug
    fkAssertMessage              : Result := 'assert message zusicherung meldung';
    fkAssignedAndAssignedNil     : Result := 'assigned nil redundant doppel pruefung';
    fkAvoidOut                   : Result := 'avoid out parameter vermeiden';
    fkBeginEndRequired           : Result := 'begin end required block klammer';
    fkCaseStatementSize          : Result := 'case statement long lang anweisung';
    fkClassPerFile               : Result := 'class per file klasse datei';
    fkCommentedOutCode           : Result := 'commented out code auskommentiert tot';
    fkConcatToFormat             : Result := 'concat format string concatenation verkettung';
    fkConsecutiveSection         : Result := 'consecutive section var const aufeinanderfolgend doppel';
    fkConsecutiveVisibility      : Result := 'consecutive visibility public private aufeinanderfolgend';
    fkConstructorWithoutInherited: Result := 'constructor inherited fehlend konstruktor';
    fkDestructorWithoutInherited : Result := 'destructor inherited fehlend destruktor';
    fkDfmActionMismatch          : Result := 'dfm action onclick mismatch konflikt';
    fkDfmCircularDataSource      : Result := 'dfm circular datasource master cycle zyklus';
    fkDfmCrossFormCoupling       : Result := 'dfm cross form coupling global kopplung';
    fkDfmDbInUiForm              : Result := 'dfm database ui form datenbank';
    fkDfmDeadEvent               : Result := 'dfm dead event onclick handler tot';
    fkDfmDefaultName             : Result := 'dfm default name button1 edit2 default';
    fkDfmDuplicateBinding        : Result := 'dfm duplicate binding event copy paste doppel';
    fkDfmEmptyBoundEvent         : Result := 'dfm empty bound event leer handler';
    fkDfmFieldTypeMismatch       : Result := 'dfm field type mismatch ftblob tdbedit';
    fkDfmForbiddenClass          : Result := 'dfm forbidden class verboten';
    fkDfmGodHandler              : Result := 'dfm god handler many events viele';
    fkDfmHardcodedCaption        : Result := 'dfm hardcoded caption resourcestring i18n';
    fkDfmHardcodedDbCreds        : Result := 'dfm hardcoded db credentials password';
    fkDfmLayerViolation          : Result := 'dfm layer violation panel container';
    fkDfmOrphanHandler           : Result := 'dfm orphan handler unbound waise';
    fkDfmRequiredFieldNotVisible : Result := 'dfm required field tab versteckt';
    fkDfmRequiredFieldUnbound    : Result := 'dfm required field unbound ungebunden';
    fkDfmSchemaMismatch          : Result := 'dfm schema mismatch field published';
    fkDfmSqlFromUserInput        : Result := 'dfm sql user input injection eingabe';
    fkDfmTabOrderConflict        : Result := 'dfm tab order conflict reihenfolge';
    fkDigitGrouping              : Result := 'digit grouping underscore ziffern gruppierung';
    fkDisabledTlsVerification    : Result := 'disabled tls verification ssl zertifikat verifikation';
    fkEmptyArgumentList          : Result := 'empty argument list leere klammer';
    fkEmptyBlock                 : Result := 'empty block leerer';
    fkEmptyFile                  : Result := 'empty file leere datei';
    fkEmptyFinallyBlock          : Result := 'empty finally block leerer';
    fkEmptyInterface             : Result := 'empty interface leeres marker';
    fkEmptyVisibilitySection     : Result := 'empty visibility section leerer sichtbarkeit';
    fkExceptOnException          : Result := 'except on exception generic generisch';
    fkExceptionName              : Result := 'exception name e-prefix benennung';
    fkExplicitTObjectInheritance : Result := 'tobject inheritance explicit redundant doppel';
    fkFieldByNameInLoop          : Result := 'fieldbyname loop schleife performance';
    fkFieldName                  : Result := 'field name f-prefix feldname';
    fkFreeAndNilHint             : Result := 'freeandnil hint hinweis';
    fkGotoStatement              : Result := 'goto statement label';
    fkGroupedDeclaration         : Result := 'grouped declaration sammeldeklaration';
    fkHttpInsteadOfHttps         : Result := 'http https url tls plaintext';
    fkIfElseBegin                : Result := 'if else begin block stil';
    fkInlineAssembly             : Result := 'inline assembly asm';
    fkInterfaceName              : Result := 'interface name i-prefix benennung';
    fkLegacyInitializationSection: Result := 'legacy initialization section finalization veraltet';
    fkLengthUnderflow            : Result := 'length underflow count minus unterlauf';
    fkLocalConstantName          : Result := 'local constant name upper snake naming konstante';
    fkLowercaseKeyword           : Result := 'lowercase keyword case stil';
    fkMethodName                 : Result := 'method name camel pascal benennung';
    fkNestedRoutine              : Result := 'nested routine verschachtelt funktion';
    fkNestedTry                  : Result := 'nested try verschachtelt';
    fkParamByNameInLoop          : Result := 'parambyname loop schleife performance';
    fkPointerName                : Result := 'pointer name p-prefix benennung';
    fkPublicField                : Result := 'public field property feld';
    fkPublicMemberWithoutDoc     : Result := 'public documentation comment dokumentation';
    fkRedundantBoolean           : Result := 'redundant boolean true false vergleich';
    fkRedundantConditional       : Result := 'redundant conditional if true false';
    fkRedundantJump              : Result := 'redundant jump exit goto sprung';
    fkRedundantParentheses       : Result := 'redundant parentheses klammer';
    fkReversedForRange           : Result := 'reversed for range umkehrt schleife';
    fkSelfAssignment             : Result := 'self assignment selbst zuweisung';
    fkStringConcatInLoop         : Result := 'string concat loop schleife stringbuilder performance';
    fkSuperfluousSemicolon       : Result := 'superfluous semicolon ueberfluessig';
    fkTThreadDestroyWithoutTerminate: Result := 'tthread destroy terminate waitfor thread';
    fkTabulationCharacter        : Result := 'tabulation character tab whitespace einrueckung';
    fkThreadResumeDeprecated     : Result := 'thread resume deprecated veraltet start';
    fkTooLongLine                : Result := 'too long line zu lang zeile';
    fkTrailingCommaArgList       : Result := 'trailing comma argument list komma';
    fkTrailingWhitespace         : Result := 'trailing whitespace leerzeichen';
    fkTwiceInheritedCalls        : Result := 'twice inherited doppelt aufruf';
    fkTypeName                   : Result := 'type name t-prefix benennung';
    fkUnitLevelKeywordIndent     : Result := 'unit level keyword indent einrueckung';
    fkVirtualCallInCtor          : Result := 'virtual call constructor konstruktor aufruf';
    fkWithStatement              : Result := 'with statement gefaehrlich namenskonflikt';
    // mORMot-Cluster (SCA153-155)
    fkUnpairedLock               : Result := 'unpaired lock unlock enter leave critical section mutex synlocker mormot try finally';
    fkMoveSizeOfPointer          : Result := 'move fillchar copymemory sizeof pointer pbyte pinteger pcardinal pchar bug speicher';
    fkWithMultipleTargets        : Result := 'with multiple targets mehrere ziele namenskonflikt clash ambiguous';
    // mORMot-Cluster Phase 2 (SCA156-158)
    fkGetMemWithoutFreeMem       : Result := 'getmem allocmem reallocmem freemem speicher leak buffer try finally mormot';
    fkSetLengthAppendInLoop      : Result := 'setlength length loop schleife realloc grow quadratic performance dynamic array';
    fkPointerArithmeticOnString  : Result := 'pchar pansichar pwidechar pointer arithmetic offset empty string nil access violation';
    // mORMot-Cluster Phase 3 (SCA159-161)
    fkEmptyOnHandler             : Result := 'empty on exception handler typed silent swallow leer ausnahme typisiert';
    fkStringFromPointer          : Result := 'string ansistring utf8string rawbytestring pointer cast overread buffer p-prefix';
    fkPointerSubtraction         : Result := 'cardinal integer longword pointer subtraction win64 truncation ptruint nativeuint';
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
    fmGodClass:                  Result := F.Kind = fkGodClass;
    fmFreeWithoutNil:            Result := F.Kind = fkFreeWithoutNil;
    fmMultipleExit:              Result := F.Kind = fkMultipleExit;
    fmLargeClass:                Result := F.Kind = fkLargeClass;
    fmUnsortedUses:              Result := F.Kind = fkUnsortedUses;
    fmMissingUnitHeader:         Result := F.Kind = fkMissingUnitHeader;
    fmFloatEquality:             Result := F.Kind = fkFloatEquality;
    fmExceptInDestructor:        Result := F.Kind = fkExceptInDestructor;
    fmBooleanParam:              Result := F.Kind = fkBooleanParam;
    fmUnusedPrivateMethod:       Result := F.Kind = fkUnusedPrivateMethod;
    fmCanBeClassMethod:          Result := F.Kind = fkCanBeClassMethod;
    fmMissingOverride:           Result := F.Kind = fkMissingOverride;
    fmBoolAlwaysTrue:            Result := F.Kind = fkBoolAlwaysTrue;
    fmConstantReturn:            Result := F.Kind = fkConstantReturn;
    fmHardcodedString:           Result := F.Kind = fkHardcodedString;
    // P6-Nachzug
    fmAssertMessage:                 Result := F.Kind = fkAssertMessage;
    fmAssignedAndAssignedNil:        Result := F.Kind = fkAssignedAndAssignedNil;
    fmAvoidOut:                      Result := F.Kind = fkAvoidOut;
    fmBeginEndRequired:              Result := F.Kind = fkBeginEndRequired;
    fmCaseStatementSize:             Result := F.Kind = fkCaseStatementSize;
    fmClassPerFile:                  Result := F.Kind = fkClassPerFile;
    fmCommentedOutCode:              Result := F.Kind = fkCommentedOutCode;
    fmConcatToFormat:                Result := F.Kind = fkConcatToFormat;
    fmConsecutiveSection:            Result := F.Kind = fkConsecutiveSection;
    fmConsecutiveVisibility:         Result := F.Kind = fkConsecutiveVisibility;
    fmConstructorWithoutInherited:   Result := F.Kind = fkConstructorWithoutInherited;
    fmDestructorWithoutInherited:    Result := F.Kind = fkDestructorWithoutInherited;
    fmDfmActionMismatch:             Result := F.Kind = fkDfmActionMismatch;
    fmDfmCircularDataSource:         Result := F.Kind = fkDfmCircularDataSource;
    fmDfmCrossFormCoupling:          Result := F.Kind = fkDfmCrossFormCoupling;
    fmDfmDbInUiForm:                 Result := F.Kind = fkDfmDbInUiForm;
    fmDfmDeadEvent:                  Result := F.Kind = fkDfmDeadEvent;
    fmDfmDefaultName:                Result := F.Kind = fkDfmDefaultName;
    fmDfmDuplicateBinding:           Result := F.Kind = fkDfmDuplicateBinding;
    fmDfmEmptyBoundEvent:            Result := F.Kind = fkDfmEmptyBoundEvent;
    fmDfmFieldTypeMismatch:          Result := F.Kind = fkDfmFieldTypeMismatch;
    fmDfmForbiddenClass:             Result := F.Kind = fkDfmForbiddenClass;
    fmDfmGodHandler:                 Result := F.Kind = fkDfmGodHandler;
    fmDfmHardcodedCaption:           Result := F.Kind = fkDfmHardcodedCaption;
    fmDfmHardcodedDbCreds:           Result := F.Kind = fkDfmHardcodedDbCreds;
    fmDfmLayerViolation:             Result := F.Kind = fkDfmLayerViolation;
    fmDfmOrphanHandler:              Result := F.Kind = fkDfmOrphanHandler;
    fmDfmRequiredFieldNotVisible:    Result := F.Kind = fkDfmRequiredFieldNotVisible;
    fmDfmRequiredFieldUnbound:       Result := F.Kind = fkDfmRequiredFieldUnbound;
    fmDfmSchemaMismatch:             Result := F.Kind = fkDfmSchemaMismatch;
    fmDfmSqlFromUserInput:           Result := F.Kind = fkDfmSqlFromUserInput;
    fmDfmTabOrderConflict:           Result := F.Kind = fkDfmTabOrderConflict;
    fmDigitGrouping:                 Result := F.Kind = fkDigitGrouping;
    fmDisabledTlsVerification:       Result := F.Kind = fkDisabledTlsVerification;
    fmEmptyArgumentList:             Result := F.Kind = fkEmptyArgumentList;
    fmEmptyBlock:                    Result := F.Kind = fkEmptyBlock;
    fmEmptyFile:                     Result := F.Kind = fkEmptyFile;
    fmEmptyFinallyBlock:             Result := F.Kind = fkEmptyFinallyBlock;
    fmEmptyInterface:                Result := F.Kind = fkEmptyInterface;
    fmEmptyVisibilitySection:        Result := F.Kind = fkEmptyVisibilitySection;
    fmExceptOnException:             Result := F.Kind = fkExceptOnException;
    fmExceptionName:                 Result := F.Kind = fkExceptionName;
    fmExplicitTObjectInheritance:    Result := F.Kind = fkExplicitTObjectInheritance;
    fmFieldByNameInLoop:             Result := F.Kind = fkFieldByNameInLoop;
    fmFieldName:                     Result := F.Kind = fkFieldName;
    fmFreeAndNilHint:                Result := F.Kind = fkFreeAndNilHint;
    fmGotoStatement:                 Result := F.Kind = fkGotoStatement;
    fmGroupedDeclaration:            Result := F.Kind = fkGroupedDeclaration;
    fmHttpInsteadOfHttps:            Result := F.Kind = fkHttpInsteadOfHttps;
    fmIfElseBegin:                   Result := F.Kind = fkIfElseBegin;
    fmInlineAssembly:                Result := F.Kind = fkInlineAssembly;
    fmInterfaceName:                 Result := F.Kind = fkInterfaceName;
    fmLegacyInitializationSection:   Result := F.Kind = fkLegacyInitializationSection;
    fmLengthUnderflow:               Result := F.Kind = fkLengthUnderflow;
    fmLocalConstantName:             Result := F.Kind = fkLocalConstantName;
    fmLowercaseKeyword:              Result := F.Kind = fkLowercaseKeyword;
    fmMethodName:                    Result := F.Kind = fkMethodName;
    fmNestedRoutine:                 Result := F.Kind = fkNestedRoutine;
    fmNestedTry:                     Result := F.Kind = fkNestedTry;
    fmParamByNameInLoop:             Result := F.Kind = fkParamByNameInLoop;
    fmPointerName:                   Result := F.Kind = fkPointerName;
    fmPublicField:                   Result := F.Kind = fkPublicField;
    fmPublicMemberWithoutDoc:        Result := F.Kind = fkPublicMemberWithoutDoc;
    fmRedundantBoolean:              Result := F.Kind = fkRedundantBoolean;
    fmRedundantConditional:          Result := F.Kind = fkRedundantConditional;
    fmRedundantJump:                 Result := F.Kind = fkRedundantJump;
    fmRedundantParentheses:          Result := F.Kind = fkRedundantParentheses;
    fmReversedForRange:              Result := F.Kind = fkReversedForRange;
    fmSelfAssignment:                Result := F.Kind = fkSelfAssignment;
    fmStringConcatInLoop:            Result := F.Kind = fkStringConcatInLoop;
    fmSuperfluousSemicolon:          Result := F.Kind = fkSuperfluousSemicolon;
    fmTThreadDestroyWithoutTerminate:Result := F.Kind = fkTThreadDestroyWithoutTerminate;
    fmTabulationCharacter:           Result := F.Kind = fkTabulationCharacter;
    fmThreadResumeDeprecated:        Result := F.Kind = fkThreadResumeDeprecated;
    fmTooLongLine:                   Result := F.Kind = fkTooLongLine;
    fmTrailingCommaArgList:          Result := F.Kind = fkTrailingCommaArgList;
    fmTrailingWhitespace:            Result := F.Kind = fkTrailingWhitespace;
    fmTwiceInheritedCalls:           Result := F.Kind = fkTwiceInheritedCalls;
    fmTypeName:                      Result := F.Kind = fkTypeName;
    fmUnitLevelKeywordIndent:        Result := F.Kind = fkUnitLevelKeywordIndent;
    fmVirtualCallInCtor:             Result := F.Kind = fkVirtualCallInCtor;
    fmWithStatement:                 Result := F.Kind = fkWithStatement;
    // mORMot-Cluster (SCA153-155)
    fmUnpairedLock:                  Result := F.Kind = fkUnpairedLock;
    fmMoveSizeOfPointer:             Result := F.Kind = fkMoveSizeOfPointer;
    fmWithMultipleTargets:           Result := F.Kind = fkWithMultipleTargets;
    // mORMot-Cluster Phase 2 (SCA156-158)
    fmGetMemWithoutFreeMem:          Result := F.Kind = fkGetMemWithoutFreeMem;
    fmSetLengthAppendInLoop:         Result := F.Kind = fkSetLengthAppendInLoop;
    fmPointerArithmeticOnString:     Result := F.Kind = fkPointerArithmeticOnString;
    // mORMot-Cluster Phase 3 (SCA159-161)
    fmEmptyOnHandler:                Result := F.Kind = fkEmptyOnHandler;
    fmStringFromPointer:             Result := F.Kind = fkStringFromPointer;
    fmPointerSubtraction:            Result := F.Kind = fkPointerSubtraction;
  else
    Result := True;   // fmAll, fmDetectorReview - der Caller wendet die
                      // Stichproben-Logik selber an, Matches laesst hier
                      // alles durch damit Severity/Type/Search-Filter
                      // weiter wirken.
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

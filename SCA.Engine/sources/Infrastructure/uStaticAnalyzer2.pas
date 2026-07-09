unit uStaticAnalyzer2;

interface

uses
  System.Generics.Collections, System.Generics.Defaults,
  System.SysUtils, System.Classes,
  uSCAConsts, uMethodd12, uIgnoreList;

type
  TStaticAnalyzer2 = class
    // Uses-Häufigkeit: liefert sortierte "N  UnitName"-Zeilen
    class function Analyze(const FileName: string): TStringList;
    class function AnalyzeRecursive(const Path: string): TStringList;

    // Speicherleck-Analyse (AST-basiert)
    class function AnalyzeLeaks(const FileName: string;
      AIncludeUsesCheck: Boolean = False): TObjectList<TLeakFinding>; overload;

    // Single-File-Analyse mit projektweitem Symbol-Reference-Index.
    // Hinweis: seit dem Visibility-Detektor-Refactor laufen
    // CanBeUnitPrivate/CanBeStrictPrivate/CanBeProtected/UnusedPublicMember
    // ohne den Index (single-file only). Die Overload bleibt erhalten weil
    // andere Konsumenten (DFM-Repo-Index, Tests) den projektweiten Scope
    // brauchen. ProjectRoot leer -> Fallback auf den simplen Single-File-Pfad.
    class function AnalyzeLeaks(const FileName: string;
      const ProjectRoot: string;
      AIncludeUsesCheck: Boolean = False): TObjectList<TLeakFinding>; overload;

    class function AnalyzeLeaksRecursive(const Path: string;
      AProgress: TProc<Integer, Integer> = nil;
      AIncludeUsesCheck: Boolean = False;
      AIgnore: TIgnoreList = nil): TObjectList<TLeakFinding>;

    // Analysiert eine bereits ermittelte Datei-Liste (z.B. aus VCS-Diff).
    // Nimmt KEINE Ownership der Liste, kopiert sie intern.
    class function AnalyzeLeaksFromList(AFiles: TStringList;
      AProgress: TProc<Integer, Integer> = nil;
      AIncludeUsesCheck: Boolean = False): TObjectList<TLeakFinding>;

  private
    class procedure ParseFiles(FileList: TStringList; var Results: TStringList);
    class procedure ParseLeaks(FileList: TStringList;
      Results: TObjectList<TLeakFinding>;
      AProgress: TProc<Integer, Integer>;
      AIncludeUsesCheck: Boolean;
      IndexFileList: TStringList = nil);
  end;

var
  // Optional Per-Detector-Timing-Accumulator. Wenn von aussen
  // (CLI --time-detectors, IDE-Perf-Mode) gesetzt, summiert das
  // AOnTime-Lambda in ParseLeaks pro Scan TotalMs + CallCount auf.
  // Nil = kein Tracking (Default).
  // Lifecycle: Caller erzeugt, Lambda fuellt, Caller liest und gibt frei.
  // KEIN threadvar: Konsumenten (CLI uConsoleRunner / IDE) erzeugen, lesen und
  // freen dieses Dictionary AUSSERHALB des SCA.Engine-Package. Ein exportierter
  // Package-threadvar loest W1032 aus und funktioniert ueber die Package-Grenze
  // nicht (Caller-Thread-TLS-Slot != Engine-Thread-Slot) - dieselbe Lektion wie
  // beim DetectorEnabledKinds-threadvar-Revert. Caller-gesetzte, package-
  // exportierte Globals MUESSEN var bleiben.
  gDetectorTimings : TDictionary<string, TPair<Int64, Integer>>;

implementation

// noinspection-file BeginEndRequired, BooleanParam, ConsecutiveSection, DuplicateBlock, ExceptOnException, GroupedDeclaration, InsecureCryptoAlgorithm, MissingUnitHeader, MultipleExit, NestedRoutine, NestedTry, NilComparison, RaisingRawException, RedundantBoolean, RedundantJump, TodoComment, TooLongLine, UnsortedUses, UnusedParameter, UnusedRoutine
// InsecureCryptoAlgorithm: die Detektor-Registrierung enthaelt die Krypto-Pre-
// Filter-Keywords ['md5','sha1','des','rc4',...] - Self-Match, kein Einsatz.
// Detector-Run-Loop: outer except E: Exception fuer per-File-Crash-Recovery
// (eine kaputte Datei darf den ganzen Scan nicht reissen). Phase-Tracking
// im scan.log dokumentiert die Ursache.

uses
  System.IOUtils, System.Diagnostics,
  uStaticFiles, uParser2, uAstNode,
  uLeakDetector2, uCodeSmells2, uSQLInjection, uHardcodedSecret,
  uFormatMismatch, uConcatToFormat, uUnusedUses, uWithStatement,
  uGotoStatement, uTabulationCharacter, uTooLongLine, uTrailingWhitespace,
  uLowercaseKeyword, uNoSonarMarker, uEmptyArgumentList,
  uInlineAssembly, uTrailingCommaArgList, uDigitGrouping,
  uCommentedOutCode, uUnitLevelKeywordIndent, uRedundantBoolean,
  uEmptyInterface, uAssertMessage, uExplicitTObjectInheritance,
  uGroupedDeclaration, uEmptyBlock, uExceptOnException,
  uConsecutiveSection, uRedundantJump, uClassPerFile,
  uSuperfluousSemicolon, uEmptyFinallyBlock, uAssignedAndAssignedNil,
  uFreeAndNilHint, uAvoidOut, uEmptyVisibilitySection,
  uLegacyInitializationSection, uPublicField, uNestedTry,
  uCaseStatementSize, uEmptyFile, uSourceEncoding, uTwiceInheritedCalls,
  uRedundantParentheses, uConsecutiveVisibility,
  uConstructorWithoutInherited, uDestructorWithoutInherited, uRedundantConditional,
  uIfElseBegin, uPointerName,
  uBeginEndRequired, uNestedRoutines,
  uFieldName, uTypeName,
  uInterfaceName, uMethodName,
  uReversedForRange, uSelfAssignment, uVirtualCallInCtor, uLengthUnderflow,
  uVisibilityCheck,
  uUnusedLocal, uUnusedParameter, uTautologicalExpr,
  uSqlDangerousStatement,
  uNilDeref, uMissingFinally, uDivByZero, uDeadCode,
  uLongMethod, uLongParamList, uMagicNumbers, uDuplicateString,
  uHardcodedPath, uDebugOutput, uDeepNesting,
  uTodoComment, uEmptyMethod, uFieldLeak, uDuplicateBlock,
  uCyclomaticComplexity, uCustomRuleDetector,
  uDfmAnalysisRunner, uDfmRepoIndex, uSymbolReferenceIndex, uAstFileCache,
  uFileTextCache, uAnalyzeContext,
  uSuppression, uCustomClassDiscovery, uPathOverrides, uConfidenceFilter,
  uSynchronizeInDestructor, uLockWithoutTryFinally,
  uPerfHotspots, uConcurrencyExt, uRestHttpSecurity,
  uPublicMemberWithoutDoc, uNamingExt,  uRuleCatalog,
  uRoutineResultAssigned, uReRaiseException, uCastAndFree, uMissingRaise,
  uInstanceInvokedConstructor, uInheritedMethodEmpty, uNilComparison,
  uRaisingRawException, uDateFormatSettings, uUnicodeToAnsiCast,
  uCharToCharPointerCast, uIfThenShortCircuit,
  uExceptionTooGeneral, uRaiseOutsideExcept,
  uUseAfterFree, uAbstractNotImpl, uLeakInConstructor, uIntegerOverflow,
  uGodClass, uFreeWithoutNil, uMultipleExit, uLargeClass, uUnsortedUses,
  uMissingUnitHeader,
  uFloatEquality, uExceptInDestructor, uBooleanParam,
  uUnusedPrivateMethod, uCanBeClassMethod, uMissingOverride,
  uBoolAlwaysTrue, uConstantReturn, uHardcodedString,
  uUnpairedLock, uMoveSizeOfPointer, uWithMultipleTargets,
  uGetMemWithoutFreeMem, uSetLengthAppendInLoop, uPointerArithmeticOnString,
  uEmptyOnHandler, uStringFromPointer, uPointerSubtraction,
  uInsecureCryptoAlgorithm, uCommandInjection, uInsecureRandom,
  uDefaultCaseInCaseStatement, uAssertWithSideEffect, uConstStringParameter,
  uCompilerDirectiveScope, uBooleanPropertyNaming,
  uVariantTypeMisuse, uTObjectListWithoutOwnership, uAnonMethodCaptureLoopVar,
  uCognitiveComplexity, uThreadFreeOnTerminateWithRef, uPathTraversal,
  uAttributeIgnoreWithoutReason, uAttributeDuplicate,
  uAttributeCategoryWithoutString, uAttributeTestFixtureWithoutTests,
  uAttributeMisalignment,
  uUnusedRoutine, uUninitVar;

type
  // Run-Methode pro Detektor: einheitliche Signatur, damit alle in einem
  // Array iteriert werden koennen.
  TDetectorRun = reference to procedure(Root: TAstNode; const FileName: string;
    Results: TObjectList<TLeakFinding>; Ctx: TAnalyzeContext);
  // 3-Parameter-Variante (ohne Ctx) fuer Detektoren, deren AnalyzeUnit den
  // TAnalyzeContext nicht entgegennimmt. AddD3 in BuildAllDetectors adaptiert
  // sie GENAU EINMAL auf TDetectorRun - statt 68 identischer Inline-Closures
  // an den Registrierungs-Call-Sites (Boilerplate-Abbau 2026-07-04).
  TDetectorRun3 = reference to procedure(Root: TAstNode; const FileName: string;
    Results: TObjectList<TLeakFinding>);
  TDetectorEntry = record
    Name            : string;
    Kind            : TFindingKind;       // fuer Profile-/Severity-Filter
    Run             : TDetectorRun;
    DefaultSeverity : TLeakSeverity;      // gecached aus TRuleCatalog -
                                          // Catalog-Lookup nur EINMAL beim
                                          // Build, nicht pro File
    // Pre-Filter-Tokens (lowercase). Wenn nicht-leer: vor dem Detector-
    // Run wird die lower-cased Datei nach einem dieser Tokens durchsucht;
    // findet keiner ein Vorkommen, wird der Detector geskippt.
    // Beispiel: 'shellexecute' fuer CommandInjection - 99% aller Files
    // haben das nicht und sparen den AST-Walk.
    // Sicherheitsregel: Tokens muessen NOTWENDIGE Substrings sein - nicht
    // hinreichend. False-Positives (Token vorhanden aber Detector findet
    // nichts) sind OK; False-Negatives (Token fehlt aber echte Treffer
    // werden geskippt) waeren Korrektheits-Regression.
    RequiredTokensLow : TArray<string>;
  end;
  // Callbacks fuer den Aufrufer (Logging / Fehler-Reporting), damit
  // RunAllDetectors selbst kein Wissen ueber LogStream/FileError-Liste hat.
  TDetectorTimeProc  = reference to procedure(const Name: string; ElapsedMs: Int64);
  TDetectorErrorProc = reference to procedure(const Name, ErrMsg: string);

const
  // Headroom ueber dem aktuellen Detector-Count (~170). Verhindert das
  // O(n^2)-SetLength-Wachstum waehrend BuildAllDetectors; bei Erreichen
  // dieser Grenze gibt es spaeter eine Range-Exception statt eines stillen
  // O(n^2)-Pfades.
  DETECTOR_CAPACITY = 220;

var
  // Unit-globale Detector-Liste. Wird deterministisch in der unit-
  // initialization gebaut (s. Datei-Ende) und ist danach read-only fuer
  // die Programm-Laufzeit. Spart ~170 Closure-Allokationen pro Datei
  // (vorher wurde die Liste in RunAllDetectors pro File neu aufgebaut).
  // Audit 2026-07: vorher lazy beim ersten Scan mit Length()=0-Check -
  // ein Datenrennen sobald zwei Scans erstmals parallel starten
  // (SetLength-Trim macht Length<>0 bevor die Liste fertig ist).
  gDetectors : TArray<TDetectorEntry>;
  // Deduplizierte Liste ALLER Pre-Filter-Tokens (lowercase) aus allen
  // tagged Detektoren. Wird in BuildAllDetectors gefuellt. RunAllDetectors
  // baut pro File EIN Token-Presence-Set ueber genau diese Tokens (statt
  // pro Detector einzeln Pos zu rufen - der waere ~24x doppelt fuer
  // shared Tokens wie '.free' / 'tcriticalsection').
  gAllPrefilterTokensLow : TArray<string>;
  // Perf (2026-07-05): P4-token-prefilter - Erstzeichen-Index (CSR-Layout)
  // ueber gAllPrefilterTokensLow fuer den Single-Pass-Prefilter in
  // RunAllDetectors.EnsureTokenSet. Fuer ein Erstzeichen c stehen die
  // Token-Indizes in
  //   gPrefilterBucketTokens[gPrefilterBucketStart[Ord(c)] ..
  //                          gPrefilterBucketStart[Ord(c)+1] - 1].
  // Wird einmalig in BuildAllDetectors gebaut, danach read-only fuer die
  // Programm-Laufzeit (gleicher Lifecycle wie gDetectors). Leere Tokens
  // werden NICHT einsortiert (Pos(''...)=0 -> matchen nie, Semantik
  // erhalten); Tokens mit Erstzeichen > #255 (heute keine) laufen als
  // Fallback weiter ueber Pos (gPrefilterTokensWideFirst).
  gPrefilterBucketStart     : array[0..256] of Integer;
  gPrefilterBucketTokens    : TArray<Integer>;
  gPrefilterTokensWideFirst : TArray<Integer>;

procedure BuildAllDetectors; forward;

procedure EnsureDetectorsBuilt; inline;
// Seit dem initialization-Build nur noch Sicherheitsnetz (idempotent).
begin
  if Length(gDetectors) = 0 then BuildAllDetectors;
end;

function IsDetectorEnabled(const D: TDetectorEntry;
  AIncludeUsesCheck: Boolean; AContext: TAnalyzeContext): Boolean;
// Filter-Eval pro Scan-Aufruf. Wandert hierhin aus dem alten Add()-
// Helper, damit die Detector-Liste statisch gecached werden kann -
// Filter-State (DetectorEnabledKinds, DetectorMinSeverity,
// AIncludeUsesCheck) kann sich zwischen Scans aendern.
// TD-1 (2026-07-06): Kind-/Severity-Filter jetzt aus AContext.Config (via
// Cfg*-Helfer) statt direkt vom uSCAConsts-Global; AContext=nil faellt auf
// das Global zurueck (byte-identisch, da Config==Globals gesnapshottet ist).
var
  EnKinds : TFindingKinds;
begin
  // UnusedUses-Opt-out: laeuft nur bei explizit angeforderter Uses-Pruefung
  // (frueher: hartes Skip:=True nach dem Add, jetzt im Filter).
  if (D.Kind = fkUnusedUses) and not AIncludeUsesCheck then Exit(False);

  // DfmAnalysis-Adapter: laeuft immer, weil intern ~20 DFM-Detektor-Kinds
  // emittiert werden. Profile/Severity-Filter greift dann in der Post-
  // Filter-Schleife auf Finding-Ebene. Identifikation per Name weil der
  // Kind (fkDfmDefaultName) nur Repraesentant ist.
  if D.Name = 'DfmAnalysis' then Exit(True);

  // SourceEncoding-Adapter: EIN Detektor emittiert 9 Encoding-/Unicode-Sicherheit-
  // Kinds (SCA185-193: Utf8NoBom/InvalidUtf8/ControlChar/BidiOverride/AnsiNonAscii/
  // Utf16/Utf32/InvisibleChar/NonAsciiIdentifier). Der Read (eigener ReadAllBytes,
  // + optional EIN Lex-Durchgang) wird nur getriggert wenn mind. EIN Kind aktiv
  // ist (Perf-Gate); die Post-Filter-Schleife dropt einzeln deaktivierte Kinds auf
  // Finding-Ebene. Kind (fkSourceUtf8NoBom) ist nur Repraesentant fuer AddD.
  if D.Name = 'SourceEncoding' then
  begin
    EnKinds := CfgEnabledKinds(AContext);
    Exit( (EnKinds = [])
          or (fkSourceUtf8NoBom in EnKinds)
          or (fkSourceInvalidUtf8 in EnKinds)
          or (fkSourceControlChar in EnKinds)
          or (fkSourceBidiOverride in EnKinds)
          or (fkSourceAnsiNonAscii in EnKinds)
          or (fkSourceUtf16 in EnKinds)
          or (fkSourceUtf32 in EnKinds)
          or (fkSourceInvisibleChar in EnKinds)
          or (fkSourceNonAsciiIdentifier in EnKinds) );
  end;

  // Profile-Whitelist: leere Menge = kein Filter, sonst muss Kind drin sein.
  // Einmal in ein Local lesen (Hot-Path: ~145 Detektoren x N Dateien).
  EnKinds := CfgEnabledKinds(AContext);
  if (EnKinds <> []) and not (D.Kind in EnKinds) then Exit(False);

  // Severity-Schwellwert. lsError=0 < lsWarning=1 < lsHint=2 - groesserer
  // Ord = lockerer Schwellwert. Detector skippen wenn seine Default-
  // Severity strenger ist als der konfigurierte Min-Threshold.
  if Ord(D.DefaultSeverity) > Ord(CfgMinSeverity(AContext)) then Exit(False);

  Result := True;
end;

procedure BuildAllDetectors;
// Wird einmal pro Prozess-Lebenszeit aufgerufen (EnsureDetectorsBuilt).
// Allokiert das Detector-Array vor (DETECTOR_CAPACITY), trimmt am Ende
// auf die tatsaechliche Anzahl. Severity wird einmalig aus dem
// TRuleCatalog gezogen und gecached.
var
  Count : Integer;
  // Perf (2026-07-05): P4-token-prefilter - Zaehl-/Cursor-Array fuer den
  // Counting-Sort beim Aufbau des Erstzeichen-Index (s. Datei-Kopf,
  // gPrefilterBucketStart).
  CntPerFirst : array[0..255] of Integer;

  procedure AddD(const AName: string; AKind: TFindingKind; ARun: TDetectorRun);
  overload;
  begin
    // Count (outer-var von BuildAllDetectors) wird im outer-body initialisiert
    // bevor AddD aufgerufen wird; FP des Nested-Closure-Pattern.
    if Count >= Length(gDetectors) then
      raise Exception.CreateFmt(
        'BuildAllDetectors: DETECTOR_CAPACITY (%d) ueberschritten - ' +
        'Konstante erhoehen', [Length(gDetectors)]);
    gDetectors[Count].Name            := AName;
    gDetectors[Count].Kind            := AKind;
    gDetectors[Count].Run             := ARun;
    gDetectors[Count].DefaultSeverity := TRuleCatalog.GetRule(AKind).DefaultSeverity;
    SetLength(gDetectors[Count].RequiredTokensLow, 0);
    Inc(Count);
  end;

  // Overload mit Pre-Filter-Tokens. AddD-Aufrufer liefern lowercase
  // Tokens; ist NOTWENDIGE Substring-Bedingung (s. Doku TDetectorEntry).
  procedure AddD(const AName: string; AKind: TFindingKind; ARun: TDetectorRun;
    const ARequiredTokensLow: array of string); overload;
  var
    i : Integer;
  begin
    AddD(AName, AKind, ARun);
    SetLength(gDetectors[Count - 1].RequiredTokensLow, Length(ARequiredTokensLow));
    for i := 0 to High(ARequiredTokensLow) do
      gDetectors[Count - 1].RequiredTokensLow[i] := ARequiredTokensLow[i];
  end;

  // Registrierung fuer 3-Parameter-Detektoren (AnalyzeUnit ohne Ctx):
  // kapselt die Ctx-verwerfende Adapter-Closure GENAU EINMAL - die
  // Call-Sites uebergeben die Methodenreferenz direkt (2026-07-04).
  // Die Closure captured nur ARun3 (eigener Parameter von AddD3, nicht
  // outer-frame) - kein E2555-Capture-Problem.
  procedure AddD3(const AName: string; AKind: TFindingKind; ARun3: TDetectorRun3);
  overload;
  begin
    AddD(AName, AKind,
      procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>;
        Ctx: TAnalyzeContext)
      begin
        ARun3(R, F, L);
      end);
  end;

  // Overload mit Pre-Filter-Tokens - identische Token-Semantik wie die
  // AddD-Token-Overload (Tokens auf den zuletzt registrierten Eintrag).
  procedure AddD3(const AName: string; AKind: TFindingKind; ARun3: TDetectorRun3;
    const ARequiredTokensLow: array of string); overload;
  var
    i : Integer;
  begin
    AddD3(AName, AKind, ARun3);
    SetLength(gDetectors[Count - 1].RequiredTokensLow, Length(ARequiredTokensLow));
    for i := 0 to High(ARequiredTokensLow) do
      gDetectors[Count - 1].RequiredTokensLow[i] := ARequiredTokensLow[i];
  end;

begin
  SetLength(gDetectors, DETECTOR_CAPACITY);
  Count := 0;

  AddD('Leak',             fkMemoryLeak,      TLeakDetector2.AnalyzeUnit);   // TD-1 2c: AContext-fuehrend (LeakyClasses aus Ctx)
  AddD3('EmptyExcept',     fkEmptyExcept,     TEmptyExceptDetector2.AnalyzeUnit);
  AddD3('SQLInjection',    fkSQLInjection,    TSQLInjectionDetector.AnalyzeUnit);
  AddD3('HardcodedSecret', fkHardcodedSecret, THardcodedSecretDetector.AnalyzeUnit);
  AddD3('FormatMismatch',  fkFormatMismatch,  TFormatMismatchDetector.AnalyzeUnit);
  AddD3('ConcatToFormat',  fkConcatToFormat,  TConcatToFormatDetector.AnalyzeUnit);
  AddD('WithStatement',   fkWithStatement,   TWithStatementDetector.AnalyzeUnit, ['with ']);
  AddD('GotoStatement',   fkGotoStatement,   TGotoStatementDetector.AnalyzeUnit, ['goto ']);
  AddD('TabulationCharacter', fkTabulationCharacter, TTabulationCharacterDetector.AnalyzeUnit);
  AddD('TooLongLine',     fkTooLongLine,     TTooLongLineDetector.AnalyzeUnit);
  AddD('TrailingWhitespace', fkTrailingWhitespace, TTrailingWhitespaceDetector.AnalyzeUnit);
  AddD('LowercaseKeyword', fkLowercaseKeyword, TLowercaseKeywordDetector.AnalyzeUnit);
  AddD('NoSonarMarker',   fkNoSonarMarker,   TNoSonarMarkerDetector.AnalyzeUnit, ['nosonar']);
  AddD('EmptyArgumentList',fkEmptyArgumentList,TEmptyArgumentListDetector.AnalyzeUnit);
  AddD('InlineAssembly',  fkInlineAssembly,  TInlineAssemblyDetector.AnalyzeUnit, ['asm']);
  AddD('TrailingCommaArgList',fkTrailingCommaArgList,TTrailingCommaArgListDetector.AnalyzeUnit);
  AddD('DigitGrouping',   fkDigitGrouping,   TDigitGroupingDetector.AnalyzeUnit);
  AddD('CommentedOutCode',fkCommentedOutCode,TCommentedOutCodeDetector.AnalyzeUnit);
  AddD('UnitLevelKeywordIndent',fkUnitLevelKeywordIndent,TUnitLevelKeywordIndentDetector.AnalyzeUnit);
  AddD('RedundantBoolean',fkRedundantBoolean,TRedundantBooleanDetector.AnalyzeUnit);
  AddD('EmptyInterface',  fkEmptyInterface,  TEmptyInterfaceDetector.AnalyzeUnit);
  AddD('AssertMessage',   fkAssertMessage,   TAssertMessageDetector.AnalyzeUnit);
  AddD('ExplicitTObjectInheritance',fkExplicitTObjectInheritance,TExplicitTObjectInheritanceDetector.AnalyzeUnit);
  AddD('GroupedDeclaration',fkGroupedDeclaration,TGroupedDeclarationDetector.AnalyzeUnit);
  AddD('EmptyBlock',      fkEmptyBlock,      TEmptyBlockDetector.AnalyzeUnit);
  AddD('ExceptOnException',fkExceptOnException,TExceptOnExceptionDetector.AnalyzeUnit);
  AddD('ConsecutiveSection',fkConsecutiveSection,TConsecutiveSectionDetector.AnalyzeUnit);
  AddD('RedundantJump',   fkRedundantJump,   TRedundantJumpDetector.AnalyzeUnit);
  AddD('ClassPerFile',    fkClassPerFile,    TClassPerFileDetector.AnalyzeUnit);
  AddD('SuperfluousSemicolon',fkSuperfluousSemicolon,TSuperfluousSemicolonDetector.AnalyzeUnit);
  AddD('EmptyFinallyBlock',fkEmptyFinallyBlock,TEmptyFinallyBlockDetector.AnalyzeUnit);
  AddD('AssignedAndAssignedNil',fkAssignedAndAssignedNil,TAssignedAndAssignedNilDetector.AnalyzeUnit);
  AddD('FreeAndNilHint',  fkFreeAndNilHint,  TFreeAndNilHintDetector.AnalyzeUnit);
  AddD('AvoidOut',        fkAvoidOut,        TAvoidOutDetector.AnalyzeUnit);
  AddD('EmptyVisibilitySection',fkEmptyVisibilitySection,TEmptyVisibilitySectionDetector.AnalyzeUnit);
  AddD('LegacyInitializationSection',fkLegacyInitializationSection,TLegacyInitializationSectionDetector.AnalyzeUnit);
  AddD('PublicField',     fkPublicField,     TPublicFieldDetector.AnalyzeUnit);
  AddD('NestedTry',       fkNestedTry,       TNestedTryDetector.AnalyzeUnit);
  AddD('CaseStatementSize',fkCaseStatementSize,TCaseStatementSizeDetector.AnalyzeUnit);
  AddD('EmptyFile',       fkEmptyFile,       TEmptyFileDetector.AnalyzeUnit);
  // SourceEncoding: EIN Eintrag, 4 Kinds (siehe IsDetectorEnabled-Sonderfall).
  // KEIN RequiredTokensLow - muss immer laufen (kein Token signalisiert Encoding).
  AddD('SourceEncoding',  fkSourceUtf8NoBom, TSourceEncodingDetector.AnalyzeUnit);
  AddD3('TwiceInheritedCalls',fkTwiceInheritedCalls,TTwiceInheritedCallsDetector.AnalyzeUnit);
  AddD('RedundantParentheses',fkRedundantParentheses,TRedundantParenthesesDetector.AnalyzeUnit);
  AddD('ConsecutiveVisibility',fkConsecutiveVisibility,TConsecutiveVisibilityDetector.AnalyzeUnit);
  AddD3('ConstructorWithoutInherited',fkConstructorWithoutInherited,TConstructorWithoutInheritedDetector.AnalyzeUnit);
  AddD('DestructorWithoutInherited',fkDestructorWithoutInherited,TDestructorWithoutInheritedDetector.AnalyzeUnit);
  AddD('RedundantConditional',fkRedundantConditional,TRedundantConditionalDetector.AnalyzeUnit);
  AddD('IfElseBegin',     fkIfElseBegin,     TIfElseBeginDetector.AnalyzeUnit);
  AddD('PointerName',     fkPointerName,     TPointerNameDetector.AnalyzeUnit);
  AddD('BeginEndRequired',fkBeginEndRequired,TBeginEndRequiredDetector.AnalyzeUnit);
  AddD('NestedRoutine',   fkNestedRoutine,   TNestedRoutinesDetector.AnalyzeUnit);
  AddD('FieldName',       fkFieldName,       TFieldNameDetector.AnalyzeUnit);
  AddD('TypeName',        fkTypeName,        TTypeNameDetector.AnalyzeUnit);
  AddD('InterfaceName',   fkInterfaceName,   TInterfaceNameDetector.AnalyzeUnit);
  AddD3('MethodName',      fkMethodName,      TMethodNameDetector.AnalyzeUnit);
  AddD('ReversedForRange',fkReversedForRange,TReversedForRangeDetector.AnalyzeUnit, ['downto']);
  AddD3('SelfAssignment',  fkSelfAssignment,  TSelfAssignmentDetector.AnalyzeUnit);
  AddD3('MissingRaise',    fkMissingRaise,    TMissingRaiseDetector.AnalyzeUnit);
  AddD3('RoutineResultUnassigned', fkRoutineResultUnassigned, TRoutineResultAssignedDetector.AnalyzeUnit);
  AddD3('ReRaiseException', fkReRaiseException, TReRaiseExceptionDetector.AnalyzeUnit);
  AddD3('CastAndFree',     fkCastAndFree,     TCastAndFreeDetector.AnalyzeUnit);
  AddD3('InstanceInvokedConstructor', fkInstanceInvokedConstructor, TInstanceInvokedConstructorDetector.AnalyzeUnit);
  AddD3('InheritedMethodEmpty', fkInheritedMethodEmpty, TInheritedMethodEmptyDetector.AnalyzeUnit);
  AddD3('NilComparison',   fkNilComparison,   TNilComparisonDetector.AnalyzeUnit);
  AddD3('RaisingRawException', fkRaisingRawException, TRaisingRawExceptionDetector.AnalyzeUnit);
  AddD3('DateFormatSettings', fkDateFormatSettings, TDateFormatSettingsDetector.AnalyzeUnit);
  AddD3('UnicodeToAnsiCast', fkUnicodeToAnsiCast, TUnicodeToAnsiCastDetector.AnalyzeUnit);
  AddD3('CharToCharPointerCast', fkCharToCharPointerCast, TCharToCharPointerCastDetector.AnalyzeUnit);
  AddD3('IfThenShortCircuit', fkIfThenShortCircuit, TIfThenShortCircuitDetector.AnalyzeUnit);
  AddD3('ExceptionTooGeneral', fkExceptionTooGeneral, TExceptionTooGeneralDetector.AnalyzeUnit);
  AddD3('RaiseOutsideExcept', fkRaiseOutsideExcept, TRaiseOutsideExceptDetector.AnalyzeUnit);
  AddD('UseAfterFree', fkUseAfterFree, TUseAfterFreeDetector.AnalyzeUnit, ['.free', 'freeandnil']);
  AddD3('AbstractNotImpl', fkAbstractNotImpl, TAbstractNotImplDetector.AnalyzeUnit);
  AddD3('LeakInConstructor', fkLeakInConstructor, TLeakInConstructorDetector.AnalyzeUnit);
  AddD('IntegerOverflow', fkIntegerOverflow, TIntegerOverflowDetector.AnalyzeUnit, ['int64']);
  AddD3('GodClass', fkGodClass, TGodClassDetector.AnalyzeUnit);
  AddD3('FreeWithoutNil', fkFreeWithoutNil, TFreeWithoutNilDetector.AnalyzeUnit);
  AddD3('MultipleExit', fkMultipleExit, TMultipleExitDetector.AnalyzeUnit);
  AddD3('LargeClass', fkLargeClass, TLargeClassDetector.AnalyzeUnit);
  AddD3('UnsortedUses', fkUnsortedUses, TUnsortedUsesDetector.AnalyzeUnit);
  AddD('MissingUnitHeader', fkMissingUnitHeader, TMissingUnitHeaderDetector.AnalyzeUnit);
  AddD('FloatEquality', fkFloatEquality, TFloatEqualityDetector.AnalyzeUnit, ['double', 'single', 'extended', 'currency', 'real']);
  AddD3('ExceptInDestructor', fkExceptInDestructor, TExceptInDestructorDetector.AnalyzeUnit);
  AddD3('BooleanParam', fkBooleanParam, TBooleanParamDetector.AnalyzeUnit);
  AddD('UnusedPrivateMethod', fkUnusedPrivateMethod, TUnusedPrivateMethodDetector.AnalyzeUnit);
  AddD3('CanBeClassMethod', fkCanBeClassMethod, TCanBeClassMethodDetector.AnalyzeUnit);
  AddD3('MissingOverride', fkMissingOverride, TMissingOverrideDetector.AnalyzeUnit);
  AddD('BoolAlwaysTrue', fkBoolAlwaysTrue, TBoolAlwaysTrueDetector.AnalyzeUnit);
  AddD3('ConstantReturn', fkConstantReturn, TConstantReturnDetector.AnalyzeUnit);
  AddD('HardcodedString', fkHardcodedString, THardcodedStringDetector.AnalyzeUnit);
  AddD('UnpairedLock', fkUnpairedLock, TUnpairedLockDetector.AnalyzeUnit, ['tcriticalsection', 'tmonitor', '.enter', '.acquire']);
  AddD('MoveSizeOfPointer', fkMoveSizeOfPointer, TMoveSizeOfPointerDetector.AnalyzeUnit, ['move(', 'fillchar(']);
  AddD('WithMultipleTargets', fkWithMultipleTargets, TWithMultipleTargetsDetector.AnalyzeUnit);
  AddD('GetMemWithoutFreeMem', fkGetMemWithoutFreeMem, TGetMemWithoutFreeMemDetector.AnalyzeUnit, ['getmem', 'allocmem', 'reallocmem']);
  AddD('SetLengthAppendInLoop', fkSetLengthAppendInLoop, TSetLengthAppendInLoopDetector.AnalyzeUnit, ['setlength']);
  AddD('PointerArithmeticOnString', fkPointerArithmeticOnString, TPointerArithmeticOnStringDetector.AnalyzeUnit, ['pchar(', 'pansichar(', 'pwidechar(']);
  AddD('EmptyOnHandler', fkEmptyOnHandler, TEmptyOnHandlerDetector.AnalyzeUnit, ['except', 'on ']);
  AddD('StringFromPointer', fkStringFromPointer, TStringFromPointerDetector.AnalyzeUnit, ['pchar(', 'pansichar(', 'pwidechar(']);
  AddD('PointerSubtraction', fkPointerSubtraction, TPointerSubtractionDetector.AnalyzeUnit, ['cardinal(', 'integer(', 'nativeuint(', 'nativeint(', 'nativeint ', 'cardinal ']);
  // Security-Familie: schwache Krypto + Command-Injection.
  AddD3('InsecureCryptoAlgorithm', fkInsecureCryptoAlgorithm, TInsecureCryptoAlgorithmDetector.AnalyzeUnit, ['md5', 'sha1', 'des', 'rc4', 'crypto', 'hash']);
  AddD3('CommandInjection', fkCommandInjection, TCommandInjectionDetector.AnalyzeUnit, ['shellexecute', 'createprocess', 'winexec']);
  // SCA167 InsecureRandom: file-Pre-Filter auf 'random' (Substring) skippt
  // grosse Files die das Wort nicht enthalten.
  AddD3('InsecureRandom', fkInsecureRandom, TInsecureRandomDetector.AnalyzeUnit, ['random']);
  // SCA168 DefaultCaseInCaseStatement: brauchen nur nkCaseStmt; Pre-Filter 'case'.
  AddD3('DefaultCaseInCaseStatement', fkDefaultCaseInCaseStatement, TDefaultCaseInCaseStatementDetector.AnalyzeUnit, ['case ']);
  // SCA169 AssertWithSideEffect: Pre-Filter 'assert'.
  AddD3('AssertWithSideEffect', fkAssertWithSideEffect, TAssertWithSideEffectDetector.AnalyzeUnit, ['assert']);
  // SCA170 ConstStringParameter: kein Pre-Filter (jede Unit kann Methods haben).
  AddD3('ConstStringParameter', fkConstStringParameter, TConstStringParameterDetector.AnalyzeUnit);
  // SCA171 CompilerDirectiveScope: file-Pre-Filter auf '{$' (Substring).
  AddD('CompilerDirectiveScope', fkCompilerDirectiveScope, TCompilerDirectiveScopeDetector.AnalyzeUnit, ['{$']);
  // SCA172 BooleanPropertyNaming: file-Pre-Filter auf 'boolean'.
  AddD('BooleanPropertyNaming', fkBooleanPropertyNaming, TBooleanPropertyNamingDetector.AnalyzeUnit, ['boolean']);
  // SCA173 VariantTypeMisuse: Pre-Filter 'variant' damit Files ohne komplett geskippt werden.
  AddD3('VariantTypeMisuse', fkVariantTypeMisuse, TVariantTypeMisuseDetector.AnalyzeUnit, ['variant']);
  // SCA174 TObjectListWithoutOwnership: Pre-Filter 'tlist<' faengt Generic-Pattern.
  AddD3('TObjectListWithoutOwnership', fkTObjectListWithoutOwnership, TTObjectListWithoutOwnershipDetector.AnalyzeUnit, ['tlist<']);
  // SCA175 AnonMethodCaptureLoopVar: Pre-Filter 'procedure' (anonymous-Marker).
  AddD3('AnonMethodCaptureLoopVar', fkAnonMethodCaptureLoopVar, TAnonMethodCaptureLoopVarDetector.AnalyzeUnit, ['procedure']);
  // SCA176 CognitiveComplexity: kein Pre-Filter (jede Method gepruft).
  AddD3('CognitiveComplexity', fkCognitiveComplexity, TCognitiveComplexityDetector.AnalyzeUnit);
  // SCA177 ThreadFreeOnTerminateWithRef: Pre-Filter 'freeonterminate'.
  AddD3('ThreadFreeOnTerminateWithRef', fkThreadFreeOnTerminateWithRef, TThreadFreeOnTerminateWithRefDetector.AnalyzeUnit, ['freeonterminate']);
  // SCA178 PathTraversal: Pre-Filter file-open-API tokens.
  AddD3('PathTraversal', fkPathTraversal, TPathTraversalDetector.AnalyzeUnit, ['tfilestream', 'tfile.', 'assignfile', 'fileopen', 'filecreate']);
  // SCA179-183 Attribute-Detector-Familie. Pre-Filter '[' faengt
  // Attribute-Syntax (jeder Detektor scannt file-text fuer Attribut-Patterns).
  AddD('AttributeIgnoreWithoutReason', fkAttributeIgnoreWithoutReason, TAttributeIgnoreWithoutReasonDetector.AnalyzeUnit, ['[ignore']);
  AddD('AttributeDuplicate', fkAttributeDuplicate, TAttributeDuplicateDetector.AnalyzeUnit, ['[']);
  AddD('AttributeCategoryWithoutString', fkAttributeCategoryWithoutString, TAttributeCategoryWithoutStringDetector.AnalyzeUnit, ['[category']);
  AddD('AttributeTestFixtureWithoutTests', fkAttributeTestFixtureWithoutTests, TAttributeTestFixtureWithoutTestsDetector.AnalyzeUnit, ['[testfixture']);
  AddD('AttributeMisalignment', fkAttributeMisalignment, TAttributeMisalignmentDetector.AnalyzeUnit, ['[']);
  // Dead-Code-Familie: standalone Routinen ohne Aufruf (analog SCA147 fuer
  // class-private Methoden, schliesst die Luecke top-level Routinen).
  AddD('UnusedRoutine', fkUnusedRoutine, TUnusedRoutineDetector.AnalyzeUnit);
  AddD3('VirtualCallInCtor',fkVirtualCallInCtor,TVirtualCallInCtorDetector.AnalyzeUnit);
  AddD('LengthUnderflow', fkLengthUnderflow, TLengthUnderflowDetector.AnalyzeUnit, ['length(', '.count', 'high(']);
  // VisibilityCheck emittiert vier Kinds (CanBeUnitPrivate, CanBeStrict-
  // Private, CanBeProtected, UnusedPublicMember) auf den
  // fkCanBeUnitPrivate-Anker im Profile-Filter.
  // Single-file-Modus (kein gSymbolRefIndex) - global scan abgeschaltet
  // weil zu viele False-Positives lieferte; siehe uVisibilityCheck.pas.
  AddD('VisibilityCheck',fkCanBeUnitPrivate, TVisibilityCheckDetector.AnalyzeUnit);
  // Concurrency-Detektor-Familie
  AddD3('SynchronizeInDestructor', fkSynchronizeInDestructor, TSynchronizeInDestructorDetector.AnalyzeUnit);
  AddD('LockWithoutTryFinally', fkLockWithoutTryFinally, TLockWithoutTryFinallyDetector.AnalyzeUnit, ['tcriticalsection', 'tmonitor', '.enter', '.acquire']);
  // Concurrency-Familie erweitert (SCA113-114): Thread-Lifecycle-Bugs
  AddD('ConcurrencyExt',     fkThreadResumeDeprecated, TConcurrencyExtDetector.AnalyzeUnit, ['tthread', '.synchronize', '.resume', '.queue', 'parambyname', 'fieldbyname']);
  // Performance-Hotspots (SCA110-112)
  AddD('PerfHotspots',       fkStringConcatInLoop,     TPerfHotspotsDetector.AnalyzeUnit);
  // REST/HTTP-Security (SCA115-116)
  AddD('RestHttpSecurity',   fkHttpInsteadOfHttps,     TRestHttpSecurityDetector.AnalyzeUnit, ['http://', 'https://', 'tls', 'ssl', 'thttp', 'idhttp', 'rest.client', '.securityprotocol']);
  // Doc-Luecken (SCA117)
  AddD('PublicMemberWithoutDoc', fkPublicMemberWithoutDoc, TPublicMemberWithoutDocDetector.AnalyzeUnit);
  // Naming-Familie erweitert (SCA118-119)
  AddD3('NamingExt',          fkExceptionName,          TNamingExtDetector.AnalyzeUnit);
  AddD('UnusedLocalVar', fkUnusedLocalVar,  TUnusedLocalDetector.AnalyzeUnit);
  // SCA166 UninitVar - lokale Variable die vor erstem Write gelesen wird.
  // Konservatives single-method-Modell (siehe Konzept_SCA166_UninitVar.md).
  AddD('UninitVar',      fkUninitVar,       TUninitVarDetector.AnalyzeUnit);
  AddD3('UnusedParameter',fkUnusedParameter, TUnusedParameterDetector.AnalyzeUnit);
  AddD('TautologicalBoolExpr',fkTautologicalBoolExpr, TTautologicalExprDetector.AnalyzeUnit);
  AddD3('SqlDangerousStatement', fkSqlDangerousStatement, TSqlDangerousStatementDetector.AnalyzeUnit);
  // UnusedUses: bleibt im Detector-Pool eingetragen; der per-Scan-Opt-out
  // (AIncludeUsesCheck=False) wird in IsDetectorEnabled() zur Laufzeit
  // ausgewertet. Frueher haerteres Skip:=True nach dem Add - jetzt
  // dynamisch, damit derselbe Detector-Cache fuer Scans mit und ohne
  // UsesCheck wiederverwendet werden kann.
  AddD3('UnusedUses',      fkUnusedUses,      TUnusedUsesDetector.AnalyzeUnit);
  AddD3('NilDeref',        fkNilDeref,        TNilDerefDetector.AnalyzeUnit);
  AddD('MissingFinally',   fkMissingFinally,  TMissingFinallyDetector.AnalyzeUnit);   // TD-1 2c: AContext-fuehrend (LeakyClasses aus Ctx)
  AddD3('DivByZero',       fkDivByZero,       TDivByZeroDetector.AnalyzeUnit);
  AddD3('DeadCode',        fkDeadCode,        TDeadCodeDetector.AnalyzeUnit);
  // TD-1 (2026-07-06): jetzt AContext-fuehrend (Schwellen aus Ctx.Config) -> AddD statt AddD3.
  AddD('LongMethod',      fkLongMethod,      TLongMethodDetector.AnalyzeUnit);
  AddD('LongParamList',   fkLongParamList,   TLongParamListDetector.AnalyzeUnit);
  AddD3('MagicNumber',     fkMagicNumber,     TMagicNumberDetector.AnalyzeUnit);
  AddD3('DuplicateString', fkDuplicateString, TDuplicateStringDetector.AnalyzeUnit);
  AddD3('HardcodedPath',   fkHardcodedPath,   THardcodedPathDetector.AnalyzeUnit);
  AddD3('DebugOutput',     fkDebugOutput,     TDebugOutputDetector.AnalyzeUnit);
  AddD('DeepNesting',     fkDeepNesting,     TDeepNestingDetector.AnalyzeUnit);   // TD-1: AContext-fuehrend
  AddD('TodoComment',     fkTodoComment,     TTodoCommentDetector.AnalyzeUnit, ['todo', 'fixme', 'hack', 'xxx']);
  AddD3('EmptyMethod',     fkEmptyMethod,     TEmptyMethodDetector.AnalyzeUnit);
  // FieldLeak: gleicher Kind wie LeakDetector (fkMemoryLeak) - Profile-
  // Filter behandelt beide identisch.
  AddD('FieldLeak',        fkMemoryLeak,      TFieldLeakDetector.AnalyzeUnit);   // TD-1 2c: AContext-fuehrend (LeakyClasses aus Ctx)
  AddD('DuplicateBlock',  fkDuplicateBlock,  TDuplicateBlockDetector.AnalyzeUnit);
  AddD('CyclomaticComplexity', fkCyclomaticComplexity, TCyclomaticComplexityDetector.AnalyzeUnit);   // TD-1: AContext-fuehrend
  // DFM-Adapter: ruft intern ~20 DFM-Detektoren, jeder mit eigenem Kind.
  // Profile/Severity-Filter darf den Adapter NICHT skippen - die Filterung
  // passiert spaeter im Post-Filter auf Finding-Ebene. IsDetectorEnabled()
  // erkennt den Adapter am Name='DfmAnalysis' und liefert dort immer True.
  AddD('DfmAnalysis',     fkDfmDefaultName,  procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>; Ctx: TAnalyzeContext) begin TDfmAnalysisRunner.AnalyzePasFile(F, L, Ctx); end);

  // Array auf tatsaechliche Anzahl trimmen.
  SetLength(gDetectors, Count);

  // Deduplizierte Pre-Filter-Token-Liste aufbauen. RunAllDetectors macht
  // pro File EIN Token-Presence-Set ueber genau diese Tokens (statt
  // Pos pro Detector zu wiederholen - shared Tokens wie 'tcriticalsection'
  // werden sonst mehrmals gescannt).
  var Seen := TDictionary<string, Boolean>.Create;
  try
    for var i := 0 to High(gDetectors) do
      for var j := 0 to High(gDetectors[i].RequiredTokensLow) do
        if not Seen.ContainsKey(gDetectors[i].RequiredTokensLow[j]) then
          Seen.Add(gDetectors[i].RequiredTokensLow[j], True);
    SetLength(gAllPrefilterTokensLow, Seen.Count);
    var Idx : Integer := 0;
    for var Tok in Seen.Keys do
    begin
      gAllPrefilterTokensLow[Idx] := Tok;
      Inc(Idx);
    end;
  finally
    Seen.Free;
  end;

  // Perf (2026-07-05): P4-token-prefilter - Erstzeichen-Index (CSR) ueber
  // gAllPrefilterTokensLow aufbauen (Counting-Sort in zwei Durchlaeufen).
  // EnsureTokenSet vergleicht damit pro Textposition nur noch die Tokens,
  // deren Erstzeichen dem aktuellen Zeichen entspricht - EIN Durchlauf
  // ueber den File-Text statt ~82 einzelner Pos()-Scans.
  FillChar(CntPerFirst, SizeOf(CntPerFirst), 0);
  SetLength(gPrefilterTokensWideFirst, 0);
  for var t := 0 to High(gAllPrefilterTokensLow) do
    if gAllPrefilterTokensLow[t] <> '' then  // leere Tokens: Pos('')=0 -> nie Match
    begin
      var FirstOrd := Ord(gAllPrefilterTokensLow[t][1]);
      if FirstOrd <= 255 then
        Inc(CntPerFirst[FirstOrd])
      else
      begin
        // Erstzeichen ausserhalb Byte-Bereich: Pos-Fallback-Liste.
        SetLength(gPrefilterTokensWideFirst,
          Length(gPrefilterTokensWideFirst) + 1);
        gPrefilterTokensWideFirst[High(gPrefilterTokensWideFirst)] := t;
      end;
    end;
  gPrefilterBucketStart[0] := 0;
  for var c := 0 to 255 do
    gPrefilterBucketStart[c + 1] := gPrefilterBucketStart[c] + CntPerFirst[c];
  SetLength(gPrefilterBucketTokens, gPrefilterBucketStart[256]);
  // Zweiter Durchlauf: Token-Indizes einsortieren (CntPerFirst als Cursor
  // recycelt).
  FillChar(CntPerFirst, SizeOf(CntPerFirst), 0);
  for var t := 0 to High(gAllPrefilterTokensLow) do
    if gAllPrefilterTokensLow[t] <> '' then
    begin
      var FirstOrd := Ord(gAllPrefilterTokensLow[t][1]);
      if FirstOrd <= 255 then
      begin
        gPrefilterBucketTokens[gPrefilterBucketStart[FirstOrd] +
          CntPerFirst[FirstOrd]] := t;
        Inc(CntPerFirst[FirstOrd]);
      end;
    end;
end;

procedure FillMissingMethodNames(Root: TAstNode;
  Results: TObjectList<TLeakFinding>; FromIdx: Integer);
// Line-basierte Detektoren (AttributeDuplicate, TooLongLine, ...) setzen
// MethodName = '' weil sie keinen AST-Methodenknoten kennen. Damit das Grid
// (Haupt-Frame + File-Panel) trotzdem die einschliessende Methode zeigt,
// loesen wir hier zentral Zeile -> Methode auf: fuer jeden Befund ohne
// MethodName die Methode mit der GROESSTEN Decl-Zeile <= Befund-Zeile.
//
// FindAll(nkMethod) liefert eine eigene Kopie (Caller-owned) - Sortieren +
// Freigeben sind sicher. Greift nur wenn ueberhaupt ein leerer MethodName im
// neuen Befund-Bereich existiert (sonst kein Walk).
var
  Methods : TList<TAstNode>;
  i, Ln   : Integer;
  NeedFill: Boolean;

  function MethodNameForLine(L: Integer): string;
  var lo, hi, mid, found: Integer;
  begin
    Result := '';
    lo := 0; hi := Methods.Count - 1; found := -1;
    while lo <= hi do
    begin
      mid := (lo + hi) div 2;
      if Methods[mid].Line <= L then begin found := mid; lo := mid + 1; end
      else hi := mid - 1;
    end;
    if found >= 0 then Result := Methods[found].Name;
  end;

begin
  if (Root = nil) or (Results = nil) then Exit;
  NeedFill := False;
  for i := FromIdx to Results.Count - 1 do
    if (Results[i].MethodName = '') and (Results[i].Kind <> fkFileReadError) then
    begin NeedFill := True; Break; end;
  if not NeedFill then Exit;

  Methods := Root.FindAll(nkMethod);
  try
    for i := Methods.Count - 1 downto 0 do
      if Methods[i].Name = '' then Methods.Delete(i);   // namenlose raus
    if Methods.Count = 0 then Exit;
    Methods.Sort(TComparer<TAstNode>.Construct(
      function(const A, B: TAstNode): Integer
      begin
        Result := A.Line - B.Line;
      end));
    for i := FromIdx to Results.Count - 1 do
    begin
      if Results[i].MethodName <> '' then Continue;
      if Results[i].Kind = fkFileReadError then Continue;
      Ln := StrToIntDef(Results[i].LineNumber, 0);
      if Ln > 0 then
        Results[i].MethodName := MethodNameForLine(Ln);
    end;
  finally
    Methods.Free;
  end;
end;

procedure RunAllDetectors(Root: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>; AIncludeUsesCheck: Boolean;
  AContext: TAnalyzeContext;
  AOnTime: TDetectorTimeProc; AOnError: TDetectorErrorProc);
// Pro-File-Detector-Run. Detector-Liste ist global gecached
// (BuildAllDetectors) - hier nur noch Filter-Eval + Run pro Detector +
// Post-Filter auf Finding-Ebene.
//
// Perf-Hot-Path:
//   * PrevCount markiert den Stand von Results VOR den Detektoren. Der
//     Post-Filter iteriert nur Results[PrevCount..Count-1] (= die NEUEN
//     Findings dieses Files) statt der kumulativen Liste -> O(n) statt
//     O(n^2) ueber die Scan-Laufzeit. Bei 1000 Files mit je 100 Findings:
//     vorher ~50 Mio Filter-Iterations, jetzt ~100k.
//   * Watch wird nur instanziiert wenn AOnTime tatsaechlich assigned ist
//     (spart ~1 µs QueryPerformanceCounter pro Detektor pro File).
var
  i, j       : Integer;
  Watch      : TStopwatch;
  PrevCount  : Integer;
  HasTimeCb  : Boolean;
  FilterActive : Boolean;
  Lines        : TStringList;
  Cached       : Boolean;
  TokenMatch   : Boolean;
  // Pro-File Token-Presence-Set: TRUE = Token im File vorhanden, FALSE = nicht.
  // Wird LAZY beim ersten Tagged-Detector aufgebaut (EinMAL pro File ueber
  // gAllPrefilterTokensLow). Detector-Check ist danach O(1) Hash-Lookup
  // pro Token statt teurem Pos pro Detector × Token.
  TokenPresent : TDictionary<string, Boolean>;
  TokenSetReady : Boolean;

  function EnsureTokenSet: Boolean;
  var
    SrcLow    : string;
    PSrc      : PChar;
    SrcLen    : Integer;
    p, b, k   : Integer;
    ChOrd     : Integer;
    TokIdx    : Integer;
    TokLen    : Integer;
    Remaining : Integer;
    FoundTok  : TArray<Boolean>;   // parallel zu gAllPrefilterTokensLow
  begin
    if TokenSetReady then Exit(TokenPresent.Count > 0);
    TokenSetReady := True;
    Lines := AcquireLines(FileName, Cached);
    if Lines = nil then Exit(False);
    try
      SrcLow := LowerCase(Lines.Text);
    finally
      ReleaseLines(Lines, Cached);
    end;
    if SrcLow = '' then Exit(False);
    // Perf (2026-07-05): P4-token-prefilter - EIN Durchlauf ueber den
    // gelowerten Text statt eines eigenen Pos()-Scans pro Unique-Token
    // (~82 Full-Text-Scans pro File). An jeder Textposition werden nur
    // die Tokens verglichen, deren Erstzeichen dem aktuellen Zeichen
    // entspricht (Erstzeichen-Index aus BuildAllDetectors). Semantik
    // EXAKT wie vorher: reiner Substring-Match auf dem gelowerten Text
    // (kein Whole-Word) - das Ergebnis-Set ist identisch zu
    // Pos(Token, SrcLow) > 0 pro Token.
    SrcLen := Length(SrcLow);
    PSrc   := PChar(SrcLow);        // 0-basiert indiziert
    SetLength(FoundTok, Length(gAllPrefilterTokensLow));
    Remaining := Length(gPrefilterBucketTokens);  // Early-Exit wenn alle gefunden
    p := 0;
    while (p < SrcLen) and (Remaining > 0) do
    begin
      ChOrd := Ord(PSrc[p]);
      if ChOrd <= 255 then
        for b := gPrefilterBucketStart[ChOrd]
              to gPrefilterBucketStart[ChOrd + 1] - 1 do
        begin
          TokIdx := gPrefilterBucketTokens[b];
          if FoundTok[TokIdx] then Continue;
          TokLen := Length(gAllPrefilterTokensLow[TokIdx]);
          if (p + TokLen <= SrcLen) and
             CompareMem(@PSrc[p], Pointer(gAllPrefilterTokensLow[TokIdx]),
               TokLen * SizeOf(Char)) then
          begin
            FoundTok[TokIdx] := True;
            TokenPresent.AddOrSetValue(gAllPrefilterTokensLow[TokIdx], True);
            Dec(Remaining);
          end;
        end;
      Inc(p);
    end;
    // Fallback fuer Tokens mit Erstzeichen > #255 (heute keine): alte
    // Pos-Semantik unveraendert.
    for k := 0 to High(gPrefilterTokensWideFirst) do
      if Pos(gAllPrefilterTokensLow[gPrefilterTokensWideFirst[k]], SrcLow) > 0 then
        TokenPresent.AddOrSetValue(
          gAllPrefilterTokensLow[gPrefilterTokensWideFirst[k]], True);
    Result := TokenPresent.Count > 0;
  end;

begin
  EnsureDetectorsBuilt;

  HasTimeCb    := Assigned(AOnTime);
  FilterActive := (CfgEnabledKinds(AContext) <> []) or   // TD-1: per-Scan
                  (CfgMinSeverity(AContext) <> lsHint);
  PrevCount    := Results.Count;
  TokenSetReady := False;
  TokenPresent := TDictionary<string, Boolean>.Create;
  try

  for i := 0 to High(gDetectors) do
  begin
    if not IsDetectorEnabled(gDetectors[i], AIncludeUsesCheck, AContext) then Continue;

    // Pre-Filter via RequiredTokensLow. TokenPresent enthaelt nach
    // EnsureTokenSet genau die Tokens die im File vorkommen - O(1)
    // Hash-Lookup pro Detector-Token, kein wiederholtes Pos mehr.
    if Length(gDetectors[i].RequiredTokensLow) > 0 then
    begin
      EnsureTokenSet;  // Result irrelevant - leeres Set -> alle skipen
      TokenMatch := False;
      for j := 0 to High(gDetectors[i].RequiredTokensLow) do
        if TokenPresent.ContainsKey(gDetectors[i].RequiredTokensLow[j]) then
        begin
          TokenMatch := True;
          Break;
        end;
      if not TokenMatch then Continue;
    end;

    if HasTimeCb then
      Watch := TStopwatch.StartNew;
    try
      gDetectors[i].Run(Root, FileName, Results, AContext);
    except
      // User-Cancel (EAbort) muss durchgereicht werden, damit die
      // Schleife in AnalyzeLeaksRecursive abbricht. Ein generischer
      // Detektor-Fehler hingegen blockiert die anderen Detektoren nicht.
      on EAbort do raise;
      on E: Exception do
        if Assigned(AOnError) then
          AOnError(gDetectors[i].Name, E.Message);
    end;
    if HasTimeCb then
      AOnTime(gDetectors[i].Name, Watch.ElapsedMilliseconds);
  end;

  // ---- Post-Filter ----
  // Detector-Level-Skip ist nicht fein genug fuer Adapter, die intern
  // mehrere Kinds produzieren (DfmAnalysisRunner). Daher Findings noch
  // einmal durchgehen:
  //   * Kind nicht im Profile -> raus
  //   * Severity strenger als MinSeverity -> raus (Detector koennte ein
  //     Finding mit haerterer Severity erzeugen als KIND_META erlaubt;
  //     auch CustomRules tragen variable Severity).
  // fkFileReadError ist immer durchgelassen (Diagnose-Befund), unabhaengig
  // vom Profile.
  // PrevCount-Bound: nur die in diesem Aufruf neu hinzugekommenen Findings
  // werden geprueft - frueher angelegte sind bereits Filter-validiert.
  if FilterActive then
  begin
    // TD-1 (2026-07-06): Filter-Werte per-Scan aus AContext.Config, einmal
    // vor der Schleife lesen (byte-identisch - Config ist scan-konstant).
    var EnKinds := CfgEnabledKinds(AContext);
    var MinSev  := CfgMinSeverity(AContext);
    for i := Results.Count - 1 downto PrevCount do
    begin
      if Results[i].Kind = fkFileReadError then Continue;
      if (EnKinds <> []) and
         not (Results[i].Kind in EnKinds) then
      begin
        Results.Delete(i);
        Continue;
      end;
      if Ord(Results[i].Severity) > Ord(MinSev) then
        Results.Delete(i);
    end;
  end;

  // Einschliessende Methode fuer line-basierte Befunde (MethodName='')
  // nachtragen - zentral, damit Haupt-Grid UND File-Panel sie anzeigen.
  FillMissingMethodNames(Root, Results, PrevCount);

  finally
    TokenPresent.Free;
  end;
end;

{ Zählt uses-Items über alle Dateien und liefert Top-N sortiert. }

class procedure TStaticAnalyzer2.ParseFiles(FileList: TStringList;
  var Results: TStringList);
var
  Parser     : TParser2;
  NameCounts : TDictionary<string, Integer>;
  Root       : TAstNode;
  UsesList   : TList<TAstNode>;
  UsesNode   : TAstNode;
  Item       : TAstNode;
  FileName   : string;
  i          : Integer;
  Pairs      : TArray<TPair<string, Integer>>;
  Pair       : TPair<string, Integer>;
begin
  Parser     := TParser2.Create;
  NameCounts := TDictionary<string, Integer>.Create;
  try
    for i := 0 to FileList.Count - 1 do
    begin
      FileName := FileList[i];
      try
        Root := Parser.ParseFile(FileName);
      except
        on E: Exception do
        begin
          Results.Add('ERROR ' + FileName + ': ' + E.Message);
          Continue;
        end;
      end;

      try
        // Alle uses-Klauseln im Baum finden (interface + implementation)
        UsesList := Root.FindAll(nkUses);
        try
          for UsesNode in UsesList do
            for Item in UsesNode.Children do
              if Item.Kind = nkUsesItem then
              begin
                if NameCounts.ContainsKey(Item.Name) then
                  NameCounts[Item.Name] := NameCounts[Item.Name] + 1
                else
                  NameCounts.Add(Item.Name, 1);
              end;
        finally
          UsesList.Free;
        end;
      finally
        Root.Free;
      end;
    end;

    // Absteigend nach Häufigkeit sortieren
    Pairs := NameCounts.ToArray;
    TArray.Sort<TPair<string, Integer>>(Pairs,
      TComparer<TPair<string, Integer>>.Construct(
        function(const A, B: TPair<string, Integer>): Integer
        begin
          Result := B.Value - A.Value;
        end));

    for Pair in Pairs do
      Results.Add(Format('%d  %s', [Pair.Value, Pair.Key]));
  finally
    Parser.Free;
    NameCounts.Free;
  end;
end;

class procedure TStaticAnalyzer2.ParseLeaks(FileList: TStringList;
  Results: TObjectList<TLeakFinding>; AProgress: TProc<Integer, Integer>;
  AIncludeUsesCheck: Boolean; IndexFileList: TStringList);
// MAX_FILE_BYTES kommt aus uSCAConsts.DetectorMaxFileBytes (analyser.ini ->
// MaxFileMB * 1024 * 1024). Default 5 MB.

  procedure AddFileError(const AFileName, AMsg: string);
  var F: TLeakFinding;
  begin
    F            := TLeakFinding.Create;
    F.FileName   := AFileName;
    F.MethodName := '';
    F.LineNumber := '0';
    F.MissingVar := AMsg;
    F.SetKind(fkFileReadError);
    Results.Add(F);
  end;

  procedure SafeProgress(Current, Total: Integer);
  begin
    if not Assigned(AProgress) then Exit;
    try
      AProgress(Current, Total);
    except
      on EAbort do raise; // User-Cancel muss durchgereicht werden!
      // andere Callback-Exceptions duerfen die Analyse nicht abbrechen
    end;
  end;

var
  Parser    : TParser2;
  Root      : TAstNode;
  FileName  : string;
  FileSize  : Int64;
  i, Total  : Integer;
  LogPath   : string;
  LogStream : TStreamWriter;
  Watch     : TStopwatch;
  ElapsedMs : Int64;
  // Phase-Tracking fuer Crash-Diagnose. Wird an Schluesselstellen aktualisiert
  // und im Outer-Handler bei "Analyseabbruch: ..." mit-geloggt. Variable-
  // Assignment ist quasi-kostenlos; kein Logging im Happy-Path.
  LastPhase : string;
  LastFile  : string;
  // Phase-3-Foundation (Konzept_D2): besitzt die per-Scan-Instanzen
  // (AstFileCache/SymbolRefIndex/DfmRepoIndex). Globals bleiben Backward-
  // Compat-Aliase; der Context steuert nur den Lifecycle. Verhaltensneutral.
  Ctx : TAnalyzeContext;
  // UnusedSuppression (Audit_CodeReview #2, 2026-07-05): die im Main-Loop
  // pro Datei eingesammelten '// noinspection'-Marker. Der Context BESITZT
  // die Collection waehrend des Scans; im inneren finally (vor FreeAndNil(
  // Ctx)) wird sie per Ownership-Transfer hierher gerettet, weil die
  // Suppression-Phase (TSuppression.ApplyToFindings) erst NACH dem Context-
  // Teardown laeuft. Die aeusserste try-finally-Klammer unten gibt sie auf
  // JEDEM Pfad frei (auch beim Re-Raise aus dem Scan).
  PreMarkers : TObjectDictionary<string, TList<TSuppressionMarker>>;
  // Audit 2026-07-01 (Global-State): Snapshot der Caller/User/INI-konfigurierten
  // LeakyClasses VOR der Auto-Discovery. AutoDiscovery ergaenzt die GLOBALE
  // LeakyClasses waehrend des Scans; ohne Restore akkumulieren die auto-
  // entdeckten Klassen ueber wiederholte Scans (Server/IDE-Reuse) und
  // verfaelschen Folge-Scans. Im finally wird auf diesen Baseline restauriert.
  LeakySnapshot : TArray<string>;
  // TD-1 Inkrement 2b (2026-07-06): per-Scan-Filter-Werte fuer die Post-Filter-
  // Phase. Diese laeuft NACH FreeAndNil(Ctx) (Suppression/Confidence unten),
  // darum werden die Werte - wie PreMarkers - vorher aus dem Context gerettet.
  PostMinConf : TFindingConfidence;
  PostEnKinds : TFindingKinds;

  procedure LogLine(const S: string);
  begin
    if Assigned(LogStream) then
      try LogStream.WriteLine(S); LogStream.Flush; except end;
  end;

begin
  if (FileList = nil) or (Results = nil) then Exit;

  // Audit 2026-07-01 (Global-State): Baseline der Caller/User/INI-konfigurierten
  // LeakyClasses sichern (VOR jeder Auto-Discovery). Im finally wird darauf
  // zurueckgesetzt, damit die per-Scan auto-entdeckten Klassen nicht ueber
  // wiederholte Scans in der GLOBALEN LeakyClasses akkumulieren.
  if AutoDiscoverCustomClasses and Assigned(LeakyClasses) then
    LeakySnapshot := LeakyClasses.ToStringArray
  else
    LeakySnapshot := nil;

  // Log-Datei zur Diagnose: zeigt pro Datei welcher Schritt wie lange dauert.
  // Bei "App haengt" laesst sich daraus ablesen welche Datei der Uebeltaeter ist.
  LogStream := nil;
  // Selbe Log-Datei wie der Scan - liegt im %APPDATA%\StaticCodeAnalyser
  // Verzeichnis (gleiches wie ignore.txt).
  LogPath := TIgnoreList.LogFilePath;
  try
    if not DirectoryExists(TIgnoreList.ConfigDir) then
      ForceDirectories(TIgnoreList.ConfigDir);
  except
    // Best-effort: kein ConfigDir = kein Log, der Scan laeuft trotzdem.
  end;
  Parser := nil;
  LastPhase := 'init';
  LastFile  := '';
  PreMarkers := nil;
  // UnusedSuppression (Audit #2, 2026-07-05): aeusserste Klammer NUR fuer
  // PreMarkers - die Marker-Collection wechselt im inneren finally per
  // Ownership-Transfer vom Ctx hierher und muss auch dann freigegeben
  // werden, wenn der Scan per Re-Raise abbricht (die Post-Filter unten
  // laufen dann nie). Bewusst ohne Re-Indent des Bestands - gleiches
  // Muster wie der Outer-Diagnose-Try weiter unten.
  try
  // Eine gemeinsame try-finally klammer fuer LogStream UND Parser - so leakt
  // weder bei Parser-Create-OOM der LogStream noch umgekehrt.
  try
    try
      // Append-Modus, damit der Scan-Log nicht ueberschrieben wird
      LogStream := TStreamWriter.Create(LogPath, True, TEncoding.UTF8);
      LogLine('=== ParseLeaks gestartet: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now, TFormatSettings.Invariant)
              + ' (' + IntToStr(FileList.Count) + ' Dateien) ===');
    except
      LogStream := nil;
    end;

    Ctx := nil;   // defensiv: FreeAndNil(Ctx) im finally muss immer sicher sein

    // Outer-Diagnose-Try: bei Exception VOR re-raise die letzte Phase + das
    // aktuelle File ins Log schreiben. Sonst sieht der Caller-Outer-Handler
    // nur "Analyseabbruch: <Message>" ohne Kontext.
    try


    // AST-File-Cache: pro .pas einmal parsen, von beiden Pre-Indizes UND
    // dem Main-Loop wiederverwendet. Spart 2 von 3 Parser-Durchlaeufen pro
    // File (perf_analyse.md Hot-Spot 🅐).
    // Phase-3 D.2.3: Context erzeugen, der die per-Scan-Instanzen
    // (AstFileCache/DfmRepoIndex/SymbolRefIndex) BESITZT und am Scan-Ende
    // freigibt. Keine Prozess-Globals mehr fuer diese drei -> jeder (auch
    // paralleler) Scan arbeitet auf eigenem State.
    Ctx := TAnalyzeContext.Create;
    // TD-1 (2026-07-06): skalare Scan-Config JETZT aus den uSCAConsts-Globals
    // in den Context snapshotten (Globals halten hier bereits die Scan-Config
    // aus ApplyConfig/SetupForRun). Ab hier lesen die migrierten Scan-Pfade
    // Schwellen/Filter/Flags aus Ctx.Config statt direkt vom Prozess-Global -
    // Voraussetzung fuer parallele Scans, byte-identisch weil Config==Globals.
    Ctx.SnapshotConfigFromGlobals;
    // TD-1 Inkrement 2c (2026-07-06): LeakyClasses-Baseline in den Context
    // kopieren. Der Global haelt hier bereits die per-Scan-Baseline
    // (RegisterToLeakyClasses lief in ApplyConfig/SetupForRun VOR dem Scan);
    // ab jetzt haengt die AutoDiscovery ihre Funde an Ctx.LeakyClasses statt an
    // den Global (s.u.), und die Leak-Detektoren lesen via CtxLeakyClasses aus
    // dem Context. Byte-identisch: gleicher Inhalt + gleiche List-Settings wie
    // der Global, nur nicht mehr prozessweit geteilt. AddStrings auf die
    // sortierte Ziel-Liste uebernimmt den Inhalt (Reihenfolge egal, dupIgnore).
    if Assigned(LeakyClasses) then
      Ctx.LeakyClasses.AddStrings(LeakyClasses);

    Ctx.AstFileCache := TAstFileCache.Create;

    // File-Text-Cache: pro .pas einmal Lines.LoadFromFile, von den
    // File-Scan-Detektoren (Todo, With, Reversed, Length, Tautological,
    // DuplicateBlock, CustomRule) wiederverwendet (perf_analyse.md
    // Hot-Spot 🅑).
    // Lifecycle-Fix 2026-07-04 (Audit Global-State): Clear + WIEDERVERWENDUNG
    // der einen Prozess-Instanz statt FreeAndNil + Re-Create. Das alte Muster
    // riss ein Use-after-free-Fenster fuer jeden Halter der ALTEN Referenz
    // auf (das Cache-OBJEKT wechselte die Identitaet bei jedem Scan-Start).
    // Clear ist hier sicher: das TObjectDictionary (doOwnsValues) gibt nur
    // die EINTRAEGE frei - saemtliche AcquireLines-Konsumenten (Detektoren,
    // uSuppression, uFindingFingerprint, uStaticAnalyzer2) nutzen die Lines
    // strikt transient (Acquire -> try/finally ReleaseLines) und halten
    // zwischen Scans keine Value-Referenzen; der Main-Loop cleart ohnehin
    // schon nach jedem File. Kein Leak: Clear raeumt dieselben Eintraege ab,
    // die vorher der Destructor abgeraeumt hat.
    if Assigned(gFileTextCache) then
      gFileTextCache.Clear                 // Instanz bleibt stabil - alte
                                           // Referenzen bleiben gueltig
    else
      gFileTextCache := TFileTextCache.Create;
    Ctx.FileTextCache := gFileTextCache;   // nur referenziert (lebt weiter)

    // Repo-weiten Index fuer Cross-Unit-Detektoren einmal pro Scan
    // aufbauen. Wenn das Build crasht (defekte .pas), schluckt der
    // Index das selbst - der Hauptanalyse-Pfad laeuft auch ohne Index
    // weiter, Cross-Unit-Detektoren schweigen dann mangels Daten.
    //
    // IndexFileList ist optional: wenn der Aufrufer einen breiteren
    // Projekt-Scope mitgibt (z.B. Single-File-Analyse mit ProjectRoot),
    // wird der Index aus dem groesseren Scope aufgebaut. Sonst Default:
    // Index = analysierte Files.
    var IndexFiles: TStringList := IndexFileList;
    if IndexFiles = nil then IndexFiles := FileList;

    LastPhase := 'Pre-Index: DfmRepoIndex.Build';
    Ctx.DfmRepoIndex := TDfmRepoIndex.Create;
    try
      Ctx.DfmRepoIndex.Build(IndexFiles, Ctx.AstFileCache);
    except
      FreeAndNil(Ctx.DfmRepoIndex);   // ggf. nil (Build-Fehler) - ok
    end;

    // Symbol-Reference-Index. Visibility-Detektoren (fkCanBeUnitPrivate,
    // fkCanBeStrictPrivate, fkCanBeProtected, fkUnusedPublicMember)
    // konsultieren ihn NICHT mehr - sie laufen single-file. Index wird
    // hier dennoch aufgebaut weil andere Konsumenten (Tests, mORMot-Cross-
    // Check) ihn lesen; kann perspektivisch entfallen wenn keiner mehr
    // referenziert.
    LastPhase := 'Pre-Index: SymbolRefIndex.Build';
    Ctx.SymbolRefIndex := TSymbolReferenceIndex.Create;
    try
      Ctx.SymbolRefIndex.Build(IndexFiles, Ctx.AstFileCache);
    except
      FreeAndNil(Ctx.SymbolRefIndex);     // ggf. nil (Build-Fehler) - ok
    end;
    Ctx.DetectorTimings := gDetectorTimings;    // nur referenziert (Caller-owned)

    LastPhase := 'Parser.Create + Main-Loop start';
    Parser := TParser2.Create;
    Total  := FileList.Count;
    for i := 0 to Total - 1 do
    begin
      SafeProgress(i + 1, Total);

      FileName := FileList[i];
      LastFile  := FileName;
      LastPhase := Format('File %d/%d: pre-check', [i + 1, Total]);

      // Leerer Dateiname → ignorieren (defensiv)
      if Trim(FileName) = '' then
      begin
        AddFileError('(leer)', 'Leerer Dateiname in der Liste');
        Continue;
      end;

      // Datei-Existenz pruefen (mit Exception-Schutz – Race-Conditions)
      try
        if not TFile.Exists(FileName) then
        begin
          AddFileError(FileName, 'Datei nicht gefunden');
          Continue;
        end;
      except
        on E: Exception do
        begin
          AddFileError(FileName, 'Datei-Existenzpruefung fehlgeschlagen: ' + E.Message);
          Continue;
        end;
      end;

      // Datei-Groesse pruefen (Datei kann zwischen Exists und GetSize verschwinden)
      try
        FileSize := TFile.GetSize(FileName);
      except
        on E: Exception do
        begin
          AddFileError(FileName, 'Dateigroesse nicht ermittelbar: ' + E.Message);
          Continue;
        end;
      end;

      if FileSize > Ctx.Config.MaxFileBytes then   // TD-1: per-Scan statt Global
      begin
        AddFileError(FileName, Format('Datei zu groß (%.1f MB) – Analyse übersprungen',
                                     [FileSize / (1024 * 1024)]));
        Continue;
      end;

      // Leere Dateien ueberspringen (nichts zu analysieren, kein Fehler)
      if FileSize = 0 then Continue;

      // Datei einlesen und parsen
      LogLine(Format('[%d/%d] %s (%d KB)',
                     [i + 1, Total, FileName, FileSize div 1024]));
      Watch := TStopwatch.StartNew;

      Root := nil;
      // OwnsRoot=False wenn der Cache das Root besitzt (er freet es bei
      // Evict). True wenn lokal geparst -> nach AST-Verarbeitung selbst free.
      var OwnsRoot := False;
      LastPhase := Format('File %d/%d: Parse/Acquire', [i + 1, Total]);
      try
        try
          // Cache-Pfad bevorzugen: Pre-Indizes haben das Root schon erzeugt.
          if Assigned(Ctx.AstFileCache) then
          begin
            Root := Ctx.AstFileCache.Acquire(FileName);
            OwnsRoot := False;
          end
          else
          begin
            Root := Parser.ParseFile(FileName);
            OwnsRoot := True;
          end;
        except
          on E: Exception do
          begin
            LogLine('  PARSER-FEHLER: ' + E.Message);
            AddFileError(FileName, 'Lesefehler: ' + E.Message);
            Continue;
          end;
        end;

        if Root = nil then
        begin
          // Bei Cache-Pfad ist die konkrete Parser-Exception in
          // gAstFileCache.FFailed hinterlegt - rausholen damit der Log
          // dieselbe Info enthaelt wie im Fallback-Pfad.
          var FailMsg := '';
          if Assigned(Ctx.AstFileCache) then
            FailMsg := Ctx.AstFileCache.GetFailMessage(FileName);
          if FailMsg = '' then FailMsg := 'Parser lieferte kein Ergebnis';
          LogLine('  PARSER-FEHLER: ' + FailMsg);
          AddFileError(FileName, FailMsg);
          Continue;
        end;

        ElapsedMs := Watch.ElapsedMilliseconds;
        // Im Cache-Pfad ist das eine Cache-Lookup-Zeit (~0 ms bei Hit);
        // im Fallback-Pfad echte Parse-Zeit. Slow-Warning nur fuer letzteres.
        if OwnsRoot then
        begin
          if ElapsedMs > 500 then
            LogLine(Format('  Parse: %d ms (langsam!)', [ElapsedMs]))
          else if Assigned(LogStream) then
            LogLine(Format('  Parse: %d ms', [ElapsedMs]));
        end
        else if Assigned(LogStream) then
          LogLine(Format('  Acquire: %d ms (cache)', [ElapsedMs]));

        // Detektoren ausfuehren - jeder einzeln geschuetzt, damit ein
        // fehlerhafter Detektor nicht alle anderen blockiert.
        // Vorher hardcoded 'for DetectorIdx := 0 to 20' + grosse case-Anweisung -
        // jetzt iterativ ueber RunAllDetectors-Helper. Hinzufuegen eines
        // Detektors -> nur ein Eintrag in der Helper-Funktion.
        // Closures captern LogStream/Results/FileName direkt, da nested procs
        // (LogLine/AddFileError) von anonymen Methoden nicht referenziert
        // werden duerfen (E2555).
        var CaptLogStream := LogStream;
        var CaptResults   := Results;
        var CaptFileName  := FileName;

        // Auto-Discovery: wenn aktiviert, vor dem MemoryLeak-Detektor das AST
        // nach Custom-Klassen scannen und LeakyClasses ergaenzen. Wirkt fuer
        // alle nachfolgenden Files in DIESEM Lauf - kumulativ, weil
        // Sorted+dupIgnore.
        // ExcludeLeakyClasses werden hier respektiert - sonst koennte
        // Discovery eine vom User explizit ausgeschlossene Klasse wieder
        // einschleusen.
        // Auto-Discovery: TCustomClassDiscovery teilt die gefundenen Klassen
        // in zwei Gruppen auf - "instantiable" (Konstruktor/Destruktor oder
        // Create-Aufruf in der Unit) und "static-only" (keine Instanziierungs-
        // Hinweise gefunden, vermutlich Utility-Klassen).
        //
        //  * Instantiable -> Runtime-LeakyClasses (Detektion in diesem Lauf)
        //                    + DiscoveredClasses (fuer .log)
        //  * StaticOnly   -> nur DiscoveredStaticClasses (.log, auskommentiert)
        //
        // Beide Gruppen respektieren LeakyClassExcludes. Die INI bleibt
        // unangetastet; der User entscheidet handisch welche Klasse er in
        // [Detectors] LeakyClasses uebernimmt.
        LastPhase := Format('File %d/%d: AutoDiscovery', [i + 1, Total]);
        if Ctx.Config.AutoDiscover then   // TD-1: per-Scan-Gate statt Global
        try
          var Instantiable : TArray<string>;
          var StaticOnly   : TArray<string>;
          TCustomClassDiscovery.DiscoverInUnit(Root, Instantiable, StaticOnly);

          for var Cls in Instantiable do
          begin
            if Assigned(LeakyClassExcludes) and
               (LeakyClassExcludes.IndexOf(Cls) >= 0) then Continue;
            // TD-1 Inkrement 2c: Discovery-Funde an die per-Scan-Kopie haengen
            // (nicht mehr an den Prozess-Global). Ctx.LeakyClasses existiert
            // immer (Constructor), der Guard bleibt als Spiegel des alten Codes.
            if Assigned(Ctx.LeakyClasses) then
              Ctx.LeakyClasses.Add(Cls);
            if Assigned(DiscoveredClasses) then
              DiscoveredClasses.Add(Cls);
          end;

          for var Cls in StaticOnly do
          begin
            if Assigned(LeakyClassExcludes) and
               (LeakyClassExcludes.IndexOf(Cls) >= 0) then Continue;
            // Bewusst NICHT in LeakyClasses - static-only Klassen haben
            // keine Instanzen und brauchen keine Leak-Detektion.
            if Assigned(DiscoveredStaticClasses) then
              DiscoveredStaticClasses.Add(Cls);
          end;
        except
          // Audit 2026-07-01 (Error-Handling): Discovery-Fehler auf EINER Datei
          // darf nicht den GESAMTEN Scan abreissen (frueher: Exception
          // propagierte an der try/finally vorbei aus der File-Schleife).
          // Wie der RunAllDetectors-Fehlerpfad: als fkFileReadError melden +
          // weiter. User-Cancel (EAbort) bleibt durchgereicht.
          on EAbort do raise;
          on E: Exception do
          begin
            var Ferr := TLeakFinding.Create;
            Ferr.FileName   := FileName;
            Ferr.MethodName := '';
            Ferr.LineNumber := '0';
            Ferr.MissingVar := 'AutoDiscovery failed: ' + E.Message;
            Ferr.SetKind(fkFileReadError);
            Results.Add(Ferr);
          end;
        end;

        // Custom-Rules (aus analyser-rules.yml) NACH den built-in
        // Detektoren - so liegen sie im Output sortierbar zusammen.
        // No-op wenn TCustomRuleDetector.LoadFromYaml nicht aufgerufen
        // wurde (HasRules = False).
        LastPhase := Format('File %d/%d: CustomRules', [i + 1, Total]);
        if TCustomRuleDetector.HasRules then
          try
            TCustomRuleDetector.AnalyzeFile(FileName, Results, Ctx);
          except
            // Audit 2026-07-01 (Error-Handling): eine fehlerhafte Custom-Rule
            // darf nicht den GESAMTEN Scan abreissen - als fkFileReadError
            // melden + weiter. EAbort bleibt durchgereicht.
            on EAbort do raise;
            on E: Exception do
            begin
              var Ferr := TLeakFinding.Create;
              Ferr.FileName   := FileName;
              Ferr.MethodName := '';
              Ferr.LineNumber := '0';
              Ferr.MissingVar := 'CustomRules failed: ' + E.Message;
              Ferr.SetKind(fkFileReadError);
              Results.Add(Ferr);
            end;
          end;

        LastPhase := Format('File %d/%d: RunAllDetectors', [i + 1, Total]);
        RunAllDetectors(Root, FileName, Results, AIncludeUsesCheck, Ctx,
          procedure(const Name: string; ElapsedMs: Int64)
          var
            Acc: TPair<Int64, Integer>;
          begin
            if (ElapsedMs > 500) and Assigned(CaptLogStream) then
              try
                CaptLogStream.WriteLine(Format('  Detektor %s: %d ms (langsam!)',
                  [Name, ElapsedMs]));
                CaptLogStream.Flush;
              except end;
            // Per-Detector-Timing aggregieren wenn Accumulator vom Caller
            // bereitgestellt wurde. Spart einem CLI-Konsumenten den eigenen
            // AOnTime-Pfad zu bauen.
            if Assigned(gDetectorTimings) then
            begin
              if gDetectorTimings.TryGetValue(Name, Acc) then
                gDetectorTimings.AddOrSetValue(Name,
                  TPair<Int64, Integer>.Create(Acc.Key + ElapsedMs, Acc.Value + 1))
              else
                gDetectorTimings.Add(Name,
                  TPair<Int64, Integer>.Create(ElapsedMs, 1));
            end;
          end,
          procedure(const Name, ErrMsg: string)
          begin
            if Assigned(CaptLogStream) then
              try
                CaptLogStream.WriteLine(Format('  DETEKTOR %s FEHLER: %s',
                  [Name, ErrMsg]));
                CaptLogStream.Flush;
              except end;
            // entspricht AddFileError - inlined wegen Capture-Limits
            var F := TLeakFinding.Create;
            F.FileName   := CaptFileName;
            F.MethodName := '';
            F.LineNumber := '0';
            F.MissingVar := Format('Detector %s failed: %s',
                                   [Name, ErrMsg]);
            F.SetKind(fkFileReadError);
            CaptResults.Add(F);
          end);

        // UnusedSuppression Scan-Zeit-Collection (Audit #2a, 2026-07-05):
        // Marker dieser Datei JETZT einsammeln - der Dateitext liegt noch
        // heiss im gFileTextCache (das finally unten cleart ihn gleich).
        // Bewusst NUR fuer erfolgreich gescannte Dateien (nach RunAll-
        // Detectors): fuer Parse-Fehler-Dateien liefe kein Detektor, jeder
        // Marker waere trivial "unused" - das waere Rauschen, kein Signal.
        LastPhase := Format('File %d/%d: CollectSuppressionMarkers',
                            [i + 1, Total]);
        try
          TSuppression.CollectMarkersForScan(FileName, Ctx.SuppressionMarkers);
        except
          // Best-effort: ein Collection-Fehler degradiert nur das Unused-
          // Tracking dieser Datei, nicht den Scan. User-Cancel geht durch.
          on EAbort do raise;
          on Exception do ;
        end;
      finally
        LastPhase := Format('File %d/%d: finally Root.Free/Evict', [i + 1, Total]);
        if OwnsRoot then
          Root.Free
        else if Assigned(Ctx.AstFileCache) then
          Ctx.AstFileCache.Evict(FileName);  // Memory-Peak bremsen
        LastPhase := Format('File %d/%d: finally gFileTextCache.Clear', [i + 1, Total]);
        // Text-Cache fuer die abgearbeitete Datei freigeben - die File-Scan-
        // Detektoren haben sie konsumiert, niemand brauchts mehr.
        if Assigned(gFileTextCache) then
          gFileTextCache.Clear;
      end;
    end;
    LastPhase := 'Main-Loop fertig, post-process';

    // Outer-Diagnose-Try Schliessung: bei Exception VOR re-raise die letzte
    // Phase + das aktuelle File ins Log schreiben. So sieht der Caller-Outer-
    // Handler (AnalyzeLeaksRecursive etc.) statt nur "Analyseabbruch: <msg>"
    // im scan.log einen klaren Trail "letzte Phase: ... aktuelles File: ...".
    except
      on EAbort do raise;
      on E: Exception do
      begin
        LogLine('');
        LogLine(Format('=== ABBRUCH: %s: %s ===',
                       [E.ClassName, E.Message]));
        LogLine(Format('=== letzte Phase: %s ===',  [LastPhase]));
        if LastFile <> '' then
          LogLine(Format('=== aktuelles File: %s ===', [LastFile]))
        else
          LogLine('=== aktuelles File: (n/a - Crash vor Main-Loop) ===');
        // Re-raise damit der Caller-Outer-Handler sein "Analyseabbruch: ..."
        // SARIF/UI-Finding wie bisher anlegt. Im scan.log steht jetzt der
        // Kontext direkt vor dieser Meldung.
        raise;
      end;
    end;
  finally
    // LogStream auch bei EAbort sauber schliessen, danach Parser.
    // Eine gemeinsame Klammer verhindert dass Parser-Create-OOM den LogStream
    // hinterlaesst oder umgekehrt.
    LogLine('=== ParseLeaks fertig: ' + FormatDateTime('hh:nn:ss', Now, TFormatSettings.Invariant) + ' ===');
    if Assigned(LogStream) then
      FreeAndNil(LogStream);
    Parser.Free;
    // Repo-Index nach dem Scan wieder freigeben - Cross-Unit-Detektoren
    // ausserhalb dieses Scans sollen nicht versehentlich stale Daten sehen.
    // Phase-3-Foundation: der Context besitzt AstFileCache/SymbolRefIndex/
    // DfmRepoIndex und gibt sie hier frei (gleiche 3 Instanzen, gleiche
    // Reihenfolge wie zuvor). Danach die Backward-Compat-Globals auf nil
    // setzen (zeigten auf die jetzt freigegebenen Instanzen). gFileTextCache
    // wird vom Context NICHT angefasst und lebt absichtlich weiter.
    // UnusedSuppression (Audit #2, 2026-07-05): die Marker-Collection
    // ueberlebt den Context - Ownership-Transfer ins lokale PreMarkers
    // (Suppression-Phase unten braucht sie; die aeusserste Klammer gibt
    // sie frei). Ctx.Destroy sieht nil und fasst nichts an.
    if Ctx <> nil then
    begin
      PreMarkers := Ctx.SuppressionMarkers;
      Ctx.SuppressionMarkers := nil;
    end;
    // TD-1 Inkrement 2b (2026-07-06): per-Scan-Filter-Werte VOR FreeAndNil(Ctx)
    // retten - die Post-Filter-Phase (Suppression/Confidence unten) laeuft nach
    // dem Context-Teardown, wuerde also sonst wieder die Prozess-Globals lesen.
    // Cfg*(Ctx) ist nil-sicher (Global-Fallback). Byte-identisch, weil der
    // Config-Snapshot == Global zur Scan-Zeit ist (Filter-Skalar mutiert nicht).
    PostMinConf := CfgMinConfidence(Ctx);
    PostEnKinds := CfgEnabledKinds(Ctx);
    FreeAndNil(Ctx);
    // Audit 2026-07-01 (Global-State): die in diesem Scan auto-entdeckten Klassen
    // wieder aus der GLOBALEN LeakyClasses entfernen -> zurueck auf die Caller-
    // Baseline. Verhindert Akkumulation ueber wiederholte Scans (Server/IDE-
    // Reuse) und damit Detektions-Drift in Folge-Scans.
    // TD-1 Inkrement 2c (2026-07-06): jetzt effektiv ein No-Op - seit die
    // AutoDiscovery in Ctx.LeakyClasses schreibt (s.o.), wird der Global
    // scan-zeit NICHT mehr mutiert; Clear+Re-Add stellt also dieselbe Baseline
    // wieder her. BEWUSST BELASSEN (minimiert Diff/Risiko ohne Build und bleibt
    // korrekt, falls je wieder etwas den Global scan-zeit anfasst).
    if AutoDiscoverCustomClasses and Assigned(LeakyClasses) then
    begin
      LeakyClasses.Clear;
      if LeakySnapshot <> nil then
        LeakyClasses.AddStrings(LeakySnapshot);
    end;
    // gFileTextCache lebt absichtlich weiter bis zur naechsten Scan-Start-
    // Phase (oder dem finalization-Block). Suppression-Phase + ContextHash-
    // Berechnung im SARIF/Baseline-Output rufen AcquireLines fuer jede
    // Finding-Datei; ohne den Cache haette das 191k+ einzelne LoadFromFile
    // + UTF-8-Validierungen zur Folge (gemessen +20-60s pro Real-World-
    // Scan). Per-File-Clear in der Detector-Schleife bleibt, der Cache
    // fuellt sich im Post-Scan lazy nach.
  end;

  // Suppression-Kommentare auswerten und Befunde filtern. PreMarkers =
  // Scan-Zeit-Marker-Collection (Audit #2a): damit meldet die Unused-
  // Emission auch stale Marker in Dateien ohne (suppresste) Findings.
  // Das ENTFERNEN von Findings laeuft unveraendert ueber die lazy
  // BuildMap-Lookups - byte-identisch zum bisherigen Filter-Verhalten.
  try
    TSuppression.ApplyToFindings(Results, PreMarkers, @PostEnKinds);
  except
    // Suppression-Fehler duerfen das Ergebnis nicht zerstoeren
  end;

  // Path-Overrides anwenden (analyser.ini [PathOverrides]). Wird nach
  // uSuppression aufgerufen, sodass `// noinspection` Vorrang hat.
  try
    TPathOverrides.ApplyToFindings(Results);
  except
    // Path-Override-Fehler duerfen das Ergebnis nicht zerstoeren
  end;

  // Konfidenz-Schwellwert anwenden (PostMinConf = per-Scan-Snapshot von
  // FindingMinConfidence, vor FreeAndNil(Ctx) gerettet - TD-1 2b).
  // Verwirft heuristische Befunde unter der Schwelle (Default fcMedium ->
  // nur fcLow raus). Zuletzt in der Pipeline: Suppression/Path-Overrides
  // sollen unabhaengig von der Confidence greifen koennen.
  try
    TConfidenceFilter.ApplyToFindings(Results, PostMinConf);
  except
    // Filter-Fehler duerfen das Ergebnis nicht zerstoeren
  end;

  finally
    // PreMarkers-Klammer (s. Kommentar am Prozedur-Anfang): Scan-Zeit-
    // Marker-Collection auf jedem Pfad freigeben. nil-sicher.
    FreeAndNil(PreMarkers);
  end;
end;

class function TStaticAnalyzer2.AnalyzeLeaks(const FileName: string;
  AIncludeUsesCheck: Boolean): TObjectList<TLeakFinding>;

  procedure AddError(const Msg: string);
  var F: TLeakFinding;
  begin
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := '';
    F.LineNumber := '0';
    F.MissingVar := Msg;
    F.SetKind(fkFileReadError);
    Result.Add(F);
  end;

var
  FileList: TStringList;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  if Trim(FileName) = '' then
  begin
    AddError('Kein Dateiname angegeben');
    Exit;
  end;

  FileList := TStringList.Create;
  try
    FileList.Add(FileName);
    try
      ParseLeaks(FileList, Result, nil, AIncludeUsesCheck);
    except
      on E: Exception do
        AddError('Analyseabbruch: ' + E.Message);
    end;
  finally
    FileList.Free;
  end;
end;

class function TStaticAnalyzer2.AnalyzeLeaks(const FileName: string;
  const ProjectRoot: string;
  AIncludeUsesCheck: Boolean): TObjectList<TLeakFinding>;
// Single-File-Findings + projektweit aufgebauter Symbol-Reference-Index.
// Hinweis: seit dem Visibility-Detektor-Refactor (single-file only) ist
// der projektweite Index fuer Visibility-Detektoren nicht mehr noetig;
// die Overload bleibt fuer andere Detektoren erhalten (DFM-Repo-Index,
// Cross-Unit-Symbol-Lookup, falls spaeter benoetigt).
//
// Wenn ProjectRoot leer ist oder das Verzeichnis nicht existiert, faellt
// die Routine auf den einfachen Single-File-Pfad zurueck (kein Index).

  procedure AddError(const Msg: string);
  var F: TLeakFinding;
  begin
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := '';
    F.LineNumber := '0';
    F.MissingVar := Msg;
    F.SetKind(fkFileReadError);
    Result.Add(F);
  end;

var
  AnalyzeList : TStringList;
  IndexList   : TStringList;
  ScanErr     : string;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  if Trim(FileName) = '' then
  begin
    AddError('Kein Dateiname angegeben');
    Exit;
  end;

  // ProjectRoot leer oder ungueltig -> Fallback auf den klassischen
  // Single-File-Pfad ohne Cross-Unit-Index.
  if (Trim(ProjectRoot) = '') or (not DirectoryExists(ProjectRoot)) then
  begin
    Result.Free;
    Result := AnalyzeLeaks(FileName, AIncludeUsesCheck);
    Exit;
  end;

  AnalyzeList := TStringList.Create;
  IndexList   := nil;
  try
    AnalyzeList.Add(FileName);
    try
      IndexList := TStaticFiles.TryGetAllPasFiles(ProjectRoot, ScanErr,
        nil, nil);
    except
      IndexList := nil;
    end;
    // Bei nil oder leerer IndexList faellt ParseLeaks intern auf
    // AnalyzeList zurueck - also identisches Verhalten zu Single-File.
    try
      ParseLeaks(AnalyzeList, Result, nil, AIncludeUsesCheck, IndexList);
    except
      on E: Exception do
        AddError('Analyseabbruch: ' + E.Message);
    end;
  finally
    IndexList.Free;
    AnalyzeList.Free;
  end;
end;

class function TStaticAnalyzer2.AnalyzeLeaksRecursive(const Path: string;
  AProgress: TProc<Integer, Integer>;
  AIncludeUsesCheck: Boolean;
  AIgnore: TIgnoreList): TObjectList<TLeakFinding>;

  procedure AddError(const Msg: string);
  var F: TLeakFinding;
  begin
    F            := TLeakFinding.Create;
    F.FileName   := Path;
    F.MethodName := '';
    F.LineNumber := '0';
    F.MissingVar := Msg;
    F.SetKind(fkFileReadError);
    Result.Add(F);
  end;

var
  FileList : TStringList;
  ScanErr  : string;
begin
  Result := TObjectList<TLeakFinding>.Create(True);

  if Trim(Path) = '' then
  begin
    AddError('Kein Pfad angegeben');
    Exit;
  end;

  if not DirectoryExists(Path) then
  begin
    AddError('Verzeichnis nicht gefunden: ' + Path);
    Exit;
  end;

  // Dateien sammeln. Den Progress-Callback nutzen wir auch hier mit
  // Total = -1 als Marker fuer "Scanne Verzeichnis" - der UI-Layer kann
  // dann einen Status-Text setzen und Application.ProcessMessages /
  // Abort-Check durchfuehren. Bei nicht uebergebenem Callback passiert
  // nichts.
  try
    FileList := TStaticFiles.TryGetAllPasFiles(Path, ScanErr,
      procedure(FilesFound: Integer)
      begin
        if Assigned(AProgress) then
          AProgress(FilesFound, -1);
      end,
      AIgnore);
  except
    on EAbort do
    begin
      // Abbruch bereits waehrend des Verzeichnis-Scans
      FreeAndNil(Result);
      raise;
    end;
    on E: Exception do
    begin
      // Nicht-EAbort-Fehler im Verzeichnis-Scan (z.B. OOM): frueher
      // propagierte er ungefangen aus der Funktion -> die bereits erzeugte
      // Result-Liste leakte (kein umschliessendes try/finally). Jetzt als
      // Finding melden und die (nicht-leere) Liste sauber zurueckgeben.
      // (FileList ist hier unassigned - Wurf VOR dem Return -> KEIN FileList.Free;
      //  das folgende ParseLeaks-try/finally wird per Exit bewusst uebersprungen.)
      AddError('Verzeichnis-Scan fehlgeschlagen: ' + E.Message);
      Exit;
    end;
  end;
  try
    if ScanErr <> '' then
      AddError('Verzeichnis-Scan: ' + ScanErr);

    if FileList.Count = 0 then
    begin
      // Kein Fehler, aber Hinweis fuer den Benutzer
      AddError('Keine .pas-Dateien im Verzeichnis gefunden');
      Exit;
    end;

    try
      ParseLeaks(FileList, Result, AProgress, AIncludeUsesCheck);
    except
      on EAbort do
      begin
        // Benutzerseitiger Abbruch (z.B. ueber Cancel-Button im Progress-Callback).
        // Result-Liste freigeben, damit kein Leak entsteht, und EAbort weiter
        // hochreichen - der Aufrufer erkennt den Abbruch daran.
        FreeAndNil(Result);
        raise;
      end;
      on E: Exception do
        AddError('Analyseabbruch: ' + E.Message);
    end;
  finally
    FileList.Free;
  end;
end;

class function TStaticAnalyzer2.AnalyzeLeaksFromList(AFiles: TStringList;
  AProgress: TProc<Integer, Integer>;
  AIncludeUsesCheck: Boolean): TObjectList<TLeakFinding>;
// Analysiert eine vorgefertigte Datei-Liste (z.B. aus uVcsChanges).
// Eingangsliste wird kopiert - der Aufrufer behaelt seine Ownership.

  procedure AddError(const Msg: string);
  var F: TLeakFinding;
  begin
    F            := TLeakFinding.Create;
    F.FileName   := '';
    F.MethodName := '';
    F.LineNumber := '0';
    F.MissingVar := Msg;
    F.SetKind(fkFileReadError);
    Result.Add(F);
  end;

var
  Copy: TStringList;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  if (AFiles = nil) or (AFiles.Count = 0) then
  begin
    AddError('Keine Dateien zu analysieren');
    Exit;
  end;

  Copy := TStringList.Create;
  try
    Copy.AddStrings(AFiles);
    try
      ParseLeaks(Copy, Result, AProgress, AIncludeUsesCheck);
    except
      on EAbort do
      begin
        FreeAndNil(Result);
        raise;
      end;
      on E: Exception do
        AddError('Analyseabbruch: ' + E.Message);
    end;
  finally
    Copy.Free;
  end;
end;

class function TStaticAnalyzer2.Analyze(const FileName: string): TStringList;
var
  FileList: TStringList;
begin
  Result   := TStringList.Create;
  FileList := TStringList.Create;
  try
    FileList.Add(FileName);
    ParseFiles(FileList, Result);
  finally
    FileList.Free;
  end;
end;

class function TStaticAnalyzer2.AnalyzeRecursive(const Path: string): TStringList;
var
  FileList: TStringList;
begin
  Result   := TStringList.Create;
  FileList := TStaticFiles.GetAllPasFilesRecursive(Path);
  try
    ParseFiles(FileList, Result);
  finally
    FileList.Free;
  end;
end;

initialization
  // Detector-Liste deterministisch beim Unit-Load bauen statt lazy beim
  // ersten Scan (Race-frei; Kosten einmalig ~150 Closure-Allokationen).
  // BuildAllDetectors liest keinen Config-State - Filter werden pro Scan
  // via IsDetectorEnabled ausgewertet - daher Init-Reihenfolge-unabhaengig.
  BuildAllDetectors;

end.

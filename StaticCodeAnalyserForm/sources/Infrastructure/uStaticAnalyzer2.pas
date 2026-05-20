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

implementation

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
  uCaseStatementSize, uEmptyFile, uTwiceInheritedCalls,
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
  uFileTextCache,
  uSuppression, uCustomClassDiscovery, uPathOverrides,
  uSynchronizeInDestructor, uLockWithoutTryFinally,
  uPerfHotspots, uConcurrencyExt, uRestHttpSecurity,
  uPublicMemberWithoutDoc, uNamingExt,  uRuleCatalog,
  uRoutineResultAssigned, uReRaiseException, uCastAndFree, uMissingRaise,
  uInstanceInvokedConstructor, uInheritedMethodEmpty, uNilComparison,
  uRaisingRawException, uDateFormatSettings, uUnicodeToAnsiCast,
  uCharToCharPointerCast, uIfThenShortCircuit;

type
  // Run-Methode pro Detektor: einheitliche Signatur, damit alle in einem
  // Array iteriert werden koennen.
  TDetectorRun = reference to procedure(Root: TAstNode; const FileName: string;
    Results: TObjectList<TLeakFinding>);
  TDetectorEntry = record
    Name : string;
    Kind : TFindingKind;  // fuer Profile-/Severity-Filter (uSCAConsts globals)
    Run  : TDetectorRun;
    Skip : Boolean;
  end;
  // Callbacks fuer den Aufrufer (Logging / Fehler-Reporting), damit
  // RunAllDetectors selbst kein Wissen ueber LogStream/FileError-Liste hat.
  TDetectorTimeProc  = reference to procedure(const Name: string; ElapsedMs: Int64);
  TDetectorErrorProc = reference to procedure(const Name, ErrMsg: string);

procedure RunAllDetectors(Root: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>; AIncludeUsesCheck: Boolean;
  AOnTime: TDetectorTimeProc; AOnError: TDetectorErrorProc);
var
  Detectors : array of TDetectorEntry;
  i         : Integer;
  Watch     : TStopwatch;

  procedure Add(const AName: string; AKind: TFindingKind; ARun: TDetectorRun);
  // Skip-Check pro Detektor zentralisiert:
  //   1. Profile-Whitelist (DetectorEnabledKinds): leere Menge = kein
  //      Filter, sonst Whitelist.
  //   2. Severity-Schwellwert (DetectorMinSeverity): Detector wird
  //      geskippt wenn seine Default-Severity strenger ist
  //      (ord(sev) > ord(MinSeverity), da lsError=0 < lsWarning=1 < lsHint=2).
  // Beide Kriterien sind ODER-verknuepft - einer von beiden reicht.
  // Mehrere Detektoren teilen sich einen Kind (z.B. mehrere DFM-Detektoren
  // sind alle ueber DfmAnalysisRunner gebuendelt unter ihren eigenen Kinds);
  // pro Add() greift trotzdem nur EIN Kind als Filter-Schluessel.
  var
    Sev : TLeakSeverity;
  begin
    SetLength(Detectors, Length(Detectors) + 1);
    with Detectors[High(Detectors)] do
    begin
      Name := AName;
      Kind := AKind;
      Run  := ARun;
      Skip := False;

      // (1) Profile-Whitelist. Leere Menge = "kein Filter".
      if (uSCAConsts.DetectorEnabledKinds <> []) and
         not (AKind in uSCAConsts.DetectorEnabledKinds) then
        Skip := True;

      // (2) Severity-Schwellwert. Catalog-Lookup ist O(1) (Dictionary).
      if not Skip then
      begin
        Sev := TRuleCatalog.GetRule(AKind).DefaultSeverity;
        if Ord(Sev) > Ord(uSCAConsts.DetectorMinSeverity) then
          Skip := True;
      end;
    end;
  end;

begin
  Add('Leak',            fkMemoryLeak,      procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TLeakDetector2.AnalyzeUnit(R, F, L); end);
  Add('EmptyExcept',     fkEmptyExcept,     procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TEmptyExceptDetector2.AnalyzeUnit(R, F, L); end);
  Add('SQLInjection',    fkSQLInjection,    procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TSQLInjectionDetector.AnalyzeUnit(R, F, L); end);
  Add('HardcodedSecret', fkHardcodedSecret, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin THardcodedSecretDetector.AnalyzeUnit(R, F, L); end);
  Add('FormatMismatch',  fkFormatMismatch,  procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TFormatMismatchDetector.AnalyzeUnit(R, F, L); end);
  Add('ConcatToFormat',  fkConcatToFormat,  procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TConcatToFormatDetector.AnalyzeUnit(R, F, L); end);
  Add('WithStatement',   fkWithStatement,   procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TWithStatementDetector.AnalyzeUnit(R, F, L); end);
  Add('GotoStatement',   fkGotoStatement,   procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TGotoStatementDetector.AnalyzeUnit(R, F, L); end);
  Add('TabulationCharacter', fkTabulationCharacter, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TTabulationCharacterDetector.AnalyzeUnit(R, F, L); end);
  Add('TooLongLine',     fkTooLongLine,     procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TTooLongLineDetector.AnalyzeUnit(R, F, L); end);
  Add('TrailingWhitespace', fkTrailingWhitespace, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TTrailingWhitespaceDetector.AnalyzeUnit(R, F, L); end);
  Add('LowercaseKeyword', fkLowercaseKeyword, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TLowercaseKeywordDetector.AnalyzeUnit(R, F, L); end);
  Add('NoSonarMarker',   fkNoSonarMarker,   procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TNoSonarMarkerDetector.AnalyzeUnit(R, F, L); end);
  Add('EmptyArgumentList',fkEmptyArgumentList,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TEmptyArgumentListDetector.AnalyzeUnit(R, F, L); end);
  Add('InlineAssembly',  fkInlineAssembly,  procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TInlineAssemblyDetector.AnalyzeUnit(R, F, L); end);
  Add('TrailingCommaArgList',fkTrailingCommaArgList,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TTrailingCommaArgListDetector.AnalyzeUnit(R, F, L); end);
  Add('DigitGrouping',   fkDigitGrouping,   procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TDigitGroupingDetector.AnalyzeUnit(R, F, L); end);
  Add('CommentedOutCode',fkCommentedOutCode,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TCommentedOutCodeDetector.AnalyzeUnit(R, F, L); end);
  Add('UnitLevelKeywordIndent',fkUnitLevelKeywordIndent,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TUnitLevelKeywordIndentDetector.AnalyzeUnit(R, F, L); end);
  Add('RedundantBoolean',fkRedundantBoolean,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TRedundantBooleanDetector.AnalyzeUnit(R, F, L); end);
  Add('EmptyInterface',  fkEmptyInterface,  procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TEmptyInterfaceDetector.AnalyzeUnit(R, F, L); end);
  Add('AssertMessage',   fkAssertMessage,   procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TAssertMessageDetector.AnalyzeUnit(R, F, L); end);
  Add('ExplicitTObjectInheritance',fkExplicitTObjectInheritance,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TExplicitTObjectInheritanceDetector.AnalyzeUnit(R, F, L); end);
  Add('GroupedDeclaration',fkGroupedDeclaration,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TGroupedDeclarationDetector.AnalyzeUnit(R, F, L); end);
  Add('EmptyBlock',      fkEmptyBlock,      procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TEmptyBlockDetector.AnalyzeUnit(R, F, L); end);
  Add('ExceptOnException',fkExceptOnException,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TExceptOnExceptionDetector.AnalyzeUnit(R, F, L); end);
  Add('ConsecutiveSection',fkConsecutiveSection,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TConsecutiveSectionDetector.AnalyzeUnit(R, F, L); end);
  Add('RedundantJump',   fkRedundantJump,   procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TRedundantJumpDetector.AnalyzeUnit(R, F, L); end);
  Add('ClassPerFile',    fkClassPerFile,    procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TClassPerFileDetector.AnalyzeUnit(R, F, L); end);
  Add('SuperfluousSemicolon',fkSuperfluousSemicolon,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TSuperfluousSemicolonDetector.AnalyzeUnit(R, F, L); end);
  Add('EmptyFinallyBlock',fkEmptyFinallyBlock,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TEmptyFinallyBlockDetector.AnalyzeUnit(R, F, L); end);
  Add('AssignedAndAssignedNil',fkAssignedAndAssignedNil,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TAssignedAndAssignedNilDetector.AnalyzeUnit(R, F, L); end);
  Add('FreeAndNilHint',  fkFreeAndNilHint,  procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TFreeAndNilHintDetector.AnalyzeUnit(R, F, L); end);
  Add('AvoidOut',        fkAvoidOut,        procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TAvoidOutDetector.AnalyzeUnit(R, F, L); end);
  Add('EmptyVisibilitySection',fkEmptyVisibilitySection,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TEmptyVisibilitySectionDetector.AnalyzeUnit(R, F, L); end);
  Add('LegacyInitializationSection',fkLegacyInitializationSection,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TLegacyInitializationSectionDetector.AnalyzeUnit(R, F, L); end);
  Add('PublicField',     fkPublicField,     procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TPublicFieldDetector.AnalyzeUnit(R, F, L); end);
  Add('NestedTry',       fkNestedTry,       procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TNestedTryDetector.AnalyzeUnit(R, F, L); end);
  Add('CaseStatementSize',fkCaseStatementSize,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TCaseStatementSizeDetector.AnalyzeUnit(R, F, L); end);
  Add('EmptyFile',       fkEmptyFile,       procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TEmptyFileDetector.AnalyzeUnit(R, F, L); end);
  Add('TwiceInheritedCalls',fkTwiceInheritedCalls,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TTwiceInheritedCallsDetector.AnalyzeUnit(R, F, L); end);
  Add('RedundantParentheses',fkRedundantParentheses,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TRedundantParenthesesDetector.AnalyzeUnit(R, F, L); end);
  Add('ConsecutiveVisibility',fkConsecutiveVisibility,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TConsecutiveVisibilityDetector.AnalyzeUnit(R, F, L); end);
  Add('ConstructorWithoutInherited',fkConstructorWithoutInherited,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TConstructorWithoutInheritedDetector.AnalyzeUnit(R, F, L); end);
  Add('DestructorWithoutInherited',fkDestructorWithoutInherited,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TDestructorWithoutInheritedDetector.AnalyzeUnit(R, F, L); end);
  Add('RedundantConditional',fkRedundantConditional,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TRedundantConditionalDetector.AnalyzeUnit(R, F, L); end);
  Add('IfElseBegin',     fkIfElseBegin,     procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TIfElseBeginDetector.AnalyzeUnit(R, F, L); end);
  Add('PointerName',     fkPointerName,     procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TPointerNameDetector.AnalyzeUnit(R, F, L); end);
  Add('BeginEndRequired',fkBeginEndRequired,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TBeginEndRequiredDetector.AnalyzeUnit(R, F, L); end);
  Add('NestedRoutine',   fkNestedRoutine,   procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TNestedRoutinesDetector.AnalyzeUnit(R, F, L); end);
  Add('FieldName',       fkFieldName,       procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TFieldNameDetector.AnalyzeUnit(R, F, L); end);
  Add('TypeName',        fkTypeName,        procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TTypeNameDetector.AnalyzeUnit(R, F, L); end);
  Add('InterfaceName',   fkInterfaceName,   procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TInterfaceNameDetector.AnalyzeUnit(R, F, L); end);
  Add('MethodName',      fkMethodName,      procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TMethodNameDetector.AnalyzeUnit(R, F, L); end);
  Add('ReversedForRange',fkReversedForRange,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TReversedForRangeDetector.AnalyzeUnit(R, F, L); end);
  Add('SelfAssignment',  fkSelfAssignment,  procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TSelfAssignmentDetector.AnalyzeUnit(R, F, L); end);
  Add('MissingRaise',    fkMissingRaise,    procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TMissingRaiseDetector.AnalyzeUnit(R, F, L); end);
  Add('RoutineResultUnassigned', fkRoutineResultUnassigned, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TRoutineResultAssignedDetector.AnalyzeUnit(R, F, L); end);
  Add('ReRaiseException', fkReRaiseException, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TReRaiseExceptionDetector.AnalyzeUnit(R, F, L); end);
  Add('CastAndFree',     fkCastAndFree,     procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TCastAndFreeDetector.AnalyzeUnit(R, F, L); end);
  Add('InstanceInvokedConstructor', fkInstanceInvokedConstructor, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TInstanceInvokedConstructorDetector.AnalyzeUnit(R, F, L); end);
  Add('InheritedMethodEmpty', fkInheritedMethodEmpty, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TInheritedMethodEmptyDetector.AnalyzeUnit(R, F, L); end);
  Add('NilComparison',   fkNilComparison,   procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TNilComparisonDetector.AnalyzeUnit(R, F, L); end);
  Add('RaisingRawException', fkRaisingRawException, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TRaisingRawExceptionDetector.AnalyzeUnit(R, F, L); end);
  Add('DateFormatSettings', fkDateFormatSettings, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TDateFormatSettingsDetector.AnalyzeUnit(R, F, L); end);
  Add('UnicodeToAnsiCast', fkUnicodeToAnsiCast, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TUnicodeToAnsiCastDetector.AnalyzeUnit(R, F, L); end);
  Add('CharToCharPointerCast', fkCharToCharPointerCast, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TCharToCharPointerCastDetector.AnalyzeUnit(R, F, L); end);
  Add('IfThenShortCircuit', fkIfThenShortCircuit, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TIfThenShortCircuitDetector.AnalyzeUnit(R, F, L); end);
  Add('VirtualCallInCtor',fkVirtualCallInCtor,procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TVirtualCallInCtorDetector.AnalyzeUnit(R, F, L); end);
  Add('LengthUnderflow', fkLengthUnderflow, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TLengthUnderflowDetector.AnalyzeUnit(R, F, L); end);
  // VisibilityCheck emittiert vier Kinds (CanBeUnitPrivate, CanBeStrict-
  // Private, CanBeProtected, UnusedPublicMember) auf den
  // fkCanBeUnitPrivate-Anker im Profile-Filter.
  // Single-file-Modus (kein gSymbolRefIndex) - global scan abgeschaltet
  // weil zu viele False-Positives lieferte; siehe uVisibilityCheck.pas.
  Add('VisibilityCheck',fkCanBeUnitPrivate, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TVisibilityCheckDetector.AnalyzeUnit(R, F, L); end);
  // Concurrency-Detektor-Familie
  Add('SynchronizeInDestructor', fkSynchronizeInDestructor, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TSynchronizeInDestructorDetector.AnalyzeUnit(R, F, L); end);
  Add('LockWithoutTryFinally', fkLockWithoutTryFinally, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TLockWithoutTryFinallyDetector.AnalyzeUnit(R, F, L); end);
  // Concurrency-Familie erweitert (SCA113-114): Thread-Lifecycle-Bugs
  Add('ConcurrencyExt',     fkThreadResumeDeprecated, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TConcurrencyExtDetector.AnalyzeUnit(R, F, L); end);
  // Performance-Hotspots (SCA110-112)
  Add('PerfHotspots',       fkStringConcatInLoop,     procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TPerfHotspotsDetector.AnalyzeUnit(R, F, L); end);
  // REST/HTTP-Security (SCA115-116)
  Add('RestHttpSecurity',   fkHttpInsteadOfHttps,     procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TRestHttpSecurityDetector.AnalyzeUnit(R, F, L); end);
  // Doc-Luecken (SCA117)
  Add('PublicMemberWithoutDoc', fkPublicMemberWithoutDoc, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TPublicMemberWithoutDocDetector.AnalyzeUnit(R, F, L); end);
  // Naming-Familie erweitert (SCA118-119)
  Add('NamingExt',          fkExceptionName,          procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TNamingExtDetector.AnalyzeUnit(R, F, L); end);
  Add('UnusedLocalVar', fkUnusedLocalVar,  procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TUnusedLocalDetector.AnalyzeUnit(R, F, L); end);
  Add('UnusedParameter',fkUnusedParameter, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TUnusedParameterDetector.AnalyzeUnit(R, F, L); end);
  Add('TautologicalBoolExpr',fkTautologicalBoolExpr, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TTautologicalExprDetector.AnalyzeUnit(R, F, L); end);
  Add('SqlDangerousStatement', fkSqlDangerousStatement, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TSqlDangerousStatementDetector.AnalyzeUnit(R, F, L); end);
  Add('UnusedUses',      fkUnusedUses,      procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TUnusedUsesDetector.AnalyzeUnit(R, F, L); end);
  // UsesCheck zusaetzlich zum Profile-/Severity-Filter: bleibt Skip-Wahr
  // wenn der Caller AIncludeUsesCheck=False uebergibt - auch bei strict
  // profile, damit der "AIncludeUsesCheck=False" Standard nicht umgangen
  // wird. (strict profile zaehlt UnusedUses zur Whitelist; der Boolean ist
  // der Pre-Existing-Opt-out, der haerter wirkt.)
  if not AIncludeUsesCheck then Detectors[High(Detectors)].Skip := True;
  Add('NilDeref',        fkNilDeref,        procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TNilDerefDetector.AnalyzeUnit(R, F, L); end);
  Add('MissingFinally',  fkMissingFinally,  procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TMissingFinallyDetector.AnalyzeUnit(R, F, L); end);
  Add('DivByZero',       fkDivByZero,       procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TDivByZeroDetector.AnalyzeUnit(R, F, L); end);
  Add('DeadCode',        fkDeadCode,        procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TDeadCodeDetector.AnalyzeUnit(R, F, L); end);
  Add('LongMethod',      fkLongMethod,      procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TLongMethodDetector.AnalyzeUnit(R, F, L); end);
  Add('LongParamList',   fkLongParamList,   procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TLongParamListDetector.AnalyzeUnit(R, F, L); end);
  Add('MagicNumber',     fkMagicNumber,     procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TMagicNumberDetector.AnalyzeUnit(R, F, L); end);
  Add('DuplicateString', fkDuplicateString, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TDuplicateStringDetector.AnalyzeUnit(R, F, L); end);
  Add('HardcodedPath',   fkHardcodedPath,   procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin THardcodedPathDetector.AnalyzeUnit(R, F, L); end);
  Add('DebugOutput',     fkDebugOutput,     procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TDebugOutputDetector.AnalyzeUnit(R, F, L); end);
  Add('DeepNesting',     fkDeepNesting,     procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TDeepNestingDetector.AnalyzeUnit(R, F, L); end);
  Add('TodoComment',     fkTodoComment,     procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TTodoCommentDetector.AnalyzeUnit(R, F, L); end);
  Add('EmptyMethod',     fkEmptyMethod,     procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TEmptyMethodDetector.AnalyzeUnit(R, F, L); end);
  // FieldLeak: gleicher Kind wie LeakDetector (fkMemoryLeak) - Profile-
  // Filter behandelt beide identisch.
  Add('FieldLeak',       fkMemoryLeak,      procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TFieldLeakDetector.AnalyzeUnit(R, F, L); end);
  Add('DuplicateBlock',  fkDuplicateBlock,  procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TDuplicateBlockDetector.AnalyzeUnit(R, F, L); end);
  Add('CyclomaticComplexity', fkCyclomaticComplexity, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TCyclomaticComplexityDetector.AnalyzeUnit(R, F, L); end);
  // DFM-Adapter: ruft intern ~20 DFM-Detektoren, jeder produziert seinen
  // eigenen Kind. Wir wuerden hier zu Unrecht alles skippen, wenn der
  // einzelne Repraesentant-Kind nicht im Profile waere. Daher laeuft der
  // Adapter immer (ist No-Op fuer .pas ohne companion .dfm) - die Filterung
  // findet auf Finding-Ebene weiter unten statt. Skip := False explizit.
  Add('DfmAnalysis',     fkDfmDefaultName,  procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TDfmAnalysisRunner.AnalyzePasFile(F, L); end);
  Detectors[High(Detectors)].Skip := False;

  for i := 0 to High(Detectors) do
  begin
    if Detectors[i].Skip then Continue;
    Watch := TStopwatch.StartNew;
    try
      Detectors[i].Run(Root, FileName, Results);
    except
      // User-Cancel (EAbort) muss durchgereicht werden, damit die
      // Schleife in AnalyzeLeaksRecursive abbricht. Ein generischer
      // Detektor-Fehler hingegen blockiert die anderen Detektoren nicht.
      on EAbort do raise;
      on E: Exception do
        if Assigned(AOnError) then
          AOnError(Detectors[i].Name, E.Message);
    end;
    if Assigned(AOnTime) then
      AOnTime(Detectors[i].Name, Watch.ElapsedMilliseconds);
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
  if (uSCAConsts.DetectorEnabledKinds <> []) or
     (uSCAConsts.DetectorMinSeverity <> lsHint) then
  begin
    for i := Results.Count - 1 downto 0 do
    begin
      if Results[i].Kind = fkFileReadError then Continue;
      if (uSCAConsts.DetectorEnabledKinds <> []) and
         not (Results[i].Kind in uSCAConsts.DetectorEnabledKinds) then
      begin
        Results.Delete(i);
        Continue;
      end;
      if Ord(Results[i].Severity) > Ord(uSCAConsts.DetectorMinSeverity) then
        Results.Delete(i);
    end;
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

  procedure LogLine(const S: string);
  begin
    if Assigned(LogStream) then
      try LogStream.WriteLine(S); LogStream.Flush; except end;
  end;

begin
  if (FileList = nil) or (Results = nil) then Exit;

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
  // Eine gemeinsame try-finally klammer fuer LogStream UND Parser - so leakt
  // weder bei Parser-Create-OOM der LogStream noch umgekehrt.
  try
    try
      // Append-Modus, damit der Scan-Log nicht ueberschrieben wird
      LogStream := TStreamWriter.Create(LogPath, True, TEncoding.UTF8);
      LogLine('=== ParseLeaks gestartet: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)
              + ' (' + IntToStr(FileList.Count) + ' Dateien) ===');
    except
      LogStream := nil;
    end;

    // AST-File-Cache: pro .pas einmal parsen, von beiden Pre-Indizes UND
    // dem Main-Loop wiederverwendet. Spart 2 von 3 Parser-Durchlaeufen pro
    // File (perf_analyse.md Hot-Spot 🅐).
    gAstFileCache := TAstFileCache.Create;

    // File-Text-Cache: pro .pas einmal Lines.LoadFromFile, von den
    // File-Scan-Detektoren (Todo, With, Reversed, Length, Tautological,
    // DuplicateBlock, CustomRule) wiederverwendet (perf_analyse.md
    // Hot-Spot 🅑).
    gFileTextCache := TFileTextCache.Create;

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

    gDfmRepoIndex := TDfmRepoIndex.Create;
    try
      gDfmRepoIndex.Build(IndexFiles);
    except
      FreeAndNil(gDfmRepoIndex);
    end;

    // Symbol-Reference-Index. Visibility-Detektoren (fkCanBeUnitPrivate,
    // fkCanBeStrictPrivate, fkCanBeProtected, fkUnusedPublicMember)
    // konsultieren ihn NICHT mehr - sie laufen single-file. Index wird
    // hier dennoch aufgebaut weil andere Konsumenten (Tests, mORMot-Cross-
    // Check) ihn lesen; kann perspektivisch entfallen wenn keiner mehr
    // referenziert.
    gSymbolRefIndex := TSymbolReferenceIndex.Create;
    try
      gSymbolRefIndex.Build(IndexFiles);
    except
      FreeAndNil(gSymbolRefIndex);
    end;

    Parser := TParser2.Create;
    Total  := FileList.Count;
    for i := 0 to Total - 1 do
    begin
      SafeProgress(i + 1, Total);

      FileName := FileList[i];

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

      if FileSize > DetectorMaxFileBytes then
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
      try
        try
          // Cache-Pfad bevorzugen: Pre-Indizes haben das Root schon erzeugt.
          if Assigned(gAstFileCache) then
          begin
            Root := gAstFileCache.Acquire(FileName);
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
          if Assigned(gAstFileCache) then
            FailMsg := gAstFileCache.GetFailMessage(FileName);
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
        if AutoDiscoverCustomClasses then
        begin
          var Instantiable : TArray<string>;
          var StaticOnly   : TArray<string>;
          TCustomClassDiscovery.DiscoverInUnit(Root, Instantiable, StaticOnly);

          for var Cls in Instantiable do
          begin
            if Assigned(LeakyClassExcludes) and
               (LeakyClassExcludes.IndexOf(Cls) >= 0) then Continue;
            if Assigned(LeakyClasses) then
              LeakyClasses.Add(Cls);
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
        end;

        // Custom-Rules (aus analyser-rules.yml) NACH den built-in
        // Detektoren - so liegen sie im Output sortierbar zusammen.
        // No-op wenn TCustomRuleDetector.LoadFromYaml nicht aufgerufen
        // wurde (HasRules = False).
        if TCustomRuleDetector.HasRules then
          TCustomRuleDetector.AnalyzeFile(FileName, Results);

        RunAllDetectors(Root, FileName, Results, AIncludeUsesCheck,
          procedure(const Name: string; ElapsedMs: Int64) begin
            if (ElapsedMs > 500) and Assigned(CaptLogStream) then
              try
                CaptLogStream.WriteLine(Format('  Detektor %s: %d ms (langsam!)',
                  [Name, ElapsedMs]));
                CaptLogStream.Flush;
              except end;
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
      finally
        if OwnsRoot then
          Root.Free
        else if Assigned(gAstFileCache) then
          gAstFileCache.Evict(FileName);  // Memory-Peak bremsen
        // Text-Cache fuer die abgearbeitete Datei freigeben - die File-Scan-
        // Detektoren haben sie konsumiert, niemand brauchts mehr.
        if Assigned(gFileTextCache) then
          gFileTextCache.Clear;
      end;
    end;
  finally
    // LogStream auch bei EAbort sauber schliessen, danach Parser.
    // Eine gemeinsame Klammer verhindert dass Parser-Create-OOM den LogStream
    // hinterlaesst oder umgekehrt.
    LogLine('=== ParseLeaks fertig: ' + FormatDateTime('hh:nn:ss', Now) + ' ===');
    if Assigned(LogStream) then
      FreeAndNil(LogStream);
    Parser.Free;
    // Repo-Index nach dem Scan wieder freigeben - Cross-Unit-Detektoren
    // ausserhalb dieses Scans sollen nicht versehentlich stale Daten sehen.
    if Assigned(gDfmRepoIndex) then
      FreeAndNil(gDfmRepoIndex);
    if Assigned(gSymbolRefIndex) then
      FreeAndNil(gSymbolRefIndex);
    if Assigned(gAstFileCache) then
      FreeAndNil(gAstFileCache);
    if Assigned(gFileTextCache) then
      FreeAndNil(gFileTextCache);
  end;

  // Suppression-Kommentare auswerten und Befunde filtern
  try
    TSuppression.ApplyToFindings(Results);
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

end.

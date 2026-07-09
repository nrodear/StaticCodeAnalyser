unit uSCAConsts;

interface

uses
  System.Classes, SysUtils;

const
  // --- Engine-Defaults der Scan-Konfiguration (2026-07-04) ---
  // Single Source of Truth: dieselben Konstanten speisen die Deklarations-
  // Initializer der Config-Globals unten UND ResetEngineConfigDefaults.
  // Eine Wert-Aenderung hier wirkt damit garantiert auf BEIDE Stellen
  // (kein Drift zwischen Prozess-Start-Zustand und Reset-Zustand).
  DEF_MAX_BODY_LINES            = 50;
  DEF_MAX_STATEMENTS            = 30;
  DEF_MAX_PARAMS                = 5;
  DEF_MAX_NESTING               = 4;
  DEF_MAX_CYCLOMATIC            = 10;
  DEF_MIN_BLOCK_LINES           = 8;
  DEF_MAX_LOCAL_VARS            = 200;
  DEF_MAX_CHILDREN_RECURSIVE    = 5000;
  DEF_MAX_FILE_BYTES            = 5 * 1024 * 1024;
  DEF_MAX_GOD_HANDLER_EVENTS    = 5;
  DEF_MAX_DB_IN_UI_FORM_HINT    = 3;
  DEF_MAX_LINE_LENGTH           = 120;
  DEF_MAX_CASE_BRANCHES         = 10;
  DEF_UI_MAX_DISPLAYED_FINDINGS = 0;
  DEF_AUTO_DISCOVER_CLASSES     = False;

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
  AutoDiscoverCustomClasses: Boolean = DEF_AUTO_DISCOVER_CLASSES;

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
  DetectorMaxBodyLines     : Integer = DEF_MAX_BODY_LINES;   // uLongMethod
  DetectorMaxStatements    : Integer = DEF_MAX_STATEMENTS;   // uLongMethod sek. Schwelle
  DetectorMaxParams        : Integer = DEF_MAX_PARAMS;       // uLongParamList
  DetectorMaxNesting       : Integer = DEF_MAX_NESTING;      // uDeepNesting (>4 = Fund)
  DetectorMaxCyclomatic    : Integer = DEF_MAX_CYCLOMATIC;   // uCyclomaticComplexity (>10 = Fund)
  DetectorMinBlockLines    : Integer = DEF_MIN_BLOCK_LINES;  // uDuplicateBlock
  // uUninitVar Hard-Caps gegen pathologisch grosse Methoden:
  // Bei Ueberschreitung wird die Methode nicht analysiert (kein Flag,
  // kein Crash) - sichert Detector-Wall-Time gegen O(n)-Eskalation.
  DetectorMaxLocalVars          : Integer = DEF_MAX_LOCAL_VARS;
  DetectorMaxChildrenRecursive  : Integer = DEF_MAX_CHILDREN_RECURSIVE;
  DetectorMaxFileBytes     : Integer = DEF_MAX_FILE_BYTES;          // uStaticAnalyzer2
  DetectorMaxGodHandlerEvents : Integer = DEF_MAX_GOD_HANDLER_EVENTS; // uDfmGodHandler
  DetectorMaxDbInUiFormHint   : Integer = DEF_MAX_DB_IN_UI_FORM_HINT; // uDfmDataModuleSplitHint
                                                          // (ab N DB-Komponenten auf der Form
                                                          // empfehlen statt N Einzelmeldungen)
  DetectorMaxLineLength       : Integer = DEF_MAX_LINE_LENGTH;      // uTooLongLine
  DetectorMaxCaseBranches     : Integer = DEF_MAX_CASE_BRANCHES;    // uCaseStatementSize

  // UI-Schwelle: maximale Anzahl Befunde im Grid. TStringGrid wird ab
  // ~50k Zeilen spuerbar trag (interne Cell-Storage-Arrays + Scrollbar-
  // Metrik), bei 150k+ ist Scrollen unangenehm. Wird der Cap ueber-
  // schritten, zeigt das Grid nur die ersten N Eintraege (nach Sortierung)
  // und der Status macht das transparent. Export/CSV/Baseline arbeiten
  // weiterhin mit der vollen Liste.
  //   0 = kein Cap (User-Wunsch 2026-05-31: alle Befunde anzeigen, auch
  //   wenn TStringGrid bei >50k spuerbar laggt - siehe
  //   Konzept_GridPerformance150k.md fuer Optimierungs-Optionen).
  //   Beide Consumer (uMainForm Standalone + uIDEAnalyserForm Plugin)
  //   pruefen `if UIMaxDisplayedFindings > 0` und ueberspringen das Cap
  //   bei 0 - kein weiterer Code-Aufruf noetig.
  UIMaxDisplayedFindings : Integer = DEF_UI_MAX_DISPLAYED_FINDINGS;

  // Trivial-Liste fuer uMagicNumbers - Zahlen die NICHT als Magic-Number
  // gemeldet werden. Default: 0,1,2,-1,10,100. INI-Override moeglich.
  // Stringliste damit Vergleich mit den geparsten Zahlen-Strings ohne
  // Konversion klappt.
  DetectorMagicTrivials    : TStringList = nil;

  // Format-Funktionen die der uFormatMismatch-Detektor pruefen soll.
  // Default: NUR 'Format' (System.SysUtils, printf-Style %s/%d/%.2f).
  // mORMot's FormatUtf8/FormatString sind BEWUSST NICHT im Default: ihre
  // %-Semantik ist NICHT identisch mit Delphi-Format (einzelnes '%' statt
  // %s/%d, '%%' = ZWEI Platzhalter, Argument-Reuse bei Ueberzahl, '?'-SQL-
  // Params, literale '%' in CSS wie 'width:100%') -> der Detektor produziert
  // dort fast nur False-Positives (Real-World-Audit 2026-06-25). Wer es
  // dennoch will: [Detectors] FormatFunctions=Format,FormatUtf8,FormatString.
  // Lowercase-normalisiert beim Match.
  DetectorFormatFunctions  : TStringList = nil;

  // Verbotene Komponentenklassen fuer den uDfmForbiddenClass-Detektor.
  // Default leer - der Detektor schweigt, bis das Projekt Klassen via
  // analyser.ini eintraegt:
  //   [Components] ForbiddenClasses=TLabel,TQuery
  // Case-insensitiver Match auf TComponentNode.ClassRef.
  DfmForbiddenClasses      : TStringList = nil;

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

  // Konfidenz eines Befundes - wie sicher der Detektor ist, dass es KEIN
  // False-Positive ist. Orthogonal zur Severity (die sagt: wie schlimm
  // WENN echt). Ordering bewusst aufsteigend (fcLow=0 < fcHigh=2), damit
  // der Schwellwert-Filter "raus wenn Ord(Confidence) < Ord(MinConfidence)"
  // natuerlich liest.
  //   fcLow    - heuristischer Treffer, hohe FP-Quote (z.B. rein lexikalisch
  //              ohne Typ-/Scope-Kontext)
  //   fcMedium - plausibel, gelegentlich FP
  //   fcHigh   - sicherer Treffer (Default - bestehende Detektoren emittieren
  //              binaer und gelten damit als hochkonfident)
  TFindingConfidence = (
    fcLow,
    fcMedium,
    fcHigh
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
    fkDuplicateBlock,   // mehrere identische Code-Blocks (>=8 Zeilen)
    fkCyclomaticComplexity, // McCabe-Komplexitaet > Schwellwert
    fkCustomRule,          // Custom-Rule aus analyser-rules.yml (siehe
                           // uCustomRuleDetector). Spezifische Rule-ID
                           // steht in TLeakFinding.RuleID.
    fkDfmDefaultName,      // Komponente im DFM mit Default-Name
                           // (Button1, Edit3, Panel2 ...) - Refactoring-Killer
    fkDfmHardcodedCaption, // UI-Text-Property (Caption/Hint/...) als String-
                           // Literal im DFM, statt ueber Lokalisierungs-Layer
    fkDfmHardcodedDbCreds, // Klartext-Credentials auf einer DB-Verbindungs-
                           // Komponente (Password / ConnectionString mit Pwd=)
    fkDfmDuplicateBinding, // Mehrere Komponenten binden gleichen
                           // (DataSource, DataField) -> Update-Konflikt
    fkDfmDeadEvent,        // OnClick zeigt auf Methode, die in der Form-
                           // Klasse nicht (mehr) existiert -> Streaming-Crash
    fkDfmOrphanHandler,    // Published Methode mit Sender-Signatur, aber
                           // keine Komponente bindet sie -> Dead Code
    fkDfmEmptyBoundEvent,  // Event ist gebunden, Methode existiert, aber
                           // Body leer -> wahrscheinlich vergessener Stub
    fkDfmSchemaMismatch,   // DFM-Komponente hat kein published Field in
                           // der Form-Klasse -> Streaming-Fehler/Smell
    fkDfmCircularDataSource, // Zyklus in DataSource.DataSet /
                           // DataSet.MasterSource Kanten -> Endlos-Loop
                           // bei BeforeOpen / Master-Detail-Refresh
    fkDfmSqlFromUserInput, // SQL-Property einer DB-Query wird mit Text-
                           // Property einer UI-Input-Komponente konkateniert
                           // -> SQL-Injection ueber Form-Field
    fkDfmRequiredFieldUnbound,   // TField mit Required=True hat keine UI-
                                 // Bindung -> Pflichtfeld nicht eingebbar
    fkDfmRequiredFieldNotVisible,// TField mit Required=True nur an
                                 // Visible=False UI-Controls gebunden ->
                                 // User kann das Pflichtfeld nicht erreichen
    fkDfmFieldTypeMismatch,      // UI-DB-Control-Klasse passt nicht zum
                                 // TField.DataType (TDBEdit fuer TBooleanField)
    fkDfmTabOrderConflict,       // Zwei Geschwister-Komponenten im selben
                                 // Parent haben den gleichen TabOrder-Wert
    fkDfmForbiddenClass,         // Komponente nutzt eine via analyser.ini
                                 // verbotene Klasse (Style-Guide)
    fkDfmDbInUiForm,             // DB-Komponente (Connection/Query) direkt
                                 // auf einer TForm/TFrame statt im DataModule
    fkDfmCrossFormCoupling,      // Code in Form1 greift via Form2.<field>
                                 // auf published Felder einer anderen Form
                                 // zu (Kapselungsbruch)
    fkDfmLayerViolation,         // Eingabe-Control direkt auf TForm statt
                                 // im TPanel/TGroupBox eingebettet
    fkDfmGodHandler,             // Eine Methode haengt an >=N Komponenten-
                                 // Events (Spaghetti-Indikator)
    fkDfmActionMismatch,         // Komponente hat Action UND OnClick gesetzt
                                 // -> Action gewinnt, OnClick ist toter Code
    fkConcatToFormat,            // Refactoring-Hint: lange String-Konkat-Kette
                                 // ('a' + x + 'b' + IntToStr(y)) -> Format(...).
                                 // ReDelphi-Roadmap 2.5.
    fkWithStatement,             // `with X do ...` - Scope-Shadowing-Falle, vom
                                 // Compiler nicht gewarnt. Marco Cantu /
                                 // delphi.org / Stack Overflow zaehlen das zu
                                 // den haeufigsten Delphi-Bug-Quellen.
    fkReversedForRange,          // `for i := 10 to 1 do` - From > To, 0 Iter.
                                 // Klassischer `downto`-vergessen-Tippfehler.
    fkSelfAssignment,            // `x := x;` - No-Op oder Copy-Paste-Fehler.
                                 // Property-Setter mit Side-Effects ausgenommen.
    fkVirtualCallInCtor,         // Virtuelle Methode im Constructor gerufen -
                                 // abgeleiteter Override laeuft mit halb-
                                 // initialisiertem Self (klass. Subtle-Bug).
    fkLengthUnderflow,           // `Length(s) - X` / `.Count - X` ohne Guard ->
                                 // Native-UInt-Underflow bei leerem String/Array.
    fkCanBeUnitPrivate,          // Public-Member wird in der aktuellen Unit
                                 // referenziert -> Delphi-klassisches `private`
                                 // (unit-scope) reicht. Single-file-decidable
                                 // (kein Cross-Unit-Index noetig); bei Cross-
                                 // Unit-Konsumenten meckert sowieso der
                                 // Compiler. Vorher: fkCanBePrivate (mit
                                 // global scan, lieferte zu viele FPs).
    fkCanBeProtected,            // Public-Member wird nur in Subklassen genutzt
                                 // -> protected reicht (Cross-Unit).
    fkUnusedPublicMember,        // Public-Member wird in keinem Sub-Klassen-/
                                 // Cross-Unit-Pfad gerufen -> Dead-API.
    fkUnusedLocalVar,            // Lokale `var X: T;` im Methoden-Body nie
                                 // referenziert. Compiler-Warnung H2164,
                                 // aber als SCA-Hint mit Suppression nuetzlich.
    fkUnusedParameter,           // Method-Parameter nirgends im Body genutzt.
                                 // Skip-Regeln: override, Event-Handler (Sender),
                                 // Interface-Impl.
    fkTautologicalBoolExpr,      // Binary-Op mit gleicher LHS und RHS:
                                 // `x = x`, `a and a`, `(p <> p)` -
                                 // klassischer Copy-Paste-Bug.
    fkDfmMasterDetailUnlinked,   // DFM: TDataSet hat MasterSource gesetzt
                                 // aber kein MasterFields/IndexFieldNames ->
                                 // silent Cross-Join zur Laufzeit.
    fkDfmDataModuleSplitHint,    // DFM: viele fkDfmDbInUiForm-Findings auf
                                 // derselben Form -> aggregierter Refactor-
                                 // Hint statt N Einzelmeldungen.
    fkSqlDangerousStatement,     // SQL: UPDATE/DELETE/TRUNCATE ohne WHERE
                                 // -> betrifft alle Zeilen (Production-Disaster).
    fkFormatLocaleHint,          // FormatMismatch-Variante: %.2f / %.3f ohne
                                 // TFormatSettings -> Komma-vs-Punkt-Falle
                                 // bei DE/EN-Lokalisierung.
    fkGotoStatement,             // `goto` in Pascal-Code - SonarDelphi-Mapping
                                 // (communitydelphi:GotoStatement). Strukturen-
                                 // brechende Anweisung, sollte durch Exit /
                                 // Helper-Methode ersetzt werden.
    fkTabulationCharacter,       // Tab-Zeichen im Source (SonarDelphi:
                                 // TabulationCharacter). Style/Formatting -
                                 // pro Zeile ein Finding auf erste Tab-Position.
    fkTooLongLine,               // Zeile > 120 Zeichen (SonarDelphi:TooLongLine).
                                 // Standard-Schwelle aus Code-Review-Praxis,
                                 // siehe MAX_LINE_LEN in uTooLongLine.
    fkTrailingWhitespace,        // Zeile endet mit Space/Tab (SonarDelphi:
                                 // TrailingWhitespace). Diff-Hygiene.
    fkLowercaseKeyword,          // Pascal-Keyword nicht in Kleinschreibung
                                 // (Begin/End/Procedure/...). SonarDelphi:
                                 // LowercaseKeyword.
    fkNoSonarMarker,             // // NOSONAR-Suppression-Marker im Source.
                                 // Audit-Hinweis (SonarDelphi:NoSonar).
    fkEmptyArgumentList,         // Identifier() statt Identifier; - leere
                                 // Argument-Liste (SonarDelphi:EmptyArgumentList).
    fkInlineAssembly,            // `asm...end`-Block (SonarDelphi:
                                 // InlineAssembly). Portabilitaet/Maintainability.
    fkTrailingCommaArgList,      // `Foo(A, B,)` - trailing Komma in
                                 // Argument-Liste (SonarDelphi:
                                 // TrailingCommaArgumentList).
    fkDigitGrouping,             // Grosses Int-Literal ohne `_`-Trennung
                                 // (SonarDelphi:DigitGrouping). Seit
                                 // Delphi 10.4: 1_000_000 statt 1000000.
    fkCommentedOutCode,          // Kommentar enthaelt Pascal-Code-Marker
                                 // (SonarDelphi:CommentedOutCode).
    fkUnitLevelKeywordIndent,    // Section-Keyword nicht auf Spalte 1
                                 // (SonarDelphi:UnitLevelKeywordIndentation).
    fkRedundantBoolean,          // `X = True` / `X <> False` Vergleich
                                 // (SonarDelphi:RedundantBoolean).
    fkEmptyInterface,            // `IFoo = interface end;` ohne Methoden
                                 // (SonarDelphi:EmptyInterface).
    fkAssertMessage,             // `Assert(cond);` ohne Message-String
                                 // (SonarDelphi:AssertMessage).
    fkExplicitTObjectInheritance, // `class(TObject)` explizit (redundant)
                                 // (SonarDelphi:ExplicitTObjectInheritance).
    fkGroupedDeclaration,        // `A, B: Type;` Gruppen-Deklaration
                                 // (SonarDelphi:GroupedField/Variable/
                                 // ParameterDeclaration).
    fkEmptyBlock,                // Leerer `begin..end`-Block
                                 // (SonarDelphi:EmptyBlock).
    fkExceptOnException,         // `on E: Exception do` faengt Root-Klasse
                                 // (SonarDelphi:CatchAllException Variante).
    fkConsecutiveSection,        // Zwei `const`/`type`/`var` Sektionen
                                 // hintereinander (SonarDelphi:
                                 // ConsecutiveConst/Type/Var Section).
    fkRedundantJump,             // `Exit;`/`Continue;`/`Break;` direkt
                                 // vor `end` (SonarDelphi:RedundantJump).
    fkClassPerFile,              // Mehrere Klassen-Deklarationen in einer
                                 // Unit (SonarDelphi:ClassPerFile).
    fkSuperfluousSemicolon,      // `;;` doppeltes Semikolon
                                 // (SonarDelphi:SuperfluousSemicolon).
    fkEmptyFinallyBlock,         // `try ... finally end;` leerer Cleanup
                                 // (SonarDelphi:EmptyFinallyBlock).
    fkAssignedAndAssignedNil,    // `Assigned(X) and (X <> nil)` redundant
                                 // (SonarDelphi:AssignedAndAssignedNil).
    fkFreeAndNilHint,            // `X.Free; X := nil;` -> `FreeAndNil(X)`
                                 // (SonarDelphi:FreeAndNil).
    fkAvoidOut,                  // `out`-Parameter (SonarDelphi:AvoidOut).
    fkEmptyVisibilitySection,    // Leere Visibility-Section in Klasse
                                 // (SonarDelphi:EmptyVisibilitySection).
    fkLegacyInitializationSection, // `begin..end.` statt `initialization`
                                 // (SonarDelphi:LegacyInitializationSection).
    fkPublicField,               // Oeffentliches Klassen-Feld
                                 // (SonarDelphi:PublicField).
    fkNestedTry,                 // Verschachtelter `try`-Block
                                 // (SonarDelphi:NestedTry).
    fkCaseStatementSize,         // `case` mit >= 10 Branches
                                 // (SonarDelphi:CaseStatementSize).
    fkEmptyFile,                 // Unit ohne jegliche Deklarationen
                                 // (SonarDelphi:EmptyFile).
    fkTwiceInheritedCalls,       // Mehrere `inherited` in derselben Methode
                                 // (SonarDelphi:TwiceInheritedCalls).
    fkRedundantParentheses,      // `((Ident))` doppelte Klammern um simple
                                 // Ausdruecke (SonarDelphi:RedundantParentheses).
    fkConsecutiveVisibility,     // Dieselbe Visibility-Section zweimal in
                                 // einer Klasse (SonarDelphi:
                                 // ConsecutiveVisibilitySection).
    fkConstructorWithoutInherited, // Konstruktor ohne `inherited` Aufruf
                                 // (SonarDelphi:ConstructorWithoutInherited).
    fkDestructorWithoutInherited,// Destruktor ohne `inherited` Aufruf
                                 // (SonarDelphi:DestructorWithoutInherited).
    fkRedundantConditional,      // `if X then Y := True else Y := False`
                                 // (SonarDelphi:RedundantConditional).
    fkIfElseBegin,               // Asymmetrische begin/end-Verwendung in
                                 // if/else (SonarDelphi:IfElseBegin).
    fkPointerName,               // Pointer-Typ-Alias ohne `P`-Prefix
                                 // (SonarDelphi:PointerName).
    fkBeginEndRequired,          // Branch ohne `begin..end` Block
                                 // (SonarDelphi:BeginEndRequired).
    fkNestedRoutine,             // Geschachtelte procedure/function
                                 // innerhalb einer anderen Methode
                                 // (SonarDelphi:NestedRoutines-Variante).
    fkFieldName,                 // Klassen-Feld ohne `F`-Prefix
                                 // (SonarDelphi:FieldName).
    fkTypeName,                  // Class/Record-Type ohne `T`-Prefix
                                 // (SonarDelphi:TypeName).
    fkInterfaceName,             // Interface-Typ ohne `I`-Prefix
                                 // (SonarDelphi:InterfaceName).
    fkMethodName,                // Methoden-Name nicht in PascalCase
                                 // (SonarDelphi:MethodName).
    fkCanBeStrictPrivate,        // Public-Member wird AUSSCHLIESSLICH von
                                 // Methoden der eigenen Klasse referenziert
                                 // -> `strict private` (echtes class-scope-
                                 // private, D2007+). Strengere Variante von
                                 // fkCanBeUnitPrivate; beide laufen nur
                                 // single-file (kein gSymbolRefIndex).
    fkSynchronizeInDestructor,   // TThread.Synchronize-Aufruf in einem
                                 // destructor Destroy. Klassischer Deadlock-
                                 // Pfad: der Worker-Thread blockiert auf
                                 // dem UI-Thread, der UI-Thread wartet via
                                 // WaitFor auf den Worker -> Hang.
    fkLockWithoutTryFinally,     // TCriticalSection.Enter (oder Acquire,
                                 // EnterCriticalSection, MonitorEnter)
                                 // ohne umschliessendes try/finally
                                 // .Leave/.Release -> bei Exception
                                 // verbleibt der Lock dauerhaft gesperrt
                                 // (Deadlock / Hang in jedem nachfolgenden
                                 // Enter-Aufruf).
    // ---- Performance-Hotspots (SCA110-112) ----
    fkStringConcatInLoop,        // s := s + x innerhalb for/while/repeat -
                                 // quadratische Allokationen, StringBuilder
                                 // oder TStringList.Add+Text ist O(n).
    fkParamByNameInLoop,         // Query.ParamByName('x').AsString := y in
                                 // Hot-Path - Lookup ist O(n) per Aufruf.
                                 // Cachen oder Params[i] direkt nutzen.
    fkFieldByNameInLoop,         // DataSet.FieldByName('x').AsString in
                                 // Loop - selber O(n)-Lookup-Hit wie
                                 // ParamByName. Field-Pointer einmal
                                 // ausserhalb der Loop holen.
    // ---- Concurrency-Familie erweitert (SCA113-114) ----
    fkThreadResumeDeprecated,    // TThread.Resume ist seit D2010 deprecated.
                                 // Stattdessen TThread.Start nutzen oder
                                 // Create(False).
    fkTThreadDestroyWithoutTerminate, // FreeAndNil(MyThread) ohne vorheriges
                                 // Terminate + WaitFor - Worker laeuft
                                 // weiter waehrend das Objekt zerstoert
                                 // wird -> AV / Heap-Corruption.
    // ---- REST/HTTP-Security (SCA115-116) ----
    fkHttpInsteadOfHttps,        // 'http://'-Stringliteral fuer Remote-URL
                                 // - Plaintext-Connect, MITM-Risiko.
                                 // Localhost/127.0.0.1 ausgenommen.
    fkDisabledTlsVerification,   // THTTPClient.SecureProtocols := [] /
                                 // .IgnoreCertificateErrors := True /
                                 // OnVerifyPeer := nil-Body - aktive
                                 // Deaktivierung der TLS-Validierung.
    // ---- Doc-Luecken (SCA117) ----
    fkPublicMemberWithoutDoc,    // Public-Member (Methode/Property/Klasse)
                                 // ohne XMLDoc oder /// Praefix-Kommentar
                                 // direkt davor. Setting: nur fuer
                                 // interface-Section.
    // ---- Naming-Familie erweitert (SCA118-119) ----
    fkExceptionName,             // class(Exception)-Descendant ohne
                                 // 'E'-Prefix (z.B. MyError statt EMyError).
    fkLocalConstantName,         // const im Methoden-Body sollte UPPER_SNAKE
                                 // (z.B. MAX_RETRIES) - PascalCase = Smell.
    fkMissingRaise,              // Exception.Create(...) erzeugt aber nie
                                 // geraised - klassischer Copy-Paste-Bug
                                 // nach raise-Refactoring. SonarDelphi-
                                 // Pendant: MissingRaiseCheck.
    fkRoutineResultUnassigned,   // Function-Body endet ohne Result-Zuweisung
                                 // -> undefined Rueckgabewert (Heisenbug).
                                 // SonarDelphi-Pendant: RoutineResultAssignedCheck.
    fkReRaiseException,          // `except on E: T do raise E;` verliert den
                                 // Original-Stack-Trace - `raise;` ohne
                                 // Argument behaelt ihn. SonarDelphi-Pendant:
                                 // ReRaiseExceptionCheck.
    fkCastAndFree,               // `TFoo(x).Free` - Typ-Cast vor Free/Destroy
                                 // ist redundant (Destroy ist virtual) und
                                 // signalisiert oft Verwirrung. SonarDelphi-
                                 // Pendant: CastAndFreeCheck.
    fkInstanceInvokedConstructor,// `obj.Create` - Constructor auf Instance
                                 // statt Class -> KEINE Allokation, Fields
                                 // werden ueber bestehende Daten gemalt.
                                 // SonarDelphi-Pendant:
                                 // InstanceInvokedConstructorCheck.
    fkInheritedMethodEmpty,      // `procedure Foo; override; begin inherited;
                                 // end;` - leeres Override ohne Mehrwert.
                                 // SonarDelphi-Pendant:
                                 // InheritedMethodWithNoCodeCheck.
    fkNilComparison,             // `x = nil` / `x <> nil` statt `Assigned(x)`
                                 // - Konvention/Style. SonarDelphi-Pendant:
                                 // NilComparisonCheck.
    fkRaisingRawException,       // `raise Exception.Create(...)` mit Basis-
                                 // klasse statt spezifischer Subklasse.
                                 // SonarDelphi-Pendant: RaisingRawExceptionCheck.
    fkDateFormatSettings,        // StrToDate/StrToFloat/... ohne explizites
                                 // TFormatSettings - locale-abhaengig.
                                 // SonarDelphi-Pendant: DateFormatSettingsCheck.
    fkUnicodeToAnsiCast,         // AnsiString(s)/UTF8String(s)/... Cast
                                 // ohne explizite Encoding - stiller
                                 // Datenverlust fuer non-ASCII. SonarDelphi-
                                 // Pendant: UnicodeToAnsiCastCheck.
    fkCharToCharPointerCast,     // PChar(charValue) - Char wird als Pointer
                                 // reinterpretiert (Codepoint = Adresse) ->
                                 // undefined behavior. SonarDelphi-Pendant:
                                 // CharacterToCharacterPointerCastCheck.
    fkIfThenShortCircuit,        // Math.IfThen / StrUtils.IfThen - beide
                                 // Aerme werden immer evaluiert, kein
                                 // Short-Circuit wie bei if/then/else.
                                 // SonarDelphi-Pendant: IfThenShortCircuitCheck.
    fkExceptionTooGeneral,       // SCA132 - `except on E: Exception do`
                                 // statt spezifischer Exception-Subklasse.
                                 // Sonar-50 #11.
    fkRaiseOutsideExcept,        // SCA133 - nacktes `raise;` ausserhalb
                                 // eines except-/on-Handlers loest eine
                                 // Access Violation aus. Sonar-50 #15.
    fkUseAfterFree,              // SCA134 - Zugriff auf eine Variable nach
                                 // .Free / FreeAndNil ohne Reassignment.
                                 // Sonar-50 #7.
    fkAbstractNotImpl,           // SCA135 - konkrete Subklasse erbt
                                 // abstrakte Methode, ueberschreibt sie
                                 // aber nicht. Within-unit only.
                                 // Sonar-50 #10.
    fkLeakInConstructor,         // SCA136 - Constructor weist Felder zu
                                 // UND raised - bei raise nach partieller
                                 // Init leaken die schon erzeugten Felder.
                                 // Sonar-50 #12.
    fkIntegerOverflow,           // SCA137 - Int64-Ziel-Variable bekommt
                                 // Product zweier Operanden ohne Int64-
                                 // Cast - Multiplikation overflow'ed
                                 // in 32-Bit. Sonar-50 #14.
    fkGodClass,                  // SCA138 - Klasse mit zu vielen Methoden
                                 // (>20) oder Feldern (>15). Sonar-50 #31.
    fkFreeWithoutNil,            // SCA139 - obj.Free ohne anschliessendes
                                 // obj := nil; dangling pointer moeglich.
                                 // Sonar-50 #25.
    fkMultipleExit,              // SCA140 - Methode mit > 3 Exit-Statements;
                                 // Pfad-Vielfalt erschwert Verstaendnis.
                                 // Sonar-50 #34.
    fkLargeClass,                // SCA141 - Klassen-Implementation > 500
                                 // Zeilen. Sonar-50 #35.
    fkUnsortedUses,              // SCA142 - uses-Klausel-Eintraege nicht
                                 // alphabetisch. Sonar-50 #47.
    fkMissingUnitHeader,         // SCA143 - Unit beginnt ohne erklaerendes
                                 // Kommentar-Block. Sonar-50 #48.
    fkFloatEquality,             // SCA144 - `=`/`<>` zwischen Float-
                                 // Operanden ist nie zuverlaessig wegen
                                 // IEEE-754-Rundung. Sonar-50 #19.
    fkExceptInDestructor,        // SCA145 - Destruktor enthaelt nkRaise
                                 // ausserhalb try/except - Crash beim
                                 // Aufraeumen. Sonar-50 #23.
    fkBooleanParam,              // SCA146 - Boolean-Parameter wird
                                 // intern als Branching-Flag genutzt -
                                 // zwei dedizierte Methoden waeren
                                 // klarer. Sonar-50 #33.
    fkUnusedPrivateMethod,       // SCA147 - private Methode in einer
                                 // Klasse hat keinen Aufrufer in der
                                 // gleichen Unit. Sonar-50 #37.
    fkCanBeClassMethod,          // SCA148 - Instance-Methode greift
                                 // weder auf Self noch auf Instanz-
                                 // Felder zu - waere als `class function`
                                 // sauberer. Sonar-50 #50.
    fkMissingOverride,           // SCA149 - Methode ueberschreibt eine
                                 // virtuelle Methode der Parent-Klasse
                                 // ohne `override`-Direktive. Within-
                                 // unit only. Sonar-50 #21.
    fkBoolAlwaysTrue,            // SCA150 - Boolean-Vergleich der immer
                                 // True/False ergibt: `Length(s) >= 0`.
                                 // Sonar-50 #18 (narrow).
    fkConstantReturn,            // SCA151 - Function weist `Result` an
                                 // mehreren Stellen den gleichen Literal-
                                 // Wert zu. Sonar-50 #43.
    fkHardcodedString,           // SCA152 - User-sichtbarer String als
                                 // Literal (Caption/Hint/Text) statt
                                 // resourcestring / i18n. Sonar-50 #46.
    fkUnpairedLock,              // SCA153 - Lock/EnterCriticalSection
                                 // ohne paired UnLock im try/finally.
                                 // mORMot/concurrency hotspot.
    fkMoveSizeOfPointer,         // SCA154 - Move(Src, Dst, SizeOf(<Ptr>))
                                 // kopiert nur Pointer-Groesse statt
                                 // Buffer-Inhalt - klassischer Bug.
    fkWithMultipleTargets,       // SCA155 - `with A, B do` mit Komma-
                                 // separierten Targets - Identifier-
                                 // Resolution reihenfolgeabhaengig.
    fkGetMemWithoutFreeMem,      // SCA156 - GetMem(p, n)/AllocMem/ReallocMem
                                 // ohne paired FreeMem im try/finally.
                                 // mORMot-Pattern, klassischer Memory-Leak.
    fkSetLengthAppendInLoop,     // SCA157 - SetLength(arr, Length(arr)+1)
                                 // innerhalb einer Schleife -> O(n*n)
                                 // Realloc-Aufwand statt einmal vor-grow.
    fkPointerArithmeticOnString, // SCA158 - PChar(s) + n / PAnsiChar(s) + n
                                 // ohne Empty-Check: PChar('') = nil ->
                                 // Pointer-Arithmetik auf NIL = AV.
    fkEmptyOnHandler,            // SCA159 - on E: SomeException do ; (oder
                                 // begin end) - typisierter Exception-Handler
                                 // schluckt Fehler still, ohne Logging/Raise.
    fkStringFromPointer,         // SCA160 - String(P) / AnsiString(P) /
                                 // UTF8String(P) Cast aus typisiertem Pointer
                                 // ohne Length-Prefix-Garantie -> Buffer-Overread.
    fkPointerSubtraction,        // SCA161 - Cardinal(P1) - Cardinal(P2)
                                 // (oder Integer/LongWord) auf Pointern -
                                 // Win64-Truncation: oberes 32-Bit verloren.
    fkInsecureCryptoAlgorithm,   // SCA162 - Verwendung schwacher/veralteter
                                 // Krypto-Verfahren (MD5/SHA1/DES/RC4/TLS1.0)
                                 // via Stringliteral oder Klassen-/Funktions-
                                 // Aufruf (THashMD5, TIdHashSHA1, ...).
    fkCommandInjection,          // SCA163 - ShellExecute/CreateProcess/WinExec
                                 // mit String-Konkatenation im Command-
                                 // Argument - mit untrusted Input = Command-
                                 // Injection-Risiko. Confidence-Default fcLow,
                                 // da ohne Taint-Tracking heuristisch.
    fkUnusedRoutine,             // SCA164 - top-level Procedure/Function im
                                 // Unit-Scope die nirgendwo aufgerufen wird.
                                 // Schliesst die Luecke zwischen SCA147
                                 // (nur class private) und SCA148+ (nur class
                                 // public). Single-File-Scope mit Self-Call-
                                 // Exclusion (analog SonarDelphi UnusedRoutine).
    fkUnusedSuppression,         // SCA165 - '// noinspection X'-Marker der
                                 // an seiner Position kein Finding suppressed
                                 // hat. Hinweis: Detektor wurde verbessert
                                 // (Suppression nicht mehr noetig) ODER
                                 // Suppression-Target war falsch gesetzt.
                                 // Emittiert vom uSuppression-Post-Filter.
    fkUninitVar,                 // SCA016 - lokale Variable die auf einem
                                 // Pfad gelesen wird bevor sie auf demselben
                                 // Pfad geschrieben wurde. Konservatives
                                 // single-method-Scope-Modell (FixInsight-
                                 // Style). Siehe Konzept_SCA016_UninitVar.md.
    fkInsecureRandom,            // SCA167 - Random/RandomRange/RandomFrom
                                 // ohne dass Randomize im File irgendwo
                                 // aufgerufen wird. Random seedet sich nicht
                                 // selbst -> bei Seed=0 gleiche Sequenz pro Lauf.
                                 // FP-Tradeoff: cross-unit Randomize wird
                                 // nicht gesehen; Suppression-Marker dann.
    fkDefaultCaseInCaseStatement, // SCA168 - case-Stmt ohne else-Branch.
                                 // Unhandled-Values fallen still durch.
    fkAssertWithSideEffect,      // SCA169 - Assert(Func()) wo Func einen
                                 // Side-Effect hat. Release-Build entfernt
                                 // Assert komplett -> Side-Effect weg.
    fkConstStringParameter,      // SCA170 - string-Parameter ohne const-
                                 // Modifier. Performance + Klarheit.
    fkCompilerDirectiveScope,    // SCA171 - {$WARNINGS OFF} ohne {$WARNINGS ON}
                                 // im File. Switch leakt in nachfolgende
                                 // Compilation-Units.
    fkBooleanPropertyNaming,     // SCA172 - Boolean-Property ohne Is/Has/
                                 // Can/Should-Prefix.
    fkVariantTypeMisuse,         // SCA173 - Variant in Methode mit Loop -
                                 // COM-VarType-Dispatch in Hot-Path.
    fkTObjectListWithoutOwnership, // SCA174 - TList<T>.Create + Add(T.Create)
                                 // ohne TObjectList<T> - Items leaken.
    fkAnonMethodCaptureLoopVar,  // SCA175 - Anonyme Methode im for-Loop
                                 // captured Loop-Var per Reference.
    fkCognitiveComplexity,       // SCA176 - Sonar-Cognitive-Complexity > 15.
                                 // Verschachtelte Logik schwerer als linear-McCabe.
    fkThreadFreeOnTerminateWithRef, // SCA177 - Zugriff auf Thread-Var nach
                                 // FreeOnTerminate := True - AV-Risiko.
    fkPathTraversal,             // SCA178 - File-Open + User-Input-Concat.
                                 // Heuristik (kein Taint-Tracking).
    fkAttributeIgnoreWithoutReason, // SCA179 - [Ignore] ohne Reason-Message.
    fkAttributeDuplicate,        // SCA180 - same Attribute zweimal am Member.
    fkAttributeCategoryWithoutString, // SCA181 - [Category] ohne String-Arg.
    fkAttributeTestFixtureWithoutTests, // SCA182 - [TestFixture]-Klasse ohne [Test].
    fkAttributeMisalignment,     // SCA183 - Attribute mit Leerzeile zum Member.
    fkDfmComponentUnused,        // SCA184 - published DFM-Komponente die weder
                                 // im Code, in anderen Units noch DFM-intern
                                 // referenziert wird (Refactoring-Rest). fcLow.
    // Encoding-/Unicode-Sicherheit-Familie (Konzept_FileEncodingDetector, Welle 1):
    fkSourceUtf8NoBom,           // SCA185 - UTF-8 ohne BOM + Nicht-ASCII (Compiler
                                 //          liest ANSI -> Mojibake).
    fkSourceInvalidUtf8,         // SCA186 - ungueltige UTF-8-Sequenz (ueberlang/
                                 //          Surrogat/>U+10FFFF).
    fkSourceControlChar,         // SCA187 - NUL/verbotenes Steuerzeichen im Quelltext.
    fkSourceBidiOverride,        // SCA188 - bidirektionales Override-Steuerzeichen
                                 //          (Trojan Source, CVE-2021-42574 / CWE-1007).
    // Encoding-Familie Welle 2:
    fkSourceAnsiNonAscii,        // SCA189 - ANSI (kein-BOM, kein gueltiges UTF-8) mit
                                 //          Nicht-ASCII -> codepage-abhaengig.
    fkSourceUtf16,               // SCA190 - UTF-16-Quelltext (kompiliert, ungewoehnlich).
    fkSourceUtf32                // SCA191 - UTF-32/UCS-4-Quelltext -> Compiler-Fehler F2438.
  );

  // Set-Typ fuer Detector-Filter (Profile/EnabledKinds). Mit 43 Werten
  // weit unter dem 256-Element-Limit eines Delphi-Sets.
  TFindingKinds = set of TFindingKind;
  // TD-1 Inkrement 2b (2026-07-06): optionaler Set-Zeiger fuer die Post-Scan-
  // Filter. nil = Global-Fallback (uSCAConsts.DetectorEnabledKinds, Test-/
  // Legacy-Aufrufer); non-nil = per-Scan-Wert (aus TAnalyzeContext.Config vor
  // FreeAndNil(Ctx) gesnapshottet). Ein Set hat keinen "unset"-Sentinel
  // ([] ist gueltig = "kein Filter"), daher Zeiger statt Wert+Flag.
  PFindingKinds = ^TFindingKinds;

  // Suppression-Marker: '// noinspection X' an einer Quell-Zeile, das auf
  // eine Target-Zeile (naechste Code-Zeile danach; 0 = file-wide Marker
  // '// noinspection-file') zielt. Wird vom Suppression-Filter konsumiert,
  // wenn dort ein Finding der passenden Kinds liegt.
  // 2026-07-05 (Audit_CodeReview #2): aus uSuppression hierher verschoben -
  // TAnalyzeContext traegt jetzt die per-Scan-Marker-Collection und darf
  // uSuppression nicht uses'en (uAnalyzeContext -> uSuppression ->
  // uDetectorUtils -> uAnalyzeContext waere ein Interface-Zyklus, seit
  // uDetectorUtils fuer den P1-Strip-Cache uAnalyzeContext kennt).
  // uSuppression aliast die Typen fuer alle bestehenden Konsumenten.
  TSuppressionMarker = record
    MarkerLine : Integer;        // Zeile mit dem '// noinspection ...'
    TargetLine : Integer;        // Ziel-Zeile (0 = file-wide)
    Kinds      : TFindingKinds;
    Consumed   : Boolean;        // True wenn der Marker mind. 1 Finding suppresst hat
  end;

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
  //
  // DefaultSeverity muss bit-exakt zu rules/sca-rules.json
  // defaultSeverity passen - der Konsistenz-Test in
  // uTestRuleCatalog (JsonSeverityMatchesKindMeta) faellt sofort,
  // wenn die beiden divergieren.
  TFindingKindMeta = record
    Name            : string;       // 'MemoryLeak' (canonical token)
    FindingType     : TFindingType; // Sonar-Kategorie
    DefaultSeverity : TLeakSeverity;// Standard-Severity beim Emit
  end;

  TConsts = record
    class function GetLeakyClasses: TStringList; static;
  end;

const
  // Single-Source-of-Truth fuer die Build-Version. Wird im CLI
  // (--version), im About-Dialog und in der Form-Caption verwendet.
  // VerInfo-Keys in den .dproj-Dateien muessen dazu passen
  // (FileVersion / ProductVersion = SCA_VERSION_FULL).
  SCA_VERSION      = '0.9.8';
  SCA_VERSION_FULL = '0.9.8.0';
  SCA_RELEASE_DATE = '2026-05-27';

  // Reihenfolge MUSS exakt mit TFindingKind uebereinstimmen.
  // Beim Hinzufuegen eines neuen TFindingKind: hier nachpflegen, dann
  // den eigentlichen Detektor in TStaticAnalyzer2.RunAllDetectors
  // registrieren - das sind die einzigen zwei Stellen.
  KIND_META: array[TFindingKind] of TFindingKindMeta = (
    (Name: 'MemoryLeak';      FindingType: ftBug;             DefaultSeverity: lsError),   // fkMemoryLeak
    (Name: 'EmptyExcept';     FindingType: ftCodeSmell;       DefaultSeverity: lsWarning), // fkEmptyExcept
    (Name: 'SQLInjection';    FindingType: ftVulnerability;   DefaultSeverity: lsError),   // fkSQLInjection
    (Name: 'HardcodedSecret'; FindingType: ftVulnerability;   DefaultSeverity: lsError),   // fkHardcodedSecret
    (Name: 'FormatMismatch';  FindingType: ftBug;             DefaultSeverity: lsError),   // fkFormatMismatch
    (Name: 'FileReadError';   FindingType: ftFileError;       DefaultSeverity: lsError),   // fkFileReadError
    (Name: 'UnusedUses';      FindingType: ftCodeSmell;       DefaultSeverity: lsHint),    // fkUnusedUses
    (Name: 'NilDeref';        FindingType: ftBug;             DefaultSeverity: lsWarning), // fkNilDeref
    (Name: 'MissingFinally';  FindingType: ftCodeSmell;       DefaultSeverity: lsWarning), // fkMissingFinally
    (Name: 'DivByZero';       FindingType: ftBug;             DefaultSeverity: lsWarning), // fkDivByZero
    (Name: 'DeadCode';        FindingType: ftCodeSmell;       DefaultSeverity: lsWarning), // fkDeadCode
    (Name: 'LongMethod';      FindingType: ftCodeSmell;       DefaultSeverity: lsHint),    // fkLongMethod
    (Name: 'LongParamList';   FindingType: ftCodeSmell;       DefaultSeverity: lsHint),    // fkLongParamList
    (Name: 'MagicNumber';     FindingType: ftCodeSmell;       DefaultSeverity: lsHint),    // fkMagicNumber
    (Name: 'DuplicateString'; FindingType: ftCodeDuplication; DefaultSeverity: lsHint),    // fkDuplicateString
    (Name: 'HardcodedPath';   FindingType: ftSecurityHotspot; DefaultSeverity: lsWarning), // fkHardcodedPath
    (Name: 'DebugOutput';     FindingType: ftCodeSmell;       DefaultSeverity: lsWarning), // fkDebugOutput
    (Name: 'DeepNesting';     FindingType: ftCodeSmell;       DefaultSeverity: lsHint),    // fkDeepNesting
    (Name: 'TodoComment';     FindingType: ftCodeSmell;       DefaultSeverity: lsHint),    // fkTodoComment
    (Name: 'EmptyMethod';     FindingType: ftCodeSmell;       DefaultSeverity: lsHint),    // fkEmptyMethod
    (Name: 'DuplicateBlock';  FindingType: ftCodeDuplication; DefaultSeverity: lsHint),    // fkDuplicateBlock
    (Name: 'CyclomaticComplexity'; FindingType: ftCodeSmell;  DefaultSeverity: lsHint),    // fkCyclomaticComplexity
    (Name: 'CustomRule';      FindingType: ftCodeSmell;       DefaultSeverity: lsWarning), // fkCustomRule
    (Name: 'DfmDefaultName';      FindingType: ftCodeSmell;       DefaultSeverity: lsHint),    // fkDfmDefaultName
    (Name: 'DfmHardcodedCaption'; FindingType: ftCodeSmell;       DefaultSeverity: lsHint),    // fkDfmHardcodedCaption
    (Name: 'DfmHardcodedDbCreds'; FindingType: ftVulnerability;   DefaultSeverity: lsError),   // fkDfmHardcodedDbCreds
    (Name: 'DfmDuplicateBinding'; FindingType: ftBug;             DefaultSeverity: lsWarning), // fkDfmDuplicateBinding
    (Name: 'DfmDeadEvent';        FindingType: ftBug;             DefaultSeverity: lsError),   // fkDfmDeadEvent
    (Name: 'DfmOrphanHandler';    FindingType: ftCodeSmell;       DefaultSeverity: lsHint),    // fkDfmOrphanHandler
    (Name: 'DfmEmptyBoundEvent';  FindingType: ftCodeSmell;       DefaultSeverity: lsHint),    // fkDfmEmptyBoundEvent
    (Name: 'DfmSchemaMismatch';      FindingType: ftBug;          DefaultSeverity: lsError),   // fkDfmSchemaMismatch
    (Name: 'DfmCircularDataSource';  FindingType: ftBug;          DefaultSeverity: lsError),   // fkDfmCircularDataSource
    (Name: 'DfmSqlFromUserInput';        FindingType: ftVulnerability; DefaultSeverity: lsError),   // fkDfmSqlFromUserInput
    (Name: 'DfmRequiredFieldUnbound';    FindingType: ftBug;          DefaultSeverity: lsWarning), // fkDfmRequiredFieldUnbound
    (Name: 'DfmRequiredFieldNotVisible'; FindingType: ftBug;          DefaultSeverity: lsWarning), // fkDfmRequiredFieldNotVisible
    (Name: 'DfmFieldTypeMismatch';       FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkDfmFieldTypeMismatch
    (Name: 'DfmTabOrderConflict';        FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkDfmTabOrderConflict
    (Name: 'DfmForbiddenClass';          FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkDfmForbiddenClass
    (Name: 'DfmDbInUiForm';              FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkDfmDbInUiForm
    (Name: 'DfmCrossFormCoupling';       FindingType: ftBug;          DefaultSeverity: lsWarning), // fkDfmCrossFormCoupling
    (Name: 'DfmLayerViolation';          FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkDfmLayerViolation
    (Name: 'DfmGodHandler';              FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkDfmGodHandler
    (Name: 'DfmActionMismatch';          FindingType: ftBug;          DefaultSeverity: lsWarning), // fkDfmActionMismatch
    (Name: 'ConcatToFormat';             FindingType: ftCodeSmell;    DefaultSeverity: lsWarning), // fkConcatToFormat
    (Name: 'WithStatement';              FindingType: ftCodeSmell;    DefaultSeverity: lsWarning), // fkWithStatement
    (Name: 'ReversedForRange';           FindingType: ftBug;          DefaultSeverity: lsError),   // fkReversedForRange
    (Name: 'SelfAssignment';             FindingType: ftBug;          DefaultSeverity: lsWarning), // fkSelfAssignment
    (Name: 'VirtualCallInCtor';          FindingType: ftBug;          DefaultSeverity: lsError),   // fkVirtualCallInCtor
    (Name: 'LengthUnderflow';            FindingType: ftBug;          DefaultSeverity: lsHint),    // fkLengthUnderflow
    (Name: 'CanBeUnitPrivate';           FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkCanBeUnitPrivate
    (Name: 'CanBeProtected';             FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkCanBeProtected
    (Name: 'UnusedPublicMember';         FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkUnusedPublicMember
    (Name: 'UnusedLocalVar';             FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkUnusedLocalVar
    (Name: 'UnusedParameter';            FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkUnusedParameter
    (Name: 'TautologicalBoolExpr';       FindingType: ftBug;          DefaultSeverity: lsError),   // fkTautologicalBoolExpr
    (Name: 'DfmMasterDetailUnlinked';    FindingType: ftBug;          DefaultSeverity: lsError),   // fkDfmMasterDetailUnlinked
    (Name: 'DfmDataModuleSplitHint';     FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkDfmDataModuleSplitHint
    (Name: 'SqlDangerousStatement';      FindingType: ftBug;          DefaultSeverity: lsError),   // fkSqlDangerousStatement
    (Name: 'FormatLocaleHint';           FindingType: ftBug;          DefaultSeverity: lsHint),    // fkFormatLocaleHint
    (Name: 'GotoStatement';              FindingType: ftCodeSmell;    DefaultSeverity: lsWarning), // fkGotoStatement
    (Name: 'TabulationCharacter';        FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkTabulationCharacter
    (Name: 'TooLongLine';                FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkTooLongLine
    (Name: 'TrailingWhitespace';         FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkTrailingWhitespace
    (Name: 'LowercaseKeyword';           FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkLowercaseKeyword
    (Name: 'NoSonarMarker';              FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkNoSonarMarker
    (Name: 'EmptyArgumentList';          FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkEmptyArgumentList
    (Name: 'InlineAssembly';             FindingType: ftCodeSmell;    DefaultSeverity: lsWarning), // fkInlineAssembly
    (Name: 'TrailingCommaArgList';       FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkTrailingCommaArgList
    (Name: 'DigitGrouping';              FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkDigitGrouping
    (Name: 'CommentedOutCode';           FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkCommentedOutCode
    (Name: 'UnitLevelKeywordIndent';     FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkUnitLevelKeywordIndent
    (Name: 'RedundantBoolean';           FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkRedundantBoolean
    (Name: 'EmptyInterface';             FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkEmptyInterface
    (Name: 'AssertMessage';              FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkAssertMessage
    (Name: 'ExplicitTObjectInheritance'; FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkExplicitTObjectInheritance
    (Name: 'GroupedDeclaration';         FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkGroupedDeclaration
    (Name: 'EmptyBlock';                 FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkEmptyBlock
    (Name: 'ExceptOnException';          FindingType: ftBug;          DefaultSeverity: lsWarning), // fkExceptOnException
    (Name: 'ConsecutiveSection';         FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkConsecutiveSection
    (Name: 'RedundantJump';              FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkRedundantJump
    (Name: 'ClassPerFile';               FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkClassPerFile
    (Name: 'SuperfluousSemicolon';       FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkSuperfluousSemicolon
    (Name: 'EmptyFinallyBlock';          FindingType: ftBug;          DefaultSeverity: lsWarning), // fkEmptyFinallyBlock
    (Name: 'AssignedAndAssignedNil';     FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkAssignedAndAssignedNil
    (Name: 'FreeAndNilHint';             FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkFreeAndNilHint
    (Name: 'AvoidOut';                   FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkAvoidOut
    (Name: 'EmptyVisibilitySection';     FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkEmptyVisibilitySection
    (Name: 'LegacyInitializationSection';FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkLegacyInitializationSection
    (Name: 'PublicField';                FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkPublicField
    (Name: 'NestedTry';                  FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkNestedTry
    (Name: 'CaseStatementSize';          FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkCaseStatementSize
    (Name: 'EmptyFile';                  FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkEmptyFile
    (Name: 'TwiceInheritedCalls';        FindingType: ftBug;          DefaultSeverity: lsWarning), // fkTwiceInheritedCalls
    (Name: 'RedundantParentheses';       FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkRedundantParentheses
    (Name: 'ConsecutiveVisibility';      FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkConsecutiveVisibility
    (Name: 'ConstructorWithoutInherited';FindingType: ftBug;          DefaultSeverity: lsWarning), // fkConstructorWithoutInherited
    (Name: 'DestructorWithoutInherited'; FindingType: ftBug;          DefaultSeverity: lsError),   // fkDestructorWithoutInherited
    (Name: 'RedundantConditional';       FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkRedundantConditional
    (Name: 'IfElseBegin';                FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkIfElseBegin
    (Name: 'PointerName';                FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkPointerName
    (Name: 'BeginEndRequired';           FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkBeginEndRequired
    (Name: 'NestedRoutine';              FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkNestedRoutine
    (Name: 'FieldName';                  FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkFieldName
    (Name: 'TypeName';                   FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkTypeName
    (Name: 'InterfaceName';              FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkInterfaceName
    (Name: 'MethodName';                 FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkMethodName
    (Name: 'CanBeStrictPrivate';         FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkCanBeStrictPrivate
    (Name: 'SynchronizeInDestructor';    FindingType: ftBug;          DefaultSeverity: lsError),   // fkSynchronizeInDestructor
    (Name: 'LockWithoutTryFinally';      FindingType: ftBug;          DefaultSeverity: lsError),   // fkLockWithoutTryFinally
    (Name: 'StringConcatInLoop';         FindingType: ftCodeSmell;    DefaultSeverity: lsWarning), // fkStringConcatInLoop
    (Name: 'ParamByNameInLoop';          FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkParamByNameInLoop
    (Name: 'FieldByNameInLoop';          FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkFieldByNameInLoop
    (Name: 'ThreadResumeDeprecated';     FindingType: ftCodeSmell;    DefaultSeverity: lsWarning), // fkThreadResumeDeprecated
    (Name: 'TThreadDestroyWithoutTerminate'; FindingType: ftBug;      DefaultSeverity: lsError),   // fkTThreadDestroyWithoutTerminate
    (Name: 'HttpInsteadOfHttps';         FindingType: ftSecurityHotspot; DefaultSeverity: lsWarning),// fkHttpInsteadOfHttps
    (Name: 'DisabledTlsVerification';    FindingType: ftVulnerability; DefaultSeverity: lsError),  // fkDisabledTlsVerification
    (Name: 'PublicMemberWithoutDoc';     FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkPublicMemberWithoutDoc
    (Name: 'ExceptionName';              FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkExceptionName
    (Name: 'LocalConstantName';          FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkLocalConstantName
    (Name: 'MissingRaise';               FindingType: ftBug;          DefaultSeverity: lsError),   // fkMissingRaise
    (Name: 'RoutineResultUnassigned';    FindingType: ftBug;          DefaultSeverity: lsError),   // fkRoutineResultUnassigned
    (Name: 'ReRaiseException';           FindingType: ftBug;          DefaultSeverity: lsWarning), // fkReRaiseException
    (Name: 'CastAndFree';                FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkCastAndFree
    (Name: 'InstanceInvokedConstructor'; FindingType: ftBug;          DefaultSeverity: lsError),   // fkInstanceInvokedConstructor
    (Name: 'InheritedMethodEmpty';       FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkInheritedMethodEmpty
    (Name: 'NilComparison';              FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkNilComparison
    (Name: 'RaisingRawException';        FindingType: ftCodeSmell;    DefaultSeverity: lsWarning), // fkRaisingRawException
    (Name: 'DateFormatSettings';         FindingType: ftBug;          DefaultSeverity: lsWarning), // fkDateFormatSettings
    (Name: 'UnicodeToAnsiCast';          FindingType: ftBug;          DefaultSeverity: lsWarning), // fkUnicodeToAnsiCast
    (Name: 'CharToCharPointerCast';      FindingType: ftBug;          DefaultSeverity: lsError),   // fkCharToCharPointerCast
    (Name: 'IfThenShortCircuit';         FindingType: ftBug;          DefaultSeverity: lsWarning), // fkIfThenShortCircuit
    (Name: 'ExceptionTooGeneral';        FindingType: ftCodeSmell;    DefaultSeverity: lsWarning), // fkExceptionTooGeneral
    (Name: 'RaiseOutsideExcept';         FindingType: ftBug;          DefaultSeverity: lsError),   // fkRaiseOutsideExcept
    (Name: 'UseAfterFree';               FindingType: ftBug;          DefaultSeverity: lsError),   // fkUseAfterFree
    (Name: 'AbstractNotImpl';            FindingType: ftBug;          DefaultSeverity: lsError),   // fkAbstractNotImpl
    (Name: 'LeakInConstructor';          FindingType: ftBug;          DefaultSeverity: lsError),   // fkLeakInConstructor
    (Name: 'IntegerOverflow';            FindingType: ftBug;          DefaultSeverity: lsError),   // fkIntegerOverflow
    (Name: 'GodClass';                   FindingType: ftCodeSmell;    DefaultSeverity: lsWarning), // fkGodClass
    (Name: 'FreeWithoutNil';             FindingType: ftCodeSmell;    DefaultSeverity: lsWarning), // fkFreeWithoutNil
    (Name: 'MultipleExit';               FindingType: ftCodeSmell;    DefaultSeverity: lsWarning), // fkMultipleExit
    (Name: 'LargeClass';                 FindingType: ftCodeSmell;    DefaultSeverity: lsWarning), // fkLargeClass
    (Name: 'UnsortedUses';               FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkUnsortedUses
    (Name: 'MissingUnitHeader';          FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkMissingUnitHeader
    (Name: 'FloatEquality';              FindingType: ftBug;          DefaultSeverity: lsWarning), // fkFloatEquality
    (Name: 'ExceptInDestructor';         FindingType: ftBug;          DefaultSeverity: lsWarning), // fkExceptInDestructor
    (Name: 'BooleanParam';               FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkBooleanParam
    (Name: 'UnusedPrivateMethod';        FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkUnusedPrivateMethod
    (Name: 'CanBeClassMethod';           FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkCanBeClassMethod
    (Name: 'MissingOverride';            FindingType: ftBug;          DefaultSeverity: lsWarning), // fkMissingOverride
    (Name: 'BoolAlwaysTrue';             FindingType: ftBug;          DefaultSeverity: lsWarning), // fkBoolAlwaysTrue
    (Name: 'ConstantReturn';             FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkConstantReturn
    (Name: 'HardcodedString';            FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkHardcodedString
    (Name: 'UnpairedLock';               FindingType: ftBug;          DefaultSeverity: lsWarning), // fkUnpairedLock
    (Name: 'MoveSizeOfPointer';          FindingType: ftBug;          DefaultSeverity: lsWarning), // fkMoveSizeOfPointer
    (Name: 'WithMultipleTargets';        FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkWithMultipleTargets
    (Name: 'GetMemWithoutFreeMem';       FindingType: ftBug;          DefaultSeverity: lsWarning), // fkGetMemWithoutFreeMem
    (Name: 'SetLengthAppendInLoop';      FindingType: ftCodeSmell;    DefaultSeverity: lsWarning), // fkSetLengthAppendInLoop
    (Name: 'PointerArithmeticOnString';  FindingType: ftBug;          DefaultSeverity: lsWarning), // fkPointerArithmeticOnString
    (Name: 'EmptyOnHandler';             FindingType: ftBug;          DefaultSeverity: lsWarning), // fkEmptyOnHandler
    (Name: 'StringFromPointer';          FindingType: ftBug;          DefaultSeverity: lsWarning), // fkStringFromPointer
    (Name: 'PointerSubtraction';         FindingType: ftBug;          DefaultSeverity: lsWarning), // fkPointerSubtraction
    (Name: 'InsecureCryptoAlgorithm';    FindingType: ftVulnerability;DefaultSeverity: lsWarning), // fkInsecureCryptoAlgorithm
    (Name: 'CommandInjection';           FindingType: ftVulnerability;DefaultSeverity: lsError),   // fkCommandInjection
    (Name: 'UnusedRoutine';              FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkUnusedRoutine
    (Name: 'UnusedSuppression';          FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkUnusedSuppression
    (Name: 'UninitVar';                  FindingType: ftBug;          DefaultSeverity: lsError),   // fkUninitVar
    (Name: 'InsecureRandom';             FindingType: ftBug;          DefaultSeverity: lsWarning), // fkInsecureRandom
    (Name: 'DefaultCaseInCaseStatement'; FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkDefaultCaseInCaseStatement
    (Name: 'AssertWithSideEffect';       FindingType: ftBug;          DefaultSeverity: lsWarning), // fkAssertWithSideEffect
    (Name: 'ConstStringParameter';       FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkConstStringParameter
    (Name: 'CompilerDirectiveScope';     FindingType: ftCodeSmell;    DefaultSeverity: lsWarning), // fkCompilerDirectiveScope
    (Name: 'BooleanPropertyNaming';      FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkBooleanPropertyNaming
    (Name: 'VariantTypeMisuse';          FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkVariantTypeMisuse
    (Name: 'TObjectListWithoutOwnership';FindingType: ftBug;          DefaultSeverity: lsWarning), // fkTObjectListWithoutOwnership
    (Name: 'AnonMethodCaptureLoopVar';   FindingType: ftBug;          DefaultSeverity: lsError),   // fkAnonMethodCaptureLoopVar
    (Name: 'CognitiveComplexity';        FindingType: ftCodeSmell;    DefaultSeverity: lsWarning), // fkCognitiveComplexity
    (Name: 'ThreadFreeOnTerminateWithRef';FindingType: ftBug;         DefaultSeverity: lsError),   // fkThreadFreeOnTerminateWithRef
    (Name: 'PathTraversal';              FindingType: ftVulnerability;DefaultSeverity: lsError),   // fkPathTraversal
    (Name: 'AttributeIgnoreWithoutReason';FindingType: ftCodeSmell;   DefaultSeverity: lsHint),    // fkAttributeIgnoreWithoutReason
    (Name: 'AttributeDuplicate';         FindingType: ftCodeSmell;    DefaultSeverity: lsWarning), // fkAttributeDuplicate
    (Name: 'AttributeCategoryWithoutString';FindingType: ftBug;       DefaultSeverity: lsError),   // fkAttributeCategoryWithoutString
    (Name: 'AttributeTestFixtureWithoutTests';FindingType: ftCodeSmell;DefaultSeverity: lsWarning),// fkAttributeTestFixtureWithoutTests
    (Name: 'AttributeMisalignment';      FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkAttributeMisalignment
    (Name: 'DfmComponentUnused';         FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkDfmComponentUnused
    (Name: 'SourceUtf8NoBom';            FindingType: ftBug;          DefaultSeverity: lsWarning), // fkSourceUtf8NoBom
    (Name: 'SourceInvalidUtf8';          FindingType: ftFileError;    DefaultSeverity: lsError),   // fkSourceInvalidUtf8
    (Name: 'SourceControlChar';          FindingType: ftFileError;    DefaultSeverity: lsError),   // fkSourceControlChar
    (Name: 'SourceBidiOverride';         FindingType: ftVulnerability;DefaultSeverity: lsError),   // fkSourceBidiOverride
    (Name: 'SourceAnsiNonAscii';         FindingType: ftCodeSmell;    DefaultSeverity: lsWarning), // fkSourceAnsiNonAscii
    (Name: 'SourceUtf16';                FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkSourceUtf16
    (Name: 'SourceUtf32';                FindingType: ftFileError;    DefaultSeverity: lsError)    // fkSourceUtf32
  );

// Convenience-Wrapper - delegieren auf KIND_META.
function KindName(K: TFindingKind): string;
function KindFindingType(K: TFindingKind): TFindingType;
// Default-Severity fuer ein TFindingKind. Wird von TLeakFinding.SetKind
// genutzt um Severity konsistent aus dem Catalog zu ziehen statt sie
// in jedem Detector hardzucoden. Wert MUSS zu rules/sca-rules.json
// defaultSeverity passen - Test in uTestRuleCatalog enforced das.
function KindDefaultSeverity(K: TFindingKind): TLeakSeverity;
// Reverse-Lookup ueber Name (case-insensitive). Liefert False bei
// unbekanntem Namen; Kind ist dann undefiniert.
function KindFromName(const Name: string; out K: TFindingKind): Boolean;
// Klassifizierung: liefert True wenn das TFindingKind zur SonarDelphi-
// Import-Welle (SCA060+) gehoert. Markierung beginnt ab fkGotoStatement -
// alles davor sind SCA-native Detektoren (Phase 0/A). Wird im HTML-Export
// fuer den Detector-Filter (Alle/Top10/Ohne SonarDelphi/Nur SonarDelphi)
// genutzt. Sobald neue SonarDelphi-Kinds zwischen den nativen geschoben
// werden, muss diese Funktion auf eine Whitelist umgestellt werden.
function IsSonarDelphiKind(K: TFindingKind): Boolean;

// Default-Konfidenz pro TFindingKind (Phase-1 A.1 Audit). Die meisten
// Detektoren sind sicher (fcHigh) - heuristische Pattern-Matcher und
// Metrik-basierte Hints sind als fcMedium markiert, damit sie im
// Default-Profil (FindingMinConfidence=fcMedium) sichtbar bleiben aber
// per --min-confidence high ausgeblendet werden koennen.
//   fcLow    - Detektoren die explizit niedrig sein wollen (z.B.
//              uCommandInjection ohne Taint-Tracking) setzen
//              Confidence selbst nach SetKind herab.
//   fcMedium - Pattern-Match-/Metrik-basiert, gelegentliche FPs
//   fcHigh   - struktureller Bug-Match, klare Logik (Default)
// Begruendung pro Kind: siehe docs/ConfidenceAudit.md.
function KindDefaultConfidence(K: TFindingKind): TFindingConfidence;

// Lesbarer Name einer Konfidenz-Stufe ('low'/'medium'/'high') - fuer
// Config-Serialisierung, SARIF-Rank und UI.
function ConfidenceName(C: TFindingConfidence): string;
// Reverse-Lookup (case-insensitive). Unbekannt/leer -> ADefault.
function ParseConfidence(const S: string;
  ADefault: TFindingConfidence = fcMedium): TFindingConfidence;

const
  // Engine-Defaults der Filter-Globals unten - Teil des Default-Satzes von
  // ResetEngineConfigDefaults (2026-07-04, s. Const-Block am Unit-Anfang;
  // hier separat, weil TLeakSeverity/TFindingConfidence erst oben deklariert
  // sind).
  DEF_DETECTOR_MIN_SEVERITY  = lsHint;
  DEF_FINDING_MIN_CONFIDENCE = fcMedium;

var
  // Whitelist erlaubter Kinds fuer den Detector-Loop. Wird von
  // TRepoSettings.ApplyDetectorThresholds aus dem Profile (rules/
  // sca-rules.json -> profiles.<name>) gesetzt.
  //   Empty ([])         = kein Filter, alle Detektoren laufen
  //                        (Backwards-Compat-Default fuer Code, der
  //                        ApplyDetectorThresholds nicht ruft).
  //   Non-Empty Subset   = Whitelist, andere Detektoren werden geskippt.
  DetectorEnabledKinds : TFindingKinds = [];

  // Severity-Schwellwert. Detektoren deren DefaultSeverity (laut Catalog)
  // strenger ist als dieser Wert werden geskippt.
  //   lsHint    (Default) = alles laeuft (Ordinal 2, nichts ist strenger)
  //   lsWarning           = Hints raus, Warnings + Errors laufen
  //   lsError             = nur sichere Bugs / Vulnerabilities
  // Severity-Ordering: lsError=0 < lsWarning=1 < lsHint=2 -> ein
  // Detector wird geskippt wenn Ord(DetectorSev) > Ord(MinSeverity).
  DetectorMinSeverity  : TLeakSeverity = DEF_DETECTOR_MIN_SEVERITY;

  // Konfidenz-Schwellwert (Post-Filter). Befunde deren Confidence niedriger
  // ist als dieser Wert werden verworfen.
  //   fcLow              = kein Filter (alles laeuft, auch heuristische Treffer)
  //   fcMedium (Default) = nur fcLow raus
  //   fcHigh             = nur sichere Treffer
  // Ordering: fcLow=0 < fcMedium=1 < fcHigh=2 -> ein Befund faellt raus
  // wenn Ord(Confidence) < Ord(FindingMinConfidence). fkFileReadError ist
  // davon ausgenommen (Diagnose-Befund, vgl. uConfidenceFilter).
  FindingMinConfidence : TFindingConfidence = DEF_FINDING_MIN_CONFIDENCE;

// Setzt ALLE Scan-Konfigurations-Globals dieser Unit auf die dokumentierten
// Engine-Defaults zurueck (2026-07-04, Audit Global-State):
//   * skalare Detektor-Schwellen (DetectorMax*/DetectorMin*, DEF_*-Konstanten)
//   * Filter (DetectorEnabledKinds/DetectorMinSeverity/FindingMinConfidence)
//   * Flags (AutoDiscoverCustomClasses, UIMaxDisplayedFindings)
//   * Konfigurations-Listen: Clear + Basisbefuellung (LeakyClasses,
//     LeakyClassExcludes, DetectorMagicTrivials, DetectorFormatFunctions,
//     DfmForbiddenClasses) - die Listen-OBJEKTE bleiben dabei stabil
//     (kein Re-Create), haengende Referenzen bleiben gueltig.
//
// BEWUSST NICHT enthalten:
//   * DiscoveredClasses/DiscoveredStaticClasses - Output-SAMMLER des Laufs,
//     keine Konfiguration; Consumer leeren sie pro Run selbst (SetupForRun
//     Schritt 7 / ApplyDetectorConfig).
//   * Flags (Byte) - Parser-Zustands-Bitmaske (TSectionFlag), kein Config.
//
// Wird im initialization-Block gerufen (Startzustand = beweisbar derselbe
// wie vor dem Refactoring) und von uEngineApi.TAnalysisSession.ApplyConfig
// als Config-Riegel vor jedem Neuaufbau des Config-Satzes (verhindert dass
// Scan 2 im Direkt-Modus still die INI-Schwellen von Scan 1 erbt).
procedure ResetEngineConfigDefaults;

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

// noinspection-file AvoidOut, MissingUnitHeader, NestedRoutine, NoSonarMarker, RedundantBoolean, TodoComment, TooLongLine, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

{ ---- KIND_META Helpers ---- }

function KindName(K: TFindingKind): string;
begin
  Result := KIND_META[K].Name;
end;

function KindFindingType(K: TFindingKind): TFindingType;
begin
  Result := KIND_META[K].FindingType;
end;

function KindDefaultSeverity(K: TFindingKind): TLeakSeverity;
begin
  Result := KIND_META[K].DefaultSeverity;
end;

function KindDefaultConfidence(K: TFindingKind): TFindingConfidence;
// Phase-1 A.1 Confidence-Audit. Listet die Kinds die NICHT als fcHigh
// gelten. Default (else-Pfad) = fcHigh. Begruendung pro Eintrag:
// docs/ConfidenceAudit.md.
begin
  case K of
    // --- FP-Rate >50% gemessen -> fcLow = raus aus dem Default-Profil
    //     (fcLow < fcMedium-Schwelle), bleibt opt-in via Profil mit
    //     niedrigerer FindingMinConfidence ---
    // SCA148 CanBeClassMethod: Korpus-Triage 2026-06-28 ~68% FP (Stichprobe
    // 31 / 19090 Funde). Dominante FP-Klasse = geerbte VCL-/Basisklassen-
    // Member ueber Unit-Grenzen (z.B. SynHighlighter-FuncXxx = 3725 Funde,
    // VCL-Property-Setter), nur mit cross-unit-Member-Resolution fixbar.
    // H4-Entscheidung: Demotion statt grossem fragilem Detektor-Umbau (lsHint,
    // kein Bug). Siehe Todo_DetectorHardening.md.
    fkCanBeClassMethod: Result := fcLow;
    // SCA170 ConstStringParameter: Korpus-Triage 2026-06-28 ~26% FP (20-50%-
    // Band) bei fast ungeguardetem Detektor, der zudem auf fcHigh stand
    // (mis-tiered fuer einen Perf-Hint-Smell). Guard fuer vertrags-fixierte
    // Signaturen (virtual/override/message/Event-Handler) ergaenzt; Tier auf
    // fcLow -> raus aus dem Default-Profil, opt-in.
    fkConstStringParameter: Result := fcLow;
    // Single-File-Scope-Familie: Sichtbarkeits-/Nutzungs-Regeln auf PUBLIC-
    // Member, die nur das aktuelle File sehen (kein Cross-Unit-Index). Public-
    // Member sind per Definition fuer Cross-Unit-Nutzung da -> hohe strukturelle
    // FP-Rate (gleiche Ursache wie CanBeClassMethod, dort 68% gemessen). Nicht
    // ohne Cross-Unit-Index fixbar -> fcLow (raus aus Default, opt-in).
    // (fkUnusedPrivateMethod bleibt fcMedium: private Scope ist single-file
    //  weitgehend valide, FP nur via RTTI/DFM.)
    fkCanBeUnitPrivate, fkCanBeProtected, fkCanBeStrictPrivate,
    fkUnusedPublicMember: Result := fcLow;
    // Bug-Detektoren mit gemessener FP-Rate >50% (Real-World-Triage 2026-06-28)
    // OHNE billigen Vollfix (brauchen CFG-/Cross-Unit-Analyse) -> aus fcHigh auf
    // fcLow, damit sie den CI-Build nicht mit ueberwiegend falschen Befunden rot
    // faerben. SCA134 UseAfterFree ~94% (then/else-Branch-Disjunktheit, echte
    // CFG-Dominanz noetig); SCA135 AbstractNotImpl ~79% (konkrete Leaf-Subklasse
    // liegt cross-file, in-Unit-ParentSet sieht sie nicht).
    fkUseAfterFree, fkAbstractNotImpl: Result := fcLow;
    // SCA078 ExceptOnException: lexikalisch + guard-los, ist ein striktes
    // Superset von SCA132 (ExceptionTooGeneral) - 1370/1414 SCA132-Stellen
    // sind auch hier, plus 3910 zusaetzliche, die SCA132 als legitime
    // Boundary-/Translate-Reraise-Handler bewusst unterdrueckt. ~72% FP.
    // Bis SCA078 in SCA132 gemerged ist -> fcLow (SCA132 deckt die echten ab).
    fkExceptOnException: Result := fcLow;
    // SCA049 LengthUnderflow: lexikalisch, KEIN Guard-/CFG-Wissen (`if Length(s)
    // >= K` davor unsichtbar). ~80% FP (Triage 2026-06-29): vorab-geguardete
    // Slices, penultimate-Index `arr[Count-2]`, strip-trailing nach Build.
    // Delete(/Copy(-Idiom ist jetzt geguarded; der CFG-Rest ist nicht billig
    // fixbar -> fcLow (lsHint sowieso).
    fkLengthUnderflow: Result := fcLow;
    // SCA158 PointerArithmeticOnString: lexisch `PChar(x) +/- n`. ~645 Funde,
    // strukturell >50% FP (Triage 2026-06-29): dominante Klasse ist das sichere
    // interne Header-Zugriffs-Idiom auf ROHE Pointer/dyn. Arrays (mORMot/
    // dmustache: PAnsiChar(arr)-_DALEN etc.), NICHT managed Strings - die
    // PChar('')=nil-Praemisse trifft dort nicht. Kein billiger Guard ohne
    // Typ-Aufloesung (string vs Pointer) -> fcLow.
    fkPointerArithmeticOnString: Result := fcLow;
    // SCA184 DfmComponentUnused: neuer Cross-Unit-Heuristik-Detektor mit
    // realer FP-Flaeche (namens-basierter Use-Nachweis ueber Code/DFM/Cross-
    // Unit-Index, kein exaktes Binding). Bewusst unter dem fcMedium-Default-
    // Filter; Promotion erst nach Real-World-A/B.
    fkDfmComponentUnused: Result := fcLow;

    // SCA185 SourceUtf8NoBom: fcLow (raus aus dem Default-Profil, opt-in). Ein
    // reiner Byte-Detektor kann Nicht-ASCII in KOMMENTAREN (vom Compiler
    // verworfen -> funktional harmlos) nicht von Nicht-ASCII in String-Literalen
    // (echter Laufzeit-Bug) unterscheiden - das braucht Token-/AST-Scope
    // (spaetere Welle). Auf einem realen Korpus (Self-Scan 74/472 Dateien) ist
    // die Mehrheit Kommentar-Rauschen. Die UTF-8-vs-CP1252-Grenze ist zudem bei
    // einer 2-Byte-Sequenz unentscheidbar (C3 A9 = UTF-8 'e-acute' UND gueltiges
    // CP1252). fkSourceInvalidUtf8/ControlChar/BidiOverride bleiben fcHigh
    // (else-Default) - deterministische, praezise Byte-Fakten, 0 Self-Scan.
    fkSourceUtf8NoBom: Result := fcLow;
    // SCA189 SourceAnsiNonAscii: fcMedium. Feuert nur bei Nicht-ASCII, das KEIN
    // gueltiges UTF-8 ist (also echt 8-bit-enkodiert) - staerkeres Signal als E1
    // und 0 Self-Scan-Treffer, daher default-sichtbar. Teilt aber E1s Kommentar-
    // vs-String-Grenze; bei Real-World-Rauschen ggf. demoten.
    // SCA190 SourceUtf16: fcLow (kompiliert, stilistisch/Tooling-Reibung, opt-in).
    // SCA191 SourceUtf32 bleibt fcHigh (else-Default) - harter Compiler-Fehler F2438.
    fkSourceAnsiNonAscii: Result := fcMedium;
    fkSourceUtf16:        Result := fcLow;

    // --- Welle 4: reine FORMATIERUNGS-/Style-Regeln (2026-06-29) ---
    // Definitiv KEINE Bugs (Whitespace, Zeilenlaenge, Keyword-Casing, Deklara-
    // tions-Gruppierung, uses-Reihenfolge). Standen bisher auf fcHigh (else-
    // Default) und waren mit ~75k Funden die groesste Rauschquelle im strict-/
    // hint-Profil. fcLow -> raus aus jedem Confidence>=Medium-Profil, bleiben
    // opt-in. (Kampagne Welle 4: via Confidence ruhigstellen, NICHT haerten.)
    // Bewusst NICHT demotet: BeginEndRequired/WithStatement/NestedRoutine/
    // NilComparison/PublicMemberWithoutDoc (debattierbar, echte Smells) -> die
    // gehoeren in die Profil-Konfiguration, nicht pauschal fcLow.
    fkTooLongLine, fkTrailingWhitespace, fkTabulationCharacter,
    fkLowercaseKeyword, fkDigitGrouping, fkGroupedDeclaration,
    fkConsecutiveSection, fkUnsortedUses: Result := fcLow;

    // --- Pattern-Match-basiert (rein lexikalisch / regex) ---
    fkHardcodedSecret,           // 'password=...'-Heuristik ohne Wert-Check
    fkHardcodedPath,             // C:\...-Pattern, viele OK-Faelle (Tests)
    fkHardcodedString,           // Lokalisierbarer String, kontextabhaengig
    fkTodoComment,               // rein lexikalisch, Triage-Hint
    fkCommentedOutCode,          // Heuristik, Round 13 fixt grossen Teil aber FPs bleiben
    fkDuplicateString,           // Token-Match, viele triviale Hits
    fkDuplicateBlock,            // LOC-Toleranz, FP bei boilerplate
    fkMagicNumber,               // viele konventionell-OK-Faelle (0,1,-1,100)
    fkDebugOutput,               // WriteLn kann legitim sein (CLI-Tools)

    // --- Metric-basiert (Schwellwert-Heuristik) ---
    fkLongMethod,
    fkLongParamList,
    fkLargeClass,
    fkGodClass,
    fkDeepNesting,
    fkCyclomaticComplexity,
    fkCaseStatementSize,

    // --- Style-/Refactor-Praeferenzen ---
    fkBooleanParam,              // legitim bei Toggles
    fkMultipleExit,              // Kontroverses Style-Thema
    fkPublicMemberWithoutDoc,    // viele triviale Methoden brauchen keinen Doc
    fkConstantReturn,            // legitim bei Default-Implementierungen
    fkUnusedParameter,           // legitim bei Interface-Impl
    fkUnusedPrivateMethod,       // RTTI/DFM-Konsumenten unsichtbar

    // --- Schema-Heuristik (DFM ohne vollen Schema-Index) ---
    fkDfmDefaultName,
    fkDfmHardcodedCaption,
    fkDfmFieldTypeMismatch,
    fkDfmTabOrderConflict,
    fkDfmForbiddenClass,
    fkDfmLayerViolation,
    fkDfmGodHandler,
    fkDfmDbInUiForm,

    // --- Security-Heuristik ohne Datenfluss ---
    fkSQLInjection,              // ohne Taint-Tracking, viele Konst-Strings
    fkInsecureCryptoAlgorithm,   // Pattern-Match auf Algo-Namen

    // --- Bug-Detektoren mit FP-Rate ~55-60% + billigem Teil-Guard (Real-World
    //     2026-06-28): aus fcHigh auf fcMedium herabgestuft (bleiben im Default,
    //     aber nicht mehr "hochkonfident"; Rest-FP via CFG/Parser-Followup).
    fkRoutineResultUnassigned,   // SCA121 ~58% (absolute-Result, nested-scope, ifdef)
    fkLockWithoutTryFinally      // SCA109 ~85% pre-guard (call-free-Getter/Setter)
    : Result := fcMedium;

  else
    Result := fcHigh;
  end;
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

function ConfidenceName(C: TFindingConfidence): string;
begin
  case C of
    fcLow:    Result := 'low';
    fcMedium: Result := 'medium';
    fcHigh:   Result := 'high';
  else
    Result := 'high';
  end;
end;

function ParseConfidence(const S: string;
  ADefault: TFindingConfidence): TFindingConfidence;
var
  L : string;
begin
  L := LowerCase(Trim(S));
  if L = 'low'    then Exit(fcLow);
  if L = 'medium' then Exit(fcMedium);
  if L = 'high'   then Exit(fcHigh);
  Result := ADefault;
end;

function IsSonarDelphiKind(K: TFindingKind): Boolean;
begin
  // SonarDelphi-Import lebt zwischen fkGotoStatement (SCA060) und
  // fkMethodName (SCA106). Alles davor (fkMemoryLeak..fkFormatLocaleHint)
  // sowie SCA-native Erweiterungen NACH SCA106 (fkCanBeStrictPrivate ff.)
  // sind nicht SonarDelphi - mit Ausnahme einzelner SonarDelphi-Pendants
  // die nach SCA106 ans Enum-Ende angehaengt wurden (Whitelist-Suffix).
  Result := (Ord(K) >= Ord(fkGotoStatement)) and
            (Ord(K) <= Ord(fkMethodName));
  if Result then Exit;
  case K of
    fkMissingRaise,                // SCA120, SonarDelphi:MissingRaiseCheck
    fkRoutineResultUnassigned,     // SCA121, SonarDelphi:RoutineResultAssignedCheck
    fkReRaiseException,            // SCA122, SonarDelphi:ReRaiseExceptionCheck
    fkCastAndFree,                 // SCA123, SonarDelphi:CastAndFreeCheck
    fkInstanceInvokedConstructor,  // SCA124, SonarDelphi:InstanceInvokedConstructorCheck
    fkInheritedMethodEmpty,        // SCA125, SonarDelphi:InheritedMethodWithNoCodeCheck
    fkNilComparison,               // SCA126, SonarDelphi:NilComparisonCheck
    fkRaisingRawException,         // SCA127, SonarDelphi:RaisingRawExceptionCheck
    fkDateFormatSettings,          // SCA128, SonarDelphi:DateFormatSettingsCheck
    fkUnicodeToAnsiCast,           // SCA129, SonarDelphi:UnicodeToAnsiCastCheck
    fkCharToCharPointerCast,       // SCA130, SonarDelphi:CharacterToCharacterPointerCastCheck
    fkIfThenShortCircuit:          // SCA131, SonarDelphi:IfThenShortCircuitCheck
      Result := True;
  end;
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

procedure CreateEngineConfigLists;
// Erzeugt die Listen-OBJEKTE einmal pro Prozess (initialization) und setzt
// ihre Objekt-Eigenschaften (CaseSensitive/Sorted/Duplicates). Die inhalt-
// liche Basisbefuellung liegt in ResetEngineConfigDefaults - Aufteilung
// 2026-07-04 (Audit Global-State): Erzeugung und Default-WERTE getrennt,
// damit der Default-Satz jederzeit wiederherstellbar ist, ohne die Objekt-
// Identitaet der Listen zu wechseln (haengende Referenzen bleiben gueltig).
// (Vorher: InitDefaultLeakyClasses = Erzeugung + Befuellung in einem.)
begin
  LeakyClasses := TStringList.Create;
  LeakyClasses.CaseSensitive := False;
  LeakyClasses.Sorted        := True;
  LeakyClasses.Duplicates    := dupIgnore;

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

  DetectorMagicTrivials := TStringList.Create;
  DetectorMagicTrivials.CaseSensitive := False;
  DetectorMagicTrivials.Sorted        := True;
  DetectorMagicTrivials.Duplicates    := dupIgnore;

  DetectorFormatFunctions := TStringList.Create;
  DetectorFormatFunctions.CaseSensitive := False;
  DetectorFormatFunctions.Sorted        := True;
  DetectorFormatFunctions.Duplicates    := dupIgnore;

  DfmForbiddenClasses := TStringList.Create;
  DfmForbiddenClasses.CaseSensitive := False;
  DfmForbiddenClasses.Sorted        := True;
  DfmForbiddenClasses.Duplicates    := dupIgnore;
end;

procedure ResetEngineConfigDefaults;
// Kompletter Config-Default-Satz - Doku am Interface-Prototyp (2026-07-04).
// Skalar-Defaults kommen aus den DEF_*-Konstanten (dieselben, die die
// Deklarations-Initializer speisen) -> Reset-Zustand == Prozess-Start-
// Zustand ist per Konstruktion garantiert.
const
  DEFAULT_LEAKY_CLASSES: array of string = [
    // RTL / VCL
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
    'TStreamReader', 'TStreamWriter', 'TZipFile',
    // mORMot2 - die Klassen tauchen in jedem mORMot-Projekt auf und
    // sind owner-managed (keine ARC, kein Auto-Free). Liste basiert auf
    // Real-World-Review aus mORMot2-Crosscheck (TODO 🅲).
    'TJsonWriter', 'TTextWriter', 'TBufferWriter',
    'TRawUtf8List', 'TSynList', 'TSynObjectList',
    'TSqlDBStatement', 'TSqlDBConnection', 'TSqlDBStatementCached',
    'TSynPersistent', 'TSynAutoCreateFields',
    'TDocVariantData', 'TSynDictionary',
    'TOrm', 'TOrmTable', 'TOrmTableJson',
    'TRestServer', 'TRestClientUri',
    'TSynLogFile', 'TSynLog',
    'TSynMonitor', 'TSynLocker',
    'TSynBackgroundThreadMethod'
  ];
  // Default-Trivial-Liste fuer uMagicNumbers.
  DEFAULT_MAGIC_TRIVIALS: array of string = [
    '0', '1', '2', '3', '4', '5', '6', '7', '-1',
    '8', '10', '16', '24', '31', '32', '63', '64', '100', '128', '255', '256',
    '512', '1024'];
  // Default der Format-aehnlichen Funktionen fuer uFormatMismatch.
  // Lower-case (CaseSensitive=False), damit die Detector-Match-Logik
  // direkt darauf operieren kann. mORMot-Funcs bewusst aus (s. Interface).
  DEFAULT_FORMAT_FUNCTIONS: array of string = ['format'];
begin
  // Skalare Detektor-Schwellen.
  DetectorMaxBodyLines         := DEF_MAX_BODY_LINES;
  DetectorMaxStatements        := DEF_MAX_STATEMENTS;
  DetectorMaxParams            := DEF_MAX_PARAMS;
  DetectorMaxNesting           := DEF_MAX_NESTING;
  DetectorMaxCyclomatic        := DEF_MAX_CYCLOMATIC;
  DetectorMinBlockLines        := DEF_MIN_BLOCK_LINES;
  DetectorMaxLocalVars         := DEF_MAX_LOCAL_VARS;
  DetectorMaxChildrenRecursive := DEF_MAX_CHILDREN_RECURSIVE;
  DetectorMaxFileBytes         := DEF_MAX_FILE_BYTES;
  DetectorMaxGodHandlerEvents  := DEF_MAX_GOD_HANDLER_EVENTS;
  DetectorMaxDbInUiFormHint    := DEF_MAX_DB_IN_UI_FORM_HINT;
  DetectorMaxLineLength        := DEF_MAX_LINE_LENGTH;
  DetectorMaxCaseBranches      := DEF_MAX_CASE_BRANCHES;
  UIMaxDisplayedFindings       := DEF_UI_MAX_DISPLAYED_FINDINGS;

  // Filter/Whitelist + Flags.
  DetectorEnabledKinds      := [];   // leer = kein Filter, alle Detektoren
  DetectorMinSeverity       := DEF_DETECTOR_MIN_SEVERITY;
  FindingMinConfidence      := DEF_FINDING_MIN_CONFIDENCE;
  AutoDiscoverCustomClasses := DEF_AUTO_DISCOVER_CLASSES;

  // Konfigurations-Listen: Clear + Basisbefuellung. Assigned-Guards, damit
  // der Aufruf auch vor CreateEngineConfigLists (bzw. nach finalization)
  // nie crasht - dann sind nur die Skalare gesetzt.
  if Assigned(LeakyClasses) then
  begin
    LeakyClasses.Clear;
    LeakyClasses.AddStrings(DEFAULT_LEAKY_CLASSES);
  end;
  if Assigned(LeakyClassExcludes) then
    LeakyClassExcludes.Clear;
  if Assigned(DetectorMagicTrivials) then
  begin
    DetectorMagicTrivials.Clear;
    DetectorMagicTrivials.AddStrings(DEFAULT_MAGIC_TRIVIALS);
  end;
  if Assigned(DetectorFormatFunctions) then
  begin
    DetectorFormatFunctions.Clear;
    DetectorFormatFunctions.AddStrings(DEFAULT_FORMAT_FUNCTIONS);
  end;
  // DfmForbiddenClasses bleibt leer per Default - der Detektor schweigt,
  // bis das Projekt eigene Klassen via analyser.ini eintraegt.
  if Assigned(DfmForbiddenClasses) then
    DfmForbiddenClasses.Clear;
end;

initialization
  // Reihenfolge: erst Listen-Objekte erzeugen, dann Default-Satz befuellen.
  // Netto-Startzustand identisch zum frueheren InitDefaultLeakyClasses
  // (reines Refactoring der Init, 2026-07-04).
  CreateEngineConfigLists;
  ResetEngineConfigDefaults;

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
  if Assigned(DetectorFormatFunctions) then
    FreeAndNil(DetectorFormatFunctions);
  if Assigned(DfmForbiddenClasses) then
    FreeAndNil(DfmForbiddenClasses);

end.

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
  DetectorMaxCyclomatic    : Integer = 10;     // uCyclomaticComplexity (>10 = Fund)
  DetectorMinBlockLines    : Integer = 8;      // uDuplicateBlock
  DetectorMaxFileBytes     : Integer = 5 * 1024 * 1024;  // uStaticAnalyzer2
  DetectorMaxGodHandlerEvents : Integer = 5;             // uDfmGodHandler
  DetectorMaxDbInUiFormHint   : Integer = 3;             // uDfmDataModuleSplitHint
                                                          // (ab N DB-Komponenten auf der Form
                                                          // empfehlen statt N Einzelmeldungen)

  // Trivial-Liste fuer uMagicNumbers - Zahlen die NICHT als Magic-Number
  // gemeldet werden. Default: 0,1,2,-1,10,100. INI-Override moeglich.
  // Stringliste damit Vergleich mit den geparsten Zahlen-Strings ohne
  // Konversion klappt.
  DetectorMagicTrivials    : TStringList = nil;

  // Format-Funktionen die der uFormatMismatch-Detektor pruefen soll.
  // Default: Format, FormatUtf8, FormatString. Alle drei haben dieselbe
  // %-Platzhalter-Semantik wie Delphi-Format - typisch in mORMot2-Code
  // wo FormatUtf8 als RawUtf8-Variante haeufig vorkommt. INI-Override:
  // [Detectors] FormatFunctions=Format,FormatUtf8,FormatString,_fmt
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
    fkCanBePrivate,              // Public-Member wird nur in eigener Unit
                                 // referenziert -> private moeglich (Cross-Unit).
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
    fkConsecutiveVisibility      // Dieselbe Visibility-Section zweimal in
                                 // einer Klasse (SonarDelphi:
                                 // ConsecutiveVisibilitySection).
  );

  // Set-Typ fuer Detector-Filter (Profile/EnabledKinds). Mit 43 Werten
  // weit unter dem 256-Element-Limit eines Delphi-Sets.
  TFindingKinds = set of TFindingKind;

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
    (Name: 'CanBePrivate';               FindingType: ftCodeSmell;    DefaultSeverity: lsHint),    // fkCanBePrivate
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
    (Name: 'ConsecutiveVisibility';      FindingType: ftCodeSmell;    DefaultSeverity: lsHint)     // fkConsecutiveVisibility
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
  DetectorMinSeverity  : TLeakSeverity = lsHint;

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

function KindDefaultSeverity(K: TFindingKind): TLeakSeverity;
begin
  Result := KIND_META[K].DefaultSeverity;
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
  DetectorMagicTrivials.AddStrings(['0', '1', '2', '3', '4', '5', '6', '7', '-1',
    '8', '10', '16', '24', '31', '32', '63', '64', '100', '128', '255', '256',
    '512', '1024']);

  // Default-Liste der Format-aehnlichen Funktionen fuer uFormatMismatch.
  // Lower-case (CaseSensitive=False), damit die Detector-Match-Logik
  // direkt darauf operieren kann.
  DetectorFormatFunctions := TStringList.Create;
  DetectorFormatFunctions.CaseSensitive := False;
  DetectorFormatFunctions.Sorted        := True;
  DetectorFormatFunctions.Duplicates    := dupIgnore;
  DetectorFormatFunctions.AddStrings(['format', 'formatutf8', 'formatstring']);

  // DfmForbiddenClasses bleibt leer per Default - der Detektor schweigt,
  // bis das Projekt eigene Klassen via analyser.ini eintraegt.
  DfmForbiddenClasses := TStringList.Create;
  DfmForbiddenClasses.CaseSensitive := False;
  DfmForbiddenClasses.Sorted        := True;
  DfmForbiddenClasses.Duplicates    := dupIgnore;
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
  if Assigned(DetectorFormatFunctions) then
    FreeAndNil(DetectorFormatFunctions);
  if Assigned(DfmForbiddenClasses) then
    FreeAndNil(DfmForbiddenClasses);

end.

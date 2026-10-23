program reDelphix.Test;

// DUnitX-Testprojekt des Moduls reDelphix (Nico, 2026-10-05: "erstelle ein
// reDelphix.Test Project; Tests fuer alle Varianten des Detektors SCA044").
//
// Prueft den ToolsAPI-freien Teil des Moduls gegen den ECHTEN Core:
//   * uTestRdxRecipes  - Literal-Codec, Format()-Bau, Query-Objekt,
//                        Scope-Tabelle (reine Textlogik)
//   * uTestRdxBench    - Selbstpruefung des FPC-Pruefstands: Literale
//                        bleiben unangepasst (Review R6-03)
//   * uTestRdxSca044   - Ende zu Ende: Parser, Detektor SCA044,
//                        TSourcePlaces, Rezept-Laeufer - je Variante eine
//                        Temp-Datei, derselbe Weg wie im IDE-Package
//   * uTestRdxActionRing - Ring der Aktionsobjekte des Anbieters (Besitz,
//                        Chargen, Grenzen)
//   * uTestRdxBufferMath - Zeile/Spalte -> Byte im UTF-8-Puffer, Pruefung
//                        aller Ersetzungen, Spaltengrenze, Textwahl
//   * uTestRdxSuppress - Unterdrueck-Marker setzen und entfernen
//   * uTestRdxSuppressTargets - Ziele eines Markers wie im Core (Review
//                        R1-01/R1-03): Entfernen und Setzen ueber Kommentarzeilen
//   * uTestRdxSuppressCore - dieselben Hilfen gegen den ECHTEN Core
//                        (TSuppression): Drift-Waechter (Pruefer B1-FA)
//   * uTestRdxSimpleFixes - Editorhilfen SCA074/SCA075/SCA085/SCA087/
//                        SCA139 auf Text, ohne Parser
//   * uTestRdxStructFixes - Editorhilfen SCA007/SCA168 (uses-Eintrag,
//                        case-else) auf Text, ohne Parser
//   * uTestRdxBlockFixes - Editorhilfe SCA101/SCA099 (begin..end) auf
//                        Text, ohne Parser
//   * uTestRdxLineFixes - Editorhilfen SCA082/SCA071/SCA088/SCA123 (eine
//                        Zeile) auf Text, ohne Parser
//   * uTestRdxRaiseFixes - Editorhilfen SCA020/SCA120/SCA122 (Ausnahmen,
//                        leerer Rumpf) auf Text, ohne Parser
//   * uTestRdxDeclFixes - Editorhilfen SCA117/SCA197/SCA149 (Deklarationen)
//                        auf Text, ohne Parser
//   * uTestRdxFlowFixes - Quick-Fixes SCA098/SCA080/SCA047 (ganze
//                        Anweisungen) auf Text, ohne Parser
//   * uTestRdxRoutineFixes - Quick-Fix SCA164 (ungenutzte Routine) und
//                        die Bausteine Routinengrenzen und Decl/Impl-
//                        Finder auf Text, ohne Parser
//   * uTestRdxMethodFixes - Quick-Fix SCA147 (ungenutzte private
//                        Methode) auf Text, ohne Parser
//   * uTestRdxCleanupFixes - Quick-Fixes SCA070/SCA053 (Aufraeumen,
//                        Charge H3a) und CutEdit auf Text, ohne Parser
//   * uTestRdxCleanupScope - SCA053-Sperren der Charge H3c (Include,
//                        Makro, asm, Klammer) auf Text, ohne Parser
//   * uTestRdxTryFixes - Quick-Fixes try/finally SCA009/SCA001 (Charge H4,
//                        Baustein B5) auf Text, ohne Parser
//   * uTestRdxTryLocks - dieselben an Sperren und Puffern SCA109/SCA153/
//                        SCA156 auf Text, ohne Parser
//   * uTestRdxResultFixes - Quick-Fixes SCA121/SCA196 (Charge H5, Result
//                        initialisieren) auf Text, ohne Parser
//   * uTestRdxInheritedFixes - Quick-Fixes SCA096/SCA097 (inherited in
//                        Konstruktor/Destruktor) auf Text, ohne Parser
//   * uTestRdxSqlTemplate - SQL-Vorlage zu SCA003 (Charge S1): nur Werte
//                        werden Parameter, DDL/Namen abgelehnt, Konstanten
//                        im Text, FireDAC-ExecSQL, Namen aus dem Operanden
//   * uTestRdxSqlFacts - ihre Nachweise am Quelltext: Konstante, FireDAC-
//                        Verbindung, Parameternamen, Platzhalter (SCA199)
//   * uTestRdxSqlGuards - die Nacharbeit des Gegen-Reviews (Charge SQc):
//                        Inline-Variable, Sichtbarkeit, Name der Konstante
//                        bleibt, DDL-Sperre, Kette Q.SQL.Add, ADO, LIMIT, '?'
//   * uTestRdxResultGuards - die Sperren und Werte aus dem Gegen-Review H5
//                        (Charge H5c: Delegation, abstrakt/objfpc, Exit auf
//                        jeder Tiefe, Vorfahrenliste, Literal statt
//                        Default(T), Typ der Unit)
//   * uTestRdxResultFixesDetector - die Hilfen der Charge H5 gegen die
//                        echten Detektoren (Fund -> Hilfe -> Fund weg)
//   * uTestRdxMagicFix - Quick-Fix SCA014 (Charge Q14, Lokale Konstante
//                        einfuehren) auf Text, ohne Parser: Ziel aus dem
//                        Fund, Name, Spuren alter Compiler, FPC
//   * uTestRdxMagicGuards - die Nacharbeit des Gegen-Reviews (Charge
//                        SQc): alte Delphi-Projekte neben der Unit,
//                        Netzpfad, Hauptblock eines Programms
//   * uTestRdxMagicFixDetector - dieselbe Hilfe gegen den echten
//                        Detektor uMagicNumbers (Fund -> Hilfe -> Fund weg)
//   * uTestRdxTryGates - die Sperren und Formen aus dem Gegen-Review H4
//                        (Charge H4c: Weitergabe ohne Ausstieg, andere
//                        Schreibweisen, 'End :=', Einrueckung ...)
//   * uTestRdxTryFixesDetector - die try/finally-Hilfen gegen die echten
//                        Detektoren (Fund -> Hilfe -> Fund weg)
//   * uTestRdxCleanupDetector - dieselben Hilfen gegen die echten
//                        Detektoren uCommentedOutCode/uUnusedLocal
//   * uTestRdxExprFixes - Editorhilfen SCA066/SCA072/SCA084 (uQuickFix-
//                        Umzug) auf Text, ohne Parser
//   * uTestRdxNilFix   - Editorhilfe SCA126 auf Text, ohne Parser
//   * uTestRdxSimpleFixesDetector - dieselben Hilfen gegen den echten
//                        Detektor, Katalog-Beispiele bad -> good
//   * uTestRdxRoutineFixesDetector - SCA164/SCA147 gegen die echten
//                        Detektoren (Fund -> Hilfe -> Fund weg)
//   * uTestRdxDetectorKit - gemeinsame Helfer der Detektor-Rundlaeufe
//                        (keine Fixture; Charge H3c)
//   * uTestRdxTextKit  - gemeinsame Helfer der Testunits: Join, Apply,
//                        LineOf, WriteText, Temp-Verzeichnisse (keine
//                        Fixture, FPC-tauglich; Review R6-08)
//   * uTestRdxCodeMap  - Code-Sicht (uRdxCodeMap) gegen ScanCodeLine des
//                        Cores (Drift-Waechter), StartsInside
//   * uTestRdxQualifyUses - Planung von "uses: X -> Scope.X" (QualifyUses)
//   * uTestRdxProjectUnits - Index der Projekt-Units fuer "uses: X ->
//                        Scope.X" (TRdxProjectUnits, Review R1-02)
//   * uTestRdxPaths    - die eine Netzpfad-Regel (uRdxPaths, Charge
//                        B2S-a): UNC, Win32-Namensraum, Netzlaufwerk ueber
//                        die Naht; SCA164/SCA014 auf '\\?\C:\..'
//   * uTestRdxBlocks   - Bausteine in uRdxBlocks (Charge B2S-b): die Suche
//                        nach der Routine um eine Stelle (HeadBefore) mit
//                        den Politiken von SCA009 und SCA196,
//                        MemberHeads und der Index der Klassenkoepfe
//                        (SCA096), TypeHasBody
//   * uTestRdxFixTable - die Tabelle der einfachen Hilfen (uRdxFixTable):
//                        jede Zeile mit Planer, Hinweis und Menuetext
//   * uTestRdxIntroPlan - Code-Aktion "Lokale Variable einfuehren": das
//                        Literal am Caret, Deklaration, Spalten (Textlogik)
//   * uTestRdxIntroRefuse - dieselbe Aktion: Zweig ohne begin, Ablehnungen
//   * uTestRdxIntroGuards - dieselbe Aktion: Schutzregeln aus dem Korpus-A/B,
//                        Zusammenhang ueber Zeilen, Ende des Sync-Blocks
//   * uTestRdxIntroEdits - dieselbe Aktion: Ersetzungen des Writers (C1h)
//                        Ende zu Ende auf UTF-8-Pufferbytes
//   * uTestRdxIntroContext - dieselbe Aktion: Zusammenhang ueber Zeilen
//                        (mehrzeilige Strings, asm, initialization, FPC-
//                        Weiche, Direktiven, Kommentargrenzen)
//   * uTestRdxText     - die Sprache der reDelphix-Texte (uRdxText,
//                        Entscheid E29): Override, redelphix.ini (Vorlage,
//                        auto/fest), Sprache der SCA, analyser.ini
//   * uTestRdxTextMsgs - die gemeinsamen Texte aus uRdxText (Charge C1):
//                        je Funktion en/de/fr, de = bisheriger Wortlaut
//   Nacharbeit des Code-Reviews (Charge FB):
//   * uTestRdxFormatGuards - Format()-Umformung: kein Literal ueber 255
//                        Elemente (R2-02), kein Zeiger am Kettenanfang
//   * uTestRdxFreeTypes - Typ-Sperre von SCA085/SCA139 auf Text (Zeiger-
//                        typen und Aliasse der Unit, R2-01/R3-01)
//   * uTestRdxSqlBinds - SQL-Vorlage: Literal-Laenge (R2-02), geerbtes
//                        Member vor der Unit-Konstante (R2-05)
//   * uTestRdxFreeGatesDetector - die Sperren aus Laeufer und Tabelle
//                        gegen die echten Detektoren (TRdxFixTable.FixFor)
//   Einfache Hilfen der Chargen Q und R (je Planer-Unit uRdx<Name>Fix eine
//   Testunit: Planer auf Text, Adapter der Tabelle, Rundlauf mit dem
//   echten Detektor; Einzelheiten im Kopf jeder Unit):
//   * uTestRdxHttpsFix          - SCA115 'http://' -> 'https://'
//   * uTestRdxParensFix         - SCA094 '((X))' -> '(X)'
//   * uTestRdxAttrGapFix        - SCA183 Leerzeilen nach einem Attribut
//   * uTestRdxTwiceInheritedFix - SCA093 zweiter gleicher inherited-Aufruf
//                                 entfaellt
//   * uTestRdxNativeIntFix      - SCA161 Integer(P1) - Integer(P2) ->
//                                 NativeInt
//   * uTestRdxEmptyFinallyFix   - SCA083 try..finally ohne Aufraeum-Code
//                                 entfaellt
//   * uTestRdxForRangeFix       - SCA046 'to' -> 'downto' bzw. Grenzen
//                                 tauschen
//   * uTestRdxTabsFix           - SCA061 Tabs -> Leerzeichen
//   * uTestRdxTrailingBlanksFix - SCA063 Leerraum am Zeilenende
//   * uTestRdxKeywordCaseFix    - SCA064 Schluesselwort klein
//   * uTestRdxEmptyExceptFix    - SCA002 leerer except-Block -> 'raise;'
//   * uTestRdxEmptyOnHandlerFix - SCA159 leerer on-Handler -> 'raise;'
//   * uTestRdxEmptyBlockFix     - SCA077 'with X.Add(T) do begin end;' ->
//                                 'X.Add(T);'
//   * uTestRdxNoSonarFix        - SCA065 '// NOSONAR' -> Marker des
//                                 Analysers ueber der Zeile
//   * uTestRdxTrailingCommaFix  - SCA068 Komma vor ')'
//   * uTestRdxGroupedDeclFix    - SCA076 'A, B: T;' -> eine Zeile je Name
//   * uTestRdxIgnoreReasonFix   - SCA179 '[Ignore]' mit Grund
//   * uTestRdxAttrDuplicateFix  - SCA180 doppeltes Attribut loeschen
//   * uTestRdxCategoryArgFix    - SCA181 '[Category]' mit Argument
//   * uTestRdxGotoExitFix       - SCA060 goto zum Routinen-Ende -> Exit
//   * uTestRdxFormatSettingsFix - SCA128 ', FormatSettings' bzw.
//                                 ', TFormatSettings.Invariant'
//   * uTestRdxFormatLocaleFix   - SCA059 Format mit drittem Argument
//                                 FormatSettings bzw. Invariant
//   * uTestRdxMethodNameFix     - SCA106 Methodenname gross in
//                                 Deklaration und Implementierung
//   * uTestRdxIntegerOverflowFix - SCA137 'A * B' -> 'Int64(A) * B'
//   * uTestRdxBidiOverrideFix   - SCA188 Bidi-Steuerzeichen loeschen
//                                 bzw. als #$-Code
//   * uTestRdxInvisibleCharFix  - SCA192 unsichtbare Zeichen loeschen
//                                 bzw. als #$-Code
//   * uTestRdxThreadResumeFix   - SCA113 Resume -> Start nach
//                                 Create(True)
//   * uTestRdxInsecureRandomFix - SCA167 Randomize in die
//                                 initialization
//   * uTestRdxFloatEqualityFix  - SCA144 '=' -> SameValue/IsZero
//   * uTestRdxMoveSizeFix       - SCA154 SizeOf(PTyp) -> SizeOf(Typ)
//   * uTestRdxDebugOutputFix    - SCA017 Ausgabe in {$IFDEF DEBUG}
//                                 bzw. loeschen
//   * uTestRdxDeadCodeFix       - SCA011 toten Code hinter Exit/raise
//                                 loeschen
//   * uTestRdxIfThenFix         - SCA131 IfThen -> if..then..else
//   * uTestRdxAssertSideEffectFix - SCA169 'Assert(C)' ->
//                                   'if not (C) then Assert(False, ..)'
//   * uTestRdxUnusedParameterFix - SCA054 Parameter -> _Parameter in
//                                  Deklaration und Implementierung
//   * uTestRdxConstStringParameterFix - SCA170 const vor den string-
//                                       Parameter
//   * uTestRdxExceptionNameFix  - SCA118 MyError -> EMyError
//   * uTestRdxLocalConstantNameFix - SCA119 lokale Konstante in
//                                    UPPER_SNAKE_CASE
//   * uTestRdxDigitGroupingFix  - SCA069 1800000 -> 1_800_000
//   * uTestRdxConsecutiveSectionFix - SCA079 doppeltes const/var
//                                     zusammenlegen
//   * uTestRdxAvoidOutFix       - SCA086 out -> var
//   * uTestRdxRawExceptionFix   - SCA127 Exception -> EArgumentException
//                                 bzw. EInvalidOpException
//   * uTestRdxClassMethodFix    - SCA148 Methode -> class ... static
//   * uTestRdxAlwaysTrueFix     - SCA150 immer wahres if aufloesen
//   * uTestRdxObjectListFix     - SCA174 TList<T> -> TObjectList<T>
//   * uTestRdxHomoglyphFix      - SCA193 Homoglyph-Bezeichner in ASCII
//   * uTestRdxParamNameFix      - SCA199 Parametername mit Tippfehler ->
//                                 Platzhalter des SQL
//   * uTestRdxDeepNestingFix    - SCA018 letztes if -> Waechter-Klausel
//   * uTestRdxLookupHoistFix    - SCA111/SCA112 ParamByName/FieldByName
//                                 vor die Schleife
//   * uTestRdxLoopBoundFix      - SCA203 Grenze der for-Schleife auf den
//                                 letzten Index
//   * uTestRdxInheritedEmptyFix - SCA125 leeres Override loeschen
//                                 (Deklaration und Implementierung)
//
// SPRACHE: der Hauptblock setzt die reDelphix-Texte fuer ALLE Tests auf
// Deutsch (SetRdxLanguageOverride('de'), wie der FPC-Pruefstand) - die
// Erwartungen sind deutsch bzw. die deutschen Menuetexte aus i18n/de.po,
// und mit Override liest und schreibt uRdxText keine redelphix.ini (kein
// Testlauf fasst %APPDATA% an).
//
// Engine-Units kommen ueber den Suchpfad aus ..\..\SCA.Engine\sources
// (wie StaticCodeAnalyserForm\tests\TestProject), die Modul-Units aus
// ..\source. Kein ToolsAPI: uRdxEditor und uRdxProvider bleiben draussen.
//
// LAUF: Debug und Release definieren TESTINSIGHT - GUI-Subsystem,
// TestInsight.DUnitX.RunRegisteredTests, Exit-Code immer 0 (TestInsight
// verwirft das Ergebnis). Einen auswertbaren Exit-Code liefert nur die
// Konfiguration CI (ohne TESTINSIGHT, mit CI): Console-Subsystem,
// Konsolen- und NUnit-Logger, ExitCode 1 bei einem roten Test oder einer
// Ausnahme im Runner, keine Pause am Ende (Review R6-09 - bis dahin galt
// TESTINSIGHT fuer alle Konfigurationen, der Zweig unten wurde nie
// uebersetzt). Beide Runner werten einen Test ohne Assert als rot
// (FailsOnNoAsserts wie TestInsight; ebenso der FPC-Pruefstand).
{$IFNDEF TESTINSIGHT}
{$APPTYPE CONSOLE}
{$ENDIF}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  {$IFDEF TESTINSIGHT}
  TestInsight.DUnitX,
  {$ELSE}
  DUnitX.Loggers.Console,
  DUnitX.Loggers.XML.NUnit,
  {$ENDIF }
  DUnitX.TestFramework,
  uRdxText in '..\source\uRdxText.pas',
  uRdxRecipes in '..\source\uRdxRecipes.pas',
  uRdxPaths in '..\source\uRdxPaths.pas',
  uRdxScopeTable in '..\source\uRdxScopeTable.pas',
  uRdxBufferMath in '..\source\uRdxBufferMath.pas',
  uRdxCodeMap in '..\source\uRdxCodeMap.pas',
  uRdxBlocks in '..\source\uRdxBlocks.pas',
  uRdxSuppress in '..\source\uRdxSuppress.pas',
  uRdxRtlTypes in '..\source\uRdxRtlTypes.pas',
  uRdxTypeProof in '..\source\uRdxTypeProof.pas',
  uRdxSimpleFixes in '..\source\uRdxSimpleFixes.pas',
  uRdxStructFixes in '..\source\uRdxStructFixes.pas',
  uRdxLineFixes in '..\source\uRdxLineFixes.pas',
  uRdxRaiseFixes in '..\source\uRdxRaiseFixes.pas',
  uRdxDeclFixes in '..\source\uRdxDeclFixes.pas',
  uRdxFlowFixes in '..\source\uRdxFlowFixes.pas',
  uRdxRoutineFixes in '..\source\uRdxRoutineFixes.pas',
  uRdxCleanupFixes in '..\source\uRdxCleanupFixes.pas',
  uRdxTryFixes in '..\source\uRdxTryFixes.pas',
  uRdxTrySpan in '..\source\uRdxTrySpan.pas',
  uRdxHandOver in '..\source\uRdxHandOver.pas',
  uRdxCompilerTraces in '..\source\uRdxCompilerTraces.pas',
  uRdxResultFixes in '..\source\uRdxResultFixes.pas',
  uRdxInheritedFixes in '..\source\uRdxInheritedFixes.pas',
  uRdxSqlTemplate in '..\source\uRdxSqlTemplate.pas',
  uRdxSqlFacts in '..\source\uRdxSqlFacts.pas',
  uRdxRecipeRunner in '..\source\uRdxRecipeRunner.pas',
  uRdxFixRunner in '..\source\uRdxFixRunner.pas',
  uRdxFixTable in '..\source\uRdxFixTable.pas',
  uRdxIntroPlan in '..\source\uRdxIntroPlan.pas',
  uRdxIntroEdits in '..\source\uRdxIntroEdits.pas',
  uRdxMagicFixes in '..\source\uRdxMagicFixes.pas',
  uRdxHttpsFix in '..\source\uRdxHttpsFix.pas',
  uRdxParensFix in '..\source\uRdxParensFix.pas',
  uRdxAttrGapFix in '..\source\uRdxAttrGapFix.pas',
  uRdxTwiceInheritedFix in '..\source\uRdxTwiceInheritedFix.pas',
  uRdxNativeIntFix in '..\source\uRdxNativeIntFix.pas',
  uRdxEmptyFinallyFix in '..\source\uRdxEmptyFinallyFix.pas',
  uRdxForRangeFix in '..\source\uRdxForRangeFix.pas',
  uRdxTabsFix in '..\source\uRdxTabsFix.pas',
  uRdxTrailingBlanksFix in '..\source\uRdxTrailingBlanksFix.pas',
  uRdxKeywordCaseFix in '..\source\uRdxKeywordCaseFix.pas',
  uRdxEmptyExceptFix in '..\source\uRdxEmptyExceptFix.pas',
  uRdxEmptyOnHandlerFix in '..\source\uRdxEmptyOnHandlerFix.pas',
  uRdxEmptyBlockFix in '..\source\uRdxEmptyBlockFix.pas',
  uRdxNoSonarFix in '..\source\uRdxNoSonarFix.pas',
  uRdxTrailingCommaFix in '..\source\uRdxTrailingCommaFix.pas',
  uRdxGroupedDeclFix in '..\source\uRdxGroupedDeclFix.pas',
  uRdxIgnoreReasonFix in '..\source\uRdxIgnoreReasonFix.pas',
  uRdxAttrDuplicateFix in '..\source\uRdxAttrDuplicateFix.pas',
  uRdxCategoryArgFix in '..\source\uRdxCategoryArgFix.pas',
  uRdxGotoExitFix in '..\source\uRdxGotoExitFix.pas',
  uRdxFormatSettingsFix in '..\source\uRdxFormatSettingsFix.pas',
  uRdxMethodNameFix in '..\source\uRdxMethodNameFix.pas',
  uRdxIntegerOverflowFix in '..\source\uRdxIntegerOverflowFix.pas',
  uRdxCharEscapeFix in '..\source\uRdxCharEscapeFix.pas',
  uRdxThreadResumeFix in '..\source\uRdxThreadResumeFix.pas',
  uRdxInsecureRandomFix in '..\source\uRdxInsecureRandomFix.pas',
  uRdxFloatEqualityFix in '..\source\uRdxFloatEqualityFix.pas',
  uRdxMoveSizeFix in '..\source\uRdxMoveSizeFix.pas',
  uRdxDebugOutputFix in '..\source\uRdxDebugOutputFix.pas',
  uRdxDeadCodeFix in '..\source\uRdxDeadCodeFix.pas',
  uRdxIfThenFix in '..\source\uRdxIfThenFix.pas',
  uRdxAssertSideEffectFix in '..\source\uRdxAssertSideEffectFix.pas',
  uRdxUnusedParameterFix in '..\source\uRdxUnusedParameterFix.pas',
  uRdxConstStringParameterFix in '..\source\uRdxConstStringParameterFix.pas',
  uRdxExceptionNameFix in '..\source\uRdxExceptionNameFix.pas',
  uRdxLocalConstantNameFix in '..\source\uRdxLocalConstantNameFix.pas',
  uRdxDigitGroupingFix in '..\source\uRdxDigitGroupingFix.pas',
  uRdxConsecutiveSectionFix in '..\source\uRdxConsecutiveSectionFix.pas',
  uRdxAvoidOutFix in '..\source\uRdxAvoidOutFix.pas',
  uRdxRawExceptionFix in '..\source\uRdxRawExceptionFix.pas',
  uRdxClassMethodFix in '..\source\uRdxClassMethodFix.pas',
  uRdxAlwaysTrueFix in '..\source\uRdxAlwaysTrueFix.pas',
  uRdxObjectListFix in '..\source\uRdxObjectListFix.pas',
  uRdxHomoglyphFix in '..\source\uRdxHomoglyphFix.pas',
  uRdxParamNameFix in '..\source\uRdxParamNameFix.pas',
  uRdxDeepNestingFix in '..\source\uRdxDeepNestingFix.pas',
  uRdxLookupHoistFix in '..\source\uRdxLookupHoistFix.pas',
  uRdxLoopBoundFix in '..\source\uRdxLoopBoundFix.pas',
  uRdxInheritedEmptyFix in '..\source\uRdxInheritedEmptyFix.pas',
  uTestRdxRecipes in 'uTestRdxRecipes.pas',
  uTestRdxBench in 'uTestRdxBench.pas',
  uTestRdxSca044 in 'uTestRdxSca044.pas',
  uTestRdxFormatGuards in 'uTestRdxFormatGuards.pas',
  uTestRdxActionRing in 'uTestRdxActionRing.pas',
  uTestRdxBufferMath in 'uTestRdxBufferMath.pas',
  uTestRdxSuppress in 'uTestRdxSuppress.pas',
  uTestRdxSuppressTargets in 'uTestRdxSuppressTargets.pas',
  uTestRdxSuppressCore in 'uTestRdxSuppressCore.pas',
  uTestRdxSimpleFixes in 'uTestRdxSimpleFixes.pas',
  uTestRdxFreeTypes in 'uTestRdxFreeTypes.pas',
  uTestRdxExprFixes in 'uTestRdxExprFixes.pas',
  uTestRdxStructFixes in 'uTestRdxStructFixes.pas',
  uTestRdxBlockFixes in 'uTestRdxBlockFixes.pas',
  uTestRdxLineFixes in 'uTestRdxLineFixes.pas',
  uTestRdxRaiseFixes in 'uTestRdxRaiseFixes.pas',
  uTestRdxDeclFixes in 'uTestRdxDeclFixes.pas',
  uTestRdxFlowFixes in 'uTestRdxFlowFixes.pas',
  uTestRdxRoutineFixes in 'uTestRdxRoutineFixes.pas',
  uTestRdxMethodFixes in 'uTestRdxMethodFixes.pas',
  uTestRdxCleanupFixes in 'uTestRdxCleanupFixes.pas',
  uTestRdxCleanupScope in 'uTestRdxCleanupScope.pas',
  uTestRdxCleanupDetector in 'uTestRdxCleanupDetector.pas',
  uTestRdxTryFixes in 'uTestRdxTryFixes.pas',
  uTestRdxTryLocks in 'uTestRdxTryLocks.pas',
  uTestRdxTryGates in 'uTestRdxTryGates.pas',
  uTestRdxTryFixesDetector in 'uTestRdxTryFixesDetector.pas',
  uTestRdxResultFixes in 'uTestRdxResultFixes.pas',
  uTestRdxInheritedFixes in 'uTestRdxInheritedFixes.pas',
  uTestRdxResultGuards in 'uTestRdxResultGuards.pas',
  uTestRdxSqlTemplate in 'uTestRdxSqlTemplate.pas',
  uTestRdxSqlFacts in 'uTestRdxSqlFacts.pas',
  uTestRdxSqlGuards in 'uTestRdxSqlGuards.pas',
  uTestRdxSqlBinds in 'uTestRdxSqlBinds.pas',
  uTestRdxResultFixesDetector in 'uTestRdxResultFixesDetector.pas',
  uTestRdxMagicFix in 'uTestRdxMagicFix.pas',
  uTestRdxHttpsFix in 'uTestRdxHttpsFix.pas',
  uTestRdxParensFix in 'uTestRdxParensFix.pas',
  uTestRdxAttrGapFix in 'uTestRdxAttrGapFix.pas',
  uTestRdxTwiceInheritedFix in 'uTestRdxTwiceInheritedFix.pas',
  uTestRdxNativeIntFix in 'uTestRdxNativeIntFix.pas',
  uTestRdxEmptyFinallyFix in 'uTestRdxEmptyFinallyFix.pas',
  uTestRdxForRangeFix in 'uTestRdxForRangeFix.pas',
  uTestRdxTabsFix in 'uTestRdxTabsFix.pas',
  uTestRdxTrailingBlanksFix in 'uTestRdxTrailingBlanksFix.pas',
  uTestRdxKeywordCaseFix in 'uTestRdxKeywordCaseFix.pas',
  uTestRdxEmptyExceptFix in 'uTestRdxEmptyExceptFix.pas',
  uTestRdxEmptyOnHandlerFix in 'uTestRdxEmptyOnHandlerFix.pas',
  uTestRdxEmptyBlockFix in 'uTestRdxEmptyBlockFix.pas',
  uTestRdxNoSonarFix in 'uTestRdxNoSonarFix.pas',
  uTestRdxTrailingCommaFix in 'uTestRdxTrailingCommaFix.pas',
  uTestRdxGroupedDeclFix in 'uTestRdxGroupedDeclFix.pas',
  uTestRdxIgnoreReasonFix in 'uTestRdxIgnoreReasonFix.pas',
  uTestRdxAttrDuplicateFix in 'uTestRdxAttrDuplicateFix.pas',
  uTestRdxCategoryArgFix in 'uTestRdxCategoryArgFix.pas',
  uTestRdxGotoExitFix in 'uTestRdxGotoExitFix.pas',
  uTestRdxFormatSettingsFix in 'uTestRdxFormatSettingsFix.pas',
  uTestRdxFormatLocaleFix in 'uTestRdxFormatLocaleFix.pas',
  uTestRdxMethodNameFix in 'uTestRdxMethodNameFix.pas',
  uTestRdxIntegerOverflowFix in 'uTestRdxIntegerOverflowFix.pas',
  uTestRdxBidiOverrideFix in 'uTestRdxBidiOverrideFix.pas',
  uTestRdxInvisibleCharFix in 'uTestRdxInvisibleCharFix.pas',
  uTestRdxThreadResumeFix in 'uTestRdxThreadResumeFix.pas',
  uTestRdxInsecureRandomFix in 'uTestRdxInsecureRandomFix.pas',
  uTestRdxFloatEqualityFix in 'uTestRdxFloatEqualityFix.pas',
  uTestRdxMoveSizeFix in 'uTestRdxMoveSizeFix.pas',
  uTestRdxDebugOutputFix in 'uTestRdxDebugOutputFix.pas',
  uTestRdxDeadCodeFix in 'uTestRdxDeadCodeFix.pas',
  uTestRdxIfThenFix in 'uTestRdxIfThenFix.pas',
  uTestRdxAssertSideEffectFix in 'uTestRdxAssertSideEffectFix.pas',
  uTestRdxUnusedParameterFix in 'uTestRdxUnusedParameterFix.pas',
  uTestRdxConstStringParameterFix in 'uTestRdxConstStringParameterFix.pas',
  uTestRdxExceptionNameFix in 'uTestRdxExceptionNameFix.pas',
  uTestRdxLocalConstantNameFix in 'uTestRdxLocalConstantNameFix.pas',
  uTestRdxDigitGroupingFix in 'uTestRdxDigitGroupingFix.pas',
  uTestRdxConsecutiveSectionFix in 'uTestRdxConsecutiveSectionFix.pas',
  uTestRdxAvoidOutFix in 'uTestRdxAvoidOutFix.pas',
  uTestRdxRawExceptionFix in 'uTestRdxRawExceptionFix.pas',
  uTestRdxClassMethodFix in 'uTestRdxClassMethodFix.pas',
  uTestRdxAlwaysTrueFix in 'uTestRdxAlwaysTrueFix.pas',
  uTestRdxObjectListFix in 'uTestRdxObjectListFix.pas',
  uTestRdxHomoglyphFix in 'uTestRdxHomoglyphFix.pas',
  uTestRdxParamNameFix in 'uTestRdxParamNameFix.pas',
  uTestRdxDeepNestingFix in 'uTestRdxDeepNestingFix.pas',
  uTestRdxLookupHoistFix in 'uTestRdxLookupHoistFix.pas',
  uTestRdxLoopBoundFix in 'uTestRdxLoopBoundFix.pas',
  uTestRdxInheritedEmptyFix in 'uTestRdxInheritedEmptyFix.pas',
  uTestRdxMagicGuards in 'uTestRdxMagicGuards.pas',
  uTestRdxMagicFixDetector in 'uTestRdxMagicFixDetector.pas',
  uTestRdxNilFix in 'uTestRdxNilFix.pas',
  uTestRdxSimpleFixesDetector in 'uTestRdxSimpleFixesDetector.pas',
  uTestRdxRoutineFixesDetector in 'uTestRdxRoutineFixesDetector.pas',
  uTestRdxFreeGatesDetector in 'uTestRdxFreeGatesDetector.pas',
  uTestRdxDetectorKit in 'uTestRdxDetectorKit.pas',
  uTestRdxTextKit in 'uTestRdxTextKit.pas',
  uTestRdxCodeMap in 'uTestRdxCodeMap.pas',
  uTestRdxQualifyUses in 'uTestRdxQualifyUses.pas',
  uTestRdxProjectUnits in 'uTestRdxProjectUnits.pas',
  uTestRdxPaths in 'uTestRdxPaths.pas',
  uTestRdxBlocks in 'uTestRdxBlocks.pas',
  uTestRdxFixTable in 'uTestRdxFixTable.pas',
  uTestRdxIntroPlan in 'uTestRdxIntroPlan.pas',
  uTestRdxIntroRefuse in 'uTestRdxIntroRefuse.pas',
  uTestRdxIntroGuards in 'uTestRdxIntroGuards.pas',
  uTestRdxIntroEdits in 'uTestRdxIntroEdits.pas',
  uTestRdxIntroContext in 'uTestRdxIntroContext.pas',
  uTestRdxTextMsgs in 'uTestRdxTextMsgs.pas',
  uTestRdxText in 'uTestRdxText.pas';

{ keep comment here to protect the following conditional from being removed by the IDE when adding a unit }
{$IFNDEF TESTINSIGHT}

var
  runner: ITestRunner;
  results: IRunResults;
  logger: ITestLogger;
  nunitLogger: ITestLogger;
{$ENDIF}

begin
  // Deutsch fuer alle Tests (s. Kopf, SPRACHE) - vor jedem Lauf, auch
  // unter TestInsight.
  SetRdxLanguageOverride('de');
{$IFDEF TESTINSIGHT}
  TestInsight.DUnitX.RunRegisteredTests;
  Halt(0);
{$ELSE}
  try
    TDUnitX.CheckCommandLine;
    runner := TDUnitX.CreateRunner;
    runner.UseRTTI := True;
    runner.FailsOnNoAsserts := True;
    if TDUnitX.Options.ConsoleMode <> TDunitXConsoleMode.Off then
    begin
      logger := TDUnitXConsoleLogger.Create
        (TDUnitX.Options.ConsoleMode = TDunitXConsoleMode.Quiet);
      runner.AddLogger(logger);
    end;
    nunitLogger := TDUnitXXMLNUnitFileLogger.Create
      (TDUnitX.Options.XMLOutputFile);
    runner.AddLogger(nunitLogger);
    results := runner.Execute;
    if not results.AllPassed then
      System.ExitCode := EXIT_ERRORS;
{$IFNDEF CI}
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      System.Write('Done.. press <Enter> key to quit.');
      System.Readln;
    end;
{$ENDIF}
  except
    // Wirft der Runner selbst (Fixture-Konstruktor, RTTI), darf der
    // Prozess nicht mit 0 enden - ein Skriptlauf meldete sonst Erfolg
    // (Review reDelphiX nach Bereichen 2026-10-10, Nit 53).
    on E: Exception do
    begin
      System.Writeln(E.ClassName, ': ', E.Message);
      System.ExitCode := EXIT_ERRORS;
    end;
  end;
{$ENDIF}

end.

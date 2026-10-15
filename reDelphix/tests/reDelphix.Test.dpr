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
//   * uTestRdxCodeMap  - Code-Sicht (uRdxCodeMap) gegen ScanCodeLine des
//                        Cores (Drift-Waechter), StartsInside
//   * uTestRdxQualifyUses - Planung von "uses: X -> Scope.X" (QualifyUses)
//   * uTestRdxProjectUnits - Index der Projekt-Units fuer "uses: X ->
//                        Scope.X" (TRdxProjectUnits, Review R1-02)
//   * uTestRdxPaths    - die eine Netzpfad-Regel (uRdxPaths, Charge
//                        B2S-a): UNC, Win32-Namensraum, Netzlaufwerk ueber
//                        die Naht; SCA164/SCA014 auf '\\?\C:\..'
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
  uRdxSimpleFixes in '..\source\uRdxSimpleFixes.pas',
  uRdxStructFixes in '..\source\uRdxStructFixes.pas',
  uRdxLineFixes in '..\source\uRdxLineFixes.pas',
  uRdxRaiseFixes in '..\source\uRdxRaiseFixes.pas',
  uRdxDeclFixes in '..\source\uRdxDeclFixes.pas',
  uRdxFlowFixes in '..\source\uRdxFlowFixes.pas',
  uRdxRoutineFixes in '..\source\uRdxRoutineFixes.pas',
  uRdxCleanupFixes in '..\source\uRdxCleanupFixes.pas',
  uRdxTryFixes in '..\source\uRdxTryFixes.pas',
  uRdxCompilerTraces in '..\source\uRdxCompilerTraces.pas',
  uRdxResultFixes in '..\source\uRdxResultFixes.pas',
  uRdxSqlTemplate in '..\source\uRdxSqlTemplate.pas',
  uRdxRecipeRunner in '..\source\uRdxRecipeRunner.pas',
  uRdxFixTable in '..\source\uRdxFixTable.pas',
  uRdxIntroPlan in '..\source\uRdxIntroPlan.pas',
  uRdxIntroEdits in '..\source\uRdxIntroEdits.pas',
  uRdxMagicFixes in '..\source\uRdxMagicFixes.pas',
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
  uTestRdxMagicGuards in 'uTestRdxMagicGuards.pas',
  uTestRdxMagicFixDetector in 'uTestRdxMagicFixDetector.pas',
  uTestRdxNilFix in 'uTestRdxNilFix.pas',
  uTestRdxSimpleFixesDetector in 'uTestRdxSimpleFixesDetector.pas',
  uTestRdxRoutineFixesDetector in 'uTestRdxRoutineFixesDetector.pas',
  uTestRdxFreeGatesDetector in 'uTestRdxFreeGatesDetector.pas',
  uTestRdxDetectorKit in 'uTestRdxDetectorKit.pas',
  uTestRdxCodeMap in 'uTestRdxCodeMap.pas',
  uTestRdxQualifyUses in 'uTestRdxQualifyUses.pas',
  uTestRdxProjectUnits in 'uTestRdxProjectUnits.pas',
  uTestRdxPaths in 'uTestRdxPaths.pas',
  uTestRdxFixTable in 'uTestRdxFixTable.pas',
  uTestRdxIntroPlan in 'uTestRdxIntroPlan.pas',
  uTestRdxIntroRefuse in 'uTestRdxIntroRefuse.pas',
  uTestRdxIntroGuards in 'uTestRdxIntroGuards.pas',
  uTestRdxIntroEdits in 'uTestRdxIntroEdits.pas',
  uTestRdxIntroContext in 'uTestRdxIntroContext.pas',
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

program reDelphix.Test;

// DUnitX-Testprojekt des Moduls reDelphix (Nico, 2026-10-05: "erstelle ein
// reDelphix.Test Project; Tests fuer alle Varianten des Detektors SCA044").
//
// Prueft den ToolsAPI-freien Teil des Moduls gegen den ECHTEN Core:
//   * uTestRdxRecipes  - Literal-Codec, Format()-Bau, SQL-Vorlage,
//                        Scope-Tabelle (reine Textlogik)
//   * uTestRdxSca044   - Ende zu Ende: Parser, Detektor SCA044,
//                        TSourcePlaces, Rezept-Laeufer - je Variante eine
//                        Temp-Datei, derselbe Weg wie im IDE-Package
//   * uTestRdxActionRing - Ring der Aktionsobjekte des Anbieters (Besitz,
//                        Chargen, Grenzen)
//   * uTestRdxBufferMath - Zeile/Spalte -> Byte im UTF-8-Puffer, Pruefung
//                        aller Ersetzungen, Spaltengrenze, Textwahl
//   * uTestRdxSuppress - Unterdrueck-Marker setzen und entfernen
//   * uTestRdxSimpleFixes - Editorhilfen SCA074/SCA075/SCA085/SCA087/
//                        SCA139 auf Text, ohne Parser
//   * uTestRdxStructFixes - Editorhilfen SCA007/SCA168 (uses-Eintrag,
//                        case-else) auf Text, ohne Parser
//   * uTestRdxBlockFixes - Editorhilfe SCA101/SCA099 (begin..end) auf
//                        Text, ohne Parser
//   * uTestRdxExprFixes - Editorhilfen SCA066/SCA072/SCA084 (uQuickFix-
//                        Umzug) auf Text, ohne Parser
//   * uTestRdxNilFix   - Editorhilfe SCA126 auf Text, ohne Parser
//   * uTestRdxSimpleFixesDetector - dieselben Hilfen gegen den echten
//                        Detektor, Katalog-Beispiele bad -> good
//
// Engine-Units kommen ueber den Suchpfad aus ..\..\SCA.Engine\sources
// (wie StaticCodeAnalyserForm\tests\TestProject), die Modul-Units aus
// ..\source. Kein ToolsAPI: uRdxEditor und uRdxProvider bleiben draussen.
//
// CLI-Lauf: Console-Subsystem; TestInsight-Lauf: GUI-Subsystem (Muster
// aus TestProject.dpr, s. dort).
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
  uRdxRecipes in '..\source\uRdxRecipes.pas',
  uRdxScopeTable in '..\source\uRdxScopeTable.pas',
  uRdxBufferMath in '..\source\uRdxBufferMath.pas',
  uRdxCodeMap in '..\source\uRdxCodeMap.pas',
  uRdxSuppress in '..\source\uRdxSuppress.pas',
  uRdxSimpleFixes in '..\source\uRdxSimpleFixes.pas',
  uRdxStructFixes in '..\source\uRdxStructFixes.pas',
  uRdxRecipeRunner in '..\source\uRdxRecipeRunner.pas',
  uTestRdxRecipes in 'uTestRdxRecipes.pas',
  uTestRdxSca044 in 'uTestRdxSca044.pas',
  uTestRdxActionRing in 'uTestRdxActionRing.pas',
  uTestRdxBufferMath in 'uTestRdxBufferMath.pas',
  uTestRdxSuppress in 'uTestRdxSuppress.pas',
  uTestRdxSimpleFixes in 'uTestRdxSimpleFixes.pas',
  uTestRdxExprFixes in 'uTestRdxExprFixes.pas',
  uTestRdxStructFixes in 'uTestRdxStructFixes.pas',
  uTestRdxBlockFixes in 'uTestRdxBlockFixes.pas',
  uTestRdxNilFix in 'uTestRdxNilFix.pas',
  uTestRdxSimpleFixesDetector in 'uTestRdxSimpleFixesDetector.pas',
  uTestRdxCodeMap in 'uTestRdxCodeMap.pas',
  uTestRdxQualifyUses in 'uTestRdxQualifyUses.pas';

{ keep comment here to protect the following conditional from being removed by the IDE when adding a unit }
{$IFNDEF TESTINSIGHT}

var
  runner: ITestRunner;
  results: IRunResults;
  logger: ITestLogger;
  nunitLogger: ITestLogger;
{$ENDIF}

begin
{$IFDEF TESTINSIGHT}
  TestInsight.DUnitX.RunRegisteredTests;
  Halt(0);
{$ELSE}
  try
    TDUnitX.CheckCommandLine;
    runner := TDUnitX.CreateRunner;
    runner.UseRTTI := True;
    runner.FailsOnNoAsserts := False;
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

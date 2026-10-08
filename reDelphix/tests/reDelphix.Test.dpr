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
  uRdxSuppress in '..\source\uRdxSuppress.pas',
  uRdxRecipeRunner in '..\source\uRdxRecipeRunner.pas',
  uTestRdxRecipes in 'uTestRdxRecipes.pas',
  uTestRdxSca044 in 'uTestRdxSca044.pas',
  uTestRdxActionRing in 'uTestRdxActionRing.pas',
  uTestRdxBufferMath in 'uTestRdxBufferMath.pas',
  uTestRdxSuppress in 'uTestRdxSuppress.pas';

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
    on E: Exception do
      System.Writeln(E.ClassName, ': ', E.Message);
  end;
{$ENDIF}

end.

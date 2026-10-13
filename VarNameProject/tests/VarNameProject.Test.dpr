program VarNameProject.Test;

// DUnitX-Testprojekt von VarNameProject (Nico 2026-10-11: "erstelle auch
// tests um die editorhelper zu testen").
//
// Prueft den ToolsAPI-freien Teil der Code-Aktion "Lokale Variable
// einfuehren" auf Text - dieselben Units, die das IDE-Paket
// benutzt:
//   * uTestVnpPlan  - uVnpPlan: Literal am Caret, gleiche Literale der
//                     Zeile, Deklarationszeile, Spalten, Kommentare,
//                     freier Name, Bytes/Zeichen
//   * uTestVnpRefuse - uVnpPlan: Zweig ohne begin (begin..end) und alle
//                     Ablehnungen
//   * uTestVnpGuards - Schutzregeln aus dem Korpus-A/B: Routinen-Koepfe,
//                     case-Marken, offene Bloecke, Direktiven, mehrzeilige
//                     Strings
//   * uTestVnpEdits - uVnpEdits: Text-Schnappschuss, Ziel an der
//                     Caret-Position und die Ersetzungen des Writers (C1h)
//                     Ende zu Ende - der Text, der danach im Puffer steht
//                     (Demo-Faelle 1-6, CR LF und LF, Umlaute vor dem
//                     Literal)
//   * uTestVnpContext - uVnpEdits.TargetAt ueber mehrere Zeilen: mehrzeilige
//                     Strings mit mehr als drei Quotes, Kommentargrenzen
//                     eines begin..end, asm/initialization, Direktiven,
//                     Bedingungsausdruck, FPC-Weiche, Zeilenenden je Zeile
//   * uTestVnpTemplate - D1: Template-Code, Template-Datei, eigenes
//                     Template erkennen, Anweisung loeschen und
//                     zurueckschreiben, Modell der Template-Expansion
// Der IDE-Teil (uVnpIntroduce: Sync Edit, InsertCode, Fokus, Abbau) ist
// nur in der IDE pruefbar - Testplan in ..\README.md.
//
// Dieselben Testunits laufen ohne IDE im FPC-Pruefstand
// (..\tools\fpc-pruefstand\build.sh).
//
// CLI-Lauf: Console-Subsystem; TestInsight-Lauf: GUI-Subsystem (Muster aus
// reDelphix.Test.dpr).
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
  uVnpPlan in '..\source\uVnpPlan.pas',
  uVnpEdits in '..\source\uVnpEdits.pas',
  uTestVnpPlan in 'uTestVnpPlan.pas',
  uTestVnpRefuse in 'uTestVnpRefuse.pas',
  uTestVnpGuards in 'uTestVnpGuards.pas',
  uTestVnpEdits in 'uTestVnpEdits.pas',
  uTestVnpContext in 'uTestVnpContext.pas',
  uTestVnpTemplate in 'uTestVnpTemplate.pas';

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
    // Wirft der Runner selbst (Fixture-Konstruktor, RTTI), darf der Prozess
    // nicht mit 0 enden - ein Skriptlauf meldete sonst Erfolg.
    on E: Exception do
    begin
      System.Writeln(E.ClassName, ': ', E.Message);
      System.ExitCode := EXIT_ERRORS;
    end;
  end;
{$ENDIF}

end.

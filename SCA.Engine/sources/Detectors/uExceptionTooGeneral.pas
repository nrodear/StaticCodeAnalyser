unit uExceptionTooGeneral;

// Detektor: `except on E: Exception do ...` mit Basisklasse Exception.
//
// Pattern (Code Smell, Sonar-50 #11):
//   try
//     DoStuff;
//   except
//     on E: Exception do           // <-- faengt ALLES, inklusive
//       Log(E.Message);             //     EOutOfMemory, EAbort, ...
//   end;
//
// Korrekt:
//   try
//     DoStuff;
//   except
//     on E: EDatabaseError do      // spezifische Subklasse
//       Log(E.Message);
//     on E: EArgumentException do
//       Log(E.Message);
//   end;
//
// Warum schaedlich: das Basis-Exception faengt jeden Fehler, auch solche
// die normalerweise NICHT vom User-Code behandelt werden sollten (z.B.
// EOutOfMemory, EAccessViolation, EAbort als Steuerflusssignal). Der
// Aufrufer denkt, er habe alles im Griff - in Wirklichkeit verschluckt
// er System-Fehler die abgebrochen werden sollten.
//
// Erkennung (AST):
//   Parser legt 'on E: T do ...' als nkOnHandler ab. Dabei:
//     OnNode.Name    = Exception-Variablen-Name (z.B. 'E') oder leer
//     OnNode.TypeRef = Typ-Identifier (z.B. 'Exception', 'EFoo')
//   Befund wenn SameText(TypeRef, 'Exception').
//
// Bewusst NICHT als Finding:
//   * `except ... end;` ohne `on`-Klausel - faengt zwar auch alles, das
//     ist aber Pattern fuer Top-Level-Crash-Handler. Eigener Detector
//     (fkEmptyExcept fuer leere Variante) deckt das ab.
//   * `on E: EAbort do ... raise;` mit re-raise - dort wuerde Filter
//     greifen, aber TypeRef='EAbort' nicht 'Exception'.
//   * Legit Top-Level-Handler die LOGGEN und beenden:
//       `on E: Exception do begin WriteLn(ErrOutput, 'Fatal: ', E.Message);`
//       `Exit(Integer(cecToolError)); end;`
//     Diese Pattern faengt zwar 'Exception' breit, ist aber bewusst die
//     defensive Schutzschicht am Top-Level (CLI-Runner, Worker-Threads).
//     Heuristik: Body enthaelt einen Log-Call (WriteLn/Write/Log/Output*)
//     UND einen Exit/Halt - dann ist es kein Swallow, sondern saubere
//     Crash-Translation.
//
// Sonar-Pendant: ExceptionTooGeneral / "java:S2221" (Java)
//                S110 Pattern bezogen auf Delphi-Hierarchie.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TExceptionTooGeneralDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, CanBeStrictPrivate, CyclomaticComplexity, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

function IsLegitTopLevelHandler(OnNode: TAstNode): Boolean;
// True wenn der Handler-Body sowohl LOGGT (WriteLn/Write/Log*/OutputDebug*)
// als auch BEENDET/RAISE'T (Exit/Halt/raise). Dann ist es kein blindes
// Swallow, sondern saubere Crash-Translation am Top-Level.
//
// Heuristik scannt nur die DIREKTEN Calls im Subtree des OnHandlers - kein
// Daten-Fluss, kein Symbol-Lookup. Schmal genug um nur die klare 'log+exit'
// und 'log+raise' Pattern zu treffen.
var
  Stack    : TList<TAstNode>;
  Cur      : TAstNode;
  i        : Integer;
  NameLow  : string;
  HasLog   : Boolean;
  HasLeave : Boolean;
begin
  Result   := False;
  HasLog   := False;
  HasLeave := False;
  Stack    := TList<TAstNode>.Create;
  try
    Stack.Add(OnNode);
    while Stack.Count > 0 do
    begin
      Cur := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);

      // raise; (bare re-raise) ist eine Form von Leave - Exception
      // propagiert nach oben.
      if Cur.Kind = nkRaise then HasLeave := True;
      if Cur.Kind = nkExit  then HasLeave := True;
      // Result := exit-code im Handler ist auch Leave-Pattern: Funktion
      // gibt Fehler-Code zurueck und faellt natuerlich durch ans Method-End.
      // Klassische CLI-Runner-/Worker-Translation:
      //   `except on E: Exception do begin WriteLn(...); Result := cecToolError; end;`
      // Wir akzeptieren auch `Result.Field`/`Result[i]`/`Result^`-Zuweisungen.
      if Cur.Kind = nkAssign then
      begin
        NameLow := LowerCase(Trim(Cur.Name));
        if (NameLow = 'result') or
           NameLow.StartsWith('result.') or
           NameLow.StartsWith('result[') or
           NameLow.StartsWith('result^') then
          HasLeave := True;
      end;

      if Cur.Kind = nkCall then
      begin
        NameLow := LowerCase(Cur.Name);
        // Log-Pattern: WriteLn/Write/Log*/OutputDebugString/ShowMessage
        if NameLow.StartsWith('writeln(')      or
           NameLow.StartsWith('write(')        or
           NameLow.StartsWith('outputdebug')   or
           NameLow.StartsWith('log')           or
           NameLow.StartsWith('showmessage(')  or
           NameLow.StartsWith('savetofile(')   then
          HasLog := True;
        // Leave-Pattern: Halt(...) / Exit(...)
        if NameLow.StartsWith('halt(')         or
           NameLow.StartsWith('halt;')         or
           NameLow.StartsWith('exit(')         or
           NameLow.StartsWith('exit;')         then
          HasLeave := True;
      end;
      if HasLog and HasLeave then Exit(True);

      for i := 0 to Cur.Children.Count - 1 do
        Stack.Add(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

class procedure TExceptionTooGeneralDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Handlers : TList<TAstNode>;
  N        : TAstNode;
  F        : TLeakFinding;
begin
  Handlers := MethodNode.FindAll(nkOnHandler);
  try
    for N in Handlers do
    begin
      if not SameText(N.TypeRef, 'Exception') then Continue;
      if IsLegitTopLevelHandler(N) then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := MethodNode.Name;
      F.LineNumber := IntToStr(N.Line);
      F.MissingVar :=
        'except on E: Exception catches every error - prefer a specific subclass';
      F.SetKind(fkExceptionTooGeneral);
      Results.Add(F);
    end;
  finally
    Handlers.Free;
  end;
end;

class procedure TExceptionTooGeneralDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(M, FileName, Results);
  finally
    Methods.Free;
  end;
end;

end.

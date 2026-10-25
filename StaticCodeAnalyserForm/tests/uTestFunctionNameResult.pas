unit uTestFunctionNameResult;

// Tests fuer TFunctionNameResultDetector (Charge N / FN, 2026-10-25):
// SCA204 FunctionNameAsResult ('GetCount := ..' statt 'Result := ..') und
// SCA205 FunctionNameRecursion ('Total := Total + X' - rechts ein
// rekursiver Aufruf).
//
// Der Detektor liest den Quelltext samt {$mode}-Direktiven - die Tests
// laufen ueber FindingsOfFile (dort registriert). Jede Quelle traegt ihre
// Erwartung als Marke: '// HIT204' bzw. '// HIT205' auf der ersten
// erwarteten Fundzeile; Negativproben stehen neben einer POSITIVEN Wache in
// derselben Quelle (oder einer Gegenquelle im selben Test), sind also ohne
// den Detektor rot. Die Quellen sind mit dem echten Scanner (FPC-Harness)
// und der Python-Nachbildung nachgerechnet (scratchpad chargeN/FN/tests).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFunctionNameResult = class
  public
    [Test] procedure Assign_MethodGetter_Hint;
    [Test] procedure Assign_CaseLabelAndTwoOnALine_OnePerLine;
    [Test] procedure Assign_NestedRoutines_OnlyOwnName;
    [Test] procedure Assign_ShadowWithProcedure_NotReported;
    [Test] procedure Assign_CommentStringElement_NotReported;
    [Test] procedure Assign_ModeFpcWithoutResult_NotReported;
    [Test] procedure Read_ParameterlessAccumulator_Error;
    [Test] procedure Read_ConditionAndExit_ErrorOncePerLine;
    [Test] procedure Read_DefaultParameter_Warning;
    [Test] procedure Read_DeliberateRecursionBeside_Warning;
    [Test] procedure Read_BareCallArgument_Warning;
    [Test] procedure Read_ResultStyleRecursion_NotReported;
    [Test] procedure Read_MandatoryParamAndOperators_NotReported;
    [Test] procedure Read_ModeObjFpc_OnlyAssign;
    [Test] procedure Read_FpcDialectWithoutMode_NotReported;
    [Test] procedure Read_IfdefVersions_OneBranchRead;
    [Test] procedure Read_DeclarationsWithoutBody_NotReported;
    [Test] procedure Message_NamesTheFunction;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uStaticFiles, uFuncNameResultScan,
  uTestFindingHelper;

const
  CRLF = #13#10;
  // Read_ParameterlessAccumulator_Error und Message_NamesTheFunction.
  SRC_TOTAL =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function Total: Integer;' + CRLF +
    'var' + CRLF +
    '  I: Integer;' + CRLF +
    'begin' + CRLF +
    '  Total := 0;' + CRLF +
    '  for I := 1 to 3 do' + CRLF +
    '    Total := Total + I; // HIT205' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;

// A204 Funde SCA204 und A205 Funde SCA205; der erste steht jeweils auf der
// Zeile mit '// HIT204' bzw. '// HIT205' (SCA204 nur, wenn die Quelle die
// Marke traegt), der erste SCA205 mit der Schwere ASev205.
procedure Check(const ASrc: string; A204, A205: Integer;
  ASev205: TLeakSeverity; const AWhy: string);
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
  L   : string;
begin
  F := TFindingHelper.FindingsOfFile(ASrc);
  try
    Assert.AreEqual<Integer>(A204,
      TFindingHelper.Count(F, fkFunctionNameAsResult), 'SCA204: ' + AWhy);
    Assert.AreEqual<Integer>(A205,
      TFindingHelper.Count(F, fkFunctionNameRecursion), 'SCA205: ' + AWhy);
    L := TFindingHelper.LineOf(ASrc, '// HIT204');
    if (A204 > 0) and (L <> '') then
      Assert.AreEqual(L, TFindingHelper.FirstOf(F,
        fkFunctionNameAsResult).LineNumber, 'SCA204-Zeile: ' + AWhy);
    if A205 > 0 then
    begin
      Hit := TFindingHelper.FirstOf(F, fkFunctionNameRecursion);
      Assert.AreEqual(TFindingHelper.LineOf(ASrc, '// HIT205'),
        Hit.LineNumber, 'SCA205-Zeile: ' + AWhy);
      Assert.AreEqual<Integer>(Ord(ASev205), Ord(Hit.Severity),
        'SCA205-Schwere: ' + AWhy);
    end;
  finally
    F.Free;
  end;
end;

// die altmodische Zuweisung im Getter einer Methode
procedure TTestFunctionNameResult.Assign_MethodGetter_Hint;
const
  SRC =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'type' + CRLF +
    '  TList = class' + CRLF +
    '    FCount: Integer;' + CRLF +
    '    function GetCount: Integer;' + CRLF +
    '  end;' + CRLF +
    'function TList.GetCount: Integer;' + CRLF +
    'begin' + CRLF +
    '  GetCount := FCount; // HIT204' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
begin
  Check(SRC, 1, 0, lsError, 'Assign_MethodGetter_Hint');
end;

// hinter einem case-Label gemeldet; zwei Zuweisungen auf einer Zeile = ein
// Fund
procedure TTestFunctionNameResult.Assign_CaseLabelAndTwoOnALine_OnePerLine;
const
  SRC =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function Pick(N: Integer): Integer;' + CRLF +
    'begin' + CRLF +
    '  case N of' + CRLF +
    '    1: Pick := 10; // HIT204' + CRLF +
    '  end;' + CRLF +
    '  if N > 5 then Pick := 1 else Pick := 2;' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
begin
  Check(SRC, 2, 0, lsError, 'Assign_CaseLabelAndTwoOnALine_OnePerLine');
end;

// die innere Funktion meldet ihre eigene Zuweisung; die aeussere wird nicht
// beurteilt, weil die innere ihren Namen nennt
procedure TTestFunctionNameResult.Assign_NestedRoutines_OnlyOwnName;
const
  SRC =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function Outer: Integer;' + CRLF +
    '  function Inner: Integer;' + CRLF +
    '  begin' + CRLF +
    '    Inner := 2; // HIT204' + CRLF +
    '    Outer := 3;' + CRLF +
    '  end;' + CRLF +
    'begin' + CRLF +
    '  Outer := Inner;' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
begin
  Check(SRC, 1, 0, lsError, 'Assign_NestedRoutines_OnlyOwnName');
end;

// Prozedur, gleichnamige lokale Variable, with-Anweisung und anonyme Methode
// melden nichts - die Wache schon
procedure TTestFunctionNameResult.Assign_ShadowWithProcedure_NotReported;
const
  SRC =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'procedure Proc;' + CRLF +
    'begin' + CRLF +
    '  Proc := 1;' + CRLF +
    'end;' + CRLF +
    'function Shadow: Integer;' + CRLF +
    'var' + CRLF +
    '  Shadow: Integer;' + CRLF +
    'begin' + CRLF +
    '  Shadow := 5;' + CRLF +
    'end;' + CRLF +
    'function UsesWith: Integer;' + CRLF +
    'begin' + CRLF +
    '  with Obj do' + CRLF +
    '    UsesWith := 5;' + CRLF +
    '  P := procedure begin UsesWith := 6; end;' + CRLF +
    '  UsesWith := 7; // HIT204' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
begin
  Check(SRC, 1, 0, lsError, 'Assign_ShadowWithProcedure_NotReported');
end;

// Kommentar, String und Element des Ergebnisses (Recs.X :=) melden nichts
procedure TTestFunctionNameResult.Assign_CommentStringElement_NotReported;
const
  SRC =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function Recs: TRec;' + CRLF +
    'begin' + CRLF +
    '  { Recs := Default(TRec); }' + CRLF +
    '  // Recs := Default(TRec);' + CRLF +
    '  S := ''Recs := 1'';' + CRLF +
    '  Recs.X := 5;' + CRLF +
    '  Recs := Other; // HIT204' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
begin
  Check(SRC, 1, 0, lsError, 'Assign_CommentStringElement_NotReported');
end;

// {$mode fpc} und {$X-} kennen kein Result - weder Fund noch Fix; die Wache
// ist dieselbe Funktion mit {$modeswitch result}
procedure TTestFunctionNameResult.Assign_ModeFpcWithoutResult_NotReported;
const
  SRC_FPC =
    'unit t;' + CRLF +
    '{$mode fpc}' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function Twice(X: Integer): Integer;' + CRLF +
    'begin' + CRLF +
    '  Twice := 2 * X;' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
  SRC_SWITCH =
    'unit t;' + CRLF +
    '{$mode fpc}' + CRLF +
    '{$modeswitch result}' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function Twice(X: Integer): Integer;' + CRLF +
    'begin' + CRLF +
    '  Twice := 2 * X; // HIT204' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
  SRC_XOFF =
    'unit t;' + CRLF +
    '{$H+,X-}' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function Twice(X: Integer): Integer;' + CRLF +
    'begin' + CRLF +
    '  Twice := 2 * X;' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
begin
  Check(SRC_FPC, 0, 0, lsError, '{$mode fpc} ohne Result');
  Check(SRC_XOFF, 0, 0, lsError, '{$H+,X-}: Delphi kennt kein Result');
  Check(SRC_SWITCH, 1, 0, lsError, '{$modeswitch result} macht Result verfuegbar');
end;

// Total := Total + I - rechts ein rekursiver Aufruf; dieselbe Zeile traegt
// auch den SCA204-Fund
procedure TTestFunctionNameResult.Read_ParameterlessAccumulator_Error;
begin
  Check(SRC_TOTAL, 2, 1, lsError, 'Read_ParameterlessAccumulator_Error');
end;

// Lesen in Bedingung und Exit(Name) auf einer Zeile: ein Fund, Error
procedure TTestFunctionNameResult.Read_ConditionAndExit_ErrorOncePerLine;
const
  SRC =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function Level: Integer;' + CRLF +
    'begin' + CRLF +
    '  Level := 1;' + CRLF +
    '  if Level > 2 then Exit(Level); // HIT205' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
begin
  Check(SRC, 1, 1, lsError, 'Read_ConditionAndExit_ErrorOncePerLine');
end;

// nur Default-Parameter: der nackte Name ruft Dd(0) - Warning
procedure TTestFunctionNameResult.Read_DefaultParameter_Warning;
const
  SRC =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function Dd(A: Integer = 0): Integer;' + CRLF +
    'begin' + CRLF +
    '  Dd := A + Dd; // HIT205' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
begin
  Check(SRC, 1, 1, lsWarning, 'Read_DefaultParameter_Warning');
end;

// eine Aufruf-Anweisung Next; im Rumpf zeigt bewusste Rekursion - Warning
procedure TTestFunctionNameResult.Read_DeliberateRecursionBeside_Warning;
const
  SRC =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function Next: Integer;' + CRLF +
    'begin' + CRLF +
    '  Next := 0;' + CRLF +
    '  if Skip then' + CRLF +
    '    Next;' + CRLF +
    '  Next := Next + 1; // HIT205' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
begin
  Check(SRC, 2, 1, lsWarning, 'Read_DeliberateRecursionBeside_Warning');
end;

// nacktes Argument Foo(Arg) - vielleicht ein var-Parameter: Warning
procedure TTestFunctionNameResult.Read_BareCallArgument_Warning;
const
  SRC =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function Arg: Integer;' + CRLF +
    'begin' + CRLF +
    '  Arg := 1; // HIT204' + CRLF +
    '  Foo(Arg); // HIT205' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
begin
  Check(SRC, 1, 1, lsWarning, 'Read_BareCallArgument_Warning');
end;

// wer Result schreibt, meint mit -Factor den Aufruf - kein Fund; die Wache
// zeigt den bewiesenen Fall
procedure TTestFunctionNameResult.Read_ResultStyleRecursion_NotReported;
const
  SRC =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function Factor: Integer;' + CRLF +
    'begin' + CRLF +
    '  if Tok = ''-'' then' + CRLF +
    '    Result := -Factor' + CRLF +
    '  else' + CRLF +
    '    Result := 1;' + CRLF +
    'end;' + CRLF +
    'function Sum: Integer;' + CRLF +
    'begin' + CRLF +
    '  Sum := 1;' + CRLF +
    '  Sum := Sum * 2; // HIT205' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
begin
  Check(SRC, 2, 1, lsError, 'Read_ResultStyleRecursion_NotReported');
end;

// Pflichtparameter (Compilerfehler oder andere Ueberladung), Inc(),
// inherited, @, Self., Name() - kein SCA205
procedure TTestFunctionNameResult.Read_MandatoryParamAndOperators_NotReported;
const
  SRC =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function WithArg(A: Integer): Integer;' + CRLF +
    'begin' + CRLF +
    '  WithArg := A + WithArg; // HIT204' + CRLF +
    'end;' + CRLF +
    'function TFoo.Value: Integer;' + CRLF +
    'begin' + CRLF +
    '  Value := inherited Value;' + CRLF +
    '  Inc(Value);' + CRLF +
    '  P := @Value;' + CRLF +
    '  X := Self.Value + Value();' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
begin
  Check(SRC, 2, 0, lsError, 'Read_MandatoryParamAndOperators_NotReported');
end;

// {$mode objfpc}: rechts liest der Name das Ergebnis (FPC-Probe) - nur
// SCA204
procedure TTestFunctionNameResult.Read_ModeObjFpc_OnlyAssign;
const
  SRC =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    '{$mode objfpc}' + CRLF +
    'function Total: Integer;' + CRLF +
    'begin' + CRLF +
    '  Total := 0; // HIT204' + CRLF +
    '  Total := Total + 1;' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
begin
  Check(SRC, 2, 0, lsError, 'Read_ModeObjFpc_OnlyAssign');
end;

// Scan-Dialekt FPC ohne {$mode}: Modus unbekannt - beide still; unter Delphi
// dieselbe Quelle mit Fund
procedure TTestFunctionNameResult.Read_FpcDialectWithoutMode_NotReported;
const
  SRC =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function Total: Integer;' + CRLF +
    'begin' + CRLF +
    '  Total := 0;' + CRLF +
    '  Total := Total + 1; // HIT205' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
var
  Alt : TSourceDialect;
begin
  Check(SRC, 2, 1, lsError, 'Scan-Dialekt Delphi: Datei ohne {$mode} ist Delphi');
  Alt := TStaticFiles.ScanDialect;
  TStaticFiles.ScanDialect := dlFpc;
  try
    Check(SRC, 0, 0, lsError, 'Scan-Dialekt FPC: Modus unbekannt');
  finally
    TStaticFiles.ScanDialect := Alt;
  end;
end;

// zwei IFDEF-Fassungen mit je einem begin: nur eine wird gelesen, der Rumpf
// der inneren Funktion endet richtig - die aeussere ruft sie nur auf
procedure TTestFunctionNameResult.Read_IfdefVersions_OneBranchRead;
const
  SRC =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function TSym.GetToken: Boolean;' + CRLF +
    '  function CanBeToken: Boolean;' + CRLF +
    '  var i: Integer;' + CRLF +
    '  begin' + CRLF +
    '    CanBeToken := True; // HIT204' + CRLF +
    '    for i := 0 to 3 do' + CRLF +
    '      {$IFNDEF FPC}' + CRLF +
    '      if not (fLine[i] in [#32, #9]) then begin' + CRLF +
    '      {$ELSE}' + CRLF +
    '      if not (fLine[i] in [#9]) then begin' + CRLF +
    '      {$ENDIF}' + CRLF +
    '        CanBeToken := False;' + CRLF +
    '        Break;' + CRLF +
    '      end;' + CRLF +
    '  end;' + CRLF +
    'begin' + CRLF +
    '  Result := False;' + CRLF +
    '  if CanBeToken then' + CRLF +
    '    Result := True;' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
begin
  Check(SRC, 2, 0, lsError, 'Read_IfdefVersions_OneBranchRead');
end;

// interface-Kopf, Klassenrumpf, forward und external sind keine Rumpfe; der
// Rumpf nach forward zaehlt
procedure TTestFunctionNameResult.Read_DeclarationsWithoutBody_NotReported;
const
  SRC =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'function Api: Integer;' + CRLF +
    'type' + CRLF +
    '  TFoo = class' + CRLF +
    '    function Get: Integer;' + CRLF +
    '  end;' + CRLF +
    'implementation' + CRLF +
    'type' + CRLF +
    '  TBar = class' + CRLF +
    '    function Get: Integer;' + CRLF +
    '  end;' + CRLF +
    'function Ext: Integer; stdcall; external ''x.dll'';' + CRLF +
    'function Later: Integer; forward;' + CRLF +
    'function Api: Integer;' + CRLF +
    'begin' + CRLF +
    '  Result := Later;' + CRLF +
    'end;' + CRLF +
    'function Later: Integer;' + CRLF +
    'begin' + CRLF +
    '  Later := 1; // HIT204' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
begin
  Check(SRC, 1, 0, lsError,
    'nur der Rumpf von Later; Api schreibt Result und ruft Later');
end;

// Die Meldungen nennen den Namen wie geschrieben; SCA204 ist ein Hint, die
// feste Form liest der Planer in reDelphix (FNR_ASSIGN_PREFIX/_MID).
procedure TTestFunctionNameResult.Message_NamesTheFunction;
var
  F : TObjectList<TLeakFinding>;
  A, R : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC_TOTAL);
  try
    A := TFindingHelper.FirstOf(F, fkFunctionNameAsResult);
    R := TFindingHelper.FirstOf(F, fkFunctionNameRecursion);
    Assert.IsNotNull(A, 'SCA204-Fund fehlt');
    Assert.IsNotNull(R, 'SCA205-Fund fehlt');
    Assert.AreEqual<Integer>(Ord(lsHint), Ord(A.Severity), 'SCA204 ist ein Hint');
    Assert.AreEqual(FNR_ASSIGN_PREFIX + 'Total' + FNR_ASSIGN_MID +
      FNR_ASSIGN_ADVICE, A.MissingVar, 'SCA204-Meldung');
    Assert.IsTrue(Pos('Function name ''Total'' read in its own body is a ' +
      'recursive call', R.MissingVar) = 1, 'SCA205 nennt den Namen');
    Assert.IsTrue(Pos('write Total() if the recursion is intended',
      R.MissingVar) > 0, 'SCA205 nennt die Aufruf-Form');
  finally
    F.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFunctionNameResult);
end.

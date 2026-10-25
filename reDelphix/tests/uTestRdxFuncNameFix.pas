unit uTestRdxFuncNameFix;

// Editorhilfe SCA204 FunctionNameAsResult (uRdxFuncNameFix):
//   Fixture 1 (Text, ohne Parser und Detektor): 'Name :=' -> 'Result :='
//   im Getter, je Zeile alle Zuweisungen, hinter case-Label, Lesestelle
//   bleibt; Gegenproben verschobene Zeile, Meldung ohne Namen, Kommentar
//   zwischen Name und ':=', {$mode fpc}, {$X-}, {$IFDEF FPC} ohne {$mode},
//   geschachtelte Routine, Prozedur, verdeckender Bezeichner, with davor.
//   Fixture 2 (hinter {$IFNDEF FPC}, nur reDelphix.Test): der ECHTE
//   Detektor meldet, die Tabelle plant aus dem Fund (TRdxFixTable.FixFor,
//   Adapter PlanFuncNameResult), die Ersetzung wird angewandt - und der
//   Detektor schweigt (SCA204), SCA205 bleibt, wo rechts gelesen wird.
// Fixture 1 laeuft auch im FPC-Pruefstand (build.sh).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxFuncNameFix = class
  public
    [Test] procedure Getter_Becomes_Result;
    [Test] procedure Spelling_And_Comment_Kept;
    [Test] procedure Two_On_One_Line_Both;
    [Test] procedure Case_Label;
    [Test] procedure Read_On_Line_Stays;
    [Test] procedure Moved_Line_NoHelp;
    [Test] procedure Message_Without_Name_NoHelp;
    [Test] procedure Comment_Before_Assign_NoHelp;
    [Test] procedure Mode_Without_Result_NoHelp;
    [Test] procedure Fpc_Unit_Without_Mode_NoHelp;
    [Test] procedure Nested_Routine_NoHelp;
    [Test] procedure Shadowing_Local_NoHelp;
    [Test] procedure With_Before_Line_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxFuncNameFixDetector = class
  public
    [Test] procedure Detector_Getter_RoundTrip;
    [Test] procedure Detector_Accumulator_ReadStays;
    [Test] procedure Detector_CatalogExample;
    [Test] procedure Adapter_Without_Lines_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxFuncNameFix,
  uTestRdxTextKit   // Join, Apply, LineOf
{$IFNDEF FPC}
  , System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uFunctionNameResult,
  uRdxRecipeRunner, uRdxFixTable, uTestRdxDetectorKit
{$ENDIF}
  ;

const
  // Kennungen in den Gruenden, die in en/de/fr gleich bleiben (ASCII in
  // Anfuehrung bzw. Klammern) - der Test haengt nicht an der Sprache.
  REASON_MOVED    = '"GetCount :="';
  REASON_MESSAGE  = '"Name :="';
  REASON_NONCODE  = '":="';
  REASON_MODE     = '{$mode fpc}';
  REASON_X_OFF    = '{$X-}';
  REASON_FPC      = '{$IFDEF FPC}';
  REASON_OTHER    = 'Inner';
  REASON_SHADOW   = '"Shadow"';
  REASON_WITH     = '"with"';
  // Die Meldung des Detektors (uFuncNameResultScan.MessageOf) fuer AName.
  ADVICE = ' - write ''Result :='' (the bare name in an expression is a '
    + 'recursive call)';

function Msg(const AName: string): string;
begin
  Result := FNR_ASSIGN_PREFIX + AName + FNR_ASSIGN_MID + ADVICE;
end;

// ---- Helfer ----

// Eine Unit: AHead vor 'interface' (Direktiven), die Zeilen AImpl hinter
// 'implementation'.
function InUnit(const AHead: string; const AImpl: array of string): string;
begin
  Result := 'unit u;' + #13#10;
  if AHead <> '' then
    Result := Result + AHead + #13#10;
  Result := Result + Join(['interface', 'implementation']) + #13#10 +
    Join(AImpl) + #13#10 + 'end.';
end;

// Eine Funktion F: Integer mit dem Rumpf ABody.
function InFunc(const AName: string; const ABody: array of string): string;
var
  L : array of string;
  i : Integer;
begin
  SetLength(L, Length(ABody) + 3);
  L[0] := 'function ' + AName + ': Integer;';
  L[1] := 'begin';
  for i := 0 to High(ABody) do
    L[i + 2] := ABody[i];
  L[High(L)] := 'end;';
  Result := InUnit('', L);
end;

// Die Hilfe fuer die Zeile mit AMarker: neuer Text oder '' bei Ablehnung.
function Fix(const ASource, AMarker, AMessage: string;
  out AReason: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if TRdxFuncNameFix.ResultAssign(Map, LineOf(ASource, AMarker), AMessage,
       E, AReason) then
      Result := Apply(ASource, E);
  finally
    Map.Free;
    SL.Free;
  end;
end;

procedure AssertFix(const ASource, AMarker, AName, AExpected: string);
var
  R : string;
begin
  Assert.AreEqual(AExpected, Fix(ASource, AMarker, Msg(AName), R), R);
end;

procedure AssertNoHelp(const ASource, AMarker, AName,
  AReasonPart: string);
var
  R : string;
begin
  Assert.AreEqual('', Fix(ASource, AMarker, Msg(AName), R), 'keine Aenderung');
  Assert.IsTrue(Pos(AReasonPart, R) > 0, 'Grund: ' + R);
end;

// ---- Fixture 1 ----

procedure TTestRdxFuncNameFix.Getter_Becomes_Result;
const
  BEFORE = 'function TList.GetCount: Integer;';
begin
  AssertFix(InUnit('', [BEFORE, 'begin', '  GetCount := FCount;', 'end;']),
    'GetCount :=', 'GetCount',
    InUnit('', [BEFORE, 'begin', '  Result := FCount;', 'end;']));
end;

procedure TTestRdxFuncNameFix.Spelling_And_Comment_Kept;
begin
  // Der Name steht in der Meldung wie an der Stelle geschrieben; der
  // Vergleich ist ohne Gross/klein, Kommentar und Rest der Zeile bleiben.
  AssertFix(InFunc('GetCount', ['  GETCOUNT := 1; // GetCount := 2']),
    'GETCOUNT', 'GETCOUNT',
    InFunc('GetCount', ['  Result := 1; // GetCount := 2']));
end;

procedure TTestRdxFuncNameFix.Two_On_One_Line_Both;
begin
  AssertFix(InFunc('Pick', ['  if N > 5 then Pick := 1 else Pick := 2;']),
    'Pick := 1', 'Pick',
    InFunc('Pick', ['  if N > 5 then Result := 1 else Result := 2;']));
end;

procedure TTestRdxFuncNameFix.Case_Label;
begin
  AssertFix(InFunc('Pick', ['  case N of', '    1: Pick := 10;', '  end;']),
    '1: Pick', 'Pick',
    InFunc('Pick', ['  case N of', '    1: Result := 10;', '  end;']));
end;

procedure TTestRdxFuncNameFix.Read_On_Line_Stays;
begin
  // Rechts bleibt der Name stehen (SCA205, eigener Fund ohne Hilfe).
  AssertFix(InFunc('Total', ['  Total := 0;', '  Total := Total + 1;']),
    'Total + 1', 'Total',
    InFunc('Total', ['  Total := 0;', '  Result := Total + 1;']));
end;

procedure TTestRdxFuncNameFix.Moved_Line_NoHelp;
begin
  AssertNoHelp(InFunc('GetCount', ['  X := GetCount;']), 'X :=', 'GetCount',
    REASON_MOVED);
end;

procedure TTestRdxFuncNameFix.Message_Without_Name_NoHelp;
var
  R : string;
begin
  Assert.AreEqual('', Fix(InFunc('GetCount', ['  GetCount := 1;']),
    'GetCount :=', 'Loop past the last index: i := 0 to L.Count', R));
  Assert.IsTrue(Pos(REASON_MESSAGE, R) > 0, R);
end;

procedure TTestRdxFuncNameFix.Comment_Before_Assign_NoHelp;
begin
  AssertNoHelp(InFunc('GetCount', ['  GetCount {x} := 1;']), '{x}',
    'GetCount', REASON_NONCODE);
end;

procedure TTestRdxFuncNameFix.Mode_Without_Result_NoHelp;
begin
  AssertNoHelp(InUnit('{$mode fpc}', ['function Twice(X: Integer): Integer;',
    'begin', '  Twice := 2 * X;', 'end;']), 'Twice :=', 'Twice', REASON_MODE);
  AssertNoHelp(InUnit('{$H+,X-}', ['function Twice(X: Integer): Integer;',
    'begin', '  Twice := 2 * X;', 'end;']), 'Twice :=', 'Twice', REASON_X_OFF);
end;

procedure TTestRdxFuncNameFix.Fpc_Unit_Without_Mode_NoHelp;
const
  BODY: array[0..3] of string = ('function Twice(X: Integer): Integer;',
    'begin', '  Twice := 2 * X;', 'end;');
begin
  AssertNoHelp(InUnit('{$IFDEF FPC}{$H+}{$ENDIF}', BODY), 'Twice :=',
    'Twice', REASON_FPC);
  // Mit eigenem Modus ist Result belegt.
  AssertFix(InUnit('{$IFDEF FPC}{$mode objfpc}{$ENDIF}', BODY), 'Twice :=',
    'Twice', InUnit('{$IFDEF FPC}{$mode objfpc}{$ENDIF}',
    ['function Twice(X: Integer): Integer;', 'begin', '  Result := 2 * X;',
     'end;']));
end;

procedure TTestRdxFuncNameFix.Nested_Routine_NoHelp;
begin
  // In Inner ist Result das Ergebnis von Inner, nicht von Outer.
  AssertNoHelp(InUnit('', ['function Outer: Integer;',
    '  function Inner: Integer;', '  begin', '    Outer := 3;',
    '    Result := 2;', '  end;', 'begin', '  Result := Inner;', 'end;']),
    'Outer := 3', 'Outer', REASON_OTHER);
  // Eine Prozedur hat kein Ergebnis.
  AssertNoHelp(InUnit('', ['procedure Proc;', 'begin', '  Proc := 1;',
    'end;']), 'Proc := 1', 'Proc', 'Proc');
end;

procedure TTestRdxFuncNameFix.Shadowing_Local_NoHelp;
begin
  AssertNoHelp(InUnit('', ['function Shadow: Integer;', 'var',
    '  Shadow: Integer;', 'begin', '  Shadow := 5;', 'end;']),
    'Shadow := 5', 'Shadow', REASON_SHADOW);
end;

procedure TTestRdxFuncNameFix.With_Before_Line_NoHelp;
begin
  AssertNoHelp(InFunc('Total', ['  with Obj do', '    Foo := 1;',
    '  Total := 2;']), 'Total := 2', 'Total', REASON_WITH);
end;

{$IFNDEF FPC}

// ---- Fixture 2 (nur Delphi) ----

procedure RunDetector(AKind: TFindingKind; Root: TAstNode; const Path: string;
  Results: TObjectList<TLeakFinding>);
begin
  TFunctionNameResultDetector.AnalyzeUnit(Root, Path, Results);
end;

// Der erste Fund AKind des echten Detektors, geplant ueber den Einstieg
// des Anbieters und angewandt; bei Ablehnung '' und der Grund in AReason.
function FixFirst(const ASource: string; out AReason: string): string;
var
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  Result := '';
  Seen := DetectSource('rdx_fn_', ASource, fkFunctionNameAsResult,
    RunDetector);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet');
  O := PlanFixIn(ASource, 't.pas', fkFunctionNameAsResult, Seen[0]);
  AReason := O.Reason;
  if O.Enabled then
    Result := Apply(ASource, O.Edits);
end;

function CountOf(const ASource: string; AKind: TFindingKind): Integer;
begin
  Result := Length(DetectSource('rdx_fn_', ASource, AKind, RunDetector));
end;

procedure TTestRdxFuncNameFixDetector.Detector_Getter_RoundTrip;
var
  Src, Fixed, R : string;
begin
  Src := InUnit('', ['function TList.GetCount: Integer;', 'begin',
    '  GetCount := FCount;', 'end;']);
  Fixed := FixFirst(Src, R);
  Assert.AreEqual(InUnit('', ['function TList.GetCount: Integer;', 'begin',
    '  Result := FCount;', 'end;']), Fixed, R);
  Assert.AreEqual<Integer>(0, CountOf(Fixed, fkFunctionNameAsResult),
    'der Detektor schweigt danach');
end;

procedure TTestRdxFuncNameFixDetector.Detector_Accumulator_ReadStays;
var
  Src, Fixed, R : string;
begin
  // Nur die eine Zeile: 'Total := 0' ist der erste Fund; die Zeile mit
  // dem Lesen behaelt ihren SCA205-Fund (Absicht offen, keine Hilfe).
  Src := InFunc('Total', ['  Total := 0;', '  Total := Total + 1;']);
  Assert.AreEqual<Integer>(1, CountOf(Src, fkFunctionNameRecursion));
  Fixed := FixFirst(Src, R);
  Assert.AreEqual(InFunc('Total', ['  Result := 0;', '  Total := Total + 1;']),
    Fixed, R);
  Assert.AreEqual<Integer>(1, CountOf(Fixed, fkFunctionNameAsResult),
    'die zweite Zuweisung bleibt ein eigener Fund');
  Assert.AreEqual<Integer>(1, CountOf(Fixed, fkFunctionNameRecursion),
    'SCA205 bleibt');
end;

procedure TTestRdxFuncNameFixDetector.Detector_CatalogExample;
var
  Meta : TRuleMeta;
  Bad, Good, R : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkFunctionNameAsResult);
  Bad := InUnit('', [CatalogText(Meta.BadExample)]);
  Good := InUnit('', [CatalogText(Meta.GoodExample)]);
  Assert.AreEqual(Good, FixFirst(Bad, R), R);
end;

procedure TTestRdxFuncNameFixDetector.Adapter_Without_Lines_NoHelp;
var
  Finding : TLeakFinding;
  O       : TRdxFixOutcome;
begin
  Finding := TLeakFinding.New('t.pas', '', 1, Msg('GetCount'),
    fkFunctionNameAsResult);
  try
    O := TRdxFixTable.FixFor(nil, nil, Finding, nil);
    Assert.IsFalse(O.Enabled);
    Assert.IsTrue(O.Reason <> '', 'ein Grund steht da');
    Assert.AreEqual<Integer>(0, Length(O.Edits));
  finally
    Finding.Free;
  end;
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxFuncNameFix);
{$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxFuncNameFixDetector);
{$ENDIF}

end.

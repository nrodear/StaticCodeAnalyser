unit uTestRoutineResultAssigned;

// Tests fuer den TRoutineResultAssignedDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRoutineResultAssigned = class
  public
    // ---- Positive Varianten ------------------------------------------------
    [Test] procedure FunctionWithoutResult_Reported;
    [Test] procedure FunctionWithUnrelatedAssign_Reported;

    // ---- Negative Varianten / Guards --------------------------------------
    [Test] procedure FunctionWithResult_NoFinding;
    [Test] procedure FunctionWithFunctionNameAssign_NoFinding;
    [Test] procedure FunctionWithExit_NoFinding;
    [Test] procedure FunctionWithRaise_NoFinding;
    [Test] procedure FunctionWithRaiseHelper_NoFinding;
    [Test] procedure FunctionWithResultMethodCall_NoFinding;
    // Real-World 2026-06-26: 'with Result do begin Field := ... end' setzt
    // Result (Parser legt with-Target als nkCall 'Result' ab).
    [Test] procedure FunctionWithResultViaWith_NoFinding;
    [Test] procedure Procedure_NoFinding;
    [Test] procedure AbstractFunction_NoFinding;
    [Test] procedure ForwardFunction_NoFinding;
    [Test] procedure InterfaceMethodDecl_NoFinding;
    [Test] procedure ClassMethodDecl_NoFinding;
    [Test] procedure AbsoluteResultAlias_NoFinding;
    [Test] procedure RecordResult_FieldAssign_NoFinding;
    [Test] procedure ArrayResult_IndexAssign_NoFinding;
    [Test] procedure FnNameDotField_NoFinding;
    [Test] procedure TryGetValuePassesResult_NoFinding;
    [Test] procedure TryStrToIntPassesResult_NoFinding;
    [Test] procedure CallPassesResultFollowedByOther_NoFinding;
    [Test] procedure TypecastResultLhs_NoFinding;
    [Test] procedure UnrelatedVarSimilarName_StillReported;
    [Test] procedure NestedRoutine_OuterResultAssigned_NoFinding;
    [Test] procedure NestedFunctionWithoutResult_NotAnalyzed_NoFinding;

    // ---- Finding-Inhalt ----------------------------------------------------
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestRoutineResultAssigned.AbsoluteResultAlias_NoFinding;
// FP-Fix (Real-World 2026-06-28): 'X: T absolute Result' - Schreibzugriffe via
// Alias X gehen an den Result-Slot, 'Result' steht nie auf einer LHS.
const SRC =
  'unit t; implementation'#13#10 +
  'function Pack(a, b: Word): Cardinal;'#13#10 +
  'var Bits: Cardinal absolute Result;'#13#10 +
  'begin'#13#10 +
  '  Bits := (a shl 16) or b;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned),
    'absolute-Result-Alias schreibt den Return-Slot - kein unassigned');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.FunctionWithoutResult_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Integer;'#13#10 +
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.FunctionWithUnrelatedAssign_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Integer;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin x := 42; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.FunctionWithResult_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Integer;'#13#10 +
  'begin Result := 42; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.FunctionWithFunctionNameAssign_NoFinding;
// Pascal-Stil: `<funcname> := value` ist auch valide.
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Integer;'#13#10 +
  'begin Foo := 42; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.FunctionWithExit_NoFinding;
// Exit(value) wird vom Parser als nkExit gespeichert (Argument verworfen).
// Konservativ: jedes Exit deaktiviert das Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo(x: Integer): Integer;'#13#10 +
  'begin if x > 0 then Exit(x); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.FunctionWithRaise_NoFinding;
// Function die immer wirft braucht kein Result.
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Integer;'#13#10 +
  'begin raise Exception.Create(''not implemented''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.FunctionWithRaiseHelper_NoFinding;
// Regression delphimvcframework Serializer-Stubs (40+ FPs):
// Functions die ueber Helper-Aufruf raisen ('RaiseNotImplemented;',
// 'Abort;', 'RaiseLastOSError;') zaehlen wie nkRaise.
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: string;'#13#10 +
  'begin RaiseNotImplemented; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned),
    'RaiseNotImplemented im Body = semantisch raise, kein Result noetig');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.FunctionWithResultMethodCall_NoFinding;
// Regression DUnitX.Utils TPropInfoExt.NameFld:
//   function NameFld: TTypeInfoFieldAccessor;
//   begin Result.SetData(@NameLength); end;
// Method-Call AM Result setzt es semantisch (record-Init-Pattern).
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: TFoo;'#13#10 +
  'begin Result.SetData(42); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned),
    'Result.<method>(args) ist semantisch ein Result-write');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.FunctionWithResultViaWith_NoFinding;
// Regression Alcinoe TALFBXClientSQLParam.Create-Stil:
//   function Make: TPoint;
//   begin with Result do begin X := 1; Y := 2; end; end;
// 'with Result do' setzt Result-Felder; der Parser legt das with-Target
// als nkCall mit Name='Result' ab -> als Result-write werten.
const SRC =
  'unit t; implementation'#13#10 +
  'function Make: TPoint;'#13#10 +
  'begin'#13#10 +
  '  with Result do'#13#10 +
  '  begin'#13#10 +
  '    X := 1;'#13#10 +
  '    Y := 2;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned),
    '''with Result do'' ist semantisch ein Result-write');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.Procedure_NoFinding;
// Procedure hat keinen Return-Type -> nicht relevant.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.AbstractFunction_NoFinding;
// `function ...; virtual; abstract;` hat keinen Body.
const SRC =
  'unit t; interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  function Bar: Integer; virtual; abstract;'#13#10 +
  'end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.ForwardFunction_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Integer; forward;'#13#10 +
  'function Foo: Integer;'#13#10 +
  'begin Result := 1; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.InterfaceMethodDecl_NoFinding;
// Interface-Methoden haben keinen Body - die Implementierung kommt in
// der implementierenden Klasse. Frueher FP, jetzt durch HasBodyStatement
// abgefangen.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  IFoo = interface'#13#10 +
  '    function GetServiceNameSuffix: string;'#13#10 +
  '    function GetCount: Integer;'#13#10 +
  '    procedure SetActive(Value: Boolean);'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.ClassMethodDecl_NoFinding;
// Klassen-Method-Deklarationen im Typ-Section haben auch keinen Body -
// derselbe Mechanismus.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    function Compute(x: Integer): Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'function TFoo.Compute(x: Integer): Integer;'#13#10 +
  'begin Result := x * 2; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.RecordResult_FieldAssign_NoFinding;
// Spiegelt den realen FP aus uLexer.MakeTok: Function liefert Record und
// weist Result feldweise zu. Frueher als "kein Result-Assign" geflaggt.
const SRC =
  'unit t; interface'#13#10 +
  'type TToken = record Kind: Integer; Value: string; end;'#13#10 +
  'function MakeTok(K: Integer; const V: string): TToken;'#13#10 +
  'implementation'#13#10 +
  'function MakeTok(K: Integer; const V: string): TToken;'#13#10 +
  'begin'#13#10 +
  '  Result.Kind  := K;'#13#10 +
  '  Result.Value := V;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.ArrayResult_IndexAssign_NoFinding;
// Array-Return: Result[i] := X.
const SRC =
  'unit t; implementation'#13#10 +
  'function BuildArray: TArray<Integer>;'#13#10 +
  'begin'#13#10 +
  '  SetLength(Result, 3);'#13#10 +
  '  Result[0] := 1;'#13#10 +
  '  Result[1] := 2;'#13#10 +
  '  Result[2] := 3;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.FnNameDotField_NoFinding;
// Klassischer Pascal-Stil: <FnName>.Field := X statt Result.Field := X.
const SRC =
  'unit t; implementation'#13#10 +
  'function MakeTok: TToken;'#13#10 +
  'begin'#13#10 +
  '  MakeTok.Kind  := 1;'#13#10 +
  '  MakeTok.Value := ''hi'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.TryGetValuePassesResult_NoFinding;
// Original-FP aus horse-master/Horse.Core.Param.pas:
// Result wird via `var`-Parameter an TryGetValue uebergeben - das ist
// eine Zuweisung von der Callee-Seite, der Detector muss sie erkennen.
const SRC =
  'unit t; implementation'#13#10 +
  'function GetItem(const AKey: string): string;'#13#10 +
  'begin'#13#10 +
  '  FParams.TryGetValue(AKey, Result);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.TryStrToIntPassesResult_NoFinding;
// RTL-Standard: TryStrToInt schreibt das Ergebnis ueber var-Param.
const SRC =
  'unit t; implementation'#13#10 +
  'function Parse(const S: string): Integer;'#13#10 +
  'begin'#13#10 +
  '  TryStrToInt(S, Result);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.CallPassesResultFollowedByOther_NoFinding;
// Result als nicht-letztes Argument.
const SRC =
  'unit t; implementation'#13#10 +
  'function Compute: Integer;'#13#10 +
  'begin'#13#10 +
  '  DoWork(Result, ''logKey'', 42);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.TypecastResultLhs_NoFinding;
// FP-Fix (Real-World 2026-06-23): Result wird per Typecast/Pointer-Cast als
// LHS zugewiesen - `TColorRec(Result).R := ...`. Result steht IN den Klammern,
// der Prefix-Check verfehlt es; ContainsIdentifier(LHS,'result') faengt es.
const SRC =
  'unit t; implementation'#13#10 +
  'function ToColor(r, g, b: Byte): Integer;'#13#10 +
  'begin'#13#10 +
  '  TColorRec(Result).R := r;'#13#10 +
  '  TColorRec(Result).G := g;'#13#10 +
  '  TColorRec(Result).B := b;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned),
    'Typecast-Result-LHS (TColorRec(Result).R :=) zaehlt als Result-Zuweisung');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.UnrelatedVarSimilarName_StillReported;
// `ResultCache` ist NICHT `Result` - Word-Boundary muss verhindern, dass
// das Finding faelschlich verschwindet.
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Integer;'#13#10 +
  'var ResultCache: Integer;'#13#10 +
  'begin'#13#10 +
  '  DoWork(ResultCache);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRoutineResultUnassigned));
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.NestedRoutine_OuterResultAssigned_NoFinding;
// Root-Cause-Fix (Parser nested routine): aeussere Funktion mit lokaler
// nested procedure VOR dem begin. Frueher fraß ParseLocalVarSection die
// nested routine als Pseudo-Local-Var und ParseMethodImpl interpretierte
// den NESTED-Body als Outer-Body -> der echte Outer-`Result :=` ging
// verloren -> FP. Jetzt wird die nested routine als eigenes nkMethod-Child
// geparst, der Outer-Body bleibt erhalten.
const SRC =
  'unit t; implementation'#13#10 +
  'function Outer: Integer;'#13#10 +
  'var i: Integer;'#13#10 +
  '  procedure Helper;'#13#10 +
  '  begin'#13#10 +
  '    i := 1;'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  Helper;'#13#10 +
  '  Result := i;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned),
    'Outer-Body Result-Assign darf durch nested routine nicht verloren gehen');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.NestedFunctionWithoutResult_NotAnalyzed_NoFinding;
// Nested routines werden geparst (damit der Outer-Body gefunden wird), aber
// bewusst NICHT als analysierbare Methoden im AST belassen (siehe
// ParseMethodImpl: sonst feuern SCA148/176/166/121 massenhaft auf nested
// Helpern; der Smell selbst meldet der lexische uNestedRoutines-Detektor).
// Daher: die nested Inner-Function OHNE Result-Assign erzeugt KEIN SCA121.
// Outer weist Result zu -> ebenfalls sauber -> insgesamt 0.
const SRC =
  'unit t; implementation'#13#10 +
  'function Outer: Integer;'#13#10 +
  '  function Inner: Integer;'#13#10 +
  '  begin'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  Result := Inner;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned),
    'nested routines werden nicht standalone analysiert; Outer ist sauber');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Integer;'#13#10 +
  'begin end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkRoutineResultUnassigned then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkRoutineResultUnassigned finding expected');
    Assert.AreEqual(fkRoutineResultUnassigned, Hit.Kind);
    Assert.AreEqual(lsError,                   Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRoutineResultAssigned);

end.

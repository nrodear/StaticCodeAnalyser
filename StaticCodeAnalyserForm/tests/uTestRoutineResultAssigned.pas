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
    // Real-World FP-Audit 2026-07-10: out/var-Param in Bedingung + @Result
    [Test] procedure ResultOutParamInIfCondition_NoFinding;
    [Test] procedure ResultAddressTaken_NoFinding;
    // Gegenprobe: reiner Result-Read in Klammer-Gruppierung ist KEINE Zuweisung
    [Test] procedure ResultReadInParenCondition_StillReported;
    // Track B2 (2026-07-12): Label-Target 'done: Result := X' parst jetzt
    [Test] procedure LabelTargetResultAssign_NoFinding;
    [Test] procedure LabelTargetNoResultAssign_StillReported;
    // Recharakterisierung after30 (2026-07-12): managed-Return + leerer Body
    [Test] procedure ManagedStringReturnEmptyBody_NoFinding;
    [Test] procedure ManagedInterfaceReturnEmptyBody_NoFinding;
    // KRITISCHE Gegenprobe: managed-Return MIT Statements bleibt „forgot Result:="
    [Test] procedure ManagedStringReturnWithStatements_StillReported;

    // ---- 30%-Real-World-Audit 2026-07-31: vier FP-Klassen + TP-Gegenproben --
    // (1) asm-/assembler-Routinen: Result kommt per Register
    [Test] procedure AsmBlockInBody_NoFinding;
    [Test] procedure AsmOnlyInCommentOrString_StillReported;
    [Test] procedure AssemblerDirective_NoFinding;
    [Test] procedure StdcallDirective_StillReported;
    // (2) Result als var/out-Argument hinter Keyword-Member (Stream.Read)
    [Test] procedure ResultAsVarArgViaKeywordMember_NoFinding;
    [Test] procedure ResultReadInParen_FileHarness_StillReported;
    // (3) Deklaration ohne eigenen Rumpf (Parser zieht fremdes var-Gelaende an)
    [Test] procedure DeclarationWithoutOwnBody_NoFinding;
    [Test] procedure VarSectionWithRealBody_StillReported;
    // (4) IFDEF-Twin im if-Kopf (zweifaches 'then' nach Direktiven-Strip)
    [Test] procedure IfdefThenTwinInCondition_NoFinding;
    [Test] procedure BalancedIfThen_StillReported;
    // Review-Fund 2026-07-31 (Z.922): Scan-Bereich klammert nested routines aus
    [Test] procedure NestedRoutineAssignsResult_OuterStillReported;
    [Test] procedure NestedRoutinePresent_OuterVarArgGate_NoFinding;

    // ---- Finding-Inhalt ----------------------------------------------------
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  uAstNode, uParser2, uRoutineResultAssigned,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

// ---------------------------------------------------------------------------
// Datei-Harness (2026-07-31). SCA121 haengt in TFindingHelper.FindingsOf, also
// im IN-MEMORY-AST-Buendel mit dem Platzhalternamen 'sample.pas' - dort gibt es
// keine lesbare Datei, und die vier neuen Quelltext-Gates (asm-Rumpf, Result als
// Call-Argument, IFDEF-Twin) sind damit inaktiv. Ein Test dafuer waere im
// AST-Harness vakuum-gruen. Dieser lokale Harness schreibt den Quelltext in eine
// temporaere Datei, parst sie ueber denselben ParseFile-Pfad wie die Produktion
// und ruft NUR SCA121 auf - damit laufen die Gates echt.
function FindingsOnFile(const Source: string): TObjectList<TLeakFinding>;
var
  Parser   : TParser2;
  Root     : TAstNode;
  TempPath : string;
  SL       : TStringList;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  TempPath := TPath.Combine(TPath.GetTempPath,
    'sca121_' + TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '')
                  .Replace('-', '') + '.pas');
  SL := TStringList.Create;
  try
    SL.Text := Source;
    SL.SaveToFile(TempPath, TEncoding.UTF8);
  finally
    SL.Free;
  end;
  try
    Parser := TParser2.Create;
    try
      Root := Parser.ParseFile(TempPath);
      try
        TRoutineResultAssignedDetector.AnalyzeUnit(Root, TempPath, Result);
      finally
        Root.Free;
      end;
    finally
      Parser.Free;
    end;
  finally
    if TFile.Exists(TempPath) then
      TFile.Delete(TempPath);
  end;
end;

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

// ============================================================
// Real-World FP-Audit 2026-07-10 (SCA121 68% FP, error-level)
// ============================================================

procedure TTestRoutineResultAssigned.ResultOutParamInIfCondition_NoFinding;
// 'if Supports(x, IFoo, Result) then' - Result ist der out-Param des Calls IN
// der Bedingung (nkIfStmt.TypeRef, kein nkCall) -> vorher verfehlt -> FP.
const SRC =
  'unit t; implementation'#13#10 +
  'function GetFoo(const x: IInterface): Boolean;'#13#10 +
  'begin'#13#10 +
  '  if Supports(x, IFoo, Result) then'#13#10 +
  '    DoLog;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned),
    'Supports(..., Result) in der Bedingung schreibt Result (out-Param)');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.ResultAddressTaken_NoFinding;
// 'p := @Result' - die Adresse wird genommen und der Callee schreibt durch den
// Zeiger; kein direktes 'Result :=' -> vorher FP.
const SRC =
  'unit t; implementation'#13#10 +
  'function Build: Integer;'#13#10 +
  'var p: Pointer;'#13#10 +
  'begin'#13#10 +
  '  p := @Result;'#13#10 +
  '  FillIt(p);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned),
    '@Result -> Adresse genommen, Callee fuellt Result');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.ResultReadInParenCondition_StillReported;
// Gegenprobe: '(Result > 0)' ist eine reine Klammer-Gruppierung (Read), KEINE
// Zuweisung und kein Call-Argument -> der Guard darf hier NICHT unterdruecken.
const SRC =
  'unit t; implementation'#13#10 +
  'function Compute: Integer;'#13#10 +
  'begin'#13#10 +
  '  if (Result > 0) then'#13#10 +
  '    DoLog;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkRoutineResultUnassigned) >= 1,
    'reiner Result-Read in (Result > 0) ist keine Zuweisung - bleibt Fund');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.LabelTargetResultAssign_NoFinding;
// Track B2 (2026-07-12): 'done: Result := X' - das Label-Target. Vor dem Fix
// machte ParseCallOrAssign nkCall('done') + SkipToSemicolon verschluckte die
// markierte Zuweisung 'Result := X' -> Result galt als nie zugewiesen (FP).
// Jetzt wird das ':' konsumiert und die markierte Anweisung normal geparst.
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo(x: Integer): Integer;'#13#10 +
  'label done;'#13#10 +
  'begin'#13#10 +
  '  done: Result := x + 1;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned),
    'Result-Zuweisung hinter Label-Target zaehlt - kein unassigned');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.LabelTargetNoResultAssign_StillReported;
// TP-Gegenprobe: Label-Target OHNE Result-Zuweisung ('done: Beep;') -> Result
// bleibt unzugewiesen -> Fund bleibt. Sichert ab, dass der Label-Parse nicht
// faelschlich eine Result-Zuweisung vortaeuscht.
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo(x: Integer): Integer;'#13#10 +
  'label done;'#13#10 +
  'begin'#13#10 +
  '  done: Beep;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkRoutineResultUnassigned) >= 1,
    'Label-Target ohne Result-Zuweisung bleibt unassigned-Fund');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.ManagedStringReturnEmptyBody_NoFinding;
// Recharakterisierung after30: managed-Return (string, auto-init '') + leerer
// Body -> Return NICHT "undefined", sondern definierter Leerwert -> kein SCA121.
const SRC =
  'unit t; implementation'#13#10 +
  'function GetName: string;'#13#10 +
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned),
    'string-Return (auto '''') + leerer Body -> kein undefined-Return-Fund');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.ManagedInterfaceReturnEmptyBody_NoFinding;
// managed-Return (Interface, auto-nil) + leerer Body -> definierter Leerwert nil.
const SRC =
  'unit t; implementation'#13#10 +
  'function GetLogger: ILogger;'#13#10 +
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned),
    'Interface-Return (auto-nil) + leerer Body -> kein undefined-Return-Fund');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.ManagedStringReturnWithStatements_StillReported;
// KRITISCHE TP-Gegenprobe: managed-Return ABER Body hat Statements (rechnet,
// vergisst aber Result:=) -> echter "forgot Result:="-Bug -> bleibt Fund. Der
// managed-Skip darf NUR bei EFFEKTIV LEEREM Body greifen.
const SRC =
  'unit t; implementation'#13#10 +
  'function BuildName(a, b: string): string;'#13#10 +
  'var tmp: string;'#13#10 +
  'begin'#13#10 +
  '  tmp := a + b;'#13#10 +
  '  DoLog(tmp);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkRoutineResultUnassigned) >= 1,
    'managed-Return mit Statements (Result nie gesetzt) bleibt echter SCA121-Bug');
  finally F.Free; end;
end;

// ============================================================
// 30%-Real-World-Audit 2026-07-31 (SCA121 156 Funde, 35% FP)
// ============================================================

procedure TTestRoutineResultAssigned.AsmBlockInBody_NoFinding;
// FP-Klasse "asm-/assembler-Routinen" (jvWinDialogs.ExecuteShellMessageBox):
// gemischter Pascal+asm-Rumpf - der asm-Block setzt Result per Register
// ('mov Result, EAX'). uParser2 emittiert fuer 'asm ... end' KEINE Knoten, der
// AST hat also keinerlei Evidenz -> nur das Quelltext-Gate kann das sehen.
const SRC =
  'unit t; implementation'#13#10 +
  'function Shell(a: Integer): Integer;'#13#10 +
  'begin'#13#10 +
  '  asm'#13#10 +
  '    mov ecx, a'#13#10 +
  '    mov Result, ecx'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsOnFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned),
    'asm-Block im Rumpf setzt Result per Register - kein unassigned');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.AsmOnlyInCommentOrString_StillReported;
// TP-Gegenprobe zum asm-Gate: 'asm' NUR im Kommentar und im Stringliteral -
// beides blendet CleanRangeText aus, es gibt keinen echten asm-Block. Der Fund
// muss bleiben (sonst waere das Gate ein Wort-Suchlauf ohne Kontext).
const SRC =
  'unit t; implementation'#13#10 +
  'function Compute: Integer;'#13#10 +
  'begin'#13#10 +
  '  // asm waere hier nur Prosa'#13#10 +
  '  DoLog(''asm'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsOnFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkRoutineResultUnassigned) >= 1,
    'asm in Kommentar/String ist kein asm-Block - Fund bleibt');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.AssemblerDirective_NoFinding;
// FP-Klasse "asm-/assembler-Routinen", TypeRef-Pfad (HexDump.LongMulDiv):
// die 'assembler'-Direktive landet als ';assembler' im TypeRef. Der Fall ist
// SYNTHETISCH mit Pascal-Rumpf gebaut, damit er genau dieses Gate isoliert -
// die reale Form hat einen asm-Rumpf und wird zusaetzlich vom nkBlock-Gate
// gedeckt.
const SRC =
  'unit t; implementation'#13#10 +
  'function LongMulDiv(a, b: Integer): Integer; assembler;'#13#10 +
  'begin'#13#10 +
  '  DoLog(a);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned),
    '''assembler''-Direktive -> Result kommt per Register');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.StdcallDirective_StillReported;
// TP-Gegenprobe: NUR 'assembler' darf das Gate ausloesen - eine gewoehnliche
// Calling-Convention (stdcall) sitzt im selben TypeRef-Direktiven-Teil und
// darf den Fund nicht stillstellen.
const SRC =
  'unit t; implementation'#13#10 +
  'function Compute(a: Integer): Integer; stdcall;'#13#10 +
  'begin'#13#10 +
  '  DoLog(a);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkRoutineResultUnassigned) >= 1,
    'stdcall ist keine asm-Routine - Fund bleibt');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.ResultAsVarArgViaKeywordMember_NoFinding;
// FP-Klasse "Result als var/out-Argument" (JvTMTL.ReadInt):
// 'Stream.Read(Result, SizeOf(Result))' schreibt Result ueber einen
// var-Parameter. 'Read' ist ein Keyword-Token - ParsePrimary bricht die
// Suffix-Kette hinter dem Punkt ab, die Argumentliste landet nie im
// nkCall-Namen. Die AST-Guards (CallPassesResultAsArg /
// AnyNodeStringWritesResult) sehen davon nichts, nur der Quelltext.
const SRC =
  'unit t; implementation'#13#10 +
  'function ReadInt(Stream: TStream): Integer;'#13#10 +
  'begin'#13#10 +
  '  Stream.Read(Result, SizeOf(Result));'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsOnFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned),
    'Result als var-Argument von Stream.Read ist eine Zuweisung');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.ResultReadInParen_FileHarness_StillReported;
// TP-Gegenprobe zum Call-Argument-Gate im DATEI-Harness: '(Result > 0)' ist
// reine Klammer-Gruppierung (Read), kein Call-Argument - vor der Klammer steht
// kein Identifier-Zeichen. Der Fund muss bleiben.
const SRC =
  'unit t; implementation'#13#10 +
  'function Compute: Integer;'#13#10 +
  'begin'#13#10 +
  '  if (Result > 0) then'#13#10 +
  '    DoLog;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsOnFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkRoutineResultUnassigned) >= 1,
    'reiner Result-Read in Klammern ist kein Call-Argument - Fund bleibt');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.DeclarationWithoutOwnBody_NoFinding;
// FP-Klasse "Interface-Deklaration statt Implementation geankert"
// (mormot.lib.gssapi ServerForceKeytab Z.616): eine Routinen-DEKLARATION ohne
// Rumpf; ParseMethodImpl zieht die FOLGENDE unit-level var-Sektion als
// vermeintlich lokale Deklaration an den Knoten, die nkLocalVar-Kinder liessen
// HasBodyStatement True werden. Ohne begin..end gibt es keine Beweisgrundlage.
const SRC =
  'unit t; implementation'#13#10 +
  'function DeclOnly(const a: string): Boolean;'#13#10 +
  #13#10 +
  'var'#13#10 +
  '  gFlag: Boolean;'#13#10 +
  #13#10 +
  'function RealOne: Boolean;'#13#10 +
  'begin'#13#10 +
  '  Result := True;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned),
    'Deklaration ohne eigenen begin..end-Rumpf ist kein Fund');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.VarSectionWithRealBody_StillReported;
// TP-Gegenprobe zum nkBlock-Gate: dieselbe Form MIT eigenem Rumpf - lokale
// var-Sektion, Statements, aber kein Result. Bleibt der echte "forgot
// Result:="-Bug.
const SRC =
  'unit t; implementation'#13#10 +
  'function Broken(const a: string): Boolean;'#13#10 +
  'var'#13#10 +
  '  gFlag: Boolean;'#13#10 +
  'begin'#13#10 +
  '  gFlag := a <> '''';'#13#10 +
  '  DoLog(gFlag);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkRoutineResultUnassigned) >= 1,
    'eigener Rumpf ohne Result-Zuweisung bleibt echter SCA121-Bug');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.IfdefThenTwinInCondition_NoFinding;
// FP-Klasse "IFDEF-Twin im if-Kopf" (JvMemDS.FindFieldData Z.638): der Lexer
// skippt Direktiven wie Kommentare, dadurch stehen ZWEI 'then' zu EINEM 'if'
// im Token-Strom. Der zweite Bedingungsrest wird als eigene Anweisung geparst,
// SkipToSemicolon frisst den then-Zweig und ParseBlock bricht am 'else' ab -
// BEIDE Result-Zuweisungen verschwinden aus dem AST.
const SRC =
  'unit t; implementation'#13#10 +
  'function FindFieldData(Buffer: Pointer): Pointer;'#13#10 +
  'var'#13#10 +
  '  Index: Integer;'#13#10 +
  'begin'#13#10 +
  '  Index := 0;'#13#10 +
  '  if (Index >= 0) and'#13#10 +
  '    {$IFDEF COMPILER4_UP}'#13#10 +
  '    (Index < 10) then'#13#10 +
  '    {$ELSE}'#13#10 +
  '    (Index < 20) then'#13#10 +
  '    {$ENDIF}'#13#10 +
  '    Result := Buffer'#13#10 +
  '  else'#13#10 +
  '    Result := nil;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsOnFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned),
    'IFDEF-Twin im Bedingungskopf: Result wird in beiden Zweigen gesetzt');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.BalancedIfThen_StillReported;
// TP-Gegenprobe zum Twin-Gate: normales if/then/else - 'then' und 'if' sind
// ausgeglichen, das Gate darf NICHT feuern.
const SRC =
  'unit t; implementation'#13#10 +
  'function Compute(a: Integer): Integer;'#13#10 +
  'begin'#13#10 +
  '  if a > 0 then'#13#10 +
  '    DoLog'#13#10 +
  '  else'#13#10 +
  '    DoOther;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsOnFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkRoutineResultUnassigned) >= 1,
    'ausgeglichenes if/then ist kein IFDEF-Twin - Fund bleibt');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.NestedRoutineAssignsResult_OuterStillReported;
// Pre-Build-Review-Fund 2026-07-31 (uRoutineResultAssigned.pas Z.922): der
// Quelltext-Bereich einer Routine reicht bis zum naechsten TOP-LEVEL-Kopf und
// enthielt damit auch den Deklarationsteil samt der verschachtelten Routinen.
// Das `Inc(Result)` unten gehoert der NESTED function Inner - vor dem Fix
// stellte es ueber SourceWordIsCallArg den echten Error-Tier-Fund der aeusseren
// Funktion still (Real-World: TES5Edit Sniff/Proc/ProcFindDrawCalls.pas:77).
// Der Fix schneidet die nkNestedRange-Spans aus dem Scan heraus.
// OHNE den Fix ist dieser Test ROT (0 statt >= 1).
const SRC =
  'unit t; implementation'#13#10 +
  'function Outer(a: Integer): Integer;'#13#10 +
  #13#10 +
  '  function Inner(b: Integer): Integer;'#13#10 +
  '  begin'#13#10 +
  '    Result := b;'#13#10 +
  '    Inc(Result);'#13#10 +
  '  end;'#13#10 +
  #13#10 +
  'begin'#13#10 +
  '  DoLog(Inner(a));'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsOnFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkRoutineResultUnassigned) >= 1,
    'Result der nested routine darf den Fund der aeusseren Funktion nicht stillstellen');
  finally F.Free; end;
end;

procedure TTestRoutineResultAssigned.NestedRoutinePresent_OuterVarArgGate_NoFinding;
// Gegenprobe zum Fix des Review-Funds Z.922: die nested routine wird
// ausgeschnitten, der EIGENE Rumpf aber weiterhin voll gescannt. Hier steht
// `Stream.Read(Result, SizeOf(Result))` im Rumpf der AEUSSEREN Funktion -
// 'Read' ist ein Keyword-Token, ParsePrimary bricht hinter dem Punkt ab, der
// AST sieht nur nkCall('Stream'), also kann NUR das Quelltext-Gate greifen.
// Wuerde der Fix den Bereich zu grosszuegig ausschneiden (oder die Gates
// pauschal abschalten, sobald eine nested routine existiert), waere dieser
// Test ROT.
const SRC =
  'unit t; implementation'#13#10 +
  'function Outer(Stream: TStream): Integer;'#13#10 +
  #13#10 +
  '  function Inner(b: Integer): Integer;'#13#10 +
  '  begin'#13#10 +
  '    Result := b;'#13#10 +
  '  end;'#13#10 +
  #13#10 +
  'begin'#13#10 +
  '  Stream.Read(Result, SizeOf(Result));'#13#10 +
  '  DoLog(Inner(1));'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsOnFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned),
    'Gate bleibt fuer den eigenen Rumpf aktiv, auch wenn eine nested routine existiert');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRoutineResultAssigned);

end.

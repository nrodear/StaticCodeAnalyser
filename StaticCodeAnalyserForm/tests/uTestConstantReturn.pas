unit uTestConstantReturn;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConstantReturn = class
  public
    [Test] procedure SameLiteralEveryPath_Reported;
    [Test] procedure DifferentLiterals_NotReported;
    [Test] procedure SingleAssignment_NotReported;
    [Test] procedure NonLiteralRhs_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // --- Escape-Scan (SCA151-FP-Paket 2026-08-27) --------------------------
    [Test] procedure ResultAsCallArgument_NotReported;
    [Test] procedure SetLengthOnResult_NotReported;
    [Test] procedure ResultInIfCondition_NotReported;
    [Test] procedure ResultInWhileCondition_NotReported;
    [Test] procedure ForResultLoopHeader_NotReported;
    [Test] procedure IndexedResultAssign_NotReported;
    // --- Exit-Literale -----------------------------------------------------
    [Test] procedure ExitWithDifferentLiteral_NotReported;
    [Test] procedure BareExitPlusConstantResult_StillReported;
    // --- Literal-Heuristik -------------------------------------------------
    [Test] procedure HexLikeIdentifierRhs_NotReported;
    [Test] procedure HexLiteralRhs_StillReported;
    // --- Wortgrenzen des Escape-Scans --------------------------------------
    [Test] procedure PlainConstantResult_StillReported;
    [Test] procedure DottedResultMember_StillReported;
    [Test] procedure DottedResultMemberInIfHead_StillReported;
    [Test] procedure ResultInStringLiteral_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestConstantReturn.SameLiteralEveryPath_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'function Timeout: Integer;'#13#10 +
  'begin'#13#10 +
  '  if Slow then'#13#10 +
  '    Result := 30'#13#10 +
  '  else'#13#10 +
  '    Result := 30;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkConstantReturn) >= 1);
  finally F.Free; end;
end;

procedure TTestConstantReturn.DifferentLiterals_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'function Timeout: Integer;'#13#10 +
  'begin'#13#10 +
  '  if Slow then Result := 30 else Result := 60;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstantReturn));
  finally F.Free; end;
end;

procedure TTestConstantReturn.SingleAssignment_NotReported;
// Eine einzige Result-Zuweisung -> trivial, kein Smell.
const SRC =
  'unit t; implementation'#13#10 +
  'function Timeout: Integer;'#13#10 +
  'begin'#13#10 +
  '  Result := 30;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstantReturn));
  finally F.Free; end;
end;

procedure TTestConstantReturn.NonLiteralRhs_NotReported;
// Variable/Konstante als RHS -> kein klares "always returns literal X".
const SRC =
  'unit t; implementation'#13#10 +
  'function Timeout: Integer;'#13#10 +
  'begin'#13#10 +
  '  if Slow then Result := DEFAULT_TIMEOUT else Result := DEFAULT_TIMEOUT;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstantReturn));
  finally F.Free; end;
end;

procedure TTestConstantReturn.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Integer;'#13#10 +
  'begin'#13#10 +
  '  if X then Result := 1 else Result := 1;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkConstantReturn then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkConstantReturn finding expected');
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

// === Escape-Scan =========================================================
// Alle sechs Faelle waren bis 2026-08-27 Funde ("always returns nil/-1/0"),
// obwohl der Rueckgabewert im Rumpf nachweislich veraendert wird. Sie decken
// je EINEN Einhaengepunkt des Scans ab; die Fixtures sind bewusst so knapp,
// dass genau ein Gate greifen kann.

procedure TTestConstantReturn.ResultAsCallArgument_NotReported;
// Result als var/out-Argument. Der Parser legt den vollen Argumenttext im
// nkCall.Name ab, dort steht 'Result' als eigenes Wort.
// Korpus-Klasse: CnWizUtils.pas:4450 (Supports(IModule, IOTAProjectGroup,
// Result)), mormot.core.text.pas:3010 (HexDisplayToBin(@tmp, @result, ...)).
const SRC =
  'unit t; implementation'#13#10 +
  'function GetOpts: IUnknown;'#13#10 +
  'begin'#13#10 +
  '  Result := nil;'#13#10 +
  '  Supports(FOwner, IUnknown, Result);'#13#10 +
  '  Result := nil;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstantReturn));
  finally F.Free; end;
end;

procedure TTestConstantReturn.SetLengthOnResult_NotReported;
// Dieselbe Mechanik wie oben, aber mit der haeufigsten Compiler-Magic-
// Routine: SetLength mutiert ihr erstes Argument.
const SRC =
  'unit t; implementation'#13#10 +
  'function GrowBuf: TBytes;'#13#10 +
  'begin'#13#10 +
  '  Result := nil;'#13#10 +
  '  SetLength(Result, 16);'#13#10 +
  '  Result := nil;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstantReturn));
  finally F.Free; end;
end;

procedure TTestConstantReturn.ResultInIfCondition_NotReported;
// Result in einer Bedingung gelesen -> er ist ein Akkumulator, nicht eine
// Konstante. Nachbau von mormot.core.text.pas:3010 GetNextItemHexa.
const SRC =
  'unit t; implementation'#13#10 +
  'function ParseHexa: Integer;'#13#10 +
  'begin'#13#10 +
  '  Result := 0;'#13#10 +
  '  if not HexToBin(FSrc, @Result, 8) then'#13#10 +
  '    Result := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstantReturn));
  finally F.Free; end;
end;

procedure TTestConstantReturn.ResultInWhileCondition_NotReported;
// while-Kopf: eigener Einhaengepunkt (nkWhileStmt.TypeRef), und im Gegensatz
// zum if-Kopf joint der Parser hier OHNE Blanks ('Result<3') - der Scan darf
// sich also nicht auf Leerzeichen als Wortgrenze verlassen.
const SRC =
  'unit t; implementation'#13#10 +
  'function CountDown: Integer;'#13#10 +
  'begin'#13#10 +
  '  Result := 0;'#13#10 +
  '  while Result < 3 do'#13#10 +
  '    Advance;'#13#10 +
  '  Result := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstantReturn));
  finally F.Free; end;
end;

procedure TTestConstantReturn.ForResultLoopHeader_NotReported;
// Suchidiom 'for Result := 0 to N': der Schleifenkopf ist KEIN nkAssign, die
// Laufvariable ist trotzdem der Rueckgabewert. Korpus:
// Alcinoe.QuickSortList.pas:726 IndexOfObject.
const SRC =
  'unit t; implementation'#13#10 +
  'function ScanSlots: Integer;'#13#10 +
  'begin'#13#10 +
  '  Result := -1;'#13#10 +
  '  for Result := 0 to 9 do'#13#10 +
  '    DoStep;'#13#10 +
  '  Result := -1;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstantReturn));
  finally F.Free; end;
end;

procedure TTestConstantReturn.IndexedResultAssign_NotReported;
// 'Result[0] := 1' landet als nkAssign mit Name 'Result[]' und fiel damit
// still durch IsResultLhs - die Funktion sah aus, als schriebe sie nur den
// nil-Default.
const SRC =
  'unit t; implementation'#13#10 +
  'function BuildPair: TBytes;'#13#10 +
  'begin'#13#10 +
  '  Result := nil;'#13#10 +
  '  Result[0] := 1;'#13#10 +
  '  Result := nil;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstantReturn));
  finally F.Free; end;
end;

// === Exit-Literale =======================================================

procedure TTestConstantReturn.ExitWithDifferentLiteral_NotReported;
// Nachbau von Alcinoe.FMX.Controls.pas:1902 IsAncestorOf: zweimal
// 'Result := False', dazwischen ein 'Exit(True)'. Der Exit-Wert gehoert in
// dieselbe Wertemenge, sonst meldet der Detektor "always returns False".
// Das nackte 'Exit;' in Zeile 2 des Rumpfs steht bewusst mit drin - es darf
// die Auswertung NICHT beeinflussen.
const SRC =
  'unit t; implementation'#13#10 +
  'function IsAncestorOf(AItem: TObject): Boolean;'#13#10 +
  'begin'#13#10 +
  '  Result := False;'#13#10 +
  '  if AItem = nil then Exit;'#13#10 +
  '  while AItem <> nil do'#13#10 +
  '  begin'#13#10 +
  '    if AItem = FRoot then Exit(True);'#13#10 +
  '    AItem := AItem.Parent;'#13#10 +
  '  end;'#13#10 +
  '  Result := False;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstantReturn));
  finally F.Free; end;
end;

procedure TTestConstantReturn.BareExitPlusConstantResult_StillReported;
// REGRESSIONSWAECHTER. Ein argumentloses 'Exit;' erzeugt denselben nkExit-
// Knoten wie 'Exit(x)', nur mit leerem TypeRef. Wer den leeren TypeRef als
// Skip-Grund ODER als Wert in der Menge behandelt, loescht 35 der 48 echten
// Funde im Korpus - der Fruehausstieg steht in fast jedem davon.
const SRC =
  'unit t; implementation'#13#10 +
  'function AlwaysZero(AFlag: Boolean): Integer;'#13#10 +
  'begin'#13#10 +
  '  Result := 0;'#13#10 +
  '  if AFlag then Exit;'#13#10 +
  '  Result := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkConstantReturn) >= 1,
    'nacktes Exit; darf den Fund nicht loeschen');
  finally F.Free; end;
end;

// === Literal-Heuristik ===================================================

procedure TTestConstantReturn.HexLikeIdentifierRhs_NotReported;
// 'Def' besteht nur aus Hex-Ziffern und galt darum als Zahl-Literal ->
// "always returns Def". Belegt an JclRegistry.pas:1015 RegReadIntegerDef
// und zehn Schwestern in derselben Unit.
const SRC =
  'unit t; implementation'#13#10 +
  'function ReadIntDef(Def: Integer): Integer;'#13#10 +
  'begin'#13#10 +
  '  if FOk then'#13#10 +
  '    Result := Def'#13#10 +
  '  else'#13#10 +
  '    Result := Def;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstantReturn));
  finally F.Free; end;
end;

procedure TTestConstantReturn.HexLiteralRhs_StillReported;
// Gegenprobe zur Haertung: MIT '$'-Praefix bleibt es ein Zahl-Literal.
const SRC =
  'unit t; implementation'#13#10 +
  'function MaskValue: Integer;'#13#10 +
  'begin'#13#10 +
  '  if FWide then'#13#10 +
  '    Result := $FF'#13#10 +
  '  else'#13#10 +
  '    Result := $FF;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkConstantReturn) >= 1,
    '$FF ist weiterhin ein Literal');
  finally F.Free; end;
end;

// === Wortgrenzen des Escape-Scans ========================================

procedure TTestConstantReturn.PlainConstantResult_StillReported;
// Der Rumpf ruft etwas auf, das mit dem Rueckgabewert nichts zu tun hat -
// der Escape-Scan darf daran nicht haengenbleiben.
const SRC =
  'unit t; implementation'#13#10 +
  'function DefaultTimeout: Integer;'#13#10 +
  'begin'#13#10 +
  '  Result := 30;'#13#10 +
  '  DoSomething;'#13#10 +
  '  Result := 30;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkConstantReturn) >= 1,
    'ohne jede Mutation bleibt es ein Fund');
  finally F.Free; end;
end;

procedure TTestConstantReturn.DottedResultMemberInIfHead_StillReported;
// Gegenpruefungs-MAJOR 2026-08-27: derselbe Ausschluss, aber im IF-KOPF.
// ParseIfStmt joint jedes Token mit einem unbedingten Leerzeichen
// ('c . decl . result = nil'), darum lief der Punkt-Ausschluss dort ins
// Leere und die Methode galt faelschlich als Result-mutierend - 6 echte
// Korpus-Funde gingen so verloren. Der Fix kollabiert ' .' / '. '
// vor dem Wortscan.
const SRC =
  'unit t; implementation'#13#10 +
  'function Check(c: TCtx): Integer;'#13#10 +
  'begin'#13#10 +
  '  if c.Decl.Result = nil then'#13#10 +
  '    Result := -1'#13#10 +
  '  else'#13#10 +
  '    Result := -1;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkConstantReturn) >= 1,
    'fremdes .Result im if-Kopf ist kein Zugriff auf den Rueckgabewert');
  finally F.Free; end;
end;

procedure TTestConstantReturn.DottedResultMember_StillReported;
// 'FMsg.Result' ist ein fremdes Member (TMessage hat ein Feld dieses
// Namens), kein Zugriff auf den eigenen Rueckgabewert - der Punkt links vom
// Wort schliesst den Treffer aus.
const SRC =
  'unit t; implementation'#13#10 +
  'function HandleMsg: Integer;'#13#10 +
  'begin'#13#10 +
  '  Log(FMsg.Result);'#13#10 +
  '  if FOk then Result := 7 else Result := 7;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkConstantReturn) >= 1,
    'Member nach dem Punkt ist kein Result-Zugriff');
  finally F.Free; end;
end;

procedure TTestConstantReturn.ResultInStringLiteral_StillReported;
// Hausinvariante: Strings zaehlen NIE als Code-Use. Der Parser haelt das
// Literal in Quelltextform im nkCall.Name, der Scan muss es strippen.
const SRC =
  'unit t; implementation'#13#10 +
  'function Ping: Integer;'#13#10 +
  'begin'#13#10 +
  '  Log(''no result yet'');'#13#10 +
  '  if FOk then Result := 7 else Result := 7;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkConstantReturn) >= 1,
    'result im String ist kein Code-Use');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConstantReturn);

end.

unit uTestDeadCodeParser;

// Regressionstests fuer SCA011 DeadCode, die NICHT den Detektor pruefen,
// sondern den AST, den er bekommt: 32 der 41 Sample-FP des Stufe-2-Audits
// (2026-08-16) entstanden im Parser - Exit-Argument nicht klammerbalanciert,
// at-Klausel als Geschwisterknoten, fehlender goto-Zweig, bedingungsloses
// nkContinue fuer einen gleichnamigen Bezeichner.
//
// Alle Faelle laufen ueber TFindingHelper.FindingsOfFile: die quellbasierten
// Guards von uDeadCode sind ohne Datei auf Platte still inert.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDeadCodeParserExt = class
  public
    [Test] procedure DeadCode_NestedParenExitArgSameLine_NoFinding;
    [Test] procedure DeadCode_RaiseAtClauseOnNextLine_NoFinding;
    [Test] procedure DeadCode_ConditionalTerminatorOneLiner_NoFinding;
    [Test] procedure DeadCode_BothInsideSameIfdef_StillReported;
    [Test] procedure DeadCode_GotoLabelNamedExit_NoFinding;
    [Test] procedure DeadCode_GotoAfterExit_StillReported;
    [Test] procedure DeadCode_ContinueAsVarParamInLoop_NoFinding;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestDeadCodeParserExt.DeadCode_NestedParenExitArgSameLine_NoFinding;
// FP-Audit Stufe 2 (2026-08-16): der Exit-Argument-Scanner in uParser2 war
// nicht klammerbalanciert und stoppte an der ERSTEN ')'. Der Argumentrest
// leckte als eigenstaendiger Geschwister-Knoten auf DERSELBEN Zeile heraus
// und sah fuer SCA011 wie Code nach dem Exit aus (16 von 41 Sample-FP; der
// Balance-Guard im Detektor verlangt Nxt.Line > Child.Line und ist im
// Ein-Zeilen-Fall inert).
const SRC =
  'unit t; implementation'#13#10+
  'function Foo: Integer;'#13#10+
  'begin'#13#10+
  '  Exit(Calc(1, Inner(2), 3));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDeadCode),
    'geschachtelte Klammern im Exit-Argument sind kein toter Code');
  finally F.Free; end;
end;

procedure TTestDeadCodeParserExt.DeadCode_RaiseAtClauseOnNextLine_NoFinding;
// FP-Audit Stufe 2 (2026-08-16): 'at' ist im Lexer kein Schluesselwort;
// ParseRaiseStmt liess die at-Klausel im Strom stehen, der naechste
// ParseStatement-Durchlauf machte daraus einen Geschwister-nkCall('at') mit
// der Zeilennummer der FOLGEzeile - fuer SCA011 toter Code hinter dem raise
// (16 von 41 Sample-FP, mORMot-/JsonDataObjects-Muster).
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  raise EFoo.CreateFmt(''x %d'', [1])'#13#10+
  '    at get_caller_addr(get_frame);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDeadCode),
    'die at-Klausel gehoert zum raise, sie ist kein toter Code');
  finally F.Free; end;
end;

procedure TTestDeadCodeParserExt.DeadCode_ConditionalTerminatorOneLiner_NoFinding;
// FP-Audit Stufe 2 (2026-08-16): steht der TERMINATOR allein in einem
// {$IFDEF}-Einzeiler, ist die Folgezeile ohne das Define der tragende Pfad.
// Der aeltere Guard suchte eine Direktiven-Zeile STRIKT zwischen beiden und
// lief hier leer, weil Start und Ende des Bereichs auf DIESELBE Zeile fallen
// (uPSCompiler-Familie, 4 Repo-Kopien).
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  {$IFDEF DEBUG} raise EFoo.Create(''x''); {$ENDIF}'#13#10+
  '  Exit;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDeadCode),
    'ohne das Define existiert der raise nicht - das Exit ist erreichbar');
  finally F.Free; end;
end;

procedure TTestDeadCodeParserExt.DeadCode_BothInsideSameIfdef_StillReported;
// TP-Gegenprobe zum Guard darueber: liegen Terminator UND Folgeanweisung im
// SELBEN bedingten Bereich, ist die Folgeanweisung in jedem Build tot.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  {$IFDEF DEBUG}'#13#10+
  '  Exit;'#13#10+
  '  DoDead;'#13#10+
  '  {$ENDIF}'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDeadCode) >= 1,
    'im selben bedingten Zweig bleibt der Code nach Exit tot');
  finally F.Free; end;
end;

procedure TTestDeadCodeParserExt.DeadCode_GotoLabelNamedExit_NoFinding;
// FP-Audit Stufe 2 (2026-08-16): ParseStatement hatte keinen goto-Zweig. Das
// 'goto' fiel in den else-Pfad, der naechste Durchlauf sah das Label-Ident -
// und wenn das Label wie ein Terminator heisst (mORMot deklariert in
// Hot-Paths 'label Ret, Exit;'), dispatchte tkKwExit und legte einen ECHTEN
// nkExit an, noch dazu auf BLOCK-Ebene statt im then-Zweig. Damit galt jede
// Zeile nach einem bedingten 'goto Exit;' als tot.
const SRC =
  'unit t; implementation'#13#10+
  'function Foo: Integer;'#13#10+
  'label Exit;'#13#10+
  'begin'#13#10+
  '  if A then goto Exit;'#13#10+
  '  Result := 1;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDeadCode),
    'ein Label namens Exit ist kein Terminator');
  finally F.Free; end;
end;

procedure TTestDeadCodeParserExt.DeadCode_GotoAfterExit_StillReported;
// TP-Gegenprobe: die goto-Anweisung MUSS einen Knoten erzeugen - sonst
// verschwinden die belegten TP, bei denen ein 'goto <Label>;' selbst der
// tote Code nach einem 'exit;' ist (FastCodeCharPos.pas:636).
const SRC =
  'unit t; implementation'#13#10+
  'function Foo: Integer;'#13#10+
  'label Ret;'#13#10+
  'begin'#13#10+
  '  Exit;'#13#10+
  '  goto Ret;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDeadCode) >= 1,
    'ein goto nach einem Exit ist toter Code');
  finally F.Free; end;
end;

procedure TTestDeadCodeParserExt.DeadCode_ContinueAsVarParamInLoop_NoFinding;
// FP-Audit Stufe 2 (2026-08-16): 'Break'/'Continue' sind keine reservierten
// Woerter. 'procedure NextButtonClick(var Continue: Boolean)' mit
// 'Continue := False;' IM Schleifenrumpf erzeugte bedingungslos einen
// nkContinue; der kompensierende Detektor-Guard wirkt nur ausserhalb von
// Schleifen und war dort inert.
const SRC =
  'unit t; implementation'#13#10+
  'procedure NextButtonClick(var Continue: Boolean);'#13#10+
  'var i: Integer;'#13#10+
  'begin'#13#10+
  '  for i := 0 to 3 do'#13#10+
  '  begin'#13#10+
  '    Continue := False;'#13#10+
  '    DoWork(i);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDeadCode),
    'Zuweisung an einen Parameter namens Continue ist kein Schleifensprung');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDeadCodeParserExt);

end.

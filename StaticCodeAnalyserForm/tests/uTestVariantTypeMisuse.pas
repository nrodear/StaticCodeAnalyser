unit uTestVariantTypeMisuse;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestVariantTypeMisuse = class
  public
    [Test] procedure VariantLocalInMethodWithLoop_Reported;
    [Test] procedure VariantLocalInMethodWithoutLoop_NotReported;
    [Test] procedure IntegerLocalInLoop_NotReported;
    [Test] procedure OleVariantLocalInLoop_Reported;
    // Autopsie 2026-08-26, Gate A: In-Loop-Usage statt Methode-hat-Loop.
    [Test] procedure VariantOnlyBeforeLoop_NotReported;
    [Test] procedure VariantOnlyAfterLoop_NotReported;
    [Test] procedure VariantInWhileCondition_Reported;
    [Test] procedure NestedRoutineBlindSpot_StillReported;
    // Gegenpruefungs-BLOCKER 2026-08-26: nkParam.Name traegt den
    // Modifier ('const keyvalues') - ohne Strip fiel JEDER solche
    // Param, auch bei Hot-Path-Nutzung (JvCsvData.LocateRecord).
    [Test] procedure ConstVariantParamUsedInLoop_StillReported;
    // Posten 221: repeat-until als dritter Loop-Kind, plus die
    // Parser-Grenze der until-Bedingung
    [Test] procedure VariantInRepeatBody_Reported;
    [Test] procedure VariantOnlyBeforeRepeat_NotReported;
    [Test] procedure VariantOnlyInUntilCondition_KnownLimit;
    [Test] procedure VariantAlsoInRepeatBody_Reported;
    [Test] procedure VariantInRepeatBodyOnly_Reported;
    [Test] procedure ConstVariantParamInRepeatBody_Reported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 221: repeat-until, der dritte Loop-Kind --------------- }
//
// nkRepeatStmt steht in HasLoopChild (uVariantTypeMisuse.pas:137)
// und in der Kind-Menge von UsedInAnyLoop (:150), aber keiner der
// neun Bestandstests hat ihn je beruehrt - for und while ja, repeat
// nie.
//
// Dazu die im Kopfkommentar (:34-37) dokumentierte Grenze: die
// until-BEDINGUNG ist im AST gar nicht da. uParser2.ParseRepeatStmt
// (:3013-3015) macht "Eat(tkKwUntil); SkipToSemicolon;" - der
// Ausdruck wird gelesen und verworfen. SubtreeMentionsIdent kann ihn
// deshalb nicht finden.
//
// Das Spiegelbild steht schon in dieser Datei:
// VariantInWhileCondition_Reported meldet, weil der while-KOPF im
// AST steht. Erst das Paar macht die Asymmetrie als
// Parser-Eigenschaft lesbar statt als Detektor-Zufall.
//
// Alle Fixtures an der Exe gemessen.

procedure TTestVariantTypeMisuse.VariantInRepeatBody_Reported;
// DER TRAGENDE TEST der Gruppe: er stirbt, wenn nkRepeatStmt
// aus HasLoopChild (:137) faellt, UND wenn es aus der
// Kind-Menge von UsedInAnyLoop (:150) faellt. Die anderen
// beiden repeat-Tests bleiben bei solchen Regressionen gruen
// (0 ist dann immer noch 0). Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var v: Variant; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := 0;'#13#10 +
  '  repeat'#13#10 +
  '    Use(v, i);'#13#10 +
  '    Inc(i);'#13#10 +
  '  until i > 100;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(
      TFindingHelper.Count(F, fkVariantTypeMisuse) >= 1,
      'Variant im repeat-Rumpf muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestVariantTypeMisuse.VariantOnlyBeforeRepeat_NotReported;
// Das repeat-Gegenstueck zu VariantOnlyBeforeLoop_NotReported.
// Es faengt GENAU EINE Mutation: "Gate A wird fuer
// repeat-Methoden umgangen". Gegen "repeat faellt aus der
// Loop-Erkennung" ist es blind - dafuer ist der Test darueber
// zustaendig. Gemessen: 0.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var v: Variant; i, n: Integer;'#13#10 +
  'begin'#13#10 +
  '  v := ReadConfig;'#13#10 +
  '  n := Integer(v);'#13#10 +
  '  i := 0;'#13#10 +
  '  repeat'#13#10 +
  '    Work(i);'#13#10 +
  '    Inc(i);'#13#10 +
  '  until i > n;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkVariantTypeMisuse),
      'Nutzung nur VOR dem repeat ist kein Loop-Fund');
  finally F.Free; end;
end;

procedure TTestVariantTypeMisuse.VariantOnlyInUntilCondition_KnownLimit;
// DIE GRENZE. Der Variant wird ausschliesslich in der
// until-Bedingung genutzt - und die existiert im AST nicht.
// Gemessen: 0.
//
// Wird dieser Test eines Tages rot, ist das kein Defekt,
// sondern ein Signal: dann haengt ParseRepeatStmt den
// until-Ausdruck in den Baum, und das bewegt Funde in JEDEM
// AST-laufenden Detektor, nicht nur hier.
//
// Am Korpus ist die Klasse leer: 13.419 Dateien, Kommentare
// und Literale gestrippt, repeat/until mit Tiefen-Stack
// gepaart - null Faelle, in denen ein Variant NUR in der
// until-Bedingung steht. Es gibt hier nichts zu gewinnen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var v: Variant; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := 0;'#13#10 +
  '  repeat'#13#10 +
  '    Step(i);'#13#10 +
  '    Inc(i);'#13#10 +
  '  until v = Null;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkVariantTypeMisuse),
      'BEKANNTE GRENZE: die until-Bedingung steht nicht im AST');
  finally F.Free; end;
end;

procedure TTestVariantTypeMisuse.VariantAlsoInRepeatBody_Reported;
// DIE KLAMMER zum Test darueber: Zeichen fuer Zeichen
// dieselbe Fixture, dieselbe until-Bedingung, nur eine
// zusaetzliche Rumpfzeile. Gemessen: 1. Damit kommt die Null
// oben vom unsichtbaren until-Ausdruck und nicht davon, dass
// die Fixture den Detektor verfehlt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var v: Variant; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := 0;'#13#10 +
  '  repeat'#13#10 +
  '    Step(i);'#13#10 +
  '    Inc(i);'#13#10 +
  '    v := Fetch(i);'#13#10 +
  '  until v = Null;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(
      TFindingHelper.Count(F, fkVariantTypeMisuse) >= 1,
      'derselbe Variant im Rumpf wird sehr wohl gemeldet');
  finally F.Free; end;
end;

procedure TTestVariantTypeMisuse.VariantInRepeatBodyOnly_Reported;
// Gegenrichtung: im Rumpf genutzt, until nennt ihn NICHT.
// Gemessen: 1. Zusammen mit den zwei Tests darueber ist die
// Regel dreifach eingeklammert - gezaehlt wird der RUMPF.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var v: Variant; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := 0;'#13#10 +
  '  repeat'#13#10 +
  '    Step(i);'#13#10 +
  '    Inc(i);'#13#10 +
  '    if v = Null then Break;'#13#10 +
  '  until i > 10;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(
      TFindingHelper.Count(F, fkVariantTypeMisuse) >= 1,
      'die until-Bedingung ist fuer den Fund nicht noetig');
  finally F.Free; end;
end;

procedure TTestVariantTypeMisuse.ConstVariantParamInRepeatBody_Reported;
// Der const-Parameter-Pfad (Modifier-Strip :109-121) ueber
// dem dritten Loop-Kind - die beiden Stellen sind getrennt.
// Das ist die Form, die im Korpus wirklich vorkommt:
// jvcl JvDBTreeView.pas:1174 meldet MField ueber genau
// diesen Weg (und das danebenstehende MV richtigerweise
// nicht, weil es nur ausserhalb des repeat steht).
// Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10 +
  'function Find(const KeyValues: Variant): Integer;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  Result := -1;'#13#10 +
  '  i := 0;'#13#10 +
  '  repeat'#13#10 +
  '    if Match(KeyValues, i) then Result := i;'#13#10 +
  '    Inc(i);'#13#10 +
  '  until i > 100;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(
      TFindingHelper.Count(F, fkVariantTypeMisuse) >= 1,
      'const-Variant-Parameter im repeat-Rumpf wird gemeldet');
  finally F.Free; end;
end;


procedure TTestVariantTypeMisuse.VariantLocalInMethodWithLoop_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var v: Variant; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 100 do v := v + 1;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkVariantTypeMisuse) >= 1,
      'Variant in Methode mit for-loop muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestVariantTypeMisuse.VariantLocalInMethodWithoutLoop_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var v: Variant;'#13#10 +
  'begin'#13#10 +
  '  v := 42;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVariantTypeMisuse),
      'Variant ohne Loop in der Methode ist kein Perf-Issue');
  finally F.Free; end;
end;

procedure TTestVariantTypeMisuse.IntegerLocalInLoop_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i, j: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 100 do j := j + 1;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVariantTypeMisuse),
      'Integer-Locals interessieren diesen Detektor nicht');
  finally F.Free; end;
end;

procedure TTestVariantTypeMisuse.OleVariantLocalInLoop_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var ov: OleVariant; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 100 do ov := i;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkVariantTypeMisuse) >= 1,
      'OleVariant zaehlt auch');
  finally F.Free; end;
end;

procedure TTestVariantTypeMisuse.VariantOnlyBeforeLoop_NotReported;
// Gate A: der Variant wird nur VOR dem Loop benutzt - die dominante
// FP-Klasse der Autopsie (18/19 Stichproben-FPs, alle 14 Audit-FPs;
// 282 der 613 rw14-Funde).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var v: Variant; i, n: Integer;'#13#10 +
  'begin'#13#10 +
  '  v := ReadConfig;'#13#10 +
  '  n := Integer(v);'#13#10 +
  '  for i := 0 to n do Work(i);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVariantTypeMisuse),
      'Variant ausserhalb des Loops ist kein Hot-Path-Problem');
  finally F.Free; end;
end;

procedure TTestVariantTypeMisuse.VariantOnlyAfterLoop_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var v: Variant; i, s: Integer;'#13#10 +
  'begin'#13#10 +
  '  s := 0;'#13#10 +
  '  for i := 0 to 100 do s := s + i;'#13#10 +
  '  v := s;'#13#10 +
  '  Store(v);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVariantTypeMisuse),
      'Nutzung nur nach dem Loop');
  finally F.Free; end;
end;

procedure TTestVariantTypeMisuse.VariantInWhileCondition_Reported;
// Die Loop-KOPF-Bedingung gehoert zum Loop-Teilbaum - Nutzung dort
// ist Hot-Path.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var v: Variant;'#13#10 +
  'begin'#13#10 +
  '  v := Fetch;'#13#10 +
  '  while v <> Null do'#13#10 +
  '    Step;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkVariantTypeMisuse) >= 1,
      'while-Bedingung ist In-Loop-Nutzung');
  finally F.Free; end;
end;

procedure TTestVariantTypeMisuse.NestedRoutineBlindSpot_StillReported;
// Guard: nested Routinen sind im AST verworfen (nkNestedRange) - die
// Nutzung im nested Loop ist unsichtbar, der Fund muss konservativ
// STEHEN bleiben (JvDBUtils-KeyValues-Familie, 36 Guard-Keeps mit
// belegten TPs - Gegenpruefung 2026-08-26).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Outer;'#13#10 +
  'var v: Variant; i: Integer;'#13#10 +
  '  procedure Inner;'#13#10 +
  '  var k: Integer;'#13#10 +
  '  begin'#13#10 +
  '    for k := 0 to 9 do v := v + k;'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 3 do Inner;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkVariantTypeMisuse) >= 1,
      'nested-blinde Methode bleibt konservativ gemeldet');
  finally F.Free; end;
end;

procedure TTestVariantTypeMisuse.ConstVariantParamUsedInLoop_StillReported;
// BLOCKER-Regression aus der Diff-Gegenpruefung: 'const KeyValues:
// Variant' wird im Parser als Name 'const keyvalues' gefuehrt - die
// Such-Needle matchte nie, der Kern-TP der Regel (JvCsvData
// LocateRecord, Record-Scan-Doppelschleife) fiel still.
const SRC =
  'unit t; implementation'#13#10 +
  'function Find(const KeyValues: Variant): Integer;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  Result := -1;'#13#10 +
  '  for i := 0 to 100 do'#13#10 +
  '    if Match(KeyValues, i) then Result := i;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkVariantTypeMisuse) >= 1,
      'const-Variant-Param mit In-Loop-Nutzung bleibt Fund');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestVariantTypeMisuse);

end.

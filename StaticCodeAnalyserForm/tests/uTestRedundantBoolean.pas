unit uTestRedundantBoolean;

// Tests fuer TRedundantBooleanDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRedundantBoolean = class
  public
    [Test] procedure NoComparison_NoFinding;
    [Test] procedure EqualsTrue_Reported;
    [Test] procedure EqualsFalse_Reported;
    [Test] procedure NotEqualsFalse_Reported;
    [Test] procedure AssignTrue_NotReported;
    [Test] procedure ConstDecl_NotReported;
    [Test] procedure GeOperator_NotReported;
    [Test] procedure RedundantBoolean_KindAndSeverity;
    // --- Ist-Messung 2026-07-18 (SCA072 100% FP im Sample): Deklarations-Kontexte ---
    [Test] procedure DefaultParamBoolTrue_NotReported;
    [Test] procedure ConstBlockFolgezeile_NotReported;
    [Test] procedure InitializedGlobalVar_NotReported;
    [Test] procedure AssignRhsCompare_StillReported;   // TP-Gegenprobe
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestRedundantBoolean.NoComparison_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if Active then DoStuff;'#13#10 +
  '  if not Disabled then OtherStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantBoolean));
  finally F.Free; end;
end;

procedure TTestRedundantBoolean.EqualsTrue_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if Active = True then DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRedundantBoolean));
  finally F.Free; end;
end;

procedure TTestRedundantBoolean.EqualsFalse_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Active = False then DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRedundantBoolean));
  finally F.Free; end;
end;

procedure TTestRedundantBoolean.NotEqualsFalse_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Active <> False then DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRedundantBoolean));
  finally F.Free; end;
end;

procedure TTestRedundantBoolean.AssignTrue_NotReported;
// `:=` ist Assignment, kein Vergleich.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X: Boolean;'#13#10 +
  'begin'#13#10 +
  '  X := True;'#13#10 +
  '  X := False;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantBoolean));
  finally F.Free; end;
end;

procedure TTestRedundantBoolean.ConstDecl_NotReported;
// `const X = True;` ist Deklaration, nicht Vergleich.
const SRC =
  'unit t; implementation'#13#10 +
  'const Active = True; Disabled = False;'#13#10 +
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantBoolean));
  finally F.Free; end;
end;

procedure TTestRedundantBoolean.GeOperator_NotReported;
// `>=` und `<=` duerfen nicht versehentlich gematcht werden.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Count >= 10 then DoStuff;'#13#10 +
  '  if X <= 0 then OtherStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantBoolean));
  finally F.Free; end;
end;

procedure TTestRedundantBoolean.RedundantBoolean_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Active = True then DoStuff;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkRedundantBoolean then
      begin
        Assert.AreEqual<TFindingKind>(fkRedundantBoolean, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,            Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkRedundantBoolean finding');
  finally F.Free; end;
end;

procedure TTestRedundantBoolean.DefaultParamBoolTrue_NotReported;
// Ist-Messung 2026-07-18 (dominante FP-Klasse 14/15): 'X: Boolean = True' als
// DEFAULT-PARAMETERWERT ist ein Initializer, kein Vergleich. Colon-Rule: vor
// dem LHS-Ident ('Boolean') steht ein nacktes ':' -> Deklaration -> Skip.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const ARaise: Boolean = True); forward;'#13#10 +
  'function Bar(A: Integer; const ASilent: boolean = False): string; forward;'#13#10 +
  'procedure Foo(const ARaise: Boolean = True);'#13#10 +
  'begin end;'#13#10 +
  'function Bar(A: Integer; const ASilent: boolean = False): string;'#13#10 +
  'begin Result := ''''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantBoolean),
    'Boolean-Default-Parameter ist Deklaration, kein redundanter Vergleich');
  finally F.Free; end;
end;

procedure TTestRedundantBoolean.ConstBlockFolgezeile_NotReported;
// Ist-Messung 2026-07-18: untypisierte Konstante auf einer FOLGE-Zeile eines
// const-Blocks ('X = False;') - der alte Zeilenanfangs-Check sah nur die
// Kopfzeile. const-Section-Tracker: Sections enthalten keinen ausfuehrbaren
// Code -> Skip TP-safe. 'begin' beendet die Section (Gegenprobe im selben SRC).
const SRC =
  'unit t; implementation'#13#10 +
  'const'#13#10 +
  '  cDefault = False;'#13#10 +
  '  cTyped: Boolean = True;'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantBoolean),
    'const-Block-Folgezeilen sind Deklarationen, keine Vergleiche');
  finally F.Free; end;
end;

procedure TTestRedundantBoolean.InitializedGlobalVar_NotReported;
// 'var GFlag: Boolean = True;' (initialisiertes Global) - Colon-Rule greift.
const SRC =
  'unit t; implementation'#13#10 +
  'var'#13#10 +
  '  GFlag: Boolean = True;'#13#10 +
  'procedure Foo;'#13#10 +
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRedundantBoolean),
    'initialisiertes Global ist Deklaration, kein Vergleich');
  finally F.Free; end;
end;

procedure TTestRedundantBoolean.AssignRhsCompare_StillReported;
// TP-Gegenprobe zur Colon-Rule: 'R := Active = True;' - vor dem LHS-Ident
// 'Active' steht das '=' aus ':=' (KEIN nacktes ':') -> echter redundanter
// Vergleich, muss weiterhin gemeldet werden.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var R, Active: Boolean;'#13#10 +
  'begin'#13#10 +
  '  R := Active = True;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRedundantBoolean),
    'Vergleich auf Assign-RHS bleibt ein Fund (Colon-Rule greift nicht)');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRedundantBoolean);

end.

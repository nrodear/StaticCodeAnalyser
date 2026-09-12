unit uTestCompilerDirectiveScope;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCompilerDirectiveScope = class
  public
    [Test] procedure WarningsOffWithoutOn_Reported;
    [Test] procedure WarningsOffAndOn_NotReported;
    [Test] procedure RangeChecksOffWithoutOn_Reported;
    [Test] procedure WarningsOffInsidePushPop_NotReported;
    [Test] procedure DirectiveInStringLiteral_NotReported;
    // Voll-Review 2026-09-12 (Major 46): Kurzformen {$R±}/{$B±}/{$Q±}
    [Test] procedure LongOffClosedByShortPlus_NotReported;
    [Test] procedure ShortMinusWithoutOn_Reported;
    [Test] procedure ResourceDirective_NotConfused;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestCompilerDirectiveScope.WarningsOffWithoutOn_Reported;
const SRC =
  '{$WARNINGS OFF}'#13#10 +
  'unit t; interface'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkCompilerDirectiveScope) >= 1,
      '{$WARNINGS OFF} ohne ON muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestCompilerDirectiveScope.WarningsOffAndOn_NotReported;
const SRC =
  '{$WARNINGS OFF}'#13#10 +
  'unit t; interface'#13#10 +
  'implementation'#13#10 +
  '{$WARNINGS ON}'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCompilerDirectiveScope),
      'OFF + ON ist balanced - kein Finding');
  finally F.Free; end;
end;

procedure TTestCompilerDirectiveScope.RangeChecksOffWithoutOn_Reported;
const SRC =
  'unit t; interface'#13#10 +
  '{$RANGECHECKS OFF}'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkCompilerDirectiveScope) >= 1,
      '{$RANGECHECKS OFF} ohne ON muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestCompilerDirectiveScope.WarningsOffInsidePushPop_NotReported;
// FP-Fix (Real-World 2026-06-21): {$POP} restauriert den Switch-State -
// ein {$WARNINGS OFF} zwischen {$PUSH} und {$POP} leakt NICHT.
const SRC =
  '{$PUSH}'#13#10 +
  '{$WARNINGS OFF}'#13#10 +
  'unit t; interface'#13#10 +
  'implementation'#13#10 +
  '{$POP}'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCompilerDirectiveScope),
      '{$PUSH}/{$POP} restauriert den State - kein Leak');
  finally F.Free; end;
end;

procedure TTestCompilerDirectiveScope.DirectiveInStringLiteral_NotReported;
// Review-MEDIUM 2026-08-09: '{$WARNINGS OFF}' als String-INHALT ist keine
// Direktive - vorher zaehlte das Literal als echtes OFF und erzeugte einen
// falschen Unbalanced-Fund.
const SRC =
  'unit t; interface'#13#10 +
  'implementation'#13#10 +
  'const cDirSample = ''{$WARNINGS OFF}'';'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCompilerDirectiveScope),
      'Direktive im String-Literal darf nicht als OFF zaehlen');
  finally F.Free; end;
end;

procedure TTestCompilerDirectiveScope.LongOffClosedByShortPlus_NotReported;
// Voll-Review 2026-09-12 (Major 46): '{$R+}' schaltet denselben Switch
// wie '{$RANGECHECKS ON}' - die Kurzform war fuer die Bilanz
// unsichtbar und das OFF blieb als falscher Fund stehen (Bestands-Exe:
// 1 FP, empirisch belegt).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  '{$RANGECHECKS OFF}'#13#10 +
  'implementation'#13#10 +
  '{$R+}'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkCompilerDirectiveScope),
    '{$R+} schliesst {$RANGECHECKS OFF} - kein Fund');
  finally F.Free; end;
end;

procedure TTestCompilerDirectiveScope.ShortMinusWithoutOn_Reported;
// Spiegelrichtung: ein nacktes '{$R-}' ohne ON/'+' leckt genauso wie
// die Langform (Bestands-Exe: 0 Funde, empirisch belegt - FN).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  '{$R-}'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkCompilerDirectiveScope),
    '{$R-} ohne Gegenstueck muss wie RANGECHECKS OFF gemeldet werden');
  finally F.Free; end;
end;

procedure TTestCompilerDirectiveScope.ResourceDirective_NotConfused;
// Gegenrichtung zur Kurzform-Alternation: '{$R *.res}' ist die
// Ressourcen-Direktive, kein Range-Switch - genau EIN Schaltzeichen
// haelt sie draussen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  '{$R *.res}'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkCompilerDirectiveScope),
    '{$R *.res} ist kein Switch');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCompilerDirectiveScope);

end.

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
    // Voll-Review 2026-09-12 (Major 46): Kurzformen {$R+/-} etc.
    [Test] procedure LongOffClosedByShortPlus_NotReported;
    [Test] procedure ShortMinusWithoutOn_Reported;
    [Test] procedure ResourceDirective_NotConfused;
    // Voll-Review 2026-09-12 (Testluecke 98): POP/PUSH und die
    // getrackten Direktiven
    [Test] procedure HintsOffWithoutOn_Reported;
    [Test] procedure PopWithoutPushClosesSwitch_NoFinding;
    [Test] procedure UnbalancedPush_StillReported;
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

procedure TTestCompilerDirectiveScope.HintsOffWithoutOn_Reported;
// Testluecke 98 (Voll-Review 2026-09-12): dass HINTS zu den getrackten
// Direktiven gehoert, war ungetestet - die Suite hatte nur fuenf Faelle.
// Ein ausgeschaltetes HINTS ohne Gegenstueck gilt fuer den Rest der
// Datei und ist genau das, was die Regel meint.
// Andere Form als der POP-Zwilling darunter (eigener Unit-Name,
// Funktion statt Prozedur) - sonst melden sich die beiden Fixtures
// gegenseitig als DuplicateBlock.
const SRC =
  'unit u;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  '{$HINTS OFF}'#13#10 +
  'function Wert: Integer;'#13#10 +
  'begin'#13#10 +
  '  Result := 1;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkCompilerDirectiveScope),
    'HINTS OFF ohne ON gilt bis zum Dateiende');
  finally F.Free; end;
end;

procedure TTestCompilerDirectiveScope.PopWithoutPushClosesSwitch_NoFinding;
// Der Toleranz-Zweig: ein {$POP} OHNE vorheriges {$PUSH} ist kein
// Fehler - es schliesst den offenen Schalter trotzdem. Ohne diesen
// Test koennte die Toleranz unbemerkt verschwinden und jede
// PUSH-lose Bibliothek Meldungen produzieren. An der gebauten Exe
// verifiziert.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  '{$HINTS OFF}'#13#10 +
  'procedure P;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  '{$POP}'#13#10 +
  'procedure Q;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkCompilerDirectiveScope),
    'POP schliesst den Schalter auch ohne vorheriges PUSH');
  finally F.Free; end;
end;

procedure TTestCompilerDirectiveScope.UnbalancedPush_StillReported;
// Die andere Richtung: ein {$PUSH}, das nie zurueckgenommen wird,
// rettet den ausgeschalteten Schalter NICHT - der Snapshot wird im
// finally freigegeben, der Fund bleibt.
// Bewusst anders geformt als die beiden Fixtures darueber (andere
// Direktive, andere Routine) - byte-nah gebaut melden sie sich
// gegenseitig als DuplicateBlock.
const SRC =
  'unit v;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  '{$PUSH}'#13#10 +
  '{$OVERFLOWCHECKS OFF}'#13#10 +
  'function Rechne(A: Integer): Integer;'#13#10 +
  'begin'#13#10 +
  '  Result := A * 2;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkCompilerDirectiveScope),
    'ein offenes PUSH nimmt das OFF nicht zurueck');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCompilerDirectiveScope);

end.

unit uTestTwiceInheritedCalls;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTwiceInheritedCalls = class
  public
    [Test] procedure SingleInherited_NoFinding;
    [Test] procedure TwoInherited_Reported;
    [Test] procedure NoInherited_NoFinding;
    [Test] procedure TwiceInheritedCalls_KindAndSeverity;
    [Test] procedure InheritedInIfElseBranches_NoFinding;
    [Test] procedure TwoSequentialInherited_StillReported;
    // --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---
    [Test] procedure InheritedDifferentParentMethods_NotReported;
    [Test] procedure InheritedSameMethodNameTwice_Reported;
    // --- Real-World FP-Audit 2026-07-12 (Welle 3, nkConditionalRange) ---
    [Test] procedure InheritedInIfdefElseBranches_NoFinding;
    [Test] procedure TwoInheritedSameIfdefBlock_StillReported;
    // Voll-Review 2026-09-12 (Testluecke 115): Block jenseits der Wurzel
    [Test] procedure InheritedPairInNestedBlock_Reported;
    [Test] procedure BareAndQualifiedInheritedMixed_Reported;
    [Test] procedure QualifiedInheritedOtherMethod_NoFinding;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestTwiceInheritedCalls.SingleInherited_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  inherited;'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTwiceInheritedCalls));
  finally F.Free; end;
end;

procedure TTestTwiceInheritedCalls.TwoInherited_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  inherited;'#13#10 +
  '  DoStuff;'#13#10 +
  '  inherited;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTwiceInheritedCalls));
  finally F.Free; end;
end;

procedure TTestTwiceInheritedCalls.NoInherited_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTwiceInheritedCalls));
  finally F.Free; end;
end;

procedure TTestTwiceInheritedCalls.TwiceInheritedCalls_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  inherited;'#13#10 +
  '  inherited;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkTwiceInheritedCalls then
      begin
        Assert.AreEqual<TFindingKind>(fkTwiceInheritedCalls, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsWarning,            Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkTwiceInheritedCalls finding');
  finally F.Free; end;
end;

// FP-Guard (2026-06-29): zwei `inherited` ueber if/else-Branches verteilt
// haengen an nkIfStmt - NICHT an einem nkBlock - und laufen mutual-exklusiv.
// Darf NICHT gemeldet werden.
procedure TTestTwiceInheritedCalls.InheritedInIfElseBranches_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  if X then inherited else inherited;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTwiceInheritedCalls));
  finally F.Free; end;
end;

// Zwei sequenzielle `inherited` direkte Kinder EINES nkBlock - laufen beide,
// Parent-Side-Effekte verdoppeln sich -> bleibt ein Finding.
procedure TTestTwiceInheritedCalls.TwoSequentialInherited_StillReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  inherited;'#13#10 +
  '  inherited;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkTwiceInheritedCalls) >= 1);
  finally F.Free; end;
end;


// --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---

// Real-World-FP-Audit 2026-07-10 (SCA093, Fix ef3608e): zwei `inherited` die
// VERSCHIEDENE Parent-Methoden aufrufen (`inherited Lock;` + `inherited Unlock;`)
// verdoppeln KEINE Side-Effekte einer einzelnen Methode. Der fuehrende Bezeichner
// (Lock/Unlock) ist nicht der Methoden-Name (Bar) -> QualifyingInheritedInBlock
// zaehlt 0 -> darf NICHT gemeldet werden (frueher: DirectChildCount zaehlte 2).
procedure TTestTwiceInheritedCalls.InheritedDifferentParentMethods_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  inherited Lock;'#13#10 +
  '  inherited Unlock;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTwiceInheritedCalls),
        'inherited Lock + inherited Unlock rufen verschiedene Parent-Methoden - kein Doppelaufruf, kein Bug');
  finally F.Free; end;
end;

// Must-stay TP (SCA093 Fix-Branch b): zwei `inherited Bar;` im Rumpf von TFoo.Bar
// rufen die GLEICHE Parent-Methode (Bar) erneut auf -> deren Side-Effekte laufen
// zweimal. Der neue Guard zaehlt gleichnamiges `inherited <Methode>` weiterhin
// (LeadingInheritedIdent = 'Bar' = ShortMethodName) -> muss gemeldet bleiben.
procedure TTestTwiceInheritedCalls.InheritedSameMethodNameTwice_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  inherited Bar;'#13#10 +
  '  inherited Bar;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkTwiceInheritedCalls) >= 1,
        'zweimal inherited Bar verdoppelt die Parent-Bar - echter Bug, muss gemeldet bleiben');
  finally F.Free; end;
end;
procedure TTestTwiceInheritedCalls.InheritedInIfdefElseBranches_NoFinding;
// Welle 3 (Real-World-FP-Audit 2026-07-12, 'ifdef-else-mutually-exclusive'):
// Der Parser inlined {$IFDEF}/{$ELSE} in denselben nkBlock; die zwei `inherited`
// laufen aber NIE beide (nur EIN Zweig kompiliert). Die {$ELSE}-Direktivenzeile
// liegt strikt zwischen den Calls -> nkConditionalRange-Guard -> kein Befund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '{$IFDEF MACOSX}'#13#10 +
  '  inherited;'#13#10 +
  '{$ELSE}'#13#10 +
  '  inherited;'#13#10 +
  '{$ENDIF}'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTwiceInheritedCalls),
    'zwei inherited in {$IFDEF}/{$ELSE}-Zweigen laufen nie beide - kein Befund');
  finally F.Free; end;
end;

procedure TTestTwiceInheritedCalls.TwoInheritedSameIfdefBlock_StillReported;
// TP-Gegenkontrolle: zwei `inherited` im SELBEN {$IFDEF}-Block (Direktive nur
// davor/danach, NICHT dazwischen) laufen beide -> muss weiter Befund sein.
// Sichert ab dass der Guard nur bei Direktive ZWISCHEN den Calls greift.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '{$IFDEF WIN32}'#13#10 +
  '  inherited;'#13#10 +
  '  inherited;'#13#10 +
  '{$ENDIF}'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTwiceInheritedCalls),
    'zwei inherited im selben {$IFDEF}-Block laufen beide - bleibt Befund');
  finally F.Free; end;
end;

procedure TTestTwiceInheritedCalls.InheritedPairInNestedBlock_Reported;
// Testluecke 115 (Voll-Review 2026-09-12): der Detektor sucht ueber
// FindAll(nkBlock), also auch in GESCHACHTELTEN begin..end-Bloecken -
// getestet war nur der Wurzelblock. An der Bestands-Exe verifiziert:
// das Paar im if-Block wird gemeldet.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TChild.Run;'#13#10 +
  'begin'#13#10 +
  '  if X then'#13#10 +
  '  begin'#13#10 +
  '    inherited;'#13#10 +
  '    inherited;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTwiceInheritedCalls),
    'auch ein geschachtelter Block wird auf doppelte inherited geprueft');
  finally F.Free; end;
end;

procedure TTestTwiceInheritedCalls.BareAndQualifiedInheritedMixed_Reported;
// Mischform im SELBEN Block: bares 'inherited;' und qualifiziertes
// 'inherited Run;'. Beide zaehlen - aber NUR, weil der qualifizierte
// Aufruf DIESELBE Methode nennt: QualifyingInheritedInBlock vergleicht
// LeadingInheritedIdent gegen den kurzen Methodennamen.
//
// Genau daran ist die erste Fassung dieses Tests gescheitert (sie nahm
// 'inherited Bar;' und erwartete einen Fund). An der Bestands-Exe
// gemessen: mit 'inherited Run;' 1 Fund, mit 'inherited Bar;' 0 - die
// Gegenprobe steht direkt darunter.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TChild.Run;'#13#10 +
  'begin'#13#10 +
  '  inherited;'#13#10 +
  '  inherited Run;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTwiceInheritedCalls),
    'bare und gleichnamig qualifizierte Form zaehlen gemeinsam');
  finally F.Free; end;
end;

procedure TTestTwiceInheritedCalls.QualifiedInheritedOtherMethod_NoFinding;
// Gegenprobe zur Mischform: nennt der qualifizierte Aufruf eine ANDERE
// Methode ('inherited Bar;' in TChild.Run), ist es kein doppelter
// Aufruf derselben geerbten Methode - kein Fund (Bestands-Exe: 0).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TChild.Run;'#13#10 +
  'begin'#13#10 +
  '  inherited;'#13#10 +
  '  inherited Bar;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTwiceInheritedCalls),
    'ein qualifizierter Aufruf einer anderen Methode zaehlt nicht mit');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestTwiceInheritedCalls);

end.

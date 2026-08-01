unit uTestUnusedRoutine;

// Tests fuer TUnusedRoutineDetector (SCA164).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUnusedRoutine = class
  public
    // ---- Positive: Standalone-Implementation ohne Aufruf -----------------
    [Test] procedure Unused_StandaloneImpl_Reported;
    [Test] procedure Unused_StandaloneFunctionImpl_Reported;
    [Test] procedure Unused_RecursiveSelfCallOnly_Reported;
    [Test] procedure Unused_NeverCalledBetweenOtherRoutines_Reported;

    // ---- Negative: irgendein Caller existiert ----------------------------
    [Test] procedure Unused_StandaloneCalledOnce_NoFinding;
    [Test] procedure Unused_StandaloneCalledTwice_NoFinding;
    [Test] procedure Unused_CallerInOtherRoutine_NoFinding;

    // ---- Negative: FP-Guards -------------------------------------------
    [Test] procedure Unused_ConstructorStandalone_NoFinding;
    [Test] procedure Unused_DestructorStandalone_NoFinding;
    [Test] procedure Unused_RegisterProcedure_NoFinding;
    [Test] procedure Unused_InterfaceForwardDeclared_NoFinding;
    [Test] procedure Unused_ClassMethodImpl_NoFinding;

    // ---- Finding-Inhalt --------------------------------------------------
    // ---- Link-Gates (30%-Audit 2026-07-31) --------------------------------
    [Test] procedure Unused_ExternalImport_NoFinding;
    [Test] procedure Unused_CdeclInObjLinkingUnit_NoFinding;
    [Test] procedure Unused_LibPrefixDirective_IsNotObjLink;
    [Test] procedure Unused_PascalHelperInObjLinkingUnit_StillReported;

    [Test] procedure Unused_Finding_KindSeverityConfidence;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestUnusedRoutine.Unused_StandaloneImpl_Reported;
// Klassischer Fall: Routine nur in implementation, nirgends gerufen.
const SRC =
  'unit t; interface implementation'#13#10 +
  'procedure InternalHelper;'#13#10 +
  'begin'#13#10 +
  '  WriteLn(''hi'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnusedRoutine) >= 1);
  finally F.Free; end;
end;

procedure TTestUnusedRoutine.Unused_StandaloneFunctionImpl_Reported;
const SRC =
  'unit t; interface implementation'#13#10 +
  'function Compute: Integer;'#13#10 +
  'begin'#13#10 +
  '  Result := 42;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnusedRoutine) >= 1);
  finally F.Free; end;
end;

procedure TTestUnusedRoutine.Unused_RecursiveSelfCallOnly_Reported;
// Self-Call darf NICHT als Verwendung zaehlen - sonst wuerde eine rekursive
// dead Routine niemals geflagged. Mirror von SonarDelphi
// testUnusedRecursiveRoutineShouldAddIssue.
const SRC =
  'unit t; interface implementation'#13#10 +
  'procedure Recurse(N: Integer);'#13#10 +
  'begin'#13#10 +
  '  if N > 0 then Recurse(N - 1);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnusedRoutine) >= 1);
  finally F.Free; end;
end;

procedure TTestUnusedRoutine.Unused_NeverCalledBetweenOtherRoutines_Reported;
// Routine in der Mitte, andere Routinen rundherum die sie NICHT rufen.
// Stellt sicher dass die Routine-Range korrekt geschnitten wird.
const SRC =
  'unit t; interface implementation'#13#10 +
  'procedure First;'#13#10 +
  'begin WriteLn(''first''); end;'#13#10 +
  'procedure Middle;'#13#10 +
  'begin WriteLn(''middle''); end;'#13#10 +
  'procedure Last;'#13#10 +
  'begin'#13#10 +
  '  First;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    // First wird von Last gerufen -> kein Finding fuer First.
    // Middle wird nirgends gerufen -> Finding.
    // Last wird nirgends gerufen -> Finding.
    Assert.IsTrue(TFindingHelper.Count(F, fkUnusedRoutine) >= 2,
      'Middle UND Last muessen als unused gemeldet werden, First nicht');
  finally F.Free; end;
end;

procedure TTestUnusedRoutine.Unused_StandaloneCalledOnce_NoFinding;
const SRC =
  'unit t; interface implementation'#13#10 +
  'procedure Helper;'#13#10 +
  'begin WriteLn(''hi''); end;'#13#10 +
  'procedure Main;'#13#10 +
  'begin'#13#10 +
  '  Helper;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    // Helper wird einmal gerufen -> kein Finding fuer Helper.
    // Main wird nirgends gerufen -> Finding fuer Main.
    // Wir asserten genau: KEIN Finding mit MethodName='Helper'.
    var FoundHelper := False;
    for var Fnd in F do
      if (Fnd.Kind = fkUnusedRoutine) and SameText(Fnd.MethodName, 'Helper') then
        FoundHelper := True;
    Assert.IsFalse(FoundHelper, 'Helper wird gerufen, darf nicht geflagged sein');
  finally F.Free; end;
end;

procedure TTestUnusedRoutine.Unused_StandaloneCalledTwice_NoFinding;
const SRC =
  'unit t; interface implementation'#13#10 +
  'procedure Helper;'#13#10 +
  'begin WriteLn(''hi''); end;'#13#10 +
  'procedure A;'#13#10 +
  'begin Helper; end;'#13#10 +
  'procedure B;'#13#10 +
  'begin Helper; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    var FoundHelper := False;
    for var Fnd in F do
      if (Fnd.Kind = fkUnusedRoutine) and SameText(Fnd.MethodName, 'Helper') then
        FoundHelper := True;
    Assert.IsFalse(FoundHelper);
  finally F.Free; end;
end;

procedure TTestUnusedRoutine.Unused_CallerInOtherRoutine_NoFinding;
// Routine in derselben Unit, aber in einer anderen Routine gerufen.
const SRC =
  'unit t; interface implementation'#13#10 +
  'procedure Worker;'#13#10 +
  'begin WriteLn(''work''); end;'#13#10 +
  'procedure Entry;'#13#10 +
  'begin'#13#10 +
  '  Worker;'#13#10 +
  '  Worker;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    var FoundWorker := False;
    for var Fnd in F do
      if (Fnd.Kind = fkUnusedRoutine) and SameText(Fnd.MethodName, 'Worker') then
        FoundWorker := True;
    Assert.IsFalse(FoundWorker);
  finally F.Free; end;
end;

procedure TTestUnusedRoutine.Unused_ConstructorStandalone_NoFinding;
// Constructor/Destructor sind nicht direkt callbar - sie laufen implizit
// via Class.Create / FreeAndNil. Wir flaggen sie nicht (synthetischer
// Case - in echtem Code stehen Constructors immer in Klassen).
const SRC =
  'unit t; interface implementation'#13#10 +
  'constructor Init;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedRoutine));
  finally F.Free; end;
end;

procedure TTestUnusedRoutine.Unused_DestructorStandalone_NoFinding;
const SRC =
  'unit t; interface implementation'#13#10 +
  'destructor Done;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedRoutine));
  finally F.Free; end;
end;

procedure TTestUnusedRoutine.Unused_RegisterProcedure_NoFinding;
// `procedure Register;` ist die IDE-Plugin-Bootstrap-Konvention - die
// IDE ruft sie via Pkg-Loader implicit. Darf nicht geflagged werden.
const SRC =
  'unit t; interface implementation'#13#10 +
  'procedure Register;'#13#10 +
  'begin'#13#10 +
  '  RegisterComponents(''MyPalette'', [TMyComponent]);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedRoutine));
  finally F.Free; end;
end;

procedure TTestUnusedRoutine.Unused_InterfaceForwardDeclared_NoFinding;
// Routine mit Forward-Decl im interface koennte cross-unit gerufen werden -
// ohne Bare-Call-Index unentscheidbar -> nicht flaggen (MVP-Verhalten).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'procedure ExportedHelper;'#13#10 +
  'implementation'#13#10 +
  'procedure ExportedHelper;'#13#10 +
  'begin'#13#10 +
  '  WriteLn(''export'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedRoutine));
  finally F.Free; end;
end;

procedure TTestUnusedRoutine.Unused_ClassMethodImpl_NoFinding;
// Qualifizierter Name (TFoo.Bar) ist Klassen-Methoden-Impl - wird durch
// SCA147 / SCA148+ abgedeckt, nicht von uns geflagged (Filter im Detector).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  procedure Bar;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedRoutine));
  finally F.Free; end;
end;

procedure TTestUnusedRoutine.Unused_Finding_KindSeverityConfidence;
const SRC =
  'unit t; interface implementation'#13#10 +
  'procedure DeadHelper;'#13#10 +
  'begin'#13#10 +
  '  WriteLn(''dead'');'#13#10 +
  'end;'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkUnusedRoutine then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.AreEqual(fkUnusedRoutine, Hit.Kind);
    Assert.AreEqual(lsHint, Hit.Severity,
      'fkUnusedRoutine soll lsHint sein (Code Smell, kein Bug)');
    Assert.AreEqual(fcHigh, Hit.Confidence,
      'Implementation-only ohne Forward-Decl ist hochkonfident');
  finally F.Free; end;
end;

procedure TTestUnusedRoutine.Unused_ExternalImport_NoFinding;
// Korpus-Beleg Kastri DW.Biometric.iOS.pas:407: der Link-Anker wird NIE
// gerufen - genau das ist sein Zweck. Ein Import ist keine Implementation.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure LocalAuthenticationLoader; cdecl; external ''libLocalAuth'';'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedRoutine),
    'Rumpflose external-Deklaration ist ein Import, kein toter Code');
  finally F.Free; end;
end;

procedure TTestUnusedRoutine.Unused_CdeclInObjLinkingUnit_NoFinding;
// Korpus-Beleg mORMot mormot.lib.quickjs.pas:2081: 'acosh' existiert fuer
// das statisch gelinkte quickjs.obj. Der Aufrufer ist der C-Code, nicht
// Pascal - Entfernen bricht den Link.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  '{$L quickjs.obj}'#13#10 +
  'function acosh(x: double): double; cdecl;'#13#10 +
  'begin'#13#10 +
  '  Result := x;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedRoutine),
    'C-Aufrufkonvention in einer obj-linkenden Unit ist kein toter Code');
  finally F.Free; end;
end;

procedure TTestUnusedRoutine.Unused_LibPrefixDirective_IsNotObjLink;
// WAECHTER gegen die naheliegende Praefix-Falle: '{$LIBPREFIX' faengt
// ebenfalls mit '{$L' an, ist aber kein Objekt-Link. Das Gate darf hier
// nicht greifen, sonst verschwindet die ganze Unit aus der Regel.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  '{$LIBPREFIX ''''}'#13#10 +
  'procedure DeadHelper; cdecl;'#13#10 +
  'begin'#13#10 +
  '  Beep;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedRoutine),
    '{$LIBPREFIX} ist kein {$L} - das Link-Gate darf nicht greifen');
  finally F.Free; end;
end;

procedure TTestUnusedRoutine.Unused_PascalHelperInObjLinkingUnit_StillReported;
// WAECHTER: in einer obj-linkenden Unit wird NICHT alles stillgeschaltet.
// Ein reiner Pascal-Helfer ohne Aufrufkonvention kann vom C-Code nicht
// gerufen werden und bleibt pruefbar.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  '{$L quickjs.obj}'#13#10 +
  'procedure PascalOnlyHelper;'#13#10 +
  'begin'#13#10 +
  '  Beep;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedRoutine),
    'Pascal-Helfer ohne Aufrufkonvention bleibt auch in obj-Units ein Fund');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnusedRoutine);

end.

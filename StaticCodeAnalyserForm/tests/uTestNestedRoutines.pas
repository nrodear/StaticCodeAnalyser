unit uTestNestedRoutines;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestNestedRoutines = class
  public
    [Test] procedure FlatRoutines_NoFinding;
    [Test] procedure NestedProc_Reported;
    [Test] procedure NestedRoutines_KindAndSeverity;
    // --- True Positives: der Existenzgrund der Regel ---------------------
    [Test] procedure NestedInMethodBody_Reported;
    [Test] procedure NestedInMethodBody_AnchorLine;
    [Test] procedure NestedInFreeRoutine_Reported;
    [Test] procedure SecondLevelNesting_BothReported;
    // --- FP-Klassen aus dem 30%-Audit 2026-07-31 (SCA102) ----------------
    [Test] procedure ClassMethodDeclarations_NoFinding;
    [Test] procedure InterfaceSectionAfterCommentWord_NoFinding;
    [Test] procedure ExternalRoutines_NoFinding;
    [Test] procedure ForwardDeclarations_NoFinding;
    [Test] procedure SingleLineRoutines_NoFinding;
    [Test] procedure IfdefTwinSameName_NoFinding;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestNestedRoutines.FlatRoutines_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure InnerHelper;'#13#10 +
  'begin'#13#10 +
  '  DoX;'#13#10 +
  'end;'#13#10 +
  'procedure Outer;'#13#10 +
  'begin'#13#10 +
  '  InnerHelper;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNestedRoutine));
  finally F.Free; end;
end;

procedure TTestNestedRoutines.NestedProc_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Outer;'#13#10 +
  '  procedure Inner;'#13#10 +
  '  begin'#13#10 +
  '    DoX;'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  Inner;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkNestedRoutine) >= 1);
  finally F.Free; end;
end;

procedure TTestNestedRoutines.NestedRoutines_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Outer;'#13#10 +
  '  procedure Inner;'#13#10 +
  '  begin'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  Inner;'#13#10 +
  'end;';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkNestedRoutine then
      begin
        Assert.AreEqual<TFindingKind>(fkNestedRoutine, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,         Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkNestedRoutine finding');
  finally Findings.Free; end;
end;

// ===========================================================================
// True Positives - muessen die FP-Haertung von 2026-07-31 ueberleben.
// ===========================================================================

const
  // Echte lokale Routine in einer METHODEN-Implementierung (nach dem
  // lokalen var-Block). Genau dafuer gibt es die Regel.
  SRC_NESTED_IN_METHOD =
    'unit t; implementation'#13#10 +
    'procedure TFoo.Bar;'#13#10 +
    'var'#13#10 +
    '  X: Integer;'#13#10 +
    ''#13#10 +
    '  procedure Helper;'#13#10 +
    '  begin'#13#10 +
    '    X := 1;'#13#10 +
    '  end;'#13#10 +
    ''#13#10 +
    'begin'#13#10 +
    '  Helper;'#13#10 +
    'end;';

procedure TTestNestedRoutines.NestedInMethodBody_Reported;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC_NESTED_IN_METHOD);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkNestedRoutine));
  finally F.Free; end;
end;

procedure TTestNestedRoutines.NestedInMethodBody_AnchorLine;
// Monotonie-Gate der FP-Haertung: der ueberlebende Fund darf sich nicht
// verschieben - er zeigt weiter auf die Zeile der inneren Routine.
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC_NESTED_IN_METHOD);
  try
    Fnd := TFindingHelper.FirstOf(F, fkNestedRoutine);
    Assert.IsNotNull(Fnd, 'expected fkNestedRoutine finding');
    Assert.AreEqual(
      TFindingHelper.LineOf(SRC_NESTED_IN_METHOD, 'procedure Helper;'),
      Fnd.LineNumber);
  finally F.Free; end;
end;

procedure TTestNestedRoutines.NestedInFreeRoutine_Reported;
// Nested routine in einer FREIEN (nicht an eine Klasse gebundenen) Funktion.
const SRC =
  'unit t; implementation'#13#10 +
  'function Compute(A: Integer): Integer;'#13#10 +
  'var'#13#10 +
  '  T: Integer;'#13#10 +
  ''#13#10 +
  '  function Twice(V: Integer): Integer;'#13#10 +
  '  begin'#13#10 +
  '    Result := V * 2;'#13#10 +
  '  end;'#13#10 +
  ''#13#10 +
  'begin'#13#10 +
  '  T := Twice(A);'#13#10 +
  '  Result := T;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkNestedRoutine));
  finally F.Free; end;
end;

procedure TTestNestedRoutines.SecondLevelNesting_BothReported;
// Verschachtelung zweiter Ebene: Middle (in Outer) UND Inner (in Middle).
// Deckt die Ketten-Aufloesung bvChain ab - Outer und Middle haben kein
// direkt folgendes `begin`, ihr Rumpf-Beweis kommt ueber die Kette.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Outer;'#13#10 +
  '  procedure Middle;'#13#10 +
  '    procedure Inner;'#13#10 +
  '    begin'#13#10 +
  '      DoX;'#13#10 +
  '    end;'#13#10 +
  '  begin'#13#10 +
  '    Inner;'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  Middle;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkNestedRoutine));
  finally F.Free; end;
end;

// ===========================================================================
// FP-Klassen aus Todo_Funde_Detector_SCA102_2026-07-31.
// Jeder dieser Tests war vor der Haertung ROT (Fundzahl in Klammern).
// ===========================================================================

procedure TTestNestedRoutines.ClassMethodDeclarations_NoFinding;
// FP-Klasse 1 (16 von 24 im Audit-Sample), vorher 2 Funde: aufeinander
// folgende Methoden-DEKLARATIONEN in einer Typdeklaration sind keine
// nested routines - sie haben keinen Rumpf.
const SRC =
  'unit t; implementation'#13#10 +
  'type'#13#10 +
  '  TFoo = class(TObject)'#13#10 +
  '    procedure Alpha;'#13#10 +
  '    procedure Beta;'#13#10 +
  '    function Gamma: Integer;'#13#10 +
  '  end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNestedRoutine));
  finally F.Free; end;
end;

procedure TTestNestedRoutines.InterfaceSectionAfterCommentWord_NoFinding;
// FP-Klasse 2 / Ursache Nr. 1 (Gate A), vorher 1 Fund: das Wort
// `implementation` in einem KOMMENTAR schaltete den Automaten mitten in
// die interface-Section, wo dann Prototypen als nested gemeldet wurden.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  '// the real implementation lives further down'#13#10 +
  'procedure Alpha(A: Integer);'#13#10 +
  'procedure Beta(B: Integer);'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNestedRoutine));
  finally F.Free; end;
end;

procedure TTestNestedRoutines.ExternalRoutines_NoFinding;
// FP-Klasse 2 (external-Prototypen), vorher 1 Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'function AAA(X: Integer): Integer; external ''a.dll'';'#13#10 +
  'function BBB(X: Integer): Integer; external ''a.dll'';'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNestedRoutine));
  finally F.Free; end;
end;

procedure TTestNestedRoutines.ForwardDeclarations_NoFinding;
// FP-Klasse 2 (forward-Deklarationen), vorher 1 Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure AAA; forward;'#13#10 +
  'procedure BBB; forward;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNestedRoutine));
  finally F.Free; end;
end;

procedure TTestNestedRoutines.SingleLineRoutines_NoFinding;
// Gate C, vorher 1 Fund: Kopf + Rumpf auf EINER Zeile hinterlaesst keine
// lokale Decl-Section - der Nachbar auf der Folgezeile ist Unit-Ebene.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure AAA; begin DoX; end;'#13#10 +
  'procedure BBB; begin DoY; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNestedRoutine));
  finally F.Free; end;
end;

procedure TTestNestedRoutines.IfdefTwinSameName_NoFinding;
// Gate D, vorher 1 Fund: zwei Koepfe derselben Routine in verschiedenen
// Praeprozessor-Zweigen teilen sich EINEN Rumpf. Da {$...} wie ein
// Kommentar gestrippt wird, standen sie fuer den Automaten direkt
// hintereinander.
const SRC =
  'unit t; implementation'#13#10 +
  '{$IFDEF UNICODE}'#13#10 +
  'procedure TFoo.Bar(A: Integer);'#13#10 +
  '{$ELSE}'#13#10 +
  'procedure TFoo.Bar(A: string);'#13#10 +
  '{$ENDIF}'#13#10 +
  'begin'#13#10 +
  '  DoX;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNestedRoutine));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNestedRoutines);

end.

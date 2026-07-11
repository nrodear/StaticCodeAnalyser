unit uTestDebugOutput;

// Tests fuer den TDebugOutputDetector.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestSrcBuilder,
  uTestFindingHelper;

type
  // ---- DebugOutput (TDebugOutputDetector) --------------------------------------------
  [TestFixture]
  TTestDebugOutput = class
  public
    [Test] procedure Debug_WriteLnCall_ReportsWarning;
    [Test] procedure Debug_ShowMessageCall_ReportsWarning;
    // Scope-Entscheidung 2026-07-11: MessageDlg + InputBox sind keine SCA017-
    // Ziele mehr (bewusste UI bzw. Eingabe-Primitiv) -> NoFinding.
    [Test] procedure Debug_MessageDlg_NoFinding;
    [Test] procedure Debug_OutputDebugStringCall_ReportsWarning;
    [Test] procedure Debug_InputBox_NoFinding;
    [Test] procedure Debug_NormalCall_NoFinding;
    [Test] procedure Debug_PrefixedNameWordBoundary_NoFalsePositive;
    [Test] procedure Debug_LoggerWriteCall_NoFalsePositive;
    [Test] procedure Debug_TwoDebugCalls_BothReported;
    [Test] procedure Debug_ShowMessagePosCall_ReportsWarning;
    // Real-World FP-Audit 2026-07-10: member-qualifiziertes WriteLn
    [Test] procedure Debug_MemberQualifiedWriteLn_NoFinding;
    [Test] procedure Debug_SystemQualifiedWriteLn_ReportsWarning;
  end;

implementation

// =============================================================================
// DebugOutput-Tests
// =============================================================================

procedure TTestDebugOutput.Debug_WriteLnCall_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin WriteLn(''debug''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_ShowMessageCall_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin ShowMessage(''Hallo''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_MessageDlg_NoFinding;
// Scope-Entscheidung 2026-07-11 (Real-World-FP-Audit): MessageDlg mit mt*-Typ +
// [mb*]-Button-Set ist bewusste strukturierte UI, kein vergessenes Debug-Popup
// -> kein Ziel mehr. (ShowMessage bleibt Ziel, s. Debug_ShowMessageCall.)
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin MessageDlg(''ok'', mtInformation, [mbOK], 0); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDebugOutput),
    'MessageDlg ist bewusste UI, kein SCA017-Ziel mehr');
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_OutputDebugStringCall_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin OutputDebugString(''hi''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_InputBox_NoFinding;
// Scope-Entscheidung 2026-07-11 (Real-World-FP-Audit): InputBox/InputQuery sind
// Eingabe-Primitive (liefern einen Wert statt Output) -> kein SCA017-Ziel mehr.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin s := InputBox(''titel'', ''prompt'', ''default''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDebugOutput),
    'InputBox ist Eingabe-Primitiv, kein SCA017-Ziel mehr');
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_NormalCall_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin Logger.Info(''ok''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_PrefixedNameWordBoundary_NoFalsePositive;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin MyWriteLn(''hi''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_LoggerWriteCall_NoFalsePositive;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin Logger.WriteEntry(''msg''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_TwoDebugCalls_BothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  WriteLn(''a'');'#13#10+
  '  ShowMessage(''b'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_ShowMessagePosCall_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin ShowMessagePos(''x'', 100, 100); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_MemberQualifiedWriteLn_NoFinding;
// Real-World FP-Audit 2026-07-10: Self.WriteLn / FConsoleWriter.WriteLn ist eine
// eigene Writer-/Logging-Methode der Klasse, KEIN RTL-Debug-Output.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  Self.WriteLn(''x'');'#13#10+
  '  FConsoleWriter.WriteLn(''y'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDebugOutput),
    'member-qualifiziertes WriteLn ist eigene Methode, kein RTL-Debug');
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_SystemQualifiedWriteLn_ReportsWarning;
// Gegenprobe: System.WriteLn IST das RTL-WriteLn -> bleibt Fund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin System.WriteLn(''debug''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDebugOutput),
    'System.WriteLn ist RTL-Debug-Output');
  finally F.Free; end;
end;

end.

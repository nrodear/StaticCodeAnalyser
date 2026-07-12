unit uTestHardcodedPath;

// Tests fuer den THardcodedPathDetector.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestSrcBuilder,
  uTestFindingHelper;

type
  // ---- HardcodedPath (THardcodedPathDetector) ----------------------------------------
  [TestFixture]
  TTestHardcodedPath = class
  public
    [Test] procedure Path_WindowsDriveBackslash_ReportsWarning;
    [Test] procedure Path_WindowsDriveForwardslash_ReportsWarning;
    [Test] procedure Path_UNCPath_ReportsWarning;
    [Test] procedure Path_UnixUsr_SystemPath_NoFinding;
    [Test] procedure Path_UnixEtc_SystemPath_NoFinding;
    [Test] procedure Path_UnixTmp_SystemPath_NoFinding;
    [Test] procedure Path_UnixOpt_ReportsWarning;
    [Test] procedure Path_UnixHome_ReportsWarning;
    [Test] procedure Path_UnixHomeShort_ReportsWarning;
    [Test] procedure Path_RegularString_NoFinding;
    [Test] procedure Path_RelativePath_NoFinding;
    [Test] procedure Path_SameDuplicateOnce_NotDuplicated;
    // ---- Severity / Finding-Inhalt / Multi-Hit ---------------------------
    [Test] procedure Path_Finding_KindAndSeverity;
    [Test] procedure Path_Finding_MissingVarMentionsPath;
    [Test] procedure Path_MultipleHitsInSameMethod_AllReported;
    // ---- Real-World-FP-Audit 2026-07-12: test-vector/expected-value -------
    [Test] procedure Path_AssertAreEqualExpectedValue_NoFinding;
    [Test] procedure Path_DUnitCheckComparison_NoFinding;
    [Test] procedure Path_NonAssertionCallWithPath_StillReported;
  end;

implementation

// =============================================================================
// HardcodedPath-Tests
// =============================================================================

procedure TTestHardcodedPath.Path_WindowsDriveBackslash_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''C:\Windows\System32'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_WindowsDriveForwardslash_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''D:/Daten/projekt'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_UNCPath_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''\\fileserver\share\sub'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_UnixUsr_SystemPath_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''/usr/local/bin/foo'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_UnixEtc_SystemPath_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''/etc/hosts'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_UnixTmp_SystemPath_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''/tmp/sca_test_file.tmp'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_UnixOpt_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''/opt/myapp/config'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_UnixHome_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''/home/user/.config'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_UnixHomeShort_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''~/projects/src'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_RegularString_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''hello world'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_RelativePath_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''subdir/file.txt'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_SameDuplicateOnce_NotDuplicated;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin'#13#10+
  '  p := ''C:\Temp'';'#13#10+
  '  p := ''C:\Temp'';'#13#10+
  '  p := ''C:\Temp'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''C:\Windows\System32''; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkHardcodedPath then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkHardcodedPath finding expected');
    Assert.AreEqual(fkHardcodedPath, Hit.Kind);
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_Finding_MissingVarMentionsPath;
// MissingVar muss den eigentlichen Pfad enthalten, sonst kann der User
// im Grid nicht erkennen welcher String getroffen wurde.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''C:\MyProjects\Secrets''; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkHardcodedPath then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.Contains(Hit.MissingVar, 'C:\MyProjects\Secrets');
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_MultipleHitsInSameMethod_AllReported;
// Zwei verschiedene hardgecodete Pfade in derselben Methode -> beide Findings.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p, q: string;'#13#10+
  'begin'#13#10+
  '  p := ''C:\Windows\System32'';'#13#10+
  '  q := ''/home/user/secret'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

// =============================================================================
// Real-World-FP-Audit 2026-07-12 - FP-Klasse 'test-vector-/expected-value-
// Pfadliteral': pfadfoermige Literale, die nur als Erwartungs-/Vergleichswert
// eines Assertions-Aufrufs dienen, beruehren nie das Dateisystem.
// =============================================================================

procedure TTestHardcodedPath.Path_AssertAreEqualExpectedValue_NoFinding;
// FP-Suppression: Pfad als Erwartungswert in Assert.AreEqual (DUnitX). Wie im
// Real-World-Sample ALDUnitXTestStringUtils.pas (Assert.AreEqual('C:\Temp\File',
// actual)) - kein Datei-Zugriff, daher kein Fund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  Assert.AreEqual(''C:\Temp\File'', s);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_DUnitCheckComparison_NoFinding;
// FP-Suppression: Pfad als Vergleichs-Operand in klassischem DUnit Check(...).
// Wie im Real-World-Sample TestJclDebug.pas (Check((s = 'C:\TEST\FOO.OBJ') ...)).
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  Check(s = ''C:\TEST\FOO.OBJ'', ''mismatch'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_NonAssertionCallWithPath_StillReported;
// TP-Gegenprobe: derselbe Pfad-Literal in einem echten Datei-Aufruf
// (kein Assertions-Callee) bleibt Fund - die Assertions-Suppression darf
// Produktions-Datei-Operationen NICHT verschlucken.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var sl: TStringList;'#13#10+
  'begin'#13#10+
  '  sl.SaveToFile(''C:\Temp\File'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

end.

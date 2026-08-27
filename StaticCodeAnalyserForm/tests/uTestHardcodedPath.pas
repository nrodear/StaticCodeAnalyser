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
    // ---- SCA016-FP-Paket 2026-08-27, Gate A: lokaler Test*-Vektorhelfer ---
    [Test] procedure Path_TestVectorHelperInTestUnit_NoFinding;
    [Test] procedure Path_QualifiedTestVectorHelperInTestUnit_NoFinding;
    [Test] procedure Path_TestVectorHelperInProductionUnit_StillReported;
    [Test] procedure Path_FileOperationInTestUnit_StillReported;
    // ---- Gate B: mORMot-Assertionsfamilie ---------------------------------
    [Test] procedure Path_MormotCheckEqual_NoFinding;
    [Test] procedure Path_CheckFileExists_StillReported;
    // ---- Gate C: OS-feste UNC-Namespaces ----------------------------------
    [Test] procedure Path_OsFixedUncNamespaces_NoFinding;
    [Test] procedure Path_AdminShare_StillReported;
  end;

implementation

uses
  // Nur fuer HardcodedPathFindingsFor (Gate A braucht einen frei waehlbaren
  // Dateinamen); im Interface werden sie nicht gebraucht.
  uAstNode, uParser2, uHardcodedPath;

// Der zentrale Harness TFindingHelper.FindingsOf verwendet den festen
// Platzhalter-Dateinamen 'sample.pas'. Gate A (SCA016-FP-Paket 2026-08-27)
// haengt aber am Dateinamen (TDetectorUtils.IsTestFixturePath/tplSecret),
// deshalb hier ein schlanker Direkt-Aufruf nur dieses Detektors mit frei
// waehlbarem Namen - dasselbe Muster wie SqlDangerFindingsFor in
// uTestSqlDangerousStatement. Der Detektor laeuft regulaer im AST-Harness
// (FindingsOf) - s. uTestFindingHelper Z.150.
//
// Die Namen sind bewusst BLOSSE Basisnamen ohne Verzeichnis: tplSecret
// matched 'PathFunc.Test.pas' schon ueber die Basename-Regel '*test.pas'.
// Ein Testname mit Laufwerksbuchstaben waere selbst ein Pfadliteral in einem
// nkCall und zwaenge dieser Datei ein 'noinspection-file HardcodedPath' auf
// (so wie in uTestSqlDangerousStatement, wo die Segment-Verankerung echte
// Verzeichnisse braucht). Hier ist das nicht noetig.
function HardcodedPathFindingsFor(const ASource, AFileName: string)
  : TObjectList<TLeakFinding>;
var
  P    : TParser2;
  Root : TAstNode;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  P := TParser2.Create;
  try
    Root := P.ParseSource(ASource);
    try
      THardcodedPathDetector.AnalyzeUnit(Root, AFileName, Result);
    finally
      Root.Free;
    end;
  finally
    P.Free;
  end;
end;

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

// =============================================================================
// SCA016-FP-Paket 2026-08-27, Gate A - lokaler 'Test*'-Vektorhelfer in einer
// Test-Unit. Der Callee loest IsAssertionCall nicht aus (er heisst nicht
// Assert/Check/AreEqual), das Pfadliteral ist trotzdem ein Testvektor.
// 98 Funde im Korpus, 94 davon in issrc\Components\PathFunc.Test.pas.
//
// Die naechsten drei Tests sind ein kontrolliertes A/B: Test 1 und 3 teilen
// WOERTLICH denselben Quelltext und unterscheiden sich nur im Dateinamen,
// Test 4 teilt den Dateinamen mit Test 1 und unterscheidet sich nur im
// Callee. So ist belegt, dass BEIDE Bedingungen des Gates tragen.
// =============================================================================

const
  // Auf einen Pfad reduzierter Testvektor-Aufruf im Stil von
  // PathFunc.Test.pas (dort z.B. TestPathCombine mit Dir, Datei und
  // Erwartungswert) - ein Literal genuegt, die Fundzahl bleibt so ablesbar.
  SRC_TEST_VECTOR_CALL =
    'unit t; implementation'#13#10+
    'procedure Foo;'#13#10+
    'var s: string;'#13#10+
    'begin'#13#10+
    '  TestPathCombine(''C:\Temp\x'', s);'#13#10+
    'end;';
  // '*test.pas' ist eine tplSecret-Basename-Regel - der Name reicht, ein
  // Verzeichnis braucht das Gate hier nicht.
  TEST_UNIT_NAME = 'PathFunc.Test.pas';
  PROD_UNIT_NAME = 'PathFunc.pas';

procedure TTestHardcodedPath.Path_TestVectorHelperInTestUnit_NoFinding;
// Gate A greift: Test-Unit UND 'Test*'-Callee.
var F: TObjectList<TLeakFinding>;
begin
  F := HardcodedPathFindingsFor(SRC_TEST_VECTOR_CALL, TEST_UNIT_NAME);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_QualifiedTestVectorHelperInTestUnit_NoFinding;
// Pin fuer die Qualifizierungs-Entscheidung: geprueft wird der Namensteil
// HINTER dem letzten Punkt, also greift 'Self.TestPathCombine' genauso wie
// der unqualifizierte Aufruf. Am Korpus messneutral (alle 98 Treffer sind
// unqualifiziert) - dieser Test haelt die Entscheidung trotzdem fest, damit
// sie nicht unbemerkt zurueckgedreht wird.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  Self.TestPathCombine(''C:\Temp\x'', s);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := HardcodedPathFindingsFor(SRC, TEST_UNIT_NAME);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_TestVectorHelperInProductionUnit_StillReported;
// TP-Gegenprobe zu Gate A, Achse Dateiname: WOERTLICH derselbe Quelltext wie
// Path_TestVectorHelperInTestUnit_NoFinding, nur in einer Produktions-Unit.
// Der Callee-Praefix allein darf nichts unterdruecken - sonst faellt auch
// ein echter Hardcode wie 'TestConnection(''C:\db.fdb'')' unter den Tisch.
var F: TObjectList<TLeakFinding>;
begin
  F := HardcodedPathFindingsFor(SRC_TEST_VECTOR_CALL, PROD_UNIT_NAME);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_FileOperationInTestUnit_StillReported;
// TP-Gegenprobe zu Gate A, Achse Callee: derselbe Dateiname wie
// Path_TestVectorHelperInTestUnit_NoFinding, aber eine echte Datei-Operation.
// Ein Fixture-Setup, das nach 'C:\Temp\out.log' schreibt, ist auch in einer
// Test-Unit umgebungsabhaengig und bleibt Fund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var sl: TStringList;'#13#10+
  'begin'#13#10+
  '  sl.SaveToFile(''C:\Temp\out.log'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := HardcodedPathFindingsFor(SRC, TEST_UNIT_NAME);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

// =============================================================================
// Gate B - mORMots Assertionsfamilie (TSynTestCase.CheckEqual & Co.).
// 7 Funde im Korpus, u.a. mORMot2-master\test\test.core.base.pas:958.
// =============================================================================

procedure TTestHardcodedPath.Path_MormotCheckEqual_NoFinding;
// Woertlich test.core.base.pas:958. Der Pfad steckt im Argument eines
// GESCHACHTELTEN Aufrufs - der Parser faltet die ganze Argumentliste in EINEN
// nkCall-Namen, der aeussere Callee 'CheckEqual' entscheidet also allein.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  CheckEqual(GetFileNameWithoutExtOrPath(''c:\temp\toto.ext''), ''toto'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_CheckFileExists_StillReported;
// TP-Gegenprobe zu Gate B: die Liste matched EXAKT, nicht als Praefix.
// 'CheckFileExists' faengt mit dem Listeneintrag 'check' an, ist aber eine
// echte Datei-Operation. Mit einem Praefix-Match waere dieser Test rot -
// genau davor warnt der Kommentar in uHardcodedPath, seit die Liste mit
// Gate B von sechs auf zwoelf Eintraege gewachsen ist.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  CheckFileExists(''C:\Temp\marker.txt'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

// =============================================================================
// Gate C - OS-feste UNC-Namespaces. 3 Funde im Korpus (doublecmd:
// uwslfilesource.pas, udrivewatcher.pas).
// =============================================================================

procedure TTestHardcodedPath.Path_OsFixedUncNamespaces_NoFinding;
// Diese drei Wurzeln vergibt Windows fest; es steckt kein Host- oder
// Freigabename darin, also nichts, was man konfigurierbar machen koennte.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p, q, r: string;'#13#10+
  'begin'#13#10+
  '  p := ''\\wsl$\Ubuntu\home\me'';'#13#10+
  '  q := ''\\wsl.localhost\Ubuntu\srv'';'#13#10+
  '  r := ''\\tsclient\c\shared'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_AdminShare_StillReported;
// TP-Gegenprobe zu Gate C: im Admin-Share steht der HOSTNAME hardkodiert -
// das '$' allein macht eine UNC-Wurzel nicht OS-fest. Die Denyliste
// praefix-matched auf '\\wsl$\', nicht auf '$'.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''\\buildsrv\c$\logs''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

end.

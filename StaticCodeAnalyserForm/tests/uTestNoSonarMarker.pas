unit uTestNoSonarMarker;

// Tests fuer TNoSonarMarkerDetector (Audit-Marker auf // NOSONAR).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestNoSonarMarker = class
  public
    [Test] procedure NoMarker_NoFinding;
    [Test] procedure SimpleNoSonar_Reported;
    [Test] procedure LowercaseNosonar_Reported;
    [Test] procedure NoSonarInBlockComment_NotReported;
    [Test] procedure NoSonarInStringLiteral_NotReported;
    [Test] procedure MultipleMarkers_AllReported;
    [Test] procedure NoSonarMarker_KindAndSeverity;
    // Posten 264: der Marker wurde als Teilstring geprueft
    [Test] procedure MarkerNameAsIdentifierPart_NotReported;
    [Test] procedure NosonarqubeSubstring_NotReported;
    [Test] procedure MarkerWithColonReason_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 264: der Marker als ganzes Wort -------------------- }
//
// Der Marker wurde als TEILSTRING geprueft. Jeder Bezeichner, der
// 'NoSonar' enthaelt - der Regelname selbst, der Unit-Name, das Kind -
// erfuellte das Praedikat; im eigenen Baum waren das 6 von 20
// Treffern.
//
// Zeilenlokal war das nicht zu bremsen: der Fund sitzt AUF der
// Kommentarzeile, und BuildMarkers ueberspringt Kommentarzeilen bei
// der Target-Suche. Deshalb standen drei 'noinspection-file
// NoSonarMarker' im Repo - die Regel hat sich selbst mundtot gemacht.
//
// Alle Erwartungen an der gebauten Exe gemessen. Der Detektor meldet
// EINEN Fund je Datei, deshalb traegt jede Fixture genau einen Fall.

procedure TTestNoSonarMarker.MarkerNameAsIdentifierPart_NotReported;
// Die eigene Selbstbezichtigung: zwei Erwaehnungen des Regelnamens,
// kein einziger echter Marker. Heute 1 Fund, nach dem Fix 0.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  // noinspection NoSonarMarker'#13#10 +
  '  DoStuff; // siehe uNoSonarMarker.pas'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkNoSonarMarker),
      'der Regelname in einem Kommentar ist kein NOSONAR-Marker');
  finally F.Free; end;
end;

procedure TTestNoSonarMarker.NosonarqubeSubstring_NotReported;
// Dieselbe Klasse von der anderen Seite: 'NOSONARQUBE' beginnt mit
// dem Marker. Heute 1 Fund, nach dem Fix 0.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  DoStuff; // NOSONARQUBE laeuft hier nicht'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkNoSonarMarker),
      'NOSONARQUBE ist ein anderes Wort');
  finally F.Free; end;
end;

procedure TTestNoSonarMarker.MarkerWithColonReason_StillReported;
// GEGENPROBE gegen Ueberstraffung: ein echter Marker mit
// Doppelpunkt-Begruendung. Vor wie nach dem Fix 1 Fund - der
// Doppelpunkt ist keine Wortgrenzenverletzung.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  DoStuff; // NOSONAR: id stammt aus einem Enum'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkNoSonarMarker),
      'ein echter Marker bleibt ein Fund');
  finally F.Free; end;
end;


procedure TTestNoSonarMarker.NoMarker_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNoSonarMarker));
  finally F.Free; end;
end;

procedure TTestNoSonarMarker.SimpleNoSonar_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Dispose(P); // NOSONAR - legacy code path'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkNoSonarMarker));
  finally F.Free; end;
end;

procedure TTestNoSonarMarker.LowercaseNosonar_Reported;
// Marker ist case-insensitive: nosonar / NoSonar / NOSONAR -> 1 Treffer
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  DoStuff; // nosonar'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkNoSonarMarker));
  finally F.Free; end;
end;

procedure TTestNoSonarMarker.NoSonarInBlockComment_NotReported;
// Marker zaehlen nur in //-Kommentaren, nicht in {..} oder (*..*).
// Konvention konsistent zu SonarDelphi: NOSONAR ist ein End-of-Line-Marker.
const SRC =
  'unit t; implementation'#13#10 +
  '{ NOSONAR - some block-comment text }'#13#10 +
  '(* NOSONAR in paren-star *)'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNoSonarMarker));
  finally F.Free; end;
end;

procedure TTestNoSonarMarker.NoSonarInStringLiteral_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  WriteLn(''// NOSONAR is a marker'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNoSonarMarker));
  finally F.Free; end;
end;

procedure TTestNoSonarMarker.MultipleMarkers_AllReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure A; begin DoA; end; // NOSONAR'#13#10 +
  'procedure B; begin DoB; end; // NOSONAR'#13#10 +
  'procedure C; begin DoC; end; // clean comment'#13#10 +
  'procedure D; begin DoD; end; // NOSONAR'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(3, TFindingHelper.Count(F, fkNoSonarMarker));
  finally F.Free; end;
end;

procedure TTestNoSonarMarker.NoSonarMarker_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; begin DoStuff; end; // NOSONAR'#13#10;
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkNoSonarMarker then
      begin
        Assert.AreEqual<TFindingKind>(fkNoSonarMarker, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,         Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkNoSonarMarker finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNoSonarMarker);

end.

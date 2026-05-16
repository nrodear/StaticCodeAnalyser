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
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestNoSonarMarker.NoMarker_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkNoSonarMarker));
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
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkNoSonarMarker));
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
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkNoSonarMarker));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkNoSonarMarker));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkNoSonarMarker));
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
  try Assert.AreEqual(3, TFindingHelper.Count(F, fkNoSonarMarker));
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

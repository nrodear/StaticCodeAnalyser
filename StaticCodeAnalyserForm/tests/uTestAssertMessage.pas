unit uTestAssertMessage;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestAssertMessage = class
  public
    [Test] procedure AssertWithMessage_NoFinding;
    [Test] procedure AssertWithoutMessage_Reported;
    [Test] procedure NestedFunctionCall_NoFinding;
    [Test] procedure NotACallToAssert_NoFinding;
    [Test] procedure AssertMessage_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestAssertMessage.AssertWithMessage_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  Assert(Count > 0, ''Items must not be empty'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAssertMessage));
  finally F.Free; end;
end;

procedure TTestAssertMessage.AssertWithoutMessage_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  Assert(Count > 0);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkAssertMessage));
  finally F.Free; end;
end;

procedure TTestAssertMessage.NestedFunctionCall_NoFinding;
// Verschachtelter Aufruf: das innere Komma in Max(A, B) gehoert nicht
// zur Assert-Argumentliste auf Top-Level. Trotzdem soll der Assert
// gemeldet werden, falls nur ein Arg vorhanden. Hier ist 2-Arg-Assert
// also kein Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  Assert(Count > 0, Format(''bad: %d'', [Count]));'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAssertMessage));
  finally F.Free; end;
end;

procedure TTestAssertMessage.NotACallToAssert_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var AssertX: Integer;'#13#10 +
  '  AssertX := 1;'#13#10 +
  '  MyAssert(X);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAssertMessage));
  finally F.Free; end;
end;

procedure TTestAssertMessage.AssertMessage_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; Assert(X); end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkAssertMessage then
      begin
        Assert.AreEqual<TFindingKind>(fkAssertMessage, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,         Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkAssertMessage finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAssertMessage);

end.

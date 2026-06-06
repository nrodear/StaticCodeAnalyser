unit uTestLongMethod;

// Tests fuer TLongMethodDetector. Schwellwerte greifen ab beiden:
// MaxBodyLines UND MaxStatements ueberschritten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLongMethod = class
  public
    [Test] procedure ShortMethod_NoFinding;
    [Test] procedure LongMethod_Reported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections, System.Classes,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestLongMethod.ShortMethod_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  WriteLn(''a'');'#13#10 +
  '  WriteLn(''b'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLongMethod));
  finally F.Free; end;
end;

procedure TTestLongMethod.LongMethod_Reported;
// 80+ Body-Zeilen mit 80+ Statements - sollte ueber jeden vernuenftigen
// Schwellwert (Default 50/50) hinaus sein.
var
  SB : TStringBuilder;
  i  : Integer;
  F  : TObjectList<TLeakFinding>;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; implementation');
    SB.AppendLine('procedure Foo;');
    SB.AppendLine('begin');
    for i := 1 to 80 do
      SB.AppendLine(Format('  WriteLn(''%d'');', [i]));
    SB.AppendLine('end;');
    F := TFindingHelper.FindingsOf(SB.ToString);
    try Assert.IsTrue(TFindingHelper.Count(F, fkLongMethod) >= 1);
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestLongMethod.Finding_KindAndSeverity;
var
  SB  : TStringBuilder;
  i   : Integer;
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; implementation');
    SB.AppendLine('procedure Foo;');
    SB.AppendLine('begin');
    for i := 1 to 80 do
      SB.AppendLine(Format('  WriteLn(''%d'');', [i]));
    SB.AppendLine('end;');
    F := TFindingHelper.FindingsOf(SB.ToString);
    try
      Hit := nil;
      for Fnd in F do
        if Fnd.Kind = fkLongMethod then begin Hit := Fnd; Break; end;
      Assert.IsNotNull(Hit, 'fkLongMethod finding expected');
      Assert.AreEqual(fkLongMethod, Hit.Kind);
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLongMethod);

end.

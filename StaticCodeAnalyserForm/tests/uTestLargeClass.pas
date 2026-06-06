unit uTestLargeClass;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLargeClass = class
  public
    [Test] procedure LargeClass_Reported;
    [Test] procedure SmallClass_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestLargeClass.LargeClass_Reported;
// Erzeuge eine Klasse + Implementation die ueber 500 Zeilen spannt.
var
  SB : TStringBuilder;
  i  : Integer;
  F  : TObjectList<TLeakFinding>;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t;');
    SB.AppendLine('interface');
    SB.AppendLine('type');
    SB.AppendLine('  TBig = class');
    SB.AppendLine('    procedure A;');
    SB.AppendLine('    procedure B;');
    SB.AppendLine('  end;');
    SB.AppendLine('implementation');
    SB.AppendLine('procedure TBig.A;');
    SB.AppendLine('begin');
    // 600 Zeilen Body in A.
    for i := 1 to 600 do
      SB.AppendLine(Format('  WriteLn(''%d'');', [i]));
    SB.AppendLine('end;');
    SB.AppendLine('procedure TBig.B;');
    SB.AppendLine('begin WriteLn(''b''); end;');
    SB.AppendLine('end.');
    F := TFindingHelper.FindingsOf(SB.ToString);
    try Assert.IsTrue(TFindingHelper.Count(F, fkLargeClass) >= 1);
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestLargeClass.SmallClass_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    procedure Bar;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Bar; begin WriteLn(''x''); end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLargeClass));
  finally F.Free; end;
end;

procedure TTestLargeClass.Finding_KindAndSeverity;
var
  SB  : TStringBuilder;
  i   : Integer;
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t;');
    SB.AppendLine('interface');
    SB.AppendLine('type TBig = class procedure A; end;');
    SB.AppendLine('implementation');
    SB.AppendLine('procedure TBig.A;');
    SB.AppendLine('begin');
    for i := 1 to 600 do
      SB.AppendLine(Format('  WriteLn(''%d'');', [i]));
    SB.AppendLine('end;');
    SB.AppendLine('end.');
    F := TFindingHelper.FindingsOf(SB.ToString);
    try
      Hit := nil;
      for Fnd in F do
        if Fnd.Kind = fkLargeClass then begin Hit := Fnd; Break; end;
      Assert.IsNotNull(Hit, 'fkLargeClass finding expected');
      Assert.AreEqual(lsWarning, Hit.Severity);
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLargeClass);

end.

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
    // Real-World FP-Audit 2026-07-10 Regression (span-overcounts-sibling-classes)
    [Test] procedure SmallSiblingOfBigClass_OnlyBigReported;
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

procedure TTestLargeClass.SmallSiblingOfBigClass_OnlyBigReported;
// Real-World FP-Audit 2026-07-10 (span-overcounts-sibling-classes): eine winzige
// Klasse, die sich eine Unit mit einer grossen teilt, bekam faelschlich die Span
// der ganzen Unit - der Parser haengt nachfolgende Geschwister-Decls als
// Descendants an die erste Klasse, und die alte max-min-Span zaehlte zusaetzlich
// die erst weit hinten implementierte Einzelmethode voll. Nach dem Summen-Fix
// (Deklarations-Span gedeckelt an der naechsten Klasse + Summe der Methoden-Body-
// Spans) wird NUR die grosse Klasse gemeldet.
var
  SB       : TStringBuilder;
  i        : Integer;
  F        : TObjectList<TLeakFinding>;
  Fnd, Hit : TLeakFinding;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; interface');
    SB.AppendLine('type');
    SB.AppendLine('  TSmall = class');   // winzig: 1 Methode, ~3 eigene Zeilen
    SB.AppendLine('    procedure A;');
    SB.AppendLine('  end;');
    SB.AppendLine('  TBig = class');      // gross: 550 Felder-Deklaration
    for i := 1 to 550 do
      SB.AppendLine(Format('    F%d: Integer;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation');
    // TSmall.A wird erst NACH den 550 Feldern implementiert (Zeile ~558) -
    // exakt der Fall den die alte max-min-Span als "557 Zeilen" fehlzaehlte.
    SB.AppendLine('procedure TSmall.A; begin end;');
    SB.AppendLine('end.');
    F := TFindingHelper.FindingsOf(SB.ToString);
    try
      Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkLargeClass),
        'nur die grosse Klasse TBig, nicht die winzige Geschwister-Klasse TSmall');
      Hit := nil;
      for Fnd in F do
        if Fnd.Kind = fkLargeClass then begin Hit := Fnd; Break; end;
      Assert.AreEqual('TBig', Hit.MethodName,
        'gemeldete Klasse muss TBig sein (TSmall ist der span-slurp-FP)');
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLargeClass);

end.

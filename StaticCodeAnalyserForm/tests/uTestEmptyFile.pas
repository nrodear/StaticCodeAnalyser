unit uTestEmptyFile;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEmptyFile = class
  public
    [Test] procedure FileWithDecl_NoFinding;
    [Test] procedure EmptyUnit_Reported;
    [Test] procedure JustConst_NoFinding;
    [Test] procedure EmptyFile_KindAndSeverity;
    // Voll-Review 2026-09-12 (Major 60): Arbeit leistende Units
    [Test] procedure InitializationOnlyUnit_NoFinding;
    [Test] procedure IncludeOnlyUnit_NoFinding;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestEmptyFile.FileWithDecl_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'procedure Foo;'#13#10 +
  'implementation'#13#10 +
  'procedure Foo; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyFile));
  finally F.Free; end;
end;

procedure TTestEmptyFile.EmptyUnit_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyFile));
  finally F.Free; end;
end;

procedure TTestEmptyFile.JustConst_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'const X = 1;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyFile));
  finally F.Free; end;
end;

procedure TTestEmptyFile.EmptyFile_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkEmptyFile then
      begin
        Assert.AreEqual<TFindingKind>(fkEmptyFile, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,     Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkEmptyFile finding');
  finally F.Free; end;
end;

procedure TTestEmptyFile.InitializationOnlyUnit_NoFinding;
// Voll-Review 2026-09-12 (Major 60): eine Registrierungs-Unit, deren
// ganzer Zweck der initialization-Seiteneffekt ist, galt als 'leer' -
// der Loeschempfehlung zu folgen braeche das Programm (Bestands-Exe:
// 1 FP, empirisch belegt, ef1.pas).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'initialization'#13#10 +
  '  RegisterFoo;'#13#10 +
  'finalization'#13#10 +
  '  UnregisterFoo;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyFile),
    'initialization-Arbeit ist Inhalt - keine Loeschempfehlung');
  finally F.Free; end;
end;

procedure TTestEmptyFile.IncludeOnlyUnit_NoFinding;
// Zweite Form: Deklarationen kommen aus einem {$I}-Include - die
// '{'-Zeile wurde vorher wie eine Leerzeile uebersprungen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  '{$I decls.inc}'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyFile),
    'include-basierte Deklarationen sind Inhalt');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEmptyFile);

end.

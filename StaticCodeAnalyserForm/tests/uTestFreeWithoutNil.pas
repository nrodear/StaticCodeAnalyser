unit uTestFreeWithoutNil;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFreeWithoutNil = class
  public
    [Test] procedure FreeWithoutNil_Reported;
    [Test] procedure FreeAndNil_NotReported;
    [Test] procedure FreeAtMethodEnd_NotReported;
    [Test] procedure FreeFollowedByNilAssign_NotReported;
    [Test] procedure FreeInDestructor_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestFreeWithoutNil.FreeWithoutNil_Reported;
// HINWEIS: Detector flaggt seit Round-5-Fix nur FELDER, nicht Locals
// (Locals fallen beim Method-End aus dem Scope, kein Dangling-Risiko).
// Daher SRC mit FFoo-Feld statt 'var L: TStringList;'.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FList: TStringList;'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.DoStuff;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  WriteLn(''after free'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkFreeWithoutNil) >= 1);
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeAndNil_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  FreeAndNil(L);'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeAtMethodEnd_NotReported;
// Free als letzte Anweisung -> kein Folge-Use moeglich -> kein Befund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeFollowedByNilAssign_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Free;'#13#10 +
  '  L := nil;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.Finding_KindAndSeverity;
// Field-Pattern - analog zu FreeWithoutNil_Reported (Round-5-Fix).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FList: TStringList;'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.DoStuff;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkFreeWithoutNil then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkFreeWithoutNil finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeInDestructor_NotReported;
// FP-Fix (Real-World 2026-06-21): im Destruktor ist Nil-Out nach Free
// sinnlos - das Objekt selbst wird zerstoert. Ein Destruktor mit mehreren
// Field.Free erzeugte sonst je ein Finding.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FA, FB: TObject;'#13#10 +
  '  public'#13#10 +
  '    destructor Destroy; override;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FA.Free;'#13#10 +
  '  FB.Free;'#13#10 +
  '  inherited;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
      'Field.Free im Destruktor braucht kein Nil-Out - kein Finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFreeWithoutNil);

end.

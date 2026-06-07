unit uTestAbstractNotImpl;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestAbstractNotImpl = class
  public
    [Test] procedure AbstractInBase_NotOverriddenInDerived_Reported;
    [Test] procedure AbstractInBase_OverriddenInDerived_NoFinding;
    [Test] procedure NoBaseInUnit_NoFinding;
    [Test] procedure DerivedItselfAbstract_NoFinding;
    [Test] procedure AnonymousRecordField_DoesNotConfuseParser;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestAbstractNotImpl.AbstractInBase_NotOverriddenInDerived_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure DoWork; virtual; abstract;'#13#10 +
  '  end;'#13#10 +
  '  TDerived = class(TBase)'#13#10 +
  '    procedure SomethingElse;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkAbstractNotImpl) >= 1);
  finally F.Free; end;
end;

procedure TTestAbstractNotImpl.AbstractInBase_OverriddenInDerived_NoFinding;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure DoWork; virtual; abstract;'#13#10 +
  '  end;'#13#10 +
  '  TDerived = class(TBase)'#13#10 +
  '    procedure DoWork; override;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAbstractNotImpl));
  finally F.Free; end;
end;

procedure TTestAbstractNotImpl.NoBaseInUnit_NoFinding;
// Cross-Unit-Base: TForm o.ae., der Detector kann nichts wissen -> kein Finding.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TMyForm = class(TForm)'#13#10 +
  '    procedure Foo;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAbstractNotImpl));
  finally F.Free; end;
end;

procedure TTestAbstractNotImpl.DerivedItselfAbstract_NoFinding;
// Wenn die abgeleitete Klasse selbst abstract ist (`class abstract`), darf
// sie offene abstrakte Methoden weiterreichen.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure DoWork; virtual; abstract;'#13#10 +
  '  end;'#13#10 +
  '  TStillAbstract = class abstract(TBase)'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAbstractNotImpl));
  finally F.Free; end;
end;

procedure TTestAbstractNotImpl.AnonymousRecordField_DoesNotConfuseParser;
// Regression mORMot.core.mustache TSynMustacheContextVariant (8 FPs):
// Class hat 'fContext: array of record ... end;' als Feld. Ohne
// Record-Depth-Tracking sieht der Parser das innere 'end' als
// Class-End - alle override-Methoden danach werden ausserhalb der
// Klasse abgelegt -> alle abstract-Methoden der Base scheinen
// nicht ueberschrieben.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure DoWork; virtual; abstract;'#13#10 +
  '  end;'#13#10 +
  '  TDerived = class(TBase)'#13#10 +
  '  protected'#13#10 +
  '    fStuff: array of record'#13#10 +
  '      A: Integer;'#13#10 +
  '      B: string;'#13#10 +
  '    end;'#13#10 +
  '    procedure DoWork; override;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAbstractNotImpl),
    'anonymes record als Feld darf override-Methode nicht aushebeln');
  finally F.Free; end;
end;

procedure TTestAbstractNotImpl.Finding_KindAndSeverity;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure DoWork; virtual; abstract;'#13#10 +
  '  end;'#13#10 +
  '  TDerived = class(TBase)'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkAbstractNotImpl then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkAbstractNotImpl finding expected');
    Assert.AreEqual(fkAbstractNotImpl, Hit.Kind);
    Assert.AreEqual(lsError,           Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAbstractNotImpl);

end.

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
    [Test] procedure DerivedIntroducesAbstractMethod_NoFinding;
    [Test] procedure AnonymousRecordField_DoesNotConfuseParser;
    [Test] procedure TCustomBase_TreatedAsAbstract_NoFinding;
    [Test] procedure IntermediateBase_LeafOverrides_NoFinding;
    [Test] procedure Finding_KindAndSeverity;
    // --- Voll-Review 2026-09-12 (Blocker): Interface in der Elternliste ---
    [Test] procedure InterfaceInParentList_AbstractMissing_Reported;
    // Voll-Review 2026-09-12 (Testluecke 118): die Threshold-Heuristik
    [Test] procedure ParentWithThreeAbstract_NoOverride_Skipped;
    [Test] procedure ParentWithOneAbstract_NoOverride_Reported;
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

procedure TTestAbstractNotImpl.DerivedIntroducesAbstractMethod_NoFinding;
// FP-Fix (Real-World 2026-06-28): die Subklasse ueberschreibt die Base-Abstract-
// Methode nicht, fuehrt aber SELBST eine neue 'virtual; abstract'-Methode ein
// -> sie ist damit ebenfalls abstrakt (Zwischen-Basis), die konkreten Blatt-
// Subklassen liefern die Overrides. Kein EAbstractError-Befund.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure DoWork; virtual; abstract;'#13#10 +
  '  end;'#13#10 +
  '  TMid = class(TBase)'#13#10 +
  '    procedure DoOther; virtual; abstract;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAbstractNotImpl),
    'Subklasse mit eigener abstract-Methode ist selbst abstrakt - kein Finding');
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

procedure TTestAbstractNotImpl.TCustomBase_TreatedAsAbstract_NoFinding;
// Regression Img32.Draw TCustomColorRenderer (~20 FPs):
// VCL-Konvention - Klassen mit Prefix TCustom*/TAbstract* sind
// Zwischen-Abstract-Basen die Override an Subklassen weiterreichen.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure DoIt; virtual; abstract;'#13#10 +
  '  end;'#13#10 +
  '  TCustomMiddle = class(TBase)'#13#10 +
  '    procedure SetSomething(v: Integer); virtual;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAbstractNotImpl),
    'TCustom-Prefix-Klasse als implicit-abstract werten');
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

procedure TTestAbstractNotImpl.IntermediateBase_LeafOverrides_NoFinding;
// FP-Fix (Real-World 2026-06-23): TMid erbt Exec, ueberschreibt NICHT - ist
// aber selbst Basis von TLeaf, das ueberschreibt. TMid ist eine Zwischen-
// Basis (nie instanziiert) -> kein EAbstractError. Nur Blatt-Klassen flaggen.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure Exec; virtual; abstract;'#13#10 +
  '  end;'#13#10 +
  '  TMid = class(TBase)'#13#10 +
  '  end;'#13#10 +
  '  TLeaf = class(TMid)'#13#10 +
  '    procedure Exec; override;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAbstractNotImpl),
    'Intermediate-Basis (selbst Parent) nicht flaggen - Blatt liefert Override');
  finally F.Free; end;
end;

procedure TTestAbstractNotImpl.InterfaceInParentList_AbstractMissing_Reported;
// Voll-Review 2026-09-12 (Blocker, Zwilling des uMissingOverride-Fixes):
// die byte-gleiche ExtractParentName-Kopie splittete am Komma, der
// Parser trennt aber mit BLANK ('TBase IThing') - der Parent-Lookup
// lief leer und die fehlende abstract-Implementierung einer Subklasse
// mit Interface in der Elternliste blieb ungemeldet (Bestands-Exe: 0,
// empirisch geprueft).
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  IThing = interface'#13#10 +
  '    procedure Ping;'#13#10 +
  '  end;'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure DoWork; virtual; abstract;'#13#10 +
  '  end;'#13#10 +
  '  TDerived = class(TBase, IThing)'#13#10 +
  '    procedure Ping;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkAbstractNotImpl),
    'class(TBase, IThing) ohne DoWork-Override: EAbstractError-Risiko ' +
    'muss gemeldet werden - Basisklasse ist der erste Eltern-Ident');
  finally F.Free; end;
end;

procedure TTestAbstractNotImpl.ParentWithThreeAbstract_NoOverride_Skipped;
// Testluecke 118 (Voll-Review 2026-09-12): 'OverrideCount = 0 UND
// Parent hat >= 3 abstract-Methoden -> Intermediate-Abstract, Skip'
// war ungetestet. Die Schwelle 3 ist kein Zufallswert: sie wurde am
// 2026-06-13 gewaehlt, damit sie nicht mit dem Fall '1 abstract + 0
// overrides -> Finding' kollidiert. Beide Seiten gehoeren gepinnt,
// sonst kann die Zahl unbemerkt wandern.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TParent3 = class'#13#10 +
  '    procedure A; virtual; abstract;'#13#10 +
  '    procedure B; virtual; abstract;'#13#10 +
  '    procedure C; virtual; abstract;'#13#10 +
  '  end;'#13#10 +
  '  TChild3 = class(TParent3)'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAbstractNotImpl),
    'ab drei abstract-Methoden ohne ein einziges Override gilt die '
    + 'Ableitung als Intermediate-Abstract');
  finally F.Free; end;
end;

procedure TTestAbstractNotImpl.ParentWithOneAbstract_NoOverride_Reported;
// Die Gegenseite derselben Schwelle: EINE abstract-Methode ohne
// Override bleibt ein Fund (EAbstractError beim Aufruf).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TParent1 = class'#13#10 +
  '    procedure A; virtual; abstract;'#13#10 +
  '  end;'#13#10 +
  '  TChild1 = class(TParent1)'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkAbstractNotImpl) >= 1,
    'eine nicht ueberschriebene abstract-Methode bleibt ein Fund');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAbstractNotImpl);

end.

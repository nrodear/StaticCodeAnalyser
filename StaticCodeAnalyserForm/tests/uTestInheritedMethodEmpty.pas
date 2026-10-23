unit uTestInheritedMethodEmpty;

// Tests fuer den TInheritedMethodEmptyDetector (SCA125).
//
// Q14 (2026-10-23): die frueheren Tests nutzten die UNGUELTIGE Form
// 'procedure TFoo.Bar; override; begin inherited; end;' - der
// Implementierungskopf wiederholt 'override' in Delphi nie. Sie prueften
// damit die Selbstkonsistenz des Detektors, der im echten Code 0 Funde
// lieferte. Jetzt steht 'override' wie im Compiler an der Deklaration in
// der Klasse. Der Detektor liest Attribute und Direktiven aus dem
// Quelltext -> FindingsOfFile (im In-Memory-Harness ist die Datei nicht
// lesbar und er meldet bewusst nichts).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestInheritedMethodEmpty = class
  public
    // ---- Funde ---------------------------------------------------------
    [Test] procedure BareInherited_ProtectedOverride_Reported;
    [Test] procedure DestructorSameName_Reported;
    [Test] procedure ExactPassThrough_Reported;
    [Test] procedure ExactPassThroughConstParam_Reported;
    [Test] procedure FunctionResultAssign_Reported;
    [Test] procedure ImplHeaderWithoutParams_Reported;
    [Test] procedure PublicWithoutAncestor_LowConfidence;
    [Test] procedure AncestorInUnitSameVisibility_HighConfidence;
    // ---- Gegenproben: kein Fund ----------------------------------------
    [Test] procedure AncestorInUnitWidensVisibility_NoFinding;
    [Test] procedure DeclarationWithoutOverride_NoFinding;
    [Test] procedure TransformedArgs_NoFinding;
    [Test] procedure InheritedPlusOtherStatement_NoFinding;
    [Test] procedure InheritedOtherName_NoFinding;
    [Test] procedure FunctionWithoutResultAssign_NoFinding;
    [Test] procedure AttributeOnDeclaration_NoFinding;
    [Test] procedure FinalDirective_NoFinding;
    [Test] procedure DefaultParameter_NoFinding;
    [Test] procedure OverloadedDeclaration_NoFinding;
    [Test] procedure DirectiveInBody_NoFinding;
    [Test] procedure NamedWithoutArgsButParams_NoFinding;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

const
  CRLF = #13#10;
  KOPF = 'unit t;' + CRLF + 'interface' + CRLF + 'type' + CRLF;

function Treffer(const Src: string): Integer;
var
  F : TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(Src);
  try
    Result := TFindingHelper.Count(F, fkInheritedMethodEmpty);
  finally
    F.Free;
  end;
end;

function Konfidenz(const Src: string): TFindingConfidence;
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(Src);
  try
    Hit := TFindingHelper.FirstOf(F, fkInheritedMethodEmpty);
    Assert.IsNotNull(Hit, 'SCA125-Fund erwartet');
    Result := Hit.Confidence;
  finally
    F.Free;
  end;
end;

procedure TTestInheritedMethodEmpty.BareInherited_ProtectedOverride_Reported;
const SRC = KOPF +
  '  TFoo = class(TControl)' + CRLF +
  '  protected' + CRLF +
  '    procedure Paint; override;' + CRLF +
  '  end;' + CRLF +
  'implementation' + CRLF +
  'procedure TFoo.Paint;' + CRLF +
  'begin' + CRLF +
  '  inherited;' + CRLF +
  'end;' + CRLF +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInheritedMethodEmpty));
    Hit := TFindingHelper.FirstOf(F, fkInheritedMethodEmpty);
    Assert.AreEqual<TLeakSeverity>(lsHint, Hit.Severity);
    Assert.AreEqual<TFindingConfidence>(fcHigh, Hit.Confidence);
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'procedure TFoo.Paint;'),
      Hit.LineNumber, 'Fund am Implementierungskopf');
  finally
    F.Free;
  end;
end;

procedure TTestInheritedMethodEmpty.DestructorSameName_Reported;
// public, Vorfahr nicht in der Unit - Destroy ist in TObject public.
const SRC = KOPF +
  '  TFoo = class(TObject)' + CRLF +
  '  public' + CRLF +
  '    destructor Destroy; override;' + CRLF +
  '  end;' + CRLF +
  'implementation' + CRLF +
  'destructor TFoo.Destroy;' + CRLF +
  'begin' + CRLF +
  '  inherited Destroy;' + CRLF +
  'end;' + CRLF +
  'end.';
begin
  Assert.AreEqual<TFindingConfidence>(fcHigh, Konfidenz(SRC));
end;

procedure TTestInheritedMethodEmpty.ExactPassThrough_Reported;
const SRC = KOPF +
  '  TFoo = class(TControl)' + CRLF +
  '  protected' + CRLF +
  '    procedure MoveBy(ALeft, ATop: Integer); override;' + CRLF +
  '  end;' + CRLF +
  'implementation' + CRLF +
  'procedure TFoo.MoveBy(ALeft, ATop: Integer);' + CRLF +
  'begin' + CRLF +
  '  inherited MoveBy(ALeft, ATop);' + CRLF +
  'end;' + CRLF +
  'end.';
begin
  Assert.AreEqual<Integer>(1, Treffer(SRC), '1:1-Durchreichung ist ein reiner Bypass');
end;

procedure TTestInheritedMethodEmpty.ExactPassThroughConstParam_Reported;
// nkParam.Name traegt den Modifier ('const S') - der Vergleich streift ihn ab.
const SRC = KOPF +
  '  TFoo = class(TControl)' + CRLF +
  '  protected' + CRLF +
  '    procedure SetTitle(const S: string); override;' + CRLF +
  '  end;' + CRLF +
  'implementation' + CRLF +
  'procedure TFoo.SetTitle(const S: string);' + CRLF +
  'begin' + CRLF +
  '  inherited SetTitle(S);' + CRLF +
  'end;' + CRLF +
  'end.';
begin
  Assert.AreEqual<Integer>(1, Treffer(SRC));
end;

procedure TTestInheritedMethodEmpty.FunctionResultAssign_Reported;
const SRC = KOPF +
  '  TFoo = class(TStrings)' + CRLF +
  '  protected' + CRLF +
  '    function Get(Index: Integer): string; override;' + CRLF +
  '  end;' + CRLF +
  'implementation' + CRLF +
  'function TFoo.Get(Index: Integer): string;' + CRLF +
  'begin' + CRLF +
  '  Result := inherited Get(Index);' + CRLF +
  'end;' + CRLF +
  'end.';
begin
  Assert.AreEqual<Integer>(1, Treffer(SRC));
end;

procedure TTestInheritedMethodEmpty.ImplHeaderWithoutParams_Reported;
// Delphi erlaubt den Kopf ohne Parameterliste - dann gelten die
// Parameter der Deklaration.
const SRC = KOPF +
  '  TFoo = class(TControl)' + CRLF +
  '  protected' + CRLF +
  '    procedure Resize(AWidth: Integer); override;' + CRLF +
  '  end;' + CRLF +
  'implementation' + CRLF +
  'procedure TFoo.Resize;' + CRLF +
  'begin' + CRLF +
  '  inherited Resize(AWidth);' + CRLF +
  'end;' + CRLF +
  'end.';
begin
  Assert.AreEqual<Integer>(1, Treffer(SRC));
end;

procedure TTestInheritedMethodEmpty.PublicWithoutAncestor_LowConfidence;
// public, Vorfahr nicht in der Unit, kein bekannter public-Name: das
// Override koennte protected nach public anheben (TButton.Click) -> fcLow.
const SRC = KOPF +
  '  TFoo = class(TControl)' + CRLF +
  '  public' + CRLF +
  '    procedure Click; override;' + CRLF +
  '  end;' + CRLF +
  'implementation' + CRLF +
  'procedure TFoo.Click;' + CRLF +
  'begin' + CRLF +
  '  inherited;' + CRLF +
  'end;' + CRLF +
  'end.';
begin
  Assert.AreEqual<TFindingConfidence>(fcLow, Konfidenz(SRC));
end;

procedure TTestInheritedMethodEmpty.AncestorInUnitSameVisibility_HighConfidence;
// Gegenstueck zu PublicWithoutAncestor: derselbe public-Fall, aber der
// Vorfahr steht in der Unit und ist ebenfalls public -> belegt, fcHigh.
const SRC = KOPF +
  '  TBase = class' + CRLF +
  '  public' + CRLF +
  '    procedure Click; virtual;' + CRLF +
  '  end;' + CRLF +
  '  TFoo = class(TBase)' + CRLF +
  '  public' + CRLF +
  '    procedure Click; override;' + CRLF +
  '  end;' + CRLF +
  'implementation' + CRLF +
  'procedure TBase.Click;' + CRLF +
  'begin' + CRLF +
  '  Beep;' + CRLF +
  'end;' + CRLF +
  'procedure TFoo.Click;' + CRLF +
  'begin' + CRLF +
  '  inherited;' + CRLF +
  'end;' + CRLF +
  'end.';
begin
  Assert.AreEqual<TFindingConfidence>(fcHigh, Konfidenz(SRC));
end;

procedure TTestInheritedMethodEmpty.AncestorInUnitWidensVisibility_NoFinding;
// Der Vorfahr ist protected, das Override public: es HEBT die
// Sichtbarkeit an. Loeschen braeche Aufrufer (E2361) - kein Leerlauf.
const SRC = KOPF +
  '  TBase = class' + CRLF +
  '  protected' + CRLF +
  '    procedure Click; virtual;' + CRLF +
  '  end;' + CRLF +
  '  TFoo = class(TBase)' + CRLF +
  '  public' + CRLF +
  '    procedure Click; override;' + CRLF +
  '  end;' + CRLF +
  'implementation' + CRLF +
  'procedure TBase.Click;' + CRLF +
  'begin' + CRLF +
  '  Beep;' + CRLF +
  'end;' + CRLF +
  'procedure TFoo.Click;' + CRLF +
  'begin' + CRLF +
  '  inherited;' + CRLF +
  'end;' + CRLF +
  'end.';
begin
  Assert.AreEqual<Integer>(0, Treffer(SRC));
end;

procedure TTestInheritedMethodEmpty.DeclarationWithoutOverride_NoFinding;
const SRC = KOPF +
  '  TFoo = class(TControl)' + CRLF +
  '  protected' + CRLF +
  '    procedure Paint; virtual;' + CRLF +
  '  end;' + CRLF +
  'implementation' + CRLF +
  'procedure TFoo.Paint;' + CRLF +
  'begin' + CRLF +
  '  inherited;' + CRLF +
  'end;' + CRLF +
  'end.';
begin
  Assert.AreEqual<Integer>(0, Treffer(SRC));
end;

procedure TTestInheritedMethodEmpty.TransformedArgs_NoFinding;
// Voll-Review 2026-09-12 (Major 71): 'inherited Create(nil)' reparentet -
// kein Bypass.
const SRC = KOPF +
  '  TFoo = class(TComponent)' + CRLF +
  '  public' + CRLF +
  '    constructor Create(AOwner: TComponent); override;' + CRLF +
  '  end;' + CRLF +
  'implementation' + CRLF +
  'constructor TFoo.Create(AOwner: TComponent);' + CRLF +
  'begin' + CRLF +
  '  inherited Create(nil);' + CRLF +
  'end;' + CRLF +
  'end.';
begin
  Assert.AreEqual<Integer>(0, Treffer(SRC));
end;

procedure TTestInheritedMethodEmpty.InheritedPlusOtherStatement_NoFinding;
const SRC = KOPF +
  '  TFoo = class(TControl)' + CRLF +
  '  protected' + CRLF +
  '    procedure Paint; override;' + CRLF +
  '  end;' + CRLF +
  'implementation' + CRLF +
  'procedure TFoo.Paint;' + CRLF +
  'begin' + CRLF +
  '  inherited;' + CRLF +
  '  DrawFrame;' + CRLF +
  'end;' + CRLF +
  'end.';
begin
  Assert.AreEqual<Integer>(0, Treffer(SRC));
end;

procedure TTestInheritedMethodEmpty.InheritedOtherName_NoFinding;
const SRC = KOPF +
  '  TFoo = class(TControl)' + CRLF +
  '  protected' + CRLF +
  '    procedure Paint; override;' + CRLF +
  '  end;' + CRLF +
  'implementation' + CRLF +
  'procedure TFoo.Paint;' + CRLF +
  'begin' + CRLF +
  '  inherited Repaint;' + CRLF +
  'end;' + CRLF +
  'end.';
begin
  Assert.AreEqual<Integer>(0, Treffer(SRC));
end;

procedure TTestInheritedMethodEmpty.FunctionWithoutResultAssign_NoFinding;
// Der Aufruf ohne Zuweisung verwirft das Ergebnis des Vorfahren.
const SRC = KOPF +
  '  TFoo = class(TStrings)' + CRLF +
  '  protected' + CRLF +
  '    function GetCount: Integer; override;' + CRLF +
  '  end;' + CRLF +
  'implementation' + CRLF +
  'function TFoo.GetCount: Integer;' + CRLF +
  'begin' + CRLF +
  '  inherited GetCount;' + CRLF +
  'end;' + CRLF +
  'end.';
begin
  Assert.AreEqual<Integer>(0, Treffer(SRC));
end;

procedure TTestInheritedMethodEmpty.AttributeOnDeclaration_NoFinding;
// DMVC-Muster: das Override traegt ein Routen-Attribut - es ist nicht leer.
const SRC = KOPF +
  '  TFoo = class(TBaseController)' + CRLF +
  '  protected' + CRLF +
  '    [MVCPath(''/people'')]' + CRLF +
  '    procedure GetPeople; override;' + CRLF +
  '  end;' + CRLF +
  'implementation' + CRLF +
  'procedure TFoo.GetPeople;' + CRLF +
  'begin' + CRLF +
  '  inherited;' + CRLF +
  'end;' + CRLF +
  'end.';
begin
  Assert.AreEqual<Integer>(0, Treffer(SRC));
end;

procedure TTestInheritedMethodEmpty.FinalDirective_NoFinding;
// 'final' versiegelt die Methode - das Loeschen hebt die Sperre auf.
const SRC = KOPF +
  '  TFoo = class(TControl)' + CRLF +
  '  protected' + CRLF +
  '    procedure Paint; override; final;' + CRLF +
  '  end;' + CRLF +
  'implementation' + CRLF +
  'procedure TFoo.Paint;' + CRLF +
  'begin' + CRLF +
  '  inherited;' + CRLF +
  'end;' + CRLF +
  'end.';
begin
  Assert.AreEqual<Integer>(0, Treffer(SRC));
end;

procedure TTestInheritedMethodEmpty.DefaultParameter_NoFinding;
// Ein Default am Override kann vom Vorfahren abweichen.
const SRC = KOPF +
  '  TFoo = class(TControl)' + CRLF +
  '  protected' + CRLF +
  '    procedure Scroll(Delta: Integer = 1); override;' + CRLF +
  '  end;' + CRLF +
  'implementation' + CRLF +
  'procedure TFoo.Scroll(Delta: Integer);' + CRLF +
  'begin' + CRLF +
  '  inherited Scroll(Delta);' + CRLF +
  'end;' + CRLF +
  'end.';
begin
  Assert.AreEqual<Integer>(0, Treffer(SRC));
end;

procedure TTestInheritedMethodEmpty.OverloadedDeclaration_NoFinding;
const SRC = KOPF +
  '  TFoo = class(TLoader)' + CRLF +
  '  protected' + CRLF +
  '    procedure Load(const S: string); overload; override;' + CRLF +
  '    procedure Load(N: Integer); overload; override;' + CRLF +
  '  end;' + CRLF +
  'implementation' + CRLF +
  'procedure TFoo.Load(const S: string);' + CRLF +
  'begin' + CRLF +
  '  inherited Load(S);' + CRLF +
  'end;' + CRLF +
  'procedure TFoo.Load(N: Integer);' + CRLF +
  'begin' + CRLF +
  '  Clear;' + CRLF +
  'end;' + CRLF +
  'end.';
begin
  Assert.AreEqual<Integer>(0, Treffer(SRC));
end;

procedure TTestInheritedMethodEmpty.DirectiveInBody_NoFinding;
const SRC = KOPF +
  '  TFoo = class(TControl)' + CRLF +
  '  protected' + CRLF +
  '    procedure Paint; override;' + CRLF +
  '  end;' + CRLF +
  'implementation' + CRLF +
  'procedure TFoo.Paint;' + CRLF +
  'begin' + CRLF +
  '  {$WARNINGS OFF}' + CRLF +
  '  inherited;' + CRLF +
  'end;' + CRLF +
  'end.';
begin
  Assert.AreEqual<Integer>(0, Treffer(SRC));
end;

procedure TTestInheritedMethodEmpty.NamedWithoutArgsButParams_NoFinding;
// 'inherited Resize;' ruft die PARAMETERLOSE Variante - nur das nackte
// 'inherited;' reicht die Parameter implizit durch.
const SRC = KOPF +
  '  TFoo = class(TControl)' + CRLF +
  '  protected' + CRLF +
  '    procedure Resize(AWidth: Integer); override;' + CRLF +
  '  end;' + CRLF +
  'implementation' + CRLF +
  'procedure TFoo.Resize(AWidth: Integer);' + CRLF +
  'begin' + CRLF +
  '  inherited Resize;' + CRLF +
  'end;' + CRLF +
  'end.';
begin
  Assert.AreEqual<Integer>(0, Treffer(SRC));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestInheritedMethodEmpty);

end.

unit uTestMissingOverride;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMissingOverride = class
  public
    [Test] procedure MissingOverride_Reported;
    [Test] procedure WithOverride_NotReported;
    [Test] procedure WithReintroduce_NotReported;
    [Test] procedure NonVirtualParent_NotReported;
    [Test] procedure CrossUnitParent_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---
    [Test] procedure OverloadedDistinctSignature_NotReported;
    [Test] procedure ConstructorHidesVirtual_Reported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestMissingOverride.MissingOverride_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure DoWork; virtual;'#13#10 +
  '  end;'#13#10 +
  '  TDerived = class(TBase)'#13#10 +
  '    procedure DoWork;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMissingOverride) >= 1);
  finally F.Free; end;
end;

procedure TTestMissingOverride.WithOverride_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure DoWork; virtual;'#13#10 +
  '  end;'#13#10 +
  '  TDerived = class(TBase)'#13#10 +
  '    procedure DoWork; override;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingOverride));
  finally F.Free; end;
end;

procedure TTestMissingOverride.WithReintroduce_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure DoWork; virtual;'#13#10 +
  '  end;'#13#10 +
  '  TDerived = class(TBase)'#13#10 +
  '    procedure DoWork; reintroduce;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingOverride));
  finally F.Free; end;
end;

procedure TTestMissingOverride.NonVirtualParent_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure DoWork;'#13#10 +
  '  end;'#13#10 +
  '  TDerived = class(TBase)'#13#10 +
  '    procedure DoWork;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingOverride));
  finally F.Free; end;
end;

procedure TTestMissingOverride.CrossUnitParent_NotReported;
// Parent in anderer Unit (TForm) - Detektor erkennt es nicht, KEIN Finding.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TMyForm = class(TForm)'#13#10 +
  '    procedure Paint;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingOverride));
  finally F.Free; end;
end;

procedure TTestMissingOverride.Finding_KindAndSeverity;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure DoWork; virtual;'#13#10 +
  '  end;'#13#10 +
  '  TDerived = class(TBase)'#13#10 +
  '    procedure DoWork;'#13#10 +
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
      if Fnd.Kind = fkMissingOverride then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkMissingOverride finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;


// --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---

procedure TTestMissingOverride.OverloadedDistinctSignature_NotReported;
// Real-World-FP-Audit 2026-07-10 (Alcinoe.MultiPartParser:291,
// fpClass=distinct-signature-overload): eine `overload`-Methode mit
// ABWEICHENDER Signatur kuendigt bewusst eine zusaetzliche Ueberladung an und
// versteckt die virtuelle Basis NICHT - die gleich-signaturige Variante ist
// separat als `override` deklariert. Kein W1010 -> KEIN Finding.
// Der Fix (ef3608e) skippt jede Derived-Methode mit ';overload' im TypeRef
// (IsOverloadedDeclaration).
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure Decode(A: Integer); virtual;'#13#10 +
  '  end;'#13#10 +
  '  TDerived = class(TBase)'#13#10 +
  '    procedure Decode(A: Integer); overload; override;'#13#10 +
  '    procedure Decode(A, B: Integer); overload;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingOverride),
    'distinct-signature overload does not hide the base virtual - no W1010');
  finally F.Free; end;
end;

procedure TTestMissingOverride.ConstructorHidesVirtual_Reported;
// Real-World-FP-Audit 2026-07-10 tp_examples_must_stay (Kastri DW.FileWriter:45):
// TLogWriter redeklariert Create OHNE override/overload/reintroduce, waehrend
// TFileWriter.Create `overload; virtual` ist -> versteckt die virtuelle Basis
// echt (W1010). Der neue overload-Guard darf diesen Fund NICHT unterdruecken:
// der Nachfahr-Ctor traegt selbst KEIN ';overload', ist unqualifiziert und
// keine class-ctor -> muss weiter feuern.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFileWriter = class'#13#10 +
  '    constructor Create(const AFileName: string); overload; virtual;'#13#10 +
  '  end;'#13#10 +
  '  TLogWriter = class(TFileWriter)'#13#10 +
  '    constructor Create(const AFileName: string; ALevel: Integer);'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMissingOverride) >= 1,
    'derived ctor without override genuinely hides virtual base ctor (W1010)');
  finally F.Free; end;
end;
initialization
  TDUnitX.RegisterTestFixture(TTestMissingOverride);

end.

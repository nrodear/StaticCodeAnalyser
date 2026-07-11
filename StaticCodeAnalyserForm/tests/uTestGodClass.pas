unit uTestGodClass;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestGodClass = class
  public
    [Test] procedure ManyMethods_Reported;
    [Test] procedure ManyFields_Reported;
    [Test] procedure SmallClass_NotReported;
    [Test] procedure AbstractClass_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---
    [Test] procedure EmptyExceptionClassDecl_NotReported;
    [Test] procedure FormWithManyControls_Reported;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestGodClass.ManyMethods_Reported;
// 25 Methoden in einer Klasse > MAX_METHODS = 20.
var
  SB : TStringBuilder;
  i  : Integer;
  F  : TObjectList<TLeakFinding>;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; interface');
    SB.AppendLine('type');
    SB.AppendLine('  TGod = class');
    for i := 1 to 25 do
      SB.AppendLine(Format('    procedure M%d;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation end.');
    F := TFindingHelper.FindingsOf(SB.ToString);
    try Assert.IsTrue(TFindingHelper.Count(F, fkGodClass) >= 1);
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestGodClass.ManyFields_Reported;
// 20 Felder > MAX_FIELDS = 15.
var
  SB : TStringBuilder;
  i  : Integer;
  F  : TObjectList<TLeakFinding>;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; interface');
    SB.AppendLine('type');
    SB.AppendLine('  TFatRecord = class');
    for i := 1 to 20 do
      SB.AppendLine(Format('    F%d: Integer;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation end.');
    F := TFindingHelper.FindingsOf(SB.ToString);
    try Assert.IsTrue(TFindingHelper.Count(F, fkGodClass) >= 1);
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestGodClass.SmallClass_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    FA: Integer;'#13#10 +
  '    FB: Integer;'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGodClass));
  finally F.Free; end;
end;

procedure TTestGodClass.AbstractClass_NotReported;
// `class abstract` ist Designintent - selbst mit vielen Methoden kein
// Refactoring-Bedarf.
var
  SB : TStringBuilder;
  i  : Integer;
  F  : TObjectList<TLeakFinding>;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; interface');
    SB.AppendLine('type');
    SB.AppendLine('  TFramework = class abstract');
    for i := 1 to 25 do
      SB.AppendLine(Format('    procedure M%d; virtual; abstract;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation end.');
    F := TFindingHelper.FindingsOf(SB.ToString);
    try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGodClass));
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestGodClass.Finding_KindAndSeverity;
var
  SB  : TStringBuilder;
  i   : Integer;
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; interface');
    SB.AppendLine('type');
    SB.AppendLine('  TGod = class');
    for i := 1 to 25 do
      SB.AppendLine(Format('    procedure M%d;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation end.');
    F := TFindingHelper.FindingsOf(SB.ToString);
    try
      Hit := nil;
      for Fnd in F do
        if Fnd.Kind = fkGodClass then begin Hit := Fnd; Break; end;
      Assert.IsNotNull(Hit, 'fkGodClass finding expected');
      Assert.AreEqual(fkGodClass, Hit.Kind);
      Assert.AreEqual(lsWarning,  Hit.Severity);
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;


// --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---

procedure TTestGodClass.EmptyExceptionClassDecl_NotReported;
// Real-World FP-Audit 2026-07-10 (Alcinoe ALOpenOffice.pas / Alcinoe.ExprEval.pas):
// `EFoo = class(Exception);` ist eine leere Einzeiler-Deklaration - die Quellzeile
// endet auf ');' und die Klasse hat KEINEN Body. Der Parser kennt fuer `class(...)`
// keinen Semikolon-Abbruch (ParseClassBody schluckt via `else Next` alles bis zum
// naechsten `end`) und zieht die nachfolgenden Unit-Level-Routinen faelschlich als
// Methoden herein -> absurder God-Class-Count (real EALOpenOfficeException 22m).
// IsEmptyClassDeclLine (Fix ef3608e) erkennt die `);'-Zeile und unterdrueckt den
// reinen Parser-Slurp-Artefakt-Fund. Kein Bug: 0 echte Member.
// MUSS ueber FindingsOfFile laufen - der Guard liest die Quellzeile per AcquireLines
// (im AST-only-Harness FindingsOf ist Lines=nil und der Guard feuert nie).
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  EFoo = class(Exception);'#13#10 +
  '  procedure P01;'#13#10 +
  '  procedure P02;'#13#10 +
  '  procedure P03;'#13#10 +
  '  procedure P04;'#13#10 +
  '  procedure P05;'#13#10 +
  '  procedure P06;'#13#10 +
  '  procedure P07;'#13#10 +
  '  procedure P08;'#13#10 +
  '  procedure P09;'#13#10 +
  '  procedure P10;'#13#10 +
  '  procedure P11;'#13#10 +
  '  procedure P12;'#13#10 +
  '  procedure P13;'#13#10 +
  '  procedure P14;'#13#10 +
  '  procedure P15;'#13#10 +
  '  procedure P16;'#13#10 +
  '  procedure P17;'#13#10 +
  '  procedure P18;'#13#10 +
  '  procedure P19;'#13#10 +
  '  procedure P20;'#13#10 +
  '  procedure P21;'#13#10 +
  '  procedure P22;'#13#10 +
  '  procedure P23;'#13#10 +
  '  procedure P24;'#13#10 +
  '  procedure P25;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGodClass),
    'leere class(...);-Einzeiler-Decl (Parser-Slurp-Artefakt) ist keine God-Klasse');
  finally F.Free; end;
end;

procedure TTestGodClass.FormWithManyControls_Reported;
// Must-stay (Real-World-FP-Audit tp_examples_must_stay, Alcinoe ALButton TForm1):
// Composite-Root-Form mit 17 Control-Feldern (> MAX_FIELDS=15). rule_desc zielt
// explizit auf UI-Composite-Roots. Der Klassenkopf endet auf ')' (nicht ');') und
// der Body ist mehrzeilig mit terminierendem 'end;' -> IsEmptyClassDeclLine greift
// NICHT, der echte God-Class-Fund muss weiter feuern. Direkter Kontrastfall zum
// leeren Einzeiler oben (beweist: der Fix killt nur die `);'-Slurp-Artefakte).
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBigForm = class(TForm)'#13#10 +
  '    E01: TEdit;'#13#10 +
  '    E02: TEdit;'#13#10 +
  '    E03: TEdit;'#13#10 +
  '    E04: TEdit;'#13#10 +
  '    E05: TEdit;'#13#10 +
  '    E06: TEdit;'#13#10 +
  '    E07: TEdit;'#13#10 +
  '    E08: TEdit;'#13#10 +
  '    E09: TEdit;'#13#10 +
  '    E10: TEdit;'#13#10 +
  '    E11: TEdit;'#13#10 +
  '    E12: TEdit;'#13#10 +
  '    E13: TEdit;'#13#10 +
  '    E14: TEdit;'#13#10 +
  '    E15: TEdit;'#13#10 +
  '    E16: TEdit;'#13#10 +
  '    E17: TEdit;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkGodClass) >= 1,
    'Form mit 17 Control-Feldern (> 15) ist eine God-Klasse und muss weiter melden');
  finally F.Free; end;
end;
initialization
  TDUnitX.RegisterTestFixture(TTestGodClass);

end.

unit uTestInlineAssembly;

// Tests fuer TInlineAssemblyDetector (file-scan: `asm` Wort-Match).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestInlineAssembly = class
  public
    [Test] procedure NoAsm_NoFinding;
    [Test] procedure SimpleAsm_Reported;
    [Test] procedure UppercaseAsm_Reported;
    [Test] procedure AsmInString_NotReported;
    [Test] procedure AsmInLineComment_NotReported;
    [Test] procedure AsmInBlockComment_NotReported;
    [Test] procedure IdentifierWithAsmSubstr_NotReported;
    [Test] procedure InlineAssembly_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestInlineAssembly.NoAsm_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInlineAssembly));
  finally F.Free; end;
end;

procedure TTestInlineAssembly.SimpleAsm_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'function CpuId: Cardinal;'#13#10 +
  'asm'#13#10 +
  '  XOR EAX, EAX'#13#10 +
  '  CPUID'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInlineAssembly));
  finally F.Free; end;
end;

procedure TTestInlineAssembly.UppercaseAsm_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'function CpuId: Cardinal;'#13#10 +
  'ASM'#13#10 +                        // Pascal ist case-insensitive
  '  XOR EAX, EAX'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInlineAssembly));
  finally F.Free; end;
end;

procedure TTestInlineAssembly.AsmInString_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  WriteLn(''see asm block in CpuId for details'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInlineAssembly));
  finally F.Free; end;
end;

procedure TTestInlineAssembly.AsmInLineComment_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  '// historic asm fast-path removed in 2020 cleanup'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInlineAssembly));
  finally F.Free; end;
end;

procedure TTestInlineAssembly.AsmInBlockComment_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  '{ asm block removed }'#13#10 +
  '(* asm here too *)'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInlineAssembly));
  finally F.Free; end;
end;

procedure TTestInlineAssembly.IdentifierWithAsmSubstr_NotReported;
// `Bitmask` / `Schasm` / `MyAsmHelper` enthalten `asm`-Substrings - kein Match.
const SRC =
  'unit t; implementation'#13#10 +
  'var Bitmask: Cardinal; MyAsmHelper: TObject;'#13#10 +
  'procedure Foo; begin Bitmask := 0; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInlineAssembly));
  finally F.Free; end;
end;

procedure TTestInlineAssembly.InlineAssembly_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'function CpuId: Cardinal;'#13#10 +
  'asm'#13#10 +
  '  CPUID'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkInlineAssembly then
      begin
        Assert.AreEqual<TFindingKind>(fkInlineAssembly, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsWarning,       Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkInlineAssembly finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestInlineAssembly);

end.

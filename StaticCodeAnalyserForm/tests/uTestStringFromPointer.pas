unit uTestStringFromPointer;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestStringFromPointer = class
  public
    [Test] procedure StringFromPByte_Reported;
    [Test] procedure UTF8StringFromPChar_Reported;
    [Test] procedure StringFromInteger_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestStringFromPointer.StringFromPByte_Reported;
// Variable muss mit P+Grossbuchstabe beginnen (lex-Heuristik in uSCA160).
// Realistisches mORMot-Idiom: `var PBuf: PByte` oder direkter Cast `PByte(...)`.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var PBuf: PByte; s: string;'#13#10 +
  'begin'#13#10 +
  '  s := string(PBuf);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkStringFromPointer) >= 1);
  finally F.Free; end;
end;

procedure TTestStringFromPointer.UTF8StringFromPChar_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var PName: PChar; s: RawUTF8;'#13#10 +
  'begin'#13#10 +
  '  s := UTF8String(PName);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkStringFromPointer) >= 1);
  finally F.Free; end;
end;

procedure TTestStringFromPointer.StringFromInteger_NotReported;
// string(IntegerVar) ist eine andere Cast-Form (Integer->String), kein
// Pointer-Cast - kein P-Praefix -> kein Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(N: Integer);'#13#10 +
  'var s: string;'#13#10 +
  'begin'#13#10 +
  '  s := IntToStr(N);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringFromPointer));
  finally F.Free; end;
end;

procedure TTestStringFromPointer.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var PBuf: PByte; s: string;'#13#10 +
  'begin'#13#10 +
  '  s := string(PBuf);'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkStringFromPointer then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkStringFromPointer finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestStringFromPointer);

end.

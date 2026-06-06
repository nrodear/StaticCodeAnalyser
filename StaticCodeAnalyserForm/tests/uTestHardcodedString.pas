unit uTestHardcodedString;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestHardcodedString = class
  public
    [Test] procedure CaptionAssignment_Reported;
    [Test] procedure ShowMessageLiteral_Reported;
    [Test] procedure ResourceKeyStyle_NotReported;
    [Test] procedure EmptyString_NotReported;
    [Test] procedure SingleCharString_NotReported;
    [Test] procedure NonLetterString_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestHardcodedString.CaptionAssignment_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Form1.Caption := ''Mein Programm'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkHardcodedString) >= 1);
  finally F.Free; end;
end;

procedure TTestHardcodedString.ShowMessageLiteral_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  ShowMessage(''Daten gespeichert'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkHardcodedString) >= 1);
  finally F.Free; end;
end;

procedure TTestHardcodedString.ResourceKeyStyle_NotReported;
// UPPER_SNAKE Key sieht wie ein Resource-Identifier aus -> kein Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Form1.Caption := ''S_MAIN_FORM_CAPTION'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedString));
  finally F.Free; end;
end;

procedure TTestHardcodedString.EmptyString_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Form1.Caption := '''';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedString));
  finally F.Free; end;
end;

procedure TTestHardcodedString.SingleCharString_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Form1.Caption := ''-'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedString));
  finally F.Free; end;
end;

procedure TTestHardcodedString.NonLetterString_NotReported;
// Nur Sonderzeichen / Zahlen, kein Buchstabe -> kein User-Text.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Form1.Caption := ''123.45'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedString));
  finally F.Free; end;
end;

procedure TTestHardcodedString.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Form1.Caption := ''Hello World'';'#13#10 +
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
      if Fnd.Kind = fkHardcodedString then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkHardcodedString finding expected');
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestHardcodedString);

end.

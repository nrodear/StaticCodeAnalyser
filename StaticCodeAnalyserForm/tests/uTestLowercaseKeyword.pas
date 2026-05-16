unit uTestLowercaseKeyword;

// Tests fuer TLowercaseKeywordDetector (file-scan, kuratierte Keyword-Liste).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLowercaseKeyword = class
  public
    [Test] procedure AllLowercase_NoFinding;
    [Test] procedure PascalCaseBegin_Reported;
    [Test] procedure UppercaseEnd_Reported;
    [Test] procedure MultipleMixedCase_AllReported;
    [Test] procedure KeywordInStringLiteral_NoFinding;
    [Test] procedure KeywordInLineComment_NoFinding;
    [Test] procedure KeywordInBlockComment_NoFinding;
    [Test] procedure IdentifierWithKeywordSubstr_NoFinding;
    [Test] procedure LowercaseKeyword_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestLowercaseKeyword.AllLowercase_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if X then DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLowercaseKeyword));
  finally F.Free; end;
end;

procedure TTestLowercaseKeyword.PascalCaseBegin_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'Begin'#13#10 +                      // <-- Begin = Treffer
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkLowercaseKeyword));
  finally F.Free; end;
end;

procedure TTestLowercaseKeyword.UppercaseEnd_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoStuff;'#13#10 +
  'END;';                              // <-- END = Treffer
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkLowercaseKeyword));
  finally F.Free; end;
end;

procedure TTestLowercaseKeyword.MultipleMixedCase_AllReported;
const SRC =
  'Unit t; Implementation'#13#10 +    // Unit + Implementation = 2
  'Procedure Foo;'#13#10 +            // Procedure = 1
  'Begin'#13#10 +                     // Begin = 1
  '  If X Then DoStuff;'#13#10 +      // If + Then = 2
  'End;';                             // End = 1
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(7, TFindingHelper.Count(F, fkLowercaseKeyword));
  finally F.Free; end;
end;

procedure TTestLowercaseKeyword.KeywordInStringLiteral_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  WriteLn(''Begin Procedure End'');'#13#10 +  // String -> kein Treffer
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLowercaseKeyword));
  finally F.Free; end;
end;

procedure TTestLowercaseKeyword.KeywordInLineComment_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  '// Procedure Begin End if then'#13#10 +     // Komentar -> kein Treffer
  'procedure Foo;'#13#10 +
  'begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLowercaseKeyword));
  finally F.Free; end;
end;

procedure TTestLowercaseKeyword.KeywordInBlockComment_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  '{ Procedure Begin End }'#13#10 +
  '(* If Then Else *)'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLowercaseKeyword));
  finally F.Free; end;
end;

procedure TTestLowercaseKeyword.IdentifierWithKeywordSubstr_NoFinding;
// MyBegin / EndPoint enthalten Keyword-Substrings, sind aber selbst keine
// Keywords. Word-Boundary-Check muss greifen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var MyBegin: Integer; EndPoint: TPoint;'#13#10 +
  'begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLowercaseKeyword));
  finally F.Free; end;
end;

procedure TTestLowercaseKeyword.LowercaseKeyword_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'Procedure Foo; begin end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkLowercaseKeyword then
      begin
        Assert.AreEqual<TFindingKind>(fkLowercaseKeyword, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint, Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkLowercaseKeyword finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLowercaseKeyword);

end.

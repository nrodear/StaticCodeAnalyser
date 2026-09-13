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
    // Voll-Review 2026-09-12 (Major 75): asm-Bloecke
    [Test] procedure AsmMnemonics_NoFinding;
    [Test] procedure UppercaseAfterAsmEnd_StillReported;
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLowercaseKeyword));
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
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkLowercaseKeyword));
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
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkLowercaseKeyword));
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
  try Assert.AreEqual<Integer>(7, TFindingHelper.Count(F, fkLowercaseKeyword));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLowercaseKeyword));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLowercaseKeyword));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLowercaseKeyword));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLowercaseKeyword));
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

procedure TTestLowercaseKeyword.AsmMnemonics_NoFinding;
// Voll-Review 2026-09-12 (Major 75): der Scanner kannte keinen
// asm-Zustand - XOR/SHL im klassischen Uppercase-BASM-Stil wurden als
// Keyword-Verstoss gemeldet, obwohl es x86-Mnemonics sind (der
// Harness sieht fcLow-Funde ungefiltert; an der CLI verdeckt der
// Default-Confidence-Filter das Kind komplett).
const SRC =
  'unit t; implementation'#13#10 +
  'function Q(x: Integer): Integer;'#13#10 +
  'asm'#13#10 +
  '  XOR EAX,EAX'#13#10 +
  '  SHL EDX,2'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLowercaseKeyword),
    'Mnemonics im asm-Block sind keine Pascal-Keywords');
  finally F.Free; end;
end;

procedure TTestLowercaseKeyword.UppercaseAfterAsmEnd_StillReported;
// Gegenrichtung: NACH dem schliessenden `end` des asm-Blocks ist der
// Scanner wieder scharf - pinnt, dass der Zustand korrekt verlassen
// wird und Major 75 nicht ueberschiesst.
const SRC =
  'unit t; implementation'#13#10 +
  'function Q(x: Integer): Integer;'#13#10 +
  'asm'#13#10 +
  '  XOR EAX,EAX'#13#10 +
  'end;'#13#10 +
  'procedure P;'#13#10 +
  'begin'#13#10 +
  '  IF True then'#13#10 +
  '    Exit;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkLowercaseKeyword),
    'nach dem asm-end wird IF wieder gemeldet');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLowercaseKeyword);

end.

unit uTestCommentedOutCode;

// Tests fuer TCommentedOutCodeDetector (Heuristik auf Pascal-Marker
// in //- und {}-Kommentaren).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCommentedOutCode = class
  public
    [Test] procedure ProseComment_NoFinding;
    [Test] procedure CodeLineComment_Reported;
    [Test] procedure CodeBlockComment_Reported;
    [Test] procedure SinglePascalToken_NoFinding;
    [Test] procedure ProseWithWeakKeywords_NoFinding;
    [Test] procedure CompilerDirective_NoFinding;
    [Test] procedure CommentedOutCode_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestCommentedOutCode.ProseComment_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  '// FreeAndNil is safer than Free for fields'#13#10 +
  '// see DocWiki for details'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommentedOutCode));
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.CodeLineComment_Reported;
// Kommentar mit `:=` und trailing `;` -> 2 Marker -> Treffer.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  // X := 42;'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCommentedOutCode) >= 1);
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.CodeBlockComment_Reported;
// `{...}` block comment mit `begin`/`end` plus `;` -> 3+ Marker.
const SRC =
  'unit t; implementation'#13#10 +
  '{ if Active then begin DoStuff; end; }'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCommentedOutCode) >= 1);
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.SinglePascalToken_NoFinding;
// Nur ein Marker (trailing `;`) - Schwelle = 2.
const SRC =
  'unit t; implementation'#13#10 +
  '// use FreeAndNil instead of Free;'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommentedOutCode));
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.ProseWithWeakKeywords_NoFinding;
// FP-Fix (Real-World 2026-06-28): englische Prosa mit prosa-haeufigen Keywords
// (if/then/for/while/end) traf frueher die 2-Marker-Schwelle und wurde als
// Code geflaggt. Ohne STARKEN Pascal-Marker (:=, trailing ;, begin/procedure/
// function) jetzt kein Treffer. Kommentar steht isoliert zwischen Code-Zeilen,
// damit nicht der Doc-Block-Guard (angrenzende //) das Ergebnis verfaelscht.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoA;'#13#10 +
  '  // if the value is nil then return for each item while at the end'#13#10 +
  '  DoB;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommentedOutCode),
    'Prosa mit if/then/for/while/end ohne starken Marker ist kein Code');
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.CompilerDirective_NoFinding;
// `{$...}` ist Compiler-Direktive, kein Kommentar - kein Treffer.
const SRC =
  'unit t;'#13#10 +
  '{$IFDEF DEBUG}'#13#10 +
  '{$DEFINE WITH_LOGGING}'#13#10 +
  '{$ENDIF}'#13#10 +
  'implementation'#13#10 +
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommentedOutCode));
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.CommentedOutCode_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  '// X := 42; if X then begin DoStuff; end;'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkCommentedOutCode then
      begin
        Assert.AreEqual<TFindingKind>(fkCommentedOutCode, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,            Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkCommentedOutCode finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCommentedOutCode);

end.

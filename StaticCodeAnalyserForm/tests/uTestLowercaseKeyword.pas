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
    // Posten 260: der '&'-Escape macht Keywords zu Identifiern
    [Test] procedure EscapedIdentifier_NoFinding;
    [Test] procedure EscapedIdentifierThenRealKeyword_StillReported;
    // Posten 171: mehrzeiliger Kommentar-Zustand
    [Test] procedure KeywordInMultiLineBlockComment_NoFinding;
    [Test] procedure KeywordInMultiLineParenStarComment_NoFinding;
    [Test] procedure KeywordAfterMultiLineCommentClose_StillReported;
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

{ --- Posten 260: der '&'-Escape -------------------------------- }
//
// Der Scanner kannte den Delphi-Escape nicht: das & fiel schlicht
// durch, danach begann das Wort regulaer, IsKeyword schlug an und die
// Grossschreibung wurde geruegt. `&Type`, `&To`, `&Set` sind aber
// IDENTIFIER - Java-, COM- und Redis-Namen, Property-Namen -, und die
// Kleinschreib-Konvention gilt fuer sie nicht.
//
// Der Kopfkommentar der Unit fuehrt als bewusste Ausnahmen nur die
// kontextsensitiven Woerter (default/read/write/name/message) auf;
// der Escape-Fall stand dort nicht, war also keine gewollte Grenze.
//
// Beide Erwartungen an der gebauten Exe gemessen. ACHTUNG beim
// Nachmessen: SCA064 ist fcLow und braucht MinConfidence=low in der
// ini - mit den Vorgaben liefern beide Fixturen 0 Funde.

procedure TTestLowercaseKeyword.EscapedIdentifier_NoFinding;
// Heute 2 Funde (Zeile 5 und 6), nach dem Fix 0.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Y: Integer;'#13#10 +
  'begin'#13#10 +
  '  Y := Bar.&Type;'#13#10 +
  '  Bar.&To := Y;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkLowercaseKeyword),
      'ein Wort hinter & ist ein Identifier, kein Keyword');
  finally F.Free; end;
end;

procedure TTestLowercaseKeyword.EscapedIdentifierThenRealKeyword_StillReported;
// GEGENPROBE auf DERSELBEN Zeile: der Escape darf nur sich selbst
// stillstellen, nicht den Rest der Zeile. Heute 2 Funde (beide auf
// Zeile 5), nach dem Fix genau 1 - das 'End'.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Y: Integer;'#13#10 +
  'begin'#13#10 +
  '  Y := Bar.&Type; End;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkLowercaseKeyword),
      'das End hinter dem Escape bleibt ein Keyword');
  finally F.Free; end;
end;


{ --- Posten 171: der Kommentar-Zustand ueber Zeilengrenzen ------- }
//
// KeywordInBlockComment_NoFinding prueft nur EINZEILIGE Kommentare.
// Der Zeilenuebertrag von InBlockComm/InParenStarComm - der
// fehleranfaelligste Teil des Scanners - war unbelegt.
//
// Der Scanner ist hier NICHT betroffen von dem Zustandsleck, das in
// derselben Charge uSuperfluousSemicolon, uGotoStatement und
// uGroupedDeclaration getroffen hat: er sammelt je Zeile alle Woerter
// und steigt am Treffer nicht aus. An der gebauten Exe geprueft -
// 'BEGIN' vor einem geoeffneten Kommentar und 'END;' darin ergeben
// zusammen genau 1 Fund. Diese Tests nageln das fest.
//
// ACHTUNG beim Nachmessen von Hand: SCA064 ist fcLow und braucht
// MinConfidence=low in der ini, sonst liefert jede Fixture 0.

procedure TTestLowercaseKeyword.KeywordInMultiLineBlockComment_NoFinding;
// Grossgeschriebenes Keyword INNERHALB eines ueber zwei Zeilen
// offenen {..}. Vor wie nach der Ergaenzung 1 Fund - und zwar der
// echte 'BEGIN', nicht das auskommentierte 'END;'.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'BEGIN'#13#10 +
  '  Beep;  {'#13#10 +
  '  END;'#13#10 +
  '  }'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkLowercaseKeyword),
      'nur das echte BEGIN zaehlt, das END im Kommentar nicht');
  finally F.Free; end;
end;

procedure TTestLowercaseKeyword.KeywordInMultiLineParenStarComment_NoFinding;
// Dasselbe fuer die (* *)-Form - eigener Zustand, eigener Pfad.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'BEGIN'#13#10 +
  '  Beep;  (*'#13#10 +
  '  END;'#13#10 +
  '  *)'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkLowercaseKeyword),
      'auch der (* *)-Zustand traegt ueber die Zeilengrenze');
  finally F.Free; end;
end;

procedure TTestLowercaseKeyword.KeywordAfterMultiLineCommentClose_StillReported;
// Die Gegenrichtung: hinter dem Kommentarende zaehlt wieder Code.
// Wuerde der Zustand nicht ZURUECKGESETZT, bliebe der Rest der Unit
// stumm - dieser Test faengt das.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Beep;  {'#13#10 +
  '  Notiz'#13#10 +
  '  }'#13#10 +
  '  END;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkLowercaseKeyword),
      'nach dem Kommentarende wird wieder gemeldet');
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

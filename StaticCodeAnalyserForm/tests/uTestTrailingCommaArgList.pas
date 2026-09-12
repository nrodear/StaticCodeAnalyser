unit uTestTrailingCommaArgList;

// Tests fuer TTrailingCommaArgListDetector (file-scan: `,\s*)`).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTrailingCommaArgList = class
  public
    [Test] procedure NoTrailingComma_NoFinding;
    [Test] procedure SingleTrailingComma_Reported;
    [Test] procedure TrailingCommaWithSpace_Reported;
    [Test] procedure TrailingCommaInString_NotReported;
    [Test] procedure TrailingCommaInComment_NotReported;
    [Test] procedure InteriorComma_NotReported;
    [Test] procedure TrailingCommaArgList_KindAndSeverity;
    // Voll-Review 2026-09-12 (Testluecke 113): die Kommentar-Zustaende
    [Test] procedure ParenStarCommentDoesNotSuppressRealCase;
    [Test] procedure MultiLineBraceCommentDoesNotSuppressRealCase;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestTrailingCommaArgList.NoTrailingComma_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  WriteLn(''A'', ''B'');'#13#10 +
  '  DoStuff(1, 2, 3);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTrailingCommaArgList));
  finally F.Free; end;
end;

procedure TTestTrailingCommaArgList.SingleTrailingComma_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoStuff(A, B,);'#13#10 +          // <-- trailing comma
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTrailingCommaArgList));
  finally F.Free; end;
end;

procedure TTestTrailingCommaArgList.TrailingCommaWithSpace_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  DoStuff(A, B,   );'#13#10 +       // Komma + space + `)`
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTrailingCommaArgList));
  finally F.Free; end;
end;

procedure TTestTrailingCommaArgList.TrailingCommaInString_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  WriteLn(''A, B,)'');'#13#10 +     // Komma + `)` im String
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTrailingCommaArgList));
  finally F.Free; end;
end;

procedure TTestTrailingCommaArgList.TrailingCommaInComment_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  '// DoStuff(A, B,) was a typo'#13#10 +
  '{ DoStuff(C, D,) in this comment }'#13#10 +
  'procedure Foo; begin DoStuff(A, B); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTrailingCommaArgList));
  finally F.Free; end;
end;

procedure TTestTrailingCommaArgList.InteriorComma_NotReported;
// Komma in der Mitte einer Argument-Liste (kein trailing).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoStuff(A, B, C);'#13#10 +
  '  Format(''%d-%d'', [1, 2]);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTrailingCommaArgList));
  finally F.Free; end;
end;

procedure TTestTrailingCommaArgList.TrailingCommaArgList_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; begin DoStuff(A,); end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkTrailingCommaArgList then
      begin
        Assert.AreEqual<TFindingKind>(fkTrailingCommaArgList, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,                Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkTrailingCommaArgList finding');
  finally F.Free; end;
end;

procedure TTestTrailingCommaArgList.ParenStarCommentDoesNotSuppressRealCase;
// Testluecke 113 (Voll-Review 2026-09-12): der (*..*)-Pfad war ohne
// Test. Die Fixture legt beide Faelle nebeneinander - dieselbe
// Zeichenfolge einmal im Kommentar (darf NICHT melden) und einmal als
// echter Aufruf (muss melden). Genau EIN Fund beweist beide Seiten
// zugleich.
//
// Der Detektor arbeitet zeilenweise: die abschliessende Klammer muss
// auf derselben Zeile stehen wie das Komma (an der gebauten Exe
// gemessen - die mehrzeilige Form meldet nicht, und das ist eine
// andere, hier nicht behandelte Grenze).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure P;'#13#10 +
  'begin'#13#10 +
  '  (* Beispiel: DoIt(1, 2, ); *)'#13#10 +
  '  DoIt(1, 2, );'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkTrailingCommaArgList),
    'nur der echte Aufruf zaehlt, nicht das Beispiel im Kommentar');
  finally F.Free; end;
end;

procedure TTestTrailingCommaArgList.MultiLineBraceCommentDoesNotSuppressRealCase;
// Zweiter Zustand: ein {..}-Blockkommentar ueber MEHRERE Zeilen, in
// dem das Muster vorkommt. Der Zustand muss ueber die Zeilengrenze
// getragen werden - sonst meldete die mittlere Kommentarzeile, und der
// echte Fall dahinter koennte verloren gehen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure P;'#13#10 +
  'begin'#13#10 +
  '  { Beispiel:'#13#10 +
  '    DoIt(1, 2, );'#13#10 +
  '    noch im Kommentar }'#13#10 +
  '  DoIt(1, 2, );'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkTrailingCommaArgList),
    'der Blockkommentar-Zustand traegt ueber Zeilen');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestTrailingCommaArgList);

end.

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
    // Voll-Review 2026-09-12 (Major 69): Kommentare zaehlen NIE als Code
    [Test] procedure BlockComment_NotReported;
    [Test] procedure TrailingLineComment_NotReported;
    // Testluecke 156: die ungetesteten Ausgabewege
    [Test] procedure MessageDlgLiteral_Reported;
    [Test] procedure HintProperty_Reported;
    [Test] procedure TextProperty_Reported;
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

procedure TTestHardcodedString.BlockComment_NotReported;
// Voll-Review 2026-09-12 (Major 69): nur GANZZEILIGE //-Kommentare
// wurden uebersprungen - auskommentierter Code im {..}-Block wurde
// gemeldet (Bestands-Exe: 1 FP auf dieser Fixture, empirisch belegt;
// Projektregel 'Kommentare zaehlen NIE als Code-Use').
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  { Form1.Caption := ''Alte Beschriftung''; }'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedString),
    'auskommentierte Zuweisung im Blockkommentar ist kein Code-Use');
  finally F.Free; end;
end;

procedure TTestHardcodedString.TrailingLineComment_NotReported;
// Geschwisterfall zu BlockComment_NotReported: der //-Kommentar HINTER
// Code auf derselben Zeile fiel durch den alten Trim-StartsWith-Skip
// (Bestands-Exe: 1 FP auf dieser Fixture, empirisch belegt).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoIt; // ShowMessage(''Hallo Welt'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedString),
    'Trailing-Kommentar hinter Code ist kein Code-Use');
  finally F.Free; end;
end;

{ --- Testluecke 156: MessageDlg, Hint, Text ---------------------- }
//
// Der Detektor kennt zwei Wege zum Nutzer: den Dialog-Aufruf und die
// Text-Property. Belegt war von jedem nur EINE Auspraegung -
// ShowMessage und Caption. MessageDlg steht zwar im Meldetext, war
// aber nie geprueft; Hint und Text ebenso wenig.
// Alle drei am gebauten Stand nachgemessen: je 1 Fund.

procedure TTestHardcodedString.MessageDlgLiteral_Reported;
// Der zweite Dialog-Aufruf neben ShowMessage. Faellt er aus der
// Liste, bleibt die Suite gruen - der Meldetext nennt ihn trotzdem.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  MessageDlg(''Datei konnte nicht geladen werden'', mtError, [mbOK], 0);'#13#10 +
  'end;'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkHardcodedString),
    'MessageDlg ist ein Ausgabeweg wie ShowMessage');
  finally F.Free; end;
end;

procedure TTestHardcodedString.HintProperty_Reported;
// Hint ist eine eigene Property in der Liste, nicht Caption.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Button1.Hint := ''Diesen Knopf zum Speichern druecken'';'#13#10 +
  'end;'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkHardcodedString),
    'ein Hint ist sichtbarer Text');
  finally F.Free; end;
end;

procedure TTestHardcodedString.TextProperty_Reported;
// Text ist die dritte Property der Liste.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Edit1.Text := ''Bitte hier den Namen eintragen'';'#13#10 +
  'end;'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkHardcodedString),
    'auch ein Edit-Text ist sichtbarer Text');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestHardcodedString);

end.

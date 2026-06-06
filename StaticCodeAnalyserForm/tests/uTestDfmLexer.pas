unit uTestDfmLexer;

// Smoke-Tests für uDfmLexer - Phase 1 Walking-Skeleton.
// Fokus: Token-Sequenz fuer Hierarchie, String-Multi-Segment-Merging,
// Klammer-Blöcke als atomare Tokens, Robustheit gegen Klammer-Zeichen
// innerhalb von Strings.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmLexer = class
  public
    // --- Grundsätzliches ---
    [Test] procedure Test_Empty_ReturnsEof;
    [Test] procedure Test_Whitespace_IsSkipped;

    // --- Object-Hierarchie ---
    [Test] procedure Test_BasicObject_TokenSequence;
    [Test] procedure Test_NestedObject_TokenSequence;
    [Test] procedure Test_InheritedKeyword;
    [Test] procedure Test_InlineKeyword;

    // --- Property-Wert-Atome ---
    [Test] procedure Test_QualifiedPropertyPath;
    [Test] procedure Test_BooleanKeywords;
    [Test] procedure Test_Integer;
    [Test] procedure Test_NegativeIntegerAsTwoTokens;
    [Test] procedure Test_HexInteger;
    [Test] procedure Test_Float;

    // --- Strings ---
    [Test] procedure Test_SimpleString;
    [Test] procedure Test_StringWithDoubledQuote_Escape;
    [Test] procedure Test_String_CharCodeConcat;
    [Test] procedure Test_String_HexCharCode;
    [Test] procedure Test_String_PlusContinuation_Merges;
    [Test] procedure Test_String_LineBreakBetweenSegments_Merges;

    // --- Klammer-Blöcke als atomare Tokens ---
    [Test] procedure Test_Set_AsAtomicToken;
    [Test] procedure Test_Binary_AsAtomicToken_EmptyValue;
    [Test] procedure Test_ItemList_AsAtomicToken;
    [Test] procedure Test_ItemList_Nested_DepthCounter;
    [Test] procedure Test_StrList_AsAtomicToken;

    // --- Robustheit: Klammer-Zeichen in Strings dürfen Balance nicht brechen ---
    [Test] procedure Test_BracketCharInString_DoesNotBreakSet;
    [Test] procedure Test_AngleCharInString_DoesNotBreakItemList;
    [Test] procedure Test_ParenCharInString_DoesNotBreakStrList;

    // --- Realer DFM-Schnipsel ---
    [Test] procedure Test_RealisticFormStub_NoUnknownTokens;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  uDfmLexer;

{ Helper: alle Tokens bis tkEof einsammeln. }
function CollectTokens(const Src: string): TList<TDfmToken>;
var
  Lex : TDfmLexer;
  Tok : TDfmToken;
begin
  Result := TList<TDfmToken>.Create;
  Lex := TDfmLexer.Create(Src);
  try
    repeat
      Tok := Lex.Next;
      Result.Add(Tok);
    until Tok.Kind = tkEof;
  finally
    Lex.Free;
  end;
end;

{ --- Grundsätzliches --- }

procedure TTestDfmLexer.Test_Empty_ReturnsEof;
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('');
  try
    Assert.AreEqual<Integer>(1, Toks.Count);
    Assert.AreEqual(tkEof, Toks[0].Kind);
  finally
    Toks.Free;
  end;
end;

procedure TTestDfmLexer.Test_Whitespace_IsSkipped;
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('   '#13#10'   '#9'  ');
  try
    Assert.AreEqual<Integer>(1, Toks.Count);
    Assert.AreEqual(tkEof, Toks[0].Kind);
  finally
    Toks.Free;
  end;
end;

{ --- Object-Hierarchie --- }

procedure TTestDfmLexer.Test_BasicObject_TokenSequence;
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('object Form2: TForm2'#13#10'end');
  try
    Assert.AreEqual(6, Toks.Count, 'erwartet: object Form2 : TForm2 end EOF');
    Assert.AreEqual(tkKwObject, Toks[0].Kind);
    Assert.AreEqual(tkIdent,    Toks[1].Kind);
    Assert.AreEqual('Form2',    Toks[1].Value);
    Assert.AreEqual(tkColon,    Toks[2].Kind);
    Assert.AreEqual(tkIdent,    Toks[3].Kind);
    Assert.AreEqual('TForm2',   Toks[3].Value);
    Assert.AreEqual(tkKwEnd,    Toks[4].Kind);
    Assert.AreEqual(tkEof,      Toks[5].Kind);
  finally
    Toks.Free;
  end;
end;

procedure TTestDfmLexer.Test_NestedObject_TokenSequence;
var
  Toks: TList<TDfmToken>;
  ObjectCount, EndCount, I: Integer;
begin
  Toks := CollectTokens(
    'object Form2: TForm2'#13#10 +
    '  object Btn1: TButton'#13#10 +
    '  end'#13#10 +
    '  object Panel1: TPanel'#13#10 +
    '    object Lbl1: TLabel'#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    'end');
  try
    ObjectCount := 0;
    EndCount    := 0;
    for I := 0 to Toks.Count - 1 do
    begin
      if Toks[I].Kind = tkKwObject then Inc(ObjectCount);
      if Toks[I].Kind = tkKwEnd    then Inc(EndCount);
    end;
    Assert.AreEqual(4, ObjectCount, 'vier object-Header');
    Assert.AreEqual(4, EndCount,    'vier end-Tokens');
  finally
    Toks.Free;
  end;
end;

procedure TTestDfmLexer.Test_InheritedKeyword;
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('inherited Form2: TForm2 end');
  try
    Assert.AreEqual(tkKwInherited, Toks[0].Kind);
  finally
    Toks.Free;
  end;
end;

procedure TTestDfmLexer.Test_InlineKeyword;
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('inline Frame1: TFrame1 end');
  try
    Assert.AreEqual(tkKwInline, Toks[0].Kind);
  finally
    Toks.Free;
  end;
end;

{ --- Property-Wert-Atome --- }

procedure TTestDfmLexer.Test_QualifiedPropertyPath;
// Font.Style = ...
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('Font.Style = []');
  try
    Assert.AreEqual(tkIdent,  Toks[0].Kind); Assert.AreEqual('Font',  Toks[0].Value);
    Assert.AreEqual(tkDot,    Toks[1].Kind);
    Assert.AreEqual(tkIdent,  Toks[2].Kind); Assert.AreEqual('Style', Toks[2].Value);
    Assert.AreEqual(tkEquals, Toks[3].Kind);
    Assert.AreEqual(tkSet,    Toks[4].Kind);
  finally
    Toks.Free;
  end;
end;

procedure TTestDfmLexer.Test_BooleanKeywords;
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('Visible = True Enabled = False');
  try
    Assert.AreEqual(tkKwTrue,  Toks[2].Kind);
    Assert.AreEqual(tkKwFalse, Toks[5].Kind);
  finally
    Toks.Free;
  end;
end;

procedure TTestDfmLexer.Test_Integer;
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('Top = 42');
  try
    Assert.AreEqual(tkInteger, Toks[2].Kind);
    Assert.AreEqual('42',      Toks[2].Value);
  finally
    Toks.Free;
  end;
end;

procedure TTestDfmLexer.Test_NegativeIntegerAsTwoTokens;
// '-' und Zahl bleiben getrennte Tokens; Parser fügt zusammen.
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('Tag = -1');
  try
    Assert.AreEqual(tkMinus,   Toks[2].Kind);
    Assert.AreEqual(tkInteger, Toks[3].Kind);
    Assert.AreEqual('1',       Toks[3].Value);
  finally
    Toks.Free;
  end;
end;

procedure TTestDfmLexer.Test_HexInteger;
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('Color = $00FF00FF');
  try
    Assert.AreEqual(tkInteger,   Toks[2].Kind);
    Assert.AreEqual('$00FF00FF', Toks[2].Value);
  finally
    Toks.Free;
  end;
end;

procedure TTestDfmLexer.Test_Float;
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('Ratio = 1.5');
  try
    Assert.AreEqual(tkFloat, Toks[2].Kind);
    Assert.AreEqual('1.5',   Toks[2].Value);
  finally
    Toks.Free;
  end;
end;

{ --- Strings --- }

procedure TTestDfmLexer.Test_SimpleString;
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('Caption = ''Hallo''');
  try
    Assert.AreEqual(tkString, Toks[2].Kind);
    Assert.AreEqual('Hallo',  Toks[2].Value);
  finally
    Toks.Free;
  end;
end;

procedure TTestDfmLexer.Test_StringWithDoubledQuote_Escape;
// 'It''s' -> It's
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('Caption = ''It''''s''');
  try
    Assert.AreEqual(tkString, Toks[2].Kind);
    Assert.AreEqual('It''s',  Toks[2].Value);
  finally
    Toks.Free;
  end;
end;

procedure TTestDfmLexer.Test_String_CharCodeConcat;
// 'a'#10'b' -> a<LF>b
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('Caption = ''a''#10''b''');
  try
    Assert.AreEqual(tkString,    Toks[2].Kind);
    Assert.AreEqual('a'#10'b',   Toks[2].Value);
  finally
    Toks.Free;
  end;
end;

procedure TTestDfmLexer.Test_String_HexCharCode;
// #$41 -> 'A'
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('Caption = #$41');
  try
    Assert.AreEqual(tkString, Toks[2].Kind);
    Assert.AreEqual('A',      Toks[2].Value);
  finally
    Toks.Free;
  end;
end;

procedure TTestDfmLexer.Test_String_PlusContinuation_Merges;
// 'foo' + 'bar' -> ein einziges tkString mit 'foobar'
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('Caption = ''foo'' + ''bar''');
  try
    Assert.AreEqual(tkString, Toks[2].Kind);
    Assert.AreEqual('foobar', Toks[2].Value);
    Assert.AreEqual(tkEof,    Toks[3].Kind, 'kein zusätzliches tkPlus oder tkString-Token');
  finally
    Toks.Free;
  end;
end;

procedure TTestDfmLexer.Test_String_LineBreakBetweenSegments_Merges;
// Multi-line mit nur Whitespace zwischen Segmenten:
//   'erste'
//   'zweite'
// (kein '+' nötig in DFM, Pascal-Style-Concat)
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('Caption = ''erste''' + #13#10 + '  ''zweite''');
  try
    Assert.AreEqual(tkString,       Toks[2].Kind);
    Assert.AreEqual('erstezweite',  Toks[2].Value);
  finally
    Toks.Free;
  end;
end;

{ --- Klammer-Blöcke als atomare Tokens --- }

procedure TTestDfmLexer.Test_Set_AsAtomicToken;
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('Style = [fsBold, fsItalic]');
  try
    Assert.AreEqual(tkSet,                 Toks[2].Kind);
    Assert.AreEqual('[fsBold, fsItalic]',  Toks[2].Value);
  finally
    Toks.Free;
  end;
end;

procedure TTestDfmLexer.Test_Binary_AsAtomicToken_EmptyValue;
// Inhalt wird verworfen, nur Position/Kind zählt.
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('Picture.Data = {010203FF}');
  try
    Assert.AreEqual(tkBinary, Toks[4].Kind);
    Assert.AreEqual('',       Toks[4].Value);
  finally
    Toks.Free;
  end;
end;

procedure TTestDfmLexer.Test_ItemList_AsAtomicToken;
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('Columns = <item Width = 100 end>');
  try
    Assert.AreEqual(tkItemList, Toks[2].Kind);
    Assert.AreEqual('<item Width = 100 end>', Toks[2].Value);
  finally
    Toks.Free;
  end;
end;

procedure TTestDfmLexer.Test_ItemList_Nested_DepthCounter;
// Nested <...>-Blöcke - Counter muss korrekt bilanzieren.
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('Cols = <item Sub = <item end> end>');
  try
    Assert.AreEqual(tkItemList, Toks[2].Kind);
    Assert.AreEqual('<item Sub = <item end> end>', Toks[2].Value);
    Assert.AreEqual(tkEof, Toks[3].Kind, 'inneres > darf äußeren Block nicht beenden');
  finally
    Toks.Free;
  end;
end;

procedure TTestDfmLexer.Test_StrList_AsAtomicToken;
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('Lines.Strings = (' + #13#10 + '  ''erste''' + #13#10 + '  ''zweite'')');
  try
    Assert.AreEqual(tkStrList, Toks[4].Kind);
  finally
    Toks.Free;
  end;
end;

{ --- Robustheit: Klammern in Strings dürfen Balance nicht brechen --- }

procedure TTestDfmLexer.Test_BracketCharInString_DoesNotBreakSet;
// Set, der einen String mit ']' enthält - das ']' im String darf
// den Set-Block nicht schließen.
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('X = [''a]b'']');
  try
    Assert.AreEqual(tkSet,         Toks[2].Kind);
    Assert.AreEqual('[''a]b'']',   Toks[2].Value);
    Assert.AreEqual(tkEof,         Toks[3].Kind);
  finally
    Toks.Free;
  end;
end;

procedure TTestDfmLexer.Test_AngleCharInString_DoesNotBreakItemList;
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('X = <item C = ''a>b'' end>');
  try
    Assert.AreEqual(tkItemList, Toks[2].Kind);
    Assert.AreEqual(tkEof,      Toks[3].Kind);
  finally
    Toks.Free;
  end;
end;

procedure TTestDfmLexer.Test_ParenCharInString_DoesNotBreakStrList;
var
  Toks: TList<TDfmToken>;
begin
  Toks := CollectTokens('X = (''a)b'')');
  try
    Assert.AreEqual(tkStrList, Toks[2].Kind);
    Assert.AreEqual(tkEof,     Toks[3].Kind);
  finally
    Toks.Free;
  end;
end;

{ --- Realer DFM-Schnipsel --- }

procedure TTestDfmLexer.Test_RealisticFormStub_NoUnknownTokens;
// Misch-DFM mit allen Konstrukten - keinerlei tkUnknown darf rauskommen.
const
  SRC =
    'object Form2: TForm2'#13#10 +
    '  Left = 0'#13#10 +
    '  Top = 0'#13#10 +
    '  Caption = ''Static Code Analysis Tool''' + #13#10 +
    '  ClientHeight = 600'#13#10 +
    '  ClientWidth = 800'#13#10 +
    '  Color = clBtnFace'#13#10 +
    '  Font.Charset = DEFAULT_CHARSET'#13#10 +
    '  Font.Color = clWindowText'#13#10 +
    '  Font.Height = -11'#13#10 +
    '  Font.Name = ''Segoe UI'''#13#10 +
    '  Font.Style = []'#13#10 +
    '  PixelsPerInch = 96'#13#10 +
    '  TextHeight = 13'#13#10 +
    '  object pnlTop: TPanel'#13#10 +
    '    Left = 0'#13#10 +
    '    Top = 0'#13#10 +
    '    Width = 800'#13#10 +
    '    Height = 41'#13#10 +
    '    Align = alTop'#13#10 +
    '    Caption = ''pnlTop'''#13#10 +
    '    TabOrder = 0'#13#10 +
    '    object btnGo: TButton'#13#10 +
    '      Left = 10'#13#10 +
    '      Top = 8'#13#10 +
    '      Width = 75'#13#10 +
    '      Height = 25'#13#10 +
    '      Caption = ''Go'''#13#10 +
    '      TabOrder = 0'#13#10 +
    '      OnClick = btnGoClick'#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    '  object Memo1: TMemo'#13#10 +
    '    Left = 0'#13#10 +
    '    Top = 41'#13#10 +
    '    Lines.Strings = ('#13#10 +
    '      ''Memo1'''#13#10 +
    '      ''Zweite Zeile'')'#13#10 +
    '    TabOrder = 1'#13#10 +
    '  end'#13#10 +
    'end';
var
  Toks: TList<TDfmToken>;
  ObjectCount, EndCount, UnknownCount, I: Integer;
begin
  Toks := CollectTokens(SRC);
  try
    ObjectCount  := 0;
    EndCount     := 0;
    UnknownCount := 0;
    for I := 0 to Toks.Count - 1 do
    begin
      case Toks[I].Kind of
        tkKwObject: Inc(ObjectCount);
        tkKwEnd:    Inc(EndCount);
        tkUnknown:  Inc(UnknownCount);
      end;
    end;
    // Quelle enthält Form2 / pnlTop / btnGo / Memo1 = 4 object-Header,
    // dazu jeweils ein end -> 4 / 4.
    Assert.AreEqual(4, ObjectCount, 'Form2/pnlTop/btnGo/Memo1 = 4 object-Header');
    Assert.AreEqual(4, EndCount,    'gleiche Anzahl end');
    Assert.AreEqual(0, UnknownCount, 'keinerlei unerkanntes Token');
  finally
    Toks.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmLexer);

end.

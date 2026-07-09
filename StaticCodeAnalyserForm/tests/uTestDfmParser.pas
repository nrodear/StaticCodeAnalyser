unit uTestDfmParser;

// Smoke-Tests für uDfmParser + uComponentGraph - Phase 1 Walking-Skeleton.
// Fokus: Hierarchie korrekt aufgebaut, Properties sauber überlesen,
// Inherited/Inline-Flags gesetzt, robust gegen die typischen DFM-Konstrukte
// (Multi-Line-Strings, Sets, ItemListen, Binär-Blobs).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmParser = class
  public
    // --- Hierarchie ---
    [Test] procedure Test_Empty_NoRoots;
    [Test] procedure Test_SingleObject_BuildsRoot;
    [Test] procedure Test_NestedHierarchy_BuildsTree;
    [Test] procedure Test_TwoSiblings_BuildsSiblings;
    [Test] procedure Test_DeepNesting_BuildsCorrectTree;

    // --- Inherited / Inline ---
    [Test] procedure Test_InheritedObject_FlagSet;
    [Test] procedure Test_InlineObject_FlagSet;
    [Test] procedure Test_PlainObject_FlagsAreFalse;

    // --- Properties werden übersprungen ---
    [Test] procedure Test_PropertyAssignments_SkippedNotInGraph;
    [Test] procedure Test_QualifiedProperty_Skipped;
    [Test] procedure Test_StrList_ValueSkipped_NextSiblingStillParsed;
    [Test] procedure Test_ItemList_ValueSkipped;
    [Test] procedure Test_Binary_ValueSkipped;
    [Test] procedure Test_NegativeNumber_Skipped;

    // --- Position-Info am Knoten ---
    [Test] procedure Test_LineNumber_IsObjectHeaderLine;

    // --- Realer DFM-Stub ---
    [Test] procedure Test_RealisticFormStub_HierarchyCorrect;

    // --- Graph-API ---
    [Test] procedure Test_EnumerateAll_DepthFirstOrder;
    [Test] procedure Test_FindByName_FindsNested;
    [Test] procedure Test_FindByName_CaseInsensitive;
    [Test] procedure Test_FindByName_NotFound_ReturnsNil;

    // --- Property-Capture (Iteration 2) ---
    [Test] procedure Test_Property_StringValue_CapturedWithKindAndRaw;
    [Test] procedure Test_Property_IntegerValue_CapturedAsInteger;
    [Test] procedure Test_Property_NegativeInteger_RawValueIncludesSign;
    [Test] procedure Test_Property_FloatValue_CapturedAsFloat;
    [Test] procedure Test_Property_BooleanValue_CapturedAsBool;
    [Test] procedure Test_Property_IdentValue_CapturedAsIdent;
    [Test] procedure Test_Property_SetValue_RawIncludesBrackets;
    [Test] procedure Test_Property_StrListValue_CapturedAsStrList;
    [Test] procedure Test_Property_ItemListValue_CapturedAsItemList;
    [Test] procedure Test_Property_BinaryValue_KindOnly_RawEmpty;
    [Test] procedure Test_Property_QualifiedPath_KeyKeepsDots;
    [Test] procedure Test_Property_LookupCaseInsensitive;
    [Test] procedure Test_Property_MultilineString_MergedByLexer;
    [Test] procedure Test_Property_OnFormAndChild_BothCaptured;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  uDfmParser,
  uComponentGraph;

function ParseToGraph(const Src: string): TComponentGraph;
var
  Parser: TDfmParser;
begin
  Parser := TDfmParser.Create;
  try
    Result := Parser.ParseSource(Src);
  finally
    Parser.Free;
  end;
end;

{ --- Hierarchie --- }

procedure TTestDfmParser.Test_Empty_NoRoots;
var
  G: TComponentGraph;
begin
  G := ParseToGraph('');
  try
    Assert.AreEqual<Integer>(0, G.Roots.Count);
  finally
    G.Free;
  end;
end;

procedure TTestDfmParser.Test_SingleObject_BuildsRoot;
var
  G: TComponentGraph;
begin
  G := ParseToGraph('object Form2: TForm2'#13#10'end');
  try
    Assert.AreEqual<Integer>(1,         G.Roots.Count);
    Assert.AreEqual('Form2',   G.Roots[0].Name);
    Assert.AreEqual('TForm2',  G.Roots[0].ClassRef);
    Assert.AreEqual<Integer>(0,         G.Roots[0].Children.Count);
  finally
    G.Free;
  end;
end;

procedure TTestDfmParser.Test_NestedHierarchy_BuildsTree;
var
  G    : TComponentGraph;
  Root : TComponentNode;
  Btn  : TComponentNode;
begin
  G := ParseToGraph(
    'object Form2: TForm2'#13#10 +
    '  object Btn1: TButton'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, G.Roots.Count);
    Root := G.Roots[0];
    Assert.AreEqual('Form2', Root.Name);
    Assert.AreEqual<Integer>(1, Root.Children.Count);
    Btn := Root.Children[0];
    Assert.AreEqual('Btn1',    Btn.Name);
    Assert.AreEqual('TButton', Btn.ClassRef);
    Assert.AreSame(Root, Btn.Parent);
  finally
    G.Free;
  end;
end;

procedure TTestDfmParser.Test_TwoSiblings_BuildsSiblings;
var
  G   : TComponentGraph;
  Root: TComponentNode;
begin
  G := ParseToGraph(
    'object Form2: TForm2'#13#10 +
    '  object A: TPanel'#13#10 +
    '  end'#13#10 +
    '  object B: TPanel'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Root := G.Roots[0];
    Assert.AreEqual<Integer>(2,   Root.Children.Count);
    Assert.AreEqual('A', Root.Children[0].Name);
    Assert.AreEqual('B', Root.Children[1].Name);
  finally
    G.Free;
  end;
end;

procedure TTestDfmParser.Test_DeepNesting_BuildsCorrectTree;
var
  G : TComponentGraph;
  N : TComponentNode;
begin
  G := ParseToGraph(
    'object L0: TForm'#13#10 +
    '  object L1: TPanel'#13#10 +
    '    object L2: TPanel'#13#10 +
    '      object L3: TLabel'#13#10 +
    '      end'#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    'end');
  try
    N := G.Roots[0];
    Assert.AreEqual('L0', N.Name);
    Assert.AreEqual('L1', N.Children[0].Name);
    Assert.AreEqual('L2', N.Children[0].Children[0].Name);
    Assert.AreEqual('L3', N.Children[0].Children[0].Children[0].Name);
  finally
    G.Free;
  end;
end;

{ --- Inherited / Inline --- }

procedure TTestDfmParser.Test_InheritedObject_FlagSet;
var
  G: TComponentGraph;
begin
  G := ParseToGraph('inherited Form2: TForm2'#13#10'end');
  try
    Assert.IsTrue (G.Roots[0].IsInherited);
    Assert.IsFalse(G.Roots[0].IsInline);
  finally
    G.Free;
  end;
end;

procedure TTestDfmParser.Test_InlineObject_FlagSet;
var
  G: TComponentGraph;
begin
  G := ParseToGraph('inline Frame1: TFrame1'#13#10'end');
  try
    Assert.IsFalse(G.Roots[0].IsInherited);
    Assert.IsTrue (G.Roots[0].IsInline);
  finally
    G.Free;
  end;
end;

procedure TTestDfmParser.Test_PlainObject_FlagsAreFalse;
var
  G: TComponentGraph;
begin
  G := ParseToGraph('object Form2: TForm2 end');
  try
    Assert.IsFalse(G.Roots[0].IsInherited);
    Assert.IsFalse(G.Roots[0].IsInline);
  finally
    G.Free;
  end;
end;

{ --- Properties werden übersprungen --- }

procedure TTestDfmParser.Test_PropertyAssignments_SkippedNotInGraph;
// Mehrere triviale Properties dürfen die Hierarchie nicht stören.
var
  G   : TComponentGraph;
  Root: TComponentNode;
begin
  G := ParseToGraph(
    'object Form2: TForm2'#13#10 +
    '  Left = 0'#13#10 +
    '  Top = 0'#13#10 +
    '  Caption = ''Test'''#13#10 +
    '  Visible = True'#13#10 +
    'end');
  try
    Root := G.Roots[0];
    Assert.AreEqual('Form2', Root.Name);
    Assert.AreEqual<Integer>(0,       Root.Children.Count, 'Properties dürfen nicht als Children erscheinen');
  finally
    G.Free;
  end;
end;

procedure TTestDfmParser.Test_QualifiedProperty_Skipped;
// Font.Charset, Font.Style etc. müssen sauber überlesen werden.
var
  G   : TComponentGraph;
  Root: TComponentNode;
begin
  G := ParseToGraph(
    'object Form2: TForm2'#13#10 +
    '  Font.Charset = DEFAULT_CHARSET'#13#10 +
    '  Font.Color = clWindowText'#13#10 +
    '  Font.Height = -11'#13#10 +
    '  Font.Style = []'#13#10 +
    '  object Btn: TButton'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Root := G.Roots[0];
    Assert.AreEqual<Integer>(1,     Root.Children.Count);
    Assert.AreEqual('Btn', Root.Children[0].Name);
  finally
    G.Free;
  end;
end;

procedure TTestDfmParser.Test_StrList_ValueSkipped_NextSiblingStillParsed;
// Multi-Line-String-Liste als Property-Wert - der ')'-Token darf den
// Parser nicht aus dem aktuellen Object werfen.
var
  G   : TComponentGraph;
  Root: TComponentNode;
begin
  G := ParseToGraph(
    'object Form2: TForm2'#13#10 +
    '  object Memo1: TMemo'#13#10 +
    '    Lines.Strings = ('#13#10 +
    '      ''a'''#13#10 +
    '      ''b'')'#13#10 +
    '    TabOrder = 0'#13#10 +
    '  end'#13#10 +
    '  object Memo2: TMemo'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Root := G.Roots[0];
    Assert.AreEqual<Integer>(2,       Root.Children.Count);
    Assert.AreEqual('Memo1', Root.Children[0].Name);
    Assert.AreEqual('Memo2', Root.Children[1].Name);
  finally
    G.Free;
  end;
end;

procedure TTestDfmParser.Test_ItemList_ValueSkipped;
// <item ... end> als Property-Wert.
var
  G   : TComponentGraph;
  Root: TComponentNode;
begin
  G := ParseToGraph(
    'object Form2: TForm2'#13#10 +
    '  object Grid1: TGrid'#13#10 +
    '    Columns = <item Width = 100 end item Width = 200 end>'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Root := G.Roots[0];
    Assert.AreEqual<Integer>(1,        Root.Children.Count);
    Assert.AreEqual('Grid1',  Root.Children[0].Name);
  finally
    G.Free;
  end;
end;

procedure TTestDfmParser.Test_Binary_ValueSkipped;
var
  G   : TComponentGraph;
  Root: TComponentNode;
begin
  G := ParseToGraph(
    'object Form2: TForm2'#13#10 +
    '  object Img1: TImage'#13#10 +
    '    Picture.Data = {01020304FF}'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Root := G.Roots[0];
    Assert.AreEqual('Img1', Root.Children[0].Name);
  finally
    G.Free;
  end;
end;

procedure TTestDfmParser.Test_NegativeNumber_Skipped;
// 'Top = -1' - tkMinus + tkInteger als zwei Tokens, müssen beide
// als Property-Wert (gleiche Zeile) konsumiert werden.
var
  G   : TComponentGraph;
  Root: TComponentNode;
begin
  G := ParseToGraph(
    'object Form2: TForm2'#13#10 +
    '  Top = -1'#13#10 +
    '  Left = -2'#13#10 +
    '  object Btn: TButton'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Root := G.Roots[0];
    Assert.AreEqual<Integer>(1,     Root.Children.Count);
    Assert.AreEqual('Btn', Root.Children[0].Name);
  finally
    G.Free;
  end;
end;

{ --- Position-Info am Knoten --- }

procedure TTestDfmParser.Test_LineNumber_IsObjectHeaderLine;
var
  G   : TComponentGraph;
  Root: TComponentNode;
  Btn : TComponentNode;
begin
  G := ParseToGraph(
    'object Form2: TForm2'#13#10 +       // Zeile 1
    '  Caption = ''Hi'''#13#10 +         // Zeile 2
    '  object Btn: TButton'#13#10 +      // Zeile 3
    '  end'#13#10 +
    'end');
  try
    Root := G.Roots[0];
    Btn  := Root.Children[0];
    Assert.AreEqual<Integer>(1, Root.Line, 'Root-Objekt-Header in Zeile 1');
    Assert.AreEqual<Integer>(3, Btn.Line,  'Btn-Objekt-Header in Zeile 3');
  finally
    G.Free;
  end;
end;

{ --- Realer DFM-Stub --- }

procedure TTestDfmParser.Test_RealisticFormStub_HierarchyCorrect;
const
  SRC =
    'object Form2: TForm2'#13#10 +
    '  Left = 0'#13#10 +
    '  Top = 0'#13#10 +
    '  Caption = ''Static Code Analysis Tool'''#13#10 +
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
    '    Align = alTop'#13#10 +
    '    Caption = ''pnlTop'''#13#10 +
    '    TabOrder = 0'#13#10 +
    '    object btnGo: TButton'#13#10 +
    '      Caption = ''Go'''#13#10 +
    '      OnClick = btnGoClick'#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    '  object Memo1: TMemo'#13#10 +
    '    Lines.Strings = ('#13#10 +
    '      ''Memo1'''#13#10 +
    '      ''Zweite Zeile'')'#13#10 +
    '    TabOrder = 1'#13#10 +
    '  end'#13#10 +
    'end';
var
  G    : TComponentGraph;
  Root : TComponentNode;
  All  : TList<TComponentNode>;
begin
  G := ParseToGraph(SRC);
  try
    Assert.AreEqual<Integer>(1, G.Roots.Count);
    Root := G.Roots[0];
    Assert.AreEqual('Form2', Root.Name);
    Assert.AreEqual<Integer>(2, Root.Children.Count, 'pnlTop + Memo1 als direkte Children');
    Assert.AreEqual('pnlTop', Root.Children[0].Name);
    Assert.AreEqual('Memo1',  Root.Children[1].Name);
    Assert.AreEqual<Integer>(1, Root.Children[0].Children.Count, 'btnGo unter pnlTop');
    Assert.AreEqual('btnGo', Root.Children[0].Children[0].Name);

    All := G.EnumerateAll;
    try
      Assert.AreEqual<Integer>(4, All.Count, 'Form2, pnlTop, btnGo, Memo1');
    finally
      All.Free;
    end;
  finally
    G.Free;
  end;
end;

{ --- Graph-API --- }

procedure TTestDfmParser.Test_EnumerateAll_DepthFirstOrder;
var
  G   : TComponentGraph;
  All : TList<TComponentNode>;
begin
  G := ParseToGraph(
    'object A: TPanel'#13#10 +
    '  object B: TPanel'#13#10 +
    '    object C: TPanel'#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    '  object D: TPanel'#13#10 +
    '  end'#13#10 +
    'end');
  try
    All := G.EnumerateAll;
    try
      Assert.AreEqual<Integer>(4,   All.Count);
      Assert.AreEqual('A', All[0].Name);
      Assert.AreEqual('B', All[1].Name);
      Assert.AreEqual('C', All[2].Name);
      Assert.AreEqual('D', All[3].Name);
    finally
      All.Free;
    end;
  finally
    G.Free;
  end;
end;

procedure TTestDfmParser.Test_FindByName_FindsNested;
var
  G : TComponentGraph;
  N : TComponentNode;
begin
  G := ParseToGraph(
    'object Form2: TForm2'#13#10 +
    '  object Outer: TPanel'#13#10 +
    '    object Inner: TButton'#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    'end');
  try
    N := G.FindByName('Inner');
    Assert.IsNotNull(N);
    Assert.AreEqual('TButton', N.ClassRef);
  finally
    G.Free;
  end;
end;

procedure TTestDfmParser.Test_FindByName_CaseInsensitive;
var
  G : TComponentGraph;
begin
  G := ParseToGraph('object Form2: TForm2 end');
  try
    Assert.IsNotNull(G.FindByName('form2'));
    Assert.IsNotNull(G.FindByName('FORM2'));
  finally
    G.Free;
  end;
end;

procedure TTestDfmParser.Test_FindByName_NotFound_ReturnsNil;
var
  G: TComponentGraph;
begin
  G := ParseToGraph('object Form2: TForm2 end');
  try
    Assert.IsNull(G.FindByName('Nope'));
  finally
    G.Free;
  end;
end;

{ --- Property-Capture (Iteration 2) --- }

procedure TTestDfmParser.Test_Property_StringValue_CapturedWithKindAndRaw;
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph('object Form2: TForm2 Caption = ''Hallo'' end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('Caption', V));
    Assert.AreEqual(pvkString, V.Kind);
    Assert.AreEqual('Hallo',   V.RawValue);
  finally G.Free; end;
end;

procedure TTestDfmParser.Test_Property_IntegerValue_CapturedAsInteger;
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph('object Form2: TForm2 Top = 42 end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('Top', V));
    Assert.AreEqual(pvkInteger, V.Kind);
    Assert.AreEqual('42',       V.RawValue);
  finally G.Free; end;
end;

procedure TTestDfmParser.Test_Property_NegativeInteger_RawValueIncludesSign;
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph('object Form2: TForm2 Top = -1 end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('Top', V));
    Assert.AreEqual(pvkInteger, V.Kind);
    Assert.AreEqual('-1',       V.RawValue);
  finally G.Free; end;
end;

procedure TTestDfmParser.Test_Property_FloatValue_CapturedAsFloat;
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph('object Form2: TForm2 Ratio = 1.5 end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('Ratio', V));
    Assert.AreEqual(pvkFloat, V.Kind);
    Assert.AreEqual('1.5',    V.RawValue);
  finally G.Free; end;
end;

procedure TTestDfmParser.Test_Property_BooleanValue_CapturedAsBool;
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph('object Form2: TForm2 Visible = True Enabled = False end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('Visible', V));
    Assert.AreEqual(pvkBool, V.Kind);
    Assert.AreEqual('True',  V.RawValue);
    Assert.IsTrue(G.Roots[0].TryGetProperty('Enabled', V));
    Assert.AreEqual('False', V.RawValue);
  finally G.Free; end;
end;

procedure TTestDfmParser.Test_Property_IdentValue_CapturedAsIdent;
// clRed, alTop, DEFAULT_CHARSET, Btn1Click ... alles als Ident gespeichert.
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph('object Form2: TForm2 Color = clBtnFace end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('Color', V));
    Assert.AreEqual(pvkIdent,  V.Kind);
    Assert.AreEqual('clBtnFace', V.RawValue);
  finally G.Free; end;
end;

procedure TTestDfmParser.Test_Property_SetValue_RawIncludesBrackets;
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph('object Form2: TForm2 Font.Style = [fsBold, fsItalic] end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('Font.Style', V));
    Assert.AreEqual(pvkSet,                V.Kind);
    Assert.AreEqual('[fsBold, fsItalic]',  V.RawValue);
  finally G.Free; end;
end;

procedure TTestDfmParser.Test_Property_StrListValue_CapturedAsStrList;
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph(
    'object Memo: TMemo'#13#10 +
    '  Lines.Strings = ('#13#10 +
    '    ''a'''#13#10 +
    '    ''b'')'#13#10 +
    'end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('Lines.Strings', V));
    Assert.AreEqual(pvkStrList, V.Kind);
    Assert.Contains(V.RawValue, '''a''');
    Assert.Contains(V.RawValue, '''b''');
  finally G.Free; end;
end;

procedure TTestDfmParser.Test_Property_ItemListValue_CapturedAsItemList;
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph(
    'object Grid: TGrid Columns = <item Width = 100 end> end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('Columns', V));
    Assert.AreEqual(pvkItemList, V.Kind);
    Assert.Contains(V.RawValue, 'item');
  finally G.Free; end;
end;

procedure TTestDfmParser.Test_Property_BinaryValue_KindOnly_RawEmpty;
// Lexer verwirft Binary-Inhalt. Detektoren brauchen i.d.R. nur die Existenz
// (z.B. um Picture.Data zu erkennen) - der Inhalt ist binaer.
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph(
    'object Img: TImage Picture.Data = {01020304FF} end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('Picture.Data', V));
    Assert.AreEqual(pvkBinary, V.Kind);
    Assert.AreEqual('',        V.RawValue);
  finally G.Free; end;
end;

procedure TTestDfmParser.Test_Property_QualifiedPath_KeyKeepsDots;
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph(
    'object Form2: TForm2'#13#10 +
    '  Font.Charset = DEFAULT_CHARSET'#13#10 +
    '  Font.Height = -11'#13#10 +
    '  Font.Name = ''Segoe UI'''#13#10 +
    'end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('Font.Charset', V));
    Assert.AreEqual('DEFAULT_CHARSET', V.RawValue);
    Assert.IsTrue(G.Roots[0].TryGetProperty('Font.Height', V));
    Assert.AreEqual('-11',             V.RawValue);
    Assert.IsTrue(G.Roots[0].TryGetProperty('Font.Name', V));
    Assert.AreEqual('Segoe UI',        V.RawValue);
  finally G.Free; end;
end;

procedure TTestDfmParser.Test_Property_LookupCaseInsensitive;
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph('object Form2: TForm2 Caption = ''Hi'' end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('caption', V),    'caption');
    Assert.IsTrue(G.Roots[0].TryGetProperty('CAPTION', V),    'CAPTION');
    Assert.IsTrue(G.Roots[0].TryGetProperty('CaPtIoN', V),    'CaPtIoN');
    Assert.AreEqual('Hi', V.RawValue);
  finally G.Free; end;
end;

procedure TTestDfmParser.Test_Property_MultilineString_MergedByLexer;
// 'foo' + 'bar' ueber zwei Zeilen -> Lexer merged zu einem tkString.
// Property-Capture muss den gemergten Wert speichern.
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph(
    'object Form2: TForm2'#13#10 +
    '  Caption = ''foo'' +'#13#10 +
    '    ''bar'''#13#10 +
    'end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('Caption', V));
    Assert.AreEqual('foobar', V.RawValue);
  finally G.Free; end;
end;

procedure TTestDfmParser.Test_Property_OnFormAndChild_BothCaptured;
var
  G   : TComponentGraph;
  V   : TPropValue;
  Btn : TComponentNode;
begin
  G := ParseToGraph(
    'object Form2: TForm2'#13#10 +
    '  Caption = ''Form'''#13#10 +
    '  object Btn: TButton'#13#10 +
    '    Caption = ''Click'''#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('Caption', V));
    Assert.AreEqual('Form', V.RawValue);
    Btn := G.Roots[0].Children[0];
    Assert.IsTrue(Btn.TryGetProperty('Caption', V));
    Assert.AreEqual('Click', V.RawValue);
  finally G.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmParser);

end.

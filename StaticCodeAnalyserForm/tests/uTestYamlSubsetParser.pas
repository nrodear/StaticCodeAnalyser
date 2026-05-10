unit uTestYamlSubsetParser;

// Tests fuer den YAML-Subset-Parser. Nur die Konstrukte die wir fuer
// analyser-rules.yml tatsaechlich brauchen.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes,
  uYamlSubsetParser;

type
  [TestFixture]
  TTestYamlSubsetParser = class
  public
    [Test] procedure SimpleMapping_TwoKeys;
    [Test] procedure NestedMapping;
    [Test] procedure SequenceOfStrings;
    [Test] procedure SequenceOfMappings_FullExample;
    [Test] procedure DoubleQuotedValueHandlesEscapes;
    [Test] procedure SingleQuotedValueHandlesDoubledQuote;
    [Test] procedure CommentLines_AreIgnored;
    [Test] procedure InlineCommentAfterValue_IsStripped;
    [Test] procedure BlankLines_AreIgnored;
    [Test] procedure GetBool_AcceptsTrueYesOn1;
    [Test] procedure GetInt_ParsesIntegers;
    [Test] procedure GetSequenceStrings_ReturnsArray;
    [Test] procedure TabIndentation_RaisesError;
  end;

implementation

procedure TTestYamlSubsetParser.SimpleMapping_TwoKeys;
const SRC =
  'name: Alice'#10+
  'age: 30'#10;
var Root: TYamlNode;
begin
  Root := TYamlParser.ParseString(SRC);
  try
    Assert.AreEqual<TYamlNodeKind>(yntMapping, Root.Kind);
    Assert.AreEqual('Alice', Root.GetString('name'));
    Assert.AreEqual('30', Root.GetString('age'));
  finally Root.Free; end;
end;

procedure TTestYamlSubsetParser.NestedMapping;
const SRC =
  'tool:'#10+
  '  name: SCA'#10+
  '  version: 0.8.0'#10;
var Root, Tool: TYamlNode;
begin
  Root := TYamlParser.ParseString(SRC);
  try
    Tool := Root.GetChild('tool');
    Assert.IsNotNull(Tool, 'tool muss vorhanden sein');
    Assert.AreEqual<TYamlNodeKind>(yntMapping, Tool.Kind);
    Assert.AreEqual('SCA',   Tool.GetString('name'));
    Assert.AreEqual('0.8.0', Tool.GetString('version'));
  finally Root.Free; end;
end;

procedure TTestYamlSubsetParser.SequenceOfStrings;
const SRC =
  'tags:'#10+
  '  - memory'#10+
  '  - security'#10+
  '  - sql'#10;
var Root, Seq: TYamlNode;
begin
  Root := TYamlParser.ParseString(SRC);
  try
    Seq := Root.GetChild('tags');
    Assert.AreEqual<TYamlNodeKind>(yntSequence, Seq.Kind);
    Assert.AreEqual<Integer>(3, Seq.ItemCount);
    Assert.AreEqual('memory',   Seq.GetItem(0).Value);
    Assert.AreEqual('security', Seq.GetItem(1).Value);
    Assert.AreEqual('sql',      Seq.GetItem(2).Value);
  finally Root.Free; end;
end;

procedure TTestYamlSubsetParser.SequenceOfMappings_FullExample;
// Real-world Pattern: rules-Liste mit jeweils mehreren Feldern.
const SRC =
  'rules:'#10+
  '  - id: PROJ001'#10+
  '    severity: error'#10+
  '    pattern: "TADOQuery"'#10+
  '  - id: PROJ002'#10+
  '    severity: warning'#10+
  '    pattern: "Sleep("'#10;
var Root, Rules, R0, R1: TYamlNode;
begin
  Root := TYamlParser.ParseString(SRC);
  try
    Rules := Root.GetChild('rules');
    Assert.AreEqual<TYamlNodeKind>(yntSequence, Rules.Kind);
    Assert.AreEqual<Integer>(2, Rules.ItemCount);
    R0 := Rules.GetItem(0);
    Assert.AreEqual<TYamlNodeKind>(yntMapping, R0.Kind);
    Assert.AreEqual('PROJ001',   R0.GetString('id'));
    Assert.AreEqual('error',     R0.GetString('severity'));
    Assert.AreEqual('TADOQuery', R0.GetString('pattern'));
    R1 := Rules.GetItem(1);
    Assert.AreEqual('PROJ002', R1.GetString('id'));
    Assert.AreEqual('Sleep(',  R1.GetString('pattern'));
  finally Root.Free; end;
end;

procedure TTestYamlSubsetParser.DoubleQuotedValueHandlesEscapes;
const SRC = 'msg: "line1\nline2"'#10;
var Root: TYamlNode;
begin
  Root := TYamlParser.ParseString(SRC);
  try
    Assert.AreEqual('line1'#10'line2', Root.GetString('msg'),
      'Double-quoted: \n soll zu Newline werden');
  finally Root.Free; end;
end;

procedure TTestYamlSubsetParser.SingleQuotedValueHandlesDoubledQuote;
const SRC = 'msg: ''it''''s ok'''#10;
var Root: TYamlNode;
begin
  Root := TYamlParser.ParseString(SRC);
  try
    Assert.AreEqual('it''s ok', Root.GetString('msg'),
      'Single-quoted: '''' wird zu single quote');
  finally Root.Free; end;
end;

procedure TTestYamlSubsetParser.CommentLines_AreIgnored;
const SRC =
  '# This is a comment'#10+
  'name: Alice'#10+
  '# Another comment'#10+
  'age: 30'#10;
var Root: TYamlNode;
begin
  Root := TYamlParser.ParseString(SRC);
  try
    Assert.AreEqual('Alice', Root.GetString('name'));
    Assert.AreEqual('30',    Root.GetString('age'));
  finally Root.Free; end;
end;

procedure TTestYamlSubsetParser.InlineCommentAfterValue_IsStripped;
const SRC = 'name: Alice  # her name'#10;
var Root: TYamlNode;
begin
  Root := TYamlParser.ParseString(SRC);
  try
    Assert.AreEqual('Alice', Root.GetString('name'),
      'Inline-Kommentar nach Whitespace muss entfernt werden');
  finally Root.Free; end;
end;

procedure TTestYamlSubsetParser.BlankLines_AreIgnored;
const SRC =
  ''#10+
  'name: Alice'#10+
  ''#10+
  ''#10+
  'age: 30'#10+
  ''#10;
var Root: TYamlNode;
begin
  Root := TYamlParser.ParseString(SRC);
  try
    Assert.AreEqual('Alice', Root.GetString('name'));
    Assert.AreEqual('30',    Root.GetString('age'));
  finally Root.Free; end;
end;

procedure TTestYamlSubsetParser.GetBool_AcceptsTrueYesOn1;
const SRC =
  'a: true'#10+
  'b: yes'#10+
  'c: on'#10+
  'd: "1"'#10+
  'e: false'#10;
var Root: TYamlNode;
begin
  Root := TYamlParser.ParseString(SRC);
  try
    Assert.IsTrue (Root.GetBool('a'));
    Assert.IsTrue (Root.GetBool('b'));
    Assert.IsTrue (Root.GetBool('c'));
    Assert.IsTrue (Root.GetBool('d'));
    Assert.IsFalse(Root.GetBool('e'));
  finally Root.Free; end;
end;

procedure TTestYamlSubsetParser.GetInt_ParsesIntegers;
const SRC =
  'count: 42'#10+
  'invalid: "abc"'#10;
var Root: TYamlNode;
begin
  Root := TYamlParser.ParseString(SRC);
  try
    Assert.AreEqual<Integer>(42, Root.GetInt('count'));
    Assert.AreEqual<Integer>(99, Root.GetInt('invalid', 99),
      'Parse-Fehler -> Default');
  finally Root.Free; end;
end;

procedure TTestYamlSubsetParser.GetSequenceStrings_ReturnsArray;
const SRC =
  'globs:'#10+
  '  - "*.pas"'#10+
  '  - "*.dpr"'#10;
var Root: TYamlNode;
    Arr : TArray<string>;
begin
  Root := TYamlParser.ParseString(SRC);
  try
    Arr := Root.GetSequenceStrings('globs');
    Assert.AreEqual<Integer>(2, Length(Arr));
    Assert.AreEqual('*.pas', Arr[0]);
    Assert.AreEqual('*.dpr', Arr[1]);
  finally Root.Free; end;
end;

procedure TTestYamlSubsetParser.TabIndentation_RaisesError;
const SRC = 'tool:'#10#9'name: SCA'#10;
begin
  Assert.WillRaise(
    procedure begin TYamlParser.ParseString(SRC).Free end,
    EYamlParseError,
    'Tab-Indentation muss zu EYamlParseError fuehren');
end;

end.

unit uTestDfmQualifiedValue;

// Charge R5 (2026-10-26): qualifizierter Bezeichner als DFM-Property-Wert.
// TWriter schreibt eine Referenz auf die Komponente eines anderen Moduls
// oder eines eingebetteten Frames als 'Besitzer.Name' (PopupMenu =
// dm.Pop). uDfmParser las nur den ersten Bezeichner als Wert, 'Pop' als
// naechsten Property-Namen, und Consume(tkEquals) warf - die GANZE
// Formdatei war verloren (221 von 3.061 Text-Formularen in
// D:\git-sca-realworld, 18 von 1.013 in D:\git-sca-lazarus).
//
// TTestDfmQualifiedValue laeuft auch im FPC-Pruefstand (reine Parser-
// Tests). TTestDfmQualifiedValueDetectors sind die Detektor-Gegenproben
// (Delphi-only, ziehen uMethodd12 und die Detektor-Units).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmQualifiedValue = class
  public
    [Test] procedure DottedValue_FileSurvives_LaterPropertyRead;
    [Test] procedure DottedValue_KeptAsIdentWithFullPath;
    [Test] procedure DottedValue_PositionIsFirstIdent;
    [Test] procedure TwoDots_FullPathKept;
    [Test] procedure DottedValue_LastBeforeEnd_HierarchyIntact;
    [Test] procedure DottedValue_InChild_SiblingsStillParsed;
    [Test] procedure DottedValue_InInheritedForm_ChildrenKept;
    [Test] procedure DotWithoutIdent_ValueEndsAtDot;
    [Test] procedure DotThenIdentOnNextLine_IsNextProperty;
    [Test] procedure PlainIdentValue_Unchanged;
    [Test] procedure QualifiedPropertyName_StillWorks;
    [Test] procedure FloatValue_StaysFloat;
    [Test] procedure ValuelessProperty_NextQualifiedNameNotAdopted;
    [Test] procedure OtherValueForms_AfterDottedValue_AllCaptured;
  end;

  {$IFNDEF FPC}
  [TestFixture]
  TTestDfmQualifiedValueDetectors = class
  public
    [Test] procedure DefaultName_FormWithDottedValue_StillReported;
    [Test] procedure ActionMismatch_DottedAction_Reported;
    [Test] procedure CircularDataSource_DottedDataSet_NoCycle;
  end;
  {$ENDIF}

implementation

uses
  {$IFNDEF FPC}
  System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uDfmDefaultName, uDfmActionMismatch, uDfmCircularDataSource,
  {$ENDIF}
  System.SysUtils,
  uDfmParser,
  uComponentGraph;

const
  CRLF = #13#10;

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

{ TTestDfmQualifiedValue }

procedure TTestDfmQualifiedValue.DottedValue_FileSurvives_LaterPropertyRead;
// Der Befund selbst: vorher warf ParseSource, der Graph war weg.
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph(
    'object F: TF' + CRLF +
    '  PopupMenu = dm.Pop' + CRLF +
    '  Left = 2' + CRLF +
    '  object Button1: TButton' + CRLF +
    '    Left = 1' + CRLF +
    '  end' + CRLF +
    'end');
  try
    Assert.AreEqual<Integer>(1, G.Roots.Count, 'die Wurzel entsteht');
    Assert.AreEqual<Integer>(1, G.Roots[0].Children.Count,
      'das Kind hinter dem Punkt-Wert ist da');
    Assert.IsTrue(G.Roots[0].TryGetProperty('Left', V),
      'die Property hinter dem Punkt-Wert wird gelesen');
    Assert.AreEqual('2', V.RawValue);
  finally G.Free; end;
end;

procedure TTestDfmQualifiedValue.DottedValue_KeptAsIdentWithFullPath;
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph(
    'object F: TF' + CRLF +
    '  PopupMenu = dm.Pop' + CRLF +
    'end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('PopupMenu', V));
    Assert.IsTrue(V.Kind = pvkIdent, 'Referenz bleibt ein Bezeichner-Wert');
    Assert.AreEqual('dm.Pop', V.RawValue, 'voller Pfad im RawValue');
    Assert.AreEqual('dm.Pop', V.AsIdent, 'AsIdent liefert ihn ebenso');
  finally G.Free; end;
end;

procedure TTestDfmQualifiedValue.DottedValue_PositionIsFirstIdent;
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph(
    'object F: TF' + CRLF +
    '  Images = dmShared.Images' + CRLF +
    'end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('Images', V));
    Assert.AreEqual<Integer>(2, V.Line);
    Assert.AreEqual<Integer>(12, V.Col, 'Spalte des ersten Bezeichners');
  finally G.Free; end;
end;

procedure TTestDfmQualifiedValue.TwoDots_FullPathKept;
// Korpus Lazarus: eine Referenz durch zwei Besitzer.
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph(
    'object F: TF' + CRLF +
    '  ActiveControl = Frame1.Panel1.OKButton' + CRLF +
    '  Tag = 5' + CRLF +
    'end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('ActiveControl', V));
    Assert.AreEqual('Frame1.Panel1.OKButton', V.RawValue);
    Assert.IsTrue(G.Roots[0].TryGetProperty('Tag', V));
    Assert.AreEqual('5', V.RawValue);
  finally G.Free; end;
end;

procedure TTestDfmQualifiedValue.DottedValue_LastBeforeEnd_HierarchyIntact;
// Zweite Fehlform im Korpus (8 rw, 1 laz): der Punkt-Wert ist die letzte
// Property vor 'end' - vorher traf Consume(tkEquals) das 'end'.
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph(
    'object F: TF' + CRLF +
    '  object mi1: TMenuItem' + CRLF +
    '    Action = CommandsDataModule.actEditUndo' + CRLF +
    '  end' + CRLF +
    '  object mi2: TMenuItem' + CRLF +
    '  end' + CRLF +
    'end');
  try
    Assert.AreEqual<Integer>(2, G.Roots[0].Children.Count,
      'beide Menuepunkte sind Kinder der Wurzel');
    Assert.IsTrue(G.Roots[0].Children[0].TryGetProperty('Action', V));
    Assert.AreEqual('CommandsDataModule.actEditUndo', V.RawValue);
  finally G.Free; end;
end;

procedure TTestDfmQualifiedValue.DottedValue_InChild_SiblingsStillParsed;
var
  G : TComponentGraph;
begin
  G := ParseToGraph(
    'object F: TF' + CRLF +
    '  object tb: TToolBar' + CRLF +
    '    Images = dmCnSharedImages.Images' + CRLF +
    '    object btn1: TToolButton' + CRLF +
    '    end' + CRLF +
    '  end' + CRLF +
    '  object pnl: TPanel' + CRLF +
    '  end' + CRLF +
    'end');
  try
    Assert.AreEqual<Integer>(2, G.Roots[0].Children.Count);
    Assert.AreEqual<Integer>(1, G.Roots[0].Children[0].Children.Count);
    Assert.AreEqual('pnl', G.Roots[0].Children[1].Name);
  finally G.Free; end;
end;

procedure TTestDfmQualifiedValue.DottedValue_InInheritedForm_ChildrenKept;
var
  G : TComponentGraph;
begin
  G := ParseToGraph(
    'inherited F2: TF2' + CRLF +
    '  inherited tb: TToolBar' + CRLF +
    '    Images = dm.Images' + CRLF +
    '  end' + CRLF +
    '  object lbl: TLabel' + CRLF +
    '  end' + CRLF +
    'end');
  try
    Assert.IsTrue(G.Roots[0].IsInherited);
    Assert.AreEqual<Integer>(2, G.Roots[0].Children.Count);
  finally G.Free; end;
end;

procedure TTestDfmQualifiedValue.DotWithoutIdent_ValueEndsAtDot;
// Degeneriert: ein Punkt ohne Bezeichner dahinter beendet den Wert; der
// Rest der Datei parst weiter wie vorher.
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph(
    'object F: TF' + CRLF +
    '  PopupMenu = dm. 7' + CRLF +
    '  Tag = 3' + CRLF +
    'end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('PopupMenu', V));
    Assert.AreEqual('dm', V.RawValue);
    Assert.IsTrue(G.Roots[0].TryGetProperty('Tag', V));
    Assert.AreEqual('3', V.RawValue);
  finally G.Free; end;
end;

procedure TTestDfmQualifiedValue.DotThenIdentOnNextLine_IsNextProperty;
// Gegenprobe zur Zeilenpruefung in ReadQualifiedTail: der Bezeichner
// hinter einem Punkt am Zeilenende ist der Name der naechsten Property,
// kein Pfadteil (TWriter bricht Bezeichner nie um).
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph(
    'object F: TF' + CRLF +
    '  PopupMenu = dm.' + CRLF +
    '  Tag = 3' + CRLF +
    'end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('PopupMenu', V));
    Assert.AreEqual('dm', V.RawValue);
    Assert.IsTrue(G.Roots[0].TryGetProperty('Tag', V),
      'Tag bleibt eine eigene Property');
    Assert.AreEqual('3', V.RawValue);
  finally G.Free; end;
end;

procedure TTestDfmQualifiedValue.PlainIdentValue_Unchanged;
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph(
    'object F: TF' + CRLF +
    '  Align = alClient' + CRLF +
    '  Color = clBtnFace' + CRLF +
    'end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('Align', V));
    Assert.IsTrue(V.Kind = pvkIdent);
    Assert.AreEqual('alClient', V.RawValue);
    Assert.IsTrue(G.Roots[0].TryGetProperty('Color', V));
    Assert.AreEqual('clBtnFace', V.RawValue);
  finally G.Free; end;
end;

procedure TTestDfmQualifiedValue.QualifiedPropertyName_StillWorks;
// Der Punkt im Property-NAMEN (ParseQualifiedName) bleibt unberuehrt.
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph(
    'object F: TF' + CRLF +
    '  Font.Name = ''Tahoma''' + CRLF +
    '  Font.Style = [fsBold]' + CRLF +
    'end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('Font.Name', V));
    Assert.AreEqual('Tahoma', V.RawValue);
    Assert.IsTrue(G.Roots[0].TryGetProperty('Font.Style', V));
    Assert.IsTrue(V.Kind = pvkSet);
  finally G.Free; end;
end;

procedure TTestDfmQualifiedValue.FloatValue_StaysFloat;
// Der Punkt einer Zahl gehoert dem Lexer (ReadNumber), nicht dem Pfad.
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph(
    'object F: TF' + CRLF +
    '  Value = 1.5E-10' + CRLF +
    '  Tag = 4' + CRLF +
    'end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('Value', V));
    Assert.IsTrue(V.Kind = pvkFloat);
    Assert.AreEqual('1.5E-10', V.RawValue);
    Assert.IsTrue(G.Roots[0].TryGetProperty('Tag', V));
  finally G.Free; end;
end;

procedure TTestDfmQualifiedValue.ValuelessProperty_NextQualifiedNameNotAdopted;
// Eine wertlose Property darf sich weder den Namen noch den Pfad der
// naechsten Property aneignen.
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph(
    'object F: TF' + CRLF +
    '  PopupMenu =' + CRLF +
    '  Font.Name = ''Arial''' + CRLF +
    'end');
  try
    Assert.IsFalse(G.Roots[0].TryGetProperty('PopupMenu', V));
    Assert.IsTrue(G.Roots[0].TryGetProperty('Font.Name', V));
    Assert.AreEqual('Arial', V.RawValue);
  finally G.Free; end;
end;

procedure TTestDfmQualifiedValue.OtherValueForms_AfterDottedValue_AllCaptured;
// Die uebrigen Wertformen (Korpus-Zensus: keine scheitert) hinter einem
// Punkt-Wert: String mit #-Zeichen und '+'-Fortsetzung, Menge, Binaer-
// daten, Collection, Strings-Liste, negative Zahl mit Exponent.
var
  G : TComponentGraph;
  V : TPropValue;
begin
  G := ParseToGraph(
    'object F: TF' + CRLF +
    '  DataSource = dm.ds' + CRLF +
    '  Caption = ''a''#13#10 +' + CRLF +
    '    ''b''' + CRLF +
    '  Anchors = [akLeft, akTop]' + CRLF +
    '  Glyph.Data = {0102FF}' + CRLF +
    '  Columns = <' + CRLF +
    '    item' + CRLF +
    '      Expanded = False' + CRLF +
    '    end>' + CRLF +
    '  Lines.Strings = (' + CRLF +
    '    ''x'')' + CRLF +
    '  Ratio = -2.5E+3' + CRLF +
    'end');
  try
    Assert.IsTrue(G.Roots[0].TryGetProperty('Caption', V));
    Assert.AreEqual('a'#13#10'b', V.RawValue);
    Assert.IsTrue(G.Roots[0].TryGetProperty('Anchors', V));
    Assert.IsTrue(V.Kind = pvkSet);
    Assert.IsTrue(G.Roots[0].TryGetProperty('Glyph.Data', V));
    Assert.IsTrue(V.Kind = pvkBinary);
    Assert.IsTrue(G.Roots[0].TryGetProperty('Columns', V));
    Assert.IsTrue(V.Kind = pvkItemList);
    Assert.IsTrue(G.Roots[0].TryGetProperty('Lines.Strings', V));
    Assert.IsTrue(V.Kind = pvkStrList);
    Assert.IsTrue(G.Roots[0].TryGetProperty('Ratio', V));
    Assert.AreEqual('-2.5E+3', V.RawValue);
  finally G.Free; end;
end;

{$IFNDEF FPC}

{ TTestDfmQualifiedValueDetectors }

type
  TAnalyzeProc = reference to procedure(G: TComponentGraph;
    R: TObjectList<TLeakFinding>);

function RunOn(const Src: string; const Run: TAnalyzeProc): TObjectList<TLeakFinding>;
var
  G : TComponentGraph;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  G := ParseToGraph(Src);
  try
    Run(G, Result);
  finally
    G.Free;
  end;
end;

function CountKind(F: TObjectList<TLeakFinding>; K: TFindingKind): Integer;
var
  X : TLeakFinding;
begin
  Result := 0;
  for X in F do
    if X.Kind = K then Inc(Result);
end;

procedure TTestDfmQualifiedValueDetectors.DefaultName_FormWithDottedValue_StillReported;
// SCA024 meldet auf einem Formular mit Punkt-Wert wieder - vorher fehlte
// das ganze Formular (Korpus realworld: +919 SCA024).
var
  F : TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object F: TF' + CRLF +
    '  PopupMenu = dm.Pop' + CRLF +
    '  object Button1: TButton' + CRLF +
    '  end' + CRLF +
    'end',
    procedure(G: TComponentGraph; R: TObjectList<TLeakFinding>)
    begin
      TDfmDefaultNameDetector.Analyze(G, 'test.dfm', R);
    end);
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkDfmDefaultName));
  finally F.Free; end;
end;

procedure TTestDfmQualifiedValueDetectors.ActionMismatch_DottedAction_Reported;
// Action aus einem Datenmodul UND OnClick: derselbe Widerspruch wie mit
// einer lokalen Action; der Text nennt den vollen Pfad.
var
  F : TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object F: TF' + CRLF +
    '  object b: TButton' + CRLF +
    '    Action = DM.actSave' + CRLF +
    '    OnClick = bClick' + CRLF +
    '  end' + CRLF +
    'end',
    procedure(G: TComponentGraph; R: TObjectList<TLeakFinding>)
    begin
      TDfmActionMismatchDetector.Analyze(G, 'test.dfm', R);
    end);
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkDfmActionMismatch));
    Assert.IsTrue(Pos('Action=DM.actSave', F[0].MissingVar) > 0,
      'Meldung nennt den vollen Pfad: ' + F[0].MissingVar);
  finally F.Free; end;
end;

procedure TTestDfmQualifiedValueDetectors.CircularDataSource_DottedDataSet_NoCycle;
// Gegenprobe: eine Referenz in ein anderes Modul ist keine lokale Kante -
// der Name 'dm.qry' trifft keine Komponente dieses Formulars.
var
  F : TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object F: TF' + CRLF +
    '  object ds: TDataSource' + CRLF +
    '    DataSet = dm.qry' + CRLF +
    '  end' + CRLF +
    '  object qry: TQuery' + CRLF +
    '    DataSource = ds' + CRLF +
    '  end' + CRLF +
    'end',
    procedure(G: TComponentGraph; R: TObjectList<TLeakFinding>)
    begin
      TDfmCircularDataSourceDetector.Analyze(G, 'test.dfm', R);
    end);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkDfmCircularDataSource));
  finally F.Free; end;
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestDfmQualifiedValue);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestDfmQualifiedValueDetectors);
  {$ENDIF}

end.

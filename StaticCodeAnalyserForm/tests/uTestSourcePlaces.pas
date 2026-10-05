unit uTestSourcePlaces;

// Tests fuer uSourcePlaces, den Quellstellen-Dienst
// (Konzept_SourceRefactor_Quellstellen 2026-10-02, Schritte 2 und 3).
//
// Zwei Gruppen:
//   * Dateibasiert: eine Temp-Datei wird geschrieben, geoeffnet und ueber
//     die Primitive befragt - derselbe Weg wie beim Konsumenten.
//   * Baumbasiert: CollectNodesAt auf einem Handbaum, damit Sortierung,
//     Filter und Leerfaelle unabhaengig vom Parser festgepinnt sind.
//
// Erwartete Spalten werden mit Pos() aus der Testzeile berechnet.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSourcePlaces = class
  public
    // ---- Lebenszyklus ----
    [Test] procedure Open_MissingFile_FalseAndClosed;
    [Test] procedure Open_ReadsLines;
    [Test] procedure Close_ResetsEverything;
    [Test] procedure Unopened_PrimitivesAreTotal;

    // ---- P1 / P3 / P4 ueber die Datei ----
    [Test] procedure StatementAt_DescribesStatement;
    [Test] procedure ChainOf_WithMatchingTarget;
    [Test] procedure ChainOf_WithWrongTarget_Nil;
    [Test] procedure CallOf_WithMatchingHead;

    // ---- P2 ueber die Datei (Parser) ----
    [Test] procedure NodesAt_FindsAssignAndCallOnTheirLines;
    [Test] procedure NodesAt_UnknownLine_Empty;
    [Test] procedure NodesAt_ThenChainOf_RoundTrip;

    // ---- P2 auf dem Handbaum ----
    [Test] procedure Collect_NilRoot_Empty;
    [Test] procedure Collect_FiltersKindAndLine;
    [Test] procedure Collect_SortsByColumn;
    [Test] procedure Collect_DeepTree_NoStackOverflow;

    // ---- P6 / P7 ----
    [Test] procedure HashOf_MatchesBuilder;
    [Test] procedure ConditionalRanges_FromMarkers;

    // ---- P4 Argumentliste / P5 uses / P8 Bezeichner ----
    [Test] procedure CallOf_SeveralArguments_FallsBackToArgumentParts;
    [Test] procedure UsesEntries_BySection;
    [Test] procedure CollectUsesEntries_HandTree_SkipsMismatch;
    [Test] procedure IdentifiersIn_SkipsLiteralsHexAndExponent;

    // ---- Vertrag ----
    // (P9 DeclaredTypeOf und die Typaufloesung der Operanden stehen in
    // uTestSourcePlacesTypes - sie brauchen den echten Parser, der
    // FPC-Pruefstand faehrt diese Unit mit einem Stub.)
    [Test] procedure Version_IsOne;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uAstNode, uRefactorInfo, uRefactorInfoBuilder, uSourcePlaces;

const
  SRC_UNIT =
    'unit t; implementation'#13#10 +
    'procedure Foo;'#13#10 +
    'var Name, r: string;'#13#10 +
    'begin'#13#10 +
    '  r := ''Hallo '' + Name + ''!'' + Name;'#13#10 +
    '  Bar(''x'' + Name);'#13#10 +
    'end;'#13#10 +
    'end.';

// Schreibt ASource in eine Temp-Datei und liefert deren Pfad. Der
// Aufrufer loescht sie.
function WriteTemp(const ASource: string): string;
var
  SL : TStringList;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP'))
    + 'sca_places_' + FormatDateTime('hhnnsszzz', Now)
    + IntToStr(Random(1000000)) + '.pas';
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    SL.SaveToFile(Result);
  finally
    SL.Free;
  end;
end;

// Zeile (1-basiert) der ersten Quellzeile, die AMarker enthaelt.
function LineOf(const ASource, AMarker: string): Integer;
var
  SL : TStringList;
  i  : Integer;
begin
  Result := 0;
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    for i := 0 to SL.Count - 1 do
      if Pos(AMarker, SL[i]) > 0 then
        Exit(i + 1);
  finally
    SL.Free;
  end;
end;

function ColOf(const ASource, AMarker: string): Integer;
var
  SL : TStringList;
  i  : Integer;
begin
  Result := 0;
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    for i := 0 to SL.Count - 1 do
      if Pos(AMarker, SL[i]) > 0 then
        Exit(Pos(AMarker, SL[i]));
  finally
    SL.Free;
  end;
end;

{ ---- Lebenszyklus ---- }

procedure TTestSourcePlaces.Open_MissingFile_FalseAndClosed;
var
  P : TSourcePlaces;
begin
  P := TSourcePlaces.Create;
  try
    Assert.IsFalse(P.Open('Z:\gibt\es\nicht\x.pas'));
    Assert.IsFalse(P.IsOpen);
    Assert.AreEqual('', P.FileName);
    Assert.AreEqual<Integer>(0, P.LineCount);
  finally
    P.Free;
  end;
end;

procedure TTestSourcePlaces.Open_ReadsLines;
var
  P    : TSourcePlaces;
  Path : string;
begin
  Path := WriteTemp(SRC_UNIT);
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.Open(Path));
    Assert.IsTrue(P.IsOpen);
    Assert.AreEqual(Path, P.FileName);
    Assert.AreEqual<Integer>(8, P.LineCount);
  finally
    P.Free;
    DeleteFile(Path);
  end;
end;

procedure TTestSourcePlaces.Close_ResetsEverything;
var
  P    : TSourcePlaces;
  Path : string;
begin
  Path := WriteTemp(SRC_UNIT);
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.Open(Path));
    P.Close;
    Assert.IsFalse(P.IsOpen);
    Assert.AreEqual<Integer>(0, P.LineCount);
    Assert.AreEqual<Integer>(0, Length(P.NodesAt(5, [nkAssign])));
  finally
    P.Free;
    DeleteFile(Path);
  end;
end;

procedure TTestSourcePlaces.Unopened_PrimitivesAreTotal;
var
  P : TSourcePlaces;
  S : TRefactorSpan;
begin
  P := TSourcePlaces.Create;
  try
    S := TRefactorSpan.Make(ROLE_STATEMENT, 1, 1, 1, 5);
    Assert.IsFalse(Assigned(P.StatementAt(1, 1)));
    Assert.IsFalse(Assigned(P.ChainOf(1, 1)));
    Assert.IsFalse(Assigned(P.CallOf(1, 1)));
    Assert.AreEqual<Integer>(0, Length(P.NodesAt(1, [nkAssign, nkCall])));
    Assert.AreEqual<Integer>(0, Length(P.CodeViewOf(S)));
    Assert.AreEqual('', P.TextOf(S));
    Assert.AreEqual('', P.HashOf(S));
    Assert.AreEqual<Integer>(0, Length(P.ConditionalRanges));
  finally
    P.Free;
  end;
end;

{ ---- P1 / P3 / P4 ---- }

procedure TTestSourcePlaces.StatementAt_DescribesStatement;
var
  P    : TSourcePlaces;
  Path : string;
  Info : TRefactorInfo;
begin
  Path := WriteTemp(SRC_UNIT);
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.Open(Path));
    Info := P.StatementAt(LineOf(SRC_UNIT, 'r :='), ColOf(SRC_UNIT, 'r :='));
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual('r := ''Hallo '' + Name + ''!'' + Name;',
        P.TextOf(Info.Span));
      Assert.AreEqual<Integer>(LineOf(SRC_UNIT, 'r :=') + 1, Info.InsertLine);
    finally
      Info.Free;
    end;
  finally
    P.Free;
    DeleteFile(Path);
  end;
end;

procedure TTestSourcePlaces.ChainOf_WithMatchingTarget;
var
  P    : TSourcePlaces;
  Path : string;
  Info : TRefactorInfo;
begin
  Path := WriteTemp(SRC_UNIT);
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.Open(Path));
    Info := P.ChainOf(LineOf(SRC_UNIT, 'r :='), ColOf(SRC_UNIT, 'r :='), 'r');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(5, Length(Info.Parts), 'Ziel + vier Terme');
      Assert.AreEqual(ROLE_LITERAL, Info.Parts[1].Role);
      Assert.AreEqual('Name', P.TextOf(Info.Parts[2]));
    finally
      Info.Free;
    end;
  finally
    P.Free;
    DeleteFile(Path);
  end;
end;

procedure TTestSourcePlaces.ChainOf_WithWrongTarget_Nil;
var
  P    : TSourcePlaces;
  Path : string;
begin
  Path := WriteTemp(SRC_UNIT);
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.Open(Path));
    Assert.IsFalse(Assigned(P.ChainOf(LineOf(SRC_UNIT, 'r :='),
      ColOf(SRC_UNIT, 'r :='), 'Other')),
      'die Gegenprobe gegen den Knoten greift');
  finally
    P.Free;
    DeleteFile(Path);
  end;
end;

procedure TTestSourcePlaces.CallOf_WithMatchingHead;
var
  P    : TSourcePlaces;
  Path : string;
  Info : TRefactorInfo;
begin
  Path := WriteTemp(SRC_UNIT);
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.Open(Path));
    Info := P.CallOf(LineOf(SRC_UNIT, 'Bar('), ColOf(SRC_UNIT, 'Bar('), 'Bar');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual('Bar', P.TextOf(Info.Parts[0]));
      Assert.AreEqual<Integer>(3, Length(Info.Parts));
    finally
      Info.Free;
    end;
  finally
    P.Free;
    DeleteFile(Path);
  end;
end;

{ ---- P2 ueber die Datei ---- }

procedure TTestSourcePlaces.NodesAt_FindsAssignAndCallOnTheirLines;
var
  P     : TSourcePlaces;
  Path  : string;
  Nodes : TArray<TNodeRef>;
begin
  Path := WriteTemp(SRC_UNIT);
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.Open(Path));
    Nodes := P.NodesAt(LineOf(SRC_UNIT, 'r :='), [nkAssign]);
    Assert.AreEqual<Integer>(1, Length(Nodes), 'eine Zuweisung auf der Zeile');
    Assert.IsTrue(Nodes[0].Kind = nkAssign);
    Assert.AreEqual('r', Nodes[0].Name);
    Assert.AreEqual<Integer>(ColOf(SRC_UNIT, 'r :='), Nodes[0].Col);

    Nodes := P.NodesAt(LineOf(SRC_UNIT, 'Bar('), [nkCall]);
    Assert.AreEqual<Integer>(1, Length(Nodes), 'ein Aufruf auf der Zeile');
    Assert.AreEqual<Integer>(1, Pos('Bar', Nodes[0].Name),
      'der Name beginnt mit dem Aufrufkopf');
    Assert.AreEqual<Integer>(ColOf(SRC_UNIT, 'Bar('), Nodes[0].Col);
  finally
    P.Free;
    DeleteFile(Path);
  end;
end;

procedure TTestSourcePlaces.NodesAt_UnknownLine_Empty;
var
  P    : TSourcePlaces;
  Path : string;
begin
  Path := WriteTemp(SRC_UNIT);
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.Open(Path));
    Assert.AreEqual<Integer>(0, Length(P.NodesAt(999, [nkAssign, nkCall])));
    Assert.AreEqual<Integer>(0, Length(P.NodesAt(0, [nkAssign, nkCall])));
    Assert.AreEqual<Integer>(0, Length(P.NodesAt(LineOf(SRC_UNIT, 'r :='), [])));
  finally
    P.Free;
    DeleteFile(Path);
  end;
end;

procedure TTestSourcePlaces.NodesAt_ThenChainOf_RoundTrip;
// Der Weg des Konsumenten: Fund (Zeile) -> Knoten (Spalte, Ziel) ->
// Beschreibung mit Gegenprobe.
var
  P     : TSourcePlaces;
  Path  : string;
  Nodes : TArray<TNodeRef>;
  Info  : TRefactorInfo;
begin
  Path := WriteTemp(SRC_UNIT);
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.Open(Path));
    Nodes := P.NodesAt(LineOf(SRC_UNIT, 'r :='), [nkAssign]);
    Assert.AreEqual<Integer>(1, Length(Nodes));
    Info := P.ChainOf(Nodes[0].Line, Nodes[0].Col, Nodes[0].Name);
    try
      Assert.IsTrue(Assigned(Info), 'Knoten und Quelltext meinen dieselbe Anweisung');
      Assert.AreEqual('r', P.TextOf(Info.Parts[0]));
    finally
      Info.Free;
    end;
  finally
    P.Free;
    DeleteFile(Path);
  end;
end;

{ ---- P2 auf dem Handbaum ---- }

procedure TTestSourcePlaces.Collect_NilRoot_Empty;
begin
  Assert.AreEqual<Integer>(0,
    Length(TSourcePlaces.CollectNodesAt(nil, 1, [nkAssign])));
end;

procedure TTestSourcePlaces.Collect_FiltersKindAndLine;
var
  Root  : TAstNode;
  M     : TAstNode;
  Nodes : TArray<TNodeRef>;
begin
  Root := TAstNode.Create(nkUnit, '', 1, 1);
  try
    M := Root.Add(nkMethod, 'Foo', 2, 1);
    M.Add(nkAssign, 'a', 3, 3).TypeRef := '1';
    M.Add(nkCall,   'Bar(x)', 3, 11);
    M.Add(nkAssign, 'b', 4, 3).TypeRef := '2';
    Nodes := TSourcePlaces.CollectNodesAt(Root, 3, [nkAssign]);
    Assert.AreEqual<Integer>(1, Length(Nodes));
    Assert.AreEqual('a', Nodes[0].Name);
    Assert.AreEqual('1', Nodes[0].TypeRef);
    Nodes := TSourcePlaces.CollectNodesAt(Root, 3, [nkAssign, nkCall]);
    Assert.AreEqual<Integer>(2, Length(Nodes));
    Nodes := TSourcePlaces.CollectNodesAt(Root, 4, [nkCall]);
    Assert.AreEqual<Integer>(0, Length(Nodes));
  finally
    Root.Free;
  end;
end;

procedure TTestSourcePlaces.Collect_SortsByColumn;
var
  Root  : TAstNode;
  Nodes : TArray<TNodeRef>;
begin
  Root := TAstNode.Create(nkUnit, '', 1, 1);
  try
    // bewusst in falscher Reihenfolge angehaengt
    Root.Add(nkAssign, 'c', 7, 30);
    Root.Add(nkAssign, 'a', 7, 3);
    Root.Add(nkAssign, 'b', 7, 15);
    Nodes := TSourcePlaces.CollectNodesAt(Root, 7, [nkAssign]);
    Assert.AreEqual<Integer>(3, Length(Nodes));
    Assert.AreEqual('a', Nodes[0].Name);
    Assert.AreEqual('b', Nodes[1].Name);
    Assert.AreEqual('c', Nodes[2].Name);
  finally
    Root.Free;
  end;
end;

procedure TTestSourcePlaces.Collect_DeepTree_NoStackOverflow;
const
  DEPTH = 20000;
var
  Root, N : TAstNode;
  i       : Integer;
  Nodes   : TArray<TNodeRef>;
begin
  Root := TAstNode.Create(nkUnit, '', 1, 1);
  try
    N := Root;
    for i := 1 to DEPTH do
      N := N.Add(nkMethod, '', i + 1, 1);
    N.Add(nkAssign, 'deep', DEPTH + 5, 1);
    Nodes := TSourcePlaces.CollectNodesAt(Root, DEPTH + 5, [nkAssign]);
    Assert.AreEqual<Integer>(1, Length(Nodes));
    Assert.AreEqual('deep', Nodes[0].Name);
  finally
    Root.Free;
  end;
end;

{ ---- P6 / P7 ---- }

procedure TTestSourcePlaces.HashOf_MatchesBuilder;
var
  P    : TSourcePlaces;
  Path : string;
  Info : TRefactorInfo;
  SL   : TStringList;
begin
  Path := WriteTemp(SRC_UNIT);
  P := TSourcePlaces.Create;
  SL := TStringList.Create;
  try
    Assert.IsTrue(P.Open(Path));
    SL.LoadFromFile(Path);
    Info := P.StatementAt(LineOf(SRC_UNIT, 'r :='), ColOf(SRC_UNIT, 'r :='));
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual(Info.SpanHash, P.HashOf(Info.Span));
      Assert.AreEqual(TRefactorInfoBuilder.HashOfSpan(SL, Info.Span),
        P.HashOf(Info.Span),
        'ein Konsument mit eigener Zeilenliste rechnet denselben Wert');
      Assert.AreEqual<Integer>(1, Length(P.CodeViewOf(Info.Span)));
    finally
      Info.Free;
    end;
  finally
    SL.Free;
    P.Free;
    DeleteFile(Path);
  end;
end;

procedure TTestSourcePlaces.ConditionalRanges_FromMarkers;
const
  SRC =
    'unit t; implementation'#13#10 +
    'procedure Foo;'#13#10 +
    'begin'#13#10 +
    '{$IFDEF X}'#13#10 +
    '  a := 1;'#13#10 +
    '{$ENDIF}'#13#10 +
    'end;'#13#10 +
    'end.';
var
  P      : TSourcePlaces;
  Path   : string;
  Ranges : TArray<TSourceLineRange>;
begin
  Path := WriteTemp(SRC);
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.Open(Path));
    Ranges := P.ConditionalRanges;
    Assert.AreEqual<Integer>(1, Length(Ranges));
    Assert.AreEqual<Integer>(LineOf(SRC, '{$IFDEF'), Ranges[0].StartLine);
    Assert.AreEqual<Integer>(LineOf(SRC, '{$ENDIF'), Ranges[0].EndLine);
  finally
    P.Free;
    DeleteFile(Path);
  end;
end;

{ ---- P4 Argumentliste / P5 uses / P8 Bezeichner ---- }

procedure TTestSourcePlaces.CallOf_SeveralArguments_FallsBackToArgumentParts;
const
  SRC =
    'unit t; implementation'#13#10 +
    'procedure Foo;'#13#10 +
    'begin'#13#10 +
    '  ExecuteFmt(''x %'', [a]);'#13#10 +
    'end;'#13#10 +
    'end.';
var
  P    : TSourcePlaces;
  Path : string;
  Info : TRefactorInfo;
begin
  Path := WriteTemp(SRC);
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.Open(Path));
    Info := P.CallOf(LineOf(SRC, 'ExecuteFmt'), ColOf(SRC, 'ExecuteFmt'),
      'ExecuteFmt');
    try
      Assert.IsTrue(Assigned(Info), 'zwei Argumente: die Argumentliste');
      Assert.AreEqual<Integer>(3, Length(Info.Parts));
      Assert.AreEqual(ROLE_ARGUMENT, Info.Parts[1].Role);
      Assert.AreEqual('[a]', P.TextOf(Info.Parts[2]));
      Assert.IsFalse(Info.FixSafe);
    finally
      Info.Free;
    end;
  finally
    P.Free;
    DeleteFile(Path);
  end;
end;

procedure TTestSourcePlaces.UsesEntries_BySection;
const
  SRC =
    'unit t;'#13#10 +
    'interface'#13#10 +
    'uses'#13#10 +
    '  SysUtils, System.Classes;'#13#10 +
    'implementation'#13#10 +
    'uses Vcl.Forms;'#13#10 +
    'end.';
var
  P       : TSourcePlaces;
  Path    : string;
  Entries : TArray<TRefactorSpan>;
begin
  Path := WriteTemp(SRC);
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.Open(Path));
    Entries := P.UsesEntries(usInterface);
    Assert.AreEqual<Integer>(2, Length(Entries));
    Assert.AreEqual(ROLE_UNIT, Entries[0].Role);
    Assert.AreEqual('SysUtils', P.TextOf(Entries[0]));
    Assert.AreEqual('SysUtils', Entries[0].Resolved);
    Assert.AreEqual('System.Classes', P.TextOf(Entries[1]),
      'der qualifizierte Name ist EIN Eintrag');
    Entries := P.UsesEntries(usImplementation);
    Assert.AreEqual<Integer>(1, Length(Entries));
    Assert.AreEqual('Vcl.Forms', P.TextOf(Entries[0]));
    Assert.AreEqual<Integer>(3, Length(P.UsesEntries(usAny)));
  finally
    P.Free;
    DeleteFile(Path);
  end;
end;

procedure TTestSourcePlaces.CollectUsesEntries_HandTree_SkipsMismatch;
const
  L4 = '  SysUtils, Classes;';
var
  Root, Intf, UsesN : TAstNode;
  Lines   : TStringList;
  Entries : TArray<TRefactorSpan>;
begin
  Lines := TStringList.Create;
  Root  := TAstNode.Create(nkUnit, '', 1, 1);
  try
    Lines.Add('unit t;');
    Lines.Add('interface');
    Lines.Add('uses');
    Lines.Add(L4);
    Intf  := Root.Add(nkInterface, 'interface', 2, 1);
    UsesN := Intf.Add(nkUses, 'uses', 3, 1);
    UsesN.Add(nkUsesItem, 'SysUtils', 4, Pos('SysUtils', L4));
    UsesN.Add(nkUsesItem, 'Classes',  4, Pos('Classes', L4));
    // Knoten, dessen Name nicht zum Quelltext an seiner Position passt:
    // wird ausgelassen statt falsch beschrieben.
    UsesN.Add(nkUsesItem, 'Forms', 4, Pos('SysUtils', L4));
    Entries := TSourcePlaces.CollectUsesEntries(Root, Lines, usInterface);
    Assert.AreEqual<Integer>(2, Length(Entries));
    Assert.AreEqual('SysUtils',
      TRefactorInfoBuilder.SpanText(Lines, Entries[0]));
    Assert.AreEqual('Classes',
      TRefactorInfoBuilder.SpanText(Lines, Entries[1]));
    Assert.AreEqual<Integer>(0,
      Length(TSourcePlaces.CollectUsesEntries(Root, Lines, usImplementation)));
    Assert.AreEqual<Integer>(0,
      Length(TSourcePlaces.CollectUsesEntries(nil, Lines, usAny)));
  finally
    Root.Free;
    Lines.Free;
  end;
end;

procedure TTestSourcePlaces.IdentifiersIn_SkipsLiteralsHexAndExponent;
const
  SRC =
    'unit t; implementation'#13#10 +
    'procedure Foo;'#13#10 +
    'begin'#13#10 +
    '  r := Foo(x1, ''abc'', $FF, 1e5) + #13; // Bar'#13#10 +
    'end;'#13#10 +
    'end.';
var
  P      : TSourcePlaces;
  Path   : string;
  Info   : TRefactorInfo;
  Idents : TArray<TRefactorSpan>;
begin
  Path := WriteTemp(SRC);
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.Open(Path));
    Info := P.StatementAt(LineOf(SRC, 'r :='), ColOf(SRC, 'r :='));
    try
      Assert.IsTrue(Assigned(Info));
      Idents := P.IdentifiersIn(Info.Span);
      Assert.AreEqual<Integer>(3, Length(Idents),
        'r, Foo, x1 - nicht abc, FF, e5, Bar');
      Assert.AreEqual('r',   Idents[0].Resolved);
      Assert.AreEqual('Foo', Idents[1].Resolved);
      Assert.AreEqual('x1',  Idents[2].Resolved);
      Assert.AreEqual(ROLE_IDENT, Idents[1].Role);
      Assert.AreEqual('Foo', P.TextOf(Idents[1]));
    finally
      Info.Free;
    end;
  finally
    P.Free;
    DeleteFile(Path);
  end;
end;

{ ---- Vertrag ---- }

procedure TTestSourcePlaces.Version_IsOne;
begin
  Assert.AreEqual<Integer>(1, SOURCE_PLACES_VERSION);
end;

initialization
  Randomize;
  TDUnitX.RegisterTestFixture(TTestSourcePlaces);

end.

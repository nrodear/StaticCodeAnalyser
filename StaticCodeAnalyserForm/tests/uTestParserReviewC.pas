unit uTestParserReviewC;

// Parser-Befunde aus dem Review Bereich C Engine-Kern (Major 14,
// 2026-10-14): das Phantom-nkField 'strict', die if-Bedingung mit
// verdoppelten Apostrophen und kompaktem Join, der for-Kopf ohne
// Leerzeichen um den Punkt, die Notbremse des Argument-Scanners und die
// Kodierungskette von ParseFile. Dazu Gegenproben, dass die drei
// zusammengefuehrten Sammel-Schleifen (Typname, record-Typ, Inline-
// Initializer) token-identisch geblieben sind.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestParserReviewC = class
  public
    [Test] procedure StrictPrivate_NoPhantomField;
    [Test] procedure IfCondition_QuotesDoubled_AndCompactJoin;
    [Test] procedure ForHeader_DottedMemberWithoutSpaces_KeepsAssignSpacing;
    [Test] procedure ForVar_TypedInlineVariable_Unchanged;
    [Test] procedure ArgumentScanner_UnbalancedParen_StopsAtBlockEnd;
    [Test] procedure ArgumentScanner_AnonymousMethodArgs_Unchanged;
    [Test] procedure ParseFile_Utf8BomWithInvalidByte_NotEmptyTree;
    [Test] procedure InlineVarConst_TypeAndInitializer_Unchanged;
    [Test] procedure RecordFieldType_Balanced_Unchanged;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  System.Generics.Collections,
  uAstNode, uParser2;

function Parse(const ASrc: string): TAstNode;
var
  P : TParser2;
begin
  P := TParser2.Create;
  try
    Result := P.ParseSource(ASrc);
  finally
    P.Free;
  end;
end;

// Erster Knoten der Art AKind mit genau diesem Namen (case-insensitiv);
// nil, wenn keiner.
function NodeNamed(Root: TAstNode; AKind: TNodeKind;
  const AName: string): TAstNode;
var
  L : TList<TAstNode>;
  N : TAstNode;
begin
  Result := nil;
  L := Root.FindAll(AKind);
  try
    for N in L do
      if SameText(N.Name, AName) then Exit(N);
  finally
    L.Free;
  end;
end;

function CountKind(Root: TAstNode; AKind: TNodeKind): Integer;
var
  L : TList<TAstNode>;
begin
  L := Root.FindAll(AKind);
  try
    Result := L.Count;
  finally
    L.Free;
  end;
end;

procedure TTestParserReviewC.StrictPrivate_NoPhantomField;
// 'strict' ist fuer den Lexer ein Bezeichner und lief in den Feld-Pfad:
// je 'strict private'/'strict protected' ein typloses nkField 'strict'
// (817 Stellen im Korpus, zaehlt in SCA138).
const
  SRC =
    'unit s; interface'#13#10 +
    'type'#13#10 +
    '  TFoo = class'#13#10 +
    '  strict private'#13#10 +
    '    FA: Integer;'#13#10 +
    '  strict protected'#13#10 +
    '    FB: string;'#13#10 +
    '  public'#13#10 +
    '    procedure P;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
var
  Root : TAstNode;
begin
  Root := Parse(SRC);
  try
    Assert.AreEqual<Integer>(2, CountKind(Root, nkField),
      'genau FA und FB - kein Phantom-Feld strict');
    Assert.IsNull(NodeNamed(Root, nkField, 'strict'));
    Assert.IsNotNull(NodeNamed(Root, nkField, 'FA'));
    Assert.AreEqual('string', NodeNamed(Root, nkField, 'FB').TypeRef);
    Assert.AreEqual<Integer>(3, CountKind(Root, nkVisibilitySection),
      'strict private, strict protected, public');
  finally
    Root.Free;
  end;
end;

procedure TTestParserReviewC.IfCondition_QuotesDoubled_AndCompactJoin;
// Wie while/case: ein eingebetteter Apostroph steht wieder verdoppelt
// (sonst oeffnete er fuer die Literal-Blanker der Detektoren einen
// falschen String), und 'Obj.Count' bleibt zusammen (vorher 'Obj . Count',
// unsichtbar fuer uSymbolReferenceIndex).
const
  SRC =
    'unit i; interface implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '  if (S = ''it''''s'') and (Obj.Count > 1) then'#13#10 +
    '    X;'#13#10 +
    'end;'#13#10 +
    'end.';
var
  Root : TAstNode;
  L    : TList<TAstNode>;
begin
  Root := Parse(SRC);
  try
    L := Root.FindAll(nkIfStmt);
    try
      Assert.AreEqual<Integer>(1, L.Count);
      Assert.AreEqual('(S=''it''''s'')and(Obj.Count>1)', L[0].TypeRef);
    finally
      L.Free;
    end;
  finally
    Root.Free;
  end;
end;

procedure TTestParserReviewC.ForHeader_DottedMemberWithoutSpaces_KeepsAssignSpacing;
// Der for-Kopf behaelt seine Leerzeichen (uNilDeref prueft 'x := ' und
// 'x in '), nur um den Punkt kommt keines mehr.
const
  SRC =
    'unit f; interface implementation'#13#10 +
    'procedure P;'#13#10 +
    'var i: Integer;'#13#10 +
    'begin'#13#10 +
    '  for i := 0 to List.Count - 1 do'#13#10 +
    '    X;'#13#10 +
    '  for var Item in Owner.Items do'#13#10 +
    '    Y;'#13#10 +
    'end;'#13#10 +
    'end.';
var
  Root : TAstNode;
  L    : TList<TAstNode>;
begin
  Root := Parse(SRC);
  try
    L := Root.FindAll(nkForStmt);
    try
      Assert.AreEqual<Integer>(2, L.Count);
      Assert.AreEqual('i := 0 to List.Count - 1', L[0].TypeRef);
      // Bei 'for var' steht die Variable NICHT im Kopf (sie ist der
      // nkLocalVar-Kindknoten) - wie vor dem Umbau.
      Assert.AreEqual('in Owner.Items', L[1].TypeRef);
      Assert.IsNotNull(NodeNamed(Root, nkLocalVar, 'Item'));
    finally
      L.Free;
    end;
  finally
    Root.Free;
  end;
end;

procedure TTestParserReviewC.ForVar_TypedInlineVariable_Unchanged;
// Gegenprobe zur zusammengefuehrten Typ-Sammelschleife: die Inline-
// Schleifenvariable traegt ihren Typ, der Kopf bleibt wie bisher.
const
  SRC =
    'unit g; interface implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '  for var J: Integer := 0 to 2 do'#13#10 +
    '    X;'#13#10 +
    'end;'#13#10 +
    'end.';
var
  Root : TAstNode;
  V    : TAstNode;
  L    : TList<TAstNode>;
begin
  Root := Parse(SRC);
  try
    V := NodeNamed(Root, nkLocalVar, 'J');
    Assert.IsNotNull(V, 'Inline-Schleifenvariable');
    Assert.AreEqual('Integer', V.TypeRef);
    L := Root.FindAll(nkForStmt);
    try
      // Kopf ab dem Token hinter dem Typ - die Variable traegt der
      // nkLocalVar-Knoten (unveraendertes Verhalten).
      Assert.AreEqual(':= 0 to 2', L[0].TypeRef);
    finally
      L.Free;
    end;
  finally
    Root.Free;
  end;
end;

procedure TTestParserReviewC.ArgumentScanner_UnbalancedParen_StopsAtBlockEnd;
// Eine nie geschlossene Klammer liess den Argument-Scanner bis zum
// Dateiende laufen: Q samt Rumpf verschwand im nkCall-Namen von DoIt.
// Jetzt stoppt er am 'end' ohne offenen Block; Q wird normal geparst.
const
  SRC =
    'unit u; interface implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '  DoIt(1, 2;'#13#10 +
    '  Other;'#13#10 +
    'end;'#13#10 +
    'procedure Q;'#13#10 +
    'begin'#13#10 +
    '  Last;'#13#10 +
    'end;'#13#10 +
    'end.';
var
  Root : TAstNode;
begin
  Root := Parse(SRC);
  try
    Assert.AreEqual<Integer>(2, CountKind(Root, nkMethod), 'P und Q');
    Assert.IsNotNull(NodeNamed(Root, nkCall, 'Last'),
      'der Rumpf von Q ist nach der Notbremse wieder da');
  finally
    Root.Free;
  end;
end;

procedure TTestParserReviewC.ArgumentScanner_AnonymousMethodArgs_Unchanged;
// Die Notbremse darf gueltige Argumente nicht treffen: anonyme Methode
// mit case-Block und ';' in ihrer Parameterliste.
const
  SRC =
    'unit a; interface implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '  List.Sort(TComparer<Integer>.Construct('#13#10 +
    '    function(const A: Integer; const B: Integer): Integer'#13#10 +
    '    begin'#13#10 +
    '      case A of'#13#10 +
    '        1: Result := 0;'#13#10 +
    '      else Result := 1;'#13#10 +
    '      end;'#13#10 +
    '    end));'#13#10 +
    '  After;'#13#10 +
    'end;'#13#10 +
    'end.';
var
  Root  : TAstNode;
  L     : TList<TAstNode>;
  N     : TAstNode;
  Sort  : Boolean;
begin
  Root := Parse(SRC);
  try
    Sort := False;
    L := Root.FindAll(nkCall);
    try
      for N in L do
        if N.Name.StartsWith('List.Sort(') then Sort := True;
    finally
      L.Free;
    end;
    Assert.IsTrue(Sort, 'der Sort-Aufruf mit anonymer Methode als Argument');
    Assert.IsNotNull(NodeNamed(Root, nkCall, 'After'),
      'der Aufruf dahinter ist ein eigener Knoten');
  finally
    Root.Free;
  end;
end;

procedure TTestParserReviewC.ParseFile_Utf8BomWithInvalidByte_NotEmptyTree;
// UTF-8-BOM, dahinter ein ungueltiges Byte: die alte Kette las die Datei
// als UTF-16 - leerer Baum, kein Fund, kein Fehler.
var
  Datei : string;
  P     : TParser2;
  Root  : TAstNode;
begin
  Datei := TPath.Combine(TPath.GetTempPath, 'sca_parser_bom_' +
    TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '') + '.pas');
  TFile.WriteAllBytes(Datei, TBytes.Create($EF, $BB, $BF) +
    TEncoding.ASCII.GetBytes('unit b; interface implementation'#13#10 +
      'procedure P;'#13#10'begin'#13#10'  X; // ') +
    TBytes.Create($C0, $80) +
    TEncoding.ASCII.GetBytes(#13#10'end;'#13#10'end.'));
  P := TParser2.Create;
  try
    Root := P.ParseFile(Datei);
    try
      Assert.IsNotNull(Root);
      Assert.AreEqual<Integer>(1, CountKind(Root, nkMethod),
        'die Routine ist da - kein leerer UTF-16-Baum');
      Assert.IsNotNull(NodeNamed(Root, nkCall, 'X'));
    finally
      Root.Free;
    end;
  finally
    P.Free;
    if TFile.Exists(Datei) then TFile.Delete(Datei);
  end;
end;

procedure TTestParserReviewC.InlineVarConst_TypeAndInitializer_Unchanged;
// Gegenprobe zu den zusammengefuehrten Sammel-Schleifen: Typ und
// Initializer einer Inline-var und einer Inline-const wie vor dem Umbau.
const
  SRC =
    'unit v; interface implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '  var A: Integer := (1 + 2);'#13#10 +
    '  const C: TPoint = (X: 1; Y: 2);'#13#10 +
    '  var S := ''it''''s'';'#13#10 +
    '  Z;'#13#10 +
    'end;'#13#10 +
    'end.';
var
  Root : TAstNode;
  N    : TAstNode;
begin
  Root := Parse(SRC);
  try
    N := NodeNamed(Root, nkLocalVar, 'A');
    Assert.IsNotNull(N);
    Assert.AreEqual('Integer', N.TypeRef);
    N := NodeNamed(Root, nkAssign, 'A');
    Assert.IsNotNull(N, 'Initializer als nkAssign');
    Assert.AreEqual('(1+2)', N.TypeRef);
    N := NodeNamed(Root, nkField, 'C');
    Assert.IsNotNull(N, 'Inline-Konstante als nkField der nkConstSection');
    Assert.AreEqual('TPoint=(X:1;Y:2)', N.TypeRef);
    N := NodeNamed(Root, nkAssign, 'S');
    Assert.IsNotNull(N);
    Assert.AreEqual('''it''''s''', N.TypeRef);
    Assert.IsNotNull(NodeNamed(Root, nkCall, 'Z'),
      'der Scan endet am ; - die Anweisung dahinter bleibt eigen');
  finally
    Root.Free;
  end;
end;

procedure TTestParserReviewC.RecordFieldType_Balanced_Unchanged;
// Gegenprobe zum zusammengefuehrten record-Mini-Parser: der anonyme
// record-Typ eines Feldes wird balanciert gelesen, das Feld danach
// gehoert noch zur Klasse.
const
  SRC =
    'unit r; interface'#13#10 +
    'type'#13#10 +
    '  TR = class'#13#10 +
    '    FCtx: array of record A: Integer; B: TFoo; end;'#13#10 +
    '    FNext: Integer;'#13#10 +
    '    procedure M;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TR.M;'#13#10 +
    'var R: record X: Integer; Y: record Z: Byte; end; end;'#13#10 +
    'begin'#13#10 +
    '  W;'#13#10 +
    'end;'#13#10 +
    'end.';
var
  Root : TAstNode;
  N    : TAstNode;
begin
  Root := Parse(SRC);
  try
    N := NodeNamed(Root, nkField, 'FCtx');
    Assert.IsNotNull(N);
    Assert.IsTrue(N.TypeRef.StartsWith('arrayofrecord'), N.TypeRef);
    Assert.IsTrue(N.TypeRef.EndsWith('end'), N.TypeRef);
    Assert.AreEqual('Integer', NodeNamed(Root, nkField, 'FNext').TypeRef);
    N := NodeNamed(Root, nkLocalVar, 'R');
    Assert.IsNotNull(N, 'lokale Variable mit verschachteltem record-Typ');
    Assert.IsTrue(N.TypeRef.StartsWith('record'), N.TypeRef);
    Assert.IsNotNull(NodeNamed(Root, nkCall, 'W'), 'der Rumpf ist nicht verloren');
  finally
    Root.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestParserReviewC);

end.

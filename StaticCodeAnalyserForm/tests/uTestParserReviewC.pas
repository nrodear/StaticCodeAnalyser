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
    [Test] procedure IfCondition_QuotesDoubled_SpacedForm;
    [Test] procedure ForHeader_DottedMemberWithoutSpaces_KeepsAssignSpacing;
    [Test] procedure ForVar_TypedInlineVariable_Unchanged;
    [Test] procedure ArgumentScanner_UnbalancedParen_StopsAtBlockEnd;
    [Test] procedure ArgumentScanner_AnonymousMethodArgs_Unchanged;
    [Test] procedure ParseFile_Utf8BomWithInvalidByte_NotEmptyTree;
    [Test] procedure InlineVarConst_TypeAndInitializer_Unchanged;
    [Test] procedure RecordFieldType_Balanced_Unchanged;
    // Review Woche G03-20/G03-22
    [Test] procedure ForHeader_RangeOperator_SpacedBothSides;
    [Test] procedure ArgumentScanner_LocalRecordTypeInAnonMethod_Continues;
  end;

  // Parser-Charge P (2026-10-27): FPC-'type helper' (P1), anonyme Methode
  // mit var-Sektion (P2). Eigene Fixture,
  // damit TTestParserReviewC unter 20 Tests bleibt; Parse/NodeNamed/
  // CountKind liegen auf Unit-Ebene.
  [TestFixture]
  TTestParserChargeP = class
  public
    // P1 - 'type helper for X'
    [Test] procedure TypeHelper_ClassBehindHelperIsParsed;
    [Test] procedure TypeHelper_StrongAliasAndEnumUnchanged;
    [Test] procedure TypeHelper_MethodNameFoundAtDeclaration;
    // P2 - anonyme Methode mit var-Sektion (Paket 9015)
    [Test] procedure AnonVarSection_BodyStaysRhsText;
    [Test] procedure AnonVarSection_InlineVarInitializer;
    [Test] procedure AnonVarSection_LocalRoutineAndProcTypeInHead;
    [Test] procedure AnonVarSection_FormatMismatchAtAssignment;
  end;

implementation

// noinspection-file ClassPerFile
// Zwei Fixtures (Grenze 20 Tests je Fixture): die Review-Befunde und die
// Parser-Charge P teilen Parse/NodeNamed/CountKind - eine zweite Datei
// braechte nur einen zweiten Projekteintrag.

uses
  System.SysUtils, System.Classes, System.IOUtils,
  System.Generics.Collections,
  uSCAConsts, uMethodd12,   // TLeakFinding, fkMethodName (Charge P)
  uAstNode, uParser2,
  uTestFindingHelper;       // FindingsOfFile (Charge P, Detektor-Tests)

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
    // Die erste Sektion legt der Parser immer an: die implizite
    // 'published' vor dem ersten Schluesselwort (Bestand). Kein 'strict'.
    Assert.AreEqual<Integer>(4, CountKind(Root, nkVisibilitySection),
      'implizit published, strict private, strict protected, public');
    Assert.IsNull(NodeNamed(Root, nkVisibilitySection, 'strict'),
      'keine Sektion namens strict');
    Assert.IsNotNull(NodeNamed(Root, nkVisibilitySection, 'protected'));
  finally
    Root.Free;
  end;
end;

procedure TTestParserReviewC.IfCondition_QuotesDoubled_SpacedForm;
// Ein eingebetteter Apostroph steht wieder verdoppelt (sonst oeffnete er
// fuer die Literal-Blanker der Detektoren einen falschen String). Die Form
// bleibt die alte - ein Leerzeichen nach jedem Token -, weil rund 20
// Detektoren gegen sie geschrieben sind (Welle 1 schrieb sie kompakt und
// brach MagicNumber, Bau 2026-10-14). 'Obj . Count' sieht der Symbolindex
// trotzdem (uTestSymbolReferenceIndex.Build_IfConditionDottedMember_Indexed).
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
      Assert.AreEqual('( S = ''it''''s'' ) and ( Obj . Count > 1 )', L[0].TypeRef);
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

procedure TTestParserReviewC.ForHeader_RangeOperator_SpacedBothSides;
// Die Punkt-Regel des for-Kopfs entschied ueber das letzte Zeichen: der
// Bereichsoperator '..' endet auf '.', das Folgetoken klebte daran
// ('..High'). Jetzt zaehlt die Tokenart - '..' steht wie vor Major 14
// beidseitig mit Leerzeichen, der Member-Punkt bleibt ohne.
const
  SRC =
    'unit r; interface implementation'#13#10 +
    'procedure P;'#13#10 +
    'var x: Integer;'#13#10 +
    'begin'#13#10 +
    '  for x in [Low(A)..High(A)] do'#13#10 +
    '    X;'#13#10 +
    '  for x := Low(A) to List.Count - 1 do'#13#10 +
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
      Assert.AreEqual('x in [ Low ( A ) .. High ( A ) ]', L[0].TypeRef);
      Assert.AreEqual('x := Low ( A ) to List.Count - 1', L[1].TypeRef);
    finally
      L.Free;
    end;
  finally
    Root.Free;
  end;
end;

procedure TTestParserReviewC.ArgumentScanner_LocalRecordTypeInAnonMethod_Continues;
// Eine anonyme Methode als Argument mit lokalem record-Typ: das 'end' des
// record kam vor dem ersten 'begin', die Notbremse brach den Scan dort
// ab - der Rumpf der anonymen Methode lief als eigene Anweisungen in P,
// und der Aufrufname endete beim record. Jetzt oeffnet 'record' wie
// begin, der Rumpf bleibt im Argument.
const
  SRC =
    'unit q; interface implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '  List.ForEach(procedure(const X: Integer)'#13#10 +
    '    type TPair = record A, B: Integer; end;'#13#10 +
    '    var Pr: TPair;'#13#10 +
    '    begin'#13#10 +
    '      Pr.A := X;'#13#10 +
    '    end);'#13#10 +
    '  After;'#13#10 +
    'end;'#13#10 +
    'end.';
var
  Root    : TAstNode;
  L       : TList<TAstNode>;
  N       : TAstNode;
  ForEach : TAstNode;
begin
  Root := Parse(SRC);
  try
    ForEach := nil;
    L := Root.FindAll(nkCall);
    try
      for N in L do
        if N.Name.StartsWith('List.ForEach(') then ForEach := N;
    finally
      L.Free;
    end;
    Assert.IsNotNull(ForEach, 'der ForEach-Aufruf');
    Assert.IsTrue(Pos('Pr.A', ForEach.Name) > 0,
      'der Rumpf der anonymen Methode gehoert zum Argument: ' + ForEach.Name);
    Assert.IsNotNull(NodeNamed(Root, nkCall, 'After'),
      'der Aufruf dahinter ist ein eigener Knoten');
  finally
    Root.Free;
  end;
end;

{ ---- Parser-Charge P ---- }

const
  // Helper VOR der Klasse in derselben type-Sektion (stdctrls.pp-Muster).
  SRC_TYPE_HELPER =
    'unit h;'#13#10 +                              // 1
    'interface'#13#10 +                            // 2
    'type'#13#10 +                                 // 3
    '  TIntHelper = type helper for Integer'#13#10 + // 4
    '    function IsZero: Boolean;'#13#10 +        // 5
    '  end;'#13#10 +                               // 6
    '  TFoo = class'#13#10 +                       // 7
    '    procedure doStuff;'#13#10 +               // 8
    '  end;'#13#10 +                               // 9
    'implementation'#13#10 +                       // 10
    'function TIntHelper.IsZero: Boolean;'#13#10 + // 11
    'begin'#13#10 +                                // 12
    '  Result := Self = 0;'#13#10 +                // 13
    'end;'#13#10 +                                 // 14
    'procedure TFoo.doStuff;'#13#10 +              // 15
    'begin'#13#10 +                                // 16
    'end;'#13#10 +                                 // 17
    'end.';                                        // 18

procedure TTestParserChargeP.TypeHelper_ClassBehindHelperIsParsed;
// Vorher: der Alias-Zweig las bis zum ';' hinter 'Boolean', das 'end'
// beendete die type-Sektion, TFoo fehlte im AST (Exe 8c3eac8f: SCA106
// meldet doStuff an der Implementierungszeile, s. Test unten).
var
  Root  : TAstNode;
  HNode : TAstNode;
begin
  Root := Parse(SRC_TYPE_HELPER);
  try
    HNode := NodeNamed(Root, nkRecord, 'TIntHelper');
    Assert.IsNotNull(HNode, 'der type helper ist ein nkRecord');
    Assert.AreEqual<Integer>(4, HNode.Line);
    Assert.AreEqual<Integer>(16, HNode.Col, 'Position = das type-Token');
    Assert.IsNotNull(NodeNamed(Root, nkClass, 'TFoo'),
      'die Klasse hinter dem Helper ist im AST');
    Assert.IsNull(NodeNamed(Root, nkTypeAlias, 'TIntHelper'),
      'kein Alias-Knoten mehr');
  finally
    Root.Free;
  end;
end;

procedure TTestParserChargeP.TypeHelper_StrongAliasAndEnumUnchanged;
// Gegenprobe: 'type' ohne 'helper' (starker Alias) bleibt im Alias-Zweig
// mit demselben TypeRef; der Enum dahinter und record/class helper
// laufen wie bisher.
const
  SRC =
    'unit a; interface'#13#10 +
    'type'#13#10 +
    '  TMyInt = type Integer;'#13#10 +
    '  TColor = (cRed, cGreen);'#13#10 +
    '  TStrHelper = record helper for string'#13#10 +
    '    function Len: Integer;'#13#10 +
    '  end;'#13#10 +
    '  TBar = class'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
var
  Root : TAstNode;
begin
  Root := Parse(SRC);
  try
    Assert.IsNotNull(NodeNamed(Root, nkTypeAlias, 'TMyInt'));
    Assert.AreEqual('Integer', NodeNamed(Root, nkTypeAlias, 'TMyInt').TypeRef);
    Assert.IsNotNull(NodeNamed(Root, nkEnumType, 'TColor'));
    Assert.IsNotNull(NodeNamed(Root, nkRecord, 'TStrHelper'));
    Assert.IsNotNull(NodeNamed(Root, nkClass, 'TBar'));
  finally
    Root.Free;
  end;
end;

procedure TTestParserChargeP.TypeHelper_MethodNameFoundAtDeclaration;
// Detektor-Sicht der sichtbarsten P1-Bewegung (SCA106, laz 28 Paare): mit
// der Klasse im AST meldet SCA106 die Deklarationszeile 8. Ohne Fix kennt
// der Parser TFoo nicht und meldet die Implementierung (Zeile 15) - Exe
// 8c3eac8f an genau dieser Zeichenkette: 1 Fund, Zeile 15 (ROT).
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC_TYPE_HELPER);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMethodName),
      'doStuff genau einmal');
    Hit := nil;
    for Fnd in F do
    begin
      if Fnd.Kind = fkMethodName then
      begin
        Hit := Fnd;
      end;
    end;
    Assert.AreEqual('8', Hit.LineNumber, 'Fund an der Deklaration in TFoo');
  finally
    F.Free;
  end;
end;

function AssignNamed(Root: TAstNode; const AName: string): TAstNode;
// nkAssign mit genau diesem LHS; nil, wenn keiner.
begin
  Result := NodeNamed(Root, nkAssign, AName);
end;

procedure TTestParserChargeP.AnonVarSection_BodyStaysRhsText;
// Vorher endete der RHS-Scan am ';' hinter 'TStringList' - der Rumpf lief
// als Anweisungen von P weiter ('L.Free' als nkCall von P, 'L' als
// Label-Phantom). Jetzt bleibt er RHS-Text wie bei jeder anonymen Methode
// ohne var-Sektion; 'After' ist wieder eine Anweisung von P.
const
  SRC =
    'unit a; interface implementation'#13#10 +
    'procedure P;'#13#10 +
    'var Q: TProc;'#13#10 +
    'begin'#13#10 +
    '  Q := procedure'#13#10 +
    '    var'#13#10 +
    '      L: TStringList;'#13#10 +
    '    begin'#13#10 +
    '      L := TStringList.Create;'#13#10 +
    '      L.Free;'#13#10 +
    '    end;'#13#10 +
    '  After;'#13#10 +
    'end;'#13#10 +
    'end.';
var
  Root : TAstNode;
  Q    : TAstNode;
begin
  Root := Parse(SRC);
  try
    Q := AssignNamed(Root, 'Q');
    Assert.IsNotNull(Q, 'die Zuweisung an Q');
    Assert.IsTrue(Pos('L.Free', Q.TypeRef) > 0,
      'der Rumpf gehoert zur RHS: ' + Q.TypeRef);
    Assert.IsNull(NodeNamed(Root, nkCall, 'L.Free'), 'kein L.Free in P');
    Assert.IsNull(AssignNamed(Root, 'L'), 'kein L := .. in P');
    Assert.IsNotNull(NodeNamed(Root, nkCall, 'After'),
      'die Anweisung dahinter gehoert wieder zu P');
  finally
    Root.Free;
  end;
end;

procedure TTestParserChargeP.AnonVarSection_InlineVarInitializer;
// Derselbe Fall im Initializer einer Inline-Variablen
// (ScanInlineInitializer, delphimvcframework objectpool-Muster).
const
  SRC =
    'unit b; interface implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '  var R: TProc := procedure'#13#10 +
    '    var I: Integer;'#13#10 +
    '    begin'#13#10 +
    '      I := 1;'#13#10 +
    '    end;'#13#10 +
    '  After;'#13#10 +
    'end;'#13#10 +
    'end.';
var
  Root : TAstNode;
  R    : TAstNode;
begin
  Root := Parse(SRC);
  try
    R := AssignNamed(Root, 'R');
    Assert.IsNotNull(R, 'Initializer als nkAssign auf R');
    Assert.IsTrue(Pos('I:=1', R.TypeRef) > 0, 'Rumpf im Initializer: ' + R.TypeRef);
    Assert.IsNull(AssignNamed(Root, 'I'), 'kein I := 1 in P');
    Assert.IsNotNull(NodeNamed(Root, nkCall, 'After'));
  finally
    Root.Free;
  end;
end;

procedure TTestParserChargeP.AnonVarSection_LocalRoutineAndProcTypeInHead;
// Im Kopf: eine Prozedurtyp-Variable (oeffnet keinen Kopf - sonst liefe
// der Scan ueber das Ende der Zuweisung hinaus) und eine benannte lokale
// Routine mit eigenem begin..end (TES5Edit-Muster). Beides bleibt in der
// RHS; die Anweisung dahinter gehoert zu P.
const
  SRC =
    'unit c; interface implementation'#13#10 +
    'procedure P;'#13#10 +
    'var Q: TFunc<Integer, Integer>;'#13#10 +
    'begin'#13#10 +
    '  Q := function(A: Integer): Integer'#13#10 +
    '    var'#13#10 +
    '      F: procedure(X: Integer);'#13#10 +
    '    function Twice(B: Integer): Integer;'#13#10 +
    '    begin'#13#10 +
    '      Result := 2 * B;'#13#10 +
    '    end;'#13#10 +
    '    begin'#13#10 +
    '      F := nil;'#13#10 +
    '      Result := Twice(A);'#13#10 +
    '    end;'#13#10 +
    '  After;'#13#10 +
    'end;'#13#10 +
    'end.';
var
  Root : TAstNode;
  Q    : TAstNode;
begin
  Root := Parse(SRC);
  try
    Q := AssignNamed(Root, 'Q');
    Assert.IsNotNull(Q);
    Assert.IsTrue(Pos('Twice(A)', Q.TypeRef) > 0, 'Rumpf in der RHS: ' + Q.TypeRef);
    Assert.IsNull(AssignNamed(Root, 'Result'), 'kein Result := .. in P');
    Assert.IsNull(AssignNamed(Root, 'F'), 'kein F := nil in P');
    Assert.IsNotNull(NodeNamed(Root, nkCall, 'After'));
  finally
    Root.Free;
  end;
end;

procedure TTestParserChargeP.AnonVarSection_FormatMismatchAtAssignment;
// Detektor-Sicht der sichtbarsten P2-Bewegung (SCA005, rw 9 von 12 Funden
// wandern): der Format-Fehler im Rumpf bleibt gemeldet, jetzt an der Zeile
// der Zuweisung (9) - wie bei jeder anonymen Methode ohne var-Sektion.
// Exe 8c3eac8f an dieser Zeichenkette: 1 Fund, Zeile 13 (ROT).
const
  SRC =
    'unit a;'#13#10 +                           // 1
    'interface'#13#10 +                         // 2
    'uses System.SysUtils;'#13#10 +             // 3
    'implementation'#13#10 +                    // 4
    'procedure Run(A, B: Integer);'#13#10 +     // 5
    'var'#13#10 +                               // 6
    '  P: TProc;'#13#10 +                       // 7
    'begin'#13#10 +                             // 8
    '  P := procedure'#13#10 +                  // 9
    '    var'#13#10 +                           // 10
    '      S: string;'#13#10 +                  // 11
    '    begin'#13#10 +                         // 12
    '      S := Format(''%d'', [A, B]);'#13#10 + // 13
    '    end;'#13#10 +                          // 14
    '  P();'#13#10 +                            // 15
    'end;'#13#10 +                              // 16
    'end.';                                     // 17
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFormatMismatch),
      'ein Platzhalter, zwei Argumente');
    Hit := nil;
    for Fnd in F do
    begin
      if Fnd.Kind = fkFormatMismatch then
      begin
        Hit := Fnd;
      end;
    end;
    Assert.AreEqual('9', Hit.LineNumber, 'Fund an der Zuweisung P := ..');
  finally
    F.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestParserReviewC);
  TDUnitX.RegisterTestFixture(TTestParserChargeP);

end.

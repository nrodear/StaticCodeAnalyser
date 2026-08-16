unit uTestAstSpans;

// Tests fuer uAstSpans.TAstSpans.SubtreeMaxLine (Stufe B / Inkrement I3).
//
// WARUM DIESE TESTS EXISTIEREN
//
// Die Frage "groesste Zeilennummer im Teilbaum" war siebenfach im Kernpaket
// nachgebaut. Zwei der Fassungen sind rekursiv und haben keine nil-Pruefung.
// Beim Zusammenlegen entscheidet sich an vier Stellen, ob das Ergebnis
// gleich bleibt - und genau die pinnen die Tests hier fest:
//
//   1. Zaehlt der uebergebene Knoten selbst mit? (Ja - Test MaxInRoot.)
//   2. Schneidet ein Zwischenknoten mit Zeile 0 den Teilbaum ab?
//      (Nein - Test ZeroLineNode_DoesNotCutSubtree.)
//   3. Haengt das Ergebnis an der Besuchsreihenfolge?
//      (Nein - Test MaxInFirstChild.)
//   4. Traegt der Walk tiefe Baeume ohne Stapelueberlauf?
//      (Ja, weil er iterativ ist - Test DeepChain_NoStackOverflow.)
//
// WARUM DER STARTWERT 0 UNBEOBACHTBAR IST
//
// Fuenf Bestandskopien belegen das Ergebnis mit der Knotenzeile vor, zwei
// starten bei 0. Beide Formen liefern denselben Wert, solange keine Zeile
// negativ ist - und auf geparsten Baeumen ist keine negativ:
//
//   * uLexer.pas:315   setzt die Zeile auf 1
//   * uLexer.pas:357   erhoeht sie ausschliesslich, senkt sie nie
//   * uParser2.pas:266 erzeugt den Wurzelknoten mit Zeile 1
//
// Diese drei Belege sind die gesamte Begruendung dafuer, dass die
// Umstellungen der Aufrufer byte-identische SARIFs liefern muessen. Wer
// den Parser spaeter so umbaut, dass Zeile 0 oder eine negative Zeile
// entsteht, muss an dieser Stelle scheitern statt still das SARIF zu
// verschieben - dafuer stehen NegativeLines_ClampToZero und
// AllLinesZero_ReturnsZero hier.
//
// GEGENPROBE GEGEN DEN ABGELOESTEN CODE
//
// LegacyIterativeMax bildet die abgeloeste Fassung aus
// uLeakDetector2.pas:2066 nach, LegacyRecursiveMax die Fassung aus
// uLargeClass.pas:79 und uTypeResolver.pas:162. Beide werden gegen das
// Primitiv gefahren - auf Handbaeumen und auf einem echten Parser-Baum.
// Einzige bewusste Abweichung der Nachbildung: die nil-Pruefung steht als
// Assigned statt als Vergleich gegen nil, damit der Selbstscan keinen
// zusaetzlichen NilComparison-Fund bekommt. Semantisch ist das dasselbe.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  uAstNode,
  uAstSpans,
  uParser2,
  uTestSrcBuilder;

type
  [TestFixture]
  TTestAstSpans = class
  private
    // Nachbildung von uLeakDetector2.pas:2066 (abgeloeste Fassung):
    // Start bei 0, nil liefert 0, iterativer nicht-besitzender Stapel.
    class function LegacyIterativeMax(ARoot: TAstNode): Integer; static;
    // Nachbildung von uLargeClass.pas:79 / uTypeResolver.pas:162:
    // Start bei der Knotenzeile, rekursiv, KEINE nil-Pruefung. Nur auf
    // flachen Handbaeumen aufrufen - auf tiefen Baeumen ist genau das
    // die Fassung, die den Stapel sprengt.
    class function LegacyRecursiveMax(ANode: TAstNode): Integer; static;
    // Baut eine Kette der Laenge ALen: Wurzel mit Zeile 1, danach je ein
    // einziges Kind mit aufsteigender Zeile. Der Aufrufer gibt frei.
    class function BuildChain(ALen: Integer): TAstNode; static;
  public
    [Test] procedure NilNode_ReturnsZero;
    [Test] procedure SingleNode_ReturnsOwnLine;
    [Test] procedure ChildDeeperThanParent_ReturnsDeepest;
    [Test] procedure MaxInRoot_RootCountsItself;
    [Test] procedure MaxInFirstChild_OrderIndependent;
    [Test] procedure ZeroLineNode_DoesNotCutSubtree;
    [Test] procedure AllLinesZero_ReturnsZero;
    [Test] procedure NegativeLines_ClampToZero;
    [Test] procedure DeepChain_NoStackOverflow;
    [Test] procedure WideTree_AllChildrenVisited;
    [Test] procedure MatchesLegacyIterative_OnHandTree;
    [Test] procedure MatchesLegacyRecursive_OnHandTree;
    [Test] procedure MatchesLegacyIterative_OnParsedMethods;
  end;

implementation

uses
  System.SysUtils;

const
  // Tief genug, dass die beiden rekursiven Bestandskopien am 1-MB-Stapel
  // von TestProject.exe scheitern wuerden. Die iterative Fassung und
  // TAstNode.Destroy (uAstNode.pas:253) tragen die Tiefe.
  DEEP_CHAIN_LEN = 50000;
  // Breit genug, dass ein quadratisch wachsender Arbeitsstapel auffiele.
  WIDE_CHILD_COUNT = 10000;
  // Achtmal derselbe Wurzelname: als Literal waere das ein
  // DuplicateString-Fund (Baseline 228, keine Luft).
  ROOT_NAME = 'root';

class function TTestAstSpans.LegacyIterativeMax(ARoot: TAstNode): Integer;
var
  Stack : TList<TAstNode>;
  N     : TAstNode;
  C     : TAstNode;
begin
  Result := 0;
  if not Assigned(ARoot) then Exit;
  Stack := TList<TAstNode>.Create;
  try
    Stack.Add(ARoot);
    while Stack.Count > 0 do
    begin
      N := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);
      if N.Line > Result then
      begin
        Result := N.Line;
      end;
      for C in N.Children do
      begin
        Stack.Add(C);
      end;
    end;
  finally
    Stack.Free;
  end;
end;

class function TTestAstSpans.LegacyRecursiveMax(ANode: TAstNode): Integer;
var
  Child : TAstNode;
  Sub   : Integer;
begin
  Result := ANode.Line;
  for Child in ANode.Children do
  begin
    Sub := LegacyRecursiveMax(Child);
    if Sub > Result then
    begin
      Result := Sub;
    end;
  end;
end;

class function TTestAstSpans.BuildChain(ALen: Integer): TAstNode;
var
  Cur : TAstNode;
  i   : Integer;
begin
  Result := TAstNode.Create(nkUnit, 'chain', 1, 1);
  Cur := Result;
  for i := 2 to ALen do
  begin
    Cur := Cur.Add(nkBlock, '', i);
  end;
end;

procedure TTestAstSpans.NilNode_ReturnsZero;
// Vertragstest, kein Aequivalenztest: drei Bestandskopien
// (uUnusedRoutine.pas:235, uTypeResolver.pas:162, uLargeClass.pas:79)
// lesen die Knotenzeile ungeprueft und wuerfen hier eine AV. Ihre
// Aufrufer reichen nie nil herein, deshalb ist 0 statt AV eine
// Haertung ohne Fundwirkung - und keine Verhaltensaenderung, die ein
// A/B sehen koennte.
begin
  Assert.AreEqual<Integer>(0, TAstSpans.SubtreeMaxLine(nil));
end;

procedure TTestAstSpans.SingleNode_ReturnsOwnLine;
var
  Node : TAstNode;
begin
  Node := TAstNode.Create(nkMethod, 'm', 42, 1);
  try
    Assert.AreEqual<Integer>(42, TAstSpans.SubtreeMaxLine(Node));
  finally
    Node.Free;
  end;
end;

procedure TTestAstSpans.ChildDeeperThanParent_ReturnsDeepest;
// Trennt Teilbaum-Maximum von Direkt-Kind-Maximum: das Maximum sitzt
// beim ENKEL, nicht bei einem der direkten Kinder.
var
  Root : TAstNode;
  Mid  : TAstNode;
begin
  Root := TAstNode.Create(nkUnit, ROOT_NAME, 10, 1);
  try
    Mid := Root.Add(nkBlock, 'a', 20);
    Mid.Add(nkCall, 'deep', 99);
    Root.Add(nkBlock, 'b', 30);

    Assert.AreEqual<Integer>(99, TAstSpans.SubtreeMaxLine(Root));
  finally
    Root.Free;
  end;
end;

procedure TTestAstSpans.MaxInRoot_RootCountsItself;
// Der Knoten selbst zaehlt mit. Wer beim Zusammenlegen den Push der
// Wurzel vergisst UND bei 0 startet, faellt genau hier durch - und
// sonst nirgends.
var
  Root : TAstNode;
begin
  Root := TAstNode.Create(nkMethod, 'm', 100, 1);
  try
    Root.Add(nkBlock, 'a', 5);
    Root.Add(nkBlock, 'b', 5);

    Assert.AreEqual<Integer>(100, TAstSpans.SubtreeMaxLine(Root));
  finally
    Root.Free;
  end;
end;

procedure TTestAstSpans.MaxInFirstChild_OrderIndependent;
// Das Maximum steht im ERSTEN Kind. Die Bestandskopien laufen teils
// rueckwaerts (LIFO), teils vorwaerts (Rekursion) - fuer ein Maximum
// darf das keinen Unterschied machen.
var
  Root : TAstNode;
begin
  Root := TAstNode.Create(nkUnit, ROOT_NAME, 10, 1);
  try
    Root.Add(nkBlock, 'first', 90);
    Root.Add(nkBlock, 'second', 20);

    Assert.AreEqual<Integer>(90, TAstSpans.SubtreeMaxLine(Root));
  finally
    Root.Free;
  end;
end;

procedure TTestAstSpans.ZeroLineNode_DoesNotCutSubtree;
// Synthetische Zwischenknoten entstehen ohne Zeilenargument und tragen
// die Default-Zeile 0 (uAstNode.pas:110-111). Sie duerfen den Walk
// nicht abschneiden - sonst verloeren alle Aufrufer Teilbaeume.
var
  Root : TAstNode;
  Mid  : TAstNode;
begin
  Root := TAstNode.Create(nkUnit, ROOT_NAME, 10, 1);
  try
    Mid := Root.Add(nkBlock);          // Zeile 0, absichtlich
    Mid.Add(nkCall, 'below-zero-node', 77);

    Assert.AreEqual<Integer>(77, TAstSpans.SubtreeMaxLine(Root));
  finally
    Root.Free;
  end;
end;

procedure TTestAstSpans.AllLinesZero_ReturnsZero;
// Genau der Zustand, in dem die meisten Bestandstests von uTestTAstNode
// laufen (dort wird das Zeilenargument nie gesetzt). Der Test beweist
// fuer sich genommen nichts ueber Zeilen - er pinnt nur, dass Startwert
// 0 und Startwert Knotenzeile hier zusammenfallen.
var
  Root : TAstNode;
begin
  Root := TAstNode.Create(nkUnit, ROOT_NAME);
  try
    Root.Add(nkBlock).Add(nkCall);

    Assert.AreEqual<Integer>(0, TAstSpans.SubtreeMaxLine(Root));
  finally
    Root.Free;
  end;
end;

procedure TTestAstSpans.NegativeLines_ClampToZero;
// Der EINZIGE Eingabezustand, in dem die sieben Bestandskopien
// auseinanderlaufen. Das Primitiv haelt die Form von
// uLeakDetector2.pas:2066 und uParser2.pas:1624 (Start bei 0) - der
// abzuloesende Aufrufer ist genau diese Form, damit ist die Umstellung
// wertgleich statt nur ergebnisgleich. Auf geparsten Baeumen ist der
// Fall unerreichbar (uLexer.pas:315/:357). Faellt dieser Test kuenftig
// um, hat jemand die Zeilenherkunft geaendert - dann sind die
// Aufrufer-Umstellungen neu zu begruenden.
var
  Root : TAstNode;
begin
  Root := TAstNode.Create(nkUnit, ROOT_NAME, -5, 1);
  try
    Root.Add(nkBlock, 'a', -10);

    Assert.AreEqual<Integer>(0, TAstSpans.SubtreeMaxLine(Root));
    Assert.AreEqual<Integer>(-5, LegacyRecursiveMax(Root),
      'die Seed-Form liefert hier bewusst etwas anderes');
  finally
    Root.Free;
  end;
end;

procedure TTestAstSpans.DeepChain_NoStackOverflow;
// Die Rechtfertigung der Iterativ-Auflage. TestProject.exe setzt keine
// Stapelgroesse, laeuft also auf dem 1-MB-Default; die rekursiven
// Bestandskopien reissen bei dieser Tiefe. LegacyRecursiveMax wird hier
// bewusst NICHT gerufen.
var
  Root : TAstNode;
begin
  Root := BuildChain(DEEP_CHAIN_LEN);
  try
    Assert.AreEqual<Integer>(DEEP_CHAIN_LEN, TAstSpans.SubtreeMaxLine(Root));
    Assert.AreEqual<Integer>(DEEP_CHAIN_LEN, LegacyIterativeMax(Root));
  finally
    Root.Free;
  end;
end;

procedure TTestAstSpans.WideTree_AllChildrenVisited;
// Breiter statt tiefer Baum: belegt, dass der wachsende Arbeitsstapel
// alle Geschwister aufnimmt und die Nicht-Rekursion nicht mit
// quadratischen Kosten erkauft ist.
var
  Root : TAstNode;
  i    : Integer;
begin
  Root := TAstNode.Create(nkUnit, ROOT_NAME, 1, 1);
  try
    for i := 2 to WIDE_CHILD_COUNT + 1 do
    begin
      Root.Add(nkBlock, '', i);
    end;

    Assert.AreEqual<Integer>(WIDE_CHILD_COUNT + 1,
      TAstSpans.SubtreeMaxLine(Root));
  finally
    Root.Free;
  end;
end;

procedure TTestAstSpans.MatchesLegacyIterative_OnHandTree;
// Direkter Vergleich mit dem abgeloesten Code aus uLeakDetector2.
var
  Root : TAstNode;
  Mid  : TAstNode;
begin
  Root := TAstNode.Create(nkUnit, ROOT_NAME, 3, 1);
  try
    Mid := Root.Add(nkClass, 'TFoo', 7);
    Mid.Add(nkMethod, 'Bar', 11).Add(nkBlock, '', 19);
    Mid.Add(nkField, 'FBaz', 9);
    Root.Add(nkBlock);                 // Zeile 0 dazwischen

    Assert.AreEqual<Integer>(LegacyIterativeMax(Root),
      TAstSpans.SubtreeMaxLine(Root));
  finally
    Root.Free;
  end;
end;

procedure TTestAstSpans.MatchesLegacyRecursive_OnHandTree;
// Dieselbe Gegenprobe gegen die REKURSIVE Bestandsform - sie belegt,
// dass Rekursion und Iteration dieselbe Knotenmenge besuchen. Alle
// Zeilen sind positiv, also greift der Startwert-Unterschied nicht.
var
  Root : TAstNode;
  Mid  : TAstNode;
begin
  Root := TAstNode.Create(nkUnit, ROOT_NAME, 2, 1);
  try
    Mid := Root.Add(nkClass, 'TFoo', 8);
    Mid.Add(nkMethod, 'Bar', 14).Add(nkBlock, '', 23);
    Root.Add(nkMethod, 'Baz', 31);

    Assert.AreEqual<Integer>(LegacyRecursiveMax(Root),
      TAstSpans.SubtreeMaxLine(Root));
  finally
    Root.Free;
  end;
end;

procedure TTestAstSpans.MatchesLegacyIterative_OnParsedMethods;
// Handbaeume belegen den Vertrag, nicht die Ablesung echter Parser-
// Zeilen. Deshalb zusaetzlich ueber einen geparsten Baum: fuer JEDEN
// Methodenknoten muss das Primitiv denselben Wert liefern wie die
// abgeloeste Fassung. Das ersetzt das A/B ueber den Korpus nicht, es
// ist aber die einzige Stelle im Testrahmen, an der echte Zeilen-
// nummern beteiligt sind.
var
  Parser  : TParser2;
  Root    : TAstNode;
  Methods : TList<TAstNode>;
  M       : TAstNode;
  Source  : string;
begin
  Source := Src([
    'unit t;',
    'interface',
    'implementation',
    'procedure First;',
    'var',
    '  L: TStringList;',
    'begin',
    '  L := TStringList.Create;',
    '  try',
    '    L.Add(''x'');',
    '  finally',
    '    L.Free;',
    '  end;',
    'end;',
    'procedure Second;',
    'begin',
    '  if True then',
    '  begin',
    '    Beep;',
    '  end;',
    'end;',
    'end.']);

  // EIN try/finally statt drei geschachtelter: die geschachtelte Fassung
  // erzeugte zwei NestedTry-Funde im Self-Scan (Baseline 269, keine Luft).
  // Free auf nil ist ein No-op, deshalb traegt die Sammel-Freigabe in
  // umgekehrter Erzeugungsreihenfolge dieselbe Garantie.
  Parser  := nil;
  Root    := nil;
  Methods := nil;
  try
    Parser  := TParser2.Create;
    Root    := Parser.ParseSource(Source);
    Methods := Root.FindAll(nkMethod);
    Assert.IsTrue(Methods.Count > 0, 'Testquelle liefert keine Methoden');
    for M in Methods do
    begin
      Assert.AreEqual<Integer>(LegacyIterativeMax(M),
        TAstSpans.SubtreeMaxLine(M),
        Format('Abweichung bei Methode "%s" (Zeile %d)', [M.Name, M.Line]));
    end;
  finally
    Methods.Free;
    Root.Free;
    Parser.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAstSpans);

end.

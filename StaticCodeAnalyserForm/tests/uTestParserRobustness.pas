unit uTestParserRobustness;

// Tests fuer Parser-Robustheit gegen Real-World-mORMot2-Konstrukte.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uAstNode, uParser2,
  uTestSrcBuilder,
  uTestFindingHelper;

type
  // ---- Parser-Robustheit (Real-World mORMot2-Konstrukte) -----------------------------
  // Probe: jeder Test hat einen Memory-Leak in einer Methode, die DURCH oder
  // NACH dem zu testenden Konstrukt definiert ist. Wenn der Parser das
  // Konstrukt korrekt verarbeitet, wird der Leak gefunden; wenn nicht, geht
  // der Body verloren und der Leak verschwindet.
  [TestFixture]
  TTestParserRobustness = class
  public
    [Test] procedure Parser_InterfaceDecl_FollowingMethodLeakDetected;
    [Test] procedure Parser_GenericTypeDecl_MethodLeakDetected;
    [Test] procedure Parser_GenericMethodSig_LeakDetected;
    [Test] procedure Parser_PackedRecord_FollowingMethodLeakDetected;
    [Test] procedure Parser_LabelSection_BodyLeakDetected;
    [Test] procedure Parser_ClassHelperFor_FollowingMethodLeakDetected;
    [Test] procedure Parser_IfdefDuplicatedHeaders_NoPhantomDuplicate;
    [Test] procedure Parser_InlineRecordVarType_BodyNotLost;
    [Test] procedure Parser_NestedInlineRecordVarType_BodyNotLost;
    [Test] procedure Parser_InlineRecordTypeInLocalConst_BodyNotLost;
    [Test] procedure Parser_NestedRoutine_OuterBodyLeakDetected;
    [Test] procedure Parser_NestedRoutine_NestedBodyNotAnalyzed;

    // ---- Bug A (2026-07-04): impl-level Section-Truncation ------------
    // type/const/var-Sections zwischen Top-Level-Implementierungen bzw.
    // record-tragende lokale type-Sections brachen den Parse ab - der
    // Rest der Datei fehlte im AST. AST-Level-Asserts via uParser2 direkt.
    [Test] procedure Parser_ImplTypeSectionBetweenImpls_BothMethodsTopLevel;
    [Test] procedure Parser_ImplConstSectionBetweenImpls_BothMethodsTopLevel;
    [Test] procedure Parser_ImplVarSectionBetweenImpls_BothMethodsTopLevel;
    [Test] procedure Parser_ImplSectionBeforeFirstImpl_MethodParsed;
    [Test] procedure Parser_ImplMultipleSectionsBetweenImpls_BothMethodsTopLevel;
    [Test] procedure Parser_LocalRecordTypeSection_RestOfFileParsed;
    [Test] procedure Parser_LocalNestedRecordTypeSection_RestOfFileParsed;
    [Test] procedure Parser_ForwardDeclThenTypeSection_RestOfFileParsed;
    [Test] procedure Parser_NestedTypeInImplClass_RestOfFileParsed;
    [Test] procedure Parser_TrailingCodeAfterEndDot_NotParsed;

    // ---- Bug B (2026-07-04): IFDEF-Methoden-Verschachtelung -----------
    // {$IFDEF}/{$ELSE}-Twin-Bodies (zwei begin, ein end) liessen alle
    // Folge-Methoden im Body der ersten Methode verschwinden (blcksock).
    [Test] procedure Parser_IfdefTwinHeadersSharedEnd_FollowupMethodsTopLevel;
    [Test] procedure Parser_IfdefSingleHeaderTwoBegins_FollowupMethodTopLevel;
    [Test] procedure Parser_LegalNestedRoutine_NotHoistedToTopLevel;
    [Test] procedure Parser_AnonymousMethodInBody_NoTopLevelMethod;
    [Test] procedure Parser_LocalProcTypeVar_NoFalseRecovery;
  end;

implementation

{ ---- AST-Helper fuer die Bug-A/Bug-B-Tests (2026-07-04) ---- }

// Liefert den nkImplementation-Knoten der Unit (nil wenn keiner existiert).
function ImplNodeOf(Root: TAstNode): TAstNode;
var
  C: TAstNode;
begin
  Result := nil;
  for C in Root.Children do
    if C.Kind = nkImplementation then Exit(C);
end;

// Kommagetrennte Namen aller DIREKTEN nkMethod-Kinder (= Top-Level-
// Methoden) in Deklarationsreihenfolge. Genestete Methoden erscheinen
// bewusst NICHT - genau das unterscheidet Top-Level von Absorbiert.
function TopLevelMethodNames(ImplN: TAstNode): string;
var
  C: TAstNode;
begin
  Result := '';
  if ImplN = nil then Exit;
  for C in ImplN.Children do
    if C.Kind = nkMethod then
    begin
      if Result <> '' then Result := Result + ',';
      Result := Result + C.Name;
    end;
end;

{ ---- TTestParserRobustness ---- }

procedure TTestParserRobustness.Parser_InterfaceDecl_FollowingMethodLeakDetected;
// Vorher: `IFoo = interface ... end;` hatte keinen Case in ParseTypeSection,
// fiel in TypeAlias-else-Branch, dessen Schleife beim ersten internen `;`
// brach -> komplettes Interface verloren UND der nachfolgende `end;` schloss
// einen ueberraschenden Block. Heute: tkKwInterface-Case ruft ParseClassBody
// und liest das Interface sauber - die nachfolgende Methode bleibt
// erkennbar.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  IFoo = interface'#13#10+
  '    procedure Bar;'#13#10+
  '    function Baz: Integer;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Test;'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  '  // L.Free fehlt!'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak in Methode nach Interface-Decl muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_GenericTypeDecl_MethodLeakDetected;
// Vorher: `TFoo<T> = class` -> Eat(tkEq) schlug am `<` fehl -> SkipToSemicolon
// -> komplette Generic-Klasse verloren. Heute: SkipGenericParams konsumiert
// `<T>` vor dem `=`.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TBox<T> = class'#13#10+
  '    procedure Add(Item: T);'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure TBox<T>.Add(Item: T);'#13#10+
  'var Tmp: TStringList;'#13#10+
  'begin'#13#10+
  '  Tmp := TStringList.Create;'#13#10+
  '  // Tmp.Free fehlt!'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak in qualifizierter Generic-Methode muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_GenericMethodSig_LeakDetected;
// Generic-Methode `function Get<T>: T;`. SkipGenericParams konsumiert das
// `<T>` nach dem Methodennamen, sodass die Param-Liste / Rueckgabetyp
// nicht verschoben werden.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure DoIt;'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  'end;'#13#10+
  'function Get<T>: T;'#13#10+
  'begin'#13#10+
  '  Result := Default(T);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'DoIt vor Generic-Method muss als Leak erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_PackedRecord_FollowingMethodLeakDetected;
// `packed record` wurde vorher als TypeAlias missinterpretiert weil
// tkKwPacked keinen Case hatte. Heute: optionales Eat(tkKwPacked) vor dem
// class/record-Switch.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TPoint = packed record'#13#10+
  '    X: Integer;'#13#10+
  '    Y: Integer;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure UseLeak;'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak nach packed record muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_LabelSection_BodyLeakDetected;
// `label x;` zwischen var-Block und begin liess vorher die Outer-Schleife
// in ParseLocalVarSection enden und ParseMethodImpl sah `label` statt
// `begin` -> Body verloren. Heute: tkKwLabel wird wie var/const/type als
// Section akzeptiert und bis zum naechsten ; geskippt.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure Tricky;'#13#10+
  'label'#13#10+
  '  loop1, loop2;'#13#10+
  'var'#13#10+
  '  L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  '  // L.Free fehlt!'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak in Methode mit label-Section muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_ClassHelperFor_FollowingMethodLeakDetected;
// `record helper for string` war ein Stolperstein: nach `record` kam ein
// Ident `helper` der als Feld-Decl ge-misinterpretiert wurde. Heute:
// SkipHelperFor konsumiert `helper for <type>` bevor ParseClassBody startet.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TStringHelper = record helper for string'#13#10+
  '    function MyLen: Integer;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'function TStringHelper.MyLen: Integer;'#13#10+
  'begin'#13#10+
  '  Result := Length(Self);'#13#10+
  'end;'#13#10+
  'procedure UseLeak;'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak nach record helper muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_IfdefDuplicatedHeaders_NoPhantomDuplicate;
// IFDEF um Method-Header herum ergibt zwei sichtbare Header im Token-Stream
// (Lexer skippt nur Comments). ParseMethodImpl entfernt jetzt einen
// Headless-Knoten wenn der naechste Token wieder ein Method-Keyword ist
// -> kein Phantom-Duplikat im AST mehr.
//
// Wir testen das indirekt: ein Leak in dem (echten) Body soll genau einmal
// gemeldet werden, nicht doppelt durch Phantom-Methode.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  '{$IFDEF FPC}'#13#10+
  'function DoIt: Integer;'#13#10+
  '{$ELSE}'#13#10+
  'function DoIt: Integer;'#13#10+
  '{$ENDIF}'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  '  Result := L.Count;'#13#10+
  '  // L.Free fehlt!'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak darf nicht durch Phantom-Methoden-Duplikat verdoppelt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_InlineRecordVarType_BodyNotLost;
// Vorher: anonymer `record`-Typ als Var-Typ - TypeName-Loop in
// ParseLocalVarSection brach am ersten `;` _innerhalb_ des records ab,
// dann las der Outer-Loop das folgende `end` als Section-Grenze und
// ParseMethodImpl verlor den Methodenrumpf -> Leak weg, doppelter Bug.
// Heute: Mini-Parser bis matching `end`.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Test;'#13#10+
  'var'#13#10+
  '  R: record A: Integer; B: Integer; end;'#13#10+
  '  L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  '  // L.Free fehlt!'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak nach inline-record-Var-Typ muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_NestedInlineRecordVarType_BodyNotLost;
// Nested record inside record - Depth-Tracking muss beide `end` zaehlen.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Test;'#13#10+
  'var'#13#10+
  '  R: record'#13#10+
  '    A: record X: Integer; Y: Integer; end;'#13#10+
  '    B: Integer;'#13#10+
  '  end;'#13#10+
  '  L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak nach nested-inline-record muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_InlineRecordTypeInLocalConst_BodyNotLost;
// Inline-record als Typ einer Local-Const-Initialisierung. Section bleibt
// auf var (kein type-Section); der Mini-Parser muss auch hier sauber
// laufen, sonst geht der Body verloren.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Test;'#13#10+
  'var'#13#10+
  '  P: record Key: string; Value: Integer; end;'#13#10+
  '  L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak nach Single-Line inline-record muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_NestedRoutine_OuterBodyLeakDetected;
// Root-Cause-Fix Parser nested routine: eine lokale `procedure` VOR dem
// begin der aeusseren Methode. Vorher fraß ParseLocalVarSection sie als
// Pseudo-Var und ParseMethodImpl nahm den NESTED-Body als Outer-Body ->
// der echte Outer-Body (mit dem Leak) ging verloren. Heute wird die nested
// routine als eigenes nkMethod-Child geparst, der Outer-Body bleibt erhalten.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Test;'#13#10+
  'var L: TStringList;'#13#10+
  '  procedure Helper;'#13#10+
  '  begin'#13#10+
  '    Sleep(1);'#13#10+
  '  end;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  '  Helper;'#13#10+
  '  // L.Free fehlt!'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Outer-Body-Leak darf durch nested routine nicht verschwinden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_NestedRoutine_NestedBodyNotAnalyzed;
// Der Leak steckt IM Body der nested routine. Nested routines werden geparst
// (damit der Outer-Body nicht verloren geht), aber bewusst NICHT als
// analysierbare Methoden im AST belassen (siehe ParseMethodImpl). Daher wird
// der Leak in der nested routine NICHT als fkMemoryLeak gemeldet - konsistent
// mit dem fruehen Verhalten (AST enthielt nie nested routines) und vermeidet
// die Findings-Flut auf nested Helpern. Wichtig ist nur: der Outer-Body bleibt
// intakt (X := 1 wird sauber geparst, kein Crash, kein verlorener Body).
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Test;'#13#10+
  'var X: Integer;'#13#10+
  '  procedure Helper;'#13#10+
  '  var L: TStringList;'#13#10+
  '  begin'#13#10+
  '    L := TStringList.Create;'#13#10+
  '    // L.Free fehlt!'#13#10+
  '  end;'#13#10+
  'begin'#13#10+
  '  X := 1;'#13#10+
  '  Helper;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak in nested routine wird nicht standalone gemeldet (nicht analysiert)');
  finally F.Free; end;
end;

{ ---- Bug A (2026-07-04): impl-level Section-Truncation ---- }

procedure TTestParserRobustness.Parser_ImplTypeSectionBetweenImpls_BothMethodsTopLevel;
// Guard: eine type-Section (Klasse) ZWISCHEN zwei Top-Level-Impls darf den
// Parse nicht abbrechen - beide Methoden muessen als direkte Kinder des
// implementation-Knotens im AST stehen.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure FirstProc;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'type'#13#10+
  '  TLocal = class'#13#10+
  '    FData: Integer;'#13#10+
  '  end;'#13#10+
  'procedure SecondProc;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  ImplN  : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      Assert.AreEqual<Integer>(2, ImplN.DirectChildCount(nkMethod),
        'beide Methoden muessen Top-Level im AST stehen');
      Assert.AreEqual('FirstProc,SecondProc', TopLevelMethodNames(ImplN),
        'Methodennamen/-reihenfolge auf Top-Level');
      Assert.AreEqual<Integer>(2, Root.DescendantCount(nkMethod),
        'keine zusaetzlichen/genesteten Methoden im Baum');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_ImplConstSectionBetweenImpls_BothMethodsTopLevel;
// Guard: const-Section zwischen Impls.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure FirstProc;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'const'#13#10+
  '  CMax = 5;'#13#10+
  'procedure SecondProc;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  ImplN  : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      Assert.AreEqual<Integer>(2, ImplN.DirectChildCount(nkMethod),
        'beide Methoden muessen Top-Level im AST stehen');
      Assert.AreEqual('FirstProc,SecondProc', TopLevelMethodNames(ImplN),
        'Methodennamen/-reihenfolge auf Top-Level');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_ImplVarSectionBetweenImpls_BothMethodsTopLevel;
// Guard: var-Section zwischen Impls.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure FirstProc;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'var'#13#10+
  '  GState: Integer;'#13#10+
  'procedure SecondProc;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  ImplN  : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      Assert.AreEqual<Integer>(2, ImplN.DirectChildCount(nkMethod),
        'beide Methoden muessen Top-Level im AST stehen');
      Assert.AreEqual('FirstProc,SecondProc', TopLevelMethodNames(ImplN),
        'Methodennamen/-reihenfolge auf Top-Level');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_ImplSectionBeforeFirstImpl_MethodParsed;
// Guard: Section direkt nach 'implementation', VOR der ersten Routine.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'type'#13#10+
  '  TLocal = class'#13#10+
  '    FData: Integer;'#13#10+
  '  end;'#13#10+
  'procedure OnlyProc;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  ImplN  : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      Assert.AreEqual<Integer>(1, ImplN.DirectChildCount(nkMethod),
        'Methode nach der Section muss Top-Level im AST stehen');
      Assert.AreEqual('OnlyProc', TopLevelMethodNames(ImplN),
        'Methodenname auf Top-Level');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_ImplMultipleSectionsBetweenImpls_BothMethodsTopLevel;
// Guard: mehrere Sections (type+const+var) hintereinander zwischen Impls.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure FirstProc;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'type'#13#10+
  '  TAlias = Integer;'#13#10+
  'const'#13#10+
  '  CMax = 5;'#13#10+
  'var'#13#10+
  '  GCount: Integer;'#13#10+
  'procedure SecondProc;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  ImplN  : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      Assert.AreEqual<Integer>(2, ImplN.DirectChildCount(nkMethod),
        'beide Methoden muessen Top-Level im AST stehen');
      Assert.AreEqual('FirstProc,SecondProc', TopLevelMethodNames(ImplN),
        'Methodennamen/-reihenfolge auf Top-Level');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_LocalRecordTypeSection_RestOfFileParsed;
// Bug-A-Kernrepro: LOKALE type-Section mit record im Deklarationsteil einer
// Routine. Vorher stoppte der Section-Skip am ersten `end` im record-Body,
// ParseMethodImpl fand kein `begin` und ParseImplementationSection hielt
// das record-`end` fuer das Unit-Ende -> ALLES danach fehlte im AST
// (Selbstscan-Repro '20 -> 1 Findings'). Heute: balancierter record-Skip.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure WithLocalType;'#13#10+
  'type'#13#10+
  '  TRec = record X: Integer; end;'#13#10+
  'var A: TStringList;'#13#10+
  'begin'#13#10+
  '  A := TStringList.Create;'#13#10+
  'end;'#13#10+
  'procedure SecondProc;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  ImplN  : TAstNode;
  FirstM : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      Assert.AreEqual<Integer>(2, ImplN.DirectChildCount(nkMethod),
        'Methode mit lokaler record-type-Section UND Folgemethode im AST');
      Assert.AreEqual('WithLocalType,SecondProc', TopLevelMethodNames(ImplN),
        'Methodennamen/-reihenfolge auf Top-Level');
      FirstM := ImplN.FindFirstChild(nkMethod);
      Assert.IsTrue(FirstM.HasDirectChild(nkBlock),
        'Body von WithLocalType darf nicht verloren gehen');
      Assert.AreEqual<Integer>(1, FirstM.DescendantCount(nkAssign),
        'Zuweisung im Body von WithLocalType muss im AST stehen');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_LocalNestedRecordTypeSection_RestOfFileParsed;
// Wie Parser_LocalRecordTypeSection_RestOfFileParsed, aber mit NESTED
// record im record - der balancierte Skip muss beide `end` zaehlen.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure WithLocalNestedRec;'#13#10+
  'type'#13#10+
  '  TRec = record'#13#10+
  '    Inner: record X: Integer; end;'#13#10+
  '    Y: Integer;'#13#10+
  '  end;'#13#10+
  'var A: TStringList;'#13#10+
  'begin'#13#10+
  '  A := TStringList.Create;'#13#10+
  'end;'#13#10+
  'procedure SecondProc;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  ImplN  : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      Assert.AreEqual<Integer>(2, ImplN.DirectChildCount(nkMethod),
        'nested record in lokaler type-Section darf Folge-Code nicht kappen');
      Assert.AreEqual('WithLocalNestedRec,SecondProc', TopLevelMethodNames(ImplN),
        'Methodennamen/-reihenfolge auf Top-Level');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_ForwardDeclThenTypeSection_RestOfFileParsed;
// Bug-A-Repro forward-Variante: nach `procedure Fwd; forward;` lief frueher
// ParseLocalVarSection weiter und frass die folgende impl-level type-Section
// als vermeintlich lokale Sektion - deren Class-`end` kappte den Rest der
// Datei. Heute: forward/external beenden ParseMethodImpl sofort, der
// Impl-Loop parst die Section regulaer.
// Erwartung 3 nkMethod: Forward-Knoten (headless, wie eine Interface-
// Signatur) + echte Fwd-Implementierung + SecondProc.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure Fwd; forward;'#13#10+
  'type'#13#10+
  '  TLocalHelper = class'#13#10+
  '    FData: Integer;'#13#10+
  '  end;'#13#10+
  'procedure Fwd;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'procedure SecondProc;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  ImplN  : TAstNode;
  LastM  : TAstNode;
  C      : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      Assert.AreEqual<Integer>(3, ImplN.DirectChildCount(nkMethod),
        'Forward-Knoten + echte Fwd-Impl + SecondProc erwartet');
      Assert.AreEqual('Fwd,Fwd,SecondProc', TopLevelMethodNames(ImplN),
        'Methodennamen/-reihenfolge auf Top-Level');
      // Die LETZTE Methode (SecondProc) muss ihren Body behalten haben.
      LastM := nil;
      for C in ImplN.Children do
        if C.Kind = nkMethod then LastM := C;
      Assert.IsTrue(LastM.HasDirectChild(nkBlock),
        'SecondProc-Body darf nicht verloren gehen');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_NestedTypeInImplClass_RestOfFileParsed;
// Bug-A-Repro nested-type-Variante: Klasse mit NESTED Typ in einer
// impl-level type-Section. ParseClassBody endet am inneren `end`, das
// aeussere `end` sickerte zum Impl-Loop durch und beendete frueher die
// komplette Section (Truncation). Heute: stray-`end`-Resync im Impl-Loop -
// nur echtes `end.`/EOF terminiert.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure FirstProc;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'type'#13#10+
  '  TOuter = class'#13#10+
  '  public'#13#10+
  '    type TInner = class'#13#10+
  '      FX: Integer;'#13#10+
  '    end;'#13#10+
  '  end;'#13#10+
  'procedure SecondProc;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  ImplN  : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      Assert.AreEqual<Integer>(2, ImplN.DirectChildCount(nkMethod),
        'nested type im Class-Body darf SecondProc nicht kappen');
      Assert.AreEqual('FirstProc,SecondProc', TopLevelMethodNames(ImplN),
        'Methodennamen/-reihenfolge auf Top-Level');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_TrailingCodeAfterEndDot_NotParsed;
// Review-Guard (2026-07-04): Text NACH 'end.' ist per Sprachdefinition tot
// (Dead-Code-Idiom: 'end.' hochziehen um den Dateirest zu deaktivieren).
// Der end.-Zweig des Impl-Loops muss den Rest bis EOF verwerfen - sonst
// entstuenden Phantom-AST-Knoten (und damit Findings) auf totem Code.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure FirstProc;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.'#13#10+
  'type'#13#10+
  '  TDead = class'#13#10+
  '    FData: Integer;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure DeadProc;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  ImplN  : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      Assert.AreEqual<Integer>(1, Root.DescendantCount(nkMethod),
        'toter Code hinter end. darf keine Phantom-Methoden erzeugen');
      Assert.AreEqual('FirstProc', TopLevelMethodNames(ImplN),
        'nur die Methode VOR end. steht im AST');
      Assert.AreEqual<Integer>(0, Root.DescendantCount(nkClass),
        'tote type-Section hinter end. darf keinen Klassen-Knoten erzeugen');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

{ ---- Bug B (2026-07-04): IFDEF-Methoden-Verschachtelung ---- }

procedure TTestParserRobustness.Parser_IfdefTwinHeadersSharedEnd_FollowupMethodsTopLevel;
// blcksock-Muster Variante 1: ZWEI Header + ZWEI begin, EIN gemeinsames
// end ({$IFDEF}/{$ELSE}-Twin-Bodies; der Lexer skippt Direktiven als
// Kommentare). Vorher landeten der zweite First-Body UND alle Folge-
// Methoden als Statements im Body der ersten Methode. Heute: qualifizierte
// Header im offenen Body werden als neue Top-Level-Methode recovert.
// Erwartung: 4 Top-Level-Methoden (First-Twin bewusst doppelt - beide
// IFDEF-Zweige bleiben sichtbar), KEINE genestete Methode.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  '{$IFDEF CIL}'#13#10+
  'procedure TFoo.First;'#13#10+
  'begin'#13#10+
  '  DoNetStuff;'#13#10+
  '{$ELSE}'#13#10+
  'procedure TFoo.First;'#13#10+
  'var L1: TStringList;'#13#10+
  'begin'#13#10+
  '  L1 := TStringList.Create;'#13#10+
  '{$ENDIF}'#13#10+
  'end;'#13#10+
  'procedure TFoo.Second;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'procedure TFoo.Third;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  ImplN  : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      Assert.AreEqual<Integer>(4, ImplN.DirectChildCount(nkMethod),
        'First-Twin (2x) + Second + Third muessen Top-Level stehen');
      Assert.AreEqual('TFoo.First,TFoo.First,TFoo.Second,TFoo.Third',
        TopLevelMethodNames(ImplN),
        'Folge-Methoden auf Top-Level statt im Body der ersten');
      Assert.AreEqual<Integer>(4, Root.DescendantCount(nkMethod),
        'keine Methode darf in einer anderen genestet sein');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_IfdefSingleHeaderTwoBegins_FollowupMethodTopLevel;
// blcksock-Muster Variante 2 (Original InternalCanRead, blcksock.pas
// ~Z.2772): EIN Header, dann {$IFDEF}-begin + {$ELSE}-var+begin, EIN end.
// Das eine end schliesst nur den inneren Block; der Header der naechsten
// Methode tauchte im noch offenen Body auf und wurde samt Body absorbiert
// (im Real-File verschwanden ALLE Folge-Methoden bis Dateiende).
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'function TBlockSocket.InternalCanRead(Timeout: Integer): Boolean;'#13#10+
  '{$IFDEF CIL}'#13#10+
  'begin'#13#10+
  '  Result := True;'#13#10+
  '{$ELSE}'#13#10+
  'var'#13#10+
  '  x: Integer;'#13#10+
  'begin'#13#10+
  '  x := Timeout;'#13#10+
  '  Result := x > 0;'#13#10+
  '{$ENDIF}'#13#10+
  'end;'#13#10+
  'function TBlockSocket.CanRead(Timeout: Integer): Boolean;'#13#10+
  'begin'#13#10+
  '  Result := InternalCanRead(Timeout);'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  ImplN  : TAstNode;
  LastM  : TAstNode;
  C      : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      Assert.AreEqual<Integer>(2, ImplN.DirectChildCount(nkMethod),
        'CanRead muss trotz Two-Begins-Vorgaenger Top-Level stehen');
      Assert.AreEqual('TBlockSocket.InternalCanRead,TBlockSocket.CanRead',
        TopLevelMethodNames(ImplN),
        'Folge-Methode auf Top-Level statt im Body der ersten');
      LastM := nil;
      for C in ImplN.Children do
        if C.Kind = nkMethod then LastM := C;
      Assert.IsTrue(LastM.HasDirectChild(nkBlock),
        'CanRead-Body muss an CanRead haengen');
      Assert.AreEqual<Integer>(1, LastM.DescendantCount(nkAssign),
        'Result-Zuweisung muss im CanRead-Body stehen');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_LegalNestedRoutine_NotHoistedToTopLevel;
// Gegenprobe Bug B: eine LEGALE nested routine (unqualifizierter Header im
// Deklarationsteil) darf von der Recovery nicht angefasst werden. Sie wird
// wie bisher geparst und verworfen (nkNestedRange-Marker, Policy siehe
// ParseMethodImpl) - sie darf weder als Top-Level-Methode auftauchen noch
// den Outer-Body beschaedigen.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Test;'#13#10+
  'var L: TStringList;'#13#10+
  '  procedure Helper;'#13#10+
  '  begin'#13#10+
  '    Sleep(1);'#13#10+
  '  end;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  '  Helper;'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  ImplN  : TAstNode;
  M      : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      Assert.AreEqual<Integer>(1, ImplN.DirectChildCount(nkMethod),
        'nested routine darf NICHT als Top-Level-Methode gehoisted werden');
      Assert.AreEqual('TFoo.Test', TopLevelMethodNames(ImplN),
        'nur die aeussere Methode auf Top-Level');
      M := ImplN.FindFirstChild(nkMethod);
      Assert.AreEqual<Integer>(1, M.DescendantCount(nkNestedRange),
        'nested routine hinterlaesst genau einen nkNestedRange-Marker');
      Assert.IsTrue(M.HasDirectChild(nkBlock),
        'Outer-Body muss erhalten bleiben');
      Assert.AreEqual<Integer>(1, M.DescendantCount(nkAssign),
        'Outer-Zuweisung muss im AST stehen');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_AnonymousMethodInBody_NoTopLevelMethod;
// Gegenprobe Bug B: anonyme Methode im Body (Expression-Kontext). Die
// `procedure`-Tokens werden vom RHS-Scanner konsumiert und erreichen den
// Statement-Dispatcher nie - es darf keine Phantom-Top-Level-Methode
// entstehen.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Test;'#13#10+
  'var CB: TProc;'#13#10+
  'begin'#13#10+
  '  CB := procedure'#13#10+
  '    begin'#13#10+
  '      Beep;'#13#10+
  '    end;'#13#10+
  '  CB();'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  ImplN  : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      Assert.AreEqual<Integer>(1, ImplN.DirectChildCount(nkMethod),
        'anonyme Methode darf keine Top-Level-Methode erzeugen');
      Assert.AreEqual('TFoo.Test', TopLevelMethodNames(ImplN),
        'nur die echte Methode im AST');
      Assert.AreEqual<Integer>(1, Root.DescendantCount(nkMethod),
        'keine Phantom-nkMethod im Baum');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_LocalProcTypeVar_NoFalseRecovery;
// Gegenprobe Bug B: `procedure(...)` als TYP einer lokalen Variable steht
// hinter ':' und wird vom TypeName-Loop konsumiert - kein Recovery-Fall.
// Body und Folge-Methode muessen normal geparst werden.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Test;'#13#10+
  'var CB: procedure(Sender: TObject) of object;'#13#10+
  'begin'#13#10+
  '  CB := nil;'#13#10+
  'end;'#13#10+
  'procedure After;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  ImplN  : TAstNode;
  FirstM : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      Assert.AreEqual<Integer>(2, ImplN.DirectChildCount(nkMethod),
        'proc-Typ-Var darf weder Recovery ausloesen noch After kappen');
      Assert.AreEqual('TFoo.Test,After', TopLevelMethodNames(ImplN),
        'Methodennamen/-reihenfolge auf Top-Level');
      FirstM := ImplN.FindFirstChild(nkMethod);
      Assert.IsTrue(FirstM.HasDirectChild(nkBlock),
        'Body von TFoo.Test muss erhalten bleiben');
      Assert.AreEqual<Integer>(1, FirstM.DescendantCount(nkAssign),
        'CB := nil muss als Zuweisung im Body stehen');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

end.

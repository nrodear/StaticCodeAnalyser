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
    // Real-World FP-Audit 2026-07-12 (SCA028): nicht-reservierte Standard-Routine
    // als Methoden-/Event-Handler-Name (Lexer -> tkKwExit)
    [Test] procedure Parser_KeywordMethodNameUnqualified_Captured;
    [Test] procedure Parser_KeywordMethodNameQualified_Captured;
    // --- Parser Mechanismus A (2026-07-26): Inline-const im Rumpf ---
    [Test] procedure Parser_InlineConst_EmitsConstSectionField;
    [Test] procedure Parser_InlineConst_TypedEmitsTypeAndValue;
    [Test] procedure Parser_InlineConst_SemicolonInStringKeepsSync;
    [Test] procedure Parser_InlineConst_ParenAndArrayKeepSync;
    [Test] procedure Parser_InlineConst_MissingEqualsIsBounded;
    [Test] procedure Parser_InlineConst_TypedNoLongerHidesDeadCode;
    [Test] procedure Parser_LocalConstSection_StillParsedAsBefore;

    // --- Nested-Type-Implementierungs-Header (2026-07-27) ---
    [Test] procedure Parser_NestedTypeImplHeader_FullNameCaptured;
    [Test] procedure Parser_NestedTypeImplHeader_ParamsCaptured;
    [Test] procedure Parser_NestedTypeSiblings_HaveDistinctNames;
    [Test] procedure Parser_TripleQualifier_FullNameCaptured;
    [Test] procedure Parser_NestedTypeWithGenerics_QualifiersCaptured;
    [Test] procedure Parser_SingleQualifier_StillUnchanged;
    [Test] procedure Parser_DotWithoutIdent_IsBounded;
    [Test] procedure Parser_ProcTypeLocalWithCallingConv_NoPhantomVar;

    // --- Verschachtelte Typen im Klassenrumpf (2026-07-28) ---
    [Test] procedure Parser_NestedTypeInClassBody_BecomesOwnClassNode;
    [Test] procedure Parser_NestedTypeInClassBody_OuterMembersSurvive;
    [Test] procedure Parser_NestedTypeMembers_NotAttributedToOuter;
    [Test] procedure Parser_TwoNestedTypes_BothResolvable;
    [Test] procedure Parser_NestedRecordAndAlias_AreHandled;
    [Test] procedure Parser_BodylessClass_DoesNotSwallowFollowers;
    [Test] procedure Parser_BodylessClassNested_OuterSurvives;
    [Test] procedure Parser_ClassAbstractWithParents_MembersParsed;
    [Test] procedure Parser_IfdefTwinClassHeader_IsBounded;
    [Test] procedure Parser_NestedTypeWithoutTypeKeyword_IsBounded;
    [Test] procedure Parser_ObjectTwinWithVariantRecord_IsBounded;
    [Test] procedure Parser_NestedProcTypeOfObject_DoesNotEatClass;
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

procedure TTestParserRobustness.Parser_KeywordMethodNameUnqualified_Captured;
// Real-World FP-Audit 2026-07-12 (SCA028): 'Exit' ist eine Standard-Routine,
// KEIN reserviertes Wort -> darf Methoden-/Event-Handler-Name sein. Der Lexer
// tokenisiert 'exit' als tkKwExit; der Parser muss es an der Namens-Position
// (direkt nach 'procedure') dennoch als Methoden-Namen erfassen.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure Exit(Sender: TObject);'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.';
var Parser: TParser2; Root, ImplN: TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      Assert.AreEqual('Exit', TopLevelMethodNames(ImplN),
        'keyword-benannte Methode Exit muss als nkMethod erfasst werden');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_KeywordMethodNameQualified_Captured;
// Qualifizierte Implementierung 'procedure TForm1.Exit(...)': nach dem '.' steht
// wieder tkKwExit -> muss ebenfalls als Namensteil erfasst werden (der Binder
// braucht 'TForm1.Exit', damit das DFM-Event 'Exit' aufloest -> kein SCA028-FP).
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TForm1.Exit(Sender: TObject);'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.';
var Parser: TParser2; Root, ImplN: TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      Assert.AreEqual('TForm1.Exit', TopLevelMethodNames(ImplN),
        'qualifizierte keyword-benannte Methode muss als nkMethod erfasst werden');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_InlineConst_EmitsConstSectionField;
// Mechanismus A: 'const X = 42;' im Anweisungsteil wird jetzt geparst und -
// wie eine lokale const-SEKTION - als nkConstSection -> nkField abgelegt
// (TypeRef '=42', Typ leer). Vorher entstand ein Phantom-nkCall('X').
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  const Limit = 42;'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.';
var
  P    : TParser2;
  Root : TAstNode;
  Secs : TList<TAstNode>;
  Fld  : TAstNode;
begin
  P := TParser2.Create;
  try
    Root := P.ParseSource(SRC);
    try
      Secs := Root.FindAll(nkConstSection);
      try
        Assert.IsTrue(Secs.Count >= 1,
          'Inline-const muss eine nkConstSection erzeugen');
        Fld := nil;
        for var S in Secs do
          for var C in S.Children do
            if (C.Kind = nkField) and SameText(C.Name, 'Limit') then Fld := C;
        Assert.IsNotNull(Fld, 'nkField Limit erwartet');
        Assert.IsTrue(Pos('42', Fld.TypeRef) > 0,
          'TypeRef muss den Wert tragen, ist: ' + Fld.TypeRef);
      finally Secs.Free; end;
      // Der Folge-Call darf NICHT verschluckt worden sein (Token-Sync).
      Assert.IsTrue(Root.DescendantCount(nkCall) >= 1,
        'Anweisung nach der Inline-const fehlt im AST');
    finally Root.Free; end;
  finally P.Free; end;
end;

procedure TTestParserRobustness.Parser_InlineConst_TypedEmitsTypeAndValue;
// Typisierte Form: TypeRef traegt '<Typ>=<Wert>' - dieselbe Konvention wie
// im Sektionspfad (ParseVarLikeSection), damit const-aufloesende Detektoren
// (uFormatMismatch, uNamingExt) Inline-Consts automatisch sehen.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  const Max: Integer = 7;'#13#10+
  'end;'#13#10+
  'end.';
var
  P    : TParser2;
  Root : TAstNode;
  Secs : TList<TAstNode>;
  Ref  : string;
begin
  P := TParser2.Create;
  try
    Root := P.ParseSource(SRC);
    try
      Ref := '';
      Secs := Root.FindAll(nkConstSection);
      try
        for var S in Secs do
          for var C in S.Children do
            if (C.Kind = nkField) and SameText(C.Name, 'Max') then Ref := C.TypeRef;
      finally Secs.Free; end;
      Assert.IsTrue(Pos('=', Ref) > 0,
        'TypeRef muss Typ und Wert per Gleichheitszeichen trennen, ist: ' + Ref);
      Assert.IsTrue(Pos('Integer', Ref) > 0,
        'Typtext fehlt in TypeRef, ist: ' + Ref);
      Assert.IsTrue(Pos('7', Ref) > 0,
        'Wert fehlt in TypeRef, ist: ' + Ref);
    finally Root.Free; end;
  finally P.Free; end;
end;

procedure TTestParserRobustness.Parser_InlineConst_SemicolonInStringKeepsSync;
// Semikolon IM String-Literal darf den RHS-Scan nicht beenden. End-to-End:
// der Leak NACH der Inline-const muss weiterhin gefunden werden.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure Foo;'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  const Sep = ''a;b'';'#13#10+
  '  L := TStringList.Create;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak nach Inline-const mit Semikolon im String muss gefunden werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_InlineConst_ParenAndArrayKeepSync;
// Klammer- und Array-Initializer (die ';'-in-Klammern-Faelle) duerfen den
// Scan ebenfalls nicht abschneiden - Folgeanweisung bleibt sichtbar.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure Foo;'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  const A: array[0..1] of Integer = (1, 2);'#13#10+
  '  L := TStringList.Create;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak nach Array-Inline-const muss gefunden werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_InlineConst_MissingEqualsIsBounded;
// Kaputte Quelle (kein '='): der Arm darf nicht haengen und nicht den Rest
// der Routine schreddern - der Leak danach bleibt auffindbar.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure Foo;'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  const Broken 5;'#13#10+
  '  L := TStringList.Create;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'kaputte Inline-const darf den Parser nicht desynchronisieren');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_InlineConst_TypedNoLongerHidesDeadCode;
// DER EIGENTLICHE VORHER-SCHADEN (Review 2026-07-26): eine TYPISIERTE
// Inline-const lief in den Label-Pfad (ParsePrimary stoppt vor ':',
// IsSimpleLabelName trifft) und schrieb die Zeile in FLabelLines. Ueber
// nkLabelMark hielt uDeadCode (SCA011) sie fuer ein goto-Sprungziel und
// unterdrueckte ECHTE Dead-Code-Funde. Jetzt muss der Code nach Exit
// wieder gemeldet werden.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  const Flag: Integer = 1;'#13#10+
  '  Exit;'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkDeadCode) >= 1,
      'toter Code nach Exit muss trotz typisierter Inline-const gemeldet werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_LocalConstSection_StillParsedAsBefore;
// Nicht-Regressions-Anker: eine echte const-SEKTION im Deklarationsteil
// laeuft weiterhin ueber ParseLocalVarSection (nicht ueber den neuen Arm) -
// beide Eintraege muessen als nkField unter nkConstSection erscheinen.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure Foo;'#13#10+
  'const'#13#10+
  '  Alpha = 1;'#13#10+
  '  Beta = 2;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.';
var
  P    : TParser2;
  Root : TAstNode;
  Secs : TList<TAstNode>;
  Cnt  : Integer;
begin
  P := TParser2.Create;
  try
    Root := P.ParseSource(SRC);
    try
      Cnt := 0;
      Secs := Root.FindAll(nkConstSection);
      try
        for var S in Secs do
          for var C in S.Children do
            if C.Kind = nkField then Inc(Cnt);
      finally Secs.Free; end;
      Assert.AreEqual<Integer>(2, Cnt,
        'const-Sektion muss weiterhin beide Eintraege liefern');
    finally Root.Free; end;
  finally P.Free; end;
end;

{ ---- Nested-Type-Implementierungs-Header (2026-07-27) ----

  Delphi erlaubt Typen innerhalb von Typen. Deren Implementierungs-Header
  tragen ZWEI Qualifizierer: 'procedure TOuter.TInner.DoIt;'. Der Parser
  konsumierte frueher nur den ersten Punkt - die Methode hiess dann
  'TOuter.TInner' und der Rest blieb im Tokenstrom liegen. Korpus-Zensus
  2026-07-27: 2951 solcher Header in 91 Dateien.                          }

// Liefert die Anzahl der nkParam-Kinder der ersten Methode der impl-Sektion.
function FirstMethodParamCount(ImplN: TAstNode): Integer;
var
  C, P : TAstNode;
begin
  Result := -1;
  if ImplN = nil then Exit;
  for C in ImplN.Children do
    if C.Kind = nkMethod then
    begin
      Result := 0;
      for P in C.Children do
        if P.Kind = nkParam then Inc(Result);
      Exit;
    end;
end;

procedure TTestParserRobustness.Parser_NestedTypeImplHeader_FullNameCaptured;
// Der Methodenname muss ALLE Qualifizierer tragen. Sonst greift der
// Decl-gegen-Impl-Abgleich in uCanBeClassMethod ins Leere (SCA148).
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TOuter.TInner.DoIt;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.';
var Parser: TParser2; Root, ImplN: TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      Assert.AreEqual('TOuter.TInner.DoIt', TopLevelMethodNames(ImplN),
        'beide Qualifizierer muessen im Methodennamen stehen');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_NestedTypeImplHeader_ParamsCaptured;
// Der zweite, unauffaelligere Schaden: weil nach dem abgebrochenen Namen ein
// tkDot statt der Klammer stand, lief Eat(tkLParen) ins Leere und SAEMTLICHE
// Parameter fehlten im AST. 16 Detektoren lesen nkParam.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TOuter.TInner.DoIt(const A: string; B: Integer);'#13#10+
  'begin'#13#10+
  'end;'#13#10+
  'end.';
var Parser: TParser2; Root: TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Assert.AreEqual<Integer>(2, FirstMethodParamCount(ImplNodeOf(Root)),
        'Parameter einer nested-type-Methode muessen im AST landen');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_NestedTypeSiblings_HaveDistinctNames;
// Frueher trugen ALLE Methoden derselben nested class denselben Namen
// ('TOuter.TInner') - Namens-basierte Zuordnungen kollidierten dadurch.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TOuter.TInner.First;'#13#10+
  'begin'#13#10+
  'end;'#13#10+
  'procedure TOuter.TInner.Second;'#13#10+
  'begin'#13#10+
  'end;'#13#10+
  'end.';
var Parser: TParser2; Root: TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Assert.AreEqual('TOuter.TInner.First,TOuter.TInner.Second',
        TopLevelMethodNames(ImplNodeOf(Root)),
        'Geschwister einer nested class muessen unterscheidbar bleiben');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_TripleQualifier_FullNameCaptured;
// Zwei Ebenen Schachtelung kommen real vor (Korpus: 539 Header mit drei
// Punkten, 96 mit vier).
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TA.TB.TC.Run;'#13#10+
  'begin'#13#10+
  'end;'#13#10+
  'end.';
var Parser: TParser2; Root: TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Assert.AreEqual('TA.TB.TC.Run', TopLevelMethodNames(ImplNodeOf(Root)),
        'auch drei Qualifizierer muessen vollstaendig erfasst werden');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_NestedTypeWithGenerics_QualifiersCaptured;
// Generic-Parameter duerfen an JEDEM Qualifizierer stehen und gehoeren nicht
// in den Namen.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TOuter<T>.TInner.DoIt(A: T);'#13#10+
  'begin'#13#10+
  'end;'#13#10+
  'end.';
var Parser: TParser2; Root: TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Assert.AreEqual('TOuter.TInner.DoIt',
        TopLevelMethodNames(ImplNodeOf(Root)),
        'Generic-Parameter gehoeren nicht in den Methodennamen');
      Assert.AreEqual<Integer>(1, FirstMethodParamCount(ImplNodeOf(Root)),
        'Parameter muessen auch mit Generic-Qualifizierer ankommen');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_SingleQualifier_StillUnchanged;
// Regressionswaechter: der Normalfall (ein Qualifizierer) muss sich exakt
// wie vorher verhalten - er ist 268570 von 271521 Headern im Korpus.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'function TFoo.Bar(X: Integer): string;'#13#10+
  'begin'#13#10+
  'end;'#13#10+
  'end.';
var Parser: TParser2; Root: TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Assert.AreEqual('TFoo.Bar', TopLevelMethodNames(ImplNodeOf(Root)),
        'einfach qualifizierter Header darf sich nicht veraendern');
      Assert.AreEqual<Integer>(1, FirstMethodParamCount(ImplNodeOf(Root)),
        'Parameter des Normalfalls muessen erhalten bleiben');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_DotWithoutIdent_IsBounded;
// Kaputte Quelle: Punkt ohne folgenden Bezeichner. Die Schleife darf nicht
// haengen und den Rest der Unit nicht schreddern.
//
// BEWUSST mit ZWEI Punkten formuliert. Die einfache Form 'procedure TOuter.;'
// waere vakuum-gruen: alter und neuer Code konsumieren dort exakt dieselben
// Tokens (if-Zweig bzw. erste Schleifenrunde, beide ohne Ident, beide
// SkipGenericParams, beide raus), der AST ist identisch - der Test haette also
// auch VOR dem Fix bestanden und nichts abgesichert. Erst der zweite
// Qualifizierer unterscheidet die Fassungen.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TOuter.TInner.;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'procedure TOther.Works;'#13#10+
  'begin'#13#10+
  'end;'#13#10+
  'end.';
var Parser: TParser2; Root: TAstNode; Names: string;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Names := TopLevelMethodNames(ImplNodeOf(Root));
      // Der kaputte Header darf den Namen bis zum letzten gueltigen
      // Bezeichner tragen - und die FOLGENDE Methode muss ankommen.
      Assert.IsTrue(Pos('TOuter.TInner', Names) > 0,
        'gueltiger Namensteil vor dem kaputten Punkt fehlt, Ist: ' + Names);
      Assert.IsTrue(Pos('TOther.Works', Names) > 0,
        'Methode nach dem kaputten Header fehlt, Ist: ' + Names);
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_ProcTypeLocalWithCallingConv_NoPhantomVar;
// Eine lokale Variable mit prozeduralem Typ traegt die Aufrufkonvention
// HINTER dem Semikolon des Typs:
//   LBlock: procedure(p: Integer); cdecl;
// Der Typ-Scan endet an diesem ';', und die naechste Runde der var-Sektion
// sah 'cdecl' als Bezeichner - es entstand eine typlose Phantom-Variable
// dieses Namens, die SCA166 als uninitialisiert meldete (Korpuslauf
// 2026-07-27: drei Error-Tier-Funde in Alcinoe.FMX.WebBrowser).
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure Foo;'#13#10+
  'var'#13#10+
  '  LBlock: procedure(policy: Integer); cdecl;'#13#10+
  '  LReal: Integer;'#13#10+
  'begin'#13#10+
  '  LReal := 1;'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root, ImplN, M, C : TAstNode;
  Names  : string;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      M := nil;
      for C in ImplN.Children do
        if C.Kind = nkMethod then begin M := C; Break; end;
      Assert.IsNotNull(M, 'Methode fehlt');
      Names := '';
      for C in M.Children do
        if C.Kind = nkLocalVar then
        begin
          if Names <> '' then Names := Names + ',';
          Names := Names + C.Name;
        end;
      Assert.AreEqual('LBlock,LReal', Names,
        'Aufrufkonvention darf keine Phantom-Variable erzeugen, Ist: ' + Names);
    finally Root.Free; end;
  finally Parser.Free; end;
end;

{ ---- Verschachtelte Typen im Klassenrumpf (2026-07-28) ----

  'type TInner = class ... end;' innerhalb eines Klassenrumpfs. Bis zu diesem
  Fix wurde 'TInner' als Feld verdaut, und das innere 'end' beendete den
  AEUSSEREN Klassenrumpf: Member des inneren Typs galten als Member der
  Aussenklasse, alle danach deklarierten Outer-Member gingen verloren.
  Korpus-Zensus 2026-07-28: 356 Stellen in 132 Dateien.                     }

const
  SRC_NESTED =
    'unit t;'#13#10+
    'interface'#13#10+
    'type'#13#10+
    '  TOuter = class'#13#10+
    '  public'#13#10+
    '    type'#13#10+
    '      TInner = class'#13#10+
    '      public'#13#10+
    '        procedure InnerProc;'#13#10+
    '      end;'#13#10+
    '    procedure OuterProc;'#13#10+
    '    FOuterField: Integer;'#13#10+
    '  end;'#13#10+
    'implementation'#13#10+
    'end.';

// Liefert die Namen aller nkClass-Knoten, komma-getrennt und sortiert wie
// gefunden.
function ClassNames(Root: TAstNode): string;
var
  L : TList<TAstNode>;
  N : TAstNode;
begin
  Result := '';
  L := Root.FindAll(nkClass);
  try
    for N in L do
    begin
      if Result <> '' then Result := Result + ',';
      Result := Result + N.Name;
    end;
  finally L.Free; end;
end;

// Sucht den nkClass-Knoten mit dem gegebenen Namen.
function ClassByName(Root: TAstNode; const AName: string): TAstNode;
var
  L : TList<TAstNode>;
  N : TAstNode;
begin
  Result := nil;
  L := Root.FindAll(nkClass);
  try
    for N in L do
      if SameText(N.Name, AName) then Exit(N);
  finally L.Free; end;
end;

// Methodennamen eines Klassenknotens (rekursiv, wie es die Detektoren tun).
function MethodNamesOf(Cls: TAstNode): string;
var
  L : TList<TAstNode>;
  N : TAstNode;
begin
  Result := '';
  if Cls = nil then Exit;
  L := Cls.FindAll(nkMethod);
  try
    for N in L do
    begin
      if Result <> '' then Result := Result + ',';
      Result := Result + N.Name;
    end;
  finally L.Free; end;
end;

procedure TTestParserRobustness.Parser_NestedTypeInClassBody_BecomesOwnClassNode;
// Der innere Typ muss ein eigener nkClass-Knoten sein - sonst findet ihn
// keine Klassenaufloesung, und mehrere Detektor-Guards laufen ins Leere.
var Parser: TParser2; Root: TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC_NESTED);
    try
      Assert.IsNotNull(ClassByName(Root, 'TInner'),
        'verschachtelter Typ muss als eigener nkClass-Knoten erscheinen, '
        + 'gefunden: ' + ClassNames(Root));
      Assert.IsNotNull(ClassByName(Root, 'TOuter'), 'Aussenklasse fehlt');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_NestedTypeInClassBody_OuterMembersSurvive;
// Der eigentliche Schaden: das innere 'end' beendete den aeusseren Rumpf,
// wodurch ALLES danach verloren ging.
var Parser: TParser2; Root: TAstNode; Outer: TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC_NESTED);
    try
      Outer := ClassByName(Root, 'TOuter');
      Assert.IsNotNull(Outer, 'Aussenklasse fehlt');
      Assert.IsTrue(Pos('OuterProc', MethodNamesOf(Outer)) > 0,
        'nach dem verschachtelten Typ deklarierte Methode fehlt, Ist: '
        + MethodNamesOf(Outer));
      // BEWUSST auf den Namen pruefen, nicht auf HasDescendant(nkField):
      // der ALTE Parser machte den Bezeichner 'TInner' selbst zum nkField
      // von TOuter - ein anonymer Feld-Existenz-Check waere also auch vor
      // dem Fix gruen gewesen (vakuum-gruen, 5-Tage-Review 2026-07-28).
      var HasNamed := False;
      var Flds := Outer.FindAll(nkField);
      try
        for var FN in Flds do
          if SameText(FN.Name, 'FOuterField') then HasNamed := True;
      finally Flds.Free; end;
      Assert.IsTrue(HasNamed,
        'nach dem verschachtelten Typ deklariertes Feld FOuterField fehlt');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_NestedTypeMembers_NotAttributedToOuter;
// Gegenprobe zum Ablageort: der innere Typ haengt als GESCHWISTER in der
// Typsektion, nicht unter der Aussenklasse. Sonst zaehlten neun Detektoren,
// die rekursiv ueber einen Klassenknoten laufen, InnerProc als Member von
// TOuter.
var Parser: TParser2; Root: TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC_NESTED);
    try
      Assert.AreEqual<Integer>(0,
        Pos('InnerProc', MethodNamesOf(ClassByName(Root, 'TOuter'))),
        'Member des inneren Typs duerfen der Aussenklasse nicht zugerechnet '
        + 'werden, Ist: ' + MethodNamesOf(ClassByName(Root, 'TOuter')));
      Assert.IsTrue(Pos('InnerProc', MethodNamesOf(ClassByName(Root, 'TInner'))) > 0,
        'InnerProc muss beim inneren Typ liegen');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_TwoNestedTypes_BothResolvable;
// Vor dem Fix existierte der ERSTE verschachtelte Typ gar nicht und alle
// FOLGENDEN landeten versehentlich auf Unit-Ebene. Genau diese Asymmetrie
// hat einen Detektor-Guard der Vorwelle unterlaufen - beide muessen jetzt
// gleich behandelt werden.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TOuter = class'#13#10+
  '  public'#13#10+
  '    type'#13#10+
  '      TFirst = class'#13#10+
  '        procedure Alpha;'#13#10+
  '      end;'#13#10+
  '    type'#13#10+
  '      TSecond = class'#13#10+
  '        procedure Beta;'#13#10+
  '      end;'#13#10+
  '    procedure OuterProc;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var Parser: TParser2; Root: TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Assert.IsNotNull(ClassByName(Root, 'TFirst'),
        'erster verschachtelter Typ fehlt, gefunden: ' + ClassNames(Root));
      Assert.IsNotNull(ClassByName(Root, 'TSecond'),
        'zweiter verschachtelter Typ fehlt, gefunden: ' + ClassNames(Root));
      Assert.IsTrue(Pos('OuterProc', MethodNamesOf(ClassByName(Root, 'TOuter'))) > 0,
        'Outer-Methode nach zwei verschachtelten Typen fehlt');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_NestedRecordAndAlias_AreHandled;
// record als verschachtelter Typ -> nkRecord; ein blosser Alias erzeugt
// keinen Knoten, darf den Rumpf aber auch nicht zerlegen.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TOuter = class'#13#10+
  '  public'#13#10+
  '    type'#13#10+
  '      TRec = record'#13#10+
  '        A: Integer;'#13#10+
  '      end;'#13#10+
  '      TAlias = Integer;'#13#10+
  '    procedure OuterProc;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  Recs   : TList<TAstNode>;
  Found  : Boolean;
  N      : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Found := False;
      Recs := Root.FindAll(nkRecord);
      try
        for N in Recs do
          if SameText(N.Name, 'TRec') then Found := True;
      finally Recs.Free; end;
      Assert.IsTrue(Found, 'verschachtelter record muss ein nkRecord werden');
      Assert.IsTrue(Pos('OuterProc', MethodNamesOf(ClassByName(Root, 'TOuter'))) > 0,
        'Alias oder record duerfen den Klassenrumpf nicht abschneiden');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_BodylessClass_DoesNotSwallowFollowers;
// 'EFoo = class(Exception);' - rumpflose Klasse, Standard-Idiom fuer
// Exception-Ableitungen. Ohne den Semikolon-Ausstieg parste ParseClassBody
// einen Phantom-Rumpf; seit der nested-type-Rekursion frass der das gesamte
// Interface bis zum ersten Methoden-'end' (Korpus 2026-07-28: -37164 Funde
// in 642 Dateien, VirtualTrees.pas verlor ALLE rumpfbasierten Funde).
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  EProbeError = class(Exception);'#13#10+
  '  PInt = ^Integer;'#13#10+
  '  TRec = record'#13#10+
  '    A: Integer;'#13#10+
  '  end;'#13#10+
  '  TWorker = class'#13#10+
  '  public'#13#10+
  '    procedure Run(P: TObject);'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure TWorker.Run(P: TObject);'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  ImplN, M, C : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Assert.IsNotNull(ClassByName(Root, 'EProbeError'),
        'rumpflose Klasse muss als nkClass existieren');
      Assert.IsNotNull(ClassByName(Root, 'TWorker'),
        'Folgeklasse wurde vom Phantom-Rumpf verschluckt, gefunden: '
        + ClassNames(Root));
      // Und die Implementation muss ihren Rumpf behalten haben.
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      M := nil;
      for C in ImplN.Children do
        if (C.Kind = nkMethod) and SameText(C.Name, 'TWorker.Run') then M := C;
      Assert.IsNotNull(M, 'Methoden-Implementierung fehlt im AST');
      Assert.IsTrue(M.HasChild(nkBlock),
        'Methodenrumpf fehlt - Interface-Entgleisung frisst die Implementation');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_BodylessClassNested_OuterSurvives;
// Dieselbe Kurzform als verschachtelter Typ im Klassenrumpf.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TOuter = class'#13#10+
  '  public'#13#10+
  '    type'#13#10+
  '      EInnerError = class(Exception);'#13#10+
  '    procedure OuterProc;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var Parser: TParser2; Root: TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Assert.IsNotNull(ClassByName(Root, 'EInnerError'),
        'rumpflose nested class muss als nkClass existieren');
      Assert.IsTrue(Pos('OuterProc', MethodNamesOf(ClassByName(Root, 'TOuter'))) > 0,
        'Outer-Member nach der rumpflosen nested class fehlt');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_ClassAbstractWithParents_MembersParsed;
// 'class abstract(TBase)' / 'class sealed(TBase)' - die Modifier stehen VOR
// der Elternliste und sind UNGLEICH tokenisiert: 'abstract' ist ein echtes
// Keyword (tkKwAbstract), 'sealed' ein tkIdent. Beide Pfade muessen den
// Modifier konsumieren, sonst wird er zum Pseudo-Feld und die Elternliste
// landet im Else-Churn (TypeRef leer). Der erste Wurf dieses Fixes pruefte
// nur tkIdent - der Test hier war prompt rot.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TBase = class'#13#10+
  '  end;'#13#10+
  '  TAbs = class abstract(TBase)'#13#10+
  '  public'#13#10+
  '    procedure Muss;'#13#10+
  '  end;'#13#10+
  '  TSeal = class sealed(TBase)'#13#10+
  '  public'#13#10+
  '    procedure Auch;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var Parser: TParser2; Root: TAstNode; Cls: TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Cls := ClassByName(Root, 'TAbs');
      Assert.IsNotNull(Cls, 'class abstract fehlt als nkClass');
      Assert.IsTrue(Pos('TBase', Cls.TypeRef) > 0,
        'Elternklasse muss trotz abstract-Modifier in TypeRef stehen, Ist: '
        + Cls.TypeRef);
      Assert.IsTrue(Pos('Muss', MethodNamesOf(Cls)) > 0,
        'Member der abstract-Klasse fehlen');
      Cls := ClassByName(Root, 'TSeal');
      Assert.IsNotNull(Cls, 'class sealed fehlt als nkClass');
      Assert.IsTrue(Pos('TBase', Cls.TypeRef) > 0,
        'Elternklasse muss trotz sealed-Modifier in TypeRef stehen, Ist: '
        + Cls.TypeRef);
      Assert.IsTrue(Pos('Auch', MethodNamesOf(Cls)) > 0,
        'Member der sealed-Klasse fehlen');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_IfdefTwinClassHeader_IsBounded;
// IFDEF-Twin-Klassenkopf (VirtualTrees.pas-Muster): der Lexer emittiert
// BEIDE Zweige, der zweite Kopf steht scheinbar im Rumpf des ersten. Die
// nested-type-Rekursion darf ihn NICHT schlucken (sie schluckte sonst den
// echten Rumpf samt 'end;' und der Phantom-Rumpf frass bis zur
// Implementation). Der Struktur-Waechter (Rekursion nur nach 'type')
// begrenzt den Schaden aufs Vor-Welle-2b-Niveau: EIN gemergter Twin-Knoten,
// die Folgeklasse und die Implementation bleiben intakt.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  {$IFDEF X}'#13#10+
  '  TVTEdit = class(TFirstBase)'#13#10+
  '  {$ELSE}'#13#10+
  '  TVTEdit = class(TSecondBase)'#13#10+
  '  {$ENDIF}'#13#10+
  '  private'#13#10+
  '    FRef: Integer;'#13#10+
  '  end;'#13#10+
  '  TAfterTwin = class'#13#10+
  '  public'#13#10+
  '    procedure Danach;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure TAfterTwin.Danach;'#13#10+
  'begin'#13#10+
  '  if Self <> nil then'#13#10+
  '    Beep;'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  ImplN, M, C : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Assert.IsNotNull(ClassByName(Root, 'TAfterTwin'),
        'Klasse nach dem IFDEF-Twin fehlt - Phantom-Rumpf hat gefressen, '
        + 'gefunden: ' + ClassNames(Root));
      ImplN := ImplNodeOf(Root);
      Assert.IsNotNull(ImplN, 'implementation-Node fehlt');
      M := nil;
      for C in ImplN.Children do
        if (C.Kind = nkMethod) and SameText(C.Name, 'TAfterTwin.Danach') then
          M := C;
      Assert.IsNotNull(M, 'Implementierung nach dem Twin fehlt im AST');
      Assert.IsTrue(M.HasChild(nkBlock), 'Methodenrumpf nach dem Twin fehlt');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_NestedTypeWithoutTypeKeyword_IsBounded;
// Gegenprobe zum Struktur-Waechter: ein 'Ident = class'-Kopf im Klassenrumpf
// OHNE vorangehendes 'type' (grammatisch dort unmoeglich, praktisch ein
// Twin- oder Fehlerartefakt) darf KEINEN Geschwister-Typknoten erzeugen -
// und den Rumpf trotzdem nicht zerlegen.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TOuter = class'#13#10+
  '  public'#13#10+
  '    FEcht: Integer;'#13#10+
  '    TPhantom = class(TBase)'#13#10+
  '    procedure OuterProc;'#13#10+
  '  end;'#13#10+
  '  TDanach = class'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var Parser: TParser2; Root: TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Assert.IsNull(ClassByName(Root, 'TPhantom'),
        'ohne type-Sektion darf kein Geschwister-Typknoten entstehen');
      Assert.IsNotNull(ClassByName(Root, 'TDanach'),
        'Folgeklasse fehlt - der Waechter hat den Schaden nicht begrenzt, '
        + 'gefunden: ' + ClassNames(Root));
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_ObjectTwinWithVariantRecord_IsBounded;
// Das mORMot-quickjs-Muster (USERECORDWITHMETHODS), das after108 noch
// zerlegte: record/object-IFDEF-Twin, dessen gemeinsamer Rumpf mit einem
// VARIANTEN anonymen Record-Feld beginnt. Der Twin-Skip war token-blind,
// stoppte am ';' in der ersten Variantenklammer, und deren inneres 'end'
// schloss den aeusseren Typ - die restliche Interface-Sektion (im Original
// -30 externe Deklarationen) riss mit. Jetzt: Twin-Kopf wird nur noch als
// Kopf konsumiert, der Rumpf gehoert der aeusseren Schleife.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  JSValueRaw = record'#13#10+
  '    u: Double;'#13#10+
  '  end;'#13#10+
  '  {$ifdef USERECORDWITHMETHODS}'#13#10+
  '  JSValue = record'#13#10+
  '  {$else}'#13#10+
  '  JSValue = object'#13#10+
  '  {$endif}'#13#10+
  '  private'#13#10+
  '    u: record'#13#10+
  '      case byte of'#13#10+
  '        0:'#13#10+
  '          (i32,'#13#10+
  '           tag: integer);'#13#10+
  '        1:'#13#10+
  '          (f64: Double);'#13#10+
  '      end;'#13#10+
  '  public'#13#10+
  '    function TagInt: integer;'#13#10+
  '  end;'#13#10+
  'function js_lowercase_probe(ctx: integer): integer;'#13#10+
  '  cdecl; external ''qj.dll'';'#13#10+
  'implementation'#13#10+
  'function JSValue.TagInt: integer;'#13#10+
  'begin'#13#10+
  '  Result := 0;'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  Meths  : TList<TAstNode>;
  M      : TAstNode;
  DeclOk, ImplOk : Boolean;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      DeclOk := False;
      ImplOk := False;
      Meths := Root.FindAll(nkMethod);
      try
        for M in Meths do
        begin
          if SameText(M.Name, 'js_lowercase_probe') then DeclOk := True;
          if SameText(M.Name, 'JSValue.TagInt') and M.HasChild(nkBlock) then
            ImplOk := True;
        end;
      finally Meths.Free; end;
      Assert.IsTrue(DeclOk,
        'Deklaration nach dem object-Twin fehlt - Varianten-end hat den '
        + 'Typ vorzeitig geschlossen');
      Assert.IsTrue(ImplOk,
        'Methodenrumpf der Twin-Struktur fehlt im AST');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_NestedProcTypeOfObject_DoesNotEatClass;
// Methodenzeiger-Typ in einer nested type-Sektion:
//   type TEvent = function(const A: TObject): Boolean of object;
// 'of object' oeffnet KEINEN Rumpf. Der balancierte Wert-Skip zaehlte
// 'object' zunaechst als Rumpf-Oeffner - das ';' terminierte nie, der Skip
// frass bis zu einem fremden 'end' und riss die Klasse mit (after109:
// 70 Dateien, Alcinoe.Localization 647->0). Alcinoe-Muster.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TOuter = class'#13#10+
  '  public'#13#10+
  '    type'#13#10+
  '      TCheckEvent = function(const Sender: TObject): Boolean of object;'#13#10+
  '      TInner = class'#13#10+
  '      public'#13#10+
  '        procedure InnerProc;'#13#10+
  '      end;'#13#10+
  '    procedure OuterProc;'#13#10+
  '  end;'#13#10+
  '  TDanach = class'#13#10+
  '  public'#13#10+
  '    procedure Folge;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var Parser: TParser2; Root: TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Assert.IsTrue(Pos('OuterProc', MethodNamesOf(ClassByName(Root, 'TOuter'))) > 0,
        'Member nach dem of-object-Alias fehlt - Skip hat die Klasse gefressen');
      Assert.IsNotNull(ClassByName(Root, 'TInner'),
        'nested class nach dem of-object-Alias fehlt, gefunden: '
        + ClassNames(Root));
      Assert.IsNotNull(ClassByName(Root, 'TDanach'),
        'Folgeklasse fehlt, gefunden: ' + ClassNames(Root));
    finally Root.Free; end;
  finally Parser.Free; end;
end;

end.

unit uTestParserRobustness;

// Tests fuer Parser-Robustheit gegen Real-World-mORMot2-Konstrukte.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uAstNode, uParser2,
  uDetectorUtils,   // ContainsWholeWordLower (Escaped-Identifier-Test)
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
    // ---- Attribute in Parameter-Position (Backlog 4e #4, 2026-08-01) ----
    [Test] procedure Parser_ParamAttribute_NoPhantomParam;
    [Test] procedure Parser_ParamAttributeBeforeModifier_NoPhantomParam;
    [Test] procedure Parser_ParamAttributeWithArgs_TypeStillCaptured;
    [Test] procedure Parser_UnbalancedParamAttribute_DoesNotEatDeclaration;
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
    // T2b (Review 2026-07-30): Generic-Argumente der Elternliste gehoeren
    // NICHT in TypeRef - 'TObjectList TItem' sah aus wie Basis+Interface.
    [Test] procedure Parser_GenericParentArgs_NotInTypeRef;
    // T3 (2026-07-31): Generic-Call-Statement darf seine Argumente nicht
    // verlieren - 'SetValue<T>(FColor, AValue);' brach an tkLt ab.
    [Test] procedure Parser_GenericCallStatement_KeepsArgs;
    // Parser-Inkrement 2026-07-31: zwei Abbruch-Ursachen, die in 121
    // Korpusdateien den Rest der Unit fuer ALLE AST-Detektoren
    // unsichtbar machten.
    [Test] procedure Parser_AttributeBeforeTypeDecl_SectionSurvives;
    [Test] procedure Parser_EscapedIdentifier_DoesNotCloseInterface;
    // Gate-Nachtrag: MEMBER-Attribute erzeugten Phantom-Felder
    // (275 der 792 neuen GodClass-Funde feuerten nur deswegen).
    [Test] procedure Parser_MemberAttribute_NoPhantomField;
    // G1-2 (Review 2026-08-25): typisierte Record-Konstante in einer
    // const-SEKTION. Die flache Wert-Schleife stoppte am ';' INNERHALB
    // der Klammer - abgeschnittener Wert plus ein Phantom-nkField je
    // weiterem Record-Element.
    [Test] procedure Parser_TypedRecordConst_NoPhantomFields;
    // R5 (finales Review 2026-08-25): unvollstaendige Klammer im
    // Konstantenwert (Live-Editieren) darf nicht den Rest der Unit
    // fressen - implementation und alle Methoden muessen im AST bleiben.
    [Test] procedure Parser_UnclosedConstParen_DoesNotEatUnit;
    // Upstream-Bericht Ian Branch 2026-08-27: Positions-Drift in der
    // Namenslisten-Fortsetzung. Prueft die ZEILE, nicht den Fund -
    // genau die Luecke, durch die der Defekt gerutscht ist.
    [Test] procedure VarNameList_WithContextKeyword_KeepsOwnLine;

    // ---- case-else vs. if-else (Parserfix 2026-08-28) ------------------
    // ParseIfStmt pruefte nach dem then-Zweig bedingungslos auf
    // 'else' und wusste nicht, ob die then-Anweisung ihr ';' schon
    // geschluckt hatte. Ein case-else wurde dadurch zum else des ifs im
    // LETZTEN ARM (Korpus: 151 Stellen in 120 Dateien, Beleg
    // cnwizards .../DCU32/op.pas:509 mit Exit statt raise).
    //
    // Diese Tests assertieren STRUKTUR UND POSITION, nicht Fundzahlen:
    // die Upstream-Lehre vom 2026-08-27 war, dass fundzahl-basierte Tests
    // einen reinen Positionsdefekt gruen liessen.
    [Test] procedure CaseElse_AfterArmIfThenExit_IsCaseArmNotElseBranch;
    [Test] procedure CaseElse_AfterArmIfThenRaise_IsCaseArmNotElseBranch;
    [Test] procedure CaseElse_RealIfElseInLastArm_KeepsItsElseBranch;
    [Test] procedure CaseElse_MultiStatementBody_AllStatementsInAst;
    [Test] procedure ExceptElse_AfterOnHandlerIf_BelongsToExceptBlock;
    [Test] procedure IfThenEmptyStatement_ElseStillBindsToIf;
    [Test] procedure CaseElse_AfterVariousSemicolonEatingArms_NoElseBranch;
    // Verschachtelte ';'-Fresser als then-Anweisung des Arm-ifs: ein case
    // und ein try fressen ihr ';' erst NACH ihrem eigenen 'end'. Beide
    // Rahmen stellen den Taker-Zustand des Arms wieder her.
    [Test] procedure CaseElse_AfterArmIfWithNestedCaseOrTry_NoElseBranch;
    // Der abgelehnte else darf den Rumpf NICHT kosten: alles was nach dem
    // case in derselben Methode steht, muss im AST bleiben.
    [Test] procedure CaseElse_RejectedElse_RestOfMethodBodyIntact;

    // ---- Leerer case-Arm (01.09.) ---------------------------------------
    // 'X: ;' hat keine Anweisung. Vor dem Fix frass die Leeranweisungs-
    // Schleife von ParseStatement das ';' des Arms, und der FOLGENDE Arm
    // wurde zum Rumpf des leeren Arms - beim Folge-Arm mit Label-LISTE
    // sogar restlos verschluckt. Beleg Abbrevia AbGzTyp.pas:1152.
    [Test] procedure CaseArm_EmptyArm_FollowingArmKeepsOwnStatement;
    [Test] procedure CaseArm_EmptyArmBeforeBlockArm_NoPhantomLeak;

    // ---- Bedingte Kompilierung: das ';'-vor-else-Idiom ------------------
    // GEGENPROBE zum Fix oben. Der Lexer verwirft '{...}' samt Direktiven
    // als Kommentar und emittiert im Default BEIDE Zweige - das Idiom
    //   end {$IFDEF X} ; {$ELSE} else Foo; {$ENDIF}
    // erzeugt also den Tokenstrom 'end ; else Foo ;'. Das ist ein ECHTES
    // if-else mit einem ';' davor; im Quelltext hat E2029 nie gegriffen.
    // Korpus: JsonDataObjects.pas:7627/:8242 (3 Kopien) + JvCsvData.pas:3743
    // = 7 Stellen auf D:\git-sca-realworld, alle auf Methodenrumpf-Ebene.
    // Die geschweiften Klammern stehen in den Tests IN STRINGLITERALEN -
    // sonst waeren sie Direktiven DIESER Datei statt Testdaten.
    [Test] procedure IfdefSemicolonElse_AtBodyLevel_ElseBindsToIf;
    [Test] procedure IfdefSemicolonElse_InCaseArmBlock_ElseBindsToIf;
    // BENANNTE RESTLUECKE, bewusst festgenagelt: direkt in einem case-Arm
    // ist das Idiom im Tokenstrom nicht von einem echten case-else zu
    // unterscheiden. Der Test haelt fest, dass der Schaden eine
    // FEHLZUORDNUNG ist - und kein Token-Verlust.
    [Test] procedure IfdefSemicolonElse_DirectlyInCaseArm_KnownGap_NothingLost;
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

procedure TTestParserRobustness.Parser_GenericParentArgs_NotInTypeRef;
// T2b (Review 2026-07-30): der Eltern-Loop sammelte Generic-Argumente als
// eigene space-getrennte Eintraege - 'class(TObjectList<TItem>)' wurde
// TypeRef 'TObjectList TItem' und war fuer Konsumenten nicht von
// 'Basis + Interface' unterscheidbar (uUnusedParameter-FN-Restklasse aus
// 86cd02f). Jetzt konsumiert der Generic-Zweig des Eltern-Loops die
// Argumente balanciert (BEWUSST kein SkipGenericParams: die Idents
// muessen als nkGenericArgs-Marker erhalten bleiben, siehe unten) -
// auch verschachtelt ('TDictionary<string, TList<TItem>>', '>>' sind
// ZWEI tkGt) und bei generischen Interfaces ('IComparer<TItem>').
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TGen = class(TObjectList<TItem>)'#13#10+
  '  public'#13#10+
  '    procedure MussEins;'#13#10+
  '  end;'#13#10+
  '  TMulti = class(TDictionary<string, TList<TItem>>, IComparer<TItem>)'#13#10+
  '  public'#13#10+
  '    procedure MussZwei;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var Parser: TParser2; Root: TAstNode; Cls: TAstNode; GArgs: string;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Cls := ClassByName(Root, 'TGen');
      Assert.IsNotNull(Cls, 'TGen fehlt als nkClass');
      Assert.AreEqual<string>('TObjectList', Cls.TypeRef,
        'Generic-Args duerfen nicht als eigene Parents auftauchen');
      Assert.IsTrue(Pos('MussEins', MethodNamesOf(Cls)) > 0,
        'Member nach generischer Elternliste fehlen');
      // Uses-Nachweis: die Argument-Idents muessen als nkGenericArgs-
      // Marker erhalten bleiben (uUnusedUses erntet Name aller Knoten -
      // sonst verloere 'uses uX' seinen Beleg, wenn TItem nur hier steht).
      GArgs := '';
      for var Ch in Cls.Children do
        if Ch.Kind = nkGenericArgs then GArgs := GArgs + '|' + Ch.Name;
      Assert.AreEqual<string>('|TItem', GArgs,
        'TGen: Argument-Ident muss als nkGenericArgs-Marker haengen');
      Cls := ClassByName(Root, 'TMulti');
      Assert.IsNotNull(Cls, 'TMulti fehlt als nkClass');
      Assert.AreEqual<string>('TDictionary IComparer', Cls.TypeRef,
        'verschachtelte Args + generisches Interface muessen zu genau ' +
        'zwei Eintraegen kollabieren');
      Assert.IsTrue(Pos('MussZwei', MethodNamesOf(Cls)) > 0,
        'Member nach mehrteiliger generischer Elternliste fehlen');
      GArgs := '';
      for var Ch in Cls.Children do
        if Ch.Kind = nkGenericArgs then GArgs := GArgs + '|' + Ch.Name;
      Assert.AreEqual<string>('|TList TItem|TItem', GArgs,
        'TMulti: je <...>-Block ein Marker mit den Ident-Args ' +
        '(string ist Keyword, kein Ident)');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_GenericCallStatement_KeepsArgs;
// T3 (2026-07-31): ParsePrimary brach die Suffix-Schleife an tkLt ab -
// 'SetValue<TAlphaColor>(FColor, AValue);' wurde ein argumentloses
// nkCall('SetValue') und SkipToSemicolon frass den Rest. Detektoren
// sahen 'AValue' nie als gelesen (8 belegte SCA054-FPs in den
// FMX./Vcl.Skia-Settern). Jetzt konsumiert der tkLt-Zweig das
// Generic-Suffix balanciert und der tkLParen-Zweig haengt die
// Argumente regulaer an den nkCall-Namen.
const SRC =
  'unit t;'#13#10+
  'implementation'#13#10+
  'procedure Foo(const AValue: Integer);'#13#10+
  'begin'#13#10+
  '  SetValue<TAlphaColor>(FColor, AValue);'#13#10+
  '  ProcessFields<Data.DB.TField>(List);'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  Calls  : TList<TAstNode>;
  Names  : string;
  Hit    : Boolean;
  DotHit : Boolean;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Calls := Root.FindAll(nkCall);
      try
        Hit := False;
        DotHit := False;
        Names := '';
        for var C in Calls do
        begin
          Names := Names + ' | ' + C.Name;
          if (Pos('SetValue', C.Name) > 0) and
             (Pos('AValue', C.Name) > 0) and
             (Pos('TAlphaColor', C.Name) > 0) then
            Hit := True;
          // Dotted Typargumente werden ENTPUNKTET angehaengt ('Data DB
          // TField'): 'data.' im Namen waere fuer Deref-Scanner ein
          // Phantom-Deref einer lokalen Variable Data (Review 2026-07-31).
          if (Pos('ProcessFields', C.Name) > 0) and
             (Pos('TField', C.Name) > 0) and
             (Pos('Data.', C.Name) = 0) then
            DotHit := True;
        end;
        Assert.IsTrue(Hit,
          'nkCall muss Generic-Suffix UND Argumente tragen, Ist:' + Names);
        Assert.IsTrue(DotHit,
          'dotted Typargument muss entpunktet im Namen stehen, Ist:'
          + Names);
      finally Calls.Free; end;
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_AttributeBeforeTypeDecl_SectionSurvives;
// Parser-Inkrement 2026-07-31, Ursache 1 (4.146 belegte Folge-FPs in
// 117 Korpusdateien): '[JavaSignature(...)]' vor einer Typdeklaration
// liess ParseTypeSection den ATTRIBUTNAMEN als Typnamen lesen; das
// fehlende '=' fuehrte in SkipToSemicolon (verschluckte die echte
// Deklaration) und das folgende 'function' beendete per Exit die
// gesamte Typsektion. Alles danach existierte im AST nicht mehr.
// Der Test prueft genau das: der Typ MIT Attribut und ALLE Folgetypen
// muessen im Baum stehen.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TVorher = class'#13#10+
  '  end;'#13#10+
  '  [JavaSignature(''androidx/webkit/BackForwardCacheSettings'')]'#13#10+
  '  JBackForward = interface(JObject)'#13#10+
  '    function getMaxPagesInCache: Integer; cdecl;'#13#10+
  '  end;'#13#10+
  '  [ComponentPlatforms(pidWin32 or pidWin64)]'#13#10+
  '  TMitAttribut = class'#13#10+
  '  public'#13#10+
  '    procedure MussDaSein;'#13#10+
  '  end;'#13#10+
  '  TDanach = class'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var Parser: TParser2; Root: TAstNode; Cls: TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Assert.IsNotNull(ClassByName(Root, 'TVorher'),
        'Typ VOR dem Attribut fehlt, gefunden: ' + ClassNames(Root));
      Assert.IsNotNull(ClassByName(Root, 'JBackForward'),
        'Typ MIT Attribut fehlt (Attribut als Typname gelesen?), '
        + 'gefunden: ' + ClassNames(Root));
      Cls := ClassByName(Root, 'TMitAttribut');
      Assert.IsNotNull(Cls,
        'zweiter Typ mit Attribut fehlt, gefunden: ' + ClassNames(Root));
      Assert.IsTrue(Pos('MussDaSein', MethodNamesOf(Cls)) > 0,
        'Member des Typs mit Attribut fehlen');
      Assert.IsNotNull(ClassByName(Root, 'TDanach'),
        'Folgetyp fehlt - die Typsektion wurde vorzeitig beendet, '
        + 'gefunden: ' + ClassNames(Root));
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_MemberAttribute_NoPhantomField;
// Gate-Nachtrag 2026-07-31: das Attribut-Problem gab es auf ZWEI Ebenen.
// Der Typ-Ebenen-Skip war gefixt, im Klassenrumpf fiel '[' aber weiter
// in den else-Zweig - der folgende Bezeichner landete im tkIdent-Zweig
// und wurde OHNE Doppelpunkt als FELD abgelegt. Aus
// '[MVCTable(''customers'')]' wurde also ein Phantom-nkField('MVCTable'),
// aus '[MVCHTTPMethods([httpGET])]' sogar zwei. Am Korpus gemessen:
// 275 der 792 neuen SCA138-GodClass-Funde (35%) feuerten AUSSCHLIESSLICH
// wegen solcher Phantom-Member.
// Der Test zaehlt die Felder: erwartet werden genau die zwei ECHTEN.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  [MVCTable(''customers'')]'#13#10+
  '  TCustomer = class'#13#10+
  '  private'#13#10+
  '    [MVCTableField(''id'', [foPrimaryKey])]'#13#10+
  '    FId: Integer;'#13#10+
  '    [Weak]'#13#10+
  '    FOwnerRef: TObject;'#13#10+
  '  public'#13#10+
  '    [MVCHTTPMethods([httpGET])]'#13#10+
  '    procedure Fetch;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  Cls    : TAstNode;
  Fields : TList<TAstNode>;
  Names  : string;
  Cnt    : Integer;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Cls := ClassByName(Root, 'TCustomer');
      Assert.IsNotNull(Cls, 'Klasse mit Attribut fehlt, gefunden: '
        + ClassNames(Root));
      Fields := Cls.FindAll(nkField);
      try
        Cnt := 0;
        Names := '';
        for var F in Fields do
        begin
          Inc(Cnt);
          if Names <> '' then Names := Names + ',';
          Names := Names + F.Name;
        end;
        Assert.AreEqual<Integer>(2, Cnt,
          'genau zwei ECHTE Felder erwartet (FId, FOwnerRef) - jedes '
          + 'weitere ist ein Phantom aus einem Member-Attribut, Ist: '
          + Names);
        Assert.IsTrue(Pos('FId', Names) > 0, 'FId fehlt, Ist: ' + Names);
        Assert.IsTrue(Pos('FOwnerRef', Names) > 0,
          'FOwnerRef fehlt, Ist: ' + Names);
      finally Fields.Free; end;
      Assert.IsTrue(Pos('Fetch', MethodNamesOf(Cls)) > 0,
        'Methode nach dem Attribut fehlt');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_EscapedIdentifier_DoesNotCloseInterface;
// Parser-Inkrement 2026-07-31, Ursache 2 (1.737 belegte Folge-FPs in
// 4 Korpusdateien): der Lexer kannte '&' nicht. In
// 'function &end: UITextPosition; cdecl;' wurde '&' zu tkUnknown und
// das folgende 'end' zu tkKwEnd - das schloss den Interface-Rumpf
// mitten in der Deklaration, danach entgleiste die ganze Typsektion.
// Das '&' wird verworfen, der Bezeichner ist NIE ein Keyword.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  UITextRange = interface(NSObject)'#13#10+
  '    function &end: Integer; cdecl;'#13#10+
  '    function &type: Integer; cdecl;'#13#10+
  '    function isEmpty: Boolean; cdecl;'#13#10+
  '  end;'#13#10+
  '  TDanach = class'#13#10+
  '  public'#13#10+
  '    procedure MussDaSein;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var Parser: TParser2; Root: TAstNode; Cls: TAstNode; Names: string;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Cls := ClassByName(Root, 'UITextRange');
      Assert.IsNotNull(Cls, 'Interface mit &-Bezeichnern fehlt, '
        + 'gefunden: ' + ClassNames(Root));
      Names := MethodNamesOf(Cls);
      // Der Escaped Identifier steht OHNE '&' im Baum - so wird er auch
      // referenziert ('x.&end' adressiert das Member 'end'). Wortgenau
      // pruefen: ein Substring-Test wuerde auch auf 'legend' anspringen.
      Assert.IsTrue(TDetectorUtils.ContainsWholeWordLower('end',
        LowerCase(Names)),
        'escaped Bezeichner "end" fehlt als Member, Ist: ' + Names);
      // '&type' ist mit 543 Korpus-Stellen das haeufigste Escape-Muster
      // und das einzige, das im Klassenrumpf InTypeSection umlegt (dort
      // haengt die nested-type-Rekursion dran) - deshalb eigener Assert.
      Assert.IsTrue(TDetectorUtils.ContainsWholeWordLower('type',
        LowerCase(Names)),
        'escaped Bezeichner "type" fehlt als Member, Ist: ' + Names);
      Assert.IsTrue(Pos('isEmpty', Names) > 0,
        'Member NACH dem escaped Bezeichner fehlt - der Rumpf wurde '
        + 'vorzeitig geschlossen, Ist: ' + Names);
      Cls := ClassByName(Root, 'TDanach');
      Assert.IsNotNull(Cls, 'Folgetyp fehlt - Typsektion entgleist, '
        + 'gefunden: ' + ClassNames(Root));
      Assert.IsTrue(Pos('MussDaSein', MethodNamesOf(Cls)) > 0,
        'Member des Folgetyps fehlen');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_ParamAttribute_NoPhantomParam;
// Backlog 4e #4: 'const [MVCFromBody] P: TPerson' erzeugte ZWEI nkParam -
// den echten und ein Phantom namens 'MVCFromBody' ohne Typ. Der Namens-Loop
// nimmt kein '[' an, GuardAdvance schob es weg, und im naechsten Durchlauf
// stand der Attributname wie ein Parametername da. Jeder nkParam-lesende
// Detektor sah ihn - allen voran SCA054 (ein Attributname wird nie benutzt).
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TCtrl.Post(const [MVCFromBody] P: TPerson);'#13#10+
  'begin'#13#10+
  'end;'#13#10+
  'end.';
var Parser: TParser2; Root: TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Assert.AreEqual<Integer>(1, FirstMethodParamCount(ImplNodeOf(Root)),
        'Attribut in Parameter-Position darf keinen Phantom-Parameter erzeugen');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_ParamAttributeBeforeModifier_NoPhantomParam;
// Die andere Stellung: Attribut VOR dem Modifier. Beide kommen in echtem
// Code vor, deshalb wird an beiden Stellen uebersprungen.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TCtrl.Post([Weak] const A: TObject; B: Integer);'#13#10+
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
        'Attribut vor dem Modifier darf keinen Phantom-Parameter erzeugen');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_ParamAttributeWithArgs_TypeStillCaptured;
// Attribut MIT Argumentliste - die Klammern darin duerfen den Skip nicht
// vorzeitig beenden. Danach muss der echte Parameter samt Typ stehen.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TCtrl.Post([MVCPath(''/x'', 42)] const P: TPerson);'#13#10+
  'begin'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root, ImplN, C, Prm : TAstNode;
  Found  : Boolean;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Assert.AreEqual<Integer>(1, FirstMethodParamCount(ImplN));
      Found := False;
      for C in ImplN.Children do
        if C.Kind = nkMethod then
          for Prm in C.Children do
            if Prm.Kind = nkParam then
            begin
              Assert.AreEqual('TPerson', Prm.TypeRef,
                'Typ des echten Parameters muss erhalten bleiben');
              Found := True;
            end;
      Assert.IsTrue(Found, 'Parameter-Knoten fehlt');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_UnbalancedParamAttribute_DoesNotEatDeclaration;
// WAECHTER fuer die Recovery-Grenze: ein unbalanciertes '[' darf nicht die
// halbe Unit fressen. Die naechste Routine muss weiterhin im AST landen.
// (Lehre aus dem T2b/T3-Generic-Zweig, gleiche Bauart.)
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure Broken(const [Oops A: TPerson);'#13#10+
  'begin'#13#10+
  'end;'#13#10+
  'procedure Healthy(B: Integer);'#13#10+
  'begin'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root, ImplN, C : TAstNode;
  Cnt    : Integer;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      ImplN := ImplNodeOf(Root);
      Cnt := 0;
      for C in ImplN.Children do
        if C.Kind = nkMethod then Inc(Cnt);
      Assert.IsTrue(Cnt >= 2,
        'Unbalanciertes Attribut darf die Folge-Routine nicht verschlucken');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.Parser_TypedRecordConst_NoPhantomFields;
// 'P: TPoint = (X: 1; Y: 2);' ist EIN Feld. Die Vorfassung lieferte
// zwei ('P' mit abgeschnittenem Wert, Phantom 'Y' mit TypeRef '2)').
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'const'#13#10+
  '  P: TPoint = (X: 1; Y: 2);'#13#10+
  '  N = 7;'#13#10+
  'implementation'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
  Secs   : TList<TAstNode>;
  FeldP  : TAstNode;
  FeldY  : TAstNode;
  FeldN  : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Secs := Root.FindAll(nkConstSection);
      try
        Assert.IsTrue(Secs.Count >= 1, 'const-Sektion fehlt im AST');
        FeldP := nil; FeldY := nil; FeldN := nil;
        for var S in Secs do
          for var C in S.Children do
            if C.Kind = nkField then
            begin
              if SameText(C.Name, 'P') then FeldP := C;
              if SameText(C.Name, 'Y') then FeldY := C;
              if SameText(C.Name, 'N') then FeldN := C;
            end;
        Assert.IsNotNull(FeldP, 'nkField P erwartet');
        Assert.IsNull(FeldY,
          'Phantom-Feld Y - der Wert-Scan ist am inneren '';'' gestorben');
        Assert.IsTrue(Pos('Y', FeldP.TypeRef) > 0,
          'der Wert von P muss VOLLSTAENDIG in TypeRef stehen, ist: ' +
          FeldP.TypeRef);
        // Und die Sektion laeuft nach der Record-Konstante normal weiter.
        Assert.IsNotNull(FeldN, 'die Folge-Konstante N fehlt - Token-Desync');
        Assert.IsTrue(Pos('7', FeldN.TypeRef) > 0,
          'Wert von N fehlt, TypeRef: ' + FeldN.TypeRef);
      finally
        Secs.Free;
      end;
    finally
      Root.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTestParserRobustness.Parser_UnclosedConstParen_DoesNotEatUnit;
// 'const A = (1, 2;' - die schliessende Klammer fehlt (Watch-Mode scannt
// beim Tippen). Der Depth-Scanner haelt die Tiefe dann fuer offen; ohne
// die Rettungsleinen konsumierte er bis EOF, und die implementation
// existierte fuer keinen Detektor mehr.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'const'#13#10+
  '  A = (1, 2;'#13#10+
  'implementation'#13#10+
  'procedure P;'#13#10+
  'begin'#13#10+
  '  Beep;'#13#10+
  'end;'#13#10+
  'end.';
var
  Parser : TParser2;
  Root   : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Assert.IsNotNull(ImplNodeOf(Root),
        'implementation-Node fehlt - der Konstanten-Scanner hat die Unit gefressen');
      Assert.IsTrue(Pos('P', TopLevelMethodNames(ImplNodeOf(Root))) > 0,
        'Methode P fehlt im AST');
    finally
      Root.Free;
    end;
  finally
    Parser.Free;
  end;
end;


procedure TTestParserRobustness.VarNameList_WithContextKeyword_KeepsOwnLine;
// UPSTREAM-BERICHT (Ian Branch, GITLAK, 2026-08-27) zum Kommalisten-Fix:
// die Fortsetzungsschleife benutzte 'T' - dieselbe Variable, die die
// Position der DEKLARATION traegt und nach der Schleife fuer JEDEN
// emittierten nkLocalVar gelesen wird. Ein Kontextwort an zweiter Stelle
// ueberschrieb sie, und alle Namen bekamen die Position des LETZTEN.
//
// WAS DER PARSER HIER LEISTET - und was NICHT (Testfassung korrigiert,
// die erste Fassung dieses Tests war falsch und wurde rot): eine
// Deklaration hat EINE Position, und alle ihre Namen teilen sie. Der
// Emit lautet 'Parent.Add(nkLocalVar, VN, T.Line, T.Col)' fuer jedes VN -
// pro Name eine eigene Zeile war nie das Verhalten und ist auch nicht
// Ziel des Fixes. Richtig ist: BEIDE Namen tragen die Zeile des
// DEKLARATIONSANFANGS (6), nicht die des letzten Namens (7).
// Damit unterscheidet der Test genau die beiden Zustaende:
//   defekt  -> read = 7, write = 7   (Position des letzten Namens)
//   korrekt -> read = 6, write = 6   (Position der Deklaration)
const SRC =
  'unit t;'#13#10 +          // 1
  'interface'#13#10 +        // 2
  'implementation'#13#10 +   // 3
  'procedure Foo;'#13#10 +   // 4
  'var'#13#10 +              // 5
  '  read,'#13#10 +          // 6  <- Deklarationsanfang
  '  write: Integer;'#13#10 +// 7
  'begin'#13#10 +
  '  read := 1; write := 2;'#13#10 +
  'end;'#13#10 +
  'end.';
var
  Parser : TParser2;
  Root, ImplN, M, C : TAstNode;
  LineRead, LineWrite : Integer;
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
      LineRead := -1; LineWrite := -1;
      for C in M.Children do
        if C.Kind = nkLocalVar then
        begin
          if SameText(C.Name, 'read')  then LineRead  := C.Line;
          if SameText(C.Name, 'write') then LineWrite := C.Line;
        end;
      Assert.AreEqual<Integer>(6, LineRead,
        'read traegt die Deklarationszeile');
      Assert.AreEqual<Integer>(6, LineWrite,
        'write traegt DIESELBE Deklarationszeile - vor dem Fix trugen ' +
        'beide die Zeile 7 des letzten Namens');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

{ ---- Helfer fuer die case-else-Tests (Parserfix 2026-08-28) ---- }

// Der n-te DIREKTE nkCaseArm eines case-Knotens (0-basiert), nil wenn
// es ihn nicht gibt. Direkt (nicht FindAll), weil genau die ZUORDNUNG
// zum case-Knoten der Prueflingsteil ist - ein verschachtelter Arm
// darf hier nicht mitzaehlen.
function CaseArmAt(CaseNode: TAstNode; AIndex: Integer): TAstNode;
var
  C : TAstNode;
  N : Integer;
begin
  Result := nil;
  if CaseNode = nil then Exit;
  N := 0;
  for C in CaseNode.Children do
    if C.Kind = nkCaseArm then
    begin
      if N = AIndex then Exit(C);
      Inc(N);
    end;
end;

// Namen aller direkten nkCaseArm-Kinder, in spitzen Klammern und
// kommagetrennt ('<>,<>,<else>'). Die Klammern machen den LEEREN Namen
// eines normalen Arms in der Fehlermeldung sichtbar. Der else-Arm heisst
// 'else' - genau daran haengt SCA168.
function CaseArmNameList(CaseNode: TAstNode): string;
var
  C : TAstNode;
begin
  Result := '';
  if CaseNode = nil then Exit;
  for C in CaseNode.Children do
    if C.Kind = nkCaseArm then
    begin
      if Result <> '' then Result := Result + ',';
      Result := Result + '<' + C.Name + '>';
    end;
end;

// 'Name@Zeile' aller DIREKTEN nkCall-Kinder, kommagetrennt. Position ist
// hier Teil der Zusicherung: die Upstream-Lehre vom 2026-08-27 war, dass
// rein zaehlende Tests einen Positionsdefekt gruen liessen.
function DirectCallsWithLines(N: TAstNode): string;
var
  C : TAstNode;
begin
  Result := '';
  if N = nil then Exit;
  for C in N.Children do
    if C.Kind = nkCall then
    begin
      if Result <> '' then Result := Result + ',';
      Result := Result + C.Name + '@' + IntToStr(C.Line);
    end;
end;

// Rumpf-Block (nkBlock) der Methode mit diesem Namen. Ueber die nkMethod-
// Knoten gesucht, nicht per Root.FindFirst(nkBlock): das traefe den ersten
// Block IRGENDWO im Baum und waere bei mehreren Prozeduren zufaellig.
function MethodBodyOf(Root: TAstNode; const AName: string): TAstNode;
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
begin
  Result  := nil;
  Methods := Root.FindAll(nkMethod);
  try
    for M in Methods do
      if SameText(M.Name, AName) then
        Exit(M.FindFirstChild(nkBlock));
  finally
    Methods.Free;
  end;
end;

procedure TTestParserRobustness.CaseElse_AfterArmIfThenExit_IsCaseArmNotElseBranch;
// Die op.pas-Form (cnwizards .../DCU32/op.pas:509): der letzte Arm endet
// auf 'if ... then Exit;', danach folgt das case-else. Vor dem Fix band
// ParseIfStmt das else an das Arm-if - der case-else wurde ein
// nkElseBranch statt eines nkCaseArm.
const SRC =
  'unit t;'#13#10+                                          // 1
  'interface'#13#10+                                        // 2
  'implementation'#13#10+                                   // 3
  'procedure Decode(W, R: Integer; var RN: Integer);'#13#10+ // 4
  'begin'#13#10+                                            // 5
  '  case W of'#13#10+                                      // 6
  '    0: RN := R;'#13#10+                                  // 7
  '    1: if not RegW(R, RN) then Exit;'#13#10+             // 8
  '    else Exit;'#13#10+                                   // 9
  '  end;'#13#10+                                           // 10
  'end;'#13#10+                                             // 11
  'end.';                                                   // 12
var
  Parser  : TParser2;
  Root    : TAstNode;
  CaseN   : TAstNode;
  ElseArm : TAstNode;
  IfN     : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      CaseN := Root.FindFirst(nkCaseStmt);
      Assert.IsNotNull(CaseN, 'nkCaseStmt fehlt');
      Assert.AreEqual<Integer>(6, CaseN.Line, 'case steht in Zeile 6');

      // KERN: kein einziger nkElseBranch im Baum - das else gehoert dem
      // case, nicht dem if im letzten Arm.
      Assert.AreEqual<Integer>(0, Root.DescendantCount(nkElseBranch),
        'das case-else darf KEIN nkElseBranch sein');

      Assert.AreEqual('<>,<>,<else>', CaseArmNameList(CaseN),
        'drei Arme, der letzte mit Name ''else'' (daran haengt SCA168)');
      Assert.AreEqual<Integer>(3, CaseN.DirectChildCount(nkCaseArm),
        'genau drei direkte nkCaseArm');

      // Positionen der Arme (nicht nur ihre Anzahl).
      Assert.AreEqual<Integer>(7, CaseArmAt(CaseN, 0).Line, 'Arm 0 in Zeile 7');
      Assert.AreEqual<Integer>(8, CaseArmAt(CaseN, 1).Line, 'Arm 1 in Zeile 8');

      ElseArm := CaseArmAt(CaseN, 2);
      Assert.IsNotNull(ElseArm, 'else-Arm fehlt');
      Assert.AreEqual('else', ElseArm.Name, 'else-Arm traegt den Namen ''else''');
      Assert.AreEqual<Integer>(9, ElseArm.Line, 'else-Arm in Zeile 9');
      Assert.AreEqual<Integer>(1, ElseArm.DirectChildCount(nkExit),
        'das Exit des case-else haengt direkt am else-Arm');

      // Das Arm-if behaelt seinen then-Zweig und bekommt KEINEN else-Zweig.
      IfN := CaseArmAt(CaseN, 1).FindFirst(nkIfStmt);
      Assert.IsNotNull(IfN, 'nkIfStmt im Arm 1 fehlt');
      Assert.AreEqual<Integer>(8, IfN.Line, 'das Arm-if steht in Zeile 8');
      Assert.AreEqual<Integer>(1, IfN.DirectChildCount(nkExit),
        'der then-Zweig (Exit) bleibt am if');
      Assert.AreEqual<Integer>(0, IfN.DescendantCount(nkElseBranch),
        'das Arm-if darf keinen else-Zweig bekommen haben');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.CaseElse_AfterArmIfThenRaise_IsCaseArmNotElseBranch;
// Dieselbe Falle mit raise statt Exit - ParseRaiseStmt frisst sein ';'
// genauso. Die urspruengliche Diagnose nannte nur diesen Fall; er ist
// nicht der einzige, aber er muss ebenfalls halten.
const SRC =
  'unit t;'#13#10+                                          // 1
  'interface'#13#10+                                        // 2
  'implementation'#13#10+                                   // 3
  'procedure Decode(W: Integer; var RN: Integer);'#13#10+   // 4
  'begin'#13#10+                                            // 5
  '  case W of'#13#10+                                      // 6
  '    0: RN := 1;'#13#10+                                  // 7
  '    1: if not Ok(W) then raise EAbort.Create(''bad'');'#13#10+ // 8
  '    else RN := 0;'#13#10+                                // 9
  '  end;'#13#10+                                           // 10
  'end;'#13#10+                                             // 11
  'end.';                                                   // 12
var
  Parser  : TParser2;
  Root    : TAstNode;
  CaseN   : TAstNode;
  ElseArm : TAstNode;
  IfN     : TAstNode;
  Asg     : TAstNode;
  C       : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      CaseN := Root.FindFirst(nkCaseStmt);
      Assert.IsNotNull(CaseN, 'nkCaseStmt fehlt');
      Assert.AreEqual<Integer>(0, Root.DescendantCount(nkElseBranch),
        'das case-else darf KEIN nkElseBranch sein');
      Assert.AreEqual('<>,<>,<else>', CaseArmNameList(CaseN),
        'drei Arme, der letzte mit Name ''else''');

      ElseArm := CaseArmAt(CaseN, 2);
      Assert.IsNotNull(ElseArm, 'else-Arm fehlt');
      Assert.AreEqual<Integer>(9, ElseArm.Line, 'else-Arm in Zeile 9');
      Asg := nil;
      for C in ElseArm.Children do
        if C.Kind = nkAssign then Asg := C;
      Assert.IsNotNull(Asg, 'die Zuweisung des case-else fehlt');
      Assert.AreEqual('RN', Asg.Name, 'Zuweisungsziel im else-Arm');
      Assert.AreEqual<Integer>(9, Asg.Line, 'Zuweisung in Zeile 9');

      IfN := CaseArmAt(CaseN, 1).FindFirst(nkIfStmt);
      Assert.IsNotNull(IfN, 'nkIfStmt im Arm 1 fehlt');
      Assert.AreEqual<Integer>(1, IfN.DirectChildCount(nkRaise),
        'das raise bleibt der then-Zweig des Arm-if');
      Assert.AreEqual<Integer>(0, IfN.DescendantCount(nkElseBranch),
        'das Arm-if darf keinen else-Zweig bekommen haben');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.CaseElse_RealIfElseInLastArm_KeepsItsElseBranch;
// GEGENPROBE: der Fix darf nicht zu weit greifen. Ohne ';' vor dem else
// ist es ein ECHTES if-else und muss gebunden bleiben - und das case
// braucht trotzdem seinen eigenen else-Arm.
const SRC =
  'unit t;'#13#10+                                          // 1
  'interface'#13#10+                                        // 2
  'implementation'#13#10+                                   // 3
  'procedure Decode(W: Integer; var RN: Integer);'#13#10+   // 4
  'begin'#13#10+                                            // 5
  '  case W of'#13#10+                                      // 6
  '    0: RN := 1;'#13#10+                                  // 7
  '    1: if Ok(W) then RN := 2 else RN := 3;'#13#10+       // 8
  '    else RN := 4;'#13#10+                                // 9
  '  end;'#13#10+                                           // 10
  'end;'#13#10+                                             // 11
  'end.';                                                   // 12
var
  Parser  : TParser2;
  Root    : TAstNode;
  CaseN   : TAstNode;
  ElseArm : TAstNode;
  IfN     : TAstNode;
  ElseBr  : TAstNode;
  Asg     : TAstNode;
  C       : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      CaseN := Root.FindFirst(nkCaseStmt);
      Assert.IsNotNull(CaseN, 'nkCaseStmt fehlt');
      Assert.AreEqual('<>,<>,<else>', CaseArmNameList(CaseN),
        'das case behaelt seinen eigenen else-Arm');

      // GENAU EIN nkElseBranch im Baum: der des echten if-else.
      Assert.AreEqual<Integer>(1, Root.DescendantCount(nkElseBranch),
        'das echte if-else muss seinen else-Zweig behalten');

      IfN := CaseArmAt(CaseN, 1).FindFirst(nkIfStmt);
      Assert.IsNotNull(IfN, 'nkIfStmt im Arm 1 fehlt');
      Assert.AreEqual<Integer>(1, IfN.DirectChildCount(nkElseBranch),
        'der else-Zweig haengt am if, nicht am case');

      ElseBr := IfN.FindFirst(nkElseBranch);
      Assert.IsNotNull(ElseBr, 'nkElseBranch fehlt');
      // Der Knoten traegt Zeile/Spalte des ERSTEN TOKENS NACH 'else'
      // (ParseIfStmt liest die Position nach dem Next) - hier dieselbe
      // Zeile 8. Bekannte Eigenheit, bewusst festgenagelt.
      Assert.AreEqual<Integer>(8, ElseBr.Line, 'else-Zweig in Zeile 8');
      Asg := nil;
      for C in ElseBr.Children do
        if C.Kind = nkAssign then Asg := C;
      Assert.IsNotNull(Asg, 'Zuweisung im else-Zweig des if fehlt');
      Assert.AreEqual('3', Asg.TypeRef,
        'der else-Zweig des if traegt RN := 3');

      // ... und der case-else-Arm traegt die 4, nicht die 3.
      ElseArm := CaseArmAt(CaseN, 2);
      Assert.IsNotNull(ElseArm, 'else-Arm fehlt');
      Assert.AreEqual<Integer>(9, ElseArm.Line, 'else-Arm in Zeile 9');
      Asg := nil;
      for C in ElseArm.Children do
        if C.Kind = nkAssign then Asg := C;
      Assert.IsNotNull(Asg, 'Zuweisung im case-else fehlt');
      Assert.AreEqual('4', Asg.TypeRef, 'der case-else traegt RN := 4');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.CaseElse_MultiStatementBody_AllStatementsInAst;
// FOLGESCHADEN: bei MEHRSTELLIGEM case-else parste ParseIfStmt nur EINE
// Anweisung in den (faelschlich erzeugten) else-Zweig; die Arm-Schleife
// machte aus dem Rest einen Phantom-Arm und SkipTo verwarf ihn. Beta/
// Gamma/Delta fehlten damit VOLLSTAENDIG im AST - fuer JEDEN Detektor
// unsichtbar. Hier zaehlen deshalb Namen UND Zeilen.
const SRC =
  'unit t;'#13#10+                                          // 1
  'interface'#13#10+                                        // 2
  'implementation'#13#10+                                   // 3
  'procedure Decode(W: Integer);'#13#10+                    // 4
  'begin'#13#10+                                            // 5
  '  case W of'#13#10+                                      // 6
  '    0: AlphaProc;'#13#10+                                // 7
  '    1: if Ok(W) then Exit;'#13#10+                       // 8
  '    else'#13#10+                                         // 9
  '      BetaProc;'#13#10+                                  // 10
  '      GammaProc;'#13#10+                                 // 11
  '      DeltaProc;'#13#10+                                 // 12
  '  end;'#13#10+                                           // 13
  'end;'#13#10+                                             // 14
  'end.';                                                   // 15
var
  Parser  : TParser2;
  Root    : TAstNode;
  CaseN   : TAstNode;
  ElseArm : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      CaseN := Root.FindFirst(nkCaseStmt);
      Assert.IsNotNull(CaseN, 'nkCaseStmt fehlt');
      Assert.AreEqual<Integer>(0, Root.DescendantCount(nkElseBranch),
        'das case-else darf KEIN nkElseBranch sein');

      // Genau DREI Arme: vor dem Fix entstand ein vierter Phantom-Arm aus
      // dem Wiedereinstieg der Arm-Schleife.
      Assert.AreEqual('<>,<>,<else>', CaseArmNameList(CaseN),
        'genau drei Arme - ein vierter waere der Phantom-Arm');

      ElseArm := CaseArmAt(CaseN, 2);
      Assert.IsNotNull(ElseArm, 'else-Arm fehlt');
      // 'else' steht allein in Zeile 9; der Arm-Knoten traegt die Position
      // des ERSTEN TOKENS DANACH (BetaProc, Zeile 10) - die Position wird
      // nach dem Eat(tkKwElse) gelesen. Bekannte Eigenheit, festgenagelt.
      Assert.AreEqual<Integer>(10, ElseArm.Line,
        'else-Arm traegt die Zeile des ersten Rumpf-Tokens');

      // KERN: alle drei Anweisungen, an ihren echten Zeilen, direkt am Arm.
      Assert.AreEqual('BetaProc@10,GammaProc@11,DeltaProc@12',
        DirectCallsWithLines(ElseArm),
        'der komplette mehrstellige else-Rumpf muss im AST stehen');
      Assert.AreEqual<Integer>(3, ElseArm.DirectChildCount(nkCall),
        'drei Anweisungen im else-Arm');

      // Der erste Arm bleibt unberuehrt.
      Assert.AreEqual('AlphaProc@7', DirectCallsWithLines(CaseArmAt(CaseN, 0)),
        'Arm 0 bleibt unveraendert');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.ExceptElse_AfterOnHandlerIf_BelongsToExceptBlock;
// Dieselbe Ursache im except-else: der on-Handler endet auf
// 'if ... then Exit;', danach folgt das else des except-Blocks. Vor dem
// Fix wanderte Cleanup in einen nkElseBranch INNERHALB des on-Handlers.
const SRC =
  'unit t;'#13#10+                                          // 1
  'interface'#13#10+                                        // 2
  'implementation'#13#10+                                   // 3
  'procedure Foo;'#13#10+                                   // 4
  'begin'#13#10+                                            // 5
  '  try'#13#10+                                            // 6
  '    Risky;'#13#10+                                       // 7
  '  except'#13#10+                                         // 8
  '    on E: Exception do if Retry then Exit;'#13#10+       // 9
  '    else'#13#10+                                         // 10
  '      Cleanup;'#13#10+                                   // 11
  '  end;'#13#10+                                           // 12
  'end;'#13#10+                                             // 13
  'end.';                                                   // 14
var
  Parser : TParser2;
  Root   : TAstNode;
  TryN   : TAstNode;
  ExN    : TAstNode;
  OnN    : TAstNode;
  IfN    : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      TryN := Root.FindFirst(nkTryExcept);
      Assert.IsNotNull(TryN, 'nkTryExcept fehlt');
      ExN := TryN.FindFirst(nkExceptBlock);
      Assert.IsNotNull(ExN, 'nkExceptBlock fehlt');
      Assert.AreEqual<Integer>(8, ExN.Line, 'except steht in Zeile 8');

      // KERN: kein nkElseBranch - das else gehoert dem except-Block.
      Assert.AreEqual<Integer>(0, Root.DescendantCount(nkElseBranch),
        'das except-else darf KEIN nkElseBranch sein');

      OnN := ExN.FindFirst(nkOnHandler);
      Assert.IsNotNull(OnN, 'nkOnHandler fehlt');
      Assert.AreEqual<Integer>(9, OnN.Line, 'on-Handler in Zeile 9');
      Assert.AreEqual<Integer>(0, OnN.DescendantCount(nkElseBranch),
        'der on-Handler darf keinen else-Zweig verschluckt haben');
      Assert.AreEqual<Integer>(0, OnN.DescendantCount(nkCall),
        'Cleanup darf NICHT unter dem on-Handler haengen');

      IfN := OnN.FindFirst(nkIfStmt);
      Assert.IsNotNull(IfN, 'nkIfStmt im on-Handler fehlt');
      Assert.AreEqual<Integer>(1, IfN.DirectChildCount(nkExit),
        'der then-Zweig (Exit) bleibt am if');

      // Cleanup haengt DIREKT am except-Block (so parst ParseTryStmt den
      // else-Zweig eines except - er bekommt keinen eigenen Knoten).
      Assert.AreEqual('Cleanup@11', DirectCallsWithLines(ExN),
        'der except-else-Rumpf haengt direkt am nkExceptBlock');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.IfThenEmptyStatement_ElseStillBindsToIf;
// DAS BENANNTE REGRESSIONSRISIKO. 'if C then ; else X;' - hier gehoert
// das ';' zur LEEREN then-Anweisung, das else also doch zum if. Der
// nackte Test 'FLastConsumed <> tkSemicolon' wuerde hier falsch trennen;
// ParseIfStmt faengt das ueber sein EmptyThen ab.
// Delphi selbst lehnt die Form mit E2029 ab, korpusweit 0 Vorkommen -
// dieser Test ist die Absicherung, nicht der Normalfall.
//
// ZWEI Prozeduren, und die zweite ist die wichtigere: seit dem
// Taker-Gate (FElseTakerOpen) bindet ein else auf Methodenrumpf-Ebene
// ohnehin immer ans if - dort traegt EmptyThen nichts mehr. Lastragend
// ist es nur noch INNERHALB eines case-Arms, wo der Taker-Rahmen offen
// ist. Genau das prueft 'Bar'.
const SRC =
  'unit t;'#13#10+                                          // 1
  'interface'#13#10+                                        // 2
  'implementation'#13#10+                                   // 3
  'procedure Foo;'#13#10+                                   // 4
  'begin'#13#10+                                            // 5
  '  if Ready then ; else Fallback;'#13#10+                 // 6
  'end;'#13#10+                                             // 7
  'procedure Bar(W: Integer);'#13#10+                       // 8
  'begin'#13#10+                                            // 9
  '  case W of'#13#10+                                      // 10
  '    0: if Ready then ; else Fallback2;'#13#10+           // 11
  '  end;'#13#10+                                           // 12
  'end;'#13#10+                                             // 13
  'end.';                                                   // 14
var
  Parser : TParser2;
  Root   : TAstNode;
  Body   : TAstNode;
  CaseN  : TAstNode;
  IfN    : TAstNode;
  ElseBr : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Assert.AreEqual<Integer>(2, Root.DescendantCount(nkIfStmt),
        'genau zwei if im Baum');

      // ---- Foo: Methodenrumpf-Ebene, kein Taker-Rahmen ----
      Body := MethodBodyOf(Root, 'Foo');
      Assert.IsNotNull(Body, 'Rumpf-Block von Foo fehlt');
      IfN := Body.FindFirstChild(nkIfStmt);
      Assert.IsNotNull(IfN, 'nkIfStmt in Foo fehlt');
      Assert.AreEqual<Integer>(6, IfN.Line, 'if steht in Zeile 6');

      // KERN: das else bleibt am if gebunden.
      Assert.AreEqual<Integer>(1, IfN.DirectChildCount(nkElseBranch),
        'bei leerem then-Zweig muss das else weiterhin an das if binden');

      ElseBr := IfN.FindFirstChild(nkElseBranch);
      Assert.IsNotNull(ElseBr, 'nkElseBranch fehlt');
      Assert.AreEqual<Integer>(6, ElseBr.Line, 'else-Zweig in Zeile 6');
      Assert.AreEqual('Fallback@6', DirectCallsWithLines(ElseBr),
        'der else-Rumpf haengt am else-Zweig des if');

      // ---- Bar: im case-Arm, Taker-Rahmen OFFEN - hier zaehlt EmptyThen ----
      Body  := MethodBodyOf(Root, 'Bar');
      Assert.IsNotNull(Body, 'Rumpf-Block von Bar fehlt');
      CaseN := Body.FindFirstChild(nkCaseStmt);
      Assert.IsNotNull(CaseN, 'nkCaseStmt in Bar fehlt');
      Assert.AreEqual('<>', CaseArmNameList(CaseN),
        'EmptyThen schlaegt den Taker-Rahmen: das case bekommt KEINEN else-Arm');

      IfN := CaseArmAt(CaseN, 0).FindFirstChild(nkIfStmt);
      Assert.IsNotNull(IfN, 'nkIfStmt im case-Arm fehlt');
      Assert.AreEqual<Integer>(1, IfN.DirectChildCount(nkElseBranch),
        'auch im case-Arm bindet das else bei leerem then-Zweig an das if');
      Assert.AreEqual('Fallback2@11',
        DirectCallsWithLines(IfN.FindFirstChild(nkElseBranch)),
        'der else-Rumpf haengt am else-Zweig des Arm-if');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.CaseElse_AfterVariousSemicolonEatingArms_NoElseBranch;
// Die Falle ist NICHT auf raise/Exit beschraenkt: praktisch jeder
// Anweisungsparser frisst sein eigenes ';'. Vier Faelle in einer Datei -
// 'end;' (ParseBlock), 'Foo;' (ParseCallOrAssign), while und for (beide
// ueber die Rumpf-Anweisung). In allen vier muss das else beim case
// bleiben.
const SRC =
  'unit t;'#13#10+                                          // 1
  'interface'#13#10+                                        // 2
  'implementation'#13#10+                                   // 3
  'procedure WithBlock(W: Integer);'#13#10+                 // 4
  'begin'#13#10+                                            // 5
  '  case W of'#13#10+                                      // 6
  '    0: if Ok(W) then begin AlphaProc; end;'#13#10+       // 7
  '    else BetaProc;'#13#10+                               // 8
  '  end;'#13#10+                                           // 9
  'end;'#13#10+                                             // 10
  'procedure WithCall(W: Integer);'#13#10+                  // 11
  'begin'#13#10+                                            // 12
  '  case W of'#13#10+                                      // 13
  '    0: if Ok(W) then GammaProc;'#13#10+                  // 14
  '    else DeltaProc;'#13#10+                              // 15
  '  end;'#13#10+                                           // 16
  'end;'#13#10+                                             // 17
  'procedure WithWhile(W: Integer);'#13#10+                 // 18
  'begin'#13#10+                                            // 19
  '  case W of'#13#10+                                      // 20
  '    0: if Ok(W) then while Ok(W) do EpsilonProc;'#13#10+ // 21
  '    else ZetaProc;'#13#10+                               // 22
  '  end;'#13#10+                                           // 23
  'end;'#13#10+                                             // 24
  'procedure WithFor(W: Integer);'#13#10+                   // 25
  'var I: Integer;'#13#10+                                  // 26
  'begin'#13#10+                                            // 27
  '  case W of'#13#10+                                      // 28
  '    0: if Ok(W) then for I := 1 to 3 do EtaProc;'#13#10+ // 29
  '    else ThetaProc;'#13#10+                              // 30
  '  end;'#13#10+                                           // 31
  'end;'#13#10+                                             // 32
  'end.';                                                   // 33
var
  Parser : TParser2;
  Root   : TAstNode;
  Cases  : TList<TAstNode>;
  Bodies : string;
  N      : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      // KERN: in KEINEM der vier Faelle darf ein else-Zweig entstehen.
      Assert.AreEqual<Integer>(0, Root.DescendantCount(nkElseBranch),
        'kein case-else darf als nkElseBranch geparst worden sein');

      Cases := Root.FindAll(nkCaseStmt);
      try
        Assert.AreEqual<Integer>(4, Cases.Count, 'vier case-Anweisungen');
        Bodies := '';
        for N in Cases do
        begin
          Assert.AreEqual('<>,<else>', CaseArmNameList(N),
            'jedes case braucht genau einen normalen und einen else-Arm');
          if Bodies <> '' then Bodies := Bodies + ';';
          Bodies := Bodies + DirectCallsWithLines(CaseArmAt(N, 1));
        end;
        // Rumpf UND Zeile je else-Arm - beweist die Zuordnung, nicht nur
        // die Existenz eines else-Arms.
        Assert.AreEqual(
          'BetaProc@8;DeltaProc@15;ZetaProc@22;ThetaProc@30', Bodies,
          'jeder else-Rumpf haengt am else-Arm SEINES case');
      finally Cases.Free; end;
    finally Root.Free; end;
  finally Parser.Free; end;
end;

{ ---- Tests fuer die Rahmen-/Direktiven-Faelle (2026-08-28) ---- }

procedure TTestParserRobustness.CaseElse_AfterArmIfWithNestedCaseOrTry_NoElseBranch;
// MINOR aus der Gegenpruefung: zwei ';'-Fresser als VERSCHACHTELTER Rahmen
// in der then-Anweisung des Arm-ifs. Beide fressen ihr ';' erst nach dem
// eigenen 'end' und stellen den Taker-Zustand des Arms danach wieder her -
// das case-else muss trotzdem beim case bleiben. Heute korrekt, bisher
// ungetestet.
const SRC =
  'unit t;'#13#10+                                          // 1
  'interface'#13#10+                                        // 2
  'implementation'#13#10+                                   // 3
  'procedure ArmWithCase(W, X: Integer);'#13#10+            // 4
  'begin'#13#10+                                            // 5
  '  case W of'#13#10+                                      // 6
  '    0: if Ok(W) then'#13#10+                             // 7
  '         case X of'#13#10+                               // 8
  '           1: AlphaProc;'#13#10+                         // 9
  '         end;'#13#10+                                    // 10
  '  else'#13#10+                                           // 11
  '    BetaProc;'#13#10+                                    // 12
  '  end;'#13#10+                                           // 13
  'end;'#13#10+                                             // 14
  'procedure ArmWithTry(W: Integer);'#13#10+                // 15
  'begin'#13#10+                                            // 16
  '  case W of'#13#10+                                      // 17
  '    0: if Ok(W) then'#13#10+                             // 18
  '         try'#13#10+                                     // 19
  '           GammaProc;'#13#10+                            // 20
  '         finally'#13#10+                                 // 21
  '           DeltaProc;'#13#10+                            // 22
  '         end;'#13#10+                                    // 23
  '  else'#13#10+                                           // 24
  '    EpsilonProc;'#13#10+                                 // 25
  '  end;'#13#10+                                           // 26
  'end;'#13#10+                                             // 27
  'end.';                                                   // 28
var
  Parser    : TParser2;
  Root      : TAstNode;
  OuterCase : TAstNode;
  InnerCase : TAstNode;
  IfN       : TAstNode;
  TryN      : TAstNode;
  FinN      : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      // KERN: in keiner der beiden Formen darf ein nkElseBranch entstehen.
      Assert.AreEqual<Integer>(0, Root.DescendantCount(nkElseBranch),
        'beide case-else muessen case-Arme bleiben');

      // ---- Fall 1: verschachteltes case als then-Anweisung ----
      OuterCase := MethodBodyOf(Root, 'ArmWithCase').FindFirstChild(nkCaseStmt);
      Assert.IsNotNull(OuterCase, 'aeusseres case in ArmWithCase fehlt');
      Assert.AreEqual('<>,<else>', CaseArmNameList(OuterCase),
        'ArmWithCase: ein normaler Arm und ein else-Arm');
      Assert.AreEqual('BetaProc@12',
        DirectCallsWithLines(CaseArmAt(OuterCase, 1)),
        'ArmWithCase: der else-Rumpf haengt am else-Arm des AEUSSEREN case');

      IfN := CaseArmAt(OuterCase, 0).FindFirstChild(nkIfStmt);
      Assert.IsNotNull(IfN, 'Arm-if in ArmWithCase fehlt');
      Assert.AreEqual<Integer>(7, IfN.Line, 'Arm-if in Zeile 7');
      InnerCase := IfN.FindFirstChild(nkCaseStmt);
      Assert.IsNotNull(InnerCase, 'das innere case ist die then-Anweisung');
      Assert.AreEqual<Integer>(8, InnerCase.Line, 'inneres case in Zeile 8');
      Assert.AreEqual('<>', CaseArmNameList(InnerCase),
        'das innere case hat genau EINEN Arm und KEINEN else-Arm');
      Assert.AreEqual('AlphaProc@9',
        DirectCallsWithLines(CaseArmAt(InnerCase, 0)),
        'der Arm des inneren case bleibt vollstaendig');

      // ---- Fall 2: verschachteltes try..finally als then-Anweisung ----
      OuterCase := MethodBodyOf(Root, 'ArmWithTry').FindFirstChild(nkCaseStmt);
      Assert.IsNotNull(OuterCase, 'aeusseres case in ArmWithTry fehlt');
      Assert.AreEqual('<>,<else>', CaseArmNameList(OuterCase),
        'ArmWithTry: ein normaler Arm und ein else-Arm');
      Assert.AreEqual('EpsilonProc@25',
        DirectCallsWithLines(CaseArmAt(OuterCase, 1)),
        'ArmWithTry: der else-Rumpf haengt am else-Arm des case');

      IfN := CaseArmAt(OuterCase, 0).FindFirstChild(nkIfStmt);
      Assert.IsNotNull(IfN, 'Arm-if in ArmWithTry fehlt');
      TryN := IfN.FindFirstChild(nkTryFinally);
      Assert.IsNotNull(TryN, 'das try..finally ist die then-Anweisung');
      Assert.AreEqual('GammaProc@20', DirectCallsWithLines(TryN),
        'der try-Rumpf bleibt am nkTryFinally');
      FinN := TryN.FindFirstChild(nkFinallyBlock);
      Assert.IsNotNull(FinN, 'nkFinallyBlock fehlt');
      Assert.AreEqual('DeltaProc@22', DirectCallsWithLines(FinN),
        'der finally-Rumpf bleibt am nkFinallyBlock');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.CaseArm_EmptyArm_FollowingArmKeepsOwnStatement;
// LEERER ARM (01.09.), AST-Seite. Vor dem Fix hatte das case nur ZWEI Arme:
// ParseStatement frass das ';' von Arm 1, ParseCallOrAssign legte fuer das
// Label 'aaAdd' ein Phantom-nkCall an und SkipToSemicolon verschluckte den
// Rest des dritten Arms restlos. Am echten Code gegengeprueft: mit
// 'aaAdd, aaMove: if P = nil then DoAdd;' meldet SCA126 (AST-basiert) den
// nil-Vergleich HEUTE nicht und nach der Reparatur des Arms schon - die
// Anweisung fehlt also wirklich im Baum, sie ist nicht nur fehlzugeordnet.
const SRC =
  'unit t;'#13#10+                                          // 1
  'interface'#13#10+                                        // 2
  'implementation'#13#10+                                   // 3
  'procedure Save(Mode: TAction);'#13#10+                   // 4
  'begin'#13#10+                                            // 5
  '  case Mode of'#13#10+                                   // 6
  '    aaNone: DoNone;'#13#10+                              // 7
  '    aaDelete: ;'#13#10+                                  // 8
  '    aaAdd, aaMove: DoAdd;'#13#10+                        // 9
  '  end;'#13#10+                                           // 10
  '  DoAfter;'#13#10+                                       // 11
  'end;'#13#10+                                             // 12
  'end.';                                                   // 13
var
  Parser : TParser2;
  Root   : TAstNode;
  CaseN  : TAstNode;
  Body   : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      CaseN := Root.FindFirst(nkCaseStmt);
      Assert.IsNotNull(CaseN, 'nkCaseStmt fehlt');

      // KERN: drei Arme. Vor dem Fix waren es zwei.
      Assert.AreEqual('<>,<>,<>', CaseArmNameList(CaseN),
        'drei Arme - vor dem Fix verschluckte der leere Arm den dritten');
      Assert.AreEqual<Integer>(3, CaseN.DirectChildCount(nkCaseArm),
        'genau drei direkte nkCaseArm');

      // Positionen, nicht nur Anzahl (Lehre vom 2026-08-27).
      Assert.AreEqual<Integer>(7, CaseArmAt(CaseN, 0).Line, 'Arm 0 in Zeile 7');
      Assert.AreEqual<Integer>(8, CaseArmAt(CaseN, 1).Line, 'Arm 1 in Zeile 8');
      Assert.AreEqual<Integer>(9, CaseArmAt(CaseN, 2).Line, 'Arm 2 in Zeile 9');

      Assert.AreEqual('DoNone@7', DirectCallsWithLines(CaseArmAt(CaseN, 0)),
        'Arm 0 behaelt seine Anweisung');
      Assert.AreEqual('', DirectCallsWithLines(CaseArmAt(CaseN, 1)),
        'der LEERE Arm bleibt leer - vor dem Fix stand hier das ' +
        'Phantom-nkCall ''aaAdd@9''');
      Assert.AreEqual('DoAdd@9', DirectCallsWithLines(CaseArmAt(CaseN, 2)),
        'der Folge-Arm behaelt seine eigene Anweisung');

      Body := MethodBodyOf(Root, 'Save');
      Assert.IsNotNull(Body, 'Rumpf-Block von Save fehlt');
      Assert.AreEqual('DoAfter@11', DirectCallsWithLines(Body),
        'der Rumpf nach dem case bleibt unversehrt');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.CaseArm_EmptyArmBeforeBlockArm_NoPhantomLeak;
// LEERER ARM (01.09.), Detektorseite - Klasse J, Gruppe 'finally-uebersehen'.
// Nachbau von Abbrevia AbGzTyp.pas SaveArchive (Z. 1106-1233): zwei
// geschachtelte try/finally, dazwischen ein case mit LEEREM Arm
// ('aaDelete: ;', Z. 1152) und einem Folge-Arm mit Bezeichner-Label-Liste
// und 'begin'-Rumpf. SkipBalanced schloss dieses 'begin' am 'end' des
// inneren try, der Parser landete auf 'except', und der Methodenrumpf
// endete VOR den beiden finally-Bloecken - beide Frees waren unsichtbar
// (SCA001 'never-freed' auf AbGzTyp.pas:1107 und :1112).
// Die Form ist mit der Release-Exe gegengeprueft: so gebaut zwei Funde,
// mit repariertem Arm keiner.
const SRC =
  'unit t;'#13#10+                                          // 1
  'interface'#13#10+                                        // 2
  'implementation'#13#10+                                   // 3
  'procedure Save(Mode: TAction);'#13#10+                   // 4
  'var'#13#10+                                              // 5
  '  A, B: TStringList;'#13#10+                             // 6
  'begin'#13#10+                                            // 7
  '  try'#13#10+                                            // 8
  '    A := TStringList.Create;'#13#10+                     // 9
  '    try'#13#10+                                          // 10
  '      B := TStringList.Create;'#13#10+                   // 11
  '      case Mode of'#13#10+                               // 12
  '        aaNone: DoNone;'#13#10+                          // 13
  '        aaDelete: ;'#13#10+                              // 14
  '        aaAdd, aaMove: begin'#13#10+                     // 15
  '          try'#13#10+                                    // 16
  '            try'#13#10+                                  // 17
  '              DoWork;'#13#10+                            // 18
  '            finally'#13#10+                              // 19
  '              DoCleanup;'#13#10+                         // 20
  '            end;'#13#10+                                 // 21
  '          except'#13#10+                                 // 22
  '            DoLog;'#13#10+                               // 23
  '          end;'#13#10+                                   // 24
  '        end;'#13#10+                                     // 25
  '      end;'#13#10+                                       // 26
  '    finally'#13#10+                                      // 27
  '      A.Free;'#13#10+                                    // 28
  '    end;'#13#10+                                         // 29
  '  finally'#13#10+                                        // 30
  '    B.Free;'#13#10+                                      // 31
  '  end;'#13#10+                                           // 32
  'end;'#13#10+                                             // 33
  'end.';                                                   // 34
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'beide Objekte werden in einem finally freigegeben - vor dem Fix ' +
      'meldete der Detektor zwei Phantom-Lecks, weil der Rumpf vor den ' +
      'finally-Bloecken abbrach');
  finally F.Free; end;
end;

procedure TTestParserRobustness.CaseElse_RejectedElse_RestOfMethodBodyIntact;
// MAJOR-Testluecke aus der Gegenpruefung: ein ABGELEHNTES else darf den
// Rest des Methodenrumpfs nicht kosten. Wird das else abgelehnt, ohne dass
// jemand es aufnimmt, verlaesst ParseBlock seinen Rumpf bei tkKwElse ohne
// Konsum - und ohne das 'end' zu fressen. Alles danach faellt aus dem AST.
// Hier NIMMT der case es auf; der Test nagelt fest, dass die Anweisungen
// VOR und NACH dem case erhalten bleiben.
const SRC =
  'unit t;'#13#10+                                          // 1
  'interface'#13#10+                                        // 2
  'implementation'#13#10+                                   // 3
  'procedure Decode(W: Integer);'#13#10+                    // 4
  'begin'#13#10+                                            // 5
  '  AlphaProc;'#13#10+                                     // 6
  '  case W of'#13#10+                                      // 7
  '    0: if Ok(W) then Exit;'#13#10+                       // 8
  '  else'#13#10+                                           // 9
  '    BetaProc;'#13#10+                                    // 10
  '  end;'#13#10+                                           // 11
  '  GammaProc;'#13#10+                                     // 12
  '  DeltaProc;'#13#10+                                     // 13
  'end;'#13#10+                                             // 14
  'end.';                                                   // 15
var
  Parser : TParser2;
  Root   : TAstNode;
  Body   : TAstNode;
  CaseN  : TAstNode;
  IfN    : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Assert.AreEqual<Integer>(0, Root.DescendantCount(nkElseBranch),
        'das case-else darf KEIN nkElseBranch sein');

      Body := MethodBodyOf(Root, 'Decode');
      Assert.IsNotNull(Body, 'Rumpf-Block von Decode fehlt');
      // KERN: der Rumpf ist vollstaendig - vor UND nach dem case.
      Assert.AreEqual('AlphaProc@6,GammaProc@12,DeltaProc@13',
        DirectCallsWithLines(Body),
        'der Methodenrumpf darf durch das abgelehnte else nichts verlieren');

      CaseN := Body.FindFirstChild(nkCaseStmt);
      Assert.IsNotNull(CaseN, 'nkCaseStmt fehlt');
      Assert.AreEqual('<>,<else>', CaseArmNameList(CaseN),
        'ein normaler Arm und ein else-Arm');
      Assert.AreEqual('BetaProc@10',
        DirectCallsWithLines(CaseArmAt(CaseN, 1)),
        'der else-Rumpf haengt am else-Arm');

      IfN := CaseArmAt(CaseN, 0).FindFirstChild(nkIfStmt);
      Assert.IsNotNull(IfN, 'Arm-if fehlt');
      Assert.AreEqual<Integer>(1, IfN.DirectChildCount(nkExit),
        'der then-Zweig (Exit) bleibt am Arm-if');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.IfdefSemicolonElse_AtBodyLevel_ElseBindsToIf;
// DER BLOCKER AUS DER GEGENPRUEFUNG. Der Lexer verwirft '{...}' samt
// Direktiven als Kommentar und emittiert im Default BEIDE Zweige
// (gLexerIfdefSkipEnabled = False). Aus
//     end {$IFDEF X} ; {$ELSE} else Foo; {$ENDIF}
// wird der Tokenstrom 'end ; else Foo ;' - ein ECHTES if-else mit einem
// ';' davor, denn ';' und else stehen in einander ausschliessenden
// Zweigen. Wuerde das else hier abgelehnt, nimmt es niemand auf: ParseBlock
// verlaesst den Rumpf bei tkKwElse ohne Konsum und ohne das 'end' - der
// ganze Rest der Methode faellt aus dem AST.
//
// Zwei Korpusformen in einer Datei:
//   ParseNumber  = JsonDataObjects.pas:7627/:8242 (begin..end vor dem ';')
//   OpenFields   = JvCsvData.pas:3743 (nackter Aufruf vor dem ';')
// Die geschweiften Klammern stehen in STRINGLITERALEN - sonst waeren sie
// Direktiven DIESER Testdatei statt Testdaten.
const SRC =
  'unit t;'#13#10+                                          // 1
  'interface'#13#10+                                        // 2
  'implementation'#13#10+                                   // 3
  'procedure ParseNumber(W: Integer);'#13#10+               // 4
  'begin'#13#10+                                            // 5
  '  if Ok(W) then'#13#10+                                  // 6
  '  begin'#13#10+                                          // 7
  '    AlphaProc;'#13#10+                                   // 8
  '  end'#13#10+                                            // 9
  '  {$IFDEF KEEP_PRECISION}'#13#10+                        // 10
  '  ;'#13#10+                                              // 11
  '  {$ELSE}'#13#10+                                        // 12
  '  else'#13#10+                                           // 13
  '    BetaProc;'#13#10+                                    // 14
  '  {$ENDIF}'#13#10+                                       // 15
  '  GammaProc;'#13#10+                                     // 16
  '  DeltaProc;'#13#10+                                     // 17
  'end;'#13#10+                                             // 18
  'procedure OpenFields;'#13#10+                            // 19
  'begin'#13#10+                                            // 20
  '  {$IFNDEF HAS_AUTO_FIELDS}'#13#10+                      // 21
  '  if DefaultFields then'#13#10+                          // 22
  '  {$ENDIF}'#13#10+                                       // 23
  '    CreateFields'#13#10+                                 // 24
  '  {$IFDEF HAS_AUTO_FIELDS}'#13#10+                       // 25
  '    ;'#13#10+                                            // 26
  '  {$ELSE}'#13#10+                                        // 27
  '  else'#13#10+                                           // 28
  '    InternalInitFieldDefs;'#13#10+                       // 29
  '  {$ENDIF}'#13#10+                                       // 30
  '  BindFields;'#13#10+                                    // 31
  'end;'#13#10+                                             // 32
  'end.';                                                   // 33
var
  Parser : TParser2;
  Root   : TAstNode;
  Body   : TAstNode;
  IfN    : TAstNode;
  ThenB  : TAstNode;
  ElseBr : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      // Genau zwei else-Zweige - einer je Prozedur.
      Assert.AreEqual<Integer>(2, Root.DescendantCount(nkElseBranch),
        'beide {$IFDEF}-Idiome muessen ein if-else ergeben');
      Assert.AreEqual<Integer>(0, Root.DescendantCount(nkCaseStmt),
        'hier gibt es kein case - der Taker-Rahmen ist zu');

      // ---- Form 1 (JsonDataObjects): begin..end vor dem ';' ----
      Body := MethodBodyOf(Root, 'ParseNumber');
      Assert.IsNotNull(Body, 'Rumpf-Block von ParseNumber fehlt');
      IfN := Body.FindFirstChild(nkIfStmt);
      Assert.IsNotNull(IfN, 'nkIfStmt in ParseNumber fehlt');
      Assert.AreEqual<Integer>(6, IfN.Line, 'if steht in Zeile 6');
      Assert.AreEqual<Integer>(1, IfN.DirectChildCount(nkElseBranch),
        'das else muss an das if binden - sonst ist der Rumpf ab hier weg');

      ThenB := IfN.FindFirstChild(nkBlock);
      Assert.IsNotNull(ThenB, 'then-Block fehlt');
      Assert.AreEqual('AlphaProc@8', DirectCallsWithLines(ThenB),
        'der then-Block bleibt vollstaendig');

      ElseBr := IfN.FindFirstChild(nkElseBranch);
      Assert.IsNotNull(ElseBr, 'nkElseBranch fehlt');
      Assert.AreEqual('BetaProc@14', DirectCallsWithLines(ElseBr),
        'der else-Rumpf haengt am else-Zweig des if');

      // KERN: alles NACH dem Idiom ist noch da. Genau das ging vor dem
      // Taker-Gate verloren.
      Assert.AreEqual('GammaProc@16,DeltaProc@17', DirectCallsWithLines(Body),
        'der Rest des Methodenrumpfs muss erhalten bleiben');

      // ---- Form 2 (JvCsvData): nackter Aufruf vor dem ';' ----
      Body := MethodBodyOf(Root, 'OpenFields');
      Assert.IsNotNull(Body, 'Rumpf-Block von OpenFields fehlt');
      IfN := Body.FindFirstChild(nkIfStmt);
      Assert.IsNotNull(IfN, 'nkIfStmt in OpenFields fehlt');
      Assert.AreEqual<Integer>(22, IfN.Line, 'if steht in Zeile 22');
      Assert.AreEqual('CreateFields@24', DirectCallsWithLines(IfN),
        'die then-Anweisung bleibt am if');
      Assert.AreEqual<Integer>(1, IfN.DirectChildCount(nkElseBranch),
        'auch hier muss das else an das if binden');

      ElseBr := IfN.FindFirstChild(nkElseBranch);
      Assert.IsNotNull(ElseBr, 'nkElseBranch in OpenFields fehlt');
      Assert.AreEqual('InternalInitFieldDefs@29', DirectCallsWithLines(ElseBr),
        'der else-Rumpf haengt am else-Zweig des if');
      Assert.AreEqual('BindFields@31', DirectCallsWithLines(Body),
        'der Rest des Methodenrumpfs muss erhalten bleiben');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.IfdefSemicolonElse_InCaseArmBlock_ElseBindsToIf;
// Dasselbe Idiom INNERHALB eines begin..end, das seinerseits in einem
// case-Arm steht. Der Arm haette das else aufgenommen - der begin..end-
// Rahmen dazwischen kann es aber nicht, also bindet es ans if. Genau
// dafuer setzt ParseBlock den Taker-Rahmen aus und stellt ihn danach
// wieder her: das case-else in Zeile 19 gehoert weiterhin dem case.
const SRC =
  'unit t;'#13#10+                                          // 1
  'interface'#13#10+                                        // 2
  'implementation'#13#10+                                   // 3
  'procedure Decode(W: Integer);'#13#10+                    // 4
  'begin'#13#10+                                            // 5
  '  case W of'#13#10+                                      // 6
  '    0:'#13#10+                                           // 7
  '      begin'#13#10+                                      // 8
  '        if Ok(W) then'#13#10+                            // 9
  '          AlphaProc'#13#10+                              // 10
  '        {$IFDEF KEEP_PRECISION}'#13#10+                  // 11
  '        ;'#13#10+                                        // 12
  '        {$ELSE}'#13#10+                                  // 13
  '        else'#13#10+                                     // 14
  '          BetaProc;'#13#10+                              // 15
  '        {$ENDIF}'#13#10+                                 // 16
  '        GammaProc;'#13#10+                               // 17
  '      end;'#13#10+                                       // 18
  '  else'#13#10+                                           // 19
  '    DeltaProc;'#13#10+                                   // 20
  '  end;'#13#10+                                           // 21
  '  EpsilonProc;'#13#10+                                   // 22
  'end;'#13#10+                                             // 23
  'end.';                                                   // 24
var
  Parser : TParser2;
  Root   : TAstNode;
  Body   : TAstNode;
  CaseN  : TAstNode;
  ArmBlk : TAstNode;
  IfN    : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      // Genau EIN else-Zweig: der des if. Das case behaelt seinen else-Arm.
      Assert.AreEqual<Integer>(1, Root.DescendantCount(nkElseBranch),
        'das {$IFDEF}-else gehoert dem if, nicht dem case');

      Body  := MethodBodyOf(Root, 'Decode');
      Assert.IsNotNull(Body, 'Rumpf-Block von Decode fehlt');
      CaseN := Body.FindFirstChild(nkCaseStmt);
      Assert.IsNotNull(CaseN, 'nkCaseStmt fehlt');
      Assert.AreEqual('<>,<else>', CaseArmNameList(CaseN),
        'das case behaelt seinen eigenen else-Arm');
      Assert.AreEqual('DeltaProc@20', DirectCallsWithLines(CaseArmAt(CaseN, 1)),
        'der case-else-Rumpf haengt am else-Arm');

      ArmBlk := CaseArmAt(CaseN, 0).FindFirstChild(nkBlock);
      Assert.IsNotNull(ArmBlk, 'begin..end des Arms fehlt');
      IfN := ArmBlk.FindFirstChild(nkIfStmt);
      Assert.IsNotNull(IfN, 'nkIfStmt im Arm-Block fehlt');
      Assert.AreEqual<Integer>(9, IfN.Line, 'if steht in Zeile 9');
      Assert.AreEqual('AlphaProc@10', DirectCallsWithLines(IfN),
        'die then-Anweisung bleibt am if');
      Assert.AreEqual<Integer>(1, IfN.DirectChildCount(nkElseBranch),
        'im begin..end nimmt niemand das else auf - es bindet ans if');
      Assert.AreEqual('BetaProc@15',
        DirectCallsWithLines(IfN.FindFirstChild(nkElseBranch)),
        'der else-Rumpf haengt am else-Zweig des if');

      // Nichts geht verloren - weder im Arm-Block noch nach dem case.
      Assert.AreEqual('GammaProc@17', DirectCallsWithLines(ArmBlk),
        'der Rest des Arm-Blocks bleibt erhalten');
      Assert.AreEqual('EpsilonProc@22', DirectCallsWithLines(Body),
        'der Rest des Methodenrumpfs bleibt erhalten');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

procedure TTestParserRobustness.IfdefSemicolonElse_DirectlyInCaseArm_KnownGap_NothingLost;
// BENANNTE RESTLUECKE, bewusst festgenagelt (2026-08-28).
// Steht das {$IFDEF}-Idiom DIREKT in einem case-Arm - ohne begin..end
// dazwischen -, dann ist der Taker-Rahmen offen und das else wird
// abgelehnt. Der case nimmt es als seinen else-Arm. Im TOKENSTROM ist
// dieser Fall von einem echten case-else nicht zu unterscheiden; dafuer
// muesste der Lexer melden, dass zwischen ';' und 'else' eine bedingte
// Direktive lag. Auf D:\git-sca-realworld kommt die Kombination 0-mal vor
// (alle 7 Idiom-Stellen liegen auf Methodenrumpf-Ebene).
//
// Was dieser Test SICHERT: der Schaden ist eine FEHLZUORDNUNG, kein
// Verlust. BetaProc bleibt im AST, AlphaProc bleibt am if, und der Rumpf
// nach dem case ist unversehrt.
//
// Er sichert aber auch die REICHWEITE des Schadens, und die geht weiter
// als der eine Arm: sobald der case sein else genommen hat, sammelt die
// else-Schleife alles bis zum 'end' ein - der nachfolgende ECHTE Arm 1
// verliert seine nkCaseArm-Struktur und landet im else-Rumpf. Deshalb
// steht hier ein zweiter Arm; ohne ihn behauptete der Test eine
// Harmlosigkeit, die er nicht geprueft hat.
// Schlaegt der Test eines Tages um, weil die Luecke geschlossen wurde,
// ist der erwartete neue Stand: nkElseBranch = 1 am if,
// CaseArmNameList = '<>,<>' (zwei echte Arme, kein else-Arm).
const SRC =
  'unit t;'#13#10+                                          // 1
  'interface'#13#10+                                        // 2
  'implementation'#13#10+                                   // 3
  'procedure Decode(W: Integer);'#13#10+                    // 4
  'begin'#13#10+                                            // 5
  '  case W of'#13#10+                                      // 6
  '    0: if Ok(W) then'#13#10+                             // 7
  '         AlphaProc'#13#10+                               // 8
  '       {$IFDEF KEEP_PRECISION}'#13#10+                   // 9
  '       ;'#13#10+                                         // 10
  '       {$ELSE}'#13#10+                                   // 11
  '       else'#13#10+                                      // 12
  '         BetaProc;'#13#10+                               // 13
  '       {$ENDIF}'#13#10+                                  // 14
  '    1: ZetaProc;'#13#10+                                 // 15
  '  end;'#13#10+                                           // 16
  '  GammaProc;'#13#10+                                     // 17
  'end;'#13#10+                                             // 18
  'end.';                                                   // 19
var
  Parser : TParser2;
  Root   : TAstNode;
  Body   : TAstNode;
  CaseN  : TAstNode;
  IfN    : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      Body  := MethodBodyOf(Root, 'Decode');
      Assert.IsNotNull(Body, 'Rumpf-Block von Decode fehlt');
      CaseN := Body.FindFirstChild(nkCaseStmt);
      Assert.IsNotNull(CaseN, 'nkCaseStmt fehlt');

      // DIE LUECKE - so ist der Stand heute, nicht so soll er bleiben.
      Assert.AreEqual<Integer>(0, Root.DescendantCount(nkElseBranch),
        'RESTLUECKE: das if verliert seinen else-Zweig an den case-Arm');
      Assert.AreEqual('<>,<else>', CaseArmNameList(CaseN),
        'RESTLUECKE: der case bekommt einen else-Arm, den es nicht gibt - ' +
        'und der ECHTE Arm 1 erscheint nicht mehr als eigener nkCaseArm, ' +
        'weil die else-Schleife alles bis zum end einsammelt');

      // ... und das ist die Zusicherung, die trotzdem gilt: NICHTS ist weg.
      // Beide Aufrufe liegen im else-Arm - BetaProc gehoert dorthin (im
      // aktiven Zweig), ZetaProc ist der strukturell verschluckte Arm 1.
      // Genau diese Zeile unterscheidet "Fehlzuordnung" von "Verlust":
      // wandert ZetaProc hier je heraus, ist die Luecke teurer geworden
      // als dokumentiert.
      Assert.AreEqual('BetaProc@13,ZetaProc@15',
        DirectCallsWithLines(CaseArmAt(CaseN, 1)),
        'BetaProc UND der verschluckte Arm 1 bleiben im AST - ' +
        'Fehlzuordnung, kein Verlust');
      IfN := CaseArmAt(CaseN, 0).FindFirstChild(nkIfStmt);
      Assert.IsNotNull(IfN, 'Arm-if fehlt');
      Assert.AreEqual('AlphaProc@8', DirectCallsWithLines(IfN),
        'die then-Anweisung bleibt am if');
      Assert.AreEqual('GammaProc@17', DirectCallsWithLines(Body),
        'der Rumpf nach dem case bleibt unversehrt');
    finally Root.Free; end;
  finally Parser.Free; end;
end;

end.
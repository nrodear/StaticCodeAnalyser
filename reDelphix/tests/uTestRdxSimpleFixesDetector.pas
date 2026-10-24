unit uTestRdxSimpleFixesDetector;

// Editorhilfen Stufe 2a gegen den ECHTEN Core (nur Delphi, reDelphix.Test):
// Parser, die Detektoren SCA075/SCA085/SCA126 (dazu SCA074/SCA087/SCA139
// in der zweiten, SCA066/SCA072/SCA084 in der dritten, SCA007/SCA168 in
// der vierten, SCA101/SCA099 in der fuenften, SCA082/SCA071/SCA088/SCA123
// in der sechsten, SCA020/SCA120/SCA122 in der siebten, SCA117/SCA197/
// SCA149 in der achten, SCA098/SCA080/SCA047 in der neunten Fixture),
// TSourcePlaces und
// TRdxFixTable.FixFor - derselbe Einstieg wie im Anbieter. Je Fall meldet
// der Detektor, die Hilfe plant aus dem Fund (Art, Zeile, Meldung), die
// Ersetzungen werden angewandt - und derselbe Detektor meldet danach
// NICHTS mehr. Dazu die Katalog-
// Beispiele (TRuleMeta.BadExample/GoodExample): aus 'bad' wird genau
// 'good'. Die Faelle ohne Parser stehen in uTestRdxSimpleFixes.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxSimpleFixesDetector = class
  public
    // ---- SCA075 ----
    [Test] procedure Sca075_RoundTrip;
    [Test] procedure Sca075_CatalogExample;
    // ---- SCA085 ----
    [Test] procedure Sca085_RoundTrip;
    [Test] procedure Sca085_MissingSysUtils_AddsUses;
    [Test] procedure Sca085_Property_NoHelp;
    [Test] procedure Sca085_PropertyBesideSameNamedField_NoHelp;
    [Test] procedure Sca085_InlineVar_Helps;
    // Review R6-04 (Nachbesserung FF): der Detektor meldet 'X{c}.Free;'
    // und Co., die Hilfe nennt den Kommentar als Grund.
    [Test] procedure Sca085_CommentInExpression_NoHelp;
    [Test] procedure Sca085_CatalogExample;
    // ---- SCA126 ----
    [Test] procedure Sca126_RoundTrip;
    [Test] procedure Sca126_TwoStatementsOnOneLine_NoHelp;
    [Test] procedure Sca126_EventField_NoHelp;
    // Review nach Bereichen 2026-10-10, Minor 6: ein Bezeichner ohne
    // beweisbaren Typ (geerbt) kann ein Funktionszeiger sein.
    [Test] procedure Sca126_UnknownType_NoHelp;
    // Gegen-Review: im with-Block kann der Operand ein Member sein.
    [Test] procedure Sca126_InWith_NoHelp;
    [Test] procedure Sca126_CatalogExample;
    // Review Quick-Fix-Units 2026-10-14 (Blocker): ein Funktionstyp
    // derselben Unit und ein Pfad auf eine Methode ohne Argumente.
    [Test] procedure Sca126_ProcTypeOfOwnUnit_NoHelp;
    [Test] procedure Sca126_PathOperands;
    // Semantik-Gegen-Review 2026-10-14 (Major, Charge R8): ein Kundentyp
    // einer anderen Unit ist nicht bewiesen - wie bei SCA084.
    [Test] procedure Sca126_ForeignType_NoHelp;
    // Entscheid E27 (Nico 2026-10-14, Charge R10): eine Klasse der Delphi-
    // Quellen (uRdxRtlTypes) ist bewiesen, auch aus einer anderen Unit.
    [Test] procedure Sca126_RtlType_Helps;
  end;

  // Stufe 2, Rest (2026-10-10): SCA074, SCA087, SCA139 - eine eigene
  // Fixture, damit keine Klasse ueber 20 Tests waechst (SCA138).
  [TestFixture]
  TTestRdxSimpleFixesDetector2 = class
  public
    // ---- SCA074 ----
    [Test] procedure Sca074_RoundTrip;
    [Test] procedure Sca074_OwnAssert_NoHelp;
    [Test] procedure Sca074_InWith_NoHelp;
    [Test] procedure Sca074_CatalogExample;
    // ---- SCA087 ----
    [Test] procedure Sca087_RoundTrip;
    [Test] procedure Sca087_CatalogExample;
    // ---- SCA139 ----
    [Test] procedure Sca139_RoundTrip;
    [Test] procedure Sca139_MissingSysUtils_AddsUses;
    [Test] procedure Sca139_Property_NoHelp;
    [Test] procedure Sca139_RecordWithFree_NoHelp;
    // Gegen-Review 2026-10-10: eine Klasse mit eigener Methode Free (Pool).
    [Test] procedure Sca139_OwnFreeMethod_NoHelp;
    [Test] procedure Sca139_CatalogExample;
  end;

  // uQuickFix-Umzug (Beschluss 2026-10-09): SCA066, SCA072, SCA084.
  [TestFixture]
  TTestRdxSimpleFixesDetector3 = class
  public
    // ---- SCA066 ----
    [Test] procedure Sca066_RoundTrip;
    [Test] procedure Sca066_InExpression_NoHelp;
    [Test] procedure Sca066_FpcFile_NoHelp;
    [Test] procedure Sca066_CatalogExample;
    // Gegen-Review 2026-10-10: prozedurales Ziel (Korpus cnwizards) und
    // Prozedurvariable als Aufrufziel.
    [Test] procedure Sca066_ProcTarget_NoHelp;
    [Test] procedure Sca066_ProcVariable_NoHelp;
    // ---- SCA072 ----
    [Test] procedure Sca072_RoundTrip;
    [Test] procedure Sca072_LongBool_NoHelp;
    [Test] procedure Sca072_UnknownType_NoHelp;
    [Test] procedure Sca072_CatalogExample;
    [Test] procedure Sca072_InWith_NoHelp;
    // ---- SCA084 ----
    [Test] procedure Sca084_RoundTrip;
    [Test] procedure Sca084_ProcType_NoHelp;
    [Test] procedure Sca084_UnknownType_NoHelp;
    [Test] procedure Sca084_CatalogExample;
    // Gegen-Review 2026-10-10: Alias auf einen Funktionstyp, eigene Routine
    // Assigned, Klasse aus einer anderen Unit (Zulassungsliste).
    [Test] procedure Sca084_FuncAlias_NoHelp;
    [Test] procedure Sca084_OwnAssigned_NoHelp;
    [Test] procedure Sca084_OtherUnitType_NoHelp;
    // Katalogfeld editorHelp (Beschluss 2026-10-10, HTML-QF-Badge) =
    // die Regeln mit einer Hilfe dieses Moduls.
    [Test] procedure Catalog_EditorHelpMatchesHelps;
  end;

  // Stufe 3 (uRdxStructFixes): SCA007 uses-Eintrag, SCA168 case-else.
  [TestFixture]
  TTestRdxSimpleFixesDetector4 = class
  public
    // ---- SCA007 ----
    [Test] procedure Sca007_RoundTrip;
    [Test] procedure Sca007_OnlyEntry_RemovesClause;
    [Test] procedure Sca007_MarkedAsBehaviorChange;
    // ---- SCA168 ----
    [Test] procedure Sca168_RoundTrip;
    [Test] procedure Sca168_Raise_AddsUses;
    [Test] procedure Sca168_FpcFile_Raise_ShortUses;
    [Test] procedure Sca168_CatalogExample;
    // 2026-10-22: die Klasse, die eine Hilfe schreibt, gibt es in der RTL.
    [Test] procedure RaisedClasses_ExistInRtl;
    // Gegen-Review 2026-10-10.
    [Test] procedure Sca168_LastArmIf_RoundTrip;
    [Test] procedure Sca007_StaleFinding_NoHelp;
    [Test] procedure Alternative_OtherKinds_None;
    // Wochen-Review 2026-10-21
    [Test] procedure Sca007_NamespaceSibling_NotAUse;
  end;

  // Stufe 3: SCA101 und SCA099, Zweig als Block (Entscheid E7).
  [TestFixture]
  TTestRdxSimpleFixesDetector5 = class
  public
    [Test] procedure Sca101_RoundTrip;
    [Test] procedure Sca101_CatalogExample;
    [Test] procedure Sca101_CaseElse_RoundTrip;
    [Test] procedure Sca101_StaleFinding_NoHelp;
    [Test] procedure Sca101_SameMeaning;
    [Test] procedure Sca099_RoundTrip_SilencesSca101;
    [Test] procedure Sca099_CatalogExample;
    // Gegen-Review 2026-10-10, Blocker 1.
    [Test] procedure Sca099_AnonMethodHeader_NoHelp;
  end;

  // Zeilen-Hilfen (uRdxLineFixes): SCA082, SCA071, SCA088, SCA123.
  [TestFixture]
  TTestRdxSimpleFixesDetector6 = class
  public
    [Test] procedure Sca082_RoundTrip_CatalogExample;
    [Test] procedure Sca071_RoundTrip;
    [Test] procedure Sca071_CatalogExample;
    [Test] procedure Sca088_RoundTrip_CatalogExample;
    [Test] procedure Sca123_RoundTrip;
    [Test] procedure Sca123_CatalogExample_NoHelp;
    // Gegen-Review Zeilen-Hilfen: ein anderer Typ (verdecktes Free,
    // Pointer) und ein unbekannter Typ.
    [Test] procedure Sca123_OtherType_NoHelp;
  end;

  // Ausnahmen und leere Rumpfe (uRdxRaiseFixes): SCA020, SCA120, SCA122.
  [TestFixture]
  TTestRdxSimpleFixesDetector7 = class
  public
    [Test] procedure Sca020_RoundTrip;
    [Test] procedure Sca020_Raise_AddsUses;
    [Test] procedure Sca020_CatalogExample;
    [Test] procedure Sca120_RoundTrip_CatalogExample;
    [Test] procedure Sca122_RoundTrip_CatalogExample;
    [Test] procedure Sca122_InnerTry_NoHelp;
  end;

  // Deklarationen (uRdxDeclFixes): SCA117, SCA197, SCA149.
  [TestFixture]
  TTestRdxSimpleFixesDetector8 = class
  public
    [Test] procedure Sca117_RoundTrip;
    [Test] procedure Sca117_CatalogExample;
    [Test] procedure Sca197_RoundTrip_CatalogExample;
    [Test] procedure Sca197_ComImport_NoHelp;
    [Test] procedure Sca149_Override_CatalogExample;
    [Test] procedure Sca149_Reintroduce_RoundTrip;
  end;

  // Ganze Anweisungen (uRdxFlowFixes, Charge H2): SCA098, SCA080, SCA047 -
  // dazu die Pruefungen des Laeufers (Boolean bewiesen, Variable, with).
  [TestFixture]
  TTestRdxSimpleFixesDetector9 = class
  public
    [Test] procedure Sca098_RoundTrip;
    [Test] procedure Sca098_CatalogExample;
    [Test] procedure Sca098_NotProvenBoolean_NoHelp;
    [Test] procedure Sca098_InWith_NoHelp;
    [Test] procedure Sca080_RoundTrip_CatalogExample;
    [Test] procedure Sca080_ThenExit_NoHelp;
    [Test] procedure Sca047_RoundTrip;
    [Test] procedure Sca047_CatalogExample;
    [Test] procedure Sca047_ResultAndWith_NoHelp;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog,
  uExplicitTObjectInheritance, uFreeAndNilHint, uNilComparison,
  uAssertMessage, uEmptyVisibilitySection, uFreeWithoutNil,
  uEmptyArgumentList, uRedundantBoolean, uAssignedAndAssignedNil,
  uUnusedUses, uDefaultCaseInCaseStatement, uBeginEndRequired, uIfElseBegin,
  uSuperfluousSemicolon, uUnitLevelKeywordIndent, uLegacyInitializationSection,
  uCastAndFree, uEmptyMethod, uMissingRaise, uReRaiseException, uRdxRaiseFixes,
  uRdxStructFixes,   // RAISE_UNHANDLED (RaisedClasses_ExistInRtl)
  uPublicMemberWithoutDoc, uInterfaceGuid, uMissingOverride, uRdxDeclFixes,
  uRedundantConditional, uRedundantJump, uSelfAssignment,
  uEngineApi, uRdxBufferMath, uRdxRecipeRunner,
  uRdxFixTable,   // der Einstieg des Anbieters (Charge R8: Tabelle statt Ketten)
  uTestRdxDetectorKit,   // TSeen, Detect-/Plan-/FixAll-Helfer (Charge H3c)
  uTestRdxTextKit;       // Join, Apply

// ---- Helfer (die gemeinsamen seit Charge H3c in uTestRdxDetectorKit) ----

// Die Detektoren der Anweisungs-Hilfen - ein fuenfter Verteiler (SCA091).
procedure RunFlowDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  case AKind of
    fkRedundantConditional:
      TRedundantConditionalDetector.AnalyzeUnit(Root, Path, Results);
    fkRedundantJump:
      TRedundantJumpDetector.AnalyzeUnit(Root, Path, Results);
    fkSelfAssignment:
      TSelfAssignmentDetector.AnalyzeUnit(Root, Path, Results);
  else
    Assert.Fail('keine Hilfe fuer diese Art');
  end;
end;

// Die Detektoren der Deklarations-Hilfen - ein vierter Verteiler (SCA091).
procedure RunDeclDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  case AKind of
    fkPublicMemberWithoutDoc:
      TPublicMemberWithoutDocDetector.AnalyzeUnit(Root, Path, Results);
    fkInterfaceWithoutGuid:
      TInterfaceGuidDetector.AnalyzeUnit(Root, Path, Results);
    fkMissingOverride:
      TMissingOverrideDetector.AnalyzeUnit(Root, Path, Results);
  else
    RunFlowDetector(AKind, Root, Path, Results);
  end;
end;

// Die Detektoren der Zeilen-Hilfen - ein dritter Verteiler (SCA091).
procedure RunLineDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  case AKind of
    fkSuperfluousSemicolon:
      TSuperfluousSemicolonDetector.AnalyzeUnit(Root, Path, Results);
    fkUnitLevelKeywordIndent:
      TUnitLevelKeywordIndentDetector.AnalyzeUnit(Root, Path, Results);
    fkLegacyInitializationSection:
      TLegacyInitializationSectionDetector.AnalyzeUnit(Root, Path, Results);
    fkCastAndFree:
      TCastAndFreeDetector.AnalyzeUnit(Root, Path, Results);
    fkEmptyMethod:
      TEmptyMethodDetector.AnalyzeUnit(Root, Path, Results);
    fkMissingRaise:
      TMissingRaiseDetector.AnalyzeUnit(Root, Path, Results);
    fkReRaiseException:
      TReRaiseExceptionDetector.AnalyzeUnit(Root, Path, Results);
  else
    RunDeclDetector(AKind, Root, Path, Results);
  end;
end;

// Die Detektoren aus dem uQuickFix-Umzug und der Stufe 3 - ein zweiter
// Verteiler (SCA091).
procedure RunLaterDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  case AKind of
    fkEmptyArgumentList:
      TEmptyArgumentListDetector.AnalyzeUnit(Root, Path, Results);
    fkRedundantBoolean:
      TRedundantBooleanDetector.AnalyzeUnit(Root, Path, Results);
    fkAssignedAndAssignedNil:
      TAssignedAndAssignedNilDetector.AnalyzeUnit(Root, Path, Results);
    fkUnusedUses:
      TUnusedUsesDetector.AnalyzeUnit(Root, Path, Results);
    fkDefaultCaseInCaseStatement:
      TDefaultCaseInCaseStatementDetector.AnalyzeUnit(Root, Path, Results);
    fkBeginEndRequired:
      TBeginEndRequiredDetector.AnalyzeUnit(Root, Path, Results);
    fkIfElseBegin:
      TIfElseBeginDetector.AnalyzeUnit(Root, Path, Results);
  else
    RunLineDetector(AKind, Root, Path, Results);
  end;
end;

// Der Verteiler fuer den echten Detektor der Art AKind (TDetectorRun).
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  case AKind of
    fkExplicitTObjectInheritance:
      TExplicitTObjectInheritanceDetector.AnalyzeUnit(Root, Path, Results);
    fkFreeAndNilHint:
      TFreeAndNilHintDetector.AnalyzeUnit(Root, Path, Results);
    fkNilComparison:
      TNilComparisonDetector.AnalyzeUnit(Root, Path, Results);
    fkAssertMessage:
      TAssertMessageDetector.AnalyzeUnit(Root, Path, Results);
    fkEmptyVisibilitySection:
      TEmptyVisibilitySectionDetector.AnalyzeUnit(Root, Path, Results);
    fkFreeWithoutNil:
      TFreeWithoutNilDetector.AnalyzeUnit(Root, Path, Results);
  else
    RunLaterDetector(AKind, Root, Path, Results);
  end;
end;

// Funde der Art AKind - der echte Detektor auf dem echten AST.
function Detect(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_simple_', ASource, AKind, RunDetector);
end;

// Der zweite Eintrag (TRdxFixTable.AlternativeFixFor) fuer EINEN Fund -
// SCA168 (else mit raise) und SCA020 (raise ENotImplemented). Der Lauf des
// Kits (PlanAltFixIn) fuer 't.pas' - bis zur Review Woche G07-27 stand er
// hier kopiert.
function PlanAltFix(const ASource: string; AKind: TFindingKind;
  const ASeen: TSeen): TRdxFixOutcome;
begin
  Result := PlanAltFixIn(ASource, 't.pas', AKind, ASeen);
end;

// Die Hilfe (FixFor) fuer EINEN Fund als ganzes Ergebnis - mit
// ChangesBehavior und Hinweis. Der Lauf des Kits (PlanFixIn) fuer 't.pas'
// - bis zur Review Woche G07-27 stand er hier Zeile fuer Zeile kopiert
// (ohne den Handles-Assert des Kits).
function PlanMain(const ASource: string; AKind: TFindingKind;
  const ASeen: TSeen): TRdxFixOutcome;
begin
  Result := PlanFixIn(ASource, 't.pas', AKind, ASeen);
end;

// Fund fuer Fund, bis der Detektor schweigt (uTestRdxDetectorKit).
function FixAll(const ASource: string; AKind: TFindingKind): string;
begin
  Result := FixAllWith(ASource, AKind, Detect);
end;

// Der erste Fund muss abgelehnt werden, mit AReasonPart im Grund.
procedure AssertNoHelp(const ASource: string; AKind: TFindingKind;
  const AReasonPart: string);
begin
  AssertNoHelpWith(ASource, AKind, AReasonPart, Detect);
end;

// Wie AssertNoHelp, aber fuer den Fund auf Zeile ALine (Kit seit der
// Review Woche G07-27).
procedure AssertNoHelpAt(const ASource: string; AKind: TFindingKind;
  ALine: Integer; const AReasonPart: string);
begin
  uTestRdxDetectorKit.AssertNoHelpAt(ASource, AKind, ALine, AReasonPart,
    Detect);
end;

function CountOf(const APart, AText: string): Integer;
var
  P : Integer;
begin
  Result := 0;
  P := Pos(APart, AText);
  while P > 0 do
  begin
    Inc(Result);
    P := Pos(APart, AText, P + Length(APart));
  end;
end;

// Ein Katalog-Beispiel als Quelltext: '...' faellt weg, Zeilenenden CRLF
// (JSON liefert #10, der eingebaute Katalog #13#10) - anders als
// uTestRdxDetectorKit.CatalogText, das '...' stehen laesst.
function Snip(const AExample: string): string;
begin
  Result := StringReplace(AExample, '...', '', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #10, #13#10, [rfReplaceAll]);
end;

// Deklarationen im interface einer Unit.
function InInterface(const ADecl: string): string;
begin
  Result := Join(['unit t;', 'interface', ADecl, 'implementation', 'end.']);
end;

// Anweisungen in einer Routine (je Zeile zwei Leerzeichen eingerueckt).
function InRoutine(const AStatements: string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation',
    'uses System.SysUtils;', 'procedure P;', 'var', '  Obj: TObject;',
    'begin',
    '  ' + StringReplace(AStatements, #13#10, #13#10'  ', [rfReplaceAll]),
    'end;', 'end.']);
end;

{ ---- SCA075 ---- }

procedure TTestRdxSimpleFixesDetector.Sca075_RoundTrip;
const
  HEAD = 'unit t;'#13#10'interface'#13#10'type'#13#10;
  TAIL = #13#10'implementation'#13#10'end.';
begin
  Assert.AreEqual(HEAD + Join([
    '  TA = class',
    '    FX: Integer;',
    '  end;',
    '  TB = class end;',
    '  TC = class end;',
    '  TD = class(TInterfacedObject)',
    '  end;']) + TAIL,
    FixAll(HEAD + Join([
    '  TA = class(TObject)',
    '    FX: Integer;',
    '  end;',
    '  TB = class (TObject) end;',
    '  TC = class(TObject);',
    '  TD = class(TInterfacedObject)',
    '  end;']) + TAIL, fkExplicitTObjectInheritance));
end;

procedure TTestRdxSimpleFixesDetector.Sca075_CatalogExample;
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkExplicitTObjectInheritance);
  Assert.IsTrue(Pos('class(TObject)', Meta.BadExample) > 0, Meta.BadExample);
  Assert.AreEqual(InInterface(Snip(Meta.GoodExample)),
    FixAll(InInterface(Snip(Meta.BadExample)), fkExplicitTObjectInheritance));
end;

{ ---- SCA085 ---- }

const
  // Eine Klasse mit Feld, Property und einer Methode, deren Rumpf die
  // Faelle einsetzen (%s); uses-Zeilen im interface und implementation.
  UNIT_085 =
    'unit t;'#13#10 +
    'interface'#13#10 +
    'uses System.Classes;'#13#10 +
    'type'#13#10 +
    '  TFoo = class'#13#10 +
    '  private'#13#10 +
    '    FList: TList;'#13#10 +
    '  public'#13#10 +
    '    property Items: TList read FList write FList;'#13#10 +
    '    procedure Done;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    '%s'#13#10 +
    'procedure TFoo.Done;'#13#10 +
    'var'#13#10 +
    '  Obj: TObject;'#13#10 +
    'begin'#13#10 +
    '%s'#13#10 +
    'end;'#13#10 +
    'end.';

procedure TTestRdxSimpleFixesDetector.Sca085_RoundTrip;
begin
  Assert.AreEqual(
    Format(UNIT_085, ['uses System.SysUtils;', Join([
      '  FreeAndNil(Obj);',
      '  FreeAndNil(FList);'])]),
    FixAll(Format(UNIT_085, ['uses System.SysUtils;', Join([
      '  Obj.Free;',
      '  Obj := nil;',
      '  FList.Free;',
      '  FList := nil;'])]), fkFreeAndNilHint));
end;

procedure TTestRdxSimpleFixesDetector.Sca085_MissingSysUtils_AddsUses;
var
  After : string;
begin
  // Ohne SysUtils kommt die uses-Ergaenzung in DENSELBEN Undo-Schritt;
  // die zweite Hilfe braucht sie dann nicht mehr.
  After := FixAll(Format(UNIT_085, ['', Join([
    '  Obj.Free;',
    '  Obj := nil;',
    '  FList.Free;',
    '  FList := nil;'])]), fkFreeAndNilHint);
  Assert.IsTrue(Pos('FreeAndNil(Obj);', After) > 0, After);
  Assert.IsTrue(Pos('FreeAndNil(FList);', After) > 0, After);
  Assert.IsTrue(Pos(':= nil', After) = 0, After);
  Assert.AreEqual<Integer>(1, CountOf('SysUtils', After),
    'SysUtils genau einmal ergaenzt: ' + After);
end;

procedure TTestRdxSimpleFixesDetector.Sca085_Property_NoHelp;
begin
  // Eine Property als FreeAndNil-Argument uebersetzt nicht.
  AssertNoHelp(Format(UNIT_085, ['uses System.SysUtils;', Join([
    '  Items.Free;',
    '  Items := nil;'])]), fkFreeAndNilHint, 'Property');
end;

procedure TTestRdxSimpleFixesDetector.Sca085_PropertyBesideSameNamedField_NoHelp;
begin
  // Review 2026-10-09: DeclaredTypeOf findet JEDES gleichnamige Feld der
  // Unit (hier TRow.Items) - die Property-Sperre darf daran nicht haengen.
  AssertNoHelp(Format(UNIT_085, [
    'uses System.SysUtils;'#13#10'type'#13#10'  TRow = record Items: TList; end;',
    Join([
    '  Items.Free;',
    '  Items := nil;'])]), fkFreeAndNilHint, 'Property');
end;

procedure TTestRdxSimpleFixesDetector.Sca085_InlineVar_Helps;
begin
  // 'var L := ...' ohne Typ kennt DeclaredTypeOf nicht - trotzdem eine
  // Variable.
  Assert.AreEqual(
    Format(UNIT_085, ['uses System.SysUtils;', Join([
      '  var L := TList.Create;',
      '  FreeAndNil(L);'])]),
    FixAll(Format(UNIT_085, ['uses System.SysUtils;', Join([
      '  var L := TList.Create;',
      '  L.Free;',
      '  L := nil;'])]), fkFreeAndNilHint));
end;

procedure TTestRdxSimpleFixesDetector.Sca085_CommentInExpression_NoHelp;
const
  FORMS: array[0..2] of string = ('  FList{owned}.Free;', '  FList.{c}Free;',
    '  FList.Free {c};');
var
  Form : string;
begin
  // Der Detektor liest die Zeile ohne Kommentare und meldet diese Formen
  // wie 'FList.Free;' (ohne Delphi gegengeprueft: CLI-Exe, SCA085 auf allen
  // drei). Die Hilfe ersetzt nicht ueber einen Kommentar hinweg und nennt
  // ihn - bis Review R6-04 lautete der Grund direkt nach dem Scan 'X.Free;
  // steht nicht mehr an der gemeldeten Stelle'.
  for Form in FORMS do
    AssertNoHelp(Format(UNIT_085, ['uses System.SysUtils;', Join([Form,
      '  FList := nil;'])]), fkFreeAndNilHint, 'Kommentar im Ausdruck');
end;

procedure TTestRdxSimpleFixesDetector.Sca085_CatalogExample;
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkFreeAndNilHint);
  Assert.IsTrue(Pos('.Free;', Meta.BadExample) > 0, Meta.BadExample);
  Assert.AreEqual(InRoutine(Snip(Meta.GoodExample)),
    FixAll(InRoutine(Snip(Meta.BadExample)), fkFreeAndNilHint));
end;

{ ---- SCA126 ---- }

const
  UNIT_126 =
    'unit t;'#13#10 +
    'interface'#13#10 +
    'uses System.Classes;'#13#10 +
    'type'#13#10 +
    '  TNode = class'#13#10 +
    '    Next: TNode;'#13#10 +
    '  end;'#13#10 +
    '  TFoo = class'#13#10 +
    '    FList: TList;'#13#10 +
    '    FDriver: TChromium;'#13#10 +
    '    FOwner: TObject;'#13#10 +
    '    FOnChange: TNotifyEvent;'#13#10 +
    '    function Check(Obj: TObject; P: TNode): Boolean;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'function TFoo.Check(Obj: TObject; P: TNode): Boolean;'#13#10 +
    'var'#13#10 +
    '  B: Boolean;'#13#10 +
    'begin'#13#10 +
    '%s'#13#10 +
    'end;'#13#10 +
    'end.';

procedure TTestRdxSimpleFixesDetector.Sca126_RoundTrip;
begin
  // Operanden mit bewiesenem Typ: TObject (Feld und Parameter) und die
  // Klasse TNode dieser Unit. FList: TList (System.Classes) ist seit E27
  // ueber die Liste der Delphi-Quellen bewiesen (Sca126_RtlType_Helps);
  // FDriver: TChromium (Kundentyp, andere Unit) bleibt ohne Hilfe
  // (Sca126_ForeignType_NoHelp).
  Assert.AreEqual(
    Format(UNIT_126, [Join([
      '  if Assigned(FOwner) then',
      '    FOwner.Free;',
      '  while Assigned(P) do',
      '    P := P.Next;',
      '  B := not Assigned(Obj);',
      '  Result := Assigned(FOwner) and Assigned(Obj);',
      '  Assert(Assigned(Obj), ''x'');',
      '  if not Assigned(Obj) then',
      '    Exit(not Assigned(FOwner));'])]),
    FixAll(Format(UNIT_126, [Join([
      '  if FOwner <> nil then',
      '    FOwner.Free;',
      '  while P <> nil do',
      '    P := P.Next;',
      '  B := Obj = nil;',
      '  Result := (FOwner <> nil) and not (Obj = nil);',
      '  Assert(Obj <> nil, ''x'');',
      '  if nil = Obj then',
      '    Exit(FOwner = nil);'])]), fkNilComparison));
end;

procedure TTestRdxSimpleFixesDetector.Sca126_ForeignType_NoHelp;
begin
  // TChromium kommt aus einer fremden Unit (CEF): DeclaredTypeOf liefert
  // 'tchromium', weder die Datei noch die Liste der Delphi-Quellen beweist,
  // dass es eine Klasse ist - ein 'TObjFactory = function: TObject' einer
  // anderen Unit saehe genauso aus, und '= nil' riefe ihn auf, Assigned()
  // nicht (Charge R8; bis E27 stand hier FList: TList).
  AssertNoHelp(Format(UNIT_126, [Join([
    '  if FDriver <> nil then',
    '    FDriver.Free;'])]), fkNilComparison, 'nicht als Klasse');
end;

procedure TTestRdxSimpleFixesDetector.Sca126_RtlType_Helps;
begin
  // E27: TList aus System.Classes steht in der Liste der Delphi-Quellen
  // (uRdxRtlTypes) - bewiesen, obwohl diese Unit es nicht deklariert.
  Assert.AreEqual(
    Format(UNIT_126, [Join([
      '  if Assigned(FList) then',
      '    FList.Clear;'])]),
    FixAll(Format(UNIT_126, [Join([
      '  if FList <> nil then',
      '    FList.Clear;'])]), fkNilComparison));
end;

procedure TTestRdxSimpleFixesDetector.Sca126_TwoStatementsOnOneLine_NoHelp;
begin
  // Zwei Funde mit gleicher Zeile und Meldung - keiner laesst sich
  // zuordnen.
  AssertNoHelp(Format(UNIT_126, ['  if Obj = nil then B := FList = nil;']),
    fkNilComparison, 'mehrdeutig');
end;

procedure TTestRdxSimpleFixesDetector.Sca126_EventField_NoHelp;
begin
  // Methodenzeiger: '= nil' ruft auf (Delphi), Assigned() prueft den Zeiger.
  AssertNoHelp(Format(UNIT_126, [Join([
    '  if FOnChange <> nil then',
    '    FOnChange(Self);'])]), fkNilComparison, 'Ereignis');
end;

procedure TTestRdxSimpleFixesDetector.Sca126_UnknownType_NoHelp;
begin
  AssertNoHelp(Format(UNIT_126, [Join([
    '  if FFactory = nil then',
    '    Exit(False);'])]), fkNilComparison, 'unbekannt');
end;

procedure TTestRdxSimpleFixesDetector.Sca126_InWith_NoHelp;
begin
  AssertNoHelp(Format(UNIT_126, [Join([
    '  with P do',
    '    if FList = nil then',
    '      Exit(False);'])]), fkNilComparison, 'with');
end;

procedure TTestRdxSimpleFixesDetector.Sca126_CatalogExample;
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkNilComparison);
  Assert.IsTrue(Pos('nil', Meta.BadExample) > 0, Meta.BadExample);
  Assert.AreEqual(InRoutine(Snip(Meta.GoodExample)),
    FixAll(InRoutine(Snip(Meta.BadExample)), fkNilComparison));
end;

const
  // Wie UNIT_126, dazu ein Funktionstyp der Unit und ein Feld davon.
  UNIT_126_FACTORY =
    'unit t;'#13#10 +
    'interface'#13#10 +
    'uses System.Classes;'#13#10 +
    'type'#13#10 +
    '  TObjFactory = function: TObject;'#13#10 +
    '  TFoo = class'#13#10 +
    '    FMaker: TObjFactory;'#13#10 +
    '    FList: TList;'#13#10 +
    '    function Check: Boolean;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'function TFoo.Check: Boolean;'#13#10 +
    'begin'#13#10 +
    '%s'#13#10 +
    'end;'#13#10 +
    'end.';

procedure TTestRdxSimpleFixesDetector.Sca126_ProcTypeOfOwnUnit_NoHelp;
begin
  // 'FMaker = nil' ruft die Funktion auf (Delphi), 'not Assigned(FMaker)'
  // pruefte den Zeiger - der Typname TObjFactory verraet das nicht, erst
  // seine Deklaration in der Unit.
  AssertNoHelp(Format(UNIT_126_FACTORY, [Join([
    '  if FMaker = nil then',
    '    Exit(False);',
    '  Result := True;'])]), fkNilComparison, 'Prozedurtyp');
end;

procedure TTestRdxSimpleFixesDetector.Sca126_PathOperands;
begin
  // 'FList.First' ist eine Methode ohne Argumente: nicht als Feld
  // bewiesen, keine Hilfe.
  AssertNoHelp(Format(UNIT_126_FACTORY, [Join([
    '  if FList.First = nil then',
    '    Exit(False);',
    '  Result := True;'])]), fkNilComparison, 'nicht als Feld bewiesen');
  // 'P.Next' endet auf ein Feld der Unit (TNode.Next: TNode) - die Hilfe
  // kommt; 'FItems[I]' vergleicht ein Ergebnis (uTestRdxNilFix prueft die
  // Operanden-Regel selbst).
  Assert.AreEqual(
    Format(UNIT_126, [Join([
      '  while Assigned(P.Next) do',
      '    P := P.Next;',
      '  Result := True;'])]),
    FixAll(Format(UNIT_126, [Join([
      '  while P.Next <> nil do',
      '    P := P.Next;',
      '  Result := True;'])]), fkNilComparison));
end;

{ ---- SCA074 ---- }

procedure TTestRdxSimpleFixesDetector2.Sca074_RoundTrip;
begin
  Assert.AreEqual(InRoutine(Join([
      'Assert(Obj <> nil, ''Obj <> nil'');',
      'Assert(Assigned(Obj), ''ok'');',
      'Assert(Pos(''a'', ''b'') = 0, ''Pos(''''a'''', ''''b'''') = 0'');',
      'if Obj = nil then Assert(False, ''False'');'])),
    FixAll(InRoutine(Join([
      'Assert(Obj <> nil);',
      'Assert(Assigned(Obj), ''ok'');',
      'Assert(Pos(''a'', ''b'') = 0);',
      'if Obj = nil then Assert(False);'])), fkAssertMessage));
end;

procedure TTestRdxSimpleFixesDetector2.Sca074_OwnAssert_NoHelp;
begin
  // Eine eigene Routine Assert bindet vor System.Assert. Geprueft wird der
  // Aufruf in Zeile 9 - der Detektor meldet auch die Deklaration in
  // Zeile 4 (Gegen-Review 2026-10-10).
  AssertNoHelpAt(Join(['unit t;', 'interface', 'implementation',
    'procedure Assert(B: Boolean);', 'begin', 'end;',
    'procedure P;', 'begin', '  Assert(True);', 'end;', 'end.']),
    fkAssertMessage, 9, 'eigene Routine');
end;

procedure TTestRdxSimpleFixesDetector2.Sca074_InWith_NoHelp;
begin
  AssertNoHelp(InRoutine(Join(['with Obj do', '  Assert(True);'])),
    fkAssertMessage, 'with');
end;

procedure TTestRdxSimpleFixesDetector2.Sca074_CatalogExample;
var
  Meta : TRuleMeta;
begin
  // Das Katalog-'good' traegt eine Begruendung in Worten; die Hilfe kann
  // nur die Bedingung selbst einsetzen - das Muster (Bedingung, Meldung)
  // ist dasselbe, und der Detektor schweigt danach.
  Meta := TRuleCatalog.GetRuleCanonical(fkAssertMessage);
  Assert.AreEqual('Assert(Items.Count > 0);', Snip(Meta.BadExample));
  Assert.AreEqual(InRoutine('Assert(Items.Count > 0, ''Items.Count > 0'');'),
    FixAll(InRoutine(Snip(Meta.BadExample)), fkAssertMessage));
  Assert.AreEqual<Integer>(0, Length(Detect(InRoutine(Snip(Meta.GoodExample)),
    fkAssertMessage)), 'good meldet nichts');
end;

{ ---- SCA087 ---- }

procedure TTestRdxSimpleFixesDetector2.Sca087_RoundTrip;
begin
  Assert.AreEqual(InInterface(Join([
      'type',
      '  TFoo = class',
      '  private',
      '    FX: Integer;',
      '  public',
      '    procedure P;',
      '  end;',
      '  TBar = class',
      '    FY: Integer;',
      '  end;'])),
    FixAll(InInterface(Join([
      'type',
      '  TFoo = class',
      '  public',
      '  strict private',
      '  private',
      '    FX: Integer;',
      '  protected',
      '  public',
      '    procedure P;',
      '  end;',
      '  TBar = class',
      '    FY: Integer;',
      '  published',
      '  end;'])), fkEmptyVisibilitySection));
end;

procedure TTestRdxSimpleFixesDetector2.Sca087_CatalogExample;
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkEmptyVisibilitySection);
  Assert.IsTrue(Pos('public', Meta.BadExample) > 0, Meta.BadExample);
  Assert.AreEqual(InInterface(Snip(Meta.GoodExample)),
    FixAll(InInterface(Snip(Meta.BadExample)), fkEmptyVisibilitySection));
end;

{ ---- SCA139 ---- }

const
  // Ein Feld, eine Property und eine Methode (kein Destruktor), deren
  // Rumpf die Faelle einsetzen; Changed folgt, sonst waere Free die letzte
  // Anweisung (der Detektor schweigt dann).
  UNIT_139 =
    'unit t;'#13#10 +
    'interface'#13#10 +
    'uses System.Classes;'#13#10 +
    'type'#13#10 +
    '%s'#13#10 +
    '  TFoo = class'#13#10 +
    '  private'#13#10 +
    '    FList: TList;'#13#10 +
    '%s'#13#10 +
    '  public'#13#10 +
    '    property Items: TList read FList write FList;'#13#10 +
    '    procedure Reset;'#13#10 +
    '    procedure Changed;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    '%s'#13#10 +
    'procedure TFoo.Reset;'#13#10 +
    'begin'#13#10 +
    '%s'#13#10 +
    '  Changed;'#13#10 +
    'end;'#13#10 +
    'procedure TFoo.Changed;'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    'end.';

procedure TTestRdxSimpleFixesDetector2.Sca139_RoundTrip;
begin
  Assert.AreEqual(
    Format(UNIT_139, ['', '', 'uses System.SysUtils;', Join([
      '  if Assigned(FList) then FreeAndNil(FList);',
      '  FreeAndNil(FList);'])]),
    FixAll(Format(UNIT_139, ['', '', 'uses System.SysUtils;', Join([
      '  if Assigned(FList) then FList.Free;',
      '  FList.Free;'])]), fkFreeWithoutNil));
end;

procedure TTestRdxSimpleFixesDetector2.Sca139_MissingSysUtils_AddsUses;
var
  After : string;
begin
  After := FixAll(Format(UNIT_139, ['', '', '', '  FList.Free;']), fkFreeWithoutNil);
  Assert.IsTrue(Pos('FreeAndNil(FList);', After) > 0, After);
  Assert.AreEqual<Integer>(1, CountOf('SysUtils', After),
    'SysUtils genau einmal ergaenzt: ' + After);
end;

procedure TTestRdxSimpleFixesDetector2.Sca139_Property_NoHelp;
begin
  AssertNoHelp(Format(UNIT_139, ['', '', 'uses System.SysUtils;',
    '  Items.Free;']), fkFreeWithoutNil, 'Property');
end;

procedure TTestRdxSimpleFixesDetector2.Sca139_RecordWithFree_NoHelp;
begin
  // 'FRec.Free' ruft die Methode des Records - FreeAndNil(FRec) waere
  // falsch: Delphi ab 10.4 bricht ab (E2010), FPC und aeltere Delphi
  // nehmen den Record still als untypisiertes var-Argument.
  AssertNoHelp(Format(UNIT_139, [
    '  TRec = record'#13#10'    procedure Free;'#13#10'  end;',
    '    FRec: TRec;', 'uses System.SysUtils;',
    '  FRec.Free;']), fkFreeWithoutNil, 'kein Objekt');
end;

procedure TTestRdxSimpleFixesDetector2.Sca139_OwnFreeMethod_NoHelp;
begin
  // 'FBuf.Free' gibt das Objekt an den Pool zurueck; FreeAndNil(FBuf)
  // zerstoerte es.
  AssertNoHelp(Format(UNIT_139, [
    '  TPooled = class'#13#10'    procedure Free; reintroduce;'#13#10'  end;',
    '    FBuf: TPooled;', 'uses System.SysUtils;',
    '  FBuf.Free;']), fkFreeWithoutNil, 'eigene Methode Free');
end;

procedure TTestRdxSimpleFixesDetector2.Sca139_CatalogExample;
const
  // L als Unit-Global: eine lokale Variable meldet der Detektor nicht
  // (sie faellt mit der Routine aus dem Scope).
  WRAP =
    'unit t;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'uses System.Classes, System.SysUtils;'#13#10 +
    'var'#13#10 +
    '  L: TStringList;'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '%s'#13#10 +
    'end;'#13#10 +
    'end.';
var
  Meta  : TRuleMeta;
  After : string;
begin
  // Katalog 'good' laesst die Use-After-Free-Zeile weg und kommentiert
  // anders - verglichen wird die Ersetzung, nicht der ganze Text.
  Meta := TRuleCatalog.GetRuleCanonical(fkFreeWithoutNil);
  Assert.IsTrue(Pos('L.Free;', Meta.BadExample) > 0, Meta.BadExample);
  After := FixAll(Format(WRAP, [Snip(Meta.BadExample)]), fkFreeWithoutNil);
  Assert.IsTrue(Pos('  FreeAndNil(L);', After) > 0, After);
  Assert.IsTrue(Pos('L.Free', After) = 0, After);
  Assert.IsTrue(Pos('FreeAndNil(L);', Meta.GoodExample) > 0, Meta.GoodExample);
end;

{ ---- SCA066 ---- }

procedure TTestRdxSimpleFixesDetector3.Sca066_RoundTrip;
begin
  Assert.AreEqual(InRoutine(Join([
      'Obj := TObject.Create;',
      'Obj.Free;'])),
    FixAll(InRoutine(Join([
      'Obj := TObject.Create();',
      'Obj.Free();'])), fkEmptyArgumentList));
end;

procedure TTestRdxSimpleFixesDetector3.Sca066_InExpression_NoHelp;
begin
  // Als Argument koennte der Name ohne Klammern als Zeiger gelten.
  AssertNoHelp(InRoutine('if Assigned(Obj.ClassType()) then Exit;'),
    fkEmptyArgumentList, 'Ausdrucks');
end;

procedure TTestRdxSimpleFixesDetector3.Sca066_FpcFile_NoHelp;
begin
  AssertNoHelp(Join(['unit t;', '{$mode delphi}', 'interface',
    'implementation', 'procedure P;', 'begin', '  Init();', 'end;', 'end.']),
    fkEmptyArgumentList, 'FPC');
end;

// Anweisungen in einer Funktion mit Ergebnis Integer - das Katalog-
// Beispiel weist an Result zu, dessen Typ die Hilfe prueft.
function InFunction(const AStatements: string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation',
    'function F: Integer;', 'begin',
    '  ' + StringReplace(AStatements, #13#10, #13#10'  ', [rfReplaceAll]),
    'end;', 'end.']);
end;

procedure TTestRdxSimpleFixesDetector3.Sca066_CatalogExample;
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkEmptyArgumentList);
  Assert.IsTrue(Pos('()', Meta.BadExample) > 0, Meta.BadExample);
  Assert.AreEqual(InFunction(Snip(Meta.GoodExample)),
    FixAll(InFunction(Snip(Meta.BadExample)), fkEmptyArgumentList));
end;

procedure TTestRdxSimpleFixesDetector3.Sca066_ProcTarget_NoHelp;
begin
  // cnwizards CnViewSMRUnit: Proc ist prozedural - 'Proc := PrevNextProc'
  // laese die Funktion als Methodenzeiger statt sie aufzurufen.
  AssertNoHelp(Join(['unit t;', 'interface', 'type',
    '  TPrevNextProc = procedure(const S: string) of object;',
    '  TFoo = class',
    '    function PrevNextProc: TPrevNextProc;',
    '    procedure Run;',
    '  end;',
    'implementation',
    'function TFoo.PrevNextProc: TPrevNextProc;', 'begin', '  Result := nil;', 'end;',
    'procedure TFoo.Run;', 'var', '  Proc: TPrevNextProc;', 'begin',
    '  Proc := PrevNextProc();', 'end;', 'end.']),
    fkEmptyArgumentList, 'Prozedurtyp');
end;

procedure TTestRdxSimpleFixesDetector3.Sca066_ProcVariable_NoHelp;
begin
  AssertNoHelp(Join(['unit t;', 'interface', 'type', '  TCall = procedure;',
    'implementation', 'procedure P(Cb: TCall);', 'begin', '  Cb();', 'end;',
    'end.']), fkEmptyArgumentList, 'Variable');
end;

{ ---- SCA072 ---- }

const
  // Je eine Variable vom Typ Boolean und LongBool; der Rumpf (%s) ohne
  // Einrueckung, wie die Katalog-Beispiele.
  UNIT_072 =
    'unit t;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  Active: Boolean;'#13#10 +
    '  Disabled: Boolean;'#13#10 +
    '  Win: LongBool;'#13#10 +
    'begin'#13#10 +
    '%s'#13#10 +
    'end;'#13#10 +
    'end.';

procedure TTestRdxSimpleFixesDetector3.Sca072_RoundTrip;
begin
  Assert.AreEqual(
    Format(UNIT_072, [Join([
      'if Active then Exit;',
      'if not Disabled then Exit;',
      'while not Active do Exit;'])]),
    FixAll(Format(UNIT_072, [Join([
      'if Active = True then Exit;',
      'if Disabled <> True then Exit;',
      'while Active = False do Exit;'])]), fkRedundantBoolean));
end;

procedure TTestRdxSimpleFixesDetector3.Sca072_LongBool_NoHelp;
begin
  // LongBool(2) ist wahr, aber nicht gleich True - die Hilfe aenderte das.
  AssertNoHelp(Format(UNIT_072, ['if Win = True then Exit;']),
    fkRedundantBoolean, 'longbool');
end;

procedure TTestRdxSimpleFixesDetector3.Sca072_UnknownType_NoHelp;
begin
  AssertNoHelp(Format(UNIT_072, ['if Flag = True then Exit;']),
    fkRedundantBoolean, 'unbekannt');
end;

procedure TTestRdxSimpleFixesDetector3.Sca072_InWith_NoHelp;
begin
  AssertNoHelp(Format(UNIT_072, [Join(['with TObject.Create do',
    '  if Active = True then Exit;'])]), fkRedundantBoolean, 'with');
end;

procedure TTestRdxSimpleFixesDetector3.Sca072_CatalogExample;
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkRedundantBoolean);
  Assert.IsTrue(Pos('= True', Meta.BadExample) > 0, Meta.BadExample);
  Assert.AreEqual(Format(UNIT_072, [Snip(Meta.GoodExample)]),
    FixAll(Format(UNIT_072, [Snip(Meta.BadExample)]), fkRedundantBoolean));
end;

{ ---- SCA084 ---- }

procedure TTestRdxSimpleFixesDetector3.Sca084_RoundTrip;
begin
  Assert.AreEqual(InRoutine(Join([
      'if Assigned(Obj) then Exit;',
      'if Assigned(Obj) then Exit;'])),
    FixAll(InRoutine(Join([
      'if Assigned(Obj) and (Obj <> nil) then Exit;',
      'if (Obj <> nil) and Assigned(Obj) then Exit;'])),
      fkAssignedAndAssignedNil));
  // E27 (Charge R10): eine Klasse der Delphi-Quellen aus einer anderen
  // Unit ist bewiesen (uRdxRtlTypes) - derselbe Beweis wie bei SCA126.
  Assert.AreEqual(Join(['unit t;', 'interface', 'implementation',
    'uses System.Classes;', 'procedure P;', 'var', '  L: TStringList;', 'begin',
    '  if Assigned(L) then Exit;', 'end;', 'end.']),
    FixAll(Join(['unit t;', 'interface', 'implementation',
      'uses System.Classes;', 'procedure P;', 'var', '  L: TStringList;', 'begin',
      '  if Assigned(L) and (L <> nil) then Exit;', 'end;', 'end.']),
      fkAssignedAndAssignedNil));
end;

procedure TTestRdxSimpleFixesDetector3.Sca084_ProcType_NoHelp;
begin
  // 'Cb <> nil' ruft die Prozedur auf, Assigned(Cb) nicht.
  AssertNoHelp(Join(['unit t;', 'interface', 'type', '  TCall = procedure;',
    'implementation', 'procedure P(Cb: TCall);', 'begin',
    '  if Assigned(Cb) and (Cb <> nil) then Exit;', 'end;', 'end.']),
    fkAssignedAndAssignedNil, 'Prozedurtyp');
end;

procedure TTestRdxSimpleFixesDetector3.Sca084_UnknownType_NoHelp;
begin
  AssertNoHelp(InRoutine('if Assigned(Foo) and (Foo <> nil) then Exit;'),
    fkAssignedAndAssignedNil, 'unbekannt');
end;

procedure TTestRdxSimpleFixesDetector3.Sca084_FuncAlias_NoHelp;
begin
  // 'Lookup <> nil' ruft die Funktion auf; der Alias versteckt den Typ.
  AssertNoHelp(Join(['unit t;', 'interface', 'type',
    '  TObjFunc = function: TObject;', '  TLookup = TObjFunc;',
    'implementation', 'procedure P(Lookup: TLookup);', 'begin',
    '  if Assigned(Lookup) and (Lookup <> nil) then Exit;', 'end;', 'end.']),
    fkAssignedAndAssignedNil, 'Prozedurtyp');
end;

procedure TTestRdxSimpleFixesDetector3.Sca084_OwnAssigned_NoHelp;
begin
  AssertNoHelp(Join(['unit t;', 'interface', 'implementation',
    'function Assigned(P: Pointer): Boolean;', 'begin', '  Result := True;',
    'end;', 'procedure P;', 'var', '  Obj: TObject;', 'begin',
    '  if Assigned(Obj) and (Obj <> nil) then Exit;', 'end;', 'end.']),
    fkAssignedAndAssignedNil, 'eigene Routine');
end;

procedure TTestRdxSimpleFixesDetector3.Sca084_OtherUnitType_NoHelp;
begin
  // TChromium (CEF) ist eine Klasse - beweisen laesst es sich weder in
  // dieser Unit noch ueber die Liste der Delphi-Quellen; SCA084 bleibt bei
  // der Zulassungsliste (bis E27 stand hier TStringList, seitdem bewiesen:
  // Sca084_RoundTrip).
  AssertNoHelp(Join(['unit t;', 'interface', 'implementation',
    'uses uCef;', 'procedure P;', 'var', '  L: TChromium;', 'begin',
    '  if Assigned(L) and (L <> nil) then Exit;', 'end;', 'end.']),
    fkAssignedAndAssignedNil, 'nicht als Klasse');
end;

procedure TTestRdxSimpleFixesDetector3.Sca084_CatalogExample;
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkAssignedAndAssignedNil);
  Assert.IsTrue(Pos('<> nil', Meta.BadExample) > 0, Meta.BadExample);
  Assert.AreEqual(InRoutine(Snip(Meta.GoodExample)),
    FixAll(InRoutine(Snip(Meta.BadExample)), fkAssignedAndAssignedNil));
end;

procedure TTestRdxSimpleFixesDetector3.Catalog_EditorHelpMatchesHelps;
var
  K    : TFindingKind;
  Want : Boolean;
begin
  // Hilfen = TRdxFixTable.Handles, dazu die Rezepte Format() (SCA044) und
  // SQL-Vorlage (SCA003, Zwischenablage - auch eine Code-Aktion zum Fund,
  // Q17 2026-10-23) sowie 'Marker entfernen' (SCA165). Nicht:
  // uses-qualifizieren (ein Umbau, keine Hilfe).
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Want := TRdxFixTable.Handles(K)
      or (K in [fkConcatToFormat, fkSQLInjection, fkUnusedSuppression]);
    Assert.AreEqual(Want, TRuleCatalog.GetRuleCanonical(K).EditorHelp,
      'editorHelp in rules/sca-rules.json: ' + KindName(K));
  end;
end;

{ ---- SCA007 ---- }

const
  // uses-Klausel im implementation-Teil (%s), eine Routine ohne Bezug auf
  // System.Classes oder System.Math - SysUtils gilt dem Detektor als
  // immer benoetigt.
  UNIT_007 =
    'unit t;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    '%s'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '  Exit;'#13#10 +
    'end;'#13#10 +
    'end.';

procedure TTestRdxSimpleFixesDetector4.Sca007_RoundTrip;
begin
  // Erst der erste Eintrag, dann der letzte (ab dem Komma davor).
  Assert.AreEqual(Format(UNIT_007, ['uses System.SysUtils;']),
    FixAll(Format(UNIT_007,
      ['uses System.Classes, System.SysUtils, System.Math;']), fkUnusedUses));
end;

procedure TTestRdxSimpleFixesDetector4.Sca007_OnlyEntry_RemovesClause;
begin
  Assert.AreEqual(Join(['unit t;', 'interface', 'implementation',
      'procedure P;', 'begin', '  Exit;', 'end;', 'end.']),
    FixAll(Format(UNIT_007, ['uses' + #13#10 + '  System.Classes;']),
      fkUnusedUses));
end;

procedure TTestRdxSimpleFixesDetector4.Sca007_MarkedAsBehaviorChange;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // Entscheid E2: eine Unit kann im initialization-Abschnitt registrieren.
  Src := Format(UNIT_007, ['uses System.Classes, System.SysUtils;']);
  Seen := Detect(Src, fkUnusedUses);
  Assert.AreEqual<Integer>(1, Length(Seen), 'nur System.Classes');
  // Ueber den Einstieg des Anbieters wie PlanMain (bis zur Review Woche
  // G07-27 eine vierte Hand-Kopie des Laufs).
  O := PlanMain(Src, fkUnusedUses, Seen[0]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsTrue(O.ChangesBehavior, 'Kennzeichnung (aendert Verhalten)');
  Assert.AreEqual('System.Classes', O.Name);
end;

{ ---- SCA168 ---- }

procedure TTestRdxSimpleFixesDetector4.Sca168_RoundTrip;
begin
  Assert.AreEqual(InRoutine(Join(['case Obj.Tag of', '  1: Exit;', 'else',
      'end;'])),
    FixAll(InRoutine(Join(['case Obj.Tag of', '  1: Exit;', 'end;'])),
      fkDefaultCaseInCaseStatement));
end;

procedure TTestRdxSimpleFixesDetector4.Sca168_Raise_AddsUses;
var
  Src, After : string;
  Seen       : TArray<TSeen>;
  O          : TRdxFixOutcome;
begin
  // Ohne SysUtils: die uses-Ergaenzung kommt mit (EInvalidOpException).
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure P(X: Integer);',
    'begin', '  case X of', '    1: Exit;', '  end;', 'end;', 'end.']);
  Seen := Detect(Src, fkDefaultCaseInCaseStatement);
  Assert.AreEqual<Integer>(1, Length(Seen));
  O := PlanAltFix(Src, fkDefaultCaseInCaseStatement, Seen[0]);
  Assert.AreEqual<Integer>(1, O.Variant, 'zweiter Eintrag');
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsTrue(O.ChangesBehavior, 'Kennzeichnung (aendert Verhalten)');
  After := Apply(Src, O.Edits);
  Assert.IsTrue(Pos('raise EInvalidOpException.Create(', After) > 0, After);
  Assert.AreEqual<Integer>(1, CountOf('SysUtils', After), After);
  Assert.AreEqual<Integer>(0, Length(Detect(After, fkDefaultCaseInCaseStatement)),
    'der Detektor schweigt');
end;

procedure TTestRdxSimpleFixesDetector4.Sca168_FpcFile_Raise_ShortUses;
var
  Src    : string;
  After  : string;
  Seen   : TArray<TSeen>;
  O      : TRdxFixOutcome;
  Edits  : TArray<TRdxEdit>;
  Reason : string;
begin
  // EInvalidOpException steht auch in SysUtils von FPC 3.2.2: die
  // raise-Variante gilt in FPC-Dateien, die uses-Ergaenzung nimmt den
  // Kurznamen (FPC 3.2 kennt keine Unit-Scopes). Bis 2026-10-22 sperrte
  // EProgrammerError (gibt es in keiner RTL) die Variante hier.
  Src := Join(['unit t;', '{$mode delphi}', 'interface', 'implementation',
    'procedure P(X: Integer);', 'begin', '  case X of', '    1: Exit;', '  end;',
    'end;', 'end.']);
  Seen := Detect(Src, fkDefaultCaseInCaseStatement);
  Assert.AreEqual<Integer>(1, Length(Seen));
  O := PlanAltFix(Src, fkDefaultCaseInCaseStatement, Seen[0]);
  Assert.AreEqual<Integer>(1, O.Variant, 'zweiter Eintrag');
  Assert.IsTrue(O.Enabled, O.Reason);
  After := Apply(Src, O.Edits);
  Assert.IsTrue(Pos('raise EInvalidOpException.Create(', After) > 0, After);
  Assert.AreEqual<Integer>(1, CountOf('SysUtils', After), After);
  Assert.AreEqual<Integer>(0, Pos('System.SysUtils', After), After);
  // Das leere else bleibt auch in FPC-Dateien verfuegbar.
  Assert.IsTrue(PlanFix(Src, fkDefaultCaseInCaseStatement, Seen[0], Edits,
    Reason), Reason);
end;

procedure TTestRdxSimpleFixesDetector4.Sca168_CatalogExample;
var
  Meta  : TRuleMeta;
  Bad   : string;
  Seen  : TArray<TSeen>;
  O     : TRdxFixOutcome;
begin
  // 'good' traegt raise mit einem anderen Text ('Unhandled status') - die
  // leere Hilfe schreibt das else, die zweite das raise; danach schweigt
  // der Detektor.
  Meta := TRuleCatalog.GetRuleCanonical(fkDefaultCaseInCaseStatement);
  Assert.IsTrue(Pos('raise EInvalidOpException.Create(', Meta.GoodExample) > 0,
    Meta.GoodExample);
  Bad := InRoutine(Snip(Meta.BadExample));
  Assert.AreEqual(StringReplace(Bad, #13#10'  end;', #13#10'  else'#13#10'  end;',
    []), FixAll(Bad, fkDefaultCaseInCaseStatement));
  Seen := Detect(Bad, fkDefaultCaseInCaseStatement);
  Assert.AreEqual<Integer>(1, Length(Seen), 'der Detektor meldet');
  O := PlanAltFix(Bad, fkDefaultCaseInCaseStatement, Seen[0]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(0, Length(Detect(Apply(Bad, O.Edits),
    fkDefaultCaseInCaseStatement)), 'der Detektor schweigt');
end;

procedure TTestRdxSimpleFixesDetector4.Sca168_LastArmIf_RoundTrip;
begin
  // Ohne ';' hinter dem letzten Arm bande das else an das if - die Hilfe
  // setzt es mit, danach schweigt der Detektor.
  Assert.AreEqual(InRoutine(Join(['case Obj.Tag of',
      '  1: if Obj = nil then Exit;', 'else', 'end;'])),
    FixAll(InRoutine(Join(['case Obj.Tag of', '  1: if Obj = nil then Exit',
      'end;'])), fkDefaultCaseInCaseStatement));
end;

procedure TTestRdxSimpleFixesDetector4.Sca007_StaleFinding_NoHelp;
var
  Src    : string;
  Seen   : TSeen;
  Edits  : TArray<TRdxEdit>;
  Reason : string;
begin
  // Der Fund stammt aus einem aelteren Scan; inzwischen steht TStringList
  // im Text - die Unit wird gebraucht.
  Src := Join(['unit t;', 'interface', 'implementation',
    'uses System.Classes, System.SysUtils;', 'procedure P;', 'begin',
    '  TStringList.Create.Free;', 'end;', 'end.']);
  Seen.Line := 4;
  Seen.Msg := 'System.Classes';
  Assert.IsFalse(PlanFix(Src, fkUnusedUses, Seen, Edits, Reason));
  Assert.IsTrue(Pos('benutzt', Reason) > 0, Reason);
end;

// Ein Geschwister-Eintrag in uses ('mormot.core.os.security' neben
// 'mormot.core.os') ist kein Bezug: vorher las UnitStillUsed die
// uses-Klausel mit, sah 'os' '.' und sperrte die Hilfe mit "wird im Text
// benutzt" (Wochen-Review 2026-10-21). Ein voll qualifizierter Bezug im
// Code zaehlt weiter.
procedure TTestRdxSimpleFixesDetector4.Sca007_NamespaceSibling_NotAUse;
var
  Src    : string;
  Seen   : TSeen;
  Edits  : TArray<TRdxEdit>;
  Reason : string;
begin
  Src := Join(['unit t;', 'interface', 'implementation',
    'uses mormot.core.os, mormot.core.os.security;', 'procedure P;', 'begin',
    '  Exit;', 'end;', 'end.']);
  Seen.Line := 4;
  Seen.Msg := 'mormot.core.os';
  Assert.IsTrue(PlanFix(Src, fkUnusedUses, Seen, Edits, Reason),
    'Geschwister in uses: ' + Reason);
  Src := Join(['unit t;', 'interface', 'implementation',
    'uses mormot.core.os, mormot.core.os.security;', 'procedure P;', 'begin',
    '  mormot.core.os.Sleep(1);', 'end;', 'end.']);
  Assert.IsFalse(PlanFix(Src, fkUnusedUses, Seen, Edits, Reason),
    'voll qualifizierter Bezug');
  Assert.IsTrue(Pos('benutzt', Reason) > 0, Reason);
end;

procedure TTestRdxSimpleFixesDetector4.Alternative_OtherKinds_None;
var
  Seen : TSeen;
begin
  Seen.Line := 4;
  Seen.Msg := 'System.Classes';
  Assert.AreEqual<Integer>(0, PlanAltFix(Format(UNIT_007,
    ['uses System.Classes;']), fkUnusedUses, Seen).Variant,
    'nur SCA168 und SCA020 haben einen zweiten Eintrag');
end;

// Die Klasse hinter 'raise ' bis zum ersten Punkt; '' ohne beides.
function RaisedClass(const ATemplate: string): string;
var
  P, Q : Integer;
begin
  Result := '';
  P := Pos('raise ', ATemplate);
  Q := Pos('.', ATemplate);
  if (P > 0) and (Q > P + Length('raise ')) then
    Result := Copy(ATemplate, P + Length('raise '),
      Q - P - Length('raise '));
end;

// Die Klassen, die eine Hilfe in Nutzercode schreibt, gibt es in
// System.SysUtils von Delphi 12 und 13 und in SysUtils von FPC 3.2.2
// (2026-10-22: SCA168 schrieb EProgrammerError - die Klasse gibt es in
// keiner RTL, nach dem Klick kompilierte der Code nicht, E2003). Die
// Positivliste ist aus den RTL-Quellen abgeschrieben (System.SysUtils.pas
// Zeilen 468-597, FPC sysutilh.inc); eine neue Klasse erst dort
// nachsehen, dann hier eintragen.
procedure TTestRdxSimpleFixesDetector4.RaisedClasses_ExistInRtl;
const
  RTL_CLASSES: array[0..4] of string = ('EArgumentException',
    'EArgumentOutOfRangeException', 'EInvalidOpException', 'ENotImplemented',
    'ENotSupportedException');
  TEMPLATES: array[0..1] of string = (RAISE_UNHANDLED, RAISE_NOT_IMPLEMENTED);
var
  Template, Cls, Known : string;
  Found                : Boolean;
begin
  for Template in TEMPLATES do
  begin
    Cls := RaisedClass(Template);
    Found := False;
    for Known in RTL_CLASSES do
      if SameText(Known, Cls) then
        Found := True;
    Assert.IsTrue(Found, Format('%s schreibt "%s" - nicht in der Positivliste',
      [Template, Cls]));
  end;
end;

{ ---- SCA101 / SCA099 ---- }

procedure TTestRdxSimpleFixesDetector5.Sca101_RoundTrip;
begin
  // then und else auf eigenen Zeilen, do inline - Fund fuer Fund, bis der
  // Detektor schweigt.
  Assert.AreEqual(InRoutine(Join(['if Obj <> nil then', 'begin', '  Obj.Free;',
      'end', 'else', 'begin', '  Obj := nil;', 'end;', 'while Obj <> nil do',
      'begin', '  Obj := nil;', 'end;'])),
    FixAll(InRoutine(Join(['if Obj <> nil then', '  Obj.Free', 'else',
      '  Obj := nil;', 'while Obj <> nil do Obj := nil;'])), fkBeginEndRequired));
end;

procedure TTestRdxSimpleFixesDetector5.Sca101_CatalogExample;
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkBeginEndRequired);
  Assert.AreEqual(InRoutine(Snip(Meta.GoodExample)),
    FixAll(InRoutine(Snip(Meta.BadExample)), fkBeginEndRequired));
end;

procedure TTestRdxSimpleFixesDetector5.Sca101_CaseElse_RoundTrip;
begin
  // Das else des case traegt eine Anweisungsliste: sie kommt ganz in den
  // Block, nicht nur ihre erste Anweisung.
  Assert.AreEqual(InRoutine(Join(['case Ord(Obj = nil) of', '  0: Obj := nil;',
      'else', 'begin', '  Obj.Free;', '  Obj := nil;', 'end;', 'end;'])),
    FixAll(InRoutine(Join(['case Ord(Obj = nil) of', '  0: Obj := nil;', 'else',
      '  Obj.Free;', '  Obj := nil;', 'end;'])), fkBeginEndRequired));
end;

procedure TTestRdxSimpleFixesDetector5.Sca101_StaleFinding_NoHelp;
var
  Seen   : TArray<TSeen>;
  Edits  : TArray<TRdxEdit>;
  Reason : string;
begin
  // Der Fund stammt aus einem aelteren Scan; inzwischen steht der Zweig in
  // begin..end.
  Seen := Detect(InRoutine('if Obj <> nil then Obj.Free;'), fkBeginEndRequired);
  Assert.AreEqual<Integer>(1, Length(Seen), 'der Detektor meldet');
  Assert.IsFalse(PlanFix(InRoutine('if Obj <> nil then begin Obj.Free; end;'),
    fkBeginEndRequired, Seen[0], Edits, Reason));
  Assert.IsTrue(Pos('schon in begin..end', Reason) > 0, Reason);
end;

procedure TTestRdxSimpleFixesDetector5.Sca101_SameMeaning;
var
  Src     : string;
  Seen    : TArray<TSeen>;
  SL      : TStringList;
  Finding : TLeakFinding;
  O       : TRdxFixOutcome;
begin
  // Bedeutungsgleich: kein '(changes behavior)', Strg+Alt+F darf sie
  // ausfuehren; der Hinweis sagt es. Ueber die Tabelle - sie setzt den
  // Hinweis, nicht der Rumpf (Charge R8); BlockFix braucht keinen Dienst.
  Src := InRoutine('if Obj <> nil then Obj.Free;');
  Seen := Detect(Src, fkBeginEndRequired);
  Assert.AreEqual<Integer>(1, Length(Seen), 'der Detektor meldet');
  SL := TStringList.Create;
  Finding := nil;
  try
    Finding := TLeakFinding.New('t.pas', '', Seen[0].Line, Seen[0].Msg,
      fkBeginEndRequired);
    SL.Text := Src;
    O := TRdxFixTable.FixFor(nil, SL, Finding, nil);
  finally
    Finding.Free;
    SL.Free;
  end;
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsFalse(O.ChangesBehavior);
  Assert.IsTrue(Pos('gleiche Bedeutung', O.Hint) > 0, O.Hint);
end;

procedure TTestRdxSimpleFixesDetector5.Sca099_RoundTrip_SilencesSca101;
var
  Src, Want : string;
begin
  // 'end else X;' melden beide Regeln; beide Hilfen schreiben dasselbe, und
  // danach schweigen beide Detektoren.
  Src := InRoutine(Join(['if Obj = nil then', 'begin', '  Obj := nil;',
    'end else Obj.Free;']));
  Want := InRoutine(Join(['if Obj = nil then', 'begin', '  Obj := nil;',
    'end else', 'begin', '  Obj.Free;', 'end;']));
  Assert.AreEqual(Want, FixAll(Src, fkIfElseBegin));
  Assert.AreEqual(Want, FixAll(Src, fkBeginEndRequired));
  Assert.AreEqual<Integer>(0, Length(Detect(Want, fkBeginEndRequired)),
    'SCA101 schweigt nach der SCA099-Hilfe');
end;

procedure TTestRdxSimpleFixesDetector5.Sca099_CatalogExample;
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkIfElseBegin);
  Assert.AreEqual(InRoutine(Snip(Meta.GoodExample)),
    FixAll(InRoutine(Snip(Meta.BadExample)), fkIfElseBegin));
end;

procedure TTestRdxSimpleFixesDetector5.Sca099_AnonMethodHeader_NoHelp;
var
  Src : string;
begin
  // Das ';' im var-Teil der anonymen Methode ist kein case-else: beide
  // Regeln bieten nichts an, statt 'H();' in den else-Zweig zu ziehen.
  Src := InRoutine(Join(['if Obj = nil then', '  H := procedure', '    var',
    '      S: string;', '    begin', '      S := ''x'';', '    end', 'else',
    '  H := nil;', 'H();']));
  AssertNoHelp(Src, fkIfElseBegin, 'anonymen Methode');
  AssertNoHelpAt(Src, fkBeginEndRequired, 16, 'anonymen Methode');
end;

{ ---- SCA082 / SCA071 / SCA088 / SCA123 ---- }

// Eine Unit: interface, implementation, dann AText (CRLF), dann 'end.'.
function InImplementation(const AText: string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', AText, 'end.']);
end;

procedure TTestRdxSimpleFixesDetector6.Sca082_RoundTrip_CatalogExample;
var
  Meta : TRuleMeta;
begin
  Assert.AreEqual(InRoutine('Obj := nil;'),
    FixAll(InRoutine('Obj := nil;;'), fkSuperfluousSemicolon));
  Meta := TRuleCatalog.GetRuleCanonical(fkSuperfluousSemicolon);
  Assert.AreEqual(InRoutine(Snip(Meta.GoodExample)),
    FixAll(InRoutine(Snip(Meta.BadExample)), fkSuperfluousSemicolon));
end;

procedure TTestRdxSimpleFixesDetector6.Sca071_RoundTrip;
begin
  // uses meldet der Detektor nur allein auf der Zeile.
  Assert.AreEqual(Join(['unit t;', 'interface', 'uses', '  System.SysUtils;',
      'implementation', 'end.']),
    FixAll(Join(['unit t;', 'interface', '  uses', '  System.SysUtils;',
      '  implementation', 'end.']), fkUnitLevelKeywordIndent));
end;

procedure TTestRdxSimpleFixesDetector6.Sca071_CatalogExample;
var
  Meta      : TRuleMeta;
  Bad, Done : string;
begin
  // 'good' rueckt auch 'procedure Foo' aus - das meldet die Regel nicht;
  // verglichen wird die Zeile des Schluesselworts.
  Meta := TRuleCatalog.GetRuleCanonical(fkUnitLevelKeywordIndent);
  Assert.IsTrue(Pos('implementation', Snip(Meta.GoodExample)) = 1,
    Meta.GoodExample);
  Bad := Join(['unit t;', 'interface', Snip(Meta.BadExample), 'end.']);
  Done := FixAll(Bad, fkUnitLevelKeywordIndent);
  Assert.AreEqual(StringReplace(Bad, '  implementation', 'implementation', []),
    Done);
end;

procedure TTestRdxSimpleFixesDetector6.Sca088_RoundTrip_CatalogExample;
var
  Meta : TRuleMeta;
  Done : string;
begin
  Assert.AreEqual(InImplementation(Join(['procedure P; begin end;',
      'initialization', '  P;'])),
    FixAll(InImplementation(Join(['procedure P; begin end;', 'begin', '  P;'])),
      fkLegacyInitializationSection));
  // 'bad' traegt eine Kommentarzeile davor, 'good' nicht - 'good' steht im
  // Ergebnis.
  Meta := TRuleCatalog.GetRuleCanonical(fkLegacyInitializationSection);
  Done := FixAll(Join(['unit t;', 'interface', 'implementation',
    Snip(Meta.BadExample)]), fkLegacyInitializationSection);
  Assert.IsTrue(Pos(Snip(Meta.GoodExample), Done) > 0, Done);
end;

// Eine Routine mit der Variablen L vom Typ ADecl und der Anweisung AStmt.
function WithLocal(const ADecl, AStmt: string): string;
begin
  Result := InImplementation(Join(['uses System.Classes;', 'procedure P;',
    'var', '  L: ' + ADecl + ';', 'begin', '  ' + AStmt, 'end;']));
end;

procedure TTestRdxSimpleFixesDetector6.Sca123_RoundTrip;
begin
  // Nur der Cast auf den eigenen Typ ist beweisbar ohne Wirkung.
  Assert.AreEqual(WithLocal('TStringList', 'L.Free;'),
    FixAll(WithLocal('TStringList', 'TStringList(L).Free;'), fkCastAndFree));
end;

procedure TTestRdxSimpleFixesDetector6.Sca123_CatalogExample_NoHelp;
var
  Meta : TRuleMeta;
begin
  // Das Katalog-Beispiel castet ein TObject auf TStringList - ob
  // TStringList Free verdeckt, weiss die Hilfe nicht (dafuer braeuchte sie
  // den Typindex); sie bietet nichts an.
  Meta := TRuleCatalog.GetRuleCanonical(fkCastAndFree);
  AssertNoHelp(InImplementation(Snip(Meta.BadExample)), fkCastAndFree,
    'nicht als');
end;

procedure TTestRdxSimpleFixesDetector6.Sca123_OtherType_NoHelp;
begin
  // dwsUtils: TRefCountedObject.Free zaehlt nur herunter - 'L.Free' auf
  // einem TObject zerstoerte das Objekt.
  AssertNoHelp(WithLocal('TObject', 'TRefCountedObject(L).Free;'), fkCastAndFree,
    'nicht als');
  // Pointer: ohne den Cast uebersetzt 'L.Free' nicht.
  AssertNoHelp(WithLocal('Pointer', 'TObject(L).Free;'), fkCastAndFree,
    'nicht als');
  // Ein Feld aus einer anderen Unit: Typ unbekannt.
  AssertNoHelp(InRoutine('TStringList(FOther).Free;'), fkCastAndFree,
    'unbekannt');
end;

{ ---- SCA020 / SCA120 / SCA122 ---- }

procedure TTestRdxSimpleFixesDetector7.Sca020_RoundTrip;
begin
  // Der Absichtskommentar: danach schweigt der Detektor.
  Assert.AreEqual(InImplementation(Join(['procedure P;', 'begin',
      '  ' + INTENT_LINE, 'end;'])),
    FixAll(InImplementation(Join(['procedure P;', 'begin', 'end;'])),
      fkEmptyMethod));
  // Die Inline-Form auf einer Zeile: uEmptyMethod.BodyHasIntentComment
  // nimmt '{ intentionally empty }' hinter dem begin als Absicht (Review
  // Woche G07-28 - bis dahin nur ohne Detektor geprueft).
  Assert.AreEqual(InImplementation('procedure P; begin ' + INTENT_INLINE
      + ' end;'),
    FixAll(InImplementation('procedure P; begin end;'), fkEmptyMethod));
end;

procedure TTestRdxSimpleFixesDetector7.Sca020_Raise_AddsUses;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
  Done : string;
begin
  // Zweiter Eintrag: raise ENotImplemented, gekennzeichnet; SysUtils fehlt
  // und kommt mit.
  Src := InImplementation(Join(['procedure P;', 'begin', 'end;']));
  Seen := Detect(Src, fkEmptyMethod);
  Assert.AreEqual<Integer>(1, Length(Seen), 'der Detektor meldet');
  O := PlanAltFix(Src, fkEmptyMethod, Seen[0]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(1, O.Variant);
  Assert.IsTrue(O.ChangesBehavior, 'gekennzeichnet (E2)');
  Done := Apply(Src, O.Edits);
  Assert.IsTrue(Pos('raise ENotImplemented.Create(''P'');', Done) > 0, Done);
  Assert.IsTrue(Pos('SysUtils', Done) > 0, Done);
  Assert.AreEqual<Integer>(0, Length(Detect(Done, fkEmptyMethod)),
    'der Detektor schweigt');
end;

procedure TTestRdxSimpleFixesDetector7.Sca020_CatalogExample;
var
  Meta      : TRuleMeta;
  Bad, Want : string;
  Seen      : TArray<TSeen>;
  O         : TRdxFixOutcome;
begin
  // 'good' traegt raise mit '...' als Text - die Hilfe setzt den Namen ein.
  Meta := TRuleCatalog.GetRuleCanonical(fkEmptyMethod);
  Bad := Join(['unit t;', 'interface', 'implementation', 'uses System.SysUtils;',
    Snip(Meta.BadExample), 'end.']);
  Want := Join(['unit t;', 'interface', 'implementation', 'uses System.SysUtils;',
    StringReplace(Snip(Meta.GoodExample), 'Create('''')',
      'Create(''DoStuff'')', []), 'end.']);
  Seen := Detect(Bad, fkEmptyMethod);
  Assert.AreEqual<Integer>(1, Length(Seen), 'der Detektor meldet');
  O := PlanAltFix(Bad, fkEmptyMethod, Seen[0]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual(Want, Apply(Bad, O.Edits));
end;

procedure TTestRdxSimpleFixesDetector7.Sca120_RoundTrip_CatalogExample;
var
  Meta : TRuleMeta;
  Bad  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // 'good' hat keinen Kommentar mehr - verglichen wird die Ersetzung.
  Meta := TRuleCatalog.GetRuleCanonical(fkMissingRaise);
  Assert.IsTrue(Pos('raise EArgumentOutOfRangeException.Create(',
    Meta.GoodExample) > 0, Meta.GoodExample);
  Bad := InImplementation(Snip(Meta.BadExample));
  Assert.AreEqual(StringReplace(Bad, '    EArgumentOutOfRangeException.Create(',
      '    raise EArgumentOutOfRangeException.Create(', []),
    FixAll(Bad, fkMissingRaise));
  // Aendert das Verhalten (das ist der Fix) - gekennzeichnet nach E2.
  Seen := Detect(Bad, fkMissingRaise);
  O := PlanMain(Bad, fkMissingRaise, Seen[0]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsTrue(O.ChangesBehavior, 'gekennzeichnet (E2)');
end;

procedure TTestRdxSimpleFixesDetector7.Sca122_RoundTrip_CatalogExample;
var
  Meta : TRuleMeta;
  Bad  : string;
begin
  // 'good' traegt einen anderen Kommentar - verglichen wird die Ersetzung.
  Meta := TRuleCatalog.GetRuleCanonical(fkReRaiseException);
  Assert.IsTrue(Pos('raise;', Meta.GoodExample) > 0, Meta.GoodExample);
  Bad := InRoutine(Snip(Meta.BadExample));
  Assert.AreEqual(StringReplace(Bad, 'raise E;', 'raise;', []),
    FixAll(Bad, fkReRaiseException));
end;

procedure TTestRdxSimpleFixesDetector7.Sca122_InnerTry_NoHelp;
begin
  // Im except eines inneren try waere 'raise;' die innere Exception.
  AssertNoHelp(InRoutine(Join(['try', '  Obj.Free;', 'except',
    '  on E: Exception do', '    try', '      Obj := nil;', '    except',
    '      raise E;', '    end;', 'end;'])), fkReRaiseException, 'inneren try');
end;

{ ---- SCA117 / SCA197 / SCA149 ---- }

procedure TTestRdxSimpleFixesDetector8.Sca117_RoundTrip;
begin
  // Je Member das Geruest - Parameter, Index-Parameter, returns nur bei
  // Funktionen; danach schweigt der Detektor.
  Assert.AreEqual(InInterface(Join(['type', '  TFoo = class', '  public',
      '    /// <summary></summary>', '    /// <param name="A"></param>',
      '    /// <param name="B"></param>',
      '    procedure Run(A: Integer; const B: string);',
      '    /// <summary></summary>', '    /// <returns></returns>',
      '    function Count: Integer;',
      '    /// <summary></summary>', '    /// <param name="I"></param>',
      '    property Items[I: Integer]: string read GetItem;', '  end;'])),
    FixAll(InInterface(Join(['type', '  TFoo = class', '  public',
      '    procedure Run(A: Integer; const B: string);',
      '    function Count: Integer;',
      '    property Items[I: Integer]: string read GetItem;', '  end;'])),
      fkPublicMemberWithoutDoc));
end;

procedure TTestRdxSimpleFixesDetector8.Sca117_CatalogExample;
var
  Meta : TRuleMeta;
begin
  // 'good' traegt einen Summary-Text - das Geruest bleibt leer.
  Meta := TRuleCatalog.GetRuleCanonical(fkPublicMemberWithoutDoc);
  Assert.AreEqual(InInterface(StringReplace(Snip(Meta.GoodExample),
      'Starts the worker.', '', [])),
    FixAll(InInterface(Snip(Meta.BadExample)), fkPublicMemberWithoutDoc));
end;

procedure TTestRdxSimpleFixesDetector8.Sca197_RoundTrip_CatalogExample;
const
  CATALOG_GUID = '{4F2C1A80-91D3-4E7B-B0A6-6C3E1D9F2B54}';
var
  Meta            : TRuleMeta;
  Bad, Done, Guid : string;
  P               : Integer;
begin
  // 'bad' traegt hinter dem Interface einen Aufruf - nur die Deklaration
  // zaehlt. Die GUID ist neu: gelesen, als GUID geprueft und fuer den
  // Vergleich gegen die des Katalogs getauscht.
  Meta := TRuleCatalog.GetRuleCanonical(fkInterfaceWithoutGuid);
  Bad := Snip(Meta.BadExample);
  Bad := InInterface(Copy(Bad, 1, Pos('end;', Bad) + 3));
  Done := FixAll(Bad, fkInterfaceWithoutGuid);
  P := Pos('[''{', Done);
  Assert.IsTrue(P > 0, Done);
  Guid := Copy(Done, P + 2, Length(CATALOG_GUID));
  Assert.AreEqual(Guid, GUIDToString(StringToGUID(Guid)), 'eine GUID');
  Assert.AreNotEqual(CATALOG_GUID, Guid);
  Assert.AreEqual(InInterface(Snip(Meta.GoodExample)),
    StringReplace(Done, Guid, CATALOG_GUID, []));
end;

procedure TTestRdxSimpleFixesDetector8.Sca197_ComImport_NoHelp;
begin
  // Ein COM-Import braucht die echte IID - eine neue GUID waere falsch.
  AssertNoHelp(InInterface(Join(['type', '  IComThing = interface(IUnknown)',
    '    function Ping: HResult; stdcall;', '  end;'])),
    fkInterfaceWithoutGuid, 'COM-Import');
end;

procedure TTestRdxSimpleFixesDetector8.Sca149_Override_CatalogExample;
var
  Meta : TRuleMeta;
  Bad  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // 'good' zeigt nur TDerived ohne Kommentar - verglichen wird die
  // Ersetzung. override aendert, wohin der virtuelle Aufruf geht:
  // gekennzeichnet nach E2.
  Meta := TRuleCatalog.GetRuleCanonical(fkMissingOverride);
  Assert.IsTrue(Pos('procedure DoWork; override;', Meta.GoodExample) > 0,
    Meta.GoodExample);
  Bad := InInterface('type'#13#10 + Snip(Meta.BadExample));
  Seen := Detect(Bad, fkMissingOverride);
  Assert.AreEqual<Integer>(1, Length(Seen), 'der Detektor meldet');
  O := PlanMain(Bad, fkMissingOverride, Seen[0]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual(DIRECTIVE_OVERRIDE, O.Name);
  Assert.IsTrue(O.ChangesBehavior, 'gekennzeichnet (E2)');
  Assert.AreEqual(StringReplace(Bad, 'procedure DoWork;   ',
      'procedure DoWork; override;   ', []),
    FixAll(Bad, fkMissingOverride));
end;

procedure TTestRdxSimpleFixesDetector8.Sca149_Reintroduce_RoundTrip;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // Abweichende Signatur: override waere ein Compilerfehler - reintroduce,
  // bedeutungsgleich (nur W1010 entfaellt), nicht gekennzeichnet.
  Src := InInterface(Join(['type', '  TBase = class',
    '    procedure DoWork; virtual;', '  end;', '  TDerived = class(TBase)',
    '    procedure DoWork(A: Integer);', '  end;']));
  Seen := Detect(Src, fkMissingOverride);
  Assert.AreEqual<Integer>(1, Length(Seen), 'der Detektor meldet');
  O := PlanMain(Src, fkMissingOverride, Seen[0]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual(DIRECTIVE_REINTRODUCE, O.Name);
  Assert.IsFalse(O.ChangesBehavior, 'bedeutungsgleich');
  Assert.AreEqual(StringReplace(Src, 'DoWork(A: Integer);',
      'DoWork(A: Integer); reintroduce;', []),
    FixAll(Src, fkMissingOverride));
end;

{ ---- SCA098 / SCA080 / SCA047 ---- }

procedure TTestRdxSimpleFixesDetector9.Sca098_RoundTrip;
begin
  // Vorwaerts ueber Zeilen, Gegenrichtung mit Vergleich und mit einem
  // Boolean-Bezeichner; Result ist Boolean (Funktion), Done eine lokale
  // Boolean-Variable. Danach schweigt der Detektor.
  Assert.AreEqual(InImplementation(Join(['function F(A, B: Integer): Boolean;',
      'var', '  Done: Boolean;', 'begin', '  Result := A > B;',
      '  Done := not (A = B);', '  Result := not Done;', 'end;'])),
    FixAll(InImplementation(Join(['function F(A, B: Integer): Boolean;', 'var',
      '  Done: Boolean;', 'begin', '  if A > B then', '    Result := True',
      '  else', '    Result := False;',
      '  if A = B then Done := False else Done := True;',
      '  if Done then Result := False else Result := True;', 'end;'])),
      fkRedundantConditional));
end;

procedure TTestRdxSimpleFixesDetector9.Sca098_CatalogExample;
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkRedundantConditional);
  Assert.AreEqual(InImplementation(Join(['function F(Active: Boolean): Boolean;',
      'begin', '  ' + Snip(Meta.GoodExample), 'end;'])),
    FixAll(InImplementation(Join(['function F(Active: Boolean): Boolean;',
      'begin', '  ' + Snip(Meta.BadExample), 'end;'])), fkRedundantConditional));
end;

procedure TTestRdxSimpleFixesDetector9.Sca098_NotProvenBoolean_NoHelp;
begin
  // Ein Variant bekaeme den Wert der Bedingung statt True/False.
  AssertNoHelp(InImplementation(Join(['function F(A: Integer): Boolean;', 'var',
    '  V: Variant;', 'begin', '  if A > 0 then V := True else V := False;',
    '  Result := V;', 'end;'])), fkRedundantConditional,
    'nicht als Boolean bewiesen');
  // Gegenrichtung mit einem Aufruf als C: sein Typ ist nicht bewiesen
  // (bei einem Variant waere 'not' bitweise).
  AssertNoHelp(InImplementation(Join(['function IsOk(A: Integer): Boolean;',
    'begin', '  Result := A > 0;', 'end;', 'procedure P(A: Integer);', 'var',
    '  Done: Boolean;', 'begin',
    '  if IsOk(A) then Done := False else Done := True;', 'end;'])),
    fkRedundantConditional, 'Bedingung ist nicht als Boolean bewiesen');
end;

procedure TTestRdxSimpleFixesDetector9.Sca098_InWith_NoHelp;
begin
  // Im with-Block koennte Done ein Member des with-Ausdrucks sein.
  AssertNoHelp(InImplementation(Join(['procedure P(A: Boolean);', 'var',
    '  Obj: TObject;', '  Done: Boolean;', 'begin', '  with Obj do', '  begin',
    '    if A then Done := True else Done := False;', '  end;', 'end;'])),
    fkRedundantConditional, 'with');
end;

procedure TTestRdxSimpleFixesDetector9.Sca080_RoundTrip_CatalogExample;
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkRedundantJump);
  Assert.AreEqual(InImplementation(Snip(Meta.GoodExample)),
    FixAll(InImplementation(Snip(Meta.BadExample)), fkRedundantJump));
  // Continue hinter dem else eines if: 'else Continue' faellt weg.
  Assert.AreEqual(InImplementation(Join(['procedure Q(A: Boolean);', 'var',
      '  I: Integer;', 'begin', '  for I := 0 to 9 do', '  begin',
      '    if A then', '      Beep;', '  end;', 'end;'])),
    FixAll(InImplementation(Join(['procedure Q(A: Boolean);', 'var',
      '  I: Integer;', 'begin', '  for I := 0 to 9 do', '  begin',
      '    if A then', '      Beep', '    else', '      Continue;', '  end;',
      'end;'])), fkRedundantJump));
end;

procedure TTestRdxSimpleFixesDetector9.Sca080_ThenExit_NoHelp;
begin
  // 'if A then Exit;' am Ende: es bliebe 'if A then' stehen.
  AssertNoHelp(InImplementation(Join(['procedure P(A: Boolean);', 'begin',
    '  Beep;', '  if A then Exit;', 'end;'])), fkRedundantJump, 'hinter then');
end;

procedure TTestRdxSimpleFixesDetector9.Sca047_RoundTrip;
const
  HEAD = 'type'#13#10'  TFoo = class'#13#10'    FCount: Integer;'#13#10
    + '    procedure Run(ACount: Integer);'#13#10'  end;'#13#10
    + 'procedure TFoo.Run(ACount: Integer);'#13#10'var'#13#10
    + '  Temp: string;'#13#10'begin'#13#10'  Temp := ''x'';'#13#10;
begin
  // Lokale Variable, Feld der Unit, Parameter - jede Zeile faellt weg.
  Assert.AreEqual(InImplementation(HEAD + Join(['  Beep;', 'end;'])),
    FixAll(InImplementation(HEAD + Join(['  Temp := Temp;', '  FCount := FCount;',
      '  ACount := ACount;', '  Beep;', 'end;'])), fkSelfAssignment));
end;

procedure TTestRdxSimpleFixesDetector9.Sca047_CatalogExample;
const
  HEAD = 'type'#13#10'  TFoo = class'#13#10'    FCount: Integer;'#13#10
    + '    procedure SetCount(ACount: Integer);'#13#10'  end;'#13#10
    + 'procedure TFoo.SetCount(ACount: Integer);'#13#10'begin'#13#10
    + '  Beep;'#13#10;
var
  Meta : TRuleMeta;
begin
  // 'good' zeigt den gemeinten Wert (Tippfehler ACount) - die Hilfe kann
  // ihn nicht raten und loescht die wirkungslose Zuweisung.
  Meta := TRuleCatalog.GetRuleCanonical(fkSelfAssignment);
  Assert.AreEqual('FCount := ACount;', Snip(Meta.GoodExample));
  Assert.AreEqual(InImplementation(HEAD + 'end;'),
    FixAll(InImplementation(HEAD + '  ' + Snip(Meta.BadExample) + #13#10
      + 'end;'), fkSelfAssignment));
end;

procedure TTestRdxSimpleFixesDetector9.Sca047_ResultAndWith_NoHelp;
begin
  // Result := Result stillt vielleicht eine Compiler-Meldung.
  AssertNoHelp(InImplementation(Join(['function F: Integer;', 'begin',
    '  Result := 1;', '  Result := Result;', 'end;'])), fkSelfAssignment,
    'Result');
  // Im with-Block koennte X ein Member mit Setter sein.
  AssertNoHelp(InImplementation(Join(['procedure P;', 'var', '  Obj: TObject;',
    '  X: Integer;', 'begin', '  X := 1;', '  with Obj do', '  begin',
    '    Beep;', '    X := X;', '  end;', 'end;'])), fkSelfAssignment, 'with');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxSimpleFixesDetector);
  TDUnitX.RegisterTestFixture(TTestRdxSimpleFixesDetector2);
  TDUnitX.RegisterTestFixture(TTestRdxSimpleFixesDetector3);
  TDUnitX.RegisterTestFixture(TTestRdxSimpleFixesDetector4);
  TDUnitX.RegisterTestFixture(TTestRdxSimpleFixesDetector5);
  TDUnitX.RegisterTestFixture(TTestRdxSimpleFixesDetector6);
  TDUnitX.RegisterTestFixture(TTestRdxSimpleFixesDetector7);
  TDUnitX.RegisterTestFixture(TTestRdxSimpleFixesDetector8);
  TDUnitX.RegisterTestFixture(TTestRdxSimpleFixesDetector9);

end.

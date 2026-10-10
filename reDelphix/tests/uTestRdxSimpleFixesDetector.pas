unit uTestRdxSimpleFixesDetector;

// Editorhilfen Stufe 2a gegen den ECHTEN Core (nur Delphi, reDelphix.Test):
// Parser, die Detektoren SCA075/SCA085/SCA126 (dazu SCA074/SCA087/SCA139
// in der zweiten, SCA066/SCA072/SCA084 in der dritten, SCA007/SCA168 in
// der vierten, SCA101/SCA099 in der fuenften Fixture),
// TSourcePlaces und
// TRdxFixRunner.FixFor - derselbe Einstieg wie im Anbieter. Je Fall meldet
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
    [Test] procedure Sca168_FpcFile_NoRaise;
    [Test] procedure Sca168_CatalogExample;
    // Gegen-Review 2026-10-10.
    [Test] procedure Sca168_LastArmIf_RoundTrip;
    [Test] procedure Sca007_StaleFinding_NoHelp;
    [Test] procedure Alternative_OtherKinds_None;
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
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uParser2, uMethodd12, uSCAConsts, uRuleCatalog,
  uExplicitTObjectInheritance, uFreeAndNilHint, uNilComparison,
  uAssertMessage, uEmptyVisibilitySection, uFreeWithoutNil,
  uEmptyArgumentList, uRedundantBoolean, uAssignedAndAssignedNil,
  uUnusedUses, uDefaultCaseInCaseStatement, uBeginEndRequired, uIfElseBegin,
  uEngineApi, uRdxBufferMath, uRdxRecipeRunner;

type
  // Was die Hilfe aus einem Fund liest - wie der Anbieter aus TLeakFinding.
  TSeen = record
    Line : Integer;
    Msg  : string;
  end;

// ---- Helfer ----

function WriteTemp(const ASource: string): string;
var
  SL : TStringList;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP'))
    + 'rdx_simple_' + GUIDToString(TGUID.NewGuid) + '.pas';
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    SL.SaveToFile(Result);
  finally
    SL.Free;
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
    Assert.Fail('keine Hilfe fuer diese Art');
  end;
end;

// Funde der Art AKind - der echte Detektor auf dem echten AST.
function Detect(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
var
  Path    : string;
  Parser  : TParser2;
  Root    : TAstNode;
  Results : TObjectList<TLeakFinding>;
  F       : TLeakFinding;
  n       : Integer;
begin
  Result := nil;
  Path := WriteTemp(ASource);
  Results := TObjectList<TLeakFinding>.Create(True);
  try
    Parser := TParser2.Create;
    try
      Root := Parser.ParseFile(Path);
      try
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
      finally
        Root.Free;
      end;
    finally
      Parser.Free;
    end;
    SetLength(Result, Results.Count);
    n := 0;
    for F in Results do
      if F.Kind = AKind then
      begin
        Result[n].Line := F.LineInt;
        Result[n].Msg  := F.Message;
        Inc(n);
      end;
    SetLength(Result, n);
  finally
    Results.Free;
    DeleteFile(Path);
  end;
end;

// Die Hilfe fuer EINEN Fund ueber den Einstieg des Anbieters: der Fund
// als TLeakFinding, der Quellstellen-Dienst auf demselben Text.
function PlanFix(const ASource: string; AKind: TFindingKind;
  const ASeen: TSeen; out AEdits: TArray<TRdxEdit>; out AReason: string): Boolean;
var
  SL      : TStringList;
  Places  : TSourcePlaces;
  Finding : TLeakFinding;
  O       : TRdxFixOutcome;
begin
  Assert.IsTrue(TRdxFixRunner.Handles(AKind), 'FixFor kennt die Art');
  SL := TStringList.Create;
  Places := TSourcePlaces.Create;
  Finding := TLeakFinding.New('t.pas', '', ASeen.Line, ASeen.Msg, AKind);
  try
    SL.Text := ASource;
    Assert.IsTrue(Places.OpenSource('t.pas', ASource), 'OpenSource');
    O := TRdxFixRunner.FixFor(Places, SL, Finding,
      TRdxRecipeRunner.UsesNamesOf(Places));
  finally
    Finding.Free;
    Places.Free;
    SL.Free;
  end;
  AEdits  := O.Edits;
  AReason := O.Reason;
  Result  := O.Enabled;
end;

// Der zweite Eintrag (TRdxFixRunner.AlternativeFixFor) fuer EINEN Fund -
// heute nur SCA168 (else mit raise).
function PlanAltFix(const ASource: string; AKind: TFindingKind;
  const ASeen: TSeen): TRdxFixOutcome;
var
  SL      : TStringList;
  Places  : TSourcePlaces;
  Finding : TLeakFinding;
begin
  SL := TStringList.Create;
  Places := TSourcePlaces.Create;
  Finding := TLeakFinding.New('t.pas', '', ASeen.Line, ASeen.Msg, AKind);
  try
    SL.Text := ASource;
    Assert.IsTrue(Places.OpenSource('t.pas', ASource), 'OpenSource');
    Result := TRdxFixRunner.AlternativeFixFor(Places, SL, Finding,
      TRdxRecipeRunner.UsesNamesOf(Places));
  finally
    Finding.Free;
    Places.Free;
    SL.Free;
  end;
end;

// Schreibt wie der Editor: alle Ersetzungen gegen denselben Puffer geprueft.
function Apply(const ASource: string; const AEdits: TArray<TRdxEdit>): string;
var
  Bytes : TBytes;
  Plan  : TArray<TRdxByteEdit>;
  Err   : string;
begin
  Bytes := TEncoding.UTF8.GetBytes(ASource);
  Assert.IsTrue(PlanByteEdits(Bytes, AEdits, Plan, Err), Err);
  Result := TEncoding.UTF8.GetString(ApplyByteEdits(Bytes, Plan));
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet (wie der Benutzer es
// taete), bis der Detektor schweigt.
function FixAll(const ASource: string; AKind: TFindingKind): string;
const
  MAX_PASSES = 10;
var
  Seen   : TArray<TSeen>;
  Edits  : TArray<TRdxEdit>;
  Reason : string;
  Pass   : Integer;
begin
  Result := ASource;
  for Pass := 1 to MAX_PASSES do
  begin
    Seen := Detect(Result, AKind);
    if Length(Seen) = 0 then Exit;
    Assert.IsTrue(PlanFix(Result, AKind, Seen[0], Edits, Reason),
      Format('Zeile %d: %s', [Seen[0].Line, Reason]));
    Result := Apply(Result, Edits);
  end;
  Assert.Fail(Format('der Detektor meldet nach %d Runden noch', [MAX_PASSES]));
end;

// Der erste Fund muss abgelehnt werden, mit AReasonPart im Grund.
procedure AssertNoHelp(const ASource: string; AKind: TFindingKind;
  const AReasonPart: string);
var
  Seen   : TArray<TSeen>;
  Edits  : TArray<TRdxEdit>;
  Reason : string;
begin
  Seen := Detect(ASource, AKind);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet');
  Assert.IsFalse(PlanFix(ASource, AKind, Seen[0], Edits, Reason), 'keine Hilfe');
  Assert.IsTrue(Pos(AReasonPart, Reason) > 0, Reason);
end;

// Wie AssertNoHelp, aber fuer den Fund auf Zeile ALine.
procedure AssertNoHelpAt(const ASource: string; AKind: TFindingKind;
  ALine: Integer; const AReasonPart: string);
var
  Seen   : TArray<TSeen>;
  S      : TSeen;
  Edits  : TArray<TRdxEdit>;
  Reason : string;
begin
  Seen := Detect(ASource, AKind);
  for S in Seen do
    if S.Line = ALine then
    begin
      Assert.IsFalse(PlanFix(ASource, AKind, S, Edits, Reason), 'keine Hilfe');
      Assert.IsTrue(Pos(AReasonPart, Reason) > 0, Reason);
      Exit;
    end;
  Assert.Fail(Format('kein Fund auf Zeile %d', [ALine]));
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

function Join(const ALines: array of string): string;
begin
  Result := string.Join(#13#10, ALines);
end;

// Ein Katalog-Beispiel als Quelltext: '...' faellt weg, Zeilenenden CRLF
// (JSON liefert #10, der eingebaute Katalog #13#10).
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
  Assert.AreEqual(
    Format(UNIT_126, [Join([
      '  if Assigned(FList) then',
      '    FList.Clear;',
      '  while Assigned(P) do',
      '    P := P.Next;',
      '  B := not Assigned(Obj);',
      '  Result := Assigned(FList) and Assigned(Obj);',
      '  Assert(Assigned(Obj), ''x'');',
      '  if not Assigned(Obj) then',
      '    Exit(not Assigned(FList));'])]),
    FixAll(Format(UNIT_126, [Join([
      '  if FList <> nil then',
      '    FList.Clear;',
      '  while P <> nil do',
      '    P := P.Next;',
      '  B := Obj = nil;',
      '  Result := (FList <> nil) and not (Obj = nil);',
      '  Assert(Obj <> nil, ''x'');',
      '  if nil = Obj then',
      '    Exit(FList = nil);'])]), fkNilComparison));
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
  // TStringList ist eine Klasse - beweisen laesst es sich in dieser Unit
  // nicht; SCA084 bleibt bei der Zulassungsliste.
  AssertNoHelp(Join(['unit t;', 'interface', 'implementation',
    'uses System.Classes;', 'procedure P;', 'var', '  L: TStringList;', 'begin',
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
  // Hilfen = TRdxFixRunner.Handles, dazu Format() (SCA044, eigenes Rezept)
  // und 'Marker entfernen' (SCA165). Nicht: die SQL-Vorlage (SCA003, nur
  // Zwischenablage) und uses-qualifizieren (ein Umbau, keine Hilfe).
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Want := TRdxFixRunner.Handles(K)
      or (K in [fkConcatToFormat, fkUnusedSuppression]);
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
  Src     : string;
  Seen    : TArray<TSeen>;
  SL      : TStringList;
  Places  : TSourcePlaces;
  Finding : TLeakFinding;
  O       : TRdxFixOutcome;
begin
  // Entscheid E2: eine Unit kann im initialization-Abschnitt registrieren.
  Src := Format(UNIT_007, ['uses System.Classes, System.SysUtils;']);
  Seen := Detect(Src, fkUnusedUses);
  Assert.AreEqual<Integer>(1, Length(Seen), 'nur System.Classes');
  SL := TStringList.Create;
  Places := TSourcePlaces.Create;
  Finding := TLeakFinding.New('t.pas', '', Seen[0].Line, Seen[0].Msg,
    fkUnusedUses);
  try
    SL.Text := Src;
    Assert.IsTrue(Places.OpenSource('t.pas', Src), 'OpenSource');
    O := TRdxFixRunner.FixFor(Places, SL, Finding,
      TRdxRecipeRunner.UsesNamesOf(Places));
  finally
    Finding.Free;
    Places.Free;
    SL.Free;
  end;
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
  // Ohne SysUtils: die uses-Ergaenzung kommt mit (EProgrammerError).
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure P(X: Integer);',
    'begin', '  case X of', '    1: Exit;', '  end;', 'end;', 'end.']);
  Seen := Detect(Src, fkDefaultCaseInCaseStatement);
  Assert.AreEqual<Integer>(1, Length(Seen));
  O := PlanAltFix(Src, fkDefaultCaseInCaseStatement, Seen[0]);
  Assert.AreEqual<Integer>(1, O.Variant, 'zweiter Eintrag');
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsTrue(O.ChangesBehavior, 'Kennzeichnung (aendert Verhalten)');
  After := Apply(Src, O.Edits);
  Assert.IsTrue(Pos('raise EProgrammerError.Create(', After) > 0, After);
  Assert.AreEqual<Integer>(1, CountOf('SysUtils', After), After);
  Assert.AreEqual<Integer>(0, Length(Detect(After, fkDefaultCaseInCaseStatement)),
    'der Detektor schweigt');
end;

procedure TTestRdxSimpleFixesDetector4.Sca168_FpcFile_NoRaise;
var
  Src    : string;
  Seen   : TArray<TSeen>;
  O      : TRdxFixOutcome;
  Edits  : TArray<TRdxEdit>;
  Reason : string;
begin
  Src := Join(['unit t;', '{$mode delphi}', 'interface', 'implementation',
    'procedure P(X: Integer);', 'begin', '  case X of', '    1: Exit;', '  end;',
    'end;', 'end.']);
  Seen := Detect(Src, fkDefaultCaseInCaseStatement);
  Assert.AreEqual<Integer>(1, Length(Seen));
  O := PlanAltFix(Src, fkDefaultCaseInCaseStatement, Seen[0]);
  Assert.AreEqual<Integer>(1, O.Variant, 'der Eintrag steht da - gesperrt');
  Assert.IsFalse(O.Enabled);
  Assert.IsTrue(Pos('EProgrammerError', O.Reason) > 0, O.Reason);
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
  Assert.IsTrue(Pos('raise EProgrammerError.Create(', Meta.GoodExample) > 0,
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

procedure TTestRdxSimpleFixesDetector4.Alternative_OtherKinds_None;
var
  Seen : TSeen;
begin
  Seen.Line := 4;
  Seen.Msg := 'System.Classes';
  Assert.AreEqual<Integer>(0, PlanAltFix(Format(UNIT_007,
    ['uses System.Classes;']), fkUnusedUses, Seen).Variant,
    'nur SCA168 hat einen zweiten Eintrag');
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
  Src  : string;
  Seen : TArray<TSeen>;
  SL   : TStringList;
  O    : TRdxFixOutcome;
begin
  // Bedeutungsgleich: kein '(changes behavior)', Strg+Alt+F darf sie
  // ausfuehren; der Hinweis sagt es.
  Src := InRoutine('if Obj <> nil then Obj.Free;');
  Seen := Detect(Src, fkBeginEndRequired);
  Assert.AreEqual<Integer>(1, Length(Seen), 'der Detektor meldet');
  SL := TStringList.Create;
  try
    SL.Text := Src;
    O := TRdxFixRunner.BlockFix(fkBeginEndRequired, SL, Seen[0].Line,
      Seen[0].Msg);
  finally
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

initialization
  TDUnitX.RegisterTestFixture(TTestRdxSimpleFixesDetector);
  TDUnitX.RegisterTestFixture(TTestRdxSimpleFixesDetector2);
  TDUnitX.RegisterTestFixture(TTestRdxSimpleFixesDetector3);
  TDUnitX.RegisterTestFixture(TTestRdxSimpleFixesDetector4);
  TDUnitX.RegisterTestFixture(TTestRdxSimpleFixesDetector5);

end.

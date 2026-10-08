unit uTestRdxSimpleFixesDetector;

// Editorhilfen Stufe 2a gegen den ECHTEN Core (nur Delphi, reDelphix.Test):
// Parser, die Detektoren SCA075/SCA085/SCA126, TSourcePlaces und
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
    [Test] procedure Sca126_CatalogExample;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uParser2, uMethodd12, uSCAConsts, uRuleCatalog,
  uExplicitTObjectInheritance, uFreeAndNilHint, uNilComparison,
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
        else
          Assert.Fail('keine Hilfe fuer diese Art');
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

procedure TTestRdxSimpleFixesDetector.Sca126_CatalogExample;
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkNilComparison);
  Assert.IsTrue(Pos('nil', Meta.BadExample) > 0, Meta.BadExample);
  Assert.AreEqual(InRoutine(Snip(Meta.GoodExample)),
    FixAll(InRoutine(Snip(Meta.BadExample)), fkNilComparison));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxSimpleFixesDetector);

end.

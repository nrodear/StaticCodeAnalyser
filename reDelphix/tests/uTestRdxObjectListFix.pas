unit uTestRdxObjectListFix;

// Editorhilfe SCA174 TObjectListWithoutOwnership (uRdxObjectListFix): die
// lokale 'TList<TFoo>', die frische Objekte aufnimmt, wird in Deklaration
// und Create eine 'TObjectList<TFoo>'.
//   Fixture 1 (Text, ohne Parser und Detektor, FPC-tauglich): der Planer
//   auf der Code-Sicht - Umformung (var-Abschnitt, inline, Schreibweise,
//   alle zugelassenen Nutzungen) und die Sperren (Meldung, verschobene
//   Zeile, Parameter, globale Liste, Gruppe, Typ, zwei Zuweisungen,
//   Create mit Argument, fremdes Objekt, Element frei oder als Wert, Liste
//   als Wert, ungepruefte Members, Laufvariable, with, Direktive, uses,
//   eigener Typ).
//   Fixture 2 (nur Delphi): der ECHTE Detektor (uTObjectListWithoutOwnership)
//   auf dem echten AST meldet die Add-Zeile; die Hilfe ueber den Einstieg
//   der Tabelle (TRdxFixTable.FixFor via PlanFixIn/FixAllWith, Adapter
//   PlanObjectList) behebt den Fund, bis der Detektor schweigt.
// Die Quellen haben den Kopf HEAD (Zeilen 1-6, 'procedure Foo;' auf 6);
// die Zeile eines Fundes sucht LineOf, statt sie zu zaehlen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxObjectListFix = class
  public
    // ---- Umformung ----
    [Test] procedure LocalVar_DeclAndCreate_Replaced;
    [Test] procedure InlineVar_TypedAndUntyped_Replaced;
    [Test] procedure Spelling_AndEmptyParens_Kept;
    [Test] procedure CheckedUses_Replaced;
    // ---- Gegenproben ----
    [Test] procedure MessageWithoutNames_NoHelp;
    [Test] procedure MovedLine_CommentOrString_NoHelp;
    [Test] procedure Parameter_NoHelp;
    [Test] procedure GlobalOrOuterVariable_NoHelp;
    [Test] procedure GroupedDeclaration_NoHelp;
    [Test] procedure OtherDeclaredType_NoHelp;
    [Test] procedure TwoAssignments_NoHelp;
    [Test] procedure CreateWithArgument_NoHelp;
    [Test] procedure AddedObjectNotFresh_NoHelp;
    [Test] procedure ItemFreed_NoHelp;
    [Test] procedure ItemAsValue_NoHelp;
    [Test] procedure ListAsValue_NoHelp;
    [Test] procedure UncheckedMemberOrSetter_NoHelp;
    [Test] procedure LoopVariable_NoHelp;
    [Test] procedure WithOrDirective_NoHelp;
    [Test] procedure UsesAndOwnType;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxObjectListDetector = class
  public
    [Test] procedure Detector_ReportsAddLine;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Table_TwoEditsMarkedAndName;
    [Test] procedure Detector_TwoAdds_Fixed;
    [Test] procedure Detector_InlineVar_RoundTrip;
    [Test] procedure Detector_CatalogExample_Fixed;
    [Test] procedure Detector_ItemFreed_NoHelp;
    [Test] procedure Detector_Field_NoHelp;
    [Test] procedure Detector_ReusedVariable_NoHelp;
    // ---- Sperre auf Text (die erste Fixture traegt schon 20 Tests) ----
    [Test] procedure NestedRoutineUse_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog,
  uTObjectListWithoutOwnership,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // TRdxFixTable.CaptionFor
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText, PlanFixIn
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxObjectListFix,
  uRdxText,              // _() und MsgMovedSuffix
  uTestRdxTextKit;       // Join, Apply, LineOf

const
  // Die Meldung des Detektors (uTObjectListWithoutOwnership): Typ der
  // Liste, Name KLEIN, hinzugefuegte Klasse, Typ.
  MSG_FMT = 'TList<%s> "%s" gets a new %s.Create - instances will leak when '
    + 'the list is freed. Use TObjectList<%s> instead (OwnsObjects=True is '
    + 'the default).';
  HEAD: array[0..5] of string = ('unit t;', 'interface', 'uses',
    '  System.Generics.Collections;', 'implementation', 'procedure Foo;');
  STD_DECLS: array[0..1] of string = ('var', '  L: TList<TFoo>;');
  STD_BODY: array[0..5] of string = ('  L := TList<TFoo>.Create;', '  try',
    '    L.Add(TFoo.Create);', '  finally', '    L.Free;', '  end;');
  ADD_TEXT = 'L.Add(TFoo.Create)';
  CRLF = #13#10;

// ---- Helfer ----

function Msg(const AType, AVar, AAdded: string): string;
begin
  Result := Format(MSG_FMT, [AType, LowerCase(AVar), AAdded, AType]);
end;

function StdMsg: string;
begin
  Result := Msg('TFoo', 'l', 'TFoo');
end;

// Eine Unit mit HEAD, den Deklarationen ADecls (auch keine) und dem Rumpf
// ABody der Routine Foo.
function Src(const ADecls, ABody: array of string): string;
begin
  Result := Join(HEAD);
  if Length(ADecls) > 0 then
    Result := Result + CRLF + Join(ADecls);
  Result := Result + CRLF + 'begin' + CRLF + Join(ABody) + CRLF
    + Join(['end;', 'end.']);
end;

function StdSrc: string;
begin
  Result := Src(STD_DECLS, STD_BODY);
end;

// Was die Hilfe aus ASource machen soll: jedes 'TList<' ein 'TObjectList<'.
function Owned(const ASource: string): string;
begin
  Result := StringReplace(ASource, 'TList<', 'TObjectList<', [rfReplaceAll]);
end;

// Der Planer fuer Zeile ALine und Meldung AMsg.
function PlanOf(const ASource: string; ALine: Integer; const AMsg: string;
  out APlan: TRdxObjectListPlan; out AReason: string): Boolean;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    try
      Result := TRdxObjectListFix.OwnItems(Map, ALine, AMsg, APlan, AReason);
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
end;

// Die Hilfe muss gelten (Meldung StdMsg, Zeile des ersten ADD_TEXT); der
// neue Text.
function Fixed(const ASource: string): string;
var
  P : TRdxObjectListPlan;
  R : string;
begin
  Assert.IsTrue(PlanOf(ASource, LineOf(ASource, ADD_TEXT), StdMsg, P, R), R);
  Result := Apply(ASource, P.Edits);
end;

procedure AssertRefusedAt(const ASource: string; ALine: Integer;
  const AReason: string);
var
  P : TRdxObjectListPlan;
  R : string;
begin
  Assert.IsFalse(PlanOf(ASource, ALine, StdMsg, P, R), 'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
  Assert.AreEqual<Integer>(0, Length(P.Edits), 'keine Ersetzung');
  Assert.AreEqual('TFoo', P.Name, 'Name auch bei Ablehnung');
end;

// Keine Hilfe fuer den Fund auf der Zeile des ersten ADD_TEXT.
procedure AssertRefused(const ASource, AReason: string);
begin
  AssertRefusedAt(ASource, LineOf(ASource, ADD_TEXT), AReason);
end;

// Der Standardrumpf mit AExtra vor dem finally (hinter dem ersten Add).
function StdWith(const AExtra: array of string): string;
begin
  Result := Join(HEAD) + CRLF + Join(STD_DECLS) + CRLF
    + Join(['begin', '  L := TList<TFoo>.Create;', '  try',
      '    L.Add(TFoo.Create);']) + CRLF + Join(AExtra) + CRLF
    + Join(['  finally', '    L.Free;', '  end;', 'end;', 'end.']);
end;

// ---- Umformung ----

procedure TTestRdxObjectListFix.LocalVar_DeclAndCreate_Replaced;
var
  P : TRdxObjectListPlan;
  R : string;
begin
  Assert.AreEqual(Owned(StdSrc), Fixed(StdSrc));
  // Zwei Ersetzungen in EINEM Plan: Deklaration (Zeile 8), Create (10).
  Assert.IsTrue(PlanOf(StdSrc, 12, StdMsg, P, R), R);
  Assert.AreEqual<Integer>(2, Length(P.Edits), 'zwei Ersetzungen');
  Assert.AreEqual<Integer>(8, P.Edits[0].Span.StartLine);
  Assert.AreEqual<Integer>(6, P.Edits[0].Span.StartCol);
  Assert.AreEqual<Integer>(10, P.Edits[1].Span.StartLine);
  Assert.AreEqual('TList', P.Edits[1].Expected);
  Assert.AreEqual('TObjectList', P.Edits[1].NewText);
  Assert.AreEqual('TFoo', P.Name);
end;

procedure TTestRdxObjectListFix.InlineVar_TypedAndUntyped_Replaced;
var
  S : string;
  P : TRdxObjectListPlan;
  R : string;
begin
  // 'var L: TList<TFoo> := TList<TFoo>.Create;' - zwei Ersetzungen auf
  // einer Zeile.
  S := Src([], ['  var L: TList<TFoo> := TList<TFoo>.Create;',
    '  L.Add(TFoo.Create);', '  L.Free;']);
  Assert.AreEqual(Owned(S), Fixed(S));
  // 'var L := TList<TFoo>.Create;' - der Typ folgt dem Create.
  S := Src([], ['  var L := TList<TFoo>.Create;', '  L.Add(TFoo.Create);',
    '  L.Free;']);
  Assert.AreEqual(Owned(S), Fixed(S));
  Assert.IsTrue(PlanOf(S, LineOf(S, ADD_TEXT), StdMsg, P, R), R);
  Assert.AreEqual<Integer>(1, Length(P.Edits), 'nur das Create');
end;

procedure TTestRdxObjectListFix.Spelling_AndEmptyParens_Kept;
var
  S : string;
  P : TRdxObjectListPlan;
  R : string;
begin
  // Die Meldung schreibt den Namen klein; der Code darf anders schreiben,
  // 'Create()' ist dasselbe Create. Nur 'TList' wird ersetzt.
  S := Src(['var', '  List: tlist<TFoo>;'], ['  list := TLIST<TFoo>.create();',
    '  LIST.add(TFoo.Create);', '  list.Free;']);
  Assert.IsTrue(PlanOf(S, 11, Msg('TFoo', 'list', 'TFoo'), P, R), R);
  Assert.AreEqual(Src(['var', '  List: TObjectList<TFoo>;'],
    ['  list := TObjectList<TFoo>.create();', '  LIST.add(TFoo.Create);',
     '  list.Free;']), Apply(S, P.Edits));
end;

procedure TTestRdxObjectListFix.CheckedUses_Replaced;
var
  S : string;
begin
  // Alle zugelassenen Nutzungen: Add/Insert frischer Objekte (Argumente
  // Literale), Count, Elemente nur vor einem Member, for-in mit Member-
  // Aufrufen, Assigned, Vergleich mit nil, Sort, Delete, Clear, FreeAndNil.
  S := Src(['var', '  L: TList<TFoo>;', '  i: Integer;', '  E: TFoo;'],
    ['  L := TList<TFoo>.Create;', '  try',
     '    L.Add(TFoo.Create);',
     '    L.Insert(0, TFoo.Create(''x'', 1, nil));',
     '    L.Add(TBar.Create(-1, True));',
     '    for i := 0 to L.Count - 1 do',
     '      L[i].Run;',
     '    L.Items[0].Name := ''a'';',
     '    L.First.Run;',
     '    for E in L do',
     '      E.Run;',
     '    if Assigned(L) and (L <> nil) then',
     '      L.Sort;',
     '    L.Delete(0);',
     '    L.Clear;',
     '  finally',
     '    FreeAndNil(L);',
     '  end;']);
  Assert.AreEqual(Owned(S), Fixed(S));
end;

// ---- Gegenproben ----

procedure TTestRdxObjectListFix.MessageWithoutNames_NoHelp;
var
  P : TRdxObjectListPlan;
  R : string;
begin
  Assert.IsFalse(PlanOf(StdSrc, 12, 'TList leaks', P, R));
  Assert.AreEqual(_(R_OL_NO_MESSAGE), R);
  Assert.IsFalse(PlanOf(StdSrc, 12, 'TList<TFoo> gets a new TFoo.Create', P,
    R));
  Assert.AreEqual(_(R_OL_NO_MESSAGE), R);
  Assert.AreEqual('TFoo', ListTypeArgOf(StdMsg));
  Assert.AreEqual('l', ListVarOf(StdMsg));
end;

procedure TTestRdxObjectListFix.MovedLine_CommentOrString_NoHelp;
var
  R : string;
begin
  R := MsgMovedSuffix(_(R_OL_NO_ADD, ['l']));
  AssertRefusedAt(StdSrc, 11, R);
  AssertRefusedAt(StdSrc, 13, R);
  AssertRefusedAt(StdSrc, 0, R);
  AssertRefusedAt(StdSrc, 99, R);
  // Kommentar und String sind nie Code.
  AssertRefusedAt(StdWith(['    // L.Add(TFoo.Create);']), 13, R);
  AssertRefusedAt(StdWith(['    S := ''L.Add(TFoo.Create)'';']), 13, R);
  // 'Obj.L.Add' ist nicht die Variable L.
  AssertRefusedAt(StdWith(['    Obj.L.Add(TFoo.Create);']), 13, R);
end;

procedure TTestRdxObjectListFix.Parameter_NoHelp;
begin
  AssertRefused(Join(['unit t;', 'interface', 'uses',
    '  System.Generics.Collections;', 'implementation',
    'procedure Foo(L: TList<TFoo>);', 'begin', '  L := TList<TFoo>.Create;',
    '  L.Add(TFoo.Create);', 'end;', 'end.']), _(R_OL_PARAM, ['L']));
end;

procedure TTestRdxObjectListFix.GlobalOrOuterVariable_NoHelp;
begin
  // Eine globale Liste.
  AssertRefused(Join(['unit t;', 'interface', 'uses',
    '  System.Generics.Collections;', 'implementation', 'var',
    '  L: TList<TFoo>;', 'procedure Foo;', 'begin',
    '  L := TList<TFoo>.Create;', '  L.Add(TFoo.Create);', 'end;', 'end.']),
    _(R_OL_NOT_LOCAL, ['L']));
  // Die Liste der aeusseren Routine, gefuellt in der inneren.
  AssertRefused(Join(['unit t;', 'interface', 'uses',
    '  System.Generics.Collections;', 'implementation', 'procedure Outer;',
    'var', '  L: TList<TFoo>;', '  procedure Inner;', '  begin',
    '    L.Add(TFoo.Create);', '  end;', 'begin', '  L := TList<TFoo>.Create;',
    '  Inner;', '  L.Free;', 'end;', 'end.']), _(R_OL_NOT_LOCAL, ['L']));
end;

procedure TTestRdxObjectListFix.GroupedDeclaration_NoHelp;
begin
  AssertRefused(Src(['var', '  L, M: TList<TFoo>;'], STD_BODY),
    _(R_OL_GROUPED, ['L']));
  AssertRefused(Src(['var', '  M, L: TList<TFoo>;'], STD_BODY),
    _(R_OL_GROUPED, ['L']));
  AssertRefused(Src([], ['  var L, M: TList<TFoo>;',
    '  L := TList<TFoo>.Create;', '  L.Add(TFoo.Create);']),
    _(R_OL_GROUPED, ['L']));
end;

procedure TTestRdxObjectListFix.OtherDeclaredType_NoHelp;
begin
  AssertRefused(Src(['var', '  L: TList<TBar>;'], STD_BODY),
    _(R_OL_DECL_TYPE, ['L', 8, 'TFoo']));
  // Qualifiziert: die Hilfe ersetzt nur die einfache Form.
  AssertRefused(Src(['var', '  L: Generics.Collections.TList<TFoo>;'],
    STD_BODY), _(R_OL_DECL_TYPE, ['L', 8, 'TFoo']));
  // Ein Alias ist ein anderer Typ.
  AssertRefused(Src(['var', '  L: TFooList;'], STD_BODY),
    _(R_OL_DECL_TYPE, ['L', 8, 'TFoo']));
  // Eine typisierte Konstante ist keine Variable.
  AssertRefused(Src(['const', '  L: TList<TFoo> = nil;'], STD_BODY),
    _(R_OL_NOT_LOCAL, ['L']));
end;

procedure TTestRdxObjectListFix.TwoAssignments_NoHelp;
begin
  // Wiederverwendung (Posten 306 des Detektors): welches Add zu welcher
  // Liste gehoert, liest die Hilfe nicht.
  AssertRefused(Src(STD_DECLS, ['  L := TList<TFoo>.Create;',
    '  L.Add(TFoo.Create);', '  L.Free;', '  L := TList<TFoo>.Create;',
    '  L.Free;']), _(R_OL_ASSIGNS, ['L', 2, 'TFoo']));
  AssertRefused(Src([], ['  var L := TList<TFoo>.Create;',
    '  L.Add(TFoo.Create);', '  L.Free;', '  L := nil;']),
    _(R_OL_ASSIGNS, ['L', 2, 'TFoo']));
  // Keine Zuweisung in der Routine.
  AssertRefused(Src(STD_DECLS, ['  L.Add(TFoo.Create);']),
    _(R_OL_ASSIGNS, ['L', 0, 'TFoo']));
end;

procedure TTestRdxObjectListFix.CreateWithArgument_NoHelp;
begin
  // Create(Collection) uebernaehme fremde Objekte.
  AssertRefused(Src(STD_DECLS, ['  L := TList<TFoo>.Create(Other);',
    '  L.Add(TFoo.Create);']), _(R_OL_CREATE, ['L', 10, 'TFoo']));
  AssertRefused(Src(STD_DECLS, ['  L := MakeList;', '  L.Add(TFoo.Create);']),
    _(R_OL_CREATE, ['L', 10, 'TFoo']));
  AssertRefused(Src(STD_DECLS, ['  L := TList<TBar>.Create;',
    '  L.Add(TFoo.Create);']), _(R_OL_CREATE, ['L', 10, 'TFoo']));
end;

procedure TTestRdxObjectListFix.AddedObjectNotFresh_NoHelp;
begin
  // Ein Objekt aus einer Variablen kann einen anderen Besitzer haben.
  AssertRefused(StdWith(['    L.Add(Item);']), _(R_OL_ADD_ARG, [13]));
  // Self/Owner als TComponent-Besitzer: der gibt es selbst frei.
  AssertRefused(StdWith(['    L.Add(TFoo.Create(Self));']),
    _(R_OL_ADD_ARG, [13]));
  AssertRefused(StdWith(['    L.Insert(0, Item);']), _(R_OL_ADD_ARG, [13]));
  AssertRefused(StdWith(['    L.Add(TFoo.Create.Init);']),
    _(R_OL_ADD_ARG, [13]));
end;

procedure TTestRdxObjectListFix.ItemFreed_NoHelp;
begin
  // Doppelte Freigabe: die Liste gibt das Element danach noch einmal frei.
  AssertRefused(StdWith(['    L[0].Free;']), _(R_OL_ITEM, [13]));
  AssertRefused(StdWith(['    L.Items[0].Free;']), _(R_OL_ITEM, [13]));
  AssertRefused(StdWith(['    L.Last.Destroy;']), _(R_OL_ITEM, [13]));
  AssertRefused(StdWith(['    FreeAndNil(L[0]);']), _(R_OL_ITEM, [13]));
end;

procedure TTestRdxObjectListFix.ItemAsValue_NoHelp;
begin
  AssertRefused(StdWith(['    X := L[0];']), _(R_OL_ITEM, [13]));
  AssertRefused(StdWith(['    Other.Add(L.First);']), _(R_OL_ITEM, [13]));
  AssertRefused(StdWith(['    with L[0] do Run;']), _(R_OL_WITH));
end;

procedure TTestRdxObjectListFix.ListAsValue_NoHelp;
begin
  AssertRefused(StdWith(['    Keep(L);']), _(R_OL_VALUE, ['L', 13]));
  AssertRefused(StdWith(['    FList := L;']), _(R_OL_VALUE, ['L', 13]));
  AssertRefused(StdWith(['    Exit(L);']), _(R_OL_VALUE, ['L', 13]));
  AssertRefused(StdWith(['    P := @L;']), _(R_OL_VALUE, ['L', 13]));
end;

procedure TTestRdxObjectListFix.UncheckedMemberOrSetter_NoHelp;
begin
  AssertRefused(StdWith(['    X := L.Extract(X);']),
    _(R_OL_MEMBER, ['L', 'Extract', 13]));
  AssertRefused(StdWith(['    L.Remove(X);']),
    _(R_OL_MEMBER, ['L', 'Remove', 13]));
  AssertRefused(StdWith(['    A := L.ToArray;']),
    _(R_OL_MEMBER, ['L', 'ToArray', 13]));
  AssertRefused(StdWith(['    L.OnNotify := Handler;']),
    _(R_OL_MEMBER, ['L', 'OnNotify', 13]));
  AssertRefused(StdWith(['    L.Count := 0;']), _(R_OL_SETTER, [13, 'L']));
  AssertRefused(StdWith(['    L[0] := TFoo.Create;']),
    _(R_OL_SETTER, [13, 'L']));
end;

procedure TTestRdxObjectListFix.LoopVariable_NoHelp;
var
  S : string;
begin
  S := Join(HEAD) + CRLF + Join(['var', '  L: TList<TFoo>;', '  E: TFoo;',
    'begin', '  L := TList<TFoo>.Create;', '  L.Add(TFoo.Create);']);
  // S endet mit Zeile 12 (das Add); die Schleife steht auf Zeile 13.
  AssertRefused(S + CRLF + Join(['  for E in L do E.Free;', 'end;', 'end.']),
    _(R_OL_LOOP_VAR, ['E', 13]));
  AssertRefused(S + CRLF + Join(['  for E in L do', '    Keep(E);', 'end;',
    'end.']), _(R_OL_LOOP_VAR, ['E', 14]));
  AssertRefused(S + CRLF + Join(['  for var X in L do FreeAndNil(X);', 'end;',
    'end.']), _(R_OL_LOOP_VAR, ['X', 13]));
  // Die Laufvariable wird auch ausserhalb der Schleife freigegeben.
  AssertRefused(S + CRLF + Join(['  for E in L do E.Run;', '  E.Free;',
    'end;', 'end.']), _(R_OL_LOOP_VAR, ['E', 14]));
end;

procedure TTestRdxObjectListFix.WithOrDirective_NoHelp;
begin
  AssertRefused(StdWith(['    with Obj do Run;']), _(R_OL_WITH));
  AssertRefused(StdWith(['    {$IFDEF DEBUG}', '    L.Clear;', '    {$ENDIF}']),
    _(R_OL_DIRECTIVE));
end;

procedure TTestRdxObjectListFix.UsesAndOwnType;
var
  S : string;
begin
  // Ohne Generics.Collections in uses: TObjectList<T> kaeme nicht sicher
  // von dort.
  AssertRefused(StringReplace(StdSrc, 'System.Generics.Collections',
    'Spring.Collections', []), _(R_OL_USES));
  // Die kurze Form und eine Liste mehrerer Units zaehlen.
  S := StringReplace(StdSrc, '  System.Generics.Collections;',
    '  System.SysUtils, Generics.Collections in ''gc.pas'', System.Classes;',
    []);
  Assert.AreEqual(Owned(S), Fixed(S));
  // Ein eigener Typ TObjectList bzw. TList in der Datei.
  AssertRefused(StringReplace(StdSrc, 'implementation',
    'type TObjectList<T> = class end;' + CRLF + 'implementation', []),
    _(R_OL_OWN_TYPE, ['TObjectList']));
  AssertRefused(StringReplace(StdSrc, 'implementation',
    'type TList<T> = class end;' + CRLF + 'implementation', []),
    _(R_OL_OWN_TYPE, ['TList']));
end;

{$IFNDEF FPC}

{ ---- Detektor und Tabelle ---- }

// Die Funde der Art SCA174 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TTObjectListWithoutOwnershipDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_ol_', ASource, fkTObjectListWithoutOwnership,
    RunDetector);
end;

// Dasselbe in der Form TDetectFunc (FixAllWith).
function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_ol_', ASource, AKind, RunDetector);
end;

// Die Hilfe fuer den ersten Fund des Detektors ueber den Einstieg der
// Tabelle (PlanFixIn: TRdxFixTable.FixFor, Adapter PlanObjectList).
function PlanFirst(const ASource: string): TRdxFixOutcome;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet einen Fund');
  Result := PlanFixIn(ASource, 't.pas', fkTObjectListWithoutOwnership,
    Seen[0]);
end;

// Fund fuer Fund ueber die Tabelle, nach jeder Ersetzung neu gemeldet, bis
// der Detektor schweigt (FixAllWith).
function FixAll(const ASource: string): string;
begin
  Result := FixAllWith(ASource, fkTObjectListWithoutOwnership, DetectKind);
end;

procedure TTestRdxObjectListDetector.Detector_ReportsAddLine;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(StdSrc);
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(12, Seen[0].Line, 'die Zeile des Add');
  Assert.AreEqual(StdMsg, Seen[0].Msg);
  Assert.AreEqual('l', ListVarOf(Seen[0].Msg), 'Name klein');
  Assert.AreEqual('TFoo', ListTypeArgOf(Seen[0].Msg));
end;

procedure TTestRdxObjectListDetector.Detector_RoundTrip;
var
  Fixed : string;
begin
  Fixed := FixAll(StdSrc);
  Assert.AreEqual(Owned(StdSrc), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxObjectListDetector.Table_TwoEditsMarkedAndName;
var
  O : TRdxFixOutcome;
begin
  // Tabellenzeile: Deklaration und Create in EINEM Schritt, gekennzeichnet
  // (Changes: True), Name = der Elementtyp aus der Meldung, Hinweis der
  // Zeile.
  O := PlanFirst(StdSrc);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(2, Length(O.Edits), 'Deklaration und Create');
  Assert.IsTrue(O.ChangesBehavior, 'gekennzeichnet');
  Assert.AreEqual('TFoo', O.Name);
  Assert.IsTrue(Pos('Clear', O.Hint) > 0, O.Hint);
  Assert.IsTrue(Pos('TObjectList<TFoo>',
    TRdxFixTable.CaptionFor(fkTObjectListWithoutOwnership, O)) > 0,
    'der Menuetext nennt den Elementtyp');
end;

procedure TTestRdxObjectListDetector.Detector_TwoAdds_Fixed;
var
  S : string;
begin
  // Ein Fund je Add; die eine Hilfe behebt beide.
  S := Src(STD_DECLS, ['  L := TList<TFoo>.Create;', '  L.Add(TFoo.Create);',
    '  L.Add(TBar.Create);', '  L.Free;']);
  Assert.AreEqual<Integer>(2, Length(Detect(S)), 'zwei Funde');
  Assert.AreEqual(Owned(S), FixAll(S));
end;

procedure TTestRdxObjectListDetector.Detector_InlineVar_RoundTrip;
var
  S : string;
begin
  // Der Parser legt den Initializer einer inline-Variablen als Zuweisung
  // ab (uParser2.ParseInlineVarStmt) - der Detektor sieht ihn.
  S := Src([], ['  var L := TList<TFoo>.Create;', '  L.Add(TFoo.Create);',
    '  L.Free;']);
  Assert.AreEqual<Integer>(1, Length(Detect(S)), 'ein Fund');
  Assert.AreEqual(Owned(S), FixAll(S));
end;

procedure TTestRdxObjectListDetector.Detector_CatalogExample_Fixed;
var
  Meta : TRuleMeta;
  S    : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkTObjectListWithoutOwnership);
  Assert.IsTrue(Pos('TList<TFoo>.Create', Meta.BadExample) > 0,
    Meta.BadExample);
  // Das Beispiel als Rumpf von Foo, L lokal.
  S := Join(HEAD) + CRLF + Join(STD_DECLS) + CRLF + 'begin' + CRLF
    + CatalogText(Meta.BadExample) + CRLF + Join(['end;', 'end.']);
  Assert.AreEqual<Integer>(1, Length(Detect(S)),
    'der Detektor meldet das Beispiel');
  Assert.AreEqual(Owned(S), FixAll(S));
end;

procedure TTestRdxObjectListDetector.Detector_ItemFreed_NoHelp;
var
  O : TRdxFixOutcome;
begin
  // Die Elemente werden schon von Hand freigegeben - der Detektor meldet
  // trotzdem, die Hilfe lehnt ab (sonst doppelte Freigabe).
  O := PlanFirst(Src(['var', '  L: TList<TFoo>;', '  i: Integer;'],
    ['  L := TList<TFoo>.Create;', '  L.Add(TFoo.Create);',
     '  for i := 0 to L.Count - 1 do', '    L[i].Free;', '  L.Free;']));
  Assert.IsFalse(O.Enabled);
  Assert.AreEqual(_(R_OL_ITEM, [14]), O.Reason);
end;

procedure TTestRdxObjectListDetector.Detector_Field_NoHelp;
var
  O : TRdxFixOutcome;
begin
  // Ein Feld: der Detektor meldet (Name klein, ohne Self), die Hilfe nicht -
  // die Liste kann anderswo gefuellt oder geleert werden.
  O := PlanFirst(Join(['unit t;', 'interface', 'uses',
    '  System.Generics.Collections;', 'type', '  TFoo = class', '  end;',
    '  THolder = class', '  private', '    FList: TList<TFoo>;', '  public',
    '    constructor Create;', '  end;', 'implementation',
    'constructor THolder.Create;', 'begin', '  FList := TList<TFoo>.Create;',
    '  FList.Add(TFoo.Create);', 'end;', 'end.']));
  Assert.IsFalse(O.Enabled);
  Assert.AreEqual(_(R_OL_NOT_LOCAL, ['FList']), O.Reason);
end;

procedure TTestRdxObjectListDetector.Detector_ReusedVariable_NoHelp;
var
  O : TRdxFixOutcome;
begin
  // Posten 306 des Detektors: das Add gehoert zur besitzenden Liste, eine
  // spaetere TList-Zuweisung laesst den Detektor trotzdem melden. Die
  // Deklaration ist keine TList<TFoo> - keine Hilfe.
  O := PlanFirst(Src(['var', '  L: TObjectList<TFoo>;'],
    ['  L := TObjectList<TFoo>.Create;', '  L.Add(TFoo.Create);', '  L.Free;',
     '  L := TList<TFoo>.Create;', '  L.Free;']));
  Assert.IsFalse(O.Enabled);
  Assert.AreEqual(_(R_OL_DECL_TYPE, ['L', 8, 'TFoo']), O.Reason);
end;

procedure TTestRdxObjectListDetector.NestedRoutineUse_NoHelp;
begin
  // Eine verschachtelte Routine nutzt die Liste der aeusseren.
  AssertRefused(Join(['unit t;', 'interface', 'uses',
    '  System.Generics.Collections;', 'implementation', 'procedure Outer;',
    'var', '  L: TList<TFoo>;', '  procedure Inner;', '  begin',
    '    L.Clear;', '  end;', 'begin', '  L := TList<TFoo>.Create;',
    '  L.Add(TFoo.Create);', '  Inner;', '  L.Free;', 'end;', 'end.']),
    _(R_OL_NESTED, ['L', 11]));
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxObjectListFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxObjectListDetector);
  {$ENDIF}

end.

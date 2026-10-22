unit uTestRdxUnusedParameterFix;

// Editorhilfe SCA054 UnusedParameter (uRdxUnusedParameterFix): 'Mode' ->
// '_Mode' in Implementierung, Deklarationen und '<param name>'-Doku. Die
// Faelle auf Text laufen ohne Parser und ohne Detektor (FPC-tauglich: der
// Planer bindet nur uRdxCodeMap, uRdxBlocks, uRdxBufferMath, uRdxText);
// die Rundlaeufe mit dem ECHTEN Detektor stehen in der zweiten Fixture
// (nur Delphi) und laufen ueber den Einstieg der Tabelle
// (TRdxFixTable.FixFor, Adapter PlanUnusedParameter - wie der Anbieter).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxUnusedParameterFix = class
  public
    [Test] procedure FreeRoutine_ImplOnly;
    [Test] procedure Method_DeclImplAndDoc;
    [Test] procedure InterfaceDecl_And_Forward;
    [Test] procedure ClassProcedure_Group;
    [Test] procedure GenericClass_Method;
    [Test] procedure CommentAndString_AreNoUse;
    [Test] procedure Edits_SpanAndName;
    [Test] procedure Refuse_Used;
    [Test] procedure Refuse_UsedInNestedOrInactiveCode;
    [Test] procedure Refuse_Asm;
    [Test] procedure Refuse_CommentOrAttributeInList;
    [Test] procedure Refuse_NewNameTaken;
    [Test] procedure Refuse_Overload_And_Twin;
    [Test] procedure Refuse_RecordMethod_NoDecl;
    [Test] procedure Refuse_Attribute;
    [Test] procedure Refuse_Include;
    [Test] procedure Refuse_DeclDiffers;
    [Test] procedure Refuse_TwoHeadsOnLine;
    [Test] procedure Refuse_Moved_NoName_Underscore;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxUnusedParameterFixDetector = class
  public
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_CommentOnly_Help;
    [Test] procedure Detector_Overload_NoHelp;
    // ---- Tabellenzeile ----
    [Test] procedure Table_HintAndName;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxText,
  uRdxUnusedParameterFix,
  uTestRdxTextKit   // Join, Apply, NewMap
{$IFNDEF FPC}
  , System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uUnusedParameter,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uTestRdxDetectorKit    // TSeen, DetectSource, PlanFixIn, FixAllWith
{$ENDIF}
  ;

// ---- Helfer ----

// Die Meldung wie der Detektor sie schreibt.
function UMsg(const AName: string): string;
begin
  Result := Format('Unused parameter: %s (never read in method body)',
    [AName]);
end;

// Der Plan fuer Zeile ALine mit der Meldung AMessage.
function PlanOf(const ASource: string; ALine: Integer; const AMessage: string;
  out APlan: TRdxParamPlan; out AReason: string): Boolean;
var
  Map : TRdxCodeMap;
begin
  Map := NewMap(ASource);
  try
    Result := TRdxUnusedParameterFix.MarkUnused(Map, ALine, AMessage, APlan,
      AReason);
  finally
    Map.Free;
  end;
end;

// Der neue Text fuer den Parameter AName auf ALine; '' bei Ablehnung
// (AReason).
function Fix(const ASource: string; ALine: Integer; const AName: string;
  out AReason: string): string;
var
  P : TRdxParamPlan;
begin
  Result := '';
  if PlanOf(ASource, ALine, UMsg(AName), P, AReason) then
    Result := Apply(ASource, P.Edits);
end;

// Abgelehnt mit genau dem Grund AWant.
procedure AssertRefused(const ASource: string; ALine: Integer;
  const AName, AWant: string);
var
  R : string;
begin
  Assert.AreEqual('', Fix(ASource, ALine, AName, R), AWant);
  Assert.AreEqual(AWant, R);
end;

// Eine Unit mit den Zeilen ABody hinter 'implementation' (Zeile 4 ff.).
function ImplUnit(const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation']) + #13#10
    + Join(ABody) + #13#10 + 'end.';
end;

// ---- Text ----

procedure TTestRdxUnusedParameterFix.FreeRoutine_ImplOnly;
var
  R : string;
begin
  Assert.AreEqual(
    ImplUnit(['procedure Work(A: Integer; _Mode: Integer);', 'begin',
      '  A := A + 1;', 'end;']),
    Fix(ImplUnit(['procedure Work(A: Integer; Mode: Integer);', 'begin',
      '  A := A + 1;', 'end;']), 4, 'Mode', R), R);
end;

procedure TTestRdxUnusedParameterFix.Method_DeclImplAndDoc;
var
  R : string;
begin
  // Deklaration im Klassenrumpf, Implementierung und die '<param name>'
  // der '///'-Doku ueber beiden - jede in ihrer Schreibweise.
  Assert.AreEqual(Join(['unit t;', 'interface', 'type', '  TFoo = class',
    '  public', '    /// <summary>Runs.</summary>',
    '    /// <param name="_Mode">ignored</param>',
    '    procedure Run(_Mode: Integer);', '  end;', 'implementation',
    '/// <param name="_mode">ignored</param>',
    'procedure TFoo.Run(_Mode: Integer);', 'begin', 'end;', 'end.']),
    Fix(Join(['unit t;', 'interface', 'type', '  TFoo = class', '  public',
      '    /// <summary>Runs.</summary>',
      '    /// <param name="Mode">ignored</param>',
      '    procedure Run(Mode: Integer);', '  end;', 'implementation',
      '/// <param name="mode">ignored</param>',
      'procedure TFoo.Run(Mode: Integer);', 'begin', 'end;', 'end.']),
      12, 'Mode', R), R);
end;

procedure TTestRdxUnusedParameterFix.InterfaceDecl_And_Forward;
var
  R : string;
begin
  // Deklaration im interface-Teil.
  Assert.AreEqual(Join(['unit t;', 'interface',
    'procedure Work(_Mode: Integer);', 'implementation',
    'procedure Work(_Mode: Integer);', 'begin', 'end;', 'end.']),
    Fix(Join(['unit t;', 'interface', 'procedure Work(Mode: Integer);',
      'implementation', 'procedure Work(Mode: Integer);', 'begin', 'end;',
      'end.']), 5, 'Mode', R), R);
  // forward im implementation-Teil, anders geschrieben; der Aufruf bleibt.
  Assert.AreEqual(
    ImplUnit(['procedure Work(_mode: Integer); forward;', 'procedure Caller;',
      'begin', '  Work(1);', 'end;', 'procedure Work(_Mode: Integer);',
      'begin', 'end;']),
    Fix(ImplUnit(['procedure Work(mode: Integer); forward;',
      'procedure Caller;', 'begin', '  Work(1);', 'end;',
      'procedure Work(Mode: Integer);', 'begin', 'end;']), 9, 'Mode', R), R);
end;

procedure TTestRdxUnusedParameterFix.ClassProcedure_Group;
var
  R : string;
begin
  Assert.AreEqual(Join(['unit t;', 'interface', 'type', '  TFoo = class',
    '    class procedure Run(A, _Mode: Integer; const S: string);', '  end;',
    'implementation',
    'class procedure TFoo.Run(A, _Mode: Integer; const S: string);', 'begin',
    '  Writeln(A, S);', 'end;', 'end.']),
    Fix(Join(['unit t;', 'interface', 'type', '  TFoo = class',
      '    class procedure Run(A, Mode: Integer; const S: string);', '  end;',
      'implementation',
      'class procedure TFoo.Run(A, Mode: Integer; const S: string);',
      'begin', '  Writeln(A, S);', 'end;', 'end.']), 8, 'Mode', R), R);
end;

procedure TTestRdxUnusedParameterFix.GenericClass_Method;
var
  R : string;
begin
  Assert.AreEqual(Join(['unit t;', 'interface', 'type', '  TBox<T> = class',
    '    procedure Put(const Item: T; _Mode: Integer);', '  end;',
    'implementation', 'procedure TBox<T>.Put(const Item: T; _Mode: Integer);',
    'begin', '  Writeln(Item);', 'end;', 'end.']),
    Fix(Join(['unit t;', 'interface', 'type', '  TBox<T> = class',
      '    procedure Put(const Item: T; Mode: Integer);', '  end;',
      'implementation',
      'procedure TBox<T>.Put(const Item: T; Mode: Integer);', 'begin',
      '  Writeln(Item);', 'end;', 'end.']), 8, 'Mode', R), R);
end;

procedure TTestRdxUnusedParameterFix.CommentAndString_AreNoUse;
var
  R : string;
begin
  // Kommentar und String nennen den Namen - keine Verwendung, beide bleiben.
  Assert.AreEqual(
    ImplUnit(['procedure Work(_Mode: Integer);', 'begin',
      '  // Mode is ignored on purpose', '  Writeln(''Mode'');', 'end;']),
    Fix(ImplUnit(['procedure Work(Mode: Integer);', 'begin',
      '  // Mode is ignored on purpose', '  Writeln(''Mode'');', 'end;']),
      4, 'Mode', R), R);
end;

procedure TTestRdxUnusedParameterFix.Edits_SpanAndName;
var
  P : TRdxParamPlan;
  R : string;
  L : string;
begin
  L := 'procedure Work(A: Integer; Mode: Integer);';
  Assert.IsTrue(PlanOf(ImplUnit([L, 'begin', '  A := A + 1;', 'end;']), 4,
    UMsg('Mode'), P, R), R);
  Assert.AreEqual('Mode', P.Name);
  Assert.AreEqual<Integer>(1, Length(P.Edits));
  // Der Bereich ist genau der Name: Zeile 4, ab seiner Spalte, nicht leer.
  Assert.AreEqual<Integer>(4, P.Edits[0].Span.StartLine);
  Assert.AreEqual<Integer>(Pos('Mode', L), P.Edits[0].Span.StartCol);
  Assert.AreEqual<Integer>(4, P.Edits[0].Span.EndLine);
  Assert.AreEqual<Integer>(Pos('Mode', L) + 4, P.Edits[0].Span.EndCol);
  Assert.AreEqual('Mode', P.Edits[0].Expected);
  Assert.AreEqual('_Mode', P.Edits[0].NewText);
  // Abgelehnt: der Name aus der Meldung fuer den Menuetext, keine Ersetzung.
  Assert.IsFalse(PlanOf(ImplUnit([L, 'begin', '  A := Mode;', 'end;']), 4,
    UMsg('Mode'), P, R));
  Assert.AreEqual('Mode', P.Name);
  Assert.AreEqual<Integer>(0, Length(P.Edits));
end;

procedure TTestRdxUnusedParameterFix.Refuse_Used;
begin
  AssertRefused(ImplUnit(['procedure Work(Mode: Integer);', 'begin',
    '  if Mode > 0 then Exit;', 'end;']), 4, 'Mode',
    MsgStaleSuffix(_(R_UP_USED, ['Mode', 6])));
end;

procedure TTestRdxUnusedParameterFix.Refuse_UsedInNestedOrInactiveCode;
begin
  // In einer lokalen Routine.
  AssertRefused(ImplUnit(['procedure Work(Mode: Integer);',
    '  procedure Inner;', '  begin', '    Writeln(Mode);', '  end;', 'begin',
    '  Inner;', 'end;']), 4, 'Mode',
    MsgStaleSuffix(_(R_UP_USED, ['Mode', 7])));
  // In einem Zweig, den der Scan nicht sieht.
  AssertRefused(ImplUnit(['procedure Work(Mode: Integer);', 'begin',
    '  {$IFDEF DEBUG}', '  Writeln(Mode);', '  {$ENDIF}', 'end;']), 4, 'Mode',
    MsgStaleSuffix(_(R_UP_USED, ['Mode', 7])));
end;

procedure TTestRdxUnusedParameterFix.Refuse_Asm;
begin
  // asm liest Parameter ueber Register, ohne ihren Namen.
  AssertRefused(ImplUnit(['procedure Work(Mode: Integer);', 'asm',
    '  MOV EAX, 1', 'end;']), 4, 'Mode', _(R_UP_ASM));
  AssertRefused(ImplUnit(['procedure Work(Mode: Integer);', 'begin',
    '  asm', '    NOP', '  end;', 'end;']), 4, 'Mode', _(R_UP_ASM));
end;

procedure TTestRdxUnusedParameterFix.Refuse_CommentOrAttributeInList;
begin
  AssertRefused(ImplUnit(['procedure Work({%H-}Mode: Integer);', 'begin',
    'end;']), 4, 'Mode', _(R_UP_NOISE));
  AssertRefused(ImplUnit(['procedure Work(Mode: Integer { unused });',
    'begin', 'end;']), 4, 'Mode', _(R_UP_NOISE));
  AssertRefused(ImplUnit(['procedure Work(const [Ref] Mode: Integer);',
    'begin', 'end;']), 4, 'Mode', _(R_UP_NOISE));
end;

procedure TTestRdxUnusedParameterFix.Refuse_NewNameTaken;
begin
  // '_Mode' steht schon in der Datei - doppelt bzw. verdeckt danach.
  AssertRefused(ImplUnit(['var', '  _Mode: Integer;',
    'procedure Work(Mode: Integer);', 'begin', 'end;']), 6, 'Mode',
    _(R_UP_TAKEN, ['_Mode', 5]));
end;

procedure TTestRdxUnusedParameterFix.Refuse_Overload_And_Twin;
begin
  AssertRefused(ImplUnit(['procedure Work(Mode: Integer); overload;',
    'begin', 'end;', 'procedure Work(const S: string); overload;', 'begin',
    '  Writeln(S);', 'end;']), 4, 'Mode', _(R_UP_OVERLOAD, ['Work']));
  // $IFDEF-Zwillinge ohne overload: welche Deklaration gilt, bleibt offen.
  AssertRefused(ImplUnit(['{$IFDEF A}', 'procedure Work(Mode: Integer);',
    'begin', 'end;', '{$ELSE}', 'procedure Work(Mode: Integer);', 'begin',
    'end;', '{$ENDIF}']), 5, 'Mode', _(R_UP_TWIN, ['Work', 9]));
end;

procedure TTestRdxUnusedParameterFix.Refuse_RecordMethod_NoDecl;
begin
  // Der Finder kennt nur Klassenkoepfe - ohne Deklaration keine Hilfe
  // (sonst E2037).
  AssertRefused(Join(['unit t;', 'interface', 'type', '  TRec = record',
    '    procedure Run(Mode: Integer);', '  end;', 'implementation',
    'procedure TRec.Run(Mode: Integer);', 'begin', 'end;', 'end.']), 8,
    'Mode', _(R_UP_NO_DECL, ['TRec.Run']));
end;

procedure TTestRdxUnusedParameterFix.Refuse_Attribute;
begin
  // Am Member (REST-Controller binden Parameter per Namen) ...
  AssertRefused(Join(['unit t;', 'interface', 'type', '  TApi = class',
    '  public', '    [MVCPath(''/run'')]', '    procedure Run(Mode: Integer);',
    '  end;', 'implementation', 'procedure TApi.Run(Mode: Integer);', 'begin',
    'end;', 'end.']), 10, 'Mode', _(R_UP_ATTRIBUTE));
  // ... und an der Klasse.
  AssertRefused(Join(['unit t;', 'interface', 'type', '  [MVCPath(''/api'')]',
    '  TApi = class', '  public', '    procedure Run(Mode: Integer);', '  end;',
    'implementation', 'procedure TApi.Run(Mode: Integer);', 'begin', 'end;',
    'end.']), 10, 'Mode', _(R_UP_ATTRIBUTE));
end;

procedure TTestRdxUnusedParameterFix.Refuse_Include;
begin
  // Freie Routine: ein Include kann die Deklaration tragen.
  AssertRefused(Join(['unit t;', 'interface', '{$I defs.inc}',
    'implementation', 'procedure Work(Mode: Integer);', 'begin', 'end;',
    'end.']), 5, 'Mode', _(R_UP_INCLUDE, [3]));
  // Methode: ein Include in der Routine kann den Parameter lesen.
  AssertRefused(Join(['unit t;', 'interface', 'type', '  TFoo = class',
    '    procedure Run(Mode: Integer);', '  end;', 'implementation',
    'procedure TFoo.Run(Mode: Integer);', 'begin', '  {$I body.inc}', 'end;',
    'end.']), 8, 'Mode', _(R_UP_INCLUDE, [10]));
end;

procedure TTestRdxUnusedParameterFix.Refuse_DeclDiffers;
begin
  AssertRefused(Join(['unit t;', 'interface', 'type', '  TFoo = class',
    '    procedure Run(AMode: Integer);', '  end;', 'implementation',
    'procedure TFoo.Run(Mode: Integer);', 'begin', 'end;', 'end.']), 8,
    'Mode', _(R_UP_DECL_DIFFERS, [5]));
end;

procedure TTestRdxUnusedParameterFix.Refuse_TwoHeadsOnLine;
begin
  AssertRefused(ImplUnit(['procedure A(Mode: Integer); begin end; '
    + 'procedure B(Mode: Integer); begin end;']), 4, 'Mode',
    _(R_UP_MANY_HEADS, [2, 'Mode']));
end;

procedure TTestRdxUnusedParameterFix.Refuse_Moved_NoName_Underscore;
var
  S, R : string;
  P    : TRdxParamPlan;
begin
  S := ImplUnit(['procedure Work(Mode: Integer);', 'begin', 'end;']);
  // Zeile verschoben.
  AssertRefused(S, 5, 'Mode', MsgMovedSuffix(_(R_UP_NO_HEAD, ['Mode'])));
  // Ein anderer Name als in der Liste.
  AssertRefused(S, 4, 'Other', MsgMovedSuffix(_(R_UP_NO_HEAD, ['Other'])));
  // Die Meldung nennt keinen Parameter.
  Assert.IsFalse(PlanOf(S, 4, 'Unused something', P, R));
  Assert.AreEqual(_(R_UP_NO_NAME), R);
  // Schon mit '_' - der Detektor meldet so etwas nicht.
  Assert.IsFalse(PlanOf(S, 4, UMsg('_Mode'), P, R));
  Assert.AreEqual(MsgStaleSuffix(_(R_UP_UNDERSCORE, ['_Mode'])), R);
end;

{$IFNDEF FPC}

// ---- echter Detektor ----

procedure RunUnusedParam(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TUnusedParameterDetector.AnalyzeUnit(Root, Path, Results);
end;

// Die Form TDetectFunc (uTestRdxDetectorKit) fuer FixAllWith.
function DetectKind(const ASource: string;
  AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('sca054', ASource, AKind, RunUnusedParam);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectKind(ASource, fkUnusedParameter);
end;

// Fund fuer Fund ueber den Einstieg der Tabelle (PlanFixIn ->
// TRdxFixTable.FixFor -> PlanUnusedParameter), bis der Detektor schweigt.
function FixAll(const ASource: string): string;
begin
  Result := FixAllWith(ASource, fkUnusedParameter, DetectKind);
end;

procedure TTestRdxUnusedParameterFixDetector.Detector_RoundTrip;
var
  Bad, Good : string;
begin
  Bad := Join(['unit t;', 'interface', 'type', '  TFoo = class', '  public',
    '    procedure Run(A: Integer; Mode: Integer);', '  end;',
    'procedure Work(Flag: Boolean);', 'implementation',
    'procedure TFoo.Run(A: Integer; Mode: Integer);', 'begin',
    '  A := A + 1;', 'end;', 'procedure Work(Flag: Boolean);', 'begin',
    'end;', 'end.']);
  Good := Join(['unit t;', 'interface', 'type', '  TFoo = class', '  public',
    '    procedure Run(A: Integer; _Mode: Integer);', '  end;',
    'procedure Work(_Flag: Boolean);', 'implementation',
    'procedure TFoo.Run(A: Integer; _Mode: Integer);', 'begin',
    '  A := A + 1;', 'end;', 'procedure Work(_Flag: Boolean);', 'begin',
    'end;', 'end.']);
  Assert.AreEqual<Integer>(2, Length(Detect(Bad)));
  Assert.AreEqual(Good, FixAll(Bad));
  Assert.AreEqual<Integer>(0, Length(Detect(Good)));
end;

procedure TTestRdxUnusedParameterFixDetector.Detector_CommentOnly_Help;
var
  Bad : string;
begin
  // Kommentar und String nennen den Namen: der Detektor meldet, die Hilfe
  // greift, Kommentar und String bleiben.
  Bad := ImplUnit(['procedure Work(Mode: Integer);', 'begin',
    '  // Mode is ignored on purpose', '  Writeln(''Mode'');', 'end;']);
  Assert.AreEqual<Integer>(1, Length(Detect(Bad)));
  Assert.AreEqual(
    ImplUnit(['procedure Work(_Mode: Integer);', 'begin',
      '  // Mode is ignored on purpose', '  Writeln(''Mode'');', 'end;']),
    FixAll(Bad));
end;

procedure TTestRdxUnusedParameterFixDetector.Detector_Overload_NoHelp;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // Der Detektor meldet Mode der ersten Ueberladung; die Hilfe lehnt ab.
  Src := ImplUnit(['procedure Work(Mode: Integer); overload;', 'begin',
    'end;', 'procedure Work(const S: string); overload;', 'begin',
    '  if S = '''' then Exit;', 'end;']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen));
  Assert.AreEqual<Integer>(4, Seen[0].Line);
  O := PlanFixIn(Src, 't.pas', fkUnusedParameter, Seen[0]);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_UP_OVERLOAD, ['Work']), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

procedure TTestRdxUnusedParameterFixDetector.Table_HintAndName;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // Die Zeile der Tabelle: Name = der Parameter (Menuetext), der feste
  // Hinweis der Zeile, nicht gekennzeichnet (bedeutungsgleich).
  Src := ImplUnit(['procedure Work(Mode: Integer);', 'begin', 'end;']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen));
  O := PlanFixIn(Src, 't.pas', fkUnusedParameter, Seen[0]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual('Mode', O.Name);
  Assert.IsTrue(O.Hint <> '', 'Hinweis der Zeile');
  Assert.IsFalse(O.ChangesBehavior, 'nicht gekennzeichnet');
  Assert.AreEqual(
    ImplUnit(['procedure Work(_Mode: Integer);', 'begin', 'end;']),
    Apply(Src, O.Edits));
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxUnusedParameterFix);
{$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxUnusedParameterFixDetector);
{$ENDIF}

end.

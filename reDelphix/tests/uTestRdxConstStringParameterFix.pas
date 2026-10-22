unit uTestRdxConstStringParameterFix;

// Editorhilfe SCA170 ConstStringParameter (uRdxConstStringParameterFix):
// 'const' vor den string-Parameter in Implementierung und Deklarationen.
// Die Faelle auf Text laufen ohne Parser und ohne Detektor (FPC-tauglich:
// der Planer bindet nur Textlogik); die Rundlaeufe mit dem ECHTEN Detektor
// stehen in der zweiten Fixture (nur Delphi) und laufen ueber den Einstieg
// der Tabelle (TRdxFixTable.FixFor, Adapter PlanConstStringParameter - wie
// der Anbieter). Die Sperren des Kopfs
// (overload, asm, Kommentar in der Liste ...) prueft
// uTestRdxUnusedParameterFix - beide Hilfen teilen ReadSite.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxConstStringParameterFix = class
  public
    [Test] procedure LocalFunction_Const;
    [Test] procedure Forward_And_Impl;
    [Test] procedure PrivateMethod_DeclAndImpl;
    [Test] procedure ImplementationClass_PublicMethod;
    [Test] procedure Group_ConstBeforeGroup;
    [Test] procedure ReadOnlyUses_Help;
    [Test] procedure Refuse_InterfaceDecl;
    [Test] procedure Refuse_PublicMethod;
    [Test] procedure Refuse_Virtual;
    [Test] procedure Refuse_InterfaceOnClass;
    [Test] procedure Refuse_Assigned;
    [Test] procedure Refuse_PassedToUnknownRoutine;
    [Test] procedure Refuse_Address_And_LoopVariable;
    [Test] procedure Refuse_RoutineAsValue;
    [Test] procedure Refuse_OtherNameOfGroupWritten;
    [Test] procedure Refuse_Modifier_And_Type;
    [Test] procedure Refuse_DeclGroupsDifferently;
    [Test] procedure Refuse_Include;
    [Test] procedure Refuse_WrittenInLocalRoutine;
    [Test] procedure Refuse_NoName_Moved;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxConstStringParameterFixDetector = class
  public
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_Interface_NoHelp;
    [Test] procedure Detector_Written_NoHelp;
    // ---- Tabellenzeile ----
    [Test] procedure Table_HintAndName;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxText,
  uRdxUnusedParameterFix,       // TRdxParamPlan, R_UP_* (geteilte Gruende)
  uRdxConstStringParameterFix,
  uTestRdxTextKit   // Join, Apply
{$IFNDEF FPC}
  , System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uConstStringParameter,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uTestRdxDetectorKit    // TSeen, DetectSource, PlanFixIn, FixAllWith
{$ENDIF}
  ;

// ---- Helfer ----

// Die Meldung wie der Detektor sie schreibt.
function CMsg(const AName, AType: string): string;
begin
  Result := Format('Parameter "%s: %s" should be declared as `const` - '
    + 'avoids the refcount bump on each call and clarifies that the method '
    + 'does not mutate the argument.', [AName, AType]);
end;

// Der Plan fuer Zeile ALine mit der Meldung AMessage.
function PlanOf(const ASource: string; ALine: Integer; const AMessage: string;
  out APlan: TRdxParamPlan; out AReason: string): Boolean;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    Result := TRdxConstStringParameterFix.MakeConst(Map, ALine, AMessage,
      APlan, AReason);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Der neue Text fuer den string-Parameter AName auf ALine; '' bei
// Ablehnung (AReason).
function Fix(const ASource: string; ALine: Integer; const AName: string;
  out AReason: string): string;
var
  P : TRdxParamPlan;
begin
  Result := '';
  if PlanOf(ASource, ALine, CMsg(AName, 'string'), P, AReason) then
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

// Eine Klasse TLog im interface-Teil mit der Deklaration ADecl unter der
// Sichtbarkeit AVis (Zeile 6) und ihre Implementierung AImpl (Zeile 9)
// mit 'Writeln(Msg);' im Rumpf. AHeritage etwa '(TInterfacedObject, ILog)'.
function LogUnit(const AHeritage, AVis, ADecl, AImpl: string): string;
begin
  Result := Join(['unit t;', 'interface', 'type',
    '  TLog = class' + AHeritage, '  ' + AVis, '    ' + ADecl, '  end;',
    'implementation', AImpl, 'begin', '  Writeln(Msg);', 'end;', 'end.']);
end;

// ---- Text ----

procedure TTestRdxConstStringParameterFix.LocalFunction_Const;
var
  R : string;
begin
  Assert.AreEqual(
    ImplUnit(['function Hash(const s: string): Integer;', 'begin',
      '  Result := Length(s);', 'end;']),
    Fix(ImplUnit(['function Hash(s: string): Integer;', 'begin',
      '  Result := Length(s);', 'end;']), 4, 's', R), R);
end;

procedure TTestRdxConstStringParameterFix.Forward_And_Impl;
var
  R : string;
begin
  // Der Aufruf bleibt, forward und Implementierung bekommen das const.
  Assert.AreEqual(
    ImplUnit(['procedure Log(const Msg: string); forward;', 'procedure Run;',
      'begin', '  Log(''x'');', 'end;', 'procedure Log(const Msg: string);',
      'begin', '  Writeln(Msg);', 'end;']),
    Fix(ImplUnit(['procedure Log(Msg: string); forward;', 'procedure Run;',
      'begin', '  Log(''x'');', 'end;', 'procedure Log(Msg: string);',
      'begin', '  Writeln(Msg);', 'end;']), 9, 'Msg', R), R);
end;

procedure TTestRdxConstStringParameterFix.PrivateMethod_DeclAndImpl;
var
  R : string;
begin
  Assert.AreEqual(
    LogUnit('', 'private', 'procedure Note(const Msg: string);',
      'procedure TLog.Note(const Msg: string);'),
    Fix(LogUnit('', 'private', 'procedure Note(Msg: string);',
      'procedure TLog.Note(Msg: string);'), 9, 'Msg', R), R);
  Assert.AreEqual(
    LogUnit('', 'strict private', 'procedure Note(const Msg: string);',
      'procedure TLog.Note(const Msg: string);'),
    Fix(LogUnit('', 'strict private', 'procedure Note(Msg: string);',
      'procedure TLog.Note(Msg: string);'), 9, 'Msg', R), R);
end;

procedure TTestRdxConstStringParameterFix.ImplementationClass_PublicMethod;
var
  R : string;
begin
  // Eine Klasse des implementation-Teils sieht keine andere Unit.
  Assert.AreEqual(
    ImplUnit(['type', '  THelper = class', '  public',
      '    procedure Show(A: Integer; const Text: string);', '  end;',
      'procedure THelper.Show(A: Integer; const Text: string);', 'begin',
      '  Writeln(A, Text);', 'end;']),
    Fix(ImplUnit(['type', '  THelper = class', '  public',
      '    procedure Show(A: Integer; Text: string);', '  end;',
      'procedure THelper.Show(A: Integer; Text: string);', 'begin',
      '  Writeln(A, Text);', 'end;']), 9, 'Text', R), R);
end;

procedure TTestRdxConstStringParameterFix.Group_ConstBeforeGroup;
var
  R : string;
  P : TRdxParamPlan;
begin
  // Das const steht vor der Gruppe und gilt fuer beide Namen.
  Assert.AreEqual(
    ImplUnit(['procedure Log(const A, B: string);', 'begin',
      '  Writeln(A + B);', 'end;']),
    Fix(ImplUnit(['procedure Log(A, B: string);', 'begin',
      '  Writeln(A + B);', 'end;']), 4, 'B', R), R);
  // Menuetext: der Name aus der Meldung; die Ersetzung trifft den ersten.
  Assert.IsTrue(PlanOf(ImplUnit(['procedure Log(A, B: string);', 'begin',
    '  Writeln(A + B);', 'end;']), 4, CMsg('B', 'string'), P, R), R);
  Assert.AreEqual('B', P.Name);
  Assert.AreEqual<Integer>(1, Length(P.Edits));
  Assert.AreEqual('A', P.Edits[0].Expected);
  Assert.AreEqual('const A', P.Edits[0].NewText);
end;

procedure TTestRdxConstStringParameterFix.ReadOnlyUses_Help;
var
  R : string;
begin
  // Index lesen, Array-Konstruktor, nur lesende RTL-Routinen, Exit und der
  // rekursive Aufruf beschreiben S nicht.
  Assert.AreEqual(
    ImplUnit(['function Hash(const S: string): Integer;', 'var', '  C: Char;',
      'begin', '  C := S[1];',
      '  Writeln(Format(''%s'', [S]), Copy(S, 1, 2));',
      '  if Pos(''x'', S) > 0 then', '    Exit(Hash(Copy(S, 2, MaxInt)));',
      '  Result := Length(S) + Ord(C);', 'end;']),
    Fix(ImplUnit(['function Hash(S: string): Integer;', 'var', '  C: Char;',
      'begin', '  C := S[1];',
      '  Writeln(Format(''%s'', [S]), Copy(S, 1, 2));',
      '  if Pos(''x'', S) > 0 then', '    Exit(Hash(Copy(S, 2, MaxInt)));',
      '  Result := Length(S) + Ord(C);', 'end;']), 4, 'S', R), R);
end;

procedure TTestRdxConstStringParameterFix.Refuse_InterfaceDecl;
begin
  AssertRefused(Join(['unit t;', 'interface',
    'function Hash(s: string): Integer;', 'implementation',
    'function Hash(s: string): Integer;', 'begin', '  Result := Length(s);',
    'end;', 'end.']), 5, 's', _(R_CS_INTERFACE, [3]));
end;

procedure TTestRdxConstStringParameterFix.Refuse_PublicMethod;
begin
  AssertRefused(LogUnit('', 'public', 'procedure Note(Msg: string);',
    'procedure TLog.Note(Msg: string);'), 9, 'Msg', _(R_CS_VISIBLE));
  AssertRefused(LogUnit('', 'protected', 'procedure Note(Msg: string);',
    'procedure TLog.Note(Msg: string);'), 9, 'Msg', _(R_CS_VISIBLE));
end;

procedure TTestRdxConstStringParameterFix.Refuse_Virtual;
begin
  AssertRefused(LogUnit('', 'private',
    'procedure Note(Msg: string); virtual;',
    'procedure TLog.Note(Msg: string);'), 9, 'Msg',
    _(R_CS_DISPATCH, ['virtual']));
end;

procedure TTestRdxConstStringParameterFix.Refuse_InterfaceOnClass;
begin
  // Die private Methode kann ein Member von ILog sein (E2291 danach).
  AssertRefused(LogUnit('(TInterfacedObject, ILog)', 'private',
    'procedure Note(Msg: string);', 'procedure TLog.Note(Msg: string);'), 9,
    'Msg', _(R_CS_IFACE, ['ILog']));
  AssertRefused(LogUnit('(ILog)', 'private',
    'procedure Note(Msg: string);', 'procedure TLog.Note(Msg: string);'), 9,
    'Msg', _(R_CS_IFACE, ['ILog']));
end;

procedure TTestRdxConstStringParameterFix.Refuse_Assigned;
begin
  AssertRefused(ImplUnit(['function Clean(S: string): string;', 'begin',
    '  S := Trim(S);', '  Result := S;', 'end;']), 4, 'S',
    _(R_CS_WRITTEN, ['S', 6]));
  AssertRefused(ImplUnit(['procedure Upper(S: string);', 'begin',
    '  S[1] := ''X'';', '  Writeln(S);', 'end;']), 4, 'S',
    _(R_CS_WRITTEN, ['S', 6]));
end;

procedure TTestRdxConstStringParameterFix.Refuse_PassedToUnknownRoutine;
begin
  // Delete hat einen var-Parameter; Store ist unbekannt - beides sperrt.
  AssertRefused(ImplUnit(['procedure Cut(S: string);', 'begin',
    '  Delete(S, 1, 1);', '  Writeln(S);', 'end;']), 4, 'S',
    _(R_CS_ARGUMENT, ['S', 'Delete', 6]));
  AssertRefused(ImplUnit(['procedure Keep(S: string);', 'begin',
    '  Store(1, S);', 'end;']), 4, 'S', _(R_CS_ARGUMENT, ['S', 'Store', 6]));
end;

procedure TTestRdxConstStringParameterFix.Refuse_Address_And_LoopVariable;
begin
  AssertRefused(ImplUnit(['procedure Peek(S: string);', 'begin',
    '  Writeln(PChar(@S));', 'end;']), 4, 'S', _(R_CS_ADDRESS, ['S', 6]));
  AssertRefused(ImplUnit(['procedure Each(S: string; L: TStrings);', 'begin',
    '  for S in L do', '    Writeln(S);', 'end;']), 4, 'S',
    _(R_CS_WRITTEN, ['S', 6]));
end;

procedure TTestRdxConstStringParameterFix.Refuse_RoutineAsValue;
begin
  // Als Wert passt der Typ danach nicht mehr ('procedure(S: string)').
  AssertRefused(ImplUnit(['procedure Log(Msg: string);', 'begin',
    '  Writeln(Msg);', 'end;', 'procedure Run;', 'begin',
    '  Handler := @Log;', 'end;']), 4, 'Msg', _(R_CS_VALUE, ['Log', 10]));
  AssertRefused(ImplUnit(['procedure Log(Msg: string);', 'begin',
    '  Writeln(Msg);', 'end;', 'procedure Run;', 'begin',
    '  Register(1, Log);', 'end;']), 4, 'Msg', _(R_CS_VALUE, ['Log', 10]));
end;

procedure TTestRdxConstStringParameterFix.Refuse_OtherNameOfGroupWritten;
begin
  // Das const gaelte auch fuer B - B wird beschrieben.
  AssertRefused(ImplUnit(['procedure Pair(A, B: string);', 'begin',
    '  B := A;', '  Writeln(B);', 'end;']), 4, 'A',
    _(R_CS_WRITTEN, ['B', 6]));
end;

procedure TTestRdxConstStringParameterFix.Refuse_Modifier_And_Type;
var
  R : string;
  P : TRdxParamPlan;
begin
  AssertRefused(ImplUnit(['procedure Show(var S: string);', 'begin',
    '  Writeln(S);', 'end;']), 4, 'S',
    MsgStaleSuffix(_(R_CS_MODIFIER, ['S', 'var'])));
  AssertRefused(ImplUnit(['procedure Show(S: Integer);', 'begin',
    '  Writeln(S);', 'end;']), 4, 'S',
    MsgMovedSuffix(_(R_CS_TYPE, ['S', 'string'])));
  // Die Meldung nennt AnsiString, der Kopf string: verschoben.
  Assert.IsFalse(PlanOf(ImplUnit(['procedure Show(S: string);', 'begin',
    '  Writeln(S);', 'end;']), 4, CMsg('S', 'AnsiString'), P, R));
  Assert.AreEqual(MsgMovedSuffix(_(R_CS_TYPE, ['S', 'AnsiString'])), R);
end;

procedure TTestRdxConstStringParameterFix.Refuse_DeclGroupsDifferently;
begin
  AssertRefused(ImplUnit(['procedure Pair(A: string; B: string); forward;',
    'procedure Pair(A, B: string);', 'begin', '  Writeln(A, B);', 'end;']), 5,
    'A', _(R_CS_GROUP, [4]));
end;

procedure TTestRdxConstStringParameterFix.Refuse_Include;
begin
  // Methode: ein Include kann die Methode als Wert nutzen.
  AssertRefused(Join(['unit t;', 'interface', '{$I defs.inc}', 'type',
    '  TLog = class', '  private', '    procedure Note(Msg: string);', '  end;',
    'implementation', 'procedure TLog.Note(Msg: string);', 'begin',
    '  Writeln(Msg);', 'end;', 'end.']), 10, 'Msg', _(R_CS_INCLUDE, [3]));
  // Freie Routine: schon der Kopf sperrt (geteilter Grund aus ReadSite).
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    '{$I defs.inc}', 'procedure Log(Msg: string);', 'begin', '  Writeln(Msg);',
    'end;', 'end.']), 5, 'Msg', _(R_UP_INCLUDE, [4]));
end;

procedure TTestRdxConstStringParameterFix.Refuse_WrittenInLocalRoutine;
begin
  AssertRefused(ImplUnit(['procedure Show(S: string);', '  procedure Inner;',
    '  begin', '    S := '''';', '  end;', 'begin', '  Inner;', 'end;']), 4,
    'S', _(R_CS_WRITTEN, ['S', 7]));
end;

procedure TTestRdxConstStringParameterFix.Refuse_NoName_Moved;
var
  S, R : string;
  P    : TRdxParamPlan;
begin
  S := ImplUnit(['procedure Show(S: string);', 'begin', '  Writeln(S);',
    'end;']);
  Assert.IsFalse(PlanOf(S, 4, 'Parameter without quotes', P, R));
  Assert.AreEqual(_(R_CS_NO_NAME), R);
  AssertRefused(S, 6, 'S', MsgMovedSuffix(_(R_UP_NO_HEAD, ['S'])));
end;

{$IFNDEF FPC}

// ---- echter Detektor ----

procedure RunConstString(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TConstStringParameterDetector.AnalyzeUnit(Root, Path, Results);
end;

// Die Form TDetectFunc (uTestRdxDetectorKit) fuer FixAllWith.
function DetectKind(const ASource: string;
  AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('sca170', ASource, AKind, RunConstString);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectKind(ASource, fkConstStringParameter);
end;

// Fund fuer Fund ueber den Einstieg der Tabelle (PlanFixIn ->
// TRdxFixTable.FixFor -> PlanConstStringParameter), bis der Detektor
// schweigt.
function FixAll(const ASource: string): string;
begin
  Result := FixAllWith(ASource, fkConstStringParameter, DetectKind);
end;

// Die Hilfe fuer den Fund ASeen ueber den Einstieg der Tabelle.
function PlanSeen(const ASource: string; const ASeen: TSeen): TRdxFixOutcome;
begin
  Result := PlanFixIn(ASource, 't.pas', fkConstStringParameter, ASeen);
end;

procedure TTestRdxConstStringParameterFixDetector.Detector_RoundTrip;
var
  Bad, Good : string;
begin
  Bad := Join(['unit t;', 'interface', 'type', '  TLog = class', '  private',
    '    FCount: Integer;', '    procedure Note(Msg: string);', '  public',
    '    procedure Run;', '  end;', 'implementation',
    'function Hash(s: string): Integer;', 'begin', '  Result := Length(s);',
    'end;', 'procedure TLog.Note(Msg: string);', 'begin',
    '  Inc(FCount, Length(Msg) + Hash(''x''));', 'end;', 'procedure TLog.Run;',
    'begin', '  Note(''x'');', 'end;', 'end.']);
  Good := Join(['unit t;', 'interface', 'type', '  TLog = class', '  private',
    '    FCount: Integer;', '    procedure Note(const Msg: string);',
    '  public', '    procedure Run;', '  end;', 'implementation',
    'function Hash(const s: string): Integer;', 'begin',
    '  Result := Length(s);', 'end;', 'procedure TLog.Note(const Msg: string);',
    'begin', '  Inc(FCount, Length(Msg) + Hash(''x''));', 'end;',
    'procedure TLog.Run;', 'begin', '  Note(''x'');', 'end;', 'end.']);
  Assert.AreEqual<Integer>(2, Length(Detect(Bad)));
  Assert.AreEqual(Good, FixAll(Bad));
  Assert.AreEqual<Integer>(0, Length(Detect(Good)));
end;

procedure TTestRdxConstStringParameterFixDetector.Detector_Interface_NoHelp;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // Der Detektor meldet die Implementierung; die Routine steht im
  // interface-Teil - andere Units koennen sie als Wert nutzen.
  Src := Join(['unit t;', 'interface', 'function Hash(s: string): Integer;',
    'implementation', 'function Hash(s: string): Integer;', 'begin',
    '  Result := Length(s);', 'end;', 'end.']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen));
  Assert.AreEqual<Integer>(5, Seen[0].Line);
  O := PlanSeen(Src, Seen[0]);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_CS_INTERFACE, [3]), O.Reason);
end;

procedure TTestRdxConstStringParameterFixDetector.Detector_Written_NoHelp;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // Der Detektor fragt nicht, ob der Rumpf den Parameter beschreibt - die
  // Hilfe schon (danach E2064).
  Src := ImplUnit(['function Clean(s: string): string;', 'begin',
    '  s := Trim(s);', '  Result := s;', 'end;']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen));
  O := PlanSeen(Src, Seen[0]);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_CS_WRITTEN, ['s', 6]), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

procedure TTestRdxConstStringParameterFixDetector.Table_HintAndName;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // Die Zeile der Tabelle: Name = der Parameter (Menuetext), der feste
  // Hinweis der Zeile (nennt das const-Aliasing), nicht gekennzeichnet.
  Src := ImplUnit(['function Hash(s: string): Integer;', 'begin',
    '  Result := Length(s);', 'end;']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen));
  O := PlanSeen(Src, Seen[0]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual('s', O.Name);
  Assert.IsTrue(Pos('const', O.Hint) > 0, O.Hint);
  Assert.IsFalse(O.ChangesBehavior, 'nicht gekennzeichnet');
  Assert.AreEqual(ImplUnit(['function Hash(const s: string): Integer;',
    'begin', '  Result := Length(s);', 'end;']), Apply(Src, O.Edits));
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxConstStringParameterFix);
{$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxConstStringParameterFixDetector);
{$ENDIF}

end.

unit uTestRdxLookupHoistFix;

// Editorhilfe SCA111 ParamByNameInLoop und SCA112 FieldByNameInLoop
// (uRdxLookupHoistFix): der Planer auf Text (erste Fixture,
// FPC-tauglich) und der ECHTE Detektor (uPerfHotspots) auf dem echten AST
// ueber den Einstieg der Tabelle (TRdxFixTable.FixFor via PlanFixIn/
// FixAllWith, Adapter PlanParamByNameLoop/PlanFieldByNameLoop; zweite
// Fixture, nur Delphi). Der Adapter verlangt den Empfaenger als Variable
// (LookupCheck, Quellstellen-Dienst) - die Quellen der zweiten Fixture
// deklarieren Q darum neben i (Declared, dieselben Zeilen). Die Fixtures
// stehen in einer Routine 'Foo', deren Rumpf auf Zeile 8 beginnt (BODY).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxLookupHoistFix = class
  public
    // ---- Umformung ----
    [Test] procedure FieldWhileLoop_Hoisted;
    [Test] procedure ParamForLoop_Hoisted;
    [Test] procedure ParamRepeatWithCloseOpen_Hoisted;
    [Test] procedure SingleStatementBody_Hoisted;
    [Test] procedure SameCallsReplaced_OthersKept;
    [Test] procedure NestedLoops_InnermostAround;
    [Test] procedure NameFromField_FreeSuffix;
    // ---- Gegenproben ----
    [Test] procedure MovedLine_NoHelp;
    [Test] procedure TwoDifferentCalls_NoHelp;
    [Test] procedure ReceiverOrArgument_NoHelp;
    [Test] procedure ResetInLoop_NoHelp;
    [Test] procedure ReceiverOtherUse_NoHelp;
    [Test] procedure AnonymousMethod_NoHelp;
    [Test] procedure NoStatementPlace_NoHelp;
    [Test] procedure WithOrDirective_NoHelp;
    [Test] procedure NoLoopOrRoutine_NoHelp;
    [Test] procedure CompilerTraces_NoHelp;
    [Test] procedure ReceiverDeclared_NoHelp;
    [Test] procedure UnreadableLoop_NoHelp;
    [Test] procedure CommentInsideCall_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxLookupHoistDetector = class
  public
    [Test] procedure Detector_ReportsCallLines;
    [Test] procedure Detector_FieldRoundTrip;
    [Test] procedure Detector_ParamRoundTrip;
    [Test] procedure Detector_SingleStatementRoundTrip;
    [Test] procedure Detector_CatalogExamples_Fixed;
    [Test] procedure Detector_NestedLoops_TwoPasses;
    [Test] procedure Detector_TwoCallsOnLine_NoHelp;
    // ---- Tabellenzeile (Adapter, LookupCheck) ----
    [Test] procedure Table_HintNamesVariableAndMarked;
    [Test] procedure Table_UnknownReceiver_NoHelp;
    [Test] procedure Table_FpcFile_NamesInlineVariable;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uPerfHotspots,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // TRdxFixTable.CaptionFor
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText, PlanFixIn
  {$ENDIF}
  uRdxCodeMap, uRdxLookupHoistFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply, NewMap

const
  BODY = 8;   // erste Rumpfzeile von Wrap
  // Die Meldungen des Detektors (fest, ohne Daten).
  MSG_FIELD = 'FieldByName(...) call inside loop - linear lookup per call. '
    + 'Cache the TField reference once before the loop and reuse it.';
  MSG_PARAM = 'ParamByName(...) call inside loop - linear lookup per call. '
    + 'Cache the TParam reference outside the loop or use Params[Index] '
    + 'with a known position.';

// ---- Helfer ----

// Eine Unit mit EINER Routine Foo (Zeile 4); Rumpf ab Zeile 8.
function Wrap(const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    'var', '  i: Integer;', 'begin']) + #13#10 + Join(ABody) + #13#10
    + Join(['end;', 'end.']);
end;

// Dasselbe mit AIntf im interface-Teil (ab Zeile 3); der Rumpf beginnt
// dann Length(AIntf) Zeilen spaeter.
function WrapWith(const AIntf, ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface']) + #13#10 + Join(AIntf) + #13#10
    + Join(['implementation', 'procedure Foo;', 'var', '  i: Integer;',
    'begin']) + #13#10 + Join(ABody) + #13#10 + Join(['end;', 'end.']);
end;

// Die Standard-Schleife mit ALine als erster Rumpfzeile (BODY + 2) und
// AMore dahinter.
function LoopWith(const ALine, AMore: string): string;
begin
  Result := Wrap(['  while not Q.Eof do', '  begin', ALine, AMore,
    '    Q.Next;', '  end;']);
end;

// Der Planer (AParam: SCA111, sonst SCA112) fuer Zeile ALine.
function PlanOf(const ASource: string; ALine: Integer; AParam: Boolean;
  out APlan: TRdxLookupPlan; out AReason: string): Boolean;
var
  Map : TRdxCodeMap;
begin
  Map := NewMap(ASource);
  try
    if AParam then
      Result := TRdxLookupHoistFix.ParamByNameLoop(Map, ALine, MSG_PARAM,
        APlan, AReason)
    else
      Result := TRdxLookupHoistFix.FieldByNameLoop(Map, ALine, MSG_FIELD,
        APlan, AReason);
  finally
    Map.Free;
  end;
end;

// Der neue Text, oder '' bei Ablehnung (AReason).
function Plan(const ASource: string; ALine: Integer; AParam: Boolean;
  out AReason: string): string;
var
  P : TRdxLookupPlan;
begin
  Result := '';
  if PlanOf(ASource, ALine, AParam, P, AReason) then
    Result := Apply(ASource, P.Edits);
end;

// Die Hilfe muss gelten (sonst scheitert der Test mit dem Grund).
function Applied(const ASource: string; ALine: Integer;
  AParam: Boolean): string;
var
  R : string;
begin
  Result := Plan(ASource, ALine, AParam, R);
  Assert.IsTrue(Result <> '', R);
end;

procedure AssertRefused(const ASource: string; ALine: Integer;
  AParam: Boolean; const AReason: string);
var
  R : string;
begin
  Assert.AreEqual('', Plan(ASource, ALine, AParam, R), 'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
end;

// ---- Umformung ----

procedure TTestRdxLookupHoistFix.FieldWhileLoop_Hoisted;
var
  Src, R : string;
  P      : TRdxLookupPlan;
begin
  Src := Wrap(['  Total := 0;', '  while not Q.Eof do', '  begin',
    '    Total := Total + Q.FieldByName(''Amount'').AsCurrency;',
    '    Q.Next;', '  end;']);
  Assert.AreEqual(Wrap(['  Total := 0;',
    '  var FldAmount := Q.FieldByName(''Amount'');',
    '  while not Q.Eof do', '  begin',
    '    Total := Total + FldAmount.AsCurrency;', '    Q.Next;', '  end;']),
    Applied(Src, BODY + 3, False));
  Assert.IsTrue(PlanOf(Src, BODY + 3, False, P, R), R);
  Assert.AreEqual('Q.FieldByName(''Amount'')', P.Lookup, 'Lookup');
  Assert.AreEqual('Q', P.Receiver, 'Empfaenger');
  Assert.AreEqual('FldAmount', P.Name, 'Name');
  Assert.AreEqual<Integer>(BODY + 1, P.LoopLine, 'Schleifenzeile');
  Assert.AreEqual<Integer>(1, P.Count, 'ein Vorkommen');
  Assert.AreEqual<Integer>(2, Length(P.Edits), 'Einfuegung und Ersetzung');
  // Die Einfuegung beginnt auf der (nicht leeren) Schleifenzeile.
  Assert.AreEqual('  while', P.Edits[0].Expected);
end;

procedure TTestRdxLookupHoistFix.ParamForLoop_Hoisted;
begin
  // ExecSQL in der Schleife laesst die Parameter stehen.
  Assert.AreEqual(Wrap(['  var PrmId := Q.ParamByName(''id'');',
    '  for i := 0 to High(Ids) do', '  begin',
    '    PrmId.AsInteger := Ids[i];', '    Q.ExecSQL;', '  end;']),
    Applied(Wrap(['  for i := 0 to High(Ids) do', '  begin',
      '    Q.ParamByName(''id'').AsInteger := Ids[i];', '    Q.ExecSQL;',
      '  end;']), BODY + 2, True));
end;

procedure TTestRdxLookupHoistFix.ParamRepeatWithCloseOpen_Hoisted;
begin
  // Close/Open lassen die Parameter stehen (SCA111), sperren aber SCA112
  // (ResetInLoop_NoHelp).
  Assert.AreEqual(Wrap(['  var PrmDay := Q.ParamByName(''Day'');', '  repeat',
    '    Q.Close;', '    PrmDay.AsDate := D;', '    Q.Open;', '    D := D + 1;',
    '  until D > Last;']),
    Applied(Wrap(['  repeat', '    Q.Close;',
      '    Q.ParamByName(''Day'').AsDate := D;', '    Q.Open;',
      '    D := D + 1;', '  until D > Last;']), BODY + 2, True));
end;

procedure TTestRdxLookupHoistFix.SingleStatementBody_Hoisted;
begin
  // Rumpf ohne begin auf der Zeile der Schleife.
  Assert.AreEqual(Wrap(['  var FldQty := Q.FieldByName(''Qty'');',
    '  for i := 0 to 9 do Sum := Sum + FldQty.AsInteger;', '  Done;']),
    Applied(Wrap(['  for i := 0 to 9 do Sum := Sum + '
      + 'Q.FieldByName(''Qty'').AsInteger;', '  Done;']), BODY, False));
  // Rumpf ist ein if/else ohne begin.
  Assert.AreEqual(Wrap(['  var FldOld := Q.FieldByName(''Old'');',
    '  while not Q.Eof do',
    '    if FldOld.AsBoolean then Q.Delete else Q.Next;', '  Done;']),
    Applied(Wrap(['  while not Q.Eof do',
      '    if Q.FieldByName(''Old'').AsBoolean then Q.Delete else Q.Next;',
      '  Done;']), BODY + 1, False));
end;

procedure TTestRdxLookupHoistFix.SameCallsReplaced_OthersKept;
var
  Src, R : string;
  P      : TRdxLookupPlan;
begin
  // Kopf, Rumpf und zwei auf einer Zeile; ein anderes Feld und dasselbe
  // Feld anders geschrieben bleiben stehen.
  Src := Wrap(['  while Q.FieldByName(''N'').AsInteger > 0 do', '  begin',
    '    A := Q.FieldByName(''N'').AsInteger;',
    '    B := Q.FieldByName(''M'').AsInteger;',
    '    C := Q.FieldByName(''n'').AsInteger;',
    '    D := Q.FieldByName(''N'').AsString + Q.FieldByName(''N'').AsString;',
    '    Q.Next;', '  end;']);
  Assert.AreEqual(Wrap(['  var FldN := Q.FieldByName(''N'');',
    '  while FldN.AsInteger > 0 do', '  begin', '    A := FldN.AsInteger;',
    '    B := Q.FieldByName(''M'').AsInteger;',
    '    C := Q.FieldByName(''n'').AsInteger;',
    '    D := FldN.AsString + FldN.AsString;', '    Q.Next;', '  end;']),
    Applied(Src, BODY + 2, False));
  Assert.IsTrue(PlanOf(Src, BODY + 2, False, P, R), R);
  Assert.AreEqual<Integer>(4, P.Count, 'vier Vorkommen');
end;

procedure TTestRdxLookupHoistFix.NestedLoops_InnermostAround;
var
  Src : string;
begin
  // Q2 wird in der aeusseren Schleife neu geoeffnet - die innere ist der
  // Platz fuer ihr Feld; Q1 und der Parameter von Q2 gehen vor die
  // aeussere.
  Src := Wrap(['  while not Q1.Eof do', '  begin', '    Q2.Close;',
    '    Q2.ParamByName(''Id'').AsInteger := Q1.FieldByName(''Id'').AsInteger;',
    '    Q2.Open;', '    while not Q2.Eof do', '    begin',
    '      Sum := Sum + Q2.FieldByName(''Amount'').AsCurrency;',
    '      Q2.Next;', '    end;', '    Q1.Next;', '  end;']);
  Assert.AreEqual(Wrap(['  while not Q1.Eof do', '  begin', '    Q2.Close;',
    '    Q2.ParamByName(''Id'').AsInteger := Q1.FieldByName(''Id'').AsInteger;',
    '    Q2.Open;', '    var FldAmount := Q2.FieldByName(''Amount'');',
    '    while not Q2.Eof do', '    begin',
    '      Sum := Sum + FldAmount.AsCurrency;',
    '      Q2.Next;', '    end;', '    Q1.Next;', '  end;']),
    Applied(Src, BODY + 7, False));
  Assert.AreEqual(Wrap(['  var FldId := Q1.FieldByName(''Id'');',
    '  while not Q1.Eof do', '  begin', '    Q2.Close;',
    '    Q2.ParamByName(''Id'').AsInteger := FldId.AsInteger;',
    '    Q2.Open;', '    while not Q2.Eof do', '    begin',
    '      Sum := Sum + Q2.FieldByName(''Amount'').AsCurrency;',
    '      Q2.Next;', '    end;', '    Q1.Next;', '  end;']),
    Applied(Src, BODY + 3, False));
  Assert.AreEqual(Wrap(['  var PrmId := Q2.ParamByName(''Id'');',
    '  while not Q1.Eof do', '  begin', '    Q2.Close;',
    '    PrmId.AsInteger := Q1.FieldByName(''Id'').AsInteger;',
    '    Q2.Open;', '    while not Q2.Eof do', '    begin',
    '      Sum := Sum + Q2.FieldByName(''Amount'').AsCurrency;',
    '      Q2.Next;', '    end;', '    Q1.Next;', '  end;']),
    Applied(Src, BODY + 3, True));
end;

procedure TTestRdxLookupHoistFix.NameFromField_FreeSuffix;
var
  Src : string;
begin
  Assert.AreEqual('FldAmount', TRdxLookupHoistFix.VarNameFor('Fld', 'Amount'));
  Assert.AreEqual('FldCustomerId',
    TRdxLookupHoistFix.VarNameFor('Fld', 'customer_id'));
  Assert.AreEqual('PrmFirstName',
    TRdxLookupHoistFix.VarNameFor('Prm', 'first name'));
  Assert.AreEqual('Fld2nd', TRdxLookupHoistFix.VarNameFor('Fld', '2nd'));
  Assert.AreEqual('FldABC', TRdxLookupHoistFix.VarNameFor('Fld', 'a.b-c'));
  Assert.AreEqual('Fld', TRdxLookupHoistFix.VarNameFor('Fld', '---'));
  // Der Name kommt schon vor (auch im Kommentar): Suffix 2.
  Src := LoopWith('    S := S + Q.FieldByName(''Amount'').AsString;',
    '    // FldAmount gibt es schon');
  Assert.AreEqual(Wrap(['  var FldAmount2 := Q.FieldByName(''Amount'');',
    '  while not Q.Eof do', '  begin', '    S := S + FldAmount2.AsString;',
    '    // FldAmount gibt es schon', '    Q.Next;', '  end;']),
    Applied(Src, BODY + 2, False));
  // Alle neun vergeben.
  AssertRefused(LoopWith('    S := S + Q.FieldByName(''Amount'').AsString;',
    '    // FldAmount FldAmount2 FldAmount3 FldAmount4 FldAmount5 FldAmount6 '
    + 'FldAmount7 FldAmount8 FldAmount9'), BODY + 2, False,
    _(R_LH_NAME, ['FldAmount', 'FldAmount', 'FldAmount']));
end;

// ---- Gegenproben ----

procedure TTestRdxLookupHoistFix.MovedLine_NoHelp;
var
  Src : string;
begin
  Src := LoopWith('    X := Q.FieldByName(''A'').AsString;', '    Y := 1;');
  // Die Zeile davor / danach traegt keinen Aufruf, eine Zeile ausserhalb.
  AssertRefused(Src, BODY + 1, False,
    MsgMovedSuffix(_(R_LH_MOVED, [METHOD_FIELD])));
  AssertRefused(Src, BODY + 3, False,
    MsgMovedSuffix(_(R_LH_MOVED, [METHOD_FIELD])));
  AssertRefused(Src, 99, False, MsgMovedSuffix(_(R_LH_MOVED, [METHOD_FIELD])));
  AssertRefused(Src, 0, False, MsgMovedSuffix(_(R_LH_MOVED, [METHOD_FIELD])));
  // Die andere Regel auf derselben Zeile.
  AssertRefused(Src, BODY + 2, True,
    MsgMovedSuffix(_(R_LH_MOVED, [METHOD_PARAM])));
  // Kommentar und String sind nie Code.
  Src := LoopWith('    // X := Q.FieldByName(''A'').AsString;',
    '    S := ''Q.FieldByName(x)'';');
  AssertRefused(Src, BODY + 2, False,
    MsgMovedSuffix(_(R_LH_MOVED, [METHOD_FIELD])));
  AssertRefused(Src, BODY + 3, False,
    MsgMovedSuffix(_(R_LH_MOVED, [METHOD_FIELD])));
end;

procedure TTestRdxLookupHoistFix.TwoDifferentCalls_NoHelp;
begin
  // Welchen der Fund meint, sagt die Meldung nicht.
  AssertRefused(LoopWith('    X := Q.FieldByName(''A'').AsString + '
    + 'Q.FieldByName(''B'').AsString;', '    Y := 1;'), BODY + 2, False,
    _(R_LH_MANY, [2, METHOD_FIELD]));
  AssertRefused(LoopWith('    X := Q1.FieldByName(''A'').AsString + '
    + 'Q2.FieldByName(''A'').AsString;', '    Y := 1;'), BODY + 2, False,
    _(R_LH_MANY, [2, METHOD_FIELD]));
end;

procedure TTestRdxLookupHoistFix.ReceiverOrArgument_NoHelp;
begin
  AssertRefused(LoopWith('    X := Self.Q.FieldByName(''A'').AsString;',
    '    Y := 1;'), BODY + 2, False, _(R_LH_RECEIVER, [METHOD_FIELD]));
  AssertRefused(LoopWith('    X := DM.Q.FieldByName(''A'').AsString;',
    '    Y := 1;'), BODY + 2, False, _(R_LH_RECEIVER, [METHOD_FIELD]));
  AssertRefused(LoopWith('    X := Self.FieldByName(''A'').AsString;',
    '    Y := 1;'), BODY + 2, False, _(R_LH_RECEIVER, [METHOD_FIELD]));
  AssertRefused(LoopWith('    X := Q.FieldByName(FieldName).AsString;',
    '    Y := 1;'), BODY + 2, False, _(R_LH_ARG, [METHOD_FIELD]));
  AssertRefused(LoopWith('    X := Q.FieldByName(''A'' + ''B'').AsString;',
    '    Y := 1;'), BODY + 2, False, _(R_LH_ARG, [METHOD_FIELD]));
  AssertRefused(LoopWith('    X := Q.FieldByName('''').AsString;',
    '    Y := 1;'), BODY + 2, False, _(R_LH_ARG, [METHOD_FIELD]));
  AssertRefused(LoopWith('    X := Q.FieldByName({c} ''A'').AsString;',
    '    Y := 1;'), BODY + 2, False, _(R_LH_ARG, [METHOD_FIELD]));
  AssertRefused(LoopWith('    X := Q.FieldByName(', '      ''A'').AsString;'),
    BODY + 2, False, _(R_LH_ARG, [METHOD_FIELD]));
end;

procedure TTestRdxLookupHoistFix.ResetInLoop_NoHelp;
begin
  // SCA112: schliessen, oeffnen, SQL wechseln - die Felder koennen neu
  // entstehen.
  AssertRefused(LoopWith('    X := Q.FieldByName(''A'').AsString;',
    '    Q.Close;'), BODY + 2, False,
    _(R_LH_RESET_FIELD, ['Q.Close', BODY + 3, 'Q']));
  AssertRefused(LoopWith('    X := Q.FieldByName(''A'').AsString;',
    '    Q.Active := False;'), BODY + 2, False,
    _(R_LH_RESET_FIELD, ['Q.Active', BODY + 3, 'Q']));
  AssertRefused(LoopWith('    X := Q.FieldByName(''A'').AsString;',
    '    Q.SQL.Text := S;'), BODY + 2, False,
    _(R_LH_RESET_FIELD, ['Q.SQL', BODY + 3, 'Q']));
  // Dieselbe Schleife wie ParamRepeatWithCloseOpen_Hoisted mit einem Feld.
  AssertRefused(Wrap(['  repeat', '    Q.Close;',
    '    X := Q.FieldByName(''Day'').AsDateTime;', '    Q.Open;',
    '  until X > Last;']), BODY + 2, False,
    _(R_LH_RESET_FIELD, ['Q.Close', BODY + 1, 'Q']));
  // SCA111: SQL und Params legen die Parameter neu an.
  AssertRefused(LoopWith('    Q.ParamByName(''A'').AsString := S;',
    '    Q.SQL.Text := S;'), BODY + 2, True,
    _(R_LH_RESET_PARAM, ['Q.SQL', BODY + 3, 'Q']));
  AssertRefused(LoopWith('    Q.ParamByName(''A'').AsString := S;',
    '    Q.Params.Clear;'), BODY + 2, True,
    _(R_LH_RESET_PARAM, ['Q.Params', BODY + 3, 'Q']));
end;

procedure TTestRdxLookupHoistFix.ReceiverOtherUse_NoHelp;
begin
  // Zugewiesen, weitergereicht, ueber ein anderes Objekt erreicht.
  AssertRefused(LoopWith('    X := Q.FieldByName(''A'').AsString;',
    '    Q := NextQuery(Q);'), BODY + 2, False,
    _(R_LH_BARE, ['Q', BODY + 3, 'Q']));
  AssertRefused(LoopWith('    X := Q.FieldByName(''A'').AsString;',
    '    Show(Q);'), BODY + 2, False, _(R_LH_BARE, ['Q', BODY + 3, 'Q']));
  AssertRefused(LoopWith('    X := Q.FieldByName(''A'').AsString;',
    '    Self.Q.Refresh;'), BODY + 2, False,
    _(R_LH_BARE, ['Q', BODY + 3, 'Q']));
  // Q ist die Schleifenvariable.
  AssertRefused(Wrap(['  for Q in Queries do',
    '    X := Q.FieldByName(''A'').AsString;']), BODY + 1, False,
    _(R_LH_BARE, ['Q', BODY, 'Q']));
end;

procedure TTestRdxLookupHoistFix.AnonymousMethod_NoHelp;
begin
  AssertRefused(LoopWith('    TThread.Queue(nil, procedure begin '
    + 'Show(Q.FieldByName(''A'').AsString); end);', '    Y := 1;'),
    BODY + 2, False, _(R_LH_ANON, ['Q']));
end;

procedure TTestRdxLookupHoistFix.NoStatementPlace_NoHelp;
begin
  // Hinter 'then': die Deklaration gehoerte in den Zweig.
  AssertRefused(Wrap(['  if A then while not Q.Eof do', '  begin',
    '    X := Q.FieldByName(''A'').AsString;', '    Q.Next;', '  end;']),
    BODY + 2, False, _(R_LH_PLACE, [BODY]));
  // Nicht am Zeilenanfang.
  AssertRefused(Wrap(['  Q.First; while not Q.Eof do', '  begin',
    '    X := Q.FieldByName(''A'').AsString;', '    Q.Next;', '  end;']),
    BODY + 2, False, _(R_LH_PLACE, [BODY]));
  // Im try-Teil (kein begin..end).
  AssertRefused(Wrap(['  try', '    Q.First;', '    while not Q.Eof do',
    '    begin', '      X := Q.FieldByName(''A'').AsString;', '      Q.Next;',
    '    end;', '  finally', '    Q.Close;', '  end;']), BODY + 4, False,
    _(R_LH_PLACE, [BODY + 2]));
end;

procedure TTestRdxLookupHoistFix.WithOrDirective_NoHelp;
begin
  AssertRefused(Wrap(['  with Form do Caption := ''x'';',
    '  while not Q.Eof do', '  begin', '    X := Q.FieldByName(''A'').AsString;',
    '    Q.Next;', '  end;']), BODY + 3, False,
    _(R_LH_ROUTINE_WORD, ['with']));
  AssertRefused(Wrap(['  while not Q.Eof do', '  begin',
    '    X := Q.FieldByName(''A'').AsString;', '    {$IFDEF DEBUG}',
    '    Log(X);', '    {$ENDIF}', '    Q.Next;', '  end;']), BODY + 2, False,
    _(R_LH_DIRECTIVE, ['Q']));
end;

procedure TTestRdxLookupHoistFix.NoLoopOrRoutine_NoHelp;
begin
  // Keine Schleife um den Aufruf - bzw. eine, die vorher endet.
  AssertRefused(Wrap(['  X := Q.FieldByName(''A'').AsString;']), BODY, False,
    MsgStaleSuffix(_(R_LH_NO_LOOP)));
  AssertRefused(Wrap(['  while not Q.Eof do Q.Next;',
    '  X := Q.FieldByName(''A'').AsString;']), BODY + 1, False,
    MsgStaleSuffix(_(R_LH_NO_LOOP)));
  // Hauptblock eines Programms: keine Routine.
  AssertRefused(Join(['program p;', 'begin', '  while not Q.Eof do', '  begin',
    '    X := Q.FieldByName(''A'').AsString;', '    Q.Next;', '  end;',
    'end.']), 5, False, _(R_LH_NO_ROUTINE));
end;

procedure TTestRdxLookupHoistFix.CompilerTraces_NoHelp;
const
  LOOP: array[0..4] of string = ('  while not Q.Eof do', '  begin',
    '    X := Q.FieldByName(''A'').AsString;', '    Q.Next;', '  end;');
begin
  // Der Rumpf beginnt mit einer interface-Zeile eine Zeile spaeter.
  AssertRefused(WrapWith(['{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}'], LOOP),
    BODY + 3, False, _(R_LH_FPC, [3]));
  AssertRefused(WrapWith(['{$IFDEF VER320}{$ENDIF}'], LOOP), BODY + 3, False,
    _(R_LH_OLD, ['VER320', 3]));
  // Ohne unit-Kopf: Include oder Skript.
  AssertRefused(Join(['procedure Foo;', 'begin', '  while not Q.Eof do',
    '  begin', '    X := Q.FieldByName(''A'').AsString;', '    Q.Next;',
    '  end;', 'end;']), 5, False, _(R_LH_SCRIPT));
end;

procedure TTestRdxLookupHoistFix.ReceiverDeclared_NoHelp;
const
  LOOP: array[0..4] of string = ('  while not Q.Eof do', '  begin',
    '    X := Q.FieldByName(''A'').AsString;', '    Q.Next;', '  end;');
begin
  AssertRefused(WrapWith(['function Q: TDataSet;'], LOOP), BODY + 3, False,
    _(R_LH_DECLARED, ['Q']));
  AssertRefused(WrapWith(['type', '  TFoo = class',
    '    property Q: TDataSet read FQ;', '  end;'], LOOP), BODY + 6, False,
    _(R_LH_DECLARED, ['Q']));
end;

procedure TTestRdxLookupHoistFix.UnreadableLoop_NoHelp;
begin
  // Die innere Schleife (Zeile BODY + 2) liest die Hilfe nicht - sie
  // koennte den Aufruf umfassen.
  AssertRefused(Wrap(['  while not Q.Eof do', '  begin',
    '    for i := 0 to 3 do P := procedure begin end;',
    '    X := Q.FieldByName(''A'').AsString;', '    Q.Next;', '  end;']),
    BODY + 3, False, _(R_LH_LOOP_UNREADABLE, [BODY + 2]));
end;

procedure TTestRdxLookupHoistFix.CommentInsideCall_NoHelp;
begin
  // Das zweite Vorkommen traegt einen Kommentar - die Ersetzung nahme ihn
  // mit.
  AssertRefused(LoopWith('    X := Q.FieldByName(''A'').AsString;',
    '    Y := Q.{c}FieldByName(''A'').AsString;'), BODY + 2, False,
    _(R_LH_COMMENT, ['Q.FieldByName(''A'')', BODY + 3]));
end;

{$IFNDEF FPC}

{ ---- Detektor und Tabelle ---- }

// Die Funde der Arten SCA111/SCA112 - der echte Detektor auf dem echten
// AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TPerfHotspotsDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_lookup_', ASource, AKind, RunDetector);
end;

// ASource mit Q als Variable von Foo - auf der Zeile von i (Wrap,
// WrapWith), die Zeilen bleiben. Ohne Deklaration lehnt der Adapter ab
// (LookupCheck: Q koennte eine Funktion sein).
function Declared(const ASource: string): string;
begin
  Result := StringReplace(ASource, '  i: Integer;',
    '  i: Integer; Q: TFDQuery;', []);
end;

// Die Hilfe fuer den ersten Fund der Art AKind ueber den Einstieg der
// Tabelle (PlanFixIn: TRdxFixTable.FixFor, Adapter PlanParamByNameLoop
// bzw. PlanFieldByNameLoop) in der Datei AFile.
function PlanFirstIn(const ASource, AFile: string;
  AKind: TFindingKind): TRdxFixOutcome;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(ASource, AKind);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet');
  Result := PlanFixIn(ASource, AFile, AKind, Seen[0]);
end;

// Fund fuer Fund ueber die Tabelle, nach jeder Ersetzung neu gemeldet, bis
// der Detektor schweigt (FixAllWith).
function FixAll(const ASource: string; AKind: TFindingKind): string;
begin
  Result := FixAllWith(ASource, AKind, Detect);
end;

procedure TTestRdxLookupHoistDetector.Detector_ReportsCallLines;
var
  Seen : TArray<TSeen>;
begin
  // Je Aufruf ein Fund auf seiner Zeile, mit der festen Meldung.
  Seen := Detect(LoopWith('    X := Q.FieldByName(''A'').AsString;',
    '    Y := 1;'), fkFieldByNameInLoop);
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(BODY + 2, Seen[0].Line, 'Zeile des Aufrufs');
  Assert.AreEqual(MSG_FIELD, Seen[0].Msg, 'feste Meldung');
  Seen := Detect(LoopWith('    Q.ParamByName(''A'').AsString := S;',
    '    Q.ExecSQL;'), fkParamByNameInLoop);
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(BODY + 2, Seen[0].Line, 'Zeile des Aufrufs');
  Assert.AreEqual(MSG_PARAM, Seen[0].Msg, 'feste Meldung');
  // Zwei Aufrufe auf einer Zeile: zwei gleiche Funde.
  Seen := Detect(LoopWith('    X := Q.FieldByName(''A'').AsString + '
    + 'Q.FieldByName(''B'').AsString;', '    Y := 1;'), fkFieldByNameInLoop);
  Assert.AreEqual<Integer>(2, Length(Seen), 'zwei Funde');
  Assert.AreEqual<Integer>(Seen[0].Line, Seen[1].Line, 'dieselbe Zeile');
end;

procedure TTestRdxLookupHoistDetector.Detector_FieldRoundTrip;
var
  Fixed : string;
begin
  Fixed := FixAll(Declared(Wrap(['  while not Q.Eof do', '  begin',
    '    Total := Total + Q.FieldByName(''Amount'').AsCurrency;',
    '    Count := Count + Q.FieldByName(''Amount'').AsInteger;',
    '    Q.Next;', '  end;'])), fkFieldByNameInLoop);
  Assert.AreEqual(Declared(Wrap([
    '  var FldAmount := Q.FieldByName(''Amount'');',
    '  while not Q.Eof do', '  begin',
    '    Total := Total + FldAmount.AsCurrency;',
    '    Count := Count + FldAmount.AsInteger;', '    Q.Next;', '  end;'])),
    Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed, fkFieldByNameInLoop)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxLookupHoistDetector.Detector_ParamRoundTrip;
var
  Fixed : string;
begin
  Fixed := FixAll(Declared(Wrap(['  repeat', '    Q.Close;',
    '    Q.ParamByName(''Day'').AsDate := D;', '    Q.Open;',
    '    D := D + 1;', '  until D > Last;'])), fkParamByNameInLoop);
  Assert.AreEqual(Declared(Wrap(['  var PrmDay := Q.ParamByName(''Day'');',
    '  repeat', '    Q.Close;', '    PrmDay.AsDate := D;', '    Q.Open;',
    '    D := D + 1;', '  until D > Last;'])), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed, fkParamByNameInLoop)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxLookupHoistDetector.Detector_SingleStatementRoundTrip;
var
  Fixed : string;
begin
  // Rumpf ohne begin: der Detektor liest ihn bis zum naechsten ';'.
  Fixed := FixAll(Declared(Wrap(['  while not Q.Eof do',
    '    if Q.FieldByName(''Old'').AsBoolean then Q.Delete else Q.Next;',
    '  Done;'])), fkFieldByNameInLoop);
  Assert.AreEqual(Declared(Wrap(['  var FldOld := Q.FieldByName(''Old'');',
    '  while not Q.Eof do',
    '    if FldOld.AsBoolean then Q.Delete else Q.Next;', '  Done;'])), Fixed);
end;

procedure TTestRdxLookupHoistDetector.Detector_CatalogExamples_Fixed;
var
  Meta  : TRuleMeta;
  Src   : string;
  Fixed : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkFieldByNameInLoop);
  Assert.IsTrue(Pos('FieldByName', Meta.BadExample) > 0, Meta.BadExample);
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    'var', '  Q: TFDQuery;', 'begin', CatalogText(Meta.BadExample), 'end;',
    'end.']);
  Assert.AreEqual<Integer>(1, Length(Detect(Src, fkFieldByNameInLoop)),
    'der Detektor meldet das Beispiel');
  Fixed := FixAll(Src, fkFieldByNameInLoop);
  Assert.IsTrue(Pos('var FldAmount := Q.FieldByName(''Amount'');', Fixed) > 0,
    Fixed);
  Assert.IsTrue(Pos('FldAmount.AsCurrency', Fixed) > 0, Fixed);

  Meta := TRuleCatalog.GetRuleCanonical(fkParamByNameInLoop);
  Assert.IsTrue(Pos('ParamByName', Meta.BadExample) > 0, Meta.BadExample);
  Src := Declared(Join(['unit t;', 'interface', 'implementation',
    'procedure Foo;', 'var', '  i: Integer;', 'begin',
    CatalogText(Meta.BadExample), 'end;', 'end.']));
  Assert.AreEqual<Integer>(1, Length(Detect(Src, fkParamByNameInLoop)),
    'der Detektor meldet das Beispiel');
  Fixed := FixAll(Src, fkParamByNameInLoop);
  Assert.IsTrue(Pos('var PrmId := Q.ParamByName(''id'');', Fixed) > 0, Fixed);
  Assert.IsTrue(Pos('PrmId.AsInteger := Ids[i];', Fixed) > 0, Fixed);
end;

procedure TTestRdxLookupHoistDetector.Detector_NestedLoops_TwoPasses;
begin
  // Erst die innere Schleife; die neue Zeile steht in der aeusseren, der
  // Detektor meldet sie, und der zweite Durchlauf zieht sie weiter hinaus
  // (Name2) - Q.First laesst die Felder stehen.
  Assert.AreEqual(Declared(Wrap([
    '  var FldAmount2 := Q.FieldByName(''Amount'');',
    '  for i := 0 to 9 do', '  begin', '    Q.First;',
    '    var FldAmount := FldAmount2;', '    while not Q.Eof do', '    begin',
    '      Sum := Sum + FldAmount.AsCurrency;', '      Q.Next;', '    end;',
    '  end;'])),
    FixAll(Declared(Wrap(['  for i := 0 to 9 do', '  begin', '    Q.First;',
      '    while not Q.Eof do', '    begin',
      '      Sum := Sum + Q.FieldByName(''Amount'').AsCurrency;',
      '      Q.Next;', '    end;', '  end;'])), fkFieldByNameInLoop));
end;

procedure TTestRdxLookupHoistDetector.Detector_TwoCallsOnLine_NoHelp;
var
  O : TRdxFixOutcome;
begin
  O := PlanFirstIn(Declared(LoopWith('    X := Q.FieldByName(''A'').AsString + '
    + 'Q.FieldByName(''B'').AsString;', '    Y := 1;')), 't.pas',
    fkFieldByNameInLoop);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_LH_MANY, [2, METHOD_FIELD]), O.Reason);
  // Der Menuetext kennt den Aufruf erst, wenn er feststeht; gekennzeichnet
  // ist der Eintrag auch gesperrt (Tabellenzeile).
  Assert.AreEqual('', O.Name);
  Assert.IsTrue(O.ChangesBehavior);
end;

procedure TTestRdxLookupHoistDetector.Table_HintNamesVariableAndMarked;
var
  O : TRdxFixOutcome;
begin
  // Der Hinweis nennt den neuen Namen (HintByPlanner), der Menuetext den
  // Aufruf; gekennzeichnet (Changes: True).
  O := PlanFirstIn(Declared(LoopWith(
    '    Q.ParamByName(''Id'').AsInteger := 1;', '    Q.ExecSQL;')), 't.pas',
    fkParamByNameInLoop);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual('Q.ParamByName(''Id'')', O.Name);
  Assert.IsTrue(O.ChangesBehavior, 'gekennzeichnet');
  Assert.IsTrue(Pos('Parameter-Referenz PrmId', O.Hint) > 0, O.Hint);
  Assert.IsTrue(Pos('Q.ParamByName(''Id'')',
    TRdxFixTable.CaptionFor(fkParamByNameInLoop, O)) > 0,
    'der Menuetext nennt den Aufruf');
  O := PlanFirstIn(Declared(LoopWith('    X := Q.FieldByName(''A'').AsString;',
    '    Y := 1;')), 't.pas', fkFieldByNameInLoop);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsTrue(Pos('Feld-Referenz FldA', O.Hint) > 0, O.Hint);
end;

procedure TTestRdxLookupHoistDetector.Table_UnknownReceiver_NoHelp;
var
  O : TRdxFixOutcome;
begin
  // Q ist nirgends deklariert - es koennte eine Funktion sein, die bei
  // jedem Aufruf ein anderes Objekt liefert (LookupCheck).
  O := PlanFirstIn(LoopWith('    X := Q.FieldByName(''A'').AsString;',
    '    Y := 1;'), 't.pas', fkFieldByNameInLoop);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(TRdxLookupHoistFix.UnknownReceiverReason('Q'), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
  // Eine Inline-Variable vor der Schleife gilt als Beweis.
  O := PlanFirstIn(Wrap(['  var Q := TFDQuery.Create(nil);',
    '  while not Q.Eof do', '  begin',
    '    X := Q.FieldByName(''A'').AsString;', '    Q.Next;', '  end;']),
    't.pas', fkFieldByNameInLoop);
  Assert.IsTrue(O.Enabled, O.Reason);
end;

procedure TTestRdxLookupHoistDetector.Table_FpcFile_NamesInlineVariable;
var
  O : TRdxFixOutcome;
begin
  // Eine .pp-Datei baut FPC - der Plattenblick (lfInlineVar) lehnt ab und
  // nennt die Inline-Variable, nicht die Inline-Konstante von SCA014.
  O := PlanFirstIn(Declared(LoopWith('    X := Q.FieldByName(''A'').AsString;',
    '    Y := 1;')), 't.pp', fkFieldByNameInLoop);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.IsTrue(Pos('Inline-Variable', O.Reason) > 0, O.Reason);
  Assert.AreEqual<Integer>(0, Pos('Inline-Konstante', O.Reason), O.Reason);
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxLookupHoistFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxLookupHoistDetector);
  {$ENDIF}

end.

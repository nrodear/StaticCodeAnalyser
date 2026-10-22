unit uTestRdxParamNameFix;

// Editorhilfe SCA199 ParamNameMismatch (uRdxParamNameFix): der Planer auf
// Text (erste Fixture, FPC-tauglich) und der ECHTE Detektor
// (uParamNameMismatch) auf dem echten AST mit MapFix wie der Adapter der
// Tabelle (zweite Fixture, nur Delphi). Die Fixtures stehen in einer
// Routine 'Load(Q: TFDQuery)', deren Rumpf auf Zeile 5 beginnt; der
// gemeldete Aufruf steht auf Zeile 8 (CALL_LINE). Die Meldung (a) nennt die
// Platzhalter des SQL ('(it has :Id, :Name)') - daraus waehlt der Planer.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxParamNameFix = class
  public
    // ---- Umformung ----
    [Test] procedure Transposition_Fixed;
    [Test] procedure OneLetter_Fixed;
    [Test] procedure SpellingOfSql_Kept;
    [Test] procedure QueryChains_Fixed;
    [Test] procedure Edit_ReplacesOnlyTheName;
    [Test] procedure TypoDistance_Rules;
    [Test] procedure FieldByNameSameName_Fixed;
    // ---- Gegenproben ----
    [Test] procedure FarName_NoHelp;
    [Test] procedure TwoCandidates_NoHelp;
    [Test] procedure ShortName_NoHelp;
    [Test] procedure TruncatedOrEmptyList_NoHelp;
    [Test] procedure OtherDirectionOrForm_NoHelp;
    [Test] procedure NameAlreadySet_NoHelp;
    [Test] procedure MovedLineOrQuery_NoHelp;
    [Test] procedure CommentOrString_NoHelp;
    [Test] procedure NotPlainLiteral_NoHelp;
    [Test] procedure TwiceOnLine_NoHelp;
    [Test] procedure NoRoutine_NoHelp;
    [Test] procedure CastOrIndex_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxParamNameDetector = class
  public
    [Test] procedure Detector_ReportsUnknownWithList;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_CreatedQuery_BothDirectionsGone;
    [Test] procedure Detector_CatalogExample_NoHelp;
    [Test] procedure Detector_MapFix_OneEdit;
  end;
{$ENDIF}

implementation

// noinspection-file SQLInjection
// Die Fixtures sind SQL in String-Literalen - genau das, was SCA003 sucht.

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uParamNameMismatch,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixRunner,         // MapFix (wie der Adapter der Tabelle)
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxParamNameFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply

const
  CALL_LINE = 8;   // der Aufruf in Std
  SQL_CLEAR = '  Q.SQL.Clear;';
  SQL_ADD   = '  Q.SQL.Add(''select * from t where name = :Name and id = :Id'');';
  SET_ID    = '  Q.ParamByName(''Id'').AsInteger := 1;';
  OPEN_Q    = '  Q.Open;';
  LIST_STD  = ':Id, :Name';

// ---- Helfer ----

// Eine Unit mit EINER Routine Load(Q: TFDQuery); Rumpf ab Zeile 6.
function Wrap(const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation',
    'procedure Load(Q: TFDQuery);', 'begin']) + #13#10 + Join(ABody)
    + #13#10 + Join(['end;', 'end.']);
end;

// Das Muster: SQL mit :Name und :Id, ACall auf Zeile CALL_LINE.
function Std(const ACall: string): string;
begin
  Result := Wrap([SQL_CLEAR, SQL_ADD, ACall, SET_ID, OPEN_Q]);
end;

// Der Aufruf mit dem Namen AName.
function Call(const AName: string): string;
begin
  Result := '  Q.ParamByName(''' + AName + ''').AsString := ''x'';';
end;

// Die Meldung (a) des Detektors (uParamNameScan.MessageOf).
function Msg(const AQuery, AParam, AList: string): string;
begin
  Result := Format('%s.ParamByName(''%s''): the SQL this routine assigns '
    + 'to %s has no :%s (it has %s) - raises "parameter not found" at run '
    + 'time', [AQuery, AParam, AQuery, AParam, AList]);
end;

// Der Planer fuer Zeile ALine: die Ersetzung in AEdit, True oder False mit
// dem Grund.
function PlanEdit(const ASource: string; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  AReason := '';
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    try
      Result := TRdxParamNameFix.UsePlaceholder(Map, ALine, AMessage, AEdit,
        AReason);
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
end;

// Der neue Text, oder '' bei Ablehnung (AReason).
function Plan(const ASource: string; ALine: Integer; const AMessage: string;
  out AReason: string): string;
var
  E : TRdxEdit;
begin
  Result := '';
  if PlanEdit(ASource, ALine, AMessage, E, AReason) then
    Result := Apply(ASource, E);
end;

// Die Hilfe muss gelten (sonst scheitert der Test mit dem Grund).
function Applied(const ASource: string; ALine: Integer;
  const AMessage: string): string;
var
  R : string;
begin
  Result := Plan(ASource, ALine, AMessage, R);
  Assert.IsTrue(Result <> '', R);
end;

procedure AssertRefused(const ASource: string; ALine: Integer;
  const AMessage, AReason: string);
var
  R : string;
begin
  Assert.AreEqual('', Plan(ASource, ALine, AMessage, R), 'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
end;

// ---- Umformung ----

procedure TTestRdxParamNameFix.Transposition_Fixed;
begin
  Assert.AreEqual(Std(Call('Name')),
    Applied(Std(Call('Nmae')), CALL_LINE, Msg('Q', 'Nmae', LIST_STD)));
end;

procedure TTestRdxParamNameFix.OneLetter_Fixed;
begin
  // Ein Zeichen fehlt, ist zu viel oder anders.
  Assert.AreEqual(Std(Call('Name')),
    Applied(Std(Call('Nme')), CALL_LINE, Msg('Q', 'Nme', LIST_STD)));
  Assert.AreEqual(Std(Call('Name')),
    Applied(Std(Call('Namee')), CALL_LINE, Msg('Q', 'Namee', LIST_STD)));
  Assert.AreEqual(Std(Call('Name')),
    Applied(Std(Call('Nane')), CALL_LINE, Msg('Q', 'Nane', LIST_STD)));
  Assert.AreEqual(Std(Call('cust_id')),
    Applied(Std(Call('custid')), CALL_LINE, Msg('Q', 'custid',
      ':cust_id, :Id')));
end;

procedure TTestRdxParamNameFix.SpellingOfSql_Kept;
begin
  // Eingesetzt wird der Name, wie die Meldung ihn aus dem SQL nennt.
  Assert.AreEqual(Std(Call('CustomerID')),
    Applied(Std(Call('customerIF')), CALL_LINE, Msg('Q', 'customerIF',
      ':CustomerID, :Id')));
end;

procedure TTestRdxParamNameFix.QueryChains_Fixed;
begin
  // 'Self.' und Params/Parameters zwischen Query und ParamByName.
  Assert.AreEqual(
    Std('  Self.Q.Params.ParamByName(''Name'').AsString := ''x'';'),
    Applied(Std('  Self.Q.Params.ParamByName(''Nmae'').AsString := ''x'';'),
      CALL_LINE, Msg('Q', 'Nmae', LIST_STD)));
  Assert.AreEqual(
    Std('  Q.Parameters.ParamByName(''Name'').Value := ''x'';'),
    Applied(Std('  Q.Parameters.ParamByName(''Nmae'').Value := ''x'';'),
      CALL_LINE, Msg('Q', 'Nmae', LIST_STD)));
  // Eine Query mit Punkt-Kette (Datenmodul).
  Assert.AreEqual(
    Std('  DM.qryUser.ParamByName(''Name'').AsString := ''x'';'),
    Applied(Std('  DM.qryUser.ParamByName(''Nmae'').AsString := ''x'';'),
      CALL_LINE, Msg('DM.qryUser', 'Nmae', LIST_STD)));
end;

procedure TTestRdxParamNameFix.Edit_ReplacesOnlyTheName;
var
  E : TRdxEdit;
  R : string;
begin
  // '  Q.ParamByName(''Nmae'')': das Quote steht in Spalte 17, der Name in
  // 18..21.
  Assert.IsTrue(PlanEdit(Std(Call('Nmae')), CALL_LINE,
    Msg('Q', 'Nmae', LIST_STD), E, R), R);
  Assert.AreEqual('Nmae', E.Expected);
  Assert.AreEqual('Name', E.NewText);
  Assert.AreEqual<Integer>(CALL_LINE, E.Span.StartLine);
  Assert.AreEqual<Integer>(CALL_LINE, E.Span.EndLine);
  Assert.AreEqual<Integer>(18, E.Span.StartCol);
  Assert.AreEqual<Integer>(22, E.Span.EndCol);
end;

procedure TTestRdxParamNameFix.TypoDistance_Rules;
begin
  Assert.AreEqual<Integer>(1, ParamTypoDistance('Nmae', 'Name'), 'vertauscht');
  Assert.AreEqual<Integer>(1, ParamTypoDistance('Nme', 'Name'), 'fehlt');
  Assert.AreEqual<Integer>(1, ParamTypoDistance('Namee', 'Name'), 'zu viel');
  Assert.AreEqual<Integer>(1, ParamTypoDistance('Nane', 'Name'), 'anders');
  Assert.AreEqual<Integer>(0, ParamTypoDistance('NAME', 'name'),
    'Gross/klein zaehlt nicht');
  Assert.AreEqual<Integer>(5, ParamTypoDistance('custid', 'customer_id'),
    'fuenf Zeichen fehlen');
  Assert.AreEqual<Integer>(2, ParamTypoDistance('abcd', 'badc'),
    'zwei Vertauschungen');
  Assert.AreEqual<Integer>(3, ParamTypoDistance('abc', ''), 'leer');
end;

procedure TTestRdxParamNameFix.FieldByNameSameName_Fixed;
begin
  // Ein Feld gleichen Namens setzt keinen Parameter - keine Sperre.
  Assert.AreEqual(
    Wrap([SQL_CLEAR, SQL_ADD, Call('Name'), SET_ID, OPEN_Q,
      '  S := Q.FieldByName(''Name'').AsString;']),
    Applied(Wrap([SQL_CLEAR, SQL_ADD, Call('Nmae'), SET_ID, OPEN_Q,
      '  S := Q.FieldByName(''Name'').AsString;']), CALL_LINE,
      Msg('Q', 'Nmae', LIST_STD)));
end;

// ---- Gegenproben ----

procedure TTestRdxParamNameFix.FarName_NoHelp;
begin
  // Das Katalogbeispiel: 'custid' -> 'customer_id' ist kein Tippfehler.
  AssertRefused(Std(Call('custid')), CALL_LINE,
    Msg('Q', 'custid', ':customer_id'),
    _(R_PN_NO_CANDIDATE, ['custid', ':customer_id']));
  // Nur Gross/klein anders meldet der Detektor nie - hier kein Tippfehler.
  AssertRefused(Std(Call('NAME')), CALL_LINE, Msg('Q', 'NAME', ':Name'),
    _(R_PN_NO_CANDIDATE, ['NAME', ':Name']));
end;

procedure TTestRdxParamNameFix.TwoCandidates_NoHelp;
begin
  AssertRefused(Std(Call('Nme')), CALL_LINE, Msg('Q', 'Nme', ':Name, :Nmea'),
    _(R_PN_MANY, [2, 'Nme']));
end;

procedure TTestRdxParamNameFix.ShortName_NoHelp;
begin
  AssertRefused(Std(Call('ix')), CALL_LINE, Msg('Q', 'ix', ':id'),
    _(R_PN_SHORT, ['ix']));
  // Der Kandidat selbst ist zu kurz.
  AssertRefused(Std(Call('Idd')), CALL_LINE, Msg('Q', 'Idd', ':Id'),
    _(R_PN_NO_CANDIDATE, ['Idd', ':Id']));
end;

procedure TTestRdxParamNameFix.TruncatedOrEmptyList_NoHelp;
begin
  // Mehr als sechs Platzhalter: die Liste ist gekappt.
  AssertRefused(Std(Call('Nmae')), CALL_LINE,
    Msg('Q', 'Nmae', ':a, :b, :c, :d, :e, :Name, ...'), _(R_PN_TRUNCATED));
  AssertRefused(Std(Call('Nmae')), CALL_LINE,
    'Q.ParamByName(''Nmae''): the SQL this routine assigns to Q has no '
    + ':Nmae (it has no named placeholders) - raises "parameter not found" '
    + 'at run time', _(R_PN_NO_PLACEHOLDERS));
end;

procedure TTestRdxParamNameFix.OtherDirectionOrForm_NoHelp;
begin
  // Fund (b): der Platzhalter ohne Zuweisung - kein Wert bekannt.
  AssertRefused(Std(Call('Nmae')), CALL_LINE - 1,
    'Q.SQL uses :Name, but this routine sets other parameters of Q and '
    + 'never this one - execution fails with an unbound parameter or binds '
    + 'NULL. Assign it with ParamByName(''Name'')', _(R_PN_NOT_UNKNOWN));
  AssertRefused(Std(Call('Nmae')), CALL_LINE, 'x', _(R_PN_NOT_UNKNOWN));
  // Andere Form: Schluss anders, Listeneintrag ohne ':'.
  AssertRefused(Std(Call('Nmae')), CALL_LINE,
    Msg('Q', 'Nmae', LIST_STD) + '!', _(R_PN_MESSAGE));
  AssertRefused(Std(Call('Nmae')), CALL_LINE, Msg('Q', 'Nmae', 'Name'),
    _(R_PN_MESSAGE));
end;

procedure TTestRdxParamNameFix.NameAlreadySet_NoHelp;
begin
  // Die Routine setzt :Name schon - ein zweiter Zugriff ueberschriebe ihn.
  AssertRefused(Wrap([SQL_CLEAR, SQL_ADD, Call('Nmae'), SET_ID,
    '  Q.ParamByName(''Name'').AsString := ''y'';', OPEN_Q]), CALL_LINE,
    Msg('Q', 'Nmae', LIST_STD), _(R_PN_USED, ['Name']));
  AssertRefused(Wrap([SQL_CLEAR, SQL_ADD, Call('Nmae'),
    '  Q.ParamValues[''Id;name''] := VarArrayOf([1, ''y'']);', OPEN_Q]),
    CALL_LINE, Msg('Q', 'Nmae', LIST_STD), _(R_PN_USED, ['Name']));
  AssertRefused(Wrap([SQL_CLEAR, SQL_ADD, Call('Nmae'), SET_ID,
    '  if Q.FindParam(''name'') = nil then Exit;', OPEN_Q]), CALL_LINE,
    Msg('Q', 'Nmae', LIST_STD), _(R_PN_USED, ['Name']));
end;

procedure TTestRdxParamNameFix.MovedLineOrQuery_NoHelp;
begin
  // Die Zeile danach setzt 'Id', nicht 'Nmae'.
  AssertRefused(Std(Call('Nmae')), CALL_LINE + 1, Msg('Q', 'Nmae', LIST_STD),
    MsgMovedSuffix(_(R_PN_MOVED, ['Q', 'Nmae'])));
  AssertRefused(Std(Call('Nmae')), 99, Msg('Q', 'Nmae', LIST_STD),
    MsgMovedSuffix(_(R_PN_MOVED, ['Q', 'Nmae'])));
  // Die Meldung nennt eine andere Query.
  AssertRefused(Std(Call('Nmae')), CALL_LINE, Msg('Q2', 'Nmae', LIST_STD),
    MsgMovedSuffix(_(R_PN_MOVED, ['Q2', 'Nmae'])));
end;

procedure TTestRdxParamNameFix.CommentOrString_NoHelp;
begin
  AssertRefused(Std('  // Q.ParamByName(''Nmae'').AsString := ''x'';'),
    CALL_LINE, Msg('Q', 'Nmae', LIST_STD),
    MsgMovedSuffix(_(R_PN_MOVED, ['Q', 'Nmae'])));
  AssertRefused(Std('  S := ''Q.ParamByName(''''Nmae'''')'';'), CALL_LINE,
    Msg('Q', 'Nmae', LIST_STD), MsgMovedSuffix(_(R_PN_MOVED, ['Q', 'Nmae'])));
end;

procedure TTestRdxParamNameFix.NotPlainLiteral_NoHelp;
begin
  // Der Name ist kein einfaches Literal als ganzes Argument.
  AssertRefused(Std('  Q.ParamByName(''Nm'' + ''ae'').AsString := ''x'';'),
    CALL_LINE, Msg('Q', 'Nmae', LIST_STD),
    MsgMovedSuffix(_(R_PN_MOVED, ['Q', 'Nmae'])));
  AssertRefused(Std('  Q.ParamByName(''Nm''#97''e'').AsString := ''x'';'),
    CALL_LINE, Msg('Q', 'Nmae', LIST_STD),
    MsgMovedSuffix(_(R_PN_MOVED, ['Q', 'Nmae'])));
end;

procedure TTestRdxParamNameFix.TwiceOnLine_NoHelp;
begin
  AssertRefused(Std('  Q.ParamByName(''Nmae'').AsString := '
    + 'Q.ParamByName(''Nmae'').AsString;'), CALL_LINE,
    Msg('Q', 'Nmae', LIST_STD), _(R_PN_TWICE, ['Nmae']));
end;

procedure TTestRdxParamNameFix.NoRoutine_NoHelp;
begin
  // Der Aufruf steht im initialization-Abschnitt (Zeile 7).
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'initialization', SQL_CLEAR, SQL_ADD, Call('Nmae'), 'end.']), 7,
    Msg('Q', 'Nmae', LIST_STD), _(R_PN_NO_ROUTINE));
end;

procedure TTestRdxParamNameFix.CastOrIndex_NoHelp;
begin
  // Hinter einem Cast oder Index meldet der Detektor nie; die Kette passt
  // dann zu keiner Query.
  AssertRefused(Std('  TFDQuery(X).ParamByName(''Nmae'').AsString := ''x'';'),
    CALL_LINE, Msg('X', 'Nmae', LIST_STD),
    MsgMovedSuffix(_(R_PN_MOVED, ['X', 'Nmae'])));
  AssertRefused(Std('  Qs[0].ParamByName(''Nmae'').AsString := ''x'';'),
    CALL_LINE, Msg('Qs', 'Nmae', LIST_STD),
    MsgMovedSuffix(_(R_PN_MOVED, ['Qs', 'Nmae'])));
end;

{$IFNDEF FPC}

{ ---- Detektor ---- }

// Die Funde der Art SCA199 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TParamNameMismatchDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_pnm_', ASource, fkParamNameMismatch,
    RunDetector);
end;

// Ist S ein Fund (a) - ParamByName mit unbekanntem Namen?
function IsUnknown(const S: TSeen): Boolean;
begin
  Result := Pos('''): the SQL this routine assigns to ', S.Msg) > 0;
end;

// Die Hilfe fuer den Fund S ueber MapFix - so ruft sie der Adapter der
// Tabelle.
function PlanSeen(const ASource: string; const S: TSeen): TRdxFixOutcome;
var
  SL : TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Result := MapFix(SL, S.Line, S.Msg, TRdxParamNameFix.UsePlaceholder);
  finally
    SL.Free;
  end;
end;

// Die Hilfe fuer den ersten Fund (a).
function PlanFirst(const ASource: string; out ASeen: TSeen): TRdxFixOutcome;
var
  S : TSeen;
begin
  for S in Detect(ASource) do
    if IsUnknown(S) then
    begin
      ASeen := S;
      Exit(PlanSeen(ASource, S));
    end;
  Assert.Fail('der Detektor meldet keinen Fund (a)');
  Result := Default(TRdxFixOutcome);
end;

// Fund (a) fuer Fund (a), nach jeder Ersetzung neu gemeldet, bis keiner
// mehr kommt.
function FixAll(const ASource: string): string;
const
  MAX_PASSES = 10;
var
  Pass  : Integer;
  O     : TRdxFixOutcome;
  S     : TSeen;
  Found : Boolean;
begin
  Result := ASource;
  for Pass := 1 to MAX_PASSES do
  begin
    Found := False;
    for S in Detect(Result) do
      Found := Found or IsUnknown(S);
    if not Found then
      Exit;
    O := PlanFirst(Result, S);
    Assert.IsTrue(O.Enabled, O.Reason);
    Result := Apply(Result, O.Edits);
  end;
  Assert.Fail('der Detektor meldet auch nach zehn Durchlaeufen Funde (a)');
end;

procedure TTestRdxParamNameDetector.Detector_ReportsUnknownWithList;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(Std(Call('Nmae')));
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund (a), kein (b)');
  Assert.AreEqual<Integer>(CALL_LINE, Seen[0].Line, 'Zeile des Literals');
  Assert.AreEqual(Msg('Q', 'Nmae', LIST_STD), Seen[0].Msg);
end;

procedure TTestRdxParamNameDetector.Detector_RoundTrip;
var
  Fixed : string;
begin
  Fixed := FixAll(Std(Call('Nmae')));
  Assert.AreEqual(Std(Call('Name')), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxParamNameDetector.Detector_CreatedQuery_BothDirectionsGone;
var
  Src, Fixed : string;
  Seen       : TArray<TSeen>;
  O          : TRdxFixOutcome;
begin
  // Eine hier erzeugte Query: (b) fuer :Name (Zeile 9) und (a) fuer 'Nmae'
  // (Zeile 10). Die Hilfe gibt es nur fuer (a); danach schweigen beide.
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure Load;',
    'var', '  Q: TFDQuery;', 'begin', '  Q := TFDQuery.Create(nil);',
    SQL_ADD, Call('Nmae'), SET_ID, OPEN_Q, 'end;', 'end.']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(2, Length(Seen), 'zwei Funde');
  Assert.AreEqual<Integer>(9, Seen[0].Line, '(b) auf der SQL-Zeile');
  O := PlanSeen(Src, Seen[0]);
  Assert.IsFalse(O.Enabled, 'keine Hilfe fuer (b)');
  Assert.AreEqual(_(R_PN_NOT_UNKNOWN), O.Reason);
  Assert.AreEqual<Integer>(10, Seen[1].Line, '(a) auf der Aufrufzeile');
  O := PlanSeen(Src, Seen[1]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Fixed := Apply(Src, O.Edits);
  Assert.AreEqual(StringReplace(Src, '''Nmae''', '''Name''', []), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)), 'beide Funde weg');
end;

procedure TTestRdxParamNameDetector.Detector_CatalogExample_NoHelp;
var
  Meta : TRuleMeta;
  Src  : string;
  S    : TSeen;
  O    : TRdxFixOutcome;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkParamNameMismatch);
  Assert.IsTrue(Pos('custid', Meta.BadExample) > 0, Meta.BadExample);
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure Load;',
    'var', '  Q: TFDQuery;', '  Id: Integer;', 'begin',
    CatalogText(Meta.BadExample), 'end;', 'end.']);
  O := PlanFirst(Src, S);
  Assert.IsFalse(O.Enabled, 'custid -> customer_id ist kein Tippfehler');
  Assert.AreEqual(_(R_PN_NO_CANDIDATE, ['custid', ':customer_id']), O.Reason);
end;

procedure TTestRdxParamNameDetector.Detector_MapFix_OneEdit;
var
  S : TSeen;
  O : TRdxFixOutcome;
begin
  O := PlanFirst(Std(Call('Nmae')), S);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(1, Length(O.Edits), 'eine Ersetzung');
  Assert.AreEqual('Nmae', O.Edits[0].Expected);
  Assert.AreEqual('Name', O.Edits[0].NewText);
  // Die Kennzeichnung (Changes: True) und den Namen im Menuetext setzt der
  // Adapter bzw. die Tabellenzeile - MapFix laesst beide auf dem Default.
  Assert.IsFalse(O.ChangesBehavior);
  Assert.AreEqual('', O.Name);
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxParamNameFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxParamNameDetector);
  {$ENDIF}

end.

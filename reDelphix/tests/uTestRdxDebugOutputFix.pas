unit uTestRdxDebugOutputFix;

// Editorhilfe SCA017 DebugOutput (uRdxDebugOutputFix): der Planer auf Text
// (erste Fixture, FPC-tauglich) und der ECHTE Detektor (uDebugOutput) auf
// dem echten AST mit MapFix wie der Adapter der Tabelle (zweite Fixture,
// nur Delphi). Die Fixtures stehen in einer Routine 'Foo', deren Rumpf auf
// Zeile 5 beginnt; seine erste Anweisung steht auf Zeile 6 (BODY).
// WrapInDebug ist der erste Eintrag ('{$IFDEF DEBUG}'), DeleteCall der
// zweite (loeschen).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxDebugOutputFix = class
  public
    // ---- Umformung ----
    [Test] procedure WriteLn_WrapsInDebug;
    [Test] procedure WriteLn_DeleteRemovesLine;
    [Test] procedure MultiLineCall_WholeStatement;
    [Test] procedure SystemQualified_Wraps;
    [Test] procedure OtherNames_CaseInsensitive;
    [Test] procedure ListPositions_Wrap;
    [Test] procedure TabIndent_Kept;
    [Test] procedure OnlyStatement_WrapButNoDelete;
    [Test] procedure EndOfFile_WrapButNoDelete;
    // ---- Gegenproben ----
    [Test] procedure Branch_NoHelp;
    [Test] procedure SharedLine_NoHelp;
    [Test] procedure TwoCalls_NoHelp;
    [Test] procedure CommentOrString_NoHelp;
    [Test] procedure CommentOnLines_NoHelp;
    [Test] procedure Directive_NoHelp;
    [Test] procedure UnderDebugCondition_NoHelp;
    [Test] procedure MovedOrNoName_NoHelp;
    [Test] procedure MemberCall_NoHelp;
    [Test] procedure NoSemicolon_NoHelp;
    [Test] procedure InsideExpression_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxDebugOutputDetector = class
  public
    [Test] procedure Detector_ReportsCallLineAndName;
    [Test] procedure Detector_RoundTripWrap;
    [Test] procedure Detector_RoundTripDelete;
    [Test] procedure Detector_CatalogExample_Wrapped;
    [Test] procedure Detector_MultiLineCall_Deleted;
    [Test] procedure Detector_BranchFinding_NoHelp;
    [Test] procedure Detector_AnonymousMethod_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uDebugOutput,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixRunner,         // MapFix (wie der Adapter der Tabelle)
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxDebugOutputFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply

const
  BODY = 6;   // erste Rumpfzeile von Wrap

// ---- Helfer ----

// Eine Unit mit EINER Routine Foo; Rumpf ab Zeile 6.
function Wrap(const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    'begin']) + #13#10 + Join(ABody) + #13#10 + Join(['end;', 'end.']);
end;

// Die Meldung des Detektors zum Namen AName (klein).
function Msg(const AName: string): string;
begin
  Result := 'Debug output: ' + AName;
end;

// Der Planer (ADelete: zweiter Eintrag) fuer Zeile ALine: der neue Text,
// oder '' bei Ablehnung (AReason).
function PlanWith(const ASource: string; ALine: Integer;
  const AMessage: string; ADelete: Boolean; out AReason: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
  Ok  : Boolean;
begin
  Result := '';
  AReason := '';
  Ok := False;
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    try
      if ADelete then
        Ok := TRdxDebugOutputFix.DeleteCall(Map, ALine, AMessage, E, AReason)
      else
        Ok := TRdxDebugOutputFix.WrapInDebug(Map, ALine, AMessage, E,
          AReason);
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
  if Ok then
    Result := Apply(ASource, E);
end;

// Die Hilfe muss gelten (sonst scheitert der Test mit dem Grund).
function Wrapped(const ASource: string; ALine: Integer;
  const AName: string): string;
var
  R : string;
begin
  Result := PlanWith(ASource, ALine, Msg(AName), False, R);
  Assert.IsTrue(Result <> '', R);
end;

function Deleted(const ASource: string; ALine: Integer;
  const AName: string): string;
var
  R : string;
begin
  Result := PlanWith(ASource, ALine, Msg(AName), True, R);
  Assert.IsTrue(Result <> '', R);
end;

// Beide Eintraege muessen mit AReason ablehnen.
procedure AssertRefused(const ASource: string; ALine: Integer;
  const AName, AReason: string);
var
  R : string;
begin
  Assert.AreEqual('', PlanWith(ASource, ALine, Msg(AName), False, R),
    'keine Hilfe (einklammern)');
  Assert.AreEqual(AReason, R, 'Grund (einklammern)');
  Assert.AreEqual('', PlanWith(ASource, ALine, Msg(AName), True, R),
    'keine Hilfe (loeschen)');
  Assert.AreEqual(AReason, R, 'Grund (loeschen)');
end;

// ---- Umformung ----

procedure TTestRdxDebugOutputFix.WriteLn_WrapsInDebug;
begin
  Assert.AreEqual(
    Wrap(['  Foo;', '  {$IFDEF DEBUG}', '  WriteLn(''here #3'');',
      '  {$ENDIF}', '  Bar;']),
    Wrapped(Wrap(['  Foo;', '  WriteLn(''here #3'');', '  Bar;']), BODY + 1,
      'writeln'));
end;

procedure TTestRdxDebugOutputFix.WriteLn_DeleteRemovesLine;
begin
  Assert.AreEqual(Wrap(['  Foo;', '  Bar;']),
    Deleted(Wrap(['  Foo;', '  WriteLn(''here #3'');', '  Bar;']), BODY + 1,
      'writeln'));
  // Die letzte Anweisung vor end (davor ';'): kein leerer Block.
  Assert.AreEqual(Wrap(['  Foo;']),
    Deleted(Wrap(['  Foo;', '  WriteLn(1);']), BODY + 1, 'writeln'));
end;

procedure TTestRdxDebugOutputFix.MultiLineCall_WholeStatement;
var
  Src : string;
begin
  // Die Anweisung reicht bis zu ihrem ';' auf der Folgezeile.
  Src := Wrap(['  Foo;', '  ShowMessage(Format(''%d of %d'',', '    [A, B]));',
    '  Bar;']);
  Assert.AreEqual(
    Wrap(['  Foo;', '  {$IFDEF DEBUG}', '  ShowMessage(Format(''%d of %d'',',
      '    [A, B]));', '  {$ENDIF}', '  Bar;']),
    Wrapped(Src, BODY + 1, 'showmessage'));
  Assert.AreEqual(Wrap(['  Foo;', '  Bar;']),
    Deleted(Src, BODY + 1, 'showmessage'));
end;

procedure TTestRdxDebugOutputFix.SystemQualified_Wraps;
begin
  // 'System.' gehoert zur Anweisung (der Detektor meldet es ausdruecklich).
  Assert.AreEqual(
    Wrap(['  Foo;', '  {$IFDEF DEBUG}', '  System.WriteLn(''x'');',
      '  {$ENDIF}']),
    Wrapped(Wrap(['  Foo;', '  System.WriteLn(''x'');']), BODY + 1,
      'writeln'));
  Assert.AreEqual(Wrap(['  Foo;']),
    Deleted(Wrap(['  Foo;', '  System.WriteLn(''x'');']), BODY + 1,
      'writeln'));
end;

procedure TTestRdxDebugOutputFix.OtherNames_CaseInsensitive;
var
  Src, R : string;
begin
  Src := Wrap(['  Foo;', '  OUTPUTDEBUGSTRING(PChar(S));',
    '  ShowMessagePos(''x'', 10, 10);', '  Bar;']);
  Assert.AreEqual(
    Wrap(['  Foo;', '  ShowMessagePos(''x'', 10, 10);', '  Bar;']),
    Deleted(Src, BODY + 1, 'outputdebugstring'));
  Assert.AreEqual(
    Wrap(['  Foo;', '  OUTPUTDEBUGSTRING(PChar(S));', '  {$IFDEF DEBUG}',
      '  ShowMessagePos(''x'', 10, 10);', '  {$ENDIF}', '  Bar;']),
    Wrapped(Src, BODY + 2, 'showmessagepos'));
  // 'showmessage' ist nicht 'ShowMessagePos' - ganze Woerter.
  Assert.AreEqual('', PlanWith(Src, BODY + 2, Msg('showmessage'), False, R));
  Assert.AreEqual(MsgMovedSuffix(_(R_DBG_MOVED, ['showmessage'])), R);
end;

procedure TTestRdxDebugOutputFix.ListPositions_Wrap;
var
  Src : string;
begin
  // Hinter try, finally und repeat steht eine Anweisungsliste.
  Src := Wrap(['  try', '    WriteLn(1);', '  finally', '    WriteLn(2);',
    '  end;', '  repeat', '    WriteLn(3);', '  until A;']);
  Assert.AreEqual(
    Wrap(['  try', '    {$IFDEF DEBUG}', '    WriteLn(1);', '    {$ENDIF}',
      '  finally', '    WriteLn(2);', '  end;', '  repeat', '    WriteLn(3);',
      '  until A;']),
    Wrapped(Src, BODY + 1, 'writeln'));
  Assert.AreEqual(
    Wrap(['  try', '    WriteLn(1);', '  finally', '    {$IFDEF DEBUG}',
      '    WriteLn(2);', '    {$ENDIF}', '  end;', '  repeat', '    WriteLn(3);',
      '  until A;']),
    Wrapped(Src, BODY + 3, 'writeln'));
  Assert.AreEqual(
    Wrap(['  try', '    WriteLn(1);', '  finally', '    WriteLn(2);',
      '  end;', '  repeat', '    {$IFDEF DEBUG}', '    WriteLn(3);',
      '    {$ENDIF}', '  until A;']),
    Wrapped(Src, BODY + 6, 'writeln'));
end;

procedure TTestRdxDebugOutputFix.TabIndent_Kept;
begin
  // Die Direktiven bekommen die Einrueckung der Anweisung (hier Tabs).
  Assert.AreEqual(
    Wrap(['  if A then', '  begin', '    Foo;', #9#9'{$IFDEF DEBUG}',
      #9#9'WriteLn(1);', #9#9'{$ENDIF}', '  end;']),
    Wrapped(Wrap(['  if A then', '  begin', '    Foo;', #9#9'WriteLn(1);',
      '  end;']), BODY + 3, 'writeln'));
end;

procedure TTestRdxDebugOutputFix.OnlyStatement_WrapButNoDelete;
var
  Src, R : string;
begin
  // Einziger Inhalt eines Blocks: einklammern laesst den Block im
  // Quelltext stehen, loeschen liesse ihn leer (SCA077).
  Src := Wrap(['  if A then', '  begin', '    ShowMessage(''x'');', '  end;']);
  Assert.AreEqual(
    Wrap(['  if A then', '  begin', '    {$IFDEF DEBUG}',
      '    ShowMessage(''x'');', '    {$ENDIF}', '  end;']),
    Wrapped(Src, BODY + 2, 'showmessage'));
  Assert.AreEqual('', PlanWith(Src, BODY + 2, Msg('showmessage'), True, R));
  Assert.AreEqual(MsgOnlyStatementEmptyBlock('begin'), R);
  Assert.AreEqual('', PlanWith(Wrap(['  repeat', '    WriteLn(1);',
    '  until A;']), BODY + 1, Msg('writeln'), True, R));
  Assert.AreEqual(MsgOnlyStatementEmptyBlock('repeat'), R);
end;

procedure TTestRdxDebugOutputFix.EndOfFile_WrapButNoDelete;
var
  Src, R : string;
begin
  // Die Anweisung steht auf der letzten Zeile der Datei (ohne end.).
  Src := Join(['program p;', 'begin', '  Foo;', '  WriteLn(1);']);
  Assert.AreEqual(
    Join(['program p;', 'begin', '  Foo;', '  {$IFDEF DEBUG}', '  WriteLn(1);',
      '  {$ENDIF}']),
    Wrapped(Src, 4, 'writeln'));
  Assert.AreEqual('', PlanWith(Src, 4, Msg('writeln'), True, R));
  Assert.AreEqual(_(R_DBG_LAST_LINE), R);
end;

// ---- Gegenproben ----

procedure TTestRdxDebugOutputFix.Branch_NoHelp;
begin
  // Einzige Anweisung eines Zweigs: im Release bzw. geloescht bindete die
  // naechste Anweisung an den Zweig.
  AssertRefused(Wrap(['  if A then', '    WriteLn(''x'');', '  Bar;']),
    BODY + 1, 'writeln', _(R_DBG_BRANCH, ['then']));
  AssertRefused(Wrap(['  if A then Foo else WriteLn(''x'');', '  Bar;']),
    BODY, 'writeln', _(R_DBG_BRANCH, ['else']));
  AssertRefused(Wrap(['  for I := 1 to 3 do', '    WriteLn(I);']), BODY + 1,
    'writeln', _(R_DBG_BRANCH, ['do']));
  AssertRefused(Wrap(['  case A of', '    1: WriteLn(''x'');', '  end;']),
    BODY + 1, 'writeln', _(R_DBG_BRANCH, [':']));
end;

procedure TTestRdxDebugOutputFix.SharedLine_NoHelp;
begin
  AssertRefused(Wrap(['  Foo; WriteLn(''x'');']), BODY, 'writeln',
    _(R_DBG_SHARED));
  AssertRefused(Wrap(['  WriteLn(''x''); Foo;']), BODY, 'writeln',
    _(R_DBG_SHARED));
  // Die anonyme Methode steht im Argument eines anderen Aufrufs.
  AssertRefused(Wrap(['  Run(procedure begin WriteLn(''x''); end);']), BODY,
    'writeln', _(R_DBG_SHARED));
end;

procedure TTestRdxDebugOutputFix.TwoCalls_NoHelp;
begin
  AssertRefused(Wrap(['  WriteLn(1); WriteLn(2);']), BODY, 'writeln',
    _(R_DBG_MANY, ['writeln']));
end;

procedure TTestRdxDebugOutputFix.CommentOrString_NoHelp;
begin
  // Kommentar und String sind nie Code.
  AssertRefused(Wrap(['  // WriteLn(''x'');', '  Foo;']), BODY, 'writeln',
    MsgMovedSuffix(_(R_DBG_MOVED, ['writeln'])));
  AssertRefused(Wrap(['  { WriteLn(x); }', '  Foo;']), BODY, 'writeln',
    MsgMovedSuffix(_(R_DBG_MOVED, ['writeln'])));
  AssertRefused(Wrap(['  S := ''WriteLn(x);'';']), BODY, 'writeln',
    MsgMovedSuffix(_(R_DBG_MOVED, ['writeln'])));
  // Die Zeile beginnt in einem Block-Kommentar.
  AssertRefused(Wrap(['  {', '  WriteLn(''x'');', '  }', '  Foo;']), BODY + 1,
    'writeln', MsgLineStartsInCommentOrString);
end;

procedure TTestRdxDebugOutputFix.CommentOnLines_NoHelp;
begin
  // Ein Kommentar erklaert die Ausgabe vielleicht.
  AssertRefused(Wrap(['  Foo;', '  WriteLn(''x''); // Kontrolle']), BODY + 1,
    'writeln', _(R_DBG_COMMENT));
  AssertRefused(Wrap(['  Foo;', '  ShowMessage(A + { Teil }', '    B);']),
    BODY + 1, 'showmessage', _(R_DBG_COMMENT));
end;

procedure TTestRdxDebugOutputFix.Directive_NoHelp;
begin
  // Auf der Zeile; ein Bedingungsblock, der davor oeffnet bzw. dahinter
  // schliesst (Leerzeilen zaehlen nicht).
  AssertRefused(Wrap(['  Foo;', '  WriteLn(''x''); {$IFDEF X}{$ENDIF}']),
    BODY + 1, 'writeln', _(R_DBG_DIRECTIVE));
  AssertRefused(Wrap(['  {$IFDEF MSWINDOWS}', '  OutputDebugString(''x'');',
    '  {$ENDIF}']), BODY + 1, 'outputdebugstring', _(R_DBG_AROUND));
  AssertRefused(Wrap(['  {$IFDEF X}', '  Foo;', '', '  WriteLn(''x'');', '',
    '  {$ENDIF}']), BODY + 3, 'writeln', _(R_DBG_AROUND));
  // Gegenprobe: '{$R+}' davor und '{$ENDIF}' eines anderen Blocks davor
  // umschliessen die Anweisung nicht.
  Assert.AreEqual(
    Wrap(['  {$R+}', '  {$IFDEF DEBUG}', '  WriteLn(1);', '  {$ENDIF}']),
    Wrapped(Wrap(['  {$R+}', '  WriteLn(1);']), BODY + 1, 'writeln'));
  Assert.AreEqual(
    Wrap(['  {$IFDEF X}', '  Foo;', '  {$ENDIF}', '  {$IFDEF DEBUG}',
      '  WriteLn(1);', '  {$ENDIF}']),
    Wrapped(Wrap(['  {$IFDEF X}', '  Foo;', '  {$ENDIF}', '  WriteLn(1);']),
      BODY + 3, 'writeln'));
end;

procedure TTestRdxDebugOutputFix.UnderDebugCondition_NoHelp;
var
  Src : string;
begin
  // Ein offener Block, der DEBUG nennt - auch weit weg und im ELSE-Zweig.
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    '{$IFNDEF DEBUG}', 'procedure Foo;', 'begin', '  Foo;', '  WriteLn(''x'');',
    '  Bar;', 'end;', '{$ENDIF}', 'end.']), 8, 'writeln',
    _(R_DBG_UNDER_DEBUG));
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    '{$IFDEF DEBUG}', 'procedure Bar;', 'begin', 'end;', '{$ELSE}',
    'procedure Foo;', 'begin', '  Foo;', '  WriteLn(''x'');', '  Bar;', 'end;',
    '{$ENDIF}', 'end.']), 12, 'writeln', _(R_DBG_UNDER_DEBUG));
  // Gegenprobe: ein geschlossener DEBUG-Block davor und ein anderer offener
  // Block sperren nicht.
  Src := Join(['unit t;', 'interface', 'implementation', '{$IFDEF DEBUG}',
    'procedure Bar;', 'begin', 'end;', '{$ENDIF}', '{$IFDEF MSWINDOWS}',
    'procedure Foo;', 'begin', '  Foo;', '  WriteLn(''x'');', '  Bar;', 'end;',
    '{$ENDIF}', 'end.']);
  Assert.AreEqual(StringReplace(Src, '  WriteLn(''x'');',
    '  {$IFDEF DEBUG}'#13#10'  WriteLn(''x'');'#13#10'  {$ENDIF}', []),
    Wrapped(Src, 13, 'writeln'));
end;

procedure TTestRdxDebugOutputFix.MovedOrNoName_NoHelp;
var
  Src, R : string;
begin
  Src := Wrap(['  Foo;', '  WriteLn(''x'');']);
  AssertRefused(Src, BODY, 'writeln',
    MsgMovedSuffix(_(R_DBG_MOVED, ['writeln'])));
  AssertRefused(Src, 99, 'writeln',
    MsgMovedSuffix(_(R_DBG_MOVED, ['writeln'])));
  AssertRefused(Src, 0, 'writeln',
    MsgMovedSuffix(_(R_DBG_MOVED, ['writeln'])));
  AssertRefused(Src, BODY + 1, 'showmessage',
    MsgMovedSuffix(_(R_DBG_MOVED, ['showmessage'])));
  // Ohne Namen in der Meldung.
  Assert.AreEqual('', PlanWith(Src, BODY + 1, 'Debug output', False, R));
  Assert.AreEqual(_(R_DBG_NO_NAME), R);
  Assert.AreEqual('writeln',
    TRdxDebugOutputFix.CallNameOf('Debug output: writeln'));
end;

procedure TTestRdxDebugOutputFix.MemberCall_NoHelp;
begin
  // Eine eigene Methode (der Detektor meldet sie nicht) und eine Adresse.
  AssertRefused(Wrap(['  Log.WriteLn(''x'');']), BODY, 'writeln',
    MsgMovedSuffix(_(R_DBG_MOVED, ['writeln'])));
  AssertRefused(Wrap(['  P := @WriteLn;']), BODY, 'writeln',
    MsgMovedSuffix(_(R_DBG_MOVED, ['writeln'])));
end;

procedure TTestRdxDebugOutputFix.NoSemicolon_NoHelp;
begin
  // Letzte Anweisung vor end ohne ';' und eine Klammer, die nie schliesst.
  AssertRefused(Wrap(['  Foo;', '  WriteLn(''x'')']), BODY + 1, 'writeln',
    _(R_DBG_NO_SEMI));
  AssertRefused(Wrap(['  Foo;', '  WriteLn(''x'';']), BODY + 1, 'writeln',
    MsgStatementEndNotFound);
end;

procedure TTestRdxDebugOutputFix.InsideExpression_NoHelp;
begin
  AssertRefused(Wrap(['  X := 1 +', '    WriteLn(1);']), BODY + 1, 'writeln',
    MsgUnclearStatementOwner('+'));
end;

{$IFNDEF FPC}

{ ---- Detektor ---- }

// Die Funde der Art SCA017 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TDebugOutputDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_dbg_', ASource, fkDebugOutput, RunDetector);
end;

// Die Hilfe fuer den ersten Fund des Detektors ueber MapFix - so ruft sie
// der Adapter der Tabelle.
function PlanFirst(const ASource: string; ADelete: Boolean;
  out ASeen: TSeen): TRdxFixOutcome;
var
  Seen : TArray<TSeen>;
  SL   : TStringList;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet einen Fund');
  ASeen := Seen[0];
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    if ADelete then
      Result := MapFix(SL, ASeen.Line, ASeen.Msg, TRdxDebugOutputFix.DeleteCall)
    else
      Result := MapFix(SL, ASeen.Line, ASeen.Msg,
        TRdxDebugOutputFix.WrapInDebug);
  finally
    SL.Free;
  end;
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt.
function FixAll(const ASource: string; ADelete: Boolean): string;
const
  MAX_PASSES = 10;
var
  Pass : Integer;
  O    : TRdxFixOutcome;
  S    : TSeen;
begin
  Result := ASource;
  for Pass := 1 to MAX_PASSES do
  begin
    if Length(Detect(Result)) = 0 then
      Exit;
    O := PlanFirst(Result, ADelete, S);
    Assert.IsTrue(O.Enabled, O.Reason);
    Result := Apply(Result, O.Edits);
  end;
  Assert.Fail('der Detektor schweigt auch nach zehn Durchlaeufen nicht');
end;

procedure TTestRdxDebugOutputDetector.Detector_ReportsCallLineAndName;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(Wrap(['  Foo;', '  WriteLn(''here #3'');', '  Bar;']));
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(BODY + 1, Seen[0].Line, 'Zeile des Aufrufs');
  Assert.AreEqual('Debug output: writeln', Seen[0].Msg);
  Assert.AreEqual('writeln', TRdxDebugOutputFix.CallNameOf(Seen[0].Msg));
end;

procedure TTestRdxDebugOutputDetector.Detector_RoundTripWrap;
var
  Src, Fixed : string;
begin
  Src := Wrap(['  Foo;', '  WriteLn(''here #3'');', '  ShowMessage(''x'');',
    '  Bar;']);
  Assert.AreEqual<Integer>(2, Length(Detect(Src)), 'zwei Funde');
  Fixed := FixAll(Src, False);
  Assert.AreEqual(Wrap(['  Foo;', '  {$IFDEF DEBUG}', '  WriteLn(''here #3'');',
    '  {$ENDIF}', '  {$IFDEF DEBUG}', '  ShowMessage(''x'');', '  {$ENDIF}',
    '  Bar;']), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxDebugOutputDetector.Detector_RoundTripDelete;
var
  Src, Fixed : string;
begin
  Src := Wrap(['  Foo;', '  WriteLn(''here #3'');', '  OutputDebugString(''x'');',
    '  Bar;']);
  Assert.AreEqual<Integer>(2, Length(Detect(Src)), 'zwei Funde');
  Fixed := FixAll(Src, True);
  Assert.AreEqual(Wrap(['  Foo;', '  Bar;']), Fixed);
end;

procedure TTestRdxDebugOutputDetector.Detector_CatalogExample_Wrapped;
var
  Meta : TRuleMeta;
  Src  : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkDebugOutput);
  Assert.IsTrue(Pos('WriteLn', Meta.BadExample) > 0, Meta.BadExample);
  Src := Wrap(['  Foo;', '  ' + CatalogText(Meta.BadExample), '  Bar;']);
  Assert.AreEqual<Integer>(1, Length(Detect(Src)),
    'der Detektor meldet das Beispiel');
  Assert.AreEqual(Wrap(['  Foo;', '  {$IFDEF DEBUG}',
    '  ' + CatalogText(Meta.BadExample), '  {$ENDIF}', '  Bar;']),
    FixAll(Src, False));
end;

procedure TTestRdxDebugOutputDetector.Detector_MultiLineCall_Deleted;
var
  Src  : string;
  Seen : TArray<TSeen>;
begin
  Src := Wrap(['  Foo;', '  ShowMessage(Format(''%d of %d'',', '    [A, B]));',
    '  Bar;']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(BODY + 1, Seen[0].Line, 'Zeile des Aufrufs');
  Assert.AreEqual(Wrap(['  Foo;', '  Bar;']), FixAll(Src, True));
end;

procedure TTestRdxDebugOutputDetector.Detector_BranchFinding_NoHelp;
var
  S : TSeen;
  O : TRdxFixOutcome;
begin
  // Der Detektor meldet auch die einzige Anweisung eines Zweigs.
  O := PlanFirst(Wrap(['  if A then', '    WriteLn(''x'');', '  Bar;']),
    False, S);
  Assert.AreEqual<Integer>(BODY + 1, S.Line, 'Zeile des Aufrufs');
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_DBG_BRANCH, ['then']), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

procedure TTestRdxDebugOutputDetector.Detector_AnonymousMethod_NoHelp;
var
  S : TSeen;
  O : TRdxFixOutcome;
begin
  // Rechts in einer Zuweisung meldet der Detektor die Zeile der Zuweisung
  // (nkAssign); die Hilfe sieht dort mehr als den Aufruf.
  O := PlanFirst(Wrap(['  Foo;', '  P := procedure begin WriteLn(''x''); end;',
    '  Bar;']), True, S);
  Assert.AreEqual<Integer>(BODY + 1, S.Line, 'Zeile der Zuweisung');
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_DBG_SHARED), O.Reason);
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxDebugOutputFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxDebugOutputDetector);
  {$ENDIF}

end.

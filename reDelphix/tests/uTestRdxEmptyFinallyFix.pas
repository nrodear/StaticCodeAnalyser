unit uTestRdxEmptyFinallyFix;

// Editorhilfe SCA083 EmptyFinallyBlock (uRdxEmptyFinallyFix) - nur Delphi,
// reDelphix.Test: die Faelle auf Text (Planer ueber die Code-Sicht), dazu
// der echte Detektor (uEmptyFinallyBlock) mit dem Adapter PlanEmptyFinally
// und das Katalog-Beispiel. Die Unit braucht den Quellstellen-Dienst des
// Cores (Adapter) und den Detektor - sie gehoert nicht in den FPC-Pruefstand.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxEmptyFinallyFix = class
  public
    // ---- Umformung ----
    [Test] procedure Basic_Dedent;
    [Test] procedure FinallyEndOnOneLine;
    [Test] procedure Tabs_Kept;
    [Test] procedure Nested_BlocksInBody;
    [Test] procedure MissingSemicolon_AddedBeforeComment;
    [Test] procedure EndWithoutSemicolon_BeforeEnd;
    [Test] procedure FlatBody;
    // ---- Gegenproben: keine Hilfe ----
    [Test] procedure Refuse_Comment;
    [Test] procedure Refuse_NotEmpty;
    [Test] procedure Refuse_BranchWithoutBegin;
    [Test] procedure Refuse_LineProblems;
    [Test] procedure Refuse_BodyWords;
    [Test] procedure Refuse_DirectiveAndMultiLine;
    [Test] procedure Refuse_Layout;
    [Test] procedure Refuse_IndentAndEmptyBody;
    // ---- echter Detektor ----
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_CatalogExample;
    [Test] procedure Adapter_Outcome;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uEmptyFinallyBlock,
  uRdxBufferMath, uRdxCodeMap, uRdxRecipeRunner, uRdxEmptyFinallyFix,
  uTestRdxDetectorKit,   // TSeen, CatalogText, DetectSource
  uTestRdxTextKit;       // Join, Apply, LineOf

const
  // Die erste Zeile des Rumpfs in InUnit.
  BODY_LINE = 6;

// Eine Unit mit einer Routine P und den Zeilen ALines als Rumpf (ab Zeile 6).
function InUnit(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation', 'procedure P;'])
    + #13#10 + 'begin' + #13#10 + Join(ALines) + #13#10 + Join(['end;', 'end.']);
end;

// Anweisungen in einer Routine (je Zeile zwei Leerzeichen eingerueckt).
function InRoutine(const AStatements: string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', 'procedure P;',
    'var', '  Stream: TFileStream;', 'begin',
    '  ' + StringReplace(AStatements, #13#10, #13#10'  ', [rfReplaceAll]),
    'end;', 'end.']);
end;

// Der Planer an Zeile ALine: der neue Text, bei einer Ablehnung '' und der
// Grund in AReason.
function FixAt(const ASource: string; ALine: Integer;
  out AReason: string): string;
var
  SL   : TStringList;
  Map  : TRdxCodeMap;
  Edit : TRdxEdit;
begin
  Result := '';
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    try
      if TRdxEmptyFinallyFix.Unwrap(Map, ALine, '', Edit, AReason) then
        Result := Apply(ASource, Edit);
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
end;

// Dasselbe an der ersten Zeile mit 'finally'.
function Fix(const ASource: string; out AReason: string): string;
begin
  Result := FixAt(ASource, LineOf(ASource, 'finally'), AReason);
end;

procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TEmptyFinallyBlockDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_emptyfin_', ASource, fkEmptyFinallyBlock,
    RunDetector);
end;

// Fund fuer Fund ueber den Adapter, nach jeder Ersetzung neu gemeldet, bis
// der Detektor schweigt.
function FixAll(const ASource: string): string;
const
  MAX_PASSES = 10;
var
  Seen : TArray<TSeen>;
  Pass : Integer;
  SL   : TStringList;
  F    : TLeakFinding;
  O    : TRdxFixOutcome;
begin
  Result := ASource;
  for Pass := 1 to MAX_PASSES do
  begin
    Seen := Detect(Result);
    if Length(Seen) = 0 then Exit;
    SL := TStringList.Create;
    F := TLeakFinding.New('t.pas', '', Seen[0].Line, Seen[0].Msg,
      fkEmptyFinallyBlock);
    try
      SL.Text := Result;
      O := PlanEmptyFinally(nil, SL, F, nil);
      Assert.IsTrue(O.Enabled, Format('Zeile %d: %s', [Seen[0].Line, O.Reason]));
      Result := Apply(Result, O.Edits);
    finally
      F.Free;
      SL.Free;
    end;
  end;
  Assert.Fail(Format('der Detektor meldet nach %d Runden noch', [MAX_PASSES]));
end;

// ---- Umformung ----

procedure TTestRdxEmptyFinallyFix.Basic_Dedent;
var
  R : string;
begin
  Assert.AreEqual(
    InUnit(['  Obj := TFoo.Create;', '  DoWork(Obj);', '  More(Obj);',
      '  Done;']),
    Fix(InUnit(['  Obj := TFoo.Create;', '  try', '    DoWork(Obj);',
      '    More(Obj);', '  finally', '  end;', '  Done;']), R), R);
end;

procedure TTestRdxEmptyFinallyFix.FinallyEndOnOneLine;
var
  R : string;
begin
  Assert.AreEqual(InUnit(['  Work;', '  Done;']),
    Fix(InUnit(['  try', '    Work;', '  finally end;', '  Done;']), R), R);
end;

procedure TTestRdxEmptyFinallyFix.Tabs_Kept;
var
  R : string;
begin
  Assert.AreEqual(InUnit([#9'Work(1,', #9#9'2);']),
    Fix(InUnit([#9'try', #9#9'Work(1,', #9#9#9'2);', #9'finally', #9'end;']),
      R), R);
end;

procedure TTestRdxEmptyFinallyFix.Nested_BlocksInBody;
var
  R : string;
begin
  // Das leere finally ist das aeussere (Zeile BODY_LINE + 16); der Rumpf hat
  // begin, case..else und ein try..finally mit Inhalt - die Bilanz stimmt,
  // Exit bleibt, wie es war.
  Assert.AreEqual(
    InUnit(['  A;', '  if C then', '  begin', '    Exit;', '  end;',
      '  case N of', '    1: Work;', '  else', '    Other;', '  end;',
      '  try', '    Inner;', '  finally', '    Inner2;', '  end;', '  B;']),
    FixAt(InUnit(['  A;', '  try', '    if C then', '    begin', '      Exit;',
      '    end;', '    case N of', '      1: Work;', '    else',
      '      Other;', '    end;', '    try', '      Inner;', '    finally',
      '      Inner2;', '    end;', '  finally', '  end;', '  B;']),
      BODY_LINE + 16, R), R);
end;

procedure TTestRdxEmptyFinallyFix.MissingSemicolon_AddedBeforeComment;
var
  R : string;
begin
  // Das ';' hinter end gehoert nach dem Fix der letzten Anweisung.
  Assert.AreEqual(InUnit(['  Work(Obj); // note']),
    Fix(InUnit(['  try', '    Work(Obj) // note', '  finally', '  end;']),
      R), R);
end;

procedure TTestRdxEmptyFinallyFix.EndWithoutSemicolon_BeforeEnd;
var
  R : string;
begin
  // Das try ist die letzte Anweisung des Blocks: 'end' ohne ';' vor dem end.
  Assert.AreEqual(
    InUnit(['  if C then', '  begin', '    A;', '  end;']),
    Fix(InUnit(['  if C then', '  begin', '    try', '      A;', '    finally',
      '    end', '  end;']), R), R);
end;

procedure TTestRdxEmptyFinallyFix.FlatBody;
var
  R : string;
begin
  // Rumpf auf der Ebene des try: nichts auszuruecken.
  Assert.AreEqual(InUnit(['  Work;']),
    Fix(InUnit(['  try', '  Work;', '  finally', '  end;']), R), R);
end;

// ---- Gegenproben ----

procedure TTestRdxEmptyFinallyFix.Refuse_Comment;
var
  R : string;
begin
  // Ein Kommentar im finally ist Absicht - der Detektor sieht ihn nicht und
  // meldet trotzdem.
  Assert.AreEqual('', Fix(InUnit(['  try', '    Work;', '  finally',
    '    // TODO: free', '  end;']), R));
  Assert.AreEqual(R_EFB_COMMENT, R);
  Assert.AreEqual('', Fix(InUnit(['  try', '    Work;', '  finally {keep}',
    '  end;']), R));
  Assert.AreEqual(R_EFB_COMMENT, R);
  Assert.AreEqual('', Fix(InUnit(['  try', '    Work;', '  finally',
    '  {$IFDEF X}', '  end;']), R));
  Assert.AreEqual(R_EFB_COMMENT, R);
end;

procedure TTestRdxEmptyFinallyFix.Refuse_NotEmpty;
var
  R : string;
begin
  Assert.AreEqual('', Fix(InUnit(['  try', '    Work;', '  finally',
    '    Obj.Free;', '  end;']), R));
  Assert.AreEqual(R_EFB_NOT_EMPTY, R);
end;

procedure TTestRdxEmptyFinallyFix.Refuse_BranchWithoutBegin;
var
  R : string;
begin
  // then, else und eine case-Marke: ohne begin..end gaebe es keinen Rumpf.
  Assert.AreEqual('', Fix(InUnit(['  if C then', '    try', '      Work;',
    '    finally', '    end;']), R));
  Assert.AreEqual(R_EFB_BRANCH, R);
  Assert.AreEqual('', Fix(InUnit(['  if C then', '    Other', '  else',
    '    try', '      Work;', '    finally', '    end;']), R));
  Assert.AreEqual(R_EFB_BRANCH, R);
  Assert.AreEqual('', Fix(InUnit(['  case N of', '    1: try', '      Work;',
    '    finally', '    end;', '  end;']), R));
  Assert.AreEqual(R_EFB_BRANCH, R);
end;

procedure TTestRdxEmptyFinallyFix.Refuse_LineProblems;
var
  R : string;
begin
  // Zeile ohne finally (verschoben), finally nur im String bzw. Kommentar,
  // zwei finally auf einer Zeile (mehrdeutig).
  Assert.AreEqual('', FixAt(InUnit(['  try', '    Work;', '  finally',
    '  end;']), BODY_LINE, R));
  Assert.IsTrue(Pos('kein finally', R) > 0, R);
  Assert.AreEqual('', FixAt(InUnit(['  S := ''finally end'';']), BODY_LINE, R));
  Assert.IsTrue(Pos('kein finally', R) > 0, R);
  Assert.AreEqual('', FixAt(InUnit(['  Work; // finally end']), BODY_LINE, R));
  Assert.IsTrue(Pos('kein finally', R) > 0, R);
  Assert.AreEqual('', FixAt(InUnit(['  try try A; finally end; finally end;']),
    BODY_LINE, R));
  Assert.IsTrue(Pos('mehrdeutig', R) > 0, R);
end;

procedure TTestRdxEmptyFinallyFix.Refuse_BodyWords;
var
  R : string;
begin
  // Ein Inline-var galte nach dem Fix im umgebenden Block; goto verliert
  // seinen Block.
  Assert.AreEqual('', Fix(InUnit(['  try', '    var N := 1;', '    Use(N);',
    '  finally', '  end;']), R));
  Assert.AreEqual(R_EFB_SPECIAL, R);
  Assert.AreEqual('', Fix(InUnit(['  try', '    goto Done;', '  finally',
    '  end;']), R));
  Assert.AreEqual(R_EFB_SPECIAL, R);
end;

procedure TTestRdxEmptyFinallyFix.Refuse_DirectiveAndMultiLine;
var
  R : string;
begin
  Assert.AreEqual('', Fix(InUnit(['  try', '  {$IFDEF DEBUG}', '    Log;',
    '  {$ENDIF}', '    Work;', '  finally', '  end;']), R));
  Assert.AreEqual(R_EFB_DIRECTIVE, R);
  Assert.AreEqual('', Fix(InUnit(['  try', '    { a', '      b }', '    Work;',
    '  finally', '  end;']), R));
  Assert.AreEqual(R_EFB_MULTILINE, R);
end;

procedure TTestRdxEmptyFinallyFix.Refuse_Layout;
var
  R : string;
begin
  // Alles auf einer Zeile, Kommentar hinter end, Kommentar hinter try, ';'
  // erst auf der Folgezeile.
  Assert.AreEqual('', Fix(InUnit(['  try Work; finally end;']), R));
  Assert.AreEqual(R_EFB_TRY_LINE, R);
  Assert.AreEqual('', Fix(InUnit(['  try', '    Work;', '  finally',
    '  end; // done']), R));
  Assert.AreEqual(R_EFB_FIN_LINE, R);
  Assert.AreEqual('', Fix(InUnit(['  try // guard', '    Work;', '  finally',
    '  end;']), R));
  Assert.AreEqual(R_EFB_TRY_LINE, R);
  Assert.AreEqual('', Fix(InUnit(['  begin', '    try', '      Work;',
    '    finally', '    end', '    ;', '  end;']), R));
  Assert.AreEqual(R_EFB_END_TAIL, R);
end;

procedure TTestRdxEmptyFinallyFix.Refuse_IndentAndEmptyBody;
var
  R : string;
begin
  // Eine Randzeile im Rumpf liesse sich nicht gleich ausruecken.
  Assert.AreEqual('', Fix(InUnit(['  try', '    Work;', '// stray',
    '    More;', '  finally', '  end;']), R));
  Assert.AreEqual(Format(R_EFB_INDENT, [BODY_LINE + 2]), R);
  // Kein Rumpf, nur ein Kommentar: es bliebe nichts.
  Assert.AreEqual('', Fix(InUnit(['  try', '  finally', '  end;']), R));
  Assert.AreEqual(R_EFB_EMPTY_BODY, R);
  Assert.AreEqual('', Fix(InUnit(['  try', '    // nothing', '  finally',
    '  end;']), R));
  Assert.AreEqual(R_EFB_EMPTY_BODY, R);
end;

// ---- echter Detektor ----

procedure TTestRdxEmptyFinallyFix.Detector_RoundTrip;
var
  Source : string;
begin
  // Ein leeres finally im inneren try (das aeussere hat Inhalt) und eines
  // mit 'finally end;' auf einer Zeile - der Detektor meldet beide, nach
  // dem Fix keines mehr.
  Source := InUnit(['  Obj := TObject.Create;', '  try', '    try',
    '      DoWork(Obj);', '      More(Obj);', '    finally', '    end;',
    '  finally', '    Obj.Free;', '  end;', '  try', '    Other;',
    '  finally end;']);
  Assert.AreEqual<Integer>(2, Length(Detect(Source)));
  Assert.AreEqual(
    InUnit(['  Obj := TObject.Create;', '  try', '    DoWork(Obj);',
      '    More(Obj);', '  finally', '    Obj.Free;', '  end;', '  Other;']),
    FixAll(Source));
end;

procedure TTestRdxEmptyFinallyFix.Detector_CatalogExample;
var
  Meta   : TRuleMeta;
  Source : string;
begin
  // Das Beispiel 'bad' des Katalogs mit einem Rumpf statt '...': try,
  // finally und end fallen weg.
  Meta := TRuleCatalog.GetRuleCanonical(fkEmptyFinallyBlock);
  Assert.IsTrue(Pos('finally', Meta.BadExample) > 0, Meta.BadExample);
  Source := InRoutine(StringReplace(CatalogText(Meta.BadExample), '...',
    'Work(Stream);', [rfReplaceAll]));
  Assert.AreEqual<Integer>(1, Length(Detect(Source)));
  Assert.AreEqual(
    InRoutine(Join(['Stream := TFileStream.Create(P);', 'Work(Stream);'])),
    FixAll(Source));
end;

procedure TTestRdxEmptyFinallyFix.Adapter_Outcome;
var
  F  : TLeakFinding;
  O  : TRdxFixOutcome;
  SL : TStringList;
  S  : string;
begin
  S := InUnit(['  try', '    Work;', '  finally', '  end;']);
  F := TLeakFinding.New('t.pas', '', LineOf(S, 'finally'), 'Empty finally',
    fkEmptyFinallyBlock);
  SL := TStringList.Create;
  try
    // Ohne Zeilen: kein Puffer.
    O := PlanEmptyFinally(nil, nil, F, nil);
    Assert.IsFalse(O.Enabled);
    Assert.AreEqual(R_NO_FILE, O.Reason);
    SL.Text := S;
    O := PlanEmptyFinally(nil, SL, F, nil);
    Assert.IsTrue(O.Enabled, O.Reason);
    Assert.AreEqual(InUnit(['  Work;']), Apply(S, O.Edits));
  finally
    SL.Free;
    F.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxEmptyFinallyFix);

end.

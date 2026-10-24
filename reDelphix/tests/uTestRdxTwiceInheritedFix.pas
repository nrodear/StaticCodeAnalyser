unit uTestRdxTwiceInheritedFix;

// Editorhilfe SCA093 TwiceInheritedCalls (uRdxTwiceInheritedFix), nur
// Delphi (reDelphix.Test): die Planer auf Text, die Adapter in der Form der
// Tabelle und der ECHTE Detektor (uTwiceInheritedCalls) auf dem echten AST.
// Der Fund zeigt auf den Methodenkopf (Zeile 4 der Fixtures), die Aufrufe
// stehen darunter; der Hauptweg loescht den zweiten, der zweite Eintrag den
// ersten Aufruf. Um beide zu unterscheiden, schreiben die Fixtures den
// zweiten Aufruf anders gross ('Inherited;') - Delphi liest sie gleich.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxTwiceInheritedFix = class
  public
    // ---- Planer auf Text ----
    [Test] procedure Main_DeletesSecondCall;
    [Test] procedure Alt_DeletesFirstCall;
    [Test] procedure NamedCallWithArguments;
    [Test] procedure DifferentArguments_NoHelp;
    [Test] procedure CodeBetween_NoHelp;
    [Test] procedure CommentBetween_NoHelp;
    [Test] procedure SharedLine_NoHelp;
    [Test] procedure CommentedOrStringCall_NotCounted;
    [Test] procedure ThreeCalls_NoHelp;
    [Test] procedure MovedLine_NoHelp;
    [Test] procedure NestedBlock_NoHelp;
    [Test] procedure NestedRoutine_NoHelp;
    [Test] procedure MissingSemicolon_NoHelp;
    [Test] procedure OtherMember_NoHelp;
    // ---- Adapter der Tabelle ----
    [Test] procedure Adapters_VariantsAndHints;
    [Test] procedure Adapter_StaleFinding_AltStaysMarked;
    // ---- echter Detektor ----
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_AltRoundTrip_Method;
    [Test] procedure Detector_CatalogExample_NoHelp;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog,
  uTwiceInheritedCalls,
  uRdxBufferMath, uRdxCodeMap, uRdxRecipeRunner,
  uRdxFixTable, uRdxTwiceInheritedFix,
  uRdxText,              // _(), MsgMovedSuffix, MsgByHand (Gruende, E29)
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText
  uTestRdxTextKit;       // Join, Apply

const
  HEAD_LINE = 4;   // Zeile des Methodenkopfs in Wrap

// ---- Helfer ----

// Eine Unit mit EINER Routine; der Kopf steht auf Zeile 4, der Rumpf ab 6.
function WrapIn(const AHead: string; const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', AHead, 'begin'])
    + #13#10 + Join(ABody) + #13#10 + Join(['end;', 'end.']);
end;

function Wrap(const ABody: array of string): string;
begin
  Result := WrapIn('procedure Foo;', ABody);
end;

// Der Planer (Hauptweg oder AAlt) fuer Zeile ALine: der neue Text, oder ''
// bei Ablehnung (AReason).
function Plan(const ASource: string; ALine: Integer; AAlt: Boolean;
  out AReason: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
  Ok  : Boolean;
begin
  Result := '';
  AReason := '';
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    try
      if AAlt then
        Ok := TRdxTwiceInheritedFix.DeleteFirst(Map, ALine, '', E, AReason)
      else
        Ok := TRdxTwiceInheritedFix.DeleteSecond(Map, ALine, '', E, AReason);
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
  if Ok then
    Result := Apply(ASource, E);
end;

// Wie Plan, aber die Hilfe muss gelten (sonst scheitert der Test mit dem
// Grund).
function Applied(const ASource: string; ALine: Integer;
  AAlt: Boolean): string;
var
  R : string;
begin
  Result := Plan(ASource, ALine, AAlt, R);
  Assert.IsTrue(Result <> '', R);
end;

// Beide Wege lehnen mit demselben Grund ab.
procedure AssertRefused(const ASource: string; ALine: Integer;
  const AReason: string);
var
  R : string;
begin
  Assert.AreEqual('', Plan(ASource, ALine, False, R), 'Hauptweg: keine Hilfe');
  Assert.AreEqual(AReason, R, 'Hauptweg: Grund');
  Assert.AreEqual('', Plan(ASource, ALine, True, R), 'Alt: keine Hilfe');
  Assert.AreEqual(AReason, R, 'Alt: Grund');
end;

// Die Funde der Art SCA093 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TTwiceInheritedCallsDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_twice_', ASource, fkTwiceInheritedCalls,
    RunDetector);
end;

// Die Hilfe (Hauptweg oder AAlt) fuer den EINEN Fund des Detektors ueber
// den Einstieg des Anbieters (uTestRdxDetectorKit.PlanFixIn bzw.
// PlanAltFixIn: TRdxFixTable.FixFor/AlternativeFixFor mit dem
// Quellstellen-Dienst; bis zur Review Woche G06 eine eigene Kopie mit
// APlaces = nil - der Adapter braucht ihn nicht), angewendet wie der
// Editor.
function FixOnce(const ASource: string; AAlt: Boolean): string;
var
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  Seen := Detect(ASource);
  Assert.AreEqual<Integer>(1, Length(Seen), 'der Detektor meldet genau einen Fund');
  if AAlt then
    O := PlanAltFixIn(ASource, 't.pas', fkTwiceInheritedCalls, Seen[0])
  else
    O := PlanFixIn(ASource, 't.pas', fkTwiceInheritedCalls, Seen[0]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Result := Apply(ASource, O.Edits);
end;

// ---- Planer auf Text ----

procedure TTestRdxTwiceInheritedFix.Main_DeletesSecondCall;
begin
  Assert.AreEqual(Wrap(['  inherited;']),
    Applied(Wrap(['  inherited;', '  Inherited;']), HEAD_LINE, False));
  // Leerzeile zwischen den Aufrufen stoert nicht.
  Assert.AreEqual(Wrap(['  inherited;', '']),
    Applied(Wrap(['  inherited;', '', '  Inherited;']), HEAD_LINE, False));
end;

procedure TTestRdxTwiceInheritedFix.Alt_DeletesFirstCall;
begin
  Assert.AreEqual(Wrap(['  Inherited;']),
    Applied(Wrap(['  inherited;', '  Inherited;']), HEAD_LINE, True));
end;

procedure TTestRdxTwiceInheritedFix.NamedCallWithArguments;
const
  HEAD = 'procedure TA.Bar(AOwner: TObject; N: Integer);';
begin
  Assert.AreEqual(WrapIn(HEAD, ['  inherited bar(AOwner, 1);']),
    Applied(WrapIn(HEAD, ['  inherited bar(AOwner, 1);',
      '  inherited Bar(AOwner, 1);']), HEAD_LINE, False));
  Assert.AreEqual(WrapIn(HEAD, ['  inherited Bar(AOwner, 1);']),
    Applied(WrapIn(HEAD, ['  inherited bar(AOwner, 1);',
      '  inherited Bar(AOwner, 1);']), HEAD_LINE, True));
end;

procedure TTestRdxTwiceInheritedFix.DifferentArguments_NoHelp;
const
  HEAD = 'procedure TA.Bar(AOwner: TObject; N: Integer);';
begin
  AssertRefused(WrapIn(HEAD, ['  inherited Bar(AOwner, 1);',
    '  inherited Bar(AOwner, 2);']), HEAD_LINE, _(R_TWICE_DIFFERENT));
  // Ein String-Literal ist gross/klein genau.
  AssertRefused(WrapIn(HEAD, ['  inherited Bar(''a'');',
    '  inherited Bar(''A'');']), HEAD_LINE, _(R_TWICE_DIFFERENT));
end;

procedure TTestRdxTwiceInheritedFix.CodeBetween_NoHelp;
begin
  // Die Form des Katalog-Beispiels: ob DoStuff vom ersten Aufruf abhaengt,
  // weiss die Hilfe nicht.
  AssertRefused(Wrap(['  inherited;', '  DoStuff;', '  inherited;']),
    HEAD_LINE, _(R_TWICE_NOT_ADJACENT));
end;

procedure TTestRdxTwiceInheritedFix.CommentBetween_NoHelp;
begin
  AssertRefused(Wrap(['  inherited;', '  // erst der Vorfahr', '  inherited;']),
    HEAD_LINE, _(R_TWICE_BETWEEN));
  AssertRefused(Wrap(['  inherited;', '  {$IFDEF X}', '  inherited;']),
    HEAD_LINE, _(R_TWICE_BETWEEN));
end;

procedure TTestRdxTwiceInheritedFix.SharedLine_NoHelp;
begin
  AssertRefused(Wrap(['  inherited;', '  inherited; // zweiter']),
    HEAD_LINE, _(R_TWICE_SHARED));
  AssertRefused(Wrap(['  inherited; inherited;']), HEAD_LINE, _(R_TWICE_SHARED));
end;

procedure TTestRdxTwiceInheritedFix.CommentedOrStringCall_NotCounted;
begin
  // Ein auskommentierter oder in einem String stehender Aufruf ist keiner.
  AssertRefused(Wrap(['  inherited;', '  // inherited;']), HEAD_LINE,
    _(R_TWICE_COUNT, [1]));
  AssertRefused(Wrap(['  inherited;', '  { inherited; }']), HEAD_LINE,
    _(R_TWICE_COUNT, [1]));
  AssertRefused(Wrap(['  inherited;', '  S := ''inherited;'';']), HEAD_LINE,
    _(R_TWICE_COUNT, [1]));
end;

procedure TTestRdxTwiceInheritedFix.ThreeCalls_NoHelp;
begin
  AssertRefused(Wrap(['  inherited;', '  inherited;', '  inherited;']),
    HEAD_LINE, _(R_TWICE_COUNT, [3]));
end;

procedure TTestRdxTwiceInheritedFix.MovedLine_NoHelp;
var
  Src : string;
begin
  Src := Wrap(['  inherited;', '  Inherited;']);
  // Zeile 5 ist das begin, Zeile 6 ein Aufruf: kein Routinenkopf.
  AssertRefused(Src, HEAD_LINE + 1, MsgMovedSuffix(_(R_TWICE_HEAD_MOVED)));
  AssertRefused(Src, HEAD_LINE + 2, MsgMovedSuffix(_(R_TWICE_HEAD_MOVED)));
  AssertRefused(Src, 99, MsgMovedSuffix(_(R_TWICE_HEAD_MOVED)));
end;

procedure TTestRdxTwiceInheritedFix.NestedBlock_NoHelp;
begin
  // Die Hilfe beschraenkt sich auf die oberste Ebene des Rumpfs.
  AssertRefused(Wrap(['  if X then', '  begin', '    inherited;',
    '    Inherited;', '  end;']), HEAD_LINE, _(R_TWICE_COUNT, [0]));
  // Ein bedingter Aufruf zaehlt nicht mit.
  AssertRefused(Wrap(['  if X then', '    inherited;', '  Inherited;']),
    HEAD_LINE, _(R_TWICE_COUNT, [1]));
end;

procedure TTestRdxTwiceInheritedFix.NestedRoutine_NoHelp;
begin
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'procedure Foo;', '  procedure Inner;', '  begin', '  end;', 'begin',
    '  inherited;', '  Inherited;', 'end;', 'end.']), HEAD_LINE,
    _(R_TWICE_BODY, [MsgByHand]));
end;

procedure TTestRdxTwiceInheritedFix.MissingSemicolon_NoHelp;
begin
  // Der letzte Aufruf vor dem end ohne ';' - die Hilfe liest ihn nicht.
  AssertRefused(Wrap(['  inherited;', '  Inherited']), HEAD_LINE,
    _(R_TWICE_UNREADABLE, [MsgByHand]));
end;

procedure TTestRdxTwiceInheritedFix.OtherMember_NoHelp;
begin
  // 'inherited Lock' ruft eine andere Elternmethode als Foo - der Detektor
  // zaehlt es nicht, die Hilfe auch nicht.
  AssertRefused(Wrap(['  inherited Lock;', '  inherited Lock;']), HEAD_LINE,
    _(R_TWICE_COUNT, [0]));
end;

// ---- Adapter der Tabelle ----

procedure TTestRdxTwiceInheritedFix.Adapters_VariantsAndHints;
var
  SL      : TStringList;
  F       : TLeakFinding;
  Main, A : TRdxFixOutcome;
begin
  SL := TStringList.Create;
  F := nil;
  try
    F := TLeakFinding.New('t.pas', '', HEAD_LINE, 'x', fkTwiceInheritedCalls);
    SL.Text := Wrap(['  inherited;', '  Inherited;']);
    Main := TRdxFixTable.FixFor(nil, SL, F, nil);
    A := TRdxFixTable.AlternativeFixFor(nil, SL, F, nil);
  finally
    F.Free;
    SL.Free;
  end;
  Assert.IsTrue(Main.Enabled, Main.Reason);
  Assert.AreEqual<Integer>(0, Main.Variant, 'Hauptweg ist Variant 0');
  Assert.AreEqual<Integer>(1, Length(Main.Edits), 'Hauptweg: eine Ersetzung');
  Assert.AreEqual<Integer>(7, Main.Edits[0].Span.StartLine, 'der zweite Aufruf');
  Assert.IsTrue(A.Enabled, A.Reason);
  Assert.AreEqual<Integer>(1, A.Variant, 'der zweite Eintrag ist Variant 1');
  Assert.IsTrue(A.ChangesBehavior, 'gekennzeichnet (E2)');
  // de.po traegt echte Umlaute (Charge G7) - hier als #$-Code.
  Assert.AreEqual('der erste Aufruf entf'#$00E4'llt - die Elternmethode '
    + 'l'#$00E4'uft nur noch einmal; Reihenfolge und Nebenwirkung '
    + 'pr'#$00FC'fen', A.Hint);
  Assert.AreEqual<Integer>(6, A.Edits[0].Span.StartLine, 'der erste Aufruf');
end;

procedure TTestRdxTwiceInheritedFix.Adapter_StaleFinding_AltStaysMarked;
var
  SL : TStringList;
  F  : TLeakFinding;
  A  : TRdxFixOutcome;
begin
  SL := TStringList.Create;
  F := nil;
  try
    // Der Fund zeigt auf Zeile 5, doch dort steht das begin.
    F := TLeakFinding.New('t.pas', '', HEAD_LINE + 1, 'x', fkTwiceInheritedCalls);
    SL.Text := Wrap(['  inherited;', '  Inherited;']);
    A := TRdxFixTable.AlternativeFixFor(nil, SL, F, nil);
  finally
    F.Free;
    SL.Free;
  end;
  Assert.IsFalse(A.Enabled, 'gesperrt');
  Assert.AreEqual(MsgMovedSuffix(_(R_TWICE_HEAD_MOVED)), A.Reason);
  Assert.AreEqual<Integer>(1, A.Variant, 'der Eintrag bleibt der zweite');
  Assert.IsTrue(A.ChangesBehavior, 'auch gesperrt gekennzeichnet');
  Assert.AreEqual<Integer>(0, Length(A.Edits), 'keine Ersetzung');
end;

// ---- echter Detektor ----

procedure TTestRdxTwiceInheritedFix.Detector_RoundTrip;
var
  Src, After : string;
begin
  Src := Wrap(['  inherited;', '  Inherited;']);
  After := FixOnce(Src, False);
  Assert.AreEqual(Wrap(['  inherited;']), After);
  Assert.AreEqual<Integer>(0, Length(Detect(After)), 'der Detektor schweigt danach');
end;

procedure TTestRdxTwiceInheritedFix.Detector_AltRoundTrip_Method;
const
  HEAD = 'procedure TFoo.Bar;';
var
  Src, After : string;
begin
  Src := WrapIn(HEAD, ['  Inherited Bar;', '  inherited bar;']);
  After := FixOnce(Src, True);
  Assert.AreEqual(WrapIn(HEAD, ['  inherited bar;']), After);
  Assert.AreEqual<Integer>(0, Length(Detect(After)), 'der Detektor schweigt danach');
end;

procedure TTestRdxTwiceInheritedFix.Detector_CatalogExample_NoHelp;
var
  Meta : TRuleMeta;
  Src  : string;
  Seen : TArray<TSeen>;
  SL   : TStringList;
  F    : TLeakFinding;
  O    : TRdxFixOutcome;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkTwiceInheritedCalls);
  Assert.IsTrue(Pos('inherited;', Meta.BadExample) > 0, Meta.BadExample);
  Src := Join(['unit t;', 'interface', 'implementation',
    CatalogText(Meta.BadExample), 'end.']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen), 'der Detektor meldet das Beispiel');
  SL := TStringList.Create;
  F := nil;
  try
    F := TLeakFinding.New('t.pas', '', Seen[0].Line, Seen[0].Msg,
      fkTwiceInheritedCalls);
    SL.Text := Src;
    O := TRdxFixTable.FixFor(nil, SL, F, nil);
  finally
    F.Free;
    SL.Free;
  end;
  // Zwischen den Aufrufen steht DoStuff: keine Hilfe.
  Assert.IsFalse(O.Enabled, 'keine Hilfe fuer das Katalog-Beispiel');
  Assert.AreEqual(_(R_TWICE_NOT_ADJACENT), O.Reason);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxTwiceInheritedFix);

end.

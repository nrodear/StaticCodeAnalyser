unit uTestRdxNoSonarFix;

// Editorhilfe SCA065 NoSonarMarker (uRdxNoSonarFix) - nur Delphi,
// reDelphix.Test (der echte Detektor und der echte Core gehoeren dazu):
//   Planer auf Text: Marker-Zeile darueber mit Einzug, Rest des Kommentars
//     hinter dem Code (mit ':' und '-' als Trenner, 'NOSONAR(S1234)'),
//     Schreibweisen (//nosonar, NoSonar), Marker einer Art darueber bleibt;
//   Gegenproben: eigene Kommentarzeile, NOSONAR nicht erstes Wort, doppelt,
//     Rest beginnt mit noinspection, 'All' schon darueber, Block-Kommentar,
//     String, mehrzeiliger String, verschobene Zeile, fehlende Spalte;
//   Rundlauf mit dem ECHTEN Detektor (danach schweigt er) und dem ECHTEN
//     Core (TSuppression): der neue Marker unterdrueckt die Zeile ausser den
//     kritischen Arten, und er gilt nicht als wirkungslos.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxNoSonarFix = class
  public
    // ---- Planer auf Text ----
    [Test] procedure Trailing_MarkerMovesAbove;
    [Test] procedure Reason_StaysBehindCode;
    [Test] procedure ColonReason_StaysBehindCode;
    [Test] procedure Spellings_AndGapKept;
    [Test] procedure Indent_IsKept;
    [Test] procedure ParenReason_StaysBehindCode;
    [Test] procedure KindMarkerAbove_Stacks;
    // ---- Gegenproben ----
    [Test] procedure OwnLine_NoHelp;
    [Test] procedure NotFirstWord_NoHelp;
    [Test] procedure NamedTwice_NoHelp;
    [Test] procedure RestIsMarker_NoHelp;
    [Test] procedure AllAbove_NoHelp;
    [Test] procedure InBlockStringOrMultiLine_NoHelp;
    [Test] procedure MovedLine_OtherWord_NoHelp;
    [Test] procedure NoColumn_NoHelp;
    // ---- Adapter ----
    [Test] procedure Adapter_PlansOneEdit;
    [Test] procedure Adapter_NoFile_NoHelp;
    // ---- echter Detektor und Core ----
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_CatalogExample;
    [Test] procedure Core_MarkerSuppressesTheLine;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uNoSonarMarker,
  uSuppression, uFileTextCache,
  uRdxBufferMath, uRdxCodeMap, uRdxRecipeRunner, uRdxNoSonarFix,
  uRdxText,             // _() und die gemeinsamen Gruende
  uTestRdxTextKit,      // Join, Apply
  uTestRdxDetectorKit;  // DetectSource, TSeen, WriteTemp

const
  QUOTE3        = #39#39#39;
  FILE_NAME     = 't.pas';
  MARKER        = '// noinspection All';

type
  // Ein Fund nach dem Filter des Cores.
  TFound = record
    Kind : TFindingKind;
    Line : Integer;
  end;

// Die Meldung des Detektors fuer die Spalte ACol.
function NsMsg(ACol: Integer): string;
begin
  Result := Format('NOSONAR marker at column %d - migrate to `// noinspection` '
    + 'or fix the underlying finding.', [ACol]);
end;

// Eine Unit mit den Zeilen ALines als Rumpf einer Routine (ab Zeile 6).
function InUnit(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation', 'procedure P;'])
    + #13#10 + 'begin' + #13#10 + Join(ALines) + #13#10 + Join(['end;', 'end.']);
end;

// Die Hilfe fuer Zeile ALine mit der Spalte ACol in der Meldung: neuer Text
// oder '' bei Ablehnung (AReason).
function FixCol(const ASource: string; ALine, ACol: Integer;
  out AReason: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if TRdxNoSonarFix.ToNoinspection(Map, ALine, NsMsg(ACol), E, AReason) then
      Result := Apply(ASource, E);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Dasselbe mit der Spalte des ersten '//' der Zeile.
function Fix(const ASource: string; ALine: Integer; out AReason: string): string;
var
  SL : TStringList;
  Col: Integer;
begin
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Col := 0;
    if (ALine >= 1) and (ALine <= SL.Count) then
      Col := Pos('//', SL[ALine - 1]);
  finally
    SL.Free;
  end;
  Result := FixCol(ASource, ALine, Col, AReason);
end;

// Die Hilfe ist angeboten und liefert AExpected.
procedure AssertFix(const AExpected, ASource: string; ALine: Integer);
var
  R : string;
begin
  Assert.AreEqual(AExpected, Fix(ASource, ALine, R), R);
end;

// Keine Hilfe, mit dem Grund AReason.
procedure AssertNoFix(const ASource: string; ALine: Integer;
  const AReason: string);
var
  R : string;
begin
  Assert.AreEqual('', Fix(ASource, ALine, R), ASource);
  Assert.AreEqual(AReason, R, ASource);
end;

function Moved: string;
begin
  Result := MsgMovedSuffix(_(R_NS_MOVED));
end;

procedure RunNoSonar(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TNoSonarMarkerDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_ns_', ASource, fkNoSonarMarker, RunNoSonar);
end;

// Alle Funde des echten Detektors, jede Hilfe auf dem Ausgangstext geplant
// und zusammen angewendet (die Zeilen ueberlappen nicht). Die Hilfe muss
// jeden Fund annehmen.
function FixAll(const ASource: string): string;
var
  Seen  : TArray<TSeen>;
  Edits : TArray<TRdxEdit>;
  SL    : TStringList;
  F     : TLeakFinding;
  O     : TRdxFixOutcome;
  i     : Integer;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet');
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    SetLength(Edits, Length(Seen));
    for i := 0 to High(Seen) do
    begin
      F := TLeakFinding.New(FILE_NAME, '', Seen[i].Line, Seen[i].Msg,
        fkNoSonarMarker);
      try
        O := PlanNoSonar(nil, SL, F, nil);
      finally
        F.Free;
      end;
      Assert.IsTrue(O.Enabled, Seen[i].Msg + ' / ' + O.Reason);
      Edits[i] := O.Edits[0];
    end;
  finally
    SL.Free;
  end;
  Result := Apply(ASource, Edits);
end;

// Der Core auf ASource: Datei schreiben, Marker einsammeln wie der Scan, die
// gesetzten Funde (AKinds[i] in Zeile ALines[i]) filtern; was bleibt, samt
// den Meldungen wirkungsloser Marker (fkUnusedSuppression auf der
// Markerzeile). Ohne Profil-Gate (leere Artenmenge).
function CoreRun(const ASource: string; const AKinds: array of TFindingKind;
  const ALines: array of Integer): TArray<TFound>;
var
  Path     : string;
  Findings : TObjectList<TLeakFinding>;
  Pre      : TObjectDictionary<string, TList<TSuppressionMarker>>;
  Gate     : TFindingKinds;
  i        : Integer;
begin
  Assert.AreEqual<Integer>(Length(AKinds), Length(ALines), 'Arten und Zeilen');
  Path := WriteTemp('rdx_nscore_', ASource);
  Findings := TObjectList<TLeakFinding>.Create(True);
  Pre := nil;
  try
    Pre := TObjectDictionary<string, TList<TSuppressionMarker>>.Create(
      [doOwnsValues]);
    for i := 0 to High(AKinds) do
      Findings.Add(TLeakFinding.New(Path, '', ALines[i], 'gesetzt', AKinds[i]));
    TSuppression.CollectMarkersForScan(Path, Pre);
    Gate := [];
    TSuppression.ApplyToFindings(Findings, Pre, @Gate);
    SetLength(Result, Findings.Count);
    for i := 0 to Findings.Count - 1 do
    begin
      Result[i].Kind := Findings[i].Kind;
      Result[i].Line := Findings[i].LineInt;
    end;
  finally
    Pre.Free;
    Findings.Free;
    if Assigned(gFileTextCache) then
      gFileTextCache.RemoveFile(Path);
    DeleteFile(Path);
  end;
end;

function Has(const AFound: TArray<TFound>; AKind: TFindingKind;
  ALine: Integer): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := 0 to High(AFound) do
    if (AFound[i].Kind = AKind) and (AFound[i].Line = ALine) then
      Exit(True);
end;

{ ---- Planer auf Text ---- }

procedure TTestRdxNoSonarFix.Trailing_MarkerMovesAbove;
begin
  AssertFix(InUnit(['  ' + MARKER, '  Dispose(P);']),
    InUnit(['  Dispose(P); // NOSONAR']), 6);
end;

procedure TTestRdxNoSonarFix.Reason_StaysBehindCode;
begin
  // Der Grund steht NICHT auf der Markerzeile: 'noinspection All - Grund' ist
  // kein Marker (All gilt nur als ganze Artenliste).
  AssertFix(InUnit(['  ' + MARKER, '  Dispose(P); // we know about this']),
    InUnit(['  Dispose(P); // NOSONAR - we know about this']), 6);
end;

procedure TTestRdxNoSonarFix.ColonReason_StaysBehindCode;
begin
  AssertFix(InUnit(['  ' + MARKER, '  X := 1; // id from enum']),
    InUnit(['  X := 1; // NOSONAR: id from enum']), 6);
  AssertFix(InUnit(['  ' + MARKER, '  X := 1;// id from enum']),
    InUnit(['  X := 1;//NOSONAR:id from enum']), 6);
end;

procedure TTestRdxNoSonarFix.Spellings_AndGapKept;
begin
  AssertFix(InUnit(['  ' + MARKER, '  X := 1;']),
    InUnit(['  X := 1;   //nosonar']), 6);
  AssertFix(InUnit(['  ' + MARKER, '  X := 1;   // kept']),
    InUnit(['  X := 1;   // NoSonar kept']), 6);
end;

procedure TTestRdxNoSonarFix.Indent_IsKept;
begin
  AssertFix(InUnit([#9 + MARKER, #9 + 'Go;']),
    InUnit([#9 + 'Go; // NOSONAR']), 6);
  AssertFix(InUnit([MARKER, 'Go;']), InUnit(['Go; // NOSONAR']), 6);
end;

procedure TTestRdxNoSonarFix.ParenReason_StaysBehindCode;
begin
  // '(' ist keine Bezeichnerzeichen: NOSONAR(S1234) ist das Wort.
  AssertFix(InUnit(['  ' + MARKER, '  Go; // (S1234) legacy']),
    InUnit(['  Go; // NOSONAR(S1234) legacy']), 6);
end;

procedure TTestRdxNoSonarFix.KindMarkerAbove_Stacks;
begin
  // Ein Marker einer Art darueber bleibt, der neue steht dazwischen: der
  // Core vereinigt gestapelte Marker fuer das Code-Ziel.
  AssertFix(InUnit(['  // noinspection NilComparison', '  ' + MARKER,
      '  if A = nil then Go;']),
    InUnit(['  // noinspection NilComparison',
      '  if A = nil then Go; // NOSONAR']), 7);
end;

{ ---- Gegenproben ---- }

procedure TTestRdxNoSonarFix.OwnLine_NoHelp;
begin
  AssertNoFix(InUnit(['  // NOSONAR', '  Go;']), 6, _(R_NS_OWN_LINE));
  AssertNoFix(InUnit(['  // NOSONAR weil', '  Go;']), 6, _(R_NS_OWN_LINE));
end;

procedure TTestRdxNoSonarFix.NotFirstWord_NoHelp;
begin
  AssertNoFix(InUnit(['  Go; // see NOSONAR']), 6, _(R_NS_NOT_FIRST));
  AssertNoFix(InUnit(['  Go; // x NOSONAR: y']), 6, _(R_NS_NOT_FIRST));
end;

procedure TTestRdxNoSonarFix.NamedTwice_NoHelp;
begin
  AssertNoFix(InUnit(['  Go; // NOSONAR NOSONAR']), 6, _(R_NS_MANY));
  AssertNoFix(InUnit(['  Go; // NOSONAR - not a NOSONAR']), 6, _(R_NS_MANY));
end;

procedure TTestRdxNoSonarFix.RestIsMarker_NoHelp;
begin
  // Der Rest wuerde hinter dem Code ein eigener Marker, der die FOLGEZEILE
  // trifft.
  AssertNoFix(InUnit(['  Go; // NOSONAR noinspection NilComparison']), 6,
    _(R_NS_REST_MARKER));
  AssertNoFix(InUnit(['  Go; // NOSONAR: NoInspection All']), 6,
    _(R_NS_REST_MARKER));
end;

procedure TTestRdxNoSonarFix.AllAbove_NoHelp;
begin
  AssertNoFix(InUnit(['  ' + MARKER, '  Go; // NOSONAR']), 7, _(R_NS_HAVE_ALL));
  // Auch ohne Einzug und mit anderem Leerraum.
  AssertNoFix(InUnit(['//noinspection' + #9 + 'ALL', '  Go; // NOSONAR']), 7,
    _(R_NS_HAVE_ALL));
end;

procedure TTestRdxNoSonarFix.InBlockStringOrMultiLine_NoHelp;
begin
  // Zeile beginnt in einem Block-Kommentar.
  AssertNoFix(InUnit(['  { note', '  Go; // NOSONAR }']), 7,
    MsgLineStartsInCommentOrString);
  // Das '//' steht in einem Block-Kommentar derselben Zeile.
  AssertNoFix(InUnit(['  { Go; // NOSONAR }']), 6, Moved);
  AssertNoFix(InUnit(['  (* Go; // NOSONAR *)']), 6, Moved);
  // ... oder in einem String.
  AssertNoFix(InUnit(['  S := ' + #39 + '// NOSONAR' + #39 + ';']), 6, Moved);
  // Zeile im mehrzeiligen String (der Detektor meldet sie trotzdem).
  AssertNoFix(InUnit(['  S := ' + QUOTE3, '    text // NOSONAR',
    '  ' + QUOTE3 + ';']), 7, MsgLineStartsInCommentOrString);
end;

procedure TTestRdxNoSonarFix.MovedLine_OtherWord_NoHelp;
var
  R : string;
begin
  // Kein Kommentar mehr in der Zeile.
  Assert.AreEqual('', FixCol(InUnit(['  Go;']), 6, 3, R));
  Assert.AreEqual(Moved, R);
  // Falsche Spalte (das '//' steht an Spalte 7), Zeile hinter dem Ende.
  Assert.AreEqual('', FixCol(InUnit(['  Go; // NOSONAR']), 6, 5, R));
  Assert.AreEqual(Moved, R);
  Assert.AreEqual('', FixCol(InUnit(['  Go; // NOSONAR']), 99, 7, R));
  Assert.AreEqual(Moved, R);
  // Ein anderes Wort (der Detektor meldet es nie): kein ganzes NOSONAR.
  AssertNoFix(InUnit(['  Go; // NOSONARQUBE']), 6, Moved);
  AssertNoFix(InUnit(['  Go; // uNoSonarMarker']), 6, Moved);
end;

procedure TTestRdxNoSonarFix.NoColumn_NoHelp;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
  R   : string;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := InUnit(['  Go; // NOSONAR']);
    Map := TRdxCodeMap.Create(SL);
    Assert.IsFalse(TRdxNoSonarFix.ToNoinspection(Map, 6, 'NOSONAR marker', E, R));
    Assert.AreEqual(MsgNoColumn, R);
  finally
    Map.Free;
    SL.Free;
  end;
end;

{ ---- Adapter ---- }

procedure TTestRdxNoSonarFix.Adapter_PlansOneEdit;
var
  SL   : TStringList;
  F    : TLeakFinding;
  O    : TRdxFixOutcome;
  Src  : string;
  Seen : TSeen;
begin
  Src := InUnit(['  Go; // NOSONAR']);
  SL := TStringList.Create;
  F := nil;
  try
    F := TLeakFinding.New(FILE_NAME, '', 6, NsMsg(7), fkNoSonarMarker);
    SL.Text := Src;
    O := PlanNoSonar(nil, SL, F, nil);
  finally
    F.Free;
    SL.Free;
  end;
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(1, Integer(Length(O.Edits)));
  Assert.AreEqual(InUnit(['  ' + MARKER, '  Go;']), Apply(Src, O.Edits[0]));
  // Die Kennzeichnung "aendert das Verhalten" (der Marker unterdrueckt
  // danach die Regeln der Zeile, NOSONAR tat das nicht) setzt erst die
  // Tabellenzeile (FixFor) - der Adapter laesst sie auf dem Default.
  Seen.Line := 6;
  Seen.Msg := NsMsg(7);
  Seen.Variant := '';
  O := PlanFixIn(Src, FILE_NAME, fkNoSonarMarker, Seen);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsTrue(O.ChangesBehavior, 'gekennzeichnet');
end;

procedure TTestRdxNoSonarFix.Adapter_NoFile_NoHelp;
var
  F : TLeakFinding;
  O : TRdxFixOutcome;
begin
  F := TLeakFinding.New(FILE_NAME, '', 6, NsMsg(7), fkNoSonarMarker);
  try
    O := PlanNoSonar(nil, nil, F, nil);
  finally
    F.Free;
  end;
  Assert.IsFalse(O.Enabled);
  Assert.AreEqual(R_NO_FILE, O.Reason);
end;

{ ---- echter Detektor und Core ---- }

procedure TTestRdxNoSonarFix.Detector_RoundTrip;
var
  Fixed : string;
begin
  Fixed := FixAll(InUnit(['  Dispose(P); // NOSONAR - we know',
    '  Go(A);   // nosonar', '  X := 1;//NOSONAR: id from enum']));
  Assert.AreEqual(InUnit(['  ' + MARKER, '  Dispose(P); // we know',
    '  ' + MARKER, '  Go(A);', '  ' + MARKER, '  X := 1;// id from enum']),
    Fixed);
  Assert.AreEqual<Integer>(0, Integer(Length(Detect(Fixed))),
    'der Detektor schweigt');
end;

procedure TTestRdxNoSonarFix.Detector_CatalogExample;
var
  Meta  : TRuleMeta;
  Bad   : string;
  Fixed : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkNoSonarMarker);
  Assert.IsTrue(Pos('NOSONAR', Meta.BadExample) > 0, Meta.BadExample);
  Bad := StringReplace(Meta.BadExample, #13#10, #10, [rfReplaceAll]);
  Assert.IsTrue(Pos(#10, Bad) = 0, 'ein einzeiliges Beispiel');
  Fixed := FixAll(InUnit([Bad]));
  Assert.IsTrue(Pos(MARKER, Fixed) > 0, Fixed);
  Assert.AreEqual<Integer>(0, Integer(Length(Detect(Fixed))),
    'der Detektor schweigt');
end;

procedure TTestRdxNoSonarFix.Core_MarkerSuppressesTheLine;
var
  Src, Fixed, R : string;
  Found         : TArray<TFound>;
begin
  Src := InUnit(['  Go(1); // NOSONAR - because']);
  // Vorher unterdrueckt der Core nichts: NOSONAR kennt er nicht.
  Found := CoreRun(Src, [fkNilComparison, fkHardcodedSecret], [6, 6]);
  Assert.IsTrue(Has(Found, fkNilComparison, 6), 'vorher gemeldet');
  Assert.IsTrue(Has(Found, fkHardcodedSecret, 6), 'vorher gemeldet');
  Fixed := Fix(Src, 6, R);
  Assert.AreEqual(InUnit(['  ' + MARKER, '  Go(1); // because']), Fixed, R);
  // Nachher: der Marker (Zeile 6) trifft die Code-Zeile 7. Eine gewoehnliche
  // Art ist unterdrueckt, die kritische bleibt (All erfasst sie nie), und der
  // Marker gilt nicht als wirkungslos.
  Found := CoreRun(Fixed, [fkNilComparison, fkHardcodedSecret], [7, 7]);
  Assert.IsFalse(Has(Found, fkNilComparison, 7), 'unterdrueckt');
  Assert.IsTrue(Has(Found, fkHardcodedSecret, 7), 'kritisch bleibt sichtbar');
  Assert.IsFalse(Has(Found, fkUnusedSuppression, 6), 'Marker wirkt');
  // Und die eigene Zeile des Markers ist NICHT sein Ziel.
  Found := CoreRun(Fixed, [fkNilComparison], [6]);
  Assert.IsTrue(Has(Found, fkNilComparison, 6), 'die Markerzeile selbst');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxNoSonarFix);

end.

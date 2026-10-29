unit uTestRdxTabsFix;

// Editorhilfe SCA061 TabulationCharacter (uRdxTabsFix): Tabs der gemeldeten
// Zeile -> Leerzeichen bis zum naechsten Tabstopp, nur im Code. Tabweite aus
// den Nachbarzeilen (rwE29), ohne Beweis 2. Auf Text (Gegenproben: String,
// Kommentar, verschobene Zeile) und mit dem ECHTEN Detektor (Rundlauf,
// Katalog-Beispiel) - nur Delphi, reDelphix.Test. Tabs im Quelltext dieser Unit stehen als TAB = #9.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxTabsFix = class
  public
    [Test] procedure Indent_OneAndTwoTabs;
    [Test] procedure Indent_MixedWithSpaces;
    [Test] procedure Between_Tokens_NextTabStop;
    [Test] procedure StringTab_Stays_IndentFixed;
    [Test] procedure CodeTabsAroundStringTab;
    [Test] procedure FirstTabInString_NoHelp;
    [Test] procedure CommentTab_NoHelp;
    [Test] procedure BlockCommentLine_NoHelp;
    [Test] procedure MovedLine_NoHelp;
    [Test] procedure NoColumn_NoHelp;
    [Test] procedure OnlyReportedLine_Changes;
    // rwE29: Tabweite aus den Nachbarzeilen.
    [Test] procedure Width8_ReasonCodeTable;
    [Test] procedure Width8_DirectiveBetweenSpaceLines;
    [Test] procedure Width8_SpaceTableAfterTab;
    [Test] procedure Width8_VarBlock;
    [Test] procedure TwoWidthsAlike_NoHelp;
    [Test] procedure TieWithDefault_KeepsDefault;
    [Test] procedure Plan_Hint_NamesWidth;
    [Test] procedure Plan_Adapter;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_StringOnly_NoHelp;
    [Test] procedure Detector_CatalogExample;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uTabulationCharacter,
  uRdxBufferMath, uRdxCodeMap, uRdxRecipeRunner, uRdxFixTable, uRdxTabsFix,
  uRdxText,              // MsgNoColumn (E29)
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText
  uTestRdxTextKit;       // Join, Apply

const
  TAB = #9;
  // Gruende (Teile davon) der Hilfe.
  RS_MOVED    = 'kein Tab an der gemeldeten Stelle';
  RS_NOT_CODE = 'in einem String oder Kommentar';
  RS_AMBIGUOUS = 'ebenso wie zu';

// ---- Helfer ----

// Die Meldung wie der Detektor sie schreibt.
function TabMsg(ACol: Integer): string;
begin
  Result := Format('Tab character at column %d - use spaces for indentation '
    + '(consistency across editors).', [ACol]);
end;

// Die Hilfe fuer Zeile ALine: neuer Text oder '' bei Ablehnung (AReason).
function Fix(const ASource: string; ALine: Integer; const AMessage: string;
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
    if TRdxTabsFix.Tabs(Map, ALine, AMessage, E, AReason) then
      Result := Apply(ASource, E);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Eine Zeile als Quelltext, Hilfe auf Zeile 1 mit der Spalte des ersten Tabs.
function FixLine(const ALine: string; out AReason: string): string;
begin
  Result := Fix(ALine, 1, TabMsg(Pos(TAB, ALine)), AReason);
end;

procedure RunTabs(AKind: TFindingKind; Root: TAstNode; const Path: string;
  Results: TObjectList<TLeakFinding>);
begin
  TTabulationCharacterDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('tabs', ASource, fkTabulationCharacter, RunTabs);
end;

// Dasselbe in der Form von TDetectFunc (FixAllWith).
function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := Detect(ASource);
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt - ueber den Einstieg des Anbieters
// (uTestRdxDetectorKit.FixAllWith, TRdxFixTable.FixFor; bis zur Review
// Woche G06 eine eigene Schleife).
function FixAll(const ASource: string): string;
begin
  Result := FixAllWith(ASource, fkTabulationCharacter, DetectKind);
end;

function InUnit(const ABody: string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', ABody, 'end.']);
end;

// ---- Text ----

procedure TTestRdxTabsFix.Indent_OneAndTwoTabs;
var
  R : string;
begin
  Assert.AreEqual('  DoStuff;', FixLine(TAB + 'DoStuff;', R), R);
  Assert.AreEqual('    DoStuff;', FixLine(TAB + TAB + 'DoStuff;', R), R);
end;

procedure TTestRdxTabsFix.Indent_MixedWithSpaces;
var
  R : string;
begin
  // Ein Tab nach einem Leerzeichen springt nur bis zum naechsten Stopp.
  Assert.AreEqual('  X;', FixLine(' ' + TAB + 'X;', R), R);
  Assert.AreEqual('    X;', FixLine('  ' + TAB + 'X;', R), R);
  Assert.AreEqual('    X;', FixLine(TAB + ' ' + TAB + 'X;', R), R);
end;

procedure TTestRdxTabsFix.Between_Tokens_NextTabStop;
var
  R : string;
begin
  Assert.AreEqual('XY:=  1;', FixLine('XY:=' + TAB + '1;', R), R);
  Assert.AreEqual('abc d;', FixLine('abc' + TAB + 'd;', R), R);
end;

procedure TTestRdxTabsFix.StringTab_Stays_IndentFixed;
var
  R : string;
begin
  Assert.AreEqual('  S := ''a' + TAB + 'b'';',
    FixLine(TAB + 'S := ''a' + TAB + 'b'';', R), R);
end;

procedure TTestRdxTabsFix.CodeTabsAroundStringTab;
var
  R : string;
begin
  Assert.AreEqual('X ''a' + TAB + 'b''  ;',
    FixLine('X' + TAB + '''a' + TAB + 'b''' + TAB + ';', R), R);
end;

procedure TTestRdxTabsFix.FirstTabInString_NoHelp;
var
  R : string;
begin
  Assert.AreEqual('', FixLine('S := ''a' + TAB + 'b'';', R));
  Assert.IsTrue(Pos(RS_NOT_CODE, R) > 0, R);
end;

procedure TTestRdxTabsFix.CommentTab_NoHelp;
var
  R : string;
begin
  Assert.AreEqual('', FixLine('X; // a' + TAB + 'b', R));
  Assert.IsTrue(Pos(RS_NOT_CODE, R) > 0, R);
end;

procedure TTestRdxTabsFix.BlockCommentLine_NoHelp;
var
  R : string;
begin
  Assert.AreEqual('', Fix(Join(['{ Kommentar', TAB + 'innen', '}']), 2,
    TabMsg(1), R));
  Assert.IsTrue(Pos(RS_NOT_CODE, R) > 0, R);
end;

procedure TTestRdxTabsFix.MovedLine_NoHelp;
var
  R : string;
begin
  // Spalte 1 ist kein Tab mehr; Zeile nicht mehr vorhanden; der Tab steht
  // weiter hinten, nicht an der gemeldeten Spalte.
  Assert.AreEqual('', Fix('  X;', 1, TabMsg(1), R));
  Assert.IsTrue(Pos(RS_MOVED, R) > 0, R);
  Assert.AreEqual('', Fix(TAB + 'X;', 5, TabMsg(1), R));
  Assert.IsTrue(Pos(RS_MOVED, R) > 0, R);
  Assert.AreEqual('', Fix(TAB + 'X;' + TAB, 1, TabMsg(4), R));
  Assert.IsTrue(Pos(RS_MOVED, R) > 0, R);
end;

procedure TTestRdxTabsFix.NoColumn_NoHelp;
var
  R : string;
begin
  Assert.AreEqual('', Fix(TAB + 'X;', 1, 'Tab character', R));
  Assert.AreEqual(MsgNoColumn, R);
end;

procedure TTestRdxTabsFix.OnlyReportedLine_Changes;
var
  R : string;
begin
  Assert.AreEqual(Join(['begin', '  A;', TAB + 'B;', 'end;']),
    Fix(Join(['begin', TAB + 'A;', TAB + 'B;', 'end;']), 2, TabMsg(1), R), R);
end;

// ---- Tabweite aus den Nachbarzeilen (rwE29) ----

// Indy IdSSLOpenSSLHeaders.pas:10183 (minimiert): die Tabelle ist fuer
// Tabweite 8 ausgerichtet - Namen verschiedener Laenge mit 3, 4 bzw. 5 Tabs
// enden alle mit '=' in Spalte 48. Gegenprobe: mit fester Weite 2 (bis
// rwE29) stuende '=' der Zeile in Spalte 24 (9 statt 33 Leerzeichen).
procedure TTestRdxTabsFix.Width8_ReasonCodeTable;
const
  T3 = TAB + TAB + TAB;
var
  R : string;
begin
  Assert.AreEqual(Join([
      '  {$EXTERNALSYM TS_R_BAD_PKCS7_TYPE}',
      '  TS_R_BAD_PKCS7_TYPE' + T3 + TAB + '= 132;',
      '  {$EXTERNALSYM TS_R_BAD_TYPE}',
      '  TS_R_BAD_TYPE' + StringOfChar(' ', 33) + '= 133;',
      '  {$EXTERNALSYM TS_R_CERTIFICATE_VERIFY_ERROR}',
      '  TS_R_CERTIFICATE_VERIFY_ERROR' + T3 + '= 100;',
      '  TS_R_COULD_NOT_SET_ENGINE' + T3 + '= 127;']),
    Fix(Join([
      '  {$EXTERNALSYM TS_R_BAD_PKCS7_TYPE}',
      '  TS_R_BAD_PKCS7_TYPE' + T3 + TAB + '= 132;',
      '  {$EXTERNALSYM TS_R_BAD_TYPE}',
      '  TS_R_BAD_TYPE' + T3 + TAB + TAB + '= 133;',
      '  {$EXTERNALSYM TS_R_CERTIFICATE_VERIFY_ERROR}',
      '  TS_R_CERTIFICATE_VERIFY_ERROR' + T3 + '= 100;',
      '  TS_R_COULD_NOT_SET_ENGINE' + T3 + '= 127;']), 4, TabMsg(16), R), R);
end;

// PascalScript uPSRuntime.pas:6469 (minimiert): '<TAB>      {$else}' steht
// bei Tabweite 8 in Spalte 14 wie die mit 14 Leerzeichen eingerueckten
// Code-Zeilen. Gegenprobe: mit fester Weite 2 rutschte '{$else}' auf
// Spalte 8.
procedure TTestRdxTabsFix.Width8_DirectiveBetweenSpaceLines;
var
  I14, R : string;
begin
  I14 := StringOfChar(' ', 14);
  Assert.AreEqual(Join([
      I14 + 'S := unaligned(P^);',
      TAB + '      {$ifdef FPC_REQUIRES_PROPER_ALIGNMENT}',
      I14 + 'S := unaligned(Q^);',
      I14 + '{$else}',
      I14 + 'S := Q^;',
      TAB + '      {$endif}',
      I14 + 'Inc(N, SizeOf(Single));']),
    Fix(Join([
      I14 + 'S := unaligned(P^);',
      TAB + '      {$ifdef FPC_REQUIRES_PROPER_ALIGNMENT}',
      I14 + 'S := unaligned(Q^);',
      TAB + '      {$else}',
      I14 + 'S := Q^;',
      TAB + '      {$endif}',
      I14 + 'Inc(N, SizeOf(Single));']), 4, TabMsg(1), R), R);
end;

// JVCL DirectShow9.pas:6829 (minimiert): Tab + 17 Leerzeichen bringen '='
// bei Tabweite 8 genau in Spalte 41 der mit Leerzeichen ausgerichteten
// Nachbarn. Gegenprobe: mit fester Weite 2 stuende '=' in Spalte 35.
procedure TTestRdxTabsFix.Width8_SpaceTableAfterTab;
var
  R : string;
begin
  Assert.AreEqual(Join([
      '  ED_EDIT_SEEK_PREROLL' + StringOfChar(' ', 19) + '= ED_BASE+683;',
      '  ED_EDIT_SEEK_BOOKMARK' + StringOfChar(' ', 18) + '= ED_BASE+685;',
      '  ED_EDIT_PREREAD' + StringOfChar(' ', 24) + '= ED_BASE+815;',
      '//']),
    Fix(Join([
      '  ED_EDIT_SEEK_PREROLL' + StringOfChar(' ', 19) + '= ED_BASE+683;',
      '  ED_EDIT_SEEK_BOOKMARK' + StringOfChar(' ', 18) + '= ED_BASE+685;',
      '  ED_EDIT_PREREAD' + TAB + StringOfChar(' ', 17) + '= ED_BASE+815;',
      '//']), 3, TabMsg(18), R), R);
end;

// JVCL gifimage.pas:8067 (minimiert): der var-Block ist fuer Tabweite 8
// ausgerichtet (':' in Spalte 24 hinter 2 bzw. 3 Tabs). Gegenprobe: mit
// fester Weite 2 stuende ':' der Zeile in Spalte 12.
procedure TTestRdxTabsFix.Width8_VarBlock;
const
  T2 = TAB + TAB;
var
  R : string;
begin
  Assert.AreEqual(Join([
      '  var',
      '    i' + T2 + TAB + ': integer;',
      '    Cache' + StringOfChar(' ', 15)
        + ': array[0..CacheSize-1] of TCacheEntry;',
      '    LastEntry' + T2 + ': integer;',
      '    Scanline' + T2 + ': PRGBTriple;']),
    Fix(Join([
      '  var',
      '    i' + T2 + TAB + ': integer;',
      '    Cache' + T2 + ': array[0..CacheSize-1] of TCacheEntry;',
      '    LastEntry' + T2 + ': integer;',
      '    Scanline' + T2 + ': PRGBTriple;']), 3, TabMsg(10), R), R);
end;

// Die Nachbarzeile passt zu Tabweite 4 wie zu 8 ('=' in Spalte 8), zur
// Vorgabe 2 nicht: welche gilt, ist offen - Sperre. Gegenprobe: bis rwE29
// ersetzte die Hilfe mit Weite 2 ('ABCDE =', '=' in Spalte 6).
procedure TTestRdxTabsFix.TwoWidthsAlike_NoHelp;
var
  R : string;
begin
  Assert.AreEqual('', Fix(Join(['X' + StringOfChar(' ', 7) + '= 1;',
    'ABCDE' + TAB + '= 2;']), 2, TabMsg(6), R));
  Assert.IsTrue(Pos(RS_AMBIGUOUS, R) > 0, R);
end;

// Passt die Nachbarzeile zur Vorgabe 2 und zu 4 gleich ('=' in Spalte 4),
// bleibt es bei 2. Pinnt die Regel; auch vor rwE29 gruen (immer 2).
procedure TTestRdxTabsFix.TieWithDefault_KeepsDefault;
var
  R : string;
begin
  Assert.AreEqual(Join(['AB  = 1;', 'ABC = 2;']),
    Fix(Join(['AB  = 1;', 'ABC' + TAB + '= 2;']), 2, TabMsg(4), R), R);
end;

// Der Hinweis nennt die Weite und woher sie kommt. Gegenprobe: bis rwE29
// stand fest 'Tabweite 2 (Annahme)' (FIX_HINTS) - auch bei der Tabelle.
procedure TTestRdxTabsFix.Plan_Hint_NamesWidth;
var
  SL : TStringList;
  F  : TLeakFinding;
  O  : TRdxFixOutcome;
begin
  SL := TStringList.Create;
  F := nil;
  try
    F := TLeakFinding.New('t.pas', '', 3, TabMsg(18), fkTabulationCharacter);
    SL.Text := Join([
      '  ED_EDIT_SEEK_PREROLL' + StringOfChar(' ', 19) + '= ED_BASE+683;',
      '  ED_EDIT_SEEK_BOOKMARK' + StringOfChar(' ', 18) + '= ED_BASE+685;',
      '  ED_EDIT_PREREAD' + TAB + StringOfChar(' ', 17) + '= ED_BASE+815;']);
    O := TRdxFixTable.FixFor(nil, SL, F, nil);
    Assert.IsTrue(O.Enabled, O.Reason);
    Assert.IsTrue(Pos('Tabweite 8, wie', O.Hint) > 0, O.Hint);
    Assert.AreEqual<Integer>(0, Pos('Annahme', O.Hint), O.Hint);
  finally
    F.Free;
    SL.Free;
  end;
end;

procedure TTestRdxTabsFix.Plan_Adapter;
var
  SL : TStringList;
  F  : TLeakFinding;
  O  : TRdxFixOutcome;
begin
  SL := TStringList.Create;
  F := nil;
  try
    F := TLeakFinding.New('t.pas', '', 2, TabMsg(1), fkTabulationCharacter);
    SL.Text := Join(['begin', TAB + 'A;', 'end;']);
    O := TRdxFixTable.FixFor(nil, SL, F, nil);
    Assert.IsTrue(O.Enabled, O.Reason);
    Assert.AreEqual<Integer>(1, Length(O.Edits));
    Assert.AreEqual(TAB, O.Edits[0].Expected);
    Assert.AreEqual('  ', O.Edits[0].NewText);
    // Ohne Beweis in den Nachbarzeilen: die Annahme 2 (rwE29).
    Assert.IsTrue(Pos('Tabweite 2 (Annahme', O.Hint) > 0, O.Hint);
    // Ohne Datei keine Hilfe.
    O := TRdxFixTable.FixFor(nil, nil, F, nil);
    Assert.IsFalse(O.Enabled);
    Assert.AreEqual<Integer>(0, Length(O.Edits));
    Assert.AreNotEqual('', O.Reason);
  finally
    F.Free;
    SL.Free;
  end;
end;

// ---- echter Detektor ----

procedure TTestRdxTabsFix.Detector_RoundTrip;
var
  Bad, Good : string;
begin
  Bad := InUnit(Join(['procedure P;', 'begin', TAB + 'A;',
    TAB + TAB + 'B;', ' ' + TAB + 'C := 1;', 'end;']));
  Good := InUnit(Join(['procedure P;', 'begin', '  A;', '    B;',
    '  C := 1;', 'end;']));
  Assert.AreEqual<Integer>(3, Length(Detect(Bad)));
  Assert.AreEqual(Good, FixAll(Bad));
  Assert.AreEqual<Integer>(0, Length(Detect(Good)));
end;

procedure TTestRdxTabsFix.Detector_StringOnly_NoHelp;
var
  Src  : string;
  Seen : TArray<TSeen>;
  SL   : TStringList;
  F    : TLeakFinding;
  O    : TRdxFixOutcome;
begin
  Src := InUnit(Join(['procedure P;', 'begin', '  S := ''a' + TAB + 'b'';',
    'end;']));
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen));
  SL := TStringList.Create;
  F := nil;
  try
    F := TLeakFinding.New('t.pas', '', Seen[0].Line, Seen[0].Msg,
      fkTabulationCharacter);
    SL.Text := Src;
    O := TRdxFixTable.FixFor(nil, SL, F, nil);
    Assert.IsFalse(O.Enabled);
    Assert.IsTrue(Pos(RS_NOT_CODE, O.Reason) > 0, O.Reason);
  finally
    F.Free;
    SL.Free;
  end;
end;

procedure TTestRdxTabsFix.Detector_CatalogExample;
var
  Meta      : TRuleMeta;
  Bad, Good : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkTabulationCharacter);
  // Das Beispiel nennt den Tab als '<TAB>'.
  Bad := StringReplace(Meta.BadExample, '<TAB>', TAB, [rfReplaceAll]);
  Assert.IsTrue(Pos(TAB, Bad) > 0, Meta.BadExample);
  Bad := InUnit(CatalogText(Bad));
  Good := InUnit(CatalogText(Meta.GoodExample));
  Assert.IsTrue(Length(Detect(Bad)) > 0, 'der Detektor meldet das Beispiel');
  Assert.AreEqual(Good, FixAll(Bad));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxTabsFix);

end.

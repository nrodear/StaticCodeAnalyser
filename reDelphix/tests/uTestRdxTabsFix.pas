unit uTestRdxTabsFix;

// Editorhilfe SCA061 TabulationCharacter (uRdxTabsFix): Tabs der gemeldeten
// Zeile -> Leerzeichen bis zum naechsten Tabstopp (Tabweite 2), nur im
// Code. Auf Text (Gegenproben: String, Kommentar, verschobene Zeile) und
// mit dem ECHTEN Detektor (Rundlauf, Katalog-Beispiel) - nur Delphi,
// reDelphix.Test. Tabs im Quelltext dieser Unit stehen als TAB = #9.

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
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText
  uTestRdxTextKit;       // Join, Apply

const
  TAB = #9;
  // Gruende (Teile davon) der Hilfe.
  RS_MOVED    = 'kein Tab an der gemeldeten Stelle';
  RS_NOT_CODE = 'in einem String oder Kommentar';

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

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt (ueber TRdxFixTable.FixFor, Adapter PlanTabs).
function FixAll(const ASource: string): string;
const
  MAX_PASSES = 10;
var
  Seen : TArray<TSeen>;
  SL   : TStringList;
  F    : TLeakFinding;
  O    : TRdxFixOutcome;
  Pass : Integer;
begin
  Result := ASource;
  for Pass := 1 to MAX_PASSES do
  begin
    Seen := Detect(Result);
    if Length(Seen) = 0 then Exit;
    SL := TStringList.Create;
    F := TLeakFinding.New('t.pas', '', Seen[0].Line, Seen[0].Msg,
      fkTabulationCharacter);
    try
      SL.Text := Result;
      O := TRdxFixTable.FixFor(nil, SL, F, nil);
      Assert.IsTrue(O.Enabled, Format('Zeile %d: %s', [Seen[0].Line, O.Reason]));
      Result := Apply(Result, O.Edits);
    finally
      F.Free;
      SL.Free;
    end;
  end;
  Assert.Fail('der Detektor meldet nach 10 Runden noch');
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
  Assert.AreEqual(R_NO_COLUMN, R);
end;

procedure TTestRdxTabsFix.OnlyReportedLine_Changes;
var
  R : string;
begin
  Assert.AreEqual(Join(['begin', '  A;', TAB + 'B;', 'end;']),
    Fix(Join(['begin', TAB + 'A;', TAB + 'B;', 'end;']), 2, TabMsg(1), R), R);
end;

procedure TTestRdxTabsFix.Plan_Adapter;
var
  SL : TStringList;
  F  : TLeakFinding;
  O  : TRdxFixOutcome;
begin
  SL := TStringList.Create;
  F := TLeakFinding.New('t.pas', '', 2, TabMsg(1), fkTabulationCharacter);
  try
    SL.Text := Join(['begin', TAB + 'A;', 'end;']);
    O := TRdxFixTable.FixFor(nil, SL, F, nil);
    Assert.IsTrue(O.Enabled, O.Reason);
    Assert.AreEqual<Integer>(1, Length(O.Edits));
    Assert.AreEqual(TAB, O.Edits[0].Expected);
    Assert.AreEqual('  ', O.Edits[0].NewText);
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
  F := TLeakFinding.New('t.pas', '', Seen[0].Line, Seen[0].Msg,
    fkTabulationCharacter);
  try
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

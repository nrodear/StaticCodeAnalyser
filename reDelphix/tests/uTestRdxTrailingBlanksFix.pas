unit uTestRdxTrailingBlanksFix;

// Editorhilfe SCA063 TrailingWhitespace (uRdxTrailingBlanksFix) - nur
// Delphi, reDelphix.Test (der echte Detektor und der Parser gehoeren dazu):
//   Planer auf Text: Leerzeichen, Tabs, nur Leerraum, Kommentare und
//     Direktiven (erlaubt), mehrzeiliger oder offener String (keine Hilfe),
//     verschobene Zeile, falsche Spalte, fehlende Spalte;
//   Rundlauf mit dem ECHTEN Detektor: danach meldet er nichts mehr, der
//     Rest des Textes bleibt gleich; Katalog-Beispiel (bad -> good).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxTrailingBlanksFix = class
  public
    // ---- Planer auf Text ----
    [Test] procedure Spaces_AreRemoved;
    [Test] procedure Tabs_AndMixed_AreRemoved;
    [Test] procedure BlankOnlyLine_BecomesEmpty;
    [Test] procedure InLineComment_IsRemoved;
    [Test] procedure InBlockComment_IsRemoved;
    [Test] procedure AfterDirective_IsRemoved;
    [Test] procedure AfterMultiLineStringClose_IsRemoved;
    [Test] procedure ColumnOf_ReadsMessage;
    // ---- Gegenproben ----
    [Test] procedure InsideMultiLineString_NoHelp;
    [Test] procedure MultiLineStringOpener_NoHelp;
    [Test] procedure OpenString_NoHelp;
    [Test] procedure MovedLine_NoHelp;
    [Test] procedure WrongColumn_NoHelp;
    [Test] procedure NoColumn_NoHelp;
    [Test] procedure NoFile_NoHelp;
    // ---- echter Detektor ----
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_CatalogExample;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uTrailingWhitespace,
  uRdxBufferMath, uRdxCodeMap, uRdxRecipeRunner, uRdxTrailingBlanksFix,
  uTestRdxTextKit,      // Join, Apply
  uTestRdxDetectorKit;  // DetectSource, TSeen

const
  // Teile der Gruende (uRdxTrailingBlanksFix) - die Tests pruefen den Sinn,
  // nicht den ganzen Wortlaut.
  REASON_MOVED  = 'gemeldeten Stelle';
  REASON_STRING = 'String';
  REASON_NOFILE = 'keine Datei';
  QUOTE3        = #39#39#39;
  QUOTE1        = #39;
  TAG_SPACES    = '<-- trailing spaces';
  FILE_NAME     = 't.pas';

// Die Meldung, wie der Detektor sie schreibt.
function BlanksMsg(ACol: Integer): string;
begin
  Result := Format('Trailing whitespace from column %d - configure editor '
    + 'to trim on save.', [ACol]);
end;

// Eine Unit mit den Zeilen ALines als Rumpf einer Routine (ab Zeile 6).
function InUnit(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation', 'procedure P;'])
    + #13#10 + 'begin' + #13#10 + Join(ALines) + #13#10 + Join(['end;', 'end.']);
end;

// Die Hilfe fuer Zeile ALine mit der Meldung AMessage ueber den Adapter der
// Tabelle: neuer Text oder '' bei Ablehnung (AReason).
function Fix(const ASource: string; ALine: Integer; const AMessage: string;
  out AReason: string): string;
var
  SL      : TStringList;
  Finding : TLeakFinding;
  O       : TRdxFixOutcome;
begin
  Result := '';
  SL := TStringList.Create;
  Finding := TLeakFinding.New(FILE_NAME, '', ALine, AMessage,
    fkTrailingWhitespace);
  try
    SL.Text := ASource;
    O := PlanTrailingBlanks(nil, SL, Finding, nil);
    AReason := O.Reason;
    if O.Enabled then
      Result := Apply(ASource, O.Edits);
  finally
    Finding.Free;
    SL.Free;
  end;
end;

procedure RunTrailing(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TTrailingWhitespaceDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_tw_', ASource, fkTrailingWhitespace, RunTrailing);
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
        fkTrailingWhitespace);
      try
        O := PlanTrailingBlanks(nil, SL, F, nil);
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

{ ---- Planer auf Text ---- }

procedure TTestRdxTrailingBlanksFix.Spaces_AreRemoved;
var
  R : string;
begin
  Assert.AreEqual(InUnit(['  DoStuff;', '  More;']),
    Fix(InUnit(['  DoStuff;   ', '  More;']), 6, BlanksMsg(11), R), R);
end;

procedure TTestRdxTrailingBlanksFix.Tabs_AndMixed_AreRemoved;
var
  R : string;
begin
  Assert.AreEqual(InUnit(['  DoStuff;']),
    Fix(InUnit(['  DoStuff; ' + #9 + ' ' + #9]), 6, BlanksMsg(11), R), R);
end;

procedure TTestRdxTrailingBlanksFix.BlankOnlyLine_BecomesEmpty;
var
  R : string;
begin
  Assert.AreEqual(InUnit(['  A;', '', '  B;']),
    Fix(InUnit(['  A;', '    ' + #9, '  B;']), 7, BlanksMsg(1), R), R);
end;

procedure TTestRdxTrailingBlanksFix.InLineComment_IsRemoved;
var
  R : string;
begin
  Assert.AreEqual(InUnit(['  A; // note']),
    Fix(InUnit(['  A; // note  ']), 6, BlanksMsg(13), R), R);
end;

procedure TTestRdxTrailingBlanksFix.InBlockComment_IsRemoved;
var
  R : string;
begin
  // Die Zeile liegt in einem Block-Kommentar: der Leerraum ist harmlos.
  Assert.AreEqual(InUnit(['  { first', '  second }']),
    Fix(InUnit(['  { first   ', '  second }']), 6, BlanksMsg(10), R), R);
end;

procedure TTestRdxTrailingBlanksFix.AfterDirective_IsRemoved;
var
  R : string;
begin
  Assert.AreEqual(InUnit(['{$IFDEF X}', '  A;', '{$ENDIF}']),
    Fix(InUnit(['{$IFDEF X}  ', '  A;', '{$ENDIF}']), 6, BlanksMsg(11), R), R);
end;

procedure TTestRdxTrailingBlanksFix.AfterMultiLineStringClose_IsRemoved;
var
  R : string;
begin
  // Die Zeile mit den schliessenden Quotes: dahinter ist wieder Code.
  Assert.AreEqual(
    InUnit(['  S := ' + QUOTE3, '    text', '  ' + QUOTE3 + ';']),
    Fix(InUnit(['  S := ' + QUOTE3, '    text', '  ' + QUOTE3 + ';  ']), 8,
      BlanksMsg(7), R), R);
end;

procedure TTestRdxTrailingBlanksFix.ColumnOf_ReadsMessage;
begin
  Assert.AreEqual<Integer>(12, TRdxTrailingBlanksFix.ColumnOf(BlanksMsg(12)));
  Assert.AreEqual<Integer>(0, TRdxTrailingBlanksFix.ColumnOf('Line ends with blanks'));
end;

{ ---- Gegenproben ---- }

procedure TTestRdxTrailingBlanksFix.InsideMultiLineString_NoHelp;
var
  R : string;
begin
  // Der Leerraum am Ende einer Zeile im String ist Inhalt des Strings.
  Assert.AreEqual('',
    Fix(InUnit(['  S := ' + QUOTE3, '    text  ', '  ' + QUOTE3 + ';']), 7,
      BlanksMsg(9), R));
  Assert.IsTrue(Pos(REASON_STRING, R) > 0, R);
end;

procedure TTestRdxTrailingBlanksFix.MultiLineStringOpener_NoHelp;
var
  R : string;
begin
  Assert.AreEqual('',
    Fix(InUnit(['  S := ' + QUOTE3 + '  ', '    text', '  ' + QUOTE3 + ';']),
      6, BlanksMsg(11), R));
  Assert.IsTrue(Pos(REASON_STRING, R) > 0, R);
end;

procedure TTestRdxTrailingBlanksFix.OpenString_NoHelp;
var
  R : string;
begin
  // Ein nicht geschlossener String bis zum Zeilenende.
  Assert.AreEqual('', Fix(InUnit(['  S := ' + QUOTE1 + 'abc  ']), 6,
    BlanksMsg(12), R));
  Assert.IsTrue(Pos(REASON_STRING, R) > 0, R);
end;

procedure TTestRdxTrailingBlanksFix.MovedLine_NoHelp;
var
  R : string;
begin
  // Die Zeile hat keinen Leerraum am Ende (schon bereinigt oder verschoben).
  Assert.AreEqual('', Fix(InUnit(['  DoStuff;']), 6, BlanksMsg(11), R));
  Assert.IsTrue(Pos(REASON_MOVED, R) > 0, R);
  Assert.AreEqual('', Fix(InUnit(['  DoStuff;']), 99, BlanksMsg(1), R));
  Assert.IsTrue(Pos(REASON_MOVED, R) > 0, R);
end;

procedure TTestRdxTrailingBlanksFix.WrongColumn_NoHelp;
var
  R : string;
begin
  // Spalte mitten im Text, hinter dem Zeilenende und mitten in der Endfolge.
  Assert.AreEqual('', Fix(InUnit(['  DoStuff;   ']), 6, BlanksMsg(5), R));
  Assert.IsTrue(Pos(REASON_MOVED, R) > 0, R);
  Assert.AreEqual('', Fix(InUnit(['  DoStuff;   ']), 6, BlanksMsg(99), R));
  Assert.IsTrue(Pos(REASON_MOVED, R) > 0, R);
  Assert.AreEqual('', Fix(InUnit(['  DoStuff;   ']), 6, BlanksMsg(12), R));
  Assert.IsTrue(Pos(REASON_MOVED, R) > 0, R);
end;

procedure TTestRdxTrailingBlanksFix.NoColumn_NoHelp;
var
  R : string;
begin
  Assert.AreEqual('', Fix(InUnit(['  DoStuff;   ']), 6, 'Trailing blanks', R));
  Assert.AreEqual(R_NO_COLUMN, R);
end;

procedure TTestRdxTrailingBlanksFix.NoFile_NoHelp;
var
  F : TLeakFinding;
  O : TRdxFixOutcome;
begin
  F := TLeakFinding.New(FILE_NAME, '', 6, BlanksMsg(11), fkTrailingWhitespace);
  try
    O := PlanTrailingBlanks(nil, nil, F, nil);
  finally
    F.Free;
  end;
  Assert.IsFalse(O.Enabled);
  Assert.IsTrue(Pos(REASON_NOFILE, O.Reason) > 0, O.Reason);
end;

{ ---- echter Detektor ---- }

procedure TTestRdxTrailingBlanksFix.Detector_RoundTrip;
var
  Fixed : string;
begin
  Fixed := FixAll(InUnit(['  A;  ', '  B; // c ' + #9, '  { d  ',
    '  e }', '    ' + #9, '  C;']));
  Assert.AreEqual(InUnit(['  A;', '  B; // c', '  { d', '  e }', '', '  C;']),
    Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)), 'der Detektor schweigt');
end;

procedure TTestRdxTrailingBlanksFix.Detector_CatalogExample;
var
  Meta : TRuleMeta;
  Bad  : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkTrailingWhitespace);
  // Das Beispiel markiert den Leerraum mit einem Pfeil; ohne ihn endet die
  // Zeile auf den Leerzeichen.
  Assert.IsTrue(Pos(TAG_SPACES, Meta.BadExample) > 0, Meta.BadExample);
  Bad := StringReplace(Meta.BadExample, TAG_SPACES, '', []);
  Assert.AreEqual(InUnit([Meta.GoodExample]), FixAll(InUnit([Bad])));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxTrailingBlanksFix);

end.

unit uTestFormatterMarker;

// Tests fuer TFormatterMarkerDetector (SCA206, Nico-Entscheide 2026-11-06):
// Formatter-Marker {(*} / {*)} falsch geschrieben (Leerraum) oder ohne
// Partner (Start ohne Ende, Ende ohne Start, zweiter Start im offenen
// Bereich).
//
// Der Detektor liest den Dateitext (AcquireLines) - die Tests laufen ueber
// FindingsOfFile (dort registriert), die Unterdrueckung ueber die
// Produktions-Pipeline (FindingsViaPipeline).
//
// Geprueft wird immer die GANZE Fundliste der Regel: Zahl, Zeile und
// Meldung je Fund (CheckFindings), nicht nur die Anzahl.
//
// Jede Negativprobe steht mit einer WACHE in derselben Quelle: ein
// einzelnes {*)} ohne offenen Bereich (F2) HINTER dem Doppelgaenger eines
// Starts, Doppelgaenger eines Endes stehen dahinter. Erwartet ist genau der
// eine Fund an der Wache. Ohne Detektor ist jeder Test damit rot (0 Funde);
// zaehlt der Detektor einen Start-Doppelgaenger faelschlich als Start,
// schliesst die Wache ihn (0 Funde); zaehlt er ein End-Doppelgaenger, kommt
// ein zweites F2 dazu; haelt er ihn fuer einen kaputten Marker (F4), steht
// ein Fund auf der falschen Zeile.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFormatterMarker = class
  public
    // ---- Melden: F1-F4 ----------------------------------------------------
    [Test] procedure StartWithoutEnd_Reported;
    [Test] procedure EndWithoutStart_Reported;
    [Test] procedure SecondStartInOpenRegion_Reported;
    [Test] procedure BlankInsideStart_Reported;
    [Test] procedure BlankInsideEnd_Reported;
    [Test] procedure TabInsideStart_Reported;
    [Test] procedure BlanksInBothMarkers_TwoMalformed;
    [Test] procedure EndBeforeStart_TwoFindings;
    [Test] procedure Finding_IsHintMediumFileLevel;
    // ---- Nicht melden (je mit Wache) --------------------------------------
    [Test] procedure BalancedPair_NoFinding;
    [Test] procedure PairOnOneLine_NoFinding;
    [Test] procedure TwoPairs_NoFinding;
    [Test] procedure MarkerInString_NoFinding;
    [Test] procedure MarkerInLineComment_NoFinding;
    [Test] procedure MarkerInParenComment_NoFinding;
    [Test] procedure MarkerInMultiLineString_NoFinding;
    [Test] procedure FootnoteBrace_NoFinding;
    [Test] procedure CommentedOutBlock_NoFinding;
    [Test] procedure BraceParenComment_NoFinding;
    [Test] procedure DirectiveLookalike_NoFinding;
    [Test] procedure IfdefBranches_CountedRaw;
    [Test] procedure NoMarker_NoFinding;
    // ---- Pipeline, Katalog, Profile ---------------------------------------
    [Test] procedure NoInspection_Suppresses;
    [Test] procedure CatalogExample_BadReported_GoodClean;
    [Test] procedure Profiles_DefaultStrictCodeQuality_NotIdeFastBugsOnly;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uRuleCatalog,
  uTestFindingHelper;

const
  CRLF = #13#10;
  // Drei Apostrophe: oeffnet bzw. schliesst einen Delphi-12-Mehrzeilenstring.
  Q3 = '''''''';

  // Die festen Meldungen (englisch, Teil des Fingerprints) - woertlich
  // gepinnt: eine Textaenderung bewegt jeden Bestandsfund.
  MSG_F1 = 'Formatter marker {(*} is never closed by {*)} - GExperts, ' +
    'CnWizards and JCF leave the rest of the file unformatted';
  MSG_F2 = 'Formatter marker {*)} has no opening {(*} - it closes nothing, ' +
    'the code above it is formatted';
  MSG_F3 = 'Second {(*} inside an open formatter-off region - the markers ' +
    'do not nest, the first {*)} already switches formatting back on';

// F4 traegt den Markertext (Steuerzeichen als '#9') und die exakte Form.
function MsgF4(const AText, AExact: string): string;
begin
  Result := Format('Malformed formatter marker ''%s'' - formatters ' +
    'recognise only the exact ''%s'' without blanks, so this marker is ' +
    'ignored', [AText, AExact]);
end;

// Eine Quelle aus Zeilen (je mit CRLF) - Zeile k des Arrays ist Zeile k + 1.
function Src(const ALines: array of string): string;
var
  i : Integer;
begin
  Result := '';
  for i := 0 to High(ALines) do
    Result := Result + ALines[i] + CRLF;
end;

// Prueft die SCA206-Funde von ASrc (FindingsOfFile) in Reihenfolge gegen
// die erwarteten Zeilen und Meldungen. Funde anderer Regeln zaehlen nicht.
procedure CheckFindings(const ASrc: string; const ALines: array of Integer;
  const AMsgs: array of string);
var
  F   : TObjectList<TLeakFinding>;
  Own : TList<TLeakFinding>;
  X   : TLeakFinding;
  k   : Integer;
begin
  F := TFindingHelper.FindingsOfFile(ASrc);
  Own := TList<TLeakFinding>.Create;
  try
    for X in F do
      if X.Kind = fkFormatterMarker then
        Own.Add(X);
    Assert.AreEqual<Integer>(Length(ALines), Own.Count,
      'Zahl der SCA206-Funde');
    for k := 0 to Own.Count - 1 do
    begin
      Assert.AreEqual(IntToStr(ALines[k]), Own[k].LineNumber,
        Format('Zeile von Fund %d', [k + 1]));
      Assert.AreEqual(AMsgs[k], Own[k].MissingVar,
        Format('Meldung von Fund %d', [k + 1]));
    end;
  finally
    Own.Free;
    F.Free;
  end;
end;

// Kein SCA206-Fund in ASrc. Nur zusammen mit einer Positivprobe in
// demselben Test verwenden - allein waere er ohne Detektor gruen.
procedure CheckNoFindings(const ASrc: string);
var
  F : TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(ASrc);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFormatterMarker),
      'Zahl der SCA206-Funde');
  finally
    F.Free;
  end;
end;

{ ---- Melden ---------------------------------------------------------------- }

procedure TTestFormatterMarker.StartWithoutEnd_Reported;
// F1: der Formatter formatiert ab Zeile 3 nichts mehr.
begin
  CheckFindings(Src([
    'unit A;',                 // 1
    'interface',               // 2
    '{(*}',                    // 3
    'const X = 1;',            // 4
    'implementation',          // 5
    'end.']),                  // 6
    [3], [MSG_F1]);
end;

procedure TTestFormatterMarker.EndWithoutStart_Reported;
// F2: das Ende schliesst nichts.
begin
  CheckFindings(Src([
    'unit A;',                 // 1
    'interface',               // 2
    '{*)}',                    // 3
    'implementation',          // 4
    'end.']),                  // 5
    [3], [MSG_F2]);
end;

procedure TTestFormatterMarker.SecondStartInOpenRegion_Reported;
// F3 an Zeile 5 und nur dort: der Bereich ist am Ende zu (kein F1 an
// Zeile 3), denn ein Schalter braucht nur EIN Ende.
begin
  CheckFindings(Src([
    'unit A;',                 // 1
    'interface',               // 2
    '{(*}',                    // 3
    'const X = 1;',            // 4
    '{(*}',                    // 5
    'const Y = 2;',            // 6
    '{*)}',                    // 7
    'implementation',          // 8
    'end.']),                  // 9
    [5], [MSG_F3]);
end;

procedure TTestFormatterMarker.BlankInsideStart_Reported;
// F4 am Start; er zaehlt in der Bilanz als gemeint - KEIN F2 am
// korrekten Ende in Zeile 5.
begin
  CheckFindings(Src([
    'unit A;',                 // 1
    'interface',               // 2
    '{ (*}',                   // 3
    'const X = 1;',            // 4
    '{*)}',                    // 5
    'implementation',          // 6
    'end.']),                  // 7
    [3], [MsgF4('{ (*}', '{(*}')]);
end;

procedure TTestFormatterMarker.BlankInsideEnd_Reported;
// F4 am Ende; es schliesst den Bereich - KEIN F1 am Start in Zeile 3.
begin
  CheckFindings(Src([
    'unit A;',                 // 1
    'interface',               // 2
    '{(*}',                    // 3
    'const X = 1;',            // 4
    '{*) }',                   // 5
    'implementation',          // 6
    'end.']),                  // 7
    [5], [MsgF4('{*) }', '{*)}')]);
end;

procedure TTestFormatterMarker.TabInsideStart_Reported;
// Tab statt Blank; die Meldung zeigt ihn als '#9'.
begin
  CheckFindings(Src([
    'unit A;',                 // 1
    'interface',               // 2
    '{(*'#9'}',                // 3
    'const X = 1;',            // 4
    '{*)}',                    // 5
    'implementation',          // 6
    'end.']),                  // 7
    [3], [MsgF4('{(*#9}', '{(*}')]);
end;

procedure TTestFormatterMarker.BlanksInBothMarkers_TwoMalformed;
// Beide Marker kaputt: zwei F4, keine Bilanzmeldung dazu.
begin
  CheckFindings(Src([
    'unit A;',                 // 1
    'interface',               // 2
    '{ (* }',                  // 3
    'const X = 1;',            // 4
    '{ *)}',                   // 5
    'implementation',          // 6
    'end.']),                  // 7
    [3, 5], [MsgF4('{ (* }', '{(*}'), MsgF4('{ *)}', '{*)}')]);
end;

procedure TTestFormatterMarker.EndBeforeStart_TwoFindings;
// Das Korpusmuster (JCF BasicStats.pas): das Ende steht vor dem Start.
// F2 am Ende (Zeile 3), F1 am Start (Zeile 6) - in Zeilenreihenfolge,
// obwohl F1 erst am Dateiende feststeht.
begin
  CheckFindings(Src([
    'unit A;',                 // 1
    'interface',               // 2
    '{*)}',                    // 3
    'const X = 1;',            // 4
    'implementation',          // 5
    '{(*}',                    // 6
    'procedure P;',            // 7
    'begin',                   // 8
    'end;',                    // 9
    'end.']),                  // 10
    [3, 6], [MSG_F2, MSG_F1]);
end;

procedure TTestFormatterMarker.Finding_IsHintMediumFileLevel;
// Hint (nur Formatierung, nie das Kompilat), fcMedium (F1 kann Absicht
// sein), Code Smell, Datei-Ebene ohne Methode.
var
  F : TObjectList<TLeakFinding>;
  X : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(Src([
    'unit A;', 'interface', '{(*}', 'implementation', 'end.']));
  try
    X := TFindingHelper.FirstOf(F, fkFormatterMarker);
    Assert.IsNotNull(X, 'Fund fehlt');
    Assert.AreEqual<Integer>(Ord(lsHint), Ord(X.Severity), 'Schweregrad');
    Assert.AreEqual<Integer>(Ord(fcMedium), Ord(X.Confidence), 'Konfidenz');
    Assert.AreEqual<Integer>(Ord(ftCodeSmell), Ord(KindFindingType(X.Kind)),
      'Typ');
    Assert.AreEqual('', X.MethodName, 'Methode');
    Assert.AreEqual('FormatterMarker', KindName(fkFormatterMarker), 'Name');
  finally
    F.Free;
  end;
end;

{ ---- Nicht melden ----------------------------------------------------------- }

procedure TTestFormatterMarker.BalancedPair_NoFinding;
begin
  CheckFindings(Src([
    'unit A;',                 // 1
    'interface',               // 2
    '{(*}',                    // 3
    'const X = 1;',            // 4
    '{*)}',                    // 5
    '{*)}',                    // 6  Wache
    'implementation',          // 7
    'end.']),                  // 8
    [6], [MSG_F2]);
end;

procedure TTestFormatterMarker.PairOnOneLine_NoFinding;
// Zwei Kommentare auf einer Zeile: der Lauf liest die Zeile hinter dem
// ersten '}' weiter.
begin
  CheckFindings(Src([
    'unit A;',                                  // 1
    'implementation',                           // 2
    'procedure P(A: Boolean);',                 // 3
    'begin',                                    // 4
    '  {(*} if A then Exit; {*)}',              // 5
    'end;',                                     // 6
    '{*)}',                                     // 7  Wache
    'end.']),                                   // 8
    [7], [MSG_F2]);
end;

procedure TTestFormatterMarker.TwoPairs_NoFinding;
begin
  CheckFindings(Src([
    'unit A;',                 // 1
    'interface',               // 2
    '{(*}',                    // 3
    'const X = 1;',            // 4
    '{*)}',                    // 5
    '{(*}',                    // 6
    'const Y = 2;',            // 7
    '{*)}',                    // 8
    '{*)}',                    // 9  Wache
    'implementation',          // 10
    'end.']),                  // 11
    [9], [MSG_F2]);
end;

procedure TTestFormatterMarker.MarkerInString_NoFinding;
// JCF-Konstanten-Muster (FormatFlags.pas): Marker in String-Literalen,
// auch mit '' im selben Literal davor.
begin
  CheckFindings(Src([
    'unit A;',                                  // 1
    'interface',                                // 2
    'const',                                    // 3
    '  S = ''it''''s {(*}'';',                  // 4
    '{*)}',                                     // 5  Wache
    '  T = ''{*)}'';',                          // 6
    'implementation',                           // 7
    'end.']),                                   // 8
    [5], [MSG_F2]);
end;

procedure TTestFormatterMarker.MarkerInLineComment_NoFinding;
// Doku-Muster aus CnScanners.pas: Marker in //-Kommentaren.
begin
  CheckFindings(Src([
    'unit A;',                                  // 1
    'interface',                                // 2
    '// {(*} start to not format',              // 3
    'const X = 1; // {(*}',                     // 4
    '{*)}',                                     // 5  Wache
    '// {*)} end to not format',                // 6
    'implementation',                           // 7
    'end.']),                                   // 8
    [5], [MSG_F2]);
end;

procedure TTestFormatterMarker.MarkerInParenComment_NoFinding;
// In (* *) ist ein { nur Text - einzeilig und ueber Zeilen.
begin
  CheckFindings(Src([
    'unit A;',                                  // 1
    'interface',                                // 2
    '(* use {(*} here *)',                      // 3
    '(*',                                       // 4
    '  {(*}',                                   // 5
    '*)',                                       // 6
    '{*)}',                                     // 7  Wache
    '(* and {*)} there *)',                     // 8
    'implementation',                           // 9
    'end.']),                                   // 10
    [7], [MSG_F2]);
end;

procedure TTestFormatterMarker.MarkerInMultiLineString_NoFinding;
// Delphi-12-Mehrzeilenstring: die Zeilen dazwischen sind String, kein
// Code. Hinter dem schliessenden ''' ist wieder Code (die Wache in
// Zeile 6 steht deshalb auf einer eigenen Zeile danach).
begin
  CheckFindings(Src([
    'unit A;',                                  // 1
    'interface',                                // 2
    'const S = ' + Q3,                          // 3
    '  {(*}',                                   // 4
    '  ' + Q3 + ';',                            // 5
    '{*)}',                                     // 6  Wache
    'implementation',                           // 7
    'end.']),                                   // 8
    [6], [MSG_F2]);
end;

procedure TTestFormatterMarker.FootnoteBrace_NoFinding;
// Fussnoten-Spalte aus den JvRichEd-Kopien (jvcl, 96 Stellen im Korpus):
// '(*)' ist kein '(*', also auch kein kaputter Marker.
begin
  CheckFindings(Src([
    'unit A;',                                  // 1
    'interface',                                // 2
    'const',                                    // 3
    '  CFM_SMALLCAPS = $0040; { (*)    }',      // 4
    '{*)}',                                     // 5  Wache
    'implementation',                           // 6
    'end.']),                                   // 7
    [5], [MSG_F2]);
end;

procedure TTestFormatterMarker.CommentedOutBlock_NoFinding;
// Auskommentierter Block in { } ueber mehrere Zeilen: das '(*' in Zeile 4
// ist Text. Ein Lauf, der den { }-Zustand nicht ueber die Zeile traegt,
// liest dort einen (* *)-Kommentar, der erst am '*)' der Wache endet -
// dann fehlt der Fund.
begin
  CheckFindings(Src([
    'unit A;',                                  // 1
    'interface',                                // 2
    '{',                                        // 3
    '  (*',                                     // 4
    '  X: Integer;',                            // 5
    '}',                                        // 6
    '{*)}',                                     // 7  Wache
    'implementation',                           // 8
    'end.']),                                   // 9
    [7], [MSG_F2]);
end;

procedure TTestFormatterMarker.BraceParenComment_NoFinding;
// '{(* ... *)}' ist EIN { }-Kommentar (F6, Gebiet von SCA070), kein
// Marker - einzeilig wie mehrzeilig.
begin
  CheckFindings(Src([
    'unit A;',                                  // 1
    'interface',                                // 2
    '{(* old code *)}',                         // 3
    '{(*',                                      // 4
    '  const Old = 1;',                         // 5
    '*)}',                                      // 6
    '{*)}',                                     // 7  Wache
    'implementation',                           // 8
    'end.']),                                   // 9
    [7], [MSG_F2]);
end;

procedure TTestFormatterMarker.DirectiveLookalike_NoFinding;
// Direktiven ({$...} und (*$...*)) sind nie Kandidaten, auch wenn ein
// '(*' darin steht.
begin
  CheckFindings(Src([
    'unit A;',                                  // 1
    'interface',                                // 2
    '{$MESSAGE HINT ''(*''}',                   // 3
    '(*$HINTS ON*)',                            // 4
    '{*)}',                                     // 5  Wache
    'implementation',                           // 6
    'end.']),                                   // 7
    [5], [MSG_F2]);
end;

procedure TTestFormatterMarker.IfdefBranches_CountedRaw;
// Grenze G1: {$IFDEF}-Zweige zaehlen roh (wie CnWizards) - der Start im
// einen und das Ende im anderen Zweig bilden ein Paar.
begin
  CheckFindings(Src([
    'unit A;',                                  // 1
    'interface',                                // 2
    '{$IFDEF FMT_A}',                           // 3
    '{(*}',                                     // 4
    '{$ELSE}',                                  // 5
    '{*)}',                                     // 6
    '{$ENDIF}',                                 // 7
    '{*)}',                                     // 8  Wache
    'implementation',                           // 9
    'end.']),                                   // 10
    [8], [MSG_F2]);
end;

procedure TTestFormatterMarker.NoMarker_NoFinding;
// Datei ohne Marker (nur gewoehnliche Kommentare und '(*' im String):
// kein Fund. Dieselbe Datei mit einem {(*} davor meldet - so ist der Test
// ohne Detektor rot.
begin
  CheckNoFindings(Src([
    'unit A;',                                  // 1
    'interface',                                // 2
    '(* note *) { note }',                      // 3
    'const S = ''(*'';',                        // 4
    'implementation',                           // 5
    'end.']));                                  // 6
  CheckFindings(Src([
    'unit A;',                                  // 1
    'interface',                                // 2
    '(* note *) { note }',                      // 3
    'const S = ''(*'';',                        // 4
    '{(*}',                                     // 5
    'implementation',                           // 6
    'end.']),                                   // 7
    [5], [MSG_F1]);
end;

{ ---- Pipeline, Katalog, Profile --------------------------------------------- }

procedure TTestFormatterMarker.NoInspection_Suppresses;
// Grenze G4 (absichtlich offen bis Dateiende): der Marker steht in der
// Zeile DAVOR - ein '// noinspection' hinter dem {(*} gaelte der
// naechsten Zeile, nicht der eigenen. Ohne Marker sichtbar (Default-
// Konfidenz fcMedium), mit Marker weg und der Marker verbraucht.
var
  F : TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(Src([
    'unit A;', 'interface', '{(*}', 'implementation', 'end.']));
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFormatterMarker),
      'sichtbar');
  finally
    F.Free;
  end;
  F := TFindingHelper.FindingsViaPipeline(Src([
    'unit A;', 'interface',
    '// noinspection FormatterMarker - tables below stay hand-aligned',
    '{(*}', 'implementation', 'end.']));
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFormatterMarker),
      'unterdrueckt');
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedSuppression),
      'Marker verbraucht');
  finally
    F.Free;
  end;
end;

procedure TTestFormatterMarker.CatalogExample_BadReported_GoodClean;
// Die Beispiele des Katalogs (rules/sca-rules.json) muessen stimmen: bad
// meldet genau das F4 am Start, good nichts.
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkFormatterMarker);
  Assert.AreEqual('SCA206', Meta.ID);
  CheckFindings(Src(['unit A;', 'interface', Meta.BadExample,
    'implementation', 'end.']), [3], [MsgF4('{ (*}', '{(*}')]);
  CheckNoFindings(Src(['unit A;', 'interface', Meta.GoodExample,
    'implementation', 'end.']));
end;

procedure TTestFormatterMarker.Profiles_DefaultStrictCodeQuality_NotIdeFastBugsOnly;
// Entscheid E7: default (ueber '*'), strict und code-quality; nicht
// ide-fast (Bugs/Security fuer jede geoeffnete Datei), nicht bugs-only.
begin
  Assert.IsTrue(fkFormatterMarker in TRuleCatalog.GetProfile('default'),
    'default');
  Assert.IsTrue(fkFormatterMarker in TRuleCatalog.GetProfile('strict'),
    'strict');
  Assert.IsTrue(fkFormatterMarker in TRuleCatalog.GetProfile('code-quality'),
    'code-quality');
  Assert.IsFalse(fkFormatterMarker in TRuleCatalog.GetProfile('ide-fast'),
    'ide-fast');
  Assert.IsFalse(fkFormatterMarker in TRuleCatalog.GetProfile('bugs-only'),
    'bugs-only');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFormatterMarker);

end.

unit uRdxTabsFix;

// reDelphix - Editorhilfe SCA061 TabulationCharacter (Tab-Zeichen im
// Quelltext): die Tabs EINER Zeile werden durch Leerzeichen ersetzt.
//
// DETEKTOR (uTabulationCharacter): pro Zeile EIN Fund auf den ersten Tab
// ('Tab character at column N - ...'), und zwar unabhaengig davon, ob der
// Tab im Code, in einem String oder in einem Kommentar steht.
//
// UMFORMUNG: jeder Tab im Code und in Kommentaren (Code-Sicht der
// TRdxCodeMap) wird durch so viele Leerzeichen ersetzt, dass die
// Anzeigespalte bis zum naechsten Tabstopp erhalten bleibt. Ein Tab nach
// Leerzeichen springt also auf den naechsten Stopp, nicht um eine ganze
// Tabweite weiter. Leerraum mit Tab am Zeilenende (hinter dem letzten
// sichtbaren Zeichen) entfaellt ganz, statt zu Leerzeichen zu werden. Tabs
// in Strings (auch mehrzeiligen) und in Compiler-Direktiven bleiben (sie
// sind Inhalt: '{$MESSAGE ..}', '{$I ..}'); zwischen dem ersten und dem
// letzten ersetzten Tab zaehlen sie in der Spaltenrechnung mit derselben
// Tabweite. Der Planer meldet EINE Ersetzung vom ersten Tab (bzw. vom
// Anfang des Leerraums am Zeilenende) bis zum letzten ersetzten Tab (bzw.
// bis zum Zeilenende); der Text dazwischen bleibt wie er ist.
//
// KOMMENTARE (Realworld-Test rwE30 Stufe 2: 13 Sperren 'erster Tab im
// Kommentar' unnoetig - Einrueckung einer Zeile im Blockkommentar, ein
// einzelner Tab hinter '//', ein Tab am Ende von '///</summary>'): Leerraum
// im Kommentar ist fuer den Compiler bedeutungslos, die Hilfe ersetzt ihn
// wie im Code. Bis dahin blieb er stehen, und die Hilfe sperrte, sobald der
// erste Tab der Zeile in einem Kommentar lag.
//
// TABWEITE (TabWidth; rwE29: bis dahin fest 2; rwE30: dateiweit, 3 dazu):
// Kandidaten sind 2, 4 und 8 (TAB_CANDIDATES) - 3 nur, wenn die ganze Datei
// sie beweist (s. unten). Je Kandidat zaehlt die Hilfe Belege, zuerst um
// die Zeile (NEIGHBOUR_LINES darueber und darunter), dann - nur wenn das
// nicht entscheidet - in der ganzen Datei:
//   Struktur  je zwei aufeinanderfolgende Codezeilen mit verschiedener
//             Einrueckung, von denen eine einen Tab traegt: hinter einem
//             Blockoeffner ('begin', 'then', 'do', 'try', 'var' ...) muss
//             die Folgezeile tiefer stehen ('begin' hinter then/do/else
//             darf auf derselben Spalte stehen), hinter einer mit ';'
//             abgeschlossenen Anweisung nicht tiefer (Verstoss). Ist die
//             Stufe der Datei aus reinen Leerzeichenzeilen bekannt (die
//             haeufigste Stufe hinter einem Oeffner, mindestens dreimal),
//             zaehlt eine andere Stufe hinter einem Oeffner als Abweichung
//             (MainFm.pas: Tab-Rumpf unter '  if .. then begin' mit 2er-
//             Stufen - Weite 2 legt ihn flach, 8 springt um 6, 4 passt).
//   Anker     die Spalte, an der nach einem Leerraum mit ersetzbarem Tab
//             der Text weitergeht: am Zeilenanfang gegen Nachbarzeilen, die
//             NUR mit Leerzeichen einruecken (deren Spalte haengt an keiner
//             Weite - '<TAB>      {$else}' unter 14 Leerzeichen), sonst
//             gegen dieselben zwei Zeichen an derselben Spalte ('= ', ': ',
//             '//') in jeder Nachbarzeile (Tabellen; zwei, damit ': integer'
//             nicht auf ':=' einer Anweisung trifft - gifimage.pas:12280).
// Gezaehlt wird nur, was die Kandidaten unterscheidet. Rangfolge fuer eine
// Zeile mit Tab in der Einrueckung: Verstoesse, Abweichungen, Anker am
// Zeilenanfang, Anker in der Zeile; sonst zuerst die Anker in der Zeile.
// Die Datei entscheidet nur mit Abstand (MIN_FILE_EVIDENCE) auf dem ersten
// Rang, der die Kandidaten trennt. Danach:
//   - ergeben alle Kandidaten dieselbe Zeile ('ABC<TAB>= 1' bei 4 und 8,
//     ein Tab am Zeilenende): Hilfe, die Weite spielt keine Rolle
//   - ergeben die besten dieselbe Zeile: Hilfe mit dieser Weite (Hinweis:
//     Nachbarzeilen bzw. Datei)
//   - sonst, ist die Vorgabe DEFAULT_TAB_WIDTH = 2 unter den besten: die
//     Vorgabe - eine ANNAHME, nicht die Option 'Tab stops' der IDE (der
//     Kern kennt keine ToolsAPI); so auch in einer reinen Tab-Datei ohne
//     jeden Beleg (Katalog-Beispiel 'begin / <TAB>DoStuff; / end;')
//   - sonst Sperre: zwei Weiten passen gleich gut und aendern die Zeile
//     verschieden.
// Weite 3 (ODRegExp.pas: '<TAB>if' gegen '   else', '   <TAB>result')
// steht nur zur Wahl, wenn die Datei sie nach Struktur und Einrueckung
// allein besser als alle anderen belegt - als Zufallstreffer passt sie zu
// vielen Tabellen ('movdqu<TAB>' und 'pxor<TAB>' enden bei 3 beide in
// Spalte 9).
// LAUFZEIT: die Belege der ganzen Datei rechnet FileProfile EINMAL je
// Code-Sicht (TRdxCodeMap.Serial; die Funde eines Menues und der Probe
// teilen die Map ihrer Datei) - eine Datei mit Tausenden Tab-Zeilen
// kostet sie nicht je Fund.
//
// SPERREN (lieber keine Hilfe als eine falsche): die Spalte der Meldung
// ist kein Tab oder nicht der erste der Zeile (Zeile verschoben), der ERSTE
// Tab der Zeile liegt in einem String oder einer Direktive (der Fund bliebe
// stehen), zwei Tabweiten passen gleich gut und aendern die Zeile
// verschieden. Bleibt ein Tab in einem String hinter dem ersten stehen,
// meldet der Detektor die Zeile danach mit dessen Spalte (wie bisher). Nur
// die gemeldete Zeile - der Massenmodus kommt spaeter.
//
// OHNE ToolsAPI und ohne Delphi-only-Unit (FPC-Pruefstand): den Adapter
// PlanTabs (Form TRdxFixPlanner) traegt die Tabelle uRdxFixTable; den
// Hinweis liefert Hint.

interface

uses
  uRdxBufferMath,    // TRdxEdit
  uRdxCodeMap;       // TRdxCodeMap

const
  // Tabweite, wenn nichts eine beweist: eine Annahme, nicht die der IDE
  // (s. Kopf). Bis rwE29 die einzige (TAB_WIDTH).
  DEFAULT_TAB_WIDTH = 2;
  // So viele Zeilen darueber und darunter liest TabWidth zuerst.
  NEIGHBOUR_LINES = 8;
  // Die seltene Weite: nur mit Beweis aus der ganzen Datei (s. Kopf).
  RARE_TAB_WIDTH = 3;
  // So viel muss die Datei auf dem trennenden Rang vorne liegen.
  MIN_FILE_EVIDENCE = 3;

  // Die Gruende und Hinweise als englische msgids (E29), uebersetzt mit _()
  // aus uRdxText; Deutsch und Franzoesisch in i18n/de.po und i18n/fr.po.
  // Im interface fuer die Tests (Vergleich unabhaengig von der Sprache).
  // Das Ende ' - Zeile verschoben? ...' haengt MsgMovedSuffix an.
  R_TAB_MOVED = 'no tab at the reported place';
  // rwE30: bis dahin 'the first tab of the line is inside a string or
  // comment - ...' (R_TAB_NOT_CODE) - Kommentar-Tabs ersetzt die Hilfe seither.
  R_TAB_IN_TEXT = 'the first tab of the line is inside a string or a '
    + 'compiler directive - it stays untouched, the help would leave the '
    + 'finding in place';
  // %d, %d die beiden Weiten, %s MsgByHand. rwE30: die Datei entscheidet
  // jetzt mit (bis dahin 'the neighbouring lines fit tab width %d as well
  // as %d - which one the alignment of the file follows is open; %s').
  R_TAB_AMBIGUOUS = 'the neighbouring lines fit tab width %d as well as %d, '
    + 'and the rest of the file does not decide between them; %s';
  // Die Hinweise (bis rwE30 als R_TABS_DERIVED_HINT/R_TABS_DEFAULT_HINT in
  // uRdxFixTable, mit '...; tabs in strings and comments stay'). %d die Weite.
  R_TABS_LOCAL_HINT = 'tabs become spaces - tab width %d, as the alignment '
    + 'of the neighbouring lines shows; tabs in strings stay';
  R_TABS_FILE_HINT = 'tabs become spaces - tab width %d, as the alignment '
    + 'elsewhere in the file shows; tabs in strings stay';
  R_TABS_DEFAULT_HINT = 'tabs become spaces - tab width %d (assumption, the '
    + 'file does not show one); tabs in strings stay';
  R_TABS_ANY_HINT = 'tabs become spaces - the same result for every tab '
    + 'width in question; tabs in strings stay';
  R_TABS_TRAIL_HINT = 'the tabs at the end of the line are removed; nothing '
    + 'else changes';

type
  // Woher die Tabweite von TabWidth kommt.
  //   twDefault    nichts beweist eine - DEFAULT_TAB_WIDTH (Annahme)
  //   twDerived    die Nachbarzeilen
  //   twFile       der Rest der Datei (die Nachbarzeilen entschieden nicht)
  //   twAny        jeder Kandidat ergibt dieselbe Zeile
  //   twAmbiguous  zwei Weiten gleich gut, verschiedenes Ergebnis - Sperre
  TRdxTabWidthSource = (twDefault, twDerived, twFile, twAny, twAmbiguous);

  // Der Planer von SCA061 (Form TRdxMapPlanner, uRdxFixRunner).
  TRdxTabsFix = class
  public
    // SCA061: die Tabs im Code und in Kommentaren von ALine -> Leerzeichen
    // bis zum naechsten Tabstopp (Weite aus TabWidth), Tabs am Zeilenende
    // entfallen. Spalte aus der Meldung ('Tab character at column N').
    class function Tabs(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // Die Tabweite fuer ALine (s. Kopf); bei twAmbiguous die kleinere der
    // beiden Weiten, AOther die groessere - sonst AOther = 0. Fuer Tabs und
    // Hint.
    class function TabWidth(AMap: TRdxCodeMap; ALine: Integer;
      out ASource: TRdxTabWidthSource; out AOther: Integer): Integer; static;

    // Der Hinweis der Hilfe fuer ALine (uebersetzt): die Weite und woher sie
    // kommt bzw. dass nur Tabs am Zeilenende entfallen. Fuer den Adapter
    // PlanTabs (uRdxFixTable), nach einem Tabs mit Ergebnis True.
    class function Hint(AMap: TRdxCodeMap; ALine: Integer): string; static;

    // Wie oft die Belege einer ganzen Datei gerechnet wurden (FileProfile,
    // je Code-Sicht einmal) - fuer Tests und das Messgeruest.
    class function FileScans: Integer; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,   // TRefactorSpan.Make
  uRdxText;        // _(), MsgNoColumn, MsgMovedSuffix, MsgByHand (E29)

const
  TAB = #9;
  SPAN_061 = 'sca061';
  // Die Weiten, unter denen TabWidth waehlt (2 die Vorgabe, 3 nur mit
  // Beweis der Datei, 4 und 8 die gaengigen Editor-Einstellungen).
  TAB_CANDIDATE_COUNT = 4;
  TAB_CANDIDATES: array[0..TAB_CANDIDATE_COUNT - 1] of Integer =
    (2, 3, 4, 8);
  RARE_INDEX = 1;      // TAB_CANDIDATES[RARE_INDEX] = RARE_TAB_WIDTH
  DEFAULT_INDEX = 0;   // TAB_CANDIDATES[DEFAULT_INDEX] = DEFAULT_TAB_WIDTH
  // Groesste Stufe, die die Stufen-Statistik zaehlt (StepOf).
  MAX_STEP = 16;
  // So oft muss die haeufigste Stufe vorkommen, damit sie gilt.
  MIN_STEP_COUNT = 3;
  // So weit sucht InDirective den Anfang eines mehrzeiligen Kommentars.
  MAX_COMMENT_LINES = 50;

  // Hinter diesen Woertern (Ende einer Zeile) steht die Folgezeile tiefer.
  OPEN_WORDS: array[0..22] of string = ('begin', 'try', 'repeat', 'then',
    'do', 'else', 'of', 'except', 'finally', 'record', 'var', 'const',
    'type', 'asm', 'private', 'protected', 'public', 'published', 'class',
    'label', 'resourcestring', 'threadvar', 'uses');
  // Mit diesen Woertern beginnt eine Zeile, deren Spalte an einem anderen
  // Block haengt - keine Regel.
  CLOSE_WORDS: array[0..4] of string = ('end', 'until', 'except', 'finally',
    'else');
  // Ein Kopf: hinter seinem ';' darf die Folgezeile tiefer stehen ('var'
  // einer Routine, Direktiven-Zeilen).
  HEAD_WORDS: array[0..6] of string = ('procedure', 'function',
    'constructor', 'destructor', 'operator', 'class', 'property');

type
  // Ein Anker (s. Kopf): die Anzeigespalte (0-basiert), an der hinter einem
  // Leerraum der Text weitergeht, ob der Leerraum am Zeilenanfang steht
  // (Einrueckung), und die zwei Zeichen dort (#0 hinter dem Zeilenende).
  TRdxTabAnchor = record
    Col  : Integer;
    Lead : Boolean;
    Ch   : Char;
    Ch2  : Char;
  end;
  TRdxTabAnchors = array of TRdxTabAnchor;
  TRdxTabAnchorRows = array of TRdxTabAnchors;

  // Die Belege je Kandidat (Index wie TAB_CANDIDATES).
  TRdxTabCounts = array[0..TAB_CANDIDATE_COUNT - 1] of Integer;
  TRdxTabStats = record
    Viol  : TRdxTabCounts;   // Struktur-Verstoesse
    Miss  : TRdxTabCounts;   // Abweichungen von der Stufe der Datei
    Lead  : TRdxTabCounts;   // Anker am Zeilenanfang
    Inner : TRdxTabCounts;   // Anker in der Zeile
  end;
  TRdxTabSet = array[0..TAB_CANDIDATE_COUNT - 1] of Boolean;
  TRdxTabKey = array[0..3] of Integer;

  // Eine Codezeile fuer die Struktur-Regeln: Einrueckung, erstes Wort bzw.
  // Zeichen und letztes Token des Codes (klein).
  TRdxTabLine = record
    Indent : string;
    First  : string;
    Last   : string;
  end;

  // Was die Hilfe in der Zeile ersetzt (Spalten 1-basiert).
  TRdxTabPlan = record
    Text  : string;    // die Zeile
    Line  : Integer;
    First : Integer;   // der erste Tab (die gemeldete Spalte)
    Last  : Integer;   // der letzte ersetzte Tab vor dem Zeilenende, 0 = keiner
    Trail : Integer;   // Anfang des Leerraums am Zeilenende, 0 = keiner mit Tab
  end;

  // Die Belege der ganzen Datei, gerechnet fuer genau eine Code-Sicht
  // (Serial; Muster uRdxSuppress.TFileFacts).
  TRdxTabFile = record
    Serial : Int64;          // 0 = keiner
    Step   : Integer;        // Stufe der Datei, 0 = unbekannt
    Stats  : TRdxTabStats;
  end;

var
  // EIN Eintrag, ohne Sperre: reDelphix rechnet nur im IDE-Hauptthread (wie
  // GMapSerial in uRdxCodeMap).
  GTabFile  : TRdxTabFile;
  GTabScans : Integer = 0;

function IsSpaceOrTab(C: Char): Boolean;
begin
  Result := (C = ' ') or (C = TAB);
end;

// Anzeigebreite von AWhite (Leerzeichen und Tabs) ab Spalte 0.
function DisplayWidth(const AWhite: string; AWidth: Integer): Integer;
var
  i : Integer;
begin
  Result := 0;
  for i := 1 to Length(AWhite) do
    if AWhite[i] = TAB then
      Inc(Result, AWidth - (Result mod AWidth))
    else
      Inc(Result);
end;

// Liegt (ALine, ACol) - ein Kommentarzeichen - in einer Compiler-Direktive?
// Sucht den Anfang des Kommentars, auch ueber Zeilen (StartsInside).
function InDirective(AMap: TRdxCodeMap; ALine, ACol: Integer): Boolean;
var
  L, C, Steps : Integer;
begin
  L := ALine;
  C := ACol;
  Steps := 0;
  while True do
  begin
    while (C > 1) and (AMap.ClassAt(L, C - 1) = 'k') do
      Dec(C);
    if (C > 1) or not AMap.StartsInside(L) or (L <= 1)
       or (Steps >= MAX_COMMENT_LINES) then
      Break;
    // Der Kommentar begann weiter oben.
    Dec(L);
    Inc(Steps);
    C := Length(AMap.Raw(L)) + 1;
    // Unerwartet: die Zeile davor endet nicht im Kommentar - im Zweifel
    // wie eine Direktive (der Tab bleibt).
    if (C > 1) and (AMap.ClassAt(L, C - 1) <> 'k') then
      Exit(True);
  end;
  Result := AMap.DirectiveStartsAt(L, C);
end;

// Ersetzt die Hilfe den Tab an (ALine, ACol)? Code ja, Kommentar ja,
// Direktive und String nein (den Leerraum am Zeilenende regelt PlanOf).
function Replaceable(AMap: TRdxCodeMap; ALine, ACol: Integer): Boolean;
begin
  case AMap.ClassAt(ALine, ACol) of
    'c': Result := True;
    'k': Result := not InDirective(AMap, ALine, ACol);
  else
    Result := False;
  end;
end;

// Was in ALine zu ersetzen ist (s. TRdxTabPlan); False ohne Tab.
function PlanOf(AMap: TRdxCodeMap; ALine: Integer;
  out APlan: TRdxTabPlan): Boolean;
var
  L       : string;
  i, T    : Integer;
  HasTab  : Boolean;
  InText  : Boolean;
  Stop    : Integer;
begin
  APlan := Default(TRdxTabPlan);
  L := AMap.Raw(ALine);
  APlan.Text := L;
  APlan.Line := ALine;
  APlan.First := Pos(TAB, L);
  Result := APlan.First > 0;
  if not Result then Exit;
  // Leerraum am Zeilenende: mit Tab und ohne String-Zeichen (mehrzeiliger
  // String) entfaellt er ganz.
  T := Length(L);
  while (T >= 1) and IsSpaceOrTab(L[T]) do
    Dec(T);
  HasTab := False;
  InText := False;
  for i := T + 1 to Length(L) do
  begin
    if L[i] = TAB then HasTab := True;
    if AMap.ClassAt(ALine, i) = 's' then InText := True;
  end;
  if HasTab and not InText then
    APlan.Trail := T + 1;
  Stop := Length(L);
  if APlan.Trail > 0 then
    Stop := APlan.Trail - 1;
  for i := APlan.First to Stop do
    if (L[i] = TAB) and Replaceable(AMap, ALine, i) then
      APlan.Last := i;
end;

// Erste Spalte der Ersetzung.
function SpanStart(const APlan: TRdxTabPlan): Integer;
begin
  Result := APlan.First;
  if (APlan.Trail > 0) and (APlan.Trail < Result) then
    Result := APlan.Trail;
end;

// Letzte Spalte der Ersetzung.
function SpanEnd(const APlan: TRdxTabPlan): Integer;
begin
  if APlan.Trail > 0 then
    Result := Length(APlan.Text)
  else
    Result := APlan.Last;
end;

// Der neue Text fuer SpanStart..SpanEnd bei Tabweite AWidth.
function NewTextOf(AMap: TRdxCodeMap; const APlan: TRdxTabPlan;
  AWidth: Integer): string;
var
  L       : string;
  i, V, n : Integer;
begin
  Result := '';
  if APlan.Last = 0 then Exit;   // nur Leerraum am Zeilenende
  L := APlan.Text;
  // Anzeigespalte (0-basiert) vor First: davor steht kein Tab (First ist
  // der erste Tab der Zeile), jedes Zeichen zaehlt eine Spalte.
  V := APlan.First - 1;
  for i := APlan.First to APlan.Last do
    if L[i] <> TAB then
    begin
      Result := Result + L[i];
      Inc(V);
    end
    else
    begin
      n := AWidth - (V mod AWidth);
      if Replaceable(AMap, APlan.Line, i) then
        Result := Result + StringOfChar(' ', n)
      else
        Result := Result + TAB;
      Inc(V, n);
    end;
  if APlan.Trail > 0 then
    Result := Result + Copy(L, APlan.Last + 1, APlan.Trail - APlan.Last - 1);
end;

// Ergeben alle Kandidaten in ASet dieselbe Zeile? Ohne Kandidat: True.
function SameResult(AMap: TRdxCodeMap; const APlan: TRdxTabPlan;
  const ASet: TRdxTabSet): Boolean;
var
  i     : Integer;
  Seen  : Boolean;
  S, S0 : string;
begin
  Result := True;
  Seen := False;
  S0 := '';
  for i := 0 to High(TAB_CANDIDATES) do
    if ASet[i] then
    begin
      S := NewTextOf(AMap, APlan, TAB_CANDIDATES[i]);
      if not Seen then
      begin
        S0 := S;
        Seen := True;
      end
      else if S <> S0 then
        Exit(False);
    end;
end;

// ---- Anker ----

// Die Anker von AText bei Tabweite AWidth. Mit AMap: nur hinter einem
// Leerraum, der einen ersetzbaren Tab der Zeile ALine traegt (die
// gemeldete Zeile - nur dort bewegt die Weite den Text); ohne (nil):
// hinter jedem Leerraum (Nachbarzeilen, Rohtext).
function AnchorsOf(const AText: string; AWidth: Integer; AMap: TRdxCodeMap;
  ALine: Integer): TRdxTabAnchors;
var
  i, j, V, n : Integer;
  OwnTab     : Boolean;
begin
  Result := nil;
  n := 0;
  V := 0;
  i := 1;
  while i <= Length(AText) do
  begin
    if not IsSpaceOrTab(AText[i]) then
    begin
      Inc(V);
      Inc(i);
      Continue;
    end;
    j := i;
    OwnTab := False;
    while (j <= Length(AText)) and IsSpaceOrTab(AText[j]) do
    begin
      if AText[j] = TAB then
      begin
        if (AMap <> nil) and Replaceable(AMap, ALine, j) then
          OwnTab := True;
        Inc(V, AWidth - (V mod AWidth));
      end
      else
        Inc(V);
      Inc(j);
    end;
    if (j <= Length(AText)) and ((AMap = nil) or OwnTab) then
    begin
      SetLength(Result, n + 1);
      Result[n].Col := V;
      Result[n].Lead := i = 1;
      Result[n].Ch := AText[j];
      if j < Length(AText) then
        Result[n].Ch2 := AText[j + 1]
      else
        Result[n].Ch2 := #0;
      Inc(n);
    end;
    i := j;
  end;
end;

// Die Treffer der Anker AOwn in einer Nachbarzeile (ihre Anker ANeighbour):
// am Zeilenanfang nur gegen eine Einrueckung aus Leerzeichen (APure), in der
// Zeile gegen dieselben zwei Zeichen an derselben Spalte.
procedure CountHits(const AOwn, ANeighbour: TRdxTabAnchors; APure: Boolean;
  var AInner, ALead: Integer);
var
  a, b : Integer;
begin
  for a := 0 to High(AOwn) do
    for b := 0 to High(ANeighbour) do
    begin
      if AOwn[a].Col <> ANeighbour[b].Col then Continue;
      if AOwn[a].Lead and ANeighbour[b].Lead then
      begin
        if APure then
        begin
          Inc(ALead);
          Break;
        end;
      end
      else if not AOwn[a].Lead and not ANeighbour[b].Lead
         and (AOwn[a].Ch = ANeighbour[b].Ch)
         and (AOwn[a].Ch2 = ANeighbour[b].Ch2) then
      begin
        Inc(AInner);
        Break;
      end;
    end;
end;

// Rueckt S nur mit Leerzeichen ein (die Spalte haengt an keiner Weite)?
function PureIndent(const S: string): Boolean;
begin
  Result := Pos(TAB, IndentOf(S)) = 0;
end;

// Die Anker-Treffer von ALine gegen ihre Nachbarzeilen, je Kandidat.
procedure LineHits(AMap: TRdxCodeMap; ALine: Integer;
  out AInner, ALead: TRdxTabCounts);
var
  c, k : Integer;
  Own  : TRdxTabAnchors;
  N    : string;
begin
  for c := 0 to High(TAB_CANDIDATES) do
  begin
    AInner[c] := 0;
    ALead[c] := 0;
    Own := AnchorsOf(AMap.Raw(ALine), TAB_CANDIDATES[c], AMap, ALine);
    if Length(Own) = 0 then Continue;
    for k := ALine - NEIGHBOUR_LINES to ALine + NEIGHBOUR_LINES do
    begin
      if (k < 1) or (k > AMap.LineCount) or (k = ALine) then Continue;
      N := AMap.Raw(k);
      if IsBlankLine(N) then Continue;
      CountHits(Own, AnchorsOf(N, TAB_CANDIDATES[c], nil, k), PureIndent(N),
        AInner[c], ALead[c]);
    end;
  end;
end;

// Unterscheiden die Werte die Kandidaten?
function Differs(const ACounts: TRdxTabCounts): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := 1 to High(ACounts) do
    if ACounts[i] <> ACounts[0] then
      Exit(True);
end;

procedure AddCounts(var ASum: TRdxTabCounts; const AAdd: TRdxTabCounts);
var
  i : Integer;
begin
  for i := 0 to High(ASum) do
    Inc(ASum[i], AAdd[i]);
end;

// ---- Struktur ----

// ALine als Codezeile (s. TRdxTabLine); False, wenn sie nicht mit Code
// beginnt (Leerzeile, Kommentar, Direktive, String).
function LineOf(AMap: TRdxCodeMap; ALine: Integer;
  out AInfo: TRdxTabLine): Boolean;
var
  S       : string;
  p, q, r : Integer;
begin
  AInfo := Default(TRdxTabLine);
  S := AMap.Raw(ALine);
  p := SkipBlanks(S, 1);
  Result := (p <= Length(S)) and AMap.IsCode(ALine, p);
  if not Result then Exit;
  AInfo.Indent := Copy(S, 1, p - 1);
  if IsIdentStart(S[p]) then
  begin
    q := p;
    while (q < Length(S)) and IsIdentChar(S[q + 1])
          and AMap.IsCode(ALine, q + 1) do
      Inc(q);
    AInfo.First := LowerCase(Copy(S, p, q - p + 1));
  end
  else
    AInfo.First := S[p];
  // Das letzte Token des Codes (Kommentare und Leerraum dahinter zaehlen
  // nicht).
  q := Length(S);
  while (q >= 1) and (not AMap.IsCode(ALine, q) or IsSpaceOrTab(S[q])) do
    Dec(q);
  if IsIdentChar(S[q]) then
  begin
    r := q;
    while (r > 1) and IsIdentChar(S[r - 1]) and AMap.IsCode(ALine, r - 1) do
      Dec(r);
    AInfo.Last := LowerCase(Copy(S, r, q - r + 1));
  end
  else
    AInfo.Last := S[q];
end;

// Die Regel fuer die Folgezeile B hinter P bei Weite AWidth (s. Kopf,
// Struktur). False: keine Regel fuer dieses Paar.
function PairRule(const P, B: TRdxTabLine; AWidth, AStep: Integer;
  out AViol, AMiss: Boolean): Boolean;
var
  d : Integer;
begin
  Result := False;
  AViol := False;
  AMiss := False;
  if InList(B.First, CLOSE_WORDS) then Exit;
  d := DisplayWidth(B.Indent, AWidth) - DisplayWidth(P.Indent, AWidth);
  if InList(P.Last, OPEN_WORDS) then
  begin
    Result := True;
    if (B.First = 'begin') and InList(P.Last, BRANCH_WORDS) then
    begin
      AViol := d < 0;
      AMiss := (AStep > 0) and (d <> 0) and (d <> AStep);
    end
    else
    begin
      AViol := d <= 0;
      AMiss := (AStep > 0) and (d <> AStep);
    end;
  end
  else if (P.Last = ';') and not InList(P.First, HEAD_WORDS) then
  begin
    Result := True;
    AViol := d > 0;
  end;
end;

// Verstoesse und Abweichungen der Codezeilen AFrom..ATo, je Kandidat; nur
// Paare mit verschiedener Einrueckung, eine davon mit Tab, und nur, was die
// Kandidaten unterscheidet.
procedure PairStats(AMap: TRdxCodeMap; AFrom, ATo, AStep: Integer;
  var AStats: TRdxTabStats);
var
  i, c      : Integer;
  Prev, Cur : TRdxTabLine;
  HasPrev   : Boolean;
  Viol      : TRdxTabCounts;
  Miss      : TRdxTabCounts;
  V, M      : Boolean;
  Applies   : Boolean;
begin
  HasPrev := False;
  if AFrom < 1 then AFrom := 1;
  if ATo > AMap.LineCount then ATo := AMap.LineCount;
  for i := AFrom to ATo do
  begin
    if not LineOf(AMap, i, Cur) then Continue;
    if HasPrev and (Prev.Indent <> Cur.Indent)
       and ((Pos(TAB, Prev.Indent) > 0) or (Pos(TAB, Cur.Indent) > 0)) then
    begin
      Applies := False;
      for c := 0 to High(TAB_CANDIDATES) do
      begin
        Applies := PairRule(Prev, Cur, TAB_CANDIDATES[c], AStep, V, M);
        Viol[c] := Ord(V);
        Miss[c] := Ord(M);
      end;
      if Applies then
      begin
        if Differs(Viol) then AddCounts(AStats.Viol, Viol);
        if Differs(Miss) then AddCounts(AStats.Miss, Miss);
      end;
    end;
    Prev := Cur;
    HasPrev := True;
  end;
end;

// Die Stufe der Datei (s. Kopf), 0 = unbekannt.
function StepOf(AMap: TRdxCodeMap): Integer;
var
  Hist      : array[1..MAX_STEP] of Integer;
  i, d, Top : Integer;
  Prev, Cur : TRdxTabLine;
  HasPrev   : Boolean;
begin
  for d := 1 to MAX_STEP do
    Hist[d] := 0;
  HasPrev := False;
  for i := 1 to AMap.LineCount do
  begin
    if not LineOf(AMap, i, Cur) then Continue;
    if HasPrev and (Pos(TAB, Prev.Indent) = 0) and (Pos(TAB, Cur.Indent) = 0)
       and InList(Prev.Last, OPEN_WORDS)
       and not ((Cur.First = 'begin') and InList(Prev.Last, BRANCH_WORDS))
       and not InList(Cur.First, CLOSE_WORDS) then
    begin
      d := Length(Cur.Indent) - Length(Prev.Indent);
      if (d >= 1) and (d <= MAX_STEP) then
        Inc(Hist[d]);
    end;
    Prev := Cur;
    HasPrev := True;
  end;
  Result := 0;
  Top := MIN_STEP_COUNT - 1;
  for d := 1 to MAX_STEP do
    if Hist[d] > Top then
    begin
      Top := Hist[d];
      Result := d;
    end;
end;

// Die Belege der ganzen Datei (s. Kopf, LAUFZEIT): einmal je Code-Sicht.
function FileProfile(AMap: TRdxCodeMap): TRdxTabFile;
var
  i, k, c  : Integer;
  Rows     : array[0..TAB_CANDIDATE_COUNT - 1] of TRdxTabAnchorRows;
  Pure     : array of Boolean;
  Blank    : array of Boolean;
  Own      : TRdxTabAnchors;
  Inner    : TRdxTabCounts;
  Lead     : TRdxTabCounts;
  Prepared : Boolean;
begin
  if (GTabFile.Serial <> 0) and (GTabFile.Serial = AMap.Serial) then
    Exit(GTabFile);
  Inc(GTabScans);
  Result := Default(TRdxTabFile);
  Result.Serial := AMap.Serial;
  Result.Step := StepOf(AMap);
  PairStats(AMap, 1, AMap.LineCount, Result.Step, Result.Stats);
  // Anker: die Nachbar-Anker jeder Zeile je Weite einmal (erst, wenn eine
  // Zeile einen Tab traegt).
  Prepared := False;
  for i := 1 to AMap.LineCount do
  begin
    if Pos(TAB, AMap.Raw(i)) = 0 then Continue;
    if not Prepared then
    begin
      SetLength(Pure, AMap.LineCount + 1);
      SetLength(Blank, AMap.LineCount + 1);
      for k := 1 to AMap.LineCount do
      begin
        Blank[k] := IsBlankLine(AMap.Raw(k));
        Pure[k] := PureIndent(AMap.Raw(k));
      end;
      for c := 0 to High(TAB_CANDIDATES) do
      begin
        SetLength(Rows[c], AMap.LineCount + 1);
        for k := 1 to AMap.LineCount do
          Rows[c][k] := AnchorsOf(AMap.Raw(k), TAB_CANDIDATES[c], nil, k);
      end;
      Prepared := True;
    end;
    for c := 0 to High(TAB_CANDIDATES) do
    begin
      Inner[c] := 0;
      Lead[c] := 0;
      Own := AnchorsOf(AMap.Raw(i), TAB_CANDIDATES[c], AMap, i);
      if Length(Own) = 0 then Continue;
      for k := i - NEIGHBOUR_LINES to i + NEIGHBOUR_LINES do
        if (k >= 1) and (k <= AMap.LineCount) and (k <> i)
           and not Blank[k] then
          CountHits(Own, Rows[c][k], Pure[k], Inner[c], Lead[c]);
    end;
    if Differs(Inner) then AddCounts(Result.Stats.Inner, Inner);
    if Differs(Lead) then AddCounts(Result.Stats.Lead, Lead);
  end;
  GTabFile := Result;
end;

// ---- Auswahl ----

// Der Schluessel von Kandidat i (kleiner = besser; s. Kopf, Rangfolge).
function KeyOf(const AStats: TRdxTabStats; i: Integer;
  ALeadTab: Boolean): TRdxTabKey;
begin
  if ALeadTab then
  begin
    Result[0] := AStats.Viol[i];
    Result[1] := AStats.Miss[i];
    Result[2] := -AStats.Lead[i];
    Result[3] := -AStats.Inner[i];
  end
  else
  begin
    Result[0] := -AStats.Inner[i];
    Result[1] := AStats.Viol[i];
    Result[2] := AStats.Miss[i];
    Result[3] := -AStats.Lead[i];
  end;
end;

// Vergleicht die ersten ADepth Stellen: <0, 0, >0. ADiff: der Abstand auf
// der ersten verschiedenen Stelle (0 bei Gleichheit).
function CompareKeys(const A, B: TRdxTabKey; ADepth: Integer;
  out ADiff: Integer): Integer;
var
  i : Integer;
begin
  Result := 0;
  ADiff := 0;
  for i := 0 to ADepth - 1 do
    if A[i] <> B[i] then
    begin
      ADiff := Abs(A[i] - B[i]);
      if A[i] < B[i] then
        Exit(-1)
      else
        Exit(1);
    end;
end;

// Die Kandidaten aus ASet mit dem kleinsten Schluessel (die ersten ADepth
// Stellen); liegt der naechstbeste auf der trennenden Stelle weniger als
// AThreshold zurueck, bleibt ASet.
function Narrow(const ASet: TRdxTabSet; const AStats: TRdxTabStats;
  ALeadTab: Boolean; ADepth, AThreshold: Integer): TRdxTabSet;
var
  Keys       : array[0..TAB_CANDIDATE_COUNT - 1] of TRdxTabKey;
  i, b, r, d : Integer;
begin
  b := -1;
  for i := 0 to High(TAB_CANDIDATES) do
  begin
    Result[i] := False;
    if not ASet[i] then Continue;
    Keys[i] := KeyOf(AStats, i, ALeadTab);
    if (b < 0) or (CompareKeys(Keys[i], Keys[b], ADepth, d) < 0) then
      b := i;
  end;
  if b < 0 then
    Exit(ASet);
  // Die besten; r der naechstbeste dahinter.
  r := -1;
  for i := 0 to High(TAB_CANDIDATES) do
    if ASet[i] then
    begin
      if CompareKeys(Keys[i], Keys[b], ADepth, d) = 0 then
        Result[i] := True
      else if (r < 0) or (CompareKeys(Keys[i], Keys[r], ADepth, d) < 0) then
        r := i;
    end;
  if (r >= 0) and (AThreshold > 0) then
  begin
    CompareKeys(Keys[r], Keys[b], ADepth, d);
    if d < AThreshold then
      Result := ASet;
  end;
end;

function SameSet(const A, B: TRdxTabSet): Boolean;
var
  i : Integer;
begin
  Result := True;
  for i := 0 to High(A) do
    if A[i] <> B[i] then
      Exit(False);
end;

// Der erste bzw. letzte Kandidat in ASet (Weite), 0 ohne.
function FirstOf(const ASet: TRdxTabSet): Integer;
var
  i : Integer;
begin
  Result := 0;
  for i := 0 to High(TAB_CANDIDATES) do
    if ASet[i] then
      Exit(TAB_CANDIDATES[i]);
end;

function LastOf(const ASet: TRdxTabSet): Integer;
var
  i : Integer;
begin
  Result := 0;
  for i := High(TAB_CANDIDATES) downto 0 do
    if ASet[i] then
      Exit(TAB_CANDIDATES[i]);
end;

class function TRdxTabsFix.TabWidth(AMap: TRdxCodeMap; ALine: Integer;
  out ASource: TRdxTabWidthSource; out AOther: Integer): Integer;
var
  Plan         : TRdxTabPlan;
  FileP        : TRdxTabFile;
  Local        : TRdxTabStats;
  All, Cands   : TRdxTabSet;
  Best, Best2  : TRdxTabSet;
  Only3        : TRdxTabSet;
  i            : Integer;
  LeadTab      : Boolean;
begin
  AOther := 0;
  ASource := twDefault;
  Result := DEFAULT_TAB_WIDTH;
  if not PlanOf(AMap, ALine, Plan) then Exit;
  FileP := FileProfile(AMap);
  // Ein Tab in der Einrueckung, der kein Leerraum am Zeilenende ist.
  LeadTab := (Plan.Last > 0)
    and (Plan.First <= Length(IndentOf(Plan.Text)));
  for i := 0 to High(TAB_CANDIDATES) do
  begin
    All[i] := True;
    Only3[i] := i = RARE_INDEX;
  end;
  // 3 nur, wenn die Datei sie nach Struktur und Einrueckung allein belegt.
  Cands := All;
  if not SameSet(Narrow(All, FileP.Stats, True, 3, MIN_FILE_EVIDENCE),
                 Only3) then
    Cands[RARE_INDEX] := False;
  if SameResult(AMap, Plan, Cands) then
  begin
    ASource := twAny;
    Exit;
  end;
  Local := Default(TRdxTabStats);
  PairStats(AMap, ALine - NEIGHBOUR_LINES, ALine + NEIGHBOUR_LINES,
    FileP.Step, Local);
  LineHits(AMap, ALine, Local.Inner, Local.Lead);
  Best := Narrow(Cands, Local, LeadTab, 4, 0);
  if SameResult(AMap, Plan, Best) then
  begin
    ASource := twDerived;
    Exit(FirstOf(Best));
  end;
  Best2 := Narrow(Best, FileP.Stats, LeadTab, 4, MIN_FILE_EVIDENCE);
  if SameResult(AMap, Plan, Best2) then
  begin
    ASource := twFile;
    Exit(FirstOf(Best2));
  end;
  if Best2[DEFAULT_INDEX] then
    Exit;   // twDefault, DEFAULT_TAB_WIDTH
  ASource := twAmbiguous;
  Result := FirstOf(Best2);
  AOther := LastOf(Best2);
end;

class function TRdxTabsFix.Tabs(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  L         : string;
  Col       : Integer;
  W, Other  : Integer;
  S0, S1    : Integer;
  Plan      : TRdxTabPlan;
  Source    : TRdxTabWidthSource;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  Col := ColumnFromMessage(AMessage);
  if Col <= 0 then
  begin
    AReason := MsgNoColumn;
    Exit;
  end;
  L := AMap.Raw(ALine);
  if (Col > Length(L)) or (L[Col] <> TAB) or (Pos(TAB, L) <> Col)
     or not PlanOf(AMap, ALine, Plan) then
  begin
    AReason := MsgMovedSuffix(_(R_TAB_MOVED));
    Exit;
  end;
  // Der erste Tab: im Leerraum am Zeilenende, im Code oder im Kommentar.
  if not ((Plan.Trail > 0) and (Col >= Plan.Trail))
     and not Replaceable(AMap, ALine, Col) then
  begin
    AReason := _(R_TAB_IN_TEXT);
    Exit;
  end;
  W := TabWidth(AMap, ALine, Source, Other);
  if Source = twAmbiguous then
  begin
    AReason := _(R_TAB_AMBIGUOUS, [W, Other, MsgByHand]);
    Exit;
  end;
  S0 := SpanStart(Plan);
  S1 := SpanEnd(Plan);
  AEdit.Span := TRefactorSpan.Make(SPAN_061, ALine, S0, ALine, S1 + 1);
  AEdit.Expected := Copy(L, S0, S1 + 1 - S0);
  AEdit.NewText := NewTextOf(AMap, Plan, W);
  Result := True;
end;

class function TRdxTabsFix.Hint(AMap: TRdxCodeMap; ALine: Integer): string;
var
  Plan   : TRdxTabPlan;
  W, Alt : Integer;
  Source : TRdxTabWidthSource;
begin
  if PlanOf(AMap, ALine, Plan) and (Plan.Last = 0) then
    Exit(_(R_TABS_TRAIL_HINT));
  W := TabWidth(AMap, ALine, Source, Alt);
  case Source of
    twDerived : Result := _(R_TABS_LOCAL_HINT, [W]);
    twFile    : Result := _(R_TABS_FILE_HINT, [W]);
    twAny     : Result := _(R_TABS_ANY_HINT);
  else
    Result := _(R_TABS_DEFAULT_HINT, [W]);
  end;
end;

class function TRdxTabsFix.FileScans: Integer;
begin
  Result := GTabScans;
end;

end.

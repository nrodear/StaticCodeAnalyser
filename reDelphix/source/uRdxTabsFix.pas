unit uRdxTabsFix;

// reDelphix - Editorhilfe SCA061 TabulationCharacter (Tab-Zeichen im
// Quelltext): die Tabs EINER Zeile werden durch Leerzeichen ersetzt.
//
// DETEKTOR (uTabulationCharacter): pro Zeile EIN Fund auf den ersten Tab
// ('Tab character at column N - ...'), und zwar unabhaengig davon, ob der
// Tab im Code, in einem String oder in einem Kommentar steht.
//
// UMFORMUNG: jeder Tab im CODE (Code-Sicht der TRdxCodeMap: Einrueckung und
// Leerraum zwischen Token) wird durch so viele Leerzeichen ersetzt, dass die
// Anzeigespalte bis zum naechsten Tabstopp erhalten bleibt. Ein Tab nach
// Leerzeichen springt also auf den naechsten Stopp, nicht um eine ganze
// Tabweite weiter. Tabs in Strings und Kommentaren bleiben unangetastet
// (sie sind Inhalt, nicht Layout); zwischen dem ersten und dem letzten
// Code-Tab zaehlen sie in der Spaltenrechnung mit derselben Tabweite. Der
// Planer meldet EINE Ersetzung vom ersten bis zum letzten Code-Tab der
// Zeile; der Text dazwischen bleibt wie er ist.
//
// TABWEITE (TabWidth, Realworld-Test rwE29: bis dahin fest 2, und sechs
// fuer Tabweite 8 ausgerichtete Tabellen und Direktiven - Indy, PascalScript,
// JVCL, DirectShow - verloren ihre Ausrichtung): die Hilfe leitet sie aus
// der Datei ab. Je Kandidat (TAB_CANDIDATES: 2, 4, 8) rechnet sie die
// Spalten, an denen nach einem Leerraum mit Code-Tab der Text der Zeile
// weitergeht ('Anker'), und zaehlt, wie viele Nachbarzeilen (NEIGHBOUR_LINES
// darueber und darunter, ihr Rohtext, mit derselben Weite gerechnet) an
// derselben Spalte ebenfalls einen Anker haben - fuer die Einrueckung
// (Anker am Zeilenanfang) jeden, sonst einen mit demselben Zeichen ('=',
// ':', '//'). Beweis ist, was nur EINE Weite erklaert: eine Nachbarzeile
// mit Leerzeichen statt Tabs ('<TAB>      {$else}' unter 14 Leerzeichen)
// oder mit anderer Tab-Zahl vor derselben Spalte ('TS_R_BAD_TYPE<TAB>x5 ='
// gegen 'TS_R_BAD_PKCS7_TYPE<TAB>x4 ='). Erklaeren alle Weiten gleich viel
// (reine Tab-Einrueckung, Nachbarn mit denselben Tabs), gilt die Vorgabe
// DEFAULT_TAB_WIDTH = 2 (eine ANNAHME, nicht die Option 'Tab stops' der
// IDE - der Kern kennt keine ToolsAPI); erklaeren zwei Weiten ohne die
// Vorgabe gleich viel, ist die Weite offen (Sperre). Der Hinweis nennt die
// Weite und woher sie kommt (der Adapter PlanTabs setzt ihn).
//
// SPERREN (lieber keine Hilfe als eine falsche): die Spalte der Meldung
// ist kein Tab oder nicht der erste der Zeile (Zeile verschoben), der ERSTE
// Tab der Zeile liegt in einem String oder Kommentar (der Fund bliebe
// stehen), die Nachbarzeilen passen zu zwei Tabweiten gleich gut. Nur die
// gemeldete Zeile - der Massenmodus kommt spaeter.
//
// OHNE ToolsAPI und ohne Delphi-only-Unit (FPC-Pruefstand): den Adapter
// PlanTabs (Form TRdxFixPlanner) traegt die Tabelle uRdxFixTable.

interface

uses
  uRdxBufferMath,    // TRdxEdit
  uRdxCodeMap;       // TRdxCodeMap

const
  // Tabweite, wenn die Nachbarzeilen keine beweisen: eine Annahme, nicht
  // die der IDE (s. Kopf). Bis rwE29 die einzige (TAB_WIDTH).
  DEFAULT_TAB_WIDTH = 2;
  // So viele Zeilen darueber und darunter liest TabWidth.
  NEIGHBOUR_LINES = 8;

type
  // Woher die Tabweite von TabWidth kommt.
  //   twDefault    die Nachbarzeilen beweisen keine - DEFAULT_TAB_WIDTH
  //   twDerived    genau eine Weite erklaert die Nachbarzeilen am besten
  //   twAmbiguous  zwei Weiten ohne die Vorgabe gleich gut - Sperre
  TRdxTabWidthSource = (twDefault, twDerived, twAmbiguous);

  // Der Planer von SCA061 (Form TRdxMapPlanner, uRdxFixRunner).
  TRdxTabsFix = class
  public
    // SCA061: die Tabs im Code von ALine -> Leerzeichen bis zum naechsten
    // Tabstopp (Weite aus TabWidth). Spalte aus der Meldung ('Tab character
    // at column N').
    class function Tabs(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // Die Tabweite fuer ALine aus den Nachbarzeilen (s. Kopf); bei
    // twAmbiguous die kleinere der beiden Weiten, AOther die groessere -
    // sonst AOther = 0. Fuer Tabs und den Hinweis des Adapters.
    class function TabWidth(AMap: TRdxCodeMap; ALine: Integer;
      out ASource: TRdxTabWidthSource; out AOther: Integer): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,   // TRefactorSpan.Make
  uRdxText;        // _(), MsgNoColumn, MsgMovedSuffix, MsgByHand (E29)

const
  TAB = #9;
  SPAN_061 = 'sca061';
  // Die Weiten, unter denen TabWidth waehlt (2 die Vorgabe, 4 und 8 die
  // gaengigen Editor-Einstellungen).
  TAB_CANDIDATE_COUNT = 3;
  TAB_CANDIDATES: array[0..TAB_CANDIDATE_COUNT - 1] of Integer = (2, 4, 8);
  // Die Gruende als englische msgids (E29), uebersetzt mit _() aus
  // uRdxText; Deutsch und Franzoesisch in i18n/de.po und i18n/fr.po. Das
  // Ende ' - Zeile verschoben? ...' haengt MsgMovedSuffix an.
  R_TAB_MOVED = 'no tab at the reported place';
  R_TAB_NOT_CODE = 'the first tab of the line is inside a string or comment '
    + '- it stays untouched, the help would leave the finding in place';
  // %d, %d die beiden Weiten, %s MsgByHand.
  R_TAB_AMBIGUOUS = 'the neighbouring lines fit tab width %d as well as %d - '
    + 'which one the alignment of the file follows is open; %s';

type
  // Ein Anker (s. Kopf): die Anzeigespalte (0-basiert), an der hinter einem
  // Leerraum der Text weitergeht, ob der Leerraum am Zeilenanfang steht
  // (Einrueckung), und das Zeichen dort.
  TRdxTabAnchor = record
    Col  : Integer;
    Lead : Boolean;
    Ch   : Char;
  end;
  TRdxTabAnchors = array of TRdxTabAnchor;

function IsSpaceOrTab(C: Char): Boolean;
begin
  Result := (C = ' ') or (C = TAB);
end;

// Die Anker von AText bei Tabweite AWidth. Mit AMap: nur hinter einem
// Leerraum, der einen Code-Tab der Zeile ALine traegt (die gemeldete Zeile -
// nur dort bewegt die Weite den Text); ohne (nil): hinter jedem Leerraum
// (Nachbarzeilen, Rohtext).
function AnchorsOf(const AText: string; AWidth: Integer; AMap: TRdxCodeMap;
  ALine: Integer): TRdxTabAnchors;
var
  i, j, V, n : Integer;
  CodeTab    : Boolean;
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
    CodeTab := False;
    while (j <= Length(AText)) and IsSpaceOrTab(AText[j]) do
    begin
      if AText[j] = TAB then
      begin
        if (AMap <> nil) and AMap.IsCode(ALine, j) then
          CodeTab := True;
        Inc(V, AWidth - (V mod AWidth));
      end
      else
        Inc(V);
      Inc(j);
    end;
    if (j <= Length(AText)) and ((AMap = nil) or CodeTab) then
    begin
      SetLength(Result, n + 1);
      Result[n].Col := V;
      Result[n].Lead := i = 1;
      Result[n].Ch := AText[j];
      Inc(n);
    end;
    i := j;
  end;
end;

// Wie viele Anker von AOwn trifft ANeighbour (s. Kopf: Einrueckung auf
// Einrueckung, sonst dasselbe Zeichen an derselben Spalte)?
function AnchorHits(const AOwn, ANeighbour: TRdxTabAnchors): Integer;
var
  a, b : Integer;
begin
  Result := 0;
  for a := 0 to High(AOwn) do
    for b := 0 to High(ANeighbour) do
      if (AOwn[a].Col = ANeighbour[b].Col)
         and ((AOwn[a].Lead and ANeighbour[b].Lead)
           or (AOwn[a].Ch = ANeighbour[b].Ch)) then
      begin
        Inc(Result);
        Break;
      end;
end;

// Die Treffer der Anker von ALine in den Nachbarzeilen bei Weite AWidth.
function WidthScore(AMap: TRdxCodeMap; ALine, AWidth: Integer): Integer;
var
  Own : TRdxTabAnchors;
  k   : Integer;
  N   : string;
begin
  Result := 0;
  Own := AnchorsOf(AMap.Raw(ALine), AWidth, AMap, ALine);
  if Length(Own) = 0 then Exit;
  for k := ALine - NEIGHBOUR_LINES to ALine + NEIGHBOUR_LINES do
  begin
    if (k < 1) or (k > AMap.LineCount) or (k = ALine) then Continue;
    N := AMap.Raw(k);
    if IsBlankLine(N) then Continue;
    Inc(Result, AnchorHits(Own, AnchorsOf(N, AWidth, nil, k)));
  end;
end;

class function TRdxTabsFix.TabWidth(AMap: TRdxCodeMap; ALine: Integer;
  out ASource: TRdxTabWidthSource; out AOther: Integer): Integer;
var
  Score       : array[0..TAB_CANDIDATE_COUNT - 1] of Integer;
  i, Best, n  : Integer;
  First, Last : Integer;
  HasDefault  : Boolean;
begin
  AOther := 0;
  Best := 0;
  for i := 0 to High(TAB_CANDIDATES) do
  begin
    Score[i] := WidthScore(AMap, ALine, TAB_CANDIDATES[i]);
    if Score[i] > Best then
      Best := Score[i];
  end;
  // Die Weiten mit dem besten Wert: wie viele, die erste, die letzte, und
  // ob die Vorgabe darunter ist.
  n := 0;
  First := 0;
  Last := 0;
  HasDefault := False;
  for i := 0 to High(TAB_CANDIDATES) do
    if Score[i] = Best then
    begin
      if n = 0 then
        First := TAB_CANDIDATES[i];
      Last := TAB_CANDIDATES[i];
      Inc(n);
      if TAB_CANDIDATES[i] = DEFAULT_TAB_WIDTH then
        HasDefault := True;
    end;
  if n = 1 then
  begin
    ASource := twDerived;
    Result := First;
  end
  else if (n = TAB_CANDIDATE_COUNT) or HasDefault then
  begin
    // Alle gleich (kein Beweis) oder die Vorgabe unter den besten: die
    // Vorgabe widerspricht den Nachbarzeilen nicht.
    ASource := twDefault;
    Result := DEFAULT_TAB_WIDTH;
  end
  else
  begin
    ASource := twAmbiguous;
    Result := First;
    AOther := Last;
  end;
end;

class function TRdxTabsFix.Tabs(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  L, S        : string;
  Col, First  : Integer;
  Last, i, V  : Integer;
  n, W, Other : Integer;
  Source      : TRdxTabWidthSource;
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
  if (Col > Length(L)) or (L[Col] <> TAB) or (Pos(TAB, L) <> Col) then
  begin
    AReason := MsgMovedSuffix(_(R_TAB_MOVED));
    Exit;
  end;
  if not AMap.IsCode(ALine, Col) then
  begin
    AReason := _(R_TAB_NOT_CODE);
    Exit;
  end;
  W := TabWidth(AMap, ALine, Source, Other);
  if Source = twAmbiguous then
  begin
    AReason := _(R_TAB_AMBIGUOUS, [W, Other, MsgByHand]);
    Exit;
  end;
  // Erster und letzter Code-Tab; der Text dazwischen wird mitgefuehrt.
  First := Col;
  Last := Col;
  for i := Col to Length(L) do
    if (L[i] = TAB) and AMap.IsCode(ALine, i) then
      Last := i;
  // Anzeigespalte (0-basiert) vor First: davor steht kein Tab (First ist
  // der erste Tab der Zeile, s. oben), jedes Zeichen zaehlt eine Spalte.
  V := First - 1;
  S := '';
  for i := First to Last do
    if L[i] <> TAB then
    begin
      S := S + L[i];
      Inc(V);
    end
    else
    begin
      n := W - (V mod W);
      if AMap.IsCode(ALine, i) then
        S := S + StringOfChar(' ', n)
      else
        S := S + TAB;
      Inc(V, n);
    end;
  AEdit.Span := TRefactorSpan.Make(SPAN_061, ALine, First, ALine, Last + 1);
  AEdit.Expected := Copy(L, First, Last + 1 - First);
  AEdit.NewText := S;
  Result := True;
end;

end.

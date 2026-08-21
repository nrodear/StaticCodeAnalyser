unit uHintTextLayout;

// Reine Text-Layout-Logik des Nur-Text-Annotation-Hints
// (Konzept_AnnotationHint_NurText_2026-08-09, Weg B). Bewusst OHNE
// Canvas: die Breite kommt ueber einen Mess-Callback herein, damit die
// Kuerzungsregeln ohne IDE und ohne Fenster testbar sind - der
// Zeichenpfad selbst (uIDELineHighlighter) bleibt untestbar, seine
// Logik soll deshalb hier so duenn wie moeglich ankommen.
//
// KURZFORM STATT TITEL (Messung 0.3 vom 2026-08-12): die Titellaengen
// des Self-Scans liegen bei Median 96 Zeichen, nur ~24 % passen in 60
// Zeichen Restbreite - die Mehrheit passt nicht. Laut Todo-Abnahme wird
// deshalb NICHT der Titel gekuerzt, sondern die Kurzform
// "Badge <Gedankenstrich> Regelname" gezeichnet; der volle Titel bleibt
// dem Findings-Panel ueberlassen.

interface

uses
  System.SysUtils;

const
  // Zeichen als Codes statt Literale - die Quelltexte des Projekts sind
  // nicht durchgaengig UTF-8-markiert, ein rohes Literal koennte beim
  // Speichern in der IDE kippen.
  HINT_ELLIPSIS = #$2026;   // Horizontal Ellipsis
  HINT_SEP      = #$2014;   // Em Dash

// Kurzform des Text-Hints: 'Badge <Em-Dash> Regelname'. Leere Teile
// fallen weg (nur Badge bzw. nur Regelname), beide leer -> ''.
function ComposeTextHint(const ABadge, ARuleName: string): string;
  overload;

// Dreiteilige Fassung mit den weiteren Fundstellen (SCA015/SCA021).
// Leeres ASites faellt weg - dann identisch zur zweiteiligen Form.
function ComposeTextHint(const ABadge, ARuleName,
  ASites: string): string; overload;

// 'Auch in Zeile(n): 6, 7, 12, 45 ...' aus dem Rohwert von
// TLeakFinding.RelatedLines (komma-getrennte Zeilennummern).
// Zeigt hoechstens HINT_MAX_SITES Nummern; gibt es mehr, folgt eine
// Ellipse statt einer Zahl - RelatedLines ist im Detektor gedeckelt,
// ein Zaehler daraus wuerde dem '26x' im Meldetext widersprechen.
// Leerer oder unbrauchbarer Eingabewert -> ''.
function FormatRelatedLines(const ARelated: string): string;

// Kuerzt AText so, dass AMeasure(Ergebnis) <= AMaxWidthPx bleibt.
// Passt der Text ganz, kommt er unveraendert zurueck; sonst wird auf
// das laengste Praefix + Ellipse gekuerzt (Binaersuche ueber die
// Praefixlaenge - AMeasure ist in der Praefixlaenge monoton). Passt
// nicht einmal ein Zeichen + Ellipse, kommt '' zurueck - der Aufrufer
// zeichnet dann gar nicht (nie ein hart abgeschnittener Rest).
// Vor der Ellipse bleibt weder ein Leerzeichen noch ein halbes
// Surrogatpaar stehen (Emoji im Badge).
function ShortenToWidth(const AText: string; AMaxWidthPx: Integer;
  const AMeasure: TFunc<string, Integer>): string;

// Nimmt die Fassungen von der laengsten zur kuerzesten und liefert die
// ERSTE, die in AMaxWidthPx passt. Passt keine, wird die LETZTE
// (kuerzeste) wie bisher per Ellipse gekuerzt.
//
// Warum gestuft statt einfach kuerzen: haengt man die Fundstellen an
// und kuerzt dann stumpf, frisst die Ellipse zuerst die Zeilennummern
// und danach den REGELNAMEN - der Hint zeigte dann 'Code Smell - Dupli...'
// statt der vollstaendigen Kurzform. Die Stufen geben die unwichtigere
// Information zuerst auf.
function FitStagedHint(const AStufen: array of string;
  AMaxWidthPx: Integer; const AMeasure: TFunc<string, Integer>): string;

const
  // Hoechstens so viele Zeilennummern im Hint - Nutzervorgabe
  // 2026-08-20. Der Rest wird zur Ellipse.
  HINT_MAX_SITES = 4;

// ---------------------------------------------------------------------
// "Die Fundzeile wurde bearbeitet" - Ziel 2 des Konzepts
// ---------------------------------------------------------------------
// Der Zeichenpfad nimmt beim ERSTEN Anblick einer markierten Zeile einen
// Schnappschuss ihres Textes und vergleicht ihn bei jedem weiteren
// Repaint. Weicht er ab, wurde die Zeile bearbeitet - der Fund ist bis
// zum naechsten Scan nicht mehr belegt und die Markierung faellt.
//
// Warum das hier liegt und nicht im Zeichenpfad: es ist die einzige
// ENTSCHEIDUNG des Merkmals, und ohne Canvas und ohne IDE pruefbar.
// uIDELineHighlighter bleibt untestbar; was dort ankommt, soll so duenn
// wie moeglich sein - dieselbe Begruendung wie fuer die Kuerzungsregeln
// oben.
//
// Warum ueberhaupt eine Kodierung: der Schnappschuss liegt an der Marke
// (TFindingMark.SrcText), und '' muss "noch nie gesehen" bedeuten. Eine
// echte LEERE Zeile waere davon sonst nicht zu unterscheiden - in einem
// Mehrzeilen-Befund traegt jede Zeile eine eigene Marke, Leerzeilen
// eingeschlossen; sie wuerde nie als bearbeitet erkannt. Ein zweites
// Feld "HasSnapshot: Boolean" waere die naheliegende Alternative und die
// gefaehrlichere: von einem Record initialisiert Delphi nur die
// VERWALTETEN Felder (Strings) verlaesslich, ein Boolean kann mit Muell
// starten - und haette dann Marken beim allerersten Repaint geloescht.
//
// Der Vergleich ist ROH (Entscheidung 2 des Konzepts): eine geaenderte
// Einrueckung ist eine Aenderung. Ein Formatierer ueber die ganze Datei
// raeumt damit alle Marken ab - bewusst in Kauf genommen, der naechste
// Scan stellt sie wieder her.
const
  // Praefix, das einen genommenen Schnappschuss von "keiner" trennt.
  //
  // Die tragende Eigenschaft ist NICHT "#1 kommt in Quelltext nicht vor" -
  // das waere fuer einen Editor-PUFFER auch gar nicht garantiert, der
  // haelt jedes eingefuegte Steuerzeichen. Sie ist: EncodeLineSnapshot
  // haengt das Praefix BEDINGUNGSLOS an, ist damit injektiv und liefert
  // nie ''. Encode(#1 + 'x') = #1#1'x' bleibt also von Encode('x')
  // unterscheidbar, und '' bleibt eindeutig "noch nie gesehen" - auch
  // fuer eine Zeile, die selbst mit #1 beginnt (Review 2026-08-21; die
  // erste Fassung begruendete es mit der staerkeren, unnoetigen und
  // fuer den Puffer falschen Annahme).
  SNAPSHOT_MARK = #1;

// Kodiert einen Zeilentext zum Schnappschuss. Ergebnis ist nie leer.
function EncodeLineSnapshot(const ALineText: string): string;

// True, wenn ASnapshot einen Schnappschuss traegt UND ACurrentText davon
// abweicht. Ohne Schnappschuss ('') immer False: eine Zeile, die noch nie
// gemalt wurde, kann nicht als bearbeitet gelten.
//
// VERTRAG: ASnapshot ist entweder '' oder eine Ausgabe von
// EncodeLineSnapshot - NIE roher Zeilentext. Roh hereingereicht meldet die
// Funktion "bearbeitet", auch wenn beide Texte gleich sind (das Praefix
// fehlt dann auf einer Seite). Der einzige Aufrufer haelt das ein
// (TFindingHighlighter.NoteLineText), ein Test pinnt es.
function LineWasEdited(const ASnapshot, ACurrentText: string): Boolean;


implementation

uses
  System.Character,
  uLocalization;   // _() fuer die Zeilen-Beschriftung

function ComposeTextHint(const ABadge, ARuleName: string): string;
var
  Badge, Rule : string;
begin
  Badge := Trim(ABadge);
  Rule  := Trim(ARuleName);
  if Rule = '' then Exit(Badge);
  if Badge = '' then Exit(Rule);
  Result := Badge + ' ' + HINT_SEP + ' ' + Rule;
end;

function ComposeTextHint(const ABadge, ARuleName,
  ASites: string): string;
var
  Kurz, Sites : string;
begin
  Kurz  := ComposeTextHint(ABadge, ARuleName);
  Sites := Trim(ASites);
  if Sites = '' then Exit(Kurz);
  if Kurz  = '' then Exit(Sites);
  Result := Format('%s %s %s', [Kurz, HINT_SEP, Sites]);
end;

function FormatRelatedLines(const ARelated: string): string;
var
  Teile : TArray<string>;
  Zeig  : Integer;
  i     : Integer;
  SB    : TStringBuilder;
  Teil  : string;
begin
  Result := '';
  if Trim(ARelated) = '' then Exit;
  Teile := Trim(ARelated).Split([',']);
  SB := TStringBuilder.Create;
  try
    Zeig := 0;
    for i := Low(Teile) to High(Teile) do
    begin
      Teil := Trim(Teile[i]);
      // '6,,7' oder Endkomma - leere Stuecke sind keine Fundstelle.
      if Teil = '' then
      begin
        Continue;
      end;
      if Zeig >= HINT_MAX_SITES then
      begin
        SB.Append(' ').Append(HINT_ELLIPSIS);
        Break;
      end;
      if Zeig > 0 then
      begin
        SB.Append(', ');
      end;
      SB.Append(Teil);
      Inc(Zeig);
    end;
    if Zeig = 0 then Exit('');
    Result := Format(_('Also at line(s): %s'), [SB.ToString]);
  finally
    SB.Free;
  end;
end;

function FitStagedHint(const AStufen: array of string;
  AMaxWidthPx: Integer; const AMeasure: TFunc<string, Integer>): string;
var
  i      : Integer;
  Kand   : string;
  Letzte : string;
begin
  Letzte := '';
  for i := Low(AStufen) to High(AStufen) do
  begin
    Kand := Trim(AStufen[i]);
    if Kand = '' then Continue;
    Letzte := Kand;
    // Ohne Messfunktion ist keine Aussage moeglich - dann die laengste
    // Fassung liefern, wie ShortenToWidth es auch haelt.
    if not Assigned(AMeasure) then Exit(Kand);
    if AMeasure(Kand) <= AMaxWidthPx then Exit(Kand);
  end;
  Result := ShortenToWidth(Letzte, AMaxWidthPx, AMeasure);
end;

function ShortenToWidth(const AText: string; AMaxWidthPx: Integer;
  const AMeasure: TFunc<string, Integer>): string;
var
  Lo, Hi, Mid : Integer;
begin
  Result := Trim(AText);
  if Result = '' then Exit;
  // Ohne Messfunktion ist keine Aussage moeglich - lieber unveraendert
  // zurueckgeben als raten (der Aufrufer clampt ohnehin am Zeilenrand).
  if not Assigned(AMeasure) then Exit;
  if AMeasure(Result) <= AMaxWidthPx then Exit;

  // Binaersuche ueber die behaltene Praefixlaenge: groesstes Praefix,
  // dessen Breite samt Ellipse noch passt.
  Lo := 0;
  Hi := Length(Result) - 1;
  while Lo < Hi do
  begin
    Mid := (Lo + Hi + 1) div 2;
    if AMeasure(Copy(Result, 1, Mid) + HINT_ELLIPSIS) <= AMaxWidthPx then
    begin
      Lo := Mid;
    end
    else
    begin
      Hi := Mid - 1;
    end;
  end;
  if Lo = 0 then Exit('');

  // Weissraum direkt vor der Ellipse saehe wie ein Wortrest aus.
  Result := TrimRight(Copy(Result, 1, Lo));
  // Kein haengendes High-Surrogate (Badge-Emoji sind Surrogatpaare).
  if (Result <> '') and Result[Length(Result)].IsHighSurrogate then
  begin
    SetLength(Result, Length(Result) - 1);
    // Der Drop kann Weissraum freilegen ('AB ' + halbes Emoji): ohne
    // zweites TrimRight stuende genau das Leerzeichen vor der Ellipse,
    // das der Vertrag ausschliesst (Review 2026-08-13).
    Result := TrimRight(Result);
  end;
  if Result = '' then Exit('');
  Result := Result + HINT_ELLIPSIS;
end;

function EncodeLineSnapshot(const ALineText: string): string;
begin
  Result := SNAPSHOT_MARK + ALineText;
end;

function LineWasEdited(const ASnapshot, ACurrentText: string): Boolean;
// Ohne Allokation: die naheliegende Fassung
// 'ASnapshot <> EncodeLineSnapshot(ACurrentText)' baut pro Aufruf einen
// neuen String (Praefix + Vollkopie der Zeile), der sofort wieder stirbt.
// Diese Funktion laeuft im Zeichenpfad je markierter Zeile und Repaint -
// dort ist der Muell nicht noetig (Review 2026-08-21). Geprueft wird
// stattdessen direkt gegen ASnapshot: Laenge muss um genau das Praefix
// groesser sein, der Rest zeichenweise gleich.
begin
  if ASnapshot = '' then Exit(False);
  Result := not ((Length(ASnapshot) = Length(ACurrentText) + 1)
             and CompareMem(PChar(ASnapshot) + 1, PChar(ACurrentText),
                            Length(ACurrentText) * SizeOf(Char)));
end;

end.

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

end.

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

implementation

uses
  System.Character;

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
  end;
  if Result = '' then Exit('');
  Result := Result + HINT_ELLIPSIS;
end;

end.

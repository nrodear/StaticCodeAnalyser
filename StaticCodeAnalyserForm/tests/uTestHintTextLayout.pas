unit uTestHintTextLayout;

// Tests fuer uHintTextLayout (SCA.SharedUI) - die Kuerzungs- und
// Kompositionsregeln des Nur-Text-Annotation-Hints.
//
// Der Zeichenpfad selbst (uIDELineHighlighter.DrawTextHint) bleibt
// ungedeckt - uIDE*-Units liegen in keinem Testprojekt. Deshalb ist die
// Logik dort so duenn wie moeglich und die Regeln leben hier: die Breite
// kommt als Mess-Callback herein, im Test eine feste Breite je
// UTF-16-Einheit.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestHintTextLayout = class
  public
    [Test] procedure Compose_BadgeAndRule_JoinedWithEmDash;
    [Test] procedure Compose_MissingParts_FallBackToTheOther;
    [Test] procedure Shorten_FittingText_StaysUntouched;
    [Test] procedure Shorten_LongText_GetsPrefixPlusEllipsis;
    [Test] procedure Shorten_TooNarrow_YieldsEmpty;
    [Test] procedure Shorten_NoSpaceBeforeEllipsis;
    [Test] procedure Shorten_CutAtSurrogatePair_DropsHalfChar;
    [Test] procedure Shorten_CutAtSurrogateAfterSpace_TrimsAgain;
    // Fundstellen im Nur-Text-Hint (2026-08-20, SCA015/SCA021)
    [Test] procedure Sites_UpToFourNumbers_ThenEllipsis;
    [Test] procedure Sites_EmptyOrBlank_YieldsNothing;
    [Test] procedure Sites_StripsBlanksAndEmptyParts;
    [Test] procedure Staged_LongestStageWins_WhenItFits;
    [Test] procedure Staged_FallsBackToShorterStage_WhenTooNarrow;
    [Test] procedure Staged_NoStageFits_ShortensTheLastOne;
  end;

implementation

uses
  System.SysUtils, uHintTextLayout;

const
  PX_PER_CHAR = 7;
  RULE_NAME   = 'MemoryLeak';

function FixedMeasure(S: string): Integer;
// Deterministische Messfunktion: 7 px je UTF-16-Einheit. Monoton in der
// Praefixlaenge - genau die Eigenschaft, die die Binaersuche braucht.
begin
  Result := Length(S) * PX_PER_CHAR;
end;

procedure TTestHintTextLayout.Compose_BadgeAndRule_JoinedWithEmDash;
begin
  Assert.AreEqual('BUG ' + HINT_SEP + ' ' + RULE_NAME,
    ComposeTextHint('BUG', RULE_NAME));
end;

procedure TTestHintTextLayout.Compose_MissingParts_FallBackToTheOther;
begin
  Assert.AreEqual('BUG', ComposeTextHint('BUG', '   '),
    'Leerer Regelname -> nur Badge');
  Assert.AreEqual(RULE_NAME, ComposeTextHint('', RULE_NAME),
    'Leerer Badge -> nur Regelname');
  Assert.AreEqual('', ComposeTextHint(' ', ''), 'Beides leer -> leer');
end;

procedure TTestHintTextLayout.Shorten_FittingText_StaysUntouched;
begin
  Assert.AreEqual('kurz',
    ShortenToWidth('kurz', 10 * PX_PER_CHAR, FixedMeasure));
end;

procedure TTestHintTextLayout.Shorten_LongText_GetsPrefixPlusEllipsis;
var
  S : string;
begin
  // 20 Zeichen Budget: laengstes Praefix + Ellipse = 19 + 1 Zeichen.
  S := ShortenToWidth(StringOfChar('a', 40), 20 * PX_PER_CHAR, FixedMeasure);
  Assert.AreEqual(StringOfChar('a', 19) + HINT_ELLIPSIS, S);
  Assert.IsTrue(FixedMeasure(S) <= 20 * PX_PER_CHAR,
    'Das Ergebnis muss in das Budget passen');
end;

procedure TTestHintTextLayout.Shorten_TooNarrow_YieldsEmpty;
begin
  // Budget unter 2 Zeichen: nicht mal 1 Zeichen + Ellipse passt ->
  // leer, der Aufrufer zeichnet gar nicht (nie ein abgeschnittener Rest).
  Assert.AreEqual('',
    ShortenToWidth('irgendwas', PX_PER_CHAR, FixedMeasure));
end;

procedure TTestHintTextLayout.Shorten_NoSpaceBeforeEllipsis;
var
  S : string;
begin
  // Der Schnitt landet direkt hinter 'ab ' - das Leerzeichen vor der
  // Ellipse muss weg (Leerzeichen+Ellipse saehe wie ein Wortrest aus).
  S := ShortenToWidth('ab cdefghij', 4 * PX_PER_CHAR, FixedMeasure);
  Assert.AreEqual('ab' + HINT_ELLIPSIS, S);
end;

procedure TTestHintTextLayout.Shorten_CutAtSurrogatePair_DropsHalfChar;
const
  EMOJI = #$D83D#$DC1E;   // Marienkaefer, 2 UTF-16-Einheiten
var
  S : string;
begin
  // Budget 4 Einheiten: Praefix (3) + Ellipse (1). Einheit 3 ist die
  // ERSTE Haelfte des Emojis - sie darf nicht als halbes Zeichen vor
  // der Ellipse stehen bleiben.
  S := ShortenToWidth('ab' + EMOJI + 'cdef', 4 * PX_PER_CHAR, FixedMeasure);
  Assert.AreEqual('ab' + HINT_ELLIPSIS, S);
end;

procedure TTestHintTextLayout.Shorten_CutAtSurrogateAfterSpace_TrimsAgain;
// REGRESSION (Review 2026-08-13): TrimRight lief VOR dem Surrogat-Drop.
// Endet der Schnitt auf Weissraum + High-Surrogate ('ab ' + halbes
// Emoji), entfernte TrimRight nichts (das Surrogate schirmt ab), der
// Drop legte das Leerzeichen frei - und vor der Ellipse stand genau der
// Wortrest, den der Vertrag ausschliesst.
const
  EMOJI = #$D83D#$DC1E;
var
  S : string;
begin
  // 9 Einheiten, Budget 5: Praefix (4) + Ellipse = 'ab ' + High-Surrogate.
  S := ShortenToWidth('ab ' + EMOJI + 'cdef', 5 * PX_PER_CHAR, FixedMeasure);
  Assert.AreEqual('ab' + HINT_ELLIPSIS, S);
end;

procedure TTestHintTextLayout.Sites_UpToFourNumbers_ThenEllipsis;
// Nutzervorgabe: hoechstens VIER Nummern; der Rest wird zur Ellipse,
// BEWUSST keine Zahl - RelatedLines ist im Detektor gedeckelt, ein
// Zaehler daraus wuerde dem '26x' im Meldetext widersprechen.
var
  S : string;
begin
  S := FormatRelatedLines('6,7,12,45,99,120');
  Assert.IsTrue(S.Contains('6, 7, 12, 45'),
    'die ersten vier Nummern muessen erscheinen: ' + S);
  Assert.IsFalse(S.Contains('99'),
    'die fuenfte Nummer darf NICHT erscheinen: ' + S);
  Assert.IsTrue(S.Contains(HINT_ELLIPSIS),
    'bei mehr als vier muss eine Ellipse folgen: ' + S);
end;

procedure TTestHintTextLayout.Sites_EmptyOrBlank_YieldsNothing;
// Alle anderen Regeln liefern ein leeres RelatedLines - dann darf der
// Hint keine leere Beschriftung tragen.
begin
  Assert.AreEqual('', FormatRelatedLines(''));
  Assert.AreEqual('', FormatRelatedLines('   '));
  Assert.AreEqual('', FormatRelatedLines(',,'));
end;

procedure TTestHintTextLayout.Sites_StripsBlanksAndEmptyParts;
// Leere Stuecke ('6,,7') und Endkommata duerfen keine Luecken oder
// haengenden Trenner erzeugen.
var
  S : string;
begin
  S := FormatRelatedLines(' 6 , ,7, ');
  Assert.IsTrue(S.Contains('6, 7'), 'erwartet 6, 7 - war: ' + S);
  Assert.IsFalse(S.Contains(HINT_ELLIPSIS),
    'zwei Nummern brauchen keine Ellipse: ' + S);
end;

procedure TTestHintTextLayout.Staged_LongestStageWins_WhenItFits;
// Stufe 1 traegt die Fundstellen und gewinnt, solange sie passt.
const
  STUFE1 = 'Hint mit Stellen';
  STUFE2 = 'Hint';
begin
  Assert.AreEqual(STUFE1,
    FitStagedHint([STUFE1, STUFE2], 40 * PX_PER_CHAR, FixedMeasure));
end;

procedure TTestHintTextLayout.Staged_FallsBackToShorterStage_WhenTooNarrow;
// Zu schmal fuer Stufe 1: die naechste Stufe kommt UNGEKUERZT - genau
// dafuer gibt es die Leiter. Stumpfes Kuerzen haette stattdessen die
// Ellipse in den Regelnamen geschoben.
const
  STUFE1 = 'viel zu lang fuer das Budget';
  STUFE2 = 'passt';
begin
  Assert.AreEqual(STUFE2,
    FitStagedHint([STUFE1, STUFE2], 6 * PX_PER_CHAR, FixedMeasure));
end;

procedure TTestHintTextLayout.Staged_NoStageFits_ShortensTheLastOne;
// Passt keine Stufe, wird die KUERZESTE per Ellipse gekuerzt -
// bisheriges Verhalten, nur eine Stufe tiefer.
var
  S : string;
begin
  S := FitStagedHint([StringOfChar('a', 40), StringOfChar('b', 20)],
                     10 * PX_PER_CHAR, FixedMeasure);
  Assert.AreEqual(StringOfChar('b', 9) + HINT_ELLIPSIS, S);
  Assert.IsTrue(FixedMeasure(S) <= 10 * PX_PER_CHAR,
    'auch die Rueckfall-Kuerzung muss ins Budget passen');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestHintTextLayout);

end.

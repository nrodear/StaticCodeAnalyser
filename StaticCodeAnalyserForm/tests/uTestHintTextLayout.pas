unit uTestHintTextLayout;

// Tests fuer uHintTextLayout (SCA.SharedUI) - die Kuerzungs- und
// Kompositionsregeln des Nur-Text-Annotation-Hints und die
// Schnappschuss-Regel "die Fundzeile wurde bearbeitet" (Ziel 2).
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

  // Eigene Fixture, nicht bloss Ordnungsliebe: die Schnappschuss-Regel
  // ("wurde die Fundzeile bearbeitet?", Ziel 2 des Konzepts 2026-08-09)
  // ist eine andere Verantwortlichkeit als das Text-Layout des Hints -
  // sie kennt weder Breiten noch Canvas noch einen Mess-Callback.
  // Zusammen in einer Klasse waren es 22 Testroutinen, und der eigene
  // GodClass-Detektor hat sie zu Recht gemeldet.
  [TestFixture]
  TTestLineSnapshot = class
  public
    [Test] procedure Snapshot_OfAnyLine_IsNeverEmpty;
    [Test] procedure Snapshot_Missing_MeansNeverEdited;
    [Test] procedure Snapshot_SameText_MeansNotEdited;
    [Test] procedure Snapshot_ChangedText_MeansEdited;
    [Test] procedure Snapshot_EmptyLine_IsWatchedLikeAnyOther;
    [Test] procedure Snapshot_IndentationChange_CountsAsEdit;
    [Test] procedure Snapshot_RawTextAsSnapshot_CountsAsEdited;
    [Test] procedure Snapshot_LineStartingWithSentinel_StaysDistinguishable;
  end;

implementation

// noinspection-file ClassPerFile
// Zwei Fixtures in einer Datei, und zwar bewusst: sie pruefen dieselbe
// Unit uHintTextLayout, nur ihre zwei getrennten Verantwortlichkeiten
// (Text-Layout des Hints und die Schnappschuss-Regel von Ziel 2). Sie
// zu trennen war der Punkt - sie auf zwei DATEIEN zu verteilen brachte
// nichts ausser einem zweiten Projektdatei-Eintrag. Dasselbe Muster
// tragen sechs weitere Testunits dieses Projekts.

uses
  System.SysUtils, uHintTextLayout;

const
  PX_PER_CHAR = 7;
  RULE_NAME   = 'MemoryLeak';
  // Beispiel-Fundzeile der Schnappschuss-Tests. Als Konstante, weil der
  // Selbst-Scan sie sonst als DuplicateString meldet - und die Baseline
  // anzufassen waere hier die falsche Antwort.
  SRC_LINE    = '  Foo.Free;';

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

{ ---- Schnappschuss der Fundzeile (Ziel 2) ---- }

procedure TTestLineSnapshot.Snapshot_OfAnyLine_IsNeverEmpty;
// Traegt der Vertrag: '' heisst "kein Schnappschuss". Eine Kodierung, die
// fuer irgendeine Eingabe '' liefert, macht diese Zeile blind.
begin
  Assert.AreNotEqual('', EncodeLineSnapshot(''),
    'auch die leere Zeile bekommt einen Schnappschuss');
  Assert.AreNotEqual('', EncodeLineSnapshot(SRC_LINE));
end;

procedure TTestLineSnapshot.Snapshot_Missing_MeansNeverEdited;
// Eine Zeile, die noch nie gemalt wurde, kann nicht bearbeitet worden
// sein. Andersherum waere jede frisch gesetzte Marke beim ersten Repaint
// weg - das Merkmal haette sich selbst aufgefressen.
begin
  Assert.IsFalse(LineWasEdited('', 'x := 1;'));
  Assert.IsFalse(LineWasEdited('', ''));
end;

procedure TTestLineSnapshot.Snapshot_SameText_MeansNotEdited;
var
  Snap : string;
begin
  Snap := EncodeLineSnapshot(SRC_LINE);
  Assert.IsFalse(LineWasEdited(Snap, SRC_LINE));
end;

procedure TTestLineSnapshot.Snapshot_ChangedText_MeansEdited;
var
  Snap : string;
begin
  Snap := EncodeLineSnapshot(SRC_LINE);
  Assert.IsTrue(LineWasEdited(Snap, SRC_LINE + ' // weg'),
    'ein getipptes Zeichen genuegt');
  Assert.IsTrue(LineWasEdited(Snap, ''),
    'Zeile leergeraeumt ist auch bearbeitet');
end;

procedure TTestLineSnapshot.Snapshot_EmptyLine_IsWatchedLikeAnyOther;
// Der Grund fuer die Kodierung. In einem Mehrzeilen-Befund traegt jede
// Zeile eine eigene Marke, Leerzeilen eingeschlossen. Ohne Sentinel waere
// ihr Schnappschuss '' und damit von "nie gesehen" nicht zu trennen - die
// Zeile bliebe fuer immer unbeobachtet.
var
  Snap : string;
begin
  Snap := EncodeLineSnapshot('');
  Assert.IsFalse(LineWasEdited(Snap, ''), 'unveraendert leer');
  Assert.IsTrue(LineWasEdited(Snap, 'a'), 'in die Leerzeile getippt');
end;

procedure TTestLineSnapshot.Snapshot_IndentationChange_CountsAsEdit;
// Entscheidung 2 des Konzepts: ROH vergleichen. Bewusst in Kauf genommen,
// dass ein Formatierer ueber die Datei alle Marken abraeumt; der naechste
// Scan stellt sie wieder her.
var
  Snap : string;
begin
  Snap := EncodeLineSnapshot(SRC_LINE);
  Assert.IsTrue(LineWasEdited(Snap, '  ' + SRC_LINE), 'tiefer eingerueckt');
  Assert.IsTrue(LineWasEdited(Snap, TrimLeft(SRC_LINE)), 'Einrueckung weg');
end;

procedure TTestLineSnapshot.Snapshot_RawTextAsSnapshot_CountsAsEdited;
// Pinnt den VERTRAG, nicht eine Schoenheit: Argument 1 muss kodiert sein.
// Roher Text dort meldet 'bearbeitet', obwohl beide Texte gleich sind -
// das ist gewollt (ein fehlendes Praefix IST ein Unterschied), aber es
// muss festgenagelt sein, damit ein spaeterer Umbau es nicht still dreht.
begin
  Assert.IsTrue(LineWasEdited(SRC_LINE, SRC_LINE),
    'unkodierter Schnappschuss gilt als bearbeitet - Aufrufer muss kodieren');
end;

procedure TTestLineSnapshot.Snapshot_LineStartingWithSentinel_StaysDistinguishable;
// Die tragende Eigenschaft des Sentinels ist Injektivitaet, nicht die
// Annahme '#1 kommt im Quelltext nicht vor'. Eine Zeile, die selbst mit
// dem Sentinel beginnt, muss sauber durchlaufen: unveraendert = nicht
// bearbeitet, veraendert = bearbeitet, und sie darf nicht mit der
// Kodierung ihres eigenen Rumpfes verwechselt werden.
var
  Snap : string;
begin
  Snap := EncodeLineSnapshot(SNAPSHOT_MARK + 'x');
  Assert.IsFalse(LineWasEdited(Snap, SNAPSHOT_MARK + 'x'), 'unveraendert');
  Assert.IsTrue(LineWasEdited(Snap, 'x'), 'anderer Text');
  Assert.AreNotEqual(Snap, EncodeLineSnapshot('x'),
    'Encode muss injektiv bleiben - sonst kollidieren die beiden Zeilen');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestHintTextLayout);
  TDUnitX.RegisterTestFixture(TTestLineSnapshot);

end.

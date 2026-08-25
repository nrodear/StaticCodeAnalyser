unit uTestContrastColor;

// Tests fuer uAnalyserTheme.IsLightColor - die Entscheidung, ob auf einer
// Flaeche schwarze oder weisse Schrift lesbar ist.
//
// ANLASS: Die Funktion lag wortgleich zweimal im IDE-Plugin
// (uIDELineHighlighter und uIDEAnnotationOverlay) und war damit ungetestet
// und driftgefaehrdet. Beim Zusammenlegen faellt sie zum ersten Mal in
// eine Schicht, die ein Testprojekt erreicht.
//
// Warum das hier ueberhaupt geht: uAnalyserTheme liegt in SCA.SharedUI,
// und dessen Quellverzeichnis steht im DCC_UnitSearchPath des
// Testprojekts. Die uIDE*-Units des Plugins liegen in keinem Testprojekt -
// deshalb wandert genau die VCL- und ToolsAPI-freie Rechnung hierher und
// der Rest bleibt ungedeckt.
//
// Die Schwelle ist bewusst eine andere als bei IsActiveThemeDark: dort
// wird das THEME anhand einer Systemfarbe eingeordnet (arithmetisches
// Mittel, Schwelle 128), hier der Schriftkontrast auf einer BELIEBIGEN
// uebergebenen Farbe (BT.601, Schwelle 127). Wer die beiden je
// zusammenlegen will, muss an diesen Tests vorbei.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestContrastColor = class
  public
    // Die Eckfaelle, bei denen die Antwort nicht strittig sein darf.
    [Test] procedure BlackAndWhiteAreUnambiguous;
    // Die Gewichtung ist der Kern: Gruen wiegt schwer, Blau leicht.
    [Test] procedure GreenIsLightBlueIsDark;
    // Genau an der Schwelle - haelt den Vergleichsoperator fest.
    [Test] procedure ThresholdIsExclusiveAt127;
    // Die Akzentfarben, fuer die es die Funktion ueberhaupt gibt.
    [Test] procedure SeverityAccentsGetReadableText;
    // ecsDefault steht seit 2026-08-25 als TOTE Zeile in EDITOR_ACCENT -
    // nur damit die Tabelle das ganze Enum indiziert und ein viertes
    // Schema E2072 ausloest (Fremdbericht, Befund 2). Die Zeile enthaelt
    // clNone. Wer den ecsDefault-Zweig in EditorAccent entfernt oder die
    // Zeile fuer echte Farben haelt, faerbt die Marker unsichtbar - das
    // faellt sonst erst im Editor auf.
    [Test] procedure DefaultSchemeDelegatesAndDoesNotReadTheTable;
    // Fremdbericht 2026-08-23, Befund 3: EditorColorSchemeToStr hatte ein
    // else und persistierte jedes unbekannte Schema als 'default'. Der
    // Anwender waehlt es, die INI behaelt etwas anderes, beim naechsten
    // Laden ist die Wahl weg - ohne Fehler, ohne Hinweis. Der Rundlauf
    // haelt fest, dass jedes Schema seinen eigenen Token hat.
    [Test] procedure EverySchemeSurvivesTheIniRoundTrip;
    // System-Color-Indices muessen aufgeloest werden, nicht durchrutschen.
    [Test] procedure SystemColorIndexIsResolved;
    // EnsureHintContrast (Nur-Text-Hint 2026-08-12): der Akzent haelt
    // einen MINDESTABSTAND zur typischen Hintergrund-Luminanz - Abstand,
    // nicht Seitenvergleich (die dokumentierte ApplyStyleColors-Schwaeche).
    [Test] procedure HintContrast_DarkAccentOnDarkBg_GetsLifted;
    [Test] procedure HintContrast_LightAccentOnLightBg_GetsDarkened;
    [Test] procedure HintContrast_AlreadyContrasty_StaysUntouched;
    [Test] procedure HintContrast_ExtremesAreSafe;
  end;

implementation

uses
  Winapi.Windows,    // GetRValue/GetGValue/GetBValue - stehen NICHT in
                     // Vcl.Graphics, das liefert nur ColorToRGB
  System.SysUtils,   // Format in den Kontrast-Fehlermeldungen
  System.Classes,    // TStringList - Doppelte-Token-Probe
  System.UITypes, Vcl.Graphics, uAnalyserTypes, uAnalyserTheme;

function Lum601(C: TColor): Integer;
// Vergleichsrechnung im Test, damit die Erwartungen nicht geraten sind.
var
  rgb : Cardinal;
begin
  rgb := ColorToRGB(C);
  Result := (GetRValue(rgb) * 299 + GetGValue(rgb) * 587 +
             GetBValue(rgb) * 114) div 1000;
end;

procedure TTestContrastColor.BlackAndWhiteAreUnambiguous;
begin
  Assert.IsTrue(IsLightColor(clWhite), 'Weiss muss hell sein');
  Assert.IsFalse(IsLightColor(clBlack), 'Schwarz muss dunkel sein');
end;

procedure TTestContrastColor.GreenIsLightBlueIsDark;
// Reines Gruen (Luminanz 149) gilt als hell, reines Blau (29) als dunkel.
// Bei einem arithmetischen Mittel waeren beide gleich (85) - dieser Test
// haelt fest, dass BT.601 und nicht der Durchschnitt gerechnet wird.
begin
  Assert.IsTrue(IsLightColor(clLime), 'Gruen muss hell sein (BT.601)');
  Assert.IsFalse(IsLightColor(clBlue), 'Blau muss dunkel sein (BT.601)');
  Assert.AreNotEqual(IsLightColor(clLime), IsLightColor(clBlue),
    'Gruen und Blau duerfen nicht gleich eingestuft werden - genau das ' +
    'waere das Ergebnis eines arithmetischen Mittels');
end;

procedure TTestContrastColor.ThresholdIsExclusiveAt127;
// Ein Grauwert erzeugt Luminanz = Grauwert. 127 ist NICHT hell, 128 schon.
begin
  Assert.AreEqual(127, Lum601(TColor($7F7F7F)), 'Testannahme falsch');
  Assert.AreEqual(128, Lum601(TColor($808080)), 'Testannahme falsch');
  Assert.IsFalse(IsLightColor(TColor($7F7F7F)), 'genau auf der Schwelle');
  Assert.IsTrue(IsLightColor(TColor($808080)),  'einen Schritt darueber');
end;

procedure TTestContrastColor.SeverityAccentsGetReadableText;
// Fuer jede Severity muss die Einstufung zur gerechneten Luminanz passen.
// Der Test prueft die Konsistenz, nicht eine auswendig gelernte Farbe -
// eine geaenderte Palette bleibt damit gruen, eine geaenderte Formel nicht.
var
  Sev : TFindingSeverity;
  C   : TColor;
begin
  for Sev := Low(TFindingSeverity) to High(TFindingSeverity) do
  begin
    C := SeverityAccent(Sev);
    Assert.AreEqual(Lum601(C) > 127, IsLightColor(C),
      'Einstufung weicht von der BT.601-Rechnung ab');
  end;
end;

procedure TTestContrastColor.SystemColorIndexIsResolved;
// clWindowText ist ein System-Color-Index mit gesetztem oberstem Bit.
// Ohne ColorToRGB waere die Rechnung Unsinn. Der Test fordert nur, dass
// beide Wege dasselbe sagen - der konkrete Wert haengt am Theme.
begin
  Assert.AreEqual(Lum601(clWindowText) > 127, IsLightColor(clWindowText));
  Assert.AreEqual(Lum601(clWindow) > 127, IsLightColor(clWindow));
end;

// Erwartungswerte der EnsureHintContrast-Tests: typische Hintergrund-
// Luminanzen und Mindestabstand aus der Implementation (Dark ~30,
// Light ~240, Abstand 90). Die Tests rechnen gegen dieselben Zahlen -
// wer die Konstanten dort aendert, muss hier begruendet nachziehen.
const
  EXPECT_DARK_TARGET  = 30 + 90;   // Mindest-Luminanz auf dunklem Grund
  EXPECT_LIGHT_TARGET = 240 - 90;  // Hoechst-Luminanz auf hellem Grund

procedure TTestContrastColor.HintContrast_DarkAccentOnDarkBg_GetsLifted;
// Dunkles Rot (Luminanz ~45) auf dunklem Editor: ohne Anhebung
// unsichtbar - genau der Fall, der die Bereichs-Abmischung 2026-08
// gekippt hat ("die range wird nicht markiert").
var
  C : TColor;
begin
  C := EnsureHintContrast(TColor($00000099), True);  // dunkles Rot (BGR!)
  Assert.IsTrue(Lum601(C) >= EXPECT_DARK_TARGET,
    Format('Luminanz %d liegt unter dem Mindestabstand %d',
           [Lum601(C), EXPECT_DARK_TARGET]));
end;

procedure TTestContrastColor.HintContrast_LightAccentOnLightBg_GetsDarkened;
// Helles Gelb (Luminanz ~226) auf hellem Editor - muss abdunkeln.
var
  C : TColor;
begin
  C := EnsureHintContrast(TColor($0000FFFF), False); // Gelb (BGR)
  Assert.IsTrue(Lum601(C) <= EXPECT_LIGHT_TARGET,
    Format('Luminanz %d liegt ueber der Hoechstgrenze %d',
           [Lum601(C), EXPECT_LIGHT_TARGET]));
end;

procedure TTestContrastColor.HintContrast_AlreadyContrasty_StaysUntouched;
// Ein bereits kontrastreicher Akzent darf nicht verfaelscht werden -
// die Severity-Farbe ist die Identitaet des Hints.
begin
  Assert.AreEqual(Integer(ColorToRGB(clWhite)),
    Integer(EnsureHintContrast(clWhite, True)),
    'Weiss auf dunklem Grund bleibt Weiss');
  Assert.AreEqual(Integer(ColorToRGB(clBlack)),
    Integer(EnsureHintContrast(clBlack, False)),
    'Schwarz auf hellem Grund bleibt Schwarz');
end;

procedure TTestContrastColor.HintContrast_ExtremesAreSafe;
// Die Grenzlagen duerfen nicht in eine Division rutschen: Schwarz auf
// dunklem Grund (Cur=0, Blend Richtung Weiss) und Weiss auf hellem
// Grund (Cur=255, Blend Richtung Schwarz) muessen beide den Abstand
// erreichen, ohne Ausnahme.
begin
  Assert.IsTrue(Lum601(EnsureHintContrast(clBlack, True)) >= EXPECT_DARK_TARGET);
  Assert.IsTrue(Lum601(EnsureHintContrast(clWhite, False)) <= EXPECT_LIGHT_TARGET);
end;

procedure TTestContrastColor.DefaultSchemeDelegatesAndDoesNotReadTheTable;
var
  Sev : TFindingSeverity;
begin
  for Sev := Low(TFindingSeverity) to High(TFindingSeverity) do
  begin
    // Beide Untergruende: der Default ist theme-unabhaengig, deshalb muss
    // hell und dunkel dieselbe Farbe liefern wie SeverityAccent.
    Assert.AreEqual<TColor>(SeverityAccent(Sev),
      EditorAccent(Sev, ecsDefault, False),
      'ecsDefault (hell) liest die tote Tabellenzeile statt SeverityAccent');
    Assert.AreEqual<TColor>(SeverityAccent(Sev),
      EditorAccent(Sev, ecsDefault, True),
      'ecsDefault (dunkel) liest die tote Tabellenzeile statt SeverityAccent');
  end;

  // Gegenprobe: die echten Schemata liefern etwas ANDERES als der
  // Default - sonst pruefte der Test oben nur, dass alles clNone ist.
  Assert.AreNotEqual<TColor>(EditorAccent(fsError, ecsDefault, False),
    EditorAccent(fsError, ecsGray, False),
    'ecsGray muss sich vom Default unterscheiden');
end;

procedure TTestContrastColor.EverySchemeSurvivesTheIniRoundTrip;
var
  Sch    : TEditorColorScheme;
  Token  : string;
  Gesehen: TStringList;
begin
  Gesehen := TStringList.Create;
  try
    Gesehen.CaseSensitive := False;
    for Sch := Low(TEditorColorScheme) to High(TEditorColorScheme) do
    begin
      Token := EditorColorSchemeToStr(Sch);
      Assert.IsNotEmpty(Token, 'Schema ohne INI-Token');
      Assert.AreEqual<TEditorColorScheme>(Sch, ParseEditorColorScheme(Token),
        'Rundlauf gebrochen fuer Token ' + QuotedStr(Token));
      // Zwei Schemata mit demselben Token waeren dasselbe Leck in gruen:
      // der Rundlauf ginge, aber eines der beiden waere unerreichbar.
      Assert.IsTrue(Gesehen.IndexOf(Token) < 0,
        'Token ' + QuotedStr(Token) + ' ist doppelt vergeben');
      Gesehen.Add(Token);
    end;

    // Und der Eintrag "Text" liegt HINTER den Schemata, nicht auf einem.
    Assert.AreEqual<Integer>(High(EDITOR_COLOR_SCHEME_ORDER) + 1,
      SCHEME_IDX_TEXTONLY,
      'der TextOnly-Eintrag ueberdeckt ein Farbschema im Combo');
  finally
    Gesehen.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestContrastColor);


end.

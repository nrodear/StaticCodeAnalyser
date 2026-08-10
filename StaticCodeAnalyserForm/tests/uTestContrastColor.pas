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
    // System-Color-Indices muessen aufgeloest werden, nicht durchrutschen.
    [Test] procedure SystemColorIndexIsResolved;
  end;

implementation

uses
  Winapi.Windows,    // GetRValue/GetGValue/GetBValue - stehen NICHT in
                     // Vcl.Graphics, das liefert nur ColorToRGB
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

initialization
  TDUnitX.RegisterTestFixture(TTestContrastColor);

end.

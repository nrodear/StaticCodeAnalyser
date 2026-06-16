unit uAnalyserPalette;

// Zentrale Farbpalette des Static Code Analysis Tool for Delphi. Alle hartcodierten RGB-
// Werte aus den Detector-/UI-Units sammeln sich hier.
//
// Konventionen:
//   * SEVBG_*    - Severity-Hintergrundfarben (Pastell, fuer Light-Theme).
//                  Werden im Dark-Theme automatisch gemixt -> siehe
//                  uIDEAnalyserForm.SeverityBg.
//   * ACCENT_*   - Saturierte Akzentfarben fuer 3px-Indikatorleiste UND
//                  als Mix-Quelle in SeverityBg. Saturation und Helligkeit
//                  so gewaehlt, dass sie auf hellem UND dunklem Hintergrund
//                  noch lesbar sind.
//   * ICON_*     - Glyph-Akzente fuer die Stat-Tiles (oben in der Toolbar).
//                  Bewusst saturiert - sie sollen sich von Chrome abheben.
//
// TColor-Werte sind in BGR-Hex notiert (Delphi-Konvention): $00BBGGRR.

interface

uses
  Vcl.Graphics;

const
  // ---------------------------------------------------------------------------
  // Severity-Hintergruende (Light-Theme-Pastelle)
  // ---------------------------------------------------------------------------
  SEVBG_ERROR      = TColor($00E0E0F8); // Pastell-Rosa  - Fehler
  SEVBG_WARNING    = TColor($00E0F4FA); // Pastell-Amber - Warnung
  SEVBG_HINT       = TColor($00ECF4ED); // Pastell-Mint  - Hinweis
  SEVBG_FILEERROR  = TColor($00DCE0FA); // Pastell-Korall - Lesefehler
  SEVBG_UNUSEDUSES = TColor($00F4ECFA); // Pastell-Lavendel - ungenutzte Uses
  SEVBG_NILDEREF   = TColor($00DCE0FA); // wie FileError - NilDeref
  SEVBG_DIVZERO    = TColor($00DCE0FA); // wie FileError - DivByZero
  SEVBG_DEADCODE   = TColor($00EEEEEE); // Hellgrau - toter Code

  // ---------------------------------------------------------------------------
  // Severity-Akzente (3px-Indikatorleiste + Tint-Mix)
  // ---------------------------------------------------------------------------
  ACCENT_ERROR     = TColor($00404DE5); // sattes Rot
  ACCENT_WARNING   = TColor($000098E8); // sattes Amber
  ACCENT_HINT      = TColor($004D9D4D); // sattes Gruen
  ACCENT_FILEERROR = TColor($003040D5); // Korall
  ACCENT_NEUTRAL   = TColor($00B0B0B0); // Mittelgrau

  // ---------------------------------------------------------------------------
  // Editor-Marker-Farbschemata: gelten NUR fuer Stripe + Mini-Infobar +
  // Hover-Overlay-Titlebar im IDE-Editor. Properties-Panel, Hauptfenster-
  // Grid, Stat-Tiles bleiben bei den ACCENT_*-Originalwerten.
  // Jedes Schema hat eine Light- und Dark-Variante; die Auswahl erfolgt
  // ueber StyleServices-Luminanz des Editor-Hintergrunds.
  // ---------------------------------------------------------------------------

  // "Gray" - voellig farblos, neutrale Graustufen. Severity wird nur ueber
  // die Helligkeit unterschieden, nicht ueber den Farbton.
  GRAY_LIGHT_ERROR     = TColor($00606060); // dunkler Grau
  GRAY_LIGHT_WARNING   = TColor($00808080); // mittel
  GRAY_LIGHT_HINT      = TColor($00A0A0A0); // hell
  GRAY_LIGHT_FILEERROR = TColor($00505050); // sehr dunkel

  GRAY_DARK_ERROR      = TColor($00C0C0C0); // sehr hell - kontrastiert auf dunklem Editor
  GRAY_DARK_WARNING    = TColor($00A0A0A0); // hell
  GRAY_DARK_HINT       = TColor($00808080); // mittel
  GRAY_DARK_FILEERROR  = TColor($00D0D0D0); // fast weiss

  // "Subtle" - Farben, aber stark desaturiert / abgedaempft. Erkennbar als
  // Severity-Color, aber nicht visuell aufdringlich.
  SUBTLE_LIGHT_ERROR     = TColor($006070B0); // gedaempftes Rot
  SUBTLE_LIGHT_WARNING   = TColor($0050A0C0); // gedaempftes Amber
  SUBTLE_LIGHT_HINT      = TColor($0080A080); // gedaempftes Gruen
  SUBTLE_LIGHT_FILEERROR = TColor($005070A0); // gedaempftes Korall

  SUBTLE_DARK_ERROR      = TColor($008090D0); // helleres gedaempftes Rot
  SUBTLE_DARK_WARNING    = TColor($0070B0D0); // helleres Amber
  SUBTLE_DARK_HINT       = TColor($0090B090); // helleres Gruen
  SUBTLE_DARK_FILEERROR  = TColor($007090C0); // helleres Korall

  // ---------------------------------------------------------------------------
  // Stat-Tile-Glyph-Akzente (BGR)
  // ---------------------------------------------------------------------------
  ICON_ERROR       = TColor($002030E0); // Rot-Orange
  ICON_WARN        = TColor($002090F0); // Orange
  ICON_INFO        = TColor($00F09020); // Hellblau
  ICON_FILEERR     = TColor($00A0A0A0); // Hellgrau
  ICON_SMELL       = TColor($00B040A0); // Magenta (Komplexitaet)
  ICON_BUG         = TColor($002030E0); // Rot
  ICON_VULN        = TColor($0080C040); // Gruen (Sicherheit)
  ICON_HOT         = TColor($0040D0E0); // Gelb (Performance)
  ICON_DUP         = TColor($00F0A040); // Cyan-Blau
  ICON_SCORE       = TColor($002080F0); // Orange (Codequalitaet/Flamme)

  // ---------------------------------------------------------------------------
  // Grid-Hilfsfarben
  // ---------------------------------------------------------------------------
  ZEBRA            = TColor($00F7F7F7); // Zeilenwechsel im Light-Theme

implementation

end.

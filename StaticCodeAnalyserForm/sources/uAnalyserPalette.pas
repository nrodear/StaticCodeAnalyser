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

unit uIDEColors;

// Semantische IDE-Theme-Palette fuer den Plugin-Frame, die Hilfe-Spalte,
// die Sonar-Tiles, die Options-Pages.
//
// ZWECK
//   Bisher tauchten clBtnFace / clWindow / cl3DDkShadow / clBtnText /
//   clWindowText / clGrayText verstreut in mehreren Units auf. Jede
//   Stelle setzte "die richtige System-Farbe", aber die Bedeutung
//   ("Chrome", "Content", "Separator") war nur per Daumenkommentar
//   erkennbar. Diese Konstanten machen die Intention im Identifier-
//   Namen explizit und liefern einen einzigen Touchpoint, falls das
//   Plugin spaeter eine angepasste Palette bekommt.
//
// RUNTIME-VERHALTEN
//   Alle Konstanten zeigen auf System-Color-Indices (clBtnFace u.a.).
//   Der aktive VCL-Style remapped sie zur Paint-Zeit auf das aktuelle
//   IDE-Theme — hell im Light-Theme, dunkel im Dark-Theme, korrekt
//   in Mountain Mist / Carbon / Custom-Styles. Es gibt also keinen
//   Verhaltensunterschied gegenueber den frueher direkt geschriebenen
//   System-Colors — nur eine Konsistenz- und Lesbarkeits-Verbesserung.

interface

uses
  Vcl.Controls,    // TLabel fuer StyleAsHintLabel
  Vcl.StdCtrls,
  Vcl.Graphics;

const
  // Chrome / Toolbar / Frame-Hintergrund (Plugin-Rahmen, Tile-Aussenflaeche).
  IDE_BG_CHROME    : TColor = clBtnFace;

  // Content-Bereich (Memo, Edit, Grid, Tiles-Innenflaeche bei Severity-
  // Akzent-Layern).
  IDE_BG_CONTENT   : TColor = clWindow;

  // Bold-Text auf Chrome (Headings, Count-Zahlen in Tiles).
  IDE_FG_CHROME    : TColor = clBtnText;

  // Standard-Text auf Content (Memo-Inhalt, Edit-Text, Grid-Zellen).
  IDE_FG_CONTENT   : TColor = clWindowText;

  // Gedaempfter Caption-Text (Tile-Caption unter der Count-Zahl,
  // Hint-Texte unter Edit-Feldern).
  IDE_FG_DIM       : TColor = clGrayText;

  // Separator-Linien (1 px Trennlinien zwischen Panels, Splittern, Tile-
  // Rahmen). clBtnShadow statt cl3DDkShadow: bleibt im Dark-Theme deutlich
  // gegen den Tile/Panel-Hintergrund sichtbar; cl3DDkShadow kollabiert dort
  // teilweise auf den gleichen RGB-Wert wie clBtnFace und verschwindet.
  IDE_SEPARATOR    : TColor = clBtnShadow;

  // Tools>Options-Page Frame-Hintergrund - NUR der DARK-Theme-Ton. Kuratierter
  // dunkler Ton mit leichtem Blau-Hauch (2026-06-19 User-Wahl); explizit NICHT
  // system-color, weil clWindow im Dark-Theme nicht zum gewuenschten Look remapped.
  // TColor-Konvention BGR: #2A2D32 (R=2A G=2D B=32) -> $00322D2A.
  // Konsument: TIDETheme.OptionsFrameBg - waehlt im DARK-Theme diese Konstante,
  // im LIGHT-Theme dagegen TIDETheme.FrameBg (Bugfix 2026-07-15: bedingungsloses
  // Setzen dieser Dunkelfarbe machte die Options-Page im hellen Theme falsch dunkel).
  IDE_BG_OPTIONS_FRAME : TColor = TColor($00322D2A);

// Wendet den "Hint-Label-Style" (IDE_FG_DIM, 8pt, ParentFont aus) auf das
// uebergebene Label an. Dient als Single-Point-of-Truth fuer Help-/Hint-
// Beschriftungen unter Edit-Feldern und Checkboxes in den Options-Pages.
// Idempotent; tolerant gegen nil.
procedure StyleAsHintLabel(L: TLabel);

implementation

procedure StyleAsHintLabel(L: TLabel);
begin
  if L = nil then Exit;
  L.ParentFont := False;
  L.Font.Size  := 8;
  L.Font.Color := IDE_FG_DIM;
end;

end.

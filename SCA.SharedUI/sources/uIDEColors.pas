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

implementation

end.

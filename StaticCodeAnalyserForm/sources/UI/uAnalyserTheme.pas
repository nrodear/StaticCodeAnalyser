unit uAnalyserTheme;

// Theme-Helper fuer das Static Code Analysis Tool for Delphi.
// Aufgabe: Severity-bezogene Farben aus dem aktiven IDE-/VCL-Theme ableiten.
//
// Das Modul kennt KEINE Strings - es operiert ausschliesslich auf dem
// TFindingSeverity-Enum aus uAnalyserTypes. Konvertierung von/zum String
// findet nur an der UI-Grenze statt.
//
// Ergebnis-Farben werden ueber StyleServices.GetSystemColor zur Aufruf-
// Zeit bestimmt - der aktive VCL-Style/IDE-Theme bestimmt die Basis,
// auf die der Severity-Akzent gemischt wird. Damit gleicher Code in
// Light-, Dark- und Custom-Themes konsistent aussieht.

interface

uses
  System.SysUtils,
  Vcl.Graphics, Vcl.Themes,
  uAnalyserTypes;

type
  TStyleServicesProvider = reference to function: TCustomStyleServices;

var
  // Global Hook fuer Color-Auflösung. IDE-Plugin setzt das auf eine
  // Funktion die IOTAIDEThemingServices.StyleServices liefert.
  // Standalone laesst's nil — ActiveStyleServices faellt dann auf die
  // VCL-globale Vcl.Themes.StyleServices zurueck.
  StyleServicesProvider: TStyleServicesProvider = nil;

// Liefert die aktive TCustomStyleServices. Im IDE-Plugin-Kontext via
// StyleServicesProvider die IDE-spezifische (folgt IDE-Theme).
// Sonst die VCL-globale (folgt TStyleManager.ActiveStyle).
function ActiveStyleServices: TCustomStyleServices;

// Saturierte Akzentfarbe fuer eine Severity. Wird verwendet:
//   * 3px-Indikatorleiste am linken Zellenrand
//   * Akzent-Schriftfarben fuer "Vorher"/"Nachher"-Labels
//   * Mix-Quelle in SeverityBg
function SeverityAccent(Severity: TFindingSeverity): TColor;

// Themed Severity-Hintergrundfarbe. Mischt einen kleinen Anteil
// (TINT_RATIO) der Akzentfarbe in die theme-aufgeloeste Basisfarbe.
//   ABase = clWindow  -> Default fuer Datentabellen
//   ABase = clBtnFace -> fuer Chrome-Elemente (z. B. Help-Desc-Label)
function SeverityBg(Severity: TFindingSeverity;
  ABase: TColor = clWindow): TColor; overload;

// Wie oben, aber mit explizitem StyleServices fuer die Color-Aufloesung.
// Wird vom IDE-Plugin-Renderer aufgerufen — dort muss die IDE-spezifische
// Theming.StyleServices verwendet werden (sonst gewinnt die VCL-globale
// und Severity-Hintergruende rendern im VCL-Style statt im IDE-Theme).
function SeverityBg(Severity: TFindingSeverity;
  ABase: TColor; AStyleServices: TCustomStyleServices): TColor; overload;

// Lineare Farbmischung. Ratio=0 -> Base, Ratio=1 -> Accent.
// Loest System-Color-Indices vorher per ColorToRGB auf.
function BlendColor(Base, Accent: TColor; Ratio: Single): TColor;

implementation

uses
  Winapi.Windows,
  uAnalyserPalette;

function ActiveStyleServices: TCustomStyleServices;
begin
  Result := nil;
  if Assigned(StyleServicesProvider) then
    Result := StyleServicesProvider();
  if not Assigned(Result) then
    Result := Vcl.Themes.StyleServices;
end;

function SeverityAccent(Severity: TFindingSeverity): TColor;
begin
  case Severity of
    fsError:     Result := ACCENT_ERROR;
    fsWarning:   Result := ACCENT_WARNING;
    fsHint:      Result := ACCENT_HINT;
    fsFileError: Result := ACCENT_FILEERROR;
  else
    Result := clNone;
  end;
end;

function BlendColor(Base, Accent: TColor; Ratio: Single): TColor;
var
  rgbB, rgbA : Cardinal;
  rB, gB, bB : Integer;
  rA, gA, bA : Integer;
  Inv        : Single;
begin
  rgbB := ColorToRGB(Base);
  rgbA := ColorToRGB(Accent);
  rB := GetRValue(rgbB); gB := GetGValue(rgbB); bB := GetBValue(rgbB);
  rA := GetRValue(rgbA); gA := GetGValue(rgbA); bA := GetBValue(rgbA);
  Inv := 1 - Ratio;
  Result := Winapi.Windows.RGB(
    Round(rB * Inv + rA * Ratio),
    Round(gB * Inv + gA * Ratio),
    Round(bB * Inv + bA * Ratio));
end;

function SeverityBg(Severity: TFindingSeverity;
  ABase: TColor): TColor;
begin
  // Default-Pfad: via Vcl.Themes.StyleServices (global). Im Docked-Mode
  // wird die globale durch Theming.ApplyTheme(Form) korrekt mitgezogen;
  // Theming.StyleServices/ActiveStyleServices liefert dort nach Theme-
  // Switch nicht zuverlaessig frische Farben fuer Custom-Paint. Wer
  // explizit die IDE-Variante braucht (Grid-Renderer) kann das ueber
  // die 3-Parameter-Overload tun.
  Result := SeverityBg(Severity, ABase, StyleServices);
end;

function SeverityBg(Severity: TFindingSeverity;
  ABase: TColor; AStyleServices: TCustomStyleServices): TColor;
const
  TINT_RATIO = 0.22; // 22% Akzent eingemischt - sichtbar, nicht aggressiv
var
  Base, Accent: TColor;
  ResolvedBase: TColor;
begin
  Accent := SeverityAccent(Severity);
  if Accent = clNone then Exit(clNone);
  if Assigned(AStyleServices) then
    ResolvedBase := AStyleServices.GetSystemColor(ABase)
  else
    ResolvedBase := StyleServices.GetSystemColor(ABase);
  Base := ResolvedBase;
  Result := BlendColor(Base, Accent, TINT_RATIO);
end;

end.

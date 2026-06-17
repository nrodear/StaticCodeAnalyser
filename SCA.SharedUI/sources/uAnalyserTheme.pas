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

type
  // Farbschema NUR fuer Editor-Marker (Stripe + Mini-Infobar + Overlay-
  // Titlebar). Properties-Panel + Hauptfenster-Grid + Stat-Tiles ignorieren
  // den Schema-Schalter und behalten ihre eigenen Severity-Farben aus
  // SeverityAccent.
  TEditorColorScheme = (
    ecsDefault,   // Original-ACCENT_* (kraftvoll, hohe Saturation)
    ecsGray,      // Reine Graustufen, kein Farbton
    ecsSubtle     // Gedaempfte Farben, niedrige Saturation
  );

// Editor-spezifische Akzentfarbe. Nutzt das gewuenschte Schema und passt
// die Helligkeit automatisch an Light/Dark-Theme an (BgIsDark = True ->
// dunkler Theme-Hintergrund -> hellere Marker, sonst umgekehrt).
function EditorAccent(Severity: TFindingSeverity;
  Scheme: TEditorColorScheme; BgIsDark: Boolean): TColor;

// Heuristisch: True wenn der aktive Theme einen dunklen Hintergrund hat.
// Schwellwert: Luminanz von StyleServices.GetSystemColor(clWindow) < 128.
function IsActiveThemeDark: Boolean;

// String <-> Enum Konvertierung fuer INI-Persistierung. Akzeptiert
// 'default', 'gray', 'subtle' case-insensitiv. Unbekannt -> ecsDefault.
function ParseEditorColorScheme(const S: string): TEditorColorScheme;
function EditorColorSchemeToStr(Scheme: TEditorColorScheme): string;

// Aktualisiert die globalen GCachedEditorScheme + GCachedEditorBgDark.
// Caller liefert den String aus seiner Settings-Quelle - so kommt der
// uAnalyserTheme-Layer ohne TRepoSettings-Abhaengigkeit aus (Layering:
// SCA.SharedUI darf SCA.Engine.uRepoSettings nicht direkt importieren).
// Komplett defensiv - Exceptions werden geschluckt, die Defaults bleiben
// erhalten.
procedure RefreshEditorColorSchemeCache(const ASchemeStr: string);

const
  // Display-Reihenfolge fuer ComboBoxen. Index hier == ComboBox.ItemIndex.
  // Loest die ehemalige Dreifach-case-Statement (Items.Add + Load-Map +
  // Save-Map) auf. Neues Schema dazu = ein Eintrag, zwei case-Branches
  // verschwinden.
  EDITOR_COLOR_SCHEME_ORDER: array[0..2] of TEditorColorScheme =
    (ecsDefault, ecsGray, ecsSubtle);

// Konvertierung ComboBox.ItemIndex <-> TEditorColorScheme. Fuer Caller
// die das Combo-Mapping nicht jedes Mal selbst hinschreiben wollen.
function SchemeFromComboIndex(AIndex: Integer): TEditorColorScheme;
function ComboIndexFromScheme(Scheme: TEditorColorScheme): Integer;

var
  // Globaler Cache fuer das Editor-Farbschema. Wird vom IDE-Plugin-Init
  // gesetzt und nach jedem Settings-Save / Theme-Change refresht.
  // BuildMarkEntries / HighlightAllFindingsInFile lesen nur diese Var -
  // kein TRepoSettings.Create + StyleServices-Lookup pro Scan-Lauf.
  // Defaults sind sicher (ecsDefault, False) bis das Plugin sie aktiv setzt.
  GCachedEditorScheme : TEditorColorScheme = ecsDefault;
  GCachedEditorBgDark : Boolean            = False;

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

// noinspection-file EmptyArgumentList, GroupedDeclaration, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

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

function EditorAccent(Severity: TFindingSeverity;
  Scheme: TEditorColorScheme; BgIsDark: Boolean): TColor;
begin
  case Scheme of
    ecsGray:
      if BgIsDark then
        case Severity of
          fsError:     Result := GRAY_DARK_ERROR;
          fsWarning:   Result := GRAY_DARK_WARNING;
          fsHint:      Result := GRAY_DARK_HINT;
          fsFileError: Result := GRAY_DARK_FILEERROR;
        else
          Result := clNone;
        end
      else
        case Severity of
          fsError:     Result := GRAY_LIGHT_ERROR;
          fsWarning:   Result := GRAY_LIGHT_WARNING;
          fsHint:      Result := GRAY_LIGHT_HINT;
          fsFileError: Result := GRAY_LIGHT_FILEERROR;
        else
          Result := clNone;
        end;
    ecsSubtle:
      if BgIsDark then
        case Severity of
          fsError:     Result := SUBTLE_DARK_ERROR;
          fsWarning:   Result := SUBTLE_DARK_WARNING;
          fsHint:      Result := SUBTLE_DARK_HINT;
          fsFileError: Result := SUBTLE_DARK_FILEERROR;
        else
          Result := clNone;
        end
      else
        case Severity of
          fsError:     Result := SUBTLE_LIGHT_ERROR;
          fsWarning:   Result := SUBTLE_LIGHT_WARNING;
          fsHint:      Result := SUBTLE_LIGHT_HINT;
          fsFileError: Result := SUBTLE_LIGHT_FILEERROR;
        else
          Result := clNone;
        end;
  else
    // ecsDefault - Originalverhalten, theme-unabhaengig.
    Result := SeverityAccent(Severity);
  end;
end;

const
  // Mid-Point der 0..255-Luminanz-Skala. Dark-Themes haben typisch
  // ~30 (#1E1E1E), Light-Themes ~240 (#F0F0F0) - 128 trennt sicher.
  THEME_DARK_AVG_THRESHOLD = 128;

function IsActiveThemeDark: Boolean;
// Einfache RGB-Durchschnitts-Heuristik (statt gewichtetem Luminanz-
// Mittel Y = 0.299R + 0.587G + 0.114B) weil clWindow meist neutral-grau
// ist und der Unterschied zwischen Light/Dark eindeutig liegt.
var
  Svc : TCustomStyleServices;
  C   : TColor;
  rgb : Cardinal;
  Avg : Integer;
begin
  Result := False;
  Svc := ActiveStyleServices;
  if not Assigned(Svc) then Exit;
  try
    C := Svc.GetSystemColor(clWindow);
  except
    Exit;
  end;
  rgb := ColorToRGB(C);
  Avg := (GetRValue(rgb) + GetGValue(rgb) + GetBValue(rgb)) div 3;
  Result := Avg < THEME_DARK_AVG_THRESHOLD;
end;

function ParseEditorColorScheme(const S: string): TEditorColorScheme;
var Lower : string;
begin
  Lower := LowerCase(Trim(S));
  if Lower = 'gray' then Exit(ecsGray);
  if Lower = 'subtle' then Exit(ecsSubtle);
  if Lower = 'default' then Exit(ecsDefault);
  // Unbekannter Wert: still auf Default zurueck, aber Debug-Log fuer
  // den Fall dass der User einen Tippfehler in der INI hat (z.B. 'grey'
  // statt 'gray'). Leere String + Erst-Init liefern auch Default, das
  // ist OK - nur 'echte' Tippfehler werden geloggt.
  if Lower <> '' then
    Winapi.Windows.OutputDebugString(PChar(
      'SCA: unknown EditorColorScheme value ' + QuotedStr(S) +
      ' - falling back to default'));
  Result := ecsDefault;
end;

function EditorColorSchemeToStr(Scheme: TEditorColorScheme): string;
begin
  case Scheme of
    ecsGray:   Result := 'gray';
    ecsSubtle: Result := 'subtle';
  else
    Result := 'default';
  end;
end;

procedure RefreshEditorColorSchemeCache(const ASchemeStr: string);
begin
  try
    GCachedEditorScheme := ParseEditorColorScheme(ASchemeStr);
  except
    GCachedEditorScheme := ecsDefault;
  end;
  try
    GCachedEditorBgDark := IsActiveThemeDark;
  except
    GCachedEditorBgDark := False;
  end;
end;

function SchemeFromComboIndex(AIndex: Integer): TEditorColorScheme;
begin
  if (AIndex >= Low(EDITOR_COLOR_SCHEME_ORDER)) and
     (AIndex <= High(EDITOR_COLOR_SCHEME_ORDER)) then
    Result := EDITOR_COLOR_SCHEME_ORDER[AIndex]
  else
    Result := ecsDefault;
end;

function ComboIndexFromScheme(Scheme: TEditorColorScheme): Integer;
var
  i : Integer;
begin
  for i := Low(EDITOR_COLOR_SCHEME_ORDER) to High(EDITOR_COLOR_SCHEME_ORDER) do
    if EDITOR_COLOR_SCHEME_ORDER[i] = Scheme then Exit(i);
  Result := 0;   // Fallback: erster Eintrag (Default)
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

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
  // Liefert eine Farbe aus einer Quelle, die diese Unit nicht kennen darf.
  TStyleColorProvider = reference to function: TColor;

var
  // Global Hook fuer Color-Auflösung. IDE-Plugin setzt das auf eine
  // Funktion die IOTAIDEThemingServices.StyleServices liefert.
  // Standalone laesst's nil — ActiveStyleServices faellt dann auf die
  // VCL-globale Vcl.Themes.StyleServices zurueck.
  StyleServicesProvider: TStyleServicesProvider = nil;

  // Global Hook fuer die ECHTE Hintergrundfarbe des Code-Editors. Das
  // IDE-Plugin setzt das auf eine Funktion, die
  // INTACodeEditorServices.Options.BackgroundColor[atWhiteSpace] liefert
  // (TIDETheme.EditorBg); ausserhalb der IDE bleibt es nil.
  //
  // WOFUER: GCachedEditorBgDark steuert, ob EditorAccent die Hell- oder die
  // Dunkel-Variante der Gray/Subtle-Paletten waehlt - also die Farbe der
  // Markierungen IM EDITOR. Bis 2026-08-10 kam die Antwort aus
  // IsActiveThemeDark, das GetSystemColor(clWindow) misst: die Farbe des
  // IDE-RAHMENS. Bei hellem Editor in dunkler IDE (und umgekehrt) wurde
  // damit die falsche Variante gewaehlt - und zwar genau in dem Fall, fuer
  // den TIDETheme.EditorBg ueberhaupt existiert. Der Kommentar in
  // uAnalyserPalette hatte die richtige Regel schon beschrieben, der Code
  // folgte ihr nur nicht.
  //
  // Als Hook und nicht als direkter Aufruf, weil diese Unit in
  // SCA.SharedUI liegt und ToolsAPI nicht kennen darf - dieselbe
  // Schichtgrenze und dasselbe Muster wie bei StyleServicesProvider
  // daneben. Der Setzer muss ihn beim Entladen wieder auf nil setzen,
  // sonst zeigt die Closure in entladenen Plugin-Code.
  EditorBgProvider: TStyleColorProvider = nil;

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
// ACHTUNG: das ist der IDE-RAHMEN. Fuer alles, was IM EDITOR gezeichnet
// wird, ist IsEditorBgDark die richtige Frage.
function IsActiveThemeDark: Boolean;

/// <summary>
///   True, wenn der Hintergrund des CODE-EDITORS dunkel ist. Fuer die
///   Farbwahl der Editor-Markierungen die richtige Frage; ohne gesetzten
///   EditorBgProvider identisch zu IsActiveThemeDark.
/// </summary>
function IsEditorBgDark: Boolean;

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

/// <summary>
///   True, wenn AColor als "hell" wirkt und schwarze Schrift darauf besser
///   kontrastiert als weisse. Luminanz nach ITU-R BT.601, Schwelle 127.
/// </summary>
/// <remarks>
///   Hier und nicht je Aufrufer: die Funktion lag wortgleich zweimal im
///   Plugin (uIDELineHighlighter und uIDEAnnotationOverlay). Zwei Kopien
///   einer Kontrastregel koennen auseinanderlaufen, ohne dass es auffaellt -
///   das Ergebnis waere Schrift, die an einer Stelle lesbar ist und an der
///   anderen nicht.
///
///   Bewusst NICHT mit IsActiveThemeDark zusammengelegt: das misst das
///   THEME (eine Systemfarbe, arithmetisches Mittel), diese Funktion eine
///   BELIEBIGE uebergebene Farbe. Gleiche Frage, andere Quelle und andere
///   Formel - siehe Konzept_UiArchitektur_IdePlugin_2026-08-10.md.
///
///   System-Color-Indices werden per ColorToRGB aufgeloest, clNone liefert
///   damit den Wert der aktuellen Systemfarbe und nicht $1FFFFFFF.
/// </remarks>
function IsLightColor(AColor: TColor): Boolean;

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
  // Mitte derselben Skala fuer die gewichtete BT.601-Luminanz. Getrennte
  // Konstante, weil die Frage eine andere ist: hier geht es um den
  // Schriftkontrast auf einer beliebigen Flaeche, oben um die Einordnung
  // des Themes anhand einer Systemfarbe.
  CONTRAST_LUM_THRESHOLD = 127;

function IsLightColor(AColor: TColor): Boolean;
// Vertrag und Begruendung stehen an der Deklaration.
var
  rgb     : Cardinal;
  R, G, B : Integer;
  Lum     : Integer;
begin
  rgb := ColorToRGB(AColor);
  R := GetRValue(rgb);
  G := GetGValue(rgb);
  B := GetBValue(rgb);
  // ITU-R BT.601: Gruen wiegt am schwersten, Blau am leichtesten - das
  // entspricht der Helligkeitswahrnehmung des Auges besser als ein
  // arithmetisches Mittel.
  Lum := (R * 299 + G * 587 + B * 114) div 1000;
  Result := Lum > CONTRAST_LUM_THRESHOLD;
end;

function IsEditorBgDark: Boolean;
// Ist der Hintergrund des CODE-EDITORS dunkel? Das ist die Frage, die fuer
// die Farbe der Editor-Markierungen zaehlt - nicht, ob das IDE-Theme
// dunkel ist. Beides faellt oft zusammen, aber eben nicht immer.
//
// Ohne gesetzten EditorBgProvider (Standalone-EXE, Tests) faellt die
// Funktion auf IsActiveThemeDark zurueck - dasselbe Verhalten wie vor dem
// 2026-08-10, nur als bewusster Rueckfall statt als einziger Weg.
//
// Gerechnet wird mit IsLightColor, also BT.601 wie ueberall sonst beim
// Kontrast; der Rueckfall behaelt seine eigene Formel, weil er eine
// Systemfarbe misst (Begruendung an IsActiveThemeDark).
var
  Bg : TColor;
begin
  if not Assigned(EditorBgProvider) then
    Exit(IsActiveThemeDark);
  Bg := clNone;
  try
    Bg := EditorBgProvider();
  // Provider zeigt ins Leere (Plugin halb entladen) oder die ToolsAPI
  // liefert nicht - Bg bleibt clNone und die Zeile darunter faellt auf
  // IsActiveThemeDark zurueck. Eine Farbfrage darf nichts abbrechen.
  // noinspection EmptyExcept
  except
  end;
  if Bg = clNone then
    Exit(IsActiveThemeDark);
  Result := not IsLightColor(Bg);
end;

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
    // IsEditorBgDark statt IsActiveThemeDark (2026-08-10): der Cache
    // steuert die Farbe der Marker IM EDITOR, also muss er den
    // Editor-Hintergrund messen und nicht den IDE-Rahmen. Ohne gesetzten
    // EditorBgProvider ist das Verhalten unveraendert.
    GCachedEditorBgDark := IsEditorBgDark;
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

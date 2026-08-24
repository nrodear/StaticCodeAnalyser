unit uIDETheme;

// Zentraler IDE-Theme-Manager fuer das Analyser-Plugin.
//
// PUBLIC FACADE (TIDETheme)
//   * Apply(AControl)                — wendet das aktuelle IDE-Theme auf
//                                      AControl + alle Descendants an.
//   * Subscribe(Callback): IInterface — Theme-Wechsel-Event abonnieren;
//                                      RAII via Refcount.
//   * FrameBg / FrameFg / EditorBg   — gecachte Theme-Standardfarben.
//   * IsDark                         — Heuristik fuer Dark-Mode-Akzente.
//
// APPLY-PIPELINE pro Descendant (siehe ApplyRecursive):
//   1. ATheming.ApplyTheme(C)               — IDE-Style-Hook initialisieren
//   2. StyleElements - [seClient] erhalten  — Snapshot+Restore
//   3. Color/Font.Color resolven            — ORIGINAL-Identifier
//                                             (clBtnFace, clWindow, ...) ->
//                                             konkretes RGB aus IDE-Style
//   4. StyleName := IdeStyle.Name           — per-Control-Style (10.4+),
//                                             routet StyleHooks zur IDE-
//                                             Style-Quelle statt zur VCL-
//                                             globalen (Docked-Mode-Fix)
//   5. Invalidate / TCustomGrid: Repaint    — repaint mit neuen Farben
//
// WARUM SO AUFWAENDIG
//   IOTAIDEThemingServices.ApplyTheme propagiert in Delphi 12 nicht
//   zuverlaessig transitiv von einem TFrame auf seine Kinder. Im Docked-
//   Modus aktualisiert es ausserdem die VCL-globale Vcl.Themes.StyleServices
//   NICHT - StyleHooks lesen dann stale Farben. Die per-Descendant-
//   Pipeline oben kompensiert beide Probleme ohne den 2-Sek-Hang von
//   TStyleManager.SetStyle (Application.Broadcast(CM_STYLECHANGED) ueber
//   alle IDE-Forms).
//
// THREAD-MODELL
//   IOTAIDEThemingServices feuert ChangedTheme im Main-Thread; alle
//   Subscriber-Aufrufe laufen im VCL-Thread.
//
// LIFECYCLE
//   * Singleton G wird lazy beim ersten Apply/Subscribe gebaut.
//   * Unit-Finalization gibt G frei -> Notifier abgemeldet.
//   * TSubscription ist refcount-owned; Aufrufer haelt ein IInterface,
//     bei dessen Free wird automatisch unsubscribed (kein Detach noetig).
//   * Origin-Color-Cache (FOrigColors) wird mit dem Singleton freigegeben.

interface

uses
  System.Classes,
  Vcl.Controls, Vcl.Graphics;

type
  // Method-Pointer fuer Theme-Changed-Callbacks. Subscriber bekommen kein
  // Argument - alle benoetigten Farben holen sie sich via TIDETheme.XxxBg/
  // EditorBg/IsDark direkt nach dem Callback.
  TThemeChangedProc = procedure of object;

  // Statisches Service-Facade. Konstruiert nichts - der echte Implementation-
  // Singleton lebt unit-intern in G und wird lazy initialisiert.
  TIDETheme = class
  public
    // Wendet das aktuelle IDE-Theme auf AControl + alle Descendants an.
    // Schritte (Details siehe Unit-Header und ApplyRecursive):
    //   1. RegisterFormClass + ApplyTheme auf dem Top-Level-Form.
    //   2. Per-Descendant Pipeline: ApplyTheme + Color-Resolve +
    //      StyleName-Binding + Invalidate (Repaint bei Grids).
    //
    // Idempotent. AControl=nil ist ein no-op.
    class procedure Apply(AControl: TWinControl); static;

    // Registriert ACallback fuer Theme-Wechsel-Events. Liefert ein
    // IInterface - solange der Aufrufer es haelt, wird der Callback bei
    // jedem ChangedTheme gerufen. Wenn der Aufrufer das Interface auf nil
    // setzt (oder es out-of-scope geht), wird der Callback automatisch
    // wieder ausgehaengt (Refcount-RAII).
    //
    // Typischer Aufruf im Frame-Constructor:
    //   FThemeSub := TIDETheme.Subscribe(ThemeChanged);
    // Im Destructor reicht FThemeSub := nil; (oder FThemeSub geht eh out
    // of scope wenn das Frame zerlegt wird).
    class function Subscribe(ACallback: TThemeChangedProc): IInterface; static;

    // Cached IDE-Frame-Hintergrund (StyleServices.GetSystemColor(clWindow)).
    // Cache wird beim Theme-Wechsel automatisch invalidiert.
    class function FrameBg: TColor; static;

    // Hintergrund fuer die Tools>Options-Pages (SCA/Sonar): im DARK-Theme der
    // kuratierte Ton IDE_BG_OPTIONS_FRAME (User-Wahl 2026-06-19), im LIGHT-Theme
    // die theme-korrekte System-Window-Farbe (FrameBg). Bugfix 2026-07-15:
    // vorher wurde die Dunkelfarbe bedingungslos gesetzt -> die Options-Page war
    // im hellen IDE-Theme faelschlich immer dunkel.
    class function OptionsFrameBg: TColor; static;

    // Cached IDE-Frame-Textfarbe.
    class function FrameFg: TColor; static;

    // Cached Source-Editor-Hintergrund via INTACodeEditorServices.Options.
    // Wichtig: Editor-Theme kann vom Frame-Theme abweichen (dunkler IDE-
    // Rahmen mit hellem Editor und umgekehrt). Liefert clNone wenn der
    // Service nicht verfuegbar ist (z.B. Plugin-Init vor ToolsAPI-Ready).
    class function EditorBg: TColor; static;

    // True wenn FrameBg perzeptuell "dunkel" wirkt (Luminanz <= 50%).
    // Heuristik via ITU-R BT.601. Subscriber koennen damit Dark-Mode-
    // spezifische Akzente einschalten ohne den genauen Style-Namen abzu-
    // fragen.
    class function IsDark: Boolean; static;

    /// <summary>
    ///   Baut den Theme-Singleton und meldet seine beiden Notifier an,
    ///   ohne dass vorher jemand eine Farbe gelesen haben muss.
    /// </summary>
    /// <remarks>
    ///   Ohne diesen Aufruf laeuft die Anmeldung LAZY - gemessen am
    ///   2026-08-10 geschah sie 43 Sekunden nach dem Paketladen, naemlich
    ///   beim ersten Theme-Zugriff. Jede Farbumstellung davor ginge
    ///   verloren, und genau die frueheste Phase ist die, in der ein
    ///   Anwender seine IDE einrichtet.
    ///
    ///   Aufzurufen beim Plugin-Start, direkt nachdem die Provider-Hooks
    ///   nach SCA.SharedUI gesetzt sind - vorher wuesste der Cache den
    ///   Editor-Hintergrund noch nicht. Idempotent.
    /// </remarks>
    class procedure Prime; static;
  end;

implementation

// noinspection-file BeginEndRequired, CanBeClassMethod, CanBeStrictPrivate, CanBeUnitPrivate, ClassPerFile, EmptyArgumentList, EmptyExcept, EmptyMethod, GroupedDeclaration, LargeClass, NestedRoutine, NilComparison, TooLongLine, UnsortedUses, UnusedPublicMember
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.SysUtils,
  System.Generics.Collections,
  Winapi.Windows,
  Vcl.Forms, Vcl.Themes, Vcl.Grids,
  ToolsAPI, ToolsAPI.Editor,
  uAnalyserTheme,  // RefreshEditorBgDarkCache - geteilter Cache in SCA.SharedUI
  uAppTheme,       // ApplyTitleBarTheme - die Titelzeile folgt nur DWM
  uIDEColors;   // IDE_BG_OPTIONS_FRAME (kuratierter Dark-Ton) fuer OptionsFrameBg

type
  TIDEThemeImpl = class;

  // Refcount-Hilfsobjekt: wird vom Subscribe-Aufrufer gehalten. Beim
  // letzten _Release aus der Refcount-Hierarchie wird Destroy gerufen,
  // das die Subscription beim Singleton abmeldet.
  TSubscription = class(TInterfacedObject)
  private
    FCallback : TThemeChangedProc;
  public
    constructor Create(ACallback: TThemeChangedProc);
    destructor Destroy; override;
  end;

  // Interner ToolsAPI-Notifier. Lebt genau einmal, wird im
  // TIDEThemeImpl.EnsureNotifier registriert. Detach setzt FOwner=nil
  // damit ein spaet feuerndes ChangedTheme nach Plugin-Unload nicht in
  // die freigegebene Impl-Instanz schiesst.
  TThemeNotifier = class(TNotifierObject, INTAIDEThemingServicesNotifier)
  private
    FOwner : TIDEThemeImpl;
  public
    constructor Create(AOwner: TIDEThemeImpl);
    procedure ChangingTheme;
    procedure ChangedTheme;
    procedure Detach;
  end;

  // Zweiter, UNABHAENGIGER Notifier: das EDITOR-FARBSCHEMA. Es kann sich
  // ohne IDE-Theme-Wechsel aendern (Tools > Optionen > Editor > Farbe),
  // und dann stimmen EditorBg und alle daraus abgeleiteten Markerfarben
  // nicht mehr.
  //
  // GEMESSEN am 2026-08-10: RAD 12 bedient ihn, AddEditorColorNotifier
  // liefert einen gueltigen Index, und er feuert BEIDE Faelle - sowohl
  // beim Farbschema- als auch beim Theme-Wechsel. Deshalb genuegt dieser
  // eine Notifier; ein zweiter Weg fuer den Theme-Fall waere doppelt.
  //
  // Erst ab Interface-Stufe 260 verfuegbar; Supports() klaert das.
  TEditorColorNotifier = class(TNotifierObject, IOTAEditorColorSpeedSetting)
  private
    FOwner : TIDEThemeImpl;
  public
    constructor Create(AOwner: TIDEThemeImpl);
    procedure EditorColorChanging;
    procedure EditorColorChanged;
    procedure Detach;
  end;

  // Per-Control Snapshot der Original-System-Color-Identifier
  // (clBtnFace / clWindow / clWindowText / ...). Wird beim ersten
  // ResolveIDEColor pro Control eingefangen damit nachfolgende Theme-
  // Switches gegen den Original-Identifier resolven (sonst Second-Switch-
  // Bug: nach erstem Resolve verliert Color das clSystemColor-Bit und
  // wird beim naechsten Switch nicht mehr aufgeloest).
  TControlColors = record
    Color     : TColor;
    FontColor : TColor;
  end;

  TIDEThemeImpl = class
  private
    FSubs        : TList<TSubscription>;
    FNotifierIdx : Integer;
    FNotifierIfc : IInterface;
    FNotifierObj : TThemeNotifier;
    // Zweiter Notifier, eigener Index-Raum: RemoveEditorColorNotifier ist
    // nicht RemoveNotifier. Die Indizes zu verwechseln haette die IDE ein
    // fremdes Abo abmelden lassen.
    FColorNotifIdx : Integer;
    FColorNotifIfc : IInterface;
    FColorNotifObj : TEditorColorNotifier;
    // Color-Cache - nach Theme-Wechsel invalidiert, beim naechsten Read
    // lazy neu berechnet.
    FCacheValid  : Boolean;
    // Eigenes Flag, weil FEditorBg aus einer ANDEREN Quelle kommt
    // (INTACodeEditorServices) und zu einer anderen Zeit bereit ist.
    // Beim IDE-Start ohne offene Datei faellt genau dieser Dienst aus,
    // waehrend das Theming laengst steht - ein gemeinsames Flag haette
    // das clNone dann zusammen mit den richtigen Rahmenfarben
    // eingefroren.
    FEditorBgValid : Boolean;
    FFrameBg     : TColor;
    FFrameFg     : TColor;
    FEditorBg    : TColor;
    // Origin-Color-Snapshot pro Control. Key = Pointer(TControl);
    // Wert = (orig Color, orig Font.Color). Wird in ApplyRecursive beim
    // ersten Encounter befuellt; bei spaeteren Theme-Switches gelesen.
    //
    // Lifetime: Eintraege werden nie geloescht. Raw-Pointer-Key heisst:
    // wenn ein Control freigegeben + neuer Control an gleiche Adresse
    // allokiert wird, liefert GetOrigColors veraltete Werte. In der
    // Praxis unkritisch - Frame + Childs leben die ganze IDE-Session.
    FOrigColors  : TDictionary<Pointer, TControlColors>;
    procedure EnsureNotifier;
    procedure RebuildCache;
    procedure NotifyChanged;
    procedure RegisterSub(ASub: TSubscription);
    procedure UnregisterSub(ASub: TSubscription);
  public
    constructor Create;
    destructor Destroy; override;
    function GetOrigColors(AC: TControl;
      const ACurrent: TControlColors): TControlColors;
  end;

var
  // Unit-globaler Singleton. nil bis zum ersten Apply/Subscribe-Call,
  // damit Plugin-Init nicht zur Falle wird wenn BorlandIDEServices noch
  // nicht da ist.
  G: TIDEThemeImpl;

// Wirkt diese Farbe perzeptuell dunkel? Aus TIDETheme.IsDark
// herausgezogen, weil Apply die Frage seit 2026-08-24 fuer eine Farbe
// beantworten muss, die NICHT aus dem Cache stammt.
function IstDunkel(AColor: TColor): Boolean;
const
  // 50 % von 255, perzeptuelle Mitte. Unter dieser Luminanz behandeln
  // Subscriber das Theme als "dunkel" und schalten Dark-Mode-Akzente ein.
  DARK_LUMINANCE_MAX = 127;
var
  Rgb       : Cardinal;
  Luminance : Integer;
begin
  Rgb := ColorToRGB(AColor);
  // ITU-R BT.601 perzeptuelles Mittel
  Luminance := (GetRValue(Rgb) * 299 + GetGValue(Rgb) * 587 +
                GetBValue(Rgb) * 114) div 1000;
  Result := Luminance <= DARK_LUMINANCE_MAX;
end;

procedure EnsureImpl;
begin
  if G = nil then
    G := TIDEThemeImpl.Create;
end;

// ---------------------------------------------------------------------------
// TSubscription
// ---------------------------------------------------------------------------

constructor TSubscription.Create(ACallback: TThemeChangedProc);
begin
  inherited Create;
  FCallback := ACallback;
end;

destructor TSubscription.Destroy;
begin
  // Singleton kann waehrend Plugin-Teardown vor uns sterben. Dann ist
  // G bereits nil und das Unregister wird zum no-op.
  if Assigned(G) then
    G.UnregisterSub(Self);
  inherited;
end;

// ---------------------------------------------------------------------------
// TThemeNotifier
// ---------------------------------------------------------------------------

constructor TThemeNotifier.Create(AOwner: TIDEThemeImpl);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TThemeNotifier.ChangingTheme;
begin
  // Pre-Switch: nichts zu tun. Service feuert das Event BEVOR der neue
  // Style aktiv ist - jetzt zu invalidieren waere verfrueht.
end;

procedure TThemeNotifier.ChangedTheme;
begin
  if Assigned(FOwner) then
    FOwner.NotifyChanged;
end;

procedure TThemeNotifier.Detach;
begin
  FOwner := nil;
end;

// ---------------------------------------------------------------------------
// TEditorColorNotifier
// ---------------------------------------------------------------------------

constructor TEditorColorNotifier.Create(AOwner: TIDEThemeImpl);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TEditorColorNotifier.EditorColorChanging;
begin
  // Wie bei ChangingTheme: das Ereignis kommt VOR der Umstellung, jetzt zu
  // invalidieren waere verfrueht - der naechste Read holte die alten Farben.
end;

procedure TEditorColorNotifier.EditorColorChanged;
begin
  if Assigned(FOwner) then
    FOwner.NotifyChanged;
end;

procedure TEditorColorNotifier.Detach;
begin
  FOwner := nil;
end;

// ---------------------------------------------------------------------------
// TIDEThemeImpl
// ---------------------------------------------------------------------------

constructor TIDEThemeImpl.Create;
begin
  inherited Create;
  FSubs          := TList<TSubscription>.Create;
  FNotifierIdx   := -1;
  FColorNotifIdx := -1;
  FCacheValid    := False;
  FEditorBgValid := False;
  FOrigColors  := TDictionary<Pointer, TControlColors>.Create;
end;

destructor TIDEThemeImpl.Destroy;
var
  Theming: IOTAIDEThemingServices;
begin
  // Reihenfolge: Detach VOR RemoveNotifier - sonst koennte ein
  // im Flug befindlicher ChangedTheme-Call noch in unsere bereits
  // teilweise zerlegte Instanz feuern.
  if Assigned(FNotifierObj) then
    FNotifierObj.Detach;

  if Assigned(FColorNotifObj) then
    FColorNotifObj.Detach;

  if FNotifierIdx <> -1 then
  begin
    if Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) then
      Theming.RemoveNotifier(FNotifierIdx);
    FNotifierIdx := -1;
  end;
  FNotifierIfc := nil;
  FNotifierObj := nil;

  // Eigener Index-Raum, eigene Abmelde-Methode. Das Supports() wird
  // bewusst ein zweites Mal gemacht statt das Ergebnis von oben zu
  // benutzen: liefert der Dienst beim Herunterfahren schon nichts mehr,
  // sollen beide Abmeldungen unabhaengig voneinander scheitern duerfen.
  //
  // GExperts hat seinen Theme-Notifier genau hier auskommentiert - das
  // Freigeben waehrend des IDE-Endes warf eine Invalid-Pointer-Ausnahme,
  // weil die Theming-Dienste vor dem Plugin zerstoert werden. Die
  // Reihenfolge Detach-vor-Remove und das Supports() sind der Schutz
  // dagegen; das Detach oben wirkt auch dann, wenn das Remove ausfaellt.
  if FColorNotifIdx <> -1 then
  begin
    if Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) then
      Theming.RemoveEditorColorNotifier(FColorNotifIdx);
    FColorNotifIdx := -1;
  end;
  FColorNotifIfc := nil;
  FColorNotifObj := nil;

  // Die Subscriptions selbst NICHT freigeben - sie sind refcount-owned
  // vom Aufrufer. Nur unsere Liste.
  FreeAndNil(FSubs);
  FreeAndNil(FOrigColors);
  inherited;
end;

function TIDEThemeImpl.GetOrigColors(AC: TControl;
  const ACurrent: TControlColors): TControlColors;
// Liefert die Original-System-Color-Identifier fuer AC. Erster Aufruf
// pro Control: ACurrent wird gespeichert + zurueckgegeben. Spaetere
// Aufrufe: gespeicherter Wert. Damit kann ResolveIDEColor bei jedem
// Theme-Switch gegen den Original-Identifier (clBtnFace etc.) resolven,
// statt gegen den schon konkreten RGB vom letzten Switch.
begin
  if not FOrigColors.TryGetValue(Pointer(AC), Result) then
  begin
    Result := ACurrent;
    FOrigColors.Add(Pointer(AC), Result);
  end;
end;

procedure TIDEThemeImpl.EnsureNotifier;
var
  Theming    : IOTAIDEThemingServices;
  Notifier   : TThemeNotifier;
  ColorNotif : TEditorColorNotifier;
  Idx        : Integer;
begin
  if FNotifierIdx <> -1 then Exit;
  if not Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) then Exit;

  Notifier := TThemeNotifier.Create(Self);
  FNotifierObj := Notifier;
  FNotifierIfc := Notifier as INTAIDEThemingServicesNotifier;
  FNotifierIdx := Theming.AddNotifier(
    FNotifierIfc as INTAIDEThemingServicesNotifier);

  // Zweiter Notifier fuer das Editor-Farbschema. Rueckgabe < 0 heisst
  // Fehler (ToolsAPI.pas:10545) - dann NICHT merken, sonst meldete der
  // Destruktor spaeter Index -1 ab.
  if FColorNotifIdx = -1 then
  begin
    ColorNotif := TEditorColorNotifier.Create(Self);
    FColorNotifObj := ColorNotif;
    FColorNotifIfc := ColorNotif as IOTAEditorColorSpeedSetting;
    Idx := Theming.AddEditorColorNotifier(
      FColorNotifIfc as IOTAEditorColorSpeedSetting);
    if Idx >= 0 then
      FColorNotifIdx := Idx
    else
    begin
      // Aeltere IDE ohne Stufe 260 oder Dienst verweigert: der
      // Theme-Notifier allein bleibt, das Verhalten faellt auf den Stand
      // vor 2026-08-10 zurueck.
      FColorNotifIfc := nil;
      FColorNotifObj := nil;
    end;
  end;
end;

procedure TIDEThemeImpl.RebuildCache;
var
  Svc     : INTACodeEditorServices;
  Theming : IOTAIDEThemingServices;
  Style   : TCustomStyleServices;
  AusIde  : Boolean;
begin
  // Bevorzugt die IDE-Style-Quelle. Vcl.Themes.StyleServices (global) ist
  // im Docked-Modus haeufig stale - dann liefern FrameBg/FrameFg Farben
  // vom vorigen Theme. Fallback nur wenn das ToolsAPI-Service nicht da ist.
  if Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) then
    Style := Theming.StyleServices
  else
    Style := nil;
  // NICHT nur "Dienst da?", sondern "Theme steht?". Waehrend des
  // Paketladens antwortet Supports() bereits erfolgreich, das Theme ist
  // aber noch nicht angewandt - dann liefert StyleServices die hellen
  // Vorgabefarben, und ein blosses Assigned() haette sie als gueltig
  // festgeschrieben. ActiveTheme ist erst dann nicht leer, wenn die IDE
  // ihr Theme gesetzt hat.
  //
  // Bewusst ActiveTheme und NICHT IDEThemingEnabled: ein absichtlich
  // abgeschaltetes Theming ist ein gueltiger Dauerzustand und wuerde den
  // Cache sonst nie gueltig werden lassen.
  AusIde := Assigned(Style) and Assigned(Theming) and (Theming.ActiveTheme <> '');
  if not Assigned(Style) then
    Style := StyleServices;

  FFrameBg := Style.GetSystemColor(clWindow);
  FFrameFg := Style.GetSystemColor(clWindowText);
  FEditorBg := clNone;
  FEditorBgValid := False;
  try
    if Supports(BorlandIDEServices, INTACodeEditorServices, Svc) then
    begin
      FEditorBg := Svc.Options.BackgroundColor[atWhiteSpace];
      FEditorBgValid := FEditorBg <> clNone;
    end;
  except
    // Editor-Service kann waehrend Plugin-Init noch nicht initialisiert
    // sein. clNone als Fallback signalisiert "frag StyleServices.clWindow".
  end;
  // NUR cachen, wenn die Farben aus der IDE-Quelle stammen.
  //
  // Bis zum 2026-08-24 stand hier ein unbedingtes True. Kam der Fallback
  // zum Zug - das ToolsAPI-Service ist waehrend des Plugin-Starts eine
  // Weile nicht da -, dann wurden die Farben der globalen
  // Vcl.Themes.StyleServices als gueltig festgeschrieben. Das ist im
  // bds.exe-Prozess der VCL-Vorgabestyle, also HELL, und es blieb so bis
  // zum naechsten Theme-Ereignis.
  //
  // Gemessen an der Diagnosedatei des Profil-Fensters: erster Aufruf
  // dark=0 caption=$FFFFFF, 25 Sekunden spaeter dasselbe Fenster dark=1
  // caption=$322F2D. Zwischen beiden lag nichts als ein Theme-Ereignis,
  // das den Cache verwarf.
  //
  // Ungueltig lassen heisst: der naechste Zugriff fragt erneut. Das
  // kostet einen Supports-Aufruf, solange das Service fehlt - und liefert
  // richtige Farben, sobald es da ist.
  FCacheValid := AusIde;
end;

procedure TIDEThemeImpl.NotifyChanged;
var
  i        : Integer;
  Snapshot : TArray<TSubscription>;
begin
  FCacheValid    := False;
  FEditorBgValid := False;
  // Den geteilten Cache in SCA.SharedUI mitziehen. Bis 2026-08-10 passierte
  // das NIE: der Kommentar an GCachedEditorBgDark behauptete eine
  // Auffrischung "nach jedem Settings-Save / Theme-Change", fuer den
  // Theme-Fall gab es aber keinen einzigen Aufrufer. Die Editor-Marker
  // behielten damit die Helligkeitsentscheidung vom Plugin-Start.
  //
  // VOR der Subscriber-Schleife: deren Callbacks lesen den Cache bereits.
  uAnalyserTheme.RefreshEditorBgDarkCache;
  // Snapshot bevor wir iterieren - Subscriber-Callback koennte sich selbst
  // (oder andere) unsubscriben, was die Liste mutiert.
  Snapshot := FSubs.ToArray;
  for i := 0 to High(Snapshot) do
  begin
    if not Assigned(Snapshot[i]) then Continue;
    if not Assigned(Snapshot[i].FCallback) then Continue;
    try
      Snapshot[i].FCallback();
    except
      // Ein Subscriber-Crash darf andere Subscriber nicht stoppen.
      // Die IDE schluckt sowieso alles in der Notifier-Kette - hier
      // genauso defensiv.
    end;
  end;
end;

procedure TIDEThemeImpl.RegisterSub(ASub: TSubscription);
begin
  if Assigned(FSubs) and (FSubs.IndexOf(ASub) < 0) then
    FSubs.Add(ASub);
end;

procedure TIDEThemeImpl.UnregisterSub(ASub: TSubscription);
begin
  if Assigned(FSubs) then
    FSubs.Remove(ASub);
end;

// ---------------------------------------------------------------------------
// TIDETheme (statische Facade)
// ---------------------------------------------------------------------------

type
  // Hack-Class um auf protected TControl.Color / .Font zuzugreifen.
  TControlAccess = class(TControl);

procedure ResolveIDEColor(var AColor: TColor;
  const AStyle: TCustomStyleServices);
// Wenn AColor ein System-Color-Identifier (clBtnFace, clWindow, ...) ist,
// resolve ihn ueber AStyle zur konkreten RGB-Aufloesung. Identifier-Bit
// ist $80000000 (clSystemColor).
//
// Hintergrund (Konzept_DockedThemeRefresh.md):
//   System-Color-Properties (TPanel.Color := clBtnFace) werden zur Paint-
//   Zeit ueber die VCL-globale Vcl.Themes.StyleServices aufgeloest. Im
//   Docked-Modus ist die VCL-globale aber NICHT auf das IDE-Theme syncen
//   (Theming.ApplyTheme(IDE-Main) propagiert nicht in fremde Frame-
//   Subtrees). Mit dieser Funktion schreiben wir konkrete RGB-Werte aus
//   dem aktiven IDE-Theme direkt auf den Control — Paint haengt nicht
//   mehr von VCL-Style-Aufloesung ab.
begin
  if (AColor <> clNone) and ((AColor and clSystemColor) <> 0) then
    AColor := AStyle.GetSystemColor(AColor);
end;

procedure ApplyStyleHookPreserveSeClient(ATheming: IOTAIDEThemingServices;
  AC: TControl);
// ApplyTheme registriert den IDE-Style-Hook auf AC. Sichert dabei den
// "StyleElements - [seClient]"-Trick: Controls, die ihren Hintergrund per
// eigener Color (statt Style-Farbe) malen sollen, werden mit entferntem
// seClient erzeugt (Tile-Panels, Help-Panel-Caption, die Options-ScrollBox).
// Falls ATheming.ApplyTheme intern StyleElements auf den Default
// [seBorder, seClient, seFont] zurueckschreibt, wuerde das den Trick brechen.
// Snapshot + Restore garantiert die Persistenz ueber alle Theme-Switches.
//
// Gilt fuer JEDES TControl, nicht nur TCustomControl: eine TScrollBox
// (TScrollingWinControl) wird von TScrollBoxStyleHook gemalt, dessen Brush
// fest auf GetStyleColor(scWindow) steht und Control.Color IGNORIERT. Nur ohne
// seClient lehnt der Hook WM_ERASEBKGND ab und das Erase faellt auf
// TWinControl.WMEraseBkgnd = eigene Color zurueck (verifiziert an Vcl.Themes/
// Vcl.Controls-Quelle). StyleElements ist auf TControl deklariert; der
// TControlAccess-Cracker erreicht es fuer alle Control-Klassen. No-op fuer
// Controls mit Default-seClient (HadSeClient=True -> kein Restore), also
// unkritisch fuer die uebrigen bereits gethemten Controls.
var
  HadSeClient : Boolean;
begin
  HadSeClient := seClient in TControlAccess(AC).StyleElements;

  ATheming.ApplyTheme(AC);

  if not HadSeClient then
    TControlAccess(AC).StyleElements :=
      TControlAccess(AC).StyleElements - [seClient];
end;

procedure ResolveDescendantColors(AC: TControl;
  const AIdeStyle: TCustomStyleServices);
// Color + Font.Color auf konkrete RGB-Werte aus dem IDE-Style aufloesen.
// Resolution laeuft gegen den ORIGINAL-Identifier (clBtnFace, clWindow, ...),
// gecached pro Control in G.GetOrigColors - sonst wuerde der zweite Switch
// gegen den schon konkreten RGB vom ersten resolven (Second-Switch-Bug).
// Im Docked-Modus essenziell, weil VCL-globale StyleServices nicht auf das
// IDE-Theme syncen.
var
  Cur, Orig : TControlColors;
  C         : TColor;
begin
  Cur.Color     := TControlAccess(AC).Color;
  Cur.FontColor := TControlAccess(AC).Font.Color;
  Orig := G.GetOrigColors(AC, Cur);

  C := Orig.Color;
  ResolveIDEColor(C, AIdeStyle);
  TControlAccess(AC).Color := C;

  C := Orig.FontColor;
  ResolveIDEColor(C, AIdeStyle);
  TControlAccess(AC).Font.Color := C;
end;

procedure BindToIdeStyle(AC: TControl; const AIdeStyle: TCustomStyleServices);
// Per-Control-Style (Delphi 10.4+): bindet AC direkt an den IDE-Style-Namen.
// Damit lesen VCL-Style-Hooks (TButton, TComboBox, TStringGrid-Border,
// TProgressBar, TStatusBar) ihre Farben aus dem IDE-Style statt aus der
// VCL-globalen StyleServices die im Docked-Modus stale ist - ohne den
// 2-Sek-Hang von TStyleManager.SetStyle (siehe TIDETheme.Apply).
begin
  if AIdeStyle.Name <> '' then
    AC.StyleName := AIdeStyle.Name;
end;

procedure TriggerRepaint(AC: TControl);
// Invalidate ohne synchrones Update (Update wuerde flackern - siehe GExperts
// Bug #86, GX_GrepResults ForceRedraw via Visible-Toggle). Color/Font.Color
// sind bereits auf konkrete RGB-Werte gesetzt - der spaetere WM_PAINT laeuft
// also gegen feste Farben.
// TCustomGrid braucht zusaetzlich Repaint: StringGrid/DrawGrid haben einen
// eigenen Paint-Cache, der vom Invalidate nicht verlaesslich getroffen wird.
begin
  AC.Invalidate;
  if AC is TCustomGrid then
    TCustomGrid(AC).Repaint;
end;

procedure ApplyRecursive(ATheming: IOTAIDEThemingServices; AC: TControl);
// Walked den Control-Baum unter AC und fuehrt pro Knoten die Apply-Pipeline
// aus (siehe Unit-Header). Per-Descendant ApplyTheme ist Pflicht:
// IOTAIDEThemingServices.ApplyTheme propagiert in Delphi 12 nicht
// zuverlaessig transitiv von einem TFrame auf seine Kinder (commit f3c77ac).
//
// Siehe Konzept_DockedThemeRefresh.md fuer die drei kausalen Ursachen
// und den kombinierten Fix.
var
  i        : Integer;
  WC       : TWinControl;
  IdeStyle : TCustomStyleServices;
begin
  if Assigned(ATheming) then
  begin
    ApplyStyleHookPreserveSeClient(ATheming, AC);

    IdeStyle := ATheming.StyleServices;
    if Assigned(IdeStyle) and Assigned(G) then
    begin
      ResolveDescendantColors(AC, IdeStyle);
      BindToIdeStyle(AC, IdeStyle);
    end;
  end;

  TriggerRepaint(AC);

  if AC is TWinControl then
  begin
    WC := TWinControl(AC);
    for i := 0 to WC.ControlCount - 1 do
      ApplyRecursive(ATheming, WC.Controls[i]);
  end;
end;

class procedure TIDETheme.Apply(AControl: TWinControl);
var
  Theming : IOTAIDEThemingServices;
  TopForm : TCustomForm;
  TitelBg : TColor;
  TitelFg : TColor;
  Quelle  : string;
begin
  if AControl = nil then Exit;

  EnsureImpl;
  G.EnsureNotifier;

  if not Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) then
    Theming := nil;

  if Assigned(Theming) then
  begin
    // Bewusst KEIN TStyleManager.SetStyle(IDE-Theme.Name):
    // SetStyle ruft intern SendStyleChangedMessage = Loop ueber Screen.Forms[]
    // mit Perform(CM_STYLECHANGED). Jede IDE-Form (50+) benachrichtigt ihre
    // Children (1000+ Controls), jeder Style-Hook invalidiert + repainted.
    // Resultat: ~2 Sek Block der gesamten IDE pro Theme-Switch.
    //
    // Stattdessen routen wir VCL-Style-Hooks via per-Control TControl.StyleName
    // in ApplyRecursive auf den IDE-Style (siehe BindToIdeStyle). Selbe
    // Wirkung fuer unsere Controls (TButton, TComboBox, TStringGrid-Border,
    // TProgressBar, TStatusBar), ohne den globalen Broadcast.
    //
    // Historie: commit daabca5 hatte TrySetStyle drin - der Hang war zu teuer.

    // ToolsAPI-vorgesehener Weg um eine Form-Klasse fuer IDE-Theming zu
    // aktivieren: RegisterFormClass + ApplyTheme.
    TopForm := GetParentForm(AControl);
    if Assigned(TopForm) then
    begin
      Theming.RegisterFormClass(TCustomFormClass(TopForm.ClassType));
      Theming.ApplyTheme(TopForm);
      TopForm.Invalidate;
    end;
  end;

  // Per-Descendant ApplyTheme + Invalidate. Pflicht-Pfad - propagiert
  // selber durch die Frame-Hierarchie, unabhaengig davon ob TopForm
  // (Float = TOTADockForm) oder die IDE-Main-Form (Docked) ist.
  ApplyRecursive(Theming, AControl);

  // Die Titelzeile zum Schluss, und NUR wenn ein Fenster uebergeben
  // wurde. Zwei Gruende fuer diese Reihenfolge und diese Bedingung:
  //
  //   * ApplyRecursive setzt je Control StyleName, und das erzeugt das
  //     Fensterhandle neu (nachgewiesen an einem Aufrufstapel am
  //     2026-08-24). Das DWM-Attribut haengt am Handle - vorher gesetzt
  //     waere es verloren.
  //   * Alle heutigen Aufrufer uebergeben FRAMES. Wuerde die Titelzeile
  //     ueber GetParentForm ermittelt, faerbte ein gedockter Frame die
  //     Titelzeile der IDE selbst um. Das steht uns nicht zu.
  if AControl is TCustomForm then
  begin
    // Farben aus der LEBENDEN Quelle, nicht aus dem Cache.
    //
    // Das ist das Muster, das dieses Projekt ohnehin ueberall verfolgt:
    // ApplyRecursive dreissig Zeilen weiter oben liest
    // ATheming.StyleServices direkt, ebenso die Stat-Tiles, das
    // Hilfe-Panel und das Properties-Frame. Nur die Titelzeile hat
    // bisher FrameBg/FrameFg genommen - also den Cache - und damit in
    // EINER Funktion aus zwei Quellen gelesen.
    //
    // Das ist keine Stilfrage. Der Cache wird beim Paketladen gefuellt
    // (Prime -> RefreshEditorBgDarkCache -> EditorBgProvider ->
    // EditorBg -> RebuildCache), also waehrend des Splashs, wenn das
    // IDE-Theme noch nicht steht. Gemessen: erstes Oeffnen des
    // Profil-Fensters dark=0 caption=$FFFFFF, 25 Sekunden spaeter
    // dasselbe Fenster dark=1 caption=$322F2D.
    //
    // Aus der lebenden Quelle gelesen ist jedes geoeffnete Fenster
    // selbstkorrigierend - unabhaengig davon, was im Cache steht und ob
    // je ein Notifier gefeuert hat.
    if Assigned(Theming) and Assigned(Theming.StyleServices) then
    begin
      TitelBg := Theming.StyleServices.GetSystemColor(clWindow);
      TitelFg := Theming.StyleServices.GetSystemColor(clWindowText);
      Quelle  := 'live';
    end
    else
    begin
      // Kein Theming-Dienst: dann ist der Cache die einzige Auskunft,
      // die es gibt.
      TitelBg := FrameBg;
      TitelFg := FrameFg;
      Quelle  := 'cache';
    end;

    // Selbstauskunft. Die Diagnosedatei zeigte am 2026-08-24 drei
    // Oeffnungen binnen 32 Sekunden, davon eine mit weisser Titelzeile -
    // und das mit dem Code, der bereits LIVE liest. Damit ist die Frage
    // nicht mehr "Cache oder nicht", sondern: welches Fenster war es, und
    // was hat die IDE zu diesem Zeitpunkt ueber ihr eigenes Theme gesagt.
    if Assigned(Theming) then
      TAppTheme.LogLine(Format('IDE-Apply: %s "%s" quelle=%s theme="%s" enabled=%d',
        [AControl.ClassName, TCustomForm(AControl).Caption, Quelle,
         Theming.ActiveTheme, Ord(Theming.IDEThemingEnabled)]))
    else
      TAppTheme.LogLine(Format('IDE-Apply: %s "%s" quelle=%s KEIN Theming-Dienst',
        [AControl.ClassName, TCustomForm(AControl).Caption, Quelle]));
    TAppTheme.ApplyTitleBarTheme(TCustomForm(AControl), IstDunkel(TitelBg),
                                 TitelBg, TitelFg);
  end;
end;

class function TIDETheme.Subscribe(ACallback: TThemeChangedProc): IInterface;
var
  Sub : TSubscription;
begin
  EnsureImpl;
  G.EnsureNotifier;
  Sub := TSubscription.Create(ACallback);
  G.RegisterSub(Sub);
  Result := Sub;
end;

class function TIDETheme.FrameBg: TColor;
begin
  EnsureImpl;
  if not G.FCacheValid then G.RebuildCache;
  Result := G.FFrameBg;
end;

class function TIDETheme.OptionsFrameBg: TColor;
begin
  // Dark-Theme: kuratierter Ton beibehalten (User-Wahl 2026-06-19). Light-Theme:
  // die theme-korrekte System-Window-Farbe statt der Dunkelfarbe (Bugfix).
  if IsDark then
    Result := IDE_BG_OPTIONS_FRAME
  else
    Result := FrameBg;
end;

class function TIDETheme.FrameFg: TColor;
begin
  EnsureImpl;
  if not G.FCacheValid then G.RebuildCache;
  Result := G.FFrameFg;
end;

class function TIDETheme.EditorBg: TColor;
begin
  EnsureImpl;
  // Auch neu holen, wenn NUR der Editor-Wert fehlt. Beim IDE-Start ohne
  // offene Datei antwortet INTACodeEditorServices nicht, das Theming
  // aber schon - mit dem gemeinsamen Flag blieb das clNone dann stehen,
  // bis irgendein Notifier feuerte.
  if not (G.FCacheValid and G.FEditorBgValid) then G.RebuildCache;
  Result := G.FEditorBg;
end;

class function TIDETheme.IsDark: Boolean;
begin
  Result := IstDunkel(TIDETheme.FrameBg);
end;

class procedure TIDETheme.Prime;
// Vertrag und Begruendung stehen an der Deklaration.
begin
  EnsureImpl;
  if Assigned(G) then
  begin
    G.EnsureNotifier;
    // Cache gleich mit dem richtigen Wert fuellen. Ohne das haette
    // GCachedEditorBgDark bis zum ersten Theme-Ereignis den Vorgabewert
    // False, obwohl der EditorBgProvider zu diesem Zeitpunkt schon steht.
    uAnalyserTheme.RefreshEditorBgDarkCache;

    // ...und den Farb-Cache danach WIEDER verwerfen.
    //
    // Der Aufruf darueber ist nicht harmlos: er laeuft ueber
    // IsEditorBgDark -> EditorBgProvider -> TIDETheme.EditorBg in ein
    // RebuildCache hinein. Prime kommt aber aus InstallSharedUiHooks,
    // also aus dem Paketlade-Pfad waehrend des Splashs - genau dann ist
    // das IDE-Theme noch nicht angewandt.
    //
    // Ohne diese Zeile war Prime der Grund, aus dem der Cache die
    // Splash-Farben trug: gefuellt wurde er hier, verworfen nur von
    // NotifyChanged, und die beiden Notifier melden ausschliesslich
    // AENDERUNGEN. Die IDE setzt ihr Theme lange vor unserem Register -
    // es feuert also nichts, und der falsche Wert stand die ganze
    // Sitzung.
    G.FCacheValid    := False;
    G.FEditorBgValid := False;
  end;
end;

initialization

finalization
  // Singleton freigeben - das deregistriert den Notifier und leert die
  // Subscription-Liste. Noch lebende TSubscription-Instanzen (Refcount > 0)
  // sehen beim spaeteren Destroy G=nil und werden zu no-ops.
  if Assigned(G) then
  begin
    var T := G;
    G := nil;
    T.Free;
  end;

end.

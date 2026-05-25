unit uIDETheme;

// Zentraler IDE-Theme-Manager fuer das Analyser-Plugin.
//
// ZWECK
//   Ein einziger Notifier registriert sich beim IOTAIDEThemingServices.
//   Frames/Forms melden sich via Subscribe(Callback) an und bekommen den
//   Theme-Wechsel als reguliertem Method-Call mitgeteilt. Apply(Control)
//   ist die kanonische "wende aktuelles IDE-Theme jetzt an" Operation -
//   inklusive Float-Mode-TopForm-Refresh und Grid-Repaint-Sonderlocke.
//
// VORHER
//   - uIDEThemeIntegration.TIDEThemeIntegration pro Frame mit eigener
//     Notifier-Registration + Detach-Tanz (~240 Zeilen)
//   - Frei stehende ApplyIDETheme()-Prozedur fuer One-Shot-Aufrufe in
//     Options-Pages
//   - CMStyleChanged-Message-Handler im Frame als zweiter Trigger
//   - 11 hardcoded Color := clBtnFace in TAnalyserFrame
//
// NACHHER
//   - Eine Unit, eine Klasse, drei Public-Methoden
//   - Notifier wird lazy beim ersten Subscribe oder Apply registriert
//   - Subscriber halten ein IInterface; bei dessen Free wird automatisch
//     unsubscribed (RAII, kein manueller Detach mehr)
//
// THREAD-MODELL
//   IOTAIDEThemingServices feuert ChangedTheme im Main-Thread. Keine
//   Locks noetig - alle Subscriber-Aufrufe laufen im VCL-Thread.
//
// FINALIZATION
//   Globaler Singleton wird in der Unit-Finalization sauber freigegeben,
//   was den Notifier abmeldet. Noch lebende Subscriptions (deren IInterface-
//   Halter den Frame noch nicht freigegeben haben) sehen G=nil und werden
//   beim spaeteren Free zu No-ops.

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
    // Wendet das aktuelle IDE-Theme auf AControl an. Hat drei Effekte:
    //   1. IOTAIDEThemingServices.ApplyTheme auf dem Top-Level-Form
    //      (Float-Mode: Host-TForm; sonst AControl selbst).
    //   2. Rekursives Invalidate aller Kindcontrols.
    //   3. Explizites Repaint auf TCustomGrid-Descendants (StringGrid &
    //      DrawGrid haben einen Paint-Cache der vom Invalidate nicht
    //      verlaesslich getroffen wird).
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
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Winapi.Windows,
  Vcl.Forms, Vcl.Themes, Vcl.Grids,
  ToolsAPI, ToolsAPI.Editor;

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

  TIDEThemeImpl = class
  private
    FSubs        : TList<TSubscription>;
    FNotifierIdx : Integer;
    FNotifierIfc : IInterface;
    FNotifierObj : TThemeNotifier;
    // Color-Cache - nach Theme-Wechsel invalidiert, beim naechsten Read
    // lazy neu berechnet.
    FCacheValid  : Boolean;
    FFrameBg     : TColor;
    FFrameFg     : TColor;
    FEditorBg    : TColor;
    procedure EnsureNotifier;
    procedure RebuildCache;
    procedure NotifyChanged;
    procedure RegisterSub(ASub: TSubscription);
    procedure UnregisterSub(ASub: TSubscription);
  public
    constructor Create;
    destructor Destroy; override;
  end;

var
  // Unit-globaler Singleton. nil bis zum ersten Apply/Subscribe-Call,
  // damit Plugin-Init nicht zur Falle wird wenn BorlandIDEServices noch
  // nicht da ist.
  G: TIDEThemeImpl;

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
// TIDEThemeImpl
// ---------------------------------------------------------------------------

constructor TIDEThemeImpl.Create;
begin
  inherited Create;
  FSubs        := TList<TSubscription>.Create;
  FNotifierIdx := -1;
  FCacheValid  := False;
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

  if FNotifierIdx <> -1 then
  begin
    if Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) then
      Theming.RemoveNotifier(FNotifierIdx);
    FNotifierIdx := -1;
  end;
  FNotifierIfc := nil;
  FNotifierObj := nil;

  // Die Subscriptions selbst NICHT freigeben - sie sind refcount-owned
  // vom Aufrufer. Nur unsere Liste.
  FreeAndNil(FSubs);
  inherited;
end;

procedure TIDEThemeImpl.EnsureNotifier;
var
  Theming  : IOTAIDEThemingServices;
  Notifier : TThemeNotifier;
begin
  if FNotifierIdx <> -1 then Exit;
  if not Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) then Exit;

  Notifier := TThemeNotifier.Create(Self);
  FNotifierObj := Notifier;
  FNotifierIfc := Notifier as INTAIDEThemingServicesNotifier;
  FNotifierIdx := Theming.AddNotifier(
    FNotifierIfc as INTAIDEThemingServicesNotifier);
end;

procedure TIDEThemeImpl.RebuildCache;
var
  Svc : INTACodeEditorServices;
begin
  FFrameBg := StyleServices.GetSystemColor(clWindow);
  FFrameFg := StyleServices.GetSystemColor(clWindowText);
  FEditorBg := clNone;
  try
    if Supports(BorlandIDEServices, INTACodeEditorServices, Svc) then
      FEditorBg := Svc.Options.BackgroundColor[atWhiteSpace];
  except
    // Editor-Service kann waehrend Plugin-Init noch nicht initialisiert
    // sein. clNone als Fallback signalisiert "frag StyleServices.clWindow".
  end;
  FCacheValid := True;
end;

procedure TIDEThemeImpl.NotifyChanged;
var
  i        : Integer;
  Snapshot : TArray<TSubscription>;
begin
  FCacheValid := False;
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

procedure ApplyRecursive(ATheming: IOTAIDEThemingServices; AC: TControl);
// Walked den Control-Baum unter AC. Pro Knoten:
//   1. ApplyTheme via IOTAIDEThemingServices (registriert Style-Hook).
//   2. Color + Font.Color via IDE-StyleServices auf konkretes RGB resolven
//      und auf den Control schreiben (kritisch im Docked-Modus).
//   3. Invalidate + Update — SYNCHRONER WM_PAINT solange Theming.
//      StyleServices garantiert frisch ist.
//   4. TCustomGrid: zusaetzlich Repaint (Paint-Cache zwingen).
//
// Per-Descendant ApplyTheme ist Pflicht. IOTAIDEThemingServices.ApplyTheme
// propagiert in Delphi 12 nicht zuverlaessig transitiv von einem TFrame
// auf seine Kinder (commit f3c77ac).
//
// Siehe Konzept_DockedThemeRefresh.md fuer die drei kausalen Ursachen
// und den kombinierten Fix.
var
  i        : Integer;
  WC       : TWinControl;
  IdeStyle : TCustomStyleServices;
  C        : TColor;
begin
  if Assigned(ATheming) then
  begin
    ATheming.ApplyTheme(AC);

    // B: Color + Font.Color per IDE-StyleServices in konkrete RGB-Werte
    //    aufloesen. Macht den Control paint-zeit-unabhaengig von der
    //    VCL-globalen StyleServices.
    IdeStyle := ATheming.StyleServices;
    if Assigned(IdeStyle) then
    begin
      C := TControlAccess(AC).Color;
      ResolveIDEColor(C, IdeStyle);
      TControlAccess(AC).Color := C;

      C := TControlAccess(AC).Font.Color;
      ResolveIDEColor(C, IdeStyle);
      TControlAccess(AC).Font.Color := C;
    end;
  end;

  // Invalidate ohne synchrones Update (GExperts-Pattern in GX_GrepResults:
  // ForceRedraw via Visible-Toggle - Update fuehrt zu Flicker, dokumentiert
  // in GExperts-Bug #86). Color/Font.Color sind durch ResolveIDEColor oben
  // bereits auf konkrete RGB-Werte aus dem IDE-Theme gesetzt - der spaetere
  // WM_PAINT laeuft also gegen feste Farben, nicht gegen die noch sich
  // einpendelnde VCL-globale StyleServices.
  AC.Invalidate;
  if AC is TCustomGrid then
    TCustomGrid(AC).Repaint;

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
begin
  if AControl = nil then Exit;

  EnsureImpl;
  G.EnsureNotifier;

  if not Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) then
    Theming := nil;

  if Assigned(Theming) then
  begin
    // ToolsAPI-vorgesehener Weg um eine Form-Klasse fuer IDE-Theming zu
    // aktivieren: RegisterFormClass + ApplyTheme. Damit verwendet
    // ApplyTheme die IDE-eigene StyleServices (Theme-Service-intern)
    // statt der globalen Vcl.Themes.StyleServices.
    // Kein TStyleManager.SetStyle - das wuerde sonst die GESAMTE Delphi-
    // IDE re-painten (2-Sek-Hang).
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

class function TIDETheme.FrameFg: TColor;
begin
  EnsureImpl;
  if not G.FCacheValid then G.RebuildCache;
  Result := G.FFrameFg;
end;

class function TIDETheme.EditorBg: TColor;
begin
  EnsureImpl;
  if not G.FCacheValid then G.RebuildCache;
  Result := G.FEditorBg;
end;

class function TIDETheme.IsDark: Boolean;
var
  rgb     : Cardinal;
  R, G_, B: Integer;
  Lum     : Integer;
begin
  rgb := ColorToRGB(TIDETheme.FrameBg);
  R   := GetRValue(rgb);
  G_  := GetGValue(rgb);
  B   := GetBValue(rgb);
  // ITU-R BT.601 perzeptuelles Mittel
  Lum := (R * 299 + G_ * 587 + B * 114) div 1000;
  Result := Lum <= 127;
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

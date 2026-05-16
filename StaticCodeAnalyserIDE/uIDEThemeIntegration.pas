unit uIDEThemeIntegration;

// Kapselt die IDE-Theme-Integration des Analyser-Frames:
//   * Initiales ApplyTheme nach FrameCreated (Floating-Mode-Hooks etc.)
//   * Notifier-Registrierung beim IOTAIDEThemingServices
//   * RefreshFromIDETheme nach Theme-Wechsel: TopForm-ApplyTheme +
//     ApplyThemeRecursive(Frame) + optionaler Repaint-Callback (Grid)
//   * Saubere Notifier-Abmeldung im Destruktor
//
// Vorher: 3 Felder (FThemeNotifierIdx/Obj/Ifc), eine separate
// TFrameThemeNotifier-Klasse und ~80 Zeilen Theme-Logik direkt im
// Frame plus 14 Zeilen Notifier-Setup in TAnalyserDockableForm.
// FrameCreated. Jetzt zentralisiert in einer Helper-Komponente.
//
// Lifecycle:
//   1. Frame-Ctor: TIDEThemeIntegration.Create(Self, Self, ACallback)
//      - speichert Frame-Referenz und Repaint-Callback, FNotifierIdx := -1.
//   2. FrameCreated: Helper.Attach
//      - jetzt gibt es BorlandIDEServices und der Frame ist gehostet,
//        also ApplyTheme + Notifier registrieren.
//   3. Theme-Wechsel via IDE: Notifier ruft Helper.RefreshFromIDETheme.
//   4. Frame-Destroy: FreeAndNil(FThemeIntegration) explizit FRUEH (vor
//      anderen Frame-Feldern), damit der Notifier weg ist bevor das
//      Frame zerlegt wird.
//
// Wichtig:
//   * Der CMStyleChanged-Message-Handler muss in der Frame-Klasse
//     bleiben (Delphi-Message-Dispatch ist klassen-gebunden) und nur
//     auf RefreshFromIDETheme delegieren.
//   * SetParent-Override genauso - die Methode wird vom VCL-Framework
//     direkt am Frame aufgerufen, kann nicht ausgelagert werden.

interface

uses
  System.Classes,
  Vcl.Controls;

type
  // Wird nach jedem Theme-Refresh gerufen - Frame nutzt das fuer den
  // TStringGrid-Repaint, der ueber die rekursive Invalidate nicht
  // zuverlaessig vom Paint-Cache abgeholt wird.
  TThemeRefreshProc = procedure of object;

  TIDEThemeIntegration = class(TComponent)
  private
    FFrame          : TWinControl;
    FOnAfterRefresh : TThemeRefreshProc;
    FNotifierIdx    : Integer;
    // Klassenreferenz fuer Detach-Aufruf vor Notifier-Free.
    FNotifierObj    : TObject;
    // Interface-Referenz haelt den Notifier am Leben solange wir ihn
    // brauchen (parallel zur IDE-Service-Refcount-Referenz).
    FNotifierIfc    : IInterface;
  public
    // AFrame: Ziel-Control fuer ApplyTheme + ApplyThemeRecursive
    //         (i.d.R. der Analyser-Frame selbst).
    // AOnAfterRefresh: optional, wird am Ende von RefreshFromIDETheme
    //                  aufgerufen - z.B. fuer Grid-Repaint.
    constructor Create(AOwner: TComponent; AFrame: TWinControl;
      AOnAfterRefresh: TThemeRefreshProc); reintroduce;
    destructor Destroy; override;

    // Einmalig nach FrameCreated aufrufen: registriert Notifier und
    // wendet das aktuelle IDE-Theme an. Idempotent ist nicht noetig -
    // wird nur einmal pro Frame-Lifetime aufgerufen.
    procedure Attach;

    // Refresh-Pfad nach Theme-Wechsel oder VCL-Style-Change.
    //   1. Top-Level-Form via GetParentForm finden (Floating-Modus!)
    //      und ApplyTheme dort anwenden - sonst bleibt die Title-Bar
    //      im alten Theme.
    //   2. Fallback: ApplyTheme(FFrame) wenn kein Parent.
    //   3. ApplyThemeRecursive(FFrame) - Invalidate aller Kinder.
    //   4. Optionaler Callback fuer spezifische Repaints.
    procedure RefreshFromIDETheme;

    // Erzwingt Repaint und triggert TStringGrid-/TMemo-/TPanel-Caches
    // dazu, ihren neu gemappten clWindow/clBtnFace abzurufen. Public,
    // damit der Frame es bei Bedarf einzeln triggern kann.
    class procedure ApplyThemeRecursive(AControl: TControl); static;
  end;

// One-shot Theme-Anwendung fuer kurzlebige Frames/Forms (Tools>Options-Pages,
// Modaldialoge). KEIN Notifier - die IDE zerstoert und re-created den Frame
// beim naechsten Open, daher kommt das frische Theme automatisch beim
// naechsten FrameCreated. Fuer langlebige Forms (Dock-Window) stattdessen
// TIDEThemeIntegration mit Notifier verwenden.
procedure ApplyIDETheme(AComponent: TComponent);

implementation

uses
  System.SysUtils,
  Vcl.Forms,
  ToolsAPI;

procedure ApplyIDETheme(AComponent: TComponent);
var
  Theming : IOTAIDEThemingServices;
begin
  if AComponent = nil then Exit;
  if not Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) then Exit;
  if not Theming.IDEThemingEnabled then Exit;
  Theming.ApplyTheme(AComponent);
end;

type
  // Interner Notifier - haelt den Helper als Reference. Bei Helper-
  // Destroy wird Detach gerufen, sodass die Reference hier nie
  // dangling ist.
  TFrameThemeNotifier = class(TNotifierObject, INTAIDEThemingServicesNotifier)
  private
    FOwner: TIDEThemeIntegration;
  public
    constructor Create(AOwner: TIDEThemeIntegration);
    procedure ChangingTheme;
    procedure ChangedTheme;
    procedure Detach;
  end;

{ TFrameThemeNotifier }

constructor TFrameThemeNotifier.Create(AOwner: TIDEThemeIntegration);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TFrameThemeNotifier.ChangingTheme;
begin
  // Vor dem Wechsel: nichts zu tun. Der IDE-Service feuert das Event
  // bevor der neue Style aktiv ist, deshalb ist Repaint hier sinnlos.
end;

procedure TFrameThemeNotifier.ChangedTheme;
begin
  if Assigned(FOwner) then
    FOwner.RefreshFromIDETheme;
end;

procedure TFrameThemeNotifier.Detach;
begin
  FOwner := nil;
end;

{ TIDEThemeIntegration }

constructor TIDEThemeIntegration.Create(AOwner: TComponent; AFrame: TWinControl;
  AOnAfterRefresh: TThemeRefreshProc);
begin
  inherited Create(AOwner);
  FFrame          := AFrame;
  FOnAfterRefresh := AOnAfterRefresh;
  FNotifierIdx    := -1;
end;

destructor TIDEThemeIntegration.Destroy;
var
  Theming: IOTAIDEThemingServices;
begin
  // Reihenfolge ist wichtig:
  //   1. Detach: nimmt dem Notifier die Helper-Referenz - ein noch
  //      schwebender ChangedTheme-Call sieht jetzt FOwner=nil und exit'd.
  //   2. RemoveNotifier: IDE-Service gibt seinen Refcount frei.
  //   3. Interface-Refcount loslassen: Notifier wird freigegeben.
  if Assigned(FNotifierObj) then
    TFrameThemeNotifier(FNotifierObj).Detach;
  if FNotifierIdx <> -1 then
  begin
    if Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) then
      Theming.RemoveNotifier(FNotifierIdx);
    FNotifierIdx := -1;
  end;
  FNotifierIfc := nil;
  FNotifierObj := nil;
  inherited;
end;

procedure TIDEThemeIntegration.Attach;
var
  Theming  : IOTAIDEThemingServices;
  Notifier : TFrameThemeNotifier;
begin
  if not Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) then Exit;

  // ApplyTheme registriert die IDE-spezifischen Style-Hooks und
  // invalidiert rekursiv - im Floating-Modus essentiell.
  if Theming.IDEThemingEnabled then
    Theming.ApplyTheme(FFrame);

  // Notifier registrieren - haelt sowohl Klassenreferenz (fuer
  // Detach) als auch Interface (fuer Refcount), plus gibt eine
  // zweite Interface-Referenz an die IDE.
  Notifier := TFrameThemeNotifier.Create(Self);
  FNotifierObj := Notifier;
  FNotifierIfc := Notifier as INTAIDEThemingServicesNotifier;
  FNotifierIdx := Theming.AddNotifier(
    FNotifierIfc as INTAIDEThemingServicesNotifier);
end;

procedure TIDEThemeIntegration.RefreshFromIDETheme;
var
  Theming : IOTAIDEThemingServices;
  TopForm : TCustomForm;
begin
  if Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) then
    if Theming.IDEThemingEnabled then
    begin
      // ApplyTheme auf TopForm deckt rekursiv alle Kindcontrols ab -
      // inklusive unserem Frame. Self-ApplyTheme nur als Fallback wenn
      // (noch) kein Parent vorhanden ist.
      TopForm := GetParentForm(FFrame);
      if Assigned(TopForm) then
      begin
        Theming.ApplyTheme(TopForm);
        TopForm.Invalidate;
      end
      else
        Theming.ApplyTheme(FFrame);
    end;
  ApplyThemeRecursive(FFrame);
  if Assigned(FOnAfterRefresh) then
    FOnAfterRefresh();
end;

class procedure TIDEThemeIntegration.ApplyThemeRecursive(AControl: TControl);
var
  i  : Integer;
  WC : TWinControl;
begin
  AControl.Invalidate;
  if AControl is TWinControl then
  begin
    WC := TWinControl(AControl);
    for i := 0 to WC.ControlCount - 1 do
      ApplyThemeRecursive(WC.Controls[i]);
  end;
end;

end.

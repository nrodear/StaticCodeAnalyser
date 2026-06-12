unit uIDEExpert;

// Delphi IDE Expert: registriert "Static Code Analysis Tool for Delphi"
//   * Tools-Menu-Eintrag mit Icon (via INTAServices.AddImages + TAction)
//   * Splash-Screen-Eintrag waehrend IDE-Start
//   * Help -> About -> Plugins-Eintrag
//
// Tools-Menu-Pattern (canonical Embarcadero, OTAPI-Docs Kap. 15):
//   IOTAMenuWizard wird absichtlich NICHT verwendet - die kann keinen Icon.
//   Stattdessen direkt INTAServices.MainMenu manipulieren: BMP laden ->
//   in TImageList -> AddImages liefert ImageIndex in der IDE-Shared-Liste ->
//   TAction mit OnExecute + ImageIndex -> TMenuItem mit Action -> in das
//   ToolsMenu einhaengen.

interface

uses
  ToolsAPI;

type
  TStaticCodeAnalyserExpert = class(TNotifierObject, IOTAWizard)
  public
    destructor Destroy; override;
    { IOTAWizard }
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;
  end;

procedure Register;

implementation

// noinspection-file ConcatToFormat
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  Winapi.Windows, System.SysUtils,
  Vcl.Graphics, Vcl.ImgList, Vcl.Controls, Vcl.Menus, Vcl.ActnList,
  uIDEAnalyserForm;

const
  PLUGIN_TITLE   = 'Static Code Analysis';
  PLUGIN_DESC    = 'Static Code Analysis Tool for Delphi - findings, ' +
                   'metrics, leak detection, Sonar export.';
  PLUGIN_VERSION = 'v0.9.8';
  PLUGIN_LICENSE = 'Freeware / Open Source';

  // Resource-Namen aus branding\sca_branding.rc (BITMAP-Type).
  // 24x24 fuer Splash + About-Box (groesserer Header-Space).
  SCA_APP_BMP_RES   = 'SCA_APP_BMP';
  // 16x16 fuer das IDE-Tools-Menu (Standard-Menu-Icon-Groesse).
  SCA_APP_BMP16_RES = 'SCA_APP_BMP16';

type
  // Tiny Wrapper-Klasse weil TAction.OnExecute eine Methode (procedure of
  // object) erwartet, KEINE freie Prozedur. Lebt waehrend der gesamten
  // BPL-Laufzeit und wird in finalization freigegeben.
  TToolsMenuHandler = class
  public
    procedure MenuClick(Sender: TObject);
  end;

var
  // Index in der About-Box; gebraucht zum Unregister beim BPL-Unload.
  // -1 = nicht registriert (z.B. wenn IDE keine AboutBoxServices liefert).
  GAboutBoxIndex : Integer = -1;
  // Branding-HBITMAP fuer Splash + About-Box, gecached fuer BPL-Laufzeit.
  // 0 = nicht geladen (Resource fehlt oder LoadBitmap failed). Lebensdauer
  // an die BPL gekoppelt - die IDE haelt das Handle waehrend Splash + About-
  // Box, ein verfruehter DeleteObject wuerde dangling references erzeugen.
  GBrandingHBmp  : HBITMAP = 0;
  // Tools-Menu-Eintrag (TMenuItem in INTAServices.MainMenu) + die zugrunde
  // liegende TAction. Beide bei BPL-Unload freigeben sonst Dangling-Eintrag
  // im IDE-Menue bis IDE-Neustart.
  GToolsMenuItem : TMenuItem = nil;
  GToolsAction   : TAction   = nil;
  GToolsHandler  : TToolsMenuHandler = nil;

procedure TToolsMenuHandler.MenuClick(Sender: TObject);
// OnExecute-Methode der TAction - identisch zum vormaligen IOTAMenuWizard.
// Execute-Pfad: zeigt das Dockable-Form.
begin
  ShowAnalyserDockableForm;
end;

function BrandingHBitmap: HBITMAP;
// Canonical Embarcadero-Pattern (OTAPI-Docs Kap. 9): LoadBitmap(HInstance,
// '<resname>') liefert HBITMAP direkt aus der BITMAP-Resource. Null wenn
// Resource fehlt - dann fallen Splash/About auf Text-only zurueck.
begin
  if GBrandingHBmp = 0 then
    GBrandingHBmp := LoadBitmap(HInstance, SCA_APP_BMP_RES);
  Result := GBrandingHBmp;
end;

procedure RegisterSplashScreen;
// Erscheint waehrend des IDE-Starts unter "Loaded plugins" im Splash.
// HBITMAP = 0: kein Icon - der Eintrag wird trotzdem als Text gerendert.
begin
  if not Assigned(SplashScreenServices) then Exit;
  SplashScreenServices.AddPluginBitmap(
    PLUGIN_TITLE + ' ' + PLUGIN_VERSION,
    BrandingHBitmap,
    False,         // IsUnregistered
    PLUGIN_LICENSE,
    '');           // SKUBuild
end;

procedure RegisterAboutBox;
// Eintrag unter Help -> About -> Plugins.
var
  Svc : IOTAAboutBoxServices;
begin
  if not Supports(BorlandIDEServices, IOTAAboutBoxServices, Svc) then Exit;
  GAboutBoxIndex := Svc.AddPluginInfo(
    PLUGIN_TITLE + ' ' + PLUGIN_VERSION,
    PLUGIN_DESC,
    BrandingHBitmap,
    False,
    PLUGIN_LICENSE,
    '');
end;

procedure UnregisterAboutBox;
var
  Svc : IOTAAboutBoxServices;
begin
  if (GAboutBoxIndex >= 0)
     and Supports(BorlandIDEServices, IOTAAboutBoxServices, Svc) then
    Svc.RemovePluginInfo(GAboutBoxIndex);
  GAboutBoxIndex := -1;
end;

// ---------------------------------------------------------------------------
// Tools-Menu-Eintrag mit Icon
// ---------------------------------------------------------------------------

function FindIDEToolsMenu(MainMenu: TMainMenu): TMenuItem;
// Suche rekursiv nach dem ToolsMenu-Item im IDE-Hauptmenue. Embarcadero
// benennt es 'ToolsMenu' (siehe OTAPI-Docs Kap. 15). Fallback bei sehr
// alten Delphi-Versionen: name='Tools1Item' o.ae. - im Zweifel via
// Top-Level-Walk nach Caption '&Tools'.
var
  i : Integer;
  M : TMenuItem;

  function WalkSub(AParent: TMenuItem): TMenuItem;
  var
    k : Integer;
  begin
    Result := nil;
    for k := 0 to AParent.Count - 1 do
    begin
      if SameText(AParent[k].Name, 'ToolsMenu') then Exit(AParent[k]);
      Result := WalkSub(AParent[k]);
      if Result <> nil then Exit;
    end;
  end;

begin
  Result := nil;
  if not Assigned(MainMenu) then Exit;
  // Erste Welle: rekursiver Name-Match auf 'ToolsMenu'.
  for i := 0 to MainMenu.Items.Count - 1 do
  begin
    M := MainMenu.Items[i];
    if SameText(M.Name, 'ToolsMenu') then Exit(M);
    Result := WalkSub(M);
    if Result <> nil then Exit;
  end;
  // Fallback: Top-Level nach Caption '&Tools' / 'Tools' suchen.
  for i := 0 to MainMenu.Items.Count - 1 do
  begin
    M := MainMenu.Items[i];
    if SameText(M.Caption, '&Tools') or SameText(M.Caption, 'Tools') then
      Exit(M);
  end;
end;

procedure RegisterToolsMenuItem;
// 1) BMP-Resource laden + in TImageList -> INTAServices.AddImages liefert
//    den IDE-globalen ImageIndex.
// 2) TAction mit OnExecute + ImageIndex erzeugen.
// 3) TMenuItem mit der Action ans Ende des ToolsMenu haengen.
// Fehlerpfade still: wenn AddImages oder FindIDEToolsMenu nichts liefert,
// kein Menue-Eintrag - das Plugin bleibt aber ueber den Splash erreichbar.
var
  NTAS       : INTAServices;
  IL         : TImageList;
  BM         : TBitmap;
  ImageIndex : Integer;
  ToolsMenu  : TMenuItem;
begin
  if not Supports(BorlandIDEServices, INTAServices, NTAS) then Exit;
  ToolsMenu := FindIDEToolsMenu(NTAS.MainMenu);
  if not Assigned(ToolsMenu) then Exit;

  ImageIndex := -1;
  // ImageList nur als Transport-Vehikel - AddImages kopiert intern.
  IL := TImageList.Create(nil);
  try
    BM := TBitmap.Create;
    try
      try
        BM.LoadFromResourceName(HInstance, SCA_APP_BMP16_RES);
        // clWhite -> transparent (24-bit BMP hat keinen Alpha-Channel,
        // wir mappen den weissen Hintergrund per Mask zu Transparenz).
        IL.AddMasked(BM, clWhite);
        ImageIndex := NTAS.AddImages(IL);
      except
        // Resource-Load oder AddImages fehlgeschlagen - ImageIndex bleibt
        // -1, MenuItem laeuft ohne Icon (immer noch besser als kein Eintrag).
      end;
    finally
      BM.Free;
    end;
  finally
    IL.Free;
  end;

  // TAction in der IDE-eigenen ActionList registrieren (Wichtig - sonst
  // gilt der ShortCut-Code nicht und das ImageIndex-Mapping greift nicht).
  // OnExecute ist TNotifyEvent (procedure of object) - braucht eine
  // Methode an einer Instanz, nicht eine freie Prozedur. Daher der
  // GToolsHandler-Wrapper.
  if GToolsHandler = nil then
    GToolsHandler := TToolsMenuHandler.Create;
  GToolsAction := TAction.Create(nil);
  GToolsAction.ActionList := NTAS.ActionList;
  GToolsAction.Caption    := PLUGIN_TITLE;
  GToolsAction.OnExecute  := GToolsHandler.MenuClick;
  GToolsAction.Hint       := PLUGIN_DESC;
  GToolsAction.Category   := 'SCA';
  if ImageIndex >= 0 then
    GToolsAction.ImageIndex := ImageIndex;

  GToolsMenuItem := TMenuItem.Create(NTAS.MainMenu);
  GToolsMenuItem.Action := GToolsAction;
  GToolsMenuItem.Name   := 'SCAToolsMenuItem';
  ToolsMenu.Add(GToolsMenuItem);
end;

procedure UnregisterToolsMenuItem;
// MenuItem zuerst (sonst Dangling-Reference im IDE-Menue), dann Action,
// dann Handler. Action darf NUR freigegeben werden NACHDEM MenuItem keine
// Referenz mehr haelt - sonst AV beim naechsten IDE-Repaint.
begin
  if Assigned(GToolsMenuItem) then
  begin
    GToolsMenuItem.Free;        // entfernt aus dem Parent automatisch
    GToolsMenuItem := nil;
  end;
  if Assigned(GToolsAction) then
  begin
    GToolsAction.Free;
    GToolsAction := nil;
  end;
  if Assigned(GToolsHandler) then
  begin
    GToolsHandler.Free;
    GToolsHandler := nil;
  end;
end;

procedure Register;
begin
  RegisterAnalyserDockableForm;
  RegisterPackageWizard(TStaticCodeAnalyserExpert.Create);
  RegisterAboutBox;
  RegisterToolsMenuItem;
end;

{ TStaticCodeAnalyserExpert }

destructor TStaticCodeAnalyserExpert.Destroy;
begin
  UnregisterAnalyserDockableForm;
  inherited;
end;

function TStaticCodeAnalyserExpert.GetIDString: string;
begin
  Result := 'StaticCodeAnalyser';
end;

function TStaticCodeAnalyserExpert.GetName: string;
begin
  Result := 'Static Code Analysis';
end;

function TStaticCodeAnalyserExpert.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

procedure TStaticCodeAnalyserExpert.Execute;
begin
  ShowAnalyserDockableForm;
end;

initialization
  // Splash-Screen-Eintrag: muss in initialization stehen, NICHT in Register -
  // Register feuert nach Komponenten-Registrierung, da ist der Splash i.d.R.
  // schon weg. initialization feuert beim BPL-Load - bei "Load on Startup"-
  // Packages waehrend der IDE-Start-Sequenz, also rechtzeitig fuer den Splash.
  RegisterSplashScreen;

finalization
  // Tools-Menue zuerst (haengt vom Action ab, das die IDE bei UnregisterAboutBox
  // noch nicht beruehrt - aber Reihenfolge schadet nicht).
  UnregisterToolsMenuItem;
  UnregisterAboutBox;
  // Branding-HBITMAP erst NACH Unregister freigeben - die IDE haelt das
  // Handle waehrend des AboutBox/Splash-Lifecycle.
  if GBrandingHBmp <> 0 then
  begin
    DeleteObject(GBrandingHBmp);
    GBrandingHBmp := 0;
  end;
end.

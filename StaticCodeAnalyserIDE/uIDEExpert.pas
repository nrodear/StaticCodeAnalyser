unit uIDEExpert;

// Delphi IDE Expert: registriert "Static Code Analysis Tool for Delphi" im Tools-Menü
// + Splash-Screen-Eintrag waehrend IDE-Start + Help -> About-Eintrag.

interface

uses
  ToolsAPI;

type
  TStaticCodeAnalyserExpert = class(TNotifierObject, IOTAWizard, IOTAMenuWizard)
  public
    destructor Destroy; override;
    { IOTAWizard }
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;
    { IOTAMenuWizard }
    function GetMenuText: string;
  end;

procedure Register;

implementation

uses
  Winapi.Windows, System.SysUtils,
  uIDEAnalyserForm;

const
  PLUGIN_TITLE   = 'Static Code Analysis';
  PLUGIN_DESC    = 'Static Code Analysis Tool for Delphi - findings, ' +
                   'metrics, leak detection, Sonar export.';
  PLUGIN_VERSION = 'v0.9.1';
  PLUGIN_LICENSE = 'Freeware / Open Source';

  // Resource-Name aus branding\sca_branding.rc (BITMAP-Type).
  SCA_APP_BMP_RES = 'SCA_APP_BMP';

var
  // Index in der About-Box; gebraucht zum Unregister beim BPL-Unload.
  // -1 = nicht registriert (z.B. wenn IDE keine AboutBoxServices liefert).
  GAboutBoxIndex : Integer = -1;
  // Branding-HBITMAP aus sca_branding.res, gecached fuer BPL-Laufzeit.
  // 0 = nicht geladen (Resource fehlt oder LoadBitmap failed). Lebensdauer
  // an die BPL gekoppelt - die IDE haelt das Handle waehrend Splash + About-
  // Box, ein verfruehter DeleteObject wuerde dangling references erzeugen.
  GBrandingHBmp  : HBITMAP = 0;

function BrandingHBitmap: HBITMAP;
// Canonical Embarcadero-Pattern (siehe Embarcadero OTAPI-Docs Kap. 9):
// LoadBitmap(HInstance, '<resname>') liefert HBITMAP direkt aus der
// BITMAP-Resource. Null wenn Resource fehlt - dann fallen Splash/About
// auf Text-only zurueck.
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
// Eintrag unter Help -> About -> Plugins. Index merken um beim BPL-Unload
// sauber UnregisterAboutBox aufzurufen (sonst Dangling-Eintrag bis IDE-Neustart).
var
  Svc : IOTAAboutBoxServices;
begin
  if not Supports(BorlandIDEServices, IOTAAboutBoxServices, Svc) then Exit;
  GAboutBoxIndex := Svc.AddPluginInfo(
    PLUGIN_TITLE + ' ' + PLUGIN_VERSION,
    PLUGIN_DESC,
    BrandingHBitmap,
    False,         // IsUnregistered
    PLUGIN_LICENSE,
    '');           // SKUBuild
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

procedure Register;
begin
  RegisterAnalyserDockableForm;
  RegisterPackageWizard(TStaticCodeAnalyserExpert.Create);
  RegisterAboutBox;
end;

{ TStaticCodeAnalyserExpert }

destructor TStaticCodeAnalyserExpert.Destroy;
begin
  UnregisterAnalyserDockableForm;
  inherited;
end;

function TStaticCodeAnalyserExpert.GetIDString: string;
begin
  Result := 'StaticCodeAnalyser' ;
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

function TStaticCodeAnalyserExpert.GetMenuText: string;
begin
  Result := 'Static Code Analysis';
end;

initialization
  // Splash-Screen-Eintrag: muss in initialization stehen, NICHT in Register -
  // Register feuert nach Komponenten-Registrierung, da ist der Splash i.d.R.
  // schon weg. initialization feuert beim BPL-Load - bei "Load on Startup"-
  // Packages waehrend der IDE-Start-Sequenz, also rechtzeitig fuer den Splash.
  RegisterSplashScreen;

finalization
  // About-Box-Eintrag entfernen wenn der Plugin-BPL entladen wird
  // (z.B. ueber Component -> Install Packages -> Remove).
  UnregisterAboutBox;
  // Branding-HBITMAP erst NACH Unregister freigeben - die IDE haelt das
  // Handle waehrend des AboutBox/Splash-Lifecycle.
  if GBrandingHBmp <> 0 then
  begin
    DeleteObject(GBrandingHBmp);
    GBrandingHBmp := 0;
  end;
end.

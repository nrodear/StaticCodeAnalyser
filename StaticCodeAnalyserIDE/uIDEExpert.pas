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
  Winapi.Windows, System.SysUtils, uIDEAnalyserForm;

const
  PLUGIN_TITLE   = 'Static Code Analysis';
  PLUGIN_DESC    = 'Static Code Analysis Tool for Delphi - findings, ' +
                   'metrics, leak detection, Sonar export.';
  PLUGIN_VERSION = 'v0.9.1';
  PLUGIN_LICENSE = 'Freeware / Open Source';

var
  // Index in der About-Box; gebraucht zum Unregister beim BPL-Unload.
  // -1 = nicht registriert (z.B. wenn IDE keine AboutBoxServices liefert).
  GAboutBoxIndex : Integer = -1;

procedure RegisterSplashScreen;
// Erscheint waehrend des IDE-Starts unter "Loaded plugins" im Splash.
// HBITMAP = 0: kein Icon - der Eintrag wird trotzdem als Text gerendert.
// Spaeter kann eine 24x24 BMP-Resource via {$R} + LoadBitmap(HInstance, ...)
// nachgereicht werden, dann statt 0 das Handle uebergeben.
begin
  if not Assigned(SplashScreenServices) then Exit;
  SplashScreenServices.AddPluginBitmap(
    PLUGIN_TITLE + ' ' + PLUGIN_VERSION,
    0,             // hBitmap - 0 = text-only Eintrag
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
    0,             // hBitmap
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
end.

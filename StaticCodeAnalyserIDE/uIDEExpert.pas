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
  Winapi.Windows, System.SysUtils, Vcl.Graphics,
  uIDEAnalyserForm, uBrandingImage;

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
  // Branding-Bitmap aus sca_branding.rc gecached fuer die gesamte BPL-Laufzeit.
  // Die IDE referenziert das HBITMAP-Handle - wenn wir die TBitmap zu frueh
  // freigeben koennte das Handle ungueltig werden (Verhalten ist API-doku-
  // unklar zwischen Delphi-Versionen). Lifetime an die BPL koppeln ist
  // safe, kostet ~80 KB Speicher.
  GBrandingBmp   : Vcl.Graphics.TBitmap = nil;

function BrandingBitmap: Vcl.Graphics.TBitmap;
// Lazy-Load. Fallback nil -> Aufrufer uebergeben hBitmap=0 fuer text-only.
begin
  if GBrandingBmp = nil then
  begin
    try
      GBrandingBmp := uBrandingImage.LoadSCABitmap;
    except
      // Resource fehlt / PNG-Decoder-Mismatch - kein Splash/AboutBox-Icon,
      // aber kein Plugin-Crash.
      GBrandingBmp := nil;
    end;
  end;
  Result := GBrandingBmp;
end;

procedure RegisterSplashScreen;
// Erscheint waehrend des IDE-Starts unter "Loaded plugins" im Splash.
// HBITMAP = 0: kein Icon - der Eintrag wird trotzdem als Text gerendert.
var
  Bmp  : Vcl.Graphics.TBitmap;
  HBmp : HBITMAP;
begin
  if not Assigned(SplashScreenServices) then Exit;
  Bmp  := BrandingBitmap;
  if Assigned(Bmp) then HBmp := Bmp.Handle else HBmp := 0;
  SplashScreenServices.AddPluginBitmap(
    PLUGIN_TITLE + ' ' + PLUGIN_VERSION,
    HBmp,
    False,         // IsUnregistered
    PLUGIN_LICENSE,
    '');           // SKUBuild
end;

procedure RegisterAboutBox;
// Eintrag unter Help -> About -> Plugins. Index merken um beim BPL-Unload
// sauber UnregisterAboutBox aufzurufen (sonst Dangling-Eintrag bis IDE-Neustart).
var
  Svc  : IOTAAboutBoxServices;
  Bmp  : Vcl.Graphics.TBitmap;
  HBmp : HBITMAP;
begin
  if not Supports(BorlandIDEServices, IOTAAboutBoxServices, Svc) then Exit;
  Bmp  := BrandingBitmap;
  if Assigned(Bmp) then HBmp := Bmp.Handle else HBmp := 0;
  GAboutBoxIndex := Svc.AddPluginInfo(
    PLUGIN_TITLE + ' ' + PLUGIN_VERSION,
    PLUGIN_DESC,
    HBmp,
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
  // Branding-Bitmap erst NACH Unregister freigeben - die IDE haelt das
  // HBITMAP-Handle waehrend des AboutBox/Splash-Lifecycle.
  FreeAndNil(GBrandingBmp);
end.

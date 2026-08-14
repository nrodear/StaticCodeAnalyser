; =============================================================================
; StaticCodeAnalyserSetup.iss  —  Inno Setup 6.x, Installer P1 (nur D12-Schiene)
; Referenz: Welle 1, 2026-07-25
; Grundlage: Doku_05_IDE_Plugin.md (Installer-Abschnitt) + Konzept_IdePluginInstaller_2026-07-23
;
; Leitplanken (aus der Doku, bindend):
;   * Per-User: HKCU + %LOCALAPPDATA%\Programs\StaticCodeAnalyser — NIE elevieren
;     (elevated wuerde HKCU in den Admin-Hive schreiben).
;   * "Known Packages" (NICHT "Known IDE Packages"/"Experts"); Wertdaten NIE leer
;     (leere Wertdaten = Package laedt nicht).
;   * Deinstallation: Registry-Werte VOR den Dateien entfernen.
;   * Privacy ist Existenzgrund: der Installer baut KEINE Netzverbindung auf —
;     kein Update-Check, keine Telemetrie, kein Download. Dieses Skript enthaelt
;     bewusst keinerlei Netz-Funktionalitaet.
;   * D12 = BDS 23.0 (Win32-IDE). D13 = BDS 37.0 (geblockt, s. Platzhalter unten).
; =============================================================================

; --- Versionsstand ------------------------------------------------------------
; SECHS Stellen tragen die Version, alle muessen zusammenpassen:
;   uSCAConsts.SCA_VERSION + SCA_VERSION_FULL
;   rules/sca-rules.json  ->  tool.version
;   StaticCodeAnalyser.d12.dproj      VerInfo_Keys + VerInfo_Release
;   StaticCodeAnalyser.IDE.d12.dproj  VerInfo_Keys + VerInfo_Release
;   uIDEExpert.PLUGIN_VERSION  (Titel im IDE-Fenster)
;   diese Datei
; Der frueher hier vermerkte Drift ist behoben: seit 0.9.10 stimmen die
; numerischen VerInfo-Felder mit dem Keys-String ueberein (sie standen
; seit 0.9.4 auf 0/9/4, waehrend der String etwas anderes behauptete),
; und seit 0.9.11 ist auch PLUGIN_VERSION nachgezogen - die stand zwei
; Releases zurueck.
; Ueberschreibbar per ISCC /DSCAVersion=x.y.z.0 - package-release.ps1 setzt
; die Version zentral, der Default hier dient nur dem Hand-Compile.
#ifndef SCAVersion
  #define SCAVersion    "0.9.16.0"
#endif
#define SCAAppName      "Static Code Analyser for Delphi (IDE-Plugin)"
#define SCAPublisher    "StaticCodeAnalyser"

; --- Community-Buttons unten links im Wizard (Vorbild: Inno-Setup-eigener
; Installer). Klick oeffnet den STANDARD-BROWSER - rein nutzerinitiiert,
; das Privacy-Gate (kein automatischer Netzzugriff des Setups) bleibt
; unberuehrt. SCADonateUrl leer = Donate-Button erscheint nicht (die
; PayPal-Adresse ist ein User-Entscheid; per /DSCADonateUrl=... setzbar).
#ifndef SCADonateUrl
  #define SCADonateUrl ""
#endif
#define SCAGitHubUrl    "https://github.com/nrodear/StaticCodeAnalyser"

; --- Quell-BPLs ---------------------------------------------------------------
; RELEASE-ZIEL laut Konzept P1: Monolith-BPL "StaticCodeAnalyser.Plugin.d12.bpl"
; (requires nur rtl/vcl/vclwinx/designide/xmlrtl). Diese dpk existiert im Repo
; NOCH NICHT — im Repo existiert aktuell nur der Dev-3-Package-Satz:
;   StaticCodeAnalyserIDE\StaticCodeAnalyser.IDE.d12.dproj
;     -> MainSource StaticCodeAnalyser.IDE.d12.dpk
;     -> BPL:  StaticCodeAnalyser.IDE.d12.bpl
;     -> requires: rtl, vcl, vclwinx, designide, SCA.Engine, SCA.SharedUI
;   SCA.Engine\SCA.Engine.dpk          -> SCA.Engine.bpl
;   SCA.SharedUI\SCA.SharedUI.dpk      -> SCA.SharedUI.bpl
; Die dproj setzt KEIN DCC_BplOutput -> BPLs landen im D12-Standard-BPL-Ordner
; (C:\Users\Public\Documents\Embarcadero\Studio\23.0\Bpl).
;
; Umschalter: seit 2026-08-14 existiert die Monolith-dpk im Repo
; (StaticCodeAnalyserIDE\StaticCodeAnalyser.Plugin.d12.dpk) - SCA_MONOLITH
; ist damit der Release-Default: es wird NUR die eine BPL installiert.
; Fuer die Dev-3-BPL-Uebergangsvariante per ISCC-Kommandozeile ohne dieses
; Define bauen (Zeile auskommentieren).
#define SCA_MONOLITH

; Quellordner der gebauten BPLs (Build-Maschine; per ISCC /D ueberschreibbar):
;   iscc /DSCABplSourceDir="D:\pfad\zu\bpls" StaticCodeAnalyserSetup.iss
#ifndef SCABplSourceDir
  #define SCABplSourceDir "C:\Users\Public\Documents\Embarcadero\Studio\23.0\Bpl"
#endif

; Repo-Wurzel fuer Beilagen (Regelkatalog):
#ifndef SCARepoRoot
  #define SCARepoRoot "..\"
#endif

#ifdef SCA_MONOLITH
  #define SCAPluginBpl "StaticCodeAnalyser.Plugin.d12.bpl"
#else
  #define SCAPluginBpl "StaticCodeAnalyser.IDE.d12.bpl"
#endif

; BDS-Registry-Schluessel D12 (HKCU):
#define BDS23Key        "Software\Embarcadero\BDS\23.0"
#define KnownPackages23 BDS23Key + "\Known Packages"
#define DisabledPkgs23  BDS23Key + "\Disabled Packages"

[Setup]
AppId={{7C1B3A52-9E44-4B7D-A0F3-5D2C8E6F1B90}
AppName={#SCAAppName}
AppVersion={#SCAVersion}
AppPublisher={#SCAPublisher}
; Per-User laut Konzept: %LOCALAPPDATA%\Programs\StaticCodeAnalyser
; (ANNAHME Welle 1, 2026-07-25: Konzept-Layout {localappdata}\Programs gewinnt
;  gegenueber der Kurzform "{userappdata}" aus dem Auftrag — das Konzept ist
;  mehrfach verifiziert und {userappdata} waere Roaming-APPDATA.)
DefaultDirName={localappdata}\Programs\StaticCodeAnalyser
DisableProgramGroupPage=yes
; NIE elevieren (HKCU-Schreibziel!):
PrivilegesRequired=lowest
OutputBaseFilename=StaticCodeAnalyserSetup-{#SCAVersion}
Compression=lzma2
SolidCompression=yes
; Nur Windows, 32/64-Bit-OS egal (BPL selbst ist Win32 fuer die D12-Win32-IDE):
ArchitecturesAllowed=x86compatible x64compatible
UninstallDisplayName={#SCAAppName}
UninstallDisplayIcon={app}\bpl\d12\{#SCAPluginBpl}
; Kein Neustart noetig; IDE-Prozess-Check passiert im [Code]-Teil:
CloseApplications=no
; Sprachauswahl IMMER anbieten (Nutzer-Feedback 2026-08-15: bei englischer
; Windows-Anzeigesprache kam der Wizard stumm englisch; deutsche Nutzer mit
; en-Windows sind in der Delphi-Welt haeufig - fragen statt raten):
ShowLanguageDialog=yes

[Languages]
; de + en laut Konzept P3 (P1 liefert das Geruest schon mit):
Name: "de"; MessagesFile: "compiler:Languages\German.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
; Privacy-Zusicherung sichtbar im Setup (Doku: EULA + Installer-UI sichern das zu):
de.PrivacyNote=Dieses Setup und das Plugin bauen niemals Netzwerkverbindungen auf: kein Update-Check, keine Telemetrie, kein AI/LLM-Egress.
en.PrivacyNote=This setup and the plugin never open network connections: no update check, no telemetry, no AI/LLM egress.
de.IdeRunning=Die Delphi-12-IDE (bds.exe, BDS 23.0) scheint zu laufen. Bitte alle Delphi-12-Instanzen schliessen und das Setup erneut starten.
en.IdeRunning=The Delphi 12 IDE (bds.exe, BDS 23.0) appears to be running. Please close all Delphi 12 instances and restart setup.
de.DevBplWarn=In "Known Packages" (BDS 23.0) ist bereits eine Entwickler-Registrierung des Plugins mit anderem Pfad eingetragen:%n%n%1%n%nDer Eintrag wird durch die Installations-Registrierung ersetzt (Koexistenz-Schutz, verhindert Doppel-Laden).
en.DevBplWarn=A developer registration of the plugin with a different path already exists in "Known Packages" (BDS 23.0):%n%n%1%n%nIt will be replaced by the installed registration (coexistence guard, prevents double loading).
de.DonateBtn=PayPal-Spende
en.DonateBtn=PayPal Donate
de.StarBtn=Stern auf GitHub
en.StarBtn=Star on GitHub

[Messages]
; Privacy-Hinweis auf der Willkommensseite ergaenzen:
de.WelcomeLabel2=%n[name/ver] wird auf Ihrem Computer installiert (nur fuer den aktuellen Benutzer, ohne Administratorrechte).%n%nDieses Setup und das Plugin bauen niemals Netzwerkverbindungen auf: kein Update-Check, keine Telemetrie, kein AI/LLM-Egress.
en.WelcomeLabel2=%nThis will install [name/ver] on your computer (current user only, no administrator rights).%n%nThis setup and the plugin never open network connections: no update check, no telemetry, no AI/LLM egress.

[Files]
; --- D12-BPL(s) ---------------------------------------------------------------
#ifdef SCA_MONOLITH
; Release-Variante: EINE Monolith-BPL — loest laut Doku PATH-, Kollisions-,
; Koexistenz- und Portable-Problem gleichzeitig (requires nur IDE-eigene Pakete,
; die der Loader im bds.exe-Verzeichnis findet).
Source: "{#SCABplSourceDir}\{#SCAPluginBpl}"; DestDir: "{app}\bpl\d12"; Flags: ignoreversion
#else
; Dev-3-BPL-Variante (aktueller Repo-Stand). WICHTIG (Doku-Lehre): der Windows-
; Loader loest requires per Modulname ueber bds.exe-Dir -> System32 -> PATH,
; NICHT im BPL-Verzeichnis. Deshalb werden SCA.Engine/SCA.SharedUI ebenfalls in
; "Known Packages" registriert (volle Pfade): die IDE laedt sie dann selbst,
; und bereits geladene Module loest der Loader per Modulname auf. Die
; Registry-Enumeration liefert die Werte pfad-alphabetisch, "...\SCA.*" kommt
; vor "...\StaticCodeAnalyser.*" — die Abhaengigkeiten sind also zuerst da.
; Das ist eine dokumentierte Uebergangsloesung bis zur Monolith-BPL (P1-Ziel).
Source: "{#SCABplSourceDir}\SCA.Engine.bpl";   DestDir: "{app}\bpl\d12"; Flags: ignoreversion
Source: "{#SCABplSourceDir}\SCA.SharedUI.bpl"; DestDir: "{app}\bpl\d12"; Flags: ignoreversion
Source: "{#SCABplSourceDir}\{#SCAPluginBpl}";  DestDir: "{app}\bpl\d12"; Flags: ignoreversion
#endif

; --- Regelkatalog -------------------------------------------------------------
; Doku Punkt 10: FindJsonFile-Pfad 3 (Install-Verzeichnis) gewinnt vor Pfad 4
; (APPDATA); der Installer ueberschreibt rules\sca-rules.json bei Updates.
Source: "{#SCARepoRoot}rules\sca-rules.json"; DestDir: "{app}\rules"; Flags: ignoreversion

[Registry]
; HKCU-Registrierung fuer die D12-IDE (BDS 23.0, Win32).
; Wertname = voller BPL-Pfad, Wertdaten = Beschreibung (NIE leer!).
; uninsdeletevalue: Inno deinstalliert in umgekehrter Installationsreihenfolge,
; d.h. diese Registry-Werte verschwinden VOR den Dateien (Doku-Grundsatz);
; zusaetzlich raeumt CurUninstallStepChanged (usUninstall) als Gurt+Hosentraeger.
#ifndef SCA_MONOLITH
Root: HKCU; Subkey: "{#KnownPackages23}"; ValueType: string; \
  ValueName: "{app}\bpl\d12\SCA.Engine.bpl"; \
  ValueData: "Static Code Analyser - Engine"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "{#KnownPackages23}"; ValueType: string; \
  ValueName: "{app}\bpl\d12\SCA.SharedUI.bpl"; \
  ValueData: "Static Code Analyser - Shared UI"; Flags: uninsdeletevalue
#endif
Root: HKCU; Subkey: "{#KnownPackages23}"; ValueType: string; \
  ValueName: "{app}\bpl\d12\{#SCAPluginBpl}"; \
  ValueData: "Static Code Analyser for Delphi (IDE-Plugin)"; Flags: uninsdeletevalue

; =============================================================================
; --- D13-PLATZHALTER (GEBLOCKT: kein Delphi 13 auf der Build-Maschine) --------
; D13 "Florence" = BDS 37.0 (Nummernsprung 23.0 -> 37.0 ist real, NIE rechnen),
; Package-Suffix 370, Win32 + Win64-IDE. Fuer die 64-bit-IDE gilt:
;   * 32-bit-BPL laedt NIE in der 64-bit-IDE -> eigene Win64-BPL noetig.
;   * Registrierung unter "Known Packages x64" (64-bit-Erkennung via "App x64").
; Aktivierung erst nach P2 (.d13-Projektsatz VER370, Win32+Win64-Builds,
; Pflicht-Smoke uIDEAnnotationOverlay + Tools-Menue-Suche).
;
;#define BDS37Key           "Software\Embarcadero\BDS\37.0"
;#define KnownPackages37    BDS37Key + "\Known Packages"
;#define KnownPackages37x64 BDS37Key + "\Known Packages x64"
;
;[Files]  (in obige Sektion integrieren, Components-gesteuert d13/d13x64)
;Source: "{#SCABplSourceDir}\StaticCodeAnalyser.Plugin.d13.bpl";  DestDir: "{app}\bpl\d13";    Flags: ignoreversion
;Source: "{#SCABplSourceDir}\StaticCodeAnalyser.Plugin.d13x64.bpl"; DestDir: "{app}\bpl\d13x64"; Flags: ignoreversion
;
;[Registry]  (in obige Sektion integrieren)
;Root: HKCU; Subkey: "{#KnownPackages37}"; ValueType: string; \
;  ValueName: "{app}\bpl\d13\StaticCodeAnalyser.Plugin.d13.bpl"; \
;  ValueData: "Static Code Analyser for Delphi (IDE-Plugin)"; Flags: uninsdeletevalue
;Root: HKCU; Subkey: "{#KnownPackages37x64}"; ValueType: string; \
;  ValueName: "{app}\bpl\d13x64\StaticCodeAnalyser.Plugin.d13x64.bpl"; \
;  ValueData: "Static Code Analyser for Delphi (IDE-Plugin)"; Flags: uninsdeletevalue
; =============================================================================

[Code]
// ---------------------------------------------------------------------------
// Welle 1, 2026-07-25 — [Code]-Teil: IDE-Prozess-Check, Koexistenz-Check gegen
// Dev-BPLs, Disabled-Packages-Bereinigung, Uninstall-Reihenfolge.
// KEINERLEI Netzwerkzugriff (Privacy-Gate).
// ---------------------------------------------------------------------------

const
  KNOWN_PACKAGES_23    = 'Software\Embarcadero\BDS\23.0\Known Packages';
  DISABLED_PACKAGES_23 = 'Software\Embarcadero\BDS\23.0\Disabled Packages';
  PLUGIN_BPL_NAME      = '{#SCAPluginBpl}';

// Laeuft die Delphi-12-IDE? Erkennung ueber das IDE-Hauptfenster (Klasse
// TAppBuilder) — bewusst ohne Prozess-APIs/WMI, bleibt lowest-privilege.
// Grenze: unterscheidet nicht zwischen BDS-Versionen; bei parallel laufendem
// D13 warnt der Check konservativ mit (akzeptiert fuer P1, nur D12-Schiene).
function IsDelphiIdeRunning: Boolean;
begin
  Result := FindWindowByClassName('TAppBuilder') <> 0;
end;

// Sammelt alle "Known Packages"-Wertnamen (= volle BPL-Pfade), die auf eine
// unserer BPL-Dateinamen enden, aber NICHT auf den Installationspfad zeigen.
// Das sind Dev-Registrierungen (Public-Documents-Bpl der Build-Maschine) —
// Koexistenz-Gefahr: dieselbe Package-Ident darf nicht doppelt laden.
procedure CollectForeignPluginEntries(const InstalledPath: string; Entries: TStringList);
var
  Names: TArrayOfString;
  I: Integer;
  N: string;
begin
  if RegGetValueNames(HKEY_CURRENT_USER, KNOWN_PACKAGES_23, Names) then
    for I := 0 to GetArrayLength(Names) - 1 do
    begin
      N := Names[I];
      if (CompareText(ExtractFileName(N), PLUGIN_BPL_NAME) = 0) and
         (CompareText(N, InstalledPath) <> 0) then
        Entries.Add(N);
    end;
end;

function InitializeSetup: Boolean;
begin
  Result := True;
  if IsDelphiIdeRunning then
  begin
    MsgBox(CustomMessage('IdeRunning'), mbError, MB_OK);
    Result := False;
  end;
end;

// ---------------------------------------------------------------------------
// Community-Buttons unten links (Vorbild: Inno-Setup-eigener Installer).
// ShellExecAsOriginalUser: oeffnet den Browser im Nutzerkontext - reiner
// Klick-Link, das Setup selbst baut weiterhin keine Verbindung auf.
// ---------------------------------------------------------------------------

procedure OpenCommunityUrl(const Url: string);
var
  ErrCode: Integer;
begin
  ShellExecAsOriginalUser('open', Url, '', '', SW_SHOWNORMAL, ewNoWait, ErrCode);
end;

procedure StarButtonClick(Sender: TObject);
begin
  OpenCommunityUrl('{#SCAGitHubUrl}');
end;

#if SCADonateUrl != ""
procedure DonateButtonClick(Sender: TObject);
begin
  OpenCommunityUrl('{#SCADonateUrl}');
end;
#endif

procedure InitializeWizard;
var
  Btn: TNewButton;
  NextLeft: Integer;
begin
  NextLeft := ScaleX(12);

#if SCADonateUrl != ""
  Btn := TNewButton.Create(WizardForm);
  Btn.Parent  := WizardForm;
  Btn.Left    := NextLeft;
  Btn.Top     := WizardForm.CancelButton.Top;
  Btn.Width   := ScaleX(100);
  Btn.Height  := WizardForm.CancelButton.Height;
  Btn.Caption := CustomMessage('DonateBtn');
  Btn.OnClick := @DonateButtonClick;
  NextLeft := Btn.Left + Btn.Width + ScaleX(8);
#endif

  Btn := TNewButton.Create(WizardForm);
  Btn.Parent  := WizardForm;
  Btn.Left    := NextLeft;
  Btn.Top     := WizardForm.CancelButton.Top;
  Btn.Width   := ScaleX(110);
  Btn.Height  := WizardForm.CancelButton.Height;
  Btn.Caption := CustomMessage('StarBtn');
  Btn.OnClick := @StarButtonClick;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  InstalledPath, N: string;
  Foreign: TStringList;
  I: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    InstalledPath := ExpandConstant('{app}\bpl\d12\') + PLUGIN_BPL_NAME;

    // 1) Koexistenz-Check: fremde (Dev-)Registrierungen derselben Plugin-BPL
    //    entfernen, damit die IDE die Package-Ident nicht doppelt laedt.
    Foreign := TStringList.Create;
    try
      CollectForeignPluginEntries(InstalledPath, Foreign);
      for I := 0 to Foreign.Count - 1 do
      begin
        N := Foreign[I];
        MsgBox(FmtMessage(CustomMessage('DevBplWarn'), [N]), mbInformation, MB_OK);
        RegDeleteValue(HKEY_CURRENT_USER, KNOWN_PACKAGES_23, N);
      end;
    finally
      Foreign.Free;
    end;

    // 2) Disabled-Packages-Bereinigung: hatte der User das Plugin frueher per
    //    "Can't load package -> Nein" deaktiviert (IDE-Selbstheilung), bliebe
    //    der Disabled-Eintrag bestehen und wuerde die frische Installation
    //    stumm blockieren.
    if RegValueExists(HKEY_CURRENT_USER, DISABLED_PACKAGES_23, InstalledPath) then
      RegDeleteValue(HKEY_CURRENT_USER, DISABLED_PACKAGES_23, InstalledPath);
  end;
end;

function InitializeUninstall: Boolean;
begin
  Result := True;
  if IsDelphiIdeRunning then
  begin
    MsgBox(CustomMessage('IdeRunning'), mbError, MB_OK);
    Result := False;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  InstalledPath: string;
begin
  // usUninstall feuert VOR dem Loeschen der Dateien -> hier raeumen wir die
  // Registry-Werte explizit (Doku-Grundsatz "Registry vor Dateien"), auch wenn
  // uninsdeletevalue dieselbe Reihenfolge bereits garantiert (Gurt+Hosentraeger,
  // deckt zudem manuell verschobene/duplizierte Eintraege ab).
  if CurUninstallStep = usUninstall then
  begin
    InstalledPath := ExpandConstant('{app}\bpl\d12\') + PLUGIN_BPL_NAME;
    RegDeleteValue(HKEY_CURRENT_USER, KNOWN_PACKAGES_23, InstalledPath);
    RegDeleteValue(HKEY_CURRENT_USER, DISABLED_PACKAGES_23, InstalledPath);
#ifndef SCA_MONOLITH
    RegDeleteValue(HKEY_CURRENT_USER, KNOWN_PACKAGES_23,
      ExpandConstant('{app}\bpl\d12\SCA.Engine.bpl'));
    RegDeleteValue(HKEY_CURRENT_USER, KNOWN_PACKAGES_23,
      ExpandConstant('{app}\bpl\d12\SCA.SharedUI.bpl'));
    RegDeleteValue(HKEY_CURRENT_USER, DISABLED_PACKAGES_23,
      ExpandConstant('{app}\bpl\d12\SCA.Engine.bpl'));
    RegDeleteValue(HKEY_CURRENT_USER, DISABLED_PACKAGES_23,
      ExpandConstant('{app}\bpl\d12\SCA.SharedUI.bpl'));
#endif
  end;
end;

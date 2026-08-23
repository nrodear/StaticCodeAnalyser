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
; unberuehrt. SCADonateUrl leer = Donate-Button erscheint nicht.
; PayPal-Adresse vom User festgelegt 2026-08-15 (siehe README_Installer).
#ifndef SCADonateUrl
  #define SCADonateUrl "https://paypal.me/nrodear"
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

; --- D12.3 64-bit-IDE (VORBEREITET, standardmaessig AUS) ---------------------
; Aktivieren mit ISCC /DSCA_D12_X64, sobald (a) eine Win64-DESIGN-BPL des
; Plugins gebaut ist (Plugin-dproj um die Win64-Plattform ergaenzen; braucht
; die 64-bit-Designzeit-Pakete aus D12.3) und (b) der Registry-Schluessel am
; Zielsystem VERIFIZIERT wurde. Merksaetze aus der D13-Recherche, die hier
; analog gelten: 32-bit-BPL laedt NIE in der 64-bit-IDE; Registrierung der
; 64-bit-IDE laeuft ueber "Known Packages x64"; Erkennung via Wert "App x64".
#ifdef SCA_D12_X64
  #define KnownPackages23x64 BDS23Key + "\Known Packages x64"
  #define DisabledPkgs23x64  BDS23Key + "\Disabled Packages x64"
  #ifndef SCABplSourceDirX64
    #define SCABplSourceDirX64 "C:\Users\Public\Documents\Embarcadero\Studio\23.0\Bpl\Win64"
  #endif
#endif

; --- Delphi 13 "Florence" = BDS 37.0 ------------------------------------------
; Der Nummernsprung 23.0 -> 37.0 ist real, NIE ausrechnen.
;
; D13 bringt ZWEI IDEs mit, und das ist der Grund fuer die zweite Schiene:
;   bin\bds.exe     32-bit  -> laedt nur Win32-BPLs, "Known Packages"
;   bin64\bds.exe   64-bit  -> laedt nur Win64-BPLs, "Known Packages x64"
; Am 2026-08-23 an der Installation gemessen: bin64\bds.exe vorhanden,
; 5 designide-Dateien in bin64, 48 dcl*-BPLs, designide.dcp fuer win64.
;
; ZUM VERGLEICH, damit niemand denselben Irrtum wiederholt: Delphi 12 hat
; KEINE 64-bit-IDE. Gleiche Messung unter 23.0: kein bin64\bds.exe, kein
; designide in bin64, kein designide.dcp fuer win64, null dcl*-BPLs. Der
; SCA_D12_X64-Block oben ist deshalb eine Vorwegnahme und bleibt
; ausgeschaltet - er laesst sich hier weder bauen noch pruefen.
#define SCA_D13
#define SCA_D13_X64

#ifdef SCA_D13
  #define BDS37Key        "Software\Embarcadero\BDS\37.0"
  #define KnownPackages37 BDS37Key + "\Known Packages"
  #define DisabledPkgs37  BDS37Key + "\Disabled Packages"
  ; Quellordner der D13-BPLs. Ein Projektsatz baut beide Generationen; die
  ; Generation steckt im Zielordner der IDE, nicht im Dateinamen - deshalb
  ; heisst die Monolith-BPL hier wie unter D12.
  #ifndef SCABplSourceDirD13
    #define SCABplSourceDirD13 "C:\Users\Public\Documents\Embarcadero\Studio\37.0\Bpl"
  #endif
#endif

#ifdef SCA_D13_X64
  #define KnownPackages37x64 BDS37Key + "\Known Packages x64"
  #define DisabledPkgs37x64  BDS37Key + "\Disabled Packages x64"
  #ifndef SCABplSourceDirD13X64
    #define SCABplSourceDirD13X64 "C:\Users\Public\Documents\Embarcadero\Studio\37.0\Bpl\Win64"
  #endif
#endif

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
; Lizenz-Seite: MIT (User-Entscheid 2026-08-15) - dieselbe Datei speist
; auch das GetIt-Paket (getit\...json, Feld License).
LicenseFile={#SCARepoRoot}LICENSE

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
de.NoDelphi12=Es wurde weder Delphi 12 (BDS 23.0) noch Delphi 13 (BDS 37.0) auf diesem System gefunden. Das Plugin unterstuetzt Delphi 12.0-12.3 (32-bit-IDE) sowie Delphi 13 (32- und 64-bit-IDE); aeltere Versionen werden nicht unterstuetzt. Das Setup wird beendet, es wird nichts installiert.
en.NoDelphi12=Neither Delphi 12 (BDS 23.0) nor Delphi 13 (BDS 37.0) was found on this system. The plugin supports Delphi 12.0-12.3 (32-bit IDE) and Delphi 13 (32-bit and 64-bit IDE); older versions are not supported. Setup will close without installing anything.
de.DevBplWarn=In "Known Packages" (BDS 23.0) ist bereits eine Entwickler-Registrierung des Plugins mit anderem Pfad eingetragen:%n%n%1%n%nDer Eintrag wird durch die Installations-Registrierung ersetzt (Koexistenz-Schutz, verhindert Doppel-Laden).
en.DevBplWarn=A developer registration of the plugin with a different path already exists in "Known Packages" (BDS 23.0):%n%n%1%n%nIt will be replaced by the installed registration (coexistence guard, prevents double loading).
de.DonateBtn=PayPal-Spende
en.DonateBtn=PayPal Donate
de.StarBtn=Stern auf GitHub
en.StarBtn=Star on GitHub
; Versions-Uebersicht auf der "Ready to Install"-Seite (Nutzerwunsch
; 2026-08-15; installierbare Version FETT via TRichEditViewer). Bewusst
; dieselben Aussagen wie die Matrix in README_Installer.md par.0 - bei
; Aenderungen BEIDE Stellen pflegen. Einzeilige Bausteine, der [Code]-Teil
; setzt sie zu RTF (fett) bzw. Plain-Text (Fallback-Memo) zusammen.
de.ReadyHead=Unterstuetzte Delphi-Versionen:
en.ReadyHead=Supported Delphi versions:
de.ReadyYes=Delphi 12.0 - 12.3 (32-bit-IDE)  -  JA, dieses Setup
en.ReadyYes=Delphi 12.0 - 12.3 (32-bit IDE)  -  YES, this setup
de.ReadyNo1=Delphi 12.3 (64-bit-IDE)  -  noch nicht (vorbereitet, braucht eigene Win64-BPL)
en.ReadyNo1=Delphi 12.3 (64-bit IDE)  -  not yet (prepared, needs its own Win64 BPL)
de.ReadyNo2=Delphi 13 "Florence"  -  noch nicht
en.ReadyNo2=Delphi 13 "Florence"  -  not yet
de.ReadyNo3=Delphi 11 und aelter  -  nicht unterstuetzt
en.ReadyNo3=Delphi 11 and older  -  not supported
de.ReadyNote=Hinweis: Fuer andere Delphi-IDE-Versionen bestehen derzeit keine Testmoeglichkeiten. Alternative: das Projekt von GitHub laden und die Packages selbst in der IDE bauen und installieren - Anleitung (HowTo_Build.md) im Repository:
en.ReadyNote=Note: there is currently no way for us to test on other Delphi IDE versions. Alternative: download the project from GitHub and build/install the packages yourself in the IDE - instructions (HowTo_Build.md) in the repository:

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
Source: "{#SCABplSourceDir}\{#SCAPluginBpl}"; DestDir: "{app}\bpl\d12"; \
  Flags: ignoreversion; Check: IsDelphi12Installed
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

#ifdef SCA_D12_X64
; D12.3-64-bit-IDE: eigene Win64-BPL in eigenen Ordner (gleicher Dateiname,
; anderer Build - Quellordner ist der Win64-BPL-Standardordner).
Source: "{#SCABplSourceDirX64}\{#SCAPluginBpl}"; DestDir: "{app}\bpl\d12x64"; Flags: ignoreversion
#endif

; --- D13-BPLs -----------------------------------------------------------------
; Check: nur schreiben, wenn die jeweilige IDE wirklich da ist. Ohne das
; landen Dateien und HKCU-Werte in einer toten BDS-Schiene - dieselbe
; Ueberlegung wie bei IsDelphi12Installed.
#ifdef SCA_D13
Source: "{#SCABplSourceDirD13}\{#SCAPluginBpl}"; DestDir: "{app}\bpl\d13"; \
  Flags: ignoreversion; Check: IsDelphi13Installed
#endif
#ifdef SCA_D13_X64
; Die 64-bit-IDE laedt NIE eine 32-bit-BPL. Eigener Build, eigener Ordner,
; gleicher Dateiname - unterschieden wird ueber den Pfad in der Registry.
Source: "{#SCABplSourceDirD13X64}\{#SCAPluginBpl}"; DestDir: "{app}\bpl\d13x64"; \
  Flags: ignoreversion; Check: IsDelphi13X64Available
#endif

; --- Regelkatalog -------------------------------------------------------------
; Doku Punkt 10: FindJsonFile-Pfad 3 (Install-Verzeichnis) gewinnt vor Pfad 4
; (APPDATA); der Installer ueberschreibt rules\sca-rules.json bei Updates.
Source: "{#SCARepoRoot}rules\sca-rules.json"; DestDir: "{app}\rules"; Flags: ignoreversion
; Sprach-Overlays: uebersetzte Regelnamen/-kurzbeschreibungen (de/fr).
; Fehlen sie, faellt die Anzeige still auf Englisch zurueck - deshalb
; installieren, nicht dem Zufall ueberlassen.
Source: "{#SCARepoRoot}rules\sca-rules.de.json"; DestDir: "{app}\rules"; Flags: ignoreversion
Source: "{#SCARepoRoot}rules\sca-rules.fr.json"; DestDir: "{app}\rules"; Flags: ignoreversion

[Icons]
; Sichtbarer Weg zum Deinstaller (Nutzerfrage 2026-08-15): den unins000.exe
; erzeugt Inno automatisch (+ Eintrag in Windows "Apps & Features"), aber ein
; IDE-Plugin hat keine startbare EXE und damit keinen natuerlichen Fundort -
; deshalb ein Startmenue-Eintrag. {userprograms}: per-user, kein Admin.
Name: "{userprograms}\Static Code Analyser for Delphi\Uninstall Static Code Analyser (IDE-Plugin)"; \
  Filename: "{uninstallexe}"

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
  ValueData: "Static Code Analyser for Delphi (IDE-Plugin)"; \
  Flags: uninsdeletevalue; Check: IsDelphi12Installed
#ifdef SCA_D12_X64
Root: HKCU; Subkey: "{#KnownPackages23x64}"; ValueType: string; \
  ValueName: "{app}\bpl\d12x64\{#SCAPluginBpl}"; \
  ValueData: "Static Code Analyser for Delphi (IDE-Plugin, 64-bit IDE)"; Flags: uninsdeletevalue
#endif

; --- D13 (BDS 37.0) -----------------------------------------------------------
#ifdef SCA_D13
Root: HKCU; Subkey: "{#KnownPackages37}"; ValueType: string; \
  ValueName: "{app}\bpl\d13\{#SCAPluginBpl}"; \
  ValueData: "Static Code Analyser for Delphi (IDE-Plugin)"; \
  Flags: uninsdeletevalue; Check: IsDelphi13Installed
#endif
#ifdef SCA_D13_X64
Root: HKCU; Subkey: "{#KnownPackages37x64}"; ValueType: string; \
  ValueName: "{app}\bpl\d13x64\{#SCAPluginBpl}"; \
  ValueData: "Static Code Analyser for Delphi (IDE-Plugin, 64-bit IDE)"; \
  Flags: uninsdeletevalue; Check: IsDelphi13X64Available
#endif

; =============================================================================
; --- D13-PLATZHALTER (wartet auf den Projektsatz, NICHT auf die IDE) ---------
; D13 "Florence" = BDS 37.0 (Nummernsprung 23.0 -> 37.0 ist real, NIE rechnen),
; Package-Suffix 370, Win32 + Win64-IDE. Fuer die 64-bit-IDE gilt:
;   * 32-bit-BPL laedt NIE in der 64-bit-IDE -> eigene Win64-BPL noetig.
;   * Registrierung unter "Known Packages x64" (64-bit-Erkennung via "App x64").
; RICHTIGSTELLUNG 2026-08-22: hier stand "kein Delphi 13 auf der
; Build-Maschine". Das ist falsch und war es vermutlich schon eine Weile -
; die Registry fuehrt HKCU\SOFTWARE\Embarcadero\BDS.0 mit RootDir
; Studio.0, Edition "Starter", "App x64" = bin64ds.exe und den
; Schluesseln "Known Packages" UND "Known Packages x64"; der Dev-BPL-Satz
; ist dort bereits fuer Win32 und Win64 gebaut. Der Blocker war ein
; Phantom, und drei weitere Dokumente haben ihre eigenen Blocker daraus
; abgeleitet.
; Was WIRKLICH fehlt, bevor dieser Block scharf gestellt wird: der
; Projektsatz-Entscheid (LIBSUFFIX AUTO gegen Versionssuffix im
; Dateinamen - heute traegt KEIN einziges dpk/dproj eine
; LIBSUFFIX-Direktive) und eine Win64-faehige Plugin-Projektdatei; das
; ausgelieferte Monolith-Paket steht auf TargetedPlatforms=1.
; Offen bleibt fuer den GetIt-Local-Package-Test allein die Edition
; "Starter" - ob die dafuer reicht, ist ungeprueft.
;
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
  KNOWN_PACKAGES_37    = 'Software\Embarcadero\BDS\37.0\Known Packages';
  DISABLED_PACKAGES_37 = 'Software\Embarcadero\BDS\37.0\Disabled Packages';
  KNOWN_PACKAGES_37X64 = 'Software\Embarcadero\BDS\37.0\Known Packages x64';
  DISABLED_PKGS_37X64  = 'Software\Embarcadero\BDS\37.0\Disabled Packages x64';
  PLUGIN_BPL_NAME      = '{#SCAPluginBpl}';

// Laeuft die Delphi-12-IDE? Erkennung ueber das IDE-Hauptfenster (Klasse
// TAppBuilder) — bewusst ohne Prozess-APIs/WMI, bleibt lowest-privilege.
// Grenze: unterscheidet nicht zwischen BDS-Versionen; bei parallel laufendem
// D13 warnt der Check konservativ mit (akzeptiert fuer P1, nur D12-Schiene).
function IsDelphiIdeRunning: Boolean;
begin
  Result := FindWindowByClassName('TAppBuilder') <> 0;
end;

// Ist die UNTERSTUETZTE IDE (Delphi 12 = BDS 23.0) ueberhaupt installiert?
// Ohne diesen Check wuerde das Setup auf einer Maschine ohne D12 stumm
// Dateien + HKCU-Werte in eine tote BDS-Schiene schreiben (Nutzerfrage
// 2026-08-15). Suchreihenfolge:
//   1. HKCU\Software\Embarcadero\BDS\23.0\RootDir - existiert, sobald die
//      IDE fuer diesen Benutzer einmal gestartet wurde.
//   2. HKLM\Software\Embarcadero\BDS\23.0\RootDir - der Installationseintrag
//      (32-bit-Setup-Prozess -> WOW6432Node-Sicht passt zur 32-bit-IDE).
// Zusaetzlich muss bin\bds.exe unter RootDir real existieren - ein
// Registry-Leichnam nach Deinstallation zaehlt nicht.
function IsDelphi12Installed: Boolean;
var
  RootDir: string;
begin
  Result := False;
  if not RegQueryStringValue(HKEY_CURRENT_USER,
       'Software\Embarcadero\BDS\23.0', 'RootDir', RootDir) then
    if not RegQueryStringValue(HKEY_LOCAL_MACHINE,
         'Software\Embarcadero\BDS\23.0', 'RootDir', RootDir) then
      Exit;
  Result := FileExists(AddBackslash(RootDir) + 'bin\bds.exe');
end;

// Wurzelverzeichnis einer BDS-Generation, oder '' wenn sie nicht da ist.
// Gleiche Suchreihenfolge und gleiche Begruendung wie oben.
function BdsRootDir(const Version: string): string;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER,
       'Software\Embarcadero\BDS\' + Version, 'RootDir', Result) then
    if not RegQueryStringValue(HKEY_LOCAL_MACHINE,
         'Software\Embarcadero\BDS\' + Version, 'RootDir', Result) then
      Result := '';
end;

// Ist Delphi 13 (BDS 37.0) installiert? Wie bei D12 zaehlt nur eine real
// vorhandene bin\bds.exe, nicht ein Registry-Leichnam.
function IsDelphi13Installed: Boolean;
var
  RootDir: string;
begin
  RootDir := BdsRootDir('37.0');
  Result := (RootDir <> '')
        and FileExists(AddBackslash(RootDir) + 'bin\bds.exe');
end;

// Hat diese Delphi-13-Installation auch die 64-bit-IDE?
// Sie ist eine eigene Datei (bin64\bds.exe) und kann fehlen - dann darf
// keine Win64-BPL registriert werden, sonst scheitert jeder IDE-Start an
// einem Paket, das niemand laden kann.
// Delphi 12 hat diese Datei GAR NICHT; darum gibt es hier bewusst kein
// Gegenstueck fuer 23.0 (2026-08-23 an beiden Installationen gemessen).
function IsDelphi13X64Available: Boolean;
var
  RootDir: string;
begin
  RootDir := BdsRootDir('37.0');
  Result := (RootDir <> '')
        and FileExists(AddBackslash(RootDir) + 'bin64\bds.exe');
end;

// Mindestens eine unterstuetzte IDE?
function IsAnySupportedIdeInstalled: Boolean;
begin
  Result := IsDelphi12Installed or IsDelphi13Installed;
end;

// Gehoert der BPL-Dateiname zur SCA-Familie? Im Monolith-Modus zaehlen
// auch die ALT-Registrierungen des Dev-3-Package-Satzes dazu: die
// Monolith-BPL enthaelt dieselben Units — bleibt ein alter
// SCA.Engine-/SCA.SharedUI-/IDE.d12-Eintrag stehen, wirft die IDE beim
// Start "enthaelt die Unit ..., die auch im Package ... enthalten ist"
// (2026-08-15 auf dem Zweit-PC real passiert, via GetIt-Install).
function IsScaFamilyBpl(const FileName: string): Boolean;
begin
  Result := (CompareText(FileName, PLUGIN_BPL_NAME) = 0)
#ifdef SCA_MONOLITH
    or (CompareText(FileName, 'StaticCodeAnalyser.IDE.d12.bpl') = 0)
    or (CompareText(FileName, 'SCA.Engine.bpl') = 0)
    or (CompareText(FileName, 'SCA.SharedUI.bpl') = 0)
#endif
  ;
end;

// Sammelt alle "Known Packages"-Wertnamen (= volle BPL-Pfade), die auf eine
// unserer BPL-Dateinamen enden, aber NICHT auf den Installationspfad zeigen.
// Das sind Dev-/Alt-Registrierungen (z.B. Public-Documents-Bpl) —
// Koexistenz-Gefahr: dieselbe Unit darf nicht doppelt laden.
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
      if IsScaFamilyBpl(ExtractFileName(N)) and
         (CompareText(N, InstalledPath) <> 0) then
        Entries.Add(N);
    end;
end;

function InitializeSetup: Boolean;
begin
  Result := True;
  // Reihenfolge: erst "ist eine unterstuetzte IDE da?", dann "laeuft sie?" -
  // die Nicht-installiert-Meldung ist die praezisere von beiden.
  // Seit 2026-08-23 reicht D12 ODER D13; welche Schienen tatsaechlich
  // beschrieben werden, entscheiden die Check:-Ausdruecke je Eintrag.
  if not IsAnySupportedIdeInstalled then
  begin
    MsgBox(CustomMessage('NoDelphi12'), mbError, MB_OK);
    Result := False;
    Exit;
  end;
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

// "Ready to Install"-Seite: Versions-Uebersicht + Selbstbau-Hinweis VOR den
// Standard-Infos (Zielordner). Die Seite zeigt sonst nur "Click Install..." -
// genau hier trifft der Nutzer die Entscheidung, also gehoert die
// Unterstuetzungs-Auskunft hierhin (Nutzerwunsch 2026-08-15).
// Darstellung: TRichEditViewer ueber dem ReadyMemo, damit die
// INSTALLIERBARE Version FETT stehen kann (Memo kann kein Bold);
// das Plain-Memo bleibt als Datenquelle/Fallback gefuellt.
var
  GReadyRich   : TRichEditViewer;
  GMemoDirInfo : string;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo,
  MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo,
  MemoTasksInfo: String): String;
begin
  // Zielordner-Block fuer den RTF-Aufbau in CurPageChanged merken.
  GMemoDirInfo := MemoDirInfo;
  Result := CustomMessage('ReadyHead') + NewLine + NewLine
          + CustomMessage('ReadyYes') + NewLine
          + CustomMessage('ReadyNo1') + NewLine
          + CustomMessage('ReadyNo2') + NewLine
          + CustomMessage('ReadyNo3') + NewLine + NewLine
          + CustomMessage('ReadyNote') + NewLine
          + '{#SCAGitHubUrl}' + NewLine;
  if MemoDirInfo <> '' then
    Result := Result + NewLine + MemoDirInfo + NewLine;
end;

// RTF-Sonderzeichen entschaerfen (Backslash/geschweifte Klammern - der
// Zielordner-Block enthaelt Windows-Pfade).
function RtfEscape(const S: string): string;
begin
  Result := S;
  StringChangeEx(Result, '\', '\\', True);
  StringChangeEx(Result, '{', '\{', True);
  StringChangeEx(Result, '}', '\}', True);
end;

// Zeilenumbrueche des Memo-Texts (#13#10) in RTF-\par wandeln.
function RtfPar(const S: string): string;
begin
  Result := RtfEscape(S);
  StringChangeEx(Result, #13#10, '\par ', True);
  StringChangeEx(Result, #13, '\par ', True);
  StringChangeEx(Result, #10, '\par ', True);
end;

function BuildReadyRtf: string;
begin
  // \ansicpg1252: der Zielordner-Block kommt aus der Sprachdatei und darf
  // Umlaute enthalten; Segoe UI \fs18 = 9pt wie die Wizard-Schrift.
  Result :=
    '{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0 Segoe UI;}}\f0\fs18 '
    + RtfPar(CustomMessage('ReadyHead')) + '\par \par '
    + '{\b ' + RtfPar(CustomMessage('ReadyYes')) + '}\par '
    + RtfPar(CustomMessage('ReadyNo1')) + '\par '
    + RtfPar(CustomMessage('ReadyNo2')) + '\par '
    + RtfPar(CustomMessage('ReadyNo3')) + '\par \par '
    + RtfPar(CustomMessage('ReadyNote')) + '\par '
    + RtfPar('{#SCAGitHubUrl}') + '\par ';
  if GMemoDirInfo <> '' then
    Result := Result + '\par ' + RtfPar(GMemoDirInfo) + '\par ';
  Result := Result + '}';
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if GReadyRich = nil then Exit;
  if CurPageID = wpReady then
  begin
    GReadyRich.RTFText := BuildReadyRtf;
    GReadyRich.Visible := True;
    WizardForm.ReadyMemo.Visible := False;
  end
  else
    GReadyRich.Visible := False;
end;

procedure InitializeWizard;
var
  Btn: TNewButton;
  NextLeft: Integer;
begin
  // Ready-Memo: Inno-Default ist WordWrap AUS + horizontaler Scrollbalken -
  // die Hinweis-Saetze der Versions-Uebersicht liefen damit aus dem Bild
  // (Nutzer-Feedback 2026-08-15). Umbruch an, nur vertikal scrollen
  // (gilt fuer das Fallback-Memo; die Anzeige uebernimmt der RichViewer).
  WizardForm.ReadyMemo.WordWrap   := True;
  WizardForm.ReadyMemo.ScrollBars := ssVertical;

  // RichEdit-Viewer anstelle des ReadyMemo - traegt die RTF-Fassung mit
  // FETTER installierbarer Version (CurPageChanged). Bewusst NICHT
  // deckungsgleich (Nutzer-Feedback 2026-08-15): etwas nach unten
  // geschoben (das zweizeilige "Click Install..."-Label wurde sonst
  // angeschnitten) und unten verkuerzt (die Box wirkte zu gross).
  GReadyRich := TRichEditViewer.Create(WizardForm);
  GReadyRich.Parent := WizardForm.ReadyMemo.Parent;
  GReadyRich.SetBounds(WizardForm.ReadyMemo.Left,
    WizardForm.ReadyMemo.Top + ScaleY(16),
    WizardForm.ReadyMemo.Width,
    WizardForm.ReadyMemo.Height - ScaleY(48));
  GReadyRich.Anchors    := WizardForm.ReadyMemo.Anchors;
  GReadyRich.ReadOnly   := True;
  GReadyRich.ScrollBars := ssVertical;
  GReadyRich.UseRichEdit := True;
  GReadyRich.Visible    := False;

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
  InstalledPathD13: string;
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
    // D13, beide IDE-Bitness-Schienen. Gurt und Hosentraeger neben
    // uninsdeletevalue - loeschen, was nicht existiert, ist folgenlos.
    InstalledPathD13 := ExpandConstant('{app}\bpl\d13\') + PLUGIN_BPL_NAME;
    RegDeleteValue(HKEY_CURRENT_USER, KNOWN_PACKAGES_37, InstalledPathD13);
    RegDeleteValue(HKEY_CURRENT_USER, DISABLED_PACKAGES_37, InstalledPathD13);
    InstalledPathD13 := ExpandConstant('{app}\bpl\d13x64\') + PLUGIN_BPL_NAME;
    RegDeleteValue(HKEY_CURRENT_USER, KNOWN_PACKAGES_37X64, InstalledPathD13);
    RegDeleteValue(HKEY_CURRENT_USER, DISABLED_PKGS_37X64, InstalledPathD13);
#ifdef SCA_D12_X64
    RegDeleteValue(HKEY_CURRENT_USER, '{#KnownPackages23x64}',
      ExpandConstant('{app}\bpl\d12x64\') + PLUGIN_BPL_NAME);
    RegDeleteValue(HKEY_CURRENT_USER, '{#DisabledPkgs23x64}',
      ExpandConstant('{app}\bpl\d12x64\') + PLUGIN_BPL_NAME);
#endif
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

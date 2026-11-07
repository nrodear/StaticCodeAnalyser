; =============================================================================
; StaticCodeAnalyserSetup.iss  —  Inno Setup 6.x, Paketsatz fuer drei IDE-Schienen
; Referenz: Welle 1, 2026-07-25; Paketsatz ab 0.9.19
; Grundlage: Doku_05_IDE_Plugin.md (Installer-Abschnitt) + Konzept_IdePluginInstaller_2026-07-23
;            + Konzept_AuslieferungPaketsatz_2026-10-28
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
;   * D12 = BDS 23.0 (Win32-IDE). D13 = BDS 37.0 (Win32- und Win64-IDE).
;   * Der IDE-PATH-Override ist ein GETEILTER Wert: nur das eigene Segment
;     einfuegen oder entfernen, nie den Wert ersetzen.
; =============================================================================

; --- Versionsstand ------------------------------------------------------------
; Diese Stellen tragen die Version, alle muessen zusammenpassen:
;   uSCAConsts.SCA_VERSION + SCA_VERSION_FULL
;   rules/sca-rules.json  ->  tool.version
;   StaticCodeAnalyser.d12.dproj      VerInfo_Keys + VerInfo_Release
;   die vier Paket-dproj (SCA.Engine, SCA.SharedUI, StaticCodeAnalyser.IDE.d12,
;   reDelphix.d12)  VerInfo_Keys + numerische Felder, je Win32 UND Win64
;   diese Datei
; uIDEExpert.PLUGIN_VERSION (Titel im IDE-Fenster) ist KEINE eigene Stelle
; mehr: seit 2026-08-23 leitet sie sich aus SCA_VERSION ab ('v' +
; SCA_VERSION) und zieht von selbst nach. Vorher war sie von Hand
; gepflegt und blieb zweimal haengen (bis 0.9.11 zwei Releases zurueck,
; bei 0.9.17 als einzige Stelle).
; Der frueher hier vermerkte Drift ist behoben: seit 0.9.10 stimmen die
; numerischen VerInfo-Felder mit dem Keys-String ueberein (sie standen
; seit 0.9.4 auf 0/9/4, waehrend der String etwas anderes behauptete).
; Ueberschreibbar per ISCC /DSCAVersion=x.y.z.0 bzw. x.y.z.w (vierteilig,
; z.B. 0.9.19.1) - package-release.ps1 setzt
; die Version zentral, der Default hier dient nur dem Hand-Compile.
#ifndef SCAVersion
  #define SCAVersion    "0.9.19.1"
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
; Ausgeliefert wird seit 0.9.19 der Paketsatz, den auch der Dev-Bau erzeugt.
; Vier BPLs je Schiene:
;   SCA.Engine<suffix>.bpl          Laufzeitpaket ({$RUNONLY})
;   SCA.SharedUI<suffix>.bpl        Laufzeitpaket ({$RUNONLY})
;   StaticCodeAnalyser.IDE.d12.bpl  Design-Paket, requires Engine + SharedUI
;   reDelphix.d12.bpl               Design-Paket, requires Engine; fest Teil jeder Schiene
; Die dproj setzen KEIN DCC_BplOutput -> BPLs landen im Standard-BPL-Ordner
; der jeweiligen IDE (Studio\<bds>\Bpl, Win64 in Bpl\Win64). Die Generation
; steckt im Ordner, auch "d12" im Namen der Design-Pakete gilt fuer beide.
;
; Ladeweg (L3): Der Windows-Loader loest requires ueber bds.exe-Verzeichnis,
; System32 und PATH auf, NIE im Ordner der Design-BPL, und ein RUNONLY-Paket
; darf nicht in die Known Packages. Deshalb stehen nur die Design-BPLs dort
; (voller Pfad), und {app}\bpl\<schiene> kommt vorn in den IDE-eigenen Override
; HKCU\Software\Embarcadero\BDS\<bds>\Environment Variables\PATH. Am 2026-10-28
; gemessen: die IDE uebernimmt ihn vor dem Laden der Known Packages, auch
; bin64\bds.exe, und beide Loader ueberspringen gleichnamige BPLs der falschen
; Bitbreite.

; Quellordner der gebauten BPLs (Build-Maschine; per ISCC /D ueberschreibbar):
;   iscc /DSCABplSourceDir="D:\pfad\zu\bpls" StaticCodeAnalyserSetup.iss
; D13 entsprechend: SCABplSourceDirD13, SCABplSourceDirD13X64.
#ifndef SCABplSourceDir
  #define SCABplSourceDir "C:\Users\Public\Documents\Embarcadero\Studio\23.0\Bpl"
#endif

; Repo-Wurzel fuer Beilagen (Regelkatalog):
#ifndef SCARepoRoot
  #define SCARepoRoot "..\"
#endif

#define SCAIdeBpl      "StaticCodeAnalyser.IDE.d12.bpl"
#define SCARdxBpl      "reDelphix.d12.bpl"
; Altlast bis 0.9.18, nur noch fuer die Upgrade-Bereinigung:
#define SCAMonolithBpl "StaticCodeAnalyser.Plugin.d12.bpl"

; Versions-Suffix der LAUFZEITpakete (Q1, 2026-09-21). Die beiden .dpk
; tragen {$LIBSUFFIX AUTO}; der Compiler haengt damit je Generation
; "290" bzw. "370" an, Win32 und Win64 gleich. Grund: beide Bpl-Ordner
; stehen im PATH, und ein Laufzeitpaket wird IMMER darueber aufgeloest -
; gleichnamige BPLs zweier Generationen liessen D12 die Fassung von D13
; laden (belegt am 2026-09-19 und 2026-09-20, beide Male roter IDE-Start).
; Die Design-BPLs bleiben OHNE Suffix: sie stehen mit vollem Pfad in
; den Known Packages, dort sucht der Loader nicht.
#define SCASuffixD12 "290"
#define SCASuffixD13 "370"

; BDS-Registry-Schluessel D12 (HKCU):
#define BDS23Key        "Software\Embarcadero\BDS\23.0"
#define KnownPackages23 BDS23Key + "\Known Packages"
#define DisabledPkgs23  BDS23Key + "\Disabled Packages"

; --- KEINE 64-bit-Schiene fuer Delphi 12 -------------------------------------
; Hier stand ein vorbereiteter SCA_D12_X64-Zweig. Er ist am 2026-08-23
; entfernt worden, weil er nie funktionieren kann:
;
;   * Delphi 12 hat KEINE 64-bit-IDE. 23.0\bin64\bds.exe existiert nicht,
;     in bin64 liegt keine einzige dcl*-BPL.
;   * Ein Win64-Entwurfszeitpaket laesst sich dort auch nicht BAUEN:
;     designide gibt es nur als 23.0\bin\designide290.bpl und
;     23.0\lib\win32\{debug,release}\designide.dcp. Der Ordner
;     23.0\lib\win64\release existiert und traegt 96 DCPs - designide ist
;     keines davon, ToolsAPI.dcu fehlt ebenfalls.
;
; Der Versuch endet mit "E2202 Package 'designide' wird benoetigt, konnte
; aber nicht gefunden werden". Beide Design-dpk fangen das inzwischen mit
; einer verstaendlichen {$MESSAGE FATAL}-Zeile ab.
;
; Fuer Delphi 13 gilt das Gegenteil - siehe den Block direkt darunter.

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
; designide in bin64, kein designide.dcp fuer win64, null dcl*-BPLs.
; Ein Gegenstueck fuer D12 gibt es deshalb nicht - der frueher
; vorbereitete Zweig ist am selben Tag entfernt worden, siehe oben.
#define SCA_D13
#define SCA_D13_X64

#ifdef SCA_D13
  #define BDS37Key        "Software\Embarcadero\BDS\37.0"
  #define KnownPackages37 BDS37Key + "\Known Packages"
  #define DisabledPkgs37  BDS37Key + "\Disabled Packages"
  ; Quellordner der D13-BPLs. Ein Projektsatz baut beide Generationen; die
  ; Generation steckt im Zielordner der IDE und im Suffix der Laufzeitpakete
  ; - die Design-BPLs heissen hier wie unter D12.
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
; Ohne VersionInfoVersion bleibt die FileVersion der Setup-Exe LEER -
; Inno leitet nur die ProductVersion aus AppVersion ab. Explorer und
; jedes Werkzeug, das nach der Dateiversion fragt, sehen dann nichts.
VersionInfoVersion={#SCAVersion}
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
; Nur Windows, 32/64-Bit-OS egal: das Setup selbst laeuft als 32-bit-Prozess,
; welche BPLs es ablegt, haengt allein von den gewaehlten Schienen ab.
ArchitecturesAllowed=x86compatible x64compatible
UninstallDisplayName={#SCAAppName}
; Nicht auf eine BPL zeigen: jede Schiene ist abwaehlbar, die Datei fehlte dann.
UninstallDisplayIcon={uninstallexe}
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
de.IdeRunning=Eine Delphi-IDE (bds.exe) scheint zu laufen. Bitte alle Delphi-Instanzen schliessen und erneut starten.
en.IdeRunning=A Delphi IDE (bds.exe) appears to be running. Please close all Delphi instances and start again.
de.NoDelphi12=Es wurde weder Delphi 12 (BDS 23.0) noch Delphi 13 (BDS 37.0) auf diesem System gefunden. Das Plugin unterstuetzt Delphi 12.0-12.3 (32-bit-IDE) sowie Delphi 13 (32- und 64-bit-IDE); aeltere Versionen werden nicht unterstuetzt. Das Setup wird beendet, es wird nichts installiert.
en.NoDelphi12=Neither Delphi 12 (BDS 23.0) nor Delphi 13 (BDS 37.0) was found on this system. The plugin supports Delphi 12.0-12.3 (32-bit IDE) and Delphi 13 (32-bit and 64-bit IDE); older versions are not supported. Setup will close without installing anything.
de.DevBplWarn=Unter "%2" ist bereits eine Entwickler-Registrierung des Plugins mit anderem Pfad eingetragen:%n%n%1%nDer Eintrag wird durch die Installations-Registrierung ersetzt (Koexistenz-Schutz, verhindert Doppel-Laden).
en.DevBplWarn=A developer registration of the plugin with a different path already exists under "%2":%n%n%1%nIt will be replaced by the installed registration (coexistence guard, prevents double loading).
de.MonolithWarn=Die fruehere Einzel-BPL des Plugins war noch registriert:%n%n%1%nDer Eintrag wurde entfernt: der neue Paketsatz enthaelt dieselben Units, beide zusammen liessen die IDE beim Start scheitern.
en.MonolithWarn=The former single-BPL plugin was still registered:%n%n%1%nThe entry has been removed: the new package set contains the same units, and having both would make the IDE fail at startup.
de.OverrideFail=Der PATH-Eintrag der IDE konnte nicht geschrieben werden (%1). Ohne ihn laedt das Plugin beim IDE-Start nicht.
en.OverrideFail=The IDE's PATH entry could not be written (%1). Without it the plugin will not load when the IDE starts.
de.DonateBtn=PayPal-Spende
en.DonateBtn=PayPal Donate
de.StarBtn=Stern auf GitHub
en.StarBtn=Star on GitHub
; Versions-Uebersicht auf der "Ready to Install"-Seite (Nutzerwunsch
; 2026-08-15; installierbare Version FETT via TRichEditViewer). Bewusst
; dieselben Aussagen wie die Matrix in README_Installer.md par.0 - bei
; Aenderungen BEIDE Stellen pflegen. Einzeilige Bausteine, der [Code]-Teil
; setzt sie zu RTF (fett) bzw. Plain-Text (Fallback-Memo) zusammen.
; --- Auswahlliste der Ziel-IDEs (2026-08-23) ---------------------------------
; Angezeigt wird nur, was auf diesem Rechner wirklich gefunden wurde - die
; Check:-Ausdruecke der [Components] blenden den Rest aus. Installiert wird
; nur, was angehakt ist.
de.TypeFull=Alle gefundenen Delphi-Versionen
en.TypeFull=All Delphi versions found
de.TypeCustom=Benutzerdefiniert
en.TypeCustom=Custom
de.CompD12=Delphi 12 Athens (32-bit-IDE)
en.CompD12=Delphi 12 Athens (32-bit IDE)
de.CompD13=Delphi 13 Florence (32-bit-IDE)
en.CompD13=Delphi 13 Florence (32-bit IDE)
de.CompD13X64=Delphi 13 Florence (64-bit-IDE)
en.CompD13X64=Delphi 13 Florence (64-bit IDE)
de.NoComponent=Bitte mindestens eine Delphi-Version auswaehlen - sonst wird kein Plugin installiert.
en.NoComponent=Please select at least one Delphi version - otherwise no plugin is installed.

de.ReadyHead=Unterstuetzte Delphi-Versionen:
en.ReadyHead=Supported Delphi versions:
de.ReadyYes1=Delphi 12.0 - 12.3 (32-bit-IDE)  -  JA, dieses Setup
en.ReadyYes1=Delphi 12.0 - 12.3 (32-bit IDE)  -  YES, this setup
de.ReadyYes2=Delphi 13 "Florence" (32-bit-IDE)  -  JA, dieses Setup
en.ReadyYes2=Delphi 13 "Florence" (32-bit IDE)  -  YES, this setup
de.ReadyYes3=Delphi 13 "Florence" (64-bit-IDE)  -  JA, dieses Setup
en.ReadyYes3=Delphi 13 "Florence" (64-bit IDE)  -  YES, this setup
de.ReadyNo1=Delphi 12 (64-bit-IDE)  -  gibt es nicht: Delphi 12 bringt keine 64-bit-IDE mit
en.ReadyNo1=Delphi 12 (64-bit IDE)  -  does not exist: Delphi 12 ships no 64-bit IDE
de.ReadyNo2=Delphi 11 und aelter  -  nicht unterstuetzt
en.ReadyNo2=Delphi 11 and older  -  not supported
de.ReadyNote=Hinweis: Fuer andere Delphi-IDE-Versionen bestehen derzeit keine Testmoeglichkeiten. Alternative: das Projekt von GitHub laden und die Packages selbst in der IDE bauen und installieren - Anleitung (HowTo_Build.md) im Repository:
en.ReadyNote=Note: there is currently no way for us to test on other Delphi IDE versions. Alternative: download the project from GitHub and build/install the packages yourself in the IDE - instructions (HowTo_Build.md) in the repository:
de.ReadyPath=Das Setup traegt seinen Paketordner vorn in die PATH-Einstellung der gewaehlten IDEs ein (Tools > Optionen > IDE > Umgebungsvariablen), sonst findet die IDE die Plugin-Pakete nicht. Bestehende Eintraege bleiben erhalten, die Deinstallation nimmt nur diesen Ordner wieder heraus.
en.ReadyPath=Setup adds its package folder to the front of the PATH setting of the selected IDEs (Tools > Options > IDE > Environment Variables); without it the IDE cannot find the plugin packages. Existing entries stay in place, uninstalling removes only this folder.

[Messages]
; Privacy-Hinweis auf der Willkommensseite ergaenzen:
de.WelcomeLabel2=%n[name/ver] wird auf Ihrem Computer installiert (nur fuer den aktuellen Benutzer, ohne Administratorrechte).%n%nDieses Setup und das Plugin bauen niemals Netzwerkverbindungen auf: kein Update-Check, keine Telemetrie, kein AI/LLM-Egress.
en.WelcomeLabel2=%nThis will install [name/ver] on your computer (current user only, no administrator rights).%n%nThis setup and the plugin never open network connections: no update check, no telemetry, no AI/LLM egress.

[Types]
Name: "full";   Description: "{cm:TypeFull}"
Name: "custom"; Description: "{cm:TypeCustom}"; Flags: iscustom

[Components]
; Check: entscheidet, ob der Eintrag ueberhaupt ERSCHEINT. Eine nicht
; installierte IDE steht damit gar nicht erst zur Auswahl - besser als ein
; Haken, der ins Leere fuehrt.
; Types: full -> in der Voreinstellung sind alle gefundenen angehakt.
; disablenouninstallwarning: Innos Warnung "wird nicht deinstalliert" waere
; hier falsch, CurStepChanged entfernt Abgewaehltes restlos.
; reDelphix ist bewusst KEINE eigene Komponente: es gehoert fest zu jeder Schiene
; und wird mit ihr installiert und registriert. Technisch haengt das Plugin nicht
; davon ab (StaticCodeAnalyser.IDE.d12 requires nur Engine und SharedUI).
Name: "d12";    Description: "{cm:CompD12}";    Types: full custom; \
  Flags: disablenouninstallwarning; Check: IsDelphi12Installed
Name: "d13";    Description: "{cm:CompD13}";    Types: full custom; \
  Flags: disablenouninstallwarning; Check: IsDelphi13Installed
Name: "d13x64"; Description: "{cm:CompD13X64}"; Types: full custom; \
  Flags: disablenouninstallwarning; Check: IsDelphi13X64Available

[Files]
; Vier BPLs je Schiene, Components statt Check: nur schreiben, wenn die
; jeweilige IDE wirklich da und gewaehlt ist. Ohne das landen Dateien und
; HKCU-Werte in einer toten BDS-Schiene.
; --- D12 (BDS 23.0) -----------------------------------------------------------
Source: "{#SCABplSourceDir}\SCA.Engine{#SCASuffixD12}.bpl"; DestDir: "{app}\bpl\d12"; \
  Flags: ignoreversion; Components: d12
Source: "{#SCABplSourceDir}\SCA.SharedUI{#SCASuffixD12}.bpl"; DestDir: "{app}\bpl\d12"; \
  Flags: ignoreversion; Components: d12
Source: "{#SCABplSourceDir}\{#SCAIdeBpl}"; DestDir: "{app}\bpl\d12"; \
  Flags: ignoreversion; Components: d12
Source: "{#SCABplSourceDir}\{#SCARdxBpl}"; DestDir: "{app}\bpl\d12"; \
  Flags: ignoreversion; Components: d12

; --- D13 (BDS 37.0) -----------------------------------------------------------
#ifdef SCA_D13
Source: "{#SCABplSourceDirD13}\SCA.Engine{#SCASuffixD13}.bpl"; DestDir: "{app}\bpl\d13"; \
  Flags: ignoreversion; Components: d13
Source: "{#SCABplSourceDirD13}\SCA.SharedUI{#SCASuffixD13}.bpl"; DestDir: "{app}\bpl\d13"; \
  Flags: ignoreversion; Components: d13
Source: "{#SCABplSourceDirD13}\{#SCAIdeBpl}"; DestDir: "{app}\bpl\d13"; \
  Flags: ignoreversion; Components: d13
Source: "{#SCABplSourceDirD13}\{#SCARdxBpl}"; DestDir: "{app}\bpl\d13"; \
  Flags: ignoreversion; Components: d13
#endif
#ifdef SCA_D13_X64
; Die 64-bit-IDE laedt NIE eine 32-bit-BPL. Eigener Build, eigener Ordner,
; gleiche Dateinamen - unterschieden wird ueber den Pfad.
Source: "{#SCABplSourceDirD13X64}\SCA.Engine{#SCASuffixD13}.bpl"; DestDir: "{app}\bpl\d13x64"; \
  Flags: ignoreversion; Components: d13x64
Source: "{#SCABplSourceDirD13X64}\SCA.SharedUI{#SCASuffixD13}.bpl"; DestDir: "{app}\bpl\d13x64"; \
  Flags: ignoreversion; Components: d13x64
Source: "{#SCABplSourceDirD13X64}\{#SCAIdeBpl}"; DestDir: "{app}\bpl\d13x64"; \
  Flags: ignoreversion; Components: d13x64
Source: "{#SCABplSourceDirD13X64}\{#SCARdxBpl}"; DestDir: "{app}\bpl\d13x64"; \
  Flags: ignoreversion; Components: d13x64
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

[UninstallDelete]
; Inno entfernt die installierten Dateien selbst. Die drei bpl-Ordner
; koennen aber Reste tragen - etwa eine BPL aus einem frueheren Lauf, die
; in diesem Lauf nicht mehr installiert wurde. Ohne diese Zeilen bliebe
; {app} nach der Deinstallation als Geruest stehen.
Type: filesandordirs; Name: "{app}\bpl\d12"
Type: filesandordirs; Name: "{app}\bpl\d13"
Type: filesandordirs; Name: "{app}\bpl\d13x64"
Type: dirifempty;     Name: "{app}\bpl"

[Icons]
; Sichtbarer Weg zum Deinstaller (Nutzerfrage 2026-08-15): den unins000.exe
; erzeugt Inno automatisch (+ Eintrag in Windows "Apps & Features"), aber ein
; IDE-Plugin hat keine startbare EXE und damit keinen natuerlichen Fundort -
; deshalb ein Startmenue-Eintrag. {userprograms}: per-user, kein Admin.
Name: "{userprograms}\Static Code Analyser for Delphi\Uninstall Static Code Analyser (IDE-Plugin)"; \
  Filename: "{uninstallexe}"

[Registry]
; HKCU-Registrierung, je Schiene die beiden Design-BPLs. Die Laufzeitpakete
; gehoeren NIE hierher ({$RUNONLY}), sie findet die IDE ueber den PATH-Override,
; den CurStepChanged setzt.
; Wertname = voller BPL-Pfad, Wertdaten = Beschreibung (NIE leer!).
; uninsdeletevalue: Inno deinstalliert in umgekehrter Installationsreihenfolge,
; d.h. diese Registry-Werte verschwinden VOR den Dateien (Doku-Grundsatz);
; zusaetzlich raeumt CurUninstallStepChanged (usUninstall) als Gurt+Hosentraeger.
; --- D12 (BDS 23.0, Win32) ----------------------------------------------------
Root: HKCU; Subkey: "{#KnownPackages23}"; ValueType: string; \
  ValueName: "{app}\bpl\d12\{#SCAIdeBpl}"; \
  ValueData: "Static Code Analyser for Delphi (IDE-Plugin)"; \
  Flags: uninsdeletevalue; Components: d12
Root: HKCU; Subkey: "{#KnownPackages23}"; ValueType: string; \
  ValueName: "{app}\bpl\d12\{#SCARdxBpl}"; \
  ValueData: "reDelphix - Source Refactor for Static Code Analyser"; \
  Flags: uninsdeletevalue; Components: d12

; --- D13 (BDS 37.0) -----------------------------------------------------------
#ifdef SCA_D13
Root: HKCU; Subkey: "{#KnownPackages37}"; ValueType: string; \
  ValueName: "{app}\bpl\d13\{#SCAIdeBpl}"; \
  ValueData: "Static Code Analyser for Delphi (IDE-Plugin)"; \
  Flags: uninsdeletevalue; Components: d13
Root: HKCU; Subkey: "{#KnownPackages37}"; ValueType: string; \
  ValueName: "{app}\bpl\d13\{#SCARdxBpl}"; \
  ValueData: "reDelphix - Source Refactor for Static Code Analyser"; \
  Flags: uninsdeletevalue; Components: d13
#endif
#ifdef SCA_D13_X64
Root: HKCU; Subkey: "{#KnownPackages37x64}"; ValueType: string; \
  ValueName: "{app}\bpl\d13x64\{#SCAIdeBpl}"; \
  ValueData: "Static Code Analyser for Delphi (IDE-Plugin, 64-bit IDE)"; \
  Flags: uninsdeletevalue; Components: d13x64
Root: HKCU; Subkey: "{#KnownPackages37x64}"; ValueType: string; \
  ValueName: "{app}\bpl\d13x64\{#SCARdxBpl}"; \
  ValueData: "reDelphix - Source Refactor for Static Code Analyser (64-bit IDE)"; \
  Flags: uninsdeletevalue; Components: d13x64
#endif

[Code]
// ---------------------------------------------------------------------------
// Welle 1, 2026-07-25 — [Code]-Teil: IDE-Prozess-Check, Koexistenz-Check gegen
// Dev-BPLs, Disabled-Packages-Bereinigung, Uninstall-Reihenfolge; seit 0.9.19
// IDE-PATH-Override und Upgrade-Bereinigung des Monolithen.
// KEINERLEI Netzwerkzugriff (Privacy-Gate).
// ---------------------------------------------------------------------------

const
  KNOWN_PACKAGES_23    = 'Software\Embarcadero\BDS\23.0\Known Packages';
  DISABLED_PACKAGES_23 = 'Software\Embarcadero\BDS\23.0\Disabled Packages';
  ENV_VARS_23          = 'Software\Embarcadero\BDS\23.0\Environment Variables';
  KNOWN_PACKAGES_37    = 'Software\Embarcadero\BDS\37.0\Known Packages';
  DISABLED_PACKAGES_37 = 'Software\Embarcadero\BDS\37.0\Disabled Packages';
  KNOWN_PACKAGES_37X64 = 'Software\Embarcadero\BDS\37.0\Known Packages x64';
  DISABLED_PKGS_37X64  = 'Software\Embarcadero\BDS\37.0\Disabled Packages x64';
  ENV_VARS_37          = 'Software\Embarcadero\BDS\37.0\Environment Variables';
  IDE_BPL_NAME      = '{#SCAIdeBpl}';
  RDX_BPL_NAME      = '{#SCARdxBpl}';
  MONOLITH_BPL_NAME = '{#SCAMonolithBpl}';
  SUFFIX_D12        = '{#SCASuffixD12}';
  SUFFIX_D13        = '{#SCASuffixD13}';

// Laeuft eine Delphi-IDE? Erkennung ueber das IDE-Hauptfenster (Klasse
// TAppBuilder) — bewusst ohne Prozess-APIs/WMI, bleibt lowest-privilege.
// Unterscheidet nicht zwischen BDS-Versionen; das passt, das Setup fasst
// mehrere Schienen an.
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

// AStamm + Versions-Ziffern + .bpl? Trifft SCA.Engine.bpl, SCA.Engine290.bpl
// und SCA.Engine370.bpl, aber kein fremdes SCA.EngineTools.bpl.
function IsPaketMitSuffix(const FileName, AStamm: string): Boolean;
var
  Rest: string;
  I: Integer;
begin
  Result := False;
  if CompareText(Copy(FileName, 1, Length(AStamm)), AStamm) <> 0 then
    Exit;
  if CompareText(Copy(FileName, Length(FileName) - 3, 4), '.bpl') <> 0 then
    Exit;
  Rest := Copy(FileName, Length(AStamm) + 1,
    Length(FileName) - Length(AStamm) - 4);
  for I := 1 to Length(Rest) do
    if (Rest[I] < '0') or (Rest[I] > '9') then
      Exit;
  Result := True;
end;

// Gehoert der BPL-Dateiname zur SCA-Familie? Jede Registrierung dieser
// Familie ausserhalb des Installationsordners ist eine Koexistenz-Gefahr:
// Monolith und Paketsatz enthalten dieselben Units, und eine Dev-BPL neben
// der installierten laedt die Engine doppelt. Die IDE wirft dann beim Start
// "enthaelt die Unit ..., die auch im Package ... enthalten ist"
// (2026-08-15 auf dem Zweit-PC real passiert, via GetIt-Install).
function IsScaFamilyBpl(const FileName: string): Boolean;
begin
  Result := IsPaketMitSuffix(FileName, 'SCA.Engine')
    or IsPaketMitSuffix(FileName, 'SCA.SharedUI')
    or (CompareText(FileName, IDE_BPL_NAME) = 0)
    or (CompareText(FileName, RDX_BPL_NAME) = 0)
    or (CompareText(FileName, MONOLITH_BPL_NAME) = 0);
end;

// Voller Installationspfad einer Schiene bzw. einer BPL darin.
function SchienenOrdner(const AOrdner: string): string;
begin
  Result := ExpandConstant('{app}\bpl\') + AOrdner;
end;

function BplPfad(const AOrdner, ABpl: string): string;
begin
  Result := AddBackslash(SchienenOrdner(AOrdner)) + ABpl;
end;

// Sammelt alle "Known Packages"-Wertnamen (= volle BPL-Pfade), die auf eine
// unserer BPL-Dateinamen enden, aber NICHT auf die beiden installierten
// Design-BPLs dieser Schiene zeigen.
// Das sind Dev-/Alt-Registrierungen (z.B. Public-Documents-Bpl) —
// Koexistenz-Gefahr: dieselbe Unit darf nicht doppelt laden.
// Fremde Registrierungen der SCA-Familie in EINEM Registry-Zweig sammeln.
//
// Der Zweig ist jetzt ein Parameter. Vorher stand hier fest
// KNOWN_PACKAGES_23 - der Check sah also nur die D12-Schiene. Am
// 2026-08-23 war die Folge: unter 37.0 waren SCA.Engine und SCA.SharedUI
// aus einem IDE-Bau registriert, das Setup legte den Monolithen daneben,
// und Delphi 13 verweigerte den Dienst mit "enthaelt die Unit
// 'uLocalization', die auch im Package 'SCA.Engine' enthalten ist".
procedure CollectForeignPluginEntries(const AKey, AOrdner: string;
  Entries: TStringList);
var
  Names: TArrayOfString;
  I: Integer;
  N: string;
begin
  if RegGetValueNames(HKEY_CURRENT_USER, AKey, Names) then
    for I := 0 to GetArrayLength(Names) - 1 do
    begin
      N := Names[I];
      if IsScaFamilyBpl(ExtractFileName(N)) and
         (CompareText(N, BplPfad(AOrdner, IDE_BPL_NAME)) <> 0) and
         (CompareText(N, BplPfad(AOrdner, RDX_BPL_NAME)) <> 0) then
        Entries.Add(N);
    end;
end;

// ---------------------------------------------------------------------------
// IDE-PATH-Override (Ladeweg L3). Der Wert ist GETEILT, InterBase steht dort
// z.B. mit ...\IDE_spoof;$(PATH). Deshalb nur das eigene Segment bewegen und
// alles andere Zeichen fuer Zeichen stehen lassen.
// ---------------------------------------------------------------------------

function IstGleichesSegment(const A, B: string): Boolean;
begin
  Result := AnsiLowercase(RemoveBackslash(Trim(A)))
          = AnsiLowercase(RemoveBackslash(Trim(B)));
end;

function OverrideOhneSegment(const AWert, ASegment: string): string;
var
  Teile: TArrayOfString;
  I, Behalten: Integer;
begin
  Result := '';
  Behalten := 0;
  Teile := StringSplit(AWert, [';'], stAll);
  for I := 0 to GetArrayLength(Teile) - 1 do
    if not IstGleichesSegment(Teile[I], ASegment) then
    begin
      if Behalten > 0 then
        Result := Result + ';';
      Result := Result + Teile[I];
      Behalten := Behalten + 1;
    end;
end;

// Immer entnehmen und vorn einsetzen: das haelt den Wert bei Doppelinstallation
// stabil und holt das Segment nach vorn, falls ein anderes Werkzeug davor kam.
function OverrideMitSegment(const AWert, ASegment: string): string;
begin
  Result := OverrideOhneSegment(AWert, ASegment);
  // Ohne $(PATH) verloere die IDE ihren geerbten Suchpfad.
  if Trim(Result) = '' then
    Result := '$(PATH)';
  Result := ASegment + ';' + Result;
end;

// Bleibt nach dem Entfernen nur das, was das Setup selbst angelegt haette,
// ist der Ausgangszustand "kein Wert" wiederhergestellt.
function IstLeererOverride(const AWert: string): Boolean;
begin
  Result := (Trim(AWert) = '') or (CompareText(Trim(AWert), '$(PATH)') = 0);
end;

// RegWriteStringValue erhaelt REG_EXPAND_SZ (Inno-Hilfe), RegQueryStringValue
// liest beide Typen; der Werttyp eines vorhandenen Werts bleibt also.
// Fehlt der HKCU-Wert, gilt die Vorlage der Delphi-Installation aus HKLM
// (32-bit-Sicht) als Ausgangswert. Sonst gingen ihre Segmente verloren, denn
// der neue HKCU-Wert verdeckt sie.
function SetzeOverrideSegment(const AEnvKey, AOrdner: string): Boolean;
var
  Alt, Neu: string;
  Vorhanden: Boolean;
begin
  Vorhanden := RegQueryStringValue(HKEY_CURRENT_USER, AEnvKey, 'PATH', Alt);
  if not Vorhanden then
    if not RegQueryStringValue(HKEY_LOCAL_MACHINE_32, AEnvKey, 'PATH', Alt) then
      Alt := '';
  Neu := OverrideMitSegment(Alt, SchienenOrdner(AOrdner));
  Result := (Vorhanden and (Neu = Alt))
    or RegWriteStringValue(HKEY_CURRENT_USER, AEnvKey, 'PATH', Neu);
end;

// Eine aus HKLM entstandene HKCU-Kopie bleibt ohne unser Segment stehen: ob
// sie vorher schon da war, ist nicht unterscheidbar, und sie wirkt wie die
// Vorlage.
procedure EntferneOverrideSegment(const AEnvKey, AOrdner: string);
var
  Alt, Neu: string;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER, AEnvKey, 'PATH', Alt) then
    Exit;
  Neu := OverrideOhneSegment(Alt, SchienenOrdner(AOrdner));
  if Neu = Alt then
    Exit;     // nicht unser Segment drin -> der Wert geht uns nichts an
  if IstLeererOverride(Neu) then
  begin
    RegDeleteValue(HKEY_CURRENT_USER, AEnvKey, 'PATH');
    RegDeleteKeyIfEmpty(HKEY_CURRENT_USER, AEnvKey);
  end
  else
    RegWriteStringValue(HKEY_CURRENT_USER, AEnvKey, 'PATH', Neu);
end;

// Ein Dialog hielte einen Silent-Lauf an, bis jemand klickt; dort genuegt das Log.
procedure MeldeFehler(const AText: string; const ASilent: Boolean);
begin
  Log(AText);
  if not ASilent then
    MsgBox(AText, mbError, MB_OK);
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
    MeldeFehler(CustomMessage('NoDelphi12'), WizardSilent);
    Result := False;
    Exit;
  end;
  if IsDelphiIdeRunning then
  begin
    MeldeFehler(CustomMessage('IdeRunning'), WizardSilent);
    Result := False;
  end;
end;

// Zweiter Blick unmittelbar vor dem Schreiben: eine waehrend des Wizards
// gestartete IDE haelt die BPLs fest. Der Text stoppt Setup auf der
// Vorbereiten-Seite. Silent zeigt Inno ihn als Dialog (gemessen), deshalb
// faengt NextButtonClick diesen Fall vorher ab.
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if IsDelphiIdeRunning then
    Result := CustomMessage('IdeRunning');
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
  GMemoDirInfo  : string;
  GMemoCompInfo : string;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo,
  MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo,
  MemoTasksInfo: String): String;
begin
  // Zielordner- und Auswahlblock fuer den RTF-Aufbau in CurPageChanged
  // merken. Ohne den Auswahlblock zeigt die Zusammenfassung nicht, welche
  // Delphi-Versionen der Nutzer gerade angehakt hat - die Seite haette
  // ihren Zweck verfehlt.
  GMemoDirInfo  := MemoDirInfo;
  GMemoCompInfo := MemoComponentsInfo;
  Result := CustomMessage('ReadyHead') + NewLine + NewLine
          + CustomMessage('ReadyYes1') + NewLine
          + CustomMessage('ReadyYes2') + NewLine
          + CustomMessage('ReadyYes3') + NewLine
          + CustomMessage('ReadyNo1') + NewLine
          + CustomMessage('ReadyNo2') + NewLine + NewLine
          + CustomMessage('ReadyNote') + NewLine
          + '{#SCAGitHubUrl}' + NewLine + NewLine
          + CustomMessage('ReadyPath') + NewLine;
  if MemoComponentsInfo <> '' then
    Result := Result + NewLine + MemoComponentsInfo + NewLine;
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
    + '{\b ' + RtfPar(CustomMessage('ReadyYes1')) + '}\par '
    + '{\b ' + RtfPar(CustomMessage('ReadyYes2')) + '}\par '
    + '{\b ' + RtfPar(CustomMessage('ReadyYes3')) + '}\par '
    + RtfPar(CustomMessage('ReadyNo1')) + '\par '
    + RtfPar(CustomMessage('ReadyNo2')) + '\par \par '
    + RtfPar(CustomMessage('ReadyNote')) + '\par '
    + RtfPar('{#SCAGitHubUrl}') + '\par \par '
    + RtfPar(CustomMessage('ReadyPath')) + '\par ';
  if GMemoCompInfo <> '' then
    Result := Result + '\par ' + RtfPar(GMemoCompInfo) + '\par ';
  if GMemoDirInfo <> '' then
    Result := Result + '\par ' + RtfPar(GMemoDirInfo) + '\par ';
  Result := Result + '}';
end;

// Auf der Komponentenseite nicht weiterlassen, wenn nichts angehakt ist.
// Ohne das laeuft das Setup durch, legt den Ordner und den Regelkatalog an
// und installiert kein einziges Plugin - ein Erfolg, der keiner ist.
function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  // Silent-Gegenstueck zu PrepareToInstall: ein False beendet Setup ohne Dialog.
  if (CurPageID = wpReady) and WizardSilent and IsDelphiIdeRunning then
  begin
    MeldeFehler(CustomMessage('IdeRunning'), True);
    Result := False;
    Exit;
  end;
  if CurPageID <> wpSelectComponents then
    Exit;
  if not (WizardIsComponentSelected('d12')
       or WizardIsComponentSelected('d13')
       or WizardIsComponentSelected('d13x64')) then
  begin
    MeldeFehler(CustomMessage('NoComponent'), WizardSilent);
    Result := False;
  end;
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

// Meldung im Wizard; ein Silent-Lauf darf an keinem Dialog haengen bleiben,
// dort steht der Text nur im Log.
procedure Hinweis(const AText: string);
begin
  Log(AText);
  if not WizardSilent then
    MsgBox(AText, mbInformation, MB_OK);
end;

// Fremde SCA-Registrierungen eines Zweigs entfernen und den Nutzer
// darueber unterrichten. Stillschweigend loeschen waere hier falsch: es
// ist SEINE Dev-Registrierung, die verschwindet.
procedure RaeumeFremdeRegistrierungen(const AKey, AOrdner: string);
var
  Foreign: TStringList;
  I: Integer;
begin
  Foreign := TStringList.Create;
  try
    CollectForeignPluginEntries(AKey, AOrdner, Foreign);
    if Foreign.Count > 0 then
      Hinweis(FmtMessage(CustomMessage('DevBplWarn'), [Foreign.Text, AKey]));
    for I := 0 to Foreign.Count - 1 do
      RegDeleteValue(HKEY_CURRENT_USER, AKey, Foreign[I]);
  finally
    Foreign.Free;
  end;
end;

// Monolith-Werte eines Zweigs entfernen. Es zaehlt der Dateiname, nicht der
// Pfad: GetIt schreibt seine Wertnamen re-tokenisiert als %Makro%\...bpl.
procedure EntferneMonolithWerte(const AKey: string; Treffer: TStringList);
var
  Names: TArrayOfString;
  I: Integer;
begin
  if RegGetValueNames(HKEY_CURRENT_USER, AKey, Names) then
    for I := 0 to GetArrayLength(Names) - 1 do
      if CompareText(ExtractFileName(Names[I]), MONOLITH_BPL_NAME) = 0 then
      begin
        RegDeleteValue(HKEY_CURRENT_USER, AKey, Names[I]);
        if Treffer.IndexOf(Names[I]) < 0 then
          Treffer.Add(Names[I]);
      end;
end;

procedure EntferneDatei(const APfad: string);
begin
  if FileExists(APfad) then
    DeleteFile(APfad);
end;

// Upgrade-Bereinigung vom Monolithen bis 0.9.18, ueber ALLE drei Schienen,
// auch abgewaehlte: er enthaelt dieselben Units wie der Paketsatz, und ein
// uebersehener Rest legt die IDE beim Start lahm. Die Datei eines GetIt-Pakets
// bleibt im Katalog liegen, sie gehoert GetIt; unsere eigene wird geloescht.
procedure RaeumeMonolith;
var
  Treffer: TStringList;
begin
  Treffer := TStringList.Create;
  try
    EntferneMonolithWerte(KNOWN_PACKAGES_23, Treffer);
    EntferneMonolithWerte(DISABLED_PACKAGES_23, Treffer);
    EntferneMonolithWerte(KNOWN_PACKAGES_37, Treffer);
    EntferneMonolithWerte(DISABLED_PACKAGES_37, Treffer);
    EntferneMonolithWerte(KNOWN_PACKAGES_37X64, Treffer);
    EntferneMonolithWerte(DISABLED_PKGS_37X64, Treffer);
    EntferneDatei(BplPfad('d12', MONOLITH_BPL_NAME));
    EntferneDatei(BplPfad('d13', MONOLITH_BPL_NAME));
    EntferneDatei(BplPfad('d13x64', MONOLITH_BPL_NAME));
    if Treffer.Count > 0 then
      Hinweis(FmtMessage(CustomMessage('MonolithWarn'), [Treffer.Text]));
  finally
    Treffer.Free;
  end;
end;

procedure EntferneRegistrierung(const APfad, AKnownKey, ADisabledKey: string);
begin
  RegDeleteValue(HKEY_CURRENT_USER, AKnownKey, APfad);
  RegDeleteValue(HKEY_CURRENT_USER, ADisabledKey, APfad);
end;

procedure EntferneRegistrierungen(const AOrdner, AKnownKey, ADisabledKey: string);
begin
  EntferneRegistrierung(BplPfad(AOrdner, IDE_BPL_NAME), AKnownKey, ADisabledKey);
  EntferneRegistrierung(BplPfad(AOrdner, RDX_BPL_NAME), AKnownKey, ADisabledKey);
  EntferneRegistrierung(BplPfad(AOrdner, MONOLITH_BPL_NAME), AKnownKey, ADisabledKey);
end;

// Eine Variante restlos entfernen: Registrierung, Override-Segment, Dateien,
// Ordner.
//
// WOZU: Inno installiert eine abgewaehlte Komponente nicht - es entfernt
// sie aber auch NICHT, wenn sie aus einem frueheren Lauf noch daliegt.
// Wer das Setup erneut startet und eine Delphi-Version aushakt, haette
// sonst weiterhin BPL und Registry-Eintrag: abgewaehlt waere nicht
// deinstalliert, und die IDE wuerde das Plugin weiter laden.
procedure EntferneVariante(const AOrdner, ASuffix, AKnownKey, ADisabledKey,
  AEnvKey: string);
begin
  // Registry zuerst, Dateien danach - dieselbe Reihenfolge wie bei der
  // Deinstallation. Eine registrierte, aber fehlende BPL laesst die IDE
  // bei jedem Start scheitern.
  EntferneRegistrierungen(AOrdner, AKnownKey, ADisabledKey);
  EntferneOverrideSegment(AEnvKey, AOrdner);
  EntferneDatei(BplPfad(AOrdner, IDE_BPL_NAME));
  EntferneDatei(BplPfad(AOrdner, RDX_BPL_NAME));
  EntferneDatei(BplPfad(AOrdner, 'SCA.SharedUI' + ASuffix + '.bpl'));
  EntferneDatei(BplPfad(AOrdner, 'SCA.Engine' + ASuffix + '.bpl'));
  RemoveDir(SchienenOrdner(AOrdner));   // wirkt nur, wenn leer - genau so gewollt
end;

// Eine angehakte Schiene fertigstellen; Dateien und Known-Packages-Werte hat
// Inno zu diesem Zeitpunkt schon geschrieben.
procedure RichteSchieneEin(const AOrdner, AKnownKey, ADisabledKey, AEnvKey: string);
begin
  // Override VOR jeder Bereinigung: ohne ihn laedt der Paketsatz nicht, und
  // eine Dev-Registrierung waere dann der einzige lauffaehige Stand.
  if not SetzeOverrideSegment(AEnvKey, AOrdner) then
  begin
    MeldeFehler(FmtMessage(CustomMessage('OverrideFail'), [AEnvKey]), WizardSilent);
    Exit;
  end;

  // Koexistenz-Check, aber NUR fuer angehakte Komponenten. Einen Registry-
  // Zweig, den wir gar nicht bespielen, fasst das Setup nicht an - dort darf
  // der Nutzer seinen Dev-Satz behalten.
  RaeumeFremdeRegistrierungen(AKnownKey, AOrdner);

  // Disabled-Packages-Bereinigung: hatte der User ein Paket frueher per
  // "Can't load package -> Nein" deaktiviert (IDE-Selbstheilung), bliebe
  // der Disabled-Eintrag bestehen und wuerde die frische Installation
  // stumm blockieren.
  RegDeleteValue(HKEY_CURRENT_USER, ADisabledKey, BplPfad(AOrdner, IDE_BPL_NAME));
  RegDeleteValue(HKEY_CURRENT_USER, ADisabledKey, BplPfad(AOrdner, RDX_BPL_NAME));
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep <> ssPostInstall then
    Exit;

  RaeumeMonolith;

  if WizardIsComponentSelected('d12') then
    RichteSchieneEin('d12', KNOWN_PACKAGES_23, DISABLED_PACKAGES_23, ENV_VARS_23)
  else
    EntferneVariante('d12', SUFFIX_D12, KNOWN_PACKAGES_23,
      DISABLED_PACKAGES_23, ENV_VARS_23);

  // d13x64 VOR d13: beide teilen sich EINEN Override, jedes Einsetzen landet
  // vorn, also steht d13 am Ende vor d13x64 - wie Bpl vor Bpl\Win64 im System-
  // PATH. Beide Loader ueberspringen die falsche Bitbreite (gemessen), die
  // feste Folge haelt nur den Wert stabil.
  if WizardIsComponentSelected('d13x64') then
    RichteSchieneEin('d13x64', KNOWN_PACKAGES_37X64, DISABLED_PKGS_37X64, ENV_VARS_37)
  else
    EntferneVariante('d13x64', SUFFIX_D13, KNOWN_PACKAGES_37X64,
      DISABLED_PKGS_37X64, ENV_VARS_37);

  if WizardIsComponentSelected('d13') then
    RichteSchieneEin('d13', KNOWN_PACKAGES_37, DISABLED_PACKAGES_37, ENV_VARS_37)
  else
    EntferneVariante('d13', SUFFIX_D13, KNOWN_PACKAGES_37,
      DISABLED_PACKAGES_37, ENV_VARS_37);
end;

function InitializeUninstall: Boolean;
begin
  Result := True;
  if IsDelphiIdeRunning then
  begin
    MeldeFehler(CustomMessage('IdeRunning'), UninstallSilent);
    Result := False;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  // usUninstall feuert VOR dem Loeschen der Dateien -> hier raeumen wir die
  // Registry-Werte explizit (Doku-Grundsatz "Registry vor Dateien"), auch wenn
  // uninsdeletevalue dieselbe Reihenfolge bereits garantiert (Gurt+Hosentraeger,
  // deckt zudem manuell verschobene/duplizierte Eintraege ab). Alle Schienen,
  // unabhaengig von der Auswahl - loeschen, was nicht existiert, ist folgenlos.
  if CurUninstallStep = usUninstall then
  begin
    EntferneOverrideSegment(ENV_VARS_23, 'd12');
    EntferneOverrideSegment(ENV_VARS_37, 'd13');
    EntferneOverrideSegment(ENV_VARS_37, 'd13x64');
    EntferneRegistrierungen('d12', KNOWN_PACKAGES_23, DISABLED_PACKAGES_23);
    EntferneRegistrierungen('d13', KNOWN_PACKAGES_37, DISABLED_PACKAGES_37);
    EntferneRegistrierungen('d13x64', KNOWN_PACKAGES_37X64, DISABLED_PKGS_37X64);
  end;
end;

# Installer P1 — Bauanleitung (D12-Schiene)

> Referenz: Welle 1, 2026-07-25 | Grundlage: Doku_05_IDE_Plugin.md (Installer-Abschnitt),
> Konzept_IdePluginInstaller_2026-07-23 | D13 (BDS 37.0) ist GEBLOCKT — nur als
> auskommentierter Platzhalter im .iss enthalten.

## 1. Was zu bauen ist (in der IDE — kein msbuild/dcc32, kein RemoteDelphi)

Ziel-IDE: **Delphi 12 (BDS 23.0), Plattform Win32, Konfiguration Release**.

### Variante A — Release-Ziel (Konzept P1, noch offen)

Monolith-Package `StaticCodeAnalyser.Plugin.d12.dpk` (requires nur
`rtl, vcl, vclwinx, designide, xmlrtl`). **Diese dpk existiert im Repo noch
nicht** — sie ist das eigentliche P1-Arbeitspaket auf IDE-Seite. Sobald sie
gebaut ist: im `.iss` den Define `#define SCA_MONOLITH` aktivieren
(Kommentarzeichen entfernen), fertig.

Warum Monolith: der Windows-Loader loest `requires` per Modulname ueber
bds.exe-Verzeichnis → System32 → PATH auf, **nicht** im BPL-Verzeichnis.
Drei separate BPLs in einem privaten Installationsordner sind daher nicht
direkt ladbar.

### Variante B — aktueller Repo-Stand (Default des .iss)

Der Dev-3-Package-Satz, in dieser Reihenfolge in der IDE bauen (Release/Win32):

| # | Projekt | dpk | erzeugte BPL |
|---|---------|-----|--------------|
| 1 | `SCA.Engine\SCA.Engine.dproj` | `SCA.Engine.dpk` | `SCA.Engine.bpl` |
| 2 | `SCA.SharedUI\SCA.SharedUI.dpk` | `SCA.SharedUI.dpk` | `SCA.SharedUI.bpl` |
| 3 | `StaticCodeAnalyserIDE\StaticCodeAnalyser.IDE.d12.dproj` | `StaticCodeAnalyser.IDE.d12.dpk` | `StaticCodeAnalyser.IDE.d12.bpl` |

BPL-Ausgabeort: die dproj setzt **kein** `DCC_BplOutput` → die BPLs landen im
D12-Standardordner `C:\Users\Public\Documents\Embarcadero\Studio\23.0\Bpl`
(genau dorthin zeigt der `.iss`-Default `SCABplSourceDir`).

Der `.iss` registriert in Variante B **alle drei** BPLs mit vollem Pfad in
`Known Packages`; die IDE laedt Engine/SharedUI dadurch selbst, bevor die
Plugin-BPL ihre `requires` aufloest (Registry-Enumeration ist pfad-
alphabetisch: `SCA.*` vor `StaticCodeAnalyser.*`). Das ist eine dokumentierte
**Uebergangsloesung** — Release-Kanal bleibt die Monolith-BPL.

### Vor dem Release (Checkliste aus der Doku)

- **Versions-Sync** (Doku Punkt 3): `uSCAConsts.SCA_VERSION`,
  `uIDEExpert.PLUGIN_VERSION`, dproj-`VerInfo` (aktuell 0/9/4 vs. 0.9.8.0
  Drift!) synchronisieren; danach `#define SCAVersion` im `.iss` nachziehen.
- Verwaisten `SCA.Refactor.bpl`-Eintrag in der Dev-Registry bereinigen
  (Doku Punkt 4) — der Koexistenz-Check des Setups fasst nur Plugin-BPL-Namen an.
- Frischeste-Binaries-Check: User wechselt Win32/Win64 — sicherstellen, dass
  die neueste BPL wirklich aus einem Win32-Release-Build stammt.

## 2. Inno-Compile-Schritt

Voraussetzung: **Inno Setup 6.x** (ISCC.exe im PATH oder voller Pfad).

```bat
cd /d d:\git-demos\delphi\StaticCodeAnalyser\installer
iscc StaticCodeAnalyserSetup.iss
```

Optionen:

```bat
:: abweichender BPL-Quellordner (z. B. dedizierter Release-Staging-Ordner):
iscc /DSCABplSourceDir="D:\release\bpl" StaticCodeAnalyserSetup.iss

:: Monolith-Variante, sobald StaticCodeAnalyser.Plugin.d12.bpl existiert:
iscc /DSCA_MONOLITH StaticCodeAnalyserSetup.iss
```

Output: `installer\Output\StaticCodeAnalyserSetup-<Version>.exe`.

Der Regelkatalog `rules\sca-rules.json` wird relativ zum Repo (`SCARepoRoot`,
Default `..\`) eingesammelt und nach `{app}\rules` installiert. Hinweis fuer
die Nutzer-Doku (Doku Punkt 10): die Install-Kopie gewinnt vor der
APPDATA-Kopie; eigene Regeln via `CustomRulesFile`-Setting pflegen, der
Installer ueberschreibt `rules\sca-rules.json` bei jedem Update.

## 3. Was der Installer tut

- **Per-User, nie elevated** (`PrivilegesRequired=lowest`): Dateien nach
  `%LOCALAPPDATA%\Programs\StaticCodeAnalyser\bpl\d12\`, Registrierung unter
  `HKCU\Software\Embarcadero\BDS\23.0\Known Packages`
  (Wertname = voller BPL-Pfad, Wertdaten nie leer).
- **IDE-Prozess-Check** vor Install und Uninstall (TAppBuilder-Fenster).
- **Koexistenz-Check**: vorhandene Dev-Registrierung derselben Plugin-BPL
  unter anderem Pfad wird gemeldet und entfernt (verhindert Doppel-Laden).
- **Disabled-Packages-Bereinigung**: ein frueherer "Can't load package →
  Nein"-Eintrag wuerde die frische Installation sonst stumm blockieren.
- **Deinstallation**: Registry-Werte werden VOR den Dateien entfernt
  (`uninsdeletevalue` + expliziter `usUninstall`-Handler).
- **Privacy-Gate**: keinerlei Netzwerk-Code; Zusicherung steht sichtbar auf
  der Willkommensseite (de/en).

## 4. Testmatrix (D12-Teilmenge von Konzept §9; D13-Zeilen entfallen bis P2)

| # | Umgebung / Szenario | Erwartung |
|---|---------------------|-----------|
| 1 | Frische VM, D12 installiert, Non-Admin-Konto | Setup laeuft ohne UAC-Prompt durch; BPL unter `%LOCALAPPDATA%\Programs\StaticCodeAnalyser\bpl\d12\`; `Known Packages`-Wert vorhanden, Wertdaten nicht leer |
| 2 | IDE-Start nach Install | Plugin laedt (Splash/About-Branding sichtbar, Tools-Menue-Eintrag da); kein "Can't load package" |
| 3 | Setup starten, waehrend bds.exe laeuft | Setup bricht mit klarer Meldung ab (kein Teil-Install) |
| 4 | Dev-Maschine mit manuell registrierter Dev-BPL (Public-Documents-Bpl) | Koexistenz-Hinweis erscheint; nach Install existiert nur noch der Install-Pfad-Eintrag; IDE laedt das Plugin genau einmal |
| 5 | Vorher per "Can't load package → Nein" deaktiviert (Disabled Packages) | Setup raeumt den Disabled-Eintrag; Plugin laedt nach Neustart wieder |
| 6 | Update ueber Bestand (aeltere Version installiert) | BPL + `rules\sca-rules.json` ueberschrieben; genau ein Registry-Eintrag; keine Duplikate |
| 7 | Silent-Install `StaticCodeAnalyserSetup-*.exe /VERYSILENT /NORESTART` | identisches Ergebnis wie #1; Exit-Code 0 |
| 8 | Deinstallation (IDE zu) | Registry-Werte weg (Known + Disabled Packages), danach Dateien weg; IDE startet sauber ohne Fehlermeldung |
| 9 | **Privacy-Netzwerk-Gate**: Install + IDE-Session unter Netzwerk-Monitor (z. B. lokale Firewall-Logs) | 0 ausgehende Verbindungen von Setup und Plugin |
| 10 | Variante B: Registry-Ladereihenfolge | `SCA.Engine.bpl`/`SCA.SharedUI.bpl`-Eintraege vorhanden; IDE-Start ohne "Modul nicht gefunden"; falls doch: Monolith-Variante vorziehen (bekannte Grenze der Uebergangsloesung) |

Manuelle Verifikation gehoert dem User am gebauten Plugin (Doku-Leitplanke:
Plugin-Interaktion ist nicht headless verifizierbar).

## 5. Bekannte Grenzen / Ausblick

- **D13 (BDS 37.0, Suffix 370, `Known Packages x64`)**: komplett geblockt bis
  zur D13-Beschaffung; Platzhalter-Sektion im `.iss` ist vorbereitet und
  auskommentiert. 32-bit-BPL laedt nie in der 64-bit-IDE → eigene Win64-BPL.
- **D12.3-64-bit-IDE ist in v1 bewusst ausgeschlossen** (Doku Punkt 12).
- Notfall-/Diagnose-Skripte (`sca-disable-plugin.cmd`) sind P3-Umfang, nicht P1.
- Signing/EULA haengen an der offenen Lizenzmodell-Entscheidung (Doku Punkt 9).

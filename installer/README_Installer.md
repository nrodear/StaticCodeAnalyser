# Installer - Bauanleitung (D12- und D13-Schiene)

## 0. Community-Buttons + unterstützte Delphi-Versionen

**Buttons unten links im Wizard** (Vorbild: Inno-Setup-eigener Installer;
Klick öffnet den Standard-Browser, das Setup selbst bleibt netzfrei):

- **PayPal Donate** → `https://paypal.me/nrodear` (User-Festlegung
  2026-08-15; Default im `.iss` als `SCADonateUrl`, per
  `/DSCADonateUrl=...` überschreibbar, leer = Button ausgeblendet)
- **Star on GitHub** → `https://github.com/nrodear/StaticCodeAnalyser`

**Unterstützungs-Matrix Delphi-IDE-Versionen** (Stand 2026-08-23;
BPLs sind compiler-versionsgebunden — eine D12-BPL lädt NUR in BDS 23.0):

| Delphi | BDS | IDE-Bitness | Plugin-BPL | Registry-Schlüssel (HKCU) | Setup-Stand |
|---|---|---|---|---|---|
| ≤ 11 Alexandria | ≤ 22.0 | 32-bit | — | — | **NICHT unterstützt** (bewusste Entscheidung: Editor-Integration nutzt die RAD-Studio-12-ToolsAPI; D11 im Konzept 2026-07-23 abgelehnt) |
| 12.0–12.2 Athens | 23.0 | 32-bit | `StaticCodeAnalyser.Plugin.d12.bpl` (Win32) | `...\BDS\23.0\Known Packages` | **UNTERSTÜTZT — aktueller Release-Weg** |
| 12.3 Athens | 23.0 | 32-bit-IDE | dieselbe Win32-BPL | wie oben | **UNTERSTÜTZT** (die 32-bit-IDE von 12.3 ist identisch registriert) |
| 12.x Athens | 23.0 | **64-bit-IDE** | — | — | **GIBT ES NICHT.** Delphi 12 bringt keine 64-bit-IDE mit: kein `23.0\bin64\bds.exe`, keine `dcl*`-BPL in `bin64`, und `designide` existiert nur für Win32 (`23.0\lib\win64\release` hat 96 DCPs, designide ist keines davon). Ein Win64-Entwurfszeitpaket lässt sich dort nicht einmal bauen. Der frühere `/DSCA_D12_X64`-Zweig ist am 2026-08-23 entfernt worden |
| 13 Florence | **37.0** (Nummernsprung!) | 32-bit | `StaticCodeAnalyser.Plugin.d12.bpl` (Win32), Ziel `{app}\bpl\d13` | `...\BDS\37.0\Known Packages` | **UNTERSTÜTZT** seit 0.9.17 |
| 13 Florence | 37.0 | **64-bit-IDE** | dieselbe .dpk, Win64 gebaut, Ziel `{app}\bpl\d13x64` | `...\BDS\37.0\Known Packages x64` | **UNTERSTÜTZT** seit 0.9.17. Unterschieden wird über den Zielordner, nicht über den Dateinamen — EIN Projektsatz baut beide Generationen |

Warum keine älteren Versionen: neben der ToolsAPI-Grenze ist jede BPL an
ihre Compiler-Version gebunden — Unterstützung einer weiteren Delphi-
Version heißt immer: eigener Projektsatz, eigener Build, eigene
Registry-Schiene. Ungetestete Schienen werden nicht ins Setup
aufgenommen (lieber ehrlich „nicht unterstützt" als still kaputt).


> Referenz: Welle 1, 2026-07-25 | Grundlage: Doku_05_IDE_Plugin.md (Installer-Abschnitt),
> Konzept_IdePluginInstaller_2026-07-23. *Hier stand bis 2026-08-24, D13 sei
> GEBLOCKT und nur ein auskommentierter Platzhalter - das widersprach der
> Tabelle direkt darueber. Seit 0.9.17 ist die D13-Schiene ausgeliefert.*

## 1. Was zu bauen ist (in der IDE — kein msbuild/dcc32, kein RemoteDelphi)

Ziel-IDE: **Delphi 12 (BDS 23.0), Plattform Win32, Konfiguration Release**.

### Variante A — Release-Ziel (Default seit 2026-08-14)

Monolith-Package `StaticCodeAnalyserIDE\StaticCodeAnalyser.Plugin.d12.dpk`
(+ .dproj; requires nur `rtl, vcl, vclwinx, designide, xmlrtl`; enthaelt
ALLE 268 Units von Engine + SharedUI + IDE). In der IDE als
**Release/Win32** bauen — die BPL landet im D12-Standard-BPL-Ordner.
`SCA_MONOLITH` ist im `.iss` seit 2026-08-14 AKTIV (Release-Default).
WICHTIG: Die Monolith-BPL nie zusammen mit dem Dev-3-Package-Satz in
derselben IDE registrieren (gleiche Units doppelt) — auf der Dev-Maschine
bleibt der 3er-Satz, die Monolith-BPL wird nur GEBAUT, nicht registriert;
der Installer-Koexistenz-Check schuetzt Endanwender-Maschinen.

Warum Monolith: der Windows-Loader loest `requires` per Modulname ueber
bds.exe-Verzeichnis → System32 → PATH auf, **nicht** im BPL-Verzeichnis.
Drei separate BPLs in einem privaten Installationsordner sind daher nicht
direkt ladbar.

### Variante B — Dev-3-BPL-Satz (nur noch per Kommandozeile ohne SCA_MONOLITH)

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
  `uIDEExpert.PLUGIN_VERSION`, dproj-`VerInfo` synchronisieren (der
  fruehere 0/9/4-vs-0.9.8.0-Drift ist historisch, seit 0.9.10 behoben);
  danach `#define SCAVersion` im `.iss` nachziehen.
- Verwaisten `SCA.Refactor.bpl`-Eintrag in der Dev-Registry bereinigen
  (Doku Punkt 4) — der Koexistenz-Check des Setups fasst nur Plugin-BPL-Namen an.
- Frischeste-Binaries-Check: User wechselt Win32/Win64 — sicherstellen, dass
  die neueste BPL wirklich aus einem Win32-Release-Build stammt.

## 2. Inno-Compile-Schritt

Voraussetzung: **Inno Setup 6.x** (ISCC.exe im PATH oder voller Pfad).

**Regelweg seit 2026-08-14: `tools\package-release.ps1` baut das Setup
mit** (Schritt "setup": prueft die BPL-VERSIONINFO gegen die Release-
Version, ruft ISCC mit `/DSCAVersion=<Version>.0` und legt
`StaticCodeAnalyserSetup-<Version>.0.exe` zu den uebrigen Assets in
`release-artifacts\`; Opt-out per `-SkipInstaller`).

Hand-Compile weiterhin moeglich:

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
  `%LOCALAPPDATA%\Programs\StaticCodeAnalyser\bpl\<variante>\`, Registrierung
  unter `HKCU\Software\Embarcadero\BDS\<gen>\Known Packages` (Wertname =
  voller BPL-Pfad, Wertdaten nie leer). Drei Ziele seit 0.9.17:

  | Variante | Datei nach | Registry-Zweig |
  |---|---|---|
  | Delphi 12, 32-Bit-IDE | `bpl\d12` | `BDS\23.0\Known Packages` |
  | Delphi 13, 32-Bit-IDE | `bpl\d13` | `BDS\37.0\Known Packages` |
  | Delphi 13, 64-Bit-IDE | `bpl\d13x64` | `BDS\37.0\Known Packages x64` |

- **Versionsauswahl auf einer eigenen Wizard-Seite**: Das Setup listet nur
  die Varianten, deren IDE es auf dem Rechner tatsaechlich findet - jeder
  `[Components]`-Eintrag traegt eine `Check:`-Bedingung. Installiert wird
  ausschliesslich das Angehakte. Wer eine zuvor installierte Variante
  aushakt, wird sie los: Registrierung, Datei, Ordner - in dieser
  Reihenfolge. Eine leere Auswahl blockt `NextButtonClick` mit Meldung ab,
  statt ein Setup ohne Wirkung durchlaufen zu lassen.
- **IDE-Prozess-Check** vor Install und Uninstall (TAppBuilder-Fenster).
- **Koexistenz-Check, je Registry-Zweig einzeln**: eine vorhandene
  Dev-Registrierung derselben Plugin-BPL unter anderem Pfad wird gemeldet
  und entfernt (verhindert Doppel-Laden). Geprueft wird nur in den Zweigen
  angehakter Varianten - einen Zweig, den das Setup gar nicht bespielt,
  fasst es auch nicht an. *Bis 2026-08-23 lief dieser Check fest gegen
  `BDS\23.0` und sah die D13-Schiene deshalb nicht; genau daran ist das
  Plugin unter Delphi 13 gescheitert.*
- **Disabled-Packages-Bereinigung**: ein frueherer "Can't load package →
  Nein"-Eintrag wuerde die frische Installation sonst stumm blockieren.
- **Deinstallation**: Registry-Werte werden VOR den Dateien entfernt
  (`uninsdeletevalue` + expliziter `usUninstall`-Handler), und zwar in
  allen drei Zweigen - unabhaengig davon, was diese Installation gesetzt
  hat. `[UninstallDelete]` raeumt danach `bpl\d12`, `bpl\d13`,
  `bpl\d13x64` und den dann leeren `bpl`-Ordner ab.
- **Privacy-Gate**: keinerlei Netzwerk-Code; Zusicherung steht sichtbar auf
  der Willkommensseite (de/en).
- **Sprachauswahl** Deutsch/Englisch beim Setup-Start.
- **MIT-Lizenzseite**: das Setup zeigt die Lizenz (`LICENSE` im Repo-Root)
  als Lizenzseite an.
- **PayPal-/GitHub-Buttons** im Setup (Spenden- bzw. Projektlink).
- **Startmenue-Eintrag fuer den Deinstaller** (unins000.exe war sonst
  unauffindbar).
- **Ready-Seite** mit Versions-Matrix; die installierbare Version ist
  fett hervorgehoben (TRichEditViewer + RTF, Memo als Fallback).

## 4. Testmatrix (aus Konzept §9)

| # | Umgebung / Szenario | Erwartung |
|---|---------------------|-----------|
| 1 | Frische VM, D12 installiert, Non-Admin-Konto | Setup laeuft ohne UAC-Prompt durch; BPL unter `%LOCALAPPDATA%\Programs\StaticCodeAnalyser\bpl\d12\`; `Known Packages`-Wert vorhanden, Wertdaten nicht leer |
| 2 | IDE-Start nach Install | Plugin laedt (Splash/About-Branding sichtbar, Tools-Menue-Eintrag da); kein "Can't load package" |
| 3 | Setup starten, waehrend bds.exe laeuft | Setup bricht mit klarer Meldung ab (kein Teil-Install) |
| 3b | Maschine OHNE Delphi 12 (kein BDS 23.0 bzw. RootDir ohne bin\bds.exe) | Setup bricht VOR der Installation mit "Delphi 12 wurde nicht gefunden" ab; keine Dateien, keine Registry-Werte |
| 4 | Dev-Maschine mit manuell registrierter Dev-BPL (Public-Documents-Bpl) | Koexistenz-Hinweis erscheint; nach Install existiert nur noch der Install-Pfad-Eintrag; IDE laedt das Plugin genau einmal |
| 5 | Vorher per "Can't load package → Nein" deaktiviert (Disabled Packages) | Setup raeumt den Disabled-Eintrag; Plugin laedt nach Neustart wieder |
| 6 | Update ueber Bestand (aeltere Version installiert) | BPL + `rules\sca-rules.json` ueberschrieben; genau ein Registry-Eintrag; keine Duplikate |
| 7 | Silent-Install `StaticCodeAnalyserSetup-*.exe /VERYSILENT /NORESTART` | identisches Ergebnis wie #1; Exit-Code 0 |
| 8 | Deinstallation (IDE zu) | Registry-Werte weg (Known + Disabled Packages), danach Dateien weg; IDE startet sauber ohne Fehlermeldung |
| 9 | **Privacy-Netzwerk-Gate**: Install + IDE-Session unter Netzwerk-Monitor (z. B. lokale Firewall-Logs) | 0 ausgehende Verbindungen von Setup und Plugin |
| 10 | Variante B: Registry-Ladereihenfolge | `SCA.Engine.bpl`/`SCA.SharedUI.bpl`-Eintraege vorhanden; IDE-Start ohne "Modul nicht gefunden"; falls doch: Monolith-Variante vorziehen (bekannte Grenze der Uebergangsloesung) |

Die Tabelle ist an der D12-Schiene entstanden; zwischen den Varianten
unterscheiden sich Registry-Zweig und Zielordner, der Ablauf nicht. Am
2026-08-23 hat der User alle drei Varianten von Hand durchgespielt,
Installation und Deinstallation je sauber.

Manuelle Verifikation gehoert dem User am gebauten Plugin (Doku-Leitplanke:
Plugin-Interaktion ist nicht headless verifizierbar).

## 5. Bekannte Grenzen / Ausblick

- **D13 (BDS 37.0) ist seit 0.9.17 ausgeliefert**, 32- und 64-Bit.
  *Hier standen bis 2026-08-24 eine "auskommentierte Platzhalter-Sektion"
  und zwei offene Punkte. Beide sind entschieden:* der Projektsatz bleibt
  **einer** - kein `LIBSUFFIX`, unterschieden wird ueber den Zielordner
  (`bpl\d12` / `bpl\d13` / `bpl\d13x64`), nicht ueber den Dateinamen; und
  `StaticCodeAnalyser.Plugin.d12.dproj` steht auf `TargetedPlatforms=3`,
  baut also Win32 und Win64 aus derselben Projektdatei. Ungeprueft bleibt
  allein, ob die Edition "Starter" fuer den GetIt-Lokaltest genuegt.
- **Eine 64-Bit-IDE von Delphi 12 gibt es nicht.** Gemessen, nicht
  vermutet: unter `Studio\23.0` fehlt `bin64\bds.exe`, dort liegen 0
  `dcl*`-BPLs, und `designide` existiert fuer Win64 ueberhaupt nicht (96
  DCPs im Win64-Ordner, `designide` nicht darunter). Ein 64-Bit-Plugin ist
  unter D12 also nicht "in v1 ausgeschlossen", wie es hier vorher hiess,
  sondern nicht baubar - die `.dpk` faengt den Versuch mit
  `{$MESSAGE FATAL}` und lesbarem Text ab.
- Notfall-/Diagnose-Skripte (`sca-disable-plugin.cmd`) sind P3-Umfang, nicht P1.
- Lizenz: MIT (entschieden 2026-08-15); Code-Signing weiterhin offen
  (Zertifikatsfrage).

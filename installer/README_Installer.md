# Installer - Bauanleitung (D12- und D13-Schiene)

## 0. Community-Buttons + unterstützte Delphi-Versionen

**Buttons unten links im Wizard** (Vorbild: Inno-Setup-eigener Installer;
Klick öffnet den Standard-Browser, das Setup selbst bleibt netzfrei):

- **PayPal Donate** → `https://paypal.me/nrodear` (User-Festlegung
  2026-08-15; Default im `.iss` als `SCADonateUrl`, per
  `/DSCADonateUrl=...` überschreibbar, leer = Button ausgeblendet)
- **Star on GitHub** → `https://github.com/nrodear/StaticCodeAnalyser`

**Unterstützungs-Matrix Delphi-IDE-Versionen** (Stand 0.9.19;
BPLs sind compiler-versionsgebunden — eine D12-BPL lädt NUR in BDS 23.0):

| Delphi | BDS | IDE-Bitness | Paketsatz (vier BPLs) | Registry-Schlüssel (HKCU) | Setup-Stand |
|---|---|---|---|---|---|
| ≤ 11 Alexandria | ≤ 22.0 | 32-bit | — | — | **NICHT unterstützt** (bewusste Entscheidung: Editor-Integration nutzt die RAD-Studio-12-ToolsAPI; D11 im Konzept 2026-07-23 abgelehnt) |
| 12.0–12.2 Athens | 23.0 | 32-bit | `SCA.Engine290`, `SCA.SharedUI290`, `StaticCodeAnalyser.IDE.d12`, `reDelphix.d12` (Win32), Ziel `{app}\bpl\d12` | `...\BDS\23.0\Known Packages` | **UNTERSTÜTZT** |
| 12.3 Athens | 23.0 | 32-bit-IDE | dieselben Win32-BPLs | wie oben | **UNTERSTÜTZT** (die 32-bit-IDE von 12.3 ist identisch registriert) |
| 12.x Athens | 23.0 | **64-bit-IDE** | — | — | **GIBT ES NICHT.** Delphi 12 bringt keine 64-bit-IDE mit: kein `23.0\bin64\bds.exe`, keine `dcl*`-BPL in `bin64`, und `designide` existiert nur für Win32 (`23.0\lib\win64\release` hat 96 DCPs, designide ist keines davon). Ein Win64-Entwurfszeitpaket lässt sich dort nicht einmal bauen. Der frühere `/DSCA_D12_X64`-Zweig ist am 2026-08-23 entfernt worden |
| 13 Florence | **37.0** (Nummernsprung!) | 32-bit | `SCA.Engine370`, `SCA.SharedUI370`, `StaticCodeAnalyser.IDE.d12`, `reDelphix.d12` (Win32), Ziel `{app}\bpl\d13` | `...\BDS\37.0\Known Packages` | **UNTERSTÜTZT** seit 0.9.17 |
| 13 Florence | 37.0 | **64-bit-IDE** | dieselben Dateinamen, Win64 gebaut, Ziel `{app}\bpl\d13x64` | `...\BDS\37.0\Known Packages x64` | **UNTERSTÜTZT** seit 0.9.17. Unterschieden wird über den Zielordner, nicht über den Dateinamen — EIN Projektsatz baut beide Generationen |

Warum keine älteren Versionen: neben der ToolsAPI-Grenze ist jede BPL an
ihre Compiler-Version gebunden — Unterstützung einer weiteren Delphi-
Version heißt immer: eigener Build, eigene Registry-Schiene, eigener
Ordner im IDE-PATH. Ungetestete Schienen werden nicht ins Setup
aufgenommen (lieber ehrlich „nicht unterstützt" als still kaputt).


> Referenz: Welle 1, 2026-07-25 | Grundlage: Doku_05_IDE_Plugin.md (Installer-Abschnitt),
> Konzept_IdePluginInstaller_2026-07-23. *Hier stand bis 2026-08-24, D13 sei
> GEBLOCKT und nur ein auskommentierter Platzhalter - das widersprach der
> Tabelle direkt darueber. Seit 0.9.17 ist die D13-Schiene ausgeliefert.*

## 1. Was zu bauen ist (in der IDE — kein msbuild/dcc32, kein RemoteDelphi)

Ausgeliefert wird seit 0.9.19 der **Paketsatz**, den auch der Dev-Bau erzeugt:
vier Pakete auf drei Schienen, zusammen 12 BPLs, Konfiguration **Release**.

Je Schiene in dieser Reihenfolge bauen:

| # | Projekt | erzeugte BPL | Art |
|---|---------|--------------|-----|
| 1 | `SCA.Engine\SCA.Engine.dproj` | `SCA.Engine<suffix>.bpl` | Laufzeitpaket (`{$RUNONLY}`) |
| 2 | `SCA.SharedUI\SCA.SharedUI.dproj` | `SCA.SharedUI<suffix>.bpl` | Laufzeitpaket (`{$RUNONLY}`), requires Engine |
| 3 | `StaticCodeAnalyserIDE\StaticCodeAnalyser.IDE.d12.dproj` | `StaticCodeAnalyser.IDE.d12.bpl` | Design-Paket, requires Engine + SharedUI |
| 4 | `reDelphix\reDelphix.d12.dproj` | `reDelphix.d12.bpl` | Design-Paket, requires Engine |

Die drei Schienen, BPL-Ausgabeort jeweils unter
`C:\Users\Public\Documents\Embarcadero\Studio\`:

| Schiene | IDE | Suffix | BPL-Ausgabeort | ISCC-Define |
|---|---|---|---|---|
| D12 Win32 | Delphi 12 (BDS 23.0) | `290` | `23.0\Bpl` | `SCABplSourceDir` |
| D13 Win32 | Delphi 13 (BDS 37.0) | `370` | `37.0\Bpl` | `SCABplSourceDirD13` |
| D13 Win64 | Delphi 13 (BDS 37.0) | `370` | `37.0\Bpl\Win64` | `SCABplSourceDirD13X64` |

EIN Projektsatz baut alle drei Schienen, dieselben `.dproj` in beiden IDEs;
auch `d12` im Namen der Design-Pakete gilt fuer beide Generationen. Die dproj
setzen **kein** `DCC_BplOutput`, die BPLs landen im Standardordner der
jeweiligen IDE (genau dorthin zeigen die `.iss`-Defaults). Win64 unter Delphi
12 faengt `{$MESSAGE FATAL}` in beiden Design-dpk ab.

**Nach dem Merge aus dem Release-Checkout bauen.** `package-release.ps1` nimmt
Gates, Quellen und EXEs aus dem Checkout, in dem es liegt, und
`tools\stale_artifacts_check.py --release` bricht ab, sobald dort eine Quelle
juenger ist als ihr DCP. Ein Bau vor dem Merge oder aus einem anderen Worktree
zeigt ausserdem nicht den Stand, der getaggt wird.

### Warum der Paketsatz einen eigenen Ladeweg braucht

Der Windows-Loader loest `requires` per Modulname ueber
bds.exe-Verzeichnis → System32 → PATH auf, **nicht** im BPL-Verzeichnis, und
ein `{$RUNONLY}`-Paket darf nicht in die Known Packages. Deshalb stehen nur die
beiden Design-BPLs dort (voller Pfad), und das Setup legt `{app}\bpl\<schiene>`
vorn in den IDE-eigenen Override
`HKCU\Software\Embarcadero\BDS\<bds>\Environment Variables\PATH`. Am 2026-10-28
gemessen: die IDE uebernimmt ihn vor dem Laden der Known Packages, auch
`bin64\bds.exe`, und der 64-Bit-Loader ueberspringt gleichnamige 32-Bit-Dateien.

Bis 0.9.18 ging das Setup diesen Weg nicht und lieferte den Monolithen
`StaticCodeAnalyser.Plugin.d12` (eine BPL mit den Units von Engine, SharedUI und
IDE-Paket, ohne reDelphix). Der liegt noch im Repo, gehoert aber nicht mehr zum
Release. Das Setup kennt ihn nur noch, um Reste zu entfernen (Abschnitt 3);
`monolith_parity_gate.py` und der Pfad `-SkipGetIt:$false` sind Altlast fuer
Entwickler.

### Vor dem Release (Checkliste aus der Doku)

- **Versions-Sync** (Doku Punkt 3): `uSCAConsts.SCA_VERSION`,
  `uIDEExpert.PLUGIN_VERSION`, dproj-`VerInfo` synchronisieren, bei den vier
  Paket-dproj je Win32 UND Win64, Keys und numerische Felder (der
  fruehere 0/9/4-vs-0.9.8.0-Drift ist historisch, seit 0.9.10 behoben);
  danach `#define SCAVersion` im `.iss` nachziehen.
  `tools\package_set_gate.py --version <v>` prueft die Paket-dproj.
- Verwaisten `SCA.Refactor.bpl`-Eintrag in der Dev-Registry bereinigen
  (Doku Punkt 4) — der Koexistenz-Check des Setups fasst nur die SCA-Familie
  an (Abschnitt 3), `SCA.Refactor` gehoert nicht dazu.
- Frischeste-Binaries-Check: User wechselt Win32/Win64 — gleichnamige BPLs
  unterscheidet nur der Ordner. `package-release.ps1` prueft deshalb je BPL
  die PE-Machine.

## 2. Inno-Compile-Schritt

Voraussetzung: **Inno Setup 6.x** (ISCC.exe im PATH oder voller Pfad).

**Regelweg seit 2026-08-14: `tools\package-release.ps1` baut das Setup
mit** (Schritt "setup": ruft ISCC mit `/DSCAVersion=<Version>.0` und den drei
Quellordnern und legt `StaticCodeAnalyserSetup-<Version>.0.exe` zu den
uebrigen Assets in `release-artifacts\`).

Vorbedingungen, die vor jedem Dateizugriff laufen. Das Skript sammelt alle
Befunde und bricht erst dann ab; angelegt oder geraeumt ist bis dahin nichts:

- `tools\package_set_gate.py --version <Version>`: jede Unit in genau einem
  Paket, requires-Graph, Pakettyp in `.dpk` und `.dproj`, LIBSUFFIX nur an
  RUNONLY-Paketen, Plattformen + Win64-Sperre, VerInfo == Release-Version.
- `tools\stale_artifacts_check.py --release`: jedes DCP der vier Pakete auf
  den drei Schienen ist juenger als seine Quelle.
- Je BPL der 12: vorhanden, VERSIONINFO als Text und als Zahlen gleich der
  Release-Version, PE-Machine passend zur Schiene (014C bzw. 8664).

Schalter:

- `-DryRun`: nur diese Vorbedingungen, danach Ende. Die EXEs prueft erst der
  echte Lauf.
- `-SkipInstaller`: laesst den Setup-Schritt und die Vorbedingungen aus.
- `-SkipGetIt` ist Default, GetIt ist fuer 0.9.19 ausgesetzt
  (`getit\README_GetIt.md`). `-SkipGetIt:$false` nimmt den Monolithen, braucht
  dessen gebaute BPL und ist kein Releaseweg.

Hand-Compile weiterhin moeglich:

```bat
cd /d d:\git-demos\delphi\StaticCodeAnalyser\installer
iscc StaticCodeAnalyserSetup.iss
```

Optionen:

```bat
:: abweichende BPL-Quellordner (z. B. dedizierter Release-Staging-Ordner):
iscc /DSCABplSourceDir="D:\release\d12" /DSCABplSourceDirD13="D:\release\d13" ^
     /DSCABplSourceDirD13X64="D:\release\d13x64" StaticCodeAnalyserSetup.iss
```

Output: `installer\Output\StaticCodeAnalyserSetup-<Version>.exe`.

Der Regelkatalog `rules\sca-rules.json` wird relativ zum Repo (`SCARepoRoot`,
Default `..\`) eingesammelt und nach `{app}\rules` installiert. Hinweis fuer
die Nutzer-Doku (Doku Punkt 10): die Install-Kopie gewinnt vor der
APPDATA-Kopie; eigene Regeln via `CustomRulesFile`-Setting pflegen, der
Installer ueberschreibt `rules\sca-rules.json` bei jedem Update.

## 3. Was der Installer tut

- **Per-User, nie elevated** (`PrivilegesRequired=lowest`): Dateien nach
  `%LOCALAPPDATA%\Programs\StaticCodeAnalyser\bpl\<schiene>\`, Registrierung
  unter `HKCU\Software\Embarcadero\BDS\<gen>\Known Packages` (Wertname =
  voller BPL-Pfad, Wertdaten nie leer). Drei Ziele seit 0.9.17, je Ziel vier
  BPLs seit 0.9.19:

  | Schiene | Dateien nach | Registry-Zweig | PATH-Override |
  |---|---|---|---|
  | Delphi 12, 32-Bit-IDE | `bpl\d12` | `BDS\23.0\Known Packages` | `BDS\23.0\Environment Variables`, Wert `PATH` |
  | Delphi 13, 32-Bit-IDE | `bpl\d13` | `BDS\37.0\Known Packages` | `BDS\37.0\Environment Variables`, Wert `PATH` |
  | Delphi 13, 64-Bit-IDE | `bpl\d13x64` | `BDS\37.0\Known Packages x64` | derselbe Wert wie die 32-Bit-IDE |

  In den Known Packages stehen nur `StaticCodeAnalyser.IDE.d12.bpl` und
  `reDelphix.d12.bpl`, nie die Laufzeitpakete.
- **IDE-PATH-Override**: das Setup setzt `{app}\bpl\<schiene>` vorn in den
  Wert. Er ist geteilt (InterBase traegt dort z. B. `...\IDE_spoof;$(PATH)`):
  nur das eigene Segment wird bewegt, alles andere bleibt Zeichen fuer
  Zeichen. Das Segment wird immer entnommen und vorn eingesetzt, eine
  Doppelinstallation aendert den Wert also nicht. Fehlt der Wert, entsteht
  er als `<segment>;$(PATH)`. Unter BDS 37.0 teilen sich beide Schienen den
  Wert, `bpl\d13` steht vor `bpl\d13x64`. Scheitert das Schreiben, meldet das
  Setup es: ohne den Eintrag laedt das Plugin beim IDE-Start nicht.
- **reDelphix als eigene Komponente** (`redelphix`): vorgewaehlt, abwaehlbar,
  gilt fuer alle gewaehlten Schienen; das IDE-Paket haengt nicht davon ab.
  Die Abwahl entfernt je Schiene die Registrierung (Known + Disabled) und
  `reDelphix.d12.bpl`, Laufzeitpakete und Override bleiben. Kennt die von Inno
  gespeicherte Auswahl reDelphix noch nicht (Upgrade von 0.9.18), waehlt das
  Setup es vor; eine echte Abwahl aus einem spaeteren Lauf bleibt bestehen.
- **Monolith-Bereinigung beim Upgrade**: Reste von
  `StaticCodeAnalyser.Plugin.d12.bpl` aus einer Installation bis 0.9.18 werden
  entfernt, die Known- und Disabled-Werte aller drei Zweige, auch abgewaehlter,
  und die Datei im eigenen `bpl\<schiene>`. Es zaehlt der Dateiname, nicht der
  Pfad; so faellt auch die Registrierung eines GetIt-Pakets mit
  `%Makro%`-Wertnamen. Dessen Dateien im GetIt-Katalog bleiben liegen.
  Treffer meldet das Setup in einem Hinweis.

- **Versionsauswahl auf einer eigenen Wizard-Seite**: Das Setup listet nur
  die Varianten, deren IDE es auf dem Rechner tatsaechlich findet - jeder
  `[Components]`-Eintrag traegt eine `Check:`-Bedingung. Installiert wird
  ausschliesslich das Angehakte. Wer eine zuvor installierte Variante
  aushakt, wird sie los: Registrierung, Override-Segment, Dateien, Ordner -
  in dieser Reihenfolge. Eine Auswahl ohne Delphi-Version blockt
  `NextButtonClick` mit Meldung ab, statt ein Setup ohne Wirkung durchlaufen
  zu lassen.
- **IDE-Prozess-Check** vor Install und Uninstall (TAppBuilder-Fenster).
- **Koexistenz-Check, je Registry-Zweig einzeln**: eine Registrierung der
  SCA-Familie (`SCA.Engine*` und `SCA.SharedUI*` mit oder ohne Versionssuffix,
  `StaticCodeAnalyser.IDE.d12`, `reDelphix.d12`, Monolith) unter anderem Pfad
  wird gemeldet und entfernt (verhindert Doppel-Laden). Wer nach der
  Deinstallation wieder einen eigenen Bau nutzt, traegt ihn neu ein
  (`HowTo_Build.md`, 5.2 und 5.3). Geprueft wird nur in den Zweigen
  angehakter Varianten - einen Zweig, den das Setup gar nicht bespielt,
  fasst es auch nicht an. *Bis 2026-08-23 lief dieser Check fest gegen
  `BDS\23.0` und sah die D13-Schiene deshalb nicht; genau daran ist das
  Plugin unter Delphi 13 gescheitert.*
- **Disabled-Packages-Bereinigung**: ein frueherer "Can't load package →
  Nein"-Eintrag wuerde die frische Installation sonst stumm blockieren. Gilt
  fuer beide Design-BPLs.
- **Hinweise im Silent-Lauf**: Koexistenz-, Monolith- und Override-Meldungen
  stehen dort nur im Log, kein Dialog haelt den Lauf an.
- **Deinstallation**: Registry-Werte werden VOR den Dateien entfernt
  (`uninsdeletevalue` + expliziter `usUninstall`-Handler), und zwar in
  allen drei Zweigen - unabhaengig davon, was diese Installation gesetzt
  hat. Der Handler nimmt auch die Override-Segmente heraus, und nur diese:
  fremde Segmente bleiben. Bleibt vom Wert nichts oder nur `$(PATH)` uebrig,
  verschwindet er, der Schluessel mit, wenn er dann leer ist.
  `[UninstallDelete]` raeumt danach `bpl\d12`, `bpl\d13`,
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
  fett hervorgehoben (TRichEditViewer + RTF, Memo als Fallback). Darunter
  der Hinweis auf den PATH-Eintrag (Tools > Optionen > IDE >
  Umgebungsvariablen) und die gewaehlten Komponenten.

## 4. Testmatrix (aus Konzept §9)

| # | Umgebung / Szenario | Erwartung |
|---|---------------------|-----------|
| 1 | Frische VM, D12 installiert, Non-Admin-Konto | Setup laeuft ohne UAC-Prompt durch; vier BPLs unter `%LOCALAPPDATA%\Programs\StaticCodeAnalyser\bpl\d12\`; `Known Packages`-Werte nur fuer `StaticCodeAnalyser.IDE.d12.bpl` und `reDelphix.d12.bpl`, Wertdaten nicht leer; `{app}\bpl\d12` vorn im IDE-PATH-Override |
| 2 | IDE-Start nach Install | Plugin laedt (Splash/About-Branding sichtbar, Tools-Menue-Eintrag da); kein "Can't load package"; Engine und SharedUI laden aus `{app}\bpl\d12` |
| 3 | Setup starten, waehrend bds.exe laeuft | Setup bricht mit klarer Meldung ab (kein Teil-Install) |
| 3b | Maschine OHNE unterstuetzte IDE (weder BDS 23.0 noch 37.0, oder RootDir ohne bin\bds.exe) | Setup bricht VOR der Installation mit "weder Delphi 12 noch Delphi 13 gefunden" ab; keine Dateien, keine Registry-Werte |
| 4 | Dev-Maschine mit registriertem Dev-Satz (Public-Documents-Bpl) | Koexistenz-Hinweis erscheint; nach Install existieren nur noch die Install-Pfad-Eintraege; IDE laedt das Plugin genau einmal |
| 5 | Vorher per "Can't load package → Nein" deaktiviert (Disabled Packages) | Setup raeumt den Disabled-Eintrag; Plugin laedt nach Neustart wieder |
| 6 | Update ueber Bestand (Paketsatz installiert, auch dasselbe Setup zweimal) | BPLs + `rules\sca-rules.json` ueberschrieben; genau ein Registry-Eintrag je Design-BPL; Override-Segment genau einmal |
| 6b | Upgrade vom 0.9.18-Monolithen, aus Setup und aus GetIt, alle drei Schienen | Hinweis erscheint; Monolith-Werte (Known + Disabled) weg, eigene Monolith-Datei weg; IDE-Start ohne "enthaelt die Unit ..."; reDelphix war vorgewaehlt |
| 7 | Silent-Install `StaticCodeAnalyserSetup-*.exe /VERYSILENT /NORESTART` | identisches Ergebnis wie #1; Exit-Code 0; Hinweise nur im Log |
| 8 | Deinstallation (IDE zu) | Registry-Werte weg (Known + Disabled Packages), Override-Wert im Ausgangszustand mit allen fremden Segmenten, danach Dateien weg; IDE startet sauber ohne Fehlermeldung |
| 9 | **Privacy-Netzwerk-Gate**: Install + IDE-Session unter Netzwerk-Monitor (z. B. lokale Firewall-Logs) | 0 ausgehende Verbindungen von Setup und Plugin |
| 10 | reDelphix am Fund | Gluehbirne erscheint, Quick-Fix schreibt, Strg+Z macht ihn rueckgaengig; Aktionen im Kontextmenue des Dock-Grids |
| 11 | reDelphix abwaehlen (Setup erneut) | `reDelphix.d12.bpl` und seine Registry-Werte weg, Plugin laedt weiter, Override bleibt |
| 12 | Eine Schiene abwaehlen (Setup erneut) | Dateien, Known-, Disabled-Werte und Override-Segment dieser Schiene weg |
| 13 | D12 und D13 gleichzeitig offen | jede IDE laedt ihre 290- bzw. 370-Fassung |
| 14 | Fremdbau: `SCA.CLI.Demo` samt Engine selbst gebaut, IDE neu starten | Plugin laedt weiter aus `{app}\bpl\<schiene>` |

Die Tabelle ist an der D12-Schiene entstanden; zwischen den Schienen
unterscheiden sich Registry-Zweig, Zielordner und Suffix, der Ablauf nicht.
Der Handdurchlauf vom 2026-08-23 ueber alle drei Schienen galt dem Monolithen;
fuer den Paketsatz wird die Matrix vor dem Release neu durchgespielt.

Manuelle Verifikation gehoert dem User am gebauten Plugin (Doku-Leitplanke:
Plugin-Interaktion ist nicht headless verifizierbar).

## 5. Bekannte Grenzen / Ausblick

- **D13 (BDS 37.0) ist seit 0.9.17 ausgeliefert**, 32- und 64-Bit.
  *Hier standen bis 2026-08-24 eine "auskommentierte Platzhalter-Sektion"
  und zwei offene Punkte. Beide sind entschieden:* der Projektsatz bleibt
  **einer**. Die Laufzeitpakete tragen `{$LIBSUFFIX AUTO}` (`290` bzw. `370`,
  Win32 und Win64 gleich), die Design-Pakete keinen Suffix; die Bitbreite
  unterscheidet der Zielordner (`bpl\d13` / `bpl\d13x64`). Alle vier `.dproj`
  stehen auf `TargetedPlatforms=3`, bauen also Win32 und Win64 aus derselben
  Projektdatei.
- **GetIt ist fuer 0.9.19 ausgesetzt**: der Paketsatz laesst sich darueber
  nicht installieren, Begruendung in `getit\README_GetIt.md`.
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

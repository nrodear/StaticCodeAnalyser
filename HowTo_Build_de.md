# HowTo: Bauen und installieren (Anfaenger-Anleitung)

Diese Anleitung fuehrt dich vom Stand "ich habe nichts" bis zu
"der Analyzer laeuft auf meinem Code". Sie ist fuer Leute geschrieben,
die **neu in Delphi** sind.

Am Ende hast du:
- die **Standalone-Windows-App** (`StaticCodeAnalyser.d12.exe`)
- das **IDE-Plugin** (laedt beim Start von Delphi 12)

> **Bauen ist optional.** Die GitHub-Releases liefern fertige EXE-Zips
> (Win32/Win64), eine Setup-EXE fuers IDE-Plugin und ein GetIt-Paket —
> siehe Quick-Start im README. Dieses Dokument ist fuer Leute, die
> selbst aus den Quellen bauen wollen.

🇬🇧 [English version](HowTo_Build.md) · 🇫🇷 [Version française](HowTo_Build_fr.md)

---

## 0. Was du brauchst

- **Windows 10 oder 11** (64-bit).
- **Ca. 25 GB freier Speicher** (RAD Studio ist gross).
- Eine **Internet-Verbindung** (fuer Download und git).
- Einen **Embarcadero-Account** (kostenlos).
- Ca. **45 Minuten** Zeit. Davon ist das meiste der RAD-Studio-Installer.

---

## 1. Delphi 12 installieren (RAD Studio)

Du brauchst **Delphi 12 Athens** (auch RAD Studio 12 genannt) — eine
der Versionen 12.0–12.3. Das Plugin laeuft in der 32-bit-IDE (die
64-bit-IDE von 12.3 wird noch nicht unterstuetzt); Delphi 13 ist
geplant, aber noch nicht unterstuetzt, Delphi 11 und aelter werden
nicht unterstuetzt. Die **kostenlose Community Edition** reicht.

1. Geh auf https://www.embarcadero.com/products/delphi/starter.
2. Klick auf **"Download Free Trial"** oder **"Community Edition"**.
3. Mit deinem Embarcadero-Account einloggen (oder einen anlegen).
4. Den Installer starten (`RADStudio_Athens_setup.exe`).
5. Auswahl:
   - **Personality:** Delphi (C++Builder brauchst du nicht).
   - **Platforms:** Windows 32-bit UND Windows 64-bit (beides!).
   - **Languages:** Englisch ist OK.
   - **Extras (optional):** GetIt-Package-Manager — Default lassen.
6. Warten. Der Download ist ~6 GB; die Installation belegt ~12 GB.
7. Nach der Installation **RAD Studio** starten. EULA beim ersten Start
   bestaetigen.

Du siehst jetzt die **Delphi-IDE** mit dem "Welcome"-Tab. Schliesse
geoeffnete Beispiel-Projekte.

---

## 2. Dieses Projekt von GitHub laden

Du brauchst **git fuer Windows**: https://git-scm.com/download/win.

Oeffne **Command Prompt** oder **PowerShell** in dem Ordner, in dem
du deinen Code haelst, und tippe:

```cmd
cd D:\projects
git clone https://github.com/nrodear/StaticCodeAnalyser.git
cd StaticCodeAnalyser
```

Du kannst jeden Pfad nehmen. In dieser Anleitung nehmen wir
`D:\projects\StaticCodeAnalyser` an.

---

## 3. Die Projekt-Gruppe in Delphi oeffnen

Das Projekt liefert eine **Project-Group** mit 4 Sub-Projekten
(Engine, geteilte UI, Standalone, IDE-Plugin).

1. In Delphi: Menue **File → Open Project**.
2. Navigiere zu `D:\projects\StaticCodeAnalyser`.
3. Unten im Dialog **"Files of type"** auf
   **"Delphi project group (`*.groupproj`)"** umstellen.
4. `StaticCodeAnalyser.d12.groupproj` waehlen und **Open** klicken.

Rechts in der IDE siehst du jetzt das **Project Manager**-Fenster mit:

- `SCA.Engine` — die Scanner-Engine.
- `SCA.SharedUI` — UI-Komponenten fuer Standalone + Plugin.
- `StaticCodeAnalyser.d12` — die Standalone-EXE.
- `StaticCodeAnalyser.IDE.d12` — das IDE-Plugin (ein BPL-Package).

Delphi zeigt das **aktive** Sub-Projekt in **fetter** grueuner Schrift.
Wir wechseln das aktive Projekt unten je nach Bedarf.

---

## 4. Die Standalone-EXE bauen

Die Standalone ist eine einfache `.exe`. Du startest sie per
Command-Line oder Doppelklick.

### 4.1 Plattform waehlen (32-bit vs 64-bit)

64-bit ist Default und empfohlen.

Im Project Manager:

1. Auf den Pfeil neben `StaticCodeAnalyser.d12` klicken (aufklappen).
2. **Target Platforms** aufklappen.
3. **Rechtsklick** auf `Windows 64-bit (Win64)` → **Activate**.
4. **Rechtsklick** auf `Configuration` → **Release** → **Activate**.

Fuer 32-bit nimm stattdessen `Windows 32-bit (Win32)`.

> **Tipp:** du kannst spaeter jederzeit zurueck wechseln —
> Rechtsklick → **Activate** auf der anderen Plattform reicht. Du
> kannst beide Versionen separat bauen.

### 4.2 Bauen

1. Im Project Manager **rechtsklick** auf `StaticCodeAnalyser.d12`
   (den Projekt-Namen selbst, nicht Target Platforms).
2. **Build** klicken (oder **Compile** wenn Build ausgegraut ist).
3. Warten — ca. 30 Sekunden. Im **Messages**-Fenster unten siehst du
   den Fortschritt.

Wenn **"Success"** kommt, liegt deine EXE hier:

```
D:\projects\StaticCodeAnalyser\Output\Win64 Release\StaticCodeAnalyser.d12.exe
```

(Fuer Win32: `Output\Win32 Release\…`. Fuer Debug: `…\Win64 Debug\…`.)

### 4.3 Stack-Size-Patch anwenden (einmal pro Build)

Der Compiler setzt 1 MB Stack. Tiefe Pascal-Files koennen das sprengen
und crashen. Oeffne PowerShell im Projekt-Ordner und tippe:

```powershell
tools\patch-stack-size.ps1 "Output\Win64 Release\StaticCodeAnalyser.d12.exe"
```

Das Skript meldet `Patched ... SizeOfStackReserve: 1 MB -> 32 MB`.
Nach **jedem frischen Build** wiederholen.

---

## 5. Das IDE-Plugin bauen und installieren

Das Plugin ist ein `.bpl` (Borland Package Library), das Delphi beim
Start ladet.

> **Abkuerzung:** wer das Plugin nur *benutzen* will, braucht diesen
> Abschnitt nicht — die Releases liefern eine **Setup-EXE**
> (`StaticCodeAnalyserSetup-<Version>.exe`) und ein **GetIt Local
> Package**; beide installieren das Release-Monolith-Package
> (`StaticCodeAnalyser.Plugin.d12.dpk`, ein einziges `.bpl`, keine
> separaten Engine-Packages). Die Schritte unten bauen den Dev-Satz
> aus drei Packages aus den Quellen.

### 5.1 Das Plugin bauen

Das Plugin laeuft in der **32-bit-IDE** (die 64-bit-IDE von 12.3 wird
noch nicht unterstuetzt). Das Plugin muss also 32-bit sein.

1. Im Project Manager `StaticCodeAnalyser.IDE.d12` aufklappen.
2. **Target Platforms** aufklappen.
3. **Rechtsklick** auf `Windows 32-bit (Win32)` → **Activate**.
4. Active Configuration auf **Release** umschalten (Rechtsklick auf
   `Configuration` → **Release** → **Activate**).
5. **Rechtsklick** `SCA.Engine` (im Project Manager) → **Build**.
   Das Plugin braucht das Engine-Package — erst das bauen.
6. **Rechtsklick** `SCA.SharedUI` → **Build**.
7. **Rechtsklick** `StaticCodeAnalyser.IDE.d12` → **Build**.

> ⚠️ **Jedes Projekt baut in seiner EIGENEN aktiven Plattform.** Die
> Schritte 3–4 schalten nur das angeklickte Projekt um. Steht
> `SCA.Engine` noch auf Win64, während das Plugin Win32 baut, scheitert
> das Plugin mit **`F2613 Unit '…' nicht gefunden`** — es linkt gegen
> eine veraltete Win32-`SCA.Engine.dcp` (die liegt AUSSERHALB des
> Repos, im Studio-`Dcp`-Ordner). Vor Schritt 5 prüfen: **alle drei**
> Packages — `SCA.Engine`, `SCA.SharedUI`,
> `StaticCodeAnalyser.IDE.d12` — zeigen unter Target Platforms
> **Windows 32-bit** fett. Seit v0.9.16 stehen die eingecheckten
> Vorgaben aller drei auf Win32, aber die IDE merkt sich die letzte
> Auswahl pro Projekt.

> ⚠️ **Auf `SCA.Engine` und `SCA.SharedUI` niemals „Install".** Beide sind
> Laufzeitpakete und tragen seit 2026-08-23 `{$RUNONLY}` in der `.dpk`.
> Ohne diese Direktive haelt die IDE ein Paket fuer Laufzeit UND
> Entwurfszeit und installiert es nach jedem Bau in sich selbst. Steht
> dann zusaetzlich der per Setup installierte Monolith in den Known
> Packages, verweigert Delphi 13 das Plugin mit der Meldung „enthaelt die
> Unit 'uLocalization', die auch im Package 'SCA.Engine' enthalten ist".
> Installiert wird genau EIN Paket: `StaticCodeAnalyser.IDE.d12` aus
> diesem Satz — oder der Monolith aus dem Setup, nie beides zugleich.

Du hast jetzt drei `.bpl`-Dateien in
`C:\Users\Public\Documents\Embarcadero\Studio\23.0\Bpl\`:

- `SCA.Engine.bpl`
- `SCA.SharedUI.bpl`
- `StaticCodeAnalyser.IDE.d12.bpl`

### 5.2 Der IDE sagen, dass sie das Plugin laden soll

1. Menue **Tools → Options**.
2. Links: **IDE → Packages → Design Packages**.
3. **Add…** klicken.
4. Zu `C:\Users\Public\Documents\Embarcadero\Studio\23.0\Bpl\` gehen,
   `StaticCodeAnalyser.IDE.d12.bpl` waehlen, **Open** klicken.
5. Sicherstellen, dass die Checkbox daneben **an** ist.
6. **OK** klicken.
7. **Delphi schliessen und neu starten.**

Nach dem Neustart zeigt die IDE ein neues Dock-Fenster:
**View → Static Code Analysis**.

Falls der Menue-Eintrag fehlt, ist das Plugin nicht geladen. Schau in
**View → Window List…** oder lies die Splash-Screen-Fehler vorsichtig
durch.

---

## 6. Die Standalone benutzen — erster Scan

Die Standalone ist der einfachste Weg, um zu pruefen, dass alles
funktioniert.

### 6.1 Einen Pascal-Code-Ordner waehlen

Fuer einen Smoke-Test kannst du das Projekt selbst scannen.

### 6.2 Starten

EXE doppelklicken, **ODER** per Command-Line:

```cmd
cd D:\projects\StaticCodeAnalyser
"Output\Win64 Release\StaticCodeAnalyser.d12.exe"
```

Ein Fenster mit **Stat-Cards** (Fehler / Warnungen / Hinweise / …)
und leerem Grid oeffnet sich.

### 6.3 Erster Scan

1. Im Feld **Path** oben den Ordner eintragen oder einfuegen
   (z.B. `D:\projects\StaticCodeAnalyser\SCA.Engine\sources`).
2. **Analyse** klicken.
3. Warten — bei kleinen Projekten: 1-5 Sek. Bei grossen: bis zu einer
   Minute.

Das Grid fuellt sich. Jede Zeile zeigt: Datei, Methode, Zeile,
Schweregrad, Regel, Meldung. Doppelklick oeffnet die Datei an der
richtigen Zeile (Notepad oder dein Default-Pascal-Viewer).

### 6.4 Filtern und sortieren

- Das **Filter**-Feld oben akzeptiert Substrings von Datei oder Regel.
- Klick auf einen Spalten-Header → sortieren.
- Klick auf eine **Stat-Card** (Fehler / Warnung / Hinweis) →
  nur diese Severity zeigen.

### 6.5 Report speichern

Die **Export**-Knoepfe (oben rechts) speichern als **HTML**, **JSON**,
**SARIF** (fuer SonarQube), oder kopieren in die Zwischenablage fuer
Jira/Markdown.

---

## 7. Das IDE-Plugin benutzen

Wenn du Sektion 5 fertig hast, ist das Plugin schon geladen.

### 7.1 Das Analyzer-Fenster oeffnen

Menue **View → Static Code Analysis**.

Ein Dock-Fenster erscheint (Titelleiste ziehen, um es z.B. neben den
Project Manager oder als Tab unten zu docken).

### 7.2 Die aktuell geoeffnete Datei scannen

1. Eine `.pas`-Datei im Editor oeffnen.
2. Im Static-Code-Analysis-Fenster **File** klicken.
3. Die aktuelle Datei wird gescannt. Befunde stehen im Grid.

### 7.3 Das ganze Projekt scannen

1. Dein Projekt (`.dproj`) in Delphi oeffnen.
2. Im Static-Code-Analysis-Fenster **Analyse** klicken.
3. Das ganze Projekt wird gescannt. Sekunden bis eine Minute.

### 7.4 Zu einem Befund springen

Klick auf eine Grid-Zeile: der Editor springt zu Datei + Zeile und
markiert die problematische Stelle mit einer farbigen Markierung in
der Gutter-Spalte.

### 7.5 False-Positives ausblenden

Rechtsklick auf einen Befund → **Suppress mit `// noinspection`**.
Das Plugin schreibt einen Kommentar ueber der Zeile, der genau diese
Regel an dieser Stelle ausblendet. Beim naechsten Scan ist der Befund
weg.

### 7.6 Hover-Hint

Wenn du ueber eine Befund-Zeile haengen bleibst, zeigt ein Tooltip ein
**Vorher / Nachher**-Code-Beispiel: wie das Problem aussieht und wie
der Fix aussieht.

---

## 8. Wenn was schief geht

| Symptom | Wahrscheinliche Ursache |
|---|---|
| **"Build failed: unresolved external"** | Du hast das Plugin vor dem Engine gebaut. Erst `SCA.Engine`, dann `SCA.SharedUI`, dann das Plugin bauen. |
| **Plugin-Menue fehlt nach Neustart** | Falsche Plattform (Win64 statt Win32 gebaut) oder falscher Pfad in `Tools → Options → Packages`. |
| **Standalone crasht nach ein paar Sekunden bei grossem Projekt** | Stack-Patch nicht angewendet. `tools\patch-stack-size.ps1` neu ausfuehren. |
| **EXE meldet "file not found" beim Start** | Du hast die EXE aus ihrem `Output\…`-Ordner verschoben. Entweder zurueck, oder die `.dcu`/`.bpl`-Files mit kopieren. |
| **"Cannot find SCA.Engine.bpl"** beim Plugin-Laden | Plugin findet `SCA.Engine.bpl` ueber den Delphi-Search-Path. Engine fuer dieselbe Plattform (Win32) und Konfiguration (Release) bauen. |
| **Undeklarierter Bezeichner, obwohl er sichtbar in der Quelle steht** | Ein Paket zieht die Unit aus dem **DCP** eines anderen Pakets, nicht aus der Quelle. Ist das DCP aelter als die Quelle, compilierst du gegen den alten Stand - und der Compiler zeigt auf die Aufrufstelle, nicht auf das veraltete Artefakt. `python tools\stale_artifacts_check.py` laufen lassen, dann in der Reihenfolge `SCA.Engine` -> `SCA.SharedUI` -> Plugin neu bauen. |

---

## 9. Was als naechstes

- **Analyzer konfigurieren:** oeffne `analyser.ini` in
  `%APPDATA%\StaticCodeAnalyser\`. Du kannst `Profile=` (welche Regeln
  laufen), `MinSeverity=`, `MinConfidence=` etc. setzen. Das File ist
  kommentiert.
- **Mit SonarQube verbinden:** siehe [sonarHowto_de.md](sonarHowto_de.md).
- **Aus Command-Line / CI:** schau in die `--help`-Ausgabe der
  Standalone. Nuetzliche Flags: `--profile`, `--report-sarif`,
  `--quiet`, `--time-detectors`.
- **Deutsche UI:** im Analyzer-Fenster oben Sprache auf **Deutsch**
  umstellen.

---

## 10. Wo Fragen stellen

- **GitHub-Issues:**
  https://github.com/nrodear/StaticCodeAnalyser/issues
- **Embarcadero-Docs (allgemeine Delphi-Fragen):**
  https://docwiki.embarcadero.com/RADStudio/en/Main_Page

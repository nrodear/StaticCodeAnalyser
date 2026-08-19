# Funde aus SCA herausbekommen — Formate und Workflows

🇬🇧 [English version](EXPORTS.md) · 🇫🇷 [Version française](EXPORTS_fr.md)

Diese Seite beantwortet eine Frage: **„Der Analyser ist gelaufen — wie
kommen die Funde dorthin, wo ich sie brauche?"** Sie beschreibt jeden
Export, welches der drei Frontends ihn erzeugen kann, und die sechs
Workflows, die Teams tatsächlich fahren.

Alles hier wurde gegen das gebaute Binary v0.9.14 geprüft. Wo ein Weg
heute kaputt ist, steht es dabei — samt Umgehung.

---

## Das Wichtigste vorweg

`analyser.exe` ist **ein Binary mit zwei Modi**. Ohne Argumente startet
die GUI; sobald das erste Argument mit `-` beginnt, läuft es headless
als CLI. „Nur in der GUI" heißt also nie „anderes Programm", sondern
*aus einem Skript nicht erreichbar*.

---

## Format-Matrix

| Format | CLI-Schalter | GUI-/Plugin-Menü | Wofür |
|---|---|---|---|
| **SARIF 2.1.0** | `--report-sarif <Datei>` | ✅ *SARIF (all findings)* | GitHub-/Azure-Code-Scanning, Archiv, Werkzeug-Austausch |
| **Sonar Generic Issue** | `--sonar-export <Datei>` | ✅ *Sonar: write Generic Issue report* | SonarQube-Dashboard (Einschränkung s. u.) |
| **HTML-Report** | `--report-html <Datei>` | ✅ | Funde lesen und weitergeben, ohne Werkzeug beim Empfänger |
| **Baseline-JSON** | `--write-baseline <Datei>` | ✅ *Write baseline* | CI-Gate: „nur bei **neuen** Funden scheitern" |
| **CSV** | `--report-csv <Datei>` | ✅ | Excel, Pivot, schnelles Auszählen |
| **JSON** | `--report-json <Datei>` | ✅ | eigene Skripte, Ticket-Automatisierung |
| **Jira-Wiki-Markup** | — | ✅ | Fund in ein Ticket einfügen |
| **AI-Prompt (Zwischenablage)** | — | ✅ | einzelnen Fund samt Codekontext an einen Assistenten geben |
| **Suppression-Telemetrie** | `--telemetry-csv <Datei>` | — | welche Regeln am häufigsten unterdrückt werden |
| **Detektor-Laufzeiten** | `--time-detectors` (stdout) / `--time-detectors-out <Datei>` | — | langsame Detektoren finden |

Zwei Asymmetrien sollte man kennen, bevor man etwas plant:

- **CSV und JSON exportieren die gefilterte Sicht der CLI.** Wie die
  übrigen CLI-Exporte enthalten sie, was Test-Fixture- und
  Baseline-Filter überlebt hat; die „all findings"-Einträge im GUI-Menü
  filtern nicht.
- **Der Scope hängt vom Frontend ab.** Aus der CLI enthalten Exporte die
  Funde *nach* Test-Fixture- und Baseline-Filter. Aus dem GUI-Menü
  exportieren die „all findings"-Einträge die **ungefilterte** Liste,
  unabhängig davon, was das Grid gerade zeigt. Die Menütexte sagen, was
  gilt — sie sind es wert, gelesen zu werden.

**Kodierung.** Alle JSON-Formate (SARIF, Sonar, `--report-json`,
Baseline) werden als **UTF-8 ohne BOM** geschrieben — RFC 8259 §8.1
verbietet die Byte-Order-Mark für JSON-Austausch, und `JSON.parse` in
Node scheitert daran; genau das benutzt GitHubs `upload-sarif`-Action.
CSV ist die bewusste Ausnahme und behält sein BOM, weil Excel UTF-8 nur
daran erkennt.

Bis einschließlich **v0.9.14** trugen die JSON-Exporte ein BOM; auf
diesem Stand also entfernen oder mit `utf-8-sig` lesen.

---

## Workflow 1 — CI-Gate: Build scheitert bei neuen Funden

Die Baseline ist der Mechanismus: Sie hält den heutigen Stand fest,
damit der Build von morgen nur über Neues meckert.

```bash
# einmalig, um den Ist-Zustand festzuschreiben
analyser.exe --path . --write-baseline .sca/sca.baseline.json

# in jedem Build
analyser.exe --path . --baseline .sca/sca.baseline.json --report-sarif build/sca.sarif
```

Die Exit-Codes sind gestuft: `0` sauber, ungleich null, wenn nach dem
Baseline-Filter Funde bleiben. `--fail-on error|warning|hint|none`
verengt, was zählt. Lesefehler halten einen Lauf in jedem Modus außer
`none` ungleich null: wo die Politik sonst 0 liefern würde, endet der Lauf
mit 4 — ein unvollständiger Scan darf nie wie ein sauberer aussehen.
Werkzeugfehler (99) werden vor `--fail-on` entschieden und lassen sich gar
nicht herabstufen.

**Für `--write-baseline` einen absoluten Pfad oder einen mit
Verzeichnisanteil verwenden.** Ein bloßer Dateiname
(`--write-baseline b.json`) scheitert mit *„Baseline write error:
Verzeichnis kann nicht erstellt werden"* — an v0.9.14 nachgemessen.

**In CI besser `--baseline-scan y` als einen Dateinamen.** Der Schalter
löst die Baseline dreistufig auf — `--baseline`, dann `[Baseline] File=`
aus der `analyser.ini`, dann der `.sca`-Ordner neben `--project` /
`--project-group` (bzw. `<pfad>\.sca\sca.baseline.json`) — und meldet,
welche er genommen hat. Der Punkt ist das Verhalten im Fehlerfall: wer
eine Baseline anfordert und keine findet, bekommt einen **Abbruch mit
Exit 99** samt Liste aller geprüften Pfade, statt still den kompletten
Rückstand als „neu" gemeldet zu bekommen. Genau diese stille Variante ist
der klassische Weg, auf dem eine grüne Pipeline aufhört, etwas zu
bedeuten. `--write-baseline auto` schreibt an dieselbe `.sca`-Stelle, das
Paar kommt also ohne fest verdrahtete Pfade aus:

```bash
analyser.exe --path . --write-baseline auto        # einmalig
analyser.exe --path . --baseline-scan y            # in jedem Build
```

`--baseline-scan n` ist das ausdrückliche Gegenteil: ohne Baseline
laufen, auch wenn eine Datei herumliegt. Jeder andere Wert wird
abgelehnt.

**Gibt es denselben Unit-Namen in mehreren Ordnern, `--baseline-path-fingerprint y`
setzen.** Standardmäßig identifiziert ein Fingerprint einen Fund über den
*Dateinamen*, nicht über den Pfad — zwei `uSame.pas` in verschiedenen
Ordnern teilen sich also eine Identität. Gemessene Folge: Eine Baseline aus
einem Unterordner unterdrückte **sämtliche** Funde im Nachbarordner,
darunter eine SQL-Injection, die nie jemand geprüft hatte; mit dem Schalter
bleiben sie im selben Lauf erhalten. Er ändert die Fingerprints — beim
Einschalten also eine frische Baseline schreiben.

Ein Rest bleibt bewusst: Ein Fund, dessen umgebende Zeilen in beiden
Dateien gleich sind, matcht weiterhin über die `contextHash`-Stufe. Genau
das lässt eine Baseline Umzüge und Refactorings überleben — und ist der
Grund, warum zwei byte-identische Kopien verbunden bleiben, unabhängig von
diesem Schalter.

**Eine Baseline NICHT durch Kombination der beiden Schalter
auffrischen.** Das naheliegend wirkende `--baseline alt
--write-baseline neu` schreibt nur die Funde, die den Filter
*überlebt* haben — also die neuen. An einem echten Repository gemessen:
aus einer Baseline mit 226 Einträgen wurden **0**, und der nächste Build
meldete den gesamten Altbestand erneut. Zum Auffrischen eine frische
Baseline aus einem Lauf **ohne** `--baseline` schreiben.

## Workflow 2 — Pull-Request-Review: nur das Geänderte

```bash
analyser.exe --path . --diff main...HEAD --report-html build/review.html
```

`--branch` nimmt die geänderten Dateien aus der Versionsverwaltung (Git
und SVN werden erkannt), `--diff <range>` einen Git-Bereich inklusive
`a...b` für den gemeinsamen Vorfahren. Beide schließen ungespeicherte
Änderungen ein. Der HTML-Report ist self-contained — keine externen
Dateien, er öffnet sich von einem Netzlaufwerk oder aus einem
CI-Artefakt.

## Workflow 3 — SonarQube-Dashboard

SCA pusht **nicht** nach SonarQube, und das ist richtig so: Sonar hat
keine öffentliche Schnittstelle, um externe Issues entgegenzunehmen. SCA
schreibt die Datei, `sonar-scanner` trägt sie hinein.

```bash
analyser.exe --path . --base-dir . --sonar-export sca-findings.json
sonar-scanner -Dsonar.externalIssuesReportPaths=sca-findings.json
```

> **⚠️ Im ausgelieferten ZIP kaputt — bitte vorher lesen.** Das
> Release-Archiv enthält nur die EXE. Ohne `rules/sca-rules.json`
> daneben fällt der Regelkatalog auf einen eingebauten Notbehelf zurück,
> der `type` statt `cleanCodeAttribute` + `impacts` schreibt — und
> **SonarQube verwirft daraufhin den gesamten Report** (gegen die echten
> Scanner-Engine-Validatoren geprüft: 10.7 meldet *missing mandatory
> field 'cleanCodeAttribute'*, 2025.x *missing mandatory field
> 'severity'*). Der Lauf sieht erfolgreich aus, die Datei ist da — nur
> das Dashboard bleibt leer.
>
> **Umgehung:** den `rules/`-Ordner aus dem Repository neben die EXE
> legen. Mit vorhandenem Katalog validiert der Export auf allen
> getesteten Engine-Generationen. Eine kaputte `rules/sca-rules.json`
> führt in denselben Zustand, ebenfalls lautlos.

Die Pfade im Report sind relativ zu `--base-dir` (Vorgabe: `--path`) —
den Export also mit derselben Wurzel fahren, die auch der Scanner
benutzt. Dateien außerhalb dieser Wurzel fallen auf absolute Pfade
zurück, die Sonar still als „unknown files" verwirft.

**Lesefehler stehen nicht im Sonar-Report.** Eine Datei, die der Analyser
nicht lesen konnte, sagt etwas über die Vollständigkeit des Laufs aus,
nicht über den Quelltext — als Dashboard-Issue war sie Rauschen, an dem
niemand etwas beheben kann. Sichtbar bleibt sie überall dort, wo sie
hingehört: in der Konsolen-Zusammenfassung, im Exit-Code 4, im
HTML-Report und in SARIF, das sie sowohl als `result` als auch unter
`runs[].invocations[].toolExecutionNotifications` führt. Ein Lauf mit
*ausschließlich* Lesefehlern exportiert entsprechend
`{"rules":[],"issues":[]}` — gültig, und Sonar nimmt es an. Ob ein Scan
vollständig war, steht in der Konsolenzeile, nicht im Dashboard.

## Workflow 4 — GitHub-/Azure-Code-Scanning

```bash
analyser.exe --path . --base-dir . --report-sarif sca.sarif
```

Das SARIF trägt `partialFingerprints` (Zeilen-Hash + contextHash), damit
Alerts ihre Identität über Zeilenverschiebungen behalten. Die Pfade sind
relativ zu `--base-dir` — auf die Repository-Wurzel zeigen lassen, das
erwartet Code-Scanning.

Zwei Fallen: Das UTF-8-BOM kann Node-basierte Uploader stören, und ein
**baseline-gefiltertes** SARIF arbeitet gegen den Alert-Lebenszyklus der
Plattform (sie schließt alles, was der Filter entfernt hat). Für
Code-Scanning den ungefilterten Report hochladen und die Plattform den
Zustand führen lassen.

## Workflow 5 — Entwickler am Schreibtisch

GUI oder IDE-Plugin: laufen lassen, mit den Kacheln filtern, Fund
anklicken, Vorher/Nachher-Hilfe lesen. `Strg+Alt+S` setzt einen
Suppression-Marker, `Strg+Alt+F` wendet einen Quick-Fix an. Funde öffnen
im Editor der Wahl über `[Editor]` in der `analyser.ini` (VS Code,
Notepad++, Sublime, …) — dieser Weg springt auf die genaue Zeile. Die
Delphi-IDE öffnet nur die Datei; einen Zeilen-Schalter bietet sie von
außen nicht.

Zum Weitergeben ist `--report-html` das Format, das beim Empfänger kein
Werkzeug voraussetzt.

> **Hinweis zum Weitergeben:** Der HTML-Report enthält
> Quelltext-Ausschnitte. Behandle ihn wie Quelltext, wenn du ihn
> verschickst.

## Workflow 6 — Auswertung über die Zeit

Einen eingebauten Trendspeicher gibt es nicht. Zwei praktikable Wege:
das SARIF je Build archivieren und mit `jq` auszählen — oder SonarQube
über Workflow 3 die Historie führen lassen. Die Regel-Zahlen aus der
Konsolen-Zusammenfassung sind stabil genug, um sie zu plotten, wenn man
sie mitschreibt.

---

## Bekannte Einschränkungen

Ehrliche Liste, Stand v0.9.14 — alles reproduziert:

| Bereich | Verhalten |
|---|---|
| Sonar-Export aus dem Release-ZIP | wird von SonarQube verworfen; `rules/` neben die EXE legen |
| Baseline-Auffrischen mit beiden Schaltern | kürzt die Baseline auf die neuen Funde |
| `--write-baseline` mit bloßem Dateinamen | schreibt nicht |
| JSON-Exporte | UTF-8 **mit** BOM — nach v0.9.14 behoben, jetzt BOM-frei |
| HTML-Report | speichert nur Basisdateinamen; gleichnamige Units aus verschiedenen Ordnern kollidieren |
| Baseline-Fingerprints | gleichnamige Units teilen sich standardmäßig einen Namensraum — mit `--baseline-path-fingerprint y` abschaltbar (s. u.) |
| unlesbare Quelldateien | werden in Konsole, SARIF/Sonar/HTML und Baseline unterschiedlich gezählt |
| `--parallel` | nicht deterministisch; nicht für Exporte verwenden, die man vergleicht |
| `--sonar-insecure` | akzeptiert keine selbstsignierten Zertifikate (schaltet nur TLS 1.1 frei) |
| `--sonar-test` in einem fremden Repo | eine `sonar-project.properties` im gescannten Repo überschreibt den eigenen Host — der Token geht dorthin |

---

## Welches Format wofür

- **Ein Gate, das schlechte Merges blockiert** → Baseline + Exit-Code,
  das SARIF als Beleg archivieren.
- **Ein Dashboard, auf das das Team schaut** → Sonar-Export plus Scanner
  (mit `rules/` neben der EXE).
- **Ein Mensch, der es lesen muss** → HTML-Report.
- **Eigene Werkzeuge** → SARIF; es ist das reichhaltigste und das
  einzige mit Fingerprints, alles andere lässt sich daraus ableiten.

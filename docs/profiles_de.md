# Scan-Profile

Ein **Profil** ist eine benannte Regelmenge. Es beantwortet eine einzige
Frage: *welche der 196 Detektoren laufen in diesem Scan?* Alles andere -
Severity-Schwelle, Unterdrückungen, Baseline - filtert hinterher. Das
Profil entscheidet, wonach überhaupt gesucht wird.

## Die neun eingebauten Profile

| Profil | Regeln | Wofür es da ist |
|---|---|---|
| `strict` | 196 | Alles. An diesem Profil hängt die Vollständigkeitszusage. |
| `default` | 189 | Alles außer den sieben reinen Konventionsregeln aus `style`. Diese sieben machen auf einem großen Bestand rund die Hälfte aller Funde aus - deshalb stehen sie nicht im Default. |
| `selftest-quiet` | 185 | `default` ohne ein paar Formatierungsregeln. Wird benutzt, wenn dieses Repository sich selbst scannt. |
| `code-quality` | 26 | Wartbarkeit: toter Code, lange Methoden, Komplexität, unbenutzte Uses. |
| `ide-fast` | 20 | Klein genug, um bei jeder geöffneten Datei in der IDE zu laufen. Bugs und Sicherheit, kein Stil. |
| `dfm-only` | 20 | Nur die Form-Datei-Prüfungen. |
| `bugs-only` | 15 | Nur Defekte - keine Smells, keine Konventionen. |
| `security` | 7 | Nur Verwundbarkeiten und Hotspots. |
| `style` | 7 | Die reinen Konventionsregeln, die `default` weglässt. |

Die Zahlen sind der Stand von 0.9.17, am Katalog gemessen.

## Ein Profil auswählen

| Wo | Wie |
|---|---|
| Standalone-Anwendung | Profil-Combo in der Filterzeile |
| IDE-Plugin | Profil-Combo; `[Rules] IdeProfile` setzt den Plugin-Default (`ide-fast`) |
| CLI | `--profile <name>` |
| `analyser.ini` | `[Rules] Profile=<name>` |

Beide Oberflächen zeigen auch, was *in* einem Profil steckt:
**Burger-Menü -> Regelsatz-Profile ...** listet in der Standalone wie im
IDE-Plugin jede Regel des gewählten Profils mit ID, Kind-Token, Severity
und Typ. Es ist dasselbe Fenster - es liegt in `SCA.SharedUI`, damit die
beiden nicht auseinanderlaufen können.

## Wo Profile definiert sind

In `rules/sca-rules.json`, im Block `profiles`:

```json
"profiles": {
  "security": ["SQLInjection", "HardcodedSecret", "CommandInjection"],
  "default":  ["*", "!PublicMemberWithoutDoc", "!NilComparison"]
}
```

Jeder Eintrag ist eine Liste von Token, angewandt **von links nach
rechts**:

| Token | Wirkung |
|---|---|
| `*` | alle 196 Kinds |
| `Kind` | dieses Kind aufnehmen |
| `!Kind` bzw. `-Kind` | dieses Kind entfernen |

Die Reihenfolge zählt. `["*", "!LongMethod"]` ist alles außer einer Regel;
`["!LongMethod", "*"]` ist alles, weil der `*` zuletzt läuft.

## Der Token ist der Kind-Name, nicht die SCA-ID

Ein Profil führt **Kind-Namen** (`MemoryLeak`), nie Regel-IDs (`SCA001`).
Den Kind-Namen jeder Regel zeigt die Spalte **Kind (Profil-Token)** im
Profil-Fenster, außerdem [`DETECTORS_de.md`](../DETECTORS_de.md).

Ein unbekannter Token wird **wortlos ignoriert** - kein Fehler, keine
Warnung. Ein Tippfehler bewirkt also schlicht nichts, und zwar still.
Nach dem Bearbeiten eines Profils das Profil-Fenster öffnen und prüfen,
ob die Regelzahl die gemeinte ist.

## Ein eigenes Profil schreiben

Eingebaute Profile lassen sich nicht ändern - sie stammen aus dem
ausgelieferten Katalog und werden bei jedem Update überschrieben. Ein
eigenes Profil liegt deshalb in einer eigenen Datei, und der Weg dorthin
führt über das Kopieren:

1. **Burger-Menü -> Regelsatz-Profile ...** (Standalone oder
   IDE-Plugin, beides geht)
2. Das Profil auswählen, das am nächsten kommt, **Kopieren ...** drücken
   und einen Namen vergeben (Buchstaben, Ziffern, `-`, `_`, `.`).
3. Mit **Regeln aufnehmen ...** und **Regeln entfernen** zuschneiden,
   dann **Speichern**.

Das Profil landet in `profiles.json` neben `analyser.ini`, also in
`%APPDATA%\StaticCodeAnalyser\`. Diese Datei rührt kein Update an.

Gelesen wird sie von der **Engine**, nicht nur von der Anwendung: ein
hier gebautes Profil greift auch mit `--profile <name>` auf der
Kommandozeile und steht im Profil-Combo des IDE-Plugins.

Ein Name, den bereits ein eingebautes Profil trägt, wird abgelehnt. Sonst
bedeutete derselbe Name auf zwei Rechnern Verschiedenes, und ein
Vergleich zweier SARIF-Läufe wäre wertlos.

### Diese Datei von Hand bearbeiten

`profiles.json` benutzt dieselbe Token-Syntax wie der Katalog:

```json
{
  "version": 1,
  "profiles": {
    "my-team": ["MemoryLeak", "SQLInjection", "NilDeref"]
  }
}
```

Das Fenster schreibt die Kind-Liste ausgeschrieben statt als `*` mit
Ausnahmen - was die Liste zeigt, steht also Wort für Wort in der Datei.
Ist die Datei nicht lesbar, behält die Engine die eingebauten Profile und
sagt nichts dazu; die eigenen sind dann schlicht weg, bis sie wieder
gelesen werden kann.

## Nicht dasselbe: `examples/profile-*.yml`

`examples/profile-security.yml` und seine Geschwister sind **Custom-Rule-
Dateien** (`[Detectors] CustomRulesFile=`). Sie fügen eigene
Regex-Regeln hinzu. Mit dieser Seite teilen sie nur das Wort "Profil":
ein Scan-Profil wählt unter vorhandenen Detektoren aus, eine
Custom-Rule-Datei bringt neue mit.

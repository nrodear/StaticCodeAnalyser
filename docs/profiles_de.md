# Scan-Profile

Ein **Profil** ist eine benannte Regelmenge. Es beantwortet eine einzige
Frage: *welche der 206 Detektoren laufen in diesem Scan?* Alles andere -
Severity-Schwelle, Konfidenz-Schwelle, Unterdrückungen, Baseline -
filtert hinterher. Das Profil entscheidet, wonach überhaupt gesucht wird.

## Die neun eingebauten Profile

| Profil | Regeln | Wofür es da ist |
|---|---|---|
| `strict` | 206 | Alles; in der CLI schaltet es zusätzlich SCA007 (unbenutzte Uses) ein, in EXE und IDE-Plugin nicht (siehe unten). An diesem Profil hängt die Vollständigkeitszusage - Regeln mit Konfidenz low brauchen trotzdem `[Rules] MinConfidence=low`, siehe unten. |
| `default` | 198 | Alles außer den acht reinen Konventionsregeln aus `style`. Diese acht machen auf einem großen Bestand rund die Hälfte aller Funde aus - deshalb stehen sie nicht im Default. |
| `selftest-quiet` | 195 | Alles außer elf Regeln, die für den Selbstscan abgeschaltet sind (darunter `BeginEndRequired`, `TooLongLine`, `UnsortedUses`, `ConcatToFormat`, `NestedTry`). Keine Teilmenge von `default`: Es behält fünf der `style`-Regeln. Wird benutzt, wenn dieses Repository sich selbst scannt. |
| `code-quality` | 27 | Wartbarkeit: toter Code, lange Methoden, Komplexität, unbenutzte Uses (SCA007 nur mit `[Detectors] UsesCheck=1`). |
| `ide-fast` | 21 | Klein genug, um bei jeder geöffneten Datei in der IDE zu laufen. Bugs und Sicherheit, kein Stil. |
| `dfm-only` | 20 | Nur die Form-Datei-Prüfungen. |
| `bugs-only` | 20 | Nur Defekte - keine Smells, keine Konventionen. |
| `security` | 9 | Nur Verwundbarkeiten und Hotspots. |
| `style` | 8 | Die reinen Konventionsregeln, die `default` weglässt. |

Die Zahlen sind am aktuellen Katalog gemessen, nicht geschätzt.

**Konfidenz-Schwelle.** Nach dem Profil verwirft `[Rules] MinConfidence`
(ausgeliefert: `medium`) Funde unterhalb dieser Konfidenz. 24 Regeln
melden mit Konfidenz *low* - darunter `TooLongLine`, `UnsortedUses`,
`UseAfterFree` und `AbstractNotImpl` - und bleiben deshalb in jedem
Profil stumm, auch in `strict`, bis man `MinConfidence=low` setzt. Die
Liste steht in [DETECTORS_de.md](../DETECTORS_de.md).

**`strict` und SCA007.** Nur die CLI nimmt SCA007 (unbenutzte Uses) in
`strict` dazu: `--profile strict` oder `[Rules] Profile=strict` in einem
CLI-Lauf schaltet ihn ohne `[Detectors] UsesCheck=1` ein. Die
eigenständige EXE und das IDE-Plugin behandeln `strict` wie jedes andere
Profil - dort braucht SCA007 in jedem Profil `[Detectors] UsesCheck=1`.

## Ein Profil auswählen

| Wo | Wie |
|---|---|
| Standalone-Anwendung | Profil-Combo in der Filterzeile |
| IDE-Plugin | Profil-Combo; `[Rules] IdeProfile` setzt den Plugin-Default (`ide-fast`) |
| CLI | `--profile <name>` |
| `analyser.ini` | `[Rules] Profile=<name>` |

Ein Name, den der Katalog nicht kennt, ist in der CLI ein Fehler: ob er aus
`--profile` oder aus `[Rules] Profile` kommt, der Lauf endet vor dem Scan
mit Exit 99 und nennt die bekannten Profile. Groß-/Kleinschreibung und
Leerzeichen außen spielen keine Rolle. (Bis 0.9.18 lief ein unbekannter
Name still mit allen Regeln.)

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
| `*` | alle 206 Kinds |
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
Kommandozeile und steht im Profil-Combo des IDE-Plugins. Gelesen wird
das `%APPDATA%` des Kontos, unter dem das Werkzeug läuft: ein CI-Dienstkonto
sieht ein hier angelegtes Profil nicht, und `--profile <name>` endet dort
mit Exit 99 - die Datei (siehe unten) gehört dann in dieses Konto.

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

**Gelesen wird die Datei einmal je Programmstart.** Ein von Hand
angelegtes oder bearbeitetes Profil erscheint deshalb nicht von selbst.
Im Profil-Fenster **Neu laden** drücken, dann wird sie erneut gelesen -
ohne Neustart der Anwendung oder der IDE. Profile, die *im* Fenster
entstehen, gelten sofort; „Neu laden" ist nur für Änderungen von außen.

## Ein fremdes Regelwerk übernehmen

Eine `profiles.json` von einem Kollegen, aus einem Projektverzeichnis oder
von einem Netzlaufwerk muss nicht erst nach `%APPDATA%` kopiert werden.
**Importieren ...** im Profil-Fenster liest eine beliebige Datei und
übernimmt daraus, was übernommen werden darf:

* Beide Formen werden gelesen - die vollständige Datei (`{"version": 1,
  "profiles": {...}}`) und die bloße Abbildung (`{"mein-team":
  ["MemoryLeak", ...]}`).
* Vor dem Schreiben steht da, was passieren würde: welche Profile neu
  sind, welche eigenen **überschrieben** würden und welche übersprungen
  werden, weil der Name zu einem eingebauten Profil gehört.
* Geschrieben wird erst nach Bestätigung.

Die übernommenen Profile landen in der eigenen `profiles.json`. Danach
verhalten sie sich wie selbst angelegte - einschließlich
`--profile <Name>` auf der Kommandozeile.

Das Repository bringt eine solche Datei mit:
`reDelphix/data/profile-code-aktionen.json` enthält das Profil
`code-aktionen`, die Regeln mit einer Code-Aktion von
reDelphix plus `FileReadError`. Es gehört nicht zu den eingebauten
Profilen und muss importiert werden.

## Eine Regel in der Liste finden

Beide Listen im Profil-Fenster - die Regeln des Profils und die Auswahl
unter **Regeln aufnehmen ...** - haben ein Suchfeld und sortierbare
Spalten:

* Was im Feld steht, engt die Liste ein. Gesucht wird in allen fünf
  Spalten gleichzeitig: `SCA047`, `Dfm`, `Leak`, `Warnung` und `Bug`
  führen alle zum Ziel.
* Ein Klick auf eine Spaltenüberschrift sortiert danach, ein zweiter
  dreht die Richtung um. Zweiter Schlüssel ist immer die ID - die
  Reihenfolge ist damit bei gleichem Inhalt jedes Mal dieselbe.
* In der Auswahl überleben die Haken den Filter. Erst nach `Dfm` suchen
  und drei Regeln ankreuzen, dann nach `Leak` suchen und zwei weitere -
  die Fußzeile zählt alle fünf.

## Nicht dasselbe: `examples/profile-*.yml`

`examples/profile-security.yml` und seine Geschwister sind **Custom-Rule-
Dateien** (`[Detectors] CustomRulesFile=`). Sie fügen eigene
Regex-Regeln hinzu. Mit dieser Seite teilen sie nur das Wort "Profil":
ein Scan-Profil wählt unter vorhandenen Detektoren aus, eine
Custom-Rule-Datei bringt neue mit.

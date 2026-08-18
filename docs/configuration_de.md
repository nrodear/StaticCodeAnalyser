# Konfigurationsreferenz (`analyser.ini`)

Alle Schluessel, die das Werkzeug aus `analyser.ini` liest, an einer Stelle.
Die Datei liegt unter

```
%APPDATA%\StaticCodeAnalyser\analyser.ini
```

neben `ignore.txt`. Sie wird beim ersten Start angelegt; eine aeltere
`repo.ini` wird automatisch uebernommen. Alle Schluessel sind optional - ein
fehlender Schluessel bedeutet den unten genannten Standardwert.

Dieselbe Datei lesen die eigenstaendige EXE, das IDE-Plugin und die CLI. Wo
sich die drei bewusst unterscheiden, sagt es der Schluesselname
(`IdeProfile`, `IdeMinSeverity`). CLI-Schalter schlagen die Datei fuer den
Lauf, in dem sie angegeben werden.

> SonarQube-Einstellungen stehen **nicht** in dieser Datei - siehe
> [sonar-config.md](sonar-config.md).


## `[Rules]`

| Schluessel | Typ | Standard | Bedeutung |
|---|---|---|---|
| `Profile` | String | _(leer)_ | Regelprofil fuer CLI und Standalone. Leer = alle Regeln. |
| `MinSeverity` | String | `hint` | Niedrigste gemeldete Schwere: `error`, `warning`, `hint`. |
| `MinConfidence` | String | `medium` | Konfidenz-Untergrenze: `low` schaltet den Filter aus, `medium` ist Auslieferungsstand. |
| `IdeProfile` | String | `ide-fast` | Profil des IDE-Plugins. Wird je Lauf nach `Profile` gespiegelt, ueberschreibt es aber nicht. |
| `IdeMinSeverity` | String | `hint` | Schwere-Untergrenze des IDE-Plugins, gleich gespiegelt. |
| `EnableDetectorReviewFilter` | Bool | `False` | Opt-in-Filter, der Regeln in Ueberpruefung ausblendet. |

## `[Detectors]`

| Schluessel | Typ | Standard | Bedeutung |
|---|---|---|---|
| `LeakyClasses` | String | _(leer)_ | Zusaetzliche Klassen, die SCA001 als leck-faehig behandelt, kommagetrennt. |
| `ExcludeLeakyClasses` | String | _(leer)_ | Klassen, die aus dieser Liste wieder entfernt werden. |
| `OwnershipSinks` | String | _(leer)_ | Routinen, die die Ownership eines uebergebenen Objekts uebernehmen. Standardmaessig leer - siehe DETECTORS. |
| `AutoDiscoverClasses` | Bool | `False` | Leck-faehige Klassen waehrend des Scans entdecken und protokollieren. |
| `CustomRulesFile` | String | _(leer)_ | YAML-Datei mit eigenen Regeln. |
| `FormatFunctions` | String | _(leer)_ | Zusaetzliche Format-artige Funktionen fuer die Platzhalter-Pruefung (SCA005). |
| `MagicNumberTrivials` | String | _(leer)_ | Zahlen, die SCA014 ohne benannte Konstante durchgehen laesst. |
| `IncludeTests` | Bool | `False` | Testverzeichnisse mitscannen. Standardmaessig aus - Fixtures erzeugen Rauschen. |
| `UsesCheck` | Bool | `False` | Den teuren Unused-Uses-Detektor einschalten. |
| `MaxFileMB` | Integer | `5` | Groessere Dateien werden uebersprungen. |
| `LongMethodMaxBodyLines` | Integer | `50` | Schwelle SCA012: Rumpfzeilen. |
| `LongMethodMaxStatements` | Integer | `30` | Schwelle SCA012: Anweisungen. |
| `LongParamListMaxParams` | Integer | `5` | Schwelle SCA013: Parameter. |
| `DeepNestingMaxDepth` | Integer | `4` | Schwelle SCA018: Verschachtelungstiefe. |
| `CyclomaticMax` | Integer | `10` | Schwelle SCA022: McCabe-Komplexitaet. |
| `MaxCaseBranches` | Integer | `10` | Schwelle SCA091: case-Zweige. |
| `MaxLineLength` | Integer | `120` | Schwelle fuer die Zeilenlaengen-Regel. |
| `DuplicateBlockMinLines` | Integer | `8` | Mindestlaenge eines Blocks, bevor Duplikate gemeldet werden. |

## `[Baseline]`

| Schluessel | Typ | Standard | Bedeutung |
|---|---|---|---|
| `File` | String | _(leer)_ | Baseline-JSON. Relative Pfade loesen gegen die Scan-Wurzel auf; leer = `.sca`-Standardort. |
| `OnlyNew` | Bool | `False` | Nur Funde anzeigen, die nicht in der Baseline stehen. |
| `PathInFingerprint` | Bool | `False` | Den Relativpfad in den Fingerprint aufnehmen - trennt gleichnamige Dateien in verschiedenen Ordnern. |

## `[Score]`

| Schluessel | Typ | Standard | Bedeutung |
|---|---|---|---|
| `GradeBMax` | Integer | `50` | Obere Punktgrenze fuer Note B. |
| `GradeCMax` | Integer | `200` | Obere Punktgrenze fuer Note C. |
| `GradeDMax` | Integer | `500` | Obere Punktgrenze fuer Note D; darueber gilt E. |

## `[UI]`

| Schluessel | Typ | Standard | Bedeutung |
|---|---|---|---|
| `Language` | String | `en` | Oberflaechensprache: `de`, `en`, `fr`. Leer = Systemgebietsschema. |
| `Theme` | String | `system` | Design der EXE: `system` (Windows folgen), `light`, `dark`. |
| `ClipboardOnClick` | Integer | `1` | Was ein Zeilenklick kopiert: `1` nichts, `2` Jira-Mini-Ticket, `3` Markdown-Prompt. |
| `EditorColorScheme` | String | `default` | Farbschema von Editor-Markerstreifen und Overlay-Titelleiste. |
| `OverlayPosition` | String | `sameline` | Wo sich das Hover-Overlay relativ zur Fundzeile verankert. |
| `OverlayShowOnHover` | Bool | `False` | Overlay beim Ueberfahren statt beim Klick zeigen. |
| `OverlayTextOnly` | Bool | `False` | Das Overlay-Fenster durch einen transparenten Einzeiler ersetzen. |

## `[Silent]`

| Schluessel | Typ | Standard | Bedeutung |
|---|---|---|---|
| `Enabled` | Bool | `True` | Hintergrundanalyse der bearbeiteten Datei (IDE-Plugin). |

## `[Repo]`

| Schluessel | Typ | Standard | Bedeutung |
|---|---|---|---|
| `BaseBranch` | String | _(leer)_ | Basiszweig fuer Branch-Changes. Leer = automatisch. |
| `IncludeWorkingTree` | Bool | `True` | Nicht committete Aenderungen in den Diff aufnehmen. |

## `[Paths]`

| Schluessel | Typ | Standard | Bedeutung |
|---|---|---|---|
| `GitExe` | String | _(leer)_ | Pfad zu `git.exe`. Leer = Suche im `PATH`. |
| `SvnExe` | String | _(leer)_ | Pfad zu `svn.exe`. Leer = Suche im `PATH`. |


## `[PathOverrides]`

Freiform-Sektion: jeder Schluessel ist ein Pfadfragment, jeder Wert die
Schwere, die Funde unterhalb dieses Pfads bekommen. Damit laesst sich
zugelieferter oder generierter Code herabstufen, ohne ihn auszuschliessen.

```ini
[PathOverrides]
third_party=hint
generated\=off
```

---

_Schluessel ausgelesen aus `SCA.Engine/sources/Infrastructure/uRepoSettings.pas`
und `SCA.SharedUI/sources/uAppTheme.pas`. Wer dort einen Schluessel ergaenzt,
ergaenzt ihn bitte hier - fuer diese Seite gibt es noch keinen Generator._

# Konfigurationsreferenz (`analyser.ini`)

🇬🇧 [English version](configuration.md) · 🇫🇷 [Version française](configuration_fr.md)

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
| `CognitiveLimit` | Integer | `15` | Schwelle SCA176: kognitive Komplexitaet (Verschachtelung zaehlt staerker als bei McCabe). |
| `MaxCaseBranches` | Integer | `10` | Schwelle SCA091: case-Zweige. |
| `MaxLineLength` | Integer | `120` | Schwelle fuer die Zeilenlaengen-Regel. |
| `DuplicateBlockMinLines` | Integer | `8` | Mindestlaenge eines Blocks, bevor Duplikate gemeldet werden. |

## `[Components]`

| Schluessel | Typ | Default | Bedeutung |
|---|---|---|---|
| `ForbiddenClasses` | String | _(leer)_ | Komponentenklassen, die in keiner DFM vorkommen duerfen; jede Verwendung wird als SCA038 gemeldet. Kommagetrennt, unabhaengig von Gross-/Kleinschreibung. Leer laesst die Regel stumm. |

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
| `Element.<Name>` | Bool | `True` | **Not-Aus je UI-Element des IDE-Plugins.** `0` legt genau dieses Element still, ohne Deinstallation - fuer den Fall, dass eines die IDE stoert. Wirkt erst nach IDE-Neustart; uebersprungene Elemente meldet das Plugin per Debug-Ausgabe (Praefix `SCA-UI`). Gueltige Namen: `SharedUiHooks`, `DockForm`, `LineHighlighter`, `AnnotationOverlay`, `WatchMode`, `WarmUpCaches`, `ViewMenuItem`, `EditorContextMenu`, `OptionsPageSCA`, `OptionsPageSonar`, `FindingsProperties`, `AboutBox`, `ToolsMenuItem`. `PackageWizard` ist bewusst NICHT abschaltbar - er traegt den Abbau aller uebrigen. Die eigenstaendige EXE liest diese Schluessel nicht. |
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


## `[Editor]` — womit ein Befund geoeffnet wird (nur EXE)

Das IDE-Plugin springt ueber die ToolsAPI direkt an die Stelle und liest
diesen Abschnitt nicht.

| Schluessel | Typ | Standard | Bedeutung |
|---|---|---|---|
| `ExternalEditor` | String | _(leer)_ | Voller Pfad zu einem Editor. Ist er gesetzt, uebernimmt er **alle** Dateiarten - auch `.dfm` - und die Delphi-IDE wird nicht mehr angesprochen. |
| `ExternalEditorArgs` | String | `-g "%file%:%line%"` | Argumente. Platzhalter: `%file%`, `%line%`, `%col%`, `%dir%`, `%%`. Der Standard passt zu Visual Studio Code. |
| `DfmTarget` | String | `ide` | Was ein `.dfm`-Befund oeffnet, wenn kein externer Editor gesetzt ist: `ide` oder `viewer` (eingebauter Textbetrachter, der zuverlaessig zur Zeile springt). |

## `[Sonar]`

Verbindungsdaten fuer den Test (`--sonar-test`, "Test Connection" in der
IDE) und fuer `--sonar-init`. **Keiner dieser Schluessel beeinflusst die
Analyse oder irgendeinen Detektor.** Ausfuehrlich in [sonar-config.md](sonar-config.md).

**Dieser Abschnitt hat die niedrigste Prioritaet der vier Quellen.** Ein
CLI-Schalter, eine Umgebungsvariable (`SONAR_HOST_URL`, `SONAR_TOKEN`,
`SONAR_PROJECT_KEY`, `SONAR_ORGANIZATION`, `SONAR_BRANCH`) und - fuer
Projektschluessel, Organisation und Branch - eine `sonar-project.properties`
im GESCANNTEN Repository stechen ihn aus. `--sonar-test` zeigt an, welche
Quelle den Wert geliefert hat.

**Der Token steht nicht hier.** Er liegt verschluesselt in `[SonarTokens]`,
geschrieben von der Options-Seite oder `--sonar-token`. Unter Windows ist
er an Benutzer und Rechner gebunden - eine kopierte `analyser.ini` ist
anderswo wertlos, und ein von Hand eingetragener Token laesst sich nicht
entschluesseln. Wer ihn gar nicht auf der Platte haben will, nimmt
`SONAR_TOKEN`.

| Schluessel | Typ | Default | Bedeutung |
| --- | --- | --- | --- |
| `HostUrl` | String | _(leer)_ | Basis-URL des Servers. Der Test schickt den Token als Bearer-Header genau dorthin - ein falscher Host bekommt das Geheimnis. Deshalb wird eine `sonar.host.url` aus dem gescannten Repository bewusst ignoriert. |
| `ProjectKey` | String | _(leer)_ | Das Projekt, das der Test nachschlaegt. |
| `Organization` | String | _(leer)_ | SonarCloud-Mandantenschluessel. Ohne ihn antwortet SonarCloud mit 400 und der Test meldet "Projekt nicht gefunden", obwohl es das Projekt gibt. |
| `Branch` | String | _(leer)_ | Branch-Name fuer den Lookup und fuer `--sonar-init`. |
| `Insecure` | Bool | `0` | `1` ueberspringt die TLS-Zertifikatspruefung des Tests. Das schwaecht genau den Transportweg, der den Token traegt. |
| `TokenRef` | String | _(leer)_ | Name des Eintrags in `[SonarTokens]`, der den verschluesselten Token haelt - so kann eine INI mehrere fuehren. |

## Automatisch geschrieben - nicht von Hand aendern

Diese Abschnitte pflegt die Anwendung selbst. Eine Handaenderung haelt nicht;
das naechste Schliessen des Fensters ueberschreibt sie.

| Abschnitt | Schluessel | Geschrieben von |
|---|---|---|
| `[Window]` | `Left`, `Top`, `Width`, `Height`, `Maximized` | EXE, beim Schliessen |
| `[FindingsPropertiesPanel]` | `Left`, `Top`, `Width`, `Height` | IDE-Plugin, beim Schliessen |

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

_Schluessel erhoben durch einen Scan ueber **alle** INI-Leser des Baums
(`uRepoSettings`, `uAppTheme`, `uEditorCommand`, `uCognitiveComplexity`,
`uUiElementRegistry`, …). Die erste Fassung dieser Seite wertete nur zwei
davon aus und uebersah 22 Schluessel. Wer einen Schluessel ergaenzt,
ergaenzt ihn bitte hier - fuer diese Seite gibt es noch keinen Generator._

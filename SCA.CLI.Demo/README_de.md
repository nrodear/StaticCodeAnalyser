# SCA.CLI.Demo

*🇩🇪 Deutsch — 🇬🇧 [English](README.md) — 🇫🇷 [Français](README_fr.md) — Vollständige Engine-/API-Referenz: [../SCA.Engine/API_de.md](../SCA.Engine/API_de.md)*

Minimaler Beispiel-Consumer der **SCA-Engine-API** (`uEngineApi`).

Zeigt, dass die komplette statische Analyse über die öffentliche Facade nutzbar
ist, **ohne** die Engine-Quelltexte zu kennen: dieses Projekt referenziert
ausschließlich das Laufzeit-Package **`SCA.Engine`** (`DCC_UsePackage`) — es
liegt **kein** Engine-Source-Verzeichnis im Suchpfad.

Das Programm scannt ein Verzeichnis rekursiv und gibt nur eine
**Kennwert-Statistik** aus.

## Bauen (RAD Studio / Delphi 12)

Reihenfolge wichtig — das Package muss vor dem Demo vorliegen:

1. `SCA.Engine.dproj` für die Zielplattform bauen (erzeugt `SCA.Engine.dcp`
   + `SCA.Engine290.bpl` im globalen DCP/BPL-Verzeichnis).
2. `SCA.CLI.Demo.dproj` öffnen und bauen (Konsolen-EXE, Win32 oder Win64).

Am einfachsten beide Projekte in eine Projektgruppe legen, die Engine vor
der Demo — die Gruppe baut in ihrer Reihenfolge. Die Paketbindung läuft über
`DCC_UsePackage SCA.Engine` (keine Quelltextpfade).

> Zur Laufzeit müssen `SCA.Engine290.bpl` und die Delphi-Laufzeitpakete, die
> es verlangt (`rtl290.bpl`, `xmlrtl290.bpl`), auffindbar sein (globales
> BPL-Verzeichnis liegt bei installiertem RAD Studio auf dem Pfad; für eine
> eigenständige Auslieferung alle drei `.bpl` neben die `.exe` legen).

## Aufruf

```
SCA.CLI.Demo.exe [<Pfad>] [<Profil>]
```

| Argument | Bedeutung |
|----------|-----------|
| `<Pfad>`   | Wurzelverzeichnis (Default: aktuelles Verzeichnis) |
| `<Profil>` | optional. `''` = alle Detektoren (Default); SCA007 nie, die Demo setzt `UsesCheck` nicht. Bekannt: `default`, `strict`, `ide-fast`, `security`, `bugs-only`, `code-quality`, `style`, `dfm-only`, `selftest-quiet`. Ein unbekannter Name ist wie im CLI kein Fehler: die Engine fährt alle Detektoren, und die Demo sagt das in einer Warnzeile und im Bericht. |

Exit-Code: eigene, vereinfachte Konvention der Demo, **nicht** der Vertrag
der CLI.

| Code | Demo |
|------|------|
| `0` | keine Funde |
| `3` | mindestens ein Fund beliebiger Schwere; Dateifehler zählen mit (ein leerer Ordner ergibt „keine .pas-Dateien“ und damit `3`) |
| `2` | Pfad nicht gefunden |
| `1` | Ausnahme |

Die CLI staffelt dagegen nach Schwere (`1` nur Hints, `2` Warnings, `3`
Errors, `4` Lesefehler, `99` Tool-Fehler), `--fail-on` verschiebt das;
siehe `StaticCodeAnalyser.d12.exe --help`. Kein CI-Gate auf die Codes der
Demo bauen: ihre `2` heißt „Pfad nicht gefunden“, nicht „Warnings“.

## Beispiel-Ausgabe

```
========================================================
 SCA CLI Demo - Kennwert-Statistik
========================================================
  Pfad         : D:\meinprojekt
  Profil       : (alle Detektoren)
  Dauer        : 1234 ms
  Dateien      : 186 (mit Funden)
--------------------------------------------------------
  Funde gesamt : 1156

  Nach Schweregrad:
    Fehler  (Error)  : 36
    Warnung (Warning): 438
    Hinweis (Hint)   : 865

  Nach Kategorie:
    Bug              : 72
    Code Smell       : 980
    Vulnerability    : 18
    Security Hotspot : 4
    Duplication      : 32
    File Error       : 0
========================================================
```

## Was die Demo aus der API benutzt

- `ScanRecursive(Pfad, Profil): TScanResult` — Ein-Zeilen-Rekursiv-Scan.
- `IsKnownProfile(Profil): Boolean` — erkennt einen vertippten Profilnamen.
- `TScanResult.FindingCount / ErrorCount / WarningCount / HintCount` —
  Schweregrad-Kennwerte.
- `TScanResult.Findings` (`TObjectList<TLeakFinding>`) + `TLeakFinding.FindingType`
  / `.FileName` — Kategorie-Aufschlüsselung und Datei-Zählung.

Mehr Kontrolle (Profil, MinSeverity, Baseline, Ignore-Liste, SARIF-/Sonar-/
HTML-Export …) gäbe es über `TScanRequest.Init` + `TAnalysisSession.Run` bzw.
`TScanResult.WriteSarif/WriteSonar/WriteHtml`.

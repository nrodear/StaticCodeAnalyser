# SCA.CLI.Demo

*🇩🇪 Deutsch — 🇬🇧 [English](README.md) — Vollständige Engine-/API-Referenz: [../SCA.Engine/API_de.md](../SCA.Engine/API_de.md)*

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
   + `SCA.Engine.bpl` im globalen DCP/BPL-Verzeichnis).
2. `SCA.CLI.Demo.dproj` öffnen und bauen (Konsolen-EXE, Win32 oder Win64).

Am einfachsten beide Projekte in eine Projektgruppe legen — die
`DCCReference SCA.Engine.dcp` sorgt für die richtige Build-Reihenfolge.

> Zur Laufzeit muss `SCA.Engine.bpl` auffindbar sein (globales BPL-Verzeichnis
> liegt bei installiertem RAD Studio auf dem Pfad; für eine eigenständige
> Auslieferung die `.bpl` neben die `.exe` legen).

## Aufruf

```
SCA.CLI.Demo.exe [<Pfad>] [<Profil>]
```

| Argument | Bedeutung |
|----------|-----------|
| `<Pfad>`   | Wurzelverzeichnis (Default: aktuelles Verzeichnis) |
| `<Profil>` | optional. `''` = alle Detektoren (Default). Bekannt: `default`, `strict`, `ide-fast`, `security`, `bugs-only`, `code-quality`, `dfm-only` |

Exit-Code (wie der CLI): `0` = sauber, `3` = Funde vorhanden, `1`/`2` = Fehler.

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
- `TScanResult.FindingCount / ErrorCount / WarningCount / HintCount` —
  Schweregrad-Kennwerte.
- `TScanResult.Findings` (`TObjectList<TLeakFinding>`) + `TLeakFinding.FindingType`
  / `.FileName` — Kategorie-Aufschlüsselung und Datei-Zählung.

Mehr Kontrolle (Profil, MinSeverity, Baseline, Ignore-Liste, SARIF-/Sonar-/
HTML-Export …) gäbe es über `TScanRequest.Init` + `TAnalysisSession.Run` bzw.
`TScanResult.WriteSarif/WriteSonar/WriteHtml`.

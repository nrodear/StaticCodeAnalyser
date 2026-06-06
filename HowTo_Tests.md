# HowTo: Tests bauen und laufen

Die DUnitX-Test-Suite (`StaticCodeAnalyserForm\tests\TestProject.dproj`)
braucht **zwei externe Komponenten**. Ohne sie scheitert "Alle Projekte
erzeugen" mit `F2613 Unit '...' nicht gefunden`.

| Komponente | Pflicht | Zweck |
|---|---|---|
| **DUnitX** | Pflicht | Test-Framework (Assert/[Test]-Attribute/Runner) |
| **TestInsight** | Win32 optional | IDE-Integration (Tests-Panel, live-Status) |

Das eigentliche SCA-Engine + Standalone-EXE laufen unabhaengig — die
Tests sind nur fuer Entwickler relevant. Wer nur den SCA bauen will,
kann das TestProject im IDE-Build aushaengen (s. Workarounds unten).

---

## Installation

### DUnitX (Pflicht — beide Plattformen)

```bash
cd D:\git-demos\delphi
git clone https://github.com/VSoftTechnologies/DUnitX.git dunitx
```

Im `TestProject.dproj` ist der Pfad `..\..\..\dunitx\Source` bereits in
`DCC_UnitSearchPath` eingetragen (Commit `3f1cab0`). Andere Parent-
Directory? Pfad in der dproj entsprechend anpassen oder via Tools ->
Options -> Language -> Delphi -> Library global setzen (fuer **Win32
und Win64** je separat).

### TestInsight (optional — Win32 IDE-Integration)

Bevorzugt via **GetIt Package Manager**:

1. RAD-Studio IDE -> Tools -> GetIt Package Manager
2. Suche "TestInsight" -> **Install** klicken
3. IDE-Neustart

GetIt setzt Library-Path und installiert das Plugin automatisch.

Falls GetIt-Eintrag nicht da: GitHub/Bitbucket nach
`TestInsight Stefan Glienke` durchsuchen, manuell clonen, die
`TestInsight.RADxx.dpk` kompilieren + installieren, dann `Source/` zum
Win32-Library-Path adden.

---

## Build-Pfade

| Build-Target | Plattform | Voraussetzung |
|---|---|---|
| SCA.Engine.bpl | Win32 + Win64 | rtl, nichts extern |
| SCA.SharedUI.bpl | **nur Win32** | rtl, vcl, designide (IDE-only) |
| StaticCodeAnalyser.exe (Standalone) | Win32 + Win64 | nichts extern |
| StaticCodeAnalyser.IDE.bpl | **nur Win32** | rtl, vcl, designide |
| **TestProject.exe** | Win32 + Win64 | **DUnitX** + (Win32: TestInsight) |

Die Group baut mit "Alle Projekte erzeugen" alle 5 Targets auf der
aktuell gewaehlten Plattform.

---

## Tests laufen

### IDE (Win32 mit TestInsight)

Standard-Setup. Tests-Panel zeigt live Result, Click auf failing Test
springt zur Assertion.

### IDE ohne TestInsight (Win32 oder Win64)

`TestProject.exe` als Standalone-Konsole laufen — DUnitX-Console-Logger
wird verwendet (siehe `TestProject.dpr` Z18-20):

```powershell
".\Output\Tests\Win64 Release\TestProject.exe"
```

Exit-Code 0 = alle gruen. Failures kommen als stdout + nunit-XML
neben der EXE (per `DUnitX.Loggers.Xml.NUnit`).

### Subset laufen lassen

DUnitX-Command-Line nimmt Filter:

```powershell
TestProject.exe --include:TTestUninitVar
TestProject.exe --exclude:TTestPerformance
```

---

## Workarounds

### TestProject komplett vom Build ausnehmen

Wenn Tests gerade nicht relevant sind und nur SCA gebaut werden soll,
in IDE -> Projektgruppe rechtsklicken -> **Build-Auftrag** -> Haken bei
`TestProject.dproj` entfernen. "Alle Projekte erzeugen" ueberspringt
das Projekt dann.

Aequivalent direkt im `.groupproj`: Eintrag fuer TestProject auskommentieren.

### TESTINSIGHT-Define plattform-gated

Im `TestProject.dproj` ist der Define nur fuer Win32 aktiv (Z133):

```xml
<PropertyGroup Condition="'$(Base_Win32)'!=''">
  <DCC_Define>TESTINSIGHT;$(DCC_Define)</DCC_Define>
</PropertyGroup>
```

Win64-Build ueberspringt damit automatisch die TestInsight-Imports und
braucht das Plugin nicht. Wer TestInsight gar nicht haben will, kann
den Eintrag ersatzlos loeschen.

### EFOpenError-Dialog beim Test-Run

Mehrere Tests werfen absichtlich Exceptions (`EFOpenError`,
`Exception`, etc.) um Error-Handling zu verifizieren. Der IDE-Debugger
faengt sie ab und zeigt einen Dialog. Workaround:

- **Im Dialog**: Haken bei "Diesen Exception-Typ ignorieren" +
  Fortsetzen
- **Dauerhaft**: Run -> Run Without Debugging (`Strg+Shift+F9`) statt
  F9 — der Debugger interveniert dann gar nicht
- **Selektiv**: Tools -> Options -> Debugger Options -> Language
  Exceptions -> Exception-Klasse zur Ignore-Liste adden

### Win64-spezifische E2532 bei `Assert.AreEqual(N, X.Count)`

Generic-Inference scheitert unter Win64 wenn untyped Int-Literal +
Integer kombiniert werden. Fix: expliziter Typ-Parameter
`Assert.AreEqual<Integer>(N, X.Count)`. Bereits in 1209 Stellen der
Suite gepatcht (Commit `5f1661c`). Bei neuen Tests beachten.

---

## Verwandte Files im Repo

- `StaticCodeAnalyserForm\tests\TestProject.dproj` — Test-Projekt-Config
- `StaticCodeAnalyserForm\tests\TestProject.dpr` — Test-Runner-Code
- `StaticCodeAnalyserForm\tests\uTest*.pas` — die einzelnen Test-Units
- `HowTo_AddDetector.md` — wenn ein neuer Detektor + Tests anzulegen sind
- `HowTo_DetectorSelftest.md` — Dogfooding-Workflow fuer das SCA-EXE

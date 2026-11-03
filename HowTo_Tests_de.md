# HowTo: Tests bauen und laufen
*🇩🇪 Deutsch — 🇬🇧 [English](HowTo_Tests.md) — 🇫🇷 [Français](HowTo_Tests_fr.md)*

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
cd D:\projects
git clone https://github.com/VSoftTechnologies/DUnitX.git dunitx
```

Neben das Repository klonen: im `TestProject.dproj` ist der Pfad
`..\..\..\dunitx\Source` bereits in `DCC_UnitSearchPath` eingetragen.
Andere Parent-Directory? Pfad in der dproj entsprechend anpassen oder via
Tools -> Options -> Language -> Delphi -> Library global setzen (für
**Win32 und Win64** je separat).

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
| SCA.Engine290.bpl | Win32 + Win64 | rtl, nichts extern |
| SCA.SharedUI290.bpl | Win32 + Win64 | rtl, vcl, vclwinx, SCA.Engine |
| StaticCodeAnalyser.d12.exe (Standalone) | Win32 + Win64 | nichts extern |
| StaticCodeAnalyser.IDE.d12.bpl | Win32; Win64 **nur unter Delphi 13** | rtl, vcl, vclwinx, designide, SCA.Engine, SCA.SharedUI |
| reDelphix.d12.bpl | Win32; Win64 **nur unter Delphi 13** | rtl, vcl, designide, SCA.Engine |
| **TestProject.exe** | Win32 + Win64 | **DUnitX** + TestInsight (siehe unten) |

Die Group baut mit "Alle Projekte erzeugen" jedes Projekt der Gruppe auf
der aktuell gewählten Plattform.

---

## Tests laufen

### IDE (Win32 mit TestInsight)

Standard-Setup. Tests-Panel zeigt live Result, Click auf failing Test
springt zur Assertion.

### IDE ohne TestInsight (Win32 oder Win64)

> **ACHTUNG — mit dem heutigen Stand des Repos geht das NICHT, und der
> Konsolenlauf sieht trotzdem nach Erfolg aus.**
> `TestProject.dproj` setzt `TESTINSIGHT` als `DCC_Define` in der
> **Base**-PropertyGroup, also fuer JEDE Konfiguration und Plattform.
> Damit greift im `.dpr` das `{$IFNDEF TESTINSIGHT}` nicht, die EXE
> bekommt das **GUI**-Subsystem statt Console und laeuft ueber
> `TestInsight.DUnitX` statt ueber den Console-Logger. Ohne
> TestInsight-Server in der IDE beendet sie sofort per `Halt(0)`:
> **kein stdout, keine NUnit-XML, Exit-Code 0.**
>
> Gemessen am 2026-09-20 an beiden frisch gebauten EXEn (Win32 und
> Win64): PE-Subsystem 2 = GUI, 0 Zeilen Ausgabe, Exit 0.
>
> **Exit-Code 0 ist hier also KEIN Testbeweis** - er ist von "alles
> gruen" nicht zu unterscheiden. Ergebnisse gibt es nur im
> TestInsight-Panel der IDE. Wer den Konsolenlauf wirklich will, muss
> `TESTINSIGHT` vorher aus der Base-Gruppe der `.dproj` nehmen.

Der urspruengliche Weg (nur gueltig OHNE das Define):

```powershell
".\Output\Tests\Win64 Release\TestProject.exe"
```

Dann gilt: Exit-Code 0 = alle gruen, Failures als stdout + nunit-XML
neben der EXE (per `DUnitX.Loggers.Xml.NUnit`).

### Subset laufen lassen

Nur ohne das `TESTINSIGHT`-Define (siehe oben): mit ihm erreicht die EXE
`TDUnitX.CheckCommandLine` nie und ignoriert jeden Schalter.

Tests wählt `--run` (kurz `-r`) nach Namen aus. DUnitX benennt eine
Fixture nach Unit und Klasse (`unit.klasse`), einen Test nach seiner
Methode (`unit.klasse.methode`). Ein Name wählt jeden Test, dessen
Fixture-Name mit ihm beginnt (ohne Groß-/Kleinschreibung), ein voller
Testname genau diesen einen Test. Mehrere Namen mit Komma trennen;
`--run` darf auch mehrfach stehen:

```powershell
TestProject.exe --run:uTestUninitVar.TTestUninitVar
TestProject.exe --run:uTestUninitVar.TTestUninitVar.NeverWritten_OnlyRead_Flagged
TestProject.exe --run:uTestUninitVar.TTestUninitVar,uTestPerformance.TTestPerformance
```

Der bloße Klassenname (`--run:TTestUninitVar`) trifft nichts, weil der
Fixture-Name mit der Unit beginnt.

`--include` und `--exclude` filtern nach `[Category]`, nicht nach
Klassennamen. Im Projekt trägt nur `TTestPerformance` eine Kategorie
(`perf`):

```powershell
TestProject.exe --exclude:perf
```

---

## Workarounds

### TestProject komplett vom Build ausnehmen

Wenn Tests gerade nicht relevant sind und nur SCA gebaut werden soll,
in IDE -> Projektgruppe rechtsklicken -> **Build-Auftrag** -> Haken bei
`TestProject.dproj` entfernen. "Alle Projekte erzeugen" ueberspringt
das Projekt dann.

Aequivalent direkt im `.groupproj`: Eintrag fuer TestProject auskommentieren.

### Der TESTINSIGHT-Define

Im `TestProject.dproj` steht der Define in der Base-Gruppe, gilt also für
jede Plattform und Konfiguration:

```xml
<PropertyGroup Condition="'$(Base)'!=''">
  <DCC_Define>TESTINSIGHT;$(DCC_Define)</DCC_Define>
</PropertyGroup>
```

Auch der Win64-Build braucht damit die TestInsight-Units. Wer TestInsight
gar nicht haben will, löscht den Eintrag ersatzlos; dann übernimmt der
Console-Logger.

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
Suite gepatcht. Bei neuen Tests beachten.

---

## Verwandte Files im Repo

- `StaticCodeAnalyserForm\tests\TestProject.dproj` — Test-Projekt-Config
- `StaticCodeAnalyserForm\tests\TestProject.dpr` — Test-Runner-Code
- `StaticCodeAnalyserForm\tests\uTest*.pas` — die einzelnen Test-Units
- `reDelphix\tests\reDelphix.Test.dproj` — Tests der reDelphix-Code-Aktionen;
  die Konfiguration `CI` ist ein Konsolen-Runner mit echtem Exit-Code

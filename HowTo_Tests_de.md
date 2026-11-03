# HowTo: Tests bauen und laufen
*🇩🇪 Deutsch — 🇬🇧 [English](HowTo_Tests.md) — 🇫🇷 [Français](HowTo_Tests_fr.md)*

Die DUnitX-Test-Suite (`StaticCodeAnalyserForm\tests\TestProject.dproj`)
nutzt **zwei externe Komponenten**: DUnitX immer, TestInsight nur in der
Build-Konfiguration `TestInsight`. Fehlt eine, scheitert "Alle Projekte
erzeugen" mit `F2613 Unit '...' nicht gefunden`.

| Komponente | Pflicht | Zweck |
|---|---|---|
| **DUnitX** | Pflicht | Test-Framework (Assert/[Test]-Attribute/Runner) |
| **TestInsight** | optional, nur fuer die Konfiguration `TestInsight` (siehe unten) | IDE-Integration (Tests-Panel, live-Status) |

Das eigentliche SCA-Engine + Standalone-EXE laufen unabhaengig — die
Tests sind nur fuer Entwickler relevant. Wer nur den SCA bauen will,
kann die beiden Testprojekte im IDE-Build aushaengen (s. Workarounds unten).

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

### TestInsight (optional — Win32 und Win64)

Die drei Testprojekte (`TestProject`, `reDelphix.Test`,
`VarNameProject.Test`) definieren `TESTINSIGHT` nur in ihrer
Build-Konfiguration **TestInsight** (siehe _Der TESTINSIGHT-Define_ unten).
Debug und Release kompilieren ohne die TestInsight-Units; gebraucht werden
sie nur fuer das Tests-Panel der IDE.

Bevorzugt via **GetIt Package Manager**:

1. RAD-Studio IDE -> Tools -> GetIt Package Manager
2. Suche "TestInsight" -> **Install** klicken
3. IDE-Neustart

GetIt setzt Library-Path und installiert das Plugin automatisch.

Falls GetIt-Eintrag nicht da: GitHub/Bitbucket nach
`TestInsight Stefan Glienke` durchsuchen, manuell clonen, die
`TestInsight.RADxx.dpk` kompilieren + installieren, dann `Source/` zum
Win32- und zum Win64-Library-Path adden.

---

## Build-Pfade

| Build-Target | Plattform | Voraussetzung |
|---|---|---|
| SCA.Engine290.bpl | Win32 + Win64 | rtl, nichts extern |
| SCA.SharedUI290.bpl | Win32 + Win64 | rtl, vcl, vclwinx, SCA.Engine |
| StaticCodeAnalyser.d12.exe (Standalone) | Win32 + Win64 | nichts extern |
| StaticCodeAnalyser.IDE.d12.bpl | Win32; Win64 **nur unter Delphi 13** | rtl, vcl, vclwinx, designide, SCA.Engine, SCA.SharedUI |
| reDelphix.d12.bpl | Win32; Win64 **nur unter Delphi 13** | rtl, vcl, designide, SCA.Engine |
| **TestProject.exe** | Win32 + Win64 | **DUnitX**; TestInsight nur fuer die Konfiguration `TestInsight` |

Die Group baut mit "Alle Projekte erzeugen" jedes Projekt der Gruppe in
seiner eigenen aktiven Plattform; jedes Projekt merkt sich seine. Vorher
prüfen (siehe [HowTo_Build_de.md](HowTo_Build_de.md), Abschnitt 5.1). Unter
Delphi 12 stoppen die beiden Design-Pakete auf Win64 mit `{$MESSAGE FATAL}`.

---

## Tests laufen

### IDE (Win32 mit TestInsight)

Im Projektfenster die Build-Konfiguration **TestInsight** aktivieren
(Build-Konfigurationen -> Rechtsklick -> **Aktivieren**), dann bauen und
starten. Das Tests-Panel zeigt live das Ergebnis, ein Klick auf einen
roten Test springt zur Assertion.

> **Exit-Code 0 eines TestInsight-Baus ist KEIN Testbeweis.** Er bekommt
> das **GUI**-Subsystem und laeuft ueber `TestInsight.DUnitX`; ohne
> TestInsight-Server in der IDE endet er sofort per `Halt(0)`: kein
> stdout, keine NUnit-XML, Exit-Code 0. Ergebnisse gibt es nur im
> Tests-Panel.

### IDE ohne TestInsight (Win32 oder Win64)

Die Konfigurationen **Debug** und **Release** definieren `TESTINSIGHT`
nicht: die EXE ist ein Konsolenprogramm mit dem Console-Logger.

```powershell
".\Output\Tests\Win64 Release\TestProject.exe"
```

Dann gilt: Exit-Code 0 = alle gruen, 1 = mindestens ein roter Test oder
eine Ausnahme im Runner; Failures als stdout + nunit-XML neben der EXE
(per `DUnitX.Loggers.Xml.NUnit`).

Mit F9 aus der IDE gestartet, schliesst sich das Konsolenfenster, sobald
der Lauf endet. Um die Ergebnisse zu lesen, unter Start → Parameter (Feld
*Parameter*) `--exit:Pause` eintragen: nach der Zusammenfassung wartet der
Runner mit `Done.. press <Enter> key to quit.` Gross-/Kleinschreibung des
Werts ist egal; die Langform des Schalters ist `--exitbehavior:Pause`, die
Vorgabe `Continue`. In Skripten und CI weglassen, sonst wartet der Lauf
auf einen Tastendruck (die Konfiguration `CI` von `reDelphix.Test`
ueberspringt die Pause ohnehin).

### Subset laufen lassen

Geht in jedem Debug- oder Release-Bau. Nur ein Bau in der Konfiguration
`TestInsight` erreicht `TDUnitX.CheckCommandLine` nie und ignoriert jeden
Schalter.

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

### Die Testprojekte komplett vom Build ausnehmen

Wenn Tests gerade nicht relevant sind und nur SCA gebaut werden soll,
in IDE -> Projektgruppe rechtsklicken -> **Build-Auftrag** -> Haken bei
`TestProject.dproj` und `reDelphix.Test.dproj` entfernen. "Alle Projekte
erzeugen" ueberspringt dann beide. Auch `reDelphix.Test.dproj` braucht
DUnitX.

Aequivalent direkt im `.groupproj`: beide Eintraege auskommentieren.

### Der TESTINSIGHT-Define

Jedes der drei Testprojekte setzt ihn nur in der Build-Konfiguration
`TestInsight`, einem Kind von Debug (Schluessel `Cfg_3`, in
`reDelphix.Test.dproj` `Cfg_4`):

```xml
<PropertyGroup Condition="'$(Cfg_3)'!=''">
  <DCC_Define>TESTINSIGHT;$(DCC_Define)</DCC_Define>
</PropertyGroup>
```

Debug und Release (in `reDelphix.Test.dproj` auch `CI`) bauen ohne ihn,
brauchen keine TestInsight-Units und nehmen die DUnitX-Schalter an.
Frueher stand der Define in der Base-Gruppe (in `reDelphix.Test.dproj` in
Debug und Release); jeder IDE-Bau lief dann ueber TestInsight und
ignorierte `--run`.

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
  neben Debug, Release und TestInsight gibt es `CI`, einen Konsolen-Runner,
  der am Ende nie auf einen Tastendruck wartet

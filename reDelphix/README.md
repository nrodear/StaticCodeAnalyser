# reDelphix - Source Refactor fuer den Static Code Analyser

IDE-Package (Delphi 12, Win32), das an Funden des SCA-Plugins Aktionen
anbietet: Stelle zeigen, `Format()` aus einer Verkettung bilden,
parametrisierte SQL-Vorlage, `uses`-Eintraege qualifizieren. Es liest
die Stellen ueber den Quellstellen-Dienst `TSourcePlaces` der SCA-Engine
und schreibt nur in den IDE-Editor - nie in eine Datei, nie ohne
Vergleich gegen den Scan.

Konzept: `Konzept_SourceRefactor_Quellstellen_2026-10-02.md`, Abschnitt 15
(lokal, gitignored).

## Aufbau

```
reDelphix.d12.dpk / .dproj    {$DESIGNONLY}, requires rtl, vcl, designide, SCA.Engine
source\uRdxRegister.pas       Register -> Anbieter an TFindingActions anmelden; finalization: abmelden
source\uRdxProvider.pas       je Fund die Aktionen bauen (Anker/fixMode aus dem Regelkatalog, TSourcePlaces)
source\uRdxEditor.pas         ToolsAPI: Bereich markieren, Bereich ersetzen (mit Puffer-Vergleich), Projekt-Units
source\uRdxRecipes.pas        reine Textlogik: Literal-Codec, Format(), SQL-Vorlage, Rahmenwerk
source\uRdxScopeTable.pas     Kurzname -> qualifizierte Unit (Compiler-Reihenfolge der Scope-Liste)
data\unitscopes.txt           die Scope-Tabelle (erzeugt), als RCDATA eingelinkt (data\unitscopes.rc)
tests\uTestRdxRecipes.pas     DUnitX-Tests fuer Rezepte und Tabelle (laufen auch im FPC-Pruefstand)
tools\gen_unitscopes.py       erzeugt data\unitscopes.txt aus der Delphi-Installation
tools\fpc-pruefstand          baut Core-Units + Modul-Rezepte unter FPC 3.2.2 und fuehrt die Tests aus
```

## Voraussetzungen in der IDE

* **Plugin-Variante B**: `StaticCodeAnalyser.IDE.d12` (requires `SCA.Engine`,
  `SCA.SharedUI`) muss installiert sein, nicht der Monolith
  `StaticCodeAnalyser.Plugin.d12`. reDelphix linkt gegen `SCA.Engine.bpl`;
  neben dem Monolithen liesse sich die Engine nicht laden (doppelte Units).
* SCA-Stand mit Quellstellen-Dienst und Registry "Aktionen am Fund":
  Branch `ah-sourceplaces` (AH2 `uSourcePlaces`, AH6 `uFindingActions`),
  `SCA.Engine.dcp` im Dcp-Verzeichnis der IDE.

## Bauen und installieren

Das Package ist Teil von `StaticCodeAnalyser.d12.groupproj` (letztes
Projekt, abhaengig von `SCA.Engine`) und liegt im SCA-Repo unter
`reDelphix\`. DCUs landen wie bei den anderen Projekten in
`..\Output\reDelphix\`.

1. Die Gruppe bauen (Engine, SharedUI, IDE-Plugin, Tests, reDelphix) und
   das Plugin `StaticCodeAnalyser.IDE.d12` installieren.
2. `reDelphix.d12` im Project Manager **Installieren**.
   BRCC32 erzeugt `unitscopes.res` aus `data\unitscopes.rc`.
3. Datei im Editor oeffnen, mit dem SCA-Plugin scannen, Rechtsklick auf einen
   Fund: hinter dem Trenner stehen die Aktionen von reDelphix. Ein
   ausgegrauter Eintrag nennt den Grund in Klammern.

## Was die Aktionen tun

| Aktion | Regel | Verhalten |
|---|---|---|
| Stelle zeigen | alle mit beschreibbarer Anweisung | markiert den exakten Bereich im Editor |
| Format() aus Verkettung bilden | SCA044 (`fixMode: auto`) | ersetzt die Terme durch `Format('...%s...', [..])`; nur wenn jeder Operand beweisbar ein String ist, `System.SysUtils` in der uses steht und die Literale kein SQL sind |
| Parametrisierte Vorlage in die Zwischenablage | SCA003 (`fixMode: assisted`) | baut `:p1..:pn` und `ParamByName`-Zeilen; schreibt NIE in den Editor |
| uses: X -> Scope.X | Fund in einer uses-Klausel | qualifiziert den Eintrag; Mehrdeutiges (Forms: VCL/FMX) nur bei erkennbarem Rahmenwerk, nie bei gleichnamiger Projekt-Unit |

Beschrieben werden die Stellen auf dem **Editor-Puffer** der offenen Datei
(`TRdxEditor.TryReadBuffer` -> `TSourcePlaces.OpenSource`), nicht auf der
gespeicherten Datei - ungespeicherte Aenderungen sind damit kein
Widerspruch. Vor jedem Schreiben vergleicht `uRdxEditor.ReplaceSpan` den
Bereich im Puffer mit dem beschriebenen Text; weicht er ab (Puffer seit
dem Oeffnen des Menues geaendert, Fund aus einem alten Scan), passiert
nichts, und die Meldung nennt die erste abweichende Stelle. Geschrieben wird ueber
`IOTAEditWriter` mit Byte-Positionen, die aus demselben Puffer gerechnet
sind; jede Aenderung ist mit Strg+Z ruecknehmbar. Die Fundliste des
Plugins wird nicht neu geladen - nach einer Umformung die Datei erneut
scannen.

**Protokoll:** `%TEMP%\reDelphix.log` (und DebugView) - jeder Schritt von
Anbieter, Markieren und Ersetzen mit Quelle (Puffer/Platte), Bytes,
Offsets und Gruenden. Bei einer Fehlermeldung zuerst dort nachsehen.

## Scope-Tabelle pflegen

```
python tools\gen_unitscopes.py            # Studio 23.0 (Delphi 12)
python tools\gen_unitscopes.py "C:\Program Files (x86)\Embarcadero\Studio\37.0"
```

Eine `unitscopes.txt` neben der BPL hat Vorrang vor der eingelinkten
Ressource.

## Pruefen

**`tests\reDelphix.Test.dproj`** (DUnitX, Konsole/TestInsight, in der
d12-Projektgruppe): prueft den ToolsAPI-freien Teil gegen den echten Core.

* `uTestRdxRecipes` - Literal-Codec, Format()-Bau, SQL-Vorlage,
  Scope-Tabelle (reine Textlogik).
* `uTestRdxSca044` - Ende zu Ende je Variante des Detektors SCA044:
  Parser, Detektor, `TSourcePlaces`, `uRdxRecipeRunner` - aktiv bei
  String-Lokalen/Parametern/Feldern, Char, `.ToString`, bekannten
  RTL-Aufrufen, mehrzeilig, Steuerzeichen, `%`; ausgegraut mit Grund bei
  Integer, unbekanntem Ausdruck, Kommentar, `$IFDEF`, SQL-Text,
  fehlendem SysUtils, mehrdeutiger Zeile; Idempotenz nach dem Umschreiben.

Ohne Delphi (nur die Textlogik, FPC 3.2.2):

```
bash tools/fpc-pruefstand/build.sh uTestRdxRecipes
```

`uRdxEditor` und `uRdxProvider` sind ToolsAPI und nur im Package
uebersetzbar; `uRdxRecipeRunner` ist der testbare Kern dazwischen.

## Grenzen (Stand 2026-10-05)

* Nur Delphi 12 / Win32. Fuer Delphi 13 (64-Bit-IDE) braucht es ein zweites
  Paket mit Win64-Ziel.
* Die Scope-Aufloesung bildet die VORGABE-Listen der Unit-Scopes nach; ein
  Projekt mit eigener `DCC_Namespace`-Liste wird nicht gelesen.
* Delphi-12-Mehrzeilen-Literale (`'''`) kennt der Literal-Codec nicht.

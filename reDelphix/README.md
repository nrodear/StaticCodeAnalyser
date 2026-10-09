# reDelphix - Source Refactor fuer den Static Code Analyser

IDE-Package (Delphi 12, Win32), das an Funden des SCA-Plugins Aktionen
anbietet: `Format()` aus einer Verkettung bilden, parametrisierte
SQL-Vorlage, `uses`-Eintraege qualifizieren, die Editorhilfen
`FreeAndNil(X)`, `Assigned()` und `(TObject)` entfernen, Unterdruecken und
Stelle zeigen. Es liest die Stellen ueber den Quellstellen-Dienst
`TSourcePlaces` der SCA-Engine und schreibt nur in den IDE-Editor - nie in
eine Datei und nie, ohne vorher jeden Bereich im Puffer mit dem Text zu
vergleichen, auf dem die Aktion beim Menueaufbau beschrieben wurde (siehe
"Welcher Text gilt").

Konzept: `Konzept_SourceRefactor_Quellstellen_2026-10-02.md`, Abschnitt 15
(in `reDelphix\`), Editorhilfen: `Konzept_Editorhilfen_2026-10-08.md`
(Repo-Wurzel) - beide lokal, gitignored.

## Aufbau

```
reDelphix.d12.dpk / .dproj        {$DESIGNONLY}, requires rtl, vcl, designide, SCA.Engine
source\uRdxRegister.pas           Register -> Anbieter an TFindingActions anmelden; finalization: abmelden
source\uRdxProvider.pas           je Fund die Aktionen bauen (Anker/fixMode aus dem Regelkatalog); Quell-Cache TRdxSourceCache
source\uRdxRecipeRunner.pas       Rezept-Laeufer auf TSourcePlaces: Fund -> Beschreibung -> Ersetzung; ohne ToolsAPI, testbar
source\uRdxRecipes.pas            reine Textlogik: Literal-Codec, Format() nach der Kompilat-Regel, SQL-Vorlage, uses-Schreibweise, Rahmenwerk
source\uRdxScopeTable.pas         Kurzname -> qualifizierte Unit (Compiler-Reihenfolge der Scope-Liste)
source\uRdxSimpleFixes.pas        Editorhilfen SCA075/SCA085/SCA126 (reine Textlogik)
source\uRdxSuppress.pas           Unterdrueck-Marker setzen und entfernen (reine Textlogik)
source\uRdxBufferMath.pas         Zeile/Spalte -> Byte im UTF-8-Puffer, Pruefung aller Ersetzungen, Spaltengrenze, Textwahl
source\uRdxEditor.pas             ToolsAPI: Puffer lesen, Bereich markieren, Bereiche ersetzen (ein Undo-Schritt), Projekt-Units
source\uRdxLog.pas                Protokoll %TEMP%\reDelphix.log + DebugView
data\unitscopes.txt               die Scope-Tabelle (erzeugt), als RCDATA eingelinkt (data\unitscopes.rc)
tests\reDelphix.Test.dpr/.dproj   DUnitX-Testprojekt mit 8 Testunits (siehe "Pruefen")
tools\gen_unitscopes.py           erzeugt data\unitscopes.txt aus der Delphi-Installation
tools\fpc-pruefstand\build.sh     baut Core-Units + Modul-Textlogik unter FPC 3.2.2 und fuehrt Tests aus
tools\probe\RdxCorpusProbe.dpr    Korpus-Probe: Rezept 5.1 ueber eine Liste von Fundstellen, CSV
tools\probe\sites_from_sarif.py   Fundstellen einer Regel aus einem SARIF-Lauf ziehen
```

## Voraussetzungen in der IDE

* **Plugin-Variante B**: `StaticCodeAnalyser.IDE.d12` (requires `SCA.Engine`,
  `SCA.SharedUI`) muss installiert sein, nicht der Monolith
  `StaticCodeAnalyser.Plugin.d12`. reDelphix linkt gegen `SCA.Engine.bpl`;
  neben dem Monolithen liesse sich die Engine nicht laden (doppelte Units).
* SCA-Stand mit Quellstellen-Dienst (AH2 `uSourcePlaces`) und Registry
  "Aktionen am Fund" (AH6 `uFindingActions`, mit `fakNavigate` und
  `fakSuppress`), `SCA.Engine.dcp` im Dcp-Verzeichnis der IDE.
* reDelphix ist gegen Version 1 des Quellstellen-Vertrags geschrieben.
  `uRdxRecipeRunner` prueft `SOURCE_PLACES_VERSION` beim Uebersetzen
  (`{$IF SOURCE_PLACES_VERSION <> 1}` mit `{$MESSAGE ERROR}`): hebt die
  Engine die Version, bricht der Bau von reDelphix ab, bis der Laeufer
  gegen den neuen Vertrag geprueft ist. Eine zur Laufzeit getauschte BPL
  erkennt die Konstante nicht - das leistet die Paketbindung.

## Bauen und installieren

Das Package ist Teil von `StaticCodeAnalyser.d12.groupproj` und liegt im
SCA-Repo unter `reDelphix\`. In der Gruppe steht es nach dem IDE-Plugin;
danach folgen TestProject, reDelphix.Test und RdxCorpusProbe. Es haengt von
`SCA.Engine` ab (das Package bindet `SCA.Engine.dcp`); die Gruppe traegt
das als Abhaengigkeit, ein einzelnes "Erzeugen" von `reDelphix_d12` baut
die Engine also vorher. DCUs landen wie bei den anderen Projekten in
`..\Output\reDelphix\`.

1. Die Gruppe bauen (Engine, SharedUI, IDE-Plugin, reDelphix, Tests) und
   das Plugin `StaticCodeAnalyser.IDE.d12` installieren.
2. `reDelphix.d12` im Project Manager **Installieren**.
   BRCC32 erzeugt `unitscopes.res` aus `data\unitscopes.rc`. Nach einer
   Aenderung an `data\unitscopes.txt` das Package bereinigen und neu
   erzeugen - die IDE bemerkt die geaenderte Tabelle nicht, und die alte
   Ressource bliebe eingelinkt.
3. Datei im Editor oeffnen und mit dem SCA-Plugin scannen. Die Aktionen
   stehen an drei Stellen:
   * Rechtsklick auf einen Fund im Dock-Grid oder im Editor-Kontextmenue:
     hinter dem Trenner alle Aktionen von reDelphix. Ein ausgegrauter
     Eintrag nennt den Grund in Klammern.
   * Die Gluehbirne im Editor (an der Caret-Zeile) zeigt nur die
     ausfuehrbaren Hilfen - ohne "Stelle zeigen", ohne ausgegraute
     Eintraege. Unterdruecken steht dort nur, wenn es zum Fund auch eine
     Hilfe gibt.
   * Ein `&` in einem Menuetext (aus einem Meldetext, Bezeichner oder
     Grund) erscheint woertlich, nicht als Tastenkuerzel: das Plugin
     verdoppelt es fuer das Menue.

## Was die Aktionen tun

| Aktion | Regel | Verhalten |
|---|---|---|
| Stelle zeigen | alle mit beschreibbarer Anweisung (Anker der Regel) | markiert den exakten Bereich im Editor. Nur Kontextmenue und Dock-Grid (`fakNavigate`), nicht die Gluehbirne. Ausgegraut, wenn der Bereich hinter Spalte 32767 bzw. hinter 32766 Bytes seiner Zeile liegt (die Editor-Markierung rechnet in SmallInt); liegt er beim Klick hinter dem Pufferende, meldet die Aktion das und markiert nichts |
| Format() aus Verkettung bilden | SCA044 (`fixMode: auto`) | ersetzt die Terme durch `Format('...%s...', [..])` nach der Kompilat-Regel (unten). `IntToStr(n)` mit bekanntem Ganzzahltyp wird `%d`/`%u` mit `n`; `n.ToString` bleibt `%s`. Ein Char-Operand bekannten Typs geht als `string(c)` hinein, damit ein `#0` erhalten bleibt. `X := X + ...` wird `X := X + Format(...)`. Gesperrt bei SQL-Literalen, Kommentar oder Direktive im ersetzten Bereich, Variant-Anzeichen, Zahl-Operanden, Nicht-Unicode-Strings. Fehlt `System.SysUtils` (dort lebt `Format`), wird es als zweite Ersetzung in die uses-Klausel eingefuegt (unten) - der Menuetext sagt `+ uses System.SysUtils` bzw. `+ uses SysUtils` |
| Parametrisierte Vorlage in die Zwischenablage | SCA003 (`fixMode: assisted`) | baut `:p1..:pn` und `ParamByName`-Zeilen, eingerueckt wie die Anweisung (Tabs bleiben Tabs). Ist das Ziel kein Query-Objekt (kein Glied `.SQL` oder `.CommandText`, etwa ein String-Puffer `S`), stehen die `ParamByName`-Zeilen als Kommentar mit dem Platzhalter `<Query>` da. Schreibt NIE in den Editor |
| uses: X -> Scope.X | Fund in einer uses-Klausel, auch der Programm-Klausel einer .dpr/.lpr | qualifiziert den Eintrag, dazu "uses: alle n Eintraege qualifizieren". Mehrdeutiges (Forms: VCL/FMX) nur bei erkennbarem Rahmenwerk, nie bei gleichnamiger Projekt-Unit und nie, wenn die Reihenfolge System/Vcl der Projekt-Scopes entscheiden wuerde. Gesperrt, wenn eine uses-Klausel Compiler-Direktiven traegt oder in einem `$IFDEF`-Zweig liegt |
| FreeAndNil(X) verwenden | SCA085 | `X.Free;` + `X := nil;` -> `FreeAndNil(X);`. X muss in der Unit deklariert sein (keine Property, kein geerbtes Feld); gesperrt in einem `with`-Block. Fehlt `System.SysUtils`, kommt die uses-Einfuegung mit (unten) |
| Assigned() statt Vergleich mit nil verwenden | SCA126 | schreibt ALLE nil-Vergleiche der einen Anweisung um, die auf der Fundzeile beginnt (`X = nil` -> `not Assigned(X)`). Zwei solche Anweisungen auf der Zeile heissen mehrdeutig; ein Operand vom Typ String, Variant, Menge, Array oder Prozedur/Ereignis sperrt |
| (TObject) aus der Klassendeklaration entfernen | SCA075 | `class(TObject)` -> `class` an der Spalte aus der Meldung (nur Zeilen, ohne Parser) |
| Hier / In dieser Datei unterdruecken | jeder Fund in Pascal-Quelltext | setzt `// noinspection <Art>` ueber die Fundzeile bzw. `// noinspection-file <Art>` (`fakSuppress`). Einen wirkungslosen Marker (SCA165) entfernt "Wirkungslosen Unterdrueck-Marker entfernen" stattdessen |

**uses-Ergaenzung im Einzelnen** (`TRdxRecipeRunner.PlanUses`, fuer
`Format()` und `FreeAndNil(X)`):

* **Welche Klausel:** die des implementation-Abschnitts, sonst die des
  interface-Abschnitts, sonst die Programm-Klausel (.dpr, .lpr, library).
  Ohne jede uses-Klausel wird hinter `implementation` (sonst hinter
  `interface`) eine neue angelegt. Ein Programm oder eine Library ohne
  uses-Klausel bekommt keine: der Eintrag bleibt ausgegraut
  (`System.SysUtils fehlt in uses: keine uses-Klausel und kein
  interface/implementation`).
* **Welcher Name:** `System.SysUtils`, wenn die Datei Delphi-Unit-Scopes
  schreibt (ein Eintrag unter `System.`, `Winapi.`, `Vcl.`, `FMX.`,
  `Data.`, ...) oder noch keinen uses-Eintrag hat, sonst `SysUtils` - ein
  Punkt allein ist kein Scope (`Generics.Collections`, `MyLib.Utils`). Eine
  Datei mit FPC-Weiche oder FPC-Modus (`{$IFDEF FPC}`, `{$IFNDEF FPC}`,
  `DEFINED(FPC)`, `{$mode ..}`, auch als `(*$..*)`) bekommt immer
  `SysUtils`: FPC 3.2 kennt keine Unit-Scopes.
* **Wohin in der Liste:** eine sortierte Liste bleibt sortiert (dasselbe
  Kriterium wie SCA142), eine unsortierte bekommt den Namen vorn. Gehoert
  der Name ans Ende, wird hinter dem letzten Eintrag angehaengt - samt
  `in`-Pfad und Block-Kommentar ohne `$` (`Main in 'Main.pas' {Form1}`),
  wenn danach auf derselben Zeile das `;` folgt, oder wenn die Zeile hinter
  dem Eintrag endet und die naechste nicht leere Zeile mit `;` beginnt.
  Steht dort etwas anderes (ein `//`-Kommentar, das `;` erst nach weiterem
  Text), wird VOR dem letzten Eintrag eingefuegt: immer gueltig, aber die
  Sortierung kann dann brechen.
* **Gesperrt** (Handarbeit): eine Compiler-Direktive in der Klausel (`{$..}`
  oder `(*$..*)`, von der Zeile des `uses` bis zum letzten Eintrag) oder
  eine Klausel, die ganz oder teilweise in einem `$IFDEF`-Zweig liegt - ein
  Eintrag dort kann in einem Zweig fuer ein anderes Ziel stehen.
* Beide Ersetzungen (Kette und Klausel) werden vor dem Schreiben gegen den
  Puffer geprueft und dann in EINEM Undo-Schritt geschrieben.

**Kompilat-Regel** (`TRdxRecipes.JudgeOperand`, Realworld-Stichprobe
2026-10-06): mit "nur beweisbar String" waeren am Korpus hoechstens 17 %
der SCA044-Stellen umformbar - der haeufigste Blocker waren Bezeichner
wie `sLineBreak` und Member wie `E.Message`, die in der Datei keinen
deklarierten Typ haben. Das Kompilat buergt aber: eine `+`-Kette mit einem
String-Literal uebersetzt nur, wenn jeder Operand String-vertraeglich ist
(String, Char, PChar, AnsiString, ...) oder ein Variant - und `%s` nimmt
all das, Variant eingeschlossen. Die einzige Luecke: hinter einem Variant
darf auch eine Zahl oder ein Boolean stehen, und daran scheitert `%s` zur
Laufzeit. Deshalb gilt ein Operand unbekannten Typs, wenn seine Form ein
Operand ist (Bezeichner, Member, Aufruf, Index, Cast) und er keine
Variant-Anzeichen traegt (`.Value`, `.AsVariant`, `FieldValues`, `Null`,
`Unassigned`, `True`/`False`/`nil`, `Variant(...)`, deklariert `Variant`,
`V.Name` mit `V: Variant`, `DS['Name']` = `TDataSet.FieldValues`). Warum
Variant sperrt: ist der Wert Null oder keine Zeichenkette, wirft das
Original (`NullStrictConvert`, Variant-Arithmetik String+Zahl) oder die
ganze Kette wird leer - `Format` gaebe still die uebrigen Teile aus.
Gesperrt bleiben Zahlen, Zahl-Casts, Aufrufe mit Zahl-Ergebnis (`Length`,
`Ord`, `Pos`, `StrToInt`, ...), blosse Klammerausdruecke, Mengen und
Nicht-Unicode-Strings - deklariert (`AnsiString`, `RawByteString`,
`UTF8String`, `ShortString`, `RawUtf8`) oder als Cast bzw. Funktion
(`AnsiString(x)`, `UTF8Encode(s)`, ...) - als Ziel immer und als Operand,
wenn das Ziel nicht nachweislich Unicode ist: `Format` liefert
`UnicodeString`. Ein `AnsiChar`-Operand sperrt immer (`Format` wandelt ihn
ohne Codepage). `(Sender as TButton).Caption` ist ein Operand. Der
Menuetext nennt die Herkunft: `5 Terme, 2 laut Kompilat (E.Message,
Edit1.Text)` oder `alle bewiesen`. Bewiesen sind Literale, deklarierte
String-Typen, RTL-Funktionen mit String-Ergebnis (`IntToStr`,
`ExtractFileName`, `Copy`, `TPath.Combine`, ...), RTL-Konstanten
(`sLineBreak`, `PathDelim`) und `.ToString`. In einem `with`-Block ist
kein Name bewiesen (er kann an ein Member des with-Ausdrucks binden), und
der Core nimmt den RTL-Beweis zurueck, wenn die Unit selbst eine
gleichnamige Funktion ohne String-Ergebnis deklariert
(`function Trim(..): Variant`): dort buergt nur das Kompilat, und
`IntToStr(x)` bleibt als Operand stehen statt `%d` zu werden. Nachbildung
am Korpus: 83 % statt 17 %.

Bekannte Grenzen: ein Record mit Implicit-Operator (`Nullable<string>`)
uebersetzt in der Kette, aber nicht im `Format`-Aufruf - der Compiler
meldet es, Strg+Z nimmt es zurueck; ohne Typinformation fremder Units ist
das nicht erkennbar. `x.ToString` bleibt `%s` (ein eigener Integer-Helper
koennte anders formatieren); nur `IntToStr(x)` wird `%d`/`%u`. Ein
Char-Operand unbekannten Typs (`S[i]`, `Obj.Ch`) geht ohne `string()`
hinein. Eine unit-lokale Funktion, die einen Namen aus der eigenen
RTL-Liste des Moduls verdeckt (`Copy`, `ExtractFileName`, ...), erkennt
reDelphix ausserhalb von with-Bloecken nicht - das betrifft nur den Hinweis
`alle bewiesen`, umgeformt wuerde auch laut Kompilat. Die Literale werden
Token fuer Token in den Formatstring uebernommen (`#$2103` bleibt
`#$2103`, `#37` wird `%%`), Leerraum in String-Literalen eines Operanden
bleibt erhalten. Ein Kommentar sperrt nur, wenn er im ERSETZTEN Bereich
steht; `{$` in einem String-Literal sperrt nicht.

## Welcher Text gilt

* **Beschrieben** werden die Stellen auf dem **Editor-Puffer** der offenen
  Datei (`TRdxEditor.ReadBuffer` -> `TSourcePlaces.OpenSource`), auch mit
  ungespeicherten Aenderungen; ist die Datei nicht im Editor offen, auf
  der Platte wie beim Scan. Ist sie offen, ihr Puffer aber leer oder nicht
  lesbar, kommt nur der ausgegraute Eintrag `reDelphix: Editor-Puffer leer
  oder nicht lesbar` - kein stiller Rueckfall auf die Platte.
* **Geparst** wird nur, wenn sich etwas geaendert hat: die zuletzt
  geoeffnete Quelle bleibt offen (`TRdxSourceCache`), gleicher Name,
  gleiche Herkunft (Puffer/Platte) und gleicher Text heissen kein neuer
  Parse. Gelesen wird der Puffer trotzdem je Fund neu - die ToolsAPI hat
  keinen Aenderungszaehler.
* **Gegenprobe gegen den Fund:** die Fundliste kann aelter sein als der
  Puffer. Fuer SCA044 und SCA003 muss die Anweisung auf der Fundzeile das
  Ziel tragen, das die Meldung nennt, bei SCA044 auch genau so viele `+`
  wie gemeldet (`TRdxRecipeRunner.QueryOf`/`Describe`). Sonst entfallen
  die Umformungen mit dem Grund `Zeile n traegt X, der Fund nennt Y -
  Zeile verschoben? Datei neu pruefen` bzw. `Kette auf Zeile n hat a x
  '+', der Fund nennt b - Zeile veraendert? Datei neu pruefen`. Zerfaellt
  die Kette im Quelltext anders als im Parser-Knoten (zweite
  `+`-Zaehlung in `TSourcePlaces.ChainOf`), bleibt nur "Stelle zeigen",
  und `Format()` nennt `keine Zuweisung mit Kette: <Grund>`.
* **Vor dem Schreiben** prueft `TRdxEditor.ReplaceSpans` JEDEN Bereich
  einer Aktion gegen den Text, auf dem sie beim Menueaufbau beschrieben
  wurde - als Zeilen und als die Bytes, die tatsaechlich ersetzt werden
  (`uRdxBufferMath.PlanByteEdits`). Weicht einer ab (Puffer seit dem
  Oeffnen des Menues geaendert, auch ein inzwischen leerer Puffer), wird
  KEINER geschrieben, und die Meldung nennt die erste abweichende Stelle.
* **Geschrieben** wird ueber `IOTAEditWriter` mit Byte-Positionen, die aus
  demselben Puffer gerechnet sind; alle Ersetzungen einer Aktion laufen
  durch EINEN Writer - ein Strg+Z nimmt die ganze Aktion zurueck.
* **Markiert** ("Stelle zeigen") wird ueber die Cursor-API, deren Spalten
  SmallInt sind: hinter Spalte 32767 bzw. hinter 32766 Bytes einer Zeile
  ist der Eintrag ausgegraut (`Zeile zu lang fuer die Editor-Markierung`),
  hinter dem Pufferende meldet die Aktion `... liegt hinter dem Ende des
  Editor-Puffers ... - Datei neu pruefen`.
* Die Fundliste des Plugins wird nicht neu geladen - nach einer Umformung
  die Datei erneut scannen.

**Protokoll:** `%TEMP%\reDelphix.log` (und DebugView) - jeder Schritt von
Anbieter, Markieren und Ersetzen mit Quelle (Puffer/Platte, neu geparst
oder wiederverwendet), Bytes, Offsets und Gruenden. Ist die Datei vor dem
Anhaengen groesser als 1 MiB, wird sie zu `reDelphix.log.1` (ein
frueheres `.1` entfaellt) und eine neue begonnen; beide zusammen bleiben
so bei etwa 2 MB, auch wenn die Gluehbirne bei jeder Caret-Zeile fragt.
Bei einer Fehlermeldung zuerst dort nachsehen.

## Scope-Tabelle pflegen

```
python tools\gen_unitscopes.py            # Studio 23.0 (Delphi 12)
python tools\gen_unitscopes.py "C:\Program Files (x86)\Embarcadero\Studio\37.0"
```

Fehlt `source` oder `lib\win32\release` der Installation oder findet das
Skript keine Unit, bricht es mit Exit 2 ab und laesst die Tabelle stehen;
sonst ersetzt es sie in einem Zug. Danach `reDelphix.d12` bereinigen und
neu erzeugen (siehe "Bauen und installieren"). Eine `unitscopes.txt` neben
der BPL hat Vorrang vor der eingelinkten Ressource.

## Pruefen

**`tests\reDelphix.Test.dproj`** (DUnitX, Konsole/TestInsight, in der
d12-Projektgruppe): prueft den ToolsAPI-freien Teil gegen den echten Core.

* `uTestRdxRecipes` - Literal-Codec, Format()-Bau, SQL-Vorlage,
  Scope-Tabelle (auch die echte `data\unitscopes.txt`),
  uses-Schreibweise/-Sortierung/-Einfuegestelle, Kompilat-Regel
  (Operandenform, Variant-Anzeichen, RTL-Konstanten und -Funktionen,
  Herkunft der Argumente, `%d`/`%u`) - reine Textlogik.
* `uTestRdxSca044` - Ende zu Ende je Variante des Detektors SCA044:
  Parser, Detektor, `TSourcePlaces`, `uRdxRecipeRunner` - aktiv bei
  String-Lokalen/Parametern/Feldern, Char, `.ToString`, bekannten
  RTL-Aufrufen, mehrzeilig, Steuerzeichen, `%`, Anweisung in einem
  `$IFDEF`-Zweig, Member/unbekanntem Aufruf (Kompilat), `sLineBreak`,
  `IntToStr(Integer)` als `%d` und `IntToStr(Cardinal)` als `%u`,
  `X := X + ...`; ausgegraut mit Grund bei Integer, Variant (deklariert
  oder `.Value`), AnsiString als Ziel oder Operand, Kommentar oder
  Direktive im Bereich, SQL-Text, mehrdeutiger Zeile, nur Literalen
  hinter `X +`, Kette ohne Literal, Kette mit `Format()` darin (ein
  zweiter Lauf ueber eine umgeformte Zeile findet nichts mehr), Ziel oder
  `+`-Zahl passt nicht zum Fund; `with`-Block nur laut Kompilat;
  Idempotenz nach dem Umschreiben. uses-Ergaenzung: vorhanden
  (qualifiziert/unqualifiziert) -> nichts; fehlend -> sortiert eingefuegt,
  Schreibweise der Datei (FPC-Weiche, Punktnamen ohne Scope),
  implementation vor interface, mehrzeilige Klausel, `in`-Pfad und
  Block-Kommentar hinter dem letzten Eintrag (angehaengt), `//`-Kommentar
  (vor dem letzten), Direktive oder `$IFDEF`-Zweig (gesperrt), keine
  Klausel -> neue hinter `implementation`, Programm ohne Klausel
  (gesperrt); zweite Kette nach der ersten Umformung braucht nichts mehr.
  Die Tests wenden beide Ersetzungen auf den Text an und lassen den
  Detektor erneut laufen. Dazu die SCA003-Vorlage Ende zu Ende (Aufruf
  und Zuweisung, Tabs, Mehrdeutigkeit).
* `uTestRdxActionRing` - der Ring, in dem der Anbieter seine
  Aktionsobjekte haelt (Besitz, Chargen, Grenzen).
* `uTestRdxBufferMath` - Zeile/Spalte -> Byte im UTF-8-Puffer mit
  Tabulator, Umlaut, Surrogatpaar und kombinierendem Zeichen (CRLF, LF,
  CR), Pruefung aller Ersetzungen einer Aktion, Spaltengrenze 32767,
  Textwahl Puffer/Platte/gesperrt.
* `uTestRdxSuppress` - Unterdrueck-Marker setzen und entfernen.
* `uTestRdxSimpleFixes` / `uTestRdxNilFix` - die Editorhilfen
  SCA075/SCA085 bzw. SCA126 auf Text, ohne Parser.
* `uTestRdxSimpleFixesDetector` - dieselben Hilfen gegen den echten
  Detektor: nach der Hilfe meldet er nichts mehr; die Katalog-Beispiele
  `bad` werden genau `good`.

Ohne Delphi (FPC 3.2.2):

```
bash tools/fpc-pruefstand/build.sh uTestRdxRecipes uTestRdxBufferMath uTestRdxSuppress uTestRdxSimpleFixes uTestRdxNilFix
```

Der Pruefstand uebersetzt die Core-Units des Quellstellen-Dienstes
(`uRefactor*`, `uSourcePlaces`, `uFindingActions`, `ScanCodeLine` aus
`uDetectorUtils`) mit Stubs fuer Parser und Resolver sowie die Textlogik
des Moduls (`uRdxRecipes`, `uRdxScopeTable`, `uRdxBufferMath`,
`uRdxSuppress`, `uRdxSimpleFixes`). Testunits kommen aus `reDelphix\tests`,
sonst aus `StaticCodeAnalyserForm\tests` (Core-Tests wie
`uTestSourcePlaces`, `uTestRefactorConcat`).

* **Pfadregel:** die SCA-Wurzel ist der Checkout, in dem das Skript liegt
  (das Verzeichnis ueber `reDelphix`) - Core, Rezepte und Tests kommen so
  immer aus EINEM Stand, auch in einem Worktree oder zweiten Klon.
  `SCA_ROOT=<pfad>` ueberschreibt das bewusst. Die erste Zeile des Laufs
  nennt beide Wurzeln mit Branch und Commit.
* Kopien eines frueheren Laufs loescht das Skript vor dem Kopieren; eine
  fehlende Pflichtquelle oder Testunit bricht ab, statt still eine alte
  Kopie zu uebersetzen.
* **Exit:** 0 alle Tests gruen; 1 Test rot oder Bau gescheitert; 2 Aufruf-
  oder Quellfehler, auch wenn die Zahl der `[Test]`-Attribute einer
  Testunit nicht zur Zahl der erkannten Testmethoden passt.

`uRdxEditor` und `uRdxProvider` sind ToolsAPI und nur im Package
uebersetzbar; `uRdxRecipeRunner` ist der testbare Kern dazwischen (in
reDelphix.Test, nicht im FPC-Pruefstand).

## Korpus-Probe

**`tools\probe\RdxCorpusProbe.dproj`** (Konsole, in der d12-Projektgruppe)
faehrt Rezept 5.1 ueber eine Liste von Fundstellen (`Datei<TAB>Zeile`)
und schreibt je Stelle eine CSV-Zeile plus eine Zusammenfassung mit den
Gruenden - der echte Weg des Moduls ohne ToolsAPI, also die echten Zahlen
zu jeder Regelaenderung. Eine Ausnahme kostet nur die betroffene Datei
bzw. Stelle (Kategorie `Parser: <Klasse>` bzw. `Ausnahme: <Klasse>`), nie
den Lauf; ein Pfad mit `;` steht in der CSV in Anfuehrungszeichen. Die
Liste kommt aus einem SARIF-Referenzlauf:

```
python reDelphix\tools\probe\sites_from_sarif.py rw137_ae.sarif SCA044 D:\git-sca-realworld sites.txt
python reDelphix\tools\probe\sites_from_sarif.py rw137_ae.sarif SCA044 D:\git-sca-realworld sample.txt 200 44
Output\RdxCorpusProbe\Win32 Release\RdxCorpusProbe.exe sites.txt probe.csv
```

Die zweite Form zieht eine reproduzierbare Stichprobe (N, seed). Die
Korpuswurzel ersetzt die `uriBaseId` des Laufs. `sites_from_sarif.py`
dekodiert die uri, wie der SARIF-Export sie kodiert: Prozent-Kodierung
(`%20`, `%25`, `%23`, `%3F`) wird aufgeloest, `file:///C:/...`- und
`file://server/...`-uris (Dateien ausserhalb der Scanwurzel) bleiben
absolut, fuer sie gilt die Korpuswurzel nicht. Stellen, deren Datei es
nicht gibt, meldet das Skript am Ende als `WARNUNG: n Stellen: Datei
fehlt` - ein falscher Wurzelpfad faellt so sofort auf, statt nur die
Aktiv-Quote der Probe zu druecken. Exit 2 bei falschem Aufruf, nicht
lesbarer Eingabe oder nicht schreibbarer Ausgabe. Die Python-Nachbildung
der Regeln (Audit 2026-10-06) ist eine Obergrenze; was zaehlt, ist die
Probe.

## Grenzen (Stand 2026-10-09)

* Nur Delphi 12 / Win32. Fuer Delphi 13 (64-Bit-IDE) braucht es ein zweites
  Paket mit Win64-Ziel.
* Die Scope-Aufloesung bildet die VORGABE-Listen der Unit-Scopes nach; ein
  Projekt mit eigener `DCC_Namespace`-Liste wird nicht gelesen. Wo die
  Reihenfolge System/Vcl entscheiden wuerde (heute nur `Skia`), wird
  deshalb nicht geraten.
* Delphi-12-Mehrzeilen-Literale (`'''`) kennt der Literal-Codec nicht; eine
  Anweisung mit einem solchen Literal beschreibt der Core gar nicht, es
  gibt dort also keine Umformung.
* In einem `with`-Block gilt kein Name als bewiesen (Kompilat-Regel oben),
  und `FreeAndNil(X)` wird dort nicht angeboten.

# reDelphix - Source Refactor fuer den Static Code Analyser

IDE-Package (Delphi 12, Win32), das an Funden des SCA-Plugins Aktionen
anbietet: `Format()` aus einer Verkettung bilden, parametrisierte
SQL-Vorlage, `uses`-Eintraege qualifizieren, die Quick-Fixes
`FreeAndNil(X)`, `Assigned()`, `(TObject)` entfernen, Assert-Meldung,
leeren Sichtbarkeitsabschnitt, leere Klammern und ueberfluessige Vergleiche
mit True/False bzw. nil entfernen, `if C then X := True else X := False`
durch `X := C` ersetzen, ueberfluessige `Exit;`/`Continue;` und
Selbstzuweisungen entfernen, Unterdruecken und Stelle zeigen. Es liest die Stellen ueber den Quellstellen-Dienst
`TSourcePlaces` der SCA-Engine und schreibt nur in den IDE-Editor - nie in
eine Datei und nie, ohne vorher jeden Bereich im Puffer mit dem Text zu
vergleichen, auf dem die Aktion beim Menueaufbau beschrieben wurde (siehe
"Welcher Text gilt").

Konzept: `Konzept_SourceRefactor_Quellstellen_2026-10-02.md`, Abschnitt 15
(in `reDelphix\`), Code-Aktionen (frueher "Editorhilfen"): `Konzept_Editorhilfen_2026-10-08.md`
(Repo-Wurzel) - beide lokal, gitignored.

## Aufbau

```
reDelphix.d12.dpk / .dproj        {$DESIGNONLY}, requires rtl, vcl, designide, SCA.Engine
source\uRdxRegister.pas           Register -> Anbieter an TFindingActions anmelden; finalization: abmelden
source\uRdxProvider.pas           je Fund die Aktionen bauen (Anker/fixMode aus dem Regelkatalog); Quell-Cache TRdxSourceCache
source\uRdxRecipeRunner.pas       Rezept-Laeufer auf TSourcePlaces: Fund -> Beschreibung -> Ersetzung; ohne ToolsAPI, testbar
source\uRdxFixTable.pas           Tabelle der einfachen Hilfen: je Fundart Planer, Hinweis, Kennzeichnung (E2), zweiter Eintrag, Menuetext (Charge R8); ohne ToolsAPI
source\uRdxRecipes.pas            reine Textlogik: Literal-Codec, Format() nach der Kompilat-Regel, SQL-Vorlage, uses-Schreibweise, Rahmenwerk
source\uRdxScopeTable.pas         Kurzname -> qualifizierte Unit (Compiler-Reihenfolge der Scope-Liste)
source\uRdxSimpleFixes.pas        Quick-Fixes SCA066/SCA072/SCA074/SCA075/SCA084/SCA085/SCA087/SCA126/SCA139 (reine Textlogik)
source\uRdxStructFixes.pas        Quick-Fixes SCA007 (uses-Eintrag), SCA168 (case-else), SCA101/SCA099 (begin..end), reine Textlogik
source\uRdxLineFixes.pas          Quick-Fixes an einer Zeile SCA082/SCA071/SCA088/SCA123, reine Textlogik
source\uRdxRaiseFixes.pas         Quick-Fixes an Ausnahmen und leeren Rumpfen SCA020/SCA120/SCA122, reine Textlogik
source\uRdxDeclFixes.pas          Quick-Fixes an Deklarationen SCA117/SCA197/SCA149, reine Textlogik
source\uRdxFlowFixes.pas          Quick-Fixes an ganzen Anweisungen SCA098/SCA080/SCA047 (Charge H2), reine Textlogik
source\uRdxIntroPlan.pas          Code-Aktion "Lokale Variable einfuehren" (ohne Fund): Literal am Caret, Deklaration, Spalten, Ablehnungen (reine Textlogik)
source\uRdxIntroEdits.pas         dieselbe Aktion: Puffertext, Ziel am Caret, Ersetzungen des Writers, Ende des Sync-Blocks (reine Textlogik; IDE-Teil folgt)
source\uRdxSuppress.pas           Unterdrueck-Marker setzen und entfernen (reine Textlogik)
source\uRdxCodeMap.pas            Code-Sicht der Datei (Kommentare, Strings, mehrzeilige Strings) und Token-Leser
source\uRdxBufferMath.pas         Zeile/Spalte -> Byte im UTF-8-Puffer, Pruefung aller Ersetzungen, Spaltengrenze, Textwahl
source\uRdxEditor.pas             ToolsAPI: Puffer lesen, Bereich markieren, Bereiche ersetzen (ein Undo-Schritt), Projekt-Units
source\uRdxLog.pas                Protokoll %TEMP%\reDelphix.log + DebugView
data\unitscopes.txt               die Scope-Tabelle (erzeugt), als RCDATA eingelinkt (data\unitscopes.rc)
tests\reDelphix.Test.dpr/.dproj   DUnitX-Testprojekt mit 23 Testunits (siehe "Pruefen")
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
| uses: X -> Scope.X | Fund in einer uses-Klausel, auch der Programm-Klausel einer .dpr/.lpr | qualifiziert den Eintrag, dazu "uses: alle n Eintraege qualifizieren". Mehrdeutiges (Forms: VCL/FMX) nur bei erkennbarem Rahmenwerk, nie bei gleichnamiger Projekt-Unit und nie, wenn die Reihenfolge System/Vcl der Projekt-Scopes entscheiden wuerde. Gesperrt, wenn eine uses-Klausel Compiler-Direktiven traegt oder in einem `$IFDEF`-Zweig liegt, und in einer Datei mit FPC-Weiche oder FPC-Modus (FPC 3.2 kennt keine Unit-Scopes). Macht der Eintrag (bzw. "alle") eine sortierte Klausel unsortiert, steht er gesperrt da (sonst kaeme ein neuer SCA142-Fund). Ein Umbau, keine Hilfe zum Fund (`fakRefactor`): nur Kontextmenue und Dock-Grid, nie die Gluehbirne, und je Menue nur einmal, auch wenn mehrere Funde auf der Zeile stehen |
| FreeAndNil(X) verwenden | SCA085 | `X.Free;` + `X := nil;` -> `FreeAndNil(X);`. X muss in der Unit deklariert sein (keine Property, kein geerbtes Feld); gesperrt in einem `with`-Block. Fehlt `System.SysUtils`, kommt die uses-Einfuegung mit (unten) |
| Assigned() statt Vergleich mit nil verwenden | SCA126 | schreibt ALLE nil-Vergleiche der einen Anweisung um, die auf der Fundzeile beginnt (`X = nil` -> `not Assigned(X)`). Zwei solche Anweisungen auf der Zeile heissen mehrdeutig; ein Operand vom Typ String, Variant, Menge, Array oder Prozedur/Ereignis sperrt, ebenso ein blosser Bezeichner ohne beweisbaren Typ (geerbt aus einer anderen Unit) |
| (TObject) aus der Klassendeklaration entfernen | SCA075 | `class(TObject)` -> `class` an der Spalte aus der Meldung (nur Zeilen, ohne Parser) |
| FreeAndNil(X) verwenden | SCA139 | `X.Free` -> `FreeAndNil(X)`, auch hinter `then`/`else`/`do` (ersetzt wird nur der Ausdruck). Dieselbe Variablen-Pruefung wie SCA085; X muss ein blosser Bezeichner sein (kein `Self.X`, kein Pfad), `Free` ohne Klammern und genau einmal auf der Zeile. Gesperrt, wenn der Typ von X in der Unit ein `record`, `object` oder `interface` ist (`Free` ist dort eine eigene Methode), und bei `X.Destroy`. Fehlt `System.SysUtils`, kommt die uses-Einfuegung mit |
| Bedingung als Assert-Meldung verwenden | SCA074 | `Assert(c)` -> `Assert(c, 'c')` an der Spalte aus der Meldung; Apostrophe der Bedingung werden verdoppelt. Nur, wenn die Klammer auf derselben Zeile schliesst und kein Kommentar darin steht; nicht bei `Obj.Assert`, nicht, wenn die Unit selbst eine Routine `Assert` deklariert, nicht im `with`-Block. Ein Literal ueber 255 Zeichen (E2056) sperrt |
| Unit X aus uses entfernen (aendert Verhalten) | SCA007 | loescht den Eintrag der Meldung aus seiner uses-Klausel: vor dem letzten Eintrag samt Komma bis zum naechsten - steht er allein auf seiner Zeile, die ganze Zeile samt `//`-Kommentar -, den letzten ab dem Komma davor, den einzigen mit der ganzen Klausel (ganze Zeilen, wenn sie allein steht); ein `in`-Pfad geht mit. Vorher wird der Fund am aktuellen Puffer nachgeprueft (dieselben Spuren wie der Detektor: `Unit.`-Bezug, bekannte Bezeichner) - ein Fund aus einem aelteren Scan bietet nichts an. Gesperrt bei einem Kommentar im geloeschten Bereich (auch `{Form1}` hinter einer Formular-Unit), bei Direktiven in einer uses-Klausel und wenn im Bereich mehr steht als dieser Eintrag. Gekennzeichnet nach Entscheid E2: der Fund ist heuristisch (danach kompilieren - ein Typ, den der Detektor nicht kennt, etwa `TDataModule`, macht ihn falsch), und ein `initialization`-Abschnitt der Unit laeuft danach nicht mehr. Strg+Alt+F fuehrt gekennzeichnete Hilfen nicht aus |
| Leeren else-Zweig ergaenzen / else-Zweig mit Exception ergaenzen (aendert Verhalten) | SCA168 | zwei Eintraege (Nico 2026-10-10): ein leeres `else` vor das `end` des case (bedeutungsgleich) bzw. `else raise EProgrammerError.Create('Unhandled case');` (+ `System.SysUtils` bei Bedarf). Das `end` findet eine Token-Bilanz (begin/case/try/asm/record; `&End` und `@@End` zaehlen nicht); steht es allein auf der Zeile, kommt das `else` in eine eigene Zeile mit derselben Einrueckung, die raise-Zeile eingerueckt wie die Arme. Endet der letzte Arm nicht auf `;`, setzt die Hilfe es mit - sonst bande das `else` an ein `if` im Arm (`1: if B then DoA`). Gesperrt bei einer Direktive zwischen `case` und `end`, wenn schon ein `else` oder (FPC) `otherwise` hinter `;` steht, bei einem case ohne Zweige, bei zwei `case` auf der Zeile; die raise-Variante nicht in Dateien mit FPC-Weiche oder FPC-Modus (FPC kennt EProgrammerError nicht) |
| Ueberzaehliges Semikolon entfernen | SCA082 | `; ;` an der Spalte aus der Meldung -> `;` (das zweite war eine leere Anweisung). Nur, wenn dort beide `;` Code sind (kein String) |
| Schluesselwort an Spalte 1 setzen | SCA071 | loescht die Einrueckung vor dem Unit-Schluesselwort aus der Meldung. Nicht, wenn davor mehr als Leerraum steht (ein Kommentar ginge verloren), die Zeile in einem Kommentar bzw. mehrzeiligen String beginnt oder das `interface` zu einem Typ gehoert (`IFoo =` davor - das meldet der Detektor auch) |
| begin durch initialization ersetzen | SCA088 | das `begin` des Unit-Rumpfs (`begin .. end.`) wird `initialization`, Schreibweise wie das `begin`. Nur in einer Unit (in `program`/`library` ist es der Rumpf), nur wenn das `end` zu genau diesem `begin` (Token-Bilanz) vor dem Punkt steht, nicht bei einer Direktive auf der Zeile |
| Cast nach T vor Free entfernen | SCA123 | `TFoo(X).Free` -> `X.Free` - nur, wenn X ein blosser Bezeichner ist, ausserhalb eines `with`-Blocks, und schon als genau `TFoo` deklariert (`DeclaredTypeOf`): nur dann binden beide dasselbe `Free`. Ein anderer Typ kann `Free` verdecken (`TRefCountedObject.Free` in dwsUtils zaehlt nur herunter - aus `TRefCountedObject(Obj).Free` mit `Obj: TObject` wuerde eine Zerstoerung), ein Pointer-Operand braucht den Cast zum Uebersetzen (Gegen-Review 2026-10-10: von 58 sonst angebotenen Korpusfaellen uebersetzten 36 nicht). Das Katalog-Beispiel (`L: TObject`) bekommt deshalb keine Hilfe. Nur fuer Free, kein Interface-Cast |
| Leeren Rumpf als beabsichtigt kennzeichnen / ENotImplemented im leeren Rumpf ausloesen (aendert Verhalten) | SCA020 | zwei Eintraege wie bei SCA168: `// intentionally empty` in eine eigene Zeile zwischen `begin` und `end` (eine Stufe tiefer; stehen beide auf einer Zeile, `{ intentionally empty }` inline) - der Detektor wertet einen solchen Kommentar als Absicht, bedeutungsgleich - bzw. `raise ENotImplemented.Create('<Name>');` mit dem Namen aus dem Methodenkopf (+ `System.SysUtils` bei Bedarf; FPC kennt die Klasse ebenfalls). Gesperrt bei zwei Routinenkoepfen auf der Zeile (der Fund koennte jeden meinen), bei einer lokalen Routine zwischen Kopf und Rumpf, bei `asm`, wenn hinter dem `begin` noch Code steht, wenn der Rumpf nicht leer ist (Code unter einer inaktiven Direktive oder ein asm-Block - der Detektor sieht nur den aktiven Zweig; im Korpus 288 von 3.945 Funden) und bei einem Kommentar im Rumpf (er ist keine Absicht, sonst schwiege der Detektor - meist auskommentierter Code, den der Absichtskommentar fuer SCA070 verdeckte; 726 Funde); die raise-Variante nicht in constructor/destructor und nur mit dem Namen auf der Kopfzeile |
| Exception ausloesen (aendert Verhalten) | SCA120 | `raise ` vor `EFoo.Create(..)` (auch `CreateFmt`, Argumente ueber Zeilen) - nur als ganze Anweisung: davor ein Anweisungsanfang (im then-Zweig nur, wenn auch das `if` eine Anweisung beginnt - nicht im bedingten Ausdruck von Delphi 13), hinter der `)` ihr Ende (kein `X := EFoo.Create`, kein `EFoo.Create(..).Free`); nur die Create-Varianten des Detektors (`Create`, `CreateFmt`, `CreateRes`, `CreateHelp` ...). Gekennzeichnet nach E2: der Code dahinter laeuft im Fehlerfall nicht mehr - das ist der Fix |
| raise; verwenden (Original-Stack-Trace bleibt) | SCA122 | `raise E;` -> `raise;` - nur, wenn rueckwaerts der eigene Handler `on E: T do` kommt, bevor ein `except`/`finally` (im except eines inneren try wuerfe `raise;` die innere Exception), der Handler einer anderen Variablen, eine anonyme Methode oder ein `with` (der Name koennte ein Member sein); ganze Bloecke davor zaehlen nicht |
| Dokumentationsgeruest einfuegen | SCA117 | setzt ueber die Deklaration `/// <summary></summary>`, je Typparameter `/// <typeparam name="T"></typeparam>`, je Parameter (bei einer Property: je Index-Parameter) `/// <param name="X"></param>` und bei einer Funktion `/// <returns></returns>` - eingerueckt wie die Deklaration, die Platzhalter leer (ein `TODO` riefe SCA019). Die Namen kommen aus dem Kopf, auch ueber Zeilen; `const`/`var`/`out`/`constref` und Attribute zaehlen nicht mit. Bedeutungsgleich. Gesperrt, wenn die Zeile in einem Kommentar beginnt, der Name nicht mehr zur Meldung passt, darueber ein Kommentar ueber Zeilen endet (der Detektor haelt dessen Schlusszeile fuer Code), ueber Attributzeilen schon XMLDoc (`///`) steht (der Detektor bricht an der Attributzeile ab und meldet trotz Doku - delphimvcframework; sonst entstuende ein zweiter summary-Block; andere Kommentare dort sind meist Abschnittsueberschriften, dann kommt das Geruest) oder eine Direktive im Kopf bis zu dessen `;` steht (dahinter zaehlt nicht). Ohne Attribut-Doku kommt das Geruest unter die Attribute, direkt ueber die Deklaration (dort sucht der Detektor) |
| Neue GUID einfuegen | SCA197 | eine frisch erzeugte GUID `['{...}']` in eine eigene Zeile hinter den Interface-Kopf (eingerueckt wie die Member; steht der Rumpf auf derselben Zeile, inline). Bedeutungsgleich. Gesperrt bei generischen Interfaces (eine GUID gaelte fuer alle Auspraegungen), Vorwaertsdeklarationen, `[` hinter dem Kopf (GUID oder Attribut), COM-Merkmalen im Rumpf (`stdcall`/`safecall`/`winapi`/`dispid` - ein COM-Import braucht die echte IID), `{$INTERFACES CORBA}` bzw. `{$CALLING STDCALL}` in der Datei (auch als `(*$..*)`, nur innerhalb der Direktive), wenn hinter dem Kopf kein Rumpf beginnt (`procedure`/`function`/`property`/`end`) und bei einer Direktive vom Kopf bis zum ersten Member - beides fangt Koepfe, die unter `{$IFDEF}` doppelt stehen (die GUID kaeme sonst nur in einen Zweig) |
| "override;" bzw. "reintroduce;" an die Deklaration anfuegen | SCA149 | nach dem Rat der Meldung: bei gleicher Signatur `override` (gekennzeichnet nach E2 - der virtuelle Aufruf landet danach in dieser Methode; das ist der Fix), bei abweichender `reintroduce` (bedeutungsgleich, nur W1010 entfaellt). Nie beide als Eintraege: Strg+Alt+F liesse das gekennzeichnete `override` aus und deckte den Polymorphie-Fehler mit `reintroduce` still zu. Die Direktive kommt direkt hinter das `;` des Kopfs (vor vorhandene Direktiven). `override` nur, wenn im Rumpf der Elternklasse (der Detektor sucht sie in derselben Unit) eine Methode gleichen Namens dieselbe Form hat: `class`, Parameter-Modifier, Typen und Defaults (Namen duerfen abweichen), Rueckgabe, Aufrufkonvention - der Detektor vergleicht nur die Typen, `const A` gegen `A` oder `class procedure` gegen `procedure` uebersetzten mit `override` nicht. `reintroduce` nicht bei generischem Vorfahren (`class(TBase<Integer>)`: der Detektor haelt `T` und `Integer` fuer verschieden, `override` waere dort der Fix; Typ-Aliase wie `Integer`/`Longint` erkennt er ebenso nicht - Restrisiko). Gesperrt ausserdem, wenn `override`/`reintroduce` schon dasteht, bei `override` neben `virtual`/`dynamic`/`static`/`message`/`inline`, wenn der Name nicht mehr passt, bei einer Property, bei einer Direktive im Kopf und bei unbekanntem Meldungstext |
| Zweig in begin..end setzen | SCA101, SCA099 | setzt die Anweisung hinter `then`/`else`/`do` in `begin..end` (Entscheid E7, bedeutungsgleich). SCA101: das Schluesselwort an der Spalte aus der Meldung; SCA099: das `else` hinter dem einen `end else` der Fundzeile, das der Detektor meldet (`end else if`/`end else begin` zaehlen nicht mit). Die Anweisung endet mit `;` (das `end` bekommt dann eines) oder vor `else`/`end`/`until`/`except`/`finally` (sie bekommt ein `;`, das `end` keines). Hinter dem `else` eines `case` oder `except` steht eine Anweisungsliste - dann kommt alles bis vor dessen `end` in den Block, nicht nur die erste Anweisung. Wem ein `else` gehoert, entscheidet eine Rueckwaerts-Suche wie der Compiler (dangling else: das naechste `then` ohne eigenes `else`; Bloecke und `repeat..until` werden uebersprungen); ein `;` auf oberster Ebene schliesst ein if-else aus, entscheidend ist erst das `of` bzw. `except` davor. Form: endet die Zeile des Schluesselworts mit ihm und die letzte Zeile der Anweisung mit ihr, kommen `begin` und `end` in eigene Zeilen (eingerueckt wie die Zeile des `if`/`for`/`while`/`with`/`on` bzw. des `else`; Kommentarzeilen dazwischen kommen mit in den Block); steht die Anweisung ganz auf der Zeile des Schluesselworts, kommt sie eine Stufe tiefer in eine eigene Zeile (ein folgendes `else` in die naechste); sonst inline (`begin X; end`). Gesperrt bei einem bedingten Ausdruck (Delphi 13: `X := if A then B else C`, auch verschachtelt oder als `Write`-Breite hinter `:`), wenn hinter einem `;` vor dem `else` eine Deklaration steht (`var`, `procedure` ... - der Kopf einer anonymen Methode; wem das `else` gehoert, waere unklar), bei `record` vor dem `else`, wenn in der Anweisung eine Struktur, eine anonyme Methode oder eine Inline-Deklaration steht (`var`/`const` auch in der Liste eines case-else: `begin..end` engte ihren Gueltigkeitsbereich ein), bei einer Direktive in den Zeilen vom entscheidenden Token (beim `else` das `then` bzw. `of`/`except`, sonst das Schluesselwort) bis zum Ende der Anweisung (`{$` in einem `//`-Kommentar zaehlt nicht), bei schon vorhandenem `begin` und bei leerer Anweisung |
| Leere Klammern entfernen | SCA066 | `Foo()` -> `Foo` an der Spalte aus der Meldung, auch in Deklarationen (`procedure Foo();`). Nur, wo Delphi den Namen ohne Klammern genauso aufruft: als ganze Anweisung (`Obj.Foo();`), als ganze Bedingung von `if`/`while`/`until` oder als ganze rechte Seite einer Zuweisung an eine einfache Variable, deren Typ bekannt und nicht prozedural ist (sonst liest Delphi den Namen als Zeiger). Gesperrt als Argument oder Teil eines Ausdrucks (etwa bei einer Ueberladung mit `TFunc`), bei `Arr[0]()` und `F()()`, wenn der Name eine Variable (Prozedurvariable) ist oder wie ein Ereignis heisst (`OnIdle()`), in der eigenen Funktion, im `with`-Block und in Dateien mit FPC-Weiche oder FPC-Modus. Nachfolger des alten Strg+Alt+F (uQuickFix) |
| Ueberfluessigen Vergleich mit True/False entfernen | SCA072 | `X = True` / `X <> False` -> `X`, `X = False` / `X <> True` -> `not X`. Nur fuer einen blossen Bezeichner (kein Pfad, auch nicht `Self.X`), der in der Unit als `Boolean` deklariert ist (bei Variant und LongBool ist `= True` nicht dasselbe); links davon muss ein Ausdruck beginnen und rechts von True/False einer enden - `X = True and Y` heisst `X = (True and Y)`. Gesperrt im `with`-Block. Nachfolger von uQuickFix, der auch Pfade ohne Typpruefung umschrieb |
| Ueberfluessigen Vergleich mit nil entfernen | SCA084 | `Assigned(X) and (X <> nil)` bzw. `(X <> nil) and Assigned(X)` -> `Assigned(X)`, alles auf einer Zeile und der Vergleich geklammert. X muss als Klasse, Interface oder Zeiger bewiesen sein (`TObject`, `Pointer`, `IInterface` oder in der Unit so deklariert, auch ueber Alias) - bei einem Funktionstyp ruft `X <> nil` ihn auf, `Assigned(X)` nicht. Gesperrt bei `not` davor (es bindet nur an den ersten Teil), bei einer Aufruf- oder Cast-Klammer (`Boolean(X <> nil) and ...`), bei einer eigenen Routine `Assigned` und im `with`-Block. Nachfolger von uQuickFix |
| Bedingung direkt an X zuweisen | SCA098 | `if C then X := True else X := False` -> `X := C`, Gegenrichtung (`then False else True`) -> `X := not C`. Klammern nur um ein zusammengesetztes C (`not (A > B)`; `not Ready` und schon geklammertes `not (A and B)` ohne weitere), Zeilenumbrueche in C bleiben, Ziel und Zuweisung wie im then-Zweig (`Result:=`). Bedeutungsgleich. Gegenprobe wie der Detektor: Ziel und beide Werte wie in der Meldung, kein `;` vor dem `else`, hinter dem zweiten Wert endet die Anweisung. X muss als `Boolean` deklariert sein (DeclaredTypeOf; bei Variant bekaeme X den Wert der Bedingung statt True/False). In der Gegenrichtung auch C: der Form nach Boolean - ein Vergleich auf oberster Ebene oder `and`/`or`/`xor`/`not` ueber solchen Teilen, `True`/`False` und blossen Bezeichnern - und jeder dieser Bezeichner als `Boolean` deklariert; bei einem Variant waere `not` bitweise (`not 1` ist wieder wahr), ein Aufruf als C bleibt in der Gegenrichtung deshalb aus. Gesperrt bei einem Kommentar oder einer Direktive in der Anweisung, `begin..end`-Zweigen, einem Ausdruck hinter dem zweiten Wert (`X := False or Y`), einem bedingten Ausdruck (Delphi 13), im `with`-Block und bei zwei solchen Anweisungen auf der Zeile (die Meldung nennt keine Spalte). Folgefund: stand das if hinter `end else`, meldet SCA099 danach `end else X := C` (Korpus 2 von 220) |
| Ueberfluessiges Exit/Continue entfernen | SCA080 | loescht `Exit;` bzw. `Continue;` - allein auf der Zeile die ganze Zeile; hinter dem `else` eines `if` faellt `else Exit` weg (`if C then Foo else Exit;` -> `if C then Foo;`). Bedeutungsgleich. Gegenprobe wie uRedundantJump: dahinter nur die end-Kette bis zum Routinenende, `end.` oder `until`; Exit nicht im Rumpf einer Schleife. Gesperrt als einzige Anweisung hinter `then`/`do` (`if C then Exit;` - es bliebe `if C then` stehen, und C kann Seiteneffekte haben), eines case-Zweigs, des `else` von case/except und eines Blocks (`begin Exit; end`, `except Exit; end` - es bliebe ein leerer Block), bei mehreren Sprunganweisungen auf der Zeile, bei einem Kommentar auf der Zeile (er erklaert den Sprung) und bei einer eigenen Routine `Exit`/`Continue` in der Unit (`Exit;` riefe sie auf; eine geerbte Methode dieses Namens aus einer anderen Unit sieht die Hilfe nicht - Restrisiko). Im `finally`-Teil gesperrt, obwohl dort kein Sprung uebersetzt (Delphi 12 E2126, FPC 3.2.2 Fehler 06040 - Mikroprobe 2026-10-12): Code unter einer inaktiven Direktive sieht kein Compiler. Folgefunde: ohne das Exit melden SCA121 bzw. SCA132 vereinzelt, was das Exit vorher verdeckte (Korpus je 1) |
| Selbstzuweisung von X entfernen | SCA047 | loescht `X := X;` - allein auf der Zeile die ganze Zeile -, auch Pfade (`Pt.Y := Pt.Y;`, `R^.F := R^.F;`). Bedeutungsgleich; war ein anderer Wert gemeint (Tippfehler, Katalog: `FCount := ACount`), fehlt er weiterhin - der Hinweis sagt es. Gegenprobe: links und rechts derselbe Pfad wie in der Meldung (ohne Leerraum, Gross/klein egal), dahinter endet die Anweisung. Die Wurzel muss eine Variable sein (DeclaredTypeOf oder Inline-Variable), kein Pfadteil eine Property der Unit (ihr Setter liefe sonst nicht mehr). Gesperrt fuer `Result := Result` (stillt vielleicht W1035 bzw. den FPC-Hinweis "Function result does not seem to be set" - der Katalog empfiehlt dort das Unterdruecken), wenn X auch eine Routine der Unit ist (rechts koennte ein rekursiver Aufruf stehen), bei einem `class operator Assign` in der Unit (verwaltete Records: die Zuweisung fuehrt Code aus; ein Record aus einer anderen Unit mit Assign-Operator ist nicht erkennbar - Restrisiko), bei einem Kommentar auf der Zeile (`Pt.Y := Pt.Y; // + Scroll` traegt die Absicht), als einzige Anweisung hinter `then`/`else`/`do`, eines case-Zweigs oder eines Blocks, ueber mehrere Zeilen und im `with`-Block |
| Leeren Sichtbarkeitsabschnitt entfernen | SCA087 | loescht die Zeile des leeren Abschnitts (`public`, `strict private` ...). Nur, wenn sie genau diesen Abschnitt traegt, ohne Kommentar; gesperrt bei `strict` allein auf der Zeile (es gehoert zur naechsten) und bei einer Compiler-Direktive bis zum naechsten Abschnitt (der Abschnitt waere vielleicht nur in einem Zweig leer) |
| Hier / In dieser Datei unterdruecken | jeder Fund in Pascal-Quelltext | setzt `// noinspection <Art>` ueber die Fundzeile bzw. `// noinspection-file <Art>` hinter die Kopfanweisung (`fakSuppress`); ein vorhandener Marker bekommt die Art dazu, ausser er lautet `All`/`*` (dann eine eigene Zeile). Nicht angeboten, wenn die Fundzeile in einem Block-Kommentar oder mehrzeiligen String liegt. Einen wirkungslosen Marker (SCA165) entfernt "Wirkungslosen Unterdrueck-Marker entfernen" stattdessen - nur, wenn er genau EINE Art nennt; ein Mehrarten- oder `All`-Marker steht gesperrt mit Grund da, denn SCA165 kommt auch, wenn nur die Arten des aktiven Scan-Profils nichts unterdrueckt haben |

**SCA150 BoolAlwaysTrue** bekommt bewusst keine Hilfe (in Charge H2
optional): die Meldung nennt weder Spalte noch Ausdruck; im Realwelt-Korpus
gibt es keinen Fund, im Lazarus-Korpus einen - der Korpus-Harness, das Mass
jeder Charge, kann sie nicht messen. Die bedeutungsgleiche Variante
(`if Length(s) >= 0 then A else B` -> `A`, `if Length(s) < 0 then A;` -> weg)
loescht einen ganzen Zweig und braucht dafuer den Baustein Blockpaarung
(Zweigende, haengendes `else`), den H2 nicht bringt; ausserdem muss `Length`
die RTL-Funktion sein - eine Methode `Length` aus einer anderen Unit ist im
Text nicht auszuschliessen (dasselbe Restrisiko wie bei SCA080/`Exit`, hier
aber ohne Korpus, es zu wiegen). Die gekennzeichnete Variante (`>= 0` ->
`> 0`) raet die Absicht ohne einen einzigen Beleg.

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
python reDelphix\tools\gen_unitscopes.py            # Studio 23.0 (Delphi 12)
python reDelphix\tools\gen_unitscopes.py "C:\Program Files (x86)\Embarcadero\Studio\37.0"
```

Fehlt `source` oder `lib\win32\release` der Installation oder findet das
Skript keine Unit, bricht es mit Exit 2 ab und laesst die Tabelle stehen;
sonst ersetzt es sie in einem Zug. Danach `reDelphix.d12` bereinigen und
neu erzeugen (siehe "Bauen und installieren"). Eine `unitscopes.txt` neben
der BPL hat Vorrang vor der eingelinkten Ressource.

## Code-Aktionen in der IDE ausprobieren

Profil **`code-aktionen`** in `data\profile-code-aktionen.json`: nur die
Regeln, zu denen reDelphix eine Hilfe anbietet, plus `FileReadError`
(Lesefehler bleiben sichtbar). Einspielen: Analyser-Fenster ->
Profile -> **Import...** -> die Datei waehlen -> bestaetigen; danach im
Analyser das Profil `code-aktionen` waehlen und die Datei bzw. das
Projekt scannen. Gluehbirne oder Editor-Kontextmenue auf der Fundzeile:

| Regel | Fund | Erwartete Hilfe |
|---|---|---|
| SCA044 ConcatToFormat | `s := 'a' + x + 'b';` | Format() aus Verkettung bilden (fehlt System.SysUtils, kommt es in uses) |
| SCA003 SQLInjection | `Q.SQL.Text := 'SELECT ... ' + Id;` | Parametrisierte Vorlage (in die Zwischenablage, schreibt nichts) |
| SCA075 ExplicitTObjectInheritance | `TFoo = class(TObject)` | (TObject) entfernen |
| SCA085 FreeAndNilHint | `X.Free; X := nil;` | FreeAndNil(X) |
| SCA126 NilComparison | `if X <> nil then` | Assigned(X) |
| SCA074 AssertMessage | `Assert(X > 0);` | Bedingung als Assert-Meldung |
| SCA087 EmptyVisibilitySection | `public` direkt vor `private` | leeren Abschnitt entfernen |
| SCA139 FreeWithoutNil | `FList.Free;` (Feld, ohne `FList := nil`) | FreeAndNil(FList) |
| SCA066 EmptyArgumentList | `DoStuff();` | leere Klammern entfernen |
| SCA007 UnusedUses | ungenutzte Unit in uses | Unit aus uses entfernen (gekennzeichnet) - daneben "uses qualifizieren" im Kontextmenue |
| SCA168 DefaultCaseInCaseStatement | `case` ohne `else` | leerer else-Zweig bzw. else mit Exception (gekennzeichnet) |
| SCA101 BeginEndRequired | `if Active then DoStuff;` | Zweig in begin..end setzen |
| SCA099 IfElseBegin | `end else DoC;` | Zweig in begin..end setzen |
| SCA082 SuperfluousSemicolon | `DoStuff;;` | ueberzaehliges Semikolon entfernen |
| SCA071 UnitLevelKeywordIndent | `  implementation` | Schluesselwort an Spalte 1 setzen |
| SCA088 LegacyInitializationSection | `begin ... end.` am Ende einer Unit | begin durch initialization ersetzen |
| SCA123 CastAndFree | `TStringList(L).Free;` mit `L: TStringList` | Cast vor Free entfernen |
| SCA020 EmptyMethod | `procedure P; begin end;` | Rumpf als beabsichtigt kennzeichnen bzw. ENotImplemented ausloesen (gekennzeichnet) |
| SCA120 MissingRaise | `EFoo.Create('x');` | Exception ausloesen (gekennzeichnet) |
| SCA122 ReRaiseException | `on E: EFoo do ... raise E;` | `raise;` verwenden |
| SCA117 PublicMemberWithoutDoc | `procedure Run(A: Integer);` im public-Teil | Dokumentationsgeruest einfuegen |
| SCA197 InterfaceWithoutGuid | `IFoo = interface` ohne GUID | Neue GUID einfuegen |
| SCA149 MissingOverride | `procedure DoWork;` verdeckt `TBase.DoWork; virtual;` | `override;` anfuegen (gekennzeichnet) bzw. `reintroduce;` |
| SCA072 RedundantBoolean | `if Active = True then` (Active: Boolean) | Vergleich mit True/False entfernen |
| SCA084 AssignedAndAssignedNil | `if Assigned(Obj) and (Obj <> nil) then` | Vergleich mit nil entfernen |
| SCA098 RedundantConditional | `if Active then Result := True else Result := False;` (Result: Boolean) | Bedingung direkt an Result zuweisen |
| SCA080 RedundantJump | `Exit;` als letzte Anweisung der Routine | Ueberfluessiges Exit entfernen |
| SCA047 SelfAssignment | `FCount := FCount;` (Feld der Unit) | Selbstzuweisung von FCount entfernen |
| SCA165 UnusedSuppression | wirkungsloser `// noinspection`-Marker | Marker entfernen - nur bei genau einer Art; Mehrarten- und `All`-Marker stehen gesperrt da (unter diesem Teilprofil wirken sie vielleicht nur scheinbar nicht) |
| SCA142 UnsortedUses, SCA007 UnusedUses | Fund auf einer uses-Zeile | uses: Eintraege qualifizieren (Winapi.Windows, System.SysUtils ...) - nur im Kontextmenue, nicht in der Gluehbirne: es behebt den Fund nicht |
| jede Regel ausser SCA165 | beliebig | Hier / in dieser Datei unterdruecken; Stelle zeigen (Kontextmenue) |

SCA007 laeuft nur mit eingeschaltetem uses-Check (Optionen bzw.
`[Detectors] UsesCheck=1`); SCA142 reicht fuer die uses-Hilfe. Den
Ablauf je Aktion protokolliert `%TEMP%\reDelphix.log` (`Provide ...`,
`neu geparst` / `wiederverwendet`).

## Lokale Variable einfuehren (Refactoring ohne Fund, in Arbeit)

Code-Aktion ohne Fund - seit Entscheid E26 (Nico 2026-10-13) heisst sie
**"Lokale Konstante einfuehren"**: aus dem Zahl-Literal unter dem Caret wird
`const MagicNr01 = <Literal>;` direkt ueber der Anweisung, alle gleichen
Literale der Zeile werden durch den Namen ersetzt, der Name steht danach
im Sync Edit zum Umbenennen (Variante C1h; ein Zweig ohne `begin` bekommt
`begin..end`). Eine Inline-Konstante statt der Variablen, weil keine
Typregel das Literal trifft (Kompilierprobe des Labors, Win32 D12:
`var MagicNr01 := 1` rechnete `C - MagicNr01` mit `C: Cardinal` als -1
statt 4294967295, waehlte Integer- statt ShortInt-/Byte-Ueberladungen);
die Konstante behaelt Faltung, Ueberladungswahl und die vorzeichenlose
Rechnung des Literals.

* **Stand (Bereich C, 2026-10-14, UNGEBAUT):** nur Logik und Tests.
  `uRdxIntroPlan` und `uRdxIntroEdits` sind 1:1 aus dem Labor
  `VarNameProject` uebernommen (Entscheid E24: erst der im Labor
  gemessene Stand), nur umbenannt (`TVnp*` -> `TRdxIntro*`,
  `ApplyByteEdits` -> `ApplyIntroEdits`, weil `uRdxBufferMath` schon eine
  `ApplyByteEdits` hat). Stand 2026-10-14 nach dem Review F/B vom
  2026-10-13: Inline-const (E26), mehrzeilige Strings mit mehr als drei
  Quotes, Kommentargrenzen eines `begin..end`, Kopf-Fortsetzungen
  (`message`/`dispid`/`external` auf der Folgezeile), zweite `var`/`const`
  hinter einer Anweisung, asm-Block, initialization-Abschnitt, Direktive
  zwischen Zeile darueber und Anweisung fuer jeden Plan, die Zeile
  darueber ab ihrem Kommentar-Zustand, `*)` in Spalte 1, else-Arm eines
  Bedingungsausdrucks (Delphi 13), FPC-Weiche (FPC 3.2 kennt keine
  Inline-Konstante), Zeilenende je Zeile (`RowEol`, wie
  `uRdxBufferMath.BufferEol`), Vorbedingung `Plan.Ok` von `IntroduceEdits`,
  Namen jenseits von `MagicNr99`. Die Tests `uTestRdxIntro*` (jetzt fuenf
  Units, 72 Tests: Plan 15, Refuse 9, Guards 16, Edits 20, Context 12)
  stehen in reDelphix.Test und laufen im FPC-Pruefstand (Kommando unter
  "Pruefen").
  Das Package bietet die Aktion noch nicht an.
* **Die IDE-Aktion folgt** nach dem Prototyp fuer Enter und Esc im Labor
  (E25: Esc zerstoert im Sync Edit der IDE Text, auch ohne unseren Code -
  UI-Test 2026-10-11).
* **Variante D1** (Live Template) bleibt im Labor, ebenso ihre Tests
  (`uTestVnpTemplate`).
* **Grenzen:** siehe `VarNameProject\README.md`, Abschnitt "Grenzen" (ein
  Zeilen-Leser ohne Parser - was er nicht sicher abgrenzt, lehnt er ab).
  Eigener Zeilenleser und Schreibweg bleiben bis zur Zusammenlegung mit
  `uRdxCodeMap`/`uRdxBufferMath` stehen (Bericht B, Befund 2: drei
  Kommentar-/String-Leser; ein einzelnes CR ist in `uRdxBufferMath` ein
  Zeilenende, in `uRdxIntroEdits` nicht - im Kopf von `uRdxIntroEdits`
  festgehalten).

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
* `uTestRdxSuppress` - Unterdrueck-Marker setzen und entfernen, auch in
  Block-Kommentar, mehrzeiligem String, Lizenzkopf und mit `All`.
* `uTestRdxCodeMap` - die Code-Sicht gegen `TDetectorUtils.ScanCodeLine`
  des Cores (Drift-Waechter), der Zustand am Zeilenanfang und die
  geteilten Laeufe der Planer (Charge R8): Klammerabgleich (`MatchClose`,
  `AfterClose`), "genau ein Token auf der Zeile" (`OneTokenOnLine`),
  end-Bilanz (`BlockEnd`), `DirectiveInLines`.
* `uTestRdxQualifyUses` - die Planung von "uses: X -> Scope.X"
  (`TRdxRecipeRunner.QualifyUses`): Eintraege der Zeile, alle,
  Sortierung, FPC-Weiche, Direktiven, eigene Unit.
* `uTestRdxFixTable` - die Tabelle der einfachen Hilfen (`uRdxFixTable`,
  Charge R8): jede Zeile mit Planer, Hinweis (fest oder vom Planer) und
  Menuetext, zweiter Eintrag genau mit zweitem Menuetext, Arten eindeutig
  und gleich `Handles`; Menuetexte mit Name, Variante und Kennzeichnung;
  Einstieg ohne Fund und ohne Zeile.
* `uTestRdxSimpleFixes` / `uTestRdxNilFix` / `uTestRdxExprFixes` /
  `uTestRdxStructFixes` / `uTestRdxBlockFixes` / `uTestRdxLineFixes` /
  `uTestRdxRaiseFixes` / `uTestRdxDeclFixes` / `uTestRdxFlowFixes` - die
  Quick-Fixes SCA074/SCA075/SCA085/SCA087/SCA139, SCA126,
  SCA066/SCA072/SCA084, SCA007/SCA168, SCA101/SCA099,
  SCA082/SCA071/SCA088/SCA123, SCA020/SCA120/SCA122, SCA117/SCA197/SCA149
  bzw. SCA098/SCA080/SCA047 auf Text, ohne Parser.
* `uTestRdxSimpleFixesDetector` - dieselben Hilfen gegen den echten
  Detektor: nach der Hilfe meldet er nichts mehr; die Katalog-Beispiele
  `bad` werden genau `good` (SCA074 und SCA139: das `good` traegt eine
  Begruendung in Worten bzw. laesst Zeilen weg - dort wird die Ersetzung
  verglichen; SCA047: das `good` zeigt den gemeinten Wert, die Hilfe
  loescht die Zuweisung). Fixture 9 prueft dazu die Sperren des Laeufers
  fuer SCA098/SCA047 (Boolean bewiesen, Variable, with-Block).
* `uTestRdxIntroPlan` / `uTestRdxIntroRefuse` / `uTestRdxIntroGuards` /
  `uTestRdxIntroEdits` - "Lokale Variable einfuehren" (Abschnitt oben): das
  Literal am Caret, Deklaration und Spalten, Zweig ohne `begin`, alle
  Ablehnungen und Schutzregeln, Ende des Sync-Blocks und die Ersetzungen
  des Writers Ende zu Ende auf UTF-8-Pufferbytes (CRLF, LF, BOM,
  Mehrbyte-Zeichen), Kontext ueber Zeilen (mehrzeilige Strings, asm,
  initialization, FPC-Weiche, Direktiven, Kommentargrenzen) - 79 Tests, reine
  Textlogik.

Ohne Delphi (FPC 3.2.2):

```
bash reDelphix/tools/fpc-pruefstand/build.sh uTestRdxRecipes uTestRdxBufferMath uTestRdxSuppress uTestRdxSimpleFixes uTestRdxNilFix uTestRdxCodeMap uTestRdxExprFixes uTestRdxStructFixes uTestRdxBlockFixes uTestRdxLineFixes uTestRdxRaiseFixes uTestRdxDeclFixes uTestRdxFlowFixes uTestRdxIntroPlan uTestRdxIntroRefuse uTestRdxIntroGuards uTestRdxIntroEdits uTestRdxIntroContext
```

Erwartet (Stand 2026-10-14, Charge R8): `PASSED 282  FAILED 0` - 18 Testunits,
davon 72 Tests fuer "Lokale Variable einfuehren", 12 fuer die Quick-Fixes der
Charge H2 und 7 der Charge R8 (6 fuer die geteilten Laeufe in
`uTestRdxCodeMap`, 1 fuer den Fremdtyp-Beweis von SCA126 in `uTestRdxNilFix`).

Der Pruefstand uebersetzt die Core-Units des Quellstellen-Dienstes
(`uRefactor*`, `uSourcePlaces`, `uFindingActions`, `ScanCodeLine` aus
`uDetectorUtils`) mit Stubs fuer Parser und Resolver sowie die Textlogik
des Moduls (`uRdxRecipes`, `uRdxScopeTable`, `uRdxBufferMath`,
`uRdxSuppress`, `uRdxSimpleFixes`, `uRdxStructFixes`, `uRdxLineFixes`, `uRdxRaiseFixes`, `uRdxDeclFixes`, `uRdxFlowFixes`, `uRdxCodeMap`,
`uRdxIntroPlan`, `uRdxIntroEdits`). Testunits kommen aus `reDelphix\tests`,
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
  und `FreeAndNil(X)` sowie die Assert-Meldung werden dort nicht angeboten.

# Quick-Fixes von reDelphix

> **Erzeugte Datei – nicht von Hand bearbeiten.** Quelle: [`data/quickfixes-doc.json`](data/quickfixes-doc.json) (Titel, Beschreibung, Sperren, Beispiele) und der Quelltext: welche Hilfen es gibt, ihre Menütexte und ob sie das Verhalten ändern, stehen in [`source/uRdxFixTable.pas`](source/uRdxFixTable.pas) (`FIX_ROWS`, `FIX_CAPTIONS`, `FIX_ALT_CAPTIONS`) und [`source/uRdxProvider.pas`](source/uRdxProvider.pas) (Rezepte), die Übersetzungen in [`i18n/de.po`](../i18n/de.po) und [`i18n/fr.po`](../i18n/fr.po), Regel-IDs und Namen in [`rules/sca-rules.json`](../rules/sca-rules.json).
> Erzeugen (Repo-Wurzel): `python tools/gen-quickfix-doc.py`, prüfen: `python tools/gen-quickfix-doc.py --check` (auch in der CI, `.github/workflows/quickfix-doc.yml`).

reDelphix hängt an Funde des SCA-Plugins Code-Aktionen. Hier steht jede: 60 Quick-Fixes aus der Tabelle der einfachen Hilfen (4 davon mit zweitem Eintrag) und 6 weitere Code-Aktionen des Anbieters. Wie die Hilfen im Einzelnen prüfen und schreiben, beschreibt [README.md](README.md), Abschnitt „Was die Aktionen tun“.

## Lesehilfe

- **Quick-Fix** behebt den Fund: Glühbirne im Editor (nur verfügbare Hilfen), Kontextmenü des Funds im Editor und im Dock-Grid (dort auch ausgegraut, der Grund steht im Hinweis). **Strg+Alt+F** im Dock-Grid führt die erste verfügbare Hilfe aus, die nicht gekennzeichnet ist.
- **Ändert Verhalten** (Entscheid E2): der Menütext endet auf `(changes behavior)` (de `(ändert Verhalten)`, fr `(modifie le comportement)`). Eine solche Hilfe läuft nur über Menü oder Glühbirne, nie über Strg+Alt+F.
- **Navigation** führt nur hin: Kontextmenü und Dock-Grid, nicht die Glühbirne.
- **Refactoring** formt um, behebt den Fund aber nicht: nur Kontextmenü und Dock-Grid, je Menü einmal.
- **Unterdrücken** setzt einen Marker: Kontextmenü, Dock-Grid und **Strg+Alt+S**; in der Glühbirne nur, wenn es zum Fund auch eine Hilfe gibt.
- **Menütext:** en ist die msgid aus dem Quelltext, de und fr kommen aus den .po-Dateien. Fehlt eine Übersetzung, steht hier **(fehlt)** – die IDE zeigt dann den englischen Text. `%s` und `%d` setzt reDelphix beim Menüaufbau ein; was sie bedeuten, steht je Abschnitt.
- **Nicht angeboten:** die wichtigsten Sperren. Eine gesperrte Hilfe steht meist ausgegraut im Kontextmenü, der Hinweis nennt den Grund.
- **Beispiel:** aus den Tests (`reDelphix/tests/uTestRdx*.pas`), gekürzt auf die betroffenen Zeilen.

## Übersicht

| Regel | Menütext (de) | Art | Ändert Verhalten | Abschnitt |
|---|---|---|---|---|
| SCA001 MemoryLeak | `%s in einem try/finally-Block freigeben` | Quick-Fix | ja | [SCA001](#sca001) |
| SCA002 EmptyExcept | `raise; in den leeren except-Block einfügen` | Quick-Fix | ja | [SCA002](#sca002) |
| SCA007 UnusedUses | `Unit %s aus uses entfernen` | Quick-Fix | ja | [SCA007](#sca007) |
| SCA009 MissingFinally | `%s in einem try/finally-Block freigeben` | Quick-Fix | ja | [SCA009](#sca009) |
| SCA014 MagicNumber | `Lokale Konstante für %s einführen` | Quick-Fix | nein | [SCA014](#sca014) |
| SCA020 EmptyMethod | `Leeren Rumpf als beabsichtigt kennzeichnen` / `ENotImplemented im leeren Rumpf auslösen` | Quick-Fix | nein / ja | [SCA020](#sca020) |
| SCA046 ReversedForRange | `"to" durch "downto" ersetzen` / `Schleifengrenzen vertauschen` | Quick-Fix | ja / ja | [SCA046](#sca046) |
| SCA047 SelfAssignment | `Selbstzuweisung von %s entfernen` | Quick-Fix | nein | [SCA047](#sca047) |
| SCA053 UnusedLocalVar | `Ungenutzte Variable %s entfernen` | Quick-Fix | nein | [SCA053](#sca053) |
| SCA060 GotoStatement | `"goto" durch Exit ersetzen` | Quick-Fix | nein | [SCA060](#sca060) |
| SCA061 TabulationCharacter | `Tabulatoren dieser Zeile durch Leerzeichen ersetzen` | Quick-Fix | nein | [SCA061](#sca061) |
| SCA063 TrailingWhitespace | `Leerraum am Zeilenende entfernen` | Quick-Fix | nein | [SCA063](#sca063) |
| SCA064 LowercaseKeyword | `%s klein schreiben` | Quick-Fix | nein | [SCA064](#sca064) |
| SCA065 NoSonarMarker | `NOSONAR durch einen Marker "noinspection All" ersetzen` | Quick-Fix | ja | [SCA065](#sca065) |
| SCA066 EmptyArgumentList | `Leere Klammern entfernen` | Quick-Fix | nein | [SCA066](#sca066) |
| SCA068 TrailingCommaArgList | `Überzähliges Komma entfernen` | Quick-Fix | nein | [SCA068](#sca068) |
| SCA070 CommentedOutCode | `Auskommentierten Code löschen` | Quick-Fix | nein | [SCA070](#sca070) |
| SCA071 UnitLevelKeywordIndent | `Schlüsselwort an Spalte 1 setzen` | Quick-Fix | nein | [SCA071](#sca071) |
| SCA072 RedundantBoolean | `Überflüssigen Vergleich mit True/False entfernen` | Quick-Fix | nein | [SCA072](#sca072) |
| SCA074 AssertMessage | `Bedingung als Assert-Meldung verwenden` | Quick-Fix | nein | [SCA074](#sca074) |
| SCA075 ExplicitTObjectInheritance | `(TObject) aus der Klassendeklaration entfernen` | Quick-Fix | nein | [SCA075](#sca075) |
| SCA076 GroupedDeclaration | `Gruppierte Deklaration aufteilen` | Quick-Fix | nein | [SCA076](#sca076) |
| SCA077 EmptyBlock | `Leeres "with ... do begin end" durch den Aufruf ersetzen` | Quick-Fix | nein | [SCA077](#sca077) |
| SCA080 RedundantJump | `Überflüssiges %s entfernen` | Quick-Fix | nein | [SCA080](#sca080) |
| SCA082 SuperfluousSemicolon | `Überzähliges Semikolon entfernen` | Quick-Fix | nein | [SCA082](#sca082) |
| SCA083 EmptyFinallyBlock | `Leeres try/finally entfernen` | Quick-Fix | nein | [SCA083](#sca083) |
| SCA084 AssignedAndAssignedNil | `Überflüssigen Vergleich mit nil entfernen` | Quick-Fix | nein | [SCA084](#sca084) |
| SCA085 FreeAndNilHint | `FreeAndNil(%s) verwenden` | Quick-Fix | nein | [SCA085](#sca085) |
| SCA087 EmptyVisibilitySection | `Leeren Sichtbarkeitsabschnitt entfernen` | Quick-Fix | nein | [SCA087](#sca087) |
| SCA088 LegacyInitializationSection | `begin durch initialization ersetzen` | Quick-Fix | nein | [SCA088](#sca088) |
| SCA093 TwiceInheritedCalls | `Zweiten doppelten inherited-Aufruf entfernen` / `Ersten doppelten inherited-Aufruf entfernen` | Quick-Fix | ja / ja | [SCA093](#sca093) |
| SCA094 RedundantParentheses | `Das überflüssige innere Klammerpaar entfernen` | Quick-Fix | nein | [SCA094](#sca094) |
| SCA096 ConstructorWithoutInherited | `%s als Erstes im Konstruktor aufrufen` | Quick-Fix | je nach Fund | [SCA096](#sca096) |
| SCA097 DestructorWithoutInherited | `inherited als Letztes im Destruktor aufrufen` | Quick-Fix | je nach Fund | [SCA097](#sca097) |
| SCA098 RedundantConditional | `Bedingung direkt an %s zuweisen` | Quick-Fix | nein | [SCA098](#sca098) |
| SCA099 IfElseBegin | `Zweig in begin..end setzen` | Quick-Fix | nein | [SCA099](#sca099) |
| SCA101 BeginEndRequired | `Zweig in begin..end setzen` | Quick-Fix | nein | [SCA101](#sca101) |
| SCA109 LockWithoutTryFinally | `Sperre %s in einem try/finally-Block freigeben` | Quick-Fix | ja | [SCA109](#sca109) |
| SCA115 HttpInsteadOfHttps | `https:// statt http:// verwenden` | Quick-Fix | ja | [SCA115](#sca115) |
| SCA117 PublicMemberWithoutDoc | `Dokumentationsgerüst einfügen` | Quick-Fix | nein | [SCA117](#sca117) |
| SCA120 MissingRaise | `Exception auslösen` | Quick-Fix | ja | [SCA120](#sca120) |
| SCA121 RoutineResultUnassigned | `Result mit %s initialisieren` | Quick-Fix | ja | [SCA121](#sca121) |
| SCA122 ReRaiseException | `raise; verwenden (Original-Stack-Trace bleibt)` | Quick-Fix | nein | [SCA122](#sca122) |
| SCA123 CastAndFree | `Cast nach %s vor Free entfernen` | Quick-Fix | nein | [SCA123](#sca123) |
| SCA126 NilComparison | `Assigned() statt Vergleich mit nil verwenden` | Quick-Fix | nein | [SCA126](#sca126) |
| SCA139 FreeWithoutNil | `FreeAndNil(%s) verwenden` | Quick-Fix | nein | [SCA139](#sca139) |
| SCA147 UnusedPrivateMethod | `Ungenutzte private Methode %s löschen` | Quick-Fix | nein | [SCA147](#sca147) |
| SCA149 MissingOverride | `"%s;" an die Deklaration anfügen` | Quick-Fix | je nach Fund | [SCA149](#sca149) |
| SCA153 UnpairedLock | `Sperre %s in einem try/finally-Block freigeben` | Quick-Fix | ja | [SCA153](#sca153) |
| SCA156 GetMemWithoutFreeMem | `Puffer %s in einem try/finally-Block freigeben` | Quick-Fix | ja | [SCA156](#sca156) |
| SCA159 EmptyOnHandler | `Dem leeren Ausnahme-Handler "raise;" hinzufügen` | Quick-Fix | ja | [SCA159](#sca159) |
| SCA161 PointerSubtraction | `Die 32-Bit-Casts durch NativeInt/NativeUInt ersetzen` | Quick-Fix | ja | [SCA161](#sca161) |
| SCA164 UnusedRoutine | `Ungenutzte Routine %s löschen` | Quick-Fix | nein | [SCA164](#sca164) |
| SCA168 DefaultCaseInCaseStatement | `Leeren else-Zweig ergänzen` / `else-Zweig mit Exception ergänzen` | Quick-Fix | nein / ja | [SCA168](#sca168) |
| SCA179 AttributeIgnoreWithoutReason | `Grund zu [Ignore] hinzufügen` | Quick-Fix | nein | [SCA179](#sca179) |
| SCA180 AttributeDuplicate | `Doppeltes Attribut entfernen` | Quick-Fix | nein | [SCA180](#sca180) |
| SCA181 AttributeCategoryWithoutString | `Dem Attribut einen Kategorienamen geben` | Quick-Fix | nein | [SCA181](#sca181) |
| SCA183 AttributeMisalignment | `Leerzeile nach dem Attribut entfernen` | Quick-Fix | nein | [SCA183](#sca183) |
| SCA196 ManagedResultUninit | `Result zuerst initialisieren: %s` | Quick-Fix | ja | [SCA196](#sca196) |
| SCA197 InterfaceWithoutGuid | `Neue GUID einfügen` | Quick-Fix | nein | [SCA197](#sca197) |
| jede Regel mit Anker im Regelkatalog (Feld `anchor`), wenn sich die Anweisung des Funds beschreiben lässt | `Stelle zeigen` | Navigation | nein | [Details](#rezept-showspan) |
| SCA044 ConcatToFormat | `Format() aus Verkettung bilden` | Quick-Fix | nein | [Details](#rezept-formatcall) |
| SCA003 SQLInjection | `Parametrisierte Vorlage in die Zwischenablage` | Quick-Fix | nein | [Details](#rezept-sqltemplate) |
| jeder Fund auf einer Zeile einer uses-Klausel (auch der Programm-Klausel einer .dpr/.lpr), etwa SCA142 UnsortedUses oder SCA007 UnusedUses | `uses: %s -> %s` *(fester Text)* / `uses: alle %d Einträge qualifizieren` | Refactoring | nein | [Details](#rezept-usesactions) |
| SCA165 UnusedSuppression | `Wirkungslosen Unterdrück-Marker entfernen` | Quick-Fix | nein | [Details](#rezept-removemarker) |
| alle außer SCA165 | `Hier unterdrücken (// noinspection %s)` / `In dieser Datei unterdrücken (// noinspection-file %s)` | Unterdrücken | nein | [Details](#rezept-suppress) |

## Quick-Fixes je Regel

<a id="sca001"></a>

### SCA001 – Freigabe in try/finally setzen (Variante freed-outside-finally)

- **Regel:** SCA001 `MemoryLeak` – Object created without exception-safe release
- **Art:** Quick-Fix
- **Ändert Verhalten:** **ja** – `Free` läuft danach auch bei einer Ausnahme und bei Exit – das ist der Fix. Nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| en | de | fr |
|---|---|---|
| `Free %s in a try/finally block` | `%s in einem try/finally-Block freigeben` | `Libérer %s dans un bloc try/finally` |

**Platzhalter:** `%s` = die Variable aus der Meldung.

**Wirkung:** Nur für die Variante freed-outside-finally: das `Free` ist da, steht aber neben dem `finally`. Die Erzeugung `X := TFoo.Create..;` bleibt stehen, die Zeilen bis zur Freigabe rücken eine Stufe tiefer in einen neuen `try`-Teil, die Freigabe kommt ins `finally` – derselbe Baustein wie bei SCA009.

**Nicht angeboten**

- die Varianten never-freed, return-value-not-freed und proven-leak: der Eintrag steht gesperrt mit der Variante da (maßgeblich ist das Feld `LeakVariant` des Funds)
- die Freigabe ist bedingt, liegt tiefer, steht doppelt oder in anderer Schreibweise da, oder X bekommt im Bereich eine zweite Zuweisung
- X wird im Bereich weitergegeben (Argument eines Add-/Insert-/Register-…-Aufrufs, Zuweisung an ein Feld oder `Result`, Methodenzeiger, `@X` – auch durch Cast, Klammern oder `as`) oder steht in einem raise-Ausdruck
- Direktive, Marke/goto, asm, Inline-`var`/`const` auf der Ebene der Erzeugung, mehrzeiliges `'''`-Literal im Bereich

**Beispiel**

Vorher:

```pascal
  X := TStringList.Create;
  Y := TStringList.Create;
  try
    Y.Add('a');
  finally
    Y.Free;
  end;
  X.Free;
```

Nachher:

```pascal
  X := TStringList.Create;
  try
    Y := TStringList.Create;
    try
      Y.Add('a');
    finally
      Y.Free;
    end;
  finally
    X.Free;
  end;
```

<a id="sca002"></a>

### SCA002 – `raise;` in den leeren `except`-Block einfügen

- **Regel:** SCA002 `EmptyExcept` – Empty except block
- **Art:** Quick-Fix
- **Ändert Verhalten:** **ja** – eine bisher verschluckte Ausnahme läuft jetzt nach außen weiter – der Aufrufer muss sie behandeln; war das Verschlucken Absicht, ist das ein Eingriff. Nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| en | de | fr |
|---|---|---|
| `Add raise; to the empty except block` | `raise; in den leeren except-Block einfügen` | `Ajouter raise; au bloc except vide` |

**Wirkung:** Macht aus `try Work except end;` ein `try Work except raise; end;`. Stehen `except` und `end` auf verschiedenen Zeilen, kommt das `raise;` in eine neue Zeile unter `except`, eine Stufe tiefer (die Stufe liest die Hilfe aus dem try-Rumpf davor, sonst zwei Leerzeichen bzw. ein Tab). Der Detektor meldet auf der Zeile des `except`; die Hilfe bedient nur die eindeutige Form: zwischen `except` und `end` steht nur Leerraum.

**Nicht angeboten**

- ein Kommentar oder eine Direktive steht im Block oder ein Kommentar hinter dem `end` auf seiner Zeile (ein Kommentar ist Absicht, etwa `// ignore errors`, `end; // darf scheitern`)
- zwischen `except` und `end` steht etwas anderes als Leerraum: ein Handler (`on E: ... do`, auch der leere, das ist SCA159), eine Anweisung, ein einzelnes `;` (`except;`) oder ein `else`
- die Zeile ist verschoben (kein `except` als Code auf der Zeile) oder trägt mehrere `except`

**Beispiel**

Vorher:

```pascal
  try
    Work;
  except
  end;
```

Nachher:

```pascal
  try
    Work;
  except
    raise;
  end;
```

**Beispiel: In einer Zeile**

Vorher:

```pascal
  try Work except end;
```

Nachher:

```pascal
  try Work except raise; end;
```

**Hinweis.** Die Hilfe macht den Fund still, indem sie die Ausnahme weiterreicht; ob stattdessen geloggt oder gezielt behandelt werden soll, entscheidet der Autor.

<a id="sca007"></a>

### SCA007 – Unit aus uses entfernen

- **Regel:** SCA007 `UnusedUses` – Unused unit in uses clause
- **Art:** Quick-Fix
- **Ändert Verhalten:** **ja** – der Fund ist heuristisch (danach kompilieren – ein Typ, den der Detektor nicht kennt, macht ihn falsch), und ein `initialization`-Abschnitt der Unit läuft danach nicht mehr. Nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| en | de | fr |
|---|---|---|
| `Remove unit %s from uses` | `Unit %s aus uses entfernen` | `Retirer l'unité %s de uses` |

**Platzhalter:** `%s` = die Unit aus der Meldung.

**Wirkung:** Löscht den Eintrag der Meldung aus seiner uses-Klausel: mit dem Komma bis zum nächsten Eintrag bzw. – beim letzten – ab dem Komma davor; steht er allein auf seiner Zeile, die ganze Zeile samt `//`-Kommentar; der einzige Eintrag geht mit der ganzen Klausel. Ein `in`-Pfad geht mit. Vorher prüft die Hilfe den Fund am aktuellen Puffer nach (dieselben Spuren wie der Detektor).

**Nicht angeboten**

- der Puffer trägt den Fund nicht mehr (ein Fund aus einem älteren Scan)
- ein Kommentar im gelöschten Bereich, auch `{Form1}` hinter einer Formular-Unit
- Compiler-Direktiven in einer uses-Klausel
- im gelöschten Bereich steht mehr als dieser Eintrag

**Beispiel**

Vorher:

```pascal
uses
  A,
  B,
  C;
```

Nachher:

```pascal
uses
  A,
  C;
```

**Hinweis.** SCA007 meldet der Analyser nur mit eingeschaltetem uses-Check (`[Detectors] UsesCheck=1`). Im Beispiel nennt der Fund die Unit `B`.

<a id="sca009"></a>

### SCA009 – Objekt in try/finally freigeben

- **Regel:** SCA009 `MissingFinally` – Object created without protective try/finally
- **Art:** Quick-Fix
- **Ändert Verhalten:** **ja** – `Free` läuft danach auch bei einer Ausnahme und bei Exit – das ist der Fix. Nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| en | de | fr |
|---|---|---|
| `Free %s in a try/finally block` | `%s in einem try/finally-Block freigeben` | `Libérer %s dans un bloc try/finally` |

**Platzhalter:** `%s` = die Variable aus der Meldung.

**Wirkung:** Die Erzeugung `X := TFoo.Create..;` (auch `var X := ..`, `CreateFmt` & Co., über Zeilen) bleibt stehen, die Zeilen bis zur Freigabe `X.Free`/`X.Destroy`/`FreeAndNil(X)` rücken eine Stufe tiefer in den `try`-Teil, die Freigabe kommt ins `finally`; ein direkt folgendes `X := nil;` geht mit. `try`, `finally` und `end;` stehen in eigenen Zeilen, eingerückt wie die Erzeugung.

**Nicht angeboten**

- keine unbedingte Freigabe von X in derselben Anweisungsliste (sie fehlt, steht tiefer oder in einem Zweig), eine zweite Freigabe oder eine zweite Zuweisung an X im Bereich
- Erzeugung oder Freigabe nicht allein auf ihrer Zeile, die Erzeugung hinter then/else/do oder in einem case-Zweig, nichts zwischen Erzeugung und Freigabe
- X wird im Bereich weitergegeben: direktes Argument eines Add-/Insert-/Push-/Register-…-Aufrufs, ganze rechte Seite einer Zuweisung an Feld, Property, `Result` oder Parameter – auch durch Cast, Klammern oder `as` (`FCurrent := TFoo(X)`, `List.Add(X as TObject)`) –, Methodenzeiger an ein Ereignis, `@X`; X in einem raise-Ausdruck; auch über einen generischen Cast (`TList<TFoo>(X)`), einen generischen Aufruf (`Register<TFoo>(X)`) oder einen Array-Konstruktor (`AddRange([X])`, `FArr := [X]`)
- Exit bei weitergegebenem X, Break/Continue, deren Schleife den Bereich umschließt – auch als `System.Exit`/`System.Break`/`System.Continue`
- Direktive, Marke/goto, asm, Inline-`var`/`const` auf der Ebene der Erzeugung, mehrzeiliges `'''`-Literal, ein umschließendes try, dessen except- bzw. finally-Teil X nennt

**Beispiel**

Vorher:

```pascal
  X := TStringList.Create;
  X.Add('a');
  Foo(X);
  X.Free;
```

Nachher:

```pascal
  X := TStringList.Create;
  try
    X.Add('a');
    Foo(X);
  finally
    X.Free;
  end;
```

**Hinweis.** Das Meldungs-Suffix „(try/except instead of try/finally)“ schränkt die Hilfe nicht ein – es sagt nur, dass die Methode irgendwo ein try/except hat.

<a id="sca014"></a>

### SCA014 – Lokale Konstante einführen

- **Regel:** SCA014 `MagicNumber` – Numeric literal without named constant
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Introduce local constant for %s` | `Lokale Konstante für %s einführen` | `Introduire une constante locale pour %s` |

**Platzhalter:** `%s` = die Zahl aus der Meldung; den Namen der Konstante nennt der Hinweis des Eintrags.

**Wirkung:** Setzt `const MagicNr01 = N;` als eigene Anweisung direkt vor die Anweisung mit der if-Bedingung und ersetzt das Literal der Bedingung durch den Namen – nur dieses eine; gleiche Literale hinter `then` bleiben. Ein Zweig ohne `begin` bekommt `begin..end`. Der Name ist der erste `MagicNrNN`, der in der Datei nicht vorkommt; umbenennen von Hand oder mit Refactor > Rename (Strg+Umschalt+E). Bedeutungsgleich nach der Prämisse von E26: die untypisierte Inline-Konstante behält Faltung, Überladungswahl und vorzeichenlose Rechnung des Literals – für einen Vergleichswert einer if-Bedingung gilt das als sicher, gemessen ist es noch nicht (Teil P6 der Kompilierprobe, Bau offen).

**Nicht angeboten**

- die Zahl der Meldung steht nicht oder mehrfach als Vergleichswert in den if-Bedingungen der Fundzeile (Zeile verschoben bzw. mehrdeutig), oder nur in einer Folgezeile der Bedingung
- eine Zahl mit Zifferntrennern (`if X > 200_000`, auch `200_000.5`): der Detektor meldet nur ihren ersten Block (`200`) – ein Fehlalarm, der Grund sagt es
- die Sperren der Code-Aktion „Lokale Konstante einführen“: `else if`, Zweig über mehrere Zeilen, Zeile darüber ohne Anweisungsende, Direktive davor, case-Zweig, asm, initialization, mehrzeilige Strings und Kommentare
- Dateien, die FPC oder ein Compiler vor Delphi 10.3 übersetzt: FPC-Weiche oder Spuren alter Compiler in der Unit oder einem Include, ein Include, das nicht neben der Unit liegt, ein Lazarus-Projekt/-Paket in der Nähe, `.pp`/`.lpr`, ein altes Delphi-Projekt (`.dproj` vor 10.3, `.dof`, `.bdsproj`, `.bpr`, `.bpg`)
- ein Netzpfad oder Netzlaufwerk, auch für ein Include der Unit (kein Plattenzugriff beim Menüaufbau im Hauptthread)
- der Hauptblock eines Programms bzw. einer Bibliothek

**Beispiel**

Vorher:

```pascal
  Foo;
  if X > 200 then Y := 200;
```

Nachher:

```pascal
  Foo;
  const MagicNr01 = 200;
  if X > MagicNr01 then Y := 200;
```

**Hinweis.** Keine Sync-Edit-Sitzung zum Umbenennen: dort zerstört Esc Text.

<a id="sca020"></a>

### SCA020 – Leeren Rumpf als beabsichtigt kennzeichnen

- **Regel:** SCA020 `EmptyMethod` – Empty method body
- **Art:** Quick-Fix
- **Ändert Verhalten:**
  - Eintrag 1: nein
  - Eintrag 2: **ja** – der Aufruf löst danach eine Exception aus, statt nichts zu tun. Nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| Eintrag | en | de | fr |
|---|---|---|---|
| 1 | `Mark the empty body as intentional` | `Leeren Rumpf als beabsichtigt kennzeichnen` | `Marquer le corps vide comme intentionnel` |
| 2 | `Raise ENotImplemented in the empty body` | `ENotImplemented im leeren Rumpf auslösen` | `Lever ENotImplemented dans le corps vide` |

**Wirkung (Eintrag 1):** Setzt `// intentionally empty` in eine eigene Zeile zwischen `begin` und `end`, eine Stufe tiefer; stehen beide auf einer Zeile, `{ intentionally empty }` inline. Der Detektor wertet einen solchen Kommentar als Absicht – bedeutungsgleich.

**Wirkung (Eintrag 2):** Setzt `raise ENotImplemented.Create('<Name>');` mit dem Namen aus dem Methodenkopf in den leeren Rumpf; fehlt `System.SysUtils`, kommt es in uses.

**Nicht angeboten**

- zwei Routinenköpfe auf der Zeile (der Fund könnte jeden meinen), eine lokale Routine zwischen Kopf und Rumpf, `asm`
- hinter dem `begin` steht noch Code, oder der Rumpf ist nicht wirklich leer (Code unter einer inaktiven Direktive, ein asm-Block)
- ein Kommentar im Rumpf – er ist keine Absicht (sonst schwiege der Detektor), meist auskommentierter Code
- Eintrag 2: in constructor und destructor und ohne den Namen auf der Kopfzeile

**Beispiel (Eintrag 1)**

Vorher:

```pascal
procedure TFoo.DoStuff;
begin
end;
```

Nachher:

```pascal
procedure TFoo.DoStuff;
begin
  // intentionally empty
end;
```

**Beispiel (Eintrag 2)**

Vorher wie bei Eintrag 1.

Nachher:

```pascal
procedure TFoo.DoStuff;
begin
  raise ENotImplemented.Create('TFoo.DoStuff');
end;
```

<a id="sca046"></a>

### SCA046 – `to` durch `downto` ersetzen

- **Regel:** SCA046 `ReversedForRange` – for i := High to Low - missing downto
- **Art:** Quick-Fix
- **Ändert Verhalten:**
  - Eintrag 1: **ja** – die Schleife lief bisher nie und zählt danach abwärts; war sie absichtlich abgeschaltet, ist das ein Eingriff. Nur über Menü oder Glühbirne, nie über Strg+Alt+F.
  - Eintrag 2: **ja** – die Schleife lief bisher nie und zählt danach aufwärts; war sie absichtlich abgeschaltet, ist das ein Eingriff. Nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| Eintrag | en | de | fr |
|---|---|---|---|
| 1 | `Replace "to" with "downto"` | `"to" durch "downto" ersetzen` | `Remplacer "to" par "downto"` |
| 2 | `Swap the loop bounds` | `Schleifengrenzen vertauschen` | `Échanger les bornes de la boucle` |

**Wirkung (Eintrag 1):** Macht aus `for I := 10 to 1 do` ein `for I := 10 downto 1 do`. Der Detektor meldet nur Ganzzahl-Literale, die Meldung nennt keine Spalte: die Hilfe sucht den Kopf selbst und prüft die Werte gegen die Meldung.

**Wirkung (Eintrag 2):** Vertauscht stattdessen Start- und Endwert: `for I := 1 to 10 do`.

**Nicht angeboten**

- mehrere umgekehrte Köpfe auf der Zeile, ein Kopf über mehrere Zeilen
- ein Kommentar, eine Direktive oder ein String im Kopf, eine Typangabe an der Schleifenvariablen
- die Zeile ist verschoben (die Werte passen nicht zur Meldung)
- Eintrag 2: dieselben Sperren wie der erste Eintrag

**Beispiel (Eintrag 1)**

Vorher:

```pascal
  for I := 10 to 1 do
    Process(I);
```

Nachher:

```pascal
  for I := 10 downto 1 do
    Process(I);
```

**Beispiel (Eintrag 2)**

Vorher wie bei Eintrag 1.

Nachher:

```pascal
  for I := 1 to 10 do
    Process(I);
```

<a id="sca047"></a>

### SCA047 – Selbstzuweisung entfernen

- **Regel:** SCA047 `SelfAssignment` – x := x
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Remove the self-assignment of %s` | `Selbstzuweisung von %s entfernen` | `Supprimer l'auto-affectation de %s` |

**Platzhalter:** `%s` = das Ziel der Zuweisung.

**Wirkung:** Löscht `X := X;` – allein auf der Zeile die ganze Zeile –, auch für Pfade (`Pt.Y := Pt.Y;`, `R^.F := R^.F;`). Bedeutungsgleich; war ein anderer Wert gemeint (Tippfehler), fehlt er weiterhin – der Hinweis des Eintrags sagt es.

**Nicht angeboten**

- `Result := Result` (stillt vielleicht W1035 – dort lieber unterdrücken)
- die Wurzel ist keine Variable, ein Pfadteil ist eine Property der Unit, X ist auch eine Routine der Unit
- ein `class operator Assign` in der Unit (verwaltete Records führen bei der Zuweisung Code aus)
- ein Kommentar auf der Zeile, die einzige Anweisung hinter then/else/do, eines case-Zweigs oder eines Blocks, über mehrere Zeilen, im `with`-Block

**Beispiel**

Vorher:

```pascal
  Foo;
  Temp := Temp;
  Bar;
```

Nachher:

```pascal
  Foo;
  Bar;
```

<a id="sca053"></a>

### SCA053 – Ungenutzte lokale Variable entfernen

- **Regel:** SCA053 `UnusedLocalVar` – Unused local variable
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Remove unused variable %s` | `Ungenutzte Variable %s entfernen` | `Supprimer la variable inutilisée %s` |

**Platzhalter:** `%s` = die Variable aus der Meldung.

**Wirkung:** Löscht die Deklaration: `X: T;` samt Zeile (ein `//`-Kommentar dahinter geht mit – außer er trägt einen Marker, `noinspection` oder TODO/FIXME/HACK/XXX: der gilt der Zeile dahinter bzw. bleibt stehen, als eigene Zeile), aus `A, X, B: T;` wird `A, B: T;`, `var` geht mit, wenn die Section dadurch leer wird, eine Inline-Deklaration `var X: T;` als ganze Anweisung. Bedeutungsgleich – vorher prüft die Hilfe am Text, dass der Name im Gültigkeitsbereich sonst nirgends als Code vorkommt (auch in lokalen Routinen, inaktiven Zweigen und asm).

**Nicht angeboten**

- `for var` (der Detektor meldet die Laufvariable) und ein Schlüsselwort als Name (`resourcestring`)
- eine const-/resourcestring-Section, ein Initialisierer (`= 5`, `:= F()`), `absolute`, ein Typ über mehrere Zeilen, ein Attribut, ein Kommentar oder eine Direktive in der Deklaration
- ein `// noinspection` darüber, der auf die Zeile der Deklaration zielt – gelöscht gälte er der Zeile dahinter
- ein `class operator Initialize/Finalize` in der Unit (die Variable führt Code aus)
- ein `{$I}`-Include, eine Direktive, die den Namen nennt, oder `asm` im Gültigkeitsbereich; ein FPC-Makro `{$DEFINE M := X}` in der Datei
- die einzige Anweisung eines Blocks, außerhalb einer Routine, in einer offenen Klammer (ein Parameter, keine Variable)

**Beispiel**

Vorher:

```pascal
procedure P;
var
  A: Integer;
  X: TObject;
  B: string;
begin
  A := Length(B);
end;
```

Nachher:

```pascal
procedure P;
var
  A: Integer;
  B: string;
begin
  A := Length(B);
end;
```

**Beispiel: die Section wird leer**

Vorher:

```pascal
procedure P;
var
  Tmp: Integer;   // never used
begin
  DoStuff;
end;
```

Nachher:

```pascal
procedure P;
begin
  DoStuff;
end;
```

<a id="sca060"></a>

### SCA060 – goto durch Exit ersetzen

- **Regel:** SCA060 `GotoStatement` – goto statement
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Replace "goto" with Exit` | `"goto" durch Exit ersetzen` | `Remplacer « goto » par Exit` |

**Wirkung:** Ersetzt das gemeldete `goto Marke` durch `Exit`, wenn die Marke die letzte Anweisung der Routine ist (`Marke:` steht unmittelbar vor dem end des Rumpfs). Dann führt der Sprung ans Routinenende, genau wie Exit; ein goto aus einem try heraus übersetzt Delphi nicht (E2127) – das Exit der Hilfe übersetzt und läuft durch das finally, Result einer Funktion bleibt unverändert. Die Marke selbst bleibt stehen.

**Nicht angeboten**

- die Marke ist nicht die letzte Anweisung der Routine (Code dahinter, Marke in einem inneren Block, Rücksprung)
- mehr als ein goto auf der Zeile, die Marke steht nicht auf derselben Zeile, ein Kommentar steht im goto, oder die Zeile ist verschoben
- keine Routine mit begin..end-Rumpf um die Zeile (Hauptblock, initialization, asm) oder unsichere Routinengrenzen
- der Rumpf enthält eine Compiler-Direktive oder eine anonyme Methode
- die Datei deklariert einen eigenen Bezeichner Exit

**Beispiel**

Vorher:

```pascal
label Fin;
begin
  if Failed then goto Fin;
  Work;
Fin:
end;
```

Nachher:

```pascal
label Fin;
begin
  if Failed then Exit;
  Work;
Fin:
end;
```

**Hinweis.** Die Marke bleibt stehen. Springt kein weiteres goto mehr zu ihr, meldet Delphi sie als ungenutzte Marke (Hinweis/Warnung, kein Fehler); Marke und label-Eintrag können dann von Hand entfallen.

<a id="sca061"></a>

### SCA061 – Tabulatoren der Zeile durch Leerzeichen ersetzen

- **Regel:** SCA061 `TabulationCharacter` – Tab character in source
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Replace the tabs in this line with spaces` | `Tabulatoren dieser Zeile durch Leerzeichen ersetzen` | `Remplacer les tabulations de cette ligne par des espaces` |

**Wirkung:** Ersetzt die Tabulatoren im Code der gemeldeten Zeile durch Leerzeichen bis zum nächsten Tabstopp (Tabweite 2, feste Annahme; Leerzeichen und Tab davor werden sauber zusammengezogen). Eine Ersetzung vom ersten bis zum letzten Code-Tab; Tabs in Strings und Kommentaren dazwischen bleiben. Nur die gemeldete Zeile.

**Nicht angeboten**

- der erste Tab der Zeile liegt in einem String, Kommentar oder mehrzeiligen String (der Detektor meldet ihn trotzdem, der Fund bliebe stehen)
- die Zeile ist verschoben, oder die Meldung nennt keine Spalte

**Beispiel:** nicht abbildbar – der Unterschied ist nur Leerraum (Tab gegen Leerzeichen).

**Hinweis.** Bleibt hinter dem letzten Code-Tab ein Tab in einem String oder Kommentar, meldet der Detektor die Zeile nach der Hilfe weiter.

<a id="sca063"></a>

### SCA063 – Leerraum am Zeilenende entfernen

- **Regel:** SCA063 `TrailingWhitespace` – Trailing whitespace
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Remove the trailing whitespace` | `Leerraum am Zeilenende entfernen` | `Supprimer les espaces en fin de ligne` |

**Wirkung:** Löscht die Leerzeichen und Tabs am Zeilenende, ab der Spalte aus der Meldung. Eine reine Leerzeile aus Blanks wird leer. Kommentare, Direktiven und Code sind erlaubt. Bedeutungsgleich.

**Nicht angeboten**

- der Leerraum ist String-Inhalt: eine Zeile in einem mehrzeiligen String (`'''`), die Eröffnungszeile selbst oder ein nicht geschlossener String
- die Endfolge beginnt nicht bei der Spalte aus der Meldung, oder sie reicht nicht bis zum Zeilenende

**Beispiel:** nicht abbildbar – der Unterschied ist nur Leerraum am Zeilenende.

<a id="sca064"></a>

### SCA064 – Schlüsselwort kleinschreiben

- **Regel:** SCA064 `LowercaseKeyword` – Pascal keyword not lowercase
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Write %s in lowercase` | `%s klein schreiben` | `Écrire %s en minuscules` |

**Platzhalter:** `%s` = das Schlüsselwort wie gemeldet (etwa `Begin`).

**Wirkung:** Schreibt das gemeldete Schlüsselwort an der gemeldeten Spalte klein (`Begin` → `begin`). Bedeutungsgleich: Delphi unterscheidet Groß- und Kleinschreibung nicht.

**Nicht angeboten**

- das Wort steht in einem Kommentar oder String, ist Teil eines Bezeichners oder schon klein geschrieben
- das Wort ist ein Bezeichner: hinter `.`, `&` oder `@`, vor `:=`, als benanntes Argument
- ein Wort, das auch Bezeichner sein kann (`on`, `out`, `contains`, `requires`, `implements`, `absolute`); Direktiven und Sichtbarkeitswörter nur im passenden Kontext
- die Zeile ist verschoben, oder die Meldung nennt Wort oder Spalte nicht
- ein Feld, das wie eine Direktive heißt und hinter einem Prozedurtyp-Feld steht (`OnDone: procedure of object;` / `Forward: Boolean;`) – Feldnamen sind über RTTI sichtbar

**Beispiel**

Vorher:

```pascal
procedure Run;
Begin
  DoWork;
end;
```

Nachher:

```pascal
procedure Run;
begin
  DoWork;
end;
```

**Hinweis.** Der Detektor meldet auch Member hinter einem Punkt (`Foo.End`); die Hilfe bietet dort nichts an.

<a id="sca065"></a>

### SCA065 – NOSONAR durch einen noinspection-All-Marker über der Zeile ersetzen

- **Regel:** SCA065 `NoSonarMarker` – NOSONAR suppression marker
- **Art:** Quick-Fix
- **Ändert Verhalten:** **ja** – der Marker unterdrückt jetzt alle Regeln der Zeile (bisher unterdrückte NOSONAR nichts); kritische Arten (HardcodedSecret, SQLInjection u. a.) bleiben sichtbar. Nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| en | de | fr |
|---|---|---|
| `Replace NOSONAR with a "noinspection All" marker` | `NOSONAR durch einen Marker "noinspection All" ersetzen` | `Remplacer NOSONAR par un marqueur "noinspection All"` |

**Wirkung:** Aus `X; // NOSONAR - Grund` wird eine eigene Zeile `// noinspection All` (mit dem Einzug der Zeile) über dem Code; der Rest des Kommentars bleibt hinter dem Code (`X; // Grund`). Ein führender `:` oder `-` hinter NOSONAR fällt weg, ohne Rest entfällt der Kommentar. Der Marker steht bewusst darüber: ein `noinspection` gilt für die folgende Zeile, und `All` zählt nur als ganze Artenliste – ein Grund dahinter machte ihn wirkungslos.

**Nicht angeboten**

- der Kommentar steht auf einer eigenen Zeile (unklar, welche Zeile gemeint ist), NOSONAR ist nicht das erste Wort oder steht mehrfach da
- der Rest hinter NOSONAR beginnt mit `noinspection`, oder direkt darüber steht schon `// noinspection All`
- das `//` steht in einem Block-Kommentar, String oder mehrzeiligen String, die Zeile ist verschoben, oder die Meldung nennt keine Spalte

**Beispiel**

Vorher:

```pascal
  Dispose(P); // NOSONAR - we know about this
```

Nachher:

```pascal
  // noinspection All
  Dispose(P); // we know about this
```

**Hinweis.** Findet SCA auf der Zeile nichts zu unterdrücken, meldet SCA165 den neuen Marker als wirkungslos; dann den Kommentar ganz löschen.

<a id="sca066"></a>

### SCA066 – Leere Klammern entfernen

- **Regel:** SCA066 `EmptyArgumentList` – Empty argument list
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Remove the empty parentheses` | `Leere Klammern entfernen` | `Retirer les parenthèses vides` |

**Wirkung:** `Foo()` → `Foo` an der Spalte aus der Meldung, auch in Deklarationen (`procedure Foo();`) – nur, wo Delphi den Namen ohne Klammern genauso aufruft: als ganze Anweisung, als ganze Bedingung von if/while/until oder als ganze rechte Seite einer Zuweisung an eine einfache Variable mit bekanntem, nicht prozeduralem Typ.

**Nicht angeboten**

- als Argument oder Teil eines Ausdrucks (etwa bei einer Überladung mit `TFunc`), bei `Arr[0]()` und `F()()`
- der Name ist eine Variable (Prozedurvariable) oder heißt wie ein Ereignis (`OnIdle()`)
- die Unit deklariert den Namen als Property, auch hinter einem Pfad (`Dlg.RefProc()`) – ob Delphi eine Property mit Prozedurtyp ohne () aufruft, ist ohne Delphi-12-Probe nicht belegt; eine Property einer anderen Unit mit unauffälligem Namen sieht die Sperre nicht
- in der eigenen Funktion, im `with`-Block, in Dateien mit FPC-Weiche oder FPC-Modus

**Beispiel**

Vorher:

```pascal
  DoStuff();
```

Nachher:

```pascal
  DoStuff;
```

<a id="sca068"></a>

### SCA068 – Überzähliges Komma entfernen

- **Regel:** SCA068 `TrailingCommaArgList` – Trailing comma in argument list
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Remove the trailing comma` | `Überzähliges Komma entfernen` | `Supprimer la virgule superflue` |

**Wirkung:** Löscht das Komma vor der schließenden Klammer einer Argumentliste samt dem Leerraum bis zur `)`: `Foo(A, B,)` wird `Foo(A, B)`. Der Detektor meldet die Spalte des Kommas; die Hilfe sucht rückwärts die öffnende Klammer.

**Nicht angeboten**

- vor dem Komma steht kein Argument (`Foo(,)`, `Foo(A,,)`): dort fehlt ein Element, das Komma ist nicht überzählig
- das Komma beendet eine Liste in `[...]` (Set- oder Array-Literal), oder die öffnende Klammer ist nicht zu finden
- die Zeile ist verschoben: an der Spalte steht kein Komma im Code, oder dahinter folgt etwas anderes als Leerraum und `)` (Kommentar, String)

**Beispiel**

Vorher:

```pascal
  WriteLn('A', 'B', );
  DoStuff(Param1, Param2,);
```

Nachher:

```pascal
  WriteLn('A', 'B');
  DoStuff(Param1, Param2);
```

**Hinweis.** Bedeutungsgleich: das Komma trug nichts.

<a id="sca070"></a>

### SCA070 – Auskommentierten Code löschen

- **Regel:** SCA070 `CommentedOutCode` – Commented-out code
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Delete commented-out code` | `Auskommentierten Code löschen` | `Supprimer le code mis en commentaire` |

**Wirkung:** Löscht genau die Region der Meldung ab Zeile und Spalte: eine `//`-Zeile ganz, einen Kommentar hinter Code ab seiner Spalte, die Inhaltszeilen eines mehrzeiligen `{ }`/`(* *)`. Die Begrenzer gehen erst mit, wenn der Kommentar danach leer ist; Prosa vor oder hinter der Region bleibt. Bedeutungsgleich.

**Nicht angeboten**

- eine Direktive im Bereich, ein Doku-Kommentar (`///`, `{*`, `(**`), ein Kopfkommentar vor dem ersten Code der Datei (Lizenz)
- `noinspection` oder TODO/FIXME/HACK/XXX im gelöschten Text
- der Text passt nicht mehr zur Meldung (Spalte, Code-Merkmal der ersten und letzten Zeile) – Zeile verschoben
- mehrere Kommentare in der Region, von denen einer mit Text über sie hinausreicht

**Beispiel**

Vorher:

```pascal
  Foo;
  // X := 1;
  Bar;
```

Nachher:

```pascal
  Foo;
  Bar;
```

**Beispiel: Blockkommentar über mehrere Zeilen**

Vorher:

```pascal
  Foo;
  {
    X := 1;
    Y := 2;
  }
  Bar;
```

Nachher:

```pascal
  Foo;
  Bar;
```

<a id="sca071"></a>

### SCA071 – Schlüsselwort an Spalte 1 setzen

- **Regel:** SCA071 `UnitLevelKeywordIndent` – Unit-level keyword not at column 1
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Move the keyword to column 1` | `Schlüsselwort an Spalte 1 setzen` | `Placer le mot-clé en colonne 1` |

**Wirkung:** Löscht die Einrückung vor dem Unit-Schlüsselwort aus der Meldung (`interface`, `implementation` …). Bedeutungsgleich – nur Leerraum.

**Nicht angeboten**

- vor dem Schlüsselwort steht mehr als Leerraum (ein Kommentar ginge verloren)
- die Zeile beginnt in einem Kommentar oder mehrzeiligen String
- das `interface` gehört zu einem Typ (`IFoo =` davor)

**Beispiel**

Vorher:

```pascal
unit u;
interface
  implementation
end.
```

Nachher:

```pascal
unit u;
interface
implementation
end.
```

<a id="sca072"></a>

### SCA072 – Überflüssigen Vergleich mit True/False entfernen

- **Regel:** SCA072 `RedundantBoolean` – Redundant boolean comparison
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Remove the redundant comparison with True/False` | `Überflüssigen Vergleich mit True/False entfernen` | `Retirer la comparaison superflue avec True/False` |

**Wirkung:** `X = True` / `X <> False` → `X`, `X = False` / `X <> True` → `not X` – für einen bloßen Bezeichner, der in der Unit als `Boolean` deklariert ist.

**Nicht angeboten**

- X ist kein bloßer Bezeichner (Pfad, auch `Self.X`) oder nicht als `Boolean` deklariert – bei Variant und LongBool ist `= True` nicht dasselbe
- links beginnt kein Ausdruck bzw. rechts von True/False endet keiner (`X = True and Y` heißt `X = (True and Y)`)
- im `with`-Block

**Beispiel**

Vorher:

```pascal
  if IsDone = False then Exit;
```

Nachher:

```pascal
  if not IsDone then Exit;
```

<a id="sca074"></a>

### SCA074 – Bedingung als Assert-Meldung

- **Regel:** SCA074 `AssertMessage` – Assert without message
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Use the condition as the Assert message` | `Bedingung als Assert-Meldung verwenden` | `Utiliser la condition comme message d'Assert` |

**Wirkung:** `Assert(c)` → `Assert(c, 'c')` an der Spalte aus der Meldung; Apostrophe der Bedingung werden verdoppelt. Bedeutungsgleich – die Meldung nennt danach, was fehlschlug.

**Nicht angeboten**

- die Klammer schließt nicht auf derselben Zeile, oder ein Kommentar steht darin
- `Obj.Assert`, eine eigene Routine `Assert` in der Unit, `with`-Block
- das Literal würde länger als 255 Zeichen (E2056)

**Beispiel**

Vorher:

```pascal
  Assert(X > 0);
```

Nachher:

```pascal
  Assert(X > 0, 'X > 0');
```

<a id="sca075"></a>

### SCA075 – (TObject) aus der Klassendeklaration entfernen

- **Regel:** SCA075 `ExplicitTObjectInheritance` – Explicit TObject inheritance
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Remove (TObject) from the class declaration` | `(TObject) aus der Klassendeklaration entfernen` | `Retirer (TObject) de la déclaration de classe` |

**Wirkung:** `class(TObject)` → `class` an der Spalte aus der Meldung, nur auf den Zeilen, ohne Parser. Bedeutungsgleich – TObject ist ohnehin der Vorfahr. Aus `class(TObject);` wird `class end;` (ein bloßes `class;` wäre eine Vorwärtsdeklaration).

**Nicht angeboten**

- an der Spalte der Meldung steht kein `class(TObject)` (Puffer geändert), oder die Meldung nennt keine Spalte
- weitere Einträge in der Klammer (`class(TObject, IFoo)`)
- der Klassenrumpf steht auf derselben Zeile
- die Stelle liegt in einem mehrzeiligen String

**Beispiel**

Vorher:

```pascal
  TFoo = class(TObject)
```

Nachher:

```pascal
  TFoo = class
```

<a id="sca076"></a>

### SCA076 – Gruppierte Deklaration in Einzelzeilen teilen

- **Regel:** SCA076 `GroupedDeclaration` – Grouped variable / field / parameter declaration
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Split the grouped declaration` | `Gruppierte Deklaration aufteilen` | `Scinder la déclaration groupée` |

**Wirkung:** Macht aus `A, B, C: Integer;` je Name eine Zeile (`A: Integer;`, `B: Integer;`, `C: Integer;`) mit der Einrückung der Ursprungszeile. Nur eine einzeilige Variablen- oder Felddeklaration mit einem einfachen Typnamen; steht `var` davor, trägt jede neue Zeile das `var` wieder.

**Nicht angeboten**

- der Typ ist kein einfacher Typname: `record`, `class`, `array of`, `array[..] of`, `set of`, Aufzählung, `^T`, `string[N]` (je Name entstünde ein eigener Typ, `A := B` ginge nicht mehr); Generics aus Vorsicht
- Initialisierer (`= 5`), `absolute`, Direktive hinter dem Typ, Kommentar, String oder Direktive auf der Zeile
- mehrzeilige Deklaration, mehrere Gruppen auf der Zeile
- etwas anderes als Leerraum oder ein einzelnes `var` vor den Namen (Attribut, `private`, `class var`, `threadvar`)
- Parameterlisten und case-Marken; die Zeile ist verschoben, oder die Meldung nennt keine Spalte
- vor der Gruppe steht ein Attribut, auch auf der Zeile darüber (`[Weak]` über `FA, FB: IFoo;`) – es gilt für alle Namen, nach dem Teilen stünde es nur über dem ersten

**Beispiel**

Vorher:

```pascal
var
  A, B, C: Integer;
```

Nachher:

```pascal
var
  A: Integer;
  B: Integer;
  C: Integer;
```

**Hinweis.** Der Detektor meldet auch Gruppen mit anonymem Typ; dort bleibt der Fund stehen.

<a id="sca077"></a>

### SCA077 – Leeres `with ... do begin end` durch den Aufruf ersetzen

- **Regel:** SCA077 `EmptyBlock` – Empty begin..end block
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Replace the empty "with ... do begin end" by the call` | `Leeres "with ... do begin end" durch den Aufruf ersetzen` | `Remplacer le « with ... do begin end » vide par l'appel` |

**Wirkung:** Ersetzt `with <Aufrufkette> do begin end` durch die Aufrufkette als Anweisung (`with X.Add(T) do begin end;` wird `X.Add(T);`). `begin` und `end` dürfen auf eigenen Zeilen stehen; der Fund steht auf der Zeile des `begin`. Der Aufruf wird wie vorher genau einmal ausgeführt. Bedeutungsgleich. Andere leere Blöcke (`begin end;` allein, `if C then begin end;`, `else begin end`, `while C do begin end;`) bekommen keine Hilfe.

**Nicht angeboten**

- der leere Block gehört nicht zu einem `with ... do` (if, else, while, for, allein stehendes begin..end): ob eine Anweisung fehlt oder der Zweig weg kann, entscheidet nur der Mensch
- der Ausdruck ist kein Aufruf (`with Foo do begin end;`: als Anweisung bliebe ein Bezeichner), mehrere Objekte im `with` (`with A, B do`), der Kopf geht über mehrere Zeilen, oder die Form ist keine Kette `A.B(...).C(...)` (Index, `as`, Generics)
- der Ausdruck könnte ein Typecast sein (`with TButton(Sender) do`, `with Foo(X) do`: `Name(X);` ist keine Anweisung)
- ein Kommentar oder eine Direktive steht zwischen `with` und `end`, hinter dem `end` folgt etwas anderes als `;` oder ein Blockende, die Zeile ist verschoben oder trägt mehrere `begin`

**Beispiel**

Vorher:

```pascal
  with Items.Add(T) do begin end;
```

Nachher:

```pascal
  Items.Add(T);
```

<a id="sca080"></a>

### SCA080 – Überflüssiges Exit/Continue entfernen

- **Regel:** SCA080 `RedundantJump` – Redundant Exit/Continue before end
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Remove the redundant %s` | `Überflüssiges %s entfernen` | `Supprimer le %s superflu` |

**Platzhalter:** `%s` = `Exit` bzw. `Continue`.

**Wirkung:** Löscht `Exit;` bzw. `Continue;` vor dem Ende – allein auf der Zeile die ganze Zeile; hinter dem `else` eines if fällt `else Exit` weg. Bedeutungsgleich: dahinter folgt nur noch die end-Kette bis zum Routinen- bzw. Schleifenende.

**Nicht angeboten**

- die einzige Anweisung hinter then/do, eines case-Zweigs, des else von case/except oder eines Blocks (es bliebe ein leerer Zweig)
- mehrere Sprünge auf der Zeile, ein Kommentar auf der Zeile (er erklärt den Sprung)
- eine eigene Routine `Exit` bzw. `Continue` in der Unit
- Exit im Rumpf einer Schleife, Sprünge im `finally`-Teil

**Beispiel**

Vorher:

```pascal
procedure P;
begin
  DoStuff;
  Exit;
end;
```

Nachher:

```pascal
procedure P;
begin
  DoStuff;
end;
```

<a id="sca082"></a>

### SCA082 – Überzähliges Semikolon entfernen

- **Regel:** SCA082 `SuperfluousSemicolon` – Double semicolon
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Remove the extra semicolon` | `Überzähliges Semikolon entfernen` | `Supprimer le point-virgule en trop` |

**Wirkung:** `;;` bzw. `; ;` an der Spalte aus der Meldung → `;` – das zweite war eine leere Anweisung.

**Nicht angeboten**

- an der Spalte der Meldung steht kein `;;` (Zeile verschoben), oder die Meldung nennt keine Spalte
- das `;;` steht in einem String, Kommentar oder mehrzeiligen String

**Beispiel**

Vorher:

```pascal
  DoStuff;;
```

Nachher:

```pascal
  DoStuff;
```

<a id="sca083"></a>

### SCA083 – Leeres try/finally auflösen

- **Regel:** SCA083 `EmptyFinallyBlock` – Empty finally block
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Remove the empty try/finally` | `Leeres try/finally entfernen` | `Supprimer le try/finally vide` |

**Wirkung:** Entfernt `try`, `finally` und `end` und rückt den Rumpf eine Stufe aus (Tab oder Leerzeichen des Umfelds bleiben). Fehlt dem Rumpf das `;` und stand eines hinter dem `end`, setzt die Hilfe es hinter die letzte Anweisung. Bedeutungsgleich: Ausnahmen laufen weiter nach außen.

**Nicht angeboten**

- ein Kommentar oder eine Direktive im `finally` (der Detektor meldet solche Fälle trotzdem, weil er Kommentare ausblendet)
- `try` steht hinter `then`, `else`, `do` oder einer Marke (dort bräuchte es ein `begin`)
- try, finally und end stehen nicht je allein auf ihrer Zeile, die Einrückung weicht ab, oder der Rumpf ist leer
- im Rumpf stehen `label`, `goto` oder `asm`, oder `var`/`const` auf seiner obersten Ebene (ein `const`-Parameter einer anonymen Methode oder ein Inline-`var` in einem inneren begin..end stört nicht), oder im Bereich liegt eine Direktive oder ein Blockkommentar

**Beispiel**

Vorher:

```pascal
  try
    DoWork;
  finally
  end;
```

Nachher:

```pascal
  DoWork;
```

<a id="sca084"></a>

### SCA084 – Überflüssigen nil-Vergleich entfernen

- **Regel:** SCA084 `AssignedAndAssignedNil` – Redundant Assigned + nil check
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Remove the redundant comparison with nil` | `Überflüssigen Vergleich mit nil entfernen` | `Retirer la comparaison superflue avec nil` |

**Wirkung:** `Assigned(X) and (X <> nil)` bzw. `(X <> nil) and Assigned(X)` → `Assigned(X)` – alles auf einer Zeile, der Vergleich geklammert.

**Nicht angeboten**

- X ist nicht als Klasse, Interface oder Zeiger bewiesen (in der Unit deklariert, auch über Alias, oder eine Klasse der Delphi-Quellen, E27) – bei einem Funktionstyp ruft `X <> nil` ihn auf, `Assigned(X)` nicht
- `not` davor (es bindet nur an den ersten Teil), eine Aufruf- oder Cast-Klammer (`Boolean(X <> nil) and …`)
- eine eigene Routine `Assigned` in der Unit, `with`-Block

**Beispiel**

Vorher:

```pascal
  if Assigned(Obj) and (Obj <> nil) then ;
```

Nachher:

```pascal
  if Assigned(Obj) then ;
```

<a id="sca085"></a>

### SCA085 – FreeAndNil statt Free und nil

- **Regel:** SCA085 `FreeAndNilHint` – X.Free; X := nil; should be FreeAndNil(X)
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Use FreeAndNil(%s)` | `FreeAndNil(%s) verwenden` | `Utiliser FreeAndNil(%s)` |

**Platzhalter:** `%s` = die Variable aus der Meldung.

**Wirkung:** `X.Free;` + `X := nil;` → `FreeAndNil(X);`. Fehlt `System.SysUtils` in uses, kommt es als zweite Ersetzung mit (in der Schreibweise der Datei).

**Nicht angeboten**

- X ist nicht in der Unit deklariert (Property, geerbtes Feld) oder steht im `with`-Block
- der Typ von X ist in der Unit – auch über einen Alias – ein `record`, `object`, `interface`, ein Zeiger (`PFoo = ^TFoo`) oder ein eigener Typ (`= type ..`), die Unit deklariert eine Routine `Free`, oder der Typ ist nach Konvention ein Zeiger einer anderen Unit (`PEVP_PKEY`, auch hinter einem Alias der Unit) – `FreeAndNil` nimmt nur ein `TObject`
- eine Direktive vor `X.Free;` (das nil würde bedingt)
- die Zeile trägt ein anderes Paar als die Meldung (Zeile verschoben)
- ein Kommentar im Ausdruck (`X{owned}.Free;`, `X.{c}Free;`, `X.Free {c};`) – der Detektor meldet diese Formen wie `X.Free;`, der Grund nennt den Kommentar
- `System.SysUtils` fehlt und die uses-Klausel trägt Direktiven oder liegt in einem `$IFDEF`-Zweig

**Beispiel**

Vorher:

```pascal
  L.Free;
  L := nil;
```

Nachher:

```pascal
  FreeAndNil(L);
```

<a id="sca087"></a>

### SCA087 – Leeren Sichtbarkeitsabschnitt entfernen

- **Regel:** SCA087 `EmptyVisibilitySection` – Empty visibility section in class
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Remove the empty visibility section` | `Leeren Sichtbarkeitsabschnitt entfernen` | `Retirer la section de visibilité vide` |

**Wirkung:** Löscht die Zeile des leeren Abschnitts (`public`, `strict private` …). Bedeutungsgleich.

**Nicht angeboten**

- die Zeile trägt mehr als genau diesen Abschnitt, etwa einen Kommentar
- `strict` allein auf der Zeile (es gehört zur nächsten)
- eine Compiler-Direktive bis zum nächsten Abschnitt (er wäre vielleicht nur in einem Zweig leer)

**Beispiel**

Vorher:

```pascal
  TFoo = class
  public
  private
    FX: Integer;
  end;
```

Nachher:

```pascal
  TFoo = class
  private
    FX: Integer;
  end;
```

<a id="sca088"></a>

### SCA088 – begin durch initialization ersetzen

- **Regel:** SCA088 `LegacyInitializationSection` – Legacy unit-init begin..end.
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Replace begin with initialization` | `begin durch initialization ersetzen` | `Remplacer begin par initialization` |

**Wirkung:** Das `begin` des Unit-Rumpfs (`begin .. end.`) wird `initialization`, in der Schreibweise des `begin`. Bedeutungsgleich – der Abschnitt kann danach ein `finalization` bekommen.

**Nicht angeboten**

- in `program` und `library` (dort ist es der Rumpf)
- das `end` zu genau diesem `begin` steht nicht vor dem Punkt
- eine Direktive auf der Zeile

**Beispiel**

Vorher:

```pascal
procedure P; begin end;
begin
  P;
end.
```

Nachher:

```pascal
procedure P; begin end;
initialization
  P;
end.
```

<a id="sca093"></a>

### SCA093 – Zweiten doppelten inherited-Aufruf entfernen

- **Regel:** SCA093 `TwiceInheritedCalls` – Multiple inherited calls in one method
- **Art:** Quick-Fix
- **Ändert Verhalten:**
  - Eintrag 1: **ja** – die Elternmethode läuft nur noch einmal – Reihenfolge und Nebenwirkung prüfen. Nur über Menü oder Glühbirne, nie über Strg+Alt+F.
  - Eintrag 2: **ja** – die Elternmethode läuft nur noch einmal – Reihenfolge und Nebenwirkung prüfen. Nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| Eintrag | en | de | fr |
|---|---|---|---|
| 1 | `Remove the second duplicate inherited call` | `Zweiten doppelten inherited-Aufruf entfernen` | `Supprimer le deuxième appel inherited en double` |
| 2 | `Remove the first duplicate inherited call` | `Ersten doppelten inherited-Aufruf entfernen` | `Supprimer le premier appel inherited en double` |

**Wirkung (Eintrag 1):** Löscht den zweiten von zwei gleichen, direkt aufeinander folgenden `inherited`-Aufrufen im Rumpf. Der Detektor meldet auf der Zeile des Methodenkopfs; die Hilfe sucht die Aufrufe selbst, nur auf oberster Ebene des Rumpfs, und verlangt genau zwei.

**Wirkung (Eintrag 2):** Löscht stattdessen den ersten der beiden Aufrufe.

**Nicht angeboten**

- eine Anweisung, ein Kommentar oder eine Direktive steht zwischen den Aufrufen (auch das Katalogbeispiel `inherited; DoStuff; inherited;`: ohne Datenfluss ist nicht zu beweisen, dass das Weglassen gleich bleibt)
- die Aufrufe stehen in if, case, try oder einem verschachtelten Block; es sind nicht genau zwei; sie sind nicht textgleich oder nicht je allein auf ihrer Zeile
- der letzte Aufruf hat vor dem `end` kein `;`, oder die Routine hat eine verschachtelte Routine, asm oder external
- Eintrag 2: dieselben Sperren wie der erste Eintrag

**Beispiel (Eintrag 1)**

Vorher:

```pascal
procedure TFoo.Done;
begin
  inherited;
  inherited;
end;
```

Nachher:

```pascal
procedure TFoo.Done;
begin
  inherited;
end;
```

**Beispiel (Eintrag 2)**

Vorher wie bei Eintrag 1.

Nachher:

```pascal
procedure TFoo.Done;
begin
  inherited;
end;
```

<a id="sca094"></a>

### SCA094 – Überflüssiges inneres Klammerpaar entfernen

- **Regel:** SCA094 `RedundantParentheses` – Redundant double parentheses
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Remove the redundant inner parentheses` | `Das überflüssige innere Klammerpaar entfernen` | `Retirer la paire de parenthèses interne superflue` |

**Wirkung:** Macht aus `((X))` ein `(X)`: das innere Paar fällt, das äußere bleibt. Bedeutung und Rangfolge bleiben gleich.

**Nicht angeboten**

- nur nach einem Operator (`:=`, `+`, `-`, `and`, `or` …) oder Schlüsselwort (`if`, `while`, `until` …) oder bei einem Literal als Inhalt hinter einem Bezeichner (`Foo((1))`) – sonst nicht
- `Foo((X))` mit einer Variablen: das innere Paar könnte ein Ausdruck für einen var-Parameter, eine Überladung oder ein Cast sein (3 von 4 Funden im Korpus)
- nach `=`, `:`, `,` oder `(` (Konstante, Vergleich, dreifache Klammer) und am Zeilenanfang
- ein Kommentar im Klammerpaar, danach folgt `.`, `[` oder `(`, oder die Zeile ist verschoben

**Beispiel**

Vorher:

```pascal
  if ((Ready)) then
    Run;
```

Nachher:

```pascal
  if (Ready) then
    Run;
```

<a id="sca096"></a>

### SCA096 – inherited als Erstes im Konstruktor aufrufen

- **Regel:** SCA096 `ConstructorWithoutInherited` – Constructor without inherited call
- **Art:** Quick-Fix
- **Ändert Verhalten:** **je nach Fund** – gekennzeichnet nur `inherited;` (mit `override`): der überschriebene Elternkonstruktor läuft danach zuerst, mit denselben Argumenten; `inherited Create;` ist bedeutungsgleich, TObject.Create ist leer. Dann nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| en | de | fr |
|---|---|---|
| `Call %s first in the constructor` | `%s als Erstes im Konstruktor aufrufen` | `Appeler %s en premier dans le constructeur` |

**Platzhalter:** `%s` = die eingefügte Anweisung (`inherited Create` bzw. `inherited`).

**Wirkung:** Setzt den Aufruf als erste Anweisung in eine eigene Zeile hinter das `begin`, eingerückt wie die erste Anweisung (im Einzeiler `begin end;` inline). Die Form wählt die Hilfe: `inherited Create;`, wenn die Klasse direkt von TObject erbt oder von einem Vorfahren ohne eigenen Konstruktor (TPersistent, TInterfacedObject, TCustomAttribute); `inherited;`, wenn die Deklaration `override` trägt.

**Nicht angeboten**

- ein anderer Vorfahr ohne `override` – welcher Elternkonstruktor mit welchen Argumenten laufen soll, ist Entwurf
- `override` mit `overload`, mehrere Deklarationen
- Delegation an einen anderen Konstruktor (`Create..`, `Self.Create..` oder ein Konstruktor der Klasse bzw. eines Vorfahren in der Unit)
- eine in der Unit abstrakte geerbte Methode, `{$mode objfpc}` mit einem Vorfahren außerhalb der Unit, eine Direktive in der Vorfahrenliste
- eine erste Anweisung, die abbricht (`raise`, `Assert(False..)`), `inherited` irgendwo im Text der Routine
- `object`, Record, class helper, `class constructor`, asm, eine Direktive zwischen Kopf und `begin`

**Beispiel**

Vorher:

```pascal
type
  TFoo = class
    FX: Integer;
  public
    constructor Create;
  end;
implementation
constructor TFoo.Create;
begin
  FX := 0;
end;
```

Nachher:

```pascal
type
  TFoo = class
    FX: Integer;
  public
    constructor Create;
  end;
implementation
constructor TFoo.Create;
begin
  inherited Create;
  FX := 0;
end;
```

**Beispiel: mit override (gekennzeichnet)**

Vorher:

```pascal
type
  TFoo = class(TComponent)
  public
    constructor Create(A: Integer); override;
  end;
implementation
constructor TFoo.Create(A: Integer);
begin
  Run(A);
end;
```

Nachher:

```pascal
type
  TFoo = class(TComponent)
  public
    constructor Create(A: Integer); override;
  end;
implementation
constructor TFoo.Create(A: Integer);
begin
  inherited;
  Run(A);
end;
```

<a id="sca097"></a>

### SCA097 – inherited als Letztes im Destruktor aufrufen

- **Regel:** SCA097 `DestructorWithoutInherited` – Destructor without inherited call
- **Art:** Quick-Fix
- **Ändert Verhalten:** **je nach Fund** – gekennzeichnet außer bei direktem TObject-Erben (TObject.Destroy ist leer) – sonst läuft der Elterndestruktor danach und gibt die geerbten Felder frei. Dann nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| en | de | fr |
|---|---|---|
| `Call inherited last in the destructor` | `inherited als Letztes im Destruktor aufrufen` | `Appeler inherited en dernier dans le destructeur` |

**Wirkung:** Setzt `inherited;` in eine eigene Zeile direkt vor das `end` des Rumpfs, eingerückt wie die erste Anweisung; fehlt der letzten Anweisung das `;`, kommt es hinter ihr letztes Zeichen – auch hinter ein String-Literal. Nur mit `override` an der Deklaration.

**Nicht angeboten**

- kein `override` an der Deklaration (dann verdeckt Destroy die virtuelle Methode – eigentlich SCA149)
- eine letzte Anweisung `Exit`/`raise`/`Halt`/`Abort`/`goto` (auch `System.Exit`, `System.Halt`, `SysUtils.Abort`), `Exit` (auch `System.Exit`) oder `goto` auf irgendeiner Tiefe
- eine in der Unit abstrakte geerbte Methode, `{$mode objfpc}` mit einem Vorfahren außerhalb der Unit
- eine Direktive zwischen letzter Anweisung und `end`, `inherited` im Text der Routine
- `object`-Typ, `class destructor`, asm, eine Direktive zwischen Kopf und `begin`

**Beispiel**

Vorher:

```pascal
type
  TFoo = class(TComponent)
  public
    destructor Destroy; override;
  end;
implementation
destructor TFoo.Destroy;
begin
  FList.Free;
end;
```

Nachher:

```pascal
type
  TFoo = class(TComponent)
  public
    destructor Destroy; override;
  end;
implementation
destructor TFoo.Destroy;
begin
  FList.Free;
  inherited;
end;
```

<a id="sca098"></a>

### SCA098 – Bedingung direkt zuweisen

- **Regel:** SCA098 `RedundantConditional` – Redundant conditional assignment
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Assign the condition to %s directly` | `Bedingung direkt an %s zuweisen` | `Affecter directement la condition à %s` |

**Platzhalter:** `%s` = das Ziel der Zuweisung.

**Wirkung:** `if C then X := True else X := False` → `X := C`, die Gegenrichtung → `X := not C` (Klammern nur um ein zusammengesetztes C). Zeilenumbrüche in C bleiben, Ziel und Zuweisung wie im then-Zweig. Bedeutungsgleich.

**Nicht angeboten**

- X ist nicht als `Boolean` deklariert (bei Variant bekäme X den Wert der Bedingung); in der Gegenrichtung ist auch C nicht als Boolean bewiesen – ein Aufruf als C bleibt dort aus
- Ziel und Werte passen nicht zur Meldung, ein `;` vor dem `else`, ein Ausdruck hinter dem zweiten Wert (`X := False or Y`)
- ein Kommentar oder eine Direktive in der Anweisung, begin..end-Zweige, ein bedingter Ausdruck (Delphi 13)
- `with`-Block, zwei solche Anweisungen auf der Zeile

**Beispiel**

Vorher:

```pascal
  if R.Contains(P) then
    FActive := True
  else
    FActive := False;
```

Nachher:

```pascal
  FActive := R.Contains(P);
```

**Beispiel: Gegenrichtung**

Vorher:

```pascal
  if A > B then Done := False else Done := True;
```

Nachher:

```pascal
  Done := not (A > B);
```

<a id="sca099"></a>

### SCA099 – else-Zweig in begin..end setzen

- **Regel:** SCA099 `IfElseBegin` – Asymmetric begin/end in if/else
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Put the branch in begin..end` | `Zweig in begin..end setzen` | `Mettre la branche dans begin..end` |

**Wirkung:** Setzt die Anweisung hinter dem `else` des einen `end else` der Fundzeile in `begin..end` (Entscheid E7, bedeutungsgleich). `end else if` und `end else begin` zählen nicht mit. Die Form wie bei SCA101.

**Nicht angeboten**

- ein bedingter Ausdruck (Delphi 13: `X := if A then B else C`)
- eine Struktur, eine anonyme Methode oder eine Inline-Deklaration in der Anweisung
- eine Direktive vom entscheidenden Token bis zum Ende der Anweisung
- schon vorhandenes `begin`, leere Anweisung

**Beispiel**

Vorher:

```pascal
  if A then
  begin
    X;
  end else Y;
```

Nachher:

```pascal
  if A then
  begin
    X;
  end else
  begin
    Y;
  end;
```

<a id="sca101"></a>

### SCA101 – Zweig in begin..end setzen

- **Regel:** SCA101 `BeginEndRequired` – Branch without begin..end block
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Put the branch in begin..end` | `Zweig in begin..end setzen` | `Mettre la branche dans begin..end` |

**Wirkung:** Setzt die Anweisung hinter `then`/`else`/`do` an der Spalte aus der Meldung in `begin..end` (Entscheid E7, bedeutungsgleich). Hinter dem `else` eines case oder except kommt die ganze Anweisungsliste in den Block. Wem ein `else` gehört, entscheidet eine Rückwärtssuche wie der Compiler (dangling else). `begin` und `end` stehen in eigenen Zeilen, wenn die Anweisung auf der Zeile des Schlüsselworts steht oder allein auf ihren Zeilen, sonst inline.

**Nicht angeboten**

- ein bedingter Ausdruck (Delphi 13: `X := if A then B else C`)
- eine Struktur, eine anonyme Methode oder eine Inline-Deklaration in der Anweisung
- eine Deklaration hinter einem `;` vor dem `else` (Kopf einer anonymen Methode), `record` vor dem `else`
- eine Direktive vom entscheidenden Token bis zum Ende der Anweisung
- schon vorhandenes `begin`, leere Anweisung

**Beispiel**

Vorher:

```pascal
  if Active then DoStuff;
```

Nachher:

```pascal
  if Active then
  begin
    DoStuff;
  end;
```

<a id="sca109"></a>

### SCA109 – Sperre in try/finally freigeben

- **Regel:** SCA109 `LockWithoutTryFinally` – Lock acquired without try/finally release
- **Art:** Quick-Fix
- **Ändert Verhalten:** **ja** – die Sperre wird danach auch bei einer Ausnahme freigegeben – das ist der Fix. Nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| en | de | fr |
|---|---|---|
| `Release the lock %s in a try/finally block` | `Sperre %s in einem try/finally-Block freigeben` | `Libérer le verrou %s dans un bloc try/finally` |

**Platzhalter:** `%s` = die Sperre aus der Meldung (etwa `FLock`).

**Wirkung:** Derselbe Baustein wie bei SCA009, für Sperren: Enter/Leave, Acquire/Release, BeginWrite/EndWrite, `TMonitor.Enter(O)`/`TMonitor.Exit(O)`, `EnterCriticalSection(CS)`/`LeaveCriticalSection(CS)`. Die Freigabe bestimmt die Hilfe selbst: derselbe Empfänger bzw. dasselbe Argument, als Text gleich.

**Nicht angeboten**

- Exit im Bereich (auch `System.Exit`), eine zweite Sperre derselben Sperre, eine frühere Freigabe – auch in anderer Schreibweise (`Self.FLock.Leave`, `FLock.Release` nach `FLock.Enter`)
- `TMonitor.Enter(O, Timeout)` bzw. `TMonitor.TryEnter(O)` (eine Bedingung)
- ein umschließender Handler, der die Sperre freigibt
- die Sperre der Meldung steht nicht mehr auf der Zeile; die übrigen Sperren wie bei SCA009 (Direktive, goto, asm …)

**Beispiel**

Vorher:

```pascal
  FLock.Enter;
  DoWork;
  FLock.Leave;
```

Nachher:

```pascal
  FLock.Enter;
  try
    DoWork;
  finally
    FLock.Leave;
  end;
```

<a id="sca115"></a>

### SCA115 – http:// durch https:// ersetzen

- **Regel:** SCA115 `HttpInsteadOfHttps` – Plaintext HTTP URL
- **Art:** Quick-Fix
- **Ändert Verhalten:** **ja** – der Server muss https auf dem Standardport 443 mit gültigem Zertifikat anbieten. Nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| en | de | fr |
|---|---|---|
| `Use https:// instead of http://` | `https:// statt http:// verwenden` | `Utiliser https:// au lieu de http://` |

**Wirkung:** Ersetzt im gemeldeten String-Literal nur das Schema `http://` durch `https://`. Die Hilfe sucht das Literal über die URL aus der Meldung (der Fund nennt nur die Zeile).

**Nicht angeboten**

- die URL kommt auf der Zeile zweimal vor, ist Teil eines längeren Strings oder steht in einem Kommentar oder mehrzeiligen String
- Port, Benutzerangabe, IP-Adresse (auch private), IPv6, Platzhalter im Host, ein Host ohne Punkt, `localhost`, `*.local`, `*.internal`, `*.test`
- ein Namespace- oder Schema-Kennzeichen in der Adresse oder davor (`xmlns`, `schema`, `/ns/`, `w3.org`, `tempuri.org`, `purl.org` und ähnliche) – aus Vorsicht, auch wenn der Detektor solche Adressen als echte Endpunkte meldet

**Beispiel**

Vorher:

```pascal
  Url := 'http://api.example.org/v1/items';
```

Nachher:

```pascal
  Url := 'https://api.example.org/v1/items';
```

<a id="sca117"></a>

### SCA117 – Dokumentationsgerüst einfügen

- **Regel:** SCA117 `PublicMemberWithoutDoc` – Public member missing doc comment
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Insert a documentation skeleton` | `Dokumentationsgerüst einfügen` | `Insérer un squelette de documentation` |

**Wirkung:** Setzt über die Deklaration `/// <summary></summary>`, je Typparameter `/// <typeparam name="T"></typeparam>`, je Parameter `/// <param name="X"></param>` und bei einer Funktion `/// <returns></returns>` – eingerückt wie die Deklaration, die Platzhalter leer (ein `TODO` riefe SCA019). Bedeutungsgleich.

**Nicht angeboten**

- die Zeile beginnt in einem Kommentar, oder der Name passt nicht mehr zur Meldung
- darüber endet ein Kommentar über Zeilen (der Detektor hält dessen Schlusszeile für Code)
- über Attributzeilen steht schon XMLDoc (`///`) – sonst entstünde ein zweiter summary-Block
- eine Direktive im Kopf bis zu dessen `;`

**Beispiel**

Vorher:

```pascal
  TFoo = class
  public
    procedure Run;
  end;
```

Nachher:

```pascal
  TFoo = class
  public
    /// <summary></summary>
    procedure Run;
  end;
```

**Beispiel: Funktion mit Parametern**

Vorher:

```pascal
    function Find(const AId: Integer; out AUser: TUser): Boolean;
```

Nachher:

```pascal
    /// <summary></summary>
    /// <param name="AId"></param>
    /// <param name="AUser"></param>
    /// <returns></returns>
    function Find(const AId: Integer; out AUser: TUser): Boolean;
```

<a id="sca120"></a>

### SCA120 – Exception auslösen

- **Regel:** SCA120 `MissingRaise` – Exception constructed but never raised
- **Art:** Quick-Fix
- **Ändert Verhalten:** **ja** – die Exception wird danach ausgelöst, der Code dahinter läuft im Fehlerfall nicht mehr – das ist der Fix. Nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| en | de | fr |
|---|---|---|
| `Raise the exception` | `Exception auslösen` | `Lever l'exception` |

**Wirkung:** Setzt `raise ` vor `EFoo.Create(..)` (auch `CreateFmt` & Co., Argumente über Zeilen) – nur, wenn der Ausdruck eine ganze Anweisung ist.

**Nicht angeboten**

- keine ganze Anweisung: `X := EFoo.Create`, `EFoo.Create(..).Free`, im bedingten Ausdruck von Delphi 13
- im then-Zweig, wenn das `if` keine Anweisung beginnt
- andere Aufrufe als die Create-Varianten des Detektors (`Create`, `CreateFmt`, `CreateRes`, `CreateHelp` …)

**Beispiel**

Vorher:

```pascal
  EFoo.Create('x');
```

Nachher:

```pascal
  raise EFoo.Create('x');
```

<a id="sca121"></a>

### SCA121 – Result mit dem Anfangswert initialisieren

- **Regel:** SCA121 `RoutineResultUnassigned` – Function never assigns Result
- **Art:** Quick-Fix
- **Ändert Verhalten:** **ja** – Result ist danach definiert statt zufällig; spätere Zuweisungen gelten weiter. Nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| en | de | fr |
|---|---|---|
| `Initialize Result with %s` | `Result mit %s initialisieren` | `Initialiser Result avec %s` |

**Platzhalter:** `%s` = der eingesetzte Wert (`0`, `''`, `nil`, `System.Low(T)`, `Default(T)` …).

**Wirkung:** Setzt `Result := <Wert>;` als erste Anweisung. Der Wert folgt dem Rückgabetyp: `False`, `0`, `''`, `#0`, `nil`, `[]` bzw. `System.Low(T)` für eine schlichte Aufzählung der Unit (qualifiziert – kein anderes `Low` in Klasse, Vorfahr oder Unit verdeckt es), sonst `Default(T)` (Records, Typparameter, Unbekanntes, ein Typname, den die Unit auch in einer anderen Routine oder einem Klassenrumpf definiert, eine Unit mit eigenem Bezeichner `System`).

**Nicht angeboten**

- `Default(T)` in Dateien mit Spuren von Compilern vor Delphi 2009 (`jvcl.inc`, `VER150`, `CompilerVersion < 20` …)
- eine Zuweisung an Result bzw. den Funktionsnamen oder `Exit(Wert)` (auch `System.Exit(Wert)`) im Rumpf – auch im inaktiven `$IFDEF`-Zweig
- `Default(T)` in einer Datei ohne `implementation`-Teil bzw. ohne unit/program/library-Kopf (Skripte, Includes) – ein Literal (`False`, `0`, `''`, `nil` …) bietet die Hilfe dort an
- ein FPC-Modus ohne Result, `{$X-}`, asm, eine Direktive zwischen Kopf und `begin`
- ein Rückgabetyp, der kein einfacher Typbezeichner ist oder den die Funktion in ihrem Deklarationsteil selbst definiert (im Rumpf meinte der Name den lokalen Typ), eine freie Funktion ohne Signatur im Kopf, mehrere Deklarationen

**Beispiel**

Vorher:

```pascal
function F(A: Integer): Integer;
begin
  if A > 0 then
    Log('x');
end;
```

Nachher:

```pascal
function F(A: Integer): Integer;
begin
  Result := 0;
  if A > 0 then
    Log('x');
end;
```

<a id="sca122"></a>

### SCA122 – raise; statt raise E;

- **Regel:** SCA122 `ReRaiseException` – Re-raise of bound exception variable
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Use raise; to keep the original stack trace` | `raise; verwenden (Original-Stack-Trace bleibt)` | `Utiliser raise; (conserve la pile d'appels d'origine)` |

**Wirkung:** `raise E;` → `raise;` – dieselbe Exception, der Original-Stack-Trace bleibt erhalten.

**Nicht angeboten**

- rückwärts kommt vor dem eigenen Handler `on E: T do` ein `except`/`finally` (im except eines inneren try würfe `raise;` die innere Exception)
- der Handler einer anderen Variablen, eine anonyme Methode oder ein `with` dazwischen (der Name könnte ein Member sein)
- E wird zwischen Handler und raise neu zugewiesen (`E := EWrapped.Create(..)`): `raise E` wirft dann das neue Objekt, `raise;` die ursprüngliche Exception

**Beispiel**

Vorher:

```pascal
  try
    X;
  except
    on E: EFoo do
    begin
      Log(E.Message);
      raise E;
    end;
  end;
```

Nachher:

```pascal
  try
    X;
  except
    on E: EFoo do
    begin
      Log(E.Message);
      raise;
    end;
  end;
```

<a id="sca123"></a>

### SCA123 – Cast vor Free entfernen

- **Regel:** SCA123 `CastAndFree` – Type-cast immediately before Free / Destroy
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Remove the cast to %s before Free` | `Cast nach %s vor Free entfernen` | `Supprimer le transtypage en %s avant Free` |

**Platzhalter:** `%s` = der Cast-Typ (`TFoo`).

**Wirkung:** `TFoo(X).Free` → `X.Free` – nur, wenn X schon als genau `TFoo` deklariert ist: nur dann binden beide dasselbe `Free`.

**Nicht angeboten**

- X ist kein bloßer Bezeichner, steht im `with`-Block oder ist nicht als genau dieser Typ deklariert – ein anderer Typ kann `Free` verdecken, ein Pointer-Operand braucht den Cast zum Übersetzen
- andere Methoden als `Free`, Interface-Casts

**Beispiel**

Vorher:

```pascal
  TStringList(L).Free;
```

Nachher:

```pascal
  L.Free;
```

**Hinweis.** Im Beispiel ist `L` als `TStringList` deklariert.

<a id="sca126"></a>

### SCA126 – Assigned() statt Vergleich mit nil

- **Regel:** SCA126 `NilComparison` – Use Assigned() instead of `= nil` / `<> nil`
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Use Assigned() instead of comparing with nil` | `Assigned() statt Vergleich mit nil verwenden` | `Utiliser Assigned() au lieu de comparer avec nil` |

**Wirkung:** Schreibt alle nil-Vergleiche der einen Anweisung um, die auf der Fundzeile beginnt: `X = nil` → `not Assigned(X)`, `X <> nil` → `Assigned(X)`.

**Nicht angeboten**

- zwei solche Anweisungen auf der Zeile (mehrdeutig)
- ein Operand vom Typ String, Variant, Menge, Array oder Prozedur/Ereignis
- ein Operand ohne beweisbaren Typ – bewiesen sind Klassen, Interfaces und Zeiger der Unit und Klassen/Interfaces der Delphi-Quellen (E27); ein Kundentyp aus einer anderen Unit sperrt, ein Typ in einer generischen Klasse zählt mit seinem eigenen Namen (`TList<Integer>.TEmptyFunc` ist nicht TList)

**Beispiel**

Vorher:

```pascal
  if Obj = nil then Exit;
```

Nachher:

```pascal
  if not Assigned(Obj) then Exit;
```

**Beispiel: Vergleich mit `<> nil`**

Vorher:

```pascal
  while x <> nil do x := x.Next;
```

Nachher:

```pascal
  while Assigned(x) do x := x.Next;
```

<a id="sca139"></a>

### SCA139 – FreeAndNil statt Free

- **Regel:** SCA139 `FreeWithoutNil` – Free without subsequent nil-out
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Use FreeAndNil(%s)` | `FreeAndNil(%s) verwenden` | `Utiliser FreeAndNil(%s)` |

**Platzhalter:** `%s` = die Variable vor `.Free`.

**Wirkung:** `X.Free` → `FreeAndNil(X)`, auch hinter `then`/`else`/`do` (ersetzt wird nur der Ausdruck). Fehlt `System.SysUtils` in uses, kommt es mit.

**Nicht angeboten**

- X ist kein bloßer Bezeichner (`Self.X`, Pfad) oder nicht in der Unit deklariert; `with`-Block
- der Typ von X ist in der Unit – auch über einen Alias – ein `record`, `object`, `interface`, ein Zeiger oder ein eigener Typ (`= type ..`; `Free` ist dort eine eigene Methode bzw. die des Ziels), die Unit deklariert eine Routine `Free`, oder der Typ ist nach Konvention ein Zeiger einer anderen Unit (auch hinter einem Alias der Unit)
- X ist ein `const`- bzw. `constref`-Parameter (FPC: Fehler, Delphi bis 10.3: E2197; ab 10.4 würde nur die lokale Kopie nil)
- `Free` mit Klammern oder mehrfach auf der Zeile, `X.Destroy`

**Beispiel**

Vorher:

```pascal
    FList.Free;
```

Nachher:

```pascal
    FreeAndNil(FList);
```

<a id="sca147"></a>

### SCA147 – Ungenutzte private Methode löschen

- **Regel:** SCA147 `UnusedPrivateMethod` – Private method has no caller in the unit
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Delete unused private method %s` | `Ungenutzte private Methode %s löschen` | `Supprimer la méthode privée inutilisée %s` |

**Platzhalter:** `%s` = die Methode.

**Wirkung:** Löscht die Deklaration im Klassenrumpf (samt `///`-Doku) und die Implementierung samt Kommentarzeilen darüber, die die Methode beim Namen nennen. Bedeutungsgleich – der Name steht sonst nirgends im Code der Datei (rekursive Aufrufe im eigenen Rumpf zählen nicht).

**Nicht angeboten**

- nicht unter `private`/`strict private`; `virtual`/`dynamic`/`override`/`abstract`/`reintroduce`/`message`/`overload`, Konstruktor, Destruktor, Operator
- mehr als eine Deklaration oder Implementierung, keine Implementierung in der Datei, Property-Accessor
- der Name als String-Literal (`MethodAddress`), `{$RTTI}` in der Datei, ein Attribut an Methode oder Klasse
- `{$I}` im Klassenrumpf oder im implementation-Teil, ein Include davor, das den Namen nennt (Property-Accessor einer Nachfahrenklasse), nicht neben der Unit oder auf einem Netzpfad liegt, ein Interface der Klasse aus einer anderen Unit
- ein Marker-Kommentar (`noinspection`, TODO …) hinter der Deklaration oder dem `end;` der Implementierung – er gilt der Zeile dahinter –, oder ein `// noinspection` darüber, der auf sie zielt
- eine `.dfm`/`.fmx`/`.lfm` neben der Unit nennt den Namen (Bindung an ein Ereignis)
- die Unit liegt auf einem Netzpfad bzw. Netzlaufwerk – die Hilfe liest dort keine Formdatei (Menüaufbau im Hauptthread)

**Beispiel**

Vorher:

```pascal
type
  IFoo = interface
    procedure Run;
  end;
  TFoo = class(TInterfacedObject, IFoo)
  private
    procedure Dead;
  public
    procedure Run;
  end;
implementation
procedure TFoo.Dead;
begin
end;

procedure TFoo.Run;
begin
end;
```

Nachher:

```pascal
type
  IFoo = interface
    procedure Run;
  end;
  TFoo = class(TInterfacedObject, IFoo)
  private
  public
    procedure Run;
  end;
implementation
procedure TFoo.Run;
begin
end;
```

**Hinweis.** Der leere `private`-Abschnitt, der danach bleiben kann, meldet SCA087 – mit eigener Hilfe.

<a id="sca149"></a>

### SCA149 – override bzw. reintroduce an die Deklaration anfügen

- **Regel:** SCA149 `MissingOverride` – Method shadows a virtual parent method without `override`
- **Art:** Quick-Fix
- **Ändert Verhalten:** **je nach Fund** – gekennzeichnet nur `override`: der virtuelle Aufruf landet danach in dieser Methode; `reintroduce` ist bedeutungsgleich, nur die Warnung W1010 entfällt. Dann nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| en | de | fr |
|---|---|---|
| `Add "%s;" to the declaration` | `"%s;" an die Deklaration anfügen` | `Ajouter « %s; » à la déclaration` |

**Platzhalter:** `%s` = die Direktive (`override` bzw. `reintroduce`).

**Wirkung:** Nach dem Rat der Meldung: bei gleicher Signatur `override`, bei abweichender `reintroduce`. `reintroduce` kommt direkt hinter das `;` des Kopfs (vor vorhandene Direktiven), `override` hinter ein vorhandenes `overload` (sonst ebenfalls direkt hinter den Kopf) – die Reihenfolge der Sprachreferenz. Nie beide als Einträge: Strg+Alt+F ließe das gekennzeichnete `override` aus und deckte den Polymorphie-Fehler mit `reintroduce` still zu.

**Nicht angeboten**

- `override`, wenn die Methode der Elternklasse (in derselben Unit) nicht dieselbe Form hat: `class`, Parameter-Modifier, Typen und Defaults, Rückgabe, Aufrufkonvention
- `reintroduce` bei generischem Vorfahren (`class(TBase<Integer>)`)
- `override` bzw. `reintroduce` steht schon da, `override` neben `virtual`/`dynamic`/`static`/`message`/`inline`
- der Name passt nicht mehr, eine Property, eine Direktive im Kopf, ein unbekannter Meldungstext

**Beispiel**

Vorher:

```pascal
  TBase = class
  public
    procedure DoWork(const A: string; B: Integer = 0); virtual;
  end;
  TDerived = class(TBase)
  public
    procedure DoWork(const X: string; Y: Integer = 0);
  end;
```

Nachher:

```pascal
  TBase = class
  public
    procedure DoWork(const A: string; B: Integer = 0); virtual;
  end;
  TDerived = class(TBase)
  public
    procedure DoWork(const X: string; Y: Integer = 0); override;
  end;
```

**Beispiel: abweichende Signatur: reintroduce**

Vorher:

```pascal
  TBase = class
    procedure DoWork; virtual;
  end;
  TDerived = class(TBase)
    procedure DoWork(A: Integer);
  end;
```

Nachher:

```pascal
  TBase = class
    procedure DoWork; virtual;
  end;
  TDerived = class(TBase)
    procedure DoWork(A: Integer); reintroduce;
  end;
```

<a id="sca153"></a>

### SCA153 – Sperre in try/finally freigeben

- **Regel:** SCA153 `UnpairedLock` – Lock/Unlock pair without try/finally
- **Art:** Quick-Fix
- **Ändert Verhalten:** **ja** – die Sperre wird danach auch bei einer Ausnahme freigegeben – das ist der Fix. Nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| en | de | fr |
|---|---|---|
| `Release the lock %s in a try/finally block` | `Sperre %s in einem try/finally-Block freigeben` | `Libérer le verrou %s dans un bloc try/finally` |

**Platzhalter:** `%s` = die Sperre (etwa `FLocker`).

**Wirkung:** Derselbe Baustein wie bei SCA009, für Lock/UnLock und die übrigen Sperrpaare (Enter/Leave, Acquire/Release, `EnterCriticalSection`/`LeaveCriticalSection` …). Die Sperre der Meldung wird auf der Zeile nachgeprüft; die Freigabe bestimmt die Hilfe selbst (derselbe Empfänger, als Text gleich).

**Nicht angeboten**

- Exit im Bereich (auch `System.Exit`), eine zweite Sperre derselben Sperre, eine frühere Freigabe – auch in anderer Schreibweise
- `Lock(..)` mit Argumenten (keine Sperre), `TMonitor.Enter(O, Timeout)` bzw. `TMonitor.TryEnter(O)`
- ein umschließender Handler, der die Sperre freigibt
- die Sperre der Meldung steht nicht mehr auf der Zeile; die übrigen Sperren wie bei SCA009

**Beispiel**

Vorher:

```pascal
  FLocker.Lock;
  DoStuff;
  FLocker.UnLock;
```

Nachher:

```pascal
  FLocker.Lock;
  try
    DoStuff;
  finally
    FLocker.UnLock;
  end;
```

**Hinweis.** Ein Fund an SCA109 und SCA153 zugleich verschwindet mit der einen Hilfe aus beiden.

<a id="sca156"></a>

### SCA156 – Puffer in try/finally freigeben

- **Regel:** SCA156 `GetMemWithoutFreeMem` – GetMem / AllocMem without try/finally
- **Art:** Quick-Fix
- **Ändert Verhalten:** **ja** – `FreeMem` läuft danach auch bei einer Ausnahme und bei Exit – das ist der Fix. Nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| en | de | fr |
|---|---|---|
| `Free the buffer %s in a try/finally block` | `Puffer %s in einem try/finally-Block freigeben` | `Libérer le tampon %s dans un bloc try/finally` |

**Platzhalter:** `%s` = der Puffer.

**Wirkung:** Derselbe Baustein wie bei SCA009, für `GetMem(P, N)`, `P := AllocMem(N)`, `var P[: T] := AllocMem(N)` und `P := GetMem(N)` (FPC) mit `FreeMem(P[, N])` bzw. `FreeMemAndNil(P)`; ein direkt folgendes `P := nil;` geht mit ins `finally`. P muss eine lokale Variable der Routine sein.

**Nicht angeboten**

- P ist keine lokale Variable der Routine (Feld, globale Variable, Parameter) – nach dem `finally` kennte der Halter den freigegebenen Puffer, eine finalization bzw. ein Destruktor gäbe ihn ein zweites Mal frei
- `ReallocMem` (der Puffer bestand schon vorher), `Result := ..` (der Puffer verlässt die Routine)
- ein erstes Argument, das kein einfacher Bezeichner ist (`Pointer(P)`), ein qualifizierter Aufruf außer `System.`
- `Inc`/`Dec`/`GetMem`/`ReallocMem`/`@` auf P im Bereich, auch durch einen Cast; eine Freigabe in anderer Schreibweise
- eine Weitergabe ohne Ausstieg (`FBuf := P`, `Liste.Add(P)`); die übrigen Sperren wie bei SCA009

**Beispiel**

Vorher:

```pascal
procedure Run;
var
  P: Pointer;
begin
  GetMem(P, 1024);
  DoStuff(P);
  FreeMem(P);
end;
```

Nachher:

```pascal
procedure Run;
var
  P: Pointer;
begin
  GetMem(P, 1024);
  try
    DoStuff(P);
  finally
    FreeMem(P);
  end;
end;
```

<a id="sca159"></a>

### SCA159 – Leeren Ausnahme-Handler mit raise; versehen

- **Regel:** SCA159 `EmptyOnHandler` – Typed exception handler with empty body
- **Art:** Quick-Fix
- **Ändert Verhalten:** **ja** – die Ausnahme wird nicht mehr verschluckt, sondern an den Aufrufer weitergereicht – Programmablauf und äußere Handler prüfen. Nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| en | de | fr |
|---|---|---|
| `Add "raise;" to the empty exception handler` | `Dem leeren Ausnahme-Handler "raise;" hinzufügen` | `Ajouter "raise;" au gestionnaire d'exception vide` |

**Wirkung:** Ersetzt den leeren Rumpf eines `on E: T do`-Handlers durch `raise;`, die Ausnahme läuft dann weiter statt still verschluckt zu werden. Zwei Formen: `do ;` wird `do raise;`, `do begin end` wird `do begin raise; end` (begin und end auf eigenen Zeilen: `raise;` als eigene Zeile eine Stufe tiefer). Der Detektor bleibt unverändert und meldet auch Handler mit Kommentar; die Hilfe nicht.

**Nicht angeboten**

- Kommentar oder Direktive im Handler, davor oder dahinter auf der Zeile (ein Kommentar ist Absicht, auch wenn der Detektor ihn nicht sieht), oder ein Kommentar in der Zeile davor (er nennt meist die Absicht)
- mehr als ein `on`-Handler auf der Zeile, oder die Zeile ist verschoben, der Rumpf nicht mehr leer oder der Typ ein anderer als in der Meldung
- das `on` beginnt keinen Handler (davor weder `except` noch `;`), der Kopf steht nicht auf einer Zeile oder das `;` nicht auf der Zeile von `do`
- der Typ ist EAbort (stilles Abbruchsignal der VCL)

**Beispiel**

Vorher:

```pascal
try
  DoStuff;
except
  on E: EDatabaseError do ;
end;
```

Nachher:

```pascal
try
  DoStuff;
except
  on E: EDatabaseError do raise;
end;
```

**Hinweis.** Die Hilfe macht den Fund nicht „richtig“, sie macht das Verschlucken sichtbar: ob der Aufrufer die Ausnahme erwartet oder ein Log/Recovery gebraucht wird, entscheidet der Mensch.

<a id="sca161"></a>

### SCA161 – 32-Bit-Casts durch NativeInt ersetzen

- **Regel:** SCA161 `PointerSubtraction` – Pointer subtraction via 32-bit cast
- **Art:** Quick-Fix
- **Ändert Verhalten:** **ja** – Win32 bleibt gleich, unter Win64 ist der Abstand der volle Adressabstand; bei {$R+} kann die Zuweisung an ein Integer-Ziel ERangeError auslösen. Nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| en | de | fr |
|---|---|---|
| `Replace the 32-bit casts with NativeInt/NativeUInt` | `Die 32-Bit-Casts durch NativeInt/NativeUInt ersetzen` | `Remplacer les casts 32 bits par NativeInt/NativeUInt` |

**Wirkung:** Im Zeigerabzug `Cast(a) - Cast(b)` werden beide Cast-Wörter ersetzt: `Integer`/`LongInt` durch `NativeInt`, `Cardinal`/`LongWord` durch `NativeUInt`. Eine Ersetzung vom ersten Cast-Wort bis hinter den zweiten Cast; die Operanden bleiben. Die Meldung nennt keine Spalte: die Hilfe sucht das Muster auf den Code-Spalten der Zeile und hilft nur bei genau einem Treffer.

**Nicht angeboten**

- die beiden Casts haben verschiedene Vorzeichenart (`Cardinal` gegen `Integer`) – NativeInt oder NativeUInt wäre geraten
- mehrere Treffer auf der Zeile (die Hilfe weiß nicht, welchen der Detektor meldete)
- ein Operand ist eine Zahl oder kein einfacher Bezeichner, der Abzug geht mit einem weiteren 32-Bit-Cast weiter, oder ein Kommentar, String oder eine Direktive steht dazwischen
- das Cast-Wort steht hinter `.`, `&` oder `@`

**Beispiel**

Vorher:

```pascal
  Len := Integer(PEnd) - Integer(PStart);
```

Nachher:

```pascal
  Len := NativeInt(PEnd) - NativeInt(PStart);
```

**Hinweis.** Die Hilfe prüft nicht, ob die Operanden Zeiger sind – das hat der Detektor entschieden.

<a id="sca164"></a>

### SCA164 – Ungenutzte Routine löschen

- **Regel:** SCA164 `UnusedRoutine` – Top-level routine never called
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Delete unused routine %s` | `Ungenutzte Routine %s löschen` | `Supprimer la routine inutilisée %s` |

**Platzhalter:** `%s` = die Routine.

**Wirkung:** Löscht die freie Routine des implementation-Teils vom Kopf bis zu ihrem `end;` – samt lokaler Abschnitte und Routinen, der `///`-Doku- und Attributzeilen darüber, der Kommentarzeilen darüber, die die Routine beim Namen nennen, einer Leerzeile und einer `forward`-Deklaration. Bedeutungsgleich: die Hilfe prüft am Puffer neu, dass der Name sonst nirgends steht – nicht als Code (auch nicht in inaktiven Zweigen), in keinem String-Literal und in keiner Direktive.

**Nicht angeboten**

- Overloads, Methoden (das meldet SCA147), globale FPC-Operatoren
- `export`/`public`/`alias`/`external`/`forward`/`interrupt`, `{$L}`/`{$LINK}` in der Datei
- `{$I}` im implementation-Teil oder ein Include davor, das die Routine nennt, nicht neben der Unit liegt oder – wie die Unit selbst – auf einem Netzpfad (kein Plattenzugriff beim Menüaufbau)
- eine Direktive im Bereich außer ausgeglichenem `$IF..`/`$ENDIF` bzw. `$REGION`
- ein Marker-Kommentar (`noinspection`, TODO …) hinter dem `end;` bzw. der `forward`-Deklaration – er gilt der Zeile dahinter –, `// noinspection-file` in der Routine oder ein `// noinspection` über dem Kopf bzw. der `forward`-Deklaration, der auf die Routine zielt
- zwei Routinen auf einer Zeile, ein Kopf vor `implementation`, unsichere Grenzen (lokaler Klassentyp, `$IFDEF`-geteilter Rumpf)

**Beispiel**

Vorher:

```pascal
procedure Keep;
begin
end;

/// <summary>Helper</summary>
// Dead does X
procedure Dead(A: Integer);
var
  I: Integer;
  procedure Inner;
  begin
    Dead(I);
  end;
begin
  I := A;
  Inner;
end;

procedure Keep2;
begin
  Keep;
end;
```

Nachher:

```pascal
procedure Keep;
begin
end;

procedure Keep2;
begin
  Keep;
end;
```

<a id="sca168"></a>

### SCA168 – else-Zweig im case ergänzen

- **Regel:** SCA168 `DefaultCaseInCaseStatement` – case statement without else branch
- **Art:** Quick-Fix
- **Ändert Verhalten:**
  - Eintrag 1: nein
  - Eintrag 2: **ja** – ein nicht behandelter Wert löst danach eine Exception aus. Nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| Eintrag | en | de | fr |
|---|---|---|---|
| 1 | `Add an empty else branch` | `Leeren else-Zweig ergänzen` | `Ajouter une branche else vide` |
| 2 | `Add an else branch that raises an exception` | `else-Zweig mit Exception ergänzen` | `Ajouter une branche else qui lève une exception` |

**Wirkung (Eintrag 1):** Setzt ein leeres `else` vor das `end` des case – bedeutungsgleich (alle anderen Werte: nichts tun, wie bisher). Steht das `end` allein auf der Zeile, kommt das `else` in eine eigene Zeile mit derselben Einrückung; endet der letzte Arm nicht auf `;`, setzt die Hilfe es mit.

**Wirkung (Eintrag 2):** Setzt `else raise EInvalidOpException.Create('Unhandled case');` vor das `end`, die raise-Zeile eingerückt wie die Arme; fehlt `System.SysUtils`, kommt es in uses (in Dateien mit FPC-Weiche oder FPC-Modus als `SysUtils` – FPC 3.2.2 kennt die Klasse ebenfalls).

**Nicht angeboten**

- eine Direktive zwischen `case` und `end`
- schon ein `else` oder (FPC) `otherwise` hinter `;`
- ein case ohne Zweige, zwei `case` auf der Zeile
- ein case, das keine Anweisung ist: der Variantenteil eines Records (ein verschobener Fund) oder ein case ohne umschließenden Block (Fragment)
- eine offene `(` vor dem case mit einer Direktive dazwischen – ein Zweig kann sie offen lassen, die Lage ist unklar
- Eintrag 2: dieselben Sperren wie der erste Eintrag

**Beispiel (Eintrag 1)**

Vorher:

```pascal
  case X of
    1: A;
  end;
```

Nachher:

```pascal
  case X of
    1: A;
  else
  end;
```

**Beispiel (Eintrag 2)**

Vorher wie bei Eintrag 1.

Nachher:

```pascal
  case X of
    1: A;
  else
    raise EInvalidOpException.Create('Unhandled case');
  end;
```

<a id="sca179"></a>

### SCA179 – Grund zu [Ignore] hinzufügen

- **Regel:** SCA179 `AttributeIgnoreWithoutReason` – DUnitX [Ignore] attribute without reason argument
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Add a reason to [Ignore]` | `Grund zu [Ignore] hinzufügen` | `Ajouter une raison à [Ignore]` |

**Wirkung:** Macht aus `[Ignore]` oder `[Ignore()]` ein `[Ignore('reason')]`. Der Platzhalter `reason` ist danach durch den echten Grund (Ticket, Abhängigkeit, bekannte Einschränkung) zu ersetzen. Der Test wird mit und ohne Text gleich übersprungen; Schreibweise des Namens und Einrückung bleiben.

**Nicht angeboten**

- das Attribut steht in einer Gruppe (`[Ignore, Test]`) oder neben einem anderen Attribut auf derselben Zeile (`[Test][Ignore]`)
- die Klammern haben schon einen Inhalt (`[Ignore('kaputt')]`, `[Ignore(X)]`), oder das Attribut läuft über mehrere Zeilen
- hinter dem `]` oder im Attribut steht ein Kommentar oder Text; die Zeile ist verschoben, auskommentiert oder kein Attribut

**Beispiel**

Vorher:

```pascal
[Ignore]
procedure SomeTest;
```

Nachher:

```pascal
[Ignore('reason')]
procedure SomeTest;
```

**Hinweis.** Der Platzhalter `reason` muss durch den echten Grund ersetzt werden.

<a id="sca180"></a>

### SCA180 – Doppeltes Attribut entfernen

- **Regel:** SCA180 `AttributeDuplicate` – Same attribute applied twice to one member
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Remove the duplicate attribute` | `Doppeltes Attribut entfernen` | `Supprimer l'attribut en double` |

**Wirkung:** Löscht die Dublette eines Attributs: steht sie allein auf ihrer Zeile, die ganze Zeile; steht sie mit weiteren Attributen auf einer Zeile (`[A][A]`), nur die letzte gleiche Gruppe samt Trennzeichen. Gleich heißt: derselbe Name (Groß-/Kleinschreibung egal) und genau dieselben Argumente. Bedeutungsgleich.

**Nicht angeboten**

- die Argumente unterscheiden sich (`[Category('a')]` und `[Category('b')]`) – der Detektor meldet sie ohnehin nicht
- zwischen den Attributen oder dahinter steht Code, ein Kommentar oder eine Direktive
- ein Ziel-Attribut (`[Result: …]`, `[assembly: …]`), ein Attribut über mehrere Zeilen oder mit einer Klammer im String
- die Zeile ist verschoben, steht in einem Kommentar oder ist die letzte der Datei

**Beispiel**

Vorher:

```pascal
  public
    [Test]
    [Test]
    procedure Foo;
```

Nachher:

```pascal
  public
    [Test]
    procedure Foo;
```

<a id="sca181"></a>

### SCA181 – Dem Attribut [Category] einen Kategorienamen geben

- **Regel:** SCA181 `AttributeCategoryWithoutString` – DUnitX [Category] without category-name string
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Add a category name to the attribute` | `Dem Attribut einen Kategorienamen geben` | `Donner un nom de catégorie à l'attribut` |

**Wirkung:** Macht aus `[Category]` ein `[Category('category')]`. Der Platzhalter `category` macht den Code übersetzbar; den echten Namen der Kategorie setzt du selbst (die Hilfe kann ihn nicht kennen). Schreibweise und Leerzeichen vor dem `]` bleiben, ein Kommentar dahinter auch.

**Nicht angeboten**

- das Attribut hat schon ein Argument oder eine Liste (`[Category('x')]`, `[Category(Name)]`, `[Category()]`, `[Category, Test]`) - der Detektor meldet diese Formen nie, und eine Konstante könnte ein String sein
- hinter dem `]` steht weiterer Code (`[Category][Test]`) oder eine Compiler-Direktive
- vor dem Attribut steht kein Deklarationsende (`;`, `public`, `class`, ein anderes Attribut ...) - etwa ein Array-Index - oder eine Direktive liegt dazwischen
- die Zeile ist verschoben, auskommentiert oder liegt in einem Kommentar
- das Attribut steht auf seiner Zeile hinter einem anderen (`[Test][Category]`)

**Beispiel**

Vorher:

```pascal
    [Category]
    procedure Foo;
```

Nachher:

```pascal
    [Category('category')]
    procedure Foo;
```

**Hinweis.** Der Platzhalter `category` ist bewusst kein TODO (SCA019); ersetze ihn durch den Namen deiner Kategorie, etwa `Slow`.

<a id="sca183"></a>

### SCA183 – Leerzeile nach dem Attribut entfernen

- **Regel:** SCA183 `AttributeMisalignment` – Attribute with blank line before target member
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Remove the blank line after the attribute` | `Leerzeile nach dem Attribut entfernen` | `Supprimer la ligne vide après l'attribut` |

**Wirkung:** Löscht die Leerzeilen (nur Leerzeichen oder Tab) zwischen dem Attribut und der ersten Zeile mit Inhalt, einer Deklaration. Bedeutungsgleich.

**Nicht angeboten**

- ein Ziel-Attribut (`[assembly: …]`, `[Result: …]`) oder ein Attribut über mehrere Zeilen
- hinter dem `]` steht Text oder ein Kommentar
- hinter der Leerzeile folgt ein Kommentar, eine Direktive oder keine Deklaration (der Detektor prüft nur „irgendetwas“)
- das `[` ist ein Set-Literal, nicht der Anfang eines Attributs (davor fehlt ein Deklarationsende)

**Beispiel**

Vorher:

```pascal
  public
    [Test]

    procedure Foo;
```

Nachher:

```pascal
  public
    [Test]
    procedure Foo;
```

<a id="sca196"></a>

### SCA196 – Result zuerst initialisieren

- **Regel:** SCA196 `ManagedResultUninit` – Result of managed type is read before it is assigned
- **Art:** Quick-Fix
- **Ändert Verhalten:** **ja** – Result hängt danach nicht mehr am alten Inhalt der Zielvariable des Aufrufers. Nur über Menü oder Glühbirne, nie über Strg+Alt+F.

| en | de | fr |
|---|---|---|
| `Initialize Result first: %s` | `Result zuerst initialisieren: %s` | `Initialiser Result d'abord : %s` |

**Platzhalter:** `%s` = die eingefügte Anweisung (`Result := ''`, `Result := nil` bzw. `VarClear(Result)`).

**Wirkung:** Setzt als erste Anweisung `Result := '';` (string-Familie), `Result := nil;` (dynamische Arrays, TBytes, Interfaces) oder `VarClear(Result);` (Variant – fehlt Variants in uses, kommt `System.Variants` bzw. `Variants` mit). Die Hilfe sucht die innerste Routine um die gemeldete Lese-Zeile; Name und Rückgabetyp müssen zur Meldung passen.

**Nicht angeboten**

- ein Typ, der nicht als String, dynamisches Array, Interface oder Variant bewiesen ist (ein fremdes `IFoo` kann ein Record sein); deklariert die Unit den Namen selbst, gilt nur ihre Definition auf Unit-Ebene – eine Definition in einer Routine oder einem Klassenrumpf sperrt (auch in einem Include ohne unit-Kopf)
- `absolute Result`, asm, eine Direktive zwischen Kopf und `begin`, ein FPC-Modus ohne Result
- Name oder Typ passen nicht zur Meldung, auf der Zeile steht kein `Result` (Zeile verschoben)

**Beispiel**

Vorher:

```pascal
function Join(const A: array of string): string;
var
  I: Integer;
begin
  for I := 0 to High(A) do
    Result := Result + A[I];
end;
```

Nachher:

```pascal
function Join(const A: array of string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(A) do
    Result := Result + A[I];
end;
```

<a id="sca197"></a>

### SCA197 – Neue GUID einfügen

- **Regel:** SCA197 `InterfaceWithoutGuid` – Interface declared without a GUID
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Insert a new GUID` | `Neue GUID einfügen` | `Insérer un nouveau GUID` |

**Wirkung:** Setzt eine frisch erzeugte GUID `['{...}']` in eine eigene Zeile hinter den Interface-Kopf, eingerückt wie die Member (steht der Rumpf auf derselben Zeile, inline). Bedeutungsgleich – nur für eigene Interfaces.

**Nicht angeboten**

- generische Interfaces (eine GUID gälte für alle Ausprägungen), Vorwärtsdeklarationen
- ein `[` hinter dem Kopf (GUID oder Attribut)
- COM-Merkmale im Rumpf (`stdcall`/`safecall`/`dispid` …) oder `{$INTERFACES CORBA}`/`{$CALLING STDCALL}` in der Datei – ein COM-Import braucht die echte IID
- hinter dem Kopf beginnt kein Rumpf, oder eine Direktive steht vom Kopf bis zum ersten Member

**Beispiel**

Vorher:

```pascal
type
  IFoo = interface
    procedure Run;
  end;
```

Nachher:

```pascal
type
  IFoo = interface
    ['{11111111-2222-3333-4444-555555555555}']
    procedure Run;
  end;
```

**Hinweis.** Im Beispiel steht eine feste GUID wie im Test; die Hilfe erzeugt jedes Mal eine neue.

## Weitere Code-Aktionen

Rezepte des Anbieters (`uRdxProvider`), in der Reihenfolge des Menüs.

<a id="rezept-showspan"></a>

### Stelle zeigen

- **Regel:** jede Regel mit Anker im Regelkatalog (Feld `anchor`), wenn sich die Anweisung des Funds beschreiben lässt
- **Art:** Navigation
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Show location` | `Stelle zeigen` | `Afficher l'emplacement` |

**Wirkung:** Markiert im Editor den exakten Bereich der Anweisung, die der Fund meint.

**Nicht angeboten**

- die Anweisung lässt sich nicht beschreiben (kein Anker, Zeile verschoben)
- ausgegraut: der Bereich liegt hinter Spalte 32767 bzw. hinter 32766 Bytes seiner Zeile (die Editor-Markierung rechnet in SmallInt)

**Beispiel:** kein Umbau – die Aktion markiert nur.

<a id="rezept-formatcall"></a>

### Format() aus Verkettung bilden

- **Regel:** SCA044 `ConcatToFormat` – Long string concat - prefer Format() (Katalog: fixMode `auto`)
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Build Format() from concatenation` | `Format() aus Verkettung bilden` | `Construire Format() à partir de la concaténation` |

**Wirkung:** Ersetzt die Terme einer `+`-Kette durch `Format('...%s...', [..])` nach der Kompilat-Regel: `IntToStr(n)` mit bekanntem Ganzzahltyp wird `%d`/`%u` mit `n`, ein Char-Operand bekannten Typs geht als `string(c)` hinein, `X := X + ...` wird `X := X + Format(...)`. Kein Literal im Formatstring trägt mehr als 255 Zeichen (bis Delphi 11 E2056; vorsichtig nach UTF-8 gezählt): ein längerer Teil wird mit ` + ` geteilt, der Wert bleibt. Fehlt `System.SysUtils`, kommt es als zweite Ersetzung in die uses-Klausel (eine sortierte Liste bleibt sortiert); der Hinweis des Eintrags sagt dann `+ uses System.SysUtils`.

**Nicht angeboten**

- SQL-Literale in der Kette, ein Kommentar oder eine Direktive im ersetzten Bereich
- Variant-Anzeichen (`.Value`, `FieldValues`, als Variant deklariert …), Zahl-Operanden und Aufrufe mit Zahl-Ergebnis
- ein Zeiger am Kettenanfang (`P + N + '.txt'` mit `P: PChar` bzw. `PChar(S)` – Delphi rechnet zuerst Zeiger-Arithmetik); hinter `X +` beim Selbst-Anhängen nicht, dort ist X der Anfang
- Nicht-Unicode-Strings als Ziel oder Operand (`AnsiString`, `RawByteString`, `UTF8String`, `ShortString`), ein `AnsiChar`-Operand
- die Zeile trägt nicht mehr Ziel und `+`-Zahl des Funds (Zeile verschoben)
- `System.SysUtils` fehlt und die uses-Klausel trägt Direktiven oder liegt in einem `$IFDEF`-Zweig

**Beispiel**

Vorher:

```pascal
  Text := Marker + 'id:' + IntToStr(Id) + ' Milli: ' + IntToStr(n);
```

Nachher:

```pascal
  Text := Format('%sid:%d Milli: %d', [Marker, Id, n]);
```

**Hinweis.** Im Beispiel sind `Id` und `n` als `Integer` deklariert, `Marker` als `string`. Fehlt `System.SysUtils`, wird aus `uses System.Classes, Vcl.Forms;` in derselben Aktion `uses System.Classes, System.SysUtils, Vcl.Forms;` (ein Undo-Schritt).

<a id="rezept-sqltemplate"></a>

### Parametrisierte SQL-Vorlage in die Zwischenablage

- **Regel:** SCA003 `SQLInjection` – SQL string built via concatenation (Katalog: fixMode `assisted`)
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Copy parameterized template to clipboard` | `Parametrisierte Vorlage in die Zwischenablage` | `Copier le modèle paramétré dans le presse-papiers` |

**Wirkung:** Baut aus der SQL-Verkettung eine Vorlage mit Parametern und legt sie in die Zwischenablage – schreibt nie in den Editor. Parameter wird ein Operand nur dort, wo SQL einen Wert erwartet (hinter `=`, `<>`, `<`, `>`, `LIKE`, `BETWEEN`/`AND`, in `IN (..)`/`VALUES (..)`); die Namen kommen aus dem Operanden (`FId` → `:Id`), Konstanten behalten ihren Namen. `QuotedStr(x)`, `AnsiQuotedStr(x, '''')` und das Verdoppeln der Apostrophe in einem SQL-String (`StringReplace(x, '''', '''''', [rfReplaceAll])`, auch `Trim(x).Replace('''', '''''')`) binden `x`; ein SQL-Text über 255 Zeichen wird mit ` + ` geteilt. Ziel Query-Objekt: `ParamByName`-Zeilen (bei ADO `Parameters.ParamByName`); `ExecSQL` einer FireDAC-Verbindung: die Überladung mit Werten.

**Nicht angeboten**

- DDL/DCL und prozedurale Blöcke (CREATE, ALTER, DROP, GRANT, BEGIN, EXECUTE BLOCK …) – für den Rest des Texts, auch hinter `;`
- Bezeichner-Positionen (FROM, INTO, ORDER BY, Spalten- und SELECT-Liste), ein nackter Operand in einer Join-Bedingung, ein Operand, der an einem Bezeichner klebt
- eine Anweisung, die nicht mit DML oder einer Klausel beginnt, ein `?` im Text, eine Kette ohne SQL-Literal, nur Konstanten
- ein Aufruf, der den Text ohne Parameterkanal ausführt
- ein schon maskierter Wert (`EscapeString(x)`, `QuotedStr` in einem SQL-String, `AnsiQuotedStr(x, '"')`, `x.QuotedString` auch ohne Klammern, ein Literal mit Apostroph wie in `StringReplace(x, '''', '''''', [])` ohne `rfReplaceAll`) – der Parameter trüge die Maskierung in die Daten
- eine Konstante der Unit gilt in einer Methode einer Klasse mit Vorfahr von außerhalb (`class(TForm)`) nicht als bewiesen – ein geerbtes Member gleichen Namens bindet vorher

**Beispiel**

Vorher:

```pascal
  Obj.SQL.Text := 'SELECT * FROM t WHERE a = ' + Marker + ' AND b = ' + Tag;
```

In der Zwischenablage:

```pascal
  Obj.SQL.Text := 'SELECT * FROM t WHERE a = :Marker AND b = :Tag';
  Obj.ParamByName('Marker').Value := Marker;
  Obj.ParamByName('Tag').Value := Tag;
```

<a id="rezept-usesactions"></a>

### uses-Einträge qualifizieren

- **Regel:** jeder Fund auf einer Zeile einer uses-Klausel (auch der Programm-Klausel einer .dpr/.lpr), etwa SCA142 UnsortedUses oder SCA007 UnusedUses
- **Art:** Refactoring
- **Ändert Verhalten:** nein

| Eintrag | en | de | fr |
|---|---|---|---|
| 1 | `uses: %s -> %s` | `uses: %s -> %s` *(fester Text)* | `uses: %s -> %s` *(fester Text)* |
| 2 | `uses: qualify all %d entries` | `uses: alle %d Einträge qualifizieren` | `uses : qualifier les %d entrées` |
| 3 (nur ausgegraut) | `uses: qualify entries` | `uses: Einträge qualifizieren` | `uses : qualifier les entrées` |
| 4 (nur ausgegraut) | `uses: qualify %s` | `uses: %s qualifizieren` | `uses : qualifier %s` |

**Platzhalter:** in `uses: %s -> %s` der Kurzname und der qualifizierte Name, in `uses: qualify %s` der Kurzname; `%d` = die Zahl der Einträge.

**Wirkung:** Qualifiziert einen Eintrag der uses-Klausel nach der Scope-Tabelle (`Windows` → `Winapi.Windows`), dazu „alle n Einträge“ der Zeile. Ein Umbau an der Stelle, keine Hilfe zum Fund: nie in der Glühbirne, je Menü nur einmal, auch wenn mehrere Funde auf der Zeile stehen.

**Nicht angeboten**

- ausgegraut: Scope-Tabelle nicht geladen (`unitscopes.txt`)
- ausgegraut: Compiler-Direktiven in der uses-Klausel oder die Klausel in einem `$IFDEF`-Zweig, eine Datei mit FPC-Weiche oder FPC-Modus (FPC 3.2 kennt keine Unit-Scopes)
- eine gleichnamige Projekt-Unit (Datei neben der Unit, Modul eines Projekts der Gruppe, Datei im Unit-Suchpfad der aktiven Konfiguration und Plattform, jede Ebene bis Base einzeln – `Base_Win32` eingeschlossen), ein mehrdeutiger Name ohne erkennbares Rahmenwerk (Forms: VCL/FMX)
- ausgegraut: ein Verzeichnis neben der Unit oder im Unit-Suchpfad liegt auf einem Netzpfad (UNC, Netzlaufwerk) – reDelphix liest dort im Hauptthread nicht, ob das Projekt eine gleichnamige Unit hat, bleibt offen
- ausgegraut: der Eintrag (bzw. „alle“) machte eine sortierte Klausel unsortiert – sonst käme ein neuer SCA142-Fund

**Beispiel**

Vorher:

```pascal
uses Windows, Classes, Foo;
```

Nachher:

```pascal
uses Winapi.Windows, Classes, Foo;
```

**Beispiel: alle 2 Einträge qualifizieren**

Vorher:

```pascal
uses Windows, Classes, Foo;
```

Nachher:

```pascal
uses Winapi.Windows, System.Classes, Foo;
```

**Hinweis.** `Foo` kennt die Scope-Tabelle nicht – der Eintrag bleibt.

<a id="rezept-removemarker"></a>

### Wirkungslosen Unterdrück-Marker entfernen

- **Regel:** SCA165 `UnusedSuppression` – Unused noinspection marker
- **Art:** Quick-Fix
- **Ändert Verhalten:** nein

| en | de | fr |
|---|---|---|
| `Remove ineffective suppression marker` | `Wirkungslosen Unterdrück-Marker entfernen` | `Retirer le marqueur de suppression sans effet` |

**Wirkung:** Entfernt einen `// noinspection`-Marker, der nichts unterdrückt: steht er allein auf der Zeile, die ganze Zeile; hinter Code nur den Kommentar.

**Nicht angeboten**

- ausgegraut: der Marker nennt mehr als eine Art oder lautet `All` – SCA165 kommt auch, wenn nur die Arten des aktiven Scan-Profils nichts unterdrückt haben
- ausgegraut: die nächste nicht-leere Zeile hinter dem Marker ist eine `//`-Kommentarzeile vor dem Code (etwa ein TODO, bei gestapelten Markern die Markerzeile darunter), und seine Art kann auf einer Kommentarzeile gemeldet werden (TodoComment, CommentedOutCode, NoSonarMarker, TabulationCharacter, TooLongLine, TrailingWhitespace, CustomRule, SCA185–SCA193, UnusedSuppression) – SCA165 prüft nur die Code-Zeile, auf der Kommentarzeile wirkt der Marker vielleicht doch; ein Marker einer Code-Art mit Warum-Kommentar darunter wird entfernt
- der Marker liegt in einem Blockkommentar
- ein `; noinspection`-Marker einer Konfigurationsdatei (.ini) – reDelphix liest nur Pascal-Quelltext

**Beispiel**

Vorher:

```pascal
  // noinspection NilDeref
  L := TStringList.Create;
```

Nachher:

```pascal
  L := TStringList.Create;
```

**Beispiel: Marker hinter Code**

Vorher:

```pascal
  U := 'http://x';   // noinspection HttpInsteadOfHttps
```

Nachher:

```pascal
  U := 'http://x';
```

<a id="rezept-suppress"></a>

### Hier bzw. in dieser Datei unterdrücken

- **Regel:** alle Regeln außer SCA165 `UnusedSuppression` – Fund in Pascal-Quelltext (`.pas`, `.dpr`, `.dpk`, `.inc`, `.lpr`, `.pp`)
- **Art:** Unterdrücken
- **Ändert Verhalten:** nein

| Eintrag | en | de | fr |
|---|---|---|---|
| 1 | `Suppress here (// noinspection %s)` | `Hier unterdrücken (// noinspection %s)` | `Masquer ici (// noinspection %s)` |
| 2 | `Suppress in this file (// noinspection-file %s)` | `In dieser Datei unterdrücken (// noinspection-file %s)` | `Masquer dans ce fichier (// noinspection-file %s)` |

**Platzhalter:** `%s` = die Fundart (Kind-Name, etwa `MemoryLeak`).

**Wirkung:** „Hier“ setzt `// noinspection <Art>` in eine eigene Zeile über die Fundzeile, eingerückt wie sie; „In dieser Datei“ setzt `// noinspection-file <Art>` hinter die Kopfanweisung der Unit. Ein vorhandener Marker bekommt die Art dazu, außer er lautet `All`/`*` (dann eine eigene Zeile). Auf einer `//`-Kommentarzeile (etwa einem TODO) bekommt der Marker, der sie schon trägt, die Art auch über Leerzeilen hinweg – eine neue Zeile dazwischen nähme ihm sein Ziel.

**Nicht angeboten**

- die Fundzeile liegt in einem Blockkommentar oder mehrzeiligen String
- die Art steht schon im Marker
- „Hier“ auf einer `//`-Kommentarzeile, die ein Marker trägt, der sich nicht erweitern lässt (`All`, Marker hinter Code) und eine Art nennt, die auf Kommentarzeilen gemeldet wird
- SCA165 selbst – einen wirkungslosen Marker entfernt „Wirkungslosen Unterdrück-Marker entfernen“
- Funde außerhalb von Pascal-Quelltext (.dfm, Konfiguration) – dort setzt das Plugin den Marker selbst (Strg+Alt+S)

**Beispiel**

Vorher:

```pascal
procedure P;
begin
  L := TStringList.Create;
end;
```

Nachher:

```pascal
procedure P;
begin
  // noinspection MemoryLeak
  L := TStringList.Create;
end;
```

**Beispiel: In dieser Datei unterdrücken (Art MagicNumber)**

Vorher:

```pascal
unit u;
interface
```

Nachher:

```pascal
unit u;
// noinspection-file MagicNumber
interface
```

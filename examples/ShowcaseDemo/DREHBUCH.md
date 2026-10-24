# Drehbuch: SCA und reDelphix am ShowcaseDemo

Video-Skript für das Projekt `examples/ShowcaseDemo` (englischer Überblick:
[README.md](README.md)). Ablauf: Installation, Projekt öffnen, Scan, dann
Datei für Datei die Funde und die Code-Aktionen von reDelphix. Jede der 106
Code-Aktionen (92 Quick-Fixes der Tabelle, ihre 8 zweiten Einträge, 6
Aktionen des Anbieters) ist mindestens an einer Stelle angeboten – die
Tabelle am Ende nennt sie.

Zeilennummern gelten für den unveränderten Stand (`git checkout
examples/ShowcaseDemo`). Sie verschieben sich mit jeder Hilfe, die Zeilen
einfügt oder löscht – darum die Grundregel unten.

## Grundregeln für die Aufnahme

- **Von unten nach oben arbeiten**, je Datei in der Reihenfolge dieses
  Skripts. Eine Hilfe weiter unten verschiebt die Zeilen darüber nicht.
- **Nach jeder Hilfe, die Zeilen einfügt oder löscht, die Datei neu
  analysieren** (Editor-Kontextmenü „Aktuelle Datei analysieren“ oder neu
  scannen). Sonst lehnt reDelphix die nächste Hilfe mit „Zeile verschoben“
  ab – das ist gewollt: jede Hilfe prüft den Puffer gegen den Text, auf dem
  der Fund beruht. Mit „(neu analysieren)“ markierte Schritte brauchen das
  sicher.
- **Glühbirne** (Caret auf der Fundzeile) zeigt nur ausführbare Hilfen.
  Das **Kontextmenü** im Editor oder im Dock-Grid zeigt auch gesperrte
  Einträge ausgegraut, der Kopf des Grunds steht in Klammern hinter dem
  Menütext, der ganze Grund im Hinweis (Statuszeile) – gut für eine
  Szene „warum hier nicht?“.
- **Menütext** ohne Zusatz heißt bedeutungsgleich (das steht nur im
  Hinweis); **„(ändert Verhalten)“** am Menütext kennzeichnet eine Hilfe,
  die das Verhalten ändert. Diese Hilfen laufen nur per Menü oder
  Glühbirne, nie über **Strg+Alt+F** (erste verfügbare, bedeutungsgleiche
  Hilfe im Dock-Grid). Die volle Erklärung – was sich ändert – steht im
  Hinweis des Menüpunkts.
- **Unterdrücken** steht in einem Untermenü am Ende des Menüs („Hier
  unterdrücken“ / „In dieser Datei unterdrücken“ je Fund). **Strg+Alt+S**
  unterdrückt direkt.
- Zurücksetzen jederzeit: `git checkout examples/ShowcaseDemo`.

## Szene 0: Vorbereitung (vor der Aufnahme)

1. Delphi 12 Athens (Win32-IDE) oder Delphi 13 Florence.
2. SCA als **Plugin-Variante B** und reDelphix installieren: Projektgruppe
   `StaticCodeAnalyser.d12.groupproj` öffnen, Gruppe erzeugen, dann
   `StaticCodeAnalyser.IDE.d12` und `reDelphix.d12` im Projekt-Manager
   **Installieren** (Details: `reDelphix/README.md`, Abschnitte
   „Voraussetzungen in der IDE“ und „Bauen und installieren“). Nicht den
   Monolithen `StaticCodeAnalyser.Plugin.d12` – neben ihm lädt reDelphix
   nicht.
3. `%APPDATA%\StaticCodeAnalyser\analyser.ini`, Abschnitt `[Rules]`:

   ```ini
   Profile=strict
   IdeProfile=strict
   MinSeverity=hint
   IdeMinSeverity=hint
   MinConfidence=low
   ```

   `strict` bringt die Konventionsregeln, die `default` auslässt
   (SCA007, SCA099, SCA101, SCA117, SCA126). `MinConfidence=low` braucht es
   für die sechs Formatregeln SCA061, SCA063, SCA064, SCA069, SCA076,
   SCA079 – die Engine meldet sie mit niedriger Konfidenz. Erwartung:
   **214 Funde** (mit `MinConfidence=medium` 164; Profil `default`: 188
   bzw. 138).
4. Zurücksetzen: `git checkout examples/ShowcaseDemo`, `__history`
   löschen.
5. Probelauf: einmal bauen (Win32, Debug). Erwartet: übersetzt mit
   Warnungen (W1010 „verdeckt virtuelle Methode“, W1035 „Rückgabewert
   undefiniert“, W1000 „Resume ist veraltet“, Hinweise zu ungenutzten
   Variablen). Das überzählige Komma für SCA068 steht im spät gebundenen
   Variant-Aufruf `uLegacyImport.pas:122` (`AExcel.Workbooks.Open(AFileName,);`):
   nur dort übersetzt Delphi es (leeres Argument = weggelassener optionaler
   Parameter); in einem normalen Aufruf wäre es E2034 „Zu viele Parameter“.

## Szene 1: Projekt öffnen und kompilieren

- `examples/ShowcaseDemo/ShowcaseDemo.dproj` öffnen, Projekt-Manager zeigen:
  fünf Units, ein Formular.
- Kurz bauen: „Der Compiler ist zufrieden – ein paar Warnungen, sonst nichts.
  Schauen wir, was der Static Code Analyser sieht.“

## Szene 2: Scan und Überblick

- Analyse für das Projekt starten. Dock-Fenster: **214 Funde**.
- Nach Schwere sortieren, die Error-Kacheln zeigen. Highlights **ohne**
  Code-Aktion (kurz anklicken, Fundtext vorlesen, von Hand erklären):
  - `uPriceCalculator.pas:157` **SCA202** `not AQuantity = 0` – bindet
    als `(not AQuantity) = 0`; gemeint war `AQuantity <> 0`.
  - `uPriceCalculator.pas:189` **SCA005** Format mit 3 Platzhaltern und
    2 Argumenten – zur Laufzeit EConvertError.
  - `uPriceCalculator.pas:188` **SCA203** Schleife läuft bis `Count` statt
    `Count - 1` (die Hilfe kommt in Szene 4).
  - `uOrderForm.dfm:79` **SCA033** und `uOrderForm.pas:79` **SCA003**: SQL
    aus `Edit1.Text` zusammengesetzt.
  - `uLegacyImport.pas:40` **SCA188** Trojan Source: ein unsichtbares
    Bidi-Steuerzeichen im Kommentar.
  - `uOrderRepository.pas:126` **SCA004** Passwort im Quelltext,
    `:127` **SCA200** feste IP-Adresse.
  - `uOrderForm.pas:131` **SCA008** `Order` ist nil und wird dereferenziert
    (dazu `:130` **SCA019** TODO).
  - `uOrderForm.dfm:101` **SCA026** Klartext-Passwort
    `Password=Sommer2024!` in `FDConnection1.Params.Strings` (Error).
  - `uPriceCalculator.pas:108` **SCA010** Division durch einen Parameter
    ohne Prüfung auf 0.
  - DFM: **SCA024** Standardnamen (`Button1`, `Edit1` …), **SCA039**
    Datenbank-Komponenten auf dem Formular, **SCA043** Aktion und OnClick
    zugleich an `btnRefresh`, **SCA029** `lvOrdersDblClick` ist an kein
    Ereignis gebunden – der Doppelklick tut nichts.
- Überleitung: „Für die meisten Funde hat reDelphix eine Code-Aktion – die
  Glühbirne im Editor.“

## Szene 3: uLegacyImport.pas – Altcode aufräumen

Die Unit ist absichtlich „alt“: Tabs, `Begin`/`End`, `goto`, unqualifizierte
uses, Zeichen aus einer Webseite kopiert. Von unten nach oben:

| # | Zeile | Fund | Aktion (Menütext) | Erwartung danach |
|---:|---:|---|---|---|
| 1 | 125 | SCA088 | begin durch initialization ersetzen | `initialization` statt `begin` vor `end.` |
| 2 | 115 | SCA154 | SizeOf(Integer) statt der Zeigergröße verwenden (ändert Verhalten) | `Move(ASource^, ATarget^, SizeOf(Integer))` |
| 3 | 110 | SCA161 | Die 32-Bit-Casts durch NativeInt/NativeUInt ersetzen (ändert Verhalten) | `NativeInt(PEnd) - NativeInt(PStart)` – richtig auch unter Win64 |
| 4 | 108 | SCA148 | **Hier unterdrücken** (Strg+Alt+S) statt Hilfe; im selben Menü steht „In dieser Datei unterdrücken“ | Zeile `// noinspection CanBeClassMethod` darüber; Fund weg |
| 5 | 122 | SCA068 | Überzähliges Komma entfernen – im Dock-Grid per **Strg+Alt+F** | `AExcel.Workbooks.Open(AFileName);` |
| 6 | 95–97 | SCA070 | Auskommentierten Code löschen | der `{ if Price = 0 ... }`-Block ist weg (neu analysieren) |
| 7 | 93 | SCA014 | Lokale Konstante für 20 einführen | `const MagicNr01 = 20;` vor dem `if` (neu analysieren) |
| 8 | 81 | SCA193 | Namen in ASCII-Buchstaben schreiben: Amount | alle vier `Amоunt` (kyrillisches о) heißen `Amount` |
| 9 | 73 | SCA123 | Cast nach TStringList vor Free entfernen | `Lines.Free;` |
| 10 | 68 | SCA099 | Zweig in begin..end setzen | `end else begin Inc(FStats.Skipped); end;` (neu analysieren) |
| 11 | 64 | SCA063 | Leerraum am Zeilenende entfernen | – |
| 12 | 64 | SCA061 | Tabulatoren dieser Zeile durch Leerzeichen ersetzen | Einrückung mit Leerzeichen |
| 13 | 56 | SCA060 | "goto" durch Exit ersetzen | `then Exit;` – Marke `Done:` bleibt (Delphi meldet sie danach als ungenutzt) |
| 14 | 56 | SCA101 | Zweig in begin..end setzen | `if not FileExists(..) then begin Exit; end;` (neu analysieren) |
| 15 | 46, 43 | SCA064 | End klein schreiben / Begin klein schreiben | `end;` / `begin` |
| 16 | 40 | SCA188 | Bidi-Steuerzeichen entfernen (in Strings als #$-Code) | Kommentar ohne U+202E |
| 17 | 38 | SCA192 | Unsichtbare Zeichen entfernen (in Strings als #$-Code) | `'sku;quantity;price'#$200B` – jetzt sichtbar: der Kopfvergleich konnte nie stimmen |
| 18 | 35 | SCA071 | Schlüsselwort an Spalte 1 setzen | `implementation` an Spalte 1 |
| 19 | 28, 27 | SCA117 | Dokumentationsgerüst einfügen | `/// <summary></summary>` und `/// <param ...>` über `Stats` bzw. `ImportFile` (neu analysieren) |
| 20 | 9 | SCA007 | Unit Contnrs aus uses entfernen (ändert Verhalten) | `Contnrs` ist weg |
| 21 | 9 | Refactoring | uses: Windows -> Winapi.Windows, danach „uses: alle … Einträge qualifizieren“ | `Winapi.Windows, System.SysUtils, System.Classes` |

Hinweis zu 21: die uses-Aktionen stehen nur im Kontextmenü (Refactoring,
nicht in der Glühbirne); vor Schritt 20 sind es vier Einträge.

Hinweis zu 5: `OpenInExcel` (Zeile 120) ruft niemand auf, dazu meldet
SCA164 „Ungenutzte Routine OpenInExcel löschen“. Stehen lassen – die Hilfe
löschte die Routine samt der SCA068-Stelle; SCA164 zeigt Szene 5.

## Szene 4: uPriceCalculator.pas – Rechenfehler und Stilfragen

| # | Zeile | Fund | Aktion | Erwartung danach |
|---:|---:|---|---|---|
| 1 | 342 | SCA080 | Überflüssiges Exit entfernen | `Exit;` vor dem `end` von `Reset` ist weg; die Reihenfolge zu Schritt 2 ist egal, der Fund bleibt auch mit `initialization` dahinter |
| 2 | 333 | SCA167 | Randomize im initialization-Abschnitt aufrufen (ändert Verhalten) | neuer Abschnitt `initialization Randomize;` vor `end.` |
| 3 | 319 | SCA122 | raise; verwenden (Original-Stack-Trace bleibt) | `raise;` |
| 4 | 302 | SCA002 | raise; in den leeren except-Block einfügen (ändert Verhalten) | `except raise; end;` (neu analysieren) |
| 5 | 301 | SCA128 | FormatSettings ausdrücklich übergeben | `StrToFloat(AText, FormatSettings)` |
| 6 | 293 | SCA159 | Dem leeren Ausnahme-Handler "raise;" hinzufügen (ändert Verhalten) | `on E: EConvertError do raise;` |
| 7 | 278 | SCA120 | Exception auslösen (ändert Verhalten) | `raise EArgumentOutOfRangeException.Create(..)` |
| 8 | 271 | SCA083 | Leeres try/finally entfernen | Zuweisung ohne try (neu analysieren) |
| 9 | 268 | SCA169 | Bedingung außerhalb von Assert auswerten (ändert Verhalten) | `if not (ApplyVolumeDiscount(AOrder)) then Assert(False, ..)` – der Rabatt gilt jetzt auch im Release-Build |
| 10 | 254 | SCA018 | Letztes if in eine Wächter-Klausel mit Exit umwandeln | `if not Assigned(ACoupons) then Exit;`, Block eine Ebene flacher (neu analysieren) |
| 11 | 237 | SCA011 | Unerreichbaren Code löschen: 1 Zeile(n) | die Zeile hinter `Exit;` ist weg |
| 12 | 233 | SCA094 | Das überflüssige innere Klammerpaar entfernen | `if not (FRoundToFiveCents) then` |
| 13 | 225 | SCA144 | Statt des exakten Vergleichs SameValue verwenden (ändert Verhalten) | `SameValue(FDiscount, 0.5)` |
| 14 | 223 | SCA014 | Lokale Konstante für 30 einführen | `const MagicNr01 = 30;` (neu analysieren) |
| 15 | 221 | SCA144 | Statt des exakten Vergleichs IsZero verwenden (ändert Verhalten) | `IsZero(AWeightKg)` |
| 16 | 210 | SCA044 | Format() aus Verkettung bilden | `Group := Group + Format(' (%s %%)', [FloatToStr(FDiscount)]);` |
| 17 | 209 | SCA072 | Überflüssigen Vergleich mit True/False entfernen | `if not IsVip then` |
| 18 | 208 | SCA131 | IfThen durch if..then..else ersetzen (ändert Verhalten) | `if IsVip then Group := 'VIP' else Group := Format(..)` – der Format-Aufruf läuft nur noch im else (neu analysieren) |
| 19 | 197 | SCA128 | **TFormatSettings.Invariant übergeben** (zweiter Eintrag) | `DateToStr(Date, TFormatSettings.Invariant)` |
| 20 | 192 | SCA059 | FormatSettings ausdrücklich übergeben | `Format(.., [..], FormatSettings)` |
| 21 | 191 | SCA059 | TFormatSettings.Invariant übergeben (zweiter Eintrag) | dto. mit `Invariant` |
| 22 | 189 | SCA005 | von Hand: `AOrder.Items[I].UnitPrice` als drittes Argument ergänzen | Fund weg |
| 23 | 188 | SCA203 | Schleife 0 to AOrder.Items.Count - 1 laufen lassen (ändert Verhalten) | `0 to AOrder.Items.Count - 1` |
| 24 | 186 | SCA009 | Lines in einem try/finally-Block freigeben (ändert Verhalten) | `try .. finally Lines.Free; end;` (neu analysieren) |
| 25 | 176 | SCA127 | Stattdessen EArgumentException auslösen / zweiter Eintrag EInvalidOpException | eine der beiden Klassen statt `Exception` |
| 26 | 174 | SCA137 | AQuantity vor der Multiplikation nach Int64 umwandeln (ändert Verhalten) | `Int64(AQuantity) * AUnitCents` |
| 27 | 164 | SCA168 | else-Zweig mit Exception ergänzen (zweiter Eintrag; erster: leeres else) | `else raise EInvalidOpException.Create('Unhandled case');` (neu analysieren) |
| 28 | 157 | SCA202 | von Hand: `else if AQuantity <> 0 then` | Fund weg |
| 29 | 150 | SCA119 | Konstante in MAX_DISCOUNT umbenennen | Deklaration und Verwendung umbenannt |
| 30 | 148 | SCA148 | VolumeDiscount zur statischen Klassenmethode machen | `class function ..; static;` in Deklaration und Implementierung |
| 31 | 144 | SCA047 | Selbstzuweisung von FDiscount entfernen | Zeile weg (neu analysieren) |
| 32 | 140 | SCA098 | Bedingung direkt an FIsLargeOrder zuweisen | `FIsLargeOrder := Total > LARGE_ORDER_LIMIT;` (neu analysieren) |
| 33 | 138 | SCA074 | Bedingung als Assert-Meldung verwenden | `Assert(AOrder <> nil, 'AOrder <> nil')` |
| 34 | 136 | SCA053 | Ungenutzte Variable Unused entfernen | Deklaration weg (neu analysieren) |
| 35 | 130 | SCA066 | Leere Klammern entfernen | `Reset;` |
| 36 | 97 | SCA150 | Immer wahre Bedingung entfernen | nur noch der then-Block (neu analysieren) |
| 37 | 87 | SCA046 | "to" durch "downto" ersetzen (zweiter Eintrag: Schleifengrenzen vertauschen) | `for Tier := 3 downto 1 do` |
| 38 | 80 | SCA118 | Exception-Klasse in EVoucherError umbenennen | Deklaration und `raise` umbenannt |
| 39 | 76 | SCA079 | Mit dem vorigen const-Abschnitt zusammenlegen | ein `const`-Abschnitt (neu analysieren) |
| 40 | 74 | SCA069 | Ziffern mit "_" gruppieren | `100_000_000` (ab Delphi 11) |

`SCA007` für `System.Math` (Zeile 11) ist nach Schritt 13/15 erledigt –
SameValue und IsZero kommen aus System.Math. Wer es zeigen will: **vor**
Schritt 13.

## Szene 5: uOrderModel.pas – Klassen, Vererbung, Attribute

Oben in der Unit steht schon ein Datei-Marker
`// noinspection-file ClassPerFile, BeginEndRequired` – gutes Beispiel für
eine Team-Konvention.

| # | Zeile | Fund | Aktion | Erwartung danach |
|---:|---:|---|---|---|
| 1 | 440 | SCA164 | Ungenutzte Routine FormatSku löschen | Routine weg |
| 2 | 415 | SCA174 | TObjectList<TOrderItem> verwenden, damit die Liste ihre Elemente freigibt (ändert Verhalten) | Deklaration und `Create` umgestellt – das Leck ist weg |
| 3 | 395 | SCA076 | Gruppierte Deklaration aufteilen | `Sum: Integer;` / `Weight: Integer;` (neu analysieren) |
| 4 | 393 | SCA148 | CheckDigit zur statischen Klassenmethode machen | `class function CheckDigit(..): Integer; static;` |
| 5 | 384 | SCA121 | Result mit 0 initialisieren (ändert Verhalten) | `Result := 0;` – erklären: richtig wäre `Result := FTotal` am Ende (neu analysieren) |
| 6 | 372 | SCA086 | "out" für AItem durch "var" ersetzen | Deklaration (Zeile 158) und Implementierung |
| 7 | 367 | SCA126 | Assigned() statt Vergleich mit nil verwenden | `if Assigned(FCustomer) then` |
| 8 | 354 | SCA054 | Parameter ANotify mit "_" als absichtlich ungenutzt kennzeichnen | `_ANotify` – oder erklären: eigentlich ein Bug, der Parameter wird ignoriert |
| 9 | 344 | SCA170 | Parameter ASku als const deklarieren | `const ASku: string` in Deklaration und Implementierung |
| 10 | 317 | SCA093 | Zweiten doppelten inherited-Aufruf entfernen (ändert Verhalten) | ein `inherited;` (neu analysieren) |
| 11 | 276 | SCA085 | FreeAndNil(FAddress) verwenden | `FreeAndNil(FAddress);` (neu analysieren) |
| 12 | 274 | SCA084 | Überflüssigen Vergleich mit nil entfernen | `if Assigned(FAddress) then` |
| 13 | 268 | SCA196 | Result zuerst initialisieren: Result := '' (ändert Verhalten) | `Result := '';` als erste Anweisung (neu analysieren) |
| 14 | 255 | SCA125 | Leeres Override Changed entfernen | Deklaration und Implementierung weg (neu analysieren) |
| 15 | 236 | SCA097 | inherited als Letztes im Destruktor aufrufen (ändert Verhalten) | `inherited;` vor `end` |
| 16 | 225 | SCA020 | Leeren Rumpf als beabsichtigt kennzeichnen (zweiter Eintrag: ENotImplemented auslösen) | `// intentionally empty` |
| 17 | 218 | SCA096 | inherited Create als Erstes im Konstruktor aufrufen | `inherited Create;` (neu analysieren) |
| 18 | 198 | SCA118 | Exception-Klasse in EQuantityError umbenennen | alle `raise QuantityError` mit |
| 19 | 187 | SCA183 | Leerzeile nach dem Attribut entfernen | – |
| 20 | 185 | SCA179 | Grund zu [Ignore] hinzufügen | `[Ignore('reason')]` |
| 21 | 183 | SCA180 | Doppeltes Attribut entfernen | ein `[Exported]` |
| 22 | 180 | SCA181 | Dem Attribut einen Kategorienamen geben | `[Category('category')]` |
| 23 | 147 | SCA087 | Leeren Sichtbarkeitsabschnitt entfernen | `protected` weg (neu analysieren) |
| 24 | 130 | SCA149 | "override;" an die Deklaration anfügen (ändert Verhalten) | `LineTotal` überschreibt jetzt – der Rabatt wirkt auch über `TOrderItem`-Variablen |
| 25 | 93 | SCA106 | Methodennamen als MarkAsVip schreiben | Deklaration und Implementierung |
| 26 | 80 | SCA147 | Ungenutzte private Methode NormalizedName löschen | Deklaration und Implementierung weg (neu analysieren) |
| 27 | 50 | SCA076 | Gruppierte Deklaration aufteilen | `FStreet: string;` / `FCity: string;` |
| 28 | 48 | SCA075 | (TObject) aus der Klassendeklaration entfernen | `TAddress = class` |
| 29 | 43 | SCA197 | Neue GUID einfügen | `['{...}']` unter `IOrderObserver = interface` |

## Szene 6: uOrderRepository.pas – Datenbank, Sperren, Threads

| # | Zeile | Fund | Aktion | Erwartung danach |
|---:|---:|---|---|---|
| 1 | 267 | SCA113 | Worker.Start statt Resume verwenden | `Worker.Start;` |
| 2 | 234 | SCA001 | Csv in einem try/finally-Block freigeben (ändert Verhalten) | `Csv.Free` im finally (neu analysieren). Derselbe Eintrag hängt auch am SCA009-Fund dieser Zeile |
| 3 | 225 | SCA065 | NOSONAR durch einen Marker "noinspection All" ersetzen (ändert Verhalten) | `// noinspection All` über der Zeile (neu analysieren) |
| 4 | 224, 222 | SCA003 | Parametrisierte Vorlage in die Zwischenablage | Zwischenablage zeigen: `WHERE order_ref = :OrderRef` und `FQuery.ParamByName('OrderRef').Value := AOrderRef;` – die Aktion schreibt selbst nie in den Editor |
| 5 | 222 | SCA003 | Stelle zeigen | markiert genau die Zuweisung |
| 6 | 221 | SCA165 | Wirkungslosen Unterdrück-Marker entfernen | `// noinspection NilDeref` weg (neu analysieren) |
| 7 | 216 | SCA082 | Überzähliges Semikolon entfernen | `FQuery.ExecSQL;` |
| 8 | 214 | SCA199 | Parameternamen "City" aus dem SQL verwenden (ändert Verhalten) | `ParamByName('City')` |
| 9 | 205 | SCA112 | FQuery.FieldByName('amount') vor die Schleife ziehen (ändert Verhalten) | `var FldAmount := ..` vor `while` (neu analysieren) |
| 10 | 193 | SCA111 | FQuery.ParamByName('quantity') vor die Schleife ziehen (ändert Verhalten) | `var PrmQuantity := ..` vor `for` (neu analysieren) |
| 11 | 192, 191 | SCA111 | dto. für `sku` und `order_no` | je eine Zeile mehr (jeweils neu analysieren) |
| 12 | 187 | SCA017 | Debug-Ausgabe in {$IFDEF DEBUG} setzen (ändert Verhalten) | **erst nach 10/11**: eine Direktive in der Routine sperrt SCA111 (neu analysieren) |
| 13 | 174 | SCA109 | Sperre FCacheLock in einem try/finally-Block freigeben (ändert Verhalten) | `try .. finally FCacheLock.Leave; end;` (neu analysieren) |
| 14 | 167 | SCA153 | Sperre FStatsLock in einem try/finally-Block freigeben (ändert Verhalten) | dto. mit `Release` (neu analysieren) |
| 15 | 141 | SCA003 | Parametrisierte Vorlage in die Zwischenablage | `WHERE city = :City ORDER BY name` und `ParamByName('City').Value := ACity;` |
| 16 | 134 | SCA139 | FreeAndNil(FQuery) verwenden | `FreeAndNil(FQuery);` – sonst gäbe der Destruktor die Query ein zweites Mal frei |
| 17 | 91 | SCA156 | Puffer Buffer in einem try/finally-Block freigeben (ändert Verhalten) | `try .. finally FreeMem(Buffer); end;` (neu analysieren) |
| 18 | 79 | SCA115 | https:// statt http:// verwenden (ändert Verhalten) | `'https://orders.example-shop.com/...'` |
| 19 | 16 | SCA007 | Unit Data.DB aus uses entfernen (ändert Verhalten) | `Data.DB,` weg |

## Szene 7: uOrderForm.pas und .dfm – das Formular

| # | Zeile | Fund | Aktion | Erwartung danach |
|---:|---:|---|---|---|
| 1 | 176 | SCA044 | Format() aus Verkettung bilden | `Format('Orders: %d - total %s - average %s', [Count, CurrToStr(Total), ..])` |
| 2 | 167 | SCA128 | FormatSettings ausdrücklich übergeben | `CurrToStr(.., FormatSettings)` |
| 3 | 147 | SCA077 | Leeres "with ... do begin end" durch den Aufruf ersetzen | `lvOrders.Items.AddItem(nil);` (neu analysieren) |
| 4 | 112 | SCA017 | Debug-Ausgabe löschen (zweiter Eintrag) – oder in {$IFDEF DEBUG} setzen | die ShowMessage-Zeile ist weg |
| 5 | 79 | SCA003 | Parametrisierte Vorlage in die Zwischenablage | `WHERE customer = :Edit1Text` – die Hochkommas um den Wert fallen weg; SCA033 im DFM zeigt dieselbe Lücke aus Formularsicht |

Die sechs SCA007-Funde in Zeile 8–14 (FireDAC- und VCL-Units) **nicht**
anwenden, sondern erklären: der uses-Check ist heuristisch, darum
„(ändert Verhalten)“; die IDE trägt die FireDAC-Units beim Speichern des
Formulars wieder ein. Die DFM-Funde (Szene 2, auch SCA026 `:101`) haben
keine Code-Aktion –
Doppelklick öffnet die .dfm an der Stelle.

## Szene 8: Code-Aktionen ohne Fund (Charge B)

Rechtsklick mit dem Caret auf der Stelle – im Editor-Kontextmenü stehen
die Code-Aktionen am Caret, auch auf einer Zeile ohne Fund. Stellen im Demo:

- **Lokale Konstante einführen** auf einem Zahl-Literal ohne Fund:
  `uOrderModel.pas:405` `Result := (11 - Sum mod 11) mod 11;` (Caret auf
  der ersten `11` – nur dieses Literal wird ersetzt),
  `uPriceCalculator.pas:128` `FTaxRate := 0.19;`,
  `uPriceCalculator.pas:228` `Result := 5.90;` (der `else`-Zweig bekommt
  `begin..end`). Triviale Zahlen wie in `Weight := 2;` (Zeile 398) bieten
  nichts an – dieselbe Menge, die SCA014 durchlässt (0, 1, 2, -1, 10,
  100, Zweierpotenzen bis 1024).
- **try/finally um Create, wenn ein Free existiert**:
  `uOrderForm.pas:102` `Importer := TLegacyImporter.Create;` – das `try`
  kommt erst nach `Order := TOrder.Create(..)`; wirft
  `LoadCustomer`, leckt der Importer. Kein Fund meldet das heute.

## Szene 9: Abschluss

- Neu scannen: die meisten Funde sind weg; übrig bleiben die bewussten
  (DFM, Heuristiken mit niedriger Konfidenz wie SCA052 „Dead public API“).
- Kompilieren: übersetzt weiterhin (die Hilfen prüfen vor dem Schreiben,
  dass das Ergebnis bedeutungsgleich bzw. gekennzeichnet ist).
- Zurücksetzen für den nächsten Durchlauf: `git checkout examples/ShowcaseDemo`.

## Anhang: Abdeckung aller Code-Aktionen

Nachgewiesen mit der reDelphix-Angebotsprobe (echter Code von
`uRdxFixTable`, `uRdxFixRunner`, `uRdxRecipeRunner` und aller Planer unter
FPC 3.2.2, SCA044 über `RdxCorpusProbe.exe`) auf dem SARIF des Laufs
`--profile strict --min-severity hint`, `MinConfidence=low`, Stand
reDelphiX 49ab918f (Funde nachgemessen mit der Exe 5575bd42 und der
SCA068-Stelle in Zeile 122). **106 von 106 angeboten.** Status **ja** = der echte
reDelphix-Code hat allein entschieden; **ja\*** = angeboten, eine Typ-,
with- oder Baumfrage an die Engine (`DeclaredTypeOf`, `InWithBlock`,
uses-Klauseln) hat dabei ein Probe-Orakel beantwortet – alle 19 Antworten
sind am Quelltext geprüft (Typen aus derselben Unit, kein `with` in der
Routine), einmal in der IDE gegenprüfen. „weitere / gesperrt“: weitere
Stellen mit Angebot bzw. Stellen, an denen die Hilfe begründet ablehnt
(z. B. SCA014 hinter `else if`, SCA126 bei einem Typ aus einer anderen
Unit). Nach dem Anwenden übersetzen alle 153 Ergebnisdateien unter FPC
ohne neuen Fehler, außer Delphi-eigener Syntax (Inline-`var`/`const`,
`TFormatSettings.Invariant`, Zifferntrenner, `System.Contnrs`).

| Nr. | Regel | Eintrag | Menütext (Beispiel) | Stelle | Status | weitere / gesperrt |
|---:|---|---|---|---|---|---|
| 1 | SCA001 | 1 | Csv in einem try/finally-Block freigeben (ä. V.) | uOrderRepository.pas:234 | ja | 0 / 0 |
| 2 | SCA002 | 1 | raise; in den leeren except-Block einfügen (ä. V.) | uPriceCalculator.pas:302 | ja | 0 / 0 |
| 3 | SCA007 | 1 | Unit Contnrs aus uses entfernen (ä. V.) | uLegacyImport.pas:9 | ja* | 8 / 0 |
| 4 | SCA009 | 1 | Csv in einem try/finally-Block freigeben (ä. V.) | uOrderRepository.pas:234 | ja | 1 / 0 |
| 5 | SCA011 | 1 | Unerreichbaren Code löschen: 1 Zeile(n) | uPriceCalculator.pas:237 | ja | 0 / 0 |
| 6 | SCA014 | 1 | Lokale Konstante für 3 einführen | uLegacyImport.pas:91 | ja | 2 / 1 |
| 7 | SCA017 | 1 | Debug-Ausgabe in {$IFDEF DEBUG} setzen (ä. V.) | uOrderForm.pas:112 | ja | 2 / 0 |
| 8 | SCA017 | 2 | Debug-Ausgabe löschen (ä. V.) | uOrderForm.pas:112 | ja | 2 / 0 |
| 9 | SCA018 | 1 | Letztes if in eine Wächter-Klausel mit Exit umwandeln | uPriceCalculator.pas:254 | ja | 0 / 0 |
| 10 | SCA020 | 1 | Leeren Rumpf als beabsichtigt kennzeichnen | uOrderModel.pas:225 | ja | 0 / 0 |
| 11 | SCA020 | 2 | ENotImplemented im leeren Rumpf auslösen (ä. V.) | uOrderModel.pas:225 | ja | 0 / 0 |
| 12 | SCA046 | 1 | "to" durch "downto" ersetzen (ä. V.) | uPriceCalculator.pas:87 | ja | 0 / 0 |
| 13 | SCA046 | 2 | Schleifengrenzen vertauschen (ä. V.) | uPriceCalculator.pas:87 | ja | 0 / 0 |
| 14 | SCA047 | 1 | Selbstzuweisung von FDiscount entfernen | uPriceCalculator.pas:144 | ja* | 0 / 0 |
| 15 | SCA053 | 1 | Ungenutzte Variable Unused entfernen | uPriceCalculator.pas:136 | ja | 0 / 0 |
| 16 | SCA054 | 1 | Parameter ANotify mit "_" als absichtlich ungenutzt kennzeichnen | uOrderModel.pas:354 | ja | 0 / 0 |
| 17 | SCA059 | 1 | FormatSettings ausdrücklich übergeben | uPriceCalculator.pas:189 | ja | 2 / 0 |
| 18 | SCA059 | 2 | TFormatSettings.Invariant übergeben (ä. V.) | uPriceCalculator.pas:189 | ja | 2 / 0 |
| 19 | SCA060 | 1 | "goto" durch Exit ersetzen | uLegacyImport.pas:56 | ja | 0 / 0 |
| 20 | SCA061 | 1 | Tabulatoren dieser Zeile durch Leerzeichen ersetzen | uLegacyImport.pas:64 | ja | 0 / 0 |
| 21 | SCA063 | 1 | Leerraum am Zeilenende entfernen | uLegacyImport.pas:64 | ja | 0 / 0 |
| 22 | SCA064 | 1 | Begin klein schreiben | uLegacyImport.pas:43 | ja | 1 / 0 |
| 23 | SCA065 | 1 | NOSONAR durch einen Marker "noinspection All" ersetzen (ä. V.) | uOrderRepository.pas:225 | ja | 0 / 0 |
| 24 | SCA066 | 1 | Leere Klammern entfernen | uPriceCalculator.pas:130 | ja* | 0 / 0 |
| 25 | SCA068 | 1 | Überzähliges Komma entfernen | uLegacyImport.pas:122 | ja | 0 / 0 |
| 26 | SCA069 | 1 | Ziffern mit "_" gruppieren | uPriceCalculator.pas:74 | ja | 0 / 0 |
| 27 | SCA070 | 1 | Auskommentierten Code löschen | uLegacyImport.pas:97 | ja | 0 / 0 |
| 28 | SCA071 | 1 | Schlüsselwort an Spalte 1 setzen | uLegacyImport.pas:35 | ja | 0 / 0 |
| 29 | SCA072 | 1 | Überflüssigen Vergleich mit True/False entfernen | uPriceCalculator.pas:209 | ja* | 0 / 0 |
| 30 | SCA074 | 1 | Bedingung als Assert-Meldung verwenden | uPriceCalculator.pas:138 | ja* | 0 / 0 |
| 31 | SCA075 | 1 | (TObject) aus der Klassendeklaration entfernen | uOrderModel.pas:48 | ja | 0 / 0 |
| 32 | SCA076 | 1 | Gruppierte Deklaration aufteilen | uOrderModel.pas:50 | ja | 1 / 0 |
| 33 | SCA077 | 1 | Leeres "with ... do begin end" durch den Aufruf ersetzen | uOrderForm.pas:147 | ja | 0 / 0 |
| 34 | SCA079 | 1 | Mit dem vorigen const-Abschnitt zusammenlegen | uPriceCalculator.pas:76 | ja | 0 / 0 |
| 35 | SCA080 | 1 | Überflüssiges Exit entfernen | uPriceCalculator.pas:342 | ja | 0 / 0 |
| 36 | SCA082 | 1 | Überzähliges Semikolon entfernen | uOrderRepository.pas:216 | ja | 0 / 0 |
| 37 | SCA083 | 1 | Leeres try/finally entfernen | uPriceCalculator.pas:271 | ja | 0 / 0 |
| 38 | SCA084 | 1 | Überflüssigen Vergleich mit nil entfernen | uOrderModel.pas:274 | ja* | 0 / 0 |
| 39 | SCA085 | 1 | FreeAndNil(FAddress) verwenden | uOrderModel.pas:276 | ja* | 0 / 0 |
| 40 | SCA086 | 1 | "out" für AItem durch "var" ersetzen (ä. V.) | uOrderModel.pas:158 | ja | 1 / 0 |
| 41 | SCA087 | 1 | Leeren Sichtbarkeitsabschnitt entfernen | uOrderModel.pas:147 | ja | 0 / 0 |
| 42 | SCA088 | 1 | begin durch initialization ersetzen | uLegacyImport.pas:125 | ja | 0 / 0 |
| 43 | SCA093 | 1 | Zweiten doppelten inherited-Aufruf entfernen (ä. V.) | uOrderModel.pas:317 | ja | 0 / 0 |
| 44 | SCA093 | 2 | Ersten doppelten inherited-Aufruf entfernen (ä. V.) | uOrderModel.pas:317 | ja | 0 / 0 |
| 45 | SCA094 | 1 | Das überflüssige innere Klammerpaar entfernen | uPriceCalculator.pas:233 | ja | 0 / 0 |
| 46 | SCA096 | 1 | inherited Create als Erstes im Konstruktor aufrufen | uOrderModel.pas:218 | ja | 0 / 0 |
| 47 | SCA097 | 1 | inherited als Letztes im Destruktor aufrufen (ä. V.) | uOrderModel.pas:236 | ja | 0 / 0 |
| 48 | SCA098 | 1 | Bedingung direkt an FIsLargeOrder zuweisen | uPriceCalculator.pas:140 | ja* | 0 / 0 |
| 49 | SCA099 | 1 | Zweig in begin..end setzen | uLegacyImport.pas:68 | ja | 0 / 0 |
| 50 | SCA101 | 1 | Zweig in begin..end setzen | uLegacyImport.pas:56 | ja | 1 / 0 |
| 51 | SCA106 | 1 | Methodennamen als MarkAsVip schreiben | uOrderModel.pas:93 | ja | 0 / 0 |
| 52 | SCA109 | 1 | Sperre FCacheLock in einem try/finally-Block freigeben (ä. V.) | uOrderRepository.pas:174 | ja | 0 / 0 |
| 53 | SCA111 | 1 | FQuery.ParamByName('order_no') vor die Schleife ziehen (ä. V.) | uOrderRepository.pas:191 | ja* | 2 / 0 |
| 54 | SCA112 | 1 | FQuery.FieldByName('amount') vor die Schleife ziehen (ä. V.) | uOrderRepository.pas:205 | ja* | 0 / 0 |
| 55 | SCA113 | 1 | Worker.Start statt Resume verwenden | uOrderRepository.pas:267 | ja | 0 / 0 |
| 56 | SCA115 | 1 | https:// statt http:// verwenden (ä. V.) | uOrderRepository.pas:79 | ja | 0 / 0 |
| 57 | SCA117 | 1 | Dokumentationsgerüst einfügen | uLegacyImport.pas:27 | ja | 1 / 0 |
| 58 | SCA118 | 1 | Exception-Klasse in EQuantityError umbenennen | uOrderModel.pas:198 | ja | 1 / 0 |
| 59 | SCA119 | 1 | Konstante in MAX_DISCOUNT umbenennen | uPriceCalculator.pas:150 | ja | 0 / 0 |
| 60 | SCA120 | 1 | Exception auslösen (ä. V.) | uPriceCalculator.pas:278 | ja | 0 / 0 |
| 61 | SCA121 | 1 | Result mit 0 initialisieren (ä. V.) | uOrderModel.pas:384 | ja | 0 / 0 |
| 62 | SCA122 | 1 | raise; verwenden (Original-Stack-Trace bleibt) | uPriceCalculator.pas:319 | ja | 0 / 0 |
| 63 | SCA123 | 1 | Cast nach TStringList vor Free entfernen | uLegacyImport.pas:73 | ja* | 0 / 0 |
| 64 | SCA125 | 1 | Leeres Override Changed entfernen | uOrderModel.pas:255 | ja | 0 / 0 |
| 65 | SCA126 | 1 | Assigned() statt Vergleich mit nil verwenden | uOrderModel.pas:367 | ja* | 0 / 2 |
| 66 | SCA127 | 1 | Stattdessen EArgumentException auslösen (falsches Argument) (ä. V.) | uPriceCalculator.pas:176 | ja | 0 / 0 |
| 67 | SCA127 | 2 | Stattdessen EInvalidOpException auslösen (unzulässiger Zustand) (ä. V.) | uPriceCalculator.pas:176 | ja | 0 / 0 |
| 68 | SCA128 | 1 | FormatSettings ausdrücklich übergeben | uOrderForm.pas:122 | ja | 7 / 0 |
| 69 | SCA128 | 2 | TFormatSettings.Invariant übergeben (ä. V.) | uOrderForm.pas:122 | ja | 7 / 0 |
| 70 | SCA131 | 1 | IfThen durch if..then..else ersetzen (ä. V.) | uPriceCalculator.pas:208 | ja* | 0 / 0 |
| 71 | SCA137 | 1 | AQuantity vor der Multiplikation nach Int64 umwandeln (ä. V.) | uPriceCalculator.pas:174 | ja* | 0 / 0 |
| 72 | SCA139 | 1 | FreeAndNil(FQuery) verwenden | uOrderRepository.pas:134 | ja* | 0 / 0 |
| 73 | SCA144 | 1 | Statt des exakten Vergleichs IsZero verwenden (ä. V.) | uPriceCalculator.pas:221 | ja* | 1 / 0 |
| 74 | SCA147 | 1 | Ungenutzte private Methode NormalizedName löschen | uOrderModel.pas:80 | ja | 0 / 0 |
| 75 | SCA148 | 1 | FieldLength zur statischen Klassenmethode machen | uLegacyImport.pas:108 | ja | 4 / 0 |
| 76 | SCA149 | 1 | "override;" an die Deklaration anfügen (ä. V.) | uOrderModel.pas:130 | ja | 0 / 0 |
| 77 | SCA150 | 1 | Immer wahre Bedingung entfernen | uPriceCalculator.pas:97 | ja | 0 / 0 |
| 78 | SCA153 | 1 | Sperre FStatsLock in einem try/finally-Block freigeben (ä. V.) | uOrderRepository.pas:167 | ja | 0 / 0 |
| 79 | SCA154 | 1 | SizeOf(Integer) statt der Zeigergröße verwenden (ä. V.) | uLegacyImport.pas:115 | ja* | 0 / 0 |
| 80 | SCA156 | 1 | Puffer Buffer in einem try/finally-Block freigeben (ä. V.) | uOrderRepository.pas:91 | ja | 0 / 0 |
| 81 | SCA159 | 1 | Dem leeren Ausnahme-Handler "raise;" hinzufügen (ä. V.) | uPriceCalculator.pas:293 | ja | 0 / 0 |
| 82 | SCA161 | 1 | Die 32-Bit-Casts durch NativeInt/NativeUInt ersetzen (ä. V.) | uLegacyImport.pas:110 | ja | 0 / 0 |
| 83 | SCA164 | 1 | Ungenutzte Routine FormatSku löschen | uOrderModel.pas:440 | ja | 1 / 0 |
| 84 | SCA167 | 1 | Randomize im initialization-Abschnitt aufrufen (ä. V.) | uPriceCalculator.pas:333 | ja | 0 / 0 |
| 85 | SCA168 | 1 | Leeren else-Zweig ergänzen | uPriceCalculator.pas:164 | ja | 0 / 0 |
| 86 | SCA168 | 2 | else-Zweig mit Exception ergänzen (ä. V.) | uPriceCalculator.pas:164 | ja | 0 / 0 |
| 87 | SCA169 | 1 | Bedingung außerhalb von Assert auswerten (ä. V.) | uPriceCalculator.pas:268 | ja | 0 / 0 |
| 88 | SCA170 | 1 | Parameter ASku als const deklarieren | uOrderModel.pas:344 | ja | 0 / 0 |
| 89 | SCA174 | 1 | TObjectList<TOrderItem> verwenden, damit die Liste ihre Elemente freigibt (ä. V.) | uOrderModel.pas:415 | ja | 1 / 0 |
| 90 | SCA179 | 1 | Grund zu [Ignore] hinzufügen | uOrderModel.pas:185 | ja | 0 / 0 |
| 91 | SCA180 | 1 | Doppeltes Attribut entfernen | uOrderModel.pas:183 | ja | 0 / 0 |
| 92 | SCA181 | 1 | Dem Attribut einen Kategorienamen geben | uOrderModel.pas:180 | ja | 0 / 0 |
| 93 | SCA183 | 1 | Leerzeile nach dem Attribut entfernen | uOrderModel.pas:187 | ja | 0 / 0 |
| 94 | SCA188 | 1 | Bidi-Steuerzeichen entfernen (in Strings als #$-Code) | uLegacyImport.pas:40 | ja | 0 / 0 |
| 95 | SCA192 | 1 | Unsichtbare Zeichen entfernen (in Strings als #$-Code) | uLegacyImport.pas:38 | ja | 0 / 0 |
| 96 | SCA193 | 1 | Namen in ASCII-Buchstaben schreiben: Amount | uLegacyImport.pas:81 | ja | 0 / 0 |
| 97 | SCA196 | 1 | Result zuerst initialisieren: Result := '' (ä. V.) | uOrderModel.pas:268 | ja | 0 / 0 |
| 98 | SCA197 | 1 | Neue GUID einfügen | uOrderModel.pas:43 | ja | 0 / 0 |
| 99 | SCA199 | 1 | Parameternamen "City" aus dem SQL verwenden (ä. V.) | uOrderRepository.pas:214 | ja | 0 / 0 |
| 100 | SCA203 | 1 | Schleife 0 to AOrder.Items.Count - 1 laufen lassen (ä. V.) | uPriceCalculator.pas:188 | ja | 0 / 0 |
| 101 | Anbieter | - | Format() aus Verkettung bilden | uOrderForm.pas:176 | ja | 1 / 0 |
| 102 | Anbieter | - | Hier / In dieser Datei unterdrücken | uLegacyImport.pas:8 | ja | 386 / 1 |
| 103 | Anbieter | - | Parametrisierte Vorlage in die Zwischenablage | uOrderForm.pas:79 | ja* | 3 / 0 |
| 104 | Anbieter | - | Stelle zeigen | uOrderForm.pas:176 | ja | 5 / 0 |
| 105 | Anbieter | - | Wirkungslosen Unterdrück-Marker entfernen | uOrderRepository.pas:221 | ja | 0 / 0 |
| 106 | Anbieter | - | uses-Einträge qualifizieren (uses: X -> Scope.X / alle Einträge) | uLegacyImport.pas:8 | ja* | 5 / 1 |

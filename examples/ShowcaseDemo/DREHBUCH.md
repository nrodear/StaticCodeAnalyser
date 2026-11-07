# Drehbuch: SCA und reDelphix am ShowcaseDemo

Video-Skript für das Projekt `examples/ShowcaseDemo` (englischer Überblick:
[README.md](README.md)). Ablauf: Installation, Projekt öffnen, Scan, dann
Datei für Datei die Funde und die Code-Aktionen von reDelphix. Alle 108
Code-Aktionen zu einem Fund (die 94 Quick-Fixes der Tabelle, ihre 8 zweiten
Einträge, 6 Aktionen des Anbieters) haben mindestens eine Stelle – Anhang A
nennt sie –, dazu die 10 Code-Aktionen ohne Fund (Szene 8). Für jede Regel,
die sich mit Delphi-Code zeigen lässt, steht mindestens ein Fund im Projekt
(Anhang B); es fehlt nur SCA175.

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
2. SCA samt reDelphix installieren: `StaticCodeAnalyserSetup-<Version>.exe`
   ausführen, reDelphix kommt mit dem Plugin. Aus den Quellen geht
   es auch: Projektgruppe `StaticCodeAnalyser.d12.groupproj` öffnen, Gruppe
   erzeugen, dann `StaticCodeAnalyser.IDE.d12` und `reDelphix.d12` im
   Projekt-Manager **Installieren** (Details: `reDelphix/README.md`, Abschnitte
   „Voraussetzungen in der IDE“ und „Bauen und installieren“).
3. `%APPDATA%\StaticCodeAnalyser\analyser.ini`, Abschnitte `[Rules]` und
   `[Detectors]` (vor dem Start der IDE):

   ```ini
   [Rules]
   Profile=strict
   IdeProfile=strict
   MinSeverity=hint
   IdeMinSeverity=hint
   MinConfidence=low

   [Detectors]
   UsesCheck=1
   ```

   `strict` bringt die Konventionsregeln, die `default` auslässt
   (SCA099, SCA101, SCA117, SCA126). **`UsesCheck=1`** schaltet den
   uses-Check SCA007 ein – in der IDE in jedem Profil, auch in `strict`,
   nur über diesen Schalter. Ohne ihn fehlen die neun SCA007-Funde, und die
   SCA007-Schritte (Szene 3 #20, Szene 4 Hinweis, Szene 6 #19, Szene 7)
   bieten nichts an. Die CLI schaltet ihn bei `--profile strict` selbst
   ein. `MinConfidence=low` braucht es
   für die sechs Formatregeln SCA061, SCA063, SCA064, SCA069, SCA076,
   SCA079 – die Engine meldet sie mit niedriger Konfidenz. Erwartung:
   **285 Funde**, davon 9 SCA007 (mit `MinConfidence=medium` 223; Profil
   `default`: 255 bzw. 193, dort ohne SCA007 – mit `UsesCheck=1` 264 bzw.
   202).
4. Zurücksetzen: `git checkout examples/ShowcaseDemo`, `__history`
   löschen.
5. Probelauf: einmal bauen (Win32, Debug). Erwartet: übersetzt mit
   Warnungen (W1010 „verdeckt virtuelle Methode“, W1035 „Rückgabewert
   undefiniert“, W1000 „Resume ist veraltet“, W1036 „Variable `Best` ist
   möglicherweise nicht initialisiert“, Warnungen zur Umwandlung nach
   `AnsiString`, Hinweise zu ungenutzten Variablen). Das überzählige Komma für SCA068 steht im spät gebundenen
   Variant-Aufruf `uLegacyImport.pas:188` (`AExcel.Workbooks.Open(AFileName,);`):
   nur dort übersetzt Delphi es (leeres Argument = weggelassener optionaler
   Parameter); in einem normalen Aufruf wäre es E2034 „Zu viele Parameter“.

## Szene 1: Projekt öffnen und kompilieren

- `examples/ShowcaseDemo/ShowcaseDemo.dproj` öffnen, Projekt-Manager zeigen:
  sieben Units, ein Formular (`uOrderStatus` und `uOrderEvents` sind nur für
  SCA143 und SCA092 da).
- Kurz bauen: „Der Compiler ist zufrieden – ein paar Warnungen, sonst nichts.
  Schauen wir, was der Static Code Analyser sieht.“

## Szene 2: Scan und Überblick

- Analyse für das Projekt starten. Dock-Fenster: **285 Funde** (ohne
  `UsesCheck=1` aus Szene 0: 276, die SCA007-Funde fehlen).
- Nach Schwere sortieren, die Error-Kacheln zeigen. Highlights **ohne**
  Code-Aktion (kurz anklicken, Fundtext vorlesen, von Hand erklären):
  - `uPriceCalculator.pas:231` **SCA202** `not AQuantity = 0` – bindet
    als `(not AQuantity) = 0`; gemeint war `AQuantity <> 0`.
  - `uPriceCalculator.pas:263` **SCA005** Format mit 3 Platzhaltern und
    2 Argumenten – zur Laufzeit EConvertError.
  - `uPriceCalculator.pas:262` **SCA203** Schleife läuft bis `Count` statt
    `Count - 1` (die Hilfe kommt in Szene 4).
  - `uOrderForm.dfm:79` **SCA033** und `uOrderForm.pas:81` **SCA003**: SQL
    aus `Edit1.Text` zusammengesetzt.
  - `uLegacyImport.pas:41` **SCA188** Trojan Source: ein unsichtbares
    Bidi-Steuerzeichen im Kommentar.
  - `uOrderRepository.pas:151` **SCA004** Passwort im Quelltext,
    `:152` **SCA200** feste IP-Adresse.
  - `uOrderForm.pas:134` **SCA008** `Order` ist nil und wird dereferenziert
    (dazu `:133` **SCA019** TODO).
  - `uOrderForm.dfm:101` **SCA026** Klartext-Passwort
    `Password=Sommer2024!` in `FDConnection1.Params.Strings` (Error).
  - `uPriceCalculator.pas:133` **SCA010** Division durch einen Parameter
    ohne Prüfung auf 0.
  - DFM: **SCA024** Standardnamen (`Button1`, `Edit1` …), **SCA039**
    Datenbank-Komponenten auf dem Formular, **SCA043** Aktion und OnClick
    zugleich an `btnRefresh`, **SCA029** `lvOrdersDblClick` ist an kein
    Ereignis gebunden – der Doppelklick tut nichts.
  - Weitere Fehler ohne Code-Aktion (alle Regeln mit ihrer Stelle:
    Anhang B): `uPriceCalculator.pas:160` **SCA055** `AWeek <= AWeek`
    ist immer wahr, `uPriceCalculator.pas:562` **SCA205**
    `ParcelCapacity := ParcelCapacity + I` ruft sich endlos selbst auf,
    `uOrderModel.pas:586` **SCA048** virtueller Aufruf im Konstruktor,
    `uOrderRepository.pas:300` **SCA058** `DELETE` ohne `WHERE`,
    `uOrderRepository.pas:368` **SCA116** TLS abgeschaltet,
    `uLegacyImport.pas:169` **SCA130** `PChar(';')`,
    `uOrderForm.pas:201` **SCA178** Dateiname aus dem Suchfeld.
- Überleitung: „Für die meisten Funde hat reDelphix eine Code-Aktion – die
  Glühbirne im Editor.“

## Szene 3: uLegacyImport.pas – Altcode aufräumen

Die Unit ist absichtlich „alt“: Tabs, `Begin`/`End`, `goto`, unqualifizierte
uses, Zeichen aus einer Webseite kopiert. Von unten nach oben:

| # | Zeile | Fund | Aktion (Menütext) | Erwartung danach |
|---:|---:|---|---|---|
| 1 | 191 | SCA088 | begin durch initialization ersetzen | `initialization` statt `begin` vor `end.` |
| 2 | 188 | SCA068 | Überzähliges Komma entfernen – im Dock-Grid per **Strg+Alt+F** | `AExcel.Workbooks.Open(AFileName);` |
| 2a | 128 | SCA206 | Formatter-Marker exakt schreiben | `{(*}` statt `{ (*}` – jetzt erkennen GExperts, CnWizards und JCF den Bereich um `OLD_COLUMNS` |
| 3 | 117 | SCA154 | SizeOf(Integer) statt der Zeigergröße verwenden (ändert Verhalten) | `Move(ASource^, ATarget^, SizeOf(Integer))` |
| 4 | 112 | SCA161 | Die 32-Bit-Casts durch NativeInt/NativeUInt ersetzen (ändert Verhalten) | `NativeInt(PEnd) - NativeInt(PStart)` – richtig auch unter Win64 |
| 5 | 110 | SCA148 | **Hier unterdrücken** (Strg+Alt+S) statt Hilfe; im selben Menü steht „In dieser Datei unterdrücken“ | Zeile `// noinspection CanBeClassMethod` darüber; Fund weg |
| 6 | 97–99 | SCA070 | Auskommentierten Code löschen | der `{ if Price = 0 ... }`-Block ist weg (neu analysieren) |
| 7 | 95 | SCA014 | Lokale Konstante für 20 einführen | `const MagicNr01 = 20;` vor dem `if` (neu analysieren) |
| 8 | 82 | SCA193 | Namen in ASCII-Buchstaben schreiben: Amount | alle vier `Amоunt` (kyrillisches о) heißen `Amount` |
| 9 | 74 | SCA123 | Cast nach TStringList vor Free entfernen | `Lines.Free;` |
| 10 | 69 | SCA099 | Zweig in begin..end setzen | `end else begin Inc(FStats.Skipped); end;` (neu analysieren) |
| 11 | 65 | SCA063 | Leerraum am Zeilenende entfernen | – |
| 12 | 65 | SCA061 | Tabulatoren dieser Zeile durch Leerzeichen ersetzen | Einrückung mit Leerzeichen |
| 13 | 57 | SCA060 | "goto" durch Exit ersetzen | `then Exit;` – Marke `Done:` bleibt (Delphi meldet sie danach als ungenutzt) |
| 14 | 57 | SCA101 | Zweig in begin..end setzen | `if not FileExists(..) then begin Exit; end;` (neu analysieren) |
| 15 | 47, 44 | SCA064 | End klein schreiben / Begin klein schreiben | `end;` / `begin` |
| 16 | 41 | SCA188 | Bidi-Steuerzeichen entfernen (in Strings als #$-Code) | Kommentar ohne U+202E |
| 17 | 39 | SCA192 | Unsichtbare Zeichen entfernen (in Strings als #$-Code) | `'sku;quantity;price'#$200B` – jetzt sichtbar: der Kopfvergleich konnte nie stimmen |
| 18 | 36 | SCA071 | Schlüsselwort an Spalte 1 setzen | `implementation` an Spalte 1 |
| 19 | 29, 28 | SCA117 | Dokumentationsgerüst einfügen | `/// <summary></summary>` und `/// <param ...>` über `Stats` bzw. `ImportFile` (neu analysieren) |
| 20 | 9 | SCA007 | Unit Contnrs aus uses entfernen (ändert Verhalten) | `Contnrs` ist weg |
| 21 | 9 | Refactoring | uses: Windows -> Winapi.Windows, danach „uses: alle … Einträge qualifizieren“ | `Winapi.Windows, System.SysUtils, System.Classes` |

Hinweis zu 21: die uses-Aktionen stehen nur im Kontextmenü (Refactoring,
nicht in der Glühbirne); vor Schritt 20 sind es vier Einträge.

Hinweis zu 2: `OpenInExcel` (Zeile 186) ruft niemand auf, dazu meldet
SCA164 „Ungenutzte Routine OpenInExcel löschen“. Stehen lassen – die Hilfe
löschte die Routine samt der SCA068-Stelle; SCA164 zeigt Szene 5.

## Szene 4: uPriceCalculator.pas – Rechenfehler und Stilfragen

| # | Zeile | Fund | Aktion | Erwartung danach |
|---:|---:|---|---|---|
| 0 | 550 | SCA204 | Result statt GrossTotal schreiben | `Result := NetTotal(AOrder) * (1 + FTaxRate);` – dieselbe Hilfe steht auch an den beiden `ParcelCapacity :=`-Zeilen; dort bleibt rechts der Name (SCA205, Rekursion – von Hand `Result` schreiben) |
| 1 | 416 | SCA080 | Überflüssiges Exit entfernen | `Exit;` vor dem `end` von `Reset` ist weg; die Reihenfolge zu Schritt 2 ist egal, der Fund bleibt auch mit `initialization` dahinter |
| 2 | 407 | SCA167 | Randomize im initialization-Abschnitt aufrufen (ändert Verhalten) | neuer Abschnitt `initialization Randomize;` vor `end.` |
| 3 | 393 | SCA122 | raise; verwenden (Original-Stack-Trace bleibt) | `raise;` |
| 4 | 376 | SCA002 | raise; in den leeren except-Block einfügen (ändert Verhalten) | `except raise; end;` (neu analysieren) |
| 5 | 375 | SCA128 | FormatSettings ausdrücklich übergeben | `StrToFloat(AText, FormatSettings)` |
| 6 | 367 | SCA159 | Dem leeren Ausnahme-Handler "raise;" hinzufügen (ändert Verhalten) | `on E: EConvertError do raise;` |
| 7 | 352 | SCA120 | Exception auslösen (ändert Verhalten) | `raise EArgumentOutOfRangeException.Create(..)` |
| 8 | 345 | SCA083 | Leeres try/finally entfernen | Zuweisung ohne try (neu analysieren) |
| 9 | 342 | SCA169 | Bedingung außerhalb von Assert auswerten (ändert Verhalten) | `if not (ApplyVolumeDiscount(AOrder)) then Assert(False, ..)` – der Rabatt gilt jetzt auch im Release-Build |
| 10 | 328 | SCA018 | Letztes if in eine Wächter-Klausel mit Exit umwandeln | `if not Assigned(ACoupons) then Exit;`, Block eine Ebene flacher (neu analysieren) |
| 11 | 311 | SCA011 | Unerreichbaren Code löschen: 1 Zeile(n) | die Zeile hinter `Exit;` ist weg |
| 12 | 307 | SCA094 | Das überflüssige innere Klammerpaar entfernen | `if not (FRoundToFiveCents) then` |
| 13 | 299 | SCA144 | Statt des exakten Vergleichs SameValue verwenden (ändert Verhalten) | `SameValue(FDiscount, 0.5)` |
| 14 | 297 | SCA014 | Lokale Konstante für 30 einführen | `const MagicNr01 = 30;` (neu analysieren) |
| 15 | 295 | SCA144 | Statt des exakten Vergleichs IsZero verwenden (ändert Verhalten) | `IsZero(AWeightKg)` |
| 16 | 284 | SCA044 | Format() aus Verkettung bilden | `Group := Group + Format(' (%s %%)', [FloatToStr(FDiscount)]);` |
| 17 | 283 | SCA072 | Überflüssigen Vergleich mit True/False entfernen | `if not IsVip then` |
| 18 | 282 | SCA131 | IfThen durch if..then..else ersetzen (ändert Verhalten) | `if IsVip then Group := 'VIP' else Group := Format(..)` – der Format-Aufruf läuft nur noch im else (neu analysieren) |
| 19 | 271 | SCA128 | **TFormatSettings.Invariant übergeben** (zweiter Eintrag) | `DateToStr(Date, TFormatSettings.Invariant)` |
| 20 | 266 | SCA059 | FormatSettings ausdrücklich übergeben | `Format(.., [..], FormatSettings)` |
| 21 | 265 | SCA059 | TFormatSettings.Invariant übergeben (zweiter Eintrag) | dto. mit `Invariant` |
| 22 | 263 | SCA005 | von Hand: `AOrder.Items[I].UnitPrice` als drittes Argument ergänzen | Fund weg |
| 23 | 262 | SCA203 | Schleife 0 to AOrder.Items.Count - 1 laufen lassen (ändert Verhalten) | `0 to AOrder.Items.Count - 1` |
| 24 | 260 | SCA009 | Lines in einem try/finally-Block freigeben (ändert Verhalten) | `try .. finally Lines.Free; end;` (neu analysieren) |
| 25 | 250 | SCA127 | Stattdessen EArgumentException auslösen / zweiter Eintrag EInvalidOpException | eine der beiden Klassen statt `Exception` |
| 26 | 248 | SCA137 | AQuantity vor der Multiplikation nach Int64 umwandeln (ändert Verhalten) | `Int64(AQuantity) * AUnitCents` |
| 27 | 238 | SCA168 | else-Zweig mit Exception ergänzen (zweiter Eintrag; erster: leeres else) | `else raise EInvalidOpException.Create('Unhandled case');` (neu analysieren) |
| 28 | 231 | SCA202 | von Hand: `else if AQuantity <> 0 then` | Fund weg |
| 29 | 224 | SCA119 | Konstante in MAX_DISCOUNT umbenennen | Deklaration und Verwendung umbenannt |
| 30 | 222 | SCA148 | VolumeDiscount zur statischen Klassenmethode machen | `class function ..; static;` in Deklaration und Implementierung |
| 31 | 218 | SCA047 | Selbstzuweisung von FDiscount entfernen | Zeile weg (neu analysieren) |
| 32 | 214 | SCA098 | Bedingung direkt an FIsLargeOrder zuweisen | `FIsLargeOrder := Total > LARGE_ORDER_LIMIT;` (neu analysieren) |
| 33 | 212 | SCA074 | Bedingung als Assert-Meldung verwenden | `Assert(AOrder <> nil, 'AOrder <> nil')` |
| 34 | 210 | SCA053 | Ungenutzte Variable Unused entfernen | Deklaration weg (neu analysieren) |
| 35 | 204 | SCA066 | Leere Klammern entfernen | `Reset;` |
| 36 | 122 | SCA150 | Immer wahre Bedingung entfernen | nur noch der then-Block (neu analysieren) |
| 37 | 112 | SCA046 | "to" durch "downto" ersetzen (zweiter Eintrag: Schleifengrenzen vertauschen) | `for Tier := 3 downto 1 do` |
| 38 | 105 | SCA118 | Exception-Klasse in EVoucherError umbenennen | Deklaration und `raise` umbenannt |
| 39 | 101 | SCA079 | Mit dem vorigen const-Abschnitt zusammenlegen | ein `const`-Abschnitt (neu analysieren) |
| 40 | 99 | SCA069 | Ziffern mit "_" gruppieren | `100_000_000` (ab Delphi 11) |

`SCA007` für `System.Math` (Zeile 11) ist nach Schritt 13/15 erledigt –
SameValue und IsZero kommen aus System.Math. Wer es zeigen will: **vor**
Schritt 13.

## Szene 5: uOrderModel.pas – Klassen, Vererbung, Attribute

Oben in der Unit steht schon ein Datei-Marker
`// noinspection-file ClassPerFile, BeginEndRequired` – gutes Beispiel für
eine Team-Konvention.

| # | Zeile | Fund | Aktion | Erwartung danach |
|---:|---:|---|---|---|
| 1 | 530 | SCA164 | Ungenutzte Routine FormatSku löschen | Routine weg |
| 2 | 505 | SCA174 | TObjectList<TOrderItem> verwenden, damit die Liste ihre Elemente freigibt (ändert Verhalten) | Deklaration und `Create` umgestellt – das Leck ist weg |
| 3 | 485 | SCA076 | Gruppierte Deklaration aufteilen | `Sum: Integer;` / `Weight: Integer;` (neu analysieren) |
| 4 | 483 | SCA148 | CheckDigit zur statischen Klassenmethode machen | `class function CheckDigit(..): Integer; static;` |
| 5 | 474 | SCA121 | Result mit 0 initialisieren (ändert Verhalten) | `Result := 0;` – erklären: richtig wäre `Result := FTotal` am Ende (neu analysieren) |
| 6 | 462 | SCA086 | "out" für AItem durch "var" ersetzen | Deklaration (Zeile 181) und Implementierung |
| 7 | 457 | SCA126 | Assigned() statt Vergleich mit nil verwenden | `if Assigned(FCustomer) then` |
| 8 | 444 | SCA054 | Parameter ANotify mit "_" als absichtlich ungenutzt kennzeichnen | `_ANotify` – oder erklären: eigentlich ein Bug, der Parameter wird ignoriert |
| 9 | 434 | SCA170 | Parameter ASku als const deklarieren | `const ASku: string` in Deklaration und Implementierung |
| 10 | 407 | SCA093 | Zweiten doppelten inherited-Aufruf entfernen (ändert Verhalten) | ein `inherited;` (neu analysieren) |
| 11 | 366 | SCA085 | FreeAndNil(FAddress) verwenden | `FreeAndNil(FAddress);` (neu analysieren) |
| 12 | 364 | SCA084 | Überflüssigen Vergleich mit nil entfernen | `if Assigned(FAddress) then` |
| 13 | 358 | SCA196 | Result zuerst initialisieren: Result := '' (ändert Verhalten) | `Result := '';` als erste Anweisung (neu analysieren) |
| 14 | 345 | SCA125 | Leeres Override Changed entfernen | Deklaration und Implementierung weg (neu analysieren) |
| 15 | 326 | SCA097 | inherited als Letztes im Destruktor aufrufen (ändert Verhalten) | `inherited;` vor `end` |
| 16 | 315 | SCA020 | Leeren Rumpf als beabsichtigt kennzeichnen (zweiter Eintrag: ENotImplemented auslösen) | `// intentionally empty` |
| 17 | 308 | SCA096 | inherited Create als Erstes im Konstruktor aufrufen | `inherited Create;` (neu analysieren) |
| 18 | 288 | SCA118 | Exception-Klasse in EQuantityError umbenennen | alle `raise QuantityError` mit |
| 19 | 210 | SCA183 | Leerzeile nach dem Attribut entfernen | – |
| 20 | 208 | SCA179 | Grund zu [Ignore] hinzufügen | `[Ignore('reason')]` |
| 21 | 206 | SCA180 | Doppeltes Attribut entfernen | ein `[Exported]` |
| 22 | 203 | SCA181 | Dem Attribut einen Kategorienamen geben | `[Category('category')]` |
| 23 | 170 | SCA087 | Leeren Sichtbarkeitsabschnitt entfernen | `protected` weg (neu analysieren) |
| 24 | 153 | SCA149 | "override;" an die Deklaration anfügen (ändert Verhalten) | `LineTotal` überschreibt jetzt – der Rabatt wirkt auch über `TOrderItem`-Variablen |
| 25 | 116 | SCA106 | Methodennamen als MarkAsVip schreiben | Deklaration und Implementierung |
| 26 | 103 | SCA147 | Ungenutzte private Methode NormalizedName löschen | Deklaration und Implementierung weg (neu analysieren) |
| 27 | 73 | SCA076 | Gruppierte Deklaration aufteilen | `FStreet: string;` / `FCity: string;` |
| 28 | 71 | SCA075 | (TObject) aus der Klassendeklaration entfernen | `TAddress = class` |
| 29 | 52 | SCA197 | Neue GUID einfügen | `['{...}']` unter `IOrderObserver = interface` |

## Szene 6: uOrderRepository.pas – Datenbank, Sperren, Threads

| # | Zeile | Fund | Aktion | Erwartung danach |
|---:|---:|---|---|---|
| 1 | 423 | SCA113 | Worker.Start statt Resume verwenden | `Worker.Start;` |
| 2 | 266 | SCA001 | Csv in einem try/finally-Block freigeben (ändert Verhalten) | `Csv.Free` im finally (neu analysieren). Derselbe Eintrag hängt auch am SCA009-Fund dieser Zeile |
| 3 | 257 | SCA065 | NOSONAR durch einen Marker "noinspection All" ersetzen (ändert Verhalten) | `// noinspection All` über der Zeile (neu analysieren) |
| 4 | 256, 254 | SCA003 | Parametrisierte Vorlage in die Zwischenablage | Zwischenablage zeigen: `WHERE order_ref = :OrderRef` und `FQuery.ParamByName('OrderRef').Value := AOrderRef;` – die Aktion schreibt selbst nie in den Editor |
| 5 | 254 | SCA003 | Stelle zeigen | markiert genau die Zuweisung |
| 6 | 253 | SCA165 | Wirkungslosen Unterdrück-Marker entfernen | `// noinspection NilDeref` weg (neu analysieren) |
| 7 | 248 | SCA082 | Überzähliges Semikolon entfernen | `FQuery.ExecSQL;` |
| 8 | 246 | SCA199 | Parameternamen "City" aus dem SQL verwenden (ändert Verhalten) | `ParamByName('City')` |
| 9 | 237 | SCA112 | FQuery.FieldByName('amount') vor die Schleife ziehen (ändert Verhalten) | `var FldAmount := ..` vor `while` (neu analysieren) |
| 10 | 224 | SCA111 | FQuery.ParamByName('quantity') vor die Schleife ziehen (ändert Verhalten) | `var PrmQuantity := ..` vor `for` (neu analysieren) |
| 11 | 223, 222 | SCA111 | dto. für `sku` und `order_no` | je eine Zeile mehr (jeweils neu analysieren) |
| 12 | 218 | SCA017 | Debug-Ausgabe in {$IFDEF DEBUG} setzen (ändert Verhalten) | **erst nach 10/11**: eine Direktive in der Routine sperrt SCA111 (neu analysieren) |
| 13 | 205 | SCA109 | Sperre FCacheLock in einem try/finally-Block freigeben (ändert Verhalten) | `try .. finally FCacheLock.Leave; end;` (neu analysieren) |
| 14 | 198 | SCA153 | Sperre FStatsLock in einem try/finally-Block freigeben (ändert Verhalten) | dto. mit `Release` (neu analysieren) |
| 15 | 171 | SCA003 | Parametrisierte Vorlage in die Zwischenablage | `WHERE city = :City ORDER BY name` und `ParamByName('City').Value := ACity;` |
| 16 | 160 | SCA139 | FreeAndNil(FQuery) verwenden | `FreeAndNil(FQuery);` – sonst gäbe der Destruktor die Query ein zweites Mal frei |
| 17 | 114 | SCA156 | Puffer Buffer in einem try/finally-Block freigeben (ändert Verhalten) | `try .. finally FreeMem(Buffer); end;` (neu analysieren) |
| 18 | 99 | SCA115 | https:// statt http:// verwenden (ändert Verhalten) | `'https://orders.example-shop.com/...'` |
| 19 | 18 | SCA007 | Unit Data.DB aus uses entfernen (ändert Verhalten) | `Data.DB,` weg |

## Szene 7: uOrderForm.pas und .dfm – das Formular

| # | Zeile | Fund | Aktion | Erwartung danach |
|---:|---:|---|---|---|
| 1 | 183 | SCA044 | Format() aus Verkettung bilden | `Format('Orders: %d - total %s - average %s', [Count, CurrToStr(Total), ..])` |
| 2 | 174 | SCA128 | FormatSettings ausdrücklich übergeben | `CurrToStr(.., FormatSettings)` |
| 3 | 154 | SCA077 | Leeres "with ... do begin end" durch den Aufruf ersetzen | `lvOrders.Items.AddItem(nil);` (neu analysieren) |
| 4 | 114 | SCA017 | Debug-Ausgabe löschen (zweiter Eintrag) – oder in {$IFDEF DEBUG} setzen | die ShowMessage-Zeile ist weg |
| 5 | 81 | SCA003 | Parametrisierte Vorlage in die Zwischenablage | `WHERE customer = :Edit1Text` – die Hochkommas um den Wert fallen weg; SCA033 im DFM zeigt dieselbe Lücke aus Formularsicht |

Die sechs SCA007-Funde in Zeile 8–14 (FireDAC- und VCL-Units) **nicht**
anwenden, sondern erklären: der uses-Check ist heuristisch, darum
„(ändert Verhalten)“; die IDE trägt die FireDAC-Units beim Speichern des
Formulars wieder ein. Die DFM-Funde (Szene 2, auch SCA026 `:101`) haben
keine Code-Aktion –
Doppelklick öffnet die .dfm an der Stelle.

## Szene 8: Code-Aktionen ohne Fund

Rechtsklick mit dem Caret auf der Stelle – im Editor-Kontextmenü stehen
die Code-Aktionen am Caret, auch auf einer Zeile ohne Fund. Alle zehn Arten
(`TRdxContextKind` in `reDelphix/source/uRdxContextRunner.pas`) haben im
Demo eine Stelle. Status **Probe** = schon bisher im Drehbuch und mit der
Angebotsprobe belegt, **gelesen** = gegen die Auslöseregeln im Code
geprüft, aber noch nicht in Probe oder IDE angeboten gesehen – einmal in
der IDE gegenprüfen.

| # | Code-Aktion (Menütext) | Stelle | Caret | Erwartung danach | Status |
|---:|---|---|---|---|---|
| 1 | Lokale Konstante für 11 einführen (bzw. für 0.19, 5.90) | `uOrderModel.pas:495` `Result := (11 - Sum mod 11) mod 11;`, `uPriceCalculator.pas:202` `FTaxRate := 0.19;`, `uPriceCalculator.pas:302` `Result := 5.90;` | auf der Zahl (in `:495` auf der ersten `11`) | nur dieses Literal wird `MagicNr01`; in `:302` bekommt der `else`-Zweig `begin..end` | Probe |
| 2 | Importer in einem try/finally-Block freigeben (ändert Verhalten) | `uOrderForm.pas:104` `Importer := TLegacyImporter.Create;` | in der Zeile | das `try` kommt erst nach `Order := TOrder.Create(..)`; wirft `LoadCustomer`, leckt der Importer – kein Fund meldet das | Probe |
| 3 | Format() aus Verkettung bilden | `uOrderModel.pas:321` `Result := ClassName + ' #' + IntToStr(FId);`, `uPriceCalculator.pas:271` `Lines.Add('Printed: ' + DateToStr(Date));` | irgendwo in der Kette | `Format('%s #%d', [ClassName, FId])` (`FId` ist als `Integer` belegt) bzw. `Lines.Add(Format('Printed: %s', [DateToStr(Date)]))` | Probe |
| 4 | if umkehren (then und else tauschen) | `uOrderModel.pas:468` `if Result then` (FindItem), `uPriceCalculator.pas:299` `if FDiscount = 0.5 then`, `uPriceCalculator.pas:648` `if AOrderCount >= 100 then` | auf `if` oder `then` | Bedingung verneint (`if not Result then`, `if not (FDiscount = 0.5) then`), Zweige getauscht | gelesen |
| 5 | Letztes if in eine Wächter-Klausel mit Exit umwandeln | `uOrderModel.pas:333` `if FName <> AValue then` (SetName) | auf `if` oder `then` | `if not (FName <> AValue) then Exit;`, der Block eine Ebene flacher | gelesen |
| 6 | De Morgan auf "or" anwenden | `uOrderModel.pas:411` `if (FDiscountPercent < 0) or (FDiscountPercent > 100) then` | auf `or` | die Kette wird `not (… and …)` mit verneinten Gliedern | gelesen |
| 7 | Seiten von "<=" tauschen | `uOrderModel.pas:396` `if FQuantity <= 0 then` | auf `<=` | `if 0 >= FQuantity then` | gelesen |
| 8 | if am "and" teilen | `uOrderForm.pas:140` `if (Key = VK_DELETE) and Assigned(lvOrders.Selected) then` | auf `and` | zwei geschachtelte `if` | gelesen |
| 9 | Mit dem inneren if zusammenfügen (and) | `uOrderModel.pas:457` `if FCustomer <> nil then` / `if Assigned(FCustomer.Address) then` | auf dem äußeren `if` oder `then` | ein `if (FCustomer <> nil) and Assigned(FCustomer.Address) then` | gelesen |
| 10 | Verkettungen im Formatter-Bereich nach jedem "+" umbrechen | `uOrderRepository.pas:170`–`172` (`{(*}` … `{*)}` um die SQL-Verkettung in `CustomerIdsInCity`) | irgendwo im Bereich, Markerzeilen eingeschlossen | ein Operand je Zeile, das `+` am Zeilenende, Einzug + 2 Leerzeichen; die Funde SCA003/SCA044/SCA152 der Zeile bleiben | gelesen |

Hinweise:

- Zu 1: Triviale Zahlen wie in `Weight := 2;` (`uOrderModel.pas:488`)
  bieten nichts an – dieselbe Menge, die SCA014 durchlässt (0, 1, 2, -1,
  10, 100, Zweierpotenzen bis 1024).
- Zu 2: Derselbe Menütext wie die Fund-Hilfe SCA009, mit dem Namen aus
  der Zeile.
- Zu 3: Auf `uPriceCalculator.pas:284` (SCA044, Szene 4) steht der Eintrag
  nur einmal – die Code-Aktion trägt den Menütext der Fund-Hilfe und fällt
  dahinter weg. Ein triviales `'a' + B` (ein Literal, keine Umwandlung)
  bietet nichts an.
- Zu 5: Die Wächter-Klausel gibt es nur für das letzte
  `if A then begin B end` einer Routine; auf anderen `if` steht kein
  Eintrag.
- Zu 10: Vorher zeigen, was passiert ist: die Verkettung stand einmal von
  Hand umbrochen da, Strg+D (Delphi-Formatter bis Delphi 12) kennt die
  Marker nicht und hat sie in eine Zeile gezogen. Danach Strg+D nicht mehr
  drücken – erst GExperts, CnWizards und JCF halten den Bereich ein. Der
  Bereich um `OLD_COLUMNS` in `uLegacyImport.pas` bietet die Aktion nicht
  an, solange sein Marker `{ (*}` falsch geschrieben ist (Szene 3, #2a).

## Szene 9: Abschluss

- Neu scannen: die Funde mit Hilfe sind weg; übrig bleiben die ohne Hilfe
  (DFM, die Regeln aus Anhang B, Heuristiken mit niedriger Konfidenz wie
  SCA052 „Dead public API“).
- Kompilieren: übersetzt weiterhin (die Hilfen prüfen vor dem Schreiben,
  dass das Ergebnis bedeutungsgleich bzw. gekennzeichnet ist).
- Zurücksetzen für den nächsten Durchlauf: `git checkout examples/ShowcaseDemo`.

## Anhang A: Abdeckung aller Code-Aktionen zu einem Fund

Nachgewiesen mit der reDelphix-Angebotsprobe (echter Code von
`uRdxFixTable`, `uRdxFixRunner`, `uRdxRecipeRunner` und aller Planer unter
FPC 3.2.2, SCA044 über `RdxCorpusProbe.exe`) auf dem SARIF des Laufs
`--profile strict --min-severity hint`, `MinConfidence=low`. Stand der
Probe: 106 von 107 angeboten. Seither haben auch SCA204 (`GrossTotal :=`)
und SCA206 (Marker mit Leerraum; die Hilfe kam mit der Regel dazu) eine
Stelle – **108 von 108**. Die beiden sind nur gegen die Planer gelesen
(Status **gelesen**), noch nicht durch die Probe gelaufen. Die Zeilen der
Spalte „Stelle“ sind maschinell auf die heutige Fassung nachgezogen; die
Zahlen „weitere / gesperrt“ stammen aus dem Probelauf, neue Funde einer
Regel seither stehen in Klammern. Status **ja** = der echte
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
| 1 | SCA001 | 1 | Csv in einem try/finally-Block freigeben (ä. V.) | uOrderRepository.pas:266 | ja | 0 / 0 (+1 neu: FErrors, ungeprüft) |
| 2 | SCA002 | 1 | raise; in den leeren except-Block einfügen (ä. V.) | uPriceCalculator.pas:376 | ja | 0 / 0 |
| 3 | SCA007 | 1 | Unit Contnrs aus uses entfernen (ä. V.) | uLegacyImport.pas:9 | ja* | 8 / 0 |
| 4 | SCA009 | 1 | Csv in einem try/finally-Block freigeben (ä. V.) | uOrderRepository.pas:266 | ja | 1 / 0 |
| 5 | SCA011 | 1 | Unerreichbaren Code löschen: 1 Zeile(n) | uPriceCalculator.pas:311 | ja | 0 / 0 |
| 6 | SCA014 | 1 | Lokale Konstante für 3 einführen | uLegacyImport.pas:93 | ja | 2 / 1 |
| 7 | SCA017 | 1 | Debug-Ausgabe in {$IFDEF DEBUG} setzen (ä. V.) | uOrderForm.pas:114 | ja | 2 / 0 |
| 8 | SCA017 | 2 | Debug-Ausgabe löschen (ä. V.) | uOrderForm.pas:114 | ja | 2 / 0 |
| 9 | SCA018 | 1 | Letztes if in eine Wächter-Klausel mit Exit umwandeln | uPriceCalculator.pas:328 | ja | 0 / 0 (+1 neu: OrderProblem, ungeprüft) |
| 10 | SCA020 | 1 | Leeren Rumpf als beabsichtigt kennzeichnen | uOrderModel.pas:315 | ja | 0 / 0 |
| 11 | SCA020 | 2 | ENotImplemented im leeren Rumpf auslösen (ä. V.) | uOrderModel.pas:315 | ja | 0 / 0 |
| 12 | SCA046 | 1 | "to" durch "downto" ersetzen (ä. V.) | uPriceCalculator.pas:112 | ja | 0 / 0 |
| 13 | SCA046 | 2 | Schleifengrenzen vertauschen (ä. V.) | uPriceCalculator.pas:112 | ja | 0 / 0 |
| 14 | SCA047 | 1 | Selbstzuweisung von FDiscount entfernen | uPriceCalculator.pas:218 | ja* | 0 / 0 |
| 15 | SCA053 | 1 | Ungenutzte Variable Unused entfernen | uPriceCalculator.pas:210 | ja | 0 / 0 |
| 16 | SCA054 | 1 | Parameter ANotify mit "_" als absichtlich ungenutzt kennzeichnen | uOrderModel.pas:444 | ja | 0 / 0 |
| 17 | SCA059 | 1 | FormatSettings ausdrücklich übergeben | uPriceCalculator.pas:263 | ja | 2 / 0 |
| 18 | SCA059 | 2 | TFormatSettings.Invariant übergeben (ä. V.) | uPriceCalculator.pas:263 | ja | 2 / 0 |
| 19 | SCA060 | 1 | "goto" durch Exit ersetzen | uLegacyImport.pas:57 | ja | 0 / 0 |
| 20 | SCA061 | 1 | Tabulatoren dieser Zeile durch Leerzeichen ersetzen | uLegacyImport.pas:65 | ja | 0 / 0 |
| 21 | SCA063 | 1 | Leerraum am Zeilenende entfernen | uLegacyImport.pas:65 | ja | 0 / 0 |
| 22 | SCA064 | 1 | Begin klein schreiben | uLegacyImport.pas:44 | ja | 1 / 0 |
| 23 | SCA065 | 1 | NOSONAR durch einen Marker "noinspection All" ersetzen (ä. V.) | uOrderRepository.pas:257 | ja | 0 / 0 |
| 24 | SCA066 | 1 | Leere Klammern entfernen | uPriceCalculator.pas:204 | ja* | 0 / 0 |
| 25 | SCA068 | 1 | Überzähliges Komma entfernen | uLegacyImport.pas:188 | ja | 0 / 0 |
| 26 | SCA069 | 1 | Ziffern mit "_" gruppieren | uPriceCalculator.pas:99 | ja | 0 / 0 |
| 27 | SCA070 | 1 | Auskommentierten Code löschen | uLegacyImport.pas:99 | ja | 0 / 0 |
| 28 | SCA071 | 1 | Schlüsselwort an Spalte 1 setzen | uLegacyImport.pas:36 | ja | 0 / 0 |
| 29 | SCA072 | 1 | Überflüssigen Vergleich mit True/False entfernen | uPriceCalculator.pas:283 | ja* | 0 / 0 |
| 30 | SCA074 | 1 | Bedingung als Assert-Meldung verwenden | uPriceCalculator.pas:212 | ja* | 0 / 0 |
| 31 | SCA075 | 1 | (TObject) aus der Klassendeklaration entfernen | uOrderModel.pas:71 | ja | 0 / 0 |
| 32 | SCA076 | 1 | Gruppierte Deklaration aufteilen | uOrderModel.pas:73 | ja | 1 / 0 |
| 33 | SCA077 | 1 | Leeres "with ... do begin end" durch den Aufruf ersetzen | uOrderForm.pas:154 | ja | 0 / 0 |
| 34 | SCA079 | 1 | Mit dem vorigen const-Abschnitt zusammenlegen | uPriceCalculator.pas:101 | ja | 0 / 0 |
| 35 | SCA080 | 1 | Überflüssiges Exit entfernen | uPriceCalculator.pas:416 | ja | 0 / 0 |
| 36 | SCA082 | 1 | Überzähliges Semikolon entfernen | uOrderRepository.pas:248 | ja | 0 / 0 |
| 37 | SCA083 | 1 | Leeres try/finally entfernen | uPriceCalculator.pas:345 | ja | 0 / 0 |
| 38 | SCA084 | 1 | Überflüssigen Vergleich mit nil entfernen | uOrderModel.pas:364 | ja* | 0 / 0 |
| 39 | SCA085 | 1 | FreeAndNil(FAddress) verwenden | uOrderModel.pas:366 | ja* | 0 / 0 |
| 40 | SCA086 | 1 | "out" für AItem durch "var" ersetzen (ä. V.) | uOrderModel.pas:181 | ja | 1 / 0 |
| 41 | SCA087 | 1 | Leeren Sichtbarkeitsabschnitt entfernen | uOrderModel.pas:170 | ja | 0 / 0 |
| 42 | SCA088 | 1 | begin durch initialization ersetzen | uLegacyImport.pas:191 | ja | 0 / 0 |
| 43 | SCA093 | 1 | Zweiten doppelten inherited-Aufruf entfernen (ä. V.) | uOrderModel.pas:407 | ja | 0 / 0 |
| 44 | SCA093 | 2 | Ersten doppelten inherited-Aufruf entfernen (ä. V.) | uOrderModel.pas:407 | ja | 0 / 0 |
| 45 | SCA094 | 1 | Das überflüssige innere Klammerpaar entfernen | uPriceCalculator.pas:307 | ja | 0 / 0 |
| 46 | SCA096 | 1 | inherited Create als Erstes im Konstruktor aufrufen | uOrderModel.pas:308 | ja | 0 / 0 |
| 47 | SCA097 | 1 | inherited als Letztes im Destruktor aufrufen (ä. V.) | uOrderModel.pas:326 | ja | 0 / 0 |
| 48 | SCA098 | 1 | Bedingung direkt an FIsLargeOrder zuweisen | uPriceCalculator.pas:214 | ja* | 0 / 0 |
| 49 | SCA099 | 1 | Zweig in begin..end setzen | uLegacyImport.pas:69 | ja | 0 / 0 |
| 50 | SCA101 | 1 | Zweig in begin..end setzen | uLegacyImport.pas:57 | ja | 1 / 0 |
| 51 | SCA106 | 1 | Methodennamen als MarkAsVip schreiben | uOrderModel.pas:116 | ja | 0 / 0 |
| 52 | SCA109 | 1 | Sperre FCacheLock in einem try/finally-Block freigeben (ä. V.) | uOrderRepository.pas:205 | ja | 0 / 0 |
| 53 | SCA111 | 1 | FQuery.ParamByName('order_no') vor die Schleife ziehen (ä. V.) | uOrderRepository.pas:222 | ja* | 2 / 0 |
| 54 | SCA112 | 1 | FQuery.FieldByName('amount') vor die Schleife ziehen (ä. V.) | uOrderRepository.pas:237 | ja* | 0 / 0 |
| 55 | SCA113 | 1 | Worker.Start statt Resume verwenden | uOrderRepository.pas:423 | ja | 0 / 0 |
| 56 | SCA115 | 1 | https:// statt http:// verwenden (ä. V.) | uOrderRepository.pas:99 | ja | 0 / 0 |
| 57 | SCA117 | 1 | Dokumentationsgerüst einfügen | uLegacyImport.pas:28 | ja | 1 / 0 |
| 58 | SCA118 | 1 | Exception-Klasse in EQuantityError umbenennen | uOrderModel.pas:288 | ja | 1 / 0 |
| 59 | SCA119 | 1 | Konstante in MAX_DISCOUNT umbenennen | uPriceCalculator.pas:224 | ja | 0 / 0 |
| 60 | SCA120 | 1 | Exception auslösen (ä. V.) | uPriceCalculator.pas:352 | ja | 0 / 0 |
| 61 | SCA121 | 1 | Result mit 0 initialisieren (ä. V.) | uOrderModel.pas:474 | ja | 0 / 0 |
| 62 | SCA122 | 1 | raise; verwenden (Original-Stack-Trace bleibt) | uPriceCalculator.pas:393 | ja | 0 / 0 |
| 63 | SCA123 | 1 | Cast nach TStringList vor Free entfernen | uLegacyImport.pas:74 | ja* | 0 / 0 |
| 64 | SCA125 | 1 | Leeres Override Changed entfernen | uOrderModel.pas:345 | ja | 0 / 0 |
| 65 | SCA126 | 1 | Assigned() statt Vergleich mit nil verwenden | uOrderModel.pas:457 | ja* | 0 / 2 |
| 66 | SCA127 | 1 | Stattdessen EArgumentException auslösen (falsches Argument) (ä. V.) | uPriceCalculator.pas:250 | ja | 0 / 0 |
| 67 | SCA127 | 2 | Stattdessen EInvalidOpException auslösen (unzulässiger Zustand) (ä. V.) | uPriceCalculator.pas:250 | ja | 0 / 0 |
| 68 | SCA128 | 1 | FormatSettings ausdrücklich übergeben | uOrderForm.pas:125 | ja | 7 / 0 |
| 69 | SCA128 | 2 | TFormatSettings.Invariant übergeben (ä. V.) | uOrderForm.pas:125 | ja | 7 / 0 |
| 70 | SCA131 | 1 | IfThen durch if..then..else ersetzen (ä. V.) | uPriceCalculator.pas:282 | ja* | 0 / 0 |
| 71 | SCA137 | 1 | AQuantity vor der Multiplikation nach Int64 umwandeln (ä. V.) | uPriceCalculator.pas:248 | ja* | 0 / 0 |
| 72 | SCA139 | 1 | FreeAndNil(FQuery) verwenden | uOrderRepository.pas:160 | ja* | 0 / 0 |
| 73 | SCA144 | 1 | Statt des exakten Vergleichs IsZero verwenden (ä. V.) | uPriceCalculator.pas:295 | ja* | 1 / 0 |
| 74 | SCA147 | 1 | Ungenutzte private Methode NormalizedName löschen | uOrderModel.pas:103 | ja | 0 / 0 |
| 75 | SCA148 | 1 | FieldLength zur statischen Klassenmethode machen | uLegacyImport.pas:110 | ja | 4 / 0 |
| 76 | SCA149 | 1 | "override;" an die Deklaration anfügen (ä. V.) | uOrderModel.pas:153 | ja | 0 / 0 |
| 77 | SCA150 | 1 | Immer wahre Bedingung entfernen | uPriceCalculator.pas:122 | ja | 0 / 0 |
| 78 | SCA153 | 1 | Sperre FStatsLock in einem try/finally-Block freigeben (ä. V.) | uOrderRepository.pas:198 | ja | 0 / 0 |
| 79 | SCA154 | 1 | SizeOf(Integer) statt der Zeigergröße verwenden (ä. V.) | uLegacyImport.pas:117 | ja* | 0 / 0 |
| 80 | SCA156 | 1 | Puffer Buffer in einem try/finally-Block freigeben (ä. V.) | uOrderRepository.pas:114 | ja | 0 / 0 |
| 81 | SCA159 | 1 | Dem leeren Ausnahme-Handler "raise;" hinzufügen (ä. V.) | uPriceCalculator.pas:367 | ja | 0 / 0 |
| 82 | SCA161 | 1 | Die 32-Bit-Casts durch NativeInt/NativeUInt ersetzen (ä. V.) | uLegacyImport.pas:112 | ja | 0 / 0 |
| 83 | SCA164 | 1 | Ungenutzte Routine FormatSku löschen | uOrderModel.pas:530 | ja | 1 / 0 |
| 84 | SCA167 | 1 | Randomize im initialization-Abschnitt aufrufen (ä. V.) | uPriceCalculator.pas:407 | ja | 0 / 0 |
| 85 | SCA168 | 1 | Leeren else-Zweig ergänzen | uPriceCalculator.pas:238 | ja | 0 / 0 |
| 86 | SCA168 | 2 | else-Zweig mit Exception ergänzen (ä. V.) | uPriceCalculator.pas:238 | ja | 0 / 0 |
| 87 | SCA169 | 1 | Bedingung außerhalb von Assert auswerten (ä. V.) | uPriceCalculator.pas:342 | ja | 0 / 0 |
| 88 | SCA170 | 1 | Parameter ASku als const deklarieren | uOrderModel.pas:434 | ja | 0 / 0 |
| 89 | SCA174 | 1 | TObjectList<TOrderItem> verwenden, damit die Liste ihre Elemente freigibt (ä. V.) | uOrderModel.pas:505 | ja | 1 / 0 |
| 90 | SCA179 | 1 | Grund zu [Ignore] hinzufügen | uOrderModel.pas:208 | ja | 0 / 0 |
| 91 | SCA180 | 1 | Doppeltes Attribut entfernen | uOrderModel.pas:206 | ja | 0 / 0 |
| 92 | SCA181 | 1 | Dem Attribut einen Kategorienamen geben | uOrderModel.pas:203 | ja | 0 / 0 |
| 93 | SCA183 | 1 | Leerzeile nach dem Attribut entfernen | uOrderModel.pas:210 | ja | 0 / 0 |
| 94 | SCA188 | 1 | Bidi-Steuerzeichen entfernen (in Strings als #$-Code) | uLegacyImport.pas:41 | ja | 0 / 0 |
| 95 | SCA192 | 1 | Unsichtbare Zeichen entfernen (in Strings als #$-Code) | uLegacyImport.pas:39 | ja | 0 / 0 |
| 96 | SCA193 | 1 | Namen in ASCII-Buchstaben schreiben: Amount | uLegacyImport.pas:82 | ja | 0 / 0 |
| 97 | SCA196 | 1 | Result zuerst initialisieren: Result := '' (ä. V.) | uOrderModel.pas:358 | ja | 0 / 0 |
| 98 | SCA197 | 1 | Neue GUID einfügen | uOrderModel.pas:52 | ja | 0 / 0 |
| 99 | SCA199 | 1 | Parameternamen "City" aus dem SQL verwenden (ä. V.) | uOrderRepository.pas:246 | ja | 0 / 0 |
| 100 | SCA203 | 1 | Schleife 0 to AOrder.Items.Count - 1 laufen lassen (ä. V.) | uPriceCalculator.pas:262 | ja | 0 / 0 |
| 101 | SCA204 | 1 | Result statt GrossTotal schreiben | uPriceCalculator.pas:550 | gelesen | 2 / 0 |
| 102 | SCA206 | 1 | Formatter-Marker exakt schreiben | uLegacyImport.pas:128 | gelesen | 0 / 0 |
| 103 | Anbieter | - | Format() aus Verkettung bilden | uOrderForm.pas:183 | ja | 1 / 0 |
| 104 | Anbieter | - | Hier / In dieser Datei unterdrücken | uLegacyImport.pas:8 | ja | 386 / 1 (+71 Funde seither, ungeprüft) |
| 105 | Anbieter | - | Parametrisierte Vorlage in die Zwischenablage | uOrderForm.pas:81 | ja* | 3 / 0 |
| 106 | Anbieter | - | Stelle zeigen | uOrderForm.pas:183 | ja | 5 / 0 |
| 107 | Anbieter | - | Wirkungslosen Unterdrück-Marker entfernen | uOrderRepository.pas:253 | ja | 0 / 0 |
| 108 | Anbieter | - | uses-Einträge qualifizieren (uses: X -> Scope.X / alle Einträge) | uLegacyImport.pas:8 | ja* | 5 / 1 |

## Anhang B: Regeln, die nur mit ihrem Fund gezeigt werden

Jede Regel, die sich mit übersetzbarem Delphi-Code zeigen lässt und bis
dahin im Demo keinen Fund hatte, hat jetzt mindestens einen (gemessen
mit demselben Lauf wie Szene 0; Zeilen maschinell aus dem SARIF). Der
Kommentar über der Stelle erklärt, was faul ist. SCA204 und SCA206
haben zusätzlich eine Hilfe (Anhang A, Szene 4 #0, Szene 3 #2a), die
übrigen keine.

Ohne Fund bleibt **SCA175** AnonMethodCaptureLoopVar: eine anonyme
Methode, die die Variable einer for-Schleife fängt, übersetzt Delphi
voraussichtlich nicht (E1019 „Die FOR-Schleifenvariable muss eine
einfache lokale Variable sein“). Ebenfalls nicht im Demo, weil sie kein
Delphi-Code im Projekt zeigen kann: die DFM-Regeln ohne Fund, die
Projekt- und Konfigurationsregeln (SCA023, SCA038, SCA194, SCA195,
SCA201), die Kodierungsregeln (SCA185–SCA187, SCA189–SCA191, SCA207)
und SCA006/SCA133, die nur auf nicht übersetzbaren Code ansprechen.

| Nr. | Regel | Name | Stelle | Stufe | Konfidenz |
|---:|---|---|---|---|---|
| 1 | SCA012 | LongMethod | uPriceCalculator.pas:422 | Hint | medium |
| 2 | SCA013 | LongParamList | uPriceCalculator.pas:41 | Hint | medium |
| 3 | SCA015 | DuplicateString | uPriceCalculator.pas:510 | Hint | medium |
| 4 | SCA021 | DuplicateBlock | uPriceCalculator.pas:510 | Hint | medium |
| 5 | SCA022 | CyclomaticComplexity | uPriceCalculator.pas:166, uPriceCalculator.pas:422, uPriceCalculator.pas:608 | Hint | medium |
| 6 | SCA048 | VirtualCallInCtor | uOrderModel.pas:586 | Error | high |
| 7 | SCA049 | LengthUnderflow | uPriceCalculator.pas:152 | Hint | low |
| 8 | SCA051 | CanBeProtected | uOrderModel.pas:257 | Hint | low |
| 9 | SCA055 | TautologicalBoolExpr | uPriceCalculator.pas:160 | Error | high |
| 10 | SCA058 | SqlDangerousStatement | uOrderRepository.pas:300 | Error | high |
| 11 | SCA067 | InlineAssembly | uLegacyImport.pas:138, uLegacyImport.pas:143 | Warning | high |
| 12 | SCA073 | EmptyInterface | uOrderModel.pas:57 | Hint | high |
| 13 | SCA078 | ExceptOnException | uOrderRepository.pas:291 | Hint | low |
| 14 | SCA089 | PublicField | uOrderModel.pas:227 | Hint | high |
| 15 | SCA091 | CaseStatementSize | uPriceCalculator.pas:168 | Hint | medium |
| 16 | SCA092 | EmptyFile | uOrderEvents.pas:1 | Hint | high |
| 17 | SCA095 | ConsecutiveVisibility | uOrderModel.pas:236 | Hint | high |
| 18 | SCA100 | PointerName | uOrderModel.pas:24 | Hint | high |
| 19 | SCA102 | NestedRoutine | uLegacyImport.pas:157 | Hint | high |
| 20 | SCA103 | FieldName | uOrderModel.pas:239 | Hint | high |
| 21 | SCA105 | InterfaceName | uOrderModel.pas:63 | Hint | high |
| 22 | SCA108 | SynchronizeInDestructor | uOrderRepository.pas:405 | Warning | high |
| 23 | SCA114 | TThreadDestroyWithoutTerminate | uOrderRepository.pas:440 | Hint | medium |
| 24 | SCA116 | DisabledTlsVerification | uOrderRepository.pas:368 | Error | high |
| 25 | SCA124 | InstanceInvokedConstructor | uOrderModel.pas:569 | Warning | medium |
| 26 | SCA129 | UnicodeToAnsiCast | uLegacyImport.pas:164 | Warning | high |
| 27 | SCA130 | CharToCharPointerCast | uLegacyImport.pas:169 | Error | high |
| 28 | SCA132 | ExceptionTooGeneral | uOrderRepository.pas:291 | Warning | high |
| 29 | SCA134 | UseAfterFree | uOrderRepository.pas:351 | Hint | low |
| 30 | SCA135 | AbstractNotImpl | uOrderModel.pas:263 | Hint | low |
| 31 | SCA136 | LeakInConstructor | uOrderModel.pas:578 | Warning | medium |
| 32 | SCA138 | GodClass | uPriceCalculator.pas:25 | Warning | medium |
| 33 | SCA140 | MultipleExit | uPriceCalculator.pas:422 | Warning | medium |
| 34 | SCA141 | LargeClass | uPriceCalculator.pas:25 | Warning | medium |
| 35 | SCA143 | MissingUnitHeader | uOrderStatus.pas:1 | Hint | high |
| 36 | SCA145 | ExceptInDestructor | uOrderModel.pas:594 | Warning | high |
| 37 | SCA146 | BooleanParam | uPriceCalculator.pas:495 | Hint | medium |
| 38 | SCA151 | ConstantReturn | uPriceCalculator.pas:539 | Hint | medium |
| 39 | SCA155 | WithMultipleTargets | uLegacyImport.pas:176 | Hint | high |
| 40 | SCA157 | SetLengthAppendInLoop | uOrderRepository.pas:313 | Warning | high |
| 41 | SCA158 | PointerArithmeticOnString | uLegacyImport.pas:166 | Hint | low |
| 42 | SCA160 | StringFromPointer | uLegacyImport.pas:173 | Warning | high |
| 43 | SCA162 | InsecureCryptoAlgorithm | uOrderRepository.pas:369 | Warning | medium |
| 44 | SCA163 | CommandInjection | uOrderForm.pas:191 | Hint | low |
| 45 | SCA166 | UninitVar | uPriceCalculator.pas:192 | Warning | medium |
| 46 | SCA171 | CompilerDirectiveScope | uLegacyImport.pas:120 | Warning | high |
| 47 | SCA173 | VariantTypeMisuse | uOrderRepository.pas:324 | Hint | medium |
| 48 | SCA176 | CognitiveComplexity | uPriceCalculator.pas:422 | Warning | high |
| 49 | SCA177 | ThreadFreeOnTerminateWithRef | uOrderRepository.pas:425 | Error | high |
| 50 | SCA178 | PathTraversal | uOrderForm.pas:201 | Error | high |
| 51 | SCA182 | AttributeTestFixtureWithoutTests | uOrderModel.pas:276 | Warning | high |
| 52 | SCA198 | DuplicateInterfaceGuid | uOrderModel.pas:57, uOrderModel.pas:63 | Warning | high |
| 53 | SCA204 | FunctionNameAsResult | uPriceCalculator.pas:550, uPriceCalculator.pas:560, uPriceCalculator.pas:562 | Hint | high |
| 54 | SCA205 | FunctionNameRecursion | uPriceCalculator.pas:562 | Error | high |
| 55 | SCA206 | FormatterMarker | uLegacyImport.pas:128 | Hint | medium |

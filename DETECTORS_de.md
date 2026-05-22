# Detektoren – Sonar-Prüfkatalog für das Static Code Analysis Tool for Delphi

Kanonische Liste der unterstützten und geplanten Code-Analyse-Regeln,
geordnet nach Schweregrad (Blocker → Critical → Major → Minor → Info).
Orientiert sich am Sonar-50er-Katalog plus eigene Bonus-Detektoren.

Status: ✅ implementiert | 🟡 teilweise | 🔲 offen

**Zusammenfassung:** 44 / 50 Sonar-Regel-Slots vollständig (Critical + Reliability + Maintainability + Minor weitestgehend abgedeckt) + 1 teilweise + 3 Bonus + **22 DFM-Detektoren** + **32 SonarDelphi-Migration** (SCA120-152) + **9 mORMot-Cluster** (SCA153-161) + ~60 SonarDelphi-kompatible Naming-/Formatting-Checks (SCA060-119) = **insgesamt 161 Detektor-Kinds** (geliefert von ~130 Pipeline-Klassen; einige Klassen emittieren mehrere Kinds — z. B. `uVisibilityCheck` → 4 Kinds, `uDfmAnalysisRunner` → 22 DFM-Kinds).

Verbleibende 5 offene Slots brauchen Typ-Inferenz / Flow-Analyse / Cross-Unit-Symbol-Resolution: #16 UninitVar, #20 ResultNotChecked, #22 CyclicUnitDep, #42 UnnecessaryCast, #49 DeprecatedAPI.

Die 21 Pascal-AST-Detektoren unten folgen der Sonar-50-Taxonomie.
Die **22 DFM-Detektoren** in eigenem Abschnitt sind formdatei-
spezifisch und gehören nicht in den Sonar-Katalog — sie arbeiten
auf dem DFM-Lexer + Parser + Komponentengraph (sowie FormBinder
für die Pascal-AST-Kopplung), eingeführt mit v0.10.0. Das
**SonarDelphi-Migration-Cluster (SCA120-131)** unten deckt Delphi-
spezifische Korrektheits-Checks ab, die SonarDelphi liefert und die
wir portiert haben. Die ~60 SCA060-119 Naming-/Formatting-Checks
sind hier noch nicht enumeriert — siehe [`rules/sca-rules.json`](rules/sca-rules.json)
für die kanonische Liste.

🇬🇧 [English version](DETECTORS.md)

---

## 🔴 Blocker (5)

| # | Regel | Beschreibung | Status | Unit |
|---|-------|-------------|--------|------|
| 1 | **MemoryLeak: Objekt nie freigegeben** | Objekt per `.Create` erzeugt, kein `Free`/`FreeAndNil`/`Destroy` im gesamten Methodenrumpf | ✅ | `uLeakDetector2` |
| 2 | **EmptyExcept: Leerer except-Block** | `except`-Block ohne ausführbare Anweisung – Exception wird stillschweigend verschluckt | ✅ | `uCodeSmells2` |
| 3 | **NilDeref: Nil-Zeiger ohne Prüfung** | Objekt-Feld oder Parameter wird ohne vorherige `Assigned()`-Prüfung dereferenziert | ✅ | `uNilDeref` |
| 4 | **SQLInjection: String-Konkatenation in SQL** | SQL-Befehl durch `+`-Verkettung mit Benutzereingabe – kein parametrisiertes Query | ✅ | `uSQLInjection` |
| 5 | **HardcodedSecret: Passwort/Token im Code** | Literal-Zuweisung an Variable deren Name `password`, `token`, `secret`, `key` enthält | ✅ | `uHardcodedSecret` |

---

## 🟠 Critical (10)

| # | Regel | Beschreibung | Status | Unit |
|---|-------|-------------|--------|------|
| 6 | **DivByZero: Division durch 0 möglich** | Integer-Division oder Modulo, bei der der Divisor 0 sein kann (keine Vorabprüfung) | ✅ | `uDivByZero` |
| 7 | **UseAfterFree: Objekt nach Free genutzt** | Variable wird nach `Free`/`FreeAndNil` ohne erneute Zuweisung weiterverwendet | ✅ | `uUseAfterFree` |
| 8 | **MissingFinally: Ressource ohne try/finally** | Objekt erstellt, Methode enthält try/except aber kein try/finally für Cleanup | ✅ | `uMissingFinally` |
| 9 | **FormatMismatch: Falsche Arg-Anzahl in Format()** | Anzahl der `%s`/`%d`-Platzhalter im Format-String stimmt nicht mit Argumentliste überein | ✅ | `uFormatMismatch` |
| 10 | **AbstractNotImpl: Abstrakte Methode nicht implementiert** | Konkrete Klasse erbt von abstrakter Basis, implementiert aber nicht alle `abstract`-Methoden | ✅ | `uAbstractNotImpl` (nur within-unit) |
| 11 | **ExceptionTooGeneral: Zu allgemeiner Exception-Typ** | `except on E: Exception` statt spezifischem Typ – verdeckt unerwartete Fehler | ✅ | `uExceptionTooGeneral` |
| 12 | **LeakInConstructor: Exception im Konstruktor ohne Cleanup** | Konstruktor kann nach partieller Objektinitialisierung eine Exception werfen ohne `Free` | ✅ | `uLeakInConstructor` |
| 13 | **MissingDestructor: Destruktor fehlt / Feld nicht freigegeben** | Klasse mit Objekt-Feldern: kein Destruktor oder Feld nicht in `Destroy` freigegeben | ✅ | `uFieldLeak` |
| 14 | **IntegerOverflow: Überlauf bei Arithmetik** | Multiplikation oder Potenz mit `Integer`/`Word` ohne vorherige Bereichsprüfung | ✅ | `uIntegerOverflow` (nur Int64-Ziel) |
| 15 | **RaiseWithoutClass: `raise` ohne Exception-Objekt** | Nacktes `raise` außerhalb eines `except`-Blocks – löst Access Violation aus | ✅ | `uRaiseOutsideExcept` |

---

## 🟡 Major – Zuverlässigkeit (10)

| # | Regel | Beschreibung | Status | Unit |
|---|-------|-------------|--------|------|
| 16 | **UninitVar: Uninitialisierte Variable** | Lokale Variable wird gelesen bevor sie in allen Codepfaden zugewiesen wurde | 🔲 | |
| 17 | **DeadCode: Unerreichbarer Code** | Anweisungen nach `Exit`, `Break`, `Continue` oder `raise` auf gleicher Ebene | ✅ | `uDeadCode` |
| 18 | **BoolAlwaysTrue: Boolean-Ausdruck immer wahr/falsch** | Vergleich wie `x >= 0` für `Cardinal` oder `Length(s) >= 0` – ergibt immer True | ✅ | `uBoolAlwaysTrue` (nur Length-Pattern) |
| 19 | **FloatEquality: Fließkomma-Vergleich mit =** | `if a = b` wobei `a` oder `b` vom Typ `Single`/`Double`/`Extended` ist | ✅ | `uFloatEquality` |
| 20 | **ResultNotChecked: Rückgabewert ignoriert** | Aufruf einer Funktion, deren Ergebnis (z. B. Fehlercode) nicht ausgewertet wird | 🔲 | |
| 21 | **MissingOverride: `override` fehlt** | Methode überschreibt eine `virtual`/`dynamic`-Methode der Elternklasse ohne `override` | ✅ | `uMissingOverride` (nur within-unit) |
| 22 | **CyclicUnitDep: Zyklische Unit-Abhängigkeit** | Unit A verwendet Unit B (interface), Unit B verwendet Unit A (interface) | 🔲 | |
| 23 | **ExceptInDestructor: Exception aus Destruktor** | Destruktor enthält Code der eine Exception auslösen kann ohne try/except | ✅ | `uExceptInDestructor` |
| 24 | **PublicFieldNoProperty: Öffentliches Feld statt Property** | `public`-Feld direkt exponiert statt über `property` mit Getter/Setter | ✅ | `uPublicField` |
| 25 | **FreeWithoutNil: Free ohne anschließendes Nil** | `obj.Free` ohne nachfolgendes `obj := nil` oder `FreeAndNil` – Dangling Pointer möglich | ✅ | `uFreeWithoutNil` |

---

## 🟡 Major – Wartbarkeit (10)

| # | Regel | Beschreibung | Status | Unit |
|---|-------|-------------|--------|------|
| 26 | **LongMethod: Methode zu lang** | Methoden-Rumpf überschreitet 50 ausführbare Zeilen | ✅ | `uLongMethod` |
| 27 | **TooManyParams: Zu viele Parameter** | Methode hat mehr als 5 Parameter | ✅ | `uLongParamList` |
| 28 | **CyclomaticComplexity: McCabe-Komplexität > 10** | Anzahl der Verzweigungspfade (`if`, `case`-Arm, `for`, `while`, `repeat`, `on`-Handler, `and`/`or`/`xor`) überschreitet 10 | ✅ | `uCyclomaticComplexity` |
| 29 | **DeepNesting: Verschachtelungstiefe > 4** | Code-Block ist mehr als 4 Ebenen tief eingerückt | ✅ | `uDeepNesting` |
| 30 | **DuplicateBlock: Duplizierter Code-Block** | Identischer Block (>10 Zeilen) erscheint mehrfach | 🟡 | `uDuplicateString` (nur Strings, nicht Blöcke) |
| 31 | **GodClass: Gottklasse** | Klasse hat mehr als 20 Methoden oder mehr als 15 Instanzfelder | ✅ | `uGodClass` |
| 32 | **MagicNumber: Magic Number ohne Konstante** | Numerisches Literal (außer 0 und 1) direkt im Code statt benannter Konstante | ✅ | `uMagicNumbers` |
| 33 | **BooleanParam: Boolean als Flag-Parameter** | Methode erhält `Boolean`-Parameter der intern als Verzweigung genutzt wird | ✅ | `uBooleanParam` |
| 34 | **MultipleExit: Mehr als 3 Exit-Punkte** | Methode enthält mehr als 3 `Exit`-Aufrufe | ✅ | `uMultipleExit` |
| 35 | **LargeClass: Klasse zu groß** | Unit mit einer Klasse überschreitet 500 Zeilen Implementierungscode | ✅ | `uLargeClass` |

---

## 🔵 Minor – Code Smells (10)

| # | Regel | Beschreibung | Status | Unit |
|---|-------|-------------|--------|------|
| 36 | **UnusedVar: Unbenutzte lokale Variable** | Variable im `var`-Block deklariert, aber nie gelesen oder nur geschrieben | ✅ | `uUnusedLocal` |
| 37 | **UnusedMethod: Unbenutzte private Methode** | Private Methode wird innerhalb der Unit nirgendwo aufgerufen | ✅ | `uUnusedPrivateMethod` |
| 38 | **UnusedUnit: Unit im uses nicht genutzt** | Unit im `uses`-Abschnitt, deren Symbole im Quelltext nicht referenziert werden | ✅ | `uUnusedUses` |
| 39 | **CommentedCode: Auskommentierter Code** | Block von auskommentiertem Pascal-Code (`//` oder `{ }`) ohne Erklärung | ✅ | `uCommentedOutCode` |
| 40 | **TodoComment: TODO/FIXME ohne Ticket** | Kommentar enthält `TODO`, `FIXME`, `HACK`, `XXX` ohne zugehörige Issue-Nummer | ✅ | `uTodoComment` |
| 41 | **EmptyMethod: Leere Methode** | Methode enthält ausschließlich `inherited` oder ist komplett leer | ✅ | `uEmptyMethod` |
| 42 | **UnnecessaryCast: Überflüssige Typumwandlung** | Cast auf denselben Typ oder auf direkten Vorfahren ohne Erweiterung | 🔲 | |
| 43 | **ConstantReturn: Methode gibt immer gleichen Wert zurück** | Alle Pfade einer Funktion liefern dasselbe Literal – sollte Konstante sein | ✅ | `uConstantReturn` |
| 44 | **LongLine: Zeile zu lang** | Zeile überschreitet 120 Zeichen | ✅ | `uTooLongLine` |
| 45 | **MixedIndent: Gemischte Einrückung (Tabs + Spaces)** | Zeile enthält sowohl Tabulator- als auch Leerzeichen-Einrückung | ✅ | `uTabulationCharacter` |

---

## ⚪ Info (5)

| # | Regel | Beschreibung | Status | Unit |
|---|-------|-------------|--------|------|
| 46 | **HardcodedString: Literal statt resourcestring** | Benutzer-sichtbarer String als Literal statt `resourcestring`-Deklaration | ✅ | `uHardcodedString` (Caption/Hint/Text + ShowMessage) |
| 47 | **UnsortedUses: uses nicht alphabetisch** | Einträge im `uses`-Abschnitt nicht in alphabetischer Reihenfolge | ✅ | `uUnsortedUses` |
| 48 | **MissingUnitHeader: Kein Unit-Beschreibungskommentar** | Unit beginnt ohne beschreibenden Kommentarblock (Zweck, Autor, Datum) | ✅ | `uMissingUnitHeader` |
| 49 | **DeprecatedAPI: Veraltete API verwendet** | Aufruf einer als `deprecated` markierten Methode oder Klasse | 🔲 | |
| 50 | **CanBeClassMethod: Methode ohne Self-Zugriff** | Instanzmethode greift nicht auf Instanzfelder/-methoden zu – könnte `class function` sein | ✅ | `uCanBeClassMethod` |

---

## 🎁 Bonus-Detektoren (nicht im 50er-Katalog, aber implementiert)

| Regel | Beschreibung | Unit |
|-------|-------------|------|
| **HardcodedPath** | Hardkodierte Datei-/Verzeichnispfade (`C:\…`, UNC, `/usr/…`) | `uHardcodedPath` |
| **DebugOutput** | `WriteLn`, `ShowMessage`, `OutputDebugString`, `InputBox` in Produktionscode | `uDebugOutput` |
| **DuplicateString** | String-Literal kommt 3+ mal vor – sollte als Konstante extrahiert werden | `uDuplicateString` |

---

## Implementierungsstand

```
Sonar-50-Katalog
  ✅ Vollständig:  44  (#1, #2, #3, #4, #5, #6, #7, #8, #9, #10,
                       #11, #12, #13, #14, #15, #17, #18, #19, #21,
                       #23, #24, #25, #26, #27, #29, #31, #32, #33,
                       #34, #35, #36, #37, #38, #39, #40, #41, #43,
                       #44, #45, #46, #47, #48, #50)
                     Critical (#6-#15) komplett. #7/#10/#12/#14/#18/
                     #21/#43/#46 nutzen heuristische AST-/lexikalische
                     Patterns mit dokumentierten Limitierungen.
  🟡 Teilweise:     1  (#30 - nur Strings statt Code-Blöcke)
  🎁 Bonus:         3  (HardcodedPath, DebugOutput, DuplicateString)
  🔲 Offen:         5

  → 48 von 50 Sonar-Regeln als Pascal-AST-Detektor-Code vorhanden,
    davon 45 vollständig.

📐 DFM-Detektoren:                  22 (alle vollständig)
🛡 SonarDelphi-Migration:           12 (SCA120-131, alle vollständig)
🏛 mORMot-Cluster:                   9 (SCA153-161, alle vollständig)
🧩 SonarDelphi Naming/Formatting:  ~60 (SCA060-119, siehe sca-rules.json)

🎯 Gesamt: 161 Detektor-Kinds (~130 Pipeline-Klassen).
```

---

## 📐 DFM-Detektoren — formdatei-spezifisch (nicht im 50er-Sonar-Katalog)

Diese laufen über `.dfm`-Dateien mit eigenem DFM-Lexer + Parser
+ Komponentengraph. `TFormBinder` koppelt die Form an den
zugehörigen `.pas`-AST, `TDfmRepoIndex` stellt Repo-weite
Cross-Form-Lookups bereit. Alle Detektoren liefern Vorher/Nachher-
Fix-Hints im Hilfe-Panel und haben DUnitX-Tests.

### Cluster Dead-Wiring (3) — Events / Handler / Form↔Code-Kopplung

| # | Regel (`fk…`-ID) | Beschreibung | Typ | Unit |
|---|------------------|--------------|-----|------|
| D1 | **DfmDeadEvent** | `OnClick` im DFM verweist auf Methodennamen, der im published-Abschnitt der Form nicht existiert | Bug | `uDfmDeadEvent` |
| D2 | **DfmOrphanHandler** | Published Methode mit `Sender: TObject`-Signatur, an die keine DFM-Komponente bindet | Code Smell | `uDfmOrphanHandler` |
| D3 | **DfmEmptyBoundEvent** | Event ist gebunden, Methode existiert, Rumpf aber leer / nur `inherited` | Code Smell | `uDfmEmptyBoundEvent` |

### Cluster Data-Access (4) — Datasets, Felder, Master-Detail

| # | Regel (`fk…`-ID) | Beschreibung | Typ | Unit |
|---|------------------|--------------|-----|------|
| D4 | **DfmSchemaMismatch** | DFM-`TField`/`TDataSource` hat kein passendes published-Field in der Form-Klasse | Bug | `uDfmSchemaMismatch` |
| D5 | **DfmCircularDataSource** | Zyklus in `DataSource.DataSet` / `MasterSource` — Endlosschleife / Stack-Overflow zur Laufzeit | Bug | `uDfmCircularDataSource` |
| D6 | **DfmFieldTypeMismatch** | UI-Control-Klasse passt nicht zum `TField`-Datentyp (z.B. `TDBEdit` auf `ftBlob`) | Code Smell | `uDfmFieldTypeMismatch` |
| D7 | **DfmRequiredFieldUnbound / NotVisible** | `TField` mit `Required=True` hat keine UI-Bindung (Unbound) — oder nur auf einem versteckten Tab (NotVisible) | Bug | `uDfmRequiredField` |

### Cluster Security (2) — Credentials & SQL-Injection in DFMs

| # | Regel (`fk…`-ID) | Beschreibung | Typ | Unit |
|---|------------------|--------------|-----|------|
| D8 | **DfmHardcodedDbCreds** | Klartext-Credentials auf einer `TADOConnection`/`TFDConnection`-`ConnectionString`/`Params`-Property | Vulnerability | `uDfmHardcodedDbCreds` |
| D9 | **DfmSqlFromUserInput** | SQL-Property einer DB-Query wird (im Pascal-Code) durch `+`-Verkettung mit `TEdit.Text` / anderer UI-Eingabe gebaut — DFM-Smell, der den Analyser zurück in den Pascal-AST zieht | Vulnerability | `uDfmSqlFromUserInput` |

### Cluster Layering / Architektur (4) — Trennung der Belange

| # | Regel (`fk…`-ID) | Beschreibung | Typ | Unit |
|---|------------------|--------------|-----|------|
| D10 | **DfmDbInUiForm** | DB-Komponente (`TADOConnection`, `TFDQuery`, `TClientDataSet`, …) sitzt direkt auf einem UI-Form statt in einem Data-Modul | Code Smell | `uDfmDbInUiForm` |
| D11 | **DfmCrossFormCoupling** | Code in `Form1` greift via globaler Form-Variable auf `Form2.<field>` zu | Bug | `uDfmCrossFormCoupling` |
| D12 | **DfmLayerViolation** | Eingabe-Control sitzt direkt auf `TForm` statt in Panel / `TFrame` / `TGroupBox` | Code Smell | `uDfmLayerViolation` |
| D13 | **DfmForbiddenClass** | Komponente nutzt eine via `analyser.ini → [DfmDetectors] ForbiddenClasses=` gesperrte Klasse | Code Smell | `uDfmForbiddenClass` |

### Cluster UI/UX (4) — Interaktions-Smells in der Form-Definition

| # | Regel (`fk…`-ID) | Beschreibung | Typ | Unit |
|---|------------------|--------------|-----|------|
| D14 | **DfmDuplicateBinding** | Mehrere Komponenten binden denselben `OnClick` / dasselbe `DataField` etc. — typischer Copy-Paste-Bug | Bug | `uDfmDuplicateBinding` |
| D15 | **DfmTabOrderConflict** | Zwei Geschwister-Controls auf demselben Parent haben denselben `TabOrder`-Wert | Code Smell | `uDfmTabOrderConflict` |
| D16 | **DfmGodHandler** | Eine Methode hängt an ≥ N Komponenten-Events — God-Handler, der pro Belang aufgeteilt werden sollte | Code Smell | `uDfmGodHandler` |
| D17 | **DfmActionMismatch** | Komponente hat `Action=` UND `OnClick=` gesetzt — der explizite `OnClick` gewinnt still, die `TAction`-Verklebung läuft ins Leere | Bug | `uDfmActionMismatch` |

### Cluster Naming / Lokalisierung (3) — Hygiene

| # | Regel (`fk…`-ID) | Beschreibung | Typ | Unit |
|---|------------------|--------------|-----|------|
| D18 | **DfmDefaultName** | Komponente hat noch ihren Default-Namen (`Button1`, `Edit2`, …) | Code Smell | `uDfmDefaultName` |
| D19 | **DfmHardcodedCaption** | UI-sichtbarer String (`Caption`, `Hint`, `Text`, …) als Literal im DFM statt via `resourcestring` / dxgettext | Code Smell | `uDfmHardcodedCaption` |
| D20 | **DfmHardcodedDbCreds — Param-Variante** | _(siehe D8 — selbe Unit, separate Finding-Kind für Param-Values vs. ConnectionString)_ | Vulnerability | `uDfmHardcodedDbCreds` |

---

## 🛡 SonarDelphi-Migration-Cluster — Delphi-spezifische Korrektheit (SCA120-131)

Zwölf Checks aus dem SonarDelphi-Regelsatz portiert. Sie decken
Delphi-spezifische Korrektheitslücken ab, die in der generischen
Sonar-50-Taxonomie nicht abgebildet sind: Exception-/Raise-Hygiene,
Function-Result-Disziplin, Typ-Cast-Fallen bei Free / Char / Unicode
sowie locale-abhängige Format-Aufrufe. Alle bringen Vorher/Nachher-
Fix-Hints im Hilfe-Panel und eine DUnitX-Test-Fixture mit.

| ID | Regel | Beschreibung | Schweregrad | Typ | Unit |
|----|-------|--------------|-------------|-----|------|
| SCA120 | **MissingRaise** | `EFoo.Create('msg');` erzeugt ein Exception-Objekt ohne `raise` — der Fehlerpfad wird stillschweigend übersprungen | Error | Bug | `uMissingRaise` |
| SCA121 | **RoutineResultUnassigned** | Function-Body endet ohne `Result`-Zuweisung (oder `<FunctionName> := ...`) — Rückgabewert undefiniert | Error | Bug | `uRoutineResultAssigned` |
| SCA122 | **ReRaiseException** | `on E: T do ... raise E;` verwirft den Original-Stack-Trace — `raise;` ohne Argument behält ihn | Warning | Bug | `uReRaiseException` |
| SCA123 | **CastAndFree** | `TFoo(x).Free` — der Typ-Cast hat keinen Effekt auf welches `Destroy` läuft (`Destroy` ist virtual) | Hint | Code Smell | `uCastAndFree` |
| SCA124 | **InstanceInvokedConstructor** | `obj.Create` — Constructor wird als Methode auf bestehender Instanz aufgerufen, keine Allokation, Felder werden über Live-Daten neu initialisiert | Error | Bug | `uInstanceInvokedConstructor` |
| SCA125 | **InheritedMethodEmpty** | Override, dessen kompletter Rumpf nur `inherited;` ist — bringt keinen Mehrwert, entfernen | Hint | Code Smell | `uInheritedMethodEmpty` |
| SCA126 | **NilComparison** | `Assigned(x)` / `not Assigned(x)` statt `x = nil` / `x <> nil` — Pascal-Konvention | Hint | Code Smell | `uNilComparison` |
| SCA127 | **RaisingRawException** | `raise Exception.Create('...')` — die Basisklasse trägt keine Semantik, Aufrufer können nicht selektiv filtern | Warning | Code Smell | `uRaisingRawException` |
| SCA128 | **DateFormatSettings** | `StrToDate(s)`, `FormatFloat(...)` etc. ohne TFormatSettings hängen vom System-Locale ab — bricht über Maschinen / User hinweg | Warning | Bug | `uDateFormatSettings` |
| SCA129 | **UnicodeToAnsiCast** | `AnsiString(s)` / `UTF8String(s)` / `RawByteString(s)` verliert stillschweigend Zeichen außerhalb der aktiven Codepage | Warning | Bug | `uUnicodeToAnsiCast` |
| SCA130 | **CharToCharPointerCast** | `PChar('A')` ist nicht `PChar("A")` — der Cast interpretiert den 16-Bit-Codepoint als rohe Speicheradresse | Error | Bug | `uCharToCharPointerCast` |
| SCA131 | **IfThenShortCircuit** | `Math.IfThen` / `StrUtils.IfThen` evaluiert beide Arme — kein Short-Circuit, stattdessen `if/then/else` benutzen | Warning | Bug | `uIfThenShortCircuit` |

---

## 🏛 mORMot-Cluster — Concurrency / Pointer / Aliasing (SCA153-161)

Neun Detektoren, die nach einem Audit der [mORMot2](https://github.com/synopse/mORMot2)-Sourcen
hinzugekommen sind. Sie zielen auf Muster, die in großen Low-Level-Delphi-Projekten
immer wieder auftreten: Locking-Primitiven, Raw-Heap-Allokation, Dynamic-Array-
Wachstum, Byte-Level-Puffer-Manipulation, PChar-Arithmetik, Multi-Target-`with`-Blöcke,
typisierte Exception-Handler, String-Casts aus rohen Pointern, Win64-Pointer-Arithmetik.
Alle bringen Vorher/Nachher-Fix-Hints und ein DUnitX-Fixture mit.

| ID | Regel | Beschreibung | Severity | Type | Unit |
|----|-------|--------------|----------|------|------|
| SCA153 | **UnpairedLock** | `<id>.Lock` / `EnterCriticalSection` / `TMonitor.Enter` mit passendem Unlock in derselben Routine, aber ohne umgebendes `try/finally` — eine Exception verliert das Lock und führt zum Deadlock | Warning | Bug | `uUnpairedLock` |
| SCA154 | **MoveSizeOfPointer** | `Move` / `FillChar` / `CopyMemory` / `ZeroMemory` mit `SizeOf(PXxx)`, wobei `PXxx` ein Pointer-Typ ist — kopiert nur 4/8 Bytes (Pointer-Größe), nicht den Zielpuffer | Warning | Bug | `uMoveSizeOfPointer` |
| SCA155 | **WithMultipleTargets** | `with A, B do` (zwei oder mehr Komma-getrennte Ziele) — mehrdeutige Member-Auflösung; eine neue Methode an A oder B verändert still die Bedeutung des Bodies | Hint | Code Smell | `uWithMultipleTargets` |
| SCA156 | **GetMemWithoutFreeMem** | `GetMem` / `AllocMem` / `ReallocMem` mit passendem `FreeMem` in derselben Routine, aber ohne umgebendes `try/finally` — eine Exception verliert den allokierten Heap-Buffer | Warning | Bug | `uGetMemWithoutFreeMem` |
| SCA157 | **SetLengthAppendInLoop** | `SetLength(arr, Length(arr) + N)` innerhalb einer `for/while/repeat`-Schleife — O(n*n) Realloc-Aufwand; einmal vor der Schleife vergrößern oder Block-Grow benutzen | Warning | Code Smell | `uSetLengthAppendInLoop` |
| SCA158 | **PointerArithmeticOnString** | `PChar(s) +/- Offset` (oder `PAnsiChar` / `PWideChar`) ohne vorherigen Empty-Check auf `s` — `PChar('')` ist NIL, Arithmetik auf nil führt zur Access-Violation | Warning | Bug | `uPointerArithmeticOnString` |
| SCA159 | **EmptyOnHandler** | `on E: SomeException do ;` (oder leerer `begin end`) — typisierter Exception-Handler schluckt eine spezifische Exception still; schlimmer als `except end` weil die Typ-Annotation absichtlich wirkt | Warning | Bug | `uEmptyOnHandler` |
| SCA160 | **StringFromPointer** | `string(P)` / `AnsiString(P)` / `UTF8String(P)` Cast aus P-Präfix-Pointer setzt Null-Terminator voraus — liest über das Buffer-Ende hinaus wenn Terminator fehlt; Heap-Overread | Warning | Bug | `uStringFromPointer` |
| SCA161 | **PointerSubtraction** | `Cardinal(P1) - Cardinal(P2)` (oder Integer/LongWord/LongInt-Varianten) trunkiert die oberen 32 Bit eines 64-Bit-Pointers auf Win64; stattdessen `PtrUInt`/`NativeInt` benutzen | Warning | Bug | `uPointerSubtraction` |

---

## Nächste Phasen (Empfehlung)

```
Phase 1 – fehlende Blocker/Critical: #7 UseAfterFree, #15 RaiseWithoutClass
Phase 2 – Major Zuverl.:              #16 UninitVar, #20 ResultNotChecked, #25 FreeWithoutNil
Phase 3 – Major Wartb.:               #28 HighComplexity, #34 MultipleExit, #31 GodClass
Phase 4 – Minor:                      #36 UnusedVar, #39 CommentedCode, #44 LongLine
Phase 5 – Info:                       #47 UnsortedUses, #49 DeprecatedAPI, #50 CanBeClassMethod

DFM Phase 1 (erledigt) : Dead-Wiring + Data-Access + Security
DFM Phase 2 (erledigt) : Layering / UI-UX / Naming
DFM Phase 3 (offen)    : Data-Modul-Split-Vorschlag, DesignTime-Property-Drift,
                         Master-Detail-ohne-LinkField, Frame-Instance-Property-Overrides
```

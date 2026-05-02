# TODO – Sonar-Prüfkatalog für den Static Code Analyser

50 Prüfregeln, geordnet nach Schweregrad (Blocker → Critical → Major → Minor → Info).
Status: ✅ implementiert | 🟡 teilweise | 🔲 offen

**Zusammenfassung:** 17 / 50 vollständig + 1 teilweise + 3 Bonus-Detektoren = 21 Detektoren.

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
| 7 | **UseAfterFree: Objekt nach Free genutzt** | Variable wird nach `Free`/`FreeAndNil` ohne erneute Zuweisung weiterverwendet | 🔲 | |
| 8 | **MissingFinally: Ressource ohne try/finally** | Objekt erstellt, Methode enthält try/except aber kein try/finally für Cleanup | ✅ | `uMissingFinally` |
| 9 | **FormatMismatch: Falsche Arg-Anzahl in Format()** | Anzahl der `%s`/`%d`-Platzhalter im Format-String stimmt nicht mit Argumentliste überein | ✅ | `uFormatMismatch` |
| 10 | **AbstractNotImpl: Abstrakte Methode nicht implementiert** | Konkrete Klasse erbt von abstrakter Basis, implementiert aber nicht alle `abstract`-Methoden | 🔲 | |
| 11 | **ExceptionTooGeneral: Zu allgemeiner Exception-Typ** | `except on E: Exception` statt spezifischem Typ – verdeckt unerwartete Fehler | 🔲 | |
| 12 | **LeakInConstructor: Exception im Konstruktor ohne Cleanup** | Konstruktor kann nach partieller Objektinitialisierung eine Exception werfen ohne `Free` | 🔲 | |
| 13 | **MissingDestructor: Destruktor fehlt / Feld nicht freigegeben** | Klasse mit Objekt-Feldern: kein Destruktor oder Feld nicht in `Destroy` freigegeben | ✅ | `uFieldLeak` |
| 14 | **IntegerOverflow: Überlauf bei Arithmetik** | Multiplikation oder Potenz mit `Integer`/`Word` ohne vorherige Bereichsprüfung | 🔲 | |
| 15 | **RaiseWithoutClass: `raise` ohne Exception-Objekt** | Nacktes `raise` außerhalb eines `except`-Blocks – löst Access Violation aus | 🔲 | |

---

## 🟡 Major – Zuverlässigkeit (10)

| # | Regel | Beschreibung | Status | Unit |
|---|-------|-------------|--------|------|
| 16 | **UninitVar: Uninitialisierte Variable** | Lokale Variable wird gelesen bevor sie in allen Codepfaden zugewiesen wurde | 🔲 | |
| 17 | **DeadCode: Unerreichbarer Code** | Anweisungen nach `Exit`, `Break`, `Continue` oder `raise` auf gleicher Ebene | ✅ | `uDeadCode` |
| 18 | **BoolAlwaysTrue: Boolean-Ausdruck immer wahr/falsch** | Vergleich wie `x >= 0` für `Cardinal` oder `Length(s) >= 0` – ergibt immer True | 🔲 | |
| 19 | **FloatEquality: Fließkomma-Vergleich mit =** | `if a = b` wobei `a` oder `b` vom Typ `Single`/`Double`/`Extended` ist | 🔲 | |
| 20 | **ResultNotChecked: Rückgabewert ignoriert** | Aufruf einer Funktion, deren Ergebnis (z. B. Fehlercode) nicht ausgewertet wird | 🔲 | |
| 21 | **MissingOverride: `override` fehlt** | Methode überschreibt eine `virtual`/`dynamic`-Methode der Elternklasse ohne `override` | 🔲 | |
| 22 | **CyclicUnitDep: Zyklische Unit-Abhängigkeit** | Unit A verwendet Unit B (interface), Unit B verwendet Unit A (interface) | 🔲 | |
| 23 | **ExceptInDestructor: Exception aus Destruktor** | Destruktor enthält Code der eine Exception auslösen kann ohne try/except | 🔲 | |
| 24 | **PublicFieldNoProperty: Öffentliches Feld statt Property** | `public`-Feld direkt exponiert statt über `property` mit Getter/Setter | 🔲 | |
| 25 | **FreeWithoutNil: Free ohne anschließendes Nil** | `obj.Free` ohne nachfolgendes `obj := nil` oder `FreeAndNil` – Dangling Pointer möglich | 🔲 | |

---

## 🟡 Major – Wartbarkeit (10)

| # | Regel | Beschreibung | Status | Unit |
|---|-------|-------------|--------|------|
| 26 | **LongMethod: Methode zu lang** | Methoden-Rumpf überschreitet 50 ausführbare Zeilen | ✅ | `uLongMethod` |
| 27 | **TooManyParams: Zu viele Parameter** | Methode hat mehr als 5 Parameter | ✅ | `uLongParamList` |
| 28 | **HighComplexity: Zyklomatische Komplexität > 10** | Anzahl der Verzweigungspfade (`if`, `case`, `for`, `while`, `and`, `or`) überschreitet 10 | 🔲 | |
| 29 | **DeepNesting: Verschachtelungstiefe > 4** | Code-Block ist mehr als 4 Ebenen tief eingerückt | ✅ | `uDeepNesting` |
| 30 | **DuplicateBlock: Duplizierter Code-Block** | Identischer Block (>10 Zeilen) erscheint mehrfach | 🟡 | `uDuplicateString` (nur Strings, nicht Blöcke) |
| 31 | **GodClass: Gottklasse** | Klasse hat mehr als 20 Methoden oder mehr als 15 Instanzfelder | 🔲 | |
| 32 | **MagicNumber: Magic Number ohne Konstante** | Numerisches Literal (außer 0 und 1) direkt im Code statt benannter Konstante | ✅ | `uMagicNumbers` |
| 33 | **BooleanParam: Boolean als Flag-Parameter** | Methode erhält `Boolean`-Parameter der intern als Verzweigung genutzt wird | 🔲 | |
| 34 | **MultipleExit: Mehr als 3 Exit-Punkte** | Methode enthält mehr als 3 `Exit`-Aufrufe | 🔲 | |
| 35 | **LargeClass: Klasse zu groß** | Unit mit einer Klasse überschreitet 500 Zeilen Implementierungscode | 🔲 | |

---

## 🔵 Minor – Code Smells (10)

| # | Regel | Beschreibung | Status | Unit |
|---|-------|-------------|--------|------|
| 36 | **UnusedVar: Unbenutzte lokale Variable** | Variable im `var`-Block deklariert, aber nie gelesen oder nur geschrieben | 🔲 | |
| 37 | **UnusedMethod: Unbenutzte private Methode** | Private Methode wird innerhalb der Unit nirgendwo aufgerufen | 🔲 | |
| 38 | **UnusedUnit: Unit im uses nicht genutzt** | Unit im `uses`-Abschnitt, deren Symbole im Quelltext nicht referenziert werden | ✅ | `uUnusedUses` |
| 39 | **CommentedCode: Auskommentierter Code** | Block von auskommentiertem Pascal-Code (`//` oder `{ }`) ohne Erklärung | 🔲 | |
| 40 | **TodoComment: TODO/FIXME ohne Ticket** | Kommentar enthält `TODO`, `FIXME`, `HACK`, `XXX` ohne zugehörige Issue-Nummer | ✅ | `uTodoComment` |
| 41 | **EmptyMethod: Leere Methode** | Methode enthält ausschließlich `inherited` oder ist komplett leer | ✅ | `uEmptyMethod` |
| 42 | **UnnecessaryCast: Überflüssige Typumwandlung** | Cast auf denselben Typ oder auf direkten Vorfahren ohne Erweiterung | 🔲 | |
| 43 | **ConstantReturn: Methode gibt immer gleichen Wert zurück** | Alle Pfade einer Funktion liefern dasselbe Literal – sollte Konstante sein | 🔲 | |
| 44 | **LongLine: Zeile zu lang** | Zeile überschreitet 120 Zeichen | 🔲 | |
| 45 | **MixedIndent: Gemischte Einrückung (Tabs + Spaces)** | Zeile enthält sowohl Tabulator- als auch Leerzeichen-Einrückung | 🔲 | |

---

## ⚪ Info (5)

| # | Regel | Beschreibung | Status | Unit |
|---|-------|-------------|--------|------|
| 46 | **HardcodedString: Literal statt resourcestring** | Benutzer-sichtbarer String als Literal statt `resourcestring`-Deklaration | 🔲 | |
| 47 | **UnsortedUses: uses nicht alphabetisch** | Einträge im `uses`-Abschnitt nicht in alphabetischer Reihenfolge | 🔲 | |
| 48 | **MissingUnitHeader: Kein Unit-Beschreibungskommentar** | Unit beginnt ohne beschreibenden Kommentarblock (Zweck, Autor, Datum) | 🔲 | |
| 49 | **DeprecatedAPI: Veraltete API verwendet** | Aufruf einer als `deprecated` markierten Methode oder Klasse | 🔲 | |
| 50 | **CanBeClassMethod: Methode ohne Self-Zugriff** | Instanzmethode greift nicht auf Instanzfelder/-methoden zu – könnte `class function` sein | 🔲 |

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
✅ Vollständig:  17  (#1, #2, #3, #4, #5, #6, #8, #9, #13, #17,
                     #26, #27, #29, #32, #38, #40, #41)
🟡 Teilweise:     1  (#30 - nur Strings statt Code-Blöcke)
🎁 Bonus:         3  (HardcodedPath, DebugOutput, DuplicateString)
🔲 Offen:        32

→ 21 von 50 als Detektor-Code vorhanden, davon 18 vollständig.
```

---

## Nächste Phasen (Empfehlung)

```
Phase 1 – fehlende Blocker/Critical: #7 UseAfterFree, #15 RaiseWithoutClass
Phase 2 – Major Zuverl.:              #16 UninitVar, #20 ResultNotChecked, #25 FreeWithoutNil
Phase 3 – Major Wartb.:               #28 HighComplexity, #34 MultipleExit, #31 GodClass
Phase 4 – Minor:                      #36 UnusedVar, #39 CommentedCode, #44 LongLine
Phase 5 – Info:                       #47 UnsortedUses, #49 DeprecatedAPI, #50 CanBeClassMethod
```

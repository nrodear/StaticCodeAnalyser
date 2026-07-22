# Detektoren – Sonar-Prüfkatalog für das Static Code Analysis Tool for Delphi

Kanonische Liste der unterstützten und geplanten Code-Analyse-Regeln,
geordnet nach Schweregrad (Blocker → Critical → Major → Minor → Info).
Orientiert sich am Sonar-50er-Katalog plus eigene Bonus-Detektoren.

Status: ✅ implementiert | 🟡 teilweise | 🔲 offen

**Zusammenfassung (2026-07-22):** Alle **194 Regel-Kinds** des kanonischen Rosters [`rules/sca-rules.json`](rules/sca-rules.json) sind implementiert und in dieser Datei aufgeführt (geliefert von ~151 Pipeline-Detektor-Klassen; einige Klassen emittieren mehrere Kinds — z. B. `uVisibilityCheck` → 3 Visibility-Kinds, `uPerfHotspots` → SCA110–112, `uSourceEncoding` → SCA185–193, `uDfmAnalysisRunner` → 23 DFM-Kinds; **SCA194 ist projekt-weit, nicht AST-basiert** — emittiert aus dem Projekt-/Gruppen-Scan-Dispatch, nicht der per-Datei-Detektor-Registry). 44 / 50 Sonar-Regel-Slots vollständig; die 4 offenen Slots (#20 ResultNotChecked, #22 CyclicUnitDep, #42 UnnecessaryCast, #49 DeprecatedAPI) brauchen Typ-Inferenz / Cross-Unit-Auflösung und haben noch keine SCA-ID.

Verbleibende 4 offene Slots brauchen Typ-Inferenz / Flow-Analyse / Cross-Unit-Symbol-Resolution: #20 ResultNotChecked, #22 CyclicUnitDep, #42 UnnecessaryCast, #49 DeprecatedAPI. **#16 UninitVar** ist als konservativer MVP (`SCA166`) ausgeliefert — Full Path-Sensitivity bleibt fuer Phase 3 offen.

Die 21 Pascal-AST-Detektoren unten folgen der Sonar-50-Taxonomie.
Die **23 DFM-Detektoren** in eigenem Abschnitt sind formdatei-
spezifisch und gehören nicht in den Sonar-Katalog — sie arbeiten
auf dem DFM-Lexer + Parser + Komponentengraph (sowie FormBinder
für die Pascal-AST-Kopplung), eingeführt mit v0.10.0. Das
**SonarDelphi-Migration-Cluster (SCA120-131)** unten deckt Delphi-
spezifische Korrektheits-Checks ab, die SonarDelphi liefert und die
wir portiert haben. Die SCA060-119 Naming-/Formatting-Checks sind seit 2026-07-19 in
einer eigenen Sektion unten enumeriert; [`rules/sca-rules.json`](rules/sca-rules.json)
bleibt die kanonische maschinenlesbare Liste.

🇬🇧 [English version](DETECTORS.md)

---

## 🔴 Blocker (5)

| # | SCA | Regel | Beschreibung | Status | Unit |
|---|-----|-------|-------------|--------|------|
| 1 | SCA001 | **MemoryLeak: Objekt nie freigegeben** | Objekt per `.Create` erzeugt, kein `Free`/`FreeAndNil`/`Destroy` im gesamten Methodenrumpf. Routinen, die die Ownership eines übergebenen Objekts übernehmen, lassen sich per `[Detectors] OwnershipSinks=Routine1,Routine2` whitelisten (Übergabe an eine solche Routine gilt als Ownership-Transfer → kein Leak) | ✅ | `uLeakDetector2` |
| 2 | SCA002 | **EmptyExcept: Leerer except-Block** | `except`-Block ohne ausführbare Anweisung – Exception wird stillschweigend verschluckt | ✅ | `uCodeSmells2` |
| 3 | SCA008 | **NilDeref: Nil-Zeiger ohne Prüfung** | Objekt-Feld oder Parameter wird ohne vorherige `Assigned()`-Prüfung dereferenziert | ✅ | `uNilDeref` |
| 4 | SCA003 | **SQLInjection: String-Konkatenation in SQL** | SQL-Befehl durch `+`-Verkettung mit Benutzereingabe – kein parametrisiertes Query | ✅ | `uSQLInjection` |
| 5 | SCA004 | **HardcodedSecret: Passwort/Token im Code** | Literal-Zuweisung an Variable deren Name `password`, `token`, `secret`, `key` enthält | ✅ | `uHardcodedSecret` |

---

## 🟠 Critical (10)

| # | SCA | Regel | Beschreibung | Status | Unit |
|---|-----|-------|-------------|--------|------|
| 6 | SCA010 | **DivByZero: Division durch 0 möglich** | Integer-Division oder Modulo, bei der der Divisor 0 sein kann (keine Vorabprüfung) | ✅ | `uDivByZero` |
| 7 | SCA134 | **UseAfterFree: Objekt nach Free genutzt** | Variable wird nach `Free`/`FreeAndNil` ohne erneute Zuweisung weiterverwendet | ✅ | `uUseAfterFree` |
| 8 | SCA009 | **MissingFinally: Ressource ohne try/finally** | Objekt erstellt, Methode enthält try/except aber kein try/finally für Cleanup | ✅ | `uMissingFinally` |
| 9 | SCA005 | **FormatMismatch: Falsche Arg-Anzahl in Format()** | Anzahl der `%s`/`%d`-Platzhalter im Format-String stimmt nicht mit Argumentliste überein | ✅ | `uFormatMismatch` |
| 10 | SCA135 | **AbstractNotImpl: Abstrakte Methode nicht implementiert** | Konkrete Klasse erbt von abstrakter Basis, implementiert aber nicht alle `abstract`-Methoden | ✅ | `uAbstractNotImpl` (nur within-unit) |
| 11 | SCA132 | **ExceptionTooGeneral: Zu allgemeiner Exception-Typ** | `except on E: Exception` statt spezifischem Typ – verdeckt unerwartete Fehler | ✅ | `uExceptionTooGeneral` |
| 12 | SCA136 | **LeakInConstructor: Exception im Konstruktor ohne Cleanup** | Konstruktor kann nach partieller Objektinitialisierung eine Exception werfen ohne `Free` | ✅ | `uLeakInConstructor` |
| 13 | — | **MissingDestructor: Destruktor fehlt / Feld nicht freigegeben** | Klasse mit Objekt-Feldern: kein Destruktor oder Feld nicht in `Destroy` freigegeben | ✅ | `uFieldLeak` |
| 14 | SCA137 | **IntegerOverflow: Überlauf bei Arithmetik** | Multiplikation oder Potenz mit `Integer`/`Word` ohne vorherige Bereichsprüfung | ✅ | `uIntegerOverflow` (nur Int64-Ziel) |
| 15 | — | **RaiseWithoutClass: `raise` ohne Exception-Objekt** | Nacktes `raise` außerhalb eines `except`-Blocks – löst Access Violation aus | ✅ | `uRaiseOutsideExcept` |

---

## 🟡 Major – Zuverlässigkeit (10)

| # | SCA | Regel | Beschreibung | Status | Unit |
|---|-----|-------|-------------|--------|------|
| 16 | SCA166 | **UninitVar: Uninitialisierte Variable** | Lokale Variable wird gelesen bevor sie in allen Codepfaden zugewiesen wurde | 🟡 | MVP ausgeliefert als `SCA166` (`uUninitVar.pas`) — konservativer single-method-Scope ohne volle Path-Sensitivity. Slot #16 bleibt `🟡 partial` bis Phase 3 (CFG + Symboltabelle). Siehe [Konzept_SCA166_UninitVar.md](Konzept_SCA166_UninitVar.md). |
| 17 | SCA011 | **DeadCode: Unerreichbarer Code** | Anweisungen nach `Exit`, `Break`, `Continue` oder `raise` auf gleicher Ebene | ✅ | `uDeadCode` |
| 18 | SCA150 | **BoolAlwaysTrue: Boolean-Ausdruck immer wahr/falsch** | Vergleich wie `x >= 0` für `Cardinal` oder `Length(s) >= 0` – ergibt immer True | ✅ | `uBoolAlwaysTrue` (nur Length-Pattern) |
| 19 | SCA144 | **FloatEquality: Fließkomma-Vergleich mit =** | `if a = b` wobei `a` oder `b` vom Typ `Single`/`Double`/`Extended` ist | ✅ | `uFloatEquality` |
| 20 | — | **ResultNotChecked: Rückgabewert ignoriert** | Aufruf einer Funktion, deren Ergebnis (z. B. Fehlercode) nicht ausgewertet wird | 🔲 | |
| 21 | SCA149 | **MissingOverride: `override` fehlt** | Methode überschreibt eine `virtual`/`dynamic`-Methode der Elternklasse ohne `override` | ✅ | `uMissingOverride` (nur within-unit) |
| 22 | — | **CyclicUnitDep: Zyklische Unit-Abhängigkeit** | Unit A verwendet Unit B (interface), Unit B verwendet Unit A (interface) | 🔲 | |
| 23 | SCA145 | **ExceptInDestructor: Exception aus Destruktor** | Destruktor enthält Code der eine Exception auslösen kann ohne try/except | ✅ | `uExceptInDestructor` |
| 24 | — | **PublicFieldNoProperty: Öffentliches Feld statt Property** | `public`-Feld direkt exponiert statt über `property` mit Getter/Setter | ✅ | `uPublicField` |
| 25 | SCA139 | **FreeWithoutNil: Free ohne anschließendes Nil** | `obj.Free` ohne nachfolgendes `obj := nil` oder `FreeAndNil` – Dangling Pointer möglich | ✅ | `uFreeWithoutNil` |

---

## 🟡 Major – Wartbarkeit (10)

| # | SCA | Regel | Beschreibung | Status | Unit |
|---|-----|-------|-------------|--------|------|
| 26 | SCA012 | **LongMethod: Methode zu lang** | Methoden-Rumpf überschreitet 50 ausführbare Zeilen | ✅ | `uLongMethod` |
| 27 | — | **TooManyParams: Zu viele Parameter** | Methode hat mehr als 5 Parameter | ✅ | `uLongParamList` |
| 28 | SCA022 | **CyclomaticComplexity: McCabe-Komplexität > 10** | Anzahl der Verzweigungspfade (`if`, `case`-Arm, `for`, `while`, `repeat`, `on`-Handler, `and`/`or`/`xor`) überschreitet 10 | ✅ | `uCyclomaticComplexity` |
| 29 | SCA018 | **DeepNesting: Verschachtelungstiefe > 4** | Code-Block ist mehr als 4 Ebenen tief eingerückt | ✅ | `uDeepNesting` |
| 30 | SCA021 | **DuplicateBlock: Duplizierter Code-Block** | Identischer Block (≥ `DuplicateBlockMinLines`, Default 8 normalisierte Zeilen) erscheint mehrfach in derselben Datei | ✅ | `uDuplicateBlock` (SCA021) — zeilenbasierter Sliding-Window, normalisiert Trim/Lowercase/Whitespace-Collapse, überspringt Boilerplate (`begin`/`end`/`else`/`try`/`finally`/`except`, reine Kommentare) und if/end-Branching-Blöcke |
| 31 | SCA138 | **GodClass: Gottklasse** | Klasse hat mehr als 20 Methoden oder mehr als 15 Instanzfelder | ✅ | `uGodClass` |
| 32 | SCA014 | **MagicNumber: Magic Number ohne Konstante** | Numerisches Literal (außer 0 und 1) direkt im Code statt benannter Konstante | ✅ | `uMagicNumbers` |
| 33 | SCA146 | **BooleanParam: Boolean als Flag-Parameter** | Methode erhält `Boolean`-Parameter der intern als Verzweigung genutzt wird | ✅ | `uBooleanParam` |
| 34 | SCA140 | **MultipleExit: Mehr als 3 Exit-Punkte** | Methode enthält mehr als 3 `Exit`-Aufrufe | ✅ | `uMultipleExit` |
| 35 | SCA141 | **LargeClass: Klasse zu groß** | Unit mit einer Klasse überschreitet 500 Zeilen Implementierungscode | ✅ | `uLargeClass` |

---

## 🔵 Minor – Code Smells (10)

| # | SCA | Regel | Beschreibung | Status | Unit |
|---|-----|-------|-------------|--------|------|
| 36 | — | **UnusedVar: Unbenutzte lokale Variable** | Variable im `var`-Block deklariert, aber nie gelesen oder nur geschrieben | ✅ | `uUnusedLocal` |
| 37 | — | **UnusedMethod: Unbenutzte private Methode** | Private Methode wird innerhalb der Unit nirgendwo aufgerufen | ✅ | `uUnusedPrivateMethod` |
| 38 | — | **UnusedUnit: Unit im uses nicht genutzt** | Unit im `uses`-Abschnitt, deren Symbole im Quelltext nicht referenziert werden | ✅ | `uUnusedUses` |
| 39 | — | **CommentedCode: Auskommentierter Code** | Block von auskommentiertem Pascal-Code (`//` oder `{ }`) ohne Erklärung | ✅ | `uCommentedOutCode` |
| 40 | SCA019 | **TodoComment: TODO/FIXME ohne Ticket** | Kommentar enthält `TODO`, `FIXME`, `HACK`, `XXX` ohne zugehörige Issue-Nummer | ✅ | `uTodoComment` |
| 41 | SCA020 | **EmptyMethod: Leere Methode** | Methode enthält ausschließlich `inherited` oder ist komplett leer | ✅ | `uEmptyMethod` |
| 42 | — | **UnnecessaryCast: Überflüssige Typumwandlung** | Cast auf denselben Typ oder auf direkten Vorfahren ohne Erweiterung | 🔲 | |
| 43 | SCA151 | **ConstantReturn: Methode gibt immer gleichen Wert zurück** | Alle Pfade einer Funktion liefern dasselbe Literal – sollte Konstante sein | ✅ | `uConstantReturn` |
| 44 | — | **LongLine: Zeile zu lang** | Zeile überschreitet 120 Zeichen (konfigurierbar via `[Detectors] MaxLineLength`) | ✅ | `uTooLongLine` |
| 45 | — | **MixedIndent: Gemischte Einrückung (Tabs + Spaces)** | Zeile enthält sowohl Tabulator- als auch Leerzeichen-Einrückung | ✅ | `uTabulationCharacter` |

---

## ⚪ Info (5)

| # | SCA | Regel | Beschreibung | Status | Unit |
|---|-----|-------|-------------|--------|------|
| 46 | SCA152 | **HardcodedString: Literal statt resourcestring** | Benutzer-sichtbarer String als Literal statt `resourcestring`-Deklaration | ✅ | `uHardcodedString` (Caption/Hint/Text + ShowMessage) |
| 47 | SCA142 | **UnsortedUses: uses nicht alphabetisch** | Einträge im `uses`-Abschnitt nicht in alphabetischer Reihenfolge | ✅ | `uUnsortedUses` |
| 48 | SCA143 | **MissingUnitHeader: Kein Unit-Beschreibungskommentar** | Unit beginnt ohne beschreibenden Kommentarblock (Zweck, Autor, Datum) | ✅ | `uMissingUnitHeader` |
| 49 | — | **DeprecatedAPI: Veraltete API verwendet** | Aufruf einer als `deprecated` markierten Methode oder Klasse | 🔲 | |
| 50 | SCA148 | **CanBeClassMethod: Methode ohne Self-Zugriff** | Instanzmethode greift nicht auf Instanzfelder/-methoden zu – könnte `class function` sein | ✅ | `uCanBeClassMethod` |

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

📐 DFM-Detektoren:                  23 (alle vollständig)
🛡 SonarDelphi-Migration:           12 (SCA120-131, alle vollständig)
🏛 mORMot-Cluster:                   9 (SCA153-161, alle vollständig)
🧩 SonarDelphi Naming/Formatting:  59 (SCA060-119, Sektion unten)

🎯 Gesamt: ~166 Detektor-Kinds (~158 Pipeline-Klassen).
```

---

## 📐 DFM-Detektoren — formdatei-spezifisch (nicht im 50er-Sonar-Katalog)

Diese laufen über `.dfm`-Dateien mit eigenem DFM-Lexer + Parser
+ Komponentengraph. `TFormBinder` koppelt die Form an den
zugehörigen `.pas`-AST, `TDfmRepoIndex` stellt Repo-weite
Cross-Form-Lookups bereit. Alle Detektoren liefern Vorher/Nachher-
Fix-Hints im Hilfe-Panel und haben DUnitX-Tests.

### Cluster Dead-Wiring (3) — Events / Handler / Form↔Code-Kopplung

| # | SCA | Regel (`fk…`-ID) | Beschreibung | Typ | Unit |
|---|-----|------------------|--------------|-----|------|
| D1 | SCA028 | **DfmDeadEvent** | `OnClick` im DFM verweist auf Methodennamen, der im published-Abschnitt der Form nicht existiert | Bug | `uDfmDeadEvent` |
| D2 | SCA029 | **DfmOrphanHandler** | Published Methode mit `Sender: TObject`-Signatur, an die keine DFM-Komponente bindet | Code Smell | `uDfmOrphanHandler` |
| D3 | SCA030 | **DfmEmptyBoundEvent** | Event ist gebunden, Methode existiert, Rumpf aber leer / nur `inherited` | Code Smell | `uDfmEmptyBoundEvent` |

### Cluster Data-Access (4) — Datasets, Felder, Master-Detail

| # | SCA | Regel (`fk…`-ID) | Beschreibung | Typ | Unit |
|---|-----|------------------|--------------|-----|------|
| D4 | SCA031 | **DfmSchemaMismatch** | DFM-`TField`/`TDataSource` hat kein passendes published-Field in der Form-Klasse | Bug | `uDfmSchemaMismatch` |
| D5 | SCA032 | **DfmCircularDataSource** | Zyklus in `DataSource.DataSet` / `MasterSource` — Endlosschleife / Stack-Overflow zur Laufzeit | Bug | `uDfmCircularDataSource` |
| D6 | SCA036 | **DfmFieldTypeMismatch** | UI-Control-Klasse passt nicht zum `TField`-Datentyp (z.B. `TDBEdit` auf `ftBlob`) | Code Smell | `uDfmFieldTypeMismatch` |
| D7 | SCA034/SCA035 | **DfmRequiredFieldUnbound / NotVisible** | `TField` mit `Required=True` hat keine UI-Bindung (Unbound) — oder nur auf einem versteckten Tab (NotVisible) | Bug | `uDfmRequiredField` |

### Cluster Security (2) — Credentials & SQL-Injection in DFMs

| # | SCA | Regel (`fk…`-ID) | Beschreibung | Typ | Unit |
|---|-----|------------------|--------------|-----|------|
| D8 | SCA026 | **DfmHardcodedDbCreds** | Klartext-Credentials auf einer `TADOConnection`/`TFDConnection`-`ConnectionString`/`Params`-Property | Vulnerability | `uDfmHardcodedDbCreds` |
| D9 | SCA033 | **DfmSqlFromUserInput** | SQL-Property einer DB-Query wird (im Pascal-Code) durch `+`-Verkettung mit `TEdit.Text` / anderer UI-Eingabe gebaut — DFM-Smell, der den Analyser zurück in den Pascal-AST zieht | Vulnerability | `uDfmSqlFromUserInput` |

### Cluster Layering / Architektur (4) — Trennung der Belange

| # | SCA | Regel (`fk…`-ID) | Beschreibung | Typ | Unit |
|---|-----|------------------|--------------|-----|------|
| D10 | SCA039 | **DfmDbInUiForm** | DB-Komponente (`TADOConnection`, `TFDQuery`, `TClientDataSet`, …) sitzt direkt auf einem UI-Form statt in einem Data-Modul | Code Smell | `uDfmDbInUiForm` |
| D11 | SCA040 | **DfmCrossFormCoupling** | Code in `Form1` greift via globaler Form-Variable auf `Form2.<field>` zu | Bug | `uDfmCrossFormCoupling` |
| D12 | SCA041 | **DfmLayerViolation** | Eingabe-Control sitzt direkt auf `TForm` statt in Panel / `TFrame` / `TGroupBox` | Code Smell | `uDfmLayerViolation` |
| D13 | SCA038 | **DfmForbiddenClass** | Komponente nutzt eine via `analyser.ini → [DfmDetectors] ForbiddenClasses=` gesperrte Klasse | Code Smell | `uDfmForbiddenClass` |

### Cluster UI/UX (4) — Interaktions-Smells in der Form-Definition

| # | SCA | Regel (`fk…`-ID) | Beschreibung | Typ | Unit |
|---|-----|------------------|--------------|-----|------|
| D14 | SCA027 | **DfmDuplicateBinding** | Mehrere Komponenten binden denselben `OnClick` / dasselbe `DataField` etc. — typischer Copy-Paste-Bug | Bug | `uDfmDuplicateBinding` |
| D15 | SCA037 | **DfmTabOrderConflict** | Zwei Geschwister-Controls auf demselben Parent haben denselben `TabOrder`-Wert | Code Smell | `uDfmTabOrderConflict` |
| D16 | SCA042 | **DfmGodHandler** | Eine Methode hängt an ≥ N Komponenten-Events — God-Handler, der pro Belang aufgeteilt werden sollte | Code Smell | `uDfmGodHandler` |
| D17 | SCA043 | **DfmActionMismatch** | Komponente hat `Action=` UND `OnClick=` gesetzt — der explizite `OnClick` gewinnt still, die `TAction`-Verklebung läuft ins Leere | Bug | `uDfmActionMismatch` |

### Cluster Naming / Lokalisierung (3) — Hygiene

| # | SCA | Regel (`fk…`-ID) | Beschreibung | Typ | Unit |
|---|-----|------------------|--------------|-----|------|
| D18 | SCA024 | **DfmDefaultName** | Komponente hat noch ihren Default-Namen (`Button1`, `Edit2`, …) | Code Smell | `uDfmDefaultName` |
| D19 | SCA025 | **DfmHardcodedCaption** | UI-sichtbarer String (`Caption`, `Hint`, `Text`, …) als Literal im DFM statt via `resourcestring` / dxgettext | Code Smell | `uDfmHardcodedCaption` |
| D20 | SCA026 | **DfmHardcodedDbCreds — Param-Variante** | _(siehe D8 — selbe Unit, separate Finding-Kind für Param-Values vs. ConnectionString)_ | Vulnerability | `uDfmHardcodedDbCreds` |

### Cluster Tote Komponenten (1) — nicht referenzierte Komponenten

| # | SCA | Regel (`fk…`-ID) | Beschreibung | Typ | Unit |
|---|-----|------------------|--------------|-----|------|
| D21 | SCA184 | **DfmComponentUnused** | Im DFM deklarierte Komponente wird nirgends referenziert — nicht im Code der Form, nicht aus einer anderen Unit über die globale Form-Variable (`Form1.Comp`, aufgelöst via `TSymbolReferenceIndex`) und nicht von einer anderen Komponente im DFM (`DataSource=`, `Action=`, …). Vermutlich nach einem Refactoring übrig. Läuft als `fcLow` (unter dem Default-`fcMedium`-Confidence-Filter — opt-in via `--min-confidence low`); ohne repo-weiten Symbol-Index kein Fund. Persistente `TField`s, eingebettete Frames und Units mit `FindComponent`-by-Name werden in v1 bewusst übersprungen. Bekannte v1-Lücke: Cross-Unit-**Mutationen**, bei denen die Komponente ein mittleres Kettenglied ist (`Form.Comp.Prop := x` / `.Method`), werden noch nicht erkannt. | Code Smell | `uDfmComponentUnused` |
| D24 | SCA056 | **DfmMasterDetailUnlinked** | `TDataSet` hat `MasterSource` gesetzt, aber keine `MasterFields` / `IndexFieldNames` — das Detail-Set filtert nie | Bug | `uDfmMasterDetailUnlinked` |
| D25 | SCA057 | **DfmDataModuleSplitHint** | Aggregierter Hinweis: Form hält ≥ N DB-Komponenten — Auslagerung in ein DataModule erwägen | Code Smell | `uDfmDataModuleSplitHint` |

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

---

## 🧩 Style, Struktur & Korrektheit — Cluster der ersten Generation (21 Regeln, SCA006–SCA059-Rest)

Checks aus dem ursprünglichen Aufbau, die vor den Sonar-Slot-Tabellen oben entstanden; überwiegend Struktur-/Stil-Regeln plus Pipeline-Kinds (`SCA006` emittiert der Analyzer selbst bei unlesbaren Dateien). DFM-Kinds aus diesem ID-Bereich stehen in der DFM-Sektion oben.

| SCA | Regel | Beschreibung | Severity | Typ | Status | Unit |
|-----|-------|--------------|----------|-----|--------|------|
| SCA006 | **FileReadError** | Parser-/IO-Fehler - Quelldatei unlesbar oder syntaktisch defekt | Error | File Error | ✅ | `uStaticAnalyzer2` |
| SCA007 | **UnusedUses** | Uses-Eintrag vermutlich ungenutzt (kein Bezeichner daraus referenziert) | Hint | Code Smell | ✅ | `uUnusedUses` |
| SCA013 | **LongParamList** | Methode hat mehr Parameter als das konfigurierte Maximum (Default 7) | Hint | Code Smell | ✅ | `uLongParamList` |
| SCA015 | **DuplicateString** | Gleiches String-Literal kommt N+-mal vor - in Konstante extrahieren | Hint | Code Duplication | ✅ | `uDuplicateString` |
| SCA016 | **HardcodedPath** | Hartkodierter C:\ / UNC- / Linux-Pfad im Quelltext | Warning | Security Hotspot | ✅ | `uHardcodedPath` |
| SCA017 | **DebugOutput** | Debug-Ausgabe-Statement in einer Produktions-Unit gefunden | Warning | Code Smell | ✅ | `uDebugOutput` |
| SCA023 | **CustomRule** | Pattern einer aus analyser-rules.yml geladenen Regel hat gematcht | Warning | Code Smell | ✅ | `uCustomRuleDetector` |
| SCA044 | **ConcatToFormat** | Mehrteilige String-Konkatenation - in einen Format()-Aufruf extrahieren | Warning | Code Smell | ✅ | `uConcatToFormat` |
| SCA045 | **WithStatement** | with-Statement - Scope-Shadowing-Falle, vor der der Compiler nicht warnt | Warning | Code Smell | ✅ | `uWithStatement` |
| SCA046 | **ReversedForRange** | for i := 10 to 1 do - der Schleifenkörper läuft nie | Error | Bug | ✅ | `uReversedForRange` |
| SCA047 | **SelfAssignment** | Selbstzuweisung - No-op oder Copy-Paste-Tippfehler | Warning | Bug | ✅ | `uSelfAssignment` |
| SCA048 | **VirtualCallInCtor** | Virtuelle Methode aus dem Konstruktor gerufen - Subklassen-Override sieht halbinitialisiertes Self | Error | Bug | ✅ | `uVirtualCallInCtor` |
| SCA049 | **LengthUnderflow** | Length / .Count mit Subtraktion - Native-UInt-Underflow bei leerer Menge | Hint | Bug | ✅ | `uLengthUnderflow` |
| SCA050 | **CanBeUnitPrivate** | Public-Member wird nur innerhalb der eigenen Unit referenziert - klassisches Delphi-`private` (Unit-Scope) reicht | Hint | Code Smell | ✅ | `uVisibilityCheck` |
| SCA051 | **CanBeProtected** | Public-Member wird nur aus Subklassen referenziert, nie extern | Hint | Code Smell | ✅ | `uVisibilityCheck` |
| SCA052 | **UnusedPublicMember** | Public-Member wird von keiner Subklasse und keinem Cross-Unit-Pfad referenziert | Hint | Code Smell | ✅ | `uStaticAnalyzer2` |
| SCA053 | **UnusedLocalVar** | Lokale Variable deklariert, aber nie im Methodenkörper referenziert | Hint | Code Smell | ✅ | `uUnusedLocal` |
| SCA054 | **UnusedParameter** | Methodenparameter wird im Körper nie benutzt | Hint | Code Smell | ✅ | `uUnusedParameter` |
| SCA055 | **TautologicalBoolExpr** | Binärer Operator mit identischer linker und rechter Seite: x = x, a and a, (p <> p) | Error | Bug | ✅ | `uTautologicalExpr` |
| SCA058 | **SqlDangerousStatement** | SQL-Statement ändert jede Zeile - WHERE-Klausel fehlt | Error | Bug | ✅ | `uSqlDangerousStatement` |
| SCA059 | **FormatLocaleHint** | %.2f / %.3f ohne explizite TFormatSettings - Komma-vs-Punkt-Dezimalfalle | Hint | Bug | ✅ | `uFormatMismatch` |

---

## 🔤 Naming, Formatierung & Konvention — SonarDelphi-kompatibler Cluster (59 Regeln, SCA060–SCA119)

Bisher nur über [`rules/sca-rules.json`](rules/sca-rules.json) referenziert; jetzt aufgeführt. Multi-Kind-Klassen: `uVisibilityCheck` (SCA050/051/107), `uPerfHotspots` (SCA110–112), `uRestHttpSecurity` (SCA115/116), `uConcurrencyExt` (SCA113/114).

| SCA | Regel | Beschreibung | Severity | Typ | Status | Unit |
|-----|-------|--------------|----------|-----|--------|------|
| SCA061 | **TabulationCharacter** | Tab-Zeichen rendern editorabhängig unterschiedlich - Spaces verwenden | Hint | Code Smell | ✅ | `uTabulationCharacter` |
| SCA062 | **TooLongLine** | Zeile länger als 120 Zeichen - umbrechen oder Teilausdruck extrahieren | Hint | Code Smell | ✅ | `uTooLongLine` |
| SCA063 | **TrailingWhitespace** | Zeile endet mit Space oder Tab - Diff-Hygiene | Hint | Code Smell | ✅ | `uTrailingWhitespace` |
| SCA064 | **LowercaseKeyword** | Pascal-Schlüsselwörter (`begin`/`end`/`procedure`/...) sollten kleingeschrieben sein | Hint | Code Smell | ✅ | `uLowercaseKeyword` |
| SCA065 | **NoSonarMarker** | `// NOSONAR`-Marker sollte keine Funde stummschalten - Nutzung auditieren | Hint | Code Smell | ✅ | `uNoSonarMarker` |
| SCA066 | **EmptyArgumentList** | `Foo()` sollte `Foo;` sein - leere Klammern weglassen | Hint | Code Smell | ✅ | `uEmptyArgumentList` |
| SCA067 | **InlineAssembly** | `asm...end`-Block - Pascal + Compiler-Intrinsics bevorzugen | Warning | Code Smell | ✅ | `uInlineAssembly` |
| SCA068 | **TrailingCommaArgList** | `Foo(A, B,)` - Komma streichen oder fehlendes Argument ergänzen | Hint | Code Smell | ✅ | `uTrailingCommaArgList` |
| SCA069 | **DigitGrouping** | Große Integer-Literale sollten den `_`-Trenner nutzen | Hint | Code Smell | ✅ | `uDigitGrouping` |
| SCA070 | **CommentedOutCode** | Kommentar sieht aus wie Pascal-Code - löschen oder dokumentieren | Hint | Code Smell | ✅ | `uCommentedOutCode` |
| SCA071 | **UnitLevelKeywordIndent** | `unit`/`interface`/`implementation`/`initialization`/`finalization` gehören an Spalte 1 | Hint | Code Smell | ✅ | `uUnitLevelKeywordIndent` |
| SCA072 | **RedundantBoolean** | `X = True` sollte `X` sein (analog `X <> False`) | Hint | Code Smell | ✅ | `uRedundantBoolean` |
| SCA073 | **EmptyInterface** | Interface ohne Methoden/Properties trägt keinen Kontrakt | Hint | Code Smell | ✅ | `uEmptyInterface` |
| SCA074 | **AssertMessage** | `Assert(cond);` - eine `'why'`-Message für die Diagnose ergänzen | Hint | Code Smell | ✅ | `uAssertMessage` |
| SCA075 | **ExplicitTObjectInheritance** | `class(TObject)` ist redundant - Klammern weglassen | Hint | Code Smell | ✅ | `uExplicitTObjectInheritance` |
| SCA076 | **GroupedDeclaration** | `A, B: Type` in je eine Deklaration pro Zeile aufteilen | Hint | Code Smell | ✅ | `uGroupedDeclaration` |
| SCA077 | **EmptyBlock** | Leeres `begin..end` - löschen oder das Statement einfüllen | Hint | Code Smell | ✅ | `uEmptyBlock` |
| SCA078 | **ExceptOnException** | `on E: Exception do` schluckt alles, auch AV/OOM | Warning | Bug | ✅ | `uExceptOnException` |
| SCA079 | **ConsecutiveSection** | Zwei `const`/`type`/`var`-Blöcke direkt hintereinander - zusammenführen | Hint | Code Smell | ✅ | `uConsecutiveSection` |
| SCA080 | **RedundantJump** | `Exit;` / `Continue;` / `Break;` direkt vor `end` ist ein No-op | Hint | Code Smell | ✅ | `uRedundantJump` |
| SCA081 | **ClassPerFile** | Eine Klasse pro Unit erleichtert Refactoring | Hint | Code Smell | ✅ | `uClassPerFile` |
| SCA082 | **SuperfluousSemicolon** | `;;` - das überzählige Semikolon streichen | Hint | Code Smell | ✅ | `uSuperfluousSemicolon` |
| SCA083 | **EmptyFinallyBlock** | `try ... finally end;` ohne Cleanup - entweder ergänzen oder das finally streichen | Warning | Bug | ✅ | `uEmptyFinallyBlock` |
| SCA084 | **AssignedAndAssignedNil** | `Assigned(X) and (X <> nil)` - den nil-Check streichen | Hint | Code Smell | ✅ | `uAssignedAndAssignedNil` |
| SCA085 | **FreeAndNilHint** | `FreeAndNil(X)` statt `X.Free; X := nil;` verwenden | Hint | Code Smell | ✅ | `uFreeAndNilHint` |
| SCA086 | **AvoidOut** | `var` statt `out` bevorzugen (out hat überraschende Semantik) | Hint | Code Smell | ✅ | `uAvoidOut` |
| SCA087 | **EmptyVisibilitySection** | `public`/`private`/...-Abschnitts-Header ohne Member | Hint | Code Smell | ✅ | `uEmptyVisibilitySection` |
| SCA088 | **LegacyInitializationSection** | `initialization..end.` statt Legacy-`begin..end.` verwenden | Hint | Code Smell | ✅ | `uLegacyInitializationSection` |
| SCA089 | **PublicField** | Public-Feld bricht die Kapselung - Property verwenden | Hint | Code Smell | ✅ | `uPublicField` |
| SCA090 | **NestedTry** | Geschachteltes `try..end` - inneres try in eine Methode extrahieren | Hint | Code Smell | ✅ | `uNestedTry` |
| SCA091 | **CaseStatementSize** | `case` mit >= 10 Zweigen - Polymorphie / Dispatch-Tabelle erwägen | Hint | Code Smell | ✅ | `uCaseStatementSize` |
| SCA092 | **EmptyFile** | Unit ohne type/const/var/procedure/function - löschen oder füllen | Hint | Code Smell | ✅ | `uEmptyFile` |
| SCA093 | **TwiceInheritedCalls** | Zwei oder mehr `inherited;` in derselben Methode - Parent-Seiteneffekte laufen doppelt | Warning | Bug | ✅ | `uTwiceInheritedCalls` |
| SCA094 | **RedundantParentheses** | `((Ident))` - die äußeren Klammern streichen | Hint | Code Smell | ✅ | `uRedundantParentheses` |
| SCA095 | **ConsecutiveVisibility** | Gleiche `public`/`private`/...-Sektion kommt zweimal in einer Klasse vor | Hint | Code Smell | ✅ | `uConsecutiveVisibility` |
| SCA096 | **ConstructorWithoutInherited** | Konstruktor ohne `inherited Create` - der Parent bleibt uninitialisiert | Warning | Bug | ✅ | `uConstructorWithoutInherited` |
| SCA097 | **DestructorWithoutInherited** | Destruktor ohne `inherited Destroy` - Parent-Cleanup entfällt (Leak-Risiko) | Error | Bug | ✅ | `uDestructorWithoutInherited` |
| SCA098 | **RedundantConditional** | `if Cond then X := True else X := False` sollte `X := Cond` sein | Hint | Code Smell | ✅ | `uRedundantConditional` |
| SCA099 | **IfElseBegin** | then-Zweig nutzt `begin..end`, der else-Zweig ist ein Einzel-Statement | Hint | Code Smell | ✅ | `uIfElseBegin` |
| SCA100 | **PointerName** | `Foo = ^Bar` sollte `PBar = ^Bar` sein (P-Präfix-Konvention) | Hint | Code Smell | ✅ | `uPointerName` |
| SCA101 | **BeginEndRequired** | `then`/`else`/`do <stmt>` - explizites `begin..end` bevorzugen | Hint | Code Smell | ✅ | `uBeginEndRequired` |
| SCA102 | **NestedRoutine** | Lokale nested Procedure/Function - auf Unit-Ebene extrahieren | Hint | Code Smell | ✅ | `uNestedRoutines` |
| SCA103 | **FieldName** | Klassenfelder sollten der `F<Name>`-Konvention folgen | Hint | Code Smell | ✅ | `uFieldName` |
| SCA104 | **TypeName** | Klassen- und Record-Typaliase sollten mit `T` beginnen | Hint | Code Smell | ✅ | `uTypeName` |
| SCA105 | **InterfaceName** | Interface-Aliase sollten mit `I` beginnen (`IFoo = interface`) | Hint | Code Smell | ✅ | `uInterfaceName` |
| SCA106 | **MethodName** | Methoden sollten mit Großbuchstaben beginnen (PascalCase) | Hint | Code Smell | ✅ | `uMethodName` |
| SCA107 | **CanBeStrictPrivate** | Public-Member wird NUR von Methoden der eigenen Klasse referenziert - `strict private` erreicht die stärkste Kapselung | Hint | Code Smell | ✅ | `uVisibilityCheck` |
| SCA108 | **SynchronizeInDestructor** | Synchronize() im Destruktor Destroy - klassischer Deadlock zwischen Worker- und UI-Thread | Error | Bug | ✅ | `uSynchronizeInDestructor` |
| SCA109 | **LockWithoutTryFinally** | TCriticalSection / Monitor / WinAPI-Lock ohne umschließendes try..finally - eine Exception lässt den Lock gehalten | Error | Bug | ✅ | `uLockWithoutTryFinally` |
| SCA110 | **StringConcatInLoop** | `s := s + x` in for/while/repeat - quadratische Reallokationen | Warning | Code Smell | ✅ | `uPerfHotspots` |
| SCA111 | **ParamByNameInLoop** | `Query.ParamByName('x').AsXxx := ...` in einer Schleife - linearer Lookup pro Iteration | Hint | Code Smell | ✅ | `uPerfHotspots` |
| SCA112 | **FieldByNameInLoop** | `DataSet.FieldByName('x').AsXxx` in einer Schleife - linearer Lookup pro Zeile | Hint | Code Smell | ✅ | `uPerfHotspots` |
| SCA113 | **ThreadResumeDeprecated** | `MyThread.Resume` - `MyThread.Start` verwenden (seit Delphi 2010) | Warning | Code Smell | ✅ | `uConcurrencyExt` |
| SCA114 | **TThreadDestroyWithoutTerminate** | `FreeAndNil(MyThread)` ohne vorheriges `Terminate; WaitFor` - der Worker kann noch laufen | Error | Bug | ✅ | `uConcurrencyExt` |
| SCA115 | **HttpInsteadOfHttps** | `'http://...'`-Literal für einen Remote-Endpunkt - MITM-anfällig | Warning | Security Hotspot | ✅ | `uRestHttpSecurity` |
| SCA116 | **DisabledTlsVerification** | Leere `SecureProtocols`, `IgnoreCertificateErrors := True` oder `OnVerifyPeer := nil` | Error | Vulnerability | ✅ | `uRestHttpSecurity` |
| SCA117 | **PublicMemberWithoutDoc** | Public-Methode oder -Property im `interface`-Abschnitt ohne Doku-Kommentar direkt darüber | Hint | Code Smell | ✅ | `uPublicMemberWithoutDoc` |
| SCA118 | **ExceptionName** | `class(Exception)`-Nachfahre sollte der Delphi-RTL-Konvention `E<Name>` folgen | Hint | Code Smell | ✅ | `uNamingExt` |
| SCA119 | **LocalConstantName** | `const X = 42;` in einer Methode - für numerische Konstanten UPPER_SNAKE_CASE bevorzugen | Hint | Code Smell | ✅ | `uNamingExt` |

---

## 🚀 Post-1.0-Ergänzungen (23 Regeln — SCA133, SCA147, SCA162–SCA183)

Spätere Wellen: Security/Injection, Suppression-Maschinerie, die Unused-Code-Familie und der Attribut-Cluster (SCA180–183).

| SCA | Regel | Beschreibung | Severity | Typ | Status | Unit |
|-----|-------|--------------|----------|-----|--------|------|
| SCA133 | **RaiseOutsideExcept** | `raise;` ohne Exception-Ausdruck funktioniert nur *innerhalb* eines except-Handlers (Re-Raise) - außerhalb raist es NIL und erzeugt eine Access Violation | Error | Bug | ✅ | `uRaiseOutsideExcept` |
| SCA147 | **UnusedPrivateMethod** | Eine private Methode, die von keiner anderen Methode der Unit referenziert wird, ist toter Code - löschen oder anbinden | Hint | Code Smell | ✅ | `uUnusedPrivateMethod` |
| SCA162 | **InsecureCryptoAlgorithm** | Algorithmus-Name ('MD5', 'SHA1', 'DES', 'RC4', 'TLS1.0', 'SSLv3') oder Wrapper-Klasse (THashMD5, TIdHashSHA1, ...) referenziert - anfällig für Kollisions-/Known-Plaintext-Angriffe | Warning | Vulnerability | ✅ | `uInsecureCryptoAlgorithm` |
| SCA163 | **CommandInjection** | ShellExecute / CreateProcess / WinExec mit `+` in den Argumenten - ist ein Operand user-kontrolliert, wird daraus ein Command-Injection-Vektor | Error | Vulnerability | ✅ | `uCommandInjection` |
| SCA164 | **UnusedRoutine** | Standalone-Prozedur/-Funktion im implementation-Abschnitt wird nie aufgerufen (seit 2026-07-19 Wort-Index-basiert) | Hint | Code Smell | ✅ | `uUnusedRoutine` |
| SCA165 | **UnusedSuppression** | Ein `// noinspection X`-Marker unterdrückt an seiner Zielzeile keinen Fund - entweder wurde der Detektor besser (Suppression überflüssig) oder das Suppression-Ziel war falsch | Hint | Code Smell | ✅ | `uSuppression` |
| SCA167 | **InsecureRandom** | Random / RandomRange / RandomFrom ohne Randomize - Seed=0 liefert bei jedem Lauf dieselbe deterministische Sequenz | Warning | Bug | ✅ | `uInsecureRandom` |
| SCA168 | **DefaultCaseInCaseStatement** | case-Statement ohne else-Zweig - unbehandelte Werte fallen still durch | Hint | CodeSmell | ✅ | `uDefaultCaseInCaseStatement` |
| SCA169 | **AssertWithSideEffect** | Assert(SomeCall) - der Aufruf verschwindet im Release-Build und sein Seiteneffekt geht still verloren | Warning | Bug | ✅ | `uAssertWithSideEffect` |
| SCA170 | **ConstStringParameter** | String-Parameter ohne const deklariert - erzeugt einen Refcount-Bump bei jedem Aufruf | Hint | CodeSmell | ✅ | `uConstStringParameter` |
| SCA171 | **CompilerDirectiveScope** | {$WARNINGS OFF} (oder HINTS/RANGECHECKS/...) ohne schließendes ON - leckt in nachfolgende Units | Warning | CodeSmell | ✅ | `uCompilerDirectiveScope` |
| SCA172 | **BooleanPropertyNaming** | Boolean-Property-Name liest sich wie ein Substantiv - ein Verb-Präfix bevorzugen, das sich als Frage liest | Hint | CodeSmell | ✅ | `uBooleanPropertyNaming` |
| SCA173 | **VariantTypeMisuse** | Variant-Variable in einer Methode mit Schleife - jede Variant-Operation zahlt eine 10-100x-COM-Dispatch-Steuer | Hint | CodeSmell | ✅ | `uVariantTypeMisuse` |
| SCA174 | **TObjectListWithoutOwnership** | TList<TFoo>.Create + Add(TFoo.Create) - die Liste besitzt ihre Items nicht, jede TFoo-Instanz leakt | Warning | Bug | ✅ | `uTObjectListWithoutOwnership` |
| SCA175 | **AnonMethodCaptureLoopVar** | Anonyme Methode in `for i := ... do` referenziert i - alle Closures sehen denselben Endwert | Error | Bug | ✅ | `uAnonMethodCaptureLoopVar` |
| SCA176 | **CognitiveComplexity** | Sonar-artige kognitive Komplexität über 15 - geschachtelte if/for/while/case sind mental schwer zu folgen | Warning | CodeSmell | ✅ | `uCognitiveComplexity` |
| SCA177 | **ThreadFreeOnTerminateWithRef** | Nach T.FreeOnTerminate := True riskiert jeder weitere T.Field-/T.Method-Zugriff eine Access Violation, wenn der Thread sich schon selbst zerstört hat | Error | Bug | ✅ | `uThreadFreeOnTerminateWithRef` |
| SCA178 | **PathTraversal** | File-Open-Aufruf (TFileStream.Create, AssignFile, ...) mit einem Pfad-Ausdruck, der User-Eingaben konkateniert (Edit.Text, Request.Params, ...) - Path-Traversal-Risiko | Error | Vulnerability | ✅ | `uPathTraversal` |
| SCA179 | **AttributeIgnoreWithoutReason** | [Ignore] (ohne String-Argument) überspringt den Test still - eine Message ergänzen, warum der Test deaktiviert ist | Hint | CodeSmell | ✅ | `uAttributeIgnoreWithoutReason` |
| SCA180 | **AttributeDuplicate** | Zwei identische [X]-Attribute am selben Member - Copy-Paste-Rest ohne Wirkung | Warning | CodeSmell | ✅ | `uAttributeDuplicate` |
| SCA181 | **AttributeCategoryWithoutString** | [Category] (ohne Argument) ist in DUnitX ein Compile-Fehler - immer einen Kategorienamen übergeben | Error | Bug | ✅ | `uAttributeCategoryWithoutString` |
| SCA182 | **AttributeTestFixtureWithoutTests** | Klasse ist als [TestFixture] markiert, enthält aber keine [Test]-Methoden - Zombie-Fixture, in TestInsight sichtbar, führt aber nichts aus | Warning | CodeSmell | ✅ | `uAttributeTestFixtureWithoutTests` |
| SCA183 | **AttributeMisalignment** | Attribut-Zeile gefolgt von einer Leerzeile - optisch lose, oft ein Refactoring-Rest | Hint | CodeSmell | ✅ | `uAttributeMisalignment` |

---

## 🔡 Encoding- & Trojan-Source-Familie (9 Regeln, SCA185–SCA193)

Byte-Level-Encoding-Verdikte der Quelldateien (aus den Rohbytes beim Laden berechnet, seit der Perf-Arbeit 2026-07 im Text-Cache) plus Trojan-Source-/Unicode-Abuse-Checks (CVE-2021-42574).

| SCA | Regel | Beschreibung | Severity | Typ | Status | Unit |
|-----|-------|--------------|----------|-----|--------|------|
| SCA185 | **SourceUtf8NoBom** | UTF-8-Datei ohne BOM + Nicht-ASCII - der Compiler liest sie als ANSI (Mojibake) | Warning | Bug | ✅ | `uSourceEncoding` |
| SCA186 | **SourceInvalidUtf8** | Fehlgeformtes UTF-8 (überlang / Surrogat / out-of-range) unter einem UTF-8-BOM | Error | File Error | ✅ | `uSourceEncoding` |
| SCA187 | **SourceControlChar** | NUL / unzulässiges Steuerbyte - Binärdatei oder falsch erkanntes Encoding | Error | File Error | ✅ | `uSourceEncoding` |
| SCA188 | **SourceBidiOverride** | Bidi-Override-/Isolate-Steuerzeichen - der Quelltext liest sich anders, als er kompiliert | Error | Vulnerability | ✅ | `uSourceEncoding` |
| SCA189 | **SourceAnsiNonAscii** | 8-Bit-Quelle (kein BOM, kein gültiges UTF-8) - codepage-abhängig, nicht portabel | Warning | Code Smell | ✅ | `uSourceEncoding` |
| SCA190 | **SourceUtf16** | UTF-16-Quelldatei - kompiliert, ist aber unüblich und text-tool-unfreundlich | Hint | Code Smell | ✅ | `uSourceEncoding` |
| SCA191 | **SourceUtf32** | UTF-32-Quelldatei - der Delphi-Compiler lehnt sie mit Fatal F2438 ab | Error | File Error | ✅ | `uSourceEncoding` |
| SCA192 | **SourceInvisibleChar** | Zero-Width-/unsichtbares Unicode-Zeichen - Hidden-Text-/Homoglyph-Abuse-Vektor | Warning | Vulnerability | ✅ | `uSourceEncoding` |
| SCA193 | **SourceNonAsciiIdentifier** | Bezeichner enthält einen Nicht-ASCII-Buchstaben - Homoglyph-/Verwechslungsrisiko | Warning | Vulnerability | ✅ | `uSourceEncoding` |

---

## 🗂️ Projekt-weit (SCA194) — 1 Regel

Kein AST-/per-Datei-Detektor: läuft nur bei `.dproj`/`.groupproj`-Scans (CLI `--project`/`--project-group` oder der `...`-Dialog) und vergleicht die referenzierte Projekt-Dateiliste mit den `.pas`/`.dfm`-Dateien, die physisch im Projektordner liegen. Emittiert aus dem Scan-Dispatch (`TAnalysisSession.Run`), gegated über Profil + Min-Severity.

| SCA | Regel | Beschreibung | Severity | Typ | Status | Unit |
|-----|-------|--------------|----------|-----|--------|------|
| SCA194 | **NotIncludedInProject** | .pas/.dfm im Projektordner, aber nicht im Projekt (.dproj/.groupproj) referenziert - verwaiste / tote Quelldatei | Hint | Code Smell | ✅ | `uNotIncludedInProject` |

## ⚙️ Konfiguration — SCA001 OwnershipSinks (MemoryLeak-Whitelist)

Manche Codebasen übergeben ein frisch erzeugtes Objekt an eine Routine, die die **Ownership übernimmt** (registriert es in einem besitzenden Container, serialisiert-und-gibt-frei, hängt es in einen Builder-Baum). SCA001 kann nicht über die Aufrufgrenze schauen und meldet das als Leak, obwohl der Aufgerufene das Objekt freigibt. Solche Routinen pro Projekt in `analyser.ini` whitelisten:

```ini
[Detectors]
OwnershipSinks=Render,RegisterInstance
```

Die Übergabe eines getrackten Objekts an eine gelistete Routine (`Render(obj)`, `Foo.RegisterInstance(obj)`) gilt dann als Ownership-Transfer → keine SCA001-Meldung. Der Abgleich erfolgt über den Routinennamen (Teil vor `(`), receiver-unabhängig, mit linker Wortgrenze (`Owner` matcht nie `PreOwner(`).

**Der Default ist leer — bewusst so.** Ein Real-World-Audit von 1262 SCA001-Funden über 24 Repos zeigte: echte Ownership-Sinks sind **zu 100 % framework-spezifisch** — kein Routinenname überträgt Ownership codebasen-übergreifend. Ein ausliefernder Default wurde verworfen, weil die verlockenden Kandidaten gefährlich sind:

- ❌ **Nie `LoadFromStream` / `SaveToStream` / `Assign` / einen RTL-Namen listen.** Diese *borgen* ihr Argument — sie übernehmen kein Ownership. Sie zu whitelisten maskiert echte Leaks. (Das Audit fand echte, nicht freigegebene `TMemoryStream`-Leaks, die so eine Whitelist verdeckt hätte.)
- ✅ Nur Routinen listen, von denen du **weißt**, dass sie Ownership übernehmen — und nur für das Framework, das sie definiert.

Empfohlene Opt-in-Sätze nach Framework (nur ergänzen, was das Projekt nutzt):

| Framework | Ownership-übernehmende Routinen | Beispiel |
|-----------|---------------------------------|----------|
| DelphiMVCFramework | `Render` (serialisiert das Objekt und gibt es frei) | `OwnershipSinks=Render` |
| JVCL Inspector / DI | `RegisterInstance` | `OwnershipSinks=RegisterInstance` |
| SwagDoc-Builder | `AddParameter,AddType,AddLocalVariable` (Elternknoten besitzt das Kind) | `OwnershipSinks=AddParameter,AddType,AddLocalVariable` |

Faustregel: Wenn du nicht die Zeile im Aufgerufenen zeigen kannst, die das Argument freigibt, dann liste es **nicht**.

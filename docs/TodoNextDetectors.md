# TodoNextDetectors

Priorisierte Liste noch nicht (oder nur teilweise) umgesetzter Sonar-Delphi-Checks
mit echtem Mehrwert — also solche, die echte Laufzeitfehler, Speicherprobleme
oder Sicherheitsrisiken finden, nicht reines Naming / Formatierung.

Quelle: [sonar-delphi @ master](https://github.com/integrated-application-development/sonar-delphi/tree/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks)

Cross-Reference: [sonar-coverage.md](sonar-coverage.md) (vollständige J/N-Tabelle).

Link-Konvention: `[Java]` zeigt auf die Sonar-Delphi-Source des jeweiligen Checks.

---

## A. High Priority — Bug-Finder (Laufzeitfehler / undefined behavior)

| # | Sonar-Check | Was es fängt | Sonar-Quelle |
|---:|---|---|---|
| 1 | **VariableInitializationCheck** | Lesen einer Variable bevor sie geschrieben wurde — klassischer Uninitialized-Read-Bug. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/VariableInitializationCheck.java) |
| 2 | **RoutineResultAssignedCheck** | Funktion endet ohne dass `Result` gesetzt wurde → undefined Rückgabewert. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/RoutineResultAssignedCheck.java) |
| 3 | **MissingRaiseCheck** | `Exception.Create(...)` erstellt, aber nie `raise`d → Exception leakt als unbenutztes Objekt. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/MissingRaiseCheck.java) |
| 4 | **ReRaiseExceptionCheck** | `except raise E` statt `except raise` — verliert Original-Stack-Trace und re-wraps fälschlich. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/ReRaiseExceptionCheck.java) |
| 5 | **CastAndFreeCheck** | `TObject(x).Free` — falsche Destructor-Auflösung (TObject.Destroy statt der Sub-Klassen). | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/CastAndFreeCheck.java) |
| 6 | **InstanceInvokedConstructorCheck** | `Instance.Create` statt `Class.Create` — undefined, allokiert kein Objekt. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/InstanceInvokedConstructorCheck.java) |
| 7 | **ObjectPassedAsInterfaceCheck** | TObject wird als IInterface übergeben → kein Reference-Counting → Memory-Leak / Use-After-Free. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/ObjectPassedAsInterfaceCheck.java) |
| 8 | **AddressOfCharacterDataCheck** | `@String[1]` greift in den String-Buffer → undefined nach Copy-on-Write. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/AddressOfCharacterDataCheck.java) |
| 9 | **AddressOfNestedRoutineCheck** | Adresse einer nested Routine an externe Callback übergeben → Stack-Frame nach Return ungültig. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/AddressOfNestedRoutineCheck.java) |
| 10 | **InlineDeclarationCapturedByAnonymousMethodCheck** | Inline-Var von Anonymous-Method gefangen → außerhalb des Scope ungültig. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/InlineDeclarationCapturedByAnonymousMethodCheck.java) |
| 11 | **NoreturnContractCheck** | Funktion als noreturn deklariert kehrt aber zurück → Compiler-Annahmen invalid. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/NoreturnContractCheck.java) |
| 12 | **NonLinearCastCheck** | Cast zwischen unverwandten Klassen → garantierter Runtime-EInvalidCast oder undefined Layout-Zugriff. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/NonLinearCastCheck.java) |
| 13 | **PlatformDependentCastCheck** | Pointer→Integer-Cast bricht auf 64-bit. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/PlatformDependentCastCheck.java) |
| 14 | **PlatformDependentTruncationCheck** | Implizite Truncation zwischen NativeInt und Integer → Datenverlust auf 64-bit. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/PlatformDependentTruncationCheck.java) |
| 15 | **UnicodeToAnsiCastCheck** | `AnsiString(UnicodeString)` ohne Encoding → stiller Datenverlust bei Nicht-ASCII. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/UnicodeToAnsiCastCheck.java) |
| 16 | **CharacterToCharacterPointerCastCheck** | `PChar(Char)` → Pointer auf ungültige Adresse. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/CharacterToCharacterPointerCastCheck.java) |
| 17 | **ImplicitDefaultEncodingCheck** | String/Ansi-Konversion ohne explizite Encoding → Locale-abhängig korrupt. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/ImplicitDefaultEncodingCheck.java) |
| 18 | **DateFormatSettingsCheck** | Datums-Konversion ohne TFormatSettings → Locale-Crash bei DateSeparator-Wechsel. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/DateFormatSettingsCheck.java) |
| 19 | **IfThenShortCircuitCheck** | `Math.IfThen(Cond, A(), B())` evaluiert **beide** Args (kein Short-Circuit) → Side-Effect-Bugs. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/IfThenShortCircuitCheck.java) |
| 20 | **LoopExecutingAtMostOnceCheck** | `repeat ... until True` / for-loop mit konstantem Bound → vermutlich vergessene Logik. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/LoopExecutingAtMostOnceCheck.java) |
| 21 | **ExhaustiveEnumCaseCheck** | `case Enum of` lässt Werte ungehandelt → Logik bricht bei neuem Enum-Wert. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/ExhaustiveEnumCaseCheck.java) |
| 22 | **UnspecifiedReturnTypeCheck** | Function ohne expliziten Return-Type. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/UnspecifiedReturnTypeCheck.java) |
| 23 | **IterationPastHighBoundCheck** *(lokal nur teil-coverage via uLengthUnderflow)* | Schleife läuft über `High(Array)` hinaus → Buffer-Overrun. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/IterationPastHighBoundCheck.java) |

## B. Medium Priority — Quality / Potential Bugs

| # | Sonar-Check | Was es fängt | Sonar-Quelle |
|---:|---|---|---|
| 24 | **RaisingRawExceptionCheck** | `raise Exception.Create(...)` statt einer spezifischeren Klasse → schwer zu fangen. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/RaisingRawExceptionCheck.java) |
| 25 | **RedundantAssignmentCheck** *(lokal nur uSelfAssignment ~)* | Wert wird zugewiesen und vor dem nächsten Read überschrieben → erste Zuweisung tot. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/RedundantAssignmentCheck.java) |
| 26 | **InheritedMethodWithNoCodeCheck** | `procedure Foo; override; begin inherited; end` — Override ohne Mehrwert, verlangsamt vtable. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/InheritedMethodWithNoCodeCheck.java) |
| 27 | **MissingSemicolonCheck** | Fehlendes `;` an Stellen, wo der Compiler es zwar toleriert, aber das Lesen erschwert. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/MissingSemicolonCheck.java) |
| 28 | **CompilerHintsCheck** | Suppress / Track Compiler-Hints — wertvoll als Brücke zum Compiler-Output. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/CompilerHintsCheck.java) |
| 29 | **CompilerWarningsCheck** | Compiler-Warnings als CI-Failures eskalieren. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/CompilerWarningsCheck.java) |
| 30 | **StringListDuplicatesCheck** | TStringList ohne `Duplicates`/`Sorted`-Setzung → duplicate-handling unklar. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/StringListDuplicatesCheck.java) |
| 31 | **RedundantCastCheck** | Cast auf den eigenen Typ — `Integer(I)` wo `I: Integer` → Code-Rauschen. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/RedundantCastCheck.java) |
| 32 | **NilComparisonCheck** *(lokal nur uAssignedAndAssignedNil ~)* | `x = nil` statt `not Assigned(x)` — funktional gleich, aber Konvention. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/NilComparisonCheck.java) |
| 33 | **CognitiveComplexityRoutineCheck** *(lokal nur uCyclomaticComplexity ~)* | Sonar Cognitive Complexity — strafft verschachtelte Logik schärfer als reine Cyclomatic. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/CognitiveComplexityRoutineCheck.java) |

## C. Configurable Forbidden-API-Checks (sehr nützlich wenn projektweit konfiguriert)

| # | Sonar-Check | Use-Case | Sonar-Quelle |
|---:|---|---|---|
| 34 | **ForbiddenRoutineCheck** | Pro Projekt verbotene Routinen (z. B. `Sleep`, `ShowMessage` in Lib-Code). | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/ForbiddenRoutineCheck.java) |
| 35 | **ForbiddenTypeCheck** | Z. B. verbotene Legacy-Typen, FMX in VCL-only-Projekten. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/ForbiddenTypeCheck.java) |
| 36 | **ForbiddenIdentifierCheck** | Generisch, z. B. `Application.MessageBox`-Bann. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/ForbiddenIdentifierCheck.java) |
| 37 | **ForbiddenImportFilePatternCheck** | Z. B. `**/Internal/**` nicht aus `**/Public/**` importierbar — Architektur-Boundary. | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/ForbiddenImportFilePatternCheck.java) |

## D. FMX-spezifisch (nur wenn FireMonkey-Coverage erwünscht)

| # | Sonar-Check | Use-Case | Sonar-Quelle |
|---:|---|---|---|
| 38 | **FormFmxCheck** | FMX-Form-Konsistenz (lokal nur DFM/VCL). | [Java](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/FormFmxCheck.java) |

---

## Bewusst nicht aufgenommen

Folgende fehlende Sonar-Checks sind reines Naming / Formatierung / Style mit
geringem Bug-Finding-Wert. Bei Bedarf später einzeln aufnehmen.

- `AttributeNameCheck`, `ConstantNameCheck`, `EnumNameCheck`, `HelperNameCheck`,
  `InheritedTypeNameCheck`, `MixedNamesCheck`, `RecordNameCheck`,
  `ShortIdentifierCheck`, `TypeAliasCheck`, `UnitNameCheck`, `VariableNameCheck`
- `CommentRegularExpressionCheck`, `StringLiteralRegularExpressionCheck`
- `FullyQualifiedImportCheck`, `ImportSpecificityCheck`
- `InlineConstExplicitTypeCheck`, `InlineLoopVarExplicitTypeCheck`,
  `InlineVarExplicitTypeCheck`
- `InterfaceGuidCheck`, `ObjectTypeCheck`, `PascalStyleResultCheck`
- `MathFunctionSingleOverloadCheck`, `MemberDeclarationOrderCheck`,
  `IndexLastListElementCheck`, `ExplicitBitwiseNotCheck`,
  `ExplicitDefaultPropertyReferenceCheck`
- `ProjectFileRoutineCheck`, `ProjectFileVariableCheck`
- `TooManyDefaultParametersCheck`, `TooManyVariablesCheck`
- `UnusedConstantCheck`, `UnusedFieldCheck` *(lokal ~)*, `UnusedGlobalVariableCheck`,
  `UnusedPropertyCheck`, `UnusedRoutineCheck` *(lokal ~)*, `UnusedTypeCheck`
- `VisibilityKeywordIndentationCheck`, `VisibilitySectionOrderCheck` *(lokal ~)*

---

## Empfohlene Implementierungs-Reihenfolge

1. **A1–A4** (`VariableInitializationCheck`, `RoutineResultAssignedCheck`,
   `MissingRaiseCheck`, `ReRaiseExceptionCheck`) — größter Bug-Output bei
   moderatem Implementierungsaufwand, baut auf bestehender CFG/AST-Logik auf.
2. **A5–A7** (`CastAndFreeCheck`, `InstanceInvokedConstructorCheck`,
   `ObjectPassedAsInterfaceCheck`) — speicher-/lifecycle-relevant, ergänzt
   die lokalen Leak-Detektoren (uLeakDetector2, uFieldLeak).
3. **A12–A18** (Cast-/Encoding-/Platform-Checks) — wichtig bei
   32→64-bit-Migration.
4. **B24–B33** als Code-Quality-Sweep.
5. **C34–C37** (Forbidden-API) sobald Projekt-Policy klar.

---

## Pflicht-Deliverable je Detector: Demo-Datei

Zusätzlich zur Detector-Unit, Tests und Pipeline-Integration (Checkliste siehe
[Todo_neuerdetector.md](../Todo_neuerdetector.md)) **muss** jeder neue
Detector eine begleitende Demo-`.pas` im Ordner `docs/samples/` erhalten.

### Konvention

- **Pfad**: `docs/samples/u<DetectorKind>_SCA<id>_Demo.pas`
- **Unit-Name**: identisch zum Dateinamen (Pascal-Pflicht)
- **Header-Kommentar**: nennt den Detector-Kind, die SCA-ID und die
  erwarteten Findings inkl. Zeilennummer und Routine-/Symbol-Name
- **Inhalt**: Mix aus
  - mindestens 1 Routine die **flagged** wird (mit `🚩`-Kommentar)
  - mindestens 1 Routine pro FP-Guard, die **NICHT** flagged wird (mit
    Kommentar warum der Guard greift)
  - mindestens 1 Routine, die durch echten Aufruf abgedeckt ist
  - optional: ein Beispiel mit `// noinspection <Kind>`-Suppression
- **Sekundäre Detektoren**: die Demo darf andere Detektoren mit-triggern
  (z. B. SCA147 bei einer SCA164-Demo durch ein eigenes Klassen-Feld) —
  im Header-Kommentar dokumentieren, was zur Detector-Demo gehört und was
  Co-Finding ist.

### Vorhandene Beispiele

| Demo | Detector | Verwendet als Vorlage für |
|---|---|---|
| [uUnusedRoutine_SCA164_Demo.pas](samples/uUnusedRoutine_SCA164_Demo.pas) | SCA164 `UnusedRoutine` | Standalone-Routinen, Self-Call-Exclusion, 5 FP-Guards |
| [uUnusedPrivateMethod_SCA147_Demo.pas](samples/uUnusedPrivateMethod_SCA147_Demo.pas) | SCA147 `UnusedPrivateMethod` | class private / strict private, Property-Getter, Suppression-Marker |

### Warum verbindlich?

- **Regression-Sicherung**: jede FP-Guard-Änderung lässt sich in <30 Sekunden
  durch IDE-Run gegen die Demo verifizieren — Drift-Frühwarnung
- **Living Documentation**: PR-Reviewer sehen das Detector-Verhalten an einer
  echten Pascal-Datei statt nur in Test-String-Konstanten
- **Onboarding**: neuer Contributor versteht in 5 Minuten was der Detector
  meldet und warum, ohne die Test-Unit durcharbeiten zu müssen
- **Cross-Detector-Sanity**: bei `docs/samples/`-Lauf werden FP-Klassen
  zwischen Detektoren sichtbar (z. B. erzeugt eine SCA147-Demo idealerweise
  0 SCA164-Findings)

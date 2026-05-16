# TODO — SonarDelphi → SCA Detector Migration

**Goal: 110 % coverage of all SonarDelphi findings**, plus our existing
SCA-unique detectors (DFM, security, SQL).

> **Recherche-Stand 2026-05-16**:
> - SonarDelphi v1.18.3 (IntegraDev fork): **144 Rules** (25 BUG + 119 CODE_SMELL, 0 Vulnerability/Hotspot)
> - SCA v0.9.1: **59 Rules**, davon ~22 mit SonarDelphi-Overlap, ~37 unique (20 DFM-Rules + SQL/Security/Format-Locale)
> - Coverage-Gap zum 110 %-Ziel: **~119 Rules** zu portieren, **~25 Rules** schon vorhanden
>
> **Fortschritt 2026-05-16 (gleicher Tag)**: Phase 1 zu **36/50** abgeschlossen
> (SCA060-095). Katalog von 59 → 95 Rules. Siehe "Phase 1 Status" unten.

---

## Context

Heute haben wir die SonarQube-Integration auf Production-Niveau gebracht
(`v0.9.1`). SCA-Findings landen als External Issues neben dem SonarQube-
Default-Profile "Sonar Way". Wenn ein User aber **auch** das SonarDelphi-
Plugin installiert hat, sieht er TWO Detektor-Sets parallel — wir wollen,
dass SCA allein ausreicht und das SonarDelphi-Plugin **überflüssig** wird.

"110 % Coverage" bedeutet:
- Jeder SonarDelphi-Finding muss von SCA matched werden (sonst: regression
  beim Wechsel weg von SonarDelphi)
- Unsere zusätzlichen Findings (DFM, SQL, Format-Locale) bleiben unsere
  Differentiation
- **Shadow-Run**: SonarDelphi und SCA parallel über denselben Code-Korpus,
  diff der Findings nach `(file, line, rule)` — Ziel: SonarDelphi-only-
  Findings = 0

## Bestehende Infrastruktur (nicht neu bauen)

- AST: [`uAstNode.pas`](StaticCodeAnalyserForm/sources/Parsing/uAstNode.pas), [`uParser2.pas`](StaticCodeAnalyserForm/sources/Parsing/uParser2.pas) — Visitor-tauglich, 45 `TNodeKind`-Werte
- Symbol-Reference-Index: [`uSymbolReferenceIndex.pas`](StaticCodeAnalyserForm/sources/Infrastructure/uSymbolReferenceIndex.pas) — Cross-Unit-Visibility (genutzt von `uVisibilityCheck`)
- Catalog: [`rules/sca-rules.json`](rules/sca-rules.json) + `uRuleCatalog.pas`
- KIND_META: [`uSCAConsts.pas`](StaticCodeAnalyserForm/sources/Common/uSCAConsts.pas) — Single-Source für Severity + FindingType + Name
- Detector-Pattern: 53 Beispiele in [`StaticCodeAnalyserForm/sources/Detectors/`](StaticCodeAnalyserForm/sources/Detectors/)
- Tests: DUnitX-Fixtures in `tests/uTest*.pas`

## Was SonarDelphi anders / besser macht

Nicht-portable Java-Stack:
- **ANTLR3-AST** mit ~50 fein-granulierten Node-Klassen (`RoutineImplementationNode`, `AnonymousMethodNode`, `FieldDeclarationNode`, ...)
- **Type-System mit Symbol-Resolution** über Unit-Imports (`getType().isUnresolved/isClass/isUnknown`)
- **Inheritance-Index** ("ist Klasse direkt von TObject abgeleitet?")
- **DelphiCheckContext + reportIssue()** Sonar-Framework-API

Bei uns fehlend:
- Fein-granulierte AST-Subtypes (wir haben `nkMethod` als Einheits-Bucket)
- Type-Registry mit Cross-Unit-Lookup
- Class-Hierarchy-Index (parent_name_chain pro `class_name`)

## Phase Plan

### Phase 0 — Catalog-First (1 Tag) 🅐

**Ziel**: SonarDelphi-Push-Kompatibilität sofort, ohne Detection-Logik.

- [ ] Alle 144 SonarDelphi-Rule-Keys als `fk*`-Konstanten in [`uSCAConsts.pas`](StaticCodeAnalyserForm/sources/Common/uSCAConsts.pas) (TFindingKind enum + KIND_META) einpflegen
- [ ] [`rules/sca-rules.json`](rules/sca-rules.json) auf 144 + 37 = **~181 Rules** erweitern (placeholders mit Beschreibung aus SonarDelphi-JSON)
- [ ] MQR-Mapping pro neuer Rule (`cleanCodeAttribute` + `impacts`) — viel ist mechanisch übertragbar aus SonarDelphi-Severity
- [ ] Drift-Tests `EveryFindingKindHasRichMetadata` + `EveryFindingKindHasMqrMapping` müssen weiterhin grün sein
- [ ] **Acceptance**: `analyser.exe --sonar-export` schreibt 144+37 Rule-Entries; Sonar-Push akzeptiert die JSON

> **Wert**: dadurch verstummen die SonarDelphi-Findings im Dashboard nicht
> mehr, weil unsere ID's dieselben sind — aber wir melden noch nichts.
> User sieht "alles bekannt", nur wenige Findings (die SCA schon hat).

### Phase 1 — Lexical + Single-Node-AST (Kat A+B, ~50 Rules, 2 Wochen) 🅑

Triviale Detektoren — Pattern matched 1:1 unsere bestehenden.

**Kat A (Lexical, Regex/Substring, ~20 Rules)**:

`CommentRegularExpression`, `StringLiteralRegularExpression`, `TabulationCharacter`, `TrailingWhitespace`, `TooLongLine`, `CommentedOutCode`, `LowercaseKeyword`, `MissingSemicolon`, `SuperfluousSemicolon`, `RedundantParentheses`, `TrailingCommaArgumentList`, `DigitGrouping`, `DigitSeparator`, `NoSonar`, `MixedNames`, `InlineAssembly`, `LegacyInitializationSection`, `UnitLevelKeywordIndentation`, `VisibilityKeywordIndentation`, `PascalStyleResult`

**Vorlage**: [`uTodoComment.pas`](StaticCodeAnalyserForm/sources/Detectors/uTodoComment.pas), [`uHardcodedPath.pas`](StaticCodeAnalyserForm/sources/Detectors/uHardcodedPath.pas), [`uMagicNumbers.pas`](StaticCodeAnalyserForm/sources/Detectors/uMagicNumbers.pas).
**Aufwand**: 1-2 h pro Rule.

**Kat B (AST single-node, ~30 Rules)**:

`EmptyArgumentList`, `EmptyBlock`, `EmptyFieldSection`, `EmptyFile`, `EmptyFinallyBlock`, `EmptyInterface`, `EmptyVisibilitySection`, `GotoStatement`, `GroupedFieldDeclaration`, `GroupedParameterDeclaration`, `GroupedVariableDeclaration`, `MemberDeclarationOrder`, `VisibilitySectionOrder`, `ConsecutiveConstSection`, `ConsecutiveTypeSection`, `ConsecutiveVarSection`, `ConsecutiveVisibilitySection`, `BeginEndRequired`, `CaseStatementSize`, `EmptyRoutine` (✅ haben wir), `RedundantBoolean`, `RedundantJump`, `ExplicitBitwiseNot`, `AssertMessage`, `PublicField`, `ProjectFileRoutine`, `ProjectFileVariable`, `ExplicitTObjectInheritance`, `EmptyInterface`, `ClassPerFile`

**Vorlage**: [`uEmptyMethod.pas`](StaticCodeAnalyserForm/sources/Detectors/uEmptyMethod.pas) (74 Zeilen), [`uDebugOutput.pas`](StaticCodeAnalyserForm/sources/Detectors/uDebugOutput.pas), [`uReversedForRange.pas`](StaticCodeAnalyserForm/sources/Detectors/uReversedForRange.pas).
**Aufwand**: 2-4 h pro Rule.

**Acceptance Phase 1**:
- [ ] DUnitX-Tests pro Rule mit SonarDelphi-Fixture-Files als Truth (aus `delphi-checks/src/test/resources/au/com/integradev/delphi/checks/<RuleName>/`)
- [ ] Shadow-Run: 50 Rules sollten matching Findings produzieren

#### Phase 1 Status (2026-05-16, **31/50 done**)

| ID    | Rule                          | Status | Batch |
|-------|-------------------------------|--------|-------|
| SCA060 | GotoStatement                | done   | #1 (`86db37b`) |
| SCA061 | TabulationCharacter          | done   | #2 (`2ec3620`) |
| SCA062 | TooLongLine                  | done   | #2 |
| SCA063 | TrailingWhitespace           | done   | #2 |
| SCA064 | LowercaseKeyword             | done   | #3 (`c6b2254`) |
| SCA065 | NoSonarMarker                | done   | #3 |
| SCA066 | EmptyArgumentList            | done   | #3 |
| SCA067 | InlineAssembly               | done   | #4 (`e4e783f`) |
| SCA068 | TrailingCommaArgList         | done   | #4 |
| SCA069 | DigitGrouping                | done   | #4 |
| SCA070 | CommentedOutCode             | done   | #5 (`11c75bd`) |
| SCA071 | UnitLevelKeywordIndent       | done   | #5 |
| SCA072 | RedundantBoolean             | done   | #5 |
| SCA073 | EmptyInterface               | done   | #6 (`1f70495`) |
| SCA074 | AssertMessage                | done   | #6 |
| SCA075 | ExplicitTObjectInheritance   | done   | #6 |
| SCA076 | GroupedDeclaration           | done   | #7 (`b6301e4`) (unifies Grouped Field/Var/Param) |
| SCA077 | EmptyBlock                   | done   | #7 |
| SCA078 | ExceptOnException            | done   | #7 |
| SCA079 | ConsecutiveSection           | done   | #8 (`1088e1f`) (unifies Const/Type/Var) |
| SCA080 | RedundantJump                | done   | #8 |
| SCA081 | ClassPerFile                 | done   | #8 |
| SCA082 | SuperfluousSemicolon         | done   | #9 (`21f12f7`) |
| SCA083 | EmptyFinallyBlock            | done   | #9 |
| SCA084 | AssignedAndAssignedNil       | done   | #9 |
| SCA085 | FreeAndNilHint               | done   | #10 (`a160d7d`) |
| SCA086 | AvoidOut                     | done   | #10 |
| SCA087 | EmptyVisibilitySection       | done   | #10 |
| SCA088 | LegacyInitializationSection  | done   | #11 (`0f18ca7`, fix `ad0632b`) |
| SCA089 | PublicField                  | done   | #11 |
| SCA090 | NestedTry                    | done   | #11 |
| SCA091 | CaseStatementSize            | done   | #12 (`9c95e5c`) |
| SCA092 | EmptyFile                    | done   | #12 |
| SCA093 | TwiceInheritedCalls          | done   | #12 (AST-based) |
| SCA094 | RedundantParentheses         | done   | #13 (`69df56d`) |
| SCA095 | ConsecutiveVisibility        | done   | #13 |

**Overlap-Audit (2026-05-16)**: `uEmptyBlock` (SCA077) ueberlappte initial mit
`uEmptyMethod` (existing) auf leeren Methoden-Bodies. Fix in `690d883` -
uEmptyBlock skipt jetzt Methoden-Bodies (uEmptyMethod ist dort
zustaendig), feuert nur noch fuer in-statement Bloecke (`if/while/for/case/try`).
SonarDelphi trennt das auch (EmptyRoutineImplementation vs EmptyBlock).
`uPublicField` (SCA089) ueberlappt teilweise mit `uVisibilityCheck.fkCanBePrivate`
- aber unterschiedliche Signale (Convention vs Usage), beides bleibt.

**Remaining Phase 1 candidates** (~16, with notes on difficulty):

Lexical / lower-risk:
- `MissingSemicolon` (hard - needs AST for statement-end detection)
- `MixedNames` (configurable - belongs to Phase 2 Framework)
- `CommentRegularExpression`, `StringLiteralRegularExpression` (configurable - Phase 2)
- `VisibilityKeywordIndentation` (needs class-body context)
- `PascalStyleResult` (`Result := X` vs `Foo := X` style - hard)
- `DigitSeparator` (relative of SCA069; different threshold pattern)

AST single-node / Kat B:
- `EmptyFieldSection` (similar to EmptyVisibilitySection but only for fields)
- `MemberDeclarationOrder` (needs class-body parse)
- `VisibilitySectionOrder` (needs class-body parse)
- `BeginEndRequired` (`if X then Y;` should be `begin Y end;` - style debated)
- `ExplicitBitwiseNot` (needs type info to distinguish boolean vs numeric `not`)
- `ProjectFileRoutine`, `ProjectFileVariable` (only in `.dpr` context)
- `IfElseBegin` (style for nested if/else with begin)
- `RaiseExceptionType` (needs flow context)

**Open**: 14 candidates remaining. Configurable rules (MixedNames,
*RegularExpression*) move to Phase 2 Framework. The deeper AST-context
rules (MemberDeclarationOrder, VisibilitySectionOrder, ExplicitBitwiseNot)
move to Phase 3 (multi-node + cross-unit).

### Phase 2 — Configurable Forbidden + Naming-Conventions (Framework, ~25 Rules, 1 Woche) 🅒

**Diese 25 Rules teilen sich 2 Frameworks** — bauen wir die zwei, kriegen wir 25 Rules.

**Framework A — `TForbiddenChecker<T>`** (10 Rules):

`ForbiddenConstant`, `ForbiddenEnumValue`, `ForbiddenField`, `ForbiddenIdentifier`, `ForbiddenImportFilePattern`, `ForbiddenProperty`, `ForbiddenRoutine`, `ForbiddenType`, plus die zwei Regex-Tracker (`CommentRegularExpression`, `StringLiteralRegularExpression`).

Pattern: Config-Liste in `analyser.ini` `[ForbiddenIdentifiers]`, `[ForbiddenRoutines]`, etc. Vorlage existiert teilweise in [`uDfmForbiddenClass.pas`](StaticCodeAnalyserForm/sources/Detectors/uDfmForbiddenClass.pas).

**Framework B — `TNamingConventionChecker`** (16 Rules):

`AttributeName`, `ClassName`, `ConstantName`, `ConstructorName`, `DestructorName`, `EnumName`, `FieldName`, `HelperName`, `InheritedTypeName`, `InterfaceName`, `PointerName`, `RecordName`, `RoutineName`, `ShortIdentifier`, `UnitName`, `VariableName`

Pattern: ein Regex pro Naming-Kind, Default-Patterns aus SonarDelphi übernehmen (z.B. `T[A-Z][a-zA-Z0-9]*` für Class). Config-Override per `analyser.ini`.

**Acceptance Phase 2**: SonarDelphi-Default-Naming-Profile produziert identische Findings wie unser.

### Phase 3 — AST Multi-Node + Cross-Unit (Kat C+D, ~35 Rules, 3 Wochen) 🅓

**Kat C — AST multi-node matching, ~20 Rules**:

`FormatArgumentCount` (✅ ähnlich vorhanden in `uFormatMismatch`), `FormatArgumentType`, `FormatStringValid`, `IfThenShortCircuit`, `LoopExecutingAtMostOnce`, `RedundantAssignment`, `RedundantInherited`, `MissingRaise`, `RaisingRawException`, `CatchingRawException`, `ReRaiseException`, `SwallowedException` (✅ ähnlich `uCodeSmells2/EmptyExcept`), `NilComparison`, `InstanceInvokedConstructor`, `InterfaceGuid`, `ObjectType`, `ObjectPassedAsInterface`, `ExplicitDefaultPropertyReference`, `RedundantCast`, `IndexLastListElement`

**Vorlagen**: [`uFormatMismatch.pas`](StaticCodeAnalyserForm/sources/Detectors/uFormatMismatch.pas), [`uTautologicalExpr.pas`](StaticCodeAnalyserForm/sources/Detectors/uTautologicalExpr.pas), [`uMissingFinally.pas`](StaticCodeAnalyserForm/sources/Detectors/uMissingFinally.pas).

**Kat D — Cross-Unit (Symbol-Index nötig), ~15 Rules**:

`UnusedConstant`, `UnusedField`, `UnusedGlobalVariable`, `UnusedImport` (✅ `uUnusedUses`), `UnusedProperty`, `UnusedRoutine`, `UnusedType`, `UnusedLocalVariable` (✅ `uUnusedLocal`), `UnusedParameter` (✅), `TooManyDefaultParameters`, `TooManyVariables`, `TooManyNestedRoutines`, `FullyQualifiedImport`, `ImportSpecificity`, `TypeAlias`, `UnspecifiedReturnType`

**Vorlage**: [`uVisibilityCheck.pas`](StaticCodeAnalyserForm/sources/Detectors/uVisibilityCheck.pas) (nutzt `SymbolReferenceIndex`), [`uUnusedUses.pas`](StaticCodeAnalyserForm/sources/Detectors/uUnusedUses.pas).

**Acceptance Phase 3**: Cross-Unit-Coverage matched SonarDelphi's `UnusedX`-Familie.

### Phase 4 — Inline-Declarations + Inheritance (Kat F + Modern Delphi, ~12 Rules, 2 Wochen) 🅔

**Inline-Declarations (Delphi 10.3+, 5 Rules)**:

`InlineConstExplicitType`, `InlineVarExplicitType`, `InlineLoopVarExplicitType`, `InlineDeclarationCapturedByAnonymousMethod`, `AddressOfNestedRoutine`

**Inheritance-Index nötig** (7 Rules):

`ConstructorWithoutInherited`, `DestructorWithoutInherited`, `InheritedMethodWithNoCode`, `RedundantInherited`, `InheritedTypeName`, `ExplicitTObjectInheritance` (Bonus zu Phase 1), `EmptyInterface`

**Vorab-Investition**: Neue Unit `uClassHierarchyIndex.pas` analog [`uSymbolReferenceIndex.pas`](StaticCodeAnalyserForm/sources/Infrastructure/uSymbolReferenceIndex.pas) — baut `ClassName -> ParentChain` Repo-weit. ~2 Tage Vorlauf.

**Acceptance Phase 4**: `class(TFoo)` Vererbung wird über Unit-Grenzen resolved.

### Phase 5 — Type-Flow (Kat E, ~17 Rules, **OPTIONAL** 4 Wochen) 🅕

**Hard — braucht Type-Registry**:

`AddressOfCharacterData`, `CastAndFree`, `CharacterToCharacterPointerCast`, `FreeAndNilTObject`, `NonLinearCast`, `PlatformDependentCast`, `PlatformDependentTruncation`, `UnicodeToAnsiCast`, `MathFunctionSingleOverload`, `IterationPastHighBound`, `StringListDuplicates`, `DateFormatSettings`, `ImplicitDefaultEncoding`, `AssignedAndFree`, `VariableInitialization`, `CognitiveComplexityRoutine`, `RoutineResultAssigned`

**Vorab-Investition**: `uTypeRegistry.pas` mit Cross-Unit-Type-Resolution. ~1 Woche.

**Workaround ohne Type-Registry**: pattern-match auf bekannte Type-Names als Negativliste — liefert ~70 % Coverage. Akzeptabel für Phase 5 zum Start, später durch echte Type-Registry ersetzen.

**Diese Phase ist nicht teil des 110 %-Coverage-Ziels** wenn der Aufwand zu hoch ist — SonarDelphi selbst hat hier die höchste False-Positive-Rate. Wir können diese 17 Rules im Catalog als "deferred" markieren und kommunizieren.

## Cross-cutting Tasks

### Shadow-Run-Infrastruktur (1 Tag)

- [ ] Bash/PowerShell-Script `tools/shadow-diff-sonardelphi.ps1`:
  1. Test-Corpus (z.B. Embarcadero-Samples + unser Repo) gegen SonarDelphi pushen (Pfad: sonar-scanner mit SonarDelphi-Plugin)
  2. Gleichen Corpus gegen SCA pushen (`sonar-scan.ps1` + `sonar-upload.ps1`)
  3. Diff der Findings nach `(file, line, ruleId-equivalent)` via Mapping-Tabelle in `tools/sonardelphi-rule-mapping.json`
  4. Output: "SonarDelphi-only findings: X (REGRESSIONS)" / "SCA-only: Y (OK)" / "Matched: Z"
- [ ] Mapping-Tabelle: SCA-RuleID ↔ SonarDelphi-RuleKey pflegen während Migration

### Drift-Test gegen 110 %-Ziel

- [ ] Neuer Test `uTestCoverageGap.pas`: lädt SonarDelphi-Rule-Inventar (statisches JSON checked-in als `tests/data/sonardelphi-rules-v1.18.3.json`), prüft pro Rule-Key ob ein SCA-Mapping-Eintrag existiert. Fehlende Mappings: Test rot.

### Test-Fixture-Import

- [ ] `tools/import-sonardelphi-fixtures.ps1` cloned SonarDelphi-Repo, kopiert `delphi-checks/src/test/resources/au/com/integradev/delphi/checks/<RuleName>/*.pas` als `tests/fixtures/sonardelphi/<RuleName>/`. Lizenz-Compliance: Header beachten, Quelle dokumentieren.

## Out of Scope

- **GUI** für SonarDelphi-Rule-Verwaltung — `analyser.ini` reicht für Phase 0-4
- **Quality-Profile-Migration** — SonarQube-seitig, wir liefern nur Findings
- **Auto-Fix-Suggestions** für SonarDelphi-Rules — separater Sprint
- **Reverse-Migration** (SCA → SonarDelphi-Plugin) — explizit nicht das Ziel

## Empfehlung — Reihenfolge

| Phase | Items | Aufwand | ROI |
|---|---|---|---|
| **0** Catalog-First | 144 Rule-IDs + KIND_META + JSON | 1 d | Sofort: Sonar-Push akzeptiert alles |
| **1** Lexical + Single-Node | 50 Rules (Kat A+B) | 2 w | Volumen-Gewinn, einfache Migration |
| **2** Forbidden + Naming-Framework | 25 Rules über 2 Frameworks | 1 w | Hohe Rule-Anzahl pro Code-Aufwand |
| **3** Multi-Node + Cross-Unit | 35 Rules (Kat C+D) | 3 w | Substanz, nutzt vorhandene Infrastruktur |
| **4** Inline + Inheritance | 12 Rules + Hierarchy-Index | 2 w | Modern-Delphi-Coverage |
| **5** Type-Flow (optional) | 17 Rules + Type-Registry | 4 w | High-FP-rate, separat planen |

**Total ohne Phase 5: ~9 Wochen für ~122 portierte Rules** plus die existierenden 22 Overlaps = **144 = 100 % SonarDelphi-Coverage**. Plus unsere 37 unique → **110 % erreicht**.

Mit Phase 5: ~13 Wochen für **161 Rules total** = **112 %**.

**Strikte Abhängigkeit**: Phase 0 vor allem anderen. Phase 4 braucht den Hierarchy-Index (Vorinvestition). Phase 5 braucht Type-Registry (separate Entscheidung).

---

## Sources

- [SonarDelphi v1.18.3 Repo](https://github.com/integrated-application-development/sonar-delphi/tree/v1.18.3) — 144 Rules, ANTLR3-AST
- Rule JSONs: `delphi-checks/src/main/resources/org/sonar/l10n/delphi/rules/community-delphi/*.json`
- Check-Implementations: `delphi-checks/src/main/java/au/com/integradev/delphi/checks/*Check.java`
- Test-Fixtures: `delphi-checks/src/test/resources/au/com/integradev/delphi/checks/<RuleName>/`
- Unsere Rule-Liste: [`rules/sca-rules.json`](rules/sca-rules.json) (59 Regeln, MQR-tauglich)
- Bestehender Sonar-Workflow: [`sonarHowto.md`](sonarHowto.md), [`StaticCodeAnalyserForm/scripts/`](StaticCodeAnalyserForm/scripts/)
- Verwandter TODO: [`todo-sonar.md`](todo-sonar.md) (Sonar-Integration — abgeschlossen mit v0.9.1)

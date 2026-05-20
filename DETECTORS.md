# Detectors — Sonar rule catalogue for the Static Code Analysis Tool for Delphi

Canonical list of all supported and planned analysis rules, ordered by
severity (Blocker → Critical → Major → Minor → Info). The catalogue
follows the Sonar 50-rule taxonomy and adds a handful of bonus detectors
specific to this tool.

Status legend: ✅ implemented · 🟡 partial · 🔲 open

**Summary:** 17 / 50 Sonar-rule slots complete + 1 partial + 3 bonus + **22 DFM** detectors + **12 SonarDelphi-migration** (SCA120-131) + ~60 SonarDelphi-compatible naming/formatting checks (SCA060-119) = **~120 active detectors total**.

The 21 Pascal-AST detectors below follow the Sonar 50-rule taxonomy.
The **22 DFM detectors** in the dedicated section are form-file
specific and do not appear in the Sonar catalogue — they operate on
the DFM lexer + parser + component graph (and FormBinder for
Pascal-AST coupling) introduced with v0.10.0. The **SonarDelphi-
migration cluster (SCA120-131)** below covers Delphi-specific
correctness checks that SonarDelphi ships and we ported. The bulk
of the SCA060-119 naming / formatting / structural checks is not
enumerated here yet — see [`rules/sca-rules.json`](rules/sca-rules.json)
for the canonical roster.

🇩🇪 [Deutsche Version](DETECTORS_de.md)

---

## 🔴 Blocker (5)

| # | Rule | Description | Status | Unit |
|---|------|-------------|--------|------|
| 1 | **MemoryLeak — object never freed** | Object created with `.Create` but no `Free`/`FreeAndNil`/`Destroy` anywhere in the method body | ✅ | `uLeakDetector2` |
| 2 | **EmptyExcept — empty except block** | `except` block without an executable statement — exceptions are silently swallowed | ✅ | `uCodeSmells2` |
| 3 | **NilDeref — nil pointer without check** | Object field or parameter dereferenced without a prior `Assigned()` check | ✅ | `uNilDeref` |
| 4 | **SQLInjection — string concatenation in SQL** | SQL command built by `+` concatenation with user input — no parameterised query | ✅ | `uSQLInjection` |
| 5 | **HardcodedSecret — password/token in code** | Literal assigned to a variable whose name contains `password`, `token`, `secret`, `key` | ✅ | `uHardcodedSecret` |

---

## 🟠 Critical (10)

| # | Rule | Description | Status | Unit |
|---|------|-------------|--------|------|
| 6 | **DivByZero — possible division by zero** | Integer division or modulo where the divisor can be zero (no upfront check) | ✅ | `uDivByZero` |
| 7 | **UseAfterFree — object used after Free** | Variable used after `Free`/`FreeAndNil` without being re-assigned | ✅ | `uUseAfterFree` |
| 8 | **MissingFinally — resource without try/finally** | Object created, method has try/except but no try/finally for cleanup | ✅ | `uMissingFinally` |
| 9 | **FormatMismatch — wrong arg count in Format()** | The number of `%s`/`%d` placeholders in the format string does not match the argument list | ✅ | `uFormatMismatch` |
| 10 | **AbstractNotImpl — abstract method not implemented** | Concrete class inherits from an abstract base but doesn't implement all `abstract` methods | ✅ | `uAbstractNotImpl` (within-unit only) |
| 11 | **ExceptionTooGeneral — exception type too broad** | `except on E: Exception` instead of a specific type — masks unexpected errors | ✅ | `uExceptionTooGeneral` |
| 12 | **LeakInConstructor — exception in constructor without cleanup** | Constructor can raise after partial initialisation without calling `Free` | ✅ | `uLeakInConstructor` |
| 13 | **MissingDestructor — destructor missing / field not freed** | Class with object fields: no destructor, or a field isn't freed in `Destroy` | ✅ | `uFieldLeak` |
| 14 | **IntegerOverflow — arithmetic overflow** | Multiplication or exponentiation on `Integer`/`Word` without a prior range check | ✅ | `uIntegerOverflow` (Int64 target only) |
| 15 | **RaiseWithoutClass — bare `raise`** | A bare `raise` outside an `except` block — produces an Access Violation | ✅ | `uRaiseOutsideExcept` |

---

## 🟡 Major — Reliability (10)

| # | Rule | Description | Status | Unit |
|---|------|-------------|--------|------|
| 16 | **UninitVar — uninitialised variable** | Local variable read before being assigned on every code path | 🔲 | |
| 17 | **DeadCode — unreachable code** | Statements after `Exit`, `Break`, `Continue` or `raise` at the same nesting level | ✅ | `uDeadCode` |
| 18 | **BoolAlwaysTrue — boolean always true/false** | Comparison such as `x >= 0` for `Cardinal` or `Length(s) >= 0` — always evaluates to True | 🔲 | |
| 19 | **FloatEquality — floating-point comparison with =** | `if a = b` where `a` or `b` is `Single`/`Double`/`Extended` | 🔲 | |
| 20 | **ResultNotChecked — return value ignored** | A function call whose result (e.g. an error code) is discarded | 🔲 | |
| 21 | **MissingOverride — `override` missing** | Method overrides a parent's `virtual`/`dynamic` method without `override` | 🔲 | |
| 22 | **CyclicUnitDep — cyclic unit dependency** | Unit A uses unit B (interface), unit B uses unit A (interface) | 🔲 | |
| 23 | **ExceptInDestructor — exception from destructor** | Destructor contains code that may raise without a try/except | 🔲 | |
| 24 | **PublicFieldNoProperty — public field instead of property** | `public` field exposed directly instead of via `property` with getter/setter | 🔲 | |
| 25 | **FreeWithoutNil — Free without nil-out** | `obj.Free` not followed by `obj := nil` or `FreeAndNil` — dangling pointer possible | 🔲 | |

---

## 🟡 Major — Maintainability (10)

| # | Rule | Description | Status | Unit |
|---|------|-------------|--------|------|
| 26 | **LongMethod — method too long** | Method body exceeds 50 executable lines | ✅ | `uLongMethod` |
| 27 | **TooManyParams — too many parameters** | Method has more than 5 parameters | ✅ | `uLongParamList` |
| 28 | **CyclomaticComplexity — McCabe complexity > 10** | Number of branching paths (`if`, `case` arm, `for`, `while`, `repeat`, `on` handler, `and`/`or`/`xor`) exceeds 10 | ✅ | `uCyclomaticComplexity` |
| 29 | **DeepNesting — nesting depth > 4** | Code block indented more than four levels deep | ✅ | `uDeepNesting` |
| 30 | **DuplicateBlock — duplicated code block** | Identical block (>10 lines) appears more than once | 🟡 | `uDuplicateString` (strings only, not blocks) |
| 31 | **GodClass — god class** | Class has more than 20 methods or more than 15 instance fields | 🔲 | |
| 32 | **MagicNumber — magic number without constant** | Numeric literal (other than 0 and 1) used directly in code instead of a named constant | ✅ | `uMagicNumbers` |
| 33 | **BooleanParam — boolean as flag parameter** | Method takes a `Boolean` parameter used internally for branching | 🔲 | |
| 34 | **MultipleExit — more than 3 exit points** | Method contains more than three `Exit` calls | 🔲 | |
| 35 | **LargeClass — class too big** | Single-class unit exceeds 500 lines of implementation | 🔲 | |

---

## 🔵 Minor — Code Smells (10)

| # | Rule | Description | Status | Unit |
|---|------|-------------|--------|------|
| 36 | **UnusedVar — unused local variable** | Variable declared in the `var` block but never read (or only written) | 🔲 | |
| 37 | **UnusedMethod — unused private method** | Private method never called inside the unit | 🔲 | |
| 38 | **UnusedUnit — unit in uses not used** | Unit listed in `uses` whose symbols are never referenced | ✅ | `uUnusedUses` |
| 39 | **CommentedCode — commented-out code** | Block of commented Pascal code (`//` or `{ }`) without explanation | 🔲 | |
| 40 | **TodoComment — TODO/FIXME without ticket** | Comment contains `TODO`, `FIXME`, `HACK`, `XXX` without an issue reference | ✅ | `uTodoComment` |
| 41 | **EmptyMethod — empty method** | Method only contains `inherited`, or is completely empty | ✅ | `uEmptyMethod` |
| 42 | **UnnecessaryCast — redundant type cast** | Cast to the same type or to a direct ancestor without extension | 🔲 | |
| 43 | **ConstantReturn — method always returns the same value** | Every path returns the same literal — should be a constant | 🔲 | |
| 44 | **LongLine — line too long** | Line exceeds 120 characters | 🔲 | |
| 45 | **MixedIndent — mixed indentation (tabs + spaces)** | Line contains both tab and space indentation | 🔲 | |

---

## ⚪ Info (5)

| # | Rule | Description | Status | Unit |
|---|------|-------------|--------|------|
| 46 | **HardcodedString — literal instead of resourcestring** | User-visible string as a literal instead of a `resourcestring` declaration | 🔲 | |
| 47 | **UnsortedUses — uses not alphabetic** | Entries in the `uses` section are not in alphabetical order | 🔲 | |
| 48 | **MissingUnitHeader — no unit description comment** | Unit starts without a descriptive comment block (purpose, author, date) | 🔲 | |
| 49 | **DeprecatedAPI — deprecated API used** | Call to a method or class marked `deprecated` | 🔲 | |
| 50 | **CanBeClassMethod — method without Self access** | Instance method doesn't touch instance fields/methods — could be a `class function` | 🔲 |

---

## 🎁 Bonus detectors (not in the 50-rule catalogue, but implemented)

| Rule | Description | Unit |
|------|-------------|------|
| **HardcodedPath** | Hardcoded file or directory paths (`C:\…`, UNC, `/usr/…`) | `uHardcodedPath` |
| **DebugOutput** | `WriteLn`, `ShowMessage`, `OutputDebugString`, `InputBox` left in production code | `uDebugOutput` |
| **DuplicateString** | String literal appears 3+ times — should be extracted to a constant | `uDuplicateString` |

---

## Implementation status

```
Sonar-50 catalogue
  ✅ Complete:  23  (#1, #2, #3, #4, #5, #6, #7, #8, #9, #10,
                    #11, #12, #13, #14, #15, #17, #26, #27, #29,
                    #32, #38, #40, #41)
                  Critical (#6-#15) all done; #7/#10/#12/#14 use
                  heuristic AST/lexical patterns with documented
                  limitations (see detector unit headers).
  🟡 Partial:    1  (#30 — strings only, not arbitrary blocks)
  🎁 Bonus:      3  (HardcodedPath, DebugOutput, DuplicateString)
  🔲 Open:      26

  → 27 of 50 Sonar rules backed by Pascal-AST detector code,
    24 of those fully complete.

📐 DFM detectors:                  22 (all complete)
🛡 SonarDelphi-migration:          12 (SCA120-131, all complete)
🧩 SonarDelphi naming/formatting:  ~60 (SCA060-119, see sca-rules.json)

🎯 Grand total: ~120 active detectors.
```

---

## 📐 DFM detectors — form-file specific (not in 50-rule Sonar catalogue)

These run against `.dfm` files using a dedicated DFM lexer + parser
+ component graph, with `TFormBinder` coupling the form to its
companion `.pas` AST and `TDfmRepoIndex` providing repo-wide
cross-form lookups. All ship with before/after fix hints in the
help panel and DUnitX tests.

### Dead-Wiring cluster (3) — events / handlers / form↔code coupling

| # | Rule (`fk…` id) | Description | Type | Unit |
|---|-----------------|-------------|------|------|
| D1 | **DfmDeadEvent** | `OnClick` in the DFM points to a method name that doesn't exist in the form's published section | Bug | `uDfmDeadEvent` |
| D2 | **DfmOrphanHandler** | Published method with `Sender: TObject` signature that no DFM component binds to | Code Smell | `uDfmOrphanHandler` |
| D3 | **DfmEmptyBoundEvent** | Event is bound, target method exists, but the body is empty / `inherited`-only | Code Smell | `uDfmEmptyBoundEvent` |

### Data-Access cluster (4) — datasets, fields, master-detail

| # | Rule (`fk…` id) | Description | Type | Unit |
|---|-----------------|-------------|------|------|
| D4 | **DfmSchemaMismatch** | DFM `TField`/`TDataSource` has no matching published field in the form class | Bug | `uDfmSchemaMismatch` |
| D5 | **DfmCircularDataSource** | Cycle in `DataSource.DataSet` / `MasterSource` graph — runtime infinite loop / stack overflow | Bug | `uDfmCircularDataSource` |
| D6 | **DfmFieldTypeMismatch** | UI control class doesn't match the `TField` data type (e.g. `TDBEdit` bound to `ftBlob`) | Code Smell | `uDfmFieldTypeMismatch` |
| D7 | **DfmRequiredFieldUnbound / NotVisible** | `TField` with `Required=True` has no UI binding at all (Unbound) — or only on a hidden tab (NotVisible) | Bug | `uDfmRequiredField` |

### Security cluster (2) — credentials and SQL injection in DFMs

| # | Rule (`fk…` id) | Description | Type | Unit |
|---|-----------------|-------------|------|------|
| D8 | **DfmHardcodedDbCreds** | Plaintext credentials on a `TADOConnection` / `TFDConnection` `ConnectionString` / `Params` property | Vulnerability | `uDfmHardcodedDbCreds` |
| D9 | **DfmSqlFromUserInput** | SQL property of a DB-query is built (in `Pascal`) by concatenating `TEdit.Text` or other UI input — DFM smell that pulls the analyser back into Pascal AST | Vulnerability | `uDfmSqlFromUserInput` |

### Layering / Architecture cluster (4) — separation of concerns

| # | Rule (`fk…` id) | Description | Type | Unit |
|---|-----------------|-------------|------|------|
| D10 | **DfmDbInUiForm** | DB component (`TADOConnection`, `TFDQuery`, `TClientDataSet`, …) sits directly on a UI form instead of a data-module | Code Smell | `uDfmDbInUiForm` |
| D11 | **DfmCrossFormCoupling** | Code in `Form1` reaches into `Form2.<field>` via the global form variable | Bug | `uDfmCrossFormCoupling` |
| D12 | **DfmLayerViolation** | Input control sits directly on `TForm` instead of a Panel / `TFrame` / `TGroupBox` container | Code Smell | `uDfmLayerViolation` |
| D13 | **DfmForbiddenClass** | Component class listed in `analyser.ini → [DfmDetectors] ForbiddenClasses=` is used in a DFM | Code Smell | `uDfmForbiddenClass` |

### UI/UX cluster (4) — interaction smells in the form definition

| # | Rule (`fk…` id) | Description | Type | Unit |
|---|-----------------|-------------|------|------|
| D14 | **DfmDuplicateBinding** | Multiple components bind the same `OnClick` / same `DataField` etc. — usually a copy-paste bug | Bug | `uDfmDuplicateBinding` |
| D15 | **DfmTabOrderConflict** | Two sibling controls on the same parent share the same `TabOrder` value | Code Smell | `uDfmTabOrderConflict` |
| D16 | **DfmGodHandler** | One method bound to ≥ N components' events — a god-handler that should be split per concern | Code Smell | `uDfmGodHandler` |
| D17 | **DfmActionMismatch** | Component has both `Action=` and `OnClick=` set — the explicit `OnClick` silently wins and the `TAction` glue is wasted | Bug | `uDfmActionMismatch` |

### Naming / Localisation cluster (3) — hygiene

| # | Rule (`fk…` id) | Description | Type | Unit |
|---|-----------------|-------------|------|------|
| D18 | **DfmDefaultName** | Component still has its default name (`Button1`, `Edit2`, …) | Code Smell | `uDfmDefaultName` |
| D19 | **DfmHardcodedCaption** | UI-visible string (`Caption`, `Hint`, `Text`, …) is a literal in the DFM instead of going through `resourcestring` / dxgettext | Code Smell | `uDfmHardcodedCaption` |
| D20 | **DfmHardcodedDbCreds extras** | _(see D8 — same detector, separate finding kind for parameter values vs. ConnectionString)_ | Vulnerability | `uDfmHardcodedDbCreds` |

---

## 🛡 SonarDelphi-Migration cluster — Delphi-specific correctness (SCA120-131)

Twelve checks ported from the SonarDelphi rule set. They cover
Delphi-specific correctness gaps that are not represented in the
generic Sonar 50-rule taxonomy: exception/raise hygiene, function
result discipline, type-cast traps around Free / Char / Unicode, and
locale-dependent format calls. All ship with before/after fix hints
in the help panel and a DUnitX test fixture.

| ID | Rule | Description | Severity | Type | Unit |
|----|------|-------------|----------|------|------|
| SCA120 | **MissingRaise** | `EFoo.Create('msg');` allocates an exception object without `raise` — the error path is silently skipped | Error | Bug | `uMissingRaise` |
| SCA121 | **RoutineResultUnassigned** | Function body finishes without writing `Result` (or `<FunctionName> := ...`) — return value is undefined | Error | Bug | `uRoutineResultAssigned` |
| SCA122 | **ReRaiseException** | `on E: T do ... raise E;` discards the original stack trace — use bare `raise;` to keep it | Warning | Bug | `uReRaiseException` |
| SCA123 | **CastAndFree** | `TFoo(x).Free` — the type-cast has no effect on which `Destroy` runs (`Destroy` is virtual) | Hint | Code Smell | `uCastAndFree` |
| SCA124 | **InstanceInvokedConstructor** | `obj.Create` — invokes constructor as method on an existing instance, skips allocation and re-runs field initialisation over live data | Error | Bug | `uInstanceInvokedConstructor` |
| SCA125 | **InheritedMethodEmpty** | Override whose entire body is `inherited;` — serves no purpose, remove it | Hint | Code Smell | `uInheritedMethodEmpty` |
| SCA126 | **NilComparison** | Use `Assigned(x)` / `not Assigned(x)` instead of `x = nil` / `x <> nil` — Pascal convention | Hint | Code Smell | `uNilComparison` |
| SCA127 | **RaisingRawException** | `raise Exception.Create('...')` — base class carries no semantic information, callers cannot filter selectively | Warning | Code Smell | `uRaisingRawException` |
| SCA128 | **DateFormatSettings** | `StrToDate(s)`, `FormatFloat(...)` etc. without TFormatSettings depend on the system locale — breaks across machines / users | Warning | Bug | `uDateFormatSettings` |
| SCA129 | **UnicodeToAnsiCast** | `AnsiString(s)` / `UTF8String(s)` / `RawByteString(s)` silently drops characters outside the active code page | Warning | Bug | `uUnicodeToAnsiCast` |
| SCA130 | **CharToCharPointerCast** | `PChar('A')` is not `PChar("A")` — the cast treats the 16-bit codepoint as a raw memory address | Error | Bug | `uCharToCharPointerCast` |
| SCA131 | **IfThenShortCircuit** | `Math.IfThen` / `StrUtils.IfThen` evaluate both branches — no short-circuit semantics, use `if/then/else` instead | Warning | Bug | `uIfThenShortCircuit` |

---

## Suggested implementation phases

```
Phase 1 — missing Blocker / Critical : #7  UseAfterFree, #15 RaiseWithoutClass
Phase 2 — Major reliability          : #16 UninitVar, #20 ResultNotChecked, #25 FreeWithoutNil
Phase 3 — Major maintainability      : #28 HighComplexity, #34 MultipleExit, #31 GodClass
Phase 4 — Minor                      : #36 UnusedVar, #39 CommentedCode, #44 LongLine
Phase 5 — Info                       : #47 UnsortedUses, #49 DeprecatedAPI, #50 CanBeClassMethod

DFM Phase 1 (done)  : Dead-Wiring + Data-Access + Security clusters
DFM Phase 2 (done)  : Layering / UI-UX / Naming clusters
DFM Phase 3 (open)  : data-module split suggestion, designtime-prop drift,
                      master-detail-without-LinkField, frame-instance prop overrides
```

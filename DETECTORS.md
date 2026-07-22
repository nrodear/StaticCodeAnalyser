# Detectors — Sonar rule catalogue for the Static Code Analysis Tool for Delphi

Canonical list of all supported and planned analysis rules, ordered by
severity (Blocker → Critical → Major → Minor → Info). The catalogue
follows the Sonar 50-rule taxonomy and adds a handful of bonus detectors
specific to this tool.

Status legend: ✅ implemented · 🟡 partial · 🔲 open

**Summary (2026-07-22):** All **194 rule kinds** from the canonical roster [`rules/sca-rules.json`](rules/sca-rules.json) are implemented and enumerated in this file (delivered by ~151 pipeline detector classes; several classes emit multiple kinds — e.g. `uVisibilityCheck` → 3 visibility kinds, `uPerfHotspots` → SCA110–112, `uSourceEncoding` → SCA185–193, `uDfmAnalysisRunner` → 23 DFM kinds; **SCA194 is project-scope, not AST-based** — emitted from the project/group scan dispatch, not the per-file detector registry). 44 / 50 Sonar-rule slots complete; the 4 open slots (#20 ResultNotChecked, #22 CyclicUnitDep, #42 UnnecessaryCast, #49 DeprecatedAPI) need type-inference / cross-unit resolution and have no SCA-ID yet.

Remaining 4 open slots all need type-inference / flow-analysis / cross-unit symbol resolution: #20 ResultNotChecked, #22 CyclicUnitDep, #42 UnnecessaryCast, #49 DeprecatedAPI. **#16 UninitVar** has a conservative MVP (`SCA166`) — full path-sensitivity remains open for Phase 3.

The 21 Pascal-AST detectors below follow the Sonar 50-rule taxonomy.
The **23 DFM detectors** in the dedicated section are form-file
specific and do not appear in the Sonar catalogue — they operate on
the DFM lexer + parser + component graph (and FormBinder for
Pascal-AST coupling) introduced with v0.10.0. The **SonarDelphi-
migration cluster (SCA120-131)** below covers Delphi-specific
correctness checks that SonarDelphi ships and we ported. The SCA060-119 naming / formatting / structural checks are enumerated
in their own section below (added 2026-07-19); [`rules/sca-rules.json`](rules/sca-rules.json)
remains the canonical machine-readable roster.

🇩🇪 [Deutsche Version](DETECTORS_de.md)

---

## 🔴 Blocker (5)

| # | SCA | Rule | Description | Status | Unit |
|---|-----|------|-------------|--------|------|
| 1 | SCA001 | **MemoryLeak — object never freed** | Object created with `.Create` but no `Free`/`FreeAndNil`/`Destroy` anywhere in the method body. Routines that take ownership of a passed object can be whitelisted via `[Detectors] OwnershipSinks=Routine1,Routine2` (passing the object to such a routine counts as an ownership transfer → no leak) | ✅ | `uLeakDetector2` |
| 2 | SCA002 | **EmptyExcept — empty except block** | `except` block without an executable statement — exceptions are silently swallowed | ✅ | `uCodeSmells2` |
| 3 | SCA008 | **NilDeref — nil pointer without check** | Object field or parameter dereferenced without a prior `Assigned()` check | ✅ | `uNilDeref` |
| 4 | SCA003 | **SQLInjection — string concatenation in SQL** | SQL command built by `+` concatenation with user input — no parameterised query | ✅ | `uSQLInjection` |
| 5 | SCA004 | **HardcodedSecret — password/token in code** | Literal assigned to a variable whose name contains `password`, `token`, `secret`, `key` | ✅ | `uHardcodedSecret` |

---

## 🟠 Critical (10)

| # | SCA | Rule | Description | Status | Unit |
|---|-----|------|-------------|--------|------|
| 6 | SCA010 | **DivByZero — possible division by zero** | Integer division or modulo where the divisor can be zero (no upfront check) | ✅ | `uDivByZero` |
| 7 | SCA134 | **UseAfterFree — object used after Free** | Variable used after `Free`/`FreeAndNil` without being re-assigned | ✅ | `uUseAfterFree` |
| 8 | SCA009 | **MissingFinally — resource without try/finally** | Object created, method has try/except but no try/finally for cleanup | ✅ | `uMissingFinally` |
| 9 | SCA005 | **FormatMismatch — wrong arg count in Format()** | The number of `%s`/`%d` placeholders in the format string does not match the argument list | ✅ | `uFormatMismatch` |
| 10 | SCA135 | **AbstractNotImpl — abstract method not implemented** | Concrete class inherits from an abstract base but doesn't implement all `abstract` methods | ✅ | `uAbstractNotImpl` (within-unit only) |
| 11 | SCA132 | **ExceptionTooGeneral — exception type too broad** | `except on E: Exception` instead of a specific type — masks unexpected errors | ✅ | `uExceptionTooGeneral` |
| 12 | SCA136 | **LeakInConstructor — exception in constructor without cleanup** | Constructor can raise after partial initialisation without calling `Free` | ✅ | `uLeakInConstructor` |
| 13 | — | **MissingDestructor — destructor missing / field not freed** | Class with object fields: no destructor, or a field isn't freed in `Destroy` | ✅ | `uFieldLeak` |
| 14 | SCA137 | **IntegerOverflow — arithmetic overflow** | Multiplication or exponentiation on `Integer`/`Word` without a prior range check | ✅ | `uIntegerOverflow` (Int64 target only) |
| 15 | — | **RaiseWithoutClass — bare `raise`** | A bare `raise` outside an `except` block — produces an Access Violation | ✅ | `uRaiseOutsideExcept` |

---

## 🟡 Major — Reliability (10)

| # | SCA | Rule | Description | Status | Unit |
|---|-----|------|-------------|--------|------|
| 16 | SCA166 | **UninitVar — uninitialised variable** | Local variable read before being assigned on every code path | 🟡 | MVP shipped as `SCA166` (`uUninitVar.pas`) — conservative single-method scope without full path-sensitivity. Slot #16 stays `🟡 partial` until Phase 3 (CFG + symbol table). See [Konzept_SCA166_UninitVar.md](Konzept_SCA166_UninitVar.md). |
| 17 | SCA011 | **DeadCode — unreachable code** | Statements after `Exit`, `Break`, `Continue` or `raise` at the same nesting level | ✅ | `uDeadCode` |
| 18 | SCA150 | **BoolAlwaysTrue — boolean always true/false** | Comparison such as `x >= 0` for `Cardinal` or `Length(s) >= 0` — always evaluates to True | ✅ | `uBoolAlwaysTrue` (Length-pattern only) |
| 19 | SCA144 | **FloatEquality — floating-point comparison with =** | `if a = b` where `a` or `b` is `Single`/`Double`/`Extended` | ✅ | `uFloatEquality` |
| 20 | — | **ResultNotChecked — return value ignored** | A function call whose result (e.g. an error code) is discarded | 🔲 | |
| 21 | SCA149 | **MissingOverride — `override` missing** | Method overrides a parent's `virtual`/`dynamic` method without `override` | ✅ | `uMissingOverride` (within-unit only) |
| 22 | — | **CyclicUnitDep — cyclic unit dependency** | Unit A uses unit B (interface), unit B uses unit A (interface) | 🔲 | |
| 23 | SCA145 | **ExceptInDestructor — exception from destructor** | Destructor contains code that may raise without a try/except | ✅ | `uExceptInDestructor` |
| 24 | — | **PublicFieldNoProperty — public field instead of property** | `public` field exposed directly instead of via `property` with getter/setter | ✅ | `uPublicField` |
| 25 | SCA139 | **FreeWithoutNil — Free without nil-out** | `obj.Free` not followed by `obj := nil` or `FreeAndNil` — dangling pointer possible | ✅ | `uFreeWithoutNil` |

---

## 🟡 Major — Maintainability (10)

| # | SCA | Rule | Description | Status | Unit |
|---|-----|------|-------------|--------|------|
| 26 | SCA012 | **LongMethod — method too long** | Method body exceeds 50 executable lines | ✅ | `uLongMethod` |
| 27 | — | **TooManyParams — too many parameters** | Method has more than 5 parameters | ✅ | `uLongParamList` |
| 28 | SCA022 | **CyclomaticComplexity — McCabe complexity > 10** | Number of branching paths (`if`, `case` arm, `for`, `while`, `repeat`, `on` handler, `and`/`or`/`xor`) exceeds 10 | ✅ | `uCyclomaticComplexity` |
| 29 | SCA018 | **DeepNesting — nesting depth > 4** | Code block indented more than four levels deep | ✅ | `uDeepNesting` |
| 30 | SCA021 | **DuplicateBlock — duplicated code block** | Identical block (≥ `DuplicateBlockMinLines`, default 8 normalized lines) appears more than once in the same file | ✅ | `uDuplicateBlock` (SCA021) — line-based sliding window, normalises trim/lowercase/whitespace-collapse, skips boilerplate (`begin`/`end`/`else`/`try`/`finally`/`except`, pure comments) and if/end branching blocks |
| 31 | SCA138 | **GodClass — god class** | Class has more than 20 methods or more than 15 instance fields | ✅ | `uGodClass` |
| 32 | SCA014 | **MagicNumber — magic number without constant** | Numeric literal (other than 0 and 1) used directly in code instead of a named constant | ✅ | `uMagicNumbers` |
| 33 | SCA146 | **BooleanParam — boolean as flag parameter** | Method takes a `Boolean` parameter used internally for branching | ✅ | `uBooleanParam` |
| 34 | SCA140 | **MultipleExit — more than 3 exit points** | Method contains more than three `Exit` calls | ✅ | `uMultipleExit` |
| 35 | SCA141 | **LargeClass — class too big** | Single-class unit exceeds 500 lines of implementation | ✅ | `uLargeClass` |

---

## 🔵 Minor — Code Smells (10)

| # | SCA | Rule | Description | Status | Unit |
|---|-----|------|-------------|--------|------|
| 36 | — | **UnusedVar — unused local variable** | Variable declared in the `var` block but never read (or only written) | ✅ | `uUnusedLocal` |
| 37 | — | **UnusedMethod — unused private method** | Private method never called inside the unit | ✅ | `uUnusedPrivateMethod` |
| 38 | — | **UnusedUnit — unit in uses not used** | Unit listed in `uses` whose symbols are never referenced | ✅ | `uUnusedUses` |
| 39 | — | **CommentedCode — commented-out code** | Block of commented Pascal code (`//` or `{ }`) without explanation | ✅ | `uCommentedOutCode` |
| 40 | SCA019 | **TodoComment — TODO/FIXME without ticket** | Comment contains `TODO`, `FIXME`, `HACK`, `XXX` without an issue reference | ✅ | `uTodoComment` |
| 41 | SCA020 | **EmptyMethod — empty method** | Method only contains `inherited`, or is completely empty | ✅ | `uEmptyMethod` |
| 42 | — | **UnnecessaryCast — redundant type cast** | Cast to the same type or to a direct ancestor without extension | 🔲 | |
| 43 | SCA151 | **ConstantReturn — method always returns the same value** | Every path returns the same literal — should be a constant | ✅ | `uConstantReturn` |
| 44 | — | **LongLine — line too long** | Line exceeds 120 characters (configurable via `[Detectors] MaxLineLength`) | ✅ | `uTooLongLine` |
| 45 | — | **MixedIndent — mixed indentation (tabs + spaces)** | Line contains both tab and space indentation | ✅ | `uTabulationCharacter` |

---

## ⚪ Info (5)

| # | SCA | Rule | Description | Status | Unit |
|---|-----|------|-------------|--------|------|
| 46 | SCA152 | **HardcodedString — literal instead of resourcestring** | User-visible string as a literal instead of a `resourcestring` declaration | ✅ | `uHardcodedString` (Caption/Hint/Text + ShowMessage) |
| 47 | SCA142 | **UnsortedUses — uses not alphabetic** | Entries in the `uses` section are not in alphabetical order | ✅ | `uUnsortedUses` |
| 48 | SCA143 | **MissingUnitHeader — no unit description comment** | Unit starts without a descriptive comment block (purpose, author, date) | ✅ | `uMissingUnitHeader` |
| 49 | — | **DeprecatedAPI — deprecated API used** | Call to a method or class marked `deprecated` | 🔲 | |
| 50 | SCA148 | **CanBeClassMethod — method without Self access** | Instance method doesn't touch instance fields/methods — could be a `class function` | ✅ | `uCanBeClassMethod` |

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
  ✅ Complete:  44  (#1, #2, #3, #4, #5, #6, #7, #8, #9, #10,
                    #11, #12, #13, #14, #15, #17, #18, #19, #21,
                    #23, #24, #25, #26, #27, #29, #31, #32, #33,
                    #34, #35, #36, #37, #38, #39, #40, #41, #43,
                    #44, #45, #46, #47, #48, #50)
                  Critical (#6-#15) all done. #7/#10/#12/#14/#18/
                  #21/#43/#46 use heuristic AST/lexical patterns
                  with documented limitations (narrow-by-design).
  🟡 Partial:    1  (#30 — strings only, not arbitrary blocks)
  🎁 Bonus:      3  (HardcodedPath, DebugOutput, DuplicateString)
  🔲 Open:       5

  → 48 of 50 Sonar rules backed by Pascal-AST detector code,
    45 of those fully complete.

📐 DFM detectors:                  23 (all complete)
🛡 SonarDelphi-migration:          12 (SCA120-131, all complete)
🏛 mORMot-cluster:                  9 (SCA153-161, all complete)
🧩 SonarDelphi naming/formatting:  59 (SCA060-119, section below)

🎯 Grand total: 162 detector kinds (~130 pipeline classes).
```

---

## 📐 DFM detectors — form-file specific (not in 50-rule Sonar catalogue)

These run against `.dfm` files using a dedicated DFM lexer + parser
+ component graph, with `TFormBinder` coupling the form to its
companion `.pas` AST and `TDfmRepoIndex` providing repo-wide
cross-form lookups. All ship with before/after fix hints in the
help panel and DUnitX tests.

### Dead-Wiring cluster (3) — events / handlers / form↔code coupling

| # | SCA | Rule (`fk…` id) | Description | Type | Unit |
|---|-----|-----------------|-------------|------|------|
| D1 | SCA028 | **DfmDeadEvent** | `OnClick` in the DFM points to a method name that doesn't exist in the form's published section | Bug | `uDfmDeadEvent` |
| D2 | SCA029 | **DfmOrphanHandler** | Published method with `Sender: TObject` signature that no DFM component binds to | Code Smell | `uDfmOrphanHandler` |
| D3 | SCA030 | **DfmEmptyBoundEvent** | Event is bound, target method exists, but the body is empty / `inherited`-only | Code Smell | `uDfmEmptyBoundEvent` |

### Data-Access cluster (4) — datasets, fields, master-detail

| # | SCA | Rule (`fk…` id) | Description | Type | Unit |
|---|-----|-----------------|-------------|------|------|
| D4 | SCA031 | **DfmSchemaMismatch** | DFM `TField`/`TDataSource` has no matching published field in the form class | Bug | `uDfmSchemaMismatch` |
| D5 | SCA032 | **DfmCircularDataSource** | Cycle in `DataSource.DataSet` / `MasterSource` graph — runtime infinite loop / stack overflow | Bug | `uDfmCircularDataSource` |
| D6 | SCA036 | **DfmFieldTypeMismatch** | UI control class doesn't match the `TField` data type (e.g. `TDBEdit` bound to `ftBlob`) | Code Smell | `uDfmFieldTypeMismatch` |
| D7 | SCA034/SCA035 | **DfmRequiredFieldUnbound / NotVisible** | `TField` with `Required=True` has no UI binding at all (Unbound) — or only on a hidden tab (NotVisible) | Bug | `uDfmRequiredField` |

### Security cluster (2) — credentials and SQL injection in DFMs

| # | SCA | Rule (`fk…` id) | Description | Type | Unit |
|---|-----|-----------------|-------------|------|------|
| D8 | SCA026 | **DfmHardcodedDbCreds** | Plaintext credentials on a `TADOConnection` / `TFDConnection` `ConnectionString` / `Params` property | Vulnerability | `uDfmHardcodedDbCreds` |
| D9 | SCA033 | **DfmSqlFromUserInput** | SQL property of a DB-query is built (in `Pascal`) by concatenating `TEdit.Text` or other UI input — DFM smell that pulls the analyser back into Pascal AST | Vulnerability | `uDfmSqlFromUserInput` |

### Layering / Architecture cluster (4) — separation of concerns

| # | SCA | Rule (`fk…` id) | Description | Type | Unit |
|---|-----|-----------------|-------------|------|------|
| D10 | SCA039 | **DfmDbInUiForm** | DB component (`TADOConnection`, `TFDQuery`, `TClientDataSet`, …) sits directly on a UI form instead of a data-module | Code Smell | `uDfmDbInUiForm` |
| D11 | SCA040 | **DfmCrossFormCoupling** | Code in `Form1` reaches into `Form2.<field>` via the global form variable | Bug | `uDfmCrossFormCoupling` |
| D12 | SCA041 | **DfmLayerViolation** | Input control sits directly on `TForm` instead of a Panel / `TFrame` / `TGroupBox` container | Code Smell | `uDfmLayerViolation` |
| D13 | SCA038 | **DfmForbiddenClass** | Component class listed in `analyser.ini → [DfmDetectors] ForbiddenClasses=` is used in a DFM | Code Smell | `uDfmForbiddenClass` |

### UI/UX cluster (4) — interaction smells in the form definition

| # | SCA | Rule (`fk…` id) | Description | Type | Unit |
|---|-----|-----------------|-------------|------|------|
| D14 | SCA027 | **DfmDuplicateBinding** | Multiple components bind the same `OnClick` / same `DataField` etc. — usually a copy-paste bug | Bug | `uDfmDuplicateBinding` |
| D15 | SCA037 | **DfmTabOrderConflict** | Two sibling controls on the same parent share the same `TabOrder` value | Code Smell | `uDfmTabOrderConflict` |
| D16 | SCA042 | **DfmGodHandler** | One method bound to ≥ N components' events — a god-handler that should be split per concern | Code Smell | `uDfmGodHandler` |
| D17 | SCA043 | **DfmActionMismatch** | Component has both `Action=` and `OnClick=` set — the explicit `OnClick` silently wins and the `TAction` glue is wasted | Bug | `uDfmActionMismatch` |

### Naming / Localisation cluster (3) — hygiene

| # | SCA | Rule (`fk…` id) | Description | Type | Unit |
|---|-----|-----------------|-------------|------|------|
| D18 | SCA024 | **DfmDefaultName** | Component still has its default name (`Button1`, `Edit2`, …) | Code Smell | `uDfmDefaultName` |
| D19 | SCA025 | **DfmHardcodedCaption** | UI-visible string (`Caption`, `Hint`, `Text`, …) is a literal in the DFM instead of going through `resourcestring` / dxgettext | Code Smell | `uDfmHardcodedCaption` |
| D20 | SCA026 | **DfmHardcodedDbCreds extras** | _(see D8 — same detector, separate finding kind for parameter values vs. ConnectionString)_ | Vulnerability | `uDfmHardcodedDbCreds` |

### Dead-component cluster (1) — unreferenced components

| # | SCA | Rule (`fk…` id) | Description | Type | Unit |
|---|-----|-----------------|-------------|------|------|
| D21 | SCA184 | **DfmComponentUnused** | Component declared in the DFM is never referenced — not in the form's own code, not by another unit via the global form variable (`Form1.Comp`, resolved through `TSymbolReferenceIndex`), and not by another component inside the DFM (`DataSource=`, `Action=`, …). Likely dead after refactoring. Ships at `fcLow` (below the default `fcMedium` confidence filter — opt-in via `--min-confidence low`); emits nothing without the repo-wide symbol index. Persistent `TField`s, embedded frames, and `FindComponent`-by-name units are deliberately skipped in v1. Known v1 gap: cross-unit **mutations** where the component is a middle chain token (`Form.Comp.Prop := x` / `.Method`) are not yet recognised. | Code Smell | `uDfmComponentUnused` |
| D24 | SCA056 | **DfmMasterDetailUnlinked** | `TDataSet` has `MasterSource` set but no `MasterFields` / `IndexFieldNames` — detail set never filters | Bug | `uDfmMasterDetailUnlinked` |
| D25 | SCA057 | **DfmDataModuleSplitHint** | Aggregated hint: form holds ≥ N DB components — consider extracting a data module | Code Smell | `uDfmDataModuleSplitHint` |

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

## 🏛 mORMot-Cluster — concurrency / pointer / aliasing patterns (SCA153-161)

Nine detectors added after auditing the [mORMot2](https://github.com/synopse/mORMot2)
sources, targeting patterns that recur across large low-level Delphi codebases:
threading primitives, raw heap allocation, dynamic-array growth, byte-level
buffer manipulation, PChar arithmetic, multi-target `with` blocks, typed
exception handlers, string casts from raw pointers, Win64 pointer arithmetic.
All ship with before/after fix hints and a DUnitX test fixture.

| ID | Rule | Description | Severity | Type | Unit |
|----|------|-------------|----------|------|------|
| SCA153 | **UnpairedLock** | `<id>.Lock` / `EnterCriticalSection` / `TMonitor.Enter` followed by a matching unlock in the same routine without an enclosing `try/finally` — exception path leaks the lock and deadlocks the next caller | Warning | Bug | `uUnpairedLock` |
| SCA154 | **MoveSizeOfPointer** | `Move` / `FillChar` / `CopyMemory` / `ZeroMemory` called with `SizeOf(PXxx)` where `PXxx` is a pointer type — copies only 4/8 bytes (the pointer size), not the intended buffer | Warning | Bug | `uMoveSizeOfPointer` |
| SCA155 | **WithMultipleTargets** | `with A, B do` (two or more comma-separated receivers) — ambiguous member lookup; adding a method to either A or B silently changes the body's meaning | Hint | Code Smell | `uWithMultipleTargets` |
| SCA156 | **GetMemWithoutFreeMem** | `GetMem` / `AllocMem` / `ReallocMem` followed by a matching `FreeMem` in the same routine without an enclosing `try/finally` — exception path leaks the raw heap buffer | Warning | Bug | `uGetMemWithoutFreeMem` |
| SCA157 | **SetLengthAppendInLoop** | `SetLength(arr, Length(arr) + N)` inside a `for/while/repeat` loop — quadratic realloc cost; grow once before the loop or use block-grow | Warning | Code Smell | `uSetLengthAppendInLoop` |
| SCA158 | **PointerArithmeticOnString** | `PChar(s) +/- offset` (or `PAnsiChar` / `PWideChar`) without a prior empty-check on `s` — `PChar('')` is NIL, arithmetic on nil triggers Access Violation | Warning | Bug | `uPointerArithmeticOnString` |
| SCA159 | **EmptyOnHandler** | `on E: SomeException do ;` (or empty `begin end`) — typed exception handler silently swallows a specific exception class; worse than bare `except end` because the typed annotation looks intentional | Warning | Bug | `uEmptyOnHandler` |
| SCA160 | **StringFromPointer** | `string(P)` / `AnsiString(P)` / `UTF8String(P)` cast from a P-prefixed pointer assumes a null-terminator — reads past the buffer end if the terminator is missing; heap overread | Warning | Bug | `uStringFromPointer` |
| SCA161 | **PointerSubtraction** | `Cardinal(P1) - Cardinal(P2)` (or Integer / LongWord / LongInt variants) truncates the upper 32 bits of a 64-bit pointer on Win64; use `PtrUInt` / `NativeInt` | Warning | Bug | `uPointerSubtraction` |

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

---

## 🧩 Style, Structure & Correctness — first-generation cluster (21 rules, SCA006–SCA059 remainder)

Checks from the original build-out that predate the Sonar-slot tables above; mostly structural/style rules plus pipeline-level kinds (`SCA006` is emitted by the analyzer itself on unreadable files). DFM-kinds from this ID range live in the DFM section above.

| SCA | Rule | Description | Severity | Type | Status | Unit |
|-----|------|-------------|----------|------|--------|------|
| SCA006 | **FileReadError** | Parser/IO error - source file unreadable or syntactically broken | Error | File Error | ✅ | `uStaticAnalyzer2` |
| SCA007 | **UnusedUses** | Uses-entry possibly unused (no identifier from it referenced) | Hint | Code Smell | ✅ | `uUnusedUses` |
| SCA013 | **LongParamList** | Method has more parameters than configured maximum (default 7) | Hint | Code Smell | ✅ | `uLongParamList` |
| SCA015 | **DuplicateString** | Same string literal appears N+ times - extract to constant | Hint | Code Duplication | ✅ | `uDuplicateString` |
| SCA016 | **HardcodedPath** | Hardcoded C:\ / UNC / Linux path in source | Warning | Security Hotspot | ✅ | `uHardcodedPath` |
| SCA017 | **DebugOutput** | Debug output statement found in production unit | Warning | Code Smell | ✅ | `uDebugOutput` |
| SCA023 | **CustomRule** | Pattern matched by a rule loaded from analyser-rules.yml | Warning | Code Smell | ✅ | `uCustomRuleDetector` |
| SCA044 | **ConcatToFormat** | Multi-segment string concatenation - extract to a Format() call | Warning | Code Smell | ✅ | `uConcatToFormat` |
| SCA045 | **WithStatement** | with statement - scope-shadowing trap the compiler does not warn about | Warning | Code Smell | ✅ | `uWithStatement` |
| SCA046 | **ReversedForRange** | for i := 10 to 1 do - loop body never executes | Error | Bug | ✅ | `uReversedForRange` |
| SCA047 | **SelfAssignment** | Self-assignment - no-op or copy-paste typo | Warning | Bug | ✅ | `uSelfAssignment` |
| SCA048 | **VirtualCallInCtor** | Virtual method invoked from constructor - subclass override sees half-initialised Self | Error | Bug | ✅ | `uVirtualCallInCtor` |
| SCA049 | **LengthUnderflow** | Length / .Count with subtraction - native-uint underflow when empty | Hint | Bug | ✅ | `uLengthUnderflow` |
| SCA050 | **CanBeUnitPrivate** | Public member is referenced only within the current unit - Delphi-classic `private` (unit-scope) suffices | Hint | Code Smell | ✅ | `uVisibilityCheck` |
| SCA051 | **CanBeProtected** | Public member referenced only from subclasses, never externally | Hint | Code Smell | ✅ | `uVisibilityCheck` |
| SCA052 | **UnusedPublicMember** | Public member is never referenced from any subclass or cross-unit path | Hint | Code Smell | ✅ | `uStaticAnalyzer2` |
| SCA053 | **UnusedLocalVar** | Local var declared but never referenced in method body | Hint | Code Smell | ✅ | `uUnusedLocal` |
| SCA054 | **UnusedParameter** | Method parameter is never used in the body | Hint | Code Smell | ✅ | `uUnusedParameter` |
| SCA055 | **TautologicalBoolExpr** | Binary operator with identical LHS and RHS: x = x, a and a, (p <> p) | Error | Bug | ✅ | `uTautologicalExpr` |
| SCA058 | **SqlDangerousStatement** | SQL statement modifies every row - missing WHERE clause | Error | Bug | ✅ | `uSqlDangerousStatement` |
| SCA059 | **FormatLocaleHint** | %.2f / %.3f without explicit TFormatSettings - comma vs dot decimal trap | Hint | Bug | ✅ | `uFormatMismatch` |

---

## 🔤 Naming, Formatting & Convention — SonarDelphi-compatible cluster (59 rules, SCA060–SCA119)

Formerly only referenced via [`rules/sca-rules.json`](rules/sca-rules.json); now enumerated. Multi-kind classes: `uVisibilityCheck` (SCA050/051/107), `uPerfHotspots` (SCA110–112), `uRestHttpSecurity` (SCA115/116), `uConcurrencyExt` (SCA113/114).

| SCA | Rule | Description | Severity | Type | Status | Unit |
|-----|------|-------------|----------|------|--------|------|
| SCA061 | **TabulationCharacter** | Tab characters render inconsistently across editors - use spaces | Hint | Code Smell | ✅ | `uTabulationCharacter` |
| SCA062 | **TooLongLine** | Line exceeds 120 characters - wrap or extract subexpression | Hint | Code Smell | ✅ | `uTooLongLine` |
| SCA063 | **TrailingWhitespace** | Line ends with space or tab - hygiene for diffs | Hint | Code Smell | ✅ | `uTrailingWhitespace` |
| SCA064 | **LowercaseKeyword** | Pascal keywords (`begin`/`end`/`procedure`/...) should be lowercase | Hint | Code Smell | ✅ | `uLowercaseKeyword` |
| SCA065 | **NoSonarMarker** | `// NOSONAR` marker should not silence findings - audit usage | Hint | Code Smell | ✅ | `uNoSonarMarker` |
| SCA066 | **EmptyArgumentList** | `Foo()` should be `Foo;` - drop empty parens | Hint | Code Smell | ✅ | `uEmptyArgumentList` |
| SCA067 | **InlineAssembly** | `asm...end` block - prefer Pascal + compiler intrinsics | Warning | Code Smell | ✅ | `uInlineAssembly` |
| SCA068 | **TrailingCommaArgList** | `Foo(A, B,)` - drop the comma or add the missing argument | Hint | Code Smell | ✅ | `uTrailingCommaArgList` |
| SCA069 | **DigitGrouping** | Large integer literals should use `_` separator | Hint | Code Smell | ✅ | `uDigitGrouping` |
| SCA070 | **CommentedOutCode** | Comment looks like Pascal code - delete or document | Hint | Code Smell | ✅ | `uCommentedOutCode` |
| SCA071 | **UnitLevelKeywordIndent** | `unit`/`interface`/`implementation`/`initialization`/`finalization` should start at column 1 | Hint | Code Smell | ✅ | `uUnitLevelKeywordIndent` |
| SCA072 | **RedundantBoolean** | `X = True` should be `X` (and `X <> False` likewise) | Hint | Code Smell | ✅ | `uRedundantBoolean` |
| SCA073 | **EmptyInterface** | Interface with no methods/properties carries no contract | Hint | Code Smell | ✅ | `uEmptyInterface` |
| SCA074 | **AssertMessage** | `Assert(cond);` - add a `'why'` message for diagnosis | Hint | Code Smell | ✅ | `uAssertMessage` |
| SCA075 | **ExplicitTObjectInheritance** | `class(TObject)` is redundant - drop the parens | Hint | Code Smell | ✅ | `uExplicitTObjectInheritance` |
| SCA076 | **GroupedDeclaration** | Split `A, B: Type` into one declaration per line | Hint | Code Smell | ✅ | `uGroupedDeclaration` |
| SCA077 | **EmptyBlock** | Empty `begin..end` - delete it or fill in the statement | Hint | Code Smell | ✅ | `uEmptyBlock` |
| SCA078 | **ExceptOnException** | `on E: Exception do` swallows everything including AV/OOM | Warning | Bug | ✅ | `uExceptOnException` |
| SCA079 | **ConsecutiveSection** | Two `const`/`type`/`var` blocks in a row should be merged | Hint | Code Smell | ✅ | `uConsecutiveSection` |
| SCA080 | **RedundantJump** | `Exit;` / `Continue;` / `Break;` directly before `end` is a no-op | Hint | Code Smell | ✅ | `uRedundantJump` |
| SCA081 | **ClassPerFile** | One class per unit makes refactoring easier | Hint | Code Smell | ✅ | `uClassPerFile` |
| SCA082 | **SuperfluousSemicolon** | `;;` - drop the extra semicolon | Hint | Code Smell | ✅ | `uSuperfluousSemicolon` |
| SCA083 | **EmptyFinallyBlock** | `try ... finally end;` has no cleanup - either add it or drop the finally | Warning | Bug | ✅ | `uEmptyFinallyBlock` |
| SCA084 | **AssignedAndAssignedNil** | `Assigned(X) and (X <> nil)` - drop the nil check | Hint | Code Smell | ✅ | `uAssignedAndAssignedNil` |
| SCA085 | **FreeAndNilHint** | Use `FreeAndNil(X)` instead of `X.Free; X := nil;` | Hint | Code Smell | ✅ | `uFreeAndNilHint` |
| SCA086 | **AvoidOut** | Prefer `var` over `out` (out has surprising semantics) | Hint | Code Smell | ✅ | `uAvoidOut` |
| SCA087 | **EmptyVisibilitySection** | `public`/`private`/... section header with no members | Hint | Code Smell | ✅ | `uEmptyVisibilitySection` |
| SCA088 | **LegacyInitializationSection** | Use `initialization..end.` instead of legacy `begin..end.` | Hint | Code Smell | ✅ | `uLegacyInitializationSection` |
| SCA089 | **PublicField** | Public field breaks encapsulation - use a property | Hint | Code Smell | ✅ | `uPublicField` |
| SCA090 | **NestedTry** | Nested `try..end` - consider extracting inner try into a method | Hint | Code Smell | ✅ | `uNestedTry` |
| SCA091 | **CaseStatementSize** | `case` with >= 10 branches - consider polymorphism / dispatch table | Hint | Code Smell | ✅ | `uCaseStatementSize` |
| SCA092 | **EmptyFile** | Unit has no type/const/var/procedure/function - delete or fill in | Hint | Code Smell | ✅ | `uEmptyFile` |
| SCA093 | **TwiceInheritedCalls** | Two or more `inherited;` in the same method - parent side-effects run twice | Warning | Bug | ✅ | `uTwiceInheritedCalls` |
| SCA094 | **RedundantParentheses** | `((Ident))` - drop the outer parens | Hint | Code Smell | ✅ | `uRedundantParentheses` |
| SCA095 | **ConsecutiveVisibility** | Same `public`/`private`/etc. section appears twice in one class | Hint | Code Smell | ✅ | `uConsecutiveVisibility` |
| SCA096 | **ConstructorWithoutInherited** | Constructor missing `inherited Create` - parent stays uninitialized | Warning | Bug | ✅ | `uConstructorWithoutInherited` |
| SCA097 | **DestructorWithoutInherited** | Destructor missing `inherited Destroy` - parent cleanup is skipped (leak risk) | Error | Bug | ✅ | `uDestructorWithoutInherited` |
| SCA098 | **RedundantConditional** | `if Cond then X := True else X := False` should be `X := Cond` | Hint | Code Smell | ✅ | `uRedundantConditional` |
| SCA099 | **IfElseBegin** | then-branch uses `begin..end` but else-branch is a single statement | Hint | Code Smell | ✅ | `uIfElseBegin` |
| SCA100 | **PointerName** | `Foo = ^Bar` should be `PBar = ^Bar` (P-prefix convention) | Hint | Code Smell | ✅ | `uPointerName` |
| SCA101 | **BeginEndRequired** | `then`/`else`/`do <stmt>` - prefer explicit `begin..end` | Hint | Code Smell | ✅ | `uBeginEndRequired` |
| SCA102 | **NestedRoutine** | Local nested procedure/function - extract to unit-level | Hint | Code Smell | ✅ | `uNestedRoutines` |
| SCA103 | **FieldName** | Class fields should follow `F<Name>` convention | Hint | Code Smell | ✅ | `uFieldName` |
| SCA104 | **TypeName** | Class and record type aliases should start with `T` | Hint | Code Smell | ✅ | `uTypeName` |
| SCA105 | **InterfaceName** | Interface aliases should start with `I` (`IFoo = interface`) | Hint | Code Smell | ✅ | `uInterfaceName` |
| SCA106 | **MethodName** | Methods should start with an uppercase letter (PascalCase) | Hint | Code Smell | ✅ | `uMethodName` |
| SCA107 | **CanBeStrictPrivate** | Public member is referenced ONLY by methods of its declaring class - `strict private` reaches the strongest encapsulation | Hint | Code Smell | ✅ | `uVisibilityCheck` |
| SCA108 | **SynchronizeInDestructor** | Synchronize() called from destructor Destroy - classic deadlock between worker and UI thread | Error | Bug | ✅ | `uSynchronizeInDestructor` |
| SCA109 | **LockWithoutTryFinally** | TCriticalSection / Monitor / WinAPI lock taken without enclosing try..finally - exception leaves the lock held | Error | Bug | ✅ | `uLockWithoutTryFinally` |
| SCA110 | **StringConcatInLoop** | `s := s + x` inside for/while/repeat - quadratic reallocations | Warning | Code Smell | ✅ | `uPerfHotspots` |
| SCA111 | **ParamByNameInLoop** | `Query.ParamByName('x').AsXxx := ...` inside a loop - linear lookup per iteration | Hint | Code Smell | ✅ | `uPerfHotspots` |
| SCA112 | **FieldByNameInLoop** | `DataSet.FieldByName('x').AsXxx` inside a loop - linear lookup per row | Hint | Code Smell | ✅ | `uPerfHotspots` |
| SCA113 | **ThreadResumeDeprecated** | `MyThread.Resume` - use `MyThread.Start` (since Delphi 2010) | Warning | Code Smell | ✅ | `uConcurrencyExt` |
| SCA114 | **TThreadDestroyWithoutTerminate** | `FreeAndNil(MyThread)` without prior `Terminate; WaitFor` - worker may still run | Error | Bug | ✅ | `uConcurrencyExt` |
| SCA115 | **HttpInsteadOfHttps** | `'http://...'` literal for a remote endpoint - MITM-vulnerable | Warning | Security Hotspot | ✅ | `uRestHttpSecurity` |
| SCA116 | **DisabledTlsVerification** | Empty `SecureProtocols`, `IgnoreCertificateErrors := True`, or `OnVerifyPeer := nil` | Error | Vulnerability | ✅ | `uRestHttpSecurity` |
| SCA117 | **PublicMemberWithoutDoc** | Public method or property in `interface` section with no doc comment directly above | Hint | Code Smell | ✅ | `uPublicMemberWithoutDoc` |
| SCA118 | **ExceptionName** | `class(Exception)`-Descendant should follow Delphi-RTL `E<Name>` convention | Hint | Code Smell | ✅ | `uNamingExt` |
| SCA119 | **LocalConstantName** | `const X = 42;` inside a method - prefer UPPER_SNAKE_CASE for numeric constants | Hint | Code Smell | ✅ | `uNamingExt` |

---

## 🚀 Post-1.0 additions (22 rules — SCA133, SCA147, SCA162–SCA183)

Later waves: security/injection, suppression machinery, the unused-code family and the attribute cluster (SCA180–183).

| SCA | Rule | Description | Severity | Type | Status | Unit |
|-----|------|-------------|----------|------|--------|------|
| SCA133 | **RaiseOutsideExcept** | `raise;` without an exception expression only works *inside* an except handler (re-raise) - outside it raises NIL and produces an Access Violation | Error | Bug | ✅ | `uRaiseOutsideExcept` |
| SCA147 | **UnusedPrivateMethod** | A private method that is never referenced from any other method in the same unit is dead code - delete it or wire it up | Hint | Code Smell | ✅ | `uUnusedPrivateMethod` |
| SCA162 | **InsecureCryptoAlgorithm** | Algorithm name ('MD5', 'SHA1', 'DES', 'RC4', 'TLS1.0', 'SSLv3') or wrapper class (THashMD5, TIdHashSHA1, ...) referenced - vulnerable to collision / known-plaintext attacks | Warning | Vulnerability | ✅ | `uInsecureCryptoAlgorithm` |
| SCA163 | **CommandInjection** | ShellExecute / CreateProcess / WinExec with `+` in the arguments - if any operand is user-controlled it becomes a command-injection vector | Error | Vulnerability | ✅ | `uCommandInjection` |
| SCA164 | **UnusedRoutine** | Standalone procedure/function in the implementation section is never called (word-index based since 2026-07-19) | Hint | Code Smell | ✅ | `uUnusedRoutine` |
| SCA165 | **UnusedSuppression** | A `// noinspection X` marker does not suppress any finding at its target line - either the detector improved (suppression no longer needed) or the suppression target was wrong | Hint | Code Smell | ✅ | `uSuppression` |
| SCA167 | **InsecureRandom** | Random / RandomRange / RandomFrom used without Randomize - Seed=0 yields a deterministic sequence on every run | Warning | Bug | ✅ | `uInsecureRandom` |
| SCA168 | **DefaultCaseInCaseStatement** | case statement has no else branch - unhandled values fall through silently | Hint | CodeSmell | ✅ | `uDefaultCaseInCaseStatement` |
| SCA169 | **AssertWithSideEffect** | Assert(SomeCall) - the call disappears in Release builds and its side effect is silently lost | Warning | Bug | ✅ | `uAssertWithSideEffect` |
| SCA170 | **ConstStringParameter** | string parameter declared without const - causes refcount bump on every call | Hint | CodeSmell | ✅ | `uConstStringParameter` |
| SCA171 | **CompilerDirectiveScope** | {$WARNINGS OFF} (or HINTS/RANGECHECKS/...) without a closing ON - leaks into following units | Warning | CodeSmell | ✅ | `uCompilerDirectiveScope` |
| SCA172 | **BooleanPropertyNaming** | Boolean property name reads as a noun - prefer a verb prefix that scans as a question | Hint | CodeSmell | ✅ | `uBooleanPropertyNaming` |
| SCA173 | **VariantTypeMisuse** | Variant variable inside a method that contains a loop - each Variant operation pays a 10-100x COM dispatch tax | Hint | CodeSmell | ✅ | `uVariantTypeMisuse` |
| SCA174 | **TObjectListWithoutOwnership** | TList<TFoo>.Create + Add(TFoo.Create) - the list does not own its items, every TFoo instance leaks | Warning | Bug | ✅ | `uTObjectListWithoutOwnership` |
| SCA175 | **AnonMethodCaptureLoopVar** | Anonymous method inside `for i := ... do` references i - all closures see the same final value | Error | Bug | ✅ | `uAnonMethodCaptureLoopVar` |
| SCA176 | **CognitiveComplexity** | Sonar-style cognitive-complexity exceeds 15 - nested if/for/while/case is hard to follow mentally | Warning | CodeSmell | ✅ | `uCognitiveComplexity` |
| SCA177 | **ThreadFreeOnTerminateWithRef** | After T.FreeOnTerminate := True, any subsequent T.Field/T.Method access risks Access-Violation if the thread has already self-destructed | Error | Bug | ✅ | `uThreadFreeOnTerminateWithRef` |
| SCA178 | **PathTraversal** | File-open call (TFileStream.Create, AssignFile, ...) with a path expression that concatenates user input (Edit.Text, Request.Params, ...) - path-traversal risk | Error | Vulnerability | ✅ | `uPathTraversal` |
| SCA179 | **AttributeIgnoreWithoutReason** | [Ignore] (no string arg) skips the test silently - add a message explaining why the test is disabled | Hint | CodeSmell | ✅ | `uAttributeIgnoreWithoutReason` |
| SCA180 | **AttributeDuplicate** | Two identical [X] attributes on the same member - copy-paste leftover, no effect | Warning | CodeSmell | ✅ | `uAttributeDuplicate` |
| SCA181 | **AttributeCategoryWithoutString** | [Category] (no arg) is a compile-time error in DUnitX - always pass a category name | Error | Bug | ✅ | `uAttributeCategoryWithoutString` |
| SCA182 | **AttributeTestFixtureWithoutTests** | Class is marked [TestFixture] but contains no [Test] methods - zombie fixture visible in TestInsight but executes nothing | Warning | CodeSmell | ✅ | `uAttributeTestFixtureWithoutTests` |
| SCA183 | **AttributeMisalignment** | Attribute line followed by a blank line - visually loose, often a refactoring leftover | Hint | CodeSmell | ✅ | `uAttributeMisalignment` |

---

## 🔡 Encoding & Trojan-Source family (9 rules, SCA185–SCA193)

Byte-level file-encoding verdicts (computed from the raw file bytes at load time, cached in the text cache since the 2026-07 perf work) plus Trojan-Source / Unicode-abuse checks (CVE-2021-42574).

| SCA | Rule | Description | Severity | Type | Status | Unit |
|-----|------|-------------|----------|------|--------|------|
| SCA185 | **SourceUtf8NoBom** | UTF-8 file without BOM + non-ASCII - compiler reads it as ANSI (mojibake) | Warning | Bug | ✅ | `uSourceEncoding` |
| SCA186 | **SourceInvalidUtf8** | Malformed UTF-8 (overlong / surrogate / out-of-range) under a UTF-8 BOM | Error | File Error | ✅ | `uSourceEncoding` |
| SCA187 | **SourceControlChar** | NUL / disallowed control byte - binary file or mis-detected encoding | Error | File Error | ✅ | `uSourceEncoding` |
| SCA188 | **SourceBidiOverride** | Bidi override/isolate control char - source reads differently than it compiles | Error | Vulnerability | ✅ | `uSourceEncoding` |
| SCA189 | **SourceAnsiNonAscii** | 8-bit source (no BOM, not valid UTF-8) - code-page-dependent, non-portable | Warning | Code Smell | ✅ | `uSourceEncoding` |
| SCA190 | **SourceUtf16** | UTF-16 source - compiles, but unusual and text-tool-unfriendly | Hint | Code Smell | ✅ | `uSourceEncoding` |
| SCA191 | **SourceUtf32** | UTF-32 source - Delphi compiler rejects it with fatal error F2438 | Error | File Error | ✅ | `uSourceEncoding` |
| SCA192 | **SourceInvisibleChar** | Zero-width/invisible Unicode char - hidden-text / homoglyph abuse vector | Warning | Vulnerability | ✅ | `uSourceEncoding` |
| SCA193 | **SourceNonAsciiIdentifier** | Identifier contains a non-ASCII letter - homoglyph / confusable risk | Warning | Vulnerability | ✅ | `uSourceEncoding` |

---

## 🗂️ Project-scope (SCA194) — 1 rule

Not an AST/per-file detector: runs only for `.dproj`/`.groupproj` scans (CLI `--project`/`--project-group`, or the `...` dialog) and compares the project's referenced file list against the `.pas`/`.dfm` files physically in the project folder. Emitted from the scan dispatch (`TAnalysisSession.Run`), gated by profile + min-severity.

| SCA | Rule | Description | Severity | Type | Status | Unit |
|-----|------|-------------|----------|------|--------|------|
| SCA194 | **NotIncludedInProject** | .pas/.dfm in the project folder but not referenced by the project (.dproj/.groupproj) - orphaned / dead source | Hint | Code Smell | ✅ | `uNotIncludedInProject` |

## ⚙️ Configuration — SCA001 OwnershipSinks (memory-leak whitelist)

Some codebases hand a freshly-created object to a routine that **takes ownership** of it (registers it in an owning container, serialises-and-frees it, adds it to a builder tree). SCA001 cannot see across the call boundary, so it reports these as leaks even though the callee frees the object. Whitelist such routines per project in `analyser.ini`:

```ini
[Detectors]
OwnershipSinks=Render,RegisterInstance
```

Passing a tracked object to a listed routine (`Render(obj)`, `Foo.RegisterInstance(obj)`) then counts as an ownership transfer → no SCA001 finding. Matching is by routine name (the part before `(`), receiver-independent, with a left word-boundary so `Owner` never matches `PreOwner(`.

**The default is empty — and deliberately so.** A real-world audit of 1262 SCA001 findings across 24 repos showed that genuine ownership sinks are **100 % framework-specific** — no routine name transfers ownership across codebases. Ship-wide defaults were rejected because the tempting candidates are dangerous:

- ❌ **Never list `LoadFromStream` / `SaveToStream` / `Assign` / any RTL name.** These *borrow* their argument — they do not take ownership. Whitelisting them masks genuine leaks. (The audit found real, unfreed `TMemoryStream` leaks that such a whitelist would have hidden.)
- ✅ Only list routines you **know** take ownership, and only for the framework that defines them.

Recommended opt-in sets by framework (add only what your project uses):

| Framework | Ownership-taking routines | Example |
|-----------|---------------------------|---------|
| DelphiMVCFramework | `Render` (serialises the object then frees it) | `OwnershipSinks=Render` |
| JVCL inspector / DI | `RegisterInstance` | `OwnershipSinks=RegisterInstance` |
| SwagDoc builders | `AddParameter,AddType,AddLocalVariable` (parent node owns the child) | `OwnershipSinks=AddParameter,AddType,AddLocalVariable` |

Rule of thumb: if you cannot point at the line in the callee that frees the argument, do **not** list it.

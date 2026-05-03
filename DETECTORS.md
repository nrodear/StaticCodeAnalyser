# Detectors — Sonar rule catalogue for the Static Code Analysis Tool for Delphi

Canonical list of all supported and planned analysis rules, ordered by
severity (Blocker → Critical → Major → Minor → Info). The catalogue
follows the Sonar 50-rule taxonomy and adds a handful of bonus detectors
specific to this tool.

Status legend: ✅ implemented · 🟡 partial · 🔲 open

**Summary:** 17 / 50 complete + 1 partial + 3 bonus detectors = **21 active detectors**.

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
| 7 | **UseAfterFree — object used after Free** | Variable used after `Free`/`FreeAndNil` without being re-assigned | 🔲 | |
| 8 | **MissingFinally — resource without try/finally** | Object created, method has try/except but no try/finally for cleanup | ✅ | `uMissingFinally` |
| 9 | **FormatMismatch — wrong arg count in Format()** | The number of `%s`/`%d` placeholders in the format string does not match the argument list | ✅ | `uFormatMismatch` |
| 10 | **AbstractNotImpl — abstract method not implemented** | Concrete class inherits from an abstract base but doesn't implement all `abstract` methods | 🔲 | |
| 11 | **ExceptionTooGeneral — exception type too broad** | `except on E: Exception` instead of a specific type — masks unexpected errors | 🔲 | |
| 12 | **LeakInConstructor — exception in constructor without cleanup** | Constructor can raise after partial initialisation without calling `Free` | 🔲 | |
| 13 | **MissingDestructor — destructor missing / field not freed** | Class with object fields: no destructor, or a field isn't freed in `Destroy` | ✅ | `uFieldLeak` |
| 14 | **IntegerOverflow — arithmetic overflow** | Multiplication or exponentiation on `Integer`/`Word` without a prior range check | 🔲 | |
| 15 | **RaiseWithoutClass — bare `raise`** | A bare `raise` outside an `except` block — produces an Access Violation | 🔲 | |

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
| 28 | **HighComplexity — cyclomatic complexity > 10** | Number of branching paths (`if`, `case`, `for`, `while`, `and`, `or`) exceeds 10 | 🔲 | |
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
✅ Complete:  17  (#1, #2, #3, #4, #5, #6, #8, #9, #13, #17,
                  #26, #27, #29, #32, #38, #40, #41)
🟡 Partial:    1  (#30 — strings only, not arbitrary blocks)
🎁 Bonus:      3  (HardcodedPath, DebugOutput, DuplicateString)
🔲 Open:      32

→ 21 of 50 rules backed by detector code, 18 of those fully complete.
```

---

## Suggested implementation phases

```
Phase 1 — missing Blocker / Critical : #7  UseAfterFree, #15 RaiseWithoutClass
Phase 2 — Major reliability          : #16 UninitVar, #20 ResultNotChecked, #25 FreeWithoutNil
Phase 3 — Major maintainability      : #28 HighComplexity, #34 MultipleExit, #31 GodClass
Phase 4 — Minor                      : #36 UnusedVar, #39 CommentedCode, #44 LongLine
Phase 5 — Info                       : #47 UnsortedUses, #49 DeprecatedAPI, #50 CanBeClassMethod
```

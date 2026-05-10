# StaticCodeAnalyser — Rule Catalog

All 22 detector rules. Single source of truth: [`rules/sca-rules.json`](../rules/sca-rules.json).

| ID | Name | Severity | Type | Detector |
|---|---|---|---|---|
| [SCA001](#sca001) | Object created without try/finally | Error | Bug | `uLeakDetector2.pas` |
| [SCA002](#sca002) | Empty except block | Warning | Code Smell | `uCodeSmells2.pas` |
| [SCA003](#sca003) | SQL string built via concatenation | Error | Vulnerability | `uSQLInjection.pas` |
| [SCA004](#sca004) | Hardcoded credential / API token | Error | Vulnerability | `uHardcodedSecret.pas` |
| [SCA005](#sca005) | Format() placeholder count mismatch | Error | Bug | `uFormatMismatch.pas` |
| [SCA006](#sca006) | File could not be read or parsed | Error | File Error | `(parser)` |
| [SCA007](#sca007) | Unused unit in uses clause | Hint | Code Smell | `uUnusedUses.pas` |
| [SCA008](#sca008) | Possible nil-dereference | Warning | Bug | `uNilDeref.pas` |
| [SCA009](#sca009) | Object created without protective try/finally | Warning | Code Smell | `uMissingFinally.pas` |
| [SCA010](#sca010) | Possible division by zero | Warning | Bug | `uDivByZero.pas` |
| [SCA011](#sca011) | Code after Exit/Raise is unreachable | Warning | Code Smell | `uDeadCode.pas` |
| [SCA012](#sca012) | Method exceeds line-count threshold | Hint | Code Smell | `uLongMethod.pas` |
| [SCA013](#sca013) | Too many parameters | Hint | Code Smell | `uLongParamList.pas` |
| [SCA014](#sca014) | Numeric literal without named constant | Hint | Code Smell | `uMagicNumbers.pas` |
| [SCA015](#sca015) | String literal repeated across multiple sites | Hint | Code Duplication | `uDuplicateString.pas` |
| [SCA016](#sca016) | Filesystem path as string literal | Warning | Security Hotspot | `uHardcodedPath.pas` |
| [SCA017](#sca017) | WriteLn/ShowMessage in production code | Warning | Code Smell | `uDebugOutput.pas` |
| [SCA018](#sca018) | Block nesting exceeds threshold | Hint | Code Smell | `uDeepNesting.pas` |
| [SCA019](#sca019) | TODO/FIXME marker in comment | Hint | Code Smell | `uTodoComment.pas` |
| [SCA020](#sca020) | Empty method body | Hint | Code Smell | `uEmptyMethod.pas` |
| [SCA021](#sca021) | Duplicated code block | Hint | Code Duplication | `uDuplicateBlock.pas` |
| [SCA022](#sca022) | Method exceeds McCabe complexity threshold | Hint | Code Smell | `uCyclomaticComplexity.pas` |

---

## SCA001
**Object created without try/finally**

> Object created but never freed (potential memory leak)

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `memory`, `resource-leak` |
| CWE | [CWE-401](https://cwe.mitre.org/data/definitions/401.html) |
| Config | `[Detectors] LeakyClasses` |
| Detector | `uLeakDetector2.pas` |

`TObject.Create` (or `LeakyClass.Create`) without a protective `try/finally` block leaks the instance when subsequent code raises an exception. The `Free` call must run regardless of how the protected block exits.

```pascal
// BAD
list := TStringList.Create;
DoStuff(list);   // <-- exception here leaks list

// GOOD
list := TStringList.Create;
try
  DoStuff(list);
finally
  list.Free;
end;
```

---

## SCA002
**Empty except block**

> Empty except block silently swallows every exception

| Field | Value |
|---|---|
| Severity | Warning | Type | Code Smell |
| Tags | `error-handling` |
| CWE | [CWE-390](https://cwe.mitre.org/data/definitions/390.html) |
| Detector | `uCodeSmells2.pas` |

An except-block with no statements catches every exception including unexpected ones (`EAccessViolation`, `EOutOfMemory`). Bugs become invisible. At minimum log the exception or re-raise.

```pascal
// BAD
try DoStuff except end;

// GOOD
try DoStuff except on E: Exception do LogError(E.Message); end;
```

---

## SCA003
**SQL string built via concatenation**

> SQL string concatenated with '+' from user-controllable input (injection risk)

| Field | Value |
|---|---|
| Severity | **Error** | Type | Vulnerability |
| Tags | `sql`, `injection`, `security` |
| CWE | [CWE-89](https://cwe.mitre.org/data/definitions/89.html) |
| OWASP | A03:2021-Injection |
| Detector | `uSQLInjection.pas` |

Building SQL via `'WHERE x=' + user_input` enables SQL injection if the input is untrusted. Use parameterized queries instead.

```pascal
// BAD
Query.SQL.Text := 'SELECT * FROM Users WHERE Name=''' + UserName + '''';

// GOOD
Query.SQL.Text := 'SELECT * FROM Users WHERE Name=:n';
Query.ParamByName('n').AsString := UserName;
```

---

## SCA004
**Hardcoded credential / API token**

> Password / API key / token as string literal in source code

| Field | Value |
|---|---|
| Severity | **Error** | Type | Vulnerability |
| Tags | `credentials`, `security` |
| CWE | [CWE-798](https://cwe.mitre.org/data/definitions/798.html) |
| OWASP | A07:2021-Identification-and-Authentication-Failures |
| Detector | `uHardcodedSecret.pas` |

Credentials in source code end up in version control, build artifacts, decompilers, and stack traces. Move secrets to environment variables, OS credential store, or encrypted configuration.

```pascal
// BAD
Password := 'admin123';

// GOOD
Password := GetEnvironmentVariable('DB_PASSWORD');
```

---

## SCA005
**Format() placeholder count mismatch**

> Format() / FormatUtf8() placeholder count does not match argument count

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `string-formatting` |
| Config | `[Detectors] FormatFunctions` |
| Detector | `uFormatMismatch.pas` |

Mismatched placeholders cause `EConvertError` at runtime. Detector handles RTL `Format` (`%s`/`%d`/...) and mORMot bare-`%` style (`FormatUtf8`/`FormatString`).

```pascal
// BAD
Format('%s is %d', [Name]);   // Age missing

// GOOD
Format('%s is %d', [Name, Age]);
```

---

## SCA006
**File could not be read or parsed**

> Parser/IO error - source file unreadable or syntactically broken

| Field | Value |
|---|---|
| Severity | **Error** | Type | File Error |
| Tags | `parser`, `io` |
| Detector | `(parser)` |

Special-case finding (no code defect): the file could not be loaded or the lexer/parser failed. Often indicates encoding issues, includes that don't resolve, or genuine syntax errors.

---

## SCA007
**Unused unit in uses clause**

> Uses-entry possibly unused (no identifier from it referenced)

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dead-code`, `uses-cleanup` |
| Detector | `uUnusedUses.pas` |

Heuristic: scans for any identifier from the used unit. False positives possible for units that only register classes / initialize global state via initialization sections.

---

## SCA008
**Possible nil-dereference**

> Access to a variable that may be nil at this point

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `nil-safety` |
| CWE | [CWE-476](https://cwe.mitre.org/data/definitions/476.html) |
| Detector | `uNilDeref.pas` |

Variable was assigned a value that could be nil (e.g. `Find...`-method returning nil) and is dereferenced without prior nil-check. Crashes with `EAccessViolation` at runtime.

```pascal
// BAD
obj := FindObject(id);
obj.DoStuff;   // AV if FindObject returns nil

// GOOD
obj := FindObject(id);
if Assigned(obj) then obj.DoStuff;
```

---

## SCA009
**Object created without protective try/finally**

> .Create call without surrounding try/finally - leak risk on exception

| Field | Value |
|---|---|
| Severity | Warning | Type | Code Smell |
| Tags | `memory`, `exception-safety` |
| Detector | `uMissingFinally.pas` |

Similar to MemoryLeak (SCA001) but checked structurally: any `.Create` followed by code without an enclosing `try/finally` is flagged regardless of whether `Free` is called eventually.

```pascal
// BAD
obj := TFoo.Create;
obj.DoStuff;
obj.Free;

// GOOD
obj := TFoo.Create;
try obj.DoStuff finally obj.Free end;
```

---

## SCA010
**Possible division by zero**

> Division by a variable / expression that may be zero

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `arithmetic` |
| CWE | [CWE-369](https://cwe.mitre.org/data/definitions/369.html) |
| Detector | `uDivByZero.pas` |

Right-hand side of `div`, `mod`, or `/` is a variable without prior guard against zero. Integer division crashes with `EDivByZero`, float division silently produces Inf/NaN.

```pascal
// BAD
result := total / count;

// GOOD
if count <> 0 then result := total / count;
```

---

## SCA011
**Code after Exit/Raise is unreachable**

> Statement after Exit, raise, or Halt is dead code

| Field | Value |
|---|---|
| Severity | Warning | Type | Code Smell |
| Tags | `dead-code` |
| CWE | [CWE-561](https://cwe.mitre.org/data/definitions/561.html) |
| Detector | `uDeadCode.pas` |

Anything after an unconditional terminator (`Exit`, `raise`, `Halt`, `Continue`, `Break`) in the same block is never executed. Usually leftover code from refactoring.

```pascal
// BAD
Exit;
WriteLn('never reached');

// GOOD
(remove the unreachable line)
```

---

## SCA012
**Method exceeds line-count threshold**

> Method longer than configured maximum (default 80 lines)

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `maintainability`, `complexity` |
| Config | `[Detectors] LongMethodMax` |
| Detector | `uLongMethod.pas` |

Long methods are hard to test and understand. Threshold configurable; consider extracting helper methods or splitting responsibilities.

---

## SCA013
**Too many parameters**

> Method has more parameters than configured maximum (default 7)

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `api-design` |
| Config | `[Detectors] LongParamMax` |
| Detector | `uLongParamList.pas` |

High parameter counts indicate the method is doing too much. Consider grouping related parameters into a record or class.

```pascal
// BAD
procedure SaveOrder(id, customer, address, city, zip, country, total, tax, shipping: ...);

// GOOD
procedure SaveOrder(const Order: TOrder);
```

---

## SCA014
**Numeric literal without named constant**

> Numeric literal in expression - extract to a named constant

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `maintainability` |
| Detector | `uMagicNumbers.pas` |

Numeric literals in business logic are unexplained. Use named constants for readability and single-point-of-change.

```pascal
// BAD
if RetryCount > 3 then ...

// GOOD
const MAX_RETRIES = 3;
if RetryCount > MAX_RETRIES then ...
```

---

## SCA015
**String literal repeated across multiple sites**

> Same string literal appears N+ times - extract to constant

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Duplication |
| Tags | `maintainability` |
| Config | `[Detectors] DuplicateStringMin` |
| Detector | `uDuplicateString.pas` |

Repeated strings are change-coupling hazards (typo in one place silently diverges from the others). Extract to a const, especially for user-facing messages.

---

## SCA016
**Filesystem path as string literal**

> Hardcoded C:\ / UNC / Linux path in source

| Field | Value |
|---|---|
| Severity | Warning | Type | Security Hotspot |
| Tags | `portability`, `configuration` |
| Detector | `uHardcodedPath.pas` |

Hardcoded paths break portability and CI deployment. Use config files, environment variables, or platform-aware path helpers (`TPath.Combine`, etc).

```pascal
// BAD
LogFile := 'C:\Logs\app.log';

// GOOD
LogFile := TPath.Combine(GetEnvironmentVariable('LOGDIR'), 'app.log');
```

---

## SCA017
**WriteLn/ShowMessage in production code**

> Debug output statement found in production unit

| Field | Value |
|---|---|
| Severity | Warning | Type | Code Smell |
| Tags | `debug-code` |
| Detector | `uDebugOutput.pas` |

`WriteLn` / `ShowMessage` / `OutputDebugString` usually indicate forgotten debug code. Use a proper logging framework with configurable levels.

---

## SCA018
**Block nesting exceeds threshold**

> Nested if/for/while depth higher than configured maximum (default 4)

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `complexity` |
| Config | `[Detectors] DeepNestingMax` |
| Detector | `uDeepNesting.pas` |

Deep nesting hurts readability and indicates the method is doing too much. Use guard clauses (early `Exit`) or extract inner blocks into helper methods.

```pascal
// BAD
if a then
  if b then
    if c then
      if d then DoStuff;

// GOOD
if not a then Exit;
if not b then Exit;
if not c then Exit;
if d then DoStuff;
```

---

## SCA019
**TODO/FIXME marker in comment**

> Open TODO / FIXME / HACK / XXX marker - resolve before release

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `work-tracking` |
| Detector | `uTodoComment.pas` |

Tracks open work items embedded in source. CI can enforce zero TODOs in release branches.

---

## SCA020
**Empty method body**

> Method body has no statements

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `maintainability` |
| Detector | `uEmptyMethod.pas` |

Empty method may indicate a forgotten implementation, a TODO that was never followed up, or an interface stub. Make intent explicit (assert, exception, or comment).

```pascal
// BAD
procedure DoStuff;
begin
end;

// GOOD
procedure DoStuff;
begin
  raise ENotImplemented.Create('...');
end;
```

---

## SCA021
**Duplicated code block**

> Multiple identical code blocks (>= configured minimum lines)

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Duplication |
| Tags | `dry` |
| Config | `[Detectors] DuplicateBlockMinLines` |
| Detector | `uDuplicateBlock.pas` |

Detects copy-paste blocks with at least N consecutive identical lines. Extract into a helper method or shared constant.

---

## SCA022
**Method exceeds McCabe complexity threshold**

> Cyclomatic Complexity > configured threshold (default 10)

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `complexity`, `maintainability`, `metrics` |
| Config | `[Detectors] CyclomaticMax` |
| Detector | `uCyclomaticComplexity.pas` |

McCabe complexity counts decision points (1 base + `if` + `case`-arm + `for`/`while`/`repeat` + `on`-handler + `and`/`or`/`xor`). High complexity is hard to test and understand.

---

_For richer per-rule pages with badges and full examples, install Python and run `python tools/gen-rules-docs.py`. Generated files land in `docs/rules/SCA001.md`...`SCA022.md`._

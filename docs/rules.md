# StaticCodeAnalyser — Rule Catalog

All 59 detector rules. Single source of truth: [`rules/sca-rules.json`](../rules/sca-rules.json).

| ID | Name | Severity | Type | Detector |
|---|---|---|---|---|
| [SCA001](#sca001) | Object created without try/finally | **Error** | Bug | `uLeakDetector2.pas` |
| [SCA002](#sca002) | Empty except block | Warning | Code Smell | `uCodeSmells2.pas` |
| [SCA003](#sca003) | SQL string built via concatenation | **Error** | Vulnerability | `uSQLInjection.pas` |
| [SCA004](#sca004) | Hardcoded credential / API token | **Error** | Vulnerability | `uHardcodedSecret.pas` |
| [SCA005](#sca005) | Format() placeholder count mismatch | **Error** | Bug | `uFormatMismatch.pas` |
| [SCA006](#sca006) | File could not be read or parsed | **Error** | File Error | `(parser)` |
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
| [SCA023](#sca023) | User-defined custom rule | Warning | Code Smell | `uCustomRuleDetector.pas` |
| [SCA024](#sca024) | Component with default name | Hint | Code Smell | `uDfmDefaultName.pas` |
| [SCA025](#sca025) | Hardcoded UI text in DFM | Hint | Code Smell | `uDfmHardcodedCaption.pas` |
| [SCA026](#sca026) | Hardcoded DB credentials in DFM | **Error** | Vulnerability | `uDfmHardcodedDbCreds.pas` |
| [SCA027](#sca027) | Duplicate (DataSource, DataField) binding | Warning | Bug | `uDfmDuplicateBinding.pas` |
| [SCA028](#sca028) | DFM event handler references missing method | **Error** | Bug | `uDfmDeadEvent.pas` |
| [SCA029](#sca029) | Orphan event handler | Hint | Code Smell | `uDfmOrphanHandler.pas` |
| [SCA030](#sca030) | Empty bound event handler | Hint | Code Smell | `uDfmEmptyBoundEvent.pas` |
| [SCA031](#sca031) | DFM component without published field | **Error** | Bug | `uDfmSchemaMismatch.pas` |
| [SCA032](#sca032) | Circular DataSource / Master-Detail loop | **Error** | Bug | `uDfmCircularDataSource.pas` |
| [SCA033](#sca033) | SQL property built from UI input | **Error** | Vulnerability | `uDfmSqlFromUserInput.pas` |
| [SCA034](#sca034) | Required field has no UI binding | Warning | Bug | `uDfmRequiredField.pas` |
| [SCA035](#sca035) | Required field only on hidden controls | Warning | Bug | `uDfmRequiredField.pas` |
| [SCA036](#sca036) | UI control type mismatched with TField | Hint | Code Smell | `uDfmFieldTypeMismatch.pas` |
| [SCA037](#sca037) | Duplicate TabOrder among siblings | Hint | Code Smell | `uDfmTabOrderConflict.pas` |
| [SCA038](#sca038) | Component uses forbidden class | Hint | Code Smell | `uDfmForbiddenClass.pas` |
| [SCA039](#sca039) | DB component on UI form | Hint | Code Smell | `uDfmDbInUiForm.pas` |
| [SCA040](#sca040) | Cross-form field access | Warning | Bug | `uDfmCrossFormCoupling.pas` |
| [SCA041](#sca041) | Input control directly on TForm | Hint | Code Smell | `uDfmLayerViolation.pas` |
| [SCA042](#sca042) | God event handler | Hint | Code Smell | `uDfmGodHandler.pas` |
| [SCA043](#sca043) | Component has Action + OnClick | Warning | Bug | `uDfmActionMismatch.pas` |
| [SCA044](#sca044) | Long string concat - prefer Format() | Warning | Code Smell | `uConcatToFormat.pas` |
| [SCA045](#sca045) | with X do ... | Warning | Code Smell | `uWithStatement.pas` |
| [SCA046](#sca046) | for i := High to Low - missing downto | **Error** | Bug | `uReversedForRange.pas` |
| [SCA047](#sca047) | x := x | Warning | Bug | `uSelfAssignment.pas` |
| [SCA048](#sca048) | Virtual call in constructor | **Error** | Bug | `uVirtualCallInCtor.pas` |
| [SCA049](#sca049) | Length(s) - N without guard | Hint | Bug | `uLengthUnderflow.pas` |
| [SCA050](#sca050) | Public member could be private | Hint | Code Smell | `uVisibilityCheck.pas` |
| [SCA051](#sca051) | Public member could be protected | Hint | Code Smell | `uVisibilityCheck.pas` |
| [SCA052](#sca052) | Unused public member (dead API) | Hint | Code Smell | `uVisibilityCheck.pas` |
| [SCA053](#sca053) | Unused local variable | Hint | Code Smell | `uUnusedLocal.pas` |
| [SCA054](#sca054) | Unused method parameter | Hint | Code Smell | `uUnusedParameter.pas` |
| [SCA055](#sca055) | Tautological boolean expression | **Error** | Bug | `uTautologicalExpr.pas` |
| [SCA056](#sca056) | Master-Detail without MasterFields | **Error** | Bug | `uDfmMasterDetailUnlinked.pas` |
| [SCA057](#sca057) | Form has many DB components - split DataModule | Hint | Code Smell | `uDfmDataModuleSplitHint.pas` |
| [SCA058](#sca058) | UPDATE / DELETE / TRUNCATE without WHERE | **Error** | Bug | `uSqlDangerousStatement.pas` |
| [SCA059](#sca059) | Format() float spec without TFormatSettings | Hint | Bug | `uFormatMismatch.pas` |

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

## SCA023
**User-defined custom rule**

> Pattern matched by a rule loaded from analyser-rules.yml

| Field | Value |
|---|---|
| Severity | Warning | Type | Code Smell |
| Tags | `custom`, `user-defined` |
| Config | `analyser-rules.yml` |
| Detector | `uCustomRuleDetector.pas` |

Generic kind for user-defined regex / AST rules loaded at runtime from `analyser-rules.yml`. Specific rule ID, message, and severity come from the YAML entry; this catalog entry is a placeholder so the dispatcher and SARIF exporter have stable metadata.

---

## SCA024
**Component with default name**

> Component left at wizard-default name (Button1, Edit3, Panel2 ...)

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dfm`, `naming` |
| Detector | `uDfmDefaultName.pas` |

Default names hide intent and break find-usages / rename refactorings. Rename UI controls to convey purpose (`btnSave`, `edUserName`, `pnlToolbar` ...).

```dfm
// BAD
object Button1: TButton
  Caption = 'Save'
end

// GOOD
object btnSave: TButton
  Caption = 'Save'
end
```

---

## SCA025
**Hardcoded UI text in DFM**

> Caption / Hint / Text property as literal in DFM, not via i18n layer

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dfm`, `i18n`, `localization` |
| Detector | `uDfmHardcodedCaption.pas` |

User-facing strings embedded in a `.dfm` cannot be localised, A/B-tested, or kept in a translation catalog. Assign at form construction time from a `resourcestring` or i18n helper.

---

## SCA026
**Hardcoded DB credentials in DFM**

> Plaintext Password / ConnectionString with Pwd= on a DB component

| Field | Value |
|---|---|
| Severity | **Error** | Type | Vulnerability |
| Tags | `dfm`, `credentials`, `security` |
| CWE | [CWE-798](https://cwe.mitre.org/data/definitions/798.html) |
| OWASP | A07:2021-Identification-and-Authentication-Failures |
| Detector | `uDfmHardcodedDbCreds.pas` |

Database credentials persisted in a `.dfm` leak into version control, build artifacts, and any decompiler. Move secrets to environment variables, OS credential store, or encrypted configuration and assign at runtime.

```dfm
// BAD
object FDConnection1: TFDConnection
  Params.Strings = ('Password=admin123' 'User_Name=sa')
end

// GOOD (.pas at runtime)
FDConnection1.Params.Values['Password'] := GetEnvironmentVariable('DB_PWD');
```

---

## SCA027
**Duplicate (DataSource, DataField) binding**

> Two or more controls bind the same (DataSource, DataField) pair

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `dfm`, `db-binding` |
| Detector | `uDfmDuplicateBinding.pas` |

When the user edits one bound control, the second receives a parallel update from the dataset - racey, hard-to-debug overwrites. Bind each `(DataSource, DataField)` to exactly one control.

---

## SCA028
**DFM event handler references missing method**

> OnClick / On... points to a method that does not exist in the form class

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `dfm`, `streaming`, `dead-code` |
| Detector | `uDfmDeadEvent.pas` |

DFM streaming crashes at form-load time with *"class TForm has no published method X"*. Usually caused by a manual rename in the `.pas` without updating the `.dfm`.

---

## SCA029
**Orphan event handler**

> Published TNotifyEvent-shaped method has no DFM binding

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dfm`, `dead-code` |
| Detector | `uDfmOrphanHandler.pas` |

Method looks like an event handler (`Sender: TObject`) but nothing in any `.dfm` references it. Likely leftover from a deleted control - remove or wire it up.

---

## SCA030
**Empty bound event handler**

> Event is wired in DFM, method exists, body is empty

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dfm`, `stub` |
| Detector | `uDfmEmptyBoundEvent.pas` |

An empty handler with a live DFM binding is almost always a stub forgotten after the designer added it. Either remove the binding or implement the handler.

---

## SCA031
**DFM component without published field**

> Component in DFM has no matching published field in the form class

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `dfm`, `streaming` |
| Detector | `uDfmSchemaMismatch.pas` |

DFM streaming requires every named component to have a corresponding `published` field in the host class. A missing field crashes form construction with `EReadError`.

---

## SCA032
**Circular DataSource / Master-Detail loop**

> Cycle in DataSource.DataSet / DataSet.MasterSource edges

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `dfm`, `data-access`, `infinite-loop` |
| Detector | `uDfmCircularDataSource.pas` |

A cycle in the master-detail graph causes infinite recursion during `BeforeOpen` or any refresh and stack-overflows the process. Break the cycle by removing one of the links.

---

## SCA033
**SQL property built from UI input**

> Query.SQL assembled from form-control Text / Caption properties

| Field | Value |
|---|---|
| Severity | **Error** | Type | Vulnerability |
| Tags | `dfm`, `sql`, `injection`, `security` |
| CWE | [CWE-89](https://cwe.mitre.org/data/definitions/89.html) |
| OWASP | A03:2021-Injection |
| Detector | `uDfmSqlFromUserInput.pas` |

SQL string built from form field values is SQL injection via the UI. Use parameterised queries.

```pascal
// BAD
FDQuery1.SQL.Text := 'SELECT * FROM U WHERE Name=''' + EdName.Text + '''';

// GOOD
FDQuery1.SQL.Text := 'SELECT * FROM U WHERE Name=:n';
FDQuery1.ParamByName('n').AsString := EdName.Text;
```

---

## SCA034
**Required field has no UI binding**

> TField with Required=True has no bound input control

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `dfm`, `ux`, `required-field` |
| Detector | `uDfmRequiredField.pas` |

A required field that the user cannot reach makes every insert fail with *"Field X must have a value"*. Either bind a control or drop `Required=True`.

---

## SCA035
**Required field only on hidden controls**

> TField with Required=True is bound only to Visible=False controls

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `dfm`, `ux`, `required-field` |
| Detector | `uDfmRequiredField.pas` |

Control exists but the user cannot see or interact with it - inserts fail every time. Make at least one bound control visible or drop `Required=True`.

---

## SCA036
**UI control type mismatched with TField**

> DB control class does not match TField.DataType (TDBEdit for TBooleanField)

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dfm`, `ux`, `db-binding` |
| Detector | `uDfmFieldTypeMismatch.pas` |

User sees the raw value and can corrupt the type. Pick a control compatible with the field type (`TDBCheckBox` for booleans, `TDBLookupComboBox` for FKs).

---

## SCA037
**Duplicate TabOrder among siblings**

> Two sibling controls in the same parent share the same TabOrder value

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dfm`, `ux` |
| Detector | `uDfmTabOrderConflict.pas` |

VCL serialisation tolerates duplicate `TabOrder` but tab navigation becomes order-of-declaration dependent and unpredictable for the user. Renumber so `TabOrder` is unique per parent.

---

## SCA038
**Component uses forbidden class**

> Component class is in the project's ForbiddenClasses list

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dfm`, `style-guide` |
| Config | `[Components] ForbiddenClasses` |
| Detector | `uDfmForbiddenClass.pas` |

Style-guide enforcement for project-specific class bans (`TQuery`, `TLabel` if you have a `TStyledLabel`, ...). Detector stays silent unless the project sets `[Components] ForbiddenClasses=...` in `analyser.ini`.

---

## SCA039
**DB component on UI form**

> TFDQuery / TFDConnection directly on a TForm/TFrame instead of a DataModule

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dfm`, `architecture`, `data-access` |
| Detector | `uDfmDbInUiForm.pas` |

Database infrastructure on a UI form couples persistence to presentation - hard to reuse, hard to test. Move to a `TDataModule` and reference it from the form.

---

## SCA040
**Cross-form field access**

> Code in Form1 reads / writes Form2.<published_field> directly

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `dfm`, `architecture`, `coupling` |
| Detector | `uDfmCrossFormCoupling.pas` |

Reaching across forms to grab a child control breaks encapsulation - any rename in `Form2` silently breaks `Form1`. Expose a property or method on `Form2` instead.

```pascal
// BAD
Form2.EdName.Text := 'x';

// GOOD
Form2.UserName := 'x';   // property on Form2
```

---

## SCA041
**Input control directly on TForm**

> Input control sits on the form instead of being embedded in a TPanel / TGroupBox

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dfm`, `layout` |
| Detector | `uDfmLayerViolation.pas` |

Layered layout (Form > Panel > Group > Controls) makes resizing, DPI-scaling, and theming significantly easier. Wrap controls in a layout container.

---

## SCA042
**God event handler**

> Single method wired to >= N component events (default N=5)

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dfm`, `design` |
| Config | `[Detectors] DfmGodHandlerMaxEvents` |
| Detector | `uDfmGodHandler.pas` |

Spaghetti indicator: one handler dispatching dozens of events is hard to read, hard to change, and almost always has cohesion problems. Split by responsibility.

---

## SCA043
**Component has Action + OnClick**

> Action and OnClick both set - Action wins, OnClick is dead code

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `dfm`, `dead-code` |
| Detector | `uDfmActionMismatch.pas` |

When a `TAction` is assigned, VCL routes events through the action object and the `OnClick` never fires. Pick one or call the `OnClick` body from the action's `OnExecute`.

---

## SCA044
**Long string concat - prefer Format()**

> Multi-segment string concatenation - extract to a Format() call

| Field | Value |
|---|---|
| Severity | Warning | Type | Code Smell |
| Tags | `maintainability`, `string-formatting` |
| Detector | `uConcatToFormat.pas` |

```pascal
// BAD
Msg := 'User ' + Name + ' has ' + IntToStr(N) + ' open tickets';

// GOOD
Msg := Format('User %s has %d open tickets', [Name, N]);
```

---

## SCA045
**with X do ...**

> with statement - scope-shadowing trap the compiler does not warn about

| Field | Value |
|---|---|
| Severity | Warning | Type | Code Smell |
| Tags | `scope`, `delphi-classic` |
| Detector | `uWithStatement.pas` |

Marco Cantu, delphi.org and Stack Overflow consistently rank `with` among the top Delphi bug sources. Identifiers from the outer scope get silently shadowed by members of the with-target. Use a local variable alias instead.

```pascal
// BAD
with Customer do
begin
  Name := SomeName;   // Customer.Name? or outer Name?
end;

// GOOD
C := Customer;
C.Name := SomeName;
```

---

## SCA046
**for i := High to Low - missing downto**

> for i := 10 to 1 do - loop body never executes

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `loop`, `typo` |
| Detector | `uReversedForRange.pas` |

Classic typo: `to` instead of `downto` when iterating from high to low. The loop runs zero times. Detector flags constant `From > To`.

```pascal
// BAD
for i := 10 to 1 do DoStuff(i);

// GOOD
for i := 10 downto 1 do DoStuff(i);
```

---

## SCA047
**x := x**

> Self-assignment - no-op or copy-paste typo

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `typo`, `no-op` |
| Detector | `uSelfAssignment.pas` |

Detector excludes property setters with documented side effects. A bare `x := x` is almost always a typo where one side should be a different variable.

---

## SCA048
**Virtual call in constructor**

> Virtual method invoked from constructor - subclass override sees half-initialised Self

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `oop`, `initialization-order` |
| CWE | [CWE-665](https://cwe.mitre.org/data/definitions/665.html) |
| Detector | `uVirtualCallInCtor.pas` |

C++ FAQ 23.5 / *Effective Java* item 17 in Delphi form: virtual dispatch in a constructor runs the most-derived override before subclass fields are initialised. Defer to a non-virtual post-construction hook.

```pascal
// BAD
constructor TBase.Create;
begin
  Configure;   // virtual - subclass override sees uninitialised state
end;

// GOOD
procedure TBase.AfterConstruction;
begin
  Configure;
end;
```

---

## SCA049
**Length(s) - N without guard**

> Length / .Count with subtraction - native-uint underflow when empty

| Field | Value |
|---|---|
| Severity | Hint | Type | Bug |
| Tags | `arithmetic`, `underflow` |
| Detector | `uLengthUnderflow.pas` |

`Length(s) - 1` on an empty string evaluates to `0 - 1 = MaxUInt` under NativeUInt arithmetic and indexes into garbage. Guard for emptiness or cast to `NativeInt`.

---

## SCA050
**Public member could be private**

> Public/protected member referenced only inside its own unit

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `encapsulation`, `visibility` |
| Detector | `uVisibilityCheck.pas` |

Cross-unit reference analysis: no outside caller, so tightening to `private` has no external impact. Reduces public API surface.

---

## SCA051
**Public member could be protected**

> Public member referenced only from subclasses, never externally

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `encapsulation`, `visibility` |
| Detector | `uVisibilityCheck.pas` |

Cross-unit reference analysis: all external callers live in subclasses, so `protected` is sufficient and keeps the API narrower.

---

## SCA052
**Unused public member (dead API)**

> Public member is never referenced from any subclass or cross-unit path

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dead-code`, `api` |
| Detector | `uVisibilityCheck.pas` |

No internal use AND no external use found - dead API surface. Either remove or document as intentionally exported (e.g. for binary compatibility).

---

## SCA053
**Unused local variable**

> Local var declared but never referenced in method body

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dead-code`, `locals` |
| Detector | `uUnusedLocal.pas` |

Mirrors Delphi compiler hint `H2164` but emitted as an SCA finding so it can be filtered, suppressed, and tracked uniformly with the other rules.

---

## SCA054
**Unused method parameter**

> Method parameter is never used in the body

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dead-code`, `api-design` |
| Detector | `uUnusedParameter.pas` |

Detector skips overrides, event handlers (`Sender: TObject`) and interface implementations because those signatures are externally constrained.

---

## SCA055
**Tautological boolean expression**

> Binary operator with identical LHS and RHS: x = x, a and a, (p <> p)

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `typo`, `copy-paste` |
| Detector | `uTautologicalExpr.pas` |

Classic copy-paste bug. Either one side is wrong (the typical case - a typo) or the expression is genuinely tautological and should be removed.

```pascal
// BAD
if (a = a) then ...

// GOOD
if (a = b) then ...
```

---

## SCA056
**Master-Detail without MasterFields**

> TDataSet has MasterSource set but no MasterFields / IndexFieldNames

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `dfm`, `data-access`, `performance` |
| Detector | `uDfmMasterDetailUnlinked.pas` |

VCL silently performs a Cartesian product instead of the intended Master-Detail join - every parent row pulls every detail row at runtime. Fix by setting `MasterFields` (and `IndexFieldNames` for IB/FB).

---

## SCA057
**Form has many DB components - split DataModule**

> Aggregated hint: form holds >= N DB components

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dfm`, `architecture` |
| Config | `[Detectors] DfmDataModuleSplitMin` |
| Detector | `uDfmDataModuleSplitHint.pas` |

Aggregate of multiple [SCA039](#sca039) (`DfmDbInUiForm`) findings on the same form - emitted as a single refactor hint instead of N individual findings.

---

## SCA058
**UPDATE / DELETE / TRUNCATE without WHERE**

> SQL statement modifies every row - missing WHERE clause

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `sql`, `data-loss` |
| CWE | [CWE-89](https://cwe.mitre.org/data/definitions/89.html) |
| Detector | `uSqlDangerousStatement.pas` |

`UPDATE Users SET Active=0` without `WHERE` flips every row in the table. Same for `DELETE FROM ...` and `TRUNCATE TABLE ...`. Production-disaster waiting to happen.

```pascal
// BAD
Q.SQL.Text := 'UPDATE Users SET Active=0';

// GOOD
Q.SQL.Text := 'UPDATE Users SET Active=0 WHERE Id=:id';
```

---

## SCA059
**Format() float spec without TFormatSettings**

> %.2f / %.3f without explicit TFormatSettings - comma vs dot decimal trap

| Field | Value |
|---|---|
| Severity | Hint | Type | Bug |
| Tags | `string-formatting`, `i18n`, `locale` |
| Detector | `uFormatMismatch.pas` |

On a DE Windows `Format('%.2f', [3.14])` yields `'3,14'`; on EN-US it yields `'3.14'`. For machine-readable output (SQL, JSON, CSV) always pass `TFormatSettings.Invariant`.

```pascal
// BAD
S := Format('%.2f', [Price]);

// GOOD
S := Format('%.2f', [Price], TFormatSettings.Invariant);
```

---

_For richer per-rule pages with badges and full examples, install Python and run `python tools/gen-rules-docs.py`. Generated files land in `docs/rules/SCA001.md`...`SCA059.md`._

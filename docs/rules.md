# StaticCodeAnalyser — Rule Catalog

All 193 detector rules. Single source of truth: [`rules/sca-rules.json`](../rules/sca-rules.json).

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
| [SCA060](#sca060) | goto statement | Warning | Code Smell | `uGotoStatement.pas` |
| [SCA061](#sca061) | Tab character in source | Hint | Code Smell | `uTabulationCharacter.pas` |
| [SCA062](#sca062) | Source line too long | Hint | Code Smell | `uTooLongLine.pas` |
| [SCA063](#sca063) | Trailing whitespace | Hint | Code Smell | `uTrailingWhitespace.pas` |
| [SCA064](#sca064) | Pascal keyword not lowercase | Hint | Code Smell | `uLowercaseKeyword.pas` |
| [SCA065](#sca065) | NOSONAR suppression marker | Hint | Code Smell | `uNoSonarMarker.pas` |
| [SCA066](#sca066) | Empty argument list | Hint | Code Smell | `uEmptyArgumentList.pas` |
| [SCA067](#sca067) | Inline assembly block | Warning | Code Smell | `uInlineAssembly.pas` |
| [SCA068](#sca068) | Trailing comma in argument list | Hint | Code Smell | `uTrailingCommaArgList.pas` |
| [SCA069](#sca069) | Integer literal without digit grouping | Hint | Code Smell | `uDigitGrouping.pas` |
| [SCA070](#sca070) | Commented-out code | Hint | Code Smell | `uCommentedOutCode.pas` |
| [SCA071](#sca071) | Unit-level keyword not at column 1 | Hint | Code Smell | `uUnitLevelKeywordIndent.pas` |
| [SCA072](#sca072) | Redundant boolean comparison | Hint | Code Smell | `uRedundantBoolean.pas` |
| [SCA073](#sca073) | Empty interface declaration | Hint | Code Smell | `uEmptyInterface.pas` |
| [SCA074](#sca074) | Assert without message | Hint | Code Smell | `uAssertMessage.pas` |
| [SCA075](#sca075) | Explicit TObject inheritance | Hint | Code Smell | `uExplicitTObjectInheritance.pas` |
| [SCA076](#sca076) | Grouped variable / field / parameter declaration | Hint | Code Smell | `uGroupedDeclaration.pas` |
| [SCA077](#sca077) | Empty begin..end block | Hint | Code Smell | `uEmptyBlock.pas` |
| [SCA078](#sca078) | Catch-all on root Exception class | Warning | Bug | `uExceptOnException.pas` |
| [SCA079](#sca079) | Consecutive const/type/var section | Hint | Code Smell | `uConsecutiveSection.pas` |
| [SCA080](#sca080) | Redundant Exit/Continue/Break before end | Hint | Code Smell | `uRedundantJump.pas` |
| [SCA081](#sca081) | Multiple class declarations in one file | Hint | Code Smell | `uClassPerFile.pas` |
| [SCA082](#sca082) | Double semicolon | Hint | Code Smell | `uSuperfluousSemicolon.pas` |
| [SCA083](#sca083) | Empty finally block | Warning | Bug | `uEmptyFinallyBlock.pas` |
| [SCA084](#sca084) | Redundant Assigned + nil check | Hint | Code Smell | `uAssignedAndAssignedNil.pas` |
| [SCA085](#sca085) | X.Free; X := nil; should be FreeAndNil(X) | Hint | Code Smell | `uFreeAndNilHint.pas` |
| [SCA086](#sca086) | Avoid out parameter modifier | Hint | Code Smell | `uAvoidOut.pas` |
| [SCA087](#sca087) | Empty visibility section in class | Hint | Code Smell | `uEmptyVisibilitySection.pas` |
| [SCA088](#sca088) | Legacy unit-init begin..end. | Hint | Code Smell | `uLegacyInitializationSection.pas` |
| [SCA089](#sca089) | Public field in class | Hint | Code Smell | `uPublicField.pas` |
| [SCA090](#sca090) | Nested try block | Hint | Code Smell | `uNestedTry.pas` |
| [SCA091](#sca091) | Large case statement | Hint | Code Smell | `uCaseStatementSize.pas` |
| [SCA092](#sca092) | Unit contains no declarations | Hint | Code Smell | `uEmptyFile.pas` |
| [SCA093](#sca093) | Multiple inherited calls in one method | Warning | Bug | `uTwiceInheritedCalls.pas` |
| [SCA094](#sca094) | Redundant double parentheses | Hint | Code Smell | `uRedundantParentheses.pas` |
| [SCA095](#sca095) | Consecutive visibility section | Hint | Code Smell | `uConsecutiveVisibility.pas` |
| [SCA096](#sca096) | Constructor without inherited call | Warning | Bug | `uConstructorWithoutInherited.pas` |
| [SCA097](#sca097) | Destructor without inherited call | **Error** | Bug | `uDestructorWithoutInherited.pas` |
| [SCA098](#sca098) | Redundant conditional assignment | Hint | Code Smell | `uRedundantConditional.pas` |
| [SCA099](#sca099) | Asymmetric begin/end in if/else | Hint | Code Smell | `uIfElseBegin.pas` |
| [SCA100](#sca100) | Pointer type alias not prefixed with P | Hint | Code Smell | `uPointerName.pas` |
| [SCA101](#sca101) | Branch without begin..end block | Hint | Code Smell | `uBeginEndRequired.pas` |
| [SCA102](#sca102) | Nested routine inside another method | Hint | Code Smell | `uNestedRoutines.pas` |
| [SCA103](#sca103) | Class field not prefixed with F | Hint | Code Smell | `uFieldName.pas` |
| [SCA104](#sca104) | Class/record type not prefixed with T | Hint | Code Smell | `uTypeName.pas` |
| [SCA105](#sca105) | Interface type not prefixed with I | Hint | Code Smell | `uInterfaceName.pas` |
| [SCA106](#sca106) | Method not in PascalCase | Hint | Code Smell | `uMethodName.pas` |
| [SCA107](#sca107) | Public member could be strict private | Hint | Code Smell | `uVisibilityCheck.pas` |
| [SCA108](#sca108) | TThread.Synchronize from destructor | **Error** | Bug | `uSynchronizeInDestructor.pas` |
| [SCA109](#sca109) | Lock acquired without try/finally release | **Error** | Bug | `uLockWithoutTryFinally.pas` |
| [SCA110](#sca110) | String concatenation in loop | Warning | Code Smell | `uPerfHotspots.pas` |
| [SCA111](#sca111) | ParamByName(...) called in loop | Hint | Code Smell | `uPerfHotspots.pas` |
| [SCA112](#sca112) | FieldByName(...) called in loop | Hint | Code Smell | `uPerfHotspots.pas` |
| [SCA113](#sca113) | TThread.Resume is deprecated | Warning | Code Smell | `uConcurrencyExt.pas` |
| [SCA114](#sca114) | TThread destroyed without Terminate+WaitFor | **Error** | Bug | `uConcurrencyExt.pas` |
| [SCA115](#sca115) | Plaintext HTTP URL | Warning | Security Hotspot | `uRestHttpSecurity.pas` |
| [SCA116](#sca116) | TLS verification disabled | **Error** | Vulnerability | `uRestHttpSecurity.pas` |
| [SCA117](#sca117) | Public member missing doc comment | Hint | Code Smell | `uPublicMemberWithoutDoc.pas` |
| [SCA118](#sca118) | Exception class without `E` prefix | Hint | Code Smell | `uNamingExt.pas` |
| [SCA119](#sca119) | Local constant not in UPPER_SNAKE_CASE | Hint | Code Smell | `uNamingExt.pas` |
| [SCA120](#sca120) | Exception constructed but never raised | **Error** | Bug | `uMissingRaise.pas` |
| [SCA121](#sca121) | Function never assigns Result | **Error** | Bug | `uRoutineResultAssigned.pas` |
| [SCA122](#sca122) | Re-raise of bound exception variable | Warning | Bug | `uReRaiseException.pas` |
| [SCA123](#sca123) | Type-cast immediately before Free / Destroy | Hint | Code Smell | `uCastAndFree.pas` |
| [SCA124](#sca124) | Constructor invoked on instance instead of class | **Error** | Bug | `uInstanceInvokedConstructor.pas` |
| [SCA125](#sca125) | Override whose entire body is `inherited;` | Hint | Code Smell | `uInheritedMethodEmpty.pas` |
| [SCA126](#sca126) | Use Assigned() instead of `= nil` / `<> nil` | Hint | Code Smell | `uNilComparison.pas` |
| [SCA127](#sca127) | Raise the bare `Exception` base class instead of a specific subclass | Warning | Code Smell | `uRaisingRawException.pas` |
| [SCA128](#sca128) | Locale-dependent format call without explicit TFormatSettings | Warning | Bug | `uDateFormatSettings.pas` |
| [SCA129](#sca129) | Cast from string to 8-bit string type without explicit encoding | Warning | Bug | `uUnicodeToAnsiCast.pas` |
| [SCA130](#sca130) | Cast of Char value to PChar reinterprets codepoint as pointer | **Error** | Bug | `uCharToCharPointerCast.pas` |
| [SCA131](#sca131) | IfThen() evaluates both branches - no short-circuit | Warning | Bug | `uIfThenShortCircuit.pas` |
| [SCA132](#sca132) | except on E: Exception catches every error | Warning | Code Smell | `uExceptionTooGeneral.pas` |
| [SCA133](#sca133) | Bare raise outside an except/on handler | **Error** | Bug | `uRaiseOutsideExcept.pas` |
| [SCA134](#sca134) | Variable used after Free / FreeAndNil | **Error** | Bug | `uUseAfterFree.pas` |
| [SCA135](#sca135) | Concrete subclass inherits an abstract method without override | **Error** | Bug | `uAbstractNotImpl.pas` |
| [SCA136](#sca136) | Constructor allocates fields and raises without try/except | **Error** | Bug | `uLeakInConstructor.pas` |
| [SCA137](#sca137) | Int64 target receives product of two 32-bit operands | **Error** | Bug | `uIntegerOverflow.pas` |
| [SCA138](#sca138) | Class has too many methods or fields | Warning | Code Smell | `uGodClass.pas` |
| [SCA139](#sca139) | Free without subsequent nil-out | Warning | Code Smell | `uFreeWithoutNil.pas` |
| [SCA140](#sca140) | Method has too many Exit statements | Warning | Code Smell | `uMultipleExit.pas` |
| [SCA141](#sca141) | Class implementation exceeds 500 lines | Warning | Code Smell | `uLargeClass.pas` |
| [SCA142](#sca142) | uses clause is not in alphabetical order | Hint | Code Smell | `uUnsortedUses.pas` |
| [SCA143](#sca143) | Unit has no descriptive header comment | Hint | Code Smell | `uMissingUnitHeader.pas` |
| [SCA144](#sca144) | Float equality / inequality comparison | Warning | Bug | `uFloatEquality.pas` |
| [SCA145](#sca145) | Raise inside destructor without try/except | Warning | Bug | `uExceptInDestructor.pas` |
| [SCA146](#sca146) | Boolean parameter used as internal branching flag | Hint | Code Smell | `uBooleanParam.pas` |
| [SCA147](#sca147) | Private method has no caller in the unit | Hint | Code Smell | `uUnusedPrivateMethod.pas` |
| [SCA148](#sca148) | Instance method never accesses Self - could be a class method | Hint | Code Smell | `uCanBeClassMethod.pas` |
| [SCA149](#sca149) | Method shadows a virtual parent method without `override` | Warning | Bug | `uMissingOverride.pas` |
| [SCA150](#sca150) | Boolean comparison is always true / always false | Warning | Bug | `uBoolAlwaysTrue.pas` |
| [SCA151](#sca151) | Function always returns the same literal | Hint | Code Smell | `uConstantReturn.pas` |
| [SCA152](#sca152) | User-visible string assigned as literal | Hint | Code Smell | `uHardcodedString.pas` |
| [SCA153](#sca153) | Lock acquired without try/finally release | Warning | Bug | `uUnpairedLock.pas` |
| [SCA154](#sca154) | Move/FillChar with SizeOf(pointer-type) | Warning | Bug | `uMoveSizeOfPointer.pas` |
| [SCA155](#sca155) | with statement on multiple targets | Hint | Code Smell | `uWithMultipleTargets.pas` |
| [SCA156](#sca156) | GetMem / AllocMem without try/finally | Warning | Bug | `uGetMemWithoutFreeMem.pas` |
| [SCA157](#sca157) | SetLength(arr, Length(arr) + N) inside a loop | Warning | Code Smell | `uSetLengthAppendInLoop.pas` |
| [SCA158](#sca158) | PChar(s) +/- offset without empty-check | Warning | Bug | `uPointerArithmeticOnString.pas` |
| [SCA159](#sca159) | Typed exception handler with empty body | Warning | Bug | `uEmptyOnHandler.pas` |
| [SCA160](#sca160) | String cast from raw pointer | Warning | Bug | `uStringFromPointer.pas` |
| [SCA161](#sca161) | Pointer subtraction via 32-bit cast | Warning | Bug | `uPointerSubtraction.pas` |
| [SCA162](#sca162) | Use of weak / deprecated cryptographic algorithm | Warning | Vulnerability | `uInsecureCryptoAlgorithm.pas` |
| [SCA163](#sca163) | Shell API called with string concatenation in argument | **Error** | Vulnerability | `uCommandInjection.pas` |
| [SCA164](#sca164) | Top-level routine never called | Hint | Code Smell | `uUnusedRoutine.pas` |
| [SCA165](#sca165) | Unused noinspection marker | Hint | Code Smell | `uSuppression.pas` |
| [SCA166](#sca166) | Uninitialised local variable | **Error** | Bug | `uUninitVar.pas` |
| [SCA167](#sca167) | Random call without prior Randomize | Warning | Bug | `uInsecureRandom.pas` |
| [SCA168](#sca168) | case statement without else branch | Hint | CodeSmell | `uDefaultCaseInCaseStatement.pas` |
| [SCA169](#sca169) | Assert argument contains a function call with side effects | Warning | Bug | `uAssertWithSideEffect.pas` |
| [SCA170](#sca170) | string parameter without const modifier | Hint | CodeSmell | `uConstStringParameter.pas` |
| [SCA171](#sca171) | Compiler switch OFF without matching ON in same file | Warning | CodeSmell | `uCompilerDirectiveScope.pas` |
| [SCA172](#sca172) | Boolean property without Is / Has / Can / Should prefix | Hint | CodeSmell | `uBooleanPropertyNaming.pas` |
| [SCA173](#sca173) | Variant in performance-sensitive method (contains a loop) | Hint | CodeSmell | `uVariantTypeMisuse.pas` |
| [SCA174](#sca174) | TList<T> filled with T.Create - items leak when list is freed | Warning | Bug | `uTObjectListWithoutOwnership.pas` |
| [SCA175](#sca175) | Anonymous method captures for-loop variable by reference | **Error** | Bug | `uAnonMethodCaptureLoopVar.pas` |
| [SCA176](#sca176) | Method has high cognitive complexity (nested control flow) | Warning | CodeSmell | `uCognitiveComplexity.pas` |
| [SCA177](#sca177) | Thread variable accessed after FreeOnTerminate := True | **Error** | Bug | `uThreadFreeOnTerminateWithRef.pas` |
| [SCA178](#sca178) | File-open API receives concatenated user input | **Error** | Vulnerability | `uPathTraversal.pas` |
| [SCA179](#sca179) | DUnitX [Ignore] attribute without reason argument | Hint | CodeSmell | `uAttributeIgnoreWithoutReason.pas` |
| [SCA180](#sca180) | Same attribute applied twice to one member | Warning | CodeSmell | `uAttributeDuplicate.pas` |
| [SCA181](#sca181) | DUnitX [Category] without category-name string | **Error** | Bug | `uAttributeCategoryWithoutString.pas` |
| [SCA182](#sca182) | [TestFixture] class without any [Test] method | Warning | CodeSmell | `uAttributeTestFixtureWithoutTests.pas` |
| [SCA183](#sca183) | Attribute with blank line before target member | Hint | CodeSmell | `uAttributeMisalignment.pas` |
| [SCA184](#sca184) | Unused DFM component | Hint | Code Smell | `uDfmComponentUnused.pas` |
| [SCA185](#sca185) | UTF-8 source file without BOM | Warning | Bug | `uSourceEncoding.pas` |
| [SCA186](#sca186) | Invalid UTF-8 sequence in source file | **Error** | File Error | `uSourceEncoding.pas` |
| [SCA187](#sca187) | NUL or control byte in source file | **Error** | File Error | `uSourceEncoding.pas` |
| [SCA188](#sca188) | Bidirectional override control character (Trojan Source) | **Error** | Vulnerability | `uSourceEncoding.pas` |
| [SCA189](#sca189) | ANSI source file with non-ASCII content | Warning | Code Smell | `uSourceEncoding.pas` |
| [SCA190](#sca190) | UTF-16 source file | Hint | Code Smell | `uSourceEncoding.pas` |
| [SCA191](#sca191) | UTF-32 / UCS-4 source file | **Error** | File Error | `uSourceEncoding.pas` |
| [SCA192](#sca192) | Invisible / zero-width character in source | Warning | Vulnerability | `uSourceEncoding.pas` |
| [SCA193](#sca193) | Non-ASCII character in identifier | Warning | Vulnerability | `uSourceEncoding.pas` |
| [SCA194](#sca194) | Source file not part of the project | Hint | Code Smell | `uNotIncludedInProject.pas` |

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

A bare `x := x` is almost always a typo where one side should be a different variable. The detector does not special-case property setters; the rare legitimate cases (a setter with side effects, or `Result := Result;` to silence a compiler hint) must be suppressed with a `// noinspection` comment directly above the line.

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

## SCA060
**goto statement**

> `goto` weakens structured control flow

| Field | Value |
|---|---|
| Severity | Warning | Type | Code Smell |
| Tags | `control-flow`, `delphi-classic` |
| Detector | `uGotoStatement.pas` |

`goto` and labels make the control flow non-structural: loops, nesting and try/finally become hard to follow. SonarDelphi tracks the same as communitydelphi:GotoStatement. Modern Delphi code rarely justifies goto - even multi-level break is cleaner as an extracted procedure with Exit.

```pascal
// BAD
label MyExit;
begin
  if Failed then goto MyExit;
  ...
  MyExit:
end;

// GOOD
if Failed then Exit;
...
```

---
## SCA061
**Tab character in source**

> Tab characters render inconsistently across editors - use spaces

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `formatting`, `style` |
| Detector | `uTabulationCharacter.pas` |

Pascal coding convention has been space-indentation since the 80s. Tabs render at 2/4/8 columns depending on the editor, break code-review side-by-side diffs and confuse alignment. SonarDelphi tracks the same as communitydelphi:TabulationCharacter.

```pascal
// BAD
procedure Foo;
begin
<TAB>DoStuff;
end;

// GOOD
procedure Foo;
begin
  DoStuff;
end;
```

---
## SCA062
**Source line too long**

> Line exceeds 120 characters - wrap or extract subexpression

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `formatting`, `style` |
| Detector | `uTooLongLine.pas` |

Lines over 120 chars don't fit in a standard side-by-side code review (2*120+gutter) and overflow 16:9 monitor thirds. SonarDelphi default and Sun/Java style guides agree on 120. Threshold currently hardcoded; planned config key '[Detectors] MaxLineLength'.

```pascal
// BAD
result := SomeReallyLongFunction(ArgumentOne, ArgumentTwo, ArgumentThree, ArgumentFour, ArgumentFive);

// GOOD
result := SomeReallyLongFunction(
  ArgumentOne, ArgumentTwo,
  ArgumentThree, ArgumentFour, ArgumentFive);
```

---
## SCA063
**Trailing whitespace**

> Line ends with space or tab - hygiene for diffs

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `formatting`, `style` |
| Detector | `uTrailingWhitespace.pas` |

Trailing space/tab at end of line creates phantom diff lines whenever an editor with 'trim trailing whitespace on save' touches the file. SonarDelphi tracks the same as communitydelphi:TrailingWhitespace.

```pascal
// BAD
  DoStuff;   <-- trailing spaces

// GOOD
  DoStuff;
```

---
## SCA064
**Pascal keyword not lowercase**

> Pascal keywords (`begin`/`end`/`procedure`/...) should be lowercase

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `formatting`, `style`, `convention` |
| Detector | `uLowercaseKeyword.pas` |

Object-Pascal style guide (Embarcadero DocWiki, Marco Cantu, SonarDelphi) is unambiguous: keywords are lowercase. Mixed-case variants like `Begin`/`End`/`Procedure` are leftovers from Turbo-Pascal/Delphi-1 era and create inconsistency in modern codebases. SonarDelphi tracks the same as communitydelphi:LowercaseKeyword.

```pascal
// BAD
Procedure Foo;
Begin
  If X then DoStuff;
End;

// GOOD
procedure Foo;
begin
  if X then DoStuff;
end;
```

---
## SCA065
**NOSONAR suppression marker**

> `// NOSONAR` marker should not silence findings - audit usage

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `suppression`, `audit` |
| Detector | `uNoSonarMarker.pas` |

NOSONAR markers are technical debt: each one silences a finding without fixing the underlying issue. SCA reports every NOSONAR so reviewers can audit suppressions during code review. SCA uses its own `// noinspection` marker for native suppression - NOSONAR-decorated code coming from SonarDelphi should be migrated. Matches SonarDelphi communitydelphi:NoSonar.

```pascal
// BAD
Dispose(P); // NOSONAR - we know about this

// GOOD
// noinspection - covered by integration test
Dispose(P);
```

---
## SCA066
**Empty argument list**

> `Foo()` should be `Foo;` - drop empty parens

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `style`, `convention` |
| Detector | `uEmptyArgumentList.pas` |

Delphi convention is to write parameterless calls without `()`. The C-style `Foo()` form adds noise without communicating anything and is inconsistent with the rest of the language (procedures, properties, function refs all omit parens when no args). Matches SonarDelphi communitydelphi:EmptyArgumentList.

```pascal
// BAD
MyProc();
Result := MyFunc();

// GOOD
MyProc;
Result := MyFunc;
```

---
## SCA067
**Inline assembly block**

> `asm...end` block - prefer Pascal + compiler intrinsics

| Field | Value |
|---|---|
| Severity | Warning | Type | Code Smell |
| Tags | `portability`, `maintainability` |
| Detector | `uInlineAssembly.pas` |

Inline assembly creates platform lock-in (x86/x64-only bytes that don't survive ARM cross-compile or FreePascal targets), bypasses the Delphi optimizer (no inlining or reorg), and is hard to debug. The valid use cases (CPUID detection, MMX/SSE intrinsics) are covered by RTL helpers. Matches SonarDelphi communitydelphi:InlineAssembly.

```pascal
// BAD
function Cpuid: Cardinal;
asm
  XOR EAX, EAX
  CPUID
end;

// GOOD
function Cpuid: Cardinal;
begin
  Result := GetCpuFeatures;
end;
```

---
## SCA068
**Trailing comma in argument list**

> `Foo(A, B,)` - drop the comma or add the missing argument

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `style`, `bug-risk` |
| Detector | `uTrailingCommaArgList.pas` |

Trailing comma before `)` in Delphi has no semantic benefit (unlike Python/JS where it stabilizes the diff) and suggests a forgotten argument. Matches SonarDelphi communitydelphi:TrailingCommaArgumentList.

```pascal
// BAD
WriteLn('A', 'B', );
DoStuff(Param1, Param2,);

// GOOD
WriteLn('A', 'B');
DoStuff(Param1, Param2);
```

---
## SCA069
**Integer literal without digit grouping**

> Large integer literals should use `_` separator

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `readability`, `modern-delphi` |
| Detector | `uDigitGrouping.pas` |

Delphi 10.4+ supports `_` as a digit separator in numeric literals. Constants like timeouts (1_800_000 ms = 30 min), file sizes (1_048_576 = 1 MiB), money cents and the like are dramatically more readable with explicit grouping. Threshold is 5 digits (hardcoded; `[Detectors] DigitGroupingThreshold` is planned). Hex and float literals are exempted (different convention). Matches SonarDelphi communitydelphi:DigitGrouping.

```pascal
// BAD
const TIMEOUT_MS = 1800000;
const MAX_BYTES = 10485760;

// GOOD
const TIMEOUT_MS = 1_800_000;
const MAX_BYTES = 10_485_760;
```

---
## SCA070
**Commented-out code**

> Comment looks like Pascal code - delete or document

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `maintenance`, `dead-code` |
| Detector | `uCommentedOutCode.pas` |

Heuristic: comment content with 2+ code-style markers (trailing `;`, `:=`, keywords `begin`/`end`/`procedure`/`function`/`if`/`then`/`for`/`while`) is almost certainly commented-out code. Such code rots silently: nobody dares delete it, nobody updates it. Either remove it, or replace with a TODO that explains the intent. Matches SonarDelphi communitydelphi:CommentedOutCode.

```pascal
// BAD
// X := 42;
// if Active then Process;

// GOOD
// TODO: re-enable once issue #123 is fixed - see history
```

---
## SCA071
**Unit-level keyword not at column 1**

> `unit`/`interface`/`implementation`/`initialization`/`finalization` should start at column 1

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `style`, `structure` |
| Detector | `uUnitLevelKeywordIndent.pas` |

Object Pascal convention is that the structural section keywords of a unit are flush-left at column 1. Indented section keywords obscure the unit's structure when scanning and may hint at miscounted begin/end nesting. Matches SonarDelphi communitydelphi:UnitLevelKeywordIndentation.

```pascal
// BAD
  implementation

  procedure Foo; ...

// GOOD
implementation

procedure Foo; ...
```

---
## SCA072
**Redundant boolean comparison**

> `X = True` should be `X` (and `X <> False` likewise)

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `style`, `bug-risk` |
| Detector | `uRedundantBoolean.pas` |

Comparing a Boolean to True/False is verbose and creates subtle bugs (WinAPI BOOL where Truthy != 1 evaluates `X = True` to false). The expression itself already is the condition. Matches SonarDelphi communitydelphi:RedundantBoolean. Note: `const X = True;` declarations are excluded (legitimate assignment, not comparison).

```pascal
// BAD
if Active = True then ...
if Disabled <> False then ...

// GOOD
if Active then ...
if Disabled then ...
```

---
## SCA073
**Empty interface declaration**

> Interface with no methods/properties carries no contract

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `api-design`, `dead-code` |
| Detector | `uEmptyInterface.pas` |

An `IFoo = interface end;` body without any methods or properties is either a refactor leftover or a marker interface in disguise. Marker interfaces are better modeled as attribute classes in Delphi. Matches SonarDelphi communitydelphi:EmptyInterface.

```pascal
// BAD
type IServiceMarker = interface end;

// GOOD
type ServiceMarkerAttribute = class(TCustomAttribute) end;
```

---
## SCA074
**Assert without message**

> `Assert(cond);` - add a `'why'` message for diagnosis

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `debuggability`, `errors` |
| Detector | `uAssertMessage.pas` |

`Assert(cond)` alone fails with the generic 'Assertion failed at $address' - no clue what was actually expected. `Assert(cond, 'why')` saves debugging hours. Matches SonarDelphi communitydelphi:AssertMessage.

```pascal
// BAD
Assert(Items.Count > 0);

// GOOD
Assert(Items.Count > 0, 'caller must ensure non-empty Items');
```

---
## SCA075
**Explicit TObject inheritance**

> `class(TObject)` is redundant - drop the parens

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `style`, `redundancy` |
| Detector | `uExplicitTObjectInheritance.pas` |

Every class implicitly inherits from TObject; `TFoo = class(TObject)` is identical to `TFoo = class`. Removing the explicit base highlights real inheritance changes in diffs. Matches SonarDelphi communitydelphi:ExplicitTObjectInheritance.

```pascal
// BAD
type TFoo = class(TObject) ... end;

// GOOD
type TFoo = class ... end;
```

---
## SCA076
**Grouped variable / field / parameter declaration**

> Split `A, B: Type` into one declaration per line

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `style`, `diff-hygiene` |
| Detector | `uGroupedDeclaration.pas` |

Grouped declarations (`A, B, C: Integer;` for vars, fields or parameters) confuse diffs (a new variable changes an existing line), prevent per-variable comments, and complicate type-change refactors. Each declaration on its own line is cleaner. Unifies SonarDelphi communitydelphi:GroupedFieldDeclaration / :GroupedVariableDeclaration / :GroupedParameterDeclaration into one rule (SCA may split later).

```pascal
// BAD
var A, B, C: Integer;
field FX, FY: TPoint;

// GOOD
var A: Integer;
    B: Integer;
    C: Integer;
```

---
## SCA077
**Empty begin..end block**

> Empty `begin..end` - delete it or fill in the statement

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dead-code`, `refactor` |
| Detector | `uEmptyBlock.pas` |

An empty `begin..end` is almost always a refactor leftover or never-filled-in placeholder. Either delete it or implement the missing logic. Top-level unit `begin end.` initialization sections are exempted (that is the empty init form, not a refactor rest). Matches SonarDelphi communitydelphi:EmptyBlock.

```pascal
// BAD
if Active then begin end;

// GOOD
if Active then Activate;
```

---
## SCA078
**Catch-all on root Exception class**

> `on E: Exception do` swallows everything including AV/OOM

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `error-handling`, `bug-risk` |
| Detector | `uExceptOnException.pas` |

Catching the root `Exception` class catches every error including unrecoverable ones (EAccessViolation, EOutOfMemory, EStackOverflow). Prefer a specific exception type (EDatabaseError, EFOpenError, EConvertError, ...) so unrelated failures aren't masked. Suppress with `// noinspection` if the catch-all is intentional (e.g. logger boundary).

```pascal
// BAD
try Foo; except on E: Exception do Log(E.Message); end;

// GOOD
try Foo; except on E: EDatabaseError do Log(E.Message); end;
```

---
## SCA079
**Consecutive const/type/var section**

> Two `const`/`type`/`var` blocks in a row should be merged

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `style`, `structure` |
| Detector | `uConsecutiveSection.pas` |

`const A = 1; const B = 2;` should be `const A = 1; B = 2;` - one section keyword can declare all of them. Same for `type` and `var`. Unifies SonarDelphi communitydelphi:ConsecutiveConstSection / :ConsecutiveTypeSection / :ConsecutiveVarSection into one rule. The section type is in the message.

```pascal
// BAD
const A = 1;
const B = 2;

// GOOD
const
  A = 1;
  B = 2;
```

---
## SCA080
**Redundant Exit/Continue/Break before end**

> `Exit;` / `Continue;` / `Break;` directly before `end` is a no-op

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dead-code`, `control-flow` |
| Detector | `uRedundantJump.pas` |

If `Exit` is the last statement of a procedure (or `Continue`/`Break` the last in a loop body), control flow already leaves the block - the jump statement is dead. Delete it to clarify intent. Matches SonarDelphi communitydelphi:RedundantJump.

```pascal
// BAD
procedure Foo;
begin
  DoStuff;
  Exit;
end;

// GOOD
procedure Foo;
begin
  DoStuff;
end;
```

---
## SCA081
**Multiple class declarations in one file**

> One class per unit makes refactoring easier

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `organization`, `module-boundary` |
| Detector | `uClassPerFile.pas` |

When a unit declares two or more public classes, finding and moving them between units is harder than necessary. SonarDelphi communitydelphi:ClassPerFile suggests the same. Forward declarations (`TFoo = class;`) and class-reference types (`TFooClass = class of TFoo`) are exempted.

```pascal
// BAD
type
  TFoo = class ... end;
  TBar = class ... end;

// GOOD
// uFoo.pas
type TFoo = class ... end;
// uBar.pas
type TBar = class ... end;
```

---
## SCA082
**Double semicolon**

> `;;` - drop the extra semicolon

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `typo`, `style` |
| Detector | `uSuperfluousSemicolon.pas` |

A double semicolon (`;;`) usually means a forgotten typo or a stray paste leftover. Compilers treat the second `;` as an empty statement, so it doesn't break, but it adds noise. Matches SonarDelphi communitydelphi:SuperfluousSemicolon.

```pascal
// BAD
DoStuff;;

// GOOD
DoStuff;
```

---
## SCA083
**Empty finally block**

> `try ... finally end;` has no cleanup - either add it or drop the finally

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `resource-leak`, `refactor` |
| Detector | `uEmptyFinallyBlock.pas` |

An empty `finally` block is almost always a forgotten cleanup. If there really is nothing to clean up, drop the `try..finally` wrapper. Matches SonarDelphi communitydelphi:EmptyFinallyBlock.

```pascal
// BAD
Stream := TFileStream.Create(P);
try
  ...
finally
end;

// GOOD
Stream := TFileStream.Create(P);
try
  ...
finally
  Stream.Free;
end;
```

---
## SCA084
**Redundant Assigned + nil check**

> `Assigned(X) and (X <> nil)` - drop the nil check

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `redundancy`, `style` |
| Detector | `uAssignedAndAssignedNil.pas` |

`Assigned(X)` for pointers and class instances is semantically identical to `X <> nil`. Combining both is redundant - the second check can never give a different result. Matches SonarDelphi communitydelphi:AssignedAndAssignedNil.

```pascal
// BAD
if Assigned(Obj) and (Obj <> nil) then ...

// GOOD
if Assigned(Obj) then ...
```

---
## SCA085
**X.Free; X := nil; should be FreeAndNil(X)**

> Use `FreeAndNil(X)` instead of `X.Free; X := nil;`

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `idiom`, `safety` |
| Detector | `uFreeAndNilHint.pas` |

`FreeAndNil(X)` is the canonical Delphi idiom: it does both atomically and avoids a dangling pointer if `X.Free` raises (e.g. destructor failure). Manual two-line form is also more diff-noisy and easier to break apart during later refactors. Matches SonarDelphi communitydelphi:FreeAndNil.

```pascal
// BAD
Obj.Free;
Obj := nil;

// GOOD
FreeAndNil(Obj);
```

---
## SCA086
**Avoid out parameter modifier**

> Prefer `var` over `out` (out has surprising semantics)

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `api-design`, `bug-risk` |
| Detector | `uAvoidOut.pas` |

`out` parameters clear managed types (string/Interface/dynamic arrays) on method entry - the caller's value is discarded before the method runs. Record/simple types stay uninitialized, so reading the incoming value is UB. Both are rarely what was intended. `var` is the safer default unless you need the COM-interop semantics. Matches SonarDelphi communitydelphi:AvoidOut.

```pascal
// BAD
procedure Foo(out S: string);

// GOOD
procedure Foo(var S: string);
```

---
## SCA087
**Empty visibility section in class**

> `public`/`private`/... section header with no members

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dead-code`, `refactor` |
| Detector | `uEmptyVisibilitySection.pas` |

A class with a visibility keyword followed immediately by another visibility keyword (or `end`) is usually a refactor leftover - all members of that section moved elsewhere. Delete the empty header. Matches SonarDelphi communitydelphi:EmptyVisibilitySection.

```pascal
// BAD
type TFoo = class
  public
  private
    FX: Integer;
  end;

// GOOD
type TFoo = class
  private
    FX: Integer;
  end;
```

---
## SCA088
**Legacy unit-init begin..end.**

> Use `initialization..end.` instead of legacy `begin..end.`

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `legacy`, `modernization` |
| Detector | `uLegacyInitializationSection.pas` |

Pre-Delphi-2 units marked their init block with `begin..end.`. Since Delphi 2 the idiomatic form is `initialization..end.` which can be paired with an optional `finalization` block for symmetric cleanup. Matches SonarDelphi communitydelphi:LegacyInitializationSection.

```pascal
// BAD
// at end of unit:
begin
  RegisterClass(TFoo);
end.

// GOOD
initialization
  RegisterClass(TFoo);
end.
```

---
## SCA089
**Public field in class**

> Public field breaks encapsulation - use a property

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `encapsulation`, `api-design` |
| Detector | `uPublicField.pas` |

A public field exposes the underlying storage; callers can mutate it without the class noticing. A property gives the class the option to add validation/normalization later without breaking callers. Matches SonarDelphi communitydelphi:PublicField.

```pascal
// BAD
type TFoo = class
  public
    Count: Integer;
  end;

// GOOD
type TFoo = class
  private
    FCount: Integer;
  public
    property Count: Integer read FCount write FCount;
  end;
```

---
## SCA090
**Nested try block**

> Nested `try..end` - consider extracting inner try into a method

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `error-handling`, `complexity` |
| Detector | `uNestedTry.pas` |

Nesting try blocks makes the control flow of cleanup / error recovery harder to read. Most cases unwind by either re-ordering the cleanups or extracting the inner block into its own method. Matches SonarDelphi communitydelphi:NestedTry. The detector uses a depth heuristic (counting `try` vs `end` keywords) and may produce a few false positives in heavily nested begin/end code.

```pascal
// BAD
try
  try
    DoStuff;
  finally
    Cleanup;
  end;
except
  Log;
end;

// GOOD
ProtectedDoStuff;  // helper wraps the inner try
```

---
## SCA091
**Large case statement**

> `case` with >= 10 branches - consider polymorphism / dispatch table

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `complexity`, `open-closed` |
| Detector | `uCaseStatementSize.pas` |

A `case` with many branches usually hides a polymorphism or strategy pattern. The code would be more open/closed (new behavior = new class, not new branch) and the file shorter when each branch becomes its own class method or a `TDictionary<Key, TProc>` entry. Matches SonarDelphi communitydelphi:CaseStatementSize. Threshold currently hardcoded; `[Detectors] MaxCaseBranches` is planned.

```pascal
// BAD
case Op of
  opA: ...; opB: ...; opC: ...; opD: ...; opE: ...;
  opF: ...; opG: ...; opH: ...; opI: ...; opJ: ...;
end;

// GOOD
FOperations[Op].Execute;  // dispatch table
```

---
## SCA092
**Unit contains no declarations**

> Unit has no type/const/var/procedure/function - delete or fill in

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dead-code`, `cleanup` |
| Detector | `uEmptyFile.pas` |

A `.pas` file with a unit header but no declarations is dead weight. Either delete the file or fill in the placeholder. Matches SonarDelphi communitydelphi:EmptyFile.

```pascal
// BAD
unit X;
interface
implementation
end.

// GOOD
// delete the file
```

---
## SCA093
**Multiple inherited calls in one method**

> Two or more `inherited;` in the same method - parent side-effects run twice

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `inheritance`, `bug-risk` |
| Detector | `uTwiceInheritedCalls.pas` |

Each `inherited` invocation runs the parent implementation. Two calls fire side-effects (event notifications, refcount updates, log lines) twice. Almost always a copy-paste bug. Matches SonarDelphi communitydelphi:TwiceInheritedCalls.

```pascal
// BAD
procedure Foo;
begin
  inherited;
  DoStuff;
  inherited;
end;

// GOOD
procedure Foo;
begin
  inherited;
  DoStuff;
end;
```

---
## SCA094
**Redundant double parentheses**

> `((Ident))` - drop the outer parens

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `style`, `redundancy` |
| Detector | `uRedundantParentheses.pas` |

Double parentheses around a single identifier, literal or simple expression add nothing - a single pair is sufficient (often none). Matches SonarDelphi communitydelphi:RedundantParentheses. Only the simple-expression case is flagged; complex `((A + B))` may still benefit from inner parens for precedence and is not reported.

```pascal
// BAD
if ((Active)) then ...
Result := ((42));

// GOOD
if Active then ...
Result := 42;
```

---
## SCA095
**Consecutive visibility section**

> Same `public`/`private`/etc. section appears twice in one class

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `structure`, `style` |
| Detector | `uConsecutiveVisibility.pas` |

Two `private` (or `public`/`protected`/`published`) sections in the same class with members between them should be merged into one. Helps reviewers grasp class shape at a glance. Matches SonarDelphi communitydelphi:ConsecutiveVisibilitySection. Note: empty header followed by another header is the related but distinct `EmptyVisibilitySection` rule (SCA087).

```pascal
// BAD
type TFoo = class
  private FX: Integer;
  public procedure A;
  private FY: Integer;
  end;

// GOOD
type TFoo = class
  private
    FX, FY: Integer;
  public procedure A;
  end;
```

---
## SCA096
**Constructor without inherited call**

> Constructor missing `inherited Create` - parent stays uninitialized

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `inheritance`, `initialization` |
| Detector | `uConstructorWithoutInherited.pas` |

A constructor that does not call `inherited Create(...)` (or `inherited;`) skips parent-class initialization. Parent fields and registrations end up at default/nil state, which leads to follow-up crashes when methods expect the parent to be ready. Matches SonarDelphi communitydelphi:ConstructorWithoutInherited.

```pascal
// BAD
constructor TFoo.Create;
begin
  FX := 0;
end;

// GOOD
constructor TFoo.Create;
begin
  inherited;
  FX := 0;
end;
```

---
## SCA097
**Destructor without inherited call**

> Destructor missing `inherited Destroy` - parent cleanup is skipped (leak risk)

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `inheritance`, `memory-leak` |
| Detector | `uDestructorWithoutInherited.pas` |

A destructor without `inherited Destroy` (or `inherited;`) prevents the parent class from releasing its own fields, unregistering handlers, and updating reference counts. Almost always a leak. Matches SonarDelphi communitydelphi:DestructorWithoutInherited.

```pascal
// BAD
destructor TFoo.Destroy;
begin
  FreeAndNil(FBar);
end;

// GOOD
destructor TFoo.Destroy;
begin
  FreeAndNil(FBar);
  inherited;
end;
```

---
## SCA098
**Redundant conditional assignment**

> `if Cond then X := True else X := False` should be `X := Cond`

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `simplification`, `style` |
| Detector | `uRedundantConditional.pas` |

Two branches assigning True/False to the same variable can be reduced to a single direct assignment (or `not Cond` if the polarity is reversed). Shorter, faster, and matches the boolean expression more directly. Matches SonarDelphi communitydelphi:RedundantConditional.

```pascal
// BAD
if Active then Result := True else Result := False;

// GOOD
Result := Active;
```

---
## SCA099
**Asymmetric begin/end in if/else**

> then-branch uses `begin..end` but else-branch is a single statement

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `style`, `consistency` |
| Detector | `uIfElseBegin.pas` |

When the then-branch uses `begin..end`, the else-branch should too (or both should drop it). The mixed form (`end else DoStuff;`) makes a future reader unsure whether more statements belong in the else-branch but were forgotten. `else if` (else-if chain) and `else begin` are explicitly allowed. Matches SonarDelphi communitydelphi:IfElseBegin.

```pascal
// BAD
if Active then
begin
  DoA;
  DoB;
end
else
  DoC;

// GOOD
if Active then
begin
  DoA;
  DoB;
end
else
begin
  DoC;
end;
```

---
## SCA100
**Pointer type alias not prefixed with P**

> `Foo = ^Bar` should be `PBar = ^Bar` (P-prefix convention)

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `naming`, `convention` |
| Detector | `uPointerName.pas` |

Delphi convention since day one: a pointer alias on `TXxx` is named `PXxx`. The `P` prefix makes the indirection visible at the call site. Matches SonarDelphi communitydelphi:PointerName. Naming framework will later make the prefix configurable.

```pascal
// BAD
type TIntPtr = ^Integer;

// GOOD
type PInteger = ^Integer;
```

---
## SCA101
**Branch without begin..end block**

> `then`/`else`/`do <stmt>` - prefer explicit `begin..end`

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `style`, `bug-risk` |
| Detector | `uBeginEndRequired.pas` |

A single-statement branch without `begin..end` is easy to misread; adding a second statement later without re-blocking is a classic source of indentation-vs-semantics bugs. Style-debated rule (many Delphi codebases use the compact form deliberately) - lsHint, easy to disable in profiles. `else if` chain, `raise`/`exit`/`break`/`continue` and other block-opening statements are explicitly allowed. Matches SonarDelphi communitydelphi:BeginEndRequired.

```pascal
// BAD
if Active then DoStuff;

// GOOD
if Active then
begin
  DoStuff;
end;
```

---
## SCA102
**Nested routine inside another method**

> Local nested procedure/function - extract to unit-level

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `modularity`, `testing` |
| Detector | `uNestedRoutines.pas` |

Nested routines (a `procedure`/`function` declared inside the local-decl section of another routine) are syntactically allowed but discourage testing and reuse: the inner routine can't be unit-tested or reused from elsewhere. Modern Delphi prefers anonymous methods (lambdas) for the rare cases the nesting was actually needed. Anonymous methods are NOT flagged (they have no name in the AST). Matches SonarDelphi communitydelphi:NestedRoutines.

```pascal
// BAD
procedure Outer;
  procedure Inner; begin DoX; end;
begin
  Inner;
end;

// GOOD
procedure Inner; begin DoX; end;
procedure Outer;
begin
  Inner;
end;
```

---
## SCA103
**Class field not prefixed with F**

> Class fields should follow `F<Name>` convention

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `naming`, `convention` |
| Detector | `uFieldName.pas` |

Delphi convention: class instance fields are named `FFoo` so the reader instantly knows they refer to a class member (vs a local variable or parameter). The `F` prefix avoids naming clashes with public properties (`FFoo` field with `Foo` property is the canonical pair). Only `private` and `protected` field declarations are checked - public/published fields are caught by `PublicField` (SCA089) anyway. Matches SonarDelphi communitydelphi:FieldName.

```pascal
// BAD
type TFoo = class
  private
    Counter: Integer;
  end;

// GOOD
type TFoo = class
  private
    FCounter: Integer;
  end;
```

---
## SCA104
**Class/record type not prefixed with T**

> Class and record type aliases should start with `T`

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `naming`, `convention` |
| Detector | `uTypeName.pas` |

Delphi convention: class types `TXxx`, records `TXxx` or `RXxx`, interfaces `IXxx`, pointers `PXxx` (SCA100), exceptions `EXxx`. This detector covers the class/record subset only. Forward declarations (`TFoo = class;`), `class of` references (`TFooClass = class of TFoo`) and generic syntax are handled. Matches SonarDelphi communitydelphi:TypeName.

```pascal
// BAD
type Counter = class
  ...
  end;

// GOOD
type TCounter = class
  ...
  end;
```

---
## SCA105
**Interface type not prefixed with I**

> Interface aliases should start with `I` (`IFoo = interface`)

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `naming`, `convention` |
| Detector | `uInterfaceName.pas` |

Delphi convention: interfaces are `IXxx`, mirroring `TXxx` for classes and `PXxx` for pointers. The `I` prefix signals contract vs implementation at every callsite. Also covers `dispinterface`. Matches SonarDelphi communitydelphi:InterfaceName.

```pascal
// BAD
type Service = interface ['{...}'] end;

// GOOD
type IService = interface ['{...}'] end;
```

---
## SCA106
**Method not in PascalCase**

> Methods should start with an uppercase letter (PascalCase)

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `naming`, `convention` |
| Detector | `uMethodName.pas` |

Delphi convention is PascalCase (UpperCamel) for routines and methods: `DoSomething`, not `doSomething` or `do_something`. Operator overloads and identifiers starting with `_` are exempted. Matches SonarDelphi communitydelphi:MethodName. AST-based: checks `nkMethod.Name` (qualified `TFoo.bar` splits on the dot).

```pascal
// BAD
procedure doStuff;

// GOOD
procedure DoStuff;
```

---
## SCA107
**Public member could be strict private**

> Public member is referenced ONLY by methods of its declaring class - `strict private` reaches the strongest encapsulation

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `encapsulation`, `visibility` |
| Detector | `uVisibilityCheck.pas` |

Single-file analysis: every visible caller of the `public` member is itself a method of the SAME class (no sibling class, no top-level procedure, no subclass in this unit). `strict private` (D2007+, class-scope, not unit-scope) is the tightest correct visibility. Same single-file caveat as CanBeUnitPrivate: cross-unit consumers are invisible and the compiler enforces correctness via E2361 if the change breaks something. Skips: published, virtual/abstract/override/dynamic, class constructors/destructors, RTTI-driven bases (TForm/TFrame/TDataModule/TComponent), pure-class-method utility classes. Suppress per-line with `// noinspection CanBeStrictPrivate` for intentional public surface.

```pascal
// BAD
type
  TFoo = class
  public
    procedure Helper;       // only TFoo.Run calls it
    procedure Run;
  end;

// GOOD
type
  TFoo = class
  strict private
    procedure Helper;
  public
    procedure Run;
  end;
```

---
## SCA108
**TThread.Synchronize from destructor**

> Synchronize() called from destructor Destroy - classic deadlock between worker and UI thread

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `concurrency`, `deadlock`, `threading` |
| CWE | [CWE-833](https://cwe.mitre.org/data/definitions/833.html) |
| Detector | `uSynchronizeInDestructor.pas` |

TThread.Synchronize() in a destructor body is the canonical Delphi threading deadlock: the worker thread blocks on the UI thread, but the UI thread is typically already blocked in WaitFor or the implicit WaitFor inside .Free, leading to a permanent hang. Move Synchronize-based finalization to a Terminate / OnTerminate callback that runs before the worker reaches its destructor, or guarantee the destructor is never invoked from a context that holds the UI thread. AST-based: walks every nkMethod whose name ends in '.Destroy' (or whose TypeRef carries the 'destructor' marker) and flags nkCall to 'Synchronize' / '<obj>.Synchronize'.

```pascal
// BAD
destructor TWorker.Destroy;
begin
  Synchronize(procedure begin Form1.Log('done') end);  // deadlock
  inherited;
end;

// GOOD
// Move the notify outside the destructor:
// trigger an OnTerminate handler that runs BEFORE TThread.Destroy waits.
FOnDone := procedure begin Form1.Log('done') end;
OnTerminate := FOnDone;
// destructor stays Synchronize-free.
```

---
## SCA109
**Lock acquired without try/finally release**

> TCriticalSection / Monitor / WinAPI lock taken without enclosing try..finally - exception leaves the lock held

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `concurrency`, `lock`, `exception-safety` |
| CWE | [CWE-667](https://cwe.mitre.org/data/definitions/667.html) |
| Detector | `uLockWithoutTryFinally.pas` |

Acquiring a lock (TCriticalSection.Enter / .Acquire, TMonitor.Enter, TMultiReadExclusiveWriteSynchronizer.BeginWrite, WinAPI EnterCriticalSection) without immediately following with try..finally containing the matching Leave / Release / EndWrite is one of the most common Delphi threading bugs: any exception between the acquire and the release leaves the lock permanently held, deadlocking every subsequent caller. Lexical detection: matches the acquire patterns and checks whether the next statement after the `;` is `try`. Suppress with `// noinspection LockWithoutTryFinally` for intentionally-unprotected sequences (rare; usually means the next call is itself never going to throw).

```pascal
// BAD
FLock.Enter;
DoWork;     // exception here leaves FLock held forever
FLock.Leave;

// GOOD
FLock.Enter;
try
  DoWork;
finally
  FLock.Leave;
end;
```

---
## SCA110
**String concatenation in loop**

> `s := s + x` inside for/while/repeat - quadratic reallocations

| Field | Value |
|---|---|
| Severity | Warning | Type | Code Smell |
| Tags | `performance`, `memory` |
| Detector | `uPerfHotspots.pas` |

Each `s := s + x` inside a loop body allocates a NEW string of length(s)+length(x) and copies both pieces into it. Across N iterations that is O(N^2) byte copies and Heap pressure. Two idiomatic alternatives in Delphi: (1) build into a TStringBuilder and call ToString once at the end, (2) collect parts in a TStringList and read .Text once. Detector heuristic: lexical match on the LHS == first-RHS-operand pattern (case-insensitive) inside any for/while/repeat block. False positives possible if `s` is intentionally re-used as an accumulator across short loops with tiny payloads; suppress with `// noinspection StringConcatInLoop`.

```pascal
// BAD
for i := 0 to High(Names) do
  s := s + Names[i] + ', ';

// GOOD
var SB := TStringBuilder.Create;
try
  for i := 0 to High(Names) do
    SB.Append(Names[i]).Append(', ');
  s := SB.ToString;
finally SB.Free; end;
```

---
## SCA111
**ParamByName(...) called in loop**

> `Query.ParamByName('x').AsXxx := ...` inside a loop - linear lookup per iteration

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `performance`, `database` |
| Detector | `uPerfHotspots.pas` |

ParamByName walks the TParam collection by string-compare on each call (linear in number of params). Inside a Hot-Path / loop this turns one ParamByName per Query.Execute into N per Execute. Cache the TParam reference once outside the loop or use the integer-indexed Params[i] property if the parameter position is known.

```pascal
// BAD
for i := 0 to High(Ids) do begin
  Q.ParamByName('id').AsInteger := Ids[i];
  Q.ExecSQL;
end;

// GOOD
var P := Q.ParamByName('id');
for i := 0 to High(Ids) do begin
  P.AsInteger := Ids[i];
  Q.ExecSQL;
end;
```

---
## SCA112
**FieldByName(...) called in loop**

> `DataSet.FieldByName('x').AsXxx` inside a loop - linear lookup per row

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `performance`, `database` |
| Detector | `uPerfHotspots.pas` |

FieldByName walks the TFields collection by string-compare for every call. In a DataSet-iteration loop that turns one lookup per Field into N lookups per .Next, sometimes per-row times N-fields = O(N*M). Cache the TField reference once before the loop and read/write it directly. Same fix-path as SCA111 (ParamByName) - just a different collection.

```pascal
// BAD
while not Q.Eof do begin
  Total := Total + Q.FieldByName('Amount').AsCurrency;
  Q.Next;
end;

// GOOD
var Amt := Q.FieldByName('Amount');
while not Q.Eof do begin
  Total := Total + Amt.AsCurrency;
  Q.Next;
end;
```

---
## SCA113
**TThread.Resume is deprecated**

> `MyThread.Resume` - use `MyThread.Start` (since Delphi 2010)

| Field | Value |
|---|---|
| Severity | Warning | Type | Code Smell |
| Tags | `concurrency`, `deprecated` |
| Detector | `uConcurrencyExt.pas` |

TThread.Resume has been deprecated since Delphi 2010 in favor of TThread.Start (suspends-on-create + resume-on-start became one explicit Start call). The compiler emits a deprecation warning, but it is easily missed in larger code-bases. Two fixes: (a) call .Start instead of .Resume, (b) construct with CreateSuspended := False and skip the Resume/Start step entirely. Detector matches any `<ident>.Resume` - if the identifier is NOT a TThread descendant (e.g. a TForm), suppress per line with `// noinspection ThreadResumeDeprecated`.

```pascal
// BAD
MyThread := TWorker.Create(True);
MyThread.Resume;

// GOOD
MyThread := TWorker.Create(True);
MyThread.Start;
```

---
## SCA114
**TThread destroyed without Terminate+WaitFor**

> `FreeAndNil(MyThread)` without prior `Terminate; WaitFor` - worker may still run

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `concurrency`, `lifecycle` |
| CWE | [CWE-364](https://cwe.mitre.org/data/definitions/364.html) |
| Detector | `uConcurrencyExt.pas` |

Destroying a TThread instance whose Execute is still running causes the destructor to wait via TThread.Free's implicit WaitFor - but if Execute does not honor the Terminated flag, the destructor blocks forever (UI hang), and during that wait the application can hit AVs as half-destroyed state is observed. The safe pattern is `MyThread.Terminate; MyThread.WaitFor; FreeAndNil(MyThread);` (or use FreeOnTerminate=True and never Free manually). Heuristic: matches FreeAndNil(<id>) without `<id>.Terminate` and `<id>.WaitFor` in the preceding ~10 lines. Suppress with `// noinspection TThreadDestroyWithoutTerminate` for non-thread classes.

```pascal
// BAD
// inside an OnClick:
FreeAndNil(FWorker);  // FWorker.Execute still running?

// GOOD
FWorker.Terminate;
FWorker.WaitFor;
FreeAndNil(FWorker);
```

---
## SCA115
**Plaintext HTTP URL**

> `'http://...'` literal for a remote endpoint - MITM-vulnerable

| Field | Value |
|---|---|
| Severity | Warning | Type | Security Hotspot |
| Tags | `security`, `tls`, `network` |
| CWE | [CWE-319](https://cwe.mitre.org/data/definitions/319.html) |
| OWASP | A02:2021-Cryptographic Failures |
| Detector | `uRestHttpSecurity.pas` |

A string literal starting with `http://` for any non-localhost endpoint transmits its payload unencrypted. Credentials, session tokens, and PII travel in plaintext and can be sniffed or modified by any active network actor. The fix is virtually free: change the scheme to `https://` (almost every modern service supports both). Detector skips localhost / 127.x.x.x / [::1] / 0.0.0.0 / host.docker.internal (dev workflows are legitimate) and XML-namespace URIs (`xmlns=`, `schemas`, `w3.org`, ...) which are identities, not network targets.

```pascal
// BAD
Url := 'http://api.example.com/v1/users';

// GOOD
Url := 'https://api.example.com/v1/users';
```

---
## SCA116
**TLS verification disabled**

> Empty `SecureProtocols`, `IgnoreCertificateErrors := True`, or `OnVerifyPeer := nil`

| Field | Value |
|---|---|
| Severity | **Error** | Type | Vulnerability |
| Tags | `security`, `tls`, `network` |
| CWE | [CWE-295](https://cwe.mitre.org/data/definitions/295.html) |
| OWASP | A07:2021-Identification and Authentication Failures |
| Detector | `uRestHttpSecurity.pas` |

Three Delphi patterns silently turn off TLS validation: (a) `SecureProtocols := []` removes every protocol, allowing fallback to plaintext or weakest-available, (b) `IgnoreCertificateErrors := True` accepts any certificate including expired and self-signed, (c) `OnVerifyPeer := nil` short-circuits the verification callback. All three are MITM-attractive. Replace with explicit modern-only protocols (`[TLSv1_2, TLSv1_3]`), a real trust store, or a fingerprint-pinning OnVerifyPeer handler. Detector matches the three property-assignment patterns lexically.

```pascal
// BAD
Client.SecureProtocols := [];
Client.IgnoreCertificateErrors := True;

// GOOD
Client.SecureProtocols := [TLSv1_2, TLSv1_3];
Client.OnVerifyPeer := VerifyPinnedFingerprint;
```

---
## SCA117
**Public member missing doc comment**

> Public method or property in `interface` section with no doc comment directly above

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `documentation`, `api-design` |
| Detector | `uPublicMemberWithoutDoc.pas` |

A public member in a unit's `interface` section is part of the documented API surface that other units consume. Missing doc-comments make the unit harder to use without reading the implementation. The detector accepts any of: `///` XMLDoc, a `{ ... }` block, a `(* ... *)` block, or one-or-more `//` single-line comments directly above the declaration. Skips: constructors `Create` / destructors `Destroy` (self-explanatory by convention), members starting with `_` (private-marker in public sections), `published` members (DFM/RTTI-driven, doc would be noise). Suppression: `// noinspection PublicMemberWithoutDoc` per declaration.

```pascal
// BAD
type
  TFoo = class
  public
    procedure Run;
  end;

// GOOD
type
  TFoo = class
  public
    /// <summary>Starts the worker.</summary>
    procedure Run;
  end;
```

---
## SCA118
**Exception class without `E` prefix**

> `class(Exception)`-Descendant should follow Delphi-RTL `E<Name>` convention

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `naming`, `convention` |
| Detector | `uNamingExt.pas` |

Delphi-RTL convention is unambiguous: exception classes start with `E` (EAbort, EConvertError, EAccessViolation). User-defined exception classes that omit the prefix break the convention and obscure the class kind at the call site (`raise MyError.Create(...)` vs `raise EMyError.Create(...)`). Detector matches any class whose TypeRef inherits from a known Exception class (Exception, EAbort, EAccessViolation, EExternal) and whose name does not start with `E<UpperCase>`.

```pascal
// BAD
type
  MyError = class(Exception);

// GOOD
type
  EMyError = class(Exception);
```

---
## SCA119
**Local constant not in UPPER_SNAKE_CASE**

> `const X = 42;` inside a method - prefer UPPER_SNAKE_CASE for numeric constants

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `naming`, `convention` |
| Detector | `uNamingExt.pas` |

Local numeric/integer constants inside a method body benefit from UPPER_SNAKE_CASE (`MAX_RETRIES`, `BUFFER_SIZE`, `DEFAULT_TIMEOUT`) - the reader sees instantly that the identifier is a constant, not a variable, and the convention matches the C / Java / Python convention so cross-language readers do not stumble. Detector skips: very-short names (<=2 chars, typically loop counters or temporaries), string/char-typed constants (often UI labels where PascalCase is fine). Suppress with `// noinspection LocalConstantName` for legitimate PascalCase locals.

```pascal
// BAD
procedure Foo;
const
  MaxRetries = 3;
begin ... end;

// GOOD
procedure Foo;
const
  MAX_RETRIES = 3;
begin ... end;
```

---
## SCA120
**Exception constructed but never raised**

> `EFoo.Create('msg');` allocates an exception object without `raise` - the error path is silently skipped

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `exception`, `error-handling`, `sonardelphi` |
| Detector | `uMissingRaise.pas` |

Pattern `EConvertError.Create('bad input');` without a preceding `raise` constructs an exception instance, fails to throw it, and the calling code continues as if nothing happened. The allocated object leaks (classic TObject) or gets immediately collected (ARC), and the intended error branch is gone. Almost always a copy-paste regression from `raise EConvertError.Create(...)` where the `raise` keyword was deleted. Detector heuristic: any `nkCall` named `<Ident>.Create(...)` where `<Ident>` is `Exception` or matches the Delphi `E`-prefix convention (`E` + uppercase letter, e.g. `EConvertError`, `EMyDomainError`). `raise X.Create(...)` is consumed as a string by the raise-statement parser and never produces a `nkCall`, so genuinely raised exceptions are not false-positives. Maps to Sonar-Delphi `MissingRaiseCheck`.

```pascal
// BAD
procedure Validate(x: Integer);
begin
  if x < 0 then
    EArgumentOutOfRangeException.Create('x negative');  // never raised!
end;

// GOOD
procedure Validate(x: Integer);
begin
  if x < 0 then
    raise EArgumentOutOfRangeException.Create('x negative');
end;
```

---
## SCA121
**Function never assigns Result**

> Function body finishes without writing `Result` (or `<FunctionName> := ...`) - return value is undefined

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `function`, `uninitialized`, `sonardelphi` |
| Detector | `uRoutineResultAssigned.pas` |

A function that reaches its `end;` without any `Result := ...` or Pascal-style `<FunctionName> := ...` returns whatever register/stack garbage happens to occupy the result slot. In Release builds the caller therefore receives the value of the last same-sized call - a classic Heisenbug that flips with optimisation level. Detector is intentionally conservative: it skips functions that contain any `Exit` (could be `Exit(value)` - the AST loses the argument) or `raise` (function may always throw). Procedures, abstract/forward/external declarations, and DispatchID-only declarations are also skipped. Partial coverage (Result set in one branch only) is currently a false-negative pending CFG analysis. Maps to Sonar-Delphi `RoutineResultAssignedCheck`.

```pascal
// BAD
function GetCount(L: TList): Integer;
begin
  if L = nil then
    LogMessage('nil list');
  // Result never set -> garbage
end;

// GOOD
function GetCount(L: TList): Integer;
begin
  Result := 0;
  if L <> nil then
    Result := L.Count;
end;
```

---
## SCA122
**Re-raise of bound exception variable**

> `on E: T do ... raise E;` discards the original stack trace - use bare `raise;` to keep it

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `exception`, `error-handling`, `stack-trace`, `sonardelphi` |
| Detector | `uReRaiseException.pas` |

`raise E` inside an `on E: SomeException do ...` handler starts a fresh exception propagation rooted at the re-raise site. The original stack trace - the path from where the exception was first raised down through every called routine until it reached this `except` block - is gone. Crash reports and debugger views then point at the handler, not at the actual fault location, which makes triage dramatically harder. The intent of the developer was almost certainly `raise;` (no argument), which continues propagating the *current* exception object with its existing trace intact. Detector walks each `nkOnHandler` with a non-empty bound variable name and flags every `nkRaise` inside that subtree whose argument is exactly that variable (case-insensitive). `raise;` (no argument) is correct and not flagged; `raise EWrapper.Create(...)` is also accepted (deliberate wrap). Maps to Sonar-Delphi `ReRaiseExceptionCheck`.

```pascal
// BAD
try
  RiskyCall;
except
  on E: EDivByZero do
  begin
    Log(E.Message);
    raise E;          // loses original trace
  end;
end;

// GOOD
try
  RiskyCall;
except
  on E: EDivByZero do
  begin
    Log(E.Message);
    raise;            // preserves trace
  end;
end;
```

---
## SCA123
**Type-cast immediately before Free / Destroy**

> `TFoo(x).Free` - the type-cast has no effect on which Destroy runs (Destroy is virtual)

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `memory`, `destructor`, `cast`, `sonardelphi` |
| Detector | `uCastAndFree.pas` |

Writing `TStringList(L).Free` or `TObject(L).Destroy` is a confusion smell. `TObject.Free` is a non-virtual wrapper around the *virtual* `Destroy`, so virtual dispatch happens through the runtime type of `L`, not through the static cast type. Whether you write `L.Free` or `T(L).Free`, the same destructor chain runs. The cast therefore either is redundant (cast to the variable's own type) or is misleading (cast to an unrelated class that suggests Destroy will pick a different override - it will not). If the cast target is wrong, the rest of the surrounding code may rely on that wrong assumption and break under refactoring. Detector pattern-matches `nkCall.Name` against `<Ident>(<expr>).Free[()][;]` and `<Ident>(<expr>).Destroy[()][;]` where `<Ident>` follows the Delphi class/interface naming convention (`T` or `I` plus uppercase letter). Plain `L.Free` and qualified `Owner.Bar(x).Free` (likely a function-result Free) are not flagged. Maps to Sonar-Delphi `CastAndFreeCheck`.

```pascal
// BAD
procedure Cleanup(L: TObject);
begin
  TStringList(L).Free;     // cast has no effect on dispatch
end;

// GOOD
procedure Cleanup(L: TObject);
begin
  L.Free;                  // virtual Destroy resolves at runtime
end;
```

---
## SCA124
**Constructor invoked on instance instead of class**

> `obj.Create` - invokes constructor as method on an existing instance, skips allocation and re-runs field initialisation over live data

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `constructor`, `memory`, `lifecycle`, `sonardelphi` |
| Detector | `uInstanceInvokedConstructor.pas` |

Delphi allows a constructor to be invoked on an instance, e.g. `obj.Create;`, but the result is almost never what was intended. When called as a class-method (`TFoo.Create`), the runtime first allocates a fresh memory block via `TObject.NewInstance`, sets up the VMT pointer, and then runs the constructor body. When called on an existing instance, the allocation path is skipped entirely - only the constructor body runs, which re-initialises fields (`FList := TList.Create;` overwrites the previous `FList` without freeing it, managed-type refs get stomped, default values clobber whatever the caller had set). The result is at best a logic bug, at worst memory corruption. Detector heuristic (no type-resolver available): match `nkCall.Name` against `<Ident>.Create[(<args>)][;]` where `<Ident>` starts with a lowercase letter (clearly a variable by Delphi convention, since types use the `T<Upper>` / `I<Upper>` prefix). Skips `Self`, `Result`, `Inherited`, multi-dot paths (`A.B.Create` - ambiguous), cast forms (`T(x).Create`) and class names. Accepts a small known false-positive risk for `TClass`-typed lowercase variables (rare in practice). Maps to Sonar-Delphi `InstanceInvokedConstructorCheck`.

```pascal
// BAD
procedure Reset;
var list: TStringList;
begin
  list := TStringList.Create;
  ...
  list.Create;            // no allocation, re-initialises the existing object
end;

// GOOD
procedure Reset;
var list: TStringList;
begin
  list := TStringList.Create;
  ...
  list.Clear;             // or FreeAndNil + new TStringList.Create
end;
```

---
## SCA125
**Override whose entire body is `inherited;`**

> An override that only forwards to the parent serves no purpose - remove it

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `inheritance`, `dead-code`, `sonardelphi` |
| Detector | `uInheritedMethodEmpty.pas` |

A method declared with `override` whose body contains only `inherited;` (or `inherited <SameName>;`) adds nothing on top of the parent class's behaviour. The compiler's normal virtual dispatch already calls the parent implementation if the subclass does not override - the empty override is therefore pure noise that wastes a VMT slot, slows down code reviews ('does this override do something?' - reader has to read the body to confirm 'no'), and creates dead code that needs to be revisited every time the parent method's signature changes. Detector walks every `nkMethod` whose `TypeRef` contains `;override`, skips bodyless variants (abstract / forward / external / dispid), and flags the method when its body contains exactly one non-parameter child that is `nkInherited` with either no argument expression at all (`inherited;`) or with the same identifier as the method itself (`inherited <SameName>;`). Calls to a *different* parent method (`inherited Other;` - intentional hijack) are deliberately not flagged. Maps to Sonar-Delphi `InheritedMethodWithNoCodeCheck`.

```pascal
// BAD
procedure TFooSubclass.AfterConstruction; override;
begin
  inherited;     // adds nothing - drop this whole override
end;

// GOOD
// Remove the override entirely. The parent's AfterConstruction will
// be invoked by the normal virtual dispatch.
```

---
## SCA126
**Use Assigned() instead of `= nil` / `<> nil`**

> Pascal convention: `Assigned(x)` and `not Assigned(x)` are the canonical nil-checks

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `convention`, `nil`, `sonardelphi` |
| Detector | `uNilComparison.pas` |

Direct comparison against `nil` works for object references but breaks down for method-pointer types and Variants, where the standard library prefers `Assigned`. Sticking to a single form across the code base avoids edge-case bugs and improves readability - the reader does not need to verify which form the variable's type supports. Detector scans every AST node's `Name` and `TypeRef` (the latter holds the textual form of `if`/`while`/`until` conditions and assignment right-hand sides) for the pattern `<op> nil` where `<op>` is `=` or `<>`. String literals (`'nil'`) are stripped before the match, and `:= nil` (assignment), `<= nil` / `>= nil` (rare nonsensical compares) are explicitly excluded. Maps to Sonar-Delphi `NilComparisonCheck`.

```pascal
// BAD
if Obj = nil then
  Exit;
if Obj <> nil then
  Obj.DoStuff;

// GOOD
if not Assigned(Obj) then
  Exit;
if Assigned(Obj) then
  Obj.DoStuff;
```

---
## SCA127
**Raise the bare `Exception` base class instead of a specific subclass**

> `raise Exception.Create('...')` - the base class carries no semantic information, callers cannot filter selectively

| Field | Value |
|---|---|
| Severity | Warning | Type | Code Smell |
| Tags | `exception`, `error-handling`, `sonardelphi` |
| Detector | `uRaisingRawException.pas` |

Raising the RTL base class `Exception` is the equivalent of throwing `new Error('something')` in JavaScript: it tells the caller *that* something went wrong, but not *what*. Calling code is then forced to catch the broadest possible class (`on E: Exception do ...`), which also catches every unrelated runtime error and tends to swallow bugs. Prefer a specific subclass (e.g. `EArgumentOutOfRangeException`, `EFileNotFoundException`, a domain-specific `EMyDomainError`). Detector walks every `nkRaise` node and flags it when the raised expression starts with `Exception.Create` (case-insensitive) or is exactly `Exception` (no Create call). Bare `raise;` (re-raise) and `raise E;` (variable) are not flagged. Maps to Sonar-Delphi `RaisingRawExceptionCheck`.

```pascal
// BAD
if x < 0 then
  raise Exception.Create('x is negative');

// GOOD
if x < 0 then
  raise EArgumentOutOfRangeException.CreateFmt('x = %d', [x]);
```

---
## SCA128
**Locale-dependent format call without explicit TFormatSettings**

> `StrToDate(s)`, `FormatFloat(...)` etc. without TFormatSettings depend on the system locale - breaks across machines / users

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `locale`, `i18n`, `sonardelphi` |
| Detector | `uDateFormatSettings.pas` |

Pascal's locale-aware conversion functions (`StrToDate`, `StrToTime`, `StrToDateTime`, `DateToStr`, `TimeToStr`, `DateTimeToStr`, `StrToFloat`, `StrToCurr`, `FloatToStr`, `CurrToStr`, `FormatDateTime`, `FormatFloat`, `FormatCurr`) default to the global `SysUtils.FormatSettings` record, which is initialised from the operating-system regional settings. The same code therefore behaves differently on a developer's DE-locale machine (`DateSeparator` = '.', `DecimalSeparator` = ',') than on a production server with EN-locale ('/' and '.'). Data exchanged via files, APIs, databases or CSV must always go through an explicit `TFormatSettings` (typically `FormatSettings := TFormatSettings.Invariant` for machine-readable output, or a user-locale snapshot for UI). Detector walks every `nkCall` whose function name matches a known locale-dependent RTL routine and flags the call when its name does not mention `FormatSettings` (case-insensitive substring). `StrToInt` / `IntToStr` and the boolean variants are explicitly **not** locale-dependent and not flagged. Maps to Sonar-Delphi `DateFormatSettingsCheck`.

```pascal
// BAD
var d := StrToDate(UserInput);     // breaks under EN locale
WriteLn(DateToStr(Now));

// GOOD
var FS := TFormatSettings.Invariant;
var d := StrToDate(UserInput, FS);
WriteLn(DateToStr(Now, FS));
```

---
## SCA129
**Cast from string to 8-bit string type without explicit encoding**

> `AnsiString(s)` / `UTF8String(s)` / `RawByteString(s)` silently drops characters outside the active code page

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `encoding`, `unicode`, `data-loss`, `sonardelphi` |
| Detector | `uUnicodeToAnsiCast.pas` |

Casting a `UnicodeString` (or any string typed expression - Delphi `string` is `UnicodeString` since XE) to one of the 8-bit string families (`AnsiString`, `UTF8String`, `RawByteString`, `ShortString`) goes through the implicit `DefaultSystemCodePage` conversion. Every codepoint outside the active code page is silently replaced with `?`. Emoji, non-Latin scripts, and even some Western accented letters disappear, but the assignment compiles cleanly and runs without exception - so the bug surfaces only when the data round-trips back through a Unicode aware consumer (a different DB, an HTTP API, an Excel export). Use a deliberate encoding helper (`UTF8Encode`, `TEncoding.UTF8.GetBytes`, `WideStringToUTF8` ...) instead. Detector walks `nkCall` nodes whose name starts (case-insensitive) with `AnsiString(`, `UTF8String(`, `RawByteString(` or `ShortString(`. Empty string-literal arguments (`AnsiString('')`) are not flagged. Casts to `string` (= `UnicodeString` in modern Delphi) are also not flagged. Accepts the false-positive that the input might already be the same 8-bit type (redundant cast, still suspicious as a smell). Maps to Sonar-Delphi `UnicodeToAnsiCastCheck`.

```pascal
// BAD
var u: UnicodeString;
u := 'Smiley: ' + #$1F600;
logStream.WriteString(AnsiString(u));   // smiley becomes '?'

// GOOD
var u: UnicodeString;
u := 'Smiley: ' + #$1F600;
logStream.WriteString(UTF8Encode(u));   // explicit, full Unicode
```

---
## SCA130
**Cast of Char value to PChar reinterprets codepoint as pointer**

> `PChar('A')` is not `PChar("A")` - the cast treats the 16-bit codepoint as a raw memory address

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `pointer`, `char`, `undefined-behavior`, `sonardelphi` |
| Detector | `uCharToCharPointerCast.pas` |

Delphi happily compiles `PChar(c)` where `c` is of type `Char`, `WideChar` or `AnsiChar`. The result is **not** a null-terminated 1-character string - the cast simply reinterprets the 16-bit/8-bit codepoint as a pointer. So `PChar('A')` returns the pointer value `$00000041`, which points into low-process memory; any dereference is undefined behaviour and typically explodes as an access violation, but on some platforms reads stale data instead. The intended pattern is almost always `PChar(stringExpr)`, which returns a pointer into the actual string buffer. Detector walks `nkCall` nodes whose name begins with `PChar(`, `PWideChar(` or `PAnsiChar(` and flags the call when the argument is recognisably a Char value: a single-character quoted literal (`'A'`), a character-ordinal literal (`#65`, `#$41`), or a `Chr(...)` call. Identifier arguments are not flagged because the detector has no type-resolver to determine whether the variable is a `Char` or a `string`. Maps to Sonar-Delphi `CharacterToCharacterPointerCastCheck`.

```pascal
// BAD
var p: PChar;
p := PChar('A');           // p = $00000041 (not a string)
ShowMessage(p);              // access violation

// GOOD
var p: PChar;
p := PChar(string('A'));    // explicit string wrap
ShowMessage(p);
```

---
## SCA131
**IfThen() evaluates both branches - no short-circuit**

> `Math.IfThen(cond, A(), B())` / `StrUtils.IfThen` are normal functions - both arms run before the function is called

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `control-flow`, `side-effects`, `performance`, `sonardelphi` |
| Detector | `uIfThenShortCircuit.pas` |

Both `Math.IfThen` (Integer/Double overload) and `StrUtils.IfThen` (string overload) are regular functions, not language constructs. Pascal evaluates every argument *before* the call, so the function only sees the final result values - it cannot 'skip' the not-selected branch. Whenever the arms contain function or method calls with side effects (DB read, file IO, state mutation) or with non-trivial performance cost, both run unconditionally. The whole point of writing `IfThen(cond, A, B)` instead of `if cond then x := A else x := B` was usually the assumption of short-circuit semantics - which doesn't exist here. Detector walks `nkCall` nodes whose name matches `IfThen(`, `Math.IfThen(`, or `StrUtils.IfThen(` (case-insensitive). After extracting the outer argument list, it strips string literals (so `'a(b)'` doesn't trip the heuristic) and looks for nested `(` - any nested call is a strong signal of a side-effecting branch. Calls with only literals or simple variables as arms are not flagged. Maps to Sonar-Delphi `IfThenShortCircuitCheck`.

```pascal
// BAD
x := Math.IfThen(IsCacheHit, FetchFromCache, FetchFromDb);
//                            both calls run every time

// GOOD
if IsCacheHit then
  x := FetchFromCache
else
  x := FetchFromDb;
```

---
## SCA132
**except on E: Exception catches every error**

> `on E: Exception do ...` catches the base class and therefore every descendant, including system exceptions that should not be silenced (EOutOfMemory, EAccessViolation, EAbort)

| Field | Value |
|---|---|
| Severity | Warning | Type | Code Smell |
| Tags | `exception-handling`, `error-handling`, `sonar50` |
| Detector | `uExceptionTooGeneral.pas` |

Catching `Exception` itself - the root of Delphi's exception hierarchy - silently swallows error categories the calling code is not prepared to handle: out-of-memory conditions, access violations, the `EAbort`-style flow-control exception, and anything else not derived from a domain-specific base class. Prefer a precise `on E: ESpecific do` clause, or several stacked clauses for the cases you can recover from. If you really need a fallback that re-raises after logging, use `except Log(''...''); raise; end;` - the bare `raise;` keeps the original type and stack. The detector walks `nkOnHandler` nodes and reports those whose `TypeRef` equals `Exception` (case-insensitive). Maps to Sonar-50 rule #11 (`ExceptionTooGeneral`).

```pascal
// BAD
try
  ParseConfig(s);
except
  on E: Exception do        // swallows EOutOfMemory / EAbort / ...
    Log(E.Message);
end;

// GOOD
try
  ParseConfig(s);
except
  on E: EConvertError do
    Log(E.Message);
  on E: EFileNotFoundException do
    Log(E.Message);
end;
```

---
## SCA133
**Bare raise outside an except/on handler**

> `raise;` without an exception expression only works *inside* an except handler (re-raise) - outside it raises NIL and produces an Access Violation

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `exception-handling`, `crash`, `sonar50` |
| Detector | `uRaiseOutsideExcept.pas` |

A bare `raise;` re-raises the exception currently being handled. Outside of `except` / `on E: T do` there *is* no current exception, so the RTL receives a NIL exception pointer and an Access Violation is raised inside `System._Raise` - far away from the actual mistake. The detector recursively walks the method AST while tracking an `InHandler` flag. The flag is set when the walker descends into `nkExceptBlock` or `nkOnHandler`. An `nkRaise` node with `Name = 'raise'` (bare form) that is encountered while the flag is False produces a finding. Bare `raise;` inside `finally` blocks that are themselves outside an except handler is correctly flagged. Maps to Sonar-50 rule #15 (`RaiseWithoutClass`).

```pascal
// BAD
procedure Foo(x: Integer);
begin
  if x < 0 then
    raise;             // <- no current exception -> AV inside System._Raise
end;

// GOOD
procedure Foo(x: Integer);
begin
  if x < 0 then
    raise EArgumentException.CreateFmt('x = %d (must be >= 0)', [x]);
end;
```

---
## SCA134
**Variable used after Free / FreeAndNil**

> Dereferencing a variable after `Free` or `FreeAndNil` reads a dangling pointer and produces an Access Violation

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `memory`, `lifecycle`, `crash`, `sonar50` |
| Detector | `uUseAfterFree.pas` |

After `obj.Free` or `FreeAndNil(obj)` the variable points to freed memory (or NIL). Any subsequent member access, indexer, or call passing the variable as receiver is undefined behavior - typically an Access Violation, sometimes silent corruption if the memory was reused. The detector strips strings + comments from the file, finds each `FreeAndNil(<id>)` and `<id>.Free` occurrence, then forward-scans the remaining method body for the same identifier. A subsequent `<id>.<member>`, `<id>(<args>)`, or `<id>[<idx>]` produces a finding. Reassignments `<id> := ...` or var-section starts `<id> :` end the scan window. Bare appearances without an accessor are intentionally not flagged to avoid FP on comparisons like `if x = oldL then`. Maps to Sonar-50 rule #7. Limitation: no control-flow analysis; `if Cond then Free else Use` may FP since the use is on a different path.

```pascal
// BAD
L := TStringList.Create;
L.Free;
L.Add('x');           // <- dangling pointer

// GOOD
L := TStringList.Create;
try
  L.Add('x');
finally
  FreeAndNil(L);     // any subsequent L.Method crashes loudly
end;
```

---
## SCA135
**Concrete subclass inherits an abstract method without override**

> Class derives from a base with an `abstract` method but does not override it - calling the method on the subclass instance raises EAbstractError at runtime

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `oop`, `inheritance`, `sonar50` |
| Detector | `uAbstractNotImpl.pas` |

When a class inherits an `abstract` method from its parent and does not override it, instantiating the class compiles fine but any call to the method raises `EAbstractError`. The detector walks `nkClass` nodes; for each derived class it looks up the direct parent in the same unit, collects the parent's `abstract`-flagged methods, and reports each abstract method whose name does not appear among the derived class's method names. Limitations: within-unit only (cross-unit bases like `TForm`/`TStrings` are not seen); only direct parent (multi-level chains check just one step); class helpers / interfaces / records are skipped. Classes themselves marked `class abstract` are allowed to leave methods abstract. Maps to Sonar-50 rule #10.

```pascal
// BAD
type
  TBase = class
    procedure DoWork; virtual; abstract;
  end;
  TDerived = class(TBase)
    // DoWork not overridden -> EAbstractError on call
  end;

// GOOD
type
  TDerived = class(TBase)
    procedure DoWork; override;
  end;
```

---
## SCA136
**Constructor allocates fields and raises without try/except**

> Constructor assigns fields with `<Class>.Create` and raises later - partially initialised fields leak on the exception path

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `memory`, `constructor`, `exception-handling`, `sonar50` |
| Detector | `uLeakInConstructor.pas` |

When a constructor allocates instance fields and then raises (or calls something that may raise), the already-allocated fields are not freed. The RTL invokes `Destroy` on the half-constructed instance only if `inherited Create` has already returned, and even then only fields the destructor explicitly frees are released. The detector walks `nkMethod` nodes whose `TypeRef` starts with `constructor` (skipping class constructors via the `;class` marker), then requires (a) at least one `nkAssign` whose LHS is `F<Name>` / `Self.F<Name>` and whose RHS contains a `.Create` call, (b) at least one `nkRaise` anywhere in the body, and (c) no `nkTryExcept` anywhere in the body. The combination strongly suggests a leak on the exception path. Limitations: no flow analysis (raise BEFORE any field-init still flags); a partial try/except is treated as fully protective. Maps to Sonar-50 rule #12.

```pascal
// BAD
constructor TFoo.Create;
begin
  FList := TStringList.Create;
  FOther := TOther.Create;
  if not Valid then
    raise EInvalidOp.Create('bad');     // <- FList + FOther leak
end;

// GOOD
constructor TFoo.Create;
begin
  FList := TStringList.Create;
  try
    FOther := TOther.Create;
    if not Valid then
      raise EInvalidOp.Create('bad');
  except
    FreeAndNil(FOther);
    FreeAndNil(FList);
    raise;
  end;
end;
```

---
## SCA137
**Int64 target receives product of two 32-bit operands**

> `<Int64-var> := <a> * <b>` evaluates the multiplication in 32-bit before widening - overflow truncates silently

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `arithmetic`, `integer-overflow`, `sonar50` |
| Detector | `uIntegerOverflow.pas` |

Delphi evaluates a binary expression in the type of its operands, not the type of the assignment target. When two `Integer` (32-bit) operands are multiplied and the result is assigned to an `Int64`, the multiplication runs in 32-bit; if the true product exceeds `MaxInt`, the value is silently truncated before being widened. The fix is to cast at least one operand to `Int64`. The detector strips strings + comments, scans the cleaned text for `<ident>: Int64|UInt64|QWord` declarations to build a set of 64-bit variables, then scans for assignments `<lhs> := <a> * <b>;` where the LHS is a 64-bit variable but both RHS operands are simple identifiers (no cast, no parenthesised expression) that are not themselves 64-bit. Numeric literals on either side suppress the finding (the compiler can often constant-fold safely). Limitations: no type inference for non-local operands (parameters, fields); only `*` is checked, not `+`/`-`; complex expressions like `(a + b) * c` are not matched. Maps to Sonar-50 rule #14.

```pascal
// BAD
var
  BytesTotal: Int64;
  SectorCount, SectorSize: Integer;
begin
  BytesTotal := SectorCount * SectorSize;   // <- 32-bit overflow, then widen

// GOOD
BytesTotal := Int64(SectorCount) * SectorSize;
// Cast one operand; the other is auto-promoted; multiplication is 64-bit.
```

---
## SCA138
**Class has too many methods or fields**

> A class with more than 20 methods or more than 15 instance fields concentrates too many responsibilities - hard to test, hard to evolve, hard to review

| Field | Value |
|---|---|
| Severity | Warning | Type | Code Smell |
| Tags | `oop`, `maintainability`, `single-responsibility`, `sonar50` |
| Detector | `uGodClass.pas` |

God classes are classes that own too much behaviour and state at once: typical examples are UI composite roots, all-in-one manager singletons, or first-generation domain entities that grew with the application. The detector walks `nkClass` nodes, counts direct `nkMethod` and `nkField` children (including those inside `nkVisibilitySection`), and emits a finding when MethodCount > 20 OR FieldCount > 15. Records, interfaces, class helpers, forward declarations and classes marked `class abstract` (designintent contracts) are skipped. Properties are not counted - they are syntactic sugar over getter/setter pairs. Thresholds are hardcoded to the Sonar defaults; god classes typically exceed them by 3-5x so the cutoff does not need to be hyper-tunable. Maps to Sonar-50 rule #31.

```pascal
// BAD
TUiController = class             // 60 methods, 80 fields
  FToolbar, FFilters, FGrid, ...: ...;
  procedure BuildToolbar;
  procedure FilterChange(...);
  procedure GridDrawCell(...);
  // 50 more methods mixing concerns
end;

// GOOD
TToolbarSlots    = record ... end;
TFilterController = class ... end;
TGridRenderer    = class ... end;

TUiController = class                // ~10 methods, ~5 fields
  FToolbar: TToolbarSlots;
  FFilter:  TFilterController;
  FGrid:    TGridRenderer;
  procedure Setup;
end;
```

---
## SCA139
**Free without subsequent nil-out**

> `obj.Free;` without `obj := nil;` (or using FreeAndNil) leaves a dangling pointer - any subsequent use is Use-After-Free

| Field | Value |
|---|---|
| Severity | Warning | Type | Code Smell |
| Tags | `memory`, `lifecycle`, `sonar50` |
| Detector | `uFreeWithoutNil.pas` |

After `obj.Free`, the variable still points at the freed memory. Any further dereference is Use-After-Free, an Access Violation at best, silent corruption at worst. The detector walks `nkCall` nodes whose name matches `<ident>.Free` or `<ident>.Destroy`, then forward-scans the same method for a subsequent `<ident> := nil` or `FreeAndNil(<ident>)`. If neither exists, the call is reported - unless it is the last call in the method body (no follow-up use possible, typical for destructors and try/finally tails). `Self`/`Result`/`inherited` as receivers are excluded since they follow different lifecycle patterns. Maps to Sonar-50 rule #25.

```pascal
// BAD
L := TStringList.Create;
try
  L.Add('x');
finally
  L.Free;             // <- L still points at freed memory
end;
WriteLn(L.Count);     // Use-After-Free

// GOOD
L := TStringList.Create;
try
  L.Add('x');
finally
  FreeAndNil(L);      // L is nil; further use raises loudly
end;
```

---
## SCA140
**Method has too many Exit statements**

> A method with more than 3 Exit calls has too many return paths - hard to read, hard to test, easy to miss one

| Field | Value |
|---|---|
| Severity | Warning | Type | Code Smell |
| Tags | `control-flow`, `maintainability`, `sonar50` |
| Detector | `uMultipleExit.pas` |

Multiple early returns are useful for guard clauses, but past a small number they fragment the control flow so badly that future maintainers miss conditions. The detector counts `nkExit` descendants of each `nkMethod`; threshold is 3. Refactoring options: consolidate guards into a single `if (... or ... or ...) then Exit;`, switch from early returns to a single return variable, or extract the inner logic into a helper. Maps to Sonar-50 rule #34.

```pascal
// BAD
function Find(Id: Integer): TUser;
begin
  if Id < 0 then begin Result := nil; Exit; end;
  if not Db.Connected then begin Result := nil; Exit; end;
  if not Cache.Has(Id) then begin Result := DbLoad(Id); Exit; end;
  Result := Cache.Get(Id);
  Exit;                              // 4. Exit
end;

// GOOD
function Find(Id: Integer): TUser;
begin
  Result := nil;
  if (Id < 0) or not Db.Connected then Exit;
  if Cache.Has(Id) then
    Result := Cache.Get(Id)
  else
    Result := DbLoad(Id);
end;
```

---
## SCA141
**Class implementation exceeds 500 lines**

> A class whose declaration + implementation methods span more than 500 lines has too many responsibilities

| Field | Value |
|---|---|
| Severity | Warning | Type | Code Smell |
| Tags | `maintainability`, `size`, `sonar50` |
| Detector | `uLargeClass.pas` |

Like GodClass (SCA138), but measured by line span rather than method/field count. Catches classes that look small from member counts but have huge implementation bodies - typical for legacy logic classes that grew over years. The detector walks `nkClass` nodes; for each class it determines a span via min(class-decl-line, first-method-with-prefix-line) .. max(class-decl-children-line, last-method-with-prefix-line). Threshold 500 lines. Records, interfaces, helpers and forwards are skipped. Maps to Sonar-50 rule #35.

```pascal
// BAD
// TMainForm with 800 lines of business logic mixed with UI handlers,
// database calls and report generation.

// GOOD
// Extract verticals into focused classes:
TReportRunner   = class ... end;     // own unit
TDataController = class ... end;     // own unit

TMainForm = class(TForm)
  FReport: TReportRunner;
  FData:   TDataController;
end;
```

---
## SCA142
**uses clause is not in alphabetical order**

> Entries in a `uses` clause are not in alphabetical order - merges become non-deterministic and review harder

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `style`, `convention`, `sonar50` |
| Detector | `uUnsortedUses.pas` |

Alphabetical order keeps merge conflicts deterministic and removes a class of bikeshed in code review. The detector walks `nkUses` nodes, collects `nkUsesItem` children, and compares the actual order with a case-insensitive sort. Any mismatch produces a finding on the `uses` line. Single-entry clauses are skipped. Severity is Hint because many projects deliberately group entries by layer (RTL / VCL / third-party / custom) rather than alphabetically - opt-in style, not a hard rule. Maps to Sonar-50 rule #47.

```pascal
// BAD
uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,                    // <- order broken
  System.JSON;

// GOOD
uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.SysUtils;
```

---
## SCA143
**Unit has no descriptive header comment**

> Unit starts with `interface` directly, without an explaining comment block between `unit ...;` and `interface`

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `documentation`, `convention`, `sonar50` |
| Detector | `uMissingUnitHeader.pas` |

A short header comment between the `unit ...;` declaration and the `interface` keyword tells future maintainers what the unit is for - purpose, scope, important invariants, ownership. The detector reads the file's leading lines, finds the `unit` and `interface` markers, and verifies that at least one comment line (`//`, `{...}`, or `(* ... *)`) exists between them. Severity is Hint because many legacy units skip the header without functional consequence. Maps to Sonar-50 rule #48.

```pascal
// BAD
unit MyUnit;

interface

uses ...;

// GOOD
unit MyUnit;

// Database-connection pool: wraps FireDAC TFDConnection setup
// for the report subsystem. Thread-safe; single instance per app.

interface

uses ...;
```

---
## SCA144
**Float equality / inequality comparison**

> `a = b` or `a <> b` between Single/Double/Extended operands is unreliable due to IEEE-754 rounding - use SameValue/Math.IsZero

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `floating-point`, `precision`, `sonar50` |
| Detector | `uFloatEquality.pas` |

IEEE-754 floating-point arithmetic does not guarantee exact equality even for results that look identical to the developer (`0.1 + 0.2 = 0.3` is False). Equality checks against floats are a classic silent-bug source - they look fine in tests but occasionally fire wrong. The detector strips strings and comments, then in two phases: (1) collects local variable declarations whose type is `Single`, `Double`, `Extended`, `Real`, or `Currency`; (2) scans for `<ident> = <expr>` or `<ident> <> <expr>` where at least one side references a known float variable. `:=` assignments are excluded via lookbehind. Limitations: no type-inference for function returns or non-local parameters; complex expressions like `a + b = c + d` only fire when at least one operand is a known float variable. Maps to Sonar-50 rule #19. Fix: use `System.Math.SameValue(a, b, Eps)` or `IsZero(a - b)`.

```pascal
// BAD
var Ratio: Double;
...
if Ratio = 0.5 then DoStuff;     // <- IEEE-754: almost never true after arithmetic

// GOOD
uses System.Math;
...
if SameValue(Ratio, 0.5, 1e-9) then DoStuff;
```

---
## SCA145
**Raise inside destructor without try/except**

> An unprotected `raise` in a destructor aborts the cleanup chain - inherited Destroy and subsequent FreeAndNil calls are skipped, state stays inconsistent

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `exception-handling`, `lifecycle`, `destructor`, `sonar50` |
| Detector | `uExceptInDestructor.pas` |

A destructor's job is to release the resources of one object instance and then call `inherited Destroy` to let the parent release its part. If the destructor raises an exception that no surrounding handler catches, the whole cleanup chain unwinds: inherited Destroy is never called, the parent's resources leak, the destructor frame is left half-done and the caller (typically the RTL during stack unwind) sees an exception in a context where it usually swallows or escalates incorrectly. The detector walks `nkMethod` nodes whose `TypeRef` starts with `destructor` (and is not a class destructor, which has different semantics), then recursively visits the body with an `InHandler` flag. Each `nkRaise` encountered while the flag is False is reported. Maps to Sonar-50 rule #23.

```pascal
// BAD
destructor TFoo.Destroy;
begin
  FList.Free;
  if Bad then raise EInvalidOp.Create('oops');   // <- inherited never runs
  inherited;
end;

// GOOD
destructor TFoo.Destroy;
begin
  try
    FList.Free;
    if Bad then raise EInvalidOp.Create('oops');
  except
    Log('cleanup error');
  end;
  inherited;
end;
```

---
## SCA146
**Boolean parameter used as internal branching flag**

> A Boolean parameter whose value selects between two completely different code paths is a hidden Strategy - prefer two methods with descriptive names

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `api-design`, `readability`, `sonar50` |
| Detector | `uBooleanParam.pas` |

When a Boolean parameter's value flips the function between two unrelated behaviours (`SendMsg(s, True)` vs `SendMsg(s, False)`), the call site is opaque: the reader has to either remember the method's API or look it up to know what `True` means. Two methods with descriptive names (`SendErrorMessage` / `SendInfoMessage`) make the intent obvious at the call site without comments. The detector walks `nkMethod` nodes, scans `nkParam` children for Boolean (also LongBool/WordBool/ByteBool), and reports when at least one `nkIfStmt` in the body uses the parameter as a condition. Excluded: property setters (method names starting with `Set`), well-known VCL event-handler parameter names (`Handled`, `CanShow`). Pure pass-through (Bool just forwarded without internal branching) is not flagged. Maps to Sonar-50 rule #33. Severity Hint - this is a refactoring suggestion, not a bug.

```pascal
// BAD
procedure SendNotification(const Msg: string; IsError: Boolean);
begin
  if IsError then Notify(Msg, clRed) else Notify(Msg, clBlack);
end;
// Caller: SendNotification(s, True);     // True = ???

// GOOD
procedure SendErrorNotification(const Msg: string);
begin Notify(Msg, clRed); end;

procedure SendInfoNotification(const Msg: string);
begin Notify(Msg, clBlack); end;
// Caller: SendErrorNotification(s);
```

---
## SCA147
**Private method has no caller in the unit**

> A private method that is never referenced from any other method in the same unit is dead code - delete it or wire it up

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dead-code`, `maintainability`, `sonar50` |
| Detector | `uUnusedPrivateMethod.pas` |

Private methods can only be called from inside the same unit (Delphi-classic) or class (strict private). If no other method references them, they cannot be called at all - they are dead code, often the residue of an incomplete refactoring. The detector walks `nkClass` nodes, finds `nkVisibilitySection` children with name `private` or `strict private`, collects their `nkMethod` names, and then text-scans the (string-and-comment-stripped) file body for word-boundary matches. Two matches per method are tolerated (declaration line + implementation header); more indicate at least one call. Limitations: RTTI-driven invocations via `TypeInfo` / published-by-attribute / interface dispatch are not detected; use `// noinspection UnusedPrivateMethod` to suppress in those cases. Maps to Sonar-50 rule #37.

```pascal
// BAD
TFoo = class
private
  procedure HelperA;            // <- never called
public
  procedure DoStuff;
end;

// GOOD
TFoo = class
public
  procedure DoStuff;
end;
// or call HelperA from DoStuff to make the dependency explicit
```

---
## SCA148
**Instance method never accesses Self - could be a class method**

> A method that uses only its parameters (no Self, no instance fields, no virtual chain) is functionally a class method - mark it as such to express the stateless intent

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `oop`, `refactoring`, `sonar50` |
| Detector | `uCanBeClassMethod.pas` |

When an instance method never touches `Self`, an instance field, or `inherited`, the implicit `Self` parameter is wasted - the method is effectively stateless. Declaring it `class function ... static` saves a pointer-pass, makes the stateless intent explicit, and allows callers to invoke it without an instance (`TMath.Add(1, 2)` instead of `MyMath.Add(1, 2)`). The detector walks `nkMethod` nodes that belong to a class (qualified name like `TFoo.Bar`), skips already-class methods (`;class` in TypeRef), polymorphic ones (`;virtual`/`;override`/`;dynamic`/`;abstract`), constructors and destructors, then recursively checks for any identifier named `self`, any `inherited`, or any `F<UppercaseLetter>` field reference. None of those -> finding. Limitations: implicit property access without `Self.` prefix is not detected as instance access, so calls like `Bar := ...` for a property could FP. Maps to Sonar-50 rule #50.

```pascal
// BAD
function TMath.Add(A, B: Integer): Integer;
begin
  Result := A + B;          // only uses params, no Self
end;

// GOOD
class function TMath.Add(A, B: Integer): Integer;
begin
  Result := A + B;
end;
// Caller: TMath.Add(1, 2)   // no instance needed
```

---
## SCA149
**Method shadows a virtual parent method without `override`**

> A method redeclared in a subclass with the same name as a virtual/dynamic parent method, but without the `override` directive, breaks polymorphism - the compiler issues warning W1010

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `polymorphism`, `oop`, `compiler-warning`, `sonar50` |
| Detector | `uMissingOverride.pas` |

Without `override`, the subclass method is treated as a new method by the compiler. Polymorphic dispatch via the parent's vtable still calls the parent's implementation - `Base := Derived; Base.DoWork` runs `TBase.DoWork`, not `TDerived.DoWork`. The compiler warns (W1010), but many codebases suppress that hint. The detector walks `nkClass` nodes, identifies their direct parent in the same unit, collects parent methods with `;virtual` or `;dynamic` in `TypeRef`, and then checks each subclass method whose unqualified name matches a polymorphic parent name: missing `;override` AND missing `;reintroduce` -> finding. Limitations: within-unit only (cross-unit parents like `TForm`/`TStrings` not seen); only direct parent (multi-level chains check just one step). Maps to Sonar-50 rule #21.

```pascal
// BAD
TBase = class
  procedure DoWork; virtual;
end;

TDerived = class(TBase)
  procedure DoWork;          // <- shadows TBase.DoWork (W1010)
end;

// GOOD
TDerived = class(TBase)
  procedure DoWork; override;
end;
```

---
## SCA150
**Boolean comparison is always true / always false**

> Comparisons like `Length(s) >= 0` are tautologies - the Length result is never negative, so the condition can never be false

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `control-flow`, `dead-code`, `sonar50` |
| Detector | `uBoolAlwaysTrue.pas` |

Tautological boolean comparisons usually indicate a typo (`< 0` instead of `= 0`, `>= 1` instead of `> 0`) or copy-paste residue from a prior version of the code. The compiler does not warn because the operand type allows the value range syntactically. This narrow detector strips strings + comments, then matches two patterns lexically: `Length(...) >= 0` / `Length(...) < 0` and the mirrored `0 <= Length(...)` / `0 > Length(...)`. Limitations: Cardinal/UInt variables (`<UInt> >= 0` is also always-true) cannot be detected without type inference; complex expressions like `Length(s) - 1 < 0` are not matched. Maps to Sonar-50 rule #18 (narrow form).

```pascal
// BAD
if Length(s) >= 0 then DoStuff;   // <- always True
if Length(s) < 0 then DoOther;    // <- always False

// GOOD
if Length(s) > 0 then DoStuff;    // non-empty check
if Length(s) = 0 then DoOther;    // empty check
```

---
## SCA151
**Function always returns the same literal**

> All paths in the function assign the same literal value to Result - the conditional logic adds no behavioural difference, replace the function with a constant

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dead-code`, `refactoring`, `sonar50` |
| Detector | `uConstantReturn.pas` |

When every assignment to `Result` (or to the function name in classic Pascal style) is the same literal, the function returns that literal regardless of inputs. The conditional structure is dead - either an incomplete refactor (one branch was never updated) or branches that should have produced different values do not. The detector walks `nkMethod` whose `TypeRef` declares a return type, collects `nkAssign` nodes whose LHS equals `result` or the unqualified function name, extracts the RHS literal (number, string literal, True/False/nil), and reports when at least two such assigns share the exact same literal and no non-literal assign exists. Maps to Sonar-50 rule #43.

```pascal
// BAD
function GetTimeout: Integer;
begin
  if SlowMode then
    Result := 30
  else
    Result := 30;       // <- always 30
end;

// GOOD
const DEFAULT_TIMEOUT = 30;

function GetTimeout: Integer;
begin
  Result := DEFAULT_TIMEOUT;
end;
```

---
## SCA152
**User-visible string assigned as literal**

> Caption/Hint/Text assignments and ShowMessage/MessageDlg calls with literal text bypass resourcestring / i18n - the string cannot be translated or replaced for localisation

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `i18n`, `localization`, `sonar50` |
| Detector | `uHardcodedString.pas` |

Hardcoded user-visible text makes the application untranslatable without source modifications. The detector lexically scans each source line for two narrow patterns: `<ident>.Caption|Hint|Text := '<text>'` and `ShowMessage|MessageDlg('<text>'`. The captured text is reported only when it (a) is at least 2 characters, (b) contains at least one letter (rules out single-char separators like `'-'`, `'.'`, `':'`, and numeric literals), and (c) does not look like a resource key (uppercase + underscores only, or starts with `$`). Line-comments (`//`) are skipped. Limitations: matches on non-UI classes with a Caption/Hint/Text property (e.g. internal helpers) can FP - in that case use the line-suppress marker `// noinspection HardcodedString`. Maps to Sonar-50 rule #46 (narrow form, UI-only).

```pascal
// BAD
Form1.Caption := 'Mein Programm';
Button1.Hint  := 'Klick mich';
ShowMessage('Daten gespeichert');

// GOOD
resourcestring
  SAppCaption = 'Mein Programm';
  SBtnHint    = 'Klick mich';
  SSavedMsg   = 'Daten gespeichert';

Form1.Caption := SAppCaption;
Button1.Hint  := SBtnHint;
ShowMessage(SSavedMsg);
```

---
## SCA153
**Lock acquired without try/finally release**

> <ident>.Lock / EnterCriticalSection / TMonitor.Enter followed by a matching UnLock/Leave/Exit in the same routine without an enclosing try/finally - exception path leaks the lock and deadlocks the next caller

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `concurrency`, `mormot`, `exception-safety`, `sonar50` |
| Detector | `uUnpairedLock.pas` |

Scans each source line lexically (comments + strings stripped) for the acquire token `<ident>.Lock`, `Acquire`, `EnterCriticalSection`, or bare `EnterCriticalSection(...)`. A 200-character lookahead window then searches for the matching release token (`UnLock`, `LeaveCriticalSection`, `Release`). When BOTH are present in the window but no `try` keyword precedes the release, the pair is reported - acquiring a lock and then raising before the release causes a deadlock for every subsequent waiter. mORMot-tuned: matches TSynLocker, TRWLock, TLightLock, and the bare-Windows EnterCriticalSection/LeaveCriticalSection pair. Patterns where the release is missing entirely are skipped (likely a lock-helper RAII style with the release in a destructor).

```pascal
// BAD
FLocker.Lock;
DoStuff;
FLocker.UnLock;

// GOOD
FLocker.Lock;
try
  DoStuff;
finally
  FLocker.UnLock;
end;
```

---
## SCA154
**Move/FillChar with SizeOf(pointer-type)**

> Move, FillChar, CopyMemory, or ZeroMemory called with SizeOf(PXxx) where PXxx is a pointer type - copies only 4/8 bytes (the pointer size) instead of the intended buffer

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `memory`, `pointer`, `mormot`, `sonar50` |
| Detector | `uMoveSizeOfPointer.pas` |

Lexical scan for `Move|FillChar|CopyMemory|ZeroMemory(...SizeOf(<Name>)...)` where <Name> begins with `P` followed by an uppercase letter (Delphi P-prefix convention for pointer types: PByte, PInteger, PCardinal, PChar, PSomeRecord, ...). On 64-bit, SizeOf(PXxx) returns 8 regardless of the pointed-to type; on 32-bit it returns 4. The author almost always meant SizeOf(Xxx) or Length(Buf) - the truncated copy silently leaves the rest of the buffer untouched (FillChar) or only partially copies the source (Move). Common mORMot pitfall: SizeOf(PByte) instead of explicit byte count when copying into a fixed array. Whitelist excludes SizeOf(TXxx) / SizeOf(Integer) / SizeOf(Variable) - only P-prefix-and-uppercase triggers.

```pascal
// BAD
var Buf: array[0..255] of Byte; P: PByte;
Move(Src^, P^, SizeOf(PByte));        // copies 8 bytes (pointer), not the buffer
FillChar(P^, SizeOf(PInteger), 0);    // zeroes 8 bytes, not the integer

// GOOD
Move(Src^, P^, SizeOf(Byte) * Count);  // explicit element count
FillChar(V, SizeOf(V), 0);             // matches the variable's size
```

---
## SCA155
**with statement on multiple targets**

> `with A, B do` (two or more comma-separated receivers) makes member lookup ambiguous - adding a method to either A or B silently changes the meaning of the body

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `clarity`, `with-statement`, `sonar50` |
| Detector | `uWithMultipleTargets.pas` |

Regex match `\bwith\s+<id>,\s*<id>\s*do\b` across the whole file (multiline / comments stripped). One target alone is already a code-smell (covered by fkWithStatement); two or more turn the body into a maintenance trap: a new method added to A or B can silently override what used to dispatch to the other. The compiler picks the closest match and never warns. Renames via the IDE refactor skip these references because the receiver is not named at the call site. mORMot-tuned: matches up to 200 characters per target name to tolerate fully-qualified names like `Owner.SubObject.Component`. Fix: split into separate `with` blocks, or - better - drop `with` entirely and qualify each member explicitly.

```pascal
// BAD
with Form1, List1 do
  DoStuff;     // From Form1 or List1?

// GOOD
Form1.DoStuff;
List1.Sort;
```

---
## SCA156
**GetMem / AllocMem without try/finally**

> GetMem / AllocMem / ReallocMem followed by a matching FreeMem in the same routine without an enclosing try/finally - exception path leaks the buffer permanently

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `memory-leak`, `exception-safety`, `mormot`, `sonar50` |
| Detector | `uGetMemWithoutFreeMem.pas` |

Lexical scan (comments + strings stripped) for `GetMem(...)`, `AllocMem(...)`, or `ReallocMem(...)`. A 400-character lookahead window searches for the matching `FreeMem`. When both are present in the window but no `try` keyword precedes the FreeMem, the pair is reported - any exception between allocation and release leaks the raw heap buffer. mORMot-tuned: matches the ~20 GetMem occurrences in mORMot core/ that implement high-performance buffer manipulation, where every missing try/finally is a production leak. Patterns where FreeMem is missing entirely are skipped (likely ownership-transfer to caller, or custom allocator).

```pascal
// BAD
GetMem(P, 1024);
DoStuff(P);
FreeMem(P);

// GOOD
GetMem(P, 1024);
try
  DoStuff(P);
finally
  FreeMem(P);
end;
```

---
## SCA157
**SetLength(arr, Length(arr) + N) inside a loop**

> Dynamic-array grow-by-one (or grow-by-N) inside a for/while/repeat loop - quadratic reallocation cost; grow once before the loop or use a block-grow strategy

| Field | Value |
|---|---|
| Severity | Warning | Type | Code Smell |
| Tags | `performance`, `dynamic-array`, `mormot`, `sonar50` |
| Detector | `uSetLengthAppendInLoop.pas` |

Lexical scan for any `for|while|repeat` keyword followed within 600 characters by `SetLength(<id>, Length(<id>) + ...)` where the two `<id>` names are identical (the array grows itself). Each reallocation copies the existing contents - n iterations cost n*(n+1)/2 element-copies instead of n. At 10_000 items this is ~5000x slower than a one-shot SetLength. Common mORMot performance trap when user code accumulates results without knowing the final size. Only the first grow per loop is reported to avoid spam. `SetLength(A, Length(B)+1)` (different arrays) is NOT flagged - that pattern is rare and usually intentional.

```pascal
// BAD
for i := 0 to Source.Count - 1 do
begin
  SetLength(Dest, Length(Dest) + 1);  // O(n*n)
  Dest[High(Dest)] := Source[i];
end;

// GOOD
SetLength(Dest, Source.Count);
for i := 0 to Source.Count - 1 do
  Dest[i] := Source[i];
```

---
## SCA158
**PChar(s) +/- offset without empty-check**

> `PChar(s) + n`, `PAnsiChar(s) + n`, or `PWideChar(s) + n` without a prior empty-check on `s` - PChar('') optimizes to NIL, so arithmetic on the result is a latent Access Violation

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `pointer`, `string`, `nil-deref`, `mormot`, `sonar50` |
| Detector | `uPointerArithmeticOnString.pas` |

Lexical scan for `PChar|PAnsiChar|PWideChar(<id>) [+-] <offset>`. A 200-character backward window checks for guard patterns: `<id> <> ''`, `<id> = ''`, `Length(<id>) ...`, or `Assigned(<id>)`. When no guard is found, the arithmetic is flagged. The Delphi compiler optimizes `PChar('')` to NIL (not a pointer to a static #0 character), so `PChar(s) + 5` evaluates to address $00000005 when `s` is empty - accessing it triggers Access Violation. mORMot internals consistently guard with explicit empty-checks; user code that copies the PChar arithmetic idiom often skips the guard. Limitations: backward window is 200 chars (long-range checks are missed); arithmetic via `Inc(p, ...)` on a previously-assigned PChar variable is NOT detected (would need flow analysis).

```pascal
// BAD
p := PChar(s) + 5;       // if s='' then PChar(s)=nil -> AV at $00000005

// GOOD
if s <> '' then
  p := PChar(s) + 5;
```

---
## SCA159
**Typed exception handler with empty body**

> `on E: SomeException do ;` (or `on E: ... do begin end;`) silently swallows a specific exception class - worse than a bare `except end` because the typed annotation looks intentional

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `exception-handling`, `silent-failure`, `mormot`, `sonar50` |
| Detector | `uEmptyOnHandler.pas` |

Lexical scan for `on [E:] <ExceptionType> do (;|begin end)`. The typed `on E:` form gives the impression of considered handling - a reader assumes the developer thought about this specific exception. An empty body means the failure is invisible in production: no log, no UI feedback, no telemetry. Common mORMot review finding in cleanup code where 'this can be ignored' is not documented. The bare `except end` form is already caught by SCA-001 (EmptyExcept); this rule covers the typed-handler variant.

```pascal
// BAD
try DoStuff; except
  on E: EDatabaseError do ;
end;

// GOOD
try DoStuff; except
  on E: EDatabaseError do
  begin
    Logger.Error(E.Message);
    raise;
  end;
end;
```

---
## SCA160
**String cast from raw pointer**

> `string(P)` / `AnsiString(P)` / `UTF8String(P)` / `RawByteString(P)` cast from a P-prefixed pointer assumes a null-terminator that may not exist - heap overread

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `string`, `pointer`, `heap-overread`, `mormot`, `sonar50` |
| Detector | `uStringFromPointer.pas` |

Lexical scan for `(string|RawByteString|AnsiString|UTF8String|WideString)(<id>)` where `<id>` starts with `P` followed by an uppercase letter (Delphi P-prefix convention for pointer types: PByte, PChar, PSomeRecord, ...). Delphi treats the cast as null-terminated and reads memory until the next #0 - on a buffer without a terminator this walks past the heap-block boundary, causing silent overread and occasional AV. mORMot internals use this pattern with controlled null-termination; user code copying the idiom often skips the terminator guarantee. Use `SetString(s, PChar(Buf), Len)` with explicit length instead. False-positive filter: only P-prefix+uppercase identifiers trigger - `string(IntegerVar)` (Integer-to-String) is not flagged.

```pascal
// BAD
s := string(Buf);    // PByte cast assumes null-terminator

// GOOD
SetString(s, PChar(Buf), Len);   // explicit length
```

---
## SCA161
**Pointer subtraction via 32-bit cast**

> `Cardinal(P1) - Cardinal(P2)` (or Integer / LongWord / LongInt variants) truncates the upper 32 bits of a 64-bit pointer on Win64 - difference is intermittently wrong

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `pointer`, `win64`, `truncation`, `mormot`, `sonar50` |
| Detector | `uPointerSubtraction.pas` |

Lexical scan for `(Cardinal|LongWord|Integer|LongInt)(<id>) - (Cardinal|...)(<id>)` - two 32-bit casts joined by minus. On Win64 a Pointer is 64-bit while Cardinal/Integer/LongWord/LongInt are 32-bit, so the cast drops the upper four bytes of the address. The resulting difference is wrong whenever the allocator hands out high addresses - the code works on Win32 and breaks intermittently on Win64. Common porting bug from Delphi-7 / Delphi-2007 examples that pre-date Win64. Fix: use `PtrUInt(P1) - PtrUInt(P2)` or `NativeInt(P1) - NativeInt(P2)` - pointer-width integer types that match the platform pointer size.

```pascal
// BAD
Diff := Cardinal(P1) - Cardinal(P2);   // upper 32 bits lost on Win64

// GOOD
Diff := PtrUInt(P1) - PtrUInt(P2);     // pointer-wide cast
```

---
## SCA162
**Use of weak / deprecated cryptographic algorithm**

> Algorithm name ('MD5', 'SHA1', 'DES', 'RC4', 'TLS1.0', 'SSLv3') or wrapper class (THashMD5, TIdHashSHA1, ...) referenced - vulnerable to collision / known-plaintext attacks

| Field | Value |
|---|---|
| Severity | Warning | Type | Vulnerability |
| Tags | `crypto`, `security`, `compliance` |
| CWE | [CWE-327](https://cwe.mitre.org/data/definitions/327.html), [CWE-328](https://cwe.mitre.org/data/definitions/328.html) |
| OWASP | A02:2021-Cryptographic Failures |
| Detector | `uInsecureCryptoAlgorithm.pas` |

MD5 has practical collisions since 2004 (Wang et al.), SHA1 since 2017 (SHAttered chosen-prefix). DES is 56-bit and brute-forceable, 3DES has the Sweet32 CBC collision (CVE-2016-2183). RC4 has documented statistical biases and is prohibited by RFC 7465. TLS 1.0 / 1.1 are RFC 8996 deprecated (BEAST, POODLE, Lucky13). SSLv3 was killed by POODLE (CVE-2014-3566). The detector matches algorithm names with word boundaries inside string literals/identifiers AND a set of well-known wrapper class names (substring match). Fix: switch to SHA-256/SHA-3 for hashing, AES-GCM / AES-CCM for symmetric encryption, TLS 1.2 minimum (1.3 preferred).

```pascal
// BAD
algo := 'MD5';
Hash := THashMD5.GetHashString(Input);

// GOOD
algo := 'SHA256';
Hash := THashSHA2.GetHashString(Input);
```

---
## SCA163
**Shell API called with string concatenation in argument**

> ShellExecute / CreateProcess / WinExec with `+` in the arguments - if any operand is user-controlled it becomes a command-injection vector

| Field | Value |
|---|---|
| Severity | **Error** | Type | Vulnerability |
| Tags | `injection`, `security`, `shell` |
| CWE | [CWE-78](https://cwe.mitre.org/data/definitions/78.html) |
| OWASP | A03:2021-Injection |
| Detector | `uCommandInjection.pas` |

Building the command string via concatenation (`PChar('cmd /c ' + UserInput)`) allows the attacker to append additional commands when the input is not strictly validated. This detector walks the AST and flags any nkCall whose method name (qualifier-stripped) is one of the known shell entry points AND whose argument list contains a `+` operator OUTSIDE any string literal. Because we cannot statically tell whether an operand is tainted, the finding is emitted with Confidence = Low; it surfaces in the UI only when the minimum-confidence threshold is set to 'low'. Fix: pass arguments via the dedicated parameter array (CreateProcess) or escape/validate before concatenation, prefer ShellExecuteEx with a structured SHELLEXECUTEINFO.

```pascal
// BAD
ShellExecute(0, 'open', PChar('cmd /c ' + UserInput), nil, nil, SW_SHOW);

// GOOD
// Validate UserInput against a strict whitelist, then:
ShellExecute(0, 'open', 'cmd.exe', PChar('/c safe_command'), nil, SW_SHOW);
```

---
## SCA164
**Top-level routine never called**

> Standalone procedure/function in the implementation section is never called from anywhere in the unit and is not exported via the interface section - dead code

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dead-code`, `maintainability`, `sonardelphi` |
| Detector | `uUnusedRoutine.pas` |

Fills the gap between SCA147 (UnusedPrivateMethod - only class private methods) and the visibility-check family SCA148+ (only class public members). Detects top-level (non-class) routines whose name does not appear as a caller anywhere in the same unit, excluding self-references (a recursive routine that only calls itself is still flagged - mirrors SonarDelphi UnusedRoutineCheck behaviour). False-positive guards: constructors and destructors (not directly callable as a procedure), the `override`/`virtual; abstract`/`message`/`dynamic` directives (cross-class or system dispatch), the IDE-bootstrap `Register` procedure, the enumerator trio (`MoveNext`/`GetEnumerator`/`Current` - invoked implicitly by `for-in`), and any routine forward-declared in the unit's interface section (potential cross-unit consumer). Scope is single-file - cross-unit callers of interface-section routines are not tracked in this MVP, so those are intentionally skipped. Suppress with `// noinspection UnusedRoutine` when the routine is intentionally kept (RTTI-driven invocation, attribute-consumed, plugin-loaded). Maps to SonarDelphi UnusedRoutineCheck.

```pascal
// BAD
implementation
procedure InternalHelper;     // never called
begin
  WriteLn('hi');
end;
end.

// GOOD
implementation
// remove InternalHelper, or call it from somewhere,
// or move it to interface if it should be exported
```

---
## SCA165
**Unused noinspection marker**

> A `// noinspection X` marker does not suppress any finding at its target line - either the detector improved (suppression no longer needed) or the suppression target was wrong

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `suppression`, `maintainability`, `hygiene` |
| Detector | `uSuppression.pas` |

The suppression filter (uSuppression) records every `// noinspection KindName` comment and the next code line it targets. After all detectors finish, the filter checks which markers actually suppressed a finding. Markers that never fired are reported as fkUnusedSuppression at the marker line - the user should remove the marker (detector evolution made it obsolete) or check whether the target kind name was wrong. False-negative-resistant: only markers with a clear non-comment target line are considered (markers at EOF or in pure doc-comment blocks are ignored). Profile-aware: in the default profile this hint shows up; users who want suppression-hygiene reports without detector noise can run with --profile selftest-quiet.

```pascal
// BAD
// noinspection MemoryLeak
WriteLn('hello');   // no leak here - suppression never fires

// GOOD
// (Marker entfernt - das Tool flaggt diese Zeile nicht mehr.)
WriteLn('hello');
```

---
## SCA166
**Uninitialised local variable**

> Local variable read before being assigned on every code path through the method

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `reliability`, `memory-safety`, `uninit` |
| Config | `[Detectors] UninitVarEnabled` |
| Detector | `uUninitVar.pas` |

Local variables of non-managed types (Integer, Boolean, Pointer, record, class instance) start with undefined contents. Reading them before assignment yields garbage values or an access violation - a classic crash bug. The detector walks each method's statements in source order, tracks first-write vs first-read per local variable, and flags reads that precede any write. A conservative branch model treats writes inside if/case/try-blocks as 'conditional' (fcMedium confidence; the FP rate vs full path-sensitivity is the documented trade-off, see Konzept_SCA166_UninitVar.md §5.C). Known writers from the RTL (Read, ReadLn, FillChar, Move, ZeroMemory, Initialize, New, GetMem) are detected via allowlist; other var/out-parameter calls are treated pessimistically as Reads (false-negatives but no false-positives). Pascal's auto-initialised managed types (string, dynamic array, interface) are skipped unless opted-in via INI. Methods larger than configurable caps (200 local vars / 5000 statements, default) skip analysis to avoid pathological worst-case cost.

```pascal
// BAD
procedure Foo;
var L: TStringList;
begin
  if Cond then L := TStringList.Create;
  L.Add('x');   // L undefined if Cond was false -> AV
end;

// GOOD
procedure Foo;
var L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Add('x');
  finally
    L.Free;
  end;
end;
```

---
## SCA167
**Random call without prior Randomize**

> Random / RandomRange / RandomFrom used without Randomize - Seed=0 yields a deterministic sequence on every run

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `reliability`, `randomness`, `seed` |
| Config | `[Detectors] InsecureRandomEnabled` |
| Detector | `uInsecureRandom.pas` |

Delphi's Random function uses an internal seed that defaults to 0 at program start. Until Randomize is called once (typically at the start of program execution), Random returns the same sequence of values every time the program is launched. The detector walks the AST for all calls and skips the entire unit if any Randomize invocation is present anywhere. Otherwise every Random / RandomRange / RandomFrom call is flagged. Note: Randomize calls in other units (e.g. in a use'd unit's initialization block) are not detected; suppress with `// noinspection InsecureRandom` if applicable. For cryptographic use cases (token generation, salts, password reset codes) Random is unsuitable regardless of Randomize - use TBytes from a CSPRNG (e.g. CryptGenRandom on Windows, /dev/urandom on POSIX).

```pascal
// BAD
procedure DealCards;
var i: Integer;
begin
  for i := 1 to 5 do
    Players[i].Card := Random(52);
end;

// GOOD
procedure DealCards;
var i: Integer;
begin
  Randomize;   // once, at startup
  for i := 1 to 5 do
    Players[i].Card := Random(52);
end;
```

---
## SCA168
**case statement without else branch**

> case statement has no else branch - unhandled values fall through silently

| Field | Value |
|---|---|
| Severity | Hint | Type | CodeSmell |
| Tags | `control-flow`, `default-case` |
| Config | `[Detectors] DefaultCaseInCaseStatementEnabled` |
| Detector | `uDefaultCaseInCaseStatement.pas` |

A case statement without an else branch silently ignores all values that are not explicitly listed. When the case expression takes one of these unhandled values, no action is taken and no error is raised, which can mask logic bugs (especially when new enum values are added later and the case statements are not updated). Add `else ;` for an intentional no-op (which documents the decision) or a default handler that raises an exception / logs / asserts.

```pascal
// BAD
case Status of
  stNew    : DoNew;
  stActive : DoActive;
end;

// GOOD
case Status of
  stNew    : DoNew;
  stActive : DoActive;
else
  raise EProgrammerError.Create('Unhandled status');
end;
```

---
## SCA169
**Assert argument contains a function call with side effects**

> Assert(SomeCall) - the call disappears in Release builds and its side effect is silently lost

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `reliability`, `assert`, `side-effect` |
| Config | `[Detectors] AssertWithSideEffectEnabled` |
| Detector | `uAssertWithSideEffect.pas` |

The Delphi compiler removes Assert calls entirely from Release builds (unless DCC_Assertions is on). If the asserted expression contains a function call with side effects (allocation, state mutation, I/O, counter increment), the side effect disappears too - the Release-only behavior diverges from Debug. The detector flags Assert calls whose argument contains a function-call pattern, after excluding a whitelist of known-pure RTL helpers (Length, Assigned, SizeOf, IntToStr, ...). Move the call out of the Assert and assert on the result instead.

```pascal
// BAD
Assert(InitializeSubsystem);   // Release build skips Init entirely

// GOOD
var Ok := InitializeSubsystem;
Assert(Ok, 'subsystem init failed');
```

---
## SCA170
**string parameter without const modifier**

> string parameter declared without const - causes refcount bump on every call

| Field | Value |
|---|---|
| Severity | Hint | Type | CodeSmell |
| Tags | `performance`, `string`, `refcount` |
| Config | `[Detectors] ConstStringParameterEnabled` |
| Detector | `uConstStringParameter.pas` |

Delphi increments the string's reference count on every call when the parameter is declared without `const`. With `const`, the compiler passes a pure reference and skips the refcount roundtrip. The compiler also forbids assignment to a `const` parameter, which makes the no-mutation contract explicit. For non-mutating string parameters (the overwhelming majority), prefer `const`. The detector flags parameters whose type is `string`/`AnsiString`/`UnicodeString`/`WideString`/`RawByteString`/`ShortString` without `const`/`var`/`out`.

```pascal
// BAD
function Hash(s: string): Integer;

// GOOD
function Hash(const s: string): Integer;
```

---
## SCA171
**Compiler switch OFF without matching ON in same file**

> {$WARNINGS OFF} (or HINTS/RANGECHECKS/...) without a closing ON - leaks into following units

| Field | Value |
|---|---|
| Severity | Warning | Type | CodeSmell |
| Tags | `compiler-directive`, `scope`, `switch` |
| Config | `[Detectors] CompilerDirectiveScopeEnabled` |
| Detector | `uCompilerDirectiveScope.pas` |

Delphi compiler-state directives like {$WARNINGS OFF}, {$HINTS OFF}, {$RANGECHECKS OFF}, {$BOOLEVAL OFF}, {$OVERFLOWCHECKS OFF} change the compiler state for everything compiled after them. If the OFF is not paired with a closing ON in the same file, the switch leaks into all subsequent compilation units in the same build, suppressing warnings/hints/checks far outside the intended scope. The detector counts OFF and ON per directive name in the file and reports any directive whose OFF outnumbers ON at end-of-file.

```pascal
// BAD
{$WARNINGS OFF}
procedure Foo;
begin
end;

// GOOD
{$WARNINGS OFF}
procedure Foo;
begin
end;
{$WARNINGS ON}
```

---
## SCA172
**Boolean property without Is / Has / Can / Should prefix**

> Boolean property name reads as a noun - prefer a verb prefix that scans as a question

| Field | Value |
|---|---|
| Severity | Hint | Type | CodeSmell |
| Tags | `naming`, `convention`, `boolean` |
| Config | `[Detectors] BooleanPropertyNamingEnabled` |
| Detector | `uBooleanPropertyNaming.pas` |

A Boolean property named like a noun reads ambiguously at call sites (`if X.Active then` vs. `if X.IsActive then`). Prefer a verb-style prefix (`Is`/`Has`/`Can`/`Should`/`Will`) which makes the call site read naturally as a question. The detector flags Boolean properties whose name does not start with one of these prefixes, with a built-in whitelist of established VCL conventions (Enabled, Visible, Active, Checked, Modified, ReadOnly, Selected, Focused, Loaded, Modified, Dirty, ...).

```pascal
// BAD
property Ready: Boolean;

// GOOD
property IsReady: Boolean;
```

---
## SCA173
**Variant in performance-sensitive method (contains a loop)**

> Variant variable inside a method that contains a loop - each Variant operation pays a 10-100x COM dispatch tax

| Field | Value |
|---|---|
| Severity | Hint | Type | CodeSmell |
| Tags | `performance`, `variant`, `com` |
| Config | `[Detectors] VariantTypeMisuseEnabled` |
| Detector | `uVariantTypeMisuse.pas` |

Variant operations route through the COM VarType dispatcher (VarAdd, VarCmp, VarCast, ...) which adds a typing-system roundtrip on every read, write, comparison and conversion. Inside a hot loop this multiplies the cost by the iteration count and can dominate the method's runtime. The detector flags every Variant / OleVariant local variable and parameter in methods that contain at least one for/while/repeat loop. Accepted use cases (COM/OLE bridges, JSON-Variant adapters, Excel automation) are reachable via suppression marker `// noinspection VariantTypeMisuse`.

```pascal
// BAD
procedure SumRows;
var v: Variant; i: Integer;
begin
  for i := 0 to N do v := v + Rows[i];
end;

// GOOD
procedure SumRows;
var s: Double; i: Integer;
begin
  s := 0;
  for i := 0 to N do s := s + Rows[i];
end;
```

---
## SCA174
**TList<T> filled with T.Create - items leak when list is freed**

> TList<TFoo>.Create + Add(TFoo.Create) - the list does not own its items, every TFoo instance leaks

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `memory-safety`, `leak`, `container` |
| Config | `[Detectors] TObjectListWithoutOwnershipEnabled` |
| Detector | `uTObjectListWithoutOwnership.pas` |

TList<T> is a typed container that does NOT own its items - freeing the list does not free the items it holds. When the items are class instances allocated with .Create, they leak on every list-free unless the caller manually iterates and frees each one. The correct container is TObjectList<T> from Generics.Collections, which has OwnsObjects=True by default and frees its items on destruction. The detector walks each method, collects all `TList<T>.Create` assignments (where T is a class-looking identifier), then looks for `<varname>.Add(<T>.Create)` patterns in the same method. Cross-method ownership (Add in a different method than Create) is not tracked.

```pascal
// BAD
L := TList<TFoo>.Create;
L.Add(TFoo.Create);
L.Free; // TFoo instance leaks

// GOOD
L := TObjectList<TFoo>.Create; // OwnsObjects=True default
L.Add(TFoo.Create);
L.Free; // item freed
```

---
## SCA175
**Anonymous method captures for-loop variable by reference**

> Anonymous method inside `for i := ... do` references i - all closures see the same final value

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `concurrency`, `closure`, `loop`, `capture` |
| Config | `[Detectors] AnonMethodCaptureLoopVarEnabled` |
| Detector | `uAnonMethodCaptureLoopVar.pas` |

Delphi captures variables by reference in anonymous methods. When the anonymous method is created inside a for-loop and references the loop variable, every closure shares the same reference - by the time the closures run, the loop variable has reached its terminal value and all of them observe that final value. The classic symptom is N parallel threads created in a loop all logging the final iteration number instead of 0..N-1. The detector walks for-statements, extracts the loop variable name (classic `for i :=` or inline `for var i :=`) and scans nkCall / nkAssign descendants for the combination of an `procedure`-keyword (anonymous method start) and a reference to the loop variable. Fix: copy the loop variable to a local immediately before the anonymous method body.

```pascal
// BAD
for i := 0 to 9 do
  TThread.CreateAnonymousThread(procedure
  begin WriteLn(i); end).Start;

// GOOD
for i := 0 to 9 do
begin
  var Captured := i;
  TThread.CreateAnonymousThread(procedure
  begin WriteLn(Captured); end).Start;
end;
```

---
## SCA176
**Method has high cognitive complexity (nested control flow)**

> Sonar-style cognitive-complexity exceeds 15 - nested if/for/while/case is hard to follow mentally

| Field | Value |
|---|---|
| Severity | Warning | Type | CodeSmell |
| Tags | `complexity`, `cognitive`, `maintainability` |
| Config | `[Detectors] CognitiveLimit` |
| Detector | `uCognitiveComplexity.pas` |

Cyclomatic complexity (SCA022) counts independent paths linearly - ten flat if-statements weigh the same as one triply-nested if. Cognitive complexity, introduced by Sonar in 2017, multiplies the cost of nesting: each control-flow construct adds 1 + nesting-depth. Three nested loops thus score 1+2+3=6 instead of 3. The detector walks each method with an explicit stack (stack-overflow-safe per Audit_jvcl_segfault) tracking current depth and the running sum. Boolean operators (and/or/xor) in if-conditions add +1 each. Threshold: 15 (Sonar default), configurable via INI [Detectors] CognitiveLimit.

```pascal
// BAD
procedure Foo;
begin
  if A then
    if B then
      while C do
        if D then ...
end;

// GOOD
procedure Foo;
begin
  if not A then Exit;
  if not B then Exit;
  while C do
    if D then ...
end;
```

---
## SCA177
**Thread variable accessed after FreeOnTerminate := True**

> After T.FreeOnTerminate := True, any subsequent T.Field/T.Method access risks Access-Violation if the thread has already self-destructed

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `concurrency`, `lifetime`, `thread` |
| Config | `[Detectors] ThreadFreeOnTerminateWithRefEnabled` |
| Detector | `uThreadFreeOnTerminateWithRef.pas` |

TThread.FreeOnTerminate := True transfers ownership of the thread instance to itself - the thread frees its own memory in its Execute-then-Destroy lifecycle. The caller MUST drop all references to it immediately (typically by setting the local variable to nil) because there is no synchronization between the caller's next statement and the thread's self-destruction. The detector walks each method, collects every `<var>.FreeOnTerminate := True` assignment with its source line, then finds any subsequent `<var>.<member>` access (call OR assign) in the same method. Per-method scope: cross-method references (Field-held thread accessed in another method) are not tracked.

```pascal
// BAD
T := TMyThread.Create(True);
T.FreeOnTerminate := True;
T.Start;
T.Resume;   // T may be freed

// GOOD
T := TMyThread.Create(True);
T.FreeOnTerminate := True;
T.Start;
T := nil;   // drop reference
```

---
## SCA178
**File-open API receives concatenated user input**

> File-open call (TFileStream.Create, AssignFile, ...) with a path expression that concatenates user input (Edit.Text, Request.Params, ...) - path-traversal risk

| Field | Value |
|---|---|
| Severity | **Error** | Type | Vulnerability |
| Tags | `security`, `owasp-a01`, `cwe-22`, `path-traversal` |
| Config | `[Detectors] PathTraversalEnabled` |
| Detector | `uPathTraversal.pas` |

Classical path-traversal vulnerability: user-controlled input flows into a file-system API. An attacker can submit `../../../etc/passwd` or similar to escape the intended directory and read/write arbitrary files. The detector flags expressions that contain both a file-open API token (TFileStream.Create, TFile.OpenRead/WriteText, AssignFile, FileOpen, FileCreate) AND a user-input source token (.Text, .Lines.Text, .Caption, .Value, Request.Params, Sender.Text, ParamStr) AND a `+` operator (string concatenation). The detector is heuristic - no taint tracking - so wrapped sanitizers (e.g. `Sanitize(edPath.Text)`) trigger false positives; suppress via marker if the sanitizer is trusted.

```pascal
// BAD
Stream := TFileStream.Create(BaseDir + edPath.Text, fmOpenRead);

// GOOD
var SafePath := TPath.Combine(BaseDir, TPath.GetFileName(edPath.Text));
Stream := TFileStream.Create(SafePath, fmOpenRead);
```

---
## SCA179
**DUnitX [Ignore] attribute without reason argument**

> [Ignore] (no string arg) skips the test silently - add a message explaining why the test is disabled

| Field | Value |
|---|---|
| Severity | Hint | Type | CodeSmell |
| Tags | `test`, `dunitx`, `documentation` |
| Config | `[Detectors] AttributeIgnoreWithoutReasonEnabled` |
| Detector | `uAttributeIgnoreWithoutReason.pas` |

DUnitX accepts [Ignore] both as a marker attribute and as [Ignore('reason')]. The marker form skips the test without surfacing WHY it was disabled - the test then drifts unmaintained, often forgotten. Always add a reason string referencing a ticket / external dependency / known limitation so the disable can be triaged.

```pascal
// BAD
[Ignore]
procedure SomeTest;

// GOOD
[Ignore('TBD ticket #1234 - flaky on CI')]
procedure SomeTest;
```

---
## SCA180
**Same attribute applied twice to one member**

> Two identical [X] attributes on the same member - copy-paste leftover, no effect

| Field | Value |
|---|---|
| Severity | Warning | Type | CodeSmell |
| Tags | `attribute`, `duplication` |
| Config | `[Detectors] AttributeDuplicateEnabled` |
| Detector | `uAttributeDuplicate.pas` |

Delphi's attribute model accepts repeated attributes (some, like [TestCase], are intentionally multi-applied with different args). Duplicates with IDENTICAL args are not — they are usually copy-paste leftovers from refactoring. The detector compares (attribute-name, argument-text) pairs and flags identical occurrences in the same attribute group (lines max. 2 apart). Multi-applied attributes with different args (different [TestCase('A','1')] / [TestCase('B','2')]) are correctly NOT flagged.

```pascal
// BAD
[Test]
[Test]
procedure Foo;

// GOOD
[Test]
procedure Foo;
```

---
## SCA181
**DUnitX [Category] without category-name string**

> [Category] (no arg) is a compile-time error in DUnitX - always pass a category name

| Field | Value |
|---|---|
| Severity | **Error** | Type | Bug |
| Tags | `test`, `dunitx`, `compile-error` |
| Config | `[Detectors] AttributeCategoryWithoutStringEnabled` |
| Detector | `uAttributeCategoryWithoutString.pas` |

DUnitX's [Category] attribute requires a string argument that is used to group tests for selective execution. Without the argument, the compiler raises a missing-parameter error. Always pass an explicit category name (e.g. 'Slow', 'CI-only', 'Integration').

```pascal
// BAD
[Category]
procedure Foo;

// GOOD
[Category('Slow')]
procedure Foo;
```

---
## SCA182
**[TestFixture] class without any [Test] method**

> Class is marked [TestFixture] but contains no [Test] methods - zombie fixture visible in TestInsight but executes nothing

| Field | Value |
|---|---|
| Severity | Warning | Type | CodeSmell |
| Tags | `test`, `dunitx`, `dead-code` |
| Config | `[Detectors] AttributeTestFixtureWithoutTestsEnabled` |
| Detector | `uAttributeTestFixtureWithoutTests.pas` |

DUnitX discovers test classes by scanning for [TestFixture] attributes. A fixture without any [Test] method appears in the test tree but contributes zero executable tests - typically a leftover from refactoring (tests deleted, fixture not). The detector walks file text with a simple state machine: enters fixture-window on [TestFixture] line, watches for [Test] inside, exits on the next top-level `end;`. If no [Test] was seen, the [TestFixture] line is flagged. [SetupFixture]-only fixtures (used to prepare shared state for other fixtures) are a known false-positive case - suppress with `// noinspection AttributeTestFixtureWithoutTests`.

```pascal
// BAD
[TestFixture]
TFooTests = class
  procedure Helper;
end;

// GOOD
[TestFixture]
TFooTests = class
  [Test] procedure DoesX;
end;
```

---
## SCA183
**Attribute with blank line before target member**

> Attribute line followed by a blank line - visually loose, often a refactoring leftover

| Field | Value |
|---|---|
| Severity | Hint | Type | CodeSmell |
| Tags | `attribute`, `readability` |
| Config | `[Detectors] AttributeMisalignmentEnabled` |
| Detector | `uAttributeMisalignment.pas` |

The Delphi compiler attaches an attribute to the syntactically next member regardless of intervening blank lines. Visually however, an attribute separated from its member by a blank line is easy to overlook - the reader may not realize the attribute applies to the member below. This is also a frequent symptom of refactoring where a member was moved/deleted but the attribute was left behind. The detector flags attribute lines whose next non-blank line is more than one line away.

```pascal
// BAD
[Test]

procedure Foo;

// GOOD
[Test]
procedure Foo;
```

---
## SCA184
**Unused DFM component**

> DFM component is never referenced in code, other units, or the DFM itself - possibly a refactoring leftover

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dfm`, `dead-code`, `maintainability` |
| Detector | `uDfmComponentUnused.pas` |

A component declared in the .dfm has no event binding, is not referenced by any other component's properties (DataSource, Action, ActiveControl, ...), is never used in the form's own Pascal code, and is not accessed from any other unit via the form global. It is most likely a leftover after refactoring that still allocates at runtime. Because the use-proof is name-based (no exact binding), this rule is emitted at low confidence and stays out of the default-confidence profile until validated on real-world code. Persistent field components (T*Field) and embedded frames / inherited components are skipped conservatively; the detector stays silent without a repo-wide cross-unit index.

```pascal
// BAD
object btnOld: TButton  // removed from code, left in the DFM
end

// GOOD
(remove the leftover component from the .dfm)
```

---
## SCA185
**UTF-8 source file without BOM**

> UTF-8 file without BOM + non-ASCII - compiler reads it as ANSI (mojibake)

| Field | Value |
|---|---|
| Severity | Warning | Type | Bug |
| Tags | `encoding`, `bom`, `portability` |
| Detector | `uSourceEncoding.pas` |

A source file saved as UTF-8 without a byte-order mark and containing non-ASCII characters is read by the Delphi compiler as ANSI (system code page, GetACP) - producing mojibake in string literals and comments at runtime, and the result is machine-dependent. Fix: save as UTF-8 with BOM, or compile the project with --codepage:65001.

```pascal
// BAD
// file saved as UTF-8 WITHOUT BOM, with non-ASCII text
ShowMessage('...non-ASCII...');  // compiler reads ANSI -> mojibake at runtime

// GOOD
// same file saved as UTF-8 WITH BOM (EF BB BF), or build --codepage:65001
ShowMessage('...non-ASCII...');
```

---
## SCA186
**Invalid UTF-8 sequence in source file**

> Malformed UTF-8 (overlong / surrogate / out-of-range) under a UTF-8 BOM

| Field | Value |
|---|---|
| Severity | **Error** | Type | File Error |
| Tags | `encoding`, `corruption` |
| Detector | `uSourceEncoding.pas` |

The file carries a UTF-8 BOM but contains byte sequences that are not valid RFC 3629 UTF-8 (overlong encodings, lone surrogates, or code points above U+10FFFF). The Delphi compiler silently substitutes U+FFFD, corrupting the affected characters. Re-encode the file as clean UTF-8.

```pascal
// BAD
(UTF-8 BOM present, but bytes contain an overlong or surrogate sequence)

// GOOD
(re-encode the file as valid UTF-8)
```

---
## SCA187
**NUL or control byte in source file**

> NUL / disallowed control byte - binary file or mis-detected encoding

| Field | Value |
|---|---|
| Severity | **Error** | Type | File Error |
| Tags | `encoding`, `corruption` |
| Detector | `uSourceEncoding.pas` |

The source file contains a NUL byte or a disallowed control character (below U+0020, excluding tab / newline / carriage-return / form-feed). This usually means the file is binary or has a mis-detected encoding (for example BOM-less UTF-16, where every other byte is 0x00). Inspect and re-encode the file.

```pascal
// BAD
(file contains 0x00 bytes - e.g. BOM-less UTF-16)

// GOOD
(save the file as UTF-8 with BOM)
```

---
## SCA188
**Bidirectional override control character (Trojan Source)**

> Bidi override/isolate control char - source reads differently than it compiles

| Field | Value |
|---|---|
| Severity | **Error** | Type | Vulnerability |
| Tags | `security`, `unicode`, `trojan-source` |
| CWE | [CWE-1007](https://cwe.mitre.org/data/definitions/1007.html) |
| Detector | `uSourceEncoding.pas` |

The file contains a Unicode bidirectional override or isolate control character (U+202A-202E, U+2066-2069, U+061C). These can make source code display differently to a human reviewer than it is compiled - the Trojan Source attack (CVE-2021-42574, CWE-1007). There is no legitimate use in Delphi source; remove the control character.

```pascal
// BAD
// a comment containing U+202E can visually reorder the code that follows

// GOOD
// no bidirectional control characters anywhere in source
```

---
## SCA189
**ANSI source file with non-ASCII content**

> 8-bit source (no BOM, not valid UTF-8) - code-page-dependent, non-portable

| Field | Value |
|---|---|
| Severity | Warning | Type | Code Smell |
| Tags | `encoding`, `portability` |
| Detector | `uSourceEncoding.pas` |

The file has no BOM, contains non-ASCII bytes, and is not valid UTF-8 - so it is genuinely 8-bit (ANSI) encoded. The Delphi compiler reads it in the system code page (GetACP), which makes the non-ASCII characters depend on the machine/locale and non-portable. Save the file as UTF-8 with BOM.

```pascal
// BAD
// file saved as Windows-1252 (ANSI) with non-ASCII text, no BOM

// GOOD
// save the file as UTF-8 with BOM (EF BB BF)
```

---
## SCA190
**UTF-16 source file**

> UTF-16 source - compiles, but unusual and text-tool-unfriendly

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `encoding`, `convention` |
| Detector | `uSourceEncoding.pas` |

The source file is UTF-16 (LE or BE). It compiles, but UTF-16 source is unusual and causes friction with text tooling (git diff, grep, external hooks, code review). The convention is UTF-8 with BOM.

```pascal
// BAD
(file saved as UTF-16 LE / BE)

// GOOD
(save the file as UTF-8 with BOM)
```

---
## SCA191
**UTF-32 / UCS-4 source file**

> UTF-32 source - Delphi compiler rejects it with fatal error F2438

| Field | Value |
|---|---|
| Severity | **Error** | Type | File Error |
| Tags | `encoding`, `build-breaker` |
| Detector | `uSourceEncoding.pas` |

The source file is UTF-32 / UCS-4 (detected via its byte-order mark). The Delphi compiler does not support this encoding and aborts with fatal error F2438 ("UCS-4 text encoding not supported. Convert to UCS-2 or UTF-8"). Convert the file to UTF-8 (with BOM) or UTF-16.

```pascal
// BAD
(file saved as UTF-32 LE / BE - will not compile, F2438)

// GOOD
(convert to UTF-8 with BOM)
```

---
## SCA192
**Invisible / zero-width character in source**

> Zero-width/invisible Unicode char - hidden-text / homoglyph abuse vector

| Field | Value |
|---|---|
| Severity | Warning | Type | Vulnerability |
| Tags | `security`, `unicode`, `trojan-source` |
| CWE | [CWE-1007](https://cwe.mitre.org/data/definitions/1007.html) |
| Detector | `uSourceEncoding.pas` |

The file contains an invisible or zero-width Unicode character (U+200B ZWSP, U+200C ZWNJ, U+200D ZWJ, U+2060 word-joiner, or a mid-file U+FEFF ZWNBSP). Such characters are almost never legitimate in source and can hide or alter identifiers and text - part of the Trojan Source / invisible-character family (CWE-1007). Note: U+200D can appear legitimately inside emoji string literals.

```pascal
// BAD
// an identifier or string with an embedded U+200B is not what it looks like

// GOOD
// no zero-width / invisible characters in source
```

---

## SCA193
**Non-ASCII character in identifier**

> Identifier contains a non-ASCII letter - homoglyph / confusable risk

| Field | Value |
|---|---|
| Severity | Warning | Type | Vulnerability |
| Tags | `security`, `unicode`, `trojan-source` |
| CWE | [CWE-1007](https://cwe.mitre.org/data/definitions/1007.html) |
| Detector | `uSourceEncoding.pas` |

An identifier (variable, type, routine, ...) contains a non-ASCII character. This is the homoglyph / confusable-identifier vector of the Trojan Source family (CVE-2021-42694, CWE-1007): a letter such as Cyrillic U+043E looks like Latin 'o' but is a different identifier, so two identifiers can look identical yet bind differently. A legitimate Unicode identifier is also possible, so review before changing; prefer ASCII identifiers for portability and to avoid confusion.

```pascal
// BAD
var Login: string;  // one letter is a Cyrillic homoglyph (U+043E), not Latin 'o'

// GOOD
var Login: string;  // all-ASCII identifier
```

---

## SCA194
**Source file not part of the project**

> A .pas/.dfm file lies in the project folder but is not referenced by the project (.dproj/.groupproj) - likely an orphaned / dead source file

| Field | Value |
|---|---|
| Severity | Hint | Type | Code Smell |
| Tags | `dead-code`, `project`, `maintainability` |
| Detector | `uNotIncludedInProject.pas` |
| Scope | only `.dproj`/`.groupproj` scans (CLI `--project`/`--project-group`, IDE `...` dialog) |

Runs only for project- and project-group scans (--project / --project-group, or picking a .dproj/.groupproj via the '...' dialog), where the exact project file list (DCCReferences) is known. The detector walks the project file's directory recursively for .pas and .dfm files and flags every one the project does not reference. A .dfm counts as included when its companion .pas is referenced. Typical hits: units left behind after a refactor, experimental copies, or files removed from the project but not from disk. Limitation v1: only files INSIDE the project folder tree are checked - units referenced from outside via '..' relative DCCReferences, and search-path units, are neither walked nor flagged. Directory-recursive and single-file scans do not run this check (no project-membership concept). Fix: remove the file, add it to the project, or move it out of the project folder.

```pascal
// BAD
MyProject.dproj references uMain, uData - but the folder also contains uOldHelper.pas (not referenced) -> flagged

// GOOD
Remove uOldHelper.pas, add it to the project, or move it out of the project folder
```

---

_For richer per-rule pages with badges and full examples, install Python and run `python tools/gen-rules-docs.py`. Generated files land in `docs/rules/SCA001.md`...`SCA194.md`._

# StaticCodeAnalyser — Rule Catalog

All 194 detector rules. Click an ID for full details.

| ID | Name | Severity | Type | Detector |
|---|---|---|---|---|
| [SCA001](SCA001.md) | Object created without try/finally | Error | Bug | `uLeakDetector2.pas` |
| [SCA002](SCA002.md) | Empty except block | Warning | Code Smell | `uCodeSmells2.pas` |
| [SCA003](SCA003.md) | SQL string built via concatenation | Error | Vulnerability | `uSQLInjection.pas` |
| [SCA004](SCA004.md) | Hardcoded credential / API token | Error | Vulnerability | `uHardcodedSecret.pas` |
| [SCA005](SCA005.md) | Format() placeholder count mismatch | Error | Bug | `uFormatMismatch.pas` |
| [SCA006](SCA006.md) | File could not be read or parsed | Error | File Error | `(parser)` |
| [SCA007](SCA007.md) | Unused unit in uses clause | Hint | Code Smell | `uUnusedUses.pas` |
| [SCA008](SCA008.md) | Possible nil-dereference | Warning | Bug | `uNilDeref.pas` |
| [SCA009](SCA009.md) | Object created without protective try/finally | Warning | Code Smell | `uMissingFinally.pas` |
| [SCA010](SCA010.md) | Possible division by zero | Warning | Bug | `uDivByZero.pas` |
| [SCA011](SCA011.md) | Code after Exit/Raise is unreachable | Warning | Code Smell | `uDeadCode.pas` |
| [SCA012](SCA012.md) | Method exceeds line-count threshold | Hint | Code Smell | `uLongMethod.pas` |
| [SCA013](SCA013.md) | Too many parameters | Hint | Code Smell | `uLongParamList.pas` |
| [SCA014](SCA014.md) | Numeric literal without named constant | Hint | Code Smell | `uMagicNumbers.pas` |
| [SCA015](SCA015.md) | String literal repeated across multiple sites | Hint | Code Duplication | `uDuplicateString.pas` |
| [SCA016](SCA016.md) | Filesystem path as string literal | Warning | Security Hotspot | `uHardcodedPath.pas` |
| [SCA017](SCA017.md) | WriteLn/ShowMessage in production code | Warning | Code Smell | `uDebugOutput.pas` |
| [SCA018](SCA018.md) | Block nesting exceeds threshold | Hint | Code Smell | `uDeepNesting.pas` |
| [SCA019](SCA019.md) | TODO/FIXME marker in comment | Hint | Code Smell | `uTodoComment.pas` |
| [SCA020](SCA020.md) | Empty method body | Hint | Code Smell | `uEmptyMethod.pas` |
| [SCA021](SCA021.md) | Duplicated code block | Hint | Code Duplication | `uDuplicateBlock.pas` |
| [SCA022](SCA022.md) | Method exceeds McCabe complexity threshold | Hint | Code Smell | `uCyclomaticComplexity.pas` |
| [SCA023](SCA023.md) | User-defined custom rule | Warning | Code Smell | `uCustomRuleDetector.pas` |
| [SCA024](SCA024.md) | Component with default name | Hint | Code Smell | `uDfmDefaultName.pas` |
| [SCA025](SCA025.md) | Hardcoded UI text in DFM | Hint | Code Smell | `uDfmHardcodedCaption.pas` |
| [SCA026](SCA026.md) | Hardcoded DB credentials in DFM | Error | Vulnerability | `uDfmHardcodedDbCreds.pas` |
| [SCA027](SCA027.md) | Duplicate (DataSource, DataField) binding | Warning | Bug | `uDfmDuplicateBinding.pas` |
| [SCA028](SCA028.md) | DFM event handler references missing method | Error | Bug | `uDfmDeadEvent.pas` |
| [SCA029](SCA029.md) | Orphan event handler | Hint | Code Smell | `uDfmOrphanHandler.pas` |
| [SCA030](SCA030.md) | Empty bound event handler | Hint | Code Smell | `uDfmEmptyBoundEvent.pas` |
| [SCA031](SCA031.md) | DFM component without published field | Error | Bug | `uDfmSchemaMismatch.pas` |
| [SCA032](SCA032.md) | Circular DataSource / Master-Detail loop | Error | Bug | `uDfmCircularDataSource.pas` |
| [SCA033](SCA033.md) | SQL property built from UI input | Error | Vulnerability | `uDfmSqlFromUserInput.pas` |
| [SCA034](SCA034.md) | Required field has no UI binding | Warning | Bug | `uDfmRequiredField.pas` |
| [SCA035](SCA035.md) | Required field only on hidden controls | Warning | Bug | `uDfmRequiredField.pas` |
| [SCA036](SCA036.md) | UI control type mismatched with TField | Hint | Code Smell | `uDfmFieldTypeMismatch.pas` |
| [SCA037](SCA037.md) | Duplicate TabOrder among siblings | Hint | Code Smell | `uDfmTabOrderConflict.pas` |
| [SCA038](SCA038.md) | Component uses forbidden class | Hint | Code Smell | `uDfmForbiddenClass.pas` |
| [SCA039](SCA039.md) | DB component on UI form | Hint | Code Smell | `uDfmDbInUiForm.pas` |
| [SCA040](SCA040.md) | Cross-form field access | Warning | Bug | `uDfmCrossFormCoupling.pas` |
| [SCA041](SCA041.md) | Input control directly on TForm | Hint | Code Smell | `uDfmLayerViolation.pas` |
| [SCA042](SCA042.md) | God event handler | Hint | Code Smell | `uDfmGodHandler.pas` |
| [SCA043](SCA043.md) | Component has Action + OnClick | Warning | Bug | `uDfmActionMismatch.pas` |
| [SCA044](SCA044.md) | Long string concat - prefer Format() | Warning | Code Smell | `uConcatToFormat.pas` |
| [SCA045](SCA045.md) | with X do ... | Warning | Code Smell | `uWithStatement.pas` |
| [SCA046](SCA046.md) | for i := High to Low - missing downto | Error | Bug | `uReversedForRange.pas` |
| [SCA047](SCA047.md) | x := x | Warning | Bug | `uSelfAssignment.pas` |
| [SCA048](SCA048.md) | Virtual call in constructor | Error | Bug | `uVirtualCallInCtor.pas` |
| [SCA049](SCA049.md) | Length(s) - N without guard | Hint | Bug | `uLengthUnderflow.pas` |
| [SCA050](SCA050.md) | Public member could be unit-private | Hint | Code Smell | `uVisibilityCheck.pas` |
| [SCA051](SCA051.md) | Public member could be protected | Hint | Code Smell | `uVisibilityCheck.pas` |
| [SCA052](SCA052.md) | Unused public member (dead API) | Hint | Code Smell | `uVisibilityCheck.pas` |
| [SCA053](SCA053.md) | Unused local variable | Hint | Code Smell | `uUnusedLocal.pas` |
| [SCA054](SCA054.md) | Unused method parameter | Hint | Code Smell | `uUnusedParameter.pas` |
| [SCA055](SCA055.md) | Tautological boolean expression | Error | Bug | `uTautologicalExpr.pas` |
| [SCA056](SCA056.md) | Master-Detail without MasterFields | Error | Bug | `uDfmMasterDetailUnlinked.pas` |
| [SCA057](SCA057.md) | Form has many DB components - split DataModule | Hint | Code Smell | `uDfmDataModuleSplitHint.pas` |
| [SCA058](SCA058.md) | UPDATE / DELETE / TRUNCATE without WHERE | Error | Bug | `uSqlDangerousStatement.pas` |
| [SCA059](SCA059.md) | Format() float spec without TFormatSettings | Hint | Bug | `uFormatMismatch.pas` |
| [SCA060](SCA060.md) | goto statement | Warning | Code Smell | `uGotoStatement.pas` |
| [SCA061](SCA061.md) | Tab character in source | Hint | Code Smell | `uTabulationCharacter.pas` |
| [SCA062](SCA062.md) | Source line too long | Hint | Code Smell | `uTooLongLine.pas` |
| [SCA063](SCA063.md) | Trailing whitespace | Hint | Code Smell | `uTrailingWhitespace.pas` |
| [SCA064](SCA064.md) | Pascal keyword not lowercase | Hint | Code Smell | `uLowercaseKeyword.pas` |
| [SCA065](SCA065.md) | NOSONAR suppression marker | Hint | Code Smell | `uNoSonarMarker.pas` |
| [SCA066](SCA066.md) | Empty argument list | Hint | Code Smell | `uEmptyArgumentList.pas` |
| [SCA067](SCA067.md) | Inline assembly block | Warning | Code Smell | `uInlineAssembly.pas` |
| [SCA068](SCA068.md) | Trailing comma in argument list | Hint | Code Smell | `uTrailingCommaArgList.pas` |
| [SCA069](SCA069.md) | Integer literal without digit grouping | Hint | Code Smell | `uDigitGrouping.pas` |
| [SCA070](SCA070.md) | Commented-out code | Hint | Code Smell | `uCommentedOutCode.pas` |
| [SCA071](SCA071.md) | Unit-level keyword not at column 1 | Hint | Code Smell | `uUnitLevelKeywordIndent.pas` |
| [SCA072](SCA072.md) | Redundant boolean comparison | Hint | Code Smell | `uRedundantBoolean.pas` |
| [SCA073](SCA073.md) | Empty interface declaration | Hint | Code Smell | `uEmptyInterface.pas` |
| [SCA074](SCA074.md) | Assert without message | Hint | Code Smell | `uAssertMessage.pas` |
| [SCA075](SCA075.md) | Explicit TObject inheritance | Hint | Code Smell | `uExplicitTObjectInheritance.pas` |
| [SCA076](SCA076.md) | Grouped variable / field / parameter declaration | Hint | Code Smell | `uGroupedDeclaration.pas` |
| [SCA077](SCA077.md) | Empty begin..end block | Hint | Code Smell | `uEmptyBlock.pas` |
| [SCA078](SCA078.md) | Catch-all on root Exception class | Warning | Bug | `uExceptOnException.pas` |
| [SCA079](SCA079.md) | Consecutive const/type/var section | Hint | Code Smell | `uConsecutiveSection.pas` |
| [SCA080](SCA080.md) | Redundant Exit/Continue/Break before end | Hint | Code Smell | `uRedundantJump.pas` |
| [SCA081](SCA081.md) | Multiple class declarations in one file | Hint | Code Smell | `uClassPerFile.pas` |
| [SCA082](SCA082.md) | Double semicolon | Hint | Code Smell | `uSuperfluousSemicolon.pas` |
| [SCA083](SCA083.md) | Empty finally block | Warning | Bug | `uEmptyFinallyBlock.pas` |
| [SCA084](SCA084.md) | Redundant Assigned + nil check | Hint | Code Smell | `uAssignedAndAssignedNil.pas` |
| [SCA085](SCA085.md) | X.Free; X := nil; should be FreeAndNil(X) | Hint | Code Smell | `uFreeAndNilHint.pas` |
| [SCA086](SCA086.md) | Avoid out parameter modifier | Hint | Code Smell | `uAvoidOut.pas` |
| [SCA087](SCA087.md) | Empty visibility section in class | Hint | Code Smell | `uEmptyVisibilitySection.pas` |
| [SCA088](SCA088.md) | Legacy unit-init begin..end. | Hint | Code Smell | `uLegacyInitializationSection.pas` |
| [SCA089](SCA089.md) | Public field in class | Hint | Code Smell | `uPublicField.pas` |
| [SCA090](SCA090.md) | Nested try block | Hint | Code Smell | `uNestedTry.pas` |
| [SCA091](SCA091.md) | Large case statement | Hint | Code Smell | `uCaseStatementSize.pas` |
| [SCA092](SCA092.md) | Unit contains no declarations | Hint | Code Smell | `uEmptyFile.pas` |
| [SCA093](SCA093.md) | Multiple inherited calls in one method | Warning | Bug | `uTwiceInheritedCalls.pas` |
| [SCA094](SCA094.md) | Redundant double parentheses | Hint | Code Smell | `uRedundantParentheses.pas` |
| [SCA095](SCA095.md) | Consecutive visibility section | Hint | Code Smell | `uConsecutiveVisibility.pas` |
| [SCA096](SCA096.md) | Constructor without inherited call | Warning | Bug | `uConstructorWithoutInherited.pas` |
| [SCA097](SCA097.md) | Destructor without inherited call | Error | Bug | `uDestructorWithoutInherited.pas` |
| [SCA098](SCA098.md) | Redundant conditional assignment | Hint | Code Smell | `uRedundantConditional.pas` |
| [SCA099](SCA099.md) | Asymmetric begin/end in if/else | Hint | Code Smell | `uIfElseBegin.pas` |
| [SCA100](SCA100.md) | Pointer type alias not prefixed with P | Hint | Code Smell | `uPointerName.pas` |
| [SCA101](SCA101.md) | Branch without begin..end block | Hint | Code Smell | `uBeginEndRequired.pas` |
| [SCA102](SCA102.md) | Nested routine inside another method | Hint | Code Smell | `uNestedRoutines.pas` |
| [SCA103](SCA103.md) | Class field not prefixed with F | Hint | Code Smell | `uFieldName.pas` |
| [SCA104](SCA104.md) | Class/record type not prefixed with T | Hint | Code Smell | `uTypeName.pas` |
| [SCA105](SCA105.md) | Interface type not prefixed with I | Hint | Code Smell | `uInterfaceName.pas` |
| [SCA106](SCA106.md) | Method not in PascalCase | Hint | Code Smell | `uMethodName.pas` |
| [SCA107](SCA107.md) | Public member could be strict private | Hint | Code Smell | `uVisibilityCheck.pas` |
| [SCA108](SCA108.md) | TThread.Synchronize from destructor | Error | Bug | `uSynchronizeInDestructor.pas` |
| [SCA109](SCA109.md) | Lock acquired without try/finally release | Error | Bug | `uLockWithoutTryFinally.pas` |
| [SCA110](SCA110.md) | String concatenation in loop | Warning | Code Smell | `uPerfHotspots.pas` |
| [SCA111](SCA111.md) | ParamByName(...) called in loop | Hint | Code Smell | `uPerfHotspots.pas` |
| [SCA112](SCA112.md) | FieldByName(...) called in loop | Hint | Code Smell | `uPerfHotspots.pas` |
| [SCA113](SCA113.md) | TThread.Resume is deprecated | Warning | Code Smell | `uConcurrencyExt.pas` |
| [SCA114](SCA114.md) | TThread destroyed without Terminate+WaitFor | Error | Bug | `uConcurrencyExt.pas` |
| [SCA115](SCA115.md) | Plaintext HTTP URL | Warning | Security Hotspot | `uRestHttpSecurity.pas` |
| [SCA116](SCA116.md) | TLS verification disabled | Error | Vulnerability | `uRestHttpSecurity.pas` |
| [SCA117](SCA117.md) | Public member missing doc comment | Hint | Code Smell | `uPublicMemberWithoutDoc.pas` |
| [SCA118](SCA118.md) | Exception class without `E` prefix | Hint | Code Smell | `uNamingExt.pas` |
| [SCA119](SCA119.md) | Local constant not in UPPER_SNAKE_CASE | Hint | Code Smell | `uNamingExt.pas` |
| [SCA120](SCA120.md) | Exception constructed but never raised | Error | Bug | `uMissingRaise.pas` |
| [SCA121](SCA121.md) | Function never assigns Result | Error | Bug | `uRoutineResultAssigned.pas` |
| [SCA122](SCA122.md) | Re-raise of bound exception variable | Warning | Bug | `uReRaiseException.pas` |
| [SCA123](SCA123.md) | Type-cast immediately before Free / Destroy | Hint | Code Smell | `uCastAndFree.pas` |
| [SCA124](SCA124.md) | Constructor invoked on instance instead of class | Error | Bug | `uInstanceInvokedConstructor.pas` |
| [SCA125](SCA125.md) | Override whose entire body is `inherited;` | Hint | Code Smell | `uInheritedMethodEmpty.pas` |
| [SCA126](SCA126.md) | Use Assigned() instead of `= nil` / `<> nil` | Hint | Code Smell | `uNilComparison.pas` |
| [SCA127](SCA127.md) | Raise the bare `Exception` base class instead of a specific subclass | Warning | Code Smell | `uRaisingRawException.pas` |
| [SCA128](SCA128.md) | Locale-dependent format call without explicit TFormatSettings | Warning | Bug | `uDateFormatSettings.pas` |
| [SCA129](SCA129.md) | Cast from string to 8-bit string type without explicit encoding | Warning | Bug | `uUnicodeToAnsiCast.pas` |
| [SCA130](SCA130.md) | Cast of Char value to PChar reinterprets codepoint as pointer | Error | Bug | `uCharToCharPointerCast.pas` |
| [SCA131](SCA131.md) | IfThen() evaluates both branches - no short-circuit | Warning | Bug | `uIfThenShortCircuit.pas` |
| [SCA132](SCA132.md) | except on E: Exception catches every error | Warning | Code Smell | `uExceptionTooGeneral.pas` |
| [SCA133](SCA133.md) | Bare raise outside an except/on handler | Error | Bug | `uRaiseOutsideExcept.pas` |
| [SCA134](SCA134.md) | Variable used after Free / FreeAndNil | Error | Bug | `uUseAfterFree.pas` |
| [SCA135](SCA135.md) | Concrete subclass inherits an abstract method without override | Error | Bug | `uAbstractNotImpl.pas` |
| [SCA136](SCA136.md) | Constructor allocates fields and raises without try/except | Error | Bug | `uLeakInConstructor.pas` |
| [SCA137](SCA137.md) | Int64 target receives product of two 32-bit operands | Error | Bug | `uIntegerOverflow.pas` |
| [SCA138](SCA138.md) | Class has too many methods or fields | Warning | Code Smell | `uGodClass.pas` |
| [SCA139](SCA139.md) | Free without subsequent nil-out | Warning | Code Smell | `uFreeWithoutNil.pas` |
| [SCA140](SCA140.md) | Method has too many Exit statements | Warning | Code Smell | `uMultipleExit.pas` |
| [SCA141](SCA141.md) | Class implementation exceeds 500 lines | Warning | Code Smell | `uLargeClass.pas` |
| [SCA142](SCA142.md) | uses clause is not in alphabetical order | Hint | Code Smell | `uUnsortedUses.pas` |
| [SCA143](SCA143.md) | Unit has no descriptive header comment | Hint | Code Smell | `uMissingUnitHeader.pas` |
| [SCA144](SCA144.md) | Float equality / inequality comparison | Warning | Bug | `uFloatEquality.pas` |
| [SCA145](SCA145.md) | Raise inside destructor without try/except | Warning | Bug | `uExceptInDestructor.pas` |
| [SCA146](SCA146.md) | Boolean parameter used as internal branching flag | Hint | Code Smell | `uBooleanParam.pas` |
| [SCA147](SCA147.md) | Private method has no caller in the unit | Hint | Code Smell | `uUnusedPrivateMethod.pas` |
| [SCA148](SCA148.md) | Instance method never accesses Self - could be a class method | Hint | Code Smell | `uCanBeClassMethod.pas` |
| [SCA149](SCA149.md) | Method shadows a virtual parent method without `override` | Warning | Bug | `uMissingOverride.pas` |
| [SCA150](SCA150.md) | Boolean comparison is always true / always false | Warning | Bug | `uBoolAlwaysTrue.pas` |
| [SCA151](SCA151.md) | Function always returns the same literal | Hint | Code Smell | `uConstantReturn.pas` |
| [SCA152](SCA152.md) | User-visible string assigned as literal | Hint | Code Smell | `uHardcodedString.pas` |
| [SCA153](SCA153.md) | Lock acquired without try/finally release | Warning | Bug | `uUnpairedLock.pas` |
| [SCA154](SCA154.md) | Move/FillChar with SizeOf(pointer-type) | Warning | Bug | `uMoveSizeOfPointer.pas` |
| [SCA155](SCA155.md) | with statement on multiple targets | Hint | Code Smell | `uWithMultipleTargets.pas` |
| [SCA156](SCA156.md) | GetMem / AllocMem without try/finally | Warning | Bug | `uGetMemWithoutFreeMem.pas` |
| [SCA157](SCA157.md) | SetLength(arr, Length(arr) + N) inside a loop | Warning | Code Smell | `uSetLengthAppendInLoop.pas` |
| [SCA158](SCA158.md) | PChar(s) +/- offset without empty-check | Warning | Bug | `uPointerArithmeticOnString.pas` |
| [SCA159](SCA159.md) | Typed exception handler with empty body | Warning | Bug | `uEmptyOnHandler.pas` |
| [SCA160](SCA160.md) | String cast from raw pointer | Warning | Bug | `uStringFromPointer.pas` |
| [SCA161](SCA161.md) | Pointer subtraction via 32-bit cast | Warning | Bug | `uPointerSubtraction.pas` |
| [SCA162](SCA162.md) | Use of weak / deprecated cryptographic algorithm | Warning | Vulnerability | `uInsecureCryptoAlgorithm.pas` |
| [SCA163](SCA163.md) | Shell API called with string concatenation in argument | Error | Vulnerability | `uCommandInjection.pas` |
| [SCA164](SCA164.md) | Top-level routine never called | Hint | Code Smell | `uUnusedRoutine.pas` |
| [SCA165](SCA165.md) | Unused noinspection marker | Hint | Code Smell | `uSuppression.pas` |
| [SCA166](SCA166.md) | Uninitialised local variable | Error | Bug | `uUninitVar.pas` |
| [SCA167](SCA167.md) | Random call without prior Randomize | Warning | Bug | `uInsecureRandom.pas` |
| [SCA168](SCA168.md) | case statement without else branch | Hint | CodeSmell | `uDefaultCaseInCaseStatement.pas` |
| [SCA169](SCA169.md) | Assert argument contains a function call with side effects | Warning | Bug | `uAssertWithSideEffect.pas` |
| [SCA170](SCA170.md) | string parameter without const modifier | Hint | CodeSmell | `uConstStringParameter.pas` |
| [SCA171](SCA171.md) | Compiler switch OFF without matching ON in same file | Warning | CodeSmell | `uCompilerDirectiveScope.pas` |
| [SCA172](SCA172.md) | Boolean property without Is / Has / Can / Should prefix | Hint | CodeSmell | `uBooleanPropertyNaming.pas` |
| [SCA173](SCA173.md) | Variant in performance-sensitive method (contains a loop) | Hint | CodeSmell | `uVariantTypeMisuse.pas` |
| [SCA174](SCA174.md) | TList<T> filled with T.Create - items leak when list is freed | Warning | Bug | `uTObjectListWithoutOwnership.pas` |
| [SCA175](SCA175.md) | Anonymous method captures for-loop variable by reference | Error | Bug | `uAnonMethodCaptureLoopVar.pas` |
| [SCA176](SCA176.md) | Method has high cognitive complexity (nested control flow) | Warning | CodeSmell | `uCognitiveComplexity.pas` |
| [SCA177](SCA177.md) | Thread variable accessed after FreeOnTerminate := True | Error | Bug | `uThreadFreeOnTerminateWithRef.pas` |
| [SCA178](SCA178.md) | File-open API receives concatenated user input | Error | Vulnerability | `uPathTraversal.pas` |
| [SCA179](SCA179.md) | DUnitX [Ignore] attribute without reason argument | Hint | CodeSmell | `uAttributeIgnoreWithoutReason.pas` |
| [SCA180](SCA180.md) | Same attribute applied twice to one member | Warning | CodeSmell | `uAttributeDuplicate.pas` |
| [SCA181](SCA181.md) | DUnitX [Category] without category-name string | Error | Bug | `uAttributeCategoryWithoutString.pas` |
| [SCA182](SCA182.md) | [TestFixture] class without any [Test] method | Warning | CodeSmell | `uAttributeTestFixtureWithoutTests.pas` |
| [SCA183](SCA183.md) | Attribute with blank line before target member | Hint | CodeSmell | `uAttributeMisalignment.pas` |
| [SCA184](SCA184.md) | Unused DFM component | Hint | Code Smell | `uDfmComponentUnused.pas` |
| [SCA185](SCA185.md) | UTF-8 source file without BOM | Warning | Bug | `uSourceEncoding.pas` |
| [SCA186](SCA186.md) | Invalid UTF-8 sequence in source file | Error | File Error | `uSourceEncoding.pas` |
| [SCA187](SCA187.md) | NUL or control byte in source file | Error | File Error | `uSourceEncoding.pas` |
| [SCA188](SCA188.md) | Bidirectional override control character (Trojan Source) | Error | Vulnerability | `uSourceEncoding.pas` |
| [SCA189](SCA189.md) | ANSI source file with non-ASCII content | Warning | Code Smell | `uSourceEncoding.pas` |
| [SCA190](SCA190.md) | UTF-16 source file | Hint | Code Smell | `uSourceEncoding.pas` |
| [SCA191](SCA191.md) | UTF-32 / UCS-4 source file | Error | File Error | `uSourceEncoding.pas` |
| [SCA192](SCA192.md) | Invisible / zero-width character in source | Warning | Vulnerability | `uSourceEncoding.pas` |
| [SCA193](SCA193.md) | Non-ASCII character in identifier | Warning | Vulnerability | `uSourceEncoding.pas` |
| [SCA194](SCA194.md) | Source file not part of the project | Hint | Code Smell | `uNotIncludedInProject.pas` |

---

_Generated from [`rules/sca-rules.json`](../../rules/sca-rules.json) by [`tools/gen-rules-docs.py`](../../tools/gen-rules-docs.py)._

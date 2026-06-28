# Sonar-Delphi-Check-Coverage

Vergleich der Checks im Sonar-Delphi-Projekt
([integrated-application-development/sonar-delphi](https://github.com/integrated-application-development/sonar-delphi/tree/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks),
Stand 2026-05-18) mit dem lokalen Static Code Analyser.

Spalten:

- **Sonar-Check** — Klassenname (ohne `.java`)
- **Lokal** — `J` = vorhanden, `N` = nicht umgesetzt, `~` = teilweise
- **Pendant** — Datei in [SCA.Engine/sources/Detectors/](../SCA.Engine/sources/Detectors/)
- **Hinweis** — Anmerkung bei Teil-Coverage

Nicht aufgeführt sind reine Plumbing-Klassen (`Abstract*`, `CheckList`,
`ParsingErrorCheck`) — die haben keine eigene Check-Funktion.

## Tabelle

| Sonar-Check | Lokal | Pendant | Hinweis |
|---|:---:|---|---|
| AddressOfCharacterDataCheck | N | – | – |
| AddressOfNestedRoutineCheck | N | – | – |
| AssertMessageCheck | J | uAssertMessage | – |
| AssignedAndFreeCheck | ~ | uAssignedAndAssignedNil | lokal: Assigned/AssignedNil-Misuse; Sonar: Assigned vor Free |
| AttributeNameCheck | N | – | – |
| BeginEndRequiredCheck | J | uBeginEndRequired | – |
| CaseStatementSizeCheck | J | uCaseStatementSize | – |
| CastAndFreeCheck | N | – | – |
| CatchingRawExceptionCheck | ~ | uExceptOnException | überschneidet sich mit Swallowed-Exception-Pfad |
| CharacterToCharacterPointerCastCheck | N | – | – |
| ClassNameCheck | ~ | uTypeName | lokaler `uTypeName` deckt Class/Record/Enum gemeinsam ab |
| ClassPerFileCheck | J | uClassPerFile | – |
| CognitiveComplexityRoutineCheck | ~ | uCyclomaticComplexity | lokal nur Cyclomatic, kein Cognitive |
| CommentRegularExpressionCheck | N | – | – |
| CommentedOutCodeCheck | J | uCommentedOutCode | – |
| CompilerHintsCheck | N | – | – |
| CompilerWarningsCheck | N | – | – |
| ConsecutiveConstSectionCheck | J | uConsecutiveSection | lokal kombiniert const/var/type |
| ConsecutiveTypeSectionCheck | J | uConsecutiveSection | – |
| ConsecutiveVarSectionCheck | J | uConsecutiveSection | – |
| ConsecutiveVisibilitySectionCheck | J | uConsecutiveVisibility | – |
| ConstantNameCheck | N | – | – |
| ConstructorNameCheck | ~ | uMethodName | lokaler `uMethodName` deckt Routinen generell ab |
| ConstructorWithoutInheritedCheck | J | uConstructorWithoutInherited | – |
| CyclomaticComplexityRoutineCheck | J | uCyclomaticComplexity | – |
| DateFormatSettingsCheck | N | – | – |
| DestructorNameCheck | ~ | uMethodName | siehe ConstructorNameCheck |
| DestructorWithoutInheritedCheck | J | uDestructorWithoutInherited | – |
| DigitGroupingCheck | J | uDigitGrouping | – |
| DigitSeparatorCheck | ~ | uDigitGrouping | thematisch verwandt |
| EmptyArgumentListCheck | J | uEmptyArgumentList | – |
| EmptyBlockCheck | J | uEmptyBlock | – |
| EmptyFieldSectionCheck | ~ | uEmptyVisibilitySection | lokal nur Visibility, nicht Field-Section |
| EmptyFileCheck | J | uEmptyFile | – |
| EmptyFinallyBlockCheck | J | uEmptyFinallyBlock | – |
| EmptyInterfaceCheck | J | uEmptyInterface | – |
| EmptyRoutineCheck | J | uEmptyMethod | – |
| EmptyVisibilitySectionCheck | J | uEmptyVisibilitySection | – |
| EnumNameCheck | ~ | uTypeName | siehe ClassNameCheck |
| ExhaustiveEnumCaseCheck | N | – | – |
| ExplicitBitwiseNotCheck | N | – | – |
| ExplicitDefaultPropertyReferenceCheck | N | – | – |
| ExplicitTObjectInheritanceCheck | J | uExplicitTObjectInheritance | – |
| FieldNameCheck | J | uFieldName | – |
| ForbiddenConstantCheck | N | – | – |
| ForbiddenEnumValueCheck | N | – | – |
| ForbiddenFieldCheck | N | – | – |
| ForbiddenIdentifierCheck | N | – | – |
| ForbiddenImportFilePatternCheck | N | – | – |
| ForbiddenPropertyCheck | N | – | – |
| ForbiddenRoutineCheck | N | – | – |
| ForbiddenTypeCheck | ~ | uDfmForbiddenClass | lokal nur DFM-Komponenten |
| FormDfmCheck | J | uDfm* (Sammel) | 21 DFM-spezifische Detektoren |
| FormFmxCheck | N | – | FMX nicht abgedeckt |
| FormatArgumentCountCheck | J | uFormatMismatch | – |
| FormatArgumentTypeCheck | J | uFormatMismatch | – |
| FormatStringValidCheck | J | uFormatMismatch | – |
| FreeAndNilTObjectCheck | J | uFreeAndNilHint | – |
| FullyQualifiedImportCheck | N | – | – |
| GotoStatementCheck | J | uGotoStatement | – |
| GroupedFieldDeclarationCheck | J | uGroupedDeclaration | – |
| GroupedParameterDeclarationCheck | J | uGroupedDeclaration | – |
| GroupedVariableDeclarationCheck | J | uGroupedDeclaration | – |
| HelperNameCheck | N | – | – |
| IfThenShortCircuitCheck | N | – | – |
| ImplicitDefaultEncodingCheck | N | – | – |
| ImportSpecificityCheck | N | – | – |
| IndexLastListElementCheck | N | – | – |
| InheritedMethodWithNoCodeCheck | N | – | – |
| InheritedTypeNameCheck | N | – | – |
| InlineAssemblyCheck | J | uInlineAssembly | – |
| InlineConstExplicitTypeCheck | N | – | – |
| InlineDeclarationCapturedByAnonymousMethodCheck | N | – | – |
| InlineLoopVarExplicitTypeCheck | N | – | – |
| InlineVarExplicitTypeCheck | N | – | – |
| InstanceInvokedConstructorCheck | N | – | – |
| InterfaceGuidCheck | N | – | – |
| InterfaceNameCheck | J | uInterfaceName | – |
| IterationPastHighBoundCheck | ~ | uLengthUnderflow | thematisch verwandt (Loop-Boundary-Bugs) |
| LegacyInitializationSectionCheck | J | uLegacyInitializationSection | – |
| LoopExecutingAtMostOnceCheck | N | – | – |
| LowercaseKeywordCheck | J | uLowercaseKeyword | – |
| MathFunctionSingleOverloadCheck | N | – | – |
| MemberDeclarationOrderCheck | N | – | – |
| MissingRaiseCheck | N | – | – |
| MissingSemicolonCheck | N | – | – |
| MixedNamesCheck | N | – | – |
| NilComparisonCheck | ~ | uAssignedAndAssignedNil | überschneidet sich |
| NoSonarCheck | J | uNoSonarMarker | – |
| NonLinearCastCheck | N | – | – |
| NoreturnContractCheck | N | – | – |
| ObjectPassedAsInterfaceCheck | N | – | – |
| ObjectTypeCheck | N | – | – |
| PascalStyleResultCheck | N | – | – |
| PlatformDependentCastCheck | N | – | – |
| PlatformDependentTruncationCheck | N | – | – |
| PointerNameCheck | J | uPointerName | – |
| ProjectFileRoutineCheck | N | – | – |
| ProjectFileVariableCheck | N | – | – |
| PublicFieldCheck | J | uPublicField | – |
| RaisingRawExceptionCheck | N | – | – |
| ReRaiseExceptionCheck | N | – | – |
| RecordNameCheck | ~ | uTypeName | siehe ClassNameCheck |
| RedundantAssignmentCheck | ~ | uSelfAssignment | nur Self-Assignment, nicht jeder redundant assignment |
| RedundantBooleanCheck | J | uRedundantBoolean | – |
| RedundantCastCheck | N | – | – |
| RedundantInheritedCheck | ~ | uTwiceInheritedCalls | thematisch verwandt |
| RedundantJumpCheck | J | uRedundantJump | – |
| RedundantParenthesesCheck | J | uRedundantParentheses | – |
| RoutineNameCheck | J | uMethodName | – |
| RoutineNestingDepthCheck | ~ | uNestedRoutines | Sonar: Tiefe, lokal: Anzahl |
| RoutineResultAssignedCheck | N | – | – |
| ShortIdentifierCheck | N | – | – |
| StringListDuplicatesCheck | ~ | uDuplicateString | lokal allg. String-Duplikate, nicht spez. TStringList |
| StringLiteralRegularExpressionCheck | N | – | – |
| SuperfluousSemicolonCheck | J | uSuperfluousSemicolon | – |
| SwallowedExceptionCheck | J | uExceptOnException | – |
| TabulationCharacterCheck | J | uTabulationCharacter | – |
| TooLargeRoutineCheck | J | uLongMethod | – |
| TooLongLineCheck | J | uTooLongLine | – |
| TooManyDefaultParametersCheck | N | – | – |
| TooManyNestedRoutinesCheck | J | uNestedRoutines | – |
| TooManyParametersCheck | J | uLongParamList | – |
| TooManyVariablesCheck | N | – | – |
| TrailingCommaArgumentListCheck | J | uTrailingCommaArgList | – |
| TrailingWhitespaceCheck | J | uTrailingWhitespace | – |
| TypeAliasCheck | N | – | – |
| UnicodeToAnsiCastCheck | N | – | – |
| UnitLevelKeywordIndentationCheck | J | uUnitLevelKeywordIndent | – |
| UnitNameCheck | N | – | – |
| UnspecifiedReturnTypeCheck | N | – | – |
| UnusedConstantCheck | N | – | – |
| UnusedFieldCheck | ~ | uFieldLeak | lokal Leak-Fokus, nicht reines Unused |
| UnusedGlobalVariableCheck | N | – | – |
| UnusedImportCheck | J | uUnusedUses | – |
| UnusedLocalVariableCheck | J | uUnusedLocal | – |
| UnusedPropertyCheck | N | – | – |
| UnusedRoutineCheck | ~ | uDeadCode | überlappt mit allgemeiner Dead-Code-Erkennung |
| UnusedTypeCheck | N | – | – |
| VariableInitializationCheck | N | – | – |
| VariableNameCheck | N | – | – |
| VisibilityKeywordIndentationCheck | ~ | uVisibilityCheck | thematisch verwandt |
| VisibilitySectionOrderCheck | ~ | uVisibilityCheck | thematisch verwandt |
| WithStatementCheck | J | uWithStatement | – |

## Zusammenfassung

| Status | Anzahl |
|---|---:|
| Sonar-Checks insgesamt | 138 |
| `J` (umgesetzt) | 43 |
| `~` (teilweise) | 19 |
| `N` (nicht umgesetzt) | 76 |

Coverage (J + ~): ~45 % der Sonar-Checks haben ein lokales Pendant.

## Lokale Detektoren ohne Sonar-Pendant

Diese Detektoren existieren nur im lokalen Projekt — meist projektspezifische
Erweiterungen (DFM-Audit, SQL-Sicherheit, Leak-Detection, Concurrency).

### DFM-Audit (Form-Datei-Analyse, 21 Detektoren)

- uDfmActionMismatch
- uDfmCircularDataSource
- uDfmCrossFormCoupling
- uDfmDataModuleSplitHint
- uDfmDbInUiForm
- uDfmDeadEvent
- uDfmDefaultName
- uDfmDuplicateBinding
- uDfmEmptyBoundEvent
- uDfmFieldTypeMismatch
- uDfmForbiddenClass
- uDfmGodHandler
- uDfmHardcodedCaption
- uDfmHardcodedDbCreds
- uDfmLayerViolation
- uDfmMasterDetailUnlinked
- uDfmOrphanHandler
- uDfmRequiredField
- uDfmSchemaMismatch
- uDfmSqlFromUserInput
- uDfmTabOrderConflict

### SQL- & Web-Sicherheit

- uSQLInjection
- uSQLInjectionScore
- uSqlDangerousStatement
- uRestHttpSecurity
- uHardcodedSecret

### Leak- / Memory-Detection

- uLeakDetector2
- uFieldLeak
- uMissingFinally
- uNilDeref
- uDivByZero

### Concurrency

- uLockWithoutTryFinally
- uSynchronizeInDestructor
- uConcurrencyExt
- uVirtualCallInCtor

### Code-Smells (Projekt-spezifisch)

- uConcatToFormat
- uDebugOutput
- uDeepNesting
- uDuplicateBlock
- uHardcodedPath
- uIfElseBegin
- uLengthUnderflow
- uMagicNumbers
- uNestedTry
- uPublicMemberWithoutDoc
- uRedundantConditional
- uReversedForRange
- uSelfAssignment
- uTautologicalExpr
- uTodoComment

### Bündel / Plumbing (kein eigener Check)

- uCodeSmells2 — Detector-Bündel
- uCustomClassDiscovery — Custom-LeakyClass-Erkennung
- uCustomRuleDetector — User-konfigurierbare Regeln
- uDeadCode — generelle Dead-Code-Erkennung
- uNamingExt — Naming-Conventions-Erweiterung
- uPerfHotspots — Performance-Hotspot-Bündel
- uVisibilityCheck — Visibility-Klassifikation

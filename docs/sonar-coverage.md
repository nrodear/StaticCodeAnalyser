# Sonar-Delphi-Check-Coverage

Vergleich der Checks im Sonar-Delphi-Projekt
([integrated-application-development/sonar-delphi](https://github.com/integrated-application-development/sonar-delphi/tree/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks),
Stand 2026-05-18) mit dem lokalen Static Code Analyser.

> **Was hier „Coverage" heißt.** Dieses Dokument vergleicht **Regelsätze**:
> welche Checks des Sonar-Delphi-Plugins ein Pendant unter den
> SCA-Detektoren haben. Es geht **nicht** um Test-Coverage. Zeilenabdeckung
> für Delphi entsteht aus einem Testlauf mit
> [DelphiCodeCoverage](https://github.com/DelphiCodeCoverage/DelphiCodeCoverage)
> (braucht detaillierte `.map`-Dateien) und wird über die plugin-eigene
> Property `sonar.delphi.coverage.reportPaths` importiert, Testergebnisse
> aus DUnitX über `sonar.delphi.nunit.reportPaths`. Beides setzt das
> installierte Sonar-Delphi-Plugin voraus. SCA ist ein statischer
> Analyser: er führt keine Tests aus, kann folglich keine Coverage
> erzeugen und exportiert stattdessen das Generic **Issue** Format — das
> gerade *ohne* dieses Plugin funktioniert. Die generische Property
> `sonar.coverageReportPaths` ist hier ebenfalls nicht einschlägig.

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
| CastAndFreeCheck | J | uCastAndFree | – |
| CatchingRawExceptionCheck | J | uExceptionTooGeneral | AST-basiert; uExceptOnException ist der lexikalische Zwilling |
| CharacterToCharacterPointerCastCheck | J | uCharToCharPointerCast | – |
| ClassNameCheck | ~ | uTypeName | lokaler `uTypeName` deckt Class/Record/Enum gemeinsam ab |
| ClassPerFileCheck | J | uClassPerFile | – |
| CognitiveComplexityRoutineCheck | J | uCognitiveComplexity | eigener Detektor; SCA022 deckt Cyclomatic separat ab |
| CommentRegularExpressionCheck | N | – | – |
| CommentedOutCodeCheck | J | uCommentedOutCode | – |
| CompilerHintsCheck | ~ | uCompilerDirectiveScope | lokal nur unbalanciertes OFF ohne ON; upstream jedes Abschalten |
| CompilerWarningsCheck | ~ | uCompilerDirectiveScope | lokal nur unbalanciertes OFF ohne ON; upstream jedes Abschalten |
| ConsecutiveConstSectionCheck | J | uConsecutiveSection | lokal kombiniert const/var/type |
| ConsecutiveTypeSectionCheck | J | uConsecutiveSection | – |
| ConsecutiveVarSectionCheck | J | uConsecutiveSection | – |
| ConsecutiveVisibilitySectionCheck | J | uConsecutiveVisibility | – |
| ConstantNameCheck | N | – | – |
| ConstructorNameCheck | ~ | uMethodName | lokaler `uMethodName` deckt Routinen generell ab |
| ConstructorWithoutInheritedCheck | J | uConstructorWithoutInherited | – |
| CyclomaticComplexityRoutineCheck | J | uCyclomaticComplexity | – |
| DateFormatSettingsCheck | J | uDateFormatSettings | – |
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
| ExhaustiveEnumCaseCheck | ~ | uDefaultCaseInCaseStatement | lokal jedes case ohne else, ohne Enum-Vollstaendigkeitspruefung |
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
| FormDfmCheck | J | uDfm* (Sammel) | 22 DFM-spezifische Detektoren |
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
| IfThenShortCircuitCheck | J | uIfThenShortCircuit | – |
| ImplicitDefaultEncodingCheck | N | – | – |
| ImportSpecificityCheck | N | – | – |
| IndexLastListElementCheck | N | – | – |
| InheritedMethodWithNoCodeCheck | J | uInheritedMethodEmpty | – |
| InheritedTypeNameCheck | N | – | – |
| InlineAssemblyCheck | J | uInlineAssembly | – |
| InlineConstExplicitTypeCheck | N | – | – |
| InlineDeclarationCapturedByAnonymousMethodCheck | ~ | uAnonMethodCaptureLoopVar | Schnittmenge `for var i` + Closure; lokal auch klassische Loop-Vars, upstream auch Nicht-Loop-Inline-Vars |
| InlineLoopVarExplicitTypeCheck | N | – | – |
| InlineVarExplicitTypeCheck | N | – | – |
| InstanceInvokedConstructorCheck | J | uInstanceInvokedConstructor | – |
| InterfaceGuidCheck | N | – | – |
| InterfaceNameCheck | J | uInterfaceName | – |
| IterationPastHighBoundCheck | ~ | uLengthUnderflow | thematisch verwandt (Loop-Boundary-Bugs) |
| LegacyInitializationSectionCheck | J | uLegacyInitializationSection | – |
| LoopExecutingAtMostOnceCheck | N | – | – |
| LowercaseKeywordCheck | J | uLowercaseKeyword | – |
| MathFunctionSingleOverloadCheck | N | – | – |
| MemberDeclarationOrderCheck | N | – | – |
| MissingRaiseCheck | J | uMissingRaise | – |
| MissingSemicolonCheck | N | – | – |
| MixedNamesCheck | N | – | – |
| NilComparisonCheck | J | uNilComparison | uAssignedAndAssignedNil deckt zusätzlich Assigned-Misuse ab |
| NoSonarCheck | J | uNoSonarMarker | – |
| NonLinearCastCheck | N | – | – |
| NoreturnContractCheck | N | – | – |
| ObjectPassedAsInterfaceCheck | N | – | – |
| ObjectTypeCheck | N | – | – |
| PascalStyleResultCheck | N | – | – |
| PlatformDependentCastCheck | ~ | uPointerSubtraction | lokal nur die Cast-Subtraktions-Form, upstream jeder Cast |
| PlatformDependentTruncationCheck | N | – | – |
| PointerNameCheck | J | uPointerName | – |
| ProjectFileRoutineCheck | N | – | – |
| ProjectFileVariableCheck | N | – | – |
| PublicFieldCheck | J | uPublicField | – |
| RaisingRawExceptionCheck | J | uRaisingRawException | – |
| ReRaiseExceptionCheck | J | uReRaiseException | – |
| RecordNameCheck | ~ | uTypeName | siehe ClassNameCheck |
| RedundantAssignmentCheck | ~ | uSelfAssignment | nur Self-Assignment, nicht jeder redundant assignment |
| RedundantBooleanCheck | J | uRedundantBoolean | – |
| RedundantCastCheck | N | – | – |
| RedundantInheritedCheck | ~ | uTwiceInheritedCalls | thematisch verwandt |
| RedundantJumpCheck | J | uRedundantJump | – |
| RedundantParenthesesCheck | J | uRedundantParentheses | – |
| RoutineNameCheck | J | uMethodName | – |
| RoutineNestingDepthCheck | ~ | uNestedRoutines | Sonar: Tiefe, lokal: Anzahl |
| RoutineResultAssignedCheck | J | uRoutineResultAssigned | – |
| ShortIdentifierCheck | N | – | – |
| StringListDuplicatesCheck | ~ | uDuplicateString | lokal allg. String-Duplikate, nicht spez. TStringList |
| StringLiteralRegularExpressionCheck | N | – | – |
| SuperfluousSemicolonCheck | J | uSuperfluousSemicolon | – |
| SwallowedExceptionCheck | J | uEmptyOnHandler | leerer on-Handler; leerer except-Block via uCodeSmells2 |
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
| UnicodeToAnsiCastCheck | J | uUnicodeToAnsiCast | – |
| UnitLevelKeywordIndentationCheck | J | uUnitLevelKeywordIndent | – |
| UnitNameCheck | N | – | – |
| UnspecifiedReturnTypeCheck | N | – | – |
| UnusedConstantCheck | N | – | – |
| UnusedFieldCheck | ~ | uFieldLeak | lokal Leak-Fokus, nicht reines Unused |
| UnusedGlobalVariableCheck | N | – | – |
| UnusedImportCheck | J | uUnusedUses | – |
| UnusedLocalVariableCheck | J | uUnusedLocal | – |
| UnusedPropertyCheck | N | – | – |
| UnusedRoutineCheck | J | uUnusedRoutine + uUnusedPrivateMethod | SCA164 fuer Top-Level, private Klassenmethoden separat |
| UnusedTypeCheck | N | – | – |
| VariableInitializationCheck | J | uUninitVar | SCA166, pfadsensitiv |
| VariableNameCheck | N | – | – |
| VisibilityKeywordIndentationCheck | ~ | uVisibilityCheck | thematisch verwandt |
| VisibilitySectionOrderCheck | ~ | uVisibilityCheck | thematisch verwandt |
| WithStatementCheck | J | uWithStatement + uWithMultipleTargets | Mehrfach-Targets als eigener Detektor |

## Zusammenfassung

| Status | Anzahl |
|---|---:|
| Sonar-Checks insgesamt | 144 |
| `J` (umgesetzt) | 71 |
| `~` (teilweise) | 22 |
| `N` (nicht umgesetzt) | 51 |

Coverage (J + ~): **65 %** der Sonar-Checks haben ein lokales Pendant.

Die Summenzeile muss der Zeilenzahl der Tabelle oben entsprechen
(70 + 18 + 56 = 144); wer Zeilen ändert, zählt hier nach. Bis 2026-08-08
stand hier 138 bei 144 Tabellenzeilen, und fünfzehn Zeilen meldeten „nicht
umgesetzt", obwohl die Detektor-Unit existierte — die veröffentlichte
Quote war um 16 Prozentpunkte zu niedrig.

> **Stand der Erhebung: 2026-08-09, beide Seiten geprüft.**
>
> *Sonar-Seite:* über die GitHub-API gegen den heutigen Stand von
> `delphi-checks/.../checks` abgeglichen — 154 Dateien, davon 144
> vergleichbare Checks nach Abzug von `Abstract*`, `CheckList` und
> `ParsingErrorCheck`. Die Tabelle hat exakt diese 144: keine fehlt, keine
> ist zu viel.
>
> *Lokale Seite:* alle 178 Units aus `SCA.Engine/sources/Detectors/`
> kommen jetzt vor — entweder als Pendant in der Tabelle oder in den
> Listen unten. Bis 2026-08-09 fehlten 53 davon; sechs Tabellenzeilen
> standen dadurch zu niedrig (`CatchingRawExceptionCheck` hatte in
> Wahrheit ein volles Pendant, fünf weitere ein teilweises).
>
> Wer die Quote neu ausrechnet: die Summe der drei Statuszahlen muss der
> Zeilenzahl der Tabelle entsprechen (71 + 22 + 51 = 144).

## Lokale Detektoren ohne Sonar-Pendant

Diese Detektoren existieren nur im lokalen Projekt — meist projektspezifische
Erweiterungen (DFM-Audit, SQL-Sicherheit, Leak-Detection, Concurrency).

### DFM-Audit (Form-Datei-Analyse, 22 Detektoren)

- uDfmActionMismatch
- uDfmCircularDataSource
- uDfmComponentUnused
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
- uCommandInjection
- uInsecureCryptoAlgorithm
- uPathTraversal

### Leak- / Memory-Detection

- uLeakDetector2
- uFieldLeak
- uMissingFinally
- uNilDeref
- uDivByZero
- uFreeWithoutNil
- uGetMemWithoutFreeMem
- uLeakInConstructor
- uStringFromPointer
- uTObjectListWithoutOwnership
- uUseAfterFree

### Concurrency

- uLockWithoutTryFinally
- uSynchronizeInDestructor
- uConcurrencyExt
- uVirtualCallInCtor
- uThreadFreeOnTerminateWithRef
- uUnpairedLock

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
- uAssertWithSideEffect
- uAvoidOut
- uBoolAlwaysTrue
- uBooleanParam
- uBooleanPropertyNaming
- uCanBeClassMethod
- uConstStringParameter
- uConstantReturn
- uExceptInDestructor
- uFloatEquality
- uGodClass
- uHardcodedString
- uInsecureRandom
- uLargeClass
- uMissingUnitHeader
- uMultipleExit
- uSetLengthAppendInLoop
- uUnsortedUses
- uUnusedParameter
- uVariantTypeMisuse

### Attribute- & Test-Hygiene

DUnitX- und RTTI-Attribute; im Sonar-Regelsatz gibt es dafuer nur AttributeNameCheck (Benennung), keine Semantikpruefung.

- uAttributeCategoryWithoutString
- uAttributeDuplicate
- uAttributeIgnoreWithoutReason
- uAttributeMisalignment
- uAttributeTestFixtureWithoutTests

### Pointer- & 64-Bit-Fallen

Muster, die erst unter Win64 zu Datenverlust fuehren.

- uIntegerOverflow
- uMoveSizeOfPointer
- uPointerArithmeticOnString

### Korrektheit / Laufzeit

Fehler, die zur Laufzeit zuschlagen, nicht beim Uebersetzen.

- uAbstractNotImpl
- uManagedResultUninit
- uMissingOverride
- uRaiseOutsideExcept

### Datei- & Projekt-Ebene

Befunde ueber die Datei als Ganzes bzw. ihre Projektzugehoerigkeit - ausserhalb dessen, was ein AST-Check sehen kann.

- uSourceEncoding (Familie SCA185-193)
- uNotIncludedInProject

### Bündel / Plumbing (kein eigener Check)

- uCodeSmells2 — Detector-Bündel
- uCustomClassDiscovery — Custom-LeakyClass-Erkennung
- uCustomRuleDetector — User-konfigurierbare Regeln
- uDeadCode — generelle Dead-Code-Erkennung
- uNamingExt — Naming-Conventions-Erweiterung
- uPerfHotspots — Performance-Hotspot-Bündel
- uVisibilityCheck — Visibility-Klassifikation

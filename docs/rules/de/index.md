# StaticCodeAnalyser — Regelkatalog

Alle 196 Detektor-Regeln. Eine ID anklicken führt zur vollständigen Beschreibung.

| ID | Name | Schweregrad | Typ | Detektor |
|---|---|---|---|---|
| [SCA001](SCA001.md) | Objekt ohne try/finally erzeugt | Error | Bug | `uLeakDetector2.pas` |
| [SCA002](SCA002.md) | Leerer except-Block | Warning | Code Smell | `uCodeSmells2.pas` |
| [SCA003](SCA003.md) | SQL-String per Verkettung gebaut | Error | Vulnerability | `uSQLInjection.pas` |
| [SCA004](SCA004.md) | Hartkodierte Zugangsdaten / API-Token | Error | Vulnerability | `uHardcodedSecret.pas` |
| [SCA005](SCA005.md) | Format(): Platzhalterzahl passt nicht | Error | Bug | `uFormatMismatch.pas` |
| [SCA006](SCA006.md) | Datei konnte nicht gelesen oder geparst werden | Error | File Error | `(parser)` |
| [SCA007](SCA007.md) | Ungenutzte Unit in der uses-Klausel | Hint | Code Smell | `uUnusedUses.pas` |
| [SCA008](SCA008.md) | Mögliche nil-Dereferenzierung | Warning | Bug | `uNilDeref.pas` |
| [SCA009](SCA009.md) | Objekt ohne schützendes try/finally erzeugt | Warning | Code Smell | `uMissingFinally.pas` |
| [SCA010](SCA010.md) | Mögliche Division durch null | Warning | Bug | `uDivByZero.pas` |
| [SCA011](SCA011.md) | Code nach Exit/Raise ist unerreichbar | Warning | Code Smell | `uDeadCode.pas` |
| [SCA012](SCA012.md) | Methode überschreitet die Zeilengrenze | Hint | Code Smell | `uLongMethod.pas` |
| [SCA013](SCA013.md) | Zu viele Parameter | Hint | Code Smell | `uLongParamList.pas` |
| [SCA014](SCA014.md) | Zahlenliteral ohne benannte Konstante | Hint | Code Smell | `uMagicNumbers.pas` |
| [SCA015](SCA015.md) | String-Literal an mehreren Stellen wiederholt | Hint | Code Duplication | `uDuplicateString.pas` |
| [SCA016](SCA016.md) | Dateisystempfad als String-Literal | Warning | Security Hotspot | `uHardcodedPath.pas` |
| [SCA017](SCA017.md) | WriteLn/ShowMessage im Produktivcode | Warning | Code Smell | `uDebugOutput.pas` |
| [SCA018](SCA018.md) | Blockverschachtelung überschreitet die Grenze | Hint | Code Smell | `uDeepNesting.pas` |
| [SCA019](SCA019.md) | TODO/FIXME-Marker im Kommentar | Hint | Code Smell | `uTodoComment.pas` |
| [SCA020](SCA020.md) | Leerer Methodenrumpf | Hint | Code Smell | `uEmptyMethod.pas` |
| [SCA021](SCA021.md) | Duplizierter Codeblock | Hint | Code Duplication | `uDuplicateBlock.pas` |
| [SCA022](SCA022.md) | Methode überschreitet die McCabe-Komplexität | Hint | Code Smell | `uCyclomaticComplexity.pas` |
| [SCA023](SCA023.md) | Selbst definierte Regel | Warning | Code Smell | `uCustomRuleDetector.pas` |
| [SCA024](SCA024.md) | Komponente mit Vorgabenamen | Hint | Code Smell | `uDfmDefaultName.pas` |
| [SCA025](SCA025.md) | Hartkodierter UI-Text im DFM | Hint | Code Smell | `uDfmHardcodedCaption.pas` |
| [SCA026](SCA026.md) | Hartkodierte DB-Zugangsdaten im DFM | Error | Vulnerability | `uDfmHardcodedDbCreds.pas` |
| [SCA027](SCA027.md) | Doppelte (DataSource, DataField)-Bindung | Warning | Bug | `uDfmDuplicateBinding.pas` |
| [SCA028](SCA028.md) | DFM-Ereignisbehandler zeigt auf fehlende Methode | Error | Bug | `uDfmDeadEvent.pas` |
| [SCA029](SCA029.md) | Verwaister Ereignisbehandler | Hint | Code Smell | `uDfmOrphanHandler.pas` |
| [SCA030](SCA030.md) | Leerer gebundener Ereignisbehandler | Hint | Code Smell | `uDfmEmptyBoundEvent.pas` |
| [SCA031](SCA031.md) | DFM-Komponente ohne published-Feld | Hint | Code Smell | `uDfmSchemaMismatch.pas` |
| [SCA032](SCA032.md) | Zyklische DataSource-/Master-Detail-Schleife | Error | Bug | `uDfmCircularDataSource.pas` |
| [SCA033](SCA033.md) | SQL-Property aus UI-Eingabe gebaut | Error | Vulnerability | `uDfmSqlFromUserInput.pas` |
| [SCA034](SCA034.md) | Pflichtfeld ohne UI-Bindung | Warning | Bug | `uDfmRequiredField.pas` |
| [SCA035](SCA035.md) | Pflichtfeld nur an unsichtbaren Controls | Warning | Bug | `uDfmRequiredField.pas` |
| [SCA036](SCA036.md) | UI-Control passt nicht zum TField-Typ | Hint | Code Smell | `uDfmFieldTypeMismatch.pas` |
| [SCA037](SCA037.md) | Doppelte TabOrder unter Geschwistern | Hint | Code Smell | `uDfmTabOrderConflict.pas` |
| [SCA038](SCA038.md) | Komponente nutzt eine verbotene Klasse | Hint | Code Smell | `uDfmForbiddenClass.pas` |
| [SCA039](SCA039.md) | DB-Komponente auf einem UI-Formular | Hint | Code Smell | `uDfmDbInUiForm.pas` |
| [SCA040](SCA040.md) | Formularübergreifender Feldzugriff | Warning | Bug | `uDfmCrossFormCoupling.pas` |
| [SCA041](SCA041.md) | Eingabe-Control direkt auf dem TForm | Hint | Code Smell | `uDfmLayerViolation.pas` |
| [SCA042](SCA042.md) | Ereignisbehandler mit zu vielen Bindungen | Hint | Code Smell | `uDfmGodHandler.pas` |
| [SCA043](SCA043.md) | Komponente hat Action und OnClick | Warning | Bug | `uDfmActionMismatch.pas` |
| [SCA044](SCA044.md) | Lange String-Verkettung - besser Format() | Warning | Code Smell | `uConcatToFormat.pas` |
| [SCA045](SCA045.md) | with X do ... | Warning | Code Smell | `uWithStatement.pas` |
| [SCA046](SCA046.md) | for i := High to Low - downto fehlt | Error | Bug | `uReversedForRange.pas` |
| [SCA047](SCA047.md) | x := x | Warning | Bug | `uSelfAssignment.pas` |
| [SCA048](SCA048.md) | Virtueller Aufruf im Konstruktor | Error | Bug | `uVirtualCallInCtor.pas` |
| [SCA049](SCA049.md) | Length(s) - N ohne Absicherung | Hint | Bug | `uLengthUnderflow.pas` |
| [SCA050](SCA050.md) | Public-Member könnte unit-private sein | Hint | Code Smell | `uVisibilityCheck.pas` |
| [SCA051](SCA051.md) | Public-Member könnte protected sein | Hint | Code Smell | `uVisibilityCheck.pas` |
| [SCA052](SCA052.md) | Ungenutzter Public-Member (tote API) | Hint | Code Smell | `uVisibilityCheck.pas` |
| [SCA053](SCA053.md) | Ungenutzte lokale Variable | Hint | Code Smell | `uUnusedLocal.pas` |
| [SCA054](SCA054.md) | Ungenutzter Methodenparameter | Hint | Code Smell | `uUnusedParameter.pas` |
| [SCA055](SCA055.md) | Tautologischer boolescher Ausdruck | Error | Bug | `uTautologicalExpr.pas` |
| [SCA056](SCA056.md) | Master-Detail ohne MasterFields | Error | Bug | `uDfmMasterDetailUnlinked.pas` |
| [SCA057](SCA057.md) | Formular mit vielen DB-Komponenten - DataModule abspalten | Hint | Code Smell | `uDfmDataModuleSplitHint.pas` |
| [SCA058](SCA058.md) | UPDATE / DELETE / TRUNCATE ohne WHERE | Error | Bug | `uSqlDangerousStatement.pas` |
| [SCA059](SCA059.md) | Format()-Gleitkommaformat ohne TFormatSettings | Hint | Bug | `uFormatMismatch.pas` |
| [SCA060](SCA060.md) | goto-Anweisung | Warning | Code Smell | `uGotoStatement.pas` |
| [SCA061](SCA061.md) | Tabulator im Quelltext | Hint | Code Smell | `uTabulationCharacter.pas` |
| [SCA062](SCA062.md) | Quelltextzeile zu lang | Hint | Code Smell | `uTooLongLine.pas` |
| [SCA063](SCA063.md) | Leerraum am Zeilenende | Hint | Code Smell | `uTrailingWhitespace.pas` |
| [SCA064](SCA064.md) | Pascal-Schlüsselwort nicht klein geschrieben | Hint | Code Smell | `uLowercaseKeyword.pas` |
| [SCA065](SCA065.md) | NOSONAR-Unterdrückungsmarker | Hint | Code Smell | `uNoSonarMarker.pas` |
| [SCA066](SCA066.md) | Leere Argumentliste | Hint | Code Smell | `uEmptyArgumentList.pas` |
| [SCA067](SCA067.md) | Inline-Assembler-Block | Warning | Code Smell | `uInlineAssembly.pas` |
| [SCA068](SCA068.md) | Trailing-Komma in der Argument-Liste | Hint | Code Smell | `uTrailingCommaArgList.pas` |
| [SCA069](SCA069.md) | Ganzzahlliteral ohne Ziffergruppierung | Hint | Code Smell | `uDigitGrouping.pas` |
| [SCA070](SCA070.md) | Auskommentierter Code | Hint | Code Smell | `uCommentedOutCode.pas` |
| [SCA071](SCA071.md) | Unit-Section-Keyword nicht in Spalte 1 | Hint | Code Smell | `uUnitLevelKeywordIndent.pas` |
| [SCA072](SCA072.md) | Überflüssiger Boolean-Vergleich | Hint | Code Smell | `uRedundantBoolean.pas` |
| [SCA073](SCA073.md) | Leere Interface-Deklaration | Hint | Code Smell | `uEmptyInterface.pas` |
| [SCA074](SCA074.md) | Assert ohne Meldung | Hint | Code Smell | `uAssertMessage.pas` |
| [SCA075](SCA075.md) | Explizite TObject-Ableitung | Hint | Code Smell | `uExplicitTObjectInheritance.pas` |
| [SCA076](SCA076.md) | Gruppierte Variablen-, Feld- oder Parameterdeklaration | Hint | Code Smell | `uGroupedDeclaration.pas` |
| [SCA077](SCA077.md) | Leerer begin..end-Block | Hint | Code Smell | `uEmptyBlock.pas` |
| [SCA078](SCA078.md) | Catch-all auf der Wurzelklasse Exception | Warning | Bug | `uExceptOnException.pas` |
| [SCA079](SCA079.md) | Aufeinanderfolgende const/type/var-Sektion | Hint | Code Smell | `uConsecutiveSection.pas` |
| [SCA080](SCA080.md) | Überflüssiges Exit/Continue vor end | Hint | Code Smell | `uRedundantJump.pas` |
| [SCA081](SCA081.md) | Mehrere Klassendeklarationen in einer Datei | Hint | Code Smell | `uClassPerFile.pas` |
| [SCA082](SCA082.md) | Doppeltes Semikolon | Hint | Code Smell | `uSuperfluousSemicolon.pas` |
| [SCA083](SCA083.md) | Leerer finally-Block | Warning | Bug | `uEmptyFinallyBlock.pas` |
| [SCA084](SCA084.md) | Überflüssige Assigned- plus nil-Prüfung | Hint | Code Smell | `uAssignedAndAssignedNil.pas` |
| [SCA085](SCA085.md) | X.Free; X := nil; sollte FreeAndNil(X) sein | Hint | Code Smell | `uFreeAndNilHint.pas` |
| [SCA086](SCA086.md) | out-Parameter vermeiden | Hint | Code Smell | `uAvoidOut.pas` |
| [SCA087](SCA087.md) | Leere Sichtbarkeitssektion in der Klasse | Hint | Code Smell | `uEmptyVisibilitySection.pas` |
| [SCA088](SCA088.md) | Alte Unit-Initialisierung begin..end. | Hint | Code Smell | `uLegacyInitializationSection.pas` |
| [SCA089](SCA089.md) | Public-Feld in der Klasse | Hint | Code Smell | `uPublicField.pas` |
| [SCA090](SCA090.md) | Verschachtelter try-Block | Hint | Code Smell | `uNestedTry.pas` |
| [SCA091](SCA091.md) | Große case-Anweisung | Hint | Code Smell | `uCaseStatementSize.pas` |
| [SCA092](SCA092.md) | Unit ohne Deklarationen | Hint | Code Smell | `uEmptyFile.pas` |
| [SCA093](SCA093.md) | Mehrere inherited-Aufrufe in einer Methode | Warning | Bug | `uTwiceInheritedCalls.pas` |
| [SCA094](SCA094.md) | Überflüssige doppelte Klammern | Hint | Code Smell | `uRedundantParentheses.pas` |
| [SCA095](SCA095.md) | Wiederholte Sichtbarkeitssektion | Hint | Code Smell | `uConsecutiveVisibility.pas` |
| [SCA096](SCA096.md) | Konstruktor ohne inherited-Aufruf | Warning | Bug | `uConstructorWithoutInherited.pas` |
| [SCA097](SCA097.md) | Destruktor ohne inherited-Aufruf | Error | Bug | `uDestructorWithoutInherited.pas` |
| [SCA098](SCA098.md) | Überflüssige bedingte Zuweisung | Hint | Code Smell | `uRedundantConditional.pas` |
| [SCA099](SCA099.md) | Unsymmetrisches begin/end in if/else | Hint | Code Smell | `uIfElseBegin.pas` |
| [SCA100](SCA100.md) | Zeigertyp-Alias ohne P-Präfix | Hint | Code Smell | `uPointerName.pas` |
| [SCA101](SCA101.md) | Zweig ohne begin..end-Block | Hint | Code Smell | `uBeginEndRequired.pas` |
| [SCA102](SCA102.md) | Verschachtelte Routine in einer Methode | Hint | Code Smell | `uNestedRoutines.pas` |
| [SCA103](SCA103.md) | Klassenfeld ohne F-Präfix | Hint | Code Smell | `uFieldName.pas` |
| [SCA104](SCA104.md) | Klassen-/Record-Typ ohne T-Präfix | Hint | Code Smell | `uTypeName.pas` |
| [SCA105](SCA105.md) | Interface-Typ ohne I-Präfix | Hint | Code Smell | `uInterfaceName.pas` |
| [SCA106](SCA106.md) | Methode nicht in PascalCase | Hint | Code Smell | `uMethodName.pas` |
| [SCA107](SCA107.md) | Public-Member könnte strict private sein | Hint | Code Smell | `uVisibilityCheck.pas` |
| [SCA108](SCA108.md) | TThread.Synchronize aus dem Destruktor | Error | Bug | `uSynchronizeInDestructor.pas` |
| [SCA109](SCA109.md) | Sperre ohne try/finally freigegeben | Error | Bug | `uLockWithoutTryFinally.pas` |
| [SCA110](SCA110.md) | String-Verkettung in der Schleife | Warning | Code Smell | `uPerfHotspots.pas` |
| [SCA111](SCA111.md) | ParamByName(...) in der Schleife gerufen | Hint | Code Smell | `uPerfHotspots.pas` |
| [SCA112](SCA112.md) | FieldByName(...) in der Schleife gerufen | Hint | Code Smell | `uPerfHotspots.pas` |
| [SCA113](SCA113.md) | TThread.Resume ist veraltet | Warning | Code Smell | `uConcurrencyExt.pas` |
| [SCA114](SCA114.md) | TThread ohne Terminate+WaitFor freigegeben | Error | Bug | `uConcurrencyExt.pas` |
| [SCA115](SCA115.md) | HTTP-URL im Klartext | Warning | Security Hotspot | `uRestHttpSecurity.pas` |
| [SCA116](SCA116.md) | TLS-Prüfung abgeschaltet | Error | Vulnerability | `uRestHttpSecurity.pas` |
| [SCA117](SCA117.md) | Public-Member ohne Doku-Kommentar | Hint | Code Smell | `uPublicMemberWithoutDoc.pas` |
| [SCA118](SCA118.md) | Exception-Klasse ohne `E`-Präfix | Hint | Code Smell | `uNamingExt.pas` |
| [SCA119](SCA119.md) | Lokale Konstante nicht in UPPER_SNAKE_CASE | Hint | Code Smell | `uNamingExt.pas` |
| [SCA120](SCA120.md) | Exception erzeugt, aber nie ausgelöst | Error | Bug | `uMissingRaise.pas` |
| [SCA121](SCA121.md) | Funktion weist Result nie zu | Error | Bug | `uRoutineResultAssigned.pas` |
| [SCA122](SCA122.md) | Erneutes raise der gebundenen Exception-Variablen | Warning | Bug | `uReRaiseException.pas` |
| [SCA123](SCA123.md) | Typumwandlung direkt vor Free / Destroy | Hint | Code Smell | `uCastAndFree.pas` |
| [SCA124](SCA124.md) | Konstruktor auf einer Instanz statt der Klasse aufgerufen | Warning | Bug | `uInstanceInvokedConstructor.pas` |
| [SCA125](SCA125.md) | Override, dessen Rumpf nur aus `inherited;` besteht | Hint | Code Smell | `uInheritedMethodEmpty.pas` |
| [SCA126](SCA126.md) | Assigned() statt `= nil` / `<> nil` verwenden | Hint | Code Smell | `uNilComparison.pas` |
| [SCA127](SCA127.md) | Basisklasse `Exception` statt einer eigenen Ableitung ausgelöst | Warning | Code Smell | `uRaisingRawException.pas` |
| [SCA128](SCA128.md) | Gebietsschema-abhängiger Formataufruf ohne TFormatSettings | Warning | Bug | `uDateFormatSettings.pas` |
| [SCA129](SCA129.md) | String-Umwandlung in einen 8-Bit-Typ ohne explizite Kodierung | Warning | Bug | `uUnicodeToAnsiCast.pas` |
| [SCA130](SCA130.md) | Char-Wert nach PChar umgewandelt - Codepoint wird zur Adresse | Error | Bug | `uCharToCharPointerCast.pas` |
| [SCA131](SCA131.md) | IfThen() wertet beide Zweige aus - keine Kurzschlussauswertung | Warning | Bug | `uIfThenShortCircuit.pas` |
| [SCA132](SCA132.md) | except on E: Exception fängt jeden Fehler | Warning | Code Smell | `uExceptionTooGeneral.pas` |
| [SCA133](SCA133.md) | Blankes raise außerhalb eines except/on-Handlers | Error | Bug | `uRaiseOutsideExcept.pas` |
| [SCA134](SCA134.md) | Variable nach Free / FreeAndNil verwendet | Error | Bug | `uUseAfterFree.pas` |
| [SCA135](SCA135.md) | Konkrete Ableitung erbt eine abstrakte Methode ohne override | Error | Bug | `uAbstractNotImpl.pas` |
| [SCA136](SCA136.md) | Konstruktor belegt Felder und löst ohne try/except aus | Error | Bug | `uLeakInConstructor.pas` |
| [SCA137](SCA137.md) | Int64-Ziel bekommt das Produkt zweier 32-Bit-Operanden | Error | Bug | `uIntegerOverflow.pas` |
| [SCA138](SCA138.md) | Klasse hat zu viele Methoden oder Felder | Warning | Code Smell | `uGodClass.pas` |
| [SCA139](SCA139.md) | Free ohne anschließendes nil-Setzen | Warning | Code Smell | `uFreeWithoutNil.pas` |
| [SCA140](SCA140.md) | Methode hat zu viele Exit-Anweisungen | Warning | Code Smell | `uMultipleExit.pas` |
| [SCA141](SCA141.md) | Klassenimplementierung überschreitet 500 Zeilen | Warning | Code Smell | `uLargeClass.pas` |
| [SCA142](SCA142.md) | uses-Klausel ist nicht alphabetisch sortiert | Hint | Code Smell | `uUnsortedUses.pas` |
| [SCA143](SCA143.md) | Unit hat keinen erklärenden Header-Kommentar | Hint | Code Smell | `uMissingUnitHeader.pas` |
| [SCA144](SCA144.md) | Gleichheits-/Ungleichheitsvergleich von Gleitkommazahlen | Warning | Bug | `uFloatEquality.pas` |
| [SCA145](SCA145.md) | raise im Destruktor ohne try/except | Warning | Bug | `uExceptInDestructor.pas` |
| [SCA146](SCA146.md) | Boolean-Parameter als interner Verzweigungsschalter | Hint | Code Smell | `uBooleanParam.pas` |
| [SCA147](SCA147.md) | Private Methode ohne Aufrufer in der Unit | Hint | Code Smell | `uUnusedPrivateMethod.pas` |
| [SCA148](SCA148.md) | Instanzmethode greift nie auf Self zu - könnte Klassenmethode sein | Hint | Code Smell | `uCanBeClassMethod.pas` |
| [SCA149](SCA149.md) | Methode verdeckt eine virtuelle Basismethode ohne `override` | Warning | Bug | `uMissingOverride.pas` |
| [SCA150](SCA150.md) | Boolescher Vergleich ist immer wahr / immer falsch | Warning | Bug | `uBoolAlwaysTrue.pas` |
| [SCA151](SCA151.md) | Funktion liefert immer dasselbe Literal | Hint | Code Smell | `uConstantReturn.pas` |
| [SCA152](SCA152.md) | Benutzersichtbarer Text als Literal zugewiesen | Hint | Code Smell | `uHardcodedString.pas` |
| [SCA153](SCA153.md) | Lock/Unlock-Paar ohne try/finally | Warning | Bug | `uUnpairedLock.pas` |
| [SCA154](SCA154.md) | Move/FillChar mit SizeOf eines Zeigertyps | Warning | Bug | `uMoveSizeOfPointer.pas` |
| [SCA155](SCA155.md) | with-Anweisung mit mehreren Zielen | Hint | Code Smell | `uWithMultipleTargets.pas` |
| [SCA156](SCA156.md) | GetMem / AllocMem ohne try/finally | Warning | Bug | `uGetMemWithoutFreeMem.pas` |
| [SCA157](SCA157.md) | SetLength(arr, Length(arr) + N) in der Schleife | Warning | Code Smell | `uSetLengthAppendInLoop.pas` |
| [SCA158](SCA158.md) | PChar(s) +/- Offset ohne Leerprüfung | Warning | Bug | `uPointerArithmeticOnString.pas` |
| [SCA159](SCA159.md) | Typisierter Exception-Handler mit leerem Rumpf | Warning | Bug | `uEmptyOnHandler.pas` |
| [SCA160](SCA160.md) | String-Cast aus Raw-Pointer | Warning | Bug | `uStringFromPointer.pas` |
| [SCA161](SCA161.md) | Zeigersubtraktion über eine 32-Bit-Umwandlung | Warning | Bug | `uPointerSubtraction.pas` |
| [SCA162](SCA162.md) | Schwaches oder veraltetes Kryptoverfahren verwendet | Warning | Vulnerability | `uInsecureCryptoAlgorithm.pas` |
| [SCA163](SCA163.md) | Shell-API mit String-Verkettung im Argument gerufen | Error | Vulnerability | `uCommandInjection.pas` |
| [SCA164](SCA164.md) | Routine auf oberster Ebene wird nie gerufen | Hint | Code Smell | `uUnusedRoutine.pas` |
| [SCA165](SCA165.md) | Ungenutzter noinspection-Marker | Hint | Code Smell | `uSuppression.pas` |
| [SCA166](SCA166.md) | Uninitialisierte lokale Variable | Error | Bug | `uUninitVar.pas` |
| [SCA167](SCA167.md) | Random-Aufruf ohne vorheriges Randomize | Warning | Bug | `uInsecureRandom.pas` |
| [SCA168](SCA168.md) | case-Anweisung ohne else-Zweig | Hint | Code Smell | `uDefaultCaseInCaseStatement.pas` |
| [SCA169](SCA169.md) | Assert-Argument enthält einen Aufruf mit Seiteneffekt | Warning | Bug | `uAssertWithSideEffect.pas` |
| [SCA170](SCA170.md) | string-Parameter ohne const | Hint | Code Smell | `uConstStringParameter.pas` |
| [SCA171](SCA171.md) | Compilerschalter OFF ohne passendes ON in derselben Datei | Warning | Code Smell | `uCompilerDirectiveScope.pas` |
| [SCA172](SCA172.md) | Boolean-Property ohne Is-/Has-/Can-/Should-Präfix | Hint | Code Smell | `uBooleanPropertyNaming.pas` |
| [SCA173](SCA173.md) | Variant in einer leistungskritischen Methode (enthält Schleife) | Hint | Code Smell | `uVariantTypeMisuse.pas` |
| [SCA174](SCA174.md) | TList<T> mit T.Create gefüllt - Elemente lecken beim Freigeben | Warning | Bug | `uTObjectListWithoutOwnership.pas` |
| [SCA175](SCA175.md) | Anonyme Methode fängt die Schleifenvariable per Referenz | Error | Bug | `uAnonMethodCaptureLoopVar.pas` |
| [SCA176](SCA176.md) | Methode mit hoher kognitiver Komplexität (verschachtelter Kontrollfluss) | Warning | Code Smell | `uCognitiveComplexity.pas` |
| [SCA177](SCA177.md) | Thread-Variable nach FreeOnTerminate := True verwendet | Error | Bug | `uThreadFreeOnTerminateWithRef.pas` |
| [SCA178](SCA178.md) | Datei-Open-API bekommt verkettete Benutzereingabe | Error | Vulnerability | `uPathTraversal.pas` |
| [SCA179](SCA179.md) | DUnitX-Attribut [Ignore] ohne Begründung | Hint | Code Smell | `uAttributeIgnoreWithoutReason.pas` |
| [SCA180](SCA180.md) | Dasselbe Attribut zweimal am selben Member | Warning | Code Smell | `uAttributeDuplicate.pas` |
| [SCA181](SCA181.md) | DUnitX-Attribut [Category] ohne Kategorienamen | Error | Bug | `uAttributeCategoryWithoutString.pas` |
| [SCA182](SCA182.md) | [TestFixture]-Klasse ohne [Test]-Methode | Warning | Code Smell | `uAttributeTestFixtureWithoutTests.pas` |
| [SCA183](SCA183.md) | Attribut mit Leerzeile vor dem Ziel-Member | Hint | Code Smell | `uAttributeMisalignment.pas` |
| [SCA184](SCA184.md) | Ungenutzte DFM-Komponente | Hint | Code Smell | `uDfmComponentUnused.pas` |
| [SCA185](SCA185.md) | UTF-8-Quelldatei ohne BOM | Warning | Bug | `uSourceEncoding.pas` |
| [SCA186](SCA186.md) | Ungültige UTF-8-Folge in der Quelldatei | Error | File Error | `uSourceEncoding.pas` |
| [SCA187](SCA187.md) | NUL- oder Steuerbyte in der Quelldatei | Error | File Error | `uSourceEncoding.pas` |
| [SCA188](SCA188.md) | Bidirektionales Steuerzeichen (Trojan Source) | Error | Vulnerability | `uSourceEncoding.pas` |
| [SCA189](SCA189.md) | ANSI-Quelldatei mit Nicht-ASCII-Inhalt | Warning | Code Smell | `uSourceEncoding.pas` |
| [SCA190](SCA190.md) | UTF-16-Quelldatei | Hint | Code Smell | `uSourceEncoding.pas` |
| [SCA191](SCA191.md) | UTF-32-/UCS-4-Quelldatei | Error | File Error | `uSourceEncoding.pas` |
| [SCA192](SCA192.md) | Unsichtbares Zeichen ohne Breite im Quelltext | Warning | Vulnerability | `uSourceEncoding.pas` |
| [SCA193](SCA193.md) | Nicht-ASCII-Zeichen im Bezeichner | Warning | Vulnerability | `uSourceEncoding.pas` |
| [SCA194](SCA194.md) | Quelldatei gehört nicht zum Projekt | Hint | Code Smell | `uNotIncludedInProject.pas` |
| [SCA195](SCA195.md) | Unit wird vom Projekt genutzt, ist aber nicht darin enthalten | Hint | Code Smell | `uNotIncludedInProject.pas` |
| [SCA196](SCA196.md) | Result eines verwalteten Typs wird gelesen, bevor es zugewiesen wurde | Warning | Bug | `uManagedResultUninit.pas` |

---

_Generated from [`rules/sca-rules.json`](../../../rules/sca-rules.json) by [`tools/gen-rules-docs.py`](../../../tools/gen-rules-docs.py)._

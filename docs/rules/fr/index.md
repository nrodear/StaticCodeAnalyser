# StaticCodeAnalyser — Catalogue de règles

Les 198 règles de détection. Cliquez sur un identifiant pour le détail complet.

| ID | Nom | Sévérité | Type | Détecteur |
|---|---|---|---|---|
| [SCA001](SCA001.md) | Objet créé sans try/finally | Error | Bug | `uLeakDetector2.pas` |
| [SCA002](SCA002.md) | Bloc except vide | Warning | Code Smell | `uCodeSmells2.pas` |
| [SCA003](SCA003.md) | Chaîne SQL construite par concaténation | Error | Vulnerability | `uSQLInjection.pas` |
| [SCA004](SCA004.md) | Identifiant / jeton d'API en dur | Error | Vulnerability | `uHardcodedSecret.pas` |
| [SCA005](SCA005.md) | Format() : nombre de marqueurs incohérent | Error | Bug | `uFormatMismatch.pas` |
| [SCA006](SCA006.md) | Le fichier n'a pas pu être lu ou analysé | Error | File Error | `(parser)` |
| [SCA007](SCA007.md) | Unit inutilisée dans la clause uses | Hint | Code Smell | `uUnusedUses.pas` |
| [SCA008](SCA008.md) | Déréférencement nil possible | Warning | Bug | `uNilDeref.pas` |
| [SCA009](SCA009.md) | Objet créé sans try/finally protecteur | Warning | Code Smell | `uMissingFinally.pas` |
| [SCA010](SCA010.md) | Division par zéro possible | Warning | Bug | `uDivByZero.pas` |
| [SCA011](SCA011.md) | Le code après Exit/Raise est inatteignable | Warning | Code Smell | `uDeadCode.pas` |
| [SCA012](SCA012.md) | La méthode dépasse le seuil de lignes | Hint | Code Smell | `uLongMethod.pas` |
| [SCA013](SCA013.md) | Trop de paramètres | Hint | Code Smell | `uLongParamList.pas` |
| [SCA014](SCA014.md) | Littéral numérique sans constante nommée | Hint | Code Smell | `uMagicNumbers.pas` |
| [SCA015](SCA015.md) | Littéral chaîne répété a plusieurs endroits | Hint | Code Duplication | `uDuplicateString.pas` |
| [SCA016](SCA016.md) | Chemin de fichier en littéral chaîne | Warning | Security Hotspot | `uHardcodedPath.pas` |
| [SCA017](SCA017.md) | WriteLn/ShowMessage en code de production | Warning | Code Smell | `uDebugOutput.pas` |
| [SCA018](SCA018.md) | L'imbrication de blocs dépasse le seuil | Hint | Code Smell | `uDeepNesting.pas` |
| [SCA019](SCA019.md) | Marqueur TODO/FIXME en commentaire | Hint | Code Smell | `uTodoComment.pas` |
| [SCA020](SCA020.md) | Corps de méthode vide | Hint | Code Smell | `uEmptyMethod.pas` |
| [SCA021](SCA021.md) | Bloc de code dupliqué | Hint | Code Duplication | `uDuplicateBlock.pas` |
| [SCA022](SCA022.md) | La méthode dépasse le seuil de complexité de McCabe | Hint | Code Smell | `uCyclomaticComplexity.pas` |
| [SCA023](SCA023.md) | Règle personnalisée | Warning | Code Smell | `uCustomRuleDetector.pas` |
| [SCA024](SCA024.md) | Composant au nom par défaut | Hint | Code Smell | `uDfmDefaultName.pas` |
| [SCA025](SCA025.md) | Texte d'interface en dur dans le DFM | Hint | Code Smell | `uDfmHardcodedCaption.pas` |
| [SCA026](SCA026.md) | Identifiants de base de données en dur dans le DFM | Error | Vulnerability | `uDfmHardcodedDbCreds.pas` |
| [SCA027](SCA027.md) | Liaison (DataSource, DataField) en double | Warning | Bug | `uDfmDuplicateBinding.pas` |
| [SCA028](SCA028.md) | Le gestionnaire d'événement DFM pointe vers une méthode absente | Error | Bug | `uDfmDeadEvent.pas` |
| [SCA029](SCA029.md) | Gestionnaire d'événement orphelin | Hint | Code Smell | `uDfmOrphanHandler.pas` |
| [SCA030](SCA030.md) | Gestionnaire d'événement lié mais vide | Hint | Code Smell | `uDfmEmptyBoundEvent.pas` |
| [SCA031](SCA031.md) | Composant DFM sans champ published | Hint | Code Smell | `uDfmSchemaMismatch.pas` |
| [SCA032](SCA032.md) | Boucle DataSource / maître-detail circulaire | Error | Bug | `uDfmCircularDataSource.pas` |
| [SCA033](SCA033.md) | Propriété SQL construite depuis une saisie d'interface | Error | Vulnerability | `uDfmSqlFromUserInput.pas` |
| [SCA034](SCA034.md) | Champ obligatoire sans liaison d'interface | Warning | Bug | `uDfmRequiredField.pas` |
| [SCA035](SCA035.md) | Champ obligatoire lié uniquement a des contrôles cachés | Warning | Bug | `uDfmRequiredField.pas` |
| [SCA036](SCA036.md) | Type de contrôle incompatible avec le TField | Hint | Code Smell | `uDfmFieldTypeMismatch.pas` |
| [SCA037](SCA037.md) | TabOrder en double entre frères | Hint | Code Smell | `uDfmTabOrderConflict.pas` |
| [SCA038](SCA038.md) | Le composant utilise une classe interdite | Hint | Code Smell | `uDfmForbiddenClass.pas` |
| [SCA039](SCA039.md) | Composant de base de données sur une fiche d'interface | Hint | Code Smell | `uDfmDbInUiForm.pas` |
| [SCA040](SCA040.md) | Accès a un champ d'une autre fiche | Warning | Bug | `uDfmCrossFormCoupling.pas` |
| [SCA041](SCA041.md) | Contrôle de saisie directement sur le TForm | Hint | Code Smell | `uDfmLayerViolation.pas` |
| [SCA042](SCA042.md) | Gestionnaire d'événement surcharge | Hint | Code Smell | `uDfmGodHandler.pas` |
| [SCA043](SCA043.md) | Le composant a Action et OnClick | Warning | Bug | `uDfmActionMismatch.pas` |
| [SCA044](SCA044.md) | Longue concaténation - préférer Format() | Warning | Code Smell | `uConcatToFormat.pas` |
| [SCA045](SCA045.md) | with X do ... | Warning | Code Smell | `uWithStatement.pas` |
| [SCA046](SCA046.md) | for i := High to Low - downto manquant | Error | Bug | `uReversedForRange.pas` |
| [SCA047](SCA047.md) | x := x | Warning | Bug | `uSelfAssignment.pas` |
| [SCA048](SCA048.md) | Appel virtuel dans le constructeur | Error | Bug | `uVirtualCallInCtor.pas` |
| [SCA049](SCA049.md) | Length(s) - N sans garde | Hint | Bug | `uLengthUnderflow.pas` |
| [SCA050](SCA050.md) | Le membre public pourrait être privé a l'unit | Hint | Code Smell | `uVisibilityCheck.pas` |
| [SCA051](SCA051.md) | Le membre public pourrait être protected | Hint | Code Smell | `uVisibilityCheck.pas` |
| [SCA052](SCA052.md) | Membre public inutilisé (API morte) | Hint | Code Smell | `uVisibilityCheck.pas` |
| [SCA053](SCA053.md) | Variable locale inutilisée | Hint | Code Smell | `uUnusedLocal.pas` |
| [SCA054](SCA054.md) | Paramètre de méthode inutilisé | Hint | Code Smell | `uUnusedParameter.pas` |
| [SCA055](SCA055.md) | Expression booléenne tautologique | Error | Bug | `uTautologicalExpr.pas` |
| [SCA056](SCA056.md) | Maître-detail sans MasterFields | Error | Bug | `uDfmMasterDetailUnlinked.pas` |
| [SCA057](SCA057.md) | Fiche chargée de composants de données - extraire un DataModule | Hint | Code Smell | `uDfmDataModuleSplitHint.pas` |
| [SCA058](SCA058.md) | UPDATE / DELETE / TRUNCATE sans WHERE | Error | Bug | `uSqlDangerousStatement.pas` |
| [SCA059](SCA059.md) | Format flottant dans Format() sans TFormatSettings | Hint | Bug | `uFormatMismatch.pas` |
| [SCA060](SCA060.md) | Instruction goto | Warning | Code Smell | `uGotoStatement.pas` |
| [SCA061](SCA061.md) | Tabulation dans le source | Hint | Code Smell | `uTabulationCharacter.pas` |
| [SCA062](SCA062.md) | Ligne de source trop longue | Hint | Code Smell | `uTooLongLine.pas` |
| [SCA063](SCA063.md) | Espaces en fin de ligne | Hint | Code Smell | `uTrailingWhitespace.pas` |
| [SCA064](SCA064.md) | Mot-clé Pascal pas en minuscules | Hint | Code Smell | `uLowercaseKeyword.pas` |
| [SCA065](SCA065.md) | Marqueur de suppression NOSONAR | Hint | Code Smell | `uNoSonarMarker.pas` |
| [SCA066](SCA066.md) | Liste d'arguments vide | Hint | Code Smell | `uEmptyArgumentList.pas` |
| [SCA067](SCA067.md) | Bloc assembleur en ligne | Warning | Code Smell | `uInlineAssembly.pas` |
| [SCA068](SCA068.md) | Virgule finale dans la liste d'arguments | Hint | Code Smell | `uTrailingCommaArgList.pas` |
| [SCA069](SCA069.md) | Littéral entier sans séparateur de milliers | Hint | Code Smell | `uDigitGrouping.pas` |
| [SCA070](SCA070.md) | Code en commentaire | Hint | Code Smell | `uCommentedOutCode.pas` |
| [SCA071](SCA071.md) | Mot-clé de section d'unit qui n'est pas en colonne 1 | Hint | Code Smell | `uUnitLevelKeywordIndent.pas` |
| [SCA072](SCA072.md) | Comparaison booléenne redondante | Hint | Code Smell | `uRedundantBoolean.pas` |
| [SCA073](SCA073.md) | Déclaration d'interface vide | Hint | Code Smell | `uEmptyInterface.pas` |
| [SCA074](SCA074.md) | Assert sans message | Hint | Code Smell | `uAssertMessage.pas` |
| [SCA075](SCA075.md) | Héritage explicite de TObject | Hint | Code Smell | `uExplicitTObjectInheritance.pas` |
| [SCA076](SCA076.md) | Déclaration groupée de variables, champs ou paramètres | Hint | Code Smell | `uGroupedDeclaration.pas` |
| [SCA077](SCA077.md) | Bloc begin..end vide | Hint | Code Smell | `uEmptyBlock.pas` |
| [SCA078](SCA078.md) | Capture générale sur la classe racine Exception | Warning | Bug | `uExceptOnException.pas` |
| [SCA079](SCA079.md) | Sections const/type/var consécutives | Hint | Code Smell | `uConsecutiveSection.pas` |
| [SCA080](SCA080.md) | Exit/Continue redondant avant end | Hint | Code Smell | `uRedundantJump.pas` |
| [SCA081](SCA081.md) | Plusieurs déclarations de classe dans un fichier | Hint | Code Smell | `uClassPerFile.pas` |
| [SCA082](SCA082.md) | Point-virgule double | Hint | Code Smell | `uSuperfluousSemicolon.pas` |
| [SCA083](SCA083.md) | Bloc finally vide | Warning | Bug | `uEmptyFinallyBlock.pas` |
| [SCA084](SCA084.md) | Test Assigned + nil redondant | Hint | Code Smell | `uAssignedAndAssignedNil.pas` |
| [SCA085](SCA085.md) | X.Free; X := nil; devrait être FreeAndNil(X) | Hint | Code Smell | `uFreeAndNilHint.pas` |
| [SCA086](SCA086.md) | Éviter le modificateur out | Hint | Code Smell | `uAvoidOut.pas` |
| [SCA087](SCA087.md) | Section de visibilité vide dans la classe | Hint | Code Smell | `uEmptyVisibilitySection.pas` |
| [SCA088](SCA088.md) | Initialisation d'unit à l'ancienne begin..end. | Hint | Code Smell | `uLegacyInitializationSection.pas` |
| [SCA089](SCA089.md) | Champ public dans la classe | Hint | Code Smell | `uPublicField.pas` |
| [SCA090](SCA090.md) | Bloc try imbriqué | Hint | Code Smell | `uNestedTry.pas` |
| [SCA091](SCA091.md) | Instruction case volumineuse | Hint | Code Smell | `uCaseStatementSize.pas` |
| [SCA092](SCA092.md) | Unit sans aucune déclaration | Hint | Code Smell | `uEmptyFile.pas` |
| [SCA093](SCA093.md) | Plusieurs appels inherited dans une méthode | Warning | Bug | `uTwiceInheritedCalls.pas` |
| [SCA094](SCA094.md) | Doubles parenthèses redondantes | Hint | Code Smell | `uRedundantParentheses.pas` |
| [SCA095](SCA095.md) | Section de visibilité répétée | Hint | Code Smell | `uConsecutiveVisibility.pas` |
| [SCA096](SCA096.md) | Constructeur sans appel a inherited | Warning | Bug | `uConstructorWithoutInherited.pas` |
| [SCA097](SCA097.md) | Destructeur sans appel a inherited | Error | Bug | `uDestructorWithoutInherited.pas` |
| [SCA098](SCA098.md) | Affectation conditionnelle redondante | Hint | Code Smell | `uRedundantConditional.pas` |
| [SCA099](SCA099.md) | begin/end asymétrique dans if/else | Hint | Code Smell | `uIfElseBegin.pas` |
| [SCA100](SCA100.md) | Alias de type pointeur sans préfixe P | Hint | Code Smell | `uPointerName.pas` |
| [SCA101](SCA101.md) | Branche sans bloc begin..end | Hint | Code Smell | `uBeginEndRequired.pas` |
| [SCA102](SCA102.md) | Routine imbriquée dans une méthode | Hint | Code Smell | `uNestedRoutines.pas` |
| [SCA103](SCA103.md) | Champ de classe sans préfixe F | Hint | Code Smell | `uFieldName.pas` |
| [SCA104](SCA104.md) | Type classe ou record sans préfixe T | Hint | Code Smell | `uTypeName.pas` |
| [SCA105](SCA105.md) | Type interface sans préfixe I | Hint | Code Smell | `uInterfaceName.pas` |
| [SCA106](SCA106.md) | Méthode pas en PascalCase | Hint | Code Smell | `uMethodName.pas` |
| [SCA107](SCA107.md) | Le membre public pourrait être strict private | Hint | Code Smell | `uVisibilityCheck.pas` |
| [SCA108](SCA108.md) | TThread.Synchronize depuis le destructeur | Error | Bug | `uSynchronizeInDestructor.pas` |
| [SCA109](SCA109.md) | Verrou pris sans libération par try/finally | Error | Bug | `uLockWithoutTryFinally.pas` |
| [SCA110](SCA110.md) | Concaténation de chaîne dans une boucle | Warning | Code Smell | `uPerfHotspots.pas` |
| [SCA111](SCA111.md) | ParamByName(...) appelé dans une boucle | Hint | Code Smell | `uPerfHotspots.pas` |
| [SCA112](SCA112.md) | FieldByName(...) appelé dans une boucle | Hint | Code Smell | `uPerfHotspots.pas` |
| [SCA113](SCA113.md) | TThread.Resume est obsolète | Warning | Code Smell | `uConcurrencyExt.pas` |
| [SCA114](SCA114.md) | TThread libéré sans Terminate+WaitFor | Error | Bug | `uConcurrencyExt.pas` |
| [SCA115](SCA115.md) | URL HTTP en clair | Warning | Security Hotspot | `uRestHttpSecurity.pas` |
| [SCA116](SCA116.md) | Vérification TLS désactivée | Error | Vulnerability | `uRestHttpSecurity.pas` |
| [SCA117](SCA117.md) | Membre public sans commentaire de documentation | Hint | Code Smell | `uPublicMemberWithoutDoc.pas` |
| [SCA118](SCA118.md) | Classe d'exception sans préfixe `E` | Hint | Code Smell | `uNamingExt.pas` |
| [SCA119](SCA119.md) | Constante locale pas en UPPER_SNAKE_CASE | Hint | Code Smell | `uNamingExt.pas` |
| [SCA120](SCA120.md) | Exception construite mais jamais levée | Error | Bug | `uMissingRaise.pas` |
| [SCA121](SCA121.md) | La fonction n'affecte jamais Result | Error | Bug | `uRoutineResultAssigned.pas` |
| [SCA122](SCA122.md) | Relevée de la variable d'exception liée | Warning | Bug | `uReRaiseException.pas` |
| [SCA123](SCA123.md) | Transtypage juste avant Free / Destroy | Hint | Code Smell | `uCastAndFree.pas` |
| [SCA124](SCA124.md) | Constructeur appelé sur une instance au lieu de la classe | Warning | Bug | `uInstanceInvokedConstructor.pas` |
| [SCA125](SCA125.md) | Redéfinition dont le corps se réduit a `inherited;` | Hint | Code Smell | `uInheritedMethodEmpty.pas` |
| [SCA126](SCA126.md) | Utiliser Assigned() plutôt que `= nil` / `<> nil` | Hint | Code Smell | `uNilComparison.pas` |
| [SCA127](SCA127.md) | Levée de la classe de base `Exception` au lieu d'une sous-classe | Warning | Code Smell | `uRaisingRawException.pas` |
| [SCA128](SCA128.md) | Appel de formatage dépendant de la locale sans TFormatSettings | Warning | Bug | `uDateFormatSettings.pas` |
| [SCA129](SCA129.md) | Transtypage de chaîne vers un type 8 bits sans encodage explicite | Warning | Bug | `uUnicodeToAnsiCast.pas` |
| [SCA130](SCA130.md) | Transtypage d'un Char en PChar : le point de code devient une adresse | Error | Bug | `uCharToCharPointerCast.pas` |
| [SCA131](SCA131.md) | IfThen() évalue les deux branches - pas de court-circuit | Warning | Bug | `uIfThenShortCircuit.pas` |
| [SCA132](SCA132.md) | except on E: Exception attrape toutes les erreurs | Warning | Code Smell | `uExceptionTooGeneral.pas` |
| [SCA133](SCA133.md) | raise nu hors d'un gestionnaire except/on | Error | Bug | `uRaiseOutsideExcept.pas` |
| [SCA134](SCA134.md) | Variable utilisee après Free / FreeAndNil | Error | Bug | `uUseAfterFree.pas` |
| [SCA135](SCA135.md) | Classe concrète héritant d'une méthode abstraite sans override | Error | Bug | `uAbstractNotImpl.pas` |
| [SCA136](SCA136.md) | Constructeur qui alloue des champs et lève sans try/except | Error | Bug | `uLeakInConstructor.pas` |
| [SCA137](SCA137.md) | Cible Int64 recevant le produit de deux opérandes 32 bits | Error | Bug | `uIntegerOverflow.pas` |
| [SCA138](SCA138.md) | La classe a trop de méthodes ou de champs | Warning | Code Smell | `uGodClass.pas` |
| [SCA139](SCA139.md) | Free sans mise à nil ensuite | Warning | Code Smell | `uFreeWithoutNil.pas` |
| [SCA140](SCA140.md) | La méthode a trop d'instructions Exit | Warning | Code Smell | `uMultipleExit.pas` |
| [SCA141](SCA141.md) | L'implementation de la classe dépasse 500 lignes | Warning | Code Smell | `uLargeClass.pas` |
| [SCA142](SCA142.md) | La clause uses n'est pas dans l'ordre alphabétique | Hint | Code Smell | `uUnsortedUses.pas` |
| [SCA143](SCA143.md) | L'unit n'a pas de commentaire d'en-tête descriptif | Hint | Code Smell | `uMissingUnitHeader.pas` |
| [SCA144](SCA144.md) | Comparaison d'égalité ou d'inégalité entre flottants | Warning | Bug | `uFloatEquality.pas` |
| [SCA145](SCA145.md) | raise dans un destructeur sans try/except | Warning | Bug | `uExceptInDestructor.pas` |
| [SCA146](SCA146.md) | Paramètre booléen servant d'aiguillage interne | Hint | Code Smell | `uBooleanParam.pas` |
| [SCA147](SCA147.md) | Méthode privée sans appelant dans l'unit | Hint | Code Smell | `uUnusedPrivateMethod.pas` |
| [SCA148](SCA148.md) | Méthode d'instance n'accédant jamais a Self - pourrait être de classe | Hint | Code Smell | `uCanBeClassMethod.pas` |
| [SCA149](SCA149.md) | La méthode masque une méthode virtuelle parente sans `override` | Warning | Bug | `uMissingOverride.pas` |
| [SCA150](SCA150.md) | La comparaison booléenne est toujours vraie / toujours fausse | Warning | Bug | `uBoolAlwaysTrue.pas` |
| [SCA151](SCA151.md) | La fonction renvoie toujours le même littéral | Hint | Code Smell | `uConstantReturn.pas` |
| [SCA152](SCA152.md) | Texte visible par l'utilisateur affecté en littéral | Hint | Code Smell | `uHardcodedString.pas` |
| [SCA153](SCA153.md) | Paire Lock/Unlock sans try/finally | Warning | Bug | `uUnpairedLock.pas` |
| [SCA154](SCA154.md) | Move/FillChar avec SizeOf d'un type pointeur | Warning | Bug | `uMoveSizeOfPointer.pas` |
| [SCA155](SCA155.md) | Instruction with sur plusieurs cibles | Hint | Code Smell | `uWithMultipleTargets.pas` |
| [SCA156](SCA156.md) | GetMem / AllocMem sans try/finally | Warning | Bug | `uGetMemWithoutFreeMem.pas` |
| [SCA157](SCA157.md) | SetLength(arr, Length(arr) + N) dans une boucle | Warning | Code Smell | `uSetLengthAppendInLoop.pas` |
| [SCA158](SCA158.md) | PChar(s) +/- décalage sans test de chaîne vide | Warning | Bug | `uPointerArithmeticOnString.pas` |
| [SCA159](SCA159.md) | Gestionnaire d'exception typée au corps vide | Warning | Bug | `uEmptyOnHandler.pas` |
| [SCA160](SCA160.md) | Transtypage en chaîne depuis un pointeur brut | Warning | Bug | `uStringFromPointer.pas` |
| [SCA161](SCA161.md) | Soustraction de pointeurs via un transtypage 32 bits | Warning | Bug | `uPointerSubtraction.pas` |
| [SCA162](SCA162.md) | Utilisation d'un algorithme cryptographique faible ou obsolète | Warning | Vulnerability | `uInsecureCryptoAlgorithm.pas` |
| [SCA163](SCA163.md) | API shell appelée avec concaténation dans les arguments | Error | Vulnerability | `uCommandInjection.pas` |
| [SCA164](SCA164.md) | Routine de premier niveau jamais appelée | Hint | Code Smell | `uUnusedRoutine.pas` |
| [SCA165](SCA165.md) | Marqueur noinspection inutilisé | Hint | Code Smell | `uSuppression.pas` |
| [SCA166](SCA166.md) | Variable locale non initialisée | Error | Bug | `uUninitVar.pas` |
| [SCA167](SCA167.md) | Appel a Random sans Randomize préalable | Warning | Bug | `uInsecureRandom.pas` |
| [SCA168](SCA168.md) | Instruction case sans branche else | Hint | Code Smell | `uDefaultCaseInCaseStatement.pas` |
| [SCA169](SCA169.md) | L'argument d'Assert contient un appel a effet de bord | Warning | Bug | `uAssertWithSideEffect.pas` |
| [SCA170](SCA170.md) | Paramètre string sans const | Hint | Code Smell | `uConstStringParameter.pas` |
| [SCA171](SCA171.md) | Directive de compilation OFF sans ON correspondant dans le fichier | Warning | Code Smell | `uCompilerDirectiveScope.pas` |
| [SCA172](SCA172.md) | Propriété booléenne sans préfixe Is / Has / Can / Should | Hint | Code Smell | `uBooleanPropertyNaming.pas` |
| [SCA173](SCA173.md) | Variant dans une méthode sensible aux performances (avec boucle) | Hint | Code Smell | `uVariantTypeMisuse.pas` |
| [SCA174](SCA174.md) | TList<T> rempli de T.Create - les éléments fuient a la libération | Warning | Bug | `uTObjectListWithoutOwnership.pas` |
| [SCA175](SCA175.md) | Méthode anonyme capturant la variable de boucle par référence | Error | Bug | `uAnonMethodCaptureLoopVar.pas` |
| [SCA176](SCA176.md) | Méthode a forte complexité cognitive (flot de contrôle imbriqué) | Warning | Code Smell | `uCognitiveComplexity.pas` |
| [SCA177](SCA177.md) | Variable de thread utilisee après FreeOnTerminate := True | Error | Bug | `uThreadFreeOnTerminateWithRef.pas` |
| [SCA178](SCA178.md) | API d'ouverture de fichier recevant une saisie utilisateur concaténée | Error | Vulnerability | `uPathTraversal.pas` |
| [SCA179](SCA179.md) | Attribut DUnitX [Ignore] sans argument de justification | Hint | Code Smell | `uAttributeIgnoreWithoutReason.pas` |
| [SCA180](SCA180.md) | Le même attribut applique deux fois au même membre | Warning | Code Smell | `uAttributeDuplicate.pas` |
| [SCA181](SCA181.md) | Attribut DUnitX [Category] sans nom de catégorie | Error | Bug | `uAttributeCategoryWithoutString.pas` |
| [SCA182](SCA182.md) | Classe [TestFixture] sans aucune méthode [Test] | Warning | Code Smell | `uAttributeTestFixtureWithoutTests.pas` |
| [SCA183](SCA183.md) | Attribut suivi d'une ligne vide avant le membre cible | Hint | Code Smell | `uAttributeMisalignment.pas` |
| [SCA184](SCA184.md) | Composant DFM inutilisé | Hint | Code Smell | `uDfmComponentUnused.pas` |
| [SCA185](SCA185.md) | Fichier source UTF-8 sans BOM | Warning | Bug | `uSourceEncoding.pas` |
| [SCA186](SCA186.md) | Séquence UTF-8 invalide dans le fichier source | Error | File Error | `uSourceEncoding.pas` |
| [SCA187](SCA187.md) | Octet NUL ou de contrôle dans le fichier source | Error | File Error | `uSourceEncoding.pas` |
| [SCA188](SCA188.md) | Caractère de contrôle bidirectionnel (Trojan Source) | Error | Vulnerability | `uSourceEncoding.pas` |
| [SCA189](SCA189.md) | Fichier source ANSI avec du contenu non-ASCII | Warning | Code Smell | `uSourceEncoding.pas` |
| [SCA190](SCA190.md) | Fichier source UTF-16 | Hint | Code Smell | `uSourceEncoding.pas` |
| [SCA191](SCA191.md) | Fichier source UTF-32 / UCS-4 | Error | File Error | `uSourceEncoding.pas` |
| [SCA192](SCA192.md) | Caractère invisible ou de largeur nulle dans le source | Warning | Vulnerability | `uSourceEncoding.pas` |
| [SCA193](SCA193.md) | Caractère non-ASCII dans un identifiant | Warning | Vulnerability | `uSourceEncoding.pas` |
| [SCA194](SCA194.md) | Fichier source hors du projet | Hint | Code Smell | `uNotIncludedInProject.pas` |
| [SCA195](SCA195.md) | Unit utilisee par le projet mais non incluse dedans | Hint | Code Smell | `uNotIncludedInProject.pas` |
| [SCA196](SCA196.md) | Result de type managé est lu avant d'avoir été affecté | Warning | Bug | `uManagedResultUninit.pas` |
| [SCA197](SCA197.md) | Interface déclarée sans GUID | Warning | Code Smell | `uInterfaceGuid.pas` |
| [SCA198](SCA198.md) | Deux interfaces partagent le même GUID | Warning | Bug | `uInterfaceGuid.pas` |

---

_Generated from [`rules/sca-rules.json`](../../../rules/sca-rules.json) by [`tools/gen-rules-docs.py`](../../../tools/gen-rules-docs.py)._

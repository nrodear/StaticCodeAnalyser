# Détecteurs — catalogue de règles Sonar du Static Code Analysis Tool for Delphi

Liste canonique de toutes les règles d'analyse prises en charge et
planifiées, classées par sévérité (Blocker → Critical → Major → Minor →
Info). Le catalogue suit la taxonomie Sonar des 50 règles et ajoute une
poignée de détecteurs bonus propres à cet outil.

Légende des statuts : ✅ implémenté · 🟡 partiel · 🔲 ouvert

**Résumé (2026-08-07) :** Les **198 kinds de règles** du roster canonique [`rules/sca-rules.json`](rules/sca-rules.json) sont tous implémentés et énumérés dans ce fichier (portés par **157 enregistrements de pipeline** ; plusieurs classes émettent plusieurs kinds — p. ex. `uVisibilityCheck` → 3 kinds de visibilité, `uPerfHotspots` → SCA110–112, `uSourceEncoding` → SCA185–193, `uDfmAnalysisRunner` → 23 kinds DFM ; **SCA194/SCA195 sont à portée projet, non basés sur l'AST** — émis par le dispatch du scan projet/groupe, pas par le registre de détecteurs par fichier). 44 / 50 slots de règles Sonar complets ; les 4 slots ouverts (#20 ResultNotChecked, #22 CyclicUnitDep, #42 UnnecessaryCast, #49 DeprecatedAPI) exigent de l'inférence de types / une résolution inter-unités et n'ont pas encore de SCA-ID.

Les 4 slots encore ouverts exigent tous inférence de types / analyse de flux / résolution de symboles inter-unités : #20 ResultNotChecked, #22 CyclicUnitDep, #42 UnnecessaryCast, #49 DeprecatedAPI. **#16 UninitVar** dispose d'un MVP conservateur (`SCA166`) — la sensibilité complète aux chemins reste ouverte pour la phase 3.

Les 21 détecteurs AST Pascal ci-dessous suivent la taxonomie Sonar des
50 règles. Les **23 détecteurs DFM** de la section dédiée sont propres
aux fichiers de fiche et n'apparaissent pas dans le catalogue Sonar —
ils travaillent sur le lexer DFM + parser + graphe de composants (avec
le FormBinder pour le couplage à l'AST Pascal) introduits avec la
v0.10.0. Le **cluster de migration SonarDelphi (SCA120-131)** ci-dessous
couvre des vérifications de correction propres à Delphi que SonarDelphi
livre et que nous avons portées. Les vérifications de nommage / formatage / structure SCA060-119 sont énumérées
dans leur propre section ci-dessous (ajoutée le 2026-07-19) ; [`rules/sca-rules.json`](rules/sca-rules.json)
reste le roster canonique lisible par machine.

🇬🇧 [English version](DETECTORS.md) · 🇩🇪 [Deutsche Fassung](DETECTORS_de.md)

---

## 🔴 Blocker (5)

| # | SCA | Règle | Description | Statut | Unit |
|---|-----|-------|-------------|--------|------|
| 1 | SCA001 | **MemoryLeak — objet jamais libéré** | Objet créé via `.Create` mais aucun `Free`/`FreeAndNil`/`Destroy` nulle part dans le corps de la méthode. Les routines qui prennent la propriété d'un objet transmis peuvent être mises en liste blanche via `[Detectors] OwnershipSinks=Routine1,Routine2` (passer l'objet à une telle routine compte comme un transfert de propriété → pas de fuite) | ✅ | `uLeakDetector2` |
| 2 | SCA002 | **EmptyExcept — bloc except vide** | Bloc `except` sans instruction exécutable — les exceptions sont avalées en silence | ✅ | `uCodeSmells2` |
| 3 | SCA008 | **NilDeref — pointeur nil sans vérification** | Champ objet ou paramètre déréférencé sans vérification `Assigned()` préalable | ✅ | `uNilDeref` |
| 4 | SCA003 | **SQLInjection — concaténation de chaînes dans du SQL** | Commande SQL construite par concaténation `+` avec une saisie utilisateur — pas de requête paramétrée | ✅ | `uSQLInjection` |
| 5 | SCA004 | **HardcodedSecret — mot de passe/jeton dans le code** | Littéral affecté à une variable dont le nom contient `password`, `token`, `secret`, `key` | ✅ | `uHardcodedSecret` |

---

## 🟠 Critical (10)

| # | SCA | Règle | Description | Statut | Unit |
|---|-----|-------|-------------|--------|------|
| 6 | SCA010 | **DivByZero — division par zéro possible** | Division entière ou modulo où le diviseur peut valoir zéro (pas de vérification préalable) | ✅ | `uDivByZero` |
| 7 | SCA134 | **UseAfterFree — objet utilisé après Free** | Variable utilisée après `Free`/`FreeAndNil` sans avoir été réaffectée | ✅ | `uUseAfterFree` |
| 8 | SCA009 | **MissingFinally — ressource sans try/finally** | Objet créé, la méthode a un try/except mais aucun try/finally pour le nettoyage | ✅ | `uMissingFinally` |
| 9 | SCA005 | **FormatMismatch — mauvais nombre d'arguments dans Format()** | Le nombre de marqueurs `%s`/`%d` de la chaîne de format ne correspond pas à la liste d'arguments | ✅ | `uFormatMismatch` |
| 10 | SCA135 | **AbstractNotImpl — méthode abstraite non implémentée** | Une classe concrète hérite d'une base abstraite mais n'implémente pas toutes les méthodes `abstract` | ✅ | `uAbstractNotImpl` (intra-unité uniquement) |
| 11 | SCA132 | **ExceptionTooGeneral — type d'exception trop large** | `except on E: Exception` au lieu d'un type spécifique — masque les erreurs inattendues | ✅ | `uExceptionTooGeneral` |
| 12 | SCA136 | **LeakInConstructor — exception dans le constructeur sans nettoyage** | Le constructeur peut lever une exception après une initialisation partielle sans appeler `Free` | ✅ | `uLeakInConstructor` |
| 13 | — | **MissingDestructor — destructeur manquant / champ non libéré** | Classe avec des champs objets : pas de destructeur, ou un champ n'est pas libéré dans `Destroy` | ✅ | `uFieldLeak` |
| 14 | SCA137 | **IntegerOverflow — débordement arithmétique** | Multiplication ou exponentiation sur `Integer`/`Word` sans vérification de plage préalable | ✅ | `uIntegerOverflow` (cible Int64 uniquement) |
| 15 | — | **RaiseWithoutClass — `raise` nu** | Un `raise` nu hors d'un bloc `except` — provoque une Access Violation | ✅ | `uRaiseOutsideExcept` |

---

## 🟡 Major — Fiabilité (10)

| # | SCA | Règle | Description | Statut | Unit |
|---|-----|-------|-------------|--------|------|
| 16 | SCA166 | **UninitVar — variable non initialisée** | Variable locale lue avant d'être affectée sur chaque chemin de code | 🟡 | MVP livré sous `SCA166` (`uUninitVar.pas`) — portée mono-méthode conservatrice sans sensibilité complète aux chemins. Le slot #16 reste `🟡 partiel` jusqu'à la phase 3 (CFG + table de symboles). Voir `Konzept_SCA166_UninitVar.md`. |
| 17 | SCA011 | **DeadCode — code inatteignable** | Instructions après `Exit`, `Break`, `Continue` ou `raise` au même niveau d'imbrication | ✅ | `uDeadCode` |
| 18 | SCA150 | **BoolAlwaysTrue — booléen toujours vrai/faux** | Comparaison telle que `x >= 0` pour un `Cardinal` ou `Length(s) >= 0` — vaut toujours True | ✅ | `uBoolAlwaysTrue` (motif Length uniquement) |
| 19 | SCA144 | **FloatEquality — comparaison de flottants avec =** | `if a = b` où `a` ou `b` est de type `Single`/`Double`/`Extended` | ✅ | `uFloatEquality` |
| 20 | — | **ResultNotChecked — valeur de retour ignorée** | Appel de fonction dont le résultat (p. ex. un code d'erreur) est jeté | 🔲 | |
| 21 | SCA149 | **MissingOverride — `override` manquant** | Une méthode redéfinit une méthode `virtual`/`dynamic` du parent sans `override` | ✅ | `uMissingOverride` (intra-unité uniquement) |
| 22 | — | **CyclicUnitDep — dépendance cyclique entre unités** | L'unité A utilise l'unité B (interface), l'unité B utilise l'unité A (interface) | 🔲 | |
| 23 | SCA145 | **ExceptInDestructor — exception depuis un destructeur** | Le destructeur contient du code susceptible de lever une exception sans try/except | ✅ | `uExceptInDestructor` |
| 24 | — | **PublicFieldNoProperty — champ public au lieu d'une propriété** | Champ `public` exposé directement au lieu d'une `property` avec accesseurs | ✅ | `uPublicField` |
| 25 | SCA139 | **FreeWithoutNil — Free sans mise à nil** | `obj.Free` non suivi de `obj := nil` ou de `FreeAndNil` — dangling pointer possible | ✅ | `uFreeWithoutNil` |

---

## 🟡 Major — Maintenabilité (10)

| # | SCA | Règle | Description | Statut | Unit |
|---|-----|-------|-------------|--------|------|
| 26 | SCA012 | **LongMethod — méthode trop longue** | Le corps de la méthode dépasse 50 lignes exécutables | ✅ | `uLongMethod` |
| 27 | — | **TooManyParams — trop de paramètres** | La méthode a plus de 5 paramètres | ✅ | `uLongParamList` |
| 28 | SCA022 | **CyclomaticComplexity — complexité de McCabe > 10** | Le nombre de chemins de branchement (`if`, branche `case`, `for`, `while`, `repeat`, handler `on`, `and`/`or`/`xor`) dépasse 10 | ✅ | `uCyclomaticComplexity` |
| 29 | SCA018 | **DeepNesting — profondeur d'imbrication > 4** | Bloc de code imbriqué à plus de quatre niveaux | ✅ | `uDeepNesting` |
| 30 | SCA021 | **DuplicateBlock — bloc de code dupliqué** | Un bloc identique (≥ `DuplicateBlockMinLines`, par défaut 8 lignes normalisées) apparaît plus d'une fois dans le même fichier | ✅ | `uDuplicateBlock` (SCA021) — fenêtre glissante par lignes, normalise trim/minuscules/espaces, saute le boilerplate (`begin`/`end`/`else`/`try`/`finally`/`except`, commentaires purs) et les blocs de branchement if/end |
| 31 | SCA138 | **GodClass — classe-dieu** | La classe a plus de 20 méthodes ou plus de 15 champs d'instance | ✅ | `uGodClass` |
| 32 | SCA014 | **MagicNumber — nombre magique sans constante** | Littéral numérique (autre que 0 et 1) utilisé directement dans le code au lieu d'une constante nommée | ✅ | `uMagicNumbers` |
| 33 | SCA146 | **BooleanParam — booléen comme paramètre-drapeau** | La méthode reçoit un paramètre `Boolean` utilisé en interne pour brancher | ✅ | `uBooleanParam` |
| 34 | SCA140 | **MultipleExit — plus de 3 points de sortie** | La méthode contient plus de trois appels `Exit` | ✅ | `uMultipleExit` |
| 35 | SCA141 | **LargeClass — classe trop grosse** | Une unité mono-classe dépasse 500 lignes d'implémentation | ✅ | `uLargeClass` |

---

## 🔵 Minor — Code Smells (10)

| # | SCA | Règle | Description | Statut | Unit |
|---|-----|-------|-------------|--------|------|
| 36 | — | **UnusedVar — variable locale inutilisée** | Variable déclarée dans le bloc `var` mais jamais lue (ou seulement écrite) | ✅ | `uUnusedLocal` |
| 37 | — | **UnusedMethod — méthode privée inutilisée** | Méthode privée jamais appelée dans l'unité | ✅ | `uUnusedPrivateMethod` |
| 38 | — | **UnusedUnit — unité du uses non utilisée** | Unité listée dans `uses` dont aucun symbole n'est référencé | ✅ | `uUnusedUses` |
| 39 | — | **CommentedCode — code mis en commentaire** | Bloc de code Pascal commenté (`//` ou `{ }`) sans explication | ✅ | `uCommentedOutCode` |
| 40 | SCA019 | **TodoComment — TODO/FIXME sans ticket** | Le commentaire contient `TODO`, `FIXME`, `HACK`, `XXX` sans référence à un ticket | ✅ | `uTodoComment` |
| 41 | SCA020 | **EmptyMethod — méthode vide** | La méthode ne contient que `inherited`, ou est complètement vide — un corps avec un commentaire explicatif est déjà conforme et n'est pas signalé | ✅ | `uEmptyMethod` |
| 42 | — | **UnnecessaryCast — transtypage redondant** | Cast vers le même type ou vers un ancêtre direct sans extension | 🔲 | |
| 43 | SCA151 | **ConstantReturn — la méthode renvoie toujours la même valeur** | Chaque chemin renvoie le même littéral — devrait être une constante | ✅ | `uConstantReturn` |
| 44 | — | **LongLine — ligne trop longue** | La ligne dépasse 120 caractères (configurable via `[Detectors] MaxLineLength`) | ✅ | `uTooLongLine` |
| 45 | — | **MixedIndent — indentation mixte (tabulations + espaces)** | La ligne mélange tabulations et espaces dans l'indentation | ✅ | `uTabulationCharacter` |

---

## ⚪ Info (5)

| # | SCA | Règle | Description | Statut | Unit |
|---|-----|-------|-------------|--------|------|
| 46 | SCA152 | **HardcodedString — littéral au lieu d'un resourcestring** | Chaîne visible par l'utilisateur sous forme de littéral au lieu d'une déclaration `resourcestring` | ✅ | `uHardcodedString` (Caption/Hint/Text + ShowMessage) |
| 47 | SCA142 | **UnsortedUses — uses non alphabétique** | Les entrées de la clause `uses` ne sont pas en ordre alphabétique | ✅ | `uUnsortedUses` |
| 48 | SCA143 | **MissingUnitHeader — pas de commentaire de description d'unité** | L'unité commence sans bloc de commentaire descriptif (objet, auteur, date) | ✅ | `uMissingUnitHeader` |
| 49 | — | **DeprecatedAPI — API obsolète utilisée** | Appel d'une méthode ou d'une classe marquée `deprecated` | 🔲 | |
| 50 | SCA148 | **CanBeClassMethod — méthode sans accès à Self** | La méthode d'instance ne touche ni champs ni méthodes d'instance — pourrait être une `class function` | ✅ | `uCanBeClassMethod` |

---

## 🎁 Détecteurs bonus (hors catalogue des 50 règles, mais implémentés)

| Règle | Description | Unit |
|-------|-------------|------|
| **HardcodedPath** | Chemins de fichiers ou de répertoires codés en dur (`C:\…`, UNC, `/usr/…`) | `uHardcodedPath` |
| **DebugOutput** | `WriteLn`, `ShowMessage`, `OutputDebugString`, `InputBox` laissés dans du code de production | `uDebugOutput` |
| **DuplicateString** | Un littéral de chaîne apparaît 3 fois ou plus — à extraire dans une constante | `uDuplicateString` |

---

## État d'implémentation

```
Catalogue Sonar-50
  ✅ Complets :   44  (#1, #2, #3, #4, #5, #6, #7, #8, #9, #10,
                     #11, #12, #13, #14, #15, #17, #18, #19, #21,
                     #23, #24, #25, #26, #27, #29, #31, #32, #33,
                     #34, #35, #36, #37, #38, #39, #40, #41, #43,
                     #44, #45, #46, #47, #48, #50)
                   Les Critical (#6-#15) sont tous faits. #7/#10/#12/
                   #14/#18/#21/#43/#46 utilisent des motifs AST/lexicaux
                   heuristiques aux limites documentées (étroits à dessein).
  🟡 Partiel :     1  (#30 — chaînes uniquement, pas des blocs arbitraires)
  🎁 Bonus :       3  (HardcodedPath, DebugOutput, DuplicateString)
  🔲 Ouverts :     5

  → 48 des 50 règles Sonar couvertes par du code de détecteur AST Pascal,
    dont 45 entièrement complètes.

📐 Détecteurs DFM :                 23 (tous complets)
🛡 Migration SonarDelphi :          12 (SCA120-131, toutes complètes)
🏛 Cluster mORMot :                  9 (SCA153-161, tous complets)
🧩 Nommage/formatage SonarDelphi : 60 (SCA060-119, section ci-dessous)

🎯 Total général : 198 kinds de détecteurs (179 unités de détecteur).
```

---

## 📐 Détecteurs DFM — spécifiques aux fichiers de fiche (hors catalogue Sonar 50)

Ils s'exécutent sur les fichiers `.dfm` avec un lexer DFM + parser
+ graphe de composants dédiés, `TFormBinder` couplant la fiche à
l'AST de son `.pas` compagnon et `TDfmRepoIndex` fournissant des
recherches inter-fiches à l'échelle du dépôt. Tous livrent des astuces
de correction avant/après dans le panneau d'aide et des tests DUnitX.

### Cluster Dead-Wiring (3) — événements / handlers / couplage fiche↔code

| # | SCA | Règle (ID `fk…`) | Description | Type | Unit |
|---|-----|------------------|-------------|------|------|
| D1 | SCA028 | **DfmDeadEvent** | `OnClick` dans le DFM pointe vers un nom de méthode qui n'existe pas dans la section published de la fiche | Bug | `uDfmDeadEvent` |
| D2 | SCA029 | **DfmOrphanHandler** | Méthode published avec la signature `Sender: TObject` qu'aucun composant du DFM ne lie | Code Smell | `uDfmOrphanHandler` |
| D3 | SCA030 | **DfmEmptyBoundEvent** | L'événement est lié, la méthode cible existe, mais le corps est vide / réduit à `inherited` | Code Smell | `uDfmEmptyBoundEvent` |

### Cluster Data-Access (4) — datasets, champs, master-detail

| # | SCA | Règle (ID `fk…`) | Description | Type | Unit |
|---|-----|------------------|-------------|------|------|
| D4 | SCA031 | **DfmSchemaMismatch** | Le `TField`/`TDataSource` du DFM n'a pas de champ published correspondant dans la classe de la fiche | Code Smell | `uDfmSchemaMismatch` |
| D5 | SCA032 | **DfmCircularDataSource** | Cycle dans le graphe `DataSource.DataSet` / `MasterSource` — boucle infinie / débordement de pile à l'exécution | Bug | `uDfmCircularDataSource` |
| D6 | SCA036 | **DfmFieldTypeMismatch** | La classe du contrôle UI ne correspond pas au type de données du `TField` (p. ex. `TDBEdit` lié à `ftBlob`) | Code Smell | `uDfmFieldTypeMismatch` |
| D7 | SCA034/SCA035 | **DfmRequiredFieldUnbound / NotVisible** | Un `TField` avec `Required=True` n'a aucune liaison UI (Unbound) — ou seulement sur un onglet masqué (NotVisible) | Bug | `uDfmRequiredField` |

### Cluster Security (2) — identifiants et injection SQL dans les DFM

| # | SCA | Règle (ID `fk…`) | Description | Type | Unit |
|---|-----|------------------|-------------|------|------|
| D8 | SCA026 | **DfmHardcodedDbCreds** | Identifiants en clair sur une propriété `ConnectionString` / `Params` d'un `TADOConnection` / `TFDConnection` | Vulnerability | `uDfmHardcodedDbCreds` |
| D9 | SCA033 | **DfmSqlFromUserInput** | La propriété SQL d'une requête BD est construite (côté `Pascal`) en concaténant `TEdit.Text` ou une autre saisie UI — smell DFM qui ramène l'analyseur dans l'AST Pascal | Vulnerability | `uDfmSqlFromUserInput` |

### Cluster Layering / Architecture (4) — séparation des responsabilités

| # | SCA | Règle (ID `fk…`) | Description | Type | Unit |
|---|-----|------------------|-------------|------|------|
| D10 | SCA039 | **DfmDbInUiForm** | Un composant BD (`TADOConnection`, `TFDQuery`, `TClientDataSet`, …) est posé directement sur une fiche UI au lieu d'un data module | Code Smell | `uDfmDbInUiForm` |
| D11 | SCA040 | **DfmCrossFormCoupling** | Le code de `Form1` accède à `Form2.<field>` via la variable globale de fiche | Bug | `uDfmCrossFormCoupling` |
| D12 | SCA041 | **DfmLayerViolation** | Un contrôle de saisie est posé directement sur la `TForm` au lieu d'un conteneur Panel / `TFrame` / `TGroupBox` | Code Smell | `uDfmLayerViolation` |
| D13 | SCA038 | **DfmForbiddenClass** | Une classe de composant listée dans `[Components] ForbiddenClasses=` est utilisée dans un DFM. **Actuellement inerte :** aucun code livré ne lit encore cette clé - la liste ne peut être remplie que par programme | Code Smell | `uDfmForbiddenClass` |

### Cluster UI/UX (4) — smells d'interaction dans la définition de la fiche

| # | SCA | Règle (ID `fk…`) | Description | Type | Unit |
|---|-----|------------------|-------------|------|------|
| D14 | SCA027 | **DfmDuplicateBinding** | Plusieurs composants lient le même `OnClick` / le même `DataField`, etc. — le plus souvent un bug de copier-coller | Bug | `uDfmDuplicateBinding` |
| D15 | SCA037 | **DfmTabOrderConflict** | Deux contrôles frères sur le même parent partagent la même valeur `TabOrder` | Code Smell | `uDfmTabOrderConflict` |
| D16 | SCA042 | **DfmGodHandler** | Une méthode liée aux événements de ≥ N composants — un god-handler à scinder par responsabilité | Code Smell | `uDfmGodHandler` |
| D17 | SCA043 | **DfmActionMismatch** | Le composant a à la fois `Action=` et `OnClick=` — le `OnClick` explicite gagne en silence et la glu `TAction` est perdue | Bug | `uDfmActionMismatch` |

### Cluster Naming / Localisation (3) — hygiène

| # | SCA | Règle (ID `fk…`) | Description | Type | Unit |
|---|-----|------------------|-------------|------|------|
| D18 | SCA024 | **DfmDefaultName** | Le composant porte encore son nom par défaut (`Button1`, `Edit2`, …) | Code Smell | `uDfmDefaultName` |
| D19 | SCA025 | **DfmHardcodedCaption** | Chaîne visible dans l'UI (`Caption`, `Hint`, `Text`, …) en littéral dans le DFM au lieu de passer par `resourcestring` / dxgettext | Code Smell | `uDfmHardcodedCaption` |
| D20 | SCA026 | **DfmHardcodedDbCreds extras** | _(voir D8 — même détecteur, kind de résultat distinct pour les valeurs de paramètres vs ConnectionString)_ | Vulnerability | `uDfmHardcodedDbCreds` |

### Cluster composants morts (1) — composants non référencés

| # | SCA | Règle (ID `fk…`) | Description | Type | Unit |
|---|-----|------------------|-------------|------|------|
| D21 | SCA184 | **DfmComponentUnused** | Composant déclaré dans le DFM jamais référencé — ni dans le code de la fiche elle-même, ni depuis une autre unité via la variable globale de fiche (`Form1.Comp`, résolue par `TSymbolReferenceIndex`), ni par un autre composant du DFM (`DataSource=`, `Action=`, …). Probablement mort après un refactoring. Livré en `fcLow` (sous le filtre de confiance `fcMedium` par défaut — opt-in via `--min-confidence low`) ; n'émet rien sans l'index de symboles à l'échelle du dépôt. Les `TField` persistants, les frames embarquées et les unités à `FindComponent` par nom sont délibérément ignorés en v1. Lacune v1 connue : les **mutations** inter-unités où le composant est un maillon intermédiaire de la chaîne (`Form.Comp.Prop := x` / `.Method`) ne sont pas encore reconnues. | Code Smell | `uDfmComponentUnused` |
| D24 | SCA056 | **DfmMasterDetailUnlinked** | Le `TDataSet` a `MasterSource` défini mais ni `MasterFields` ni `IndexFieldNames` — le jeu détail ne filtre jamais | Bug | `uDfmMasterDetailUnlinked` |
| D25 | SCA057 | **DfmDataModuleSplitHint** | Conseil agrégé : la fiche porte ≥ N composants BD — envisager d'extraire un data module | Code Smell | `uDfmDataModuleSplitHint` |

---

## 🛡 Cluster de migration SonarDelphi — correction propre à Delphi (SCA120-131)

Douze vérifications portées depuis le jeu de règles SonarDelphi. Elles
couvrent des lacunes de correction propres à Delphi absentes de la
taxonomie Sonar générique des 50 règles : hygiène exception/raise,
discipline du Result des fonctions, pièges de transtypage autour de
Free / Char / Unicode, et appels de format dépendants de la locale.
Toutes livrent des astuces de correction avant/après dans le panneau
d'aide et une fixture de test DUnitX.

| ID | Règle | Description | Sévérité | Type | Unit |
|----|-------|-------------|----------|------|------|
| SCA120 | **MissingRaise** | `EFoo.Create('msg');` alloue un objet exception sans `raise` — le chemin d'erreur est sauté en silence | Error | Bug | `uMissingRaise` |
| SCA121 | **RoutineResultUnassigned** | Le corps de la fonction se termine sans écrire `Result` (ni `<FunctionName> := ...`) — la valeur de retour est indéfinie | Error | Bug | `uRoutineResultAssigned` |
| SCA122 | **ReRaiseException** | `on E: T do ... raise E;` jette la pile d'appels d'origine — utiliser `raise;` nu pour la conserver | Warning | Bug | `uReRaiseException` |
| SCA123 | **CastAndFree** | `TFoo(x).Free` — le transtypage n'a aucun effet sur le `Destroy` exécuté (`Destroy` est virtuel) | Hint | Code Smell | `uCastAndFree` |
| SCA124 | **InstanceInvokedConstructor** | `obj.Create` — invoque le constructeur comme méthode sur une instance existante, saute l'allocation et réinitialise les champs par-dessus des données vivantes | Warning | Bug | `uInstanceInvokedConstructor` |
| SCA125 | **InheritedMethodEmpty** | Redéfinition dont tout le corps est `inherited;` — ne sert à rien, à supprimer | Hint | Code Smell | `uInheritedMethodEmpty` |
| SCA126 | **NilComparison** | Utiliser `Assigned(x)` / `not Assigned(x)` plutôt que `x = nil` / `x <> nil` — convention Pascal | Hint | Code Smell | `uNilComparison` |
| SCA127 | **RaisingRawException** | `raise Exception.Create('...')` — la classe de base ne porte aucune sémantique, les appelants ne peuvent pas filtrer sélectivement | Warning | Code Smell | `uRaisingRawException` |
| SCA128 | **DateFormatSettings** | `StrToDate(s)`, `FormatFloat(...)`, etc. sans TFormatSettings dépendent de la locale du système — casse d'une machine / d'un utilisateur à l'autre | Warning | Bug | `uDateFormatSettings` |
| SCA129 | **UnicodeToAnsiCast** | `AnsiString(s)` / `RawByteString(s)` / `ShortString(s)` perd en silence les caractères hors de la page de codes active | Warning | Bug | `uUnicodeToAnsiCast` |
| SCA130 | **CharToCharPointerCast** | `PChar('A')` n'est pas `PChar("A")` — le cast traite le point de code 16 bits comme une adresse mémoire brute | Error | Bug | `uCharToCharPointerCast` |
| SCA131 | **IfThenShortCircuit** | `Math.IfThen` / `StrUtils.IfThen` évaluent les deux branches — pas de court-circuit, utiliser `if/then/else` à la place | Warning | Bug | `uIfThenShortCircuit` |

---

## 🏛 Cluster mORMot — motifs concurrence / pointeurs / aliasing (SCA153-161)

Neuf détecteurs ajoutés après un audit des sources de
[mORMot2](https://github.com/synopse/mORMot2), ciblant des motifs récurrents
dans les grandes bases de code Delphi bas niveau : primitives de threading,
allocation brute sur le tas, croissance de tableaux dynamiques, manipulation
de tampons au niveau octet, arithmétique PChar, blocs `with` multi-cibles,
handlers d'exception typés, casts de chaînes depuis des pointeurs bruts,
arithmétique de pointeurs Win64. Tous livrent des astuces de correction
avant/après et une fixture de test DUnitX.

| ID | Règle | Description | Sévérité | Type | Unit |
|----|-------|-------------|----------|------|------|
| SCA153 | **UnpairedLock** | `<id>.Lock` / `EnterCriticalSection` / `TMonitor.Enter` suivi du déverrouillage correspondant dans la même routine sans `try/finally` englobant — le chemin d'exception laisse fuir le verrou et bloque le prochain appelant (deadlock) | Warning | Bug | `uUnpairedLock` |
| SCA154 | **MoveSizeOfPointer** | `Move` / `FillChar` / `CopyMemory` / `ZeroMemory` appelé avec `SizeOf(PXxx)` où `PXxx` est un type pointeur — ne copie que 4/8 octets (la taille du pointeur), pas le tampon visé | Warning | Bug | `uMoveSizeOfPointer` |
| SCA155 | **WithMultipleTargets** | `with A, B do` (deux receveurs ou plus séparés par des virgules) — résolution de membre ambiguë ; ajouter une méthode à A ou à B change en silence le sens du corps | Hint | Code Smell | `uWithMultipleTargets` |
| SCA156 | **GetMemWithoutFreeMem** | `GetMem` / `AllocMem` / `ReallocMem` suivi du `FreeMem` correspondant dans la même routine sans `try/finally` englobant — le chemin d'exception laisse fuir le tampon brut du tas | Warning | Bug | `uGetMemWithoutFreeMem` |
| SCA157 | **SetLengthAppendInLoop** | `SetLength(arr, Length(arr) + N)` dans une boucle `for/while/repeat` — coût de réallocation quadratique ; agrandir une fois avant la boucle ou croître par blocs | Warning | Code Smell | `uSetLengthAppendInLoop` |
| SCA158 | **PointerArithmeticOnString** | `PChar(s) +/- offset` (ou `PAnsiChar` / `PWideChar`) sans vérification préalable que `s` n'est pas vide — `PChar('')` est NIL, l'arithmétique sur nil déclenche une Access Violation | Warning | Bug | `uPointerArithmeticOnString` |
| SCA159 | **EmptyOnHandler** | `on E: SomeException do ;` (ou `begin end` vide) — un handler d'exception typé avale en silence une classe d'exception précise ; pire qu'un `except end` nu car l'annotation de type semble intentionnelle | Warning | Bug | `uEmptyOnHandler` |
| SCA160 | **StringFromPointer** | Le cast `string(P)` / `AnsiString(P)` / `UTF8String(P)` depuis un pointeur préfixé P suppose un terminateur nul — lit au-delà de la fin du tampon si le terminateur manque ; sur-lecture du tas | Warning | Bug | `uStringFromPointer` |
| SCA161 | **PointerSubtraction** | `Cardinal(P1) - Cardinal(P2)` (ou variantes Integer / LongWord / LongInt) tronque les 32 bits supérieurs d'un pointeur 64 bits sous Win64 ; utiliser `PtrUInt` / `NativeInt` | Warning | Bug | `uPointerSubtraction` |

---

## Phases d'implémentation suggérées

```
Phase 1 — Blocker / Critical manquants : #7  UseAfterFree, #15 RaiseWithoutClass
Phase 2 — Major fiabilité              : #16 UninitVar, #20 ResultNotChecked, #25 FreeWithoutNil
Phase 3 — Major maintenabilité         : #28 HighComplexity, #34 MultipleExit, #31 GodClass
Phase 4 — Minor                        : #36 UnusedVar, #39 CommentedCode, #44 LongLine
Phase 5 — Info                         : #47 UnsortedUses, #49 DeprecatedAPI, #50 CanBeClassMethod

DFM phase 1 (faite)   : clusters Dead-Wiring + Data-Access + Security
DFM phase 2 (faite)   : clusters Layering / UI-UX / Naming
DFM phase 3 (ouverte) : proposition de scission en data module, dérive des props design-time,
                        master-detail sans LinkField, redéfinitions de props d'instances de frames
```

---

## 🧩 Style, structure et correction — cluster de première génération (21 règles, reste SCA006–SCA059)

Vérifications issues de la construction d'origine, antérieures aux tables de slots Sonar ci-dessus ; surtout des règles structurelles/stylistiques plus des kinds au niveau pipeline (`SCA006` est émis par l'analyseur lui-même sur les fichiers illisibles). Les kinds DFM de cette plage d'ID vivent dans la section DFM ci-dessus.

| SCA | Règle | Description | Sévérité | Type | Statut | Unit |
|-----|-------|-------------|----------|------|--------|------|
| SCA006 | **FileReadError** | Erreur parseur/E-S - fichier source illisible ou syntaxiquement cassé | Error | File Error | ✅ | `uStaticAnalyzer2` |
| SCA007 | **UnusedUses** | Entrée uses probablement inutilisée (aucun identificateur n'en est référencé) | Hint | Code Smell | ✅ | `uUnusedUses` |
| SCA013 | **LongParamList** | La méthode a plus de paramètres que le maximum configuré (7 par défaut) | Hint | Code Smell | ✅ | `uLongParamList` |
| SCA015 | **DuplicateString** | Le même littéral de chaîne apparaît N fois ou plus - à extraire dans une constante | Hint | Code Duplication | ✅ | `uDuplicateString` |
| SCA016 | **HardcodedPath** | Chemin C:\ / UNC / Linux codé en dur dans la source | Warning | Security Hotspot | ✅ | `uHardcodedPath` |
| SCA017 | **DebugOutput** | Instruction de sortie de débogage trouvée dans une unité de production | Warning | Code Smell | ✅ | `uDebugOutput` |
| SCA023 | **CustomRule** | Motif reconnu par une règle chargée depuis analyser-rules.yml | Warning | Code Smell | ✅ | `uCustomRuleDetector` |
| SCA044 | **ConcatToFormat** | Concaténation de chaînes multi-segments - à extraire dans un appel Format() | Warning | Code Smell | ✅ | `uConcatToFormat` |
| SCA045 | **WithStatement** | Instruction with - piège de masquage de portée dont le compilateur ne prévient pas | Warning | Code Smell | ✅ | `uWithStatement` |
| SCA046 | **ReversedForRange** | for i := 10 to 1 do - le corps de la boucle ne s'exécute jamais | Error | Bug | ✅ | `uReversedForRange` |
| SCA047 | **SelfAssignment** | Auto-affectation - no-op ou faute de copier-coller | Warning | Bug | ✅ | `uSelfAssignment` |
| SCA048 | **VirtualCallInCtor** | Méthode virtuelle invoquée depuis le constructeur - la redéfinition de la sous-classe voit un Self à moitié initialisé | Error | Bug | ✅ | `uVirtualCallInCtor` |
| SCA049 | **LengthUnderflow** | Length / .Count avec soustraction - sous-dépassement d'entier natif non signé quand c'est vide | Hint | Bug | ✅ | `uLengthUnderflow` |
| SCA050 | **CanBeUnitPrivate** | Membre public référencé uniquement dans l'unité courante - le `private` Delphi classique (portée unité) suffit | Hint | Code Smell | ✅ | `uVisibilityCheck` |
| SCA051 | **CanBeProtected** | Membre public référencé uniquement depuis des sous-classes, jamais de l'extérieur | Hint | Code Smell | ✅ | `uVisibilityCheck` |
| SCA052 | **UnusedPublicMember** | Membre public jamais référencé par une sous-classe ni par un chemin inter-unités | Hint | Code Smell | ✅ | `uStaticAnalyzer2` |
| SCA053 | **UnusedLocalVar** | Variable locale déclarée mais jamais référencée dans le corps de la méthode | Hint | Code Smell | ✅ | `uUnusedLocal` |
| SCA054 | **UnusedParameter** | Paramètre de méthode jamais utilisé dans le corps | Hint | Code Smell | ✅ | `uUnusedParameter` |
| SCA055 | **TautologicalBoolExpr** | Opérateur binaire aux côtés gauche et droit identiques : x = x, a and a, (p <> p) | Error | Bug | ✅ | `uTautologicalExpr` |
| SCA058 | **SqlDangerousStatement** | L'instruction SQL modifie toutes les lignes - clause WHERE manquante | Error | Bug | ✅ | `uSqlDangerousStatement` |
| SCA059 | **FormatLocaleHint** | %.2f / %.3f sans TFormatSettings explicite - piège décimal virgule contre point | Hint | Bug | ✅ | `uFormatMismatch` |

---

## 🔤 Nommage, formatage et conventions — cluster compatible SonarDelphi (60 règles, SCA060–SCA119)

Autrefois référencées uniquement via [`rules/sca-rules.json`](rules/sca-rules.json) ; désormais énumérées. Classes multi-kinds : `uVisibilityCheck` (SCA050/051/107), `uPerfHotspots` (SCA110–112), `uRestHttpSecurity` (SCA115/116), `uConcurrencyExt` (SCA113/114).

| SCA | Règle | Description | Sévérité | Type | Statut | Unit |
|-----|-------|-------------|----------|------|--------|------|
| SCA060 | **GotoStatement** | `goto` affaiblit le flot de contrôle structuré - restructurer avec des boucles, `Break`/`Continue` ou une routine extraite | Warning | Code Smell | ✅ | `uGotoStatement` |
| SCA061 | **TabulationCharacter** | Les tabulations s'affichent différemment selon l'éditeur - utiliser des espaces | Hint | Code Smell | ✅ | `uTabulationCharacter` |
| SCA062 | **TooLongLine** | Ligne de plus de 120 caractères - couper ou extraire une sous-expression | Hint | Code Smell | ✅ | `uTooLongLine` |
| SCA063 | **TrailingWhitespace** | La ligne se termine par une espace ou une tabulation - hygiène des diffs | Hint | Code Smell | ✅ | `uTrailingWhitespace` |
| SCA064 | **LowercaseKeyword** | Les mots-clés Pascal (`begin`/`end`/`procedure`/...) devraient être en minuscules | Hint | Code Smell | ✅ | `uLowercaseKeyword` |
| SCA065 | **NoSonarMarker** | Le marqueur `// NOSONAR` ne devrait pas faire taire des résultats - à auditer | Hint | Code Smell | ✅ | `uNoSonarMarker` |
| SCA066 | **EmptyArgumentList** | `Foo()` devrait être `Foo;` - supprimer les parenthèses vides | Hint | Code Smell | ✅ | `uEmptyArgumentList` |
| SCA067 | **InlineAssembly** | Bloc `asm...end` - préférer Pascal + intrinsèques du compilateur | Warning | Code Smell | ✅ | `uInlineAssembly` |
| SCA068 | **TrailingCommaArgList** | `Foo(A, B,)` - supprimer la virgule ou ajouter l'argument manquant | Hint | Code Smell | ✅ | `uTrailingCommaArgList` |
| SCA069 | **DigitGrouping** | Les grands littéraux entiers devraient utiliser le séparateur `_` | Hint | Code Smell | ✅ | `uDigitGrouping` |
| SCA070 | **CommentedOutCode** | Le commentaire ressemble à du code Pascal - supprimer ou documenter | Hint | Code Smell | ✅ | `uCommentedOutCode` |
| SCA071 | **UnitLevelKeywordIndent** | `unit`/`interface`/`uses`/`implementation`/`initialization`/`finalization` devraient commencer en colonne 1 | Hint | Code Smell | ✅ | `uUnitLevelKeywordIndent` |
| SCA072 | **RedundantBoolean** | `X = True` devrait être `X` (idem `X <> False`) | Hint | Code Smell | ✅ | `uRedundantBoolean` |
| SCA073 | **EmptyInterface** | Une interface sans méthodes/propriétés ni ancêtre nommé ne porte aucun contrat | Hint | Code Smell | ✅ | `uEmptyInterface` |
| SCA074 | **AssertMessage** | `Assert(cond);` - ajouter un message `'why'` pour le diagnostic | Hint | Code Smell | ✅ | `uAssertMessage` |
| SCA075 | **ExplicitTObjectInheritance** | `class(TObject)` est redondant - supprimer les parenthèses | Hint | Code Smell | ✅ | `uExplicitTObjectInheritance` |
| SCA076 | **GroupedDeclaration** | Scinder `A, B: Type` en une déclaration par ligne | Hint | Code Smell | ✅ | `uGroupedDeclaration` |
| SCA077 | **EmptyBlock** | `begin..end` vide - le supprimer ou écrire l'instruction | Hint | Code Smell | ✅ | `uEmptyBlock` |
| SCA078 | **ExceptOnException** | `on E: Exception do` avale tout, y compris AV/OOM | Warning | Bug | ✅ | `uExceptOnException` |
| SCA079 | **ConsecutiveSection** | Deux blocs `const`/`type`/`var` consécutifs devraient être fusionnés | Hint | Code Smell | ✅ | `uConsecutiveSection` |
| SCA080 | **RedundantJump** | `Exit;` / `Continue;` juste avant `end` est un no-op (pas : `Exit` hors d'une boucle, et jamais `Break`) | Hint | Code Smell | ✅ | `uRedundantJump` |
| SCA081 | **ClassPerFile** | Une classe par unité facilite le refactoring | Hint | Code Smell | ✅ | `uClassPerFile` |
| SCA082 | **SuperfluousSemicolon** | `;;` - supprimer le point-virgule en trop | Hint | Code Smell | ✅ | `uSuperfluousSemicolon` |
| SCA083 | **EmptyFinallyBlock** | `try ... finally end;` sans nettoyage - le compléter ou supprimer le finally | Warning | Bug | ✅ | `uEmptyFinallyBlock` |
| SCA084 | **AssignedAndAssignedNil** | `Assigned(X) and (X <> nil)` - supprimer le test de nil | Hint | Code Smell | ✅ | `uAssignedAndAssignedNil` |
| SCA085 | **FreeAndNilHint** | Utiliser `FreeAndNil(X)` au lieu de `X.Free; X := nil;` | Hint | Code Smell | ✅ | `uFreeAndNilHint` |
| SCA086 | **AvoidOut** | Préférer `var` à `out` (out a une sémantique surprenante) | Hint | Code Smell | ✅ | `uAvoidOut` |
| SCA087 | **EmptyVisibilitySection** | En-tête de section `public`/`private`/... sans membres | Hint | Code Smell | ✅ | `uEmptyVisibilitySection` |
| SCA088 | **LegacyInitializationSection** | Utiliser `initialization..end.` au lieu du `begin..end.` hérité | Hint | Code Smell | ✅ | `uLegacyInitializationSection` |
| SCA089 | **PublicField** | Un champ public brise l'encapsulation - utiliser une propriété | Hint | Code Smell | ✅ | `uPublicField` |
| SCA090 | **NestedTry** | `try..end` imbriqué - envisager d'extraire le try interne dans une méthode | Hint | Code Smell | ✅ | `uNestedTry` |
| SCA091 | **CaseStatementSize** | `case` avec >= 10 branches - envisager polymorphisme / table de dispatch | Hint | Code Smell | ✅ | `uCaseStatementSize` |
| SCA092 | **EmptyFile** | L'unité n'a ni type/const/var/procedure/function - supprimer ou remplir | Hint | Code Smell | ✅ | `uEmptyFile` |
| SCA093 | **TwiceInheritedCalls** | Deux `inherited;` ou plus dans la même méthode - les effets de bord du parent s'exécutent deux fois | Warning | Bug | ✅ | `uTwiceInheritedCalls` |
| SCA094 | **RedundantParentheses** | `((Ident))` - supprimer les parenthèses extérieures | Hint | Code Smell | ✅ | `uRedundantParentheses` |
| SCA095 | **ConsecutiveVisibility** | La même section `public`/`private`/etc. apparaît deux fois dans une classe | Hint | Code Smell | ✅ | `uConsecutiveVisibility` |
| SCA096 | **ConstructorWithoutInherited** | Constructeur sans `inherited Create` - le parent reste non initialisé | Warning | Bug | ✅ | `uConstructorWithoutInherited` |
| SCA097 | **DestructorWithoutInherited** | Destructeur sans `inherited Destroy` - le nettoyage du parent est sauté (risque de fuite) | Error | Bug | ✅ | `uDestructorWithoutInherited` |
| SCA098 | **RedundantConditional** | `if Cond then X := True else X := False` devrait être `X := Cond` | Hint | Code Smell | ✅ | `uRedundantConditional` |
| SCA099 | **IfElseBegin** | La branche then utilise `begin..end` mais la branche else est une instruction unique | Hint | Code Smell | ✅ | `uIfElseBegin` |
| SCA100 | **PointerName** | `Foo = ^Bar` devrait être `PBar = ^Bar` (convention du préfixe P) | Hint | Code Smell | ✅ | `uPointerName` |
| SCA101 | **BeginEndRequired** | `then`/`else`/`do <stmt>` - préférer un `begin..end` explicite | Hint | Code Smell | ✅ | `uBeginEndRequired` |
| SCA102 | **NestedRoutine** | Procédure/fonction locale imbriquée - extraire au niveau de l'unité | Hint | Code Smell | ✅ | `uNestedRoutines` |
| SCA103 | **FieldName** | Les champs de classe devraient suivre la convention `F<Name>` | Hint | Code Smell | ✅ | `uFieldName` |
| SCA104 | **TypeName** | Les alias de types classe et record devraient commencer par `T` | Hint | Code Smell | ✅ | `uTypeName` |
| SCA105 | **InterfaceName** | Les alias d'interface devraient commencer par `I` (`IFoo = interface`) | Hint | Code Smell | ✅ | `uInterfaceName` |
| SCA106 | **MethodName** | Les méthodes devraient commencer par une majuscule (PascalCase) | Hint | Code Smell | ✅ | `uMethodName` |
| SCA107 | **CanBeStrictPrivate** | Membre public référencé UNIQUEMENT par les méthodes de sa classe déclarante - `strict private` atteint l'encapsulation la plus forte | Hint | Code Smell | ✅ | `uVisibilityCheck` |
| SCA108 | **SynchronizeInDestructor** | Synchronize() appelé depuis le destructeur Destroy - deadlock classique entre thread worker et thread UI | Error | Bug | ✅ | `uSynchronizeInDestructor` |
| SCA109 | **LockWithoutTryFinally** | Verrou TCriticalSection / Monitor / WinAPI pris sans try..finally englobant - une exception laisse le verrou tenu | Error | Bug | ✅ | `uLockWithoutTryFinally` |
| SCA110 | **StringConcatInLoop** | `s := s + x` dans for/while/repeat - réallocations quadratiques | Warning | Code Smell | ✅ | `uPerfHotspots` |
| SCA111 | **ParamByNameInLoop** | `Query.ParamByName('x').AsXxx := ...` dans une boucle - recherche linéaire à chaque itération | Hint | Code Smell | ✅ | `uPerfHotspots` |
| SCA112 | **FieldByNameInLoop** | `DataSet.FieldByName('x').AsXxx` dans une boucle - recherche linéaire à chaque ligne | Hint | Code Smell | ✅ | `uPerfHotspots` |
| SCA113 | **ThreadResumeDeprecated** | `MyThread.Resume` - utiliser `MyThread.Start` (depuis Delphi 2010) | Warning | Code Smell | ✅ | `uConcurrencyExt` |
| SCA114 | **TThreadDestroyWithoutTerminate** | `FreeAndNil(MyThread)` sans `Terminate; WaitFor` préalable - le worker peut encore tourner | Error | Bug | ✅ | `uConcurrencyExt` |
| SCA115 | **HttpInsteadOfHttps** | Littéral `'http://...'` pour un point de terminaison distant - vulnérable au MITM | Warning | Security Hotspot | ✅ | `uRestHttpSecurity` |
| SCA116 | **DisabledTlsVerification** | `SecureProtocols` vide, `IgnoreCertificateErrors := True` ou `OnVerifyPeer := nil` | Error | Vulnerability | ✅ | `uRestHttpSecurity` |
| SCA117 | **PublicMemberWithoutDoc** | Méthode ou propriété publique dans la section `interface` sans commentaire de documentation juste au-dessus | Hint | Code Smell | ✅ | `uPublicMemberWithoutDoc` |
| SCA118 | **ExceptionName** | Un descendant de `class(Exception)` devrait suivre la convention Delphi-RTL `E<Name>` | Hint | Code Smell | ✅ | `uNamingExt` |
| SCA119 | **LocalConstantName** | `const X = 42;` dans une méthode - préférer UPPER_SNAKE_CASE pour les constantes numériques | Hint | Code Smell | ✅ | `uNamingExt` |

---

## 🚀 Ajouts post-1.0 (23 règles — SCA133, SCA147, SCA162–SCA183)

Vagues ultérieures : sécurité/injection, machinerie de suppression, la famille du code inutilisé et le cluster des attributs (SCA180–183).

| SCA | Règle | Description | Sévérité | Type | Statut | Unit |
|-----|-------|-------------|----------|------|--------|------|
| SCA133 | **RaiseOutsideExcept** | `raise;` sans expression d'exception ne fonctionne qu'*à l'intérieur* d'un handler except (re-raise) - ailleurs il lève NIL et produit une Access Violation | Error | Bug | ✅ | `uRaiseOutsideExcept` |
| SCA147 | **UnusedPrivateMethod** | Une méthode privée jamais référencée par une autre méthode de la même unité est du code mort - la supprimer ou la raccorder | Hint | Code Smell | ✅ | `uUnusedPrivateMethod` |
| SCA162 | **InsecureCryptoAlgorithm** | Nom d'algorithme ('MD5', 'SHA1', 'DES', 'RC4', 'TLS1.0', 'SSLv3') ou classe d'enrobage (THashMD5, TIdHashSHA1, ...) référencé - vulnérable aux collisions / attaques à texte clair connu | Warning | Vulnerability | ✅ | `uInsecureCryptoAlgorithm` |
| SCA163 | **CommandInjection** | ShellExecute / CreateProcess / WinExec avec `+` dans les arguments - si un opérande est contrôlé par l'utilisateur, cela devient un vecteur d'injection de commande | Error | Vulnerability | ✅ | `uCommandInjection` |
| SCA164 | **UnusedRoutine** | Procédure/fonction autonome de la section implementation jamais appelée (sur index de mots depuis le 2026-07-19) | Hint | Code Smell | ✅ | `uUnusedRoutine` |
| SCA165 | **UnusedSuppression** | Un marqueur `// noinspection X` ne supprime aucun résultat à sa ligne cible - soit le détecteur s'est amélioré (suppression devenue inutile), soit la cible de la suppression était fausse | Hint | Code Smell | ✅ | `uSuppression` |
| SCA167 | **InsecureRandom** | Random / RandomRange / RandomFrom utilisé sans Randomize - Seed=0 produit la même séquence déterministe à chaque exécution | Warning | Bug | ✅ | `uInsecureRandom` |
| SCA168 | **DefaultCaseInCaseStatement** | L'instruction case n'a pas de branche else - les valeurs non gérées passent en silence ; un else suivant un if dans le dernier bras est le else du case | Hint | CodeSmell | ✅ | `uDefaultCaseInCaseStatement` |
| SCA169 | **AssertWithSideEffect** | Assert(SomeCall) - l'appel disparaît en build Release et son effet de bord est perdu en silence | Warning | Bug | ✅ | `uAssertWithSideEffect` |
| SCA170 | **ConstStringParameter** | Paramètre string déclaré sans const - incrémente le refcount à chaque appel | Hint | CodeSmell | ✅ | `uConstStringParameter` |
| SCA171 | **CompilerDirectiveScope** | {$WARNINGS OFF} (ou HINTS/RANGECHECKS/...) sans ON de fermeture - fuit dans les unités suivantes | Warning | CodeSmell | ✅ | `uCompilerDirectiveScope` |
| SCA172 | **BooleanPropertyNaming** | Le nom d'une propriété booléenne se lit comme un nom commun - préférer un préfixe verbal qui se lit comme une question | Hint | CodeSmell | ✅ | `uBooleanPropertyNaming` |
| SCA173 | **VariantTypeMisuse** | Variable Variant dans une méthode contenant une boucle - chaque opération Variant paie une taxe de dispatch COM de 10 à 100x | Hint | CodeSmell | ✅ | `uVariantTypeMisuse` |
| SCA174 | **TObjectListWithoutOwnership** | TList<TFoo>.Create + Add(TFoo.Create) - la liste ne possède pas ses éléments, chaque instance TFoo fuit | Warning | Bug | ✅ | `uTObjectListWithoutOwnership` |
| SCA175 | **AnonMethodCaptureLoopVar** | Une méthode anonyme dans `for i := ... do` référence i - toutes les fermetures voient la même valeur finale | Error | Bug | ✅ | `uAnonMethodCaptureLoopVar` |
| SCA176 | **CognitiveComplexity** | La complexité cognitive façon Sonar dépasse 15 - des if/for/while/case imbriqués sont durs à suivre mentalement | Warning | CodeSmell | ✅ | `uCognitiveComplexity` |
| SCA177 | **ThreadFreeOnTerminateWithRef** | Après T.FreeOnTerminate := True, tout accès ultérieur T.Field/T.Method risque une Access Violation si le thread s'est déjà auto-détruit | Error | Bug | ✅ | `uThreadFreeOnTerminateWithRef` |
| SCA178 | **PathTraversal** | Appel d'ouverture de fichier (TFileStream.Create, AssignFile, ...) avec une expression de chemin qui concatène une saisie utilisateur (Edit.Text, Request.Params, ...) - risque de path traversal | Error | Vulnerability | ✅ | `uPathTraversal` |
| SCA179 | **AttributeIgnoreWithoutReason** | [Ignore] (sans argument chaîne) saute le test en silence - ajouter un message expliquant pourquoi le test est désactivé | Hint | CodeSmell | ✅ | `uAttributeIgnoreWithoutReason` |
| SCA180 | **AttributeDuplicate** | Deux attributs [X] identiques sur le même membre - reste de copier-coller, sans effet | Warning | CodeSmell | ✅ | `uAttributeDuplicate` |
| SCA181 | **AttributeCategoryWithoutString** | [Category] (sans argument) est une erreur de compilation dans DUnitX - toujours passer un nom de catégorie | Error | Bug | ✅ | `uAttributeCategoryWithoutString` |
| SCA182 | **AttributeTestFixtureWithoutTests** | La classe est marquée [TestFixture] mais ne contient aucune méthode [Test] - fixture zombie visible dans TestInsight qui n'exécute rien | Warning | CodeSmell | ✅ | `uAttributeTestFixtureWithoutTests` |
| SCA183 | **AttributeMisalignment** | Ligne d'attribut suivie d'une ligne vide - visuellement décousu, souvent un reste de refactoring | Hint | CodeSmell | ✅ | `uAttributeMisalignment` |

---

## 🔡 Famille encodage et Trojan Source (9 règles, SCA185–SCA193)

Verdicts d'encodage de fichier au niveau octet (calculés depuis les octets bruts du fichier au chargement, mis en cache dans le cache de texte depuis le travail perf de 2026-07) plus vérifications Trojan Source / abus d'Unicode (CVE-2021-42574).

| SCA | Règle | Description | Sévérité | Type | Statut | Unit |
|-----|-------|-------------|----------|------|--------|------|
| SCA185 | **SourceUtf8NoBom** | Fichier UTF-8 sans BOM + non-ASCII - le compilateur le lit comme de l'ANSI (mojibake) | Warning | Bug | ✅ | `uSourceEncoding` |
| SCA186 | **SourceInvalidUtf8** | UTF-8 malformé (overlong / surrogate / hors plage) sous un BOM UTF-8 | Error | File Error | ✅ | `uSourceEncoding` |
| SCA187 | **SourceControlChar** | NUL / octet de contrôle interdit - fichier binaire ou encodage mal détecté | Error | File Error | ✅ | `uSourceEncoding` |
| SCA188 | **SourceBidiOverride** | Caractère de contrôle bidi override/isolate - la source se lit autrement qu'elle ne compile | Error | Vulnerability | ✅ | `uSourceEncoding` |
| SCA189 | **SourceAnsiNonAscii** | Source 8 bits (pas de BOM, UTF-8 invalide) - dépendante de la page de codes, non portable | Warning | Code Smell | ✅ | `uSourceEncoding` |
| SCA190 | **SourceUtf16** | Source UTF-16 - compile, mais inhabituel et hostile aux outils texte | Hint | Code Smell | ✅ | `uSourceEncoding` |
| SCA191 | **SourceUtf32** | Source UTF-32 - le compilateur Delphi la rejette avec l'erreur fatale F2438 | Error | File Error | ✅ | `uSourceEncoding` |
| SCA192 | **SourceInvisibleChar** | Caractère Unicode invisible/de largeur nulle - vecteur d'abus texte caché / homoglyphes | Warning | Vulnerability | ✅ | `uSourceEncoding` |
| SCA193 | **SourceNonAsciiIdentifier** | Un identificateur contient une lettre non ASCII - risque d'homoglyphes / de caractères confondables | Warning | Vulnerability | ✅ | `uSourceEncoding` |

---

## 🗂️ Portée projet (SCA194–SCA195) — 2 règles

Pas un détecteur AST/par fichier : ne s'exécute que pour les scans `.dproj`/`.groupproj` (CLI `--project`/`--project-group`, ou le dialogue `...`) et compare la liste des fichiers référencés par le projet aux fichiers `.pas`/`.dfm` physiquement présents dans le dossier du projet. Émis par le dispatch du scan (`TAnalysisSession.Run`), filtré par profil + sévérité minimale.

| SCA | Règle | Description | Sévérité | Type | Statut | Unit |
|-----|-------|-------------|----------|------|--------|------|
| SCA194 | **NotIncludedInProject** | .pas/.dfm dans le dossier du projet mais non référencé par le projet (.dproj/.groupproj) - source orpheline / morte | Hint | Code Smell | ✅ | `uNotIncludedInProject` |
| SCA195 | **UsedButNotInProject** | .pas référencé via uses par des unités du projet (compile grâce au chemin de recherche) mais absent du .dproj - à ajouter au projet | Hint | Code Smell | ✅ | `uNotIncludedInProject` |

## 🧪 Initialisation de Result (SCA196) — 1 règle

Les types de retour managés (famille string, tableaux dynamiques, `Variant`, interfaces) sont renvoyés via un paramètre **var** caché qui aliase la variable cible de l'appelant, y compris son ANCIEN contenu — Result n'est PAS `''`/`nil` à l'entrée, et le conseil du compilateur W1035 reste muet précisément pour ces types. Là où SCA196 se déclenche, SCA121 reste muet pour la même fonction.

| SCA | Règle | Description | Sévérité | Type | Statut | Unit |
|-----|-------|-------------|----------|------|--------|------|
| SCA196 | **ManagedResultUninit** | Le Result d'un type de retour managé est lu avant sa première affectation (`Result := Result + [x]`, `Result[i] := ...` sans SetLength, `Result.Add(...)`) - traite les données périmées de l'appelant | Warning | Bug | ✅ | `uManagedResultUninit` |
| SCA197 | **InterfaceWithoutGuid** | Interface déclarée sans GUID - Supports()/QueryInterface() ne peuvent pas la demander à l'exécution | Warning | Code Smell | ✅ | `uInterfaceGuid` |
| SCA198 | **DuplicateInterfaceGuid** | Même GUID sur deux interfaces - Supports() renvoie la première, sans erreur de compilation | Warning | Bug | ✅ | `uInterfaceGuid` |

## ⚙️ Configuration — SCA001 OwnershipSinks (liste blanche des fuites mémoire)

Certaines bases de code confient un objet fraîchement créé à une routine qui en **prend la propriété** (elle l'enregistre dans un conteneur propriétaire, le sérialise puis le libère, l'ajoute à un arbre de builder). SCA001 ne voit pas au-delà de la frontière d'appel et signale donc ces cas comme des fuites alors que l'appelé libère l'objet. Mettez ces routines en liste blanche par projet dans `analyser.ini` :

```ini
[Detectors]
OwnershipSinks=Render,RegisterInstance
```

Passer un objet suivi à une routine listée (`Render(obj)`, `Foo.RegisterInstance(obj)`) compte alors comme un transfert de propriété → pas de résultat SCA001. La correspondance se fait sur le nom de routine (la partie avant `(`), indépendamment du receveur, avec une frontière de mot à gauche pour que `Owner` ne matche jamais `PreOwner(`.

**La valeur par défaut est vide — et c'est voulu.** Un audit en conditions réelles de 1262 résultats SCA001 sur 24 dépôts a montré que les vrais puits de propriété sont **à 100 % spécifiques au framework** — aucun nom de routine ne transfère la propriété d'une base de code à l'autre. Des valeurs par défaut globales ont été rejetées parce que les candidats tentants sont dangereux :

- ❌ **Ne listez jamais `LoadFromStream` / `SaveToStream` / `Assign` / aucun nom de la RTL.** Ces routines *empruntent* leur argument — elles n'en prennent pas la propriété. Les mettre en liste blanche masque de vraies fuites. (L'audit a trouvé de vraies fuites de `TMemoryStream` jamais libérés qu'une telle liste blanche aurait cachées.)
- ✅ Ne listez que les routines dont vous **savez** qu'elles prennent la propriété, et seulement pour le framework qui les définit.

Jeux opt-in recommandés par framework (n'ajoutez que ce que votre projet utilise) :

| Framework | Routines prenant la propriété | Exemple |
|-----------|-------------------------------|---------|
| DelphiMVCFramework | `Render` (sérialise l'objet puis le libère) | `OwnershipSinks=Render` |
| Inspecteur JVCL / DI | `RegisterInstance` | `OwnershipSinks=RegisterInstance` |
| Builders SwagDoc | `AddParameter,AddType,AddLocalVariable` (le nœud parent possède l'enfant) | `OwnershipSinks=AddParameter,AddType,AddLocalVariable` |

Règle empirique : si vous ne pouvez pas montrer la ligne de l'appelé qui libère l'argument, ne le listez **pas**.

## 🧷 SCA001 — quand un *champ* compte comme libéré

La liste blanche ci-dessus concerne les objets dans une variable locale. Un
champ est jugé autrement : SCA001 apparie le constructeur au destructeur et
signale un champ que le constructeur crée et que le destructeur ne libère
pas. « Libérer » est volontairement plus large qu'un `FField.Free` littéral,
car Delphi offre plusieurs façons idiomatiques de confier ailleurs la durée
de vie d'un objet. Le détecteur reste muet quand il peut établir l'un de ces
chemins :

| Chemin | Forme | Pourquoi ce n'est pas une fuite |
|---|---|---|
| Direct | `FField.Free` / `FreeAndNil(FField)` / `FField.Destroy` | le cas évident |
| Propriétaire | `TFoo.Create(Self)`, `Create(AOwner)`, `Create(Self.Owner)` | un propriétaire `TComponent` libère ses enfants ; le premier argument du constructeur est résolu comme expression, donc un propriétaire atteint par un chemin compte aussi |
| Interface | le champ est passé à un puits typé interface | le comptage de références le libère ; un champ typé objet ne le fait jamais, la distinction compte donc |
| Alias local | `L := FField; FField := nil; L.Free` | la même instance, libérée via une locale |
| Alias de propriété | `property Items read FItems` plus `Items.Free` dans le destructeur | la même instance, libérée via son nom public |
| Routine de nettoyage | le destructeur délègue à une méthode de style `Clear`/`Cleanup` qui libère le champ | la libération est à un appel de distance |

Deux de ces chemins sont des conventions plutôt que des preuves, et il vaut
la peine de savoir lesquels :

- L'**alias de propriété** est apparié par nom — un champ `FItems` et une
  propriété `Items` déclarés sur la même classe. Le parseur jette le
  spécificateur `read`/`write`, le détecteur ne peut donc pas vérifier que
  `Items` lit vraiment `FItems`. Il exige les trois conditions : le champ
  commence par `F`, la classe déclare réellement une propriété portant le
  nom restant, et le destructeur libère exactement ce nom. Une propriété
  qui casse la convention *et* qui est libérée sous le mauvais nom serait
  manquée. Les 38 résultats que ce chemin a retirés du corpus d'audit ont
  tous été vérifiés à la source et chacun était un vrai faux positif.
- Le chemin du **propriétaire** fait confiance au premier argument du
  constructeur comme propriétaire quand il se résout en `Self`, `AOwner`
  ou `Owner`. Il ne vérifie pas que la classe construite descend de
  `TComponent`.

Si l'un de vos champs est signalé et que vous le croyez libéré, la réponse
la plus rapide est en général que la libération se produit là où le
détecteur ne peut pas suivre — dans une méthode appelée par le destructeur
via une interface, ou dans une autre unité. Supprimez le résultat sur place
avec `// noinspection MemoryLeak` plutôt que d'élargir `OwnershipSinks`,
qui porte sur des noms de routines entiers.

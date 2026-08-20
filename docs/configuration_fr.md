# Référence de configuration (`analyser.ini`)

🇬🇧 [English version](configuration.md) · 🇩🇪 [Deutsche Fassung](configuration_de.md)

Toutes les clés que l'outil lit dans `analyser.ini`, au même endroit. Le
fichier se trouve dans

```
%APPDATA%\StaticCodeAnalyser\analyser.ini
```

à côté de `ignore.txt`. Il est créé à la première utilisation ; un ancien
`repo.ini` est repris automatiquement. Toutes les clés sont facultatives —
une clé absente signifie la valeur par défaut indiquée ci-dessous.

Le même fichier est lu par l'exécutable autonome, le plugin IDE et la ligne
de commande. Là où les trois diffèrent délibérément, le nom de la clé le dit
(`IdeProfile`, `IdeMinSeverity`). Les options de la ligne de commande
l'emportent sur le fichier, pour l'exécution où elles sont indiquées.

> Les réglages SonarQube ne sont **pas** dans ce fichier — voir
> [sonar-config.md](sonar-config.md).


## `[Rules]`

| Clé | Type | Défaut | Signification |
|---|---|---|---|
| `Profile` | String | _(vide)_ | Profil de règles pour la ligne de commande et l'exécutable autonome. Vide = toutes les règles. |
| `MinSeverity` | String | `hint` | Sévérité la plus basse signalée : `error`, `warning`, `hint`. |
| `MinConfidence` | String | `medium` | Seuil de confiance : `low` désactive le filtre, `medium` est la valeur livrée. |
| `IdeProfile` | String | `ide-fast` | Profil utilisé par le plugin IDE. Reflété dans `Profile` à chaque exécution — sans l'écraser. |
| `IdeMinSeverity` | String | `hint` | Seuil de sévérité du plugin IDE, reflété de la même manière. |
| `EnableDetectorReviewFilter` | Bool | `False` | Filtre optionnel qui masque les règles encore en cours de révision. |

## `[Detectors]`

| Clé | Type | Défaut | Signification |
|---|---|---|---|
| `LeakyClasses` | String | _(vide)_ | Classes supplémentaires que SCA001 considère comme sujettes aux fuites, séparées par des virgules. |
| `ExcludeLeakyClasses` | String | _(vide)_ | Classes retirées de cette liste. |
| `OwnershipSinks` | String | _(vide)_ | Routines qui prennent la propriété d'un objet transmis. Vide par défaut — voir DETECTORS. |
| `AutoDiscoverClasses` | Bool | `False` | Découvrir les classes sujettes aux fuites pendant l'analyse et les journaliser. |
| `CustomRulesFile` | String | _(vide)_ | Fichier YAML de règles personnalisées. |
| `FormatFunctions` | String | _(vide)_ | Fonctions supplémentaires de type `Format` pour la vérification des marqueurs (SCA005). |
| `MagicNumberTrivials` | String | _(vide)_ | Nombres que SCA014 accepte sans constante nommée. |
| `IncludeTests` | Bool | `False` | Analyser aussi les répertoires de tests. Désactivé par défaut — les fixtures produisent du bruit. |
| `UsesCheck` | Bool | `False` | Activer le détecteur coûteux de clauses `uses` inutilisées. |
| `MaxFileMB` | Integer | `5` | Les fichiers plus volumineux sont ignorés. |
| `LongMethodMaxBodyLines` | Integer | `50` | Seuil SCA012 : lignes de corps. |
| `LongMethodMaxStatements` | Integer | `30` | Seuil SCA012 : instructions. |
| `LongParamListMaxParams` | Integer | `5` | Seuil SCA013 : paramètres. |
| `DeepNestingMaxDepth` | Integer | `4` | Seuil SCA018 : profondeur d'imbrication. |
| `CyclomaticMax` | Integer | `10` | Seuil SCA022 : complexité de McCabe. |
| `CognitiveLimit` | Integer | `15` | Seuil SCA176 : complexité cognitive (l'imbrication pèse davantage que chez McCabe). |
| `MaxCaseBranches` | Integer | `10` | Seuil SCA091 : branches `case`. |
| `MaxLineLength` | Integer | `120` | Seuil de la règle sur la longueur de ligne. |
| `DuplicateBlockMinLines` | Integer | `8` | Taille minimale d'un bloc avant qu'une duplication soit signalée. |

## `[Components]`

| Clé | Type | Défaut | Signification |
|---|---|---|---|
| `ForbiddenClasses` | String | _(vide)_ | Classes de composants interdites dans toute DFM ; chaque utilisation est signalée comme SCA038. Séparées par des virgules, insensibles à la casse. Vide laisse la règle silencieuse. |

## `[Baseline]`

| Clé | Type | Défaut | Signification |
|---|---|---|---|
| `File` | String | _(vide)_ | JSON de référence. Les chemins relatifs se résolvent par rapport à la racine de l'analyse ; vide = emplacement standard `.sca`. |
| `OnlyNew` | Bool | `False` | N'afficher que les résultats absents de la base de référence. |
| `PathInFingerprint` | Bool | `False` | Inclure le chemin relatif dans l'empreinte — distingue des fichiers homonymes dans des dossiers différents. |

## `[Score]`

| Clé | Type | Défaut | Signification |
|---|---|---|---|
| `GradeBMax` | Integer | `50` | Score maximal donnant la note B. |
| `GradeCMax` | Integer | `200` | Score maximal donnant la note C. |
| `GradeDMax` | Integer | `500` | Score maximal donnant la note D ; au-delà, la note est E. |

## `[UI]`

| Clé | Type | Défaut | Signification |
|---|---|---|---|
| `Language` | String | `en` | Langue de l'interface : `de`, `en`, `fr`. Vide = paramètres régionaux du système. |
| `Theme` | String | `system` | Thème de l'exécutable autonome : `system` (suivre Windows), `light`, `dark`. |
| `Element.<Nom>` | Bool | `True` | **Coupe-circuit par élément d'interface du plugin IDE.** `0` désactive exactement cet élément sans désinstaller — pour le cas où l'un d'eux perturbe l'IDE. Prend effet après un redémarrage de l'IDE ; les éléments ignorés sont signalés en sortie de débogage (préfixe `SCA-UI`). Noms valides : `SharedUiHooks`, `DockForm`, `LineHighlighter`, `AnnotationOverlay`, `WatchMode`, `WarmUpCaches`, `ViewMenuItem`, `EditorContextMenu`, `OptionsPageSCA`, `OptionsPageSonar`, `FindingsProperties`, `AboutBox`, `ToolsMenuItem`. `PackageWizard` n'est délibérément pas désactivable — il porte le démontage de tous les autres. L'exécutable autonome ignore ces clés. |
| `ClipboardOnClick` | Integer | `1` | Ce qu'un clic sur une ligne copie : `1` rien, `2` mini-ticket Jira, `3` invite Markdown. |
| `EditorColorScheme` | String | `default` | Palette de la bande de marqueurs de l'éditeur et de la barre de titre de la surimpression. |
| `OverlayPosition` | String | `sameline` | Ancrage de la surimpression au survol par rapport à la ligne du résultat. |
| `OverlayShowOnHover` | Bool | `False` | Afficher la surimpression au survol plutôt qu'au clic. |
| `OverlayTextOnly` | Bool | `False` | Remplacer la fenêtre de surimpression par un conseil transparent sur une ligne. |

## `[Silent]`

| Clé | Type | Défaut | Signification |
|---|---|---|---|
| `Enabled` | Bool | `True` | Analyse en arrière-plan du fichier en cours d'édition (plugin IDE). |

## `[Repo]`

| Clé | Type | Défaut | Signification |
|---|---|---|---|
| `BaseBranch` | String | _(vide)_ | Branche de référence pour « Branch-Changes ». Vide = détection automatique. |
| `IncludeWorkingTree` | Bool | `True` | Inclure les modifications non validées dans le diff. |

## `[Paths]`

| Clé | Type | Défaut | Signification |
|---|---|---|---|
| `GitExe` | String | _(vide)_ | Chemin vers `git.exe`. Vide = recherche dans `PATH`. |
| `SvnExe` | String | _(vide)_ | Chemin vers `svn.exe`. Vide = recherche dans `PATH`. |


## `[Editor]` — comment un résultat s'ouvre (exécutable autonome uniquement)

Le plugin IDE saute directement à l'emplacement via la ToolsAPI et ignore
cette section.

| Clé | Type | Défaut | Signification |
|---|---|---|---|
| `ExternalEditor` | String | _(vide)_ | Chemin complet vers un éditeur. S'il est défini, il ouvre **tous** les types de fichiers — y compris `.dfm` — et l'IDE Delphi n'est plus sollicité. |
| `ExternalEditorArgs` | String | `-g "%file%:%line%"` | Arguments. Marqueurs : `%file%`, `%line%`, `%col%`, `%dir%`, `%%`. La valeur par défaut correspond à Visual Studio Code. |
| `DfmTarget` | String | `ide` | Ce qu'ouvre un résultat `.dfm` lorsqu'aucun éditeur externe n'est défini : `ide` ou `viewer` (visionneuse de texte intégrée, qui atteint la ligne de façon fiable). |

## `[Sonar]`

Paramètres de connexion pour le test (`--sonar-test`, « Test Connection »
dans l'EDI) et pour `--sonar-init`. **Aucune de ces clés n'influence
l'analyse ni un détecteur.** Détail complet dans [sonar-config.md](sonar-config.md).

**Cette section a la priorité la plus basse des quatre sources.** Une
option de ligne de commande, une variable d'environnement (`SONAR_HOST_URL`,
`SONAR_TOKEN`, `SONAR_PROJECT_KEY`, `SONAR_ORGANIZATION`, `SONAR_BRANCH`) et
- pour la clé de projet, l'organisation et la branche - un
`sonar-project.properties` dans le dépôt ANALYSÉ l'emportent sur elle.
`--sonar-test` indique quelle source a fourni chaque valeur.

**Le jeton n'est pas ici.** Il réside chiffré dans `[SonarTokens]`, écrit
par la page d'options ou par `--sonar-token`. Sous Windows il est lié à
l'utilisateur et à la machine : un `analyser.ini` copié est inutilisable
ailleurs, et un jeton saisi à la main ne se déchiffre pas. Utilisez
`SONAR_TOKEN` s'il ne doit pas toucher le disque.

| Clé | Type | Défaut | Signification |
| --- | --- | --- | --- |
| `HostUrl` | String | _(vide)_ | URL de base du serveur. Le test y envoie le jeton en en-tête bearer : un hôte erroné reçoit donc le secret. C'est pourquoi un `sonar.host.url` trouvé dans le dépôt analysé est délibérément ignoré. |
| `ProjectKey` | String | _(vide)_ | Le projet que le test interroge. |
| `Organization` | String | _(vide)_ | Clé de locataire SonarCloud. Sans elle SonarCloud répond 400 et le test signale « projet introuvable » alors que le projet existe. |
| `Branch` | String | _(vide)_ | Nom de branche pour la recherche et pour `--sonar-init`. |
| `Insecure` | Bool | `0` | `1` ignore la vérification du certificat TLS du test. Cela affaiblit précisément le transport qui porte le jeton. |
| `TokenRef` | String | _(vide)_ | Nom de l'entrée dans `[SonarTokens]` qui contient le jeton chiffré - un même INI peut ainsi en porter plusieurs. |

## Écrit automatiquement — ne pas modifier

Ces sections sont maintenues par l'application. Une modification manuelle ne
tient pas ; la prochaine fermeture de la fenêtre les écrase.

| Section | Clés | Écrit par |
|---|---|---|
| `[Window]` | `Left`, `Top`, `Width`, `Height`, `Maximized` | exécutable autonome, à la fermeture |
| `[FindingsPropertiesPanel]` | `Left`, `Top`, `Width`, `Height` | plugin IDE, à la fermeture |

## `[PathOverrides]`

Section libre : chaque clé est un fragment de chemin, chaque valeur la
sévérité attribuée aux résultats situés sous ce chemin. Utile pour
déclasser du code tiers ou généré sans l'exclure.

```ini
[PathOverrides]
third_party=hint
generated\=off
```

---

_Clés relevées par un balayage de **tous** les lecteurs de l'INI de
l'arborescence (`uRepoSettings`, `uAppTheme`, `uEditorCommand`,
`uCognitiveComplexity`, `uUiElementRegistry`, …). Si vous ajoutez une clé,
ajoutez-la ici — il n'existe pas encore de générateur pour cette page._

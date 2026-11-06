# Profils d'analyse

Un **profil** est un ensemble de règles nommé. Il répond à une seule
question : *lesquels des 206 détecteurs s'exécutent dans cette analyse ?*
Tout le reste - seuil de sévérité, seuil de confiance, suppressions,
référence - filtre ensuite. Le profil décide de ce qui est cherché au départ.

## Les neuf profils intégrés

| Profil | Règles | À quoi il sert |
|---|---|---|
| `strict` | 206 | Tout ; en ligne de commande, il active en plus SCA007 (uses inutilisés), pas dans l'EXE ni dans le plugin IDE (voir plus bas). C'est de ce profil que dépend la promesse d'exhaustivité - les règles de confiance low exigent tout de même `[Rules] MinConfidence=low`, voir ci-dessous. |
| `default` | 198 | Tout sauf les huit règles de pure convention de `style`. Ces huit-là représentent environ la moitié des remontées sur une grosse base de code - d'où leur absence du profil par défaut. |
| `selftest-quiet` | 195 | Tout sauf onze règles désactivées pour l'auto-analyse (dont `BeginEndRequired`, `TooLongLine`, `UnsortedUses`, `ConcatToFormat`, `NestedTry`). Pas un sous-ensemble de `default` : il garde cinq des règles de `style`. Utilisé quand ce dépôt s'analyse lui-même. |
| `code-quality` | 27 | Maintenabilité : code mort, méthodes longues, complexité, uses inutilisés (SCA007 seulement avec `[Detectors] UsesCheck=1`). |
| `ide-fast` | 21 | Assez léger pour tourner sur chaque fichier ouvert dans l'IDE. Bugs et sécurité, pas de style. |
| `dfm-only` | 20 | Uniquement les contrôles sur les fichiers de fiche. |
| `bugs-only` | 20 | Uniquement les défauts - ni smells, ni conventions. |
| `security` | 9 | Uniquement vulnérabilités et points chauds. |
| `style` | 8 | Les règles de pure convention que `default` laisse de côté. |

Les nombres sont mesurés sur le catalogue actuel, non estimés.

**Seuil de confiance.** Après le profil, `[Rules] MinConfidence` (livré à
`medium`) écarte les résultats sous cette confiance. 24 règles signalent
avec une confiance *low* - dont `TooLongLine`, `UnsortedUses`,
`UseAfterFree` et `AbstractNotImpl` - et restent donc muettes dans tous
les profils, `strict` compris, tant que `MinConfidence=low` n'est pas
réglé. La liste se trouve dans [DETECTORS_fr.md](../DETECTORS_fr.md).

**`strict` et SCA007.** Seule la ligne de commande ajoute SCA007 (uses
inutilisés) à `strict` : `--profile strict`, ou `[Rules] Profile=strict`
dans une exécution CLI, le lance sans `[Detectors] UsesCheck=1`. L'EXE
autonome et le plugin IDE traitent `strict` comme tout autre profil - SCA007
y exige `[Detectors] UsesCheck=1` dans tous les profils.

## Choisir un profil

| Où | Comment |
|---|---|
| Application autonome | Liste déroulante de profil dans la ligne de filtres |
| Plugin IDE | Liste déroulante ; `[Rules] IdeProfile` fixe le défaut du plugin (`ide-fast`) |
| CLI | `--profile <nom>` |
| `analyser.ini` | `[Rules] Profile=<nom>` |

Un nom que le catalogue ne connaît pas est une erreur dans la CLI : qu'il
vienne de `--profile` ou de `[Rules] Profile`, l'exécution s'arrête avant
le scan avec le code 99 et liste les profils connus. La casse et les
espaces autour ne comptent pas. (Jusqu'à 0.9.18, un nom inconnu lançait
silencieusement toutes les règles.)

Les deux interfaces montrent aussi ce qu'il y a *dans* un profil :
**menu burger -> Profils de jeu de règles ...** liste, dans l'application
autonome comme dans le plugin IDE, chaque règle du profil choisi avec son
ID, son jeton de type, sa sévérité et son type. C'est la même fenêtre :
elle vit dans `SCA.SharedUI`, les deux ne peuvent donc pas diverger.

## Où les profils sont définis

Dans `rules/sca-rules.json`, dans le bloc `profiles` :

```json
"profiles": {
  "security": ["SQLInjection", "HardcodedSecret", "CommandInjection"],
  "default":  ["*", "!PublicMemberWithoutDoc", "!NilComparison"]
}
```

Chaque entrée est une liste de jetons, appliqués **de gauche à droite** :

| Jeton | Effet |
|---|---|
| `*` | les 206 types de règles |
| `Kind` | ajouter ce type |
| `!Kind` ou `-Kind` | retirer ce type |

L'ordre compte. `["*", "!LongMethod"]` donne tout sauf une règle ;
`["!LongMethod", "*"]` donne tout, parce que le `*` s'applique en dernier.

## Le jeton est le nom du type, pas l'ID SCA

Un profil liste des **noms de type** (`MemoryLeak`), jamais des ID de
règle (`SCA001`). Le nom de type de chaque règle figure dans la colonne
**Type de règle (jeton de profil)** de la fenêtre des profils, ainsi que
dans [`DETECTORS_fr.md`](../DETECTORS_fr.md).

Un jeton inconnu est **ignoré sans un mot** - aucune erreur, aucun
avertissement. Une faute de frappe ne fait donc rien du tout, en silence.
Après avoir modifié un profil, ouvrez la fenêtre des profils et vérifiez
que le nombre de règles est bien celui voulu.

## Écrire son propre profil

Les profils intégrés ne peuvent pas être modifiés : ils viennent du
catalogue livré et sont réécrits à chaque mise à jour. Votre profil vit
donc dans un fichier à lui, et l'on y arrive en copiant :

1. **Menu burger -> Profils de jeu de règles ...** (application
   autonome ou plugin IDE, au choix)
2. Choisir le profil le plus proche, appuyer sur **Copier ...** et lui
   donner un nom (lettres, chiffres, `-`, `_`, `.`).
3. L'ajuster avec **Ajouter des règles ...** et **Retirer des règles**,
   puis **Enregistrer**.

Votre profil est enregistré dans `profiles.json`, à côté
d'`analyser.ini`, dans `%APPDATA%\StaticCodeAnalyser\`. Aucune mise à
jour ne touche ce fichier.

C'est le **moteur** qui le lit, pas seulement l'application : un profil
construit ici fonctionne aussi avec `--profile <nom>` en ligne de
commande et apparaît dans la liste déroulante du plugin IDE. Il est lu
dans le `%APPDATA%` du compte qui exécute l'outil : un compte de service CI
ne voit pas votre profil, et `--profile <nom>` y termine avec le code 99 -
copiez le fichier (voir plus bas) vers ce compte.

Un nom déjà porté par un profil intégré est refusé. Sinon le même nom
signifierait des choses différentes selon la machine, et comparer deux
exécutions SARIF n'aurait plus de valeur.

### Modifier ce fichier à la main

`profiles.json` utilise la même syntaxe de jetons que le catalogue :

```json
{
  "version": 1,
  "profiles": {
    "my-team": ["MemoryLeak", "SQLInjection", "NilDeref"]
  }
}
```

La fenêtre écrit la liste des types en toutes lettres plutôt qu'un `*`
avec des exceptions : ce que la liste affiche est donc mot pour mot ce
que contient le fichier. Si le fichier ne peut pas être analysé, le
moteur conserve les profils intégrés sans rien dire ; les vôtres
disparaissent simplement jusqu'à la prochaine lecture réussie.

**Le fichier est lu une fois par démarrage du programme.** Un profil
ajouté ou modifié à la main n'apparaît donc pas tout seul. Appuyez sur
**Recharger** dans la fenêtre des profils : il est relu, sans
redémarrer l'application ni l'IDE. Les profils créés *dans* la fenêtre
sont actifs immédiatement ; Recharger ne sert qu'aux modifications
faites à l'extérieur.

## Reprendre un jeu de règles existant

Un `profiles.json` venant d'un collègue, d'un répertoire de projet ou d'un
lecteur partagé n'a pas besoin d'être copié d'abord dans `%APPDATA%`.
**Importer...** dans la fenêtre des profils lit n'importe quel fichier et
en reprend ce qui peut l'être :

* Les deux formes sont acceptées - le fichier complet (`{"version": 1,
  "profiles": {...}}`) et la simple table (`{"mon-equipe":
  ["MemoryLeak", ...]}`).
* Avant toute écriture, la fenêtre indique ce qui va se passer : quels
  profils sont nouveaux, lesquels des vôtres seraient **remplacés** et
  lesquels sont ignorés parce que le nom appartient à un profil intégré.
* Rien n'est écrit avant confirmation.

Les profils repris arrivent dans votre propre `profiles.json`. Ils se
comportent ensuite comme ceux que vous avez créés vous-même - y compris
avec `--profile <nom>` en ligne de commande.

Le dépôt fournit un tel fichier : `reDelphix/data/profile-code-aktionen.json`
contient le profil `code-aktionen`, les règles dotées d'une action de code
de reDelphix plus `FileReadError`. Il ne fait pas partie
des profils intégrés et doit être importé.

## Trouver une règle dans la liste

Les deux listes de la fenêtre des profils - les règles du profil et la
sélection sous **Ajouter des règles...** - disposent d'un champ de
recherche et de colonnes triables :

* Ce qui est saisi dans le champ restreint la liste. La recherche porte
  sur les cinq colonnes à la fois : `SCA047`, `Dfm`, `Leak`, `Warning` et
  `Bug` fonctionnent tous.
* Un clic sur un en-tête trie selon cette colonne, un second inverse le
  sens. L'ID est toujours la clé secondaire - à contenu égal, l'ordre est
  donc toujours le même.
* Dans la sélection, les cases cochées survivent au filtre. Cherchez
  `Dfm`, cochez trois règles, puis cherchez `Leak` et cochez-en deux
  autres - le pied de fenêtre en compte cinq.

## À ne pas confondre : `examples/profile-*.yml`

`examples/profile-security.yml` et ses semblables sont des **fichiers de
règles personnalisées** (`[Detectors] CustomRulesFile=`). Ils ajoutent
vos propres règles à base d'expressions régulières. Ils ne partagent que
le mot « profil » avec cette page : un profil d'analyse choisit parmi les
détecteurs existants, un fichier de règles personnalisées en apporte de
nouveaux.

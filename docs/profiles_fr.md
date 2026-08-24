# Profils d'analyse

Un **profil** est un ensemble de règles nommé. Il répond à une seule
question : *lesquels des 196 détecteurs s'exécutent dans cette analyse ?*
Tout le reste - seuil de sévérité, suppressions, référence - filtre
ensuite. Le profil décide de ce qui est cherché au départ.

## Les neuf profils intégrés

| Profil | Règles | À quoi il sert |
|---|---|---|
| `strict` | 196 | Tout. C'est de ce profil que dépend la promesse d'exhaustivité. |
| `default` | 189 | Tout sauf les sept règles de pure convention de `style`. Ces sept-là représentent environ la moitié des remontées sur une grosse base de code - d'où leur absence du profil par défaut. |
| `selftest-quiet` | 185 | `default` moins quelques règles de formatage. Utilisé quand ce dépôt s'analyse lui-même. |
| `code-quality` | 26 | Maintenabilité : code mort, méthodes longues, complexité, uses inutilisés. |
| `ide-fast` | 20 | Assez léger pour tourner sur chaque fichier ouvert dans l'IDE. Bugs et sécurité, pas de style. |
| `dfm-only` | 20 | Uniquement les contrôles sur les fichiers de fiche. |
| `bugs-only` | 15 | Uniquement les défauts - ni smells, ni conventions. |
| `security` | 7 | Uniquement vulnérabilités et points chauds. |
| `style` | 7 | Les règles de pure convention que `default` laisse de côté. |

Les nombres correspondent à la version 0.9.17, mesurés sur le catalogue.

## Choisir un profil

| Où | Comment |
|---|---|
| Application autonome | Liste déroulante de profil dans la ligne de filtres |
| Plugin IDE | Liste déroulante ; `[Rules] IdeProfile` fixe le défaut du plugin (`ide-fast`) |
| CLI | `--profile <nom>` |
| `analyser.ini` | `[Rules] Profile=<nom>` |

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
| `*` | les 196 types de règles |
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
commande et apparaît dans la liste déroulante du plugin IDE.

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

## À ne pas confondre : `examples/profile-*.yml`

`examples/profile-security.yml` et ses semblables sont des **fichiers de
règles personnalisées** (`[Detectors] CustomRulesFile=`). Ils ajoutent
vos propres règles à base d'expressions régulières. Ils ne partagent que
le mot « profil » avec cette page : un profil d'analyse choisit parmi les
détecteurs existants, un fichier de règles personnalisées en apporte de
nouveaux.

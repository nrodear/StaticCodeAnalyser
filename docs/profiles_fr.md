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

L'application autonome montre aussi ce qu'il y a *dans* un profil :
**menu burger -> Profils de jeu de règles ...** liste chaque règle du
profil choisi avec son ID, son jeton de type, sa sévérité, son type et
son unité de détecteur.

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

Il existe aujourd'hui une voie, et une réserve à connaître avant de
commencer :

1. Ouvrir `rules/sca-rules.json` à côté de l'exécutable.
2. Ajouter une entrée au bloc `profiles`.
3. Redémarrer l'application. Le nom apparaît dans la liste déroulante et
   dans la fenêtre des profils.

**La réserve :** `rules/sca-rules.json` est livré avec le produit et
réécrit à chaque mise à jour. Gardez votre profil dans une copie à part.
Une seconde voie - des profils propres dans un fichier dédié, à côté
d'`analyser.ini` et à l'abri des mises à jour - est prévue comme
deuxième étape de la fenêtre des profils. Les profils intégrés y
resteront en lecture seule.

Si le fichier de catalogue est illisible, le moteur se rabat sur une
liste compilée dans le binaire. Celle-ci ne porte que les profils
intégrés : un profil personnel disparaît donc jusqu'à ce que le fichier
redevienne lisible.

## À ne pas confondre : `examples/profile-*.yml`

`examples/profile-security.yml` et ses semblables sont des **fichiers de
règles personnalisées** (`[Detectors] CustomRulesFile=`). Ils ajoutent
vos propres règles à base d'expressions régulières. Ils ne partagent que
le mot « profil » avec cette page : un profil d'analyse choisit parmi les
détecteurs existants, un fichier de règles personnalisées en apporte de
nouveaux.

# Static Code Analysis Tool for Delphi

[![Offrez-moi un café](https://img.shields.io/badge/%E2%98%95_Offrez--moi_un_caf%C3%A9-paypal.me%2Fnrodear-0070BA?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/nrodear)

[![Licence : MIT](https://img.shields.io/badge/License-MIT-green.svg?style=flat)](LICENSE)
[![PayPal](https://img.shields.io/badge/PayPal-paypal.me%2Fnrodear-0070BA?style=flat&logo=paypal&logoColor=white)](https://paypal.me/nrodear)

> Si ce plugin vous fait gagner du temps dans votre travail Delphi, un café est apprécié. 🙏

---

**Outil d'analyse statique de code Delphi** et **linter** pour **RAD Studio 12
(Athens)** et **13 (Florence)** — livré comme **plugin IDE** avec une fenêtre d'outil
ancrable plus une **application Windows autonome**. L'installateur dessert l'IDE
32 bits de Delphi 12 et les **deux** IDE de Delphi 13, 32 et 64 bits ; l'application
autonome existe en version 32 bits et 64 bits.
Analyse basée sur l'AST avec **196 règles** : 173 contrôles
Pascal pour les fuites mémoire, l'injection SQL, les code smells, les
vulnérabilités de sécurité, l'encodage des fichiers et la sûreté Unicode
(Trojan Source) et la duplication de code
(dont un sous-ensemble **compatible Sonar-Delphi** SCA060+), **plus un
scanner DFM dédié avec 23 contrôles** bâti sur ses propres lexeur + parseur DFM +
graphe de composants, appariés à l'AST Pascal — gestionnaires d'événements morts,
identifiants de base de données en clair dans les fichiers de fiche, câblage
maître-détail circulaire, champs obligatoires de dataset sans liaison UI, SQL
construit à partir de `TEdit.Text`, couplage entre fiches, et plus encore.
Classification de type Sonar avec un Quality Score. Index de fiches à l'échelle
du dépôt pour l'analyse inter-unités. Le mode diff VCS traite les changements
`.dfm` comme déclencheurs pour la `.pas` associée. Rapport HTML avec filtre
groupé `.pas`+`.dfm`. Le plugin IDE ouvre les résultats DFM comme texte
directement dans l'éditeur de code. Copie dans le presse-papiers d'un prompt de
correction Markdown prêt pour l'IA pour n'importe quel résultat (menu
contextuel ; la copie automatique au clic est opt-in). Open source, sous licence MIT.

🇬🇧 [English version](README.md) · 🇩🇪 [Deutsche Fassung](README_de.md)

![SCA en action — analyse, résultats, surimpressions au survol dans l'IDE Delphi](docs/sca-demo.gif)

---

## Ce que fait ce plugin

En une phrase : **une analyse de type Sonar pour les projets Delphi, sans
aucune installation Sonar, directement dans l'IDE, avec passage de relais à Claude AI.**

| Capacité | Détails |
|----------|---------|
| 🐛 **Détection de bugs** | 173 règles Pascal exécutées sur chaque fichier `.pas` (MemoryLeak, NilDeref, DivByZero, FormatMismatch, MissingRaise, RoutineResultUnassigned, CharToCharPointerCast, UnpairedLock, GetMemWithoutFreeMem, PointerArithmeticOnString, …) plus 23 règles DFM sur chaque `.dfm` (gestionnaires d'événements morts, identifiants de base de données en clair, maître-détail circulaire, composants inutilisés, …) — **196 au total**, portées par 156 enregistrements de pipeline |
| 🔐 **Contrôles de sécurité** | SQLInjection (basé sur un score), HardcodedSecret, HardcodedPath ; **sûreté Unicode** — Trojan Source / bidirectional override (CVE-2021-42574), caractères invisibles / à chasse nulle, intégrité BOM / encodage UTF-8 |
| 🧹 **Code smells** | LongMethod, MagicNumber, EmptyExcept, MissingFinally, DeadCode, DuplicateString/Block |
| ⚡ **Analyse incrémentale** | Bouton « Branch-Changes » : uniquement les fichiers modifiés dans la branche Git/SVN — 200 ms au lieu de 60 s |
| 🤖 **Prompt Claude AI** | Copy AI prompt (menu contextuel) → un bloc Markdown complet avec contexte de code + avant/après est copié dans le presse-papiers ; la copie au clic est opt-in via `[UI] ClipboardOnClick` |
| 📊 **Tableau de bord de type Sonar** | Tuiles de statistiques au-dessus de la grille : Erreurs / Avertissements / Conseils / Bugs / Vulnérabilités / Qualité du code en note **A–E** (style Sonar ; score brut + détail dans l'infobulle) |
| 🎯 **Filtrer et trier** | Liste déroulante de sévérité, liste déroulante de type, champ de recherche en direct, en-têtes de colonnes cliquables |
| 📤 **Export** | SARIF, Sonar Generic Issue, rapport HTML autonome et JSON de référence depuis la CLI ; CSV, JSON, markup wiki Jira et remise au presse-papiers depuis la GUI — formats, flux de travail et limites dans [EXPORTS_fr.md](EXPORTS_fr.md) |
| 🔇 **Suppression** | `// noinspection MemoryLeak` par ligne, plus `ignore.txt` pour des fichiers entiers |
| 🌓 **Suivi du thème** | Suit automatiquement le thème actif de l'IDE (Light / Dark / Mountain Mist / Carbon) |
| 💡 **Aide avant/après** | Chaque détecteur possède une paire d'exemples de code « à ne pas faire / à faire » dans le panneau d'aide |

---

## Fonctions principales

### 1. Analyse statique de code (196 règles — 173 Pascal + 23 DFM, taxonomie Sonar)

**Contrôles AST Pascal (~130)** : **bugs** (MemoryLeak, NilDeref, DivByZero,
FormatMismatch, ReversedForRange, SelfAssignment, VirtualCallInCtor,
MissingRaise, RoutineResultUnassigned, ReRaiseException,
InstanceInvokedConstructor, CharToCharPointerCast, UnicodeToAnsiCast,
DateFormatSettings, IfThenShortCircuit, …), **vulnérabilités**
(SQLInjection, HardcodedSecret, DisabledTlsVerification),
**points chauds de sécurité** (HardcodedPath, HttpInsteadOfHttps), **code smells**
(LongMethod, MagicNumber, DeadCode, EmptyExcept, MissingFinally,
CastAndFree, NilComparison, InheritedMethodEmpty, RaisingRawException,
~60 contrôles de nommage/formatage compatibles SonarDelphi SCA060-SCA131, …)
et **duplication de code** (DuplicateString, DuplicateBlock).

**Contrôles DFM (23)** sur le lexeur + parseur de fichiers de fiche dédié +
graphe de composants, appariés à l'AST Pascal via le FormBinder :
gestionnaires d'événements morts, identifiants de base de données en clair
dans les fichiers de fiche, câblage maître-détail circulaire, champs
obligatoires de dataset sans liaison UI, SQL construit à partir de
`TEdit.Text`, couplage entre fiches, raccourcis clavier en double sur les
contrôles, chaînes Caption non traduites, et plus encore. Index de fiches à
l'échelle du dépôt pour l'analyse inter-unités.

Chaque résultat est livré avec une correction avant/après dans le panneau d'aide.

### 2. Analyse incrémentale liée au VCS (Git + SVN)

Épargnez-vous le scan complet du projet. **Un clic sur `Branch-Changes`**
suffit : l'analyseur demande à `git diff` (ou `svn status`) les fichiers
`.pas` touchés dans votre branche et n'exécute les détecteurs que sur eux.
**~200 ms au lieu de 60 s** pour une branche de fonctionnalité typique —
assez peu coûteux pour servir de garde-fou pre-commit. La configuration vit
dans `analyser.ini`. Tous les détails dans [BRANCH_CHANGES_fr.md](BRANCH_CHANGES_fr.md).

### 3. Passage de relais à l'IA (prompt Claude en un clic)

Clic droit sur une ligne de résultat, puis **Copy AI prompt** — le
presse-papiers se remplit d'un **prompt Markdown prêt à l'emploi** :
métadonnées du résultat, contexte de code (±5 lignes, avec un marqueur sur la
ligne fautive) et la correction avant/après. Collez-le dans Claude avec
**Ctrl+V** — l'IA a désormais tout ce qu'il faut pour proposer un correctif concret.

La copie *automatique* au simple clic sur une ligne est **désactivée par
défaut** et se règle via `[UI] ClipboardOnClick` dans `analyser.ini` : `1` =
ne pas toucher au presse-papiers (défaut), `2` = un mini-ticket Jira compact
(titre + 5 puces factuelles), `3` = le prompt Claude complet à chaque
clic. Rien ne quitte jamais votre machine — le texte ne va que dans le
presse-papiers local.

---

## Cas d'usage par mode de déploiement

Le même moteur d'analyse est livré sous **trois formes**, chacune taillée
pour un flux de travail différent. Choisissez selon votre poste du moment :

| Cas d'usage | Plugin IDE | EXE autonome (GUI) | CLI (même EXE) |
|---|:---:|:---:|:---:|
| **Revue en ligne pendant le codage** — voir les marqueurs Bug/Vuln à côté de la ligne que vous venez d'écrire | ✅ grille en direct + bande de 3 px dans l'éditeur + surimpression au survol | — | — |
| **Quick-Fix de la ligne courante** — appliquer une suggestion de correctif sur place | ✅ `Ctrl+Alt+F` | — | — |
| **Naviguer dans les résultats au clavier** | ✅ `Ctrl+Alt+↑/↓` entre les résultats | grille + touches fléchées | — |
| **Supprimer un faux positif sur cette ligne** | ✅ `Ctrl+Alt+S` insère `// noinspection RuleName` | manuel | manuel |
| **Confier un résultat à Claude AI** — prompt Markdown avec contexte de code | ✅ menu contextuel → presse-papiers (ou clic de ligne opt-in) | ✅ menu contextuel → presse-papiers (ou clic de ligne opt-in) | — |
| **Modifications de branche uniquement** — analyser les fichiers touchés depuis `main` / le diff SVN courant | ✅ bouton branche | ✅ bouton branche | ✅ `--branch` ou `--diff <ref>` |
| **Analyser un projet hors de Delphi** (RAD non installé / machine batch) | — | ✅ choisir un dossier, cliquer sur **▶ Analyse** | ✅ `analyser.exe <dossier>` |
| **Exécuter comme hook pre-commit** | — | — | ✅ `--min-severity error --quiet --fail-on error`, le code de sortie reflète la sévérité |
| **Exécuter en CI / GitHub Actions** | — | — | ✅ `--report-sarif sca.sarif`, étape d'upload SARIF |
| **Envoyer les résultats vers SonarQube / SonarCloud** (SCA écrit le fichier, `sonar-scanner` l'importe) | ✅ Export → Sonar | ✅ Export → Sonar | ✅ `--sonar-export sca-findings.json` — voir [EXPORTS_fr.md](EXPORTS_fr.md#workflow-3--sonarqube-dashboard) |
| **Générer un rapport HTML** pour les parties prenantes / pièces jointes Jira | ✅ Export → HTML | ✅ Export → HTML | ✅ `--report-html <fichier>` |
| **Générer un prompt de revue Claude** pour tout le lot (flux Tech-Lead) | ✅ Export → prompt Claude | clic de ligne → presse-papiers | — |
| **Export CSV / JSON / Jira** des résultats | ✅ menu Export | ✅ menu Export | — (GUI uniquement) |
| **Scan nocturne du dépôt entier** + diff contre la référence | — | ✅ planifier via le Planificateur de tâches | ✅ planifier via `cron` / `schtasks` |
| **Analyse automatique à l'enregistrement** (Live-Watch) | ✅ opt-in, voir [Live-Watch](#live-watch-plugin-ide-uniquement--%EF%B8%8F-risqué) | — | — |
| **Créer / éditer des règles personnalisées** (RegEx via l'ini `[CustomRules]`) | ✅ Tools → Options | ✅ boîte de dialogue Paramètres | éditer `analyser.ini` directement |
| **Configurer les seuils des détecteurs** (`LongMethod_MaxLines`, …) | ✅ Paramètres | ✅ Paramètres | éditer `analyser.ini` |
| **Changer la langue de l'interface** (EN / DE) | ✅ Tools → Options | ✅ Paramètres | n/a (la CLI est EN uniquement) |
| **Choisir un profil de jeu de règles** (`ide-fast`, `default`, `strict`) | ✅ liste de profils | ✅ liste de profils | ✅ `--profile <nom>` |
| **Raccourcis clavier configurables** (style cnpack : capturer la touche → stockée dans l'INI) | ✅ Paramètres → Hotkeys | — | — |

### Quel déploiement pour quel rôle

**Développeur au clavier** → plugin IDE. Boucle de retour la plus courte :
marqueurs en ligne, saut à la ligne, Quick-Fix sur place, navigation
Ctrl+Alt, presse-papiers vers Claude. Le plugin partage la MÊME engine + le
même catalogue de règles + les mêmes FixHints que les deux autres — ce que
vous voyez est ce que la CI verra.

**Relecteur de code / Tech-Lead sans RAD Studio ouvert** → GUI autonome.
Même grille, mêmes filtres, même panneau d'aide que le plugin, mais
fonctionne sur un dossier de `.pas`+`.dfm` sans IDE en cours d'exécution.
Utile pour : revue sur une autre machine, batch nocturne sur un serveur de
build sans licence Delphi, remise de l'EXE à un ingénieur non-Delphi pour un
audit ponctuel.

**Pipeline CI / hook pre-commit / tâche planifiée** → mode CLI de la même
EXE. Pas de GUI, le code de sortie reflète la sévérité via `--fail-on <level>`
(0 = propre / sous le seuil, 1 = seuil dépassé). Exports disponibles en
CLI : SARIF (`--report-sarif <fichier>`) pour GitHub Code-Scanning / Azure
Pipelines, JSON Sonar Generic (`--sonar-export <fichier>`) pour les imports
SonarQube. Les exports HTML et prompt Claude sont GUI uniquement. Le filtre
de modifications de branche (`--branch` pour la branche git courante contre
`main`, ou `--diff <ref>` pour une base arbitraire) permet aux builds de PR
de n'analyser que ce que le diff a touché.

**Les trois modes** lisent le même `analyser.ini`, le même
`rules/sca-rules.json`, les mêmes marqueurs de suppression, et émettent les
mêmes types de résultats. Passer de l'un à l'autre est gratuit — un résultat
supprimé dans l'IDE reste supprimé en CI.

---

## Démarrage rapide

1. **Installer** le plugin — trois voies, dans l'ordre recommandé :
   - **EXE d'installation** (recommandé) : télécharger
     `StaticCodeAnalyserSetup-<Version>.exe` depuis les releases GitHub et
     l'exécuter. Installation par utilisateur, aucun droit administrateur
     requis.

     Le setup demande **dans quels IDE** installer et n'affiche que ceux
     qu'il trouve réellement sur la machine :

     | | installe dans | enregistre sous |
     |---|---|---|
     | Delphi 12 (IDE 32 bits) | `bpl\d12` | `BDS\23.0\Known Packages` |
     | Delphi 13 (IDE 32 bits) | `bpl\d13` | `BDS\37.0\Known Packages` |
     | Delphi 13 (IDE 64 bits) | `bpl\d13x64` | `BDS\37.0\Known Packages x64` |

     Seules les cases cochées sont installées, et décocher une version
     déjà installée la supprime — fichier et enregistrement. Le setup
     vérifie aussi qu'aucun IDE Delphi ne tourne, nettoie les
     enregistrements conflictuels du jeu de paquets de développement,
     propose un choix de langue allemand/anglais, affiche la page de
     licence MIT et crée une entrée de désinstallation dans le menu
     Démarrer.
   - **Paquet local GetIt** : télécharger l'asset de release
     `StaticCodeAnalyser-v<V>-getit-manifest.zip`, le décompresser, puis dans
     le GetIt Package Manager choisir **Load Local Package** (en bas de la
     boîte de dialogue ; nécessite une Update Subscription active). La
     charge utile `...-plugin-getit.zip` est récupérée par GetIt lui-même
     via l'URL du manifeste — les deux sont attachés à la release. Cette
     voie installe le plugin Delphi 12.
   - **Compilation maison** : ouvrir
     `StaticCodeAnalyserIDE\StaticCodeAnalyser.IDE.d12.dpk`,
     lancer **Build**, puis **Install** (clic droit sur le paquet dans le
     Project Manager → **Install**, ou menu **Component → Install Packages**
     et choisir le paquet). Sans l'étape d'installation, le plugin compile
     mais n'apparaît jamais dans le menu de l'IDE. Instructions complètes
     dans [HowTo_Build_fr.md](HowTo_Build_fr.md).
2. Dans Delphi : **View → Static Code Analysis Tool for Delphi** — la
   fenêtre ancrable apparaît.
3. Choisir un chemin de projet → cliquer sur **▶ Analyse**.

Pour des scans incrémentaux limités aux fichiers modifiés dans la branche,
voir [BRANCH_CHANGES_fr.md](BRANCH_CHANGES_fr.md).

---

## Ce que contient une release

Chaque release sur la [page des releases](https://github.com/nrodear/StaticCodeAnalyser/releases)
fournit cinq artefacts :

| Artefact | De quoi il s'agit |
|---|---|
| `StaticCodeAnalyserSetup-<V>.exe` | **Installateur du plugin IDE.** Par utilisateur, sans droits administrateur. Choisit les IDE cibles parmi ceux qu'il détecte — Delphi 12 (32 bits) ainsi que Delphi 13 (32 et 64 bits). |
| `StaticCodeAnalyser-v<V>-Win32.zip` | **EXE autonome, 32 bits**, avec le catalogue de règles. Réserve de pile portée à 32 Mo — nécessaire pour les arbres syntaxiques profonds des gros dépôts. |
| `StaticCodeAnalyser-v<V>-Win64.zip` | **EXE autonome, 64 bits.** Le bon choix pour les gros corpus ; l'espace d'adressage y est la limite déterminante. |
| `StaticCodeAnalyser-v<V>-source.zip` | **Sources** à l'état du tag de release. |
| `StaticCodeAnalyser-v<V>-docs-scripts.zip` | **Documentation et exemples CI** — tous les guides en français, anglais et allemand, plus `examples/` (workflow GitHub Actions avec envoi SARIF, hook pre-commit, bot de commentaires PR, cible MSBuild, profils d'analyse). |

Le plugin et l'EXE autonome partagent le même moteur et le même
catalogue de règles ; seule la façon de les piloter diffère.

---

## Intégration Sonar

Les résultats SCA peuvent être exportés comme **external issues** vers
SonarQube / SonarCloud (complémentaire de [SonarDelphi](https://github.com/integrated-application-development/sonar-delphi)
— nos résultats connaissent mORMot, couvrent les fichiers DFM et apportent
des contrôles étrangers à Sonar comme `TautologicalBoolExpr`,
`ConcatToFormat`, `WithStatement`).

> **Testé avec** : SonarQube Community Build 26.5+ (Sonar 10+, mode MQR).
> Les résultats SCA s'importent comme external issues via le Generic Issue
> Format et coexistent avec le profil par défaut intégré de Sonar
> (**Sonar Way**) — aucun conflit, aucun écrasement. Fonctionne aussi bien
> avec SonarQube Server qu'avec SonarCloud.

```powershell
# Configurer une fois (IDE: Tools > Options > Sonar Integration, ou CLI):
analyser.exe --sonar-test `
  --sonar-host http://localhost:9000 `
  --sonar-token squ_xxxxx `
  --sonar-project my-delphi-project

# Lancer l'analyse et produire le Generic Issue Format pour sonar-scanner
analyser.exe --path . --full --sonar-export sca-findings.json
sonar-scanner   # le lit via sonar.externalIssuesReportPaths
```

Chaque règle porte les champs MQR de SonarQube (`cleanCodeAttribute` +
`impacts`), de sorte que les résultats apparaissent correctement dans le
tableau de bord MQR. Le stockage du jeton dans l'IDE utilise Windows DPAPI
(portée utilisateur courant) — aucun secret en clair dans `analyser.ini`.

Installation complète : [docs/sonar-setup.md](docs/sonar-setup.md).
Référence du résolveur de configuration : [docs/sonar-config.md](docs/sonar-config.md).

---

## Ce qui est détecté (196 règles — 173 Pascal + 23 DFM)

Chaque résultat tombe dans l'une des **cinq catégories Sonar** :

| Catégorie | Détecteur | Sévérité |
|-----------|-----------|----------|
| **Bug** | `MemoryLeak` (LeakDetector + FieldLeak) | Erreur / Avertissement |
| | `NilDeref` (déréférencement de nil) | Erreur |
| | `DivByZero` (division par zéro) | Erreur / Avertissement |
| | `FormatMismatch` (format contre nombre d'arguments) | Erreur |
| **Vulnerability** | `SQLInjection` (basé sur un score) | Erreur |
| | `HardcodedSecret` (clés d'API, mots de passe) | Erreur |
| **Security Hotspot** | `HardcodedPath` (`C:\…`, `/etc/…`) | Avertissement |
| **Code Smell** | `EmptyExcept` (exception avalée en silence) | Avertissement |
| | `MissingFinally` (Free hors d'un finally) | Avertissement |
| | `DeadCode` (inatteignable après exit/raise) | Avertissement |
| | `UnusedUses` (optionnel, désactivé par défaut) | Conseil |
| | `LongMethod`, `LongParamList` | Conseil |
| | `MagicNumber` (dans les conditions if) | Conseil |
| | `DebugOutput` (`OutputDebugString`, etc.) | Avertissement |
| | `DeepNesting` | Avertissement |
| | `TodoComment` (TODO/FIXME/HACK) | Conseil |
| | `EmptyMethod` | Conseil |
| **Code Duplication** | `DuplicateString` (même littéral, ≥3 occurrences) | Conseil |
| | `DuplicateBlock` (≥ `DuplicateBlockMinLines`, par défaut 8 lignes identiques) | Conseil |
| **Erreur de lecture** | `FileReadError` (parseur bloqué ou fichier trop gros) | Erreur |

Chaque détecteur vient avec un **exemple de code avant/après** dans le
panneau d'aide. **Copy AI prompt** (menu contextuel) copie dans le
presse-papiers un **bloc Markdown prêt pour Claude AI** ; la copie
automatique au clic sur une ligne est opt-in via `[UI] ClipboardOnClick`
(désactivée par défaut).

Pour les **23 détecteurs spécifiques aux DFM** (DFM-DeadEventHandler,
DFM-HardcodedDBCredentials, DFM-CircularMasterDetail,
DFM-MissingRequiredFieldBinding, DFM-SQLFromTEditText, …) et leurs
astuces de correction : voir [DETECTORS_fr.md](DETECTORS_fr.md).

Statut complet des 50 règles Sonar : voir [DETECTORS_fr.md](DETECTORS_fr.md).

---

## Utilisation

### Boutons (de gauche à droite)

| Bouton | Fonction |
|--------|----------|
| **Sélecteur de dossier** (`...`) | Choisir le dossier du projet |
| **Settings...** | Ouvrir `analyser.ini` — réglages VCS, LeakyClasses personnalisées (voir [BRANCH_CHANGES_fr.md](BRANCH_CHANGES_fr.md)) |
| **Ignore...** | Ouvrir `ignore.txt` — liste d'exclusions de fichiers/dossiers |
| **▶ Analyse** | Scan récursif — ce qui est analysé (dossier / projet / groupe) est indiqué dans l'infobulle du bouton |
| **📄 File** | Uniquement le fichier `.pas` actuellement ouvert dans l'éditeur |
| **Branch-Changes** | Uniquement les fichiers modifiés dans Git/SVN (voir [BRANCH_CHANGES_fr.md](BRANCH_CHANGES_fr.md)) |
| **Cancel** | Interrompt une analyse en cours |

![Plugin IDE SCA en action — boutons, grille, surimpressions au survol](docs/PlugInSca.gif)

### Ouvrir un résultat

Double-cliquez sur une ligne de la grille de résultats. Ce qui se passe
ensuite dépend de `[Editor]` dans `analyser.ini` — relu à chaque
double-clic, les modifications prennent donc effet immédiatement.

| Clé `[Editor]` | Signification |
|----------------|---------------|
| `ExternalEditor` | Chemin complet vers un éditeur. S'il est défini, il prend en charge **tous** les types de fichiers — y compris `.dfm` — et l'IDE Delphi n'est plus sollicité. Vide (défaut) = désactivé. |
| `ExternalEditorArgs` | Modèle d'arguments. Marqueurs : `%file%`, `%line%`, `%col%`, `%dir%`, et `%%` pour un signe pourcent littéral. Tout le reste entre signes pourcent est laissé tel quel. |
| `DfmTarget` | `ide` (défaut) ou `viewer` — ce qu'ouvre un résultat `.dfm` **quand aucun éditeur externe n'est défini**. |

```ini
[Editor]
; Visual Studio Code
ExternalEditor=C:\Program Files\Microsoft VS Code\Code.exe
ExternalEditorArgs=-g "%file%:%line%"
```

Des modèles pour d'autres éditeurs sont listés dans `analyser.ini` même
(Notepad++, Sublime Text, UltraEdit, IntelliJ/Rider). Les valeurs contenant
une espace sont mises entre guillemets automatiquement quand le marqueur
n'est pas déjà entre guillemets — un modèle sans guillemets fonctionne donc
quand même.

**Pourquoi vouloir un éditeur externe.** L'EXE autonome ne peut pas
demander à l'IDE Delphi de sauter à une ligne — RAD Studio n'expose aucune
option de ligne de commande pour cela. Elle remet le fichier au shell
Windows puis simule <kbd>Ctrl</kbd>+<kbd>G</kbd> suivi des chiffres, ce qui
ne fonctionne que tant que l'IDE tient réellement le premier plan. Un
éditeur qui accepte le numéro de ligne en argument touche toujours sa
cible. (Le **plugin IDE** n'a pas ce problème : il navigue directement via
la ToolsAPI et ignore entièrement ces réglages.)

**Résultats `.dfm`.** L'IDE ouvre une `.dfm` dans le concepteur de fiches
selon la façon dont l'extension est enregistrée, et là aucun chemin ne mène
à un numéro de ligne. La visionneuse intégrée affiche le fichier comme
texte et atteint la ligne de façon fiable, mais elle est en lecture seule.
Choisissez avec `DfmTarget`, ou depuis le menu hamburger sous **Ouvrir
les résultats avec**. Si aucun gestionnaire ne répond, la visionneuse est
utilisée de toute façon.

### Configuration par détecteur

Il n'y a pas de cases à cocher dans la barre d'outils. Tout comportement
optionnel des détecteurs se configure via `analyser.ini` (voir _Fichiers de
configuration_ plus bas) — ouvrez-le via le bouton **Settings…**, éditez,
enregistrez, cliquez à nouveau sur **▶ Analyse**. Les réglages sont
rechargés à chaque exécution, aucun redémarrage de l'IDE n'est nécessaire.

### Cartes de statistiques

Deux rangées de cartes au-dessus de la grille montrent la répartition des
résultats :

- **Par sévérité** : Erreurs / Avertissements / Conseils / Risques de sécurité / Erreurs de lecture
- **Par type** : Code Smell / Bug / Vulnerability / Security Hotspot / Code Duplication / Erreurs de lecture

Les deux rangées totalisent, à coup sûr, le même nombre.

Une **tuile Quality Score** à côté d'elles montre la qualité du code en
note **A–E** (style Sonar) ; le score brut et son détail apparaissent dans
l'infobulle de la tuile.

### Filtres

- **Listes déroulantes sévérité / type** : restreignent la grille à une seule catégorie.
- **Liste déroulante de profil** : change le jeu de règles actif à la
  volée. Profils fournis : `ide-fast` (défaut de l'IDE — bugs + vulns
  uniquement), `default` (tout sauf les sept règles de pure convention),
  `strict` (vraiment tout), `style` (exactement ces sept), `security`
  (vulns + hotspots uniquement), `bugs-only`, `code-quality`, `dfm-only`.
  Les profils vivent dans `rules/sca-rules.json` sous `profiles` et la
  liste déroulante s'en nourrit — déposez votre propre profil dans le JSON
  et il apparaît. La sélection est persistée dans `[Rules] IdeProfile` et
  prend effet à la prochaine exécution de l'analyse.
- **Champ de recherche** (`Filtrer fichier / méthode / résultat`) : filtre
  en direct sur toutes les colonnes.

### Interaction avec la grille

| Action | Effet |
|--------|-------|
| **Clic sur une ligne** | Affiche le résultat dans le panneau d'aide ; si le fichier est ouvert dans l'IDE, une bande de 3 px est peinte au bord gauche de la ligne correspondante dans l'éditeur. Ce qui atterrit dans le presse-papiers est contrôlé par `[UI] ClipboardOnClick` : `1` = rien (défaut), `2` = mini-ticket Jira, `3` = prompt Markdown pour Claude AI — en mode 3, un fournisseur de Quick-Fix (`RedundantBoolean`, `FreeAndNilHint`, `EmptyArgumentList`, `AssignedAndAssignedNil`) préfixe la ligne corrigée comme bloc de code prêt à coller. |
| **Clic droit → Copy AI prompt** | Copie le prompt Markdown Claude AI (bloc Quick-Fix inclus) — toujours, quel que soit `ClipboardOnClick`. |
| **Double-clic / Entrée** | Ouvre le fichier dans l'IDE, saute à la ligne du résultat, peint le marqueur de ligne |
| **Ctrl+Alt+F** | **Appliquer le Quick-Fix dans l'éditeur** (remplacement sur place via IOTAEditWriter, Ctrl+Z pour annuler). Uniquement pour les règles avec un fournisseur enregistré. La barre d'état rapporte le résultat. |
| **Ctrl+Alt+S** | **Insérer le marqueur de suppression** au-dessus de la ligne du résultat : `// noinspection <RuleName>`. La prochaine analyse filtre le résultat. Ctrl+Z pour revenir en arrière. |
| **F3 / Maj+F3** | Résultat suivant / précédent dans la grille |
| **Survol (colonne fichier)** | Infobulle avec le chemin complet du fichier (délai de 100 ms) |
| **Clic sur un en-tête de colonne** | Trie selon cette colonne |
| **Bande de 3 px au bord gauche** de la ligne de grille | Accent de sévérité (rouge / orange / vert / bleu) |

Le **panneau d'aide** à droite, avec les blocs de code avant/après, n'est
affiché que lorsque la fenêtre du plugin IDE est **flottante** — une fois
ancrée dans une barre latérale ou un onglet, le panneau se masque et la
grille prend toute la largeur (il réapparaît en ~250 ms après le désancrage).

![Plugin IDE SCA ancré dans un panneau latéral — panneau d'aide masqué, grille pleine largeur](docs/PlugInDockedSca.gif)

### Export

| Bouton | Format | Contenu |
|--------|--------|---------|
| **JSON** | `.json` | Tous les résultats sous forme de tableau |
| **CSV** | `.csv` | Compatible Excel (séparé par des points-virgules) |
| **Rapport HTML** | `.html` | Rapport autonome avec tri, filtres, extraits de code, avant/après. Cliquer sur un badge de sévérité filtre — et masque aussi, dans la liste déroulante, les fichiers sans résultat de cette sévérité (combinable avec le filtre de fichiers, lié par ET) |
| **Jira** | Presse-papiers | Markup wiki prêt à coller dans un ticket Jira (filtré sur un fichier) |
| **Clipboard** | Presse-papiers | Texte brut avec avant/après (filtré sur un fichier) |

### Panneau File-Findings (ancrage par fichier)

Une deuxième fenêtre ancrable qui se concentre sur le **fichier actuellement
actif dans l'éditeur**. S'ouvre via **View → Static Code Analysis - File**.
Conçue pour un ancrage latéral à côté de l'éditeur, afin de toujours voir
les résultats du fichier sur lequel vous travaillez.

| Propriété | Comportement |
|---|---|
| **Déclencheur** | Analyse automatiquement le fichier actif à l'ouverture et à chaque changement d'onglet. Aucun clic « fichier courant » nécessaire |
| **Mise à jour en direct** | Si le mode watch est actif, les déclencheurs save/edit réalimentent aussi le panneau |
| **Colonnes de la grille** | Method / Line / Type / Rule / Severity (Rule s'étire ; barre d'accent de sévérité à gauche de chaque ligne) |
| **Filtre** | Liste avec *All severities* / *Errors only* / *Errors + Warnings* |
| **Tri** | Clic sur un en-tête de colonne pour trier (bascule croissant/décroissant) |
| **Clic sur une ligne** | Saute à la ligne du résultat dans l'éditeur (navigation douce, ne ferme/rouvre pas le fichier) |
| **.pas + .dfm** | Traités comme une seule cible d'analyse — basculer d'onglet entre les deux garde les résultats visibles |
| **Mémoire de position** | Se rouvre à la dernière position (persistée en session via `analyser.ini`, entre sessions via IDE Save Desktop). Repli : centré sur la fenêtre principale de l'IDE quand rien n'est stocké ou que la position est hors écran |
| **Thème + police** | Suit le thème actif de l'IDE (clair/sombre/personnalisé) et la police du plugin (Segoe UI 8) |

---

## Langue / localisation

La langue source de l'interface est l'**anglais**. Les chaînes de l'UI sont
enveloppées dans la macro `_('…')` de `uLocalization.pas`, qui passe par
dxgettext (GNU gettext pour Delphi) lorsqu'il est activé.

### Changer de langue

| État | Effet |
|------|-------|
| **Défaut (pas de dxgettext)** | L'UI affiche les chaînes source telles quelles — anglais |
| **dxgettext activé, aucun appel à `SetLanguage`** | L'UI suit les paramètres régionaux du système via `gnugettext.UseLanguageFromSysLocale` |
| **`uLocalization.SetLanguage('de')`** | L'UI passe en allemand via `i18n/de.po` |
| **`uLocalization.SetLanguage('fr')`** | L'UI passe en français via `i18n/fr.po` |
| **`uLocalization.SetLanguage('en')`** | UI forcée en anglais |

Pour définir la langue au démarrage, appelez `SetLanguage` tôt dans
`TAnalyserDockableForm.FrameCreated` (plugin IDE) ou dans le
`TForm2.FormCreate` de l'autonome :

```pascal
uses uLocalization;

SetLanguage('de');   // 'de' / 'en' / 'fr' / '' (= défaut du système)
```

### Où vivent les traductions

| Chemin | Rôle |
|--------|------|
| `i18n/template.pot` | Modèle de la langue source (anglais) |
| `i18n/de.po` | Traduction allemande |
| `i18n/fr.po` | Traduction française |
| `i18n/en.po` | Base anglaise (identité) |
| `locale/<lang>/LC_MESSAGES/default.mo` | Binaire compilé, chargé à l'exécution |

Les fichiers `.po` sont du texte brut, adaptés à Git ; éditez-les avec
[poEdit](https://poedit.net/) ou un éditeur ordinaire.

### Activer dxgettext (installation unique)

Sans dxgettext installé, l'enveloppe est un simple passe-plat — chaque
appel à `_()` renvoie la chaîne source inchangée, l'UI reste donc en
anglais quel que soit l'argument passé à `SetLanguage`.

Pour obtenir de vraies traductions :

1. Cloner <https://github.com/sjrd/dxgettext>
2. Ajouter le dossier `dxgettext/Source/` au `DCC_UnitSearchPath` du
   plugin IDE et de l'EXE autonome
3. Ajouter `{$DEFINE USE_GETTEXT}` dans le `.dpk` (ou dans **Project
   Options → Conditional Defines**)
4. Compiler chaque `.po` en `.mo` :
   ```
   msgfmt i18n/de.po -o locale/de/LC_MESSAGES/default.mo
   msgfmt i18n/fr.po -o locale/fr/LC_MESSAGES/default.mo
   ```
5. Placer le dossier `locale/` à côté du BPL/EXE

Les traductions elles-mêmes sont les fichiers `.po` sous
[i18n/](i18n/) — c'est l'unique source. Après en avoir modifié un, lancez
`python tools/gen_po_inc.py` pour régénérer la copie compilée, puis faites
un **Clean + Build** : l'IDE ne suit pas les dépendances `.inc` de façon
fiable et lierait sinon le texte précédent.

---

## Intégration du thème

### EXE autonome : clair / sombre

L'EXE suit par défaut le **thème d'application Windows** et peut être
épinglée via le menu hamburger sous **Appearance** (*Comme Windows* /
*Clair* / *Sombre*) ou dans `analyser.ini` :

```ini
[UI]
; system = suivre Windows (défaut), light, dark
Theme=system
```

Chaque clé de `analyser.ini` - seuils, profils, référence, interface - est
listée avec sa valeur par défaut dans la
[référence de configuration](docs/configuration_fr.md).

Le style sombre est embarqué dans l'EXE — aucune option de projet VCL-Style
impliquée. En mode `system`, un changement de thème Windows prend effet
immédiatement (l'EXE écoute le broadcast) ; aucun redémarrage nécessaire.
Le menu écrit exactement la même clé INI, le réglage peut donc aussi être
déployé en distribuant `analyser.ini`.

### Tri de la grille de résultats (EXE)

Cliquez sur un en-tête de colonne pour trier ; cliquez à nouveau pour
inverser. La flèche dans l'en-tête montre la colonne active et le sens.
*Severity* trie par rang (Error > Warning > Hint), pas alphabétiquement. Un
double-clic sur la ligne d'en-tête ne fait que basculer deux fois — il
n'ouvre jamais un résultat.

### Plugin IDE

Le plugin suit le thème actif de l'IDE Delphi par plusieurs mécanismes :

- **`StyleServices.GetSystemColor`** dans le dessin personnalisé (OnDrawCell, TTilePanel.Paint)
- **`clBtnFace` / `clWindow` / `clBtnText`** comme valeurs de propriétés (thémées automatiquement via VCL Styles)
- **`IOTAIDEThemingServices.ApplyTheme`** lorsque le frame est hébergé
- **`INTAIDEThemingServicesNotifier`** pour les changements de thème en direct
- **`CM_STYLECHANGED`** plus un **override de `SetParent`** comme déclencheurs supplémentaires

Les couleurs de fond de sévérité sont mélangées au moment du dessin à
partir de la base thémée `clWindow` et d'une couleur d'accent saturée — le
même code fonctionne donc dans n'importe quel thème, sans tables
clair/sombre séparées.

**Limitation connue** : en mode flottant, la fenêtre du plugin ne reprend
pas de façon fiable les changements de thème de l'IDE à l'exécution —
`INTACustomDockableForm` n'expose aucun crochet officiel pour réappliquer
le thème sur la fiche enveloppe. Contournement : ancrer le plugin, ou
fermer et rouvrir la fenêtre après le changement de thème.

---

## Périmètre d'analyse : dossier, projet ou groupe de projets (CLI)

Au-delà du scan récursif de dossier (`--path <dir>`), la CLI peut analyser
exactement ce qu'un fichier de projet Delphi référence. Les options
d'entrée `--path`, `--file`, `--project` et `--project-group` s'excluent
mutuellement (les combinaisons invalides terminent avec le code 99) :

- `--project <file.dproj>` — analyse exactement les fichiers `.pas` listés
  dans le `.dproj` (sa liste DCCReference). Les unités uniquement
  atteignables via les chemins de recherche ne sont **pas** incluses.
- `--project-group <file.groupproj>` — analyse l'union de tous les projets
  du groupe, dédupliquée.
- `--index-root <dir>` — construit l'index inter-unités (utilisé par la
  famille de détecteurs unused/référence) sur ce répertoire, tout en
  n'analysant que la liste de fichiers résolue. Défaut : la racine commune
  de la liste résolue. Également valable avec `--branch`/`--diff`.

```powershell
analyser.d12.exe --project D:\repo\MyApp\MyApp.dproj --report-sarif sca.sarif
analyser.d12.exe --project-group D:\repo\All.groupproj --report-sarif sca.sarif

# Analyse limitée au projet, mais indexation du dépôt entier pour que les
# verdicts « unused » voient les consommateurs hors du projet :
analyser.d12.exe --project D:\repo\MyApp\MyApp.dproj --index-root D:\repo
```

Deux choses à savoir :

- **Le plugin IDE et la CLI peuvent rapporter des nombres de résultats
  différents pour le « même » projet — c'est voulu.** Le plugin lit l'état
  vivant du projet depuis la ToolsAPI (y compris les changements
  d'appartenance non enregistrés), la CLI parse le `.dproj` sur le disque ;
  la configuration côté consommateur diffère également. N'attendez pas que
  les nombres coïncident, et n'ajustez pas l'un sur l'autre.
- **Les références sont liées au périmètre d'analyse.** Une référence
  écrite depuis un scan de dossier ne convient pas à un scan de projet
  (ensemble de fichiers différent → ensemble d'empreintes différent).
  Gardez une référence par périmètre sur lequel vous posez un garde-fou.

---

## Utiliser l'analyseur avec Git et SVN

L'analyseur **détecte automatiquement** le système VCS d'après le
répertoire du projet (il cherche les marqueurs `.git/` ou `.svn/`). Les
règles personnalisées et toute la configuration des détecteurs sont
**agnostiques au VCS** — le même flux de travail marche avec les deux systèmes.

### Détection automatique

| Marqueur dans le chemin du projet | Détecté comme | CLI utilisée |
|---|---|---|
| `.git/` (ou un parent contient `.git/`) | Git | `git diff` + `git status` |
| `.svn/` | SVN | `svn status` + `svn diff` |
| aucun | Aucun | `--branch` désactivé, `--full` fonctionne |

L'exécutable VCS est localisé via `PATH`, puis les chemins d'installation
typiques (TortoiseGit, TortoiseSVN, Git for Windows, ...). Surcharge via
`analyser.ini` (voir plus bas).

### Utilisation avec Git

**Plugin/GUI** : pointer le chemin du projet sur l'arbre de travail Git,
puis cliquer sur **Branch-Changes**. L'analyseur détermine :
- les fichiers `.pas` modifiés entre `BaseBranch` et `HEAD` (validés)
- plus les modifications non validées de l'arbre de travail (quand `IncludeWorkingTree=1`)

**CLI** :
```powershell
analyser.d12.exe --path D:\my-git-repo --branch --report-sarif sca.sarif

# Optionnel : restreindre le jeu de règles via profil + sévérité minimale
analyser.d12.exe --path . --profile security --report-sarif sec.sarif
analyser.d12.exe --path . --profile bugs-only --min-severity warning
```

> **Premier lancement : si vous obtenez `0 findings`, vérifiez la ligne de
> filtre.** Avec le profil `default`, l'outil masque les résultats dans les
> fichiers ressemblant à des fixtures de test — `uTest*.pas`, `*_Test.pas`,
> `*Sample.pas`, `*Demo.pas`, `MeineUnit.pas`. Si votre première expérience
> s'appelle justement `Demo.pas`, elle est filtrée. Le scan indique quels
> fichiers il a écartés ; `--show-test-fixtures` les conserve,
> `--profile strict` désactive entièrement le filtre.

Le filtre est actif automatiquement pour `--profile default` et
`selftest-quiet`, et inactif pour tout autre profil. Les deux options
priment sur le profil : `--show-test-fixtures` conserve les résultats des
fixtures même sous `default`, `--hide-test-fixtures` les écarte même sous
`strict` ou `security`. Comme le filtre s'exécute avant le calcul du code
de sortie, il compte en CI, pas seulement à l'écran.

### Compilation conditionnelle (`{$IFDEF}`)

Par défaut, l'analyseur lit **chaque** branche `{$IFDEF}`, y compris le
code qui ne compile jamais pour votre cible — une source fréquente de
résultats étranges (déclarations en double, branches mortes). Trois
options changent cela :

| Option | Effet |
|---|---|
| `--ifdef-aware` | Ignore les branches `{$IFDEF X}` dont le `X` n'est pas dans le jeu de defines. Automatiquement actif pour `--profile selftest-quiet`, inactif sinon. |
| `--define X[,Y,Z]` | Le jeu de defines. Répétable ; les valeurs s'accumulent. |
| `--no-ifdef-aware` | Force la réactivation de toutes les branches. Gagne contre `--ifdef-aware`, quel que soit l'ordre sur la ligne de commande. |

Elles n'ont de sens qu'ensemble : **`--ifdef-aware` sans `--define` tourne
avec un jeu de defines vide**, presque chaque branche conditionnelle est
donc jetée — et le mode de défaillance n'est pas un message d'erreur, mais
des résultats qui manquent en silence. Donnez-lui les defines que votre
build utilise réellement :

```powershell
analyser.d12.exe --path . --full --ifdef-aware `
  --define MSWINDOWS,WIN64,UNICODE,CONDITIONALEXPRESSIONS
```

### Référence complète des options

`analyser.d12.exe --help` (aussi `-h`, `-?`, `/?`) imprime chaque option
avec son explication et sort avec 0, il est donc sans danger de l'appeler
depuis un script. `--version` imprime seulement la version. Les deux sont
la liste faisant foi — ce README couvre les options dans le contexte d'une
tâche, le texte d'aide les couvre toutes.

`--profile <name>` accepte n'importe quel profil de `rules/sca-rules.json`
(fournis : `default`, `strict`, `style`, `ide-fast`, `security`,
`bugs-only`, `code-quality`, `dfm-only`). **`default` laisse délibérément de
côté sept règles de pure convention** — documentation des membres publics,
`Assigned()` contre `<> nil`, `begin..end` sur les branches à instruction
unique, `begin..end` asymétrique autour de `if`/`else`, `with`, une classe
par unité et captions DFM en dur. Ce sont des résultats corrects, mais ce
sont des conventions,
et ensemble elles représentaient 48 % de tout ce qu'un nouveau venu voyait.
`--profile style` active exactement celles-ci ; `--profile strict` active
tout. `--min-severity hint|warning|error` saute les
détecteurs sous le seuil. Les deux options priment sur `[Rules]` dans `analyser.ini`.

**Réglages `analyser.ini` pour Git** :
```ini
[Repo]
; vide = auto : origin/HEAD -> main -> master
BaseBranch=develop
; 1 = inclure les modifications non validées, 0 = validées uniquement
IncludeWorkingTree=1

[Paths]
; vide = détection automatique
GitExe=C:\custom\git\bin\git.exe
```

> **Les commentaires vont sur leur propre ligne.** Un `;` *après* une
> valeur n'est pas retiré — il devient partie de la valeur.
> `BaseBranch=develop ; auto` demande à Git une branche littéralement
> nommée `develop ; auto`.

### Utilisation avec SVN

**Plugin/GUI** : identique à Git — choisir le chemin de la copie de
travail, cliquer sur **Branch-Changes**. Comme SVN n'a pas de vrai concept
de « branche » dans une copie de travail, le mode branche renvoie ici :
- toutes les modifications non validées (sortie `svn status` : M/A/R/D/?)
- optionnellement étendues des différences validées depuis la révision BASE

Idéal comme **hook pre-commit** : il vérifie exactement ce qui partirait
dans le prochain `svn commit`.

**CLI** :
```powershell
analyser.d12.exe --path D:\my-svn-wc --branch --report-sarif sca.sarif
```

**Réglages `analyser.ini` pour SVN** :
```ini
[Repo]
BaseBranch=trunk            ; SVN : typiquement trunk (informatif, pas de vrai diff)
IncludeWorkingTree=1        ; inclure les modifications non validées

[Paths]
SvnExe=C:\custom\svn\bin\svn.exe   ; vide = auto : PATH + TortoiseSVN
```

**Chemins SVN détectés automatiquement** :
1. `svn.exe` dans le PATH
2. `C:\Program Files\TortoiseSVN\bin\svn.exe`
3. `C:\Program Files (x86)\TortoiseSVN\bin\svn.exe`
4. `C:\Program Files\Subversion\bin\svn.exe`

### Règles personnalisées avec les deux VCS

Le [moteur de règles personnalisées](examples/README.md) (profils YAML)
est indépendant du VCS — il ne fait que lire des fichiers. Flux de travail
recommandé pour **les deux** systèmes VCS :

1. Placer `analyser-rules.yml` (ou l'un des profils de `examples/`) à la
   **racine du projet** — Git/SVN le versionnent avec les sources
2. Le référencer dans `analyser.ini` :
   ```ini
   [Detectors]
   CustomRulesFile=analyser-rules.yml   ; relatif à la racine du projet
   ```
3. Le plugin/GUI le charge automatiquement à la prochaine analyse

Ainsi chaque projet porte **son propre jeu de règles dans le dépôt** —
partagé par l'équipe, versionné, relisible dans les diffs de PR/MR.

### Intégration CI/CD

**GitHub Actions** (Git) : voir le modèle [`examples/ci/github-actions-sca.yml`](examples/ci/github-actions-sca.yml).
L'upload SARIF apparaît en annotations en ligne dans les PR.

**GitLab CI / Jenkins / TeamCity / Azure DevOps** : même schéma — rendre
l'outil disponible dans l'image du pipeline, lancer `analyser.exe
--path . --branch --report-sarif sca.sarif`, joindre l'artefact ou le
traiter plus loin (des plugins SARIF existent pour la plupart des CI).

**Hook pre-commit SVN** (côté serveur, Linux) :
```bash
#!/bin/sh
# /path/to/svn-repo/hooks/pre-commit
REPOS="$1"
TXN="$2"

# Ajuster le chemin de l'outil et le miroir de la copie de travail
ANALYSER=/opt/sca/analyser.d12.exe
WC=/tmp/sca-precommit-$TXN

svn export "$REPOS" "$WC" -r "$TXN" --quiet
"$ANALYSER" --path "$WC" --full --quiet
EXIT=$?
rm -rf "$WC"
exit $EXIT
```

Correspondance des codes de sortie :
- 0 = propre → commit autorisé
- 1 = conseils uniquement → commit autorisé
- 2 = avertissements → commit autorisé (ou blocage via la logique du hook)
- 3 = erreurs → **commit bloqué**

### `--parallel` — défectueux, ne pas utiliser

> **Cette option est connue comme défectueuse depuis le 2026-08-08.** Il
> était écrit ici auparavant que le résultat était identique octet pour
> octet à une exécution sérielle. Cette affirmation était fausse et n'a
> jamais été mesurée — le test derrière elle ne vérifiait que l'étape de
> fusion, jamais un vrai scan.

Onze détecteurs partagent des instances `TRegEx` globales à l'unité. Un
`TRegEx` est un record autour d'**un** objet moteur partagé dont le sujet
et les offsets sont modifiés à chaque correspondance ; deux workers dans le
même détecteur se corrompent donc mutuellement l'état. Mesuré sur un corpus
réel : cinq exécutions sérielles ont produit un seul hash SARIF identique ;
treize exécutions parallèles ont produit **treize résultats différents**,
avec **40 vrais résultats perdus** et trois résultats de sévérité Error
*inventés*. Lancer `--parallel --parallel-workers 1` reproduit le résultat
sériel octet pour octet, ce qui désigne la concurrence comme cause plutôt
qu'un chemin de code différent.

Il n'y a rien à arbitrer, car il n'y a aucun gain de vitesse à perdre :
24,3 s en sériel contre 27,7–41 s en parallèle sur 2/4/8/16/28 workers —
monotonement pire. L'ancien chiffre « environ 3 % de gain » n'est pas
reproductible. Environ la moitié du temps mur est la *pré-phase sérielle*
(parsing, index de symboles et de types), que l'option ne touche pas.

L'utiliser aujourd'hui imprime un avertissement sur stderr. La réparation
propre consiste à donner à chaque détecteur son propre `TRegEx` par appel —
le projet a déjà résolu exactement cette classe de bug une fois, dans
`uRegExMatches`, et a simplement oublié ces onze unités.

---

## Fichiers de configuration

La plupart des réglages s'éditent via **Tools > Options > Third Party >
Static Code Analyser** dans le plugin IDE (aperçu en direct, suit le thème) :

![Page Tools > Options de Static Code Analyser dans l'IDE Delphi](docs/OptionsSca.gif)

Les mêmes valeurs sont persistées dans les fichiers INI ci-dessous —
prenez le plus commode. Tous sous `%APPDATA%\StaticCodeAnalyser\` :

| Fichier | Contenu |
|---------|---------|
| `analyser.ini` | Tous les réglages — VCS (BaseBranch, chemins git/svn), bascules de détecteurs (`UsesCheck`, `IncludeTests`, `AutoDiscoverClasses`), `LeakyClasses` / `ExcludeLeakyClasses` personnalisées, seuils des détecteurs, langue de l'UI. Le fichier est créé au premier démarrage avec des commentaires auto-documentés à côté de chaque option |
| `ignore.txt` | Motifs de fichiers et de répertoires à ignorer pendant l'analyse |
| `recent.ini` | Chemins de projets récemment utilisés |
| `LeakyClassesDiscover.log` | Sortie de `AutoDiscoverClasses=1` — classes découvertes, séparées en _instantiable_ (ont un ctor/dtor ou un appel `Create()`) et _static-only candidates_. Copier manuellement les pertinentes dans `LeakyClasses=` de `analyser.ini` |
| `StaticCodeAnalyser_scan.log` | Journal de diagnostic : quel fichier a pris combien de temps |

### Seuils des détecteurs (tous optionnels, dans `[Detectors]`)

| Clé | Défaut | Effet |
|-----|--------|-------|
| `LongMethodMaxBodyLines` | 50 | `LongMethod` se déclenche quand le nombre de lignes de corps ET le nombre d'instructions dépassent tous deux leurs seuils |
| `LongMethodMaxStatements` | 30 | (seuil secondaire de `LongMethod`) |
| `LongParamListMaxParams` | 5 | `> N` paramètres → conseil de refactoring |
| `DeepNestingMaxDepth` | 4 | `> N` structures de contrôle imbriquées |
| `CyclomaticMax` | 10 | Complexité de McCabe `> N` par méthode (compte `if`, branche de `case`, `for`/`while`/`repeat`, gestionnaire `on`, `and`/`or`/`xor`) |
| `DuplicateBlockMinLines` | 8 | nombre minimal de lignes normalisées pour la détection de blocs dupliqués |
| `MaxFileMB` | 5 | les fichiers plus gros sont ignorés (garde anti-OOM pour le code généré) |
| `MaxLineLength` | 120 | `TooLongLine` se déclenche quand une ligne dépasse cette longueur |
| `MaxCaseBranches` | 10 | `CaseStatementSize` se déclenche quand un `case` a autant de branches |
| `MagicNumberTrivials` | `0,1,2,-1,10,100` | nombres exemptés de la détection `MagicNumber` |
| `UsesCheck` | 0 | détecteur `UnusedUses` (désactivé par défaut — peut produire des faux positifs) |
| `IncludeTests` | 0 | inclure `uTest*.pas`, `*_Tests.pas`, `TestProject*.dpr`, les répertoires `/tests/` |
| `AutoDiscoverClasses` | 0 | scanner l'AST du projet à la recherche de classes personnalisées nécessitant `Free` et les ajouter aux `LeakyClasses` |
| `LeakyClasses` | _(vide)_ | liste, séparée par des virgules, de classes supplémentaires à suivre |
| `ExcludeLeakyClasses` | _(vide)_ | liste, séparée par des virgules, de classes à NE PAS suivre même si elles figurent dans les valeurs par défaut |

### Live-Watch (plugin IDE uniquement) — ⚠️ RISQUÉ

Cliquer sur **📄 File** dans le plugin IDE active une surveillance en
direct mono-fichier sur exactement ce fichier : chaque enregistrement
(anti-rebond 300 ms) et chaque édition (anti-rebond 1000 ms) relance
l'analyse de CE fichier dans un thread d'arrière-plan. Changer d'onglet
vers un autre fichier ne change rien ; recliquer sur **📄 File** déplace la
surveillance vers le nouveau fichier. Les chemins de masse (**▶ Analyse**,
**Branch-Changes**) désactivent explicitement la surveillance. Il n'existe
pas de drapeau INI pour cela.

> ⚠️ **Risque de boucle infinie.** Il n'existe actuellement **aucune garde
> de réentrance** pour les lancements de workers qui se chevauchent. Si le
> worker met plus longtemps que le délai anti-rebond d'édition (1000 ms) et que
> l'utilisateur continue de taper, l'arriéré de workers grandira au lieu de
> se résorber. De plus (selon la version de Delphi), un redessin de
> l'éditeur suivant une mise à jour des résultats peut être réinterprété
> comme `Modified` — les chemins édition/enregistrement peuvent alors se
> redéclencher l'un l'autre. La seule sécurité aujourd'hui est le compteur
> de génération (écarte les résultats _tardifs_, mais n'empêche pas les
> lancements chevauchés). Ajoutez une garde de réentrance + un plafond dur
> avant tout usage élargi (`TODO.md` -> _Single-File-Live-Watch_).

---

## Suppression

Faire taire des résultats individuels en ligne :

```pascal
// noinspection MemoryLeak
list := TStringList.Create;

// noinspection NilDeref, DivByZero
DoSomethingRisky;

// noinspection All
// supprime tous les contrôles sur la ligne suivante
```

Noms de catégories reconnus (un par détecteur enregistré — la source
unique de vérité est `KIND_META` dans `uSCAConsts.pas`) :

`MemoryLeak`, `EmptyExcept`, `SQLInjection`, `HardcodedSecret`,
`FormatMismatch`, `FileReadError`, `UnusedUses`, `NilDeref`,
`MissingFinally`, `DivByZero`, `DeadCode`, `LongMethod`, `LongParamList`,
`MagicNumber`, `DuplicateString`, `HardcodedPath`, `DebugOutput`,
`DeepNesting`, `TodoComment`, `EmptyMethod`, `DuplicateBlock`, `All`.

---

## Transfert de propriété (pas d'avertissement MemoryLeak)

Ces motifs sont reconnus comme remise de propriété et ne déclenchent pas
de résultat MemoryLeak :

| Motif | Signification |
|-------|---------------|
| `Result := varName` | La fonction rend la propriété à son appelant |
| `varName.Parent := winControl` | VCL : TWinControl libère ses enfants `Controls[]` |
| `varName := X.Add(...)` | Retour emprunté — l'élément vit dans la liste `OwnsObjects` du conteneur |
| `varName := X.AddChild(...)` | Arbre AST / DOM : l'enfant appartient au parent |
| `varName := X.AddNode(...)` | TTreeView, etc. |
| `varName := X.AppendChild(...)` | XML-DOM / IXMLNode |
| `FField := varName` | Transfert variable-vers-champ — la propriété quitte la portée de la méthode |
| `FField := varName as ISomething` | Le comptage de références d'interface garde l'objet en vie |
| `inherited Create(varName, …)` | Le constructeur parent prend la propriété |
| `TAnyClass.Create(varName, …)` | Un autre constructeur prend la propriété |
| `Container.Add(varName)` | TObjectList (etc.) prend la propriété |
| `Container.Add(key, varName)` | TObjectDictionary prend la propriété |
| `Container.AddObject(text, varName)` | TStringList avec objets |
| `Container.Insert(i, varName)` | TList.Insert |
| `Container.Push(varName)` | TStack.Push |
| `Container.Enqueue(varName)` | TQueue.Enqueue |

Pour les **champs de classe**, le détecteur FieldLeak reconnaît en plus le
motif standard du propriétaire TComponent comme absence de fuite :

| Motif | Signification |
|-------|---------------|
| `FField := X.Create(Self)` | Propriétaire TComponent : `inherited Destroy` appelle `DestroyComponents` |
| `FField := X.Create(AOwner)` | Propriétaire relayé depuis le paramètre du constructeur |
| `FField := X.Create(Owner)` | Propriétaire pris d'un champ/d'une propriété existants |

---

## Architecture

```
StaticCodeAnalyserIDE/                 Paquets expert IDE : jeu de dev
                                       (SCA.Engine.dpk + SCA.SharedUI.dpk +
                                       StaticCodeAnalyser.IDE.d12.dpk) et
                                       monolithe de release
                                       (StaticCodeAnalyser.Plugin.d12.dpk)
  uIDEExpert.pas                       Enregistrement du wizard (IOTAMenuWizard)
  uIDEAnalyserForm.pas                 Fenêtre ancrable (TFrame) - coquille principale :
                                       filtres, grille de stats, tri, export,
                                       copie du prompt Claude, sentinelle de cycle de vie
  uIDELineHighlighter.pas              Bande rouge de 3 px dans la gouttière de
                                       l'éditeur IDE sur la ligne fautive
  uIDEMessages.pas                     Remise dans l'onglet Messages de l'IDE
  uIDEWatchMode.pas                    Surveillance mono-fichier (fichier courant)
                                       save 300 ms / edit 1000 ms anti-rebond
                                       ⚠️ pas de garde de réentrance - voir README
  uIDEStatsTiles.pas                   Constructeur de la rangée de tuiles de type Sonar
  uIDEHelpPanel.pas                    Panneau d'aide de droite avec avant/après,
                                       masquage auto une fois ancré
  uIDEExportMenu.pas                   Menu déroulant d'export (JSON/CSV/HTML/Jira)
  uIDEEditorIntegration.pas            Enveloppes ToolsAPI : fichier .pas courant,
                                       répertoire du projet, OpenFileAtLine
  uIDEStatusBar.pas                    Barre d'état à trois panneaux
                                       (résultats / progression / mode)
  uIDEThemeIntegration.pas             Notificateur de thème IDE + rafraîchissement ApplyTheme
  uIDEAnalyseProgress.pas              Contrôleur d'état occupé
                                       (Begin/EndRun, drapeau d'annulation)

StaticCodeAnalyserForm/sources/        Moteur d'analyse (partagé entre autonome + plugin IDE)
  Common/
    uSCAConsts.pas                     TFindingKind + KIND_META, source unique
                                       de vérité (correspondance des catégories Sonar)
    uMethodd12.pas                     Record TLeakFinding + assistants
    uRecentPaths.pas                   Gestion de recent.ini
    uRegExMatches.pas                  Assistants regex partagés
    uDetectorUtils.pas                 Assistants IsIdentChar, IsWholeWord
    uCollectValues.pas                 Collecte des valeurs littérales de l'AST

  UI/
    uAnalyserPalette.pas               Constantes de couleurs centrales
    uAnalyserTypes.pas                 Énumération TFindingSeverity + conversions
    uAnalyserTheme.pas                 SeverityBg, SeverityAccent, BlendColor
    uFindingGridRenderer.pas           Logique OnDrawCell du StringGrid
    uFindingFilter.pas                 Pipeline de filtres sévérité/type/recherche
    uLocalization.pas                  Enveloppe dxgettext (macro _('…'))

  Parsing/
    uLexer.pas                         Tokeniseur, watchdog (200k tokens)
    uParser2.pas                       Parseur à descente récursive avec
                                       garantie de progression
    uAstNode.pas                       AST avec recherche FindAll / FindFirst

  Infrastructure/
    uStaticAnalyzer2.pas               Orchestre les ~130 détecteurs Pascal par fichier
    uStaticFiles.pas                   Scan de fichiers récursif, rappel de tick,
                                       prise en charge de l'annulation, protection symlink
    uIgnoreList.pas                    ignore.txt + filtre de tests
    uVcsChanges.pas                    Diff Git/SVN via CreateProcess + pipe
    uRepoSettings.pas                  analyser.ini (BaseBranch, chemins d'exe)
    uSuppression.pas                   Marqueurs // noinspection
    uExport.pas                        JSON / CSV / Jira / presse-papiers
    uExportHtml.pas                    Rapport HTML autonome

  Output/
    uClaudePrompt.pas                  Générateur du prompt Markdown IA
    uFixHint.pas                       Exemple avant/après par type de résultat

  Detectors/
    uLeakDetector2.pas                 MemoryLeak (variables locales, basé sur l'AST)
    uFieldLeak.pas                     Fuite de champ de classe (Create / Destroy)
    uCodeSmells2.pas                   EmptyExcept
    uSQLInjection.pas                  + uSQLInjectionScore.pas (scoring)
    uHardcodedSecret.pas, uHardcodedPath.pas
    uFormatMismatch.pas, uUnusedUses.pas
    uNilDeref.pas, uMissingFinally.pas
    uDivByZero.pas, uDeadCode.pas
    uLongMethod.pas, uLongParamList.pas
    uMagicNumbers.pas, uDuplicateString.pas
    uDuplicateBlock.pas
    uDebugOutput.pas, uDeepNesting.pas
    uTodoComment.pas, uEmptyMethod.pas
    uCustomClassDiscovery.pas          Assistant AutoDiscoverClasses
                                       (pas un détecteur — alimente LeakyClasses)
```

### Flux de données

```
Fichier → Lexer → Parser2 → AST (TAstNode)
                              │
                              ├── 21 détecteurs en parallèle (try/except par détecteur)
                              │       chacun émet des TLeakFinding
                              │
                              └── TSuppression retire les marqueurs noinspection
                                          │
                                          └── TObjectList<TLeakFinding>
                                                  │
                                                  └── PopulateFindings →
                                                      Cartes de stats + grille + export
```

---

## Performance

Pour un dépôt typique de 1 000 unités :

| Phase | Par fichier | 1 000 fichiers |
|-------|-------------|----------------|
| Scan du dossier | — | 1–3 s |
| Lexer | ~5–15 ms | ~10 s |
| Parser2 | ~10–50 ms | ~30 s |
| ~130 détecteurs Pascal | ~10–60 ms | ~50 s |
| Parseur DFM + 23 détecteurs DFM (par `.dfm`) | ~5–20 ms | ~5–10 s |
| Balayage de suppression | — | <1 s |
| **Total** | **~30–100 ms** | **~60–90 s** |

Pour les re-scans incrémentaux, **utilisez Branch-Changes plutôt qu'un scan
complet** — typiquement 200 ms à 3 s. Voir [BRANCH_CHANGES_fr.md](BRANCH_CHANGES_fr.md).

### Robustesse

- **Watchdog** : limite de 200k tokens par fichier — les entrées
  pathologiques sont interrompues en moins d'une seconde au lieu de bloquer.
- **GuardAdvance** : garantie de progression dans chaque boucle externe du parseur.
- **Couverture de la syntaxe Delphi du monde réel** : le parseur gère les
  déclarations de types `interface`, les types/méthodes génériques
  (`TFoo<T>`, `function Get<T>: T;`), `packed record` / `packed class`, les
  sections `label` locales, `record helper for X` / `class helper for X` et
  les en-têtes de méthodes conditionnels par IFDEF sans perdre les corps de
  méthodes — important pour les bases de code réelles (mORMot2, etc.).
- **`MaxFileMB` (5 Mo par défaut)** : les fichiers trop gros sont signalés
  immédiatement comme `FileError`. Configurable dans `analyser.ini`.
- **MAX_DEPTH = 32** : protection contre les boucles de liens symboliques.
- **Annulation à tout moment** : `EAbort` se propage proprement à travers
  chaque couche.
- **try/except par détecteur** : un détecteur qui plante ne bloque jamais
  aucun des 154 autres.

---

## Projets de test

```
StaticCodeAnalyserForm/tests/
  TestProject.dpr                      Lanceur DUnitX
  uTest<NomDuDetecteur>.pas            un fichier par détecteur, 205 fichiers
                                       au total — 3095 tests répartis sur 229
                                       fixtures
  uTestFindingHelper.pas               harnais partagé (FindingsOf /
                                       FindingsOfFile / FindingsViaPipeline)
  uTestTAstNode.pas                    Tests des assistants AST
  uTestPerformance.pas                 Benchmarks de débit
                                       (tokens/ms, lignes/ms)
```

Les tests tournent sur DUnitX et émettent un rapport XML NUnit — prêt à
brancher en CI.

Choisissez le harnais en connaissance de cause : `FindingsOf` pilote les
détecteurs AST, `FindingsOfFile` est requis pour les détecteurs qui lisent
les lignes source, et `FindingsViaPipeline` parcourt le chemin de
production complet, y compris les filtres de profil, de sévérité, de
suppression et de confiance — c'est ce qu'un utilisateur voit réellement.

---

## Prérequis

- Delphi 12 (Athens), versions 12.0–12.3 (IDE 32 bits, BDS 23.0), et
  Delphi 13 (Florence, BDS 37.0) avec ses **deux** IDE, 32 et 64 bits.
  Delphi 12 n'a pas d'IDE 64 bits — il ne fournit `designide` qu'en
  Win32, un paquet de conception 64 bits n'y est donc même pas
  compilable. Delphi 11 et plus
  anciens ne sont pas pris en charge.
- DUnitX (uniquement pour la suite de tests, pas pour le plugin lui-même)
- Optionnel : Git for Windows ou TortoiseSVN **avec** les outils CLI pour
  la fonction Branch-Changes

### Cibles de compilation

| Cible | Win32 | Win64 |
|-------|-------|-------|
| **Plugin IDE** (`StaticCodeAnalyser.IDE.d12.dpk`) | ✅ requis | ✅ **sous Delphi 13 uniquement** — un paquet de conception hérite de la bitness de son IDE, et seul Delphi 13 en possède un en 64 bits. Sous Delphi 12, une compilation Win64 échoue sur `designide` manquant ; le `.dpk` l'intercepte avec un message lisible |
| **EXE autonome / CLI** (`analyser.d12.dproj`) | ✅ | ✅ |
| **Suite de tests** (`TestProject.dproj`) | ✅ | _ajouter la plateforme si besoin_ |

L'EXE autonome compile proprement pour `Win32` comme pour `Win64` — les
deux cibles passent par le même moteur de détecteurs et émettent les mêmes
rapports SARIF/JSON/CSV/HTML. Choisissez `Win64` si vous voulez un tas plus
grand (pertinent uniquement sur les scans de plusieurs Go).

---

## Vue d'ensemble des composants

| Composant | Chemin | Rôle |
|-----------|--------|------|
| **EXE autonome** | `StaticCodeAnalyserForm/analyser.d12.dproj` | Scan de dossiers/fichiers hors de l'IDE |
| **Plugin IDE** | `StaticCodeAnalyserIDE/StaticCodeAnalyser.IDE.d12.dpk` (jeu de dev avec `SCA.Engine.dpk` + `SCA.SharedUI.dpk` ; les releases livrent le monolithe `StaticCodeAnalyser.Plugin.d12.dpk`) | Fonction principale — fenêtre d'outil ancrable avec l'ensemble des fonctionnalités |

Les deux partagent le moteur d'analyse de `StaticCodeAnalyserForm/sources/`.

---

## Documentation

**[docs/index.md](docs/index.md) est la carte complète** — chaque document
livré, groupé selon ce que vous cherchez à faire. Les quatre dont vous
aurez le plus probablement besoin :

| Fichier | Contenu | Quand le consulter |
|---------|---------|--------------------|
| [README_fr.md](README_fr.md) | **Vue d'ensemble** — ce que fait le plugin, comment l'utiliser, architecture, performance, suppression, intégration du thème | Point de départ par défaut |
| [EXPORTS_fr.md](EXPORTS_fr.md) | **Tous les formats d'export** — SARIF, Sonar, HTML, CSV, JSON, référence — avec le flux de travail que chacun sert et les options CLI qui le pilotent | Quand vous voulez sortir les résultats *hors* de l'outil : garde-fou CI, revue de code, système de tickets, tableur |
| [DETECTORS_fr.md](DETECTORS_fr.md) | **Liste canonique des détecteurs** — chaque règle avec son statut (✅ implémentée / 🟡 partielle / 🔲 ouverte), sa description et l'unité responsable | Quand vous voulez savoir quelle règle est implémentée, ce qu'elle vérifie exactement, ou quel détecteur arrive ensuite |
| [BRANCH_CHANGES_fr.md](BRANCH_CHANGES_fr.md) | **Fonction VCS / Branch-Changes** — comment fonctionne le bouton `Branch-Changes`, configuration Git/SVN, compatibilité Tortoise, configuration `analyser.ini`, dépannage de la détection de dépôt | Quand le bouton Branch-Changes ne fait pas ce que vous attendez, ou pour affiner la configuration VCS |

Les pages par règle (ce qu'un résultat signifie et comment le corriger)
vivent sous [docs/rules/](docs/rules/index.md) ; le catalogue avec les
sévérités est [docs/rules.md](docs/rules.md).

Convention : `README.md` est large, les fichiers spécialisés sont profonds.
Dès qu'une section du README devient trop grosse, elle part dans son propre
fichier (c'est exactement ce qui est arrivé au contenu Branch-Changes).

🇩🇪 Les versions allemandes portent le suffixe `_de` : [README_de.md](README_de.md),
[EXPORTS_de.md](EXPORTS_de.md), [DETECTORS_de.md](DETECTORS_de.md),
[BRANCH_CHANGES_de.md](BRANCH_CHANGES_de.md)

---

## Projets liés et alternatives

Si vous évaluez ce projet, vous regardez peut-être aussi :

- **SonarQube / SonarLint** — couverture de langages large, mais **Delphi /
  Object Pascal n'est pas pris en charge d'origine**. Ce projet est la
  « sensation Sonar » la plus proche que vous puissiez avoir pour Delphi
  sans écrire vous-même un plugin Sonar. Mêmes cinq catégories (Bug /
  Vulnerability / Security Hotspot / Code Smell / Code Duplication), même
  idée de score de qualité, export SARIF pour GitHub Code Scanning.
- **FixInsight** (CodeHealer) — commercial, intégré à l'IDE. Ce projet est
  une **alternative libre et open source à FixInsight** avec une couverture
  de détecteurs comparable sur Pascal, plus un scanner DFM dédié que
  FixInsight ne livre pas.
- **Pascal Analyzer (PAL)** — commercial. Jeu de détecteurs qui se
  recoupe, mais pas de contrôles DFM, pas de passage de relais à Claude AI,
  pas de SARIF.
- **DFMCheck / GExperts DFM-Check** — linters DFM mono-usage. Les 23
  détecteurs DFM de ce projet en sont un sur-ensemble (analyse inter-fiches
  basée sur un graphe, index de fiches à l'échelle du dépôt, couplage à
  l'AST Pascal).
- **Hints / warnings de DCC32** — diagnostics intégrés du compilateur.
  Utiles mais limités aux contrôles syntaxiques et trivialement
  sémantiques ; pas de taxonomie, pas de requêtes AST, pas de catégorie
  sécurité.

## Mots-clés

Analyse statique de code Delphi, linter Object Pascal, plugin RAD Studio,
Delphi 12 Athens, Delphi 13 Florence, plugin IDE Delphi, ToolsAPI, analyseur DFM, linter de
fichiers de fiche, AST Pascal, alternative SonarQube pour Delphi,
alternative FixInsight, alternative Pascal Analyzer, détecteur de fuites
mémoire Delphi, détecteur d'injection SQL pour Delphi, scanner de secrets
en dur, code smell Delphi, duplication de code Delphi, complexité de McCabe
Delphi, SARIF Delphi, scan incrémental Branch-Changes, diff Git Delphi,
diff SVN Delphi, prompt Claude AI, automatisation de revue de code Delphi,
sécurité TADOQuery, sécurité TFDQuery, chaîne de providers TClientDataSet,
audit TDataSetProvider, détection de maître-détail circulaire, détection de
gestionnaires d'événements morts, détecteur de Caption non traduites, audit
dxgettext, injection SQL via TEdit.Text, identifiants DB en dur dans les
DFM, lint Pascal CI/CD, GitHub Actions Delphi SARIF, hook pre-commit Delphi.

---

## Licence

Ce projet est publié sous la **licence MIT** — voir [LICENSE](LICENSE)
pour le texte complet.

```
Copyright (c) 2026 Nicolas Gerlach
```

En bref :

- ✅ Libre d'utiliser, copier, modifier, fusionner, publier, distribuer et sous-licencier
- ✅ Libre pour un usage commercial
- ✅ Aucune garantie — le logiciel est fourni « tel quel »
- ℹ️ La mention de copyright et le texte de la licence doivent être
  conservés dans les copies ou parties substantielles du logiciel

---

## Soutien

Le lien de don est en haut de ce README — merci !

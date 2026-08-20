# Static Code Analysis Tool for Delphi

Analyseur statique de code façon Sonar pour Delphi / Object Pascal.
Détecte les fuites mémoire, les code smells, les failles de sécurité et
les problèmes de maintenabilité.

🇬🇧 [English version](BRANCH_CHANGES.md) · 🇩🇪 [Deutsche Fassung](BRANCH_CHANGES_de.md)

Le dépôt fournit deux composants :

| Composant | Rôle | Chemin |
|-----------|------|--------|
| **EXE autonome** | Outil autonome pour analyser des répertoires sur disque | `StaticCodeAnalyserForm/` |
| **Plugin IDE** | Fenêtre d'outil ancrable dans l'IDE Delphi | `StaticCodeAnalyserIDE/` |

---

## Les fonctionnalités en un coup d'œil

- **195 règles (172 Pascal + 23 DFM)** — voir [`DETECTORS_fr.md`](DETECTORS_fr.md) et [`rules/sca-rules.json`](rules/sca-rules.json) pour l'état canonique (Sonar + migration SonarDelphi + DFM + bonus)
- **Tuiles de statistiques façon Sonar** au-dessus de la grille : erreurs / avertissements / conseils / bugs / duplications de code / qualité du code en note **A–E** (score brut + détail dans l'infobulle)
- **Filtre de sévérité** + **filtre de type** (Bug, Code Smell, Vulnerability, Security Hotspot, Code Duplication)
- **Panneau d'aide à droite** avec des exemples de code « avant/après » pour chaque résultat
- **Générateur de prompt Claude AI** — un clic sur une ligne copie un bloc Markdown prêt à l'emploi dans le presse-papiers
- **Mode branche VCS** — n'analyse que les fichiers modifiés dans la branche (voir plus bas)
- **Suppression** via des commentaires `// SCA: ignore`
- **Export** en CSV / JSON / Jira / HTML
- **Suivi du thème** — suit le thème actif de l'IDE Delphi (Light / Dark / Mountain Mist / Carbon)
- **Chemins récents** conservés d'une session à l'autre
- **Liste d'exclusions** dans `%APPDATA%\StaticCodeAnalyser\ignore.txt`

---

## Les composants en détail

### 1. EXE autonome — `analyser.d12.dpr`

Programme autonome compilé à partir de `analyser.d12.dproj`. Il offre :

- Analyse récursive de dossiers
- Analyse de fichier unique
- Export CSV
- Navigation directe vers la ligne du résultat (ouvre l'IDE et saute à la ligne)

Compilation :

```
Open analyser.d12.dproj in Delphi 12  →  Project  →  Build
```

### 2. Plugin IDE — `StaticCodeAnalyser.IDE.d12.dpk`

Paquet designtime qui fournit la fenêtre d'outil ancrable. Lancement via
**Tools / Static Code Analysis Tool for Delphi** ou **View / Static Code
Analysis Tool for Delphi**.

Fonctions en plus de l'exécutable autonome :

- **📄 Fichier** — analyse le fichier source actuellement ouvert dans l'IDE
- **Branch-Changes** — n'analyse que les fichiers modifiés dans la branche
- **Navigation directe** via les services d'éditeur de l'IDE (aucun hack WinAPI)
- Rangée de tuiles de statistiques avec compteurs en direct
- Panneau d'aide avec extraits avant/après

Installation — le plus simple d'abord : l'**EXE d'installation** de la
release (`StaticCodeAnalyserSetup-<Version>.exe`) ou le **paquet local
GetIt** (`StaticCodeAnalyser-v<V>-getit-manifest.zip` → **Load Local
Package** dans le GetIt Package Manager). Pour compiler depuis les
sources :

```
Open StaticCodeAnalyser.IDE.d12.dproj  →  Project  →  Install
```

---

## Détecteurs

La liste complète avec statut (✅ implémenté · 🟡 partiel · 🔲 ouvert) se
trouve dans [`DETECTORS_fr.md`](DETECTORS_fr.md).

État actuel (v0.9.16) : **195 règles (172 Pascal + 23 DFM)** — catalogue Sonar + migration SonarDelphi (SCA120-152) + détecteurs DFM + contrôles de nommage/formatage (SCA060-119) + bonus.

Points forts par sévérité :

| Sévérité | Exemples |
|----------|----------|
| 🔴 **Blocker** | MemoryLeak, EmptyExcept, NilDeref, SQLInjection, HardcodedSecret |
| 🟠 **Critical** | DivByZero, MissingFinally, FormatMismatch, FieldLeak |
| 🟡 **Major** | LongMethod, LongParamList, DeepNesting, MagicNumber, DuplicateString |
| 🔵 **Minor** | UnusedUses, TodoComment, EmptyMethod, DeadCode |
| 🎁 **Bonus** | HardcodedPath, DebugOutput, DuplicateString |

---

## Mode Branch-Changes

Évitez l'analyse complète du projet et n'analysez que les fichiers
touchés dans la branche courante — nettement plus rapide (des secondes
au lieu de minutes), idéal comme garde-fou avant commit.

### Démarrage rapide

1. Cliquer sur le bouton **`Branch-Changes`** dans le plugin IDE
2. L'analyseur remonte depuis `Project path` à la recherche de `.git` ou `.svn`
3. Il récupère la liste des fichiers `.pas` modifiés
4. Les détecteurs ne traitent que ces fichiers ; les résultats apparaissent dans la grille

### Ce qui est inclus

**Les dépôts Git** combinent deux sources :

```
git diff --name-only --diff-filter=ACMR <base>...HEAD   # diff de branche validé
git status --porcelain                                  # non validé + non suivi
```

`<base>` est détecté automatiquement : `origin/HEAD` → `main` → `master`.
Les codes d'état `A` / `C` / `M` / `R` sont inclus ; `D` (supprimé) est
ignoré. Pour les renommages, seul le chemin de destination est analysé.

**Les dépôts SVN** ne regardent que la copie de travail :

```
svn status
```

Les codes d'état `M` / `A` / `R` / `?` sont inclus ; `D` / `!` / `I` / `C`
sont ignorés.

### Prérequis

L'outil en ligne de commande doit être joignable. Ordre de recherche :

| VCS | Ordre de recherche |
|-----|--------------------|
| **Git** | `PATH` → `C:\Program Files\Git\bin\git.exe` → `C:\Program Files (x86)\Git\bin\git.exe` → `C:\Program Files\TortoiseGit\bin\git.exe` → `TortoiseGit\mingw64\bin\git.exe` |
| **SVN** | `PATH` → `C:\Program Files\TortoiseSVN\bin\svn.exe` → `C:\Program Files (x86)\TortoiseSVN\bin\svn.exe` → `C:\Program Files\Subversion\bin\svn.exe` |

Configurations recommandées :

- **Git for Windows** ([git-scm.com](https://git-scm.com/download/win))
- **TortoiseSVN** avec l'option *« command line client tools »* activée
  — sans elle, `svn.exe` n'est pas installé

### Compatibilité Tortoise

| Configuration | Fonctionne ? |
|---------------|--------------|
| **Git for Windows** seul, ou avec TortoiseGit | ✅ via `PATH` |
| **TortoiseGit seul** sans Git for Windows | ❌ TortoiseGit ne livre pas son propre `git.exe` ; une installation Git séparée est requise |
| **TortoiseSVN avec** « command line client tools » | ✅ trouvé automatiquement dans le répertoire bin de TortoiseSVN |
| **TortoiseSVN sans** « command line client tools » | ❌ message d'erreur clair — relancer l'installateur avec l'option activée |

### Performance

| Mode | Durée typique |
|------|---------------|
| Analyse complète du répertoire | 60–90 s |
| Branch-Changes (5–30 fichiers .pas) | 200 ms – 3 s |

---

## Gestion du thème

Le plugin IDE suit le thème actif de l'IDE Delphi grâce à :

- **`StyleServices.GetSystemColor`** dans le dessin personnalisé (OnDrawCell, TTilePanel.Paint)
- **`clBtnFace` / `clWindow` / `clBtnText`** comme valeurs de propriété (thème automatique)
- **`IOTAIDEThemingServices.ApplyTheme`** quand le frame est hébergé
- **`INTAIDEThemingServicesNotifier`** pour les changements de thème en direct
- **`CM_STYLECHANGED`** plus une **redéfinition de `SetParent`** comme déclencheurs supplémentaires

Unités de l'architecture :

| Unité | Contenu |
|-------|---------|
| [`uAnalyserPalette.pas`](SCA.SharedUI/sources/uAnalyserPalette.pas) | Constantes de couleur centrales (fonds de sévérité, accents, couleurs d'icônes) |
| [`uAnalyserTypes.pas`](SCA.Engine/sources/Common/uAnalyserTypes.pas) | Énumération `TFindingSeverity` + conversions |
| [`uAnalyserTheme.pas`](SCA.SharedUI/sources/uAnalyserTheme.pas) | `SeverityBg`, `SeverityAccent`, `BlendColor` |

**Limitation connue** : en mode flottant, la fenêtre du plugin ne reprend
pas de façon fiable les changements de thème de l'IDE à l'exécution.
Contournement : ancrer le plugin, ou fermer puis rouvrir la fenêtre
après le changement de thème.

---

## Paramètres — `analyser.ini`

Un clic sur le bouton **`Settings...`** ouvre :

```
%APPDATA%\StaticCodeAnalyser\analyser.ini
```

Le fichier est créé avec un contenu par défaut au premier lancement. Les
modifications sont rechargées automatiquement au prochain clic sur
**`Branch-Changes`**.

```ini
[Repo]
; Branche de comparaison pour "git diff <base>...HEAD".
; Vide = détection automatique (origin/HEAD -> main -> master).
; Exemples : develop, release/2024.1, origin/main
BaseBranch=

; Inclure les modifications non validées de la copie de travail ?
; 1 = oui (défaut - typique d'une vérification avant commit)
; 0 = modifications validées uniquement
IncludeWorkingTree=1

[Paths]
; Chemins complets si git/svn ne sont ni dans PATH ni aux emplacements
; Tortoise standard. Sinon, laisser vide.
GitExe=
SvnExe=
```

### Ajustements courants

| Scénario | Réglage |
|----------|---------|
| L'équipe utilise `develop` comme branche par défaut | `BaseBranch=develop` |
| Revue de code des seules modifications validées | `IncludeWorkingTree=0` |
| TortoiseGit à un emplacement personnalisé | `GitExe=D:\Tools\Git\bin\git.exe` |
| TortoiseSVN sans outils CLI dans PATH | `SvnExe=C:\Program Files\TortoiseSVN\bin\svn.exe` |

---

## Suppression

Supprimer des résultats sur une seule ligne :

```pascal
x := 1 / y;  // SCA: ignore (DivByZero — y est validé en amont)
```

Exclure des fichiers entiers via `%APPDATA%\StaticCodeAnalyser\ignore.txt`
— un fichier (ou un motif de chemin) par ligne.

---

## Dépannage

### « aucun dépôt Git/SVN dans ou au-dessus de ... »

L'analyseur remonte depuis **`Project path`** à la recherche de `.git` /
`.svn`. Vérifiez que le chemin se trouve dans un dépôt et que vous
n'avez pas choisi par mégarde un sous-chemin hors de la racine du dépôt.

### « aucune branche de base (main/master) trouvée — arbre de travail uniquement »

Votre dépôt n'a pas de branche par défaut sous les noms habituels.
Définissez explicitement `BaseBranch=` dans `analyser.ini` (p. ex.
`develop`).

### Des résultats attendus manquent

- **Extension de fichier** : seuls les fichiers `.pas` sont analysés.
  `.dpr` / `.dpk` ne sont pas encore couverts (l'extension est simple).
- **Sous-modules** : `git status` ne capture pas les modifications
  internes aux sous-modules — analysez le dossier du sous-module à part.
- **Filtre de tests** : les tests sont exclus par défaut. Définissez
  `[Detectors] IncludeTests=1` dans `analyser.ini` pour les inclure.
- **Liste d'exclusions** : vérifiez `%APPDATA%\StaticCodeAnalyser\ignore.txt`.

### Chemins avec des caractères non ASCII

L'analyseur utilise la page de code par défaut pour convertir stdout.
Les chemins à caractères spéciaux peuvent subir des défauts d'encodage
(le chemin converti n'existe plus). Contournement dans `.gitconfig` :

```
[core]
    quotepath = false
```

Ainsi `git status --porcelain` émet de l'UTF-8 au lieu de séquences
échappées.

---

## Compilation / installation

| Cible | Étape |
|-------|-------|
| EXE autonome | Ouvrir `analyser.d12.dproj` → Project → Build |
| Plugin IDE (recommandé) | Exécuter le setup de release `StaticCodeAnalyserSetup-<Version>.exe`, ou charger le paquet local GetIt (`StaticCodeAnalyser-v<V>-getit-manifest.zip`) |
| Plugin IDE (depuis les sources) | Ouvrir `StaticCodeAnalyser.IDE.d12.dproj` → Project → Install |

Plateforme : **Win32** — le plugin s'exécute dans l'IDE 32 bits de
Delphi 12.0–12.3 (l'IDE 64 bits de 12.3 n'est pas encore pris en
charge).

---

## Structure du dépôt

```
StaticCodeAnalyser/
├── StaticCodeAnalyserForm/         # EXE autonome + code des détecteurs
│   ├── sources/                    # Détecteurs, parseur, aides de thème
│   ├── resources/                  # Fichiers Pascal de test des détecteurs
│   ├── tests/                      # Tests unitaires
│   └── analyser.d12.dproj          # Projet autonome
├── SCA.Engine/
│   └── SCA.Engine.dpk              # Paquet moteur (jeu dev)
├── SCA.SharedUI/
│   └── SCA.SharedUI.dpk            # Paquet Shared-UI (jeu dev)
├── StaticCodeAnalyserIDE/          # Plugin IDE (ancrable)
│   ├── uIDEExpert.pas              # Assistant du menu Tools
│   ├── uIDEAnalyserForm.pas        # Frame + enveloppe de fiche ancrable
│   ├── StaticCodeAnalyser.IDE.d12.dpk       # Paquet designtime (jeu dev)
│   └── StaticCodeAnalyser.Plugin.d12.dpk    # Paquet monolithe de release
├── docs/                           # Maquettes, croquis, captures d'écran
└── DETECTORS_fr.md                 # Catalogue complet des détecteurs avec statut
```

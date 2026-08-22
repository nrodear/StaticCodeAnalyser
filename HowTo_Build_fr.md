# HowTo : compiler et installer (guide du débutant)

Ce guide vous accompagne sur tout le chemin, de « je n'ai rien » à
« l'analyseur tourne sur mon code ». Il est écrit pour les personnes
**nouvelles en Delphi**.

Vous obtiendrez à la fin :
- l'**application Windows autonome** (`StaticCodeAnalyser.d12.exe`)
- le **plugin IDE** (chargé dans Delphi 12 à chaque ouverture)

> **Compiler est facultatif.** Les releases GitHub livrent des zips EXE
> prêts à l'emploi (Win32/Win64), un EXE d'installation pour le plugin
> IDE et un paquet GetIt — voir le démarrage rapide du README. Ce
> document s'adresse à ceux qui veulent compiler depuis les sources.

🇬🇧 [English version](HowTo_Build.md) · 🇩🇪 [Deutsche Fassung](HowTo_Build_de.md)

---

## 0. Ce qu'il vous faut

- **Windows 10 ou 11** (64 bits).
- **Environ 25 Go de disque libre** (RAD Studio est volumineux).
- Une **connexion Internet** (pour le téléchargement et pour git).
- Un **compte Embarcadero** (gratuit).
- Environ **45 minutes** au total. L'essentiel part dans l'installateur
  de RAD Studio.

---

## 1. Installer Delphi 12 (RAD Studio)

Il vous faut **Delphi 12 Athens** (aussi appelé RAD Studio 12) — l'une
des versions 12.0–12.3. Le plugin tourne dans l'IDE 32 bits (l'IDE
64 bits de 12.3 n'est pas encore pris en charge) ; Delphi 13 est prévu
mais pas encore pris en charge, Delphi 11 et antérieurs ne sont pas
pris en charge. La **Community Edition gratuite** suffit.

1. Allez sur https://www.embarcadero.com/products/delphi/starter.
2. Cliquez sur **« Download Free Trial »** ou **« Community Edition »**.
3. Connectez-vous avec votre compte Embarcadero (créez-en un si vous
   n'en avez pas).
4. Lancez l'installateur (`RADStudio_Athens_setup.exe`).
5. Choisissez :
   - **Personality :** Delphi (vous n'avez pas besoin de C++Builder).
   - **Platforms :** Windows 32-bit ET Windows 64-bit (les deux !).
   - **Languages :** l'anglais convient.
   - **Extras (facultatif) :** GetIt-Package-Manager — laissez le défaut.
6. Patientez. Le téléchargement fait ~6 Go ; l'installation ajoute
   encore ~12 Go.
7. Après l'installation, démarrez **RAD Studio**. Acceptez l'EULA au
   premier lancement.

Vous devriez maintenant voir l'**IDE Delphi** avec un onglet
« Welcome ». Fermez les projets d'exemple qu'il ouvre.

---

## 2. Télécharger ce projet depuis GitHub

Il vous faut **git** pour Windows : https://git-scm.com/download/win.

Ouvrez **Command Prompt** ou **PowerShell** dans le dossier où vous
gardez votre code, puis exécutez :

```cmd
cd D:\projects
git clone https://github.com/nrodear/StaticCodeAnalyser.git
cd StaticCodeAnalyser
```

Vous pouvez choisir n'importe quel chemin. Dans ce guide, nous
supposons `D:\projects\StaticCodeAnalyser`.

---

## 3. Ouvrir le groupe de projets dans Delphi

Le projet est livré comme **groupe de projets** contenant 4
sous-projets (moteur, UI partagée, application autonome, plugin IDE).

1. Dans Delphi, cliquez sur le menu **File → Open Project**.
2. Naviguez vers `D:\projects\StaticCodeAnalyser`.
3. En bas du dialogue, passez **« Files of type »** sur
   **« Delphi project group (`*.groupproj`) »**.
4. Choisissez `StaticCodeAnalyser.d12.groupproj` et cliquez sur **Open**.

À droite, vous voyez maintenant la fenêtre **Project Manager** avec
ces sous-projets :

- `SCA.Engine` — le moteur d'analyse.
- `SCA.SharedUI` — composants UI communs à l'autonome et au plugin.
- `StaticCodeAnalyser.d12` — l'EXE autonome.
- `StaticCodeAnalyser.IDE.d12` — le plugin IDE (un paquet BPL).

Delphi affiche le sous-projet **actif** en **gras** vert. Vous
changerez de projet actif au fil des étapes ci-dessous.

---

### 3.1 Compiler avec Delphi 13 au lieu de Delphi 12

Delphi 13 possède son propre jeu de fichiers projet. Tout le reste de
cette page est identique — seul le fichier ouvert à l'étape 3 change :

|                | Delphi 12                          | Delphi 13                          |
|----------------|------------------------------------|------------------------------------|
| Groupe         | `StaticCodeAnalyser.d12.groupproj` | `StaticCodeAnalyser.d13.groupproj` |
| Sous-projets   | `*.dproj`                          | `*.d13.dproj`                      |
| Nom du paquet  | `SCA.Engine.bpl`                   | `SCA.Engine370.bpl`                |
| Sortie         | `Output\...`                       | `Output\d13\...`                   |

Trois points à connaître :

- **Les sources sont partagées.** Les deux groupes compilent les mêmes
  fichiers `.dpk`/`.dpr` : une unité ajoutée apparaît dans les deux.
  Seuls les réglages du compilateur existent en double, et
  `tools/dproj_d13_gate.py` vérifie qu'ils restent identiques.
- **Le suffixe `370`** est la numérotation propre à Delphi 13 — son
  `designide370.bpl` procède de même. Il sépare les deux générations
  dans « Known Packages » et dans le dossier BPL. Delphi 12 continue de
  compiler sans suffixe : rien ne change pour l'installation D12.
- **Delphi 13 fournit deux IDE** : 32 bits (`binds.exe`) et 64 bits
  (`bin64ds.exe`). Un IDE 64 bits ne peut charger qu'un paquet
  **Win64** ; les projets D13 sont donc en Win64 et s'enregistrent sous
  **Known Packages x64**. Pour l'IDE 32 bits, passez la plate-forme à
  Win32 dans le Project Manager avant de compiler et utilisez **Known
  Packages**.

---

## 4. Compiler l'EXE autonome

L'autonome est un simple `.exe`. Vous le lancez depuis la ligne de
commande ou par double-clic.

### 4.1 Choisir la plateforme (32 bits vs 64 bits)

64 bits est la valeur par défaut et notre recommandation.

Dans le Project Manager :

1. Dépliez `StaticCodeAnalyser.d12` (cliquez sur la petite flèche).
2. Dépliez **Target Platforms**.
3. **Clic droit** sur `Windows 64-bit (Win64)` → cliquez sur
   **Activate**.
4. **Clic droit** sur `Configuration` → **Release** → cliquez sur
   **Activate**.

Si vous préférez l'EXE 32 bits, prenez `Windows 32-bit (Win32)`.

> **Astuce :** si vous changez d'avis plus tard, faites simplement un
> clic droit sur l'autre plateforme et cliquez de nouveau sur
> **Activate** — vous pouvez compiler les deux versions à tout moment.

### 4.2 Compiler

1. Dans le Project Manager, **clic droit** sur `StaticCodeAnalyser.d12`
   (le nom du projet lui-même, pas Target Platforms).
2. Cliquez sur **Build** (ou **Compile** si Build est grisé).
3. Patientez ~30 secondes. Surveillez la fenêtre **Messages** en bas.

Quand elle se termine par **« Success »**, votre EXE se trouve ici :

```
D:\projects\StaticCodeAnalyser\Output\Win64 Release\StaticCodeAnalyser.d12.exe
```

(Pour Win32 : `Output\Win32 Release\…`. Pour les builds Debug :
`…\Win64 Debug\…`.)

### 4.3 Appliquer le patch de taille de pile (une fois par build)

Le compilateur fixe une pile de 1 Mo. Des fichiers Pascal profonds
peuvent atteindre cette limite et planter. Ouvrez PowerShell dans le
dossier du projet et exécutez :

```powershell
tools\patch-stack-size.ps1 "Output\Win64 Release\StaticCodeAnalyser.d12.exe"
```

Le script affiche `Patched ... SizeOfStackReserve: 1 MB -> 32 MB`.
Vous devez le relancer **après chaque nouveau build**.

---

## 5. Compiler et installer le plugin IDE

Le plugin est un `.bpl` (Borland Package Library) que Delphi charge au
démarrage.

> **Raccourci :** si vous voulez seulement *utiliser* le plugin, cette
> section est inutile — les releases livrent un **EXE d'installation**
> (`StaticCodeAnalyserSetup-<Version>.exe`) et un **paquet GetIt
> local** ; les deux installent le paquet monolithique de release
> (`StaticCodeAnalyser.Plugin.d12.dpk`, un seul `.bpl`, pas de paquets
> moteur séparés). Les étapes ci-dessous compilent le jeu de
> développement de trois paquets depuis les sources.

### 5.1 Compiler le plugin

Le plugin tourne dans l'**IDE 32 bits** (l'IDE 64 bits de 12.3 n'est
pas encore pris en charge). Le plugin doit donc être en 32 bits.

1. Dans le Project Manager, dépliez `StaticCodeAnalyser.IDE.d12`.
2. Dépliez **Target Platforms**.
3. **Clic droit** sur `Windows 32-bit (Win32)` → **Activate**.
4. Passez la configuration active sur **Release** (clic droit sur
   `Configuration` → **Release** → **Activate**).
5. **Clic droit** sur `SCA.Engine` (dans le Project Manager) →
   **Build**. Le plugin a besoin du paquet moteur ; compilez-le
   d'abord.
6. **Clic droit** sur `SCA.SharedUI` → **Build**.
7. **Clic droit** sur `StaticCodeAnalyser.IDE.d12` → **Build**.

> ⚠️ **Chaque projet compile dans SA PROPRE plateforme active.** Les
> étapes 3–4 ne commutent que le projet cliqué. Si `SCA.Engine` est
> encore actif en Win64 pendant que le plugin compile en Win32, le
> plugin échoue avec **`F2613 Unit '…' nicht gefunden`** — il se lie à
> une `SCA.Engine.dcp` Win32 périmée (qui vit hors du dépôt, dans le
> dossier `Dcp` du Studio). Avant l'étape 5, vérifiez que **les trois**
> paquets — `SCA.Engine`, `SCA.SharedUI`, `StaticCodeAnalyser.IDE.d12`
> — affichent **Windows 32-bit** en gras sous leurs Target Platforms.
> Depuis la v0.9.16, les valeurs par défaut versionnées des trois sont
> alignées sur Win32, mais l'IDE mémorise votre dernière sélection par
> projet.

Vous avez maintenant trois fichiers `.bpl` dans
`C:\Users\Public\Documents\Embarcadero\Studio\23.0\Bpl\` :

- `SCA.Engine.bpl`
- `SCA.SharedUI.bpl`
- `StaticCodeAnalyser.IDE.d12.bpl`

### 5.2 Dire à l'IDE de charger le plugin

1. Cliquez sur le menu **Tools → Options**.
2. À gauche, cliquez sur **IDE → Packages → Design Packages**.
3. Cliquez sur **Add…**.
4. Naviguez vers
   `C:\Users\Public\Documents\Embarcadero\Studio\23.0\Bpl\`,
   choisissez `StaticCodeAnalyser.IDE.d12.bpl`, cliquez sur **Open**.
5. Assurez-vous que la case à côté est **cochée**.
6. Cliquez sur **OK**.
7. **Fermez et redémarrez Delphi.**

Après le redémarrage, l'IDE affiche une nouvelle fenêtre ancrable :
**View → Static Code Analysis**.

Si l'entrée de menu manque, le plugin n'a pas pu se charger. Regardez
dans **View → Window List…** ou lisez attentivement les erreurs de
l'écran de démarrage.

---

## 6. Lancer l'autonome — première analyse

L'autonome est le moyen le plus simple de vérifier que tout
fonctionne.

### 6.1 Choisir un dossier de code Pascal

Pour un test rapide, vous pouvez analyser le projet lui-même.

### 6.2 Démarrer

Double-cliquez sur l'EXE que vous avez compilé, **OU** depuis la ligne
de commande :

```cmd
cd D:\projects\StaticCodeAnalyser
"Output\Win64 Release\StaticCodeAnalyser.d12.exe"
```

Une fenêtre s'ouvre avec des **cartes de statistiques** (Erreurs /
Avertissements / Conseils / …) et une grille vide.

### 6.3 Première analyse

1. Dans le champ **Path** en haut, saisissez ou collez votre dossier
   (p. ex. `D:\projects\StaticCodeAnalyser\SCA.Engine\sources`).
2. Cliquez sur le bouton **Analyse**.
3. Patientez — petits projets : 1 à 5 secondes. Gros projets : jusqu'à
   une minute.

La grille se remplit de résultats. Chaque ligne montre : fichier,
méthode, ligne, sévérité, règle, message. Un double-clic sur une ligne
ouvre le fichier à la bonne ligne (Notepad ou votre visionneuse Pascal
par défaut).

### 6.4 Filtrer et trier

- Le champ **Filter** en haut accepte des sous-chaînes du fichier ou
  de la règle.
- Cliquez sur un en-tête de colonne pour trier.
- Cliquez sur une **carte de statistiques** (Erreurs / Avertissements /
  Conseils) pour ne garder que cette sévérité.

### 6.5 Enregistrer le rapport

Utilisez les boutons **Export** (en haut à droite) pour enregistrer en
**HTML**, **JSON**, **SARIF** (pour SonarQube), ou copiez dans le
presse-papiers pour Jira/Markdown.

---

## 7. Utiliser le plugin IDE

Si vous avez terminé la section 5, le plugin est déjà chargé.

### 7.1 Ouvrir la fenêtre de l'analyseur

Menu **View → Static Code Analysis**.

Une fenêtre ancrable apparaît (faites glisser la barre de titre pour
l'ancrer à côté du Project Manager ou comme onglet en bas).

### 7.2 Analyser le fichier actuellement ouvert

1. Ouvrez n'importe quel fichier `.pas` dans l'éditeur.
2. Dans la fenêtre Static Code Analysis, cliquez sur le bouton
   **File**.
3. Le fichier courant est analysé. Les résultats s'affichent dans la
   grille.

### 7.3 Analyser le projet entier

1. Ouvrez votre projet (`.dproj`) dans Delphi.
2. Dans la fenêtre Static Code Analysis, cliquez sur le bouton
   **Analyse**.
3. Le projet entier est analysé. Cela peut prendre de quelques
   secondes à une minute.

### 7.4 Sauter vers un résultat

Cliquez sur une ligne de la grille : l'éditeur saute vers ce fichier
et cette ligne et surligne le code fautif avec un marqueur coloré dans
la gouttière.

### 7.5 Masquer les faux positifs

Clic droit sur un résultat → **Suppress avec `// noinspection`**. Le
plugin écrit au-dessus de la ligne un commentaire qui masque
exactement cette règle à cet endroit. Le résultat disparaît à la
prochaine analyse.

### 7.6 Conseil au survol

Si vous survolez une ligne de résultat, une infobulle montre un
exemple de code **Avant / Après** : à quoi ressemble le problème, et à
quoi ressemble la correction.

---

## 8. Quand ça tourne mal

| Symptôme | Cause la plus probable |
|---|---|
| **« Build failed: unresolved external »** | Vous avez compilé le plugin avant le moteur. Compilez d'abord `SCA.Engine`, puis `SCA.SharedUI`, puis le plugin. |
| **L'entrée de menu du plugin manque après le redémarrage** | Mauvaise plateforme (vous avez compilé Win64 au lieu de Win32) ou mauvais chemin dans `Tools → Options → Packages`. |
| **L'autonome plante après quelques secondes sur un gros projet** | Patch de taille de pile non appliqué. Relancez `tools\patch-stack-size.ps1`. |
| **L'EXE se plaint « file not found » au lancement** | Vous avez déplacé l'EXE hors de son dossier `Output\…`. Remettez-le en place, ou copiez les fichiers `.dcu`/`.bpl` avec lui. |
| **« Cannot find SCA.Engine.bpl »** au chargement du plugin | Le plugin voit `SCA.Engine.bpl` via le chemin de recherche Delphi. Compilez `SCA.Engine` pour la même plateforme (Win32) et la même configuration (Release). |
| **Identificateur non déclaré alors qu'il figure bien dans les sources** | Un paquet prend cette unité dans le **DCP** d'un autre paquet, pas dans les sources. Si ce DCP est plus ancien que les sources, vous compilez contre l'ancien état — et le compilateur désigne l'appel, pas le fichier périmé. Lancez `python tools\stale_artifacts_check.py`, puis recompilez dans l'ordre `SCA.Engine` -> `SCA.SharedUI` -> plugin. |

---

## 9. Et ensuite

- **Configurer l'analyseur :** ouvrez `analyser.ini` dans
  `%APPDATA%\StaticCodeAnalyser\`. Vous pouvez régler `Profile=`
  (quelles règles s'exécutent), `MinSeverity=`, `MinConfidence=`, etc.
  Le fichier est commenté.
- **Se connecter à SonarQube :** voir [sonarHowto_fr.md](sonarHowto_fr.md).
- **Lancer depuis la ligne de commande / la CI :** voir la sortie
  `--help` de l'EXE autonome. Options utiles : `--profile`,
  `--report-sarif`, `--quiet`, `--time-detectors`.
- **Essayer l'interface en allemand :** dans la fenêtre de
  l'analyseur, passez la langue sur **Deutsch** dans la barre d'outils.

---

## 10. Où poser vos questions

- **Issues GitHub :**
  https://github.com/nrodear/StaticCodeAnalyser/issues
- **Docs Embarcadero (questions Delphi générales) :**
  https://docwiki.embarcadero.com/RADStudio/en/Main_Page

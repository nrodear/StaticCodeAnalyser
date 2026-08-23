# HowTo : compiler et lancer les tests
🇬🇧 [English version](HowTo_Tests.md) · 🇩🇪 [Deutsche Fassung](HowTo_Tests_de.md)

La suite de tests DUnitX (`StaticCodeAnalyserForm\tests\TestProject.dproj`)
a besoin de **deux composants externes**. Sans eux, « Build all projects »
échoue avec `F2613 Unit '...' not found`.

| Composant | Obligatoire | Rôle |
|---|---|---|
| **DUnitX** | obligatoire | Framework de test (Assert / attributs `[Test]` / runner) |
| **TestInsight** | Win32 optionnel | Intégration IDE (panneau de tests, statut en direct) |

Le moteur SCA proprement dit et l'EXE autonome fonctionnent
indépendamment — les tests ne concernent que les développeurs. Si vous
voulez seulement compiler le SCA, vous pouvez exclure le TestProject du
build IDE (voir les solutions de contournement plus bas).

---

## Installation

### DUnitX (obligatoire — les deux plateformes)

```bash
cd D:\git-demos\delphi
git clone https://github.com/VSoftTechnologies/DUnitX.git dunitx
```

Dans `TestProject.dproj`, le chemin `..\..\..\dunitx\Source` figure déjà
dans `DCC_UnitSearchPath` (commit `3f1cab0`). Répertoire parent
différent ? Adaptez le chemin dans le dproj ou définissez-le globalement
via Tools → Options → Language → Delphi → Library (séparément pour
**Win32 et Win64**).

### TestInsight (optionnel — intégration IDE Win32)

De préférence via le **GetIt Package Manager** :

1. IDE RAD Studio → Tools → GetIt Package Manager
2. Rechercher « TestInsight » → cliquer sur **Install**
3. Redémarrer l'IDE

GetIt règle le chemin de bibliothèque et installe le plugin
automatiquement.

Si l'entrée GetIt manque : chercher `TestInsight Stefan Glienke` sur
GitHub/Bitbucket, cloner manuellement, compiler + installer le
`TestInsight.RADxx.dpk`, puis ajouter `Source/` au chemin de
bibliothèque Win32.

---

## Cibles de build

| Cible de build | Plateforme | Prérequis |
|---|---|---|
| SCA.Engine290.bpl | Win32 + Win64 | rtl, rien d'externe |
| SCA.SharedUI290.bpl | **Win32 uniquement** | rtl, vcl, designide (IDE uniquement) |
| StaticCodeAnalyser.exe (autonome) | Win32 + Win64 | rien d'externe |
| StaticCodeAnalyser.IDE.bpl | **Win32 uniquement** | rtl, vcl, designide |
| **TestProject.exe** | Win32 + Win64 | **DUnitX** + (Win32 : TestInsight) |

« Build all projects » compile les 5 cibles sur la plateforme
actuellement sélectionnée.

---

## Lancer les tests

### IDE (Win32 avec TestInsight)

Configuration standard. Le panneau de tests affiche les résultats en
direct ; un clic sur un test en échec saute à l'assertion.

### IDE sans TestInsight (Win32 ou Win64)

Lancez `TestProject.exe` comme console autonome — le logger console de
DUnitX est alors utilisé (voir `TestProject.dpr`, lignes 18-20) :

```powershell
".\Output\Tests\Win64 Release\TestProject.exe"
```

Code de sortie 0 = tout est vert. Les échecs sortent sur stdout + en XML
NUnit à côté de l'EXE (via `DUnitX.Loggers.Xml.NUnit`).

### Lancer un sous-ensemble

La ligne de commande DUnitX accepte des filtres :

```powershell
TestProject.exe --include:TTestUninitVar
TestProject.exe --exclude:TTestPerformance
```

---

## Solutions de contournement

### Exclure complètement TestProject du build

Si les tests ne sont pas pertinents pour l'instant et que seul le SCA
doit être compilé : dans l'IDE → clic droit sur le groupe de projets →
**Build order** → décocher `TestProject.dproj`. « Build all projects »
saute alors ce projet.

De façon équivalente, commentez l'entrée TestProject directement dans le
`.groupproj`.

### Define TESTINSIGHT limité à une plateforme

Dans `TestProject.dproj`, le define n'est actif que pour Win32
(ligne 133) :

```xml
<PropertyGroup Condition="'$(Base_Win32)'!=''">
  <DCC_Define>TESTINSIGHT;$(DCC_Define)</DCC_Define>
</PropertyGroup>
```

Le build Win64 saute donc automatiquement les imports TestInsight et n'a
pas besoin du plugin. Si vous ne voulez pas du tout de TestInsight,
supprimez l'entrée purement et simplement.

### Dialogue EFOpenError pendant l'exécution des tests

Plusieurs tests lèvent délibérément des exceptions (`EFOpenError`,
`Exception`, etc.) pour vérifier la gestion des erreurs. Le débogueur de
l'IDE les intercepte et affiche un dialogue. Contournement :

- **Dans le dialogue :** cocher « Ignore this exception type » +
  continuer
- **Durablement :** Run → Run Without Debugging (`Ctrl+Shift+F9`) au
  lieu de F9 — le débogueur n'intervient alors plus du tout
- **Sélectivement :** Tools → Options → Debugger Options → Language
  Exceptions → ajouter la classe d'exception à la liste des exceptions
  ignorées

### E2532 spécifique à Win64 sur `Assert.AreEqual(N, X.Count)`

L'inférence générique échoue sous Win64 quand un littéral entier non
typé et un Integer sont combinés. Correctif : paramètre de type
explicite `Assert.AreEqual<Integer>(N, X.Count)`. Déjà corrigé à
1209 endroits de la suite (commit `5f1661c`). À garder en tête pour les
nouveaux tests.

---

## Fichiers associés dans le dépôt

- `StaticCodeAnalyserForm\tests\TestProject.dproj` — configuration du projet de test
- `StaticCodeAnalyserForm\tests\TestProject.dpr` — code du runner de tests
- `StaticCodeAnalyserForm\tests\uTest*.pas` — les unités de test individuelles
- `HowTo_AddDetector.md` — quand un nouveau détecteur + ses tests sont à créer
- `HowTo_DetectorSelftest.md` — workflow de dogfooding pour l'EXE SCA

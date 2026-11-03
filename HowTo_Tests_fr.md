# HowTo : compiler et lancer les tests
🇬🇧 [English version](HowTo_Tests.md) · 🇩🇪 [Deutsche Fassung](HowTo_Tests_de.md)

La suite de tests DUnitX (`StaticCodeAnalyserForm\tests\TestProject.dproj`)
a besoin de **deux composants externes**. Sans eux, « Build all projects »
échoue avec `F2613 Unit '...' not found`.

| Composant | Obligatoire | Rôle |
|---|---|---|
| **DUnitX** | obligatoire | Framework de test (Assert / attributs `[Test]` / runner) |
| **TestInsight** | obligatoire dans l'état actuel du dépôt (voir plus bas) | Intégration IDE (panneau de tests, statut en direct) |

Le moteur SCA proprement dit et l'EXE autonome fonctionnent
indépendamment — les tests ne concernent que les développeurs. Si vous
voulez seulement compiler le SCA, vous pouvez exclure les deux projets de
test du build IDE (voir les solutions de contournement plus bas).

---

## Installation

### DUnitX (obligatoire — les deux plateformes)

```bash
cd D:\projects
git clone https://github.com/VSoftTechnologies/DUnitX.git dunitx
```

À cloner à côté du dépôt : dans `TestProject.dproj`, le chemin
`..\..\..\dunitx\Source` figure déjà dans `DCC_UnitSearchPath`. Répertoire
parent différent ? Adaptez le chemin dans le dproj ou définissez-le
globalement via Tools → Options → Language → Delphi → Library (séparément
pour **Win32 et Win64**).

### TestInsight (obligatoire aujourd'hui — Win32 et Win64)

Les deux projets de test définissent `TESTINSIGHT` (voir _Le define
TESTINSIGHT_ plus bas) ; dans l'état actuel du dépôt, ils ne compilent
donc pas sans les unités TestInsight, sur Win32 comme sur Win64.

De préférence via le **GetIt Package Manager** :

1. IDE RAD Studio → Tools → GetIt Package Manager
2. Rechercher « TestInsight » → cliquer sur **Install**
3. Redémarrer l'IDE

GetIt règle le chemin de bibliothèque et installe le plugin
automatiquement.

Si l'entrée GetIt manque : chercher `TestInsight Stefan Glienke` sur
GitHub/Bitbucket, cloner manuellement, compiler + installer le
`TestInsight.RADxx.dpk`, puis ajouter `Source/` aux chemins de
bibliothèque Win32 et Win64.

---

## Cibles de build

| Cible de build | Plateforme | Prérequis |
|---|---|---|
| SCA.Engine290.bpl | Win32 + Win64 | rtl, rien d'externe |
| SCA.SharedUI290.bpl | Win32 + Win64 | rtl, vcl, vclwinx, SCA.Engine |
| StaticCodeAnalyser.d12.exe (autonome) | Win32 + Win64 | rien d'externe |
| StaticCodeAnalyser.IDE.d12.bpl | Win32 ; Win64 **sous Delphi 13 uniquement** | rtl, vcl, vclwinx, designide, SCA.Engine, SCA.SharedUI |
| reDelphix.d12.bpl | Win32 ; Win64 **sous Delphi 13 uniquement** | rtl, vcl, designide, SCA.Engine |
| **TestProject.exe** | Win32 + Win64 | **DUnitX** + TestInsight (voir plus bas) |

« Build all projects » compile chaque projet du groupe dans sa propre
plateforme active ; chaque projet mémorise la sienne. Vérifiez-les avant
(voir [HowTo_Build_fr.md](HowTo_Build_fr.md), section 5.1). Sous Delphi 12,
les deux paquets de conception s'arrêtent sur Win64 avec
`{$MESSAGE FATAL}`.

---

## Lancer les tests

### IDE (Win32 avec TestInsight)

Configuration standard. Le panneau de tests affiche les résultats en
direct ; un clic sur un test en échec saute à l'assertion.

### IDE sans TestInsight (Win32 ou Win64)

> **ATTENTION — compilé tel que le dépôt est aujourd'hui, cela ne marche
> PAS, et l'exécution en console a pourtant l'air d'un succès.**
> `TestProject.dproj` définit `TESTINSIGHT` comme `DCC_Define` dans le
> PropertyGroup **Base**, donc pour TOUTES les configurations et
> plateformes. Le `{$IFNDEF TESTINSIGHT}` du `.dpr` ne s'applique donc pas :
> l'EXE reçoit le sous-système **GUI** au lieu de Console et passe par
> `TestInsight.DUnitX` au lieu du logger console. Sans serveur TestInsight
> dans l'IDE, il se termine aussitôt par `Halt(0)` : **pas de stdout, pas
> de XML NUnit, code de sortie 0.**
>
> Mesuré le 2026-09-20 sur les deux EXE fraîchement compilés (Win32 et
> Win64) : sous-système PE 2 = GUI, 0 ligne de sortie, sortie 0.
>
> **Le code de sortie 0 n'est donc PAS une preuve de test** — on ne peut
> pas le distinguer de « tout est vert ». Les résultats n'existent que dans
> le panneau TestInsight de l'IDE. Pour une vraie exécution en console,
> retirez d'abord `TESTINSIGHT` du groupe Base du `.dproj`.

La voie d'origine (valable uniquement SANS le define) :

```powershell
".\Output\Tests\Win64 Release\TestProject.exe"
```

Alors : code de sortie 0 = tout est vert, les échecs sortent sur stdout +
en XML NUnit à côté de l'EXE (via `DUnitX.Loggers.Xml.NUnit`).

### Lancer un sous-ensemble

Uniquement sans le define `TESTINSIGHT` (voir plus haut) : avec lui, l'EXE
n'atteint jamais `TDUnitX.CheckCommandLine` et ignore tous les
commutateurs.

`--run` (forme courte `-r`) choisit les tests par leur nom. DUnitX nomme
une fixture d'après son unité et sa classe (`unite.classe`), un test
d'après sa méthode (`unite.classe.methode`). Un nom sélectionne chaque
test dont le nom de fixture commence par lui (sans tenir compte de la
casse), un nom de test complet sélectionne ce seul test. Plusieurs noms se
séparent par des virgules ; `--run` peut aussi être répété :

```powershell
TestProject.exe --run:uTestUninitVar.TTestUninitVar
TestProject.exe --run:uTestUninitVar.TTestUninitVar.NeverWritten_OnlyRead_Flagged
TestProject.exe --run:uTestUninitVar.TTestUninitVar,uTestPerformance.TTestPerformance
```

Le seul nom de classe (`--run:TTestUninitVar`) ne trouve rien, car le nom
de fixture commence par l'unité.

`--include` et `--exclude` filtrent par `[Category]`, pas par nom de
classe. Dans ce projet, seul `TTestPerformance` porte une catégorie
(`perf`) :

```powershell
TestProject.exe --exclude:perf
```

---

## Solutions de contournement

### Exclure complètement les projets de test du build

Si les tests ne sont pas pertinents pour l'instant et que seul le SCA
doit être compilé : dans l'IDE → clic droit sur le groupe de projets →
**Build order** → décocher `TestProject.dproj` et `reDelphix.Test.dproj`.
« Build all projects » saute alors les deux. `reDelphix.Test.dproj` exige
lui aussi DUnitX et définit `TESTINSIGHT` en Debug et en Release.

De façon équivalente, commentez les deux entrées directement dans le
`.groupproj`.

### Le define TESTINSIGHT

Dans `TestProject.dproj`, le define se trouve dans le groupe Base, il
s'applique donc à toutes les plateformes et configurations :

```xml
<PropertyGroup Condition="'$(Base)'!=''">
  <DCC_Define>TESTINSIGHT;$(DCC_Define)</DCC_Define>
</PropertyGroup>
```

Le build Win64 a donc lui aussi besoin des unités TestInsight. Si vous ne
voulez pas du tout de TestInsight, supprimez l'entrée purement et
simplement ; le logger console prend alors le relais.

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
1209 endroits de la suite. À garder en tête pour les nouveaux tests.

---

## Fichiers associés dans le dépôt

- `StaticCodeAnalyserForm\tests\TestProject.dproj` — configuration du projet de test
- `StaticCodeAnalyserForm\tests\TestProject.dpr` — code du runner de tests
- `StaticCodeAnalyserForm\tests\uTest*.pas` — les unités de test individuelles
- `reDelphix\tests\reDelphix.Test.dproj` — tests des actions de code reDelphix ;
  sa configuration `CI` est un runner console avec un vrai code de sortie

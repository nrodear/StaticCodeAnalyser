# SCA.CLI.Demo

🇬🇧 [English version](README.md) · 🇩🇪 [Deutsche Fassung](README_de.md) · Référence complète du moteur/API : [../SCA.Engine/API_fr.md](../SCA.Engine/API_fr.md)

Consommateur d'exemple minimal de l'**API du moteur SCA** (`uEngineApi`).

Il démontre que l'analyse statique complète est utilisable à travers la
façade publique **sans connaître le code source du moteur** : ce projet
référence exclusivement le package d'exécution **`SCA.Engine`**
(`DCC_UsePackage`) — **aucun** répertoire de sources du moteur ne figure
dans le chemin de recherche.

Le programme analyse un répertoire récursivement et n'affiche qu'un
**résumé de métriques**.

## L'API utilisée

| API | Rôle |
|-----|------|
| `ScanRecursive(path, profile): TScanResult` | Analyse récursive en une ligne. |
| `TScanResult.FindingCount / ErrorCount / WarningCount / HintCount` | Métriques de sévérité. |
| `TScanResult.Findings` (`TObjectList<TLeakFinding>`) | Accès au détail. |
| `TLeakFinding.FindingType` / `.FileName` | Ventilation par catégorie + nombre de fichiers. |

C'est là toute la surface — une preuve nette que la façade seule suffit.
Pour plus de contrôle (profils, MinSeverity, référence, liste
d'exclusions, export SARIF/Sonar/HTML), il existe `TScanRequest.Init` +
`TAnalysisSession.Run` et `TScanResult.WriteSarif/WriteSonar/WriteHtml`
— voir [../SCA.Engine/API_fr.md](../SCA.Engine/API_fr.md).

## Compilation (RAD Studio / Delphi 12)

L'ordre compte — le package doit exister avant la démo :

1. Compiler `SCA.Engine.dproj` pour la plateforme cible (produit
   `SCA.Engine.dcp` + `SCA.Engine.bpl` dans le répertoire DCP/BPL global).
2. Ouvrir et compiler `SCA.CLI.Demo.dproj` (EXE console, Win32 ou Win64).

Le plus simple : placer les deux projets dans un même groupe de projets.
La liaison du package passe par `DCC_UsePackage SCA.Engine` (aucun
chemin de sources).

> À l'exécution, `SCA.Engine.bpl` doit être localisable (le répertoire
> BPL global est sur le chemin quand RAD Studio est installé ; pour un
> déploiement autonome, livrer la `.bpl` à côté de l'`.exe`).

## Utilisation

```
SCA.CLI.Demo.exe [<path>] [<profile>]
```

| Argument | Signification |
|----------|---------------|
| `<path>`    | Répertoire racine (défaut : répertoire courant) |
| `<profile>` | facultatif. `''` = tous les détecteurs (défaut). Connus : `default`, `strict`, `ide-fast`, `security`, `bugs-only`, `code-quality`, `dfm-only` |

Code de sortie (comme la CLI) : `0` = propre, `3` = résultats présents,
`1`/`2` = erreur.

## Exemple de sortie

```
========================================================
 SCA CLI Demo - Kennwert-Statistik
========================================================
  Pfad         : D:\myproject
  Profil       : (alle Detektoren)
  Dauer        : 1082 ms
  Dateien      : 174 (mit Funden)
--------------------------------------------------------
  Funde gesamt : 714

  Nach Schweregrad:
    Fehler  (Error)  : 0
    Warnung (Warning): 206
    Hinweis (Hint)   : 508

  Nach Kategorie:
    Bug              : 2
    Code Smell       : 705
    Vulnerability    : 0
    Security Hotspot : 0
    Duplication      : 7
    File Error       : 0
========================================================
```

*(La sortie du programme elle-même est en allemand ; signification des
indicateurs : Pfad=chemin, Dauer=durée, Dateien=fichiers avec résultats,
Funde gesamt=total des résultats, Nach Schweregrad=par sévérité
[Fehler=erreur, Warnung=avertissement, Hinweis=conseil], Nach
Kategorie=par catégorie.)*

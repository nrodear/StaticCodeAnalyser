# SCA.Engine — Engine & API
🇬🇧 [English version](API.md) · 🇩🇪 [Deutsche Fassung](API_de.md)

Analyse statique de code pour Delphi/Object Pascal sous forme de package
d'exécution réutilisable. Ce document décrit le **moteur** (architecture,
pipeline) et l'**API publique** (`uEngineApi`) par laquelle un consommateur
lance l'analyse complète sans connaître les unités internes.

> Exemple minimal exécutable : [../SCA.CLI.Demo/](../SCA.CLI.Demo/).

- **Package :** `SCA.Engine` (`requires rtl;` — aucune dépendance VCL/FMX)
- **Version :** 0.9.14 (`uSCAConsts.SCA_VERSION`)
- **Périmètre :** ~196 détecteurs (IDs de règle `SCA001`–`SCA196`)

---

## 1. Architecture

Le moteur est une pure bibliothèque d'analyse, sans interface. Flux de
données d'une analyse :

```
  .pas / .dfm
      │
      ▼
  Lexer (uLexer)  ──►  Parser (uParser2)  ──►  AST (uAstNode)
                                                   │
                              ┌────────────────────┤
                              ▼                    ▼
                      Détecteurs AST        Détecteurs ligne/token
                      (~178 règles, une uXxx.pas chacune)
                              │
                              ▼
                     Liste TLeakFinding
                              │
   ┌──────────────────────────┼───────────────────────────────┐
   ▼                          ▼                                 ▼
 Suppression            Filtre de confiance                 Baseline
 (uSuppression:         (uConfidenceFilter:                (uBaseline:
  // noinspection)       MinConfidence)                     résultats connus)
   └──────────────────────────┼───────────────────────────────┘
                              ▼
                         TScanResult
                              │
                ┌─────────────┼─────────────┐
                ▼             ▼             ▼
             SARIF          Sonar          HTML
        (uExportSARIF) (uExportSonar…) (uExportHtml)
```

Infrastructure transversale :

- **`uAnalyzeContext`** — détient les caches propres à chaque analyse
  (cache AST, index des références de symboles, index du dépôt DFM).
  Transmis à travers les détecteurs ; aucun état global par analyse.
- **`uStaticFiles`** — collecte récursive des fichiers avec exclusions par
  défaut (`__history`, `__recovery`, `.git`, `.svn`, `node_modules`) +
  filtre d'exclusions/de tests (`uIgnoreList`).
- **`uRuleCatalog`** — métadonnées des règles (ID, titre, sévérité, type) +
  profils.
- **`uRepoSettings`** — configuration `analyser.ini` (seuils, profils,
  surcharges de chemins, règles personnalisées).

---

## 2. Démarrage rapide

Une analyse récursive en une ligne :

```pascal
uses uEngineApi;

var Res: TScanResult;
begin
  Res := ScanRecursive('C:\monprojet');   // tous les détecteurs, limites par défaut
  try
    WriteLn('Résultats : ', Res.FindingCount,
            '  (erreurs ', Res.ErrorCount,
            ', avertissements ', Res.WarningCount,
            ', conseils ', Res.HintCount, ')');
  finally
    Res.Free;   // libère aussi la liste des résultats
  end;
end;
```

Un exemple complet et exécutable est le projet **`SCA.CLI.Demo`**.

---

## 3. L'API : `uEngineApi`

La façade se compose d'un record de requête, d'un objet résultat, d'une
classe de session et de deux fonctions de commodité.

### 3.1 Points d'entrée

| Appel | Rôle |
|-------|------|
| `ScanRecursive(APath, AProfile=''): TScanResult` | Analyse récursive d'un répertoire (une ligne). |
| `AnalyzeSource(ASource, AProfile=''): TScanResult` | Analyse en mémoire d'une chaîne de code source (lint d'éditeur/intégration). |
| `TAnalysisSession.Create.Run(Req): TScanResult` | Accès complet via `TScanRequest` (toutes les options). |

### 3.2 `TScanRequest`

Remplir via `TScanRequest.Init` avec des valeurs par défaut raisonnables
(`ssRecursive`, tous les détecteurs, seuils les plus permissifs), puis
surcharger de façon ciblée.

| Champ | Type | Signification |
|-------|------|---------------|
| `Scope` | `TScanScope` | Type d'analyse (voir 3.5). Défaut `ssRecursive`. |
| `Path` | `string` | Racine (récursif) / fichier (unique) / répertoire de base (liste). |
| `Files` | `TArray<string>` | Liste de fichiers explicite pour `ssFileList`. |
| `Source` | `string` | Code source en mémoire pour `ssSource`. |
| `VcsRange` | `string` | `ssVcsChanged` : `''`=auto, sinon `shaA..shaB`. |
| `Profile` | `string` | `''`=tous les détecteurs, sinon nom de profil (voir 3.6). |
| `MinSeverity` | `TLeakSeverity` | Les résultats sous ce seuil sont écartés. |
| `MinConfidence` | `TFindingConfidence` | Seuil anti-faux-positifs (défaut `fcMedium`). |
| `MaxFileBytes` | `Integer` | `<=0` → défaut du moteur (5 Mo). |
| `UsesCheck` | `Boolean` | Exécuter le coûteux détecteur de `uses` inutilisés. |
| `AutoDiscover` | `Boolean` | Découvrir les classes personnalisées pendant l'analyse. |
| `IfdefDefines` | `TArray<string>` | Parsing sensible aux `{$IFDEF}` avec ces defines. |
| `CustomRulesPath` | `string` | YAML de règles personnalisées (`''`=aucune). |
| `BaselinePath` | `string` | Filtrer les résultats contre un JSON de référence (`''`=désactivé). |
| `WriteBaselinePath` | `string` | Écrire les résultats actuels comme nouvelle référence. |
| `ApplyRepoIni` | `Boolean` | Charger + appliquer intégralement `analyser.ini` (comme la CLI). |
| `MinSeverityName` | `string` | Mode INI : surcharge `'error'`/`'warning'`/`'hint'`. |
| `ConfigRoot` | `string` | Mode INI : racine pour la résolution INI/règles. |
| `SkipConfig` | `Boolean` | `true` : n'appliquer aucune config (le consommateur a posé l'état lui-même). |
| `SingleFileProjectRoot` | `string` | `ssSingleFile` : racine de projet pour l'index inter-unités. |
| `IgnoreList` | `TIgnoreList` | `ssRecursive` : filtre d'exclusions/de tests (`nil`=aucun). |
| `Progress` | `TProc<Integer,Integer>` | `(current,total)` ; un `EAbort` levé dedans interrompt. |

### 3.3 `TScanResult`

Possède la liste des résultats ; libérer avec `.Free` (libère aussi les
résultats, sauf après `ReleaseFindings`).

```pascal
TScanResult = class
  function FindingCount: Integer;     // total
  function ErrorCount:   Integer;     // sévérité lsError
  function WarningCount: Integer;     // sévérité lsWarning
  function HintCount:    Integer;     // sévérité lsHint
  property Findings: TObjectList<TLeakFinding>;   // accès au détail
  property BaseDir:  string;                       // racine de l'analyse

  function ReleaseFindings: TObjectList<TLeakFinding>;  // céder la propriété

  procedure WriteSarif(const AFileName: string;
                       const AToolName: string = SCA_DEFAULT_TOOLNAME);
  procedure WriteSonar(const AFileName: string);
  procedure WriteHtml (const AFileName: string);
end;
```

### 3.4 Modes de configuration

`TAnalysisSession.Run` décide d'après la requête d'où provient la
configuration des détecteurs :

1. **Direct (défaut) :** uniquement les champs de la requête (`Profile`,
   `MinSeverity`, `MinConfidence`, `MaxFileBytes`, `IfdefDefines`,
   `CustomRulesPath`). Pas d'`analyser.ini`. → c'est ce que font
   `ScanRecursive`/`AnalyzeSource`.
2. **`ApplyRepoIni := True` :** charge `analyser.ini` (depuis
   `ConfigRoot`/`Path`) et l'applique intégralement — 8 seuils, surcharges
   de chemins, listes magic/format, profil INI + règles personnalisées
   INI. C'est ainsi que fonctionne la CLI.
3. **`SkipConfig := True` :** `Run` n'applique **aucune** config — le
   consommateur a déjà posé lui-même l'état global des détecteurs/seuils
   (c'est ce que font le plugin IDE et la Form via leur propre
   préparation). `Run` ne fait alors que scope → analyse → référence.

### 3.5 Scopes (`TScanScope`)

| Valeur | Description |
|--------|-------------|
| `ssRecursive` | Répertoire récursif (défaut). Utilise `Path` + `IgnoreList` en option. |
| `ssSingleFile` | Un seul fichier `.pas` (`Path`) ; avec `SingleFileProjectRoot`, index de symboles à l'échelle du projet. |
| `ssFileList` | Liste de fichiers explicite (`Files`) ; `Path` = répertoire de base optionnel. |
| `ssVcsChanged` | Uniquement les fichiers modifiés selon le VCS (`Path`=dépôt, `VcsRange` en option). |
| `ssSource` | Code source en mémoire (`Source`) ; `Path`=nom logique optionnel. |

### 3.6 Profils

Un profil est une liste blanche de types de résultats. `''` (vide) =
**tous** les détecteurs. Profils intégrés (`uRuleCatalog`) :

| Profil | Contenu |
|--------|---------|
| `default` / `strict` | Toutes les règles. |
| `ide-fast` | Sous-ensemble rapide pour l'analyse en direct (bugs + vulnérabilités + DFM critique). |
| `security` | Vulnérabilités/secrets uniquement (SQLInjection, HardcodedSecret, …). |
| `bugs-only` | Vrais bugs uniquement (fuites, NilDeref, DivByZero, FormatMismatch, …). |
| `code-quality` | Code smells (LongMethod, MagicNumber, Cyclomatic, duplications, …). |
| `dfm-only` | Règles DFM/fiches uniquement. |

### 3.7 Modèle de données : `TLeakFinding` (`uMethodd12`)

Chaque résultat :

| Membre | Type / retour | Signification |
|--------|---------------|---------------|
| `FileName` | `string` | Fichier source. |
| `MethodName` | `string` | Méthode/routine (si connue). |
| `LineNumber` / `LineInt` | `string` / `Integer` | Ligne (champ chaîne + assistant entier). |
| `MissingVar` / `Message` | `string` | Message de détail (`Message` = alias). |
| `Severity` | `TLeakSeverity` | `lsError` / `lsWarning` / `lsHint`. |
| `Kind` | `TFindingKind` | Type de règle concret (`fkXxx`). |
| `Confidence` | `TFindingConfidence` | `fcLow` / `fcMedium` / `fcHigh`. |
| `RuleID` | `string` | ID de règle personnalisée (sinon vide). |
| `FindingType` | `TFindingType` | Catégorie (voir ci-dessous). |
| `SeverityText` / `TypeText` | `string` | Libellés lisibles. |
| `ResolvedRuleId` | `string` | `SCAxxx` (RuleID si défini, sinon consultation du catalogue). |

Enums (`uSCAConsts`) :

```pascal
TLeakSeverity     = (lsError, lsWarning, lsHint);
TFindingConfidence= (fcLow, fcMedium, fcHigh);
TFindingType      = (ftBug, ftCodeSmell, ftVulnerability,
                     ftSecurityHotspot, ftCodeDuplication, ftFileError);
```

---

## 4. Cycle de vie / threading

- Le moteur n'est **pas thread-safe** (état global partagé de
  configuration et de cache). Une analyse à la fois par processus.
- L'**analyse récursive** est sûre pour des processus éphémères à analyse
  unique (CLI/démo). Dans les hôtes résidents (IDE), préférer la voie
  fichier unique/source.
- `TScanResult` possède les résultats ; `Free` les libère. Avec
  `ReleaseFindings`, la propriété passe à l'appelant.

---

## 5. Référencer le package (mise en place côté consommateur)

Un consommateur tiers n'a besoin que du **package**, d'aucune source du
moteur :

- `.dproj` : `UsePackages=true` et `DCC_UsePackage` contient `SCA.Engine;rtl`.
- **Aucun** répertoire de sources du moteur dans `DCC_UnitSearchPath`.
- À l'exécution, `SCA.Engine290.bpl` doit être trouvable (répertoire BPL
  global ou à côté de l'`.exe`).
- `uses uEngineApi;` (+ `uMethodd12`, `uSCAConsts` pour l'accès au détail)
  — le tout depuis le package.

Exemple complet, `.dpr`/`.dproj` inclus : **`SCA.CLI.Demo`**.

---

## 6. Exemples

**Profil + export SARIF :**

```pascal
var Res := ScanRecursive('C:\src', 'security');
try
  Res.WriteSarif('report.sarif');
finally
  Res.Free;
end;
```

**Requête complète (mode INI, référence, progression) :**

```pascal
var Req := TScanRequest.Init;
Req.Path          := 'C:\src';
Req.ApplyRepoIni  := True;            // appliquer analyser.ini intégralement
Req.BaselinePath  := 'baseline.json'; // masquer les résultats connus
Req.Progress      := procedure(C, T: Integer)
                     begin Write(#13, C, '/', T); end;

var Ses := TAnalysisSession.Create;
try
  var Res := Ses.Run(Req);
  try
    Res.WriteSonar('sonar.json');
  finally
    Res.Free;
  end;
finally
  Ses.Free;
end;
```

**En mémoire (lint d'éditeur) :**

```pascal
var Res := AnalyzeSource(EditorBuffer.Text);
try
  for var F in Res.Findings do
    WriteLn(F.LineInt, ': [', F.ResolvedRuleId, '] ', F.Message);
finally
  Res.Free;
end;
```

---

## 7. Convention de codes de sortie (CLI/outils)

Les outils autonomes utilisent en général : `0` = propre, `3` = résultats
présents, `1`/`2` = erreur (exception / chemin invalide). Voir
`SCA.CLI.Demo`.

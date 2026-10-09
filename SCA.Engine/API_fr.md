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

### 3.8 Emplacements source : `TSourcePlaces` (`uSourcePlaces`)

Décrit des emplacements d'un fichier source **à la demande** — pour les consommateurs qui veulent réécrire du code (p. ex. le module « Source Refactor » reDelphix). Le service ne fait que lire : aucun scan ne tourne, aucun résultat, champ ou export n'est touché, et aucun détecteur ne l'utilise. Une instance par fichier.

`uEngineApi` réexporte les types classe et record : `TSourcePlaces`, `TNodeRef`, `TSourceLineRange`, `TUsesSection`, `TNodeKind`, `TNodeKinds`, `TRefactorInfo`, `TRefactorSpan`. Il ne réexporte **pas** les constantes ni les valeurs d'énumération : les rôles (`ROLE_*`), les types de valeur (`rv*`, `TRefactorValueType`) et les indicateurs (`rf*`, `TRefactorFlags`) demandent `uses uRefactorInfo`, la version du contrat `SOURCE_PLACES_VERSION` demande `uses uSourcePlaces`. Les deux unités font partie du package.

```pascal
Places := TSourcePlaces.Create;
try
  try
    Opened := Places.Open(FileName);    // False : fichier illisible
  except
    on E: Exception do
    begin
      Log(E.Message);                   // erreur du parseur, watchdog compris
      Opened := False;                  // rien n'est ouvert (IsOpen = False)
    end;
  end;
  if Opened then
  begin
    Nodes := Places.NodesAt(Line, [TNodeKind.nkAssign]);   // ligne du résultat -> nœuds AST
    if Length(Nodes) = 1 then
    begin
      Info := Places.ChainOf(Nodes[0].Line, Nodes[0].Col, Nodes[0].Name);
      try
        if Assigned(Info) and Info.FixSafe then
          ...                                              // construire la réécriture
      finally
        Info.Free;
      end;
    end;
  end;
finally
  Places.Free;
end;
```

| Membre | Retourne | Signification |
|--------|----------|---------------|
| `Open(FileName)` / `Close` | `Boolean` | Lit lui-même le fichier (ni cache de scan, ni verrou moteur) et analyse exactement le texte décodé. `False` si illisible. Une erreur du parseur (watchdog du parseur compris) **lève une exception** ; le service est ensuite fermé (`IsOpen = False`). Un texte ouvert auparavant est d'abord abandonné. |
| `OpenSource(FileName, Source)` | `Boolean` | Comme `Open`, mais sur un texte que l'hôte transmet (IDE : le tampon de l'éditeur avec ses modifications non enregistrées). `FileName` n'est que le nom ; le fichier n'est pas lu. `False` pour un texte vide ; une erreur du parseur lève une exception comme avec `Open`. |
| `SetIfdefDefines(Defines)` | | Vue du lexer du prochain `Open`/`OpenSource`. Le service analyse toujours dans sa propre vue, jamais dans la vue globale au processus qu'un scan en cours définit à partir de `TScanRequest.IfdefDefines`. `nil` ou vide (par défaut) = les deux branches de chaque `{$IFDEF}` ; sinon une seule branche avec exactement ces defines — un consommateur qui connaît la vue de l'exécution (`TScanRequest.IfdefDefines`) obtient alors nœuds et types dans la même vue que les résultats. Exception : pour une exécution `dlFpc` avec une liste de defines non vide (imposée aussi pour les projets `.lpi`/`.lpk`/`.lpg`), le scan ajoute `FPC` et `LCL` (`TAnalysisSession.ApplyIfdefView`), le service non — pour obtenir la vue des résultats, l'appelant les ajoute lui-même. Les valeurs sont copiées et restent en place après `Close`. Limites de la vue à deux branches : `DeclaredTypeOf` renvoie le type de l'une des branches (la dernière pour les paramètres et variables locales, la première pour les champs et globaux d'unité), et `NodesAt` peut renvoyer des nœuds des deux branches. Les defines des fichiers inclus ne sont pas évalués. |
| `IsOpen` / `FileName` / `LineCount` | `Boolean` / `string` / `Integer` | État du texte ouvert. |
| `StatementAt(Line, Col)` | `TRefactorInfo` | L'instruction qui commence là : plage avec colonnes, indicateurs, point d'insertion, hachage. `nil` si sa fin est indéterminable, y compris quand elle contient une chaîne multiligne Delphi 12 (`'''`). |
| `ChainOf(Line, Col, ExpectedTarget = '', ExpectedPlus = ANY_PLUS_COUNT)` | `TRefactorInfo` | Affectation avec chaîne `+` : cible, littéraux, opérandes, `FixSafe`. Deux contre-vérifications, chacune renvoie `nil` en cas d'écart : la cible contre `ExpectedTarget` (`TNodeRef.Name` ; `''` = pas de vérification) et le nombre de `+` au premier niveau contre `ExpectedPlus`, compté indépendamment par le consommateur (p. ex. depuis `TNodeRef.TypeRef`, comme compte SCA044). Toute valeur négative (`TSourcePlaces.ANY_PLUS_COUNT`) signifie : pas de vérification. |
| `CallOf(Line, Col, ExpectedHead)` | `TRefactorInfo` | Instruction d'appel : tête plus chaîne de l'argument unique, sinon une partie `argument` par argument. `ExpectedHead` est la tête avant la première `(` (`''` = pas de vérification). |
| `NodesAt(Line, Kinds)` | `TArray<TNodeRef>` | Nœuds AST des sortes données qui commencent sur cette ligne, triés par colonne. Deux résultats = ambiguïté. |
| `UsesEntries(Section)` | `TArray<TRefactorSpan>` | Chaque nom d'unité des clauses `uses` avec sa plage (`Resolved` = le nom tel qu'écrit). `usAny` (par défaut) couvre aussi la clause d'un programme ou d'une bibliothèque. |
| `IdentifiersIn(Span)` | `TArray<TRefactorSpan>` | Identificateurs dans une plage, en parties `ident` ; les mots-clés ne sont pas filtrés. Chaînes et commentaires sont exclus — même si la plage commence à l'intérieur de l'un d'eux, car le fichier est lu jusqu'à la plage. Limite : une chaîne multiligne Delphi 12 (`'''`) avant la plage n'est pas reconnue. |
| `CodeViewOf` / `TextOf` / `HashOf` | | Vue code fidèle aux colonnes, texte brut et SHA-256 d'une plage, tous sur le texte du dernier `Open`/`OpenSource`. Dans la vue code, les chaînes sont remplies de `~` (`TRefactorInfoBuilder.VIEW_FILL`), tandis que commentaires et directives de compilation, délimiteurs compris, sont des espaces. `HashOf` ne voit pas une modification ultérieure : pour en détecter une, rouvrir le texte actuel et comparer `HashOf(Info.Span)` à `Info.SpanHash`, ou comparer `TextOf(Span)` au tampon cible juste avant d'écrire (c'est ce que fait reDelphix). |
| `ConditionalRanges` | `TArray<TSourceLineRange>` | Plages `{$IFDEF}` du fichier. |
| `SectionLine(Section)` | `Integer` | Ligne du mot-clé `interface` / `implementation` ; `0` si la section manque (programme, bibliothèque) et pour `usAny`. |
| `LineText(Line)` | `string` | Texte d'une ligne du texte ouvert ; `''` en dehors. |
| `SpanHasComment(Span)` | `Boolean` | `True` si la plage contient un commentaire ou une directive de compilation — pour un consommateur qui ne remplace qu'une partie d'une instruction (`rfHasComment` vaut pour toute l'instruction). |
| `DeclaredTypeOf(Line, Name)` | `string` | Type déclaré (nu, en minuscules) d'un identificateur : paramètre ou variable locale de la routine englobante, sinon champ ou global d'unité ; `''` si inconnu. `string[N]` donne `'shortstring'`, pas `'string'` (le résolveur de types des détecteurs garde `'string'`). `Line` est la **ligne d'ancrage** d'une instruction (ligne d'un nœud AST), pas une ligne de continuation. Ne connaît pas les blocs `with` : renvoie la déclaration trouvée même là où le compilateur lie le nom à un membre de l'expression `with`. |
| `InWithBlock(Line)` | `Boolean` | `True` si la ligne se trouve dans le corps d'une instruction `with` (à la ligne près, de la ligne du `with` à la dernière ligne de nœud de son instruction). À interroger avant de prouver quoi que ce soit à partir de `DeclaredTypeOf`. |
| `CollectNodesAt` / `CollectUsesEntries` / `CollectIdentifiers` | | Fonctions de classe : la même chose sur un arbre, une liste de lignes ou une vue code que l'appelant possède déjà — pour les tests et les consommateurs dotés de leur propre AST. |

**`TNodeRef`** copie les champs de nœud dont un consommateur a besoin : `Kind`, `Line`, `Col`, `Name` (cible ou tête telle que le parseur l'a assemblée) et `TypeRef` (membre droit ou référence de type, aplati). L'arbre lui-même appartient au service et ne vit que jusqu'au prochain `Open`/`Close`.

**Ce que `ChainOf` et `CallOf` prouvent.** Un opérande qui est un simple identificateur reçoit son type déclaré (`rvString`/`rvNonString`, `Resolved` = nom du type), et `FixSafe` est redérivé. L'inconnu reste inconnu : `rvUnknown` et `FixSafe = False` sont le cas normal. Il n'y a aucune preuve `rvString` dans un bloc `with` (`InWithBlock` ; `Resolved` nomme toujours la déclaration trouvée), ni pour un appel RTL connu ou un terme `.ToString` dont le nom est déclaré par une fonction de l'unité elle-même avec un résultat non chaîne — cette fonction masque la routine RTL (p. ex. un `function Trim(..): Variant` local à l'unité). Les appels qualifiés par `SysUtils.`/`StrUtils.` gardent leur preuve. Une fonction déclarée dans une routine imbriquée n'est pas vue (le parseur écarte les routines imbriquées).

Les coordonnées sont à base 1 ; `EndCol` pointe **derrière** le dernier caractère. Chaque primitive sauf `Open`/`OpenSource` est totale (`nil`, vide, `0` ou `False` plutôt qu'une exception, même si rien n'est ouvert). `SOURCE_PLACES_VERSION` (= 1) est la version du contrat — une constante **de compilation** : un consommateur la vérifie avec `{$IF SOURCE_PLACES_VERSION <> 1}{$MESSAGE ERROR '...'}{$IFEND}` (reDelphix le fait dans `uRdxRecipeRunner`) et ne compile alors plus contre un contrat modifié. Elle ne détecte pas une BPL échangée à l'exécution ; c'est le rôle de la liaison de package (DCP/`requires`). La version augmente lors d'un changement de signature d'une primitive existante, de rôles, de coordonnées ou d'une dérivation de `FixSafe`/`ValueType`/`Resolved` qui déclare nouvellement quelque chose comme prouvé ; elle reste pour de nouvelles primitives, de nouveaux paramètres avec valeur par défaut et des dérivations qui ne font que devenir plus strictes.

Par règle, `rules/sca-rules.json` peut porter `anchor` (sur quoi ancrent les résultats : `statement`, `assign`, `call`, `assign-or-call` ; `uses-item` est réservé) et `fixMode` (`none` / `assisted` / `auto`) ; lus via `TRuleCatalog` (`TRuleMeta.Anchor`, `TRuleMeta.FixMode`). Une valeur absente ou inconnue retombe sur le catalogue compilé ; on désactive une règle avec `"fixMode": "none"`.

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
- `uses uEngineApi;` (+ `uMethodd12`, `uSCAConsts` pour l'accès au détail ;
  `uRefactorInfo`, `uSourcePlaces` pour les constantes du service des
  emplacements source, voir 3.8) — le tout depuis le package.

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

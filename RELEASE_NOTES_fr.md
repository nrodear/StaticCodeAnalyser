# Release 0.9.16 — Un presse-papiers silencieux, des filtres honnêtes et un conseil en texte seul

🇬🇧 [English version](RELEASE_NOTES.md) · 🇩🇪 [Deutsche Fassung](RELEASE_NOTES_de.md)

Notes de version complètes : [docs/releases/v0.9.16.md](docs/releases/v0.9.16.md)
([deutsch](docs/releases/v0.9.16_de.md)).

- **Le presse-papiers vous appartient à nouveau.** Sélectionner une
  ligne de résultat n'écrase plus votre presse-papiers par défaut.
  `[UI] ClipboardOnClick` choisit : rien (défaut), un mini-ticket Jira
  compact, ou l'invite Claude AI complète comme avant. Le geste
  délibéré — *Copy AI prompt* dans le menu contextuel, désormais aussi
  dans le dock IDE — fonctionne toujours et copie la ligne cliquée.
  L'extrait de code de l'invite ne peut plus être périmé après que vous
  avez corrigé le fichier.
- **Les filtres disent la vérité.** Les analyses démarrent sur « All » ;
  la liste des sévérités ne propose que des entrées avec des
  occurrences visibles ; et quand *afficher uniquement les nouveaux
  résultats* masque tout, la ligne d'état dit `4 hidden by baseline` au
  lieu de paraître cassée. Un changement de palette recolore
  immédiatement les marqueurs existants.
- **Nouveau : le conseil d'annotation en texte seul.** Quatrième entrée
  de la palette des marqueurs : une ligne transparente (badge + nom de
  la règle, sans fond — la sélection reste visible derrière) en
  permanence à la ligne du résultat, à la place de la fenêtre de
  surimpression. Un clic sur le texte l'écarte. Bright/Gray/Subtle
  conservent la surimpression complète, inchangée.
- Plus l'audit export/Sonar complet : `--fail-on` ne masque plus les
  erreurs de lecture, `--custom-rules` se déclenche vraiment,
  rafraîchir une référence ne la détruit plus, les exports JSON ont
  perdu leur BOM, et le ZIP de release livre `rules/sca-rules.json` —
  l'export Sonar est valide tel que livré.

---

# Précédemment — Release 0.9.14 — Un mode sombre gris, et une remise à l'IDE plus sûre

🇬🇧 [English version](RELEASE_NOTES.md) · 🇩🇪 [Deutsche Fassung](RELEASE_NOTES_de.md)

Notes de version complètes : [docs/releases/v0.9.14.md](docs/releases/v0.9.14.md)
([deutsch](docs/releases/v0.9.14_de.md)).

Une petite version de suivi de 0.9.13, guidée par ce que celle-ci avait
raté.

- **Le mode sombre est enfin gris.** Deux causes : la palette était un
  cran trop sombre (`#181818` se lit comme du noir), et — la vraie — le
  fond ne venait pas du tout de la table des couleurs. Sous un style
  VCL actif, le fond de la fiche est peint à partir des *bitmaps* du
  style, et ceux-ci portent 109 171 pixels `#000000` opaques dans le
  Windows10 Dark d'origine ; les panneaux au-dessus gardent le
  `ParentBackground` par défaut et le laissent passer. Le générateur de
  styles relève désormais chacun de ces pixels vers le ton du chrome.
- **Ouvrir un résultat ne tape plus dans votre code.** La route IDE
  pressait Ctrl+G et tapait le numéro de ligne ; une IDE occupée avale
  le raccourci, et les chiffres atterrissaient comme texte à la ligne 1
  du fichier. Ce chemin ne fait plus qu'*ouvrir* le fichier —
  instantanément, et sans revendiquer une ligne qu'il n'a pas atteinte.
  Les sauts de ligne restent là où ils fonctionnent : éditeur externe
  (`%line%`), la visionneuse `.dfm` et le plugin IDE.
- **« Apply quick fix » a quitté le menu contextuel de la grille** ;
  l'action reste sur <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>F</kbd>.

---

# Précédemment — Release 0.9.13 — La référence trouve son foyer

🇬🇧 [English version](RELEASE_NOTES.md) · 🇩🇪 [Deutsche Fassung](RELEASE_NOTES_de.md)

Notes de version complètes : [docs/releases/v0.9.13.md](docs/releases/v0.9.13.md)
([deutsch](docs/releases/v0.9.13_de.md)).

Une grande version : les références, une nouvelle règle, et l'EXE
autonome qui rattrape son retard.

- **Les références vivent désormais dans un dossier `.sca`** à côté du
  projet ou du groupe, résolu à l'identique par la CLI, l'EXE et le
  plugin ; `--baseline-scan y` échoue durement (exit 99) en CI quand
  aucune référence n'existe. La bascule « uniquement les nouveaux »
  siège dans les deux menus hamburger et propose d'écrire sur-le-champ
  une référence manquante. L'option opt-in
  `[Baseline] PathInFingerprint=1` distingue les fichiers homonymes.
- **Nouvelle règle SCA196 `ManagedResultUninit`** : `Result` lu avant
  la première écriture pour les types de retour managés — le piège du
  var-paramètre caché dont W1035 ne prévient jamais. 49/49 résultats du
  corpus vérifiés comme de vrais bugs.
- **`SCA040`/`SCA042` étaient morts en production** (ils tournaient
  avant la construction des liaisons d'événements) — ressuscités et
  durcis sur le corpus ; avec, en parallèle, une vague de corrections
  de faux positifs des détecteurs (masquage des littéraux dans
  16 détecteurs, faux essaim DataModule, mauvaise attribution des
  boucles, `SCA101` voit enfin les branches en ligne suivante).
- **L'EXE rattrape le plugin** : triage au clavier avec un éditeur de
  fichiers fidèle à l'octet, filtres par tuiles, tri honnête,
  persistance des fenêtres, prise en charge d'un éditeur externe,
  diagnostics de plantage.
- **Le mode sombre est désormais « SCA VSDark »** — la palette VS Code
  Dark Modern au lieu du Windows10 Dark noir de jais.

---

# Précédemment — Release 0.9.12 — Le panneau suit le rythme

🇬🇧 [English version](RELEASE_NOTES.md) · 🇩🇪 [Deutsche Fassung](RELEASE_NOTES_de.md)

Notes de version complètes : [docs/releases/v0.9.12.md](docs/releases/v0.9.12.md)
([deutsch](docs/releases/v0.9.12_de.md)).

Une petite version, un jour après 0.9.11.

- **Le panneau d'analyse de fichier suit désormais la souris** : la
  molette et le clic naviguent dans l'éditeur avec un délai de
  stabilisation de 50 ms — avant, la molette déplaçait la sélection et
  l'éditeur ne suivait pas du tout. La liste elle-même a cessé d'être
  poussive (un appel COM par cellule dessinée, désormais mis en cache).
- **`SCA054` signale de nouveau les routines d'une seule ligne** — la
  vérification de source de v0.9.11 comptait la signature comme un
  usage quand elle partageait sa ligne avec `begin`. Les références
  peuvent regagner quelques résultats ; ils sont réels.
- **`WatchMode` ne peut plus empiler les workers**, et sélectionner un
  résultat n'écrit plus dans le presse-papiers trente fois par seconde.
- **`package-release.ps1`** balaie les zips périmés et son garde-fou de
  tag se déclenche vraiment désormais.

---

# Précédemment — Release 0.9.11 — Réparations

🇬🇧 [English version](RELEASE_NOTES.md) · 🇩🇪 [Deutsche Fassung](RELEASE_NOTES_de.md)

Notes de version complètes : [docs/releases/v0.9.11.md](docs/releases/v0.9.11.md)
([deutsch](docs/releases/v0.9.11_de.md)).

Une version de corrections, un jour après 0.9.10. Pas de nouvelles
règles, pas de nouvelles fonctions. Tout ici est un faux positif prouvé
sur le corpus de référence, une régression glissée avec 0.9.10, ou un
numéro de version qui avait discrètement cessé d'être vrai.

- **Le défilement dans le plugin IDE est de nouveau rapide.** Trois
  causes : le crochet de gouttière ajouté en 0.9.10 interroge *chaque*
  ligne alors que la zone de code sort tôt pour les lignes non
  marquées ; les lignes de continuation sont désormais des marqueurs,
  un bloc de 21 lignes transforme donc une ligne marquée en
  vingt-et-une ; et chaque événement de défilement forçait un repeint
  complet en plus de celui que l'éditeur effectue déjà — désormais
  regroupés par un timer de stabilisation de 90 ms.
- **Chaque cellule de la grille des résultats était peinte deux fois**
  — le moteur de rendu dessine tout lui-même, mais `DefaultDrawing`
  n'avait jamais été désactivé.
- **`SCA028` ne signale plus deux sortes de non-résultats** : un
  événement explicitement vidé avec `nil`, et un gestionnaire qui ne
  *semble* manquer que parce que le nom de la classe ancêtre existe
  dans deux unités (skia4delphi porte `TfrmBase` à la fois dans son
  arbre d'exemples VCL et dans le FMX).
- **`SCA054` interroge la source avant d'affirmer qu'un paramètre n'est
  jamais lu.** Le texte AST contre lequel il comptait est une
  approximation avec pertes — une expression d'index à gauche d'une
  affectation et des arguments derrière un transtypage `as` n'y
  apparaissent jamais.
- **`SCA099 IfElseBegin` rejoint le profil `style`**, où les six autres
  règles de convention se trouvaient déjà.
- **Le plugin IDE ne s'annonce plus comme v0.9.8.**

---

# Précédemment — Release 0.9.10 — Un résultat par bloc, un profil par défaut plus silencieux

🇬🇧 [English version](RELEASE_NOTES.md) · 🇩🇪 [Deutsche Fassung](RELEASE_NOTES_de.md)

Notes de version complètes : [docs/releases/v0.9.10.md](docs/releases/v0.9.10.md)
([deutsch](docs/releases/v0.9.10_de.md)).

Une petite version, taguée le même jour que 0.9.9. **Aucune règle n'a
gagné ni perdu de résultat** — le corpus de référence reste exactement
à **560 964** sur l'ensemble des **141** règles qui se déclenchent,
vérifié règle par règle plutôt que sur le total. Ce qui a changé, c'est
*comment* les résultats sont rapportés.

- **`SCA021` nomme la vraie plage de lignes** (`lines 513-533, 8 matched
  lines`). Le message fait partie de l'empreinte SARIF, chaque résultat
  `SCA021` paraît donc nouveau face à une référence existante —
  **réécrivez votre référence**. C'est aussi pourquoi c'est une
  nouvelle version et non une republication de 0.9.9.
- **Le profil `default` est plus silencieux.** Six règles de pure
  convention — 45,4 % de tous les résultats du corpus, tous corrects —
  ont déménagé vers un nouveau profil `style`. `strict` signifie
  toujours tout.
- **L'IDE dessine le crochet de plage dans la gouttière**, et il est
  désormais visible : le chapeau croissait vers la droite depuis une
  barre de deux pixels alignée à droite, il atterrissait donc sur
  lui-même et sept pixels hors de la gouttière.
- **Un marqueur de suppression dans la plage d'un résultat compte**, à
  la fois comme correspondance et comme consommé — l'étape de migration
  exigée par 0.9.9 disparaît.
- **`--parallel` dit quand il a décliné** au lieu de passer en série
  sans un mot.
- **Deux chiffres publiés dans les notes de 0.9.9 étaient faux** et
  sont corrigés : le palier des erreurs est **2 134**, pas 2 172, et le
  parc de règles a crû de **166 → 195**, pas de 183 → 195.

---

# Précédemment — Release 0.9.9 — Moins de faux positifs, deux règles à portée projet

🇬🇧 [English version](RELEASE_NOTES.md) · 🇩🇪 [Deutsche Fassung](RELEASE_NOTES_de.md)

Notes de version complètes : [docs/releases/v0.9.9.md](docs/releases/v0.9.9.md)
([deutsch](docs/releases/v0.9.9_de.md)).

Ce cycle, l'outil a appris à rapporter **moins**. Sur le corpus de
référence de 12 800 fichiers, le nombre de résultats est tombé de
**645 622 à 560 964 — 84 658 de moins (−13,1 %)**, sans perdre
sciemment un seul vrai positif. Le parc de règles est passé de 166 à
**195 règles**.

- **−84 658 résultats**, en sept incréments mesurés et verrouillés
  séparément.
- **`SCA194` / `SCA195`** — les fichiers qui ne font pas partie du
  projet, et les unités que le projet compile sans les référencer. Les
  deux exigent une vue à l'échelle du projet, ils ne s'exécutent donc
  que dans une analyse de projet ou de groupe de projets.
- **Les pages de règles disent désormais ce qu'une règle ne signale
  délibérément *pas*.**
- **`SCA080` ne signale plus `Break`** — suivre ce conseil transformait
  des boucles de recherche en balayages complets et des boucles
  `while True` en boucles infinies.
- **La CLI annonce à chaque exécution son jeu de règles actif**, y
  compris l'origine du profil. Elle se taisait quand le profil venait
  d'`analyser.ini`, et un `ide-fast` inattendu à cet endroit ressemble
  exactement à un build cassé.

Il n'existe **aucune version 0.9.4** — elle a été sautée. v0.9.5 à
v0.9.7 étaient sorties sans notes de version ; le CHANGELOG les couvre
désormais.

---

# Précédemment — Release 0.9.8

## Mise à jour 2026-06-08 / 2026-06-09 — Hardening v3/v4 + réduction des FP

- **Format DFM Resource-Wrapper (`$FF $0A $00`) pris en charge** — les
  83 DFM de GExperts sont passés de 0 à 1 084 résultats. La couverture
  DFM de la JVCL a environ doublé.
- **Bug de réentrance du `Destroy` de l'AST** corrigé —
  `EInvalidPointer`/SARIF SCA006 sur `gAstFileCache.Evict` après le
  premier fichier d'une analyse éliminé.
- **Cache de mémoïsation `uFixHint`** — corrige l'`EOutOfMemory` Win32
  dans `HighlightAllFindingsInFile` du plugin IDE sur les grandes
  analyses (≥100k résultats).
- **scan.log : suivi de phase + journal des sauts** — chaque résultat
  `Analyseabbruch:` révèle désormais la dernière phase réussie + le
  fichier courant ; les fichiers ignorés / exclus apparaissent avec une
  raison au lieu de disparaître en silence.
- **Sprint de réduction des FP** — les FP d'auto-analyse dans
  `SCA017 DebugOutput`, `SCA070 CommentedOutCode`, `SCA019 TodoComment`
  et `SCA005 FormatMismatch` réduits d'environ 80 % (67 → 12 sur les
  trois détecteurs de style). Correction annexe :
  `FreeAndNil(Self.Field)` avec le qualificateur `Self.` est désormais
  reconnu comme une libération.
- **Configuration** — `[Detectors] MaxLineLength` et `MaxCaseBranches`
  ajoutées.

## Plus tôt dans le cycle 0.9.8

13 commits depuis v0.9.7. La phase 1 de
`Konzept_ScannerQualitaet.md` est complète
(6/6 quick-wins) ; la phase 4 a commencé avec la vérification minimale
A.3 de visibilité inter-unités. Une revue multi-personas (architecture
+ sécurité + performance) a durci le code au passage.

## Points forts

- **Rapport Markdown `--time-detectors`** — temps horloge cumulé +
  nombre d'appels par détecteur.
- **Détection automatique des fixtures de test** — les résultats issus
  de `uTest*.pas` / `*Sample.pas` / `*Demo.pas` / des répertoires
  test/samples/demos/resources sont filtrés dans les profils `default`
  et `selftest-quiet`. Ancrée à la racine du dépôt contre les attaques
  par abandon silencieux.
- **SCA165 `UnusedSuppression`** — les marqueurs `// noinspection X`
  qui n'ont jamais supprimé de résultat sont eux-mêmes signalés.
- **Suite de régression FP sur corpus doré** — 5 reproducteurs de FP
  historiques, exécuteur PowerShell, code de sortie prêt pour la CI.
- **SARIF + référence `contextHash/v1`** — SHA256 sur un extrait de
  ±3 lignes normalisé en espaces. Les références survivent aux petits
  refactorings. Rétrocompatible avec les anciennes références.
- **Audit de confiance (35 kinds → `fcMedium`)** — les kinds
  heuristiques / métriques / de style / de schéma DFM / de sécurité
  sans flux de données étiquetés. Justifications par kind à côté des
  valeurs dans `KindDefaultConfidence`,
  [`SCA.Engine/sources/Common/uSCAConsts.pas`](SCA.Engine/sources/Common/uSCAConsts.pas).
- **A.3-Minimal : SCA052 inter-unités réactivé** — `gSymbolRefIndex`
  est désormais consulté pour `fkUnusedPublicMember`. Un sondage montre
  44 % des méthodes inter-unités correctement reconnues ; la suite pour
  les 56 % restants est documentée dans
  `Konzept_ScannerQualitaet.md §A.3+`.

## Durcissement sécurité (revue multi-personas)

- **`// noinspection All`** exclut les kinds critiques pour la sécurité
  (`fkHardcodedSecret`, `fkSQLInjection`, `fkCommandInjection`,
  `fkDfmHardcodedDbCreds`, `fkDfmSqlFromUserInput`,
  `fkInsecureCryptoAlgorithm`, `fkUnusedSuppression`). Le contournement
  par marqueur unique est neutralisé.
- **`ParseMarkerLine`** utilise `TDetectorUtils.ScanCodeLine` —
  conscient du contexte chaîne / commentaire de bloc. Les marqueurs à
  l'intérieur de littéraux de chaîne ne sont plus traités comme actifs.
- **Le JSON de référence** est durci avec `MAX_BASELINE_ENTRIES =
  1_000_000` et `MAX_FINGERPRINT_LEN = 256` contre les attaques OOM.

## Performance

- **`gFileTextCache` survit à la phase post-analyse** — la suppression,
  le `contextHash` et la sortie SARIF/référence réutilisent le cache
  chaud au lieu de relire chaque fichier. Élimine ~191k
  `LoadFromFile` + validations UTF-8 redondants par analyse réelle.
- **`TFileTextCache` connaît le mtime** — les entrées périmées
  s'invalident d'elles-mêmes.
- **`uVisibilityCheck`** met en cache `AllUnitMethods` + mémoïse
  `DescendantsOf` par unité au lieu de par membre public.

## Migration

Aucun changement incompatible. Les références existantes fonctionnent
telles quelles (appariées via l'empreinte héritée) ; les nouvelles
références portent en plus `contextHash`. Les auteurs de détecteurs qui
posent `F.Confidence := xxx` après `SetKind` devraient migrer vers le
nouvel overload `SetKind(K, AConfidence)` — l'ancien motif fonctionne
toujours.

## Journal des commits

```
1e7e193  fix(cache):       mtime-aware cache-invalidation
2b723f7  fix(build):       IsTestFixturePath impl signature
120894a  fix(review):      9 review findings (Sec + Perf + API)
e18323d  refactor:         Clean-code fixes (DRY, SRP, naming)
3054630  fix(visibility):  A.3 OwnUnit path + roadmap update
0ab0bf4  feat(visibility): A.3-Minimal — gSymbolRefIndex for SCA052
a8c7c35  feat(confidence): A.1 audit — ~35 kinds as fcMedium
91ae2ec  feat(baseline):   C.2 SARIF contextHash + baseline match
7b957a8  test(corpus):     C.1 Golden-corpus + runner
c0234d7  feat(suppression):C.3 Unused-suppression tracking (SCA165)
57a0b06  feat(filter):     A.2 Test-fixture auto-detection
1b5a145  fix(perf):        gDetectorTimings in interface section
79b4f56  feat(cli):        --time-detectors flag
```

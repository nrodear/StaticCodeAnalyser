# Sortir les résultats de SCA — formats et workflows

🇬🇧 [English version](EXPORTS.md) · 🇩🇪 [Deutsche Fassung](EXPORTS_de.md)

Cette page répond à une seule question : **« L'analyseur a tourné —
comment amener les résultats là où j'en ai besoin ? »** Elle décrit
chaque export que l'outil sait produire, lequel des trois frontaux peut
le produire, et les six workflows que les équipes pratiquent réellement.

Tout ce qui suit a été vérifié contre le binaire compilé v0.9.14. Là où
un chemin est aujourd'hui cassé, c'est indiqué — contournement compris.

---

## La première chose à savoir

`analyser.exe` est **un seul binaire à deux modes**. Lancé sans
arguments, il démarre l'interface graphique ; dès que le premier
argument commence par `-`, il bascule en CLI sans interface. « GUI
uniquement » ne signifie donc jamais « programme différent », mais
*inaccessible depuis un script*.

---

## Matrice des formats

| Format | Option CLI | Menu GUI / plugin | Utile pour |
|---|---|---|---|
| **SARIF 2.1.0** | `--report-sarif <fichier>` | ✅ *SARIF (all findings)* | code scanning GitHub / Azure, archivage, échange entre outils |
| **Sonar Generic Issue** | `--sonar-export <fichier>` | ✅ *Sonar: write Generic Issue report* | tableau de bord SonarQube (voir la réserve plus bas) |
| **Rapport HTML** | `--report-html <fichier>` | ✅ | lire et partager des résultats sans aucun outillage |
| **JSON de référence** | `--write-baseline <fichier>` | ✅ *Write baseline* | gate CI : « n'échouer que sur les **nouveaux** résultats » |
| **CSV** | `--report-csv <fichier>` | ✅ | Excel, tableaux croisés, comptages ad hoc |
| **JSON** | `--report-json <fichier>` | ✅ | scripts maison, automatisation de tickets |
| **Markup wiki Jira** | — | ✅ | coller un résultat dans un ticket |
| **Prompt IA (presse-papiers)** | — | ✅ | confier un résultat isolé à un assistant, avec son contexte de code |
| **Télémétrie de suppression** | `--telemetry-csv <fichier>` | — | quelles règles sont le plus souvent supprimées (classement du bruit) |
| **Durées des détecteurs** | `--time-detectors` (stdout) / `--time-detectors-out <fichier>` | — | repérer les détecteurs lents |

Deux asymétries méritent d'être connues avant de planifier quoi que ce
soit :

- **CSV et JSON exportent la vue filtrée de la CLI.** Comme les autres
  exports CLI, ils contiennent ce qui a survécu aux filtres de fixtures
  de test et de référence ; les entrées « all findings » du menu GUI ne
  filtrent pas.
- **La portée dépend du frontal.** Depuis la CLI, les exports
  contiennent les résultats *après* filtrage par fixtures de test et
  référence. Depuis le menu GUI, les entrées « all findings » exportent
  la liste **non filtrée**, quel que soit l'affichage de la grille. Les
  libellés du menu disent ce qui s'applique — lisez-les.

**Encodage.** Tous les formats JSON (SARIF, Sonar, `--report-json`,
référence) sont écrits en **UTF-8 sans BOM** — la RFC 8259 §8.1
interdit la marque d'ordre des octets pour l'échange JSON, et
`JSON.parse` sous Node s'y étrangle, or c'est justement ce qu'utilise
l'action `upload-sarif` de GitHub. Le CSV est l'exception délibérée et
garde son BOM, car c'est ainsi qu'Excel reconnaît l'UTF-8.

Jusqu'à la **v0.9.14** incluse, les exports JSON portaient un BOM ; sur
ce build, retirez-le ou lisez avec `utf-8-sig`.

---

## Workflow 1 — Gate CI : faire échouer le build sur les nouveaux résultats

La référence est le mécanisme : elle consigne les résultats
d'aujourd'hui pour que le build de demain ne se plaigne que de ce qui a
été ajouté.

```bash
# une seule fois, pour consigner l'état actuel
analyser.exe --path . --write-baseline .sca/sca.baseline.json

# à chaque build
analyser.exe --path . --baseline .sca/sca.baseline.json --report-sarif build/sca.sarif
```

Les codes de sortie sont gradués : `0` propre, non nul quand des
résultats subsistent après le filtre de référence.
`--fail-on error|warning|hint|none` restreint ce qui compte. Les
erreurs de lecture maintiennent une exécution non nulle dans tous les
modes sauf `none` : là où la politique renverrait sinon 0, l'exécution
sort avec 4 — un scan incomplet ne doit jamais ressembler à un scan
propre. Les erreurs d'outil (99) sont décidées avant même la
consultation de `--fail-on` et ne peuvent pas du tout être abaissées.

**Utilisez un chemin absolu ou un chemin avec une partie répertoire
pour `--write-baseline`.** Un simple nom de fichier
(`--write-baseline b.json`) échoue avec *« Baseline write error:
Verzeichnis kann nicht erstellt werden »* — vérifié sur v0.9.14.

**En CI, préférez `--baseline-scan y` au nom de fichier explicite.**
L'option résout la référence en trois étapes — `--baseline`, puis
`[Baseline] File=` dans `analyser.ini`, puis le dossier `.sca` à côté
de `--project` / `--project-group` (ou `<chemin>\.sca\sca.baseline.json`)
— et indique laquelle elle a retenue. Le point essentiel est le
comportement en cas d'échec : si vous demandez une référence et
qu'aucune n'est trouvée, l'exécution **s'interrompt avec le code 99**
et liste tous les chemins essayés, au lieu de signaler en silence tout
l'arriéré comme nouveau. Cette variante silencieuse est la voie
classique par laquelle un pipeline vert cesse de vouloir dire quelque
chose. `--write-baseline auto` écrit au même emplacement `.sca`, la
paire se passe donc de chemins codés en dur :

```bash
analyser.exe --path . --write-baseline auto        # une seule fois
analyser.exe --path . --baseline-scan y            # à chaque build
```

`--baseline-scan n` est le contraire explicite : tourner sans référence
même si un fichier traîne quelque part. Toute autre valeur est rejetée
d'emblée.

**Si le même nom d'unité existe dans plusieurs dossiers, ajoutez
`--baseline-path-fingerprint y`.** Par défaut, une empreinte identifie
un résultat par le *nom de fichier*, pas par le chemin : deux
`uSame.pas` dans des dossiers différents partagent donc une même
identité. Conséquence mesurée : une référence écrite depuis un
sous-dossier a masqué en silence **tous** les résultats d'un dossier
voisin — dont une injection SQL que personne n'avait jamais examinée ;
avec l'option, la même exécution les conserve. Elle change les
empreintes : écrivez donc une référence fraîche en l'activant.

Un résidu subsiste à dessein : un résultat dont les lignes environnantes
sont identiques dans les deux fichiers correspond toujours via l'étape
`contextHash`. C'est ce qui permet à une référence de survivre aux
déplacements et aux refactorings, et c'est la raison pour laquelle deux
copies identiques à l'octet près restent liées, quoi que dise cette
option.

**Ne rafraîchissez pas une référence en combinant les deux options.**
Le `--baseline ancienne --write-baseline nouvelle` d'apparence
documentée n'écrit que les résultats qui ont *survécu* au filtre —
c'est-à-dire les nouveaux. Mesuré sur un dépôt réel : une référence de
226 entrées est devenue **0 entrée**, et le build suivant a signalé de
nouveau tout l'arriéré. Pour rafraîchir, écrivez une référence fraîche
à partir d'une exécution propre sans `--baseline`.

## Workflow 2 — Revue de pull request : seulement ce qui a changé

```bash
analyser.exe --path . --diff main...HEAD --report-html build/review.html
```

`--branch` utilise l'ensemble des fichiers modifiés selon le
gestionnaire de versions (Git et SVN détectés automatiquement),
`--diff <plage>` une plage Git, y compris la forme `a...b` de
l'ancêtre commun. Les deux incluent les modifications non validées. Le
rapport HTML est autonome — aucune ressource externe, il s'ouvre depuis
un partage de fichiers ou un artefact CI.

## Workflow 3 — Tableau de bord SonarQube

SCA ne pousse **pas** vers SonarQube, et c'est le bon choix : Sonar n'a
pas d'API publique d'ingestion pour les issues externes. SCA écrit le
fichier, et `sonar-scanner` l'achemine.

```bash
analyser.exe --path . --base-dir . --sonar-export sca-findings.json
sonar-scanner -Dsonar.externalIssuesReportPaths=sca-findings.json
```

> **⚠️ Cassé dans le ZIP livré — à lire avant d'essayer.** L'archive de
> release ne contient que l'EXE. Sans `rules/sca-rules.json` à côté, le
> catalogue de règles retombe sur un substitut intégré qui émet `type`
> au lieu de `cleanCodeAttribute` + `impacts`, et **SonarQube rejette
> le rapport entier** (vérifié contre les vrais validateurs du
> scanner-engine : 10.7 signale *missing mandatory field
> 'cleanCodeAttribute'*, 2025.x *missing mandatory field 'severity'*).
> L'exécution a l'air réussie et le fichier est écrit — seul le tableau
> de bord reste vide.
>
> **Contournement :** copier le dossier `rules/` du dépôt à côté de
> l'EXE. Avec le catalogue présent, l'export est validé sur toutes les
> générations de moteur testées. Un `rules/sca-rules.json` corrompu
> dégrade de la même manière, tout aussi silencieusement.

Les chemins du rapport sont relatifs à `--base-dir` (défaut :
`--path`) ; lancez donc l'export avec la même racine que celle
qu'utilise le scanner. Les fichiers hors de cette racine retombent sur
des chemins absolus, que Sonar écarte en silence comme « unknown
files ».

**Les erreurs de lecture ne figurent pas dans le rapport Sonar.** Un
fichier que l'analyseur n'a pas pu lire renseigne sur la complétude de
l'exécution, pas sur le source — comme issue de tableau de bord, ce
n'était que du bruit sur lequel personne ne pouvait agir. Elles restent
visibles partout où elles ont leur place : le résumé console, le code
de sortie 4, le rapport HTML et le SARIF, qui les liste à la fois comme
`result` et sous `runs[].invocations[].toolExecutionNotifications`. Une
exécution qui n'a produit *que* des erreurs de lecture exporte donc
`{"rules":[],"issues":[]}` — valide, et Sonar l'accepte. Consultez la
ligne console, pas le tableau de bord, pour savoir si un scan était
complet.

## Workflow 4 — Code scanning GitHub / Azure

```bash
analyser.exe --path . --base-dir . --report-sarif sca.sarif
```

Le SARIF porte des `partialFingerprints` (hachage de ligne +
contextHash) : les alertes gardent leur identité malgré la dérive des
lignes. Les chemins sont relatifs à `--base-dir` — pointez-le sur la
racine du dépôt, c'est ce que le code scanning attend.

Deux points à surveiller : le BOM UTF-8 peut faire trébucher les
uploaders basés sur Node, et téléverser un SARIF **filtré par la
référence** contrarie le cycle de vie des alertes de la plateforme
(elle résout tout ce que le filtre a retiré). Pour le code scanning,
téléversez le rapport non filtré et laissez la plateforme suivre
l'état.

## Workflow 5 — Le développeur à son poste

Utilisez la GUI ou le plugin IDE : lancer l'analyse, filtrer avec les
tuiles de statistiques, cliquer sur un résultat, lire l'aide
avant/après. `Ctrl+Alt+S` insère un marqueur de suppression,
`Ctrl+Alt+F` applique un Quick-Fix. Les résultats s'ouvrent dans
l'éditeur de votre choix via `[Editor]` dans `analyser.ini` (VS Code,
Notepad++, Sublime, …) — cette voie saute à la ligne exacte. L'IDE
Delphi n'ouvre que le fichier ; il n'offre pas d'option de ligne depuis
l'extérieur.

Pour le partage, `--report-html` est le format qui n'exige aucun
outillage en face.

> **Note sur le partage :** le rapport HTML intègre des extraits de
> source. Traitez-le comme du code source quand vous l'envoyez quelque
> part.

## Workflow 6 — Suivi dans le temps

Il n'existe pas de stockage de tendances intégré. Deux voies
praticables : archiver le SARIF à chaque build et compter avec `jq`, ou
laisser SonarQube tenir l'historique via le workflow 3. Les comptes par
règle du résumé console sont assez stables pour être tracés si vous les
capturez.

---

## Limitations connues

Liste honnête, état v0.9.14 — tout a été reproduit :

| Domaine | Comportement |
|---|---|
| Export Sonar depuis le ZIP de release | rejeté par SonarQube ; livrer `rules/` à côté de l'EXE |
| Rafraîchir la référence avec les deux options | tronque la référence aux seuls nouveaux résultats |
| `--write-baseline` avec un simple nom de fichier | n'écrit pas |
| Exports JSON | UTF-8 **avec** BOM — corrigé après v0.9.14, désormais sans BOM |
| Rapport HTML | ne stocke que les noms de fichiers de base ; des unités homonymes dans des dossiers différents entrent en collision |
| Empreintes de référence | les unités homonymes de dossiers différents partagent par défaut un même espace de noms — désactivable avec `--baseline-path-fingerprint y` (voir ci-dessous) |
| Fichiers source illisibles | comptés différemment dans la console, SARIF/Sonar/HTML et la référence |
| `--parallel` | déterministe depuis le 2026-08-20 (identique octet pour octet aux exécutions sérielles), mais sans gain de vitesse - la phase préalable sérielle domine |
| `--sonar-insecure` | n'accepte pas les certificats auto-signés (il n'active que TLS 1.1) |
| `--sonar-test` dans un dépôt étranger | un `sonar-project.properties` dans le dépôt scanné remplace votre hôte — votre jeton part là-bas |

---

## Quel format pour quelle tâche

- **Un gate qui bloque les mauvais merges** → référence + code de
  sortie, archiver le SARIF comme preuve.
- **Un tableau de bord que l'équipe regarde** → export Sonar plus le
  scanner (avec `rules/` à côté de l'EXE).
- **Une personne qui doit le lire** → rapport HTML.
- **Votre propre outillage** → SARIF ; c'est le plus riche et le seul
  avec des empreintes, tout le reste peut en être dérivé.

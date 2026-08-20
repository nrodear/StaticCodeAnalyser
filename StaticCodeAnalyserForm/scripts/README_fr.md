# Scripts de push Sonar

🇬🇧 [English version](README.md) · 🇩🇪 [Deutsche Fassung](README_de.md)

Deux scripts d'assistance PowerShell autour de l'exécutable autonome +
`sonar-scanner`. Séparer le scan de l'upload permet de relancer l'upload
sans re-scanner, garde le scan utilisable hors ligne (CI) et facilite
l'inspection du JSON entre les deux étapes.

**Testé avec** : SonarQube Community Build 26.5+ (Sonar 10+, mode MQR).
Les résultats SCA sont importés comme external issues via le Generic
Issue Format et coexistent avec le profil qualité par défaut de Sonar,
**Sonar Way** — aucun conflit, aucun écrasement. Fonctionne aussi bien
avec SonarQube Server qu'avec SonarCloud.

| Script | Ce qu'il fait |
|---|---|
| [`sonar-scan.ps1`](sonar-scan.ps1)     | Exécute `analyser.exe --sonar-export` et produit `sca-findings.json`. Déploie le catalogue de règles vers `%APPDATA%` au premier lancement, décode le code de sortie en un verdict lisible, valide le fichier de sortie. |
| [`sonar-upload.ps1`](sonar-upload.ps1) | Déchiffre le jeton DPAPI depuis `analyser.ini`, lit hôte/projet dans `[Sonar]`, lance `sonar-scanner` avec les bons drapeaux `-D`. Prend en charge `-DryRun` et `-DisableDelphi`. |

---

## Prérequis (une seule fois)

1. **Compiler l'EXE Release** — ouvrir
   `StaticCodeAnalyserForm/StaticCodeAnalyser.d12.dproj` dans Delphi 12,
   passer sur `Win32/Release`, **Build**.
2. **Installer sonar-scanner** — voir
   [`../../sonarHowto_fr.md`](../../sonarHowto_fr.md) section 0.1, ou
   téléchargement direct depuis
   <https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/scanners/sonarscanner/>.
   Placer `sonar-scanner.bat` soit dans le `PATH` **soit** sous
   `D:\git-demos\sonar-scanner-8.0.1\bin\` (les scripts détectent
   automatiquement les deux emplacements).
3. **Amorcer `analyser.ini`** avec les identifiants Sonar (une seule
   fois ; chiffre le jeton via DPAPI) :
   ```powershell
   $exe = "..\Win32\Release\StaticCodeAnalyser.d12.exe"
   & $exe --sonar-host    "http://sonar.company.com:9000" `
          --sonar-project "my-delphi-project" `
          --sonar-token   "squ_xxxxxxxxxx" `
          --sonar-test
   ```
   Cela remplit `%APPDATA%\StaticCodeAnalyser\analyser.ini` avec la
   section `[Sonar]` plus `[SonarTokens]` (jeton chiffré par DPAPI —
   seul le même utilisateur Windows sur la même machine peut le lire).

---

## Déroulement typique

```powershell
cd D:\git-demos\delphi\StaticCodeAnalyser\StaticCodeAnalyserForm\scripts

# Scan + upload. ProjectPath par défaut = le dépôt de l'analyseur (auto-analyse).
.\sonar-scan.ps1
.\sonar-upload.ps1

# Exemple concret : scanner tout ce qui est sous D:\git-demos et pousser.
.\sonar-scan.ps1   -ProjectPath D:\git-demos\
.\sonar-upload.ps1 -ProjectPath D:\git-demos\ -DisableDelphi

# Scans mono-fichier ou limités à la branche
.\sonar-scan.ps1 -ProjectPath D:\myrepo -Branch -Quiet

# Vérifier la commande du scanner avant de pousser
.\sonar-upload.ps1 -ProjectPath D:\myrepo -DryRun
```

`Get-Help .\sonar-scan.ps1 -Detailed` / `Get-Help .\sonar-upload.ps1
-Detailed` affiche la documentation complète de chaque paramètre.

---

## Stratégie d'exécution PowerShell (Execution Policy)

Si ce message apparaît au lancement des scripts :

```
.\sonar-scan.ps1 ist nicht digital signiert. Sie können dieses Skript
im aktuellen System nicht ausführen.   ( UnauthorizedAccess )
```

votre stratégie d'exécution est `AllSigned` (ou `Restricted`). Trois
options, de la moins intrusive à la plus permanente :

| Mode | Commande | Effet |
|---|---|---|
| **Ponctuel** | `powershell -ExecutionPolicy Bypass -File .\sonar-scan.ps1 ...` | Aucun changement d'état. Idéal pour les lancements ad hoc et la machine CI sans droits. |
| **Par session** | `Set-ExecutionPolicy -Scope Process Bypass` puis lancer normalement | Vaut jusqu'à la fermeture du shell. |
| **Permanent pour votre utilisateur** | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` | Les scripts locaux non signés s'exécutent ; les scripts téléchargés exigent toujours une signature. Le défaut de Windows Server. **Recommandé.** |

Les scripts ne doivent **pas** être réenregistrés via la boîte de
dialogue de l'ISE PowerShell avec « Save as UTF-8 » si la stratégie est
`AllSigned` — cela ajoute un BOM qui invaliderait une éventuelle
signature ultérieure.

---

## Déploiement du catalogue (d'où viennent les métadonnées de règles)

`sonar-scan.ps1` appelle
`analyser.exe --sonar-export`, qui a besoin de `rules/sca-rules.json`
pour remplir les champs `cleanCodeAttribute` + `impacts` de chaque
règle. L'EXE remonte jusqu'à 8 niveaux de répertoires depuis son propre
emplacement à la recherche de `rules\sca-rules.json` ; s'il ne le trouve
pas, l'export fonctionne quand même mais part **sans** les champs MQR —
Sonar 10+ rejette alors le JSON avec
`either type, impacts or both should be provided`.

`sonar-scan.ps1` déploie le catalogue automatiquement au premier
lancement :

```
%APPDATA%\StaticCodeAnalyser\rules\sca-rules.json
```

C'est la **recherche de priorité 4** de l'exécutable autonome (le
répertoire `rules\` dans APPDATA est trouvé quel que soit l'endroit
d'où l'EXE est lancé). Relancer le script de scan après une
modification du catalogue pour synchroniser la copie. Déploiement
manuel :

```powershell
$dst = "$env:APPDATA\StaticCodeAnalyser\rules"
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item ..\..\rules\sca-rules.json "$dst\sca-rules.json" -Force
```

---

## `-DisableDelphi` — quand le serveur Sonar a un plugin Delphi installé

Si le serveur Sonar héberge le plugin **SonarDelphi** (IntegraDev, clé
[`delphi`](https://github.com/integrated-application-development/sonar-delphi))
ou son ancien fork communautaire (`communitydelphi`), l'upload peut
échouer sur `EXECUTION FAILURE` avec des centaines de lignes `WARN` du
genre :

```
WARN  Invalid DCC_UnitSearchPath directory: ..\..\..\src\core
WARN  File specified by DCCReference does not exist: ...
WARN  Could not resolve imported file: C:\Embarcadero\Studio\23.0\Bin\CodeGear.Delphi.Targets
INFO  Conditional defines: [..., VER350, ...]
INFO  EXECUTION FAILURE
```

Le plugin Delphi analyse chaque `.dproj` / `.dpk` du périmètre et
échoue quand le projet référence des cibles ou dépendances absentes de
la machine d'analyse (typique des dépôts tiers dans un espace de
travail partagé).

`-DisableDelphi` pose cinq drapeaux pour que le capteur Delphi ne
reçoive aucune entrée et se termine proprement :

```text
-Dsonar.delphi.file.suffixes=
-Dsonar.communitydelphi.file.suffixes=
-Dsonar.lang.patterns.delphi=
-Dsonar.lang.patterns.communitydelphi=
-Dsonar.exclusions=...,**/*.dproj,**/*.dpk,**/*.dpr,**/*.dpkw
```

Les external issues de SCA ne sont pas affectées — elles référencent
les fichiers `.pas` par chemin, et ces chemins restent dans le scan.
Seul le **mappage de langage** est vidé, si bien que le capteur Delphi
ne trouve rien à traiter.

Alternatives à long terme :
- Désinstaller le plugin Delphi dans l'interface web de Sonar →
  `Administration → Marketplace → Installed → uninstall`
- Restreindre le périmètre du scan à un seul dépôt Delphi dont les
  fichiers `.dproj` ont des chemins valides (alors `-DisableDelphi`
  devient inutile)

---

## Capture des flux pour le débogage

Quand le scanner échoue silencieusement avec `EXECUTION FAILURE` sans
ligne `ERROR` dans le journal, l'exception Java réelle est partie sur
**stderr**, que le `>` de PowerShell ne capture pas par défaut.
Utilisez `*>&1` plus `Tee-Object` pour une trace complète :

```powershell
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
powershell -ExecutionPolicy Bypass -File .\sonar-upload.ps1 `
  -ProjectPath D:\git-demos\ -DisableDelphi *>&1 |
  Tee-Object -FilePath ".\sonar-upload-$ts.log"
```

`*>&1` fusionne Error/Warning/Verbose/Output en un flux unique que
`Tee-Object` peut écrire dans le fichier. Les fichiers `.log` figurent
dans `.gitignore` pour ne pas polluer les commits.

---

## Dépannage

| Symptôme | Cause | Correctif |
|---|---|---|
| `... ist nicht digital signiert` | ExecutionPolicy = AllSigned/Restricted | Voir la section *Stratégie d'exécution* ci-dessus |
| `analyser.exe not found` | Win32/Release pas compilé | Compiler d'abord le `.dproj` ; le script se rabat sur Debug avec un avertissement |
| `analyser.ini not found at ...` | Identifiants Sonar jamais amorcés | Lancer une fois le `--sonar-test` des *Prérequis* (étape 3) |
| `DPAPI decrypt failed` | INI créé par un autre utilisateur Windows / sur une autre machine | Relancer une fois `analyser.exe --sonar-token <tok>` sur cette machine |
| `Findings JSON not found` | `sonar-scan.ps1` pas encore lancé, ou `-ProjectPath` différent | Lancer `sonar-scan.ps1` avec le même `-ProjectPath`, ou passer `-JsonPath` |
| `Failed to parse report: either type, impacts or both should be provided` | EXE périmé sans catalogue → métadonnées de règles de repli | Recompiler l'EXE Release ; copier le catalogue à la main vers APPDATA |
| `[FAIL] DNS resolution` | Hôte Sonar injoignable | Vérifier l'URL, pinguer l'hôte, VPN si distant |
| `[FAIL] Token validation: 401` | Jeton révoqué ou expiré | Générer un nouveau jeton dans l'interface web de Sonar, réamorcer analyser.ini |
| `[FAIL] Project access: 403` | Projet manquant / pas de permission Browse | Créer le projet dans Sonar ou accorder le droit Browse à votre utilisateur |
| `EXECUTION FAILURE` après plus de 500 lignes `WARN` sur `DCCReference` / `DCC_UnitSearchPath` | Le plugin Delphi s'étrangle sur des `.dproj` tiers | Ajouter le drapeau `-DisableDelphi` (voir la section ci-dessus) |
| Résultats absents de Sonar après un push réussi | Fichiers exclus ou `--base-dir` erroné → les chemins pointent hors de `sonar.sources` | Mettre `--base-dir` égal à `--path` ; revoir `sonar.exclusions` |

---

## Pourquoi séparer le scan de l'upload ?

- Les **pipelines CI** exécutent souvent le scan dans un job et
  l'upload dans un job ultérieur qui détient le jeton Sonar dans son
  environnement.
- Les **ré-uploads** après une panne réseau transitoire ne doivent pas
  re-scanner une arborescence inchangée.
- L'**inspection manuelle** du JSON (jq, diff contre un lancement
  précédent, ajout de métadonnées supplémentaires) est plus simple
  quand l'artefact vit entre les deux étapes.

---

## Voir aussi

- [`../../sonarHowto_fr.md`](../../sonarHowto_fr.md) (français) /
  [`../../sonarHowto_de.md`](../../sonarHowto_de.md) — guide complet
  pas à pas, y compris l'installation de sonar-scanner et la structure
  de l'INI.
- [`../../docs/sonar-config.md`](../../docs/sonar-config.md) — ordre du
  résolveur de configuration (CLI > Env > properties > INI).
- [`../../docs/sonar-setup.md`](../../docs/sonar-setup.md) — guide
  Sonar plus large incluant le workflow du plugin IDE.
- [Spécification Sonar Generic Issue Format](https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/importing-external-issues/generic-issue-import-format/)
- [SonarDelphi (fork IntegraDev)](https://github.com/integrated-application-development/sonar-delphi)

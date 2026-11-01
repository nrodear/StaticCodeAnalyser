# Guide rapide Sonar

🇬🇧 [English version](sonarHowto.md) · 🇩🇪 [Deutsche Fassung](sonarHowto_de.md)

SCA écrit ses résultats dans un fichier et n'envoie rien. `sonar-scanner` achemine ce fichier vers le serveur. Le serveur, le scanner, les jetons et les quality gates sont décrits dans la [documentation officielle de Sonar](#documentation-officielle).

## 1. Écrire le rapport

À lancer dans le dossier du projet :

```powershell
analyser.exe --path . --sonar-export sca.json --profile default
```

La GUI et l'IDE écrivent le même format avec *Export > Sonar: write Generic Issue report (all findings)...* : toujours l'analyse entière, quoi qu'affiche la grille. *Sonar: write selected as external issue* écrit un fichier par résultat sélectionné dans `.sonar\external\` ; définissez alors `sonar.externalIssuesReportPaths=.sonar/external/`.

## 2. Configurer le scanner

`sonar-project.properties` dans le même dossier :

```properties
sonar.projectKey=my-delphi-project
sonar.sources=.
sonar.externalIssuesReportPaths=sca.json
```

SARIF fonctionne aussi : écrivez-le avec `--report-sarif sca.sarif` et définissez `sonar.sarifReportPaths=sca.sarif`. N'utilisez qu'un seul des deux, Sonar ne les déduplique pas.

## 3. Lancer le scanner

```powershell
$env:SONAR_HOST_URL = "https://sonar.example.com"
$env:SONAR_TOKEN = "<votre jeton>"
sonar-scanner
```

`ANALYSIS SUCCESSFUL` ne prouve pas l'import. Cherchez dans le journal du scanner `Imported N issues in M files` et `External issues ignored for N unknown files`.

## Erreurs à éviter

- **Un projet Sonar par dépôt Git.** Un scan depuis un dossier parent embarque tous les sous-projets, et les fichiers des dépôts imbriqués n'ont pas de données de blame : chacune de leurs issues compte comme du nouveau code (`Missing blame information for N files`).
- **Rapport et scanner dans le même dossier.** Les chemins du rapport sont relatifs au dossier du projet (`--base-dir`, par défaut `--path`), et Sonar les résout depuis le dossier de `sonar-project.properties`. Sinon, il les écarte comme fichiers inconnus.
- **Fichiers écartés.** Les résultats dans des fichiers visés par `sonar.exclusions`, dans des fichiers gitignorés et dans un sous-dossier ayant son propre `.git` que le dépôt parent ne suit pas comme sous-module sont perdus, même si SCA les a analysés.
- **Même jeu de règles.** L'IDE utilise `[Rules] IdeProfile`, et `--profile default` masque les fixtures de test (`--show-test-fixtures` les garde). Un nom de profil inconnu ne donne aucune erreur, l'analyse s'exécute avec d'autres règles.
- **Rester sur une seule voie.** La GUI et la CLI écrivent des métadonnées de règle différentes. Changer de voie modifie les sévérités et les notes dans Sonar alors que le code n'a pas changé.
- **Code de sortie dans un pipeline.** Des résultats terminent l'analyse avec le code 1 à 3. Pour que l'étape du scanner s'exécute quand même, ajoutez `--fail-on none` ; les erreurs d'outil restent en code 99.
- **SonarDelphi.** Si le plugin arrête le scanner avec `Path to Delphi standardlibrary is invalid`, définissez `sonar.delphi.installationPath` et `sonar.delphi.compilerVersion`.

## Sévérité et impact

- **Sonar connaît la sévérité par règle, pas par résultat.** L'impact d'une règle suit le résultat le plus fort de l'analyse : si la politique de preuve les a tous plafonnés, la règle porte la sévérité plafonnée (Warning : au plus MEDIUM). Un seul résultat de pleine sévérité garde les impacts du catalogue. L'impact peut donc changer d'une analyse à l'autre, les issues restent. `[Rules] EvidenceTiering=0` garde les impacts du catalogue.
- **Les résultats abaissés avec `[PathOverrides]` sont exclus,** car ils arriveraient en pleine sévérité. `--sonar-keep-downgraded` les exporte (CLI uniquement). Décidez une fois pour toutes : ce qui quitte le rapport compte comme corrigé, ce qui y entre comme nouveau.
- **BLOCKER exige SonarQube 10.8 ou plus récent.** SCA026 le porte toujours, SCA004 avec un résultat prouvé. Sur 10.3 à 10.7, un tel rapport est invalide.

## Documentation officielle

- [SonarScanner CLI](https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/scanners/sonarscanner/) : installation, jeton, URL du serveur
- [Generic Issue Import Format](https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/importing-external-issues/generic-issue-import-format/)
- [Quality Gates](https://docs.sonarsource.com/sonarqube-server/latest/quality-standards-administration/managing-quality-gates/introduction-to-quality-gates/)

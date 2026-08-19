# HowTo Sonar (EXE autonome)

🇬🇧 [English version](sonarHowto.md) · 🇩🇪 [Deutsche Fassung](sonarHowto_de.md)

Guide pas à pas pour pousser les résultats SCA dans une instance SonarQube
avec l'**EXE autonome uniquement**. Aucun plugin IDE n'est nécessaire.

**Testé avec** : SonarQube Community Build 26.5+ (Sonar 10+, mode MQR).
Les résultats SCA sont importés comme external issues via le Generic Issue
Format et apparaissent à côté du profil de qualité par défaut **Sonar Way**
de Sonar — aucun conflit, aucun écrasement. Fonctionne aussi bien avec
SonarQube Server qu'avec SonarCloud.

> **Non couvert** : la mise en place du serveur SonarQube lui-même (Docker /
> création d'un projet / génération de jetons dans l'interface web).
> Prérequis : un serveur en marche, un compte utilisateur avec un jeton et
> un projet avec la permission Browse. S'il vous en manque encore, voir
> [docs/sonar-setup.md](docs/sonar-setup.md) (section « Troubleshooting »)
> et la documentation officielle de SonarQube.

---

## 0. Prérequis — mise en place unique

### 0.1 Installer sonar-scanner

Source officielle : https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/scanners/sonarscanner/

Téléchargements directs (Windows x64) :
https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/

**Installation rapide en PowerShell** :

```powershell
# Ajuster la version si nécessaire
$ver = "6.2.1.4610"
Invoke-WebRequest `
  "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-$ver-windows-x64.zip" `
  -OutFile "$env:TEMP\sonar-scanner.zip"
Expand-Archive "$env:TEMP\sonar-scanner.zip" -DestinationPath C:\Tools -Force
Rename-Item "C:\Tools\sonar-scanner-$ver-windows-x64" "C:\Tools\sonar-scanner"

# Ajouter au PATH utilisateur (persistant)
[Environment]::SetEnvironmentVariable("PATH",
  "$env:PATH;C:\Tools\sonar-scanner\bin", "User")
```

**Ouvrez une nouvelle fenêtre PowerShell** pour que le changement de PATH
prenne effet, puis vérifiez :

```powershell
sonar-scanner --version
```

La sortie doit ressembler à `INFO: SonarScanner CLI 6.2.1.4610`. Depuis la
version 5, le scanner embarque son propre JRE — aucune installation Java
séparée n'est requise.

### 0.2 Compiler l'EXE autonome

Ouvrir `StaticCodeAnalyserForm/StaticCodeAnalyser.d12.dproj` dans Delphi 12,
passer sur `Win32 / Release`, **Build**.

Résultat : `StaticCodeAnalyserForm\Win32\Release\StaticCodeAnalyser.d12.exe`.

### 0.3 Déployer le catalogue durablement (recommandé)

`rules\sca-rules.json` est la source de données des champs
`cleanCodeAttribute` et `impacts` par règle (mode MQR de Sonar). Par défaut,
l'EXE cherche le catalogue relativement à son propre emplacement. Si vous
comptez lancer plus tard des analyses depuis des répertoires de travail
quelconques, déposez une copie utilisateur pour que l'EXE le trouve
toujours :

```powershell
$dst = "$env:APPDATA\StaticCodeAnalyser\rules"
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item "D:\git-demos\delphi\StaticCodeAnalyser\rules\sca-rules.json" `
          "$dst\sca-rules.json" -Force
```

Après une mise à jour du catalogue dans le dépôt : recopier. (Voir
[docs/sonar-config.md](docs/sonar-config.md) pour l'ordre de recherche
complet.)

---

## 1. Configuration Sonar pour l'EXE autonome

Vous avez trois façons de fournir les paramètres de connexion à l'EXE —
choisissez-en une, sans les mélanger. Les options A et B se suffisent à
elles-mêmes ; l'option C exige que l'INI existe déjà (voir plus bas) — une
installation réellement sans plugin passe donc par A ou B.

### Option A — options CLI à chaque exécution

```powershell
analyser.exe --sonar-test `
  --sonar-host http://sonar.company.com:9000 `
  --sonar-token squ_xxxxxxxxxx `
  --sonar-project my-delphi-project
```

Rapide pour les tests / pipelines CI. Attention : le jeton finit dans
l'historique du shell.

### Option B — variables d'environnement

```powershell
$env:SONAR_HOST_URL    = "http://sonar.company.com:9000"
$env:SONAR_TOKEN       = "squ_xxxxxxxxxx"
$env:SONAR_PROJECT_KEY = "my-delphi-project"

analyser.exe --sonar-test
```

Recommandé pour la CI (les magasins de secrets fournissent les variables).

### Option C — analyser.ini avec jeton chiffré par DPAPI

L'EXE autonome **lit** `%APPDATA%\StaticCodeAnalyser\analyser.ini`, mais
n'y écrit jamais de jeton — aucune option CLI n'en enregistre un. Le
fichier doit d'abord être créé par autre chose :

- **Plugin IDE** — *Tools > Options > Static Code Analysis > Sonar*,
  saisir hôte / projet / jeton, Enregistrer. C'est le seul endroit du
  produit qui chiffre un jeton avec DPAPI. Pratique si le plugin est de
  toute façon installé ; cela signifie aussi que cette option n'est pas
  disponible sur une machine sans plugin.
- **À la main** — écrire soi-même la section `[Sonar]` et produire
  l'entrée `[SonarTokens]` avec PowerShell :

```powershell
$ini = "$env:APPDATA\StaticCodeAnalyser\analyser.ini"
Add-Type -AssemblyName System.Security
$enc = [System.Security.Cryptography.ProtectedData]::Protect(
  [Text.Encoding]::UTF8.GetBytes("squ_xxxxxxxxxx"), $null, "CurrentUser")
$hex = ($enc | ForEach-Object { $_.ToString("x2") }) -join ""
@"
[Sonar]
HostUrl=http://sonar.company.com:9000
ProjectKey=my-delphi-project
TokenRef=ide-default

[SonarTokens]
ide-default=$hex
"@ | Set-Content $ini -Encoding utf8
```

Ensuite, plus aucune option n'est nécessaire :

```powershell
analyser.exe --sonar-test
```

DPAPI lie le fichier à ce compte Windows — une copie est inutilisable sur
une autre machine ou sous un autre utilisateur. Ce n'est pas un
coffre-fort : tout programme s'exécutant *sous votre identité* le déchiffre
tout aussi bien. Pour la CI, utilisez l'option B.

Si une entrée commence par `PT:`, c'est du Base64 pur, non chiffré (le
repli hors Windows). L'EXE lit aussi ces entrées et émet alors un
avertissement.

---

## 2. Tester la connexion

```powershell
analyser.exe --sonar-test
```

Sortie attendue (les quatre étapes au vert) :

```
Sonar config:
  host    = http://sonar.company.com:9000   (CLI --sonar-host)
  project = my-delphi-project               (analyser.ini)
  token   = (42 chars from CLI --sonar-token)

[OK]   DNS resolution: sonar.company.com -> 10.0.0.42
[OK]   HTTP /api/system/status: UP
[OK]   Token validation: valid
[OK]   Project access: my-delphi-project (visible)
Sonar connection healthy.
```

En cas d'échec : la ligne `[FAIL]` indique la cause (DNS, état du serveur,
jeton ou permission sur le projet).

---

## 3. Générer les résultats

### 3.1 (Optionnel) Créer sonar-project.properties

```powershell
cd D:\path\to\your\repo
analyser.exe --sonar-init
```

Écrit un modèle dans `sonar-project.properties` — à adapter :

```properties
sonar.projectKey=my-delphi-project
sonar.projectName=My Delphi Project
sonar.sources=.
sonar.sourceEncoding=UTF-8
sonar.exclusions=**/*.dcu,**/*.bpl,**/lib/**,**/Win32/**,**/Win64/**
sonar.externalIssuesReportPaths=sca-findings.json
```

Ce fichier est validé dans le VCS (le jeton n'y a **pas** sa place — il
arrive à l'exécution via une variable d'environnement ou l'INI DPAPI).

Alternative : passer toutes les valeurs via `-D` à chaque appel (voir
l'étape 4 ci-dessous). Aucun `sonar-project.properties` n'est alors
nécessaire.

### 3.2 Analyse + export

```powershell
analyser.exe `
  --path D:\path\to\your\repo `
  --full `
  --base-dir D:\path\to\your\repo `
  --sonar-export D:\path\to\your\repo\sca-findings.json
```

Points clés :
- `--full` = analyse récursive (le mode branche serait `--branch` —
  seulement les fichiers modifiés dans le VCS)
- `--base-dir` garantit que les chemins de fichiers du JSON sont
  **relatifs** à la racine du dépôt, pas absolus. Sinon Sonar ne peut pas
  relier les résultats aux fichiers source
- `--sonar-export <file>` écrit le JSON au format Sonar Generic Issue
- Optionnel : `--quiet` supprime la sortie par résultat (seul le résumé
  final reste)

Dernière ligne de la sortie :
```
Sonar Generic report written: D:\path\to\your\repo\sca-findings.json
Findings: 529 (Errors: 18, Warnings: 30, Hints: 481)
```

---

## 4. Push avec sonar-scanner

### Variante 1 — avec `sonar-project.properties`

```powershell
$env:SONAR_TOKEN = "squ_xxxxxxxxxx"
cd D:\path\to\your\repo
sonar-scanner
```

Le scanner lit `sonar-project.properties` automatiquement.

### Variante 2 — tous les paramètres en ligne

```powershell
$env:SONAR_TOKEN = "squ_xxxxxxxxxx"
cd D:\path\to\your\repo

sonar-scanner `
  "-Dsonar.host.url=http://sonar.company.com:9000" `
  "-Dsonar.projectKey=my-delphi-project" `
  "-Dsonar.projectName=My Delphi Project" `
  "-Dsonar.sources=." `
  "-Dsonar.sourceEncoding=UTF-8" `
  "-Dsonar.exclusions=**/*.dcu,**/*.bpl,**/lib/**,**/Win32/**,**/Win64/**" `
  "-Dsonar.externalIssuesReportPaths=sca-findings.json"
```

Une sortie réussie se termine par :
```
INFO  ANALYSIS SUCCESSFUL, you can find the results at:
      http://sonar.company.com:9000/dashboard?id=my-delphi-project
INFO  EXECUTION SUCCESS
INFO  Total time: 22.081s
```

La première exécution est plus lente (Sonar télécharge les plugins de
langage). Les exécutions suivantes prennent ~10–30 s selon le nombre de
fichiers.

---

## 5. Script tout-en-un (exemple)

Enregistrez-le sous `push-to-sonar.ps1` à la racine du dépôt et lancez-le
comme tâche planifiée ou à la main :

```powershell
# push-to-sonar.ps1
$ErrorActionPreference = "Stop"

$exe = "D:\git-demos\delphi\StaticCodeAnalyser\StaticCodeAnalyserForm\Win32\Release\StaticCodeAnalyser.d12.exe"
$repo = $PSScriptRoot
$json = Join-Path $repo "sca-findings.json"

# Charger le jeton chiffré DPAPI depuis analyser.ini
Add-Type -AssemblyName System.Security
$ini = Get-Content "$env:APPDATA\StaticCodeAnalyser\analyser.ini" -Raw -Encoding UTF8
$tokenHex = ([regex]::Match($ini, '(?m)^ide-default=(.+)$')).Groups[1].Value.Trim()
$bytes = [byte[]]::new($tokenHex.Length / 2)
for ($i = 0; $i -lt $tokenHex.Length; $i += 2) {
  $bytes[$i / 2] = [Convert]::ToByte($tokenHex.Substring($i, 2), 16)
}
$env:SONAR_TOKEN = [System.Text.Encoding]::UTF8.GetString(
  [System.Security.Cryptography.ProtectedData]::Unprotect(
    $bytes, $null, "CurrentUser"))

try {
  # 1. Analyse + export
  & $exe --path $repo --full --base-dir $repo --sonar-export $json --quiet
  if ($LASTEXITCODE -ge 99) { throw "SCA failed (exit $LASTEXITCODE)" }

  # 2. Push
  Push-Location $repo
  try {
    & sonar-scanner   # lit sonar-project.properties
    if ($LASTEXITCODE -ne 0) { throw "sonar-scanner failed (exit $LASTEXITCODE)" }
  } finally {
    Pop-Location
  }
} finally {
  Remove-Item Env:SONAR_TOKEN -ErrorAction SilentlyContinue
}
```

---

## Dépannage

| Symptôme | Cause | Correctif |
|---|---|---|
| `[FAIL] DNS resolution` | Hôte injoignable, faute de frappe dans l'URL | Vérifier l'URL, pinger l'hôte |
| `[FAIL] HTTP /api/system/status: 503` | Le serveur démarre encore | Attendre ~60 s, réessayer |
| `[FAIL] Token validation: 401` | Jeton invalide / expiré | Générer un nouveau jeton dans Sonar |
| `[FAIL] Project access: not found` | Le projet n'existe pas | Le créer dans Sonar (interface web) |
| `[FAIL] Project access: 403` (le projet existe) | Permission Browse manquante | Project Permissions → accorder Browse |
| `Failed to parse report: either type, impacts or both should be provided` | EXE autonome obsolète sans catalogue | Recompiler l'EXE (0.2), déployer le catalogue dans APPDATA (0.3) |
| Issues absentes dans Sonar | Mauvais `--base-dir` → chemins absolus | Mettre `--base-dir` égal à `--path` |
| `sonar-scanner` introuvable | PATH non actif | Ouvrir une nouvelle fenêtre de shell |
| Des fichiers apparaissent « Empty » dans Sonar | `sonar.exclusions` trop large | Revoir `sonar.exclusions` dans les properties |

---

## Références

- [docs/sonar-setup.md](docs/sonar-setup.md) — guide de mise en place complet (avec plugin IDE et exemples CI)
- [docs/sonar-config.md](docs/sonar-config.md) — ordre du résolveur (CLI > Env > Properties > INI)
- [Documentation Sonar Scanner](https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/scanners/sonarscanner/)
- [Sonar Generic Issue Format](https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/importing-external-issues/generic-issue-import-format/)

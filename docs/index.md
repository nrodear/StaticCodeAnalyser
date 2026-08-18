# Documentation index

Everything the project ships as documentation, in one place. The README is
the front door; this page is the map behind it.

🇩🇪 Most documents exist in both languages — the German version always
carries the `_de` suffix (`README_de.md`, `EXPORTS_de.md`, …).

---

## Start here

| Document | What it answers |
|---|---|
| [../README.md](../README.md) | What the tool does, how to run it, architecture, performance, suppression, theming. Start here if you have not used it before. |
| [../HowTo_Build.md](../HowTo_Build.md) | How to build the EXE, the IDE plugin and the test project from source (building is optional - releases ship a setup and a GetIt package). |
| [../HowTo_Tests.md](../HowTo_Tests.md) | How to run the DUnitX suite and the dogfooding gate. |
| [../CHANGELOG.md](../CHANGELOG.md) | What changed, release by release, with the reasoning. |
| [configuration.md](configuration.md) | **Every `analyser.ini` key** with its default and meaning - thresholds, profiles, baseline, UI. Also in [German](configuration_de.md) and [French](configuration_fr.md). |

## Rules and findings

| Document | What it answers |
|---|---|
| [rules.md](rules.md) | The rule catalogue: every `SCA###` with severity, default profile membership and a one-line description. |
| [rules/index.md](rules/index.md) | One page per rule — what it flags, why it matters, how to fix it, and how to suppress it when the finding is intentional. |
| [../DETECTORS.md](../DETECTORS.md) | Implementation status per detector and which unit is responsible. Useful when contributing a detector. |

## Getting findings out of the tool

| Document | What it answers |
|---|---|
| [../EXPORTS.md](../EXPORTS.md) | **All export formats** (SARIF, Sonar, HTML, CSV, JSON, baseline) — which one to pick for which workflow, and the CLI switches that drive them. |
| [../examples/ci/README.md](../examples/ci/README.md) | Ready-made CI setups: GitHub Actions, a pre-commit hook, a PR-comment bot, an MSBuild pre-build step. |
| [../examples/README.md](../examples/README.md) | The rest of the example material (custom rules, configuration snippets). |

## SonarQube / SonarCloud

| Document | What it answers |
|---|---|
| [sonar-setup.md](sonar-setup.md) | Full setup: server, token, project properties, export, scanner run, troubleshooting. |
| [sonar-config.md](sonar-config.md) | Reference for the four configuration sources and which command actually reads them. |
| [../sonarHowto.md](../sonarHowto.md) | Step-by-step walk-through for the standalone EXE, including an all-in-one PowerShell script. |
| [sonar-coverage.md](sonar-coverage.md) | How SCA rules map onto Sonar's own rule set — where the two overlap and where SCA adds something. |

## IDE plugin

End users install the plugin one of two ways: the release **setup EXE**
(`StaticCodeAnalyserSetup-<Version>.exe`) or the **GetIt local package**
from the release assets.

| Document | What it answers |
|---|---|
| [../README.md](../README.md#usage) | Plugin usage: buttons, the docked findings window, hover overlays, the options pages. |
| [../BRANCH_CHANGES.md](../BRANCH_CHANGES.md) | The Branch-Changes feature: Git/SVN detection, Tortoise compatibility, configuration, troubleshooting. |
| [../installer/README_Installer.md](../installer/README_Installer.md) | Building and running the plugin installer. |
| [../getit/README_GetIt.md](../getit/README_GetIt.md) | GetIt local package - manifest contracts and lessons. |

## Embedding the engine

| Document | What it answers |
|---|---|
| [../SCA.Engine/API.md](../SCA.Engine/API.md) | The engine API: how to run an analysis from your own Delphi code without the UI. |
| [../SCA.CLI.Demo/README.md](../SCA.CLI.Demo/README.md) | A minimal console program built on that API, as a starting point. |

## Release history

`releases/` holds the notes for each released version in both languages —
[../RELEASE_NOTES.md](../RELEASE_NOTES.md) always points at the current one.

---

Screenshots and animations used by the README live in this folder as
`.gif` files; they are not documents in their own right.

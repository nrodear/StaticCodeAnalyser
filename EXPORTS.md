# Getting findings out of SCA — formats and workflows

🇩🇪 [Deutsche Version](EXPORTS_de.md)

This page answers one question: **"I ran the analyser — how do I get the
findings where I need them?"** It covers every export the tool can
produce, which of the three front-ends can produce it, and the six
workflows teams actually run.

Everything here was verified against the built v0.9.14 binary. Where a
path is known to be broken today, it says so, with the workaround.

---

## The one thing to know first

`analyser.exe` is **one binary with two modes**. It starts the GUI when
launched without arguments, and switches to headless CLI as soon as the
first argument begins with `-`. So "GUI only" never means "different
program" — it means *not reachable from a script*.

---

## Format matrix

| Format | CLI switch | GUI / plugin menu | Good for |
|---|---|---|---|
| **SARIF 2.1.0** | `--report-sarif <file>` | ✅ *SARIF (all findings)* | GitHub / Azure code scanning, archival, tool interchange |
| **Sonar Generic Issue** | `--sonar-export <file>` | ✅ *Sonar: write Generic Issue report* | SonarQube dashboard (see caveat below) |
| **HTML report** | `--report-html <file>` | ✅ | Reading and sharing findings without any tooling |
| **Baseline JSON** | `--write-baseline <file>` | ✅ *Write baseline* | CI gate: "fail only on **new** findings" |
| **CSV** | — | ✅ | Excel, pivot tables, ad-hoc counting |
| **JSON** | — | ✅ | Own scripts, ticket automation |
| **Jira wiki markup** | — | ✅ | Pasting a finding into a ticket |
| **AI prompt (clipboard)** | — | ✅ | Hand a single finding to an assistant, with code context |
| **Suppression telemetry** | `--telemetry-csv <file>` | — | Which rules get suppressed most (noise ranking) |
| **Detector timings** | `--time-detectors-out <file>` | — | Finding slow detectors |

Two asymmetries are worth knowing before you plan anything:

- **CSV and JSON exist only in the GUI.** The two formats you would
  reach for in a script are the two you cannot script.
- **Scope differs by front-end.** From the CLI, exports contain the
  findings *after* test-fixture and baseline filtering. From the GUI
  menu, the "all findings" entries export the **unfiltered** list
  regardless of what the grid shows. The menu captions say which is
  which — read them.

All three JSON formats are written **UTF-8 with BOM**. SonarQube
tolerates it; `JSON.parse` in Node and `json.load(encoding='utf-8')` in
Python do not. Strip it or read with `utf-8-sig`.

---

## Workflow 1 — CI gate: fail the build on new findings

The baseline is the mechanism: it records today's findings so that
tomorrow's build only complains about what was added.

```bash
# once, to record the status quo
analyser.exe --path . --write-baseline .sca/sca.baseline.json

# in every build
analyser.exe --path . --baseline .sca/sca.baseline.json --report-sarif build/sca.sarif
```

Exit codes are graded: `0` clean, non-zero when findings remain after
the baseline filter. `--fail-on error|warning|hint|none` narrows what
counts. Read errors and tool errors always stay non-zero.

**Use an absolute path or a path with a directory part for
`--write-baseline`.** A bare file name (`--write-baseline b.json`)
fails with *"Baseline write error: Verzeichnis kann nicht erstellt
werden"* — verified on v0.9.14.

**Do not refresh a baseline by combining the two switches.** The
documented-looking `--baseline old --write-baseline new` writes only the
findings that *survived* the filter — that is, the new ones. Measured on
a real repository: a 226-entry baseline became **0 entries**, and the
next build reported the whole backlog again. To refresh, write a fresh
baseline from a clean run without `--baseline`.

## Workflow 2 — Pull-request review: only what changed

```bash
analyser.exe --path . --diff main...HEAD --report-html build/review.html
```

`--branch` uses the VCS's changed-file set (Git and SVN auto-detected),
`--diff <range>` a Git range including `a...b` common-ancestor form.
Both include uncommitted edits. The HTML report is self-contained — no
external assets, opens from a file share or a CI artifact.

## Workflow 3 — SonarQube dashboard

SCA does **not** push to SonarQube, and that is correct: Sonar has no
public ingest API for external issues. SCA writes the file, and
`sonar-scanner` carries it in.

```bash
analyser.exe --path . --base-dir . --sonar-export sca-findings.json
sonar-scanner -Dsonar.externalIssuesReportPaths=sca-findings.json
```

> **⚠️ Broken in the released ZIP — read this before you try.** The
> release archive contains only the EXE. Without `rules/sca-rules.json`
> beside it the rule catalog falls back to a built-in stub that emits
> `type` instead of `cleanCodeAttribute` + `impacts`, and **SonarQube
> rejects the entire report** (verified against the real scanner-engine
> validators: 10.7 reports *missing mandatory field
> 'cleanCodeAttribute'*, 2025.x *missing mandatory field 'severity'*).
> The run looks successful and the file is written — only the dashboard
> stays empty.
>
> **Workaround:** copy the repository's `rules/` folder next to the EXE.
> With the catalog present the export validates on every tested engine
> generation. A corrupt `rules/sca-rules.json` degrades the same way,
> also silently.

Paths in the report are relative to `--base-dir` (default: `--path`), so
run the export with the same root the scanner uses. Files outside that
root fall back to absolute paths, which Sonar silently discards as
"unknown files".

## Workflow 4 — GitHub / Azure code scanning

```bash
analyser.exe --path . --base-dir . --report-sarif sca.sarif
```

The SARIF carries `partialFingerprints` (line hash + contextHash), so
alerts keep their identity across line drift. Paths are relative to
`--base-dir` — point it at the repository root, which is what code
scanning expects.

Two things to watch: the UTF-8 BOM can trip Node-based uploaders, and
uploading a **baseline-filtered** SARIF fights the platform's own alert
lifecycle (it resolves everything the filter removed). For code scanning,
upload the unfiltered report and let the platform track state.

## Workflow 5 — Developer at the desk

Use the GUI or the IDE plugin: run, filter with the stat tiles, click a
finding, read the before/after help. `Ctrl+Alt+S` inserts a suppression
marker, `Ctrl+Alt+F` applies a quick fix. Findings open in the editor of
your choice via `[Editor]` in `analyser.ini` (VS Code, Notepad++,
Sublime, …) — that path jumps to the exact line. The Delphi IDE only
opens the file; it offers no external line switch.

For sharing, `--report-html` is the format that needs no tooling on the
other side.

> **Note on sharing:** the HTML report embeds source excerpts. Treat it
> like source code when you send it somewhere.

## Workflow 6 — Reporting over time

There is no built-in trend store. Two practical routes: archive the
SARIF per build and count with `jq`, or let SonarQube keep history via
Workflow 3. The per-rule counts in the console summary are stable enough
to graph if you capture them.

---

## Known limitations

Honest list, as of v0.9.14 — all reproduced:

| Area | Behaviour |
|---|---|
| Sonar export from the release ZIP | Rejected by SonarQube; ship `rules/` alongside the EXE |
| Baseline refresh with both switches | Truncates the baseline to the new findings |
| `--write-baseline` with a bare file name | Fails to write |
| CSV / JSON | GUI only, not scriptable |
| JSON exports | UTF-8 **with** BOM |
| HTML report | Stores base file names only; same-named units in different folders collide |
| Baseline fingerprints | Same-named units in different folders share a namespace; the `PathInFingerprint` opt-in is INI-only, not reachable from the CLI |
| Unreadable source files | Counted differently in console, SARIF/Sonar/HTML and baseline |
| `--parallel` | Not deterministic; do not use it for exports you compare |
| `--sonar-insecure` | Does not accept self-signed certificates (it only enables TLS 1.1) |
| `--sonar-test` inside a foreign repo | A `sonar-project.properties` in the scanned repo overrides your host — your token is sent there |

---

## Which format for which job

- **A gate that blocks bad merges** → baseline + exit code, archive the
  SARIF as evidence.
- **A dashboard your team looks at** → Sonar export plus scanner
  (with `rules/` beside the EXE).
- **A person who has to read it** → HTML report.
- **Your own tooling** → SARIF; it is the richest and the only one with
  fingerprints, and everything else can be derived from it.

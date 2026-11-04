# Getting findings out of SCA — formats and workflows

🇩🇪 [Deutsche Version](EXPORTS_de.md) · 🇫🇷 [Version française](EXPORTS_fr.md)

This page answers one question: **"I ran the analyser — how do I get the
findings where I need them?"** It covers every export the tool can
produce, which of the three front-ends can produce it, and the six
workflows teams actually run.

The workflows here were verified against built binaries (v0.9.14 and
later); the sections on the workbench report describe the 0.9.19 state.
Where a path is known to be broken today, it says so, with the
workaround.

---

## The one thing to know first

`StaticCodeAnalyser.d12.exe` is **one binary with two modes**. It starts
the GUI when launched without arguments, and switches to headless CLI as
soon as the first argument begins with `-`. So "GUI only" never means
"different program" — it means *not reachable from a script*.

---

## Format matrix

| Format | CLI switch | GUI / plugin menu | Good for |
|---|---|---|---|
| **SARIF 2.1.0** | `--report-sarif <file>` | ✅ *SARIF (all findings)* | GitHub / Azure code scanning, archival, tool interchange |
| **Sonar Generic Issue** | `--sonar-export <file>` | ✅ *Sonar: write Generic Issue report* | SonarQube dashboard (see caveat below) |
| **HTML report (CLI)** | `--report-html <file>` | — | Reading and sharing findings without any tooling |
| **HTML report (GUI)** | — | ✅ | The same purpose, a different page — see below |
| **Baseline JSON** | `--write-baseline <file>` | ✅ *Write baseline* | CI gate: "fail only on **new** findings" |
| **CSV** | `--report-csv <file>` | ✅ | Excel, pivot tables, ad-hoc counting |
| **JSON** | `--report-json <file>` | ✅ | Own scripts, ticket automation |
| **Jira wiki markup** | — | ✅ | Pasting a finding into a ticket |
| **Plain text (clipboard)** | — | ✅ | One file's findings with before/after, for pasting |
| **Sonar: single finding** | — | ✅ | One selected finding as an external-issue file under `.sonar\external\` |
| **Detector info (rule catalog)** | — | ✅ | Self-contained HTML page of all 205 rules — not a findings export |
| **AI prompt (clipboard)** | — | ✅ | Hand a single finding to an assistant, with code context |
| **Suppression telemetry** | `--telemetry-csv <file>` | — | Which rules get suppressed most (noise ranking) |
| **Detector timings** | `--time-detectors` (stdout) / `--time-detectors-out <file>` | — | Finding slow detectors |

**Two HTML reports, not one.** They serve the same purpose and share
their look, but they are separate pages and neither replaces the other:

- `--report-html` is the CLI report. Every finding stands on the page
  with its source excerpt; the rule report is a collapsible aggregate
  next to the table. Built for reading top to bottom and for archiving.
- The GUI's *HTML report* is the **workbench** page. Search, file and
  rule dropdowns, chips, top-lists, sortable columns, and a side drawer
  that shows source excerpt and rule documentation for the finding you
  clicked. Built for working through a large report at the desk. Its
  suggested file name carries the date:
  `sca_codereview_YYYY-MM-DD.html`.

**Row budget of the HTML table.** The table renders at most 20,000
findings; `--html-max-rows <n>` changes that (`0` = unlimited, an
unreadable value falls back to the default rather than to unlimited).
The report grows by roughly 4 KB per finding, so a full corpus run
without a budget would produce gigabytes. What the budget drops is
never silent: a banner above the table names the number of hidden
findings, and the summary keeps counting **all** of them. Filter,
search and sorting only ever work on the rendered rows.

**Which rule set produced this report.** The machine-readable
`sca-meta` block in the page head carries `profile`: the name of the
rule profile the scan ran with. An empty value means the run named no
profile (neither `--profile` nor `[Rules] Profile`); the analyser then
ran the `default` profile.

**Editor helps in both HTML reports.** For a rule with an **editor help**
(a code action of the IDE module reDelphix: light bulb, Ctrl+Alt+F)
the `--report-html` page names the helps — on by default;
`--html-no-editor-help` leaves them out, and the page is then exactly
the one without them. The rule report gets a column *Editor helps*
with the list of each rule, one entry per menu entry: the id
(`SCA017`, `SCA017.2` for a second entry), the menu text read from its
slug (`put-debug-output-in-ifdef-debug` becomes "Put debug output in
ifdef debug": hyphens become spaces, the first letter upper case — the
CLI does not link reDelphix and does not know the menu text itself)
and the effect, translated by the language switch of the page (keeps
behaviour / changes behaviour / depends on the finding / template,
writes nothing). The details of a finding show the same list in one
line, "Editor helps: …". The list stands **once per rule**; a finding
carries only a reference of about 40 bytes, so the report does not
grow by the list with the number of findings. The list comes from the
rule catalog (`editorHelps`), like the SARIF field below. The
**workbench page** of the GUI and the IDE shows the same list, in the
language of the page, as the first line of the rule documentation in
the drawer — once per rule, not one extra byte per finding (the export
menu always includes it; in code `AEditorHelp` of
`TFindingsWorkbenchExport.BuildHtml`/`Run`, default on). The other
exports (CSV, JSON, Sonar) carry no editor helps; SARIF names them
only with `--sarif-editor-help`.

The workbench page keeps the rule documentation **once per rule**, the
source excerpt as plain text, and no per-finding copy of the search
text — which is why it stays roughly half the size the same report used
to have. Both are self-contained: no external assets, nothing leaves
the machine.

Two asymmetries are worth knowing before you plan anything:

- **CSV and JSON export the CLI's filtered view.** Like the other CLI
  exports, they contain what survived the test-fixture and baseline
  filters; the GUI's "all findings" entries do not filter.
- **Scope differs by front-end.** From the CLI, exports contain the
  findings *after* test-fixture and baseline filtering. From the GUI
  menu, the "all findings" entries export the **unfiltered** list
  regardless of what the grid shows. The menu captions say which is
  which — read them.

**Encoding.** All JSON formats (SARIF, Sonar, `--report-json`, baseline)
are written as **UTF-8 without BOM** — RFC 8259 §8.1 forbids the byte
order mark for JSON interchange, and `JSON.parse` in Node chokes on it,
which is what GitHub's `upload-sarif` action uses. CSV is the deliberate
exception and keeps its BOM, because that is how Excel recognises UTF-8.

Up to and including **v0.9.14** the JSON exports did carry a BOM; if you
are on that build, strip it or read with `utf-8-sig`.

**Resolving the paths in SARIF.** When `--base-dir` is set (the CLI
defaults it to `--path`), finding uris are relative and `runs[0]`
names their root as `originalUriBaseIds.SRCROOT`; every location
carries `uriBaseId: "SRCROOT"`. Without a base directory the paths
stay absolute and become `file://` uris, which carry their own root —
no `uriBaseId` is emitted then, because claiming one would be wrong.

**Rule id in `--report-json`.** Each entry carries the rule id twice:
`ruleId` is the canonical spelling — the same one SARIF and the Sonar
export use — and `ruleID` is the pre-0.9.19 name, kept so existing
readers do not break. Same value in both; prefer `ruleId`, treat
`ruleID` as deprecated.

**Empty method.** The method of a finding (CSV, JSON, HTML, workbench,
baseline) is only filled in when the line lies inside a routine. A
finding on a comment, a class declaration or a form file has an empty
method. Since this is new in 0.9.19, such a finding changes its
fingerprint; a baseline with a `contextHash` still matches it while the
lines around it are unchanged.

---

## Workflow 1 — CI gate: fail the build on new findings

The baseline is the mechanism: it records today's findings so that
tomorrow's build only complains about what was added.

```bash
# once, to record the status quo
StaticCodeAnalyser.d12.exe --path . --write-baseline .sca/sca.baseline.json

# in every build
StaticCodeAnalyser.d12.exe --path . --baseline .sca/sca.baseline.json \
  --report-sarif build/sca.sarif
```

**A baseline entry covers one finding.** Since 0.9.19 the baseline counts:
two entries with the same fingerprint cover two findings, a third one is
new. Before, one entry hid every finding with that fingerprint, so
findings it used to hide show up as new.

Exit codes are graded: `0` clean, non-zero when findings remain after
the baseline filter. `--fail-on error|warning|hint|none` narrows what
counts. Read errors keep a run non-zero in every mode but `none`: where
the policy would otherwise return 0, the run exits 4 instead — an
incomplete scan must never look like a clean one. Tool errors (99) are
decided before `--fail-on` is consulted and cannot be lowered at all.

**In CI, prefer `--baseline-scan y` over naming the file.** It resolves
the baseline in three steps — `--baseline`, then `[Baseline] File=` from
`analyser.ini`, then the `.sca` folder next to `--project` /
`--project-group` (or `<path>\.sca\sca.baseline.json`) — and reports
which one it took. The point is the failure behaviour: if you ask for a
baseline and none is found, the run **aborts with exit 99** and lists
every path it tried, instead of quietly reporting the whole backlog as
new. That silent variant is the classic way a green pipeline stops
meaning anything. `--write-baseline auto` writes to the same `.sca`
location, so the pair needs no hard-coded paths:

```bash
StaticCodeAnalyser.d12.exe --path . --write-baseline auto    # once
StaticCodeAnalyser.d12.exe --path . --baseline-scan y        # every build
```

`--baseline-scan n` is the explicit opposite: run without a baseline even
if a file is lying around. Any other value is rejected outright.

**If the same unit name exists in several folders, add
`--baseline-path-fingerprint y`.** By default a fingerprint identifies a
finding by *file name*, not by path, so two `uSame.pas` in different
folders share one identity. Measured consequence: a baseline written from
one subfolder silently suppressed **every** finding in a sibling folder —
including an SQL injection nobody had ever reviewed; with the switch the
same run keeps them. It changes fingerprints, so write a fresh baseline
when you turn it on.

The `contextHash` stage (the lines around a finding) is keyed by the
same file token, plus rule and hash. By default the token is the file
name: a baseline then survives moving a file to another folder, and
byte-identical copies of a file share their entries. With
`--baseline-path-fingerprint y` the token is the relative path: moved
files show their findings as new once, and copies in different folders
stay apart.

**Refreshing a baseline with both switches.** `--baseline old
--write-baseline new` writes the full current state into `new` — every
finding of the run, the new ones included — and filters against `old`
in the same run. That refreshes the baseline, but it also accepts
everything that is new today: look at the new findings of that run
before you keep the refreshed file.

## Workflow 2 — Pull-request review: only what changed

```bash
StaticCodeAnalyser.d12.exe --path . --diff main...HEAD \
  --report-html build/review.html
```

`--branch` uses the VCS's changed-file set (Git and SVN auto-detected)
and includes uncommitted edits unless `[Repo] IncludeWorkingTree=0`.
`--diff <range>` takes a Git range including the `a...b`
common-ancestor form and compares committed states only.

Since 2026-08-25 a **failed VCS call exits 99** with the reason on
stderr - a shallow clone whose base commit was never fetched (the GitHub
Actions default of `fetch-depth: 1`) no longer turns the pipeline green
without scanning a single file. Exit 0 is reserved for a genuinely empty
diff. Fetch the base explicitly, e.g. `git fetch origin main` before the
scan. The HTML report is self-contained — no
external assets, opens from a file share or a CI artifact.

## Workflow 3 — SonarQube dashboard

SCA does **not** push to SonarQube, and that is correct: Sonar has no
public ingest API for external issues. SCA writes the file, and
`sonar-scanner` carries it in.

```bash
StaticCodeAnalyser.d12.exe --path . --base-dir . \
  --sonar-export sca-findings.json
sonar-scanner -Dsonar.externalIssuesReportPaths=sca-findings.json
```

Short guide with the mistakes worth avoiding: [sonarHowto.md](sonarHowto.md).

> **Keep `rules/sca-rules.json` beside the EXE.** The release ZIP ships
> it. Without it the rule catalog falls back to a built-in stub: the
> report stays valid, but its rules carry coarse attributes and impacts
> instead of the catalog values.

Paths in the report are relative to `--base-dir` (default: `--path`), so
run the export with the same root the scanner uses. Files outside that
root fall back to absolute paths, which Sonar silently discards as
"unknown files".

**Read errors are not in the Sonar report.** A file the analyser could
not read is a statement about the completeness of the run, not about the
source — as a dashboard issue it was noise nobody could act on. It stays
visible everywhere it belongs: the console summary, exit code 4, the HTML
report, and SARIF, which lists it both as a result and under
`runs[].invocations[].toolExecutionNotifications`. A run that produced
*only* read errors therefore exports `{"rules":[],"issues":[]}` — valid,
and Sonar accepts it. Check the console line, not the dashboard, to see
whether a scan was complete.

### What changes for existing users (export fix, October 2026)

If you already import SCA findings into SonarQube, the first analysis after
the update moves issues — once. Sonar matches issues per rule, file and
line, so every change below shows up as *closed* plus *new* in the
new-code period.

- **New issues appear.**
  - Form files whose extension is spelled differently on disk
    (`ABOUT.DFM` vs. `ABOUT.dfm`) were silently discarded by Sonar as
    unknown files. The export now uses the spelling on disk (reference
    corpus: 960 issues).
  - Custom rules with `severity: hint` were missing entirely; they are
    exported now.
  - Findings capped by the evidence policy (confidence *medium* → at most
    Warning) no longer count as downgraded. SCA001, SCA003, SCA004 and
    others now reach Sonar (reference corpus: +726 issues). Only a
    downgrade you configured yourself (`[PathOverrides]`) keeps a finding
    out; `--sonar-keep-downgraded` still brings those back.
- **Capped rules carry the capped severity.** The impact follows the
  findings of the run: if even the strongest finding of a rule is capped,
  the rule gets that severity as its impact — SCA004 without a proven
  finding arrives as SECURITY/MEDIUM instead of BLOCKER, SCA202 as
  RELIABILITY/MEDIUM. One finding at full severity keeps the catalog
  impacts for the whole rule, because Sonar has a severity per rule only;
  the impact can therefore change from run to run, the issues stay. With
  `[Rules] EvidenceTiering=0` the catalog impacts stay.
- **Binary forms on file level.** Issues in binary `.dfm` files, and
  issues on a line beyond the end of the file, now have no line. Before,
  such a line could make the scanner abort (*"N is not a valid line for
  pointer"*). Sonar closes the old line-bound issues and opens file-level
  ones.
- **Custom rule names and impacts.** Each custom rule now has its own name
  (`User-defined custom rule PROJ001`) and an impact that follows its YAML
  severity (error → HIGH, warning → MEDIUM, hint → LOW) instead of the
  shared placeholder MAINTAINABILITY/MEDIUM.
- **`engineId` only on the rule.** The issue-level `engineId` — a field of
  the deprecated format — is gone. Scripts that read the JSON directly take
  the engine from `rules[].engineId`.
- **Minimum server version.** The impact severities BLOCKER and INFO need
  SonarQube 10.8 or later (Server 2025.x, Community Build). On 10.3–10.7 a
  report containing them is invalid. SCA026 always carries BLOCKER, SCA004
  as soon as a run has a proven finding (a known token pattern).

`filePath` is resolved by Sonar relative to `sonar.projectBaseDir` (the
folder of `sonar-project.properties`), not relative to `sonar.sources` —
give `--base-dir` that folder.

## Workflow 4 — GitHub / Azure code scanning

```bash
StaticCodeAnalyser.d12.exe --path . --base-dir . --report-sarif sca.sarif
```

The SARIF carries `partialFingerprints` (line hash + contextHash), so
alerts keep their identity across line drift. Paths are relative to
`--base-dir` — point it at the repository root, which is what code
scanning expects.

The HTML report carries a collapsible **rule report** next to the
finding table: one row per rule that fired, with findings, the
error/warning/hint split, the confidence split and the share of the
total. It is the aggregate view — useful exactly when the finding
table is too long to read.

While the evidence policy (`[Rules] EvidenceTiering`, default on) is
active, every result also carries `properties.confidence`
(`low`/`medium`/`high`) — that is how a catalog-error rule reporting at
`level: warning` explains itself. The flag is stamped at **scan** time
and travels with the finding cohort, so toggling the ini between scan
and export cannot mix levels and confidence values from two different
policy states. With `EvidenceTiering=0` levels are not capped and no
result carries `properties.confidence`.

With **`--sarif-editor-help`** (off by default; without it the SARIF
is unchanged) a result of a rule that has an **editor help** (a code
action of the IDE module reDelphix: light bulb, Ctrl+Alt+F) carries
`properties.editorHelp`, one entry per menu entry as `id:effect:slug`,
on one line:

```json
"editorHelp": ["SCA017:changes:put-debug-output-in-ifdef-debug","SCA017.2:changes:delete-debug-output"]
```

`id` is the rule ID, `<rule ID>.2` for a second entry; `effect` is
`same` (keeps the behaviour), `changes` (changes it — never on
Ctrl+Alt+F), `depends` (depends on the finding) or `template` (writes
nothing into the source: SCA003 copies a parameterised SQL template to
the clipboard); `slug` names the menu text. The list comes from the
rule catalog (`editorHelps` in `rules/sca-rules.json`; the CLI does not
link reDelphix), so it says what the rule offers — whether the help
applies to that very finding is decided in the IDE. Results of rules
without a help carry no such field; `tool.driver.rules[]` carries the
same list in each rule's `properties`. The export menu of the GUI and
the IDE never write the field.

Two things to watch: a SARIF written by **v0.9.14 or earlier** carries a
UTF-8 BOM that trips Node-based uploaders (current output is BOM-free,
see *Encoding* above), and
uploading a **baseline-filtered** SARIF fights the platform's own alert
lifecycle (it resolves everything the filter removed). For code scanning,
upload the unfiltered report and let the platform track state.

## Workflow 5 — Developer at the desk

Use the GUI or the IDE plugin: run, filter with the stat tiles, click a
finding, read the before/after help. `Ctrl+Alt+S` inserts a suppression
marker; in the IDE plugin `Ctrl+Alt+F` applies the quick fix (reDelphix
package, the same as the light bulb). Findings open in the editor of
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

Honest list, as of v0.9.19:

| Area | Behaviour |
|---|---|
| Baseline fingerprints | Same-named units in different folders share a namespace by default — switch it off with `--baseline-path-fingerprint y` (see Workflow 1) |
| `--parallel` | Deterministic since 2026-08-20 (byte-identical to serial runs), but no speedup yet - the serial pre-phase dominates |

---

## Which format for which job

- **A gate that blocks bad merges** → baseline + exit code, archive the
  SARIF as evidence.
- **A dashboard your team looks at** → Sonar export plus scanner
  (with `rules/` beside the EXE).
- **A person who has to read it** → HTML report.
- **Your own tooling** → SARIF; it is the richest and the only one with
  fingerprints, and everything else can be derived from it.

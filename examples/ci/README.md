# CI Integration Examples

Reference setups for plugging the Static Code Analyser into common CI/CD
pipelines. Pick the one that matches your stack — they're independent.

| File | Purpose |
|---|---|
| `github-actions-sca.yml` | GitHub Actions workflow; uploads SARIF to Code-Scanning |
| `pre-commit-sca.ps1`     | Git client-side hook; blocks commits with Warnings+ |
| `pr-comment-bot.ps1`     | Posts a Markdown comment on the PR with only NEW findings |
| `msbuild-sca-target.xml` | MSBuild target snippet to embed SCA as pre-build step into a `.dproj` |

The examples expect the EXE as `tools\sca\StaticCodeAnalyser.d12.exe`.

---

## Common flags

All of these examples build on the new CLI flags. Cheat-sheet:

| Flag | Purpose |
|---|---|
| `--fail-on=<level>` | Exit-code policy: `error` / `warning` / `hint` / `none` / `graded` (default). With `warning`, hints are reported but don't fail the build. A run that hit read errors never reports success: where the policy would otherwise return 0, it returns 4 (1 read error + 2 hints: `graded` → 1, `warning` → 4) — only `--fail-on=none` returns 0 there. |
| `--baseline <file>` | Drop findings covered by an entry in `<file>`, each entry covering at most one finding. Only NEW findings count. |
| `--write-baseline <file>` | Write the current findings as the new baseline. Run on `main` after the team accepts the current state. |

Each baseline entry is matched in two steps. First the context hash: a
hash over the source lines around the finding (3 above, 3 below,
normalised), tied to file and rule. It survives line drift, re-indenting,
a renamed method and a changed message. Only if it does not match, the
fingerprint `SHA256(filename | kindname | methodname | detail)` decides.
An entry is lost only when both break — e.g. a method rename that also
changes the lines around the finding.

---

## github-actions-sca.yml — Workflow walkthrough

1. **Checkout** with `fetch-depth: 50` so `--branch` can diff against
   `main` if you switch from `--full` to `--branch` later.
2. **Run analyser** unfiltered, with `--base-dir .` so the paths in the
   SARIF are relative to the repo root, and `--fail-on=none` so this step
   itself stays green — the gate comes later.
3. **Upload SARIF** via `github/codeql-action/upload-sarif@v3` — the
   findings appear under **Security > Code scanning alerts** on the repo
   page, with diff-annotation on the PR itself.
4. **Archive SARIF** as a build artifact (30-day retention) so reviewers
   can download the full report when GitHub's UI summary isn't enough.
5. **Gate** in a step of its own.

**Why the upload is not baseline-filtered.** GitHub keeps the alert state
itself: it knows what is new, what is fixed and what a reviewer
dismissed. Feeding it a filtered report makes it close every alert the
baseline removed — the entire accepted backlog turns into "fixed" in one
run. So Code Scanning gets the complete picture, and the baseline is used
only where GitHub is not involved: the exit-code gate. Since one run
writes either the filtered or the unfiltered report, the baseline gate is
a second run; the workflow ships the severity gate as the default and the
baseline gate commented out next to it.

### Baseline workflow

```bash
# One-time setup on main (after team accepts current state):
StaticCodeAnalyser.d12.exe --path . --full --write-baseline sca.baseline.json
git add sca.baseline.json
git commit -m "ci: capture SCA baseline"

# Future PRs: only NEW findings count.
```

Refresh the baseline periodically (monthly / per release) so the gap
between baseline and current state doesn't grow unbounded:

```bash
StaticCodeAnalyser.d12.exe --path . --full --write-baseline sca.baseline.json
```

`--write-baseline` always records all current findings: the snapshot is
taken before the baseline filter. So `--baseline old --write-baseline new`
in one run is safe — `new` holds the complete current state, while output
and exit code count only what `old` does not cover.

A bare file name such as `sca.baseline.json` (relative to the current
directory) works for both switches. The file must
exist when you pass `--baseline`: a missing baseline is a hard error
(exit 99) on purpose, so that a typo in CI cannot silently report
"everything is new".

If several folders contain units with the same name, add
`--baseline-path-fingerprint y` (and write a fresh baseline): otherwise
one accepted finding suppresses the same-named unit everywhere else.

---

## pre-commit-sca.ps1 — Hook walkthrough

The hook runs the analyser on the working tree (`--branch` picks up only
files that differ from main). It uses the same `--baseline` mechanism so
the developer only sees findings they introduced.

### Install

Git for Windows starts hooks through its own `sh`. Do **not** copy the
script as `.git/hooks/pre-commit`: Windows PowerShell 5.1 does not run a
file without the `.ps1` extension (`-File` refuses it, a shebang call
hands it over as a command), so the hook body never runs and every commit
goes through. Keep the script as `.ps1` and add a two-line `sh` wrapper
named `pre-commit` that calls it with `-File` and hands its exit code to
Git (`exec`):

```powershell
# From repo root, in Windows PowerShell 5.1:
Copy-Item examples/ci/pre-commit-sca.ps1 .git/hooks/pre-commit-sca.ps1
Set-Content .git/hooks/pre-commit -Encoding Ascii -NoNewline -Value ("#!/bin/sh`n" +
  'exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(dirname "$0")/pre-commit-sca.ps1"' + "`n")
```

The wrapper needs LF line endings, hence `-NoNewline` with an explicit
`` `n ``. Use the current script: it calls the analyser with
`| Out-Host`, because `StaticCodeAnalyser.d12.exe` is a GUI-subsystem
program and PowerShell waits for it (and sets `$LASTEXITCODE`) only when
its output is piped - older copies without the pipe let every commit
through as well. The script expects the EXE at `tools\sca\StaticCodeAnalyser.d12.exe`
below the repo root; if it is missing, it prints
`[sca-hook] ... not found ... - skipping.` and lets the commit through.
Check the hook once: stage a unit with a known warning and commit - the
hook must print `[sca-hook] Static Code Analyser blocked the commit` and
the commit must not appear in `git log`.

Or via husky / lefthook / pre-commit-framework if your team prefers a
config-file-driven hook manager.

### Bypass (emergency)

```bash
git commit --no-verify
```

Don't make this a habit; the whole point of the hook is to catch
problems before they enter history.

---

## pr-comment-bot.ps1 — PR-comment-bot

Posts a Markdown summary comment to the open Pull-Request / Merge-Request
listing the **NEW** findings introduced by that PR (assumes a baseline
filter was applied during the analyser run).

Backends auto-detected from environment:
- **GitHub** (via [`gh` CLI](https://cli.github.com/)) when `$env:GITHUB_REPOSITORY` is set
- **GitLab** (via [`glab` CLI](https://gitlab.com/gitlab-org/cli)) when `$env:CI_PROJECT_PATH` is set

### Wire-up in GitHub Actions

Do **not** hand the bot the `sca.sarif` of `github-actions-sca.yml`: that
report is unfiltered on purpose (Code Scanning needs it complete), so the
bot would post the whole backlog as "new findings". Give it a report of a
baseline-filtered run of its own. Add to your existing workflow (after the
analyser step), and grant the job `pull-requests: write` under
`permissions:` — the shipped workflow only has `contents: read` and
`security-events: write`:

```yaml
- name: Scan for the PR comment (baseline-filtered)
  if: github.event_name == 'pull_request'
  run: |
    .\tools\sca\StaticCodeAnalyser.d12.exe `
      --path . --full --base-dir . --profile default `
      --baseline sca.baseline.json `
      --report-sarif sca-new.sarif `
      --fail-on=none --quiet | Out-Host

- name: Comment SCA findings on PR
  if: github.event_name == 'pull_request' && always()
  shell: pwsh
  env:
    GH_TOKEN: ${{ github.token }}   # gh needs a token in Actions
  run: |
    .\examples\ci\pr-comment-bot.ps1 `
      -SarifPath sca-new.sarif `
      -PrNumber ${{ github.event.pull_request.number }} `
      -Repo ${{ github.repository }}
```

The bot **exits 0** when the SARIF is missing, there is no PR context,
`gh`/`glab` is not installed or posting the comment fails (it then
prints a note instead of "posted successfully"). PR-comments are
nice-to-have, never block-the-build.

### Comment layout

The posted comment has:
- A summary table (errors / warnings / hints / total)
- The first 50 findings (configurable via `-MaxFindingsInComment`)
  sorted strongest-first
- Each finding as one row: severity icon · `file:line` · rule-id · detail

Long messages are truncated to 140 chars per row; full data is in the
SARIF artifact archived by `github-actions-sca.yml`.

---

## msbuild-sca-target.xml — Embed SCA as a Delphi pre-build step

Run the analyser automatically on every `Build` (F9 / Shift+F9 / CLI
`msbuild ProjectName.dproj`). Failure of the SCA step fails the build —
no developer can ship a regression without explicitly opting out.

### Wire-up (two options)

**Option A — paste into the `.dproj`:** open the `.dproj` in a text
editor, copy **everything between** `<Project ...>` and `</Project>` of
`msbuild-sca-target.xml` - the `<PropertyGroup>` with the defaults
**and** both `<Target>` blocks - and paste it **right before** the
closing `</Project>` tag. The targets alone do nothing: both run only if
`SCAEnabled` is `true`, and that default is set in the `<PropertyGroup>`.
Without it neither the analysis nor the `SCA SKIP` note appears, and the
build stays green.

**Option B — import from disk (recommended):** keep
`msbuild-sca-target.xml` somewhere central (e.g. `<repo>\build\`) and
add this one line near the bottom of every `.dproj` you want to gate:

```xml
<Import Project="..\..\build\msbuild-sca-target.xml" Condition="Exists('..\..\build\msbuild-sca-target.xml')" />
```

Option B is update-stable: change the snippet once, every `.dproj`
inherits the new behaviour on next build.

### Tuneable knobs (set via `/p:` on the MSBuild command-line, or by
adding `<Property...>` in the `.dproj`):

| Property | Default | Effect |
|---|---|---|
| `SCAExePath` | `..\tools\sca\StaticCodeAnalyser.d12.exe` | Where to find the analyser EXE |
| `SCABaseline` | `sca.baseline.json` | Drop known findings if file exists |
| `SCAFailOn` | `warning` | Severity to fail at (`error` / `warning` / `hint` / `none`) |
| `SCAProfile` | `default` | Rule-profile name from `rules/sca-rules.json` |
| `SCAScope` | `--branch` | `--branch` / `--full` / `--diff <range>` |
| `SCAEnabled` | `true` | Set to `false` to disable analysis temporarily |

```powershell
# Strict CI build (only errors fail the build):
msbuild MyApp.dproj /p:SCAFailOn=error /p:SCAScope=--full

# PR-style range scan (only the commits in this PR):
msbuild MyApp.dproj /p:SCAScope='--diff origin/main..HEAD'

# Skip SCA locally during quick iteration:
msbuild MyApp.dproj /p:SCAEnabled=false
```

The target prints
`SCA SKIP: StaticCodeAnalyser.d12.exe not found at '...'` and lets the
build continue if the EXE is missing — useful for developers who haven't
installed the tooling yet, while CI is gated.

---

## SonarQube + GitHub Code-Scanning side-by-side

If you already push to SonarQube, you can also push to GitHub
Code-Scanning by adding both export flags in the same run:

```yaml
- name: Analyse + export both formats
  run: |
    .\tools\sca\StaticCodeAnalyser.d12.exe `
      --path . --full `
      --report-sarif sca.sarif `
      --sonar-export sca.sonar.json `
      --fail-on=warning
```

SARIF goes to GitHub via the upload-sarif action; the Sonar JSON gets
picked up by `sonar-scanner` via
`sonar.externalIssuesReportPaths=sca.sonar.json` in your
`sonar-project.properties`. See the short guide in
[sonarHowto.md](../../sonarHowto.md).

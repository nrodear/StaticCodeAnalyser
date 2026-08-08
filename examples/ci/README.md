# CI Integration Examples

Reference setups for plugging the Static Code Analyser into common CI/CD
pipelines. Pick the one that matches your stack — they're independent.

| File | Purpose |
|---|---|
| `github-actions-sca.yml` | GitHub Actions workflow; uploads SARIF to Code-Scanning |
| `pre-commit-sca.ps1`     | Git client-side hook; blocks commits with Warnings+ |
| `pr-comment-bot.ps1`     | Posts a Markdown comment on the PR with only NEW findings |
| `msbuild-sca-target.xml` | MSBuild target snippet to embed SCA as pre-build step into a `.dproj` |

---

## Common flags

All of these examples build on the new CLI flags. Cheat-sheet:

| Flag | Purpose |
|---|---|
| `--fail-on=<level>` | Exit-code policy: `error` / `warning` / `hint` / `none` / `graded` (default). With `warning`, hints are reported but don't fail the build. |
| `--baseline <file>` | Drop findings whose fingerprint matches a known entry in `<file>`. Only NEW findings count. |
| `--write-baseline <file>` | Write the current findings as the new baseline. Run on `main` after the team accepts the current state. |

Fingerprint = `SHA256(filename | kindname | methodname | detail)`. Stable
across line-drift; refactors that rename a method DO invalidate the entry
(intentional — the rule context changed).

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
analyser.d12.exe --path . --full --write-baseline sca.baseline.json
git add sca.baseline.json
git commit -m "ci: capture SCA baseline"

# Future PRs: only NEW findings count.
```

Refresh the baseline periodically (monthly / per release) so the gap
between baseline and current state doesn't grow unbounded — but refresh
it in its **own** run:

```bash
analyser.d12.exe --path . --full --write-baseline sca.baseline.json
```

**Never combine `--baseline old --write-baseline new` in one run.** The
filter removes the known findings first, so the snapshot would contain
only what survived — i.e. it empties the baseline, and the next build
reports the whole backlog as new.

The path needs a directory part or must be absolute, and the file must
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

```powershell
# From repo root:
Copy-Item examples/ci/pre-commit-sca.ps1 .git/hooks/pre-commit
# No file extension! Git looks for "pre-commit" exactly.
```

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

Add to your existing workflow (after the analyser step):

```yaml
- name: Comment SCA findings on PR
  if: github.event_name == 'pull_request' && always()
  shell: pwsh
  run: |
    .\examples\ci\pr-comment-bot.ps1 `
      -SarifPath sca.sarif `
      -PrNumber ${{ github.event.pull_request.number }} `
      -Repo ${{ github.repository }}
```

The bot **exits 0 on any failure** (missing SARIF, no PR context, CLI
not installed). PR-comments are nice-to-have, never block-the-build.

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
editor, copy the `<Target>` blocks from `msbuild-sca-target.xml`, paste
**right before** the closing `</Project>` tag.

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
| `SCAExePath` | `..\tools\sca\analyser.d12.exe` | Where to find the analyser EXE |
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

The target prints `SCA SKIP: analyser.exe not found at '...'` and lets the
build continue if the EXE is missing — useful for developers who haven't
installed the tooling yet, while CI is gated.

---

## SonarQube + GitHub Code-Scanning side-by-side

If you already push to SonarQube, you can also push to GitHub
Code-Scanning by adding both export flags in the same run:

```yaml
- name: Analyse + export both formats
  run: |
    .\tools\sca\analyser.d12.exe `
      --path . --full `
      --report-sarif sca.sarif `
      --sonar-export sca.sonar.json `
      --fail-on=warning
```

SARIF goes to GitHub via the upload-sarif action; the Sonar JSON gets
picked up by `sonar-scanner` via
`sonar.externalIssuesReportPaths=sca.sonar.json` in your
`sonar-project.properties`. See [docs/sonar-setup.md](../../docs/sonar-setup.md)
for the full Sonar story.

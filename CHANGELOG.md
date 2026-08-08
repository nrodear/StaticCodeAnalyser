# Changelog

All notable changes to this project are documented here. Format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Fixed

- **The Sonar export was rejected by SonarQube in the shipped state.**
  The release ZIP contained only the EXE. Without `rules/sca-rules.json`
  beside it the rule catalog falls back to a built-in stub, and that
  stub emitted the legacy `type` field instead of `cleanCodeAttribute`
  + `impacts` — which makes SonarQube discard the **entire** report
  (verified against the real scanner-engine validators: 10.7 reports
  *missing mandatory field 'cleanCodeAttribute'*, 2025.x *missing
  mandatory field 'severity'*). The run looked successful, the file was
  written, and the dashboard stayed empty. Two changes: the fallback now
  emits the same MQR fields as the normal path, derived from the rule's
  finding type and default severity — and the release archive ships
  `rules/sca-rules.json` next to the EXE, verified by the packaging
  script itself.
- **Refreshing a baseline destroyed it.** `--baseline old
  --write-baseline new` wrote only the findings that had *survived* the
  filter, because the filter mutates the list in place and the snapshot
  ran afterwards. Measured: a 226-entry baseline became 0 entries, and
  the next build reported the whole backlog as new. The snapshot is
  taken before the filter now — a baseline is a picture of the current
  state, not of the difference.
- **`--write-baseline b.json` (a bare file name) failed to write.** The
  caller called `ForceDirectories` on the empty directory part.
- **`--sonar-insecure` did not accept self-signed certificates.** It only
  set the TLS protocol list — which has nothing to do with certificate
  trust — and in doing so re-enabled the deprecated TLS 1.1. It now
  installs the certificate-validation callback it always promised, and
  leaves protocol selection at the platform default.
- **A `sonar-project.properties` inside the scanned repository could
  redirect your token.** That file supplied `sonar.host.url` and
  outranked the user's own configuration, so `--sonar-test` in a cloned
  foreign repository sent the token — from the environment or the
  encrypted INI — to whatever host the repository named. `sonar.token`
  was already deliberately ignored there; the same reasoning now applies
  to the host. A hint tells you when a repository-supplied host was
  ignored.
- **Release archives used non-conformant entry names.** PowerShell's
  `Compress-Archive` writes backslashes into ZIP entries, so
  `rules/sca-rules.json` would have unpacked as a single oddly-named
  file on Linux and macOS. The archive is now built with explicit
  forward-slash entry names.

## [v0.9.14] - 2026-08-08 - A grey dark mode, and a safer IDE hand-off

### Changed

- **"Apply quick fix" left the result grid's right-click menu** (user
  decision). The action itself stays available as
  <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>F</kbd>, matching the plugin.
- **"SCA VSDark" palette v2 — one notch lighter, and the REAL cause of
  the black background fixed.** v0.9.13 shipped the literal VS Code
  values; chrome `#181818` reads as plain black on real monitors.
  Chrome is now `#252526`, widgets `#2D2D30`, borders `#3C3C3C`;
  content stays `#1F1F1F`. More importantly, a systematic audit traced
  the black to the style's **bitmaps** rather than its colour table:
  the form background is painted from bitmap data, and the stock
  Windows10 Dark bitmaps carry 109,171 opaque `#000000` pixels. The
  chrome panels sit on top of it with the VCL default
  `ParentBackground`, so they never fill with their own colour and
  that black showed through no matter which palette was configured.
  The style generator therefore lifts every opaque black pixel in the
  style bitmaps to the chrome tone (verified by counting them back to
  zero), and `cl3DDkShadow` — the grid header separator — moves from
  black to the border tone.

### Fixed

- **`--report-sarif` into a not-yet-existing folder aborted the run.**
  Writing `build/reports/sca.sarif` on a fresh CI checkout failed with
  a tool error and no report, while the sibling `--write-baseline`
  created the folder happily. Both writers create their target
  directory now — the SARIF writer and `TBaseline.Write`, whose own
  contract had promised to create the `.sca` folder while leaving the
  work to its callers (three did it, the fourth would have crashed).
- **A second scan in the same process could inherit the first one's
  baseline fingerprint mode.** `ResetEngineConfigDefaults` promises to
  reset every scan-configuration global, but the two added by the
  `PathInFingerprint` opt-in were missing from it. A fingerprint is
  supposed to be a pure function of the finding; via that gap it also
  depended on process history, which could silently invalidate a whole
  baseline. Both globals are reset now, and a regression test fails
  if the next one gets forgotten.

### Removed

- **The EXE's Delphi-IDE line jump — it could type the line number
  into your code.** Opening a finding sent Ctrl+G and then the digits
  after a fixed wait; a busy IDE (file still loading, LSP indexing)
  swallows the shortcut, and "300" plus Enter arrived as *text in line
  1 of the just-opened file*. The IDE offers no external line switch
  and keystroke simulation cannot be made reliable against a busy IDE,
  so the IDE path now only **opens** the file — instantly, without the
  ~1.6 s UI freeze the keystroke chain needed — and the status line
  says "Opened in Delphi IDE" without claiming a line it did not jump
  to. Line jumps remain where they actually work: the external editor
  (`%line%` in `[Editor]`), the built-in `.dfm` viewer — and the IDE
  plugin, whose ToolsAPI navigation was never affected.

## [v0.9.13] - 2026-08-08 - The baseline finds its home

### Added

- **Opt-in `[Baseline] PathInFingerprint=1`.** Baseline fingerprints
  then include the normalized relative path instead of just the file
  name, so same-named files in different folders no longer share
  accepted findings. Costs: baselines must be rewritten once, folder
  refactorings invalidate entries, and the scan scope must stay
  constant; a `pathFingerprint` marker in the JSON makes mode
  mismatches visible as a warning instead of silently matching
  nothing. Byte-identical file copies still match via the
  contextHash stage (by design).
- **Baseline files in a `.sca` folder + `--baseline-scan y|n`.** The
  baseline now has a canonical home next to the project file:
  `<dir>/.sca/<ProjectName>.baseline.json` (group and projects can
  share one folder; a project falls back to the parent `.sca` of its
  group). `--baseline-scan y` resolves the file via `--baseline` >
  `[Baseline] File=` (analyser.ini) > the `.sca` default location and
  FAILS HARD (exit 99) when no file exists - a typo in CI must not
  silently report "everything is new". An explicitly given
  `--baseline <file>` that is missing is now a hard error too
  (previously a silent no-op). `--write-baseline auto` writes to the
  `.sca` default location and creates the folder. The `.sca` folder
  is excluded from directory scans. The in-app "show only new
  findings" display filter stays fail-open by design.

- **New rule SCA196 `ManagedResultUninit` (Warning, Bug).** For managed
  return types (string family, dynamic arrays, `Variant`, interfaces)
  `Result` is a hidden var parameter aliasing the caller's target
  variable including its OLD content - the compiler hint W1035 stays
  silent for exactly these types. SCA196 reports the first `Result`
  READ before the first write (`Result := Result + [x]` collectors,
  `Result[i] :=` without `SetLength`, `Result.Add(...)`,
  `Exit(Result + ...)`). Corpus-validated across three measurement
  rounds (2171 → 105 → 51 findings after two FP-fix rounds); all 49
  unique corpus sites adversarially verified as real bugs (100%
  precision), hence shipped at medium confidence (visible in the
  default profile). Where SCA196 fires, SCA121 stays silent for the
  same function. Localized fix hint with before/after example (en/de/fr).

- **Light/dark theme for the standalone EXE.** Follows the Windows app
  theme by default (`[UI] Theme=system`), switchable in the hamburger
  menu under *Appearance* or via the INI key. The dark style ships
  embedded in the EXE — no VCL-style project option involved; a Windows
  theme switch takes effect immediately, no restart. Custom-painted
  surfaces (stat tiles, help panel) resolve their system colours against
  the active style, because Windows dark mode does *not* change the
  classic system colours.
- **Result-grid sorting in the standalone EXE.** Click a column header
  to sort, click again to reverse; the header shows an honest arrow.
  *Severity* sorts by rank (Error > Warning > Hint).
- **Analysable crash diagnostics** (`uCrashDiag`): caught crashes now
  report the exception class, the NT status code (distinguishing a real
  access violation from an exhausted stack) and a module-*relative*
  address that survives ASLR and resolves against a map file — the RTL
  message alone had neither.
- **`[Editor]` in `analyser.ini` — open findings in the editor of your
  choice.** `ExternalEditor` plus an `ExternalEditorArgs` template with
  `%file%`, `%line%`, `%col%` and `%dir%`. Templates for VS Code,
  Notepad++, Sublime Text, UltraEdit and IntelliJ/Rider ship commented
  out in the file. Standalone EXE only — the IDE plugin navigates through
  the ToolsAPI and never needed this.
  A value containing a space is quoted automatically unless the
  placeholder already sits inside quotes, and substitution runs in a
  single left-to-right pass so an inserted path that happens to look like
  a placeholder is not expanded a second time.
- **`.dfm` findings can open in the Delphi IDE** (`[Editor] DfmTarget`,
  default `ide`; also in the hamburger menu under **Open findings with**).
  Honest limitation: the IDE shows a `.dfm` in the form designer depending
  on how the extension is registered, and no route to a line number exists
  there — the built-in viewer stays available as `viewer` and is used
  automatically when no handler responds.
- **Keyboard triage in the standalone EXE**: <kbd>Enter</kbd> opens the
  finding, <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>S</kbd> inserts the
  `// noinspection` marker above the finding line and
  <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>F</kbd> applies the quick-fix —
  the IDE plugin's keys. Unlike the plugin (which edits the IDE buffer,
  undoable with Ctrl+Z) the EXE writes to the file itself, so both paths
  run through a byte-faithful line editor: encoding (UTF-8 with/without
  BOM, UTF-16, ANSI), line endings (CRLF/LF, even mixed) and a missing
  trailing newline are preserved exactly, enforced by a round-trip probe
  that refuses to write rather than damage a file. Multi-row selection
  is enabled (`goRangeSelect`) — "Sonar: send selected" now works on a
  range, as its code always intended.
- **Live language switch for most of the EXE**: the filter row, grid
  headers, analyse buttons and the hamburger menu now re-caption
  immediately on language change; the language menu shows native names
  (*Deutsch / English / Français*). Tiles and help panel still need a
  restart — the hint says so.
- **"Opening in Delphi IDE…"** status plus busy cursor before the
  IDE-open path blocks the UI for its ~1.6 s keystroke navigation.
- **The stat tiles are filters now, like the plugin's**: click *Errors*,
  *Warnings*, *Hints*, *Read errors*, *Cyclomatic*, *Bugs*, *Security* or
  *Duplicates* to filter the grid; *Quality* resets everything — in the
  EXE including the search box, so "show everything" really does.
- **SARIF in the export menu.** The engine always could; only the CLI
  used it. Same scope as Sonar/HTML: all findings, not the filtered view.
  Every export entry now states its scope in the caption ("JSON (filtered
  view)", "SARIF (all findings)") — previously only HTML did, which made
  the count difference between two exports of the same run inexplicable.
- **Baseline workflow in the standalone EXE** (plugin parity): *Write
  baseline from current scan…* saves the unfiltered findings as a
  baseline JSON — the same format the CLI (`--write-baseline`), the
  plugin and the HTML report exchange — and *Show only new findings*
  hides everything whose fingerprint is already in the configured
  baseline. Fail-open: a missing or broken baseline file hides nothing.
  The toggle now resolves the `.sca` default location on its own — no
  hand-written `[Baseline] File=` needed: enabling it without any
  baseline offers to write one to the `.sca` standard path (probed
  locations listed), *Write baseline* pre-fills that path, and the
  IDE plugin got the same hamburger toggle wired to the ACTIVE
  project/group; the plugin's silent mode (editor markers while
  typing) honours the `.sca` baseline too.
- **Right-click menu on the result grid**: Open, Copy AI prompt, Insert
  suppression marker, Apply quick fix — the discoverable form of the
  keyboard shortcuts.
- **The window remembers itself**: size, position, maximised state and
  column widths survive a restart (clamped to a visible monitor, so an
  unplugged second screen cannot restore the window out of sight). The
  detail column fills the remaining width like the plugin's does, and a
  minimum window size stops the filter row from collapsing.

### Changed

- **The embedded dark style is now "SCA VSDark"** — the VS Code *Dark
  Modern* palette (chrome `#181818`, content `#1F1F1F`, widgets
  `#252526`, inputs `#313131`, text `#CCCCCC`) instead of the stock
  *Windows10 Dark*, which literally sets `clBlack` for window, panel,
  grid, edit and menu. The style is generated reproducibly from the
  Redist original by `tools/make_scadark_style.py`; palette and file
  format are documented in `styles/README.md`.
- **`SCA040 DfmCrossFormCoupling` and `SCA042 DfmGodHandler` hardened
  after their revival** (see Fixed): SCA040 no longer counts local
  variables, parameters or fields that shadow a form name and anchors
  its findings in the `.pas` (demoted to low confidence until the
  next corpus round confirms precision); SCA042 stays silent when all
  bindings of a handler share one component class and one event type —
  a uniform, parameterised bundling is a pattern, not a god handler
  (corpus: −71 %).
- The status bar follows the plugin's three-channel scheme: the finding
  count is **persistent** in its own panel (it used to be wiped by the
  next event message), scan progress has its own, events keep the third.
- Splitter positions the user drags are respected — every window resize
  used to force the help panel back to one third and the before/after
  split back to 50/50 (this also fixes the IDE plugin).
- CSV/JSON export dialogs ask before overwriting and open in the scanned
  directory, matching HTML/Sonar; default file names are now
  `sca-findings.*` instead of the hard-coded German `analyse-befunde.*`.

### Fixed

- **Two DFM rules were dead in production.** `SCA040
  DfmCrossFormCoupling` and `SCA042 DfmGodHandler` ran *before* the
  event-binding repository was populated and had reported zero
  findings on every real scan since their introduction; both moved
  behind the binding build-up. Found by a systematic always-zero
  audit across all detectors.
- **`SCA032 DfmCircularDataSource` crashed on duplicate component
  names** (`TDictionary.Add` on the second `DataSource1`); edges are
  merged now.
- **`SCA034/SCA035 DfmRequiredField` reported a false-positive swarm
  on DataModules**: fields defined on a DataModule looked unbound from
  every form that uses them (single-file view); DataModule roots are
  skipped.
- **`SCA091 CaseStatementSize` counted string literals**: an embedded
  SQL `CASE … END` inside a Pascal string produced phantom branches.
  Literals are blanked before matching — and the same
  literal-stripping pass was rolled out to **15 further detectors**
  (comments/strings can no longer fake code constructs for them;
  self-scan alone dropped `ClassPerFile` from 519 to 27).
- **`SCA110–112 PerfHotspots` mis-attributed single-statement loops**:
  a `for … do stmt;` without `begin` swallowed the *following*
  statement into the loop body.
- **`SCA101 BeginEndRequired` missed the most common formatting**:
  a branch on the line *after* `if cond then` was invisible to the
  rule; continuation lines are checked now.
- **Every arrow-key step overwrote the system clipboard** (~30 writes/s
  on a held key — the VCL fires the click event on keyboard navigation
  too), and a clipboard locked by another process threw an unhandled
  exception mid-triage. Copying is debounced now (120 ms, one copy after
  the selection settles) and a locked clipboard is skipped silently.
- **Sorting or filtering hijacked the help panel and the clipboard**:
  the grid rebuild fired a click event for a row nobody clicked. The
  panel now deliberately follows the selection after a rebuild — without
  touching the clipboard.
- **In a read-only install folder (Program Files) every analyse click
  failed before the scan started** — the recent-paths INI lives next to
  the EXE and was written without a guard, ahead of the analysis call.
- **A second analyse click during a running scan nested a second run
  inside the first** (buttons stayed enabled while the progress callback
  pumps messages); the window close button was ignored during a scan.
  Analyse buttons are disabled during a run and the callback honours
  application shutdown.
- **Cancelling left a frozen "File 123 / 500" in the status bar and
  said nothing**; the 20,000-file limit silently discarded the scan with
  its message hidden *under* the progress bar. Cancel now reports
  "Analysis cancelled.", and the limit explains the way out (pick a
  subfolder, use the ignore list) in a dialog.
- **The progress bar covered the very texts the scan writes** (it
  spanned the whole status bar); it sits in a fixed area next to Cancel
  now, DPI-scaled.
- **Language mixing**: the filter-row captions were never translated
  (always English); the severity dropdown's hints and the DFM viewer's
  error were hard German (in any language). All routed through the
  catalogs now. The Sonar export dialog got its missing title and a
  translatable filter.
- **Theme switching at runtime was broken in all three paths** (found by
  review against the VCL source, all in unbuilt code): the second dark
  activation re-read an already-consumed resource stream and silently
  fell back to *light*; in a light-started session dark was never
  activatable (VCL style auto-discovery registered the embedded resource
  first, our load then failed forever on the duplicate name); in a
  dark-started session the first switch to light threw an unhandled
  `EDuplicateStyleException` at the user. Auto-discovery is now off and
  switching goes by style *name* through the VCL instance cache.
- **Sorting sorted by the wrong column.** The EXE passed its 5-column
  index straight to the sorter, which maps the 6-column plugin layout:
  clicking *Severity* sorted alphabetically by message text — with the
  arrow sitting on *Severity*. Rank sorting was unreachable. Indexes are
  mapped now.
- **Double-clicking the header row opened the selected finding** (1.2 s
  freeze plus keystrokes towards the IDE) instead of just toggling the
  sort twice.
- **An external editor with non-ASCII characters in its path was never
  startable.** The quick INI readers went through the Windows profile
  API, which reads the UTF-8 file as ANSI; the full settings loader read
  the same file correctly. Both now use the same BOM-aware path. Also:
  clicking the already-active *DFM findings* choice no longer rewrites
  the INI (which used to plant a bare, undocumented `[Editor]` section
  into pre-existing files), and a read-only `analyser.ini` now reports
  the failed save in the status bar instead of losing the choice
  silently.
- **SARIF export wrote raw control characters** — the same defect fixed
  for the Sonar export in v0.9.12: one finding message quoting e.g. `#0`
  from scanned code made the whole file unreadable for strict JSON
  parsers. Control characters without a short escape now leave as
  `\u00XX`.
- **Crash diagnostics attributed foreign addresses to the own module.**
  `uCrashDiag` checked only the lower image bound; an address in ntdll,
  a BPL or the heap was printed as "module-relative" to the own EXE —
  exactly the misattribution the unit was built to avoid. The upper
  bound (`SizeOfImage` from the own PE header) is checked now.
- **Double-click did nothing for every finding of a project scan.** When
  the scan target is a `.dproj`/`.groupproj`, the path was rebuilt against
  the *file* rather than its directory, producing `…\My.dproj\src\u.pas`
  and a "File not found" for every row.
- **The IDE navigation could type into the wrong window.** After
  `SetForegroundWindow` the return value went unchecked; Windows refuses
  the foreground switch regularly, and the routine then sent
  <kbd>Ctrl</kbd>+<kbd>G</kbd> and digits into whatever the user had in
  front of them. The foreground is now verified before any keystroke.
- **Line numbers were mistyped on non-QWERTY layouts.** `VkKeyScan(c) and
  $FF` discarded the shift-state byte, so on AZERTY the digits of the line
  number arrived as punctuation. Characters are now sent as Unicode,
  independent of the keyboard layout.
- **Failure to open was reported as success.** `ShellExecute`'s result was
  never checked at any of six call sites and it raises no exception, so the
  surrounding `try/except` was inert and the status bar claimed the file
  had been opened either way. The finding path now uses `ShellExecuteEx`
  with the program and its arguments passed separately — the shape our own
  `SCA163 CommandInjection` fix hint recommends — and reports what actually
  happened.
- **Rapid double-clicks stacked up.** The IDE path blocks the main thread
  for 1200 ms and then pumps messages, so queued clicks came back out and
  ran into each other. The handler is now re-entrancy guarded.
- **The Appearance menu was never translated.** Its captions reached the
  `.po` catalogues but not the embedded copy, so a German UI showed them in
  English.

---

## [v0.9.12] - 2026-08-04 - The panel keeps up

A small release: the file-scan panel in the IDE follows the mouse now, one
genuine detector defect found by reviewing our own week, and two guards that
close known traps. One rule may report slightly *more* than before — see
below, that is the fix working.

### Fixed

- **`SCA054 UnusedParameter` silently swallowed findings on single-line
  routines.** The source check added in v0.9.11 scans from the line of the
  `begin` token — but took the *whole* line. When the signature shares that
  line (`procedure TFoo.Bar(Sender: TObject); begin end;`), the parameter's
  own declaration counted as a use and the finding vanished. Well hidden:
  the defect only ever *suppressed*, so neither the self-scan nor the
  corpus anchor could see it, and every fixture had `begin` on its own
  line. The start line is now cut at the `begin` token (whole-word, so an
  identifier like `BeginUpdate` is not a cut point). **Expect `SCA054` to
  rise slightly on existing baselines — those are real findings coming
  back, exclusively on single-line routines.** **Measured: +4 on the
  reference corpus, every one verified in the source — single-line NIF
  handlers in TES5Edit whose parameters genuinely are not read. No other
  rule moved.**

- **The file-scan panel list was sluggish.** The renderer asked the IDE's
  theming service for style objects *per drawn cell* — a COM call, roughly
  300 per frame. Same disease the main grid had already fixed; the panel
  was the outlier. Now a one-slot cache, invalidated on theme change — and
  the theme-change handler order was corrected so the repaint happens
  *after* the cache reset, not before (that one was a review catch on the
  fix itself).

- **`WatchMode` can no longer stack workers.** `SpawnAnalyzer` spawned
  unconditionally; the generation counter only discards *late* results.
  When triggers arrive faster than an analysis finishes, the worker list
  grew — the unit header itself called it "endless loop possible" and made
  the guard a precondition for ever enabling watch by default. Now at most
  one watch worker runs; a trigger that arrives meanwhile re-arms the edit
  debounce timer instead of being dropped. Both debounce handlers clear
  their pending slot *before* spawning — the guard uses that slot as its
  retry seat, and clearing afterwards would have wiped the re-arm, making
  the guard silently ineffective.

- **Selecting a finding no longer writes the clipboard thirty times a
  second.** `GridSelectCell` ran a system-wide clipboard write, an
  `Application.ProcessMessages` and — when a quick-fix provider exists — a
  full source-file read on *every* selection change. The copy is debounced
  (120 ms, the resting row wins), and with it the `ProcessMessages` and its
  re-entrancy dance disappear entirely.

- **`package-release.ps1` hardened twice.** Zips of *other* versions
  survived every run and the documented `gh release create ... *.zip`
  follow-up would have attached them to the next release — the exact
  wrong-artifact class the script was built against; the output directory
  is now swept first. And the tag guard was dead code (PowerShell 5.1
  turns redirected native stderr into terminating errors before the
  `throw`); it now decides on the exit code.

### Changed

- **Mouse and wheel navigation in the file-scan panel follows the finding
  with a 50 ms settle delay.** Before, a click jumped instantly and the
  wheel moved the selection *without the editor following at all*. All
  three input paths now share one debounced navigator: mouse and wheel at
  50 ms, keyboard unchanged at 80 ms. Spinning the wheel fast collapses to
  a single editor jump on the resting row; re-clicking the same row
  re-centres the editor.

- **Self-scan baseline ratcheted** to the current state (0/654/2785,
  `ClassPerFile` 522) — justified fixture suppressions made the numbers
  better; tightening means future regressions surface earlier.

- **Custom-rule docs stop claiming target filters exist.** The `target`
  key is parsed and then ignored; the unit header said the opposite. The
  comments now state the truth (and the example file no longer dates the
  roadmap to "v0.9.0").

---

## [v0.9.11] - 2026-08-03 - Repairs

A fix release. Everything here is either a false positive that was proven on
the reference corpus, a regression that crept in with v0.9.10, or a version
number that had quietly stopped being true. No new rules, no new features.

On the 13,355-file reference corpus the finding count goes **560,964 →
560,073 (−891)**. Exactly two rules move — `SCA028` by −2 and `SCA054` by
−889 — and **nothing is added**: not one new finding, not one new message
shape. The other 139 rules are untouched.

### Fixed — findings that were wrong

- **`SCA028 DfmDeadEvent`: an event bound to `nil` is not a missing
  handler.** `OnCustomDrawItem = nil` says the opposite — the event is
  deliberately cleared. It was collected as a binding anyway and reported as
  a handler that could not be found. Filtered at the source, because four
  detectors share that event list and none of them wants a `nil` binding.
  Corpus reach counted beforehand: exactly one occurrence.

- **`SCA028`: an ancestor resolved from an ambiguous class name proves
  nothing.** `TfrmSplashScreen` inherits from `TfrmBase` — and skia4delphi
  carries `TfrmBase` *twice*, once under `Samples/Demo/VCL` and once under
  `.../FMX`. Only the VCL one declares the handler. The class index kept the
  first hit and dropped the rest silently, so the VCL form was bound against
  the FMX base and the handler merely *appeared* to be missing. The index now
  records which class names live in more than one unit, the binder marks
  bindings reached through such a name, and the rule stays quiet for them: a
  chain can run formally all the way up to a framework root and still be a
  stranger's.

  Not fixed, and documented as a known limit: a property whose name starts
  with `On` need not be an event. `TJvUIBQuery.OnError = etmStayIn` assigns an
  *enum*, not a method. In DFM text the two are indistinguishable — bare
  identifiers — and a spelling heuristic is out, because enum literals
  (`etmStayIn`) and IDE-generated handlers (`btnOkClick`) have exactly the
  same shape.

- **`SCA054 UnusedParameter` claimed absence it could not see.** The body it
  counts against is assembled from the name and type text of AST nodes, which
  is a *lossy* approximation of the source: the index expression on the left
  of an assignment and the arguments behind an `as` cast never appear in it.
  Both reproduced on the built analyser — `SystemPath[Kind] := 'x'` reported
  `Kind`, `(Obj as TOther).M(Index, 1)` reported `Index`. Before claiming a
  parameter is never read, the rule now asks the source, exactly as it has
  done since 2026-07-18 for routines the parser discards. Strings and
  comments are stripped first: a name in a comment is still not a use.

  Measured on the reference corpus: **14,859 → 13,970 findings (−889,
  −6.0 %)**, **zero added**, and apart from `SCA028` not one of the other 141
  rules moved. Eight drops were sampled and read in the source; every one is
  a genuine read in the two predicted shapes — `FList[Index] := Item` and
  `(FParent as TJvVisualId3v2).FTreeView.Width := Value`.

### Fixed — regressions from v0.9.10

- **Scrolling in the IDE plugin had become sluggish.** Three causes, all in
  the per-line paint path:

  *The gutter bracket asks for every line.* `PaintLine` checks
  `ShouldHighlight` first and leaves immediately for unmarked lines;
  `PaintGutter`, added in v0.9.10, calls the lookup directly. Every visible
  line began paying, marked or not.

  *Continuation lines are marks now.* Since findings span whole blocks, a
  `DuplicateBlock` over 21 lines turns one marked line into twenty-one — and
  marked lines run the expensive branch. In a duplicate-heavy file nearly
  every visible line carries the full cost.

  *Every scroll event forced a full repaint.* `EditorScrolled` invalidated all
  lines immediately, on top of the repaint the editor already performs. One
  mouse-wheel notch delivers several scroll events. The call itself is
  necessary — the editor *blits* moved lines, so the per-line callback never
  fires for them — but it is now coalesced through a 90 ms settle timer that
  fires once, when the movement stops.

  Path normalisation is memoised as well: it was three string allocations per
  call, several times per visible line.

- **Every cell of the findings grid was painted twice.** The renderer draws
  background, selection and text itself, for header and cells alike, but
  `DefaultDrawing` was never switched off — so the grid painted each cell in
  full first and the renderer painted over it. Roughly 300 redundant cell
  paints per frame at six columns and fifty rows. The panel grid had it right
  from the start; the main grid was the outlier.

### Fixed — version numbers that had stopped being true

- **The IDE plugin announced itself as v0.9.8** in its window title —
  hardcoded, two releases behind. The installer script carried the same stale
  number.
- **Six places carry the version**, not four: the two constants, the rule
  catalogue's `tool.version`, the two `.dproj` version blocks, the plugin
  title and the installer. They are now listed in the installer script so the
  next bump has them in one place.

### Changed

- **`SCA099 IfElseBegin` moved to the `style` profile.** The analysis
  behind the profile split named *seven* pure-convention rules; v0.9.10
  shipped with six. `IfElseBegin` — asymmetric `begin..end` between the
  `if` and the `else` branch — was left behind for no stated reason. It
  is the same shape as `BeginEndRequired`, which did move: a Code Smell
  at Hint severity about how the source is written, not about what it
  does. On the reference corpus it is **14,982 findings, 2.7 %**, so
  `default` now shows 4.9 % less than before. `style` covers exactly the
  seven; `strict` is unaffected and still means everything.

---

## [v0.9.10] - 2026-08-02 - One finding per block, a quieter default

Changes since **v0.9.9**, tagged the same day. No rule gained or lost a
finding: the reference corpus stays at **560,964** across all **141** rules,
verified rule by rule rather than on the total — a swap between two rules
would leave the sum untouched. Exactly one message shape changed, the
`SCA021` text below.

What moves is *how* findings are reported, not which ones. That is also why
this is a new version rather than a re-publish of v0.9.9: the `SCA021`
message is part of the SARIF fingerprint, so the same version number would
have meant two tools that hash differently.

### Breaking for baselines

- **`SCA021` message now names the real line range** (`Code block (lines
  513-533, 8 matched lines) appears 2x in file`). The old text counted
  normalised lines while the marked region counts source lines, so the two
  could never agree. The SARIF fingerprint hashes the message, so every
  `SCA021` finding gets a new fingerprint and shows up once as *new* in
  existing baselines — re-write the baseline after updating. No other rule
  affected, finding count unchanged.
- **`default` profile no longer includes six pure-convention rules**
  (`PublicMemberWithoutDoc`, `NilComparison`, `BeginEndRequired`,
  `WithStatement`, `ClassPerFile`, `DfmHardcodedCaption`) — together 45.4 %
  of all findings on the reference corpus. They moved to the new `style`
  profile; `strict` still means everything.

### Performance

- **Suppression skips files without a single marker.** Building the
  suppression map ran the comment state machine over every line of every
  file, including the overwhelming majority that contain no
  `// noinspection` at all. A cheap allocation-free scan for the token now
  decides first. Findings are unaffected by construction — a file with no
  marker has nothing to suppress.

  Measured on the reference corpus (13,355 files, quiet machine, warm
  cache): **4m14s / 4m20s** with the fast path against **4m32s** without —
  roughly **−5 %** wall clock. Read that as a direction, not as a figure:
  the two runs with the fast path differ by 5.6s between themselves, and
  only a single run of the previous build is available for comparison, so
  its own spread is unknown. Two things argue the effect is real rather
  than noise: the gap is about 2.7× the observed run-to-run spread, and the
  newer build also writes 222 KB *more* SARIF (the longer `SCA021`
  message), which pushes the other way. Note also that this corpus contains
  no suppression markers at all, so every file takes the fast path — this
  is the best case, not a typical one. Both runs produced byte-identical
  reports.

- **`--parallel` now says when it declined.** Per-file parallel scanning is
  opt-in and falls back to serial whenever the run cannot be made
  deterministic — auto-discovery, custom rules, `--time-detectors`. That
  fallback was *silent*, and it cost a measurement: a corpus run was
  started with `--parallel`, `AutoDiscoverClasses=1` was set in
  `analyser.ini`, the scan went serial, and nothing said so. It only came
  out because the parallel path does not write the per-file lines that
  turned up in the scan log. The reason now goes to stderr and into the
  log. No change to results or to when the fallback happens — only to
  whether you are told. `--parallel` is also documented in both READMEs
  for the first time, including the honest figure: **~3 %** on the
  reference corpus, because the expensive phase (parse + index build) is
  serial and runs *before* the parallel main loop.

### Editor

- **The bracket is drawn in the gutter too**, not only in the code area, so
  a finding's extent stays visible when the marked lines scroll behind
  other decorations. This is the one part of the feature that touches new
  IDE surface: the plugin previously registered no gutter painting at all.

### Fixed

- **A suppression marker inside a finding's range now counts.** A finding
  anchored at line *L* only ever matched markers registered for exactly
  *L*. Once `DuplicateBlock` began covering a line *range*, that was too
  narrow in both directions: a marker the user had placed in the middle of
  the block no longer silenced the finding, and `SCA165 UnusedSuppression`
  then reported that very marker as pointless. Both the match and the
  consumed-check now span the finding's range. Single-line findings run the
  loop exactly once, so the ordinary case stays a single dictionary lookup.

- **The standalone app's search box filtered on every keystroke.** Each
  character triggered a full pass over all findings — the same defect the
  rule-filter combo had, only older and never noticed because it predates
  the large corpora. Now debounced, like the plugin.

- **An empty result could look like a clean scan.** Files matching a test
  fixture pattern (`*Demo.pas`, `*Test*.pas`, …) are filtered out by
  default, so a first-time user analysing a file that happens to be named
  `Demo.pas` got “0 findings” and no hint why. The filter now names the
  files it dropped and says how to keep them
  (`--show-test-fixtures`). Found by walking the download-to-first-scan
  path as a new user, which had never actually been done.

- **The bracket in the gutter grew in the wrong direction.** The cap is
  drawn from its rectangle's left edge rightwards — correct in the code
  area, where the stripe is left-aligned, but the gutter bar is
  right-aligned and two pixels wide. The cap therefore covered exactly the
  two pixels already filled in the same colour and put its remaining seven
  outside the assigned rectangle, so the gutter showed a bare bar and never
  a bracket. The cap now gets its own rectangle drawn leftwards from the
  right edge, and `DrawSpanCap` clamps horizontally as well as vertically —
  the gutter is narrower than the cap as soon as line numbers are turned
  off.

- **The `default` profile was complete again in the fallback path.** When
  `rules/sca-rules.json` cannot be read, the catalogue falls back to a
  second, code-level profile list. That list still granted `default` every
  rule, so a user without the rules file would have silently got the old,
  noisier default — the exact thing the profile change set out to prevent.
  `default` is now built there as *all kinds minus `style`*, so a newly
  added rule cannot fall through.

---

## [v0.9.9] - 2026-08-02 - Fewer false positives, two project-scope rules

Changes since **v0.9.8**. Rule roster grows from 166 to **195 rules**
(`SCA001`–`SCA195`), +29; DFM rules 22 → **23**. Beyond the new detectors, this
cycle was dominated by a measured false-positive campaign: on the
12.8k-file reference corpus the finding count dropped **645,622 → 560,964
(−84,658, −13.1 %)**. The error tier now stands at **2,134** findings plus
one unreadable file.

> An earlier draft of this entry put the error tier at 2,172 and compared it
> against 2,255 for v0.9.8. Both figures were counted by matching `"level"`
> across the whole SARIF — but the `tool.driver.rules` block carries one
> `level` per *rule definition*, and the catalogue holds exactly 37 rules
> whose default severity is Error. 2,135 results + 37 definitions = 2,172.
> The v0.9.8 figure was measured the same inflated way; its corpus baseline
> is no longer on disk, so it cannot be restated on the correct basis and is
> dropped here rather than silently re-anchored. The total finding counts
> were never affected — those were counted per result, not per level.

### Performance

- **`SCA166 UninitVar` was quadratic in file size.** It ran a full-file
  scan per candidate variable; the comment at the call site claimed it ran
  only for emit candidates, which was not true — the deciding branches sit
  below it. Moved into the two emit branches. Share of detector CPU
  **36.9 % → 7.9 %**, 8.43 → 0.73 ms per file, rank 1 → 3; **−86 %**
  attributable to the fix after factoring out machine variance against
  unchanged detectors. Findings byte-identical, all 141 rules unchanged.

### Searchable rule filter

- **The rule filter combo is searchable.** It holds roughly 200 entries —
  every rule as `SCAxxx  KindName`. Typing `sqlinj` finds `SCA003`:
  characters must occur in order but need not be adjacent; word starts and
  CamelCase boundaries rank first. The filter is applied when the list
  closes, not while arrowing through it, so a single keypress no longer
  costs a full pass over all findings. Standalone app and IDE plugin.
- Known behaviour, not a defect: Windows hides the mouse pointer while you
  type in a text field and restores it on the next mouse movement
  (*Pointer Options → Hide pointer while typing*).

### Findings can span more than one line

A `DuplicateBlock` is a **block**; it was reported as a single line, and the
reader had to guess where the duplication ended. Findings now carry a line
range, and the IDE editor marks every line of it.

- **`SCA021 DuplicateBlock`: one finding per duplicated block.** The sliding
  window walks the block line by line, so a K-line duplication used to
  produce K−7 findings stacked on top of each other — the guard that was
  supposed to prevent this keyed on the start line, which is unique per
  window, so it could never fire. One class declaration in the reference
  corpus carried **18 hints on top of each other**. Windows of the *same*
  duplication are now merged into one finding covering the whole block:
  corpus **41,306 → 9,148 (−32,158)**, and no other rule moved.

  "Same duplication" is decided by the *occurrence signature* — the
  distances between the copies — not by line overlap. Two different
  duplications whose first occurrences happen to overlap stay two findings;
  merging them geometrically would have hidden one group's partner site
  entirely and mis-reported the multiplicity (a 10×-duplicated block
  announced as "2x").

- **SARIF `region.endLine`** is written for multi-line findings. Absent
  means single-line, as the format specifies.

- **The IDE editor marks the whole range,** with a bracket: a cap on the
  first line of the block and one on the last. Continuation lines carry the
  stripe so the extent is visible, but they are **not findings**: no badge,
  no hover overlay, no entry in any list. The finding stays anchored at its
  first line, and the findings list still shows one entry.
- **Overlapping duplications draw one bracket, not several.** About a
  quarter of all `SCA021` findings overlap another one; without that rule
  the stripes stack into a column from which no line can be attributed to
  a finding. The suppressed ones keep their anchor and info bar — nothing
  disappears from the report.

#### Migration note

If you silenced one of these cascades with **line-bound**
`// noinspection DuplicateBlock` comments, the markers on the swallowed
lines are no longer consumed and will be reported as
`SCA165 UnusedSuppression`. One marker on the block's first line replaces
them. File-wide `// noinspection-file` markers are unaffected.

> **Fixed in v0.9.10** — a marker anywhere inside a finding's range now
> both silences it and counts as consumed, so this migration step is no
> longer needed. It is left standing here because it is what v0.9.9 does.

### Added

- **Rule pages document what a rule deliberately does *not* report.** The
  rule catalogue gained an optional `exceptions` field (case, mechanism,
  optional snippet); `tools/gen-rules-docs.py` renders it as a
  *“Not reported (by design)”* section on every affected rule page. Without
  it a user cannot tell *“the rule found nothing”* from *“the rule has a
  gate for exactly this case”* — the most common question after a
  false-positive campaign. Deliberate false negatives are documented too,
  so nobody later hunts a bug that is a design decision.

- **`gen-rules-docs.py` validates the catalogue against its own schema**
  when `jsonschema` is installed (`--no-schema-check` opts out). The schema
  had never been executed; the first run found a `shortDescription` of 208
  characters against a documented limit of 200.

- **`SCA194` / `SCA195` — project-membership rules.** Both need a view no
  single-file check has: they compare the set of files on disk and the set
  of units actually reached by `uses` against what the project file lists,
  so they only run in a project or project-group scan.
  - `SCA194 NotIncludedInProject` — a `.pas`/`.dfm` lies in the project
    tree but no `.dproj`/`.groupproj` references it. Typically a leftover
    that is still edited, still greps as a hit, and is never compiled.
  - `SCA195 UsedButNotInProject` — the mirror case, and the more dangerous
    one: the unit *is* pulled in via `uses` and compiles through the search
    path, but is missing from the project file. It builds on the machine
    where the path happens to be set and fails everywhere else. Resolution
    follows `uses` transitively from the `.dpr` root and walks **both**
    branches of an `{$IFDEF}` — a unit used only in the inactive branch is
    still a project member.

- **`SCA185`–`SCA192` — file-encoding & Unicode-safety detector family**
  (`uSourceEncoding.pas`): whole-file, byte-level checks that read the raw
  bytes (the encoding truth the text cache discards after decoding).
  - `SCA185 SourceUtf8NoBom` — UTF-8 without BOM + non-ASCII → the Delphi
    compiler reads it as ANSI (`GetACP`) → runtime mojibake. Confidence is
    set by lexing the file (`TLexer`): non-ASCII in a **string literal or
    code** → `fcMedium` (real mojibake risk, shown by default); non-ASCII
    **only in comments** → `fcLow` (the compiler discards comments; opt-in).
  - `SCA186 SourceInvalidUtf8` — malformed UTF-8 under a UTF-8 BOM
    (overlong / surrogate / out-of-range), via a strict RFC-3629 validator.
  - `SCA187 SourceControlChar` — NUL / disallowed control byte.
  - `SCA188 SourceBidiOverride` — **Trojan Source** (CVE-2021-42574,
    CWE-1007): bidirectional override/isolate control chars that make code
    read differently than it compiles. Fires even in clean UTF-8+BOM.
  - `SCA189 SourceAnsiNonAscii` — 8-bit/ANSI source (no BOM, not valid
    UTF-8) → code-page-dependent, non-portable.
  - `SCA190 SourceUtf16` — UTF-16 source (compiles, tooling friction).
  - `SCA191 SourceUtf32` — UTF-32/UCS-4 source → compiler fatal error
    `F2438`.
  - `SCA192 SourceInvisibleChar` — invisible / zero-width chars
    (U+200B–200D, U+2060, mid-file U+FEFF; CWE-1007).
  - `SCA193 SourceNonAsciiIdentifier` — non-ASCII character in an
    identifier: the homoglyph / confusable vector of Trojan Source
    (CVE-2021-42694, CWE-1007) — e.g. a Cyrillic U+043E that looks like
    Latin `o`. Detected via `TLexer` (identifier/code tokens), only when
    the file has non-ASCII at all (no lexing cost for pure-ASCII files);
    fires even in correctly-encoded UTF-8+BOM. `fcMedium` (a legitimate
    Unicode identifier is possible).
  - Ships with 32 unit tests (`uTestSourceEncoding.pas`) and German help
    texts (`de.po`). Scope: `.pas/.dpr/.dpk/.inc`.
- **IDE plugin — baseline filter ("show only new findings")**: point the
  editor at a baseline JSON and the grid + editor markers hide the legacy
  backlog, showing only findings new since the baseline. Uses the shared
  `TBaseline` fingerprint, so the file is interchangeable with the CLI
  `--write-baseline` and the HTML-export baseline. New dock-menu action
  *"Write baseline from current scan"* and a *Baseline* section in
  Tools ▸ Options. Non-destructive (the full finding set + export are
  unaffected); fail-open (a missing/broken baseline hides nothing).

- **SCA184 `DfmComponentUnused`** — new DFM detector: flags a component
  declared in a `.dfm` that is never referenced — not in the form's own
  code, not from another unit via the global form variable
  (`Form1.Comp`, resolved through the repo-wide symbol index), and not by
  another component inside the DFM (`DataSource=`, `Action=`, …). Likely
  dead after refactoring. Ships at `fcLow` (opt-in via
  `--min-confidence low`); emits nothing without the cross-unit symbol
  index. Persistent `TField`s, embedded frames and `FindComponent`-by-name
  units are deliberately skipped in v1.
- **CLI stdout/stderr redirect support** — `sca.exe … > log.txt` and
  pipes now land in the redirect target (previously bound to `CONOUT$`,
  which ignored redirects). Works even without a parent console (CI
  runners / mintty, where output was previously lost). The redirect path
  gets a 64 KB output buffer.

### Changed

- **False-positive campaign — 84,658 fewer findings on the reference
  corpus (−13.1 %), no true positive lost.** Seven increments, each built on
  its own branch, measured in a single corpus run against the previous
  baseline, and released only after sampling the dropped findings. Every
  increment held the same anchors: **zero added findings**, no rule outside
  the increment moved, and the error tier only moved where intended.

  | Increment | Rules | Effect |
  |---|---|---|
  | Ownership transfer via `out` parameters | `SCA001` | −493 |
  | Hint-tier gates | `SCA155`, `SCA073`, `SCA147`, `SCA080` | −17,577 |
  | Declaration & reference visibility | `SCA119`, `SCA132`, `SCA020`, `SCA053`, `SCA164` | −10,531 |
  | Duplicate reporting & interface contracts | `SCA106`, `SCA070`, `SCA054`, `SCA001` | −20,455 |
  | Parser: attributes in parameter position | `SCA054`, `SCA013` | −41 |
  | Declaration boilerplate | `SCA021` | −3,403 |
  | One finding per duplicated block | `SCA021` | −32,158 |

  The recurring theme is that a rule must not fire where the language
  *forces* the repetition or where the call simply is not visible by name:
  message handlers and interface implementations are dispatched without
  ever naming the method, `Exit` inside a loop is an early return rather
  than a no-op, `Break` is never a no-op, published-property lists and
  parameter lists cannot be extracted into a method, and a declaration plus
  its implementation is one identifier, not two findings.

- **`SCA080 RedundantJump` no longer scans `Break`.** Unlike `Continue`,
  `Break` at the end of a loop body suppresses the remaining iterations —
  following the old hint turned search loops into full scans and
  `while True` loops into infinite ones. `Break` is only redundant in
  `repeat … Break; until True`, which does not occur anywhere in the
  reference corpus.

- **`SCA106 MethodName` reports once per method.** The declaration and its
  implementation are one identifier and one rename; they were reported
  twice. Findings for equally-named methods in *different* classes are
  unaffected.

- **`SCA020 EmptyMethod` accepts an intent comment.** The rule's own advice
  is to make the intent explicit by assert, exception *or comment* — a body
  that carries one has already followed it. Compiler directives and
  commented-out code do not count.

- **Performance** — full-profile corpus scan ~263 s → **~230 s** (12.8k
  files) via a per-scan strip cache (~17 detectors share one strip
  result), a single-pass token pre-filter (was ~82 full-text scans per
  file), stat-per-scan-generation in the file-text cache, and
  loop-invariant hoists in the heaviest detectors (`uCanBeClassMethod`
  O(n²)→set lookup, `uUninitVar`, `uVisibilityCheck`,
  `uSymbolReferenceIndex`, `uUseAfterFree`). The **SARIF export now
  streams** per finding instead of building the whole JSON DOM in memory.
  IDE-plugin hot paths trimmed (scroll-invalidate, search filter, sort).
- **False-positive reduction (real-world corpus, bugs-only profile)** —
  `SCA003` (SQL injection), `SCA008` (nil-deref), `SCA001` (leak),
  `SCA004` (hard-coded secret) hardened: **−29 % false positives** on the
  reference corpus with **all 37 verified true-positives preserved**.
  Includes an ORM / SQL-builder gate (mORMot `:(%):` inline-binding,
  quoting-helper calls, ORM meta-paths).
- **SCA166 `UninitVar`** — a method call on a record-typed local
  (`match.Prepare(…)`; `Self` is passed as `var`) now counts as
  initialisation, fixing a systematic false positive on mORMot
  record-with-methods. Records are distinguished from classes via the AST,
  so a genuine "method on an uninitialised class instance" bug still flags.

### Fixed

- **Regex cache grew without bound in the IDE plugin.** The per-thread
  cache key assumed pool threads are reused — true for the CLI, but the
  IDE's bulk-scan worker starts fresh threads per scan whose ids never
  return, while their compiled regex instances stayed. Now capped.

- **Size guard for an external `.po` came too late.** The file was fully
  loaded into memory and only then compared against the limit; the guard
  existed but never took effect. The file size now decides before a single
  byte is copied.

- **Embedded translation was never selected for case-differing language
  codes.** The generated dispatcher compared case-sensitively while the
  caller normalises, so a `PT.po` would have been silently ignored —
  falling back to English without any error.

- **`i18n_extract.py` harvested constants from expressions.** Any
  `NAME = <literal>` counted, including mid-expression comparisons, so
  `Found := Ext = '.pas';` produced a “constant” named `Ext`. A real
  declaration opens its line; a comparison does not.

- **Attributes in parameter position produced phantom parameters.** For
  `procedure Post(const [MVCFromBody] P: TPerson)` the parser emitted a
  second `nkParam` named after the attribute. Sixteen rules read `nkParam`;
  the visible effect was `SCA054` reporting the attribute name as an unused
  parameter, and `SCA013` both over- and under-counting parameters.

- **Self-scan is free of error-tier findings.** All thirteen were either
  test fixtures that carry the anti-pattern on purpose or false positives
  of the tool's own rules; both are now suppressed with a stated reason.

- **Mojibake in own German user-facing strings** (surfaced by the new
  `SCA185`): two engine units were saved as UTF-8 **without** a BOM and held
  non-ASCII string literals, so the compiler read them as ANSI → garbled
  output. Added a UTF-8 BOM to fix the rendered text:
  `uSQLInjectionScore.pas` (the "Rückgabewert der Funktion…" fix suggestion)
  and `uStaticAnalyzer2.pas` (the "Datei zu groß … Analyse übersprungen"
  file-too-large message). Also BOM-stamped 10 test fixtures that carried
  non-ASCII test data without a BOM.
- **UnusedSuppression** — stale `// noinspection` markers in
  finding-free files are now reported; the finding points at the `.pas`
  host line for DFM findings; a file-wide + per-line marker covering the
  same finding no longer mis-reports the per-line marker. An unreadable
  marker-host file now emits a diagnostic finding instead of silently
  disabling all suppressions for that file.
- **Parser** — a `type` / `const` / `var` section between top-level
  routine implementations no longer truncates the rest of the file's AST;
  `{$IFDEF}`-nested method bodies (Synapse `blcksock`-style) no longer
  absorb the following methods.
- **Build hygiene** — Engine source search-paths removed from the package
  consumers (`SCA.SharedUI` / IDE plugin), main `.res` files untracked
  (regenerated per build), sample fixtures dropped from the shipped
  standalone EXE; Delphi 11 compilation restored (`uCompatSet` shim).

## [v0.9.8] - 2026-06-10 - Phase 1-4 + Hardening v3 + v4 + FP-Reduction Sprint (since v0.9.7)

### 2026-06-09 — FP-Reduction + Diagnostics Pass

**Detector False-Positive reduction** on self-scan (67 → 12 FPs, −82%):
- **SCA017 DebugOutput** — String-literal contents (`'WriteLn(...)'` in UI-hint
  templates) no longer flagged as real debug calls. New `IsInsideStringLiteral`
  helper counts bare apostrophes before the match position.
- **SCA070 CommentedOutCode** — Inline-doc comments after code and doc-block
  starts (look-ahead on next line) skipped. Reduced from 45 to 9 FPs (−80%).
- **SCA019 TodoComment** — Detector-source mentions like `'TODO'` in quotes,
  `TODO / FIXME / HACK / XXX` slash-lists and `(TODO)` in parens skipped.
  Reduced from 13 to 3 FPs (−77%); remaining 3 are real backlog markers.
- **SCA005 FormatMismatch** — empty-resolved const identifiers
  (`Format(IDENT, [arg])` where IDENT resolves to empty) no longer reported
  as `0 placeholders, 1 arguments`.

**Bug fixes:**
- **FieldLeak detector** — `FreeAndNil(Self.Field)` with `Self.`-qualifier
  was not recognised as freeing, producing false leak reports in code that
  consistently uses Self-qualified field access.
- **TEMP DIAG audit-block** in `uUseAfterFree.pas` (73-line CFG-dump that
  wrote `sca-cfg-debug.log`) removed — leftover from hardening sprint.

**Diagnostics:**
- **scan.log Phase-Tracking** — outer handler in `ParseLeaks` now records
  the last successful phase + current file before any uncaught exception
  is re-raised. Replaces "Analyseabbruch: ..." mystery findings with a clear
  trail (`=== ABBRUCH: EXClass: msg / letzte Phase: X / aktuelles File: Y`).
- **scan.log skip-log** — files/directories skipped by ignore-list,
  default-exclude (`__history`/`Win32`) or symlink detection now appear in
  `StaticCodeAnalyser_scan.log` with a clear reason. Previously a black box.

**Configuration:**
- `[Detectors] MaxLineLength=N` (default 120) for `uTooLongLine`.
- `[Detectors] MaxCaseBranches=N` (default 10) for `uCaseStatementSize`.

### 2026-06-08 — DFM Resource-Wrapper Support + Stack-Hardening v3/v4

**Critical:**
- **DFM Resource-Wrapper format `$FF $0A $00`** is now supported. GExperts
  and JVCL ship binary DFMs in the `$FF $0A $00 [ResName] [pad] TPF0 ...`
  wrapper layout — previously these were silently misinterpreted as text
  and produced 0 DFM-findings. GExperts: 0 → 1.084 DFM-findings;
  JVCL DFM-findings doubled on real-world scans.
- **AST `Destroy` reentrancy double-free** (Hardening v4 follow-up): the
  iterative `TAstNode.Destroy` collected descendants into `AllDesc` and
  freed them, but each `Cur.Free` re-entered the same destructor and
  re-freed nodes via its own DFS. Manifested as `EInvalidPointer` in
  `gAstFileCache.Evict` after the first file in a scan.

**Performance:**
- **`uFixHint` Memoize-Cache** keyed by `(Kind, Severity)` — the IDE plugin's
  `HighlightAllFindingsInFile` called `FixHint()` per finding, allocating
  ~3 KB of UI-hint strings each. On a 165k-finding scan that crossed the
  Win32 user-space limit and produced `EOutOfMemory`. Cache has ≤166 unique
  slots; downstream `Entries[]`-arrays share ref-counted strings.

**Detector UI Hints:**
- Added `fkUninitVar` and `fkUnusedSuppression` to `uFixHint` (Before/After
  code snippets). 165/165 kinds now have UI-hint coverage.



13 commits since v0.9.7 (released 2026-06-01). Phase 1 of
[Konzept_ScannerQualitaet.md](Konzept_ScannerQualitaet.md) is complete
(6/6 quick-wins); Phase 4 has begun with the A.3-Minimal cross-unit
visibility check. A subsequent multi-persona review hardened the code
on Security, Performance, and API dimensions.

Full release notes: [docs/releases/v0.9.8.md](docs/releases/v0.9.8.md)
([deutsch](docs/releases/v0.9.8_de.md)).

### Added

- **`--time-detectors` CLI flag** — emits a Markdown table with per-detector
  cumulative wall-time and call count after a scan. Drives data-based
  optimisation choices.
- **Test-fixture auto-detection** (`uDetectorUtils.IsTestFixturePath`) —
  filters findings from `uTest*.pas` / `*Sample.pas` / `*Demo.pas`,
  test/samples/demos/resources directories and known fixture files. Auto-on
  for `default` and `selftest-quiet` profiles, off for `strict`. Manual
  overrides via `--hide-test-fixtures` / `--show-test-fixtures`.
- **SCA165 `UnusedSuppression`** — emits a hint when a `// noinspection X`
  marker did not suppress any finding (detector improved → marker obsolete).
- **SCA166 `UninitVar` (MVP)** — local variable read before being
  assigned. Conservative single-method-scope detector
  ([`uUninitVar.pas`](SCA.Engine/sources/Detectors/uUninitVar.pas))
  with three-class call model (READ_ALLOWLIST: `WriteLn`/`Length`/…,
  WRITE_ALLOWLIST: `ReadLn`/`FillChar`/…, UNKNOWN-calls: pessimistic-
  write). Method-boundary scan + `_`-prefix + managed-type skip + hard
  caps against pathological methods. Full path-sensitivity (if-else
  sibling-write, CFG, symbol table) deferred to Phase 2-4 per
  [`Konzept_SCA166_UninitVar.md`](Konzept_SCA166_UninitVar.md).
  Closes the long-standing DETECTORS.md slot #16 (UninitVar) with a
  conservative MVP; slot stays `🟡 partial` until full flow analysis.
- **Golden-corpus regression tests** in `tests/golden-corpus/fp-reproducers/`
  — 5 historical FP reproducer `.pas` files (one per Round-1..13 fix) plus
  `expected.json` and `tools/check-golden-corpus.ps1` PowerShell runner.
- **SARIF `partialFingerprints.contextHash/v1`** — SHA256 over a
  whitespace-normalised ±3-line snippet around the finding. Stable against
  re-indent, line drift and method renames (when method header lies outside
  the radius). Survives baseline diffs that the legacy fingerprint would
  miss.
- **Baseline matches via `contextHash` OR legacy fingerprint** — old
  baselines remain valid; new ones survive small refactors.
- **`KindDefaultConfidence` in `uSCAConsts`** — ~35 heuristic /
  metric-based / DFM-schema kinds tagged as `fcMedium`. `TLeakFinding.SetKind`
  applies the default automatically. `--min-confidence high` now blends
  out heuristic findings without losing structural-bug coverage.
  Audit table: [docs/ConfidenceAudit.md](docs/ConfidenceAudit.md).
- **`TLeakFinding.SetKind(K, AConfidence)`** overload — explicit
  Confidence-passing instead of the order-fragile post-`SetKind` overwrite.
  `uCommandInjection` migrated.
- **A.3-Minimal: `gSymbolRefIndex` reactivated** for `fkUnusedPublicMember`
  (SCA052) — cross-unit caller lookup, no more dead-public-API false
  positives for symbols actually called via `obj.Method(args)`. Audit shows
  44% of known cross-unit methods now correctly recognised; remaining 56%
  documented as A.3+ follow-up (nkRef + class-function-call index limits).

### Changed

- **`gFileTextCache` lives through the post-scan phase** — Suppression,
  ContextHash and SARIF/baseline output reuse the warm cache instead of
  re-reading every file. Eliminates ~191k redundant `LoadFromFile` +
  UTF-8 validations per real-world scan.
- **`TFileTextCache` is now mtime-aware** — stale cache entries are
  invalidated on next `GetLines` if the file's `FileAge` no longer matches.
- **`uSuppression.BuildMap` / `BuildMarkers` use `AcquireLines`** — second
  call for the same file is a cache hit instead of a duplicate read.
- **`uSuppression.ApplyToFindings` split** into three methods
  (`ApplyToFindings` orchestrator + `RemoveSuppressedFindings` +
  `EmitUnusedSuppressionFindings`).
- **`uVisibilityCheck`** caches `AllUnitMethods` (`FindAll(nkMethod)`)
  and memoises `DescendantsOf(ClassLow)` once per `AnalyzeUnit` — previously
  re-walked the tree per public member, costing up to `O(members × methods)`.
- **`uFindingFingerprint.Normalize`** extracted inner whitespace-collapse
  into `CollapseWhitespace(Line, Sb)` and reuses a single TStringBuilder
  per call instead of allocating per snippet line.
- **`TryLoadLinesWithFallback` in `uFileTextCache`** — single source of
  truth for the 3-step encoding fallback (default → UTF-8 → Unicode).
  Removed duplicate in `uSuppression`.

### Security

- **`// noinspection All` excludes security-critical kinds**
  (`fkHardcodedSecret`, `fkSQLInjection`, `fkCommandInjection`,
  `fkDfmHardcodedDbCreds`, `fkDfmSqlFromUserInput`,
  `fkInsecureCryptoAlgorithm`, `fkUnusedSuppression`). These must be
  named explicitly. Prevents a single `All` marker from hiding a backdoor.
- **`ParseMarkerLine` routes through `TDetectorUtils.ScanCodeLine`** —
  string-/block-comment-context-aware. A marker inside a string literal
  (`Log('// noinspection All // ' + Payload);`) is no longer treated as
  active. Scan state is carried per file across lines.
- **`IsTestFixturePath` repo-root-anchored** — optional `BaseDir` parameter
  matches path components only inside the scan root. Stops external paths
  like `D:\projects\company-tests\src\auth.pas` from being silently filtered.
- **Baseline JSON hardened** with `MAX_BASELINE_ENTRIES = 1_000_000`
  and `MAX_FINGERPRINT_LEN = 256`. Mitigates OOM attacks via tampered
  baseline files. Warning to `ErrOutput` on truncation.

### Fixed

- **`gDetectorTimings` moved to INTERFACE section** of `uStaticAnalyzer2`
  — was unit-private so `uConsoleRunner` could not see it; `--time-detectors`
  built but never wrote the report.
- **Latent memory leak in `gAstFileCache` + `gFileTextCache`** on repeated
  scans (IDE plugin re-runs) — caches are now freed before re-create.
- **`uVisibilityCheck` `OwnUnit` path mismatch** — `ExtractFileName`
  compared "name.pas" against full-path entries in `gSymbolRefIndex`, so
  self-references were always counted as external. Now passes full path.
- **`Baseline.Apply` skips `ContextHash` computation** when the loaded
  baseline contains no `contextHash` entries (legacy file). Saves
  ~191k SHA256 + file-read operations on legacy baselines.

### Documentation

- New: [`Konzept_ScannerQualitaet.md`](Konzept_ScannerQualitaet.md) —
  4-axis quality roadmap (Precision / Recall / Tooling / Architecture)
  with 4 prioritised phases.
- New: [`docs/ConfidenceAudit.md`](docs/ConfidenceAudit.md) — per-kind
  default-confidence table with justifications.
- New: [`tests/golden-corpus/README.md`](tests/golden-corpus/README.md) —
  FP-regression-test workflow + how to add new reproducers.
- Updated: A.3 entry in `Konzept_ScannerQualitaet.md` marks the minimal
  step done and documents the 3 index limitations (nkRef, class-function-
  call, bare-call) as A.3+ follow-up.

---

## [v0.9.7] - 2026-06-01 - Regex cache round 11

### Changed

- **Module-level regex cache extended to seven more detectors** (round 11 of
  the performance work). Patterns were recompiled per file; they are now
  compiled once per process.

### Fixed

- **`uFloatEquality` failed to compile after the round-11 change** — the
  inserted `var` broke an open `const` block (E2029/E2003).
- **Four missing finding-kind filters** added, closing the gap found by the
  filter audit.

---

## [v0.9.6] - 2026-05-31 - Self-test FP reduction + `selftest-quiet`

The tool was pointed at its own source and the results were triaged in
seven rounds. This release is almost entirely about not reporting things
that are not defects.

### Added

- **`selftest-quiet` profile and profile negation syntax.** A profile entry
  may now start with `!` to remove a kind from an inherited set, which is
  what makes a "everything except the eleven style rules" profile
  expressible at all.

### Fixed

- `SCA001 MemoryLeak` recognises the acquire/release pool pattern (~60).
- `SCA078` accepts field, indexed and dereferenced `Result` assignments; a
  plain `Result :=` was the only form understood before.
- `uExceptionTooGeneral` skips a legitimate top-level handler (~40).
- `uMethodName` skips DFM event handlers — the name is dictated by the form
  designer, not the developer (~8).
- `uTypeName` skips exception classes, whose `E`-prefix is the convention
  the rule was flagging (~4).
- `uLockWithoutTryFinally` no longer treats method headers and cache calls
  as lock acquisitions.
- `uUnusedLocal` handles nested procedures; `FreeWithoutNil` handles locals.

### Changed

- Regex patterns moved to a module-level cache instead of being recompiled
  for every file.

---

## [v0.9.5] - 2026-05-31 - `SCA162`–`SCA164`, confidence model, branding

Version **0.9.4 was skipped** — there is no such tag or release; the
version went straight from 0.9.3 to 0.9.5.

### Added

- **`SCA162 InsecureCryptoAlgorithm`**, **`SCA163 CommandInjection`**,
  **`SCA164 UnusedRoutine`**.
- **Finding confidence model** plus a central comment/string scanner, so
  detectors stop re-implementing "is this position inside a literal".
- **IDE integration** — Tools-menu entry via the canonical `INTAServices`
  pattern, and a menu command to clear all hover annotations.
- **Standalone UI aligned with the IDE plugin** (hamburger menu, Segoe UI,
  theming).
- **Application branding** — icon and image resources, including a
  float-mode icon for the dockable form.

### Changed

- **Lazy per-node `FindAll` cache** — removes roughly 140 redundant tree
  walks per file.
- **Detector post-filter O(n²) → O(n)**, and the grid stays usable at
  150k findings.
- **`.gitattributes` enforces CRLF for Delphi sources.** Mixed line endings
  had been produced by tooling that wrote files in text mode.

### Fixed

- Several detectors did not walk `nkAssign.TypeRef` and therefore missed
  everything on the right-hand side of an assignment
  (`CharToCharPointerCast`, `DateFormatSettings`, `IfThenShortCircuit`).
- Parser: `#$hh` hex character literals; the `while` condition is retained
  in `TypeRef`.
- SQL detector merges adjacent Pascal string literals before checking for
  `WHERE`, and no longer trips over English messages.
- 195 missing German translations backfilled, with a CI lock against
  regression.

---

## [0.9.3] - 2026-05-27

Polish release. No new detectors (count stays at 161). Focus on
IDE-plugin theme reliability in docked-mode, file encoding correctness,
and annotation-overlay usability.

Full release notes: [docs/releases/v0.9.3.md](docs/releases/v0.9.3.md)
([deutsch](docs/releases/v0.9.3_de.md)).

### Added

- IDE-plugin splash-screen entry + About-Box registration via standard
  ToolsAPI splash/about services.
- Visible 1 px per-tile border in the Sonar stats row, theme-aware via
  `ActiveStyleServices.GetSystemColor(clBtnShadow)`.
- `Konzept_DockedThemeRefresh.md` documenting the docked-mode theme
  diagnostic trail and the combined fix.
- `Konzept_ProjektAufteilung.md` outlining the planned project split
  (Engine / SharedUI / Standalone+CLI / IDE-Plugin / Tests).
- Regression test `StringEqualityWithFloatVarNameElsewhere_NotReported`
  for the FloatEquality string-compare false-positive.

### Changed

- **IDE-plugin theme apply pipeline** rewritten as a per-Descendant
  5-step walker (`ApplyTheme` → preserve `StyleElements - [seClient]`
  → resolve `Color`/`Font.Color` to concrete RGB → bind `StyleName` to
  the IDE style → `Invalidate` / grid `Repaint`). Fixes docked-mode
  theme refresh on tiles, toolbar panels, help-panel caption, memos.
- **`uIDETheme.TIDEThemeImpl.ApplyRecursive`** split into four named
  helpers: `ApplyStyleHookPreserveSeClient`, `ResolveDescendantColors`,
  `BindToIdeStyle`, `TriggerRepaint`.
- **`uFileTextCache.LoadFileSmart`** does three-stage encoding
  detection (BOM-sniff → strict-UTF-8 validation → Windows-1252
  fallback). Replaces the lenient `LoadFromFile(file, TEncoding.UTF8)`
  pattern that silently substituted invalid bytes.
- **Multi-finding annotation overlay** keeps each finding's
  description in an indented bullet list (was title-only summary).
  Fix-hint still suppressed for multi-mark.
- **`IDE_SEPARATOR`** color changed from `cl3DDkShadow` to
  `clBtnShadow` — visible in Dark themes (the old value collapsed
  onto `clBtnFace`).
- **`STATS_PANEL_HEIGHT`** 51 → 53 (Sonar stats row 2 px taller).
- **`FTileScore`** caption shortened from "Code Quality" to "Quality"
  (tile label + tooltip title; status-bar score line keeps the long
  form).
- **IDE-plugin toolbar** reduced from 4 rows to 3 (Path /
  Filter+Search / Stats); less-used actions moved into a hamburger
  menu.
- **`EngineSCA/`** folder renamed to `SCA.Engine/`.

### Fixed

- **Docked-mode IDE-theme refresh** affected only the grid; tiles,
  toolbar, help-panel caption and memos stayed in the previous theme.
- **`uFileTextCache`** silently produced mojibake on ANSI files with
  German umlauts in the unit header (`TEncoding.UTF8` decoded invalid
  bytes to U+FFFD instead of falling back to Windows-1252).
- **FloatEquality detector** reported `aValue = ''` (string compare)
  as a float-equality bug when another function in the same file had
  `aValue: Double` as a parameter. Stripped string content now uses
  `~` as marker so the regex can't bridge across an empty literal.
- **Theme-switch second-pass bug** — concrete RGB values were written
  back after first apply, so the next theme switch had no
  `clSystemColor` bit to resolve. Per-control original-color cache
  (`FOrigColors`) preserves the original identifier.

### Performance

- **~80× faster IDE theme switch** via cold/warm Apply split
  (per-Descendant `ApplyTheme` only on first apply; subsequent switches
  reuse registered style hooks). Full switch dropped from ~2 s of
  broadcast repaints to under ~25 ms.

---

## [0.9.2] - 2026-05-22

mORMot-cluster + Sonar-50 expansion + standalone progress +
i18n completeness. Detector count grows from 59 to **161 kinds**
(across ~130 detector classes — `uVisibilityCheck` emits 4 kinds,
`uDfmAnalysisRunner` emits 22).

Full release notes: [docs/releases/v0.9.2.md](docs/releases/v0.9.2.md)
([deutsch](docs/releases/v0.9.2_de.md)).

### Added

- **9 mORMot-cluster detectors** (SCA153-161): UnpairedLock,
  MoveSizeOfPointer, WithMultipleTargets, GetMemWithoutFreeMem,
  SetLengthAppendInLoop, PointerArithmeticOnString, EmptyOnHandler,
  StringFromPointer, PointerSubtraction.
- **SCA138-152 Sonar-50 expansion** filling Maintainability +
  Code-Smell slots: GodClass, FreeWithoutNil, MultipleExit,
  LargeClass, UnsortedUses, MissingUnitHeader, FloatEquality,
  ExceptInDestructor, BooleanParam, UnusedPrivateMethod,
  CanBeClassMethod, MissingOverride, BoolAlwaysTrue, ConstantReturn,
  HardcodedString.
- **Standalone GUI**: progress bar, Cancel button, MAX_SCAN_FILES
  scan-runaway protection (was IDE-only).
- **IDE-plugin keyboard shortcuts** are user-configurable (cnpack-
  style: press key combo, store in INI). Master toggle to disable all
  shortcuts. Settings dialog scrollable.

### Changed

- **Translation completeness: 161 / 161** finding-hint descriptions
  covered in both DE translation stores (GDeMap + i18n/de.po), all 82
  combo-labels translated.

---

## [0.9.1] - 2026-05-16

SonarQube-Integration release. Production-ready external-issues push
to SonarQube / SonarCloud, plus a major rule-catalog expansion and a
severity single-source refactor. Detector count grows from 41 to **59**
(21 Pascal + 20 DFM + 18 newer Pascal / visibility / SQL / format
detectors).

Full release notes: [docs/releases/v0.9.1.md](docs/releases/v0.9.1.md)
([deutsch](docs/releases/v0.9.1_de.md)).

### Added

#### SonarQube integration (Phase 0 + A + B + C + D per `todo-sonar.md`)

- **`uSonarConfig`** — 4-source config resolver (CLI > Env >
  `sonar-project.properties` > User-INI), DPAPI-encrypted token storage
  on Windows (plaintext+Base64 fallback on non-Windows for CI), each
  field tracks its source for diagnostics.
- **Health-check** — `--sonar-test` runs DNS → `/api/system/status` →
  token validation → project access in stages, renders an ASCII
  checklist. 403 disambiguation via `/api/components/show` distinguishes
  "project not found" from "no Browse permission".
- **Generic Issue Format export** — new unit `uExportSonarGeneric`,
  CLI flag `--sonar-export <file>`. Emits MQR fields
  (`cleanCodeAttribute` + `impacts`) per rule from the catalog; falls
  back to legacy `type` when the catalog isn't loaded so Sonar always
  accepts the JSON.
- **Project-template** — `--sonar-init` writes a `sonar-project.properties`
  template into the project root (or `.sample` if one exists).
- **IDE plugin Tools > Options > "Sonar Integration"** page
  ([uIDESonarOptions](StaticCodeAnalyserIDE/uIDESonarOptions.pas)) —
  Host / Project / Token / Branch / Insecure-TLS toggle, "Test
  Connection" button runs the same multi-stage check as the CLI,
  "Detect from project" reads `sonar-project.properties` of the active
  IDE project, token storage via DPAPI.
- **Send-to-Sonar context menus** in the findings list — bulk export
  (all findings, mirrors `--sonar-export`) plus per-issue export to
  `<repo>\.sonar\external\<severity>-<file>-L<line>-<hash>.json` for
  `sonar.externalIssuesReportPaths` pickup.
- **Pull-mode engine** `uSonarPull` — `GET /api/issues/search`, 5-min
  LRU cache, dedup-matcher for SCA-kind ↔ Sonar-rule name overlap.
  (UI binding into the findings grid deferred to a later release.)
- **PowerShell push helpers** under
  [StaticCodeAnalyserForm/scripts/](StaticCodeAnalyserForm/scripts/):
  `sonar-scan.ps1` (analysis + JSON), `sonar-upload.ps1` (DPAPI-decrypt
  + scanner) with `-DryRun` and `-DisableDelphi` switches for the
  SonarDelphi/communitydelphi sensor-crash case.

#### Rule-Catalog: 22 → 59 rules

- 37 new rule entries documented in [rules/sca-rules.json](rules/sca-rules.json)
  with full metadata (Name, ShortDescription, FullDescription, examples,
  tags, CWE, OWASP, configKey, detectorUnit). All 20 DFM detectors plus
  18 newer Pascal/visibility/SQL/format detectors: `ConcatToFormat`,
  `WithStatement`, `ReversedForRange`, `SelfAssignment`,
  `VirtualCallInCtor`, `LengthUnderflow`, `CanBePrivate`,
  `CanBeProtected`, `UnusedPublicMember`, `UnusedLocalVar`,
  `UnusedParameter`, `TautologicalBoolExpr`, `DfmMasterDetailUnlinked`,
  `DfmDataModuleSplitHint`, `SqlDangerousStatement`, `FormatLocaleHint`,
  `CustomRule`.
- **MQR mapping** per rule — `cleanCodeAttribute` (14-value taxonomy)
  + `impacts` (`softwareQuality` × `severity`) populated for all 59
  rules. Schema [rules/sca-rules.schema.json](rules/sca-rules.schema.json)
  extended; catalog version bumped 1.1 → 1.3.
- **Regenerated [docs/rules.md](docs/rules.md)** with the full 59-rule
  table and per-rule sections.

#### Detector quality

- `--sonar-export` plus `--sonar-test` plus `--sonar-init` plus seven
  per-flag overrides (`--sonar-host`, `--sonar-token`,
  `--sonar-project`, `--sonar-branch`, `--sonar-insecure`,
  `--sonar-config`).
- New drift tests `JsonSeverityMatchesKindMeta`,
  `EveryFindingKindHasRichMetadata`, `EveryFindingKindHasMqrMapping`
  in `uTestRuleCatalog` plus the full `uTestSonarConfig` and
  `uTestExportSonarGeneric` test fixtures.

### Changed

- **Severity is now single-source via `TLeakFinding.SetKind(K)`**
  ([uMethodd12](SCA.Engine/sources/Common/uMethodd12.pas)) —
  the new method sets Kind + pulls Severity from `KIND_META`. 58
  detector emit sites refactored from the two-line
  `F.Severity := lsXxx; F.Kind := fkXxx;` pattern; three detectors
  with context-dependent severity (`uLeakDetector2`, `uDivByZero`,
  `uCustomRuleDetector`) keep their manual assignment.
  `TFindingKindMeta.DefaultSeverity` is the new SOT in `KIND_META`.
- **Catalog lookup** ([uRuleCatalog.FindJsonFile](SCA.Engine/sources/Common/uRuleCatalog.pas))
  walks up to **8 directory levels** from the EXE/BPL dir (was 3) —
  fixes catalog-not-found from deep test runners and arbitrary scan
  working directories.
- **INI handling** — `TIniFile` → `TMemIniFile` in `uSonarConfig` and
  `uIDESonarOptions` so UTF-8-BOM files (Notepad default) parse
  correctly. `StoreToken` calls `Ini.UpdateFile` to persist.

### Fixed

- **Severity-drift** — `fkNilDeref` was emitting `lsError`, catalog
  said Warning → now Warning. `fkUnusedUses` was emitting `lsWarning`,
  catalog said Hint → now Hint. No existing test asserted the wrong
  values; SARIF export was already using the catalog values.
- **IDE plugin theme adoption** — Tools>Options frames now call
  `IOTAIDEThemingServices.ApplyTheme` in `FrameCreated` so they
  respect the active IDE theme (was falling back to VCL-default white).
  Shared one-shot helper `ApplyIDETheme` in
  `uIDEThemeIntegration`.
- **IDE plugin Options page i18n** — `GetArea` returns empty string
  (was `'Third Party'`) so the page lands under the localized
  "Fremdhersteller" / "Third Party" node instead of creating a second
  English-named root.
- **Options-page layout** — Frame total height fits the 520-px IDE
  pane (Connectivity-Memo no longer clipped at the bottom), labels
  use `AutoSize=False` to stay DPI-stable, DPAPI help label uses 8pt
  in a non-clipped 40-px box, memo background `clWindow` not `clBtnFace`.
- **Build** — `.dpr` contains-list updated with the new Sonar units
  (Standalone EXE refused to compile without it), `.dfm` resource
  added for `TSonarOptionsFrame` (VCL streaming needs it even for
  programmatically built frames), operator-precedence fix in
  `Pos(...)>0`-or-chains.
- **Health-check** — DNS-only stage no longer hangs, 403 case shows
  whether the project is missing or the token lacks Browse.

### Docs

- New: [sonarHowto.md](sonarHowto.md) + [sonarHowto_de.md](sonarHowto_de.md)
  (standalone-only walkthrough), [docs/sonar-setup.md](docs/sonar-setup.md)
  (full guide), [docs/sonar-config.md](docs/sonar-config.md) (resolver
  reference), [StaticCodeAnalyserForm/scripts/README.md](StaticCodeAnalyserForm/scripts/README.md)
  + `README_de.md` (scripts reference with troubleshooting table).
- All Sonar-relevant READMEs gained a "Tested with: SonarQube Community
  Build 26.5+, sits alongside Sonar Way" compatibility block.

---

## [0.9.0] - 2026-05-14

Workflow-focused release: Silent-Mode (single-file analysis from the
editor right-click + `Ctrl+Alt+A` hotkey), Rule-Set Profiles
(`ide-fast`/`default`/`strict`/`security`/`bugs-only`/`code-quality`/
`dfm-only`), Tools>Options page in the IDE, multi-file marker
storage, IDE-overlay polish, 10 new Pascal detectors with i18n, and
UI parity between Standalone form and IDE plugin.

Full release notes: [docs/releases/v0.9.0.md](docs/releases/v0.9.0.md)
([deutsch](docs/releases/v0.9.0_de.md)).

This entry retroactively documents the `v0.9.0` tag (created
2026-05-14) which was not landed in the changelog at release time.

---

## [0.8.0] - 2026-05-12

Big tagged release bundling four years of structural work: **DFM
scanner with 20 form-file detectors**, **headless CLI mode**,
**rule catalog**, **SARIF v2.1.0 export**, **IDE plugin polish**,
and **Win64 readiness** for the standalone EXE.

Detector count grows from 21 to **41 total** (21 Pascal + 20 DFM).

### Added

#### DFM scanner

- **20 DFM detectors** across six clusters (Dead-Wiring, Data-Access,
  Security, Layering, UI/UX, Naming). Each comes with a before/after
  fix hint and DUnitX tests. See [DETECTORS.md](DETECTORS.md).
- **DFM parsing infrastructure**: own lexer (`uDfmLexer`), parser
  (`uDfmParser`), component graph (`uComponentGraph`), plus
  binary-DFM reader (`uDfmBinaryReader`) for TPF0-prefixed files
  that used to be silently skipped.
- **Typed property accessors** on `TPropValue` + `TComponentNode`
  (`GetBoolean / GetInteger / GetString / GetIdent /
  SetPropertyContains`), default-aware to mirror VCL serialisation
  semantics.
- **FormBinder** (`uFormBinder`) couples DFM graph to Pascal AST.
  `BindWithParents` walks the class inheritance chain so detectors
  see inherited members.
- **Repo-wide form index** (`TDfmRepoIndex`) for cross-unit lookups:
  "which class lives in which `.pas`", "which form owns this
  datasource".
- **Frame resolver** (`uDfmFrameResolver`) loads a frame's
  components on demand for cross-frame analyses.
- **`.dfm`-aware VCS diff**: branch changes on a `.dfm` queue the
  companion `.pas` for analysis (and vice versa).
- **HTML report** groups `.pas` + `.dfm` with the same basename
  under one dropdown entry.
- **IDE plugin — DFM finding opens DFM as text** in the Code
  Editor via the Close-and-Reopen pattern (DFMCheck/GExperts-
  style). When the companion `.pas` is modified, falls back to
  opening the `.pas` with a status-bar hint that Alt+F12 toggles
  to the DFM source. Return enum `TOpenFileMode`
  (`ofmRegular` / `ofmDfmAsText` / `ofmDfmFallbackPas`) drives the
  status text.
- **Standalone EXE — modal DFM text viewer** on double-click.
- **Smarter double-click on DFM findings** in the standalone grid.
- **WatchMode** now triggers re-analysis on `.dfm` saves and edits
  (companion-aware: `.dfm`-as-text changes are mapped to the
  watched `.pas`).
- **Demo resources** under `resources/`:
  - `uOrderForm.{pas,dfm}`: `TADOQuery` + `TFields` + `TDBEdit`
    chain with intentional smells.
  - `uCustomerForm.{pas,dfm}`: `TFDQuery` → `TDataSetProvider` →
    `TClientDataSet` → `TDataSource`.

#### Headless CLI + Rule Catalog + SARIF

- **Headless CLI mode** (`{$APPTYPE CONSOLE}` dispatch) —
  `analyser.d12.exe --path X --full|--branch|--file Y
  --report-sarif sca.sarif` runs the same engine as the IDE plugin
  without RAD Studio. Exit-code mapping
  (0 clean / 1 hints / 2 warnings / 3 errors / 4 read errors /
  99 tool error) drops into CI pipelines and pre-commit hooks.
- **Rule catalog** (`rules/sca-rules.json`) — single source of
  truth for all 22 Pascal-AST detector rules (`SCA001`–`SCA022`)
  with stable IDs, severity, type, tags, CWE, OWASP refs, fix
  examples. Loader `uRuleCatalog` + JSON schema for editor
  autocomplete and CI validation.
- **SARIF v2.1.0 export** — natively consumed by GitHub Code
  Scanning, Azure DevOps, VS Code, SonarCloud. Findings appear as
  PR inline annotations; `partialFingerprints` deduplicate across
  commits.
- **GitHub Actions workflow template** in
  `.github/workflows/sca.yml` — `sca` (full project on push/PR,
  SARIF upload) + `sca-pr-changes` (branch diff, fail-on-error
  for PRs).
- **`docs/rules.md`** consolidated Markdown rule reference,
  referenced by SARIF `helpUri`.

#### IDE plugin polish

- **Three-tier responsive layout** for the docked window
  (Narrow/Medium/Full breakpoints at 500/700 px).
- **Hamburger menu** absorbs all toolbar actions in narrow mode.
- **Single-file live watch** (📄 Current file) — Save 300 ms /
  Edit 1000 ms debounced background re-analysis.
- **Hover-hint overlay** for finding lines, multi-line wrap.
- **Sonar-style stat tiles** above the grid.
- **Theme tracking** via `IOTAIDEThemingServices` +
  `INTAIDEThemingServicesNotifier` notifier.

#### Other

- **Standalone EXE compiles cleanly for Win64** —
  `analyser.d12.dproj` lists `Win32 + Win64` in its `<Platforms>`
  block. No code changes required for a 64-bit build.

### Changed

- `uIDEEditorIntegration.OpenFileAtLine` returns `TOpenFileMode`
  instead of `Boolean`. Third-party callers (unlikely outside this
  repo) need to update.
- `SafeCloseModule` uses `CloseModule(True)` (save-if-dirty)
  unconditionally — the `Modified` flag is unreliable in Delphi 12
  immediately after `OpenFile` and was blocking Close-and-Reopen.
- README + README-de rewritten to highlight 41 detectors + DFM
  scanner; added "Related projects and alternatives" and SEO
  "Keywords" / "Schlagwörter" sections.
- Toolbar buttons (`☰` hamburger, `...` browse) now sit flush
  against the right panel edge (removed 6 px right padding).

### Fixed

- `TEditSource Refcount = 2` error during IDE destroy after rapid
  DFM↔PAS click sequences. Cause: implicit interface references
  kept the source alive past IDE-internal destroy ordering. Fix:
  explicit `:= nil` on the `IOTAModule` reference in
  `SafeCloseModule`.
- DFM-finding line off-by-one in the standalone modal viewer.
- `TDictionary<string, Cardinal>` var-parameter type mismatch in
  `uExportHtml` (inline-var was inferred as `Integer`).
- `Classes.ObjectBinaryToText` qualifier dropped — `System.Classes`
  doesn't expose a `Classes`-only alias on Delphi 12; unqualified
  call resolves correctly through the `uses` chain.
- **Win64 readiness**: `uDfmTextViewer.StartPos` is now `LRESULT`
  with an explicit `Integer(...)` cast at the `SelStart` assignment
  site — eliminates `W1057 implicit truncation` warning on Win64
  builds.

---

## [0.7.2] - 2026-02-15

### Added

- Hover-overlay description as multi-line wrap text.

### Changed

- IDE plugin docked layout: hamburger menu fully absorbs all
  actions in narrow mode.

---

## [0.7.1] - 2026-01-20

### Added

- IDE hover-hint overlay on finding lines.

### Fixed

- IDE plugin: first docking reliably switches into compact layout.
- Three detectors received false-positive reduction work.

### Changed

- Central three-tier responsive layout for the IDE plugin.
- FormatMismatch fixes.

---

## [0.7.0] - 2025-12-15

### Added

- Docked-mode UI: two breakpoints (700/400) with sub-panel width
  shrinking; hamburger menu; SearchEdit shrinks in docked mode.
- DPI scaling + extracted layout constants.

---

## [0.6.x and earlier]

Initial release stream — Sonar-style classification, 21 Pascal
detectors, Git+SVN branch-changes mode, dxgettext localisation,
HTML/CSV/JSON export, Claude AI prompt copy, theme-aware
rendering. See `git log` for granular history before the changelog
was introduced.

---

## Conventions

- **MAJOR.MINOR.PATCH** follows SemVer for the public API of the
  IDE plugin (BPL exports) and the standalone CLI (flags + exit
  codes). Detector additions are **MINOR** bumps; behaviour or
  signature changes that break either are **MAJOR**.
- The pre-1.0 line is still allowed to break public surface in
  MINOR bumps when the change is necessary — every such case is
  called out under **Changed** with a migration note.
- Each entry is grouped under **Added / Changed / Fixed / Removed
  / Deprecated / Security** so a reader can scan one section.
- Dates are absolute (`YYYY-MM-DD`) so relative phrasing like
  "last week" doesn't drift.

# Todo: i18n-Backlog

Snapshot 2026-05-30, generiert mit `tools/i18n_audit.sh`.

**Source-Strings:** 456 eindeutig
**de.po msgids:**   319
**Missing in de.po:** 195 (im Source aber nicht uebersetzt)
**Dead in de.po:**    58 (msgid existiert, Source-String nicht mehr)

Im DE-UI fallen fehlende msgids auf den englischen Source-String zurueck.
Karteileichen schaden nicht, machen aber das po-File unleserlich.

## Empfohlene Reihenfolge

1. **Tote Eintraege loeschen** (mechanisch, kein Judgment, ueber poedit
   oder direkt im Text-Editor). Liste unten.
2. **Missing-Strings batchweise nachuebersetzen** (siehe unten, sortiert).
3. **CI-Lock einrichten:** `tools/i18n_audit.sh` als pre-commit-hook
   oder CI-Step - exit-code 1 wenn neue \_()-Strings ohne de.po-Eintrag
   dazukommen. Dann waechst der Backlog nicht weiter.

## Karteileichen in de.po (zu LOESCHEN)

msgids im po-File, deren Source-String entfernt wurde. Loeschen ist
mechanisch sicher - schadet hoechstens beim Restore via VCS.

```
--- Errors ---
--- Hints ---
--- Warnings ---
Analysis running...
Available shortcuts:
Class field without \"F\" prefix
Class/record type without \"T\" prefix
Ctrl+Alt+A      global         Analyse current file (silent)
Ctrl+Alt+Down   global         Jump to next finding line
Ctrl+Alt+F      findings grid  Apply Quick-Fix in editor
Ctrl+Alt+S      findings grid  Insert \"// noinspection\" marker
Ctrl+Alt+Up     global         Jump to previous finding line
Current file
Dead Code
Debug Output
Deep Nesting
Disable to mute every plugin shortcut at once. Right-click menu + toolbar buttons remain functional.
Div by Zero
Double semicolon \";;\" - one is enough
Duplicate Code Blocks
Duplicate Strings
Empty Except
Empty Methods
Empty argument list \"()\" - drop the parentheses
Enter           findings grid  Goto editor line (same as dbl-click)
Filter: %s
Findings-grid shortcuts (not configurable): Ctrl+Alt+F = Quick-Fix, Ctrl+Alt+S = Suppression, Enter = goto editor line.
Format()
Hardcoded Path
Hardcoded Secrets
Include tests
Interface type without \"I\" prefix
Jump to the next / previous highlighted finding line in the current editor tab (wrap-around at file end/start). Disable to release the shortcut to the IDE default handler.
Long Method
Magic Number
Many Parameters
Memory Leak
Missing Finally
Nil-Deref
Override whose body is just \"inherited\" adds nothing
PChar(s) arithmetic without empty-check - PChar('') is nil, arithmetic triggers AV
Pointer type alias should start with \"P\"
Prefer Assigned() over \"= nil\" / \"<> nil\"
Project path:
Read error
Repo...
SQL Injection
SQL command built with \"+\" - SQL injection risk
Save path:
Search:
Static Code Analysis Tool for Delphi
TODO/FIXME
Unused Uses
git not found. Install Git for Windows.
no Git/SVN repository in or above %s
no base branch (main/master) found - working tree only
svn not found. Install TortoiseSVN with command line tools.
with uses check
```

## Fehlende Uebersetzungen (zu ERGAENZEN in de.po)

Format-Tipp: jeder Eintrag braucht in de.po
```po
msgid "<original-string>"
msgstr "<deutsche Uebersetzung>"
```
Bei Format-Specifiern (%d, %s) Reihenfolge erhalten.

```
 - no changed .pas files
 · 
%d file(s) - running...
%d findings
%d findings on this line
...
1-2 sentences why the rule fires on THIS specific code (not the generic explanation above).
AI prompt copied to clipboard: %s, line %s (%s)
Actions menu: Branch-Changes, Cancel, Export, Settings, Ignore
After
After:
All toolbar actions (Analyse, Browse, Export, Settings, ...)
Analyse Branch-Changes
Analyse current file (silent)
Analysing %d changed file(s). %s
Analysing: 
Analysing: %s
Analysis cancelled - no new findings loaded
Analysis error: 
Analysis running - searching for files...
Anti-pattern
As of: 
Before:
Branch changes: please provide a valid project path (for repo detection).
Bug
CSV export
CSV export failed: 
CSV file (*.csv)|*.csv
CSV files|*.csv|Log files|*.log
CSV saved: %s (%d entries)
Cancel Analysis
Cancelling analysis...
Cause
Checking all classes...
Choose folder
Class field without "F" prefix
Class/record type without "T" prefix
Click: filter grid to Bug type
Click: filter grid to Cyclomatic
Click: filter grid to Duplicate type
Click: filter grid to Errors
Click: filter grid to Hints
Click: filter grid to Vulnerability type
Click: filter grid to Warnings
Click: filter grid to read errors
Clipboard: please select a row first (file not unambiguous).
Code (>>> marks the line that triggered the rule)
Code Duplication
Code Smell
Code analysis: 
Code review request - Delphi static analysis finding
Code smells / style. Refactoring candidates.
Copied code (strings, blocks). Extract Method/Constant candidates.
Could not open editor. File: 
Crosses severities - Bugs can be Errors OR Warnings.
Current file is not a Pascal file.
Cyclomatic
DFM as text: %s  Line: %d
DFM finding at line %d - .pas is modified, press Alt+F12 to view DFM as text
DFM viewer: %s  Line: %d
Detail
Detectors (analyser.ini [Detectors])
Dismiss this finding (remove marker)
Done. No findings.
Double semicolon ";;" - one is enough
ERROR
Empty argument list "()" - drop the parentheses
Enable silent analysis (editor right-click + Ctrl+Alt+A)
Errors+warnings for %s copied to clipboard.
Export: HTML, JSON, CSV, Jira markup, plain text
Field
File %d
File %d / %d
File %d / %d (%d%%)
File could not be read / parsed. Check path/encoding.
File not found: 
Filter: %s%s
Filtered: %d of %d findings
Filtered: 0 of %d findings
Finding
Findings in detail
Findings of type Bug (wrong behaviour, crash, wrong result).
Fix
Git diff %s: %d file(s) to analyse
Git: branch vs 
Git: no base branch - working tree only
HINT
HTML export failed: 
HTML file (*.html)|*.html
HTML report (all findings)...
HTML report saved: %s
Hard to test - refactor into smaller methods.
Hint: 
IDE Profile:
IDE editor service not available.
If the finding is a false positive, say so and explain why - then suggest a `// noinspection %s` suppression marker on the affected line.
Ignore list...
IncludeTests - analyse DUnit/DUnitX test units too
Info
Interface type without "I" prefix
JSON export
JSON export failed: 
JSON file (*.json)|*.json
JSON saved: %s (%d entries)
Jira export: please select a row first (file not unambiguous).
Jira markup -> Clipboard
Jira wiki markup for %s copied to clipboard (errors+warnings).
L. 
Likely bugs / risky patterns. Review before merge.
Methods with McCabe complexity > threshold (default 10).
Min-Severity:
MinSeverity "%s" - active on next analysis run
More than %d files found - scan cancelled.
No file opened.
No findings.
No matches.
Nothing to export - filter returns 0 entries.
Open analyser.ini (BaseBranch, git/svn paths, custom LeakyClasses)
Open ignore list (which files are NOT analysed)
Opened: %s  Line: %d
Override whose body is just "inherited" adds nothing
Pascal file (*.pas)|*.pas|All files|*.*
Path:
Plain text -> Clipboard
Please provide a valid project path.
Please respond with three sections
Pointer type alias should start with "P"
Prefer Assigned() over "= nil" / "<> nil"
Profile "%s" - active on next analysis run
Profile (CLI/Form):
Profile:
Project path is empty.
Quality
Quick-Fix + AI prompt copied to clipboard: %s, line %s (%s)
Quick-Fix applied: %s
Quick-Fix: cannot locate source line
Quick-Fix: editor write failed (file not in IDE?)
Quick-Fix: line out of range
Quick-Fix: pattern not matched on line %d - manual fix required
Real bugs / security holes (severity Error). Fix immediately.
Recommended fix
Rule description
Rule-Set (analyser.ini [Rules])
Rule-set: Profile=%s, MinSeverity=%s
SQL command built with "+" - SQL injection risk
SVN call failed (exit code = %d)
Save results
Saved, queueing analysis: %s
Saved: 
Scanning... %d found
Search: 
Security Hotspot
Security holes (SQL injection, hardcoded secrets ...).
Select Pascal file to analyse
Select project folder
Settings...
Settings: %s - changes take effect on the next analysis run.
Severity
Silent Mode
Sonar export failed: 
Sonar push failed: 
Sonar push needs a project directory (run analysis first).
Sonar push: select at least one finding first.
Sonar push: wrote %d issue file(s) to .sonar\external\
Sonar report saved: %s
Sonar report saved: %s (%d findings)
Sonar: send selected as external issue
Sonar: write Generic Issue report (all findings)...
Sonar: write Generic Issue report...
Static Code Analyser: analyse this file, no dock opens
Static Code Analysis
Summary
Suppress inserted: %s
Suppress: cannot locate source line
Suppress: editor write failed (file not in IDE?)
Type
Unexpected error: 
Value
Verify
Vulnerability
WARNING
Watch: could not attach to %s
Watching: %s
Weighted quality score (lower = better).
Weights: Vulnerability 10, Error 7, Hotspot 5, Warning 3, Hint 1, FileErr 2.
analyse only files changed in current branch
default
h2. Code analysis: 
in
no findings
text
the modified code as a Pascal block. Keep diff minimal: only the lines that need to change. Match surrounding indentation and naming style.
what to test or check after the fix to confirm the issue is gone (and no regressions).
▶ Analyse
📄 File
```

# Todo: i18n-Backlog

## Aktueller Stand (2026-05-30, nach Backfill-Runde)

**Missing:** **0** ✅  (war 195)
**Dead:**    49        (war 58 - Backfill hat 9 als wieder-genutzt re-aktiviert)

Komplette Backfill ueber 195 fehlende Strings ist in `i18n/de.po` als
"Backfill 2026-05-30"-Block angehaengt. Best-Effort-Uebersetzungen -
**Review empfohlen** fuer Stil/Terminologie-Konsistenz.

## Verbleibender Cleanup-Track

**49 tote Eintraege in de.po** - msgids ohne Source-Match. Hauptsaechlich:
- Alte Detector-Display-Namen ("Dead Code", "Debug Output", ...) - nach
  Refactor auf KIND_META.Name-Lookup obsolet.
- Keyboard-Shortcut-Tabellen ("Ctrl+Alt+...") - vermutlich nach UI-Redesign.
- Severity-Header ("--- Errors ---") - nach Sonar-Style-Tile-Umstellung.

Diese Eintraege beeintraechtigen den DE-UI nicht (sie werden nirgends mehr
ueber `_()` referenziert). Loeschen ist Aufraeumarbeit am po-File - am
besten mit poedit oder ueber das po-Editing-Tool deiner Wahl, NICHT per
sed/awk (fehleranfaellig bei Multi-Line-Eintraegen mit Comments).

Liste der 49 toten Eintraege:

```
--- Errors ---
--- Hints ---
--- Warnings ---
Analysis running...
Available shortcuts:
Ctrl+Alt+A      global         Analyse current file (silent)
Ctrl+Alt+Down   global         Jump to next finding line
Ctrl+Alt+F      findings grid  Apply Quick-Fix in editor
Ctrl+Alt+S      findings grid  Insert "// noinspection" marker
Ctrl+Alt+Up     global         Jump to previous finding line
Current file
Dead Code
Debug Output
Deep Nesting
Disable to mute every plugin shortcut at once. Right-click menu + toolbar buttons remain functional.
Div by Zero
Duplicate Code Blocks
Duplicate Strings
Empty Except
Empty Methods
Enter           findings grid  Goto editor line (same as dbl-click)
Filter: %s
Findings-grid shortcuts (not configurable): Ctrl+Alt+F = Quick-Fix, Ctrl+Alt+S = Suppression, Enter = goto editor line.
Format()
Hardcoded Path
Hardcoded Secrets
Include tests
Jump to the next / previous highlighted finding line in the current editor tab (wrap-around at file end/start). Disable to release the shortcut to the IDE default handler.
Long Method
Magic Number
Many Parameters
Memory Leak
Missing Finally
Nil-Deref
PChar(s) arithmetic without empty-check - PChar('') is nil, arithmetic triggers AV
Project path:
Read error
Repo...
SQL Injection
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

## Nachhaltigkeit

Der GitHub-Actions-Workflow `.github/workflows/i18n-check.yml` laeuft
`tools/i18n_audit.sh` auf jedem Push + PR. Exit-Code 1 bei Backlog-
Wachstum scheitert die Build-Pipeline - PRs die neue `_()`-Strings
ohne de.po-Eintrag einfuehren werden blockiert.

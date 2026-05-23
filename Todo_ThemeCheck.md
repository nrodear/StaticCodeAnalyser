# Theme-Refresh Checkliste — IDE-Plugin Components

> Hake ab oder kommentiere wo der Theme-Wechsel nicht greift.
> Format: `[ ]` = ungetestet · `[✓]` = OK · `[✗]` = bleibt im falschen Theme

---

## Frame-Container

- [ ] `TAnalyserFrame` selbst (Background)
- [ ] Host-TForm (IDE-Dock-Wrapper)
- [ ] Host-TForm-Titelzeile (Float-Mode)

## Toolbar-Zeile 1 — PanelPath

- [ ] `PanelPath` Background
- [ ] `LblPath` ("Project path:")
- [ ] `FProjectPath` (ComboBox)
- [ ] `FBtnBrowse` ("…")
- [ ] `FBtnIgnore` ("Ignore…")
- [ ] `FBtnRepo` ("Settings…")

## Toolbar-Zeile 2 — PanelButtons (Filter)

- [ ] `PanelButtons` Background
- [ ] `FPanelSev` Sub-Panel Background
- [ ] `FLblFilter` ("Severity:")
- [ ] `FFilterCombo` (ComboBox)
- [ ] Spacer 1 (TBevel)
- [ ] `FPanelType` Sub-Panel Background
- [ ] `FLblType` ("Type:")
- [ ] `FTypeCombo` (ComboBox)

## Toolbar-Zeile 3 — PanelSearch (Actions + Search + Export)

- [ ] `PanelSearch` Background
- [ ] `FPanelProfile` Sub-Panel Background
- [ ] `FLblProfile` ("Profile:")
- [ ] `FProfileCombo` (ComboBox)
- [ ] Spacer 1 (TBevel)
- [ ] `FBtnAnalyseChanged` ("⎇")
- [ ] `FBtnAnalyse` ("▶ Analyse")
- [ ] `FBtnAnalyseCurrent` ("📄 File")
- [ ] Spacer 2 (TBevel)
- [ ] `FLblSearch` ("Search:")
- [ ] `FSearchEdit` (Edit)
- [ ] `FBtnExport` ("Export ▼")
- [ ] `FBtnCancel` ("Cancel")
- [ ] `FBtnHamburger` ("☰")

## Stats-Tile-Reihe — FPanelStats

- [ ] `FPanelStats` Background
- [ ] Tile "Errors"
- [ ] Tile "Warnings"
- [ ] Tile "Hints"
- [ ] Tile "Read errors"
- [ ] Tile "Bugs"
- [ ] Tile "Security"
- [ ] Tile "Duplicates"
- [ ] Tile "Cyclomatic"
- [ ] Tile "Code Quality"
- [ ] Tile-Border (cl3DDkShadow)
- [ ] Tile-Glyphs (Segoe Fluent Icons, Akzentfarbe)
- [ ] Tile-Count-Zahl (Bold, IDE_FG_CHROME)
- [ ] Tile-Caption (klein, IDE_FG_DIM)

## Grid-Bereich

- [ ] `FResultGrid` Background (Cells)
- [ ] `FResultGrid` Header (FixedRow)
- [ ] `FResultGrid` Grid-Lines
- [ ] `FResultGrid` selektierte Zeile
- [ ] Severity-Cell-Akzentfarben (Error/Warn/Hint)

## Help-Panel rechts vom Grid

- [ ] `FHelpPanel` Background
- [ ] `HelpLeftSep` (1px Separator)
- [ ] `FHelpDescLabel` (Header "Select a row…" / "Before:" Text)
- [ ] `FHelpBeforePanel` Background
- [ ] `LblBefore` (rote Severity-Caption, sollte ROT bleiben unabhängig vom Theme)
- [ ] `FHelpBefore` Memo Background
- [ ] `FHelpBefore` Memo Text-Farbe (clWindowText)
- [ ] `BeforeAfterSplitter` (cl3DDkShadow)
- [ ] `HelpAfterPanel` Background
- [ ] `LblAfter` (grüne Hint-Caption, sollte GRÜN bleiben)
- [ ] `FHelpAfter` Memo Background
- [ ] `FHelpAfter` Memo Text-Farbe
- [ ] `FHelpSplitter` (Grid|Help)

## Statusbar (unten)

- [ ] `FStatusBar` Background
- [ ] Panel 0 "Findings"-Text
- [ ] Panel 1 "Progress"-Text
- [ ] Panel 2 "Mode"-Text (z.B. "Ready.")

## Progressbar

- [ ] `FProgressBar` (zwischen StatusBar und Toolbar)

## Tools → Options → Static Code Analysis

- [ ] `TSCAOptionsFrame` Background
- [ ] `FScroll` (ScrollBox)
- [ ] GroupBox "Silent"
- [ ] GroupBox "Rule-Set"
- [ ] GroupBox "Detectors"
- [ ] GroupBox "Hotkeys"
- [ ] Labels (caption text)
- [ ] Checkboxes
- [ ] ComboBoxes (Profile, MinSev, IdeProfile)
- [ ] Edit-Fields (Shortcut capture)

## Tools → Options → Sonar Integration

- [ ] `TSonarOptionsFrame` Background
- [ ] GroupBox "Server"
- [ ] GroupBox "Auth"
- [ ] GroupBox "Actions"
- [ ] Edit-Fields (Host, Project, Branch, Token)
- [ ] Buttons (Test Connection, Open analyser.ini, Reveal Token)
- [ ] `memoResult` (Connection-Test-Output)

## Editor-bezogen (separate UI, opt-out vom Theme)

- [ ] `TAnnotationOverlay` Severity-Popup (bewusst NICHT themed —
      mixt Severity-Akzent über Editor-BG, hat eigene Logik)
- [ ] `FFindingHighlighter` Editor-Stripe (Canvas-paint mit Severity-Farbe,
      kein Theme-Bezug)

---

## Test-Szenarien — bitte bei jedem Component-Block prüfen

1. **Erstöffnen (Dark-IDE):** View → SCA → Frame sollte sofort dark sein
2. **Live-Switch:** Tools → Options → IDE Style → Dark→Light → Frame folgt
3. **Float ↔ Dock:** Frame floaten, dann zurück docken → bleibt korrekt
4. **Options-Page-Live-Switch:** Tools→Options→SCA aktiv, parallel Theme switchen → Options-Frame folgt

## Bekannte Edge-Cases

- VCL-Style ≠ IDE-Theme (z.B. user hat Mountain_Mist + IDE-Dark) — wurde gelöst via `RegisterFormClass + ApplyTheme`
- Custom-3rd-Party-Style (z.B. Carbon, Iceberg) — unter `Theming.StyleServices` werden auch diese korrekt aufgelöst
- ChangeTheme während Modal-Dialog offen — bisher nicht getestet

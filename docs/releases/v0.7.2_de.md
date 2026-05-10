## v0.7.2 — Responsive-Layout-Refactor + Detector-Accuracy

Patch-Release ueber v0.7.1. Schwerpunkt: Architektur-Cleanup der Plugin-
UI (zentraler 3-Stufen-Layout-Controller statt verstreuter Visibility-
Toggler), Font-skalierte Component-Hoehen, drei FormatMismatch-Detector-
Fixes nach Code-Reviews realer mORMot-2.4-Befunde, sowie Polish am
In-Editor Hover-Hint Overlay.

### Highlights

- **Zentraler `TResponsiveLayoutController`** (NEU, ersetzt
  `TResponsiveVisibilityController`) — eine Klasse, eine ClientWidth-
  Quelle (Frame.OnResize), eine Sichtbarkeitstabelle. Vorher 5 verteilte
  Controller-Instanzen ueber 4 Panels mit chained OnResize-Hooks; jetzt
  deklarative Stage-Registrierung an einer Stelle:
  ```pascal
  FResp := TResponsiveLayoutController.Create(Self, Self,
             BREAKPOINT_MEDIUM, BREAKPOINT_FULL);
  FResp.RegisterCtrl(FBtnCancel,    usFull);             // nur FULL
  FResp.RegisterCtrl(FLblFilter,    usMedium);           // ab MEDIUM
  FResp.RegisterCtrl(FBtnHamburger, usNarrow, usMedium); // inverse
  ```
  Hat `AfterApply`-Callback fuer Folge-Anpassungen (Sub-Panel-Width-Sync,
  SearchEdit-MinWidth-Sync). Ergebnis: 5 Controller-Instanzen + chained-
  OnResize-Race-Conditions weg, +80 Zeilen Code geloescht, alle Sichtbar-
  keitsregeln auf einem Blick lesbar.

- **`TToolbarSizing`-Helper** (NEU) — loest die VCL-Quirk dass `TComboBox`
  die `Align.Height` ignoriert (rendert immer auf `ItemHeight + ~6 px`).
  Drei statische Methoden:
  - `HeightForFont(Font)` — leitet Soll-Hoehe aus `Abs(Font.Height) + 11`
    ab. DPI-aware ueber `Font.Height` (Pixel, kein extra `ScaleW` noetig).
    Bei Segoe UI 8pt = 22 px, 9pt = 23 px, 10pt = 24 px.
  - `Apply(Ctrl, AHeight)` — setzt `Constraints.MinHeight = MaxHeight`
    (VCL respektiert das auch bei aktivem Align), bei TComboBox zusaetz-
    lich `ItemHeight := AHeight - 6`. Resultat: Buttons/Edits/Combos
    rendern uniform.
  - `ApplyIconButton(Ctrl, AWidth, AHeight)` — zusaetzlich Width-
    Constraints fuer pixel-genaue Icon-Buttons (Browse "...",
    Hamburger ☰, Branch-Changes ⎇ alle uniform 32 px).

- **Floated-Min-Width = 500 px** (NEU) — `Frame.Constraints.MinWidth` +
  Propagation auf das IDE-Host-Form via `GetParentForm` in
  `FrameCreated`. Verhindert pathologisch schmale Floats - das floated
  Window kann nicht mehr unter den MEDIUM-Stufen-Threshold geschrumpft
  werden.

- **In-Editor Hover-Hint Overlay** (verfeinert) — Theme-adaptiv (Light/
  Dark folgt aktivem IDE-Theme via `INTACodeEditorServices.Options.
  BackgroundColor`), mehrzeiliger Wrap-Text, Severity-getoenter Title-
  Bar mit Akzent-Stripe links + Type-Badge rechts. Klick auf eine
  Befundzeile markiert ALLE Befunde derselben Datei (Multi-Marker via
  `TDictionary<Integer, TFindingMark>`). Komplett i18n via `_()`.

### Engine

- **FormatMismatch: drei zusammenhaengende False-Positive-Fixes** nach
  Code-Reviews realer mORMot-2.4-Befunde:

  1. **Bare-`%`-Counting** fuer mORMot-Funktionen (`FormatUtf8`,
     `FormatString`, `StringFormatUtf8`): diese nutzen `%` allein als
     Platzhalter (kein Type-Letter wie `%s`/`%d`). Neue `IsBareStyle`-
     Check + zweite Counting-Strategie via `CountPlaceholders(ABareStyle)`.
     Hardcoded-Liste `BARE_STYLE_FUNCS` - bei weiteren mORMot-Idiom-
     Funktionen dort ergaenzen.

  2. **`%%` ist KEIN Escape im Bare-Style** - verifiziert in mORMot-
     Source (`mormot.core.text.pas:9616 TFormatUtf8.Parse`): jedes `%`
     konsumiert ein Argument, `%%` = zwei aufeinanderfolgende Args ohne
     Trenner (mORMot nutzt das z.B. um Where-Clauses zu kettenkonkate-
     nieren). Standard-RTL-`Format` bleibt streng - dort ist `%%` weiter-
     hin Escape.

  3. **String-Literal-Konkatenation `'a' + 'b'`** wird vor dem Counting
     gemerged - typisch fuer mehrzeilige SQL-Strings:
     ```pascal
     FormatUtf8('SELECT ... ' + 'WHERE Id=%', [id])  // OK, 1+1 match
     ```
     Helper `ReadStringLiteral`/`SkipSpaces`, Loop bis kein `+ '...'`
     mehr folgt. Nicht-statische Fortsetzungen (`+ IntToStr(x)`) brechen
     den Merge ab und der Detector liefert nur das gemergete Prefix
     (konservativ, kein False Positive).

  Effekt auf reale mORMot-2.4-Findings:
  | File | v0.7.1 | v0.7.2 |
  |---|---|---|
  | `dmvc-ai/.../api.impl.pas:62` | False Positive (0 vs 1) | OK (1 vs 1) |
  | `dmvc-ai/.../api.impl.pas:71` | False Positive (1 vs 2) | OK (2 vs 2) |
  | `dmvc-ai/.../api.impl.pas:126` | False Positive (1 vs 2) | OK (2 vs 2) |
  | `mormot.orm.rest.pas:1780` | True Bug, Count falsch | True Bug, Count korrekt (9 vs 8) |

### IDE-Plugin

- **`TResponsiveVisibilityController` entfernt** (deprecated in v0.7.1,
  geloescht in v0.7.2) - `TResponsiveLayoutController` ersetzt vollstaendig.
- **3-Stufen-Layout** stabilisiert: NARROW (`<500`), MEDIUM (`500..849`),
  FULL (`>=850`). Zwei Stufen-Wechsel statt frueher einer - Uebergang
  vom Hamburger-Pattern zum vollen UI ist smoother (kein abrupter
  Sprung in voller Toolbar).
- **Hamburger-Menu** neu strukturiert: Analyse Branch-Changes, Cancel
  Analysis, Export..., Settings..., Ignore list... (Browse "..." und
  ▶ Analyse + 📄 File sind im Toolbar IMMER sichtbar, nicht im Menu).
  `HamburgerMenuPopup` synct Enabled-State von Cancel + Branch-Changes
  Items mit den zugehoerigen Buttons - kein Doppelclick-Race wenn
  Analyse laeuft.
- **Branch-Changes-Button** als Icon-Glyph ⎇ (32 px) statt Caption-Button
  (104 px). Caption "Branch-Changes" + Volltext bleiben im Tooltip und
  im Hamburger-Menu erreichbar.
- **`TAnalyserDockableForm.FrameCreated`** propagiert die Frame-MinWidth/
  MinHeight auf das Host-Form via `GetParentForm` - das IDE-Floating-
  Container respektiert die Mindestbreite jetzt auch beim Resize.
- **Tile-Reihe**: alle 9 Tiles uniform 55 px breit (statt frueher 65/72/72
  pro Severity-/Type-/Detector-Tile). Konsistente Sonar-Style-Reihe.
  Stage-Registrierung: 4 essentials immer, +5 ab MEDIUM (Read errors,
  Bugs, Security, Duplicates, Cyclomatic).
- **Toolbar-Padding** reduziert (`TB_PADDING_TB` 2→1) - Toolbar-Reihen
  nehmen pro Zeile 2 px weniger Hoehe ein.

### Tests

- **`TTestFormatMismatchBareStyle`** mit 6 neuen Tests in
  `uTestFormatMismatch`:
  - `FormatUtf8_TwoBarePercents_TwoArgs_NoFinding` (Original-Bug-Case)
  - `FormatUtf8_OneBarePercent_TwoArgs_ReportsError`
  - `FormatString_BarePercentSeparator_NoFinding`
  - `FormatUtf8_DoublePercent_ConsumesTwoArgs` (verifiziert kein Escape)
  - `FormatUtf8_ConcatenatedLiteral_AllPlaceholdersCounted`
  - `FormatUtf8_ConcatenatedLiteral_MismatchAcrossSplit_ReportsError`
  - `StandardFormat_PercentUnderscore_StillReportsMismatch` (RTL-Format-
    Regression)

### i18n

- **Hover-Overlay**: alle Anzeige-Strings ueber `_()` lokalisiert -
  Severity-Texte, Badge-Beschriftungen, Tile-Hints. DE-Dict-Eintraege
  fuer `Bug`, `Code Smell`, `Vulnerability`, `Security Hotspot`,
  `Code Duplication`, `Read Error`.
- **`TLeakFinding.SeverityText` / `TypeText`**: Source-Strings auf
  Englisch (Konvention von `uLocalization`), DE-Mapping ueber
  Dictionary. Falls `analyser.ini [UI]/Language=de`, wird in der UI
  automatisch `Fehler`/`Warnung`/`Hinweis` angezeigt.

### Bekannte Einschraenkungen

- **`%%`-Heuristik im Bare-Style** ist konservativ: jedes `%` zaehlt
  unabhaengig vom Kontext. Bei sehr exotischen mORMot-Patterns (z.B.
  `FormatUtf8('%' + Var, [x])`) kann der Detector daneben liegen wenn
  `Var` zur Compile-Zeit ein `%` enthaelt - aber das ist a) Bare-Style-
  konform (mORMot wuerde es auch falsch interpretieren) und b) schwer
  statisch zu erkennen.
- **Bare-Style-Funktionsliste** ist hardcoded auf
  `formatutf8`/`formatstring`/`stringformatutf8`. Falls weitere mORMot-
  Helpers (`StringFormatBuffer`, `FormatShort`, `FormatToShort`) auf-
  tauchen, in `BARE_STYLE_FUNCS` ergaenzen. Optional spaeter via
  `[Detectors] BareFormatFunctions=...` konfigurierbar machen.

### Upgrade von v0.7.1

- **Keine Source-Aenderungen** im User-Code noetig. Alle Detector-Fixes
  sind reine Engine-Verbesserungen.
- **IDE-Plugin Layout** identisch zu v0.7.1 (3-Stufen NARROW/MEDIUM/FULL),
  nur intern auf den zentralen Controller umgebaut. Keine User-
  sichtbaren Aenderungen.
- **`analyser.ini`-Konfiguration** unveraendert. `[Detectors]
  FormatFunctions` aus v0.7.1 funktioniert weiterhin - die Bare-Style-
  Erkennung erfolgt orthogonal ueber den Funktionsnamen.
- **HTML-/JSON-/CSV-Exporte** unveraendert.
- **Bestehende Suppressions, `ignore.txt`-Eintraege, Custom-LeakyClasses,
  Severity-Konfiguration** bleiben gueltig.

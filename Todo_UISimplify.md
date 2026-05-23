# Todo — IDE-Plugin UI-Vereinfachung

> Branch: `setTheme` · Stand: 2026-05-23
>
> Ziel: UI-Aufbau des Analyser-Frames vereinfachen, **ohne** Ansicht oder
> Funktionalität zu ändern. Erst beschreiben + Probleme katalogisieren,
> dann gezielt refaktorieren.

---

## 1. Wie ist die UI aktuell aufgebaut?

Der Plugin-Frame `TAnalyserFrame` (in [uIDEAnalyserForm.pas](StaticCodeAnalyserIDE/uIDEAnalyserForm.pas)) ist ein TFrame, das die IDE in ein Host-TForm einbettet. Das Frame ist horizontal in 5 alTop-Streifen + 1 alClient + 1 alBottom-Streifen aufgeteilt:

```
+--------------------------------------------------+
| FPanelStats     [alTop  — 9 Tile-Kacheln]        |
+--------------------------------------------------+
| PanelPath       [alTop  — Project Path]          |
+--------------------------------------------------+
| PanelButtons    [alTop  — Severity + Type]       |
+--------------------------------------------------+
| PanelSearch     [alTop  — Actions + Search + Export] |
+--------------------------------------------------+
| PanelClient     [alClient — Grid + Help-Panel]   |
| +------------------+----+-----------------------+ |
| |                  |    |                       | |
| |  FResultGrid     | Sp |  FHintPanel           | |
| |  (alClient)      | li |  (alRight, optional)  | |
| |                  | tt |                       | |
| |                  | er |                       | |
| +------------------+----+-----------------------+ |
+--------------------------------------------------+
| FProgressBar    [alBottom]                       |
+--------------------------------------------------+
| FStatusBar      [alBottom — 3 Panels]            |
+--------------------------------------------------+
```

**Z-Order-Trick:** alTop-Panels werden in beliebiger Code-Reihenfolge
erstellt (zuerst PanelPath, dann PanelButtons, dann PanelSearch, zuletzt
FPanelStats), dann mit `BringToFront`-Aufrufen in die gewünschte
Top-to-Bottom-Sichtreihenfolge gebracht. alTop dockt vom zuletzt-
hervorgebrachten Element nach oben.

---

## 2. Parent-Client-Diagramm (komplett)

```
TAnalyserFrame [TFrame] · Color=IDE_BG_CHROME · DoubleBuffered=True
│
├── FPanelStats [TPanel · alTop · ParentBackground=False · Color=IDE_BG_CHROME]
│   └── 9× Tile [TTilePanel · alLeft]
│       ├── TopRow [TPanel · alTop]
│       │   ├── IconLbl [TLabel · alLeft · Segoe Fluent Icons]
│       │   └── CountLbl [TLabel · alClient · Bold]
│       └── CapLbl [TLabel · alClient · 7pt · IDE_FG_DIM]
│
├── PanelPath [TPanel · alTop · ToolbarRowH] ────────────────────────── FPanelPath
│   ├── LblPath        [TLabel  · alLeft   · "Project path:"]
│   ├── FProjectPath   [TComboBox · alClient · csDropDown · Segoe UI 8]
│   ├── FBtnBrowse     [TButton · alRight  · "..."]
│   ├── FBtnIgnore     [TButton · alRight  · "Ignore..."]
│   └── FBtnRepo       [TButton · alRight  · "Settings..."]
│
├── PanelButtons [TPanel · alTop · ToolbarRowH] ─────────────────────── FPanelButtons
│   ├── FPanelSev    [TPanel · alLeft · LBL_W_FILTER+CMB_W_FILTER]
│   │   ├── FLblFilter   [TLabel  · alLeft   · "Severity:"]
│   │   └── FFilterCombo [TComboBox · alClient · 71 Items]
│   ├── (Spacer)     [TPanel · alLeft · TB_SPACER_WIDTH]
│   └── FPanelType   [TPanel · alLeft · LBL_W_TYPE+CMB_W_TYPE]
│       ├── FLblType  [TLabel  · alLeft   · "Type:"]
│       └── FTypeCombo[TComboBox · alClient · 6 Items]
│
├── PanelSearch [TPanel · alTop · ToolbarRowH] ──────────────────────── FPanelSearch
│   ├── FPanelProfile [TPanel · alLeft]
│   │   ├── FLblProfile   [TLabel · alLeft · "Profile:"]
│   │   └── FProfileCombo [TComboBox · alClient · ide-fast/default/strict]
│   ├── (Spacer)         [TPanel · alLeft]
│   ├── FBtnAnalyseChanged [TButton · alLeft · ⎇]
│   ├── FBtnAnalyse        [TButton · alLeft · "▶ Analyse"]
│   ├── FBtnAnalyseCurrent [TButton · alLeft · "📄 File"]
│   ├── (Spacer)         [TPanel · alLeft]
│   ├── FLblSearch       [TLabel  · alLeft  · "Search:"]
│   ├── FSearchEdit      [TEdit   · alClient · TextHint]
│   ├── FBtnExport       [TButton · alRight · "Export ▼" — PopupMenu]
│   ├── FBtnCancel       [TButton · alRight · "Cancel"  · Margin links]
│   └── FBtnHamburger    [TButton · alRight · ☰ — PopupMenu]
│
├── PanelClient [TPanel · alClient]
│   ├── FHintPanel [TFindingHintPanel = TComponent — kapselt:]
│   │   ├── FHelpPanel       [TPanel    · alRight · MinWidth=180]
│   │   │   ├── HelpLeftSep   [TPanel   · alLeft · 1px · IDE_SEPARATOR]
│   │   │   ├── FHelpDescLabel[TLabel   · alTop  · Caption "Select a row..."]
│   │   │   └── HelpCode       [TPanel · alClient]
│   │   │       ├── FHelpBeforePanel [TPanel · alTop · Height=150]
│   │   │       │   ├── LblBefore   [TLabel · alTop · "Before"]
│   │   │       │   └── FHelpBefore [TMemo · alClient · Consolas · IDE_BG_CONTENT]
│   │   │       ├── BeforeAfterSplitter [TSplitter · alTop · 4px]
│   │   │       └── HelpAfterPanel    [TPanel · alClient]
│   │   │           ├── LblAfter    [TLabel · alTop · "After"]
│   │   │           └── FHelpAfter  [TMemo · alClient · Consolas · IDE_BG_CONTENT]
│   │   └── FHelpSplitter    [TSplitter · alRight · 4px · IDE_SEPARATOR]
│   └── FResultGrid [TStringGrid · alClient · DoubleBuffered=True · 6 Cols · Virtual]
│       └── (Tooltip-Subclass via TFindingGridTooltip)
│
├── FProgressBar [TProgressBar · alBottom · 0..100]
│
└── FStatusBar [TAnalyserStatusBar — kapselt:]
    └── FBar [TStatusBar · alBottom · 3 Panels: Findings/Progress/Mode]
```

**Stats-Tile-Anzahl-Korrektur**: 9 Tiles laut `TStatsTilesBuilder.Build`
(Errors / Warnings / Hints / Read-errors / Bugs / Security / Duplicates /
Cyclomatic / Code Quality). Die `BREAKPOINT_FULL`-Schwelle blendet bei
weniger als 850 px ClientWidth einige Tiles aus.

---

## 3. Aktuelle Probleme

### P1 — Sub-Panel-Wrapper für Label+Combo
Drei Wrapper-Panels (FPanelSev, FPanelType, FPanelProfile) existieren nur
um die VCL-Quirk zu umgehen, dass TLabel (TGraphicControl) und TComboBox
(TWinControl) auf einem gemeinsamen alLeft-Parent in unterschiedlichen
Align-Passes positioniert werden. Konsequenz: **zusätzliche Hierarchie-Ebene
pro Label+Combo**, mehr Style-Hook-Bookkeeping, mehr Repaint-Aufwand.

### P2 — BringToFront-Reihenfolge ist verkehrte UI-Intuition
Constructor erstellt Toolbars in einer Reihenfolge (PanelPath → PanelButtons
→ PanelSearch → FPanelStats), aber die Sichtreihenfolge ist umgekehrt:
**FPanelStats oben, dann PanelPath**, etc. Erreicht durch 4
`BringToFront`-Calls am Ende. Ein neuer Toolbar-Streifen einzufügen ist
nicht-offensichtlich (man muss die Z-Order-Logik verstehen).

### P3 — PanelSearch mischt drei semantische Gruppen
Diese Zeile enthält **Aktionen** (▶ Analyse, 📄 File, ⎇ Branch),
**Konfiguration** (Profile-Combo), **Suche** (Search-Edit) und
**Output** (Export-Dropdown). Visuell durch Spacer getrennt, semantisch
aber inhomogen. Wenn der Frame schmal wird, hilft das Hamburger-Menü
nur teilweise, weil verschiedene Konzepte konkurrieren.

### P4 — Hamburger ist ein "Backup-Pfad" mit invertierter Sichtbarkeit
FBtnHamburger ist nur bei NARROW+MEDIUM sichtbar (FULL → versteckt), die
anderen Buttons sind FULL-only. Inverse Sichtbarkeit ist konzeptuell
schwer zu erfassen. Außerdem: das Hamburger-Menü wird *immer* gebaut
(BuildHamburgerMenu beim Frame-Open) auch wenn der User nie in NARROW
modus geht.

### P5 — Zwei TPanels für ProgressBar + StatusBar nebeneinander
Beide sind alBottom. ProgressBar liegt oberhalb der Statusbar (durch
Creation-Order). Das funktioniert, ist aber im Code nicht-explizit
(Reader muss VCL-alBottom-Stapel-Regel kennen).

### P6 — Statusbar-Panel-Breiten sind nicht DPI-skaliert
[uIDEStatusBar.pas:57-61](StaticCodeAnalyserForm/sources/UI/uIDEStatusBar.pas#L57-L61):
`Width := 160` / `220` / `5000`. Bei 200% DPI Skala bleibt der Text-Bereich
gleich breit (Punkte statt Pixel), aber die nicht-skalierten Werte fühlen
sich auf Hi-DPI-Displays zu schmal an.

### P7 — Stats-Tile-Hierarchie ist tief
Jedes Tile: TilePanel → TopRow → (IconLbl + CountLbl), + CapLbl.
Das sind 4 Controls pro Tile × 9 Tiles = **36 Controls** allein für die
Stats-Zeile. Theme-Switch invalidiert alle 36 → spürbarer Repaint.

### P8 — PanelClient ist ein redundanter Wrapper
PanelClient existiert nur als Parent für FResultGrid und das Help-Panel.
Beide könnten **direkt** auf das Frame als alClient bzw. alRight gehängt
werden — eine Layer-Ebene weniger. Constraint: der Help-Splitter braucht
einen gemeinsamen Container mit dem Grid für korrekte Splitter-Mechanik.

### P9 — Spacer als TPanel statt TBevel
Drei Spacer in den Toolbar-Zeilen sind leere TPanels (Color via Default
themed). Funktioniert, aber TBevel mit `Shape := bsSpacer` wäre semantisch
klarer + leichter (kein WindowHandle, kein Style-Hook nötig).

### P10 — FResponsive registriert 11 Controls
[uIDEAnalyserForm.pas:WireResponsiveLayout](StaticCodeAnalyserIDE/uIDEAnalyserForm.pas):
11 `RegisterCtrl`-Aufrufe steuern die Sichtbarkeit bei NARROW/MEDIUM/FULL.
Wenn jemand einen neuen Button hinzufügt, muss er an die Responsive-
Registrierung denken — kein Compiler-Hint wenn er es vergisst.

### P11 — Help-Panel hat 6 verschachtelte TPanel-Ebenen
FHelpPanel → HelpCode → FHelpBeforePanel → FHelpBefore. Für eine simple
"Before/After"-Anzeige mit Splitter dazwischen. Splitter-Mechanik braucht
nur 2 Panels mit alTop/alClient — die `FHelpBeforePanel`-Wrapper-Schicht
existiert vermutlich nur damit der Title-Label oben drin sitzt.

### P12 — `Color := clBtnFace` weiterhin auf FPanelStats explizit
[uIDEAnalyserForm.pas:888-889](StaticCodeAnalyserIDE/uIDEAnalyserForm.pas#L888-L889):
`FPanelStats.Color := IDE_BG_CHROME` + `FPanelStats.ParentBackground := False`.
Die Kombi ist nötig damit das Panel selbst clBtnFace malt (statt das Theme
durchzulassen). **Aber:** wenn ParentBackground=True wäre, würde Theme
das Panel paint'en — selbes Ergebnis. ParentBackground:=False ist hier
ein Rest aus einer früheren Iteration und könnte heute weg.

### P13 — Padding/Spacing per `ScaleW(TB_PADDING_LR)` etc. verstreut
DPI-Skalierungs-Aufrufe `ScaleW(CONST)` sind durchgehend nötig, weil die
Konstanten 96-DPI-Werte sind. Eine zentrale `Spacing.PadLR`-Property,
die ScaleW intern macht, würde die Call-Sites lesbarer machen.

---

## 4. Vereinfachungs-Konzepte (keine UI-Änderung)

### V1 — `BringToFront`-Reihenfolge eliminieren

Erzeuge die alTop-Panels **in der gewünschten Sichtreihenfolge**
(FPanelStats zuerst, dann PanelPath, dann PanelButtons, dann
PanelSearch). VCL dockt dann automatisch in genau dieser Reihenfolge an
den oberen Rand. → **4 `BringToFront`-Calls weg**, Code liest sich Top-to-Bottom.

**Risk:** Constraint — manche Controller (FAnalyseRunner, FAnalyseProgress)
brauchen ggf. dass bestimmte UI-Elemente vorher existieren. Reihenfolge
prüfen.

### V2 — Spacer-Panels → TBevel ohne Shape

```pascal
class function TIDEToolbar.CreateSpacer(...): TPanel;
```
wird zu
```pascal
class procedure TIDEToolbar.AddSpacer(AOwner: TComponent; ARow: TWinControl;
  AWidth: Integer);
```
mit TBevel als Spacer (oder einfach Padding ohne extra Control).
→ Pro Toolbar-Zeile **1 TPanel weniger**, ~3 Style-Hooks weniger.

**Risk:** TBevel verhält sich bei alLeft anders? Test nötig.

### V3 — PanelClient eliminieren

Grid + Help-Panel direkt auf das Frame:
- `FResultGrid.Parent := Self; FResultGrid.Align := alClient;`
- `FHintPanel.FHelpPanel.Parent := Self; .Align := alRight;`
- Splitter zwischen ihnen direkt aufs Frame.

→ **1 TPanel-Ebene weniger**, weniger Verschachtelung.

**Risk:** Splitter zwischen Grid (alClient) und HelpPanel (alRight) auf
demselben Frame — VCL erlaubt das, aber Splitter braucht explizite
Parent-Referenz.

### V4 — Statusbar-Panel-Breiten DPI-skalieren

`Width := 160` → `Width := ScaleByPPI(FBar, 160)`. Drei kleine Edits.
**Risk:** keiner.

### V5 — Hamburger lazy bauen

`BuildHamburgerMenu` erst beim ersten Klick auf den Hamburger-Button
aufrufen, nicht beim Frame-Constructor. Spart beim ersten Frame-Open
einen INI-Read + ein paar Items.

**Risk:** Wenn der User den Frame ganz schmal öffnet, ist Hamburger
sofort sichtbar und braucht das Menu. Trigger: beim Klick statt beim
Open — vertretbar.

### V6 — Help-Panel: HelpCode-Ebene auflösen

FHelpPanel direkt: HelpDescLabel (alTop) + FHelpBeforePanel (alTop) +
Splitter (alTop) + HelpAfterPanel (alClient). HelpCode-Wrapper weg.

**Risk:** Splitter-Bounds könnten anders aussehen. Layout-Test nötig.

### V7 — Stats-Tile-Caption als TopRow-Child statt eigener Layer

Aktuell: TilePanel → TopRow + CapLbl. Beide direkte Children.
Alternative: TilePanel → IconLbl + CountLbl + CapLbl (alle direkt),
manueller Bounds-Setzungs-Code im TilePanel.Paint. Komplexer Paint-Code
gegen einfachere Hierarchie — meist nicht den Aufwand wert.

**Decision:** Skip V7 — Hierarchie ist OK, nur ~36 Controls insgesamt.

### V8 — Responsive-Registrierung als Tabelle

Statt 11 einzelne `FResponsive.RegisterCtrl`-Calls:

```pascal
const
  RESPONSIVE_TABLE: array of TResponsiveEntry = (
    (Ctrl: @FBtnRepo;           Stages: [usFull]),
    (Ctrl: @FBtnIgnore;         Stages: [usFull]),
    (Ctrl: @FLblFilter;         Stages: [usMedium, usFull]),
    ...
  );
```
+ Schleife. Compact aber komplex; Risiko durch Pointer-zu-Field-Tricks.

**Decision:** Skip V8 — Aktuell-Form ist explizit und debugbar.

### V9 — FPanelStats.ParentBackground:=False entfernen

Wenn ohne diesen Flag das Panel korrekt themed paint'et (was bei
ParentBackground:=True der Fall sein sollte), kann der Flag weg.

**Risk:** Wenn TilePanel-Children mit `ParentBackground:=False` malen
und der Stats-Container ohne, gibt's keine sichtbare Naht.

---

## 5. Empfohlene Reihenfolge & Aufwand

| Schritt | Konzept | Aufwand | Wirkung |
|---|---|---|---|
| 1 | V1: `BringToFront` rauswerfen + Top-to-Bottom-Order | 15min | hohe Code-Lesbarkeit |
| 2 | V4: Statusbar-Width DPI-skalieren | 5min | Hi-DPI besseres Layout |
| 3 | V9: `FPanelStats.ParentBackground:=False` weg | 5min | Code-Sauberkeit |
| 4 | V3: PanelClient eliminieren | 20min | 1 Layer weniger |
| 5 | V6: HelpCode-Wrapper auflösen | 20min | 1 Layer weniger |
| 6 | V2: Spacer → TBevel | 15min | Style-Hook-Reduktion |
| 7 | V5: Hamburger lazy | 15min | Schnelleres Frame-Open |

**Gesamt:** ~1.5h Code + manueller IDE-Test pro Schritt.

---

## 6. Was bewusst nicht geändert wird

- **Sub-Panel-Wrapper für Label+Combo (P1)** — fix die VCL-Quirk, keine
  saubere Alternative ohne komplette Custom-Layout-Engine.
- **Inverse Hamburger-Sichtbarkeit (P4)** — User-Wunsch, FULL hat alle
  Buttons sichtbar, im schmalen Modus alles im Menu.
- **Help-Panel splittet vertikal (Before/After)** — Spec-Anforderung,
  Bottom-Up-Refactor nicht im Scope.
- **9 Stats-Tiles statt N** — designed um Sonar-Kategorien 1:1 abzubilden.
- **Statusbar mit 3 Panels** — separate Slots für Findings/Progress/Mode
  sind UI-Anforderung.

---

## 7. Akzeptanz-Tests pro Schritt (manuell, IDE-Plugin)

- [ ] T1: Frame öffnet sich mit unveränderter visueller Reihenfolge
       (Stats → Path → Buttons → Search → Grid → Progress → Status)
- [ ] T2: Spacer-Abstände identisch zur vorigen Version (Augenmaß-Vergleich)
- [ ] T3: Help-Panel öffnet/schließt korrekt via Float↔Dock-Wechsel
- [ ] T4: Splitter zwischen Grid und Help-Panel zieht beide Seiten richtig
- [ ] T5: Splitter Before/After zieht die zwei Memos richtig
- [ ] T6: Statusbar-Panels haben sinnvolle Breiten bei 100% / 150% / 200% DPI
- [ ] T7: Hamburger-Menü öffnet beim ersten Klick (lazy build) ohne
       sichtbare Verzögerung
- [ ] T8: Theme-Switch (Dark↔Light) → alle Tiles, Toolbar-Zeilen,
       Help-Panel folgen
- [ ] T9: Resize NARROW → MEDIUM → FULL → richtige Buttons sichtbar
- [ ] T10: Cold-Start im Dark-Theme → kein Light-Flash

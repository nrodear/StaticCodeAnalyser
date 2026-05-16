# Erledigte Aufgaben

Aus `TODO.md` verschobene, abgeschlossene Punkte. Strukturiert nach denselben
Kategorien wie das Original. Partielle (`[~]`) Punkte bleiben in `TODO.md`.

---

## 🔴 Bugs / Korrektheit (erledigt)

- [x] **`LoadRecentPaths` ohne `try…except` gegen korrupte INI** — _erledigt_
  `TForm2.LoadRecentPaths` und `TAnalyserFrame.LoadRecentPaths` umschließen
  jetzt den `TRecentPaths.Load`-Aufruf in try/except und leeren bei Fehler
  Items + Text. Defekte INI killt damit weder Plugin-Init noch Form-Create.
  Dateien: `UI/uMainForm.pas`, `StaticCodeAnalyserIDE/uIDEAnalyserForm.pas`.

- [x] **`uTodoComment.FindMarkerInComment` matcht in String-Literalen** — _erledigt_
  Neuer `ScanLineCommentStart`-Helper geht zeichenweise vor und überspringt
  `'…'`-Literale (inkl. doppelter `''`-Escape-Sequenzen). `var s := '// no
  comment'` triggert den Detektor jetzt nicht mehr.
  Datei: `Detectors/uTodoComment.pas:39-95`

- [x] **`uMainForm.NavigateDelphiToLine(0)` bei invalidem Input** — _erledigt_
  Pre-Check `if LineNo <= 0 then Exit;` direkt am Methodenanfang ergänzt
  (Belt-and-suspenders zur bestehenden Caller-Guard).
  Datei: `UI/uMainForm.pas:447`

- [x] **`uRegExMatches.GetName` Regex falsch (Char-Class statt Alternation)** — _erledigt_
  `[procedure|function|...]` war eine Character-Class (matchte ein
  einzelnes Zeichen aus dem Set, `|` bedeutungslos). Jetzt
  `(?:procedure|function|constructor|destructor|operator)` als echte
  Non-Capture-Alternation.
  Datei: `Common/uRegExMatches.pas:83`

- [x] **`uRegExMatches.FCache` Thread-Race** — _erledigt_
  `FCache` wird jetzt im `initialization`-Block angelegt (kein Lazy-Init-
  Race mehr); `Cached(...)` serialisiert TryGetValue+Add via
  `TMonitor.Enter(FCache)/Exit`. Damit ist der Cache safe unter parallelem
  WatchMode-Worker + Main-Analyzer.
  Datei: `Common/uRegExMatches.pas:34-50`

- [x] **`uSQLInjectionScore.Estimate` uninitialisierte Result-Felder** — _erledigt_
  Score / Difficulty / Reason / Suggestion werden jetzt am Funktionsanfang
  defensiv mit Defaults initialisiert; der `case TotalPlus of 0`-Branch
  setzt zusätzlich beschreibende Reason/Suggestion-Texte. Damit kein
  leerer Detail-Text mehr in der Befund-Anzeige.
  Datei: `Detectors/uSQLInjectionScore.pas:117-160`

- [x] **`uVcsChanges` Stdout als ANSI dekodiert** — _erledigt_
  `StringBuilder` + per-Chunk-`StrPas` ersetzt durch `TBytesStream` +
  einmaliges `TEncoding.UTF8.GetString` am EOF. Damit weder ANSI-Mangling
  noch Chunk-Boundary-Korruption bei UTF-8-Multi-Byte-Sequenzen.
  `System.AnsiStrings` und unbenutztes `SB`-Local mit entfernt.
  Datei: `Infrastructure/uVcsChanges.pas:215-273`

- [x] **`uDivByZero` `varname = 0` als Guard fehl-interpretiert** — _erledigt_
  Equality-Branch in `HasGuardingIf` separiert: `varname = 0` schuetzt
  jetzt nur dann, wenn der THEN-Zweig direkt mit `Exit` oder `raise`
  endet (auch via `begin..end`). `if x=0 then DoOther` triggert die
  Warnung jetzt wieder. Neuer Helper `ThenBranchExitsOrRaises` walkt
  IfNode.Children, ueberspringt nkElseBranch, akzeptiert nkExit/nkRaise
  direkt oder als erstes Statement im nkBlock.
  Datei: `Detectors/uDivByZero.pas:118-156`

- [x] **`uLeakDetector2` Borrowed-Reference als Factory-Call** — _erledigt_
  Dotted-Pfad ohne `(` wird nicht mehr als Factory-Call gewertet:
  `list := obj.FList` / `list := SomeProperty` produzieren keine Leak-
  Warnung mehr. Trade-off: parameterlose Factory-Methoden
  (`TFoo.Singleton`) werden dadurch nicht mehr erkannt — False-Negative
  ist hier billiger als die alten False-Positives auf jeder Field-/
  Property-Zuweisung. Regressionstest:
  `Leak_AssignFromFieldDottedNoParens_NoFinding`.
  Datei: `Detectors/uLeakDetector2.pas:160-170`

- [x] **WatchMode `FResults` Double-Free wenn `Synchronize` raised** — _erledigt_
  `DeliverResults` snapshotet `FResults` in eine lokale Variable und
  setzt das Field SOFORT auf nil, bevor der Callback aufgerufen wird.
  Bei einer Exception mid-Callback sieht der Worker-`finally`
  FResults=nil und gibt nicht doppelt frei. Lokale Snapshot-Ref
  bleibt im Callback-Ownership.
  Datei: `StaticCodeAnalyserIDE/uIDEWatchMode.pas:274-294`

- [x] **IDE `OpenFileAtLine` / `AnalyseCurrentFileClick` AV-Pfade** — _erledigt_
  Komplette IDE-Editor-API-Aufrufe nach `uIDEEditorIntegration.TIDEEditor`
  ausgelagert. Alle drei `as`-Casts (`IOTAEditorServices`,
  `IOTAModuleServices`, `IOTAActionServices`) sind jetzt durch
  `Supports(...)` ersetzt; zusätzlich nil-Check auf `EditView.Buffer`
  vor dem Zugriff auf `Buffer.FileName`.
  `AnalyseCurrentFileClick` verwendet `TIDEEditor.TryGetCurrentPasFile`
  mit Status-Code-Result (cfrNoEditorService / cfrNoOpenView /
  cfrNotPascalFile) und ruft pro Status die passende Status-Bar-Meldung.
  Datei: `StaticCodeAnalyserIDE/uIDEEditorIntegration.pas`

- [x] **`TFindingHighlighter.DetachAll` löscht Tracking-Listen nicht** — _erledigt_
  Listen werden jetzt am Ende von `DetachAll` gecleart (alle drei:
  `FAttachedIntfRefs`, `FAttachedClassRefs`, `FAttachedFiles`). Damit
  ist ein Re-Attach nach Plugin-Reload möglich; vorher skipte
  `EnsureViewNotifier` den Re-Attach permanent.
  Datei: `StaticCodeAnalyserIDE/uIDELineHighlighter.pas:168-185`

- [x] **`RegisterDockableForm` `as`-Cast kann BPL-Load crashen** — _erledigt_
  Alle drei `BorlandIDEServices as INTAServices`-Casts in `Register-`,
  `Show-` und `UnregisterAnalyserDockableForm` durch `Supports(...)`
  ersetzt. RegisterAnalyserDockableForm bricht jetzt sauber ab BEVOR
  GDockableForm erzeugt wird, falls der Service nicht verfuegbar ist -
  damit kein halbinitialisierter State mehr.
  Datei: `StaticCodeAnalyserIDE/uIDEAnalyserForm.pas:1746-1815`

### Aus mORMot2-Real-World-Review (4-Agenten-Crosscheck)

- [x] **Parser: Interface-Deklarationen verloren** — _erledigt_
  `tkKwInterface`-Case in `ParseTypeSection` ergänzt; ruft
  `ParseClassBody` analog zu tkKwClass. Forward-Decl `IFoo = interface;`
  wird als Spezialfall behandelt. Die optionale GUID `['{...}']` und
  Parent-Liste werden im else-Next-Pfad benignly geskippt.
  Regressionstest: `Parser_InterfaceDecl_FollowingMethodLeakDetected`.
  Datei: `Parsing/uParser2.pas:475-525` (neue Cases)

- [x] **Parser: Generic-Typdeklarationen `TFoo<T> = class` verloren** — _erledigt_
  Neuer Helper `SkipGenericParams` mit Depth-Tracking (für nested
  `TList<TFoo>`); wird in `ParseTypeSection` direkt nach Typname
  eingefügt sowie an drei Stellen in `ParseMethodSignature` (vor Dot,
  nach qualifiziertem Namen, nach unqualifiziertem Methodennamen).
  Regressionstests: `Parser_GenericTypeDecl_MethodLeakDetected` +
  `Parser_GenericMethodSig_LeakDetected`.
  Datei: `Parsing/uParser2.pas:159-188` (Helper), `:466-468` (TypeSection),
  `:606-624` (MethodSignature)

- [x] **Parser: `packed record` / `packed class` verloren** — _erledigt_
  `Eat(tkKwPacked)` direkt vor dem class/record-Case in
  `ParseTypeSection` — eine Zeile reicht.
  Regressionstest: `Parser_PackedRecord_FollowingMethodLeakDetected`.
  Datei: `Parsing/uParser2.pas:471-472`

- [x] **Parser: `label`-Sektion vor `begin`** — _erledigt_
  `ParseLocalVarSection`-Outer-Loop akzeptiert jetzt zusätzlich
  `tkKwLabel` und skippt bis zum nächsten `;`. Goto-Labels werden nicht
  im AST getrackt — wir wollen nur den Body retten.
  Regressionstest: `Parser_LabelSection_BodyLeakDetected`.
  Datei: `Parsing/uParser2.pas:744-755`

- [x] **Parser: `record helper for X` / `class helper for X`** — _erledigt_
  Neuer Helper `SkipHelperFor` konsumiert die optionale Präambel
  `helper for <typename>` direkt nach `record` oder `class`, bevor
  `ParseClassBody` den Member-Block liest. Target-Typname kann
  Bezeichner, dotted (`Unit.Type`), `string`, oder `array of X` sein.
  Regressionstest: `Parser_ClassHelperFor_FollowingMethodLeakDetected`.
  Datei: `Parsing/uParser2.pas:190-216` (Helper),
  `:480, :493` (Aufrufe in tkKwClass und tkKwRecord)

- [x] **Parser: Conditional-Compilation duplizierte Method-Header** — _erledigt_
  In `ParseMethodImpl`: wenn nach Signature kein `begin`/`asm` folgt,
  sondern direkt das nächste Method-Keyword (procedure/function/
  constructor/destructor/operator), wird der just-added headless
  Knoten aus dem AST entfernt. Damit erscheint die Methode bei
  IFDEF-konditionalen Headers nicht mehr doppelt.
  Regressionstest: `Parser_IfdefDuplicatedHeaders_NoPhantomDuplicate`.
  Datei: `Parsing/uParser2.pas:737-756`

- [x] **Memory-Detektor: `CreateUtf8`/`CreateFmt`/`CreateAfterAttach` nicht erkannt** — _erledigt_
  Neuer Helper `TLeakDetector2.MatchesCreate(ATypeRef, ATypeLow, out CreatePos)`
  erkennt sowohl `.Create(...)` als auch CamelCase-Varianten anhand des
  Case des Folge-Zeichens im Original-TypeRef: Grossbuchstabe = Konstruktor-
  Suffix (`CreateUtf8`, `CreateFmt`, `CreateFromFile`, `CreateAfterAttach`),
  Kleinbuchstabe = Verb-Form (`creates`, `created` - Property/Field-Suffix).
  `HasCreateAssign` und `FindCreateLine` delegieren beide an den Helper.
  Regressionstests: `Leak_CreateUtf8_NoFree_ReportsError`,
  `Leak_CreateFmt_NoFree_ReportsError`,
  `Leak_DotCreatedProperty_NotConstructor_NoFinding`.
  Datei: `Detectors/uLeakDetector2.pas:138-186` (Helper + Refactor)

- [x] **Memory-Detektor: `IsPassedToOwner` "any .Add" zu breit** — _erledigt_
  Neuer Helper `AddReceiverOwnsItems` schaut den Receiver-Typ in den
  Local-Var-/Param-Deklarationen nach. Wenn der Typ aufloesbar ist UND
  einer ownership-bewussten Whitelist (`TObjectList`,
  `TObjectDictionary`, `TObjectQueue/Stack`, `TComponentList`,
  `TOwnedCollection`, `TInterfaceList`) entspricht -> ownership.
  Bei nicht-aufloesbarem Typ (Field `FList`, dotted `obj.Items`)
  bleibt das alte permissive Verhalten als Fallback - vermeidet
  Regression in haeufigen FList.Add-Mustern. `TSynList.Add` /
  `TRawUtf8List.Add` werden jetzt korrekt als nicht-ownership
  erkannt wenn der Typ in der Methode bekannt ist.
  Datei: `Detectors/uLeakDetector2.pas:299-365` (Helper),
  `:367-391` (.add-Branch in IsPassedToOwner)

- [x] **SQL-Detektor: safe-cast-Whitelist fuer `IntToStr` / `QuotedStr` / ...** — _erledigt_
  Neuer Helper `AllConcatTermsSafe` strippt String-Literale aus dem
  RHS und pruefte an jedem `+`-Operator den nachfolgenden Token. Wenn
  alle non-Literal-Terme Aufrufe einer safe-cast-Funktion sind
  (numerisch: `IntToStr`, `Int64ToStr`, `FormatInt`, `GetEnumName`;
  escape'd: `QuotedStr`, `QuotedSQL`, `QuotedStrJSON`, `SQLVarToText`),
  wird die Risiko-Heuristik vor H1/H2 unterdrueckt. Greift sowohl in
  `IsAssignRisk` als auch in `IsCallRisk`. Reduziert mORMot2-typische
  False-Positives auf `Sql.Add(' WHERE ID=' + Int64ToStr(id))`-Mustern.
  Datei: `Detectors/uSQLInjection.pas:131-220` (Helper),
  `:240-242, :271-273` (Wiring)

- [x] **HardcodedPath: UNC mit `_`/`-` im Servernamen verworfen** — _erledigt_
  CharSet im UNC-Servername-Branch um `'_'` und `'-'` erweitert
  (RFC 952/1123, gaengige interne Hostnamen). `\\my-srv\share` und
  `\\_internal\share` werden jetzt erkannt.
  Datei: `Detectors/uHardcodedPath.pas:43-46`

- [x] **FormatMismatch: Konstanten-basierte Format-Strings aufloesen** — _erledigt_
  Parser `ParseVarLikeSection` erweitert um Const-Initializer (Wert
  wird nach `=` an die TypeRef angehaengt). Detektor sammelt pro Unit
  alle untyped String-Const-Literale in eine `TDictionary<name, value>`
  via neue `CollectStringConstants`. `ResolveFormatString` schlaegt
  Identifier-Argumente in dieser Tabelle nach. `Format(MSG_INVALID, [a])`
  mit `const MSG_INVALID = 'invalid %s'` wird jetzt geprueft.
  Dateien: `Parsing/uParser2.pas:568-636`,
  `Detectors/uFormatMismatch.pas:CollectStringConstants/ResolveFormatString`

- [x] **FormatMismatch: konfigurierbare Format-Funktionsliste** — _erledigt_
  Neue globale `DetectorFormatFunctions: TStringList` in `uSCAConsts`
  (Defaults: `Format`, `FormatUtf8`, `FormatString`). `TRepoSettings`
  laedt `[Detectors] FormatFunctions=...` als CSV und spiegelt die
  Liste in `ApplyDetectorThresholds`. Detektor iteriert ueber alle
  konfigurierten Namen mit Wortgrenzen-Check. mORMot2-Idioms
  `FormatUtf8(...)` werden out-of-the-box geprueft; Projekt-Helpers
  (`_fmt`, `FmtUtf8`) per INI ergaenzbar.
  Dateien: `Common/uSCAConsts.pas`, `Infrastructure/uRepoSettings.pas`,
  `Detectors/uFormatMismatch.pas:FormatFunctionList/TryExtractCall`

- [x] **FormatMismatch: mORMot Bare-`%` + String-Konkatenation** — _erledigt_
  Drei zusammenhaengende False-Positive-Fixes nach Code-Reviews realer
  mORMot-2.4-Befunde:
  1. **Bare-`%`-Counting** fuer `FormatUtf8`/`FormatString`/`StringFormatUtf8`:
     diese Funktionen haben kein Type-Letter (kein `%s`/`%d`), nur `%`
     allein als Platzhalter. Neue `IsBareStyle`-Check + zweite Counting-
     Strategie in `CountPlaceholders(ABareStyle)`.
  2. **`%%` ist KEIN Escape im Bare-Style**: verifiziert via mORMot-Source
     (`mormot.core.text.pas:9616 TFormatUtf8.Parse`) - jedes `%` konsumiert
     ein Argument, `%%` = zwei aufeinanderfolgende Args ohne Trenner. Das
     ist absichtlich (mORMot-Code nutzt es z.B. um Where-Clauses zu
     kettenkonkatenieren). Standard-Style (RTL `Format`) bleibt unveraendert
     - dort ist `%%` weiterhin Escape.
  3. **String-Literal-Konkatenation `'a' + 'b'`**: Detector mergte vorher
     nur das ERSTE Literal -> mehrzeilige SQL-Strings wurden nur teilweise
     gepruft (False Positive). Neue Helper `ReadStringLiteral`/`SkipSpaces`
     loopen `+ '...'`-Fortsetzungen und akkumulieren in `Inner`.
  Effekt: 3 mORMot-Demo-Findings (`api.impl.pas:62/71/126`) verschwinden;
  ein echter Bug in `mormot.orm.rest.pas:1780` (9 Platzhalter vs 8 Args)
  wird jetzt korrekt gemeldet.
  Tests: `TTestFormatMismatchBareStyle` mit 5 neuen Cases (DoublePercent,
  ConcatenatedLiteral *2, StandardFormat-Regression, ...).
  Dateien: `Detectors/uFormatMismatch.pas`, `tests/uTestFormatMismatch.pas`

---

## 🟡 Robustheit (erledigt)

- [x] **`uParser2` Skip-Loops ohne GuardAdvance** — _erledigt_
  Z. 749 (lokaler var-Block-Skip) und Z. 893 (asm-Block-Skip) jetzt
  analog zur Z. 736-Korrektur mit `var SkipStart := FNextCount; …
  GuardAdvance(SkipStart);` umschlossen.

- [x] **`ParseTryStmt` O(n²) `Children.Delete(0)`** — _erledigt_
  Logik in `TAstNode.AdoptChildrenFrom` extrahiert: erst alle Refs in den
  Ziel-Knoten kopieren, dann den Source bulk-clearen → einmaliger O(n)
  statt n × O(n). Exception-sicher (keine Doppel-Frees, keine Leaks).
  Beide try-Transfer-Stellen in `ParseTryStmt` rufen jetzt nur noch
  `TryNode.AdoptChildrenFrom(TmpBlk)`.

- [x] **Docked-Mode UI: zuverlässige Anzeige notwendiger Bedienelemente** — _erledigt (Phase 1+2)_

  **Phase 1 (Stabilisieren) erledigt:**
  - Initial-State deterministisch via `FrameResize(Self)` am Constructor-
    Ende → `FResponsive.ForceUpdate` mit `FFirstApply=True` setzt
    Visibility EINMAL nach voll fertiger UI.
  - `FSearchEdit.Constraints.MinWidth` im Narrow auf 60 px (statt 120).
  - Branch-Changes als ⎇-Glyph-Button (32 px) statt Caption-Button
    (104 px) — PanelSearch passt jetzt in jede Stufe.
  - Frame.Constraints.MinWidth=500 + Propagation auf IDE-Host-Form
    (`GetParentForm` in `FrameCreated`) — schützt vor pathologisch
    schmalen Floats.

  **Phase 2 (Architektur) erledigt:**
  - `TResponsiveVisibilityController` (5 verteilte Instanzen über 4
    Panels) entfernt → ersetzt durch zentralen `TResponsiveLayoutController`
    in `uIDEStatsTiles.pas`. Eine Instanz pro Frame, hookt Frame.OnResize.
  - Deklarative Stage-Registrierung (vgl. ursprünglicher Phase-2-Vorschlag):
    ```
    FResp.RegisterCtrl(FBtnCancel,    usFull);            // nur FULL
    FResp.RegisterCtrl(FLblFilter,    usMedium);          // ab MEDIUM
    FResp.RegisterCtrl(FBtnHamburger, usNarrow, usMedium); // inverse
    ```
  - 3-Stufen-Layout (NARROW <500, MEDIUM 500-849, FULL ≥850 px) statt
    bisher 2-Stufen — Übergang vom Hamburger-Pattern zum vollen UI ist
    dadurch smoother.
  - `AfterApply`-Callback ersetzt das chained `OnResize`-Forwarding —
    Folge-Anpassungen (Sub-Panel-Widths, SearchEdit-MinWidth) laufen
    deterministisch nach jedem Apply.
  - `TToolbarSizing.Apply`/`ApplyIconButton`/`HeightForFont` löst die
    VCL-Quirk dass TComboBox `Align.Height` ignoriert — alle Toolbar-
    Components rendern jetzt uniform.
  - Sub-Panel-Container (PanelSev/PanelType) bleiben bewusst — `TFlowPanel`-
    Refactor war nicht nötig, der zentrale Controller war ausreichend.

  **Phase 3 + 4 nicht umgesetzt** — Two-Mode-UI und User-Prefs nicht
  notwendig, der responsive-Ansatz hat sich als beherrschbar erwiesen.

  Dateien: `uIDEAnalyserForm.pas`, `uIDEStatsTiles.pas`

- [x] **WatchMode dynamic module attach** — _erledigt, dann verworfen_
  War: `TFindingEditSvcNotifier.EditorViewActivated` -> `RescanOpenModules`
  fuer Auto-Attach an neu geoeffnete Dateien. Mit dem Single-File-Watch-
  Refactor (s.u.) entfallen, weil Watch nur noch eine Datei beobachtet.

- [x] **Auto-Single-File-Scan beim Editieren** — _erledigt, dann konsolidiert_
  War: separater INI-Key `[Detectors] AutoScanOnEdit=0/1`. Mit dem
  Single-File-Watch-Refactor (s.u.) entfallen - Live-Watch ist jetzt
  immer Save+Edit, ohne INI-Flag.

- [x] **Single-File-Live-Watch (Konsolidierung)** — _erledigt, RISKY_
  WatchMode + AutoScanOnEdit INI-Flags komplett entfernt. Live-Watch
  ist jetzt implizit an "Aktuelle Datei" gekoppelt: Klick aktiviert
  einen Single-Slot-Notifier auf genau diese Datei (Save 300 ms +
  Edit 1000 ms debounced). Tab-Wechsel auf andere Datei aendert nichts;
  erneuter "Aktuelle Datei"-Klick haengt den Notifier um. Bulk-Pfade
  (Full-Project, Branch-Changes) deaktivieren den Watch explizit.
  Dateien: `Infrastructure/uRepoSettings.pas` (Flags + INI-Doc raus),
  `StaticCodeAnalyserIDE/uIDEWatchMode.pas` (Single-Slot statt Listen,
  AttachToWatchedFile/DetachWatched, EditorViewActivated -> No-op),
  `uIDEAnalyserForm.pas` (`PrepareAnalysis(const AWatchedFile: string)`).
  **!!! RISIKO Endlosschleife !!!** Heute kein Re-Entrancy-Guard fuer
  ueberlappende Spawns. Bei langsamen Workers / aktivem Tippen kann
  der Worker-Backlog wachsen, oder Editor-Repaint nach Findings-Update
  triggert (Delphi-version-abhaengig) wieder Modified. Vor breitem
  Default-On unbedingt erst:
    - Re-Entrancy-Guard (kein Spawn solange Worker laeuft)
    - Hard-Cap (max 1 Spawn / N Sekunden)
    - oder echten Cancel-Token (siehe Eintrag "WatchMode echtes
      Cancel-Token")
  Header in `uIDEWatchMode.pas` traegt warning-Block.

- [x] **`uSuppression.BuildMap` TargetLine bei EOF** — _erledigt_
  Default `TargetLine := i+2` auf `-1` geaendert; Map-Eintrag wird nur
  noch emittiert wenn die Inner-Loop eine echte Code-Zeile findet
  (`if TargetLine > 0 then ...`). Suppression-Marker am Datei-Ende
  ohne folgende Code-Zeile produzieren keine geistige Map-Eintraege
  mehr.
  Datei: `Infrastructure/uSuppression.pas:134-152`

- [x] **`uLexer.ScanNext` falsches Zeichen im Unknown-Branch** — _erledigt_
  `var UnknownCh := CurChar` Snapshot VOR Advance; danach
  `MakeTok(tkUnknown, UnknownCh, ...)`. Token enthaelt jetzt das
  korrekte (unbekannte) Zeichen statt das nachfolgende.
  Datei: `Parsing/uLexer.pas:523-530`

- [x] **`uLexer.ReadString` `#nn`-Range-Overflow** — _erledigt_
  Range-Validierung [0..$FFFF] vor `Chr`-Aufruf. Ausserhalb-Bereich
  (Astral-Plane, ueberlanges Numeral) -> U+FFFD (REPLACEMENT
  CHARACTER) statt RangeError-Crash. Lexer bleibt stabil bei
  pathologischen Inputs wie `#1000000`.
  Datei: `Parsing/uLexer.pas:343-362`

---

## 🟢 Wartbarkeit / Refactoring (erledigt)

- [x] **`uMainForm` Code-Duplikation mit IDE-Plugin** — _erledigt_
  - [x] `LoadRecentPaths`/`SaveRecentPath` extrahiert in
    `Common/uRecentPaths.pas` (TRecentPaths). Beide Forms rufen jetzt
    `TRecentPaths.Load`/`TRecentPaths.Save` mit konfigurierbarem Pinned-
    Eintrag (IDE-Projekt vs. App-Pfad, Position konfigurierbar).
    Behebt nebenbei `MAX_RECENT`-Drift und den `SaveRecentPath`-IDE-Bug
    (IDE-Projekt wurde in INI geschrieben).
  - [x] `ResultGridDrawCell` extrahiert in `UI/uFindingGridRenderer.pas`
    als gemeinsamer Renderer mit Config-Record (`StandaloneConfig` /
    `IDEConfig`). IDE und Standalone delegieren beide auf
    `TFindingGridRenderer.DrawCell`. Spaltenpositionen, Theme-Modus,
    Sort-Indicator, Zebra, Accent-Bar, Bold-File-Spalte, Ellipsis sind
    alle pro-Aufrufer konfigurierbar.

- [x] **Legacy-Parser-Pipeline entfernt** _(erledigt, finalisiert)_
  Standalone-„Analyse starten" rief frueher `TStaticAnalyzer.AnalyzeAllClasses
  Recursive` auf (Line-Scanner via `uParser`, nur MemoryLeak + EmptyExcept).
  Jetzt: ruft `TStaticAnalyzer2.AnalyzeLeaksRecursive` — dieselbe AST-Pipeline
  wie „Aktuelle Datei" und das IDE-Plugin, alle 21 Detektoren.
  Geloeschte Files: `uParser.pas`, `uStaticAnalyzer.pas`,
  `uLeakDetector.pas`, `uCodeSmells.pas` (TEmptyExceptDetector legacy
  - Ersatz ist `uCodeSmells2.TEmptyExceptDetector2`). Build-Files
  (DPR/DPK + beide DPROJ) komplett aufgeraeumt.

- [x] **`uParser.AV` bei `CurrentMethod = nil`** — _erledigt_
  Reproduzierbar in `mormot.crypt.x509.pas` (~152 KB, viele Methoden mit
  var-Sektionen, globale `var`-Bloecke in implementation): `isSectionMethod`
  konnte `True` werden, waehrend `CurrentMethod` durch den Lookahead-Pfad
  bereits genullt war. Z. 160 `CurrentMethod.SourceBody.Add(...)` -> AV
  $C0000005 mit Read of Address $14 (Field-Offset von SourceBody).
  Fix: `Assigned(CurrentMethod)`-Guard an Z. 122-123 und Z. 160 (analog
  Z. 150). Zusaetzlich `isSectionVar := false` im Lookahead-Reset, damit
  ein spaeteres `begin` nicht `isSectionMethod` auf einem nilligen
  `CurrentMethod` re-aktiviert.
  Datei: `Parsing/uParser.pas:118-132,159-188`

- [x] **`KindToName`/`KindFromName` Drift über vier Files** — _erledigt_
  Single source of truth: `KIND_META: array[TFindingKind] of
  TFindingKindMeta` in `uSCAConsts` (Record mit Name + FindingType).
  Plus drei convenience-Wrapper (`KindName`, `KindFindingType`,
  `KindFromName`). Die vorherigen 4 case-Switches sind jetzt thin
  delegates:
  - `uMethodd12.TLeakFinding.FindingType` → `KindFindingType(Kind)`
  - `uClaudePrompt.KindToName` → `KindName(K)`
  - `uExport.KindToName` → `KindName(Kind)`
  - `uSuppression.KindFromName` → `uSCAConsts.KindFromName(...)`
  Neuer `TFindingKind` braucht jetzt nur noch zwei Edits: Enum-Eintrag
  in `uSCAConsts` plus eine Zeile in `KIND_META` (gleiche Datei).

- [x] **`MAX_RECENT` doppelt definiert mit unterschiedlichen Werten** — _erledigt_
  Konsolidiert via `uRecentPaths.DEFAULT_MAX_RECENT = 3`. Beide Forms
  geben den Wert beim `TRecentPaths.Load/Save`-Aufruf mit; effektive
  Anzahl user-recent Pfade ist jetzt konsistent IDE = Standalone = 3.

- [x] **`SaveRecentPath` schreibt IDE-Projekt-Eintrag in INI** — _erledigt_
  Behoben durch den Umzug nach `uRecentPaths`: `TRecentPaths.Save`
  ueberspringt den `PinnedPath` beim INI-Write per `SameText`-Check.
  Damit landet das aktuelle IDE-Projekt nicht mehr in der INI -> beim
  naechsten Start kein Duplikat mehr in der MRU-Liste.

- [x] **`uIDEMessages.SeverityPrefix` hardcoded deutsch** — _erledigt_
  Strings durch `_()` geleitet (Source-Form jetzt englisch:
  `Error / Warning / Hint / Info`). Lokalisierbar via dxgettext +
  zentralem `SetLanguage`. Header-Doku entsprechend angepasst.
  Datei: `StaticCodeAnalyserIDE/uIDEMessages.pas:44-58`

- [x] **`uAnalyserTypes` String-Discriminator-Boundary entkoppelt** — _erledigt_
  Neuer Pfad `SeverityFromKindLevel(Kind, Severity): TFindingSeverity`
  mappt direkt vom internen Enum aufs Display-Enum, ohne String-
  Roundtrip. Die zwei high-volume Call-Sites
  (`uIDEAnalyserForm.UpdateHelp` + `TFindingFilter.Matches`) nutzen
  jetzt den enum-direkten Pfad.
  Restliche `SeverityFromText`-Aufrufer (Grid-Renderer + Sort-Comparer)
  brauchen den String-Pfad weil sie Cell-Inhalte zurueckparsen — der
  ist jetzt **locale-tolerant**: erkennt sowohl deutsche (`Fehler`)
  als auch englische (`Error`) Schreibweise. Damit ist der latente
  i18n-Bug ("Filter brechen wenn UI englisch") strukturell gefixt.
  Datei: `UI/uAnalyserTypes.pas`

---

## 🚀 Console-Mode / CI-Integration (erledigt)

- [x] **Headless-CLI-Mode für `analyser.d12.exe`** — _erledigt in v0.8.0_
  Aktuell GUI-only. Für CI-Pipelines: nicht-interaktiver Modus mit
  Exit-Code, Report-Output und Branch-Mode.

  Geplante Aufrufe:
  ```
  analyser.exe --path D:\repo --branch              # Branch-Diff (Git/SVN)
  analyser.exe --path D:\repo --full                # rekursiv
  analyser.exe --file MeineUnit.pas                 # Einzeldatei
  analyser.exe --path . --branch --report sca.json  # Report-Output
  ```

  Eigenschaften:
  - **Exit-Code-Konvention**: 0 = clean, 1 = Hints, 2 = Warnings, 3 =
    Errors, 4 = Read-Errors, 99 = Tool-Fehler. `--exit-on error|warn|hint`
    konfigurierbar.
  - **Quality-Gate-Flag**: `--max-errors 0 --max-warnings 5` →
    Pipeline-Fail wenn überschritten.
  - **VCS-Auto-Detect**: nutzt bestehenden `uVcsChanges`-Code für
    `--branch`. Setting für `--base-branch develop` durchreichbar.
  - **Stdout / `--quiet`**: tabellarische Befund-Liste auf stdout,
    `--quiet` unterdrückt alles außer Exit-Code.
  - **Locale**: `--lang en` / `--lang de` für Report-Sprache.
  - Datei: neue `Console/uConsoleRunner.pas` + Anpassung in
    `analyser.d12.dpr` (Args parsen, keine Form wenn CLI-Modus aktiv).

- [x] **GitHub-Action / GitLab-CI Beispielworkflows** — _erledigt in v0.8.0_
  `.github/workflows/sca.yml` ist im Repo; nutzt CLI + SARIF-Upload via
  `github/codeql-action/upload-sarif@v3`. GitLab-CI-Template noch offen.

- [x] **Detector-Rule-Catalog (`rules.json` als Single Source of Truth)** — _erledigt in v0.8.0_

  Foundation für SARIF-Export, GitHub Code-Scanning, externe Reporter
  und Doku-Generierung. Pro Detektor ein strukturierter Eintrag mit
  vollständiger Metadata - vorher liegt alles verstreut über
  `uSCAConsts.KIND_META`, `uFixHint`, `uLocalization` und Detector-
  Source-Comments.

  Schema (JSON):
  ```json
  {
    "rules": [
      {
        "id": "SCA001",
        "kind": "MemoryLeak",
        "name": "TObject created without try/finally",
        "shortDescription": "Object created but never freed",
        "fullDescription": "TObject.Create without protective try/finally...",
        "defaultSeverity": "Error",
        "type": "Bug",
        "tags": ["memory", "resource-leak"],
        "cwe": ["CWE-401"],
        "owasp": [],
        "configKey": "[Detectors] LeakyClasses",
        "fixHintRef": "uFixHint.MakeMemoryLeakHint",
        "detectorUnit": "uLeakDetector2.pas",
        "examples": {
          "bad":  "list := TStringList.Create; DoStuff(list); // no Free!",
          "good": "list := TStringList.Create; try DoStuff(list); finally list.Free; end;"
        },
        "addedInVersion": "0.1.0",
        "i18nKey": "rule.memoryleak.description"
      }
    ]
  }
  ```

  Pro Detektor abgedeckt (24 Regeln nach v0.7.2):
  | ID | Kind | Detector-Unit | Severity-Default |
  |---|---|---|---|
  | SCA001 | MemoryLeak | `uLeakDetector2.pas` | Error |
  | SCA002 | EmptyExcept | `uCodeSmells2.pas` | Warning |
  | SCA003 | SQLInjection | `uSQLInjection.pas` | Error |
  | SCA004 | HardcodedSecret | `uHardcodedSecret.pas` | Error |
  | SCA005 | FormatMismatch | `uFormatMismatch.pas` | Error |
  | SCA006 | FileReadError | (Parser-Error) | Error |
  | SCA007 | UnusedUses | `uUnusedUses.pas` | Hint |
  | SCA008 | NilDeref | `uNilDeref.pas` | Warning |
  | SCA009 | MissingFinally | `uMissingFinally.pas` | Warning |
  | SCA010 | DivByZero | `uDivByZero.pas` | Warning |
  | SCA011 | DeadCode | `uDeadCode.pas` | Warning |
  | SCA012 | LongMethod | `uLongMethod.pas` | Hint |
  | SCA013 | LongParamList | `uLongParamList.pas` | Hint |
  | SCA014 | MagicNumber | `uMagicNumbers.pas` | Hint |
  | SCA015 | DuplicateString | `uDuplicateString.pas` | Hint |
  | SCA016 | HardcodedPath | `uHardcodedPath.pas` | Warning |
  | SCA017 | DebugOutput | `uDebugOutput.pas` | Warning |
  | SCA018 | DeepNesting | `uDeepNesting.pas` | Hint |
  | SCA019 | TodoComment | `uTodoComment.pas` | Hint |
  | SCA020 | EmptyMethod | `uEmptyMethod.pas` | Hint |
  | SCA021 | DuplicateBlock | `uDuplicateBlock.pas` | Hint |
  | SCA022 | CyclomaticComplexity | `uCyclomaticComplexity.pas` | Hint |
  | SCA023 | FieldLeak | `uFieldLeak.pas` | Warning |
  | SCA024 | SQLInjectionScore | `uSQLInjectionScore.pas` | (Score) |

  Neue Datei: `rules/sca-rules.json` (im Repo). Validiert via JSON-
  Schema. Generator-Tool `tools/gen-rules-md.py` erzeugt daraus
  Doku-Pages (`docs/rules/SCA001.md`, ...). Detector-Code referenziert
  Rule-ID konsistent (statt nur fkXxx-Enum).

- [x] **SARIF v2.1.0 Export-Format** — _erledigt in v0.8.0_

  GitHub Code-Scanning + Azure DevOps + Visual Studio Code lesen SARIF
  nativ. Findings erscheinen direkt im PR (Inline-Annotations) und in
  GitHub Security-Tab. Voraussetzung: Rule-Catalog (s.o.) damit
  `runs[0].tool.driver.rules[]` befüllbar ist.

  Aufruf: `analyser.exe --path . --branch --report-sarif sca.sarif`

  Output-Schema (Auszug):
  ```json
  {
    "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
    "version": "2.1.0",
    "runs": [{
      "tool": {
        "driver": {
          "name": "StaticCodeAnalyser",
          "version": "0.7.2",
          "informationUri": "https://github.com/nrodear/StaticCodeAnalyser",
          "rules": [
            { "id": "SCA001", "name": "MemoryLeak",
              "shortDescription": { "text": "Object created without Free" },
              "defaultConfiguration": { "level": "error" },
              "properties": { "tags": ["memory"] } }
          ]
        }
      },
      "results": [{
        "ruleId": "SCA001",
        "level": "error",
        "message": { "text": "list2 created but never freed" },
        "locations": [{
          "physicalLocation": {
            "artifactLocation": { "uri": "src/MyUnit.pas" },
            "region": { "startLine": 42 }
          }
        }],
        "partialFingerprints": {
          "primaryLocationLineHash": "<sha256 of file+line+rule>"
        }
      }]
    }]
  }
  ```

  Implementation:
  - Datei: `Output/uExportSARIF.pas` (neu, nutzt `System.JSON`).
  - `partialFingerprints` damit GitHub Findings über Commits hinweg
    deduplicated (Baseline-File-aequivalent built-in in GitHub).
  - Repo-relative Pfade (Dateipfade ggue base-dir machen, sonst greift
    GitHub's File-Annotation nicht).
  - Tests: `uTestExportSARIF` mit JSON-Schema-Validation gegen die
    offizielle SARIF-2.1.0-Schema-Datei.

  GitHub-Workflow-Beispiel:
  ```yaml
  - name: Static Code Analysis
    run: ./analyser.exe --path . --branch --report-sarif sca.sarif
  - uses: github/codeql-action/upload-sarif@v3
    with:
      sarif_file: sca.sarif
      category: delphi-sca
  ```

- [x] **YAML-Ruleset für Custom Rules (External-Rule-Engine)** — _erledigt in v0.9.0_

  Power-User-Feature: Regex- oder Pattern-basierte Custom-Rules ohne
  Recompile des Analyzers definieren. Ergaenzt die hardcoded Detector-
  Liste um Projekt-/Team-spezifische Konventionen.

  Format: `analyser-rules.yml` im Projekt-Root oder via
  `--custom-rules path/rules.yml`-Flag.

  **Implementiert**:
  - `Common/uYamlSubsetParser.pas` (statt geplantem `uCustomRuleParser`):
    YAML-Subset-Parser fuer Block-Mappings, Block-Sequences, Quoting
    (single + double mit Escapes), Line-Comments. Kein Flow-Style,
    keine Anchors - reicht fuer Rule-Files.
  - `Detectors/uCustomRuleDetector.pas`: Pattern-Engine mit substring/
    regex/word Matching, Glob-basiertes file-include/file-exclude
    (eigener Glob-zu-Regex-Konverter mit `**`-Support, weil
    `System.Masks.MatchesMask` nur `*` kennt).
  - `examples/analyser-rules.yml`: Vorlage mit 4 dokumentierten Beispielen.
  - `examples/profile-strict.yml` (10 Regeln): Coding-Style-Konventionen.
  - `examples/profile-security.yml` (11 Regeln): CWE-Refs, Web/Crypto/IO.
  - `examples/profile-legacy-migration.yml` (12 Regeln, alle hint):
    ADO->FireDAC, Indy->THTTPClient, alte File-API ablösen.
  - `examples/README.md`: Profile-Uebersicht + How-To.
  - Tests `uTestYamlSubsetParser` (13 Cases) + `uTestCustomRuleDetector`
    (11 Cases inkl. Glob-Pattern-Edge-Cases).
  - `TLeakFinding.RuleID` neues Feld + neuer `fkCustomRule`-Kind.
  - SARIF-Export bevorzugt `F.RuleID` ueber Catalog-Lookup -
    Custom-IDs (PROJ001, STRICT001, ...) erscheinen 1:1 in
    GitHub Code-Scanning.
  - CLI: `--custom-rules <yml>`-Flag in `uConsoleRunner`.
  - Plugin/GUI: `[Detectors] CustomRulesFile=...` in `analyser.ini`,
    relative Pfade werden 4-stufig aufgeloest (Absolut -> ProjectRoot
    -> ConfigDir -> ExeDir).

  **NICHT implementiert** (fuer v0.9.x):
  - Target-Filtering (`identifier` / `comment` / `string-literal`):
    aktuell wird jedes Pattern auf den vollen Zeileninhalt angewandt.
    Echte Target-Filterung braucht AST-Integration, ist nicht trivial.
    Workaround: User nutzt `pattern-type: word` fuer Identifier-Match
    und schreibt Comment-/String-Patterns explizit (z.B. `'^//'`).

  ```yaml
  version: 1
  rules:
    - id: PROJ001
      name: "kein TADOQuery erlaubt"
      description: "Wir nutzen FireDAC - kein TADOQuery in Neucode"
      severity: error
      type: code-smell
      pattern: "\\bTADOQuery\\b"
      pattern-type: regex                # regex | substring | word
      target: identifier                  # identifier | comment | string-literal | any
      message: "Use TFDQuery from FireDAC instead of TADOQuery"
      fix-hint: |
        Replace 'TADOQuery' with 'TFDQuery' and add FireDAC.Comp.Client to uses.

    - id: PROJ002
      name: "deutsche Umlaute in Bezeichnern"
      description: "Identifier müssen ASCII-only sein (CI-Convention)"
      severity: warning
      type: code-smell
      pattern: '[a-zA-Z_]\w*[äöüÄÖÜß]\w*'
      pattern-type: regex
      target: identifier
      message: "Identifier contains non-ASCII characters"

    - id: PROJ003
      name: "kein Sleep() in Production-Units"
      severity: warning
      type: bug
      pattern: "Sleep("
      pattern-type: substring
      target: any
      file-include:
        - "src/production/**/*.pas"
      file-exclude:
        - "src/production/**/*Test*.pas"
      message: "Sleep() blocks the thread - use TTimer or async instead"
  ```

  Engine: Python wäre overkill - lieber **integriert in den Delphi-
  Analyzer**, parsed YAML via z.B. `mORMot YAML` oder einen schlanken
  eigenen Parser (YAML-Subset reicht). Detector-Klasse
  `TCustomRuleDetector.AnalyzeUnit` läuft die Regeln gegen die UnitNode.

  Output identisch zu hardcoded Rules (gleiche `TLeakFinding`-Struktur,
  gleicher SARIF-Export). Custom-Rule-IDs (`PROJ001`...) erscheinen in
  SARIF/HTML/JSON-Output 1:1.

  Datei-Inventar:
  - `Detectors/uCustomRuleDetector.pas` (neu)
  - `Common/uCustomRuleParser.pas` (neu, YAML-Subset-Parser)
  - `examples/analyser-rules.yml` (Vorlage mit kommentierten Beispielen)
  - Tests: `uTestCustomRuleDetector` mit 8-10 Cases (regex/substring/
    word, target-Selectors, file-include/exclude, Edge-Cases).

  Vorteil: Teams können in 5 Minuten eine Code-Convention durchsetzen
  ohne den Analyzer-Code anzufassen. Pattern-basiert ist schwächer als
  AST-basiert (False-Positive-Risiko bei Regex), reicht aber fuer
  ~80% der Team-Conventions (Verbotene Imports, Naming-Patterns,
  deprecated APIs).

---

## 💡 Features / Erweiterungen (erledigt)

- [x] **Standalone-Form an IDE-Plugin-UI angeglichen** — _erledigt_
  Standalone-Form hostet jetzt die gleichen geteilten UI-Helfer wie das
  Plugin-Frame:
  - **Toolbar**: 3 Panel-Rows (Path / Filter / Action). Filter-Row mit
    Severity-Combo (Display-Filter), Type-Combo, Profile-Combo, Min-
    Severity-Combo, Search-Edit. Action-Row mit Analyse file / directory /
    Branch / Save / Quit.
  - **Stats-Tile-Reihe** oberhalb der Form ueber `TStatsTilesBuilder.Build`
    aus `uIDEStatsTiles` - die gleichen 9 Sonar-Style Tiles wie im Plugin,
    1:1 Quality-Score-Gewichte.
  - **Hint-Panel** rechts vom Grid via `TFindingHintPanel` (`uIDEHelpPanel`)
    mit Before/After-Code-Beispielen. Neuer `AAlwaysVisible`-Ctor-Parameter
    deaktiviert die IDE-Plugin-Auto-Hide-Logik (Standalone-Form hat keinen
    Dock-Container).
  - **3-Panel-StatusBar** (Findings / Progress / Mode) - SimplePanel=False,
    `SimpleText`-Writes umgeleitet auf `Panels[2].Text` (Mode-Panel).
  - **Display-Filter**: `ApplyFilter` via `uFindingFilter.TFindingFilter.Matches`
    schreibt `FDisplayedFindings`-Subset; ResultGridClick mappt jetzt auf
    `FDisplayedFindings[row-1]` damit Filter-Auswahl konsistent ist.
  - **Branch-Changes-Button**: `TVcsChanges.GetChangedPasFilesAuto` analog
    zum IDE-Plugin (Git/SVN-Auto-Detect, nur geaenderte .pas analysiert).
  - **CLI**: `--profile <name>` + `--min-severity <level>` via
    `uConsoleRunner`. Apply ueber `ApplyDetectorThresholds` jetzt fuer
    ALLE Modi (vorher nur Branch). `[Rules] Profile/MinSeverity` aus INI
    plus CLI-Overrides.
  - **GUI-Konsole-Fix**: `{$APPTYPE CONSOLE}` raus, `AttachConsole(
    ATTACH_PARENT_PROCESS)` im CLI-Pfad. Doppelklick zeigt KEINE schwarze
    Konsole mehr, CLI-Pfad hat trotzdem stdout/stderr/Exit-Codes.

  Projekt-Setup: `..\StaticCodeAnalyserIDE` als `DCC_UnitSearchPath`-Eintrag
  + DCCReferences fuer die importierten IOTA-freien Plugin-Units
  (`uIDEStatsTiles`, `uIDEHelpPanel`, `uFindingFilter`). DPR analog
  ergaenzt mit `unit in '...'`-Pfaden, damit der Compiler die Units auch
  ohne Search-Path-Refresh findet.

  Dateien: `analyser.d12.dpr/.dproj`, `UI/uMainForm.{pas,dfm}`,
  `Console/uConsoleRunner.pas`, `Infrastructure/uRepoSettings.pas`,
  `Common/uRuleCatalog.pas` (FindValue-Crash-Fix bei fehlendem owasp-Feld),
  `StaticCodeAnalyserIDE/uIDEHelpPanel.pas` (AlwaysVisible-Ctor-Param).

- [x] **Rule-Set-Profile + Min-Severity-Filter** — _erledigt_
  Detector-Subset jetzt steuerbar ueber `[Rules] Profile=...` + `MinSeverity=...`
  in `analyser.ini`. Bundled-Profile in `rules/sca-rules.json` unter `profiles`:
  - `ide-fast` (~20 Kinds, Default fuer IDE-Plugin) — nur Bugs+Vulns
  - `default` (alle Detektoren, Standalone-Default)
  - `strict` (alle + opt-in UsesCheck)
  - `security` (5 Kinds: SQLInjection, HardcodedSecret, HardcodedPath +
    DFM-Security)
  - `bugs-only` (~14 Kinds — fuer CI-Gate ohne Style-Rauschen)
  - `code-quality` (~24 Smells + Duplikate — Refactoring-Session)
  - `dfm-only` (20 Kinds — Form-/UI-Review)

  Eigene Profile koennen in `sca-rules.json` per Hand ergaenzt werden;
  `*` expandiert zu allen Kinds, weitere Tokens werden additiv hinzugefuegt.
  IDE-Plugin hat zusaetzlich eine Profile-Dropdown rechts neben Severity/Type
  in der Toolbar — Auswahl wird in `[Rules] IdeProfile` persistiert und ueber-
  schreibt die INI-Voreinstellung fuer die naechsten Runs.

  Implementierung:
  - Catalog-Lookup `TRuleCatalog.GetProfile(Name): TFindingKinds`
    + Profile-Block-Parser in `LoadFromJsonFile` (`*`-Expansion).
  - `LoadFallback` enthaelt alle bundled Profile als Pascal-Konstanten -
    Dropdown ist vollstaendig auch ohne erreichbare JSON-Datei.
  - `FindJsonFile` sucht jetzt zusaetzlich via `GetModuleFileName(HInstance)`
    (=BPL-Verzeichnis im IDE-Plugin) und in
    `%APPDATA%\StaticCodeAnalyser\rules\`.
  - `RunAllDetectors` skipt Detektoren ueber Set-Membership + Severity-
    Schwelle; Post-Filter auf `Results` faengt Adapter-Findings (DFM)
    deren Kind nicht im Profile ist.
  - `TRepoSettings.UseIdeRuleSet` spiegelt `IdeProfile/IdeMinSeverity`
    transient in `Profile/MinSeverity`, damit Standalone und IDE-Plugin
    unterschiedliche Default-Profile fahren koennen ohne separate INIs.
  Dateien: `Common/uRuleCatalog.pas`, `Common/uSCAConsts.pas`,
  `Infrastructure/uStaticAnalyzer2.pas`, `Infrastructure/uRepoSettings.pas`,
  `rules/sca-rules.json`, `StaticCodeAnalyserIDE/uIDEAnalyserForm.pas`,
  `tests/uTestRuleCatalog.pas`.

- [x] **HTML-Report: Severity-Filter + Datei-Dropdown mit Filter** — _erledigt_
  Severity-Badges (Error/Warning/Hint) und Datei-Dropdown waren bereits
  als unabhaengige Filter implementiert; jetzt wirkt der Severity-Filter
  zusaetzlich AUF die Dropdown-Liste:
  - Pascal-seitig wird in `ExportHtml` pro File ein Bitmask (1=err,
    2=warn, 4=hint) ueber alle Findings akkumuliert.
  - Jede `<option>` bekommt ein `data-sev="err,hint"`-Attribut (Komma-
    Liste der vorkommenden Severities).
  - Neue JS-Funktion `applyFileDropdownVisibility()` versteckt Options,
    deren `data-sev` den aktiven Severity-Filter nicht enthaelt
    (`opt.hidden = true`). Die "Alle"-Option bleibt sichtbar; ihr
    Counter wird auf die Anzahl sichtbarer Files aktualisiert.
  - Wenn das aktuell ausgewaehlte File durch den Filter verschwindet,
    wird die Auswahl auf "Alle" zurueckgesetzt (verhindert leere
    Tabellen-Ansicht).
  - Beide Filter UND-verknuepft. Self-contained (Inline-CSS+JS, keine
    externen Abhaengigkeiten).
  Datei: `Infrastructure/uExport.pas` (`ExportHtml`).

- [x] **DFM + Komponentengraph** — _Phase 1+2+3 Detektoren erledigt (v0.10.0)_

  20 DFM-Detektoren produktiv: dedizierter DFM-Lexer/-Parser,
  `TComponentGraph`, `TFormBinder` (Pascal-AST ↔ DFM-Graph),
  `TDfmRepoIndex` (Repo-weiter Cross-Form-Lookup). Pipeline in
  `uDfmAnalysisRunner` integriert; `.dfm`-Aenderungen im VCS-Diff
  triggern die zugehoerige `.pas`. IDE-Plugin oeffnet DFM-Befunde via
  Close-and-Reopen als Text im Code-Editor. Standalone-EXE hat einen
  Modal-DFM-Text-Viewer. HTML-Report gruppiert `.pas`+`.dfm` pro
  Basename.

  **Phase 1 — MVP (erledigt):**
  - [x] DFM-Lexer + -Parser (`uDfmLexer`, `uDfmParser`)
  - [x] Binaer-DFM via RTL `ObjectBinaryToText`
  - [x] `TComponentGraph`-Datenmodell (`uDfmComponentGraph`)
  - [x] `TFormBinder` (`Infrastructure/uFormBinder`)
  - [x] Pipeline-Erweiterung (`uDfmAnalysisRunner` +
    `RunComponentDetectors`)
  - [x] Detektoren der Cluster Dead-Wiring, Naming, Security,
    UI/UX:
    `fkDfmDeadEvent`, `fkDfmOrphanHandler`, `fkDfmSchemaMismatch`,
    `fkDfmHardcodedCaption`, `fkDfmDefaultName`,
    `fkDfmHardcodedDbCreds`, `fkDfmDuplicateBinding`,
    `fkDfmEmptyBoundEvent`
  - [x] DUnitX-Tests pro Detektor (positiv/negativ/Kantenfall)

  **Phase 2 — Erweiterungs-Detektoren (erledigt):**
  - [x] DataModule-uebergreifender Resolver (`TDfmRepoIndex`)
  - [x] Cross-Form-Coupling (`fkDfmCrossFormCoupling`)
  - [x] Layer-Verstoss (`fkDfmLayerViolation`)
  - [x] God-Handler (`fkDfmGodHandler`)
  - [x] TAction halb verkabelt (`fkDfmActionMismatch`)
  - [x] Tab-Order-Konflikte (`fkDfmTabOrderConflict`)
  - [x] Verbotene Komponentenklassen (`fkDfmForbiddenClass`)
  - [x] DB-Komponente in UI-Form (`fkDfmDbInUiForm`)
  - [x] Zirkulaere Datenquellen-Verkettung
    (`fkDfmCircularDataSource`)
  - [x] SQL-Injection durch VCL-Komponenten
    (`fkDfmSqlFromUserInput`)

  **Phase 3 — DB-aware Field-Analyse (erledigt):**
  - [x] `TField`-Subgraph im ComponentGraph
  - [x] Bindung Field → UI-Komponente (Cross-Index)
  - [x] Unsichtbare Pflichtfelder (`fkDfmRequiredFieldNotVisible`)
  - [x] Pflichtfeld ohne UI-Bindung (`fkDfmRequiredFieldUnbound`)
  - [x] Falscher Komponententyp fuer Datentyp
    (`fkDfmFieldTypeMismatch`)

- [x] **DFM — Restposten Infrastruktur** _(erledigt - foundation
  steht; Folge-Refactor von Detektoren laeuft inkrementell weiter)_

  - [x] **`inherited`-Form-Aufloesung** — `TFormBinder.BindWithParents`
    + `TFormBinding.Parent` walken die Klassen-Hierarchie via
    `TDfmRepoIndex`. `HasHandler`/`HasPublishedField`/
    `HasPublishedMethod` schauen die Parent-Kette durch. Detektoren
    `DeadEvent`, `OrphanHandler`, `SchemaMismatch` profitieren
    automatisch (sie nutzen die Walk-Up-Resolver).
  - [x] **Frame-Composition ueber Units** — `TFrameResolver` in
    `Infrastructure/uDfmFrameResolver.pas`. `ResolveFrameGraph` +
    `EnumerateFrameComponents` laden auf Bedarf die Frame-DFM via
    RepoIndex. Detektor-Refactor (LayerViolation, GodHandler,
    TabOrderConflict) zur opportunistischen Nutzung folgt sobald
    konkrete False-Negative-Faelle aufschlagen.
  - [x] **Property-Typisierung** — `TPropValue.AsBoolean`,
    `AsInteger`, `AsString`, `AsIdent`, `SetContains` +
    `TComponentNode.GetBoolean/GetInteger/GetString/GetIdent/
    SetPropertyContains`. Default-Aware: gibt VCL-Default zurueck,
    wenn die Property im DFM nicht serialisiert ist. Detektoren
    `RequiredField`, `DbFieldAnalysis-Helper` umgestellt; weitere
    Detektoren ziehen opportunistisch nach.
  - [x] **Live-Refresh im IDE-Plugin auf `.dfm`-Save** — IDE-Plugin
    haengt jetzt einen zweiten `IOTAModuleNotifier` an das
    Companion-DFM-Modul (sofern als eigenes Modul offen, z.B.
    DFM-as-Text nach Close-and-Reopen). `EditorViewModified` mapped
    `.dfm`-Edits zusaetzlich auf die Watched-`.pas`. Sowohl Save als
    auch Edit fuehren zur Re-Analyse - manueller "Aktuelle Datei"-
    Klick nach DFM-Save ist nicht mehr noetig.
  - [x] **Eigener Binaer-DFM-Reader** — `uDfmBinaryReader` mit
    `IsBinary` (TPF0-Praefix-Check) + `ToText` (delegiert intern auf
    `Classes.ObjectBinaryToText`). Schnittstelle ist abstrakt
    gehalten, sodass ein voller TWriter-Eigen-Parser ohne Caller-
    Aenderung hineingetauscht werden kann. Sofort-Effekt: binaer-
    gespeicherte DFMs werden nicht mehr stumm uebersprungen.

---

## 📝 Erledigt (kompakte History)

Siehe `git log` für Details. Haupt-Themen chronologisch:

**Strukturell**
- ✅ Re-Strukturierung in `Common/Parsing/Detectors/Infrastructure/Output/UI`
- ✅ `repo.ini` → `analyser.ini` mit Auto-Migration
- ✅ Konsolidierter `uClaudePrompt`-Helper (kein Doppelcode)
- ✅ FixHint-Wrapper in IDE-Plugin (delegiert an Resolver)

**Konfiguration über INI**
- ✅ Custom-LeakyClasses + ExcludeLeakyClasses in `[Detectors]`
- ✅ `UsesCheck` / `IncludeTests` Checkboxen → INI-Settings
  (Toolbar entlastet, Pattern wie `AutoDiscoverClasses`)
- ✅ Konfigurierbare Detektor-Schwellwerte: `LongMethodMaxBodyLines`,
  `LongMethodMaxStatements`, `LongParamListMaxParams`,
  `DeepNestingMaxDepth`, `DuplicateBlockMinLines`, `MaxFileMB`,
  `MagicNumberTrivials`. Gespiegelt in `uSCAConsts`-Globals via
  `TRepoSettings.ApplyDetectorThresholds`
- ✅ Auto-Discovery von Custom-Klassen — `AutoDiscoverClasses=1` scannt
  Projekt-AST nach Klassen die `Free` brauchen, splittet in
  _instantiable_ vs. _static-only_, schreibt nach
  `LeakyClassesDiscover.log`

**Detektor-Pipeline**
- ✅ Wortgrenzen-Helper `TDetectorUtils` für 5 Detektoren
- ✅ Iterativer AST-Traversal (kein Stack-Overflow mehr)
- ✅ JSON/HTML Encoding RFC-konform mit Surrogate-Handling
- ✅ Suppression abdeckt alle 21 Finding-Kinds
- ✅ uExport UTF-8 mit BOM — `TExporter.SaveUtf8WithBom`-Helper mit
  `TUTF8Encoding.Create(True)`. Default-Singleton hat in Delphi 12
  `FUseBOM=False` — notwendig für deutsches Excel

**IDE-Plugin Integration**
- ✅ DE-Lokalisierung (eingebautes Dictionary in `uLocalization`)
- ✅ Messages-Pane statt Custom-Line-Highlights — später wieder
  deaktiviert (User-Feedback: kein Export aus Scan)
- ✅ UI-Race-Schutz: globaler `GLiveAnalyserFrame`-Sentinel verhindert
  AV bei Frame-Destruction während Worker-Callback
- ✅ Button „Repo..." → „Settings..." / „Einstellungen..." umbenannt
- ✅ FilterCombo Edge-Cases: `Items.Count = 0` + `idx >= Count`
  Pre-Checks + Re-Entry-Schutz beim ItemIndex-Reset
- ✅ Tooltip im Grid — nur Datei-Spalte, 100 ms Delay (statt IDE-Default
  500 ms), keine Tooltips auf Method/Line/Type/Severity
- ✅ Severity / Type Filter-Combos in eigenen Container-Panels —
  `TLabel`+`TComboBox` mit losem `alLeft` verschoben sich gegeneinander
  (Graphic- vs. Window-Control), Container-Pattern serialisiert sauber

**Editor-Integration (ToolsAPI)**
- ✅ Editor-Line-Highlight bei Click auf Befund — via
  `INTAEditViewNotifier.PaintLine` (DelphiLint-Pattern),
  `TNotifierObject`-Basisklasse, 3 px roter Stripe links neben der
  Zeile. Lazy-Attach beim ersten Klick (kein Plugin-Install-Risiko)
- ✅ `View.RemoveNotifier` beim Plugin-Unload — Manager trackt pro
  Attach `(TFindingViewNotifier, Index, IOTAEditView)`, ruft
  `RemoveNotifier` im Destructor mit `try/except` + Buffer-null-Check

**Watch-Mode (Live-Analyse beim Speichern)**
- ✅ Watch-Mode komplett implementiert in `uIDEWatchMode.pas`:
  - Pro offener `.pas`-Datei einen `IOTAModuleNotifier`
  - `AfterSave` triggert nach 300 ms Debounce einen
    `TWatchAnalyzer`-Background-Thread
  - `Synchronize` zurück an Frame, der via `OnWatchFindings` nur die
    Findings für diese eine Datei in `FAllFindings` ersetzt
  - Generation-Counter dropped späte Worker-Ergebnisse wenn manuelle
    Analyse zwischenzeitlich läuft
  - Aktivierung via INI `[Detectors] WatchMode=1` (Pattern wie
    `UsesCheck` / `IncludeTests`)
- ✅ WatchMode auto-aktiv bei „Aktuelle Datei" — Klick auf den Button
  forciert WatchMode unabhängig von der INI-Einstellung; Live-Edit-
  Update ist da der natural fit. Bulk-Pfade (Full-Project,
  Branch-Changes) folgen weiterhin dem INI-Wert
- ✅ `IOTAModuleNotifier` Delphi-12-kompatibel — alle drei
  Interface-Versionen explizit gelistet (`IOTAModuleNotifier`,
  `IOTAModuleNotifier80`, `IOTAModuleNotifier90`) + zusätzlich
  `IInterface` und `IOTANotifier`. Vorher AV in `coreide290.bpl` weil
  IDE-Kern auf 90 QueryInterface't und beim nil-Result NULL-Pointer
  dereferenziert

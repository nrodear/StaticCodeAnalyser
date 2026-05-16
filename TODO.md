# TODO

Offene Aufgaben für **Static Code Analysis Tool for Delphi**.
Sortiert nach Priorität: 🚨 Urgent / 🔴 Bug / 🟡 Robustheit / 🟢 Wartbarkeit / 🚀 CI-Mode / 💡 Feature / 🧪 Tests / 📋 Akzeptiert.

Erledigte Punkte siehe [docs/done.md](docs/done.md).

---

## 🚨 Urgent — Next-Up

Kuratierte Liste der höchst-prioritären offenen Punkte. Querverweise
zur ausführlichen Beschreibung im jeweiligen Abschnitt unten.

### Korrektheits-Bugs zuerst (real-world-Fundstellen aus mORMot2-Crosscheck)

- [ ] **🅰 Parser: Anonymer inline-`record`-Typ als Var-Typ → Body verloren**
  Höchste Schweregrad-Stufe: ganze Methoden-Rümpfe gehen verloren,
  weil der TypeName-Loop in `ParseLocalVarSection` (Z. 768-773) am
  ersten `;` _innerhalb_ des inline-records abbricht. Betrifft FFI-/
  OS-Code (mormot.core.os, mormot.db.raw.*). Lösung: Mini-Parser für
  inline-record bis matching `end`. Details → 🔴 Bugs.

- [ ] **🅱 DeadCode: `CheckBlock` rekursiv ohne Bound → Stack-Overflow**
  Einziger offener Bug der einen Crash auslösen kann. Pathologisch
  tiefe ASTs lassen den Detektor crashen. Lösung: iterativer
  Work-Stack analog `uAstNode.CollectAll`. Details → 🔴 Bugs.

- [ ] **🅲 Memory-Detektor: `LeakyClasses` deckt mORMot-Idiomatik nicht ab**
  Volumen-Bug: `TJsonWriter`, `TRawUtf8List`, `TSynList`,
  `TBufferWriter` etc. werden nicht getrackt → False-Negatives in
  jedem mORMot-Projekt. Lösung: `MORMOT_LEAKY`-Default-Liste oder
  INI-Eintrag. Details → 🔴 Bugs.

### Neue Detektoren mit höchstem real-world Win

- [ ] **🅳 `fkVirtualCallInCtor`** — Virtual-Methoden-Call im Constructor
  Klassisches Subtle-Bug-Pattern (abgeleitete Override läuft mit
  halb-initialisiertem Self). Single-Unit-Analyse, AST-Pattern
  überschaubar. Details → 💡 Features → Neue Detektor-Ideen.

- [ ] **🅴 `fkSelfAssignment`** — `x := x;` als No-Op / Copy-Paste-Bug
  Einfach zu implementieren, klarer Wert. Property-Setter mit
  Side-Effects als Skip-Liste. Details → 💡 Features.

- [ ] **🅵 `fkReversedForRange`** — `for i := 10 to 1 do` (0 Iterationen)
  Findet echte Tippfehler (`downto` vergessen). Trivial via AST.
  Details → 💡 Features.

- [ ] **🅶 `fkLengthUnderflow`** — `Length(s) - X` ohne Guard
  Native-UInt-Underflow → Riesenwert. Häufig in String-Slicing.
  AST: Subtraktion mit `Length(...)`/`.Count` ohne preceding Guard.
  Details → 💡 Features.

### Architektur (eigenes Cross-Unit-Pass-Modell)

- [ ] **🅷 `fkCanBePrivate`** + `fkCanBeProtected` + `fkUnusedPublicMember`
  Cross-Unit-Visibility-Check. Einziger Punkt mit signifikantem
  Infrastructure-Aufbau (neuer `uSymbolReferenceIndex`, 3-Pass-
  Modell). Liefert dafür drei Detektoren auf einmal und öffnet
  die Tür für weitere Cross-Unit-Inspections. Details → 💡 Features.

### Empfohlene Reihenfolge

1. **🅱 + 🅵 + 🅴 + 🅳** zuerst (Single-Unit, je <½ Tag, hoher Wert)
2. **🅰 + 🅲** danach (Parser-Tiefenarbeit, je ~Tag)
3. **🅶** als eigenes Refactor-Inkrement
4. **🅷** als Architektur-Increment (~2-3 Tage Infrastructure +
   Detektor + Quick-Fix)

---

## 🔴 Bugs / Korrektheit

- [ ] **`uDeadCode.CheckBlock` rekursiv ohne Bound**
  Rekursiert in `nkBlock`/`nkIfStmt`/...-Children — gleiches Stack-
  Overflow-Risiko, das `uAstNode.FindAll`/`FindFirst` schon iterativ
  umgangen haben. Pathologisch tiefe ASTs crashen den Detektor.
  Datei: `Detectors/uDeadCode.pas:54-61`
  Lösung: iterativer Work-Stack analog zu `uAstNode.CollectAll`.

### Aus mORMot2-Real-World-Review (4-Agenten-Crosscheck)

- [ ] **Parser: Anonymer inline-`record`-Typ als Var-Typ -> Body verloren**
  `var R: record A: Integer; end;` in FFI-/OS-Code:
  TypeName-Schleife in `ParseLocalVarSection` (Z. 768-773) bricht beim
  ersten `;` _innerhalb_ des records, dann erkennt der Outer-Loop das
  folgende `end` als Section-Grenze, `ParseMethodImpl` sieht `end`
  statt `begin` → **Methodenrumpf verloren**. Vorkommt in
  `mormot.core.os.pas` und `mormot.db.raw.*`.
  Datei: `Parsing/uParser2.pas:768-773`
  Lösung: bei `record` im TypeName-Branch einen Mini-Parser fuer
  inline-record bis matching `end` einsetzen.

- [ ] **Memory-Detektor: `LeakyClasses` deckt mORMot-Idiomatik nicht ab**
  `Common/uSCAConsts.pas:153-166` listet nur RTL/VCL-Klassen
  (`TStringList` etc.). Keine mORMot-Klasse (`TJsonWriter`,
  `TRawUtf8List`, `TSynList`, `TTextWriter`, `TBufferWriter`,
  `TSqlDBStatement`, `TSynPersistent`-Subklassen, ...) wird getrackt.
  Beispiel: `ui/mormot.ui.pdf.pas:4131` `fArray := TSynList.Create`
  ohne Free in der gleichen Methode → **kein Leak gemeldet**.
  Lösung: Zusatz-Liste `MORMOT_LEAKY` im Default oder Standard-INI-
  Eintrag der typischen mORMot-Klassen aktivieren.
  AutoDiscoverClasses (=1 in INI) wuerde es fangen, ist aber per
  Default off.

- [ ] **SQL-Detektor: `Format`/`FormatUtf8`-basierter SQL ungeprueft**
  `ExecuteFmt('SELECT * FROM % WHERE Id=%', [tbl, id])` ist klassisch
  mORMot. Kein `+` im Code → `HasNonLiteralPlus` matcht nicht →
  **komplett uebersehen**, obwohl `%` strukturell als Tabellenname
  einen realen Injection-Vektor erzeugt.
  Datei: `Detectors/uSQLInjection.pas:42`
  Lösung: zusaetzliche Heuristik fuer `Format(.., [..])` /
  `FormatUtf8`/`FormatSQL`/`ExecuteFmt`-Calls mit SQL-Keyword im
  Format-String.

- [ ] **SQL-Detektor: String-Konkatenation statt Parameter (Quick-Fix)**
  Heute meldet `uSQLInjection.pas` die Konkat-Risiken, bietet aber keine
  Auto-Korrektur. ReSharper-Pendant: `'... ' + IntToStr(x) + ' ...'` in
  `:param` umwandeln und `Params.ParamByName(...).AsInteger := x` einfügen.
  Lösung: Quick-Fix-Hook auf bestehenden H1/H2-Findings; AST-Pattern
  `+`-Kette + `IntToStr`/`FloatToStr` als Trigger.
  Datei: `Detectors/uSQLInjection.pas`, `StaticCodeAnalyserIDE/uIDEQuickFix.*`
  (neu, falls Quick-Fix-Framework noch fehlt).

- [ ] **SQL-Detektor: Fehlende `WHERE`-Klausel bei `UPDATE`/`DELETE`**
  Statement-Level-Inspection: `UPDATE t SET ... ;` oder `DELETE FROM t;`
  ohne `WHERE` → Warning (Risiko: ganze Tabelle betroffen). Regex-Pre-
  Filter + AST-Validierung nach Statement-Boundary.
  Datei: `Detectors/uSQLInjection.pas` oder neuer Detektor
  `Detectors/uSQLDangerousStatement.pas`.

- [ ] **SQL-Detektor: Datentyp-Mismatch Parameter ↔ Spalte**
  `Params.ParamByName('age').AsString := s;` gegen `age INTEGER` in der
  DDL → Warning. Setzt Schema-Anbindung voraus (siehe 💡 Features-Block
  „SQL Schema-aware Inspections").
  Datei: `Detectors/uSQLParamTypeMatch.pas` (neu).

- [ ] **FormatMismatch: Lokalisierungs-Falle bei `%.2f`-ohne `TFormatSettings`**
  `Format('%.2f', [x])` ohne expliziten `TFormatSettings`-Parameter ist
  Locale-abhängig (Komma vs. Punkt). Hint statt Warning. Quick-Fix:
  Aufruf in `Format('%.2f', [x], InvariantFormatSettings)` umwandeln.
  Datei: `Detectors/uFormatMismatch.pas`.

- [ ] **HardcodedSecret: Public-Crypto-Konstanten False-Positives**
  `crypt/mormot.crypt.core.pas` und Co. deklarieren `const X_TOKEN`,
  `JWT_SECRET_HEADER` als publish'te Algorithmus-Marker — `IsSecretName`
  matcht das, obwohl es kein Geheimnis ist.
  Lösung: Const-Blöcke ausserhalb von Field-/Property-Kontext skippen,
  oder Wert-Filter (Hex-/ASCII-Konstante mit Magic-Bytes 4-8 Zeichen).
  Datei: `Detectors/uHardcodedSecret.pas:46-74`

- [ ] **HardcodedSecret: ConnectionString-Templates ohne Password False-Positive**
  `FConnectionString := 'Server=localhost;Database=test;'` — kein
  `pwd=`/`password=` enthalten, aber Variablenname matcht
  `connectionstring` aus `SECRET_KW`.
  Lösung: bei ConnectionString zusätzlich Wert-Inhalt auf
  `pwd=`/`password=` pruefen.
  Datei: `Detectors/uHardcodedSecret.pas:39-44`

- [ ] **HardcodedPath: Kanonische Linux-System-Pfade False-Positive**
  `'/etc/ssl/certs'`, `'/var/run/...'`, `'/tmp/'` sind unvermeidbar in
  cross-platform OS-Includes. mORMot: `core/mormot.core.os.posix.inc`,
  `net/mormot.net.client.pas`.
  Lösung: Whitelist fuer kanonische *nix-System-Pfade
  (`/etc/`, `/var/`, `/tmp/`, `/usr/`, `/proc/`, `/sys/`).
  Datei: `Detectors/uHardcodedPath.pas:50-52`

- [ ] **DivByZero: `mod`-Pattern via TypeRef nicht zuverlässig**
  Detektor sucht `' mod '` in `nkAssign.TypeRef`, aber die String-Form
  in TypeRef ist je nach Parser-Pfad nicht garantiert. Beispiel:
  `core/mormot.core.base.pas:10130` `size := len mod size;` mit
  Parameter `size` ohne Guard → sollte Warning, kommt aber je nach
  Expression-Capture moeglicherweise nicht.
  Datei: `Detectors/uDivByZero.pas`
  Lösung: AST-strukturierte Operator-Erkennung statt TypeRef-String-Pos.

- [ ] **MagicNumber: typische Bit-Width-Werte fehlen in Trivials**
  `8`, `16`, `24`, `31`, `32`, `63`, `64`, `128`, `255`, `256` werden
  als Magic Numbers gemeldet — sind aber idiomatische Bit-/Byte-
  Konstanten (Crypto, Buffer, Encoding).
  Datei: `Common/uSCAConsts.pas` (`MagicNumberTrivials`)
  Lösung: Default erweitern; Power-of-2-Heuristik bis 1024.

- [ ] **DeepNesting: case-Tiefe falsch gewichtet**
  `case ... of` zaehlt als +1 Tiefe wie `if`. Bei Hand-optimierten
  Parsern (`mormot.core.json.pas:3466` `GetJsonField`: case+repeat+if+
  if+if = Tiefe 5) entsteht False-Positive in legitimen Hot-Path-State-
  Machines.
  Datei: `Detectors/uDeepNesting.pas:51`
  Lösung: case mit flachen Arms separat zaehlen, oder case nur als +0.5
  werten.

- [ ] **DuplicateBlock: Crypto-Round-Funktionen False-Positive**
  SHA/AES/MD5 round1-round4-Bloecke (`crypt/mormot.crypt.core.pas`) sind
  bewusst aus Performance-Gruenden uniggeoldet. `IsBranchingBoilerplate`
  filtert nur if/end-heavy Bloecke aus, nicht bit-arithmetik-heavy.
  Datei: `Detectors/uDuplicateBlock.pas:204`
  Lösung: Bloecke skippen die ueberwiegend `shl|shr|xor|and|or` sind.

- [ ] **DebugOutput in Diagnostic-/MM-Units False-Positive**
  `core/mormot.core.fpcx64mm.pas:3441-3556` `writeln(' probable ',
  classname^, ' leak ...')` ist Memory-Manager-Leak-Reporting (legitim).
  `mormot.core.log.pas` und `mormot.core.variants.pas` haben weitere
  legitime WriteLns. mORMot: hunderte False-Positives.
  Datei: `Detectors/uDebugOutput.pas:50`
  Lösung: Unit-Pattern-Whitelist (`mormot.*.log`, `*.fpcx64mm`,
  `*.test`) oder INI-konfigurierbarer Skip-Path.

- [ ] **LongMethod: physische Zeilen inflated durch IFDEFs**
  `FindLastLine` zaehlt physische Zeilen inkl. IFDEF-Blocks, die der
  Lexer zwar als `tkUnknown` mit erhoehtem `FLine` durchlaeuft. Die
  AND-Logik (Lines>50 AND Stmts>30) rettet meistens, aber eine 75-
  Zeilen-Methode mit 7 IFDEF-Blocks ist effektiv 30 Code-Zeilen.
  Datei: `Detectors/uLongMethod.pas:92,44-56`
  Lösung: nur Token-basierte Body-Zeilen zaehlen (Zeilen mit non-
  Comment-Tokens).

- [ ] **EmptyExcept: `case x of jtFirst:` einzeilig miscount'd Depth**
  `KwStart('case')` triggert depth+1 ohne `hasCode := True` wenn das
  `of` mit erstem Arm auf der gleichen Zeile steht. `mormot.core.json.
  pas:3493`-Stil.
  Datei: `Detectors/uCodeSmells.pas:97`
  Lösung: `case ... of <something>:` immer als Code-Zeile markieren.

- [ ] **DeadCode: `raise E at ReturnAddress` mishandled**
  `core/mormot.core.rtti.pas:4251`-Stil:
  `raise E {$ifdef FPC} at ... {$else} at ReturnAddress {$endif}`.
  Falls der Parser `at ReturnAddress` als Sibling-Statement aufnimmt,
  wird es als toter Code gemeldet.
  Datei: `Detectors/uDeadCode.pas:74` plus `Parsing/uParser2.pas`
  Lösung: `at <expr>`-Modifier zum nkRaise-Knoten konsumieren.

### Performance-Risiken aus mORMot2-Review

- [ ] **`DuplicateBlock` O(n*m) Memory bei sehr grossen Files**
  Window-Schluessel werden als 8-Zeilen-String concat'd (~500 chars)
  in ein Dictionary gespeichert. Bei 10k-Zeilen-Files: ~10000 Eintraege
  × 500 Bytes = ~5 MB Heap pro Datei. mORMot2 hat mehrere
  >10k-Zeilen-Files (`mormot.core.json.pas`, `mormot.core.rtti.pas`).
  Datei: `Detectors/uDuplicateBlock.pas`
  Lösung: xxHash/FNV-Hash der Window-Strings als Dict-Key statt
  String selbst.

- [ ] **`uLeakDetector2` 3x duplizierter `FindAll(nkAssign)` pro lokalem Var**
  `HasCreateAssign`, `HasFunctionCallAssign`, `IsReturnedAsResult`
  rufen je `MethodNode.FindAll(nkAssign)` und allokieren je eine neue
  TList. Bei Methoden mit 50+ lokalen Vars × 100+ Assigns:
  spuerbarer Slowdown.
  Datei: `Detectors/uLeakDetector2.pas`
  Lösung: einmalig pro Methode FindAll, dann an die Sub-Funktionen
  als Parameter durchreichen.

- [ ] **Asm-Bloecke + `@@labels` koennen 200k-Watchdog ausloesen**
  `crypt/mormot.crypt.core.pas` AES/SHA-asm-Routinen mit hunderten
  Mnemonics + `db $XX`-Tabellen. Asm-Labels `@@loop:` produziert 4
  Tokens (`@`, `@`, `loop`, `:`). Pro `mov [@@table+eax*4], ebx` 8+
  Tokens. Multipler-Effekt 3-4x → bei mehreren asm-Routinen pro File
  schiesst Token-Count ueber 200k → File wird verworfen.
  Datei: `Parsing/uLexer.pas:492` (AT-Tokenisierung)
  Lösung: `@@<ident>` als _ein_ Token (`tkAsmLabel`) zusammenfassen.

---

## 🟡 Robustheit

- [ ] **`uHardcodedSecret.IsSecretName` Coverage erweitern**
  Aktuelle Tests prüfen Defaults (`secretary` als false-positive bereits
  abgedeckt). Fehlend: `tokenize`, `passport`, `keyboard` (alle sollten
  KEIN Match sein).

- [ ] **WatchMode echtes Cancel-Token**
  Heute droppen wir nur _späte_ Worker-Ergebnisse via Generation-Counter.
  Bei einer wirklich langen Datei (5+ Sekunden) läuft der Worker zu Ende,
  obwohl der User schon weiter editiert hat — Verschwendung.
  Lösung: Cancel-Flag im Worker, periodisch von Detektoren via Callback
  abgefragt (analog zum Manual-Cancel in `AnalyseLeaksRecursive`).

- [ ] **`Parser2.ParseSource` schluckt Parser-Errors silent**
  Cached alle Exceptions außer Watchdog und gibt einen partiellen AST
  zurück, ohne den Caller zu benachrichtigen → Analyse läuft auf einem
  abgeschnittenen Baum.
  Datei: `Parsing/uParser2.pas:117-124`
  Lösung: Non-Watchdog-Errors als `fkFileReadError` melden (Pattern wie
  in `ParseLeaks`).

- [ ] **`uStaticAnalyzer2` mutiert globale `LeakyClasses` ohne Restore**
  `AutoDiscoverCustomClasses` ergänzt `LeakyClasses` kumulativ über Runs
  hinweg; ein zweiter Scan sieht die Discoveries vom ersten weiter, auch
  nach `EAbort`.
  Datei: `Infrastructure/uStaticAnalyzer2.pas:383-407`
  Lösung: Snapshot vor `ParseLeaks`, Restore in finally.

- [ ] **Detektoren mit rekursiver AST-Traversal (Stack-Overflow-Risiko)**
  `uLongMethod.FindLastLine` (Z. 44-56) und `uUnusedUses.CollectText`
  (Z. 87-130) walken den Tree rekursiv — gleiches Risiko wie
  `uDeadCode` (separat oben).
  Lösung: iterativer Work-Stack analog `uAstNode.CollectAll`.

- [ ] **`uAstNode.ChildCount` baut volle Liste nur zum Zählen**
  `ChildCount(nkParam)` allokiert `FindAll`-Liste pro Methode in
  `uLongParamList` — pure Verschwendung.
  Datei: `Parsing/uAstNode.pas:249-259`
  Lösung: iteratives Count ohne Listen-Allocation, oder direct-children-
  only Count (Params sind direkte Kids von Method).

- [ ] **WatchMode-Worker spawned auch nach `Deactivate`**
  `DebounceFire` → `SpawnAnalyzer` checkt `FActive` aber nicht
  `FOnFindings`-Assigned. Wenn `Deactivate` zwischen `NotifyFileSaved`
  und `DebounceFire` lief (Timer feuert verzögert), läuft der Worker
  trotzdem; `BumpGeneration` invalidiert zwar das Ergebnis, stoppt aber
  den laufenden Worker nicht.
  Datei: `StaticCodeAnalyserIDE/uIDEWatchMode.pas:393`

- [ ] **`TFindingHighlighter.DetachAll` Notifier-Iteration unsafe**
  Iteriert `FAttachedClassRefs` direkt während Objekte durch IDE-Unload
  invalidiert werden könnten; `DetachIfNeeded` hat zwar try/except, der
  Listen-Zugriff vorher nicht.
  Datei: `StaticCodeAnalyserIDE/uIDELineHighlighter.pas:172-176`
  Lösung: Indizes erst snapshotten, dann iterieren.

- [ ] **`NavigateDelphiToLine` SendInput an falsches Fenster**
  `FindWindow('TAppBuilder', nil)` returnt _irgendein_ IDE-Fenster bei
  mehreren Delphi-Instanzen; `SetForegroundWindow` kann unter Win10/11
  silent failen → Ctrl+G landet im falschen Fenster.
  Datei: `StaticCodeAnalyserForm/sources/UI/uMainForm.pas:485-519`
  Lösung: über `ProcessId` der eigenen IDE-Instanz fenstern, oder
  `IOTAActionServices.GoToLineAtCurrentEditor` nutzen.

- [ ] **`Resize` überschreibt User-Splitter-Drag**
  Jeder Resize setzt `FHelpPanel.Width := ThirdW` — User-Drag wird beim
  IDE-Redock (Tab-Switch, Theme-Change) verworfen. Kommentar bestätigt:
  „User-Drag wird respektiert bis zum naechsten Resize".
  Datei: `StaticCodeAnalyserIDE/uIDEAnalyserForm.pas:2630-2636`
  Lösung: User-Width im Settings persistieren, nur initial setzen.

- [ ] **`SetSelected` re-validiert nicht bei toter View**
  `FAttachedFiles.IndexOf(Key) >= 0` skipt re-attach permanent — auch
  wenn der `ViewNotifier` schon detached ist (Datei wurde geschlossen
  und wieder geöffnet). Highlight bleibt danach kaputt.
  Datei: `StaticCodeAnalyserIDE/uIDELineHighlighter.pas:201`
  Lösung: bei `IndexOf >= 0` zusätzlich prüfen ob Notifier alive ist,
  sonst Slot freigeben + neu attachen.

- [ ] **Inkrementelle Analyse für sehr große Projekte (>500k LOC)**
  ReDelphi-Vision: Inspections müssen auch in großen DPRs flüssig laufen.
  Heutige Scan-Architektur ist Per-Run-Vollscan. Vorschlag: AST-Cache
  pro Unit (Hash-keyed), Re-Analyse nur bei Hash-Diff. Watch-Mode
  liefert bereits Event-Trigger.
  Datei: `Infrastructure/uStaticAnalyzer2.pas`, neuer
  `Infrastructure/uIncrementalCache.pas`.

---

## 🟢 Wartbarkeit / Refactoring

- [~] **`uIDEAnalyserForm.pas` aufteilen** (2751 Zeilen, war 3039)
  - [x] `BuildStatsTiles`/`MakeTile`/`TTilePanel` extrahiert in
    `uIDEStatsTiles.pas` (~200 Z.). Frame ruft `TStatsTilesBuilder.Build`,
    Felder `FTileError`/`FTileWarn`/... bleiben fuer `UpdateStats` erhalten.
  - [x] `GridDrawCell` extrahiert in `UI/uFindingGridRenderer.pas` (s.u.).
  - [ ] **Filter-Logik** (`ApplyFilter`/`FilterChange`/`TypeFilterChange`/
    `SearchChange`, ~180 Z.) — noch offen. Tightly bound an Frame-State
    (FAllFindings, FDisplayedFindings, FFilterCombo, FTypeCombo,
    FSearchEdit, FResultGrid, FCurrentBaseDir, FSortColumn). Saubere
    Extraktion braucht ein TFilterContext-Record das alle Refs durch-
    reicht — nicht-trivial.
  Ziel weiterhin: Reduktion auf <1500 Zeilen (offen: ~1200 Z.).

- [ ] **Severity-Tiles im Standalone-`Form2`**
  IDE-Plugin hat die 8-Tile-Reihe (Errors / Warnings / Hints / Bugs /
  Security / Duplicates / Code-Quality), Standalone nicht. Feature-
  Parität herstellen — entweder portieren oder den IDE-Code als Helper
  extrahieren und beidseitig nutzen.

- [ ] **Leere Stub-Dateien entfernen**
  - `StaticCodeAnalyserForm/sources/MainController.pas` (7 Zeilen, leer)
  - `StaticCodeAnalyserForm/sources/Unit1.pas` (deklariert sich als
    `uParser2`, ist aber leer — Konflikt mit dem echten `uParser2.pas`
    in `Parsing/`)
  Beide ersatzlos löschen + Build-Pakete prüfen.

- [ ] **Encoding-Konvention für `.pas`-Files**
  Inkonsistent: einige Files UTF-8 ohne BOM mit rohen Umlauten, andere
  mit `#$xx`-Codepoints. Konvention festlegen + einmal-Sweep.

- [ ] **Detektor-Messages noch teilweise deutsch (Phase-2 i18n)**
  Bewusst übersprungen weil situativ — UI-Hauptpfad ist bereits englisch:
  - `Output/uFixHint.pas` — Vorher/Nachher-Snippets mit deutschen
    Inline-Kommentaren (~30 Snippet-Strings)
  - `Infrastructure/uStaticFiles.pas` — 5 Error-Messages
  - `Infrastructure/uVcsChanges.pas` — Branch-Changes-Status-Messages
  - `Detectors/uSQLInjectionScore.pas` — Reason / Suggestion-Strings

- [ ] **Severity je Detektor user-konfigurierbar**
  Heute hardcodiert (`F.Severity := lsWarning`). User möchte vielleicht
  `LongMethod` als `lsHint` einstufen oder `MagicNumber` aufwerten.
  Geplant: `[SeverityOverrides]`-Sektion in `analyser.ini` mit
  `LongMethod=hint` etc. + Read-In in `TRepoSettings`.

- [ ] **Hardcoded deutsche Strings in IDE-Form außerhalb `_()`**
  Beim i18n-Sweep übersehen:
  - `uIDEAnalyserForm.pas:1400` — `'Keine Eintraege fuer diesen Filter.'`
  - `uIDEAnalyserForm.pas:1735` — `'[watch] updated %s (%d findings)'`
  - ~~`uIDEAnalyserForm.pas:2067` — `'Analysiere: '`~~ → erledigt: jetzt
    in `uIDEAnalyseRunner.RunCurrent` als `_('Analyzing: ')`.
  - `uIDEAnalyserForm.pas:2268` — `'Ignore-Liste neu geladen ...'`

---

## 🚀 Console-Mode / CI-Integration

Großer separater Block — nichts von dem hier ist trivial, aber alles
hängt zusammen (CLI-Mode ist die Voraussetzung für CI-Integration).

- [ ] **Report-Formate für CI-Tools** _(SARIF erledigt in v0.8.0; JUnit / Sonar / Checkstyle / CodeClimate offen)_
  Mehrere Standard-Formate, je ein Output-Switch:
  - [x] `--report-sarif sca.sarif` — [SARIF v2.1.0](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/sarif-support-for-code-scanning),
    GitHub Code-Scanning-fähig (Findings im PR sichtbar) — `uExportSARIF`
  - [ ] `--report-junit sca.xml` — JUnit-XML, GitLab-CI / GitHub Actions /
    Jenkins kompatibel
  - [ ] `--report-sonar sca-sonar.json` — SonarQube Generic Issues
  - [ ] `--report-checkstyle sca-checkstyle.xml` — breitester Tool-Support
    (BitBucket, Phabricator, GitLab)
  - [ ] `--report-codeclimate sca-cc.json` — GitLab Code-Quality Widget
  - [x] `--report-html sca.html` — bestehender Report aus `uExport`,
    self-contained, fürs Build-Artefakt

  Datei: `Output/uReportFormats.pas` (neu), nutzt vorhandene
  Finding-Liste, getrennt von der UI-orientierten `uExport.pas`.

- [ ] **Pre-Commit-Hook-Script**
  `examples/pre-commit-sca.sh` (bash) und `pre-commit-sca.ps1`
  (PowerShell). Rufen `analyser.exe --branch --max-errors 0`. User
  kopiert ins `.git/hooks/pre-commit`.

- [ ] **Quality-Gate via `analyser.ini`**
  Zusätzlich zum CLI-Flag eine `[QualityGate]`-Sektion:
  ```ini
  [QualityGate]
  MaxErrors=0
  MaxWarnings=10
  MaxHints=50
  FailOn=error,warning
  ```
  Wird genutzt wenn keine CLI-Flags angegeben sind. Konsistente Defaults
  zwischen lokalem CLI-Run und Pipeline.

- [ ] **Baseline-File**
  Bei großen bestehenden Projekten will man neue Findings catchen, alte
  ignorieren.
  - `analyser.exe --baseline sca.baseline` — liest die Liste der
    bekannten Findings (Hash je File+Line+Rule), markiert sie als
    „pre-existing", failt nur bei NEUEN.
  - `analyser.exe --update-baseline sca.baseline` — re-generiert die
    Datei nach manuellem Code-Review der bestehenden Findings.

---

## 💡 Features / Erweiterungen

- [ ] **FormatMismatch: zusätzliche Sub-Inspections (ReSharper-Vorbild)**
  Erweitert den bestehenden Detektor um Diagnosen, die heute nicht
  abgedeckt sind. Argumentanzahl, Typ-Mismatch und Konstanten-Auflösung
  sind bereits implementiert (siehe 🔴 Bugs, FormatMismatch-Block).
  Offen:
  - [ ] **Index-Lücken** in `%0:s %2:s` erkennen (Index 1 fehlt →
    `EConvertError` zur Laufzeit).
  - [ ] **Ungültiger Spezifizierer** (`%q`, kaputte Breite/Präzision) —
    Whitelist `[-+ #0]*\d*(\.\d+)?[dxefgsmpunc...]` als Validator.
  - [ ] **Redundante `Format`-Aufrufe ohne Platzhalter**
    (`Format('hello', [])`) → Quick-Fix: durch String-Literal ersetzen.
  - [ ] **Verschachtelte `Format`-Aufrufe**
    (`Format('%s', [Format(...)])`) → Quick-Fix: zusammenführen.
  - [ ] **`IntToStr(x)`/`FloatToStr(x)` als `Format`-Argument** → Hint:
    redundant, `%d`/`%f` mit Roh-Wert verwenden.
  Datei: `Detectors/uFormatMismatch.pas`.

- [ ] **Format-Quick-Fixes (Alt+Enter)**
  - [ ] **Fehlendes Argument einfügen** am korrekten Index.
  - [ ] **Überzähligen Platzhalter entfernen** (samt Argument).
  - [ ] **Argument entfernen** (samt Platzhalter).
  - [ ] **Insert format argument**: in vorhandenem `Format(...)` nächsten
    Index berechnen + `%s` einfügen + `[]` erweitern; in einfachem
    String-Literal automatisch in `Format('...', [...])` umwandeln.
  - [ ] **Spezifizierer wechseln** (`%d` ↔ `%x` ↔ `%.2f`) per Menü.
  Datei: `StaticCodeAnalyserIDE/uIDEQuickFix.*` (neues Quick-Fix-Framework).

- [ ] **Format-Refactorings**
  - [ ] **Convert Konkatenation → `Format`**: `'Hallo ' + Name + ', du bist '
    + IntToStr(Age)` → `Format('Hallo %s, du bist %d', [Name, Age])`.
  - [ ] **Convert `Format` → Konkatenation** (umgekehrt).
  - [ ] **Convert `Format` → `FormatUtf8`** (mORMot-Idiom).
  - [ ] **Extract Format-String zu `resourcestring`** für Lokalisierung.
  - [ ] **Inline `resourcestring`**.
  - [ ] **Reorder arguments** — passt indizierte Platzhalter
    (`%0:s %1:d`) mit an.
  - [ ] **Switch zu `FormatSettings`-Variante** (Quick-Fix bei
    Locale-Falle, siehe 🔴 Bugs).
  Datei: `Detectors/uFormatMismatch.pas`, IDE-Quick-Fix-Framework.

- [ ] **SQL-Inspections (ReSharper-Vorbild, kein Schema nötig)**
  Reine Pattern-/AST-basierte Checks am SQL-Fragment, ohne DDL-Anbindung.
  - [ ] **`SELECT *`-Inspection** + Quick-Fix „Expand `*` to column list"
    (Quick-Fix nur mit Schema möglich; Warning auch ohne).
  - [ ] **Implizite Cross-Joins** (Komma-Joins) → Vorschlag `JOIN ... ON`.
  - [ ] **Redundante Klammern / Aliase** entfernen.
  - [ ] **Reservierte Wörter quoten** je nach Dialekt
    (`[order]` SQL-Server, `"order"` PostgreSQL).
  Setzt einen leichtgewichtigen SQL-Tokenizer/Statement-Splitter voraus,
  der noch nicht existiert.
  Datei: `Detectors/uSQLLint.pas` (neu) — eigenständiger Detektor, damit
  `uSQLInjection.pas` auf Sicherheit fokussiert bleibt.

- [ ] **SQL-Inspections mit Schema-Anbindung**
  Optional aktivierbar — braucht DDL-Connection (Config-Pfad / DSN).
  - [ ] **Unbekannte Tabelle/Spalte** → Quick-Fix: nächstgelegener Name
    (Levenshtein-Match), „Create column"-Vorschlag.
  - [ ] **Mehrdeutige Spalten** (`name` ohne Tabellenpräfix) →
    Quick-Fix: mit Alias qualifizieren.
  - [ ] **Datentyp-Mismatch zwischen Parameter und Spalte**
    (siehe 🔴 Bugs).
  Datei: `Detectors/uSQLSchemaAware.pas` (neu), neuer Config-Block
  `[Sql] SchemaDsn=...` in `analyser.ini`.

- [ ] **SQL-Refactorings**
  - [ ] **Rename**: Tabellen-/Spalten-Rename, das SQL-Strings UND Pascal-
    Code (`FieldByName('...')`, `ParamByName('...')`, ORM-Klassen)
    synchron anpasst. Cross-File, braucht Solution-Scan.
  - [ ] **Extract Query** — markiertes SQL in benannte Konstante /
    `resourcestring` / Query-Objekt extrahieren.
  - [ ] **Inline Query**.
  - [ ] **Convert `SQL.Add(...)`-Kette ↔ Multiline-String-Literal**.
  - [ ] **Move SQL to .sql-Resource** / `TStringList.LoadFromFile`.
  Datei: IDE-Refactoring-Framework (neu, ggf. analog zu Quick-Fix-Hook).

- [ ] **Settings-UI je Inspection — Severity pro Detektor**
  Heute steuern Profile (`ide-fast`/`default`/`strict`/…) das An/Aus
  pro Detektor; Severity ist im Code fix. Pendant zu ReSharpers
  Hint/Suggestion/Warning/Error: pro Detektor in der INI oder UI
  eine Severity setzbar machen.
  Datei: `Infrastructure/uRepoSettings.pas`, `Common/uRuleCatalog.pas`,
  IDE-Settings-Dialog.

- [ ] **Multi-View-Support für Highlight**
  Aktuell wird nur die TopView aktiv repainted — bei Split-View wird
  der zweite Pane erst beim nächsten Auto-Paint aktualisiert.
  Lösung: über alle EditWindows iterieren und `View.Paint` rufen.
  Datei: `StaticCodeAnalyserIDE/uIDELineHighlighter.pas`

- [ ] **„Ignore this finding"-Button im Grid-Context-Menü**
  Rechtsklick auf eine Befund-Zeile → „Suppress in code" (fügt
  `// noinspection <Kind>` über die Zeile ein) oder „Add to ignore.txt"
  (Datei-Glob in der Ignore-Datei). Heute muss der User händisch in
  `ignore.txt` editieren oder Suppression-Kommentare schreiben.

- [ ] **Bulk-Suppress (Multi-Select im Grid)**
  Mehrere Zeilen in der Ergebnisliste markieren → eine Action
  („Suppress all in code" / „Add files to ignore.txt"). Setzt
  `goRowSelect` auf Multi-Select voraus.

- [ ] **Compare-Scans (Regression-Detection)**
  Zwei Scan-Reports laden (oder einer aus Baseline) und Diff anzeigen:
  - **Neu**: Findings die im aktuellen Scan dazugekommen sind
  - **Behoben**: Findings die vorher da waren, jetzt weg
  - **Unverändert**: identisches Set
  Nützlich für Code-Reviews und PR-Kommentare.

- [ ] **Fix-It-Aktionen (auto-correct) für Trivialfälle**
  Bestimmte Detektor-Findings sind mechanisch fixbar:
  - `MissingFinally`: try/finally-Block einfügen
  - `EmptyMethod`: `inherited;`-Stub einfügen oder Methode entfernen
  - `TodoComment` ohne Issue-Nummer: Marker-Erweiterung anbieten
  Über `IOTAEditWriter` direkt im Quellcode patchen. Behutsam — nur mit
  User-Bestätigung pro Fix.

- [ ] **„Go to next / previous error"-Navigation**
  Tastenkürzel (z. B. F8 / Shift+F8 wie Compiler-Errors), springt durch
  die Findings-Liste in der aktuellen Datei. Heute muss man im Grid
  klicken um zu navigieren.

- [ ] **Mercurial-(`hg`-)Support in `uVcsChanges`**
  Heute nur Git und SVN. Mercurial-Repos via `hg status -nmar` +
  `hg diff --stat -r main` analog zu SVN. Auto-Detect über `.hg`-Ordner.
  Niedrige Priorität — Mercurial-Anteil im Delphi-Umfeld klein, aber
  technisch trivial.

- [ ] **Code-Metriken — allgemein + im Speziellen** _(Phase 1: Cyclomatic erledigt)_

  **Allgemein (Framework):**
  Heute laufen die metrik-artigen Detektoren (LongMethod, LongParamList,
  DeepNesting, MagicNumbers, DuplicateBlock, DuplicateString) als
  isolierte AST-Detektoren mit eigener Severity-Logik und melden ihre
  Treffer einzeln ins Befund-Grid. Das erzeugt Rauschen und macht
  Trends über Files/Methoden hinweg unsichtbar. Vorschlag:
  - **Metric-Layer** unterhalb der Detektoren: Pro `TMethodNode` /
    `TClassNode` / `Unit` werden Roh-Werte einmal akkumuliert
    (Lines, Statements, Params, MaxNestingDepth, Branches, Operators…)
    und als Properties am AST-Knoten oder in einer parallelen Map
    gehalten. Detektoren konsumieren die Map, statt das AST je nochmal
    selbst zu durchwandern.
  - **Metrics-View im IDE-Plugin** — analog zu `uIDEStatsTiles`: eine
    Tabelle "Top 10 Methoden nach Cyclomatic / Length / Nesting" je
    Aktuelle-Datei oder Branch-Diff. Ohne Severity, rein informativ
    (ergänzt das Befund-Grid, ersetzt es nicht).
  - **Einheitliche Threshold-Schema** in `[Metrics]` (statt verstreut
    in `[Detectors]`): `LongMethodMaxBodyLines`, `CyclomaticMax`, etc.
    plus pro-Methode-Override per Suppression-Marker
    (`// metrics: cyclomatic=15`).

  **Im Speziellen (neue Detektoren / Metriken):**
  - [x] **Cyclomatic Complexity (McCabe)** — _erledigt (Phase 1)_
    `if`/`for`/`while`/`repeat`/`case`-Arm/`on`-Handler/`and`/`or`/`xor`
    zählen +1 pro Methode, Base 1, `else` zählt nicht (binary branch).
    Schwelle 10 (Sonar/Checkstyle/PMD-Standard) via `[Detectors]
    CyclomaticMax`. Datei: `Detectors/uCyclomaticComplexity.pas`.
  - **Cognitive Complexity** (Sonar-Style) — wie Cyclomatic, aber
    Verschachtelung gewichtet (innere `if` zählen mehr als äußere).
    Korreliert besser mit "schwer zu lesen" als reine McCabe-Zahl.
  - **God-Class** — Klasse mit > N Methoden ODER > N Fields ODER
    Methoden/Fields-Verhältnis < 0.5 (Datenklasse). Heute kein
    Class-Level-Detektor.
  - **Boolean-Expression-Complexity** — `and`/`or`/`not`-Anzahl in
    einer einzelnen Condition. `if (a or b) and (c or d) and not e`
    = 5. Schwelle ~4. Hilft `if`-Statements zu vereinfachen.
  - **Comment-Density** — Kommentar-Zeilen / Code-Zeilen pro Unit.
    Sowohl Untergrenze (zu wenig docs) als auch Obergrenze
    (auskommentierter Code). Konfigurierbar per `[Metrics]`.
  - **Method-Count-per-Class** — separate Metrik für die God-Class-
    Diagnose, kann auch ohne Class-Smell-Verdacht informativ sein.
  - **Inheritance-Depth (DIT)** — Klassen-Hierarchie-Tiefe; tief
    verschachtelte Hierarchien sind Refactoring-Kandidaten. Braucht
    Cross-File-Auflösung (heute nicht da — Detektoren laufen pro Unit
    isoliert).
  - **Halstead-Metriken** (n1/n2/N1/N2 → Volume, Difficulty, Effort) —
    eher "nice to have", akademisch. Niedrige Priorität.

  **Reihenfolge-Vorschlag:** erst Metric-Layer + Cyclomatic
  (höchster Praxisnutzen, AST schon da), dann God-Class + Boolean-
  Expression (mittlerer Aufwand), dann Cognitive/DIT/Halstead
  (separater Pass).

- [ ] **DFM — Restposten Detektoren Phase 4**
  (Detektor-Backlog jenseits der heutigen 20)

  - [ ] **Master-Detail ohne `MasterFields`/`IndexFieldNames`** —
    `MasterSource` gesetzt, aber `MasterFields` leer → silent
    Cross-Join zur Laufzeit. Komplementaer zu
    `fkDfmCircularDataSource` (das Zyklen findet, aber nicht
    "kein Link").
  - [ ] **DesignTime-Property-Drift** — `DesignSize.X` !=
    `Width`/`Height`. Kommt typischerweise von High-DPI-Roundtrips
    und macht Anchors/Constraints brueschig.
  - [ ] **Frame-Instance-Property-Overrides erkennen** — Override
    einer geerbten Property auf einer Frame-Instance ohne
    `inherited`-Marker. Voraussetzung: Frame-Composition-Resolver
    (siehe oben).
  - [ ] **DataModule-Split-Vorschlag** — wenn `fkDfmDbInUiForm` >= N
    Befunde auf derselben Form, einen aggregierten "extract to data
    module"-Hint emittieren statt N einzelner.

### Neue Detektor-Ideen (allgemeine Code-Quality-Patterns)

Kandidaten für neue Detektoren — sortiert nach erwartetem
Bug-Hunt-Wert. Nicht alle sind unbedingt sinnvoll, aber jeder hier
hat in echtem Delphi-Code mal Fundstellen produziert.

#### Korrektheits-Bugs (höchste Priorität)

- [ ] **`fkVirtualCallInCtor`**
  Aufruf einer `virtual`-Methode im `constructor` ist ein klassischer
  Subtle-Bug: die abgeleitete Override läuft mit halb-initialisiertem
  Self (Felder einer Subklasse noch nicht gesetzt). AST-Pattern:
  Constructor-Body → MethodCall → MethodIsVirtual(Self.X).
  Datei: `Detectors/uVirtualCallInCtor.pas` (neu).

- [ ] **`fkSelfAssignment`**
  `x := x;` ist immer ein No-Op (oder Copy-Paste-Bug). Auch
  `Self.FFoo := FFoo;` (gleicher LHS+RHS nach Trim). AST-Pattern:
  `nkAssign` mit `LHS.Name = RHS.Name`. Trade-off: Property-Setter
  mit Side-Effects sind ein False-Positive — Properties via Type-
  Lookup ausschließen oder per Whitelist (`Capacity`, `Count`).
  Datei: `Detectors/uSelfAssign.pas` (neu).

- [ ] **`fkIdenticalIfElseBranches`**
  `if c then DoX else DoX;` — both branches identical, der `if`
  hat keinen Effekt. AST: Vergleich `IfNode.Then.Children` vs.
  `IfNode.Else.Children` strukturell (Token-Sequenz reicht).
  Datei: `Detectors/uIdenticalBranches.pas` (neu).

- [ ] **`fkTautologicalBoolExpr`**
  `(x = x)`, `(a and a)`, `(b or b)`, `(p <> p)` — Operator mit
  identischer Linker und rechter Seite. Klassischer Copy-Paste-
  Bug oder vergessener Index (`arr[i] = arr[j]` aber `j` fehlt).
  AST-Pattern: BinOp-Knoten mit `LHS.Tokens = RHS.Tokens`.
  Datei: `Detectors/uTautologicalExpr.pas` (neu).

- [ ] **`fkLengthUnderflow`**
  `Length(s) - X` ohne Vor-Check `Length(s) >= X` ist Underflow-
  Risiko: `Length` ist `NativeUInt` → bei `Length=0` und `X=1`
  wird das zu `MaxNativeUInt`. Häufig in String-Slicing.
  AST: Subtraktion mit linker Seite `Length(...)` / `.Count` /
  `.Size`, ohne preceding Guard.
  Datei: `Detectors/uLengthUnderflow.pas` (neu).

- [ ] **`fkEqualsWithoutHashCode`**
  Klasse überschreibt `function Equals(Obj: TObject): Boolean;
  override;` ohne `function GetHashCode: Integer; override;` —
  bricht TDictionary/TList.IndexOf-Semantik. Symmetrisch:
  `GetHashCode` ohne `Equals` ist auch verdächtig.
  AST: Class-Member-Scan auf Override-Trios.
  Datei: `Detectors/uEqualsHashCodePair.pas` (neu).

- [ ] **`fkUnusedLocalVar`**
  Lokale `var X: T;` die nie auf der LHS einer Zuweisung steht
  und nie als Lesezugriff in einer Expression auftaucht. Compiler
  warnt heute schon (H2164), aber als SCA-Detektor mit Suppression-
  Marker und Grid-Integration nützlich. AST: nkVarSection iterieren,
  in MethodBody nach Var-Name suchen.
  Datei: `Detectors/uUnusedLocal.pas` (neu).

- [ ] **`fkUnusedParameter`**
  Parameter der nie im Methoden-Body referenziert wird — skippen
  wenn Methode `override` (Signature-Konformität), Interface-Impl,
  oder Event-Handler (Sender etc.). AST: Parse Parameter-List,
  Scan Body für Identifier-Match.
  Datei: `Detectors/uUnusedParameter.pas` (neu).

- [ ] **`fkConfusingAndOrPrecedence`**
  Pascal: `and` bindet stärker als `or` — `a or b and c` ist
  `a or (b and c)`. Häufige Bug-Quelle wenn der Autor `(a or b) and c`
  meinte. AST: `or`-Operator mit `and`-Child OHNE explizite
  Parens → Warning, schlage Klammern vor.
  Datei: `Detectors/uMixedAndOrPrecedence.pas` (neu).

- [ ] **`fkAssertAlwaysTrue`**
  `Assert(True)`, `Assert(1 = 1)`, `Assert(Self <> nil)` direkt
  in einer non-static Methode (Self ist garantiert non-nil). AST:
  konstante Expression als Assert-Argument.
  Datei: `Detectors/uAssertAlwaysTrue.pas` (neu).

#### Style / Lesbarkeit

- [ ] **`fkAssertWithoutMessage`**
  `Assert(x > 0)` ohne den optionalen `Message`-Parameter. Beim
  Fehlschlag nur "Assertion failed at <unit>:<line>" — ohne
  Kontext schwer zu debuggen. Hint mit Quick-Fix: füge
  `'reason: ' + DebugDump` als zweiten Param hinzu.
  Datei: `Detectors/uCodeSmells2.pas` (Erweiterung).

- [ ] **`fkRedundantParens`**
  Doppelt geklammerte Expressions: `if ((x = 1)) then`, `Result := ((a))`.
  Pattern: nkParenExpr direkt in nkParenExpr ohne Operator dazwischen.
  Vorsicht: explizite Klammern bei Mixed-Precedence sind LEGITIM
  (siehe `fkConfusingAndOrPrecedence`).
  Datei: `Detectors/uRedundantParens.pas` (neu).

- [ ] **`fkRedundantVisibility`**
  `private`-Sektion direkt gefolgt von `private`-Sektion (User
  hat aus Versehen zweimal `private` geschrieben statt z.B.
  `protected`). Analog `public public`. AST: leere Visibility-
  Section-Folgen.
  Datei: `Detectors/uRedundantVisibility.pas` (neu).

- [ ] **`fkRedundantStorageClass`**
  Doppelte Modifier-Tokens: `procedure Foo; override; override;`,
  `function Bar; virtual; virtual;`, `var x: const const Integer;`.
  Compiler erlaubt manche dieser Mehrfach-Marker still, andere als
  Warning. Detektor sammelt alle Modifier-Token-Listen und meldet
  Duplikate.
  Datei: `Detectors/uRedundantModifier.pas` (neu).

- [ ] **`fkAbstractOnInterfaceMethod`**
  In `IFoo = interface … procedure DoX; abstract;` ist `abstract`
  redundant — alle Interface-Methoden sind implizit abstract.
  Hint-Severity, Quick-Fix: Modifier streichen.
  Datei: `Detectors/uCodeSmells2.pas` (Erweiterung).

- [ ] **`fkFinalOnNonVirtual`**
  `procedure Foo; final;` ohne `override` ist No-Op (`final`
  blockiert weitere Überrides, aber nur ergibt Sinn auf override-
  Methoden). Hint mit Quick-Fix: streichen.
  Datei: `Detectors/uCodeSmells2.pas` (Erweiterung).

- [ ] **`fkUselessInitializer`**
  Record-Field-Default-Initializer für Werte die der RTL-Default
  ohnehin liefert: `myInt: Integer := 0`, `myStr: string := ''`,
  `myPtr: TObject := nil`. Nur für **Record**-Felder, NICHT für
  lokale Vars (dort ist `:= 0` keineswegs der Default).
  Datei: `Detectors/uUselessInitializer.pas` (neu).

- [ ] **`fkUnsortedUses`**
  `uses`-Klausel mit nicht-alphabetisch sortierten Identifikatoren.
  RTL-/System-Units gruppieren (`System.*`, `Vcl.*` separat).
  Style-only, Severity Hint, off by default. Existierende
  Convention vieler Open-Source-Codebasen.
  Datei: `Detectors/uUnsortedUses.pas` (neu).

- [ ] **`fkLongLine`**
  Physische Zeile > 100 Zeichen (konfigurierbar via
  `[Detectors] MaxLineLength=100`). Skip für Kommentare die URLs
  enthalten, und für `const`-Definitionen mit langen String-
  Literalen.
  Datei: `Detectors/uLongLine.pas` (neu).

- [ ] **`fkLocalVarCouldBeConst`**
  Lokale `var` die nie wieder zugewiesen wird (single assignment)
  → kann `const` werden. Im Pascal-Sinne also tatsächlich
  `const X = …;` (typed const oder echte const). AST: pro
  lokale Var Anzahl der LHS-Assigns zählen; 1 = Kandidat.
  Datei: `Detectors/uVarCouldBeConst.pas` (neu).

#### Naming / Doc

- [ ] **`fkNamingConvention`**
  Konfigurierbarer Naming-Check basierend auf Delphi-Konventionen:
  - Klassen: `T`-Prefix (`TFoo`, nicht `Foo` oder `MyFoo`)
  - Interfaces: `I`-Prefix
  - Generische Typparameter: `T` oder single uppercase letter
  - Fields: `F`-Prefix in Klassen
  - Globals: `G`-Prefix empfohlen
  - Konstanten: `UPPER_SNAKE` oder `PascalCase`
  Per-Pattern abschaltbar via INI.
  Datei: `Detectors/uNamingConvention.pas` (neu).

- [ ] **`fkPublicMethodNoXmlDoc`**
  Public-Sektion-Methoden ohne `///`- oder `{///}`-XMLDoc-
  Kommentar direkt davor. Skip private/protected/strict private.
  Skip auto-generierte (Designer-Code, IDE-Hooks).
  Off by default — viele Codebasen verzichten bewusst auf XMLDoc.
  Datei: `Detectors/uMissingXmlDoc.pas` (neu).

- [ ] **`fkVarShadowsLabel`**
  Lokale `var X` mit gleichem Namen wie ein `label`-Eintrag.
  Selten, aber wenn vorhanden ein klares Lesbarkeits-Problem.
  Datei: `Detectors/uCodeSmells2.pas` (Erweiterung).

- [ ] **`fkMemberShadowsBuiltinProp`**
  Klassen-Field mit Namen wie `Name`, `Tag`, `ClassName`, `Owner`
  (TComponent-Built-Ins). Konflikt-Risiko bei späterem
  Inheritance-Wechsel zu TComponent.
  Datei: `Detectors/uCodeSmells2.pas` (Erweiterung).

#### Statement-Patterns

- [ ] **`fkReversedForRange`**
  `for i := 10 to 1 do` läuft 0 Iterationen (silent No-Op).
  Wahrscheinlich Tippfehler — `for i := 10 downto 1 do` gemeint.
  AST: nkForStmt mit konstanter LHS > RHS bei `to`-Richtung.
  Datei: `Detectors/uReversedForRange.pas` (neu).

- [ ] **`fkFunctionMissingResult`**
  `function`-Body ohne expliziten `Result :=`-Assign oder
  `Exit(value)`. Kompiler-Warnung W1035, aber als SCA-Detektor
  mit besserer Kontextierung (welche Methode, welche Branches
  fehlen).
  Datei: `Detectors/uMissingResult.pas` (neu).

- [ ] **`fkEmptyStatement`**
  Doppelte oder triple Semikolons `;;` außerhalb von
  `for …;;` (C-Style-Loop-Header — Delphi hat das nicht;
  also alle `;;` verdächtig). Hint mit Quick-Fix: collapse.
  Datei: `Detectors/uCodeSmells2.pas` (Erweiterung).

- [ ] **`fkUnusedLabel`**
  `label`-Eintrag deklariert aber kein `goto X;` im Body. Da
  `goto` selten ist, ist jedes deklarierte label das nicht
  benutzt wird mit hoher Wahrscheinlichkeit Dead-Code.
  Datei: `Detectors/uUnusedLabel.pas` (neu).

#### Architektur / Visibility (Cross-Unit-Analyse)

- [ ] **`fkCanBePrivate`** — Public-Member ohne projekt-weite externe Referenz
  Methoden, Fields, Properties in der `public`/`published`-Sektion
  einer Klasse, die NIEMALS von einer anderen Unit referenziert
  werden. Kandidaten zum Verschieben nach `private` (oder
  `protected` wenn von Subklassen genutzt). Klassisches
  "Encapsulation-Tightening" — reduziert API-Oberflaeche und
  zeigt versehentlich exportierte Helper auf.
  - **Skip wenn:**
    - Methode ist `override` oder `virtual`/`abstract` (Vererbungs-
      Hook, koennte von externer Subklasse benutzt werden)
    - Methode ist Interface-Impl (`procedure Foo; override;` mit
      passender Interface-Method)
    - Methode ist publizierter Event-Handler (DFM-Referenz —
      `uDfmRepoIndex` weiss das schon)
    - Klasse ist im `interface`-Teil eines Pakets das als BPL
      ausgeliefert wird (alles public = Plugin-API)
    - Designer-generierter Code (`{$R *.dfm}`-Bindings)
  - **Severity Hint** (kein Bug, nur Lesbarkeit/Encapsulation).
  - **Cross-Unit-Anforderung:** braucht repo-weiten Symbol-Index
    analog zu `uDfmRepoIndex` — pro Unit muss bekannt sein
    welche externen Symbole sie referenziert. Vorhandener
    AST-Walk koennte ein zweites Pass-Modell pro `AnalyzeBatch`
    aufbauen (Pass 1: alle Public-Symbole sammeln, Pass 2: alle
    Referenzen aus anderen Units, Pass 3: Diff).
  - **Quick-Fix-Idee:** "Move to private" — Member-Block-Boundary
    finden, Member-Deklaration verschieben, Forward-Refs falls
    noetig setzen.
  Datei: `Detectors/uCanBePrivate.pas` (neu), benoetigt neuen
  `Infrastructure/uSymbolReferenceIndex.pas` fuer Cross-Unit-
  Lookup.

- [ ] **`fkCanBeProtected`** — Variante: Public-Member nur aus
  Subklassen referenziert (gleiche Vererbungs-Kette), nicht von
  fremden Klassen. Kandidat fuer `protected`. Setzt
  `fkCanBePrivate`-Infrastruktur voraus.
  Datei: `Detectors/uCanBePrivate.pas` (gleicher Detektor, zwei
  Severity-Levels).

- [ ] **`fkUnusedPublicMember`** — Public-Member ohne JEDE
  Referenz, weder intern noch extern. Striktere Variante von
  `fkCanBePrivate` — der Member kann komplett geloescht werden,
  nicht nur versteckt. Schaerfere Severity (Warning statt Hint).
  Datei: `Detectors/uCanBePrivate.pas` (gleicher Detektor).

---

## 🧪 Tests

- [ ] **Unit-Tests für `TDetectorUtils`**
  Edge-Cases:
  - `FindWholeWordLower('', 'haystack')` → 0
  - `FindWholeWordLower('a', 'a')` → 1
  - `FindWholeWordLower('foo', '_foo_')` → kein Match (Underscore)
  - `IsIdentChar` mit Sonderzeichen, Numerals
  Neue Datei: `tests/uTestDetectorUtils.pas`

- [ ] **Plattformunabhängige Tests**
  Hardcodierte Windows-Pfade brechen auf Linux/macOS-CI:
  - `uTestAnalyserChecks.pas:3204` (`'D:\does\not\exist\nirvana.pas'`)
  - `uTestAnalyserChecks.pas:3226` (`'D:\nirgendwo\unbekannt'`)
  Lösung: `TPath.Combine(TPath.GetTempPath, 'sca_nirvana_' + Guid)`

- [ ] **Performance-Tests mit Soft-Schwellen**
  `uTestPerformance.pas:183, 222, 269, 314` haben harte Timeouts
  (`< 10000ms`) → flaky auf langsamen CI-Maschinen.
  Lösung: nur Warnung loggen oder Timeout aus Umgebungsvariable.

- [ ] **Schwache Asserts ersetzen**
  Pattern `Assert.IsTrue(F.Count > 0)` ohne Inhaltsprüfung — sollte
  `Assert.AreEqual(1, CountOfKind(F, fkXxx))` sein. ~30+ Stellen in
  `uTestAnalyserChecks.pas`.

- [~] **Test-Daten-Factory** — _teils erledigt (Helper da, Migration pending)_
  Neue Unit `tests/uTestSrcBuilder.pas` mit zwei Helpern:
  - `Src(['line1', 'line2'])` joined mit CRLF (ersetzt das
    `'...'#13#10+`-Pattern fuer beliebige Zeilen)
  - `ProcInUnit(Name, Vars, Body)` baut eine komplette Mini-Unit mit
    Methode + optionaler var-Sektion + Body
  Demonstriert in `Leak_AssignFromFieldDottedNoParens_NoFinding`.
  Migration der ~280 Bestand-Tests bleibt: schrittweise wenn Tests
  ohnehin angefasst werden, NICHT als Blockmigration (Risiko vs. Nutzen).
  Delphi-Constraint: `const SRC = ProcInUnit(...)` geht nicht (kein
  Funktionscall in Constants), daher `var SRC: string := ...`.

- [ ] **Coverage-Lücken abdecken**
  - `TodoComment` (10 Tests) — ausbaubar
  - `DuplicateBlock` (10 Tests)
  - `FieldLeak` — kaum Tests
  - Encoding-Edge-Cases (UTF-8-BOM, UTF-16, Windows-1252) gar nicht

- [ ] **Suppression-Tests für `// noinspection All`-Variante**
  Sicherstellen dass alle 21 Kinds vom `All`-Branch erfasst werden.

- [ ] **Tests für `uVcsChanges` (Git/SVN-Integration)**
  Aktuell ungetestet — wird nur durch manuelles Klicken auf
  „Branch-Changes" verifiziert. Mit einem Temp-Repo-Helper:
  - Git: `git init`, Datei anlegen, committen, ändern → erwarten dass
    geänderte Datei erkannt wird
  - SVN: nur `svn status`-Mock (echtes svn-Setup zu komplex für CI)
  - VCS-CLI fehlt: erwarten klare Fehlermeldung, nicht AV
  Datei: neue `tests/uTestVcsChanges.pas`

- [ ] **Tests für `uExport` (CSV / JSON / HTML / Jira)**
  Roundtrip: Liste → Export → wieder einlesen (CSV/JSON) bzw. HTML/
  Jira-Output gegen Snapshot. Encoding-Edge-Cases (Sonderzeichen,
  lange Pfade, leere Liste). **0 Tests heute.** UTF-8-BOM-Verifikation
  ist nach jüngstem Fix wichtig.

- [ ] **Tests für `uClaudePrompt`**
  Snapshot-Test des erzeugten Markdown-Blocks: Header, Code-Snippet
  ±5 Zeilen, Marker auf richtiger Zeile, Vorher/Nachher. Edge-Cases:
  Befund auf Zeile 1 (kein „vor"), letzte Zeile (kein „nach"), Datei
  mit nur 3 Zeilen.

- [ ] **Tests für `uLocalization`**
  - `_('Errors')` mit `SetLanguage('de')` → `'Fehler'`
  - Format: `_('%d findings', [5])` → korrekte Übersetzung + Substitution
  - Unbekannter Key: Passthrough = Source-String
  - Sprachwechsel mehrfach hintereinander (de → fr → en) ohne Leak

- [ ] **Apostroph-Escape in Tests verifizieren**
  Nach `HtmlEscape`-Update werden Apostrophe immer als `&#39;` escaped.
  Falls Tests rohen Output-Vergleich machen → anpassen.

- [ ] **Detektoren ohne Tests** (Inventur aus Code-Review)
  Mindestens je ein Happy-Path + ein No-Finding-Test:
  `uTodoComment` (Edge-Cases zusätzlich), `uDuplicateBlock`,
  `uDuplicateString`, `uHardcodedPath`, `uMagicNumbers`, `uDeepNesting`,
  `uLongMethod`, `uLongParamList`, `uEmptyMethod`, `uDebugOutput`,
  `uFieldLeak`, `uCustomClassDiscovery`, `uSQLInjectionScore`,
  `uFormatMismatch`, `uHardcodedSecret`, `uDivByZero`, `uNilDeref`,
  `uDeadCode`, `uMissingFinally`.

- [ ] **Lexer-/Parser-Edge-Cases**
  - Hex-Literal direkt gefolgt von `..` (Range-Operator)
  - Anonymous Methods mit nested var-Block
  - Inline-`var x: T := …` mit Konstruktor im Initializer
  - Suppression auf File mit nur Kommentaren
  - Suppression-Marker auf letzter Code-Zeile (EOF)
  - VcsChanges UTF-8 Pfade / Chunk-Boundary
  - RegEx-Race unter parallelem WatchMode + Main-Scan

- [ ] **Tests für `uIDELineHighlighter` / `uIDEWatchMode` / `uIDEMessages`**
  0 Tests heute. Deckung:
  - `EnsureViewNotifier`-Idempotenz, `DetachAll`-Wiederverwendbarkeit
  - WatchMode: Debounce, Generation-Race, Double-Activate, Deactivate-
    während-Worker-läuft
  - SeverityPrefix-Mapping, ClearAllMessages-Side-Effect
  Erfordert teilweise ToolsAPI-Mock.

- [ ] **Tests für `uIDEAnalyserForm.ApplyFilter` / Sort-Comparer**
  ~150 LOC Filter+Sort-Logik unverifiziert. SeverityRank-Reihenfolge
  und FileKey-rel-Path-Branches ungetestet.

- [ ] **Tests für `uAnalyserTheme.BlendColor` / `SeverityBg`**
  Ratio-Bounds (negativ, > 1) und `clNone`-Propagation ungetestet.

---

## 📋 Bekannt-aber-akzeptiert (kein Fix geplant)

- **Compiler-Errors verschwinden im Messages-Pane bei Scan-Start**
  Tradeoff für `ClearAllMessages` aus früherer Variante. IDE-Messages-
  Spiegelung ist heute komplett deaktiviert (siehe [docs/done.md](docs/done.md)) —
  TODO obsolet falls Spiegelung später re-aktiviert wird.

- **WatchMode + Plugin-Unload ohne explizites Worker-Cancel**
  Wenn User „Components → Remove Package" während ein Watch-Worker
  läuft, kann die Synchronize-Callback in freed Memory landen → AV.
  Sehr selten, akzeptiert. Workaround für User: WatchMode in INI
  ausschalten bevor Plugin entfernt wird.

- **`uClaudePrompt` schluckt Encoding-Fehler beim Snippet-Lesen**
  Bewusst — Snippet ist ein „best effort"-Feature, nicht
  analyse-kritisch.

- **Floating-Mode-Theme nicht live aktualisiert**
  `INTACustomDockableForm` exposes keinen offiziellen Hook für
  Theme-Reapply auf der Wrapper-Form. Workaround: Plugin docken oder
  schließen+öffnen nach Theme-Wechsel.

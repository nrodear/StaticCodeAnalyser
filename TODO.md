# TODO

Offene Aufgaben für **Static Code Analysis Tool for Delphi**.
Sortiert nach Priorität: 🔴 Bug / 🟡 Robustheit / 🟢 Wartbarkeit / 🚀 CI-Mode / 💡 Feature / 🧪 Tests / 📋 Akzeptiert / 📝 Erledigt-History.

---

## 🔴 Bugs / Korrektheit

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

- [ ] **`uDeadCode.CheckBlock` rekursiv ohne Bound**
  Rekursiert in `nkBlock`/`nkIfStmt`/...-Children — gleiches Stack-
  Overflow-Risiko, das `uAstNode.FindAll`/`FindFirst` schon iterativ
  umgangen haben. Pathologisch tiefe ASTs crashen den Detektor.
  Datei: `Detectors/uDeadCode.pas:54-61`
  Lösung: iterativer Work-Stack analog zu `uAstNode.CollectAll`.

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

- [ ] **Memory-Detektor: `CreateUtf8`/`CreateFmt`/`CreateAfterAttach` nicht erkannt**
  `HasCreateAssign` sucht `.create` und prueft Right-Boundary auf
  Non-Ident — `createu`/`createf`/`creater` schlagen fehl. Effekt:
  `E := EOrmException.CreateUtf8('%', [...])` und alle anderen
  mORMot-typischen Konstruktoren werden NICHT als Create-Assignment
  erkannt → kein Leak-Tracking.
  Beispiel-Volumen: 75+ `CreateUtf8`/`CreateFmt`-Vorkommen in mORMot2
  (`orm/mormot.orm.rest.pas:2139` etc.). Seltener bei Free-relevant
  (Exceptions reraised), aber Pattern ist universell.
  Datei: `Detectors/uLeakDetector2.pas:130-137`
  Lösung: explizite Whitelist von Konstruktor-Suffixen (`Utf8`, `Fmt`,
  `From`, `AfterAttach`, ...) zulassen, oder Right-Boundary auf
  CamelCase prüfen statt non-Ident.

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

- [ ] **SQL-Detektor: `Format`/`FormatUtf8`-basierter SQL ungeprueft**
  `ExecuteFmt('SELECT * FROM % WHERE Id=%', [tbl, id])` ist klassisch
  mORMot. Kein `+` im Code → `HasNonLiteralPlus` matcht nicht →
  **komplett uebersehen**, obwohl `%` strukturell als Tabellenname
  einen realen Injection-Vektor erzeugt.
  Datei: `Detectors/uSQLInjection.pas:42`
  Lösung: zusaetzliche Heuristik fuer `Format(.., [..])` /
  `FormatUtf8`/`FormatSQL`/`ExecuteFmt`-Calls mit SQL-Keyword im
  Format-String.

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

- [x] **HardcodedPath: UNC mit `_`/`-` im Servernamen verworfen** — _erledigt_
  CharSet im UNC-Servername-Branch um `'_'` und `'-'` erweitert
  (RFC 952/1123, gaengige interne Hostnamen). `\\my-srv\share` und
  `\\_internal\share` werden jetzt erkannt.
  Datei: `Detectors/uHardcodedPath.pas:43-46`

- [ ] **DivByZero: `mod`-Pattern via TypeRef nicht zuverlässig**
  Detektor sucht `' mod '` in `nkAssign.TypeRef`, aber die String-Form
  in TypeRef ist je nach Parser-Pfad nicht garantiert. Beispiel:
  `core/mormot.core.base.pas:10130` `size := len mod size;` mit
  Parameter `size` ohne Guard → sollte Warning, kommt aber je nach
  Expression-Capture moeglicherweise nicht.
  Datei: `Detectors/uDivByZero.pas`
  Lösung: AST-strukturierte Operator-Erkennung statt TypeRef-String-Pos.

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

- [ ] **`uHardcodedSecret.IsSecretName` Coverage erweitern**
  Aktuelle Tests prüfen Defaults (`secretary` als false-positive bereits
  abgedeckt). Fehlend: `tokenize`, `passport`, `keyboard` (alle sollten
  KEIN Match sein).

- [ ] **Docked-Mode UI: zuverlässige Anzeige notwendiger Bedienelemente**

  **Status quo (aktuell, fragil):**
  - `TResponsiveVisibilityController` hookt `Panel.OnResize`, toggelt
    `Visible` basierend auf Width-Schwelle (BREAKPOINT_DOCKED=700)
  - 4 Controller-Instanzen über 3 Panels + 1 Stats-Panel
  - `TAnalyserFrame.Resize` (override) forwarded an alle Panel-OnResizes,
    weil OnResize aus IDE-Dock-Logik teilweise verschluckt wird
  - `AdjustFilterSubPanels` hängt parallel an `PanelButtons.OnResize`
    und passt Sub-Panel-Widths an Label-Visibility an
  - Action-Buttons in `PanelSearch` summieren sich auf ~486 px im docked,
    überlaufen bei typischen 350-400 px Dock weiterhin
  - **Bekannte Schwachstellen:** mehrere Race-Conditions zwischen
    Dock-Resize und Controller-Init; chained OnResize fragil/debug-unfriendly;
    Hamburger-Visibility hat schon 3× Hin und Her gemacht

  **Phase 1: Stabilisieren (kurzfristig, Mini-Risk)**
  - Dock-State direkt erkennen (statt Width-Heuristik): `HostDockSite <> nil`
    oder `INTAEditWindow.IsFloating` aus ToolsAPI. Width bleibt Fallback.
  - PanelSearch im Docked: `BtnAnalyse` + `FBtnAnalyseCurrent` kollabieren
    auf Icon-Buttons (28 px, "▶"/"📄") oder wandern ins Hamburger-Menü.
    Ergibt PanelSearch-Belegung ~250 px - passt unter 350.
  - `FSearchEdit.Constraints.MinWidth` im Docked auf 60 px (statt 120).
  - Initial-State garantiert deterministisch: `inherited Create` -> komplett
    fertige UI -> EINMAL `RecomputeResponsiveLayout` am Ende statt mehrere
    `ApplyVisibility`-Calls aus Controller-Constructors.
  - Datei: `uIDEAnalyserForm.pas` + `uIDEStatsTiles.pas`

  **Phase 2: Layout-Architektur sauberer (mittel)**
  - Inline `TPanel`-Ketten mit hardcoded Widths ersetzen durch
    `TFlowPanel` oder eigene `TToolbarLayout`-Komponente die natives
    Overflow-Handling kennt (Controls wrappen oder kollabieren in
    Dropdown/More-Button).
  - Deklarative Layout-Config statt 4 Controller-Instanzen pro Panel:
    ```
    FToolbar.AddButton(BTN_ANALYSE, _('Start analysis'),     prAlways);
    FToolbar.AddButton(BTN_CURRENT, _('Current file'),       prAlways);
    FToolbar.AddButton(BTN_BRANCH,  _('Branch-Changes'),     prFloated);
    FToolbar.AddSeparator;
    ...
    ```
    `prFloated` heißt: nur sichtbar wenn floated, sonst im Hamburger.
  - Sub-Panel-Container-Trick (PanelSev/PanelType für Label+Combo)
    weg - Margin/Padding statt Wrapper-Panel.

  **Phase 3: Two-Mode-UI (groß)**
  - Statt Visibility-Toggle: zwei komplett verschiedene Toolbar-Aufbauten.
    Bei Dock-State-Change wird die ALTE Toolbar zerstört + die NEUE
    aufgebaut.
    - **Floated-Mode:** aktuelle volle Toolbar (3 Reihen)
    - **Docked-Mode:** EINE schmale Toolbar mit
      `[▶ Analyse ▾] [🔍 Search] [≡ Menu] [✕ Cancel]`
  - Eliminiert die ganze responsive-controller-Komplexität.
    Trade-off: Code-Duplikat zwischen den beiden Modi.

  **Phase 4: Polish (Nice-to-have)**
  - User-Pref persistieren (z.B. "Tile-Reihe immer aus", "Toolbar
    minimal") in `analyser.ini`.
  - Smooth Transition beim Dock-State-Change (`FlickerFree` flag).
  - Theme-Variante speziell für Compact-Mode (Tile-Glyphs kleiner,
    weniger Padding).

  **Reihenfolge-Vorschlag:** Phase 1 zuerst - der eigentliche Bug
  (PanelSearch zu breit + Initial-State-Race) wird gefixt ohne
  Architektur umzubauen. Phase 2 ist ein größerer Refactor (lohnt sich
  wenn weitere Detector-Filter-Buttons dazukommen). Phase 3 ist nur
  sinnvoll wenn der responsive-Ansatz sich als grundsätzlich
  unbeherrschbar erweist.

  Datei: `StaticCodeAnalyserIDE/uIDEAnalyserForm.pas` (+ neue Layout-
  Komponente in Phase 2)

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

- [ ] **Hardcoded deutsche Strings in IDE-Form außerhalb `_()`**
  Beim i18n-Sweep übersehen:
  - `uIDEAnalyserForm.pas:1400` — `'Keine Eintraege fuer diesen Filter.'`
  - `uIDEAnalyserForm.pas:1735` — `'[watch] updated %s (%d findings)'`
  - ~~`uIDEAnalyserForm.pas:2067` — `'Analysiere: '`~~ → erledigt: jetzt
    in `uIDEAnalyseRunner.RunCurrent` als `_('Analyzing: ')`.
  - `uIDEAnalyserForm.pas:2268` — `'Ignore-Liste neu geladen ...'`

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

## 🚀 Console-Mode / CI-Integration

Großer separater Block — nichts von dem hier ist trivial, aber alles
hängt zusammen (CLI-Mode ist die Voraussetzung für CI-Integration).

- [ ] **Headless-CLI-Mode für `analyser.d12.exe`**
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

- [ ] **Report-Formate für CI-Tools**
  Mehrere Standard-Formate, je ein Output-Switch:
  - `--report-junit sca.xml` — JUnit-XML, GitLab-CI / GitHub Actions /
    Jenkins kompatibel
  - `--report-sarif sca.sarif` — [SARIF v2](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/sarif-support-for-code-scanning),
    GitHub Code-Scanning-fähig (Findings im PR sichtbar)
  - `--report-sonar sca-sonar.json` — SonarQube Generic Issues
  - `--report-checkstyle sca-checkstyle.xml` — breitester Tool-Support
    (BitBucket, Phabricator, GitLab)
  - `--report-codeclimate sca-cc.json` — GitLab Code-Quality Widget
  - `--report-html sca.html` — bestehender Report aus `uExport`,
    self-contained, fürs Build-Artefakt

  Datei: `Output/uReportFormats.pas` (neu), nutzt vorhandene
  Finding-Liste, getrennt von der UI-orientierten `uExport.pas`.

- [ ] **GitHub-Action / GitLab-CI Beispielworkflows**
  `.github/workflows/sca.yml` und `examples/.gitlab-ci.yml` —
  copy-paste-fertig, nutzt CLI + SARIF/JUnit-Output.

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
  Spiegelung ist heute komplett deaktiviert (siehe Erledigt-History) —
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

---

## 📝 Erledigt (für die History)

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

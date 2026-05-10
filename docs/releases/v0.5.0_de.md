## v0.5.0 — Pre-Release

Erste oeffentliche Version des **Static Code Analysis Tool for Delphi**.
21 AST-basierte Detektoren, IDE-Plugin (RAD Studio 12 Athens) und Standalone-VCL-App.

### Features

- **AST-basierte Analyse** mit eigenem Lexer + Parser (uParser2), iterative Traversierung
- **Sonar-Style Klassifikation**: Bug / CodeSmell / Vulnerability / SecurityHotspot / CodeDuplication
- **Quality-Score** (gewichtete Summe, niedriger = besser)
- **Sonar-Style Tile-UI** im IDE-Plugin (Severity- + Type-Buckets)
- **Branch-Changes-Modus**: nur in Git/SVN geaenderte .pas-Dateien analysieren
- **VCS-Integration** mit Timeout + Process-Kill (60s Hardlimit)
- **Claude-AI-Prompt-Generierung** pro Befund (Markdown mit Code-Kontext und Vorher/Nachher)
- **Suppression** via `// noinspection <Kind>`-Kommentaren
- **Export**: HTML / JSON / CSV / Jira-Markup / Plain-Text
- **DE-Lokalisierung** der UI (eingebautes Dictionary)
- **Repo-Settings** ueber `analyser.ini` (BaseBranch, IncludeWorkingTree, Tortoise-Pfade)
- **Ignore-Liste** ueber `ignore.txt` (Glob-Patterns)
- **Tortoise-Git/SVN-Kompatibilitaet** (PATH-Suche + Standard-Installpfade)

### Detektoren

**Memory / Bugs:** MemoryLeak, FieldLeak, NilDeref, MissingFinally, DivByZero, FormatMismatch
**Security:** SQLInjection, HardcodedSecret, HardcodedPath
**Code Smells:** EmptyExcept, EmptyMethod, DeadCode, UnusedUses, DebugOutput, LongMethod, LongParamList, DeepNesting, MagicNumber, TodoComment
**Duplication:** DuplicateString, DuplicateBlock

### Requirements

- Windows 10/11
- (Plugin) RAD Studio 12 Athens
- (Standalone) keine - kompiliert als single EXE

### Bekannte Einschraenkungen

- Keine Binaries in diesem Release - nur Source. Plugin (BPL) und Standalone (EXE) selbst bauen.
- Floating-Point-Division (`/`) wird vom DivByZero-Detektor nicht geprueft
- Schwellwerte (LongMethod=50 Zeilen etc.) sind aktuell hardcoded

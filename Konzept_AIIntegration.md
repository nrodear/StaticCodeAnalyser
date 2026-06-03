# Konzept: AI als zweite Stufe der Code-Analyse

Wie kann ein klassischer Static-Code-Analyzer (SCA) mit Large-Language-
Models (LLM) kombiniert werden, um:

- **False-Positives reduzieren** ohne die Symboltabelle/CFG/Type-System
  zu bauen (Konzept_ScannerQualitaet §B.1+§A.4 sind 3-5d-Sprints —
  AI-Triage könnte 80 % davon abdecken in 1d Integration)
- **Bugs finden** die kein expliziter Detector covered (semantische
  Anti-Patterns, Architektur-Smells, Dead-Code-Cluster)
- **Fixes liefern** statt nur Befunde

Stand: Konzept-Phase. Implementierung folgt nach Review.

---

## 1. Status Quo + Lücken

### Was wir haben

| Komponente | Stand |
|---|---|
| Parser + AST (`uParser2`, `uAstNode`) | Sub-set Pascal — `nkUnit`/`nkClass`/`nkMethod`/`nkAssign`/`nkCall`/`nkIfStmt`/`nkForStmt`/etc. |
| ~165 Detektoren | AST + lexisch + line-based-Hybrid |
| File-Cache, Symbol-Index, DFM-Index | OK |
| `uClaudePrompt` | Erzeugt Markdown-Prompt für Click-to-Clipboard (User pastiert manuell in Claude/GPT/Gemini) |
| Confidence-Tagging (A.1) | fcLow/Medium/High pro Kind |
| SARIF / Baseline / `contextHash` | OK für CI |

### Was wir nicht haben (Tatsachen-Liste)

**Parser-Lücken** (Pascal-Konstrukte die als undurchsichtige TypeRef-
Strings landen statt als echte AST-Knoten):

| Konstrukt | Heutige Behandlung | Konsequenz |
|---|---|---|
| `if`/`while`/`case`-Conditions | Token-Sequenz in `TypeRef` | Sub-Calls erst seit Phase 2.2 erkannt (SCA166) |
| `nkAssign.RHS` | Token-Sequenz in `TypeRef` | Sub-Calls erst seit Phase 2.3 erkannt |
| Expression-Bäume (Operator-Bäume) | flach als Text | Detektoren wie `uTautologicalExpr` machen Regex statt AST |
| Generics-Instanziierung (`TList<TFoo>`) | `TList<TFoo>` als String | Typ-Resolution unmöglich |
| Anonymous Methods (`procedure begin end`) | als nested `nkMethod` mit auto-Name | Variable-Capture nicht trackbar |
| Attributes (`[Inject]`) | meist verloren | RTTI-driven Code wird als unused erkannt |
| Conditional-Compile (`{$IFDEF}`) | Lexer nimmt alle Branches | Deadbranch-Detection unmöglich (Konzept-A.5) |
| `with`-Statement-Scope | als Comment-Hinweis | Member-Resolution unmöglich |
| `inherited`-Aufrufe ohne Argumente | unklar | virtual-call-Tracking unzuverlässig |
| Property-Getter/Setter-Dispatching | als Field-Access | Cross-Reference unsicher |
| Interface-Implementation-Klauseln (`implements`) | partiell | Interface-Method-Mapping fehlt |

**Semantik-Lücken** (was eine echte Type-/Flow-Analyse kann, wir nicht):

- Type-Inference (`var X := foo();` — was ist X?)
- Symbol-Resolution über Inheritance-Chains
- Path-Sensitivity (`if-then-else` mit beidseitigem Write — Phase 3 A.4)
- Cross-Procedure Data-Flow (Taint-Tracking — Konzept B.3)
- Effect-System (welche Methoden mutieren globalen State?)

### Wo das die FP-Rate kostet

Aus SCA166-Phase-2-Audit konkret beziffert:

| Pre-Phase | FP-Quelle | Pessimistic-Workaround |
|---|---|---|
| Phase 1 MVP | Calls in `if`/`while` | manuelle Regex |
| Phase 2.2 | Calls in `nkAssign.RHS` | manuelle Regex |
| **Verbleibend** | Sub-Expression-Calls, Generics, mit-Scopes, RTTI-Driven-Members | **kein einfacher Fix mehr ohne AST/Symbol-Refactor** |

**Schlussfolgerung:** wir haben die offensichtlichen Hot-Spots
abgearbeitet. Die nächsten 50 % FP-Reduktion liegen entweder hinter
**3-5d Symboltabelle (B.1) + Expression-AST (B.2)** oder hinter
**AI-Triage (1d Integration)**.

---

## 2. Recherche: Delphi-Syntax-Vollständigkeit

### Pascal/Delphi-Sprach-Referenzen

- **Embarcadero Doku** — [Object Pascal Reference](https://docwiki.embarcadero.com/RADStudio/Athens/en/Object_Pascal_Reference)
  ist die kanonische Quelle. Deckt:
  - Klassische Pascal-Syntax (ISO 7185 / Extended Pascal)
  - Object-Pascal-Erweiterungen (Klassen, Interfaces, Generics,
    Anonymous Methods, Attributes, Records mit Methoden, Helper)
  - RTTI + Extended-RTTI
  - Inline-Variablen (10.3+), Type-Inferenz (10.4+)
- **ISO 10206:1990** — Extended Pascal. Veraltete Grundlage, aber
  Object-Pascal liegt darüber.
- **SonarDelphi-Parser** — [communitydelphi/sonar-delphi](https://github.com/integrated-application-development/sonar-delphi)
  hat einen vollständigen ANTLR-Grammatik. Referenz für AST-Knoten-
  Typen die wir noch nicht haben.

### Konstrukte die unser Parser noch NICHT als eigene Knoten hat

| # | Konstrukt | Aktueller Stand | Detector-Impact |
|---|---|---|---|
| 1 | Expression-Operator-Bäume (`a and b or c`) | TypeRef-String | uTautologicalExpr / uBoolAlwaysTrue arbeiten Regex-basiert |
| 2 | Inline-Variable mit Type-Inference (`var x := Foo`) | partiell als nkLocalVar mit leerem TypeRef | UnusedLocal/UninitVar können Typ nicht klassifizieren |
| 3 | Generic-Type-Parameter (`T` in `TList<T>.Add(T)`) | als Text | Type-Helper-Resolution unmöglich |
| 4 | Anonymous Method-Body | nested nkMethod | Closure-Capture wird nicht getrackt |
| 5 | Attribute-Annotationen (`[Inject]`, `[TestAttribute]`) | meist verloren beim Tokenizing | DI-Container-Members fälschlich als unused geflaggt |
| 6 | Class-Helper / Record-Helper | wie normale Klasse | Erweiterungs-Semantik geht verloren |
| 7 | `implements` (Interface-Delegation) | nicht aufgelöst | Interface-Method-Cross-Reference fehlt |
| 8 | `for X in Container` mit Custom-Enumerator | nkForStmt mit `in` | Custom-Enumerator-Methods werden als unused geflaggt |
| 9 | Operator-Overloads | als nkMethod mit speziellem Namen | keine Symmetrie-Checks möglich |
| 10 | Compiler-Direktiven `{$IFDEF}` / `{$IF}` | Lexer nimmt alle Branches | nicht-aktive Branches fließen in den Scan ein |

### Aufwand für vollständigen Parser

Realistische Schätzung pro Lücke: **2-5 Tage** für saubere AST-Knoten-
Implementation + Parser-Erweiterung + Test-Suite. **30+ Tage** für
alle 10. Plus laufende Pflege wenn Delphi 13+ neue Konstrukte einführt
(Coroutinen wurden für 13 angekündigt).

→ Vollständigkeits-Pfad ist teuer und nie "fertig".

---

## 3. Recherche: Wie LLMs Code validieren

### Vergleichsmatrix existierender Tools

| Tool | LLM-Pattern | Stärke | Schwäche |
|---|---|---|---|
| **CodeRabbit** | PR-Review-Bot, vor-merge | holistisch, kommentiert Diff-Hunks | nur PR-Kontext, nicht ganzes Repo |
| **SonarQube AI Code Assurance** (2024+) | AI-Triage auf Sonar-Findings + AI-Fix-Suggestions | nutzt existing Static-Analyzer als Anker → fokussiert | LLM-Calls kostenpflichtig pro Finding |
| **DeepSource AI Autofix** | Auto-Fix-Branch per LLM | direkter Wert für User | Static-Analysis-Erstkategorie nötig |
| **GitHub Copilot Workspace** | Task-driven (Issue → Plan → Edit → PR) | full-stack | nicht Static-Analyzer-Fokussiert |
| **Codacy Coverage AI** | KI-Coverage-Empfehlungen | Test-Generation | weniger Code-Review |
| **Cursor / Aider / Claude Code** | Editor-integriert | iterative Co-Pilot-Workflows | nicht headless / CI |
| **Snyk Code DeepCode AI** | Eigenes Model auf Bug-Korpus | sehr präzise für Security-Bugs | proprietary, Subscription |
| **Anthropic Claude API / OpenAI Chat Completions** | Roh-API | volle Kontrolle | wir bauen die Pipeline selber |

### Drei dominante LLM-Code-Validation-Pattern

#### Pattern A: AI-as-Triage (FP-Filter)

- **Input:** Static-Analysis-Finding + Code-Snippet (~10-50 Zeilen Kontext)
- **Output:** „echt" / „false positive" / „unsicher" + Begründung
- **Vorteil:** günstig (~1-5k Tokens pro Finding), zielgerichtet
- **Nachteil:** LLM kann eigentliche Symbol-Information immer noch
  nur aus dem Snippet ableiten — wenn Cross-Unit-Info nötig wäre,
  rät der LLM
- **Skalierung:** bei 991k Findings × Tokens nicht trivial — User
  würde nur kritische Subsets (z.B. `--profile bugs-only` × `fcHigh`)
  durchschleusen

#### Pattern B: AI-as-Detector (Holistische Review)

- **Input:** ganzes Pas-File (oder Method-Body) + ggf. Symbol-Tabelle-
  Hint
- **Output:** Liste von Bug-Findings ohne vorherigen Detector-Anker
- **Vorteil:** findet semantische Bugs, Architektur-Smells, Patterns
  die wir nicht codiert haben
- **Nachteil:** teuer (50-200k Tokens pro großes File), schwer
  reproduzierbar, FP-Rate nicht kontrollierbar
- **Skalierung:** macht auf 100-1000-File-Repos Sinn, nicht auf
  100k+ LoC-Codebases

#### Pattern C: AI-as-Fixer (Auto-Patch)

- **Input:** Finding + Code-Region + Vorher/Nachher-Beispiele
- **Output:** konkreter Patch / Pull-Request-fähiger Diff
- **Vorteil:** direkt umsetzbarer Mehrwert für den User
- **Nachteil:** Patch-Verifikation/Test braucht Build-Loop; rein
  text-basierte LLM-Fixes können brechen
- **Skalierung:** OK für kuratierte „opt-in"-Stellen, nicht für
  Auto-Apply

### Was die SOTA empfiehlt (Stand 2026)

- **Anthropic Claude (Sonnet/Opus 4.x)** und **OpenAI GPT-4o/o1** sind
  beide für Code-Review erprobt. Claude tendiert zu „besseren
  Begründungen", GPT zu „mehr Volume". Beide haben strukturierte
  Output-Modi (JSON-Schema-Garantie).
- **Local-Models** (Llama 3.1 70B, DeepSeek-Coder 33B, StarCoder2)
  sind machbar aber für Pascal-Syntax-Verständnis schwach (Trainings-
  Korpus dominiert von Python/JS/TS/Go).
- **Hybrid-Pattern dominiert:** Static-Analyzer als „cheap recall" +
  LLM als „expensive precision". Niemand ersetzt Static-Analysis
  durch LLM komplett.

### Privacy / Cost / Reproducibility

| Aspekt | Implikation |
|---|---|
| **Datenschutz** | Code via API an Anthropic/OpenAI → bei kommerziellen Repos zu klären. Anthropic + OpenAI bieten „no training on customer data" + Zero-Retention-Optionen. Self-hosted-Modelle als Fallback. |
| **Kosten** | Claude Sonnet ~3 USD / Mio Input-Tokens, ~15 USD / Mio Output. Pro Finding-Triage ~5 Cent. Bei 1 000 Findings/Day = 50 USD/Day = 1 500 USD/Monat — nicht skalierbar ohne Filterung |
| **Reproducibility** | LLM-Antworten sind nicht deterministisch (auch mit `temperature=0` ist es nur „best effort"). Für CI-Gates problematisch. Pragma: LLM-Output als „advisory" labeln, nicht als „blocker" |
| **Latency** | API-Round-Trip ~2-10 s pro Finding. Inline-IDE-Use OK, CI-Pipeline-Use auch (parallelisierbar). Real-Time-Hint im Editor: zu langsam |

---

## 4. SCA-spezifische Integrations-Optionen

Aus den Patterns A/B/C abgeleitet auf unser Repo:

### Option 1 — AI-FP-Triage als optionaler Post-Filter (Pattern A)

**Was:** Pipeline-Stufe nach `uConfidenceFilter`. User opt-in via
`--ai-triage` CLI-Flag oder IDE-Button „AI Review Selected Findings".

**Trigger:** nur Findings mit `Confidence in [fcMedium, fcLow]` und
optional nur ausgewählten Kinds (z.B. SCA166 UninitVar, SCA052
UnusedPublicMember — heuristische Detektoren mit viel FP-Risiko).

**Prompt-Template:** existiert teilweise schon (`uClaudePrompt.pas`).
Erweitern um JSON-Output-Schema:

```json
{
  "verdict": "true_positive" | "false_positive" | "uncertain",
  "confidence": 0.0..1.0,
  "reason": "...",
  "suggested_fix": "..."
}
```

**Effekt:** Bei SCA166 mit aktuell 994 Findings, davon ~700 fcMedium
→ ~700 LLM-Calls × 5 Cent = **35 USD pro Real-World-Scan**. Tolerierbar
für CI-Quality-Gate, zu teuer für jeden Commit. CI-Use-Case:
nightly + PR-spezifisch (`--branch` Mode beschränkt auf geänderte
Files → 10-50 Findings → 0.5-2.5 USD).

**Implementation:** ~1d. Modul `uAiTriageProvider` mit interface
`IAiProvider.Triage(Finding, Snippet): TAiVerdict`. Drei
Implementations:
- `TClaudeApiProvider` (Anthropic API)
- `TOpenAiApiProvider` (OpenAI API)
- `TLocalOllamaProvider` (lokales Llama via HTTP — privacy)

### Option 2 — AI-Generierter Fix (Pattern C)

**Was:** Auf User-Klick „Generate Fix for this Finding" → LLM-Patch
in Editor-Vorschau. Im Standalone-Modus per Clipboard + Diff-Viewer,
im IDE-Plugin direkt als Refactoring-Vorschlag.

**Effekt:** Direkter User-Value, aber LLM-Patches haben FP-Rate. User
muss review-en. **Build-Verifikation:** nicht automatisierbar (CLI-
Build-Block, siehe Memory). Optional „Apply + Run Tests" wenn User
Tests hat.

**Implementation:** ~2d. Erweitert `uClaudePrompt`-Output um „request
patch"-Variante + Response-Parser. UI-Diff-Vorschau braucht eigene
Komponente (in IDE-Plugin existiert SynEdit, nutzen).

### Option 3 — AI als Pseudo-Detector für nicht-codierte Patterns (Pattern B)

**Was:** Per-File „AI Holistic Review" — kein Detector-Anker, einfach
ganze File an LLM mit Prompt „liste alle Code-Smells und Bugs auf".

**Output:** Findings die im SARIF-Output unter `customRule = AI`
erscheinen. RuleID `AI001` etc.

**Effekt:** Findet Patterns die wir nicht codiert haben (Architektur-
Smells, Naming-Inkonsistenzen, Test-Coverage-Lücken). Aber teuer
(~20-100k Tokens pro File). Skalierung: User pickt ein File und
sagt „AI deep review" — nicht volltexturierter Scan.

**Implementation:** ~3d. Eigenes Output-Format-Mapping (LLM-JSON →
TLeakFinding). Suppression via `// noinspection AI001` etc.
Confidence: alle fcMedium.

### Option 4 — AI-Detector-Generator (Meta-Pattern)

**Was:** User hat ein Bug-Sample. Klick „Generate Detector for this
Pattern" → LLM produziert einen Pascal-Detector-Code (analog zu
uHardcodedSecret.pas) der dieses Pattern erkennt.

**Effekt:** Lange Lernkurve für SCA-Detector-Entwicklung kürzer.
Aber LLM-generierter Code muss reviewed werden + getestet.

**Implementation:** ~5d (Prompt-Engineering, Code-Generation,
Sandbox-Compile-Test, Suite-Integration).

### Option 5 — AI als Symboltabelle-Surrogat (Hybrid)

**Was:** Statt B.1 (Symboltabelle, 1 Monat Aufwand) bauen, nutzen wir
LLM als „on-demand Type-Resolver" für FP-Triage. Beispiel: Detector
findet `Foo.Bar` und weiß nicht ob `Bar` ein Field oder Method ist.
LLM-Call mit File-Kontext: „Was ist Foo.Bar in diesem Code? Field /
Method / Property?".

**Effekt:** Killer-FP-Reduktion für Detektoren die heute am Symbol-
Lookup leiden (Visibility, UnusedMember). Aber pro Detector-Call
ein LLM-Call → multi-tausende Calls pro Scan → teuer und langsam.

**Implementation:** ~3d für die Pipeline + Caching-Layer. Cache
muss persistent sein (LLM-Verdicts überleben Scans), sonst
unbezahlbar.

### Empfehlung (Priorisiert)

| # | Option | Aufwand | Wert | Risiko |
|---|---|---|---|---|
| **1** | **Option 1 AI-FP-Triage** | 1d | hoch (FP-Killer) | gering (opt-in, advisory) |
| **2** | **Option 2 AI-Fix-Generierung** | 2d | hoch (direkter User-Value) | gering (UI-Vorschau, User entscheidet) |
| 3 | Option 5 Symbol-Surrogat | 3d + Cache | mittel (komplex) | mittel (Caching-Bugs) |
| 4 | Option 3 Holistic Review | 3d | mittel (one-off-Use-Case) | mittel (Output-Format-Mapping) |
| 5 | Option 4 Detector-Generator | 5d | niedrig (rare User-Action) | hoch (LLM-Code-Quality) |

---

## 5. Architektur — Modul-Skizze

### Schicht: Provider-Abstraktion

```
+----------------------------+
| IAiProvider                |  <- interface in uAiProvider.pas
+----------------------------+
| Triage(F, Ctx): TVerdict   |
| Fix(F, Ctx): TPatch        |
| HolisticReview(File): TList|
+----------------------------+
       ^         ^         ^
       |         |         |
   Claude      OpenAI    Ollama (local)
   Provider    Provider  Provider
```

### Schicht: Pipeline-Integration

Vor / nach den existierenden Filtern:

```
1. Detectors                              [bestehend]
2. uSuppression (// noinspection)         [bestehend]
3. uPathOverrides                         [bestehend]
4. uConfidenceFilter                      [bestehend]
5. uTestFixtureFilter (A.2)               [bestehend]
6. uBaseline                              [bestehend]
7. uAiTriageFilter (NEU, opt-in)          [Option 1]
8. uOutput (SARIF / HTML / Sonar / ...)   [bestehend]
```

`uAiTriageFilter` ist standardmäßig OFF. Aktivierung via
`--ai-triage=anthropic|openai|local` und ENV `SCA_AI_API_KEY`.

### Schicht: Provider-Implementation

Pro Provider:

```pascal
unit uAiProvider.Claude;

interface

type
  TClaudeApiProvider = class(TInterfacedObject, IAiProvider)
  private
    FApiKey : string;
    FModel  : string;     // 'claude-sonnet-4-6' default
    FBudget : Integer;    // max USD pro Run, Hardcap
  public
    constructor Create(const ApiKey, Model: string;
      BudgetUsdCent: Integer = 1000);
    function Triage(F: TLeakFinding; const Snippet: string): TAiVerdict;
    function Fix(F: TLeakFinding; const Snippet: string): TAiPatch;
    function HolisticReview(const FileName, Source: string):
      TObjectList<TLeakFinding>;
  end;
```

### Schicht: Verdict-Cache

Persistenter Cache (`~/.sca/ai-cache.json`) keyed by:

```
key := SHA256(provider + model + finding.contextHash + finding.kind + finding.message)
```

Cache-Hit = LLM nicht erneut bemüht. Verdict-Stale wenn:
- Code-Snippet-Hash ändert sich (Refactor)
- Model-Version ändert sich

### Schicht: Output-Erweiterung

SARIF-Output bekommt zusätzliches Property pro Finding:

```json
{
  "ruleId": "SCA166",
  "message": "...",
  "properties": {
    "aiVerdict": "false_positive",
    "aiConfidence": 0.87,
    "aiReason": "Variable is initialized via FillChar on line 247...",
    "aiProvider": "claude-sonnet-4-6"
  }
}
```

HTML-Report bekommt eine zusätzliche Spalte „AI" mit grünem
Häkchen / rotem X / grauem Fragezeichen.

---

## 6. MVP-Pfad — pragmatischer Sprint

### Sprint 1 (3-5d) — Option 1 produktionsreif

1. `IAiProvider` Interface + `TClaudeApiProvider` (Anthropic API
   Reference-Impl)
2. JSON-Schema für Triage-Output
3. Persistent Cache
4. CLI-Flag `--ai-triage`
5. SARIF-Property-Erweiterung
6. Cost-Budget-Cap (default 100 USD pro Run, Halt bei Überschreitung)
7. Test-Suite mit Stub-Provider (kein echter API-Call)

### Sprint 2 (1-2d) — Option 2 als Opt-In

1. „Generate Fix"-Button im IDE-Plugin
2. Diff-Vorschau via SynEdit
3. Clipboard-Output für Standalone

### Sprint 3 (1d) — UX-Verfeinerung

1. IDE-Plugin: AI-Spalte im Grid
2. Filter „nur AI-confirmed bugs anzeigen"
3. Documentation

### Sprint 4 (optional) — Local-Provider

1. `TLocalOllamaProvider` für Privacy-sensitive Users
2. Default-Model `ollama/codellama` oder `ollama/qwen2.5-coder`
3. Auto-detect localhost Ollama, sonst skip

**Gesamt-Investment für MVP:** 5-10d. Liefert messbaren Wert ab
Sprint 1.

---

## 7. Konkrete erste Implementierung — Vorschlag

Wenn dieses Konzept abgesegnet wird, würde ich starten mit:

### Datei-Layout

```
StaticCodeAnalyserForm/sources/AI/
  uAiProvider.pas              (interface)
  uAiProvider.Claude.pas       (Anthropic-Impl)
  uAiProvider.OpenAi.pas       (OpenAI-Impl)
  uAiProvider.Stub.pas         (für Tests)
  uAiTriageCache.pas           (persistent JSON-Cache)
  uAiTriageFilter.pas          (Pipeline-Integration)
  uAiBudget.pas                (Cost-Cap)
StaticCodeAnalyserForm/tests/
  uTestAiTriage.pas            (Stub-Provider-Tests)
```

### Erstes konkretes Datei-Listing (Skizze)

```pascal
unit uAiProvider;

interface

uses
  System.Generics.Collections, uMethodd12;

type
  TAiVerdict = (avTruePositive, avFalsePositive, avUncertain);

  TAiTriageResult = record
    Verdict    : TAiVerdict;
    Confidence : Single;     // 0..1
    Reason     : string;
    SuggestedFix : string;   // optional
    TokensUsed : Integer;
    Provider   : string;
  end;

  IAiProvider = interface
    ['{...}']
    function Triage(F: TLeakFinding; const Snippet: string): TAiTriageResult;
    function ProviderName: string;
    function EstimateCostUsd(F: TLeakFinding; const Snippet: string): Single;
  end;
```

### Erstes Test-Szenario

```pascal
[Test] procedure TriageWithStubProvider_ReturnsFalsePositive;
  // Stub liefert immer avFalsePositive - prueft Pipeline-Integration
  // ohne echten API-Call.
```

---

## 8. Privacy / Compliance / Risiken

| Risiko | Mitigation |
|---|---|
| **Code wird an externe API geschickt** | Default = AI-Pipeline AUS. Opt-in über Flag. Klare Doku im README. Local-Provider als 1st-class-Option für Compliance-Konsumenten. |
| **API-Kosten explodieren** | Hardcap pro Run (`SCA_AI_MAX_USD_PER_RUN`, default 100 USD). Pre-Run Cost-Estimate + User-Confirmation im CLI. |
| **LLM-Verdict nicht reproduzierbar** | Cache (Verdict-Hash). LLM-Output ist „advisory" — niemals als CI-Blocker. Original Static-Analysis-Severity bleibt führend. |
| **LLM-Halluzinationen** | JSON-Schema-validierter Output. Bei Schema-Fail: skip Finding, log warning. |
| **API-Down / Rate-Limit** | Graceful degradation: alle Findings durchlassen wenn API nicht erreichbar. Log-Warnung, keine Fehler-Exit-Codes. |
| **Cross-Repo-Symbol-Info noch immer fehlt** | LLM rät auf Snippet-Basis. Pragmatische Lösung: in den Prompt zusätzlich relevante Symbole aus `gSymbolRefIndex` packen. |

---

## 9. Erfolgs-Kriterien

| Metrik | Heute (v0.9.8) | Ziel nach Sprint 1 |
|---|---|---|
| SCA166 FP-Rate | ~70 % (geschätzt aus Konzept §13) | ~30 % (LLM filtert klare FPs) |
| Per-Detector-Triage-Coverage | 0 % | 100 % für fcMedium/fcLow |
| User-Action „Apply AI Fix" | n/a | erste UX-Tests |
| Run-Cost auf Real-World-Korpus (994 SCA166-Findings) | n/a | < 5 USD pro Scan (mit Cache-Hit-Rate > 70 %) |
| CI-Latency-Add-On | n/a | < 2 Minuten parallelisiert |

---

## 10. Was NICHT in diesem Konzept ist

- **LLM ersetzt klassische Static-Analysis** — explizit nicht. Klassische
  Detektoren bleiben „first line of defense" (deterministisch,
  reproduzierbar, kostenlos, fast).
- **Auto-Apply-Fix ohne User-Review** — explizit ausgeschlossen.
- **LLM für jede Datei in Realtime** — zu langsam, zu teuer.
  AI-Triage ist Post-Scan-Phase, IDE-Hints sind explizit per-Click.
- **LLM-eigenes Modell-Training** — wir nutzen kommerzielle APIs +
  local fine-tuned Models. Eigenes Fine-Tuning auf Pascal-Korpus
  ist 6-Monats-Projekt, nicht in Scope.

---

## 11. Empfehlung

**Ja, AI-Integration ist die richtige nächste Stufe.** Begründung:

1. Klassische Parser-Vollständigkeit kostet 30+ Tage und liefert
   inkrementell.
2. AI-Triage kostet 1d Integration und kann 50-70 % der verbleibenden
   FPs killen.
3. AI-Fix-Generierung ist der naheliegende nächste User-Mehrwert
   (Click-to-Fix statt Click-to-Clipboard).
4. Privacy-Bedenken adressierbar via Local-Ollama-Provider + Opt-in.

**Konkreter Vorschlag:** Sprint 1 (Option 1 AI-FP-Triage, 3-5d) als
nächster Schritt. Bei Erfolg automatisch Sprint 2 (AI-Fix-Generierung).

Phase 3 (CFG) und Phase 4 (Symboltabelle) aus `Konzept_ScannerQualitaet`
bleiben als Backup-Plan, wenn AI-Triage nicht den erhofften FP-Killer-
Effekt hat.

---

## 12. Offene Entscheidungen vor Implementation

1. **Default-Provider**: Anthropic Claude (besseres Code-Reasoning) vs
   OpenAI GPT-4o (mehr Volume). **Empfehlung: Claude Sonnet 4.x.**
2. **Cost-Cap-Default**: 10 USD / 100 USD / unlimited? **Empfehlung: 100 USD,
   explizite Bestätigung wenn überschritten.**
3. **Cache-Location**: `~/.sca/ai-cache.json` (user-global) vs
   `<projectroot>/.sca-ai-cache.json` (per-project)? **Empfehlung:
   per-project + gitignored** (Verdicts sind project-specific).
4. **API-Key-Source**: ENV-Var, INI-Datei, oder Windows Credential
   Manager? **Empfehlung: ENV-Var primary, INI als Fallback,
   keine Klartext-Speicherung.**
5. **Triage-Target**: nur fcMedium/fcLow, oder auch fcHigh? **Empfehlung:
   alle, aber fcHigh nur wenn User es explizit anfordert
   (`--ai-triage-all`).**
6. **JSON-Schema-Validation**: harte Validation oder
   best-effort-Parse? **Empfehlung: best-effort mit Stub-Fallback.
   Bei Schema-Fail: Verdict = avUncertain, Reason = LLM-Raw-Output.**

---

## 13. Verwandte Konzepte

- [`Konzept_ScannerQualitaet.md`](Konzept_ScannerQualitaet.md) §B.1+§B.2
  — die AST/Symboltabelle die AI-Triage adressieren würde
- [`Konzept_ScannerQualitaet.md`](Konzept_ScannerQualitaet.md) §A.4 CFG
  — würde Phase 3 von SCA166 unblocken, AI-Triage kürzt das ab
- [`Konzept_SCA166_UninitVar.md`](Konzept_SCA166_UninitVar.md) §13 —
  konkretes Beispiel wo AI-Triage 70 % der verbleibenden FPs killen
  könnte ohne Phase 3
- `uClaudePrompt.pas` — die bereits existierende Manual-Prompt-Building-
  Infrastruktur, die wir wiederverwenden

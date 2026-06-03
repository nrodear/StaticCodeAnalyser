# ARD: Warum SCA bewusst KEINE automatische AI-Integration hat

**Architecture Decision Record.** Dokumentiert die bewusste Entscheidung
gegen LLM-basierte Code-Analyse-Stufen.

Status: Final. Wenn künftig jemand "lass uns ein LLM einbauen" vorschlägt,
ist die Antwort hier.

---

## 1. Frage

Kann man die verbleibenden False-Positives (FPs) klassischer Detektoren
durch eine LLM-Stufe reduzieren — z.B. AI-FP-Triage, AI-Fix-Generierung,
AI-Holistic-Review?

## 2. Antwort

**Nein.** Der Static-Code-Analyser existiert *gerade weil* die Code-
Basis nicht an externe AI-APIs gehen darf. Eine automatische AI-Pipeline
würde dem Existenzzweck des Tools widersprechen.

## 3. Begründung

### 3.1 Privacy / Compliance ist nicht-verhandelbar

Typische SCA-Anwender:

- Firmen-Repos mit IP / Trade Secrets im Code
- Regulierte Branchen (Banking, Health, Government) mit hard-no-data-
  egress-Policy
- Behörden / Defense mit Air-Gap-Anforderungen
- Open-Source-Projekte unter Lizenzen die Drittanbieter-Forwarding
  problematisch machen

Ein LLM-Call schickt **Code-Snippets** an einen externen API-Endpoint.
Auch mit „no-training"-Klauseln + Zero-Retention bleibt:

- Network-Egress nachweisbar (Compliance-Audit)
- Single-Point-of-Failure: API-Provider-Breach betrifft alle User
- Vendor-Lock-in / Pricing-Risk
- Latenz / Verfügbarkeits-Abhängigkeit

Diese Punkte sind **Designs-Constraint Nummer 1** des SCA und dürfen
nicht durch Convenience-Features kompromittiert werden.

### 3.2 Reproduzierbarkeit ist Pflicht für CI

CI-Quality-Gates müssen deterministisch sein. LLM-Output ist
nicht reproduzierbar (auch mit `temperature=0`):

- Ein Commit der gestern grün war, kann morgen rot sein — gleiche
  Eingabe, andere LLM-Antwort
- Pre-Merge-Reviews werden unzuverlässig
- Bug-Bisecting via SARIF-Baseline funktioniert nicht mehr
- Auditierbar nur durch Speichern aller LLM-Antworten (zusätzlicher
  Compliance-Aufwand)

### 3.3 Offline-Use ist explizites Feature

Der Standalone-Modus + IDE-Plugin laufen **ohne Internet**. Im
Branch-Modus (Pre-Commit-Hook) muss der Scan auch im Flugzeug, ohne
VPN, beim Kunden vor Ort funktionieren. Eine LLM-Pipeline würde das
brechen.

### 3.4 Kosten skalieren mit Repo-Größe

Bei 991 000 Findings × 5 Cent/Triage = **50 000 USD pro Real-World-
Scan** ohne Caching. Mit Caching beim Erst-Scan immer noch nicht
trivial. Statische Analyse ist konstant kostenfrei pro Run.

### 3.5 Klassische Verbesserung ist möglich und finanzierbar

Phase 2/3/4 aus [`Konzept_ScannerQualitaet.md`](Konzept_ScannerQualitaet.md):

- **B.1 Symboltabelle pro Unit** (3-5d) — adressiert den Großteil der
  Symbol-Resolution-FPs ohne externe Abhängigkeit
- **B.2 Expression-AST-Knoten** (~1 Woche) — ersetzt Regex-Workarounds
  durch echten AST-Walk
- **A.4 CFG für UseAfterFree** (3-5d) — Path-Sensitivity ohne LLM
- **A.5 IFDEF-Branch-Awareness** — Compile-Direktiven richtig auswerten

Diese Maßnahmen sind **einmalige Investitionen**, danach läuft jeder
Scan deterministisch, offline, gratis und reproduzierbar.

## 4. Was bleibt erlaubt

Der SCA hat eine **manuelle, user-getriggerte AI-Anbindung** über
[`uClaudePrompt.pas`](StaticCodeAnalyserForm/sources/Output/uClaudePrompt.pas):

- User **klickt** ein Finding
- Tool baut einen Markdown-Prompt mit Code-Snippet + Finding-Metadaten
- Tool kopiert den Prompt in die **Clipboard**
- User wechselt manuell zu Claude / GPT / Gemini und pastiert

**Warum das OK ist:** der User entscheidet pro Finding ob das Snippet
extern verarbeitet werden darf. Es gibt keinen automatischen Egress.
Das passt auch zu CI-Compliance-Audits (kein Code geht über die
Tool-Pipeline raus).

Diese manuelle Integration darf **erweitert** werden:

- ✅ Bessere Prompt-Templates pro Detector-Kind
- ✅ Multi-Finding-Prompts (mehrere Findings in einem Markdown-Block)
- ✅ Lokalisierte Prompts (DE / EN)
- ✅ Anti-Pattern-Beispiele im Prompt

Aber nicht:

- ❌ Automatischer API-Call (auch nicht opt-in über CLI-Flag)
- ❌ AI-Triage als Pipeline-Stufe
- ❌ AI-Fix-Auto-Generation im Tool selbst
- ❌ Background-LLM-Service / Daemon

## 5. Was wenn ein User trotzdem will?

Der User hat alle nötigen Hooks:

- SARIF-Export → eigene Pipeline kann das an einen LLM weitergeben
- CLI-Output strukturiert → grep-bar
- HTML-Report mit Per-Finding-Links

Wer auf eigene Verantwortung externen LLM nutzen will, kann eine
**Wrapper-Script-Layer** drumherum bauen. Das ist user-territory,
nicht tool-territory.

## 6. Alternativen die wir gehen

Statt LLM-Investition gehen wir den klassischen Pfad:

1. **`Konzept_ScannerQualitaet.md` Phase 2** — Engine-Extraction (D.1) +
   Singleton-Entkopplung (D.2)
2. **`Konzept_ScannerQualitaet.md` Phase 3** — Symboltabelle (B.1) +
   Expression-AST (B.2). Adressiert ~70 % der heute verbleibenden FPs.
3. **`Konzept_SCA166_UninitVar.md` Phase 3** — CFG-Builder
4. **`Konzept_ScannerQualitaet.md` Phase 4** — Optional je nach Bedarf

## 7. Re-Evaluation

Diese Entscheidung wird re-evaluiert wenn:

- Self-hosted LLMs (Llama / DeepSeek) für Pascal-Syntax verlässlich
  werden UND der User es opt-in haben will (immer noch nicht
  Pipeline-Default)
- Die Privacy-Landschaft sich fundamental ändert (z.B. attestable
  confidential computing für LLM-Inference)
- Eine konkrete Nicht-AI-Lösung für die verbleibenden FPs versucht
  wurde und nachweisbar nicht ausreicht

Bis dahin: **keine AI in der Code-Pipeline**.

---

## 8. Verwandte Dokumente

- [`Konzept_ScannerQualitaet.md`](Konzept_ScannerQualitaet.md) — der
  klassische Roadmap-Pfad für FP-Reduktion ohne LLM
- [`Konzept_SCA166_UninitVar.md`](Konzept_SCA166_UninitVar.md) §11 —
  Phase 3 CFG ist Beispiel für klassische Lösung der Path-Sensitivity
- [`uClaudePrompt.pas`](StaticCodeAnalyserForm/sources/Output/uClaudePrompt.pas)
  — manuelle Click-to-Clipboard-Anbindung, die einzige erlaubte
  AI-Integrationsform

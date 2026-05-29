# Audit: Alle Detektoren gegen [HowTo_AddDetector.md](HowTo_AddDetector.md)

Prüf-Konzept + Live-Snapshot der Registrierungs-Vollständigkeit aller Detektoren gegen die 23-Punkte-Checkliste. Kombination aus **automatisierten Konsistenz-Tests** (die meiste Arbeit) + gezielten **manuellen Cross-Checks** (für Punkte ohne Test-Coverage).

## Stand (Snapshot 2026-05-30)

| Quelle | Zähler | Erwartete Relation |
|--------|-------:|--------------------|
| Detector-`.pas`-Dateien in `sources/Detectors/` | **153** | Basis |
| `TFindingKind`-Enum-Einträge in `uSCAConsts.pas` | **161** | ≥ Dateien (aggregierende Detektoren emittieren mehrere Kinds) |
| `KIND_META`-Records in `uSCAConsts.pas` | **161** | = Enum-Count |
| Regel-IDs `SCAxxx` in `rules/sca-rules.json` | **161** | = KIND_META-Count |
| `case`-Branches in `uFixHint.pas` | **161** | = KIND_META-Count |
| `AddD(...)` in `uStaticAnalyzer2.BuildAllDetectors` | **130** | < Dateien (aggregator-Adapter wie `DfmAnalysisRunner` zählt 1×, `CustomRuleDetector` + `CustomClassDiscovery` laufen out-of-band) |
| Test-`.pas`-Dateien in `tests/` | **169** | Detektor + Infra-Tests + Helfer |
| Test-Units in `TestProject.dpr` | **146** | < Test-Dateien (Helfer wie `uTestFindingHelper`, `uTestSrcBuilder` ohne Fixture) |
| `<DCCReference>` für Detektoren in Standalone `.dproj` | **153** | = Dateien ✅ |
| `<DCCReference>` für Detektoren in IDE `.dproj` | **153** | = Dateien ✅ |
| Detector-uses in Standalone `.dpr` | **153** | = Dateien ✅ |
| Detector-`contains` in IDE `.dpk` | **153** | = Dateien ✅ |

**Sofort sichtbare Vollständigkeit:** Die vier Projektdatei-Register (`.dpr`/`.dproj` × Standalone/IDE) decken **alle 153 Detector-Dateien zu 100% ab**. Die vier Kataloge (Enum / KIND_META / Rules-JSON / FixHint) sind konsistent **zu 161 Kinds**.

---

## Audit-Methodik nach den 23 Checklist-Punkten

Jeder Punkt aus [HowTo_AddDetector.md](HowTo_AddDetector.md) ist entweder durch einen **automatisierten Test** abgedeckt, durch eine **manuelle Grep-Kontrolle** prüfbar, oder muss **pro Detektor** geprüft werden. Diese Aufteilung:

### A. Vollautomatisch durch Tests (rote Lampe wenn etwas fehlt)

| # | Prüfung | Test |
|---|---------|------|
| 2,3 | `TFindingKind` ↔ `KIND_META` ausgerichtet | `TTestRuleCatalog.EveryFindingKindHasRule` |
| 5 | `KIND_META` ↔ `sca-rules.json` aligned (jedes Kind hat Rule) | `TTestRuleCatalog.EveryFindingKindHasRule` |
| 5 | Rules haben Pflicht-Metadaten | `TTestRuleCatalog.EveryFindingKindHasRichMetadata` |
| 5 | Rules haben MQR-Mapping (`cleanCodeAttribute` + `impacts`) | `TTestRuleCatalog.EveryFindingKindHasMqrMapping` |
| 3 | Jeder `KIND_META.Name` ist eindeutig | `TTestSuppressionCompleteness.EveryKindNameIsUnique` |
| 3 | Jeder `KIND_META.Name` ist via `KindFromName` reverse-lookup-bar | `TTestSuppressionCompleteness.EveryKindNameResolvesViaKindFromName` |
| 8,9 | `// noinspection <Name>` funktioniert für jedes Kind | `TTestSuppressionCompleteness.EveryKindCanBeSuppressedEndToEnd` |

> **Wenn diese Tests grün laufen, sind Checklist-Punkte 2, 3, 5 für ALLE existierenden Detektoren automatisch verifiziert.** Das eliminiert ~50% der manuellen Audit-Arbeit.

### B. Manuell mit Grep prüfbar (eine Tabelle, jede Spalte ein Grep)

Für jeden Detektor `uXxx.pas` müssen folgende Vorkommen existieren:

| # | Soll | Grep-Pattern |
|---|------|--------------|
| 7 | `case fkXxx:` in `uFixHint.pas` | `grep -E "^\s+fk{Name}\s*:" sources/Output/uFixHint.pas` |
| 10 | `AddD('Xxx', fkXxx,` in `BuildAllDetectors` | `grep "AddD.*fk{Name}" sources/Infrastructure/uStaticAnalyzer2.pas` |
| 12 | Detektor-Aufruf in `uTestFindingHelper.FindingsOf` oder `FindingsOfFile` | `grep "T{Name}Detector.AnalyzeUnit" tests/uTestFindingHelper.pas` |
| 11 | Test-Unit `uTest{Name}.pas` existiert | `ls tests/uTest{Name}.pas` |
| 13 | Test-Unit in `TestProject.dpr` registriert | `grep "uTest{Name} in" tests/TestProject.dpr` |
| 14 | Test-Unit in `TestProject.dproj` registriert | `grep "uTest{Name}.pas" tests/TestProject.dproj` |
| 15 | Detector in Standalone `.dpr` | `grep "u{Name} in" StaticCodeAnalyser.d12.dpr` |
| 16 | Detector in Standalone `.dproj` | `grep "u{Name}.pas" StaticCodeAnalyser.d12.dproj` |
| 17 | Detector in IDE `.dpk` | `grep "u{Name} in" ../StaticCodeAnalyserIDE/*.dpk` |
| 18 | Detector in IDE `.dproj` | `grep "u{Name}.pas" ../StaticCodeAnalyserIDE/*.dproj` |

Aggregat-Zahlen (Snapshot oben) zeigen: für #15–18 ist die Gesamtsumme korrekt (153/153/153/153). Für #7/#10 sind die Aggregate-Zahlen erwartet kleiner als 153 (Aggregator-Detektoren), aber die **Konsistenz pro Kind** ist über die Test-Suite gesichert.

### C. Per-Detektor manuell zu prüfen (nicht aggregat-prüfbar)

| # | Prüfung | Wie |
|---|---------|-----|
| 1 | Detector-Code-Qualität (AST vs File-scan, Edge-Cases) | Code-Review pro Detektor — siehe `Konzept_GridPerformance150k.md` und letztes Audit (`fix(detectors)`-Commit `9c51dfd`) |
| 4 | `IsSonarDelphiKind` korrekt für SCA060+ | `grep "fk[A-Z]" uSCAConsts.pas` und gegen die Funktion verifizieren |
| 6 | Profile-Block in `sca-rules.json` enthält das Kind (falls gewünscht) | JSON parsen; default-Profile `default` enthält implizit alle |
| 8 | i18n-Strings in `de.po` vollständig | `xgettext`-Lauf gegen Quelltext + Diff vs po-Datei |
| 9 | i18n-Strings in `en.po` vollständig | dito |
| 19–21 | Combobox-Filter-Eintrag (nur wenn dediziert gewünscht) | manuell entscheiden pro Detektor; keine Pflicht |
| 22 | Build grün | IDE-Build |
| 23 | Konsistenz-Tests grün | TestProject in TestInsight/CLI |

---

## Vollständigkeits-Audit ausführen

### Schritt 1 — Konsistenz-Tests laufen lassen (deckt A)

In der IDE `TestProject` (DUnitX) laufen lassen. Speziell diese Fixtures müssen grün sein:

- `TTestRuleCatalog` (alle Methoden)
- `TTestSuppressionCompleteness` (alle Methoden)

Wenn **eine** rot ist, ist genau die in der Fehler-Message genannte Kind-Konstante das Problem — Punkt-2/3/5/8 für dieses Kind prüfen.

### Schritt 2 — Manueller Cross-Check (deckt B)

Für jede `uXxx.pas` in `sources/Detectors/` ein Skript laufen lassen das Punkte 7, 10, 11, 12, 13, 14 verifiziert. Skelett:

```bash
for f in StaticCodeAnalyserForm/sources/Detectors/u*.pas; do
  name=$(basename "$f" .pas | sed 's/^u//')
  fix_hint=$(grep -c "fk${name}\s*:" StaticCodeAnalyserForm/sources/Output/uFixHint.pas)
  add_d=$(grep -c "AddD(.*fk${name}" StaticCodeAnalyserForm/sources/Infrastructure/uStaticAnalyzer2.pas)
  test_file=$(test -f "StaticCodeAnalyserForm/tests/uTest${name}.pas" && echo 1 || echo 0)
  test_dpr=$(grep -c "uTest${name} in" StaticCodeAnalyserForm/tests/TestProject.dpr)
  test_helper=$(grep -c "T${name}Detector.AnalyzeUnit" StaticCodeAnalyserForm/tests/uTestFindingHelper.pas)
  printf '%-30s fix=%d addD=%d test=%d dpr=%d helper=%d\n' \
    "$name" "$fix_hint" "$add_d" "$test_file" "$test_dpr" "$test_helper"
done | sort
```

Die Aggregate-Zahlen aus dem Snapshot:
- `fix_hint`-Summe = 161 (über alle Detektor-Files; einige Files emittieren mehrere Kinds)
- `addD`-Summe = 130 (Aggregator + out-of-band wie oben erklärt)
- `test_file`-Summe ≈ 100+ (nicht jeder Detektor hat dedizierte Tests)
- `test_dpr`-Summe ≈ 100+ (gleiche Detektoren wie `test_file`)
- `test_helper`-Summe ≈ alle die nicht aggregator/out-of-band sind

### Schritt 3 — Aggregator + out-of-band-Detektoren explizit verifizieren (Lücken in B)

Detektoren die NICHT direkt in `BuildAllDetectors` stehen aber per Aggregator/Sonderpfad laufen — hier ist die Vollständigkeit fragiler:

| Aggregator | Wo registriert | Wo werden Detektor-Aufrufe gemacht | Lücken-Symptom |
|------------|----------------|-------------------------------------|----------------|
| `TDfmAnalysisRunner` | `AddD('DfmAnalysis', fkDfmDefaultName, ...)` in `BuildAllDetectors` | `uDfmAnalysisRunner.pas` ruft alle `TDfmXxxDetector.AnalyzeFile` intern auf | Wenn ein neuer `fkDfmYyy` ein zugehöriger `TDfmYyyDetector.AnalyzeFile` aber NICHT in `uDfmAnalysisRunner` invoked wird → Detector läuft nie |
| `TCustomRuleDetector` | Eigene `AnalyzeFile` aus `ParseLeaks` aufgerufen | `uCustomRuleDetector.pas` | YAML-Custom-Rules, andere Lebenszyklus |
| `TCustomClassDiscovery` | Eigener Pre-Pass im `ParseLeaks`-Loop | `uCustomClassDiscovery.pas` | Auto-Discovery, kein Findings-Output |

Für diese drei muss der entsprechende Sonderpfad pro neuem Sub-Detektor explizit gepflegt werden — keine Pflicht-Linie in `BuildAllDetectors`.

### Schritt 4 — i18n-Audit (deckt C/8/9)

```bash
# Alle _()-Strings im Quelltext sammeln und gegen .po-msgids diffen
grep -roE "_\('([^']*)'\)" StaticCodeAnalyserForm/sources/ \
  | sed -E "s/.*_\('([^']*)'\).*/\1/" | sort -u > /tmp/source_strings.txt
grep -E "^msgid " i18n/de.po \
  | sed -E 's/msgid "(.*)"/\1/' | sort -u > /tmp/po_strings.txt
diff /tmp/source_strings.txt /tmp/po_strings.txt | head -50
```

Output zeigt fehlende Übersetzungen (`<` = im Code, nicht in `.po`) und tote Einträge (`>` = in `.po`, nicht mehr im Code).

---

## Aktuelle Verdachts-Liste (Stand 2026-05-30)

Aus den Aggregate-Zahlen ableitbare offene Punkte:

### V1 — Test-Datei vs. TestProject-Registrierung
**169 Test-Dateien, aber nur 146 in `TestProject.dpr`.** Differenz: ~23 Dateien. Davon sind ~5 erwartete Helfer (z.B. `uTestFindingHelper`, `uTestSrcBuilder`). **Übrige ~18 sind verdächtig — entweder vergessene Registrierungen oder weitere Helfer.** Audit:

```bash
comm -23 \
  <(ls StaticCodeAnalyserForm/tests/uTest*.pas | xargs -n1 basename | sed 's/.pas//' | sort) \
  <(grep -oE "^\s+uTest\w+ in" StaticCodeAnalyserForm/tests/TestProject.dpr \
    | tr -d ' ' | sed 's/in$//' | sort)
```

Output = nicht-registrierte Tests. Pro Eintrag entscheiden: Helfer (OK) oder Lücke (in `.dpr` + `.dproj` ergänzen).

### V2 — Detector-Files vs. BuildAllDetectors
**153 Detector-Files, 130 `AddD(...)`.** Differenz 23. Davon erwartet:
- ~20 Sub-Detektoren in `TDfmAnalysisRunner` (alle `uDfmXxx.pas` außer ggf. einigen die separat laufen)
- 1 `TCustomRuleDetector` (out-of-band)
- 1 `TCustomClassDiscovery` (out-of-band Pre-Pass)
- 1 `TFloatEquality` ? (war zuletzt FP-Reduction — verify)

→ Audit-Script:

```bash
# Detektor-Klassen die NICHT in BuildAllDetectors aufgerufen werden
for f in StaticCodeAnalyserForm/sources/Detectors/u*.pas; do
  cls=$(grep -oE "T\w+Detector\s*=\s*class" "$f" | head -1 \
        | sed -E 's/\s*=\s*class//')
  if [ -n "$cls" ] && ! grep -q "$cls\.AnalyzeUnit" \
       StaticCodeAnalyserForm/sources/Infrastructure/uStaticAnalyzer2.pas; then
    echo "OUT-OF-BAND: $cls ($(basename $f))"
  fi
done
```

Pro Eintrag entscheiden: Aggregator-Sub (OK) oder Lücke (`AddD` ergänzen).

### V3 — Detektor ohne dedizierte Test-Datei
**ACHTUNG — Naives File-Name-Matching reicht NICHT.** Viele aeltere Detektoren
haben Bundle-Tests unter abweichenden Dateinamen (`uTestCodeMetrics`,
`uTestSafetyChecks`, `uTestDuplicate`, `uTestLeakDetector` etc.). Korrekte
Coverage-Erkennung geht ueber Assertion auf `fkXxx`-Konstanten:

```bash
# Korrekt: pro Detector den fk-Konstanten suchen, NICHT den File-Namen
for pair in "CyclomaticComplexity|fkCyclomaticComplexity" \
            "DeepNesting|fkDeepNesting" \
            "FieldLeak|fkMemoryLeak"; do
  det=$(echo "$pair" | cut -d'|' -f1)
  fk=$(echo "$pair" | cut -d'|' -f2)
  hits=$(grep -lE "Count\(.*${fk}\)|${fk}[,\)\s]" StaticCodeAnalyserForm/tests/uTest*.pas \
         | grep -v uTestFindingHelper | grep -v uTestPerformance \
         | xargs -n1 basename | tr '\n' ' ')
  if [ -z "$hits" ]; then
    echo "TRULY UNCOVERED: $det ($fk)"
  fi
done
```

**Snapshot 2026-05-30:** Re-Check der urspruenglich 9 vermuteten Detektoren
(`CodeSmells2`, `CyclomaticComplexity`, `DeadCode`, `DeepNesting`, `DivByZero`,
`DuplicateBlock`, `DuplicateString`, `FieldLeak`, `LeakDetector2`) zeigt:
**alle 9 sind tatsaechlich abgedeckt** durch Tests mit nicht-1:1-Namen. V3 ist
damit aktuell leer; bei kuenftigen Re-Audits diese Skript-Variante (fk-Konstanten
statt File-Namen) verwenden.

| Detector | Abgedeckt durch |
|----------|------------------|
| CodeSmells2 (`fkEmptyExcept`) | `uTestEmptyExcept.pas` |
| CyclomaticComplexity | `uTestCodeMetrics.pas` |
| DeadCode | `uTestSafetyChecks.pas` |
| DeepNesting | `uTestCodeMetrics.pas` |
| DivByZero | `uTestSafetyChecks.pas` |
| DuplicateBlock | `uTestDuplicate.pas` |
| DuplicateString | `uTestDuplicate.pas` |
| FieldLeak (`fkMemoryLeak`) | `uTestLeakDetector.pas` (+ ExportSARIF, ExportSonarGeneric, QuickFix, ConfidenceFilter, ParserRobustness, ComboChecks) |
| LeakDetector2 (`fkMemoryLeak`) | dito |

### V4 — i18n-Vollständigkeit (Snapshot 2026-05-30)

Aktuell keine automatische i18n-Coverage-Prüfung im Test-Suite. Manueller
Lauf (siehe Schritt-4-Skript oben, mit Glob `sources/` **und** `StaticCodeAnalyserIDE/`):

| Quelle | Count |
|--------|------:|
| Source `_(…)`-Strings (eindeutig, sources/ + IDE) | **456** |
| msgids in `de.po` | **319** |
| msgids in `en.po` | **1** ⚠️ |

**Drei Befunde:**

1. **~137 Source-Strings haben keine `de.po`-Übersetzung.** Im DE-UI fallen
   sie auf den Source-String (englisch) zurück. Beispiele aus dem Diff:
   `'AI prompt copied to clipboard: %s, line %s (%s)'`,
   `'Analyse current file (silent)'`,
   `'Anti-pattern'`, `'Before:'`, `'After:'`, `'Bug'`,
   und viele Toolbar-/Action-Texte aus dem IDE-Plugin.
2. **~50 `de.po`-Karteileichen** — msgids ohne Source-Match. Beispiele:
   `'Dead Code'`, `'Debug Output'`, `'Deep Nesting'`, `'Div by Zero'`,
   `'Duplicate Code Blocks'` — vermutlich nach Refactor auf
   `KIND_META.Name`-Lookup obsolet geworden, blocken den DE-Übersetzungs-
   Workflow aber nicht.
3. **`en.po` ist effektiv leer** (nur Standard-Header). Wenn die Konvention
   „Source-Strings sind selbst Englisch, msgid==msgstr" gilt, ist das ok;
   dann sollte das aber explizit in einer README oder im File-Header
   dokumentiert sein. Sonst bricht ein zukünftiger `xgettext`-Regen-Lauf
   die Erwartungen.

**Audit-Skript** (reproduzierbar):

```bash
grep -rohE "_\('[^']*'\)" StaticCodeAnalyserForm/sources/ StaticCodeAnalyserIDE/ \
  | sed -E "s/^_\('(.*)'\)$/\1/" | sort -u > /tmp/src_strings.txt
grep -E '^msgid "' i18n/de.po \
  | sed -E 's/^msgid "(.*)"$/\1/' | grep -v '^$' | sort -u > /tmp/de_strings.txt
comm -23 /tmp/src_strings.txt /tmp/de_strings.txt  # fehlend in de.po
comm -13 /tmp/src_strings.txt /tmp/de_strings.txt  # tot in de.po
```

**Empfehlung:** Skript als CI-Step ergänzen, der bei jedem PR scheitert wenn
neue Source-Strings keine `de.po`-Einträge bekommen. Dann werden die 137
Backlog-Strings sukzessive aufgeräumt, statt zu wachsen.

---

## Action-Items

1. **Sofort** — Konsistenz-Tests laufen lassen (5 Min). Wenn rot, Lücke gemäß Test-Message schließen. Wenn grün, ist Block A abgehakt.
2. **Mittelfristig** — V1 + V2-Skripte laufen lassen, Befunde pro Eintrag triagieren (Helfer-OK oder Registrierung nachziehen).
3. **Längerfristig** — V3-Re-Audit mit dem **korrekten Skript** (fk-Konstanten statt File-Namen). Stand 2026-05-30: V3 leer.
4. **CI-Erweiterung** — V4 als CI-Check automatisieren: jeder PR der `_('...')`-Strings hinzufügt, scheitert wenn `de.po`/`en.po` nicht synchron.

## Cross-References

- [HowTo_AddDetector.md](HowTo_AddDetector.md) — die 23-Punkte-Checkliste, gegen die geauditet wird
- [Todo_FalsePositiveReduction.md](Todo_FalsePositiveReduction.md) — separater FP-Track (orthogonal zum Vollständigkeits-Audit)
- [Konzept_GridPerformance150k.md](Konzept_GridPerformance150k.md) — UI-Perf-Konzept (orthogonal)

## TL;DR

> **Block A (Konsistenz: KIND_META/Rules/Suppression/MQR) ist automatisch geprüft** — TestProject grün = Punkte 2/3/5/8/9 abgedeckt. **Block B (Projektdateien)** ist über Aggregate-Counts (153/153/153/153) bereits **vollständig**. **Block C (Per-Detektor: Tests, i18n, Code-Qualität)** braucht Skripte aus den V1–V4-Verdachts-Listen + manuelle Triage. Insgesamt 5–10% des HowTo-Inhalts braucht echtes manuelles Auditieren; der Rest ist test-gedeckt.

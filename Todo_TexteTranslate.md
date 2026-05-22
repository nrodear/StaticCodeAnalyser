# TODO: Detektor-Texte erstellen und übersetzen

Generische Checkliste pro Detektor — alle Textstellen, die für einen Detektor
geschrieben oder übersetzt werden müssen. Komplementär zu
[`Todo_neuerdetector.md`](Todo_neuerdetector.md) (12-Phasen-Rollout).

**Quelle der Wahrheit:** englische Strings im Source.
**Übersetzungsziele:** Deutsch — in zwei parallelen Stores
([uLocalization.pas](StaticCodeAnalyserForm/sources/UI/uLocalization.pas) GDeMap
für Runtime-Fallback, [i18n/de.po](i18n/de.po) für dxgettext-Pfad).

---

## 1) Englische Texte schreiben (Source of Truth)

### 1.1 KIND_META — Kurzname für Logs / Export
`StaticCodeAnalyserForm/sources/Common/uSCAConsts.pas`

- [ ] **Name** (PascalCase, ohne `fk`-Präfix) — taucht in Sonar-Export,
  Tooltip, Log auf.
  ```pascal
  (Name: 'UnpairedLock'; FindingType: ftBug; DefaultSeverity: lsWarning),
  ```

### 1.2 Detail-String — pro Finding ausgegeben
Im Detector selbst, an `F.MissingVar` zugewiesen.

- [ ] **Detail / MissingVar** — eine knappe englische Zeile, die das KONKRETE
  Vorkommen beschreibt (mit dynamischen Werten wie Variablen-Name).
  ```pascal
  Detail := Format('Lock/Enter without surrounding try/finally - %s', [Match]);
  F.MissingVar := Detail;
  ```

### 1.3 FixHint — Hover/Help-Panel
`StaticCodeAnalyserForm/sources/Output/uFixHint.pas`

- [ ] **Description** — EINE Zeile, mit `_()` lokalisiert. Beschreibt die
  Klasse des Bugs (nicht das einzelne Vorkommen).
  ```pascal
  Result.Description := _('Lock acquired without try/finally - an exception leaks the lock');
  ```
- [ ] **Before** — Code-Beispiel "Vorher". Bleibt englisch (Code-Reviews +
  Jira sind meist englisch; Mix von DE-Erklärung + EN-Code wäre schlechter).
- [ ] **After** — Code-Beispiel "Nachher", englisch.

### 1.4 Filter-Combo-Labels
`StaticCodeAnalyserIDE/uIDEAnalyserForm.pas` UND
`StaticCodeAnalyserForm/sources/UI/uMainForm.pas` (beide!)

- [ ] **Combo-Label** — kurz (max ~30 Zeichen), Title Case, keine
  Abkürzungen (`w/o` → `without`).
  ```pascal
  FFilterCombo.Items.AddObject(_('Unpaired Lock'),
    TObject(Ord(fmUnpairedLock)));
  ```

### 1.5 KindSearchKeywords — Suchfeld
`StaticCodeAnalyserForm/sources/UI/uFindingFilter.pas`

- [ ] **Bilingual Keyword-Liste** — EN und DE Tokens, lowercase, durch
  Leerzeichen getrennt. Damit findet der User per Stichwort, unabhängig
  von der UI-Sprache.
  ```pascal
  fkUnpairedLock : Result := 'unpaired lock unlock enter leave try finally mormot';
  ```

### 1.6 Rule-Catalog (`rules/sca-rules.json`)
- [ ] **`name`** — Title-Case kurze Beschreibung, ~50 Zeichen.
- [ ] **`shortDescription`** — 1-2 Sätze, was das Pattern ist.
- [ ] **`fullDescription`** — voller Absatz: was, warum, wie erkannt,
  Limitierungen. Englisch.
- [ ] **`examples.bad`** + **`examples.good`** — Code-Snippets.
- [ ] **`cleanCodeAttribute`** — einer von:
  `FORMATTED, CONVENTIONAL, IDENTIFIABLE, CLEAR, LOGICAL, COMPLETE,
  EFFICIENT, FOCUSED, DISTINCT, MODULAR`.
- [ ] **`impacts`** — `softwareQuality` + `severity` pro Quality-Dimension.

### 1.7 Doku-Tabellen
- [ ] [`DETECTORS.md`](DETECTORS.md) — Zeile in der passenden Cluster-Tabelle
  (Sonar-50 / SonarDelphi-Migration / mORMot-Cluster / Bonus).
- [ ] Top-of-doc Counter aktualisieren (`Grand total: ~N detectors`).

---

## 2) Deutsche Übersetzungen anlegen

### 2.1 GDeMap (Runtime-Fallback)
`StaticCodeAnalyserForm/sources/UI/uLocalization.pas`

- [ ] Pro **Combo-Label** eine `GDeMap.Add(en, de)`-Zeile.
- [ ] Pro **FixHint-Description** eine `GDeMap.Add(en, de)`-Zeile.
- Umlaute über `#$nn`-Notation:
  `'Pufferl'#$E4'nge'` (`ä`=$E4, `ö`=$F6, `ü`=$FC, `ß`=$DF, `²`=$B2).

### 2.2 dxgettext-Pfad (`i18n/de.po`)
- [ ] Pro **Combo-Label** ein `msgid`/`msgstr`-Paar.
- [ ] Pro **FixHint-Description** ein `msgid`/`msgstr`-Paar.
- Direkte Umlaute (UTF-8), eingebettete Quotes mit `\"` escapen:
  ```
  msgid "Class field without \"F\" prefix"
  msgstr "Klassen-Feld ohne \"F\"-Präfix"
  ```

### 2.3 Deutsche Doku
- [ ] [`DETECTORS_de.md`](DETECTORS_de.md) — Zeile in der passenden
  Cluster-Tabelle (parallel zu `DETECTORS.md`).
- [ ] Top-of-doc Counter aktualisieren.

---

## 3) Was NICHT übersetzt wird (mit Absicht)

- `KIND_META.Name` — taucht in Sonar-Export auf, muss stabil sein.
- `Detail` / `F.MissingVar` — Englisch, weil Findings im Export / Jira
  landen, wo Sprache-Mix unschön ist.
- `FixHint.Before` / `.After` — Code-Beispiele bleiben englisch
  (siehe Kommentar oben in [uFixHint.pas](StaticCodeAnalyserForm/sources/Output/uFixHint.pas)).
- `sca-rules.json` Inhalte — Sonar lädt sie sprach-unabhängig hoch.

---

## 4) Audit-Kommandos (vor Commit prüfen)

### Zählung
```bash
grep -cE "^\s*\(Name: '" StaticCodeAnalyserForm/sources/Common/uSCAConsts.pas
grep -cE "^\s*fk[A-Z]\w+:\s*$" StaticCodeAnalyserForm/sources/Output/uFixHint.pas
grep -cE "^\s*Result\.Description\s*:=" StaticCodeAnalyserForm/sources/Output/uFixHint.pas
grep -c "GDeMap.Add" StaticCodeAnalyserForm/sources/UI/uLocalization.pas
grep -c "^msgid " i18n/de.po
```

### Vollständigkeits-Check: Alle Hints in beiden DE-Stores?
```bash
grep -oE "Result\.Description\s*:=\s*_\('[^']*'\)" \
  StaticCodeAnalyserForm/sources/Output/uFixHint.pas \
  | sed -E "s/^Result\.Description\s*:=\s*_\('//; s/'\)$//" \
  | sort -u > /tmp/sca_hints.txt
while IFS= read -r line; do
  grep -qF "GDeMap.Add('$line'"  StaticCodeAnalyserForm/sources/UI/uLocalization.pas \
    || echo "MISSING in GDeMap: $line"
  grep -qF "msgid \"$line\""     i18n/de.po \
    || echo "MISSING in de.po:  $line"
done < /tmp/sca_hints.txt
```

### Vollständigkeits-Check: Alle Combo-Labels in beiden DE-Stores?
```bash
grep -oE "_\('[^']{1,40}'\)" StaticCodeAnalyserIDE/uIDEAnalyserForm.pas \
  | sed -E "s/^_\('//; s/'\)$//" | sort -u > /tmp/sca_combos.txt
# gleiche Schleife wie oben
```

### Rule-Catalog Konsistenz
```bash
# JSON-Syntax-Check (BOM-toleranter Mini-Parser)
node -e "var s=require('fs').readFileSync('rules/sca-rules.json','utf8'); \
         if(s.charCodeAt(0)===0xFEFF)s=s.slice(1); \
         var d=JSON.parse(s); console.log('rules:',d.rules.length);"
```
Den fachlichen Konsistenz-Check (jeder `fkKind` hat genau einen
Catalog-Eintrag mit gültigem `cleanCodeAttribute`) übernimmt der
DUnitX-Test `TTestRuleCatalog.EveryFindingKindHasMqrMapping`.
Gültige Attribute: `FORMATTED, CONVENTIONAL, IDENTIFIABLE, CLEAR,
LOGICAL, COMPLETE, EFFICIENT, FOCUSED, DISTINCT, MODULAR`.

---

## 5) Style-Guide für Texte

### Englisch
- **Combo-Labels:** Title Case, max ~30 Zeichen, keine Abkürzungen
  (nicht `w/o`, `trunc` — voll: `without`, `truncation`).
- **FixHint-Description:** Einleitender Imperativ oder Aussage, kein
  Komma-Splice. Bindestrich `-` (Plain ASCII) als Trenner zwischen
  Pattern und Folge: `Lock acquired without try/finally - an exception leaks the lock`.
- **Code-Beispiele:** echtes Pascal, mit `// <- comment` für die
  Bug-Stelle. Nicht zu lang (max ~25 Zeilen).

### Deutsch
- **Anglizismen erlaubt** wo sie im Delphi-Community-Sprachgebrauch
  etabliert sind: `Buffer`, `Lock`, `Cast`, `Pointer`, `Heap-Overread`,
  `try/finally`. Aber: `kommentarlos verschluckt` statt
  `silent swallow`.
- **Direkte Umlaute** in `.po` (UTF-8), `#$nn`-Escapes in Pascal-Strings.
- **Backticks** für Code-Identifier in Beschreibungen erlaubt:
  `` `with`-Anweisung ``, `` `Assigned()` ``.

---

## 6) Standard-Workflow (Reihenfolge)

1. **Englische Texte** in Source schreiben (1.1 - 1.6).
2. **Doku-Zeilen** (1.7) + Counter inkrementieren.
3. **GDeMap-Einträge** (2.1) für Combo-Labels und FixHint-Descriptions.
4. **de.po-Einträge** (2.2) für dieselben Strings.
5. **DETECTORS_de.md** (2.3) — Mirror der DETECTORS.md-Tabelle.
6. **Audit-Kommandos** aus (4) laufen lassen — alles 0 Missing?
7. **Build** (Form + IDE) — keine compile-Fehler, keine W1033.
8. **Commit** — Style: `feat: SCAxxx Foo + N translations`.

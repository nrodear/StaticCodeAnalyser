# Golden Corpus - FP-Regression-Tests

Phase-1-Quick-Win C.1 aus [Konzept_ScannerQualitaet.md](../../Konzept_ScannerQualitaet.md).

## Zweck

Jeder Round-1-13 Detector-Fix der eine False-Positive-Klasse beseitigt
hinterlegt hier einen kleinen Pascal-Snippet, der den FP-Trigger zeigt.
Der Snippet wird vom Scanner gepruefft - **das Tool darf die geflickten
Rules NICHT mehr feuern**. Wenn doch -> FP-Regression, Scanner hat sich
zurueckverschlechtert.

## Layout

```
tests/golden-corpus/
├── README.md                          ← du bist hier
└── fp-reproducers/                    ← Pascal-Snippets pro Fix
    ├── fp01_HardcodedSecret_metafield.pas
    ├── fp02_RedundantJump_inner_end.pas
    ├── fp03_PublicField_multiline_method.pas
    ├── fp04_FreeWithoutNil_local.pas
    ├── fp05_CommentedOutCode_docblock.pas
    └── expected.json                  ← pro File: must_not_flag-Liste
```

## Verwendung

```powershell
# Im Repo-Root
powershell -ExecutionPolicy Bypass -File tools\check-golden-corpus.ps1
```

Exit-Code:
- `0` - alle Regression-Tests gruen
- `1` - mindestens ein Verstoss (FP-Regression)
- `2` - Skript-Fehler (EXE/Korpus nicht gefunden)

## Neuen Reproducer hinzufuegen

Wenn du einen neuen FP fixst:

1. Erzeuge `fpNN_<Rule>_<Pattern>.pas` mit dem FP-trigger-Code
2. Add Header-Kommentar: welcher Round-Commit, welche Rule wurde gefixt,
   was war der Trigger
3. Fuege Eintrag in `expected.json` ein:
   ```json
   "fpNN_<Rule>_<Pattern>.pas": {
     "must_not_flag": ["SCAxxx"],
     "expected_findings": []
   }
   ```
4. Run `tools\check-golden-corpus.ps1` lokal - muss gruen sein
5. Commit Snippet + JSON-Eintrag

## CI-Integration

Sollte als Build-Step nach jedem IDE-Build laufen:

```yaml
# .github/workflows/check-corpus.yml (Beispiel - noch nicht eingerichtet)
- name: Golden Corpus Regression
  run: powershell -ExecutionPolicy Bypass -File tools\check-golden-corpus.ps1
  shell: pwsh
```

## Positive vs Negativ-Tests

Heute alle Reproducer = NEGATIV-Tests (`must_not_flag` + leere
`expected_findings`-Liste). Wenn spaeter POSITIVE Tests dazukommen
(z.B. neuer Detektor SCAxxx muss diesen Bug finden):

```json
"positive_test_xxx.pas": {
  "must_not_flag": [],
  "expected_findings": [
    {"ruleId": "SCAxxx", "line": 42}
  ]
}
```

Das Runner-Skript prueft beide Listen. Derzeit nur `must_not_flag`
implementiert - `expected_findings` ist Reserve.

## Verwandte Dokumente

- [Konzept_ScannerQualitaet.md](../../Konzept_ScannerQualitaet.md) §C.1
- [Todo_FalsePositiveReduction.md](../../Todo_FalsePositiveReduction.md) §D - Historie aller bisher gefixten FP-Klassen
- [HowTo_DetectorSelftest.md](../../HowTo_DetectorSelftest.md) - der breitere Dogfooding-Workflow

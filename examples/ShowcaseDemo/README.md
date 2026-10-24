# ShowcaseDemo - SCA findings and reDelphix code actions

A small VCL order manager (Delphi 12/13, Win32/Win64) that is written to be
**scanned, not shipped**: five units with about 160-220 findings of the
Static Code Analyser (SCA), and for **every** reDelphix code action (92
quick fixes of the fix table, their 8 second entries and the 6 provider
actions) at least one finding where the action is offered. It is the
material for the demo video; the German script is [DREHBUCH.md](DREHBUCH.md).

The code compiles (warnings and hints are expected and part of the show),
but the bugs are real: the application is not meant to run against a
database.

## Files

| File | Content |
|---|---|
| `ShowcaseDemo.dpr` / `.dproj` | VCL application (Win32 + Win64) |
| `uOrderModel.pas` | customers, orders, items, export attributes |
| `uPriceCalculator.pas` | prices, discounts, taxes, vouchers, summary |
| `uOrderRepository.pas` | FireDAC data access, cache, export thread |
| `uLegacyImport.pas` | "old" CSV import (2006 style, UTF-8 with BOM: tabs, keyword case, Trojan Source characters) |
| `uOrderForm.pas` / `.dfm` | main window (the DFM rules) |

## Open and scan

1. Open `ShowcaseDemo.dproj` in Delphi 12 or 13 (the IDE recreates the
   missing `ShowcaseDemo.res`). Build once if you like.
2. Analyser settings (`%APPDATA%\StaticCodeAnalyser\analyser.ini`, `[Rules]`):
   `Profile=strict` (IDE plugin: `IdeProfile=strict`), `MinSeverity=hint`
   and **`MinConfidence=low`**. `strict` adds the convention rules that the
   `default` profile leaves out (SCA007, SCA099, SCA101, SCA117, SCA126);
   `low` is needed for the formatting rules SCA061/063/064/069/076/079,
   which the engine reports with low confidence.
3. Scan the project or the folder. CLI equivalent (the CLI reads
   `MinConfidence` from the same ini):

   ```powershell
   StaticCodeAnalyser.d12.exe --path examples\ShowcaseDemo --full --profile strict --min-severity hint --report-html demo.html
   ```

Findings measured with the Charge A build (commit 49ab918f), counted per
profile and confidence floor:

| Profile / MinConfidence | medium | low |
|---|---:|---:|
| `default` | 137 | 192 |
| `strict` (for the video) | 163 | 218 |

## Reset

Every code action edits the sources. To start over:

```powershell
git checkout examples/ShowcaseDemo
```

## Notes

- The repository self-scan (`--path <repo>`, profile `strict`) sees the
  demo on purpose; refresh the local self-scan baseline after merging.
- Build output goes to `..\..\Output\ShowcaseDemo\`, so nothing lands in
  `examples\` (the release script zips that folder).
- Do not rename the folder or the files to `*Demo.pas`, `*Sample.pas`,
  `demos\`, `samples\` or `tests\`: the engine's fixture filter hides such
  files in the `default` profile.

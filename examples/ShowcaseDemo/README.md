# ShowcaseDemo - SCA findings and reDelphix code actions

A small VCL order manager (Delphi 12/13, Win32/Win64) that is written to be
**scanned, not shipped**: seven units with about 190-290 findings of the
Static Code Analyser (SCA). Every rule that Delphi code in a project can
show has at least one finding (all but SCA175, see the German script,
appendix B); DFM, project, configuration and encoding rules are shown only
where the form or the files already give a finding. For each of the 94
reDelphix quick fixes of the fix table, their 8 second entries and the 6
provider actions there is at least one finding where the action is offered,
and each of the 10 code actions without a finding has a spot. It is the
material for the demo video; the German script is [DREHBUCH.md](DREHBUCH.md).

The code compiles (warnings and hints are expected and part of the show),
but the bugs are real: the application is not meant to run against a
database.

## Files

| File | Content |
|---|---|
| `ShowcaseDemo.dpr` / `.dproj` | VCL application (Win32 + Win64) |
| `uOrderModel.pas` | customers, orders, items, export attributes, exporters, statistics |
| `uPriceCalculator.pas` | prices, discounts, taxes, vouchers, invoice and delivery note |
| `uOrderRepository.pas` | FireDAC data access, cache, export thread, night job, order service sync |
| `uLegacyImport.pas` | "old" CSV import (2006 style, UTF-8 with BOM: tabs, keyword case, Trojan Source characters, inline assembler, DOS records) |
| `uOrderForm.pas` / `.dfm` | main window (the DFM rules) |
| `uOrderStatus.pas` | order status texts - a unit without a header comment (SCA143) |
| `uOrderEvents.pas` | a placeholder unit that was never filled (SCA092) |

## Open and scan

1. Open `ShowcaseDemo.dproj` in Delphi 12 or 13 (the IDE recreates the
   missing `ShowcaseDemo.res`). Build once if you like.
2. Analyser settings (`%APPDATA%\StaticCodeAnalyser\analyser.ini`):
   in `[Rules]` `Profile=strict` (IDE plugin: `IdeProfile=strict`),
   `MinSeverity=hint` (IDE plugin: `IdeMinSeverity=hint`) and
   **`MinConfidence=low`**; in `[Detectors]` **`UsesCheck=1`**. `strict`
   adds the convention rules that the `default` profile leaves out
   (SCA099, SCA101, SCA117, SCA126); `low` is needed for the formatting
   rules SCA061/063/064/069/076/079, which the engine reports with low
   confidence. The unused-uses check SCA007 is opt-in: the IDE plugin
   reports it only with `UsesCheck=1`, in every profile including
   `strict` (without it the IDE shows the 9 SCA007 findings less, 276
   instead of 285, and the SCA007 code actions have nothing to offer).
   The CLI switches it on by itself with `--profile strict`.
3. Scan the project or the folder. CLI equivalent (the CLI reads
   `MinConfidence` from the same ini):

   ```powershell
   StaticCodeAnalyser.d12.exe --path examples\ShowcaseDemo --full --profile strict --min-severity hint --report-html demo.html
   ```

Findings counted per profile and confidence floor (CLI run as above; the
IDE plugin shows the same with `UsesCheck=1`):

| Profile / MinConfidence | medium | low |
|---|---:|---:|
| `default` | 193 | 255 |
| `default` with `UsesCheck=1` | 202 | 264 |
| `strict` (for the video) | 223 | 285 |

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

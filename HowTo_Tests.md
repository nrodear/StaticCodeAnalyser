# HowTo: Build and run the tests

*🇬🇧 English — 🇩🇪 [Deutsch](HowTo_Tests_de.md) — 🇫🇷 [Français](HowTo_Tests_fr.md)*

The DUnitX test suite (`StaticCodeAnalyserForm\tests\TestProject.dproj`) uses
**two external components**: DUnitX always, TestInsight only in the build
configuration `TestInsight`. A missing one ends "Build all projects" with
`F2613 Unit '...' not found`.

| Component | Required | Purpose |
|---|---|---|
| **DUnitX** | required | Test framework (Assert / `[Test]` attributes / runner) |
| **TestInsight** | optional, only for the `TestInsight` configuration (see below) | IDE integration (test panel, live status) |

The actual SCA engine + standalone EXE run independently — the tests are only
relevant for developers. If you only want to build the SCA, you can exclude the
two test projects from the IDE build (see workarounds below).

---

## Installation

### DUnitX (required — both platforms)

```bash
cd D:\projects
git clone https://github.com/VSoftTechnologies/DUnitX.git dunitx
```

Clone it next to the repository: in `TestProject.dproj` the path
`..\..\..\dunitx\Source` is already in `DCC_UnitSearchPath`. Different parent
directory? Adjust the path in the dproj or set it globally via Tools → Options →
Language → Delphi → Library (separately for **Win32 and Win64**).

### TestInsight (optional — Win32 and Win64)

The three test projects (`TestProject`, `reDelphix.Test`,
`VarNameProject.Test`) define `TESTINSIGHT` only in their build
configuration **TestInsight** (see _The TESTINSIGHT define_ below). Debug
and Release compile without the TestInsight units; you need them only for
the test panel in the IDE.

Preferably via the **GetIt Package Manager**:

1. RAD Studio IDE → Tools → GetIt Package Manager
2. Search "TestInsight" → click **Install**
3. Restart the IDE

GetIt sets the library path and installs the plugin automatically.

If the GetIt entry is missing: search GitHub/Bitbucket for
`TestInsight Stefan Glienke`, clone manually, compile + install the
`TestInsight.RADxx.dpk`, then add `Source/` to the Win32 and the Win64
library path.

---

## Build targets

| Build target | Platform | Prerequisite |
|---|---|---|
| SCA.Engine290.bpl | Win32 + Win64 | rtl, nothing external |
| SCA.SharedUI290.bpl | Win32 + Win64 | rtl, vcl, vclwinx, SCA.Engine |
| StaticCodeAnalyser.d12.exe (standalone) | Win32 + Win64 | nothing external |
| StaticCodeAnalyser.IDE.d12.bpl | Win32; Win64 **under Delphi 13 only** | rtl, vcl, vclwinx, designide, SCA.Engine, SCA.SharedUI |
| reDelphix.d12.bpl | Win32; Win64 **under Delphi 13 only** | rtl, vcl, designide, SCA.Engine |
| **TestProject.exe** | Win32 + Win64 | **DUnitX**; TestInsight only for the `TestInsight` configuration |

"Build all projects" builds every project of the group on its own active
platform; each project remembers its own. Check them before (see
[HowTo_Build.md](HowTo_Build.md), section 5.1). Under Delphi 12 the two
design packages stop with `{$MESSAGE FATAL}` on Win64.

---

## Running the tests

### IDE (Win32 with TestInsight)

Activate the build configuration **TestInsight** in the Projects window
(Build Configurations → right-click → **Activate**), then build and run.
The test panel shows live results; clicking a failing test jumps to the
assertion.

> **Exit code 0 of a TestInsight build is NOT proof of a test run.** It
> gets the **GUI** subsystem and runs through `TestInsight.DUnitX`; without
> a TestInsight server in the IDE it ends at once with `Halt(0)`: no
> stdout, no NUnit XML, exit code 0. Results exist only in the test panel.

### IDE without TestInsight (Win32 or Win64)

The configurations **Debug** and **Release** do not define `TESTINSIGHT`:
the EXE is a console program with the console logger.

```powershell
".\Output\Tests\Win64 Release\TestProject.exe"
```

Then: exit code 0 = all green, 1 = at least one red test or an exception
in the runner; failures on stdout + NUnit XML next to the EXE (via
`DUnitX.Loggers.Xml.NUnit`).

### Running a subset

Works in every Debug or Release build. Only a build in the `TestInsight`
configuration never reaches `TDUnitX.CheckCommandLine` and ignores every
switch.

Tests are picked by name with `--run` (short `-r`). DUnitX names a fixture
after its unit and class (`unit.class`), a test after its method
(`unit.class.method`). A name selects every test whose fixture name starts
with it (case-insensitive), a full test name selects that one test.
Separate several names with commas; `--run` may also be repeated:

```powershell
TestProject.exe --run:uTestUninitVar.TTestUninitVar
TestProject.exe --run:uTestUninitVar.TTestUninitVar.NeverWritten_OnlyRead_Flagged
TestProject.exe --run:uTestUninitVar.TTestUninitVar,uTestPerformance.TTestPerformance
```

The bare class name (`--run:TTestUninitVar`) matches nothing, because the
fixture name starts with the unit.

`--include` and `--exclude` filter by `[Category]`, not by class name. In
this project only `TTestPerformance` carries a category (`perf`):

```powershell
TestProject.exe --exclude:perf
```

---

## Workarounds

### Exclude the test projects from the build entirely

If the tests are not currently relevant and you only want to build the SCA, in
IDE → right-click the project group → **Build order** → uncheck
`TestProject.dproj` and `reDelphix.Test.dproj`. "Build all projects" then skips
both. `reDelphix.Test.dproj` also needs DUnitX.

Equivalently, comment out both entries directly in the `.groupproj`.

### The TESTINSIGHT define

Each of the three test projects defines it only in the build configuration
`TestInsight`, a child of Debug (key `Cfg_3`, in `reDelphix.Test.dproj`
`Cfg_4`):

```xml
<PropertyGroup Condition="'$(Cfg_3)'!=''">
  <DCC_Define>TESTINSIGHT;$(DCC_Define)</DCC_Define>
</PropertyGroup>
```

Debug and Release (in `reDelphix.Test.dproj` also `CI`) build without it,
need no TestInsight units and accept the DUnitX switches. Earlier the
define sat in the Base group (in `reDelphix.Test.dproj` in Debug and
Release); every IDE build then ran through TestInsight and ignored `--run`.

### EFOpenError dialog during the test run

Several tests deliberately raise exceptions (`EFOpenError`, `Exception`, etc.) to
verify error handling. The IDE debugger catches them and shows a dialog.
Workaround:

- **In the dialog:** check "Ignore this exception type" + continue
- **Permanently:** Run → Run Without Debugging (`Ctrl+Shift+F9`) instead of F9 —
  the debugger then does not intervene at all
- **Selectively:** Tools → Options → Debugger Options → Language Exceptions → add
  the exception class to the ignore list

### Win64-specific E2532 on `Assert.AreEqual(N, X.Count)`

Generic inference fails under Win64 when an untyped int literal + Integer are
combined. Fix: explicit type parameter `Assert.AreEqual<Integer>(N, X.Count)`.
Already patched in 1209 places of the suite. Mind this for new tests.

---

## Related files in the repo

- `StaticCodeAnalyserForm\tests\TestProject.dproj` — test project config
- `StaticCodeAnalyserForm\tests\TestProject.dpr` — test runner code
- `StaticCodeAnalyserForm\tests\uTest*.pas` — the individual test units
- `reDelphix\tests\reDelphix.Test.dproj` — tests of the reDelphix code actions;
  besides Debug, Release and TestInsight it has `CI`, a console runner that
  never waits for a key press at the end

# HowTo: Build and run the tests

*🇬🇧 English — 🇩🇪 [Deutsch](HowTo_Tests_de.md) — 🇫🇷 [Français](HowTo_Tests_fr.md)*

The DUnitX test suite (`StaticCodeAnalyserForm\tests\TestProject.dproj`) needs
**two external components**. Without them "Build all projects" fails with
`F2613 Unit '...' not found`.

| Component | Required | Purpose |
|---|---|---|
| **DUnitX** | required | Test framework (Assert / `[Test]` attributes / runner) |
| **TestInsight** | required as the repository stands (see below) | IDE integration (test panel, live status) |

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

### TestInsight (required today — Win32 and Win64)

Both test projects define `TESTINSIGHT` (see _The TESTINSIGHT define_
below), so as the repository stands they do not compile without the
TestInsight units, on Win32 and Win64 alike.

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
| **TestProject.exe** | Win32 + Win64 | **DUnitX** + TestInsight (see below) |

"Build all projects" builds every project of the group on its own active
platform; each project remembers its own. Check them before (see
[HowTo_Build.md](HowTo_Build.md), section 5.1). Under Delphi 12 the two
design packages stop with `{$MESSAGE FATAL}` on Win64.

---

## Running the tests

### IDE (Win32 with TestInsight)

Standard setup. The test panel shows live results; clicking a failing test jumps
to the assertion.

### IDE without TestInsight (Win32 or Win64)

> **WARNING — built as the repository stands today, this does NOT work,
> and the console run still looks like a success.**
> `TestProject.dproj` sets `TESTINSIGHT` as a `DCC_Define` in the **Base**
> property group, so for EVERY configuration and platform. The
> `{$IFNDEF TESTINSIGHT}` in the `.dpr` therefore does not apply: the EXE
> gets the **GUI** subsystem instead of Console and runs through
> `TestInsight.DUnitX` instead of the console logger. Without a TestInsight
> server in the IDE it ends at once with `Halt(0)`: **no stdout, no NUnit
> XML, exit code 0.**
>
> Measured on 2026-09-20 on both freshly built EXEs (Win32 and Win64):
> PE subsystem 2 = GUI, 0 lines of output, exit 0.
>
> **So exit code 0 is NOT proof of a test run here** — it cannot be told
> apart from "all green". Results exist only in the TestInsight panel of
> the IDE. If you really want the console run, take `TESTINSIGHT` out of
> the Base group of the `.dproj` first.

The original way (valid only WITHOUT the define):

```powershell
".\Output\Tests\Win64 Release\TestProject.exe"
```

Then: exit code 0 = all green, failures on stdout + NUnit XML next to the
EXE (via `DUnitX.Loggers.Xml.NUnit`).

### Running a subset

Only without the `TESTINSIGHT` define (see above): with it, the EXE never
reaches `TDUnitX.CheckCommandLine` and ignores every switch.

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
both. `reDelphix.Test.dproj` also needs DUnitX and defines `TESTINSIGHT` in
Debug and Release.

Equivalently, comment out both entries directly in the `.groupproj`.

### The TESTINSIGHT define

In `TestProject.dproj` the define sits in the Base group, so it applies to every
platform and configuration:

```xml
<PropertyGroup Condition="'$(Base)'!=''">
  <DCC_Define>TESTINSIGHT;$(DCC_Define)</DCC_Define>
</PropertyGroup>
```

The Win64 build therefore needs the TestInsight units as well. If you do not want
TestInsight at all, delete the entry; the console logger then takes over.

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
- `reDelphix\tests\reDelphix.Test.dproj` — tests of the reDelphix code actions; its
  `CI` configuration is a console runner with a real exit code

# HowTo: Build and run the tests

*🇬🇧 English — 🇩🇪 [Deutsch](HowTo_Tests_de.md)*

The DUnitX test suite (`StaticCodeAnalyserForm\tests\TestProject.dproj`) needs
**two external components**. Without them "Build all projects" fails with
`F2613 Unit '...' not found`.

| Component | Required | Purpose |
|---|---|---|
| **DUnitX** | required | Test framework (Assert / `[Test]` attributes / runner) |
| **TestInsight** | Win32 optional | IDE integration (test panel, live status) |

The actual SCA engine + standalone EXE run independently — the tests are only
relevant for developers. If you only want to build the SCA, you can exclude the
TestProject from the IDE build (see workarounds below).

---

## Installation

### DUnitX (required — both platforms)

```bash
cd D:\git-demos\delphi
git clone https://github.com/VSoftTechnologies/DUnitX.git dunitx
```

In `TestProject.dproj` the path `..\..\..\dunitx\Source` is already in
`DCC_UnitSearchPath` (commit `3f1cab0`). Different parent directory? Adjust the
path in the dproj or set it globally via Tools → Options → Language → Delphi →
Library (separately for **Win32 and Win64**).

### TestInsight (optional — Win32 IDE integration)

Preferably via the **GetIt Package Manager**:

1. RAD Studio IDE → Tools → GetIt Package Manager
2. Search "TestInsight" → click **Install**
3. Restart the IDE

GetIt sets the library path and installs the plugin automatically.

If the GetIt entry is missing: search GitHub/Bitbucket for
`TestInsight Stefan Glienke`, clone manually, compile + install the
`TestInsight.RADxx.dpk`, then add `Source/` to the Win32 library path.

---

## Build targets

| Build target | Platform | Prerequisite |
|---|---|---|
| SCA.Engine.bpl | Win32 + Win64 | rtl, nothing external |
| SCA.SharedUI.bpl | **Win32 only** | rtl, vcl, designide (IDE-only) |
| StaticCodeAnalyser.exe (standalone) | Win32 + Win64 | nothing external |
| StaticCodeAnalyser.IDE.bpl | **Win32 only** | rtl, vcl, designide |
| **TestProject.exe** | Win32 + Win64 | **DUnitX** + (Win32: TestInsight) |

"Build all projects" builds all 5 targets on the currently selected platform.

---

## Running the tests

### IDE (Win32 with TestInsight)

Standard setup. The test panel shows live results; clicking a failing test jumps
to the assertion.

### IDE without TestInsight (Win32 or Win64)

Run `TestProject.exe` as a standalone console — the DUnitX console logger is used
(see `TestProject.dpr` lines 18-20):

```powershell
".\Output\Tests\Win64 Release\TestProject.exe"
```

Exit code 0 = all green. Failures appear as stdout + NUnit XML next to the EXE
(via `DUnitX.Loggers.Xml.NUnit`).

### Running a subset

The DUnitX command line takes filters:

```powershell
TestProject.exe --include:TTestUninitVar
TestProject.exe --exclude:TTestPerformance
```

---

## Workarounds

### Exclude TestProject from the build entirely

If the tests are not currently relevant and you only want to build the SCA, in
IDE → right-click the project group → **Build order** → uncheck
`TestProject.dproj`. "Build all projects" then skips that project.

Equivalently, comment out the TestProject entry directly in the `.groupproj`.

### Platform-gated TESTINSIGHT define

In `TestProject.dproj` the define is active only for Win32 (line 133):

```xml
<PropertyGroup Condition="'$(Base_Win32)'!=''">
  <DCC_Define>TESTINSIGHT;$(DCC_Define)</DCC_Define>
</PropertyGroup>
```

The Win64 build therefore skips the TestInsight imports automatically and does
not need the plugin. If you do not want TestInsight at all, delete the entry.

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
Already patched in 1209 places of the suite (commit `5f1661c`). Mind this for new
tests.

---

## Related files in the repo

- `StaticCodeAnalyserForm\tests\TestProject.dproj` — test project config
- `StaticCodeAnalyserForm\tests\TestProject.dpr` — test runner code
- `StaticCodeAnalyserForm\tests\uTest*.pas` — the individual test units
- `HowTo_AddDetector.md` — when a new detector + tests are to be created
- `HowTo_DetectorSelftest.md` — dogfooding workflow for the SCA EXE

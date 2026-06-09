# HowTo: Build and Install (Beginner Guide)

This guide walks you through the full path from "I have nothing"
to "the analyzer runs on my code". It is written for people who are
**new to Delphi**.

You will end up with:
- the **standalone Windows app** (`StaticCodeAnalyser.d12.exe`)
- the **IDE plugin** (loaded into Delphi 12 every time you open it)

---

## 0. What you need

- **Windows 10 or 11** (64-bit).
- **About 25 GB free disk** (RAD Studio is big).
- An **internet connection** (for the download and for git).
- An **Embarcadero account** (free).
- About **45 minutes** total. Most of that is the RAD Studio installer.

---

## 1. Install Delphi 12 (RAD Studio)

You need **Delphi 12 Athens** (also called RAD Studio 12). The
**free Community Edition** is enough.

1. Go to https://www.embarcadero.com/products/delphi/starter.
2. Click **"Download Free Trial"** or **"Community Edition"**.
3. Sign in with your Embarcadero account (create one if you do not have it).
4. Run the installer (`RADStudio_Athens_setup.exe`).
5. Pick:
   - **Personality:** Delphi (you do not need C++Builder).
   - **Platforms:** Windows 32-bit AND Windows 64-bit (you need both).
   - **Languages:** English is fine.
   - **Extras (optional):** GetIt-Package-Manager — leave the default.
6. Wait. The download is ~6 GB; the install adds another ~12 GB.
7. After install, start **RAD Studio**. Accept the EULA on first run.

You should now see the **Delphi IDE** with a "Welcome" tab. Close any
example projects it opens.

---

## 2. Download this project from GitHub

You need **git** for Windows: https://git-scm.com/download/win.

Open **Command Prompt** or **PowerShell** in the folder where you keep
your code, then run:

```cmd
cd D:\projects
git clone https://github.com/nrodear/StaticCodeAnalyser.git
cd StaticCodeAnalyser
```

You can pick any path. In this guide we assume `D:\projects\StaticCodeAnalyser`.

---

## 3. Open the project group in Delphi

The project ships as a **project group** that contains 4 sub-projects
(engine, shared UI, standalone app, IDE plugin).

1. In Delphi, click menu **File → Open Project**.
2. Browse to `D:\projects\StaticCodeAnalyser`.
3. At the bottom of the dialog, change **"Files of type"** to
   **"Delphi project group (`*.groupproj`)"**.
4. Pick `StaticCodeAnalyser.d12.groupproj` and click **Open**.

On the right side you now see the **Project Manager** window with these
sub-projects:

- `SCA.Engine` — the scanning engine.
- `SCA.SharedUI` — UI components used by both standalone and plugin.
- `StaticCodeAnalyser.d12` — the standalone EXE.
- `StaticCodeAnalyser.IDE.d12` — the IDE plugin (a BPL package).

Delphi shows a green **bold** font for the **active** sub-project.
You will switch the active project as needed below.

---

## 4. Build the standalone EXE

The standalone is a plain `.exe`. You run it from the command line or
double-click it.

### 4.1 Pick the platform (32-bit vs 64-bit)

64-bit is the default and what we recommend.

In the Project Manager:

1. Expand `StaticCodeAnalyser.d12` (click the small arrow).
2. Expand **Target Platforms**.
3. **Right-click** `Windows 64-bit (Win64)` → click **Activate**.
4. **Right-click** `Configuration` → **Release** → click **Activate**.

If you want the 32-bit EXE instead, pick `Windows 32-bit (Win32)`.

> **Tip:** if you change your mind later, just right-click another
> platform and click **Activate** again — you can build both versions
> any time.

### 4.2 Build

1. In the Project Manager, **right-click** `StaticCodeAnalyser.d12`
   (the project name itself, not Target Platforms).
2. Click **Build** (or **Compile** if Build is greyed out).
3. Wait ~30 seconds. Watch the **Messages** window at the bottom.

When it finishes with **"Success"**, your EXE is here:

```
D:\projects\StaticCodeAnalyser\Output\Win64 Release\StaticCodeAnalyser.d12.exe
```

(For Win32: `Output\Win32 Release\…`. For Debug builds: `…\Win64 Debug\…`.)

### 4.3 Apply the stack-size patch (one-time per build)

The compiler sets a 1 MB stack. Deep Pascal files can hit that limit
and crash. Open PowerShell in the project folder and run:

```powershell
tools\patch-stack-size.ps1 "Output\Win64 Release\StaticCodeAnalyser.d12.exe"
```

The script prints `Patched ... SizeOfStackReserve: 1 MB -> 32 MB`.
You must rerun this **after every fresh build**.

---

## 5. Build and install the IDE plugin

The plugin is a `.bpl` (Borland Package Library) that Delphi loads at
startup.

### 5.1 Build the plugin

The plugin runs **inside the Delphi IDE**, which is 32-bit. So the
plugin must be 32-bit.

1. In the Project Manager, expand `StaticCodeAnalyser.IDE.d12`.
2. Expand **Target Platforms**.
3. **Right-click** `Windows 32-bit (Win32)` → **Activate**.
4. Switch the active config to **Release** (right-click `Configuration`
   → **Release** → **Activate**).
5. **Right-click** `SCA.Engine` (in Project Manager) → **Build**.
   The plugin needs the engine package; build it first.
6. **Right-click** `SCA.SharedUI` → **Build**.
7. **Right-click** `StaticCodeAnalyser.IDE.d12` → **Build**.

You now have three `.bpl` files in
`C:\Users\Public\Documents\Embarcadero\Studio\23.0\Bpl\`:

- `SCA.Engine.bpl`
- `SCA.SharedUI.bpl`
- `StaticCodeAnalyser.IDE.d12.bpl`

### 5.2 Tell the IDE to load the plugin

1. Click menu **Tools → Options**.
2. On the left, click **IDE → Packages → Design Packages**.
3. Click **Add…**.
4. Browse to
   `C:\Users\Public\Documents\Embarcadero\Studio\23.0\Bpl\`,
   pick `StaticCodeAnalyser.IDE.d12.bpl`, click **Open**.
5. Make sure the checkbox next to it is **on**.
6. Click **OK**.
7. **Close and restart Delphi.**

After restart, the IDE shows a new dockable window:
**View → Static Code Analysis**.

If the menu entry is missing, the plugin failed to load. Check
**View → Window List…** or read the splash-screen errors carefully.

---

## 6. Run the standalone — first scan

The standalone is the easiest way to confirm things work.

### 6.1 Pick a folder of Pascal code

For a quick smoke test you can scan the project itself.

### 6.2 Launch

Double-click the EXE you built, **OR** from the command line:

```cmd
cd D:\projects\StaticCodeAnalyser
"Output\Win64 Release\StaticCodeAnalyser.d12.exe"
```

A window with **stats cards** (Errors / Warnings / Hints / …) and an
empty grid opens.

### 6.3 First scan

1. In the **Path** field at the top, type or paste your folder
   (e.g. `D:\projects\StaticCodeAnalyser\SCA.Engine\sources`).
2. Click the **Analyse** button.
3. Wait — for small projects: 1-5 seconds. For large ones: up to a
   minute.

The grid fills with findings. Each row shows: file, method, line,
severity, rule, message. Double-click a row to open the file at the
correct line (Notepad or your default Pascal viewer).

### 6.4 Filter and sort

- The **Filter** field on top accepts substrings of the file or rule.
- Click any column header to sort.
- Click a **stat card** (Errors / Warnings / Hints) to keep only that
  severity.

### 6.5 Save the report

Use the **Export** buttons (top-right) to save as **HTML**, **JSON**,
**SARIF** (for SonarQube), or copy to clipboard for Jira/Markdown.

---

## 7. Use the IDE plugin

If you completed section 5, the plugin is already loaded.

### 7.1 Open the analyser window

Menu **View → Static Code Analysis**.

A dockable window appears (drag the title bar to dock it next to
the Project Manager or as a tab at the bottom).

### 7.2 Scan the currently open file

1. Open any `.pas` file in the editor.
2. In the Static Code Analysis window, click the **File** button.
3. The current file is scanned. Findings show in the grid.

### 7.3 Scan the whole project

1. Open your project (`.dproj`) in Delphi.
2. In the Static Code Analysis window, click the **Analyse** button.
3. The whole project is scanned. May take seconds to a minute.

### 7.4 Jump to a finding

Click any row in the grid: the editor jumps to that file and line and
highlights the offending code with a colored marker in the gutter.

### 7.5 Hide false positives

Right-click any finding → **Suppress with `// noinspection`**. The
plugin writes a comment above the line that hides exactly this rule
at this place. The finding disappears on the next scan.

### 7.6 Hover hint

If you hover over a finding row, a tooltip shows a **Before / After**
code example: how the problem looks, and how the fix looks.

---

## 8. When things go wrong

| Symptom | Most likely cause |
|---|---|
| **"Build failed: unresolved external"** | You built the plugin before the engine. Build `SCA.Engine` first, then `SCA.SharedUI`, then the plugin. |
| **Plugin menu entry is missing after restart** | Wrong platform (you built Win64 instead of Win32) or wrong path in `Tools → Options → Packages`. |
| **Standalone crashes after a few seconds on a large project** | Stack-size patch not applied. Re-run `tools\patch-stack-size.ps1`. |
| **EXE complains "file not found" on launch** | You moved the EXE out of its `Output\…` folder. Either put it back, or copy the `.dcu`/`.bpl` files with it. |
| **"Cannot find SCA.Engine.bpl"** when the plugin loads | The plugin sees `SCA.Engine.bpl` via the Delphi-search path. Build `SCA.Engine` for the same platform (Win32) and configuration (Release). |

---

## 9. What next

- **Configure the analyzer:** open `analyser.ini` in
  `%APPDATA%\StaticCodeAnalyser\`. You can set `Profile=` (which rules
  run), `MinSeverity=`, `MinConfidence=`, etc. The file has comments.
- **Connect to SonarQube:** see [sonarHowto.md](sonarHowto.md).
- **Run from the command line / CI:** see the `--help` output of the
  standalone EXE. Useful flags: `--profile`, `--report-sarif`,
  `--quiet`, `--time-detectors`.
- **Try the German UI:** in the analyser window, switch language to
  **Deutsch** in the toolbar.

---

## 10. Where to ask

- **GitHub issues:** https://github.com/nrodear/StaticCodeAnalyser/issues
- **Embarcadero docs (for general Delphi questions):**
  https://docwiki.embarcadero.com/RADStudio/en/Main_Page

🇩🇪 [Deutsche Version](HowTo_Build_de.md)

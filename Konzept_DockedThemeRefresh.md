# Konzept: Theme-Refresh im Docked-Mode

Status: **Implementierung in dieser Branch (neuUI)**
Stand: 2026-05-26

## Problem

Beim IDE-Theme-Switch im **Docked-Modus** rendert nur das StringGrid mit neuen Farben.
Tiles, Toolbar-Panels, Help-Panel-Caption und Memos bleiben in der vorigen Theme-Farbe stehen.

## Diagnose

### Warum das Grid funktioniert

Zwei Bedingungen treffen zusammen:

1. **Live-Lookup der frischen Theme-Quelle pro Cell-Paint**
   `TFindingGridRenderer.DrawCell` liest in jedem Aufruf `Config.GetStyleServices()`.
   Der Provider in `uIDEAnalyserForm.GridDrawCell` holt direkt
   `BorlandIDEServices as IOTAIDEThemingServices → Theming.StyleServices` —
   die IDE-interne Theme-Quelle, garantiert auf dem aktuellen Stand.

2. **Synchroner Repaint statt deferred Invalidate**
   In `uIDETheme.ApplyRecursive` bekommen alle Controls `Invalidate`,
   aber `TCustomGrid`-Descendants zusätzlich `Repaint` (= `Invalidate + Update`).
   Das `Update` zwingt den `WM_PAINT` synchron, solange der Stack noch in
   `TIDETheme.Apply` steht und `Theming.StyleServices` definitiv frisch ist.

### Warum Tiles/Panels/Labels NICHT funktionieren

Drei kumulative Ursachen:

1. **Falsche StyleServices-Quelle in Custom-Paint**
   `TTilePanel.Paint` ruft `StyleServices.GetSystemColor(FBorderColor)` —
   das ist `Vcl.Themes.StyleServices` (global, an `TStyleManager.ActiveStyle`
   gebunden). Im Docked-Mode aktualisiert `Theming.ApplyTheme(IDE-Main-Form)`
   NICHT die VCL-globale StyleServices, weil das IDE-Theming-Service einen
   eigenen Pfad fährt.

2. **System-Color-Identifier auf TPanel/TLabel.Color werden zur Paint-Zeit
   resolved — über die stale VCL-globale StyleServices**
   `Tile.Color := IDE_BG_CHROME` setzt nur die Konstante `clBtnFace`.
   `inherited Paint` malt das Panel mit `Brush.Color := Color` → VCL resolved
   `clBtnFace` jetzt → liefert alten Wert. Selbe Mechanik für `TLabel.Color`
   und `TMemo.Color`.

3. **Asynchroner WM_PAINT-Verarbeitungszeitpunkt**
   `Invalidate` postet `WM_PAINT` in die Message-Queue. Verarbeitet wird er
   später, möglicherweise mehrere Pump-Cycles nach `TIDETheme.Apply`.
   Zwischen Apply und Paint können Style-States variieren.

### Was setTheme/a9997dd anders macht: NICHTS

`git diff setTheme..neuUI` für die Theme-Pipeline zeigt nur Kommentar-Diffs.
**Der Docked-Mode-Bug existiert auf beiden Branches identisch** — auf
`setTheme` wurde er nur nie getestet/bemerkt.

## Lösung

Drei kombinierte Maßnahmen, alle auf die Tile-Klasse von Problemen
gleichzeitig zielend:

### A. Synchroner Paint statt nur Invalidate

`uIDETheme.ApplyRecursive`:
```pascal
AC.Invalidate;
if AC is TWinControl then
  TWinControl(AC).Update;          // ← NEU: synchroner WM_PAINT
if AC is TCustomGrid then
  TCustomGrid(AC).Repaint;
```

Adressiert Ursache **3** — der Paint passiert sofort, solange
`Theming.StyleServices` frisch ist.

### B. Per-Descendant Color-Resolution zur Apply-Zeit

`uIDETheme.ApplyRecursive` nach `ATheming.ApplyTheme(AC)`:
```pascal
IdeStyle := ATheming.StyleServices;
if Assigned(IdeStyle) then
begin
  C := TControlAccess(AC).Color;
  ResolveIDEColor(C, IdeStyle);    // wenn clSystemColor-Bit gesetzt → konkreter RGB
  TControlAccess(AC).Color := C;

  C := TControlAccess(AC).Font.Color;
  ResolveIDEColor(C, IdeStyle);
  TControlAccess(AC).Font.Color := C;
end;
```

Adressiert Ursache **2** — Color/Font.Color tragen nach Apply konkrete
RGB-Werte aus dem IDE-Theme, nicht mehr System-Color-Identifier die später
re-resolved werden müssen. Beim nächsten Theme-Switch läuft die Iteration
wieder durch und resolved gegen das neue Theme.

`TControlAccess = class(TControl)` als Hack-Class für protected Color/Font.

### C. ActiveStyleServices in Custom-Paint-Pfaden

Drei Stellen:

- `uIDEStatsTiles.TTilePanel.Paint`:
  `Canvas.Pen.Color := ActiveStyleServices.GetSystemColor(FBorderColor)`
- `uIDEHelpPanel.ShowPlaceholder`:
  `FHelpDescLabel.Color := ActiveStyleServices.GetSystemColor(IDE_BG_CHROME)`
- `uIDEHelpPanel.ShowFinding`:
  `ColorDefault := ActiveStyleServices.GetSystemColor(IDE_BG_CHROME)`

`ActiveStyleServices` ist die Wrapper-Funktion in `uAnalyserTheme.pas` die
über `StyleServicesProvider` die IDE-Theming-StyleServices liefert. Provider
ist in `uIDEAnalyserForm.RegisterAnalyserDockableForm` bereits gesetzt.

Adressiert Ursache **1** — Custom-Paint nutzt die IDE-Theme-Quelle, nicht
die VCL-globale.

## Implementierungsreihenfolge

1. **A**: `Update`-Aufruf in `ApplyRecursive` (1 Zeile)
2. **B**: `ResolveIDEColor` + `TControlAccess` + Color/Font.Color-Walk in
   `ApplyRecursive` (~20 Zeilen)
3. **C**: `StyleServices` → `ActiveStyleServices` in TilePanel.Paint +
   uIDEHelpPanel.ShowPlaceholder/ShowFinding (3 Stellen)

Alle drei sind orthogonal — können einzeln gerollback werden falls Probleme.

## Test

Im Docked-Modus IDE-Theme wechseln (Tools → Options → IDE → Theme → Dark
↔ Light). Erwartet: Tiles, Toolbar-Panels, Help-Panel-Caption,
Before/After-Memos folgen dem Wechsel.

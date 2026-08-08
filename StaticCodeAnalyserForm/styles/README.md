# Eingebetteter VCL-Style

`SCADark.vsf` (interner Name `SCA VSDark`) ist ein per Skript
umgefärbtes `Windows10Dark.vsf` aus `Redist\styles\vcl\` der Delphi-12-
Installation — der Redist-Ordner ist ausdrücklich zur Weitergabe mit
eigenen Anwendungen bestimmt.

**Warum umgefärbt (2026-08-08, User-Auflage):** das Original steht
wörtlich auf `clBlack` (Window, Panel, Grid, Edit, Menü) und wirkte
erdrückend. Gewünscht war das VS-Code-„Dark Modern"-Grau; ein
Redist-Kandidat mit genau dieser Palette existiert nicht
(Zwischenschritt `Windows10SlateGray.vsf` war zu blaustichig).

**Palette** (VS Code Dark Modern; TColor = `$00BBGGRR`):

| Rolle | Wert | verwendet für |
|---|---|---|
| Chrome | `#181818` | clBtnFace, Panel, Toolbar, Caption |
| Inhalt | `#1F1F1F` | clWindow, Grid, Listen, Menü |
| Widget | `#252526` | Hints, Disabled, Alternating Rows |
| Eingabe | `#313131` | Edit, ComboBox, ButtonNormal |
| Rand | `#2B2B2B` | Border, Splitter, ActiveBorder |
| Text | `#CCCCCC` | clWindowText/clBtnText + 71 Font-Einträge |

**Entstehung:** das `.vsf`-Format ist `VCL_STYLE 2.0` + zlib; Farben
liegen darin als Klartext-Tripel `Name ':' Wert` (`Vcl.StyleAPI.pas`,
`TSeStyleColors.SaveToStream`). Das Patch-Skript ersetzt 43 Farbwerte,
das Font-Weiß und den internen Namen und verifiziert per Roundtrip —
bitmap-gezeichnete Elemente (Scrollbar-Daumen, Glyphen, Titelleisten-
Knöpfe) behalten die dunklen Original-Bitmaps, was zum dunklen Chrome
von VS Code passt. Skript: Session-Scratchpad `vsf_patch.py` 2026-08-08
(bei Bedarf aus diesem README rekonstruierbar).

Der Ressourcenname ist das neutrale `SCADARK`: er codiert die ROLLE
(der dunkle Style der Anwendung), nicht die Datei — ein erneuter Tausch
ändert nur `.rc` und `.vsf`.

`sca_styles.RES` ist mit `brcc32` aus `sca_styles.rc` erzeugt und wird im
`.dpr` über `{$R 'styles\sca_styles.RES'}` gelinkt; `uAppTheme` lädt den
Style zur Laufzeit über `TStyleManager.TryLoadFromResource` und aktiviert
ihn über das Handle — damit hängt nichts am (nicht garantierten) internen
Style-Namen.

**Der Ressourcen-TYP muss `VCLSTYLE` sein, nicht `RCDATA`.** Das ist der
Typ, den `Vcl.Styles` selbst registriert (`TStyleEngine.ResourceTypeName`).
Mit `RCDATA` stürzt das Laden ab: `TryLoadFromResource` reicht den
`ResourceType`-`PChar` an `FindStyleDescriptor` weiter, und das nimmt einen
`string` — die implizite Umwandlung dereferenziert den Zeiger. `RT_RCDATA`
ist `PChar(10)`, also der Zahlenwert 10 als Zeiger, und der Absturz meldete
folgerichtig `read of address 0x0000000a`. Der Compiler kann das nicht
sehen, weil `PChar` formal auf beide Bedeutungen passt.

**Warum eingebettet statt Projektoptionen-Haken:** die Auswahl in
„Erscheinungsbild" schreibt IDE-spezifische Einträge in die `.dproj`, die
außerhalb der IDE schwer korrekt zu erzeugen sind. Die `{$R}`-Einbettung
leistet dasselbe, ist versionierbar und baut auf jeder Maschine gleich.

Neu erzeugen (nur nötig, wenn sich die `.rc` ändert):

    cd StaticCodeAnalyserForm\styles
    "%BDS%\bin\brcc32.exe" sca_styles.rc

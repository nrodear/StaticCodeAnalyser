# Eingebetteter VCL-Style

`Windows10SlateGray.vsf` stammt aus `Redist\styles\vcl\` der Delphi-12-
Installation — der Redist-Ordner ist ausdrücklich zur Weitergabe mit
eigenen Anwendungen bestimmt.

Bis 2026-08-08 war hier `Windows10Dark.vsf` eingebettet; das nahezu
schwarze Fenster wirkte erdrückend. Das Slate-Grau entspricht dem
verbreiteten IDE-Dunkelgrau (RAD Studio, VS) — User-Auflage. Der
Ressourcenname ist seither das neutrale `SCADARK`: der Name codiert die
ROLLE (der dunkle Style der Anwendung), nicht die Datei — ein erneuter
Tausch ändert dann nur noch `.rc` und `.vsf`.

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

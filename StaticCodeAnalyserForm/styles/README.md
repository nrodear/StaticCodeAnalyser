# Eingebetteter VCL-Style

`Windows10Dark.vsf` stammt aus `Redist\styles\vcl\` der Delphi-12-
Installation — der Redist-Ordner ist ausdrücklich zur Weitergabe mit
eigenen Anwendungen bestimmt.

`sca_styles.RES` ist mit `brcc32` aus `sca_styles.rc` erzeugt und wird im
`.dpr` über `{$R 'styles\sca_styles.RES'}` gelinkt; `uAppTheme` lädt den
Style zur Laufzeit über `TStyleManager.TryLoadFromResource` und aktiviert
ihn über das Handle — damit hängt nichts am (nicht garantierten) internen
Style-Namen.

**Warum eingebettet statt Projektoptionen-Haken:** die Auswahl in
„Erscheinungsbild" schreibt IDE-spezifische Einträge in die `.dproj`, die
außerhalb der IDE schwer korrekt zu erzeugen sind. Die `{$R}`-Einbettung
leistet dasselbe, ist versionierbar und baut auf jeder Maschine gleich.

Neu erzeugen (nur nötig, wenn sich die `.rc` ändert):

    cd StaticCodeAnalyserForm\styles
    "%BDS%\bin\brcc32.exe" sca_styles.rc

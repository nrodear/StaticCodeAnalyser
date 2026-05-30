# Branding-Assets

Single source of truth fuer Bild-Assets, die Standalone-App und IDE-Plugin
gemeinsam nutzen. Beide Builds binden die Dateien aus diesem Ordner ein.

## Dateien

| Datei | Wo gebraucht |
|---|---|
| `sca.png` | App-Icon (297x242, 8-bit RGB). Wird via `sca_branding.rc` als `RCDATA`-Resource eingebettet. |
| `sca_branding.rc` | RC-Definition (`SCA_APP_PNG RCDATA "sca.png"`). Build-Integration ist **zweistufig** (siehe unten). |
| `sca_branding.res` | BRCC32-Output, **nicht** im Repo (in `.gitignore`). Regeneriert sich pro Build aus `sca_branding.rc`. |
| `uBrandingImage.pas` | Shared Pascal-Helper. `LoadSCAPng: TPngImage` und `LoadSCABitmap: TBitmap` decodieren die Resource zur Laufzeit. |

## Was wo angezeigt wird

| Pfad | Stelle | Wie |
|---|---|---|
| Standalone-EXE | `Application.Icon` (Taskleiste-Icon waehrend Laufzeit, Window-Caption) | `TIcon.Assign(LoadSCAPng)` in `.dpr` vor `CreateForm` — WIC-Codec skaliert auf System-Icon-Groessen |
| Standalone-EXE | Datei-Symbol im Explorer / Taskbar-Symbol VOR App-Start | **derzeit Delphi-Default** (`delphi_PROJECTICON.ico`) — Windows kann nur ICO-Format aus der `.res` lesen, kein PNG. Siehe **Bekanntes Limit** unten. |
| IDE-Plugin | Splash-Screen-Eintrag waehrend IDE-Boot | `SplashScreenServices.AddPluginBitmap(name, HBITMAP, ...)` mit `LoadSCABitmap.Handle` |
| IDE-Plugin | Help → About → Plugins | `IOTAAboutBoxServices.AddPluginInfo(name, desc, HBITMAP, ...)` mit `LoadSCABitmap.Handle` |

## Bekanntes Limit: EXE-Shell-Icon

Das **Datei-Icon im Windows-Explorer** und das **Taskbar-Icon vor App-Start**
liest Windows direkt aus der Resource-Section der .exe — und akzeptiert dort
nur `RT_GROUP_ICON` / `RT_ICON` (ICO-Format), kein PNG.

`Application.Icon := PNG` setzt das **Runtime-Icon** (sichtbar sobald die App
laeuft: Window-Caption, Alt-Tab, gepinnter Taskbar-Eintrag waehrend der
Sitzung). Vor App-Start sieht der User aber das in die .exe einkompilierte
Default-Icon von Delphi.

**Wenn das Shell-Icon ebenfalls `sca` zeigen soll:**

1. PNG → ICO konvertieren (z. B. mit ImageMagick, online-Konverter, oder
   `magick convert sca.png -define icon:auto-resize=256,48,32,16 sca.ico`).
2. `sca.ico` in `branding/` ablegen.
3. In `StaticCodeAnalyserForm/StaticCodeAnalyser.d12.dproj` Zeile `<Icon_MainIcon>`
   von `$(BDS)\bin\delphi_PROJECTICON.ico` auf `..\branding\sca.ico` aendern.
4. IDE-Build → die .ico wird via `brcc32` in die `.res` einkompiliert,
   Windows-Explorer zeigt das neue Icon.

## Build-Integration (zweistufig — beide Schritte zwingend)

| Schritt | Wo | Was bewirkt |
|---|---|---|
| 1. Compile | `<RcCompile Include="..\branding\sca_branding.rc"/>` im **`.dproj`** | Delphis MSBuild ruft BRCC32 auf, erzeugt `branding\sca_branding.res` |
| 2. Link | `{$R '..\branding\sca_branding.res'}` im **`.dpr` / `.dpk`** | Linker bindet die `.res` als Binary-Resource in die EXE/BPL ein |

**WICHTIG:** Schritt 1 allein reicht NICHT — ohne Schritt 2 erzeugt BRCC32
zwar die `.res`, aber RLINK32 packt sie nicht in die fertige Binary, und
das App-Icon ist nirgends sichtbar (Window-Caption, Taskleiste, About-Box,
Splash — alles leer).

**FALLE bei Schritt 2:** Die `.res`-Extension ist Pflicht.
`{$R '...rc'}` (mit `.rc`-Extension) triggert den **16-bit-Legacy-BRC**
statt BRCC32 und failt mit `E2161 RLINK32: Unsupported 16bit resource`.

## Add a new asset

1. Datei in diesem Ordner ablegen.
2. Ggf. `sca_branding.rc` um eine weitere Resource-Definition erweitern
   (`MY_ASSET RCDATA "myasset.png"`).
3. `uBrandingImage.pas` um einen Loader-Funktion erweitern.
4. Konsumenten anbinden — kein Edit an `.dproj` / `.dpk` noetig solange die
   Datei nur ueber `sca_branding.rc` referenziert wird.

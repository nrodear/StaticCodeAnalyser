# GetIt-Paket (Vorlage, Stand 2026-08-14)

`StaticCodeAnalyser-D12.getit.json` ist die **Vorlage** fuer das lokale
GetIt-Paket (RAD Studio: GetIt-Dialog -> "Load Local Package") und
zugleich die Bewerbungsmappe fuer die Einreichung bei Embarcadero
(getitnow.embarcadero.com/submit). Format: "GetIt Local Files"
(vereinfachtes Server-Format; DocWiki "Local GetIt Packages").

## Feld-Vertraege

**HARTE Format-Fallen des Local-Parsers** (GetItMapper, Exception-Analyse
2026-08-15 gegen das offizielle Abbrevia-Sample + Doku-PDF verifiziert):

1. ALLE Skalarwerte sind JSON-STRINGS - auch numerische:
   `"RequireElevation": "0"`, `"AllUsers": "0"`, Action-`"Id"`,
   `"ActionId"`, `"Type"`. Zahlen (TJSONNumber) crashen den Mapper
   (MapCatalog -> ScanTimeRegular-Stack).
2. `Parameter` ist ein ARRAY VON OBJEKTEN: `[{ "Parameter": "..." }]` -
   ein String-Array gibt "Ungueltige Typumwandlung" (DP-Thread 216209).
3. Schraegstriche in URLs escapen (`https:\/\/...`) - Url, VendorUrl,
   ProjectUrl; das Release-Skript escaped beim Ersetzen.
4. `Modified`-Format ist `yyyy-mm-dd hh:nn:ss` (String, 24h, ohne
   Millisekunden/Zeitzone) - im GetIt-Binary hartkodiert.
5. Feld-Reihenfolge und PascalCase-Namen des offiziellen Samples
   beibehalten (alter Mapper-Code, Toleranz unbekannt).

- `Id` ist STABIL zu halten (steuert den Registry-Schluessel unter
  `HKCU\...\CatalogRepository\Elements`); neue Id = koexistierendes
  Paket statt Update.
- **Updates steuert `Modified`**, nicht `Version` - `Version` ist reiner
  Anzeigetext. Bei jedem Release: `Modified` auf die Buildzeit setzen
  (geplant: Erzeugung in tools\package-release.ps1, Todo P3.3).
- `AllUsers=0` + `RequireElevation=0`: per-User, kein Admin - passt zum
  HKCU-Modell des Plugins.
- Actions: 17 = InstallIDEPackage (registriert + laedt die BPL live),
  18 = UninstallIDEPackage; Type 3 = Before Install, 5 = Before
  Uninstall. Pfad-Wurzel ist `$(BDSCatalogRepository)\<Id>\...` - dort
  entpackt GetIt das ZIP.

## Offene Punkte vor dem ersten Test (Todo P3)

1. ERLEDIGT 2026-08-15: Lizenz = **MIT** (User-Entscheid); `License`
   zeigt auf die Repo-LICENSE, `LicenseName` = MIT. Dieselbe Datei
   speist die Lizenz-Seite des Inno-Setups.
2. ERLEDIGT 2026-08-15: `sca_logo_128.png` aus branding\sca.png
   abgeleitet (500x500 -> 128x128, Lanczos).
3. ERLEDIGT 2026-08-15: package-release.ps1 erzeugt die Artefakte
   (Opt-out -SkipGetIt): `StaticCodeAnalyser-v<V>-plugin-getit.zip`
   (BPL + LICENSE + Logo im Wurzelverzeichnis) + ZWEI finalisierte
   Manifeste mit Modified=Paketier-Zeit:
   - `StaticCodeAnalyser-D12.getit.json` - Url = GitHub-Release-Asset
     (fuer Einreichung/Endnutzer; Asset muss am Release haengen)
   - `StaticCodeAnalyser-D12.local.getit.json` - Url = lokaler
     ZIP-Pfad (fuer den Lokaltest VOR dem Upload)
   Diese Datei hier bleibt die VORLAGE - Version/Modified/Url werden
   pro Release ersetzt, Aenderungen an Actions/Texten nur hier.
4. Lokaltest (P3.5): D12-IDE -> GetIt-Dialog -> "Load Local Package" ->
   `release-artifacts\StaticCodeAnalyser-D12.local.getit.json` waehlen;
   Install / Uninstall / Doppel-Install pruefen. Braucht eine aktive
   Update Subscription. VORHER sicherstellen, dass das Plugin nicht
   schon anders registriert ist (Setup deinstallieren bzw.
   Dev-Registrierung raus - sonst laedt dieselbe Unit doppelt).

Privacy-Leitplanke: das Paket enthaelt KEINEN Netzcode - GetIt laedt das
ZIP, nicht das Plugin.

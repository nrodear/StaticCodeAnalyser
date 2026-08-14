# GetIt-Paket (Vorlage, Stand 2026-08-14)

`StaticCodeAnalyser-D12.getit.json` ist die **Vorlage** fuer das lokale
GetIt-Paket (RAD Studio: GetIt-Dialog -> "Load Local Package") und
zugleich die Bewerbungsmappe fuer die Einreichung bei Embarcadero
(getitnow.embarcadero.com/submit). Format: "GetIt Local Files"
(vereinfachtes Server-Format; DocWiki "Local GetIt Packages").

## Feld-Vertraege

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

1. `License`/`EULA.txt`: Freeware-EULA fehlt noch - **Lizenzmodell ist
   User-Entscheid** (P3.1).
2. `Image`/`sca_logo_128.png`: 128px-PNG fehlt (P3.2); Quelle koennte
   branding\sca.png sein.
3. `Url`: zeigt auf ein noch nicht existierendes Release-Asset
   `...-plugin-getit.zip` (ZIP mit der Monolith-BPL im Wurzelverzeichnis);
   Erzeugung in package-release.ps1 ergaenzen (P3.3/P3.4).
4. Test via "Load Local Package" braucht eine aktive Update Subscription
   (P3.5).

Privacy-Leitplanke: das Paket enthaelt KEINEN Netzcode - GetIt laedt das
ZIP, nicht das Plugin.

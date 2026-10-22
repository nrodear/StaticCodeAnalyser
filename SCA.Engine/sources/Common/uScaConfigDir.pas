unit uScaConfigDir;

// Das Konfigurationsverzeichnis der SCA als BLATT-Unit (Folgewelle des
// Wochen-Reviews 2026-10-21, G05-21).
//
// %APPDATA%\StaticCodeAnalyser\ - ohne APPDATA das Temp-Verzeichnis
// (%TEMP%\StaticCodeAnalyser\). Dort liegen ignore.txt und das Scan-Log
// (TIgnoreList.ConfigDir), analyser.ini (uRepoSettings), profiles.json
// und rules\ (uRuleCatalog) und redelphix.ini (uRdxText).
//
// WARUM EIGENE UNIT: bis hierher stand dieselbe Formel dreimal da -
// TIgnoreList.ConfigDir (Infrastructure), TRuleCatalog.UserProfilesFilePath
// (Common, darf Infrastructure nicht binden) und DefaultConfigDir in
// uRdxText (uIgnoreList zieht die Engine-Infrastruktur nach und uebersetzt
// im FPC-Pruefstand nicht). Wer die Ablage verschiebt, musste alle drei
// Stellen anfassen. Diese Unit bindet nur SysUtils (und unter Delphi
// System.IOUtils) und uebersetzt deshalb auch unter FPC 3.2.2 - jede
// Schicht darf sie nehmen.

interface

// Mit abschliessendem Pfadtrenner.
function ScaConfigDir: string;

implementation

uses
  {$IFNDEF FPC}
  System.IOUtils,       // TPath.GetTempPath
  {$ENDIF}
  System.SysUtils;

const
  CONFIG_SUBDIR = 'StaticCodeAnalyser';

// FPC 3.2 kennt System.IOUtils nicht; GetTempDir liefert dort dasselbe
// Verzeichnis mit Trenner.
function TempDir: string;
begin
  {$IFDEF FPC}
  Result := GetTempDir;
  {$ELSE}
  Result := TPath.GetTempPath;
  {$ENDIF}
end;

function ScaConfigDir: string;
var
  Base : string;
begin
  Base := GetEnvironmentVariable('APPDATA');
  if Base = '' then
    Base := TempDir;
  Result := IncludeTrailingPathDelimiter(Base) + CONFIG_SUBDIR + PathDelim;
end;

end.

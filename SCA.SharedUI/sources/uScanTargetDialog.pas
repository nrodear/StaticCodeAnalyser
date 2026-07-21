unit uScanTargetDialog;

// EIN Dialog fuer alle Scan-Ziele (User-Anforderung 2026-07-22, Konzept_
// ScanScope par.4.3-Revision 2): Ordner ODER .dproj ODER .groupproj in
// EINEM Auswahlvorgang. Geteilt zwischen Standalone-Form und IDE-Plugin.
//
// Windows kennt keinen nativen Kombi-Dialog (FOS_PICKFOLDERS zeigt keine
// Dateien, der Datei-Modus laesst keine Ordner-Auswahl zu). Deshalb das
// bewaehrte Sentinel-Muster im DATEI-Modus:
//   * Filter zeigt .dproj/.groupproj (plus 'Alle Dateien' zum Navigieren),
//   * der Dateiname ist mit einem Sentinel vorbelegt ("Diesen Ordner
//     scannen"); navigiert der User in einen Ordner und klickt Oeffnen,
//     ohne eine Datei zu waehlen, existiert <Ordner>\<Sentinel> nicht ->
//     wir interpretieren das als ORDNER-Auswahl (aktueller Dialog-Ordner).
//   * waehlt er eine .dproj/.groupproj, kommt deren Pfad zurueck.
// Die Scope-ERKENNUNG (rekursiv vs. Projekt vs. Gruppe) macht der Aufrufer
// am Ergebnis-Pfad (Smart-Path) - dieser Dialog liefert nur den Pfad.

interface

// Liefert '' bei Abbruch; sonst einen existierenden Ordner ODER eine
// existierende .dproj-/.groupproj-/sonstige Datei (absoluter Pfad).
// AInitialDir darf auch ein Dateipfad sein (es wird dessen Ordner genutzt).
function SelectScanTarget(const AInitialDir: string): string;

implementation

uses
  System.SysUtils, Vcl.Dialogs,
  uLocalization;

function SelectScanTarget(const AInitialDir: string): string;
var
  Dlg      : TOpenDialog;
  Sentinel : string;
  Init     : string;
begin
  Result := '';
  // Sentinel bewusst OHNE Datei-Endung und lokalisiert - kollidiert
  // praktisch nie mit einer echten Datei; Kollision waere zudem harmlos
  // (dann ist es eben eine echte Datei-Auswahl).
  Sentinel := _('Scan this folder');

  Init := Trim(AInitialDir);
  if (Init <> '') and FileExists(Init) then
    Init := ExtractFilePath(Init);

  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Title    := _('Select folder, project (.dproj) or group (.groupproj)');
    Dlg.Filter   := _('Delphi project/group (*.dproj;*.groupproj)') +
                    '|*.dproj;*.groupproj|' +
                    _('All files') + ' (*.*)|*.*';
    Dlg.FileName := Sentinel;
    // ofNoValidate + KEIN ofFileMustExist: der Sentinel-"Dateiname" darf
    // nicht existieren. ofPathMustExist haelt den ORDNER-Teil valide.
    Dlg.Options  := [ofNoValidate, ofPathMustExist, ofEnableSizing];
    if Init <> '' then
      Dlg.InitialDir := Init;
    if not Dlg.Execute then Exit;

    Result := Dlg.FileName;
    if not FileExists(Result) then
    begin
      // Ordner-Fall: Sentinel (oder frei getippter Nicht-Datei-Name) im
      // navigierten Ordner -> der Ordner (= Pfad-Anteil) ist das Scan-Ziel.
      // ExtractFilePath behaelt den Trailing-Backslash - den NICHT bei einer
      // Laufwerks-/UNC-Wurzel abschneiden, sonst wird 'C:\' zu 'C:' (zeigt
      // aufs laufwerks-relative CWD statt die Wurzel).
      Result := ExtractFilePath(Result);
      if not DirectoryExists(Result) then
        Result := ''
      else if Length(ExcludeTrailingPathDelimiter(Result)) > 2 then
        Result := ExcludeTrailingPathDelimiter(Result);
      // sonst (Wurzel wie 'C:\' oder '\\srv\share\') den Delimiter behalten.
    end;
  finally
    Dlg.Free;
  end;
end;

end.

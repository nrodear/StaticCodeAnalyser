unit uVnpLog;

// VarNameProject - Protokoll jedes Schritts: in die Meldungsansicht der
// IDE (eigene Gruppe "VarNameProject") und nach %TEMP%\VarNameProject.log.
// Das Testprojekt lebt davon, dass Nico die Zeilen zurueckmeldet: welche
// Variante eine Sitzung startet, welche Offsets die IDE selbst benutzt,
// wo der Caret danach steht.

interface

procedure VnpLog(const AText: string); overload;
procedure VnpLog(const AFmt: string; const AArgs: array of const); overload;
// Pfad der Protokolldatei.
function VnpLogFile: string;
// Meldungsansicht mit der Gruppe nach vorn holen.
procedure VnpShowLog;
// Datei und Meldungsgruppe leeren.
procedure VnpClearLog;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, ToolsAPI;

const
  GROUP_NAME = 'VarNameProject';

var
  GGroup : IOTAMessageGroup = nil;

function VnpLogFile: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'VarNameProject.log');
end;

procedure AppendToFile(const AText: string);
var
  W : TStreamWriter;
begin
  try
    W := TStreamWriter.Create(VnpLogFile, True, TEncoding.UTF8);
    try
      W.WriteLine(FormatDateTime('hh:nn:ss.zzz', Now,
        TFormatSettings.Invariant) + '  ' + AText);
    finally
      W.Free;
    end;
  except
    // Das Protokoll darf den Test nie abbrechen (Datei gesperrt, TEMP
    // voll ...) - der letzte Ausweg ist der Debugger-Kanal.
    // noinspection ExceptionTooGeneral
    on E: Exception do
      // noinspection DebugOutput
      OutputDebugString(PChar(GROUP_NAME + ': ' + E.Message));
  end;
end;

function Group(const ASvc: IOTAMessageServices): IOTAMessageGroup;
begin
  if GGroup = nil then
    GGroup := ASvc.AddMessageGroup(GROUP_NAME);
  Result := GGroup;
end;

procedure VnpLog(const AText: string);
var
  Svc : IOTAMessageServices;
begin
  AppendToFile(AText);
  if Supports(BorlandIDEServices, IOTAMessageServices, Svc) then
    Svc.AddTitleMessage(AText, Group(Svc));
end;

procedure VnpLog(const AFmt: string; const AArgs: array of const);
begin
  VnpLog(Format(AFmt, AArgs));
end;

procedure VnpShowLog;
var
  Svc : IOTAMessageServices;
begin
  if Supports(BorlandIDEServices, IOTAMessageServices, Svc) then
    Svc.ShowMessageView(Group(Svc));
end;

procedure VnpClearLog;
var
  Svc : IOTAMessageServices;
begin
  if TFile.Exists(VnpLogFile) then
    TFile.Delete(VnpLogFile);
  if Supports(BorlandIDEServices, IOTAMessageServices, Svc) then
    Svc.ClearMessageGroup(Group(Svc));
end;

procedure ReleaseGroup;
var
  Svc : IOTAMessageServices;
begin
  if (GGroup <> nil)
     and Supports(BorlandIDEServices, IOTAMessageServices, Svc) then
    Svc.RemoveMessageGroup(GGroup);
  GGroup := nil;
end;

initialization

finalization
  ReleaseGroup;

end.

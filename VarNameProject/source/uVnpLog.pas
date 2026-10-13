unit uVnpLog;

// VarNameProject - Protokoll jedes Schritts: nach %TEMP%\VarNameProject.log
// und in die Meldungsansicht der IDE (eigene Gruppe "VarNameProject").
// Das Testprojekt lebt davon, dass Nico die Zeilen zurueckmeldet.
//
// Jede Dateizeile traegt die Prozess-ID, jede Ladung des Pakets schreibt
// eine Kopfzeile (PID, Prozessstart, Ladung n): das Protokoll zeigt selbst,
// ob die IDE zwischen zwei Laeufen neu gestartet wurde - im alten
// Protokoll war nicht abzulesen, dass die Laeufe 4 und 5 ohne Neustart im
// selben Prozess liefen (Gutachten 2026-10-11).
//
// VnpLogFileOnly schreibt nur die Datei: fuer die Sonde (sie soll die
// laufende Sitzung nicht anfassen), fuer except-Zweige nach einer
// Zugriffsverletzung und fuer den Abbau (dann kann die Meldungsansicht
// schon weg sein). Der naechste VnpLog bzw. VnpShowLog holt solche Zeilen
// in die Meldungsansicht nach; nach VnpReleaseGroup schreibt jeder Aufruf
// nur noch die Datei.

interface

procedure VnpLog(const AText: string); overload;
procedure VnpLog(const AFmt: string; const AArgs: array of const); overload;
// Nur in die Datei - die Meldungsansicht holt die Zeile spaeter nach.
procedure VnpLogFileOnly(const AText: string); overload;
procedure VnpLogFileOnly(const AFmt: string;
  const AArgs: array of const); overload;
// Pfad der Protokolldatei.
function VnpLogFile: string;
// Meldungsansicht mit der Gruppe nach vorn holen. NICHT waehrend einer
// Sync-Sitzung und nicht nach einer Zugriffsverletzung (Aktivierungs-
// wechsel).
procedure VnpShowLog;
// Datei und Meldungsgruppe leeren, danach die Kopfzeile neu schreiben.
procedure VnpClearLog;
// Die Ladung zaehlen, einmal je Register: Umgebungsvariable VNP_LOADS des
// IDE-Prozesses - sie uebersteht das Neuinstallieren des Pakets und
// verschwindet mit dem Prozess.
procedure VnpCountLoad;
// Kopfzeile: PID, Prozessstart, Ladung, HInstance.
procedure VnpLogHeader;
// Die Meldungsgruppe abmelden (Abbau); idempotent. Danach schreibt jeder
// Aufruf nur noch die Datei.
procedure VnpReleaseGroup;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, Vcl.Forms,
  ToolsAPI;

const
  GROUP_NAME = 'VarNameProject';
  ENV_LOADS  = 'VNP_LOADS';

var
  // Zeilen, die bisher nur in der Datei stehen.
  GPending : TStringList = nil;
  GClosed  : Boolean = False;
  GLoad    : Integer = 0;

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
      W.WriteLine(Format('%s  [%d]  %s', [FormatDateTime('hh:nn:ss.zzz', Now,
        TFormatSettings.Invariant), GetCurrentProcessId, AText]));
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

// Die Gruppe "VarNameProject" - jedes Mal frisch geholt, nie gemerkt: der
// Nutzer kann eine Gruppe schliessen ("Close Tab", Mittelklick, "Clear All
// Messages"), eine gemerkte Referenz zeigte danach auf eine verwaiste
// Gruppe - Zeilen gingen ins Leere, und RemoveMessageGroup mit ihr loeschte
// beim Abbau den Tab einer FREMDEN Gruppe (Review 2026-10-11, in coreide290
// nachvollzogen). CanClose := False sperrt das Schliessen; GetGroup deckt
// den Rest ab und findet auch die Gruppe einer frueheren Ladung.
function Group(const ASvc: IOTAMessageServices): IOTAMessageGroup;
begin
  Result := ASvc.GetGroup(GROUP_NAME);
  if Result = nil then
  begin
    Result := ASvc.AddMessageGroup(GROUP_NAME);
    Result.CanClose := False;
  end;
end;

// Die bisher nur in die Datei geschriebenen Zeilen nachholen.
procedure FlushPending(const ASvc: IOTAMessageServices);
var
  S : string;
begin
  if GPending = nil then
    Exit;
  for S in GPending do
    ASvc.AddTitleMessage(S, Group(ASvc));
  GPending.Clear;
end;

procedure VnpLogFileOnly(const AText: string);
begin
  AppendToFile(AText);
  if GClosed then
    Exit;
  if GPending = nil then
    GPending := TStringList.Create;
  GPending.Add(AText);
end;

procedure VnpLogFileOnly(const AFmt: string; const AArgs: array of const);
begin
  VnpLogFileOnly(Format(AFmt, AArgs));
end;

procedure VnpLog(const AText: string);
var
  Svc : IOTAMessageServices;
begin
  AppendToFile(AText);
  if GClosed then
    Exit;
  if Supports(BorlandIDEServices, IOTAMessageServices, Svc) then
  begin
    FlushPending(Svc);
    Svc.AddTitleMessage(AText, Group(Svc));
  end;
end;

procedure VnpLog(const AFmt: string; const AArgs: array of const);
begin
  VnpLog(Format(AFmt, AArgs));
end;

procedure VnpShowLog;
var
  Svc : IOTAMessageServices;
begin
  if GClosed then
    Exit;
  if Supports(BorlandIDEServices, IOTAMessageServices, Svc) then
  begin
    FlushPending(Svc);
    Svc.ShowMessageView(Group(Svc));
  end;
end;

procedure VnpClearLog;
var
  Svc : IOTAMessageServices;
begin
  if GPending <> nil then
    GPending.Clear;
  if FileExists(VnpLogFile) and not DeleteFile(VnpLogFile) then
    VnpLog('Protokolldatei nicht geloescht (gesperrt?) - %s', [VnpLogFile]);
  if not GClosed
     and Supports(BorlandIDEServices, IOTAMessageServices, Svc) then
    Svc.ClearMessageGroup(Group(Svc));
  VnpLogHeader;
end;

procedure VnpCountLoad;
begin
  GLoad := StrToIntDef(System.SysUtils.GetEnvironmentVariable(ENV_LOADS),
    0) + 1;
  Winapi.Windows.SetEnvironmentVariable(PChar(ENV_LOADS),
    PChar(IntToStr(GLoad)));
end;

// Startzeit des IDE-Prozesses (lokal) oder '?'.
function ProcessStart: string;
var
  Created, Ended, Kernel, User : TFileTime;
  Local                        : TFileTime;
  St                           : TSystemTime;
begin
  Result := '?';
  if GetProcessTimes(GetCurrentProcess, Created, Ended, Kernel, User)
     and FileTimeToLocalFileTime(Created, Local)
     and FileTimeToSystemTime(Local, St) then
    Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', SystemTimeToDateTime(St),
      TFormatSettings.Invariant);
end;

procedure VnpLogHeader;
begin
  VnpLog('### VarNameProject: PID %d, Prozessstart %s, Ladung %d in diesem '
    + 'Prozess, HInstance $%x, Protokoll %s', [GetCurrentProcessId,
    ProcessStart, GLoad, HInstance, VnpLogFile]);
end;

// Die Gruppe abmelden, falls es sie gibt - eine eigene Routine, damit auch
// die Freigabe der lokalen Referenzen noch im try des Aufrufers liegt.
procedure RemoveGroup;
var
  Svc : IOTAMessageServices;
  G   : IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Svc) then
    Exit;
  G := Svc.GetGroup(GROUP_NAME);
  if G <> nil then
    Svc.RemoveMessageGroup(G);
end;

procedure VnpReleaseGroup;
begin
  if GClosed then
    Exit;
  GClosed := True;
  if GPending <> nil then
    GPending.Clear;
  // Beim Ende der IDE ist die Meldungsansicht schon abgebaut:
  // RemoveMessageGroup lief dort in eine abgefangene Zugriffsverletzung
  // (Lesen von 00000008, UI-Test 2026-10-11). Die Gruppe verschwindet mit
  // dem Prozess - also nicht abmelden. VERDACHT (Pruefer 2026-10-13, Minor
  // 8): ob Application.Terminated im Wizard-Destruktor schon gesetzt ist,
  // zeigt das Protokoll ("IDE-Ende" statt "abmelden: EAccessViolation").
  // Beim Deinstallieren des Pakets im laufenden Prozess ist es False, und
  // die Gruppe wird wie bisher abgemeldet.
  if Application.Terminated then
  begin
    AppendToFile('Meldungsgruppe: IDE-Ende (Application.Terminated) - nicht '
      + 'abgemeldet, die Ansicht ist schon weg');
    Exit;
  end;
  try
    RemoveGroup;
  except
    // Netz: die Meldungsansicht kann auch sonst schon weg sein.
    // noinspection ExceptionTooGeneral
    on E: Exception do
      AppendToFile('Meldungsgruppe abmelden: ' + E.ClassName + ': '
        + E.Message);
  end;
end;

initialization

finalization
  // Netz: im Normalfall hat der Wizard-Destruktor (uVnpRegister) die Gruppe
  // schon abgemeldet, dann tut der Aufruf nichts.
  VnpReleaseGroup;
  FreeAndNil(GPending);

end.

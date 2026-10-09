unit uRdxLog;

// reDelphix - Protokoll. Jede Zeile geht an OutputDebugString (DebugView)
// UND in %TEMP%\reDelphix.log, damit ein Fehlschlag im Editor ohne
// Debugger nachvollziehbar ist (Nico, 2026-10-06: "fuege ggf. mehr
// Loginformationen hinzu"). Schreibfehler des Protokolls selbst gehen nur
// noch an DebugView - das Protokoll darf nie die Aktion zu Fall bringen.
// Ausgenommen sind der Stack-Ueberlauf (EStackExhausted, uCrashDiag) und
// EAbort: sie laufen wie im ganzen Projekt weiter (Review reDelphiX
// 2026-10-07, Nit 7).
//
// GROESSE (Review Minor 21): ist die Datei vor dem Anhaengen groesser als
// LOG_MAX_BYTES, wird sie zu reDelphix.log.1 (ein frueheres .1 entfaellt)
// und eine neue begonnen. Beide zusammen bleiben so bei etwa 2 MB, auch
// wenn die Gluehbirne bei jeder Caret-Zeile fragt.

interface

procedure RdxLog(const AMsg: string); overload;
procedure RdxLog(const AFmt: string; const AArgs: array of const); overload;
// Pfad der Protokolldatei - fuer Hinweise in Meldungen.
function RdxLogPath: string;

implementation

uses
  Winapi.Windows, System.SysUtils, System.IOUtils,
  uCrashDiag;   // EStackExhausted

const
  LOG_MAX_BYTES = 1024 * 1024;

function RdxLogPath: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'reDelphix.log');
end;

// Die eine Stelle, die an DebugView geht.
procedure DebugOut(const AMsg: string);
begin
  OutputDebugString(PChar('reDelphix: ' + AMsg));
end;

// Zu gross -> reDelphix.log.1, das naechste Anhaengen beginnt neu. Wirft
// nicht: TFile.GetSize liefert unter Windows -1 statt einer Ausnahme,
// DeleteFile/RenameFile liefern False. Scheitert das Umbenennen (eine
// zweite IDE schreibt gerade), waechst die Datei bis zum naechsten Versuch.
procedure RotateIfDue(const APath: string);
var
  Old : string;
begin
  if TFile.GetSize(APath) <= LOG_MAX_BYTES then Exit;
  Old := APath + '.1';
  if FileExists(Old) then
    System.SysUtils.DeleteFile(Old);
  System.SysUtils.RenameFile(APath, Old);
end;

procedure RdxLog(const AMsg: string);
var
  Line : string;
  Path : string;
begin
  Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + '  ' + AMsg;
  DebugOut(AMsg);
  try
    Path := RdxLogPath;
    RotateIfDue(Path);
    TFile.AppendAllText(Path, Line + sLineBreak, TEncoding.UTF8);
  except
    on EStackExhausted do raise;
    on EAbort do raise;
    // noinspection ExceptionTooGeneral
    // Das Protokoll darf die Aktion nie zu Fall bringen (s. Kopf): jeder
    // andere Schreibfehler - gesperrt, voll, keine Rechte - geht nur noch
    // an DebugView.
    on E: Exception do
      DebugOut('Protokoll nicht schreibbar: ' + E.ClassName + ': ' + E.Message);
  end;
end;

procedure RdxLog(const AFmt: string; const AArgs: array of const);
var
  Msg : string;
begin
  try
    Msg := Format(AFmt, AArgs);
  except
    // Vorlage und Argumente passen nicht zusammen (Format wirft dann
    // EConvertError) - wenigstens die Vorlage protokollieren.
    on E: EConvertError do
      Msg := AFmt + '  [Format: ' + E.Message + ']';
  end;
  RdxLog(Msg);
end;

end.

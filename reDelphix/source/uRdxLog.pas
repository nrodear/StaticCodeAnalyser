unit uRdxLog;

// reDelphix - Protokoll. Jede Zeile geht an OutputDebugString (DebugView)
// UND in %TEMP%\reDelphix.log, damit ein Fehlschlag im Editor ohne
// Debugger nachvollziehbar ist (Nico, 2026-10-06: "fuege ggf. mehr
// Loginformationen hinzu"). Schreibfehler des Protokolls selbst werden
// verschluckt - das Protokoll darf nie die Aktion zu Fall bringen.

interface

procedure RdxLog(const AMsg: string); overload;
procedure RdxLog(const AFmt: string; const AArgs: array of const); overload;
// Pfad der Protokolldatei - fuer Hinweise in Meldungen.
function RdxLogPath: string;

implementation

uses
  Winapi.Windows, System.SysUtils, System.IOUtils;

function RdxLogPath: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'reDelphix.log');
end;

procedure RdxLog(const AMsg: string);
var
  Line : string;
begin
  Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + '  ' + AMsg;
  OutputDebugString(PChar('reDelphix: ' + AMsg));
  try
    TFile.AppendAllText(RdxLogPath, Line + sLineBreak, TEncoding.UTF8);
  except
    // bewusst still: s. Kopf
  end;
end;

procedure RdxLog(const AFmt: string; const AArgs: array of const);
begin
  try
    RdxLog(Format(AFmt, AArgs));
  except
    RdxLog(AFmt);
  end;
end;

end.

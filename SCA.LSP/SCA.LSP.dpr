program SCA.LSP;

{$APPTYPE CONSOLE}

// =============================================================================
// SCA.LSP - Inkrement 0: minimaler LSP-Server (Diagnostics-only) auf der
// oeffentlichen Engine-Facade uEngineApi (vierter Consumer neben IDE-Plugin,
// CLI und Form-GUI - Doku_06_CLI_LSP_Reporting.md, LSP-Abschnitt).
//
// Transport:  stdio mit Content-Length-Framing (uLspStdio)
// Protokoll:  JSON-RPC 2.0 minimal (uLspProtocol) -
//             initialize/initialized/shutdown/exit,
//             textDocument/didOpen|didChange|didClose -> publishDiagnostics
// Analyse:    Buffer-Text -> TAnalysisSession ssSource (uLspDiagnostics);
//             Spalte konstant 1, bis Engine-Luecke E3 (Spaltenfeld in
//             TLeakFinding) geschlossen ist.
//
// ACHTUNG: stdout gehoert exklusiv dem Protokoll - hier darf NIE ein
// Writeln auf Output stehen. Fehlertexte gehen auf stderr (LogStdErr).
// =============================================================================

uses
  System.SysUtils,
  uLspStdio in 'sources\uLspStdio.pas',
  uLspProtocol in 'sources\uLspProtocol.pas',
  uLspDiagnostics in 'sources\uLspDiagnostics.pas';

var
  Server : TLspServer;

begin
  try
    Server := TLspServer.Create;
    try
      ExitCode := Server.Run;
    finally
      Server.Free;
    end;
  except
    on E: Exception do
    begin
      // Fataler Transport-/Startfehler: stderr + Exit-Code 1. NIE stdout.
      LogStdErr('Fatal: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.

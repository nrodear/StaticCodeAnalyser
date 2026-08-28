program SCA.LSP;

{$APPTYPE CONSOLE}

// =============================================================================
// SCA.LSP - Inkrement 0: minimaler LSP-Server (Diagnostics-only) auf der
// oeffentlichen Engine-Facade uEngineApi (vierter Consumer neben IDE-Plugin,
// CLI und Form-GUI - Doku_06_CLI_LSP_Reporting.md, LSP-Abschnitt).
//
// ACHTUNG - DIESES PROJEKT WIRD NICHT MITGEBAUT (Stand 2026-08-29).
// Es steht in KEINER der beiden Projektgruppen
// (StaticCodeAnalyser.d12.groupproj / .d13.64bit.groupproj) und in
// keinem Build-Skript unter tools/. Folge: Aenderungen an der
// Engine-Fassade brechen es unbemerkt - kein Compiler, kein Test, kein
// Gate sieht hierher.
//
// Nachgesehen am 2026-08-29: die genutzten Symbole (TScanRequest.Init,
// Req.Scope/Path/Source/Profile, TAnalysisSession.Run, Res.Findings)
// gibt es in uEngineApi alle noch, das Projekt duerfte also weiterhin
// uebersetzen. BEWIESEN ist das nicht - dafuer muesste es gebaut werden.
//
// Architektonisch ist es sauber: reiner Consumer der Fassade, keine
// Detektor-Logik, keine eigene Fund-Identitaet (kein Fingerprint, kein
// contextHash) - es kann also nicht von SARIF und Baseline abweichen.
// Was fehlt, ist die Aufnahme in eine Projektgruppe. Solange die
// aussteht, ist das hier Code, der verrottet, ohne dass es auffaellt -
// entweder aufnehmen oder bewusst archivieren.
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

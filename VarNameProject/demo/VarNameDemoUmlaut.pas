unit VarNameDemoUmlaut;

// VarNameProject - Fall 6 (Messpunkt M10): Nicht-ASCII VOR dem Literal.
// Diese Datei ist ABSICHTLICH UTF-8 mit BOM und enthaelt Umlaute und das
// Euro-Zeichen (sonst gilt im Repo: Pascal-Quellen nur ASCII) - sie misst,
// ob TOTACharPos.CharIndex Bytes oder Zeichen zaehlt: 'Grüße €' sind 7
// Zeichen, aber 11 UTF-8-Bytes.
//   1. Caret direkt hinter das Euro-Zeichen setzen,
//      Tools > VarNameProject > Sonde: CharIndex am Caret.
//   2. Caret auf die 42, Varianten wie in VarNameDemo.pas.

interface

function Greeting(Count: Integer): string;

implementation

uses
  System.SysUtils;

function Greeting(Count: Integer): string;
begin
  Result := 'Grüße € ' + IntToStr(Count * 42);
end;

end.

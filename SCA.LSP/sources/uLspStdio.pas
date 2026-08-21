unit uLspStdio;

// =============================================================================
// SCA.LSP - Inkrement 0 (Doku_06_CLI_LSP_Reporting.md, LSP-Abschnitt)
//
// Stdio-Transport mit Content-Length-Framing nach LSP-Basisprotokoll:
//
//   Content-Length: <n>\r\n
//   [weitere Header, werden ignoriert]\r\n
//   \r\n
//   <n Bytes UTF-8 JSON-Payload>
//
// Bewusst byte-orientiert ueber die Win32-Std-Handles (THandleStream) statt
// Readln/Writeln: die Pascal-Text-I/O wuerde CRLF-Uebersetzung und Codepage-
// Konvertierung dazwischenschalten und das Framing zerstoeren.
//
// WICHTIG fuer alle Consumer: stdout gehoert EXKLUSIV dem Protokoll. Jede
// zusaetzliche Writeln-Ausgabe korrumpiert den Stream. Debug-/Fehlertexte
// gehoeren auf stderr (siehe uLspProtocol.LogStdErr).
// =============================================================================

interface

uses
  System.SysUtils, System.Classes;

type
  ELspTransport = class(Exception);

  TLspStdio = class
  private
    FIn  : THandleStream;   // STD_INPUT_HANDLE
    FOut : THandleStream;   // STD_OUTPUT_HANDLE
    // Liest eine Header-Zeile (ASCII) bis LF; CR wird gestrippt.
    // False = EOF vor dem ersten Byte (Client hat die Pipe geschlossen).
    function ReadHeaderLine(out ALine: string): Boolean;
    // Liest exakt ACount Bytes (blockierend, mehrere Read-Runden).
    function ReadExact(var ABuf: TBytes; ACount: Integer): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    // Liest die naechste vollstaendige Nachricht. False = sauberes EOF
    // (Verbindungsende); wirft ELspTransport bei kaputtem Framing.
    function ReadMessage(out APayload: string): Boolean;

    // Schreibt eine Nachricht mit Content-Length-Header (Payload als UTF-8).
    procedure WriteMessage(const APayload: string);
  end;

implementation

uses
  Winapi.Windows;

{ TLspStdio }

constructor TLspStdio.Create;
begin
  inherited Create;
  FIn  := THandleStream.Create(GetStdHandle(STD_INPUT_HANDLE));
  FOut := THandleStream.Create(GetStdHandle(STD_OUTPUT_HANDLE));
end;

destructor TLspStdio.Destroy;
begin
  FOut.Free;
  FIn.Free;
  inherited;
end;

function TLspStdio.ReadHeaderLine(out ALine: string): Boolean;
var
  B     : Byte;
  Bytes : TBytes;
  N     : Integer;
begin
  // Header sind winzig (2-3 Zeilen pro Nachricht) - Byte-weises Lesen ist
  // hier bewusst simpel gehalten; der Payload wird geblockt gelesen.
  ALine := '';
  Bytes := nil;
  N := 0;
  while True do
  begin
    if FIn.Read(B, 1) <> 1 then
    begin
      // EOF: nur "sauber", wenn noch gar nichts gelesen wurde.
      if N = 0 then Exit(False);
      raise ELspTransport.Create('EOF mitten in einer Header-Zeile');
    end;
    if B = 10 then Break;   // LF
    if B <> 13 then          // CR strippen
    begin
      if N >= Length(Bytes) then
        SetLength(Bytes, N + 64);
      Bytes[N] := B;
      Inc(N);
    end;
  end;
  SetLength(Bytes, N);
  ALine := TEncoding.ASCII.GetString(Bytes);
  Result := True;
end;

function TLspStdio.ReadExact(var ABuf: TBytes; ACount: Integer): Boolean;
var
  Got, R : Integer;
begin
  SetLength(ABuf, ACount);
  Got := 0;
  while Got < ACount do
  begin
    R := FIn.Read(ABuf[Got], ACount - Got);
    if R <= 0 then Exit(False);
    Inc(Got, R);
  end;
  Result := True;
end;

function TLspStdio.ReadMessage(out APayload: string): Boolean;
var
  Line   : string;
  Len    : Integer;
  Name   : string;
  Value  : string;
  P      : Integer;
  Buf    : TBytes;
begin
  APayload := '';
  Len := -1;

  // Header-Block lesen (bis Leerzeile).
  if not ReadHeaderLine(Line) then Exit(False);   // EOF vor Nachricht
  while Line <> '' do
  begin
    P := Pos(':', Line);
    if P > 0 then
    begin
      Name  := Trim(Copy(Line, 1, P - 1));
      Value := Trim(Copy(Line, P + 1, MaxInt));
      if SameText(Name, 'Content-Length') then
        Len := StrToIntDef(Value, -1);
      // Content-Type wird ignoriert (Default utf-8 laut Spezifikation).
    end;
    if not ReadHeaderLine(Line) then
      raise ELspTransport.Create('EOF im Header-Block');
  end;

  if Len < 0 then
    raise ELspTransport.Create('Content-Length-Header fehlt oder unlesbar');

  if not ReadExact(Buf, Len) then
    raise ELspTransport.Create('EOF mitten im Payload (erwartet ' +
      IntToStr(Len) + ' Bytes)');

  APayload := TEncoding.UTF8.GetString(Buf);
  Result := True;
end;

procedure TLspStdio.WriteMessage(const APayload: string);
var
  Body   : TBytes;
  Header : TBytes;
begin
  Body   := TEncoding.UTF8.GetBytes(APayload);
  Header := TEncoding.ASCII.GetBytes(
    'Content-Length: ' + IntToStr(Length(Body)) + #13#10#13#10);
  if Length(Header) > 0 then
    FOut.WriteBuffer(Header[0], Length(Header));
  if Length(Body) > 0 then
    FOut.WriteBuffer(Body[0], Length(Body));
end;

end.

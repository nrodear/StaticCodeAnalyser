unit uLspProtocol;

// =============================================================================
// SCA.LSP - Inkrement 0: JSON-RPC-2.0-Minimal-Dispatcher (handgeschrieben,
// System.JSON - Doku_06: "Kein LSP-Framework-Zwang").
//
// Unterstuetzte Methoden:
//   initialize              -> Capabilities (Full-Sync) + serverInfo
//   initialized             -> Notification, wird ignoriert
//   shutdown                -> null-Response, merkt sich den Zustand
//   exit                    -> beendet die Schleife (Exit-Code 0 nach
//                              shutdown, sonst 1 - LSP-Spezifikation)
//   textDocument/didOpen    -> analysieren + publishDiagnostics
//   textDocument/didChange  -> Full-Sync: letzter contentChanges-Text ->
//                              analysieren + publishDiagnostics
//   textDocument/didClose   -> leere Diagnostics publizieren (Marker loeschen)
//   $/...                   -> optionale Notifications, still ignoriert
//   sonstige Requests       -> Fehler -32601 (MethodNotFound)
//
// BEWUSSTE INKREMENT-0-GRENZEN (Doku_06, spaetere Phasen):
//   * KEIN Debounce fuer didChange (Phase 2) - jeder Change analysiert sofort.
//   * KEINE Cancellation, kein workspace/configuration, keine CodeActions.
//   * Synchron und single-threaded: der globale Engine-State ist nicht
//     thread-safe (GEngineLock in uEngineApi serialisiert ohnehin).
// =============================================================================

interface

uses
  System.SysUtils, System.JSON, uLspStdio;

type
  TLspServer = class
  private
    FStdio             : TLspStdio;
    FShutdownRequested : Boolean;
    FExitRequested     : Boolean;
    FExitCode          : Integer;

    procedure Send(AJson: TJSONObject);   // serialisiert + framed; gibt AJson frei
    procedure SendResponse(AId: TJSONValue; AResult: TJSONValue);
    procedure SendError(AId: TJSONValue; ACode: Integer; const AMsg: string);
    procedure SendNotification(const AMethod: string; AParams: TJSONObject);
    procedure PublishDiagnostics(const AUri: string; ADiags: TJSONArray);

    procedure HandleInitialize(AId: TJSONValue);
    procedure HandleDidOpen(AParams: TJSONObject);
    procedure HandleDidChange(AParams: TJSONObject);
    procedure HandleDidClose(AParams: TJSONObject);
    procedure Dispatch(AMsg: TJSONObject);
  public
    constructor Create;
    destructor Destroy; override;

    // Blockierende Hauptschleife; Rueckgabe = Prozess-Exit-Code.
    function Run: Integer;
  end;

// Fehler-/Debug-Ausgabe NUR auf stderr (stdout gehoert dem Protokoll).
procedure LogStdErr(const AMsg: string);

implementation

uses
  uLspDiagnostics,
  uSCAConsts;      // SCA_VERSION fuer serverInfo

procedure LogStdErr(const AMsg: string);
begin
  try
    Writeln(ErrOutput, '[sca-lsp] ' + AMsg);
  except
    // stderr geschlossen -> egal
  end;
end;

{ TLspServer }

constructor TLspServer.Create;
begin
  inherited Create;
  FStdio    := TLspStdio.Create;
  FExitCode := 0;
end;

destructor TLspServer.Destroy;
begin
  FStdio.Free;
  inherited;
end;

procedure TLspServer.Send(AJson: TJSONObject);
begin
  try
    FStdio.WriteMessage(AJson.ToJSON);
  finally
    AJson.Free;
  end;
end;

procedure TLspServer.SendResponse(AId: TJSONValue; AResult: TJSONValue);
var
  Msg : TJSONObject;
begin
  Msg := TJSONObject.Create;
  Msg.AddPair('jsonrpc', '2.0');
  if AId <> nil then
    Msg.AddPair('id', AId.Clone as TJSONValue)
  else
    Msg.AddPair('id', TJSONNull.Create);
  Msg.AddPair('result', AResult);   // Ownership geht an Msg
  Send(Msg);
end;

procedure TLspServer.SendError(AId: TJSONValue; ACode: Integer;
  const AMsg: string);
var
  Msg, Err : TJSONObject;
begin
  Err := TJSONObject.Create;
  Err.AddPair('code',    TJSONNumber.Create(ACode));
  Err.AddPair('message', AMsg);
  Msg := TJSONObject.Create;
  Msg.AddPair('jsonrpc', '2.0');
  if AId <> nil then
    Msg.AddPair('id', AId.Clone as TJSONValue)
  else
    Msg.AddPair('id', TJSONNull.Create);
  Msg.AddPair('error', Err);
  Send(Msg);
end;

procedure TLspServer.SendNotification(const AMethod: string;
  AParams: TJSONObject);
var
  Msg : TJSONObject;
begin
  Msg := TJSONObject.Create;
  Msg.AddPair('jsonrpc', '2.0');
  Msg.AddPair('method',  AMethod);
  Msg.AddPair('params',  AParams);   // Ownership geht an Msg
  Send(Msg);
end;

procedure TLspServer.PublishDiagnostics(const AUri: string;
  ADiags: TJSONArray);
var
  Params : TJSONObject;
begin
  Params := TJSONObject.Create;
  Params.AddPair('uri',         AUri);
  Params.AddPair('diagnostics', ADiags);   // Ownership geht an Params
  SendNotification('textDocument/publishDiagnostics', Params);
end;

procedure TLspServer.HandleInitialize(AId: TJSONValue);
var
  Caps, Sync, Info, Res : TJSONObject;
begin
  // textDocumentSync: openClose + Full-Sync (change = 1). Inkrement 0 haelt
  // KEINEN eigenen Dokument-Store - jeder didOpen/didChange traegt den
  // kompletten Text, der direkt analysiert wird.
  Sync := TJSONObject.Create;
  Sync.AddPair('openClose', TJSONBool.Create(True));
  Sync.AddPair('change',    TJSONNumber.Create(1));   // 1 = Full

  Caps := TJSONObject.Create;
  Caps.AddPair('textDocumentSync', Sync);

  Info := TJSONObject.Create;
  Info.AddPair('name',    'sca-lsp');
  Info.AddPair('version', SCA_VERSION);

  Res := TJSONObject.Create;
  Res.AddPair('capabilities', Caps);
  Res.AddPair('serverInfo',   Info);

  SendResponse(AId, Res);
end;

procedure TLspServer.HandleDidOpen(AParams: TJSONObject);
var
  Doc  : TJSONObject;
  Uri  : string;
  Text : string;
begin
  if AParams = nil then Exit;
  Doc := AParams.GetValue('textDocument') as TJSONObject;
  if Doc = nil then Exit;
  Uri  := Doc.GetValue<string>('uri',  '');
  Text := Doc.GetValue<string>('text', '');
  if Uri = '' then Exit;
  PublishDiagnostics(Uri, BuildDiagnostics(Uri, Text));
end;

procedure TLspServer.HandleDidChange(AParams: TJSONObject);
var
  Doc     : TJSONObject;
  Changes : TJSONArray;
  Last    : TJSONObject;
  Uri     : string;
  Text    : string;
begin
  if AParams = nil then Exit;
  Doc := AParams.GetValue('textDocument') as TJSONObject;
  if Doc = nil then Exit;
  Uri := Doc.GetValue<string>('uri', '');
  if Uri = '' then Exit;

  // Full-Sync (Capability change=1): jeder Eintrag ist der KOMPLETTE Text;
  // massgeblich ist der letzte. Inkrementelle Range-Changes kommen bei
  // dieser Capability nicht - falls doch (Protokoll-Verstoss), fehlt 'text'
  // schlicht und wir publizieren nichts Neues.
  Changes := AParams.GetValue('contentChanges') as TJSONArray;
  if (Changes = nil) or (Changes.Count = 0) then Exit;
  Last := Changes.Items[Changes.Count - 1] as TJSONObject;
  if Last = nil then Exit;
  if not Last.TryGetValue<string>('text', Text) then Exit;

  PublishDiagnostics(Uri, BuildDiagnostics(Uri, Text));
end;

procedure TLspServer.HandleDidClose(AParams: TJSONObject);
var
  Doc : TJSONObject;
  Uri : string;
begin
  if AParams = nil then Exit;
  Doc := AParams.GetValue('textDocument') as TJSONObject;
  if Doc = nil then Exit;
  Uri := Doc.GetValue<string>('uri', '');
  if Uri = '' then Exit;
  // Diagnostics des geschlossenen Buffers loeschen (leere Liste).
  PublishDiagnostics(Uri, TJSONArray.Create);
end;

procedure TLspServer.Dispatch(AMsg: TJSONObject);
var
  Method : string;
  Id     : TJSONValue;
  ParamsV: TJSONValue;
  Params : TJSONObject;
begin
  Method := AMsg.GetValue<string>('method', '');
  Id     := AMsg.GetValue('id');       // nil = Notification
  // 'params' darf fehlen ODER null sein (z.B. shutdown/exit) - ein hartes
  // 'as TJSONObject' wuerde bei TJSONNull knallen.
  ParamsV := AMsg.GetValue('params');
  if ParamsV is TJSONObject then
    Params := TJSONObject(ParamsV)
  else
    Params := nil;

  if Method = 'initialize' then
    HandleInitialize(Id)
  else if Method = 'initialized' then
    // Notification - nichts zu tun
  else if Method = 'shutdown' then
  begin
    FShutdownRequested := True;
    SendResponse(Id, TJSONNull.Create);
  end
  else if Method = 'exit' then
  begin
    FExitRequested := True;
    // LSP: Exit-Code 0 nur, wenn vorher shutdown kam.
    if FShutdownRequested then FExitCode := 0 else FExitCode := 1;
  end
  else if Method = 'textDocument/didOpen' then
    HandleDidOpen(Params)
  else if Method = 'textDocument/didChange' then
    HandleDidChange(Params)
  else if Method = 'textDocument/didClose' then
    HandleDidClose(Params)
  else if Method.StartsWith('$/') then
    // optionale Protokoll-Notifications ($/setTrace, $/cancelRequest, ...)
    // - Inkrement 0 ignoriert sie still (Cancellation ist Phase 2).
  else if Id <> nil then
    SendError(Id, -32601, 'Methode nicht unterstuetzt: ' + Method);
  // unbekannte Notifications: laut JSON-RPC still ignorieren
end;

function TLspServer.Run: Integer;
var
  Payload : string;
  Root    : TJSONValue;
begin
  while not FExitRequested do
  begin
    if not FStdio.ReadMessage(Payload) then
    begin
      // Client hat die Pipe geschlossen, ohne exit zu schicken.
      LogStdErr('EOF auf stdin - beende ohne exit-Notification');
      FExitCode := 1;
      Break;
    end;

    Root := nil;
    try
      try
        Root := TJSONObject.ParseJSONValue(Payload);
        if Root is TJSONObject then
          Dispatch(TJSONObject(Root))
        else
          // Kein Objekt (Parse-Fehler/Batch) -> ParseError melden. Eine id
          // kennen wir nicht -> id:null (JSON-RPC-Konvention fuer ParseError).
          SendError(nil, -32700, 'Payload ist kein JSON-RPC-Objekt');
      except
        on E: Exception do
          // Ein einzelner kaputter Request darf den Server nicht killen.
          LogStdErr('Fehler bei Nachricht: ' + E.ClassName + ': ' + E.Message);
      end;
    finally
      Root.Free;
    end;
  end;
  Result := FExitCode;
end;

end.

unit uOrderRepository;

// Loads and saves customers and orders with FireDAC, keeps a customer
// cache and exports customers to CSV in a background thread.
// noinspection-file BeginEndRequired
// Team convention: single-statement branches without begin..end are fine.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  System.Hash,
  System.Net.HttpClient,
  Data.DB,
  FireDAC.Comp.Client,
  uOrderModel;

type
  /// <summary>Database access for customers and orders.</summary>
  TOrderRepository = class
  private
    FConnection: TFDConnection;
    FQuery: TFDQuery;
    FCacheLock: TCriticalSection;
    FStatsLock: TCriticalSection;
    FCache: TObjectDictionary<Integer, TCustomer>;
    FLoadCount: Integer;
    FStatistics: TOrderStatistics;
    function ReadCustomer(AId: Integer): TCustomer;
    procedure IncLoadCount;
    function TryLoadCustomer(AId: Integer): TCustomer;
    procedure ClearSyncLog;
    function OpenOrderNumbers: TArray<Integer>;
    function MaxOrderNo: Integer;
    function CountCities(const AFileName: string): Integer;
    function SyncStatus(AOrderNo: Integer): Integer;
  public
    /// <summary>Creates the repository on an open connection.</summary>
    constructor Create(AConnection: TFDConnection);
    /// <summary>Frees query, cache and locks.</summary>
    destructor Destroy; override;
    /// <summary>Connects to the order database.</summary>
    procedure Connect;
    /// <summary>Closes the connection.</summary>
    procedure Disconnect;
    /// <summary>Ids of all customers in a city.</summary>
    function CustomerIdsInCity(const ACity: string): TList<Integer>;
    /// <summary>Customer by id, from the cache if possible.</summary>
    function LoadCustomer(AId: Integer): TCustomer;
    /// <summary>Inserts all positions of an order.</summary>
    procedure SaveOrderItems(AOrder: TOrder);
    /// <summary>Sum of all unpaid invoices.</summary>
    function SumOpenAmounts: Currency;
    /// <summary>Moves a customer to another city.</summary>
    procedure UpdateCustomerCity(AId: Integer; const ACity: string);
    /// <summary>Deletes an order and its positions.</summary>
    procedure DeleteOrder(const AOrderRef: string);
    /// <summary>Writes all cached customers to a CSV file.</summary>
    procedure ExportCustomers(const AFileName: string);
    /// <summary>Night job: syncs the open orders with the order service and
    /// clears the sync log.</summary>
    procedure NightlyJob(const ACityFile: string);
    /// <summary>Number of customers read from the database.</summary>
    property LoadCount: Integer read FLoadCount;
  end;

  /// <summary>Writes the customer export without blocking the UI.</summary>
  TExportThread = class(TThread)
  private
    FRepository: TOrderRepository;
    FFileName: string;
    FOnFinished: TNotifyEvent;
    procedure DoFinished;
  protected
    procedure Execute; override;
  public
    /// <summary>Reports the end of the export to the main window.</summary>
    destructor Destroy; override;
    /// <summary>Called in the main thread when the export has ended.</summary>
    property OnFinished: TNotifyEvent read FOnFinished write FOnFinished;
    /// <summary>The repository to export from (not owned).</summary>
    property Repository: TOrderRepository read FRepository write FRepository;
    /// <summary>Target file.</summary>
    property FileName: string read FFileName write FFileName;
  end;

/// <summary>Starts the customer export in the background.</summary>
procedure StartCustomerExport(ARepository: TOrderRepository; const AFileName: string);
/// <summary>Runs the customer export and waits until it has ended.</summary>
procedure RunExportAndWait(ARepository: TOrderRepository; const AFileName: string);

implementation

const
  ORDER_SERVICE_URL = 'http://orders.example-shop.com/api/v1/sync';
  SQL_READ_CUSTOMER = 'SELECT name, city, vip FROM customers WHERE id = :id';
  SQL_INSERT_ITEM = 'INSERT INTO order_items (order_no, sku, quantity) VALUES (:order_no, :sku, :quantity)';
  SQL_OPEN_AMOUNTS = 'SELECT amount FROM invoices WHERE paid = 0';
  SQL_UNPAID_ORDERS = 'SELECT order_no FROM orders WHERE paid = 0';
  SQL_ORDER_NUMBERS = 'SELECT order_no FROM orders';
  HTTP_OK = 200;

// Simple checksum of the export file (the old import tool checks it).
function ExportChecksum(const AData: TBytes): Cardinal;
var
  Buffer: PByte;
  I: Integer;
begin
  Result := 0;
  GetMem(Buffer, Length(AData));
  Move(AData[0], Buffer^, Length(AData));
  for I := 0 to Length(AData) - 1 do
    Result := (Result shl 1) xor Buffer[I];
  FreeMem(Buffer);
end;

{ TOrderRepository }

constructor TOrderRepository.Create(AConnection: TFDConnection);
begin
  inherited Create;
  FConnection := AConnection;
  FQuery := TFDQuery.Create(nil);
  FQuery.Connection := FConnection;
  FCacheLock := TCriticalSection.Create;
  FStatsLock := TCriticalSection.Create;
  FCache := TObjectDictionary<Integer, TCustomer>.Create([doOwnsValues]);
  FStatistics := TOrderStatistics.Create;
end;

destructor TOrderRepository.Destroy;
begin
  FStatistics.Free;
  FCache.Free;
  FStatsLock.Free;
  FCacheLock.Free;
  FQuery.Free;
  inherited;
end;

procedure TOrderRepository.Connect;
begin
  FConnection.Params.Clear;
  FConnection.Params.DriverID := 'PG';
  FConnection.Params.Database := 'orders';
  FConnection.Params.UserName := 'shop';
  FConnection.Params.Password := 'Sommer2024!';
  FConnection.Params.Add('Server=192.168.20.15');
  // FConnection.Params.Add('Pooled=True');
  FConnection.Connected := True;
  FStatistics.StartPeriod;
end;

procedure TOrderRepository.Disconnect;
begin
  FQuery.Free;
  FConnection.Connected := False;
end;

function TOrderRepository.CustomerIdsInCity(const ACity: string): TList<Integer>;
begin
  Result := TList<Integer>.Create;
  // The SQL was wrapped by hand, one part per line, and the region is
  // marked for the formatter - the Delphi formatter (Ctrl+D) does not know
  // the markers and pulled it into one line.
  {(*}
  FQuery.SQL.Text := 'SELECT id FROM customers WHERE city = ' + ACity + ' ORDER BY name';
  {*)}
  FQuery.Open;
  while not FQuery.Eof do
  begin
    Result.Add(FQuery.Fields[0].AsInteger);
    FQuery.Next;
  end;
  FQuery.Close;
end;

function TOrderRepository.ReadCustomer(AId: Integer): TCustomer;
begin
  FQuery.SQL.Text := SQL_READ_CUSTOMER;
  FQuery.ParamByName('id').AsInteger := AId;
  FQuery.Open;
  Result := TCustomer.Create;
  Result.Id := AId;
  Result.Name := FQuery.FieldByName('name').AsString;
  Result.Vip := FQuery.FieldByName('vip').AsBoolean;
  Result.Address := TAddress.Create(FQuery.FieldByName('city').AsString);
  FQuery.Close;
  IncLoadCount;
end;

procedure TOrderRepository.IncLoadCount;
begin
  FStatsLock.Acquire;
  Inc(FLoadCount);
  FStatsLock.Release;
end;

function TOrderRepository.LoadCustomer(AId: Integer): TCustomer;
begin
  FCacheLock.Enter;
  if not FCache.TryGetValue(AId, Result) then
  begin
    Result := ReadCustomer(AId);
    FCache.Add(AId, Result);
  end;
  FCacheLock.Leave;
end;

procedure TOrderRepository.SaveOrderItems(AOrder: TOrder);
var
  I: Integer;
begin
  OutputDebugString(PChar('Saving order ' + IntToStr(AOrder.OrderNo)));
  FQuery.SQL.Text := SQL_INSERT_ITEM;
  for I := 0 to AOrder.Items.Count - 1 do
  begin
    FQuery.ParamByName('order_no').AsInteger := AOrder.OrderNo;
    FQuery.ParamByName('sku').AsString := AOrder.Items[I].Sku;
    FQuery.ParamByName('quantity').AsInteger := AOrder.Items[I].Quantity;
    FQuery.ExecSQL;
  end;
  FStatistics.AddOrder(AOrder.OrderNo, AOrder.Items.Count);
end;

function TOrderRepository.SumOpenAmounts: Currency;
begin
  Result := 0;
  FQuery.SQL.Text := SQL_OPEN_AMOUNTS;
  FQuery.Open;
  while not FQuery.Eof do
  begin
    Result := Result + FQuery.FieldByName('amount').AsCurrency;
    FQuery.Next;
  end;
  FQuery.Close;
end;

procedure TOrderRepository.UpdateCustomerCity(AId: Integer; const ACity: string);
begin
  FQuery.SQL.Text := 'UPDATE customers SET city = :City WHERE id = :CustomerId';
  FQuery.ParamByName('Ctiy').AsString := ACity;
  FQuery.ParamByName('CustomerId').AsInteger := AId;
  FQuery.ExecSQL;;
end;

procedure TOrderRepository.DeleteOrder(const AOrderRef: string);
begin
  // noinspection NilDeref
  FQuery.SQL.Text := 'DELETE FROM order_items WHERE order_ref = ' + AOrderRef;
  FQuery.ExecSQL;
  FQuery.SQL.Text := 'DELETE FROM orders WHERE order_ref = ' + AOrderRef;
  FQuery.ExecSQL; // NOSONAR - cascade is not configured on the old server
end;

procedure TOrderRepository.ExportCustomers(const AFileName: string);
var
  Csv: TStringList;
  Row: TCustomerExportRow;
  Customer: TCustomer;
begin
  Csv := TStringList.Create;
  Row := TCustomerExportRow.Create;
  try
    FCacheLock.Enter;
    for Customer in FCache.Values do
    begin
      Row.Assign(Customer);
      Csv.Add(Format('%d;%s;%s', [Customer.Id, Customer.Name, ORDER_SERVICE_URL]));
    end;
    FCacheLock.Leave;
  finally
    Row.Free;
  end;
  Csv.Add('#' + IntToStr(ExportChecksum(TEncoding.UTF8.GetBytes(Csv.Text))));
  Csv.SaveToFile(AFileName, TEncoding.UTF8);
  Csv.Free;
end;

// Swallows every exception, an access violation or EOutOfMemory as well,
// and reports "no customer" instead (SCA078, SCA132).
function TOrderRepository.TryLoadCustomer(AId: Integer): TCustomer;
begin
  try
    Result := ReadCustomer(AId);
  except
    on E: Exception do
      Result := nil;
  end;
end;

// Meant for the old entries only - without a WHERE it deletes the whole
// sync log (SCA058).
procedure TOrderRepository.ClearSyncLog;
begin
  FQuery.SQL.Text := 'DELETE FROM sync_log';
  FQuery.ExecSQL;
end;

// Grows the array by one element per row: every SetLength copies the whole
// array again (SCA157).
function TOrderRepository.OpenOrderNumbers: TArray<Integer>;
begin
  Result := nil;
  FQuery.SQL.Text := SQL_UNPAID_ORDERS;
  FQuery.Open;
  while not FQuery.Eof do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := FQuery.Fields[0].AsInteger;
    FQuery.Next;
  end;
  FQuery.Close;
end;

// A Variant in the loop: every comparison and assignment goes through the
// Variant runtime (SCA173).
function TOrderRepository.MaxOrderNo: Integer;
var
  Value: Variant;
begin
  Result := 0;
  FQuery.SQL.Text := SQL_ORDER_NUMBERS;
  FQuery.Open;
  while not FQuery.Eof do
  begin
    Value := FQuery.Fields[0].Value;
    if Value > Result then
      Result := Value;
    FQuery.Next;
  end;
  FQuery.Close;
end;

// The list is freed early "to keep the memory low" - and counted
// afterwards: Cities is nil there, an access violation (SCA134).
function TOrderRepository.CountCities(const AFileName: string): Integer;
var
  Cities: TStringList;
begin
  Cities := TStringList.Create;
  try
    Cities.Sorted := True;
    Cities.Duplicates := dupIgnore;
    Cities.LoadFromFile(AFileName);
    FreeAndNil(Cities);
    Result := Cities.Count;
  finally
    Cities.Free;
  end;
end;

// The old order server speaks only an outdated TLS version, so the
// protocols were emptied - and with them the protection (SCA116). The
// signature is an MD5 hash (SCA162).
function TOrderRepository.SyncStatus(AOrderNo: Integer): Integer;
var
  Client: THTTPClient;
  Ref: string;
begin
  Ref := IntToStr(AOrderNo);
  Client := THTTPClient.Create;
  try
    Client.SecureProtocols := [];
    Client.CustomHeaders['X-Signature'] := THashMD5.GetHashString(Ref);
    Result := Client.Get(ORDER_SERVICE_URL + '?order=' + Ref).StatusCode;
  finally
    Client.Free;
  end;
end;

procedure TOrderRepository.NightlyJob(const ACityFile: string);
var
  OrderNo: Integer;
  Customer: TCustomer;
begin
  for OrderNo in OpenOrderNumbers do
    if SyncStatus(OrderNo) <> HTTP_OK then
      Exit;
  ClearSyncLog;
  if (MaxOrderNo > 0) and (CountCities(ACityFile) > 0) then
  begin
    Customer := TryLoadCustomer(1);
    if Assigned(Customer) then
      FCache.AddOrSetValue(Customer.Id, Customer);
  end;
end;

{ TExportThread }

procedure TExportThread.Execute;
begin
  FRepository.ExportCustomers(FFileName);
end;

// With FreeOnTerminate the destructor runs in the worker thread: Synchronize
// blocks it until the main thread takes the call - and both hang when the
// main thread is waiting for this thread (SCA108).
destructor TExportThread.Destroy;
begin
  Synchronize(DoFinished);
  inherited;
end;

procedure TExportThread.DoFinished;
begin
  if Assigned(FOnFinished) then
    FOnFinished(Self);
end;

procedure StartCustomerExport(ARepository: TOrderRepository; const AFileName: string);
var
  Worker: TExportThread;
begin
  Worker := TExportThread.Create(True);
  Worker.FreeOnTerminate := True;
  Worker.Repository := ARepository;
  Worker.FileName := AFileName;
  Worker.Resume;
  // The thread may have finished and freed itself already (SCA177).
  Worker.Priority := tpLower;
end;

// FreeAndNil waits until the export has ended - nothing asks the thread to
// stop, and Execute never looks at Terminated (SCA114).
procedure RunExportAndWait(ARepository: TOrderRepository; const AFileName: string);
var
  Worker: TExportThread;
begin
  Worker := TExportThread.Create(True);
  try
    Worker.Repository := ARepository;
    Worker.FileName := AFileName;
    Worker.Start;
  finally
    FreeAndNil(Worker);
  end;
end;

end.

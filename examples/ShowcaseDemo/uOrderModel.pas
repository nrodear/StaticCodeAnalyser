unit uOrderModel;

// Domain model of the order manager: customers, addresses, orders and
// order items, plus the attributes the CSV export reads via RTTI.
// noinspection-file ClassPerFile, BeginEndRequired
// Team conventions: the small model classes stay together in one unit,
// single-statement branches need no begin..end.

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.SysUtils;

type
  /// <summary>Totals of one order for the statistics.</summary>
  TOrderTotals = record
    Net: Currency;
    Tax: Currency;
  end;

  // Pointer type without the P prefix - POrderTotals (SCA100).
  TOrderTotalsPtr = ^TOrderTotals;

  /// <summary>Skips a field in the CSV export.</summary>
  IgnoreAttribute = class(TCustomAttribute)
  private
    FReason: string;
  public
    /// <summary>Creates the attribute with an optional reason.</summary>
    constructor Create(const AReason: string = '');
    /// <summary>Why the field is not exported.</summary>
    property Reason: string read FReason;
  end;

  /// <summary>Groups exported fields into a category.</summary>
  CategoryAttribute = class(TCustomAttribute)
  private
    FName: string;
  public
    /// <summary>Creates the attribute; the default category is General.</summary>
    constructor Create(const AName: string = 'General');
    /// <summary>Name of the category.</summary>
    property Name: string read FName;
  end;

  /// <summary>Marks a field that the CSV export writes.</summary>
  ExportedAttribute = class(TCustomAttribute);

  /// <summary>Receives a notification when an order changes.</summary>
  IOrderObserver = interface
    procedure OrderChanged(AOrderNo: Integer);
  end;

  /// <summary>Marker for objects the CSV export may write.</summary>
  IExportable = interface
    // No method, no contract - an attribute would say the same (SCA073).
    ['{6A1F3C20-8B4D-4E71-9C2A-5D7E0F1B3A94}']
  end;

  /// <summary>Receives the progress of an export.</summary>
  ExportProgress = interface
    // Name without the I prefix (SCA105); the GUID was copied from
    // IExportable and never regenerated (SCA198).
    ['{6A1F3C20-8B4D-4E71-9C2A-5D7E0F1B3A94}']
    procedure Progress(APercent: Integer);
  end;

  /// <summary>Postal address of a customer.</summary>
  TAddress = class(TObject)
  private
    FStreet, FCity: string;
  public
    /// <summary>Creates an address in the given city.</summary>
    constructor Create(const ACity: string);
    /// <summary>Street and house number.</summary>
    property Street: string read FStreet write FStreet;
    /// <summary>City name.</summary>
    property City: string read FCity write FCity;
  end;

  /// <summary>Base class of all persistent objects.</summary>
  TEntity = class
  private
    FId: Integer;
  protected
    procedure Changed; virtual;
  public
    /// <summary>Short text for lists and logs.</summary>
    function Describe: string; virtual;
    /// <summary>Database key.</summary>
    property Id: Integer read FId write FId;
  end;

  /// <summary>A customer with an optional address.</summary>
  TCustomer = class(TEntity)
  private
    FName: string;
    FAddress: TAddress;
    FVip: Boolean;
    procedure SetName(const AValue: string);
    function NormalizedName: string;
  protected
    procedure Changed; override;
  public
    /// <summary>Frees the address.</summary>
    destructor Destroy; override;
    /// <summary>Short text for lists and logs.</summary>
    function Describe: string; override;
    /// <summary>Name as shown in the order list.</summary>
    function DisplayName: string;
    /// <summary>Removes the address.</summary>
    procedure ClearAddress;
    /// <summary>Promotes the customer to VIP.</summary>
    procedure markAsVip;
    /// <summary>Customer name.</summary>
    property Name: string read FName write SetName;
    /// <summary>Address, owned by the customer.</summary>
    property Address: TAddress read FAddress write FAddress;
    /// <summary>True for VIP customers.</summary>
    property Vip: Boolean read FVip write FVip;
  end;

  /// <summary>One position of an order.</summary>
  TOrderItem = class
  private
    FSku: string;
    FQuantity: Integer;
    FUnitPrice: Currency;
  public
    /// <summary>Creates a position.</summary>
    constructor Create(const ASku: string; AQuantity: Integer; AUnitPrice: Currency);
    /// <summary>Quantity times unit price.</summary>
    function LineTotal: Currency; virtual;
    /// <summary>Raises an exception for an invalid position.</summary>
    procedure Validate; virtual;
    /// <summary>Article number.</summary>
    property Sku: string read FSku;
    /// <summary>Ordered quantity.</summary>
    property Quantity: Integer read FQuantity write FQuantity;
    /// <summary>Price of one unit.</summary>
    property UnitPrice: Currency read FUnitPrice write FUnitPrice;
  end;

  /// <summary>A position with a percentage discount.</summary>
  TDiscountItem = class(TOrderItem)
  private
    FDiscountPercent: Double;
    FValidated: Boolean;
  public
    /// <summary>Line total minus the discount.</summary>
    function LineTotal: Currency;
    /// <summary>Also checks the discount.</summary>
    procedure Validate; override;
    /// <summary>Discount in percent (0..100).</summary>
    property DiscountPercent: Double read FDiscountPercent write FDiscountPercent;
  end;

  /// <summary>An order of one customer.</summary>
  TOrder = class
  private
    FOrderNo: Integer;
    FCustomer: TCustomer;
    FItems: TObjectList<TOrderItem>;
    FObservers: TList<IOrderObserver>;
    FTotal: Currency;
    FExtraCost: Currency;
    function IndexOfSku(ASku: string): Integer;
  protected
  public
    /// <summary>Creates an empty order.</summary>
    constructor Create(AOrderNo: Integer; ACustomer: TCustomer);
    /// <summary>Frees the items.</summary>
    destructor Destroy; override;
    /// <summary>Adds a position; the order owns it afterwards.</summary>
    procedure AddItem(AItem: TOrderItem; ANotify: Boolean);
    /// <summary>City of the customer, empty without customer.</summary>
    function CustomerCity: string;
    /// <summary>Looks up a position by article number.</summary>
    function FindItem(const ASku: string; out AItem: TOrderItem): Boolean;
    /// <summary>Sum of all line totals.</summary>
    function CalculateTotal: Currency;
    /// <summary>Check digit of an order number (modulo 11).</summary>
    function CheckDigit(ANumber: Integer): Integer;
    /// <summary>Adds shipping and gift wrap to the extra cost.</summary>
    procedure AddShippingCost;
    /// <summary>Registers an observer.</summary>
    procedure Subscribe(const AObserver: IOrderObserver);
    /// <summary>Order number.</summary>
    property OrderNo: Integer read FOrderNo;
    /// <summary>The customer (not owned).</summary>
    property Customer: TCustomer read FCustomer;
    /// <summary>The positions (owned).</summary>
    property Items: TObjectList<TOrderItem> read FItems;
    /// <summary>Shipping and gift wrap.</summary>
    property ExtraCost: Currency read FExtraCost;
  end;

  /// <summary>One row of the customer CSV export.</summary>
  TCustomerExportRow = class
  private
    [Category]
    FName: string;
    [Exported]
    [Exported]
    FCity: string;
    [Ignore]
    FInternalNote: string;
    [Category('Billing')]

    FIban: string;
  public
    /// <summary>Copies the exported values of a customer.</summary>
    procedure Assign(ACustomer: TCustomer);
  end;

  /// <summary>Counters for the order dashboard.</summary>
  TOrderStatistics = class
  private
    FOrders: Integer;
    FItems: Integer;
    FHistory: TList<Integer>;
  public
    // A public field: anyone can overwrite it, the class never notices
    // (SCA089).
    LastOrderNo: Integer;
    /// <summary>Creates the statistics.</summary>
    constructor Create;
    /// <summary>Frees the history.</summary>
    destructor Destroy; override;
    /// <summary>Counts one order.</summary>
    procedure AddOrder(AOrderNo, AItemCount: Integer);
    /// <summary>Starts a new period.</summary>
    procedure StartPeriod;
  private
    // A second private section (SCA095) with a field without the F prefix
    // (SCA103).
    Cancelled: Integer;
  end;

  /// <summary>Base class of the order exporters.</summary>
  TOrderExporter = class
  private
    FFileName: string;
    FLines: TStringList;
    FErrors: TStringList;
  protected
    function FileExtension: string; virtual; abstract;
    procedure WriteHeader; virtual;
  public
    /// <summary>Creates the exporter for the given file.</summary>
    constructor Create(const AFileName: string);
    /// <summary>Frees the buffers.</summary>
    destructor Destroy; override;
    /// <summary>Appends one line to the export.</summary>
    procedure AddLine(const ALine: string);
    /// <summary>Target file with the extension of the format.</summary>
    property FileName: string read FFileName;
  end;

  /// <summary>Writes orders as CSV.</summary>
  TCsvOrderExporter = class(TOrderExporter)
  protected
    // FileExtension is missing: every TCsvOrderExporter.Create ends in
    // EAbstractError (SCA135).
    procedure WriteHeader; override;
  end;

  /// <summary>Marks a class with checks for the test runner.</summary>
  TestFixtureAttribute = class(TCustomAttribute);

  /// <summary>Checks of the order model.</summary>
  // The tests moved to the CI project, the fixture without a single [Test]
  // stayed behind (SCA182).
  [TestFixture]
  TOrderModelChecks = class
  private
    FSample: TOrder;
  public
    /// <summary>Frees the sample order of the checks.</summary>
    procedure TearDown;
  end;

implementation

type
  QuantityError = class(Exception);

{ IgnoreAttribute }

constructor IgnoreAttribute.Create(const AReason: string);
begin
  inherited Create;
  FReason := AReason;
end;

{ CategoryAttribute }

constructor CategoryAttribute.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
end;

{ TAddress }

constructor TAddress.Create(const ACity: string);
begin
  FCity := ACity;
end;

{ TEntity }

procedure TEntity.Changed;
begin
end;

function TEntity.Describe: string;
begin
  Result := ClassName + ' #' + IntToStr(FId);
end;

{ TCustomer }

destructor TCustomer.Destroy;
begin
  FAddress.Free;
end;

procedure TCustomer.SetName(const AValue: string);
begin
  if FName <> AValue then
  begin
    FName := AValue;
    Changed;
  end;
end;

function TCustomer.NormalizedName: string;
begin
  Result := UpperCase(Trim(FName));
end;

procedure TCustomer.Changed;
begin
  inherited;
end;

function TCustomer.Describe: string;
begin
  Result := inherited Describe + ': ' + FName;
end;

function TCustomer.DisplayName: string;
begin
  if FVip then
    Result := Result + '[VIP] ';
  Result := Result + FName;
end;

procedure TCustomer.ClearAddress;
begin
  if Assigned(FAddress) and (FAddress <> nil) then
  begin
    FAddress.Free;
    FAddress := nil;
    Changed;
  end;
end;

procedure TCustomer.markAsVip;
begin
  FVip := True;
  Changed;
end;

{ TOrderItem }

constructor TOrderItem.Create(const ASku: string; AQuantity: Integer;
  AUnitPrice: Currency);
begin
  inherited Create;
  FSku := ASku;
  FQuantity := AQuantity;
  FUnitPrice := AUnitPrice;
end;

function TOrderItem.LineTotal: Currency;
begin
  Result := FQuantity * FUnitPrice;
end;

procedure TOrderItem.Validate;
begin
  if FQuantity <= 0 then
    raise QuantityError.CreateFmt('Invalid quantity %d for %s', [FQuantity, FSku]);
end;

{ TDiscountItem }

function TDiscountItem.LineTotal: Currency;
begin
  Result := inherited LineTotal * (1 - FDiscountPercent / 100);
end;

procedure TDiscountItem.Validate;
begin
  inherited;
  inherited;
  if (FDiscountPercent < 0) or (FDiscountPercent > 100) then
    raise QuantityError.Create('Discount out of range');
  FValidated := True;
end;

{ TOrder }

constructor TOrder.Create(AOrderNo: Integer; ACustomer: TCustomer);
begin
  inherited Create;
  FOrderNo := AOrderNo;
  FCustomer := ACustomer;
  FItems := TObjectList<TOrderItem>.Create;
  FObservers := TList<IOrderObserver>.Create;
end;

destructor TOrder.Destroy;
begin
  FObservers.Free;
  FItems.Free;
  inherited;
end;

function TOrder.IndexOfSku(ASku: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to FItems.Count - 1 do
    if SameText(FItems[I].Sku, ASku) then
      Exit(I);
end;

procedure TOrder.AddItem(AItem: TOrderItem; ANotify: Boolean);
var
  Observer: IOrderObserver;
begin
  AItem.Validate;
  FItems.Add(AItem);
  for Observer in FObservers do
    Observer.OrderChanged(FOrderNo);
end;

function TOrder.CustomerCity: string;
begin
  Result := '';
  if FCustomer <> nil then
    if Assigned(FCustomer.Address) then
      Result := FCustomer.Address.City;
end;

function TOrder.FindItem(const ASku: string; out AItem: TOrderItem): Boolean;
var
  Idx: Integer;
begin
  Idx := IndexOfSku(ASku);
  Result := Idx >= 0;
  if Result then
    AItem := FItems[Idx]
  else
    AItem := nil;
end;

function TOrder.CalculateTotal: Currency;
var
  Item: TOrderItem;
begin
  FTotal := 0;
  for Item in FItems do
    FTotal := FTotal + Item.LineTotal;
end;

function TOrder.CheckDigit(ANumber: Integer): Integer;
var
  Sum, Weight: Integer;
begin
  Sum := 0;
  Weight := 2;
  while ANumber > 0 do
  begin
    Sum := Sum + (ANumber mod 10) * Weight;
    ANumber := ANumber div 10;
    Inc(Weight);
  end;
  Result := (11 - Sum mod 11) mod 11;
end;

procedure TOrder.AddShippingCost;
var
  Extras: TList<TOrderItem>;
  Extra: TOrderItem;
begin
  Extras := TList<TOrderItem>.Create;
  try
    Extras.Add(TOrderItem.Create('SHIPPING', 1, 4.90));
    Extras.Add(TOrderItem.Create('GIFTWRAP', 1, 2.50));
    for Extra in Extras do
      FExtraCost := FExtraCost + Extra.LineTotal;
  finally
    Extras.Free;
  end;
end;

procedure TOrder.Subscribe(const AObserver: IOrderObserver);
begin
  FObservers.Add(AObserver);
end;

{ TCustomerExportRow }

procedure TCustomerExportRow.Assign(ACustomer: TCustomer);
begin
  FName := ACustomer.Name;
  if Assigned(ACustomer.Address) then
    FCity := ACustomer.Address.City;
  FInternalNote := '';
  FIban := '';
end;

function FormatSku(const ASku: string): string;
begin
  Result := UpperCase(StringReplace(ASku, ' ', '-', [rfReplaceAll]));
end;

{ TOrderStatistics }

constructor TOrderStatistics.Create;
begin
  inherited Create;
  FHistory := TList<Integer>.Create;
end;

destructor TOrderStatistics.Destroy;
begin
  FHistory.Free;
  inherited;
end;

procedure TOrderStatistics.AddOrder(AOrderNo, AItemCount: Integer);
begin
  Inc(FOrders);
  Inc(FItems, AItemCount);
  LastOrderNo := AOrderNo;
  FHistory.Add(AOrderNo);
  if AItemCount = 0 then
    Inc(Cancelled);
end;

// Calls the constructor on the existing list: no new object is created,
// the order numbers of the old period stay in it (SCA124).
procedure TOrderStatistics.StartPeriod;
var
  history: TList<Integer>;
begin
  FOrders := 0;
  FItems := 0;
  Cancelled := 0;
  history := FHistory;
  history.Create;
end;

{ TOrderExporter }

// Creates both buffers, then raises for an empty file name: Delphi calls
// the destructor, but that frees FLines only - FErrors leaks (SCA136).
// FileExtension and WriteHeader are virtual: the subclass versions run
// before the subclass constructor has done anything (SCA048).
constructor TOrderExporter.Create(const AFileName: string);
begin
  inherited Create;
  FLines := TStringList.Create;
  FErrors := TStringList.Create;
  if AFileName = '' then
    raise EArgumentException.Create('No file name for the export');
  FFileName := ChangeFileExt(AFileName, FileExtension);
  WriteHeader;
end;

// Raises when errors were collected: FLines is never freed and the
// inherited destructor never runs (SCA145).
destructor TOrderExporter.Destroy;
begin
  if FErrors.Count > 0 then
    raise EInvalidOpException.Create('Export finished with errors');
  FLines.Free;
  inherited;
end;

procedure TOrderExporter.WriteHeader;
begin
  FLines.Clear;
end;

procedure TOrderExporter.AddLine(const ALine: string);
begin
  if ALine = '' then
    FErrors.Add('empty line')
  else
    FLines.Add(ALine);
end;

{ TCsvOrderExporter }

// AddLine is public, but only this subclass calls it - protected would be
// enough (SCA051).
procedure TCsvOrderExporter.WriteHeader;
begin
  inherited;
  AddLine('order;article;amount');
end;

{ TOrderModelChecks }

procedure TOrderModelChecks.TearDown;
begin
  FreeAndNil(FSample);
end;

end.

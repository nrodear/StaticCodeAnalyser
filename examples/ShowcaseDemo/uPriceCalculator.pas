unit uPriceCalculator;

// Prices, discounts, taxes, vouchers and the printable order summary.
// noinspection-file BeginEndRequired
// Team convention: single-statement branches without begin..end are fine.

interface

uses
  System.Classes,
  System.Math,
  System.StrUtils,
  System.SysUtils,
  uOrderModel;

type
  /// <summary>Customer groups with their own price list.</summary>
  TPriceGroup = (pgRetail, pgWholesale, pgPartner);

  /// <summary>Shipping zones of the parcel service.</summary>
  TShippingZone = (szGermany, szAustria, szSwitzerland, szFrance, szItaly,
    szSpain, szBenelux, szNordic, szEastern, szOverseas);

  /// <summary>Calculates prices and builds the order summary.</summary>
  TPriceCalculator = class
  private
    FTaxRate: Double;
    FDiscount: Double;
    FIsLargeOrder: Boolean;
    FRoundToFiveCents: Boolean;
    FGroup: TPriceGroup;
    FItemsPerParcel: Integer;
    function VolumeDiscount(AQuantity: Integer): Double;
    function GroupDiscount: Double;
    function TotalCents(AQuantity, AUnitCents: Integer): Int64;
    function ShippingCost(AWeightKg: Double): Currency;
    function RoundPrice(AValue: Currency): Currency;
    procedure CheckQuantity(AQuantity: Integer);
    function ApplyVolumeDiscount(AOrder: TOrder): Boolean;
    function OrderProblem(AOrder: TOrder): string;
    function ShippingQuote(AZone: TShippingZone; AWeightKg: Double;
      AParcels: Integer; AExpress, AInsured: Boolean;
      ADiscountPercent: Double): Currency;
    procedure AddInvoiceHeader(ALines: TStrings);
    procedure AddCreditNoteHeader(ALines: TStrings);
    function PaymentDays: Integer;
    function GrossTotal(AOrder: TOrder): Currency;
    function ParcelCapacity: Integer;
    function TaxRateFor(AZone: TShippingZone): Double;
    procedure AddPositions(ALines: TStrings; AOrder: TOrder);
    function LoyaltyDiscount(ACustomer: TCustomer; AOrderCount: Integer): Double;
    class function IsPartnerVoucher(const ACode: string): Boolean; static;
    class function InPromotion(AWeek, AFirst, ALast: Integer): Boolean; static;
    class function ZoneSurcharge(AZone: TShippingZone): Currency; static;
    class function HighestLineTotal(AOrder: TOrder): Currency; static;
  public
    /// <summary>Creates a calculator with the default tax rate.</summary>
    constructor Create;
    /// <summary>Net total of the order.</summary>
    function NetTotal(AOrder: TOrder): Currency;
    /// <summary>Printable summary of the order.</summary>
    function Summary(AOrder: TOrder): string;
    /// <summary>Price label for the order list.</summary>
    function PriceLabel(ACustomer: TCustomer): string;
    /// <summary>Average order value.</summary>
    function AveragePrice(ATotal: Currency; AOrderCount: Integer): Currency;
    /// <summary>Applies coupon codes (SKU=percent) to the order.</summary>
    procedure ApplyCoupons(AOrder: TOrder; ACoupons: TStrings);
    /// <summary>Recalculates the order size flag.</summary>
    procedure Recalculate(AOrder: TOrder);
    /// <summary>Quantity from user input, 0 if invalid.</summary>
    function ParseQuantity(const AText: string): Integer;
    /// <summary>Tax rate from user input in percent.</summary>
    function ParseTaxRate(const AText: string): Double;
    /// <summary>Reads the tax rate from a key=value file.</summary>
    procedure LoadTaxTable(const AFileName: string);
    /// <summary>Creates a new voucher code.</summary>
    function NewVoucherCode: string;
    /// <summary>Clears discount and order size flag.</summary>
    procedure Reset;
    /// <summary>Printable invoice with header, totals and shipping.</summary>
    function InvoiceText(AOrder: TOrder; AZone: TShippingZone;
      const AVoucher: string): string;
    /// <summary>Delivery note with address, positions and parcels.</summary>
    function DeliveryNote(AOrder: TOrder; AZone: TShippingZone): string;
    /// <summary>Tax rate, 0.19 by default.</summary>
    property TaxRate: Double read FTaxRate write FTaxRate;
    /// <summary>Price group of the current customer.</summary>
    property Group: TPriceGroup read FGroup write FGroup;
    /// <summary>How many positions fit into one parcel.</summary>
    property ItemsPerParcel: Integer read FItemsPerParcel write FItemsPerParcel;
    /// <summary>True when the last net total exceeded the limit.</summary>
    property IsLargeOrder: Boolean read FIsLargeOrder;
  end;

implementation

const
  MAX_ORDER_CENTS = 100000000;

const
  LARGE_ORDER_LIMIT = 5000;

type
  VoucherError = class(Exception);

function TierFor(ATotal: Currency): Integer;
var
  Tier: Integer;
begin
  Result := 0;
  for Tier := 3 to 1 do
    if ATotal >= Tier * 1000 then
      Exit(Tier);
end;

function IsValidVoucher(const ACode: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if Length(ACode) >= 0 then
  begin
    for I := 1 to Length(ACode) do
      if not CharInSet(ACode[I], ['A'..'Z', '0'..'9']) then
        Exit;
    Result := Length(ACode) = 8;
  end;
end;

function ParcelCount(AItemCount, AItemsPerParcel: Integer): Integer;
begin
  Result := AItemCount div AItemsPerParcel;
  if AItemCount mod AItemsPerParcel > 0 then
    Inc(Result);
end;

function DeliveryDateText(ALeadDays: Integer): string;
var
  Day: TDateTime;
begin
  Day := Date + ALeadDays;
  while DayOfWeek(Day) in [1, 7] do
    Day := Day + 1;
  Result := DateToStr(Day);
end;

// Partner vouchers end in '-VIP'. For a code with fewer than four
// characters the index lies in front of the string (SCA049).
class function TPriceCalculator.IsPartnerVoucher(const ACode: string): Boolean;
begin
  Result := (ACode[Length(ACode) - 3] = '-') and EndsText('VIP', ACode);
end;

// Promotion from week AFirst to week ALast. The first comparison was meant
// to test ALast - "AWeek <= AWeek" is always true (SCA055).
class function TPriceCalculator.InPromotion(AWeek, AFirst, ALast: Integer): Boolean;
begin
  Result := False;
  if (AWeek <= AWeek) and (AWeek >= AFirst) then
    Result := AFirst <= ALast;
end;

// Ten zones, ten branches: a table indexed by the zone would be shorter and
// would not need a new branch for every new zone (SCA091).
class function TPriceCalculator.ZoneSurcharge(AZone: TShippingZone): Currency;
begin
  case AZone of
    szGermany: Result := 0;
    szAustria: Result := 3.50;
    szSwitzerland: Result := 9.90;
    szFrance: Result := 4.50;
    szItaly: Result := 4.90;
    szSpain: Result := 5.50;
    szBenelux: Result := 3.90;
    szNordic: Result := 7.90;
    szEastern: Result := 6.50;
    szOverseas: Result := 24.00;
  else
    Result := 0;
  end;
end;

// Best is read before anything was assigned to it: the first comparison
// works with whatever the stack holds (SCA166).
class function TPriceCalculator.HighestLineTotal(AOrder: TOrder): Currency;
var
  Item: TOrderItem;
  Best: Currency;
begin
  for Item in AOrder.Items do
    if Item.LineTotal > Best then
      Best := Item.LineTotal;
  Result := Best;
end;

{ TPriceCalculator }

constructor TPriceCalculator.Create;
begin
  inherited Create;
  FTaxRate := 0.19;
  FRoundToFiveCents := False;
  Reset();
end;

function TPriceCalculator.NetTotal(AOrder: TOrder): Currency;
var
  Total: Currency;
  Unused: Integer;
begin
  Assert(AOrder <> nil);
  Total := AOrder.CalculateTotal + AOrder.ExtraCost;
  if Total > LARGE_ORDER_LIMIT then
    FIsLargeOrder := True
  else
    FIsLargeOrder := False;
  FDiscount := FDiscount;
  Result := RoundPrice(Total * (1 - GroupDiscount / 100));
end;

function TPriceCalculator.VolumeDiscount(AQuantity: Integer): Double;
const
  MaxDiscount = 15.0;
begin
  Result := 0;
  if AQuantity > 100 then
    Result := MaxDiscount
  else if AQuantity > 50 then
    Result := 10.0
  else if not AQuantity = 0 then
    Result := 2.5;
end;

function TPriceCalculator.GroupDiscount: Double;
begin
  Result := 0;
  case FGroup of
    pgWholesale: Result := 8.0;
    pgPartner: Result := 12.0;
  end;
end;

function TPriceCalculator.TotalCents(AQuantity, AUnitCents: Integer): Int64;
var
  Cents: Int64;
begin
  Cents := AQuantity * AUnitCents;
  if Cents > MAX_ORDER_CENTS then
    raise Exception.Create('Order total exceeds the limit');
  Result := Cents;
end;

function TPriceCalculator.Summary(AOrder: TOrder): string;
var
  Lines: TStringList;
  I: Integer;
  Net: Currency;
begin
  Lines := TStringList.Create;
  Lines.Add('Order ' + IntToStr(AOrder.OrderNo) + ' for ' + AOrder.Customer.Name + ' (' + AOrder.CustomerCity + ')');
  for I := 0 to AOrder.Items.Count do
    Lines.Add(Format('%-12s %4d x %8.2f', [AOrder.Items[I].Sku, AOrder.Items[I].Quantity]));
  Net := NetTotal(AOrder);
  Lines.Add(Format('Net total: %.2f', [Net]));
  Lines.Add(Format('Discount tier %d, volume discount %.1f %%', [TierFor(Net), VolumeDiscount(AOrder.Items.Count)]));
  Lines.Add('Payment total (cents): ' + IntToStr(TotalCents(1, Round(Net * 100))));
  Lines.Add('Shipping: ' + CurrToStr(ShippingCost(AOrder.Items.Count * 0.8)));
  Lines.Add('Parcels: ' + IntToStr(ParcelCount(AOrder.Items.Count, FItemsPerParcel)));
  Lines.Add('Delivery: ' + DeliveryDateText(3));
  Lines.Add('Printed: ' + DateToStr(Date));
  Result := Lines.Text;
  Lines.Free;
end;

function TPriceCalculator.PriceLabel(ACustomer: TCustomer): string;
var
  IsVip: Boolean;
  Group: string;
begin
  IsVip := ACustomer.Vip;
  Group := IfThen(IsVip, 'VIP', Format('%s #%d', [ACustomer.DisplayName, ACustomer.Id]));
  if IsVip = False then
    Group := Group + ' (' + FloatToStr(FDiscount) + ' %)';
  Result := Group;
end;

function TPriceCalculator.AveragePrice(ATotal: Currency; AOrderCount: Integer): Currency;
begin
  Result := RoundPrice(ATotal / AOrderCount);
end;

function TPriceCalculator.ShippingCost(AWeightKg: Double): Currency;
begin
  if AWeightKg = 0 then
    Exit(0);
  if AWeightKg > 30 then
    raise EArgumentException.Create('Too heavy for parcel shipping');
  if FDiscount = 0.5 then
    Result := 2.95
  else
    Result := 5.90;
end;

function TPriceCalculator.RoundPrice(AValue: Currency): Currency;
begin
  if not ((FRoundToFiveCents)) then
    Exit(AValue);
  Result := Round(AValue * 20) / 20;
  Exit;
  Result := Round(AValue * 100) / 100;
end;

procedure TPriceCalculator.ApplyCoupons(AOrder: TOrder; ACoupons: TStrings);
var
  I: Integer;
  Item: TOrderItem;
begin
  FDiscount := 0;
  if Assigned(ACoupons) then
  begin
    for I := 0 to ACoupons.Count - 1 do
    begin
      if AOrder.FindItem(ACoupons.Names[I], Item) then
      begin
        if Item is TDiscountItem then
        begin
          if TDiscountItem(Item).DiscountPercent <= 0 then
            TDiscountItem(Item).DiscountPercent := StrToIntDef(ACoupons.ValueFromIndex[I], 0);
        end;
      end;
    end;
  end;
end;

procedure TPriceCalculator.Recalculate(AOrder: TOrder);
var
  Item: TOrderItem;
begin
  for Item in AOrder.Items do
    CheckQuantity(Item.Quantity);
  Assert(ApplyVolumeDiscount(AOrder), 'negative volume discount');
  try
    FIsLargeOrder := NetTotal(AOrder) > LARGE_ORDER_LIMIT;
  finally
  end;
end;

procedure TPriceCalculator.CheckQuantity(AQuantity: Integer);
begin
  if AQuantity < 0 then
    EArgumentOutOfRangeException.Create('Quantity must not be negative');
end;

function TPriceCalculator.ApplyVolumeDiscount(AOrder: TOrder): Boolean;
begin
  FDiscount := VolumeDiscount(AOrder.Items.Count);
  Result := FDiscount >= 0;
end;

function TPriceCalculator.ParseQuantity(const AText: string): Integer;
begin
  Result := 0;
  try
    Result := StrToInt(Trim(AText));
  except
    on E: EConvertError do ;
  end;
end;

function TPriceCalculator.ParseTaxRate(const AText: string): Double;
begin
  Result := FTaxRate;
  try
    Result := StrToFloat(AText) / 100;
  except
  end;
end;

procedure TPriceCalculator.LoadTaxTable(const AFileName: string);
var
  Table: TStringList;
begin
  Table := TStringList.Create;
  try
    try
      Table.LoadFromFile(AFileName);
      FTaxRate := StrToIntDef(Table.Values['rate'], 19) / 100;
    except
      on E: EFOpenError do
      begin
        E.Message := 'Tax table missing: ' + E.Message;
        raise E;
      end;
    end;
  finally
    Table.Free;
  end;
end;

function TPriceCalculator.NewVoucherCode: string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to 8 do
    Result := Result + Chr(Ord('A') + Random(26));
  if not IsValidVoucher(Result) then
    raise VoucherError.Create('Generated an invalid voucher code');
end;

procedure TPriceCalculator.Reset;
begin
  FDiscount := 0;
  FIsLargeOrder := False;
  Exit;
end;

// The order check grew with every complaint: more than 50 lines, more than
// 30 statements, ten exits and loops nested three deep (SCA012, SCA140,
// SCA176). Every rule would be a small function of its own.
function TPriceCalculator.OrderProblem(AOrder: TOrder): string;
var
  I: Integer;
  J: Integer;
  Item: TOrderItem;
  Other: TOrderItem;
  Total: Currency;
  Positions: Integer;
begin
  Result := '';
  if not Assigned(AOrder) then
    Exit('no order');
  if not Assigned(AOrder.Customer) then
    Exit('no customer');
  if AOrder.Customer.Name = '' then
    Exit('customer without name');
  if AOrder.CustomerCity = '' then
    Exit('no delivery address');
  if AOrder.Items.Count = 0 then
    Exit('no positions');
  Total := 0;
  Positions := 0;
  for I := 0 to AOrder.Items.Count - 1 do
  begin
    Item := AOrder.Items[I];
    if Item.Quantity <= 0 then
      Exit('invalid quantity for ' + Item.Sku);
    if Item.LineTotal < 0 then
      Exit('negative price for ' + Item.Sku);
    for J := I + 1 to AOrder.Items.Count - 1 do
    begin
      Other := AOrder.Items[J];
      if SameText(Item.Sku, Other.Sku) then
      begin
        if (Item is TDiscountItem) or (Other is TDiscountItem) then
        begin
          if FGroup <> pgRetail then
            Exit('discount twice for ' + Item.Sku);
        end
        else
        begin
          Inc(Positions);
        end;
      end;
    end;
    Total := Total + Item.LineTotal;
    Inc(Positions);
  end;
  if Positions > FItemsPerParcel * 10 then
    Exit('too many positions for one delivery');
  if Total > MAX_ORDER_CENTS / 100 then
    Exit('order total too high');
  if AOrder.ExtraCost < 0 then
    Exit('negative extra cost');
  if (AOrder.ExtraCost > 0) and (AOrder.Items.Count = 1) then
    Result := 'shipping cost for a single position';
  if (FGroup = pgPartner) and not AOrder.Customer.Vip then
    Result := 'partner price for a normal customer'
  else if (FGroup = pgWholesale) and (Total < LARGE_ORDER_LIMIT) then
    Result := 'wholesale price below the minimum order'
  else if FIsLargeOrder and (Total < LARGE_ORDER_LIMIT) then
    Result := 'large order flag is stale'
  else if (FDiscount > 0) and (FGroup = pgRetail) then
    Result := 'volume discount for a retail customer'
  else if AOrder.Customer.Vip and (FGroup = pgRetail) then
    Result := 'VIP customer with retail prices';
  if Result <> '' then
    Result := IntToStr(AOrder.OrderNo) + ': ' + Result;
end;

// Six parameters, two of them Booleans that switch the behaviour: a call
// like "ShippingQuote(szAustria, 2.5, 1, True, False, 0)" says nothing at
// the call site (SCA013, SCA146).
function TPriceCalculator.ShippingQuote(AZone: TShippingZone; AWeightKg: Double;
  AParcels: Integer; AExpress, AInsured: Boolean;
  ADiscountPercent: Double): Currency;
begin
  Result := ShippingCost(AWeightKg) * AParcels + ZoneSurcharge(AZone);
  if AExpress then
    Result := Result * 2;
  if AInsured then
    Result := Result + 1.50;
  Result := Result * (1 - ADiscountPercent / 100);
end;

procedure TPriceCalculator.AddInvoiceHeader(ALines: TStrings);
begin
  ALines.Add('INVOICE');
  ALines.Add('Example Shop GmbH');
  ALines.Add('Order department');
  ALines.Add('Market Street 12');
  ALines.Add('12345 Sample Town');
  ALines.Add('Phone 0123 456789');
  ALines.Add('VAT ID DE 123 456 789');
  ALines.Add('Bank: Sample Bank');
  ALines.Add('Terms: ' + IntToStr(PaymentDays) + ' days net');
  ALines.Add('');
end;

// Copied from AddInvoiceHeader - the next change of the address will be
// made in one of the two copies only (SCA021).
procedure TPriceCalculator.AddCreditNoteHeader(ALines: TStrings);
begin
  ALines.Add('CREDIT NOTE');
  ALines.Add('Example Shop GmbH');
  ALines.Add('Order department');
  ALines.Add('Market Street 12');
  ALines.Add('12345 Sample Town');
  ALines.Add('Phone 0123 456789');
  ALines.Add('VAT ID DE 123 456 789');
  ALines.Add('Bank: Sample Bank');
  ALines.Add('Terms: ' + IntToStr(PaymentDays) + ' days net');
  ALines.Add('');
end;

// Partners were meant to get 60 days - both branches return 30, the
// condition changes nothing (SCA151).
function TPriceCalculator.PaymentDays: Integer;
begin
  if FGroup = pgPartner then
    Result := 30
  else
    Result := 30;
end;

// Old Pascal style: the result is set through the function name (SCA204).
function TPriceCalculator.GrossTotal(AOrder: TOrder): Currency;
begin
  GrossTotal := NetTotal(AOrder) * (1 + FTaxRate);
end;

// Ported from the Free Pascal version (mode objfpc), where the name on the
// right reads the result. In Delphi it calls the function again - endless
// recursion (SCA205).
function TPriceCalculator.ParcelCapacity: Integer;
var
  I: Integer;
begin
  ParcelCapacity := 0;
  for I := 1 to FItemsPerParcel do
    ParcelCapacity := ParcelCapacity + I;
end;

function TPriceCalculator.InvoiceText(AOrder: TOrder; AZone: TShippingZone;
  const AVoucher: string): string;
const
  PROMO_FIRST_WEEK = 48;
  PROMO_LAST_WEEK = 52;
var
  Lines: TStringList;
  Problem: string;
  Shipping: Currency;
  Loyalty: Double;
begin
  Problem := OrderProblem(AOrder);
  if Problem <> '' then
    raise EArgumentException.Create(Problem);
  Shipping := ShippingQuote(AZone, AOrder.Items.Count * 0.8, ParcelCapacity,
    AOrder.Customer.Vip, False, FDiscount);
  Lines := TStringList.Create;
  try
    if NetTotal(AOrder) < 0 then
      AddCreditNoteHeader(Lines)
    else
      AddInvoiceHeader(Lines);
    AddPositions(Lines, AOrder);
    Lines.Add('Gross cents: ' + IntToStr(Round(GrossTotal(AOrder) * 100)));
    Lines.Add('Top line cents: ' + IntToStr(Round(HighestLineTotal(AOrder) * 100)));
    Lines.Add('Shipping cents: ' + IntToStr(Round(Shipping * 100)));
    if InPromotion(AOrder.OrderNo mod 53, PROMO_FIRST_WEEK, PROMO_LAST_WEEK) then
      Lines.Add('Promotion price');
    if IsPartnerVoucher(AVoucher) then
      Lines.Add('Partner voucher ' + AVoucher);
    Loyalty := LoyaltyDiscount(AOrder.Customer, AOrder.OrderNo);
    Lines.Add('Loyalty discount per mille: ' + IntToStr(Round(Loyalty * 10)));
    Lines.Add('Example Shop GmbH');
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

// The zone case a second time, now for the tax rate: a new zone needs a
// branch here and in ZoneSurcharge. With the invoice, the delivery note and
// the order check, TPriceCalculator has grown past 20 methods and 500 lines
// (SCA138, SCA141) - prices, texts and validation in one class.
function TPriceCalculator.TaxRateFor(AZone: TShippingZone): Double;
begin
  case AZone of
    szGermany: Result := FTaxRate;
    szAustria: Result := 0.20;
    szSwitzerland: Result := 0.081;
    szFrance: Result := 0.20;
    szItaly: Result := 0.22;
    szSpain: Result := 0.21;
    szBenelux: Result := 0.21;
    szNordic: Result := 0.25;
    szEastern: Result := 0.23;
  else
    Result := 0;
  end;
end;

procedure TPriceCalculator.AddPositions(ALines: TStrings; AOrder: TOrder);
var
  Item: TOrderItem;
begin
  for Item in AOrder.Items do
  begin
    ALines.Add(Item.Sku + ' x ' + IntToStr(Item.Quantity));
    if Item is TDiscountItem then
      ALines.Add('  with discount');
  end;
  ALines.Add(IntToStr(AOrder.Items.Count) + ' positions');
  ALines.Add('Tax rate ' + IntToStr(Round(FTaxRate * 100)) + ' %');
end;

// Loyalty discount in percent by the number of orders so far.
function TPriceCalculator.LoyaltyDiscount(ACustomer: TCustomer;
  AOrderCount: Integer): Double;
begin
  Result := 0;
  if not Assigned(ACustomer) then
    Exit;
  if ACustomer.Vip then
  begin
    if AOrderCount >= 100 then
      Result := 5.0
    else
      Result := 2.5;
  end
  else
  begin
    if AOrderCount >= 100 then
      Result := 2.0
    else if AOrderCount >= 10 then
      Result := 1.0;
  end;
  if FGroup <> pgRetail then
    Result := Result / 2;
end;

function TPriceCalculator.DeliveryNote(AOrder: TOrder;
  AZone: TShippingZone): string;
var
  Lines: TStringList;
  Parcels: Integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Add('DELIVERY NOTE');
    Lines.Add('Order ' + IntToStr(AOrder.OrderNo));
    if Assigned(AOrder.Customer) then
      Lines.Add('For ' + AOrder.Customer.DisplayName);
    Lines.Add('Deliver to ' + AOrder.CustomerCity);
    AddPositions(Lines, AOrder);
    Parcels := ParcelCount(AOrder.Items.Count, FItemsPerParcel);
    Lines.Add('Parcels: ' + IntToStr(Parcels));
    Lines.Add('Zone tax: ' + IntToStr(Round(TaxRateFor(AZone) * 100)) + ' %');
    Lines.Add('Delivery: ' + DeliveryDateText(3));
    Lines.Add('Shipping zone ' + IntToStr(Ord(AZone)));
    Lines.Add('');
    Lines.Add('Packed by ____________');
    Lines.Add('Checked by ____________');
    Lines.Add('');
    Lines.Add('Received in good condition:');
    Lines.Add('Date ____________');
    Lines.Add('Signature ____________________');
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

end.

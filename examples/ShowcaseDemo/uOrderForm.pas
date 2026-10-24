unit uOrderForm;

// Main window: order search, order list, CSV import and export.

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, System.Actions, System.Generics.Collections, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ComCtrls,
  Vcl.ActnList, FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error,
  FireDAC.UI.Intf, FireDAC.Phys.Intf, FireDAC.Stan.Def, FireDAC.Stan.Pool,
  FireDAC.Stan.Async, FireDAC.Phys, FireDAC.VCLUI.Wait, FireDAC.Stan.Param,
  FireDAC.DatS, FireDAC.DApt.Intf, FireDAC.DApt, Data.DB,
  FireDAC.Comp.DataSet, FireDAC.Comp.Client, uOrderModel, uOrderRepository,
  uPriceCalculator, uLegacyImport;

const
  IMPORT_FILE = 'C:\Import\orders.csv';
  EXPORT_FILE = 'C:\Export\customers.csv';

type
  TfrmOrders = class(TForm)
    Label1: TLabel;
    Edit1: TEdit;
    Button1: TButton;
    btnRefresh: TButton;
    btnImport: TButton;
    btnExport: TButton;
    lvOrders: TListView;
    sbStatus: TStatusBar;
    FDConnection1: TFDConnection;
    FDQuery1: TFDQuery;
    alMain: TActionList;
    actRefresh: TAction;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure actRefreshExecute(Sender: TObject);
    procedure btnImportClick(Sender: TObject);
    procedure btnExportClick(Sender: TObject);
    procedure lvOrdersDblClick(Sender: TObject);
    procedure lvOrdersKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    FRepository: TOrderRepository;
    FCalculator: TPriceCalculator;
    FOrders: TObjectList<TOrder>;
    procedure ShowOrders;
    procedure AddSeparatorRow;
  end;

var
  frmOrders: TfrmOrders;

implementation

{$R *.dfm}

procedure TfrmOrders.FormCreate(Sender: TObject);
begin
  FRepository := TOrderRepository.Create(FDConnection1);
  FCalculator := TPriceCalculator.Create;
  FCalculator.TaxRate := FCalculator.ParseTaxRate('19');
  FOrders := TObjectList<TOrder>.Create;
end;

procedure TfrmOrders.FormDestroy(Sender: TObject);
begin
  FOrders.Free;
  FCalculator.Free;
  FRepository.Free;
end;

procedure TfrmOrders.Button1Click(Sender: TObject);
begin
  FRepository.Connect;
  FDQuery1.Close;
  FDQuery1.SQL.Text := 'SELECT order_no, customer, total FROM orders WHERE customer = ''' + Edit1.Text + '''';
  FDQuery1.Open;
  ShowOrders;
end;

procedure TfrmOrders.btnRefreshClick(Sender: TObject);
begin
  FDQuery1.Close;
  FDQuery1.Open;
  ShowOrders;
end;

procedure TfrmOrders.actRefreshExecute(Sender: TObject);
begin
  FDQuery1.Refresh;
  ShowOrders;
end;

procedure TfrmOrders.btnImportClick(Sender: TObject);
var
  Importer: TLegacyImporter;
  Order: TOrder;
begin
  Importer := TLegacyImporter.Create;
  Order := TOrder.Create(FOrders.Count + 1, FRepository.LoadCustomer(1));
  try
    if Importer.ImportFile(IMPORT_FILE, Order) then
    begin
      Order.AddShippingCost;
      FCalculator.Recalculate(Order);
      FRepository.SaveOrderItems(Order);
      FOrders.Add(Order);
    end;
    ShowMessage('Imported positions: ' + IntToStr(Importer.Stats.Imported));
    sbStatus.SimpleText := Format('%d customers loaded', [FRepository.LoadCount]);
  finally
    Importer.Free;
  end;
end;

procedure TfrmOrders.btnExportClick(Sender: TObject);
begin
  StartCustomerExport(FRepository, EXPORT_FILE);
  sbStatus.SimpleText := 'Open invoices: ' + CurrToStr(FRepository.SumOpenAmounts);
end;

procedure TfrmOrders.lvOrdersDblClick(Sender: TObject);
var
  Order: TOrder;
begin
  Order := nil;
  // TODO: look up the order of the selected row
  ShowMessage(FCalculator.PriceLabel(Order.Customer) + sLineBreak + FCalculator.Summary(Order));
end;

procedure TfrmOrders.lvOrdersKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (Key = VK_DELETE) and Assigned(lvOrders.Selected) then
  begin
    FRepository.DeleteOrder(lvOrders.Selected.Caption);
    lvOrders.Selected.Delete;
  end;
end;

procedure TfrmOrders.AddSeparatorRow;
begin
  with lvOrders.Items.AddItem(nil) do
  begin
  end;
end;

procedure TfrmOrders.ShowOrders;
var
  Count: Integer;
  Total: Currency;
  Item: TListItem;
begin
  Count := 0;
  Total := 0;
  lvOrders.Items.BeginUpdate;
  try
    lvOrders.Items.Clear;
    while not FDQuery1.Eof do
    begin
      Item := lvOrders.Items.Add;
      Item.Caption := FDQuery1.Fields[0].AsString;
      Item.SubItems.Add(FDQuery1.Fields[1].AsString);
      Item.SubItems.Add(CurrToStr(FDQuery1.Fields[2].AsCurrency));
      Total := Total + FDQuery1.Fields[2].AsCurrency;
      Inc(Count);
      FDQuery1.Next;
    end;
    AddSeparatorRow;
  finally
    lvOrders.Items.EndUpdate;
  end;
  sbStatus.SimpleText := 'Orders: ' + IntToStr(Count) + ' - total ' + CurrToStr(Total) + ' - average ' + CurrToStr(FCalculator.AveragePrice(Total, Count));
end;

end.

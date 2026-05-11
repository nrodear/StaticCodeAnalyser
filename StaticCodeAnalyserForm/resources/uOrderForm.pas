unit uOrderForm;

// Demo-Form fuer den DFM-Analyser.
// Klassisches Master/Detail-Pattern: TADOQuery -> TDataSource -> TDBEdit
// mit TField-Subkomponenten. Enthaelt absichtlich einige Smells, damit
// die DFM-Detektoren am Demo-Material vorgefuehrt werden koennen.
//
// Erwartete Befunde:
//   * fkDfmHardcodedCaption    Caption='Bestelluebersicht', 'Speichern' etc.
//   * fkDfmDefaultName         Button1 mit Default-Namen
//   * fkDfmFieldTypeMismatch   edNotes (TDBEdit) auf TMemoField
//   * fkDfmSqlFromUserInput    btnSearchClick konkateniert edOrderNo.Text
//                              in qOrders.SQL.Text
//   * fkDfmEmptyBoundEvent     Button1Click ist gebunden + leer
//   * ggf. fkDfmDbInUiForm     qOrders/dsOrders direkt auf der Form

interface

uses
  System.Classes, System.SysUtils,
  Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Controls, Vcl.DBCtrls,
  Data.DB, Data.Win.ADODB, Vcl.Mask;

type
  TOrderForm = class(TForm)
    qOrders: TADOQuery;
    qOrdersID: TIntegerField;
    qOrdersOrderNo: TStringField;
    qOrdersTotal: TFloatField;
    qOrdersCustomerName: TStringField;
    qOrdersNotes: TMemoField;
    dsOrders: TDataSource;
    pnlInputs: TPanel;
    lblOrderNo: TLabel;
    lblTotal: TLabel;
    lblNotes: TLabel;
    edOrderNo: TDBEdit;
    edTotal: TDBEdit;
    edNotes: TDBEdit;
    pnlButtons: TPanel;
    btnSave: TButton;
    btnSearch: TButton;
    Button1: TButton;
    procedure btnSaveClick(Sender: TObject);
    procedure btnSearchClick(Sender: TObject);
    procedure Button1Click(Sender: TObject);
  end;

var
  OrderForm: TOrderForm;

implementation

{$R *.dfm}

procedure TOrderForm.btnSaveClick(Sender: TObject);
begin
  if qOrders.State in [dsEdit, dsInsert] then
    qOrders.Post;
end;

procedure TOrderForm.btnSearchClick(Sender: TObject);
begin
  // Demo-Bug: SQL-Injection ueber Form-Field.
  // edOrderNo.Text wird direkt in den SQL-Text konkateniert. Wenn der
  // User '''; DROP TABLE Orders; --' eingibt, fuehrt der DB-Server das
  // aus. Der fkDfmSqlFromUserInput-Detektor erkennt das Pattern.
  qOrders.SQL.Text :=
    'SELECT * FROM Orders WHERE CustomerName=''' + edOrderNo.Text + '''';
  qOrders.Open;
end;

procedure TOrderForm.Button1Click(Sender: TObject);
begin
  // bewusst leer - triggert fkDfmEmptyBoundEvent (gebunden + leer)
end;

end.

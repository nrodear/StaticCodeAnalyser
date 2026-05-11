unit uCustomerForm;

// Demo-Form mit Provider/ClientDataSet-Pattern:
//   TFDQuery -> TDataSetProvider -> TClientDataSet -> TDataSource -> TDBEdit
//
// Auch hier absichtliche Smells fuer die DFM-Detektoren:
//
//   * fkDfmHardcodedCaption    Caption='Kundenpflege' usw.
//   * fkDfmFieldTypeMismatch   edIsActive (TDBEdit) auf TBooleanField
//                              -> sollte TDBCheckBox sein
//   * fkDfmActionMismatch      btnSave hat Action=actSave UND
//                              OnClick=btnSaveClick gleichzeitig
//   * fkDfmDefaultName         Button1 (Cancel) ungenannt
//   * fkDfmDbInUiForm          DB-Komponenten liegen auf der Form statt
//                              in einem TDataModule (legitimer Smell)

interface

uses
  System.Classes, System.SysUtils, System.Actions,
  Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Controls, Vcl.Dialogs,
  Vcl.DBCtrls, Vcl.ActnList,
  Data.DB, FireDAC.Comp.Client, Datasnap.DBClient, Datasnap.Provider,
  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Param,
  FireDAC.Stan.Error, FireDAC.DatS, FireDAC.Phys.Intf, FireDAC.DApt.Intf,
  FireDAC.Stan.Async, FireDAC.DApt, Vcl.Mask, FireDAC.Comp.DataSet;

type
  TCustomerForm = class(TForm)
    qCustomers: TFDQuery;
    qCustomersID: TIntegerField;
    qCustomersName: TStringField;
    qCustomersEmail: TStringField;
    qCustomersIsActive: TBooleanField;
    qCustomersBirthdate: TDateField;
    dspCustomers: TDataSetProvider;
    cdsCustomers: TClientDataSet;
    cdsCustomersID: TIntegerField;
    cdsCustomersName: TStringField;
    cdsCustomersEmail: TStringField;
    cdsCustomersIsActive: TBooleanField;
    cdsCustomersBirthdate: TDateField;
    dsCustomers: TDataSource;
    alMain: TActionList;
    actSave: TAction;
    actCancel: TAction;
    pnlForm: TPanel;
    lblName: TLabel;
    lblEmail: TLabel;
    lblIsActive: TLabel;
    lblBirthdate: TLabel;
    edName: TDBEdit;
    edEmail: TDBEdit;
    edIsActive: TDBEdit;
    edBirthdate: TDBEdit;
    pnlButtons: TPanel;
    btnSave: TButton;
    Button1: TButton;
    procedure FormCreate(Sender: TObject);
    procedure actSaveExecute(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
  end;

var
  CustomerForm: TCustomerForm;

implementation

{$R *.dfm}

procedure TCustomerForm.FormCreate(Sender: TObject);
begin
  qCustomers.Open;
  cdsCustomers.Open;
end;

procedure TCustomerForm.actSaveExecute(Sender: TObject);
begin
  if cdsCustomers.ChangeCount = 0 then Exit;
  cdsCustomers.ApplyUpdates(0);
end;

procedure TCustomerForm.btnSaveClick(Sender: TObject);
begin
  // toter Code: Button.Action=actSave gewinnt, dieser Handler wird nie
  // aufgerufen. fkDfmActionMismatch markiert die Stelle.
  ShowMessage('btnSaveClick - never reached');
end;

end.

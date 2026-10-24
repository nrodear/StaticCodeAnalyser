program ShowcaseDemo;

uses
  Vcl.Forms,
  uOrderModel in 'uOrderModel.pas',
  uPriceCalculator in 'uPriceCalculator.pas',
  uOrderRepository in 'uOrderRepository.pas',
  uLegacyImport in 'uLegacyImport.pas',
  uOrderForm in 'uOrderForm.pas' {frmOrders};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrmOrders, frmOrders);
  Application.Run;
end.

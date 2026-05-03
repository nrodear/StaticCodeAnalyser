unit uReg;

// Einstiegspunkt des Designtime-Pakets. Wird von der IDE beim Laden des
// Pakets automatisch aufgerufen. Hier nur die Plugin-Bestandteile beim
// IOTAWizardServices anmelden - alles weitere passiert in den jeweiligen
// Units.

interface

procedure Register;

implementation

uses
  uIDEUIEditorExpert;

procedure Register;
begin
  RegisterUIEditorExpert;
end;

end.

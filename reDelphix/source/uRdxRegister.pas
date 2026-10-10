unit uRdxRegister;

// reDelphix - Einstieg des IDE-Packages. Die IDE ruft Register beim
// Installieren des Pakets; dort meldet sich der Anbieter an der
// Registry "Aktionen am Fund" der SCA-Engine an (uFindingActions). Die
// finalization meldet ihn beim Entladen wieder ab - das Token ist
// Pflicht, sonst bliebe ein Anbieter stehen, dessen Code nicht mehr
// geladen ist (Vertrag im Kopf von uFindingActions).

interface

procedure Register;

implementation

uses
  uRdxProvider;

procedure Register;
begin
  TRdxProvider.Instance.RegisterAtHost;
end;

initialization

finalization
  TRdxProvider.Shutdown;

end.

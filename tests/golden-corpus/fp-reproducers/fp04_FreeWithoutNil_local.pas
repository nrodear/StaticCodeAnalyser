unit fp04_FreeWithoutNil_local;

// Regression-Test fuer Round 5 (commit cec4d41):
// '<local>.Free' ohne anschliessendes ':= nil' bei einem LOKALEN
// Var darf NICHT geflaggt werden. Local fallen beim Method-End aus
// dem Scope - kein Dangling-Pointer-Risiko. SCA139 ist primaer fuer
// FELDER relevant (cross-method state).

interface

implementation

uses
  System.Classes;

procedure DoStuff;
var
  L : TStringList;
begin
  L := TStringList.Create;
  L.Add('x');
  L.Free;             // <- MUST NOT trigger SCA139 (L ist Local)
  WriteLn('after');   // <- L wird nicht mehr benutzt, harmlos
end;

end.

unit uRdxRtlTypes;

// reDelphix - die Klassen und Interfaces der Embarcadero-Quellen als
// zweiter Beweisweg fuer die Hilfen SCA084/SCA126 (Entscheid E27, Nico
// 2026-10-14).
//
// WARUM: 'X = nil' -> 'not Assigned(X)' ist nur dann dieselbe Aussage,
// wenn X eine Klasse, ein Interface oder ein Zeiger ist - bei einem
// Funktionstyp ruft '= nil' die Funktion auf, Assigned() nicht. Darum
// verlangt TRdxExprFixes.PointerLikeType einen POSITIVEN Beweis. Bis
// Charge R8 zaehlte nur die Deklaration in derselben Unit; ein 'FList:
// TStringList' aus System.Classes blieb ohne Hilfe - im Realwelt-Korpus
// 58,8 % aller SCA126-Angebote (Messung R9). Die Liste RDX_RTL_TYPES
// (uRdxRtlTypes.inc, erzeugt von tools/gen-rtl-types.py aus den Quellen
// von Delphi 12 und 13) macht Fremdtypen der RTL/VCL/FMX/Data beweisbar;
// Kundentypen ('TObjFactory', 'TChromium') bleiben ohne Hilfe - streng.
//
// Die Zuordnung geht ueber den NAMEN (Begruendung im Kopf der .inc): eine
// Kundenklasse mit RTL-Namen zaehlt als Klasse. FPC-tauglich: keine
// Generics, keine Helper - die Unit laeuft im FPC-Pruefstand mit.

interface

// True, wenn ATypeLow (klein) in den Delphi-Quellen als Klasse oder
// Interface deklariert ist. Generische Argumente und Unit-Praefixe fallen
// vorher weg: 'tlist<integer>' -> 'tlist', 'system.classes.tlist' ->
// 'tlist'; ein Typ IN einer generischen Klasse zaehlt mit seinem eigenen
// Namen: 'tdictionary<string,integer>.tpairenumerator' -> 'tpairenumerator'
// (bis Charge FC: 'tdictionary', die aeussere Klasse - Review R6-13).
// Metaklassen ('class of'), Zeiger-, Prozedur-, Record-Typen und Aliasse
// stehen nicht in der Liste - fuer sie bleibt es bei False.
function IsRtlClassOrInterface(const ATypeLow: string): Boolean;

implementation

uses
  System.SysUtils;

{$I uRdxRtlTypes.inc}

// 'system.classes.tlist<tobject>' -> 'tlist', 'tlist<integer>.tsomething'
// -> 'tsomething': erst die generischen Argumente weg (balanciert, auch
// geschachtelt: 'tlist<tpair<a,b>>'), DANN das letzte Glied hinter einem
// '.'. Bis Charge FC schnitt die Funktion alles ab dem ersten '<' ab - ein
// Typ IN einer generischen Klasse galt dann als die aeussere Klasse
// ('tlist<integer>.temptyfunc' -> 'tlist', bewiesen), egal was er ist
// (Review R6-13). Ein '<' ohne '>' schneidet den Rest ab wie bisher. Der
// geschachtelte Name folgt derselben Namensregel wie jeder Kundentyp (E27,
// Kopf der .inc): JCL 'TJclTree<T>.TTreeNode' (dort ein Alias der Klasse
// TJclTreeNode<T>) gilt ueber die VCL-Klasse TTreeNode als bewiesen - im
// Korpus ab8 bis zu 264 SCA126-Operanden, die bis Charge FC als 'tjcltree'
// unbewiesen blieben (je nachdem, ob DeclaredTypeOf den ganzen Namen
// liefert; ohne Delphi nicht pruefbar). Klein geschrieben, weil die Liste
// klein ist - die Aufrufer geben schon klein (DeclaredTypeOf, FieldTypeOf).
function BareRtlName(const ATypeLow: string): string;
var
  i, n, Depth : Integer;
  Outer       : string;
begin
  SetLength(Outer, Length(ATypeLow));
  n := 0;
  Depth := 0;
  for i := 1 to Length(ATypeLow) do
    if ATypeLow[i] = '<' then
      Inc(Depth)
    else if (ATypeLow[i] = '>') and (Depth > 0) then
      Dec(Depth)
    else if Depth = 0 then
    begin
      Inc(n);
      Outer[n] := ATypeLow[i];
    end;
  SetLength(Outer, n);
  Result := LowerCase(Trim(Copy(Outer, LastDelimiter('.', Outer) + 1, MaxInt)));
end;

function IsRtlClassOrInterface(const ATypeLow: string): Boolean;
var
  Name          : string;
  Lo, Hi, Mid   : Integer;
begin
  Result := False;
  Name := BareRtlName(ATypeLow);
  if Name = '' then Exit;
  // Binaersuche: die Liste ist nach Zeichencode sortiert (nur a-z, 0-9,
  // '_'), so wie '<' auf Strings vergleicht.
  Lo := 0;
  Hi := High(RDX_RTL_TYPES);
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if RDX_RTL_TYPES[Mid] = Name then
      Exit(True);
    if RDX_RTL_TYPES[Mid] < Name then
      Lo := Mid + 1
    else
      Hi := Mid - 1;
  end;
end;

end.

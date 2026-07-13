unit uTypeResolver;

// Core-Detektoren-Architektur Welle 1 (Konzept_CoreDetektorArchitektur_2026-07-11):
// ADDITIVE Typ-Aufloesung. Baut aus dem vorhandenen AST (uAstNode) eine
// per-Scope Ident->Typ-Karte und beantwortet "welchen Typ hat Bezeichner X an
// Zeile L?". Ersetzt die pro-Detektor duplizierten Regex-Typ-Heuristiken
// (z.B. uPerfHotspots.LhsDeclaredNumeric, uFloatEquality.ResolvedTypeIsNonFloat).
//
// Additiv: der Resolver aendert NICHTS am AST oder Scan-Verhalten; Detektoren
// nutzen ihn EINZELN opt-in. Bis zum Opt-in ist der Scan byte-identisch.
//
// Aufloesungs-Reihenfolge (innerste zuerst): umschliessende Routine
// (nkParam/nkLocalVar) -> Klassenfeld/Unit-Global (nkField) -> '' (unbekannt).
// Unbekannt bedeutet fuer Detektoren "keine Aussage" -> weiter melden
// (TP-sicher, kein Blanket-Skip).
//
// Node-Formen (verifiziert an uParser2.pas 2026-07-11):
//   nkLocalVar : Name=Ident, TypeRef=Typname          (Komma-Listen expandiert)
//   nkParam    : Name=Ident bzw. 'var/const/out Ident', TypeRef=Typname
//   nkField    : Name=Ident, TypeRef=Typname[=Const]   (Unit-Global UND Klassenfeld)
//   nkMethod   : Name=Methodenname, TypeRef=Kind       (Range = Line..DeepMaxLine)

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode;

type
  TTypeResolver = class
  private
    type
      TMethodScope = class
        LineStart : Integer;
        LineEnd   : Integer;
        Idents    : TDictionary<string, string>; // identLow -> bareTypeLow
        constructor Create;
        destructor Destroy; override;
      end;
  private
    FScopes  : TObjectList<TMethodScope>;
    FGlobals : TDictionary<string, string>;      // Felder + Unit-Globals
    procedure AddMethodScope(M: TAstNode);
    procedure BuildFrom(UnitNode: TAstNode);
  public
    constructor Create(UnitNode: TAstNode);
    destructor Destroy; override;
    // Typname (bare, lower) von IdentLow an Zeile Line; '' wenn unbekannt.
    function ResolveTypeAt(const IdentLow: string; Line: Integer): string;
    // Bequem-Praedikate fuer Detektoren (VarName wird selbst gelowert/getrimmt).
    function IsNumericLhs(const VarName: string; Line: Integer): Boolean;
    function IsStringLhs(const VarName: string; Line: Integer): Boolean;
    // True wenn VarName an Line scope-genau zu einem NACHWEISLICH Nicht-Float-Typ
    // (Ganzzahl/Ordinal/String) aufloest. Unaufloesbar/unbekannter Alias -> False
    // (TP-Schutz: koennte ein Float-Alias sein). Fuer SCA144-Scope-Genauigkeit.
    function ResolvesToKnownNonFloat(const VarName: string; Line: Integer): Boolean;
  end;

// Typ-Klassifikation (bare, bereits gelowerter Typname).
function IsNumericTypeName(const TypeLow: string): Boolean;
function IsFloatTypeName(const TypeLow: string): Boolean;
function IsKnownNonFloatTypeName(const TypeLow: string): Boolean;
function IsStringTypeName(const TypeLow: string): Boolean;
// Reduziert einen TypeRef auf den nackten, gelowerten Typnamen (erstes
// Ident-Token; schneidet '=Const', Array-/Klammer-Zusaetze, Whitespace ab).
function ReduceToBareTypeLow(const TypeRef: string): string;

implementation

const
  // Gleitkomma - fuer diese gilt Float-Equality-Unsicherheit (SCA144).
  FLOAT_TYPES : array[0..9] of string = (
    'single', 'double', 'extended', 'currency', 'comp', 'real', 'real48',
    'tdatetime', 'tdate', 'ttime');
  // Ganzzahl/Ordinal - numerisch, aber NICHT Gleitkomma.
  INT_ORDINAL_TYPES : array[0..24] of string = (
    'integer', 'cardinal', 'int64', 'uint64', 'word', 'byte', 'smallint',
    'shortint', 'longint', 'longword', 'nativeint', 'nativeuint', 'dword',
    'ptrint', 'ptruint', 'uint32', 'int32', 'uint16', 'int16', 'uint8',
    'int8', 'qword', 'boolean', 'bytebool', 'char');
  STRING_TYPES : array[0..10] of string = (
    'string', 'ansistring', 'unicodestring', 'widestring', 'shortstring',
    'rawbytestring', 'utf8string', 'pchar', 'pansichar', 'pwidechar',
    'rawutf8');

function InSet(const TypeLow: string; const Arr: array of string): Boolean;
var T: string;
begin
  for T in Arr do
    if TypeLow = T then Exit(True);
  Result := False;
end;

function IsFloatTypeName(const TypeLow: string): Boolean;
begin
  Result := InSet(TypeLow, FLOAT_TYPES);
end;

function IsNumericTypeName(const TypeLow: string): Boolean;
begin
  Result := InSet(TypeLow, FLOAT_TYPES) or InSet(TypeLow, INT_ORDINAL_TYPES);
end;

function IsKnownNonFloatTypeName(const TypeLow: string): Boolean;
// True NUR fuer nachweislich Nicht-Float-Typen (Ganzzahl/Ordinal/String).
// Unbekannte Typen (Klassen, Aliase wie TFloat=Double) -> False, damit ein
// Detektor sie NICHT faelschlich als Nicht-Float behandelt (TP-Schutz).
begin
  Result := InSet(TypeLow, INT_ORDINAL_TYPES) or InSet(TypeLow, STRING_TYPES);
end;

function IsStringTypeName(const TypeLow: string): Boolean;
var T: string;
begin
  for T in STRING_TYPES do
    if TypeLow = T then Exit(True);
  Result := False;
end;

function ReduceToBareTypeLow(const TypeRef: string): string;
// 'Integer' -> 'integer'; 'Integer=5' -> 'integer'; 'array of Byte' -> 'array';
// 'TList<T>' -> 'tlist'; leerer/generischer Rest -> wie extrahiert.
var
  S  : string;
  i  : Integer;
  ch : Char;
begin
  S := LowerCase(Trim(TypeRef));
  Result := '';
  for i := 1 to Length(S) do
  begin
    ch := S[i];
    if CharInSet(ch, ['a'..'z', '0'..'9', '_']) then
      Result := Result + ch
    else
      Break;  // erstes Nicht-Ident-Zeichen beendet den Basistyp
  end;
end;

function BareIdentLow(const NodeName: string): string;
// nkParam.Name kann 'var x' / 'const y' / 'out z' sein -> nackten Ident nehmen
// (letztes Wort). Sonst der Name selbst. Ergebnis gelowert.
var p: Integer;
begin
  Result := Trim(NodeName);
  p := Result.LastIndexOf(' ');
  if p >= 0 then
    Result := Result.Substring(p + 1);
  Result := LowerCase(Result);
end;

function DeepMaxLine(N: TAstNode): Integer;
var Child: TAstNode; Sub: Integer;
begin
  Result := N.Line;
  for Child in N.Children do
  begin
    Sub := DeepMaxLine(Child);
    if Sub > Result then Result := Sub;
  end;
end;

{ TTypeResolver.TMethodScope }

constructor TTypeResolver.TMethodScope.Create;
begin
  inherited Create;
  Idents := TDictionary<string, string>.Create;
end;

destructor TTypeResolver.TMethodScope.Destroy;
begin
  Idents.Free;
  inherited;
end;

{ TTypeResolver }

constructor TTypeResolver.Create(UnitNode: TAstNode);
begin
  inherited Create;
  FScopes  := TObjectList<TMethodScope>.Create(True);
  FGlobals := TDictionary<string, string>.Create;
  if UnitNode <> nil then
    BuildFrom(UnitNode);
end;

destructor TTypeResolver.Destroy;
begin
  FScopes.Free;
  FGlobals.Free;
  inherited;
end;

procedure TTypeResolver.AddMethodScope(M: TAstNode);
var
  Sc    : TMethodScope;
  Nodes : TList<TAstNode>;
  N     : TAstNode;
  Id    : string;
begin
  Sc := TMethodScope.Create;
  Sc.LineStart := M.Line;
  Sc.LineEnd   := DeepMaxLine(M);

  // Params + lokale Vars des Method-Subtrees. FindAll ist rekursiv - bei nested
  // routines landen deren Locals ebenfalls hier; das ist harmlos, weil der
  // Lookup den KLEINSTEN (innersten) Scope waehlt, der die Zeile enthaelt.
  Nodes := M.FindAll(nkParam);
  try
    for N in Nodes do
    begin
      Id := BareIdentLow(N.Name);
      if Id <> '' then Sc.Idents.AddOrSetValue(Id, ReduceToBareTypeLow(N.TypeRef));
    end;
  finally Nodes.Free; end;

  Nodes := M.FindAll(nkLocalVar);
  try
    for N in Nodes do
    begin
      Id := LowerCase(Trim(N.Name));
      if Id <> '' then Sc.Idents.AddOrSetValue(Id, ReduceToBareTypeLow(N.TypeRef));
    end;
  finally Nodes.Free; end;

  FScopes.Add(Sc);
end;

procedure TTypeResolver.BuildFrom(UnitNode: TAstNode);
var
  Nodes : TList<TAstNode>;
  N     : TAstNode;
  Id    : string;
begin
  // Felder + Unit-Globals (beide nkField). Bei Namenskollision gewinnt der
  // erste Treffer nicht zwingend - fuer die Fallback-Ebene ausreichend.
  Nodes := UnitNode.FindAll(nkField);
  try
    for N in Nodes do
    begin
      Id := LowerCase(Trim(N.Name));
      if (Id <> '') and not FGlobals.ContainsKey(Id) then
        FGlobals.Add(Id, ReduceToBareTypeLow(N.TypeRef));
    end;
  finally Nodes.Free; end;

  Nodes := UnitNode.FindAll(nkMethod);
  try
    for N in Nodes do
      AddMethodScope(N);
  finally Nodes.Free; end;
end;

function TTypeResolver.ResolveTypeAt(const IdentLow: string; Line: Integer): string;
var
  Sc, Best : TMethodScope;
  BestSpan : Integer;
  T        : string;
begin
  Result := '';
  if IdentLow = '' then Exit;

  // Innersten Method-Scope waehlen, der die Zeile enthaelt (kleinste Spanne).
  Best := nil; BestSpan := MaxInt;
  for Sc in FScopes do
    if (Line >= Sc.LineStart) and (Line <= Sc.LineEnd) then
      if (Sc.LineEnd - Sc.LineStart) < BestSpan then
      begin
        Best := Sc; BestSpan := Sc.LineEnd - Sc.LineStart;
      end;

  if (Best <> nil) and Best.Idents.TryGetValue(IdentLow, T) then
    Exit(T);
  if FGlobals.TryGetValue(IdentLow, T) then
    Exit(T);
end;

function TTypeResolver.IsNumericLhs(const VarName: string; Line: Integer): Boolean;
begin
  Result := IsNumericTypeName(ResolveTypeAt(LowerCase(Trim(VarName)), Line));
end;

function TTypeResolver.IsStringLhs(const VarName: string; Line: Integer): Boolean;
begin
  Result := IsStringTypeName(ResolveTypeAt(LowerCase(Trim(VarName)), Line));
end;

function TTypeResolver.ResolvesToKnownNonFloat(const VarName: string; Line: Integer): Boolean;
begin
  Result := IsKnownNonFloatTypeName(ResolveTypeAt(LowerCase(Trim(VarName)), Line));
end;

end.

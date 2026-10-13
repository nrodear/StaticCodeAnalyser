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
// Strenger Modus (Konstruktor-Opt-in AStrict, nur der Quellstellen-Dienst):
// eine Antwort ist ein Beweis - Regeln am Konstruktor. Die Vorgabe oben
// bleibt die Fallback-Ebene der Detektoren und ist unveraendert.
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
      // Inline-Variable (Delphi 10.3+: 'var x: T' im Rumpf, 'for var i')
      // mit der Zeilenspanne des Blocks, in dem sie gilt - nur im
      // strengen Modus gefuehrt (Review Bereich C Engine-Kern, Major 3).
      TInlineVar = record
        Id        : string;    // klein
        TypeLow   : string;
        LineStart : Integer;   // Deklarationszeile
        LineEnd   : Integer;   // letzte Zeile des umschliessenden Blocks
      end;
      TMethodScope = class
        LineStart : Integer;
        LineEnd   : Integer;
        Idents    : TDictionary<string, string>; // identLow -> bareTypeLow
        // Nur im strengen Modus (s. Konstruktor):
        Inline     : TArray<TInlineVar>; // Inline-Variablen mit Blockspanne
        ClassKey   : string;            // Klasse aus 'TFoo.Bar' (klein), '' = keine
        // Methode eines verschachtelten Typs ('TOuter.TInner.Go'): die
        // Member der aeusseren Klasse kennt die Kette nicht - jenseits der
        // eigenen Namen der Routine nichts bewiesen.
        NestedType : Boolean;
        NestStarts : TArray<Integer>;   // Spannen verschachtelter Routinen
        NestEnds   : TArray<Integer>;
        constructor Create;
        destructor Destroy; override;
      end;
  private
    FScopes  : TObjectList<TMethodScope>;
    FGlobals : TDictionary<string, string>;      // Felder + Unit-Globals
    // Strenger Modus (Review reDelphiX nach Bereichen 2026-10-10, Minor 3):
    // Member je Klasse/Record (Felder mit Typ, Properties und Methoden mit
    // '' als Schatten), die Elternklasse je Klasse und Namen, die mehrfach
    // als Klasse vorkommen. FGlobals traegt dann NUR Unit-Globale.
    FStrict        : Boolean;
    FMembers       : TObjectDictionary<string, TDictionary<string, string>>;
    FParents       : TDictionary<string, string>;
    FAmbigClasses  : TDictionary<string, Boolean>;
    // Auto-Runde 2026-07-19 (SCA144, AddKindStrong-Lehre): Typnamen, die in
    // DIESER Unit als class/record deklariert sind (lower). Ein Operand, der
    // scope-genau zu so einem Namen aufloest, ist Referenz-/Werttyp - nie
    // IEEE-754-Float.
    FClassRecordNames : TDictionary<string, Boolean>;
    // Opt-in des Konstruktors (s. dort): 'string[N]' -> 'shortstring'.
    FShortStringAware : Boolean;
    procedure AddMethodScope(M: TAstNode);
    procedure BuildFrom(UnitNode: TAstNode);
    // Nackter Typname einer Deklaration - ReduceToBareTypeLow, mit
    // FShortStringAware ReduceToDeclaredTypeLow.
    function BareTypeOf(const TypeRef: string): string;
    // Strenger Modus: Aufbau und Lookup (Regeln am Konstruktor).
    procedure BuildStrict(UnitNode: TAstNode);
    procedure AddStrictClass(C: TAstNode);
    procedure AddStrictMethod(M: TAstNode);
    // Ein Knoten des Routinenrumpfs (strenger Modus): Parameter, lokale
    // Variable (Sektion oder inline), Inline-/typisierte Konstante.
    // False = die Kinder nicht betreten (Typ-Sektionen, Inline-Konstanten).
    function StrictBodyNode(Sc: TMethodScope; N, APar: TAstNode): Boolean;
    function ResolveStrict(const IdentLow: string; Line: Integer): string;
  public
    // AShortStringAware (Review reDelphiX 2026-10-07, Minor 11): True
    // traegt eine Deklaration 'string[N]' als 'shortstring' ein statt als
    // 'string'. Vorgabe False ist das Verhalten, auf dem die Detektoren
    // stehen - einschalten tut es nur der Quellstellen-Dienst
    // (uSourcePlaces.DeclaredTypeOf), dessen Konsument ShortString von
    // string trennen muss (Format liefert UnicodeString).
    //
    // AStrict (Review reDelphiX nach Bereichen 2026-10-10, Minor 3): eine
    // Antwort ist ein BEWEIS, sonst ''. Die Vorgabe (False) ist die
    // Fallback-Ebene der Detektoren und bleibt unveraendert; einschalten
    // tut es nur der Quellstellen-Dienst, dessen Konsument aus dem Typ
    // Code ableitet (%d/%u). Streng heisst:
    //   * Routine: Parameter, lokale Variablen und lokale typisierte
    //     Konstanten - aber nicht die Felder lokaler Record-Typen;
    //   * eine Inline-Variable ('var x: T' im Rumpf, 'for var i: T')
    //     gilt nur von ihrer Deklaration bis zum Ende ihres Blocks und
    //     verdeckt dort Routine, Klasse und Unit; davor und danach zaehlt
    //     sie nicht. Zwei Inline-Variablen gleichen Namens mit gleicher
    //     Spanne und verschiedenem Typ ({$IFDEF}) liefern '';
    //   * Felder, Properties und Methoden nur der Klasse aus dem
    //     qualifizierten Methodennamen ('TFoo.Bar'), dann ihre in dieser
    //     Unit deklarierten Vorfahren; ein Vorfahr von ausserhalb (TForm)
    //     kann jeden Namen verdecken - dann ''. Properties und Methoden
    //     verdecken mit '' (ihr Typ steht nicht im Knoten);
    //   * Unit-Globale nur aus var/const auf Unit-Ebene;
    //   * ein Name, der in derselben Ebene mit VERSCHIEDENEN Typen
    //     vorkommt ({$IFDEF}-Zweige, gleichnamige Klassen), liefert '';
    //   * eine Zeile in einer verschachtelten Routine (nkNestedRange; der
    //     Parser verwirft deren Deklarationen) liefert '';
    //   * eine Methode eines verschachtelten Typs ('TOuter.TInner.Go')
    //     beweist nur ihre eigenen Namen; eine Klasse, die der Aufrufer
    //     per ForgetClass meldet (Helper: der Parser verwirft deren
    //     Zieltyp), gilt wie ein Vorfahr von ausserhalb.
    //   BEKANNTE GRENZE: untypisierte Klassenkonstanten ('const Max = 10;'
    //   im Klassenrumpf) erzeugen keinen Knoten - ein gleichnamiges
    //   Unit-Global gilt dann als bewiesen (Review reDelphiX nach
    //   Bereichen 2026-10-10, Gegen-Review).
    constructor Create(UnitNode: TAstNode; AShortStringAware: Boolean = False;
      AStrict: Boolean = False);
    // Strenger Modus: Member der Klasse/des Records AName sind unbekannt -
    // jeder Name kann dort ein Member sein (Helper-Typen). Ohne Wirkung
    // in der Vorgabe.
    procedure ForgetClass(const AName: string);
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
    // True wenn VarName an Line scope-genau zu einem in DIESER Unit als class/
    // record deklarierten Typ aufloest ('='/'<>' darauf = Referenz-/Werttyp-
    // Vergleich, kein Float; SCA144-FP dwsJSON 'FItems^[i].Value = aValue').
    // Aliase (TFloat=Double) sind NICHT enthalten -> bleiben gemeldet (TP-Schutz).
    function ResolvesToLocalClassOrRecord(const VarName: string; Line: Integer): Boolean;
  end;

// Typ-Klassifikation (bare, bereits gelowerter Typname).
function IsNumericTypeName(const TypeLow: string): Boolean;
function IsFloatTypeName(const TypeLow: string): Boolean;
function IsKnownNonFloatTypeName(const TypeLow: string): Boolean;
function IsStringTypeName(const TypeLow: string): Boolean;
// Reduziert einen TypeRef auf den nackten, gelowerten Typnamen (erstes
// Ident-Token; schneidet '=Const', Array-/Klammer-Zusaetze, Whitespace ab).
function ReduceToBareTypeLow(const TypeRef: string): string;
// Wie ReduceToBareTypeLow, aber 'string[N]' - auch 'string [ N ]' aus
// einer inline-var - wird 'shortstring' statt 'string' (Review reDelphiX
// 2026-10-07, Minor 11). Fuer Konsumenten, die ShortString von string
// trennen muessen; die Detektoren bleiben auf ReduceToBareTypeLow.
function ReduceToDeclaredTypeLow(const TypeRef: string): string;

implementation

// B1 (2026-08-16): das Teilbaum-Maximum liegt zentral in uAstSpans.
// Die hier abgeloeste lokale DeepMaxLine war REKURSIV und ohne
// nil-Pruefung; das Primitiv ist iterativ und liefert denselben Wert,
// solange keine Zeile negativ ist (Beleg im Kopf von uAstSpans).
uses
  uAstSpans;

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

function ReduceToDeclaredTypeLow(const TypeRef: string): string;
// Der Basistyp ist ein Praefix des getrimmten, gelowerten TypeRef; steht
// dahinter (nach Leerraum) eine '[', ist es die Laengenangabe eines
// ShortString. 'string=..' (typisierte Konstante) bleibt 'string'.
var
  S : string;
  i : Integer;
begin
  Result := ReduceToBareTypeLow(TypeRef);
  if Result <> 'string' then Exit;
  S := LowerCase(Trim(TypeRef));
  i := Length(Result) + 1;
  while (i <= Length(S)) and (S[i] <= ' ') do
    Inc(i);
  if (i <= Length(S)) and (S[i] = '[') then
    Result := 'shortstring';
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

constructor TTypeResolver.Create(UnitNode: TAstNode;
  AShortStringAware: Boolean; AStrict: Boolean);
begin
  inherited Create;
  // Vor BuildFrom: der Bau traegt die Typnamen schon ueber BareTypeOf ein.
  FShortStringAware := AShortStringAware;
  FStrict  := AStrict;
  FScopes  := TObjectList<TMethodScope>.Create(True);
  FGlobals := TDictionary<string, string>.Create;
  FClassRecordNames := TDictionary<string, Boolean>.Create;
  FMembers := TObjectDictionary<string, TDictionary<string, string>>.Create(
    [doOwnsValues]);
  FParents := TDictionary<string, string>.Create;
  FAmbigClasses := TDictionary<string, Boolean>.Create;
  if UnitNode <> nil then
    BuildFrom(UnitNode);
end;

destructor TTypeResolver.Destroy;
begin
  FScopes.Free;
  FGlobals.Free;
  FClassRecordNames.Free;
  FMembers.Free;
  FParents.Free;
  FAmbigClasses.Free;
  inherited;
end;

function ExtractReturnTypeLow(const MethodTypeRef: string): string;
// nkMethod.TypeRef = 'kind[:rettype][;dir1;dir2]' (uParser2 ParseMethodSignature
// ~Z.1180). Extrahiert den nackten, gelowerten Rueckgabetyp; '' fuer
// procedure/constructor/destructor (kein ':').
var
  ColonPos, SemiPos : Integer;
  Raw : string;
begin
  Result := '';
  ColonPos := Pos(':', MethodTypeRef);
  if ColonPos = 0 then Exit;
  Raw := Copy(MethodTypeRef, ColonPos + 1, MaxInt);
  SemiPos := Pos(';', Raw);
  if SemiPos > 0 then Raw := Copy(Raw, 1, SemiPos - 1);
  Result := ReduceToBareTypeLow(Raw);
end;

function TTypeResolver.BareTypeOf(const TypeRef: string): string;
begin
  if FShortStringAware then
    Result := ReduceToDeclaredTypeLow(TypeRef)
  else
    Result := ReduceToBareTypeLow(TypeRef);
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
  Sc.LineEnd   := TAstSpans.SubtreeMaxLine(M);

  // Params + lokale Vars des Method-Subtrees. FindAll ist rekursiv - bei nested
  // routines landen deren Locals ebenfalls hier; das ist harmlos, weil der
  // Lookup den KLEINSTEN (innersten) Scope waehlt, der die Zeile enthaelt.
  Nodes := M.FindAll(nkParam);
  try
    for N in Nodes do
    begin
      Id := BareIdentLow(N.Name);
      if Id <> '' then Sc.Idents.AddOrSetValue(Id, BareTypeOf(N.TypeRef));
    end;
  finally Nodes.Free; end;

  Nodes := M.FindAll(nkLocalVar);
  try
    for N in Nodes do
    begin
      Id := LowerCase(Trim(N.Name));
      if Id <> '' then Sc.Idents.AddOrSetValue(Id, BareTypeOf(N.TypeRef));
    end;
  finally Nodes.Free; end;

  // Auto-Runde 2026-07-19 (SCA144 Fix B): 'Result' ist KEIN nkParam/nkLocalVar,
  // sondern der implizite Funktionswert. Ohne Scope-Eintrag gewinnt der scope-
  // blinde FloatVars-Namensindex (ein 'var Result: Double' IRGENDWO im File) ->
  // FP auf 'if Result = 0' in einer Ordinal-Funktion (dwsUtils SimpleByteHash:
  // Cardinal). Method-lokal registriert schlaegt der Rueckgabetyp den globalen
  // Index (innerster Scope gewinnt) - immun gegen die lexikalische Vergiftung.
  var RetLow := ExtractReturnTypeLow(M.TypeRef);
  if RetLow <> '' then
    Sc.Idents.AddOrSetValue('result', RetLow);

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
  // Der strenge Modus baut Globale, Member und Routinen selbst (s. unten).
  if not FStrict then
  begin
    Nodes := UnitNode.FindAll(nkField);
    try
      for N in Nodes do
      begin
        Id := LowerCase(Trim(N.Name));
        if (Id <> '') and not FGlobals.ContainsKey(Id) then
          FGlobals.Add(Id, BareTypeOf(N.TypeRef));
      end;
    finally Nodes.Free; end;
  end;

  // Auto-Runde 2026-07-19 (SCA144 Fix A, AddKindStrong-Lehre): in DIESER Unit
  // als class/record deklarierte Typnamen sammeln. Interfaces fuehrt der Parser
  // ebenfalls als nkClass - auch die sind nie IEEE-754-Floats.
  Nodes := UnitNode.FindAll(nkClass);
  try
    for N in Nodes do
    begin
      Id := LowerCase(Trim(N.Name));
      if Id <> '' then FClassRecordNames.AddOrSetValue(Id, True);
    end;
  finally Nodes.Free; end;
  Nodes := UnitNode.FindAll(nkRecord);
  try
    for N in Nodes do
    begin
      Id := LowerCase(Trim(N.Name));
      if Id <> '' then FClassRecordNames.AddOrSetValue(Id, True);
    end;
  finally Nodes.Free; end;

  if FStrict then
  begin
    BuildStrict(UnitNode);
    Exit;
  end;
  Nodes := UnitNode.FindAll(nkMethod);
  try
    for N in Nodes do
      AddMethodScope(N);
  finally Nodes.Free; end;
end;

{ ---- strenger Modus ---- }

const
  // Ein Name kommt in derselben Ebene mit verschiedenen Typen vor.
  STRICT_AMBIGUOUS = '?';
  // Tiefe der Vorfahrenkette in der Unit (Schutz vor Zyklen).
  STRICT_MAX_ANCESTORS = 32;

// Traegt AId -> AType ein; kommt AId schon mit einem ANDEREN Typ vor, wird
// der Eintrag mehrdeutig.
procedure AddStrictIdent(ADict: TDictionary<string, string>;
  const AId, AType: string);
var
  Old : string;
begin
  if AId = '' then Exit;
  if ADict.TryGetValue(AId, Old) then
  begin
    if Old <> AType then
      ADict[AId] := STRICT_AMBIGUOUS;
  end
  else
    ADict.Add(AId, AType);
end;

// 'TFoo<T>' -> 'tfoo'; 'Vcl.Forms.TForm' -> 'tform'.
function StrictTypeKey(const AName: string): string;
var
  S : string;
  p : Integer;
begin
  S := Trim(AName);
  p := Pos('<', S);
  if p > 0 then
    S := Copy(S, 1, p - 1);
  p := S.LastIndexOf('.');
  if p >= 0 then
    S := S.Substring(p + 1);
  Result := LowerCase(Trim(S));
end;

// Klasse einer Methodenimplementierung: 'TOuter.TInner.DoIt' -> 'tinner';
// ohne Punkt ''.
function StrictMethodClassKey(const AMethodName: string): string;
var
  S : string;
  p : Integer;
begin
  Result := '';
  S := Trim(AMethodName);
  p := S.LastIndexOf('.');
  if p < 0 then Exit;
  Result := StrictTypeKey(S.Substring(0, p));
end;

// Erste Elternklasse aus nkClass.TypeRef ('TObject IInterface' -> 'tobject');
// '' ohne Elternliste.
function StrictParentKey(const ATypeRef: string): string;
var
  S : string;
  p : Integer;
begin
  S := Trim(ATypeRef);
  p := Pos(' ', S);
  if p > 0 then
    S := Copy(S, 1, p - 1);
  Result := StrictTypeKey(S);
end;

procedure TTypeResolver.AddStrictClass(C: TAstNode);
var
  Key     : string;
  Members : TDictionary<string, string>;
  Ch, G   : TAstNode;

  procedure AddMember(M: TAstNode);
  begin
    case M.Kind of
      nkField:    AddStrictIdent(Members, LowerCase(Trim(M.Name)), BareTypeOf(M.TypeRef));
      nkProperty: AddStrictIdent(Members, LowerCase(Trim(M.Name)), '');
      nkMethod:   AddStrictIdent(Members, StrictTypeKey(M.Name), '');
    end;
  end;

begin
  Key := StrictTypeKey(C.Name);
  if Key = '' then Exit;
  if FMembers.ContainsKey(Key) then
  begin
    FAmbigClasses.AddOrSetValue(Key, True);
    Exit;
  end;
  Members := TDictionary<string, string>.Create;
  FMembers.Add(Key, Members);
  if C.Kind = nkClass then
    FParents.AddOrSetValue(Key, StrictParentKey(C.TypeRef))
  else
    FParents.AddOrSetValue(Key, '');
  for Ch in C.Children do
    if Ch.Kind = nkVisibilitySection then
    begin
      for G in Ch.Children do
        AddMember(G);
    end
    else
      AddMember(Ch);
end;

// Inline-Variable mit der Spanne ihres Blocks APar eintragen: ab der
// Deklarationszeile bis zur letzten Knotenzeile des Blocks ('for var i'
// haengt am nkForStmt, 'var x' am umschliessenden nkBlock/Zweig).
procedure AddInlineVar(Sc: TTypeResolver.TMethodScope; N, APar: TAstNode;
  const AId, AType: string);
var
  V : TTypeResolver.TInlineVar;
begin
  if AId = '' then Exit;
  V.Id        := AId;
  V.TypeLow   := AType;
  V.LineStart := N.Line;
  V.LineEnd   := TAstSpans.SubtreeMaxLine(APar);
  if V.LineEnd < V.LineStart then V.LineEnd := V.LineStart;
  Sc.Inline := Sc.Inline + [V];
end;

// Typ der Inline-Variablen IdentLow an Line: die engste Spanne gewinnt;
// zwei gleich enge Spannen mit verschiedenem Typ sind mehrdeutig (AType
// ''). False: keine Inline-Variable dieses Namens deckt die Zeile.
function TryInlineTypeAt(Sc: TTypeResolver.TMethodScope;
  const IdentLow: string; Line: Integer; out AType: string): Boolean;
var
  i, BestSpan, Span : Integer;
begin
  AType  := '';
  Result := False;
  BestSpan := MaxInt;
  for i := 0 to High(Sc.Inline) do
  begin
    if Sc.Inline[i].Id <> IdentLow then Continue;
    if (Line < Sc.Inline[i].LineStart) or (Line > Sc.Inline[i].LineEnd) then
      Continue;
    Span := Sc.Inline[i].LineEnd - Sc.Inline[i].LineStart;
    if (not Result) or (Span < BestSpan) then
    begin
      Result   := True;
      BestSpan := Span;
      AType    := Sc.Inline[i].TypeLow;
    end
    else if (Span = BestSpan) and (AType <> Sc.Inline[i].TypeLow) then
      AType := '';
  end;
end;

// Name der Routine an Line: erst die Inline-Variablen (Blockspanne), dann
// Parameter, Sektions-Variablen und Result. True = die Routine kennt den
// Namen; AType '' heisst dann mehrdeutig.
function TryRoutineTypeAt(Sc: TTypeResolver.TMethodScope;
  const IdentLow: string; Line: Integer; out AType: string): Boolean;
begin
  Result := TryInlineTypeAt(Sc, IdentLow, Line, AType);
  if Result then Exit;
  Result := Sc.Idents.TryGetValue(IdentLow, AType);
  if Result and (AType = STRICT_AMBIGUOUS) then
    AType := '';
end;

function TTypeResolver.StrictBodyNode(Sc: TMethodScope;
  N, APar: TAstNode): Boolean;
var
  i : Integer;
begin
  Result := True;
  case N.Kind of
    nkTypeSection, nkClass, nkRecord, nkTypeAlias, nkEnumType, nkMethod:
      Result := False;
    nkParam:
      AddStrictIdent(Sc.Idents, BareIdentLow(N.Name), BareTypeOf(N.TypeRef));
    nkLocalVar:
      if APar.Kind = nkMethod then
        AddStrictIdent(Sc.Idents, LowerCase(Trim(N.Name)), BareTypeOf(N.TypeRef))
      else
        AddInlineVar(Sc, N, APar, LowerCase(Trim(N.Name)), BareTypeOf(N.TypeRef));
    nkConstSection:
      if APar.Kind <> nkMethod then
      begin
        for i := 0 to N.Children.Count - 1 do
          if N.Children[i].Kind = nkField then
            AddInlineVar(Sc, N.Children[i], APar,
              LowerCase(Trim(N.Children[i].Name)),
              BareTypeOf(N.Children[i].TypeRef));
        Result := False;
      end;
    nkField:
      AddStrictIdent(Sc.Idents, LowerCase(Trim(N.Name)), BareTypeOf(N.TypeRef));
  end;
end;

procedure TTypeResolver.AddStrictMethod(M: TAstNode);
var
  Sc      : TMethodScope;
  Stack   : TList<TAstNode>;
  Parents : TList<TAstNode>;   // Elternknoten je Stack-Eintrag
  N, Ch   : TAstNode;
  Par     : TAstNode;
  i       : Integer;
  RetLow  : string;
begin
  Sc := TMethodScope.Create;
  FScopes.Add(Sc);
  Sc.LineStart := M.Line;
  Sc.LineEnd   := TAstSpans.SubtreeMaxLine(M);
  Sc.ClassKey  := StrictMethodClassKey(M.Name);
  // 'TOuter.TInner.Go': zwei Qualifizierer - ein verschachtelter Typ.
  Sc.NestedType := Length(M.Name) - Length(StringReplace(M.Name, '.', '',
    [rfReplaceAll])) >= 2;
  TAstSpans.CollectNestedSpans(M, Sc.NestStarts, Sc.NestEnds);
  // Parameter, lokale Variablen und lokale typisierte Konstanten (nkField
  // in der const-Sektion der Routine). Lokale Typ-Sektionen nicht
  // betreten: Felder eines lokalen Records oder die Parameter eines
  // lokalen Prozedurtyps sind keine Namen der Routine. Der Elternknoten
  // entscheidet, was INLINE ist: ein nkLocalVar direkt unter nkMethod
  // stammt aus der var-Sektion, jedes andere aus dem Rumpf ('for var',
  // 'var x' im Block) und gilt nur in seiner Blockspanne; eine
  // nkConstSection unter einem Block ist eine Inline-Konstante.
  Stack := TList<TAstNode>.Create;
  Parents := TList<TAstNode>.Create;
  try
    for i := M.Children.Count - 1 downto 0 do
    begin
      Stack.Add(M.Children[i]);
      Parents.Add(M);
    end;
    while Stack.Count > 0 do
    begin
      N   := Stack[Stack.Count - 1];
      Par := Parents[Parents.Count - 1];
      Stack.Delete(Stack.Count - 1);
      Parents.Delete(Parents.Count - 1);
      if not StrictBodyNode(Sc, N, Par) then Continue;
      for i := N.Children.Count - 1 downto 0 do
      begin
        Ch := N.Children[i];
        Stack.Add(Ch);
        Parents.Add(N);
      end;
    end;
  finally
    Parents.Free;
    Stack.Free;
  end;
  RetLow := ExtractReturnTypeLow(M.TypeRef);
  if RetLow <> '' then
    AddStrictIdent(Sc.Idents, 'result', RetLow);
end;

procedure TTypeResolver.BuildStrict(UnitNode: TAstNode);
var
  Stack : TList<TAstNode>;
  N     : TAstNode;
  i     : Integer;
begin
  // Ein iterativer Gang ueber die Unit-Ebene: Klassen/Records und Routinen
  // werden als Ganzes uebernommen und nicht weiter betreten; ein nkField,
  // das dabei uebrig bleibt, steht in var/const auf Unit-Ebene.
  Stack := TList<TAstNode>.Create;
  try
    Stack.Add(UnitNode);
    while Stack.Count > 0 do
    begin
      N := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);
      case N.Kind of
        nkClass, nkRecord:
          begin
            AddStrictClass(N);
            Continue;
          end;
        nkMethod:
          begin
            AddStrictMethod(N);
            Continue;
          end;
        nkField:
          AddStrictIdent(FGlobals, LowerCase(Trim(N.Name)), BareTypeOf(N.TypeRef));
      end;
      for i := N.Children.Count - 1 downto 0 do
        Stack.Add(N.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

function TTypeResolver.ResolveStrict(const IdentLow: string;
  Line: Integer): string;
var
  Sc, Best : TMethodScope;
  BestSpan : Integer;
  T, Key   : string;
  Parent   : string;
  Members  : TDictionary<string, string>;
  i, Depth : Integer;
begin
  Result := '';
  Best := nil; BestSpan := MaxInt;
  for Sc in FScopes do
    if (Line >= Sc.LineStart) and (Line <= Sc.LineEnd) then
      if (Sc.LineEnd - Sc.LineStart) < BestSpan then
      begin
        Best := Sc; BestSpan := Sc.LineEnd - Sc.LineStart;
      end;
  if Best <> nil then
  begin
    // Verschachtelte Routine: ihre Deklarationen kennt der AST nicht.
    for i := 0 to High(Best.NestStarts) do
      if (Line >= Best.NestStarts[i]) and (Line <= Best.NestEnds[i]) then
        Exit;
    // Namen der Routine: eine Inline-Variable, deren Block die Zeile
    // deckt, verdeckt alles Weitere - ausserhalb ihrer Spanne existiert
    // sie nicht; sonst Parameter/Sektion/Result.
    if TryRoutineTypeAt(Best, IdentLow, Line, T) then
    begin
      Result := T;
      Exit;
    end;
    if Best.NestedType then
      Exit;   // Member der aeusseren Klasse unbekannt
    // Member der eigenen Klasse und ihrer Vorfahren in dieser Unit.
    Key := Best.ClassKey;
    Depth := 0;
    while (Key <> '') and (Key <> 'tobject') do
    begin
      if FAmbigClasses.ContainsKey(Key)
         or not FMembers.TryGetValue(Key, Members) then
        Exit;   // Klasse unbekannt oder mehrdeutig: jeder Name kann ein Member sein
      if Members.TryGetValue(IdentLow, T) then
      begin
        if T <> STRICT_AMBIGUOUS then
          Result := T;
        Exit;
      end;
      Inc(Depth);
      if Depth >= STRICT_MAX_ANCESTORS then
        Exit;
      // Eigene Variable fuer das Ergebnis: Key als const UND out hiesse,
      // der out-String wird vor dem Lesen des Schluessels geleert.
      if not FParents.TryGetValue(Key, Parent) then
        Exit;
      Key := Parent;
    end;
  end;
  if FGlobals.TryGetValue(IdentLow, T) and (T <> STRICT_AMBIGUOUS) then
    Result := T;
end;

procedure TTypeResolver.ForgetClass(const AName: string);
var
  Key : string;
begin
  if not FStrict then Exit;
  Key := StrictTypeKey(AName);
  if Key <> '' then
    FAmbigClasses.AddOrSetValue(Key, True);
end;

function TTypeResolver.ResolveTypeAt(const IdentLow: string; Line: Integer): string;
var
  Sc, Best : TMethodScope;
  BestSpan : Integer;
  T        : string;
begin
  Result := '';
  if IdentLow = '' then Exit;
  if FStrict then
    Exit(ResolveStrict(IdentLow, Line));

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

function TTypeResolver.ResolvesToLocalClassOrRecord(const VarName: string;
  Line: Integer): Boolean;
var
  T : string;
begin
  T := ResolveTypeAt(LowerCase(Trim(VarName)), Line);
  Result := (T <> '') and FClassRecordNames.ContainsKey(T);
end;

end.

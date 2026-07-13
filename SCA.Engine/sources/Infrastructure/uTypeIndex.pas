unit uTypeIndex;

// Repo-weiter Cross-Unit-Typ-Index (Konzept_StrukturellePhase Track C).
//
// Stellt fuer spaetere Detektor-Opt-ins (SCA114/161/174/124) zwei Dinge
// bereit, die single-file nicht sicher entscheidbar sind:
//   * Typ-KIND je Name (Klasse / Record / Enum / Alias) - z.B. um Value-Types
//     (records) von Reference-Types (classes) zu unterscheiden.
//   * Klassen-ELTERNKETTE ueber ALLE Scan-Units (ParentOf / IsDescendantOf) -
//     z.B. um "erbt von TThread / TComponent" cross-unit aufzuloesen.
//
// Aufbau-Modell (1:1 analog uSymbolReferenceIndex), single-Pass:
//   * Aufrufer (TStaticAnalyzer2) ruft Build(FileList, AstFileCache) einmal
//     pro Scan - aus DEMSELBEN AstFileCache wie SymbolRefIndex/DfmRepoIndex,
//     also KEIN Doppel-Parse (nur ein zusaetzlicher AST-Walk pro Datei).
//   * Pro Datei: FindAll(nkClass/nkRecord/nkEnumType/nkTypeAlias) und
//     Name->Kind + Klassenname->Parent in interne Dictionaries eintragen
//     (Keys durchgaengig lowercased).
//   * Nach dem Scan: SeedKnownTypes belegt bekannte RTL-Value-Type-Records
//     vor (die RTL-Units liegen ueblicherweise NICHT im Scan-Scope).
//
// Bewusste Vereinfachungen / Caveats:
//   * Der aktuelle Parser produziert KEINE nkEnumType-Knoten: Enum-Deklara-
//     tionen (`TColor = (clRed, clBlue)`) landen als nkTypeAlias (siehe
//     uParser2 ParseTypeSection else-Zweig). FindAll(nkEnumType) ist daher
//     heute leer; der Kind wird trotzdem strukturell korrekt behandelt, falls
//     der Parser ihn spaeter erzeugt. Enums sind bis dahin tkiAlias.
//   * Interfaces fuehrt der Parser ebenfalls als nkClass (uParser2 Z.721) ->
//     sie werden als tkiClass klassifiziert. Fuer die Elternketten-Frage
//     (IsDescendantOf) unschaedlich.
//   * Homonyme Typnamen ueber mehrere Units: "letzte Datei gewinnt"
//     (AddOrSetValue). Akzeptabel fuer eine Grob-Klassifikation.
//   * Wir tracken nur den BASE-Klassennamen (erstes Ident der Parent-Liste);
//     implementierte Interfaces (`class(TBase, IFoo)`) werden fuer die Kette
//     ignoriert.
//
// INERTE INFRA (Runde 1): KEIN Detektor liest diesen Index. Der Build-Block
// in TStaticAnalyzer2 ist rein additiv (nil-Fallback via CtxTypeIndex) -> das
// Scan-Verhalten bleibt byte-identisch. Detektor-Opt-ins + Tests folgen in
// Runde 2/3.
//
// Single-File-Pfad: wird Build nie aufgerufen (AContext=nil, Tests/Single-
// File), ist der Index leer (IsEmpty=True); TypeKindOf liefert tkiUnknown und
// IsDescendantOf False - exakt das heutige Verhalten ohne Cross-Unit-Wissen.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uAstFileCache;

type
  // Grob-Klassifikation eines Typnamens (Lookup-Key = lowercased Name).
  // tkiUnknown = nicht im Index (Default). Reihenfolge unkritisch, aber
  // tkiUnknown bewusst als Ordinal 0 (= Default(T) bei TryGetValue-Miss).
  TTypeIndexKind = (tkiUnknown, tkiClass, tkiRecord, tkiEnum, tkiAlias);

  TTypeIndex = class
  private
    // Per-Scan-AST-Cache (von Build gesetzt, wie bei uSymbolReferenceIndex).
    FAstCache : TAstFileCache;
    // Typname-lowercase -> Kind (Klasse/Record/Enum/Alias).
    FKinds    : TDictionary<string, TTypeIndexKind>;
    // Klassenname-lowercase -> Basisklassen-Name-lowercase. Nur Eintraege mit
    // explizitem Parent; implizit-TObject-Klassen fehlen hier (Kette endet).
    FParents  : TDictionary<string, string>;

    procedure ScanUnitForTypes(const PasFileName: string);
    procedure AddTypesFromNode(RootNode: TAstNode);
    procedure SeedKnownTypes;
  public
    constructor Create;
    destructor  Destroy; override;

    // Repo-weiten Scan ueber alle Pas-Dateien durchfuehren (einmal pro Scan).
    procedure Build(FileList: TStringList; ACache: TAstFileCache = nil);

    // Kind eines Typnamens (case-insensitiv). tkiUnknown wenn unbekannt.
    function TypeKindOf(const NameLow: string): TTypeIndexKind;

    // Direkter Basisklassen-Name (lowercased) oder '' wenn kein Parent
    // bekannt (implizit TObject / unbekannter Typ).
    function ParentOf(const NameLow: string): string;

    // True, wenn NameLow gleich BaseLow ist ODER (transitiv) von BaseLow
    // erbt - analog TObject.InheritsFrom (inklusive Self). Unbekannte Basen
    // und abgerissene Ketten liefern False; Zyklus- und Tiefen-Guard
    // (MAX_ANCESTOR_DEPTH) verhindern Endlosschleifen.
    function IsDescendantOf(const NameLow, BaseLow: string): Boolean;

    // True wenn der Index leer ist (Build nie gelaufen = Single-File-Mode).
    function IsEmpty: Boolean;
  end;

implementation

// noinspection-file CanBeClassMethod, CanBeUnitPrivate, TooLongLine, UnsortedUses, UnusedPublicMember
// Inerte Infra (Runde 1): die Public-API wird noch von keinem Detektor
// konsumiert - UnusedPublicMember ist hier erwartet, nicht tot.

uses
  uParser2;

const
  // Zyklus-/Tiefen-Schutz fuer die Elternketten-Traversierung. 32 ist weit
  // jenseits jeder realen Delphi-Vererbungstiefe; kaputte/zyklische Daten
  // brechen so garantiert ab (zusaetzlich zum Visited-Set).
  MAX_ANCESTOR_DEPTH = 32;

// Extrahiert den Basisklassen-Namen (lowercased) aus dem TypeRef eines
// nkClass-Knotens. TypeRef ist die space-separierte Parent-Liste, die
// ParseClassBody ablegt (z.B. 'TForm' oder 'TBase IFoo IBar'); das ERSTE
// Ident ist die Basisklasse, der Rest sind Interfaces. Generic-Suffixe
// (`TObjectDictionary<K, V>`) werden zuerst gekappt, damit ein Leerzeichen
// INNERHALB der Generic-Argumente nicht faelschlich als Trenner zaehlt.
function BaseClassNameLow(const RawTypeRef: string): string;
var
  S : string;
  P : Integer;
begin
  S := Trim(RawTypeRef);
  if S = '' then Exit('');
  P := Pos('<', S);
  if P > 0 then S := Trim(Copy(S, 1, P - 1));
  P := Pos(' ', S);
  if P > 0 then S := Trim(Copy(S, 1, P - 1));
  Result := LowerCase(S);
end;

constructor TTypeIndex.Create;
begin
  inherited;
  FKinds   := TDictionary<string, TTypeIndexKind>.Create;
  FParents := TDictionary<string, string>.Create;
end;

destructor TTypeIndex.Destroy;
begin
  FParents.Free;
  FKinds.Free;
  inherited;
end;

procedure TTypeIndex.AddTypesFromNode(RootNode: TAstNode);
var
  Nodes : TList<TAstNode>;
  N : TAstNode;
  NameLow, ParentLow : string;
begin
  if RootNode = nil then Exit;

  // Klassen (inkl. Interfaces, die der Parser ebenfalls als nkClass ablegt):
  // Name = Klassenname, TypeRef = Parent-Liste (erstes Ident = Basisklasse).
  Nodes := RootNode.FindAll(nkClass);
  try
    for N in Nodes do
    begin
      NameLow := LowerCase(Trim(N.Name));
      if NameLow = '' then Continue;
      FKinds.AddOrSetValue(NameLow, tkiClass);
      ParentLow := BaseClassNameLow(N.TypeRef);
      if ParentLow <> '' then
        FParents.AddOrSetValue(NameLow, ParentLow)
      else
        // Implizit TObject / kein Parent: einen ggf. vom Homonym aus einer
        // frueheren Datei gesetzten Stale-Parent entfernen ("letzte gewinnt").
        FParents.Remove(NameLow);
    end;
  finally
    Nodes.Free;
  end;

  // Records.
  Nodes := RootNode.FindAll(nkRecord);
  try
    for N in Nodes do
    begin
      NameLow := LowerCase(Trim(N.Name));
      if NameLow <> '' then FKinds.AddOrSetValue(NameLow, tkiRecord);
    end;
  finally
    Nodes.Free;
  end;

  // Enums (seit 2026-07-13 emittiert der Parser nkEnumType fuer 'T = (a, b, ..)').
  // GUARDED-Add wie beim Alias-Walk unten: nur eintragen, wenn der Name nicht
  // schon als Klasse/Record bekannt ist. So gewinnt eine echte Klassen-/Record-
  // Deklaration bei einem cross-unit-Homonym weiterhin (Verhalten identisch zur
  // Aera, in der Enums als nkTypeAlias liefen -> KEIN Ripple auf die tkiRecord-
  // Gates in uInstanceInvokedConstructor/uTObjectListWithoutOwnership). Enums
  // gewinnen aber ueber den nachfolgenden Alias-Fallback.
  Nodes := RootNode.FindAll(nkEnumType);
  try
    for N in Nodes do
    begin
      NameLow := LowerCase(Trim(N.Name));
      if (NameLow <> '') and not FKinds.ContainsKey(NameLow) then
        FKinds.Add(NameLow, tkiEnum);
    end;
  finally
    Nodes.Free;
  end;

  // Aliase (inkl. Enums beim aktuellen Parser). Nur eintragen wenn der Name
  // nicht bereits als Klasse/Record/Enum bekannt ist - eine echte Typdekla-
  // ration ist aussagekraeftiger als der Alias-Fallback.
  Nodes := RootNode.FindAll(nkTypeAlias);
  try
    for N in Nodes do
    begin
      NameLow := LowerCase(Trim(N.Name));
      if NameLow = '' then Continue;
      if not FKinds.ContainsKey(NameLow) then
        FKinds.Add(NameLow, tkiAlias);
    end;
  finally
    Nodes.Free;
  end;
end;

procedure TTypeIndex.ScanUnitForTypes(const PasFileName: string);
// Cache-Pfad (wie uSymbolReferenceIndex.ScanUnitForRefs): wenn FAstCache
// assigned, einmaliger Parse pro Repo-Lauf; der Cache besitzt das Root -
// NICHT freigeben. Ohne Cache eigener Parser + eigenes Root (OwnsRoot).
var
  Parser  : TParser2;
  Root    : TAstNode;
  OwnsRoot: Boolean;
begin
  if not FileExists(PasFileName) then Exit;
  OwnsRoot := False;

  if Assigned(FAstCache) then
    Root := FAstCache.Acquire(PasFileName)
  else
  begin
    Parser := TParser2.Create;
    try
      try
        Root := Parser.ParseFile(PasFileName);
        OwnsRoot := True;
      except
        // Defekte .pas - silent skip, wie bei uSymbolReferenceIndex.
        Exit;
      end;
    finally
      Parser.Free;
    end;
  end;

  if Root = nil then Exit;
  try
    AddTypesFromNode(Root);
  finally
    if OwnsRoot then Root.Free;
  end;
end;

procedure TTypeIndex.SeedKnownTypes;
// Konzept-Limitierung: RTL-Units (System.RegularExpressions, System.Types,
// System.Rtti, System.Diagnostics, System) liegen ueblicherweise NICHT im
// Scan-Scope. Ohne diese Seeds wuerde TypeKindOf fuer verbreitete RTL-Value-
// Type-Records tkiUnknown liefern und ein spaeterer Detektor-Opt-in (z.B.
// "record wird per := kopiert, nicht Free-pflichtig") sie fehlklassifizieren.
// Kuratierte Liste bekannter RTL-Records (bereits lowercased). Scan-Daten
// gewinnen: nur setzen, wenn der Name nicht schon aus einer Unit bekannt ist.
const
  SEED_RECORDS : array[0..8] of string = (
    'tregex',          // System.RegularExpressions
    'tnamevaluepair',  // System.Generics.Collections / System.Classes
    'trtticontext',    // System.Rtti
    'tsizef',          // System.Types
    'tpointf',         // System.Types
    'trectf',          // System.Types
    'tvalue',          // System.Rtti
    'tstopwatch',      // System.Diagnostics
    'tguid'            // System (record type)
  );
var
  i : Integer;
begin
  for i := Low(SEED_RECORDS) to High(SEED_RECORDS) do
    if not FKinds.ContainsKey(SEED_RECORDS[i]) then
      FKinds.Add(SEED_RECORDS[i], tkiRecord);
end;

procedure TTypeIndex.Build(FileList: TStringList; ACache: TAstFileCache);
// Single-Pass-Build: pro Datei AST holen (aus ACache, kein Doppel-Parse) und
// Typ-Deklarationen einsammeln. Danach RTL-Records vorbelegen.
var
  i : Integer;
begin
  FAstCache := ACache;
  if FileList <> nil then
    for i := 0 to FileList.Count - 1 do
      ScanUnitForTypes(FileList[i]);
  SeedKnownTypes;
end;

function TTypeIndex.TypeKindOf(const NameLow: string): TTypeIndexKind;
begin
  if not FKinds.TryGetValue(LowerCase(Trim(NameLow)), Result) then
    Result := tkiUnknown;
end;

function TTypeIndex.ParentOf(const NameLow: string): string;
begin
  if not FParents.TryGetValue(LowerCase(Trim(NameLow)), Result) then
    Result := '';
end;

function TTypeIndex.IsDescendantOf(const NameLow, BaseLow: string): Boolean;
var
  Cur, Nxt, BaseKey : string;
  Depth : Integer;
  Visited : TDictionary<string, Boolean>;
begin
  Result := False;
  Cur     := LowerCase(Trim(NameLow));
  BaseKey := LowerCase(Trim(BaseLow));
  if (Cur = '') or (BaseKey = '') then Exit;
  if Cur = BaseKey then Exit(True);   // inklusive Self (analog InheritsFrom)

  Visited := TDictionary<string, Boolean>.Create;
  try
    Depth := 0;
    while (Cur <> '') and (Depth < MAX_ANCESTOR_DEPTH) do
    begin
      if Visited.ContainsKey(Cur) then Break;  // Zyklus-Guard
      Visited.Add(Cur, True);
      if not FParents.TryGetValue(Cur, Nxt) then Break;  // Kette endet / unbekannt
      if Nxt = BaseKey then Exit(True);
      Cur := Nxt;
      Inc(Depth);
    end;
  finally
    Visited.Free;
  end;
end;

function TTypeIndex.IsEmpty: Boolean;
begin
  Result := FKinds.Count = 0;
end;

initialization

finalization

end.

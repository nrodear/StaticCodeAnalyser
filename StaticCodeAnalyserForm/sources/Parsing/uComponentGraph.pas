unit uComponentGraph;

// Komponentengraph aus dem DFM-Parsing - Phase 1 (Walking Skeleton).
//
// TComponentNode bildet einen einzelnen DFM-Knoten ab (object/inherited/inline)
// mit Name, Klasse, Eltern-/Kind-Verbindung und Position. Properties und
// Event-Bindungen sind in Phase 1 noch NICHT enthalten - sie kommen in
// Iteration 2 (Properties einlesen) bzw. Iteration 3 (Events + Binder).
//
// TComponentGraph haelt die Wurzel-Knoten (typisch ein Eintrag pro DFM-Datei).
// Helper "EnumerateAll" liefert eine flache Liste aller Knoten - praktisch
// fuer Detektoren wie fkDfmDefaultName, die nur den Namen brauchen.

interface

uses
  System.Generics.Collections, System.Generics.Defaults;

type
  // Klassifizierung des Property-Wert-Tokens, wie es aus dem Lexer kommt.
  // Damit koennen Detektoren typisiert auf Werte zugreifen, ohne den
  // RawValue selbst nochmal parsen zu muessen.
  TPropValueKind = (
    pvkUnknown,
    pvkString,     // 'Hallo' (RawValue ohne Anfuehrungszeichen, mit Escapes aufgeloest)
    pvkInteger,    // 42, -1, $00FF00FF
    pvkFloat,      // 1.5, 1e10
    pvkBool,       // True / False
    pvkIdent,      // clRed, alTop, DEFAULT_CHARSET, Btn1Click (Event-Handler)
    pvkSet,        // [fsBold, fsItalic]  (RawValue inkl. eckiger Klammern)
    pvkBinary,     // {01 02 FF}          (RawValue leer, nur Marker)
    pvkItemList,   // <item ... end>      (RawValue inkl. spitzer Klammern)
    pvkStrList     // ('a' 'b')           (RawValue inkl. runder Klammern)
  );

  TPropValue = record
    Kind     : TPropValueKind;
    RawValue : string;   // Lexer-Token-Wert (bei String: ohne '', mit Escape-Aufloesung)
    Line     : Integer;
    Col      : Integer;

    // Typisierte Convenience-Accessors. Liefern ADefault wenn Kind
    // nicht zum erwarteten Typ passt oder RawValue nicht parsbar ist -
    // Detektoren bekommen so eine garantiert sinnvolle Antwort und
    // muessen sich nicht selbst um Casing / Whitespace / Klammerung
    // kuemmern. Wichtig: DFMs schreiben nur Properties, deren Wert vom
    // VCL-Default abweicht. Wenn TryGetProperty('Visible', V) False
    // liefert, ist die Komponente effektiv sichtbar. Deshalb haben die
    // ADefault-Parameter Bedeutung - Aufrufer setzt den VCL-Default.
    function AsBoolean(ADefault: Boolean = False): Boolean;
    function AsInteger(ADefault: Integer = 0): Integer;
    function AsString(const ADefault: string = ''): string;
    function AsIdent(const ADefault: string = ''): string;
    // SetContains: prueft case-insensitiv, ob das Set 'AMember' enthaelt.
    // RawValue hat hier die Form '[fsBold, fsItalic]'. Robust gegen
    // Whitespace, Tabs und beliebige Reihenfolge.
    function SetContains(const AMember: string): Boolean;
  end;

  TComponentNode = class
  private
    FChildren   : TObjectList<TComponentNode>;
    FProperties : TDictionary<string, TPropValue>;
  public
    Name         : string;          // Komponenten-Instanz-Name, z.B. 'btnGo'
    ClassRef     : string;          // Klassen-Name, z.B. 'TButton'
    Parent       : TComponentNode;  // nil bei Root
    Line         : Integer;         // Zeile des 'object'/'inherited'/'inline'
    Col          : Integer;
    IsInherited  : Boolean;         // 'inherited Foo: ...' (Form-Vererbung)
    IsInline     : Boolean;         // 'inline Foo: ...' (Frame-Inlining)

    constructor Create(const AName, AClassRef: string; ALine, ACol: Integer);
    destructor  Destroy; override;

    function Add(const AName, AClassRef: string; ALine, ACol: Integer): TComponentNode;

    // Property speichern (qualifizierter Pfad wie 'Font.Style' bleibt als
    // Key erhalten). Mehrfach-Zuweisung: letzte gewinnt.
    procedure SetProperty(const APath: string; const AValue: TPropValue);
    // Property suchen (case-insensitive Lookup, weil der DFM-Reader Property-
    // Pfade in Original-Schreibweise vorhaelt, Detektoren aber nicht raten
    // sollen). Liefert False wenn nicht vorhanden.
    function  TryGetProperty(const APath: string; out AValue: TPropValue): Boolean;
    // Boolesche Bequemlichkeit fuer "hat Property X ueberhaupt einen Wert"
    function  HasProperty(const APath: string): Boolean; inline;

    // Typisierte Property-Reads mit VCL-Default-Verhalten: Wenn die
    // Property im DFM nicht steht (DFM serialisiert nur Abweichungen
    // vom Default), bekommt der Aufrufer ADefault zurueck. Damit muss
    // ein Detektor weder TryGetProperty/Kind/Cast selber bauen noch
    // auf "Property fehlt -> nehme implizit VCL-Default" raten.
    function GetBoolean(const APath: string; ADefault: Boolean = False): Boolean;
    function GetInteger(const APath: string; ADefault: Integer = 0): Integer;
    function GetString (const APath: string; const ADefault: string = ''): string;
    function GetIdent  (const APath: string; const ADefault: string = ''): string;
    // Set-Property enthaelt Member? Praktisch fuer Style-Sets
    // (Font.Style=[fsBold,fsItalic]), Anchors, BorderStyle-Optionen.
    function SetPropertyContains(const APath, AMember: string): Boolean;

    property Children:   TObjectList<TComponentNode>     read FChildren;
    property Properties: TDictionary<string, TPropValue> read FProperties;
  end;

  TComponentGraph = class
  private
    FRoots: TObjectList<TComponentNode>;
  public
    constructor Create;
    destructor  Destroy; override;

    function AddRoot(const AName, AClassRef: string; ALine, ACol: Integer): TComponentNode;

    // Flache Liste aller Knoten (Roots inkl. Children rekursiv).
    // Aufrufer ist Eigentümer der Liste und gibt sie frei. Knoten gehören
    // weiter dem Graph - die Liste ist eine reine Referenz-Sammlung.
    function EnumerateAll: TList<TComponentNode>;

    // Knoten per Name suchen (case-insensitive, erster Treffer im
    // depth-first walk). Liefert nil wenn nicht gefunden.
    function FindByName(const AName: string): TComponentNode;

    property Roots: TObjectList<TComponentNode> read FRoots;
  end;

implementation

uses
  System.SysUtils, System.StrUtils;

{ TPropValue }

function TPropValue.AsBoolean(ADefault: Boolean): Boolean;
begin
  // RawValue ist hier 'True' oder 'False' (Lexer-Keyword-Casing).
  // SameText macht uns case-insensitive falls jemand das Format
  // upstream veraendert.
  if Kind <> pvkBool then Exit(ADefault);
  if SameText(RawValue, 'True')  then Exit(True);
  if SameText(RawValue, 'False') then Exit(False);
  Result := ADefault;
end;

function TPropValue.AsInteger(ADefault: Integer): Integer;
begin
  // pvkInteger: RawValue ist '42', '-1', '$00FF00FF'. Delphis
  // StrToIntDef behandelt das '$'-Hex-Praefix korrekt.
  // Auch pvkFloat erlauben fuer Integer-getaggte Werte, die im DFM
  // aus historischen Gruenden als Float landen koennen (selten).
  if (Kind <> pvkInteger) and (Kind <> pvkFloat) then Exit(ADefault);
  Result := StrToIntDef(RawValue, ADefault);
end;

function TPropValue.AsString(const ADefault: string): string;
begin
  if Kind = pvkString then
    Result := RawValue
  else
    Result := ADefault;
end;

function TPropValue.AsIdent(const ADefault: string): string;
begin
  // Trim raeumt Whitespace weg, der durch Parser-Sonderfaelle (Sign-
  // Combine etc.) am Anfang/Ende landen koennte - in der Praxis sollte
  // RawValue hier sauber sein.
  if Kind = pvkIdent then
    Result := Trim(RawValue)
  else
    Result := ADefault;
end;

function TPropValue.SetContains(const AMember: string): Boolean;
var
  Inner : string;
  Items : TArray<string>;
  i     : Integer;
begin
  Result := False;
  if Kind <> pvkSet then Exit;
  if AMember = '' then Exit;
  // RawValue: '[fsBold, fsItalic]' oder '[ ]' oder '[fsBold]'
  Inner := Trim(RawValue);
  if (Length(Inner) >= 2) and (Inner[1] = '[') and
     (Inner[High(Inner)] = ']') then
    Inner := Copy(Inner, 2, Length(Inner) - 2);
  Inner := Trim(Inner);
  if Inner = '' then Exit;
  Items := SplitString(Inner, ',');
  for i := 0 to High(Items) do
    if SameText(Trim(Items[i]), AMember) then Exit(True);
end;

{ TComponentNode }

constructor TComponentNode.Create(const AName, AClassRef: string;
  ALine, ACol: Integer);
begin
  inherited Create;
  Name        := AName;
  ClassRef    := AClassRef;
  Line        := ALine;
  Col         := ACol;
  FChildren   := TObjectList<TComponentNode>.Create(True);
  // Property-Dictionary mit case-insensitivem String-Comparer; der DFM-
  // Writer normalisiert Property-Namen, aber Detektoren sollen sich nicht
  // darauf verlassen muessen.
  FProperties := TDictionary<string, TPropValue>.Create(
    TIStringComparer.Ordinal);
end;

destructor TComponentNode.Destroy;
begin
  FProperties.Free;
  FChildren.Free;
  inherited;
end;

function TComponentNode.Add(const AName, AClassRef: string;
  ALine, ACol: Integer): TComponentNode;
begin
  Result := TComponentNode.Create(AName, AClassRef, ALine, ACol);
  Result.Parent := Self;
  FChildren.Add(Result);
end;

procedure TComponentNode.SetProperty(const APath: string;
  const AValue: TPropValue);
begin
  // AddOrSetValue: doppelte Property-Zuweisung im DFM (sollte der Writer nie
  // erzeugen, aber pathologische DFMs gibt es) gewinnt das letzte Vorkommen.
  FProperties.AddOrSetValue(APath, AValue);
end;

function TComponentNode.TryGetProperty(const APath: string;
  out AValue: TPropValue): Boolean;
begin
  Result := FProperties.TryGetValue(APath, AValue);
end;

function TComponentNode.HasProperty(const APath: string): Boolean;
begin
  Result := FProperties.ContainsKey(APath);
end;

function TComponentNode.GetBoolean(const APath: string;
  ADefault: Boolean): Boolean;
var
  V: TPropValue;
begin
  if TryGetProperty(APath, V) then
    Result := V.AsBoolean(ADefault)
  else
    Result := ADefault;
end;

function TComponentNode.GetInteger(const APath: string;
  ADefault: Integer): Integer;
var
  V: TPropValue;
begin
  if TryGetProperty(APath, V) then
    Result := V.AsInteger(ADefault)
  else
    Result := ADefault;
end;

function TComponentNode.GetString(const APath: string;
  const ADefault: string): string;
var
  V: TPropValue;
begin
  if TryGetProperty(APath, V) then
    Result := V.AsString(ADefault)
  else
    Result := ADefault;
end;

function TComponentNode.GetIdent(const APath: string;
  const ADefault: string): string;
var
  V: TPropValue;
begin
  if TryGetProperty(APath, V) then
    Result := V.AsIdent(ADefault)
  else
    Result := ADefault;
end;

function TComponentNode.SetPropertyContains(const APath, AMember: string): Boolean;
var
  V: TPropValue;
begin
  if TryGetProperty(APath, V) then
    Result := V.SetContains(AMember)
  else
    Result := False;
end;

{ TComponentGraph }

constructor TComponentGraph.Create;
begin
  inherited;
  FRoots := TObjectList<TComponentNode>.Create(True);
end;

destructor TComponentGraph.Destroy;
begin
  FRoots.Free;
  inherited;
end;

function TComponentGraph.AddRoot(const AName, AClassRef: string;
  ALine, ACol: Integer): TComponentNode;
begin
  Result := TComponentNode.Create(AName, AClassRef, ALine, ACol);
  Result.Parent := nil;
  FRoots.Add(Result);
end;

function TComponentGraph.EnumerateAll: TList<TComponentNode>;
// Iterative Sammlung (kein Rekursionsrisiko bei pathologischen DFMs - analog
// zum Pascal-uAstNode.FindAll/CollectAll).
var
  Stack : TStack<TComponentNode>;
  Node  : TComponentNode;
  I     : Integer;
begin
  Result := TList<TComponentNode>.Create;
  Stack  := TStack<TComponentNode>.Create;
  try
    // Roots in umgekehrter Reihenfolge pushen, damit das spätere Pop die
    // ursprüngliche Reihenfolge im Result liefert.
    for I := FRoots.Count - 1 downto 0 do
      Stack.Push(FRoots[I]);

    while Stack.Count > 0 do
    begin
      Node := Stack.Pop;
      Result.Add(Node);
      for I := Node.Children.Count - 1 downto 0 do
        Stack.Push(Node.Children[I]);
    end;
  finally
    Stack.Free;
  end;
end;

function TComponentGraph.FindByName(const AName: string): TComponentNode;
var
  All: TList<TComponentNode>;
  N  : TComponentNode;
begin
  Result := nil;
  All := EnumerateAll;
  try
    for N in All do
      if SameText(N.Name, AName) then
        Exit(N);
  finally
    All.Free;
  end;
end;

end.

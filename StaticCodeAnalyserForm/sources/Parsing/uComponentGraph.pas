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
  System.SysUtils;

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

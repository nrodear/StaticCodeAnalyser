unit uAstNode;

// Delphi-AST: Knotentypen und Baumstruktur.
//
// Jeder TAstNode repraesentiert ein syntaktisches Konstrukt. Children
// werden via TObjectList<TAstNode> mit OwnsObjects=True gehalten - der
// Parent ist Owner aller seiner Kinder, ein Free(root) gibt den
// kompletten Subtree frei.
//
// API-KATEGORIEN
//
//   * SUBTREE-WIDE SEARCH (walked rekursiv durch alle Descendants):
//       FindAll, FindFirst, HasChild, ChildCount
//       (HasDescendant, DescendantCount sind synonyme Aliase mit
//       expliziterem Namen)
//
//   * DIRECT-CHILDREN-ONLY (nur unmittelbare Kinder):
//       FindFirstChild, HasDirectChild, DirectChildCount
//
//   * MUTATION:
//       Add (neuer Knoten), AddChild (existierender Knoten + Ownership-
//       Transfer), AdoptChildrenFrom (alle Children eines anderen Nodes
//       uebernehmen)
//
// API-STOLPERFALLE: Trotz "Child" im Namen walken `HasChild` und
// `ChildCount` den kompletten Subtree, nicht nur die direkten Kinder.
// ~250 Detector-Aufrufer haengen an dem Verhalten - nicht aendern.
// Fuer neuen Code: bevorzugt `HasDescendant` / `DescendantCount` (gleiche
// Semantik, klarer Name) oder `HasDirectChild` / `DirectChildCount` wenn
// wirklich nur direkte Kinder gemeint sind.
//
// NICHT VERWENDETE KIND-KONSTANTEN
//
// nkLiteral, nkBinaryOp, nkUnaryOp, nkIndex, nkDot, nkDeref sind im
// Enum reserviert fuer einen spaeteren expressions-Subtree, werden vom
// aktuellen Parser aber nicht produziert. Detectors arbeiten auf der
// flachen Text-Repraesentation in nkAssign.TypeRef / nkCall.Name.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TNodeKind = (
    // --- Kompilationseinheit ---
    nkUnit, nkInterface, nkImplementation,
    // --- Klauseln ---
    nkUses, nkUsesItem,
    nkTypeSection, nkVarSection, nkConstSection,
    // --- Typdeklarationen ---
    nkClass, nkRecord, nkEnumType, nkTypeAlias,
    nkVisibilitySection,            // public / private / protected / published
    // --- Klassen-Member ---
    nkField, nkProperty, nkMethod,
    nkParam,
    // --- Methodenrumpf ---
    nkLocalVar,
    nkBlock,                        // begin ... end
    // --- Anweisungen ---
    nkAssign,
    nkCall,
    nkIfStmt, nkElseBranch,
    nkCaseStmt, nkCaseArm,
    nkForStmt, nkWhileStmt, nkRepeatStmt,
    nkTryExcept, nkTryFinally,
    nkExceptBlock, nkOnHandler,
    nkFinallyBlock,
    nkRaise, nkExit, nkBreak, nkContinue,
    nkInherited,
    // --- Ausdruecke (reserviert, vom aktuellen Parser nicht produziert) ---
    nkIdent, nkLiteral, nkBinaryOp, nkUnaryOp,
    nkIndex, nkDot, nkDeref,
    // --- Sonstiges ---
    nkUnknown
  );

  TAstNode = class
  public
    Kind     : TNodeKind;
    Name     : string;     // Bezeichner, Operator oder Literal-Text
    TypeRef  : string;     // Typname bei Var, Param, Field, Method
    Line     : Integer;
    Col      : Integer;
    Children : TObjectList<TAstNode>;

    constructor Create(AKind: TNodeKind; const AName: string = '';
      ALine: Integer = 0; ACol: Integer = 0);
    destructor Destroy; override;

    // === MUTATION ===

    // Erzeugt einen neuen Kindknoten und nimmt Ownership. Exception-safe:
    // wirft Children.Add unerwartet (OOM), wird der gerade erzeugte
    // Knoten freigegeben - kein Leak.
    function Add(AKind: TNodeKind; const AName: string = '';
      ALine: Integer = 0; ACol: Integer = 0): TAstNode;

    // Haengt einen bereits existierenden Knoten als Kind an. UEBERTRAEGT
    // OWNERSHIP an Self - ANode darf nach diesem Aufruf NICHT mehr manuell
    // freigegeben werden (Children.OwnsObjects=True greift). Bei
    // Free(Self) wird ANode mit freigegeben.
    function AddChild(ANode: TAstNode): TAstNode;

    // O(n)-Transfer aller Children von Source in Self (Original-Reihen-
    // folge), Source.Children wird geleert. Vorher: naive Delete(0)-
    // Loops waren O(n^2) - bei try-Bodies mit 1000+ Statements messbar
    // (Sekunden statt Millisekunden).
    // Exception-Sicherheit: wenn AddChild mitten im Loop wirft, gehoeren
    // die schon uebertragenen Items Self; die Source-Slots werden
    // genullt, sodass Source.OwnsObjects:=True die noch nicht
    // uebertragenen Items korrekt freigibt ohne Doppel-Free.
    procedure AdoptChildrenFrom(Source: TAstNode);

    // === SUBTREE-WIDE SEARCH ===
    // Wandern den kompletten Subtree iterativ (Pre-Order DFS) - kein
    // Stack-Overflow bei tiefen ASTs.

    // Liste mit Ownership-Transfer - Caller MUSS Result.Free aufrufen.
    function FindAll(AKind: TNodeKind): TList<TAstNode>;
    function FindFirst(AKind: TNodeKind): TAstNode;

    // Subtree-wide trotz "Child"-Namen (Legacy-API, 250+ Aufrufer).
    // Bevorzugt fuer neuen Code: HasDescendant / DescendantCount.
    function HasChild(AKind: TNodeKind): Boolean;
    function ChildCount(AKind: TNodeKind): Integer;
    function HasDescendant(AKind: TNodeKind): Boolean; inline;
    function DescendantCount(AKind: TNodeKind): Integer; inline;

    // === DIRECT-CHILDREN-ONLY ===
    // Iterieren nur ueber Children, nicht rekursiv. Fuer Detectors die
    // strukturelle Eigenschaften pruefen ("hat dieses Method-Node einen
    // direkten Block?") ohne in den Block-Body abzusteigen.
    function FindFirstChild(AKind: TNodeKind): TAstNode;
    function HasDirectChild(AKind: TNodeKind): Boolean;
    function DirectChildCount(AKind: TNodeKind): Integer;

  private
    procedure CollectAll(AKind: TNodeKind; const AList: TList<TAstNode>);
    function CountSubtree(AKind: TNodeKind): Integer;
  end;

  // Deprecated Wrapper - existiert nur fuer Backwards-Compat.
  // Neuer Code soll die globale NodeKindName-Funktion verwenden.
  TNodeKindName = record
    class function ToString(AKind: TNodeKind): string; static;
  end;

// Lesbare Bezeichnung fuer ein TNodeKind (fuer Logging, Dumps, Tests).
function NodeKindName(AKind: TNodeKind): string;

implementation

const
  // Single-Source-Of-Truth fuer die menschlich lesbaren Kind-Namen.
  // Reihenfolge MUSS exakt mit TNodeKind uebereinstimmen.
  KIND_NAMES: array[TNodeKind] of string = (
    'Unit','Interface','Implementation',
    'Uses','UsesItem',
    'TypeSection','VarSection','ConstSection',
    'Class','Record','EnumType','TypeAlias',
    'VisibilitySection',
    'Field','Property','Method',
    'Param',
    'LocalVar',
    'Block',
    'Assign','Call',
    'IfStmt','ElseBranch',
    'CaseStmt','CaseArm',
    'ForStmt','WhileStmt','RepeatStmt',
    'TryExcept','TryFinally',
    'ExceptBlock','OnHandler',
    'FinallyBlock',
    'Raise','Exit','Break','Continue',
    'Inherited',
    'Ident','Literal','BinaryOp','UnaryOp',
    'Index','Dot','Deref',
    'Unknown'
  );

function NodeKindName(AKind: TNodeKind): string;
begin
  Result := KIND_NAMES[AKind];
end;

{ TNodeKindName }

class function TNodeKindName.ToString(AKind: TNodeKind): string;
begin
  Result := NodeKindName(AKind);
end;

{ TAstNode }

constructor TAstNode.Create(AKind: TNodeKind; const AName: string;
  ALine, ACol: Integer);
begin
  inherited Create;
  Kind     := AKind;
  Name     := AName;
  Line     := ALine;
  Col      := ACol;
  Children := TObjectList<TAstNode>.Create(True);
end;

destructor TAstNode.Destroy;
begin
  Children.Free;
  inherited;
end;

function TAstNode.Add(AKind: TNodeKind; const AName: string;
  ALine, ACol: Integer): TAstNode;
begin
  Result := TAstNode.Create(AKind, AName, ALine, ACol);
  try
    Children.Add(Result);
  except
    Result.Free;
    raise;
  end;
end;

function TAstNode.AddChild(ANode: TAstNode): TAstNode;
begin
  Children.Add(ANode);
  Result := ANode;
end;

procedure TAstNode.AdoptChildrenFrom(Source: TAstNode);
var
  Transferred : Integer;
  i           : Integer;
begin
  if (Source = nil) or (Source = Self) then Exit;

  Source.Children.OwnsObjects := False;
  Transferred := 0;
  try
    while Transferred < Source.Children.Count do
    begin
      Children.Add(Source.Children[Transferred]);
      Inc(Transferred);
    end;
    Source.Children.Clear; // einmaliger O(n), kein Free (OwnsObjects=False)
  except
    // Schon uebertragene Items aus Source-Slots rauswerfen, damit das
    // Restore von OwnsObjects=True nicht doppelt freigibt. nil-Slots sind
    // beim spaeteren Free safe (TObject.Free check'd nil).
    for i := 0 to Transferred - 1 do
      Source.Children[i] := nil;
    Source.Children.OwnsObjects := True;
    raise;
  end;
end;

// === Subtree-Walks: iterative Pre-Order DFS via Work-Stack ============

procedure TAstNode.CollectAll(AKind: TNodeKind; const AList: TList<TAstNode>);
var
  Stack : TList<TAstNode>;
  Cur   : TAstNode;
  i     : Integer;
begin
  Stack := TList<TAstNode>.Create;
  try
    Stack.Add(Self);
    while Stack.Count > 0 do
    begin
      Cur := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);
      if (Cur <> Self) and (Cur.Kind = AKind) then
        AList.Add(Cur);
      // Children in umgekehrter Reihenfolge auf Stack -> Pop in
      // links-rechts-Pre-Order.
      for i := Cur.Children.Count - 1 downto 0 do
        Stack.Add(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

function TAstNode.CountSubtree(AKind: TNodeKind): Integer;
// Wie CollectAll, aber zaehlt nur statt zu sammeln - spart die Liste-
// Allokation fuer reine Count-Queries.
var
  Stack : TList<TAstNode>;
  Cur   : TAstNode;
  i     : Integer;
begin
  Result := 0;
  Stack := TList<TAstNode>.Create;
  try
    Stack.Add(Self);
    while Stack.Count > 0 do
    begin
      Cur := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);
      if (Cur <> Self) and (Cur.Kind = AKind) then
        Inc(Result);
      for i := Cur.Children.Count - 1 downto 0 do
        Stack.Add(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

function TAstNode.FindAll(AKind: TNodeKind): TList<TAstNode>;
begin
  Result := TList<TAstNode>.Create;
  CollectAll(AKind, Result);
end;

function TAstNode.FindFirst(AKind: TNodeKind): TAstNode;
var
  Stack : TList<TAstNode>;
  Cur   : TAstNode;
  i     : Integer;
begin
  Result := nil;
  Stack  := TList<TAstNode>.Create;
  try
    Stack.Add(Self);
    while Stack.Count > 0 do
    begin
      Cur := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);
      if (Cur <> Self) and (Cur.Kind = AKind) then
        Exit(Cur);
      for i := Cur.Children.Count - 1 downto 0 do
        Stack.Add(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

function TAstNode.HasChild(AKind: TNodeKind): Boolean;
begin
  Result := Assigned(FindFirst(AKind));
end;

function TAstNode.ChildCount(AKind: TNodeKind): Integer;
begin
  Result := CountSubtree(AKind);
end;

function TAstNode.HasDescendant(AKind: TNodeKind): Boolean;
begin
  Result := HasChild(AKind);
end;

function TAstNode.DescendantCount(AKind: TNodeKind): Integer;
begin
  Result := ChildCount(AKind);
end;

// === Direct-Children-Only ============================================

function TAstNode.FindFirstChild(AKind: TNodeKind): TAstNode;
var
  i : Integer;
begin
  Result := nil;
  for i := 0 to Children.Count - 1 do
    if Children[i].Kind = AKind then
      Exit(Children[i]);
end;

function TAstNode.HasDirectChild(AKind: TNodeKind): Boolean;
begin
  Result := Assigned(FindFirstChild(AKind));
end;

function TAstNode.DirectChildCount(AKind: TNodeKind): Integer;
var
  i : Integer;
begin
  Result := 0;
  for i := 0 to Children.Count - 1 do
    if Children[i].Kind = AKind then
      Inc(Result);
end;

end.

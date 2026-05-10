unit uFormBinder;

// Verbindet einen DFM-Komponentengraph mit dem Pascal-AST der zugehoerigen
// Form-Klasse. Phase-1-Annahme: der Root des Graphs (z.B. 'Form2: TForm2')
// hat eine Klassen-Deklaration mit gleichem Namen in derselben Unit. Cross-
// Unit-Resolution (Frames, inherited Forms, DataModule-Referenzen) ist
// Phase-2-Thema.
//
// Was hier passiert:
//   1. Klasse mit Namen = Graph.Roots[0].ClassRef im AST suchen.
//   2. Aus der Klasse die published Fields/Methoden sammeln (case-insensitiv
//      indexiert, weil Delphi-Identifier nicht case-sensitiv sind).
//   3. Aus dem Implementation-Block die qualifizierten Methoden-Definitionen
//      'ClassName.MethodName' sammeln (Lookup-Key = nur MethodName).
//   4. Aus dem Graph alle Event-Properties extrahieren (Name beginnt mit
//      'On', drittes Zeichen Grossbuchstabe, Wert ist Identifier).
//
// TFormBinding ist Klasse statt Record, damit der Lifetime der inneren
// Dictionaries klar dem Aufrufer gehoert (Free in einem Schritt). Der
// UnitNode selbst bleibt im Besitz des Aufrufers (typisch: der
// TDfmAnalysisRunner, der den Parser fuhr).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uComponentGraph;

type
  TBoundEvent = record
    Component   : TComponentNode;
    EventName   : string;     // 'OnClick'
    HandlerName : string;     // 'btnGoClick' (RawValue der Property)
    Line        : Integer;    // DFM-Zeile der Bindung (Property-Zeile)
  end;

  TFormBinding = class
  private
    FUnitNode         : TAstNode;
    FFormClass        : TAstNode;
    FFormNode         : TComponentNode;
    FEvents           : TList<TBoundEvent>;
    FPublishedFields  : TDictionary<string, TAstNode>;
    FPublishedMethods : TDictionary<string, TAstNode>;
    FMethodImpls      : TDictionary<string, TAstNode>;
  public
    constructor Create;
    destructor  Destroy; override;

    // Auflöser fuer Event-Handler. Liefert zuerst die Implementation, wenn
    // vorhanden, sonst die Class-Signatur. nil wenn weder noch -> der
    // DeadEvent-Detektor.
    function ResolveHandler(const HandlerName: string): TAstNode;
    // Reine Existenz-Pruefung.
    function HasHandler(const HandlerName: string): Boolean;

    property UnitNode         : TAstNode                  read FUnitNode;
    property FormClass        : TAstNode                  read FFormClass;
    property FormNode         : TComponentNode            read FFormNode;
    property Events           : TList<TBoundEvent>        read FEvents;
    property PublishedFields  : TDictionary<string,TAstNode> read FPublishedFields;
    property PublishedMethods : TDictionary<string,TAstNode> read FPublishedMethods;
    property MethodImpls      : TDictionary<string,TAstNode> read FMethodImpls;
  end;

  TFormBinder = class
  public
    // Baut die Bindung. UnitNode kann nil sein (Pascal-Parse-Fehler) -
    // dann liefert die Funktion ein TFormBinding mit FormClass=nil und
    // leeren Lookups; die Detektoren skippen sich selbst sauber.
    class function Bind(Graph: TComponentGraph;
                        UnitNode: TAstNode): TFormBinding;
  end;

// Helper: pruefen ob ein Property-Path ein Event-Name ist
// (z.B. 'OnClick', 'OnChange', 'OnExecute'). Heuristik: beginnt mit 'On',
// drittes Zeichen ist Grossbuchstabe. 'OnlineMode' faellt nicht darunter
// (drittes Zeichen 'l').
function IsEventPropertyName(const PropName: string): Boolean;

implementation

uses
  System.StrUtils;

function IsEventPropertyName(const PropName: string): Boolean;
begin
  Result := (Length(PropName) >= 3)
        and (PropName[1] = 'O')
        and (PropName[2] = 'n')
        and CharInSet(PropName[3], ['A'..'Z']);
end;

{ TFormBinding }

constructor TFormBinding.Create;
begin
  inherited;
  FEvents           := TList<TBoundEvent>.Create;
  FPublishedFields  := TDictionary<string, TAstNode>.Create;
  FPublishedMethods := TDictionary<string, TAstNode>.Create;
  FMethodImpls      := TDictionary<string, TAstNode>.Create;
end;

destructor TFormBinding.Destroy;
begin
  FMethodImpls.Free;
  FPublishedMethods.Free;
  FPublishedFields.Free;
  FEvents.Free;
  inherited;
end;

function TFormBinding.ResolveHandler(const HandlerName: string): TAstNode;
var
  Key: string;
begin
  Key := LowerCase(HandlerName);
  if FMethodImpls.TryGetValue(Key, Result) then Exit;
  if FPublishedMethods.TryGetValue(Key, Result) then Exit;
  Result := nil;
end;

function TFormBinding.HasHandler(const HandlerName: string): Boolean;
begin
  Result := ResolveHandler(HandlerName) <> nil;
end;

{ TFormBinder }

class function TFormBinder.Bind(Graph: TComponentGraph;
  UnitNode: TAstNode): TFormBinding;

  procedure CollectPublishedMembers(ClassNode: TAstNode;
    Fields, Methods: TDictionary<string, TAstNode>);
  var
    I, J  : Integer;
    Sec   : TAstNode;
    Child : TAstNode;
  begin
    // Klassen-Deklaration: Children sind nkVisibilitySection. Eine Section
    // mit Name='published' liefert die fuer DFM-Streaming relevanten
    // Members (Defaultsection ist published in TPersistent-Hierarchie).
    for I := 0 to ClassNode.Children.Count - 1 do
    begin
      Sec := ClassNode.Children[I];
      if (Sec.Kind <> nkVisibilitySection) or
         not SameText(Sec.Name, 'published') then Continue;
      for J := 0 to Sec.Children.Count - 1 do
      begin
        Child := Sec.Children[J];
        case Child.Kind of
          nkField  : Fields.AddOrSetValue(LowerCase(Child.Name), Child);
          nkMethod : Methods.AddOrSetValue(LowerCase(Child.Name), Child);
        end;
      end;
    end;
  end;

  procedure CollectMethodImpls(AClassName: string; AUnitNode: TAstNode;
    Impls: TDictionary<string, TAstNode>);
  var
    All     : TList<TAstNode>;
    M       : TAstNode;
    Prefix  : string;
    BareKey : string;
  begin
    Prefix := LowerCase(AClassName) + '.';
    All := AUnitNode.FindAll(nkMethod);
    try
      for M in All do
      begin
        // Nur qualifizierte Methoden-Names = Implementation-Knoten.
        // 'btnGoClick' -> unqualified (Klass-Signatur). 'TForm2.btnGoClick'
        // -> qualified (Implementation). Wir nehmen nur jene, die zur
        // FormClass gehoeren.
        if not StartsText(Prefix, M.Name) then Continue;
        BareKey := LowerCase(Copy(M.Name, Length(Prefix) + 1, MaxInt));
        if BareKey = '' then Continue;
        Impls.AddOrSetValue(BareKey, M);
      end;
    finally
      All.Free;
    end;
  end;

  procedure CollectEvents(AGraph: TComponentGraph; AEvents: TList<TBoundEvent>);
  var
    All    : TList<TComponentNode>;
    Node   : TComponentNode;
    Pair   : TPair<string, TPropValue>;
    Ev     : TBoundEvent;
  begin
    All := AGraph.EnumerateAll;
    try
      for Node in All do
        for Pair in Node.Properties do
          if IsEventPropertyName(Pair.Key)
             and (Pair.Value.Kind = pvkIdent)
             and (Trim(Pair.Value.RawValue) <> '') then
          begin
            Ev.Component   := Node;
            Ev.EventName   := Pair.Key;
            Ev.HandlerName := Trim(Pair.Value.RawValue);
            Ev.Line        := Pair.Value.Line;
            AEvents.Add(Ev);
          end;
    finally
      All.Free;
    end;
  end;

var
  Classes : TList<TAstNode>;
  C       : TAstNode;
  RootClassRef : string;
begin
  Result := TFormBinding.Create;
  Result.FUnitNode := UnitNode;

  if (Graph = nil) or (Graph.Roots.Count = 0) then Exit;
  Result.FFormNode := Graph.Roots[0];
  RootClassRef := Result.FFormNode.ClassRef;

  // Events koennen unabhaengig von der Pascal-Klasse extrahiert werden.
  CollectEvents(Graph, Result.FEvents);

  // Ohne UnitNode kann der Detektor nichts gegen den Pascal-Code matchen,
  // aber TFormBinding-API bleibt benutzbar (leere Lookups).
  if UnitNode = nil then Exit;

  Classes := UnitNode.FindAll(nkClass);
  try
    for C in Classes do
      if SameText(C.Name, RootClassRef) then
      begin
        Result.FFormClass := C;
        Break;
      end;
  finally
    Classes.Free;
  end;

  if Result.FFormClass = nil then Exit;

  CollectPublishedMembers(Result.FFormClass,
    Result.FPublishedFields, Result.FPublishedMethods);
  CollectMethodImpls(Result.FFormClass.Name, UnitNode, Result.FMethodImpls);
end;

end.

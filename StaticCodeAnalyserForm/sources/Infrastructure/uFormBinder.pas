unit uFormBinder;

// Verbindet einen DFM-Komponentengraph mit dem Pascal-AST der zugehoerigen
// Form-Klasse.
//
// Iteration 1 (Phase 1): Root des Graphs (z.B. 'Form2: TForm2') hat eine
// gleichnamige Klassen-Deklaration in derselben Unit.
// Iteration 2 (Phase 2): inherited-Form-Aufloesung ueber TDfmRepoIndex -
// Bind-Methode kann optional eine Parent-Kette aufbauen, sodass
// HasHandler / HasPublishedField / HasPublishedMethod ueber die Klassen-
// Vererbung hinweg suchen. Damit fallen die false-positives bei
// vererbten DFMs weg (TForm2 = class(TForm1), wo Btn1Click in TForm1
// implementiert ist).
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
  uAstNode, uComponentGraph, uDfmRepoIndex;

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
    // Bindung der Parent-Klasse (TForm2 -> TForm1). nil wenn die direkte
    // Eltern-Klasse VCL-Root ist (TForm/TFrame/TDataModule/TComponent...)
    // oder wenn der RepoIndex sie nicht finden konnte. Bei nicht-nil
    // OWNED dieses TFormBinding den Parent + dessen Graph + UnitNode -
    // FOwnedResources sorgt fuer die Cascade-Freigabe.
    FParent           : TFormBinding;
    FOwnedResources   : TObjectList<TObject>;
  public
    constructor Create;
    destructor  Destroy; override;

    // Aufloeser fuer Event-Handler. Liefert zuerst die Implementation,
    // wenn vorhanden, sonst die Class-Signatur. Wenn lokal nichts da
    // ist UND FParent gesetzt ist, walked die Suche die Klassen-
    // Vererbung hoch. nil wenn weder im eigenen Binding noch in
    // irgendeinem Parent gefunden -> der DeadEvent-Detektor feuert.
    function ResolveHandler(const HandlerName: string): TAstNode;
    function HasHandler(const HandlerName: string): Boolean;

    // Existenz-Check fuer published Felder/Methoden ueber die Vererbungs-
    // Kette. Pflichtleser fuer den SchemaMismatch-Detektor, der heute
    // bei vererbten DFMs falsch positives produziert.
    function HasPublishedField(const FieldName: string): Boolean;
    function HasPublishedMethod(const MethodName: string): Boolean;

    // Owner-Take: Hilfe fuer TFormBinder.BindWithParents, das die
    // Parent-Kette aufbaut und Ressourcen abgibt. Aufrufer benutzt das
    // nur ueber den Binder, nicht direkt.
    procedure AdoptParent(AParent: TFormBinding;
                          ParentGraph: TComponentGraph;
                          ParentUnitNode: TAstNode);

    property UnitNode         : TAstNode                  read FUnitNode;
    property FormClass        : TAstNode                  read FFormClass;
    property FormNode         : TComponentNode            read FFormNode;
    property Events           : TList<TBoundEvent>        read FEvents;
    property PublishedFields  : TDictionary<string,TAstNode> read FPublishedFields;
    property PublishedMethods : TDictionary<string,TAstNode> read FPublishedMethods;
    property MethodImpls      : TDictionary<string,TAstNode> read FMethodImpls;
    property Parent           : TFormBinding              read FParent;
  end;

  TFormBinder = class
  public
    // Baut die Bindung. UnitNode kann nil sein (Pascal-Parse-Fehler) -
    // dann liefert die Funktion ein TFormBinding mit FormClass=nil und
    // leeren Lookups; die Detektoren skippen sich selbst sauber.
    class function Bind(Graph: TComponentGraph;
                        UnitNode: TAstNode): TFormBinding;

    // Wie Bind, baut zusaetzlich die Parent-Klassen-Kette ueber den
    // RepoIndex auf. Bei RepoIndex=nil (Single-File-Analyse) verhaelt
    // sich BindWithParents wie Bind. Stoppt an VCL-Roots
    // (TForm/TFrame/TDataModule/TComponent/TObject) oder wenn der
    // RepoIndex die Parent-Klasse nicht kennt - safe gegen Endlos-
    // Loops bei zirkulaeren Klassen-Hierarchien (cycle-detection
    // ueber Visited-Set).
    //
    // Eigentumsregeln:
    //   * Der Aufrufer behaelt Ownership ueber den UEBERGEBENEN Graph
    //     und UnitNode (das war auch in Bind so).
    //   * Die Parent-Bindings + deren Graphs/UnitNodes gehoeren dem
    //     zurueckgegebenen TFormBinding - Destroy gibt sie cascadiert
    //     frei. Aufrufer muss also nur das eine Top-Binding freigeben.
    class function BindWithParents(Graph: TComponentGraph;
                                   UnitNode: TAstNode;
                                   RepoIndex: TDfmRepoIndex): TFormBinding;
  end;

// Helper: pruefen ob ein Property-Path ein Event-Name ist
// (z.B. 'OnClick', 'OnChange', 'OnExecute'). Heuristik: beginnt mit 'On',
// drittes Zeichen ist Grossbuchstabe. 'OnlineMode' faellt nicht darunter
// (drittes Zeichen 'l').
function IsEventPropertyName(const PropName: string): Boolean;

implementation

uses
  System.IOUtils, System.StrUtils,
  uDfmParser, uDfmBinaryReader, uParser2;

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
  // OwnsObjects=True: gehaltene Parent-Resourcen (Graph + UnitNode +
  // ParentBinding) werden beim Destroy automatisch freigegeben.
  FOwnedResources   := TObjectList<TObject>.Create(True);
  FParent           := nil;
end;

destructor TFormBinding.Destroy;
begin
  // FOwnedResources gibt cascadiert Parent-Binding, Parent-Graph und
  // Parent-UnitNode frei. FParent ist nur eine NAVIGATION-Referenz auf
  // ein Objekt in FOwnedResources - NICHT separat freigeben.
  FOwnedResources.Free;
  FMethodImpls.Free;
  FPublishedMethods.Free;
  FPublishedFields.Free;
  FEvents.Free;
  inherited;
end;

procedure TFormBinding.AdoptParent(AParent: TFormBinding;
  ParentGraph: TComponentGraph; ParentUnitNode: TAstNode);
begin
  if AParent = nil then Exit;
  FParent := AParent;
  // Binding zuerst in die OwnedResources - damit FParent eine gueltige
  // Referenz hat, solange Self lebt. Reihenfolge ist auch wichtig fuer
  // die Destroy-Cascade: Binding free'd zuerst (das uses noch
  // Graph/UnitNode in ResolveHandler-Walks), dann Graph + UnitNode.
  FOwnedResources.Add(AParent);
  if ParentGraph <> nil then
    FOwnedResources.Add(ParentGraph);
  if ParentUnitNode <> nil then
    FOwnedResources.Add(ParentUnitNode);
end;

function TFormBinding.ResolveHandler(const HandlerName: string): TAstNode;
var
  Key: string;
begin
  Key := LowerCase(HandlerName);
  if FMethodImpls.TryGetValue(Key, Result) then Exit;
  if FPublishedMethods.TryGetValue(Key, Result) then Exit;
  if FParent <> nil then
    Exit(FParent.ResolveHandler(HandlerName));
  Result := nil;
end;

function TFormBinding.HasHandler(const HandlerName: string): Boolean;
begin
  Result := ResolveHandler(HandlerName) <> nil;
end;

function TFormBinding.HasPublishedField(const FieldName: string): Boolean;
var Key: string;
begin
  Key := LowerCase(FieldName);
  if FPublishedFields.ContainsKey(Key) then Exit(True);
  if FParent <> nil then Exit(FParent.HasPublishedField(FieldName));
  Result := False;
end;

function TFormBinding.HasPublishedMethod(const MethodName: string): Boolean;
var Key: string;
begin
  Key := LowerCase(MethodName);
  if FPublishedMethods.ContainsKey(Key) then Exit(True);
  if FParent <> nil then Exit(FParent.HasPublishedMethod(MethodName));
  Result := False;
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

class function TFormBinder.BindWithParents(Graph: TComponentGraph;
  UnitNode: TAstNode; RepoIndex: TDfmRepoIndex): TFormBinding;

  function IsVclRoot(const ClassRef: string): Boolean;
  // Liste der VCL-Basis-Klassen, an denen wir die Vererbungs-Aufloesung
  // stoppen. Pragma: wir loesen nur User-Klassen auf - die VCL-Klassen
  // sind nicht im Repo und es macht keinen Sinn, ueber sie hinaus zu
  // suchen. TObject ist der harte Stopper, der Rest verhindert nur
  // unnoetige RepoIndex-Lookups bei der haeufigsten Klasse direkt
  // unter dem Form-Root.
  const
    Roots: array[0..7] of string = (
      'TObject', 'TPersistent', 'TComponent',
      'TForm', 'TFrame', 'TCustomForm', 'TCustomFrame', 'TDataModule'
    );
  var R: string;
  begin
    for R in Roots do
      if SameText(ClassRef, R) then Exit(True);
    Result := False;
  end;

  function FirstAncestor(const TypeRefList: string): string;
  // ClassNode.TypeRef ist eine Space-separierte Liste: 'TForm IFoo'.
  // Das erste Token ist die Ancestor-Klasse, der Rest sind Interfaces.
  var i: Integer;
  begin
    Result := Trim(TypeRefList);
    i := Pos(' ', Result);
    if i > 0 then Result := Trim(Copy(Result, 1, i - 1));
  end;

  function FindClassNode(AUnitNode: TAstNode;
    const ClassName: string): TAstNode;
  var
    AllClasses: TList<TAstNode>;
    C: TAstNode;
  begin
    Result := nil;
    if AUnitNode = nil then Exit;
    AllClasses := AUnitNode.FindAll(nkClass);
    try
      for C in AllClasses do
        if SameText(C.Name, ClassName) then Exit(C);
    finally
      AllClasses.Free;
    end;
  end;

  function BuildParent(const ParentClassRef: string;
                       Visited: TDictionary<string, Boolean>): TFormBinding;
  var
    ParentUnitFile : string;
    ParentDfmFile  : string;
    Source         : string;
    ParentParser   : TDfmParser;
    PasParser      : TParser2;
    ParentGraph    : TComponentGraph;
    ParentUnitNode : TAstNode;
    ParentClassNode: TAstNode;
    GrandAncestor  : string;
    GrandBinding   : TFormBinding;
    LowKey         : string;
  begin
    Result := nil;
    if RepoIndex = nil then Exit;
    if ParentClassRef = '' then Exit;
    if IsVclRoot(ParentClassRef) then Exit;

    // Cycle-Guard: pathologische Faelle wie 'A inherits B inherits A' aus
    // korrupten ASTs / Conditional-Compilation. Visited-Set traegt die
    // bisher schon angefragten Klassen.
    LowKey := LowerCase(ParentClassRef);
    if Visited.ContainsKey(LowKey) then Exit;
    Visited.Add(LowKey, True);

    ParentUnitFile := RepoIndex.GetUnitForClass(ParentClassRef);
    if (ParentUnitFile = '') or not TFile.Exists(ParentUnitFile) then Exit;

    // .pas einlesen (RepoIndex hat sie bereits einmal geparst, aber der
    // AST wurde nicht gecacht - hier nochmal). Parse-Fehler werden
    // geschluckt, Parent-Binding bleibt nil.
    ParentUnitNode := nil;
    try
      PasParser := TParser2.Create;
      try
        ParentUnitNode := PasParser.ParseFile(ParentUnitFile);
      finally
        PasParser.Free;
      end;
    except
      ParentUnitNode := nil;
    end;
    if ParentUnitNode = nil then Exit;

    // .dfm zum Parent suchen + parsen. Wenn die Parent-Klasse keine DFM
    // hat (z.B. reine Code-Basis-Klasse), arbeiten wir mit Graph=nil
    // weiter - die Pascal-Class wird trotzdem gebunden, sodass
    // HasHandler/HasPublishedField fuer geerbte Methoden funktionieren.
    ParentGraph   := nil;
    ParentDfmFile := TPath.ChangeExtension(ParentUnitFile, '.dfm');
    if TFile.Exists(ParentDfmFile) then
    begin
      try
        Source := TDfmBinaryReader.ReadFile(ParentDfmFile);
        if Source <> '' then
        begin
          ParentParser := TDfmParser.Create;
          try
            ParentGraph := ParentParser.ParseSource(Source);
          finally
            ParentParser.Free;
          end;
        end;
      except
        ParentGraph := nil;
      end;
    end;

    // Wenn KEINE Parent-DFM da ist, erzeugen wir einen leeren Graph mit
    // Synth-Root, damit der Binder die Pascal-Klasse findet (sie wird
    // ueber ClassRef = ParentClassRef gematcht). Das ist der typische
    // Fall fuer reine Logik-Basis-Klassen.
    if ParentGraph = nil then
    begin
      ParentGraph := TComponentGraph.Create;
      // Synth-Root: Name leer, Klasse = ParentClassRef. Der Binder
      // matched dann die Pascal-Klasse, der Detektor sieht leere Events.
      ParentGraph.AddRoot('', ParentClassRef, 0, 0);
    end;

    Result := TFormBinder.Bind(ParentGraph, ParentUnitNode);

    // BuildParent ist verantwortlich, ParentGraph + ParentUnitNode in
    // FOwnedResources des zurueckgegebenen Bindings zu legen - der
    // top-level Aufrufer reicht das Binding nur weiter, ohne
    // Graph/UnitNode nochmal extra zu uebergeben.
    Result.FOwnedResources.Add(ParentGraph);
    Result.FOwnedResources.Add(ParentUnitNode);

    // Grand-Parent ueber Klassen-Vererbung. Wir nutzen den geparsten
    // ParentUnitNode, um den Ancestor-Token zu finden.
    GrandAncestor := '';
    ParentClassNode := FindClassNode(ParentUnitNode, ParentClassRef);
    if ParentClassNode <> nil then
      GrandAncestor := FirstAncestor(ParentClassNode.TypeRef);

    if (GrandAncestor <> '') and not IsVclRoot(GrandAncestor) then
    begin
      GrandBinding := BuildParent(GrandAncestor, Visited);
      if GrandBinding <> nil then
        // GrandBinding traegt seine eigenen Owned-Resourcen schon mit.
        Result.AdoptParent(GrandBinding, nil, nil);
    end;
  end;

var
  RootClassRef : string;
  ClassNode    : TAstNode;
  ParentRef    : string;
  ParentBinding: TFormBinding;
  Visited      : TDictionary<string, Boolean>;
begin
  // Schritt 1: lokales Binding wie gewohnt aufbauen. Graph + UnitNode
  // bleiben im Besitz des Aufrufers (analog zu Bind).
  Result := Bind(Graph, UnitNode);

  // Schritt 2: Parent-Kette versuchen. RepoIndex=nil oder keine
  // Klassen-Information -> nichts zu tun, Result bleibt unverlinkt.
  if RepoIndex = nil then Exit;
  if Result.FFormClass = nil then Exit;

  RootClassRef := Result.FFormClass.Name;
  // Visited beginnt mit dem aktuellen Klassen-Namen, damit Self-Cycles
  // ('A inherits A' via verkettete Conditional-Compilation-Pfade)
  // sofort gestoppt werden.
  Visited := TDictionary<string, Boolean>.Create;
  try
    Visited.Add(LowerCase(RootClassRef), True);

    ClassNode := Result.FFormClass;
    ParentRef := FirstAncestor(ClassNode.TypeRef);
    if (ParentRef = '') or IsVclRoot(ParentRef) then Exit;

    ParentBinding := BuildParent(ParentRef, Visited);
    if ParentBinding = nil then Exit;

    // Result adoptiert das Parent-Binding (das wiederum seine eigenen
    // Graph + UnitNode in FOwnedResources haelt - keine weiteren Args
    // hier noetig).
    Result.AdoptParent(ParentBinding, nil, nil);
  finally
    Visited.Free;
  end;
end;

end.

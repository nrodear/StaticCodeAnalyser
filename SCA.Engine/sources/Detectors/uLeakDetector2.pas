unit uLeakDetector2;

// AST-basierter Speicherleck-Detektor (Sonar-Regel #1).
//
// Erkannte Muster:
//   lsError   – Objekt per .Create erzeugt, nie freigegeben
//   lsWarning – Free außerhalb des finally-Blocks (obwohl try/finally vorhanden)
//   lsWarning – Objekt von Funktion zurückbekommen, nie freigegeben
//
// Ownership-Transfer (kein Befund):
//   Result := var                Funktion gibt Ownership ab
//   var.Parent := winControl     VCL: Parent gibt Children frei (Controls[])
//   var := X.Add(...)            Borrowed-Return aus Tree-/Container-API
//   var := X.AddChild(...)        (AST/XML/DOM/TreeView - Item lebt in
//   var := X.AddNode(...)         Container.OwnsObjects-Liste)
//   var := X.AppendChild(...)
//   FField := var                Var-zu-Feld: Method-Scope abgegeben
//   FField := var as ISomething   (Interface-Refcount uebernimmt Lifetime)
//   inherited Create(var, …)    Elternkonstruktor übernimmt
//   AnyClass.Create(var, …)     anderer Konstruktor übernimmt
//   Container.Add(...var...)     TObjectList/TObjectDictionary/...
//   Container.AddObject(t, var)  TStringList mit Objekten
//   Container.Insert(i, var)     TList.Insert
//   Container.Push(var)          TStack.Push
//   Container.Enqueue(var)       TQueue.Enqueue
//
// Korrektheitsprinzip:
//   Alle Namensvergleiche prüfen Wortgrenzen auf BEIDEN Seiten,
//   um false positives durch Teilstring-Übereinstimmungen zu verhindern
//   (z. B. 'list' ≠ 'blacklist', 'list.Free' ≠ 'blacklist.Free').

interface

uses
  System.SysUtils, System.StrUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uDetectorUtils;

type
  TLeakDetector2 = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);

  // Hilfsmethoden (public fuer Wiederverwendung in anderen Detektoren)
  public
    class function IsIdentChar(C: Char): Boolean; static; inline;
    class function IsWholeWord(const Str, Pattern: string;
      Pos_: Integer): Boolean; static;
    class function IsLeakyType(const TypeRef: string): Boolean; static;
    // Erkennt einen Konstruktor-Aufruf in der RHS einer Zuweisung:
    // sowohl `.Create(...)` als auch CamelCase-Varianten wie `.CreateUtf8`,
    // `.CreateFmt`, `.CreateFromFile`, `.CreateAfterAttach` (mORMot- / RTL-
    // gebraeuchlich). Verb-Formen `.creates` / `.created` werden bewusst
    // ausgeschlossen - die fortsetzenden Kleinbuchstaben unterscheiden
    // Identifier-Suffix (Verb) von CamelCase-Suffix (Konstruktor).
    // ATypeRef ist die original-Case-Form (TypeRef wie aus dem AST),
    // ATypeLow ist `ATypeRef.ToLower` (vorberechnet vom Caller).
    class function MatchesCreate(const ATypeRef, ATypeLow: string;
      out CreatePos: Integer): Boolean; static;
    class function HasCreateAssign(MethodNode: TAstNode;
      const VarNameLow: string): Boolean; static;
    class function HasFunctionCallAssign(MethodNode: TAstNode;
      const VarNameLow: string): Boolean; static;
    // Liefert die Quell-Zeile des ERSTEN `var := X.Create(...)`. Wird
    // genutzt um die Befund-Position auf die echte Create-Zeile zu legen
    // statt auf die var-Deklaration - bessere UX (Klick im Grid springt
    // zur Allokation), und macht inline `// noinspection`-Marker ueber
    // dem Create-Aufruf wirksam (Suppression-Map vergleicht 1:1 die
    // Finding-Line gegen die Marker-Target-Line). 0 wenn kein passender
    // Assign gefunden - Caller faellt dann auf die var-Decl-Line zurueck.
    class function FindCreateLine(MethodNode: TAstNode;
      const VarNameLow: string): Integer; static;
    class function FindFuncCallAssignLine(MethodNode: TAstNode;
      const VarNameLow: string): Integer; static;
    class function IsReturnedAsResult(MethodNode: TAstNode;
      const VarNameLow: string): Boolean; static;
    class function IsPassedToOwner(MethodNode: TAstNode;
      const VarNameLow: string): Boolean; static;
    class function SearchFree(Node: TAstNode; const VarNameLow: string;
      InFinally: Boolean; out FoundInFinally: Boolean): Boolean; static;
    class function HasTryFinallyBlock(MethodNode: TAstNode): Boolean; static;
    // True wenn der Receiver eines '.Add(item)'-Aufrufs ein ownership-
    // bewusster Container ist (TObjectList, TObjectDictionary, ...) -
    // ODER wenn der Typ unbekannt ist (Default permissiv, vermeidet
    // Regression bei FList.Add-Mustern). False nur wenn der Typ
    // aufloesbar ist UND nicht zur Whitelist passt (TList, TStringList,
    // TSynList etc. haben kein OwnsObjects).
    class function AddReceiverOwnsItems(MethodNode: TAstNode;
      const ReceiverNameLow: string): Boolean; static;
  end;

implementation

{ ---- Wortgrenz-Hilfsfunktionen ---- }

class function TLeakDetector2.IsIdentChar(C: Char): Boolean;
begin
  // Delegation auf zentralen Helper. Klassen-Wrapper bleibt erhalten, damit
  // bestehende Aufrufer in dieser Unit unveraendert bleiben.
  Result := TDetectorUtils.IsIdentChar(C);
end;

class function TLeakDetector2.IsWholeWord(const Str, Pattern: string;
  Pos_: Integer): Boolean;
var
  pRight: Integer;
begin
  Result := False;
  if Pos_ <= 0 then Exit;
  // Linke Grenze
  if (Pos_ > 1) and IsIdentChar(Str[Pos_ - 1]) then Exit;
  // Rechte Grenze
  pRight := Pos_ + Length(Pattern);
  if (pRight <= Length(Str)) and IsIdentChar(Str[pRight]) then Exit;
  Result := True;
end;

{ ---- Typ-Check ---- }

class function TLeakDetector2.IsLeakyType(const TypeRef: string): Boolean;
// LeakyClasses ist seit der Konvertierung auf TStringList eine sortierte,
// case-insensitive Liste -> IndexOf liefert >= 0 wenn die Klasse bekannt ist.
// Plus: LeakyClassExcludes-Check als zweites Sicherheitsnetz - falls eine
// Klasse trotz Exclude in LeakyClasses gelandet ist (z.B. durch Discovery
// in einer alten Plugin-Version), wird sie hier nochmal gefiltert.
var
  Clean : string;
  lt    : Integer;
begin
  Result := False;
  if not Assigned(LeakyClasses) then Exit;

  Clean := Trim(TypeRef);
  lt    := Pos('<', Clean);
  if lt > 0 then
    Clean := Trim(Copy(Clean, 1, lt - 1));
  if Clean = '' then Exit;

  // Erst Exclude-Check, dann Match-Check
  if Assigned(LeakyClassExcludes) and
     (LeakyClassExcludes.IndexOf(Clean) >= 0) then Exit;

  Result := LeakyClasses.IndexOf(Clean) >= 0;
end;

{ ---- Create-Erkennung ---- }

class function TLeakDetector2.MatchesCreate(const ATypeRef, ATypeLow: string;
  out CreatePos: Integer): Boolean;
var
  pRight : Integer;
begin
  Result    := False;
  CreatePos := 0;
  CreatePos := Pos('.create', ATypeLow);
  if CreatePos <= 0 then Exit;
  pRight := CreatePos + 7;          // direkt hinter 'create'
  // Fall A: '.Create' am Ende des Ausdrucks (kein Folge-Token)
  if pRight > Length(ATypeLow) then Exit(True);
  // Fall B: '.Create(' / '.Create ' / '.Create;' - non-Ident-Char hinter create
  if not IsIdentChar(ATypeLow[pRight]) then Exit(True);
  // Fall C: '.CreateXxx' - Folge-Zeichen ist im Original-Case ein
  // Grossbuchstabe -> CamelCase-Suffix -> Konstruktor-Variante.
  // Fall D: '.created'/'.creates' - Folge-Zeichen lowercase -> Verb-Form,
  // kein Konstruktor. ATypeRef und ATypeLow haben gleiche Laenge.
  if pRight > Length(ATypeRef) then Exit;          // defensive
  Result := CharInSet(ATypeRef[pRight], ['A'..'Z']);
end;

class function TLeakDetector2.HasCreateAssign(MethodNode: TAstNode;
  const VarNameLow: string): Boolean;
var
  Assigns  : TList<TAstNode>;
  A        : TAstNode;
  TypeLow  : string;
  Dummy    : Integer;
begin
  Result  := False;
  Assigns := MethodNode.FindAll(nkAssign);
  try
    for A in Assigns do
    begin
      // Exakter Namensvergleich (A.Name ist immer der vollständige LHS-Ausdruck)
      if A.Name.ToLower <> VarNameLow then Continue;
      TypeLow := A.TypeRef.ToLower;
      if MatchesCreate(A.TypeRef, TypeLow, Dummy) then
        Exit(True);
    end;
  finally
    Assigns.Free;
  end;
end;

class function TLeakDetector2.FindCreateLine(MethodNode: TAstNode;
  const VarNameLow: string): Integer;
var
  Assigns : TList<TAstNode>;
  A       : TAstNode;
  TypeLow : string;
begin
  Result  := 0;
  Assigns := MethodNode.FindAll(nkAssign);
  try
    for A in Assigns do
    begin
      if A.Name.ToLower <> VarNameLow then Continue;
      TypeLow := A.TypeRef.ToLower;
      var Dummy : Integer;
      if MatchesCreate(A.TypeRef, TypeLow, Dummy) then
      begin
        Result := A.Line;
        Exit;
      end;
    end;
  finally
    Assigns.Free;
  end;
end;

class function TLeakDetector2.FindFuncCallAssignLine(MethodNode: TAstNode;
  const VarNameLow: string): Integer;
var
  Assigns : TList<TAstNode>;
  A       : TAstNode;
  RHS     : string;
begin
  Result  := 0;
  Assigns := MethodNode.FindAll(nkAssign);
  try
    for A in Assigns do
    begin
      if A.Name.ToLower <> VarNameLow then Continue;
      RHS := A.TypeRef.ToLower;
      if Pos('.create', RHS) > 0 then Continue;
      if (RHS = 'nil') or (RHS = '') then Continue;
      if Pos('(', RHS) > 0 then
      begin
        Result := A.Line;
        Exit;
      end;
    end;
  finally
    Assigns.Free;
  end;
end;

class function TLeakDetector2.HasFunctionCallAssign(MethodNode: TAstNode;
  const VarNameLow: string): Boolean;
var
  Assigns : TList<TAstNode>;
  A       : TAstNode;
  RHS     : string;
begin
  Result  := False;
  Assigns := MethodNode.FindAll(nkAssign);
  try
    for A in Assigns do
    begin
      if A.Name.ToLower <> VarNameLow then Continue;
      RHS := A.TypeRef.ToLower;
      if Pos('.create', RHS) > 0 then Continue;  // durch HasCreateAssign abgedeckt
      if (RHS = 'nil') or (RHS = '') then Continue;
      // Expliziter Aufruf mit Klammern: GetList()
      if Pos('(', RHS) > 0 then Exit(True);
      // Ohne '(' KEINE Factory-Detection: 'list := obj.FList' oder
      // 'list := SomeProperty' sind geliehene Referenzen, kein Ownership-
      // Transfer. Vorher wurde jeder dotted Bezeichner-Pfad als Factory-
      // Aufruf gewertet -> False-Positives auf jeder Field-/Property-
      // Zuweisung. Lieber False-Negative auf seltene parameterlose
      // Factory-Methoden (TFoo.Singleton) als False-Positive auf Standard-
      // Field-Access.
    end;
  finally
    Assigns.Free;
  end;
end;

{ ---- Ownership-Transfer-Erkennung ---- }

class function TLeakDetector2.IsReturnedAsResult(MethodNode: TAstNode;
  const VarNameLow: string): Boolean;
// Akzeptiert:
//   'Result := varname'         (moderner Stil)
//   'Result := varname as ITyp' (explicit cast)
//   '<funcname> := varname'     (legacy Delphi/Pascal: Funktionsname
//                                als implizite Ergebnis-Variable)
//
// Vorher: Wortgrenzen-Substring-Check matched auch 'Result := L.Count'
// (L ist drin, aber als Receiver, NICHT als Result-Wert) und unterdrueckte
// damit echte Leaks (Parser_IfdefDuplicatedHeaders / Real-World-Code).
// Falls jemand 'Result := SomeWrapper(L)' nutzt: das matched nicht mehr,
// L wird als Leak gemeldet - bewusster Tradeoff (besser ein False-Positive
// auf wrap-then-return als ein verstecktes Leak).
//
// FP-Fix (doublecmd torrent/BDecode.pas:bdecodeHash): legacy Pascal-Code
// nutzt 'bdecodeHash := r;' statt 'Result := r;'. Detector hat das
// vorher als Leak gemeldet weil nur 'Result :=' anerkannt war.
var
  Assigns        : TList<TAstNode>;
  A              : TAstNode;
  LhsLow         : string;
  Trimmed        : string;
  FuncNameLow    : string;

  function IsResultLhs(const ALhsLow: string): Boolean;
  begin
    // 'Result' oder Funktionsname selbst (legacy Pascal-Return).
    Result := (ALhsLow = 'result') or
              ((FuncNameLow <> '') and (ALhsLow = FuncNameLow));
  end;

begin
  Result      := False;
  FuncNameLow := '';
  if MethodNode <> nil then
  begin
    // Method.Name kann 'TFoo.Bar' sein - rightmost Identifier extrahieren.
    FuncNameLow := MethodNode.Name.ToLower;
    var DotPos := -1;
    for var i := Length(FuncNameLow) downto 1 do
      if FuncNameLow[i] = '.' then begin DotPos := i; Break; end;
    if DotPos > 0 then
      FuncNameLow := Copy(FuncNameLow, DotPos + 1, MaxInt);
  end;

  Assigns := MethodNode.FindAll(nkAssign);
  try
    for A in Assigns do
    begin
      LhsLow := A.Name.ToLower;
      if not IsResultLhs(LhsLow) then Continue;
      Trimmed := Trim(A.TypeRef.ToLower);
      // Exakter Match: 'Result := varname'
      if Trimmed = VarNameLow then Exit(True);
      // Explicit cast: 'Result := varname as IFoo' (mit/ohne Whitespace
      // - JoinTokInto produziert ' as ', aber legacy-Parser-Output kann
      // weiterhin 'asIFoo' liefern - beide tolerieren).
      if Trimmed.StartsWith(VarNameLow + ' as ') then Exit(True);
      if Trimmed.StartsWith(VarNameLow) and
         (Length(Trimmed) >= Length(VarNameLow) + 3) and
         (Trimmed[Length(VarNameLow) + 1] = 'a') and
         (Trimmed[Length(VarNameLow) + 2] = 's') and
         CharInSet(Trimmed[Length(VarNameLow) + 3], ['a'..'z', '_']) then
        Exit(True);
    end;
  finally
    Assigns.Free;
  end;

  // A: modernes 'Exit(varname)' = Result-Transfer + Sprung. nkCall.Name
  // enthaelt den ganzen Call-Expression-String ('Exit(list)') - via
  // ExtractCallFunctionName + ExtractCallArgsRaw zerlegen.
  // Quelle: doublecmd-Audit, 825 Exit-Calls.
  var Calls : TList<TAstNode>;
  var FuncName, ArgsRaw : string;
  Calls := MethodNode.FindAll(nkCall);
  try
    for A in Calls do
    begin
      FuncName := LowerCase(TDetectorUtils.ExtractCallFunctionName(A.Name));
      if FuncName <> 'exit' then Continue;
      ArgsRaw := Trim(LowerCase(TDetectorUtils.ExtractCallArgsRaw(A.Name)));
      if ArgsRaw = VarNameLow then Exit(True);
      // Exit(list as IFoo) - explicit cast wie bei Result := list as IFoo
      if ArgsRaw.StartsWith(VarNameLow + ' as ') then Exit(True);
    end;
  finally
    Calls.Free;
  end;
end;

class function TLeakDetector2.AddReceiverOwnsItems(MethodNode: TAstNode;
  const ReceiverNameLow: string): Boolean;
// Pflicht-Whitelist: Receiver-Typ matched einen ownership-bewussten
// Container. Liste praktisch begrenzt - die Default-RTL-Container
// die wirklich Free auf Items rufen.
const
  OWNING_PREFIXES : array[0..6] of string = (
    'tobjectlist',         // TObjectList<T>(True), TObjectList(True)
    'tobjectdictionary',   // TObjectDictionary
    'tobjectqueue',
    'tobjectstack',
    'tcomponentlist',      // VCL
    'townedcollection',    // VCL
    'tinterfacelist'       // refcount-managed - effektiv ownership-aequiv
  );

  function TypeMatches(const TypeLow: string): Boolean;
  // Strenge Word-Boundary-Pruefung: 'tobjectlist' matched 'tobjectlist',
  // 'tobjectlist<tfoo>' und 'tobjectlist(true)' aber NICHT 'tobjectlistview'
  // oder 'tobjectlisthelper' (gibt es z.B. in Spring4D / mORMot Erweiterungen).
  // Vorher Pos-Match-am-Anfang ohne Boundary -> false-positive Ownership-
  // Annahme bei jeder Klasse die mit Prefix anfaengt.
  var
    prefix : string;
    pLen   : Integer;
    NextCh : Char;
  begin
    Result := False;
    for prefix in OWNING_PREFIXES do
    begin
      if Pos(prefix, TypeLow) <> 1 then Continue;
      pLen := Length(prefix);
      if Length(TypeLow) = pLen then Exit(True); // exakter Match
      NextCh := TypeLow[pLen + 1];
      // Nach dem Prefix muss ein Nicht-Identifier-Char stehen (Generic-
      // Bracket, Klammer, Whitespace, etc.) - sonst ist's ein laengerer
      // Klassenname.
      if not CharInSet(NextCh, ['a'..'z', '0'..'9', '_']) then
        Exit(True);
    end;
  end;

  function FindReceiverType(Kind: TNodeKind; out TypeLow: string): Boolean;
  var
    Lst : TList<TAstNode>;
    N   : TAstNode;
    NameLow, NameRaw : string;
  begin
    Result := False;
    TypeLow := '';
    Lst := MethodNode.FindAll(Kind);
    try
      for N in Lst do
      begin
        NameRaw := N.Name;
        // Param-Knoten koennen 'var x'/'const x'/'out x' als Name haben.
        // Wir wollen den nackten Identifier vergleichen.
        for var Mod_ in ['var ', 'const ', 'out '] do
          if NameRaw.ToLower.StartsWith(Mod_) then
            NameRaw := Copy(NameRaw, Length(Mod_) + 1, MaxInt);
        NameLow := NameRaw.ToLower;
        if NameLow = ReceiverNameLow then
        begin
          TypeLow := N.TypeRef.ToLower;
          Exit(True);
        end;
      end;
    finally
      Lst.Free;
    end;
  end;

var
  TypeLow : string;
begin
  // Default permissiv: Typ unbekannt -> alte Behavior beibehalten
  // (Add gilt als ownership-Transfer). Verhindert Regression bei
  // FList.Add-Mustern wo der Field-Typ nicht in MethodNode steht.
  Result := True;

  // Typ aus Local-Var oder Parameter aufloesen.
  if FindReceiverType(nkLocalVar, TypeLow) or
     FindReceiverType(nkParam, TypeLow) then
  begin
    if TypeLow = '' then Exit;       // sollte nicht passieren, defensiv
    Result := TypeMatches(TypeLow);  // strikte Pruefung gegen Whitelist
  end;
end;

class function TLeakDetector2.IsPassedToOwner(MethodNode: TAstNode;
  const VarNameLow: string): Boolean;
var
  Assigns : TList<TAstNode>;
  Calls   : TList<TAstNode>;
  Inh     : TList<TAstNode>;
  N       : TAstNode;
  NameLow : string;
  pCreate : Integer;
  ParentLHS : string;

  function VarInArgs(const CallName: string; AfterPos: Integer): Boolean;
  // Prüft ob VarNameLow als Wort nach Position AfterPos in CallName vorkommt
  var
    p: Integer;
  begin
    Result := False;
    p := PosEx(VarNameLow, CallName, AfterPos);
    if p > 0 then
      Result := IsWholeWord(CallName, VarNameLow, p);
  end;

begin
  Result := False;

  // VCL-Parent-Zuweisung: varName.Parent := WinControl
  // Wer als Child eines TWinControl angemeldet wird, wird beim Destroy
  // des Parents automatisch freigegeben (Controls[]-Liste). Ownership
  // ist damit ans Parent abgegeben - kein Free im Caller noetig.
  // Standard-Pattern in jedem TFrame-/TForm-Konstruktor:
  //   Btn := TButton.Create(Self);
  //   Btn.Parent := PanelTop;       // <- DIESE Zeile gibt Ownership ab
  // Vorher: jede solche Zeile -> False-Positive "MemoryLeak".
  //
  // Plus: Borrowed-Return aus Tree-/Container-API:
  //   var := someContainer.Add(...)         TObjectList<T>(True)-basiert
  //   var := someParent.AddChild(...)       AST-/DOM-Trees
  //   var := someTree.AddNode(...)          TTreeView etc.
  //   var := someParent.AppendChild(...)    XML-DOM
  // In allen Faellen registriert die Add/AddChild/AddNode/AppendChild-Methode
  // das neue Item intern in einer OwnsObjects-Liste des Containers - das
  // Result ist eine geliehene Referenz, kein Ownership-Transfer. Ein Free
  // durch den Caller wuerde Double-Free im Container-Destroy verursachen.
  // Beispiel: ENode := Parent.Add(nkX, ...) im AST-Builder.
  ParentLHS := VarNameLow + '.parent';
  Assigns := MethodNode.FindAll(nkAssign);
  try
    for N in Assigns do
    begin
      // Parent-Assign: LHS-Match
      if N.Name.ToLower = ParentLHS then
        Exit(True);
      // Borrowed-Return: LHS == VarName, RHS enthaelt eine der Tree-API-
      // Patterns. Pattern endet auf '(' damit '.add(' nicht in '.address('
      // o.ae. matched (rechte Wortgrenze ist garantiert).
      if N.Name.ToLower = VarNameLow then
      begin
        var TypeLow := N.TypeRef.ToLower;
        if (Pos('.add(',         TypeLow) > 0) or
           (Pos('.addchild(',    TypeLow) > 0) or
           (Pos('.addnode(',     TypeLow) > 0) or
           (Pos('.appendchild(', TypeLow) > 0) then
          Exit(True);
      end;
      // Var-zu-Field-Transfer:
      //   FField := varName              -> Klassen-Feld haelt jetzt Ownership
      //   FField := varName as ISome     -> Interface-Refcount haelt Lifetime
      //   Self.FField := varName         -> mit explizitem Self-Praefix
      // In allen Faellen verlaesst die Ownership den Method-Scope. Ob das
      // Feld spaeter freigegeben wird, ist Aufgabe des FieldLeakDetectors.
      // Heuristik fuer "ist LHS ein Feld": Delphi-Konvention F<Grossbuchstabe>
      // oder explizites 'self.'-Praefix. Lokale Variablen heissen klein/
      // camelCase, daher kein Match.
      //
      // Parser inseriert seit JoinTokInto Spaces zwischen Identifier-
      // Tokens, daher 'notifier as IInterface' -> 'notifier as iinterface'.
      // Wir akzeptieren beide Varianten (mit/ohne Whitespace) damit der
      // Detektor robust gegen Parser-Aenderungen bleibt.
      var RHSLow := Trim(N.TypeRef.ToLower);
      var IsTransferShape := False;
      if RHSLow = VarNameLow then
        IsTransferShape := True
      else if RHSLow.StartsWith(VarNameLow) then
      begin
        var Rest := Trim(Copy(RHSLow, Length(VarNameLow) + 1, MaxInt));
        // 'as <typename>' ODER 'as<typename>' (legacy Parser-Output).
        if Rest.StartsWith('as ') then
          IsTransferShape := True
        else if (Length(Rest) >= 3) and (Rest[1] = 'a') and (Rest[2] = 's') and
                CharInSet(Rest[3], ['a'..'z', '_']) then
          IsTransferShape := True;
      end;
      if IsTransferShape then
      begin
        var LHSOrig := N.Name;
        if SameText(Copy(LHSOrig, 1, 5), 'self.') then
          Exit(True);
        if (Length(LHSOrig) >= 2) and (LHSOrig[1] = 'F') and
           (LHSOrig[2] >= 'A') and (LHSOrig[2] <= 'Z') then
          Exit(True);
      end;
    end;
  finally
    Assigns.Free;
  end;

  // inherited Create(varName, …) — Elternkonstruktor übernimmt Ownership
  Inh := MethodNode.FindAll(nkInherited);
  try
    for N in Inh do
    begin
      NameLow := N.Name.ToLower;
      if (Pos('create', NameLow) > 0) and
         VarInArgs(NameLow, 1) then
        Exit(True);
    end;
  finally
    Inh.Free;
  end;

  Calls := MethodNode.FindAll(nkCall);
  try
    for N in Calls do
    begin
      NameLow := N.Name.ToLower;

      // AnyClass.Create(varName, …)
      pCreate := Pos('.create(', NameLow);
      if (pCreate > 0) and VarInArgs(NameLow, pCreate + 8) then
        Exit(True);

      // Container.Add(varName) bzw. Container.Add(key, varName)
      // Vorher: jede '.add('-Methode wurde als ownership-uebernehmend
      // gewertet. Das produzierte False-Negatives auf legitime Leaks
      // bei TList.Add / TStringList.Add / TSynList.Add (mORMot) -
      // diese Listen uebernehmen KEIN Ownership.
      //
      // Jetzt: nur dann ownership annehmen, wenn entweder
      //   (a) der Receiver-Typ aus Local-Var/Parameter-Deklaration
      //       bekannt ist und auf ein ownership-bewusstes Container-
      //       Pattern matched (TObjectList, TObjectDictionary, ...),
      //   (b) der Typ NICHT aufloesbar ist (Field, dotted access,
      //       inferred var) - hier bleibt das alte permissive
      //       Verhalten als Default, damit keine Regression in den
      //       haeufigen Frame-FList.Add(item)-Mustern entsteht.
      var pAdd := Pos('.add(', NameLow);
      if (pAdd > 0) and VarInArgs(NameLow, pAdd + 5) then
      begin
        var receiverLow := Copy(NameLow, 1, pAdd - 1);
        // 'self.flist' -> 'flist': Self-Praefix abstreifen, sonst matched
        // der Receiver-Name nie ein Local-Var/Param. Nur das Praefix
        // entfernen, dotted Sub-Expressions ('foo.bar.add') bleiben
        // intentional unaufloesbar (Default permissiv).
        if receiverLow.StartsWith('self.') then
          receiverLow := Copy(receiverLow, 6, MaxInt);
        if AddReceiverOwnsItems(MethodNode, receiverLow) then
          Exit(True);
      end;

      // TStringList.AddObject(text, obj) - klassisches Object-Owner-Pattern
      pAdd := Pos('.addobject(', NameLow);
      if (pAdd > 0) and VarInArgs(NameLow, pAdd + 11) then
        Exit(True);

      // TList/TQueue/TStack.Insert(index, item) - Ownership-Transfer
      pAdd := Pos('.insert(', NameLow);
      if (pAdd > 0) and VarInArgs(NameLow, pAdd + 8) then
        Exit(True);

      // TStack.Push(item) / TQueue.Enqueue(item) - Ownership-Transfer
      pAdd := Pos('.push(', NameLow);
      if (pAdd > 0) and VarInArgs(NameLow, pAdd + 6) then
        Exit(True);
      pAdd := Pos('.enqueue(', NameLow);
      if (pAdd > 0) and VarInArgs(NameLow, pAdd + 9) then
        Exit(True);
    end;
  finally
    Calls.Free;
  end;
end;

{ ---- Free-Suche ---- }

class function TLeakDetector2.SearchFree(Node: TAstNode;
  const VarNameLow: string; InFinally: Boolean;
  out FoundInFinally: Boolean): Boolean;
var
  Child        : TAstNode;
  NameLow      : string;
  ChildInFin   : Boolean;
  ChildFinFlag : Boolean;
  pMatch       : Integer;
begin
  Result         := False;
  FoundInFinally := False;

  if not Assigned(Node) then Exit;

  if Node.Kind = nkCall then
  begin
    NameLow := Node.Name.ToLower;

    // varName.Free   (mit und ohne Klammern: list.Free / list.Free())
    pMatch := Pos(VarNameLow + '.free', NameLow);
    if pMatch > 0 then
    begin
      // Linke Wortgrenze: Zeichen vor varName darf kein Bezeichner sein
      if (pMatch = 1) or not IsIdentChar(NameLow[pMatch - 1]) then
      begin
        Result := True; FoundInFinally := InFinally; Exit;
      end;
    end;

    // varName.Destroy
    pMatch := Pos(VarNameLow + '.destroy', NameLow);
    if pMatch > 0 then
    begin
      if (pMatch = 1) or not IsIdentChar(NameLow[pMatch - 1]) then
      begin
        Result := True; FoundInFinally := InFinally; Exit;
      end;
    end;

    // FreeAndNil(varName)  — Klammer links, dann rechte Grenze prüfen
    pMatch := Pos('freeandnil(' + VarNameLow, NameLow);
    if pMatch > 0 then
    begin
      var pRight := pMatch + 11 + Length(VarNameLow); // 11 = len('freeandnil(')
      // Rechte Grenze: kein Bezeichner-Zeichen nach varName
      if (pRight > Length(NameLow)) or not IsIdentChar(NameLow[pRight]) then
      begin
        Result := True; FoundInFinally := InFinally; Exit;
      end;
    end;

    // Custom-Cleanup-Pattern: Funktion deren Name auf 'release'/'dispose'/
    // 'return'/'recycle' endet und varName als Argument bekommt
    // (Acquire/Release-Pool-Pattern wie AcquireLines/ReleaseLines).
    // Match nur wenn varName als bare Argument im Klammerausdruck steht.
    pMatch := Pos('(' + VarNameLow, NameLow);
    if pMatch > 0 then
    begin
      var pRight := pMatch + 1 + Length(VarNameLow);
      var BoundaryOK := (pRight > Length(NameLow)) or
                       (NameLow[pRight] = ',') or
                       (NameLow[pRight] = ')') or
                       (NameLow[pRight] = ' ');
      if BoundaryOK then
      begin
        // Funktionsnamen-Teil vor '(' extrahieren und auf Cleanup-Marker pruefen.
        // Akzeptiere sowohl 'Release' als Praefix ('ReleaseLines', 'ReleaseBuffer')
        // als auch als Suffix ('MyRelease', 'BufferRelease'). Beide Konventionen
        // sind in Delphi-Code praesent.
        var FnName := Copy(NameLow, 1, pMatch - 1);
        if FnName.StartsWith('release') or FnName.EndsWith('release') or
           FnName.StartsWith('dispose') or FnName.EndsWith('dispose') or
           FnName.StartsWith('return')  or FnName.EndsWith('return')  or
           FnName.StartsWith('recycle') or FnName.EndsWith('recycle') then
        begin
          Result := True; FoundInFinally := InFinally; Exit;
        end;
      end;
    end;
  end;

  for Child in Node.Children do
  begin
    ChildInFin := InFinally or (Child.Kind = nkFinallyBlock);
    if SearchFree(Child, VarNameLow, ChildInFin, ChildFinFlag) then
    begin
      Result := True; FoundInFinally := ChildFinFlag; Exit;
    end;
  end;
end;

class function TLeakDetector2.HasTryFinallyBlock(MethodNode: TAstNode): Boolean;
begin
  Result := MethodNode.HasChild(nkTryFinally);
end;

{ ---- Öffentliche API ---- }

class procedure TLeakDetector2.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);

  procedure AddFinding(const MissingVar: string; Sev: TLeakSeverity;
    VLine: Integer);
  var
    F: TLeakFinding;
  begin
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := MethodNode.Name;
    F.LineNumber := IntToStr(VLine);
    F.MissingVar := MissingVar;
    F.Severity   := Sev;
    F.Kind       := fkMemoryLeak;
    F.Confidence := KindDefaultConfidence(fkMemoryLeak);
    Results.Add(F);
  end;

var
  LocalVars  : TList<TAstNode>;
  V          : TAstNode;
  VarNameLow : string;
  FreeFound  : Boolean;
  FreeInFin  : Boolean;
  HasFinally : Boolean;
begin
  LocalVars := MethodNode.FindAll(nkLocalVar);
  try
    for V in LocalVars do
    begin
      if not IsLeakyType(V.TypeRef) then Continue;

      VarNameLow := V.Name.ToLower;
      HasFinally := HasTryFinallyBlock(MethodNode);

      // ── Pfad 1: direkte .Create-Zuweisung ──────────────────────────────────
      if HasCreateAssign(MethodNode, VarNameLow) then
      begin
        if IsReturnedAsResult(MethodNode, VarNameLow) then Continue;
        if IsPassedToOwner(MethodNode, VarNameLow)    then Continue;

        FreeFound := SearchFree(MethodNode, VarNameLow, False, FreeInFin);

        // Befund auf der Create-Zeile melden statt auf der var-Decl-Zeile.
        // Bessere UX (Klick im Grid -> Allokation), und macht inline
        // // noinspection-Marker direkt ueber dem Create wirksam.
        var ReportLine := FindCreateLine(MethodNode, VarNameLow);
        if ReportLine = 0 then ReportLine := V.Line;

        if not FreeFound then
          AddFinding(V.Name, lsError, ReportLine)
        else if not FreeInFin and HasFinally then
          AddFinding(V.Name, lsWarning, ReportLine);

        Continue;
      end;

      // ── Pfad 2: Funktionsaufruf-Zuweisung — list := BuildList(...) ──────────
      if not HasFunctionCallAssign(MethodNode, VarNameLow) then Continue;

      if IsReturnedAsResult(MethodNode, VarNameLow) then Continue;
      if IsPassedToOwner(MethodNode, VarNameLow)    then Continue;

      FreeFound := SearchFree(MethodNode, VarNameLow, False, FreeInFin);

      if not FreeFound then
      begin
        var ReportLine := FindFuncCallAssignLine(MethodNode, VarNameLow);
        if ReportLine = 0 then ReportLine := V.Line;
        AddFinding(V.Name + ' - R'#$FC'ckgabewert', lsWarning, ReportLine);
      end;
    end;
  finally
    LocalVars.Free;
  end;
end;

class procedure TLeakDetector2.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(M, FileName, Results);
  finally
    Methods.Free;
  end;
end;

end.

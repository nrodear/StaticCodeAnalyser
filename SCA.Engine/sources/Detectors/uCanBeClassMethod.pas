unit uCanBeClassMethod;

// Detektor: Instance-Methode greift weder auf Self noch auf Instanz-Felder
// zu - waere als `class function` / `class procedure` sauberer.
//
// Pattern (Code Smell, Sonar-50 #50):
//   TMath = class
//     function Add(A, B: Integer): Integer;
//   end;
//
//   function TMath.Add(A, B: Integer): Integer;
//   begin
//     Result := A + B;          // nutzt nur Parameter, kein Self
//   end;
//
// Korrekt:
//   TMath = class
//     class function Add(A, B: Integer): Integer; static;
//   end;
//
// Begruendung: eine Methode ohne Zugriff auf den Instanz-State braucht
// keinen impliziten Self-Parameter. Class-Method spart einen Pointer-
// Pass, macht den "stateless"-Charakter explizit, und kann ohne Objekt-
// Instanz aufgerufen werden.
//
// Erkennung (AST):
//   * nkMethod-Knoten mit echtem Body (kein Forward).
//   * Skip wenn TypeRef ';class' (schon class method).
//   * Skip wenn TypeRef ';virtual'/';abstract'/';override'/';dynamic'
//     - virtual-Methoden haben Polymorphismus-Vertrag, dort macht
//     class-method-Refactoring keinen Sinn.
//   * Walk descendants: Identifier 'self' kommt vor -> ist Instance-
//     Methode legitim. ODER ein Field-Read/-Write der Form 'F<Name>'
//     oder 'F<Name>.<X>' -> ebenfalls Instance.
//   * Sonst: Finding.
//
// Limitierungen:
//   * Cross-method-Aufruf wie `Self.Bar(...)` auf eine Sibling-Methode
//     muss als Self-Zugriff erkannt werden - wir matchen jeden Identifier
//     namens 'self' (case-insensitive). Property-Read `MyProp` ohne
//     Self.-Prefix wird als legitimer Instance-Zugriff via Property
//     erkannt - der Property-Lookup-Zugriff laeuft ueber das Instance-
//     Layout, also implizit ueber Self. Heuristik: das pruefen wir
//     nicht; FP-Risiko bei Properties ohne Self.-Prefix.
//   * Methoden-Aufruf `Foo` ohne Self. (in Pascal legal) - kann sowohl
//     class als auch instance methods rufen. Wir flaggen das nicht,
//     wenn Self ansonsten gar nicht vorkommt.
//
// Schweregrad: lsHint - Refactoring-Hinweis, kein Bug.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TCanBeClassMethodDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, GroupedDeclaration, NestedRoutine, RedundantJump, StringConcatInLoop, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils;

function IsAlreadyClassMethod(MethodNode: TAstNode): Boolean;
begin
  Result := Pos(';class', LowerCase(MethodNode.TypeRef)) > 0;
end;

function IsPolymorphicMethod(MethodNode: TAstNode): Boolean;

  function HasDirectiveWord(const Hay, Word: string): Boolean;
  // Robuster Wortgrenzen-Match. TypeRef kann je nach Parser-Output sein:
  //   'procedure;virtual'          (kein Space)
  //   'procedure ; virtual'        (Spaces)
  //   'function: Boolean; virtual; override'
  //   'function: Boolean;virtual;override'
  // Alle Varianten muessen matchen.
  var
    P, L, WL : Integer;
    Before, After : Char;
  begin
    Result := False;
    WL := Length(Word);
    L  := Length(Hay);
    P  := 1;
    while True do
    begin
      P := PosEx(Word, Hay, P);
      if P = 0 then Exit(False);
      Before := #0;
      if P > 1 then Before := Hay[P - 1];
      After := #0;
      if P + WL - 1 < L then After := Hay[P + WL];
      // Wort-Grenze: davor kein Identifier-Char, danach kein Identifier-Char
      if not CharInSet(Before, ['a'..'z', '0'..'9', '_']) and
         not CharInSet(After,  ['a'..'z', '0'..'9', '_']) then
        Exit(True);
      P := P + WL;
    end;
  end;

var
  Low : string;
begin
  Low := LowerCase(MethodNode.TypeRef);
  Result := HasDirectiveWord(Low, 'virtual')
         or HasDirectiveWord(Low, 'override')
         or HasDirectiveWord(Low, 'dynamic')
         or HasDirectiveWord(Low, 'abstract')
         or HasDirectiveWord(Low, 'message')      // VCL-Message-Handler
         or HasDirectiveWord(Low, 'reintroduce'); // Hide-Inherited mit gleichem Namen
end;

function IsEventHandlerSignature(MethodNode: TAstNode): Boolean;
// True wenn die Methode eine Event-Handler-Signatur hat - mind. 1 Parameter
// 'Sender: TObject'. Solche Methoden werden vom Form-Designer per DFM zur
// Laufzeit an Komponenten-Events gebunden und MUESSEN Instance-Methods sein.
// Heuristik:
//   * Mind. ein nkParam-Child der Methode.
//   * Erster Parameter hat Name 'Sender' (case-insensitive) ODER
//     TypeRef matched 'tobject' (case-insensitive).
// Faengt FormCreate(Sender: TObject), btnClick(Sender: TObject),
// OnFilter(Sender: TObject; const Item: TItem; var Accept: Boolean) etc.
var
  Child : TAstNode;
begin
  Result := False;
  for Child in MethodNode.Children do
  begin
    if Child.Kind <> nkParam then Continue;
    if SameText(Child.Name, 'Sender') then Exit(True);
    if Pos('tobject', LowerCase(Child.TypeRef)) > 0 then Exit(True);
    Exit;                              // nur ersten Parameter prufen
  end;
end;

function HasBodyBlock(MethodNode: TAstNode): Boolean;
// Methode hat einen Body wenn entweder
//   * nkBlock als direktes Child (ParseBlock-Wrapper um `begin..end`), oder
//   * eine Body-Statement-Kind direkt darin steht (defensiv, alte AST-Form).
// Forward-Declarations ohne `begin` haben keinen nkBlock und werden
// korrekt geskippt.
var Child: TAstNode;
begin
  Result := False;
  for Child in MethodNode.Children do
    if (Child.Kind = nkBlock) or
       (Child.Kind in [nkAssign, nkCall, nkIfStmt, nkCaseStmt, nkForStmt,
                       nkWhileStmt, nkRepeatStmt, nkTryExcept, nkTryFinally,
                       nkRaise, nkExit, nkInherited, nkLocalVar]) then
      Exit(True);
end;

// True wenn IRGENDWO im Subtree der Identifier 'self' (case-insensitive)
// vorkommt oder ein Field-Reference der Form 'F<Buchstabe>' (klassische
// Delphi-Konvention fuer Felder).
function HasSelfOrFieldAccess(N: TAstNode): Boolean;
var
  Child : TAstNode;
  NameLow : string;
  Lead : string;
  i : Integer;
begin
  NameLow := LowerCase(N.Name);
  if NameLow = 'self' then Exit(True);
  // Field-Zugriff mit Self.<Field>-Prefix
  if StartsText('self.', N.Name) then Exit(True);
  // Field-Konvention auf das FUEHRENDE Identifier-Segment anwenden. Der
  // Parser legt gepunktete Designatoren ('FList.Add', 'fOwner.Count') als
  // EINEN Node-Namen ab - die alte Pruefung 'Pos(.)=0' verwarf daher jeden
  // Feldzugriff via Methode/Property/Index als "kein Feld" (Real-World-FP
  // 2026-06-21: ~13/15 SCA148 FP). Konvention: 'F'/'f' + GROSSBUCHSTABE
  // (FList, fOwner, fUpdateSQL). Der Grossbuchstabe als 2. Zeichen grenzt
  // gegen RTL-Funktionen ab (Format, Free, FloatToStr -> 2. Zeichen klein).
  Lead := '';
  for i := 1 to Length(N.Name) do
    if CharInSet(N.Name[i], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      Lead := Lead + N.Name[i]
    else
      Break;
  if (Length(Lead) >= 2) and CharInSet(Lead[1], ['F', 'f'])
     and CharInSet(Lead[2], ['A'..'Z']) then
    Exit(True);
  // Inherited zaehlt als Polymorphie-Indikator (sollte vorher bereits
  // ueber TypeRef geskippt sein, hier defensiv).
  if N.Kind = nkInherited then Exit(True);
  for Child in N.Children do
    if HasSelfOrFieldAccess(Child) then Exit(True);
  Result := False;
end;

// Method-Header gehoert zu einer Klasse wenn der Name ein Punkt enthaelt:
// 'TFoo.Bar' -> ja. Standalone procedures ohne Owner-Klasse haben keinen
// Punkt und sind nicht refactorbar.
function BelongsToClass(MethodNode: TAstNode): Boolean;
begin
  Result := Pos('.', MethodNode.Name) > 0;
end;

function UnqualifiedMethodName(const MethName: string): string;
var
  Dot : Integer;
begin
  Dot := Pos('.', MethName);
  if Dot > 0 then
    Result := Copy(MethName, Dot + 1, MaxInt)
  else
    Result := MethName;
end;

// True wenn IRGENDWO in AllMeths eine andere nkMethod-Deklaration des
// gleichen Method-Namens existiert, die als polymorph markiert ist.
// Interface-Decls tragen die Direktiven (`; virtual; override; abstract`),
// die Implementations-Bodies haben sie nicht - wir muessen also den
// passenden Interface-Eintrag finden.
function HasPolymorphicSiblingDecl(M: TAstNode;
  AllMeths: TList<TAstNode>): Boolean;
var
  Other : TAstNode;
  MUnq, OUnq : string;
begin
  Result := False;
  MUnq := UnqualifiedMethodName(M.Name);
  if MUnq = '' then Exit;
  for Other in AllMeths do
  begin
    if Other = M then Continue;
    OUnq := UnqualifiedMethodName(Other.Name);
    if not SameText(OUnq, MUnq) then Continue;
    if IsPolymorphicMethod(Other) or IsAlreadyClassMethod(Other) then
      Exit(True);
  end;
end;

// --- Klassen-Member-Aufloesung gegen bare Instanz-Zugriffe -------------------
// HasSelfOrFieldAccess prueft nur Node.Name (LHS/Call-Ziel) + die F-Konvention.
// Damit entgehen ihm bare Zugriffe auf Instanz-Member ueber Identifier, die NICHT
// der F-Konvention folgen und im RHS-Blob stehen (Parser legt den ganzen RHS als
// String in nkAssign.TypeRef ab):
//   H := GetClientHeightInLines * FColCount - 1;   // FColCount im RHS-Blob
//   PPN := FindNode(S); DeleteNode(PPN^);          // Sibling-Instanz-Methoden
// Folge: ~87% SCA148-FP (Audit). Loesung: pro Klasse die deklarierten Member
// (Felder/Properties/Methoden) sammeln und im Methoden-Body (Name UND TypeRef)
// nach diesen Identifiern suchen - ein Treffer = impliziter Self-Zugriff.

function ScanTextForMember(const S: string; Members: THashSet<string>): Boolean;
var
  i, n, st : Integer;
begin
  Result := False;
  if (S = '') or (Members.Count = 0) then Exit;
  n := Length(S);
  i := 1;
  while i <= n do
  begin
    if CharInSet(S[i], ['A'..'Z', 'a'..'z', '_']) then
    begin
      st := i;
      while (i <= n) and CharInSet(S[i], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
        Inc(i);
      if Members.Contains(LowerCase(Copy(S, st, i - st))) then Exit(True);
    end
    else
      Inc(i);
  end;
end;

// Sammelt die Member-Namen (lowercase, unqualifiziert) einer nkClass aus ihren
// nkVisibilitySection-Kindern (nkField/nkProperty/nkMethod).
procedure CollectClassMembers(ClassNode: TAstNode; Target: THashSet<string>);
var
  Child : TAstNode;
begin
  for Child in ClassNode.Children do
  begin
    case Child.Kind of
      nkField, nkProperty, nkMethod:
        if Child.Name <> '' then
          Target.Add(LowerCase(UnqualifiedMethodName(Child.Name)));
      nkVisibilitySection:
        CollectClassMembers(Child, Target);  // Member liegen in den Sektionen
    end;
  end;
end;

// True wenn der Body von M irgendwo einen Identifier referenziert, der ein
// deklarierter Member der eigenen Klasse ist (bare Feld/Property/Sibling-Call).
function BodyRefsInstanceMember(M: TAstNode; Members: THashSet<string>): Boolean;

  function Walk(N: TAstNode): Boolean;
  var Child: TAstNode;
  begin
    if ScanTextForMember(N.Name, Members) then Exit(True);
    if ScanTextForMember(N.TypeRef, Members) then Exit(True);
    for Child in N.Children do
      if Walk(Child) then Exit(True);
    Result := False;
  end;

var
  Child : TAstNode;
begin
  Result := False;
  if Members.Count = 0 then Exit;
  for Child in M.Children do
  begin
    // Deklarationen (Parameter/lokale Var) sind kein Member-Zugriff - ihre
    // Namen koennten zufaellig mit Membern kollidieren -> ueberspringen.
    if Child.Kind in [nkParam, nkLocalVar] then Continue;
    if Walk(Child) then Exit(True);
  end;
end;

function ClassKeyOf(const MethName: string): string;
var
  Dot : Integer;
begin
  Dot := LastDelimiter('.', MethName);
  if Dot > 0 then Result := LowerCase(Copy(MethName, 1, Dot - 1))
             else Result := '';
end;

function FirstTypeRefToken(const S: string): string;
// Erstes Identifier-Token aus ClassNode.TypeRef = die Parent-Klasse.
// ParseClassBody legt 'class(TBar, IFoo)' als 'TBar IFoo' ab -> 'tbar'.
var
  i, n : Integer;
begin
  Result := '';
  n := Length(S);
  i := 1;
  while (i <= n) and not CharInSet(S[i], ['A'..'Z', 'a'..'z', '_']) do Inc(i);
  while (i <= n) and CharInSet(S[i], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
  begin
    Result := Result + S[i];
    Inc(i);
  end;
  Result := LowerCase(Result);
end;

class procedure TCanBeClassMethodDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods    : TList<TAstNode>;
  Classes    : TList<TAstNode>;
  MemberDict : TObjectDictionary<string, THashSet<string>>;  // eigene Member
  ParentOf   : TDictionary<string, string>;                  // Klasse -> Parent (in-Unit)
  FullDict   : TObjectDictionary<string, THashSet<string>>;  // eigene + In-Unit-Vorfahren
  M, C       : TAstNode;
  Members    : THashSet<string>;
  Key        : string;

  // Stufe 2: Member-Set inkl. In-Unit-Vererbungskette aufloesen (memoized,
  // cycle-safe). Faengt bare Zugriffe auf geerbte Felder/Properties/Methoden
  // (z.B. Alcinoe TALExprAbstractFuncSym.CompileFirstArg nutzt geerbtes
  // Lexer/CompileParser). Cross-Unit-Vererbung (VCL) bleibt offen.
  function ResolveFull(const ClsKey: string): THashSet<string>;
  var
    HS, Own, ParentSet : THashSet<string>;
    ParentKey, S       : string;
  begin
    if FullDict.TryGetValue(ClsKey, HS) then Exit(HS);
    HS := THashSet<string>.Create;
    FullDict.Add(ClsKey, HS);                 // VOR Rekursion -> Cycle-Guard
    if MemberDict.TryGetValue(ClsKey, Own) then
      for S in Own do HS.Add(S);
    if ParentOf.TryGetValue(ClsKey, ParentKey) and (ParentKey <> '')
       and MemberDict.ContainsKey(ParentKey) then
      for S in ResolveFull(ParentKey) do HS.Add(S);
    Result := HS;
  end;

begin
  Methods := UnitNode.FindAll(nkMethod);
  // Pro Klasse die deklarierten Member + Parent-Bezug sammeln (einmal pro Unit).
  MemberDict := TObjectDictionary<string, THashSet<string>>.Create([doOwnsValues]);
  ParentOf   := TDictionary<string, string>.Create;
  FullDict   := TObjectDictionary<string, THashSet<string>>.Create([doOwnsValues]);
  Classes    := UnitNode.FindAll(nkClass);
  try
    for C in Classes do
    begin
      Key := LowerCase(C.Name);
      if Key = '' then Continue;
      if not MemberDict.TryGetValue(Key, Members) then
      begin
        Members := THashSet<string>.Create;
        MemberDict.Add(Key, Members);
      end;
      CollectClassMembers(C, Members);
      ParentOf.AddOrSetValue(Key, FirstTypeRefToken(C.TypeRef));
    end;
    // Volle Member-Sets (eigene + In-Unit-Vorfahren) aufloesen.
    for Key in MemberDict.Keys do ResolveFull(Key);

    for M in Methods do
    begin
      if not BelongsToClass(M) then Continue;
      if IsAlreadyClassMethod(M) then Continue;
      if IsPolymorphicMethod(M) then Continue;
      // Cross-Decl: Interface-Eintrag der Methode kann ;virtual/;override
      // tragen waehrend der Implementations-Header nur 'function' fuehrt.
      if HasPolymorphicSiblingDecl(M, Methods) then Continue;
      if not HasBodyBlock(M) then Continue;
      // Skip Constructor/Destructor - die haben implizit anderen Vertrag.
      if LowerCase(Trim(M.TypeRef)).StartsWith('constructor') then Continue;
      if LowerCase(Trim(M.TypeRef)).StartsWith('destructor')  then Continue;
      // Event-Handler werden per DFM gebunden -> muessen Instance bleiben.
      // (FormCreate, btnClick, actExecute, OnXxx etc. mit Sender: TObject)
      if IsEventHandlerSignature(M) then Continue;
      if HasSelfOrFieldAccess(M) then Continue;
      // Bare Instanz-Member-Zugriff (Feld/Property/Sibling-Call) ueber die
      // Member-Liste der Klasse inkl. In-Unit-Vorfahren - faengt RHS-Blob-,
      // Sibling- und vererbte-Member-FPs.
      if FullDict.TryGetValue(ClassKeyOf(M.Name), Members) and
         BodyRefsInstanceMember(M, Members) then Continue;

      // Message-Suffix: 'class function' fuer Funktionen, 'class procedure'
      // fuer Prozeduren. TypeRef beginnt mit 'procedure'/'function'/etc.
      var TypeLow := LowerCase(Trim(M.TypeRef));
      var ClassKind : string;
      if TypeLow.StartsWith('procedure') then ClassKind := 'class procedure'
      else                                    ClassKind := 'class function';
      Results.Add(TLeakFinding.New(FileName, M.Name, M.Line,
        Format('Method %s never accesses Self or instance fields - could ' +
               'be declared as `%s`', [M.Name, ClassKind]),
        fkCanBeClassMethod));
    end;
  finally
    Classes.Free;
    FullDict.Free;     // doOwnsValues -> gibt die THashSet-Werte mit frei
    ParentOf.Free;
    MemberDict.Free;   // doOwnsValues -> gibt die THashSet-Werte mit frei
    Methods.Free;
  end;
end;

end.

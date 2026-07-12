unit uUnusedParameter;

// Detector: Method-Parameter, der im Body nirgendwo referenziert wird.
//
// Skip-Regeln (sonst zu viel Rauschen):
//   * Methode ist `override`/`virtual`/`abstract` -> Signature-Konformitaet
//     wichtig, Param-Existenz kann von Basisklasse vorgegeben sein.
//   * Methode hat genau einen `Sender: TObject`-Param (Event-Handler-Pattern).
//   * Param-Name beginnt mit `_` (intentional convention).
//   * Body ist asm-Block oder leer.
//
// Erkennung:
//   * MethodNode.FindAll(nkParam) → Liste der Param-Knoten
//   * Body-Tokens einsammeln (rekursiv Name+TypeRef aller Children)
//   * Pro Param: zaehle case-insensitive Wortgrenzen-Vorkommen im Body
//   * Wenn 0 -> Finding
//
// Severity: lsHint.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TUnusedParameterDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(UnitNode, MethodNode: TAstNode;
      const FileName: string; Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, GroupedDeclaration, NestedRoutine, NestedTry, NilComparison, StringConcatInLoop, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  EMIT_SEVERITY = lsHint;

function IsIdentChar(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

// Modifier-Check via TypeRef-Format aus Parser (siehe 🅳-Fix):
//   'kind[:ret];dir1;dir2'
function HasModifier(MethodNode: TAstNode; const Dir: string): Boolean;
begin
  Result := Pos(';' + LowerCase(Dir), LowerCase(MethodNode.TypeRef)) > 0;
end;

// Methodennamen `TFoo.Bar` -> Klasse `TFoo`, MethodenName `Bar`.
function SplitQualified(const MethodName: string;
  out ClassName, BareName: string): Boolean;
var
  DotPos : Integer;
begin
  DotPos := Pos('.', MethodName);
  if DotPos <= 0 then
  begin
    ClassName := '';
    BareName  := MethodName;
    Exit(False);
  end;
  ClassName := Copy(MethodName, 1, DotPos - 1);
  BareName  := Copy(MethodName, DotPos + 1, MaxInt);
  Result := True;
end;

// Sucht im Unit-Tree die Class-Declaration, die zu einer Implementation
// gehoert. Liefert deren nkMethod-Knoten (die HAT die Modifier in TypeRef)
// oder nil.
function FindDeclaration(UnitNode: TAstNode; const ClassName,
  BareName: string): TAstNode;
var
  Classes : TList<TAstNode>;
  Cls : TAstNode;
  Methods : TList<TAstNode>;
  M : TAstNode;
  LowClassWanted, LowBareWanted : string;
begin
  Result := nil;
  if (UnitNode = nil) or (ClassName = '') then Exit;
  LowClassWanted := LowerCase(ClassName);
  LowBareWanted  := LowerCase(BareName);
  Classes := UnitNode.FindAll(nkClass);
  try
    for Cls in Classes do
    begin
      if LowerCase(Cls.Name) <> LowClassWanted then Continue;
      Methods := Cls.FindAll(nkMethod);
      try
        for M in Methods do
          if LowerCase(M.Name) = LowBareWanted then
            Exit(M);
      finally
        Methods.Free;
      end;
    end;
  finally
    Classes.Free;
  end;
end;

// Inheritance-Hook-Check: an der Implementation selbst (selten) ODER an
// ihrer zugehoerigen Class-Declaration (Default-Fall - Parser legt die
// Modifier nur an der Declaration ab).
function IsInheritanceHook(UnitNode, MethodNode: TAstNode): Boolean;

  function CheckOne(N: TAstNode): Boolean;
  begin
    // Hinweis: 'message' ist KEINE vom Parser erkannte Method-Direktive
    // (IsMethodDirective/IsMethodDirectiveIdent kennen sie nicht; 'message N'
    // mit Konstanten-Arg landet nicht als ';message' im TypeRef). Message-
    // Handler-Erkennung braucht daher einen Parser-Followup, nicht HasModifier.
    Result := (N <> nil) and
              (HasModifier(N, 'override')
            or HasModifier(N, 'virtual')
            or HasModifier(N, 'abstract')
            or HasModifier(N, 'dynamic'));
  end;

var
  ClassName, BareName : string;
  Decl : TAstNode;
begin
  Result := CheckOne(MethodNode);
  if Result then Exit;

  if SplitQualified(MethodNode.Name, ClassName, BareName) then
  begin
    Decl := FindDeclaration(UnitNode, ClassName, BareName);
    Result := CheckOne(Decl);
  end;
end;

// Event-Handler-Konvention: der ERSTE Parameter ist 'Sender' (bzw. *Sender)
// oder vom Typ TObject. Solche Methoden bindet der Form-Designer per DFM an
// Component-Events; ihre Signatur ist durch den Event-Typ vorgegeben, daher
// sind ungenutzte Parameter unvermeidbar (kein Finding).
//
// Erfasst BEWUSST auch Multi-Param-Handler (OnKeyPress(Sender; var Key),
// OnDrawCell(Sender; ACol, ARow, Rect, State), OnFilter(Sender; Item; Accept)).
// Frueher nur Single-`Sender` -> FP bei jedem Mehr-Param-Handler mit einem
// ungenutzten Pflicht-Param (Real-World 2026-06-28: dominante SCA054-FP-Klasse).
function IsLikelyEventHandler(MethodNode: TAstNode): Boolean;
var
  Params : TList<TAstNode>;
  LowName, LowType : string;
begin
  Result := False;
  Params := MethodNode.FindAll(nkParam);
  try
    if Params.Count = 0 then Exit;
    LowName := LowerCase(Trim(Params[0].Name));   // Modifier-Prefix stoert EndsWith nicht
    LowType := LowerCase(Params[0].TypeRef);
    Result := (LowName = 'sender') or LowName.EndsWith('sender')
              or (Pos('tobject', LowType) > 0);
  finally
    Params.Free;
  end;
end;

procedure CollectAllTokens(Root: TAstNode; SB: TStringBuilder);
var
  Stack : TStack<TAstNode>;
  Cur : TAstNode;
  i : Integer;
begin
  if Root = nil then Exit;
  Stack := TStack<TAstNode>.Create;
  try
    Stack.Push(Root);
    while Stack.Count > 0 do
    begin
      Cur := Stack.Pop;
      if Cur.Name    <> '' then SB.Append(' ').Append(Cur.Name);
      if Cur.TypeRef <> '' then SB.Append(' ').Append(Cur.TypeRef);
      for i := 0 to Cur.Children.Count - 1 do
        Stack.Push(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

class procedure TUnusedParameterDetector.AnalyzeMethod(UnitNode, MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Params : TList<TAstNode>;
  P : TAstNode;
  Name, LowName : string;
  BodySB : TStringBuilder;
  BodyLow : string;
  RefCount : Integer;
  F : TLeakFinding;
begin
  // Declarations (in nkClass) skippen - die haben keinen Body und keine
  // sinnvolle Reference-Count. Ihre Modifier konsultieren wir aber von
  // der zugehoerigen Implementation aus (siehe IsInheritanceHook).
  if not MethodNode.HasChild(nkBlock) then Exit;

  if IsInheritanceHook(UnitNode, MethodNode) then Exit;
  if IsLikelyEventHandler(MethodNode) then Exit;
  // Track B1 (2026-07-12): der SCA028-Follow-up-Guard (IsKeywordRoutineName)
  // ist entfernt - der Parser-Fix (Write/Read-Statement-Dispatch) haengt jetzt
  // die Bodies keyword-benannter Methoden korrekt an, Param-Uses sind sichtbar.

  Params := MethodNode.FindAll(nkParam);
  BodySB := TStringBuilder.Create;
  try
    if Params.Count = 0 then Exit;
    CollectAllTokens(MethodNode, BodySB);
    BodyLow := LowerCase(BodySB.ToString);

    for P in Params do
    begin
      // Parser legt Modifier `var/const/out` als Name-Praefix ab
      // ('const X' statt nur 'X'); Param-Name = letztes Wort.
      Name := Trim(P.Name);
      if Name = '' then Continue;
      var SpaceIdx := LastDelimiter(' ', Name);
      if SpaceIdx > 0 then
        Name := Copy(Name, SpaceIdx + 1, MaxInt);
      if Name.StartsWith('_') then Continue;

      LowName := LowerCase(Name);

      // Param-Deklaration ist EIN Vorkommen. Mindestens 2 noetig fuer "genutzt".
      RefCount := 0;
      var Pos1 := 1;
      while True do
      begin
        Pos1 := Pos(LowName, BodyLow, Pos1);
        if Pos1 = 0 then Break;
        var Before : Char := #0;
        if Pos1 > 1 then Before := BodyLow[Pos1 - 1];
        var After  : Char := #0;
        if Pos1 + Length(LowName) - 1 < Length(BodyLow) then
          After := BodyLow[Pos1 + Length(LowName)];
        if not IsIdentChar(Before) and not IsIdentChar(After) then
          Inc(RefCount);
        Pos1 := Pos1 + Length(LowName);
      end;

      if RefCount <= 1 then
      begin
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := MethodNode.Name;
        F.LineNumber := IntToStr(P.Line);
        F.MissingVar := Format(
          'Unused parameter: %s (never read in method body)', [Name]);
        F.SetKind(fkUnusedParameter);
        Results.Add(F);
      end;
    end;
  finally
    BodySB.Free;
    Params.Free;
  end;
end;

class procedure TUnusedParameterDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M : TAstNode;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(UnitNode, M, FileName, Results);
  finally
    Methods.Free;
  end;
end;

end.

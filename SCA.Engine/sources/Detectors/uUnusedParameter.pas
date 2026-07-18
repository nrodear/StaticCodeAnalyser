unit uUnusedParameter;

// Detector: Method-Parameter, der im Body nirgendwo referenziert wird.
//
// Skip-Regeln (sonst zu viel Rauschen):
//   * Methode ist `override`/`virtual`/`abstract` -> Signature-Konformitaet
//     wichtig, Param-Existenz kann von Basisklasse vorgegeben sein.
//   * Methode hat genau einen `Sender: TObject`-Param (Event-Handler-Pattern).
//   * Body enthaelt bare `inherited;` oder klammerloses `inherited Foo;` ->
//     Delphi reicht die aktuellen Parameter implizit an die Elternmethode weiter
//     (Signatur vom Parent vorgegeben, Param nicht wirklich ungenutzt).
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
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uDetectorUtils, uFileTextCache;

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

// True, wenn der Body ein parameter-implizit-weiterreichendes 'inherited'
// enthaelt. Delphi reicht die AKTUELLEN Methodenparameter automatisch an die
// Elternmethode weiter bei
//   * bare  'inherited;'      -> Parser: nkInherited mit LEEREM Name
//   * klammerlos 'inherited Foo;' -> nkInherited.Name = 'Foo' (kein '(')
// In beiden Formen ist ein "ungenutzter" Parameter in Wahrheit weitergeleitet
// (Signatur vom Parent vorgegeben) -> KEIN echter unused-Param. Nur
// 'inherited Foo(args)' (Name enthaelt '(') reicht NICHT implizit weiter, dort
// kann ein Param genuin ungenutzt sein -> nicht skippen.
// Wichtig: der Parser konsumiert das Keyword 'inherited' und speichert nur den
// Call-Ausdruck als Name; ein Text-Scan nach "inherited" wuerde daher genau den
// dominanten bare-Fall (leerer Name) verfehlen -> Erkennung MUSS ueber den
// nkInherited-Knotentyp laufen. (Core-Audit 2026-07-18, Welle 1 5%-FP-Konzept:
// ~7.950 FP, groesste absolute FP-Klasse, monoton + TP-safe.)
function ForwardsParamsViaInherited(MethodNode: TAstNode): Boolean;
var
  Inh : TList<TAstNode>;
  N : TAstNode;
begin
  Result := False;
  Inh := MethodNode.FindAll(nkInherited);
  try
    for N in Inh do
      if Pos('(', N.Name) = 0 then   // '' (bare) oder 'Name' ohne Klammern
        Exit(True);
  finally
    Inh.Free;
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
  // Ist-Messung 2026-07-18 (SCA054-FP-Klasse 'nested-routine-Nutzung', 3/5 der
  // Sample-FPs): der Parser verwirft nested-routine-Bodies aus dem Method-AST
  // (nur nkNestedRange-Marker bleiben, Line=Start/TypeRef=EndLine) -> ein Param,
  // der NUR in einer nested proc gelesen wird, war unsichtbar. Lazy-Fallback:
  // die Quell-Zeilen der Marker-Ranges (kommentar-/string-gestrippt - Kommentare
  // zaehlen NIE als Use) wort-gebunden nach dem Param-Namen scannen. Monoton
  // (nur zusaetzlicher Skip). Rest-Risiko Shadowing (gleichnamige nested-lokale
  // Var) unterdrueckt einen echten Fund - akzeptiert fuer lsHint, konsistent
  // mit der Text-Zaehlung des Detektors.
  NestedMarks   : TList<TAstNode>;
  StrippedLines : TArray<string>;
  StrippedReady : Boolean;
  SrcLines      : TStringList;
  SrcOwned      : Boolean;

  procedure EnsureStripped;
  var
    Code    : string;
    LineFor : TArray<Integer>;
  begin
    if StrippedReady then Exit;
    StrippedReady := True;
    SrcLines := AcquireLines(FileName, SrcOwned, nil);
    if SrcLines = nil then Exit;
    Code := TDetectorUtils.StripStringsAndCommentsCached(
      SrcLines, LineFor, nil, FileName, ' ');
    StrippedLines := Code.Split([#10]);
  end;

  function UsedInNestedRanges(const NameLow: string): Boolean;
  var
    M : TAstNode;
    li, EndL, q, NL : Integer;
    L : string;
  begin
    Result := False;
    if NestedMarks.Count = 0 then Exit;
    EnsureStripped;
    if Length(StrippedLines) = 0 then Exit;
    NL := Length(NameLow);
    for M in NestedMarks do
    begin
      EndL := StrToIntDef(M.TypeRef, M.Line);
      for li := M.Line to EndL do
      begin
        if (li < 1) or (li > Length(StrippedLines)) then Continue;
        L := LowerCase(StrippedLines[li - 1]);
        q := Pos(NameLow, L);
        while q > 0 do
        begin
          if ((q = 1) or not IsIdentChar(L[q - 1])) and
             ((q + NL > Length(L)) or not IsIdentChar(L[q + NL])) then
            Exit(True);
          q := Pos(NameLow, L, q + 1);
        end;
      end;
    end;
  end;

begin
  // Declarations (in nkClass) skippen - die haben keinen Body und keine
  // sinnvolle Reference-Count. Ihre Modifier konsultieren wir aber von
  // der zugehoerigen Implementation aus (siehe IsInheritanceHook).
  if not MethodNode.HasChild(nkBlock) then Exit;

  if IsInheritanceHook(UnitNode, MethodNode) then Exit;
  if IsLikelyEventHandler(MethodNode) then Exit;
  if ForwardsParamsViaInherited(MethodNode) then Exit;
  // Track B1 (2026-07-12): der SCA028-Follow-up-Guard (IsKeywordRoutineName)
  // ist entfernt - der Parser-Fix (Write/Read-Statement-Dispatch) haengt jetzt
  // die Bodies keyword-benannter Methoden korrekt an, Param-Uses sind sichtbar.

  StrippedReady := False;
  SrcLines      := nil;
  SrcOwned      := False;
  NestedMarks   := TList<TAstNode>.Create;
  Params := MethodNode.FindAll(nkParam);
  BodySB := TStringBuilder.Create;
  try
    if Params.Count = 0 then Exit;
    // nkNestedRange-Marker der verworfenen nested routines einsammeln
    // (direkte MethodNode-Children, siehe uParser2 ~Z.1319).
    for var NR in MethodNode.Children do
      if NR.Kind = nkNestedRange then NestedMarks.Add(NR);
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
        // Nested-Routine-Fallback (s. Kommentar oben): Param wird in einer vom
        // Parser verworfenen nested proc gelesen -> benutzt, kein Fund.
        if UsedInNestedRanges(LowName) then Continue;
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
    NestedMarks.Free;
    if SrcLines <> nil then ReleaseLines(SrcLines, SrcOwned);
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

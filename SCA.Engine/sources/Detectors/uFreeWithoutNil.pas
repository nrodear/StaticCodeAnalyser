unit uFreeWithoutNil;

// Detektor: <ident>.Free ohne nachfolgendes <ident> := nil (oder
// FreeAndNil(<ident>) statt der Zwei-Schritt-Variante).
//
// Pattern (Code Smell, Sonar-50 #25):
//   procedure Foo;
//   var L: TStringList;
//   begin
//     L := TStringList.Create;
//     try
//       ...
//     finally
//       L.Free;                 // <-- ohne L := nil; -> dangling pointer
//     end;
//     // L ist hier nicht nil, jeder Folge-Use ist Use-After-Free
//   end;
//
// Korrekt:
//   FreeAndNil(L);
//
// Heuristik (AST):
//   * Walk nkCall mit Name passend zu `<ident>.Free` (oder `.Destroy`).
//   * Schaue im SELBEN Method-Body nach einer Folge-Anweisung
//     `<ident> := nil` ODER `FreeAndNil(<ident>)`. Wenn vorhanden -> OK.
//   * Wenn die Free-Anweisung die LETZTE im Body ist (kein Folge-Use
//     moeglich) -> kein Befund (Method-Exit-Pattern, common in destructor).
//
// Limitierung: einfache lexische Heuristik, keine Path-Analysis. False
// Positives bei try/finally L.Free; end mit `Exit;`/`raise;` direkt
// nach Free werden ggf. trotzdem gemeldet.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TFreeWithoutNilDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file ConcatToFormat
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils;

// Letzte Segment-Komponente vor `.Free`/`.Destroy` extrahieren.
// `L.Free` -> `L`; `Self.FList.Free` -> `FList`; `'foo'` -> ''.
function ExtractFreeReceiver(const CallName: string): string;
var
  Low : string;
  i, DotPos, EndPos : Integer;
begin
  Result := '';
  Low := LowerCase(CallName);
  // Suche das ".free" oder ".destroy" am Ende.
  if EndsText('.free', Low) then
    EndPos := Length(CallName) - 5
  else if EndsText('.destroy', Low) then
    EndPos := Length(CallName) - 8
  else
    Exit;
  if EndPos <= 0 then Exit;

  // Identifier links vom letzten '.' bis Whitespace/Operator zurueck.
  DotPos := 0;
  for i := EndPos downto 1 do
    if CallName[i] = '.' then begin DotPos := i; Break; end;

  if DotPos > 0 then
    Result := Trim(Copy(CallName, DotPos + 1, EndPos - DotPos))
  else
    Result := Trim(Copy(CallName, 1, EndPos));
end;

function IsNilAssignTo(const N: TAstNode; const IdentLow: string): Boolean;
// True wenn N ein nkAssign der Form `<ident> := nil` oder `<owner>.<ident> := nil` ist.
var
  Lhs, LhsLow, RhsLow : string;
begin
  Result := False;
  if N.Kind <> nkAssign then Exit;
  Lhs := N.Name;
  LhsLow := LowerCase(Lhs);
  // Akzeptiere `ident`, `self.ident`, `foo.ident` als LHS-Variante.
  if (LhsLow = IdentLow)
     or EndsText('.' + IdentLow, LhsLow) then
  begin
    // RHS-Text liegt im TypeRef (uParser2 ParseStatement Z. 1618:
    // Node.TypeRef := FullRHS). Children sind in der Regel leer.
    RhsLow := LowerCase(Trim(N.TypeRef));
    if RhsLow = 'nil' then Exit(True);
    // Defensiv fuer aeltere AST-Formen.
    for var Child in N.Children do
      if SameText(Trim(Child.Name), 'nil') then Exit(True);
  end;
end;

function IsFreeAndNilOf(const N: TAstNode; const IdentLow: string): Boolean;
// True wenn N ein nkCall `FreeAndNil(<ident>)` ist.
begin
  Result := False;
  if N.Kind <> nkCall then Exit;
  if not StartsText('freeandnil(', LowerCase(Trim(N.Name))) then Exit;
  Result := Pos('(' + IdentLow + ')', LowerCase(N.Name.Replace(' ', ''))) > 0;
end;

class procedure TFreeWithoutNilDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
  Calls   : TList<TAstNode>;
  N       : TAstNode;
  Recv    : string;
  RecvLow : string;
  F       : TLeakFinding;

  function HasNilOutAfter(MethodNode, FreeCall: TAstNode;
    const IdentLow: string): Boolean;
  // Ehemals: `if S = FreeCall then AfterFree := True` - das konnte nie
  // matchen weil Stmts nur nkAssign sammelt und FreeCall ein nkCall ist
  // (Reference-Equality scheitert an Kind-Mismatch). Daher Line-basiert:
  // Statement mit Line > FreeCall.Line gilt als "nach dem Free".
  var
    Stmts : TList<TAstNode>;
    S     : TAstNode;
  begin
    Result := False;
    Stmts := MethodNode.FindAll(nkAssign);
    try
      for S in Stmts do
      begin
        if S.Line <= FreeCall.Line then Continue;
        if IsNilAssignTo(S, IdentLow) then Exit(True);
      end;
    finally
      Stmts.Free;
    end;
    Stmts := MethodNode.FindAll(nkCall);
    try
      for S in Stmts do
      begin
        if S.Line <= FreeCall.Line then Continue;
        if IsFreeAndNilOf(S, IdentLow) then Exit(True);
      end;
    finally
      Stmts.Free;
    end;
  end;

  function IsLastStmtOfMethod(MethodNode, FreeCall: TAstNode): Boolean;
  var
    AllCalls : TList<TAstNode>;
  begin
    Result := False;
    AllCalls := MethodNode.FindAll(nkCall);
    try
      // Wenn Free der letzte nkCall im Method-Body ist, kein Folge-Use moeglich.
      if (AllCalls.Count > 0) and (AllCalls[AllCalls.Count - 1] = FreeCall) then
        Result := True;
    finally
      AllCalls.Free;
    end;
  end;

var
  LocalNames : TDictionary<string, Boolean>;
  LV         : TAstNode;
  LVs        : TList<TAstNode>;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      // Lokale Var-Namen einmal pro Methode sammeln. Free-Calls auf Locals
      // sind harmlos, weil die Variable beim Method-Ende sowieso aus dem
      // Scope faellt - kein Dangling-Pointer-Risiko. FreeAndNil ist primaer
      // fuer FELDER relevant (cross-method state). Self-Test fand
      // ~100 FPs durch Locals (uAbstractNotImpl.Methods, uDetectorUtils.Chars, etc).
      LocalNames := TDictionary<string, Boolean>.Create;
      try
        LVs := M.FindAll(nkLocalVar);
        try
          for LV in LVs do
            if LV.Name <> '' then
              LocalNames.AddOrSetValue(LowerCase(Trim(LV.Name)), True);
        finally
          LVs.Free;
        end;

      Calls := M.FindAll(nkCall);
      try
        for N in Calls do
        begin
          Recv := ExtractFreeReceiver(N.Name);
          if Recv = '' then Continue;
          RecvLow := LowerCase(Recv);
          // Receiver darf kein Self/Result/Inherited sein - Free auf Self
          // wird selten von Nil-Out gefolgt (Owner-Pattern).
          if (RecvLow = 'self') or (RecvLow = 'result')
             or (RecvLow = 'inherited') then Continue;
          // Receiver ist eine lokale Variable -> Free reicht, Var faellt
          // beim Method-Ende aus dem Scope. KEIN Finding.
          if LocalNames.ContainsKey(RecvLow) then Continue;

          if HasNilOutAfter(M, N, RecvLow) then Continue;
          if IsLastStmtOfMethod(M, N) then Continue;

          F            := TLeakFinding.Create;
          F.FileName   := FileName;
          F.MethodName := M.Name;
          F.LineNumber := IntToStr(N.Line);
          F.MissingVar := Format(
            '%s.Free without subsequent %s := nil - prefer FreeAndNil(%s)',
            [Recv, Recv, Recv]);
          F.SetKind(fkFreeWithoutNil);
          Results.Add(F);
        end;
      finally
        Calls.Free;
      end;
      finally
        LocalNames.Free;
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.

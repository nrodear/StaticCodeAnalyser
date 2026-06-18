unit uVirtualCallInCtor;

// Detektor: Aufruf einer `virtual`-Methode im Constructor.
//
// Wenn ein Constructor in einer Basisklasse eine virtual-Methode ruft,
// laeuft die ueberschriebene Variante in der abgeleiteten Klasse - aber
// zu einem Zeitpunkt, wo der Sub-Klassen-Constructor noch nicht durch
// ist. Felder sind eventuell null/0, der Override greift auf halb-
// initialisiertes Self zu -> NullPointerException / Subtle-Bug.
//
// Beispiel:
//   type
//     TBase = class
//       constructor Create;
//       procedure Init; virtual;
//     end;
//     TDerived = class(TBase)
//       FCache: TList;
//       procedure Init; override;
//     end;
//
//   constructor TBase.Create;
//   begin
//     Init;            // <-- ruft TDerived.Init, FCache ist noch nil!
//   end;
//
// Algorithmus (single-unit):
//   1. Sammle alle Klassen + ihre Methoden mit Virtual-Markierung
//      (uParser2 haengt 'virtual'/'override'/'dynamic' an TypeRef an).
//   2. Fuer jeden Constructor: alle nkCall-Nodes durchgehen.
//   3. Wenn der Call-Name zu einer Methode der gleichen Klasse passt,
//      die virtual/override/dynamic ist -> Treffer.
//
// Heuristik:
//   * inherited Create / inherited Init: kein Treffer (geht hoch, nicht
//     runter; keine Override-Reflektion).
//   * Self.MyVirtual: Treffer (so wie ohne Self.).
//   * MyVirtual(args): Treffer.
//   * Andere Objekt-Calls (FFoo.DoSomething): kein Treffer.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TVirtualCallInCtorDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file ConcatToFormat, ConsecutiveSection, CyclomaticComplexity, GroupedDeclaration, LongMethod, NestedTry, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  EMIT_SEVERITY = lsError;

function IsConstructor(MethodNode: TAstNode): Boolean;
begin
  Result := LowerCase(Trim(MethodNode.TypeRef)).StartsWith('constructor');
end;

function HasDirective(MethodNode: TAstNode; const Dir: string): Boolean;
var
  Lower : string;
begin
  Lower := LowerCase(MethodNode.TypeRef);
  Result := (Pos(';' + Dir, Lower) > 0);
end;

function IsVirtualLike(MethodNode: TAstNode): Boolean;
// `dynamic` ist semantisch ebenfalls virtual-like, der Lexer kennt das
// Keyword aktuell aber nicht (kein tkKwDynamic, kommt als tkIdent durch
// und wird von IsMethodDirective nicht als Direktive konsumiert). Wenn
// der Lexer um `dynamic` erweitert wird, hier die Liste ergaenzen.
begin
  Result := HasDirective(MethodNode, 'virtual')
         or HasDirective(MethodNode, 'override');
end;

function ExtractCallTarget(const CallName: string): string;
// Aus `Self.Init` -> `Init`, aus `Init(x)` -> `Init`, aus `FFoo.Bar` -> ''
// (Object-Call - nicht relevant).
var
  Trimmed : string;
  DotPos  : Integer;
  Lhs, Rhs: string;
  ParenPos: Integer;
begin
  Result  := '';
  Trimmed := Trim(CallName);
  if Trimmed = '' then Exit;

  // Argument-Liste wegschneiden
  ParenPos := Pos('(', Trimmed);
  if ParenPos > 0 then
    Trimmed := Copy(Trimmed, 1, ParenPos - 1);

  DotPos := Pos('.', Trimmed);
  if DotPos = 0 then Exit(Trim(Trimmed));   // einfacher Call

  Lhs := LowerCase(Trim(Copy(Trimmed, 1, DotPos - 1)));
  Rhs := Trim(Copy(Trimmed, DotPos + 1, MaxInt));
  if Lhs = 'self' then Exit(Rhs);
  // Anderes Objekt - nicht relevant
end;

// Folgt rekursiv den Calls einer non-virtual Methode bis ein virtual
// erreicht wird oder das Depth-Limit greift. ChainOut akkumuliert die
// Call-Kette (lowercase-Method-Namen) damit das Finding den vollen
// Pfad "Init -> DoSetup -> DoStuff" zeigen kann.
//
// 2026-06-18 (Audit_ErrorDetectors E-6 P1): Cross-Method-Helper-
// Detection. Vorher fand der Detector nur direkte Virtual-Calls im
// Ctor. Helper-Pattern ueberging er:
//   constructor TFoo.Create; begin Init; end;   // Init = non-virtual
//   procedure TFoo.Init;     begin DoStuff; end; // DoStuff = virtual!
// → Bug, weil aufrufende Subklasse DoStuff overriden kann.
const
  MAX_CHAIN_DEPTH = 5;   // bei deeper Helpers wird's pathologisch

function FindVirtualInChain(StartName: string;
  MethodByName: TDictionary<string, TAstNode>;
  VirtualByName: TDictionary<string, TAstNode>;
  Visited, ChainOut: TList<string>;
  Depth: Integer): TAstNode;
var
  Method      : TAstNode;
  CallList    : TList<TAstNode>;
  Call        : TAstNode;
  Target, Low : string;
  VMethod     : TAstNode;
  RecurResult : TAstNode;
begin
  Result := nil;
  if Depth > MAX_CHAIN_DEPTH then Exit;
  if Visited.IndexOf(StartName) >= 0 then Exit;   // Zyklus
  Visited.Add(StartName);

  // Method existiert in dieser Klasse? Sonst koennen wir nicht weiter folgen.
  if not MethodByName.TryGetValue(StartName, Method) then Exit;

  CallList := Method.FindAll(nkCall);
  try
    for Call in CallList do
    begin
      Target := ExtractCallTarget(Call.Name);
      if Target = '' then Continue;
      Low := LowerCase(Target);
      if Low.StartsWith('inherited') then Continue;

      // Direkt-Hit: Helper ruft virtual-Method.
      if VirtualByName.TryGetValue(Low, VMethod) then
      begin
        ChainOut.Add(Low);
        Exit(VMethod);
      end;
      // Nicht-virtual, aber in der Klasse - rekursiv folgen.
      if MethodByName.ContainsKey(Low) then
      begin
        ChainOut.Add(Low);
        RecurResult := FindVirtualInChain(Low, MethodByName, VirtualByName,
          Visited, ChainOut, Depth + 1);
        if Assigned(RecurResult) then Exit(RecurResult);
        // Sackgasse - Element aus Chain wieder rausnehmen.
        ChainOut.Delete(ChainOut.Count - 1);
      end;
    end;
  finally
    CallList.Free;
  end;
end;

class procedure TVirtualCallInCtorDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Classes         : TList<TAstNode>;
  ClassNode       : TAstNode;
  VirtualByName   : TDictionary<string, TAstNode>;
  MethodByName    : TDictionary<string, TAstNode>;
  Methods         : TList<TAstNode>;
  M, Ctor, Call   : TAstNode;
  CtorList        : TList<TAstNode>;
  CallList        : TList<TAstNode>;
  Target, LowName : string;
  VMethod         : TAstNode;
  AlreadyReported : TList<string>;
  RepKey, Msg     : string;
  ClassImplCtors  : TList<TAstNode>;
  Visited, Chain  : TList<string>;
begin
  Classes := UnitNode.FindAll(nkClass);
  try
    for ClassNode in Classes do
    begin
      VirtualByName := TDictionary<string, TAstNode>.Create;
      MethodByName  := TDictionary<string, TAstNode>.Create;
      try
        // Alle virtuellen + ALLE Methoden der Klasse einsammeln.
        // MethodByName brauchen wir fuer den Cross-Helper-Walk.
        Methods := ClassNode.FindAll(nkMethod);
        try
          for M in Methods do
          begin
            LowName := LowerCase(M.Name);
            if not MethodByName.ContainsKey(LowName) then
              MethodByName.Add(LowName, M);
            if IsVirtualLike(M) and not VirtualByName.ContainsKey(LowName) then
              VirtualByName.Add(LowName, M);
          end;
        finally
          Methods.Free;
        end;
        if VirtualByName.Count = 0 then Continue;

        // ABER: MethodByName muss auch die Top-Level-Impls enthalten
        // (Methods werden im Klassen-Subtree gefunden - meist nur Headers).
        // Wir nehmen Top-Level-nkMethod und matchen via "<Klasse>.<Name>"-Prefix.
        CtorList := UnitNode.FindAll(nkMethod);
        try
          for M in CtorList do
            if LowerCase(M.Name).StartsWith(LowerCase(ClassNode.Name) + '.') then
            begin
              var DotPos := LastDelimiter('.', M.Name);
              LowName := LowerCase(Copy(M.Name, DotPos + 1, MaxInt));
              // Overwrite OK - wir wollen das Impl (mit Body) statt der
              // Klassen-Subtree-Header-Node.
              MethodByName.AddOrSetValue(LowName, M);
            end;
        finally
          CtorList.Free;
        end;

        // Constructor-Impls finden.
        ClassImplCtors := TList<TAstNode>.Create;
        try
          CtorList := UnitNode.FindAll(nkMethod);
          try
            for Ctor in CtorList do
              if IsConstructor(Ctor) and
                 LowerCase(Ctor.Name).StartsWith(LowerCase(ClassNode.Name) + '.') then
                ClassImplCtors.Add(Ctor);
          finally
            CtorList.Free;
          end;

          AlreadyReported := TList<string>.Create;
          try
            for Ctor in ClassImplCtors do
            begin
              var CtorSimpleLow := LowerCase(Ctor.Name);
              var CtorDotPos := LastDelimiter('.', CtorSimpleLow);
              if CtorDotPos > 0 then
                CtorSimpleLow := Copy(CtorSimpleLow, CtorDotPos + 1, MaxInt);

              CallList := Ctor.FindAll(nkCall);
              try
                for Call in CallList do
                begin
                  Target := ExtractCallTarget(Call.Name);
                  if Target = '' then Continue;
                  LowName := LowerCase(Target);
                  if LowName.StartsWith('inherited') then Continue;
                  if LowName = CtorSimpleLow then Continue;

                  // Direkt-Hit (alter Pfad)
                  if VirtualByName.TryGetValue(LowName, VMethod) then
                  begin
                    RepKey := Ctor.Name + '|' + LowName + '|' +
                              IntToStr(Call.Line);
                    if AlreadyReported.IndexOf(RepKey) >= 0 then Continue;
                    AlreadyReported.Add(RepKey);
                    Results.Add(TLeakFinding.New(FileName, Ctor.Name, Call.Line,
                      Format('Virtual method "%s" called from constructor "%s" ' +
                             '- override runs on half-initialized Self',
                        [VMethod.Name, Ctor.Name]),
                      fkVirtualCallInCtor));
                    Continue;
                  end;

                  // Cross-Helper-Hit: non-virtual Call, aber in dieser Klasse.
                  // Folge der Kette bis virtual oder Depth/Cycle-Limit.
                  if not MethodByName.ContainsKey(LowName) then Continue;
                  Visited := TList<string>.Create;
                  Chain   := TList<string>.Create;
                  try
                    Chain.Add(LowName);   // Erster Helper im Chain
                    VMethod := FindVirtualInChain(LowName, MethodByName,
                      VirtualByName, Visited, Chain, 1);
                    if not Assigned(VMethod) then Continue;

                    RepKey := Ctor.Name + '|' + LowerCase(VMethod.Name) + '|' +
                              IntToStr(Call.Line);
                    if AlreadyReported.IndexOf(RepKey) >= 0 then Continue;
                    AlreadyReported.Add(RepKey);

                    Msg := Format('Virtual method "%s" reachable from ' +
                                  'constructor "%s" via helper chain: %s',
                      [VMethod.Name, Ctor.Name, string.Join(' -> ', Chain.ToArray)]);
                    Results.Add(TLeakFinding.New(FileName, Ctor.Name, Call.Line,
                      Msg, fkVirtualCallInCtor));
                  finally
                    Visited.Free;
                    Chain.Free;
                  end;
                end;
              finally
                CallList.Free;
              end;
            end;
          finally
            AlreadyReported.Free;
          end;
        finally
          ClassImplCtors.Free;
        end;
      finally
        VirtualByName.Free;
        MethodByName.Free;
      end;
    end;
  finally
    Classes.Free;
  end;
end;

end.

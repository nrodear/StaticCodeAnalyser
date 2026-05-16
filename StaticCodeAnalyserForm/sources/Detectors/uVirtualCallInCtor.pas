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

class procedure TVirtualCallInCtorDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Classes         : TList<TAstNode>;
  ClassNode       : TAstNode;
  VirtualByName   : TDictionary<string, TAstNode>;
  Methods         : TList<TAstNode>;
  M, Ctor, Call   : TAstNode;
  CtorList        : TList<TAstNode>;
  CallList        : TList<TAstNode>;
  Target, LowName : string;
  VMethod         : TAstNode;
  F               : TLeakFinding;
  AlreadyReported : TList<string>;
  RepKey          : string;
  ClassImplCtors  : TList<TAstNode>;
begin
  // 1. Klassen sammeln (interface-Section). Konstruktor-Implementierungen
  //    leben aber als Top-Level nkMethod ausserhalb der Klasse. Wir
  //    matchen Constructor-Impls an ihre Klasse via Name-Praefix
  //    `TBase.Create`.

  Classes := UnitNode.FindAll(nkClass);
  try
    for ClassNode in Classes do
    begin
      VirtualByName := TDictionary<string, TAstNode>.Create;
      try
        // Alle virtuellen Methoden dieser Klasse einsammeln
        Methods := ClassNode.FindAll(nkMethod);
        try
          for M in Methods do
            if IsVirtualLike(M) then
            begin
              LowName := LowerCase(M.Name);
              if not VirtualByName.ContainsKey(LowName) then
                VirtualByName.Add(LowName, M);
            end;
        finally
          Methods.Free;
        end;
        if VirtualByName.Count = 0 then Continue;

        // Constructor-Impls finden: Top-Level nkMethod mit Name
        // `<ClassName>.<MethName>` und TypeRef startsWith 'constructor'.
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

          // Pro Constructor alle nkCall durchsuchen
          AlreadyReported := TList<string>.Create;
          try
            for Ctor in ClassImplCtors do
            begin
              CallList := Ctor.FindAll(nkCall);
              try
                for Call in CallList do
                begin
                  Target := ExtractCallTarget(Call.Name);
                  if Target = '' then Continue;
                  LowName := LowerCase(Target);
                  // inherited skippen (geht hoch, nicht runter)
                  if LowName.StartsWith('inherited') then Continue;

                  if not VirtualByName.TryGetValue(LowName, VMethod) then
                    Continue;

                  RepKey := Ctor.Name + '|' + LowName + '|' + IntToStr(Call.Line);
                  if AlreadyReported.IndexOf(RepKey) >= 0 then Continue;
                  AlreadyReported.Add(RepKey);

                  F            := TLeakFinding.Create;
                  F.FileName   := FileName;
                  F.MethodName := Ctor.Name;
                  F.LineNumber := IntToStr(Call.Line);
                  F.MissingVar := Format(
                    'Virtual method "%s" called from constructor "%s" - '
                    + 'override runs on half-initialized Self',
                    [VMethod.Name, Ctor.Name]);
                  F.SetKind(fkVirtualCallInCtor);
                  Results.Add(F);
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
      end;
    end;
  finally
    Classes.Free;
  end;
end;

end.

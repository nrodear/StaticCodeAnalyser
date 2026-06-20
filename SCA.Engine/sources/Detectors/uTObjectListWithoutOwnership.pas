unit uTObjectListWithoutOwnership;

// Detektor: TList<TObj>.Create + Add(TObj.Create) ohne TObjectList<>.
//
// Pattern (Memory-Leak):
//   L := TList<TFoo>.Create;
//   L.Add(TFoo.Create);
//   L.Free;            // TFoo-Instances LEAKEN - TList besitzt sie nicht
//
// Korrekt:
//   L := TObjectList<TFoo>.Create;   // OwnsObjects=True default
//   L.Add(TFoo.Create);
//   L.Free;                          // Items werden freigegeben
//
// Erkennung (AST + Text-Heuristik):
//   * Pass 1: nkAssign mit TypeRef der `TList<T>.Create` Pattern
//     enthaelt (genericized List, NICHT TObjectList).
//     Sammle: Var-Name -> Generic-Type-Argument.
//   * Pass 2: nkCall oder nkAssign deren Name/TypeRef
//     `<varname>.Add(T.Create)` enthaelt (gleicher T wie in Pass 1).
//     Auch `<varname>.Add(T.Construct)` etc.
//
// FP-Tradeoff:
//   * Wenn der Generic-Type-Arg KEIN Klassen-Typ ist (z.B. `TList<Integer>`,
//     `TList<TFoo>`-Record), wuerden wir flaggen wenn Add(T.Create) -
//     aber Integer.Create gibt's nicht, also wuerde Pass 2 nicht matchen.
//     Records koennen technisch eine Create-Methode haben, dann FP.
//   * `MyList := TList<TFoo>.Create; MyList.Free` ohne Add ist OK
//     (kein Leak). Pass 2 entscheidet.
//   * Cross-Method-Add (Add in einer anderen Methode als Create) wird
//     nicht erkannt - per-Method-Scope. Akzeptabler FN.
//
// Severity: lsWarning, Type: ftBug.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TTObjectListWithoutOwnershipDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.RegularExpressions;

const
  // `TList<T>.Create` aber NICHT `TObjectList<T>.Create`. Negative
  // Look-Behind (?<!): kein 'Object' direkt vor 'List'.
  TLIST_CREATE_RE = '(?<!Object)\bTList<\s*([A-Za-z_]\w*)\s*>\s*\.\s*Create';
  // `<VarName>.Add(<TypeName>.Create` - VarName aus Pass-1, TypeName muss
  // gleichen Generic-Arg matchen.
  ADD_CREATE_TMPL = '\b%s\s*\.\s*Add\s*\(\s*%s\s*\.\s*Create';

class procedure TTObjectListWithoutOwnershipDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  Assigns : TList<TAstNode>;
  Calls   : TList<TAstNode>;
  M, N    : TAstNode;
  Mtch    : TMatch;
  VarName : string;
  TypeArg : string;
  // Pro Method: Map<VarName, TypeArg>
  ListVars : TDictionary<string, string>;
  Pair     : TPair<string, string>;
  AddRE    : TRegEx;
  F        : TLeakFinding;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      ListVars := TDictionary<string, string>.Create;
      try
        // Pass 1: TList<T>.Create-Patterns sammeln.
        Assigns := M.FindAll(nkAssign);
        try
          for N in Assigns do
          begin
            Mtch := TRegEx.Match(N.TypeRef, TLIST_CREATE_RE);
            if not Mtch.Success then Continue;
            VarName := N.Name;
            TypeArg := Mtch.Groups[1].Value;
            // Qualifier-Strip auf LHS (Self.List -> List).
            var DotPos := LastDelimiter('.', VarName);
            if DotPos > 0 then VarName := Copy(VarName, DotPos + 1, MaxInt);
            ListVars.AddOrSetValue(LowerCase(VarName), TypeArg);
          end;
        finally
          Assigns.Free;
        end;
        if ListVars.Count = 0 then Continue;

        // Pass 2: Add(T.Create)-Patterns matchen.
        Calls := M.FindAll(nkCall);
        try
          for Pair in ListVars do
          begin
            AddRE := TRegEx.Create(Format(ADD_CREATE_TMPL,
              [Pair.Key, Pair.Value]), [roIgnoreCase]);
            for N in Calls do
              if AddRE.IsMatch(N.Name) then
              begin
                F            := TLeakFinding.Create;
                F.FileName   := FileName;
                F.MethodName := M.Name;
                F.LineNumber := IntToStr(N.Line);
                F.MissingVar := 'TList<' + Pair.Value + '> "' + Pair.Key +
                                '" gets a new ' + Pair.Value + '.Create - ' +
                                'instances will leak when the list is freed. ' +
                                'Use TObjectList<' + Pair.Value + '> instead ' +
                                '(OwnsObjects=True is the default).';
                F.SetKind(fkTObjectListWithoutOwnership);
                Results.Add(F);
              end;
          end;
        finally
          Calls.Free;
        end;
      finally
        ListVars.Free;
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.

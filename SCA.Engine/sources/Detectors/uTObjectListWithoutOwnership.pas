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
//     enthaelt (genericized List, NICHT TObjectList). Nur Klassen-Listen
//     (Generic-Arg 'T...'): Interface-/Werttyp-Listen leaken nicht.
//     Sammle: Var-Name -> Generic-Type-Argument.
//   * Pass 2: nkCall deren Name `<varname>.Add(<Klasse>.Create)` enthaelt.
//     Der hinzugefuegte Typ darf eine SUBKLASSE des Generic-Args sein
//     (`TList<TAnimal>` + `Add(TDog.Create)`) - leakt genauso.
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
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TTObjectListWithoutOwnershipDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

uses
  System.RegularExpressions,
  uTypeIndex;

const
  // `TList<T>.Create` aber NICHT `TObjectList<T>.Create`. Negative
  // Look-Behind (?<!): kein 'Object' direkt vor 'List'. `TList\s*<`
  // toleriert Whitespace zwischen Name und Generic-Bracket.
  TLIST_CREATE_RE = '(?<!Object)\bTList\s*<\s*([A-Za-z_]\w*)\s*>\s*\.\s*Create';
  // `<VarName>.Add(<ClassName>.Create` - VarName aus Pass-1. Der
  // hinzugefuegte Typ muss NICHT exakt dem Generic-Arg entsprechen:
  // `TList<TAnimal>` + `Add(TDog.Create)` (Subklasse) leakt genauso.
  // Daher matchen wir JEDE Klassen-`.Create` (Capture-Group fuer Message).
  ADD_CREATE_TMPL = '\b%s\s*\.\s*Add\s*\(\s*([A-Za-z_]\w*)\s*\.\s*Create';

class procedure TTObjectListWithoutOwnershipDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
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
            // Nur Klassen-Listen tracken: Generic-Arg muss der Klassen-
            // Konvention 'T...' folgen. Schliesst Interface-Listen
            // (`TList<IFoo>` - ref-counted, kein Leak) und Werttyp-Listen
            // (`TList<Integer>`/`<string>`) aus -> kein FP.
            if (TypeArg = '') or not CharInSet(TypeArg[1], ['T', 't']) then
              Continue;
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
            // ADD_CREATE_TMPL hat nur EINEN %s (VarName); der hinzugefuegte
            // Typ wird als Capture-Group 1 erfasst.
            AddRE := TRegEx.Create(Format(ADD_CREATE_TMPL,
              [Pair.Key]), [roIgnoreCase]);
            for N in Calls do
            begin
              Mtch := AddRE.Match(N.Name);
              if not Mtch.Success then Continue;
              var AddedType := Mtch.Groups[1].Value;

              // Track C Opt-in (Konzept_StrukturellePhase, Runde 3): Cross-Unit-
              // Typ-Index-Gegenprobe. Ist der hinzugefuegte Typ ein WERTTYP-
              // RECORD (TRegEx/TNameValuePair/TSizeF/... , Seed oder in-source
              // 'record'-Deklaration), dann ist `T.Create` KEINE Heap-Allokation
              // -> das Item leakt nicht, wenn die Liste freigegeben wird, und der
              // TObjectList-Rat waere falsch. NUR bei beweisbar tkiRecord
              // unterdruecken; nil/leerer Index (Tests/Single-File, AContext=nil),
              // unbekannter Typ oder Klasse -> Fund bleibt (bisheriges Verhalten,
              // TP-safe). tkiRecord ist ein DIREKTER Fakt (record -> nkRecord bzw.
              // Seed), keine Ketten-Ambiguitaet wie bei Vererbung -> kein FN-Risiko.
              var Idx := CtxTypeIndex(AContext);
              if (Idx <> nil) and (not Idx.IsEmpty) and
                 (Idx.TypeKindOf(LowerCase(AddedType)) = tkiRecord) then
                Continue;

              F            := TLeakFinding.Create;
              F.FileName   := FileName;
              F.MethodName := M.Name;
              F.LineNumber := IntToStr(N.Line);
              F.MissingVar := 'TList<' + Pair.Value + '> "' + Pair.Key +
                              '" gets a new ' + AddedType + '.Create - ' +
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

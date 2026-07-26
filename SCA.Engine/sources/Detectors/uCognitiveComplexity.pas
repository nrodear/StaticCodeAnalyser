unit uCognitiveComplexity;

// Detektor: Sonar-Cognitive-Complexity pro Methode.
//
// McCabe-Cyclomatic-Complexity (SCA022) zaehlt unabhaengige Pfade
// linear - 10 separate if-Statements werden gleich gewichtet wie
// ein dreifach verschachteltes if. Cognitive-Complexity (von Sonar
// 2017 eingefuehrt) gewichtet verschachtelte Logik schwerer, weil
// sie mental schwieriger zu folgen ist.
//
// Formel (vereinfacht, Sonar-Kompatibel):
//   B1: +1 pro Kontrollfluss-Konstrukt (if, while, for, repeat, case,
//       on-handler) - linear-Erkennung.
//   B2: +N pro Verschachtelung, wo N = aktuelle Tiefe ueber Method-Root.
//       Z.B. ein if INNERHALB eines for INNERHALB eines while:
//         while ... do         (+1, depth=0)
//           for ... do         (+1+1 = +2, depth=1)
//             if ... then      (+1+2 = +3, depth=2)
//       Cyclomatic waere: +1+1+1 = 3. Cognitive: +1+2+3 = 6.
//       AUSNAHME 'else if' (Sonar: "else if" ist +1 OHNE Nesting-
//       Zuschlag): der Parser haengt den else-Zweig als nkElseBranch
//       UNTER das nkIfStmt (uParser2.ParseIfStmt), ein 'else if' liegt
//       also strukturell eine Ebene tiefer als die Kette semantisch ist.
//       Ohne Korrektur kostete eine FLACHE else-if-Kette der Laenge N
//       nicht N sondern N*(N+1)/2 (uUnusedUses.pas:139 mit 121 else-if:
//       Score 7575 statt 121) - eine reine Metrik-Verfaelschung. Siehe
//       CountInMethod: direkte nkIfStmt-Kinder eines nkElseBranch erben
//       die Tiefe des UMGEBENDEN if, nicht die erhoehte.
//   B3: +1 pro boolean-Operator-Sequenz (and/or/xor) in if-Bedingung.
//
// Schwellwert: DetectorMaxCognitive (Default 15 - Sonar-Industry-
// Standard). > 15 bedeutet "schwer mental zu folgen".
//
// Implementierung: iterative DFS analog SCA022 (Stack-Overflow-Schutz
// bei tief verschachtelten Files - siehe Audit_jvcl_segfault.md).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

const
  // Default-Threshold; konfigurierbar via INI [Detectors] CognitiveLimit
  DEF_COGNITIVE_LIMIT = 15;

type
  TCognitiveComplexityDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    class function CountInMethod(MethodNode: TAstNode): Integer; static;
    class function CountBooleanOpsInCond(const CondText: string): Integer; static;
  end;

implementation

uses
  uRepoSettings;

function QuickReadIntDef(const ASection, AKey: string; ADefault: Integer): Integer;
var
  S : string;
begin
  S := TRepoSettings.QuickReadStr(ASection, AKey, IntToStr(ADefault));
  Result := StrToIntDef(S, ADefault);
end;

type
  TStackEntry = record
    Node  : TAstNode;
    Depth : Integer;     // Verschachtelungstiefe relativ zum Method-Root
  end;

class function TCognitiveComplexityDetector.CountBooleanOpsInCond(
  const CondText: string): Integer;
// Identische Logik wie uCyclomaticComplexity.CountBooleanOpsInCond -
// kopiert statt deren private function exportiert, um die Detektoren
// unabhaengig zu halten.
var
  Lo : string;
  i  : Integer;
  function IsWordChar(C: Char): Boolean;
  begin Result := CharInSet(C, ['a'..'z', 'A'..'Z', '0'..'9', '_']); end;
  function IsBoundaryAt(Pos: Integer): Boolean;
  begin
    Result := (Pos < 1) or (Pos > Length(Lo)) or (not IsWordChar(Lo[Pos]));
  end;
  function MatchAt(Pos: Integer; const W: string): Boolean;
  var j: Integer;
  begin
    if Pos + Length(W) - 1 > Length(Lo) then Exit(False);
    for j := 1 to Length(W) do
      if Lo[Pos + j - 1] <> W[j] then Exit(False);
    Result := IsBoundaryAt(Pos - 1) and IsBoundaryAt(Pos + Length(W));
  end;
begin
  Result := 0;
  Lo := LowerCase(CondText);
  i  := 1;
  while i <= Length(Lo) do
  begin
    case Lo[i] of
      'a': if MatchAt(i, 'and') then begin Inc(Result); Inc(i, 3); Continue; end;
      'o': if MatchAt(i, 'or')  then begin Inc(Result); Inc(i, 2); Continue; end;
      'x': if MatchAt(i, 'xor') then begin Inc(Result); Inc(i, 3); Continue; end;
    end;
    Inc(i);
  end;
end;

class function TCognitiveComplexityDetector.CountInMethod(
  MethodNode: TAstNode): Integer;
var
  Stack : TList<TStackEntry>;
  Entry, Child : TStackEntry;
  i     : Integer;
  ChildDepth : Integer;
  ElseIfDepth : Integer;   // Tiefe fuer ein direktes nkIfStmt-Kind (else if)
  IsControlFlow : Boolean;
begin
  Result := 0;
  if MethodNode = nil then Exit;
  Stack := TList<TStackEntry>.Create;
  try
    // Push children of MethodNode with Depth=0 (Method-Root selbst zaehlt nicht).
    for i := MethodNode.Children.Count - 1 downto 0 do
    begin
      Entry.Node  := MethodNode.Children[i];
      Entry.Depth := 0;
      Stack.Add(Entry);
    end;

    while Stack.Count > 0 do
    begin
      Entry := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);

      IsControlFlow := False;
      case Entry.Node.Kind of
        nkIfStmt:
          begin
            // B1 + B2: 1 + current-Depth (Sonar-Formel)
            Inc(Result, 1 + Entry.Depth);
            // B3: boolean-Operatoren in if-Condition (and/or/xor)
            Inc(Result, CountBooleanOpsInCond(Entry.Node.TypeRef));
            IsControlFlow := True;
          end;
        nkForStmt, nkWhileStmt, nkRepeatStmt,
        nkCaseStmt, nkOnHandler:
          begin
            Inc(Result, 1 + Entry.Depth);
            IsControlFlow := True;
          end;
      end;

      // Verschachtelung: wenn Control-Flow, Depth+1 fuer Children.
      if IsControlFlow then ChildDepth := Entry.Depth + 1
      else                  ChildDepth := Entry.Depth;

      // 'else if'-Korrektur (2026-07-26): nkElseBranch haengt UNTER dem
      // nkIfStmt und traegt dessen bereits erhoehte Tiefe. Ein DIREKT
      // darin liegendes nkIfStmt ist aber kein verschachteltes if,
      // sondern das naechste Glied einer flachen else-if-Kette und
      // bekommt nach Sonar +1 OHNE Nesting-Zuschlag. Es erbt daher die
      // Tiefe des umgebenden if (ChildDepth-1), womit jedes Kettenglied
      // denselben Level wie das erste if bekommt -> Kosten N statt
      // N*(N+1)/2. Bewusst NUR fuer das direkte Kind: ein 'else begin
      // if ... end' liegt unter einem nkBlock, behaelt also seinen
      // Nesting-Zuschlag (Sonar-konform). Der Eingriff kann Scores
      // ausschliesslich SENKEN - nichts wird neu gezaehlt.
      ElseIfDepth := ChildDepth;
      if (Entry.Node.Kind = nkElseBranch) and (ChildDepth > 0) then
        ElseIfDepth := ChildDepth - 1;

      for i := Entry.Node.Children.Count - 1 downto 0 do
      begin
        Child.Node  := Entry.Node.Children[i];
        if Child.Node.Kind = nkIfStmt then Child.Depth := ElseIfDepth
        else                               Child.Depth := ChildDepth;
        Stack.Add(Child);
      end;
    end;
  finally
    Stack.Free;
  end;
end;

class procedure TCognitiveComplexityDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
  CC      : Integer;
  Limit   : Integer;
  F       : TLeakFinding;
begin
  Limit := QuickReadIntDef('Detectors', 'CognitiveLimit', DEF_COGNITIVE_LIMIT);
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      CC := CountInMethod(M);
      if CC <= Limit then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := M.Name;
      F.LineNumber := IntToStr(M.Line);
      F.MissingVar := Format(
        'Cognitive complexity %d (limit: %d) - nested control flow ' +
        'is hard to follow. Refactor by extracting helper methods or ' +
        'inverting guard conditions.',
        [CC, Limit]);
      F.SetKind(fkCognitiveComplexity);
      Results.Add(F);
    end;
  finally
    Methods.Free;
  end;
end;

end.

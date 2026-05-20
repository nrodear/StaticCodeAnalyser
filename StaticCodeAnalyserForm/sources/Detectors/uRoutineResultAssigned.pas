unit uRoutineResultAssigned;

// Detektor: Function-Body endet ohne dass `Result` (oder der Function-Name)
// jemals geschrieben wurde.
//
// Pattern (Bug):
//   function Compute(x: Integer): Integer;
//   begin
//     if x > 0 then
//       LogMessage('positive');
//     // <-- Result nie gesetzt -> undefined Return-Value
//   end;
//
// Korrekt:
//   function Compute(x: Integer): Integer;
//   begin
//     Result := 0;
//     if x > 0 then
//     begin
//       Result := x * 2;
//       LogMessage('positive');
//     end;
//   end;
//
// Folge: In Release-Builds liefert die Funktion den Wert des
// stack/register-Garbages oder den Wert des letzten gleichgrossen
// Calls - klassischer "manchmal funktioniert es"-Heisenbug.
//
// Erkennung (konservativ, keine Path-Sensitivity):
//   * Nur Functions: MNode.TypeRef enthaelt ':' (= Return-Type vorhanden).
//   * Skip wenn Body abstract/forward/external/virtual+abstract (kein Body).
//   * Skip wenn IRGENDWO im Body:
//       - nkExit  - koennte Exit(value) sein (Argument vom Parser verworfen).
//       - nkRaise - Method wirft, kein Return-Pfad noetig.
//       - nkAssign mit LHS = 'result' (case-insensitive) - hier kommt
//         die Result-Zuweisung.
//       - nkAssign mit LHS = <FunctionName> (case-insensitive) - klassischer
//         Pascal-Stil: `<func> := value`.
//   * Sonst -> Finding.
//
// Bewusst nicht analysiert:
//   * Partial Coverage (Result in einem then-Zweig, aber nicht im else)
//     -> bewusst False-Negative bis CFG-Analyse implementiert ist.
//
// Sonar-Pendant: RoutineResultAssignedCheck
// https://github.com/integrated-application-development/sonar-delphi/blob/
//   master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/
//   RoutineResultAssignedCheck.java

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TRoutineResultAssignedDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// Liefert True wenn TypeRef einen Return-Type enthaelt (Format
// 'function:RetType[;direktive...]'). Procedures haben keinen ':' im
// Kind-Teil. Robust gegen Direktiven-Suffix.
function IsFunctionMethod(const TypeRef: string): Boolean;
var
  ColonPos, SemiPos : Integer;
begin
  ColonPos := Pos(':', TypeRef);
  if ColonPos = 0 then Exit(False);
  SemiPos := Pos(';', TypeRef);
  // ':' muss VOR dem ersten ';'-Direktiv-Trenner kommen, sonst koennte
  // ein generisches 'procedure;virtual:abstract' (theoretisch) falsch
  // matchen. In der Praxis kommt das nicht vor, defensiv trotzdem.
  Result := (SemiPos = 0) or (ColonPos < SemiPos);
end;

// True wenn TypeRef einen der Body-losen Direktiven-Marker enthaelt.
function IsBodyless(const TypeRef: string): Boolean;
var
  Low : string;
begin
  Low := LowerCase(TypeRef);
  Result := (Pos(';abstract',  Low) > 0) or
            (Pos(';forward',   Low) > 0) or
            (Pos(';external',  Low) > 0) or
            (Pos(';dispid',    Low) > 0);
end;

// Letztes Segment eines qualifizierten Methodennamens.
// 'TFoo.Bar' -> 'Bar'; 'Bar' -> 'Bar'; 'TFoo<T>.Bar' -> 'Bar'.
function UnqualifiedName(const MethName: string): string;
var
  i : Integer;
begin
  Result := MethName;
  for i := Length(MethName) downto 1 do
    if MethName[i] = '.' then
    begin
      Result := Copy(MethName, i + 1, MaxInt);
      Exit;
    end;
end;

// Normalisiert eine LHS-String fuer Vergleich: lowercase, Whitespace raus.
function NormalizeLhs(const S: string): string;
var
  i : Integer;
  C : Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    C := S[i];
    if C > ' ' then
      Result := Result + LowerCase(C);
  end;
end;

class procedure TRoutineResultAssignedDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  TypeRef    : string;
  FnNameLow  : string;
  Exits      : TList<TAstNode>;
  Raises     : TList<TAstNode>;
  Assigns    : TList<TAstNode>;
  N          : TAstNode;
  LhsLow     : string;
  HasResult  : Boolean;
  F          : TLeakFinding;
begin
  TypeRef := MethodNode.TypeRef;
  if not IsFunctionMethod(TypeRef) then Exit;     // procedure -> skip
  if IsBodyless(TypeRef) then Exit;               // abstract/forward/external

  // Body-Inhalt: jedes Exit oder Raise reicht als Skip-Grund.
  Exits := MethodNode.FindAll(nkExit);
  try
    if Exits.Count > 0 then Exit;
  finally
    Exits.Free;
  end;

  Raises := MethodNode.FindAll(nkRaise);
  try
    if Raises.Count > 0 then Exit;
  finally
    Raises.Free;
  end;

  // Pruefe alle nkAssign auf LHS = 'result' oder <FunctionName>.
  FnNameLow := LowerCase(UnqualifiedName(MethodNode.Name));
  HasResult := False;

  Assigns := MethodNode.FindAll(nkAssign);
  try
    for N in Assigns do
    begin
      LhsLow := NormalizeLhs(N.Name);
      if (LhsLow = 'result') or (LhsLow = FnNameLow) then
      begin
        HasResult := True;
        Break;
      end;
    end;
  finally
    Assigns.Free;
  end;

  if HasResult then Exit;

  F            := TLeakFinding.Create;
  F.FileName   := FileName;
  F.MethodName := MethodNode.Name;
  F.LineNumber := IntToStr(MethodNode.Line);
  F.MissingVar := Format(
    'Function %s never assigns Result (return value undefined)',
    [UnqualifiedName(MethodNode.Name)]);
  F.SetKind(fkRoutineResultUnassigned);
  Results.Add(F);
end;

class procedure TRoutineResultAssignedDetector.AnalyzeUnit(UnitNode: TAstNode;
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

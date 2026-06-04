unit uUnsortedUses;

// Detektor: uses-Klausel-Eintraege NICHT alphabetisch sortiert.
//
// Pattern (Code Smell, Sonar-50 #47):
//   uses
//     System.Classes,
//     System.SysUtils,
//     System.IOUtils,                  // <-- nicht alphabetisch
//     System.JSON;
//
// Korrekt:
//   uses
//     System.Classes,
//     System.IOUtils,
//     System.JSON,
//     System.SysUtils;
//
// Erkennung (AST):
//   * Walk nkUses-Knoten.
//   * Sammle alle nkUsesItem-Children.
//   * Vergleiche mit case-insensitive sortierter Variante.
//   * Bei Differenz: einen Finding pro nkUses (nicht pro Item).
//
// Schweregrad: lsHint - viele Projekte gruppieren uses thematisch
// (interface vs implementation, RTL/VCL/Custom). Empfehlung, kein
// Pflicht-Lint.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TUnsortedUsesDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.Generics.Defaults;

class procedure TUnsortedUsesDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  UsesNodes : TList<TAstNode>;
  U         : TAstNode;
  Names, Sorted : TArray<string>;
  i         : Integer;
  Unsorted  : Boolean;
  F         : TLeakFinding;
begin
  UsesNodes := UnitNode.FindAll(nkUses);
  try
    for U in UsesNodes do
    begin
      if U.Children.Count < 2 then Continue;
      SetLength(Names, U.Children.Count);
      for i := 0 to U.Children.Count - 1 do
        Names[i] := U.Children[i].Name;
      Sorted := Copy(Names);
      TArray.Sort<string>(Sorted, TComparer<string>.Construct(
        function(const A, B: string): Integer
        begin
          Result := CompareText(A, B);
        end));
      Unsorted := False;
      for i := 0 to High(Names) do
        if not SameText(Names[i], Sorted[i]) then
        begin
          Unsorted := True;
          Break;
        end;
      if not Unsorted then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(U.Line);
      F.MissingVar := 'uses clause is not in alphabetical order';
      F.SetKind(fkUnsortedUses);
      Results.Add(F);
    end;
  finally
    UsesNodes.Free;
  end;
end;

end.

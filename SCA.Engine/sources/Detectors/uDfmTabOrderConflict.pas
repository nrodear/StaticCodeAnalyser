unit uDfmTabOrderConflict;

// Detektor: Zwei oder mehr Geschwister-Komponenten im selben Parent haben
// den gleichen TabOrder-Wert.
//
// Die VCL bestimmt bei gleicher TabOrder die Reihenfolge undefiniert
// (intern wird die Erzeugungs-Reihenfolge benutzt - das ist nach
// Refactoring oft anders als die Layout-Reihenfolge im Designer). Ergebnis:
// Tab springt nicht so wie der User es erwartet.
//
// Erkennung: pro Parent eine Hash-Map TabOrder -> List<Comp>. Wenn eine
// Liste >= 2 Komponenten hat, alle beteiligten Komponenten melden.
//
// Schweregrad: lsHint, FindingType: ftCodeSmell.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uComponentGraph;

type
  TDfmTabOrderConflictDetector = class
  public
    class procedure Analyze(Graph: TComponentGraph; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

procedure CheckParent(Parent: TComponentNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Buckets : TObjectDictionary<string, TList<TComponentNode>>;
  Child   : TComponentNode;
  V       : TPropValue;
  Key     : string;
  List    : TList<TComponentNode>;
  I       : Integer;
  F       : TLeakFinding;
  Pair    : TPair<string, TList<TComponentNode>>;
begin
  Buckets := TObjectDictionary<string, TList<TComponentNode>>.Create([doOwnsValues]);
  try
    for I := 0 to Parent.Children.Count - 1 do
    begin
      Child := Parent.Children[I];
      if not Child.TryGetProperty('TabOrder', V) then Continue;
      if V.Kind <> pvkInteger then Continue;

      Key := Trim(V.RawValue);
      if not Buckets.TryGetValue(Key, List) then
      begin
        List := TList<TComponentNode>.Create;
        Buckets.Add(Key, List);
      end;
      List.Add(Child);
    end;

    for Pair in Buckets do
      if Pair.Value.Count >= 2 then
        for Child in Pair.Value do
        begin
          F            := TLeakFinding.Create;
          F.FileName   := FileName;
          F.MethodName := '';
          F.LineNumber := IntToStr(Child.Line);
          F.MissingVar := Format('%s shares TabOrder=%s with sibling(s) in %s',
                                  [Child.Name, Pair.Key, Parent.Name]);
          F.SetKind(fkDfmTabOrderConflict);
          Results.Add(F);
        end;
  finally
    Buckets.Free;
  end;
end;

class procedure TDfmTabOrderConflictDetector.Analyze(Graph: TComponentGraph;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  All : TList<TComponentNode>;
  N   : TComponentNode;
begin
  if Graph = nil then Exit;
  All := Graph.EnumerateAll;
  try
    for N in All do
      if N.Children.Count >= 2 then
        CheckParent(N, FileName, Results);
  finally
    All.Free;
  end;
end;

end.

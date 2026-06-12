unit uCollectValues;

interface

uses
  System.SysUtils, Classes, System.Generics.Collections;

type

  TCollectValues = record
    class procedure Aggregate(const Input: TStringList;
      var NameCounts: TDictionary<string, Integer>); static;
  end;

implementation

// noinspection-file ConsecutiveSection, GroupedDeclaration, MissingUnitHeader, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

class procedure TCollectValues.Aggregate(const Input: TStringList;
  var NameCounts: TDictionary<string, Integer>);
var
  nameList: TArray<string>;
  name, line: string;
  nameTrimed: string;
begin
  for line in Input do
  begin
    nameList := line.Split([',']);
    for name in nameList do
    begin
      nameTrimed := Trim(name).TrimRight([';', ' ']);
      if nameTrimed <> '' then
      begin
        if NameCounts.ContainsKey(nameTrimed) then
          NameCounts[nameTrimed] := NameCounts[nameTrimed] + 1
        else
          NameCounts.Add(nameTrimed, 1);
      end;
    end;
  end;
end;

end.

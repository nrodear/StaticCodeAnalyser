unit uMultipleExit;

// Detektor: Methode mit zu vielen Exit-Statements (> 6).
//
// Pattern (Code Smell, Sonar-50 #34): eine Vielzahl von Exit-Punkten macht den
// Kontrollfluss schwer lesbar und schwer zu testen. Refactoring: Guards
// zusammenfassen, einen einzigen Return-Pfad anstreben.
//
// Schwelle 2026-07-11 von 3 auf 6 angehoben (Real-World-Korpus D:\git-sca-
// realworld): fruehe Guard-Clauses ('if not Valid then Exit') sind idiomatisches,
// gutes Delphi - Methoden mit 4-6 Exits sind fast durchweg reine Guard-Ketten,
// kein Smell (40% aller alten Funde hatten GENAU 4 Exits). Erst ab 7+ Exits
// deutet es auf wirklich verwobenen Kontrollfluss. -73% Noise ohne die genuin
// exit-lastigen Methoden zu verlieren.
//
// Erkennung (AST):
//   * Pro Methode: zaehle nkExit-Descendants (nested/anon-Methoden bekommen
//     eigene nkMethod-Knoten -> keine Doppelzaehlung, verifiziert).
//   * Threshold: > MAX_EXITS.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TMultipleExitDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file CanBeClassMethod, ConsecutiveSection, NestedTry, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  MAX_EXITS = 6;

class procedure TMultipleExitDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
  Exits   : TList<TAstNode>;
  F       : TLeakFinding;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      Exits := M.FindAll(nkExit);
      try
        if Exits.Count <= MAX_EXITS then Continue;
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := M.Name;
        F.LineNumber := IntToStr(M.Line);
        F.MissingVar := Format(
          'Method %s has %d Exit statements (threshold %d) - consolidate guards / single return',
          [M.Name, Exits.Count, MAX_EXITS]);
        F.SetKind(fkMultipleExit);
        Results.Add(F);
      finally
        Exits.Free;
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.

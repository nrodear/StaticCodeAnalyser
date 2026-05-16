unit uTwiceInheritedCalls;

// Detektor fuer Methoden mit mehrfachem `inherited;` Aufruf.
//
// SonarDelphi-Aequivalent: communitydelphi:TwiceInheritedCalls. Mehrere
// `inherited`-Aufrufe in derselben Methode sind fast immer ein Bug:
// jeder Aufruf invoked die Parent-Implementierung ein weiteres Mal,
// was Side-Effekte verdoppelt (z.B. zweimal `OnChange` feuern).
//
// Erkennung: AST-basiert. Pro `nkMethod`-Knoten zaehle `nkInherited`-
// Vorkommen im Body-Block. Bei >= 2 wird auf der Methoden-Zeile gemeldet.
//
// Schweregrad: lsWarning.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TTwiceInheritedCallsDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

const
  EMIT_SEVERITY = lsWarning;

function CountInheritedInSubtree(Node: TAstNode): Integer;
var
  Child : TAstNode;
begin
  Result := 0;
  if Node = nil then Exit;
  if Node.Kind = nkInherited then Inc(Result);
  for Child in Node.Children do
    Inc(Result, CountInheritedInSubtree(Child));
end;

class procedure TTwiceInheritedCallsDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
  Count   : Integer;
  F       : TLeakFinding;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      Count := CountInheritedInSubtree(M);
      if Count < 2 then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := M.Name;
      F.LineNumber := IntToStr(M.Line);
      F.MissingVar := Format(
        '%d `inherited` calls in this method - usually a bug ' +
        '(parent side-effects run twice). Keep one call or extract ' +
        'helpers.', [Count]);
      F.SetKind(fkTwiceInheritedCalls);
      Results.Add(F);
    end;
  finally
    Methods.Free;
  end;
end;

end.

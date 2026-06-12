unit uMultipleExit;

// Detektor: Methode mit > 3 Exit-Statements.
//
// Pattern (Code Smell, Sonar-50 #34):
//   function FindUser(const Id: Integer): TUser;
//   begin
//     if Id < 0 then begin Result := nil; Exit; end;
//     if not DbConnected then begin Result := nil; Exit; end;
//     if not Cache.Contains(Id) then begin Result := DbLoad(Id); Exit; end;
//     Result := Cache.Get(Id);
//     Exit;                                        // <-- 4. Exit
//   end;
//
// Folge: Vielzahl von Exit-Punkten macht den Kontrollfluss schwer
// lesbar und schwer zu testen. Refactoring: Guards zusammenfassen,
// einen einzigen Return-Pfad anstreben.
//
// Erkennung (AST):
//   * Pro Methode: zaehle nkExit-Descendants.
//   * Threshold: > MAX_EXITS. Default 3.

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
  MAX_EXITS = 3;

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

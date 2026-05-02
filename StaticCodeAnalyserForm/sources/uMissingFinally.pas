unit uMissingFinally;

// Detektor fuer fehlenden try/finally-Schutz (Sonar-Regel #8).
//
// Erkennt lokale Variablen leaky Typen, bei denen:
//   - .Create aufgerufen wird
//   - .Free/.Destroy/FreeAndNil aufgerufen wird
//   - aber KEIN try/finally-Block in der Methode vorhanden ist
//
// Ohne try/finally kann eine Exception zwischen Create und Free
// zu einem Speicherleck fuehren.
//
// Beispiel (Befund):
//   list := TStringList.Create;
//   DoWork(list);          // wirft Exception
//   list.Free;             // wird nie erreicht → Leck
//
// Korrekt (kein Befund):
//   list := TStringList.Create;
//   try
//     DoWork(list);
//   finally
//     list.Free;
//   end;
//
// Hinweis: Variablen die als Ergebnis weitergegeben oder an einen
//          Owner-Konstruktor uebergeben werden, werden uebersprungen.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uLeakDetector2;

type
  TMissingFinallyDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

class procedure TMissingFinallyDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  LocalVars  : TList<TAstNode>;
  V          : TAstNode;
  VarNameLow : string;
  FreeFound  : Boolean;
  FreeInFin  : Boolean;
  HasFinally : Boolean;
  HasExcept  : Boolean;
  F          : TLeakFinding;
begin
  HasFinally := TLeakDetector2.HasTryFinallyBlock(MethodNode);
  HasExcept  := MethodNode.HasChild(nkTryExcept);

  // Hat die Methode bereits try/finally, deckt TLeakDetector2 den Fall
  // 'Free ausserhalb finally' bereits ab → hier nichts melden.
  if HasFinally then Exit;

  LocalVars := MethodNode.FindAll(nkLocalVar);
  try
    for V in LocalVars do
    begin
      if not TLeakDetector2.IsLeakyType(V.TypeRef) then Continue;

      VarNameLow := V.Name.ToLower;

      if not TLeakDetector2.HasCreateAssign(MethodNode, VarNameLow) then Continue;
      if TLeakDetector2.IsReturnedAsResult(MethodNode, VarNameLow) then Continue;
      if TLeakDetector2.IsPassedToOwner(MethodNode, VarNameLow)    then Continue;

      // Free muss vorhanden sein – sonst meldet TLeakDetector2 als lsError
      FreeFound := TLeakDetector2.SearchFree(MethodNode, VarNameLow,
                                             False, FreeInFin);
      if not FreeFound then Continue;

      // Create + Free vorhanden, aber kein try/finally
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := MethodNode.Name;
      F.LineNumber := IntToStr(V.Line);
      if HasExcept then
        F.MissingVar := V.Name + ' (try/except statt try/finally)'
      else
        F.MissingVar := V.Name;
      F.Severity   := lsWarning;
      F.Kind       := fkMissingFinally;
      Results.Add(F);
    end;
  finally
    LocalVars.Free;
  end;
end;

class procedure TMissingFinallyDetector.AnalyzeUnit(UnitNode: TAstNode;
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

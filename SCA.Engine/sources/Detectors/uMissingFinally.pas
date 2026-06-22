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

// noinspection-file BeginEndRequired, CanBeStrictPrivate, LongMethod, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

class procedure TMissingFinallyDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  LocalVars  : TList<TAstNode>;
  V          : TAstNode;
  VarNameLow : string;
  FreeFound  : Boolean;
  FreeInFin  : Boolean;
  HasExcept  : Boolean;
  HasReraise : Boolean;
  RaiseNodes : TList<TAstNode>;
  R          : TAstNode;
  F          : TLeakFinding;
begin
  HasExcept  := MethodNode.HasChild(nkTryExcept);

  // Re-raise-Cleanup-Idiom erkennen: `try Build; except Obj.Free; raise; end`
  // ist funktional aequivalent zu try/finally fuer den FEHLERpfad - der
  // ERFOLGSpfad behaelt/transferiert das Objekt bewusst (Owner-Transfer,
  // Cache-Store). Ein try/finally waere hier FALSCH (es wuerde das Objekt
  // auch bei Erfolg freigeben). Signal: ein bare `raise;` (nkRaise mit Name
  // 'raise') irgendwo in der Methode - das gibt es nur in einem except-
  // Handler. Real-World/Self-Scan FP-Klasse 2026-06-21.
  HasReraise := False;
  RaiseNodes := MethodNode.FindAll(nkRaise);
  try
    for R in RaiseNodes do
      if SameText(Trim(R.Name), 'raise') then begin HasReraise := True; Break; end;
  finally
    RaiseNodes.Free;
  end;

  // PER-VAR-Pruefung: Methode kann durchaus try/finally haben, aber
  // nicht jede leaky var ist auch IM finally freigegeben. Z.B.:
  //   lst := TStringList.Create;
  //   lst.Free;
  //   try DoStuff finally Cleanup; end;  // try/finally aber NICHT um lst
  // Hier soll MissingFinally feuern. Vorher: method-wide HasFinally->
  // Exit hat das verschluckt. Pro-var FreeInFin-Check erkennt es jetzt.
  // (Fuer den Fall "method hat NULL try/finally" wird HasExcept-Hinweis
  // nur dann beigegeben wenn mindestens try/except existiert.)

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
      // Free liegt bereits IM finally - alles gut, kein MissingFinally.
      if FreeInFin then Continue;
      // try/except MIT bare re-raise = Cleanup-und-Reraise-Idiom (s.o.) ->
      // funktional try/finally fuer den Fehlerpfad, kein MissingFinally.
      if HasExcept and HasReraise then Continue;

      // Create + Free vorhanden, aber kein try/finally.
      // Emit auf der Create-Zeile (statt var-decl): bessere UX und
      // // noinspection-Marker direkt ueber dem Create greifen jetzt.
      var ReportLine := TLeakDetector2.FindCreateLine(MethodNode, VarNameLow);
      if ReportLine = 0 then ReportLine := V.Line;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := MethodNode.Name;
      F.LineNumber := IntToStr(ReportLine);
      if HasExcept then
        F.MissingVar := V.Name + ' (try/except instead of try/finally)'
      else
        F.MissingVar := V.Name;
      F.SetKind(fkMissingFinally);
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

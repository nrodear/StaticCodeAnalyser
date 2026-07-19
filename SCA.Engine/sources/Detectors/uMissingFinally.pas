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
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uLeakDetector2, uAnalyzeContext,
  uDetectorUtils, uFileTextCache;

type
  TMissingFinallyDetector = class
  public
    // AContext (TD-1 2c): bis in TLeakDetector2.IsLeakyType durchgereicht, damit
    // MissingFinally dieselbe (Auto-Discovery-erweiterte) LeakyClasses-Liste
    // sieht wie der Haupt-Leak-Detektor. Default =nil -> Global-Fallback.
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, CanBeStrictPrivate, LongMethod, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

class procedure TMissingFinallyDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  LocalVars    : TList<TAstNode>;
  V            : TAstNode;
  VarNameLow   : string;
  FreeFound    : Boolean;
  FreeInFin    : Boolean;
  HasExcept    : Boolean;
  HasReraise   : Boolean;
  RaiseNodes   : TList<TAstNode>;
  R            : TAstNode;
  F            : TLeakFinding;
  StrippedLines: TArray<string>;   // finally-Mis-Attachment-Fix (lazy, Port aus uLeakDetector2)
  StrippedReady: Boolean;
  SrcLines     : TStringList;
  SrcOwned     : Boolean;

  procedure EnsureStripped;
  // Lazy: erst wenn ein MissingFinally-Befund anstehen wuerde. Nutzt den
  // geteilten Strip-Cache (einmal pro Datei) und splittet in Zeilen.
  // 1:1 aus TLeakDetector2.AnalyzeMethod (finally-Region-by-Source).
  var
    Code    : string;
    LineFor : TArray<Integer>;
  begin
    if StrippedReady then Exit;
    StrippedReady := True;   // auch bei Fehlschlag nicht erneut versuchen
    SrcLines := AcquireLines(FileName, SrcOwned, CtxFileTextCache(AContext));
    if SrcLines = nil then Exit;
    Code := TDetectorUtils.StripStringsAndCommentsCached(
      SrcLines, LineFor, AContext, FileName, ' ');
    StrippedLines := Code.Split([#10]);
  end;

begin
  StrippedReady := False;
  SrcLines      := nil;
  SrcOwned      := False;
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
      if not TLeakDetector2.IsLeakyType(V.TypeRef, AContext) then Continue;

      VarNameLow := V.Name.ToLower;

      if not TLeakDetector2.HasCreateAssign(MethodNode, VarNameLow) then Continue;
      if TLeakDetector2.IsReturnedAsResult(MethodNode, VarNameLow) then Continue;
      if TLeakDetector2.IsPassedToOwner(MethodNode, VarNameLow)    then Continue;
      // Konsistenz-Port (Welle 2, 2026-07-18): uLeakDetector2 Pfad 1 hat dieses
      // Owner-Param-Gate (Z.1444), MissingFinally fehlte es. TKlasse.Create(Self/
      // Owner/AOwner/Application) uebergibt Ownership per TComponent-Konvention an
      // den Owner -> kein manuelles try/finally noetig -> kein Befund. Monoton.
      if TLeakDetector2.IsOwnerParamCreate(MethodNode, VarNameLow) then Continue;

      // Free muss vorhanden sein – sonst meldet TLeakDetector2 als lsError
      FreeFound := TLeakDetector2.SearchFree(MethodNode, VarNameLow,
                                             False, FreeInFin);
      if not FreeFound then Continue;
      // Free liegt bereits IM finally - alles gut, kein MissingFinally.
      if FreeInFin then Continue;
      // try/except MIT bare re-raise = Cleanup-und-Reraise-Idiom (s.o.) ->
      // funktional try/finally fuer den Fehlerpfad, kein MissingFinally.
      if HasExcept and HasReraise then Continue;

      // finally-Mis-Attachment-Fix (Konsistenz-Port aus uLeakDetector2, Welle 2
      // 2026-07-18; Auto-Runde 2026-07-19: Anker von nkFinallyBlock auf QUELLE
      // umgestellt): der AST-FreeInFin sagt "nicht im finally", aber in der
      // QUELLE liegt der Free doch in einer finally-Region - der Parser
      // attachiert bei nested try / {$IFDEF} / 'F:=nil;try' sogar den AEUSSEREN
      // nkFinallyBlock fehl (der AST-Anker war deshalb fuer die realen Faelle
      // ein No-Op). FreeInFinallyRegionBySource scannt jetzt die 'finally'-
      // Keywords der gestrippten Quelle innerhalb der Methodenspanne. Monoton,
      // TP-safe: suppressed nur bei bewiesenem Region-Containment (kein
      // finally in der Quelle -> False).
      EnsureStripped;
      if TLeakDetector2.FreeInFinallyRegionBySource(
           MethodNode, StrippedLines, VarNameLow) then Continue;

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
    if SrcLines <> nil then ReleaseLines(SrcLines, SrcOwned);
  end;
end;

class procedure TMissingFinallyDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(M, FileName, Results, AContext);
  finally
    Methods.Free;
  end;
end;

end.

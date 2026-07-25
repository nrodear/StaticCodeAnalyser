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

  function SafeSpanSuppresses(const AVarLow, ATypeRefLow: string;
    ACreateLine: Integer): Boolean;
  // C1 (Triage 2026-07-24, groesste SCA009-FP-Klasse 'kein riskanter Code
  // dazwischen'): zwischen Create und Free steht AUSSCHLIESSLICH nicht-
  // werfender Code auf dem Objekt selbst -> die try/finally-Forderung ist
  // nicht actionable (FP). STRENG:
  //   * Typ-Gate: nur bekannte speicherbasierte RTL-Container (IO-Member
  //     zusaetzlich per loadfrom/saveto-Verbot ausgeschlossen); TSQLQuery &
  //     Co. (Open wirft!) sind NICHT in der Liste -> Gate aus.
  //   * Create-Zeile = genau ein Statement; Free-Zeile unkonditional
  //     (beginnt mit '<var>.free'/'freeandnil(<var>').
  //   * Jede Span-Zeile: '<var>.member ...' oder 'lokal := <var>.member'
  //     oder begin/end - ALLES andere (if/for/try/with/exit/raise/goto,
  //     fremde Calls, Fortsetzungszeilen) -> kein Drop.
  // Kein Stripped-Cache (In-Memory-Harness) -> kein Drop (fail-safe).
  const
    SAFE_TYPES : array[0..9] of string = (
      'tstringlist', 'tlist', 'tobjectlist', 'tstringstream',
      'tmemorystream', 'tstringbuilder', 'tqueue', 'tstack',
      'tdictionary', 'tobjectdictionary');
  var
    TypeBase : string;
    i, FreeIdx : Integer;
    L : string;
    OK : Boolean;
  begin
    Result := False;
    if (ACreateLine <= 0) or (Length(StrippedLines) = 0)
       or (ACreateLine > Length(StrippedLines)) then Exit;
    TypeBase := Trim(ATypeRefLow);
    i := Pos('<', TypeBase);
    if i > 0 then TypeBase := Trim(Copy(TypeBase, 1, i - 1));
    OK := False;
    for var st in SAFE_TYPES do
      if TypeBase = st then begin OK := True; Break; end;
    if not OK then Exit;
    L := LowerCase(Trim(StrippedLines[ACreateLine - 1]));
    if not (L.StartsWith(AVarLow + ' :=') or L.StartsWith(AVarLow + ':=')) then
      Exit;
    i := Pos(';', L);
    if (i = 0) or (Trim(Copy(L, i + 1, MaxInt)) <> '') then Exit;
    FreeIdx := 0;
    for i := ACreateLine + 1 to Length(StrippedLines) do
    begin
      L := LowerCase(Trim(StrippedLines[i - 1]));
      if L.StartsWith(AVarLow + '.free') or L.StartsWith(AVarLow + '.destroy')
         or L.StartsWith('freeandnil(' + AVarLow) then
      begin
        FreeIdx := i;
        Break;
      end;
    end;
    if FreeIdx = 0 then Exit;
    for i := ACreateLine + 1 to FreeIdx - 1 do
    begin
      L := LowerCase(Trim(StrippedLines[i - 1]));
      if (L = '') or (L = 'begin') or (L = 'end') or (L = 'end;') then Continue;
      if (Pos('loadfrom', L) > 0) or (Pos('saveto', L) > 0) then Exit;
      if L.StartsWith(AVarLow + '.') then Continue;
      var pAss := Pos(':=', L);
      if pAss > 0 then
      begin
        var LHS := Trim(Copy(L, 1, pAss - 1));
        var RHS := Trim(Copy(L, pAss + 2, MaxInt));
        var LhsPlain := LHS <> '';
        for var k := 1 to Length(LHS) do
          if not CharInSet(LHS[k], ['a'..'z', '0'..'9', '_']) then
          begin
            LhsPlain := False;
            Break;
          end;
        if LhsPlain and RHS.StartsWith(AVarLow + '.') then Continue;
      end;
      Exit;   // alles andere: kein Drop
    end;
    Result := True;
  end;

  function ExceptSwallowSuppresses(const AVarLow: string;
    ACreateLine: Integer): Boolean;
  // C2 (Triage 2026-07-24, umgesetzt 2026-07-25): except-SWALLOW-Fall.
  // Muster:
  //   Obj := TFoo.Create;
  //   try ... except <Handler ohne raise/Exit/goto> end;
  //   Obj.Free;
  // Der Handler SCHLUCKT die Exception -> die Ausfuehrung erreicht Obj.Free
  // auf BEIDEN Pfaden -> kein Leak-Fenster, die try/finally-Forderung ist
  // ein FP. Ergaenzt das bestehende 'HasExcept and HasReraise'-Gate, das
  // nur den RE-RAISE-Fall abdeckt. Quell-basiert auf StrippedLines
  // (Kommentare/Strings zaehlen nie); STRENG und fail-safe wie
  // SafeSpanSuppresses:
  //   * Create-Zeile = genau ein Statement; direkt danach (nur Leer-/begin-
  //     Zeilen dazwischen) ein alleinstehendes 'try'.
  //   * Balancierte begin/case-end-Zaehlung; bei JEDEM nested 'try' (oder
  //     'finally'/'asm') im Bereich -> kein Drop (konservativ).
  //   * try-TEIL: 'raise' ist ok (wird ja gefangen), aber 'exit'/'goto'
  //     sind verboten (umgehen den Free). except-TEIL: 'raise*' (auch
  //     RaiseOuterException), 'exit', 'goto', 'break', 'continue' verboten
  //     (alles davon verlaesst den Handler, ohne den Free zu erreichen).
  //   * Der except-Block muss mit purem 'end;' schliessen; danach (nur
  //     Leerzeilen dazwischen) unkonditional '<var>.free;' bzw.
  //     'freeandnil(<var>);' als naechstes Statement.
  // Kein Stripped-Cache (In-Memory-Harness) -> kein Drop (fail-safe).
  var
    i, j, k  : Integer;
    L, Tok   : string;
    TryLine  : Integer;
    EndLine  : Integer;
    Depth    : Integer;
    InExcept : Boolean;
  begin
    Result := False;
    if (ACreateLine <= 0) or (Length(StrippedLines) = 0)
       or (ACreateLine > Length(StrippedLines)) then Exit;
    // Create-Zeile: Einzelstatement '<var> := ...;'
    L := LowerCase(Trim(StrippedLines[ACreateLine - 1]));
    if not (L.StartsWith(AVarLow + ' :=') or L.StartsWith(AVarLow + ':=')) then
      Exit;
    i := Pos(';', L);
    if (i = 0) or (Trim(Copy(L, i + 1, MaxInt)) <> '') then Exit;
    // Direkt folgend (nur Leer-/begin-Zeilen dazwischen): alleinstehendes 'try'
    TryLine := 0;
    for i := ACreateLine + 1 to Length(StrippedLines) do
    begin
      L := LowerCase(Trim(StrippedLines[i - 1]));
      if (L = '') or (L = 'begin') then Continue;
      if L = 'try' then TryLine := i;
      Break;
    end;
    if TryLine = 0 then Exit;
    // try..except..end; abschreiten (tokenweise, balanciert)
    Depth    := 0;
    InExcept := False;
    EndLine  := 0;
    for i := TryLine + 1 to Length(StrippedLines) do
    begin
      L := LowerCase(Trim(StrippedLines[i - 1]));
      j := 1;
      while j <= Length(L) do
      begin
        if CharInSet(L[j], ['a'..'z', '_']) then
        begin
          k := j;
          while (k <= Length(L)) and CharInSet(L[k], ['a'..'z', '0'..'9', '_']) do
            Inc(k);
          Tok := Copy(L, j, k - j);
          // Member-Zugriffe ('obj.free', 'e.classname') sind KEINE
          // Schluesselwoerter - Tokens mit '.'-Vorgaenger ueberspringen.
          if (j > 1) and (L[j - 1] = '.') then Tok := '';
          j := k;
          if Tok <> '' then
          begin
            // Nested try (auch try/finally) oder asm im Bereich: die
            // Kontrollfluss-Analyse waere nicht mehr trivial -> kein Drop.
            if (Tok = 'try') or (Tok = 'finally') or (Tok = 'asm') then Exit;
            if (Tok = 'begin') or (Tok = 'case') then
              Inc(Depth)
            else if Tok = 'end' then
            begin
              if Depth > 0 then
                Dec(Depth)
              else
              begin
                // Schliessendes end des try..except: muss NACH except liegen
                // und als pures 'end;' schliessen (kein Code dahinter).
                if not InExcept then Exit;
                if Trim(Copy(L, j, MaxInt)) <> ';' then Exit;
                EndLine := i;
              end;
            end
            else if Tok = 'except' then
            begin
              if (Depth > 0) or InExcept then Exit;
              InExcept := True;
            end
            // Exit/goto im try-Teil umgehen den Free (Exit wird NICHT
            // gefangen!) und sind im except-Teil ebenso toedlich -> aus.
            else if (Tok = 'exit') or (Tok = 'goto') then
              Exit
            // Handler darf nicht re-raisen (raise/raise <expr>/E.RaiseOuter-
            // Exception via raise*-Praefix) und nicht per break/continue aus
            // einer umgebenden Schleife springen -> sonst kein Swallow-Beweis.
            else if InExcept and ((Copy(Tok, 1, 5) = 'raise')
                    or (Tok = 'break') or (Tok = 'continue')) then
              Exit;
          end;
        end
        else
          Inc(j);
      end;
      if EndLine > 0 then Break;
    end;
    if EndLine = 0 then Exit;
    // Nach dem 'end;' (nur Leerzeilen dazwischen): unkonditionaler Free als
    // ganzes Statement - strenger als SafeSpan (exaktes Match statt Praefix).
    for i := EndLine + 1 to Length(StrippedLines) do
    begin
      L := LowerCase(Trim(StrippedLines[i - 1]));
      if L = '' then Continue;
      if (L = AVarLow + '.free;')
         or (L = 'freeandnil(' + AVarLow + ');') then
        Result := True;
      Exit;   // erste Nicht-Leerzeile entscheidet
    end;
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

      // C1: SafeSpan - nur harmloser Container-Code zwischen Create und
      // Free -> kein actionabler Befund (EnsureStripped lief oben schon).
      if SafeSpanSuppresses(VarNameLow, LowerCase(V.TypeRef), ReportLine) then
        Continue;

      // C2: except-swallow - der Handler schluckt die Exception, Obj.Free
      // wird auf beiden Pfaden erreicht -> kein Leak-Fenster (Triage
      // 2026-07-24, umgesetzt 2026-07-25; EnsureStripped lief oben schon).
      if ExceptSwallowSuppresses(VarNameLow, ReportLine) then
        Continue;

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

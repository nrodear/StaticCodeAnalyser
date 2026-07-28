unit uNotIncludedInProject;

// Detektor SCA194 - NotIncludedInProject (User-Anforderung 2026-07-22).
//
// Idee: Beim Scan einer Projektdatei (.dproj) oder Projektgruppe (.groupproj)
// kennt die Engine die EXAKTE Projekt-Dateiliste (DCCReferences, via
// uProjectFiles). Diese wird gegen ALLE .pas/.dfm-Dateien im Projektordner
// (rekursiv) verglichen. Dateien, die physisch im Ordner liegen, aber NICHT
// zum Projekt gehoeren, sind verwaiste/tote Quellen -> Finding.
//
// Warum kein normaler AST-Detektor:
//   Dies ist ein SCAN-UEBERGREIFENDER Vergleich (Projekt-Liste vs. Platte),
//   kein per-.pas-Check. Er hat keinen UnitNode. Deshalb wird er NICHT ueber
//   die gDetectors-Registry gefahren, sondern direkt aus dem
//   ssProject/ssProjectGroup-Dispatch in TAnalysisSession.Run aufgerufen
//   (uEngineApi) - dort liegt die aufgeloeste Projektliste vor. In allen
//   anderen Scopes (ssRecursive/ssSingleFile/...) gibt es keine Projekt-
//   Mitgliedschaft; der Detektor laeuft dort schlicht nicht.
//
// .dfm-Logik: Ein .dfm gilt als "im Projekt", wenn seine gleichnamige .pas
// im Projekt referenziert ist (Companion). Ein .dfm ohne referenzierte .pas
// (bzw. ohne .pas) ist verwaist.
//
// SCA195-Abspaltung (User-Anforderung 2026-07-29): Eine Datei, die NICHT im
// Projekt steht, aber von Projekt-Units per uses gezogen wird, ist NICHT
// verwaist - sie kompiliert ueber den Suchpfad mit und fehlt lediglich in
// der Projektverwaltung. Das ist eine ANDERE Aussage mit anderem Fix
// ("ins Projekt aufnehmen" statt "loeschen/pruefen"), deshalb ein eigenes
// Finding-Kind fkUsedButNotInProject. Die Zuordnung ist TRANSITIV: zieht
// eine Projekt-Unit Orphan A und A wiederum Orphan B, dann kompiliert auch
// B mit (der Compiler folgt den uses ueber den Suchpfad) - B ist also
// ebenfalls 195, nicht 194. uses-Namen werden LEXIKALISCH gewonnen
// (Kommentare/Strings vorher geblankt - Projektregel: Kommentare zaehlen
// NIE als Code-Use); der Match laeuft ueber den Dateinamen ohne Endung,
// der bei Delphi dem (ggf. gepunkteten) Unit-Namen entspricht.
// v1-Grenzen:
//   * Eine Orphan-Datei, die namensgleich mit einer benutzten RTL-/Fremd-
//     Unit ist (z.B. eine lokale Windows.pas), wird als 195 gemeldet,
//     obwohl der Compiler je nach Suchpfad die andere nehmen kann -
//     Namensgleichheit im Projektbaum ist aber selbst ein Befund wert.
//   * Whitespace INNERHALB eines gepunkteten uses-Namens ('System .
//     SysUtils' - legal, aber exotisch) zerreisst den Match; die Unit
//     bliebe 194.
//   * Der Fixpunkt ist O(Orphans x Kettentiefe) mit NormKey-Aufrufen pro
//     Runde - beim 20000-Datei-Cap theoretisch quadratisch, praktisch von
//     der Kettentiefe (wenige Runden) begrenzt.
//
// Walk-Root: der CommonRoot der AUFGELOESTEN Projektliste (BaseDir aus dem
// Dispatch), rekursiv - NICHT das .dproj-Verzeichnis. Grund (Real-World-Scan
// 2026-07-22): reale Projekte legen die .dproj oft in packages\ und die Units
// in ..\source\; ein Walk des .dproj-Ordners faende dann fast nichts. Der
// CommonRoot ist das engste Verzeichnis, das ALLE Projektdateien umschliesst -
// dort liegen auch die verwaisten Nachbardateien. Search-Path-Units ausserhalb
// dieses Baums bleiben unberuehrt (v1-Grenze).
//
// Robustheit (Review 2026-07-22):
//   * DETERMINISTISCHE Reihenfolge: die Fundliste wird vor dem Emittieren
//     sortiert (FindFirst-Reihenfolge ist FS-abhaengig) - sonst waere das
//     SARIF nicht byte-stabil ueber Laeufe.
//   * ignore.txt-Parity: der Walk respektiert dieselbe TIgnoreList wie die
//     Projektliste (sonst wuerde eine bewusst ignorierte Datei faelschlich
//     als Orphan gemeldet).
//   * MAX-Files-Cap analog Haupt-Scanner - Schutz vor versehentlich riesigem
//     Walk-Root (z.B. .dproj im Repo-Root).
//   * .dpr/.dpk werden nie gesammelt (nur .pas/.dfm) - die Projekt-
//     Hauptdatei kann sich also nicht selbst als Orphan melden.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uMethodd12, uSCAConsts, uIgnoreList;

type
  TNotIncludedInProjectDetector = class
  public
    // AProjectPasList: die aufgeloeste .pas-Projektliste (uProjectFiles),
    //   absolute Pfade. AWalkRoot: Verzeichnis, das rekursiv nach .pas/.dfm
    //   durchsucht wird (Projekt-/Gruppendatei-Verzeichnis). AIgnore (opt.):
    //   dieselbe Ignore-Liste wie fuer die Projektliste. Haengt pro
    //   Datei ohne Projekt-Referenz ein Finding an AResults (nach Pfad
    //   sortiert): fkUsedButNotInProject wenn per uses gezogen, sonst
    //   fkNotIncludedInProject. Liefert die Anzahl der Funde.
    // AProjectFile (opt.): Pfad der .dproj - Detect liest zusaetzlich die
    // uses-Klausel der gleichnamigen .dpr/.dpk (die Programm-Hauptdatei
    // steht NIE in der DCCReference-Liste; ohne sie blieben Units, die nur
    // das .dpr zieht, faelschlich SCA194 statt SCA195 - Review 2026-07-29).
    // Bei .groupproj existiert keine gleichnamige .dpr - harmloser No-Op.
    class function Detect(AProjectPasList: TStringList;
      const AWalkRoot: string;
      AResults: TObjectList<TLeakFinding>;
      AIgnore: TIgnoreList = nil;
      const AProjectFile: string = ''): Integer; static;
  end;

implementation

uses
  System.IOUtils,
  uDetectorUtils,    // IsIdentChar (uses-Scan, SCA195)
  uFileTextCache;    // AcquireLines/ReleaseLines - Projektdateien liegen nach
                     // dem Hauptscan im Cache (uses-Scan praktisch I/O-frei);
                     // Orphans/Testkontext laufen ueber den Fallback-Load

const
  // Wie TStaticFiles.EXCLUDED_DIRS - bewusst dupliziert, damit dieser
  // Ein-Mal-pro-Projektscan-Walk den perf-kritischen *.pas-Scanner nicht
  // anfasst. Bei Aenderungen dort hier mitziehen.
  EXCLUDED_DIRS : array[0..6] of string =
    ('.', '..', '__recovery', '__history', '.git', '.svn', 'node_modules');
  MAX_DEPTH     = 32;
  MAX_WALK_FILES = 20000;   // Cap analog TStaticAnalyzer2/uIDEAnalyseRunner

// Sammelt alle uses-Referenzen (lowercase, voller - ggf. gepunkteter - Name)
// der Datei in ANames. Lexikalisch auf dem GESTRIPPTEN Text: Kommentare und
// String-Literale sind geblankt, bevor irgendetwas zaehlt (Projektregel:
// Kommentare sind NIE Code-Use; und der Pfad-String einer
// "X in 'file.pas'"-Klausel kann so kein Phantom-'uses' liefern).
// Danach reiner Wort-Lauf: ab jedem Wort 'uses' werden Ident-Folgen
// (inklusive Punkten fuer dotted units) bis zum ';' eingesammelt; das
// reservierte 'in' wird uebersprungen. 'uses' ist ein reserviertes Wort und
// kann im gestrippten Code nirgendwo sonst als ganzes Wort auftauchen -
// interface- und implementation-Klausel werden so automatisch beide erfasst.
// Eigener Mini-Stripper NUR fuer den uses-Scan: Kommentare, Compiler-
// Direktiven und String-Literale werden durch je EIN Leerzeichen ersetzt.
//
// Warum nicht TDetectorUtils.StripStringsAndComments: das entfernt
// {..}-Bloecke ERSATZLOS - beim Cross-Platform-Idiom
//   uses {$IFDEF FPC}fgl{$ELSE}Generics.Collections{$ENDIF};
// verschmolzen die Nachbar-Idents zum Phantom-Token
// 'fglgenerics.collections' und KEINER der beiden Namen wurde gesammelt
// (Review 2026-07-29). Mit Leerzeichen-Ersatz zaehlen BEIDE Zweige - fuer
// diese Regel die richtige Semantik: welcher Zweig aktiv ist, haengt von
// Defines ab, und eine Unit, die in irgendeinem Zweig gezogen wird, ist
// nicht tot.
function StripForUsesScan(const Raw: string): string;
var
  SB   : TStringBuilder;
  i, n : Integer;
begin
  SB := TStringBuilder.Create(Length(Raw));
  try
    i := 1;
    n := Length(Raw);
    while i <= n do
    begin
      case Raw[i] of
        '''':
          begin
            Inc(i);
            while i <= n do
            begin
              if Raw[i] = '''' then
              begin
                if (i < n) and (Raw[i + 1] = '''') then
                  Inc(i, 2)          // verdoppeltes Apostroph im Literal
                else
                begin
                  Inc(i);
                  Break;
                end;
              end
              else if Raw[i] = #10 then
                Break                // Delphi-Literal endet an der Zeile
              else
                Inc(i);
            end;
            SB.Append(' ');
          end;
        '{':
          begin
            while (i <= n) and (Raw[i] <> '}') do Inc(i);
            if i <= n then Inc(i);   // '}' konsumieren
            SB.Append(' ');
          end;
        '(':
          if (i < n) and (Raw[i + 1] = '*') then
          begin
            Inc(i, 2);
            while (i < n) and not ((Raw[i] = '*') and (Raw[i + 1] = ')')) do
              Inc(i);
            if i < n then Inc(i, 2) else i := n + 1;
            SB.Append(' ');
          end
          else
          begin
            SB.Append(Raw[i]);
            Inc(i);
          end;
        '/':
          if (i < n) and (Raw[i + 1] = '/') then
          begin
            while (i <= n) and (Raw[i] <> #10) do Inc(i);
            SB.Append(' ');          // das #10 bleibt fuer die naechste Runde
          end
          else
          begin
            SB.Append(Raw[i]);
            Inc(i);
          end;
      else
        SB.Append(Raw[i]);
        Inc(i);
      end;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure CollectUsesNames(const AFile: string;
  ANames: TDictionary<string, Boolean>);
var
  Lines  : TStringList;
  Owned  : Boolean;
  Text   : string;
  i, n   : Integer;
  Start  : Integer;
  W      : string;
  InUses : Boolean;
begin
  // AcquireLines statt gFileTextCache.GetLines direkt: das Global startet
  // nil (leere initialization-Sektion!) und wird erst vom Scan-Setup
  // erzeugt - AcquireLines faellt dann auf einen lokalen Load zurueck.
  // Im Projekt-Scan ist es ein Cache-Hit (der Hauptscan hat die Dateien
  // schon gelesen), im Test-/Standalone-Kontext ein Einzel-Load.
  Lines := AcquireLines(AFile, Owned);
  if Lines = nil then Exit;
  try
    Text := LowerCase(StripForUsesScan(Lines.Text));
  finally
    ReleaseLines(Lines, Owned);
  end;
  n := Length(Text);
  i := 1;
  InUses := False;
  while i <= n do
  begin
    if TDetectorUtils.IsIdentChar(Text[i]) then
    begin
      Start := i;
      while (i <= n) and (TDetectorUtils.IsIdentChar(Text[i]) or
            (InUses and (Text[i] = '.'))) do
        Inc(i);
      W := Copy(Text, Start, i - Start);
      if not InUses then
      begin
        // '&uses' waere ein escaped Ident, kein Schluesselwort.
        if (W = 'uses') and ((Start = 1) or (Text[Start - 1] <> '&')) then
          InUses := True;
      end
      else if (W <> 'in') and (W <> '') then
        ANames.AddOrSetValue(W, True);
    end
    else
    begin
      if InUses and (Text[i] = ';') then
        InUses := False;
      Inc(i);
    end;
  end;
end;

function NormKey(const APath: string): string;
begin
  // Case-insensitiv (Windows) + KANONISCH. uProjectFiles liefert bereits
  // GetFullPath-Pfade; der Walk kann bei relativem/nicht-kanonischem Root
  // aber '..'/relative Pfade liefern - deshalb hier explizit GetFullPath,
  // damit beide Seiten sicher deckungsgleich sind (Review 2026-07-22:
  // sonst FP-Storm bei 'sca --project sub\P.dproj'). GetFullPath ist auf
  // existierenden Datei-/Absolutpfaden idempotent + wirft praktisch nicht;
  // Fallback auf reines LowerCase falls doch.
  try
    Result := LowerCase(TPath.GetFullPath(APath));
  except
    Result := LowerCase(APath);
  end;
end;

class function TNotIncludedInProjectDetector.Detect(
  AProjectPasList: TStringList; const AWalkRoot: string;
  AResults: TObjectList<TLeakFinding>; AIgnore: TIgnoreList;
  const AProjectFile: string): Integer;
var
  ProjSet     : TDictionary<string, Boolean>;
  UsedNames   : TDictionary<string, Boolean>;
  UsedOrphans : TDictionary<string, Boolean>;
  DiskPas     : TStringList;
  DiskDfm     : TStringList;
  Orphans     : TStringList;
  F, Comp     : string;
  i           : Integer;
  Aborted     : Boolean;
  Changed     : Boolean;
  Emit194     : Boolean;
  Emit195     : Boolean;

  procedure Walk(const APath: string; ADepth: Integer);
  var
    SR   : TSearchRec;
    Full : string;
    Ext  : string;
    Excl : Boolean;
    Dir  : string;
  begin
    if Aborted or (ADepth > MAX_DEPTH) then Exit;
    if FindFirst(IncludeTrailingPathDelimiter(APath) + '*', faAnyFile, SR) <> 0 then
      Exit;
    try
      repeat
        if Aborted then Exit;
        {$WARN SYMBOL_PLATFORM OFF}
        if (SR.Attr and faSymLink) <> 0 then Continue;
        {$WARN SYMBOL_PLATFORM ON}
        if (SR.Attr and faDirectory) <> 0 then
        begin
          Excl := False;
          for Dir in EXCLUDED_DIRS do
            if SameText(SR.Name, Dir) then begin Excl := True; Break; end;
          if Excl then Continue;
          Full := IncludeTrailingPathDelimiter(APath) + SR.Name;
          // Verzeichnis-Ebene der Ignore-Liste (Trick wie TStaticFiles):
          // ganzer Unterbaum uebersprungen, wenn das Verzeichnis ignoriert ist.
          if Assigned(AIgnore) and
             AIgnore.IsIgnored(IncludeTrailingPathDelimiter(Full) + 'dummy.pas') then
            Continue;
          Walk(Full, ADepth + 1);
        end
        else
        begin
          Ext := LowerCase(ExtractFileExt(SR.Name));
          if (Ext <> '.pas') and (Ext <> '.dfm') then Continue;
          Full := IncludeTrailingPathDelimiter(APath) + SR.Name;
          if Assigned(AIgnore) and AIgnore.IsIgnored(Full) then Continue;
          if Ext = '.pas' then DiskPas.Add(Full) else DiskDfm.Add(Full);
          if (DiskPas.Count + DiskDfm.Count) >= MAX_WALK_FILES then
          begin
            Aborted := True;   // Cap erreicht - Walk sauber beenden
            Exit;
          end;
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;

begin
  Result := 0;
  if (AProjectPasList = nil) or (AResults = nil) then Exit;
  if (AWalkRoot = '') or not DirectoryExists(AWalkRoot) then Exit;

  // Per-Kind-Gating: dieser Pfad laeuft am Post-Filter vorbei, deshalb
  // wird hier selbst entschieden, welches der beiden Kinds emittiert
  // werden darf (der Dispatch prueft nur noch, ob MINDESTENS eines an ist).
  Emit194 := (uSCAConsts.DetectorEnabledKinds = []) or
             (fkNotIncludedInProject in uSCAConsts.DetectorEnabledKinds);
  Emit195 := (uSCAConsts.DetectorEnabledKinds = []) or
             (fkUsedButNotInProject in uSCAConsts.DetectorEnabledKinds);
  if not (Emit194 or Emit195) then Exit;

  ProjSet     := TDictionary<string, Boolean>.Create;
  UsedNames   := TDictionary<string, Boolean>.Create;
  UsedOrphans := TDictionary<string, Boolean>.Create;
  DiskPas     := TStringList.Create;
  DiskDfm     := TStringList.Create;
  Orphans     := TStringList.Create;
  try
    for i := 0 to AProjectPasList.Count - 1 do
      ProjSet.AddOrSetValue(NormKey(AProjectPasList[i]), True);

    Aborted := False;
    Walk(AWalkRoot, 0);

    // SCA195-Vorbereitung: uses-Namen aller PROJEKT-Units einsammeln.
    // Die Dateien liegen nach dem Hauptscan im gFileTextCache - das ist
    // ein Woerterbuch-Aufbau, kein zweiter Disk-Scan.
    for i := 0 to AProjectPasList.Count - 1 do
      CollectUsesNames(AProjectPasList[i], UsedNames);

    // Programm-Hauptdatei (.dpr/.dpk): steht nie in der DCCReference-
    // Liste, ihre uses-Klausel ist aber die WURZEL des Kompilats -
    // handgepflegte Projekte ziehen Units oft NUR von dort.
    if AProjectFile <> '' then
    begin
      F := ChangeFileExt(AProjectFile, '.dpr');
      if FileExists(F) then CollectUsesNames(F, UsedNames);
      F := ChangeFileExt(AProjectFile, '.dpk');
      if FileExists(F) then CollectUsesNames(F, UsedNames);
    end;

    // Verwaiste .pas klassifizieren: benutzt (fkUsedButNotInProject) oder
    // tot (fkNotIncludedInProject). TRANSITIVER Fixpunkt: eine als benutzt
    // erkannte Orphan-Unit traegt ihre eigenen uses-Namen nach - der
    // Compiler folgt der Kette ueber den Suchpfad genauso.
    repeat
      Changed := False;
      for F in DiskPas do
      begin
        if ProjSet.ContainsKey(NormKey(F)) then Continue;
        if UsedOrphans.ContainsKey(NormKey(F)) then Continue;
        if UsedNames.ContainsKey(
             LowerCase(ChangeFileExt(ExtractFileName(F), ''))) then
        begin
          UsedOrphans.AddOrSetValue(NormKey(F), True);
          CollectUsesNames(F, UsedNames);
          Changed := True;
        end;
      end;
    until not Changed;

    // Tags: 0 = .pas tot, 1 = .dfm tot, 2 = .pas benutzt, 3 = .dfm dessen
    // .pas benutzt ist (Companion folgt der Klassifikation seiner Unit).
    for F in DiskPas do
      if not ProjSet.ContainsKey(NormKey(F)) then
      begin
        if UsedOrphans.ContainsKey(NormKey(F)) then
          Orphans.AddObject(F, TObject(2))
        else
          Orphans.AddObject(F, TObject(0));
      end;

    for F in DiskDfm do
    begin
      Comp := ChangeFileExt(F, '.pas');
      if ProjSet.ContainsKey(NormKey(Comp)) then Continue;
      if UsedOrphans.ContainsKey(NormKey(Comp)) then
        Orphans.AddObject(F, TObject(3))
      else
        Orphans.AddObject(F, TObject(1));
    end;

    // DETERMINISTISCHE Ausgabe: nach Pfad sortieren (FindFirst-Reihenfolge
    // ist FS-abhaengig -> sonst nicht byte-stabil). Die Object-Tags wandern
    // beim Sort mit, sodass die passende Message erhalten bleibt.
    Orphans.CaseSensitive := False;
    Orphans.Sort;

    for i := 0 to Orphans.Count - 1 do
    begin
      case IntPtr(Orphans.Objects[i]) of
        0: if Emit194 then
           begin
             AResults.Add(TLeakFinding.New(Orphans[i], '', 1,
               'Source file is in the project folder but not referenced by the ' +
               'project (.dproj/.groupproj) - orphaned / dead unit?',
               fkNotIncludedInProject));
             Inc(Result);
           end;
        1: if Emit194 then
           begin
             AResults.Add(TLeakFinding.New(Orphans[i], '', 1,
               'Form file (.dfm) is in the project folder but its unit is not ' +
               'referenced by the project (.dproj/.groupproj) - orphaned form?',
               fkNotIncludedInProject));
             Inc(Result);
           end;
        2: if Emit195 then
           begin
             AResults.Add(TLeakFinding.New(Orphans[i], '', 1,
               'Unit is used by the project (via uses, compiled through the ' +
               'search path) but not included in the project file ' +
               '(.dproj/.groupproj) - add it to the project',
               fkUsedButNotInProject));
             Inc(Result);
           end;
        3: if Emit195 then
           begin
             AResults.Add(TLeakFinding.New(Orphans[i], '', 1,
               'Form file (.dfm) belongs to a unit that is used by the ' +
               'project but not included in the project file ' +
               '(.dproj/.groupproj) - add the unit (and its form) to the project',
               fkUsedButNotInProject));
             Inc(Result);
           end;
      end;
    end;
  finally
    Orphans.Free;
    DiskDfm.Free;
    DiskPas.Free;
    UsedOrphans.Free;
    UsedNames.Free;
    ProjSet.Free;
  end;
end;

end.

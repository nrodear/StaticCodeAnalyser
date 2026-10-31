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
// Namensvetter einer PROJEKT-Unit (Review 2026-07-30): eine Orphan-Datei,
// deren Name bereits durch eine Datei der Projektliste gedeckt ist
// (backup\uMain.pas neben der referenzierten src\uMain.pas), bleibt 194 -
// die DCCReference/'in'-Klausel pinnt den Pfad, der Compiler kompiliert
// die Projekt-Datei, die Kopie ist tot ('experimental copies' sind ein
// 194-Kernszenario). Sie speist auch ihre uses NICHT in den Fixpunkt.
// v1-Grenzen:
//   * Eine Orphan-Datei, die namensgleich mit einer benutzten RTL-/Fremd-
//     Unit ist (z.B. eine lokale Windows.pas), wird als 195 gemeldet,
//     obwohl der Compiler je nach Suchpfad die andere nehmen kann -
//     Namensgleichheit im Projektbaum ist aber selbst ein Befund wert
//     (nur fuer NICHT-Projekt-Namen; Projekt-Namensvetter siehe oben).
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
    // uses-Klausel der gleichnamigen .dpr bzw. die uses+contains-Klausel
    // der gleichnamigen .dpk (die Programm-Hauptdatei steht NIE in der
    // DCCReference-Liste; ohne sie blieben Units, die nur das .dpr zieht,
    // faelschlich SCA194 statt SCA195 - Review 2026-07-29).
    // AMemberProjects (opt., Review 2026-07-30): bei .groupproj existiert
    // keine gleichnamige .dpr - die uses-Wurzeln liegen in den MEMBER-
    // Projekten. Der Dispatch uebergibt deren .dproj-Pfade, Detect zieht
    // pro Member die .dpr/.dpk nach; ohne sie bekaeme eine nur vom
    // Member-.dpr gezogene Unit im Gruppen-Scan 194 statt 195.
    class function Detect(AProjectPasList: TStringList;
      const AWalkRoot: string;
      AResults: TObjectList<TLeakFinding>;
      AIgnore: TIgnoreList = nil;
      const AProjectFile: string = '';
      AMemberProjects: TStrings = nil): Integer; static;
  end;

implementation

uses
  uStaticFiles,   // IsUnitLikeFile/IsFormFileName + .pp-Schluessel (Lazarus A4)
  System.IOUtils,
  uDetectorUtils,    // UsesNamesOfText (uses-Scan, SCA195)
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
  // Kompilat-Wurzel einer .dpk: zaehlt im uses-Scan wie 'uses'.
  DPK_ROOT_CLAUSE = 'contains';

// Sammelt alle uses-Referenzen (lowercase, voller - ggf. gepunkteter - Name)
// der Datei in ANames. Der lexikalische Scan (Kommentare, Direktiven und
// Strings geblankt, BEIDE Zweige einer {$IFDEF}-Weiche zaehlen, der
// 'in'-Pfad faellt weg) steht seit 2026-10-27 unveraendert in
// TDetectorUtils.UsesNamesOfText - SCA184/S4 braucht dieselbe Sicht.
// Begruendungen und Grenzen stehen dort.
procedure CollectUsesNames(const AFile: string;
  ANames: TDictionary<string, Boolean>;
  const AExtraClauseWord: string = '');
// AExtraClauseWord = DPK_ROOT_CLAUSE (Review 2026-07-30): .dpk-Packages
// haben keine uses-Klausel - die Kompilat-Wurzel ist dort 'contains'. Der
// Wort-Walk behandelt 'contains' dann wie 'uses' ('in'-Pfad-Skip greift
// identisch).
// Bewusst OPT-IN nur fuer .dpk-Wurzeln: in .pas-Dateien ist 'contains'
// kein reserviertes Wort und koennte als Bezeichner Phantom-Namen sammeln.
var
  Lines  : TStringList;
  Owned  : Boolean;
  Text   : string;
  W      : string;
begin
  // AcquireLines statt gFileTextCache.GetLines direkt: das Global startet
  // nil (leere initialization-Sektion!) und wird erst vom Scan-Setup
  // erzeugt - AcquireLines faellt dann auf einen lokalen Load zurueck.
  // Im Projekt-Scan ist es ein Cache-Hit (der Hauptscan hat die Dateien
  // schon gelesen), im Test-/Standalone-Kontext ein Einzel-Load.
  Lines := AcquireLines(AFile, Owned);
  if Lines = nil then Exit;
  try
    Text := Lines.Text;
  finally
    ReleaseLines(Lines, Owned);
  end;
  for W in TDetectorUtils.UsesNamesOfText(Text, AExtraClauseWord) do
  begin
    ANames.AddOrSetValue(W, True);
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
  const AProjectFile: string; AMemberProjects: TStrings): Integer;
var
  ProjSet     : TDictionary<string, Boolean>;
  ProjBase    : TDictionary<string, Boolean>;
  UsedNames   : TDictionary<string, Boolean>;
  UsedOrphans : TDictionary<string, Boolean>;
  DiskPas     : TStringList;
  DiskDfm     : TStringList;
  Orphans     : TStringList;
  F, Comp     : string;
  Base        : string;
  i           : Integer;
  Aborted     : Boolean;
  Changed     : Boolean;
  Emit194     : Boolean;
  Emit195     : Boolean;

  procedure Walk(const APath: string; ADepth: Integer);
  var
    SR   : TSearchRec;
    Full : string;
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
          // Lazarus A4: dieselben zwei Fragen wie ueberall - Unit-
          // Endungen des Dialekts plus Formdatei-Endungen. Bei
          // dlDelphi identisch zur alten Zweierliste.
          //
          // KORREKTUR nach dem ersten Bau (26 rote Tests, alle
          // "got 0"): hier stand F statt SR.Name - F ist die
          // Laufvariable der SPAETEREN for-Schleife und war waehrend
          // des Walks leer, der Filter verwarf damit JEDE Datei. Und
          // die Add-Weiche unten haette bei dlFpc eine .pp in die
          // DFM-Liste gesteckt (Ext='.pas'-Vergleich statt der
          // Unit-Frage). Lehre: eine Variablen-Ersetzung braucht die
          // umgebenden zwanzig Zeilen, nicht die eine.
          // .lpr ist bei dlFpc zwar Unit-artig fuer die SAMMLUNG, aber
          // hier gilt die Kopf-Politik ".dpr/.dpk werden nie gesammelt"
          // (die Programm-Hauptdatei kann sich nicht selbst als Orphan
          // melden) - die .lpr ist das Lazarus-Pendant zur .dpr.
          // SameText statt String-Helper: SR.Name ist TFileName, ein
          // benannter string-Typ - TStringHelper greift dort nicht
          // (E2018 im ersten Bauversuch).
          if SameText(ExtractFileExt(SR.Name), '.lpr') then Continue;
          if not (TStaticFiles.IsUnitLikeFile(SR.Name)
                  or TStaticFiles.IsFormFileName(SR.Name)) then Continue;
          Full := IncludeTrailingPathDelimiter(APath) + SR.Name;
          if Assigned(AIgnore) and AIgnore.IsIgnored(Full) then Continue;
          if TStaticFiles.IsUnitLikeFile(SR.Name) then
            DiskPas.Add(Full)
          else
            DiskDfm.Add(Full);
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
  ProjBase    := TDictionary<string, Boolean>.Create;
  UsedNames   := TDictionary<string, Boolean>.Create;
  UsedOrphans := TDictionary<string, Boolean>.Create;
  DiskPas     := TStringList.Create;
  DiskDfm     := TStringList.Create;
  Orphans     := TStringList.Create;
  try
    for i := 0 to AProjectPasList.Count - 1 do
    begin
      ProjSet.AddOrSetValue(NormKey(AProjectPasList[i]), True);
      // Basename-Set der Projektliste (Review 2026-07-30): Unit-Namen,
      // die bereits durch eine PROJEKT-Datei gedeckt sind - Namensvetter
      // im Walk-Baum sind tote Kopien und bleiben 194.
      ProjBase.AddOrSetValue(
        LowerCase(ChangeFileExt(ExtractFileName(AProjectPasList[i]), '')),
        True);
    end;

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
      // .dpk: Kompilat-Wurzel ist die contains-Klausel (uses gibt es in
      // Packages nicht) - Review 2026-07-30, vorher garantierter No-Op.
      F := ChangeFileExt(AProjectFile, '.dpk');
      if FileExists(F) then CollectUsesNames(F, UsedNames, DPK_ROOT_CLAUSE);
      // .lpr (A6/C6, 2026-09-18): das Lazarus-Programm ist die
      // uses-Wurzel eines .lpi-Scans. ANDERS als die .dpr steht die
      // .lpr normalerweise SCHON in der Projektliste (FromLpi nimmt
      // sie als Unit0 auf, IsPartOfProject=True) - dann ist diese
      // Zeile idempotent (UsedNames dedupliziert). Sie deckt den
      // Randfall .lpi ohne gelistete .lpr, damit der Rat 194/195
      // nicht am Listenzustand haengt.
      F := ChangeFileExt(AProjectFile, '.lpr');
      if FileExists(F) then CollectUsesNames(F, UsedNames);
    end;

    // Gruppen-Scan (Review 2026-07-30): die Wurzeln der MEMBER-Projekte
    // nachziehen - bei .groupproj existiert keine gleichnamige .dpr; eine
    // nur vom Member-.dpr gezogene Unit bekaeme sonst im Gruppen-Scan 194
    // ('verwaist - loeschen?') statt 195, im Einzel-Scan desselben
    // Projekts aber 195 - widerspruechlicher Rat je Scan-Modus.
    if AMemberProjects <> nil then
      for i := 0 to AMemberProjects.Count - 1 do
      begin
        F := ChangeFileExt(AMemberProjects[i], '.dpr');
        if FileExists(F) then CollectUsesNames(F, UsedNames);
        F := ChangeFileExt(AMemberProjects[i], '.dpk');
        if FileExists(F) then CollectUsesNames(F, UsedNames, DPK_ROOT_CLAUSE);
        // .lpg-Member sind .lpi/.lpk-Pfade (A6/C6) - gleiche
        // .lpr-Nachziehung wie oben, gleiche Idempotenz.
        F := ChangeFileExt(AMemberProjects[i], '.lpr');
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
        Base := LowerCase(ChangeFileExt(ExtractFileName(F), ''));
        // Namensvetter einer PROJEKT-Unit (Review 2026-07-30): der
        // Compiler kompiliert die im Projekt referenzierte Datei - die
        // Kopie hier ist tot und bleibt 194. Ohne dieses Gate kippte
        // jede stale Kopie (backup\uMain.pas) auf 195, der Fix-Rat
        // 'add it to the project' waere ein Duplicate-Unit-Konflikt,
        // und CollectUsesNames zoege ihre uses transitiv in weitere
        // 195-Fehlklassifikationen (Backup-Ordner-Kaskade).
        if ProjBase.ContainsKey(Base) then Continue;
        if UsedNames.ContainsKey(Base) then
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
      // Lazarus A4: die Schwester einer .lfm kann eine .pp sein -
      // SCHLUESSEL-Vergleich gegen die Projektliste, bewusst ohne
      // Plattenzugriff (der Detektor fragt 'im Projekt?', nicht
      // 'auf Platte?').
      if (TStaticFiles.ScanDialect = dlFpc)
         and (not ProjSet.ContainsKey(NormKey(Comp)))
         and (not UsedOrphans.ContainsKey(NormKey(Comp))) then
        Comp := ChangeFileExt(F, '.pp');
      // A5 (2026-09-17): auch das PROGRAMM kann der Formdatei-Host
      // sein - Lazarus legt die Hauptform-.lfm neben die .lpr
      // (Korpusfall examples/affinetransforms: project1.lfm +
      // project1.lpr). Ohne diese Stufe war die .lfm im .lpi-Scan
      // ein Orphan-FP des frischen A5-Pfads.
      if (TStaticFiles.ScanDialect = dlFpc)
         and (not ProjSet.ContainsKey(NormKey(Comp)))
         and (not UsedOrphans.ContainsKey(NormKey(Comp))) then
        Comp := ChangeFileExt(F, '.lpr');
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
               'project file - orphaned / dead unit?',
               fkNotIncludedInProject));
             Inc(Result);
           end;
        1: if Emit194 then
           begin
             AResults.Add(TLeakFinding.New(Orphans[i], '', 1,
               'Form file (.dfm/.lfm) is in the project folder but its unit is ' +
               'not referenced by the project file - orphaned form?',
               fkNotIncludedInProject));
             Inc(Result);
           end;
        2: if Emit195 then
           begin
             AResults.Add(TLeakFinding.New(Orphans[i], '', 1,
               'Unit is used by the project (via uses, compiled through the ' +
               'search path) but not included in the project file - ' +
               'add it to the project',
               fkUsedButNotInProject));
             Inc(Result);
           end;
        3: if Emit195 then
           begin
             AResults.Add(TLeakFinding.New(Orphans[i], '', 1,
               'Form file (.dfm/.lfm) belongs to a unit that is used by the ' +
               'project but not included in the project file - ' +
               'add the unit (and its form) to the project',
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
    ProjBase.Free;
    ProjSet.Free;
  end;
end;

end.

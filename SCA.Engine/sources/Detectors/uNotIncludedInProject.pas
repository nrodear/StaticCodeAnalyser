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
    //   verwaister Datei ein fkNotIncludedInProject-Finding an AResults
    //   (nach Pfad sortiert). Liefert die Anzahl der Funde.
    class function Detect(AProjectPasList: TStringList;
      const AWalkRoot: string;
      AResults: TObjectList<TLeakFinding>;
      AIgnore: TIgnoreList = nil): Integer; static;
  end;

implementation

uses
  System.IOUtils;

const
  // Wie TStaticFiles.EXCLUDED_DIRS - bewusst dupliziert, damit dieser
  // Ein-Mal-pro-Projektscan-Walk den perf-kritischen *.pas-Scanner nicht
  // anfasst. Bei Aenderungen dort hier mitziehen.
  EXCLUDED_DIRS : array[0..6] of string =
    ('.', '..', '__recovery', '__history', '.git', '.svn', 'node_modules');
  MAX_DEPTH     = 32;
  MAX_WALK_FILES = 20000;   // Cap analog TStaticAnalyzer2/uIDEAnalyseRunner

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
  AResults: TObjectList<TLeakFinding>; AIgnore: TIgnoreList): Integer;
var
  ProjSet  : TDictionary<string, Boolean>;
  DiskPas  : TStringList;
  DiskDfm  : TStringList;
  Orphans  : TStringList;
  F, Comp  : string;
  i        : Integer;
  Aborted  : Boolean;

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

  ProjSet := TDictionary<string, Boolean>.Create;
  DiskPas := TStringList.Create;
  DiskDfm := TStringList.Create;
  Orphans := TStringList.Create;
  try
    for i := 0 to AProjectPasList.Count - 1 do
      ProjSet.AddOrSetValue(NormKey(AProjectPasList[i]), True);

    Aborted := False;
    Walk(AWalkRoot, 0);

    // Verwaiste .pas: auf Platte, aber nicht im Projekt.
    for F in DiskPas do
      if not ProjSet.ContainsKey(NormKey(F)) then
        Orphans.AddObject(F, TObject(0));   // Tag 0 = .pas

    // Verwaiste .dfm: die gleichnamige .pas ist nicht im Projekt (ein .dfm,
    // dessen .pas referenziert ist, gehoert als Companion dazu).
    for F in DiskDfm do
    begin
      Comp := ChangeFileExt(F, '.pas');
      if not ProjSet.ContainsKey(NormKey(Comp)) then
        Orphans.AddObject(F, TObject(1));   // Tag 1 = .dfm
    end;

    // DETERMINISTISCHE Ausgabe: nach Pfad sortieren (FindFirst-Reihenfolge
    // ist FS-abhaengig -> sonst nicht byte-stabil). Die Object-Tags wandern
    // beim Sort mit, sodass die passende Message erhalten bleibt.
    Orphans.CaseSensitive := False;
    Orphans.Sort;

    for i := 0 to Orphans.Count - 1 do
    begin
      if IntPtr(Orphans.Objects[i]) = 1 then
        AResults.Add(TLeakFinding.New(Orphans[i], '', 1,
          'Form file (.dfm) is in the project folder but its unit is not ' +
          'referenced by the project (.dproj/.groupproj) - orphaned form?',
          fkNotIncludedInProject))
      else
        AResults.Add(TLeakFinding.New(Orphans[i], '', 1,
          'Source file is in the project folder but not referenced by the ' +
          'project (.dproj/.groupproj) - orphaned / dead unit?',
          fkNotIncludedInProject));
      Inc(Result);
    end;
  finally
    Orphans.Free;
    DiskDfm.Free;
    DiskPas.Free;
    ProjSet.Free;
  end;
end;

end.

unit uStaticFiles;

interface

uses
  System.SysUtils, System.Classes, System.Masks, System.IOUtils,
  uIgnoreList;

type
  // Periodisch waehrend des Scans aufgerufen. Argument: bislang gefundene Datei-Anzahl.
  // Der Aufrufer kann hier Application.ProcessMessages machen oder Abort
  // (-> EAbort) ausloesen, wenn der User die Suche abbrechen will.
  TScanTickProc = reference to procedure(FilesFound: Integer);

  TStaticFiles = class
    class function GetAllPasFilesRecursive(const Path: string)
      : TStringList; static;

    // Wie GetAllPasFilesRecursive, aber Fehler kommen als out-Parameter zurueck
    // statt eine Exception auszuloesen. ATick (optional) wird etwa alle 100
    // gefundenen Eintraege aufgerufen - praktisch fuer UI-Responsivitaet bei
    // grossen Verzeichnis-Baeumen. AIgnore (optional) filtert Dateien
    // vor dem Hinzufuegen zur Ergebnisliste.
    class function TryGetAllPasFiles(const Path: string;
      out ErrorMsg: string;
      ATick: TScanTickProc = nil;
      AIgnore: TIgnoreList = nil): TStringList; static;

    class function ValidatePath(const Path: string): boolean;

    // Walked von AFilePath aus die Verzeichnishierarchie nach oben und
    // liefert das erste Verzeichnis das eine `.dproj`, `.dpk` oder
    // `.dpr` enthaelt. Wenn nichts gefunden wird: ExtractFilePath(AFilePath)
    // als pragmatischer Fallback (mindestens das eigene Verzeichnis).
    // Der Search-Stop bei `.git`/`.svn` faengt Repos ohne Delphi-Projekt-
    // datei (z.B. einzelne `.pas` in einem Git-Repo) ab.
    class function FindProjectRoot(const AFilePath: string): string; static;
  private
    // ALogSkip (optional): wird pro uebersprungener Datei/Verzeichnis mit
    // einem klartext-Grund aufgerufen. Geht in StaticCodeAnalyser_scan.log
    // damit "warum ist datei X nicht im Scan-Output" diagnostizierbar wird,
    // ohne den Errors-Channel zu fluten (der landet im UI-Grid).
    class procedure ScanRec(const Path: string; List: TStringList;
      Depth: Integer; Errors: TStringList; ATick: TScanTickProc;
      AIgnore: TIgnoreList;
      var TickCounter: Integer;
      ALogSkip: TProc<string> = nil); static;
  end;

implementation

// noinspection-file EmptyExcept, ExceptOnException
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  MAX_DEPTH       = 32;   // Schutz vor Symlink-Endlosschleifen
  EXCLUDED_DIRS  : array[0..6] of string = (
    '.', '..',
    '__recovery', '__history',
    '.git', '.svn', 'node_modules'
  );

class procedure TStaticFiles.ScanRec(const Path: string; List: TStringList;
  Depth: Integer; Errors: TStringList; ATick: TScanTickProc;
  AIgnore: TIgnoreList;
  var TickCounter: Integer;
  ALogSkip: TProc<string> = nil);

  procedure LogSkip(const S: string);
  begin
    if Assigned(ALogSkip) then
      try ALogSkip(S); except end;
  end;
const
  // Tick-Callback nach so vielen verarbeiteten Eintraegen.
  // Klein genug, damit auch kleine Verzeichnisse Cancel zulassen, aber nicht
  // pro Eintrag um nicht von ProcessMessages-Overhead aufgefressen zu werden.
  TICK_EVERY = 25;
var
  SearchRec : TSearchRec;
  FullPath  : string;
  IsDir     : Boolean;
  Excluded  : Boolean;
begin
  if Depth > MAX_DEPTH then
  begin
    if Assigned(Errors) then
      Errors.Add(Format('Maximale Verzeichnistiefe erreicht: %s', [Path]));
    Exit;
  end;

  try
    if FindFirst(IncludeTrailingPathDelimiter(Path) + '*.*', faAnyFile,
                 SearchRec) <> 0 then
      Exit;
  except
    on E: Exception do
    begin
      if Assigned(Errors) then
        Errors.Add(Format('Verzeichnis nicht lesbar: %s (%s)',
                          [Path, E.Message]));
      Exit;
    end;
  end;

  try
    repeat
      try
        IsDir := (SearchRec.Attr and faDirectory) <> 0;

        if not IsDir then
        begin
          // Symlinks fuer Dateien skippen (faSymLink ist gesetzt)
          {$WARN SYMBOL_PLATFORM OFF}
          if (SearchRec.Attr and faSymLink) <> 0 then
          begin
            LogSkip('Skip (Symlink-Datei): ' +
                    IncludeTrailingPathDelimiter(Path) + SearchRec.Name);
            Continue;
          end;
          {$WARN SYMBOL_PLATFORM ON}
          if MatchesMask(SearchRec.Name, '*.pas') then
          begin
            FullPath := IncludeTrailingPathDelimiter(Path) + SearchRec.Name;
            // Benutzer-Ignore-Liste: Datei wird stillschweigend uebersprungen.
            // Frueher landete "Ignoriert: ..." in Errors und damit als
            // FileError-Befund im Grid - mit dem Test-Filter wuerden hunderte
            // Zeilen Laerm produziert. Stattdessen via ALogSkip nur ins
            // scan.log - sichtbar fuer Diagnose, keine UI-Findings.
            if Assigned(AIgnore) and AIgnore.IsIgnored(FullPath) then
            begin
              LogSkip(Format('Ignoriert (Datei via ignore.txt): %s',
                             [FullPath]));
              Continue;
            end;
            List.Add(FullPath);
          end;
        end
        else
        begin
          // Ausgeschlossene Verzeichnisse (.git, __history etc.)
          Excluded := False;
          for var Ex in EXCLUDED_DIRS do
            if SameText(SearchRec.Name, Ex) then
            begin
              Excluded := True;
              Break;
            end;
          if Excluded then
          begin
            // '.' und '..' nicht loggen (jeder Ordner hat die) - sonst spammt
            // jeder besuchte Unterordner zwei "Ausgeschlossen"-Zeilen.
            if (SearchRec.Name <> '.') and (SearchRec.Name <> '..') then
              LogSkip(Format('Ausgeschlossen (Default-Verzeichnis): %s',
                [IncludeTrailingPathDelimiter(Path) + SearchRec.Name]));
            Continue;
          end;
          // Symlinks fuer Verzeichnisse skippen (Endlosschleifen-Schutz)
          {$WARN SYMBOL_PLATFORM OFF}
          if (SearchRec.Attr and faSymLink) <> 0 then
          begin
            LogSkip('Skip (Symlink-Verzeichnis): ' +
                    IncludeTrailingPathDelimiter(Path) + SearchRec.Name);
            Continue;
          end;
          {$WARN SYMBOL_PLATFORM ON}

          FullPath := IncludeTrailingPathDelimiter(Path) + SearchRec.Name;
          // Verzeichnis-Ignore (z.B. "tests/"): Unterbaum komplett ueberspringen
          if Assigned(AIgnore) and AIgnore.IsIgnored(FullPath + '/dummy.pas') then
          begin
            LogSkip(Format('Ignoriert (Verzeichnis via ignore.txt): %s',
                           [FullPath]));
            Continue;
          end;
          ScanRec(FullPath, List, Depth + 1, Errors, ATick, AIgnore,
                  TickCounter, ALogSkip);
        end;

        // Tick-Callback fuer UI-Responsivitaet/Cancel.
        // EAbort soll nicht abgefangen werden - sondern den Scan beenden.
        Inc(TickCounter);
        if (TickCounter mod TICK_EVERY = 0) and Assigned(ATick) then
          ATick(List.Count);
      except
        on EAbort do raise; // Abbruch durch Tick-Callback
        on E: Exception do
        begin
          if Assigned(Errors) then
            Errors.Add(Format('Fehler bei "%s": %s',
                              [SearchRec.Name, E.Message]));
        end;
      end;
    until FindNext(SearchRec) <> 0;
  finally
    FindClose(SearchRec);
  end;
end;

class function TStaticFiles.GetAllPasFilesRecursive(const Path: string)
  : TStringList;
// Alte API – wirft keine Exception mehr, gibt aber leere Liste bei Fehler zurueck.
var
  TickCounter: Integer;
begin
  Result := TStringList.Create;
  TickCounter := 0;
  try
    if (Path = '') or not DirectoryExists(Path) then Exit;
    ScanRec(Path, Result, 0, nil, nil, nil, TickCounter);
  except
    // Niemals wirft: Result bleibt entweder leer oder enthaelt
    // bereits gefundene Dateien.
  end;
end;

class function TStaticFiles.TryGetAllPasFiles(const Path: string;
  out ErrorMsg: string;
  ATick: TScanTickProc;
  AIgnore: TIgnoreList): TStringList;
// Neue API: gibt Fehler explizit zurueck, damit Caller informieren kann.
// ATick wird waehrend des Scans periodisch aufgerufen - Aufrufer kann
// dort ProcessMessages machen oder per Abort den Scan abbrechen.
//
// Diagnose: Schreibt eine Log-Datei nach
// %APPDATA%\StaticCodeAnalyser\StaticCodeAnalyser_scan.log
// mit allen betretenen Verzeichnissen und ggf. Fehlern. Hilft bei Reports
// von "Scan haengt bei N Dateien". Pfad kommt aus TIgnoreList.LogFilePath
// (selbes Verzeichnis wie ignore.txt).
var
  Errors      : TStringList;
  TickCounter : Integer;
  LogPath     : string;
  LogStream   : TStreamWriter;

  procedure Log(const S: string);
  begin
    if Assigned(LogStream) then
      try LogStream.WriteLine(S); except end;
  end;

begin
  // nil-init damit bei OOM waehrend zweiter Allokation die erste nicht leakt;
  // .Free ist nil-safe und das finally raeumt auf egal wo wir abbrechen.
  Result      := nil;
  Errors      := nil;
  LogStream   := nil;
  ErrorMsg    := '';
  TickCounter := 0;
  // Log liegt im selben Verzeichnis wie die Ignore-Liste (=ConfigDir).
  // Verzeichnis ggf. anlegen, sonst scheitert TStreamWriter.Create.
  LogPath := TIgnoreList.LogFilePath;
  try
    if not DirectoryExists(TIgnoreList.ConfigDir) then
      ForceDirectories(TIgnoreList.ConfigDir);
  except
    // bei Berechtigungsproblem: Log einfach unterdruecken
  end;
  try
    Result := TStringList.Create;
    Errors := TStringList.Create;
    try
      LogStream := TStreamWriter.Create(LogPath, False, TEncoding.UTF8);
      Log('=== Scan gestartet: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)
          + ' Pfad: ' + Path + ' ===');
    except
      // Log-Datei optional - kein Hard-Fail. FreeAndNil statt nil-Zuweisung,
      // sonst leakt der StreamWriter falls Create klappt aber das erste Log()
      // wirft (z.B. disk full).
      FreeAndNil(LogStream);
    end;

    if Path = '' then
    begin
      ErrorMsg := 'Kein Pfad angegeben';
      Exit;
    end;
    if not DirectoryExists(Path) then
    begin
      ErrorMsg := Format('Verzeichnis nicht gefunden: %s', [Path]);
      Log('ABBRUCH: ' + ErrorMsg);
      Exit;
    end;
    try
      if Assigned(AIgnore) then
        Log(Format('Ignore-Liste aktiv: %d Muster aus %s',
                   [AIgnore.PatternCount, AIgnore.ConfigFilePath]));
      // ALogSkip-Callback: ScanRec ruft das pro skip-event (Ignore/Excluded
      // /Symlink). Capture LogStream direkt - nested procs (Log) sind in
      // anonymous methods nicht referenzierbar (E2555).
      var CaptStream := LogStream;
      ScanRec(Path, Result, 0, Errors, ATick, AIgnore, TickCounter,
        procedure(S: string)
        begin
          if Assigned(CaptStream) then
            try CaptStream.WriteLine(S); except end;
        end);
      Log(Format('=== Scan fertig: %d Dateien, %d Eintraege gepruft ===',
                 [Result.Count, TickCounter]));
    except
      on EAbort do
      begin
        Log('ABBRUCH durch User');
        FreeAndNil(Result);
        raise;
      end;
      on E: Exception do
      begin
        ErrorMsg := 'Unerwarteter Fehler: ' + E.Message;
        Log('AUSNAHME: ' + E.ClassName + ': ' + E.Message);
      end;
    end;
    if Errors.Count > 0 then
    begin
      ErrorMsg := Errors.Text;
      Log('--- Fehler waehrend Scan ---');
      Log(Errors.Text);
    end;
  finally
    Errors.Free;
    if Assigned(LogStream) then
      LogStream.Free;
  end;
end;

class function TStaticFiles.ValidatePath(const Path: string): boolean;
begin
  if Path = '' then Exit(False);
  try
    Result := DirectoryExists(Path) or FileExists(Path);
  except
    Result := False;
  end;
end;

class function TStaticFiles.FindProjectRoot(const AFilePath: string): string;

  function HasProjectFile(const Dir: string): Boolean;
  var
    SR : TSearchRec;
  begin
    Result := False;
    if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*.dproj', faAnyFile, SR) = 0 then
    begin
      FindClose(SR);
      Exit(True);
    end;
    if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*.dpk', faAnyFile, SR) = 0 then
    begin
      FindClose(SR);
      Exit(True);
    end;
    if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*.dpr', faAnyFile, SR) = 0 then
    begin
      FindClose(SR);
      Exit(True);
    end;
  end;

  function IsVcsRoot(const Dir: string): Boolean;
  begin
    Result := DirectoryExists(IncludeTrailingPathDelimiter(Dir) + '.git')
           or DirectoryExists(IncludeTrailingPathDelimiter(Dir) + '.svn')
           or DirectoryExists(IncludeTrailingPathDelimiter(Dir) + '.hg');
  end;

var
  Dir, Parent, Fallback : string;
  Steps : Integer;
begin
  Fallback := ExtractFilePath(AFilePath);
  Result := Fallback;
  if Fallback = '' then Exit;
  Dir := ExcludeTrailingPathDelimiter(Fallback);
  // Maximal 12 Ebenen aufsteigen - schuetzt vor Endlos-Loop bei kaputten
  // UNC-Pfaden / Sym-Link-Zyklen.
  Steps := 0;
  while (Dir <> '') and (Steps < 12) do
  begin
    if HasProjectFile(Dir) then Exit(IncludeTrailingPathDelimiter(Dir));
    if IsVcsRoot(Dir) then Exit(IncludeTrailingPathDelimiter(Dir));
    Parent := ExtractFileDir(Dir);
    if (Parent = '') or (Parent = Dir) then Break;  // root reached
    Dir := Parent;
    Inc(Steps);
  end;
  Result := Fallback;
end;

end.

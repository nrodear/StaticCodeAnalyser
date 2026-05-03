unit uVcsChanges;

// Ermittelt geaenderte .pas-Dateien aus einem VCS-Repository (Git oder SVN).
//
// Workflow:
//   1. Repo-Root nach oben suchen (.git fuer Git, .svn fuer SVN)
//   2. Je nach VCS unterschiedliche Befehle:
//      Git:
//        - 'git diff --name-only --diff-filter=ACMR <base>...HEAD'
//          (committed Branch-Diff vs main/master)
//        - 'git status --porcelain' (uncommitted Working Tree)
//      SVN:
//        - 'svn status' (uncommitted Working Copy + unversioned)
//   3. Filter auf .pas, deleted skippen, absolute Pfade
//
// Verwendet CreateProcess mit Pipe um stdout abzugreifen - kein Console-Fenster,
// keine Tempdateien.

interface

uses
  System.Classes, System.SysUtils,
  uRepoSettings;

type
  TVcsKind = (vkNone, vkGit, vkSvn);

  TVcsChanges = class
  public
    // Sucht .git oder .svn Verzeichnis ausgehend von APath nach oben.
    // Returnt Root-Pfad und VCS-Typ. AKind=vkNone wenn nichts gefunden.
    class function DetectRepo(const APath: string;
      out AKind: TVcsKind): string; static;

    // Liefert alle geaenderten .pas-Dateien. AInfo enthaelt einen kurzen
    // Status-Text fuer die UI ("Git Branch vs main", "SVN Working Copy", ...).
    // ASettings (optional) ueberschreibt das Auto-Verhalten:
    //   BaseBranch, IncludeWorkingTree, GitExePath, SvnExePath.
    class function GetChangedPasFiles(const ARepoRoot: string;
      AKind: TVcsKind; out AInfo: string;
      ASettings: TRepoSettings = nil): TStringList; static;

    // Kombi-Aufruf: Detect + GetChanged in einem Schritt.
    class function GetChangedPasFilesAuto(const APath: string;
      out AInfo: string;
      ASettings: TRepoSettings = nil): TStringList; static;
  private
    // Ruft '<exe> <args>' im RepoRoot auf und gibt stdout zurueck.
    // Result True wenn Exit-Code 0 war.
    class function RunCmd(const AExe, AArgs, ACwd: string;
      out AStdOut: string; out AExitCode: Cardinal): Boolean; static;

    // Sucht das Executable: erst PATH, dann in typischen Installations-
    // pfaden inkl. TortoiseGit/TortoiseSVN. Liefert vollen Pfad oder
    // den Namen unveraendert (wird dann von CreateProcess via PATH
    // aufgeloest oder schlaegt fehl).
    class function ResolveExe(const AName: string): string; static;

    class function GetGitChanges(const ARepoRoot: string;
      ASettings: TRepoSettings; out AInfo: string): TStringList; static;
    class function GetSvnChanges(const ARepoRoot: string;
      ASettings: TRepoSettings; out AInfo: string): TStringList; static;
  end;

implementation

uses
  Winapi.Windows, System.AnsiStrings, System.IOUtils;

{ ----------------------------------------------------------------- }

class function TVcsChanges.DetectRepo(const APath: string;
  out AKind: TVcsKind): string;
var
  Dir, Parent: string;
begin
  Result := '';
  AKind  := vkNone;
  Dir := ExcludeTrailingPathDelimiter(APath);
  while (Dir <> '') and DirectoryExists(Dir) do
  begin
    if DirectoryExists(IncludeTrailingPathDelimiter(Dir) + '.git') then
    begin
      AKind := vkGit;
      Exit(Dir);
    end;
    if DirectoryExists(IncludeTrailingPathDelimiter(Dir) + '.svn') then
    begin
      AKind := vkSvn;
      Exit(Dir);
    end;
    Parent := ExtractFilePath(Dir);
    if (Parent = '') or (Parent = Dir) then Break;
    Dir := ExcludeTrailingPathDelimiter(Parent);
  end;
end;

class function TVcsChanges.ResolveExe(const AName: string): string;
// Sucht in dieser Reihenfolge:
//   1. PATH (via SearchPath WinAPI)
//   2. Bekannte Tortoise-Pfade je nach Tool-Name
//   3. Bekannte git-scm/svn-Standardpfade
// Liefert den vollen Pfad. Falls nichts gefunden wird, wird AName
// unveraendert zurueckgegeben - CreateProcess schlaegt dann mit Fehler 2 fehl.
const
  GIT_HINTS: array[0..4] of string = (
    'C:\Program Files\Git\bin\git.exe',
    'C:\Program Files (x86)\Git\bin\git.exe',
    'C:\Program Files\TortoiseGit\bin\git.exe',
    'C:\Program Files (x86)\TortoiseGit\bin\git.exe',
    'C:\Program Files\TortoiseGit\mingw64\bin\git.exe'
  );
  SVN_HINTS: array[0..3] of string = (
    'C:\Program Files\TortoiseSVN\bin\svn.exe',
    'C:\Program Files (x86)\TortoiseSVN\bin\svn.exe',
    'C:\Program Files\Subversion\bin\svn.exe',
    'C:\Program Files (x86)\Subversion\bin\svn.exe'
  );
var
  Buf       : array[0..MAX_PATH - 1] of Char;
  FilePart  : PChar;
  ExeName   : string;
  Hint      : string;
begin
  // Mit .exe-Endung suchen, sonst findet SearchPath unter Win nichts
  ExeName := AName;
  if not ExeName.ToLower.EndsWith('.exe') then
    ExeName := ExeName + '.exe';

  // ---- 1) PATH ----
  if SearchPath(nil, PChar(ExeName), nil, MAX_PATH, Buf, FilePart) > 0 then
    Exit(string(Buf));

  // ---- 2/3) Bekannte Pfade ----
  if SameText(AName, 'git') or SameText(AName, 'git.exe') then
  begin
    for Hint in GIT_HINTS do
      if FileExists(Hint) then Exit(Hint);
  end
  else if SameText(AName, 'svn') or SameText(AName, 'svn.exe') then
  begin
    for Hint in SVN_HINTS do
      if FileExists(Hint) then Exit(Hint);
  end;

  // Fallback: unveraendert zurueckgeben - CreateProcess wird mit "not found"
  // fehlschlagen und der Aufrufer kriegt ExitCode = -1.
  Result := AName;
end;

class function TVcsChanges.RunCmd(const AExe, AArgs, ACwd: string;
  out AStdOut: string; out AExitCode: Cardinal): Boolean;
var
  SecAttr   : TSecurityAttributes;
  ReadPipe  : THandle;
  WritePipe : THandle;
  StartInfo : TStartupInfo;
  ProcInfo  : TProcessInformation;
  Buf       : array[0..4095] of AnsiChar;
  BytesRead : Cardinal;
  Cmd       : string;
  SB        : TStringBuilder;
begin
  Result    := False;
  AStdOut   := '';
  AExitCode := Cardinal(-1);

  SecAttr := Default(TSecurityAttributes);
  SecAttr.nLength        := SizeOf(SecAttr);
  SecAttr.bInheritHandle := True;

  if not CreatePipe(ReadPipe, WritePipe, @SecAttr, 0) then Exit;
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);

    StartInfo := Default(TStartupInfo);
    StartInfo.cb          := SizeOf(StartInfo);
    StartInfo.dwFlags     := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    StartInfo.wShowWindow := SW_HIDE;
    StartInfo.hStdOutput  := WritePipe;
    StartInfo.hStdError   := WritePipe;
    StartInfo.hStdInput   := GetStdHandle(STD_INPUT_HANDLE);

    // Executable aufloesen (PATH oder Tortoise-Pfade) und mit Quotes
    // umgeben, weil typische Tortoise-Installationspfade Leerzeichen haben.
    var ResolvedExe := ResolveExe(AExe);
    if Pos(' ', ResolvedExe) > 0 then
      Cmd := '"' + ResolvedExe + '" ' + AArgs
    else
      Cmd := ResolvedExe + ' ' + AArgs;

    ProcInfo := Default(TProcessInformation);

    if not CreateProcess(nil, PChar(Cmd), nil, nil, True,
       CREATE_NO_WINDOW, nil, PChar(ACwd), StartInfo, ProcInfo) then
      Exit;
    try
      // Write-End im Parent schliessen, sonst blockt ReadFile auf EOF
      CloseHandle(WritePipe);
      WritePipe := 0;

      // Polling-Loop mit Gesamt-Timeout. Vorher: blockierendes ReadFile ohne
      // Timeout - haengender Prozess (z.B. git wartet auf Credentials) liess
      // den Caller ewig warten. Jetzt: PeekNamedPipe-Polling mit
      // GetTickCount-Watchdog; bei Timeout wird der Prozess geKILLT.
      const TOTAL_TIMEOUT_MS = 60 * 1000; // 60s harter Cap
      var StartTick : Cardinal := GetTickCount;
      var Available : Cardinal := 0;
      var Done      : Boolean  := False;
      var ProcStat  : Cardinal;
      var ToRead    : Cardinal;

      SB := TStringBuilder.Create;
      try
        while not Done do
        begin
          // Wieviel Bytes liegen abrufbar im Pipe-Buffer?
          if not PeekNamedPipe(ReadPipe, nil, 0, nil, @Available, nil) then
            Available := 0;

          if Available > 0 then
          begin
            ToRead := Available;
            if ToRead > SizeOf(Buf) - 1 then ToRead := SizeOf(Buf) - 1;
            if not ReadFile(ReadPipe, Buf[0], ToRead, BytesRead, nil) then
              Break;
            if BytesRead = 0 then Break;
            Buf[BytesRead] := #0;
            SB.Append(string(System.AnsiStrings.StrPas(@Buf[0])));
            // Tick zuruecksetzen: solange Daten fliessen, ist Prozess "lebendig"
            StartTick := GetTickCount;
          end
          else
          begin
            // Keine Daten verfuegbar: ist der Prozess noch am Leben?
            ProcStat := WaitForSingleObject(ProcInfo.hProcess, 0);
            if ProcStat = WAIT_OBJECT_0 then
            begin
              // Prozess fertig - finalen Pipe-Rest noch leeren
              if PeekNamedPipe(ReadPipe, nil, 0, nil, @Available, nil)
                 and (Available > 0) then
              begin
                ToRead := Available;
                if ToRead > SizeOf(Buf) - 1 then ToRead := SizeOf(Buf) - 1;
                if ReadFile(ReadPipe, Buf[0], ToRead, BytesRead, nil)
                   and (BytesRead > 0) then
                begin
                  Buf[BytesRead] := #0;
                  SB.Append(string(System.AnsiStrings.StrPas(@Buf[0])));
                end;
              end;
              Done := True;
            end
            else if GetTickCount - StartTick > TOTAL_TIMEOUT_MS then
            begin
              // Prozess haengt - hart killen, Sentinel ExitCode
              TerminateProcess(ProcInfo.hProcess, 1);
              WaitForSingleObject(ProcInfo.hProcess, 1000);
              AExitCode := Cardinal(-2); // Sentinel: Timeout
              Done      := True;
            end
            else
              Sleep(50);
          end;
        end;
        AStdOut := SB.ToString;
      finally
        SB.Free;
      end;

      // ExitCode nur dann frisch lesen wenn nicht durch Timeout vorgemerkt
      if AExitCode <> Cardinal(-2) then
        GetExitCodeProcess(ProcInfo.hProcess, AExitCode);
      Result := AExitCode = 0;
    finally
      CloseHandle(ProcInfo.hProcess);
      CloseHandle(ProcInfo.hThread);
    end;
  finally
    if WritePipe <> 0 then CloseHandle(WritePipe);
    CloseHandle(ReadPipe);
  end;
end;

{ ---- Git ---- }

class function TVcsChanges.GetGitChanges(const ARepoRoot: string;
  ASettings: TRepoSettings; out AInfo: string): TStringList;
var
  Output, Base : string;
  ExitCode     : Cardinal;
  SL           : TStringList;
  Line, Path   : string;
  Status       : string;
  pArrow       : Integer;

  procedure AddIfPas(const ARelPath: string);
  var P, T: string;
  begin
    T := Trim(ARelPath);
    if not T.ToLower.EndsWith('.pas') then Exit;
    P := IncludeTrailingPathDelimiter(ARepoRoot) + T.Replace('/', '\');
    if FileExists(P) then
      Result.Add(P);
  end;

begin
  AInfo  := '';
  Result := TStringList.Create;
  Result.Duplicates    := dupIgnore;
  Result.Sorted        := True;
  Result.CaseSensitive := False;

  // ---- Settings-Override fuer git-Pfad ----
  var GitExe := 'git';
  if Assigned(ASettings) and (ASettings.GitExePath <> '') and
     FileExists(ASettings.GitExePath) then
    GitExe := ASettings.GitExePath;

  // ---- Sanity-Check: ist git ueberhaupt aufrufbar? ----
  if not RunCmd(GitExe, '--version', ARepoRoot, Output, ExitCode) then
  begin
    AInfo := 'git nicht gefunden. Installiere Git for Windows ' +
             '(git-scm.com) oder setze in repo.ini den Pfad zu git.exe.';
    Exit;
  end;

  // ---- Base-Branch: Settings-Override oder Auto-Detect ----
  Base := '';
  if Assigned(ASettings) and (ASettings.BaseBranch <> '') then
    Base := ASettings.BaseBranch
  else if RunCmd(GitExe, 'symbolic-ref --short refs/remotes/origin/HEAD',
                 ARepoRoot, Output, ExitCode) then
    Base := Trim(Output)
  else if RunCmd(GitExe, 'rev-parse --verify --quiet main',
                 ARepoRoot, Output, ExitCode) then
    Base := 'main'
  else if RunCmd(GitExe, 'rev-parse --verify --quiet master',
                 ARepoRoot, Output, ExitCode) then
    Base := 'master';

  // ---- 1) Branch-Diff (committed) ----
  if Base <> '' then
  begin
    if RunCmd(GitExe,
       'diff --name-only --diff-filter=ACMR ' + Base + '...HEAD',
       ARepoRoot, Output, ExitCode) then
    begin
      SL := TStringList.Create;
      try
        SL.Text := Output;
        for Line in SL do
          AddIfPas(Line);
      finally
        SL.Free;
      end;
    end;
    AInfo := 'Git: Branch vs ' + Base;
  end
  else
    AInfo := 'Git: kein Base-Branch - nur Working Tree';

  // ---- 2) Working Tree - nur wenn Settings es zulassen ----
  var IncludeWT := True;
  if Assigned(ASettings) then
    IncludeWT := ASettings.IncludeWorkingTree;
  if not IncludeWT then Exit;

  if RunCmd(GitExe, 'status --porcelain', ARepoRoot, Output, ExitCode) then
  begin
    SL := TStringList.Create;
    try
      SL.Text := Output;
      for Line in SL do
      begin
        if Length(Line) < 4 then Continue;
        Status := Copy(Line, 1, 2);
        Path   := Copy(Line, 4, MaxInt);

        // 'D' (deleted) skippen - File existiert nicht mehr
        if (Status[1] = 'D') or (Status[2] = 'D') then Continue;

        // Rename: 'R  old -> new' - nur Ziel-Pfad nehmen
        pArrow := Pos(' -> ', Path);
        if pArrow > 0 then
          Path := Copy(Path, pArrow + 4, MaxInt);

        // Quotes entfernen (Pfade mit Sonderzeichen)
        if (Length(Path) >= 2) and (Path[1] = '"') and
           (Path[Length(Path)] = '"') then
          Path := Copy(Path, 2, Length(Path) - 2);

        AddIfPas(Path);
      end;
    finally
      SL.Free;
    end;
  end;
end;

{ ---- SVN ---- }

class function TVcsChanges.GetSvnChanges(const ARepoRoot: string;
  ASettings: TRepoSettings; out AInfo: string): TStringList;
// SVN hat kein Branch-Diff-Konzept wie Git (Branches sind Repository-Kopien).
// Wir liefern nur Working-Copy-Aenderungen via 'svn status'.
//
// Status-Output Format:
//   M       path/to/file.pas
//   A       path/to/added.pas
//   ?       unversioned/file.pas
//   D       deleted/file.pas      <- skippen
//   !       missing/file.pas      <- skippen
//
// Spalte 1 = file modification status; danach 6 weitere Spalten fuer
// Properties/Lock/usw. Pfad ab Spalte 8.
var
  Output     : string;
  ExitCode   : Cardinal;
  SL         : TStringList;
  Line, Path : string;
  StatChar   : Char;

  procedure AddIfPas(const ARelPath: string);
  var P, T: string;
  begin
    T := Trim(ARelPath);
    if not T.ToLower.EndsWith('.pas') then Exit;
    // svn liefert i.d.R. relative Pfade mit Backslash unter Windows
    if TPath.IsPathRooted(T) then
      P := T
    else
      P := IncludeTrailingPathDelimiter(ARepoRoot) + T.Replace('/', '\');
    if FileExists(P) then
      Result.Add(P);
  end;

begin
  AInfo  := 'SVN: Working Copy';
  Result := TStringList.Create;
  Result.Duplicates    := dupIgnore;
  Result.Sorted        := True;
  Result.CaseSensitive := False;

  // ---- Settings-Override fuer svn-Pfad ----
  var SvnExe := 'svn';
  if Assigned(ASettings) and (ASettings.SvnExePath <> '') and
     FileExists(ASettings.SvnExePath) then
    SvnExe := ASettings.SvnExePath;

  // ---- Sanity-Check: ist svn aufrufbar? ----
  // TortoiseSVN braucht die Option "command line client tools" beim Install.
  if not RunCmd(SvnExe, '--version --quiet', ARepoRoot, Output, ExitCode) then
  begin
    AInfo := 'svn nicht gefunden. Installiere TortoiseSVN MIT der Option ' +
             '"command line client tools" oder setze in repo.ini den Pfad zu svn.exe.';
    Exit;
  end;

  if not RunCmd(SvnExe, 'status', ARepoRoot, Output, ExitCode) then
  begin
    AInfo := 'SVN-Aufruf fehlgeschlagen (ExitCode=' + IntToStr(ExitCode) + ')';
    Exit;
  end;

  SL := TStringList.Create;
  try
    SL.Text := Output;
    for Line in SL do
    begin
      if Length(Line) < 8 then Continue;
      StatChar := Line[1];

      // 'D' (deleted), '!' (missing), 'I' (ignored), 'C' (conflict) skippen
      if CharInSet(StatChar, ['D', '!', 'I', 'C', ' ']) then
      begin
        // 'C' (Conflict) auch raus weil Datei evtl. nicht parsbar.
        // ' ' = unmodified - fuer Property-Aenderungen aber nicht inhaltlich.
        Continue;
      end;

      // Akzeptieren: M (modified), A (added), R (replaced), ? (unversioned),
      // X (external), ~ (versioned/obstructed)
      if not CharInSet(StatChar, ['M', 'A', 'R', '?']) then Continue;

      Path := Copy(Line, 8, MaxInt);
      AddIfPas(Path);
    end;
  finally
    SL.Free;
  end;
end;

{ ---- Public API ---- }

class function TVcsChanges.GetChangedPasFiles(const ARepoRoot: string;
  AKind: TVcsKind; out AInfo: string;
  ASettings: TRepoSettings): TStringList;
begin
  case AKind of
    vkGit : Result := GetGitChanges(ARepoRoot, ASettings, AInfo);
    vkSvn : Result := GetSvnChanges(ARepoRoot, ASettings, AInfo);
  else
    Result := TStringList.Create;
    AInfo  := 'Kein VCS erkannt';
  end;
end;

class function TVcsChanges.GetChangedPasFilesAuto(const APath: string;
  out AInfo: string;
  ASettings: TRepoSettings): TStringList;
var
  Root : string;
  Kind : TVcsKind;
begin
  Root := DetectRepo(APath, Kind);
  if Kind = vkNone then
  begin
    Result := TStringList.Create;
    AInfo  := 'Kein Git-/SVN-Repository in oder oberhalb von "' + APath + '"';
    Exit;
  end;
  Result := GetChangedPasFiles(Root, Kind, AInfo, ASettings);
end;

end.

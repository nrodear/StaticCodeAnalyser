program SCA.CLI.Demo;

{$APPTYPE CONSOLE}

// =============================================================================
// SCA CLI Demo - minimaler Beispiel-Consumer der SCA-Engine-API.
//
// Zweck: zeigen, dass die komplette Analyse ueber die oeffentliche Facade
// uEngineApi nutzbar ist. Dieses Projekt referenziert AUSSCHLIESSLICH das
// Laufzeit-Package SCA.Engine (DCC_UsePackage) - KEINE Engine-Quelltexte
// liegen im Suchpfad. Es scannt ein Verzeichnis rekursiv und gibt eine
// Kennwert-Statistik aus (sonst nichts).
//
// Aufruf:  SCA.CLI.Demo.exe [<Pfad>] [<Profil>]
//   <Pfad>    Wurzelverzeichnis (Default: aktuelles Verzeichnis)
//   <Profil>  optional - '' = alle Detektoren (Default). Bekannte Profile:
//             default, strict, ide-fast, security, bugs-only,
//             code-quality, dfm-only
//
// Exit-Code (wie der CLI): 0 = sauber, 3 = Funde vorhanden, 1/2 = Fehler.
// =============================================================================

uses
  System.SysUtils,
  System.Diagnostics,
  System.Generics.Collections,
  uEngineApi,   // <- die EINZIGE SCA-API, die der Consumer direkt aufruft
  uMethodd12,   // TLeakFinding (Findings-Liste durchlaufen)
  uSCAConsts;   // TFindingType + ftXxx (Kategorie-Enum)

type
  // Aggregierte Kennwerte eines Laufs.
  TStat = record
    Files    : Integer;                          // distinkte Dateien mit Funden
    Total    : Integer;                          // Funde gesamt
    Errors   : Integer;                          // Schweregrad Fehler
    Warnings : Integer;                          // Schweregrad Warnung
    Hints    : Integer;                          // Schweregrad Hinweis
    ByType   : array[TFindingType] of Integer;   // Funde je Kategorie
  end;

function TypeLabel(T: TFindingType): string;
begin
  case T of
    ftBug:             Result := 'Bug';
    ftCodeSmell:       Result := 'Code Smell';
    ftVulnerability:   Result := 'Vulnerability';
    ftSecurityHotspot: Result := 'Security Hotspot';
    ftCodeDuplication: Result := 'Duplication';
    ftFileError:       Result := 'File Error';
  else                 Result := '?';
  end;
end;

procedure CollectStats(Res: TScanResult; out S: TStat);
var
  F     : TLeakFinding;
  Files : TDictionary<string, Byte>;
begin
  FillChar(S, SizeOf(S), 0);
  // Schweregrad-Kennwerte direkt aus der Facade.
  S.Total    := Res.FindingCount;
  S.Errors   := Res.ErrorCount;
  S.Warnings := Res.WarningCount;
  S.Hints    := Res.HintCount;

  // Kategorie + distinkte Dateien durch einmaliges Durchlaufen der Findings.
  Files := TDictionary<string, Byte>.Create;
  try
    for F in Res.Findings do
    begin
      Inc(S.ByType[F.FindingType]);
      if (F.FileName <> '') and not Files.ContainsKey(F.FileName) then
        Files.Add(F.FileName, 0);
    end;
    S.Files := Files.Count;
  finally
    Files.Free;
  end;
end;

procedure PrintReport(const APath, AProfile: string; ElapsedMs: Int64;
  const S: TStat);
var
  T : TFindingType;
begin
  WriteLn('========================================================');
  WriteLn(' SCA CLI Demo - Kennwert-Statistik');
  WriteLn('========================================================');
  WriteLn(Format('  Pfad         : %s', [APath]));
  if AProfile = '' then
    WriteLn('  Profil       : (alle Detektoren)')
  else
    WriteLn(Format('  Profil       : %s', [AProfile]));
  WriteLn(Format('  Dauer        : %d ms', [ElapsedMs]));
  WriteLn(Format('  Dateien      : %d (mit Funden)', [S.Files]));
  WriteLn('--------------------------------------------------------');
  WriteLn(Format('  Funde gesamt : %d', [S.Total]));
  WriteLn('');
  WriteLn('  Nach Schweregrad:');
  WriteLn(Format('    Fehler  (Error)  : %d', [S.Errors]));
  WriteLn(Format('    Warnung (Warning): %d', [S.Warnings]));
  WriteLn(Format('    Hinweis (Hint)   : %d', [S.Hints]));
  WriteLn('');
  WriteLn('  Nach Kategorie:');
  for T := Low(TFindingType) to High(TFindingType) do
    WriteLn(Format('    %-17s: %d', [TypeLabel(T), S.ByType[T]]));
  WriteLn('========================================================');
end;

var
  Path    : string;
  Profile : string;
  Res     : TScanResult;
  SW      : TStopwatch;
  Stat    : TStat;
begin
  try
    if ParamCount >= 1 then Path := ParamStr(1) else Path := GetCurrentDir;
    if ParamCount >= 2 then Profile := ParamStr(2) else Profile := '';

    if not DirectoryExists(Path) then
    begin
      WriteLn('Verzeichnis nicht gefunden: ', Path);
      ExitCode := 2;
      Exit;
    end;

    WriteLn('Scanne ', Path, ' ...');
    SW := TStopwatch.StartNew;
    // Die komplette Engine in einer Zeile. (Fuer mehr Kontrolle gaebe es
    // TScanRequest.Init + TAnalysisSession.Run - hier reicht der Convenience-
    // Einzeiler, der intern genau das macht.)
    Res := ScanRecursive(Path, Profile);
    try
      SW.Stop;
      CollectStats(Res, Stat);
      PrintReport(Path, Profile, SW.ElapsedMilliseconds, Stat);
    finally
      Res.Free;
    end;

    if Stat.Total > 0 then ExitCode := 3 else ExitCode := 0;
  except
    on E: Exception do
    begin
      WriteLn('Fehler: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.

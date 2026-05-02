unit uStaticAnalyzer2;

interface

uses
  System.Generics.Collections, System.Generics.Defaults,
  System.SysUtils, System.Classes,
  uSCAConsts, uMethodd12, uIgnoreList;

type
  TStaticAnalyzer2 = class
    // Uses-Häufigkeit: liefert sortierte "N  UnitName"-Zeilen
    class function Analyze(const FileName: string): TStringList;
    class function AnalyzeRecursive(const Path: string): TStringList;

    // Speicherleck-Analyse (AST-basiert)
    class function AnalyzeLeaks(const FileName: string;
      AIncludeUsesCheck: Boolean = False): TObjectList<TLeakFinding>;
    class function AnalyzeLeaksRecursive(const Path: string;
      AProgress: TProc<Integer, Integer> = nil;
      AIncludeUsesCheck: Boolean = False;
      AIgnore: TIgnoreList = nil): TObjectList<TLeakFinding>;

    // Analysiert eine bereits ermittelte Datei-Liste (z.B. aus VCS-Diff).
    // Nimmt KEINE Ownership der Liste, kopiert sie intern.
    class function AnalyzeLeaksFromList(AFiles: TStringList;
      AProgress: TProc<Integer, Integer> = nil;
      AIncludeUsesCheck: Boolean = False): TObjectList<TLeakFinding>;

  private
    class procedure ParseFiles(FileList: TStringList; var Results: TStringList);
    class procedure ParseLeaks(FileList: TStringList;
      Results: TObjectList<TLeakFinding>;
      AProgress: TProc<Integer, Integer>;
      AIncludeUsesCheck: Boolean);
  end;

implementation

uses
  System.IOUtils, System.Diagnostics,
  uStaticFiles, uParser2, uAstNode,
  uLeakDetector2, uCodeSmells2, uSQLInjection, uHardcodedSecret,
  uFormatMismatch, uUnusedUses,
  uNilDeref, uMissingFinally, uDivByZero, uDeadCode,
  uLongMethod, uLongParamList, uMagicNumbers, uDuplicateString,
  uHardcodedPath, uDebugOutput, uDeepNesting,
  uTodoComment, uEmptyMethod, uFieldLeak, uDuplicateBlock,
  uSuppression;

{ Zählt uses-Items über alle Dateien und liefert Top-N sortiert. }

class procedure TStaticAnalyzer2.ParseFiles(FileList: TStringList;
  var Results: TStringList);
var
  Parser     : TParser2;
  NameCounts : TDictionary<string, Integer>;
  Root       : TAstNode;
  UsesList   : TList<TAstNode>;
  UsesNode   : TAstNode;
  Item       : TAstNode;
  FileName   : string;
  i          : Integer;
  Pairs      : TArray<TPair<string, Integer>>;
  Pair       : TPair<string, Integer>;
begin
  Parser     := TParser2.Create;
  NameCounts := TDictionary<string, Integer>.Create;
  try
    for i := 0 to FileList.Count - 1 do
    begin
      FileName := FileList[i];
      try
        Root := Parser.ParseFile(FileName);
      except
        on E: Exception do
        begin
          Results.Add('ERROR ' + FileName + ': ' + E.Message);
          Continue;
        end;
      end;

      try
        // Alle uses-Klauseln im Baum finden (interface + implementation)
        UsesList := Root.FindAll(nkUses);
        try
          for UsesNode in UsesList do
            for Item in UsesNode.Children do
              if Item.Kind = nkUsesItem then
              begin
                if NameCounts.ContainsKey(Item.Name) then
                  NameCounts[Item.Name] := NameCounts[Item.Name] + 1
                else
                  NameCounts.Add(Item.Name, 1);
              end;
        finally
          UsesList.Free;
        end;
      finally
        Root.Free;
      end;
    end;

    // Absteigend nach Häufigkeit sortieren
    Pairs := NameCounts.ToArray;
    TArray.Sort<TPair<string, Integer>>(Pairs,
      TComparer<TPair<string, Integer>>.Construct(
        function(const A, B: TPair<string, Integer>): Integer
        begin
          Result := B.Value - A.Value;
        end));

    for Pair in Pairs do
      Results.Add(Format('%d  %s', [Pair.Value, Pair.Key]));
  finally
    Parser.Free;
    NameCounts.Free;
  end;
end;

class procedure TStaticAnalyzer2.ParseLeaks(FileList: TStringList;
  Results: TObjectList<TLeakFinding>; AProgress: TProc<Integer, Integer>;
  AIncludeUsesCheck: Boolean);
const
  MAX_FILE_BYTES = 5 * 1024 * 1024; // 5 MB – größere Dateien überspringen

  procedure AddFileError(const AFileName, AMsg: string);
  var F: TLeakFinding;
  begin
    F            := TLeakFinding.Create;
    F.FileName   := AFileName;
    F.MethodName := '';
    F.LineNumber := '0';
    F.MissingVar := AMsg;
    F.Severity   := lsError;
    F.Kind       := fkFileReadError;
    Results.Add(F);
  end;

  procedure SafeProgress(Current, Total: Integer);
  begin
    if not Assigned(AProgress) then Exit;
    try
      AProgress(Current, Total);
    except
      on EAbort do raise; // User-Cancel muss durchgereicht werden!
      // andere Callback-Exceptions duerfen die Analyse nicht abbrechen
    end;
  end;

var
  Parser    : TParser2;
  Root      : TAstNode;
  FileName  : string;
  FileSize  : Int64;
  i, Total  : Integer;
  LogPath   : string;
  LogStream : TStreamWriter;
  Watch     : TStopwatch;
  ElapsedMs : Int64;

  procedure LogLine(const S: string);
  begin
    if Assigned(LogStream) then
      try LogStream.WriteLine(S); LogStream.Flush; except end;
  end;

begin
  if (FileList = nil) or (Results = nil) then Exit;

  // Log-Datei zur Diagnose: zeigt pro Datei welcher Schritt wie lange dauert.
  // Bei "App haengt" laesst sich daraus ablesen welche Datei der Uebeltaeter ist.
  LogStream := nil;
  // Selbe Log-Datei wie der Scan - liegt im %APPDATA%\StaticCodeAnalyser
  // Verzeichnis (gleiches wie ignore.txt).
  LogPath := TIgnoreList.LogFilePath;
  try
    if not DirectoryExists(TIgnoreList.ConfigDir) then
      ForceDirectories(TIgnoreList.ConfigDir);
  except
  end;
  Parser := nil;
  // Eine gemeinsame try-finally klammer fuer LogStream UND Parser - so leakt
  // weder bei Parser-Create-OOM der LogStream noch umgekehrt.
  try
    try
      // Append-Modus, damit der Scan-Log nicht ueberschrieben wird
      LogStream := TStreamWriter.Create(LogPath, True, TEncoding.UTF8);
      LogLine('=== ParseLeaks gestartet: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)
              + ' (' + IntToStr(FileList.Count) + ' Dateien) ===');
    except
      LogStream := nil;
    end;

    Parser := TParser2.Create;
    Total  := FileList.Count;
    for i := 0 to Total - 1 do
    begin
      SafeProgress(i + 1, Total);

      FileName := FileList[i];

      // Leerer Dateiname → ignorieren (defensiv)
      if Trim(FileName) = '' then
      begin
        AddFileError('(leer)', 'Leerer Dateiname in der Liste');
        Continue;
      end;

      // Datei-Existenz pruefen (mit Exception-Schutz – Race-Conditions)
      try
        if not TFile.Exists(FileName) then
        begin
          AddFileError(FileName, 'Datei nicht gefunden');
          Continue;
        end;
      except
        on E: Exception do
        begin
          AddFileError(FileName, 'Datei-Existenzpruefung fehlgeschlagen: ' + E.Message);
          Continue;
        end;
      end;

      // Datei-Groesse pruefen (Datei kann zwischen Exists und GetSize verschwinden)
      try
        FileSize := TFile.GetSize(FileName);
      except
        on E: Exception do
        begin
          AddFileError(FileName, 'Dateigroesse nicht ermittelbar: ' + E.Message);
          Continue;
        end;
      end;

      if FileSize > MAX_FILE_BYTES then
      begin
        AddFileError(FileName, Format('Datei zu groß (%.1f MB) – Analyse übersprungen',
                                     [FileSize / (1024 * 1024)]));
        Continue;
      end;

      // Leere Dateien ueberspringen (nichts zu analysieren, kein Fehler)
      if FileSize = 0 then Continue;

      // Datei einlesen und parsen
      LogLine(Format('[%d/%d] %s (%d KB)',
                     [i + 1, Total, FileName, FileSize div 1024]));
      Watch := TStopwatch.StartNew;

      Root := nil;
      try
        try
          Root := Parser.ParseFile(FileName);
        except
          on E: Exception do
          begin
            LogLine('  PARSER-FEHLER: ' + E.Message);
            AddFileError(FileName, 'Lesefehler: ' + E.Message);
            Continue;
          end;
        end;

        if Root = nil then
        begin
          LogLine('  PARSER liefert nil');
          AddFileError(FileName, 'Parser lieferte kein Ergebnis');
          Continue;
        end;

        ElapsedMs := Watch.ElapsedMilliseconds;
        if ElapsedMs > 500 then
          LogLine(Format('  Parse: %d ms (langsam!)', [ElapsedMs]))
        else if Assigned(LogStream) then
          LogLine(Format('  Parse: %d ms', [ElapsedMs]));

        // Detektoren ausfuehren – jeder einzeln geschuetzt, damit ein
        // fehlerhafter Detektor nicht alle anderen blockiert.
        for var DetectorIdx := 0 to 20 do
        begin
          if (DetectorIdx = 5) and not AIncludeUsesCheck then Continue;
          Watch := TStopwatch.StartNew;
          try
            case DetectorIdx of
               0: TLeakDetector2.AnalyzeUnit(Root, FileName, Results);
               1: TEmptyExceptDetector2.AnalyzeUnit(Root, FileName, Results);
               2: TSQLInjectionDetector.AnalyzeUnit(Root, FileName, Results);
               3: THardcodedSecretDetector.AnalyzeUnit(Root, FileName, Results);
               4: TFormatMismatchDetector.AnalyzeUnit(Root, FileName, Results);
               5: TUnusedUsesDetector.AnalyzeUnit(Root, FileName, Results);
               6: TNilDerefDetector.AnalyzeUnit(Root, FileName, Results);
               7: TMissingFinallyDetector.AnalyzeUnit(Root, FileName, Results);
               8: TDivByZeroDetector.AnalyzeUnit(Root, FileName, Results);
               9: TDeadCodeDetector.AnalyzeUnit(Root, FileName, Results);
              10: TLongMethodDetector.AnalyzeUnit(Root, FileName, Results);
              11: TLongParamListDetector.AnalyzeUnit(Root, FileName, Results);
              12: TMagicNumberDetector.AnalyzeUnit(Root, FileName, Results);
              13: TDuplicateStringDetector.AnalyzeUnit(Root, FileName, Results);
              14: THardcodedPathDetector.AnalyzeUnit(Root, FileName, Results);
              15: TDebugOutputDetector.AnalyzeUnit(Root, FileName, Results);
              16: TDeepNestingDetector.AnalyzeUnit(Root, FileName, Results);
              17: TTodoCommentDetector.AnalyzeUnit(Root, FileName, Results);
              18: TEmptyMethodDetector.AnalyzeUnit(Root, FileName, Results);
              19: TFieldLeakDetector.AnalyzeUnit(Root, FileName, Results);
              20: TDuplicateBlockDetector.AnalyzeUnit(Root, FileName, Results);
            end;
          except
            on E: Exception do
            begin
              LogLine(Format('  DETEKTOR %d FEHLER: %s', [DetectorIdx, E.Message]));
              AddFileError(FileName,
                Format('Detektor %d fehlgeschlagen: %s', [DetectorIdx, E.Message]));
            end;
          end;
          ElapsedMs := Watch.ElapsedMilliseconds;
          if ElapsedMs > 500 then
            LogLine(Format('  Detektor %d: %d ms (langsam!)', [DetectorIdx, ElapsedMs]));
        end;
      finally
        Root.Free;
      end;
    end;
  finally
    // LogStream auch bei EAbort sauber schliessen, danach Parser.
    // Eine gemeinsame Klammer verhindert dass Parser-Create-OOM den LogStream
    // hinterlaesst oder umgekehrt.
    LogLine('=== ParseLeaks fertig: ' + FormatDateTime('hh:nn:ss', Now) + ' ===');
    if Assigned(LogStream) then
      FreeAndNil(LogStream);
    Parser.Free;
  end;

  // Suppression-Kommentare auswerten und Befunde filtern
  try
    TSuppression.ApplyToFindings(Results);
  except
    // Suppression-Fehler duerfen das Ergebnis nicht zerstoeren
  end;
end;

class function TStaticAnalyzer2.AnalyzeLeaks(const FileName: string;
  AIncludeUsesCheck: Boolean): TObjectList<TLeakFinding>;

  procedure AddError(const Msg: string);
  var F: TLeakFinding;
  begin
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := '';
    F.LineNumber := '0';
    F.MissingVar := Msg;
    F.Severity   := lsError;
    F.Kind       := fkFileReadError;
    Result.Add(F);
  end;

var
  FileList: TStringList;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  if Trim(FileName) = '' then
  begin
    AddError('Kein Dateiname angegeben');
    Exit;
  end;

  FileList := TStringList.Create;
  try
    FileList.Add(FileName);
    try
      ParseLeaks(FileList, Result, nil, AIncludeUsesCheck);
    except
      on E: Exception do
        AddError('Analyseabbruch: ' + E.Message);
    end;
  finally
    FileList.Free;
  end;
end;

class function TStaticAnalyzer2.AnalyzeLeaksRecursive(const Path: string;
  AProgress: TProc<Integer, Integer>;
  AIncludeUsesCheck: Boolean;
  AIgnore: TIgnoreList): TObjectList<TLeakFinding>;

  procedure AddError(const Msg: string);
  var F: TLeakFinding;
  begin
    F            := TLeakFinding.Create;
    F.FileName   := Path;
    F.MethodName := '';
    F.LineNumber := '0';
    F.MissingVar := Msg;
    F.Severity   := lsError;
    F.Kind       := fkFileReadError;
    Result.Add(F);
  end;

var
  FileList : TStringList;
  ScanErr  : string;
begin
  Result := TObjectList<TLeakFinding>.Create(True);

  if Trim(Path) = '' then
  begin
    AddError('Kein Pfad angegeben');
    Exit;
  end;

  if not DirectoryExists(Path) then
  begin
    AddError('Verzeichnis nicht gefunden: ' + Path);
    Exit;
  end;

  // Dateien sammeln. Den Progress-Callback nutzen wir auch hier mit
  // Total = -1 als Marker fuer "Scanne Verzeichnis" - der UI-Layer kann
  // dann einen Status-Text setzen und Application.ProcessMessages /
  // Abort-Check durchfuehren. Bei nicht uebergebenem Callback passiert
  // nichts.
  try
    FileList := TStaticFiles.TryGetAllPasFiles(Path, ScanErr,
      procedure(FilesFound: Integer)
      begin
        if Assigned(AProgress) then
          AProgress(FilesFound, -1);
      end,
      AIgnore);
  except
    on EAbort do
    begin
      // Abbruch bereits waehrend des Verzeichnis-Scans
      FreeAndNil(Result);
      raise;
    end;
  end;
  try
    if ScanErr <> '' then
      AddError('Verzeichnis-Scan: ' + ScanErr);

    if FileList.Count = 0 then
    begin
      // Kein Fehler, aber Hinweis fuer den Benutzer
      AddError('Keine .pas-Dateien im Verzeichnis gefunden');
      Exit;
    end;

    try
      ParseLeaks(FileList, Result, AProgress, AIncludeUsesCheck);
    except
      on EAbort do
      begin
        // Benutzerseitiger Abbruch (z.B. ueber Cancel-Button im Progress-Callback).
        // Result-Liste freigeben, damit kein Leak entsteht, und EAbort weiter
        // hochreichen - der Aufrufer erkennt den Abbruch daran.
        FreeAndNil(Result);
        raise;
      end;
      on E: Exception do
        AddError('Analyseabbruch: ' + E.Message);
    end;
  finally
    FileList.Free;
  end;
end;

class function TStaticAnalyzer2.AnalyzeLeaksFromList(AFiles: TStringList;
  AProgress: TProc<Integer, Integer>;
  AIncludeUsesCheck: Boolean): TObjectList<TLeakFinding>;
// Analysiert eine vorgefertigte Datei-Liste (z.B. aus uVcsChanges).
// Eingangsliste wird kopiert - der Aufrufer behaelt seine Ownership.

  procedure AddError(const Msg: string);
  var F: TLeakFinding;
  begin
    F            := TLeakFinding.Create;
    F.FileName   := '';
    F.MethodName := '';
    F.LineNumber := '0';
    F.MissingVar := Msg;
    F.Severity   := lsError;
    F.Kind       := fkFileReadError;
    Result.Add(F);
  end;

var
  Copy: TStringList;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  if (AFiles = nil) or (AFiles.Count = 0) then
  begin
    AddError('Keine Dateien zu analysieren');
    Exit;
  end;

  Copy := TStringList.Create;
  try
    Copy.AddStrings(AFiles);
    try
      ParseLeaks(Copy, Result, AProgress, AIncludeUsesCheck);
    except
      on EAbort do
      begin
        FreeAndNil(Result);
        raise;
      end;
      on E: Exception do
        AddError('Analyseabbruch: ' + E.Message);
    end;
  finally
    Copy.Free;
  end;
end;

class function TStaticAnalyzer2.Analyze(const FileName: string): TStringList;
var
  FileList: TStringList;
begin
  Result   := TStringList.Create;
  FileList := TStringList.Create;
  try
    FileList.Add(FileName);
    ParseFiles(FileList, Result);
  finally
    FileList.Free;
  end;
end;

class function TStaticAnalyzer2.AnalyzeRecursive(const Path: string): TStringList;
var
  FileList: TStringList;
begin
  Result   := TStringList.Create;
  FileList := TStaticFiles.GetAllPasFilesRecursive(Path);
  try
    ParseFiles(FileList, Result);
  finally
    FileList.Free;
  end;
end;

end.

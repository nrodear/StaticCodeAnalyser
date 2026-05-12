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
  uCyclomaticComplexity, uCustomRuleDetector,
  uDfmAnalysisRunner, uDfmRepoIndex,
  uSuppression, uCustomClassDiscovery,
  uRuleCatalog;

type
  // Run-Methode pro Detektor: einheitliche Signatur, damit alle in einem
  // Array iteriert werden koennen.
  TDetectorRun = reference to procedure(Root: TAstNode; const FileName: string;
    Results: TObjectList<TLeakFinding>);
  TDetectorEntry = record
    Name : string;
    Kind : TFindingKind;  // fuer Profile-/Severity-Filter (uSCAConsts globals)
    Run  : TDetectorRun;
    Skip : Boolean;
  end;
  // Callbacks fuer den Aufrufer (Logging / Fehler-Reporting), damit
  // RunAllDetectors selbst kein Wissen ueber LogStream/FileError-Liste hat.
  TDetectorTimeProc  = reference to procedure(const Name: string; ElapsedMs: Int64);
  TDetectorErrorProc = reference to procedure(const Name, ErrMsg: string);

procedure RunAllDetectors(Root: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>; AIncludeUsesCheck: Boolean;
  AOnTime: TDetectorTimeProc; AOnError: TDetectorErrorProc);
var
  Detectors : array of TDetectorEntry;
  i         : Integer;
  Watch     : TStopwatch;

  procedure Add(const AName: string; AKind: TFindingKind; ARun: TDetectorRun);
  // Skip-Check pro Detektor zentralisiert:
  //   1. Profile-Whitelist (DetectorEnabledKinds): leere Menge = kein
  //      Filter, sonst Whitelist.
  //   2. Severity-Schwellwert (DetectorMinSeverity): Detector wird
  //      geskippt wenn seine Default-Severity strenger ist
  //      (ord(sev) > ord(MinSeverity), da lsError=0 < lsWarning=1 < lsHint=2).
  // Beide Kriterien sind ODER-verknuepft - einer von beiden reicht.
  // Mehrere Detektoren teilen sich einen Kind (z.B. mehrere DFM-Detektoren
  // sind alle ueber DfmAnalysisRunner gebuendelt unter ihren eigenen Kinds);
  // pro Add() greift trotzdem nur EIN Kind als Filter-Schluessel.
  var
    Sev : TLeakSeverity;
  begin
    SetLength(Detectors, Length(Detectors) + 1);
    with Detectors[High(Detectors)] do
    begin
      Name := AName;
      Kind := AKind;
      Run  := ARun;
      Skip := False;

      // (1) Profile-Whitelist. Leere Menge = "kein Filter".
      if (uSCAConsts.DetectorEnabledKinds <> []) and
         not (AKind in uSCAConsts.DetectorEnabledKinds) then
        Skip := True;

      // (2) Severity-Schwellwert. Catalog-Lookup ist O(1) (Dictionary).
      if not Skip then
      begin
        Sev := TRuleCatalog.GetRule(AKind).DefaultSeverity;
        if Ord(Sev) > Ord(uSCAConsts.DetectorMinSeverity) then
          Skip := True;
      end;
    end;
  end;

begin
  Add('Leak',            fkMemoryLeak,      procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TLeakDetector2.AnalyzeUnit(R, F, L); end);
  Add('EmptyExcept',     fkEmptyExcept,     procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TEmptyExceptDetector2.AnalyzeUnit(R, F, L); end);
  Add('SQLInjection',    fkSQLInjection,    procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TSQLInjectionDetector.AnalyzeUnit(R, F, L); end);
  Add('HardcodedSecret', fkHardcodedSecret, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin THardcodedSecretDetector.AnalyzeUnit(R, F, L); end);
  Add('FormatMismatch',  fkFormatMismatch,  procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TFormatMismatchDetector.AnalyzeUnit(R, F, L); end);
  Add('UnusedUses',      fkUnusedUses,      procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TUnusedUsesDetector.AnalyzeUnit(R, F, L); end);
  // UsesCheck zusaetzlich zum Profile-/Severity-Filter: bleibt Skip-Wahr
  // wenn der Caller AIncludeUsesCheck=False uebergibt - auch bei strict
  // profile, damit der "AIncludeUsesCheck=False" Standard nicht umgangen
  // wird. (strict profile zaehlt UnusedUses zur Whitelist; der Boolean ist
  // der Pre-Existing-Opt-out, der haerter wirkt.)
  if not AIncludeUsesCheck then Detectors[High(Detectors)].Skip := True;
  Add('NilDeref',        fkNilDeref,        procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TNilDerefDetector.AnalyzeUnit(R, F, L); end);
  Add('MissingFinally',  fkMissingFinally,  procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TMissingFinallyDetector.AnalyzeUnit(R, F, L); end);
  Add('DivByZero',       fkDivByZero,       procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TDivByZeroDetector.AnalyzeUnit(R, F, L); end);
  Add('DeadCode',        fkDeadCode,        procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TDeadCodeDetector.AnalyzeUnit(R, F, L); end);
  Add('LongMethod',      fkLongMethod,      procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TLongMethodDetector.AnalyzeUnit(R, F, L); end);
  Add('LongParamList',   fkLongParamList,   procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TLongParamListDetector.AnalyzeUnit(R, F, L); end);
  Add('MagicNumber',     fkMagicNumber,     procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TMagicNumberDetector.AnalyzeUnit(R, F, L); end);
  Add('DuplicateString', fkDuplicateString, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TDuplicateStringDetector.AnalyzeUnit(R, F, L); end);
  Add('HardcodedPath',   fkHardcodedPath,   procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin THardcodedPathDetector.AnalyzeUnit(R, F, L); end);
  Add('DebugOutput',     fkDebugOutput,     procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TDebugOutputDetector.AnalyzeUnit(R, F, L); end);
  Add('DeepNesting',     fkDeepNesting,     procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TDeepNestingDetector.AnalyzeUnit(R, F, L); end);
  Add('TodoComment',     fkTodoComment,     procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TTodoCommentDetector.AnalyzeUnit(R, F, L); end);
  Add('EmptyMethod',     fkEmptyMethod,     procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TEmptyMethodDetector.AnalyzeUnit(R, F, L); end);
  // FieldLeak: gleicher Kind wie LeakDetector (fkMemoryLeak) - Profile-
  // Filter behandelt beide identisch.
  Add('FieldLeak',       fkMemoryLeak,      procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TFieldLeakDetector.AnalyzeUnit(R, F, L); end);
  Add('DuplicateBlock',  fkDuplicateBlock,  procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TDuplicateBlockDetector.AnalyzeUnit(R, F, L); end);
  Add('CyclomaticComplexity', fkCyclomaticComplexity, procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TCyclomaticComplexityDetector.AnalyzeUnit(R, F, L); end);
  // DFM-Adapter: ruft intern ~20 DFM-Detektoren, jeder produziert seinen
  // eigenen Kind. Wir wuerden hier zu Unrecht alles skippen, wenn der
  // einzelne Repraesentant-Kind nicht im Profile waere. Daher laeuft der
  // Adapter immer (ist No-Op fuer .pas ohne companion .dfm) - die Filterung
  // findet auf Finding-Ebene weiter unten statt. Skip := False explizit.
  Add('DfmAnalysis',     fkDfmDefaultName,  procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>) begin TDfmAnalysisRunner.AnalyzePasFile(F, L); end);
  Detectors[High(Detectors)].Skip := False;

  for i := 0 to High(Detectors) do
  begin
    if Detectors[i].Skip then Continue;
    Watch := TStopwatch.StartNew;
    try
      Detectors[i].Run(Root, FileName, Results);
    except
      // User-Cancel (EAbort) muss durchgereicht werden, damit die
      // Schleife in AnalyzeLeaksRecursive abbricht. Ein generischer
      // Detektor-Fehler hingegen blockiert die anderen Detektoren nicht.
      on EAbort do raise;
      on E: Exception do
        if Assigned(AOnError) then
          AOnError(Detectors[i].Name, E.Message);
    end;
    if Assigned(AOnTime) then
      AOnTime(Detectors[i].Name, Watch.ElapsedMilliseconds);
  end;

  // ---- Post-Filter ----
  // Detector-Level-Skip ist nicht fein genug fuer Adapter, die intern
  // mehrere Kinds produzieren (DfmAnalysisRunner). Daher Findings noch
  // einmal durchgehen:
  //   * Kind nicht im Profile -> raus
  //   * Severity strenger als MinSeverity -> raus (Detector koennte ein
  //     Finding mit haerterer Severity erzeugen als KIND_META erlaubt;
  //     auch CustomRules tragen variable Severity).
  // fkFileReadError ist immer durchgelassen (Diagnose-Befund), unabhaengig
  // vom Profile.
  if (uSCAConsts.DetectorEnabledKinds <> []) or
     (uSCAConsts.DetectorMinSeverity <> lsHint) then
  begin
    for i := Results.Count - 1 downto 0 do
    begin
      if Results[i].Kind = fkFileReadError then Continue;
      if (uSCAConsts.DetectorEnabledKinds <> []) and
         not (Results[i].Kind in uSCAConsts.DetectorEnabledKinds) then
      begin
        Results.Delete(i);
        Continue;
      end;
      if Ord(Results[i].Severity) > Ord(uSCAConsts.DetectorMinSeverity) then
        Results.Delete(i);
    end;
  end;
end;

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
// MAX_FILE_BYTES kommt aus uSCAConsts.DetectorMaxFileBytes (analyser.ini ->
// MaxFileMB * 1024 * 1024). Default 5 MB.

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
    // Best-effort: kein ConfigDir = kein Log, der Scan laeuft trotzdem.
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

    // Repo-weiten Index fuer Cross-Unit-Detektoren einmal pro Scan
    // aufbauen. Wenn das Build crasht (defekte .pas), schluckt der
    // Index das selbst - der Hauptanalyse-Pfad laeuft auch ohne Index
    // weiter, Cross-Unit-Detektoren schweigen dann mangels Daten.
    gDfmRepoIndex := TDfmRepoIndex.Create;
    try
      gDfmRepoIndex.Build(FileList);
    except
      FreeAndNil(gDfmRepoIndex);
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

      if FileSize > DetectorMaxFileBytes then
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

        // Detektoren ausfuehren - jeder einzeln geschuetzt, damit ein
        // fehlerhafter Detektor nicht alle anderen blockiert.
        // Vorher hardcoded 'for DetectorIdx := 0 to 20' + grosse case-Anweisung -
        // jetzt iterativ ueber RunAllDetectors-Helper. Hinzufuegen eines
        // Detektors -> nur ein Eintrag in der Helper-Funktion.
        // Closures captern LogStream/Results/FileName direkt, da nested procs
        // (LogLine/AddFileError) von anonymen Methoden nicht referenziert
        // werden duerfen (E2555).
        var CaptLogStream := LogStream;
        var CaptResults   := Results;
        var CaptFileName  := FileName;

        // Auto-Discovery: wenn aktiviert, vor dem MemoryLeak-Detektor das AST
        // nach Custom-Klassen scannen und LeakyClasses ergaenzen. Wirkt fuer
        // alle nachfolgenden Files in DIESEM Lauf - kumulativ, weil
        // Sorted+dupIgnore.
        // ExcludeLeakyClasses werden hier respektiert - sonst koennte
        // Discovery eine vom User explizit ausgeschlossene Klasse wieder
        // einschleusen.
        // Auto-Discovery: TCustomClassDiscovery teilt die gefundenen Klassen
        // in zwei Gruppen auf - "instantiable" (Konstruktor/Destruktor oder
        // Create-Aufruf in der Unit) und "static-only" (keine Instanziierungs-
        // Hinweise gefunden, vermutlich Utility-Klassen).
        //
        //  * Instantiable -> Runtime-LeakyClasses (Detektion in diesem Lauf)
        //                    + DiscoveredClasses (fuer .log)
        //  * StaticOnly   -> nur DiscoveredStaticClasses (.log, auskommentiert)
        //
        // Beide Gruppen respektieren LeakyClassExcludes. Die INI bleibt
        // unangetastet; der User entscheidet handisch welche Klasse er in
        // [Detectors] LeakyClasses uebernimmt.
        if AutoDiscoverCustomClasses then
        begin
          var Instantiable : TArray<string>;
          var StaticOnly   : TArray<string>;
          TCustomClassDiscovery.DiscoverInUnit(Root, Instantiable, StaticOnly);

          for var Cls in Instantiable do
          begin
            if Assigned(LeakyClassExcludes) and
               (LeakyClassExcludes.IndexOf(Cls) >= 0) then Continue;
            if Assigned(LeakyClasses) then
              LeakyClasses.Add(Cls);
            if Assigned(DiscoveredClasses) then
              DiscoveredClasses.Add(Cls);
          end;

          for var Cls in StaticOnly do
          begin
            if Assigned(LeakyClassExcludes) and
               (LeakyClassExcludes.IndexOf(Cls) >= 0) then Continue;
            // Bewusst NICHT in LeakyClasses - static-only Klassen haben
            // keine Instanzen und brauchen keine Leak-Detektion.
            if Assigned(DiscoveredStaticClasses) then
              DiscoveredStaticClasses.Add(Cls);
          end;
        end;

        // Custom-Rules (aus analyser-rules.yml) NACH den built-in
        // Detektoren - so liegen sie im Output sortierbar zusammen.
        // No-op wenn TCustomRuleDetector.LoadFromYaml nicht aufgerufen
        // wurde (HasRules = False).
        if TCustomRuleDetector.HasRules then
          TCustomRuleDetector.AnalyzeFile(FileName, Results);

        RunAllDetectors(Root, FileName, Results, AIncludeUsesCheck,
          procedure(const Name: string; ElapsedMs: Int64) begin
            if (ElapsedMs > 500) and Assigned(CaptLogStream) then
              try
                CaptLogStream.WriteLine(Format('  Detektor %s: %d ms (langsam!)',
                  [Name, ElapsedMs]));
                CaptLogStream.Flush;
              except end;
          end,
          procedure(const Name, ErrMsg: string)
          begin
            if Assigned(CaptLogStream) then
              try
                CaptLogStream.WriteLine(Format('  DETEKTOR %s FEHLER: %s',
                  [Name, ErrMsg]));
                CaptLogStream.Flush;
              except end;
            // entspricht AddFileError - inlined wegen Capture-Limits
            var F := TLeakFinding.Create;
            F.FileName   := CaptFileName;
            F.MethodName := '';
            F.LineNumber := '0';
            F.MissingVar := Format('Detector %s failed: %s',
                                   [Name, ErrMsg]);
            F.Severity   := lsError;
            F.Kind       := fkFileReadError;
            CaptResults.Add(F);
          end);
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
    // Repo-Index nach dem Scan wieder freigeben - Cross-Unit-Detektoren
    // ausserhalb dieses Scans sollen nicht versehentlich stale Daten sehen.
    if Assigned(gDfmRepoIndex) then
      FreeAndNil(gDfmRepoIndex);
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

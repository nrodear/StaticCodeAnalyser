unit uStaticAnalyzer;

interface

uses
  System.Generics.Collections, SysUtils, System.Classes, uMethodd12;

type
  // Fortschritts-Callback: (aktuellerIndex, gesamtDateien)
  TAnalysisProgress = reference to procedure(Current, Total: Integer);

  TStaticAnalyzer = class

    class function Analyze(const filename, myClass: string): TStringList;

    class function AnalyzeRecursive(const Path, myClass: string): TStringList;

    class function AnalyzeAllClassesRecursive(const Path: string;
      AProgress: TAnalysisProgress = nil): TObjectList<TLeakFinding>;

    class function AnalyzeAllClassesSingleFile(const FileName: string): TObjectList<TLeakFinding>;

  private
    class procedure ParseFiles(FileList: TStringList; const myClazz: string;
      out results: TStringList);

    class procedure ParseFilesAllClasses(FileList: TStringList;
      const classes: TStringList; out results: TObjectList<TLeakFinding>;
      AProgress: TAnalysisProgress = nil);

    class function TrySearchMissingFreeds(VaiableNames: TStringList;
      Body: TStringList; out messageMissing: TStringList): boolean;
  end;

implementation

uses
  uStaticFiles, uParser, uSCAConsts, uLeakDetector, uCodeSmells;

class function TStaticAnalyzer.Analyze(const filename, myClass: string)
  : TStringList;
var
  FileList: TStringList;
  results: TStringList;
begin
  results := TStringList.Create;
  FileList := TStringList.Create;
  try
    FileList.Add(filename);
    ParseFiles(FileList, myClass, results);
  finally
    FreeAndNil(FileList);
  end;
  Result := results;
end;

class function TStaticAnalyzer.AnalyzeRecursive(const Path, myClass: string)
  : TStringList;
var
  FileList: TStringList;
  results: TStringList;
begin
  results := TStringList.Create;
  FileList := TStaticFiles.GetAllPasFilesRecursive(Path);
  try
    ParseFiles(FileList, myClass, results);
  finally
    FileList.Free;
  end;
  Result := results;
end;

class function TStaticAnalyzer.AnalyzeAllClassesRecursive(const Path: string;
  AProgress: TAnalysisProgress): TObjectList<TLeakFinding>;
var
  FileList: TStringList;
  classes: TStringList;
  results: TObjectList<TLeakFinding>;
begin
  results  := TObjectList<TLeakFinding>.Create;
  FileList := TStaticFiles.GetAllPasFilesRecursive(Path);
  classes  := TConsts.GetLeakyClasses;
  try
    ParseFilesAllClasses(FileList, classes, results, AProgress);
  finally
    FileList.Free;
    classes.Free;
  end;
  Result := results;
end;

class function TStaticAnalyzer.AnalyzeAllClassesSingleFile(
  const FileName: string): TObjectList<TLeakFinding>;
var
  FileList: TStringList;
  classes : TStringList;
  results : TObjectList<TLeakFinding>;
begin
  results  := TObjectList<TLeakFinding>.Create;
  FileList := TStringList.Create;
  classes  := TConsts.GetLeakyClasses;
  try
    FileList.Add(FileName);
    ParseFilesAllClasses(FileList, classes, results);
  finally
    FileList.Free;
    classes.Free;
  end;
  Result := results;
end;

class procedure TStaticAnalyzer.ParseFilesAllClasses(FileList: TStringList;
  const classes: TStringList; out results: TObjectList<TLeakFinding>;
  AProgress: TAnalysisProgress);
var
  filename: string;
  i, k: Integer;
  methodInfos: TObjectList<TMethodInfo>;
  methodInfo: TMethodInfo;
  VarNames: TStringList;
  leakResults: TObjectList<TLeakResult>;
  smellResults: TObjectList<TSmellFinding>;
  lr: TLeakResult;
  sf: TSmellFinding;
  finding: TLeakFinding;
  rawLines: TStringList;
  lowLines: TStringList;
  total: Integer;
begin
  VarNames     := TStringList.Create;
  leakResults  := TObjectList<TLeakResult>.Create;
  smellResults := TObjectList<TSmellFinding>.Create;
  methodInfos  := TObjectList<TMethodInfo>.Create;
  rawLines     := TStringList.Create;
  lowLines     := TStringList.Create;
  total        := FileList.Count;
  try
    for i := 0 to total - 1 do
    begin
      // Fortschritt melden (jede Datei)
      if Assigned(AProgress) then
        AProgress(i + 1, total);

      filename := FileList[i];

      // Datei einmalig laden — Encoding-Fallback: Default → UTF-8 → UTF-16 → Win-1252
      try
        rawLines.LoadFromFile(filename);
      except
        try
          rawLines.LoadFromFile(filename, TEncoding.UTF8);
        except
          try
            rawLines.LoadFromFile(filename, TEncoding.Unicode);
          except
            Continue; // Datei nicht lesbar — überspringen
          end;
        end;
      end;

      // Lowercase-Kopie zeilenweise (kein .Text.ToLower)
      lowLines.Clear;
      for k := 0 to rawLines.Count - 1 do
        lowLines.Add(rawLines[k].ToLower);

      // ---- Parser ----
      methodInfos.Clear;
      try
        TParser.ParseLines(rawLines, methodInfos);
      except
        Continue;
      end;

      // ---- Speicherleck-Analyse pro Methode ----
      // DetectAll: ExtractFinallyRanges + body.Text werden nur EINMAL pro Methode berechnet
      for methodInfo in methodInfos do
      begin
        VarNames.Clear;
        methodInfo.GetVarNamesByClasses(classes, VarNames);
        if VarNames.Count = 0 then Continue;

        leakResults.Clear;
        TLeakDetector.DetectAll(VarNames, methodInfo.SourceBody, leakResults);

        for lr in leakResults do
        begin
          finding            := TLeakFinding.Create;
          finding.FileName   := filename;
          finding.MethodName := methodInfo.Name;
          finding.LineNumber := methodInfo.LineNumber;
          finding.MissingVar := lr.VarName;
          finding.Severity   := lr.Severity;
          finding.Kind       := fkMemoryLeak;
          results.Add(finding);
        end;
      end;

      // ---- Leere except-Bloecke ----
      smellResults.Clear;
      TEmptyExceptDetector.Detect(lowLines, smellResults);

      for sf in smellResults do
      begin
        finding            := TLeakFinding.Create;
        finding.FileName   := filename;
        finding.MethodName := '';
        finding.LineNumber := IntToStr(sf.LineNumber);
        finding.MissingVar := sf.Description;
        finding.Severity   := sf.Severity;
        finding.Kind       := fkEmptyExcept;
        results.Add(finding);
      end;
    end;
  finally
    FreeAndNil(VarNames);
    FreeAndNil(leakResults);
    FreeAndNil(smellResults);
    FreeAndNil(methodInfos);
    FreeAndNil(rawLines);
    FreeAndNil(lowLines);
  end;
end;

class procedure TStaticAnalyzer.ParseFiles(FileList: TStringList;
  const myClazz: string; out results: TStringList);
var
  filename: string;
  i: Integer;
  methodInfos: TObjectList<TMethodInfo>;
  methodInfo: TMethodInfo;
  VaiableNames: TStringList;
  messageMissing: TStringList;
  onceFileName: boolean;
begin
  messageMissing := TStringList.Create;
  VaiableNames := TStringList.Create;
  methodInfos := TObjectList<TMethodInfo>.Create;
  try
    for i := 0 to FileList.Count - 1 do
    begin
      methodInfos.Clear;
      filename := FileList[i];
      try
        TParser.ParseFile(filename, methodInfos);
      except
        results.Add('ERROR parse file failed: ' + filename);
        Continue;
      end;

      if methodInfos.Count <> 0 then
      begin
        onceFileName := false;

        for methodInfo in methodInfos do
        begin
          VaiableNames.Clear;
          methodInfo.GetVarNamesByFilter(myClazz, VaiableNames);

          messageMissing.Add('method; line:' + methodInfo.LineNumber + ':' +
            methodInfo.Name);

          // results.Add(Vaiable);
          // suche string var.free
          if TrySearchMissingFreeds(VaiableNames, methodInfo.SourceBody,
            messageMissing) then
          begin
            if not onceFileName then
              results.Add(filename);
            onceFileName := true;
            results.AddStrings(messageMissing);
          end;
          messageMissing.Clear;
        end;

      end;

    end;
  finally
    FreeAndNil(VaiableNames);
    FreeAndNil(messageMissing);
    FreeAndNil(methodInfos);
  end;

end;

class function TStaticAnalyzer.TrySearchMissingFreeds(VaiableNames: TStringList;
  Body: TStringList; out messageMissing: TStringList): boolean;

var
  searchDestroy, searchFree: string;
  searchFreeAnd, asResult: string;
  myVar: string;
  myMessage: string;
begin
  Result := false;

  myMessage := 'missing freeds: ';
  for myVar in VaiableNames do
  begin

    // all to lower
    asResult := 'result := ' + myVar + ';';
    searchFree := myVar + '.free';
    searchDestroy := myVar + '.destroy';
    searchFreeAnd := 'freeandnil(' + myVar + ')';

    if (Body.Text.IndexOf(searchFree.ToLower) = -1) and
      (Body.Text.IndexOf(searchDestroy.ToLower) = -1) and
      (Body.Text.IndexOf(searchFreeAnd.ToLower) = -1) and
      (Body.Text.IndexOf(asResult.ToLower) = -1) then
    begin
      Result := true;
      messageMissing.Add(myMessage + ' ' + myVar);
    end;

  end;

end;

end.

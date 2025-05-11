unit StaticAnalyzer;

interface

uses
  System.Generics.Collections, SysUtils, System.Classes;

type
  TStaticAnalyzer = class

    class function Analyze(const filename, myClass: string): TStringList;

    class function AnalyzeRecursive(const Path, myClass: string): TStringList;

  private
    class procedure ParseFiles(FileList: TStringList; const myClazz: string;
      out results: TStringList);

    class function TrySearchMissingFreeds(VaiableNames: TStringList;
      Body: TStringList; out messageMissing: TStringList): boolean;
  end;

implementation

uses
  Dialogs,
  StaticFiles, uParser, uMethodd12;

class function TStaticAnalyzer.Analyze(const filename, myClass: string)
  : TStringList;
var
  FileList: TStringList;
  results: TStringList;
begin
  FileList := TStringList.Create;
  results := TStringList.Create;
  FileList.Add(filename);
  ParseFiles(FileList, myClass, results);

  freeAndNil(FileList);
  Result := results;
end;

class function TStaticAnalyzer.AnalyzeRecursive(const Path, myClass: string)
  : TStringList;
var
  FileList: TStringList;
  CheckResult: TStringList;
  results: TStringList;
begin
  results := TStringList.Create;
  FileList := TStaticFiles.GetAllPasFilesRecursive(Path);
  CheckResult := TStringList.Create;
  ParseFiles(FileList, myClass, results);
  Result := results;

  FileList.free;
  freeAndNil(CheckResult);
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

  freeAndNil(VaiableNames);
  freeAndNil(messageMissing);
  freeAndNil(methodInfos);

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

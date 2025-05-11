unit StaticFiles;

interface

uses
  System.SysUtils, System.Classes, System.Masks, System.StrUtils,
  System.IOUtils;

type
  TStaticFiles = class
    class function GetAllPasFilesRecursive(const Path: string)
      : TStringList; static;

  end;

implementation

class function TStaticFiles.GetAllPasFilesRecursive(const Path: string)
  : TStringList;
var
  SearchRec: TSearchRec;
  SubDir: string;
begin
  Result := TStringList.Create;
  try
    if FindFirst(IncludeTrailingPathDelimiter(Path) + '*.*', faAnyFile,
      SearchRec) = 0 then
    begin
      repeat
        if (SearchRec.Attr and faDirectory) = 0 then
        begin
          if MatchesMask(SearchRec.Name, '*.pas') then
            Result.Add(IncludeTrailingPathDelimiter(Path) + SearchRec.Name);
        end
        else if (SearchRec.Name <> '.') and (SearchRec.Name <> '..') then
        begin
          SubDir := IncludeTrailingPathDelimiter(Path) + SearchRec.Name;
          Result.AddStrings(GetAllPasFilesRecursive(SubDir));
        end;
      until FindNext(SearchRec) <> 0;
      FindClose(SearchRec);
    end;
  except
    raise;
  end;
end;

end.

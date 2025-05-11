unit uParser;

interface

uses
  System.StrUtils, System.Classes, System.SysUtils, System.Generics.Collections,
  System.RegularExpressions,
  uMethodd12;

type
  TParser = class
    class function GetName(const line: string): string;
    class function IsCommentOf(const line: string;
      isStart: boolean = true): boolean;
    class function MatchString(searchStr: string; const line: string)
      : boolean; static;

    class function MatchOnlyString(searchStr: string; const line: string)
      : boolean; static;
    class function GetCodeOnly(const line: string): string;
    class procedure ParseFile(const FileName: string;
      out methodsList: TObjectList<TMethodInfo>); static;

  end;

implementation

class procedure TParser.ParseFile(const FileName: string;
  out methodsList: TObjectList<TMethodInfo>);

var
  Lines: TStringList;
  line, nextLine: string;
  CurrentMethod: TMethodInfo;
  I, J: Integer;
  signatur: string;
  isSectionSignatur, isSectionMethod: boolean;
  isSectionComment: boolean;
  isSectionVar: boolean;
  isSectionImplementation: boolean;
begin
  isSectionImplementation := false;
  isSectionSignatur := false;
  isSectionComment := false;
  isSectionMethod := false;
  isSectionVar := false;
  signatur := '';

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(FileName);
    CurrentMethod := nil;

    for I := 0 to Lines.Count - 1 do
    begin
      line := Trim(Lines[I]);
      if (Pos('implementation', line) = 1) then
      begin
        isSectionImplementation := true;
        Continue;
      end;

      if (Pos('end.', line) = 1) then
      begin
        Continue;
      end;

      // nix los implementation
      if (line = '') or not isSectionImplementation then
        Continue;

      // Kommentar: do skip
      // Start des Kommentar erkennen
      if IsCommentOf(line) then
      begin
        if (Pos('//', line) = 1) then
          Continue;
        // comment only or (code + comment)
        // comment only
        if GetCodeOnly(line) = line then
        begin
          isSectionComment := true;
          Continue;
        end;
      end;
      // Ende des Kommentar erkennen
      if (isSectionComment and IsCommentOf(line, false)) then
      begin
        isSectionComment := false;
        Continue;
      end;
      if (Pos('//', line) = 1) or isSectionComment then
        Continue;

      ///
      /// isSectionSignatur
      ///
      if MatchString('procedure|function|constructor|destructor', line) then
      begin
        isSectionSignatur := true;
        CurrentMethod := TMethodInfo.Create;
        CurrentMethod.SourceBody.Clear;
        CurrentMethod.Variables.Clear;
        methodsList.Add(CurrentMethod);
      end;

      if (isSectionSignatur and MatchOnlyString('var|begin|const', line.ToLower))
      then
      begin
        isSectionSignatur := false;
        CurrentMethod.signatur := signatur;
        CurrentMethod.Name := GetName(signatur);
        CurrentMethod.LineNumber := inttostr(I);
        signatur := '';
        isSectionMethod := false;
      end;

      if isSectionSignatur then
      begin
        signatur := signatur + line;
        Continue
      end;

      ///
      /// var section
      ///
      if MatchOnlyString('var', line) then
      begin
        isSectionVar := true;
        Continue;
      end;

      if isSectionVar and MatchOnlyString('begin', line) then
      begin
        isSectionVar := false;
        isSectionMethod := true;
      end;

      if Assigned(CurrentMethod) and isSectionVar then
      begin
        CurrentMethod.Variables.Add(line);
        Continue;
      end;

      ///
      /// rest body section
      ///
      if isSectionMethod then
        try
          CurrentMethod.SourceBody.Add(line.ToLower);
        except
          on E: Exception do
            raise;
        end;

      // neue Funktionen braucht das Land
      J := I;
      nextLine := '';
      while (J < Lines.Count) and ((nextLine = '') or (nextLine = 'end.')) do
      begin

        if (J + 1 < Lines.Count) then
          nextLine := Trim(Lines[J + 1])
        else
          nextLine := '';

        Inc(J);
      end;

      if MatchString('procedure|function', nextLine) then
      begin
        isSectionMethod := false;
        CurrentMethod := nil;
      end;

    end;
  finally
    Lines.Free;
  end;
end;

class function TParser.IsCommentOf(const line: string;
  isStart: boolean = true): boolean;
const
  regStart = '(?:\/\/|\{\*|\(\*)';
  regEnd = '\*\)|\*\}';
var
  Regex: TRegEx;
  Match: TMatch;
  regPattern: string;
begin
  regPattern := regEnd;
  if isStart then
    regPattern := regStart;

  Regex := TRegEx.Create(regPattern, [roIgnoreCase]);
  Match := Regex.Match(line.ToLower);
  result := Match.Success;
end;

class function TParser.MatchOnlyString(searchStr: string;
  const line: string): boolean;
var
  Regex: TRegEx;
  Match: TMatch;
begin
  Regex := TRegEx.Create('^' + searchStr + '\s*$', [roIgnoreCase]);
  Match := Regex.Match(line.ToLower);
  result := Match.Success;
end;

class function TParser.MatchString(searchStr: string;
  const line: string): boolean;
var
  Regex: TRegEx;
  Match: TMatch;
begin
  Regex := TRegEx.Create('^\s*(class\s+)?(' + searchStr + ')\s+\w+',
    [roIgnoreCase]);
  Match := Regex.Match(line.ToLower);
  result := Match.Success;
end;

class function TParser.GetName(const line: string): string;
const
  NamePattern = '[function|procedure]\s+(?:\w+\.)?(\w+)\s*';

var
  Regex: TRegEx;
  Match: TMatch;
begin
  Regex := TRegEx.Create(NamePattern, [roIgnoreCase]);
  Match := Regex.Match(line.ToLower);
  if Match.Success then
    result := Match.Groups[1].Value
  else
    result := 'err:)';
end;

class function TParser.GetCodeOnly(const line: string): string;
const
  codePattern = '^(.*?)\s*(?=\/\/|\{\*|\(\*)|$';
var
  Regex: TRegEx;
  Match: TMatch;
begin
  Regex := TRegEx.Create(codePattern);
  Match := Regex.Match(line);

  if Match.Success then
    result := Match.Value
  else
    result := line;
end;

end.

unit uEmptyVisibilitySection;

// Detektor fuer leere Visibility-Sections in Klassen-Bodies.
//
// SonarDelphi-Aequivalent: communitydelphi:EmptyVisibilitySection. Eine
// Klasse mit `public\n private` ohne Member dazwischen ist Refactor-Rest
// (alle public members wurden in andere Sections verschoben). Aufraeumen.
//
// Erkennung: zeilenweiser Scan. Wenn das erste Wort einer Zeile eines
// der Visibility-Keywords ist (`private`, `protected`, `public`,
// `published`, `strict private`, `strict protected`), und das NAECHSTE
// Visibility-Keyword direkt nach Whitespace/Kommentaren folgt (keine
// Felder/Methoden dazwischen), wird gemeldet.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TEmptyVisibilitySectionDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, GroupedDeclaration, LongMethod, MultipleExit, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

function ExtractFirstWord(const Line: string; out StartCol: Integer): string;
var
  i, n, wStart : Integer;
  c            : Char;
begin
  Result := '';
  StartCol := 0;
  n := Length(Line);
  i := 1;
  while (i <= n) and CharInSet(Line[i], [' ', #9]) do Inc(i);
  if i > n then Exit;
  c := Line[i];
  if c = '{' then Exit;
  if (c = '/') and (i < n) and (Line[i + 1] = '/') then Exit;
  if (c = '(') and (i < n) and (Line[i + 1] = '*') then Exit;
  if not CharInSet(c, ['A'..'Z','a'..'z','_']) then Exit;
  wStart := i;
  StartCol := wStart;
  while (i <= n) and CharInSet(Line[i], ['A'..'Z','a'..'z','0'..'9','_']) do
    Inc(i);
  Result := Copy(Line, wStart, i - wStart);
end;

function IsVisibilityKw(const Lower: string): Boolean; inline;
begin
  Result := (Lower = 'private') or (Lower = 'protected')
         or (Lower = 'public')  or (Lower = 'published')
         or (Lower = 'strict');
end;

function IsClassEnderKw(const Lower: string): Boolean; inline;
begin
  Result := (Lower = 'end');
end;

class procedure TEmptyVisibilitySectionDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines       : TStringList;
  Cached      : Boolean;
  i           : Integer;
  Col         : Integer;
  Word        : string;
  Lower       : string;
  LastVis     : string;
  LastVisLine : Integer;
  F           : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    LastVis := '';
    LastVisLine := -1;
    for i := 0 to Lines.Count - 1 do
    begin
      Word := ExtractFirstWord(Lines[i], Col);
      if Word = '' then Continue;
      Lower := LowerCase(Word);
      if IsVisibilityKw(Lower) then
      begin
        if LastVis <> '' then
        begin
          // Vorherige Visibility-Section hatte keine Member-Zeilen
          F            := TLeakFinding.Create;
          F.FileName   := FileName;
          F.MethodName := '';
          F.LineNumber := IntToStr(LastVisLine + 1);
          F.MissingVar := Format(
            'Empty `%s` section - delete the section header or add ' +
            'its members.', [LastVis]);
          F.SetKind(fkEmptyVisibilitySection);
          Results.Add(F);
        end;
        LastVis := Lower;
        LastVisLine := i;
      end
      else if IsClassEnderKw(Lower) then
      begin
        if LastVis <> '' then
        begin
          F            := TLeakFinding.Create;
          F.FileName   := FileName;
          F.MethodName := '';
          F.LineNumber := IntToStr(LastVisLine + 1);
          F.MissingVar := Format(
            'Empty `%s` section at end of class - delete the section ' +
            'header.', [LastVis]);
          F.SetKind(fkEmptyVisibilitySection);
          Results.Add(F);
        end;
        LastVis := '';
        LastVisLine := -1;
      end
      else
      begin
        // Anderer Identifier -> Section hat Inhalt, kein leerer Section
        LastVis := '';
        LastVisLine := -1;
      end;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

unit uConsecutiveVisibility;

// Detektor fuer konsekutive Visibility-Sections mit DERSELBEN Sichtbarkeit:
//   public ... members ... public ... members ...
//
// SonarDelphi-Aequivalent: communitydelphi:ConsecutiveVisibilitySection.
// Anders als `EmptyVisibilitySection` (zwei Visibility-Header ohne
// Member dazwischen): hier sind durchaus Member zwischen den beiden
// Headern, aber beide Header haben dieselbe Sichtbarkeit. Der zweite
// ist also redundant - die Member sollten in einen Block.
//
// Erkennung: zeilenweiser First-Word-Scan ueber die Datei. Stack-frei
// genuegt: pro Klassen-Block (zwischen `class`/`record` und `end`)
// tracken wir die letzte gesehene Visibility. Wenn dieselbe nochmal
// (mit Member dazwischen) auftaucht, melden wir.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TConsecutiveVisibilityDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

function ExtractFirstWord(const Line: string): string;
var
  i, n, wStart : Integer;
  c            : Char;
begin
  Result := '';
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
  while (i <= n) and CharInSet(Line[i], ['A'..'Z','a'..'z','0'..'9','_']) do
    Inc(i);
  Result := Copy(Line, wStart, i - wStart);
end;

function IsVisibilityKw(const Lower: string): Boolean; inline;
begin
  Result := (Lower = 'private') or (Lower = 'protected')
         or (Lower = 'public')  or (Lower = 'published');
end;

class procedure TConsecutiveVisibilityDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines       : TStringList;
  Cached      : Boolean;
  i           : Integer;
  Word, L     : string;
  LastVis     : string;
  HadMembers  : Boolean;
  F           : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    LastVis := '';
    HadMembers := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Word := ExtractFirstWord(Lines[i]);
      if Word = '' then Continue;
      L := LowerCase(Word);
      // `end` beendet Klassen-Block - State zuruecksetzen
      if L = 'end' then
      begin
        LastVis := '';
        HadMembers := False;
        Continue;
      end;
      // `class`/`record` startet einen neuen Block
      if (L = 'class') or (L = 'record') then
      begin
        LastVis := '';
        HadMembers := False;
        Continue;
      end;
      if IsVisibilityKw(L) then
      begin
        if (LastVis = L) and HadMembers then
        begin
          F            := TLeakFinding.Create;
          F.FileName   := FileName;
          F.MethodName := '';
          F.LineNumber := IntToStr(i + 1);
          F.MissingVar := Format(
            'Consecutive `%s` section - merge with the previous %s ' +
            'block (one section header should declare all members).',
            [L, L]);
          F.SetKind(fkConsecutiveVisibility);
          Results.Add(F);
        end;
        LastVis := L;
        HadMembers := False;
      end
      else
      begin
        // Member-Zeile
        if LastVis <> '' then HadMembers := True;
      end;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

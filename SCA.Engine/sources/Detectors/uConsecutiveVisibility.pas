unit uConsecutiveVisibility;

// Detektor fuer konsekutive Visibility-Sections mit DERSELBEN Sichtbarkeit:
//   private FX ...
//   public  procedure Bar ...
//   private FY ...
//
// SonarDelphi-Aequivalent: communitydelphi:ConsecutiveVisibilitySection.
// Sobald innerhalb einer Klasse derselbe Visibility-Header EIN ZWEITES
// MAL auftritt (egal ob direkt benachbart oder durch andere Sections
// getrennt), gilt es als redundant - die Member sollten konsolidiert
// werden.
//
// Abgrenzung zu uEmptyVisibilitySection (SCA087): jenes feuert wenn der
// erste Header gar keine Member hat (`private\nprivate\n...`). Hier feuert
// es nur wenn dieselbe Visibility nach Membern ZURUECK kommt.
//
// Erkennung: zeilenweiser First-Word-Scan. Pro Klassen-Block (zwischen
// `class`/`record` und `end`) tracken wir eine Liste der Visibilities,
// die bereits "Member gesehen haben". Sobald dieselbe wieder auftritt:
// melden.
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

// noinspection-file MultipleExit
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

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

// True wenn nach dem ersten Wort (Visibility-Keyword) noch nicht-leerer
// Inhalt auf der Zeile steht. Faengt den Style ab, in dem Member und
// Visibility auf einer Zeile zusammenstehen: `public procedure A;`
// statt `public\n  procedure A;`. Ohne den Check wuerde der Detektor
// glauben, die Section habe keine Member, und das zweite `public`
// nicht als konsekutiv erkennen.
function LineHasContentAfter(const Line, FirstWord: string): Boolean;
var
  Trimmed, Rest : string;
begin
  Result := False;
  Trimmed := TrimLeft(Line);
  if Length(Trimmed) <= Length(FirstWord) then Exit;
  Rest := TrimLeft(Copy(Trimmed, Length(FirstWord) + 1, MaxInt));
  Result := Rest <> '';
end;

class procedure TConsecutiveVisibilityDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines       : TStringList;
  Cached      : Boolean;
  i           : Integer;
  Word, L     : string;
  SeenVis     : TStringList;
  CurrentVis  : string;
  CurHasMembs : Boolean;
  F           : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  SeenVis := TStringList.Create;
  try
    SeenVis.CaseSensitive := False;
    CurrentVis := '';
    CurHasMembs := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Word := ExtractFirstWord(Lines[i]);
      if Word = '' then Continue;
      L := LowerCase(Word);
      // `end` schliesst Klassen-Block (oder andere) - State zuruecksetzen
      if L = 'end' then
      begin
        SeenVis.Clear;
        CurrentVis := '';
        CurHasMembs := False;
        Continue;
      end;
      if IsVisibilityKw(L) then
      begin
        // Dieselbe Visibility schon mit Membern gesehen?
        if SeenVis.IndexOf(L) >= 0 then
        begin
          F            := TLeakFinding.Create;
          F.FileName   := FileName;
          F.MethodName := '';
          F.LineNumber := IntToStr(i + 1);
          F.MissingVar := Format(
            'Visibility section `%s` already appeared earlier in this ' +
            'class - merge the members into a single %s block.', [L, L]);
          F.SetKind(fkConsecutiveVisibility);
          Results.Add(F);
        end;
        CurrentVis  := L;
        CurHasMembs := False;
        // Same-line Member: `public procedure A;` zaehlt schon als
        // "Member gesehen" - sonst erkennen wir bei `public ...
        // public ...` die Wiederholung nicht.
        if LineHasContentAfter(Lines[i], Word) then
        begin
          if SeenVis.IndexOf(L) < 0 then SeenVis.Add(L);
          CurHasMembs := True;
        end;
      end
      else
      begin
        // Member-Zeile (oder andere Inhaltszeile innerhalb einer Section)
        if (CurrentVis <> '') and not CurHasMembs then
        begin
          if SeenVis.IndexOf(CurrentVis) < 0 then
            SeenVis.Add(CurrentVis);
          CurHasMembs := True;
        end;
      end;
    end;
  finally
    SeenVis.Free;
    ReleaseLines(Lines, Cached);
  end;
end;

end.

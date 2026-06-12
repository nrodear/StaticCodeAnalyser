unit uConsecutiveSection;

// Detektor fuer konsekutive Section-Keywords im Unit/Class-Scope:
// `const X = 1; const Y = 2;` -> sollte `const X = 1; Y = 2;` sein.
//
// SonarDelphi-Aequivalent: communitydelphi:ConsecutiveConstSection,
// :ConsecutiveTypeSection, :ConsecutiveVarSection. Hier zu einer
// Regel zusammengefasst (`fkConsecutiveSection`) - die Section-Art
// steht in der Message.
//
// Erkennung: pro Datei zeilenweiser Scan. Pro Zeile wird das erste Wort
// extrahiert (ignoriert Leading-Whitespace). Wenn das Wort eines von
// `const`/`type`/`var` ist und das ZULETZT GESEHENE `Top-Level-Wort`
// (also non-Whitespace, non-Kommentar) dieselbe Section war, wird
// gemeldet. "Top-Level" heisst hier: andere Section-Opener wie
// `procedure`/`function`/`begin`/`implementation`/`uses`/`type`/`class`
// resetten die "Last-Section"-Variable.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TConsecutiveSectionDetector = class
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

class procedure TConsecutiveSectionDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines       : TStringList;
  Cached      : Boolean;
  i           : Integer;
  Col         : Integer;
  Word        : string;
  Lower       : string;
  LastSection : string;
  IsSectionKw : Boolean;
  IsResetKw   : Boolean;
  F           : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    LastSection := '';
    for i := 0 to Lines.Count - 1 do
    begin
      Word := ExtractFirstWord(Lines[i], Col);
      if Word = '' then Continue;
      Lower := LowerCase(Word);
      IsSectionKw := (Lower = 'const') or (Lower = 'type') or (Lower = 'var');
      IsResetKw := (Lower = 'procedure') or (Lower = 'function')
                or (Lower = 'constructor') or (Lower = 'destructor')
                or (Lower = 'begin') or (Lower = 'end')
                or (Lower = 'implementation') or (Lower = 'interface')
                or (Lower = 'initialization') or (Lower = 'finalization')
                or (Lower = 'uses') or (Lower = 'unit');
      if IsSectionKw then
      begin
        if LastSection = Lower then
        begin
          F            := TLeakFinding.Create;
          F.FileName   := FileName;
          F.MethodName := '';
          F.LineNumber := IntToStr(i + 1);
          F.MissingVar := Format(
            'Consecutive `%s` section - merge with the previous %s ' +
            'block (one section keyword should declare all of them).',
            [Lower, Lower]);
          F.SetKind(fkConsecutiveSection);
          Results.Add(F);
        end;
        LastSection := Lower;
      end
      else if IsResetKw then
        LastSection := '';
      // Andere Worte (Identifier-Deklarationen innerhalb einer Section)
      // aendern LastSection nicht - sonst wuerde `const X = 1; Y = 2; const`
      // beim `Y`-Identifier resetten.
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

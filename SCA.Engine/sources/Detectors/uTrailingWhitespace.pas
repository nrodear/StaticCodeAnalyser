unit uTrailingWhitespace;

// Detektor fuer trailing Whitespace am Zeilenende.
//
// Style-Rule: trailing Space oder Tab am Zeilenende verschmutzt Diffs
// (jeder Editor mit "trim trailing whitespace on save" produziert
// scheinbar leere Aenderungen), bricht Markdown-Tabellen, und kostet
// Bytes. SonarDelphi-Rule communitydelphi:TrailingWhitespace flagged
// dasselbe.
//
// Erkennung: pure Zeilen-Scan. Eine Zeile gilt als "trailing-whitespace-
// dirty" wenn sie nicht-leer ist UND mit Space/Tab endet. Pure leere
// Zeilen (Length=0) sind kein Treffer.
//
// Schweregrad: lsHint - reines Style.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TTrailingWhitespaceDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

function HasTrailingWs(const Line: string; out FirstWsCol: Integer): Boolean;
var
  n : Integer;
  c : Char;
begin
  Result     := False;
  FirstWsCol := 0;
  n := Length(Line);
  if n = 0 then Exit;
  c := Line[n];
  if (c <> ' ') and (c <> #9) then Exit;
  Result := True;
  // Zurueck zum ersten Whitespace-Zeichen der Trailing-Sequenz
  FirstWsCol := n;
  while FirstWsCol > 1 do
  begin
    c := Line[FirstWsCol - 1];
    if (c <> ' ') and (c <> #9) then Break;
    Dec(FirstWsCol);
  end;
end;

class procedure TTrailingWhitespaceDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines    : TStringList;
  i, Col   : Integer;
  F        : TLeakFinding;
  Cached   : Boolean;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    for i := 0 to Lines.Count - 1 do
    begin
      if not HasTrailingWs(Lines[i], Col) then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := Format(
        'Trailing whitespace from column %d - configure editor to ' +
        'trim on save.', [Col]);
      F.SetKind(fkTrailingWhitespace);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

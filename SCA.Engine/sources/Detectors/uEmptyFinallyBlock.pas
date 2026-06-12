unit uEmptyFinallyBlock;

// Detektor fuer leere `finally`-Bloecke in `try..finally..end`.
//
// SonarDelphi-Aequivalent: communitydelphi:EmptyFinallyBlock. Ein leerer
// finally-Block dient meist als Refactor-Rest oder wurde "vergessen
// auszufuellen". Wenn es WIRKLICH nichts zum Aufraeumen gibt, ist
// `try..finally end;` Overhead ohne Funktion - dann reicht der `try`-
// Block alleine (bzw. mit `try..except` wenn Error-Handling benoetigt).
//
// Erkennung: Source kommentbereinigt joinen, dann Pattern `finally` Wort
// gefolgt von nur Whitespace + `end` Wort.
//
// Schweregrad: lsWarning - im Gegensatz zu leerem begin/end ist hier oft
// ein Cleanup-Gedanke vergessen worden.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TEmptyFinallyBlockDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsWarning;

function IsIdent(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

function StripFileComments(Lines: TStringList; out LineForChar: TArray<Integer>): string;
var
  Buf            : TStringBuilder;
  i, n, j        : Integer;
  Line           : string;
  InBlk, InParen : Boolean;
  InStr          : Boolean;
  c              : Char;
  pClose         : Integer;
  Chars          : TList<Integer>;
begin
  Buf := TStringBuilder.Create;
  Chars := TList<Integer>.Create;
  try
    InBlk := False; InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      InStr := False;
      j := 1;
      n := Length(Line);
      while j <= n do
      begin
        if InBlk then
        begin
          pClose := PosEx('}', Line, j);
          if pClose = 0 then Break;
          InBlk := False;
          j := pClose + 1; Continue;
        end;
        if InParen then
        begin
          pClose := PosEx('*)', Line, j);
          if pClose = 0 then Break;
          InParen := False;
          j := pClose + 2; Continue;
        end;
        c := Line[j];
        if InStr then
        begin
          Buf.Append(c); Chars.Add(i);
          if c = '''' then
          begin
            if (j < n) and (Line[j + 1] = '''') then
            begin Buf.Append(''''); Chars.Add(i); Inc(j, 2); end
            else begin InStr := False; Inc(j); end;
          end
          else Inc(j);
          Continue;
        end;
        if c = '''' then
        begin Buf.Append(c); Chars.Add(i); InStr := True; Inc(j); Continue; end;
        if (c = '/') and (j < n) and (Line[j + 1] = '/') then Break;
        if c = '{' then
        begin
          pClose := PosEx('}', Line, j + 1);
          if pClose = 0 then begin InBlk := True; Break; end;
          j := pClose + 1; Continue;
        end;
        if (c = '(') and (j < n) and (Line[j + 1] = '*') then
        begin
          pClose := PosEx('*)', Line, j + 2);
          if pClose = 0 then begin InParen := True; Break; end;
          j := pClose + 2; Continue;
        end;
        Buf.Append(c); Chars.Add(i);
        Inc(j);
      end;
      Buf.Append(#10); Chars.Add(i);
    end;
    Result := Buf.ToString;
    LineForChar := Chars.ToArray;
  finally
    Chars.Free;
    Buf.Free;
  end;
end;

class procedure TEmptyFinallyBlockDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines      : TStringList;
  Cached     : Boolean;
  Code       : string;
  Lwr        : string;
  LineFor    : TArray<Integer>;
  p, q, j    : Integer;
  c          : Char;
  IsEmpty    : Boolean;
  Between    : string;
  LineNumber : Integer;
  F          : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    Code := StripFileComments(Lines, LineFor);
    Lwr := LowerCase(Code);
    p := 1;
    while True do
    begin
      p := PosEx('finally', Lwr, p);
      if p = 0 then Break;
      // Wortgrenzen
      if (p > 1) and IsIdent(Code[p - 1]) then begin Inc(p); Continue; end;
      if (p + 7 <= Length(Code)) and IsIdent(Code[p + 7]) then
      begin Inc(p); Continue; end;
      // Nach `finally` zum `end` springen
      j := p + 7;
      while (j <= Length(Code)) and CharInSet(Code[j], [' ', #9, #10, #13]) do
        Inc(j);
      // `end` Wort?
      if (j + 2 > Length(Code)) then begin Inc(p, 7); Continue; end;
      if SameText(Copy(Code, j, 3), 'end') and
         ((j + 3 > Length(Code)) or not IsIdent(Code[j + 3])) then
      begin
        Between := Copy(Code, p + 7, j - p - 7);
        IsEmpty := True;
        for c in Between do
          if not CharInSet(c, [' ', #9, #10, #13]) then
          begin IsEmpty := False; Break; end;
        if IsEmpty then
        begin
          q := p - 1;
          if (q >= 0) and (q < Length(LineFor)) then
            LineNumber := LineFor[q]
          else
            LineNumber := 0;
          F            := TLeakFinding.Create;
          F.FileName   := FileName;
          F.MethodName := '';
          F.LineNumber := IntToStr(LineNumber + 1);
          // noinspection EmptyFinallyBlock
          // FP: Detector findet 'try..finally end' im Message-String-Literal
          // (StripFileComments strippt nur Kommentare, nicht Strings).
          F.MissingVar := 'Empty `finally` block - either add the missing ' +
            'cleanup or change `try..finally end` to `try ... end`.';
          F.SetKind(fkEmptyFinallyBlock);
          Results.Add(F);
        end;
      end;
      Inc(p, 7);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

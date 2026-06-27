unit uNestedTry;

// Detektor fuer verschachtelte `try`-Bloecke.
//
// SonarDelphi-Aequivalent: communitydelphi:NestedTry. Mehrere try-
// Bloecke in einander zu verschachteln erschwert das Verstaendnis der
// Fehlerbehandlung. In den meisten Faellen lassen sich nested-try-
// Sequenzen durch Extraktion in eine eigene Methode oder durch
// Umstellen der Cleanup-Reihenfolge entkoppeln.
//
// Erkennung: zeilenweise Tokenstream-Scan; tracke "try-depth" als
// Differenz `try` minus `end` Vorkommen (Wortgrenzen!). Wenn ein
// neues `try` gefunden wird waehrend depth >= 1, wird gemeldet.
// Hinweis: andere `end`-Verwendungen (begin/end, case/end, record/end,
// class/end) dekrementieren ebenfalls - das produziert evtl. negative
// Depth-Werte, die wir auf 0 clampen. Auf realem Code laeuft die
// Heuristik akzeptabel.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TNestedTryDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, GroupedDeclaration, IfElseBegin, LongMethod, MultipleExit, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

function IsIdent(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

type
  TTokenKind = (tkTry, tkEnd);
  TTokenHit = record
    Kind : TTokenKind;
    Line : Integer;
    Col  : Integer;
  end;

procedure ScanLineForKeywords(const Line: string; LineNumber: Integer;
  var InBlockComm: Boolean; var InParenStarComm: Boolean;
  Hits: TList<TTokenHit>);
var
  i, n   : Integer;
  InStr  : Boolean;
  pClose : Integer;
  c      : Char;
  Hit    : TTokenHit;
begin
  InStr := False;
  i := 1;
  n := Length(Line);
  while i <= n do
  begin
    if InBlockComm then
    begin
      pClose := PosEx('}', Line, i);
      if pClose = 0 then Exit;
      InBlockComm := False;
      i := pClose + 1; Continue;
    end;
    if InParenStarComm then
    begin
      pClose := PosEx('*)', Line, i);
      if pClose = 0 then Exit;
      InParenStarComm := False;
      i := pClose + 2; Continue;
    end;
    c := Line[i];
    if InStr then
    begin
      if c = '''' then
      begin
        if (i < n) and (Line[i + 1] = '''') then Inc(i, 2)
        else begin InStr := False; Inc(i); end;
      end
      else Inc(i);
      Continue;
    end;
    if c = '''' then begin InStr := True; Inc(i); Continue; end;
    if (c = '/') and (i < n) and (Line[i + 1] = '/') then Exit;
    if c = '{' then
    begin
      pClose := PosEx('}', Line, i + 1);
      if pClose = 0 then begin InBlockComm := True; Exit; end;
      i := pClose + 1; Continue;
    end;
    if (c = '(') and (i < n) and (Line[i + 1] = '*') then
    begin
      pClose := PosEx('*)', Line, i + 2);
      if pClose = 0 then begin InParenStarComm := True; Exit; end;
      i := pClose + 2; Continue;
    end;
    // try Wort
    if CharInSet(c, ['T', 't']) and (i + 2 <= n) and
       SameText(Copy(Line, i, 3), 'try') then
    begin
      if ((i = 1) or not IsIdent(Line[i - 1])) and
         ((i + 3 > n) or not IsIdent(Line[i + 3])) then
      begin
        Hit.Kind := tkTry; Hit.Line := LineNumber; Hit.Col := i;
        Hits.Add(Hit);
        Inc(i, 3); Continue;
      end;
    end;
    // end Wort
    if CharInSet(c, ['E', 'e']) and (i + 2 <= n) and
       SameText(Copy(Line, i, 3), 'end') then
    begin
      if ((i = 1) or not IsIdent(Line[i - 1])) and
         ((i + 3 > n) or not IsIdent(Line[i + 3])) then
      begin
        Hit.Kind := tkEnd; Hit.Line := LineNumber; Hit.Col := i;
        Hits.Add(Hit);
        Inc(i, 3); Continue;
      end;
    end;
    Inc(i);
  end;
end;

class procedure TNestedTryDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines  : TStringList;
  Cached : Boolean;
  Hits   : TList<TTokenHit>;
  InBlk, InParen : Boolean;
  i      : Integer;
  Hit    : TTokenHit;
  Depth  : Integer;
  F      : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  Hits := TList<TTokenHit>.Create;
  try
    InBlk := False; InParen := False;
    for i := 0 to Lines.Count - 1 do
      ScanLineForKeywords(Lines[i], i, InBlk, InParen, Hits);
    Depth := 0;
    for Hit in Hits do
    begin
      case Hit.Kind of
        tkTry:
          begin
            if Depth >= 1 then
            begin
              F            := TLeakFinding.Create;
              F.FileName   := FileName;
              F.MethodName := '';
              F.LineNumber := IntToStr(Hit.Line + 1);
              F.MissingVar := Format(
                'Nested `try` block at column %d - consider extracting ' +
                'the inner try into its own method.', [Hit.Col]);
              F.SetKind(fkNestedTry);
              Results.Add(F);
            end;
            Inc(Depth);
          end;
        tkEnd:
          if Depth > 0 then Dec(Depth);
      end;
    end;
  finally
    Hits.Free;
    ReleaseLines(Lines, Cached);
  end;
end;

end.

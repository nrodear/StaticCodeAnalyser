unit uRdxCodeMap;

// reDelphix - Code-Sicht einer Datei und Token-Leser darauf, OHNE ToolsAPI.
// Gemeinsame Grundlage der Planer (uRdxSimpleFixes), der Unterdrueck-Hilfen
// (uRdxSuppress) und des Laeufers (uRdxRecipeRunner); bis 2026-10-10 lag sie
// in uRdxSimpleFixes, und uRdxSuppress zog dafuer die Planer mit (Review
// reDelphiX nach Bereichen, Minor 7).
//
// Verhaeltnis zum Core: TDetectorUtils.ScanCodeLine ist dieselbe Regel fuer
// Kommentare und einzeilige Strings - uTestRdxCodeMap prueft beide an
// denselben Eingaben gegeneinander. Unterschied mit Absicht: die Code-Sicht
// kennt die mehrzeiligen Strings von Delphi 12 (''' ... '''), ScanCodeLine
// nicht; der Core fuehrt diese Regel als
// TRefactorInfoBuilder.OpensMultiLineString.

interface

uses
  System.SysUtils, System.Classes;

const
  MIN_MULTI_QUOTES = 3;   // ''' oeffnet einen mehrzeiligen String (Delphi 12)

type
  // Zeichenklassen einer Datei, spaltentreu: 'c' Code, 's' String-Literal,
  // 'k' Kommentar oder Direktive ({...}, (*...*), //...). Block-Kommentare
  // und mehrzeilige Strings werden ueber Zeilen verfolgt, einfache Strings
  // enden mit der Zeile.
  TRdxCodeMap = class
  private
    FLines   : TStrings;
    FClass   : TArray<string>;
    FSlash   : TArray<Integer>;   // je Zeile: Spalte des '//'-Kommentars, 0 = keiner
    FInside  : TArray<Boolean>;   // je Zeile: beginnt in Block-Kommentar oder mehrzeiligem String
    // Zustand nur waehrend des Aufbaus (Create): die Zeile, ihre Klassen
    // und was gerade offen ist.
    FText    : string;
    FKinds   : string;
    FInBrace : Boolean;
    FInParen : Boolean;
    FInStr   : Boolean;
    FMulti   : Integer;   // offener mehrzeiliger String: Zahl seiner Quotes, 0 = keiner
    // Je ein Schritt ab Spalte j der Zeile FText; liefern die Spalte dahinter.
    function StepComment(j: Integer): Integer;
    function StepString(j: Integer): Integer;
    function StepQuote(j: Integer): Integer;
    function StepCode(ALineIdx, j: Integer): Integer;
    // Zeilenanfang in einem mehrzeiligen String.
    function StepMultiLine: Integer;
  public
    constructor Create(ALines: TStrings);
    // Zahl der Zeilen der Datei.
    function LineCount: Integer;
    // Rohzeile ALine (1-basiert), '' ausserhalb.
    function Raw(ALine: Integer): string;
    // Klasse des Zeichens (ALine, ACol); ' ' ausserhalb der Zeile.
    function ClassAt(ALine, ACol: Integer): Char;
    // True, wenn (ALine, ACol) Code ist - kein String, kein Kommentar.
    function IsCode(ALine, ACol: Integer): Boolean;
    // Kommentar oder Direktive in ALine zwischen AFrom..ATo.
    function HasComment(ALine, AFrom, ATo: Integer): Boolean;
    // String, Kommentar oder Direktive in ALine zwischen AFrom..ATo.
    function HasNonCode(ALine, AFrom, ATo: Integer): Boolean;
    // Spalte, an der in ALine ein '//'-Kommentar BEGINNT (aus Code heraus,
    // nicht in einem String, {...} oder (*...*)); 0 = keiner.
    function LineCommentCol(ALine: Integer): Integer;
    // True, wenn ALine IN einem Block-Kommentar ({...}, (*...*)) oder
    // mehrzeiligen String beginnt, der in einer frueheren Zeile anfing.
    // Eine Zeile, die man davor einfuegt, laege dann ebenfalls darin.
    function StartsInside(ALine: Integer): Boolean;
  end;

  // Ein Code-Token: Bezeichner/Schluesselwort (klein in Low), Zahl, oder
  // ein Satzzeichen (':=', '<>', '<=', '>=', '..' als eines).
  TRdxToken = record
    Line : Integer;
    Col  : Integer;   // erstes Zeichen
    Len  : Integer;
    Low  : string;    // klein geschrieben
    function IsWord: Boolean;
    function EndCol: Integer;   // hinter dem letzten Zeichen
  end;

function IsIdentStart(C: Char): Boolean;
function IsIdentChar(C: Char): Boolean;
function IsBlank(C: Char): Boolean;
// Erste Spalte ab AFrom, die kein Leerzeichen/Tab ist (Length + 1 am Ende).
function SkipBlanks(const S: string; AFrom: Integer): Integer;
// Zahl der Quotes ab S[AAt] in Folge.
function QuoteRun(const S: string; AAt: Integer): Integer;

// Das Token, das an (ALine, ACol) beginnt (Code vorausgesetzt).
function TokenAt(AMap: TRdxCodeMap; ALine, ACol: Integer): TRdxToken;
// Naechstes Code-Token ab (ALine, ACol) einschliesslich - ueber Leerraum,
// Strings, Kommentare und Zeilen hinweg; Low = '' am Dateiende.
function NextToken(AMap: TRdxCodeMap; ALine, ACol: Integer): TRdxToken;
// Token unmittelbar nach ATok.
function After(AMap: TRdxCodeMap; const ATok: TRdxToken): TRdxToken;
// Das Token, das an (ALine, ACol) ENDET (Code, kein Leerraum).
function TokenEndingAt(AMap: TRdxCodeMap; ALine, ACol: Integer): TRdxToken;
// Vorheriges Code-Token vor (ALine, ACol) ausschliesslich.
function PrevToken(AMap: TRdxCodeMap; ALine, ACol: Integer): TRdxToken;
// Vor ATok.
function Before(AMap: TRdxCodeMap; const ATok: TRdxToken): TRdxToken;

implementation

// Zeichen > #127 wie der Core (uRefactorInfoBuilder) und uRdxRecipes:
// Bezeichner mit Umlaut sind in Delphi erlaubt - sonst lehnten die Planer
// 'Uebersicht.Free' mit einem falschen Grund ab (Review nach Bereichen
// 2026-10-10, Nit 17).
function IsIdentStart(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_']) or (C > #127);
end;

function IsIdentChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (C > #127);
end;

function IsBlank(C: Char): Boolean;
begin
  Result := CharInSet(C, [' ', #9]);
end;

function SkipBlanks(const S: string; AFrom: Integer): Integer;
begin
  Result := AFrom;
  while (Result <= Length(S)) and IsBlank(S[Result]) do
    Inc(Result);
end;

function QuoteRun(const S: string; AAt: Integer): Integer;
begin
  Result := 0;
  while (AAt + Result <= Length(S)) and (S[AAt + Result] = '''') do
    Inc(Result);
end;

{ TRdxCodeMap }

constructor TRdxCodeMap.Create(ALines: TStrings);
var
  i, j : Integer;
begin
  inherited Create;
  FLines := ALines;
  SetLength(FClass, ALines.Count);
  SetLength(FSlash, ALines.Count);
  SetLength(FInside, ALines.Count);
  FInBrace := False;
  FInParen := False;
  FMulti   := 0;
  for i := 0 to ALines.Count - 1 do
  begin
    FInside[i] := FInBrace or FInParen or (FMulti > 0);
    FText  := ALines[i];
    FKinds := '';
    SetLength(FKinds, Length(FText));
    FInStr := False;
    j := 1;
    if FMulti > 0 then
      j := StepMultiLine;
    while j <= Length(FText) do
      if FInBrace or FInParen then
        j := StepComment(j)
      else if FInStr then
        j := StepString(j)
      else
        j := StepCode(i, j);
    FClass[i] := FKinds;
  end;
  FText  := '';
  FKinds := '';
end;

function TRdxCodeMap.StepComment(j: Integer): Integer;
begin
  FKinds[j] := 'k';
  Result := j + 1;
  if FInBrace then
  begin
    if FText[j] = '}' then FInBrace := False;
  end
  else if (FText[j] = '*') and (j < Length(FText)) and (FText[j + 1] = ')') then
  begin
    FKinds[j + 1] := 'k';
    FInParen := False;
    Result := j + 2;
  end;
end;

function TRdxCodeMap.StepString(j: Integer): Integer;
begin
  FKinds[j] := 's';
  Result := j + 1;
  if FText[j] <> '''' then Exit;
  if (j < Length(FText)) and (FText[j + 1] = '''') then
  begin
    FKinds[j + 1] := 's';   // verdoppeltes '' im String
    Result := j + 2;
  end
  else
    FInStr := False;
end;

// Ein Quote im Code: Anfang eines Strings. Eine ungerade Zahl von
// mindestens drei Quotes am Zeilenende beginnt einen mehrzeiligen String
// (Delphi 12: ''' ... ''') - der endet erst in der Zeile, die mit
// derselben Zahl Quotes beginnt.
function TRdxCodeMap.StepQuote(j: Integer): Integer;
var
  q, k : Integer;
begin
  q := QuoteRun(FText, j);
  if (q >= MIN_MULTI_QUOTES) and Odd(q)
     and (SkipBlanks(FText, j + q) > Length(FText)) then
  begin
    FMulti := q;
    for k := j to Length(FText) do
      FKinds[k] := 's';
    Exit(Length(FText) + 1);
  end;
  FKinds[j] := 's';
  FInStr := True;
  Result := j + 1;
end;

function TRdxCodeMap.StepMultiLine: Integer;
var
  k, Start : Integer;
begin
  Start := SkipBlanks(FText, 1);
  if QuoteRun(FText, Start) = FMulti then
  begin
    FMulti := 0;   // schliessende Quotes; dahinter wieder Code
    Result := Start + QuoteRun(FText, Start);
  end
  else
    Result := Length(FText) + 1;
  for k := 1 to Result - 1 do
    FKinds[k] := 's';
end;

function TRdxCodeMap.StepCode(ALineIdx, j: Integer): Integer;
var
  n, k : Integer;
begin
  n := Length(FText);
  Result := j + 1;
  if FText[j] = '''' then
    Result := StepQuote(j)
  else if (FText[j] = '/') and (j < n) and (FText[j + 1] = '/') then
  begin
    // Zeilenkommentar: der Rest der Zeile.
    FSlash[ALineIdx] := j;
    for k := j to n do
      FKinds[k] := 'k';
    Result := n + 1;
  end
  else if FText[j] = '{' then
  begin
    FKinds[j] := 'k';
    FInBrace := True;
  end
  else if (FText[j] = '(') and (j < n) and (FText[j + 1] = '*') then
  begin
    FKinds[j] := 'k';
    FKinds[j + 1] := 'k';
    FInParen := True;
    Result := j + 2;
  end
  else
    FKinds[j] := 'c';
end;

function TRdxCodeMap.LineCount: Integer;
begin
  Result := FLines.Count;
end;

function TRdxCodeMap.Raw(ALine: Integer): string;
begin
  if (ALine < 1) or (ALine > FLines.Count) then
    Exit('');
  Result := FLines[ALine - 1];
end;

function TRdxCodeMap.ClassAt(ALine, ACol: Integer): Char;
begin
  Result := ' ';
  if (ALine < 1) or (ALine > Length(FClass)) then Exit;
  if (ACol < 1) or (ACol > Length(FClass[ALine - 1])) then Exit;
  Result := FClass[ALine - 1][ACol];
end;

function TRdxCodeMap.IsCode(ALine, ACol: Integer): Boolean;
begin
  Result := ClassAt(ALine, ACol) = 'c';
end;

function TRdxCodeMap.HasComment(ALine, AFrom, ATo: Integer): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := AFrom to ATo do
    if ClassAt(ALine, i) = 'k' then
      Exit(True);
end;

function TRdxCodeMap.HasNonCode(ALine, AFrom, ATo: Integer): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := AFrom to ATo do
    if CharInSet(ClassAt(ALine, i), ['k', 's']) then
      Exit(True);
end;

function TRdxCodeMap.LineCommentCol(ALine: Integer): Integer;
begin
  Result := 0;
  if (ALine >= 1) and (ALine <= Length(FSlash)) then
    Result := FSlash[ALine - 1];
end;

function TRdxCodeMap.StartsInside(ALine: Integer): Boolean;
begin
  Result := (ALine >= 1) and (ALine <= Length(FInside)) and FInside[ALine - 1];
end;

{ TRdxToken }

function TRdxToken.IsWord: Boolean;
begin
  Result := (Low <> '') and IsIdentStart(Low[1]);
end;

function TRdxToken.EndCol: Integer;
begin
  Result := Col + Len;
end;

{ ---- Token-Lesen auf der Code-Sicht ---- }

function TokenAt(AMap: TRdxCodeMap; ALine, ACol: Integer): TRdxToken;
var
  L    : string;
  j    : Integer;
  Two  : string;
begin
  Result := Default(TRdxToken);
  Result.Line := ALine;
  Result.Col  := ACol;
  L := AMap.Raw(ALine);
  if IsIdentStart(L[ACol]) then
  begin
    j := ACol;
    while (j <= Length(L)) and IsIdentChar(L[j]) and AMap.IsCode(ALine, j) do
      Inc(j);
    Result.Len := j - ACol;
  end
  else if CharInSet(L[ACol], ['0'..'9']) then
  begin
    j := ACol;
    while (j <= Length(L)) and IsIdentChar(L[j]) do Inc(j);
    Result.Len := j - ACol;
  end
  else
  begin
    Two := Copy(L, ACol, 2);
    if ((Two = ':=') or (Two = '<>') or (Two = '<=') or (Two = '>=')
        or (Two = '..')) and AMap.IsCode(ALine, ACol + 1) then
      Result.Len := 2
    else
      Result.Len := 1;
  end;
  Result.Low := LowerCase(Copy(L, ACol, Result.Len));
end;

function NextToken(AMap: TRdxCodeMap; ALine, ACol: Integer): TRdxToken;
var
  Li, Co : Integer;
begin
  Li := ALine;
  Co := ACol;
  while Li <= AMap.LineCount do
  begin
    while Co <= Length(AMap.Raw(Li)) do
    begin
      if AMap.IsCode(Li, Co) and not IsBlank(AMap.Raw(Li)[Co]) then
        Exit(TokenAt(AMap, Li, Co));
      Inc(Co);
    end;
    Inc(Li);
    Co := 1;
  end;
  Result := Default(TRdxToken);
end;

function After(AMap: TRdxCodeMap; const ATok: TRdxToken): TRdxToken;
begin
  Result := NextToken(AMap, ATok.Line, ATok.EndCol);
end;

function TokenEndingAt(AMap: TRdxCodeMap; ALine, ACol: Integer): TRdxToken;
var
  L : string;
  S : Integer;
begin
  L := AMap.Raw(ALine);
  if IsIdentChar(L[ACol]) then
  begin
    S := ACol;
    while (S > 1) and IsIdentChar(L[S - 1]) and AMap.IsCode(ALine, S - 1) do
      Dec(S);
    Exit(TokenAt(AMap, ALine, S));
  end;
  // Zwei-Zeichen-Operator, der hier endet?
  if (ACol > 1) and AMap.IsCode(ALine, ACol - 1) then
  begin
    Result := TokenAt(AMap, ALine, ACol - 1);
    if Result.Len = 2 then Exit;
  end;
  Result := TokenAt(AMap, ALine, ACol);
end;

function PrevToken(AMap: TRdxCodeMap; ALine, ACol: Integer): TRdxToken;
var
  Li, Co : Integer;
  L      : string;
begin
  Li := ALine;
  Co := ACol - 1;
  while Li >= 1 do
  begin
    L := AMap.Raw(Li);
    if Co > Length(L) then Co := Length(L);
    while Co >= 1 do
    begin
      if AMap.IsCode(Li, Co) and not IsBlank(L[Co]) then
        Exit(TokenEndingAt(AMap, Li, Co));
      Dec(Co);
    end;
    Dec(Li);
    Co := MaxInt;
  end;
  Result := Default(TRdxToken);
end;

function Before(AMap: TRdxCodeMap; const ATok: TRdxToken): TRdxToken;
begin
  Result := PrevToken(AMap, ATok.Line, ATok.Col);
end;

end.

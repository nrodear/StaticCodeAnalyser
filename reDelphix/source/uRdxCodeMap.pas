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
  System.Classes;   // TStrings

const
  MIN_MULTI_QUOTES = 3;   // ''' oeffnet einen mehrzeiligen String (Delphi 12)
  // Token, die ein eigenes 'end' brauchen - die end-Bilanzen der Planer
  // (uRdxStructFixes, uRdxLineFixes; bis 2026-10-10 je eine Kopie).
  END_OPENERS: array[0..4] of string = ('begin', 'case', 'try', 'asm',
    'record');
  // Hinter diesen Token ist ein Wort ein Bezeichner ('&End', '@@End',
  // 'X.Then').
  IDENT_PREFIXES: array[0..2] of string = ('&', '@', '.');
  // Token vor dem Anfang einer Anweisung (uRdxStructFixes: steht vor dem
  // if etwas anderes, ist es ein bedingter Ausdruck; uRdxRaiseFixes:
  // 'EFoo.Create(..)' als ganze Anweisung).
  STATEMENT_PREV: array[0..11] of string = (';', 'begin', 'then', 'else',
    'do', 'try', 'finally', 'except', 'repeat', ':', 'initialization',
    'finalization');

type
  // Zeichenklassen einer Datei, spaltentreu: 'c' Code, 's' String-Literal,
  // 'k' Kommentar oder Direktive ({...}, (*...*), //...). Block-Kommentare
  // und mehrzeilige Strings werden ueber Zeilen verfolgt, einfache Strings
  // enden mit der Zeile.
  // LEBENSDAUER (Review Quick-Fix-Units 2026-10-14): die Map LEIHT ALines -
  // die Klassen entstehen einmal in Create (Schnappschuss), Raw() und
  // LineCount lesen dagegen live aus ALines. ALines muss darum laenger
  // leben als die Map und darf waehrend ihrer Lebensdauer nicht veraendert
  // werden; sonst passen Klassen und Text nicht mehr zusammen, und die
  // Planer lesen Code, wo ein Kommentar steht. Die Aufrufer (uRdxProvider,
  // uRdxRecipeRunner, die Tests) bauen die Map je Lauf neu.
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
    // Liest ALines einmal und klassifiziert jedes Zeichen; ALines bleibt im
    // Besitz des Aufrufers (s. LEBENSDAUER oben).
    constructor Create(ALines: TStrings);
    // Zahl der Zeilen der Datei (live aus ALines).
    function LineCount: Integer;
    // Rohzeile ALine (1-basiert, live aus ALines), '' ausserhalb.
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

  // Ein Schritt einer Token-Suche der Planer: weiter, gefunden, abbrechen.
  TRdxStep = (rsGoOn, rsFound, rsStop);

  // Ein Code-Token: Bezeichner/Schluesselwort (klein in Low), Zahl, oder
  // ein Satzzeichen (':=', '<>', '<=', '>=', '..' als eines). Low = '' ist
  // "kein Token" (Dateiende, nicht gefunden; Default(TRdxToken)).
  TRdxToken = record
    Line : Integer;
    Col  : Integer;   // erstes Zeichen
    Len  : Integer;
    Low  : string;    // klein geschrieben
    // True fuer einen Bezeichner oder ein Schluesselwort (Low beginnt mit
    // einem Bezeichner-Anfangszeichen) - nicht fuer Zahl, Satzzeichen oder
    // "kein Token". Ob das Wort ein Schluesselwort ist, sagt erst der
    // Kontext (IsKeywordAfter, die KEYWORDS der Planer).
    function IsWord: Boolean;
    function EndCol: Integer;   // hinter dem letzten Zeichen
  end;

  // Praedikat einer Token-Suche auf einer Zeile (OneTokenOnLine): passt T?
  // AArg ist der Suchbegriff des Aufrufers (ein Name, ein Ziel), '' ohne.
  // Das Token davor holt sich ein Praedikat selbst (Before) - eine plaine
  // Funktion, weil FPC 3.2 keine Funktionsreferenzen kennt.
  TRdxTokenTest = function(AMap: TRdxCodeMap; const T: TRdxToken;
    const AArg: string): Boolean;

  // Eine Token-Suche auf einer Zeile (OneTokenOnLine): das Praedikat, sein
  // Argument und die Texte der Gruende - What ist, was fehlt ('kein begin',
  // 'keine Selbstzuweisung "x := x"'), ManyFmt der Text der Mehrdeutigkeit
  // mit %d fuer die Zahl der Treffer ('%d begin', '%d-mal "end else"').
  // Bis Charge R8 (2026-10-14) stand diese Suche siebenmal in den Planern.
  TRdxLineSearch = record
    Test    : TRdxTokenTest;
    Arg     : string;
    What    : string;
    ManyFmt : string;
  end;

  // Haken der end-Bilanz (BlockEnd): je Token, das weder Oeffner noch end
  // ist, mit dem Token davor und der Tiefe (1 = oberste Ebene des Blocks);
  // liefert den Grund, die Bilanz abzubrechen, oder ''.
  TRdxBlockHook = function(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
    ADepth: Integer): string;

// Bezeichner-Zeichen wie im Core (TRefactorInfoBuilder): Buchstabe, '_'
// oder ein Zeichen ueber #127 (Umlaute sind in Delphi-Bezeichnern erlaubt)
// beginnt einen Bezeichner, dazu Ziffern darin. Zahlen beginnen NICHT mit
// IsIdentStart - so trennt TokenAt Zahl und Wort.
function IsIdentStart(C: Char): Boolean;
function IsIdentChar(C: Char): Boolean;
// Leerzeichen oder Tab - der Leerraum, den die Planer ueberspringen
// (andere Steuerzeichen stehen in einer Zeile nicht, Zeilenenden kennt die
// Map nicht).
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

// Beginnt an (ALine, ACol) eine Compiler-Direktive ('{$' oder '(*$')? Die
// Code-Sicht fuehrt Direktiven als Kommentar ('k'); '{$' in einem
// '//'-Kommentar ist keine (Gegen-Review SCA101, Nit 6).
function DirectiveAt(AMap: TRdxCodeMap; ALine, ACol: Integer): Boolean;
// Beginnt zwischen (AFromLine, 1) und dem Token ATo eine Direktive? Bis
// Dateiende, wenn ATo leer ist.
function DirectiveBefore(AMap: TRdxCodeMap; AFromLine: Integer;
  const ATo: TRdxToken): Boolean;
// Eine Direktive (DirectiveAt) in den Zeilen AFrom..ATo? Bis Charge R8
// (2026-10-14) je eine Kopie in uRdxLineFixes, uRdxDeclFixes und
// uRdxStructFixes.
function DirectiveInLines(AMap: TRdxCodeMap; AFrom, ATo: Integer): Boolean;

// ---- Geteilte Laeufe der Planer (Charge R8, 2026-10-14: bis dahin je
// Planer eine Kopie - Klammerabgleich 4x, "genau ein Token" 7x, end-Bilanz
// 3x). ----

// Die schliessende Klammer zu AOpen - '(' zu ')', '[' zu ']', '<' zu '>' -
// ab AOpen gezaehlt, nur die eigene Klammerart, ueber Zeilen hinweg; Low =
// '' ohne (auch, wenn AOpen keine dieser Klammern ist). AMaxLines begrenzt
// die Suche auf die Zeilen bis AOpen.Line + AMaxLines (0 = nur die Zeile
// von AOpen).
function MatchClose(AMap: TRdxCodeMap; const AOpen: TRdxToken;
  AMaxLines: Integer = MaxInt): TRdxToken;
// Das Token hinter der schliessenden Klammer zu AOpen (MatchClose); Low =
// '' ohne Klammer oder am Dateiende.
function AfterClose(AMap: TRdxCodeMap; const AOpen: TRdxToken): TRdxToken;

// Genau ein Code-Token auf ALine, auf das ASearch.Test passt: '' und das
// Token in AHit; sonst der Grund (OneTokenReason; AHit ist dann der letzte
// Treffer oder leer). Die Planer lehnen so Funde ab, deren Zeile verschoben
// (kein Treffer) oder mehrdeutig (mehrere) ist.
function OneTokenOnLine(AMap: TRdxCodeMap; ALine: Integer;
  const ASearch: TRdxLineSearch; out AHit: TRdxToken): string;
// Der Grund zu ACount Treffern auf ALine: 0 -> '<AWhat> auf der
// gemeldeten Zeile - Zeile verschoben? Datei neu pruefen'; mehr als 1 ->
// 'Zeile N traegt <AManyFmt mit ACount> - mehrdeutig'; genau 1 -> ''.
function OneTokenReason(ALine, ACount: Integer;
  const AWhat, AManyFmt: string): string;

// Die end-Bilanz vorwaerts ab hinter AFrom (dem Oeffner bzw. dem else einer
// Anweisungsliste): END_OPENERS als Schluesselwort zaehlen hoch, 'end'
// herunter ('&End', '@@End', 'X.End' sind Bezeichner, IsKeywordAfter). Das
// end, das die Bilanz schliesst, kommt nach AEnd, das Token davor nach
// ALast; beide leer, wenn keines kommt. AHook (nil = keiner) sieht jedes
// andere Token und kann mit einem Grund abbrechen - der ist dann das
// Ergebnis, sonst ''.
function BlockEnd(AMap: TRdxCodeMap; const AFrom: TRdxToken;
  AHook: TRdxBlockHook; out AEnd, ALast: TRdxToken): string;

// ALow ist eines der Woerter in AList (gleich geschrieben).
function InList(const ALow: string; const AList: array of string): Boolean;
// Ein Wort als Schluesselwort - nicht hinter '&', '@' oder '.' (APrev).
function IsKeywordAfter(const T, APrev: TRdxToken): Boolean;
// ALow oeffnet einen Block mit eigenem 'end' (END_OPENERS).
function IsEndOpener(const ALow: string): Boolean;
// Eine Einrueckstufe: was ADeeperLine ueber AIndent hinaus einrueckt;
// sonst ein Tab, wenn AIndent Tabs traegt, oder zwei Leerzeichen.
function IndentStep(const AIndent, ADeeperLine: string): string;
// 'at column N' aus einer Meldung; 0 = nicht vorhanden. Bis 2026-10-10 in
// uRdxSimpleFixes, seit SCA101 auch fuer uRdxStructFixes.
function ColumnFromMessage(const AMessage: string): Integer;

implementation

uses
  System.SysUtils;   // CharInSet, LowerCase, Format

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

function DirectiveAt(AMap: TRdxCodeMap; ALine, ACol: Integer): Boolean;
var
  L     : string;
  Slash : Integer;
begin
  L := AMap.Raw(ALine);
  Slash := AMap.LineCommentCol(ALine);
  Result := (AMap.ClassAt(ALine, ACol) = 'k')
    and ((Slash = 0) or (ACol < Slash))
    and ((Copy(L, ACol, 2) = '{$') or (Copy(L, ACol, 3) = '(*$'));
end;

function DirectiveBefore(AMap: TRdxCodeMap; AFromLine: Integer;
  const ATo: TRdxToken): Boolean;
var
  Li, Co, Last, Stop : Integer;
begin
  Result := False;
  Last := AMap.LineCount;
  if ATo.Low <> '' then
    Last := ATo.Line;
  for Li := AFromLine to Last do
  begin
    Stop := Length(AMap.Raw(Li));
    if (ATo.Low <> '') and (Li = ATo.Line) then
      Stop := ATo.Col - 1;
    for Co := 1 to Stop do
      if DirectiveAt(AMap, Li, Co) then
        Exit(True);
  end;
end;

function DirectiveInLines(AMap: TRdxCodeMap; AFrom, ATo: Integer): Boolean;
var
  Li, Co : Integer;
begin
  Result := False;
  for Li := AFrom to ATo do
    for Co := 1 to Length(AMap.Raw(Li)) do
      if DirectiveAt(AMap, Li, Co) then
        Exit(True);
end;

// Die Klammerart zu einer oeffnenden Klammer; '' fuer alles andere.
function CloserOf(const AOpenLow: string): string;
begin
  if AOpenLow = '(' then
    Result := ')'
  else if AOpenLow = '[' then
    Result := ']'
  else if AOpenLow = '<' then
    Result := '>'
  else
    Result := '';
end;

function MatchClose(AMap: TRdxCodeMap; const AOpen: TRdxToken;
  AMaxLines: Integer): TRdxToken;
var
  Close : string;
  Depth : Integer;
  T     : TRdxToken;
begin
  Result := Default(TRdxToken);
  Close := CloserOf(AOpen.Low);
  if Close = '' then Exit;
  Depth := 0;
  T := AOpen;
  // T.Line - AOpen.Line statt AOpen.Line + AMaxLines: MaxInt als Vorgabe
  // liefe sonst ueber.
  while (T.Low <> '') and (T.Line - AOpen.Line <= AMaxLines) do
  begin
    if T.Low = AOpen.Low then
      Inc(Depth)
    else if T.Low = Close then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit(T);
    end;
    T := After(AMap, T);
  end;
end;

function AfterClose(AMap: TRdxCodeMap; const AOpen: TRdxToken): TRdxToken;
var
  Close : TRdxToken;
begin
  Result := Default(TRdxToken);
  Close := MatchClose(AMap, AOpen);
  if Close.Low <> '' then
    Result := After(AMap, Close);
end;

function OneTokenReason(ALine, ACount: Integer;
  const AWhat, AManyFmt: string): string;
begin
  Result := '';
  if ACount = 0 then
    Result := Format('%s auf der gemeldeten Zeile - Zeile verschoben? Datei '
      + 'neu pruefen', [AWhat])
  else if ACount > 1 then
    Result := Format('Zeile %d traegt %s - mehrdeutig',
      [ALine, Format(AManyFmt, [ACount])]);
end;

function OneTokenOnLine(AMap: TRdxCodeMap; ALine: Integer;
  const ASearch: TRdxLineSearch; out AHit: TRdxToken): string;
var
  T : TRdxToken;
  n : Integer;
begin
  AHit := Default(TRdxToken);
  n := 0;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if ASearch.Test(AMap, T, ASearch.Arg) then
    begin
      Inc(n);
      AHit := T;
    end;
    T := After(AMap, T);
  end;
  Result := OneTokenReason(ALine, n, ASearch.What, ASearch.ManyFmt);
end;

function BlockEnd(AMap: TRdxCodeMap; const AFrom: TRdxToken;
  AHook: TRdxBlockHook; out AEnd, ALast: TRdxToken): string;
var
  T, Prev : TRdxToken;
  Depth   : Integer;
begin
  Result := '';
  AEnd := Default(TRdxToken);
  ALast := Default(TRdxToken);
  Depth := 1;
  Prev := AFrom;
  T := After(AMap, AFrom);
  while T.Low <> '' do
  begin
    if IsKeywordAfter(T, Prev) and IsEndOpener(T.Low) then
      Inc(Depth)
    else if IsKeywordAfter(T, Prev) and (T.Low = 'end') then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        AEnd := T;
        ALast := Prev;
        Exit;
      end;
    end
    else if Assigned(AHook) then
    begin
      Result := AHook(AMap, T, Prev, Depth);
      if Result <> '' then Exit;
    end;
    Prev := T;
    T := After(AMap, T);
  end;
end;

function InList(const ALow: string; const AList: array of string): Boolean;
var
  S : string;
begin
  Result := False;
  for S in AList do
    if ALow = S then
      Exit(True);
end;

function IsKeywordAfter(const T, APrev: TRdxToken): Boolean;
begin
  Result := T.IsWord and not InList(APrev.Low, IDENT_PREFIXES);
end;

function IsEndOpener(const ALow: string): Boolean;
begin
  Result := InList(ALow, END_OPENERS);
end;

function IndentStep(const AIndent, ADeeperLine: string): string;
var
  Deeper : string;
begin
  Deeper := Copy(ADeeperLine, 1, SkipBlanks(ADeeperLine, 1) - 1);
  if (Length(Deeper) > Length(AIndent))
     and (Copy(Deeper, 1, Length(AIndent)) = AIndent) then
    Exit(Copy(Deeper, Length(AIndent) + 1, MaxInt));
  Result := '  ';
  if Pos(#9, AIndent) > 0 then
    Result := #9;
end;

function ColumnFromMessage(const AMessage: string): Integer;
const
  KEY = 'at column ';
var
  p, i : Integer;
begin
  Result := 0;
  p := Pos(KEY, AMessage);
  if p = 0 then Exit;
  i := p + Length(KEY);
  while (i <= Length(AMessage)) and CharInSet(AMessage[i], ['0'..'9']) do
  begin
    Result := Result * 10 + Ord(AMessage[i]) - Ord('0');
    Inc(i);
  end;
end;

end.

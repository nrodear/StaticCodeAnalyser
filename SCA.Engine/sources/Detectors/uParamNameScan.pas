unit uParamNameScan;

// SCA199 ParamNameMismatch - der reine Scanner, ohne AST und ohne Datei.
//
// Eingabe ist der Quelltext EINER Routine (Kopfzeile bis Rumpfende), die
// Ausgabe die Unstimmigkeiten zwischen den Platzhaltern im SQL einer
// Query und den Parameter-Zugriffen auf dieselbe Query:
//
//   (a) Q.ParamByName('x') - aber das SQL, das diese Routine Q gibt, hat
//       kein :x. Das ist zur Laufzeit "Parameter 'x' not found" (FireDAC,
//       BDE, dbExpress, UniDAC, Zeos, ADO-Parameters). Meist ein Tippfehler
//       oder ein Platzhalter, der beim Umbau des SQL umbenannt wurde.
//   (b) Das SQL hat :y, die Routine weist Q aber nirgends 'y' zu, obwohl
//       sie andere Parameter von Q setzt. Ausfuehren scheitert dann mit
//       einem ungebundenen Parameter (FireDAC: Datentyp unbekannt, Oracle:
//       ORA-01008) oder bindet still NULL.
//
// Die Regel ist bewusst schweigsam. Sie urteilt nur, wenn sie das SQL der
// Query in dieser Routine VOLLSTAENDIG aus Literalen kennt:
//
//   * Q entsteht in der Routine (Q := TXxx.Create...) oder das SQL wird vor
//     dem ersten Add geleert (Q.SQL.Clear / Q.SQL.Text := ...). Sonst haengt
//     Add an SQL an, das aus dem DFM oder einer anderen Routine kommt.
//   * Jeder Beitrag zum SQL ist ein Literal ('...', #13#10, sLineBreak, '+').
//     Format(), Variablen, Konstanten, SQL.Assign, LoadFromFile, Makros,
//     Open/ExecSQL mit SQL-Argument machen Q unbekannt.
//   * Eine Routine mit 'with', mit SQL/ParamByName ohne Objekt davor oder
//     hinter einem Cast/Index (TFDQuery(X).SQL, Qs[i].SQL) wird ganz
//     uebergangen: wem der Zugriff gilt, ist lexikalisch nicht sicher.
//
// Weitere Gruende zu schweigen (Verifikation 2026-10-07):
//   * Q wird als Wert weitergereicht (BindParams(Q), Result := Q,
//     DataSource.DataSet := Q) oder eine unbekannte Methode mit Argumenten
//     laeuft auf Q (Q.AddWhere('...')) - beides kann SQL oder Parameter
//     aendern. FreeAndNil/Assigned und Dataset-Methoden wie FieldByName
//     zaehlen nicht.
//   * Q ist nicht in der Routine erzeugt (Feld, DFM-Komponente) und die
//     Routine ruft eine eigene Methode ohne Objekt und ohne Argumente
//     (BindFilter;) - die kann Q bedienen.
//   * Eine geschachtelte Routine erwaehnt Q.
//   * Das SQL ist ein Programmblock (BEGIN ... END, Firebird EXECUTE BLOCK,
//     PL/SQL): ':v' kann dort eine lokale Variable sein - dann kein (b).
//   * Ein String im SQL schliesst nicht (Oracle q'[...]', Backslash-
//     Escapes): die Platzhalter sind dann nicht verlaesslich lesbar.
//
// (b) braucht zusaetzlich: Q ist in der Routine erzeugt (sonst binden
// Master-Detail, DFM-Params oder andere Routinen), Params werden nicht
// dynamisch angefasst (Params[i], ParamByName(Variable), MasterSource),
// und die Routine setzt mindestens einen Parameter von Q mit Literal-Namen.
//
// Gelesen wird ab dem ersten 'begin' der Routine - Kopf und var-Abschnitt
// sind Deklarationen, keine Benutzungen.
//
// Zugriffe, die als Zuweisung zaehlen: ParamByName, Params.ParamByName,
// Parameters.ParamByName (ADO), FindParam, ParamValues['a;b'], und fuer
// Direct Oracle Access (TOracleQuery) SetVariable / DeclareVariable /
// SetComplexVariable / SetLongVariable. Gemeldet unter (a) wird nur
// ParamByName: FindParam liefert nil statt zu werfen, und ob DOA eine
// deklarierte, aber im SQL fehlende Variable ablehnt, ist hier nicht
// belegt.
//
// Platzhalter im SQL: ':name' ausserhalb von SQL-Strings ('..', "..",
// `..`) und SQL-Kommentaren (--, /* */). Kein Platzhalter sind '::'
// (Postgres-Cast), ':=' (PL/SQL), ':1' (positional), ':new.'/':old.'
// (Oracle-Trigger) und ein ':' direkt hinter einem Bezeichner, ')' oder
// ']' (Arraygrenzen, Zeitangaben ausserhalb von Strings). Ein '?' im SQL
// (unbenannte Parameter) macht Namensvergleiche wertlos - die Query wird
// dann uebergangen. Fuer (a) zaehlt ein Platzhalter auch dann als
// vorhanden, wenn er nur in einem SQL-Kommentar steht: Data.DB, ADO und
// IBX legen ihn trotzdem als Parameter an.
//
// Gross-/Kleinschreibung spielt beim Vergleich keine Rolle - so halten es
// alle genannten Bibliotheken.

interface

uses
  System.SysUtils, System.Classes;

type
  TParamNameIssueKind = (
    pikUnknownParam,          // (a) ParamByName ohne Platzhalter
    pikUnassignedPlaceholder  // (b) Platzhalter ohne Zuweisung
  );

  TParamNameIssue = record
    Kind         : TParamNameIssueKind;
    Line         : Integer;   // 1-basiert, Datei-Zeile
    Query        : string;    // wie im Quelltext geschrieben, z. B. 'qryUser'
    Param        : string;    // der Name ohne ':'
    Placeholders : string;    // sortierte Liste ':a, :b' (fuer (a))
  end;

  TParamNameScan = class
  public
    // Prueft den Quelltext einer Routine. AFirstLine ist die Datei-Zeile
    // der ersten Zeile von ACode. Kommentare duerfen enthalten sein.
    // AHidden: Quelltext geschachtelter Routinen (aus ACode ausgeblendet) -
    // erwaehnt er eine Query, wird sie nicht beurteilt.
    // Liefert die Befunde nach Zeile sortiert.
    class function ScanRoutine(const ACode: string; AFirstLine: Integer;
      const AHidden: string = ''): TArray<TParamNameIssue>; static;

    // Platzhalter eines SQL-Textes in Reihenfolge des ersten Auftretens,
    // je Name einmal (Schreibweise des ersten Auftretens). Oeffentlich fuer
    // die Tests.
    class function PlaceholdersOf(const ASql: string): TArray<string>; static;

    // Meldetexte - hier, damit Detektor und Tests denselben Text sehen.
    class function MessageOf(const AIssue: TParamNameIssue): string; static;
  end;

implementation

// noinspection-file BeginEndRequired, IfElseBegin, TooLongLine

const
  // So viele Platzhalter nennt die Meldung (a), dann ', ...'. Die Liste
  // hilft beim Tippfehler (:CustId vs. 'CustomerId'); zwanzig Namen liest
  // niemand.
  MAX_LISTED = 6;

  // Mitgliedswoerter, an denen eine Query-Kette endet (klein).
  MEMBER_WORDS: array[0..11] of string = (
    'sql', 'parambyname', 'params', 'parameters', 'findparam',
    'paramvalues', 'setvariable', 'declarevariable', 'setcomplexvariable',
    'setlongvariable', 'macrobyname', 'macros');

type
  TTokKind = (tkIdent, tkString, tkNumber, tkSym, tkAssign);

  TTok = record
    Kind : TTokKind;
    Text : string;   // Bezeichner wie geschrieben / Symbol / DEKODIERTER Literalwert
    Low  : string;   // Bezeichner klein, sonst = Text
    Line : Integer;
  end;

  TPlaceholder = record
    Name    : string;    // Bezeichner-Lesart: Buchstaben, Ziffern, _ @ $ #
    AltName : string;    // Lesart von Data.DB/ADODB ParseSQL: bis Leerzeichen,
                         // ',', ';', ')' oder Zeilenende (':a+1' -> 'a+1')
    Offset  : Integer;   // 1-basiert im gescannten Text
  end;

function IsIdentStart(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_']) or (Ord(C) > 127);
end;

function IsIdentChar(C: Char): Boolean;
begin
  Result := IsIdentStart(C) or CharInSet(C, ['0'..'9']);
end;

// Wie string.Join - ohne den Typ-Helfer, damit der FPC-Pruefstand dieselbe
// Unit uebersetzt.
function JoinStr(const ASep: string; const AParts: array of string): string;
var
  k : Integer;
  Sb : TStringBuilder;
begin
  Sb := TStringBuilder.Create;
  try
    for k := 0 to High(AParts) do
    begin
      if k > 0 then Sb.Append(ASep);
      Sb.Append(AParts[k]);
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function IsMemberWord(const ALow: string): Boolean;
var
  W : string;
begin
  for W in MEMBER_WORDS do
    if W = ALow then Exit(True);
  Result := False;
end;

// ===========================================================================
// Pascal-Tokenizer. Kommentare und Direktiven fallen weg, ein Literal aus
// mehreren Teilen ('a'#13#10'b') wird EIN Token mit dekodiertem Wert.
// ===========================================================================

type
  TTokenizer = class
  private
    FSrc   : string;
    FPos   : Integer;
    FLine  : Integer;
    FToks  : TArray<TTok>;
    FCount : Integer;
    procedure Push(AKind: TTokKind; const AText: string; ALine: Integer);
    procedure SkipUntil(const AClose: string);
    procedure ReadQuoted(ASb: TStringBuilder);
    procedure ReadCharCode(ASb: TStringBuilder);
    procedure ReadLiteral;
    procedure ReadNumber;
    procedure ReadIdent;
    function Peek(AOffset: Integer): Char;
    function SkipTrivia(C: Char): Boolean;
    procedure ReadToken(C: Char);
  public
    function Run(const S: string; AFirstLine: Integer): TArray<TTok>;
  end;

function TTokenizer.Peek(AOffset: Integer): Char;
begin
  if FPos + AOffset <= Length(FSrc) then
    Result := FSrc[FPos + AOffset]
  else
    Result := #0;
end;

procedure TTokenizer.Push(AKind: TTokKind; const AText: string; ALine: Integer);
begin
  if FCount >= Length(FToks) then
    SetLength(FToks, FCount * 2 + 16);
  FToks[FCount].Kind := AKind;
  FToks[FCount].Text := AText;
  if AKind = tkIdent then
    FToks[FCount].Low := LowerCase(AText)
  else
    FToks[FCount].Low := AText;
  FToks[FCount].Line := ALine;
  Inc(FCount);
end;

// Ueberspringt bis einschliesslich AClose ('}' oder '*)'), zaehlt Zeilen.
// AClose = #10 (Zeilenkommentar) bleibt VOR dem Zeilenwechsel stehen, damit
// SkipTrivia ihn zaehlt.
procedure TTokenizer.SkipUntil(const AClose: string);
begin
  while (FPos <= Length(FSrc)) and
        (Copy(FSrc, FPos, Length(AClose)) <> AClose) do
  begin
    if FSrc[FPos] = #10 then Inc(FLine);
    Inc(FPos);
  end;
  if AClose <> #10 then
    Inc(FPos, Length(AClose));
end;

// '...' mit '' als Escape; endet spaetestens am Zeilenende.
procedure TTokenizer.ReadQuoted(ASb: TStringBuilder);
begin
  Inc(FPos);   // oeffnendes '
  while FPos <= Length(FSrc) do
  begin
    if FSrc[FPos] = #10 then Exit;
    if FSrc[FPos] = '''' then
    begin
      if Peek(1) <> '''' then
      begin
        Inc(FPos);
        Exit;
      end;
      ASb.Append('''');
      Inc(FPos, 2);
      Continue;
    end;
    ASb.Append(string(FSrc[FPos]));
    Inc(FPos);
  end;
end;

// #13 oder #$0D
procedure TTokenizer.ReadCharCode(ASb: TStringBuilder);
var
  Start : Integer;
  Code  : Integer;
begin
  Inc(FPos);   // #
  Start := FPos;
  if Peek(0) = '$' then
  begin
    Inc(FPos);
    while CharInSet(Peek(0), ['0'..'9', 'A'..'F', 'a'..'f']) do Inc(FPos);
  end
  else
    while CharInSet(Peek(0), ['0'..'9']) do Inc(FPos);
  Code := StrToIntDef(Copy(FSrc, Start, FPos - Start), -1);
  if (Code >= 0) and (Code <= $FFFF) then
    ASb.Append(string(Char(Code)));
end;

procedure TTokenizer.ReadLiteral;
var
  Sb    : TStringBuilder;
  Start : Integer;
begin
  Start := FLine;
  Sb := TStringBuilder.Create;
  try
    while CharInSet(Peek(0), ['''', '#']) do
      if Peek(0) = '''' then
        ReadQuoted(Sb)
      else
        ReadCharCode(Sb);
    Push(tkString, Sb.ToString, Start);
  finally
    Sb.Free;
  end;
end;

procedure TTokenizer.ReadNumber;
var
  Start : Integer;
begin
  Start := FPos;
  Inc(FPos);
  while CharInSet(Peek(0), ['0'..'9', 'A'..'F', 'a'..'f', '.', 'x', 'X']) do
  begin
    if (Peek(0) = '.') and (Peek(1) = '.') then Break;   // Bereich 1..9
    Inc(FPos);
  end;
  Push(tkNumber, Copy(FSrc, Start, FPos - Start), FLine);
end;

procedure TTokenizer.ReadIdent;
var
  Start : Integer;
begin
  Start := FPos;
  while IsIdentChar(Peek(0)) do Inc(FPos);
  Push(tkIdent, Copy(FSrc, Start, FPos - Start), FLine);
end;

// Leerraum, Zeilenwechsel, Kommentare. True, wenn etwas uebersprungen wurde.
function TTokenizer.SkipTrivia(C: Char): Boolean;
begin
  Result := True;
  if C = #10 then
  begin
    Inc(FLine);
    Inc(FPos);
  end
  else if C <= ' ' then
    Inc(FPos)
  else if C = '{' then
    SkipUntil('}')
  else if (C = '(') and (Peek(1) = '*') then
  begin
    Inc(FPos, 2);   // '(*)' schliesst den Kommentar nicht
    SkipUntil('*)');
  end
  else if (C = '/') and (Peek(1) = '/') then
    SkipUntil(#10)
  else
    Result := False;
end;

procedure TTokenizer.ReadToken(C: Char);
begin
  if CharInSet(C, ['''', '#']) then
    ReadLiteral
  else if (C = ':') and (Peek(1) = '=') then
  begin
    Push(tkAssign, ':=', FLine);
    Inc(FPos, 2);
  end
  else if CharInSet(C, ['0'..'9', '$']) then
    ReadNumber
  else if (C = '&') and IsIdentStart(Peek(1)) then
  begin
    Inc(FPos);   // &Bezeichner: Schluesselwort als Name
    ReadIdent;
  end
  else if IsIdentStart(C) then
    ReadIdent
  else
  begin
    Push(tkSym, C, FLine);
    Inc(FPos);
  end;
end;

function TTokenizer.Run(const S: string; AFirstLine: Integer): TArray<TTok>;
begin
  FSrc := S;
  FPos := 1;
  FLine := AFirstLine;
  FToks := nil;
  FCount := 0;
  while FPos <= Length(FSrc) do
    if not SkipTrivia(FSrc[FPos]) then
      ReadToken(FSrc[FPos]);
  SetLength(FToks, FCount);
  Result := FToks;
end;

// ===========================================================================
// SQL-Platzhalter
// ===========================================================================

// Ab APos (zeigt auf ', " oder `) bis hinter das schliessende Zeichen; ''
// als Escape oeffnet sofort wieder und ist damit von selbst abgedeckt.
// AClosed = False, wenn der Text vorher endet.
function SkipSqlQuoted(const ASql: string; APos: Integer;
  out AClosed: Boolean): Integer;
var
  Q : Char;
begin
  Q := ASql[APos];
  Result := APos + 1;
  while (Result <= Length(ASql)) and (ASql[Result] <> Q) do Inc(Result);
  AClosed := Result <= Length(ASql);
  Inc(Result);
end;

// Oracle q'[...]' / q'{...}' / q'!...!': APos zeigt auf das '''' hinter q.
function SkipOracleQQuote(const ASql: string; APos: Integer;
  out AClosed: Boolean): Integer;
var
  Open, Close : Char;
begin
  AClosed := False;
  Result := Length(ASql) + 1;
  if APos + 1 > Length(ASql) then Exit;
  Open := ASql[APos + 1];
  case Open of
    '[': Close := ']';
    '(': Close := ')';
    '{': Close := '}';
    '<': Close := '>';
  else
    Close := Open;
  end;
  Result := APos + 2;
  while Result < Length(ASql) do
  begin
    if (ASql[Result] = Close) and (ASql[Result + 1] = '''') then
    begin
      AClosed := True;
      Exit(Result + 2);
    end;
    Inc(Result);
  end;
  Result := Length(ASql) + 1;
end;

function IsOracleQQuote(const ASql: string; APos: Integer): Boolean;
begin
  Result := (ASql[APos] = '''') and (APos > 1) and
            CharInSet(ASql[APos - 1], ['q', 'Q', 'n', 'N']) and
            ((APos = 2) or not IsIdentChar(ASql[APos - 2])) and
            ((ASql[APos - 1] = 'q') or (ASql[APos - 1] = 'Q'));
end;

// Ab APos ('-' von '--' oder '/' von '/*') hinter den Kommentar.
function SkipSqlComment(const ASql: string; APos: Integer): Integer;
begin
  Result := APos;
  if ASql[APos] = '-' then
  begin
    while (Result <= Length(ASql)) and (ASql[Result] <> #10) do Inc(Result);
    Exit;
  end;
  Inc(Result, 2);
  while (Result < Length(ASql)) and
        not ((ASql[Result] = '*') and (ASql[Result + 1] = '/')) do
    Inc(Result);
  Inc(Result, 2);
end;

function IsSqlCommentStart(const ASql: string; APos: Integer): Boolean;
begin
  Result := (APos < Length(ASql)) and
            (((ASql[APos] = '-') and (ASql[APos + 1] = '-')) or
             ((ASql[APos] = '/') and (ASql[APos + 1] = '*')));
end;

// Zeichen eines Parameternamens. Breiter als ein Pascal-Bezeichner: ADO
// und SQL Server schreiben ':@Name', Oracle erlaubt $ und #
// (Kundenkorpus 2026-10-07: ACBr-Beispiel mit TADOQuery und ':@CodigoBarras'
// - ohne '@' waere das ein Fehlalarm gewesen).
function IsParamNameStart(C: Char): Boolean;
begin
  Result := IsIdentStart(C) or (C = '@');
end;

function IsParamNameChar(C: Char): Boolean;
begin
  Result := IsIdentChar(C) or CharInSet(C, ['@', '$', '#']);
end;

// Wie TParams.ParseSQL (Data.DB) und TParameters.ParseSQL (ADODB) das
// Namensende finden.
function IsParseSqlDelimiter(C: Char): Boolean;
begin
  Result := CharInSet(C, [' ', ',', ';', ')', #13, #10]);
end;

// ':"Name mit Leerzeichen"' - beide RTL-Parser kennen die Form.
function ReadQuotedName(const ASql: string; APos: Integer;
  out AName: string; out ANext: Integer): Boolean;
var
  Q : Char;
  Start : Integer;
begin
  Q := ASql[APos + 1];
  Start := APos + 2;
  ANext := Start;
  while (ANext <= Length(ASql)) and (ASql[ANext] <> Q) do Inc(ANext);
  AName := Copy(ASql, Start, ANext - Start);
  Inc(ANext);
  Result := AName <> '';
end;

// ':' an APos: ist das ein benannter Platzhalter? Dann Name/AltName und
// True; ANext zeigt in jedem Fall auf das naechste zu lesende Zeichen.
function ReadPlaceholder(const ASql: string; APos: Integer;
  out AName, AAltName: string; out ANext: Integer): Boolean;
var
  Prev : Char;
  Start, AltEnd : Integer;
begin
  Result := False;
  AName := '';
  AAltName := '';
  ANext := APos + 1;
  if APos >= Length(ASql) then Exit;
  if CharInSet(ASql[APos + 1], [':', '=']) then
  begin
    ANext := APos + 2;   // '::' Cast bzw. maskierter ':', ':=' Zuweisung
    Exit;
  end;
  if APos > 1 then Prev := ASql[APos - 1] else Prev := ' ';
  if IsIdentChar(Prev) or CharInSet(Prev, [')', ']', '.', ':']) then Exit;
  if CharInSet(ASql[APos + 1], ['"', '`']) then
  begin
    Result := ReadQuotedName(ASql, APos, AName, ANext);
    AAltName := AName;
    Exit;
  end;
  if not IsParamNameStart(ASql[APos + 1]) then Exit;
  Start := APos + 1;
  ANext := Start;
  while (ANext <= Length(ASql)) and IsParamNameChar(ASql[ANext]) do Inc(ANext);
  AName := Copy(ASql, Start, ANext - Start);
  AltEnd := Start;
  while (AltEnd <= Length(ASql)) and not IsParseSqlDelimiter(ASql[AltEnd]) do
    Inc(AltEnd);
  AAltName := Copy(ASql, Start, AltEnd - Start);
  // Oracle-Trigger: :new.spalte / :old.spalte sind Pseudo-Records
  if (ANext <= Length(ASql)) and (ASql[ANext] = '.') and
     (SameText(AName, 'new') or SameText(AName, 'old')) then
    Exit;
  Result := True;
end;

type
  TSqlScanInfo = record
    Positional : Boolean;   // '?' im Code-Teil
    Block      : Boolean;   // Wort BEGIN im Code-Teil (PSQL/PL-SQL-Block)
    Unbalanced : Boolean;   // ein String schliesst nicht
  end;

// Liest das Wort ab APos; True, wenn es BEGIN ist. ANext dahinter.
function ReadSqlWord(const ASql: string; APos: Integer; out ANext: Integer): Boolean;
begin
  ANext := APos;
  while (ANext <= Length(ASql)) and IsIdentChar(ASql[ANext]) do Inc(ANext);
  Result := SameText(Copy(ASql, APos, ANext - APos), 'begin');
end;

type
  // Platzhalter in SQL-Kommentaren mitlesen? Fuer (a) ja - Data.DB, ADO
  // und IBX legen sie dort ebenfalls an.
  TCommentMode = (cmSkipComments, cmReadComments);

// Strings und (je nach AMode) Kommentare ab APos ueberspringen. True, wenn
// dort so etwas beginnt; ANext dann dahinter (sonst unveraendert),
// AInfo.Unbalanced bei offenem String.
function SkipNonCode(const ASql: string; APos: Integer; AMode: TCommentMode;
  var AInfo: TSqlScanInfo; var ANext: Integer): Boolean;
var
  Closed : Boolean;
begin
  Result := True;
  Closed := True;
  if IsOracleQQuote(ASql, APos) then
    ANext := SkipOracleQQuote(ASql, APos, Closed)
  else if CharInSet(ASql[APos], ['''', '"', '`']) then
    ANext := SkipSqlQuoted(ASql, APos, Closed)
  else if (AMode = cmSkipComments) and IsSqlCommentStart(ASql, APos) then
    ANext := SkipSqlComment(ASql, APos)
  else
    Result := False;
  if not Closed then
    AInfo.Unbalanced := True;
end;

// Ein Wortanfang ausserhalb eines Namens?
function IsWordStart(const ASql: string; APos: Integer): Boolean;
begin
  Result := IsIdentStart(ASql[APos]) and
            ((APos = 1) or not IsParamNameChar(ASql[APos - 1]));
end;

// Alle benannten Platzhalter.
function ScanPlaceholders(const ASql: string; AMode: TCommentMode;
  out AInfo: TSqlScanInfo): TArray<TPlaceholder>;
var
  i, Next, Cnt : Integer;
  Name, AltName : string;
begin
  Result := nil;
  AInfo.Positional := False;
  AInfo.Block := False;
  AInfo.Unbalanced := False;
  Cnt := 0;
  i := 1;
  while i <= Length(ASql) do
  begin
    Next := i + 1;
    if SkipNonCode(ASql, i, AMode, AInfo, Next) then
      // Next steht hinter String bzw. Kommentar
    else if ASql[i] = '?' then
      AInfo.Positional := True
    else if IsWordStart(ASql, i) then
      AInfo.Block := ReadSqlWord(ASql, i, Next) or AInfo.Block
    else if (ASql[i] = ':') and ReadPlaceholder(ASql, i, Name, AltName, Next) then
    begin
      if Cnt >= Length(Result) then SetLength(Result, Cnt * 2 + 8);
      Result[Cnt].Name := Name;
      Result[Cnt].AltName := AltName;
      Result[Cnt].Offset := i + 1;
      Inc(Cnt);
    end;
    i := Next;
  end;
  SetLength(Result, Cnt);
end;

function UniqueNames(const APh: TArray<TPlaceholder>): TArray<string>;
var
  i, j, Cnt : Integer;
  Seen : Boolean;
begin
  Result := nil;
  SetLength(Result, Length(APh));
  Cnt := 0;
  for i := 0 to High(APh) do
  begin
    Seen := False;
    for j := 0 to Cnt - 1 do
      if AnsiSameText(Result[j], APh[i].Name) then
      begin
        Seen := True;
        Break;
      end;
    if Seen then Continue;
    Result[Cnt] := APh[i].Name;
    Inc(Cnt);
  end;
  SetLength(Result, Cnt);
end;

class function TParamNameScan.PlaceholdersOf(const ASql: string): TArray<string>;
var
  Info : TSqlScanInfo;
begin
  Result := UniqueNames(ScanPlaceholders(ASql, cmSkipComments, Info));
end;

// ===========================================================================
// Routine
// ===========================================================================

type
  TSqlPart = record
    Text : string;
    Line : Integer;
  end;

  TRef = record
    Name   : string;
    Line   : Integer;
    Throws : Boolean;   // ParamByName: wirft, wenn der Name fehlt -> (a)
  end;

  TQueryState = record
    Key        : string;   // klein, Punkt-Kette ohne 'self.'
    Display    : string;
    Created    : Boolean;
    Reset      : Boolean;
    HasSqlOp   : Boolean;
    Incomplete : Boolean;   // SQL oder Parameter nicht vollstaendig sichtbar -> kein Urteil
    DynRefs    : Boolean;   // Parameter dynamisch angefasst -> kein (b)
    Parts      : TArray<TSqlPart>;
    Refs       : TArray<TRef>;
  end;

  TChain = record
    Toks  : TArray<TTok>;
    Last  : Integer;   // Token-Index des letzten Kettenglieds
  end;

  // Lesezugriffe auf die Token-Folge einer Routine.
  TTokenCursor = class
  protected
    FToks : TArray<TTok>;
    FN    : Integer;
    function Tok(AIdx: Integer): TTok;
    function IsSym(AIdx: Integer; const AText: string): Boolean;
    function MatchClose(AOpen: Integer): Integer;
    function ExprEnd(AFrom: Integer): Integer;
    function LiteralExpr(AFrom, ATo: Integer; out AValue: string): Boolean;
    function ReadChain(AStart: Integer): TChain;
    procedure ChainKey(const AChain: TChain; ACount: Integer;
      out AKey, ADisplay: string);
  end;

  // Sammelt je Query SQL-Teile und Parameterzugriffe einer Routine.
  TRoutineScanner = class(TTokenCursor)
  private
    FQs       : TArray<TQueryState>;
    FBareCall : Boolean;          // eigene Methode ohne Objekt aufgerufen
    FHidden   : TArray<string>;   // Bezeichner (klein) geschachtelter Routinen
    function QueryOf(const AKey, ADisplay: string): Integer;
    procedure AddPart(AQ: Integer; const AText: string; ALine: Integer);
    procedure AddRef(AQ: Integer; const AName: string; ALine: Integer;
      AThrows: Boolean);
    procedure HandleSqlAdd(AQ, E: Integer);
    procedure HandleSqlText(AQ, E: Integer);
    procedure HandleSql(AQ: Integer; const AChain: TChain; AMember: Integer);
    procedure HandleParamValues(AQ, E: Integer);
    procedure HandleParamAccess(AQ: Integer; const AMember: string; E: Integer);
    procedure HandleAssign(const AChain: TChain);
    function IsReleaseArg(AStart: Integer): Boolean;
    function IsStatementStart(AIdx: Integer): Boolean;
    procedure HandleMethodCall(const AChain: TChain);
    procedure HandlePlainChain(const AChain: TChain; AStart: Integer);
    procedure HandleMemberChain(const AChain: TChain; AMember: Integer);
    function IsUnsafeAt(AIdx: Integer): Boolean;
    function Walk: Boolean;
    procedure ApplyRoutineFacts;
  public
    function Run(const ACode, AHidden: string;
      AFirstLine: Integer): TArray<TParamNameIssue>;
  end;

  // Das Urteil ueber die gesammelten Queries einer Routine.
  TQueryJudge = class
  private
    FIssues  : TArray<TParamNameIssue>;
    procedure AddIssue(const AIssue: TParamNameIssue);
    function PlaceholderList(const ANames: TArray<string>): string;
    function LineOfPlaceholder(const AQ: TQueryState; const APh: TArray<TPlaceholder>;
      const AStarts: TArray<Integer>; const AName: string): Integer;
    procedure JudgeUnknown(const AQ: TQueryState; const ANames: TArray<string>;
      const APhAll: TArray<TPlaceholder>);
    procedure JudgeUnassigned(const AQ: TQueryState; const ANames: TArray<string>;
      const APh: TArray<TPlaceholder>; const AStarts: TArray<Integer>);
    procedure Judge(const AQ: TQueryState);
    procedure SortIssues;
  public
    function Run(const AQs: TArray<TQueryState>): TArray<TParamNameIssue>;
  end;

function TTokenCursor.Tok(AIdx: Integer): TTok;
begin
  if (AIdx >= 0) and (AIdx < FN) then
    Exit(FToks[AIdx]);
  Result.Kind := tkSym;
  Result.Text := '';
  Result.Low  := '';
  Result.Line := 0;
end;

function TTokenCursor.IsSym(AIdx: Integer; const AText: string): Boolean;
begin
  Result := (AIdx >= 0) and (AIdx < FN) and (FToks[AIdx].Kind = tkSym) and
            (FToks[AIdx].Text = AText);
end;

// 'Self.FQuery' und 'FQuery' sind dieselbe Query.
function TRoutineScanner.QueryOf(const AKey, ADisplay: string): Integer;
var
  k : Integer;
  Key, Disp : string;
begin
  Key := AKey;
  Disp := ADisplay;
  if Copy(Key, 1, 5) = 'self.' then
  begin
    Delete(Key, 1, 5);
    Delete(Disp, 1, 5);
  end;
  for k := 0 to High(FQs) do
    if FQs[k].Key = Key then Exit(k);
  Result := Length(FQs);
  SetLength(FQs, Result + 1);
  FQs[Result].Key := Key;
  FQs[Result].Display := Disp;
end;

// Index der passenden schliessenden Klammer zu AOpen ('(' oder '['), -1
// wenn sie fehlt.
function TTokenCursor.MatchClose(AOpen: Integer): Integer;
var
  k, Depth : Integer;
  Op, Cl : string;
begin
  Result := -1;
  Op := FToks[AOpen].Text;
  if Op = '(' then Cl := ')' else Cl := ']';
  Depth := 0;
  for k := AOpen to FN - 1 do
  begin
    if FToks[k].Kind <> tkSym then Continue;
    if FToks[k].Text = Op then
      Inc(Depth)
    else if FToks[k].Text = Cl then
    begin
      Dec(Depth);
      if Depth = 0 then Exit(k);
    end;
  end;
end;

function IsStatementEndWord(const T: TTok): Boolean;
begin
  Result := (T.Kind = tkIdent) and
            ((T.Low = 'end') or (T.Low = 'else') or (T.Low = 'except') or
             (T.Low = 'finally') or (T.Low = 'until'));
end;

function IsStatementEnd(const T: TTok): Boolean;
begin
  if T.Kind = tkSym then
    Exit(T.Text = ';');
  Result := (T.Kind = tkIdent) and
            ((T.Low = 'end') or (T.Low = 'else') or (T.Low = 'except') or
             (T.Low = 'finally') or (T.Low = 'until'));
end;

// Ende des Ausdrucks ab AFrom: erstes ';'/end/else/... auf Klammertiefe 0
// oder eine schliessende Klammer, die nicht zum Ausdruck gehoert.
function TTokenCursor.ExprEnd(AFrom: Integer): Integer;
var
  k, Depth : Integer;
begin
  Depth := 0;
  for k := AFrom to FN - 1 do
  begin
    if IsSym(k, '(') or IsSym(k, '[') then
      Inc(Depth)
    else if IsSym(k, ')') or IsSym(k, ']') then
    begin
      if Depth = 0 then Exit(k);
      Dec(Depth);
    end
    else if (Depth = 0) and IsStatementEnd(FToks[k]) then
      Exit(k);
  end;
  Result := FN;
end;

// FToks[AFrom..ATo-1] ist ein reiner Literal-Ausdruck? Dann Wert in AValue.
function TTokenCursor.LiteralExpr(AFrom, ATo: Integer;
  out AValue: string): Boolean;
var
  k : Integer;
  HasLit : Boolean;
  Sb : TStringBuilder;
begin
  AValue := '';
  HasLit := False;
  Sb := TStringBuilder.Create;
  try
    for k := AFrom to ATo - 1 do
    begin
      if FToks[k].Kind = tkString then
      begin
        Sb.Append(FToks[k].Text);
        HasLit := True;
      end
      else if (FToks[k].Kind = tkIdent) and (FToks[k].Low = 'slinebreak') then
        Sb.Append(string(#10))
      else if not ((FToks[k].Kind = tkSym) and
                   ((FToks[k].Text = '+') or (FToks[k].Text = '(') or
                    (FToks[k].Text = ')'))) then
        Exit(False);
    end;
    AValue := Sb.ToString;
  finally
    Sb.Free;
  end;
  Result := HasLit;
end;

procedure TRoutineScanner.AddPart(AQ: Integer; const AText: string; ALine: Integer);
var
  L : Integer;
begin
  L := Length(FQs[AQ].Parts);
  SetLength(FQs[AQ].Parts, L + 1);
  FQs[AQ].Parts[L].Text := AText;
  FQs[AQ].Parts[L].Line := ALine;
end;

procedure TRoutineScanner.AddRef(AQ: Integer; const AName: string;
  ALine: Integer; AThrows: Boolean);
var
  L : Integer;
begin
  L := Length(FQs[AQ].Refs);
  SetLength(FQs[AQ].Refs, L + 1);
  FQs[AQ].Refs[L].Name := AName;
  FQs[AQ].Refs[L].Line := ALine;
  FQs[AQ].Refs[L].Throws := AThrows;
end;

procedure TQueryJudge.AddIssue(const AIssue: TParamNameIssue);
var
  L : Integer;
begin
  L := Length(FIssues);
  SetLength(FIssues, L + 1);
  FIssues[L] := AIssue;
end;

// Maximale Kette ident(.ident)* ab AStart.
function TTokenCursor.ReadChain(AStart: Integer): TChain;
var
  Cnt : Integer;
begin
  SetLength(Result.Toks, 4);
  Result.Toks[0] := FToks[AStart];
  Cnt := 1;
  Result.Last := AStart;
  while IsSym(Result.Last + 1, '.') and (Tok(Result.Last + 2).Kind = tkIdent) do
  begin
    if Cnt >= Length(Result.Toks) then
      SetLength(Result.Toks, Cnt * 2);
    Result.Toks[Cnt] := FToks[Result.Last + 2];
    Inc(Cnt);
    Inc(Result.Last, 2);
  end;
  SetLength(Result.Toks, Cnt);
end;

// Die ersten ACount Glieder als Schluessel (klein) und Anzeige.
procedure TTokenCursor.ChainKey(const AChain: TChain; ACount: Integer;
  out AKey, ADisplay: string);
var
  Low, Txt : TArray<string>;
  k : Integer;
begin
  SetLength(Low, ACount);
  SetLength(Txt, ACount);
  for k := 0 to ACount - 1 do
  begin
    Low[k] := AChain.Toks[k].Low;
    Txt[k] := AChain.Toks[k].Text;
  end;
  AKey := JoinStr('.', Low);
  ADisplay := JoinStr('.', Txt);
end;

procedure TRoutineScanner.HandleSqlAdd(AQ, E: Integer);
var
  Close : Integer;
  V : string;
begin
  if not IsSym(E + 1, '(') then
  begin
    FQs[AQ].Incomplete := True;
    Exit;
  end;
  if not (FQs[AQ].Created or FQs[AQ].Reset or FQs[AQ].HasSqlOp) then
    FQs[AQ].Incomplete := True;   // haengt an fremdes SQL an
  FQs[AQ].HasSqlOp := True;
  Close := MatchClose(E + 1);
  if (Close < 0) or not LiteralExpr(E + 2, Close, V) then
  begin
    FQs[AQ].Incomplete := True;
    Exit;
  end;
  AddPart(AQ, V, FToks[E + 2].Line);
end;

procedure TRoutineScanner.HandleSqlText(AQ, E: Integer);
var
  V : string;
begin
  if Tok(E + 1).Kind <> tkAssign then Exit;   // lesen ist harmlos
  FQs[AQ].Reset := True;
  FQs[AQ].HasSqlOp := True;
  if not LiteralExpr(E + 2, ExprEnd(E + 2), V) then
  begin
    FQs[AQ].Incomplete := True;
    Exit;
  end;
  AddPart(AQ, V, FToks[E + 2].Line);
end;

// AMember = Index von 'SQL' in der Kette.
procedure TRoutineScanner.HandleSql(AQ: Integer; const AChain: TChain;
  AMember: Integer);
var
  Sub : string;
begin
  // Q.SQL := X, Q.SQL[i] := X, Foo(Q.SQL), Q.SQL.Strings.Foo: unbekannt
  if AMember + 1 <> High(AChain.Toks) then
  begin
    FQs[AQ].Incomplete := True;
    Exit;
  end;
  Sub := AChain.Toks[AMember + 1].Low;
  if (Sub = 'add') or (Sub = 'append') then
    HandleSqlAdd(AQ, AChain.Last)
  else if Sub = 'text' then
    HandleSqlText(AQ, AChain.Last)
  else if Sub = 'clear' then
  begin
    FQs[AQ].Reset := True;
    FQs[AQ].HasSqlOp := True;
  end
  else if (Sub <> 'count') and (Sub <> 'beginupdate') and (Sub <> 'endupdate') then
    FQs[AQ].Incomplete := True;   // Assign, AddStrings, LoadFromFile, Insert, ...
end;

// Q.ParamValues['a;b'] := ...
procedure TRoutineScanner.HandleParamValues(AQ, E: Integer);
var
  Names : TStringList;
  k : Integer;
begin
  if not (IsSym(E + 1, '[') and (Tok(E + 2).Kind = tkString) and
          (IsSym(E + 3, ']') or IsSym(E + 3, ','))) then
  begin
    FQs[AQ].DynRefs := True;
    Exit;
  end;
  Names := TStringList.Create;
  try
    Names.StrictDelimiter := True;
    Names.Delimiter := ';';
    Names.DelimitedText := FToks[E + 2].Text;
    for k := 0 to Names.Count - 1 do
      if Trim(Names[k]) <> '' then
        AddRef(AQ, Trim(Names[k]), FToks[E + 2].Line, False);
  finally
    Names.Free;
  end;
end;

procedure TRoutineScanner.HandleParamAccess(AQ: Integer; const AMember: string;
  E: Integer);
begin
  if AMember = 'paramvalues' then
  begin
    HandleParamValues(AQ, E);
    Exit;
  end;
  // erstes Argument muss EIN Literal sein: ('x') bzw. ('x', ...)
  if not IsSym(E + 1, '(') or (MatchClose(E + 1) < 0) or
     (Tok(E + 2).Kind <> tkString) or
     not (IsSym(E + 3, ')') or IsSym(E + 3, ',')) then
  begin
    FQs[AQ].DynRefs := True;
    Exit;
  end;
  AddRef(AQ, FToks[E + 2].Text, FToks[E + 2].Line, AMember = 'parambyname');
end;

// V := TXxx.Create(...) erzeugt - nur genau diese Form, alles andere
// (eigene Konstruktoren mit SQL, V := DM.qry, V := Make(...)) ersetzt die
// Query durch eine unbekannte.
procedure TRoutineScanner.HandleAssign(const AChain: TChain);
var
  Key, Disp : string;
  Q, Stop, Close : Integer;
  Rhs : TChain;
  Created : Boolean;
begin
  ChainKey(AChain, Length(AChain.Toks), Key, Disp);
  Stop := ExprEnd(AChain.Last + 2);
  Created := False;
  if Tok(AChain.Last + 2).Kind = tkIdent then
  begin
    Rhs := ReadChain(AChain.Last + 2);
    if (Length(Rhs.Toks) >= 2) and (Rhs.Toks[High(Rhs.Toks)].Low = 'create') then
    begin
      if Rhs.Last + 1 = Stop then
        Created := True
      else if IsSym(Rhs.Last + 1, '(') then
      begin
        Close := MatchClose(Rhs.Last + 1);
        Created := (Close >= 0) and (Close + 1 = Stop);
      end;
    end;
  end;
  Q := QueryOf(Key, Disp);
  FQs[Q].Created := Created;
  FQs[Q].Reset := False;
  FQs[Q].HasSqlOp := False;
end;

// Steht AIdx am Anfang einer Anweisung?
function TRoutineScanner.IsStatementStart(AIdx: Integer): Boolean;
var
  P : TTok;
begin
  P := Tok(AIdx - 1);
  Result := (AIdx = 0) or ((P.Kind = tkSym) and (P.Text = ';')) or
            ((P.Kind = tkIdent) and
             ((P.Low = 'begin') or (P.Low = 'then') or (P.Low = 'else') or
              (P.Low = 'do') or (P.Low = 'try') or (P.Low = 'finally') or
              (P.Low = 'except') or (P.Low = 'repeat')));
end;

// Methoden, die SQL und Parameter einer Query nicht anfassen.
function IsHarmlessMethod(const ALow: string): Boolean;
const
  HARMLESS: array[0..27] of string = (
    'fieldbyname', 'findfield', 'locate', 'lookup', 'fields', 'moveby',
    'gotobookmark', 'freebookmark', 'bookmarkvalid', 'comparebookmarks',
    'getfieldnames', 'createblobstream', 'close', 'free', 'prepare',
    'unprepare', 'first', 'next', 'last', 'prior', 'edit', 'post', 'cancel',
    'refresh', 'disablecontrols', 'enablecontrols', 'execute', 'disposeof');
var
  W : string;
begin
  for W in HARMLESS do
    if W = ALow then Exit(True);
  Result := False;
end;

// Routinen der RTL, die als nackter Aufruf keine Query bedienen.
function IsRtlRoutine(const ALow: string): Boolean;
const
  // RTL-Routinen und Schluesselwoerter ('end;' steht auch am Anweisungsanfang)
  RTL: array[0..40] of string = (
    'inc', 'dec', 'exit', 'break', 'continue', 'freeandnil', 'setlength',
    'include', 'exclude', 'abort', 'raiselastoserror', 'sleep', 'assert',
    'showmessage', 'messagedlg', 'writeln', 'inherited', 'application',
    'begin', 'end', 'try', 'finally', 'except', 'then', 'else', 'do', 'if',
    'while', 'for', 'repeat', 'until', 'case', 'of', 'raise', 'not', 'and',
    'or', 'on', 'result', 'self', 'nil');
var
  W : string;
begin
  for W in RTL do
    if W = ALow then Exit(True);
  Result := False;
end;

// Aufruf an einer Kette: Q.Foo(...), Foo(...), Foo; Self.Foo.
procedure TRoutineScanner.HandleMethodCall(const AChain: TChain);
var
  Key, Disp, Last : string;
  HasArgs : Boolean;
  Q : Integer;
begin
  Last := AChain.Toks[High(AChain.Toks)].Low;
  HasArgs := IsSym(AChain.Last + 1, '(') and not IsSym(AChain.Last + 2, ')');
  // eigene Methode ohne Objekt und ohne Argumente (BindFilter; Self.Prepare):
  // kann jede Feld-Query bedienen. Mit Argumenten (CheckEquals(1, X)) ist es
  // eine Funktion ihrer Argumente - die Korpusmessung 2026-10-07 zeigte, dass
  // die Argument-Variante fast nur Test-Assertions traf und die Regel im
  // Kundenkorpus von 28 auf 2 gefangene Mutationen druecken wuerde.
  if (Length(AChain.Toks) = 1) or
     ((Length(AChain.Toks) = 2) and (AChain.Toks[0].Low = 'self')) then
  begin
    if not HasArgs and not IsRtlRoutine(Last) then
      FBareCall := True;
    Exit;
  end;
  if (Length(AChain.Toks) < 2) or not HasArgs or IsHarmlessMethod(Last) then Exit;
  // Q.AddWhere('...'), Q.Open('select ...'), Q.ExecSQL('...'): unbekannt
  ChainKey(AChain, Length(AChain.Toks) - 1, Key, Disp);
  Q := QueryOf(Key, Disp);
  FQs[Q].Incomplete := True;
end;

// FreeAndNil(Q) und Assigned(Q) geben die Query nicht weiter.
function TRoutineScanner.IsReleaseArg(AStart: Integer): Boolean;
begin
  Result := IsSym(AStart - 1, '(') and (Tok(AStart - 2).Kind = tkIdent) and
            ((Tok(AStart - 2).Low = 'freeandnil') or
             (Tok(AStart - 2).Low = 'assigned'));
end;

// Kette ohne Mitgliedswort: Zuweisung, Aufruf oder Wert-Benutzung.
procedure TRoutineScanner.HandlePlainChain(const AChain: TChain; AStart: Integer);
var
  Key, Disp, Last : string;
  Q : Integer;
begin
  Last := AChain.Toks[High(AChain.Toks)].Low;
  if Tok(AChain.Last + 1).Kind = tkAssign then
  begin
    // Q.MasterSource := DS / Q.DataSource := DS: Master-Detail bindet
    if (Length(AChain.Toks) >= 2) and
       ((Last = 'mastersource') or (Last = 'datasource') or (Last = 'masterfields')) then
    begin
      ChainKey(AChain, Length(AChain.Toks) - 1, Key, Disp);
      Q := QueryOf(Key, Disp);
      FQs[Q].DynRefs := True;
      Exit;
    end;
    HandleAssign(AChain);
    Exit;
  end;
  if IsSym(AChain.Last + 1, '(') or
     (IsStatementStart(AStart) and (IsSym(AChain.Last + 1, ';') or
      IsStatementEndWord(Tok(AChain.Last + 1)))) then
  begin
    HandleMethodCall(AChain);
    Exit;
  end;
  if IsReleaseArg(AStart) or (Length(AChain.Toks) > 1) then Exit;
  // Q als Wert (Argument, rechte Seite): wer Q bekommt, kann SQL und
  // Parameter aendern - kein Urteil ueber Q.
  ChainKey(AChain, 1, Key, Disp);
  Q := QueryOf(Key, Disp);
  FQs[Q].Incomplete := True;
end;

procedure TRoutineScanner.HandleMemberChain(const AChain: TChain; AMember: Integer);
var
  Key, Disp, Member : string;
  Q : Integer;
begin
  ChainKey(AChain, AMember, Key, Disp);
  Member := AChain.Toks[AMember].Low;
  // Params.ParamByName / Parameters.ParamByName / Params.FindParam / ...
  if ((Member = 'params') or (Member = 'parameters')) and
     (AMember < High(AChain.Toks)) and
     ((AChain.Toks[AMember + 1].Low = 'parambyname') or
      (AChain.Toks[AMember + 1].Low = 'findparam') or
      (AChain.Toks[AMember + 1].Low = 'paramvalues')) then
  begin
    Inc(AMember);
    Member := AChain.Toks[AMember].Low;
  end;
  Q := QueryOf(Key, Disp);
  if Member = 'sql' then
    HandleSql(Q, AChain, AMember)
  else if (Member = 'macrobyname') or (Member = 'macros') then
    FQs[Q].Incomplete := True     // Makros koennen SQL samt Platzhaltern einsetzen
  else if (Member = 'params') or (Member = 'parameters') or
          (AMember <> High(AChain.Toks)) then
    FQs[Q].DynRefs := True        // Params[i], Params.Assign, Params.Count, ...
  else
    HandleParamAccess(Q, Member, AChain.Last);
end;

// Zugriffe, deren Ziel lexikalisch nicht sicher ist: 'with', ein
// Mitgliedswort ohne Objekt davor oder hinter ')'/']'.
function TRoutineScanner.IsUnsafeAt(AIdx: Integer): Boolean;
begin
  if FToks[AIdx].Low = 'with' then Exit(True);
  if not IsMemberWord(FToks[AIdx].Low) then Exit(False);
  if IsSym(AIdx - 1, '.') then
    Exit(IsSym(AIdx - 2, ')') or IsSym(AIdx - 2, ']'));
  Result := IsSym(AIdx + 1, '.') or IsSym(AIdx + 1, '(') or IsSym(AIdx + 1, '[');
end;

// Laeuft einmal ueber die Tokens. False = Routine uebergehen.
function TRoutineScanner.Walk: Boolean;
var
  i, k, Member : Integer;
  Chain : TChain;
begin
  // Kopf und Deklarationen ueberspringen: 'Q: TFDQuery' ist keine Benutzung
  i := 0;
  while (i < FN) and not ((FToks[i].Kind = tkIdent) and (FToks[i].Low = 'begin')) do
    Inc(i);
  while i < FN do
  begin
    if FToks[i].Kind <> tkIdent then
    begin
      Inc(i);
      Continue;
    end;
    if IsUnsafeAt(i) then Exit(False);
    if IsSym(i - 1, '.') then
    begin
      Inc(i);   // Glied einer Kette, die schon lief
      Continue;
    end;
    Chain := ReadChain(i);
    Member := -1;
    for k := 1 to High(Chain.Toks) do
      if IsMemberWord(Chain.Toks[k].Low) then
      begin
        Member := k;
        Break;
      end;
    if Member < 0 then
      HandlePlainChain(Chain, i)
    else
      HandleMemberChain(Chain, Member);
    i := Chain.Last + 1;
  end;
  Result := True;
end;

// Was die ganze Routine ueber jede Query sagt.
procedure TRoutineScanner.ApplyRoutineFacts;
var
  k : Integer;
  First, H : string;
begin
  for k := 0 to High(FQs) do
  begin
    // nicht erzeugte Query + eigener Methodenaufruf: der kann sie bedienen
    if FBareCall and not FQs[k].Created then
      FQs[k].Incomplete := True;
    // geschachtelte Routine erwaehnt die Query
    First := FQs[k].Key;
    if Pos('.', First) > 0 then First := Copy(First, 1, Pos('.', First) - 1);
    for H in FHidden do
      if H = First then
        FQs[k].Incomplete := True;
    // (b) nur fuer in der Routine erzeugte Queries (Master-Detail, DFM-Params)
    if not FQs[k].Created then
      FQs[k].DynRefs := True;
  end;
end;

// Sortierte Liste ':a, :b' fuer die Meldung (a), gekappt bei MAX_LISTED.
function TQueryJudge.PlaceholderList(const ANames: TArray<string>): string;
var
  List : TStringList;
  Parts : TArray<string>;
  k, Cnt : Integer;
begin
  List := TStringList.Create;
  try
    for k := 0 to High(ANames) do
      List.Add(':' + ANames[k]);
    List.Sort;
    Cnt := List.Count;
    if Cnt > MAX_LISTED then Cnt := MAX_LISTED;
    SetLength(Parts, Cnt);
    for k := 0 to Cnt - 1 do
      Parts[k] := List[k];
    Result := JoinStr(', ', Parts);
    if List.Count > MAX_LISTED then
      Result := Result + ', ...';
  finally
    List.Free;
  end;
end;

// Zeile des SQL-Teils, in dem AName zuerst steht.
function TQueryJudge.LineOfPlaceholder(const AQ: TQueryState;
  const APh: TArray<TPlaceholder>; const AStarts: TArray<Integer>;
  const AName: string): Integer;
var
  e, k : Integer;
begin
  Result := AQ.Parts[0].Line;
  for e := 0 to High(APh) do
  begin
    if not AnsiSameText(APh[e].Name, AName) then Continue;
    for k := High(AStarts) downto 0 do
      if APh[e].Offset >= AStarts[k] then
        Exit(AQ.Parts[k].Line);
    Exit;
  end;
end;

// Traegt irgendein Platzhalter AName - in einer der beiden Lesarten?
function MatchesAny(const APh: TArray<TPlaceholder>; const AName: string): Boolean;
var
  P : TPlaceholder;
begin
  for P in APh do
    if AnsiSameText(P.Name, AName) or AnsiSameText(P.AltName, AName) then Exit(True);
  Result := False;
end;

// AltName des ersten Platzhalters mit diesem Namen.
function AltOf(const APh: TArray<TPlaceholder>; const AName: string): string;
var
  P : TPlaceholder;
begin
  for P in APh do
    if AnsiSameText(P.Name, AName) then Exit(P.AltName);
  Result := '';
end;

function HasRef(const ARefs: TArray<TRef>; const AName: string): Boolean;
var
  R : TRef;
begin
  for R in ARefs do
    if AnsiSameText(R.Name, AName) then Exit(True);
  Result := False;
end;

// (a) ParamByName ohne Platzhalter
procedure TQueryJudge.JudgeUnknown(const AQ: TQueryState;
  const ANames: TArray<string>; const APhAll: TArray<TPlaceholder>);
var
  R : TRef;
  Iss : TParamNameIssue;
  List : string;
begin
  List := PlaceholderList(ANames);
  for R in AQ.Refs do
  begin
    if not R.Throws or MatchesAny(APhAll, R.Name) then Continue;
    Iss.Kind := pikUnknownParam;
    Iss.Line := R.Line;
    Iss.Query := AQ.Display;
    Iss.Param := R.Name;
    Iss.Placeholders := List;
    AddIssue(Iss);
  end;
end;

// (b) Platzhalter ohne Zuweisung
procedure TQueryJudge.JudgeUnassigned(const AQ: TQueryState;
  const ANames: TArray<string>; const APh: TArray<TPlaceholder>;
  const AStarts: TArray<Integer>);
var
  Name : string;
  Iss : TParamNameIssue;
begin
  if AQ.DynRefs then Exit;
  for Name in ANames do
  begin
    if HasRef(AQ.Refs, Name) or HasRef(AQ.Refs, AltOf(APh, Name)) then Continue;
    Iss.Kind := pikUnassignedPlaceholder;
    Iss.Line := LineOfPlaceholder(AQ, APh, AStarts, Name);
    Iss.Query := AQ.Display;
    Iss.Param := Name;
    Iss.Placeholders := '';
    AddIssue(Iss);
  end;
end;

procedure TQueryJudge.Judge(const AQ: TQueryState);
var
  Joined : TStringBuilder;
  Starts : TArray<Integer>;
  Ph, PhAll : TArray<TPlaceholder>;
  Names : TArray<string>;
  Info, InfoAll : TSqlScanInfo;
  Sql : string;
  k : Integer;
begin
  if AQ.Incomplete or (Length(AQ.Parts) = 0) or (Length(AQ.Refs) = 0) then Exit;
  // Teile verbinden, Teilanfaenge fuer die Zeilenzuordnung merken
  SetLength(Starts, Length(AQ.Parts));
  Joined := TStringBuilder.Create;
  try
    for k := 0 to High(AQ.Parts) do
    begin
      if k > 0 then Joined.Append(string(#10));
      Starts[k] := Joined.Length + 1;
      Joined.Append(AQ.Parts[k].Text);
    end;
    Sql := Joined.ToString;
  finally
    Joined.Free;
  end;
  Ph := ScanPlaceholders(Sql, cmSkipComments, Info);
  PhAll := ScanPlaceholders(Sql, cmReadComments, InfoAll);
  if Info.Positional or Info.Unbalanced then Exit;
  Names := UniqueNames(Ph);
  JudgeUnknown(AQ, Names, PhAll);
  // Programmblock: ':v' kann eine lokale PSQL/PL-SQL-Variable sein
  if not Info.Block then
    JudgeUnassigned(AQ, Names, Ph, Starts);
end;

// nach Zeile sortieren (Einfuegesortierung, stabil, wenige Eintraege)
procedure TQueryJudge.SortIssues;
var
  k, m : Integer;
  Tmp : TParamNameIssue;
begin
  for k := 1 to High(FIssues) do
  begin
    Tmp := FIssues[k];
    m := k - 1;
    while (m >= 0) and (FIssues[m].Line > Tmp.Line) do
    begin
      FIssues[m + 1] := FIssues[m];
      Dec(m);
    end;
    FIssues[m + 1] := Tmp;
  end;
end;

function TQueryJudge.Run(const AQs: TArray<TQueryState>): TArray<TParamNameIssue>;
var
  Q : TQueryState;
begin
  FIssues := nil;
  for Q in AQs do
    Judge(Q);
  SortIssues;
  Result := FIssues;
end;

function TRoutineScanner.Run(const ACode, AHidden: string;
  AFirstLine: Integer): TArray<TParamNameIssue>;
var
  Tz : TTokenizer;
  J : TQueryJudge;
  Hidden : TArray<TTok>;
  k : Integer;
begin
  Result := nil;
  Tz := TTokenizer.Create;
  try
    FToks := Tz.Run(ACode, AFirstLine);
    Hidden := Tz.Run(AHidden, AFirstLine);
  finally
    Tz.Free;
  end;
  SetLength(FHidden, Length(Hidden));
  for k := 0 to High(Hidden) do
    FHidden[k] := Hidden[k].Low;
  FN := Length(FToks);
  FQs := nil;
  FBareCall := False;
  if not Walk then Exit;
  ApplyRoutineFacts;
  J := TQueryJudge.Create;
  try
    Result := J.Run(FQs);
  finally
    J.Free;
  end;
end;

class function TParamNameScan.ScanRoutine(const ACode: string;
  AFirstLine: Integer; const AHidden: string): TArray<TParamNameIssue>;
var
  S : TRoutineScanner;
begin
  S := TRoutineScanner.Create;
  try
    Result := S.Run(ACode, AHidden, AFirstLine);
  finally
    S.Free;
  end;
end;

class function TParamNameScan.MessageOf(const AIssue: TParamNameIssue): string;
var
  Have : string;
begin
  if AIssue.Kind = pikUnknownParam then
  begin
    if AIssue.Placeholders = '' then
      Have := 'it has no named placeholders'
    else
      Have := 'it has ' + AIssue.Placeholders;
    Result := Format('%s.ParamByName(''%s''): the SQL this routine assigns ' +
      'to %s has no :%s (%s) - raises "parameter not found" at run time',
      [AIssue.Query, AIssue.Param, AIssue.Query, AIssue.Param, Have]);
  end
  else
    Result := Format('%s.SQL uses :%s, but this routine sets other parameters ' +
      'of %s and never this one - execution fails with an unbound parameter ' +
      'or binds NULL. Assign it with ParamByName(''%s'')',
      [AIssue.Query, AIssue.Param, AIssue.Query, AIssue.Param]);
end;

end.

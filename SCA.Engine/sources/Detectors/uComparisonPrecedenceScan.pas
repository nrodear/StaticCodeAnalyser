unit uComparisonPrecedenceScan;

// SCA202 ComparisonPrecedence - der reine Scanner, ohne AST und ohne Datei.
//
// In Pascal binden not, and, or und xor STAERKER als die Vergleiche
// (=, <>, <, >, <=, >=, in). Zwei Schreibweisen kompilieren deshalb
// still und tun etwas anderes, als sie aussehen (FPC-Mikroproben
// 2026-10-23, Praemissen-Tabelle im Katalogeintrag):
//
//   K1 'not' vor einem Vergleich:  if not Count > 0 then
//      wird zu (not Count) > 0. Bei Ganzzahlen ist not das BITWEISE
//      Komplement - die Bedingung ist fuer jedes Count >= 0 falsch. Bei
//      Boolean-Operanden mit = / <> ist (not A) = B gleichwertig zu
//      not (A = B): dort kein Fund.
//   K2 Vergleichskette ueber and/or/xor:  if A = True or B = False then
//      wird zu (A = (True or B)) = False. Das kompiliert NUR, wenn die
//      Operanden Boolean (oder Variant) sind - mit Ganzzahlen, Strings,
//      Aufzaehlungen meldet der Compiler einen Typfehler, dort braucht es
//      keinen Fund.
//
// Nie gemeldet: 'Flags and Mask = 0' (= (Flags and Mask) = 0, das
// korrekte Bit-Test-Idiom), 'X = A or B' (Absicht offen), 'not' hinter
// and/or/* (Flags and not Mask <> 0 ist ebenfalls ein Bit-Test).
//
// Eingabe ist der Quelltext einer Datei; Kommentare und Direktiven,
// String-Literale (auch Delphi-12-Mehrzeiler ''') und asm-Bloecke zaehlen
// nie als Code. Ausgabe sind die Kandidaten mit dem lexikalischen Beleg:
// Proven = der Typ ist belegt (K1: nicht Boolean - Zahl rechts, Zahlmenge
// rechts, Pos/Ord/Length/CompareText... als Operand, .Count/.IndexOf als
// letztes Glied; K2: True/False an einem der Vergleiche). Die Typaufloesung
// nackter Bezeichner macht der Detektor (uComparisonPrecedence) - er
// bekommt sie in OperandIdent/RhsIdent.
//
// Bewusst ohne Generics, Inline-Variablen und Typ-Helfer: die Unit laeuft
// unveraendert im FPC-Pruefstand (Korpus-Abgleich gegen die Python-
// Nachbildung).

interface

uses
  System.SysUtils;

type
  TPrecTokKind = (ptIdent, ptNumber, ptString, ptOp);

  TPrecToken = record
    Kind : TPrecTokKind;
    Low  : string;     // Bezeichner klein ('&Name' behaelt das '&'), sonst der Text
    Pos  : Integer;    // 1-basiert im Quelltext
    Len  : Integer;
    Line : Integer;    // 1-basiert
    Col  : Integer;    // 1-basiert
  end;
  TPrecTokens = array of TPrecToken;

  TPrecClass = (pcNotOperand, pcComparisonChain);

  TPrecHit = record
    Kind         : TPrecClass;
    Line         : Integer;   // K1: Zeile des 'not', K2: des and/or/xor
    Col          : Integer;
    Proven       : Boolean;   // Typ lexikalisch belegt (s. Unit-Kopf)
    Equality     : Boolean;   // K1: der Vergleich ist = oder <>
    OperandIdent : string;    // K1: nackter Bezeichner hinter not (klein), sonst ''
    RhsIdent     : string;    // K1: nackter Bezeichner rechts vom Vergleich (klein), sonst ''
    OpText       : string;    // K1: Vergleichsoperator, K2: and/or/xor (klein)
    LeftText     : string;    // K1: Operand hinter not; K2: Operand links von and/or/xor
    RightText    : string;    // K2: Operand rechts von and/or/xor
  end;
  TPrecHits = array of TPrecHit;

// Zerlegt ASource in Tokens - ohne Kommentare, ohne asm-Bloecke.
function TokenizePrecedence(const ASource: string): TPrecTokens;
// Alle Kandidaten K1 und K2, nach Token-Reihenfolge je Klasse (erst K1).
function ScanPrecedence(const ASource: string): TPrecHits;

implementation

// noinspection-file BeginEndRequired, CyclomaticComplexity, DeepNesting, LongMethod, MultipleExit, TooLongLine

const
  // Reservierte Woerter, die kein Operand sein koennen (klein).
  RESERVED: array[0..58] of string = (
    'and', 'or', 'xor', 'not', 'div', 'mod', 'shl', 'shr', 'in', 'is', 'as',
    'then', 'do', 'else', 'of', 'begin', 'end', 'if', 'while', 'until',
    'repeat', 'case', 'try', 'except', 'finally', 'with', 'for', 'to',
    'downto', 'var', 'const', 'type', 'procedure', 'function', 'raise',
    'array', 'set', 'record', 'class', 'object', 'label', 'goto', 'nil',
    'inherited', 'asm', 'constructor', 'destructor', 'property', 'out',
    'packed', 'uses', 'unit', 'program', 'interface', 'implementation',
    'initialization', 'finalization', 'resourcestring', 'threadvar');
  RESERVED2: array[0..4] of string = (
    'exports', 'library', 'operator', 'dispinterface', 'file');
  // Ende eines Ausdrucksfensters (if/while/until/:=) auf Tiefe 0.
  WIN_STOP: array[0..11] of string = (
    'then', 'do', 'else', 'end', 'until', 'begin', 'to', 'downto', 'of',
    'except', 'finally', 'repeat');
  // Was hinter dem '>' einer Typargumentliste stehen darf.
  GEN_FOLLOW_OPS: array[0..6] of string = ('.', '(', ')', ']', ';', ',', ':=');
  GEN_FOLLOW_IDS: array[0..12] of string = (
    'then', 'do', 'and', 'or', 'xor', 'else', 'of', 'end', 'until', 'to',
    'downto', 'is', 'as');
  // Operand-Aufrufe mit Ganzzahl-Ergebnis: 'not Pos(...) > 0'.
  INT_FUNCS: array[0..14] of string = (
    'pos', 'posex', 'ord', 'length', 'comparetext', 'comparestr',
    'ansicomparetext', 'ansicomparestr', 'strcomp', 'stricomp', 'sizeof',
    'round', 'trunc', 'strtoint', 'strtointdef');
  // Letztes Glied einer Kette mit Ganzzahl-Ergebnis: 'not List.Count = 0'.
  INT_MEMBERS: array[0..5] of string = (
    'count', 'indexof', 'indexofname', 'indexofobject', 'selcount',
    'itemindex');
  // Letztes Glied einer Kette mit Boolean-Ergebnis - mit = / <> ist
  // (not X.Checked) = Y gleichwertig zu not (X.Checked = Y).
  BOOL_MEMBERS: array[0..13] of string = (
    'checked', 'visible', 'enabled', 'active', 'readonly', 'modified',
    'focused', 'showing', 'eof', 'bof', 'isempty', 'selected', 'expanded',
    'down');

function InList(const S: string; const AList: array of string): Boolean;
var
  i : Integer;
begin
  for i := Low(AList) to High(AList) do
    if AList[i] = S then
      Exit(True);
  Result := False;
end;

function IsReserved(const S: string): Boolean;
begin
  Result := InList(S, RESERVED) or InList(S, RESERVED2);
end;

function IsDigitCh(C: Char): Boolean; inline;
begin
  Result := (C >= '0') and (C <= '9');
end;

function IsHexCh(C: Char): Boolean; inline;
begin
  Result := IsDigitCh(C) or ((C >= 'a') and (C <= 'f')) or
            ((C >= 'A') and (C <= 'F'));
end;

function IsIdStart(C: Char): Boolean; inline;
begin
  Result := ((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z')) or
            (C = '_') or (Ord(C) > 127);
end;

function IsIdChar(C: Char): Boolean; inline;
begin
  Result := IsIdStart(C) or IsDigitCh(C);
end;

// --- Tokenizer -------------------------------------------------------------

type
  TPrecLexer = class
  private
    FSrc       : string;
    FN         : Integer;
    FI         : Integer;   // 1-basierter Lesezeiger
    FLine      : Integer;
    FLineStart : Integer;   // Index des ersten Zeichens der aktuellen Zeile
    FInAsm     : Boolean;
    FToks      : TPrecTokens;
    FCount     : Integer;
    procedure Add(AKind: TPrecTokKind; AStart, AEnd: Integer);
    // Zeilenzaehlung fuer den Bereich [AFrom, ATo) (Kommentare, Mehrzeiler).
    procedure CountLines(AFrom, ATo: Integer);
    function StringEnd(AStart: Integer): Integer;
    function MultiLineStringEnd(AStart: Integer): Integer;
  public
    constructor Create(const ASource: string);
    function Run: TPrecTokens;
  end;

constructor TPrecLexer.Create(const ASource: string);
begin
  inherited Create;
  FSrc := ASource;
  FN := Length(ASource);
  FI := 1;
  FLine := 1;
  FLineStart := 1;
end;

procedure TPrecLexer.Add(AKind: TPrecTokKind; AStart, AEnd: Integer);
begin
  if FInAsm then Exit;
  if FCount = Length(FToks) then
    SetLength(FToks, FCount * 2 + 64);
  FToks[FCount].Kind := AKind;
  if AKind = ptIdent then
    FToks[FCount].Low := LowerCase(Copy(FSrc, AStart, AEnd - AStart))
  else
    FToks[FCount].Low := Copy(FSrc, AStart, AEnd - AStart);
  FToks[FCount].Pos  := AStart;
  FToks[FCount].Len  := AEnd - AStart;
  FToks[FCount].Line := FLine;
  FToks[FCount].Col  := AStart - FLineStart + 1;
  Inc(FCount);
end;

procedure TPrecLexer.CountLines(AFrom, ATo: Integer);
var
  k : Integer;
begin
  for k := AFrom to ATo - 1 do
    if FSrc[k] = #10 then
    begin
      Inc(FLine);
      FLineStart := k + 1;
    end;
end;

// Ende (exklusiv) eines '...'-Literals ab AStart (dem Apostroph). '' ist
// ein Apostroph im Literal; ein offenes Literal endet am Zeilenende.
function TPrecLexer.StringEnd(AStart: Integer): Integer;
var
  j : Integer;
begin
  j := AStart + 1;
  while j <= FN do
  begin
    if FSrc[j] = '''' then
    begin
      if (j < FN) and (FSrc[j + 1] = '''') then
      begin
        Inc(j, 2);
        Continue;
      end;
      Exit(j + 1);
    end;
    if FSrc[j] = #10 then
      Exit(j);
    Inc(j);
  end;
  Result := j;
end;

// Delphi-12-Mehrzeiler: ''' allein am Zeilenende eroeffnet ihn, eine
// Zeile, die (nach Leerraum) mit ''' beginnt, schliesst ihn. 0 = kein
// Mehrzeiler an AStart.
function TPrecLexer.MultiLineStringEnd(AStart: Integer): Integer;
var
  j : Integer;
begin
  Result := 0;
  if (AStart + 2 > FN) or (FSrc[AStart + 1] <> '''') or
     (FSrc[AStart + 2] <> '''') then Exit;
  j := AStart + 3;
  while (j <= FN) and ((FSrc[j] = ' ') or (FSrc[j] = #9) or (FSrc[j] = #13)) do
    Inc(j);
  if (j <= FN) and (FSrc[j] <> #10) then Exit;
  // Schliessende Zeile suchen.
  while j <= FN do
  begin
    // j steht auf einem #10: naechste Zeile pruefen.
    Inc(j);
    while (j <= FN) and ((FSrc[j] = ' ') or (FSrc[j] = #9)) do
      Inc(j);
    if (j + 2 <= FN) and (FSrc[j] = '''') and (FSrc[j + 1] = '''') and
       (FSrc[j + 2] = '''') then
      Exit(j + 3);
    while (j <= FN) and (FSrc[j] <> #10) do
      Inc(j);
  end;
  Result := FN + 1;
end;

function TPrecLexer.Run: TPrecTokens;
var
  c   : Char;
  a, j, k : Integer;
  W   : string;
begin
  while FI <= FN do
  begin
    c := FSrc[FI];
    if c = #10 then
    begin
      Inc(FLine);
      Inc(FI);
      FLineStart := FI;
      Continue;
    end;
    if (c = ' ') or (c = #9) or (c = #13) or (c = #12) or (c = #11) or (c = #0) then
    begin
      Inc(FI);
      Continue;
    end;
    // Kommentare und Direktiven
    if (c = '/') and (FI < FN) and (FSrc[FI + 1] = '/') then
    begin
      while (FI <= FN) and (FSrc[FI] <> #10) do
        Inc(FI);
      Continue;
    end;
    if c = '{' then
    begin
      j := FI + 1;
      while (j <= FN) and (FSrc[j] <> '}') do
        Inc(j);
      if j <= FN then Inc(j);
      CountLines(FI, j);
      FI := j;
      Continue;
    end;
    if (c = '(') and (FI < FN) and (FSrc[FI + 1] = '*') then
    begin
      j := FI + 2;
      while (j < FN) and not ((FSrc[j] = '*') and (FSrc[j + 1] = ')')) do
        Inc(j);
      if j < FN then
        Inc(j, 2)
      else
        j := FN + 1;
      CountLines(FI, j);
      FI := j;
      Continue;
    end;
    a := FI;
    if c = '''' then
    begin
      j := MultiLineStringEnd(a);
      if j > 0 then
      begin
        Add(ptString, a, j);
        CountLines(a, j);
      end
      else
      begin
        j := StringEnd(a);
        Add(ptString, a, j);
      end;
      FI := j;
      Continue;
    end;
    if c = '#' then
    begin
      j := a + 1;
      if (j <= FN) and (FSrc[j] = '$') then
      begin
        Inc(j);
        while (j <= FN) and IsHexCh(FSrc[j]) do Inc(j);
      end
      else
        while (j <= FN) and IsDigitCh(FSrc[j]) do Inc(j);
      Add(ptString, a, j);
      FI := j;
      Continue;
    end;
    if IsDigitCh(c) then
    begin
      j := a + 1;
      while (j <= FN) and IsDigitCh(FSrc[j]) do Inc(j);
      if (j < FN) and (FSrc[j] = '.') and IsDigitCh(FSrc[j + 1]) then
      begin
        Inc(j);
        while (j <= FN) and IsDigitCh(FSrc[j]) do Inc(j);
      end;
      if (j < FN) and ((FSrc[j] = 'e') or (FSrc[j] = 'E')) and
         (IsDigitCh(FSrc[j + 1]) or (FSrc[j + 1] = '+') or (FSrc[j + 1] = '-')) then
      begin
        k := j + 1;
        if (FSrc[k] = '+') or (FSrc[k] = '-') then Inc(k);
        if (k <= FN) and IsDigitCh(FSrc[k]) then
        begin
          j := k;
          while (j <= FN) and IsDigitCh(FSrc[j]) do Inc(j);
        end;
      end;
      Add(ptNumber, a, j);
      FI := j;
      Continue;
    end;
    if c = '$' then
    begin
      j := a + 1;
      while (j <= FN) and IsHexCh(FSrc[j]) do Inc(j);
      Add(ptNumber, a, j);
      FI := j;
      Continue;
    end;
    if (c = '&') and (FI < FN) and IsIdStart(FSrc[FI + 1]) then
    begin
      // &Name: ein Bezeichner, auch wenn Name ein reserviertes Wort ist.
      j := a + 1;
      while (j <= FN) and IsIdChar(FSrc[j]) do Inc(j);
      Add(ptIdent, a, j);
      FI := j;
      Continue;
    end;
    if IsIdStart(c) then
    begin
      j := a + 1;
      while (j <= FN) and IsIdChar(FSrc[j]) do Inc(j);
      W := LowerCase(Copy(FSrc, a, j - a));
      if FInAsm then
      begin
        if W = 'end' then
        begin
          FInAsm := False;
          Add(ptIdent, a, j);
        end;
      end
      else if W = 'asm' then
        FInAsm := True
      else
        Add(ptIdent, a, j);
      FI := j;
      Continue;
    end;
    if FI < FN then
    begin
      W := Copy(FSrc, FI, 2);
      if (W = '<>') or (W = '<=') or (W = '>=') or (W = ':=') or (W = '..') then
      begin
        Add(ptOp, a, a + 2);
        Inc(FI, 2);
        Continue;
      end;
    end;
    Add(ptOp, a, a + 1);
    Inc(FI);
  end;
  SetLength(FToks, FCount);
  Result := FToks;
end;

function TokenizePrecedence(const ASource: string): TPrecTokens;
var
  L : TPrecLexer;
begin
  L := TPrecLexer.Create(ASource);
  try
    Result := L.Run;
  finally
    L.Free;
  end;
end;

// --- Scanner ---------------------------------------------------------------

type
  TPrecScanner = class
  private
    FSrc   : string;
    FT     : TPrecTokens;
    FN     : Integer;
    FHits  : TPrecHits;
    FCount : Integer;
    FSeen  : array of Boolean;   // K2: and/or/xor-Token schon gemeldet
    function IsOp(I: Integer; const S: string): Boolean;
    function IsKw(I: Integer; const S: string): Boolean;
    function IsPlainId(I: Integer): Boolean;
    function IsRelop(I: Integer): Boolean;
    function IsBoolLit(I: Integer): Boolean;
    function MatchClose(J: Integer): Integer;
    function GenericClose(J: Integer): Integer;
    function OperandEnd(J: Integer): Integer;
    function SpanText(AFrom, ATo: Integer): string;
    procedure AddHit(const H: TPrecHit);
    procedure ScanNotOperands;
    procedure CheckNot(I, R: Integer);
    procedure ScanChains;
    procedure ScanLevel(A, B: Integer);
    procedure CheckSegment(const AKinds: array of Char;
      const AIdx: array of Integer; ACount: Integer);
  public
    constructor Create(const ASource: string);
    function Run: TPrecHits;
  end;

constructor TPrecScanner.Create(const ASource: string);
begin
  inherited Create;
  FSrc := ASource;
  FT := TokenizePrecedence(ASource);
  FN := Length(FT);
  SetLength(FSeen, FN);
end;

function TPrecScanner.IsOp(I: Integer; const S: string): Boolean;
begin
  Result := (I >= 0) and (I < FN) and (FT[I].Kind = ptOp) and (FT[I].Low = S);
end;

function TPrecScanner.IsKw(I: Integer; const S: string): Boolean;
begin
  Result := (I >= 0) and (I < FN) and (FT[I].Kind = ptIdent) and (FT[I].Low = S);
end;

function TPrecScanner.IsPlainId(I: Integer): Boolean;
begin
  Result := (I >= 0) and (I < FN) and (FT[I].Kind = ptIdent) and
            not IsReserved(FT[I].Low);
end;

function TPrecScanner.IsRelop(I: Integer): Boolean;
var
  S : string;
begin
  Result := False;
  if (I < 0) or (I >= FN) then Exit;
  S := FT[I].Low;
  if FT[I].Kind = ptOp then
    Result := (S = '=') or (S = '<>') or (S = '<') or (S = '>') or
              (S = '<=') or (S = '>=')
  else if FT[I].Kind = ptIdent then
    Result := S = 'in';
end;

function TPrecScanner.IsBoolLit(I: Integer): Boolean;
begin
  Result := IsKw(I, 'true') or IsKw(I, 'false');
end;

// FT[J] ist '(' oder '[': Index NACH der passenden Klammer, -1 ohne.
function TPrecScanner.MatchClose(J: Integer): Integer;
var
  D : Integer;
  S : string;
begin
  D := 0;
  while J < FN do
  begin
    if FT[J].Kind = ptOp then
    begin
      S := FT[J].Low;
      if (S = '(') or (S = '[') then
        Inc(D)
      else if (S = ')') or (S = ']') then
      begin
        Dec(D);
        if D = 0 then
          Exit(J + 1);
      end;
    end;
    Inc(J);
  end;
  Result := -1;
end;

// FT[J] ist '<' direkt hinter einem Bezeichner: Index des schliessenden
// '>' einer Typargumentliste ('TList<Integer>.Create', 'IsType<T>'),
// sonst -1. Innen nur Bezeichner, '.', ',' und geschachtelte <>; dahinter
// eines der GEN_FOLLOW-Tokens - 'A < B > C' bleibt ein Vergleich.
function TPrecScanner.GenericClose(J: Integer): Integer;
var
  D, K, F : Integer;
  S : string;
begin
  Result := -1;
  if not (IsOp(J, '<') and IsPlainId(J - 1)) then Exit;
  D := 1;
  K := J + 1;
  while (K < FN) and (K <= J + 40) do
  begin
    S := FT[K].Low;
    if FT[K].Kind = ptIdent then
    begin
      if IsReserved(S) and (S <> 'array') and (S <> 'of') then
        Exit(-1);
    end
    else if (FT[K].Kind = ptOp) and ((S = '.') or (S = ',')) then
      // erlaubt
    else if (FT[K].Kind = ptOp) and (S = '<') then
      Inc(D)
    else if (FT[K].Kind = ptOp) and (S = '>') then
    begin
      Dec(D);
      if D = 0 then
      begin
        F := K + 1;
        if F >= FN then Exit(K);
        if ((FT[F].Kind = ptOp) and InList(FT[F].Low, GEN_FOLLOW_OPS)) or
           ((FT[F].Kind = ptIdent) and InList(FT[F].Low, GEN_FOLLOW_IDS)) then
          Exit(K);
        Exit(-1);
      end;
    end
    else
      Exit(-1);
    Inc(K);
  end;
end;

// Index NACH dem Operanden ab J: Bezeichnerkette mit Aufrufen, Indizes,
// '^' und Typargumenten, Klammerausdruck mit Kette, Literal, nil. -1 =
// an J beginnt kein Operand.
function TPrecScanner.OperandEnd(J: Integer): Integer;
var
  C : Integer;
  S : string;
begin
  Result := -1;
  if J >= FN then Exit;
  if IsOp(J, '@') then Inc(J);
  if IsKw(J, 'inherited') then Inc(J);
  if J >= FN then Exit;
  S := FT[J].Low;
  case FT[J].Kind of
    ptOp:
      begin
        if S <> '(' then Exit;
        J := MatchClose(J);
        if J < 0 then Exit;
      end;
    ptNumber:
      Exit(J + 1);
    ptString:
      begin
        while (J < FN) and (FT[J].Kind = ptString) do
          Inc(J);
        Exit(J);
      end;
    ptIdent:
      begin
        if S = 'nil' then Exit(J + 1);
        if IsReserved(S) then Exit;
        Inc(J);
      end;
  end;
  while J < FN do
  begin
    S := FT[J].Low;
    if FT[J].Kind <> ptOp then Break;
    if (S = '.') and (J + 1 < FN) and (FT[J + 1].Kind = ptIdent) then
      Inc(J, 2)
    else if (S = '(') or (S = '[') then
    begin
      J := MatchClose(J);
      if J < 0 then Exit(-1);
    end
    else if S = '^' then
      Inc(J)
    else if S = '<' then
    begin
      C := GenericClose(J);
      if C < 0 then Break;
      J := C + 1;
    end
    else
      Break;
  end;
  Result := J;
end;

// Originaltext der Tokens [AFrom, ATo) mit einfachen Leerzeichen, hoechstens
// 60 Zeichen.
function TPrecScanner.SpanText(AFrom, ATo: Integer): string;
var
  k : Integer;
  Prev, Cur : string;
  Glue : Boolean;
begin
  Result := '';
  for k := AFrom to ATo - 1 do
  begin
    if (k < 0) or (k >= FN) then Break;
    if k > AFrom then
    begin
      Prev := FT[k - 1].Low;
      Cur := FT[k].Low;
      Glue := ((FT[k].Kind = ptOp) and ((Cur = '.') or (Cur = ',') or
                (Cur = ')') or (Cur = ']') or (Cur = '^'))) or
              ((FT[k - 1].Kind = ptOp) and ((Prev = '.') or (Prev = '(') or
                (Prev = '[') or (Prev = '@'))) or
              ((FT[k].Kind = ptOp) and ((Cur = '(') or (Cur = '[')) and
               ((FT[k - 1].Kind = ptIdent) or (Prev = ')') or (Prev = ']')));
      if not Glue then
        Result := Result + ' ';
    end;
    Result := Result + Copy(FSrc, FT[k].Pos, FT[k].Len);
    if Length(Result) > 60 then
      Exit(Copy(Result, 1, 57) + '...');
  end;
end;

procedure TPrecScanner.AddHit(const H: TPrecHit);
begin
  if FCount = Length(FHits) then
    SetLength(FHits, FCount * 2 + 8);
  FHits[FCount] := H;
  Inc(FCount);
end;

// K1: 'not' am Anfang eines Operanden - hinter if/while/until/case, ':=',
// '(', '[' oder ','. Hinter and/or/*/+ ist 'not' ein Teil des Operanden
// ('Flags and not Mask <> 0' = Bit-Test) und bleibt still.
procedure TPrecScanner.ScanNotOperands;
var
  i, E : Integer;
  P : string;
  Starts : Boolean;
begin
  for i := 1 to FN - 1 do
  begin
    if not IsKw(i, 'not') then Continue;
    P := FT[i - 1].Low;
    if FT[i - 1].Kind = ptIdent then
      Starts := (P = 'if') or (P = 'while') or (P = 'until') or (P = 'case')
    else if FT[i - 1].Kind = ptOp then
      Starts := (P = ':=') or (P = '(') or (P = '[') or (P = ',')
    else
      Starts := False;
    if not Starts then Continue;
    E := OperandEnd(i + 1);
    if (E < 0) or not IsRelop(E) then Continue;
    CheckNot(i, E);
  end;
end;

// I = 'not', R = der Vergleichsoperator direkt hinter dem Operanden.
procedure TPrecScanner.CheckNot(I, R: Integer);
var
  H : TPrecHit;
  RK, Q, A, K, D : Integer;
  S, LastMember : string;
begin
  H := Default(TPrecHit);
  H.Kind := pcNotOperand;
  H.Line := FT[I].Line;
  H.Col := FT[I].Col;
  H.OpText := FT[R].Low;
  H.Equality := (H.OpText = '=') or (H.OpText = '<>');
  H.LeftText := SpanText(I + 1, R);
  // Rechte Seite
  RK := R + 1;
  if IsBoolLit(RK) then Exit;   // (not B) = True ist gleichwertig
  Q := RK;
  if IsOp(Q, '-') or IsOp(Q, '+') then Inc(Q);
  if (Q < FN) and (FT[Q].Kind = ptNumber) then
    H.Proven := True;
  if IsOp(RK, '[') then
  begin
    Q := RK + 1;
    if IsOp(Q, '-') then Inc(Q);
    if (Q < FN) and (FT[Q].Kind = ptNumber) then
      H.Proven := True;
  end;
  if IsPlainId(RK) and (OperandEnd(RK) = RK + 1) then
    H.RhsIdent := FT[RK].Low;
  // Operand
  A := I + 1;
  if IsPlainId(A) then
  begin
    if R = A + 1 then
      H.OperandIdent := FT[A].Low;
    if IsOp(A + 1, '(') and InList(FT[A].Low, INT_FUNCS) then
      H.Proven := True;
    // Letztes Glied der Kette - Aufruf-/Indexklammern und '^' am Ende
    // ueberspringen ('L.IndexOf(S)' -> indexof).
    K := R - 1;
    while (K > A) and (FT[K].Kind = ptOp) and
          ((FT[K].Low = ')') or (FT[K].Low = ']') or (FT[K].Low = '^')) do
    begin
      if FT[K].Low = '^' then
      begin
        Dec(K);
        Continue;
      end;
      D := 0;
      while K > A do
      begin
        S := FT[K].Low;
        if (FT[K].Kind = ptOp) and ((S = ')') or (S = ']')) then
          Inc(D)
        else if (FT[K].Kind = ptOp) and ((S = '(') or (S = '[')) then
        begin
          Dec(D);
          if D = 0 then Break;
        end;
        Dec(K);
      end;
      Dec(K);
    end;
    LastMember := '';
    if (K >= A) and (FT[K].Kind = ptIdent) then
      LastMember := FT[K].Low;
    if (R > A + 1) and InList(LastMember, INT_MEMBERS) then
      H.Proven := True;
    if H.Equality and (R > A + 1) and InList(LastMember, BOOL_MEMBERS) then
      Exit;
  end;
  AddHit(H);
end;

// K2: Ausdrucksfenster hinter if/while/until/:= bis zum ersten then/do/
// else/end/until/begin/to/downto/of/except/finally/repeat bzw. ';' auf
// Tiefe 0 (oder der Klammer, die das Fenster schliesst).
procedure TPrecScanner.ScanChains;
var
  i, j, D : Integer;
  S : string;
begin
  for i := 0 to FN - 1 do
  begin
    S := FT[i].Low;
    if not (((FT[i].Kind = ptIdent) and ((S = 'if') or (S = 'while') or (S = 'until'))) or
            ((FT[i].Kind = ptOp) and (S = ':='))) then
      Continue;
    j := i + 1;
    D := 0;
    while j < FN do
    begin
      S := FT[j].Low;
      if FT[j].Kind = ptOp then
      begin
        if (S = '(') or (S = '[') then
          Inc(D)
        else if (S = ')') or (S = ']') then
        begin
          Dec(D);
          if D < 0 then Break;
        end
        else if (D = 0) and (S = ';') then
          Break;
      end
      else if (D = 0) and (FT[j].Kind = ptIdent) and InList(S, WIN_STOP) then
        Break;
      Inc(j);
    end;
    ScanLevel(i + 1, j);
  end;
end;

// Eine Klammerebene [A, B): Vergleiche (R), and/or/xor (L) und Trenner
// (, .. : ; := und die Fenster-Endwoerter) sammeln; Klammern rekursiv.
procedure TPrecScanner.ScanLevel(A, B: Integer);
var
  Kinds : array of Char;
  Idx   : array of Integer;
  Cnt, J, M, C : Integer;
  S : string;

  procedure Push(AKind: Char; AIndex: Integer);
  begin
    if Cnt = Length(Kinds) then
    begin
      SetLength(Kinds, Cnt * 2 + 8);
      SetLength(Idx, Cnt * 2 + 8);
    end;
    Kinds[Cnt] := AKind;
    Idx[Cnt] := AIndex;
    Inc(Cnt);
  end;

begin
  Cnt := 0;
  J := A;
  while J < B do
  begin
    S := FT[J].Low;
    if (FT[J].Kind = ptOp) and ((S = '(') or (S = '[')) then
    begin
      M := MatchClose(J);
      if (M < 0) or (M > B) then Exit;
      ScanLevel(J + 1, M - 1);
      J := M;
      Continue;
    end;
    if ((FT[J].Kind = ptOp) and ((S = ',') or (S = '..') or (S = ':') or
        (S = ';') or (S = ':='))) or
       ((FT[J].Kind = ptIdent) and InList(S, WIN_STOP)) then
      Push('|', J)
    else if (FT[J].Kind = ptOp) and (S = '<') then
    begin
      C := GenericClose(J);
      if (C >= 0) and (C < B) then
      begin
        J := C + 1;
        Continue;
      end;
      Push('R', J);
    end
    else if IsRelop(J) then
      Push('R', J)
    else if (FT[J].Kind = ptIdent) and ((S = 'and') or (S = 'or') or (S = 'xor')) then
      Push('L', J);
    Inc(J);
  end;
  Push('|', B);
  CheckSegment(Kinds, Idx, Cnt);
end;

// Je Segment zwischen zwei Trennern: liegt ein and/or/xor zwischen dem
// ersten und dem letzten Vergleich, ist das eine Kette (K2). Gemeldet
// wird das erste solche and/or/xor des Segments.
procedure TPrecScanner.CheckSegment(const AKinds: array of Char;
  const AIdx: array of Integer; ACount: Integer);
var
  SegStart, k, m, q, FirstR, LastR, L, RBefore, RAfter : Integer;
  H : TPrecHit;
begin
  SegStart := 0;
  for k := 0 to ACount - 1 do
  begin
    if AKinds[k] <> '|' then Continue;
    // Segment [SegStart, k)
    FirstR := -1;
    LastR := -1;
    for m := SegStart to k - 1 do
      if AKinds[m] = 'R' then
      begin
        if FirstR < 0 then FirstR := AIdx[m];
        LastR := AIdx[m];
      end;
    if (FirstR >= 0) and (LastR > FirstR) then
      for m := SegStart to k - 1 do
      begin
        if AKinds[m] <> 'L' then Continue;
        L := AIdx[m];
        if (L <= FirstR) or (L >= LastR) then Continue;
        if not FSeen[L] then
        begin
          FSeen[L] := True;
          H := Default(TPrecHit);
          H.Kind := pcComparisonChain;
          H.Line := FT[L].Line;
          H.Col := FT[L].Col;
          H.OpText := FT[L].Low;
          // Die Operanden von and/or/xor: zwischen dem naechsten Vergleich
          // links und dem naechsten rechts.
          RBefore := FirstR;
          RAfter := LastR;
          for q := SegStart to k - 1 do
            if AKinds[q] = 'R' then
            begin
              if (AIdx[q] < L) and (AIdx[q] > RBefore) then RBefore := AIdx[q];
              if (AIdx[q] > L) and (AIdx[q] < RAfter) then RAfter := AIdx[q];
              // Beleg Boolean: True/False direkt an einem der Vergleiche.
              if IsBoolLit(AIdx[q] - 1) or IsBoolLit(AIdx[q] + 1) then
                H.Proven := True;
            end;
          H.LeftText := SpanText(RBefore + 1, L);
          H.RightText := SpanText(L + 1, RAfter);
          AddHit(H);
        end;
        Break;
      end;
    SegStart := k + 1;
  end;
end;

function TPrecScanner.Run: TPrecHits;
begin
  FCount := 0;
  ScanNotOperands;
  ScanChains;
  SetLength(FHits, FCount);
  Result := FHits;
end;

function ScanPrecedence(const ASource: string): TPrecHits;
var
  S : TPrecScanner;
begin
  S := TPrecScanner.Create(ASource);
  try
    Result := S.Run;
  finally
    S.Free;
  end;
end;

end.

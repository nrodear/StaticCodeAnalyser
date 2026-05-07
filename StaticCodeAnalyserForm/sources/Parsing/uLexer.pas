unit uLexer;

// Delphi-Lexer: zerlegt Quelltext in Token-Stream.
// Schlüsselwörter werden case-insensitiv erkannt.

interface

uses
  System.SysUtils,  System.Generics.Collections, System.TypInfo;

type
  TTokenKind = (
    tkUnknown,
    // --- Schlüsselwörter (alphabetisch sortiert für Binärsuche) ---
    tkKwAbstract, tkKwAnd, tkKwArray, tkKwAs, tkKwAsm,
    tkKwBegin, tkKwBreak,
    tkKwCase, tkKwClass, tkKwConst, tkKwConstructor, tkKwContinue,
    tkKwDeprecated, tkKwDestructor, tkKwDiv, tkKwDo, tkKwDownto,
    tkKwElse, tkKwEnd, tkKwExcept, tkKwExit, tkKwExternal,
    tkKwFalse, tkKwFinalization, tkKwFinally, tkKwFor, tkKwForward,
    tkKwFunction, tkKwGoto,
    tkKwIf, tkKwImplementation, tkKwIn, tkKwInherited,
    tkKwInitialization, tkKwInline, tkKwInterface, tkKwIs,
    tkKwLabel, tkKwMod,
    tkKwNil, tkKwNot,
    tkKwObject, tkKwOf, tkKwOn, tkKwOperator, tkKwOr, tkKwOut,
    tkKwOverload, tkKwOverride,
    tkKwPacked, tkKwPrivate, tkKwProcedure, tkKwProgram,
    tkKwProperty, tkKwProtected, tkKwPublic, tkKwPublished,
    tkKwRaise, tkKwRead, tkKwRecord, tkKwReintroduce, tkKwRepeat,
    tkKwResult, tkKwSet, tkKwShl, tkKwShr, tkKwStatic, tkKwString,
    tkKwThen, tkKwTo, tkKwTrue, tkKwTry, tkKwType,
    tkKwUnit, tkKwUntil, tkKwUses,
    tkKwVar, tkKwVirtual,
    tkKwWhile, tkKwWith, tkKwWrite, tkKwXor,
    // --- Bezeichner und Literale ---
    tkIdent,
    tkIntLit, tkFloatLit, tkStrLit,
    // --- Operatoren und Satzzeichen ---
    tkAssign,     // :=
    tkColon,      // :
    tkSemicolon,  // ;
    tkComma,      // ,
    tkDot,        // .
    tkDotDot,     // ..
    tkLParen,     // (
    tkRParen,     // )
    tkLBracket,   // [
    tkRBracket,   // ]
    tkAt,         // @
    tkCaret,      // ^
    tkPlus,       // +
    tkMinus,      // -
    tkStar,       // *
    tkSlash,      // /
    tkEq,         // =
    tkNeq,        // <>
    tkLt,         // <
    tkLtEq,       // <=
    tkGt,         // >
    tkGtEq,       // >=
    // --- Dateiende ---
    tkEof
  );

  TToken = record
    Kind  : TTokenKind;
    Value : string;
    Line  : Integer;
    Col   : Integer;
    function IsKeyword: Boolean;
    function IsMethodHead: Boolean;
    function IsVisibility: Boolean;
  end;

  TLexer = class
  private
    FSource  : string;
    FLen     : Integer;
    FPos     : Integer;    // 1-basiert
    FLine    : Integer;
    FCol     : Integer;
    FPeeked  : Boolean;
    FPeekTok : TToken;

    class var FKeywords: TDictionary<string, TTokenKind>;
    class procedure InitKeywords; static;

    function  CurChar: Char; inline;
    function  PeekChar(Offset: Integer = 1): Char; inline;
    procedure Advance(Count: Integer = 1);
    procedure SkipWhitespace;
    function  ReadLineComment: TToken;
    function  ReadBraceComment: TToken;
    function  ReadParenStarComment: TToken;
    function  ReadString: TToken;
    function  ReadNumber: TToken;
    function  ReadIdent: TToken;
    function  MakeTok(AKind: TTokenKind; const AVal: string;
                      ALine, ACol: Integer): TToken; inline;
    function  ScanNext: TToken;
  public
    class constructor Create;
    class destructor Destroy;

    constructor Create(const ASource: string);

    function Next: TToken;
    function Peek: TToken;
    function Consume(AKind: TTokenKind): TToken;
    function TryConsume(AKind: TTokenKind; out Tok: TToken): Boolean;
    function AtEnd: Boolean;
  end;

implementation

{ TToken }

function TToken.IsKeyword: Boolean;
begin
  Result := (Kind >= tkKwAbstract) and (Kind <= tkKwXor);
end;

function TToken.IsMethodHead: Boolean;
begin
  Result := Kind in [tkKwProcedure, tkKwFunction,
                     tkKwConstructor, tkKwDestructor, tkKwOperator];
end;

function TToken.IsVisibility: Boolean;
begin
  Result := Kind in [tkKwPublic, tkKwPrivate, tkKwProtected, tkKwPublished];
end;

{ TLexer – Klassen-Initialisierung }

class constructor TLexer.Create;
begin
  InitKeywords;
end;

class destructor TLexer.Destroy;
begin
  FreeAndNil(FKeywords);
end;

class procedure TLexer.InitKeywords;
const
  N = 82;
  Names: array[0..N-1] of string = (
    'abstract','and','array','as','asm',
    'begin','break',
    'case','class','const','constructor','continue',
    'deprecated','destructor','div','do','downto',
    'else','end','except','exit','external',
    'false','finalization','finally','for','forward','function','goto',
    'if','implementation','in','inherited','initialization',
    'inline','interface','is',
    'label','mod',
    'nil','not',
    'object','of','on','operator','or','out','overload','override',
    'packed','private','procedure','program','property',
    'protected','public','published',
    'raise','read','record','reintroduce','repeat','result',
    'set','shl','shr','static','string',
    'then','to','true','try','type',
    'unit','until','uses',
    'var','virtual',
    'while','with','write','xor'
  );
  Kinds: array[0..N-1] of TTokenKind = (
    tkKwAbstract,tkKwAnd,tkKwArray,tkKwAs,tkKwAsm,
    tkKwBegin,tkKwBreak,
    tkKwCase,tkKwClass,tkKwConst,tkKwConstructor,tkKwContinue,
    tkKwDeprecated,tkKwDestructor,tkKwDiv,tkKwDo,tkKwDownto,
    tkKwElse,tkKwEnd,tkKwExcept,tkKwExit,tkKwExternal,
    tkKwFalse,tkKwFinalization,tkKwFinally,tkKwFor,tkKwForward,
    tkKwFunction,tkKwGoto,
    tkKwIf,tkKwImplementation,tkKwIn,tkKwInherited,
    tkKwInitialization,tkKwInline,tkKwInterface,tkKwIs,
    tkKwLabel,tkKwMod,
    tkKwNil,tkKwNot,
    tkKwObject,tkKwOf,tkKwOn,tkKwOperator,tkKwOr,tkKwOut,
    tkKwOverload,tkKwOverride,
    tkKwPacked,tkKwPrivate,tkKwProcedure,tkKwProgram,
    tkKwProperty,tkKwProtected,tkKwPublic,tkKwPublished,
    tkKwRaise,tkKwRead,tkKwRecord,tkKwReintroduce,tkKwRepeat,
    tkKwResult,tkKwSet,tkKwShl,tkKwShr,tkKwStatic,tkKwString,
    tkKwThen,tkKwTo,tkKwTrue,tkKwTry,tkKwType,
    tkKwUnit,tkKwUntil,tkKwUses,
    tkKwVar,tkKwVirtual,
    tkKwWhile,tkKwWith,tkKwWrite,tkKwXor
  );
var
  i: Integer;
begin
  FKeywords := TDictionary<string, TTokenKind>.Create(N * 2);
  for i := 0 to N - 1 do
    FKeywords.Add(Names[i], Kinds[i]);
end;

{ TLexer }

constructor TLexer.Create(const ASource: string);
begin
  inherited Create;
  FSource  := ASource;
  FLen     := Length(ASource);
  FPos     := 1;
  FLine    := 1;
  FCol     := 1;
  FPeeked  := False;
end;

function TLexer.CurChar: Char;
begin
  if FPos <= FLen then Result := FSource[FPos]
                  else Result := #0;
end;

function TLexer.PeekChar(Offset: Integer): Char;
var
  p: Integer;
begin
  p := FPos + Offset;
  if p <= FLen then Result := FSource[p]
               else Result := #0;
end;

procedure TLexer.Advance(Count: Integer);
var
  i: Integer;
begin
  for i := 1 to Count do
  begin
    if FPos > FLen then Break;
    if FSource[FPos] = #10 then
    begin
      Inc(FLine);
      FCol := 1;
    end
    else
      Inc(FCol);
    Inc(FPos);
  end;
end;

procedure TLexer.SkipWhitespace;
begin
  while (FPos <= FLen) and (FSource[FPos] <= ' ') do
    Advance;
end;

function TLexer.MakeTok(AKind: TTokenKind; const AVal: string;
  ALine, ACol: Integer): TToken;
begin
  Result.Kind  := AKind;
  Result.Value := AVal;
  Result.Line  := ALine;
  Result.Col   := ACol;
end;

function TLexer.ReadLineComment: TToken;
var
  L, C: Integer;
  Start: Integer;
begin
  L     := FLine;
  C     := FCol;
  Start := FPos;
  while (FPos <= FLen) and (FSource[FPos] <> #10) do
    Advance;
  Result := MakeTok(tkUnknown, Copy(FSource, Start, FPos - Start), L, C);
end;

function TLexer.ReadBraceComment: TToken;
// { ... }  oder  {$ ... } (Compiler-Direktive – wird übersprungen)
var
  L, C: Integer;
begin
  L := FLine; C := FCol;
  Advance; // skip '{'
  while (FPos <= FLen) and (CurChar <> '}') do
    Advance;
  if FPos <= FLen then Advance; // skip '}'
  Result := MakeTok(tkUnknown, '', L, C);
end;

function TLexer.ReadParenStarComment: TToken;
// (* ... *)
var
  L, C: Integer;
begin
  L := FLine; C := FCol;
  Advance(2); // skip '(*'
  while FPos <= FLen do
  begin
    if (CurChar = '*') and (PeekChar = ')') then
    begin
      Advance(2);
      Break;
    end;
    Advance;
  end;
  Result := MakeTok(tkUnknown, '', L, C);
end;

function TLexer.ReadString: TToken;
// Verarbeitet Delphi-Stringliterale: 'text', #nn und Kombinationen wie 'a'#10'b'.
// CurChar zeigt beim Aufruf auf das öffnende ' oder #.
var
  L, C: Integer;
  S   : string;
begin
  L := FLine; C := FCol;
  S := '';
  while FPos <= FLen do
  begin
    if CurChar = '''' then
    begin
      Advance; // öffnendes ' überspringen
      while FPos <= FLen do
      begin
        if CurChar = '''' then
        begin
          Advance; // ' konsumieren
          if (FPos <= FLen) and (CurChar = '''') then
          begin
            // '' innerhalb des Strings = maskiertes einfaches Anführungszeichen
            S := S + '''';
            Advance;
          end
          else
            Break; // schließendes ' – Segment abgeschlossen
        end
        else
        begin
          S := S + CurChar;
          Advance;
        end;
      end;
    end
    else if CurChar = '#' then
    begin
      // Zeichencode #nn: BMP-Bereich (0..65535). Hoehere Codepoints
      // (Astral-Plane) brauchen Surrogate-Paare und werden im Lexer
      // durch U+FFFD (REPLACEMENT CHARACTER) ersetzt - der Source-Text
      // ist dann technisch falsch, aber der Lexer crasht nicht und der
      // Parser sieht weiter ein gueltiges StrLit-Token.
      Advance;
      var Num := '';
      while (FPos <= FLen) and CharInSet(CurChar, ['0'..'9']) do
      begin
        Num := Num + CurChar;
        Advance;
      end;
      var CodePoint := StrToIntDef(Num, 0);
      if (CodePoint < 0) or (CodePoint > $FFFF) then
        S := S + #$FFFD
      else
        S := S + Chr(CodePoint);
    end
    else
      Break; // kein weiteres String-Segment
  end;
  Result := MakeTok(tkStrLit, S, L, C);
end;

function TLexer.ReadNumber: TToken;
var
  L, C  : Integer;
  Start : Integer;
  Kind  : TTokenKind;
begin
  L     := FLine;
  C     := FCol;
  Start := FPos;
  Kind  := tkIntLit;

  if CurChar = '$' then
  begin
    // Hex-Literal
    Advance;
    while CharInSet(CurChar, ['0'..'9', 'A'..'F', 'a'..'f']) do
      Advance;
  end
  else
  begin
    while CharInSet(CurChar, ['0'..'9']) do Advance;
    if (CurChar = '.') and (PeekChar <> '.') then
    begin
      Kind := tkFloatLit;
      Advance;
      while CharInSet(CurChar, ['0'..'9']) do Advance;
    end;
    if CharInSet(CurChar, ['e', 'E']) then
    begin
      Kind := tkFloatLit;
      Advance;
      if CharInSet(CurChar, ['+', '-']) then Advance;
      while CharInSet(CurChar, ['0'..'9']) do Advance;
    end;
  end;
  Result := MakeTok(Kind, Copy(FSource, Start, FPos - Start), L, C);
end;

function TLexer.ReadIdent: TToken;
var
  L, C  : Integer;
  Start : Integer;
  Lower : string;
  Kind  : TTokenKind;
begin
  L     := FLine;
  C     := FCol;
  Start := FPos;
  while (FPos <= FLen) and CharInSet(CurChar, ['A'..'Z','a'..'z','0'..'9','_']) do
    Advance;
  var Raw := Copy(FSource, Start, FPos - Start);
  Lower := Raw.ToLower;
  if not FKeywords.TryGetValue(Lower, Kind) then
    Kind := tkIdent;
  Result := MakeTok(Kind, Raw, L, C);
end;

function TLexer.ScanNext: TToken;
var
  L, C: Integer;
begin
  while True do
  begin
    SkipWhitespace;
    if FPos > FLen then
      Exit(MakeTok(tkEof, '', FLine, FCol));

    L := FLine;
    C := FCol;

    case CurChar of
      // Kommentare
      '/': if PeekChar = '/' then
           begin
             ReadLineComment;
             Continue;
           end
           else
           begin
             Advance;
             Exit(MakeTok(tkSlash, '/', L, C));
           end;
      '{': begin ReadBraceComment; Continue; end;
      '(': if PeekChar = '*' then
           begin
             ReadParenStarComment;
             Continue;
           end
           else
           begin
             Advance;
             Exit(MakeTok(tkLParen, '(', L, C));
           end;

      // Zeichenketten
      '''': Exit(ReadString);
      '#':  Exit(ReadString);

      // Zahlen
      '0'..'9': Exit(ReadNumber);
      '$':      Exit(ReadNumber);

      // Bezeichner und Schlüsselwörter
      'A'..'Z', 'a'..'z', '_': Exit(ReadIdent);

      // Operatoren
      ':': if PeekChar = '=' then
           begin
             Advance(2);
             Exit(MakeTok(tkAssign, ':=', L, C));
           end
           else
           begin
             Advance;
             Exit(MakeTok(tkColon, ':', L, C));
           end;
      ';': begin Advance; Exit(MakeTok(tkSemicolon, ';', L, C)); end;
      ',': begin Advance; Exit(MakeTok(tkComma,     ',', L, C)); end;
      '.': if PeekChar = '.' then
           begin
             Advance(2);
             Exit(MakeTok(tkDotDot, '..', L, C));
           end
           else
           begin
             Advance;
             Exit(MakeTok(tkDot, '.', L, C));
           end;
      ')': begin Advance; Exit(MakeTok(tkRParen,   ')', L, C)); end;
      '[': begin Advance; Exit(MakeTok(tkLBracket, '[', L, C)); end;
      ']': begin Advance; Exit(MakeTok(tkRBracket, ']', L, C)); end;
      '@': begin Advance; Exit(MakeTok(tkAt,        '@', L, C)); end;
      '^': begin Advance; Exit(MakeTok(tkCaret,     '^', L, C)); end;
      '+': begin Advance; Exit(MakeTok(tkPlus,      '+', L, C)); end;
      '-': begin Advance; Exit(MakeTok(tkMinus,     '-', L, C)); end;
      '*': begin Advance; Exit(MakeTok(tkStar,      '*', L, C)); end;
      '=': begin Advance; Exit(MakeTok(tkEq,        '=', L, C)); end;
      '<': if PeekChar = '>' then
           begin
             Advance(2);
             Exit(MakeTok(tkNeq, '<>', L, C));
           end
           else if PeekChar = '=' then
           begin
             Advance(2);
             Exit(MakeTok(tkLtEq, '<=', L, C));
           end
           else
           begin
             Advance;
             Exit(MakeTok(tkLt, '<', L, C));
           end;
      '>': if PeekChar = '=' then
           begin
             Advance(2);
             Exit(MakeTok(tkGtEq, '>=', L, C));
           end
           else
           begin
             Advance;
             Exit(MakeTok(tkGt, '>', L, C));
           end;
    else
      // Token-Wert MUSS vor Advance gelesen werden - sonst zeigt CurChar
      // schon auf das NAECHSTE Zeichen und wir taggen das falsche Zeichen
      // als Unknown. Lokale Variable als Snapshot.
      var UnknownCh := CurChar;
      Advance;
      Result := MakeTok(tkUnknown, UnknownCh, L, C);
      Exit;
    end;
  end;
end;

function TLexer.Next: TToken;
begin
  if FPeeked then
  begin
    Result  := FPeekTok;
    FPeeked := False;
  end
  else
    Result := ScanNext;
end;

function TLexer.Peek: TToken;
begin
  if not FPeeked then
  begin
    FPeekTok := ScanNext;
    FPeeked  := True;
  end;
  Result := FPeekTok;
end;

function TLexer.Consume(AKind: TTokenKind): TToken;
begin
  Result := Next;
  if Result.Kind <> AKind then
    raise Exception.CreateFmt(
      'Zeile %d: Token "%s" erwartet, aber "%s" gefunden.',
      [Result.Line, GetEnumName(TypeInfo(TTokenKind), Ord(AKind)), Result.Value]);
end;

function TLexer.TryConsume(AKind: TTokenKind; out Tok: TToken): Boolean;
begin
  Result := Peek.Kind = AKind;
  if Result then
    Tok := Next;
end;

function TLexer.AtEnd: Boolean;
begin
  Result := Peek.Kind = tkEof;
end;

end.

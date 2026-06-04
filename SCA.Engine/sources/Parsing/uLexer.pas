unit uLexer;

// Delphi-Lexer: zerlegt Quelltext in Token-Stream.
// Schlüsselwörter werden case-insensitiv erkannt.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.TypInfo;

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

  // A.5 Phase 1a: Conditional-Compilation-Stack ohne Skip-Wirkung.
  // Pro {$IFDEF/{$IFNDEF/{$IF wird ein Frame gepusht (immer Active=True
  // in Phase 1a - kein Defines-Eval, kein Token-Skip). Phase 1b/2 wird
  // die Active-Flag aus dem Define-Set ableiten und im Lexer-Loop
  // Tokens skippen wenn nicht Active.
  TConditionalState = record
    Active        : Boolean;  // True = Token-Emit aktiv (Phase 1a: immer True)
    InElse        : Boolean;  // True wenn aktuell im else-Branch
    DirectiveLine : Integer;  // Zeile des oeffnenden {$IFDEF
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

    // A.5 Phase 1a: Conditional-Stack. Top = aktive Direktive.
    FConditionalStack : TArray<TConditionalState>;
    // Statistik: max. erreichte Stack-Tiefe pro Lexer-Lauf
    // (fuer Phase 1b-Audit + Tests).
    FConditionalMaxDepth : Integer;

    // A.5 Phase 1b: Defines-Set + Skip-Schalter.
    // FDefines case-insensitiv, sortiert.
    // FConditionalSkipEnabled: Default False (kompatibel zu Phase 1a -
    // kein Verhaltens-Change). Wenn aktiviert: Token-Stream skipt
    // Branches in denen CurrentlyActive=False.
    FDefines                : TStringList;
    FConditionalSkipEnabled : Boolean;
    // Statistik: wieviele Tokens wurden uebersprungen (fuer Telemetrie).
    FConditionalSkippedTokens : Integer;

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

    // A.5 Phase 1a: Direktive-Recognition + Stack-Pflege.
    procedure HandleConditionalDirective(const ABody: string; ALine: Integer);
    procedure PushConditional(AActive: Boolean; ALine: Integer);
    procedure PopConditional;
    procedure ToggleConditionalToElse;

    // A.5 Phase 1b: Defines-Auswertung + Skip-Helpers.
    function IsDefined(const AName: string): Boolean;
    function CurrentlyActive: Boolean;
    function ParseDirectiveIdent(const ABody: string;
      var Pos: Integer): string;
  public
    class constructor Create;
    class destructor Destroy;

    constructor Create(const ASource: string);

    function Next: TToken;
    function Peek: TToken;
    function Consume(AKind: TTokenKind): TToken;
    function TryConsume(AKind: TTokenKind; out Tok: TToken): Boolean;
    function AtEnd: Boolean;

    // A.5 Phase 1a: Read-only-Zugriff fuer Tests und Telemetrie.
    function ConditionalDepth: Integer;
    function ConditionalMaxDepth: Integer;

    // A.5 Phase 1b: Defines + Skip-Steuerung.
    // Default-Konstruktor laesst FConditionalSkipEnabled=False -
    // Verhalten identisch zu Phase 1a. Aktivierung explizit per
    // EnableConditionalSkipping(<Defines>).
    procedure AddDefine(const AName: string);
    procedure RemoveDefine(const AName: string);
    procedure EnableConditionalSkipping;
    procedure DisableConditionalSkipping;
    function  IsConditionalSkippingEnabled: Boolean;
    function  ConditionalSkippedTokens: Integer;

    destructor Destroy; override;
  end;

// A.5 Phase 1b-Wiring: globale Default-Konfiguration. Wird von
// uParser2.TParser2.ParseSource gelesen und auf jeden neu erzeugten
// Lexer angewendet. CLI-Flags (`--ifdef-aware`, `--define X`) in
// uConsoleRunner setzen diese Variablen vor dem Scan.
//
// Lazy-init: gLexerIfdefDefines wird beim ersten Add erstellt und in
// finalization freigegeben. Thread-safe ist NICHT noetig - CLI-Args
// werden vor dem Scan-Lauf gesetzt, Scan ist single-threaded.
var
  gLexerIfdefSkipEnabled : Boolean = False;
  gLexerIfdefDefines     : TStringList = nil;

procedure LexerIfdefAddDefine(const AName: string);
procedure LexerIfdefRemoveDefine(const AName: string);
procedure LexerIfdefClear;

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
  // A.5 Phase 1b: Defines case-insensitive, sortiert fuer Binary-Search.
  FDefines := TStringList.Create;
  FDefines.CaseSensitive := False;
  FDefines.Sorted        := True;
  FDefines.Duplicates    := dupIgnore;
  FConditionalSkipEnabled   := False;  // Default: kompatibel zu Phase 1a
  FConditionalSkippedTokens := 0;
end;

destructor TLexer.Destroy;
begin
  FDefines.Free;
  inherited;
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
// { ... }  oder  {$ ... } (Compiler-Direktive)
// A.5 Phase 1a: Conditional-Direktiven ({$IFDEF/{$ELSE/{$ENDIF/etc.)
// werden recognized und pflegen FConditionalStack. KEIN Token-Skip in
// Phase 1a - alle Tokens weiter normal emittiert. Phase 1b haengt die
// Active-Flag aus dem Define-Set ab und skippt im Lexer-Loop.
var
  L, C, BodyStart : Integer;
  Body            : string;
begin
  L := FLine; C := FCol;
  Advance; // skip '{'
  BodyStart := FPos;
  while (FPos <= FLen) and (CurChar <> '}') do
    Advance;
  // Body ohne oeffnende/schliessende Klammer
  if FPos > BodyStart then
    Body := Copy(FSource, BodyStart, FPos - BodyStart)
  else
    Body := '';
  if FPos <= FLen then Advance; // skip '}'

  // Direktive-Erkennung: Body muss mit '$' beginnen (= '{$..}')
  if (Length(Body) >= 1) and (Body[1] = '$') then
    HandleConditionalDirective(Body, L);

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
      // Zeichencode #nn (dezimal) ODER #$hhhh (hex). BMP-Bereich
      // (0..65535). Hoehere Codepoints (Astral-Plane) brauchen
      // Surrogate-Paare und werden im Lexer durch U+FFFD (REPLACEMENT
      // CHARACTER) ersetzt - der Source-Text ist dann technisch falsch,
      // aber der Lexer crasht nicht und der Parser sieht weiter ein
      // gueltiges StrLit-Token.
      // Frueher fehlte der `$`-Pfad: `#$41` wurde als `#<leer>` (NUL) +
      // `$41` (separates Number-Token) gelesen - der Hex-Char-Literal
      // tauchte im AST nie zusammenhaengend auf.
      Advance;
      var Num    : string := '';
      var IsHex  : Boolean := False;
      if (FPos <= FLen) and (CurChar = '$') then
      begin
        IsHex := True;
        Advance;
        while (FPos <= FLen) and CharInSet(CurChar,
              ['0'..'9', 'A'..'F', 'a'..'f']) do
        begin
          Num := Num + CurChar;
          Advance;
        end;
      end
      else
      begin
        while (FPos <= FLen) and CharInSet(CurChar, ['0'..'9']) do
        begin
          Num := Num + CurChar;
          Advance;
        end;
      end;
      var CodePoint : Integer;
      if IsHex then
        CodePoint := StrToIntDef('$' + Num, 0)
      else
        CodePoint := StrToIntDef(Num, 0);
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
// A.5 Phase 1b: wenn Conditional-Skipping aktiv UND aktuell in inaktivem
// Branch -> Token verwerfen + naechsten lesen. Direktiven (ReadBrace-
// Comment) werden trotzdem korrekt verarbeitet (Stack-Pflege), nur
// die zurueckgegebenen Tokens werden gefiltert. tkEof darf NIE
// gefiltert werden sonst Endlos-Loop.
begin
  if FPeeked then
  begin
    Result  := FPeekTok;
    FPeeked := False;
  end
  else
    Result := ScanNext;

  if not FConditionalSkipEnabled then Exit;

  while (Result.Kind <> tkEof) and (not CurrentlyActive) do
  begin
    Inc(FConditionalSkippedTokens);
    Result := ScanNext;
  end;
end;

function TLexer.Peek: TToken;
// A.5 Phase 1b: Peek nutzt selbe Skip-Logik wie Next.
begin
  if not FPeeked then
  begin
    FPeekTok := ScanNext;
    if FConditionalSkipEnabled then
      while (FPeekTok.Kind <> tkEof) and (not CurrentlyActive) do
      begin
        Inc(FConditionalSkippedTokens);
        FPeekTok := ScanNext;
      end;
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

function TLexer.ParseDirectiveIdent(const ABody: string;
  var Pos: Integer): string;
// Liest den Identifier nach dem Verb (z.B. nach IFDEF). Skippt
// Leading-Whitespace, liest A..Z, a..z, 0..9, _. Returnt
// uppercase-trimmed.
var
  L, Start : Integer;
begin
  L := Length(ABody);
  while (Pos <= L) and (ABody[Pos] in [#9, ' ']) do Inc(Pos);
  Start := Pos;
  while (Pos <= L) and (ABody[Pos] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Inc(Pos);
  Result := UpperCase(Copy(ABody, Start, Pos - Start));
end;

function TLexer.IsDefined(const AName: string): Boolean;
begin
  Result := FDefines.IndexOf(AName) >= 0;
end;

function TLexer.CurrentlyActive: Boolean;
// True wenn ALLE Stack-Frames Active sind. Sobald irgendwo im Stack
// ein inaktives Frame ist (= wir sind in einem geskippten Branch),
// wird der gesamte Code geskippt - auch bei aktivem Top-Frame.
var
  i : Integer;
begin
  for i := 0 to Length(FConditionalStack) - 1 do
    if not FConditionalStack[i].Active then Exit(False);
  Result := True;
end;

procedure TLexer.HandleConditionalDirective(const ABody: string;
  ALine: Integer);
// Erwartet Body OHNE umschliessende '{' '}'. Body[1] ist '$'.
// Erkennt: $IFDEF X, $IFNDEF X, $IF expr, $ELSEIF expr, $ELSE,
//          $ENDIF, $IFEND. Case-insensitive.
// A.5 Phase 1b: IFDEF/IFNDEF werten gegen FDefines aus. Die
// Active-Flag des gepushten Frames spiegelt das Ergebnis - aber:
// wenn der PARENT bereits inaktiv ist, wird der Frame als Active=False
// gepushed (egal was Defines sagen) damit nested ELSE nicht aktivieren.
// Phase-1b-Limitierung: $IF wird konservativ als Active=True behandelt
// (Expression-Mini-Parser kommt in Phase 2).
var
  i, L         : Integer;
  Verb, Ident  : string;
  ParentActive : Boolean;
  NewActive    : Boolean;
begin
  L := Length(ABody);
  i := 2;  // skip '$'
  Verb := ParseDirectiveIdent(ABody, i);
  ParentActive := CurrentlyActive;

  if Verb = 'IFDEF' then
  begin
    Ident := ParseDirectiveIdent(ABody, i);
    NewActive := ParentActive and IsDefined(Ident);
    PushConditional(NewActive, ALine);
  end
  else if Verb = 'IFNDEF' then
  begin
    Ident := ParseDirectiveIdent(ABody, i);
    NewActive := ParentActive and (not IsDefined(Ident));
    PushConditional(NewActive, ALine);
  end
  else if Verb = 'IF' then
    // Konservativ: Active=True wenn Parent aktiv. Phase 2 expr-eval.
    PushConditional(ParentActive, ALine)
  else if (Verb = 'ELSE') or (Verb = 'ELSEIF') then
    ToggleConditionalToElse
  else if (Verb = 'ENDIF') or (Verb = 'IFEND') then
    PopConditional;
  // Andere Direktiven ($R, $WARN, $INCLUDE, etc.) ignorieren.
end;

procedure TLexer.PushConditional(AActive: Boolean; ALine: Integer);
var
  Frame : TConditionalState;
  L     : Integer;
begin
  Frame.Active        := AActive;
  Frame.InElse        := False;
  Frame.DirectiveLine := ALine;
  L := Length(FConditionalStack);
  SetLength(FConditionalStack, L + 1);
  FConditionalStack[L] := Frame;
  if L + 1 > FConditionalMaxDepth then
    FConditionalMaxDepth := L + 1;
end;

procedure TLexer.PopConditional;
var
  L : Integer;
begin
  L := Length(FConditionalStack);
  if L > 0 then
    SetLength(FConditionalStack, L - 1);
  // Pop ohne Push (z.B. orphan $ENDIF) wird silent ignoriert. Real-
  // world: Defekter Source oder Pre-Compiled-Section - kein
  // Lexer-Crash-Grund.
end;

procedure TLexer.ToggleConditionalToElse;
// A.5 Phase 1b: naive Toggle Top.Active. Korrekt, weil CurrentlyActive
// den GESAMTEN Stack prueft - wenn ein Parent-Frame inaktiv ist,
// bleibt der else-Branch trotzdem inaktiv (parent dominiert).
var
  L : Integer;
begin
  L := Length(FConditionalStack);
  if L > 0 then
  begin
    FConditionalStack[L - 1].InElse := True;
    FConditionalStack[L - 1].Active := not FConditionalStack[L - 1].Active;
  end;
end;

function TLexer.ConditionalDepth: Integer;
begin
  Result := Length(FConditionalStack);
end;

function TLexer.ConditionalMaxDepth: Integer;
begin
  Result := FConditionalMaxDepth;
end;

procedure TLexer.AddDefine(const AName: string);
begin
  if Trim(AName) <> '' then
    FDefines.Add(Trim(AName));
end;

procedure TLexer.RemoveDefine(const AName: string);
var
  Idx : Integer;
begin
  Idx := FDefines.IndexOf(Trim(AName));
  if Idx >= 0 then FDefines.Delete(Idx);
end;

procedure TLexer.EnableConditionalSkipping;
begin
  FConditionalSkipEnabled := True;
end;

procedure TLexer.DisableConditionalSkipping;
begin
  FConditionalSkipEnabled := False;
end;

function TLexer.IsConditionalSkippingEnabled: Boolean;
begin
  Result := FConditionalSkipEnabled;
end;

function TLexer.ConditionalSkippedTokens: Integer;
begin
  Result := FConditionalSkippedTokens;
end;

function TLexer.AtEnd: Boolean;
begin
  Result := Peek.Kind = tkEof;
end;

{ === A.5 Phase 1b Wiring: globale Defines-Liste === }

procedure EnsureLexerIfdefDefines;
begin
  if gLexerIfdefDefines = nil then
  begin
    gLexerIfdefDefines := TStringList.Create;
    gLexerIfdefDefines.CaseSensitive := False;
    gLexerIfdefDefines.Sorted        := True;
    gLexerIfdefDefines.Duplicates    := dupIgnore;
  end;
end;

procedure LexerIfdefAddDefine(const AName: string);
var
  Trimmed : string;
begin
  Trimmed := Trim(AName);
  if Trimmed = '' then Exit;
  EnsureLexerIfdefDefines;
  gLexerIfdefDefines.Add(Trimmed);
end;

procedure LexerIfdefRemoveDefine(const AName: string);
var
  Idx : Integer;
begin
  if gLexerIfdefDefines = nil then Exit;
  Idx := gLexerIfdefDefines.IndexOf(Trim(AName));
  if Idx >= 0 then gLexerIfdefDefines.Delete(Idx);
end;

procedure LexerIfdefClear;
begin
  if gLexerIfdefDefines <> nil then gLexerIfdefDefines.Clear;
end;

finalization
  gLexerIfdefDefines.Free;
  gLexerIfdefDefines := nil;

end.

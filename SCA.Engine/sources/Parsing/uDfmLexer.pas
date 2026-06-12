unit uDfmLexer;

// DFM-Lexer: zerlegt einen Text-DFM-Quelltext in einen Token-Stream.
// Aufbau parallel zu uLexer (Pascal-Lexer): 1-basierte Position, Line/Col-
// Tracking, Peek/Next/Consume-API.
//
// Phase-1-Scope (siehe TODO.md / DFM + Komponentengraph): der Lexer liefert
// nur soviel Detail, wie der Parser fuer die Hierarchie + spaetere Property-
// Auswertung braucht. Geschachtelte Klammer-Blöcke
//   [...]   Sets           -> tkSet      (Roh-Text inkl. Klammern)
//   {...}   Binär-Blobs    -> tkBinary   (Inhalt verworfen, nur Position)
//   <...>   Item-Listen    -> tkItemList (Roh-Text, nested-aware)
//   (...)   Strln-Listen   -> tkStrList  (Roh-Text inkl. Klammern)
// werden als atomare Tokens geliefert, damit der Parser sie einfach skippen
// kann. Wenn spaeter Properties typisiert ausgewertet werden sollen (Phase 2/3),
// kann ein separater Sub-Lexer auf den Raw-Inhalt arbeiten.
//
// Binär-DFM wird hier NICHT behandelt - der Aufrufer muss vorab via
// ObjectBinaryToText konvertieren (siehe Phase 1 TODO).

interface

uses
  System.SysUtils, System.Generics.Collections, System.TypInfo;

type
  TDfmTokenKind = (
    tkUnknown,
    // --- Schlüsselwörter (case-insensitiv) ---
    tkKwObject,     // 'object'
    tkKwInherited,  // 'inherited'
    tkKwInline,     // 'inline'   (TFrame-Inlining)
    tkKwEnd,        // 'end'
    tkKwTrue,       // 'True'
    tkKwFalse,      // 'False'
    // --- Bezeichner und Literale ---
    tkIdent,        // 'Form2', 'TForm2', 'clRed', 'Lines', 'Strings', ...
    tkInteger,      // '0', '42'      (ohne Vorzeichen; '-' ist tkMinus)
    tkFloat,        // '1.5', '1e10'
    tkString,       // 'foo' bzw. 'a'+#10+'b' (Lexer-intern zusammengefügt)
    tkSet,          // '[fsBold, fsItalic]'   (Roh-Text inkl. eckiger Klammern)
    tkBinary,       // '{0102FF...}'          (Inhalt nicht relevant)
    tkItemList,     // '<item ... end ...>'   (Roh-Text inkl. spitzer Klammern)
    tkStrList,      // '(''a'' ''b'')'        (Roh-Text inkl. runder Klammern)
    // --- Trennzeichen ---
    tkColon,        // :  (object-Header: Name : ClassName)
    tkEquals,       // =  (Property = Value)
    tkDot,          // .  (Property-Pfad: Font.Style)
    tkComma,        // ,  (selten; in Sets wird intern verschluckt)
    tkMinus,        // -  (Vorzeichen vor Zahl)
    // --- Dateiende ---
    tkEof
  );

  TDfmToken = record
    Kind  : TDfmTokenKind;
    Value : string;
    Line  : Integer;
    Col   : Integer;
  end;

  TDfmLexer = class
  private
    FSource  : string;
    FLen     : Integer;
    FPos     : Integer;    // 1-basiert (analog uLexer)
    FLine    : Integer;
    FCol     : Integer;
    FPeeked  : Boolean;
    FPeekTok : TDfmToken;

    class var FKeywords: TDictionary<string, TDfmTokenKind>;
    class procedure InitKeywords; static;

    function  CurChar: Char; inline;
    function  PeekChar(Offset: Integer = 1): Char; inline;
    procedure Advance(Count: Integer = 1);
    procedure SkipWhitespace;

    function  ReadIdent: TDfmToken;
    function  ReadNumber: TDfmToken;
    function  ReadString: TDfmToken;
    function  ReadSet: TDfmToken;
    function  ReadBinary: TDfmToken;
    function  ReadItemList: TDfmToken;
    function  ReadStrList: TDfmToken;

    function  MakeTok(AKind: TDfmTokenKind; const AVal: string;
                      ALine, ACol: Integer): TDfmToken; inline;
    function  ScanNext: TDfmToken;
  public
    class constructor Create;
    class destructor Destroy;

    constructor Create(const ASource: string);

    function Next: TDfmToken;
    function Peek: TDfmToken;
    function Consume(AKind: TDfmTokenKind): TDfmToken;
    function TryConsume(AKind: TDfmTokenKind; out Tok: TDfmToken): Boolean;
    function AtEnd: Boolean;
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CanBeClassMethod, CanBeStrictPrivate, CyclomaticComplexity, DeepNesting, DuplicateBlock, GodClass, GroupedDeclaration, IfElseBegin, LocalConstantName, LongMethod, MultipleExit, PublicMemberWithoutDoc, RaisingRawException, RedundantJump, StringConcatInLoop, TooLongLine, UnsortedUses
// DFM-Lexer-Token-Concat: kurze property-Name-/Value-Strings.

{ TDfmLexer – Klassen-Initialisierung }

class constructor TDfmLexer.Create;
begin
  InitKeywords;
end;

class destructor TDfmLexer.Destroy;
begin
  FreeAndNil(FKeywords);
end;

class procedure TDfmLexer.InitKeywords;
const
  N = 6;
  Names: array[0..N-1] of string = (
    'object', 'inherited', 'inline', 'end', 'true', 'false'
  );
  Kinds: array[0..N-1] of TDfmTokenKind = (
    tkKwObject, tkKwInherited, tkKwInline, tkKwEnd, tkKwTrue, tkKwFalse
  );
var
  i: Integer;
begin
  FKeywords := TDictionary<string, TDfmTokenKind>.Create(N * 2);
  for i := 0 to N - 1 do
    FKeywords.Add(Names[i], Kinds[i]);
end;

{ TDfmLexer }

constructor TDfmLexer.Create(const ASource: string);
begin
  inherited Create;
  FSource  := ASource;
  FLen     := Length(ASource);
  FPos     := 1;
  FLine    := 1;
  FCol     := 1;
  FPeeked  := False;
end;

function TDfmLexer.CurChar: Char;
begin
  if FPos <= FLen then Result := FSource[FPos]
                  else Result := #0;
end;

function TDfmLexer.PeekChar(Offset: Integer): Char;
var
  p: Integer;
begin
  p := FPos + Offset;
  if p <= FLen then Result := FSource[p]
               else Result := #0;
end;

procedure TDfmLexer.Advance(Count: Integer);
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

procedure TDfmLexer.SkipWhitespace;
begin
  while (FPos <= FLen) and (FSource[FPos] <= ' ') do
    Advance;
end;

function TDfmLexer.MakeTok(AKind: TDfmTokenKind; const AVal: string;
  ALine, ACol: Integer): TDfmToken;
begin
  Result.Kind  := AKind;
  Result.Value := AVal;
  Result.Line  := ALine;
  Result.Col   := ACol;
end;

function TDfmLexer.ReadIdent: TDfmToken;
// DFM-Identifier: [A-Za-z_][A-Za-z0-9_]*
// Keywords werden case-insensitiv erkannt.
var
  L, C  : Integer;
  Start : Integer;
  Raw   : string;
  Kind  : TDfmTokenKind;
begin
  L     := FLine;
  C     := FCol;
  Start := FPos;
  while (FPos <= FLen) and CharInSet(CurChar, ['A'..'Z','a'..'z','0'..'9','_']) do
    Advance;
  Raw := Copy(FSource, Start, FPos - Start);
  if not FKeywords.TryGetValue(Raw.ToLower, Kind) then
    Kind := tkIdent;
  Result := MakeTok(Kind, Raw, L, C);
end;

function TDfmLexer.ReadNumber: TDfmToken;
// Ganzzahl- oder Float-Literal. Vorzeichen wird NICHT mit konsumiert -
// das macht ScanNext via separatem tkMinus-Token.
// DFM kennt zusätzlich Hex via '$' (gleiche Schreibweise wie Pascal).
var
  L, C  : Integer;
  Start : Integer;
  Kind  : TDfmTokenKind;
begin
  L     := FLine;
  C     := FCol;
  Start := FPos;
  Kind  := tkInteger;

  if CurChar = '$' then
  begin
    Advance;
    while CharInSet(CurChar, ['0'..'9','A'..'F','a'..'f']) do
      Advance;
  end
  else
  begin
    while CharInSet(CurChar, ['0'..'9']) do Advance;
    if (CurChar = '.') and CharInSet(PeekChar, ['0'..'9']) then
    begin
      Kind := tkFloat;
      Advance;
      while CharInSet(CurChar, ['0'..'9']) do Advance;
    end;
    if CharInSet(CurChar, ['e','E']) then
    begin
      Kind := tkFloat;
      Advance;
      if CharInSet(CurChar, ['+','-']) then Advance;
      while CharInSet(CurChar, ['0'..'9']) do Advance;
    end;
  end;
  Result := MakeTok(Kind, Copy(FSource, Start, FPos - Start), L, C);
end;

function TDfmLexer.ReadString: TDfmToken;
// DFM-String: 'foo' mit ''-Escape, optional via '+' und/oder Whitespace mit
// weiteren Segmenten zusammengefügt:
//
//   Caption = 'erste Zeile' +
//     'zweite Zeile' +
//     #13#10 +
//     'mit Newline'
//
// Lexer-internes Merging: solange nach dem aktuellen String-Segment nur
// Whitespace (inkl. Newline) und optional ein '+' folgt, gefolgt von einem
// neuen String-Segment oder #nn, weiter sammeln. Damit kommt aus dem Lexer
// genau EIN tkString-Token pro Property-Wert raus, auch wenn der String im
// DFM auf mehrere Zeilen verteilt ist.
//
// CurChar zeigt beim Aufruf auf das öffnende ' oder #.
var
  L, C       : Integer;
  Buf        : string;
  SavedPos   : Integer;
  SavedLine  : Integer;
  SavedCol   : Integer;
  Num        : string;
  CodePoint  : Integer;
begin
  L := FLine; C := FCol;
  Buf := '';
  while FPos <= FLen do
  begin
    if CurChar = '''' then
    begin
      Advance; // öffnendes ' überspringen
      while FPos <= FLen do
      begin
        if CurChar = '''' then
        begin
          Advance;
          if (FPos <= FLen) and (CurChar = '''') then
          begin
            // '' = ein einfaches Anführungszeichen im String
            Buf := Buf + '''';
            Advance;
          end
          else
            Break; // schließendes ' - Segment-Ende
        end
        else
        begin
          Buf := Buf + CurChar;
          Advance;
        end;
      end;
    end
    else if CurChar = '#' then
    begin
      // #nn oder #$xx (Zeichencode). BMP-Bereich (0..65535); höhere
      // Codepoints werden durch U+FFFD ersetzt (analog Pascal-Lexer).
      Advance;
      Num := '';
      if CurChar = '$' then
      begin
        Advance;
        while (FPos <= FLen) and CharInSet(CurChar, ['0'..'9','A'..'F','a'..'f']) do
        begin
          Num := Num + CurChar;
          Advance;
        end;
        CodePoint := StrToIntDef('$' + Num, 0);
      end
      else
      begin
        while (FPos <= FLen) and CharInSet(CurChar, ['0'..'9']) do
        begin
          Num := Num + CurChar;
          Advance;
        end;
        CodePoint := StrToIntDef(Num, 0);
      end;
      if (CodePoint < 0) or (CodePoint > $FFFF) then
        Buf := Buf + #$FFFD
      else
        Buf := Buf + Chr(CodePoint);
    end
    else
      Break;

    // Schauen, ob nach Whitespace ein weiteres Segment folgt - dann
    // konkatenieren. Wenn nicht, Position zurückrollen und String-Token
    // beenden.
    SavedPos  := FPos;
    SavedLine := FLine;
    SavedCol  := FCol;
    SkipWhitespace;
    if (CurChar = '+') then
    begin
      Advance;
      SkipWhitespace;
    end;
    if (CurChar = '''') or (CurChar = '#') then
      Continue          // weiter sammeln
    else
    begin
      FPos  := SavedPos;
      FLine := SavedLine;
      FCol  := SavedCol;
      Break;
    end;
  end;
  Result := MakeTok(tkString, Buf, L, C);
end;

function TDfmLexer.ReadSet: TDfmToken;
// '[' ... ']'  - Strings können enthalten sein und müssen überlesen werden,
// damit ein ''']''' im String den Klammer-Counter nicht bricht.
// Sets verschachteln nicht.
var
  L, C  : Integer;
  Start : Integer;
begin
  L := FLine; C := FCol;
  Start := FPos;
  Advance; // '['
  while (FPos <= FLen) and (CurChar <> ']') do
  begin
    if CurChar = '''' then
      ReadString          // verschluckt das String-Segment robust
    else
      Advance;
  end;
  if (FPos <= FLen) and (CurChar = ']') then Advance;
  Result := MakeTok(tkSet, Copy(FSource, Start, FPos - Start), L, C);
end;

function TDfmLexer.ReadBinary: TDfmToken;
// '{' ... '}'  - Hex-Bytes (Whitespace getrennt). Inhalt für Phase 1 nicht
// relevant; Lexer skippt komplett und liefert ein leeres Value-Feld (Position
// reicht). Verschachtelt nicht.
var
  L, C: Integer;
begin
  L := FLine; C := FCol;
  Advance; // '{'
  while (FPos <= FLen) and (CurChar <> '}') do
    Advance;
  if (FPos <= FLen) and (CurChar = '}') then Advance;
  Result := MakeTok(tkBinary, '', L, C);
end;

function TDfmLexer.ReadItemList: TDfmToken;
// '<' ... '>'  - Collection-Items: <item Prop=Value ... end item ... end>.
// KANN verschachteln (Item-Property ist selbst eine Collection), deshalb
// Klammer-Counter. Strings drinnen müssen wieder überlesen werden, weil
// '''>''' sonst den Counter zerschießt.
var
  L, C  : Integer;
  Start : Integer;
  Depth : Integer;
begin
  L := FLine; C := FCol;
  Start := FPos;
  Depth := 0;
  while FPos <= FLen do
  begin
    case CurChar of
      '<': begin Inc(Depth); Advance; end;
      '>': begin
             Dec(Depth);
             Advance;
             if Depth = 0 then Break;
           end;
      '''': ReadString;
    else
      Advance;
    end;
  end;
  Result := MakeTok(tkItemList, Copy(FSource, Start, FPos - Start), L, C);
end;

function TDfmLexer.ReadStrList: TDfmToken;
// '(' ... ')' - in DFM fast ausschließlich Multi-Line-String-Listen
//   Lines.Strings = (
//     'erste Zeile'
//     'zweite Zeile')
// Strings müssen überlesen werden, sonst kippt ein ''')''' den Counter.
// Verschachtelt theoretisch nicht (DFM-Format kennt keine nested Tuples),
// pragmatisch trotzdem Depth-Counter falls jemals nötig.
var
  L, C  : Integer;
  Start : Integer;
  Depth : Integer;
begin
  L := FLine; C := FCol;
  Start := FPos;
  Depth := 0;
  while FPos <= FLen do
  begin
    case CurChar of
      '(': begin Inc(Depth); Advance; end;
      ')': begin
             Dec(Depth);
             Advance;
             if Depth = 0 then Break;
           end;
      '''': ReadString;
    else
      Advance;
    end;
  end;
  Result := MakeTok(tkStrList, Copy(FSource, Start, FPos - Start), L, C);
end;

function TDfmLexer.ScanNext: TDfmToken;
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
      // Bezeichner und Schlüsselwörter
      'A'..'Z', 'a'..'z', '_':
        Exit(ReadIdent);

      // Zahlen (ohne Vorzeichen)
      '0'..'9', '$':
        Exit(ReadNumber);

      // String-Literale
      '''', '#':
        Exit(ReadString);

      // Klammer-Blöcke - atomar
      '[': Exit(ReadSet);
      '{': Exit(ReadBinary);
      '<': Exit(ReadItemList);
      '(': Exit(ReadStrList);

      // Trennzeichen
      ':': begin Advance; Exit(MakeTok(tkColon,  ':', L, C)); end;
      '=': begin Advance; Exit(MakeTok(tkEquals, '=', L, C)); end;
      '.': begin Advance; Exit(MakeTok(tkDot,    '.', L, C)); end;
      ',': begin Advance; Exit(MakeTok(tkComma,  ',', L, C)); end;
      '-': begin Advance; Exit(MakeTok(tkMinus,  '-', L, C)); end;
    else
      // Unbekanntes Zeichen - Snapshot vor Advance, damit der Token-Wert
      // das tatsächliche Zeichen trägt (analog uLexer).
      var UnknownCh := CurChar;
      Advance;
      Exit(MakeTok(tkUnknown, UnknownCh, L, C));
    end;
  end;
end;

function TDfmLexer.Next: TDfmToken;
begin
  if FPeeked then
  begin
    Result  := FPeekTok;
    FPeeked := False;
  end
  else
    Result := ScanNext;
end;

function TDfmLexer.Peek: TDfmToken;
begin
  if not FPeeked then
  begin
    FPeekTok := ScanNext;
    FPeeked  := True;
  end;
  Result := FPeekTok;
end;

function TDfmLexer.Consume(AKind: TDfmTokenKind): TDfmToken;
begin
  Result := Next;
  if Result.Kind <> AKind then
    raise Exception.CreateFmt(
      'Zeile %d: DFM-Token "%s" erwartet, aber "%s" gefunden.',
      [Result.Line, GetEnumName(TypeInfo(TDfmTokenKind), Ord(AKind)), Result.Value]);
end;

function TDfmLexer.TryConsume(AKind: TDfmTokenKind; out Tok: TDfmToken): Boolean;
begin
  Result := Peek.Kind = AKind;
  if Result then
    Tok := Next;
end;

function TDfmLexer.AtEnd: Boolean;
begin
  Result := Peek.Kind = tkEof;
end;

end.

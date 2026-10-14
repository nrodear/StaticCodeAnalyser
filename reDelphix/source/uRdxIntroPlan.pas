unit uRdxIntroPlan;

// reDelphix - Code-Aktion "Lokale Konstante einfuehren" (Refactoring ohne
// Fund; bis E26 "Lokale Variable einfuehren"): die reine Textlogik, OHNE
// ToolsAPI (laeuft auch unter FPC, Pruefstand tools\fpc-pruefstand): das
// Zahl-Literal unter dem Caret finden, alle gleichen Literale derselben
// Zeile, die Deklarationszeile 'const <Name> = <Literal>;' und die
// Spalten nach dem Schreiben. Den Namen fragt die Aktion nicht vorher ab
// (Nico 2026-10-11, E17: wie ReSharper - der Code entsteht mit einem
// vorlaeufigen Namen, der Name wird umrandet, der Caret steht darauf,
// Tippen aendert alle Stellen mit). Diese Unit liefert nur WAS geschrieben
// wird und WO der Name danach steht.
//
// Die Deklaration ist eine Inline-KONSTANTE, keine Variable (Nico
// 2026-10-13, E26): eine Konstante behaelt Faltung, Ueberladungswahl und
// die vorzeichenlose Rechnung des Literals. Die Kompilierprobe
// probe\VnpTypeProbe.dpr (Win32, D12) zeigte fuer 'var X := 1': 'C - X'
// mit C: Cardinal ergab -1 statt 4294967295 (P2.33/34), und Integer-
// statt ShortInt-/Byte-Ueberladungen wurden gewaehlt (P4.9-16). Eine
// Inline-Konstante gibt es in FPC 3.2 nicht - Dateien mit FPC-Weiche
// lehnt uRdxIntroEdits.TargetAt ab (LineLooksFpcAware).
//
// 1:1 aus dem Labor VarNameProject (uVnpPlan, Stand 2026-10-14 nach dem
// Review F/B vom 2026-10-13, Entscheid E24: erst der im Labor gemessene
// Stand, die Zusammenlegung mit uRdxCodeMap/uRdxBufferMath folgt
// spaeter), nur Variante C1h - der
// Code des Live Templates fuer D1 (TemplateCode, LoneLfCount) bleibt im
// Labor. Der IDE-Teil folgt, wenn das Labor Enter und Esc geklaert hat
// (E25: Esc zerstoert im Sync Edit der IDE Text, UI-Test 2026-10-11).
//
// Spalten sind 1-basierte Zeichenspalten der Zeile (UTF-16), Bytes
// rechnen erst uRdxIntroEdits und der IDE-Teil (Utf8Len).

interface

uses
  System.SysUtils;

type
  TRdxIntroPlan = record
    Ok         : Boolean;
    Reason     : string;           // warum nicht (Ok = False)
    Literal    : string;           // '42', '$FF', '3.5'
    Indent     : string;           // Einrueckung der Zeile
    DeclText   : string;           // Indent + 'const Name = Literal;'
    NameCol    : Integer;          // Spalte des Namens in DeclText
    OldCols    : TArray<Integer>;  // Spalten der Literale vor dem Schreiben
    NewCols    : TArray<Integer>;  // dieselben Stellen nach dem Ersetzen
    NewUseLine : string;           // die Zeile nach dem Ersetzen
    // Die Zeile ist die einzige Anweisung eines Zweigs (die Zeile darueber
    // endet mit then/do/else): sie kommt mit der Deklaration in einen
    // neuen begin..end-Block (Nico 2026-10-11, Fall 3). 'begin' steht
    // direkt unter der Zweigzeile, 'end;' unter der Anweisung, beide mit
    // der Einrueckung der Zweigzeile.
    Wrap        : Boolean;
    BlockIndent : string;
  end;

// Plan fuer die Zeile ALine mit dem Caret in Spalte ACaretCol (vor dem
// Zeichen ACaretCol; direkt hinter dem Literal zaehlt auch). APrevCode ist
// die naechste Zeile mit Code darueber: die Deklaration kommt VOR die
// Zeile, also muss dort eine Anweisung zu Ende sein - oder ein Zweig
// (then/do/else), dann mit begin..end (Wrap). APrevState ist der
// Kommentar-Zustand am Anfang von APrevCode ('c' Code, 'b' in { }, 'p' in
// (* *)): beginnt die Zeile darueber in einem Kommentar, zaehlt nur ihr
// Code hinter dessen Ende ('Foo; // } if A then' hinter '{ Bsp:' ist ein
// Zweig, kein ';'); TargetAt liefert den Zustand aus StartStates.
function PlanIntroduce(const ALine, APrevCode: string; ACaretCol: Integer;
  const AName: string; APrevState: Char = 'c'): TRdxIntroPlan;

// Der Code-Anteil der Zeile: Strings bleiben, Kommentare fallen weg (von
// einer Kommentarzeile bleibt nur ihre Einrueckung). Kommentare ueber
// Zeilen sieht die Zeile nicht.
function CodePart(const ALine: string): string;

// Dasselbe fuer eine Zeile, die im Kommentar-Zustand AState beginnt ('c'
// Code, 'b' in { }, 'p' in (* *)) - fuer Kommentare ueber mehrere Zeilen.
function CodePartFrom(const ALine: string; AState: Char): string;

// Der Kommentar-Zustand am Ende von ALine, die in AState beginnt: 'b' oder
// 'p', wenn ein { }- bzw. (* *)-Kommentar offen bleibt, sonst 'c'.
function CommentStateAfter(const ALine: string; AState: Char): Char;

// Das letzte Wort im Code-Anteil von ALine ('' wenn er nicht auf ein Wort
// endet) - so wie es dasteht, Gross/Klein wie in der Zeile.
function LastWord(const ALine: string): string;

// Der Abschnitts-Zustand nach dem Code ACode (ohne Kommentare), der im
// Zustand AState beginnt: 'a' in einem asm-Block ('asm' .. 'end' - dort
// ist ';' nur ein Trenner und 'mov eax, 1' keine Anweisung), 'i' im
// initialization-/finalization-Abschnitt (bis zum Dateiende), sonst 'c'.
// TargetAt faltet damit die Zeilen ueber dem Caret.
function SectionStateAfter(const ACode: string; AState: Char): Char;

// Beginnt im Code ACode ein 'if' einen AUSDRUCK statt einer Anweisung
// (Delphi 13: 'X := if C then A', 'Foo(if C then 1 else 2)') - ein 'if',
// das nicht am Anfang steht und nicht hinter then/else/do/of, ';', ':'
// oder einem Block-Oeffner? Ein begin..end um einen Arm eines solchen
// Ausdrucks waere kein Code (Pruefer 2026-10-13, Harness 8).
function ContinuesIfExpression(const ACode: string): Boolean;

// Gehoert ein 'then' oder 'else' am Zeilenende zu einem Bedingungsausdruck
// (Delphi 13), dessen 'if' weiter oben steht? ACodeAbove: der Code der
// Zeilen von dort aufwaerts (nur Code-Zeilen, von unten nach oben; bei
// einem 'else' die Zeilen UEBER der else-Zeile, bei einem 'then' die
// then-Zeile selbst zuerst). Aufwaerts bis zum 'if': mitten in einer Zeile
// (ContinuesIfExpression) ein Ausdruck; als erstes Wort einer Zeile ein
// Ausdruck, wenn die Zeile darueber keine Anweisung beendet und keinen
// Zweig oder Block oeffnet ('X :=' / 'if C then' / 'A' / 'else'); eine
// Zeile, die vorher eine Anweisung beendet (';' am Ende) oder einen Zweig
// oder Block oeffnet, heisst: das then/else gehoert zu einer if-ANWEISUNG.
// Ohne 'if' darueber ebenso. Vorher zaehlte nur EINE Zeile ueber dem
// else, und 'X := if C then' / 'A' / 'else' / 'Foo(42);' bekam begin..end
// mitten im Ausdruck (Pruefer 2026-10-14, a).
function IfExpressionAbove(const ACodeAbove: array of string): Boolean;

// Traegt die Zeile eine FPC-Weiche oder einen FPC-Modus ('{$IFDEF FPC}',
// '{$IFNDEF FPC}', '{$IF DEFINED(FPC)}', '{$IF FPC_FULLVERSION ...}',
// '{$MODE ...}', auch als '(*$..*)')? Dieselben Spuren wie reDelphix (TRdxRecipes.
// LineLooksFpcAware): eine Inline-Konstante gibt es in FPC 3.2 nicht, in
// so einer Datei lehnt TargetAt ab. Ein Treffer in einem Kommentar macht
// nur vorsichtig, nie falsch.
function LineLooksFpcAware(const ALine: string): Boolean;

// ABase + '01', '02', ... - der erste Name, der in AText nicht als ganzes
// Wort vorkommt (Gross/Klein egal); hinter '99' geht es dreistellig
// weiter ('100'), ein fester Rueckfall ohne Pruefung gegen den Text
// koennte kollidieren (Pruefer 2026-10-13, Minor 4).
function NextFreeName(const AText, ABase: string): string;

// Zahl der UTF-8-Bytes von S.
function Utf8Len(const S: string): Integer;

// Zeichenspalte (1-basiert) zum 0-basierten UTF-8-Byteindex der Zeile.
function CharColOfByte(const ALine: string; AByteIndex: Integer): Integer;

// Ist am Ende von ALine ein String noch offen? So beginnt ein mehrzeiliger
// String (Delphi 12: ''' am Zeilenende). AState ist der Kommentar-Zustand
// am Zeilenanfang ('c', 'b', 'p') - eine Zeile, die in einem Kommentar
// beginnt, zaehlt erst ab dessen Ende (ein ''' im Kommentar oeffnet
// nichts; Pruefer 2026-10-14, c).
function StringOpenAtEnd(const ALine: string; AState: Char = 'c'): Boolean;

implementation

type
  // Ein Zahl-Literal der Zeile: Spalten [First, Stop).
  TRdxIntroRange = record
    First : Integer;
    Stop  : Integer;
  end;

  // Ein Wort (klein geschrieben) oder Satzzeichen des Codes und seine
  // Spalte.
  TRdxIntroToken = record
    Text : string;
    Pos  : Integer;
  end;

const
  // Hinter diesen Woertern beginnt eine Anweisung (letztes Wort der Zeile
  // darueber).
  STATEMENT_OPENERS: array[0..4] of string = ('begin', 'try', 'finally',
    'except', 'repeat');
  // Mit diesen Woertern beginnt keine eigene Anweisung - davor darf keine
  // Deklaration.
  NOT_A_START: array[0..8] of string = ('end', 'else', 'until', 'except',
    'finally', 'then', 'do', 'of', 'begin');
  // Hinter diesen Woertern steht genau EINE Anweisung (Zweig ohne begin).
  BRANCH_ENDS: array[0..2] of string = ('then', 'do', 'else');
  // Mit diesen Woertern beginnt eine Deklaration oder eine Zeile, deren
  // Zahlen Konstanten bleiben muessen: Routinen-Koepfe (Vorgabewerte,
  // dispid, message, external index), Eigenschaften (default), Typen,
  // Sprungmarken, asm (Korpus-A/B 2026-10-11).
  DECL_STARTS: array[0..14] of string = ('procedure', 'function',
    'constructor', 'destructor', 'operator', 'property', 'class', 'type',
    'label', 'goto', 'exports', 'resourcestring', 'threadvar', 'uses',
    'asm');
  // Mit diesen Woertern geht ein Routinen-Kopf oder eine Eigenschaft auf
  // einer FOLGEZEILE weiter ('message WM_USER + 5;', 'dispid 5;',
  // 'external ''x.dll'' index 5;', 'stdcall; external ...') - die Zeile
  // darueber endet mit ';', der Zeilen-Leser hielte sie sonst fuer eine
  // Anweisung (Pruefer 2026-10-13, Harness 1-3). Sie sind keine
  // reservierten Woerter: als Anweisung ('Index := 5', 'Name.X(42)',
  // 'Message(42)', 'Index[1] := 42', 'Register<Integer>(42)', 'Register;
  // X := 42') folgt ':=', '.', '(', '[', '^', '<' oder ein ';' mit einer
  // Anweisung dahinter (StartsHeadDirective). 'vectorcall' und
  // 'assembler' dazu (Pruefer 2026-10-14, d).
  HEAD_DIRECTIVES: array[0..28] of string = ('message', 'dispid',
    'external', 'index', 'name', 'stdcall', 'cdecl', 'safecall', 'pascal',
    'register', 'winapi', 'overload', 'override', 'virtual', 'dynamic',
    'abstract', 'reintroduce', 'inline', 'static', 'forward', 'deprecated',
    'platform', 'experimental', 'library', 'varargs', 'delayed', 'final',
    'vectorcall', 'assembler');
  // Dahinter ist ein 'message', 'index' usw. eine Anweisung, keine
  // Fortsetzung eines Kopfs.
  STATEMENT_AFTER_WORD: array[0..5] of string = (':=', '.', '(', '[', '^',
    '<');
  // Hinter diesen Woertern beginnt ein 'if' eine ANWEISUNG; jedes andere
  // Token davor ('X := if ...', 'Foo(if ...', '1 + if ...') macht es zum
  // Bedingungsausdruck (Delphi 13).
  IF_STATEMENT_AFTER: array[0..10] of string = ('then', 'else', 'do', 'of',
    ';', ':', 'begin', 'try', 'finally', 'except', 'repeat');
  // Hinter diesen Woertern als letztem Wort der Zeile darueber beginnt ein
  // Unit-Abschnitt, in dem eine Inline-Deklaration nicht gemessen ist.
  SECTION_STARTS: array[0..1] of string = ('initialization',
    'finalization');
  // Spuren einer FPC-Weiche, ohne Leerraum und klein geschrieben (wie
  // TRdxRecipes.FPC_TELLS in reDelphix).
  FPC_TELLS: array[0..5] of string = ('{$mode', '(*$mode', '$ifdeffpc',
    '$ifndeffpc', 'defined(fpc', 'fpc_fullversion');
  // Bloecke einer Zeile: diese Woerter oeffnen ...
  BLOCK_OPENERS: array[0..4] of string = ('begin', 'try', 'case', 'repeat',
    'asm');
  // ... und diese schliessen sie.
  BLOCK_CLOSERS: array[0..1] of string = ('end', 'until');

function InList(const AWord: string; const AList: array of string): Boolean;
var
  S : string;
begin
  Result := False;
  for S in AList do
    if SameText(AWord, S) then
      Exit(True);
end;

// Bezeichner-Zeichen: ASCII-Buchstaben, Ziffern, '_' und jedes
// Nicht-ASCII-Zeichen - Delphi erlaubt Unicode-Buchstaben in Bezeichnern,
// und im Code (ausserhalb von Strings und Kommentaren) steht Nicht-ASCII
// nur dort. Pruefstand 2026-10-11: sonst galt die 2 in 'Ma'#$00DF'2' als
// Literal, und die Hilfe zerstoerte den Bezeichner.
function IsIdentChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_'])
    or (Ord(C) > $7F);
end;

function IsDigit(C: Char): Boolean;
begin
  Result := CharInSet(C, ['0'..'9']);
end;

function IsHexDigit(C: Char): Boolean;
begin
  Result := CharInSet(C, ['0'..'9', 'A'..'F', 'a'..'f']);
end;

// Das Zeichen an Stelle i, #0 ausserhalb der Zeile.
function CharAt(const S: string; i: Integer): Char;
begin
  Result := #0;
  if (i >= 1) and (i <= Length(S)) then
    Result := S[i];
end;

// Zustand nach Zeichen i, wenn bisher Code war: Beginn eines Strings oder
// Kommentars?
function FromCode(const ALine: string; i: Integer): Char;
var
  Two : string;
begin
  Two := Copy(ALine, i, 2);
  if ALine[i] = '''' then
    Result := 's'
  else if ALine[i] = '{' then
    Result := 'b'
  else if Two = '(*' then
    Result := 'o'
  else if Two = '//' then
    Result := 'l'
  else
    Result := 'c';
end;

// Naechster Zustand des Zeilen-Lesers an Zeichen i: 'c' Code, 's' String,
// 'e' Quote im String (Ende oder ''), 'b' {}, 'o' und 'q' die Zeichen '('
// und '*' eines (*-Kommentars, 'p' sein Inneres, 'l' //, 'x' Ende eines
// Kommentars. Das '*' des Oeffners schliesst nie: '(*)' oeffnet nur
// (Pruefstand 2026-10-11 - bisher schloss es sofort wieder). Ein '*)'
// schliesst erst am ')' - und nur mit einem '*' DAVOR: 'Copy(ALine, 0, 2)'
// liest ab Zeichen 1, ein '*)' in Spalte 1 schloss so schon am '*', und
// das ')' galt als Code (Pruefer 2026-10-13, Minor 2).
function StepState(const ALine: string; i: Integer; AState: Char): Char;
begin
  Result := AState;
  case AState of
    'c':
      Result := FromCode(ALine, i);
    's':
      if ALine[i] = '''' then
        Result := 'e';
    'b':
      if ALine[i] = '}' then
        Result := 'x';
    'o':
      Result := 'q';
    'q':
      Result := 'p';
    'p':
      if (i > 1) and (ALine[i] = ')') and (ALine[i - 1] = '*') then
        Result := 'x';
  else
    ;   // 'l' bleibt bis zum Zeilenende
  end;
end;

// Klasse eines Zustands: 'c' Code, 's' String, 'k' Kommentar.
function ClassOfState(AState: Char): Char;
begin
  case AState of
    'c':
      Result := 'c';
    's', 'e':
      Result := 's';
  else
    Result := 'k';
  end;
end;

// Der Zeilen-Leser: die Klassen der Zeichen ('c' Code, 's' String samt
// Quotes, 'k' Kommentar) und der Zustand am Zeilenende ('s' = ein String
// ist noch offen, 'b'/'p'/'q' = ein Kommentar). Kennt '...' (mit ''),
// {...}, (*...*) und //. AStart ist der Zustand am Zeilenanfang - 'c' oder
// ein Kommentar, der in einer frueheren Zeile begann ('b', 'p').
procedure ScanLine(const ALine: string; AStart: Char; out AClasses: string;
  out AEndState: Char);
var
  i     : Integer;
  State : Char;
begin
  AClasses := StringOfChar('c', Length(ALine));
  State := AStart;
  i := 1;
  while i <= Length(ALine) do
  begin
    State := StepState(ALine, i, State);
    AClasses[i] := ClassOfState(State);
    if (State = 'e') and (CharAt(ALine, i + 1) = '''') then
    begin
      // '' im String: weiter im String.
      Inc(i);
      AClasses[i] := 's';
      State := 's';
    end
    else if CharInSet(State, ['e', 'x']) then
      State := 'c';
    Inc(i);
  end;
  AEndState := State;
end;

// Klassen der Zeichen einer Zeile, die im Code beginnt (siehe ScanLine).
function ClassesOf(const ALine: string): string;
var
  EndState : Char;
begin
  ScanLine(ALine, 'c', Result, EndState);
end;

function StringOpenAtEnd(const ALine: string; AState: Char): Boolean;
var
  Classes  : string;
  EndState : Char;
begin
  ScanLine(ALine, AState, Classes, EndState);
  Result := EndState = 's';
end;

function CommentStateAfter(const ALine: string; AState: Char): Char;
var
  Classes  : string;
  EndState : Char;
begin
  ScanLine(ALine, AState, Classes, EndState);
  case EndState of
    'b':
      Result := 'b';
    'p', 'q':
      Result := 'p';
  else
    // '//' endet mit der Zeile; ein offener String ist ein mehrzeiliger
    // (eigene Pruefung in uRdxIntroEdits) oder ein Fehler.
    Result := 'c';
  end;
end;

// Ende (exklusiv) einer Folge von Dezimalziffern und '_' (Zifferntrenner,
// Delphi 11) ab AFrom.
function DecEnd(const ALine: string; AFrom: Integer): Integer;
begin
  Result := AFrom;
  while IsDigit(CharAt(ALine, Result)) or (CharAt(ALine, Result) = '_') do
    Inc(Result);
end;

// Dasselbe fuer Hex-Ziffern.
function HexEnd(const ALine: string; AFrom: Integer): Integer;
begin
  Result := AFrom;
  while IsHexDigit(CharAt(ALine, Result)) or (CharAt(ALine, Result) = '_') do
    Inc(Result);
end;

// Ein Exponent ab i ('e5', 'E-3')? Sein Ende, sonst i.
function ExponentEnd(const ALine: string; i: Integer): Integer;
var
  j : Integer;
begin
  Result := i;
  if not CharInSet(CharAt(ALine, i), ['e', 'E']) then
    Exit;
  j := i + 1;
  if CharInSet(CharAt(ALine, j), ['+', '-']) then
    Inc(j);
  if IsDigit(CharAt(ALine, j)) then
    Result := DecEnd(ALine, j);
end;

// Ende (exklusiv) eines Zahl-Literals ab AStart (dort beginnt eines, siehe
// NumberStartsAt): dezimal mit Bruch und Exponent oder hex mit '$'. Ein
// '.' nur mit Ziffer dahinter - '1..5' ist ein Bereich.
function NumberEnd(const ALine: string; AStart: Integer): Integer;
var
  i : Integer;
begin
  if ALine[AStart] = '$' then
    Exit(HexEnd(ALine, AStart + 1));
  i := DecEnd(ALine, AStart);
  if (CharAt(ALine, i) = '.') and IsDigit(CharAt(ALine, i + 1)) then
    i := DecEnd(ALine, i + 1);
  Result := ExponentEnd(ALine, i);
end;

// Beginnt an AStart (im Code) ein eigenstaendiges Zahl-Literal? Davor kein
// Bezeichner-Zeichen, kein '#' (Zeichencode), kein '$' und kein einzelner
// '.' (Bruchteil, Feld) - '..' davor ist ein Bereich, dessen obere Grenze
// ein eigenes Literal ist ('0..9', Pruefstand 2026-10-11).
function NumberStartsAt(const ALine, AClasses: string;
  AStart: Integer): Boolean;
var
  Before : Char;
begin
  Result := (AClasses[AStart] = 'c')
    and (IsDigit(ALine[AStart])
         or ((ALine[AStart] = '$') and (AStart < Length(ALine))
             and IsHexDigit(ALine[AStart + 1])));
  if not Result or (AStart = 1) then
    Exit;
  Before := ALine[AStart - 1];
  if (Before = '.') and (CharAt(ALine, AStart - 2) = '.') then
    Exit;
  Result := not (IsIdentChar(Before)
    or CharInSet(Before, ['#', '.', '$', '&', '%']));
end;

// Alle Zahl-Literale der Zeile.
function NumbersOf(const ALine: string): TArray<TRdxIntroRange>;
var
  Classes : string;
  i, e    : Integer;
  R       : TRdxIntroRange;
begin
  Result := nil;
  Classes := ClassesOf(ALine);
  i := 1;
  while i <= Length(ALine) do
  begin
    if NumberStartsAt(ALine, Classes, i) then
    begin
      e := NumberEnd(ALine, i);
      if (e > i) and ((e > Length(ALine)) or not IsIdentChar(ALine[e])) then
      begin
        R.First := i;
        R.Stop := e;
        Result := Result + [R];
        i := e;
        Continue;
      end;
    end;
    Inc(i);
  end;
end;

function FirstWord(const ALine: string): string;
var
  i, j : Integer;
begin
  i := 1;
  while (i <= Length(ALine)) and CharInSet(ALine[i], [' ', #9]) do
    Inc(i);
  j := i;
  while (j <= Length(ALine)) and IsIdentChar(ALine[j]) do
    Inc(j);
  Result := Copy(ALine, i, j - i);
end;

function CodePart(const ALine: string): string;
begin
  Result := CodePartFrom(ALine, 'c');
end;

function CodePartFrom(const ALine: string; AState: Char): string;
var
  Classes  : string;
  EndState : Char;
  i, n     : Integer;
begin
  ScanLine(ALine, AState, Classes, EndState);
  SetLength(Result, Length(ALine));
  n := 0;
  for i := 1 to Length(ALine) do
    if Classes[i] <> 'k' then
    begin
      Inc(n);
      Result[n] := ALine[i];
    end;
  SetLength(Result, n);
end;

// Der Code der Zeile ohne Strings und Kommentare - beide werden zu
// Leerzeichen, die Spalten bleiben.
function BareCode(const ALine: string): string;
var
  Classes : string;
  i       : Integer;
begin
  Classes := ClassesOf(ALine);
  Result := ALine;
  for i := 1 to Length(Result) do
    if Classes[i] <> 'c' then
      Result[i] := ' ';
end;

// Die Woerter (klein geschrieben) und Satzzeichen des Codes einer Zeile -
// Strings und Kommentare fallen weg, ':=' ist EIN Token, ein Wort mit '&'
// davor ('&begin') ist ein Bezeichner, kein Schluesselwort - ebenso eines
// mit '@' davor: die asm-Sprungmarke '@end:' ist kein 'end' und beendet
// den asm-Block nicht (Pruefer 2026-10-14, d; '@X' als Adresse bleibt
// ein Token, das kein Wort und kein Wert ist).
function TokensOf(const ALine: string): TArray<TRdxIntroToken>;
var
  S    : string;
  i, j : Integer;
  T    : TRdxIntroToken;
begin
  Result := nil;
  S := BareCode(ALine);
  i := 1;
  while i <= Length(S) do
  begin
    j := i + 1;
    if IsIdentChar(S[i]) or (S[i] = '&') or (S[i] = '@') then
      while (j <= Length(S)) and IsIdentChar(S[j]) do
        Inc(j)
    else if (S[i] = ':') and (CharAt(S, i + 1) = '=') then
      j := i + 2;
    if not CharInSet(S[i], [' ', #9]) then
    begin
      T.Text := LowerCase(Copy(S, i, j - i));
      T.Pos := i;
      Result := Result + [T];
    end;
    i := j;
  end;
end;

// Das erste Wort des Codes (klein geschrieben) - ein Kommentar oder eine
// Direktive davor zaehlt nicht ('{$IFDEF X}const ...', Korpus-A/B
// 2026-10-11).
function FirstCodeWord(const ALine: string): string;
begin
  Result := LowerCase(FirstWord(TrimLeft(BareCode(ALine))));
end;

// +1 fuer '(' und '[', -1 fuer ')' und ']', sonst 0.
function ParenStep(const AText: string): Integer;
begin
  Result := 0;
  if (AText = '(') or (AText = '[') then
    Result := 1
  else if (AText = ')') or (AText = ']') then
    Result := -1;
end;

// +1 fuer ein Wort, das einen Block oeffnet, -1 fuer eines, das ihn
// schliesst, sonst 0.
function BlockStep(const AText: string): Integer;
begin
  Result := 0;
  if InList(AText, BLOCK_OPENERS) then
    Result := 1
  else if InList(AText, BLOCK_CLOSERS) then
    Result := -1;
end;

// Kommt das Token AText vor?
function HasToken(const ATokens: TArray<TRdxIntroToken>;
  const AText: string): Boolean;
var
  T : TRdxIntroToken;
begin
  for T in ATokens do
    if T.Text = AText then
      Exit(True);
  Result := False;
end;

// Ist der ':' bei AIndex die Typangabe einer Deklaration - davor nur Namen
// und Kommata bis zu 'var' oder 'const' ('var X:', 'var A, B:', 'for var
// I:', auch die zweite Inline-var einer Zeile, Korpus-A/B 2026-10-11)?
function IsTypeColon(const ATokens: TArray<TRdxIntroToken>;
  AIndex: Integer): Boolean;
var
  i : Integer;
begin
  i := AIndex - 1;
  while (i >= 0) and (ATokens[i].Text <> 'var')
     and (ATokens[i].Text <> 'const')
     and (IsIdentChar(ATokens[i].Text[1]) or (ATokens[i].Text = ',')) do
    Dec(i);
  Result := (i >= 0) and (i < AIndex - 1)
    and ((ATokens[i].Text = 'var') or (ATokens[i].Text = 'const'));
end;

// Index des ':' der Typangabe hinter 'var' an Index AVar ('var X:', 'var A,
// B:') oder -1 - eine Inline-var ohne Typ ('var X := ...', 'for var S in
// ...') hat keinen.
function TypeColonAfter(const ATokens: TArray<TRdxIntroToken>;
  AVar: Integer): Integer;
var
  i : Integer;
begin
  i := AVar + 1;
  while (i <= High(ATokens))
     and (IsIdentChar(ATokens[i].Text[1]) or (ATokens[i].Text = ',')) do
    Inc(i);
  Result := -1;
  if (i > AVar + 1) and (i <= High(ATokens)) and (ATokens[i].Text = ':') then
    Result := i;
end;

// Spalte, an der der Typ hinter dem ':' bei AColon endet: das erste ':='
// oder 'in' ('for var I: T in ...'; in einer var-Zeile steht 'in' nie vor
// dem ':='); ohne beides das Zeilenende (MaxInt).
function TypeEndCol(const ATokens: TArray<TRdxIntroToken>;
  AColon: Integer): Integer;
var
  i : Integer;
begin
  for i := AColon + 1 to High(ATokens) do
    if (ATokens[i].Text = ':=') or (ATokens[i].Text = 'in') then
      Exit(ATokens[i].Pos);
  Result := MaxInt;
end;

function LastWord(const ALine: string): string;
var
  S : string;
  i : Integer;
begin
  S := Trim(CodePart(ALine));
  i := Length(S);
  while (i > 0) and IsIdentChar(S[i]) do
    Dec(i);
  Result := Copy(S, i + 1, MaxInt);
end;

// Endet der Code-Anteil von ALine mit ';'?
function EndsWithSemicolon(const ALine: string): Boolean;
var
  S : string;
begin
  S := Trim(CodePart(ALine));
  Result := (S <> '') and (S[Length(S)] = ';');
end;

// Endet die Zeile darueber eine Anweisung? ';' am Ende oder ein Wort aus
// STATEMENT_OPENERS (ein '//'-Kommentar dahinter wird abgeschnitten).
function PrevEndsStatement(const APrevCode: string): Boolean;
begin
  Result := EndsWithSemicolon(APrevCode)
    or InList(LastWord(APrevCode), STATEMENT_OPENERS);
end;

// Ist die Zeile ein case-Zweig, eine Sprungmarke oder ein on-Handler ('1: X
// := 5;', 'Fertig: ...', 'on E: Exception do ...')? Dann darf keine
// Deklaration davor - zwischen case-Zweigen bzw. on-Handlern ist sie
// ungueltig. Massgeblich ist JEDER ':' ausserhalb von Klammern, der nicht
// zu ':=' gehoert - auch hinter 'for ... do case I of 1:'; Feldbreiten
// ('Writeln(X:8:2)') stehen in Klammern, die Typangabe einer Deklaration
// ('var X:', 'const C:', 'for var I:', IsTypeColon) zaehlt nicht. Ein on-Handler ohne
// Variable ('on EConvertError do ...') hat keinen ':' - ihn erkennen 'on'
// und 'do' (Pruefstand und Korpus-A/B 2026-10-11).
function IsLabeled(const ATokens: TArray<TRdxIntroToken>): Boolean;
var
  i, Depth : Integer;
begin
  if (Length(ATokens) > 0) and (ATokens[0].Text = 'on')
     and HasToken(ATokens, 'do') then
    Exit(True);
  Depth := 0;
  for i := 0 to High(ATokens) do
  begin
    Inc(Depth, ParenStep(ATokens[i].Text));
    if (ATokens[i].Text = ':') and (Depth = 0)
       and not IsTypeColon(ATokens, i) then
      Exit(True);
  end;
  Result := False;
end;

// Steht das Literal schon ALLEIN als Wert einer Deklaration ('var X :=
// 42;', 'const X = 42;', auch mit Typangabe)? Dann hat es bereits einen
// Namen - Lauf 5 (2026-10-11) baute sonst 'var MagicNr05 := 42;' vor
// 'var MagicNr01 := MagicNr05;'; seit E26 schreibt die Aktion selbst
// 'const X = 42;', beide Formen zaehlen. 'var B := X = 42;' bleibt
// erlaubt (dort ist das Literal nur ein Teil des Werts).
function AlreadyNamed(const ALine, ALiteral: string): Boolean;
var
  S, W : string;
  P    : Integer;
begin
  Result := False;
  W := FirstCodeWord(ALine);
  if (W <> 'var') and (W <> 'const') then
    Exit;
  S := LowerCase(StringReplace(StringReplace(Trim(CodePart(ALine)), ' ', '',
    [rfReplaceAll]), #9, '', [rfReplaceAll]));
  if W = 'var' then
    P := Pos(':=', S) + 2
  else
    P := Pos('=', S) + 1;
  Result := (P > 2) and (Copy(S, P, MaxInt) = LowerCase(ALiteral) + ';');
end;

// Kommt AWord als ganzes Wort in AText vor (Gross/Klein egal)?
function ContainsWord(const AText, AWord: string): Boolean;
var
  P, After : Integer;
  U, W     : string;
begin
  U := UpperCase(AText);
  W := UpperCase(AWord);
  P := Pos(W, U);
  while P > 0 do
  begin
    After := P + Length(W);
    if ((P = 1) or not IsIdentChar(U[P - 1]))
       and ((After > Length(U)) or not IsIdentChar(U[After])) then
      Exit(True);
    P := Pos(W, U, P + 1);
  end;
  Result := False;
end;

// Ein Token auf oberster Ebene (ausserhalb von Bloecken und Klammern) der
// Zweig-Anweisung: False, wenn die Zeile damit mehr enthaelt als die eine
// Anweisung. AIfs zaehlt die offenen if DIESER Zeile.
function TopLevelOk(const AText: string; ALast: Boolean;
  var AIfs: Integer): Boolean;
begin
  Result := True;
  if AText = 'if' then
    Inc(AIfs)
  else if AText = 'else' then
  begin
    // Ohne eigenes if davor gehoert das else zum if darueber.
    Result := AIfs > 0;
    Dec(AIfs);
  end
  else if (AText = 'finally') or (AText = 'except') then
    // Gehoert zu einem try ausserhalb der Zeile.
    Result := False
  else if AText = ';' then
    // Ein ';' vor dem letzten beendet die Anweisung schon.
    Result := ALast;
end;

// Ist der Code der Zeile genau EINE vollstaendige Anweisung? Jeder Block
// (begin/try/case/repeat/asm .. end/until) schliesst auf der Zeile, ein
// ';' steht nur ganz am Ende (Bloecke und Klammern ausgenommen), und jedes
// else gehoert zu einem if dieser Zeile ('if C then A else B;' - ein else
// bindet ans naechste if). Sonst aenderte begin..end um die ganze Zeile,
// was im Zweig laeuft: 'Y := 42; Z := 1;' (Z liefe nur noch im Zweig),
// 'for ... do begin X := 42;' (der Rest der Schleife fiele heraus)
// (Pruefstand und Korpus-A/B 2026-10-11).
function SingleStatement(const ATokens: TArray<TRdxIntroToken>): Boolean;
var
  i, Block, Paren, Ifs : Integer;
begin
  Result := (Length(ATokens) > 0) and (ATokens[High(ATokens)].Text = ';');
  Block := 0;
  Paren := 0;
  Ifs := 0;
  i := 0;
  while Result and (i <= High(ATokens)) do
  begin
    Inc(Block, BlockStep(ATokens[i].Text));
    Inc(Paren, ParenStep(ATokens[i].Text));
    if (Block = 0) and (Paren = 0) then
      Result := TopLevelOk(ATokens[i].Text, i = High(ATokens), Ifs);
    Result := Result and (Block >= 0);
    Inc(i);
  end;
  Result := Result and (Block = 0);
end;

// Steht eines der Literale (Spalten ACols) hinter dem 'var' bei AVar
// zwischen Typ-':' und ':=' - im Typ ('var A: array[0..9] of Byte;', auch
// 'for var I: 0..9 := ...'), als Vorgabewert eines globalen 'var X:
// Integer = 5;' oder als dispid einer Parameter-Fortsetzung? Dort aendert
// die Aktion nichts (ob eine Inline-Konstante in einem Typ gilt, ist
// nicht gemessen). Eine Inline-var ohne Typ hat keinen solchen Teil.
function LiteralInTypePart(const ATokens: TArray<TRdxIntroToken>;
  const ACols: TArray<Integer>; AVar: Integer): Boolean;
var
  Colon, TypeEnd, Col : Integer;
begin
  Result := False;
  Colon := TypeColonAfter(ATokens, AVar);
  if Colon < 0 then
    Exit;
  TypeEnd := TypeEndCol(ATokens, Colon);
  for Col in ACols do
    if (Col > ATokens[Colon].Pos) and (Col < TypeEnd) then
      Exit(True);
end;

// Steht eines der Literale (Spalten ACols) hinter einem 'const' bei
// AConst ('Foo; const C = 5;')? Die Zeile deklariert dort eine Konstante -
// ihr Wert bleibt, wie er ist.
function LiteralAfterConst(const ATokens: TArray<TRdxIntroToken>;
  const ACols: TArray<Integer>; AConst: Integer): Boolean;
var
  Col : Integer;
begin
  Result := False;
  for Col in ACols do
    if Col > ATokens[AConst].Pos then
      Exit(True);
end;

// Deklarationen auf der Zeile, auch hinter einer Anweisung: JEDES 'var'
// und 'const' auf oberster Ebene (ausserhalb von Klammern) zaehlt, nicht
// nur das erste Wort - 'Foo; var A: array[0..9] of Byte;' und 'Foo; const
// C = 5;' bekamen sonst eine Deklaration (Pruefer 2026-10-13, Harness
// 21/22). Ein 'const' als erstes Wort lehnt LineReason schon ab. '' oder
// der Grund.
function InlineDeclReason(const ATokens: TArray<TRdxIntroToken>;
  const ACols: TArray<Integer>): string;
var
  k, Depth : Integer;
begin
  Result := '';
  Depth := 0;
  for k := 0 to High(ATokens) do
  begin
    Inc(Depth, ParenStep(ATokens[k].Text));
    if Depth <> 0 then
      Continue;
    if (ATokens[k].Text = 'var') and LiteralInTypePart(ATokens, ACols, k) then
      Exit('das Literal steht in der Deklaration vor ":=" (Typ, '
        + 'Vorgabewert oder dispid) - dort aendert die Aktion nichts');
    if (ATokens[k].Text = 'const') and LiteralAfterConst(ATokens, ACols, k) then
      Exit('die Zeile deklariert hinter der Anweisung eine Konstante '
        + '("const ...") - ihr Wert bleibt, wie er ist');
  end;
end;

// Index hinter der zu '<' bei AFrom passenden '>' (generischer Name).
function AfterAngles(const ATokens: TArray<TRdxIntroToken>;
  AFrom: Integer): Integer;
var
  Depth : Integer;
begin
  Result := AFrom;
  Depth := 0;
  repeat
    if ATokens[Result].Text = '<' then
      Inc(Depth)
    else if ATokens[Result].Text = '>' then
      Dec(Depth);
    Inc(Result);
  until (Depth = 0) or (Result > High(ATokens));
end;

// Beginnt der Code der Zeile mit 'Name =' oder 'Name<T> =' (nicht ':=')?
// So sehen nur Deklarationen aus - Konstanten und Typen in einem const-
// oder type-Abschnitt ('B = 42 * 2;', 'TArr<T> = array[0..9] of T;'); eine
// Anweisung beginnt nie so. Der Zeilen-Leser sieht den Abschnitt nicht,
// nur diese Form.
function IsDeclarationLine(const ATokens: TArray<TRdxIntroToken>): Boolean;
var
  k : Integer;
begin
  Result := False;
  if (Length(ATokens) < 2) or IsDigit(ATokens[0].Text[1])
     or not IsIdentChar(ATokens[0].Text[1]) then
    Exit;
  k := 1;
  if ATokens[k].Text = '<' then
    k := AfterAngles(ATokens, k);
  Result := (k <= High(ATokens)) and (ATokens[k].Text = '=');
end;

// Beginnt der Code mit einem Wert (Zahl, Zeichencode, Vorzeichen, String)?
// So beginnt keine Anweisung - die Zeile setzt einen Ausdruck fort, etwa
// den else-Wert eines Bedingungsausdrucks ueber mehrere Zeilen (Delphi
// 13).
function StartsWithValue(const ATokens: TArray<TRdxIntroToken>): Boolean;
begin
  Result := (Length(ATokens) > 0)
    and CharInSet(ATokens[0].Text[1], ['0'..'9', '$', '#', '+', '-', '%']);
end;

// Endet der Code mit ',' ausserhalb von Klammern? Dann geht eine Liste in
// der naechsten Zeile weiter, etwa case-Marken ('431..432,') - keine
// Anweisung (Korpus-A/B 2026-10-11).
function EndsWithListComma(const ATokens: TArray<TRdxIntroToken>): Boolean;
var
  T     : TRdxIntroToken;
  Depth : Integer;
begin
  Depth := 0;
  for T in ATokens do
    Inc(Depth, ParenStep(T.Text));
  Result := (Length(ATokens) > 0) and (ATokens[High(ATokens)].Text = ',')
    and (Depth = 0);
end;

// Beginnt der Code mit einer Kopf-Fortsetzung (HEAD_DIRECTIVES), hinter
// der keine Anweisung steht ('message WM_USER + 5;', 'stdcall; external
// ...')? 'Index := 5;', 'Message(42);' und 'Register<Integer>(42);' sind
// Anweisungen (STATEMENT_AFTER_WORD) - ebenso 'Register; X := 42;': ein
// ';' direkt hinter dem Wort, wenn danach etwas anderes als die naechste
// Kopf-Fortsetzung kommt ('stdcall; external ...' bleibt ein Kopf;
// Pruefer 2026-10-14, d).
function StartsHeadDirective(const ATokens: TArray<TRdxIntroToken>): Boolean;
begin
  Result := (Length(ATokens) > 0) and InList(ATokens[0].Text, HEAD_DIRECTIVES)
    and ((Length(ATokens) = 1)
         or not InList(ATokens[1].Text, STATEMENT_AFTER_WORD));
  if Result and (Length(ATokens) > 2) and (ATokens[1].Text = ';') then
    Result := InList(ATokens[2].Text, HEAD_DIRECTIVES);
end;

// Ist die Zeile eine typisierte Konstante oder eine initialisierte
// Variable 'Name: Typ = Wert;' (const-/var-Abschnitt)? Erstes Token ein
// Name (kein Wert), dann ':', spaeter '=' auf oberster Ebene - und kein
// ':=' und kein Anweisungswort (if, while, ...) auf oberster Ebene: 'lbl:
// if A = 1 then B;' ist eine Sprungmarke, 'C: Integer = 42;' die Konstante.
// Vorher nannte der Grund sie "case-Zweig" (Pruefer 2026-10-14, d).
function IsTypedConstDecl(const ATokens: TArray<TRdxIntroToken>): Boolean;
const
  STATEMENT_WORDS: array[0..13] of string = ('if', 'while', 'for', 'case',
    'repeat', 'begin', 'try', 'with', 'goto', 'raise', 'then', 'do', 'else',
    'on');
var
  i, Depth : Integer;
  HasEqual : Boolean;
begin
  Result := False;
  if (Length(ATokens) < 4) or IsDigit(ATokens[0].Text[1])
     or not IsIdentChar(ATokens[0].Text[1]) or (ATokens[1].Text <> ':') then
    Exit;
  Depth := 0;
  HasEqual := False;
  for i := 2 to High(ATokens) do
  begin
    Inc(Depth, ParenStep(ATokens[i].Text));
    if Depth <> 0 then
      Continue;
    if (ATokens[i].Text = ':=') or InList(ATokens[i].Text, STATEMENT_WORDS) then
      Exit;
    if ATokens[i].Text = '=' then
      HasEqual := True;
  end;
  Result := HasEqual;
end;

// Die Pruefungen, die nur die Zeile selbst brauchen: '' oder der Grund.
// Die Woerter am Zeilenanfang zaehlen hinter Kommentaren und Direktiven.
function LineReason(const ALine, ALiteral: string;
  const ATokens: TArray<TRdxIntroToken>): string;
var
  W : string;
begin
  W := FirstCodeWord(ALine);
  if AlreadyNamed(ALine, ALiteral) then
    Result := 'das Literal ist schon allein der Wert einer Deklaration - '
      + 'es hat bereits einen Namen'
  else if W = 'const' then
    Result := 'die Zeile deklariert eine Konstante - ihr Wert bleibt, wie '
      + 'er ist (Konstanten-Deklarationen aendert die Aktion nicht)'
  else if InList(W, DECL_STARTS) then
    Result := Format('die Zeile beginnt mit "%s" - eine Deklaration, '
      + 'Sprungmarke oder asm-Zeile; dort ist keine Deklaration erlaubt', [W])
  else if StartsHeadDirective(ATokens) then
    Result := Format('die Zeile beginnt mit "%s" - die Fortsetzung eines '
      + 'Routinen-Kopfs oder einer Eigenschaft (message, dispid, external '
      + '...); dort ist keine Deklaration erlaubt', [W])
  else if (Length(ATokens) > 0) and (ATokens[0].Text = '[') then
    Result := 'die Zeile ist ein Attribut ("[...]") - dort sind nur '
      + 'Konstanten erlaubt'
  else if IsDeclarationLine(ATokens) then
    Result := 'die Zeile ist eine Deklaration "Name = ..." (const- oder '
      + 'type-Abschnitt) - dort ist keine Inline-Deklaration erlaubt'
  else if InList(W, NOT_A_START) then
    Result := Format('die Zeile beginnt mit "%s" - davor darf keine '
      + 'Deklaration', [W])
  else if IsTypedConstDecl(ATokens) then
    Result := 'die Zeile ist eine typisierte Konstante oder initialisierte '
      + 'Variable "Name: Typ = Wert" (const-/var-Abschnitt) - ihr Wert '
      + 'bleibt, wie er ist'
  else if IsLabeled(ATokens) then
    Result := 'die Zeile ist ein case-Zweig, eine Sprungmarke oder ein '
      + 'on-Handler - davor darf keine Deklaration'
  else if StartsWithValue(ATokens) then
    Result := 'die Zeile beginnt mit einem Wert - sie setzt einen Ausdruck '
      + 'fort und ist keine Anweisung'
  else if EndsWithListComma(ATokens) then
    Result := 'die Zeile endet mit "," - eine Liste (z. B. case-Marken), '
      + 'die in der naechsten Zeile weitergeht'
  else
    Result := '';
end;

// Ein Zweig (die Zeile darueber endet mit then/do/else): darf ALine mit
// begin..end umschlossen werden? '' oder der Grund. Nur, wenn ALine auf
// dieser Zeile mit ';' endet und genau diese eine Anweisung enthaelt
// (SingleStatement; mehrzeilige Anweisungen kann der Text-Leser nicht
// abgrenzen) und das then/else nicht zu einem Bedingungsausdruck gehoert
// ('X := if C then A else' darueber).
function WrapReason(const ALine, APrevCode: string;
  const ATokens: TArray<TRdxIntroToken>): string;
begin
  if ContinuesIfExpression(APrevCode) then
    Exit('die Zeile darueber gehoert zu einem Bedingungsausdruck (Delphi '
      + '13: "X := if C then ...") - ein begin..end mitten im Ausdruck ist '
      + 'kein Code');
  if not EndsWithSemicolon(ALine) then
    Exit('die Anweisung im Zweig endet nicht auf dieser Zeile mit ";" '
      + '(mehrzeilig oder vor else) - nicht unterstuetzt');
  if not SingleStatement(ATokens) then
    Exit('auf der Zeile steht mehr als die eine Anweisung des Zweigs (ein '
      + 'zweites ";", ein else ohne eigenes if, ein offener Block) - '
      + 'begin..end um die Zeile aenderte, was im Zweig laeuft');
  Result := '';
end;

// Darf vor ALine eine Deklaration (APlan.Literal steht schon)? '' oder der
// Grund (LineReason fuer die Zeile selbst). Von der Zeile darueber zaehlt
// nur ihr Code ab dem Zustand APrevState. Setzt APlan.Wrap, wenn ALine
// die einzige Anweisung eines Zweigs ist (WrapReason).
function PlanReason(const ALine, APrevCode: string; APrevState: Char;
  var APlan: TRdxIntroPlan): string;
var
  T    : TArray<TRdxIntroToken>;
  Prev : string;
begin
  T := TokensOf(ALine);
  Result := LineReason(ALine, APlan.Literal, T);
  if Result <> '' then
    Exit;
  Prev := CodePartFrom(APrevCode, APrevState);
  if PrevEndsStatement(Prev) then
    Exit;
  if InList(LastWord(Prev), SECTION_STARTS) then
    Exit('die Zeile darueber beginnt den initialization-/finalization-'
      + 'Abschnitt - ob dort eine Inline-Deklaration gilt, ist nicht '
      + 'gemessen');
  APlan.Wrap := InList(LastWord(Prev), BRANCH_ENDS);
  if not APlan.Wrap then
    Exit('die Zeile darueber endet weder eine Anweisung noch mit then/do/'
      + 'else - unklar, wohin die Deklaration gehoert');
  Result := WrapReason(ALine, Prev, T);
end;

function PlanIntroduce(const ALine, APrevCode: string; ACaretCol: Integer;
  const AName: string; APrevState: Char): TRdxIntroPlan;
var
  Nums  : TArray<TRdxIntroRange>;
  N     : TRdxIntroRange;
  Shift : Integer;
begin
  Result := Default(TRdxIntroPlan);
  Nums := NumbersOf(ALine);
  for N in Nums do
    if (N.First <= ACaretCol) and (ACaretCol <= N.Stop) then
      Result.Literal := Copy(ALine, N.First, N.Stop - N.First);
  if Result.Literal = '' then
  begin
    Result.Reason := 'kein Zahl-Literal am Caret';
    Exit;
  end;
  Result.Reason := PlanReason(ALine, APrevCode, APrevState, Result);
  if Result.Reason <> '' then
  begin
    Result.Wrap := False;
    Exit;
  end;
  if Result.Wrap then
    Result.BlockIndent := Copy(APrevCode, 1,
      Length(APrevCode) - Length(TrimLeft(APrevCode)));
  Result.Indent := Copy(ALine, 1, Length(ALine) - Length(TrimLeft(ALine)));
  // E26: Inline-Konstante; der Name steht hinter 'const ' (6 Zeichen).
  Result.DeclText := Result.Indent + 'const ' + AName + ' = ' + Result.Literal
    + ';';
  Result.NameCol := Length(Result.Indent) + 7;
  // Alle gleichen Literale der Zeile, von links; jede Ersetzung schiebt die
  // folgenden um die Laengendifferenz.
  Result.NewUseLine := ALine;
  Shift := 0;
  for N in Nums do
    if Copy(ALine, N.First, N.Stop - N.First) = Result.Literal then
    begin
      Result.OldCols := Result.OldCols + [N.First];
      Result.NewCols := Result.NewCols + [N.First + Shift];
      Delete(Result.NewUseLine, N.First + Shift, Length(Result.Literal));
      Insert(AName, Result.NewUseLine, N.First + Shift);
      Inc(Shift, Length(AName) - Length(Result.Literal));
    end;
  Result.Reason := InlineDeclReason(TokensOf(ALine), Result.OldCols);
  if Result.Reason <> '' then
  begin
    Result.Wrap := False;
    Exit;
  end;
  Result.Ok := True;
end;

function SectionStateAfter(const ACode: string; AState: Char): Char;
var
  T : TRdxIntroToken;
begin
  Result := AState;
  for T in TokensOf(ACode) do
    case Result of
      'a':
        // Im asm-Block ist 'end' das einzige Pascal-Wort.
        if T.Text = 'end' then
          Result := 'c';
      'i':
        ;   // bis zum Dateiende
    else
      if T.Text = 'asm' then
        Result := 'a'
      else if InList(T.Text, SECTION_STARTS) then
        Result := 'i';
    end;
end;

function ContinuesIfExpression(const ACode: string): Boolean;
var
  T : TArray<TRdxIntroToken>;
  k : Integer;
begin
  T := TokensOf(ACode);
  for k := 1 to High(T) do
    if (T[k].Text = 'if') and not InList(T[k - 1].Text, IF_STATEMENT_AFTER) then
      Exit(True);
  Result := False;
end;

// Beendet der Code eine Anweisung (';' am Ende) oder oeffnet er einen
// Zweig oder Block (letztes Token aus IF_STATEMENT_AFTER)? Leer: ja - vor
// der ersten Zeile ist nichts offen.
function EndsStatementOrBranch(const ACode: string): Boolean;
var
  T : TArray<TRdxIntroToken>;
begin
  T := TokensOf(ACode);
  Result := (Length(T) = 0) or InList(T[High(T)].Text, IF_STATEMENT_AFTER);
end;

function IfExpressionAbove(const ACodeAbove: array of string): Boolean;
var
  k    : Integer;
  T    : TArray<TRdxIntroToken>;
  Next : string;
begin
  Result := False;
  for k := 0 to High(ACodeAbove) do
  begin
    if ContinuesIfExpression(ACodeAbove[k]) then
      Exit(True);
    T := TokensOf(ACodeAbove[k]);
    if (Length(T) > 0) and (T[0].Text = 'if') then
    begin
      // 'if' als erstes Wort: Ausdruck nur, wenn die Zeile darueber offen
      // endet ('X :=', 'Foo(', 'A +'); ohne Zeile darueber eine Anweisung.
      Next := '';
      if k < High(ACodeAbove) then
        Next := ACodeAbove[k + 1];
      Exit(not EndsStatementOrBranch(Next));
    end;
    if EndsStatementOrBranch(ACodeAbove[k]) then
      Exit;
  end;
end;

function LineLooksFpcAware(const ALine: string): Boolean;
var
  S    : string;
  Tell : string;
begin
  S := LowerCase(StringReplace(StringReplace(ALine, ' ', '', [rfReplaceAll]),
    #9, '', [rfReplaceAll]));
  for Tell in FPC_TELLS do
    if Pos(Tell, S) > 0 then
      Exit(True);
  Result := False;
end;

function NextFreeName(const AText, ABase: string): string;
var
  i : Integer;
begin
  i := 0;
  repeat
    Inc(i);
    Result := ABase + Format('%.2d', [i]);
  until not ContainsWord(AText, Result);
end;

function Utf8Len(const S: string): Integer;
begin
  Result := TEncoding.UTF8.GetByteCount(S);
end;

function CharColOfByte(const ALine: string; AByteIndex: Integer): Integer;
var
  Col : Integer;
begin
  Col := 1;
  while (Col <= Length(ALine))
     and (Utf8Len(Copy(ALine, 1, Col)) <= AByteIndex) do
    Inc(Col);
  Result := Col;
end;

end.

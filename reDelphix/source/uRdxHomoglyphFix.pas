unit uRdxHomoglyphFix;

// reDelphix - Editorhilfe fuer SCA193 SourceNonAsciiIdentifier, OHNE
// ToolsAPI und ohne Parser: ein Bezeichner, in dem ein Buchstabe nur wie
// ein lateinischer aussieht (Homoglyph: kyrillisches 'a' U+0430 statt 'a',
// griechisches 'My' U+039C statt 'M'), wird in ASCII geschrieben - an
// ALLEN Vorkommen im Code der Datei, in EINEM Undo-Schritt
// (TRdxHomoglyphPlan.Edits). Bedeutungsgleich, wenn der Name nur in dieser
// Unit gilt und der neue Name dort noch frei ist (Changes: False).
//
// DER FUND (uSourceEncoding, S3 - ScanNonAsciiTokens): EIN Fund je DATEI,
// auf der Zeile des ERSTEN Nicht-ASCII-Buchstabens im Code (der TLexer
// verwirft Kommentare, Strings zaehlen nicht), ohne Spalte und ohne Namen;
// nur in Dateien mit verlaesslicher Dekodierung (BOM bzw. striktes UTF-8).
// Die Hilfe nimmt auf der gemeldeten Zeile den ersten Bezeichner mit einem
// Nicht-ASCII-Zeichen; danach meldet der Detektor den naechsten.
//
// DIE TABELLE: nur feste, bekannte Paare (HOMOGLYPHS) - kyrillische und
// griechische Grossbuchstaben, die wie lateinische aussehen, und die
// kyrillischen Kleinbuchstaben a, e, o, p, c, y, x, s, i, j, h, d, q, w, l
// (Unicode confusables). Ein anderes Nicht-ASCII-Zeichen (Umlaut, ein
// Buchstabe ohne lateinischen Doppelgaenger) sperrt: das kann ein gewollter
// Name sein. Ebenso ein Name ohne einen einzigen ASCII-Buchstaben - der ist
// in einer anderen Schrift geschrieben, kein eingeschmuggelter Buchstabe.
//
// BEWIESEN (am Text, konservativ), sonst keine Hilfe:
//   - die Datei ist eine Unit mit implementation-Teil, und der Name kommt
//     im interface-Teil nicht vor (sonst sehen ihn andere Units; ein
//     Programm, eine Bibliothek, eine Unit mit 'exports' und eine
//     Include-Datei sperren);
//   - das ERSTE Vorkommen ist seine Deklaration (Delphi deklariert vor der
//     Nutzung - steht dort eine Nutzung, kommt der Name aus einer anderen
//     Unit): Routinen- oder Property-Name, Name in einer Deklarationsliste
//     ('X: T', 'X, Y: T', 'X = ..' hinter var, const, type, ';', '(' ...)
//     ausserhalb jedes Rumpfs, oder inline 'var X'/'const X' im Rumpf;
//   - ist die Deklaration lokal (in einer Routine), stehen alle Vorkommen
//     in dieser Routine; ausserhalb wuerde dort ein anderer Name gemeint;
//   - alle Vorkommen sind gleich geschrieben (die Hilfe kennt nur die
//     Tabelle, keine Gross-/Kleinschreibung kyrillischer Buchstaben);
//   - der neue Name ist kein reserviertes Wort und steht nirgends im Code
//     der Datei (sonst bindet eine bestehende Stelle um oder die neue
//     Deklaration verdeckt einen geerbten bzw. fremden Namen, den die Datei
//     benutzt);
//   - kein 'with' zwischen dem Anfang des Gueltigkeitsbereichs und dem
//     letzten Vorkommen: dort koennte der neue Name an ein Member binden;
//   - kein String-Literal ohne Leerzeichen nennt den alten oder neuen
//     Namen (Zugriff per Name: RTTI, FieldByName, Skript - ein Satz wie
//     'Login failed' zaehlt nicht), keine Compiler-Direktive nennt ihn
//     ('{$IF Declared(X)}').
// Kommentare bleiben, wie sie sind - der Compiler liest sie nicht.
//
// GRENZEN: die Deklarationsprobe liest Token, keinen Parser - ein
// Feldname in einer typisierten Record-Konstante ('(X: 1; Y: 2)') sieht
// aus wie eine Deklaration; benennt die Hilfe dann eine Nutzung um, die
// zu einer fremden Unit gehoert, uebersetzt die Unit nicht mehr (kein
// stilles Fehlverhalten, solange der neue Name dort unbekannt ist). Ein
// Kopf mit unsicheren Grenzen vor der Deklaration (Methoden im Rumpf einer
// Klasse des implementation-Teils, lokaler Klassentyp) sperrt. Der alte
// 'begin'-Abschnitt einer Unit (statt initialization) zaehlt als
// Deklarationsteil.
//
// FPC-TAUGLICH: nur Textlogik auf der Code-Sicht (uRdxCodeMap, uRdxBlocks,
// uRdxBufferMath, uRdxText, uRefactorInfo); die Tabelle steht als
// Zeichen-Codes im Quelltext (reines ASCII). Den Adapter fuer die Tabelle
// der Hilfen (PlanHomoglyph ueber TRdxFixFrame) traegt uRdxFixTable.

interface

uses
  uRdxBufferMath,   // TRdxEdit
  uRdxCodeMap;      // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_HG_NONE = 'no identifier with a non-ASCII character in the code of the '
    + 'reported line';
  R_HG_UNKNOWN = '%s in the name is no known look-alike of an ASCII letter '
    + '- maybe an intended letter';
  R_HG_NO_LATIN = 'the name has no ASCII letter - a name written in another '
    + 'script is no look-alike';
  R_HG_NOT_UNIT = 'the file is no unit with an implementation part, or it '
    + 'exports routines - the name may be used elsewhere';
  R_HG_SPELLING = 'line %d spells the name differently - the help renames '
    + 'one spelling only';
  R_HG_INTERFACE = 'the name appears in the interface part (line %d) - other '
    + 'units can use it';
  R_HG_NOT_DECLARED = 'the first use of the name (line %d) is not its '
    + 'declaration - it may come from another unit';
  R_HG_BOUNDS = 'the bounds of a routine before line %d are not safe to read';
  R_HG_OUTSIDE = 'the name is declared in a routine but used outside of it '
    + '(line %d) - another declaration may be meant there';
  R_HG_WITH = 'a "with" statement (line %d) could bind the new name %s to a '
    + 'member';
  R_HG_KEYWORD = '%s is a reserved word';
  R_HG_TAKEN = 'the name %s is already used in the code (line %d)';
  R_HG_LITERAL = 'a string literal names %s (line %d) - a lookup by name '
    + '(RTTI, scripts) could change';
  R_HG_DIRECTIVE = 'a compiler directive names %s (line %d)';

type
  // Ergebnis des Planers: je Vorkommen eine Ersetzung (EIN Undo-Schritt)
  // und der neue Name fuer den Menuetext ('' solange er nicht feststeht).
  TRdxHomoglyphPlan = record
    Edits : TArray<TRdxEdit>;
    Name  : string;
  end;

  // Der Planer auf der Code-Sicht in der Form TRdxPlannerOf<TPlan>
  // (uRdxFixTable): True genau dann, wenn AReason = ''. Die Meldung nennt
  // nichts, was die Hilfe braucht - AMessage bleibt ungelesen.
  TRdxHomoglyphFix = class
  public
    // SCA193: den ersten Bezeichner mit Nicht-ASCII-Zeichen auf ALine in
    // ASCII schreiben, an allen Vorkommen (s. Kopf der Unit).
    class function ToAscii(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxHomoglyphPlan;
      out AReason: string): Boolean; static;
    // Der ASCII-Buchstabe zum Homoglyph C (HOMOGLYPHS); #0 ohne.
    class function AsciiOf(C: Char): Char; static;
    // AName in ASCII (jedes Zeichen ueber #127 nach HOMOGLYPHS): True mit
    // dem neuen Namen, sonst False und der Grund.
    class function AsciiName(const AName: string; out ANew: string;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,    // TRefactorSpan.Make
  uRdxText,         // _(): in die reDelphix-Sprache, nie uLocalization
  uRdxBlocks;       // TRdxBlocks.HeadBefore, TRdxRoutine, TRdxHeadStep

type
  // Ein Paar der Tabelle: Zeichen-Code des Homoglyphs, ASCII-Buchstabe.
  THomoglyph = record
    Code  : Word;
    Ascii : Char;
  end;

const
  SPAN_193 = 'sca193';
  KW_EXPORTS = 'exports';
  CODE_PREFIX = 'U+';
  // Die bekannten Paare (Unicode confusables, nur Buchstaben, die in den
  // ueblichen Editor-Schriften nicht vom lateinischen zu unterscheiden
  // sind).
  HOMOGLYPHS: array[0..46] of THomoglyph = (
    // kyrillisch klein
    (Code: $0430; Ascii: 'a'), (Code: $0435; Ascii: 'e'),
    (Code: $043E; Ascii: 'o'), (Code: $0440; Ascii: 'p'),
    (Code: $0441; Ascii: 'c'), (Code: $0443; Ascii: 'y'),
    (Code: $0445; Ascii: 'x'), (Code: $0455; Ascii: 's'),
    (Code: $0456; Ascii: 'i'), (Code: $0458; Ascii: 'j'),
    (Code: $04BB; Ascii: 'h'), (Code: $04CF; Ascii: 'l'),
    (Code: $0501; Ascii: 'd'), (Code: $051B; Ascii: 'q'),
    (Code: $051D; Ascii: 'w'),
    // kyrillisch gross
    (Code: $0405; Ascii: 'S'), (Code: $0406; Ascii: 'I'),
    (Code: $0408; Ascii: 'J'), (Code: $0410; Ascii: 'A'),
    (Code: $0412; Ascii: 'B'), (Code: $0415; Ascii: 'E'),
    (Code: $041A; Ascii: 'K'), (Code: $041C; Ascii: 'M'),
    (Code: $041D; Ascii: 'H'), (Code: $041E; Ascii: 'O'),
    (Code: $0420; Ascii: 'P'), (Code: $0421; Ascii: 'C'),
    (Code: $0422; Ascii: 'T'), (Code: $0425; Ascii: 'X'),
    (Code: $04AE; Ascii: 'Y'), (Code: $051A; Ascii: 'Q'),
    (Code: $051C; Ascii: 'W'),
    // griechisch gross
    (Code: $0391; Ascii: 'A'), (Code: $0392; Ascii: 'B'),
    (Code: $0395; Ascii: 'E'), (Code: $0396; Ascii: 'Z'),
    (Code: $0397; Ascii: 'H'), (Code: $0399; Ascii: 'I'),
    (Code: $039A; Ascii: 'K'), (Code: $039C; Ascii: 'M'),
    (Code: $039D; Ascii: 'N'), (Code: $039F; Ascii: 'O'),
    (Code: $03A1; Ascii: 'P'), (Code: $03A4; Ascii: 'T'),
    (Code: $03A5; Ascii: 'Y'), (Code: $03A7; Ascii: 'X'),
    // griechisch klein
    (Code: $03BF; Ascii: 'o'));
  // Hier endet die Suche nach der Routine um eine Stelle: der Anfang des
  // implementation-Teils (Unit-Ebene) bzw. ein Abschnitt mit Anweisungen.
  UNIT_STOPS: array[0..2] of string = ('implementation', 'initialization',
    'finalization');
  // Davor beginnt eine Deklarationsliste ('var X: T', 'X: T' hinter ';',
  // Parameter hinter '(' und 'out', Felder hinter Sichtbarkeit, 'class',
  // der Vorfahrenliste ')' oder einem Attribut ']').
  DECL_PREV: array[0..14] of string = ('var', 'const', 'threadvar', 'type',
    'resourcestring', ';', '(', 'out', 'private', 'protected', 'public',
    'published', 'class', ')', ']');
  // Die reservierten Woerter von Delphi, dazu Result, Self und operator: so
  // darf der neue Name nicht heissen. Eigener Name, weil uRdxCodeMap seit
  // der Folgewelle B1 RESERVED (ohne die drei) fuehrt.
  BLOCKED_NAMES: array[0..66] of string = ('and', 'array', 'as', 'asm', 'begin',
    'case', 'class', 'const', 'constructor', 'destructor', 'dispinterface',
    'div', 'do', 'downto', 'else', 'end', 'except', 'exports', 'file',
    'finalization', 'finally', 'for', 'function', 'goto', 'if',
    'implementation', 'in', 'inherited', 'initialization', 'inline',
    'interface', 'is', 'label', 'library', 'mod', 'nil', 'not', 'object',
    'of', 'or', 'packed', 'procedure', 'program', 'property', 'raise',
    'record', 'repeat', 'resourcestring', 'set', 'shl', 'shr', 'string',
    'then', 'threadvar', 'to', 'try', 'type', 'unit', 'until', 'uses', 'var',
    'while', 'with', 'xor', 'result', 'self', 'operator');

function CodeOf(C: Char): string;
begin
  Result := CODE_PREFIX + IntToHex(Ord(C), 4);
end;

// Traegt S ein Zeichen ueber #127?
function HasNonAscii(const S: string): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := 1 to Length(S) do
    if Ord(S[i]) > 127 then
      Exit(True);
end;

// Der erste Bezeichner im Code von ALine mit einem Zeichen ueber #127; Low
// = '' ohne.
function NonAsciiWord(AMap: TRdxCodeMap; ALine: Integer): TRdxToken;
var
  T : TRdxToken;
begin
  Result := Default(TRdxToken);
  if (ALine < 1) or (ALine > AMap.LineCount) then Exit;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if T.IsWord and HasNonAscii(T.Low) then
      Exit(T);
    T := After(AMap, T);
  end;
end;

// Das Schluesselwort 'implementation' einer Unit (das erste Token der Datei
// ist 'unit'); Low = '' ohne.
function ImplementationOf(AMap: TRdxCodeMap): TRdxToken;
var
  T : TRdxToken;
begin
  Result := Default(TRdxToken);
  if NextToken(AMap, 1, 1).Low <> 'unit' then Exit;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), 'implementation');
  while T.Low <> '' do
  begin
    if (T.Low = 'implementation') and IsKeywordAfter(T, Before(AMap, T)) then
      Exit(T);
    T := NextTokenOnLineWith(AMap, T, 'implementation');
  end;
end;

// Alle Bezeichner im Code der Datei, die ALow (klein) nennen - Vergleich wie
// SameIdent (ein Zeichen ueber #127 passt zu jedem ueber #127; ein Treffer
// zu viel sperrt nur). Nur Zeilen mit einem Zeichen ueber #127 koennen sie
// tragen.
function Occurrences(AMap: TRdxCodeMap; const ALow: string): TArray<TRdxToken>;
var
  Li : Integer;
  T  : TRdxToken;
begin
  Result := nil;
  for Li := 1 to AMap.LineCount do
  begin
    if not HasNonAscii(AMap.Raw(Li)) then Continue;
    T := NextToken(AMap, Li, 1);
    while (T.Low <> '') and (T.Line = Li) do
    begin
      if T.IsWord and SameIdent(T.Low, ALow) then
        AddToken(Result, T);
      T := After(AMap, T);
    end;
  end;
end;

// Die innerste Routine, deren Bereich (Kopf bis letztes ';') AAt traegt -
// nicht die, deren Namen AAt selbst ist. ARoutine.Head.Low = '' ohne
// (Unit-Ebene), AStop das Abschnittswort, an dem die Suche endete ('' am
// Dateianfang). '' oder der Grund: ein Kopf mit unsicheren Grenzen davor.
function RoutineAround(AMap: TRdxCodeMap; const AAt: TRdxToken;
  out ARoutine: TRdxRoutine; out AStop: string): string;
var
  T : TRdxToken;
  S : TRdxHeadStep;
begin
  ARoutine := Default(TRdxRoutine);
  AStop := '';
  Result := '';
  T := AAt;
  while TRdxBlocks.HeadBefore(AMap, T, UNIT_STOPS, S) do
  begin
    if S.Stop then
    begin
      AStop := S.Tok.Low;
      Exit;
    end;
    if S.Reason <> '' then
      Exit(_(R_HG_BOUNDS, [AAt.Line]));
    if SameTok(S.Routine.NameTok, AAt) then
      Continue;
    if TokBefore(S.Routine.Head, AAt) and TokBefore(AAt, S.Routine.Last) then
    begin
      ARoutine := S.Routine;
      Exit;
    end;
  end;
end;

// Hat T die Form einer Deklaration ausserhalb eines Rumpfs? Routinen- bzw.
// Property-Name (nicht 'TKlasse.' vor dem Namen einer Methode), Marke,
// oder ein Name einer Liste 'A, T, B: Typ' bzw. 'T = ..' hinter einem Wort
// aus DECL_PREV.
function DeclShape(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
var
  P, N, W : TRdxToken;
begin
  Result := False;
  P := Before(AMap, T);
  if P.Low = '&' then
    P := Before(AMap, P);
  if (InList(P.Low, ROUTINE_WORDS) or (P.Low = 'property'))
     and IsKeywordAfter(P, Before(AMap, P)) then
    Exit(After(AMap, T).Low <> '.');
  if P.Low = 'label' then
    Exit(True);
  while P.Low = ',' do
  begin
    W := Before(AMap, P);
    if not W.IsWord then Exit;
    P := Before(AMap, W);
    if P.Low = '&' then
      P := Before(AMap, P);
  end;
  if not InList(P.Low, DECL_PREV) then Exit;
  N := After(AMap, T);
  while N.Low = ',' do
  begin
    W := After(AMap, N);
    if W.Low = '&' then
      W := After(AMap, W);
    if not W.IsWord then Exit;
    N := After(AMap, W);
  end;
  if N.Low = '<' then
    N := AfterClose(AMap, N);
  Result := (N.Low = ':') or (N.Low = '=');
end;

// Ist AFirst (das erste Vorkommen) die Deklaration? '' und in ALocal, ob
// sie in einer Routine steht (ARoutine), oder der Grund.
function DeclReason(AMap: TRdxCodeMap; const AFirst: TRdxToken;
  out ARoutine: TRdxRoutine; out ALocal: Boolean): string;
var
  Stop : string;
  P    : TRdxToken;
  Ok   : Boolean;
begin
  ALocal := False;
  Result := RoutineAround(AMap, AFirst, ARoutine, Stop);
  if Result <> '' then Exit;
  if ARoutine.Head.Low <> '' then
  begin
    ALocal := True;
    if (ARoutine.Body.Low <> '') and TokBefore(ARoutine.Body, AFirst)
       and TokBefore(AFirst, ARoutine.EndTok) then
    begin
      // Im Rumpf: nur inline 'var X' bzw. 'const X' (auch 'for var X').
      P := Before(AMap, AFirst);
      Ok := InList(P.Low, INLINE_DECLS) and IsKeywordAfter(P, Before(AMap, P));
    end
    else
      Ok := DeclShape(AMap, AFirst);
  end
  else
    // Unit-Ebene: nur im implementation-Teil, nicht in initialization bzw.
    // finalization (Anweisungen).
    Ok := (Stop = 'implementation') and DeclShape(AMap, AFirst);
  if not Ok then
    Result := _(R_HG_NOT_DECLARED, [AFirst.Line]);
end;

// Das erste 'with' als Schluesselwort von AFrom bis ATo (beide
// eingeschlossen); Zeile oder 0.
function WithLine(AMap: TRdxCodeMap; const AFrom, ATo: TRdxToken): Integer;
var
  T, P : TRdxToken;
begin
  Result := 0;
  P := Before(AMap, AFrom);
  T := AFrom;
  while (T.Low <> '') and not TokBefore(ATo, T) do
  begin
    if (T.Low = 'with') and IsKeywordAfter(T, P) then
      Exit(T.Line);
    P := T;
    T := After(AMap, T);
  end;
end;

// Die erste Zeile, deren Code den Bezeichner ALow (klein, ASCII) traegt; 0
// ohne.
function CodeLine(AMap: TRdxCodeMap; const ALow: string): Integer;
var
  T : TRdxToken;
begin
  Result := 0;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), ALow);
  while T.Low <> '' do
  begin
    if T.Low = ALow then
      Exit(T.Line);
    T := NextTokenOnLineWith(AMap, T, ALow);
  end;
end;

// Beginnt im Lauf ACol..AEnd der Zeile ALine eine Compiler-Direktive?
function RunHasDirective(AMap: TRdxCodeMap; ALine, ACol, AEnd: Integer): Boolean;
var
  Co : Integer;
begin
  Result := False;
  for Co := ACol to AEnd do
    if AMap.DirectiveStartsAt(ALine, Co) then
      Exit(True);
end;

// Die erste Zeile, auf der ein String-Literal (AClass 's') bzw. ein
// Kommentar-Lauf mit einer Direktive (AClass 'k') den Bezeichner ALow
// (klein) nennt; 0 ohne. Ein String zaehlt nur ohne Leerzeichen - so sieht
// ein Name aus, den RTTI, FieldByName oder ein Skript nachschlaegt ('Login',
// 'TUser.Login'); ein Satz ('Login failed') nennt das Wort nur. Vorfilter
// je Zeile: ein Zeichen ueber #127 bzw. das Wort (HasWordNoCase).
function MentionLine(AMap: TRdxCodeMap; const ALow: string;
  AClass: Char): Integer;
var
  Li, Co, E : Integer;
  L, Run    : string;
  Wide      : Boolean;
begin
  Result := 0;
  Wide := HasNonAscii(ALow);
  for Li := 1 to AMap.LineCount do
  begin
    L := AMap.Raw(Li);
    if Wide and not HasNonAscii(L) then Continue;
    if not Wide and not HasWordNoCase(L, ALow) then Continue;
    Co := 1;
    while Co <= Length(L) do
    begin
      if AMap.ClassAt(Li, Co) = AClass then
      begin
        E := Co;
        while AMap.ClassAt(Li, E + 1) = AClass do
          Inc(E);
        Run := Copy(L, Co, E - Co + 1);
        if HasIdentWord(LowerCase(Run), ALow)
           and (((AClass = 's') and (Pos(' ', Run) = 0))
                or ((AClass = 'k') and RunHasDirective(AMap, Li, Co, E))) then
          Exit(Li);
        Co := E + 1;
      end
      else
        Inc(Co);
    end;
  end;
end;

// Was die Namen ausserhalb des Codes trifft: ein String-Literal oder eine
// Direktive nennt den alten (AOld wie geschrieben) oder neuen Namen. '' oder
// der Grund.
function TextReason(AMap: TRdxCodeMap; const AOld, ANew: string): string;
var
  Li : Integer;
begin
  Result := '';
  Li := MentionLine(AMap, LowerCase(AOld), 's');
  if Li > 0 then
    Exit(_(R_HG_LITERAL, [AOld, Li]));
  Li := MentionLine(AMap, LowerCase(ANew), 's');
  if Li > 0 then
    Exit(_(R_HG_LITERAL, [ANew, Li]));
  Li := MentionLine(AMap, LowerCase(AOld), 'k');
  if Li > 0 then
    Exit(_(R_HG_DIRECTIVE, [AOld, Li]));
  Li := MentionLine(AMap, LowerCase(ANew), 'k');
  if Li > 0 then
    Exit(_(R_HG_DIRECTIVE, [ANew, Li]));
end;

{ TRdxHomoglyphFix }

class function TRdxHomoglyphFix.AsciiOf(C: Char): Char;
var
  H : THomoglyph;
begin
  for H in HOMOGLYPHS do
    if Ord(C) = H.Code then
      Exit(H.Ascii);
  Result := #0;
end;

class function TRdxHomoglyphFix.AsciiName(const AName: string;
  out ANew: string; out AReason: string): Boolean;
var
  i      : Integer;
  C, A   : Char;
  Latin  : Boolean;
begin
  ANew := '';
  AReason := '';
  Latin := False;
  for i := 1 to Length(AName) do
  begin
    C := AName[i];
    if Ord(C) <= 127 then
    begin
      Latin := Latin or CharInSet(C, ['A'..'Z', 'a'..'z']);
      ANew := ANew + C;
      Continue;
    end;
    A := AsciiOf(C);
    if A = #0 then
    begin
      ANew := '';
      AReason := _(R_HG_UNKNOWN, [CodeOf(C)]);
      Exit(False);
    end;
    ANew := ANew + A;
  end;
  if not Latin then
  begin
    ANew := '';
    AReason := _(R_HG_NO_LATIN);
  end;
  Result := AReason = '';
end;

class function TRdxHomoglyphFix.ToAscii(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out APlan: TRdxHomoglyphPlan;
  out AReason: string): Boolean;
var
  Tok, Impl, From  : TRdxToken;
  Occ              : TArray<TRdxToken>;
  T                : TRdxToken;
  R                : TRdxRoutine;
  Local            : Boolean;
  OldName, NewName : string;
  Li               : Integer;
  E                : TRdxEdit;
begin
  APlan := Default(TRdxHomoglyphPlan);
  R := Default(TRdxRoutine);
  Local := False;
  Result := False;
  Tok := NonAsciiWord(AMap, ALine);
  if Tok.Low = '' then
  begin
    AReason := MsgMovedSuffix(_(R_HG_NONE));
    Exit;
  end;
  OldName := TokText(AMap, Tok);
  if not AsciiName(OldName, NewName, AReason) then Exit;
  APlan.Name := NewName;
  Impl := ImplementationOf(AMap);
  if (Impl.Low = '') or (CodeLine(AMap, KW_EXPORTS) > 0) then
  begin
    AReason := _(R_HG_NOT_UNIT);
    Exit;
  end;
  Occ := Occurrences(AMap, LowerCase(OldName));
  for T in Occ do
  begin
    if TokText(AMap, T) <> OldName then
      AReason := _(R_HG_SPELLING, [T.Line])
    else if not TokBefore(Impl, T) then
      AReason := _(R_HG_INTERFACE, [T.Line]);
    if AReason <> '' then Exit;
  end;
  AReason := DeclReason(AMap, Occ[0], R, Local);
  if AReason <> '' then Exit;
  From := Impl;
  if Local then
  begin
    From := R.Head;
    for T in Occ do
      if TokBefore(T, R.Head) or not TokBefore(T, R.Last) then
      begin
        AReason := _(R_HG_OUTSIDE, [T.Line]);
        Exit;
      end;
  end;
  Li := WithLine(AMap, From, Occ[High(Occ)]);
  if Li > 0 then
    AReason := _(R_HG_WITH, [Li, NewName])
  else if InList(LowerCase(NewName), BLOCKED_NAMES) then
    AReason := _(R_HG_KEYWORD, [NewName])
  else
  begin
    Li := CodeLine(AMap, LowerCase(NewName));
    if Li > 0 then
      AReason := _(R_HG_TAKEN, [NewName, Li])
    else
      AReason := TextReason(AMap, OldName, NewName);
  end;
  if AReason <> '' then Exit;
  for T in Occ do
  begin
    E := Default(TRdxEdit);
    E.Span := TRefactorSpan.Make(SPAN_193, T.Line, T.Col, T.Line, T.EndCol);
    E.Expected := OldName;
    E.NewText := NewName;
    AddEdit(APlan.Edits, E);
  end;
  Result := True;
end;

end.

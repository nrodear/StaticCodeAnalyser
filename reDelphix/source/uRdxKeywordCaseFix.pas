unit uRdxKeywordCaseFix;

// reDelphix - Editorhilfe SCA064 LowercaseKeyword, OHNE ToolsAPI und ohne
// Parser: das gemeldete Schluesselwort ('Begin') wird klein geschrieben
// ('begin'). Delphi unterscheidet Gross- und Kleinschreibung nicht - die
// Bedeutung bleibt, nur der Text aendert sich.
//
// Der Detektor (uLowercaseKeyword) prueft nur das WORT: jedes Wort seiner
// Liste, das nicht klein steht, ausser in Strings, Kommentaren, asm-Bloecken
// und hinter '&'. Er kennt weder den Punkt davor ('Foo.End', 'L.Contains')
// noch den Zusammenhang - 'Register', 'Private', 'Override', 'On', 'Out'
// sind auch Bezeichner. GRUNDSATZ wie in uRdxLineFixes: lieber keine Hilfe
// als eine falsche. Der Planer prueft am aktuellen Text nach:
//   * das Wort steht an der gemeldeten Spalte, ist Code (kein String, kein
//     Kommentar), ganz (kein Teil eines laengeren Bezeichners) und genau so
//     geschrieben wie gemeldet;
//   * es ist ein Schluesselwort: nicht hinter '.', '&' oder '@', nicht
//     vor ':=' (benanntes Argument 'Range(Start := 0, End := 1)');
//   * RESERVIERTE Woerter ('begin', 'end', 'if', 'procedure' ...) sind
//     sonst immer Schluesselwoerter - Delphi erlaubt sie nur mit '&' als
//     Bezeichner;
//   * kontextabhaengige Woerter nur dort, wo der Zusammenhang sie sicher
//     zum Schluesselwort macht: Sichtbarkeit (private, protected, public,
//     published, strict) im Klassenkoerper vor einem Wort; Methoden-
//     Direktiven (override, virtual, overload, stdcall ...) hinter einem
//     ';' im Kopf einer Routine; abstract/sealed/helper/operator hinter
//     'class'/'record'.
//   * alle anderen (on, out, contains, requires, implements, absolute) und
//     jeder unklare Fall: keine Hilfe.
// Mehrere Funde in einer Zeile: jeder Fund hat seine Spalte, die Hilfe
// schreibt nur das Wort des angeklickten Fundes klein.

interface

uses
  System.Classes,       // TStrings
  uEngineApi,           // TSourcePlaces
  uMethodd12,           // TLeakFinding
  uRdxBufferMath,       // TRdxEdit
  uRdxCodeMap,          // TRdxCodeMap
  uRdxRecipeRunner;     // TRdxFixOutcome

const
  // Gruende der Ablehnung (deutsch, ASCII, wie die Nachbarn).
  KC_NO_WORD = 'Schluesselwort oder Spalte fehlt in der Meldung';
  KC_LOWER   = 'das Wort ist schon klein geschrieben';
  KC_MOVED   = 'das Schluesselwort steht nicht an der gemeldeten Stelle - '
    + 'Zeile verschoben? Datei neu pruefen';
  KC_IDENT   = 'hinter ".", "&" oder "@" und vor ":=" ist das Wort ein '
    + 'Bezeichner, kein Schluesselwort';
  KC_CONTEXT = '%s ist hier nicht sicher ein Schluesselwort (auch als '
    + 'Bezeichner zulaessig)';

type
  // Der Planer von SCA064 (Form TRdxMapPlanner, uRdxFixRunner).
  TRdxKeywordCaseFix = class
  public
    // SCA064: Meldung 'Keyword "Begin" should be lowercase ("begin") at
    // column 1.' Schreibt das Wort an der Spalte klein (gleiche Laenge).
    class function LowercaseKeyword(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

// Der Planer in der Form von TRdxFixPlanner (uRdxFixTable): Zeile und
// Meldung aus AFinding; Name = das Wort wie gemeldet ('Begin') fuer den
// Menuetext. APlaces und AUsesNames braucht die Hilfe nicht.
function PlanLowercaseKeyword(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxFixRunner;     // MapFix

const
  SPAN_064 = 'sca064';
  // Reservierte Woerter: als Bezeichner nur mit '&' - hinter '.', '&', '@'
  // und vor ':=' prueft der Planer vorher.
  RESERVED: array[0..63] of string = ('and', 'array', 'as', 'asm', 'begin',
    'case', 'class', 'const', 'constructor', 'destructor', 'dispinterface',
    'div', 'do', 'downto', 'else', 'end', 'except', 'exports', 'file',
    'finalization', 'finally', 'for', 'function', 'goto', 'if',
    'implementation', 'in', 'inherited', 'initialization', 'inline',
    'interface', 'is', 'label', 'library', 'mod', 'nil', 'not', 'object',
    'of', 'or', 'packed', 'procedure', 'program', 'property', 'raise',
    'record', 'repeat', 'resourcestring', 'set', 'shl', 'shr', 'string',
    'then', 'threadvar', 'to', 'try', 'type', 'unit', 'until', 'uses',
    'var', 'while', 'with', 'xor');
  VISIBILITY: array[0..3] of string = ('private', 'protected', 'public',
    'published');
  // Davor steht eine Sichtbarkeit im Klassenkoerper.
  VISIBILITY_PREV: array[0..6] of string = (';', ')', 'class', 'record',
    'object', 'interface', 'strict');
  ROUTINE_DIRECTIVES: array[0..12] of string = ('abstract', 'cdecl', 'final',
    'forward', 'override', 'overload', 'pascal', 'register', 'reintroduce',
    'safecall', 'stdcall', 'varargs', 'virtual');
  // Hier endet die Suche nach dem Kopf der Routine rueckwaerts (Tiefe 0):
  // ein Wort davor gehoert zu einer Anweisung oder Deklaration, nicht zum
  // Kopf.
  HEADER_STOPS: array[0..17] of string = (';', 'begin', 'end', ':=', 'then',
    'do', 'else', 'var', 'const', 'type', 'uses', 'implementation',
    'interface', 'initialization', 'finalization', 'try', 'finally',
    'except');
  // Den Kopf einer Routine erkennt die Suche an uRdxCodeMap.ROUTINE_WORDS.
  MAX_BACK = 400;   // so viele Token rueckwaerts, laenger ist kein Kopf

function IsReserved(const ALow: string): Boolean;
begin
  Result := InList(ALow, RESERVED);
end;

function IsRoutineDirective(const ALow: string): Boolean;
begin
  Result := InList(ALow, ROUTINE_DIRECTIVES);
end;

// Das Wort ATok ist eine Direktive hinter dem Kopf einer Routine: davor ein
// ';' (und davor weitere Direktiven, jede mit ';'), davor der Kopf, der
// rueckwaerts in einer Routine ('procedure', 'function', ...) endet, ohne
// vorher auf ein ';', begin, ':=' ... zu stossen. Eine Anweisung 'Register;'
// im Rumpf erfuellt das nicht (davor steht ';' oder 'begin' und eine
// Anweisung). DAHINTER steht bei einer Direktive ';': ein Member hinter
// einem Prozedurtyp-Feld ('OnDone: procedure of object;' / 'Forward:
// Boolean;') hat rueckwaerts dieselbe Form, aber ':' dahinter - er ist ein
// Feld, sein Name ist RTTI-sichtbar (TRttiField.Name, JSON-Export).
function IsDirectiveOfHeader(AMap: TRdxCodeMap; const ATok: TRdxToken): Boolean;
var
  Cur, P, T : TRdxToken;
  Depth, N  : Integer;
begin
  Result := False;
  if After(AMap, ATok).Low <> ';' then Exit;
  Cur := ATok;
  repeat
    P := Before(AMap, Cur);
    if P.Low <> ';' then Exit;
    T := Before(AMap, P);
    if not IsRoutineDirective(T.Low) then Break;
    Cur := T;
  until False;
  Depth := 0;
  N := 0;
  while (T.Low <> '') and (N < MAX_BACK) do
  begin
    if T.Low = ')' then
      Inc(Depth)
    else if T.Low = '(' then
    begin
      Dec(Depth);
      if Depth < 0 then Exit;
    end
    else if Depth = 0 then
    begin
      if InList(T.Low, ROUTINE_WORDS) then Exit(True);
      if InList(T.Low, HEADER_STOPS) then Exit;
    end;
    T := Before(AMap, T);
    Inc(N);
  end;
end;

// Sichtbarkeit im Klassenkoerper: davor ';', ')' oder der Typ-Kopf, dahinter
// ein Wort (Member, 'end') - ein Feld 'Public: Integer', ein Parameter und
// ein Aufruf 'Private;' haben dort ':' oder ';'.
function IsVisibility(const ALow: string; const APrev, ANext: TRdxToken): Boolean;
begin
  if ALow = 'strict' then
    Result := InList(APrev.Low, VISIBILITY_PREV)
      and ((ANext.Low = 'private') or (ANext.Low = 'protected'))
  else
    Result := InList(ALow, VISIBILITY) and InList(APrev.Low, VISIBILITY_PREV)
      and ANext.IsWord;
end;

// abstract/sealed hinter 'class' (vor '(' oder ';'), helper hinter class
// oder record (vor 'for'), operator hinter 'class'.
function IsClassModifier(const ALow: string; const APrev, ANext: TRdxToken): Boolean;
begin
  Result := False;
  if (ALow = 'abstract') or (ALow = 'sealed') then
    Result := (APrev.Low = 'class') and ((ANext.Low = '(') or (ANext.Low = ';'))
  else if ALow = 'helper' then
    Result := ((APrev.Low = 'class') or (APrev.Low = 'record'))
      and (ANext.Low = 'for')
  else if ALow = 'operator' then
    Result := (APrev.Low = 'class') and ANext.IsWord;
end;

// '' = ein Schluesselwort, sonst der Grund.
function KeywordReason(AMap: TRdxCodeMap; const ATok: TRdxToken;
  const AKw: string): string;
var
  Prev, Next : TRdxToken;
  Low        : string;
begin
  Result := '';
  Low := ATok.Low;
  Prev := Before(AMap, ATok);
  Next := After(AMap, ATok);
  if not IsKeywordAt(AMap, ATok, Prev) then
    Result := KC_IDENT
  else if IsReserved(Low) or IsVisibility(Low, Prev, Next)
     or IsClassModifier(Low, Prev, Next) then
    Result := ''
  else if not (IsRoutineDirective(Low) and IsDirectiveOfHeader(AMap, ATok)) then
    Result := Format(KC_CONTEXT, [AKw]);
end;

class function TRdxKeywordCaseFix.LowercaseKeyword(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  L, Kw, Lower : string;
  Col, Last    : Integer;
  Whole        : Boolean;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  Kw := QuotedText(AMessage, '"');
  Col := ColumnFromMessage(AMessage);
  Lower := LowerCase(Kw);
  if (Kw = '') or (Col <= 0) then
  begin
    AReason := KC_NO_WORD;
    Exit;
  end;
  if Kw = Lower then
  begin
    AReason := KC_LOWER;
    Exit;
  end;
  L := AMap.Raw(ALine);
  Last := Col + Length(Kw) - 1;
  // Das Wort steht genau so da, als Code, und ist ein ganzes Wort.
  Whole := (Last <= Length(L)) and (Copy(L, Col, Length(Kw)) = Kw)
    and AMap.IsCode(ALine, Col) and AMap.IsCode(ALine, Last)
    and ((Col = 1) or not IsIdentChar(L[Col - 1]))
    and ((Last = Length(L)) or not IsIdentChar(L[Last + 1]));
  if not Whole then
    AReason := KC_MOVED
  else
    AReason := KeywordReason(AMap, TokenAt(AMap, ALine, Col), Kw);
  if AReason <> '' then Exit;
  AEdit.Span := TRefactorSpan.Make(SPAN_064, ALine, Col, ALine, Last + 1);
  AEdit.Expected := Kw;
  AEdit.NewText := Lower;
  Result := True;
end;

function PlanLowercaseKeyword(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxKeywordCaseFix.LowercaseKeyword);
  Result.Name := QuotedText(AFinding.Message, '"');
end;

end.

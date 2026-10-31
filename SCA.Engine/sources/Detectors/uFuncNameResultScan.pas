unit uFuncNameResultScan;

// SCA204 FunctionNameAsResult / SCA205 FunctionNameRecursion - der reine
// Scanner, ohne AST, ohne Datei und ohne Typwissen (Charge N / FN,
// 2026-10-25, Auftrag Nico; Q5 im Todo_QuickFixes_Wettbewerb).
//
// Im Rumpf einer Funktion steht ihr Name fuer zwei verschiedene Dinge:
//
//   GetCount := FItems.Count;     LINKS vom ':=' ist der Name die
//                                 Ergebnisvariable (altmodische Pascal-
//                                 Form; Delphi schreibt Result) -> SCA204
//   Total := Total + X;           RECHTS (in jedem Ausdruck) ist der Name
//                                 ein AUFRUF der Funktion selbst, also eine
//                                 Rekursion - nicht das bisherige Ergebnis
//                                 -> SCA205
//
// PRAEMISSE per FPC-Mikroprobe belegt (fpc 3.2.2, scratchpad chargeN/FN/
// probe, vertrag.md): im Modus delphi/delphiunicode laeuft 'Total := Total
// + 1' rekursiv (Tiefe 3 bei Tiefenwaechter), ebenso in 'Exit(T + 1)', in
// 'if T > 1', in 'GetArr[0]' und mit Default-Parametern; 'Inc(T)',
// 'SetLength(T, ..)' und ein var-Argument 'P(T)' uebersetzen dort gar
// nicht ("Can't take the address of constant expressions"). In den Modi
// objfpc und fpc ist derselbe Name rechts das ERGEBNIS (Tiefe 1) - dort ist
// das Lesen kein Fehler. Result gibt es in delphi, delphiunicode und objfpc,
// in fpc/tp/macpas nur mit {$modeswitch result}.
//
// SCA204 (Zuweisung) meldet 'Name :=' am Anweisungsanfang. NICHT gemeldet:
// 'Name.Feld :=', 'Name[i] :=', 'Name^ :=' (unter FPC-delphi die
// Ergebnisvariable, fuer Delphi nicht belegt - bewusstes Falsch-Negativ),
// 'Name +=' (FPC-C-Operatoren).
//
// SCA205 (Lesen) meldet den nackten Namen in einem Ausdruck (nicht vor '(',
// nicht vor Typargumenten '<T>', nicht hinter '.', '@', 'inherited'), nicht
// als Aufruf-Anweisung 'Name;'. Nur fuer Funktionen, die ihrem Namen SELBST
// zuweisen: wer Result schreibt, kennt den Unterschied, und der nackte Name
// ist dann die Delphi-Schreibweise des parameterlosen rekursiven Aufrufs
// (Korpus: 20 von 20 solcher Stellen bewusst - Parser 'Result :=
// -ReadFactor', Wiederholung 'Result := AddKeyStroke', Funktionszeiger
// 'errno := Stub_errno', generisch 'GetView<NSView>'). Ausserdem nur, wenn
// der Kopf die Parameter belegt (Kopf mit Rueckgabetyp) und keinen
// Pflichtparameter hat: mit einem ist der nackte Name entweder ein
// Compilerfehler oder der Aufruf einer anderen Ueberladung (Probe: F(A) ruft
// mit 'F + A' das F()). Schwere (Proven, der Detektor setzt sie):
//   * Error (BEWIESEN): keine Parameter, keine erkennbare bewusste
//     Rekursion im Rumpf ('Name()', 'Name<T>', Aufruf-Anweisung 'Name;',
//     'Self.Name') und der Name steht nicht als nacktes Argument eines
//     Aufrufs (ausser Exit) - ein var-Parameter liesse die Unit unter Delphi
//     gar nicht uebersetzen;
//   * sonst Warning (nur Default-Parameter, bewusste Rekursion daneben,
//     nacktes Argument).
//
// Gesperrt (kein Fund):
//   * Modus: SCA204 nur wenn Result existiert (delphi, delphiunicode,
//     objfpc, oder {$modeswitch result}; nicht unter {$X-} bzw.
//     {$EXTENDEDSYNTAX OFF}, dort kennt Delphi kein Result); SCA205 nur im
//     Delphi-Modus
//     (delphi, delphiunicode). Steht KEINE {$mode}-Direktive in der Datei,
//     entscheidet ADelphiDefault (Scan-Dialekt Delphi: ja; FPC: Modus
//     unbekannt, also nein). Mehrere {$mode}-Direktiven (IFDEF-Zweige):
//     alle muessen passen;
//   * Prozeduren, Konstruktoren, Destruktoren, Operatoren;
//   * Deklarationen ohne Rumpf (interface-Abschnitt, Klassenrumpf,
//     forward, external);
//   * die Routine verdeckt den Namen: Parameter, lokale Variable,
//     Konstante, Typ oder geschachtelte Routine gleichen Namens - oder eine
//     geschachtelte Routine nennt ihn (sie kann das Ergebnis der aeusseren
//     setzen) - irgendwo zwischen Kopf und begin; inline 'var Name';
//   * der Name in einer with-Anweisung (das Objekt kann ein Element
//     gleichen Namens haben - Probe: 'with O do Total := 5' setzt das Feld)
//     oder in einer anonymen Methode - nur diese Spanne;
//   * asm-Bloecke;
//   * SCA204: ein Parameter oder eine eigene Deklaration heisst Result;
//   * SCA205: eine Direktive direkt vor oder hinter dem Namen (zwei
//     IFDEF-Fassungen aneinander);
//   * Kommentare und Strings (der Tokenizer ueberliest sie).
//
// Bedingte Uebersetzung: von {$IFDEF}/{$IF}..{$ELSE}..{$ENDIF} liest der
// Scanner EINEN Zweig - FPC ist aus dem Scan-Dialekt bekannt, jedes andere
// Symbol unbekannt (dann der erste Zweig). Sonst stuenden zwei Fassungen
// hintereinander und ein begin zu viel vor dem end (NoteConditional).
//
// Die Eingabe ist der Quelltext der Unit (Kommentare und Strings liest der
// Scanner selbst; die {$mode}-Direktiven braucht er). Ohne Generics und
// Inline-Variablen: der Korpus-Harness uebersetzt die Unit mit FPC 3.2.2.
//
// Tempo (Perf R1, 2026-10-25; vorher ~1,95 s auf laz/jvcl strict, 85 % im
// Tokenizer): der Lexer legt Token als Spannen ohne Zeichenketten an
// (TFnLite); der Vorfilter CanHit prueft darauf die notwendige Bedingung
// 'Funktionsname :=' (rund 3 % der Korpusdateien bestehen ihn); nur dann
// entstehen Text/Low (MaterializeAll, je verschiedener Zeichenfolge einmal)
// und laeuft der Scanner. Treffer identisch (FPC-Harness, 17.979 Dateien x
// beide Dialekte, byte-gleich).

interface

uses
  System.SysUtils;

type
  TFuncNameUse = (fnuAssign, fnuRead);

  TFuncNameHit = record
    Use      : TFuncNameUse;
    Line     : Integer;   // 1-basiert
    Col      : Integer;   // 1-basiert, erstes Zeichen des Namens
    Written  : string;    // der Name wie an der Stelle geschrieben
    Routine  : string;    // voller Name aus dem Kopf ('TFoo.GetCount')
    Proven   : Boolean;   // nur fnuRead: die bewiesene Menge (Error)
  end;

  TFuncNameHits = array of TFuncNameHit;

  // Was die {$mode}-Direktiven der Datei erlauben.
  TFuncNameModes = record
    AllowAssign : Boolean;   // Result existiert (SCA204, Fix)
    AllowRead   : Boolean;   // der Name rechts ist ein Aufruf (SCA205)
  end;

  TFuncNameScan = class
  public
    // Alle Treffer im Text, nach Position sortiert (je Routine in
    // Textreihenfolge, Routinen in der Reihenfolge ihres Rumpfendes).
    // AWantAssign = False (SCA204 nicht im Profil): ohne die fnuAssign-
    // Treffer, die Lese-Treffer unveraendert (Perf R1).
    class function ScanText(const AText: string; ADelphiDefault: Boolean;
      AWantAssign: Boolean = True): TFuncNameHits; static;

    // Die Meldung des Treffers (englisch wie alle Detektor-Meldungen).
    class function MessageOf(const AHit: TFuncNameHit): string; static;
  end;

const
  // Feste Teile der Meldungen. Der Planer in reDelphix (uRdxFuncNameFix)
  // liest den Namen aus FNR_ASSIGN_PREFIX + Name + FNR_ASSIGN_MID - wer
  // die Texte aendert, aendert beide.
  FNR_ASSIGN_PREFIX = 'Result assigned through the function name: ''';
  FNR_ASSIGN_MID    = ' :=''';
  FNR_ASSIGN_ADVICE = ' - write ''Result :='' (the bare name in an '
    + 'expression is a recursive call)';
  FNR_READ_FMT = 'Function name ''%s'' read in its own body is a recursive '
    + 'call, not the current result - use Result, or write %s() if the '
    + 'recursion is intended';

implementation

type
  TFnTokKind = (ftWord, ftNumber, ftString, ftSym);

  TFnTok = record
    Kind : TFnTokKind;
    Text : string;    // wie geschrieben (ohne '&')
    Low  : string;    // klein (Woerter), sonst = Text
    Line : Integer;
    Col  : Integer;
    // Direkt vor dem Token stand eine {$..}-Direktive (IFDEF-Zweige setzen
    // sonst Bruchstuecke zweier Fassungen aneinander).
    AfterDir : Boolean;
  end;

  TFnToks = array of TFnTok;

  // Ein Token als Spanne im Text, ohne Zeichenketten (Perf R1): der Lexer
  // legt erst diese an; Text/Low (TFnTok) entstehen nur fuer Dateien, die
  // den Vorfilter CanHit bestehen (Materialize).
  TFnLite = record
    Kind     : TFnTokKind;
    From     : Integer;   // Index des ersten Zeichens (mit '&')
    Len      : Integer;
    Line     : Integer;
    Col      : Integer;
    AfterDir : Boolean;
    Esc      : Boolean;   // '&'-Bezeichner
  end;

  TFnLites = array of TFnLite;

  TFnDirectives = record
    Modes        : array of string;   // klein, erstes Wort hinter $mode
    ResultSwitch : Boolean;           // {$modeswitch result} / result+
    ResultOff    : Boolean;           // kein Result: {$modeswitch result-},
                                      // {$X-}, {$EXTENDEDSYNTAX OFF}
    // Bedingte Uebersetzung: je offenem {$IF..} der Zweig, der gilt.
    FpcDefined   : Boolean;           // FPC gilt als definiert (Scan-Dialekt)
    Taking       : array of Boolean;  // der aktuelle Zweig wird gelesen
    AnyTaken     : array of Boolean;  // ein Zweig dieses IF wurde gelesen
    Depth        : Integer;
  end;

  // Der Kopf einer Routine.
  TFnHead = record
    Keyword      : string;    // function, procedure, ... (klein)
    Full         : string;    // TFoo.GetCount
    Short        : string;    // GetCount (wie geschrieben)
    ShortLow     : string;
    HasResType   : Boolean;   // ': Typ' im Kopf - Parameter sind belegt
    ParamCount   : Integer;   // Gruppen mit Namen
    AllDefault   : Boolean;   // jede Gruppe hat '= Wert'
    ParamShadow  : Boolean;   // ein Parameter heisst wie die Funktion
    ParamResult  : Boolean;   // ein Parameter heisst Result
    DeclResult   : Boolean;   // der eigene Deklarationsteil nennt Result
  end;

  // Was ein Rumpf ueber den Namen weiss (ScanBody).
  TFnBodyUses = record
    Assigns    : array of Integer;   // Token 'Name' vor ':='
    NA         : Integer;
    Reads      : array of Integer;   // Token 'Name' in einem Ausdruck
    ReadArg    : array of Boolean;   // ... als nacktes Aufruf-Argument
    NR         : Integer;
    Deliberate : Boolean;            // bewusste Rekursion im Rumpf
  end;

  TFnBools = array of Boolean;

  // Schachtelung beim Lesen einer Anweisung (StatementEnd).
  TFnNesting = record
    Depth : Integer;   // Klammern
    Blk   : Integer;   // begin/try/case/asm .. end
    Rep   : Integer;   // repeat .. until
  end;

  // Eine Gruppe der Parameterliste (ParseParams).
  TFnParamGroup = record
    HasName    : Boolean;
    HasDefault : Boolean;
    InNames    : Boolean;
  end;

  // Wie ein Vorkommen des Namens im Rumpf zaehlt (ClassifyUse).
  TFnUseClass = (fucNone, fucAssign, fucRead);

  // Die Token-Folge der Unit und ihre Strukturfragen (ohne Urteil).
  TFnTokens = class
  protected
    FToks : TFnToks;
    FN    : Integer;
    function LowAt(I: Integer): string;
    function IsWord(I: Integer): Boolean;
    function IsSym(I: Integer; const S: string): Boolean;
    function IsWordIn(I: Integer; const AList: array of string): Boolean;
    function MatchClose(I: Integer; const AOpen, AClose: string): Integer;
    function SkipTo(I: Integer; const ASym: string): Integer;
    function AsmEnd(I: Integer): Integer;
    function BlockEnd(I: Integer): Integer;
    function BlockStep(K: Integer; var S: TFnNesting): Boolean;
    function StatementEnd(I, ALimit: Integer): Integer;
    function IsGenericArgs(I: Integer): Boolean;
    function IsTypeOpener(I: Integer): Boolean;
    function SkipTypeBody(I: Integer): Integer;
    function IsRoutineStart(I: Integer): Boolean;
    function NamesWord(AFrom, ATo: Integer; const ALow: string): Boolean;
  public
    constructor Create(const AToks: TFnToks);
  end;

  // Routinen finden, Kopf lesen, Rumpf beurteilen.
  TFnScanner = class(TFnTokens)
  private
    FHits   : TFuncNameHits;
    FHitN   : Integer;
    FModes  : TFuncNameModes;
    function ParseName(var J: Integer; var AHead: TFnHead): Boolean;
    procedure NoteParamWord(J: Integer; var G: TFnParamGroup;
      var AHead: TFnHead);
    procedure ParseParams(AOpen, AClose: Integer; var AHead: TFnHead);
    function ParseHead(var I: Integer; out AHead: TFnHead): Boolean;
    function SkipDirectives(var J: Integer): Boolean;
    function ParseDecls(var J: Integer; var AHead: TFnHead): Boolean;
    function ParseRoutine(I: Integer): Integer;
    function MaskedEnd(I, ALimit: Integer): Integer;
    function InlineDeclares(J: Integer; const ALow: string): Boolean;
    function MaskBody(const AHead: TFnHead; ABegin, AEnd: Integer;
      out AMasked: TFnBools): Boolean;
    function IsCallForm(J: Integer; var AUses: TFnBodyUses): Boolean;
    function ClassifyUse(J, ABegin, AEnd: Integer;
      var AUses: TFnBodyUses): TFnUseClass;
    procedure AddRead(J: Integer; var AUses: TFnBodyUses);
    procedure NoteUse(J, ABegin, AEnd: Integer; var AUses: TFnBodyUses);
    procedure ScanBody(const AHead: TFnHead; ADeclFrom, ABegin,
      AEnd: Integer);
    procedure EmitHits(const AHead: TFnHead; const AUses: TFnBodyUses);
    procedure AddHit(const AHead: TFnHead; AUse: TFuncNameUse; ATok: Integer;
      AProven: Boolean);
  public
    constructor Create(const AToks: TFnToks; const AModes: TFuncNameModes);
    procedure Run;
    function Hits: TFuncNameHits;
  end;

const
  // Woerter, mit denen hinter dem Kopf der Deklarationsteil bzw. Rumpf
  // beginnt (alles andere ist eine Direktive bis zum ';').
  BODY_WORDS: array[0..14] of string = (
    'var', 'const', 'type', 'label', 'resourcestring', 'threadvar',
    'begin', 'asm', 'procedure', 'function', 'constructor', 'destructor',
    'class', 'operator', 'generic');
  ROUTINE_WORDS: array[0..4] of string = (
    'function', 'procedure', 'constructor', 'destructor', 'operator');
  // Typen mit Rumpf bis 'end' (vor ihnen '=' bzw. 'packed').
  CLASSLIKE_WORDS: array[0..7] of string = (
    'class', 'object', 'interface', 'dispinterface', 'objcclass',
    'objcprotocol', 'objccategory', 'cppclass');
  // Vor dem Namen am Anweisungsanfang.
  STMT_START: array[0..9] of string = (
    ';', 'begin', 'then', 'else', 'do', 'try', 'finally', 'except',
    'repeat', 'otherwise');
  // Hinter einer Aufruf-Anweisung 'Name'.
  STMT_END: array[0..5] of string = (
    ';', 'end', 'else', 'until', 'finally', 'except');
  // Oeffnen einen Block, den ein 'end' schliesst (BlockEnd).
  BLOCK_WORDS: array[0..3] of string = ('begin', 'try', 'case', 'record');
  // Beenden die Deklarationen ohne Rumpf (ParseRoutine).
  UNIT_PART_WORDS: array[0..3] of string = (
    'implementation', 'initialization', 'finalization', 'end');
  // Eingebaute Routinen mit var-Parameter: der Name als Argument uebersetzt
  // im Delphi-Modus nicht (Probe c_inc, m_varparam) - kein Fund.
  VAR_BUILTINS: array[0..15] of string = (
    'inc', 'dec', 'setlength', 'str', 'val', 'fillchar', 'move',
    'include', 'exclude', 'freeandnil', 'readln', 'read', 'insert',
    'delete', 'initialize', 'finalize');
  // Zusammengesetzte Zuweisungen (FPC {$COPERATORS}).
  COMPOUND_ASSIGN: array[0..3] of string = ('+=', '-=', '*=', '/=');
  PARAM_MODIFIERS: array[0..3] of string = ('const', 'var', 'out',
    'constref');

function InList(const S: string; const AList: array of string): Boolean;
var
  i : Integer;
begin
  for i := 0 to High(AList) do
    if AList[i] = S then
      Exit(True);
  Result := False;
end;

function IsWordStart(C: Char): Boolean;
begin
  case C of
    'A'..'Z', 'a'..'z', '_': Result := True;
  else
    Result := Ord(C) > 127;
  end;
end;

// Perf R1: ein case statt IsWordStart + Ziffernvergleich (je Zeichen jedes
// Worts).
function IsWordChar(C: Char): Boolean;
begin
  case C of
    'A'..'Z', 'a'..'z', '_', '0'..'9': Result := True;
  else
    Result := Ord(C) > 127;
  end;
end;

function IsDigit(C: Char): Boolean;
begin
  Result := (C >= '0') and (C <= '9');
end;

function IsLineBreak(C: Char): Boolean;
begin
  Result := (C = #13) or (C = #10);
end;

{ ---- Tokenizer ---- }

type
  TFnLexer = record
    S        : string;
    N        : Integer;
    P        : Integer;
    Line     : Integer;
    LineFrom : Integer;   // Index des ersten Zeichens der Zeile
  end;

function CharAt(const L: TFnLexer; APos: Integer): Char;
begin
  if (APos >= 1) and (APos <= L.N) then
    Result := L.S[APos]
  else
    Result := #0;
end;

procedure LexNewLine(var L: TFnLexer);
begin
  // P steht auf #13 oder #10; #13#10 zaehlt einmal.
  if (L.S[L.P] = #13) and (CharAt(L, L.P + 1) = #10) then
    Inc(L.P);
  Inc(L.P);
  Inc(L.Line);
  L.LineFrom := L.P;
end;

// Ueberliest bis hinter AClose (ein oder zwei Zeichen) und zaehlt Zeilen.
// AFrom/ALen: der Text dazwischen (Perf R1: als Spanne - kopiert wird nur
// der Rumpf einer Direktive, nicht jeder Kommentar).
// AClose2 = #0: ein Zeichen.
procedure LexSkipTo(var L: TFnLexer; AClose1, AClose2: Char;
  out AFrom, ALen: Integer);
var
  C : Char;
begin
  AFrom := L.P;
  while L.P <= L.N do
  begin
    C := L.S[L.P];
    if (C = AClose1) and
       ((AClose2 = #0) or (CharAt(L, L.P + 1) = AClose2)) then
    begin
      ALen := L.P - AFrom;
      if AClose2 = #0 then
        Inc(L.P)
      else
        Inc(L.P, 2);
      Exit;
    end;
    if (C = #13) or (C = #10) then
      LexNewLine(L)
    else
      Inc(L.P);
  end;
  ALen := L.N - AFrom + 1;
end;

// Ein Pascal-String ab Q samt #nn-Folgen: Index dahinter. Eine Zeile
// schliesst ein offenes Literal.
// Ein '..'-Teil ab dem Hochkomma Q: Index dahinter ('' bleibt drin).
function LexQuotedEnd(const L: TFnLexer; Q: Integer): Integer;
begin
  Result := Q + 1;
  while (Result <= L.N) and not IsLineBreak(L.S[Result]) do
  begin
    if L.S[Result] <> '''' then
      Inc(Result)
    else if CharAt(L, Result + 1) = '''' then
      Inc(Result, 2)
    else
      Exit(Result + 1);
  end;
end;

// Ein #nn- bzw. #$hh-Teil ab Q: Index dahinter.
function LexCharCodeEnd(const L: TFnLexer; Q: Integer): Integer;
begin
  Result := Q + 1;
  if CharAt(L, Result) = '$' then Inc(Result);
  while IsWordChar(CharAt(L, Result)) do
    Inc(Result);
end;

function LexStringEnd(const L: TFnLexer; Q: Integer): Integer;
begin
  Result := Q;
  while (CharAt(L, Result) = '''') or (CharAt(L, Result) = '#') do
    if L.S[Result] = '#' then
      Result := LexCharCodeEnd(L, Result)
    else
      Result := LexQuotedEnd(L, Result);
end;

function LexWordEnd(const L: TFnLexer; Q: Integer): Integer;
begin
  Result := Q + 1;
  while (Result <= L.N) and IsWordChar(L.S[Result]) do
    Inc(Result);
end;

// Steht bei P ein Zwei-Zeichen-Symbol des Tokenizers (':=', '..', '<=',
// '>=', '<>', '+=', '-=', '*=', '/=', '@@')? Zeichenvergleich statt Copy +
// Listensuche je Symbol (Perf R1).
function IsTwoCharSym(const L: TFnLexer; P: Integer): Boolean;
var
  C1, C2 : Char;
begin
  C1 := L.S[P];
  C2 := CharAt(L, P + 1);
  case C1 of
    ':', '<', '>', '+', '-', '*', '/':
      Result := (C2 = '=') or ((C1 = '<') and (C2 = '>'));
    '.': Result := C2 = '.';
    '@': Result := C2 = '@';
  else
    Result := False;
  end;
end;

// Ein Token ab L.P (dort steht kein Leerraum und kein Kommentar) als
// Spanne. L.P steht danach dahinter.
procedure LexToken(var L: TFnLexer; out T: TFnLite);
var
  C : Char;
  Q : Integer;
begin
  C := L.S[L.P];
  T.Line := L.Line;
  T.Col := L.P - L.LineFrom + 1;
  T.AfterDir := False;
  T.Esc := (C = '&') and IsWordStart(CharAt(L, L.P + 1));
  if (C = '''') or (C = '#') then
  begin
    Q := LexStringEnd(L, L.P);
    T.Kind := ftString;
  end
  else if IsDigit(C) or (C = '$') or (C = '%') or
          ((C = '&') and IsDigit(CharAt(L, L.P + 1))) then
  begin
    Q := LexWordEnd(L, L.P);
    T.Kind := ftNumber;
  end
  else if IsWordStart(C) or T.Esc then
  begin
    Q := LexWordEnd(L, L.P);
    T.Kind := ftWord;
  end
  else
  begin
    if IsTwoCharSym(L, L.P) then
      Q := L.P + 2
    else
      Q := L.P + 1;
    T.Kind := ftSym;
  end;
  T.From := L.P;
  T.Len := Q - L.P;
  L.P := Q;
end;

// Text und Kleinwort eines Tokens aus seiner Spanne.
procedure Materialize(const S: string; const ALite: TFnLite; out T: TFnTok);
begin
  T.Kind := ALite.Kind;
  T.Line := ALite.Line;
  T.Col := ALite.Col;
  T.AfterDir := ALite.AfterDir;
  if ALite.Esc then
  begin
    // Ein '&'-Bezeichner ist nie ein Schluesselwort: das Kleinwort traegt
    // das '&' weiter, damit kein 'begin'/'end' daraus wird.
    T.Text := Copy(S, ALite.From + 1, ALite.Len - 1);
    T.Low := '&' + LowerCase(T.Text);
  end
  else
  begin
    T.Text := Copy(S, ALite.From, ALite.Len);
    if T.Kind in [ftWord, ftNumber] then
      T.Low := LowerCase(T.Text)
    else
      T.Low := T.Text;
  end;
end;

// Bedingung einer {$IF..}-Direktive: 1 wahr, 0 falsch, -1 unbekannt. Nur
// das Symbol FPC ist bekannt (aus dem Scan-Dialekt); alles andere ist
// unbekannt und nimmt den ersten Zweig.
function CondValue(const AName, AArg: string;
  const D: TFnDirectives): Integer;
var
  Sym, A : string;
  i : Integer;
begin
  Result := -1;
  A := StringReplace(AArg, ' ', '', [rfReplaceAll]);
  i := 1;
  while (i <= Length(A)) and IsWordChar(A[i]) do
    Inc(i);
  Sym := Copy(A, 1, i - 1);
  if ((AName = 'ifdef') or (AName = 'ifndef')) and (Sym = 'fpc') then
    Result := Ord(D.FpcDefined = (AName = 'ifdef'))
  else if ((AName = 'if') or (AName = 'elseif')) and
          (A = 'defined(fpc)') then
    Result := Ord(D.FpcDefined)
  else if ((AName = 'if') or (AName = 'elseif')) and
          (A = 'notdefined(fpc)') then
    Result := Ord(not D.FpcDefined);
end;

// Ist der Text an dieser Stelle in der Uebersetzung (alle offenen IF-Zweige
// werden gelesen)?
function DirsActive(const D: TFnDirectives): Boolean;
var
  i : Integer;
begin
  for i := 0 to D.Depth - 1 do
    if not D.Taking[i] then
      Exit(False);
  Result := True;
end;

procedure PushConditional(var D: TFnDirectives; AValue: Integer);
begin
  if D.Depth = Length(D.Taking) then
  begin
    SetLength(D.Taking, D.Depth * 2 + 4);
    SetLength(D.AnyTaken, D.Depth * 2 + 4);
  end;
  D.Taking[D.Depth] := AValue <> 0;
  D.AnyTaken[D.Depth] := AValue <> 0;
  Inc(D.Depth);
end;

// Bedingte Uebersetzung: von zwei Fassungen ('{$IFNDEF FPC} if .. begin
// {$ELSE} if .. begin {$ENDIF}') liest der Scanner EINE - sonst stehen
// zwei 'begin' vor einem 'end', und der Rumpf einer geschachtelten Routine
// laeuft in den der aeusseren hinein (Korpus: SynUniRules CanBeToken).
// Gilt ein Zweig (Wert 1 oder unbekannt), sind alle weiteren desselben IF
// aus; ELSE gilt nur, wenn keiner galt.
procedure NoteConditional(const AName, AArg: string; var D: TFnDirectives);
var
  Top : Integer;
begin
  if InList(AName, ['ifdef', 'ifndef', 'if', 'ifopt']) then
  begin
    PushConditional(D, CondValue(AName, AArg, D));
    Exit;
  end;
  if D.Depth = 0 then Exit;
  Top := D.Depth - 1;
  if (AName = 'elseif') and D.AnyTaken[Top] then
    D.Taking[Top] := False
  else if AName = 'elseif' then
  begin
    D.Taking[Top] := CondValue(AName, AArg, D) <> 0;
    D.AnyTaken[Top] := D.Taking[Top];
  end
  else if AName = 'else' then
  begin
    D.Taking[Top] := not D.AnyTaken[Top];
    D.AnyTaken[Top] := True;
  end
  else if (AName = 'endif') or (AName = 'ifend') then
    Dec(D.Depth);
end;

// {$mode X} und {$modeswitch result[+|-]}. Ein {$mode} zaehlt auch in
// einem Zweig, der nicht gelesen wird (vorsichtig: ein objfpc-Zweig sperrt
// SCA205).
procedure NoteMode(const AName, AArg: string; var D: TFnDirectives);
var
  i : Integer;
begin
  if AName = 'mode' then
  begin
    i := 1;
    while (i <= Length(AArg)) and IsWordChar(AArg[i]) do
      Inc(i);
    SetLength(D.Modes, Length(D.Modes) + 1);
    D.Modes[High(D.Modes)] := Copy(AArg, 1, i - 1);
  end
  else if AName <> 'modeswitch' then
    Exit
  else if InList(AArg, ['result', 'result+', 'result on']) then
    D.ResultSwitch := True
  else if InList(AArg, ['result-', 'result off']) then
    D.ResultOff := True;
end;

// {$X-} bzw. {$EXTENDEDSYNTAX OFF}: Delphi kennt dann kein Result (wie
// reDelphix uRdxResultFixes.DirectiveResultReason), auch in einer
// Schalterliste '{$H+,X-}'. FPC nimmt Result dort trotzdem (Probe) - die
// Sperre gilt der Delphi-Uebersetzung.
procedure NoteExtSyntax(const AName, AArg: string; var D: TFnDirectives);
var
  Sw : string;
begin
  Sw := ',' + StringReplace(AName + AArg, ' ', '', [rfReplaceAll]) + ',';
  if ((AName = 'extendedsyntax') and (Copy(AArg, 1, 3) = 'off')) or
     ((Length(AName) = 1) and (Pos(',x-,', Sw) > 0)) then
    D.ResultOff := True;
end;

procedure NoteDirective(const ABody: string; var D: TFnDirectives);
var
  T, Name, Arg : string;
  i : Integer;
begin
  // ABody: Text hinter '$' bis vor die Klammer.
  T := LowerCase(Trim(ABody));
  i := 1;
  while (i <= Length(T)) and IsWordChar(T[i]) do
    Inc(i);
  Name := Copy(T, 1, i - 1);
  Arg := Trim(Copy(T, i, MaxInt));
  NoteConditional(Name, Arg, D);
  NoteMode(Name, Arg, D);
  NoteExtSyntax(Name, Arg, D);
end;

// Perf R1: der ganze Leerraum-Lauf ab L.P in einem Aufruf (Zeilenenden
// zaehlen wie bisher einzeln).
procedure LexBlankRun(var L: TFnLexer);
var
  C : Char;
begin
  C := L.S[L.P];
  repeat
    if (C = #13) or (C = #10) then
      LexNewLine(L)
    else
      Inc(L.P);
    if L.P > L.N then Break;
    C := L.S[L.P];
  until not ((C <= ' ') or (C = #$FEFF));
end;

// Leerraum, Zeilenende, Kommentar oder Direktive ab L.P ueberlesen (eine
// Einheit). False: dort beginnt ein Token. ADir: es war eine Direktive.
function LexTrivia(var L: TFnLexer; var D: TFnDirectives;
  var ADir: Boolean): Boolean;
var
  C : Char;
  BodyFrom, BodyLen : Integer;
begin
  Result := True;
  C := L.S[L.P];
  if (C <= ' ') or (C = #$FEFF) then
    LexBlankRun(L)
  else if (C = '/') and (CharAt(L, L.P + 1) = '/') then
  begin
    while (L.P <= L.N) and not IsLineBreak(L.S[L.P]) do
      Inc(L.P);
  end
  else if (C = '{') or ((C = '(') and (CharAt(L, L.P + 1) = '*')) then
  begin
    if C = '{' then
    begin
      Inc(L.P);
      LexSkipTo(L, '}', #0, BodyFrom, BodyLen);
    end
    else
    begin
      Inc(L.P, 2);
      LexSkipTo(L, '*', ')', BodyFrom, BodyLen);
    end;
    // Nur der Rumpf einer Direktive wird kopiert (Text hinter '$').
    if (BodyLen > 0) and (L.S[BodyFrom] = '$') then
    begin
      NoteDirective(Copy(L.S, BodyFrom + 1, BodyLen - 1), D);
      ADir := True;
    end;
  end
  else
    Result := False;
end;

// Die Token der Unit als Spannen (ACount gueltig) samt Direktiven-Lage.
procedure Tokenize(const AText: string; ADelphiDefault: Boolean;
  out AToks: TFnLites; out ACount: Integer; out ADirs: TFnDirectives);
var
  L    : TFnLexer;
  Cnt  : Integer;
  T    : TFnLite;
  AfterDir : Boolean;
begin
  AToks := nil;
  ADirs := Default(TFnDirectives);
  ADirs.FpcDefined := not ADelphiDefault;
  L.S := AText;
  L.N := Length(AText);
  L.P := 1;
  L.Line := 1;
  L.LineFrom := 1;
  Cnt := 0;
  SetLength(AToks, 256);
  AfterDir := False;
  while L.P <= L.N do
  begin
    if LexTrivia(L, ADirs, AfterDir) then Continue;
    LexToken(L, T);
    // Ein Zweig, der nicht gelesen wird: Token verwerfen (die Direktiven-
    // Marke geht an das naechste gelesene Token).
    if not DirsActive(ADirs) then
    begin
      AfterDir := True;
      Continue;
    end;
    T.AfterDir := AfterDir;
    AfterDir := False;
    if Cnt = Length(AToks) then
      SetLength(AToks, Cnt * 2);
    AToks[Cnt] := T;
    Inc(Cnt);
  end;
  ACount := Cnt;
end;

// Gleiche Zeichen der Spannen (gross/klein unterschieden).
function SpanSame(const S: string; AFrom, ALen, BFrom, BLen: Integer): Boolean;
var
  i : Integer;
begin
  if ALen <> BLen then Exit(False);
  for i := 0 to ALen - 1 do
    if S[AFrom + i] <> S[BFrom + i] then
      Exit(False);
  Result := True;
end;

// Die Token-Folge des Scanners (Text/Low) aus den ersten ACount Spannen.
// Perf R1: Text/Low je VERSCHIEDENER Zeichenfolge einmal anlegen (Art,
// '&' und damit Text/Low haengen nur an den Zeichen) - die Token teilen
// die Zeichenketten statt je Token Copy + LowerCase.
function MaterializeAll(const AText: string; const ALites: TFnLites;
  ACount: Integer): TFnToks;
var
  Heads : array of Integer;
  EFrom, ELen, ENext : array of Integer;
  EText, ELow : array of string;
  NE, Size, i, k, H, E : Integer;
  Tmp : TFnTok;
begin
  SetLength(Result, ACount);
  Size := 256;
  while Size < ACount div 2 do
    Size := Size * 2;
  SetLength(Heads, Size);
  for i := 0 to Size - 1 do
    Heads[i] := -1;
  NE := 0;
  for i := 0 to ACount - 1 do
  begin
    H := ALites[i].Len and $FFFFF;
    for k := ALites[i].From to ALites[i].From + ALites[i].Len - 1 do
      H := ((H shl 5) + H + Ord(AText[k])) and $FFFFF;
    H := H and (Size - 1);
    E := Heads[H];
    while (E >= 0) and not SpanSame(AText, ALites[i].From, ALites[i].Len,
      EFrom[E], ELen[E]) do
      E := ENext[E];
    if E < 0 then
    begin
      if NE = Length(EFrom) then
      begin
        SetLength(EFrom, NE * 2 + 64);
        SetLength(ELen, NE * 2 + 64);
        SetLength(ENext, NE * 2 + 64);
        SetLength(EText, NE * 2 + 64);
        SetLength(ELow, NE * 2 + 64);
      end;
      Materialize(AText, ALites[i], Tmp);
      E := NE;
      EFrom[E] := ALites[i].From;
      ELen[E] := ALites[i].Len;
      EText[E] := Tmp.Text;
      ELow[E] := Tmp.Low;
      ENext[E] := Heads[H];
      Heads[H] := E;
      Inc(NE);
    end;
    Result[i].Kind := ALites[i].Kind;
    Result[i].Line := ALites[i].Line;
    Result[i].Col := ALites[i].Col;
    Result[i].AfterDir := ALites[i].AfterDir;
    Result[i].Text := EText[E];
    Result[i].Low := ELow[E];
  end;
end;

{ ---- Vorfilter (Perf R1) ---- }

// Jeder Treffer braucht eine Zuweisung 'Name :=' an den eigenen Namen im
// Rumpf (SCA204 direkt; SCA205 nur bei AUses.NA > 0, EmitHits): ein Wort am
// Anweisungsanfang bzw. hinter ':' (ClassifyUse fucAssign), dahinter ':=',
// gleich dem kurzen Namen eines Funktionskopfes (ParseName). CanHit prueft
// diese NOTWENDIGE Bedingung auf den Spannen, ohne Zeichenketten anzulegen;
// fehlt sie, kann der Scanner nichts melden, und Text/Low aller Token
// (Materialize) samt Lauf entfallen. Die Namensmenge ist eine OBERMENGE
// der kurzen Namen: alle Woerter hinter 'function' bis zum ersten Token auf
// Typargument-Tiefe 0, das nicht Wort, '.' oder '<' ist. Vergleich wie
// LowerCase (nur A..Z); Zeichen ueber 127 gelten untereinander als gleich
// (Obermenge, falls ein LowerCase sie je faltete).

const
  FN_NAME_BUCKETS = 1024;   // Zweierpotenz (Maske)
  FN_LAST_ASCII   = 127;

type
  TFnNameSet = record
    Heads : array[0..FN_NAME_BUCKETS - 1] of Integer;
    From  : array of Integer;
    Len   : array of Integer;
    Next  : array of Integer;
    Count : Integer;
  end;

function FoldChar(C: Char): Char;
begin
  if (C >= 'A') and (C <= 'Z') then
    Result := Char(Ord(C) + 32)
  else if Ord(C) > FN_LAST_ASCII then
    Result := #$80
  else
    Result := C;
end;

function SpanHash(const S: string; AFrom, ALen: Integer): Integer;
var
  i : Integer;
begin
  Result := ALen and $FFFFF;
  for i := AFrom to AFrom + ALen - 1 do
    Result := ((Result shl 5) + Result + Ord(FoldChar(S[i]))) and $FFFFF;
  Result := Result and (FN_NAME_BUCKETS - 1);
end;

function SpanEq(const S: string; AFrom, ALen, BFrom, BLen: Integer): Boolean;
var
  i : Integer;
begin
  if ALen <> BLen then Exit(False);
  for i := 0 to ALen - 1 do
    if FoldChar(S[AFrom + i]) <> FoldChar(S[BFrom + i]) then
      Exit(False);
  Result := True;
end;

// Wort ohne '&', klein geschrieben gleich ALow (ALow: klein, nur ASCII).
function LiteWordIs(const S: string; const T: TFnLite;
  const ALow: string): Boolean;
var
  i : Integer;
begin
  Result := False;
  if (T.Kind <> ftWord) or T.Esc or (T.Len <> Length(ALow)) then Exit;
  for i := 1 to T.Len do
    if FoldChar(S[T.From + i - 1]) <> ALow[i] then
      Exit;
  Result := True;
end;

function LiteSym1(const S: string; const T: TFnLite; C: Char): Boolean;
begin
  Result := (T.Kind = ftSym) and (T.Len = 1) and (S[T.From] = C);
end;

// Vor dem Namen einer Zuweisung (ClassifyUse fucAssign): STMT_START oder ':'.
function LiteStmtPrev(const S: string; const T: TFnLite): Boolean;
var
  i : Integer;
begin
  if T.Kind = ftSym then
    Exit(LiteSym1(S, T, ';') or LiteSym1(S, T, ':'));
  Result := False;
  if T.Kind <> ftWord then Exit;
  for i := 0 to High(STMT_START) do
    if LiteWordIs(S, T, STMT_START[i]) then
      Exit(True);
end;

procedure NameAdd(var ASet: TFnNameSet; const S: string; const T: TFnLite);
var
  F, L, H : Integer;
begin
  F := T.From;
  L := T.Len;
  if T.Esc then
  begin
    Inc(F);
    Dec(L);
  end;
  if ASet.Count = Length(ASet.From) then
  begin
    SetLength(ASet.From, ASet.Count * 2 + 16);
    SetLength(ASet.Len, ASet.Count * 2 + 16);
    SetLength(ASet.Next, ASet.Count * 2 + 16);
  end;
  H := SpanHash(S, F, L);
  ASet.From[ASet.Count] := F;
  ASet.Len[ASet.Count] := L;
  ASet.Next[ASet.Count] := ASet.Heads[H];
  ASet.Heads[H] := ASet.Count;
  Inc(ASet.Count);
end;

function NameHas(const ASet: TFnNameSet; const S: string;
  const T: TFnLite): Boolean;
var
  E : Integer;
begin
  E := ASet.Heads[SpanHash(S, T.From, T.Len)];
  while E >= 0 do
  begin
    if SpanEq(S, T.From, T.Len, ASet.From[E], ASet.Len[E]) then
      Exit(True);
    E := ASet.Next[E];
  end;
  Result := False;
end;

// Woerter des Kopfes hinter 'function' bei I (Obermenge des kurzen Namens).
procedure CollectHeadNames(var ASet: TFnNameSet; const S: string;
  const T: TFnLites; ACount, I: Integer);
var
  J, Depth : Integer;
begin
  Depth := 0;
  J := I + 1;
  while J < ACount do
  begin
    if T[J].Kind = ftWord then
      NameAdd(ASet, S, T[J])
    else if LiteSym1(S, T[J], '<') then
      Inc(Depth)
    else if LiteSym1(S, T[J], '>') and (Depth > 0) then
      Dec(Depth)
    else if (Depth = 0) and not LiteSym1(S, T[J], '.') then
      Break;
    Inc(J);
  end;
end;

// Bei I ein Wort ohne '&' hinter STMT_START bzw. ':' und vor ':='
// (I >= 1, I + 1 < Anzahl).
function IsAssignAt(const S: string; const T: TFnLites; I: Integer): Boolean;
begin
  Result := (T[I].Kind = ftWord) and not T[I].Esc and
    (T[I + 1].Kind = ftSym) and (T[I + 1].Len = 2) and
    (S[T[I + 1].From] = ':') and (S[T[I + 1].From + 1] = '=') and
    LiteStmtPrev(S, T[I - 1]);
end;

function CanHit(const S: string; const T: TFnLites; ACount: Integer): Boolean;
var
  NS : TFnNameSet;
  i  : Integer;
begin
  Result := False;
  NS.Count := 0;
  for i := 0 to FN_NAME_BUCKETS - 1 do
    NS.Heads[i] := -1;
  for i := 0 to ACount - 1 do
    if LiteWordIs(S, T[i], 'function') then
      CollectHeadNames(NS, S, T, ACount, i);
  if NS.Count = 0 then Exit;
  // Vor dem Namen steht mindestens das begin des Rumpfs (ab Index 1),
  // hinter ihm das Zuweisungssymbol.
  for i := 1 to ACount - 2 do
    if IsAssignAt(S, T, i) and NameHas(NS, S, T[i]) then
      Exit(True);
end;

function ModesFrom(const D: TFnDirectives;
  ADelphiDefault: Boolean): TFuncNameModes;
var
  i : Integer;
  AllDelphi, AllResult : Boolean;
begin
  if Length(D.Modes) = 0 then
  begin
    Result.AllowRead := ADelphiDefault;
    Result.AllowAssign := (ADelphiDefault or D.ResultSwitch) and
      not D.ResultOff;
    Exit;
  end;
  AllDelphi := True;
  AllResult := True;
  for i := 0 to High(D.Modes) do
  begin
    AllDelphi := AllDelphi and InList(D.Modes[i], ['delphi', 'delphiunicode']);
    AllResult := AllResult and
      InList(D.Modes[i], ['delphi', 'delphiunicode', 'objfpc']);
  end;
  Result.AllowRead := AllDelphi;
  Result.AllowAssign := (AllResult or D.ResultSwitch) and not D.ResultOff;
end;

{ ---- TFnTokens ---- }

constructor TFnTokens.Create(const AToks: TFnToks);
begin
  inherited Create;
  FToks := AToks;
  FN := Length(AToks);
end;

function TFnTokens.LowAt(I: Integer): string;
begin
  if (I < 0) or (I >= FN) then
    Result := ''
  else
    Result := FToks[I].Low;
end;

function TFnTokens.IsWord(I: Integer): Boolean;
begin
  Result := (I >= 0) and (I < FN) and (FToks[I].Kind = ftWord);
end;

function TFnTokens.IsSym(I: Integer; const S: string): Boolean;
begin
  Result := (I >= 0) and (I < FN) and (FToks[I].Kind = ftSym) and
    (FToks[I].Text = S);
end;

function TFnTokens.IsWordIn(I: Integer;
  const AList: array of string): Boolean;
begin
  Result := IsWord(I) and InList(FToks[I].Low, AList);
end;

// Index der passenden schliessenden Klammer zu der bei I (oder FN).
function TFnTokens.MatchClose(I: Integer; const AOpen,
  AClose: string): Integer;
var
  Depth : Integer;
begin
  Depth := 0;
  Result := I;
  while Result < FN do
  begin
    if IsSym(Result, AOpen) then
      Inc(Depth)
    else if IsSym(Result, AClose) then
    begin
      Dec(Depth);
      if Depth = 0 then Exit;
    end;
    Inc(Result);
  end;
end;

// Index des naechsten ASym auf Klammertiefe 0 ab I (oder FN).
function TFnTokens.SkipTo(I: Integer; const ASym: string): Integer;
var
  Depth : Integer;
begin
  Depth := 0;
  Result := I;
  while Result < FN do
  begin
    if IsSym(Result, '(') or IsSym(Result, '[') then
      Inc(Depth)
    else if IsSym(Result, ')') or IsSym(Result, ']') then
      Dec(Depth)
    else if (Depth <= 0) and IsSym(Result, ASym) then
      Exit;
    Inc(Result);
  end;
end;

// Das schliessende 'end' eines asm-Blocks, der bei I beginnt.
function TFnTokens.AsmEnd(I: Integer): Integer;
begin
  Result := I + 1;
  while (Result < FN) and (LowAt(Result) <> 'end') do
    Inc(Result);
end;

// Das passende 'end' zum Block, der bei I beginnt - begin, try, case oder
// asm (sonst das letzte Token).
function TFnTokens.BlockEnd(I: Integer): Integer;
var
  Depth : Integer;
begin
  Depth := 0;
  Result := I;
  while Result < FN do
  begin
    if InList(LowAt(Result), BLOCK_WORDS) then
      Inc(Depth)
    else if LowAt(Result) = 'asm' then
    begin
      Result := AsmEnd(Result);
      if Depth = 0 then Exit;
    end
    else if LowAt(Result) = 'end' then
    begin
      Dec(Depth);
      if Depth <= 0 then Exit;
    end;
    Inc(Result);
  end;
  Result := FN - 1;
end;

// Letztes Token der Anweisung ab I (hoechstens ALimit - 1): bis vor ein
// ';', 'end', 'until', 'finally' oder 'except' auf Tiefe 0. Ein 'else'
// gehoert dazu (ein if darin - so ist die Spanne eher zu gross als zu
// klein).
// Ein Token K der Anweisung: Schachtelung nachfuehren. True, wenn die
// Anweisung VOR K endet.
function TFnTokens.BlockStep(K: Integer; var S: TFnNesting): Boolean;
var
  W : string;
begin
  Result := False;
  W := '';
  if IsWord(K) then W := LowAt(K);
  if IsSym(K, '(') or IsSym(K, '[') then
    Inc(S.Depth)
  else if IsSym(K, ')') or IsSym(K, ']') then
    Dec(S.Depth)
  else if InList(W, ['begin', 'try', 'case', 'asm']) then
    Inc(S.Blk)
  else if W = 'repeat' then
    Inc(S.Rep)
  else if W = 'end' then
  begin
    Result := S.Blk = 0;
    Dec(S.Blk);
  end
  else if (W = 'until') and (S.Rep > 0) then
    Dec(S.Rep)
  else
    Result := (S.Depth <= 0) and (S.Blk = 0) and (S.Rep = 0) and
      (IsSym(K, ';') or InList(W, ['until', 'finally', 'except']));
end;

function TFnTokens.StatementEnd(I, ALimit: Integer): Integer;
var
  K : Integer;
  S : TFnNesting;
begin
  S := Default(TFnNesting);
  for K := I to ALimit - 1 do
    if BlockStep(K, S) then
      Exit(K - 1);
  Result := ALimit - 1;
end;

// Bei I '<' Typname {'.' Typname | ',' Typname} '>' - die Typargumente
// eines generischen Aufrufs. Ein Vergleich 'Name < X' endet nie auf '>'.
function TFnTokens.IsGenericArgs(I: Integer): Boolean;
var
  J : Integer;
begin
  Result := False;
  if not IsSym(I, '<') then Exit;
  J := I + 1;
  while IsWord(J) do
  begin
    Inc(J);
    if IsSym(J, '>') then Exit(True);
    if not (IsSym(J, '.') or IsSym(J, ',')) then Exit;
    Inc(J);
  end;
end;

// Beginnt bei I ein Typ mit Rumpf bis 'end'? record immer; class & Co.
// nur hinter '=' (bzw. '= packed'), nicht 'class of', nicht die
// Vorwaerts-/Kurzform 'class;' bzw. 'class(TBase);'.
function TFnTokens.IsTypeOpener(I: Integer): Boolean;
var
  P, J : Integer;
begin
  if IsWordIn(I, ['record']) then
    Exit(True);
  Result := False;
  if not IsWordIn(I, CLASSLIKE_WORDS) then Exit;
  P := I - 1;
  if IsWordIn(P, ['packed', 'bitpacked']) then
    Dec(P);
  J := I + 1;
  if not IsSym(P, '=') or (LowAt(J) = 'of') or IsSym(J, ';') then Exit;
  while IsWordIn(J, ['abstract', 'sealed']) do
    Inc(J);
  if IsSym(J, '(') then
    J := MatchClose(J, '(', ')') + 1
  else
    J := -1;
  Result := not IsSym(J, ';');
end;

// Index hinter dem 'end' des Typrumpfs, der bei I beginnt.
function TFnTokens.SkipTypeBody(I: Integer): Integer;
var
  Depth : Integer;
begin
  Depth := 1;
  Result := I + 1;
  while Result < FN do
  begin
    if IsTypeOpener(Result) then
      Inc(Depth)
    else if LowAt(Result) = 'end' then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit(Result + 1);
    end;
    Inc(Result);
  end;
end;

// Beginnt bei I der Kopf einer Routine (function/procedure/..., auch hinter
// 'class')? Kein Prozedurtyp ('= function', ': procedure', 'reference to',
// 'of object') und keine anonyme Methode (':= function', '(procedure').
function TFnTokens.IsRoutineStart(I: Integer): Boolean;
var
  P : Integer;
begin
  Result := False;
  if not IsWordIn(I, ROUTINE_WORDS) then Exit;
  P := I - 1;
  if LowAt(P) = 'class' then
    Dec(P);
  Result := (P < 0) or IsSym(P, ';') or IsSym(P, ']') or
    IsWordIn(P, ['implementation', 'generic']);
  // Anonyme Methode: hinter dem Wort folgt kein Name.
  if Result and (LowAt(I) <> 'operator') and not IsWord(I + 1) then
    Result := False;
end;

// Steht im Bereich [AFrom, ATo) der Name ALow als Wort?
function TFnTokens.NamesWord(AFrom, ATo: Integer; const ALow: string): Boolean;
var
  J : Integer;
begin
  for J := AFrom to ATo - 1 do
    if IsWord(J) and (LowAt(J) = ALow) then
      Exit(True);
  Result := False;
end;

{ ---- TFnScanner ---- }

constructor TFnScanner.Create(const AToks: TFnToks;
  const AModes: TFuncNameModes);
begin
  inherited Create(AToks);
  FModes := AModes;
  FHits := nil;
  FHitN := 0;
end;

// Name ab J: 'TFoo.Bar', auch mit Typparametern 'TFoo<T>.Bar<U>'. J steht
// danach hinter dem Namen.
function TFnScanner.ParseName(var J: Integer; var AHead: TFnHead): Boolean;
begin
  Result := IsWord(J);
  if not Result then Exit;
  AHead.Full := FToks[J].Text;
  AHead.Short := FToks[J].Text;
  Inc(J);
  if IsSym(J, '<') then
    J := MatchClose(J, '<', '>') + 1;
  while IsSym(J, '.') and IsWord(J + 1) do
  begin
    AHead.Short := FToks[J + 1].Text;
    AHead.Full := AHead.Full + '.' + AHead.Short;
    Inc(J, 2);
    if IsSym(J, '<') then
      J := MatchClose(J, '<', '>') + 1;
  end;
  AHead.ShortLow := LowerCase(AHead.Short);
end;

// Ende einer Gruppe: zaehlen, Default pruefen, neue Gruppe.
procedure CloseParamGroup(var G: TFnParamGroup; var AHead: TFnHead);
begin
  if G.HasName then
    Inc(AHead.ParamCount);
  if G.HasName and not G.HasDefault then
    AHead.AllDefault := False;
  G.HasName := False;
  G.HasDefault := False;
  G.InNames := True;
end;

// Ein Token J auf Tiefe 0 einer Gruppe (kein ';').
procedure TFnScanner.NoteParamWord(J: Integer; var G: TFnParamGroup;
  var AHead: TFnHead);
begin
  if IsSym(J, ':') then
    G.InNames := False
  else if IsSym(J, '=') then
    G.HasDefault := True
  else if G.InNames and IsWord(J) and
          not InList(LowAt(J), PARAM_MODIFIERS) then
  begin
    G.HasName := True;
    AHead.ParamShadow := AHead.ParamShadow or (LowAt(J) = AHead.ShortLow);
    AHead.ParamResult := AHead.ParamResult or (LowAt(J) = 'result');
  end;
end;

// Parameterliste zwischen AOpen '(' und AClose ')': Gruppen auf Tiefe 1,
// getrennt durch ';' - Namen bis ':', Default hinter '='.
procedure TFnScanner.ParseParams(AOpen, AClose: Integer; var AHead: TFnHead);
var
  J, Depth : Integer;
  G : TFnParamGroup;
begin
  Depth := 0;
  G := Default(TFnParamGroup);
  G.InNames := True;
  for J := AOpen + 1 to AClose - 1 do
    if IsSym(J, '(') or IsSym(J, '[') then
      Inc(Depth)
    else if IsSym(J, ')') or IsSym(J, ']') then
      Dec(Depth)
    else if (Depth = 0) and IsSym(J, ';') then
      CloseParamGroup(G, AHead)
    else if Depth = 0 then
      NoteParamWord(J, G, AHead);
  CloseParamGroup(G, AHead);
end;

// Kopf ab I (auf dem Routinen-Wort, ggf. hinter 'class'); I steht danach
// hinter dem ';' des Kopfes (ohne Direktiven). False: kein lesbarer Kopf.
function TFnScanner.ParseHead(var I: Integer; out AHead: TFnHead): Boolean;
var
  J, Close : Integer;
begin
  Result := False;
  AHead := Default(TFnHead);
  AHead.Keyword := LowAt(I);
  AHead.AllDefault := True;
  J := I + 1;
  if AHead.Keyword = 'operator' then
  begin
    // Operatoren melden wir nicht - nur den Kopf ueberspringen.
    J := SkipTo(J, ';');
    Result := J < FN;
    if Result then I := J + 1;
    Exit;
  end;
  if not ParseName(J, AHead) then Exit;
  if IsSym(J, '(') then
  begin
    Close := MatchClose(J, '(', ')');
    if Close >= FN then Exit;
    ParseParams(J, Close, AHead);
    J := Close + 1;
  end;
  if IsSym(J, ':') then
  begin
    AHead.HasResType := True;
    J := SkipTo(J, ';');
  end;
  if not IsSym(J, ';') then Exit;
  I := J + 1;
  Result := True;
end;

// Direktiven hinter dem Kopf bis zum Deklarationsteil. False: kein Rumpf
// (forward, external, Deklaration ohne Rumpf); J steht dann hinter ihr.
function TFnScanner.SkipDirectives(var J: Integer): Boolean;
begin
  Result := True;
  while J < FN do
  begin
    if IsWordIn(J, BODY_WORDS) then Exit;
    if IsWordIn(J, ['forward', 'external']) then
    begin
      J := SkipTo(J, ';') + 1;
      Exit(False);
    end;
    // Weder Direktive noch Rumpf: Deklaration ohne Rumpf.
    if not (IsWord(J) or IsSym(J, '[')) then
      Exit(False);
    J := SkipTo(J, ';') + 1;
  end;
end;

// Deklarationsteil ab J bis zum begin (J steht dann darauf). False: kein
// begin-Rumpf (asm-Rumpf, Unit-Abschnitt, Bruch der Struktur) - J steht
// dann hinter der Routine. Geschachtelte Routinen laufen rekursiv.
function TFnScanner.ParseDecls(var J: Integer; var AHead: TFnHead): Boolean;
begin
  Result := False;
  while (J < FN) and (LowAt(J) <> 'begin') do
  begin
    if LowAt(J) = 'asm' then
    begin
      J := AsmEnd(J) + 1;
      Exit;
    end;
    if InList(LowAt(J), UNIT_PART_WORDS) then
      Exit;
    if IsTypeOpener(J) then
      J := SkipTypeBody(J)
    else if IsRoutineStart(J) then
      J := ParseRoutine(J)
    else
    begin
      // Nur der EIGENE Deklarationsteil (geschachtelte Routinen sind oben
      // schon verbraucht - ihr Result ist ein anderes).
      AHead.DeclResult := AHead.DeclResult or IsWordIn(J, ['result']);
      Inc(J);
    end;
  end;
  Result := J < FN;
end;

// Routine ab I (auf dem Routinen-Wort). Liefert den Index hinter der
// Routine.
function TFnScanner.ParseRoutine(I: Integer): Integer;
var
  Head : TFnHead;
  J, DeclFrom, EndAt : Integer;
begin
  J := I;
  if not ParseHead(J, Head) then
    Exit(I + 1);
  if not SkipDirectives(J) then
    Exit(J);
  DeclFrom := J;
  if not ParseDecls(J, Head) then
    Exit(J);
  EndAt := BlockEnd(J);
  if (Head.Keyword = 'function') and (Head.ShortLow <> '') then
    ScanBody(Head, DeclFrom, J, EndAt);
  Result := EndAt + 1;
end;

// Spanne, in der der Name nicht beurteilt wird, ab I: eine with-Anweisung
// (das Objekt kann ein Element gleichen Namens haben) bzw. eine anonyme
// Methode bis zum end ihres Rumpfs (das Ergebnis der aeusseren Funktion
// ist dort nicht erreichbar). Liefert das letzte Token der Spanne.
function TFnScanner.MaskedEnd(I, ALimit: Integer): Integer;
var
  K : Integer;
begin
  K := I + 1;
  if LowAt(I) = 'with' then
  begin
    while (K < ALimit) and not IsWordIn(K, ['do']) do
      Inc(K);
    Inc(K);
    if K >= ALimit then
      Result := ALimit - 1
    else if InList(LowAt(K), ['begin', 'try', 'case']) then
      Result := BlockEnd(K)
    else if LowAt(K) = 'asm' then
      Result := AsmEnd(K)
    else
      Result := StatementEnd(K, ALimit);
  end
  else
  begin
    // anonyme Methode: Kopf und lokale Abschnitte bis zum begin
    while (K < ALimit) and not InList(LowAt(K), ['begin', 'asm']) do
      Inc(K);
    if K >= ALimit then
      Result := ALimit - 1
    else
      Result := BlockEnd(K);
  end;
  if Result >= ALimit then
    Result := ALimit - 1;
end;

// Inline-Deklaration 'var A, Name' bzw. 'const Name' ab J (auf var/const)?
function TFnScanner.InlineDeclares(J: Integer; const ALow: string): Boolean;
var
  K : Integer;
begin
  Result := False;
  if not InList(LowAt(J), ['var', 'const']) then Exit;
  K := J + 1;
  while IsWord(K) or IsSym(K, ',') do
  begin
    if LowAt(K) = ALow then Exit(True);
    Inc(K);
  end;
end;

procedure MarkSpan(var AMasked: TFnBools; AFrom, ATo: Integer);
var
  i : Integer;
begin
  for i := AFrom to ATo do
    AMasked[i] := True;
end;

// Spannen von with und anonymen Methoden ausblenden (AMasked, Index =
// Token - ABegin). False: ein inline 'var Name' verdeckt den Namen - die
// Routine wird nicht beurteilt.
function TFnScanner.MaskBody(const AHead: TFnHead; ABegin, AEnd: Integer;
  out AMasked: TFnBools): Boolean;
var
  J, K : Integer;
begin
  Result := True;
  SetLength(AMasked, AEnd - ABegin + 1);
  for J := 0 to High(AMasked) do
    AMasked[J] := False;
  J := ABegin + 1;
  while J < AEnd do
  begin
    if InlineDeclares(J, AHead.ShortLow) then
      Exit(False);
    if LowAt(J) = 'asm' then
      J := AsmEnd(J) + 1
    else if IsWordIn(J, ['with', 'function', 'procedure']) then
    begin
      K := MaskedEnd(J, AEnd);
      MarkSpan(AMasked, J - ABegin, K - ABegin);
      J := K + 1;
    end
    else
      Inc(J);
  end;
end;

// Vorkommen J als Aufruf oder fremder Bezeichner: hinter '.', '@',
// 'inherited' bzw. vor '(' oder Typargumenten. Setzt AUses.Deliberate bei
// bewusster Rekursion ('Name()', 'Name<T>', 'Self.Name').
function TFnScanner.IsCallForm(J: Integer; var AUses: TFnBodyUses): Boolean;
begin
  if IsSym(J - 1, '.') then
  begin
    AUses.Deliberate := AUses.Deliberate or (LowAt(J - 2) = 'self');
    Exit(True);
  end;
  // Adresse bzw. Vorfahr - kein Lesen des eigenen Ergebnisses.
  if IsSym(J - 1, '@') or IsSym(J - 1, '@@') or
     IsWordIn(J - 1, ['inherited']) then
    Exit(True);
  // 'Name()' bzw. 'GetView<NSView>' ruft (eine Ueberladung) auf.
  Result := IsSym(J + 1, '(') or IsGenericArgs(J + 1);
  AUses.Deliberate := AUses.Deliberate or Result;
end;

function TFnScanner.ClassifyUse(J, ABegin, AEnd: Integer;
  var AUses: TFnBodyUses): TFnUseClass;
var
  P, Nx : Integer;
  StmtStart : Boolean;
begin
  Result := fucNone;
  if IsCallForm(J, AUses) then Exit;
  P := J - 1;
  Nx := J + 1;
  StmtStart := (P = ABegin) or
    ((FToks[P].Kind <> ftString) and InList(LowAt(P), STMT_START));
  if IsSym(Nx, ':=') and (StmtStart or IsSym(P, ':')) then
    Exit(fucAssign);
  if IsSym(Nx, ':=') or ((Nx < FN) and (FToks[Nx].Kind = ftSym) and
     InList(FToks[Nx].Text, COMPOUND_ASSIGN)) then
    Exit;
  if StmtStart then
  begin
    // 'Name.X :=', 'Name[i] :=', 'Name^ :=' bzw. Anweisung darauf: kein
    // Fund (s. Kopf). 'Name;' ist eine Aufruf-Anweisung - bewusst.
    AUses.Deliberate := AUses.Deliberate or (Nx >= AEnd) or
      ((FToks[Nx].Kind in [ftSym, ftWord]) and InList(LowAt(Nx), STMT_END));
    Exit;
  end;
  // Argument einer eingebauten Routine mit var-Parameter: uebersetzt im
  // Delphi-Modus nicht. Eine Direktive direkt davor oder dahinter: zwei
  // IFDEF-Fassungen stehen aneinander ('{$IFDEF X}A{$ELSE}B{$ENDIF}.Name').
  if not (IsSym(P, '(') and InList(LowAt(P - 1), VAR_BUILTINS)) and
     not FToks[J].AfterDir and not ((Nx < FN) and FToks[Nx].AfterDir) then
    Result := fucRead;
end;

procedure AddAssign(J: Integer; var AUses: TFnBodyUses);
begin
  if AUses.NA = Length(AUses.Assigns) then
    SetLength(AUses.Assigns, AUses.NA * 2 + 4);
  AUses.Assigns[AUses.NA] := J;
  Inc(AUses.NA);
end;

// Lese-Stelle J. Nacktes Argument eines Aufrufs: vielleicht ein var-
// Parameter (dann uebersetzt die Unit unter Delphi nicht) - nicht
// bewiesen. Exit(Name) nimmt einen Wert.
procedure TFnScanner.AddRead(J: Integer; var AUses: TFnBodyUses);
begin
  if AUses.NR = Length(AUses.Reads) then
  begin
    SetLength(AUses.Reads, AUses.NR * 2 + 4);
    SetLength(AUses.ReadArg, AUses.NR * 2 + 4);
  end;
  AUses.Reads[AUses.NR] := J;
  AUses.ReadArg[AUses.NR] := (IsSym(J - 1, '(') or IsSym(J - 1, ',')) and
    (IsSym(J + 1, ')') or IsSym(J + 1, ',')) and
    not (IsSym(J - 1, '(') and (LowAt(J - 2) = 'exit'));
  Inc(AUses.NR);
end;

procedure TFnScanner.NoteUse(J, ABegin, AEnd: Integer;
  var AUses: TFnBodyUses);
var
  Use : TFnUseClass;
begin
  Use := ClassifyUse(J, ABegin, AEnd, AUses);
  if Use = fucAssign then
    AddAssign(J, AUses)
  else if Use = fucRead then
    AddRead(J, AUses);
end;

procedure TFnScanner.ScanBody(const AHead: TFnHead; ADeclFrom, ABegin,
  AEnd: Integer);
var
  J : Integer;
  Masked : TFnBools;
  U : TFnBodyUses;
begin
  // Ein Parameter oder der Deklarationsteil (samt geschachtelter Routinen)
  // verdeckt oder nennt den Namen: kein Urteil.
  if AHead.ParamShadow or NamesWord(ADeclFrom, ABegin, AHead.ShortLow) or
     not MaskBody(AHead, ABegin, AEnd, Masked) then
    Exit;
  U := Default(TFnBodyUses);
  J := ABegin + 1;
  while J < AEnd do
  begin
    if LowAt(J) = 'asm' then
      J := AsmEnd(J)
    else if IsWord(J) and (LowAt(J) = AHead.ShortLow) and
            not Masked[J - ABegin] then
      NoteUse(J, ABegin, AEnd, U);
    Inc(J);
  end;
  EmitHits(AHead, U);
end;

// Lesen nur, wenn die Funktion ihrem Namen selbst zuweist: wer Result
// schreibt, kennt den Unterschied - der nackte Name ist dann der Aufruf,
// den Delphi fuer eine parameterlose Rekursion so schreibt (Korpus: Parser
// 'Result := -ReadFactor', Wiederholung 'Result := AddKeyStroke',
// Funktionszeiger 'errno := Stub_errno').
procedure TFnScanner.EmitHits(const AHead: TFnHead; const AUses: TFnBodyUses);
var
  K : Integer;
  ReadOk : Boolean;
begin
  if FModes.AllowAssign and not (AHead.ParamResult or AHead.DeclResult) then
    for K := 0 to AUses.NA - 1 do
      AddHit(AHead, fnuAssign, AUses.Assigns[K], False);
  ReadOk := FModes.AllowRead and (AUses.NA > 0) and AHead.HasResType and
    ((AHead.ParamCount = 0) or AHead.AllDefault);
  if ReadOk then
    for K := 0 to AUses.NR - 1 do
      AddHit(AHead, fnuRead, AUses.Reads[K], (AHead.ParamCount = 0) and
        not AUses.Deliberate and not AUses.ReadArg[K]);
end;

procedure TFnScanner.AddHit(const AHead: TFnHead; AUse: TFuncNameUse;
  ATok: Integer; AProven: Boolean);
begin
  if FHitN = Length(FHits) then
    SetLength(FHits, FHitN * 2 + 8);
  FHits[FHitN].Use := AUse;
  FHits[FHitN].Line := FToks[ATok].Line;
  FHits[FHitN].Col := FToks[ATok].Col;
  FHits[FHitN].Written := FToks[ATok].Text;
  FHits[FHitN].Routine := AHead.Full;
  FHits[FHitN].Proven := AProven;
  Inc(FHitN);
end;

procedure TFnScanner.Run;
var
  I : Integer;
  InImpl : Boolean;
begin
  InImpl := LowAt(0) <> 'unit';
  I := 0;
  while I < FN do
  begin
    if IsWordIn(I, ['implementation']) then
      InImpl := True
    else if IsWordIn(I, ['interface']) and not IsSym(I - 1, '=') then
      InImpl := False
    else if IsTypeOpener(I) then
    begin
      I := SkipTypeBody(I);
      Continue;
    end
    else if InImpl and IsRoutineStart(I) then
    begin
      I := ParseRoutine(I);
      Continue;
    end;
    Inc(I);
  end;
end;

function TFnScanner.Hits: TFuncNameHits;
begin
  Result := Copy(FHits, 0, FHitN);
end;

{ ---- TFuncNameScan ---- }

class function TFuncNameScan.ScanText(const AText: string;
  ADelphiDefault: Boolean; AWantAssign: Boolean): TFuncNameHits;
var
  Lites : TFnLites;
  Cnt : Integer;
  Dirs : TFnDirectives;
  Modes : TFuncNameModes;
  S : TFnScanner;
begin
  Result := nil;
  Tokenize(AText, ADelphiDefault, Lites, Cnt, Dirs);
  Modes := ModesFrom(Dirs, ADelphiDefault);
  // Ohne SCA204 entfallen nur die fnuAssign-Treffer; das Lesen haengt an
  // AUses.NA (den Zuweisungen), nicht an AllowAssign (EmitHits).
  Modes.AllowAssign := Modes.AllowAssign and AWantAssign;
  if not Modes.AllowAssign and not Modes.AllowRead then Exit;
  if not CanHit(AText, Lites, Cnt) then Exit;
  S := TFnScanner.Create(MaterializeAll(AText, Lites, Cnt), Modes);
  try
    S.Run;
    Result := S.Hits;
  finally
    S.Free;
  end;
end;

class function TFuncNameScan.MessageOf(const AHit: TFuncNameHit): string;
begin
  if AHit.Use = fnuAssign then
    Result := FNR_ASSIGN_PREFIX + AHit.Written + FNR_ASSIGN_MID +
      FNR_ASSIGN_ADVICE
  else
    Result := Format(FNR_READ_FMT, [AHit.Written, AHit.Written]);
end;

end.

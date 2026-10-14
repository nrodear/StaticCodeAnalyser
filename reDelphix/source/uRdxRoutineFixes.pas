unit uRdxRoutineFixes;

// reDelphix - Quick-Fixes an ungenutzten Routinen, OHNE ToolsAPI und ohne
// Parser (Konzept_Editorhilfen_Recherche_2026-10-11, Charge H3
// "Aufraeumen", Teil b):
//   SCA164 UnusedRoutine: die freie Routine des implementation-Teils
//          loeschen - vom Kopf bis zum schliessenden 'end;' samt lokaler
//          Routinen, den direkt darueber stehenden Kommentar-, Doku- und
//          Attributzeilen, EINER Leerzeile und einer forward-Deklaration.
//   SCA147 UnusedPrivateMethod: die Deklaration im Klassenrumpf (samt
//          '///'-Doku) und die Implementierung (wie bei SCA164) loeschen.
// Beide bedeutungsgleich: was niemand ruft, fehlt danach niemandem. Den
// Beweis fuehrt der Planer NEU am Puffer, nicht der Detektor: der Name
// steht ausserhalb des geloeschten Bereichs nirgends als Code - Textsuche
// ueber die ganze Datei, also auch in inaktiven $IFDEF-Zweigen, die der
// Parser des Scans nicht sieht -, in keinem String-Literal (GetProcAddress,
// MethodAddress, RTTI, Skript-Registrierung per Name) und in keiner
// Direktive ($EXTERNALSYM). Kommentare zaehlen nicht als Verwendung.
//
// BAUSTEINE (Konzept Abschnitt 5; die Routinengrenzen tragen spaeter
// SCA121/SCA196/SCA097/SCA096, der Finder SCA106/SCA054):
//   ReadRoutine     Routinengrenzen fuer Rumpfe jeder Groesse: Kopf (auch
//                   'class' davor, qualifizierter und generischer Name) ->
//                   Direktiven, auch auf Folgezeilen -> lokale Abschnitte
//                   (var/const/type/label ...) und lokale Routinen
//                   (rekursiv) -> begin bzw. asm -> passendes end -> ';'.
//                   forward/external: ohne Rumpf. (uRdxRaiseFixes.
//                   MethodBodyOn kennt nur leere Rumpfe ohne lokale
//                   Routinen.)
//   FindMethodDecls / FindMethodImpls
//                   Decl/Impl-Finder: die Deklarationen einer Methode auf
//                   Tiefe 1 im Rumpf ihrer Klasse (auch verschachtelte und
//                   generische Klassen) und ihre Implementierungskoepfe im
//                   implementation-Teil ('TOuter.TInner.Bar', 'TFoo<T>.Bar',
//                   'class procedure'). Mehr als ein Treffer heisst Overload
//                   oder mehrdeutig - die Aufrufer lehnen dann ab.
//
// WAS MITGEHT: ueber einer Implementierung die direkt anhaengenden Zeilen
// nur aus Kommentar - sie beschreiben die Routine; bliebe ein '// default
// is case-sensitive' stehen, laege er nach dem Loeschen ueber der naechsten
// Routine (Korpus: 24 '//'- und 72 Block-Kommentare direkt ueber
// SCA164-Koepfen, meist Trenner '(*---*)' und Beschreibungen). Ein
// Abschnittsmarker '{ TFoo }' bleibt stehen (er gehoert zur Gruppe). Ueber
// einer Deklaration im Klassenrumpf nur '///' - dort steht oft ein
// Gruppenkommentar ('{ Private declarations }').
//
// GRENZEN: Programme und Bibliotheken (.dpr) meldet SCA164 nicht - der
// Detektor sieht nur Kinder des implementation-Knotens; der Planer verlangt
// deshalb ein 'implementation' vor dem Kopf. Eine leere private-Sektion,
// die nach SCA147 uebrig bleibt, meldet danach SCA087 (eigene Hilfe).
//
// GRUNDSATZ wie in uRdxSimpleFixes: lieber keine Hilfe als eine falsche.

interface

uses
  uRdxBufferMath, uRdxCodeMap;

type
  // Grenzen einer Routine (ReadRoutine) bzw. einer Methodendeklaration im
  // Klassenrumpf (dann ohne Rumpf: Body.Low = '').
  TRdxRoutine = record
    Head       : TRdxToken;        // 'class' davor oder das Kopfwort
    Keyword    : TRdxToken;        // procedure, function, constructor ...
    NameTok    : TRdxToken;        // letztes Glied des Namens
    Name       : string;           // wie im Kopf, Glieder mit '.', ohne <..>
    Parts      : TArray<string>;   // die Glieder, klein
    HeaderEnd  : TRdxToken;        // das ';' hinter dem Kopf
    Directives : TArray<string>;   // klein, in Reihenfolge
    Body       : TRdxToken;        // begin bzw. asm; Low = '' ohne Rumpf
    EndTok     : TRdxToken;        // das end des Rumpfs
    Last       : TRdxToken;        // das letzte ';' der Routine
  end;

  // Ergebnis der Planer: alle Ersetzungen (EIN Undo-Schritt) und der Name
  // fuer den Menuetext - schon aus der Meldung, auch wenn abgelehnt wird.
  TRdxRoutinePlan = record
    Edits : TArray<TRdxEdit>;
    Name  : string;
  end;

  // Die Form beider Planer (uRdxFixTable: RoutineFix).
  TRdxRoutinePlanner = function(AMap: TRdxCodeMap; ALine: Integer;
    const AMessage: string; out APlan: TRdxRoutinePlan;
    out AReason: string): Boolean;

  TRdxRoutineFixes = class
  public
    // Baustein Routinengrenzen: die Routine, deren Kopf an AHead beginnt
    // ('class' oder das Kopfwort; ein Kopfwort mit 'class' davor wird auf
    // 'class' gezogen). '' oder der Grund, warum die Grenzen nicht sicher
    // sind (Kopf ohne ';', lokaler Klassentyp, kein end, hinter dem ';'
    // beginnt nichts Neues ...).
    class function ReadRoutine(AMap: TRdxCodeMap; const AHead: TRdxToken;
      out ARoutine: TRdxRoutine): string; static;

    // Baustein Decl/Impl-Finder: die Koepfe ('class' bzw. Kopfwort) der
    // Methode AMethod auf Tiefe 1 im Rumpf jeder Klasse, die wie das letzte
    // Glied von AClassPath heisst.
    class function FindMethodDecls(AMap: TRdxCodeMap;
      const AClassPath, AMethod: string): TArray<TRdxToken>; static;
    // ... und ihre Implementierungskoepfe hinter 'implementation': die
    // letzten Glieder des Namens sind AClassPath + AMethod
    // ('TOuter.TInner.Bar' passt zu 'TInner' und zu 'TOuter.TInner').
    class function FindMethodImpls(AMap: TRdxCodeMap;
      const AClassPath, AMethod: string): TArray<TRdxToken>; static;

    // SCA164: die Routine der Meldung 'Top-level routine X appears unused
    // ...' mit Kopf auf ALine loeschen (s. Kopf der Unit). Keine Hilfe fuer
    // Methoden, Koepfe vor 'implementation', export/public/alias/external/
    // forward/interrupt-Direktiven, Overloads, jede Verwendung ausserhalb
    // der Routine, den Namen in einem String-Literal oder einer Direktive,
    // {$L}/{$LINK} in der Datei, {$I} im implementation-Teil, eine
    // Direktive im Bereich ausser ausgeglichenem $IF../$ENDIF bzw. $REGION,
    // zwei Routinen auf einer Zeile.
    class function UnusedRoutine(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxRoutinePlan;
      out AReason: string): Boolean; static;

    // SCA147: die Methode der Meldung 'Private method TFoo.X appears unused
    // ...' (Deklaration auf ALine) loeschen. Keine Hilfe ausserhalb von
    // private/strict private, bei virtual/dynamic/override/abstract/
    // reintroduce/message/overload/dispid, Konstruktor/Destruktor/Operator,
    // Attribut an Klasse oder Methode, {$RTTI} in der Datei, {$I} im
    // Klassenrumpf oder im implementation-Teil, einem Interface der Klasse
    // aus einer anderen Unit, mehr als einer Deklaration oder
    // Implementierung, keiner Implementierung in der Datei, jeder weiteren
    // Verwendung (auch Property-Accessor, String-Literal, Direktive) und
    // einer Direktive im Bereich wie bei SCA164. Die Formdatei prueft der
    // Aufrufer (FormNamesMethod).
    class function UnusedPrivateMethod(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxRoutinePlan;
      out AReason: string): Boolean; static;

    // SCA147: nennt die Formdatei (.dfm/.fmx/.lfm-Text) AName als Wort -
    // etwa als Ereignis 'OnClick = AName'? Den Text liest der Aufrufer.
    class function FormNamesMethod(const AFormText, AName: string): Boolean;
      static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxStructFixes;   // RangeText

const
  SPAN_164 = 'sca164';
  SPAN_147 = 'sca147';
  KW_CLASS = 'class';
  KW_END   = 'end';
  KW_SEMI  = ';';
  ROUTINE_WORDS: array[0..4] of string = ('procedure', 'function',
    'constructor', 'destructor', 'operator');
  // Davor beginnt ein Routinenwort KEINEN Kopf: Typ einer Variablen oder
  // eines Parameters, Typdeklaration, anonyme Methode, 'reference to',
  // 'array of procedure'.
  NOT_HEAD_AFTER: array[0..7] of string = (':', '=', 'to', '(', ',', ':=',
    'of', '[');
  // Direktiven hinter einem Routinenkopf im implementation-Teil (Delphi und
  // FPC). Ein anderes Wort beginnt den Deklarationsteil - ist es dort
  // fremd, lehnt ReadRoutine ab.
  ROUTINE_DIRECTIVES: array[0..37] of string = ('overload', 'inline',
    'assembler', 'register', 'pascal', 'cdecl', 'stdcall', 'safecall',
    'winapi', 'varargs', 'forward', 'external', 'export', 'far', 'near',
    'local', 'deprecated', 'platform', 'experimental', 'library',
    'noreturn', 'static', 'unsafe', 'public', 'alias', 'nostackframe',
    'interrupt', 'iocheck', 'compilerproc', 'rtlproc', 'internproc',
    'mwpascal', 'cppdecl', 'oldfpccall', 'softfloat', 'hardfloat',
    'vectorcall', 'weakexternal');
  // Ohne Rumpf: der Kopf allein ist die Deklaration.
  BODYLESS_DIRECTIVES: array[0..1] of string = ('forward', 'external');
  // SCA164: damit ist die Routine von aussen erreichbar (Linker-Name,
  // Export, Compiler/RTL, Interrupt) oder ohne Rumpf.
  REACHABLE_DIRECTIVES: array[0..9] of string = ('export', 'public',
    'alias', 'external', 'forward', 'interrupt', 'compilerproc', 'rtlproc',
    'internproc', 'weakexternal');
  // Direktiven einer Methodendeklaration im Klassenrumpf. 'public' fehlt
  // mit Absicht: dort beginnt es einen Abschnitt.
  METHOD_DIRECTIVES: array[0..23] of string = ('virtual', 'dynamic',
    'abstract', 'overload', 'override', 'reintroduce', 'stdcall', 'cdecl',
    'register', 'pascal', 'safecall', 'inline', 'static', 'message',
    'deprecated', 'platform', 'experimental', 'final', 'winapi',
    'assembler', 'varargs', 'dispid', 'external', 'unsafe');
  // SCA147: damit erreicht die Methode ein Vorfahr, ein Nachfahr, die
  // Nachrichten-Verteilung oder ein Overload-Geschwister - ohne Namen.
  DISPATCH_DIRECTIVES: array[0..9] of string = ('virtual', 'dynamic',
    'abstract', 'override', 'reintroduce', 'message', 'overload', 'dispid',
    'external', 'final');
  // Hier endet ein Kopf nie regulaer - ihm fehlt das ';'.
  HEAD_STOPS: array[0..8] of string = ('begin', 'asm', 'var', 'const',
    'type', 'procedure', 'function', KW_END, 'implementation');
  // Kein Inhalt eines Deklarationsteils oder Rumpfs - die Grenzen waeren
  // falsch gelesen.
  UNIT_STOPS: array[0..7] of string = ('implementation', 'initialization',
    'finalization', 'interface', 'unit', 'program', 'exports', 'uses');
  // Typen mit eigenem end, die ein Deklarationsteil nicht haben darf und
  // die ein Klassenrumpf schachtelt.
  CLASS_LIKE: array[0..3] of string = (KW_CLASS, 'object', 'interface',
    'dispinterface');
  // Damit beginnt der Rumpf einer Routine.
  BODY_WORDS: array[0..1] of string = ('begin', 'asm');
  // Was hinter einer Routine folgen darf - sonst sind ihre Grenzen falsch
  // gelesen (Dateiende zaehlt auch).
  FOLLOWERS: array[0..17] of string = ('procedure', 'function',
    'constructor', 'destructor', 'operator', KW_CLASS, 'var', 'const',
    'type', 'label', 'resourcestring', 'threadvar', 'exports',
    'initialization', 'finalization', 'begin', 'asm', KW_END);
  VISIBILITY_WORDS: array[0..4] of string = ('private', 'protected',
    'public', 'published', 'automated');
  PRIVATE_SECTIONS: array[0..1] of string = ('private', 'strict private');
  // Hinter diesen Woertern ist ein Wort ein Feld, kein Abschnitt bzw.
  // keine Direktive ('Public: Boolean', 'Platform: string').
  FIELD_MARKS: array[0..2] of string = (':', ',', '=');
  NO_SPECIAL: array[0..2] of string = ('constructor', 'destructor',
    'operator');
  CLASS_MODIFIERS: array[0..1] of string = ('abstract', 'sealed');
  COND_OPEN: array[0..3] of string = ('if', 'ifdef', 'ifndef', 'ifopt');
  COND_MID: array[0..1] of string = ('else', 'elseif');
  COND_CLOSE: array[0..1] of string = ('endif', 'ifend');
  LINK_WORDS: array[0..1] of string = ('l', 'link');
  INCLUDE_WORDS: array[0..1] of string = ('i', 'include');
  // Property-Teile, hinter denen ein Methodenname Accessor ist.
  ACCESSOR_WORDS: array[0..4] of string = ('read', 'write', 'stored', 'add',
    'remove');
  KEY_ROUTINE = 'Top-level routine ';
  KEY_METHOD  = 'Private method ';
  KEY_UNUSED  = ' appears unused';
  DOC_PREFIX  = '///';
  STACK_COND   = 'c';
  STACK_REGION = 'r';
  MAX_NESTING    = 8;     // Tiefe lokaler Routinen in Routinen
  MAX_NAME_PARTS = 8;     // Glieder eines qualifizierten Namens
  MAX_BACK       = 400;   // so weit sucht InExports rueckwaerts
  R_IMPL_INCLUDE = '{$I}-Include im implementation-Teil (Zeile %d) - dort '
    + 'kann ein Aufrufer stehen, den die Hilfe nicht sieht';
  R_LAST_LINE = 'die Routine endet auf der letzten Zeile der Datei';

type
  // Ganze Zeilen Top..Bottom - ein Loeschbereich.
  TRdxLines = record
    Top    : Integer;
    Bottom : Integer;
  end;

  // Was ueber einem Kopf mitgeht: '///'-Doku und Attributzeilen
  // (Klassenrumpf, forward) oder dazu jede Zeile nur aus Kommentar
  // (Implementierung).
  TRdxAbove = (abDocOnly, abComments);

  // Ein Lauf ueber alle Code-Token: 'implementation' und jedes Vorkommen
  // des gesuchten Namens als Wort.
  TRdxNameScan = record
    Impl : TRdxToken;
    Hits : TArray<TRdxToken>;
  end;

  // Was die Zeilen-Durchsicht fand (FileFacts): je die erste Zeile, 0 =
  // keine.
  TRdxFileFacts = record
    LinksObject   : Integer;   // {$L datei} / {$LINK datei}
    ImplInclude   : Integer;   // {$I datei} hinter implementation
    Rtti          : Integer;   // {$RTTI ...}
    NameLiteral   : Integer;   // String-Literal mit dem Namen als Wort
    NameDirective : Integer;   // Direktive mit dem Namen als Wort
  end;

  // Zustand der Zeilen-Durchsicht. Own: die geloeschten Bereiche - ein
  // Literal oder eine Direktive dort zaehlt nicht.
  TRdxFactScan = record
    LowName  : string;
    ImplLine : Integer;
    Own      : array[0..1] of TRdxLines;
    Facts    : TRdxFileFacts;
    function InOwn(ALine: Integer): Boolean;
    procedure Directive(AMap: TRdxCodeMap; ALine, ACol: Integer);
    procedure Literal(AMap: TRdxCodeMap; ALine, ACol, AEnd: Integer);
  end;

  // Tiefe und Sichtbarkeit beim Lauf durch einen Klassenrumpf (Tiefe 1 =
  // die Member der Klasse; geschachtelte Typen und records zaehlen hoch).
  TRdxClassScan = record
    Depth : Integer;
    Vis   : string;      // Sichtbarkeit auf Tiefe 1, '' = Vorgabe
    procedure Step(AMap: TRdxCodeMap; const T, APrev: TRdxToken);
  end;

  // Der Deklarationsteil einer Routine (ReadDeclPart): offene record-Typen
  // und die Schachtelung der Routine.
  TRdxDeclScan = record
    Rec    : Integer;
    Depth  : Integer;
    Reason : string;
    function Step(AMap: TRdxCodeMap; var T: TRdxToken;
      const APrev: TRdxToken): TRdxStep;
  end;

  // Der Klassenkopf um eine Deklaration (EnclosingClass).
  TRdxClassHead = record
    NameTok  : TRdxToken;
    ClassTok : TRdxToken;
    Vis      : string;
  end;

{ ---- Token und Texte ---- }

function SameTok(const A, B: TRdxToken): Boolean;
begin
  Result := (A.Line = B.Line) and (A.Col = B.Col);
end;

// Steht A vor B?
function TokBefore(const A, B: TRdxToken): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Col < B.Col));
end;

function TokInRange(const T, AFirst, ALast: TRdxToken): Boolean;
begin
  Result := not TokBefore(T, AFirst) and not TokBefore(ALast, T);
end;

function TokText(AMap: TRdxCodeMap; const T: TRdxToken): string;
begin
  Result := Copy(AMap.Raw(T.Line), T.Col, T.Len);
end;

procedure AddToken(var AList: TArray<TRdxToken>; const T: TRdxToken);
begin
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := T;
end;

procedure AddText(var AList: TArray<string>; const S: string);
begin
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := S;
end;

procedure AddEdit(var AList: TArray<TRdxEdit>; const AEdit: TRdxEdit);
begin
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := AEdit;
end;

// Glieder zu 'A.B.C' (TStringBuilder - keine Verkettung in der Schleife).
function JoinDotted(const AParts: TArray<string>): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(AParts) do
    begin
      if i > 0 then
        SB.Append('.');
      SB.Append(AParts[i]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// 'TOuter.TInner' -> ['touter', 'tinner'].
function SplitDotted(const S: string): TArray<string>;
var
  Rest : string;
  P    : Integer;
begin
  Result := nil;
  Rest := LowerCase(S);
  P := Pos('.', Rest);
  while P > 0 do
  begin
    AddText(Result, Copy(Rest, 1, P - 1));
    Rest := Copy(Rest, P + 1, MaxInt);
    P := Pos('.', Rest);
  end;
  AddText(Result, Rest);
end;

// Kommt ALowName als ganzes Wort in ALowText vor (beides klein)?
function HasWord(const ALowText, ALowName: string): Boolean;
var
  P, E : Integer;
begin
  Result := False;
  if ALowName = '' then Exit;
  P := Pos(ALowName, ALowText);
  while P > 0 do
  begin
    E := P + Length(ALowName);
    if ((P = 1) or not IsIdentChar(ALowText[P - 1]))
       and ((E > Length(ALowText)) or not IsIdentChar(ALowText[E])) then
      Exit(True);
    P := Pos(ALowName, ALowText, P + 1);
  end;
end;

function HasDirective(const R: TRdxRoutine; const AWords: array of string;
  out AWord: string): Boolean;
var
  D : string;
begin
  Result := False;
  AWord := '';
  for D in R.Directives do
    if InList(D, AWords) then
    begin
      AWord := D;
      Exit(True);
    end;
end;

// Das naechste ';' auf Klammertiefe 0 ab AFrom (einschliesslich); Low = ''
// sonst.
function SemicolonAt0(AMap: TRdxCodeMap; const AFrom: TRdxToken): TRdxToken;
begin
  Result := AFrom;
  while (Result.Low <> '') and (Result.Low <> KW_SEMI) do
    if (Result.Low = '(') or (Result.Low = '[') then
      Result := AfterClose(AMap, Result)
    else
      Result := After(AMap, Result);
end;

// Beginnt an T ein Routinenkopf? Ein Routinenwort als Schluesselwort, davor
// nichts aus NOT_HEAD_AFTER (Typ, anonyme Methode).
function IsHeadAt(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
var
  P : TRdxToken;
begin
  if not InList(T.Low, ROUTINE_WORDS) then Exit(False);
  P := Before(AMap, T);
  Result := IsKeywordAfter(T, P) and not InList(P.Low, NOT_HEAD_AFTER);
end;

// Ein Kopf, dessen Name mit AArg (klein) beginnt - fuer OneTokenOnLine.
function IsHeadNamed(AMap: TRdxCodeMap; const T: TRdxToken;
  const AArg: string): Boolean;
begin
  Result := IsHeadAt(AMap, T) and (After(AMap, T).Low = AArg);
end;

// Der Anfang des Kopfs zum Routinenwort T: 'class' davor oder T selbst.
// Nicht das 'class' eines Klassenkopfs ('TFoo = class' direkt vor dem
// ersten Member).
function HeadStart(AMap: TRdxCodeMap; const T: TRdxToken): TRdxToken;
begin
  Result := Before(AMap, T);
  if (Result.Low <> KW_CLASS)
     or InList(Before(AMap, Result).Low, ['=', 'packed']) then
    Result := T;
end;

{ ---- Baustein Routinengrenzen ---- }

function ReadRoutineAt(AMap: TRdxCodeMap; const AHead: TRdxToken;
  ADepth: Integer; out R: TRdxRoutine): string; forward;

// Der Name hinter dem Kopfwort: Glieder mit '.', Typparameter '<..>'
// uebersprungen; AAfter ist das Token dahinter. '' oder der Grund.
function ReadName(AMap: TRdxCodeMap; var R: TRdxRoutine;
  out AAfter: TRdxToken): string;
var
  T   : TRdxToken;
  Raw : TArray<string>;
  n   : Integer;
begin
  AAfter := Default(TRdxToken);
  Raw := nil;
  T := After(AMap, R.Keyword);
  for n := 1 to MAX_NAME_PARTS do
  begin
    if not T.IsWord then
      Exit(Format('kein Name hinter "%s"', [R.Keyword.Low]));
    R.NameTok := T;
    AddText(R.Parts, T.Low);
    AddText(Raw, TokText(AMap, T));
    T := After(AMap, T);
    if T.Low = '<' then
      T := AfterClose(AMap, T);
    if T.Low <> '.' then
    begin
      R.Name := JoinDotted(Raw);
      AAfter := T;
      Exit('');
    end;
    T := After(AMap, T);
  end;
  Result := 'Name mit zu vielen Gliedern';
end;

// Ab AFrom (hinter dem Namen) Typparameter, Parameter und Rueckgabe bis zum
// ';' des Kopfs. '' oder der Grund.
function HeaderEndFrom(AMap: TRdxCodeMap; const AFrom: TRdxToken;
  out AEnd: TRdxToken): string;
var
  T, P : TRdxToken;
begin
  AEnd := Default(TRdxToken);
  T := AFrom;
  P := Before(AMap, AFrom);
  while (T.Low <> '') and (T.Low <> KW_SEMI) do
  begin
    if IsKeywordAfter(T, P) and InList(T.Low, HEAD_STOPS) then
      Break;
    P := T;
    if InList(T.Low, ['(', '[', '<']) then
      T := AfterClose(AMap, T)
    else
      T := After(AMap, T);
  end;
  if T.Low <> KW_SEMI then
    Exit('Ende des Kopfs nicht gefunden');
  AEnd := T;
  Result := '';
end;

// Ein Wort aus AList an T ist eine Direktive - ausser ein ':' ',' '='
// folgt (ein Feld 'Platform: string' hinter der Deklaration).
function IsDirectiveAt(AMap: TRdxCodeMap; const T: TRdxToken;
  const AList: array of string): Boolean;
begin
  Result := T.IsWord and InList(T.Low, AList)
    and not InList(After(AMap, T).Low, FIELD_MARKS);
end;

// Die Direktiven hinter dem Kopf ('overload; inline;', 'external ''x''
// name ''y'';'), auch auf Folgezeilen: je ein Wort aus AList bis zu seinem
// ';'. R.Last wird das letzte ';', AAfter das Token dahinter.
function ReadDirectives(AMap: TRdxCodeMap; var R: TRdxRoutine;
  const AList: array of string; out AAfter: TRdxToken): string;
var
  T, S : TRdxToken;
begin
  Result := '';
  R.Last := R.HeaderEnd;
  T := After(AMap, R.HeaderEnd);
  while IsDirectiveAt(AMap, T, AList) do
  begin
    AddText(R.Directives, T.Low);
    S := SemicolonAt0(AMap, T);
    if S.Low = '' then
      Exit(Format('Direktive "%s" ohne ";"', [T.Low]));
    R.Last := S;
    T := After(AMap, S);
  end;
  AAfter := T;
end;

// Eine lokale Routine ab T (Kopfwort hinter ';'): T wird ihr letztes ';'.
// '' oder der Grund.
function SkipLocalRoutine(AMap: TRdxCodeMap; var T: TRdxToken;
  ADepth: Integer): string;
var
  Sub : TRdxRoutine;
begin
  if ADepth >= MAX_NESTING then
    Exit('lokale Routinen zu tief verschachtelt');
  Result := ReadRoutineAt(AMap, T, ADepth + 1, Sub);
  if Result <> '' then
    Exit('lokale Routine ' + Sub.Name + ': ' + Result);
  T := Sub.Last;
end;

// Ein Schluesselwort im Deklarationsteil ausserhalb von records und
// lokalen Routinen: rsFound am Rumpf, rsStop mit Grund.
function DeclWordStep(const T, APrev: TRdxToken; out AReason: string): TRdxStep;
begin
  AReason := '';
  Result := rsGoOn;
  if InList(T.Low, BODY_WORDS) then
    Result := rsFound
  else if InList(T.Low, CLASS_LIKE) and (APrev.Low = '=') then
    AReason := 'lokaler Klassen- oder Objekttyp - Grenzen nicht sicher'
  else if (T.Low = KW_END) or InList(T.Low, UNIT_STOPS) then
    AReason := Format('"%s" im Deklarationsteil - Ende der Routine nicht '
      + 'sicher', [T.Low]);
  if AReason <> '' then
    Result := rsStop;
end;

{ TRdxDeclScan }

// Ein Schluesselwort des Deklarationsteils. 'case' im record hat kein
// eigenes end; ein Routinenwort hinter ';' (nicht hinter ':' oder '=' wie
// in 'P: procedure;') ist eine lokale Routine.
function TRdxDeclScan.Step(AMap: TRdxCodeMap; var T: TRdxToken;
  const APrev: TRdxToken): TRdxStep;
begin
  Result := rsGoOn;
  if T.Low = 'record' then
    Inc(Rec)
  else if Rec > 0 then
    Dec(Rec, Ord(T.Low = KW_END))
  else if InList(T.Low, ROUTINE_WORDS) and (APrev.Low = KW_SEMI) then
  begin
    Reason := SkipLocalRoutine(AMap, T, Depth);
    if Reason <> '' then
      Result := rsStop;
  end
  else
    Result := DeclWordStep(T, APrev, Reason);
end;

// Der Deklarationsteil ab AFrom (hinter Kopf und Direktiven): lokale
// Abschnitte und Routinen bis zum begin bzw. asm des Rumpfs (R.Body).
function ReadDeclPart(AMap: TRdxCodeMap; var R: TRdxRoutine;
  const AFrom: TRdxToken; ADepth: Integer): string;
var
  T, P : TRdxToken;
  Scan : TRdxDeclScan;
  Step : TRdxStep;
begin
  Scan := Default(TRdxDeclScan);
  Scan.Depth := ADepth;
  T := AFrom;
  P := R.Last;
  while T.Low <> '' do
  begin
    Step := rsGoOn;
    if IsKeywordAfter(T, P) then
      Step := Scan.Step(AMap, T, P);
    if Step = rsFound then
    begin
      R.Body := T;
      Exit('');
    end;
    if Step = rsStop then
      Exit(Scan.Reason);
    P := T;
    T := After(AMap, T);
  end;
  Result := 'kein Rumpf zur Routine gefunden';
end;

// Haken der end-Bilanz im Rumpf: Abschnittswoerter der Unit und ein
// Routinenkopf hinter ';' heissen, das passende end wurde verfehlt.
function BodyHook(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  ADepth: Integer): string;
begin
  Result := '';
  if not IsKeywordAfter(T, APrev) then Exit;
  if InList(T.Low, UNIT_STOPS) then
    Result := Format('"%s" im Rumpf - Ende der Routine nicht gefunden',
      [T.Low])
  else if (APrev.Low = KW_SEMI)
     and (InList(T.Low, ROUTINE_WORDS) or (T.Low = KW_CLASS)) then
    Result := 'Routinenkopf im Rumpf - Ende der Routine nicht sicher';
end;

// Das end eines asm-Rumpfs: das erste end als Schluesselwort ('@@End' und
// '@End' sind Marken).
function AsmEnd(AMap: TRdxCodeMap; const AAsm: TRdxToken;
  out AEnd: TRdxToken): string;
var
  T, P : TRdxToken;
begin
  AEnd := Default(TRdxToken);
  P := AAsm;
  T := After(AMap, AAsm);
  while (T.Low <> '') and not (IsKeywordAfter(T, P) and (T.Low = KW_END)) do
  begin
    P := T;
    T := After(AMap, T);
  end;
  if T.Low = '' then
    Exit('kein end zum asm-Rumpf');
  AEnd := T;
  Result := '';
end;

// Rumpf ab R.Body bis zum passenden end und dem ';' dahinter (R.Last).
function ReadBody(AMap: TRdxCodeMap; var R: TRdxRoutine): string;
var
  Last, S : TRdxToken;
begin
  if R.Body.Low = 'asm' then
    Result := AsmEnd(AMap, R.Body, R.EndTok)
  else
    Result := BlockEnd(AMap, R.Body, BodyHook, R.EndTok, Last);
  if (Result = '') and (R.EndTok.Low = '') then
    Result := 'kein end zum Rumpf gefunden';
  if Result <> '' then Exit;
  S := After(AMap, R.EndTok);
  // FPC: 'end [''eax''];' hinter einem asm-Rumpf.
  if S.Low = '[' then
    S := AfterClose(AMap, S);
  if S.Low <> KW_SEMI then
    Exit('hinter dem end des Rumpfs fehlt ";"');
  R.Last := S;
end;

// Beginnt hinter ALast etwas, das hinter einer Routine stehen darf?
function FollowsRoutine(AMap: TRdxCodeMap; const ALast: TRdxToken): Boolean;
var
  N : TRdxToken;
begin
  N := After(AMap, ALast);
  Result := (N.Low = '') or (N.Low = '[') or InList(N.Low, FOLLOWERS);
end;

function ReadRoutineAt(AMap: TRdxCodeMap; const AHead: TRdxToken;
  ADepth: Integer; out R: TRdxRoutine): string;
var
  T : TRdxToken;
  W : string;
begin
  R := Default(TRdxRoutine);
  R.Head := AHead;
  R.Keyword := AHead;
  if AHead.Low = KW_CLASS then
    R.Keyword := After(AMap, AHead);
  if not InList(R.Keyword.Low, ROUTINE_WORDS) then
    Exit('kein Routinenkopf');
  Result := ReadName(AMap, R, T);
  if Result = '' then
    Result := HeaderEndFrom(AMap, T, R.HeaderEnd);
  if Result = '' then
    Result := ReadDirectives(AMap, R, ROUTINE_DIRECTIVES, T);
  if (Result <> '') or HasDirective(R, BODYLESS_DIRECTIVES, W) then Exit;
  Result := ReadDeclPart(AMap, R, T, ADepth);
  if Result = '' then
    Result := ReadBody(AMap, R);
  if (Result = '') and not FollowsRoutine(AMap, R.Last) then
    Result := 'hinter der Routine beginnt nichts Neues - ihr Ende ist nicht '
      + 'sicher';
end;

{ ---- Zeilen und Loeschbereiche ---- }

// Eine Zeile nur aus Kommentar (keine Direktive) und nicht leer?
function CommentOnly(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  L   : string;
  i   : Integer;
  Any : Boolean;
begin
  L := AMap.Raw(ALine);
  Any := False;
  for i := 1 to Length(L) do
    if not IsBlank(L[i]) then
    begin
      if (AMap.ClassAt(ALine, i) <> 'k') or DirectiveAt(AMap, ALine, i) then
        Exit(False);
      Any := True;
    end;
  Result := Any;
end;

// Eine '///'-Zeile (XMLDoc) - der Kommentar beginnt am Zeilenanfang.
function DocLine(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  L : string;
  C : Integer;
begin
  L := AMap.Raw(ALine);
  C := SkipBlanks(L, 1);
  Result := (Copy(L, C, Length(DOC_PREFIX)) = DOC_PREFIX)
    and (AMap.LineCommentCol(ALine) = C);
end;

// Eine Zeile nur mit einem Attribut '[..]'?
function AttrLine(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  T, C : TRdxToken;
begin
  Result := False;
  T := NextToken(AMap, ALine, 1);
  if (T.Line <> ALine) or (T.Low <> '[')
     or (T.Col <> SkipBlanks(AMap.Raw(ALine), 1)) then
    Exit;
  C := MatchClose(AMap, T, 0);
  Result := (C.Line = ALine) and (After(AMap, C).Line <> ALine);
end;

// '{ TFoo }' - ein Abschnittsmarker (ein Bezeichner in geschweiften
// Klammern) gehoert zur Gruppe, nicht zur Routine darunter. Nennt er die
// Routine selbst ('{ TFoo.Bar }' ueber 'TFoo.Bar', Korpus doublecmd), ist
// er ihre Ueberschrift und geht mit.
function MarkerLine(AMap: TRdxCodeMap; ALine: Integer;
  const AName: string): Boolean;
var
  S, Inner : string;
  i        : Integer;
begin
  Result := False;
  S := Trim(AMap.Raw(ALine));
  if (Length(S) < Length('{x}')) or (S[1] <> '{') or (S[Length(S)] <> '}')
     or (S[2] = '$') then
    Exit;
  Inner := Trim(Copy(S, 2, Length(S) - 2));
  if (Inner = '') or not IsIdentStart(Inner[1]) then Exit;
  for i := 1 to Length(Inner) do
    if not (IsIdentChar(Inner[i]) or (Inner[i] = '.')) then
      Exit;
  Result := not SameText(Inner, AName)
    and not SameText(Inner, Copy(AName, LastDelimiter('.', AName) + 1,
      MaxInt));
end;

// Gehoert die Zeile ueber dem Kopf von R zu ihm (AMode)?
function BelongsAbove(AMap: TRdxCodeMap; ALine: Integer;
  const R: TRdxRoutine; AMode: TRdxAbove): Boolean;
begin
  Result := DocLine(AMap, ALine) or AttrLine(AMap, ALine)
    or ((AMode = abComments) and CommentOnly(AMap, ALine)
        and not MarkerLine(AMap, ALine, R.Name));
end;

// Die oberste Zeile, die zum Kopf von R gehoert. Ein Block-Kommentar, der
// in einer Code-Zeile darueber beginnt, bleibt ganz stehen.
function TopAbove(AMap: TRdxCodeMap; const R: TRdxRoutine;
  AMode: TRdxAbove): Integer;
begin
  Result := R.Head.Line;
  while (Result > 1) and BelongsAbove(AMap, Result - 1, R, AMode) do
    Dec(Result);
  while (Result < R.Head.Line) and AMap.StartsInside(Result) do
    Inc(Result);
end;

function BlankLine(AMap: TRdxCodeMap; ALine: Integer): Boolean;
begin
  Result := (ALine >= 1) and (ALine <= AMap.LineCount)
    and (Trim(AMap.Raw(ALine)) = '') and not AMap.StartsInside(ALine);
end;

// Stehen Kopf AFirst bis Ende ALast allein auf ihren Zeilen (ab ATop)? ''
// oder der Grund.
function OwnLinesReason(AMap: TRdxCodeMap; const AFirst, ALast: TRdxToken;
  ATop: Integer): string;
var
  P, N : TRdxToken;
begin
  Result := '';
  P := Before(AMap, AFirst);
  N := After(AMap, ALast);
  if (P.Low <> '') and (P.Line = AFirst.Line) then
    Result := 'vor dem Kopf steht Code auf derselben Zeile (zwei Routinen auf '
      + 'einer Zeile?)'
  else if (N.Low <> '') and (N.Line = ALast.Line) then
    Result := 'hinter dem Ende steht Code auf derselben Zeile (zwei Routinen '
      + 'auf einer Zeile?)'
  else if AMap.StartsInside(ATop) then
    Result := 'auf der Kopfzeile endet ein Kommentar ueber Zeilen'
  else if AMap.StartsInside(ALast.Line + 1) then
    Result := 'hinter dem Ende beginnt ein Kommentar ueber Zeilen'
  else if ALast.Line >= AMap.LineCount then
    Result := R_LAST_LINE;
end;

// Die ganzen Zeilen von R (Kopf bis R.Last) samt dem, was darueber zum
// Kopf gehoert (AMode). '' oder der Grund.
function HeadLines(AMap: TRdxCodeMap; const R: TRdxRoutine;
  AMode: TRdxAbove; out ALines: TRdxLines): string;
begin
  ALines.Top := TopAbove(AMap, R, AMode);
  ALines.Bottom := R.Last.Line;
  Result := OwnLinesReason(AMap, R.Head, R.Last, ALines.Top);
end;

// EINE Leerzeile geht mit: die dahinter, sonst die davor. Ein Bereich darf
// nicht auf einer LEEREN Zeile beginnen (TRefactorInfoBuilder.SpanFits -
// Korpus-Harness: 33 PLANFAIL); LinesEdit beginnt ihn dann auf dem letzten
// Zeichen der Zeile davor, das stehen bleibt. Die Leerzeile davor geht
// deshalb nur mit, wenn diese Zeile hinter AFloor liegt (dort endet eine
// andere Ersetzung derselben Hilfe) und auf ein ASCII-Zeichen endet (kein
// halbes Surrogatpaar).
procedure TakeBlankLine(AMap: TRdxCodeMap; var ALines: TRdxLines;
  AFloor: Integer);
var
  Start : Integer;
  L     : string;
begin
  if BlankLine(AMap, ALines.Bottom + 1)
     and (ALines.Bottom + 1 < AMap.LineCount) then
  begin
    Inc(ALines.Bottom);
    Exit;
  end;
  if not BlankLine(AMap, ALines.Top - 1) then Exit;
  Start := ALines.Top - 1;
  if AMap.Raw(Start) = '' then
    Dec(Start);
  L := AMap.Raw(Start);
  if (Start > AFloor) and (L <> '') and (L[Length(L)] < #128) then
    Dec(ALines.Top);
end;

// Die Ersetzung, die ALines loescht (bis Spalte 1 der Zeile dahinter); ist
// die erste Zeile leer, ab dem letzten Zeichen der Zeile davor (s.
// TakeBlankLine).
function LinesEdit(AMap: TRdxCodeMap; const ALines: TRdxLines;
  const ARole: string): TRdxEdit;
var
  L : string;
begin
  Result := Default(TRdxEdit);
  L := AMap.Raw(ALines.Top);
  if L <> '' then
    Result.Span := TRefactorSpan.Make(ARole, ALines.Top, 1,
      ALines.Bottom + 1, 1)
  else
  begin
    // Das Zeichen und sein Zeilenende bleiben - sonst klebte die Zeile
    // dahinter an ihm, hinter einem '//' sogar auskommentiert.
    L := AMap.Raw(ALines.Top - 1);
    Result.Span := TRefactorSpan.Make(ARole, ALines.Top - 1, Length(L),
      ALines.Bottom + 1, 1);
    Result.NewText := Copy(L, Length(L), 1) + #10;
  end;
  Result.Expected := RangeText(AMap, Result.Span);
end;

{ ---- Direktiven ---- }

// DirectiveAt nur an '{' bzw. '(' - die Durchsichten laufen ueber jedes
// Zeichen der Datei, DirectiveAt kopiert je Aufruf.
function OpensDirective(AMap: TRdxCodeMap; ALine, ACol: Integer): Boolean;
var
  L : string;
begin
  L := AMap.Raw(ALine);
  Result := (ACol <= Length(L)) and CharInSet(L[ACol], ['{', '('])
    and DirectiveAt(AMap, ALine, ACol);
end;

// Das Wort einer Direktive an (ALine, ACol): '{$IFDEF X}' -> 'ifdef'; AArg:
// dahinter Leerraum oder ein Quote (Dateiname - '{$I x.inc}', nicht
// '{$I+}').
function DirectiveWord(AMap: TRdxCodeMap; ALine, ACol: Integer;
  out AArg: Boolean): string;
var
  L    : string;
  i, j : Integer;
begin
  L := AMap.Raw(ALine);
  i := ACol + Length('{$');
  if L[ACol] = '(' then
    i := ACol + Length('(*$');
  j := i;
  while (j <= Length(L)) and CharInSet(L[j], ['A'..'Z', 'a'..'z']) do
    Inc(j);
  Result := LowerCase(Copy(L, i, j - i));
  AArg := (j <= Length(L)) and CharInSet(L[j], [' ', #9, '''']);
end;

// Ein offenes Gegenstueck vom Stapel nehmen (AWant 'c' oder 'r'). '' oder
// der Grund.
function PopDirective(var AStack: string; const AWant, AWord: string;
  ALine: Integer): string;
begin
  if Copy(AStack, Length(AStack), 1) <> AWant then
    Exit(Format('{$%s} in Zeile %d ohne Gegenstueck im Bereich',
      [UpperCase(AWord), ALine]));
  SetLength(AStack, Length(AStack) - 1);
  Result := '';
end;

// Ein Schritt der Direktiven-Bilanz: AStack traegt 'c' je offenem $IF..
// und 'r' je offenem $REGION. Jede andere Direktive sperrt - ein $DEFINE,
// $R- oder $I wirkt vielleicht ueber die Routine hinaus. '' oder Grund.
function BalanceStep(var AStack: string; const AWord: string;
  ALine: Integer): string;
begin
  Result := '';
  if InList(AWord, COND_OPEN) then
    AStack := AStack + STACK_COND
  else if AWord = 'region' then
    AStack := AStack + STACK_REGION
  else if InList(AWord, COND_MID) then
  begin
    if Copy(AStack, Length(AStack), 1) <> STACK_COND then
      Result := Format('{$%s} in Zeile %d ohne $IF im Bereich',
        [UpperCase(AWord), ALine]);
  end
  else if AWord = 'endregion' then
    Result := PopDirective(AStack, STACK_REGION, AWord, ALine)
  else if InList(AWord, COND_CLOSE) then
    Result := PopDirective(AStack, STACK_COND, AWord, ALine)
  else
    Result := Format('Compiler-Direktive {$%s} in Zeile %d - sie wirkt '
      + 'vielleicht ueber die Routine hinaus', [UpperCase(AWord), ALine]);
end;

// Die Direktiven in den Zeilen ALines: nur ausgeglichene $IF../$ELSE/
// $ENDIF und $REGION/$ENDREGION. '' oder der Grund.
function DirectiveBalance(AMap: TRdxCodeMap; const ALines: TRdxLines): string;
var
  Li, Co : Integer;
  Stack  : string;
  Arg    : Boolean;
begin
  Result := '';
  Stack := '';
  for Li := ALines.Top to ALines.Bottom do
    for Co := 1 to Length(AMap.Raw(Li)) do
      if OpensDirective(AMap, Li, Co) then
      begin
        Result := BalanceStep(Stack, DirectiveWord(AMap, Li, Co, Arg), Li);
        if Result <> '' then Exit;
      end;
  if Stack <> '' then
    Result := 'Direktive ohne Gegenstueck im Bereich ($IF.. ohne $ENDIF bzw. '
      + '$REGION ohne $ENDREGION)';
end;

{ ---- Was die Datei sonst ueber den Namen sagt ---- }

// Die letzte Spalte des Laufs gleicher Zeichenklasse ab (ALine, ACol).
function RunEnd(AMap: TRdxCodeMap; ALine, ACol: Integer): Integer;
var
  K : Char;
begin
  K := AMap.ClassAt(ALine, ACol);
  Result := ACol;
  while AMap.ClassAt(ALine, Result + 1) = K do
    Inc(Result);
end;

{ TRdxFactScan }

function TRdxFactScan.InOwn(ALine: Integer): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := Low(Own) to High(Own) do
    if (ALine >= Own[i].Top) and (ALine <= Own[i].Bottom) then
      Exit(True);
end;

procedure TRdxFactScan.Directive(AMap: TRdxCodeMap; ALine, ACol: Integer);
var
  W, Text : string;
  Arg     : Boolean;
begin
  W := DirectiveWord(AMap, ALine, ACol, Arg);
  if Arg and InList(W, LINK_WORDS) and (Facts.LinksObject = 0) then
    Facts.LinksObject := ALine;
  if Arg and InList(W, INCLUDE_WORDS) and (ALine > ImplLine)
     and (Facts.ImplInclude = 0) then
    Facts.ImplInclude := ALine;
  if (W = 'rtti') and (Facts.Rtti = 0) then
    Facts.Rtti := ALine;
  Text := LowerCase(Copy(AMap.Raw(ALine), ACol,
    RunEnd(AMap, ALine, ACol) - ACol + 1));
  if (Facts.NameDirective = 0) and not InOwn(ALine)
     and HasWord(Text, LowName) then
    Facts.NameDirective := ALine;
end;

procedure TRdxFactScan.Literal(AMap: TRdxCodeMap; ALine, ACol, AEnd: Integer);
begin
  if (Facts.NameLiteral = 0) and not InOwn(ALine)
     and HasWord(LowerCase(Copy(AMap.Raw(ALine), ACol, AEnd - ACol + 1)),
       LowName) then
    Facts.NameLiteral := ALine;
end;

// Eine Durchsicht aller Zeilen: String-Literale und Direktiven (s.
// TRdxFileFacts). AOwn und AOther: die geloeschten Bereiche.
function FileFacts(AMap: TRdxCodeMap; const ALowName: string;
  AImplLine: Integer; const AOwn, AOther: TRdxLines): TRdxFileFacts;
var
  Scan       : TRdxFactScan;
  Li, Co, E  : Integer;
begin
  Scan := Default(TRdxFactScan);
  Scan.LowName := ALowName;
  Scan.ImplLine := AImplLine;
  Scan.Own[0] := AOwn;
  Scan.Own[1] := AOther;
  for Li := 1 to AMap.LineCount do
  begin
    Co := 1;
    while Co <= Length(AMap.Raw(Li)) do
    begin
      E := Co;
      if AMap.ClassAt(Li, Co) = 's' then
      begin
        E := RunEnd(AMap, Li, Co);
        Scan.Literal(AMap, Li, Co, E);
      end
      else if OpensDirective(AMap, Li, Co) then
        Scan.Directive(AMap, Li, Co);
      Co := E + 1;
    end;
  end;
  Result := Scan.Facts;
end;

// Name im String-Literal oder in einer Direktive. '' oder der Grund.
function NameFactsReason(const F: TRdxFileFacts; const AName: string): string;
begin
  Result := '';
  if F.NameLiteral > 0 then
    Result := Format('%s steht in einem String-Literal (Zeile %d) - Aufruf '
      + 'per Name (GetProcAddress, MethodAddress, RTTI, Skript)?',
      [AName, F.NameLiteral])
  else if F.NameDirective > 0 then
    Result := Format('eine Direktive nennt %s (Zeile %d)',
      [AName, F.NameDirective]);
end;

// Ein Lauf ueber alle Code-Token: 'implementation' und jedes Vorkommen von
// ALowName als Wort - auch in inaktiven $IFDEF-Zweigen (die Code-Sicht
// wertet keine Direktiven aus).
function ScanName(AMap: TRdxCodeMap; const ALowName: string): TRdxNameScan;
var
  T, P : TRdxToken;
begin
  Result := Default(TRdxNameScan);
  P := Default(TRdxToken);
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    if T.Low = ALowName then
      AddToken(Result.Hits, T)
    else if (T.Low = 'implementation') and (Result.Impl.Low = '')
       and IsKeywordAfter(T, P) then
      Result.Impl := T;
    P := T;
    T := After(AMap, T);
  end;
end;

// Steht AHit in einer exports-Klausel? Rueckwaerts bis zum ';'.
function InExports(AMap: TRdxCodeMap; const AHit: TRdxToken): Boolean;
var
  T : TRdxToken;
  n : Integer;
begin
  Result := False;
  T := Before(AMap, AHit);
  n := 0;
  while (T.Low <> '') and (T.Low <> KW_SEMI) and (n < MAX_BACK) do
  begin
    if T.Low = 'exports' then
      Exit(True);
    T := Before(AMap, T);
    Inc(n);
  end;
end;

// Warum das Vorkommen AHit des Namens die Hilfe sperrt. AImplLine = 0:
// kein interface-Grund (SCA147 - die Klasse steht oft im interface-Teil).
function HitReason(AMap: TRdxCodeMap; const AHit: TRdxToken;
  const AName: string; AImplLine: Integer): string;
var
  P : TRdxToken;
begin
  P := Before(AMap, AHit);
  if AHit.Line < AImplLine then
    Result := Format('%s steht im interface-Teil (Zeile %d) - exportiert, '
      + 'Aufrufer in anderen Units moeglich', [AName, AHit.Line])
  else if InExports(AMap, AHit) then
    Result := Format('die exports-Klausel nennt %s (Zeile %d)',
      [AName, AHit.Line])
  else if IsHeadAt(AMap, P) then
    Result := Format('zweite Routine %s in Zeile %d - Overload, '
      + '$IFDEF-Zwilling oder Deklaration', [AName, AHit.Line])
  else if InList(P.Low, ACCESSOR_WORDS) then
    Result := Format('%s ist Accessor einer Property (Zeile %d)',
      [AName, AHit.Line])
  else
    Result := Format('%s wird in Zeile %d verwendet - Fund veraltet? Datei '
      + 'neu pruefen', [AName, AHit.Line]);
end;

// Der Name aus der Meldung zwischen AKey und ' appears unused'; '' ohne
// diese Form.
function NameFromMessage(const AMessage, AKey: string): string;
var
  E : Integer;
begin
  Result := '';
  E := Pos(KEY_UNUSED, AMessage);
  if (Pos(AKey, AMessage) = 1) and (E > Length(AKey) + 1) then
    Result := Trim(Copy(AMessage, Length(AKey) + 1, E - Length(AKey) - 1));
end;

// Der eine Kopf mit dem Namen AName auf ALine (AWhat: was gesucht wird,
// fuer den Grund). '' oder der Grund; AHead ist der Kopfanfang.
function HeadOn(AMap: TRdxCodeMap; ALine: Integer; const AName,
  AWhat: string; out AHead: TRdxToken): string;
var
  S : TRdxLineSearch;
  K : TRdxToken;
begin
  AHead := Default(TRdxToken);
  S := Default(TRdxLineSearch);
  S.Test := IsHeadNamed;
  S.Arg := LowerCase(AName);
  S.What := Format('kein Kopf %s %s', [AWhat, AName]);
  S.ManyFmt := '%d Koepfe ' + AWhat + ' ' + AName;
  Result := OneTokenOnLine(AMap, ALine, S, K);
  if Result = '' then
    AHead := HeadStart(AMap, K);
end;

{ ---- SCA164 ---- }

// Ist AHit der Name einer forward-Deklaration im implementation-Teil? Dann
// AFwd.
function ForwardAt(AMap: TRdxCodeMap; const AHit: TRdxToken;
  AImplLine: Integer; out AFwd: TRdxRoutine): Boolean;
var
  K : TRdxToken;
  W : string;
begin
  AFwd := Default(TRdxRoutine);
  K := Before(AMap, AHit);
  Result := (AHit.Line > AImplLine) and IsHeadAt(AMap, K)
    and (ReadRoutineAt(AMap, HeadStart(AMap, K), 0, AFwd) = '')
    and (Length(AFwd.Parts) = 1)
    and HasDirective(AFwd, ['forward'], W);
end;

// Die Vorkommen des Namens ausserhalb der Routine R: EINE
// forward-Deklaration (AFwd; Head.Low = '' ohne) geht mit, jedes andere
// sperrt. '' oder der Grund.
function OutsideHits(AMap: TRdxCodeMap; const AScan: TRdxNameScan;
  const R: TRdxRoutine; out AFwd: TRdxRoutine): string;
var
  H : TRdxToken;
  F : TRdxRoutine;
begin
  Result := '';
  AFwd := Default(TRdxRoutine);
  for H in AScan.Hits do
  begin
    if TokInRange(H, R.Head, R.Last) then Continue;
    if (AFwd.Head.Low = '') and ForwardAt(AMap, H, AScan.Impl.Line, F) then
    begin
      AFwd := F;
      Continue;
    end;
    Exit(HitReason(AMap, H, R.Name, AScan.Impl.Line));
  end;
end;

// Eine freie Routine mit Rumpf, von aussen nicht erreichbar? '' oder Grund.
function FreeRoutineReason(const R: TRdxRoutine): string;
var
  W : string;
begin
  Result := '';
  if (Length(R.Parts) > 1) or (R.Head.Low = KW_CLASS)
     or InList(R.Keyword.Low, NO_SPECIAL) then
    Result := 'Methode einer Klasse - die meldet SCA147 bzw. SCA148'
  else if HasDirective(R, REACHABLE_DIRECTIVES, W) then
    Result := Format('Direktive %s - die Routine ist von aussen erreichbar '
      + 'oder hat keinen Rumpf', [W]);
end;

// SCA164: {$L}, {$I} im implementation-Teil, Name in Literal/Direktive.
function RoutineFactsReason(const F: TRdxFileFacts; const AName: string): string;
begin
  if F.LinksObject > 0 then
    Result := Format('die Unit linkt eine Objektdatei ({$L} in Zeile %d) - '
      + 'der C-Code ruft Routinen per Name', [F.LinksObject])
  else if F.ImplInclude > 0 then
    Result := Format(R_IMPL_INCLUDE, [F.ImplInclude])
  else
    Result := NameFactsReason(F, AName);
end;

// Die Zeilen der forward-Deklaration AFwd (ohne: ALines bleibt 0..0). ''
// oder der Grund.
function ForwardLines(AMap: TRdxCodeMap; const AFwd: TRdxRoutine;
  out ALines: TRdxLines): string;
begin
  ALines := Default(TRdxLines);
  if AFwd.Head.Low = '' then Exit('');
  Result := HeadLines(AMap, AFwd, abDocOnly, ALines);
  if Result = '' then
    Result := DirectiveBalance(AMap, ALines);
  if Result <> '' then
    Result := 'forward-Deklaration: ' + Result;
end;

// Der Plan fuer die freie Routine R: Nachweis am Puffer, Bereiche,
// Ersetzungen (die forward-Deklaration zuerst). '' oder der Grund.
function PlanRoutine(AMap: TRdxCodeMap; const R: TRdxRoutine;
  var APlan: TRdxRoutinePlan): string;
var
  Scan       : TRdxNameScan;
  Fwd        : TRdxRoutine;
  Main, FwdL : TRdxLines;
begin
  FwdL := Default(TRdxLines);
  Scan := ScanName(AMap, LowerCase(R.Name));
  if (Scan.Impl.Low = '') or TokBefore(R.Head, Scan.Impl) then
    Exit('der Kopf steht nicht im implementation-Teil (interface oder '
      + 'Programm) - von aussen erreichbar');
  Result := OutsideHits(AMap, Scan, R, Fwd);
  if Result = '' then
    Result := ForwardLines(AMap, Fwd, FwdL);
  if Result = '' then
    Result := HeadLines(AMap, R, abComments, Main);
  if Result <> '' then Exit;
  TakeBlankLine(AMap, Main, FwdL.Bottom);
  Result := RoutineFactsReason(FileFacts(AMap, LowerCase(R.Name),
    Scan.Impl.Line, Main, FwdL), R.Name);
  if Result = '' then
    Result := DirectiveBalance(AMap, Main);
  if Result <> '' then Exit;
  if FwdL.Top > 0 then
    AddEdit(APlan.Edits, LinesEdit(AMap, FwdL, SPAN_164));
  AddEdit(APlan.Edits, LinesEdit(AMap, Main, SPAN_164));
end;

{ ---- SCA147 ---- }

// Die Deklaration ab AHead im Klassenrumpf: ein Glied als Name, Kopf bis
// ';', Direktiven (METHOD_DIRECTIVES). '' oder der Grund.
function ReadMethodDecl(AMap: TRdxCodeMap; const AHead: TRdxToken;
  out D: TRdxRoutine): string;
var
  T : TRdxToken;
begin
  D := Default(TRdxRoutine);
  D.Head := AHead;
  D.Keyword := AHead;
  if AHead.Low = KW_CLASS then
    D.Keyword := After(AMap, AHead);
  Result := ReadName(AMap, D, T);
  if (Result = '') and (Length(D.Parts) > 1) then
    Result := 'Methodenaufloesung (IFoo.X = Y) - keine eigene Methode';
  if Result = '' then
    Result := HeaderEndFrom(AMap, T, D.HeaderEnd);
  if Result = '' then
    Result := ReadDirectives(AMap, D, METHOD_DIRECTIVES, T);
end;

// Erreicht jemand die Methode ohne ihren Namen? '' oder der Grund.
function DispatchReason(const D: TRdxRoutine): string;
var
  W : string;
begin
  Result := '';
  if HasDirective(D, DISPATCH_DIRECTIVES, W) then
    Result := Format('Direktive %s - Vorfahren, Nachfahren, Nachrichten oder '
      + 'Overload-Geschwister erreichen die Methode ohne ihren Namen', [W])
  else if InList(D.Keyword.Low, NO_SPECIAL) then
    Result := Format('%s - verdeckt Geerbtes bzw. wird ohne Namen gerufen; '
      + 'von Hand pruefen', [D.Keyword.Low]);
end;

// Hat der Typ ab AKind (class, object, interface ...) einen Rumpf mit end?
// Nicht 'class;' (Vorwaerts), 'class of' (Metaklasse), 'class(TBase);'
// (Kurzform).
function TypeHasBody(AMap: TRdxCodeMap; const AKind: TRdxToken): Boolean;
var
  N : TRdxToken;
begin
  N := After(AMap, AKind);
  while InList(N.Low, CLASS_MODIFIERS) do
    N := After(AMap, N);
  if N.Low = '(' then
    N := AfterClose(AMap, N);
  Result := not InList(N.Low, [KW_SEMI, 'of', '']);
end;

// 'AName [<..>] = [packed] class' mit Rumpf an T; AClass ist das Token
// 'class'.
function ClassHeadAt(AMap: TRdxCodeMap; const T: TRdxToken;
  const ALowName: string; out AClass: TRdxToken): Boolean;
var
  N : TRdxToken;
begin
  Result := False;
  AClass := Default(TRdxToken);
  if (T.Low <> ALowName) or not IsKeywordAfter(T, Before(AMap, T)) then Exit;
  N := After(AMap, T);
  if N.Low = '<' then
    N := AfterClose(AMap, N);
  if N.Low <> '=' then Exit;
  AClass := After(AMap, N);
  if AClass.Low = 'packed' then
    AClass := After(AMap, AClass);
  Result := (AClass.Low = KW_CLASS) and TypeHasBody(AMap, AClass);
end;

{ TRdxClassScan }

// Ein Token im Klassenrumpf: end schliesst, record und geschachtelte Typen
// mit Rumpf oeffnen; auf Tiefe 1 setzt ein Abschnittswort die
// Sichtbarkeit ('strict private'). 'case' im record hat kein eigenes end.
procedure TRdxClassScan.Step(AMap: TRdxCodeMap; const T, APrev: TRdxToken);
begin
  if not IsKeywordAfter(T, APrev) then Exit;
  if T.Low = KW_END then
    Dec(Depth)
  else if T.Low = 'record' then
    Inc(Depth)
  else if InList(T.Low, CLASS_LIKE) and InList(APrev.Low, ['=', 'packed'])
     and TypeHasBody(AMap, T) then
    Inc(Depth)
  else if (Depth = 1) and InList(T.Low, VISIBILITY_WORDS)
     and not InList(After(AMap, T).Low, FIELD_MARKS) then
  begin
    Vis := T.Low;
    if APrev.Low = 'strict' then
      Vis := 'strict ' + Vis;
  end;
end;

// Das end des Klassenrumpfs ab AClass; Low = '' ohne.
function ClassEnd(AMap: TRdxCodeMap; const AClass: TRdxToken): TRdxToken;
var
  Scan : TRdxClassScan;
  P    : TRdxToken;
begin
  Scan := Default(TRdxClassScan);
  Scan.Depth := 1;
  P := AClass;
  Result := After(AMap, AClass);
  while Result.Low <> '' do
  begin
    Scan.Step(AMap, Result, P);
    if Scan.Depth = 0 then Exit;
    P := Result;
    Result := After(AMap, Result);
  end;
end;

// Ein {$I datei} in den Zeilen AFrom..ATo? Zeile oder 0.
function IncludeInLines(AMap: TRdxCodeMap; AFrom, ATo: Integer): Integer;
var
  Li, Co : Integer;
  Arg    : Boolean;
begin
  Result := 0;
  for Li := AFrom to ATo do
    for Co := 1 to Length(AMap.Raw(Li)) do
      if OpensDirective(AMap, Li, Co)
         and InList(DirectiveWord(AMap, Li, Co, Arg), INCLUDE_WORDS) and Arg then
        Exit(Li);
end;

// Die Sichtbarkeit, unter der AHead im Rumpf ab AClass auf Tiefe 1 steht;
// False, wenn AHead nicht dort steht.
function VisibilityAt(AMap: TRdxCodeMap; const AClass, AHead: TRdxToken;
  out AVis: string): Boolean;
var
  Scan : TRdxClassScan;
  T, P : TRdxToken;
begin
  Result := False;
  AVis := '';
  Scan := Default(TRdxClassScan);
  Scan.Depth := 1;
  P := AClass;
  T := After(AMap, AClass);
  while (T.Low <> '') and (Scan.Depth > 0) do
  begin
    if SameTok(T, AHead) then
    begin
      AVis := Scan.Vis;
      Exit(Scan.Depth = 1);
    end;
    Scan.Step(AMap, T, P);
    P := T;
    T := After(AMap, T);
  end;
end;

// Die Koepfe der Methode ALowName auf Tiefe 1 des Rumpfs ab AClass.
procedure AddMemberHeads(AMap: TRdxCodeMap; const AClass: TRdxToken;
  const ALowName: string; var AHeads: TArray<TRdxToken>);
var
  Scan : TRdxClassScan;
  T, P : TRdxToken;
begin
  Scan := Default(TRdxClassScan);
  Scan.Depth := 1;
  P := AClass;
  T := After(AMap, AClass);
  while (T.Low <> '') and (Scan.Depth > 0) do
  begin
    if (Scan.Depth = 1) and IsHeadNamed(AMap, T, ALowName) then
      AddToken(AHeads, HeadStart(AMap, T));
    Scan.Step(AMap, T, P);
    P := T;
    T := After(AMap, T);
  end;
end;

// Der naechste Kopf der Klasse ALowName ueber AHead (zeilenweise
// rueckwaerts), dessen Rumpf AHead auf Tiefe 1 traegt.
function EnclosingClass(AMap: TRdxCodeMap; const AHead: TRdxToken;
  const ALowName: string; out AClass: TRdxClassHead): Boolean;
var
  Li : Integer;
  T  : TRdxToken;
begin
  AClass := Default(TRdxClassHead);
  for Li := AHead.Line downto 1 do
  begin
    T := NextToken(AMap, Li, 1);
    while (T.Low <> '') and (T.Line = Li) and TokBefore(T, AHead) do
    begin
      if ClassHeadAt(AMap, T, ALowName, AClass.ClassTok) then
      begin
        AClass.NameTok := T;
        Exit(VisibilityAt(AMap, AClass.ClassTok, AHead, AClass.Vis));
      end;
      T := After(AMap, T);
    end;
  end;
  Result := False;
end;

// Die Namen der Vorfahrenliste 'class(TBase, IFoo, Unit.IBar)' (wie im
// Text, je das letzte Glied, ohne Typargumente).
function HeritageNames(AMap: TRdxCodeMap; const AClass: TRdxToken): TArray<string>;
var
  T, Close : TRdxToken;
  Last     : string;
begin
  Result := nil;
  T := After(AMap, AClass);
  while InList(T.Low, CLASS_MODIFIERS) do
    T := After(AMap, T);
  if T.Low <> '(' then Exit;
  Close := MatchClose(AMap, T);
  Last := '';
  T := After(AMap, T);
  while (T.Low <> '') and not SameTok(T, Close) do
  begin
    if T.Low = '<' then
      T := MatchClose(AMap, T)
    else if T.Low = ',' then
    begin
      AddText(Result, Last);
      Last := '';
    end
    else if T.IsWord then
      Last := TokText(AMap, T);
    if T.Low <> '' then
      T := After(AMap, T);
  end;
  if Last <> '' then
    AddText(Result, Last);
end;

// Deklariert die Datei 'ALowName [<..>] = interface' (bzw. dispinterface)?
function DeclaresInterface(AMap: TRdxCodeMap; const ALowName: string): Boolean;
var
  T, N : TRdxToken;
begin
  Result := False;
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    if T.Low = ALowName then
    begin
      N := After(AMap, T);
      if N.Low = '<' then
        N := AfterClose(AMap, N);
      if (N.Low = '=')
         and InList(After(AMap, N).Low, ['interface', 'dispinterface']) then
        Exit(True);
    end;
    T := After(AMap, T);
  end;
end;

// Ein Interface der Klasse aus einer anderen Unit? Dann kann die Methode
// eines seiner Member sein (Aufruf ueber das Interface, ohne Namen in
// dieser Unit). Der erste Eintrag ist die Vorfahrklasse. '' oder Grund.
function ForeignInterfaceReason(AMap: TRdxCodeMap;
  const AClass: TRdxToken): string;
var
  Names : TArray<string>;
  i     : Integer;
begin
  Result := '';
  Names := HeritageNames(AMap, AClass);
  for i := 1 to High(Names) do
    if not DeclaresInterface(AMap, LowerCase(Names[i])) then
      Exit(Format('die Klasse implementiert %s (nicht in dieser Datei '
        + 'deklariert) - die Methode kann ein Interface-Member sein',
        [Names[i]]));
end;

// Der letzte Teil eines Pfads ('TOuter.TInner' -> 'TInner').
function LastPart(const S: string): string;
begin
  Result := Copy(S, LastDelimiter('.', S) + 1, MaxInt);
end;

// Klasse, Sichtbarkeit, Attribute, Interfaces und Zahl der Deklarationen.
// '' oder der Grund.
function MethodContextReason(AMap: TRdxCodeMap; const D: TRdxRoutine;
  const AClassPath: string): string;
var
  C       : TRdxClassHead;
  Decls   : TArray<TRdxToken>;
  IncLine : Integer;
begin
  if not EnclosingClass(AMap, D.Head, LowerCase(LastPart(AClassPath)), C) then
    Exit(Format('die Deklaration steht nicht im Rumpf der Klasse %s - Zeile '
      + 'verschoben? Datei neu pruefen', [AClassPath]));
  if not InList(C.Vis, PRIVATE_SECTIONS) then
  begin
    if C.Vis = '' then
      C.Vis := 'Vorgabe ohne Abschnitt';
    Exit(Format('die Methode steht unter "%s", nicht unter private',
      [C.Vis]));
  end;
  if (Before(AMap, C.NameTok).Low = ']') or (Before(AMap, D.Head).Low = ']') then
    Exit('Attribut an Klasse oder Methode - RTTI kann die Methode per Name '
      + 'finden');
  Decls := TRdxRoutineFixes.FindMethodDecls(AMap, AClassPath, D.Name);
  if Length(Decls) <> 1 then
    Exit(Format('%d Deklarationen von %s in Klassen dieses Namens - '
      + 'Overload?', [Length(Decls), D.Name]));
  // Ein Include im Klassenrumpf kann eine Property mit 'read X' tragen -
  // der Detektor prueft nur Includes im implementation-Teil (Gate F).
  IncLine := IncludeInLines(AMap, C.ClassTok.Line,
    ClassEnd(AMap, C.ClassTok).Line);
  if IncLine > 0 then
    Exit(Format('{$I}-Include im Klassenrumpf (Zeile %d) - dort kann die '
      + 'Methode stehen (Property-Accessor)', [IncLine]));
  Result := ForeignInterfaceReason(AMap, C.ClassTok);
end;

// Die eine Implementierung der Methode, gelesen bis zu ihrem Ende. '' oder
// der Grund.
function MethodImplOf(AMap: TRdxCodeMap; const AClassPath: string;
  const D: TRdxRoutine; out R: TRdxRoutine): string;
var
  Heads : TArray<TRdxToken>;
begin
  R := Default(TRdxRoutine);
  Heads := TRdxRoutineFixes.FindMethodImpls(AMap, AClassPath, D.Name);
  if Length(Heads) = 0 then
    Exit(Format('keine Implementierung von %s.%s in der Datei (include-Datei? '
      + 'abstract?)', [AClassPath, D.Name]));
  if Length(Heads) > 1 then
    Exit(Format('%d Implementierungen von %s.%s - Overload?',
      [Length(Heads), AClassPath, D.Name]));
  Result := ReadRoutineAt(AMap, Heads[0], 0, R);
  if Result <> '' then
    Result := 'Implementierung: ' + Result;
end;

// Jedes Vorkommen des Namens ausser Deklaration und Implementierung
// sperrt. '' oder der Grund.
function MethodHitsReason(AMap: TRdxCodeMap; const AScan: TRdxNameScan;
  const D, R: TRdxRoutine): string;
var
  H : TRdxToken;
begin
  Result := '';
  for H in AScan.Hits do
    if not (SameTok(H, D.NameTok) or TokInRange(H, R.Head, R.Last)) then
      Exit(HitReason(AMap, H, D.Name, 0));
end;

// SCA147: {$RTTI}, {$I} im implementation-Teil, Name in Literal/Direktive.
function MethodFactsReason(const F: TRdxFileFacts; const AName: string): string;
begin
  if F.Rtti > 0 then
    Result := Format('{$RTTI} in Zeile %d - erweiterte RTTI kann private '
      + 'Methoden per Name aufrufen', [F.Rtti])
  else if F.ImplInclude > 0 then
    Result := Format(R_IMPL_INCLUDE, [F.ImplInclude])
  else
    Result := NameFactsReason(F, AName);
end;

// Der Plan fuer Deklaration D und Implementierung R. '' oder der Grund.
function PlanMethod(AMap: TRdxCodeMap; const D, R: TRdxRoutine;
  var APlan: TRdxRoutinePlan): string;
var
  Scan          : TRdxNameScan;
  DeclL, ImplL  : TRdxLines;
begin
  Scan := ScanName(AMap, LowerCase(D.Name));
  if (Scan.Impl.Low = '') or TokBefore(R.Head, Scan.Impl) then
    Exit('die Implementierung steht nicht im implementation-Teil');
  Result := MethodHitsReason(AMap, Scan, D, R);
  if Result = '' then
    Result := HeadLines(AMap, D, abDocOnly, DeclL);
  if Result = '' then
    Result := HeadLines(AMap, R, abComments, ImplL);
  if Result <> '' then Exit;
  TakeBlankLine(AMap, ImplL, DeclL.Bottom);
  Result := MethodFactsReason(FileFacts(AMap, LowerCase(D.Name),
    Scan.Impl.Line, ImplL, DeclL), D.Name);
  if Result = '' then
    Result := DirectiveBalance(AMap, DeclL);
  if Result = '' then
    Result := DirectiveBalance(AMap, ImplL);
  if (Result = '') and (DeclL.Bottom >= ImplL.Top) then
    Result := 'Deklaration und Implementierung ueberlappen';
  if Result <> '' then Exit;
  AddEdit(APlan.Edits, LinesEdit(AMap, DeclL, SPAN_147));
  AddEdit(APlan.Edits, LinesEdit(AMap, ImplL, SPAN_147));
end;

{ TRdxRoutineFixes }

class function TRdxRoutineFixes.ReadRoutine(AMap: TRdxCodeMap;
  const AHead: TRdxToken; out ARoutine: TRdxRoutine): string;
var
  H : TRdxToken;
begin
  H := AHead;
  if InList(AHead.Low, ROUTINE_WORDS) then
    H := HeadStart(AMap, AHead);
  Result := ReadRoutineAt(AMap, H, 0, ARoutine);
end;

class function TRdxRoutineFixes.FindMethodDecls(AMap: TRdxCodeMap;
  const AClassPath, AMethod: string): TArray<TRdxToken>;
var
  T, C     : TRdxToken;
  LowClass : string;
begin
  Result := nil;
  LowClass := LowerCase(LastPart(AClassPath));
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    if ClassHeadAt(AMap, T, LowClass, C) then
      AddMemberHeads(AMap, C, LowerCase(AMethod), Result);
    T := After(AMap, T);
  end;
end;

// Passen die Glieder AParts eines Kopfs zu AClassParts + ALowMethod? Die
// letzten Glieder muessen gleich sein.
function PartsMatch(const AParts, AClassParts: TArray<string>;
  const ALowMethod: string): Boolean;
var
  i, n : Integer;
begin
  n := Length(AClassParts);
  Result := (Length(AParts) > n) and (AParts[High(AParts)] = ALowMethod);
  if not Result then Exit;
  for i := 1 to n do
    Result := Result and (AParts[High(AParts) - i] = AClassParts[n - i]);
end;

class function TRdxRoutineFixes.FindMethodImpls(AMap: TRdxCodeMap;
  const AClassPath, AMethod: string): TArray<TRdxToken>;
var
  T, P, Dummy : TRdxToken;
  R           : TRdxRoutine;
  ClassParts  : TArray<string>;
  InImpl      : Boolean;
begin
  Result := nil;
  ClassParts := SplitDotted(AClassPath);
  InImpl := False;
  P := Default(TRdxToken);
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    if InImpl and IsHeadAt(AMap, T) then
    begin
      R := Default(TRdxRoutine);
      R.Keyword := T;
      if (ReadName(AMap, R, Dummy) = '')
         and PartsMatch(R.Parts, ClassParts, LowerCase(AMethod)) then
        AddToken(Result, HeadStart(AMap, T));
    end
    else if (T.Low = 'implementation') and IsKeywordAfter(T, P) then
      InImpl := True;
    P := T;
    T := After(AMap, T);
  end;
end;

class function TRdxRoutineFixes.UnusedRoutine(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxRoutinePlan;
  out AReason: string): Boolean;
var
  Head : TRdxToken;
  R    : TRdxRoutine;
begin
  APlan := Default(TRdxRoutinePlan);
  R := Default(TRdxRoutine);
  APlan.Name := NameFromMessage(AMessage, KEY_ROUTINE);
  if APlan.Name = '' then
    AReason := 'Name der Routine fehlt in der Meldung'
  else
    AReason := HeadOn(AMap, ALine, APlan.Name, 'der Routine', Head);
  if AReason = '' then
    AReason := ReadRoutineAt(AMap, Head, 0, R);
  if AReason = '' then
    AReason := FreeRoutineReason(R);
  if AReason = '' then
  begin
    APlan.Name := R.Name;
    AReason := PlanRoutine(AMap, R, APlan);
  end;
  if AReason <> '' then
    APlan.Edits := nil;
  Result := AReason = '';
end;

class function TRdxRoutineFixes.UnusedPrivateMethod(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxRoutinePlan;
  out AReason: string): Boolean;
var
  Full, ClassPath : string;
  Head            : TRdxToken;
  D, R            : TRdxRoutine;
begin
  APlan := Default(TRdxRoutinePlan);
  D := Default(TRdxRoutine);
  R := Default(TRdxRoutine);
  Full := NameFromMessage(AMessage, KEY_METHOD);
  ClassPath := Copy(Full, 1, LastDelimiter('.', Full) - 1);
  APlan.Name := LastPart(Full);
  if (ClassPath = '') or (APlan.Name = '') then
    AReason := 'Klasse oder Methode fehlt in der Meldung'
  else
    AReason := HeadOn(AMap, ALine, APlan.Name, 'der Methode', Head);
  if AReason = '' then
    AReason := ReadMethodDecl(AMap, Head, D);
  if AReason = '' then
    AReason := DispatchReason(D);
  if AReason = '' then
    AReason := MethodContextReason(AMap, D, ClassPath);
  if AReason = '' then
    AReason := MethodImplOf(AMap, ClassPath, D, R);
  if AReason = '' then
  begin
    APlan.Name := D.Name;
    AReason := PlanMethod(AMap, D, R, APlan);
  end;
  if AReason <> '' then
    APlan.Edits := nil;
  Result := AReason = '';
end;

class function TRdxRoutineFixes.FormNamesMethod(const AFormText,
  AName: string): Boolean;
begin
  Result := HasWord(LowerCase(AFormText), LowerCase(AName));
end;

end.

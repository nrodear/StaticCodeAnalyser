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
// Direktive ($EXTERNALSYM). Kommentare zaehlen nicht als Verwendung - im
// Puffer; in einem Include vor implementation sperrt jede Nennung, auch im
// Kommentar (NameInInclude liest den Rohtext).
//
// BAUSTEINE: die Routinengrenzen (ReadRoutine), der Decl/Impl-Finder
// (FindMethodDecls/FindMethodImpls), der Klassenkopf (FindClassHeads,
// HeritageOf, MethodDecl, EnclosingClass), die Include-Kette
// (IncludeChainReason) und MarkerAboveReason stehen seit Charge B2S-b in
// uRdxBlocks (Review R6-12) - bis dahin hier, und fuenf andere Planer-
// Units banden diese Unit nur fuer sie ein. Hier bleiben die Planer
// SCA164/SCA147 mit dem, was nur sie brauchen (Loeschbereiche, Namen in
// der Datei, Interfaces der Klasse).
//
// WAS MITGEHT: ueber einer Implementierung '///'-Doku, Attribute und die
// direkt anhaengenden Zeilen nur aus Kommentar, wenn sie die Routine beim
// Namen nennen ('// Name: Foo()', '{ TFoo.Bar }') und keinen Marker tragen
// (noinspection, Absichtsmarker wie SCA019). Bis Charge H3c ging JEDER
// Kommentar darueber mit; das Gegen-Review H3 (Minor 3) fand darunter
// Abschnittsueberschriften ('(* === run-time registration functions ===
// *)', '{ layout vars }') und einen Absichtsmarker - eine Ueberschrift ist
// von einer Beschreibung am Text nicht sicher zu unterscheiden, deshalb
// bleibt jetzt jeder Kommentar, der die Routine nicht nennt
// (Korpus-Harness: bei 101 der 897 SCA164-Angebote bleibt er jetzt stehen -
// 53 Trenner, 43 Texte, 4 Ueberschriften mit Trenner, 1 Absichtsmarker;
// kein Angebot faellt weg). Preis: eine Beschreibung ohne den Namen ('//
// default is case-sensitive') bleibt stehen und liegt danach ueber dem,
// was folgt - sichtbar und von Hand zu loeschen; eine geloeschte
// Ueberschrift waere still verloren. Ein Abschnittsmarker '{ TFoo }' bleibt
// ohnehin (er gehoert zur Gruppe). Ueber einer Deklaration im Klassenrumpf
// nur '///' - dort steht oft ein Gruppenkommentar ('{ Private
// declarations }').
//
// GRENZEN: Programme und Bibliotheken (.dpr) meldet SCA164 nicht - der
// Detektor sieht nur Kinder des implementation-Knotens; der Planer verlangt
// deshalb ein 'implementation' vor dem Kopf. Eine leere private-Sektion,
// die nach SCA147 uebrig bleibt, meldet danach SCA087 (eigene Hilfe).
//
// PLATTE: die Planer sind Textlogik. Include-Dateien vor
// 'implementation' (ohne die im Kopf der Unit, IncludesUpTo) liest fuer
// SCA164 und (seit Charge B1-FD) SCA147 der Check der Tabelle ueber
// IncludeReason - die Kette dahinter (IncludeChainReason, nie auf einem
// Netzpfad) steht seit Charge B2S-b in uRdxBlocks.
//
// GRUNDSATZ wie in uRdxSimpleFixes: lieber keine Hilfe als eine falsche.

interface

uses
  uRdxBufferMath, uRdxCodeMap;

type
  // Ergebnis der Planer: alle Ersetzungen (EIN Undo-Schritt) und der Name
  // fuer den Menuetext - schon aus der Meldung, auch wenn abgelehnt wird.
  // Includes: die Dateien der {$I}-Direktiven vor 'implementation' (SCA164;
  // seit Charge B1-FD auch SCA147 - ein Include im interface-Teil kann eine
  // Nachfahrenklasse mit 'property P read X' tragen, Gegen-Review R4-05)
  // - der Puffer zeigt ihren Inhalt nicht; der Aufrufer liest sie neben der
  // Unit und prueft sie (IncludeReason), bevor er die Hilfe anbietet. Das
  // Geruest der Tabelle nimmt die Planer als TRdxPlannerOf<TRdxRoutinePlan>
  // (uRdxFixTable; der eigene Typ TRdxRoutinePlanner hier war seit Charge
  // H5c unbenutzt und ist mit B1-FD gestrichen, Gegen-Review R4-07).
  TRdxRoutinePlan = record
    Edits    : TArray<TRdxEdit>;
    Name     : string;
    Includes : TArray<string>;
  end;

  // Die Planer der Charge H3b (s. Kopf; ihre Bausteine stehen seit Charge
  // B2S-b in uRdxBlocks): je Fund alle Ersetzungen in EINEM Plan oder der
  // Grund, warum keine - auf dem Puffertext ueber die Code-Sicht, ohne
  // ToolsAPI und Parser (laeuft auch im FPC-Pruefstand). Was nur die Platte
  // weiss (Formdatei, Include-Dateien), liest der Aufrufer uRdxFixTable bzw.
  // IncludeReason.
  TRdxRoutineFixes = class
  public
    // SCA164: die Routine der Meldung 'Top-level routine X appears unused
    // ...' mit Kopf auf ALine loeschen (s. Kopf der Unit). Keine Hilfe fuer
    // Methoden, globale FPC-Operatoren, Koepfe vor 'implementation',
    // export/public/alias/external/forward/interrupt-Direktiven (auch FPC
    // in Klammern: '[public, alias: ''X'']'), Overloads, jede Verwendung
    // ausserhalb der Routine (Umlaute ohne Gross/klein), den Namen in einem
    // String-Literal oder einer Direktive, {$L}/{$LINK} in der Datei, {$I}
    // im implementation-Teil, eine Direktive im Bereich ausser
    // ausgeglichenem $IF../$ENDIF bzw. $REGION, zwei Routinen auf einer
    // Zeile, einen Marker-Kommentar, der ausserhalb wirkt (auf der letzten
    // Zeile 'end; // noinspection X', '// noinspection-file' im Bereich -
    // MarkerLinesReason) oder von aussen in den Bereich zielt (ueber dem
    // Kopf '// noinspection X' - MarkerAboveReason). Die {$I}-Dateien davor
    // nennt APlan.Includes - der Aufrufer prueft sie mit IncludeReason.
    class function UnusedRoutine(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxRoutinePlan;
      out AReason: string): Boolean; static;

    // SCA147: die Methode der Meldung 'Private method TFoo.X appears unused
    // ...' (Deklaration auf ALine) loeschen. Keine Hilfe ausserhalb von
    // private/strict private, bei virtual/dynamic/override/abstract/
    // reintroduce/message/overload/dispid, Konstruktor/Destruktor/Operator,
    // Attribut an Klasse oder Methode, {$RTTI} in der Datei, {$I} im
    // Klassenrumpf oder im implementation-Teil, einem Interface der Klasse
    // aus einer anderen Unit (auch als erster Eintrag 'class(IFremd)' oder
    // als Vorfahr eines lokalen Interfaces) bzw. einem Member von
    // IInterface/IDispatch als Name, mehr als einer Deklaration oder
    // Implementierung, keiner Implementierung in der Datei, jeder weiteren
    // Verwendung (auch Property-Accessor, String-Literal, Direktive), einer
    // Direktive im Bereich und einem Marker-Kommentar, der ausserhalb wirkt
    // oder von aussen in einen der Bereiche zielt, wie bei SCA164. Die
    // Formdatei prueft der Aufrufer (FormNamesMethod),
    // die {$I}-Dateien davor (seit Charge B1-FD in APlan.Includes) ebenso
    // mit IncludeReason.
    class function UnusedPrivateMethod(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxRoutinePlan;
      out AReason: string): Boolean; static;

    // SCA147: nennt die Formdatei (.dfm/.fmx/.lfm-Text) AName als Wort -
    // etwa als Ereignis 'OnClick = AName'? Den Text liest der Aufrufer.
    class function FormNamesMethod(const AFormText, AName: string): Boolean;
      static;

    // SCA164/SCA147: die Include-Dateien AIncludes (TRdxRoutinePlan.
    // Includes) der Unit AUnitFile lesen - neben der Unit, ohne Endung auch
    // mit .inc/.pas, verschachtelte Includes ebenso. '' wenn keine AName
    // als Wort nennt; sonst der Grund - auch, wenn eine nicht zu finden oder
    // zu lesen ist oder auf einem Netzpfad liegt: sie kann die Routine im
    // interface-Teil deklarieren (nach dem Loeschen E2065), rufen (Gegen-
    // Review H3, Minor 4) bzw. die Methode als Property-Accessor einer
    // Nachfahrenklasse nennen (R4-05). '{$I %DATE%}' (FPC) ist keine Datei.
    class function IncludeReason(const AUnitFile: string;
      const AIncludes: TArray<string>; const AName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,    // TStrings (NameInInclude: TRdxIncludeTest)
  uRefactorInfo,     // TRefactorSpan.Make
  // Routinengrenzen, Decl/Impl-Finder, Klassenkopf, Include-Kette und
  // MarkerAboveReason (bis Charge B2S-b hier, Review R6-12)
  uRdxBlocks;

const
  SPAN_164 = 'sca164';
  SPAN_147 = 'sca147';
  KW_CLASS = 'class';
  KW_SEMI  = ';';
  // SCA164: damit ist die Routine von aussen erreichbar (Linker-Name,
  // Export, Compiler/RTL, Interrupt) oder ohne Rumpf.
  REACHABLE_DIRECTIVES: array[0..9] of string = ('export', 'public',
    'alias', 'external', 'forward', 'interrupt', 'compilerproc', 'rtlproc',
    'internproc', 'weakexternal');
  // SCA147: damit erreicht die Methode ein Vorfahr, ein Nachfahr, die
  // Nachrichten-Verteilung oder ein Overload-Geschwister - ohne Namen.
  DISPATCH_DIRECTIVES: array[0..9] of string = ('virtual', 'dynamic',
    'abstract', 'override', 'reintroduce', 'message', 'overload', 'dispid',
    'external', 'final');
  PRIVATE_SECTIONS: array[0..1] of string = ('private', 'strict private');
  NO_SPECIAL: array[0..2] of string = ('constructor', 'destructor',
    'operator');
  CTOR_DTOR: array[0..1] of string = ('constructor', 'destructor');
  KW_OPERATOR = 'operator';
  // SCA147, Interfaces der Klasse (ForeignInterfaceReason, wie Gate E des
  // Detektors): die Wurzeln aus System - nie in der Datei deklariert, ihre
  // Member bekannt - und die Grenze der Kette (Detektor: 64).
  INTERFACE_KINDS: array[0..1] of string = ('interface', 'dispinterface');
  ROOT_INTERFACES: array[0..2] of string = ('iinterface', 'iunknown',
    'idispatch');
  ROOT_MEMBERS: array[0..2] of string = ('queryinterface', '_addref',
    '_release');
  DISPATCH_MEMBERS: array[0..3] of string = ('gettypeinfocount',
    'gettypeinfo', 'getidsofnames', 'invoke');
  MAX_INTERFACES = 64;
  COND_OPEN: array[0..3] of string = ('if', 'ifdef', 'ifndef', 'ifopt');
  COND_MID: array[0..1] of string = ('else', 'elseif');
  COND_CLOSE: array[0..1] of string = ('endif', 'ifend');
  LINK_WORDS: array[0..1] of string = ('l', 'link');
  // Property-Teile, hinter denen ein Methodenname Accessor ist.
  ACCESSOR_WORDS: array[0..4] of string = ('read', 'write', 'stored', 'add',
    'remove');
  KEY_ROUTINE = 'Top-level routine ';
  KEY_METHOD  = 'Private method ';
  KEY_UNUSED  = ' appears unused';
  DOC_PREFIX  = '///';
  STACK_COND   = 'c';
  STACK_REGION = 'r';
  MAX_BACK       = 400;   // so weit sucht InExports rueckwaerts
  R_IMPL_INCLUDE = '{$I}-Include im implementation-Teil (Zeile %d) - dort '
    + 'kann ein Aufrufer stehen, den die Hilfe nicht sieht';
  R_LAST_LINE = 'die Routine endet auf der letzten Zeile der Datei';
  // SCA164/SCA147: Include-Dateien vor implementation (IncludeReason) - fuer
  // beide Regeln: die Routine deklarieren oder rufen (SCA164) bzw. die
  // Methode als Property-Accessor einer Nachfahrenklasse nennen (SCA147;
  // bis zur Nachpruefung der Charge B1-FD sprach der Text nur von SCA164).
  R_INC_MISSING = 'Include %s vor implementation %s - es kann den Namen '
    + 'deklarieren, rufen oder als Property-Accessor nennen, die Hilfe sieht '
    + 'es nicht';
  // SCA164/SCA147: Marker im geloeschten Bereich, die ausserhalb wirken
  // (MarkerLinesReason, Gegen-Review R4-04).
  R_MARKER_FILE = '"// noinspection-file" in Zeile %d - der Marker gilt der '
    + 'ganzen Datei und ginge mit verloren; von Hand loeschen';
  R_MARKER_TAIL = 'Zeile %d endet mit dem Kommentar "%s" - ein Marker hinter '
    + 'Code gilt der Zeile dahinter bzw. bleibt stehen; von Hand loeschen';

type
  // Ganze Zeilen Top..Bottom - ein Loeschbereich.
  TRdxLines = record
    Top    : Integer;
    Bottom : Integer;
  end;

  // Was ueber einem Kopf mitgeht: '///'-Doku und Attributzeilen
  // (Klassenrumpf, forward) oder dazu Kommentarzeilen, die die Routine
  // nennen (Implementierung, StepAbove).
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

{ ---- Token und Texte ---- }

// TokBefore und TokText stehen seit Charge H4c in uRdxCodeMap, AddToken
// und LastPart seit Charge H5c, AddText seit Charge B2S-b (dort), AddEdit
// in uRdxBufferMath.
function TokInRange(const T, AFirst, ALast: TRdxToken): Boolean;
begin
  Result := not TokBefore(T, AFirst) and not TokBefore(ALast, T);
end;

// Kommt ALowName als ganzes Wort in ALowText vor (beides klein, genau
// gleich; Wortgrenze wie IsIdentChar)? Anders als HasIdentWord (uRdxCodeMap,
// Umlaute ohne Gross/klein - fuer Verwendungen: ein Treffer zu viel sperrt)
// genau: hier entscheidet es, ob ein Kommentar ueber dem Kopf mitgeht. Bis
// Charge H3c HasWord, gleich benannt wie das ASCII-HasWord von
// uRdxCleanupFixes (Minor 5).
function HasExactWord(const ALowText, ALowName: string): Boolean;
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

// Eine Zeile eines Kommentar-Laufs ueber dem Kopf: nur Kommentar, weder
// '///'-Doku noch Attribut noch Abschnittsmarker '{ TFoo }'.
function RunLine(AMap: TRdxCodeMap; ALine: Integer;
  const AName: string): Boolean;
begin
  Result := (ALine >= 1) and CommentOnly(AMap, ALine)
    and not DocLine(AMap, ALine) and not AttrLine(AMap, ALine)
    and not MarkerLine(AMap, ALine, AName);
end;

// Die Zeilen ATop..ABottom als ein Text.
function LinesText(AMap: TRdxCodeMap; ATop, ABottom: Integer): string;
var
  SB : TStringBuilder;
  Li : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for Li := ATop to ABottom do
      SB.Append(AMap.Raw(Li)).Append(#10);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Geht der Kommentar-Lauf ATop..ABottom ueber dem Kopf von R mit? Nur, wenn
// er die Routine beim Namen nennt (dann beschreibt er sie) und keinen
// Unterdrueck- oder Absichtsmarker traegt (MarkerReason, wie SCA070).
function RunGoes(AMap: TRdxCodeMap; ATop, ABottom: Integer;
  const R: TRdxRoutine): Boolean;
var
  Text : string;
begin
  Text := LinesText(AMap, ATop, ABottom);
  Result := (MarkerReason(Text) = '')
    and HasExactWord(LowerCase(Text), LowerCase(Copy(R.Name,
      LastDelimiter('.', R.Name) + 1, MaxInt)));
end;

// Ein Schritt nach oben ab ATop (TopAbove): die neue oberste Zeile oder ATop,
// wenn darueber nichts mehr zum Kopf gehoert. '///'-Doku und Attribute
// gehoeren immer dazu; bei abComments auch ein ganzer Kommentar-Lauf, wenn
// er mitgeht (RunGoes).
function StepAbove(AMap: TRdxCodeMap; const R: TRdxRoutine; AMode: TRdxAbove;
  ATop: Integer): Integer;
var
  L, Run : Integer;
begin
  Result := ATop;
  L := ATop - 1;
  if L < 1 then Exit;
  if DocLine(AMap, L) or AttrLine(AMap, L) then
    Exit(L);
  if (AMode = abDocOnly) or not RunLine(AMap, L, R.Name) then Exit;
  Run := L;
  while RunLine(AMap, Run - 1, R.Name) do
    Dec(Run);
  if RunGoes(AMap, Run, L, R) then
    Result := Run;
end;

// Die oberste Zeile, die zum Kopf von R gehoert. Ein Block-Kommentar, der
// in einer Code-Zeile darueber beginnt, bleibt ganz stehen. Seit Charge H3c
// (Gegen-Review H3, Minor 3) geht ein Kommentar ueber einer Implementierung
// nur mit, wenn er die Routine nennt und keinen Marker traegt - eine
// Abschnittsueberschrift ('(* === run-time registration functions === *)',
// '{ layout vars }'), ein '// noinspection-file' oder ein Absichtsmarker
// gehoert zur Gruppe bzw. zur Datei und bleibt stehen, mit allem darueber.
function TopAbove(AMap: TRdxCodeMap; const R: TRdxRoutine;
  AMode: TRdxAbove): Integer;
var
  Prev : Integer;
begin
  Result := R.Head.Line;
  repeat
    Prev := Result;
    Result := StepAbove(AMap, R, AMode, Result);
  until Result = Prev;
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

// Marker, die das Loeschen der ganzen Zeilen ALines mitnaehme, obwohl sie
// ausserhalb wirken (Gegen-Review R4-04): ein '//'-Kommentar mit Marker
// (MarkerReason: noinspection oder ein Absichtsmarker wie bei SCA019) hinter
// dem Code der letzten nicht leeren Zeile - '// noinspection X' hinter Code
// gilt der naechsten Zeile, und die bleibt stehen (uSuppression.BuildMap;
// 'end; // noinspection UnusedRoutine' zielte auf die Routine dahinter);
// ein Absichtskommentar bleibt wie ueber dem Kopf stehen -, und ein
// '// noinspection-file' irgendwo im Bereich (er gilt der ganzen Datei).
// Dazu ein Zeilen-Marker darueber, der in den Bereich zielt
// (MarkerAboveReason): TopAbove laesst einen Kommentar-Lauf mit Marker
// ueber dem Kopf stehen, und bis zur Nachpruefung der Charge B1-FD galt er
// danach still der Routine dahinter. '' oder der Grund.
function MarkerLinesReason(AMap: TRdxCodeMap; const ALines: TRdxLines): string;
var
  Li, Slash, Last : Integer;
  Comment         : string;
begin
  Result := MarkerAboveReason(AMap, ALines.Top);
  if Result <> '' then Exit;
  Last := 0;
  for Li := ALines.Top to ALines.Bottom do
  begin
    Slash := AMap.LineCommentCol(Li);
    if (Slash > 0) and (Pos(MARKER_FILE,
         LowerCase(Copy(AMap.Raw(Li), Slash, MaxInt))) > 0) then
      Exit(Format(R_MARKER_FILE, [Li]));
    if Trim(AMap.Raw(Li)) <> '' then
      Last := Li;
  end;
  if Last = 0 then Exit;
  Slash := AMap.LineCommentCol(Last);
  if Slash = 0 then Exit;
  Comment := Copy(AMap.Raw(Last), Slash, MaxInt);
  if MarkerReason(Comment) <> '' then
    Result := Format(R_MARKER_TAIL, [Last,
      TrimRight(Copy(Comment, 1, MARKER_QUOTE_LEN))]);
end;

{ ---- Direktiven (OpensDirective, DirectiveWord, IncludeInLines: seit
  Charge H3c in uRdxCodeMap) ---- }

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
     and HasIdentWord(Text, LowName) then
    Facts.NameDirective := ALine;
end;

procedure TRdxFactScan.Literal(AMap: TRdxCodeMap; ALine, ACol, AEnd: Integer);
begin
  if (Facts.NameLiteral = 0) and not InOwn(ALine)
     and HasIdentWord(LowerCase(Copy(AMap.Raw(ALine), ACol, AEnd - ACol + 1)),
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
// wertet keine Direktiven aus). Umlaute vergleicht SameIdent ohne Gross/
// klein (Verdacht 1 des Gegen-Reviews H3: ein Aufruf mit grossem Umlaut
// zaehlte nicht, die Hilfe loeschte die gerufene Routine).
function ScanName(AMap: TRdxCodeMap; const ALowName: string): TRdxNameScan;
var
  T, P : TRdxToken;
begin
  Result := Default(TRdxNameScan);
  P := Default(TRdxToken);
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    if SameIdent(T.Low, ALowName) then
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
  else if IsRoutineHead(AMap, P) then
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
// fuer den Grund). '' oder der Grund; AHead ist der Kopfanfang. Der Name
// aus der Meldung steht als Argument im Text, nie im Muster ManyFmt
// (Vertrag von TRdxLineSearch; bis Review Woche G05-19 stand er dort - je
// Routinenname ein anderes Muster, keine msgid). Wortlaut unveraendert.
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
  S.ManyFmt := '%d Koepfe ' + AWhat + ' %s';
  S.ManyArg := AName;
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
  Result := (AHit.Line > AImplLine) and IsRoutineHead(AMap, K)
    and (TRdxBlocks.ReadRoutine(AMap, HeadStart(AMap, K), AFwd) = '')
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
     or InList(R.Keyword.Low, CTOR_DTOR) then
    Result := 'Methode einer Klasse - die meldet SCA147 bzw. SCA148'
  else if R.Keyword.Low = KW_OPERATOR then
    // FPC: globaler Operator ('operator explicit(A: TFoo): Integer;') - bis
    // Charge H3c hiess auch er "Methode einer Klasse" (Gegen-Review H3,
    // Minor 12).
    Result := 'globaler Operator (FPC) - der Compiler ruft ihn ueber sein '
      + 'Zeichen bzw. die Umwandlung, nicht ueber den Namen'
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
  if Result = '' then
    Result := MarkerLinesReason(AMap, Main);
  if (Result = '') and (FwdL.Top > 0) then
    Result := MarkerLinesReason(AMap, FwdL);
  if Result <> '' then Exit;
  if FwdL.Top > 0 then
    AddEdit(APlan.Edits, LinesEdit(AMap, FwdL, SPAN_164));
  AddEdit(APlan.Edits, LinesEdit(AMap, Main, SPAN_164));
  // Die Zeile von 'implementation' zaehlt mit: dort vor oder hinter dem
  // Wort sieht FileFacts (ImplInclude ab der Zeile danach) es nicht.
  APlan.Includes := IncludesUpTo(AMap, Scan.Impl.Line);
end;

{ ---- SCA147 ---- }

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

// 'T [<..>] = interface' bzw. dispinterface: das Token 'interface'; Low =
// '' ohne diese Form.
function InterfaceKindAt(AMap: TRdxCodeMap; const T: TRdxToken): TRdxToken;
var
  N : TRdxToken;
begin
  Result := Default(TRdxToken);
  N := After(AMap, T);
  if N.Low = '<' then
    N := AfterClose(AMap, N);
  if N.Low <> '=' then Exit;
  N := After(AMap, N);
  if InList(N.Low, INTERFACE_KINDS) then
    Result := N;
end;

// Deklariert die Datei 'ALowName [<..>] = interface' (bzw. dispinterface)?
// AParents bekommt die Vorfahren jeder solchen Deklaration dazu (die
// Vorwaerts-Deklaration 'IFoo = interface;' traegt keine, die volle schon).
// Der Name wird genau verglichen - ein Treffer zu viel hiesse hier "lokal",
// also weniger Sperre.
function InterfaceParents(AMap: TRdxCodeMap; const ALowName: string;
  var AParents: TArray<string>): Boolean;
var
  T, K  : TRdxToken;
  Names : TArray<string>;
  S     : string;
begin
  Result := False;
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    K := Default(TRdxToken);
    if T.Low = ALowName then
      K := InterfaceKindAt(AMap, T);
    if K.Low <> '' then
    begin
      Result := True;
      Names := TRdxBlocks.HeritageOf(AMap, K);
      for S in Names do
        AddText(AParents, S);
    end;
    T := After(AMap, T);
  end;
end;

// Die Interfaces der Vorfahrenliste: ab dem zweiten Eintrag jeder (Delphi-
// Grammatik), der erste nur, wenn er wie ein Interface heisst oder in der
// Datei als Interface steht - 'class(IFremd)' hat die Basis TObject.
function ImplementedInterfaces(AMap: TRdxCodeMap;
  const AClass: TRdxToken): TArray<string>;
var
  Names, Dummy : TArray<string>;
  i            : Integer;
begin
  Result := nil;
  Dummy := nil;
  Names := TRdxBlocks.HeritageOf(AMap, AClass);
  for i := 0 to High(Names) do
    if (i > 0) or LooksLikeInterfaceName(Names[i])
       or InterfaceParents(AMap, LowerCase(Names[i]), Dummy) then
      AddText(Result, Names[i]);
end;

// Gehoert ALowMethod zu den Membern der System-Wurzel ALowRoot
// (IInterface/IUnknown bzw. IDispatch)?
function RootMember(const ALowRoot, ALowMethod: string): Boolean;
begin
  Result := InList(ALowMethod, ROOT_MEMBERS)
    or ((ALowRoot = 'idispatch') and InList(ALowMethod, DISPATCH_MEMBERS));
end;

// Ein Interface AName der Arbeitsliste: eine Wurzel (nur ein Name aus
// ihren Membern sperrt) oder in der Datei deklariert (seine Vorfahren
// kommen an AWork) - sonst aus einer anderen Unit. '' oder der Grund.
function InterfaceReason(AMap: TRdxCodeMap; const AName, ALowMethod: string;
  var AWork: TArray<string>): string;
var
  Key, P  : string;
  Parents : TArray<string>;
begin
  Result := '';
  Key := LowerCase(AName);
  Parents := nil;
  if InList(Key, ROOT_INTERFACES) then
  begin
    if RootMember(Key, ALowMethod) then
      Result := Format('%s ist ein Member von %s - die Methode kann es '
        + 'implementieren', [ALowMethod, AName]);
  end
  else if InterfaceParents(AMap, Key, Parents) then
  begin
    for P in Parents do
      AddText(AWork, P);
  end
  else
    Result := Format('die Klasse implementiert %s (nicht in dieser Datei '
      + 'deklariert) - die Methode kann ein Interface-Member sein', [AName]);
end;

// Ein Interface der Klasse aus einer anderen Unit - direkt oder als
// Vorfahr eines Interfaces dieser Datei? Dann kann die Methode eines seiner
// Member sein (Aufruf ueber das Interface, ohne Namen in dieser Unit). Gate
// E des Detektors nachgebildet (Sca147TryResolveIfaceMembers; Gegen-Review
// H3, Minor 2 - bis Charge H3c fehlten 'class(IFremd)' und die Vorfahren
// lokaler Interfaces, nach der Hilfe E2291): jedes lokale Interface bringt
// seine Vorfahren mit; IInterface/IUnknown/IDispatch sind bekannt - dort
// sperrt nur ein Methodenname aus ihren Membern. Die Member lokaler
// Interfaces findet schon die Namenssuche (Vorkommen ausserhalb von
// Deklaration und Implementierung). '' oder der Grund.
function ForeignInterfaceReason(AMap: TRdxCodeMap; const AClass: TRdxToken;
  const ALowMethod: string): string;
var
  Work, Seen : TArray<string>;
  i          : Integer;
  Name       : string;
begin
  Result := '';
  Seen := nil;
  Work := ImplementedInterfaces(AMap, AClass);
  i := 0;
  while (Result = '') and (i < Length(Work)) do
  begin
    Name := Work[i];
    Inc(i);
    if InList(LowerCase(Name), Seen) then Continue;
    AddText(Seen, LowerCase(Name));
    if Length(Seen) > MAX_INTERFACES then
      Exit('Interface-Kette zu lang - Grenzen nicht sicher');
    Result := InterfaceReason(AMap, Name, ALowMethod, Work);
  end;
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
  Decls := TRdxBlocks.FindMethodDecls(AMap, AClassPath, D.Name);
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
  Result := ForeignInterfaceReason(AMap, C.ClassTok, LowerCase(D.Name));
end;

// Die eine Implementierung der Methode, gelesen bis zu ihrem Ende. '' oder
// der Grund.
function MethodImplOf(AMap: TRdxCodeMap; const AClassPath: string;
  const D: TRdxRoutine; out R: TRdxRoutine): string;
var
  Heads : TArray<TRdxToken>;
begin
  R := Default(TRdxRoutine);
  Heads := TRdxBlocks.FindMethodImpls(AMap, AClassPath, D.Name);
  if Length(Heads) = 0 then
    Exit(Format('keine Implementierung von %s.%s in der Datei (include-Datei? '
      + 'abstract?)', [AClassPath, D.Name]));
  if Length(Heads) > 1 then
    Exit(Format('%d Implementierungen von %s.%s - Overload?',
      [Length(Heads), AClassPath, D.Name]));
  Result := TRdxBlocks.ReadRoutine(AMap, Heads[0], R);
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
  if Result = '' then
    Result := MarkerLinesReason(AMap, DeclL);
  if Result = '' then
    Result := MarkerLinesReason(AMap, ImplL);
  if Result <> '' then Exit;
  AddEdit(APlan.Edits, LinesEdit(AMap, DeclL, SPAN_147));
  AddEdit(APlan.Edits, LinesEdit(AMap, ImplL, SPAN_147));
  // Includes vor implementation wie bei SCA164 (Gegen-Review R4-05): eines
  // ausserhalb des Klassenrumpfs kann eine Nachfahrenklasse mit 'property
  // P read X' tragen - private ist in der ganzen Unit sichtbar; nach dem
  // Loeschen E2003 im Include. Der Detektor liest sie nicht (Gate F nur
  // hinter implementation), die Includes im Klassenrumpf lehnt schon
  // MethodContextReason ab. Der Check der Tabelle liest sie neben der Unit
  // (IncludeReason): nennt eines den Namen oder fehlt es, keine Hilfe.
  APlan.Includes := IncludesUpTo(AMap, Scan.Impl.Line);
end;

{ ---- SCA164/SCA147: Include-Dateien vor implementation (die Kette liest
  uRdxBlocks.IncludeChainReason) ---- }

// SCA164/SCA147: nennt das Include AFile die Routine bzw. Methode AArg als
// Wort? '' oder der Grund (TRdxIncludeTest) - fuer beide Regeln: eine
// Deklaration im interface-Teil (nach dem Loeschen E2065), ein Aufruf oder
// ein Property-Accessor einer Nachfahrenklasse (nach dem Loeschen E2003;
// bis zur Nachpruefung der Charge B1-FD nannte der Text nur SCA164).
// Gesucht wird im ROHTEXT, mit Absicht anders als im Puffer (Kopf der Unit:
// "Kommentare zaehlen nicht"): im Include zaehlt jedes Wort, auch in einem
// Kommentar - eine Sperre zu viel, nie eine zu wenig - und in einem
// String-Literal (dort ist es wie im Puffer ein Aufruf per Name). AMap
// bleibt fuer diesen Test ungenutzt; die Form von TRdxIncludeTest teilen
// sich SCA164/SCA147 und SCA014 (Review Woche G05-20).
function NameInInclude(const AFile: string; ALines: TStrings;
  AMap: TRdxCodeMap; const AArg: string): string;
begin
  Result := '';
  if HasIdentWord(LowerCase(ALines.Text), LowerCase(AArg)) then
    Result := Format('das Include %s nennt %s - als Deklaration (nach dem '
      + 'Loeschen E2065), Aufruf oder Property-Accessor (E2003), die Hilfe '
      + 'sieht es nicht', [AFile, AArg]);
end;

{ TRdxRoutineFixes }

class function TRdxRoutineFixes.IncludeReason(const AUnitFile: string;
  const AIncludes: TArray<string>; const AName: string): string;
var
  Check : TRdxIncludeCheck;
begin
  Check.Test := NameInInclude;
  Check.Arg := AName;
  Check.MissingFmt := R_INC_MISSING;
  Result := IncludeChainReason(AUnitFile, AIncludes, Check);
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
    AReason := TRdxBlocks.ReadRoutine(AMap, Head, R);
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
    AReason := TRdxBlocks.MethodDecl(AMap, Head, D);
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
  Result := HasIdentWord(LowerCase(AFormText), LowerCase(AName));
end;

end.

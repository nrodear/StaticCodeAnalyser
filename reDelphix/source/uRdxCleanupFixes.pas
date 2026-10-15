unit uRdxCleanupFixes;

// reDelphix - Quick-Fixes "Aufraeumen", OHNE ToolsAPI und ohne Parser
// (Konzept_Editorhilfen_Recherche_2026-10-11, Abschnitt 6, Charge H3a):
//   SCA070 CommentedOutCode: den auskommentierten Bereich loeschen - eine
//          '//'-Zeile ganz, einen Kommentar hinter Code ab seiner Spalte
//          (der Leerraum am Zeilenende geht mit), die Inhaltszeilen eines
//          mehrzeiligen '{ }'/'(* *)' (41 % der Korpusfunde zeigen auf eine
//          Inhaltszeile, nicht auf den Oeffner) - die Begrenzer nur, wenn
//          der Kommentar danach leer ist.
//   SCA053 UnusedLocalVar: die Deklaration der ungenutzten Variable
//          loeschen - 'X: T;' samt Zeile (ein '//'-Kommentar dahinter mit,
//          ausser er traegt einen Marker - dann bleibt er als eigene
//          Zeile), 'A, X, B: T;' -> 'A, B: T;' (erstes/letztes Element,
//          auch ueber Zeilen), 'var' mit, wenn die Section leer wird,
//          inline 'var X: T;' als ganze Anweisung. Zielt ein
//          '// noinspection' darueber auf die Zeile, keine Hilfe - er gaelte
//          danach der Zeile dahinter (MarkerAboveCut).
// Beide sind bedeutungsgleich. GRENZE SCA070: ein '// noinspection' direkt
// ueber der geloeschten Region zielt danach auf die naechste nicht leere
// Zeile - meist die Code-Zeile, die er ohnehin traf; nur wenn dort wieder
// ein '//'-Kommentar steht oder die Region aus Zeilen eines '{ }' bestand,
// wandert er (Nachpruefung B1-FD, nicht gesperrt: die Sperre traefe vor
// allem den harmlosen Fall '// noinspection X' / '// alter Code' / Code).
//
// WIE VIEL SCA070 LOESCHT (Detektor uCommentedOutCode gelesen): er bewertet
// JEDE Zeile einzeln (ein Kommentarstueck mit mindestens zwei Code-Merkmalen,
// eines davon stark) und fasst gemeldete Zeilen zu EINER Region zusammen,
// solange dazwischen nur reine Kommentarzeilen stehen - eine Leerzeile, Code
// oder eine zeilenfuehrende Direktive beendet sie. Die Meldung nennt Spalte
// und Zeilenzahl der Region ('Comment at column C' bzw. 'block of N lines
// starting at column C'), die Zeile ist ihre erste. Der Fund deckt also die
// Zeilen R1..R1+N-1 ab (R1, C) ab - NICHT den ganzen Blockkommentar: ein
// '{ ... }' ueber 200 Zeilen mit Leerzeilen darin ergibt mehrere Funde, und
// Prosa vor oder hinter der Region hat der Detektor nicht als Code gemeldet.
// Deshalb loescht die Hilfe nur die Region; die Begrenzer gehen erst mit,
// wenn der Kommentar danach nur noch Leerraum traegt (der letzte Fund eines
// Blocks raeumt auf). Ein Begrenzer wird nie halbiert.
//
// GRUNDSATZ wie in uRdxSimpleFixes: lieber keine Hilfe als eine falsche -
// der Planer prueft den Fund am aktuellen Text nach, statt dem Detektor zu
// glauben: SCA070 ueber die Kommentarklasse der Code-Sicht (zeilen-
// uebergreifend) und das Code-Merkmal der ersten und letzten Zeile, SCA053
// ueber die Vorkommen des Namens im Rohtext der Routine (die Code-Sicht
// liest Code unter einer inaktiven Direktive und in asm als Code - beides
// zaehlt als Verwendung). Was den Namen verwenden kann, ohne ihn als Code zu
// tragen, sperrt (Gegen-Review H3, Charge H3c): ein {$I}-Include, eine
// Direktive mit dem Namen und asm im Gueltigkeitsbereich (Stack-Rahmen),
// ein FPC-Makro mit dem Namen in der Datei.

interface

uses
  uRdxBufferMath, uRdxCodeMap;

type
  // Eine Stelle im Text: Zeile und Spalte (1-basiert, in Zeichen wie die
  // Code-Sicht).
  TRdxTextPos = record
    Line : Integer;
    Col  : Integer;
  end;

  // Die Planer der Charge H3a (s. Kopf): je Fund EINE Ersetzung oder der
  // Grund, warum keine - auf dem Puffertext ueber die Code-Sicht, ohne
  // ToolsAPI und Parser (laeuft auch im FPC-Pruefstand). Der Aufrufer ist
  // die Tabelle uRdxFixTable (MapFix).
  TRdxCleanupFixes = class
  public
    // SCA070: die Region der Meldung ('Comment at column C ...' bzw.
    // 'Commented-out code block of N lines starting at column C ...') ab
    // ALine loeschen. Gegenprobe: ab (ALine, C) bis zum Ende der letzten
    // Zeile nur Kommentar und Leerraum, die Spalte am Anfang eines
    // Kommentars bzw. einer Inhaltszeile, erste und letzte Zeile mit
    // Code-Merkmal wie im Detektor. Keine Hilfe bei einer Direktive im
    // Bereich, einem Doku-Kommentar ('///', '{*', '(**'), einem Kommentar
    // vor dem ersten Code der Datei (Lizenz-/Kopfkommentar), 'noinspection'
    // oder einem Absichtsmarker wie bei SCA019 im geloeschten Text und
    // wenn mehrere Kommentare in der Region stehen und einer mit Text ueber
    // sie hinausreicht (der Schnitt waere nicht zusammenhaengend).
    class function CommentedOutCode(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // SCA053: die Deklaration des Namens aus der Meldung ('Unused local
    // variable: X (declared but never read or written)') auf ALine bzw.
    // ihren Fortsetzungszeilen loeschen. Gegenprobe auf dem Rohtext: der
    // Name kommt vom Routinenkopf (inline: vom var) bis zum Ende des
    // Gueltigkeitsbereichs (inline: das end des Blocks bzw. das Ende der
    // until-Bedingung; ein 'End := 1' als benanntes Argument beendet ihn
    // nicht) sonst nirgends als Code vor - hinter '.' steht
    // ein Member, keine Verwendung. Keine Hilfe bei 'for var', einem
    // Schluesselwort als Name ('resourcestring'), einer const-/
    // resourcestring-Section, einem Initialisierer ('= 5', ':= F()'),
    // 'absolute', einem Typ ueber mehrere Zeilen (record), einem Attribut,
    // einem Kommentar im geloeschten Text, einer Direktive in der Deklaration bzw. ihrer
    // var-Section und einem 'class operator Initialize/Finalize' in der
    // Unit (verwalteter Record: die Variable fuehrt Code aus); seit Charge
    // H3c auch bei einer Deklaration in einer offenen Klammer (Parameter),
    // einem {$I}-Include, einer Direktive mit dem Namen oder asm im
    // Gueltigkeitsbereich und einem FPC-Makro mit dem Namen in der Datei;
    // seit der Nachpruefung der Charge B1-FD bei einem '// noinspection'
    // darueber, der auf die Zeile zielt (MarkerAboveCut).
    class function UnusedLocalVar(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // X aus 'Unused local variable: X (declared but never read or
    // written)'; '' ohne diese Form.
    class function UnusedVarName(const AMessage: string): string; static;
  end;

// Die Stelle (ALine, ACol) als TRdxTextPos.
function TextPos(ALine, ACol: Integer): TRdxTextPos;

// Gemeinsamer Baustein (Charge H3, "loeschen und aufraeumen"): den Text von
// AFrom bis vor ATo loeschen und die Zeilen aufraeumen -
//   * vor AFrom und hinter ATo nur Leerraum: die ganzen Zeilen samt
//     Zeilenende (endet ATo am Zeilenanfang, bleibt dessen Zeile ganz);
//   * vor AFrom nur Leerraum, dahinter Text: der Text rueckt an die
//     Einrueckung;
//   * vor AFrom Text, dahinter nichts: ab dem Ende des Textes (kein
//     Leerraum am Zeilenende);
//   * Text auf beiden Seiten: der Leerraum dazwischen wird zu einem
//     Leerzeichen, wo schon eines stand oder zwei Token sonst verschmoelzen
//     ('begin{x}end' -> 'begin end', 'A, X: T' -> 'A: T').
// Ein Bereich beginnt auf einem Zeichen (SpanFits): liegt AFrom hinter
// einem Zeilenende oder auf einer leeren Zeile, beginnt der Schnitt auf der
// naechsten Zeile (das Zeilenende bleibt). Die letzte Zeile der Datei hat
// kein Zeilenende dahinter: dann geht das davor mit. '' oder der Grund; die
// Ersetzung in AEdit.
function CutEdit(AMap: TRdxCodeMap; const AFrom, ATo: TRdxTextPos;
  const ARole: string; out AEdit: TRdxEdit): string;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxStructFixes,   // RangeText, CommentInRange
  uRdxRoutineFixes;  // ReadRoutine (SCA053: Ende des Gueltigkeitsbereichs),
                     // MarkerAboveReason (Marker ueber der Deklaration)

const
  SPAN_070 = 'sca070';
  SPAN_053 = 'sca053';
  KEY_ONE     = 'Comment at column ';
  KEY_BLOCK   = 'Commented-out code block of ';
  KEY_START   = ' lines starting at column ';
  KEY_VAR     = 'Unused local variable: ';
  KEY_VAR_END = ' (';
  R_MOVED = 'Zeile verschoben? Datei neu pruefen';
  // Zahlen aus einer Meldung - darueber ist sie kaputt (kein Ueberlauf).
  MAX_NUMBER = 10000000;
  // SCA053: Schluesselwoerter von Delphi - kein Variablenname (17
  // Korpusfunde nennen 'resourcestring': der Parser las die Section als
  // Variable).
  RESERVED: array[0..63] of string = ('and', 'array', 'as', 'asm', 'begin',
    'case', 'class', 'const', 'constructor', 'destructor', 'dispinterface',
    'div', 'do', 'downto', 'else', 'end', 'except', 'exports', 'file',
    'finalization', 'finally', 'for', 'function', 'goto', 'if',
    'implementation', 'in', 'inherited', 'initialization', 'inline',
    'interface', 'is', 'label', 'library', 'mod', 'nil', 'not', 'object',
    'of', 'or', 'packed', 'procedure', 'program', 'property', 'raise',
    'record', 'repeat', 'resourcestring', 'set', 'shl', 'shr', 'string',
    'then', 'threadvar', 'to', 'try', 'type', 'unit', 'until', 'uses', 'var',
    'while', 'with', 'xor');
  // Abschnitte eines Deklarationsteils.
  SECTION_WORDS: array[0..5] of string = ('var', 'const', 'type',
    'resourcestring', 'label', 'threadvar');
  UNIT_BOUNDS: array[0..4] of string = ('implementation', 'interface',
    'program', 'library', 'unit');
  // Rueckwaerts: Paare mit 'end' bzw. 'until'.
  BLOCK_PAIRS: array[0..5] of string = ('begin', 'try', 'case', 'asm',
    'record', 'repeat');
  // Vor der ersten Anweisung einer Anweisungsliste.
  LIST_OPENERS: array[0..6] of string = ('begin', 'try', 'finally', 'except',
    'repeat', 'initialization', 'finalization');
  LIST_ENDS: array[0..3] of string = ('end', 'until', 'except', 'finally');
  // Typen ueber mehrere Zeilen ('X: record ... end;') - ihr ';' ist nicht
  // das Ende der Deklaration.
  MULTI_LINE_TYPES: array[0..5] of string = ('record', 'object', 'class',
    'interface', 'dispinterface', 'packed');
  // Im Typ einer Variablen steht keines davon - sonst ist die Zeile keine.
  TYPE_STOPS: array[0..8] of string = ('begin', 'end', 'var', 'const',
    'type', 'label', 'resourcestring', 'implementation', 'uses');
  // Hinter dem ';' eines prozeduralen Typs: gehoert noch zur Deklaration.
  CALL_CONVENTIONS: array[0..6] of string = ('stdcall', 'cdecl', 'register',
    'pascal', 'safecall', 'winapi', 'varargs');
  // Hinter dem Namen eines weiteren Section-Eintrags ('Name ,' / 'Name :').
  ITEM_FOLLOW: array[0..1] of string = (',', ':');
  // So viele lokale Routinen vor einer var-Section ueberspringt die Suche
  // nach ihrer Routine (OwnerRoutine).
  MAX_OWNER_STEPS = 64;
  // Stehen in keiner Parameterliste - rueckwaerts endet dort die Suche nach
  // einer offenen Klammer (InOpenParen).
  PAREN_STOPS: array[0..3] of string = ('begin', 'end', 'implementation',
    'interface');
  // FPC-Makro: '{$DEFINE M := X}' (MacroReason).
  MACRO_WORDS: array[0..1] of string = ('define', 'definec');
  MACRO_ASSIGN = ':=';
  // Die zweite Haelfte eines UTF-16-Surrogatpaars (LinesCut).
  LOW_SURROGATE_FIRST = $DC00;
  LOW_SURROGATE_LAST  = $DFFF;

type
  // SCA070: die Region der Meldung.
  TRdxRegion = record
    First : Integer;   // R1, die gemeldete Zeile
    Last  : Integer;   // R1 + N - 1
    Col   : Integer;   // C
  end;

  // Ein Kommentar der Datei.
  TRdxComment = record
    Open      : TRdxTextPos;   // erstes Zeichen des Oeffners
    Body      : TRdxTextPos;   // erstes Zeichen hinter dem Oeffner
    Close     : TRdxTextPos;   // erstes Zeichen des Schliessers ('//': Zeilenende)
    Stop      : TRdxTextPos;   // hinter dem Schliesser
    Closer    : string;        // '}' bzw. '*)', '' bei '//'
    Directive : Boolean;       // '{$' bzw. '(*$'
    Doc       : Boolean;       // '///', '{*', '(**' - Dokumentation
    Closed    : Boolean;       // False: offen bis zum Dateiende
  end;

  TRdxCommentList = array of TRdxComment;

  // SCA053: die Deklaration um den gemeldeten Namen.
  TRdxVarDecl = record
    Name    : TRdxToken;   // X
    First   : TRdxToken;   // erster Name der Gruppe
    Last    : TRdxToken;   // letzter Name der Gruppe
    Count   : Integer;     // Namen der Gruppe
    Lead    : TRdxToken;   // Token vor der Gruppe: var, ';', ']' ...
    Colon   : TRdxToken;   // Token hinter der Gruppe (':' erwartet)
    Semi    : TRdxToken;   // ';' am Ende der Deklaration
    VarTok  : TRdxToken;   // 'var' der Section bzw. der Inline-Deklaration
    InBlock : Boolean;     // Inline-Deklaration in einem Anweisungsblock
    Stop    : TRdxToken;   // Ende der Rueckwaerts-Suche: Kopf bzw. Blockoeffner
  end;

{ ---- gemeinsam ---- }

function TextPos(ALine, ACol: Integer): TRdxTextPos;
begin
  Result.Line := ALine;
  Result.Col := ACol;
end;

// A liegt vor B.
function PosBefore(const A, B: TRdxTextPos): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Col < B.Col));
end;

function TokPos(const T: TRdxToken): TRdxTextPos;
begin
  Result := TextPos(T.Line, T.Col);
end;

// Hinter dem letzten Zeichen von T.
function TokEnd(const T: TRdxToken): TRdxTextPos;
begin
  Result := TextPos(T.Line, T.EndCol);
end;

// T liegt hinter ATo (uRdxCodeMap.TokBefore umgekehrt; bis Charge H4c
// ueber PosBefore/TokPos gerechnet).
function TokAfter(const T, ATo: TRdxToken): Boolean;
begin
  Result := TokBefore(ATo, T);
end;

function SpanOf(const AFrom, ATo: TRdxTextPos;
  const ARole: string): TRefactorSpan;
begin
  Result := TRefactorSpan.Make(ARole, AFrom.Line, AFrom.Col, ATo.Line,
    ATo.Col);
end;

// Klammertiefe: '(' und '[' +1, ')' und ']' -1, sonst 0.
function ParenDelta(const T: TRdxToken): Integer;
begin
  Result := 0;
  if (T.Low = '(') or (T.Low = '[') then
    Result := 1
  else if (T.Low = ')') or (T.Low = ']') then
    Result := -1;
end;

// Die Zahl ab S[AAt] (Ziffern); 0 ohne.
function NumberAt(const S: string; AAt: Integer): Integer;
begin
  Result := 0;
  while (AAt <= Length(S)) and CharInSet(S[AAt], ['0'..'9'])
        and (Result < MAX_NUMBER) do
  begin
    Result := Result * 10 + Ord(S[AAt]) - Ord('0');
    Inc(AAt);
  end;
end;

// Steht von AFrom bis vor ATo nur Leerraum (Zeilenenden eingeschlossen)?
function BlankText(AMap: TRdxCodeMap; const AFrom, ATo: TRdxTextPos): Boolean;
begin
  Result := not PosBefore(AFrom, ATo)
    or (Trim(RangeText(AMap, SpanOf(AFrom, ATo, SPAN_070))) = '');
end;

{ ---- CutEdit: loeschen und aufraeumen ---- }

// Die zweite Haelfte eines UTF-16-Surrogatpaars? (Zweite Kopie neben
// uRdxTryFixes.IsSecondHalf - die Zusammenlegung der geteilten Helfer ist
// eine eigene Charge.)
function IsLowSurrogate(C: Char): Boolean;
begin
  Result := (Ord(C) >= LOW_SURROGATE_FIRST) and (Ord(C) <= LOW_SURROGATE_LAST);
end;

// Die ganzen Zeilen AFirst..ALast samt Zeilenende loeschen (bis Charge
// H3c LinesEdit - gleich benannt wie die Ersetzung ganzer Zeilen in
// uRdxRoutineFixes, mit anderem Vertrag; Minor 5). Ein Bereich
// beginnt auf einem Zeichen (SpanFits: weder hinter einem Zeilenende noch
// auf einer leeren Zeile). Ist AFirst leer oder steht hinter ALast (letzte
// Zeile der Datei) kein Zeilenende, beginnt er deshalb AUF dem letzten
// Zeichen der naechsten nicht leeren Zeile P davor, das neu geschrieben
// wird - samt den Zeilenenden der Leerzeilen zwischen P und AFirst, die
// bleiben. Ist dieses Zeichen die zweite Haelfte eines Surrogatpaars
// (Emoji in einem Kommentar), beginnt er auf der ersten: sonst schnitte er
// mitten im Zeichen, und PlanByteEdits lehnte jeden Klick ab (Gegen-Review
// R4-09; wie uRdxTryFixes.TryEdit). '' oder der Grund.
function LinesCut(AMap: TRdxCodeMap; AFirst, ALast: Integer;
  const ARole: string; out AEdit: TRdxEdit): string;
var
  P, Col : Integer;
  L      : string;
begin
  Result := '';
  AEdit := Default(TRdxEdit);
  if (AMap.Raw(AFirst) <> '') and (ALast < AMap.LineCount) then
  begin
    AEdit.Span := TRefactorSpan.Make(ARole, AFirst, 1, ALast + 1, 1);
    AEdit.Expected := RangeText(AMap, AEdit.Span);
    Exit;
  end;
  P := AFirst - 1;
  while (P >= 1) and (AMap.Raw(P) = '') do
    Dec(P);
  if P < 1 then
    Exit('vor dem Bereich steht nichts, und er reicht bis zum Dateiende - '
      + 'von Hand loeschen');
  L := AMap.Raw(P);
  Col := Length(L);
  if (Col > 1) and IsLowSurrogate(L[Col]) then
    Dec(Col);
  // Es bleiben die Zeilenenden von P bis AFirst - 1; hinter der letzten
  // Zeile der Datei liegt das von ALast ausserhalb des Bereichs und
  // uebernimmt das von AFirst - 1.
  if ALast < AMap.LineCount then
  begin
    AEdit.Span := TRefactorSpan.Make(ARole, P, Col, ALast + 1, 1);
    AEdit.NewText := Copy(L, Col, MaxInt) + StringOfChar(#10, AFirst - P);
  end
  else
  begin
    AEdit.Span := TRefactorSpan.Make(ARole, P, Col, ALast,
      Length(AMap.Raw(ALast)) + 1);
    AEdit.NewText := Copy(L, Col, MaxInt)
      + StringOfChar(#10, AFirst - 1 - P);
  end;
  AEdit.Expected := RangeText(AMap, AEdit.Span);
end;

// Vor AFrom nur Leerraum, hinter ATo Text: der Text rueckt an die
// Einrueckung (sie bleibt), der Leerraum vor ihm geht mit.
function IndentCut(AMap: TRdxCodeMap; const AFrom, ATo: TRdxTextPos;
  const ARole: string): TRdxEdit;
var
  S, E : TRdxTextPos;
begin
  Result := Default(TRdxEdit);
  S := TextPos(AFrom.Line, SkipBlanks(AMap.Raw(AFrom.Line), AFrom.Col));
  E := TextPos(ATo.Line, SkipBlanks(AMap.Raw(ATo.Line), ATo.Col));
  if not PosBefore(S, E) then
    S := AFrom;
  Result.Span := SpanOf(S, E, ARole);
  Result.Expected := RangeText(AMap, Result.Span);
end;

// Vor AFrom Text, hinter ATo nur Leerraum: ab dem Ende des Textes (der
// Leerraum davor geht mit) bis zum Zeilenende.
function TailCut(AMap: TRdxCodeMap; const AFrom, ATo: TRdxTextPos;
  const ARole: string): TRdxEdit;
var
  L   : string;
  Col : Integer;
begin
  Result := Default(TRdxEdit);
  L := AMap.Raw(AFrom.Line);
  Col := AFrom.Col;
  while (Col > 1) and IsBlank(L[Col - 1]) do
    Dec(Col);
  Result.Span := TRefactorSpan.Make(ARole, AFrom.Line, Col, ATo.Line,
    Length(AMap.Raw(ATo.Line)) + 1);
  Result.Expected := RangeText(AMap, Result.Span);
end;

// Muss zwischen den Resten ein Leerzeichen stehen? Nicht, wenn davor ein
// Bezeichner, ')', ']' oder ein String endet und dahinter ein Trenner
// folgt ('A, X: T' -> 'A: T'); sonst ja - zwei Woerter verschmoelzen
// ('begin{x}end'), zwei Zeichen ergaeben ein neues Token ('(' und '*'
// oeffneten einen Kommentar, ':' und '=' eine Zuweisung).
function NeedsBlank(ABefore, AAfter: Char): Boolean;
begin
  Result := not (CharInSet(AAfter, [',', ';', ':', ')', ']'])
    and (IsIdentChar(ABefore) or CharInSet(ABefore, [')', ']', ''''])));
end;

// Text auf beiden Seiten: der Leerraum um den Schnitt geht mit; ein
// Leerzeichen bleibt, wo schon eines stand oder NeedsBlank es verlangt.
function JoinCut(AMap: TRdxCodeMap; const AFrom, ATo: TRdxTextPos;
  const ARole: string): TRdxEdit;
var
  LS, LE   : string;
  SC, EC   : Integer;
begin
  Result := Default(TRdxEdit);
  LS := AMap.Raw(AFrom.Line);
  LE := AMap.Raw(ATo.Line);
  SC := AFrom.Col;
  while (SC > 1) and IsBlank(LS[SC - 1]) do
    Dec(SC);
  EC := SkipBlanks(LE, ATo.Col);
  Result.Span := TRefactorSpan.Make(ARole, AFrom.Line, SC, ATo.Line, EC);
  Result.Expected := RangeText(AMap, Result.Span);
  if (SC < AFrom.Col) or (EC > ATo.Col) or NeedsBlank(LS[SC - 1], LE[EC]) then
    Result.NewText := ' ';
end;

// Der Schnitt ab einem Zeichen (CutEdit): die vier Faelle des Kopfs.
function CutFrom(AMap: TRdxCodeMap; const AFrom, ATo: TRdxTextPos;
  const ARole: string; out AEdit: TRdxEdit): string;
var
  LeadBlank, TailBlank : Boolean;
begin
  Result := '';
  AEdit := Default(TRdxEdit);
  if not PosBefore(AFrom, ATo) then
    Exit('leerer Bereich');
  LeadBlank := SkipBlanks(AMap.Raw(AFrom.Line), 1) >= AFrom.Col;
  TailBlank := SkipBlanks(AMap.Raw(ATo.Line), ATo.Col)
    > Length(AMap.Raw(ATo.Line));
  if LeadBlank and (ATo.Col = 1) then
    Result := LinesCut(AMap, AFrom.Line, ATo.Line - 1, ARole, AEdit)
  else if LeadBlank and TailBlank then
    Result := LinesCut(AMap, AFrom.Line, ATo.Line, ARole, AEdit)
  else if LeadBlank then
    AEdit := IndentCut(AMap, AFrom, ATo, ARole)
  else if TailBlank then
    AEdit := TailCut(AMap, AFrom, ATo, ARole)
  else
    AEdit := JoinCut(AMap, AFrom, ATo, ARole);
  if (Result = '') and (AEdit.Expected = '') then
    Result := 'leerer Bereich';
end;

function CutEdit(AMap: TRdxCodeMap; const AFrom, ATo: TRdxTextPos;
  const ARole: string; out AEdit: TRdxEdit): string;
var
  From : TRdxTextPos;
begin
  // Beginnt der Schnitt hinter einem Zeilenende oder auf einer leeren Zeile
  // (SCA070: '(*' allein auf der Zeile, der Kommentar bleibt), beginnt er
  // auf der naechsten Zeile - das Zeilenende bleibt.
  From := AFrom;
  while (From.Col > Length(AMap.Raw(From.Line))) and (From.Line < ATo.Line) do
    From := TextPos(From.Line + 1, 1);
  Result := CutFrom(AMap, From, ATo, ARole, AEdit);
end;

{ ---- SCA070 ---- }

// Zeilenzahl und Spalte aus der Meldung; False ohne diese Form.
function RegionOf(const AMessage: string; ALine: Integer;
  out ARegion: TRdxRegion): Boolean;
var
  P, N : Integer;
begin
  ARegion := Default(TRdxRegion);
  ARegion.First := ALine;
  N := 0;
  if Pos(KEY_ONE, AMessage) = 1 then
  begin
    N := 1;
    ARegion.Col := NumberAt(AMessage, Length(KEY_ONE) + 1);
  end
  else if Pos(KEY_BLOCK, AMessage) = 1 then
  begin
    N := NumberAt(AMessage, Length(KEY_BLOCK) + 1);
    P := Pos(KEY_START, AMessage);
    if P > 0 then
      ARegion.Col := NumberAt(AMessage, P + Length(KEY_START));
  end;
  ARegion.Last := ALine + N - 1;
  Result := (N > 0) and (N < MAX_NUMBER) and (ARegion.Col > 0);
end;

// Ab (R1, C) bis zum Ende von R2 nur Kommentar und Leerraum? '' oder der
// Grund.
function RegionReason(AMap: TRdxCodeMap; const ARegion: TRdxRegion): string;
var
  Li, Co, From : Integer;
  L            : string;
begin
  Result := '';
  if ARegion.Last > AMap.LineCount then
    Exit(Format('der Fund reicht bis Zeile %d, die Datei hat %d Zeilen - %s',
      [ARegion.Last, AMap.LineCount, R_MOVED]));
  if AMap.ClassAt(ARegion.First, ARegion.Col) <> 'k' then
    Exit(Format('an Zeile %d Spalte %d steht kein Kommentar - %s',
      [ARegion.First, ARegion.Col, R_MOVED]));
  for Li := ARegion.First to ARegion.Last do
  begin
    L := AMap.Raw(Li);
    From := 1;
    if Li = ARegion.First then
      From := ARegion.Col;
    for Co := From to Length(L) do
      if not IsBlank(L[Co]) and (AMap.ClassAt(Li, Co) <> 'k') then
        Exit(Format('Zeile %d traegt neben dem Kommentar Code oder Text '
          + '(Spalte %d) - von Hand loeschen', [Li, Co]));
  end;
end;

// Der Schliesser ab AComment.Body suchen (die erste Fundstelle - '{ }'
// schachtelt nicht, wie in der Code-Sicht).
procedure FindCloser(AMap: TRdxCodeMap; var AComment: TRdxComment);
var
  Li, P : Integer;
begin
  Li := AComment.Body.Line;
  P := Pos(AComment.Closer, AMap.Raw(Li), AComment.Body.Col);
  while (P = 0) and (Li < AMap.LineCount) do
  begin
    Inc(Li);
    P := Pos(AComment.Closer, AMap.Raw(Li));
  end;
  if P = 0 then
  begin
    AComment.Close := TextPos(Li, Length(AMap.Raw(Li)) + 1);
    AComment.Stop := AComment.Close;
    Exit;
  end;
  AComment.Close := TextPos(Li, P);
  AComment.Stop := TextPos(Li, P + Length(AComment.Closer));
  AComment.Closed := True;
end;

// Der Kommentar, der an (ALine, ACol) beginnt; False, wenn dort kein
// Oeffner steht.
function CommentAt(AMap: TRdxCodeMap; ALine, ACol: Integer;
  out AComment: TRdxComment): Boolean;
var
  L : string;
begin
  AComment := Default(TRdxComment);
  L := AMap.Raw(ALine);
  AComment.Open := TextPos(ALine, ACol);
  Result := True;
  if Copy(L, ACol, 2) = '//' then
  begin
    AComment.Body := TextPos(ALine, ACol + 2);
    AComment.Close := TextPos(ALine, Length(L) + 1);
    AComment.Stop := AComment.Close;
    AComment.Closed := True;
    AComment.Doc := Copy(L, ACol, 3) = '///';
    Exit;
  end;
  if Copy(L, ACol, 1) = '{' then
    AComment.Closer := '}'
  else if Copy(L, ACol, 2) = '(*' then
    AComment.Closer := '*)'
  else
    Exit(False);
  AComment.Body := TextPos(ALine, ACol + Length(AComment.Closer));
  AComment.Directive := Copy(L, AComment.Body.Col, 1) = '$';
  FindCloser(AMap, AComment);
  // '{*' ist die Doku der CnPack-Quellen ('{* Kommentar zur Deklaration
  // darueber }' - Korpus: 24 Funde in cnwizards, Prosa mit 'function' und
  // 'begin' darin); '(**' ohne '(**)' ist PasDoc.
  if AComment.Closer = '}' then
    AComment.Doc := Copy(L, AComment.Body.Col, 1) = '*'
  else
    AComment.Doc := (Copy(L, AComment.Body.Col, 1) = '*')
      and PosBefore(AComment.Body, AComment.Close);
end;

procedure AddComment(var AList: TRdxCommentList; const AComment: TRdxComment);
begin
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := AComment;
end;

// Die Kommentare, die die Region beruehren (ab (R1, C) bis zum Ende von
// R2), der Reihe nach. Gelesen wird ab der letzten Zeile davor, die nicht
// in einem Kommentar beginnt - dort ist der Zustand sicher Code; jedes 'k'
// ausserhalb eines Kommentars ist dann ein Oeffner. '' oder der Grund.
function RegionComments(AMap: TRdxCodeMap; const ARegion: TRdxRegion;
  out AList: TRdxCommentList): string;
var
  Li, Co : Integer;
  C      : TRdxComment;
  From   : TRdxTextPos;
begin
  Result := '';
  AList := nil;
  From := TextPos(ARegion.First, ARegion.Col);
  Li := ARegion.First;
  while (Li > 1) and AMap.StartsInside(Li) do
    Dec(Li);
  Co := 1;
  while Li <= ARegion.Last do
    if Co > Length(AMap.Raw(Li)) then
    begin
      Inc(Li);
      Co := 1;
    end
    else if AMap.ClassAt(Li, Co) <> 'k' then
      Inc(Co)
    else
    begin
      if not CommentAt(AMap, Li, Co, C) then
        Exit(Format('Kommentar an Zeile %d Spalte %d nicht lesbar', [Li, Co]));
      if PosBefore(From, C.Stop) then
        AddComment(AList, C);
      if not C.Closed then
        Exit;
      Li := C.Stop.Line;
      Co := C.Stop.Col;
    end;
end;

// Beginnt der Fund am Oeffner seines Kommentars bzw. - bei einer
// Inhaltszeile - am Zeilenanfang? '' oder der Grund.
function StartReason(AMap: TRdxCodeMap; const ARegion: TRdxRegion;
  const AFirst: TRdxComment): string;
begin
  Result := '';
  if (AFirst.Open.Line = ARegion.First) and (AFirst.Open.Col = ARegion.Col) then
    Exit;
  if (AFirst.Open.Line < ARegion.First)
     and (SkipBlanks(AMap.Raw(ARegion.First), 1) >= ARegion.Col) then
    Exit;
  Result := Format('Spalte %d zeigt mitten in einen Kommentar - %s',
    [ARegion.Col, R_MOVED]);
end;

// Die Sperren je Kommentar: Direktive, Doku, offenes Ende - und ein
// Kommentar vor dem ersten Code der Datei (Lizenz- oder Kopfkommentar).
function KindReason(AMap: TRdxCodeMap; const AList: TRdxCommentList): string;
var
  C : TRdxComment;
begin
  Result := '';
  for C in AList do
  begin
    if C.Directive then
      Exit(Format('Direktive im Bereich (Zeile %d) - sie ist aktiver Code, '
        + 'kein Kommentar', [C.Open.Line]));
    if C.Doc then
      Exit(Format('Doku-Kommentar (///, {* bzw. (**, Zeile %d) - sein '
        + 'Beispielcode bleibt', [C.Open.Line]));
    if not C.Closed then
      Exit('Kommentar ohne Ende bis zum Dateiende');
  end;
  if PrevToken(AMap, AList[0].Open.Line, AList[0].Open.Col).Low = '' then
    Result := 'Kommentar vor dem ersten Code der Datei (Lizenz- oder '
      + 'Kopfkommentar) - von Hand entscheiden';
end;

// Backtick-Spannen ('`code`') entfernen - wie der Detektor
// (StripBacktickCodeSpans): Doku zitiert dort Code.
function StripBackticks(const S: string): string;
var
  i, n  : Integer;
  InTick : Boolean;
begin
  Result := '';
  SetLength(Result, Length(S));
  n := 0;
  InTick := False;
  for i := 1 to Length(S) do
    if S[i] = '`' then
      InTick := not InTick
    else if not InTick then
    begin
      Inc(n);
      Result[n] := S[i];
    end;
  SetLength(Result, n);
end;

// Ein starkes Code-Merkmal wie im Detektor (HasStrongCodeMarker): das
// Stueck endet auf ';', traegt ':=' oder begin/procedure/function als Wort.
// Der Detektor verlangt procedure/function zusaetzlich in
// Deklarationsstellung - hier reicht das Wort (die Pruefung ist weiter als
// seine, sie lehnt also keinen seiner Funde ab).
function StrongMarker(const APiece: string): Boolean;
var
  S, Low : string;
begin
  S := Trim(StripBackticks(APiece));
  Low := LowerCase(S);
  Result := ((S <> '') and (S[Length(S)] = ';')) or (Pos(':=', S) > 0)
    or HasAsciiWord(Low, 'begin') or HasAsciiWord(Low, 'procedure')
    or HasAsciiWord(Low, 'function');
end;

// Der Inhalt von AComment auf ALine (ohne Begrenzer), ab Spalte AFrom.
function PieceOn(AMap: TRdxCodeMap; const AComment: TRdxComment;
  ALine, AFrom: Integer): string;
var
  A, B : Integer;
begin
  Result := '';
  if (ALine < AComment.Body.Line) or (ALine > AComment.Close.Line) then
    Exit;
  A := 1;
  if ALine = AComment.Body.Line then
    A := AComment.Body.Col;
  if A < AFrom then
    A := AFrom;
  B := Length(AMap.Raw(ALine)) + 1;
  if ALine = AComment.Close.Line then
    B := AComment.Close.Col;
  Result := Copy(AMap.Raw(ALine), A, B - A);
end;

// Traegt ein Kommentarstueck auf ALine (ab AFrom) ein Code-Merkmal? Der
// Detektor meldet nur solche Zeilen, und die erste und letzte Zeile einer
// Region sind gemeldete Zeilen - fehlt es, zeigt der Fund auf andere Zeilen.
function LineLooksLikeCode(AMap: TRdxCodeMap; const AList: TRdxCommentList;
  ALine, AFrom: Integer): Boolean;
var
  C : TRdxComment;
begin
  Result := False;
  for C in AList do
    if StrongMarker(PieceOn(AMap, C, ALine, AFrom)) then
      Exit(True);
end;

function MarkerOnLineReason(ALine: Integer): string;
begin
  Result := Format('Zeile %d sieht nicht nach Code aus (kein ";" am Ende, kein '
    + '":=", kein begin/procedure/function) - %s', [ALine, R_MOVED]);
end;

// Die Gegenproben am Kommentar: Anfang, Art, Code-Merkmal. '' oder der
// Grund.
function CommentReason(AMap: TRdxCodeMap; const ARegion: TRdxRegion;
  const AList: TRdxCommentList): string;
begin
  if Length(AList) = 0 then
    Exit('kein Kommentar an der gemeldeten Stelle - ' + R_MOVED);
  Result := StartReason(AMap, ARegion, AList[0]);
  if Result = '' then
    Result := KindReason(AMap, AList);
  if Result <> '' then
    Exit;
  if not LineLooksLikeCode(AMap, AList, ARegion.First, ARegion.Col) then
    Result := MarkerOnLineReason(ARegion.First)
  else if not LineLooksLikeCode(AMap, AList, ARegion.Last, 1) then
    Result := MarkerOnLineReason(ARegion.Last);
end;

// Wo der Schliesser von AComment beginnt; steht davor auf seiner Zeile nur
// Leerraum, der Zeilenanfang (die Zeile bleibt ganz).
function CloserStart(AMap: TRdxCodeMap; const AComment: TRdxComment): TRdxTextPos;
begin
  Result := AComment.Close;
  if SkipBlanks(AMap.Raw(Result.Line), 1) >= Result.Col then
    Result.Col := 1;
end;

// Was geloescht wird (s. Kopf): der Inhalt der Region; die Begrenzer nur,
// wenn der Kommentar danach leer ist. KeepFront: der erste Kommentar begann
// vor R1 und traegt davor Text; KeepBack: der letzte endet hinter R2 und
// traegt dahinter Text - dann bleibt der jeweilige Begrenzer. '' oder der
// Grund.
function CommentCut(AMap: TRdxCodeMap; const ARegion: TRdxRegion;
  const AList: TRdxCommentList; out AFrom, ATo: TRdxTextPos): string;
var
  F, G                : TRdxComment;
  KeepFront, KeepBack : Boolean;
begin
  Result := '';
  F := AList[0];
  G := AList[High(AList)];
  KeepFront := (F.Open.Line < ARegion.First)
    and not BlankText(AMap, F.Body, TextPos(ARegion.First, 1));
  KeepBack := (G.Close.Line > ARegion.Last)
    and not BlankText(AMap, TextPos(ARegion.Last + 1, 1), G.Close);
  AFrom := F.Open;
  ATo := G.Stop;
  if (Length(AList) > 1) and (KeepFront or KeepBack) then
    Exit('mehrere Kommentare, und einer reicht mit Text ueber den Fund '
      + 'hinaus - der Schnitt waere nicht zusammenhaengend; von Hand loeschen');
  if KeepFront then
    AFrom := TextPos(ARegion.First, 1)
  else if KeepBack then
    AFrom := F.Body;
  if KeepBack then
    ATo := TextPos(ARegion.Last, Length(AMap.Raw(ARegion.Last)) + 1)
  else if KeepFront then
    ATo := CloserStart(AMap, G);
end;

class function TRdxCleanupFixes.CommentedOutCode(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  Region            : TRdxRegion;
  List              : TRdxCommentList;
  CutStart, CutStop : TRdxTextPos;
begin
  AEdit := Default(TRdxEdit);
  List := nil;
  CutStart := TextPos(0, 0);
  CutStop := TextPos(0, 0);
  if not RegionOf(AMessage, ALine, Region) then
    AReason := 'Spalte oder Zeilenzahl fehlt in der Meldung'
  else
    AReason := RegionReason(AMap, Region);
  if AReason = '' then
    AReason := RegionComments(AMap, Region, List);
  if AReason = '' then
    AReason := CommentReason(AMap, Region, List);
  if AReason = '' then
    AReason := CommentCut(AMap, Region, List, CutStart, CutStop);
  if AReason = '' then
    AReason := MarkerReason(RangeText(AMap, SpanOf(CutStart, CutStop,
      SPAN_070)));
  if AReason = '' then
    AReason := CutEdit(AMap, CutStart, CutStop, SPAN_070, AEdit);
  Result := AReason = '';
end;

{ ---- SCA053 ---- }

class function TRdxCleanupFixes.UnusedVarName(const AMessage: string): string;
var
  Q : Integer;
begin
  Result := '';
  if Pos(KEY_VAR, AMessage) <> 1 then
    Exit;
  Q := Pos(KEY_VAR_END, AMessage, Length(KEY_VAR) + 1);
  if Q = 0 then
    Q := Length(AMessage) + 1;
  Result := Trim(Copy(AMessage, Length(KEY_VAR) + 1, Q - Length(KEY_VAR) - 1));
end;

// Liest NameOn das Token T noch (auf ALine oder einer Fortsetzungszeile:
// die vorige endet mit ',')?
function InGroupLines(const T, APrev: TRdxToken; ALine: Integer): Boolean;
begin
  Result := (T.Low <> '')
    and ((T.Line = ALine) or (T.Line = APrev.Line) or (APrev.Low = ','));
end;

// Der eine Name AKey auf ALine bzw. ihren Fortsetzungszeilen (der Detektor
// meldet die Zeile des ersten Namens einer Gruppe). Hinter '.' steht ein
// Member. '' oder der Grund.
function NameOn(AMap: TRdxCodeMap; ALine: Integer; const AKey: string;
  out AHit: TRdxToken): string;
var
  T, Prev : TRdxToken;
  n       : Integer;
begin
  AHit := Default(TRdxToken);
  n := 0;
  Prev := Default(TRdxToken);
  T := NextToken(AMap, ALine, 1);
  while InGroupLines(T, Prev, ALine) do
  begin
    if T.IsWord and SameIdent(T.Low, AKey) and (Before(AMap, T).Low <> '.') then
    begin
      Inc(n);
      AHit := T;
    end;
    Prev := T;
    T := After(AMap, T);
  end;
  Result := OneTokenReason(ALine, n, Format('kein "%s"', [AKey]),
    Format('%%d-mal "%s"', [AKey]));
end;

// Die Namensgruppe um ADecl.Name ('A, X, B'): erster und letzter Name,
// Zahl, das Token davor und dahinter. '' oder der Grund.
function GroupOf(AMap: TRdxCodeMap; var ADecl: TRdxVarDecl): string;
var
  P, W : TRdxToken;
begin
  Result := '';
  ADecl.First := ADecl.Name;
  ADecl.Last := ADecl.Name;
  ADecl.Count := 1;
  P := Before(AMap, ADecl.Name);
  while P.Low = ',' do
  begin
    W := Before(AMap, P);
    if not W.IsWord then
      Exit('Namensliste nicht lesbar');
    ADecl.First := W;
    Inc(ADecl.Count);
    P := Before(AMap, W);
  end;
  ADecl.Lead := P;
  P := After(AMap, ADecl.Name);
  while P.Low = ',' do
  begin
    W := After(AMap, P);
    if not W.IsWord then
      Exit('Namensliste nicht lesbar');
    ADecl.Last := W;
    Inc(ADecl.Count);
    P := After(AMap, W);
  end;
  ADecl.Colon := P;
end;

// Ein Token des Typs auf oberster Klammerebene: Initialisierer, absolute,
// Typ ueber mehrere Zeilen oder ein Wort, das in keinem Typ steht? '' oder
// der Grund.
function TypeTokenReason(const T, APrev: TRdxToken): string;
begin
  Result := '';
  if (T.Low = '=') or (T.Low = ':=') then
    Result := 'initialisierte Variable - der Ausdruck kann Seiteneffekte haben'
  else if not IsKeywordAfter(T, APrev) then
    Exit
  else if T.Low = 'absolute' then
    Result := 'absolute-Variable - sie liegt auf dem Speicher einer anderen'
  else if InList(T.Low, MULTI_LINE_TYPES) then
    Result := Format('Typ mit "%s" (ueber mehrere Zeilen) - von Hand loeschen',
      [T.Low])
  else if InList(T.Low, TYPE_STOPS) then
    Result := Format('"%s" im Typ - Deklaration nicht lesbar', [T.Low]);
end;

// Ab AColon bis zum ';' der Deklaration (Klammern uebersprungen). '' oder
// der Grund.
function TypeEnd(AMap: TRdxCodeMap; const AColon: TRdxToken;
  out ASemi: TRdxToken): string;
var
  T, Prev : TRdxToken;
  Depth   : Integer;
begin
  ASemi := Default(TRdxToken);
  Depth := 0;
  Prev := AColon;
  T := After(AMap, AColon);
  while T.Low <> '' do
  begin
    Inc(Depth, ParenDelta(T));
    if Depth < 0 then
      Exit('Klammer ohne Gegenstueck im Typ');
    if Depth = 0 then
    begin
      Result := TypeTokenReason(T, Prev);
      if Result <> '' then
        Exit;
      if T.Low = ';' then
      begin
        ASemi := T;
        Exit('');
      end;
    end;
    Prev := T;
    T := After(AMap, T);
  end;
  Result := 'kein ";" hinter dem Typ';
end;

// Die Form der Deklaration: 'for var', Initialisierer, Typ bis ';', keine
// Aufrufkonvention dahinter. Setzt ADecl.Semi. '' oder der Grund.
function ShapeReason(AMap: TRdxCodeMap; var ADecl: TRdxVarDecl): string;
var
  N : TRdxToken;
begin
  if (ADecl.Lead.Low = 'var') and (Before(AMap, ADecl.Lead).Low = 'for') then
    Exit('for var - die Laufvariable einer Schleife (der Detektor zaehlt den '
      + 'Schleifenkopf nicht als Verwendung) - keine Hilfe');
  if ADecl.Colon.Low = ':=' then
    Exit('Inline-Deklaration mit Initialisierer ":=" - der Ausdruck kann '
      + 'Seiteneffekte haben');
  if ADecl.Colon.Low <> ':' then
    Exit(Format('kein ":" hinter der Namensliste ("%s") - %s',
      [ADecl.Colon.Low, R_MOVED]));
  Result := TypeEnd(AMap, ADecl.Colon, ADecl.Semi);
  if Result <> '' then
    Exit;
  N := After(AMap, ADecl.Semi);
  if IsKeywordAfter(N, ADecl.Semi) and InList(N.Low, CALL_CONVENTIONS) then
    Result := Format('"%s" hinter dem Typ gehoert noch zur Deklaration - von '
      + 'Hand loeschen', [N.Low]);
end;

// Ein Wort rueckwaerts (GoverningSection): True, wo die Suche endet -
// ein Abschnitt, ein Block, eine Grenze oder ein record ohne end davor.
function SectionStep(const T, APrev: TRdxToken; var ADepth: Integer): Boolean;
begin
  Result := False;
  if T.Low = 'end' then
    Inc(ADepth)
  else if T.Low = 'record' then
  begin
    Result := ADepth = 0;
    if ADepth > 0 then
      Dec(ADepth);
  end
  else if T.Low = 'begin' then
    Result := True
  else if ADepth = 0 then
    Result := InList(T.Low, SECTION_WORDS) or InList(T.Low, UNIT_BOUNDS)
      or IsRoutineHeadAfter(T, APrev);
end;

// Das Wort, das die Section um AFirst eroeffnet (var, const, ...) -
// rueckwaerts ueber die Eintraege davor (Klammern, record..end); Low = ''
// ohne.
function GoverningSection(AMap: TRdxCodeMap; const AFirst: TRdxToken): TRdxToken;
var
  T, P         : TRdxToken;
  Depth, Paren : Integer;
begin
  Result := Default(TRdxToken);
  Depth := 0;
  Paren := 0;
  T := Before(AMap, AFirst);
  while T.Low <> '' do
  begin
    P := Before(AMap, T);
    Dec(Paren, ParenDelta(T));
    if (Paren = 0) and IsKeywordAfter(T, P) and SectionStep(T, P, Depth) then
      Exit(T);
    T := P;
  end;
end;

// Ein Wort rueckwaerts (InsideBlock): rsFound in einem Anweisungsblock,
// rsStop an einem Routinenkopf, einer Abschnittsgrenze oder in case, asm,
// record; sonst weiter. end und until oeffnen rueckwaerts eine Ebene.
function BlockStep(const T, APrev: TRdxToken; var ADepth: Integer): TRdxStep;
begin
  Result := rsGoOn;
  if (T.Low = 'end') or (T.Low = 'until') then
    Inc(ADepth)
  else if InList(T.Low, BLOCK_PAIRS) and (ADepth > 0) then
    Dec(ADepth)
  else if ADepth > 0 then
    Exit
  else if InList(T.Low, LIST_OPENERS) then
    Result := rsFound
  else if InList(T.Low, BLOCK_PAIRS) or IsRoutineHeadAfter(T, APrev)
     or InList(T.Low, UNIT_BOUNDS) then
    Result := rsStop;
end;

// Liegt AVar in einem Anweisungsblock (Inline-Deklaration)? AStop ist das
// Token, an dem die Suche endete: der Blockoeffner bzw. der Routinenkopf.
// Ein Schluesselwort mit ':=' dahinter ist ein benanntes Argument und
// zaehlt nicht (IsKeywordAt, wie BlockStop seit Charge B1-FD - vorher hielt
// die Suche 'End := 1' davor fuer ein end und las die Deklaration als
// var-Section; ReadRoutine lehnte sie dann ab).
function InsideBlock(AMap: TRdxCodeMap; const AVar: TRdxToken;
  out AStop: TRdxToken): Boolean;
var
  T, P  : TRdxToken;
  Depth : Integer;
  Step  : TRdxStep;
begin
  Result := False;
  AStop := Default(TRdxToken);
  Depth := 0;
  T := Before(AMap, AVar);
  while T.Low <> '' do
  begin
    P := Before(AMap, T);
    Step := rsGoOn;
    if IsKeywordAt(AMap, T, P) then
      Step := BlockStep(T, P, Depth);
    if Step <> rsGoOn then
    begin
      AStop := T;
      Exit(Step = rsFound);
    end;
    T := P;
  end;
end;

// Steht die Deklaration hinter ';' in einer var-Section? Setzt VarTok.
// '' oder der Grund.
function SectionReason(AMap: TRdxCodeMap; var ADecl: TRdxVarDecl): string;
var
  K : TRdxToken;
begin
  Result := '';
  K := GoverningSection(AMap, ADecl.First);
  if K.Low = 'var' then
    ADecl.VarTok := K
  else if (K.Low = 'const') or (K.Low = 'resourcestring') then
    Result := Format('lokale %s-Section - keine Variable', [K.Low])
  else if K.Low = '' then
    Result := 'keine var-Section vor der Deklaration'
  else
    Result := Format('die Deklaration steht nicht in einer var-Section '
      + '("%s")', [K.Low]);
end;

// Steht T in einer offenen Klammer - ein Parameter einer Routine oder eines
// Prozedurtyps ('F: function(' bzw. 'procedure Inner(' und auf der
// Folgezeile 'var X: Integer;')? Dort ist 'var' ein Parametermodifikator,
// kein Abschnitt (Gegen-Review H3, Minor 1: die Hilfe loeschte den
// Parameter, aus 'Inner(A, A)' wurde ein Aufruf mit zu vielen Argumenten).
// Rueckwaerts mit Klammerbilanz bis zur oeffnenden Klammer; begin, end,
// implementation und interface stehen in keiner Parameterliste - dort ist
// T sicher draussen.
function InOpenParen(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
var
  P, Q  : TRdxToken;
  Depth : Integer;
begin
  Result := False;
  Depth := 0;
  P := Before(AMap, T);
  while P.Low <> '' do
  begin
    Q := Before(AMap, P);
    Dec(Depth, ParenDelta(P));
    if Depth < 0 then
      Exit(True);
    if (Depth = 0) and IsKeywordAfter(P, Q) and InList(P.Low, PAREN_STOPS) then
      Exit;
    P := Q;
  end;
end;

// Wohin die Deklaration gehoert: Inline in einem Block oder var-Section
// einer Routine. Setzt VarTok, InBlock und Stop. '' oder der Grund.
function OwnerReason(AMap: TRdxCodeMap; var ADecl: TRdxVarDecl): string;
begin
  Result := '';
  if ADecl.Lead.Low = ']' then
    Exit('Attribut vor der Deklaration - von Hand loeschen')
  else if ADecl.Lead.Low = '[' then
    Exit('der Name steht in einem Attribut ("[...]") - keine Variable')
  else if ADecl.Lead.Low = 'var' then
    ADecl.VarTok := ADecl.Lead
  else if ADecl.Lead.Low = ';' then
    Result := SectionReason(AMap, ADecl)
  else
    Result := Format('unklar, wozu die Deklaration gehoert ("%s" davor)',
      [ADecl.Lead.Low]);
  if (Result = '') and InOpenParen(AMap, ADecl.First) then
    Result := 'die Deklaration steht in einer offenen Klammer - ein Parameter '
      + 'einer Routine bzw. eines Prozedurtyps, keine lokale Variable';
  if Result <> '' then
    Exit;
  if Before(AMap, ADecl.VarTok).Low = 'class' then
    Exit('class var - ein Klassenfeld, keine lokale Variable');
  ADecl.InBlock := InsideBlock(AMap, ADecl.VarTok, ADecl.Stop);
  if ADecl.InBlock and (ADecl.Lead.Low <> 'var') then
    Result := 'Deklaration hinter ";" in einem Anweisungsblock - unklar'
  else if not ADecl.InBlock and not InList(ADecl.Stop.Low, ROUTINE_WORDS) then
    Result := 'keine Routine um die Deklaration (globale Variable?) - keine '
      + 'Hilfe';
end;

// Die Routine, deren Deklarationsteil die var-Section von ADecl traegt:
// ab dem Kopf, an dem die Rueckwaertssuche endete (ADecl.Stop); endet deren
// Routine vor der Section (eine lokale Routine davor), weiter ab ihrem Kopf
// rueckwaerts. Die Grenzen liest der Baustein ReadRoutine
// (uRdxRoutineFixes) - bis Charge H3c hatte SCA053 einen eigenen Leser
// (BodyEnd mit BodyStep und RecordEnd, Gegen-Review H3, Major 2). Der
// endete bei einem 'end' als Bezeichner ('Range(start := 0, End := 0)',
// benanntes OLE-Argument) mitten im Rumpf, und eine Verwendung dahinter
// blieb ungesehen; ReadRoutine verlangt hinter dem end ein ';' und lehnt
// dort ab. '' oder der Grund.
function OwnerRoutine(AMap: TRdxCodeMap; const ADecl: TRdxVarDecl;
  out R: TRdxRoutine): string;
var
  H, Stop : TRdxToken;
  n       : Integer;
begin
  H := ADecl.Stop;
  for n := 1 to MAX_OWNER_STEPS do
  begin
    Result := TRdxRoutineFixes.ReadRoutine(AMap, H, R);
    if Result <> '' then
      Exit('Rumpf der Routine nicht gefunden - ' + Result);
    if not TokAfter(ADecl.VarTok, R.Last) then
      Exit('');
    if InsideBlock(AMap, H, Stop) or not InList(Stop.Low, ROUTINE_WORDS) then
      Exit('Rumpf der Routine nicht gefunden');
    H := Stop;
  end;
  Result := 'Rumpf der Routine nicht gefunden - zu viele lokale Routinen';
end;

// Das letzte Token der Bedingung hinter AUntil: vor dem ';' bzw. vor dem
// Schluesselwort, das die umgebende Anweisungsliste schliesst (LIST_ENDS),
// Klammern uebersprungen; Low = '' ohne Ende. Ob Delphi eine
// Inline-Variable des repeat-Teils in der until-Bedingung gelten laesst,
// ist ohne Compiler nicht gemessen - mitlesen sperrt hoechstens (Gegen-
// Review R4, missed 1: eine Verwendung nur dort blieb ungesehen).
function UntilEnd(AMap: TRdxCodeMap; const AUntil: TRdxToken): TRdxToken;
var
  T, Prev : TRdxToken;
  Depth   : Integer;
begin
  Result := Default(TRdxToken);
  Depth := 0;
  Prev := AUntil;
  T := After(AMap, AUntil);
  while T.Low <> '' do
  begin
    Inc(Depth, ParenDelta(T));
    if Depth < 0 then
      Exit;
    if (Depth = 0) and ((T.Low = ';')
       or (InList(T.Low, LIST_ENDS) and IsKeywordAt(AMap, T, Prev))) then
      Exit(Prev);
    Prev := T;
    T := After(AMap, T);
  end;
end;

// Ein Schluesselwort T in BlockStop: Oeffner (END_OPENERS, repeat) zaehlen
// hoch, end/until herunter; True, wenn T auf Tiefe 0 den Block schliesst.
function ClosesBlock(const T: TRdxToken; var ADepth: Integer): Boolean;
begin
  Result := False;
  if IsEndOpener(T.Low) or (T.Low = 'repeat') then
    Inc(ADepth)
  else if (T.Low = 'end') or (T.Low = 'until') then
  begin
    Result := ADepth = 0;
    if not Result then
      Dec(ADepth);
  end;
end;

// Das Ende des Gueltigkeitsbereichs der Inline-Deklaration AVar: das end
// ihres Blocks bzw. - in repeat..until - das letzte Token der until-
// Bedingung (UntilEnd); Low = '' ohne. Ein end/until bzw. Oeffner mit ':='
// dahinter ist der Name eines benannten Arguments ('Doc.Range(Start := 0,
// End := 1)', OLE) und zaehlt nicht (IsKeywordAt): bis Charge B1-FD endete
// der Bereich dort still, eine Verwendung dahinter blieb ungesehen, und die
// Hilfe loeschte die benutzte Deklaration - mit einem Feld oder einer
// globalen Variablen gleichen Namens band die Verwendung danach still an
// sie (Gegen-Review R4-01; var-Sections lehnt ReadRoutine dort ab).
function BlockStop(AMap: TRdxCodeMap; const AVar: TRdxToken): TRdxToken;
var
  T, Prev : TRdxToken;
  Depth   : Integer;
begin
  Result := Default(TRdxToken);
  Depth := 0;
  Prev := AVar;
  T := After(AMap, AVar);
  while T.Low <> '' do
  begin
    if IsKeywordAt(AMap, T, Prev) and ClosesBlock(T, Depth) then
    begin
      if T.Low = 'until' then
        Exit(UntilEnd(AMap, T));
      Exit(T);
    end;
    Prev := T;
    T := After(AMap, T);
  end;
end;

// Kommt AKey von AFrom bis ATo (einschliesslich) noch einmal als Code vor -
// ausser an ASkip und hinter '.' (ein Member)? '' oder der Grund.
// Keine with-Sperre (bis 2026-10-14 vorhanden, kostete 104 Korpusangebote):
// kommt der Name im Bereich nirgends vor, kann ein with ihn nicht binden -
// das Entfernen der Deklaration aendert keine Bindung. Kommt er vor, lehnt
// schon die Pruefung oben ab.
function ScanUses(AMap: TRdxCodeMap; const AFrom, ATo, ASkip: TRdxToken;
  const AKey: string): string;
var
  T, P : TRdxToken;
begin
  Result := '';
  P := Before(AMap, AFrom);
  T := AFrom;
  while (T.Low <> '') and not TokAfter(T, ATo) do
  begin
    if T.IsWord and (P.Low <> '.') and not SameTok(T, ASkip)
       and SameIdent(T.Low, AKey) then
      Exit(Format('der Name kommt im Gueltigkeitsbereich noch vor (Zeile %d) '
        + '- auch unter {$IFDEF} und in asm zaehlt er als Verwendung',
        [T.Line]));
    P := T;
    T := After(AMap, T);
  end;
end;

// Die erste Zeile von AFrom bis ATo mit einer Direktive, deren Text hinter
// dem Wort AKey als Bezeichner nennt ('{$DEFINE M := X}', '{$IFDEF X}');
// 0 ohne.
function DirectiveNaming(AMap: TRdxCodeMap; AFrom, ATo: Integer;
  const AKey: string): Integer;
var
  Li, Co : Integer;
begin
  Result := 0;
  for Li := AFrom to ATo do
    for Co := 1 to Length(AMap.Raw(Li)) do
      if OpensDirective(AMap, Li, Co)
         and HasIdentWord(LowerCase(DirectiveArgs(AMap, Li, Co)), AKey) then
        Exit(Li);
end;

// Was im Gueltigkeitsbereich (AFrom bis ATo) den Namen verwenden kann, ohne
// dass er dort als Code steht (Gegen-Review H3, Major 1 und Verdacht 2): ein
// {$I datei} - die Include-Datei sieht weder die Hilfe noch der Detektor
// (er expandiert Includes nicht; mit einer globalen Variablen gleichen
// Namens bindet sie danach still an die globale); eine Direktive, die den
// Namen nennt (FPC-Makro '{$DEFINE M := X}'); ein asm-Block - Assembler
// spricht lokale Variablen auch ueber den Stack-Rahmen an ('[ebp-4]'), und
// die Hilfe veraendert das Stack-Layout. '' oder der Grund.
function ScopeReason(AMap: TRdxCodeMap; const AFrom, ATo: TRdxToken;
  const AKey: string): string;
var
  T, P : TRdxToken;
  Li   : Integer;
begin
  Result := '';
  Li := IncludeInLines(AMap, AFrom.Line, ATo.Line);
  if Li > 0 then
    Exit(Format('{$I}-Include im Gueltigkeitsbereich (Zeile %d) - dort kann '
      + 'der Name stehen, den die Hilfe nicht sieht', [Li]));
  Li := DirectiveNaming(AMap, AFrom.Line, ATo.Line, AKey);
  if Li > 0 then
    Exit(Format('eine Direktive nennt "%s" (Zeile %d) - Makro oder Bedingung, '
      + 'die Hilfe wertet sie nicht aus', [AKey, Li]));
  P := Before(AMap, AFrom);
  T := AFrom;
  while (T.Low <> '') and not TokAfter(T, ATo) do
  begin
    if (T.Low = 'asm') and IsKeywordAfter(T, P) then
      Exit(Format('asm im Gueltigkeitsbereich (Zeile %d) - Assembler kann die '
        + 'Variable ueber den Stack-Rahmen ansprechen, ohne ihren Namen',
        [T.Line]));
    P := T;
    T := After(AMap, T);
  end;
end;

// Ein FPC-Makro irgendwo in der Datei, das den Namen einsetzt ('{$DEFINE M
// := X}' vor der Routine, M im Rumpf)? Die Durchsicht des
// Gueltigkeitsbereichs sieht nur M. '' oder der Grund.
function MacroReason(AMap: TRdxCodeMap; const AKey: string): string;
var
  Li, Co : Integer;
  Arg    : Boolean;
  Args   : string;
begin
  Result := '';
  for Li := 1 to AMap.LineCount do
    for Co := 1 to Length(AMap.Raw(Li)) do
      if OpensDirective(AMap, Li, Co)
         and InList(DirectiveWord(AMap, Li, Co, Arg), MACRO_WORDS) then
      begin
        Args := LowerCase(DirectiveArgs(AMap, Li, Co));
        if (Pos(MACRO_ASSIGN, Args) > 0) and HasIdentWord(Args, AKey) then
          Exit(Format('ein Makro setzt "%s" ein ({$DEFINE ... := ...} in Zeile '
            + '%d) - die Hilfe sieht seine Verwendung nicht', [AKey, Li]));
      end;
end;

// Der Gueltigkeitsbereich: inline vom var bis zum end seines Blocks, sonst
// vom Routinenkopf bis zum end des Rumpfs (lokale Routinen darin
// eingeschlossen). '' oder der Grund (auch eine Verwendung, ein Include,
// eine Direktive oder asm darin, ein Makro mit dem Namen).
function UseReason(AMap: TRdxCodeMap; const ADecl: TRdxVarDecl;
  const AKey: string): string;
var
  From, Upto : TRdxToken;
  R          : TRdxRoutine;
begin
  Result := '';
  if ADecl.InBlock then
  begin
    From := ADecl.VarTok;
    Upto := BlockStop(AMap, ADecl.VarTok);
    if Upto.Low = '' then
      Exit('kein Ende des Blocks um die Deklaration gefunden');
  end
  else
  begin
    From := ADecl.Stop;
    Result := OwnerRoutine(AMap, ADecl, R);
    if Result <> '' then
      Exit;
    Upto := R.EndTok;
  end;
  Result := ScanUses(AMap, From, Upto, ADecl.Name, AKey);
  if Result = '' then
    Result := ScopeReason(AMap, From, Upto, AKey);
  if Result = '' then
    Result := MacroReason(AMap, AKey);
end;

// Ein 'class operator Initialize/Finalize' in der Unit (Delphi 10.4:
// verwaltete Records)? Dann fuehrt eine Variable dieses Typs Code aus,
// auch ungenutzt (Waechter-Idiom). Ein solcher Typ aus einer anderen Unit
// ist im Text nicht erkennbar - Restrisiko. '' oder der Grund.
function ManagedRecordReason(AMap: TRdxCodeMap): string;
var
  T, N : TRdxToken;
begin
  Result := '';
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    if T.Low = 'operator' then
    begin
      N := After(AMap, T);
      if (N.Low = 'initialize') or (N.Low = 'finalize') then
        Exit('die Unit deklariert einen class operator Initialize/Finalize '
          + '(verwalteter Record) - eine Variable kann Code ausfuehren');
    end;
    T := After(AMap, T);
  end;
end;

// Folgt hinter ASemi noch ein Eintrag derselben Section ('Name ,' bzw.
// 'Name :' oder ein Attribut)?
function MoreItems(AMap: TRdxCodeMap; const ASemi: TRdxToken): Boolean;
var
  N : TRdxToken;
begin
  N := After(AMap, ASemi);
  if (N.Low = '[') or (N.Low = '&') then
    Exit(True);
  Result := N.IsWord and not InList(N.Low, RESERVED)
    and InList(After(AMap, N).Low, ITEM_FOLLOW);
end;

// Inline-Deklaration als ganze Anweisung: hinter ';' oder als erste einer
// Liste, hinter der noch eine folgt (sonst bliebe ein leerer Block). '' oder
// der Grund.
function InlineContextReason(AMap: TRdxCodeMap; const ADecl: TRdxVarDecl): string;
var
  P, N : TRdxToken;
begin
  Result := '';
  P := Before(AMap, ADecl.VarTok);
  if P.Low = ';' then
    Exit;
  if not InList(P.Low, LIST_OPENERS) then
    Exit(Format('unklar, wozu die Inline-Deklaration gehoert ("%s" davor)',
      [P.Low]));
  N := After(AMap, ADecl.Semi);
  if (N.Low = '') or InList(N.Low, LIST_ENDS) then
    Result := Format('einzige Anweisung hinter %s - es bliebe ein leerer '
      + 'Block (SCA077)', [P.Low]);
end;

// Was geloescht wird: in einer Gruppe der Name samt Komma ('X, ' bzw.
// ', X' am Ende), sonst die Deklaration - inline samt var, in einer
// Section, die dadurch leer wird, samt var. '' oder der Grund.
function VarCut(AMap: TRdxCodeMap; const ADecl: TRdxVarDecl;
  out AFrom, ATo: TRdxTextPos): string;
begin
  Result := '';
  if (ADecl.Count > 1) and SameTok(ADecl.Name, ADecl.Last) then
  begin
    AFrom := TokPos(Before(AMap, ADecl.Name));
    ATo := TokEnd(ADecl.Name);
    Exit;
  end;
  if ADecl.Count > 1 then
  begin
    AFrom := TokPos(ADecl.Name);
    ATo := TokEnd(After(AMap, ADecl.Name));
    Exit;
  end;
  ATo := TokEnd(ADecl.Semi);
  AFrom := TokPos(ADecl.Name);
  if ADecl.InBlock then
  begin
    AFrom := TokPos(ADecl.VarTok);
    Result := InlineContextReason(AMap, ADecl);
  end
  else if (ADecl.Lead.Low = 'var') and not MoreItems(AMap, ADecl.Semi) then
    AFrom := TokPos(ADecl.VarTok);
end;

// Kommentar im geloeschten Text, Direktive in der Deklaration bzw. - in
// einer Section - von ihrem var bis zum naechsten Eintrag (ein Zweig
// koennte leer werden). '' oder der Grund.
function CutReason(AMap: TRdxCodeMap; const ADecl: TRdxVarDecl;
  const AFrom, ATo: TRdxTextPos): string;
var
  Directive : Boolean;
begin
  Result := '';
  if CommentInRange(AMap, SpanOf(AFrom, ATo, SPAN_053)) then
    Exit('Kommentar in der Deklaration - er ginge verloren');
  if ADecl.InBlock then
    Directive := DirectiveInLines(AMap, ADecl.VarTok.Line, ADecl.Semi.Line)
  else
    Directive := DirectiveBefore(AMap, ADecl.VarTok.Line,
      After(AMap, ADecl.Semi));
  if Directive then
    Result := 'Direktive in der Deklaration bzw. ihrer var-Section - ein '
      + 'Zweig koennte leer werden';
end;

// Steht die Deklaration allein auf ihrer Zeile und folgt ihr nur ein
// '//'-Kommentar, geht er mit der Zeile (er beschreibt die Variable) -
// ausser er traegt einen Marker (MarkerReason: noinspection oder ein
// Absichtsmarker wie bei SCA019). Ein '// noinspection X' hinter Code gilt
// der naechsten Zeile (uSuppression.BuildMap), ein Absichtskommentar
// bleibt wie bei SCA070 stehen; bis Charge B1-FD gingen beide mit, die
// Funde der Folgezeile erschienen danach wieder (Gegen-Review R4-04). Dann
// endet der Schnitt vor dem Kommentar, und CutEdit rueckt ihn an die
// Einrueckung - als eigene Zeile gilt er derselben Folgezeile.
function WithTrailingComment(AMap: TRdxCodeMap;
  const AFrom, ATo: TRdxTextPos): TRdxTextPos;
var
  L     : string;
  Slash : Integer;
begin
  Result := ATo;
  L := AMap.Raw(ATo.Line);
  Slash := AMap.LineCommentCol(ATo.Line);
  if (Slash > 0) and (SkipBlanks(L, ATo.Col) = Slash)
     and (SkipBlanks(AMap.Raw(AFrom.Line), 1) >= AFrom.Col)
     and (MarkerReason(Copy(L, Slash, MaxInt)) = '') then
    Result := TextPos(ATo.Line, Length(L) + 1);
end;

// Steht vor AFrom nur Leerraum, verliert die Zeile mit dem Schnitt ihren
// Code (sie geht ganz, oder ein Rest rueckt an die Einrueckung): ein
// Zeilen-Marker darueber, der auf sie zielt, gaelte danach anderem Code
// (uRdxRoutineFixes.MarkerAboveReason; Nachpruefung B1-FD: der Marker
// '// noinspection ShortVariableName' ueber 'X: Integer;' galt nach der
// Hilfe 'Y: Integer;'). Bleibt Code davor ('A, X: T' -> 'A: T'), bleibt
// auch das Ziel. '' oder der Grund.
function MarkerAboveCut(AMap: TRdxCodeMap; const AFrom: TRdxTextPos): string;
begin
  Result := '';
  if SkipBlanks(AMap.Raw(AFrom.Line), 1) >= AFrom.Col then
    Result := MarkerAboveReason(AMap, AFrom.Line);
end;

// Name, Gruppe, Form und Besitzer der Deklaration. '' oder der Grund.
function DeclReason(AMap: TRdxCodeMap; ALine: Integer; const AKey: string;
  out ADecl: TRdxVarDecl): string;
begin
  ADecl := Default(TRdxVarDecl);
  Result := NameOn(AMap, ALine, AKey, ADecl.Name);
  if Result = '' then
    Result := GroupOf(AMap, ADecl);
  if (Result = '') and (ADecl.First.Line <> ALine) then
    Result := 'die Namensliste beginnt nicht auf der gemeldeten Zeile - '
      + R_MOVED;
  // Erst der Besitzer (Section, Block), dann die Form: eine const-Section
  // heisst so, nicht 'initialisierte Variable'.
  if Result = '' then
    Result := OwnerReason(AMap, ADecl);
  if Result = '' then
    Result := ShapeReason(AMap, ADecl);
end;

class function TRdxCleanupFixes.UnusedLocalVar(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  Key               : string;
  Decl              : TRdxVarDecl;
  CutStart, CutStop : TRdxTextPos;
begin
  AEdit := Default(TRdxEdit);
  Decl := Default(TRdxVarDecl);
  CutStart := TextPos(0, 0);
  CutStop := TextPos(0, 0);
  Key := LowerCase(UnusedVarName(AMessage));
  if Key = '' then
    AReason := 'Variablenname fehlt in der Meldung'
  else if InList(Key, RESERVED) then
    AReason := Format('"%s" ist ein Schluesselwort, keine Variable (der '
      + 'Parser las eine Section als Variable) - keine Hilfe', [Key])
  else
    AReason := DeclReason(AMap, ALine, Key, Decl);
  if AReason = '' then
    AReason := UseReason(AMap, Decl, Key);
  if AReason = '' then
    AReason := ManagedRecordReason(AMap);
  if AReason = '' then
    AReason := VarCut(AMap, Decl, CutStart, CutStop);
  if AReason = '' then
    AReason := CutReason(AMap, Decl, CutStart, CutStop);
  if AReason = '' then
    AReason := MarkerAboveCut(AMap, CutStart);
  if AReason = '' then
    AReason := CutEdit(AMap, CutStart, WithTrailingComment(AMap, CutStart,
      CutStop), SPAN_053, AEdit);
  Result := AReason = '';
end;

end.

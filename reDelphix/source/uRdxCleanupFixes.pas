unit uRdxCleanupFixes;

// reDelphix - Quick-Fixes "Aufraeumen", OHNE ToolsAPI und ohne Parser
// (Konzept_Editorhilfen_Recherche_2026-10-11, Abschnitt 6, Charge H3a):
//   SCA070 CommentedOutCode: den auskommentierten Bereich loeschen - eine
//          '//'-Zeile ganz, einen Kommentar hinter Code ab seiner Spalte
//          (der Leerraum am Zeilenende geht mit), einen mehrzeiligen
//          '{ }'/'(* *)' immer GANZ samt Begrenzern (41 % der Korpusfunde
//          zeigen auf eine Inhaltszeile, nicht auf den Oeffner): reicht er
//          ueber den Fund hinaus, nur wenn auch der Rest Code ist.
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
// Bis zur Fix-Charge nach dem Realworld-Test rwE29 loeschte die Hilfe nur
// die Region und liess die Begrenzer stehen, solange der Kommentar danach
// Text trug - 15 von 50 Stellen waren falsch: verstuemmelte Reste ('{ with
// memEdit do }', 'begin' ohne 'end'), ein Off-by-one am Schliesser
// ('(*' / 'break;*)' blieben, fmain.pas:240), zerstoerte Doku-Beispiele.
// Seitdem loescht sie nur GANZE Kommentare (bzw. ganze '//'-Zeilen):
// reicht der Kommentar ueber die Region hinaus, muss jede Zeile ausserhalb
// leer oder eindeutig Code sein (CodePiece, strenger als der Detektor) -
// dann geht der ganze Kommentar, sonst gibt es keine Hilfe (der Rest
// bliebe als Torso stehen oder Prosa ginge mit). Seit der Fix-Runde 2 nach
// dem Realworld-Test rwE30 (28 unnoetige Sperren) zaehlen dort auch ein
// innerer Kommentar ('// IdentList', in '(* *)' ein '{ read X }' allein auf
// der Zeile - ausser er sagt, woher der Code stammt oder warum er bleibt:
// KEEP_WORDS), ein case-Zweig 'A:' unter 'case ... of' bzw. 'A: begin' und
// ein Aufruf ohne ';' vor 'else' als Code; eine Prosazeile ohne
// Kommentarzeichen sperrt weiter.
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
    // Code-Merkmal wie im Detektor. Geloescht werden immer ganze
    // Kommentare; reicht einer ueber die Region hinaus, nur wenn sein Text
    // dort leer oder Code ist (CodePiece; dazu innere Kommentare ohne
    // Herkunfts-/Absichtswort, case-Zweige, ein Aufruf vor 'else' - s. Kopf
    // der Unit). Keine Hilfe bei einer Direktive
    // im Bereich, einem Doku-Kommentar ('///', '{*', '(**', eine Zeile mit
    // fuehrendem '*' oder '<PRE>'), einem Kommentar vor dem ersten Code der
    // Datei (Lizenz-/Kopfkommentar) oder direkt hinter 'unit X;' (Doku der
    // Unit), 'noinspection' oder einem Absichtsmarker wie bei SCA019 im
    // geloeschten Text und wenn ein Kommentar mit anderem Text ueber die
    // Region hinausreicht (Prosa oder nicht eindeutiger Code).
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

// Der Baustein der beiden Planer dieser Unit (Charge H3, "loeschen und
// aufraeumen"); oeffentlich nur fuer die Tests (uTestRdxCleanupFixes) -
// ein anderer Planer bindet diese Unit nicht ein (Kopf von uRdxBlocks).
// Braucht ihn ein zweiter, gehoert er samt IndentCut/TailCut/JoinCut nach
// uRdxBlocks (Review Woche G07-07; bis dahin hiess er hier "gemeinsamer
// Baustein"); die Loeschung ganzer Zeilen (LinesCut) steht seit der
// Folgewelle des Wochen-Reviews als WholeLinesEdit in uRdxBufferMath. Den
// Text von
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
  uRdxBlocks,        // ReadRoutine (SCA053: Ende des Gueltigkeitsbereichs),
                     // MarkerAboveReason (Marker ueber der Deklaration)
  uRdxText;          // _() und die gemeinsamen Texte (Msg...): Gruende in der
                     // reDelphix-Sprache (E29), nie uLocalization

const
  SPAN_070 = 'sca070';
  SPAN_053 = 'sca053';
  KEY_ONE     = 'Comment at column ';
  KEY_BLOCK   = 'Commented-out code block of ';
  KEY_START   = ' lines starting at column ';
  KEY_VAR     = 'Unused local variable: ';
  KEY_VAR_END = ' (';
  // SCA053: Schluesselwoerter von Delphi (RESERVED, uRdxCodeMap) sind kein
  // Variablenname (17 Korpusfunde nennen 'resourcestring': der Parser las
  // die Section als Variable).
  // Abschnitte eines Deklarationsteils.
  SECTION_WORDS: array[0..5] of string = ('var', 'const', 'type',
    'resourcestring', 'label', 'threadvar');
  // Teile einer Unit, an denen die Suche endet - ohne initialization und
  // finalization (anders als uRdxCodeMap.UNIT_BOUNDS; bis zur Folgewelle
  // des Wochen-Reviews hiess die Liste hier ebenfalls UNIT_BOUNDS).
  UNIT_PARTS: array[0..4] of string = ('implementation', 'interface',
    'program', 'library', 'unit');
  // Rueckwaerts: Paare mit 'end' bzw. 'until'.
  BLOCK_PAIRS: array[0..5] of string = ('begin', 'try', 'case', 'asm',
    'record', 'repeat');
  // Vor der ersten Anweisung einer Anweisungsliste.
  LIST_OPENERS: array[0..6] of string = ('begin', 'try', 'finally', 'except',
    'repeat', 'initialization', 'finalization');
  // Das Ende einer Anweisungsliste: LIST_ENDS (uRdxCodeMap).
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
  // SCA070, CodePiece: ein Wort allein auf der Zeile, das so nur Code ist.
  CODE_SOLO_WORDS: array[0..21] of string = ('begin', 'end', 'else', 'try',
    'finally', 'except', 'repeat', 'var', 'const', 'type', 'uses', 'label',
    'resourcestring', 'threadvar', 'initialization', 'finalization',
    'implementation', 'interface', 'private', 'protected', 'public',
    'published');
  // ... eine Steuerzeile: beginnt mit einem dieser Woerter ...
  CODE_LEAD_WORDS: array[0..7] of string = ('if', 'while', 'for', 'with',
    'case', 'else', 'end', 'on');
  // ... und endet mit einem dieser ('if X then', 'end else begin').
  CODE_TAIL_WORDS: array[0..6] of string = ('then', 'do', 'of', 'begin',
    'else', 'try', 'repeat');
  // SCA070: der Kopf einer Unit ('unit X;'), hinter dem ihre Doku steht.
  UNIT_HEADS: array[0..3] of string = ('unit', 'program', 'library',
    'package');
  // SCA070, InnerComment: Woerter, mit denen ein Kommentar im
  // auskommentierten Code sagt, woher er stammt oder warum er bleibt
  // ('// reference implementation', '// Taken from ...', '// In case you
  // use ...') - dann ist der Block dokumentiert, nicht vergessen.
  KEEP_WORDS: array[0..15] of string = ('you', 'your', 'because',
    'reference', 'example', 'sample', 'demo', 'keep', 'kept', 'taken', 'from',
    'adapted', 'copied', 'see', 'note', 'why');

type
  // SCA070: die Region der Meldung.
  TRdxRegion = record
    First : Integer;   // R1, die gemeldete Zeile
    Last  : Integer;   // R1 + N - 1
    Col   : Integer;   // C
  end;

  // Ein Kommentar der Datei.
  // Die Namen der Schliesser-Felder unterscheiden sich nicht nur im Suffix
  // (bis zur Review Woche G07-08 Close/Closer/Closed - 'Close' las sich
  // wie ein Verb, 'G.Close.Line > R2' wie eine Flag-Pruefung).
  TRdxComment = record
    Open       : TRdxTextPos;   // erstes Zeichen des Oeffners
    Body       : TRdxTextPos;   // erstes Zeichen hinter dem Oeffner
    CloseAt    : TRdxTextPos;   // erstes Zeichen des Schliessers ('//': Zeilenende)
    Stop       : TRdxTextPos;   // hinter dem Schliesser
    CloserText : string;        // '}' bzw. '*)', '' bei '//'
    Directive  : Boolean;       // '{$' bzw. '(*$'
    Doc        : Boolean;       // '///', '{*', '(**' - Dokumentation
    IsClosed   : Boolean;       // False: offen bis zum Dateiende
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

{ ---- CutEdit: loeschen und aufraeumen ---- }

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
    Exit(_('empty range'));
  LeadBlank := SkipBlanks(AMap.Raw(AFrom.Line), 1) >= AFrom.Col;
  TailBlank := SkipBlanks(AMap.Raw(ATo.Line), ATo.Col)
    > Length(AMap.Raw(ATo.Line));
  if LeadBlank and (ATo.Col = 1) then
    Result := WholeLinesEdit(AMap, AFrom.Line, ATo.Line - 1, ARole, AEdit)
  else if LeadBlank and TailBlank then
    Result := WholeLinesEdit(AMap, AFrom.Line, ATo.Line, ARole, AEdit)
  else if LeadBlank then
    AEdit := IndentCut(AMap, AFrom, ATo, ARole)
  else if TailBlank then
    AEdit := TailCut(AMap, AFrom, ATo, ARole)
  else
    AEdit := JoinCut(AMap, AFrom, ATo, ARole);
  if (Result = '') and (AEdit.Expected = '') then
    Result := _('empty range');
end;

function CutEdit(AMap: TRdxCodeMap; const AFrom, ATo: TRdxTextPos;
  const ARole: string; out AEdit: TRdxEdit): string;
var
  From : TRdxTextPos;
begin
  // Beginnt der Schnitt hinter einem Zeilenende oder auf einer leeren Zeile
  // (bis zur Fix-Charge rwE29 bei SCA070: '(*' allein auf der Zeile, der
  // Kommentar blieb), beginnt er auf der naechsten Zeile - das Zeilenende
  // bleibt.
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
    Exit(MsgMovedSuffix(_('the finding reaches line %d, the file has %d lines',
      [ARegion.Last, AMap.LineCount])));
  if AMap.ClassAt(ARegion.First, ARegion.Col) <> 'k' then
    Exit(MsgMovedSuffix(_('no comment at line %d column %d',
      [ARegion.First, ARegion.Col])));
  for Li := ARegion.First to ARegion.Last do
  begin
    L := AMap.Raw(Li);
    From := 1;
    if Li = ARegion.First then
      From := ARegion.Col;
    for Co := From to Length(L) do
      if not IsBlank(L[Co]) and (AMap.ClassAt(Li, Co) <> 'k') then
        Exit(_('line %d carries code or text next to the comment (column %d) '
          + '- %s', [Li, Co, MsgDeleteByHand]));
  end;
end;

// Der Schliesser ab AComment.Body suchen (die erste Fundstelle - '{ }'
// schachtelt nicht, wie in der Code-Sicht).
procedure FindCloser(AMap: TRdxCodeMap; var AComment: TRdxComment);
var
  Li, P : Integer;
begin
  Li := AComment.Body.Line;
  P := Pos(AComment.CloserText, AMap.Raw(Li), AComment.Body.Col);
  while (P = 0) and (Li < AMap.LineCount) do
  begin
    Inc(Li);
    P := Pos(AComment.CloserText, AMap.Raw(Li));
  end;
  if P = 0 then
  begin
    AComment.CloseAt := TextPos(Li, Length(AMap.Raw(Li)) + 1);
    AComment.Stop := AComment.CloseAt;
    Exit;
  end;
  AComment.CloseAt := TextPos(Li, P);
  AComment.Stop := TextPos(Li, P + Length(AComment.CloserText));
  AComment.IsClosed := True;
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
    AComment.CloseAt := TextPos(ALine, Length(L) + 1);
    AComment.Stop := AComment.CloseAt;
    AComment.IsClosed := True;
    AComment.Doc := Copy(L, ACol, 3) = '///';
    Exit;
  end;
  if Copy(L, ACol, 1) = '{' then
    AComment.CloserText := '}'
  else if Copy(L, ACol, 2) = '(*' then
    AComment.CloserText := '*)'
  else
    Exit(False);
  AComment.Body := TextPos(ALine, ACol + Length(AComment.CloserText));
  AComment.Directive := Copy(L, AComment.Body.Col, 1) = '$';
  FindCloser(AMap, AComment);
  // '{*' ist die Doku der CnPack-Quellen ('{* Kommentar zur Deklaration
  // darueber }' - Korpus: 24 Funde in cnwizards, Prosa mit 'function' und
  // 'begin' darin); '(**' ohne '(**)' ist PasDoc.
  if AComment.CloserText = '}' then
    AComment.Doc := Copy(L, AComment.Body.Col, 1) = '*'
  else
    AComment.Doc := (Copy(L, AComment.Body.Col, 1) = '*')
      and PosBefore(AComment.Body, AComment.CloseAt);
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
        Exit(_('comment at line %d column %d not readable', [Li, Co]));
      if PosBefore(From, C.Stop) then
        AddComment(AList, C);
      if not C.IsClosed then
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
  Result := MsgMovedSuffix(_('column %d points into the middle of a comment',
    [ARegion.Col]));
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
  if (ALine < AComment.Body.Line) or (ALine > AComment.CloseAt.Line) then
    Exit;
  A := 1;
  if ALine = AComment.Body.Line then
    A := AComment.Body.Col;
  if A < AFrom then
    A := AFrom;
  B := Length(AMap.Raw(ALine)) + 1;
  if ALine = AComment.CloseAt.Line then
    B := AComment.CloseAt.Col;
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
  Result := MsgMovedSuffix(_('line %d does not look like code (no ";" at the '
    + 'end, no ":=", no begin/procedure/function)', [ALine]));
end;

// Die erste Zeile eines Blockkommentars in Doku-Form: sie beginnt mit '*'
// (der Rand der CnPack- und JavaDoc-Koepfe, '*  type' ueber dem Beispiel)
// oder traegt '<PRE>' ('{ |<PRE>' der CnPack-Koepfe); 0 ohne. Realworld-
// Test rwE29: CnWizMethodHook.pas:58 - die Hilfe loeschte 80 Zeilen aus
// dem Beispiel eines Kopfkommentars, den kein '{*' eroeffnete.
function DocShapeLine(AMap: TRdxCodeMap; const AComment: TRdxComment): Integer;
var
  Li : Integer;
  S  : string;
begin
  Result := 0;
  if AComment.CloserText = '' then
    Exit;
  for Li := AComment.Body.Line to AComment.CloseAt.Line do
  begin
    S := TrimLeft(PieceOn(AMap, AComment, Li, 1));
    if (Copy(S, 1, 1) = '*') or (Pos('<pre>', LowerCase(S)) > 0) then
      Exit(Li);
  end;
end;

// Steht vor APos nur der Kopf der Unit - 'unit X;' (auch program, library,
// package; der Name auch mit Punkten)? Der Kommentar direkt dahinter ist
// ihre Doku (rwE29: JvgXMLSerializer.pas:50, die Schnittstelle der Unit
// mit Signaturen und Beschreibung hinter 'unit JvgXMLSerializer;').
function AfterUnitHeader(AMap: TRdxCodeMap; const APos: TRdxTextPos): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  T := PrevToken(AMap, APos.Line, APos.Col);
  if T.Low <> ';' then
    Exit;
  T := Before(AMap, T);
  if not T.IsWord then
    Exit;
  while Before(AMap, T).Low = '.' do
  begin
    T := Before(AMap, Before(AMap, T));
    if not T.IsWord then
      Exit;
  end;
  T := Before(AMap, T);
  Result := InList(T.Low, UNIT_HEADS) and (Before(AMap, T).Low = '');
end;

// Die Sperren je Kommentar: Direktive, Doku, offenes Ende - und ein
// Kommentar vor dem ersten Code der Datei (Lizenz- oder Kopfkommentar)
// bzw. direkt hinter dem Kopf der Unit.
function KindReason(AMap: TRdxCodeMap; const AList: TRdxCommentList): string;
var
  C  : TRdxComment;
  Li : Integer;
begin
  Result := '';
  for C in AList do
  begin
    if C.Directive then
      Exit(_('directive in the range (line %d) - it is active code, not a '
        + 'comment', [C.Open.Line]));
    if C.Doc then
      Exit(_('documentation comment (///, {* or (**, line %d) - its sample '
        + 'code stays', [C.Open.Line]));
    if not C.IsClosed then
      Exit(_('comment without an end up to the end of the file'));
    Li := DocShapeLine(AMap, C);
    if Li > 0 then
      Exit(_('documentation comment (leading "*" or <PRE> in line %d) - its '
        + 'sample code stays', [Li]));
  end;
  if PrevToken(AMap, AList[0].Open.Line, AList[0].Open.Col).Low = '' then
    Result := _('comment before the first code of the file (license or '
      + 'header comment) - %s', [MsgDecideByHand])
  else if AfterUnitHeader(AMap, AList[0].Open) then
    Result := _('comment directly after the unit header (documentation of '
      + 'the unit) - %s', [MsgDecideByHand]);
end;

// Die Gegenproben am Kommentar: Anfang, Art, Code-Merkmal. '' oder der
// Grund.
function CommentReason(AMap: TRdxCodeMap; const ARegion: TRdxRegion;
  const AList: TRdxCommentList): string;
begin
  if Length(AList) = 0 then
    Exit(MsgMovedSuffix(_('no comment at the reported place')));
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

// Das erste bzw. letzte Wort von S, klein; '' wenn S nicht mit einem
// Bezeichner beginnt bzw. endet.
function FirstWordOf(const S: string): string;
var
  i : Integer;
begin
  Result := '';
  if (S = '') or not IsIdentStart(S[1]) then
    Exit;
  i := 1;
  while (i < Length(S)) and IsIdentChar(S[i + 1]) do
    Inc(i);
  Result := LowerCase(Copy(S, 1, i));
end;

function LastWordOf(const S: string): string;
var
  i : Integer;
begin
  Result := '';
  if (S = '') or not IsIdentChar(S[Length(S)]) then
    Exit;
  i := Length(S);
  while (i > 1) and IsIdentChar(S[i - 1]) do
    Dec(i);
  if IsIdentStart(S[i]) then
    Result := LowerCase(Copy(S, i, MaxInt));
end;

// Der Code-Teil eines Kommentarstuecks: ohne Leerraum aussen, ohne einen
// '//'-Kommentar dahinter und ohne ein '{' am Ende - das '{}'-Ende der
// JVCL-Quellen ('...;Forward;{}': in einem '{ }' ist das innere '{' nur
// Text; rwE30 JvThumbImage.pas:600).
function CodeText(const APiece: string): string;
var
  P : Integer;
begin
  Result := Trim(APiece);
  P := Pos('//', Result);
  if P > 1 then
    Result := TrimRight(Copy(Result, 1, P - 1));
  if (Length(Result) > 1) and (Result[Length(Result)] = '{') then
    Result := TrimRight(Copy(Result, 1, Length(Result) - 1));
end;

// Ist das Stueck eines Kommentars (ohne Begrenzer) leer oder eindeutig
// Pascal-Code - so streng, dass Prosa es kaum trifft? Code ist: endet auf
// ';' (ein '//' dahinter und ein '{' am Ende abgeschnitten, CodeText),
// traegt ':=', ist eine Direktive '{$...}' (in '(* *)' totgelegt) oder
// 'end.', ein Schluesselwort allein (CODE_SOLO_WORDS) oder eine Steuerzeile
// (CODE_LEAD_WORDS ... CODE_TAIL_WORDS: 'if X then', 'with Y do', 'end else
// begin'). Eine Zeile, die auf ',' oder ein anderes Wort endet
// ('CheckEquals', 'a,'), ist es nicht. Anders als der Detektor (zwei
// Merkmale, eines stark) prueft das nur Zeilen ausserhalb des Funds; was
// hier nicht besteht, prueft NonCodeLine weiter (innerer Kommentar,
// case-Zweig, Aufruf vor 'else') - sonst sperrt es: der Detektor hat es
// nicht als Code gemeldet.
function CodePiece(const APiece: string): Boolean;
var
  S, W1 : string;
begin
  S := Trim(APiece);
  if S = '' then
    Exit(True);
  if Copy(S, 1, 2) = '//' then
    Exit(False);
  S := CodeText(S);
  if (S[Length(S)] = ';') or (Pos(':=', S) > 0) or SameText(S, 'end.') then
    Exit(True);
  if (Copy(S, 1, 2) = '{$') and (Pos('}', S) = Length(S)) then
    Exit(True);
  W1 := FirstWordOf(S);
  if W1 = '' then
    Exit(False);
  if Length(W1) = Length(S) then
    Exit(InList(W1, CODE_SOLO_WORDS));
  Result := InList(W1, CODE_LEAD_WORDS)
    and InList(LastWordOf(S), CODE_TAIL_WORDS);
end;

// Ein Kommentar im auskommentierten Code (S getrimmt): eine ganze
// '//'-Zeile in einem '{ }'/'(* *)' bzw. in einem '(* *)' ein geschlossenes
// '{ ... }' allein auf der Zeile (keine Direktive). Realworld-Test rwE30:
// 18 von 28 unnoetigen Sperren - '// IdentList' (CnCodeFormatter.pas:3989),
// '// The Gamebryo way' (ProcCheckForErrors.pas:884), '{ read
// CurrencyString: string }' vor jeder Routine der JvInterpreter-Quellen.
// Er gehoert zum toten Code und geht mit ihm; NonCodeLine wertet ihn weder
// als Code noch als Prosa - ausser er traegt ein KEEP_WORDS-Wort
// (KeepNote). Eine Prosazeile OHNE Kommentarzeichen sperrt weiter.
function InnerComment(const AComment: TRdxComment; const S: string): Boolean;
begin
  if Copy(S, 1, 2) = '//' then
    Exit(True);
  Result := (AComment.CloserText = '*)') and (Copy(S, 1, 1) = '{')
    and (Copy(S, 1, 2) <> '{$') and (Pos('}', S) = Length(S));
end;

// Sagt der innere Kommentar S, woher der Code stammt oder warum er bleibt
// (KEEP_WORDS als Wort, ohne Gross-/Kleinschreibung)? rwE30: Img32.pas:1434
// '// reference implementation' - der Autor hebt den Block bewusst auf.
function KeepNote(const S: string): Boolean;
var
  LowS : string;
  i    : Integer;
begin
  Result := False;
  LowS := LowerCase(S);
  for i := Low(KEEP_WORDS) to High(KEEP_WORDS) do
    if HasAsciiWord(LowS, KEEP_WORDS[i]) then
      Exit(True);
end;

// Ein case-Zweig 'A[, B]:' auf ALine (S = CodeText): mit Rest Code, wenn
// der Rest CodePiece besteht ('{caImmed: begin', rwE30 DAsmUtil.pas:1062);
// allein ('FS_NM_ACTION_ADD:', rwE30 ftpfunc.pas:1133) nur unter einem
// 'case ... of' weiter oben im selben Kommentar - 'Note:' oder 'Usage:'
// allein ist Prosa.
function CaseLabel(AMap: TRdxCodeMap; const AComment: TRdxComment;
  ALine: Integer; const S: string): Boolean;
var
  i, Li : Integer;
  Rest  : string;
  T     : string;
begin
  Result := False;
  i := 1;
  repeat
    if (i > Length(S)) or not IsIdentStart(S[i]) then
      Exit;
    while (i <= Length(S)) and IsIdentChar(S[i]) do
      Inc(i);
    i := SkipBlanks(S, i);
    if (i > Length(S)) or (S[i] <> ',') then
      Break;
    i := SkipBlanks(S, i + 1);
  until False;
  if (i > Length(S)) or (S[i] <> ':') or (Copy(S, i + 1, 1) = '=') then
    Exit;
  Rest := Trim(Copy(S, i + 1, MaxInt));
  if Rest <> '' then
    Exit(CodePiece(Rest));
  for Li := AComment.Body.Line to ALine - 1 do
  begin
    T := CodeText(PieceOn(AMap, AComment, Li, 1));
    if (FirstWordOf(T) = 'case') and (LastWordOf(T) = 'of') then
      Exit(True);
  end;
end;

// Ein Aufruf ohne ';' vor einem 'else' auf ALine (S = CodeText): 'Name(...)'
// bzw. 'A.B(...)', und die naechste nicht leere Zeile des Kommentars beginnt
// mit 'else' und besteht CodePiece. rwE30: 'Match(Scaner.Token)'
// (CnCodeFormatter.pas:4005), 'PutSFmt(...)' (DCURecs.pas:1772).
function CallBeforeElse(AMap: TRdxCodeMap; const AComment: TRdxComment;
  ALine: Integer; const S: string): Boolean;
var
  i, Li : Integer;
  T     : string;
begin
  Result := False;
  if (S = '') or not IsIdentStart(S[1]) then
    Exit;
  i := 1;
  while (i <= Length(S))
        and (IsIdentChar(S[i]) or CharInSet(S[i], ['.', '^'])) do
    Inc(i);
  i := SkipBlanks(S, i);
  if (i > Length(S)) or (S[i] <> '(') or (S[Length(S)] <> ')') then
    Exit;
  for Li := ALine + 1 to AComment.CloseAt.Line do
  begin
    T := Trim(PieceOn(AMap, AComment, Li, 1));
    if T <> '' then
      Exit((FirstWordOf(T) = 'else') and CodePiece(T));
  end;
end;

// Die erste Zeile von ALine1 bis ALine2, deren Text in AComment (ohne
// Begrenzer) weder CodePiece noch ein case-Zweig (CaseLabel) oder ein
// Aufruf vor 'else' (CallBeforeElse) ist und kein innerer Kommentar
// (InnerComment) ohne KeepNote; 0, wenn alle bestehen.
function NonCodeLine(AMap: TRdxCodeMap; const AComment: TRdxComment;
  ALine1, ALine2: Integer): Integer;
var
  Li : Integer;
  S  : string;
begin
  Result := 0;
  for Li := ALine1 to ALine2 do
  begin
    S := Trim(PieceOn(AMap, AComment, Li, 1));
    if InnerComment(AComment, S) then
    begin
      if KeepNote(S) then
        Exit(Li);
    end
    else if not CodePiece(S)
       and not CaseLabel(AMap, AComment, Li, CodeText(S))
       and not CallBeforeElse(AMap, AComment, Li, CodeText(S)) then
      Exit(Li);
  end;
end;

// Was geloescht wird (s. Kopf): immer ganze Kommentare, vom Oeffner des
// ersten bis hinter den Schliesser des letzten. Beginnt der erste vor R1
// bzw. endet der letzte hinter R2, muss sein Text dort leer oder Code sein
// (NonCodeLine) - sonst bliebe ein Torso stehen ('{ with X do }', '(*' /
// 'break;*)') oder Prosa ginge mit: keine Hilfe. Bis zur Fix-Charge rwE29
// blieb der Begrenzer dann stehen und nur die Region ging (KeepFront/
// KeepBack). '' oder der Grund.
function CommentCut(AMap: TRdxCodeMap; const ARegion: TRdxRegion;
  const AList: TRdxCommentList; out AFrom, ATo: TRdxTextPos): string;
var
  F, G : TRdxComment;
  Li   : Integer;
begin
  Result := '';
  F := AList[0];
  G := AList[High(AList)];
  AFrom := F.Open;
  ATo := G.Stop;
  Li := 0;
  if F.Open.Line < ARegion.First then
    Li := NonCodeLine(AMap, F, F.Body.Line, ARegion.First - 1);
  if (Li = 0) and (G.CloseAt.Line > ARegion.Last) then
    Li := NonCodeLine(AMap, G, ARegion.Last + 1, G.CloseAt.Line);
  if Li > 0 then
    Result := _('the finding covers only part of the comment (lines %d to '
      + '%d), and its line %d is not plainly code - the rest would stay '
      + 'behind as a torso; %s', [F.Open.Line, G.CloseAt.Line, Li,
      MsgDeleteByHand]);
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
  // Eigene msgid, nicht MsgNoColumn: der Satz nennt auch die Zeilenzahl
  // (c_groups Abschnitt 3).
  if not RegionOf(AMessage, ALine, Region) then
    AReason := _('the message has no column or line count')
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
  // What als ganze uebersetzte Nominalphrase; das Muster bleibt unformatiert
  // (%d = Zahl der Treffer) und der Name aus der Meldung kommt als Argument
  // dazu, nie ins Muster (Vertrag von OneTokenReason; bis zur Review Woche
  // G07-09 stand er im Muster).
  Result := OneTokenReason(ALine, n, _('no "%s"', [AKey]),
    _('%d times "%s"'), AKey);
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
      Exit(_('name list not readable'));
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
      Exit(_('name list not readable'));
    ADecl.Last := W;
    Inc(ADecl.Count);
    P := After(AMap, W);
  end;
  ADecl.Colon := P;
end;

// Ein Token des Typs auf oberster Klammerebene: Initialisierer, absolute,
// Typ ueber mehrere Zeilen oder ein Wort, das in keinem Typ steht? '' oder
// der Grund. 'procedure of object' und 'class of TFoo' stehen auf einer
// Zeile - 'object' hinter 'of' und 'class' vor 'of' oeffnen keinen
// Typrumpf (bis zur Review Woche G07-10 lehnte die Hilfe beide mit 'Typ
// ueber mehrere Zeilen' ab).
function TypeTokenReason(AMap: TRdxCodeMap; const T, APrev: TRdxToken): string;
begin
  Result := '';
  if (T.Low = '=') or (T.Low = ':=') then
    Result := _('initialized variable - the expression can have side effects')
  else if not IsKeywordAfter(T, APrev) then
    Exit
  else if T.Low = 'absolute' then
    Result := _('absolute variable - it occupies the memory of another one')
  else if ((T.Low = 'object') and (APrev.Low = 'of'))
     or ((T.Low = 'class') and (After(AMap, T).Low = 'of')) then
    Exit
  else if InList(T.Low, MULTI_LINE_TYPES) then
    Result := _('type with "%s" (across several lines) - %s',
      [T.Low, MsgDeleteByHand])
  else if InList(T.Low, TYPE_STOPS) then
    Result := _('"%s" in the type - declaration not readable', [T.Low]);
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
      Exit(_('bracket without a counterpart in the type'));
    if Depth = 0 then
    begin
      Result := TypeTokenReason(AMap, T, Prev);
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
  Result := _('no ";" after the type');
end;

// Die Form der Deklaration: 'for var', Initialisierer, Typ bis ';', keine
// Aufrufkonvention dahinter. Setzt ADecl.Semi. '' oder der Grund.
function ShapeReason(AMap: TRdxCodeMap; var ADecl: TRdxVarDecl): string;
var
  N : TRdxToken;
begin
  if (ADecl.Lead.Low = 'var') and (Before(AMap, ADecl.Lead).Low = 'for') then
    Exit(_('for var - the control variable of a loop (the detector does not '
      + 'count the loop header as a use) - no quick fix'));
  if ADecl.Colon.Low = ':=' then
    Exit(_('inline declaration with initializer ":=" - the expression can '
      + 'have side effects'));
  if ADecl.Colon.Low <> ':' then
    Exit(MsgMovedSuffix(_('no ":" after the name list ("%s")',
      [ADecl.Colon.Low])));
  Result := TypeEnd(AMap, ADecl.Colon, ADecl.Semi);
  if Result <> '' then
    Exit;
  N := After(AMap, ADecl.Semi);
  if IsKeywordAfter(N, ADecl.Semi) and InList(N.Low, CALL_CONVENTIONS) then
    Result := _('"%s" after the type still belongs to the declaration - %s',
      [N.Low, MsgDeleteByHand]);
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
    Result := InList(T.Low, SECTION_WORDS) or InList(T.Low, UNIT_PARTS)
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
     or InList(T.Low, UNIT_PARTS) then
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
    Result := _('local %s section - not a variable', [K.Low])
  else if K.Low = '' then
    Result := _('no var section before the declaration')
  else
    Result := _('the declaration is not in a var section ("%s")', [K.Low]);
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
    Exit(_('attribute before the declaration - %s', [MsgDeleteByHand]))
  else if ADecl.Lead.Low = '[' then
    Exit(_('the name is inside an attribute ("[...]") - not a variable'))
  else if ADecl.Lead.Low = 'var' then
    ADecl.VarTok := ADecl.Lead
  else if ADecl.Lead.Low = ';' then
    Result := SectionReason(AMap, ADecl)
  else
    // Eigene msgid nach dem Muster von MsgUnclearStatementOwner - hier
    // ist die Deklaration das Subjekt (c_groups Abschnitt 3).
    Result := _('unclear what the declaration belongs to ("%s" before it)',
      [ADecl.Lead.Low]);
  if (Result = '') and InOpenParen(AMap, ADecl.First) then
    Result := _('the declaration is inside an open parenthesis - a parameter '
      + 'of a routine or of a procedural type, not a local variable');
  if Result <> '' then
    Exit;
  if Before(AMap, ADecl.VarTok).Low = 'class' then
    Exit(_('class var - a class field, not a local variable'));
  ADecl.InBlock := InsideBlock(AMap, ADecl.VarTok, ADecl.Stop);
  // Endet die Suche an case, asm oder record (BlockStep, rsStop), steht
  // davor meist der Variantenteil eines lokalen Records: sein case hat
  // kein eigenes end, die Bilanz zaehlt das end des Records zum case und
  // trifft das record auf Tiefe 0 (SectionStep kennt case darum nicht).
  // Das sperrt - mit diesem Grund; bis zur Review Woche G07-10 hiess es
  // 'globale Variable?', obwohl die Variable lokal war.
  if ADecl.InBlock and (ADecl.Lead.Low <> 'var') then
    Result := _('declaration after ";" in a statement block - unclear')
  else if not ADecl.InBlock and InList(ADecl.Stop.Low, BLOCK_PAIRS) then
    Result := _('the search for the routine ends at "%s" (line %d) - perhaps '
      + 'the variant part of a local record whose case has no end of its '
      + 'own; what the declaration belongs to is unclear - no quick fix',
      [ADecl.Stop.Low, ADecl.Stop.Line])
  else if not ADecl.InBlock and not InList(ADecl.Stop.Low, ROUTINE_WORDS) then
    Result := _('no routine around the declaration (global variable?) - no '
      + 'quick fix');
end;

// Die Routine, deren Deklarationsteil die var-Section von ADecl traegt:
// ab dem Kopf, an dem die Rueckwaertssuche endete (ADecl.Stop); endet deren
// Routine vor der Section (eine lokale Routine davor), weiter ab ihrem Kopf
// rueckwaerts. Die Grenzen liest der Baustein ReadRoutine
// (uRdxBlocks, bis Charge B2S-b in uRdxRoutineFixes) - bis Charge H3c
// hatte SCA053 einen eigenen Leser
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
    // Den Grund von ReadRoutine uebersetzt uRdxBlocks; er steht hier als
    // %s im eigenen Satz (Texte umstellen: der Aufrufer uebersetzt).
    Result := TRdxBlocks.ReadRoutine(AMap, H, R);
    if Result <> '' then
      Exit(_('routine body not found - %s', [Result]));
    if not TokAfter(ADecl.VarTok, R.Last) then
      Exit('');
    if InsideBlock(AMap, H, Stop) or not InList(Stop.Low, ROUTINE_WORDS) then
      Exit(_('routine body not found'));
    H := Stop;
  end;
  Result := _('routine body not found - too many local routines');
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
      Exit(_('the name still occurs in the scope (line %d) - under {$IFDEF} '
        + 'and in asm it also counts as a use', [T.Line]));
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
    Exit(_('{$I} include in the scope (line %d) - it may contain the name in '
      + 'a place that the quick fix does not see', [Li]));
  Li := DirectiveNaming(AMap, AFrom.Line, ATo.Line, AKey);
  if Li > 0 then
    Exit(_('a directive names "%s" (line %d) - macro or condition, the quick '
      + 'fix does not evaluate it', [AKey, Li]));
  P := Before(AMap, AFrom);
  T := AFrom;
  while (T.Low <> '') and not TokAfter(T, ATo) do
  begin
    if (T.Low = 'asm') and IsKeywordAfter(T, P) then
      Exit(_('asm in the scope (line %d) - assembler can address the '
        + 'variable via the stack frame, without its name', [T.Line]));
    P := T;
    T := After(AMap, T);
  end;
end;

// Ein FPC-Makro irgendwo in der Datei, das den Namen einsetzt ('{$DEFINE M
// := X}' vor der Routine, M im Rumpf)? Die Durchsicht des
// Gueltigkeitsbereichs sieht nur M. '' oder der Grund. Die Spalten liest
// nur eine Zeile, die ein Wort aus MACRO_WORDS nennt (HasWordNoCase, wie
// die Vorfilter aus Review R3-03): '{$DEFINE' traegt es als Wort ('$'
// davor ist kein Bezeichnerzeichen). Bis zur Review Woche G07-02 lief die
// Frage je SCA053-Fund ueber jedes Zeichen der Datei - im IDE-Hauptthread,
// beim Aufbau des Menues.
function MacroReason(AMap: TRdxCodeMap; const AKey: string): string;
var
  Li, Co : Integer;
  Arg    : Boolean;
  Args   : string;
begin
  Result := '';
  for Li := 1 to AMap.LineCount do
  begin
    if not HasWordNoCase(AMap.Raw(Li), MACRO_WORDS[0])
       and not HasWordNoCase(AMap.Raw(Li), MACRO_WORDS[1]) then
      Continue;
    for Co := 1 to Length(AMap.Raw(Li)) do
      if OpensDirective(AMap, Li, Co)
         and InList(DirectiveWord(AMap, Li, Co, Arg), MACRO_WORDS) then
      begin
        Args := LowerCase(DirectiveArgs(AMap, Li, Co));
        if (Pos(MACRO_ASSIGN, Args) > 0) and HasIdentWord(Args, AKey) then
          Exit(_('a macro inserts "%s" ({$DEFINE ... := ...} in line %d) - '
            + 'the quick fix does not see its use', [AKey, Li]));
      end;
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
      Exit(_('no end of the block around the declaration found'));
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
// ist im Text nicht erkennbar - Restrisiko. '' oder der Grund. Nur die
// Token der Zeilen, die 'operator' nennen (NextTokenOnLineWith, wie
// uRdxFlowFixes.DeclaresAssignOperator seit Charge FC) - der Name dahinter
// darf auf der Folgezeile stehen, After liest ihn dort. Bis zur Review
// Woche G07-02 las die Frage je SCA053-Fund jedes Token der Datei.
function ManagedRecordReason(AMap: TRdxCodeMap): string;
const
  KW_OPERATOR = 'operator';
var
  T, N : TRdxToken;
begin
  Result := '';
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), KW_OPERATOR);
  while T.Low <> '' do
  begin
    if T.Low = KW_OPERATOR then
    begin
      N := After(AMap, T);
      if (N.Low = 'initialize') or (N.Low = 'finalize') then
        Exit(_('the unit declares a class operator Initialize/Finalize '
          + '(managed record) - a variable can run code'));
    end;
    T := NextTokenOnLineWith(AMap, T, KW_OPERATOR);
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
    Exit(_('unclear what the inline declaration belongs to ("%s" before it)',
      [P.Low]));
  N := After(AMap, ADecl.Semi);
  if (N.Low = '') or InList(N.Low, LIST_ENDS) then
    Result := MsgOnlyStatementEmptyBlock(P.Low);
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
    Exit(_('comment in the declaration - it would be lost'));
  if ADecl.InBlock then
    Directive := DirectiveInLines(AMap, ADecl.VarTok.Line, ADecl.Semi.Line)
  else
    Directive := DirectiveBefore(AMap, ADecl.VarTok.Line,
      After(AMap, ADecl.Semi));
  if Directive then
    Result := _('directive in the declaration or its var section - a branch '
      + 'could become empty');
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
// (uRdxBlocks.MarkerAboveReason; Nachpruefung B1-FD: der Marker
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
    Result := MsgMovedSuffix(_('the name list does not start on the reported '
      + 'line'));
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
    AReason := _('the message has no variable name')
  else if InList(Key, RESERVED) then
    AReason := _('"%s" is a keyword, not a variable (the parser read a '
      + 'section as a variable) - no quick fix', [Key])
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

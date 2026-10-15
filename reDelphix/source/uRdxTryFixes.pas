unit uRdxTryFixes;

// reDelphix - Quick-Fixes "try/finally", OHNE ToolsAPI und ohne Parser
// (Konzept_Editorhilfen_Recherche_2026-10-11, Abschnitt 5 Baustein B5,
// Abschnitt 6 Charge H4; Gegen-Review H4 in Charge H4c):
//   SCA009 MissingFinally: 'X := TFoo.Create..;' .. 'X.Free;' (auch
//          'FreeAndNil(X)', qualifiziert 'SysUtils.FreeAndNil(X)',
//          'X.Destroy') - die Zeilen dazwischen kommen in den try-Teil, die
//          Freigabe ins finally; ein direkt folgendes 'X := nil;' geht mit,
//          wenn es allein auf seiner Zeile steht bzw. die Zeile von B
//          beschliesst. Das Meldungs-Suffix ' (try/except instead of
//          try/finally)' sagt nur, dass die METHODE irgendwo ein try/except
//          hat (uMissingFinally: HasExcept rekursiv), nichts ueber den Ort -
//          der Planer liest nur den Namen davor. Bis Charge H4c verlangte er
//          mit dem Suffix ein try/except im Bereich und keines drumherum;
//          das war ein Lesefehler des Detektors (Gegen-Review H4, Major 1):
//          ein umschliessendes try/except, dessen Handler X nicht nennt, ist
//          nach dem Fix richtig (erst finally, dann der Handler); nennt er
//          X, sperrt die Handler-Pruefung (EnclosingReason).
//   SCA001 MemoryLeak: dieselbe Hilfe, nur fuer die Variante
//          freed-outside-finally - die prueft der Aufrufer (uRdxFixTable,
//          Feld TLeakFinding.LeakVariant); proven-leak, never-freed und
//          return-value bekommen keine.
//   SCA109 LockWithoutTryFinally, SCA153 UnpairedLock: die Sperre (Lock/
//          UnLock, Enter/Leave, Acquire/Release, BeginWrite/EndWrite,
//          TMonitor.Enter(O)/TMonitor.Exit(O), EnterCriticalSection(CS)/
//          LeaveCriticalSection(CS)). Die Freigabe B bestimmt der Planer
//          selbst: derselbe Empfaenger bzw. dasselbe Argument, als Text
//          ohne Leerraum gleich - SCA153 nimmt jedes 'unlock'/'release' im
//          200-Zeichen-Fenster, auch das fremder Objekte.
//   SCA156 GetMemWithoutFreeMem: 'GetMem(P, N);' bzw. 'P := AllocMem(N);'
//          (auch FPC 'P := GetMem(N);', auch 'System.GetMem', auch als
//          Inline-Deklaration 'var P[: T] := AllocMem(N);') ..
//          'FreeMem(P);' - ein direkt folgendes 'P := nil;' geht mit wie bei
//          Objekten; ReallocMem sperrt (der Puffer bestand schon vorher), P
//          muss eine lokale Variable der Routine sein (Charge B1,
//          HolderReason).
//
// BAUSTEIN B5 (TryFinally): A ist eine ganze Anweisung in einer
// Anweisungsliste (davor ';', begin, try, finally, except, repeat), B ihre
// Freigabe als ganze, UNBEDINGTE Anweisung in DERSELBEN Liste dahinter
// (Blocktiefe 0, hinter ';'). Ergebnis:
//     A;
//     try
//       <die Zeilen dazwischen, eine Stufe tiefer>
//     finally
//       B;
//     end;
// try/finally/end in eigenen Zeilen, eingerueckt wie A; die Stufe ist die
// der Liste (Einrueckung von A gegen die ihres Oeffners), sonst zwei
// Leerzeichen bzw. ein Tab - sie kommt hinter den Leerraum, den eine Zeile
// mit A teilt (gemischte Einrueckung bleibt in ihrer Art). Leerzeilen
// bleiben leer.
//
// WIRKUNG (alle gekennzeichnet, Entscheid E2 - Strg+Alt+F laesst sie aus):
// B laeuft danach auch bei einer Ausnahme zwischen A und B - das ist der
// Fix, den der Detektor verlangt -, bei Objekten und Puffern auch bei Exit.
//
// SPERREN (lieber keine Hilfe als eine falsche):
//   * A hinter then/else/do ohne begin, als case-Zweig, nicht als erste
//     Anweisung ihrer Zeile oder mit weiterem Code dahinter; B nicht als
//     erste Anweisung ihrer Zeile oder mit Code dahinter (try/finally/end
//     stehen in eigenen Zeilen);
//   * keine unbedingte Freigabe in derselben Liste (B tiefer, in einem
//     anderen Zweig oder Block), eine zweite bzw. bedingte Freigabe oder
//     eine zweite Zuweisung/Sperre im Bereich (Doppelfreigabe), nichts
//     zwischen A und B (es gaebe nichts zu schuetzen);
//   * eine Freigabe in ANDERER Schreibweise im Bereich (Gegen-Review H4,
//     Minor 1 - nach dem Fix liefe sie doppelt): 'Self.FLock.Leave' bzw.
//     'TFoo(FLock).Leave' gegen 'FLock', Leave/Release fuer Enter/Acquire
//     (TCriticalSection kennt beide), 'LeaveCriticalSection(Self.FCS)',
//     'TObject(X).Free', 'Self.X.Free', 'FreeMem(PByte(P))'; B selbst muss
//     genau so heissen wie A;
//   * Direktive, Marke/goto (ein Sprung in einen try-Block uebersetzt
//     nicht), Inline-var/const auf der Ebene von A (ihr Gueltigkeitsbereich
//     schrumpfte auf den try-Block), mehrzeiliges '''-Literal (Einruecken
//     aendert den String), asm im Bereich;
//   * Break/Continue, deren Schleife den Bereich umschliesst (B liefe dort
//     jetzt mit - ein Objekt, das hinter der Schleife noch gebraucht wird,
//     waere frei); Exit bei einer Sperre (Konzept: Ablehnung); Exit bei
//     einem Objekt bzw. Puffer, der im Bereich irgendwie weitergegeben wird
//     (der Ausstieg koennte den Besitz uebergeben haben) - die Spruenge
//     auch als 'System.Exit'/'System.Break'/'System.Continue' (Charge B1,
//     SystemQualified); X in einem raise-Ausdruck ('raise X', 'raise
//     TObject(X)', 'raise X at ..') oder als Argument von
//     RaiseOuterException/ThrowOuterException;
//   * Weitergabe auch OHNE Ausstieg (Objekt, Puffer; Gegen-Review H4,
//     Blocker 1 - im Fehlerfall gaebe finally X frei, waehrend ein Halter es
//     noch kennt: aus einem Leck wuerde ein Use-after-free): X als direktes
//     Argument eines Aufrufs, dessen Name mit add/insert/push/enqueue/
//     register/attach/subscribe/put beginnt (ausser InsertComponent - der
//     Destruktor meldet sich beim Owner ab - und AddStrings, das nur den
//     Inhalt kopiert); X als ganze rechte Seite einer Zuweisung an etwas
//     anderes als eine lokale Variable der Routine (Feld, Property,
//     Element, Result, globale Variable, Parameter); ein Methodenzeiger
//     'X.M' an ein Ereignis (Ziel 'On..'/'FOn..'); '@X' bzw. '@X.M'. X
//     auch in Huellen - Typumwandlung, Klammern, 'as', beliebig tief
//     geschachtelt ('List.Add(TObject(X))', 'FCurrent := X as TFoo', seit
//     Charge B1 WrappedAt).
//     Bewusst eng (Entscheid H4c): die breite Fassung - jedes Argument,
//     jede Zuweisung - kostete im Referenzkorpus 372 von 909
//     Objekt-Angeboten;
//   * die Variable (bzw. die Freigabe der Sperre) im except-/finally-Teil
//     eines try, das A umschliesst - nach dem Fix liefe dort eine zweite
//     Freigabe bzw. ein Zugriff auf ein freigegebenes Objekt;
//   * Puffer: Inc/Dec/GetMem/ReallocMem auf P - auch durch eine
//     Typumwandlung ('Inc(PByte(P), 4)') - bzw. '@P' im Bereich (FreeMem
//     gaebe einen anderen Zeiger frei); P keine lokale Variable der Routine
//     (Feld, globale Variable, Parameter - nach finally kennte der Halter
//     den freien Puffer, Gegen-Review R5, R5-02).
// Was bleibt (README, Restrisiken): eine Weitergabe ueber einen Alias
// ('Y := X; List.Add(Y)'), an einen Konstruktor, der den Besitz uebernimmt
// ('TReader.Create(X)'), an einen Aufruf anderen Namens ('Store(X)') oder
// als Methodenzeiger im Argument ('Subscribe(X.Handler)').

interface

uses
  uRdxBufferMath, uRdxCodeMap;

type
  // Ergebnis der Planer: die eine Ersetzung und der Name fuer den
  // Menuetext - X, die Sperre bzw. der Puffer; schon aus der Meldung, auch
  // wenn der Planer ablehnt, nach einem Treffer wie im Quelltext.
  TRdxTryPlan = record
    Edit : TRdxEdit;
    Name : string;
  end;

  // Die Form der Planer (uRdxFixTable: TryForm im Geruest TRdxFixFrame).
  TRdxTryPlanner = function(AMap: TRdxCodeMap; ALine: Integer;
    const AMessage: string; out APlan: TRdxTryPlan;
    out AReason: string): Boolean;

  // Die Planer der Charge H4 (s. Kopf): je Fund EINE Ersetzung oder der
  // Grund, warum keine - auf dem Puffertext ueber die Code-Sicht (laeuft
  // auch im FPC-Pruefstand).
  TRdxTryFixes = class
  public
    // SCA009: die Erzeugung von X (Meldung: 'X', auch mit dem Suffix
    // ' (try/except instead of try/finally)' - es sagt nichts ueber den
    // Ort, s. Kopf) auf ALine und ihre Freigabe in try/finally setzen.
    class function MissingFinally(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxTryPlan;
      out AReason: string): Boolean; static;

    // SCA001, Variante freed-outside-finally (Meldung: 'X'): dieselbe
    // Hilfe; die Variante prueft der Aufrufer.
    class function FreedOutsideFinally(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxTryPlan;
      out AReason: string): Boolean; static;

    // SCA109: die Sperre der Meldung 'Lock acquired (FLock) but no ...'
    // ('EnterCriticalSection(...)', 'TMonitor.Enter(o)') auf ALine.
    class function LockWithoutFinally(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxTryPlan;
      out AReason: string): Boolean; static;

    // SCA153: die Sperre der Meldung '... leaks the lock (FLocker.Lock)'
    // ('Lock', 'EnterCriticalSection') auf ALine.
    class function UnpairedLock(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxTryPlan;
      out AReason: string): Boolean; static;

    // SCA156: die Allokation der Meldung 'GetMem without surrounding
    // try/finally - ...' (AllocMem, ReallocMem) auf ALine.
    class function GetMemWithoutFree(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxTryPlan;
      out AReason: string): Boolean; static;

    // Der Bezeichner am Anfang der Meldung (SCA009/SCA001: X, auch vor
    // ' (try/except ...)' bzw. ' - Rueckgabewert'); '' ohne.
    class function NameOf(const AMessage: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxStructFixes,   // RangeText, CommentInRange, CanAppendLine
  uRdxRoutineFixes;  // ReadRoutine (lokale Variablen der Routine um A)

const
  SPAN_TRY = 'try';
  KEY_LOCK109  = 'Lock acquired (';
  KEY_LOCK109E = ') but no enclosing';
  KEY_LOCK153  = 'leaks the lock (';
  KEY_LOCK153E = ')';
  ANY_CALL_109 = 'entercriticalsection(...)';
  // Davor beginnt eine Anweisung IN einer Anweisungsliste.
  LIST_PREV: array[0..7] of string = (';', 'begin', 'try', 'finally',
    'except', 'repeat', 'initialization', 'finalization');
  // Zweige ohne begin: dahinter steht genau eine Anweisung.
  BRANCH_WORDS: array[0..2] of string = ('then', 'else', 'do');
  // Hier endet eine Anweisungsliste.
  LIST_ENDS: array[0..3] of string = ('end', 'until', 'except', 'finally');
  // Hier endet die Rueckwaerts-Suche nach umschliessenden try-Bloecken.
  UNIT_BOUNDS: array[0..6] of string = ('implementation', 'interface',
    'initialization', 'finalization', 'unit', 'program', 'library');
  // Freigaben eines Objekts ('X.Free') bzw. eines Puffers ('FreeMem(P)').
  FREE_METHODS: array[0..2] of string = ('free', 'destroy', 'disposeof');
  FREE_AND_NIL = 'freeandnil';
  FREEMEM_WORDS: array[0..1] of string = ('freemem', 'freememandnil');
  // Sie veraendern P (Puffer): FreeMem gaebe danach einen anderen Zeiger
  // frei.
  BUFFER_CHANGERS: array[0..3] of string = ('inc', 'dec', 'getmem',
    'reallocmem');
  // Hinter X: ein Member-Zugriff, keine Weitergabe von X.
  MEMBER_SUFFIXES: array[0..2] of string = ('.', '[', '^');
  // Davor bzw. dahinter: ein direktes Argument ('F(X)', 'F(A, X, B)').
  ARG_STARTS: array[0..1] of string = ('(', ',');
  ARG_ENDS: array[0..1] of string = (',', ')');
  // Weitergabe ohne Ausstieg (Blocker 1, s. Kopf): ein Aufruf, dessen Name
  // so beginnt, haelt ein direktes Argument fest ...
  STORE_PREFIXES: array[0..7] of string = ('add', 'insert', 'push',
    'enqueue', 'register', 'attach', 'subscribe', 'put');
  // ... ausser diesen: InsertComponent - TComponent.Destroy meldet sich
  // beim Owner ab (RemoveComponent), Free im finally laesst dort keinen
  // Verweis zurueck; AddStrings kopiert nur Strings und Objects von X.
  STORE_HARMLESS: array[0..1] of string = ('insertcomponent', 'addstrings');
  // Sie werfen ihr Argument als Ausnahme (wie 'raise X').
  RAISE_CALLS: array[0..1] of string = ('raiseouterexception',
    'throwouterexception');
  // Typumwandlungen ohne T/P/I-Namen (IsCastName).
  CAST_WORDS: array[0..6] of string = ('pointer', 'nativeint', 'nativeuint',
    'integer', 'cardinal', 'int64', 'uint64');
  // So viele Token liest der Planer rueckwaerts bis zum Anfang des Ziels
  // einer Zuweisung - laenger heisst: kein Ziel, das er sicher liest.
  MAX_TARGET_TOKENS = 64;
  // Abschnitte im Deklarationsteil einer Routine: nur var deklariert
  // Variablen; davor bzw. dahinter steht ein deklarierter Name ('var A,
  // B: T;').
  VAR_SECTIONS: array[0..1] of string = ('var', 'threadvar');
  SECTION_WORDS: array[0..5] of string = ('var', 'threadvar', 'const', 'type',
    'label', 'resourcestring');
  DECL_PREV: array[0..3] of string = ('var', 'threadvar', ';', ',');
  DECL_NEXT: array[0..1] of string = (':', ',');
  // Ein Ereignis heisst 'On..' bzw. als Feld 'FOn..' (Ziel eines
  // Methodenzeigers 'X.M').
  EVENT_PREFIX = 'on';
  EVENT_FIELD  = 'FOn';
  SELF_WORD = 'self';
  SELF_DOT  = 'self.';
  // Schleifenkoepfe bis zum do.
  LOOP_HEADS: array[0..1] of string = ('for', 'while');
  INLINE_DECLS: array[0..1] of string = ('var', 'const');
  JUMP_OUT: array[0..1] of string = ('break', 'continue');
  // Die Spruenge, die auch qualifiziert stehen ('System.Exit', SpanStep).
  SYSTEM_UNIT = 'system';
  SYSTEM_JUMPS: array[0..2] of string = ('exit', 'break', 'continue');
  // Blockarten je Tiefe (TRdxSpan.Kinds).
  BLOCK_LOOP  = 'L';
  BLOCK_CASE  = 'C';
  BLOCK_OTHER = 'B';
  HEAD_LOOP = 'L';
  HEAD_WITH = 'W';
  // Eine Stufe der Liste darf so breit sein - sonst die Vorgabe
  // (IndentStep): eine ausgerichtete Zeile ('1: begin' und darunter weit
  // eingerueckt) ist keine Stufe.
  MAX_STEP = 4;
  // Die zweite Haelfte eines UTF-16-Surrogatpaars (TryEdit).
  LOW_SURROGATE_FIRST = $DC00;
  LOW_SURROGATE_LAST  = $DFFF;
  R_MOVED = 'Zeile verschoben? Datei neu pruefen';
  R_BY_HAND = 'von Hand pruefen';
  R_HELD = 'bei einer Ausnahme gaebe finally es frei, waehrend der Halter '
    + 'es noch kennt; von Hand pruefen';

type
  TRdxPairKind = (pkObject, pkLock, pkBuffer);
  TRdxLockForm = (lfMethod, lfCall, lfMonitor);
  TRdxLockSide = (sdAcquire, sdRelease);

  // Eine Sperr- bzw. Freigabe-Anweisung (LockSiteAt).
  TRdxLockSite = record
    Form    : TRdxLockForm;
    First   : TRdxToken;   // erstes Token
    CallTok : TRdxToken;   // Methode bzw. Funktion ('Enter', 'EnterCriticalSection')
    Owner   : TRdxToken;   // lfMethod: letztes Token des Empfaengers; Low = '' ohne
    Last    : TRdxToken;   // letztes Token des Aufrufs (Methode, ')' von '()' bzw. der Argumente)
    Meth    : Integer;     // lfMethod: Index in LOCK_PAIRS
    Key     : string;      // Empfaenger bzw. Argument, ohne Leerraum, klein
    Name    : string;      // dasselbe wie im Quelltext (Menuetext)
  end;

  // Eine Freigabe (ReleaseAt): das Token mit dem Namen (Objekt, Puffer)
  // und das letzte Token des Aufrufs.
  TRdxReleaseHit = record
    KeyTok : TRdxToken;
    Last   : TRdxToken;
  end;

  // Eine Erzeugung (CreateAt): ihr erstes Token ('X' bzw. 'var') und ':='.
  TRdxCreateSite = record
    First  : TRdxToken;
    Assign : TRdxToken;
  end;

  // Ein Paar A/B fuer den Baustein (s. Kopf).
  TRdxPair = record
    Kind   : TRdxPairKind;
    Lock   : TRdxLockSite;   // pkLock: die Sperre A
    Key    : string;         // pkObject/pkBuffer: die Variable, klein
    Name   : string;         // X, die Sperre bzw. P wie im Quelltext (Menuetext)
    What   : string;         // die Freigabe fuer die Gruende ('X.Free', 'FLock.Leave')
    First  : TRdxToken;      // erstes Token von A
    Semi   : TRdxToken;      // das ';' hinter A
  end;

  // Der Lauf von A nach B (ScanSpan): Klammern, Bloecke und Schleifen, was
  // er sah, und B.
  TRdxSpan = record
    Depth      : Integer;          // Blocktiefe ab A
    Paren      : Integer;
    Kinds      : string;           // je Tiefe: BLOCK_LOOP, BLOCK_CASE, BLOCK_OTHER
    Heads      : string;           // offene Koepfe bis zum do (HEAD_LOOP, HEAD_WITH)
    LoopDo     : Boolean;          // das Token davor war das do einer Schleife
    NextBegin  : Char;             // Art des naechsten begin (BLOCK_LOOP hinter do)
    Singles    : TArray<Integer>;  // Tiefen offener Schleifenrumpfe ohne begin
    HasCode    : Boolean;
    ExitLine   : Integer;          // erstes Exit, 0 = keins
    Escape     : TRdxToken;        // erste Weitergabe von X (fuer Exit); Low = '' ohne
    B          : TRdxToken;        // erstes Token der Freigabe
    BLast      : TRdxToken;        // ihr letztes (';' bzw. 'X := nil;')
    Reason     : string;
    procedure PushBlock(AKind: Char);
    procedure PopBlock;
    procedure EndSingles;
    procedure TakeLoopDo(const T: TRdxToken);
    function InLoop: Boolean;
    function InnerKind: Char;
  end;

  // Die Rueckwaerts-Suche nach den try-Bloecken um A (EnclosingTries):
  // offene Bloecke, ob ein except/finally auf der Ebene gekreuzt wurde (A
  // steht dann in dessen Handler, nicht im try-Teil) und die Funde.
  TRdxTryScan = record
    Depth   : Integer;
    Crossed : Boolean;
    Tries   : TArray<TRdxToken>;
    function Step(const T, APrev: TRdxToken): Boolean;
    procedure Opener(const T: TRdxToken);
  end;

const
  // Sperre und Freigabe je Form (Index Meth bzw. Seite).
  LOCK_PAIRS: array[0..3, TRdxLockSide] of string = (('lock', 'unlock'),
    ('enter', 'leave'), ('acquire', 'release'), ('beginwrite', 'endwrite'));
  // Dieselben fuer die Gruende, wie Delphi sie schreibt.
  RELEASE_CAPS: array[0..3] of string = ('UnLock', 'Leave', 'Release',
    'EndWrite');
  // Familie je Index von LOCK_PAIRS: Enter/Leave und Acquire/Release sind
  // bei TCriticalSection dieselbe Sperre (SameLockLoose).
  LOCK_FAMILY: array[0..3] of Integer = (0, 1, 1, 2);
  LOCK_CALLS: array[TRdxLockSide] of string = ('entercriticalsection',
    'leavecriticalsection');
  MONITOR_CALLS: array[TRdxLockSide] of string = ('enter', 'exit');
  MONITOR_TRY = 'tryenter';
  // SCA109 meldet nur diese Methoden (uLockWithoutTryFinally).
  METHODS_109: array[0..2] of string = ('enter', 'acquire', 'beginwrite');

{ ---- kleine Helfer ---- }

// Ohne Leerraum und klein - wie Empfaenger und Argumente verglichen werden.
// Zeichen fuer Zeichen, ohne Verkettung in der Schleife (SCA110).
function NoBlanksLower(const S: string): string;
var
  i, n : Integer;
begin
  SetLength(Result, Length(S));
  n := 0;
  for i := 1 to Length(S) do
    if not CharInSet(S[i], [' ', #9, #10, #13]) then
    begin
      Inc(n);
      Result[n] := S[i];
    end;
  SetLength(Result, n);
  Result := LowerCase(Result);
end;

// Der Text von AFrom bis ATo ohne Leerraum, klein; '' bei einem Kommentar
// darin (er stuende sonst im Schluessel).
function KeyText(AMap: TRdxCodeMap; const AFrom, ATo: TRdxToken): string;
var
  Span : TRefactorSpan;
begin
  Span := TRefactorSpan.Make(SPAN_TRY, AFrom.Line, AFrom.Col, ATo.Line,
    ATo.EndCol);
  if CommentInRange(AMap, Span) then
    Exit('');
  Result := NoBlanksLower(RangeText(AMap, Span));
end;

// Derselbe Text wie im Quelltext (Menuetext), Zeilen mit Leerzeichen.
function SourceText(AMap: TRdxCodeMap; const AFrom, ATo: TRdxToken): string;
begin
  Result := Trim(StringReplace(RangeText(AMap, TRefactorSpan.Make(SPAN_TRY,
    AFrom.Line, AFrom.Col, ATo.Line, ATo.EndCol)), #10, ' ', [rfReplaceAll]));
end;

// Der Text zwischen AOpen und dem ersten ACloser dahinter; '' ohne.
function MessagePart(const AMessage, AOpen, ACloser: string): string;
var
  P, Q : Integer;
begin
  Result := '';
  P := Pos(AOpen, AMessage);
  if P = 0 then Exit;
  Inc(P, Length(AOpen));
  Q := Pos(ACloser, AMessage, P);
  if Q > 0 then
    Result := Copy(AMessage, P, Q - P);
end;

// Wie MessagePart, aber bis zur LETZTEN ')' (SCA153: '(FLocker.Lock)' am
// Ende; 'EnterCriticalSection' hat keine Klammer darin).
function MessageTail(const AMessage, AOpen: string): string;
var
  P, Q : Integer;
begin
  Result := '';
  P := Pos(AOpen, AMessage);
  if P = 0 then Exit;
  Inc(P, Length(AOpen));
  Q := LastDelimiter(KEY_LOCK153E, AMessage);
  if Q >= P then
    Result := Copy(AMessage, P, Q - P);
end;

// Das erste Wort der Meldung (SCA009/SCA001: der Variablenname - so faellt
// das Suffix ' (try/except ...)' weg, s. Kopf -, auch vor ' -
// Rueckgabewert'); '' ohne.
function FirstWordOf(const AMessage: string): string;
var
  i : Integer;
begin
  Result := '';
  if (AMessage = '') or not IsIdentStart(AMessage[1]) then Exit;
  i := 1;
  while (i <= Length(AMessage)) and IsIdentChar(AMessage[i]) do
    Inc(i);
  Result := Copy(AMessage, 1, i - 1);
end;

// Ist T das Wort AKey (klein) und kein Member ('.X')? Ein Umlaut zaehlt
// wie bei SameIdent - ein Treffer zu viel sperrt nur.
function MentionsKey(const T, APrev: TRdxToken; const AKey: string): Boolean;
begin
  Result := T.IsWord and (APrev.Low <> '.') and SameIdent(T.Low, AKey);
end;

// end/until/except/finally als Schluesselwort (IsKeywordAt: 'End := 1' ist
// ein benanntes Argument).
function IsListEnd(AMap: TRdxCodeMap; const T, APrev: TRdxToken): Boolean;
begin
  Result := IsKeywordAt(AMap, T, APrev) and InList(T.Low, LIST_ENDS);
end;

// Endet an N (APrev davor) die Anweisung - ';', das Listenende oder else?
function EndsStatement(AMap: TRdxCodeMap; const N, APrev: TRdxToken): Boolean;
begin
  Result := (N.Low = ';') or (IsKeywordAt(AMap, N, APrev)
    and (InList(N.Low, LIST_ENDS) or (N.Low = 'else')));
end;

// FirstOnLine (steht T als erstes auf seiner Zeile?) steht seit Charge H5c
// in uRdxCodeMap - uRdxResultFixes hatte eine Variante.

// Hinter '()' (leere Klammern) dessen ')', sonst T.
function EmptyParensAfter(AMap: TRdxCodeMap; const T: TRdxToken): TRdxToken;
var
  O, C : TRdxToken;
begin
  Result := T;
  O := After(AMap, T);
  C := After(AMap, O);
  if (O.Low = '(') and (C.Low = ')') then
    Result := C;
end;

// Das letzte Glied eines qualifizierten Namens ab T ('SysUtils.FreeAndNil'
// -> 'FreeAndNil', 'Windows.EnterCriticalSection'); T selbst, wenn kein
// '.' folgt.
function QualifiedEnd(AMap: TRdxCodeMap; const T: TRdxToken): TRdxToken;
var
  D, N : TRdxToken;
begin
  Result := T;
  if not T.IsWord then Exit;
  D := After(AMap, Result);
  N := After(AMap, D);
  while (D.Low = '.') and N.IsWord do
  begin
    Result := N;
    D := After(AMap, Result);
    N := After(AMap, D);
  end;
end;

// Rueckwaerts ab AFrom (einschliesslich) die erste '(' bzw. '[', die bis
// AFrom nicht geschlossen ist; Low = '' ohne (';' oder Dateianfang davor).
function UnmatchedOpener(AMap: TRdxCodeMap; const AFrom: TRdxToken): TRdxToken;
var
  T     : TRdxToken;
  Depth : Integer;
begin
  Result := Default(TRdxToken);
  Depth := 0;
  T := AFrom;
  while (T.Low <> '') and (T.Low <> ';') do
  begin
    if (T.Low = ')') or (T.Low = ']') then
      Inc(Depth)
    else if (T.Low = '(') or (T.Low = '[') then
    begin
      if Depth = 0 then
        Exit(T);
      Dec(Depth);
    end;
    T := Before(AMap, T);
  end;
end;

// Ein Token von StatementStop: Klammer- und Blocktiefe fortschreiben; True,
// wo die Anweisung endet.
function StopStep(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  var AParen, ADepth: Integer): Boolean;
var
  IsKw : Boolean;
begin
  Result := False;
  IsKw := IsKeywordAt(AMap, T, APrev);
  if (T.Low = '(') or (T.Low = '[') then
    Inc(AParen)
  else if (T.Low = ')') or (T.Low = ']') then
    Dec(AParen)
  else if IsKw and IsEndOpener(T.Low) then
    Inc(ADepth)
  else if (AParen > 0) or (ADepth > 0) then
  begin
    if IsKw and (T.Low = 'end') then
      Dec(ADepth);
  end
  else
    Result := (T.Low = ';')
      or (IsKw and (InList(T.Low, LIST_ENDS) or (T.Low = 'else')));
end;

// Das Ende der Anweisung ab AFrom: das ';' ausserhalb von Klammern und
// Bloecken (eine anonyme Methode im Argument traegt eigene) oder, steht
// keines davor, das Listenende (end, until, except, finally, else); Low =
// '' am Dateiende.
function StatementStop(AMap: TRdxCodeMap; const AFrom: TRdxToken): TRdxToken;
var
  T, P         : TRdxToken;
  Paren, Depth : Integer;
begin
  Paren := 0;
  Depth := 0;
  P := Before(AMap, AFrom);
  T := AFrom;
  while T.Low <> '' do
  begin
    if StopStep(AMap, T, P, Paren, Depth) then
      Exit(T);
    P := T;
    T := After(AMap, T);
  end;
  Result := Default(TRdxToken);
end;

{ ---- Schluessel und Freigaben ---- }

// Ab T ein Aufruf 'A.B[i].M' bzw. 'M' mit der Methode M als letztem Glied
// - bloss oder mit leeren Klammern; AOwner = letztes Token davor (Low = ''
// ohne), AMeth = M, ALast = M bzw. ')'. False ohne diese Form.
function CallPathAt(AMap: TRdxCodeMap; const T: TRdxToken;
  out AOwner, AMeth, ALast: TRdxToken): Boolean;
var
  Cur, N, C : TRdxToken;
  Bare      : Boolean;   // das Glied ist bisher nur sein Wort
  Empty     : Boolean;   // ... bzw. sein Wort mit '()'
begin
  AOwner := Default(TRdxToken);
  AMeth := T;
  ALast := T;
  if not T.IsWord then Exit(False);
  Cur := T;
  Bare := True;
  Empty := False;
  // Ein Empfaenger-Glied darf Anhaenge tragen ('A[i].M', 'F(x).M',
  // 'P^.M'), das letzte (die Methode) nur leere Klammern.
  while True do
  begin
    N := After(AMap, Cur);
    if (N.Low = '(') or (N.Low = '[') then
    begin
      C := MatchClose(AMap, N);
      if C.Low = '' then Exit(False);
      Empty := Bare and (N.Low = '(') and SameTok(After(AMap, N), C);
      Bare := False;
      Cur := C;
    end
    else if N.Low = '^' then
    begin
      Bare := False;
      Empty := False;
      Cur := N;
    end
    else if (N.Low = '.') and After(AMap, N).IsWord then
    begin
      AOwner := Cur;
      AMeth := After(AMap, N);
      Cur := AMeth;
      Bare := True;
      Empty := False;
    end
    else
      Break;
  end;
  ALast := Cur;
  Result := Bare or Empty;
end;

function LockPairIndex(const ALow: string; ASide: TRdxLockSide): Integer;
var
  i : Integer;
begin
  for i := 0 to High(LOCK_PAIRS) do
    if LOCK_PAIRS[i, ASide] = ALow then
      Exit(i);
  Result := -1;
end;

// Das eine Argument der Klammer AOpen als Schluessel (S.Key, S.Name,
// S.Last); False ohne Argument, mit mehreren oder einem Kommentar darin.
function ArgSite(AMap: TRdxCodeMap; const AOpen: TRdxToken;
  var S: TRdxLockSite): Boolean;
var
  C, T, A : TRdxToken;
  Depth   : Integer;
begin
  Result := False;
  C := MatchClose(AMap, AOpen);
  A := After(AMap, AOpen);
  if (C.Low = '') or SameTok(A, C) then Exit;
  Depth := 0;
  T := A;
  while not SameTok(T, C) do
  begin
    if (T.Low = '(') or (T.Low = '[') then Inc(Depth)
    else if (T.Low = ')') or (T.Low = ']') then Dec(Depth)
    else if (T.Low = ',') and (Depth = 0) then Exit;
    T := After(AMap, T);
  end;
  S.Key := KeyText(AMap, A, Before(AMap, C));
  S.Name := SourceText(AMap, A, Before(AMap, C));
  S.Last := C;
  Result := S.Key <> '';
end;

// 'TMonitor.Enter(O)' bzw. 'TMonitor.Exit(O)' ab T.
function MonitorAt(AMap: TRdxCodeMap; const T: TRdxToken;
  ASide: TRdxLockSide; var S: TRdxLockSite): Boolean;
var
  D, M, O : TRdxToken;
begin
  Result := False;
  if T.Low <> 'tmonitor' then Exit;
  D := After(AMap, T);
  M := After(AMap, D);
  O := After(AMap, M);
  if (D.Low <> '.') or (M.Low <> MONITOR_CALLS[ASide]) or (O.Low <> '(') then
    Exit;
  S.Form := lfMonitor;
  S.First := T;
  S.CallTok := M;
  Result := ArgSite(AMap, O, S);
end;

// 'EnterCriticalSection(CS)' bzw. 'LeaveCriticalSection(CS)' ab T, auch
// qualifiziert ('Windows.EnterCriticalSection(CS)').
function CallAt(AMap: TRdxCodeMap; const T: TRdxToken; ASide: TRdxLockSide;
  var S: TRdxLockSite): Boolean;
var
  F, O : TRdxToken;
begin
  F := QualifiedEnd(AMap, T);
  O := After(AMap, F);
  Result := False;
  if (F.Low <> LOCK_CALLS[ASide]) or (O.Low <> '(') then Exit;
  S.Form := lfCall;
  S.First := T;
  S.CallTok := F;
  Result := ArgSite(AMap, O, S);
end;

// 'FLock.Enter', 'Self.FLock.Leave', 'Lock' (eigene Methode) ab T.
function MethodAt(AMap: TRdxCodeMap; const T: TRdxToken;
  ASide: TRdxLockSide; var S: TRdxLockSite): Boolean;
var
  Owner, Meth, Last : TRdxToken;
begin
  Result := CallPathAt(AMap, T, Owner, Meth, Last);
  if not Result then Exit;
  S.Meth := LockPairIndex(Meth.Low, ASide);
  if S.Meth < 0 then Exit(False);
  S.Form := lfMethod;
  S.First := T;
  S.CallTok := Meth;
  S.Owner := Owner;
  S.Last := Last;
  S.Key := '';
  S.Name := TokText(AMap, Meth);
  if Owner.Low = '' then Exit;
  S.Key := KeyText(AMap, T, Owner);
  S.Name := SourceText(AMap, T, Owner);
  Result := S.Key <> '';
end;

// Eine Sperre (ASide = sdAcquire) bzw. Freigabe ab T - T beginnt den
// Ausdruck (davor kein '.').
function LockSiteAt(AMap: TRdxCodeMap; const T: TRdxToken;
  ASide: TRdxLockSide; out S: TRdxLockSite): Boolean;
begin
  S := Default(TRdxLockSite);
  Result := T.IsWord and (MonitorAt(AMap, T, ASide, S)
    or CallAt(AMap, T, ASide, S) or MethodAt(AMap, T, ASide, S));
end;

// Dieselbe Sperre wie A (Form, Schluessel, Methode)? So genau muss B zu A
// passen.
function SameLock(const A, B: TRdxLockSite): Boolean;
begin
  Result := (A.Form = B.Form) and (A.Key = B.Key)
    and ((A.Form <> lfMethod) or (A.Meth = B.Meth));
end;

// 'tfoo(x)' -> 'x': der ganze Schluessel ist ein Name ohne Punkt mit EINER
// Klammer darum und etwas darin; sonst unveraendert. Auch ein Aufruf
// 'getlock(i)' wird so zu 'i' - ein Treffer zu viel sperrt nur.
function Uncast(const AKey: string): string;
var
  i, Open, Depth : Integer;
begin
  Result := AKey;
  Open := Pos('(', AKey);
  if (Open < 2) or (Open >= Length(AKey) - 1) or (AKey[Length(AKey)] <> ')')
     or not IsIdentStart(AKey[1]) then
    Exit;
  for i := 2 to Open - 1 do
    if not IsIdentChar(AKey[i]) then
      Exit;
  Depth := 0;
  for i := Open to Length(AKey) - 1 do
  begin
    if AKey[i] = '(' then
      Inc(Depth)
    else if AKey[i] = ')' then
      Dec(Depth);
    if Depth = 0 then
      Exit;   // die Klammer schliesst vor dem Ende - kein Cast
  end;
  Result := Copy(AKey, Open + 1, Length(AKey) - Open - 1);
end;

// Ein Schluessel ohne 'self.' davor und ohne Typumwandlung drumherum
// ('tfoo(self.flock)' -> 'flock', 'self' -> '' wie die eigene Methode) -
// so vergleichen die Gates eine Freigabe in anderer Schreibweise
// (Gegen-Review H4, Minor 1).
function NormKey(const AKey: string): string;
var
  OldLen : Integer;
begin
  Result := AKey;
  repeat
    OldLen := Length(Result);
    if Copy(Result, 1, Length(SELF_DOT)) = SELF_DOT then
      Delete(Result, 1, Length(SELF_DOT));
    Result := Uncast(Result);
  until Length(Result) = OldLen;
  if Result = SELF_WORD then
    Result := '';
end;

// Dieselbe Sperre in irgendeiner Schreibweise: Schluessel normalisiert
// (NormKey), Enter/Acquire bzw. Leave/Release als eine Familie
// (LOCK_FAMILY) - fuer die Gates, nicht fuer B.
function SameLockLoose(const A, B: TRdxLockSite): Boolean;
begin
  Result := (A.Form = B.Form) and (NormKey(A.Key) = NormKey(B.Key))
    and ((A.Form <> lfMethod) or (LOCK_FAMILY[A.Meth] = LOCK_FAMILY[B.Meth]));
end;

// Ab T ein Verweis auf die Variable AKey: 'X' oder 'Self.X'; ALast = das
// Token mit dem Namen.
function PlainRefAt(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  const AKey: string; out ALast: TRdxToken): Boolean;
var
  D : TRdxToken;
begin
  ALast := T;
  if MentionsKey(T, APrev, AKey) then Exit(True);
  D := After(AMap, T);
  Result := (T.Low = SELF_WORD) and (APrev.Low <> '.') and (D.Low = '.');
  if not Result then Exit;
  ALast := After(AMap, D);
  Result := ALast.IsWord and SameIdent(ALast.Low, AKey);
end;

// Wie PlainRefAt, auch in einer Typumwandlung 'TFoo(X)' bzw.
// 'TFoo(Self.X)'; ALast = das Token mit dem Namen bzw. die ')'.
function RefAt(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  const AKey: string; out ALast: TRdxToken): Boolean;
var
  O, V, C : TRdxToken;
begin
  ALast := T;
  if APrev.Low = '.' then Exit(False);
  Result := PlainRefAt(AMap, T, APrev, AKey, ALast);
  if Result or not T.IsWord then Exit;
  O := After(AMap, T);
  V := After(AMap, O);
  if (O.Low <> '(') or not PlainRefAt(AMap, V, O, AKey, C) then Exit;
  ALast := After(AMap, C);
  Result := ALast.Low = ')';
end;

// Ab T die Freigabe B von X? AHit.KeyTok: das Token mit dem Namen,
// AHit.Last: das letzte Token des Aufrufs.
function ObjectReleaseAt(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  const AKey: string; out AHit: TRdxReleaseHit): Boolean;
var
  D, M, F, O, V, C : TRdxToken;
begin
  Result := False;
  AHit := Default(TRdxReleaseHit);
  AHit.KeyTok := T;
  if MentionsKey(T, APrev, AKey) then
  begin
    D := After(AMap, T);
    M := After(AMap, D);
    if (D.Low <> '.') or not InList(M.Low, FREE_METHODS) then Exit;
    AHit.Last := EmptyParensAfter(AMap, M);
    Exit(True);
  end;
  // Auch qualifiziert ('SysUtils.FreeAndNil(X)') - ab dem ersten Glied, so
  // ist B eine ganze Anweisung (Gegen-Review H4, Minor 4).
  F := QualifiedEnd(AMap, T);
  if F.Low <> FREE_AND_NIL then Exit;
  O := After(AMap, F);
  V := After(AMap, O);
  C := After(AMap, V);
  Result := (O.Low = '(') and MentionsKey(V, O, AKey) and (C.Low = ')');
  AHit.KeyTok := V;
  AHit.Last := C;
end;

// Ab T die Freigabe B von P ('FreeMem(P)', 'FreeMem(P, N)', auch
// qualifiziert 'System.FreeMem(P)').
function BufferReleaseAt(AMap: TRdxCodeMap; const T: TRdxToken;
  const AKey: string; out AHit: TRdxReleaseHit): Boolean;
var
  F, O, N : TRdxToken;
begin
  Result := False;
  AHit := Default(TRdxReleaseHit);
  F := QualifiedEnd(AMap, T);
  if not InList(F.Low, FREEMEM_WORDS) then
    Exit;
  O := After(AMap, F);
  AHit.KeyTok := After(AMap, O);
  N := After(AMap, AHit.KeyTok);
  if (O.Low <> '(') or not MentionsKey(AHit.KeyTok, O, AKey)
     or ((N.Low <> ',') and (N.Low <> ')')) then
    Exit;
  AHit.Last := MatchClose(AMap, O);
  Result := AHit.Last.Low <> '';
end;

function ReleaseAt(AMap: TRdxCodeMap; const APair: TRdxPair;
  const T, APrev: TRdxToken; out AHit: TRdxReleaseHit): Boolean;
var
  S : TRdxLockSite;
begin
  AHit := Default(TRdxReleaseHit);
  S := Default(TRdxLockSite);
  case APair.Kind of
    pkObject:
      Result := ObjectReleaseAt(AMap, T, APrev, APair.Key, AHit);
    pkBuffer:
      Result := BufferReleaseAt(AMap, T, APair.Key, AHit);
  else
    Result := (APrev.Low <> '.') and LockSiteAt(AMap, T, sdRelease, S)
      and SameLock(S, APair.Lock);
    AHit.Last := S.Last;
  end;
end;

// Ab T eine Freigabe von X bzw. P in irgendeiner Schreibweise:
// 'TObject(X).Free', 'Self.X.Destroy', 'FreeAndNil(Self.X)',
// 'FreeMem(PByte(P))' - fuer die Gates; B selbst liest ReleaseAt.
function AnyVarReleaseAt(AMap: TRdxCodeMap; const APair: TRdxPair;
  const T, APrev: TRdxToken): Boolean;
var
  F, O, Last : TRdxToken;
begin
  Result := False;
  if (APair.Kind = pkObject) and RefAt(AMap, T, APrev, APair.Key, Last) then
  begin
    O := After(AMap, Last);
    Result := (O.Low = '.') and InList(After(AMap, O).Low, FREE_METHODS);
  end;
  if Result or (APrev.Low = '.') then Exit;
  F := QualifiedEnd(AMap, T);
  if ((APair.Kind = pkObject) and (F.Low <> FREE_AND_NIL))
     or ((APair.Kind = pkBuffer) and not InList(F.Low, FREEMEM_WORDS)) then
    Exit;
  O := After(AMap, F);
  Result := (O.Low = '(') and RefAt(AMap, After(AMap, O), O, APair.Key, Last)
    and InList(After(AMap, Last).Low, ARG_ENDS);
end;

// Dasselbe fuer die Sperre: derselbe Schluessel und dieselbe Familie
// (SameLockLoose).
function AnyReleaseAt(AMap: TRdxCodeMap; const APair: TRdxPair;
  const T, APrev: TRdxToken): Boolean;
var
  S : TRdxLockSite;
begin
  if APair.Kind <> pkLock then
    Exit(AnyVarReleaseAt(AMap, APair, T, APrev));
  Result := (APrev.Low <> '.') and LockSiteAt(AMap, T, sdRelease, S)
    and SameLockLoose(S, APair.Lock);
end;

{ ---- TRdxSpan ---- }

procedure TRdxSpan.PushBlock(AKind: Char);
begin
  Inc(Depth);
  Kinds := Kinds + AKind;
end;

procedure TRdxSpan.PopBlock;
begin
  Dec(Depth);
  SetLength(Kinds, Length(Kinds) - 1);
end;

// Schleifenrumpfe ohne begin, die auf dieser Tiefe begannen, enden hier
// (';', else, end, until, except, finally).
procedure TRdxSpan.EndSingles;
var
  n : Integer;
begin
  n := Length(Singles);
  while (n > 0) and (Singles[n - 1] >= Depth) do
    Dec(n);
  SetLength(Singles, n);
end;

// Das Token hinter dem do einer Schleife: begin macht den Block zum
// Schleifenrumpf, sonst ist es ein Rumpf aus einer Anweisung.
procedure TRdxSpan.TakeLoopDo(const T: TRdxToken);
begin
  if not LoopDo then Exit;
  LoopDo := False;
  if T.Low = 'begin' then
    NextBegin := BLOCK_LOOP
  else
  begin
    SetLength(Singles, Length(Singles) + 1);
    Singles[High(Singles)] := Depth;
  end;
end;

function TRdxSpan.InLoop: Boolean;
begin
  Result := (Length(Singles) > 0) or (Pos(BLOCK_LOOP, Kinds) > 0);
end;

function TRdxSpan.InnerKind: Char;
begin
  Result := BLOCK_OTHER;
  if Kinds <> '' then
    Result := Kinds[Length(Kinds)];
end;

{ ---- Die Routine um A: lokale Variablen (Weitergabe-Sperre) ---- }

// Die innerste Routine, deren Rumpf AAt enthaelt - rueckwaerts bis zu
// ihrem Kopf, Grenzen per ReadRoutine (lokale Routinen davor enthalten AAt
// nicht und werden uebergangen). False ohne.
function RoutineAround(AMap: TRdxCodeMap; const AAt: TRdxToken;
  out ARoutine: TRdxRoutine): Boolean;
var
  T, P : TRdxToken;
begin
  ARoutine := Default(TRdxRoutine);
  T := Before(AMap, AAt);
  while T.Low <> '' do
  begin
    P := Before(AMap, T);
    if IsRoutineHeadAfter(T, P)
       and (TRdxRoutineFixes.ReadRoutine(AMap, T, ARoutine) = '')
       and (ARoutine.Body.Low <> '') and TokBefore(ARoutine.Body, AAt)
       and TokBefore(AAt, ARoutine.EndTok) then
      Exit(True);
    if IsKeywordAt(AMap, T, P) and InList(T.Low, UNIT_BOUNDS) then
      Break;
    T := P;
  end;
  Result := False;
end;

// Wird an T (P davor) der Name AName deklariert ('var A, B: T;' - davor
// var, ';' bzw. ',', dahinter ':' bzw. ',')?
function DeclaresName(AMap: TRdxCodeMap; const T, P: TRdxToken;
  const AName: string): Boolean;
begin
  Result := SameIdent(T.Low, AName) and InList(P.Low, DECL_PREV)
    and InList(After(AMap, T).Low, DECL_NEXT);
end;

// Eine lokale Routine ab ihrem Kopf T ueberspringen: T wird ihr letztes
// ';'. False, wenn ihre Grenzen nicht sicher sind.
function SkipLocalRoutine(AMap: TRdxCodeMap; var T: TRdxToken): Boolean;
var
  Local : TRdxRoutine;
begin
  Result := TRdxRoutineFixes.ReadRoutine(AMap, T, Local) = '';
  if Result then
    T := Local.Last;
end;

// AName im var-Abschnitt des Deklarationsteils von ARoutine (zwischen Kopf
// und Rumpf; lokale Routinen - ihre Variablen gehoeren nicht hierher -
// uebersprungen)?
function VarInSections(AMap: TRdxCodeMap; const ARoutine: TRdxRoutine;
  const AName: string): Boolean;
var
  T, P  : TRdxToken;
  InVar : Boolean;
begin
  Result := False;
  InVar := False;
  P := ARoutine.HeaderEnd;
  T := After(AMap, P);
  while (T.Low <> '') and TokBefore(T, ARoutine.Body) do
  begin
    if IsRoutineHeadAfter(T, P) then
    begin
      if not SkipLocalRoutine(AMap, T) then
        Exit;
      InVar := False;
    end
    else if IsKeywordAt(AMap, T, P) and InList(T.Low, SECTION_WORDS) then
      InVar := InList(T.Low, VAR_SECTIONS)
    else if InVar and DeclaresName(AMap, T, P, AName) then
      Exit(True);
    P := T;
    T := After(AMap, T);
  end;
end;

// AName als Inline-var ('var A, B: T' bzw. 'var A := ..') im Rumpf ab
// ABody vor AAt?
function InlineVarBefore(AMap: TRdxCodeMap; const ABody, AAt: TRdxToken;
  const AName: string): Boolean;
var
  T, P, N : TRdxToken;
begin
  Result := False;
  P := ABody;
  T := After(AMap, ABody);
  while (T.Low <> '') and TokBefore(T, AAt) do
  begin
    if (T.Low = 'var') and IsKeywordAt(AMap, T, P) then
    begin
      N := After(AMap, T);
      while N.IsWord do
      begin
        if SameIdent(N.Low, AName) then
          Exit(True);
        if After(AMap, N).Low <> ',' then
          Break;
        N := After(AMap, After(AMap, N));
      end;
    end;
    P := T;
    T := After(AMap, T);
  end;
end;

// Ist AName eine lokale Variable der Routine um AAt (var-Abschnitt oder
// Inline-var davor)? Parameter zaehlen nicht (NonLocalTarget).
function IsLocalVar(AMap: TRdxCodeMap; const AAt: TRdxToken;
  const AName: string): Boolean;
var
  R : TRdxRoutine;
begin
  Result := RoutineAround(AMap, AAt, R) and (VarInSections(AMap, R, AName)
    or InlineVarBefore(AMap, R.Body, AAt, AName));
end;

// Das Inline-'var', mit dem die Anweisung mit dem ':=' AAssign beginnt
// ('var Y := X', 'var Y: TFoo := X'); Low = '' ohne. Die Deklaration ist
// lokal.
function InlineVarOf(AMap: TRdxCodeMap; const AAssign: TRdxToken): TRdxToken;
var
  T, P : TRdxToken;
  n    : Integer;
begin
  Result := Default(TRdxToken);
  T := Before(AMap, AAssign);
  for n := 1 to MAX_TARGET_TOKENS do
  begin
    if (T.Low = '') or InList(T.Low, LIST_PREV) or InList(T.Low, BRANCH_WORDS) then
      Exit;
    P := Before(AMap, T);
    if (T.Low = 'var') and IsKeywordAt(AMap, T, P) then
      Exit(T);
    T := P;
  end;
end;

// Das erste Token des Ziels vor AAssign (':='): rueckwaerts ueber Namen,
// '.', '^' und Klammern ('Items.Objects[I]', 'P^.Next', 'F(x).Y'); APlain
// = ein Name allein. Low = '' ohne lesbares Ziel.
function TargetStart(AMap: TRdxCodeMap; const AAssign: TRdxToken;
  out APlain: Boolean): TRdxToken;
var
  T, P : TRdxToken;
  n    : Integer;
begin
  Result := Default(TRdxToken);
  APlain := True;
  T := Before(AMap, AAssign);
  for n := 1 to MAX_TARGET_TOKENS do
  begin
    if (T.Low = ')') or (T.Low = ']') then
      T := Before(AMap, UnmatchedOpener(AMap, Before(AMap, T)))
    else if T.Low = '^' then
      T := Before(AMap, T)
    else if T.IsWord then
    begin
      P := Before(AMap, T);
      if P.Low <> '.' then
        Exit(T);
      T := Before(AMap, P);
    end
    else
      Exit;
    APlain := False;
  end;
end;

// Das Ziel der Zuweisung mit dem ':=' AAssign, wenn es keine lokale
// Variable der Routine um AAt ist - Feld, Property, Element, Result,
// globale Variable, Parameter (lieber eine Sperre zu viel: ein var-/out-
// Parameter gaebe X an den Aufrufer); '' fuer eine lokale.
function NonLocalTarget(AMap: TRdxCodeMap; const AAssign, AAt: TRdxToken): string;
var
  First : TRdxToken;
  Plain : Boolean;
begin
  Result := '';
  if InlineVarOf(AMap, AAssign).Low <> '' then Exit;
  First := TargetStart(AMap, AAssign, Plain);
  if Plain and (First.Low <> 'result') and IsLocalVar(AMap, AAt, First.Low) then
    Exit;
  if First.Low = '' then
    First := Before(AMap, AAssign);
  Result := SourceText(AMap, First, Before(AMap, AAssign));
end;

{ ---- Weitergabe ohne Ausstieg (Gegen-Review H4, Blocker 1) ---- }

// Haelt ein Aufruf namens ALow ein direktes Argument fest (STORE_PREFIXES
// ausser STORE_HARMLESS)?
function IsStoreCall(const ALow: string): Boolean;
var
  S : string;
begin
  Result := False;
  if InList(ALow, STORE_HARMLESS) then Exit;
  for S in STORE_PREFIXES do
    if Copy(ALow, 1, Length(S)) = S then
      Exit(True);
end;

// Der Name des Aufrufs, dessen direktes Argument AFirst..ALast ist (davor
// '(' bzw. ',', dahinter ',' bzw. ')'); Low = '' ohne - auch fuer ein
// Element bzw. eine Menge ('[').
function CallOfArg(AMap: TRdxCodeMap; const AFirst, ALast: TRdxToken): TRdxToken;
var
  P, O : TRdxToken;
begin
  Result := Default(TRdxToken);
  P := Before(AMap, AFirst);
  if not InList(P.Low, ARG_STARTS)
     or not InList(After(AMap, ALast).Low, ARG_ENDS) then
    Exit;
  O := UnmatchedOpener(AMap, P);
  if O.Low <> '(' then Exit;
  P := Before(AMap, O);
  if P.IsWord then
    Result := P;
end;

// Sieht AName wie ein Typ aus - eine Typumwandlung 'TObject(X)',
// 'PByte(P)', 'IFoo(X)', 'Pointer(X)'? Delphi-Konvention: T, P bzw. I und
// ein Grossbuchstabe. Ein Funktionsaufruf 'AttToHtml(X)' gibt dagegen nur
// sein Ergebnis weiter, nicht X (Korpus-Harness H4c: 'Strings.Add(
// AttToHtml(Datt))' sperrte sonst sechsmal).
function IsCastName(const AName: string): Boolean;
begin
  Result := InList(LowerCase(AName), CAST_WORDS)
    or ((Length(AName) > 1) and CharInSet(AName[1], ['T', 'P', 'I'])
      and CharInSet(AName[2], ['A'..'Z']));
end;

// Ist W (ein Wort vor '(') eine Typumwandlung (IsCastName) - und kein
// Aufruf, der sein Argument festhaelt oder wirft ('PUTDATA(X)' sieht wie
// ein Cast aus)?
function IsCastWord(AMap: TRdxCodeMap; const W: TRdxToken): Boolean;
begin
  Result := W.IsWord and IsCastName(TokText(AMap, W))
    and not IsStoreCall(W.Low) and not InList(W.Low, RAISE_CALLS);
end;

// Das Ende des Typs hinter 'as' AAs: 'TFoo', 'System.TObject' bzw. das '>'
// von 'TList<T>'; Low = '' ohne lesbaren Typ.
function AsTypeEnd(AMap: TRdxCodeMap; const AAs: TRdxToken): TRdxToken;
var
  N : TRdxToken;
begin
  Result := Default(TRdxToken);
  N := After(AMap, AAs);
  if not N.IsWord then Exit;
  Result := QualifiedEnd(AMap, N);
  N := After(AMap, Result);
  if N.Low = '<' then
    Result := MatchClose(AMap, N);
end;

// Das erste Token der Klammer AOpen samt Typumwandlung davor: 'TFoo(' bzw.
// 'System.TObject(' ab dem ersten Glied, '(' allein bei blossen Klammern;
// Low = '' hinter einem Namen, der kein Cast ist (ein Aufruf 'F(X)' - X ist
// dort sein Argument, CallOfArg).
function WrapStart(AMap: TRdxCodeMap; const AOpen: TRdxToken): TRdxToken;
var
  W, D : TRdxToken;
begin
  Result := AOpen;
  W := Before(AMap, AOpen);
  if not W.IsWord then Exit;
  if not IsCastWord(AMap, W) then
    Exit(Default(TRdxToken));
  repeat
    Result := W;
    D := Before(AMap, W);
    W := Before(AMap, D);
  until (D.Low <> '.') or not W.IsWord;
end;

// Eine Huelle mehr um AFirst..ALast (s. WrappedAt): ' as TFoo' dahinter bzw.
// eine Klammer drumherum - davor nichts oder eine Typumwandlung. True, wenn
// der Bereich gewachsen ist.
function WrapOnce(AMap: TRdxCodeMap; var AFirst, ALast: TRdxToken): Boolean;
var
  P, N, S : TRdxToken;
begin
  Result := False;
  N := After(AMap, ALast);
  if N.Low = 'as' then
  begin
    S := AsTypeEnd(AMap, N);
    if S.Low = '' then Exit;
    ALast := S;
    Exit(True);
  end;
  P := Before(AMap, AFirst);
  if (P.Low <> '(') or (N.Low <> ')') then Exit;
  S := WrapStart(AMap, P);
  if S.Low = '' then Exit;
  AFirst := S;
  ALast := N;
  Result := True;
end;

// X an T samt seinen Huellen - eine Typumwandlung 'TFoo(X)' (IsCastWord, X
// allein in der Klammer, auch qualifiziert 'System.TObject(X)'), Klammern
// '(X)' und 'X as TFoo' -, beliebig tief geschachtelt: AFirst..ALast ist der
// ganze Ausdruck, der X weiterreicht; ohne Huelle T selbst. Jede Huelle
// macht den Bereich groesser (WrapOnce), der Lauf endet also spaetestens an
// den Grenzen der Datei. Bis Charge B1 sah die Weitergabe-Sperre X nur
// direkt hinter ':=' bzw. als Argument und packte nur den Cast im Aufruf
// aus: 'FCurrent := TFoo(X);', 'FCurrent := X as TFoo;' und 'List.Add(X as
// TObject);' gingen durch (Gegen-Review R5, R5-04); bis zur Nachpruefung
// las sie hoechstens vier Huellen, mit der fuenften ging es wieder durch.
procedure WrappedAt(AMap: TRdxCodeMap; const T: TRdxToken;
  out AFirst, ALast: TRdxToken);
var
  Grown : Boolean;
begin
  AFirst := T;
  ALast := T;
  Grown := True;
  while Grown do
    Grown := WrapOnce(AMap, AFirst, ALast);
end;

// X an T als direktes Argument eines Aufrufs, der es festhaelt bzw. wirft
// - auch in einer Huelle (AFirst..ALast, WrappedAt: 'List.Add(TObject(X))',
// 'List.Add(X as TObject)'). '' oder der Grund.
function CallArgReason(AMap: TRdxCodeMap;
  const T, AFirst, ALast: TRdxToken): string;
var
  Call : TRdxToken;
begin
  Result := '';
  Call := CallOfArg(AMap, AFirst, ALast);
  if Call.Low = '' then Exit;
  if InList(Call.Low, RAISE_CALLS) then
    Exit(Format('%s wird in Zeile %d an %s uebergeben - das Objekt ist die '
      + 'Ausnahme; finally gaebe es vor dem Handler frei',
      [TokText(AMap, T), T.Line, TokText(AMap, Call)]));
  if IsStoreCall(Call.Low) then
    Result := Format('%s wird in Zeile %d an %s weitergegeben - %s',
      [TokText(AMap, T), T.Line, TokText(AMap, Call), R_HELD]);
end;

// Heisst AName wie ein Ereignis - 'On..' (Gross/klein egal, ein 'Online'
// sperrt nur) bzw. das Feld 'FOn..'?
function IsEventName(const AName: string): Boolean;
begin
  Result := SameText(Copy(AName, 1, Length(EVENT_PREFIX)), EVENT_PREFIX)
    or (Copy(AName, 1, Length(EVENT_FIELD)) = EVENT_FIELD);
end;

// X an T als ganze rechte Seite einer Zuweisung - auch in einer Huelle
// (AFirst..ALast, WrappedAt: 'FCurrent := TFoo(X);') - an keinen lokalen
// Namen ('FCurrent := X;') oder als Methodenzeiger 'X.M' an ein Ereignis
// ('Btn.OnClick := X.Handler;'). '' oder der Grund.
function AssignReason(AMap: TRdxCodeMap;
  const T, AFirst, ALast: TRdxToken): string;
var
  A, N, M, Target : TRdxToken;
begin
  Result := '';
  A := Before(AMap, AFirst);
  if A.Low <> ':=' then Exit;
  N := After(AMap, ALast);
  M := After(AMap, N);
  if (N.Low = '.') and M.IsWord
     and EndsStatement(AMap, After(AMap, M), M) then
  begin
    Target := Before(AMap, A);
    if Target.IsWord and IsEventName(TokText(AMap, Target)) then
      Result := Format('Methodenzeiger %s.%s an %s in Zeile %d - %s',
        [TokText(AMap, T), TokText(AMap, M), TokText(AMap, Target), T.Line,
        R_HELD]);
    Exit;
  end;
  if not EndsStatement(AMap, N, ALast) then Exit;
  Result := NonLocalTarget(AMap, A, T);
  if Result <> '' then
    Result := Format('%s wird in Zeile %d an %s weitergegeben (kein lokaler '
      + 'Name der Routine) - %s', [TokText(AMap, T), T.Line, Result, R_HELD]);
end;

// Weitergabe ohne Ausstieg (s. Kopf): X an T wird festgehalten - '@X',
// Argument eines Speicher-Aufrufs, Zuweisung an keinen lokalen Namen,
// Methodenzeiger an ein Ereignis, auch in einer Huelle (WrappedAt). Im
// Fehlerfall gaebe finally X frei, waehrend der Halter es noch kennt. ''
// oder der Grund.
function HandOverReason(AMap: TRdxCodeMap; const T, APrev: TRdxToken): string;
var
  First, Last : TRdxToken;
begin
  if APrev.Low = '@' then
    Exit(Format('@%s in Zeile %d - ein Zeiger bzw. Methodenzeiger auf das '
      + 'Objekt verlaesst den Bereich; %s', [TokText(AMap, T), T.Line,
      R_HELD]));
  WrappedAt(AMap, T, First, Last);
  Result := CallArgReason(AMap, T, First, Last);
  if Result = '' then
    Result := AssignReason(AMap, T, First, Last);
end;

{ ---- Der Lauf von A nach B ---- }

// B an T: die Freigabe auf Tiefe 0 hinter ';' - als ganze Anweisung (davor
// ';', dahinter ';' oder das Listenende) und mit genau dem Namen aus A.
// True mit B in S; S.Reason, wenn sie keine ganze Anweisung ist.
function TakeRelease(AMap: TRdxCodeMap; const APair: TRdxPair;
  var S: TRdxSpan; const T, APrev: TRdxToken): Boolean;
var
  Hit     : TRdxReleaseHit;
  Last, E : TRdxToken;
begin
  Result := (S.Depth = 0) and (S.Paren = 0) and (APrev.Low = ';')
    and ReleaseAt(AMap, APair, T, APrev, Hit);
  if not Result then Exit;
  if (APair.Kind <> pkLock) and (Hit.KeyTok.Low <> APair.Key) then
    S.Reason := Format('die Freigabe in Zeile %d schreibt %s anders - %s',
      [T.Line, TokText(AMap, Hit.KeyTok), R_BY_HAND]);
  Last := Hit.Last;
  E := After(AMap, Last);
  if E.Low = ';' then
    Last := E
  else if not IsListEnd(AMap, E, Last) then
    S.Reason := Format('die Freigabe in Zeile %d ist keine ganze Anweisung',
      [T.Line]);
  S.B := T;
  S.BLast := Last;
end;

// Puffer: Inc(P)/Dec(P)/GetMem(P)/ReallocMem(P) an T, auch durch eine
// Typumwandlung ('Inc(PByte(P), 4)', Gegen-Review H4, Minor 1)? '' oder
// der Grund.
function BufferChangeReason(AMap: TRdxCodeMap; const APair: TRdxPair;
  const T, APrev: TRdxToken): string;
var
  O, V, Last : TRdxToken;
begin
  Result := '';
  if (APair.Kind <> pkBuffer) or not InList(T.Low, BUFFER_CHANGERS)
     or not IsKeywordAt(AMap, T, APrev) then
    Exit;
  O := After(AMap, T);
  V := After(AMap, O);
  if (O.Low = '(') and (MentionsKey(V, O, APair.Key)
     or (RefAt(AMap, V, O, APair.Key, Last)
       and InList(After(AMap, Last).Low, ARG_ENDS))) then
    Result := Format('%s(%s) in Zeile %d veraendert den Zeiger - FreeMem gaebe '
      + 'im finally einen anderen frei', [TokText(AMap, T), APair.Name,
      T.Line]);
end;

// 'raise ..' an T: nennt der Ausdruck X ausser als Member-Zugriff ('raise
// X', 'raise TObject(X)', 'raise X at Addr', 'raise EFoo.Create(X)'), ist
// das Objekt (Teil) der Ausnahme - finally gaebe es vor dem Handler frei
// (Gegen-Review H4, Minor 1: bis Charge H4c nur das Token hinter raise).
// '' oder der Grund.
function RaiseReason(AMap: TRdxCodeMap; const APair: TRdxPair;
  const T, APrev: TRdxToken): string;
var
  U, P, Stop : TRdxToken;
begin
  Result := '';
  if (T.Low <> 'raise') or not IsKeywordAt(AMap, T, APrev) then Exit;
  Stop := StatementStop(AMap, After(AMap, T));
  P := T;
  U := After(AMap, T);
  while (U.Low <> '') and TokBefore(U, Stop) do
  begin
    if MentionsKey(U, P, APair.Key)
       and not InList(After(AMap, U).Low, MEMBER_SUFFIXES) then
      Exit(Format('raise %s in Zeile %d - %s ist (Teil) der Ausnahme; finally '
        + 'gaebe es vor dem Handler frei', [SourceText(AMap, After(AMap, T),
        Before(AMap, Stop)), T.Line, TokText(AMap, U)]));
    P := U;
    U := After(AMap, U);
  end;
end;

// Ein Vorkommen der Variablen (Objekt, Puffer) an T: zweite Zuweisung,
// '@P' bei einem Puffer, Weitergabe ohne Ausstieg (HandOverReason)
// sperren; jede andere Nennung ausser einem Member-Zugriff merkt sich S fuer
// die Exit-Sperre. '' oder der Grund.
function VarUseReason(AMap: TRdxCodeMap; const APair: TRdxPair;
  var S: TRdxSpan; const T, APrev: TRdxToken): string;
var
  N : TRdxToken;
begin
  Result := BufferChangeReason(AMap, APair, T, APrev);
  if (Result <> '') or not MentionsKey(T, APrev, APair.Key) then Exit;
  N := After(AMap, T);
  if N.Low = ':=' then
    Exit(Format('zweite Zuweisung an %s in Zeile %d - die Freigabe im '
      + 'finally traefe ein anderes Objekt', [TokText(AMap, T), T.Line]));
  if (APrev.Low = '@') and (APair.Kind = pkBuffer) then
    Exit(Format('@%s in Zeile %d - der Zeiger kann sich aendern',
      [TokText(AMap, T), T.Line]));
  Result := HandOverReason(AMap, T, APrev);
  if (Result = '') and not InList(N.Low, MEMBER_SUFFIXES)
     and (S.Escape.Low = '') then
    S.Escape := T;
end;

// Eine Freigabe bzw. (Sperre) zweite Sperre an T, die nicht B ist - auch
// in anderer Schreibweise -, bzw. ein Vorkommen der Variablen, das sperrt.
// '' oder der Grund.
function UseReason(AMap: TRdxCodeMap; const APair: TRdxPair;
  var S: TRdxSpan; const T, APrev: TRdxToken): string;
var
  Hit : TRdxReleaseHit;
  L   : TRdxLockSite;
begin
  if ReleaseAt(AMap, APair, T, APrev, Hit) then
    Exit(Format('%s in Zeile %d - eine bedingte, tiefer liegende oder zweite '
      + 'Freigabe im Bereich; mit finally liefe sie doppelt',
      [APair.What, T.Line]));
  if AnyReleaseAt(AMap, APair, T, APrev) then
    Exit(Format('die Freigabe in Zeile %d gibt %s in anderer Schreibweise '
      + 'frei (Self., Typumwandlung, Leave/Release) - mit finally liefe sie '
      + 'doppelt; %s', [T.Line, APair.Name, R_BY_HAND]));
  if APair.Kind <> pkLock then
  begin
    Result := RaiseReason(AMap, APair, T, APrev);
    if Result = '' then
      Result := VarUseReason(AMap, APair, S, T, APrev);
    Exit;
  end;
  Result := '';
  if (APrev.Low <> '.') and LockSiteAt(AMap, T, sdAcquire, L)
     and SameLockLoose(L, APair.Lock) then
    Result := Format('die Sperre wird in Zeile %d noch einmal genommen - %s',
      [T.Line, R_BY_HAND]);
end;

// Ein Schluesselwort, das Bloecke und Schleifen fortschreibt. '' oder der
// Grund, wenn die Liste von A hier endet.
function BlockReason(var S: TRdxSpan; const T: TRdxToken): string;
begin
  Result := '';
  if InList(T.Low, LIST_ENDS) and (S.Depth = 0) then
    Exit('-');
  if (T.Low = 'end') or (T.Low = 'until') then
  begin
    S.EndSingles;
    S.PopBlock;
  end
  else if (T.Low = 'except') or (T.Low = 'finally') then
    S.EndSingles
  else if T.Low = 'case' then
    S.PushBlock(BLOCK_CASE)
  else if T.Low = 'repeat' then
    S.PushBlock(BLOCK_LOOP)
  else if T.Low = 'begin' then
  begin
    S.PushBlock(S.NextBegin);
    S.NextBegin := BLOCK_OTHER;
  end
  else if IsEndOpener(T.Low) then
    S.PushBlock(BLOCK_OTHER);
end;

// Koepfe von for/while/with bis zu ihrem do; das do einer Schleife meldet
// das naechste Token als Rumpf an (TakeLoopDo).
procedure HeadStep(var S: TRdxSpan; const T: TRdxToken);
begin
  if InList(T.Low, LOOP_HEADS) then
    S.Heads := S.Heads + HEAD_LOOP
  else if T.Low = 'with' then
    S.Heads := S.Heads + HEAD_WITH
  else if (T.Low = 'do') and (S.Heads <> '') then
  begin
    S.LoopDo := S.Heads[Length(S.Heads)] = HEAD_LOOP;
    SetLength(S.Heads, Length(S.Heads) - 1);
  end
  else if T.Low = 'else' then
    S.EndSingles;
end;

// Steht das Wort T (APrev davor) hinter 'System.' - 'System.Exit',
// 'System.Break', die Spruenge der RTL (Vcl.ActnMan schreibt
// 'System.Break')? Hinter '.' ist ein Wort kein Schluesselwort
// (IsKeywordAt), der Sprung blieb so ungesehen (Gegen-Review R5, R5-05:
// 'if C then System.Exit;' bei einer Sperre angeboten). 'TMonitor.Exit(O)'
// ist die Freigabe einer Sperre. Dieselbe Probe steht in uRdxResultFixes.
function SystemQualified(AMap: TRdxCodeMap; const T, APrev: TRdxToken): Boolean;
var
  Q : TRdxToken;
begin
  Result := False;
  if (APrev.Low <> '.') or not T.IsWord then Exit;
  Q := Before(AMap, APrev);
  Result := (Q.Low = SYSTEM_UNIT) and (Before(AMap, Q).Low <> '.');
end;

// Spruenge, asm und Inline-Deklarationen. '' oder der Grund.
function JumpReason(const APair: TRdxPair; var S: TRdxSpan;
  const T, APrev: TRdxToken): string;
begin
  Result := '';
  if (T.Low = 'exit') and (APair.Kind = pkLock) then
    Result := Format('Exit in Zeile %d - mit finally gaebe der Ausstieg die '
      + 'Sperre jetzt frei; %s', [T.Line, R_BY_HAND])
  else if T.Low = 'exit' then
  begin
    if S.ExitLine = 0 then
      S.ExitLine := T.Line;
  end
  else if InList(T.Low, JUMP_OUT) and not S.InLoop then
    Result := Format('%s in Zeile %d verlaesst den Bereich - die Freigabe '
      + 'liefe dort jetzt mit; %s', [T.Low, T.Line, R_BY_HAND])
  else if T.Low = 'goto' then
    Result := Format('goto in Zeile %d - ein Sprung in bzw. aus einem '
      + 'try-Block; %s', [T.Line, R_BY_HAND])
  else if T.Low = 'asm' then
    Result := Format('asm in Zeile %d im Bereich', [T.Line])
  else if InList(T.Low, INLINE_DECLS) and (S.Depth = 0)
     and InList(APrev.Low, LIST_PREV) then
    Result := Format('Inline-Deklaration (%s) in Zeile %d - ihr '
      + 'Gueltigkeitsbereich schrumpfte auf den try-Block', [T.Low, T.Line]);
end;

// Eine Marke 'L:' am Anfang einer Anweisung (nicht in einem case)? Ein
// goto von aussen in den try-Block uebersetzt nicht. '' oder der Grund.
function LabelReason(AMap: TRdxCodeMap; const S: TRdxSpan;
  const T, APrev: TRdxToken): string;
begin
  Result := '';
  if InList(APrev.Low, LIST_PREV) and (S.InnerKind <> BLOCK_CASE)
     and (T.IsWord or CharInSet(T.Low[1], ['0'..'9']))
     and (After(AMap, T).Low = ':') then
    Result := Format('Marke %s: in Zeile %d - ein goto in den try-Block '
      + 'uebersetzt nicht', [TokText(AMap, T), T.Line]);
end;

// Ein Wort des Laufs (SpanStep): als Schluesselwort Koepfe, Spruenge und
// Bloecke; ein qualifizierter Sprung 'System.Exit' wie das Schluesselwort
// (SystemQualified). '' oder der Grund.
function WordReason(AMap: TRdxCodeMap; const APair: TRdxPair;
  var S: TRdxSpan; const T, APrev: TRdxToken): string;
begin
  Result := '';
  if IsKeywordAt(AMap, T, APrev) then
  begin
    HeadStep(S, T);
    Result := JumpReason(APair, S, T, APrev);
    if Result = '' then
      Result := BlockReason(S, T);
  end
  else if InList(T.Low, SYSTEM_JUMPS) and SystemQualified(AMap, T, APrev) then
    Result := JumpReason(APair, S, T, APrev);
end;

// Ein Token des Laufs (ScanSpan): rsFound an B, rsStop mit S.Reason.
function SpanStep(AMap: TRdxCodeMap; const APair: TRdxPair; var S: TRdxSpan;
  const T, APrev: TRdxToken): TRdxStep;
begin
  Result := rsStop;
  if TakeRelease(AMap, APair, S, T, APrev) then
    Exit(rsFound);
  S.TakeLoopDo(T);
  S.Reason := UseReason(AMap, APair, S, T, APrev);
  if S.Reason = '' then
    S.Reason := LabelReason(AMap, S, T, APrev);
  if S.Reason <> '' then Exit;
  if (T.Low = '(') or (T.Low = '[') then
    Inc(S.Paren)
  else if (T.Low = ')') or (T.Low = ']') then
    Dec(S.Paren)
  else if (T.Low = ';') and (S.Paren = 0) then
    S.EndSingles
  else
  begin
    S.Reason := WordReason(AMap, APair, S, T, APrev);
    if S.Reason <> '' then Exit;
  end;
  Result := rsGoOn;
end;

// Von hinter A bis B: True mit B in S, sonst False mit S.Reason.
function ScanSpan(AMap: TRdxCodeMap; const APair: TRdxPair;
  var S: TRdxSpan): Boolean;
var
  T, Prev : TRdxToken;
  Step    : TRdxStep;
begin
  Result := False;
  Prev := APair.Semi;
  T := After(AMap, APair.Semi);
  while T.Low <> '' do
  begin
    Step := SpanStep(AMap, APair, S, T, Prev);
    if Step = rsFound then
      Exit(S.Reason = '');
    if Step = rsStop then Break;
    S.HasCode := True;
    Prev := T;
    T := After(AMap, T);
  end;
  // '-': die Liste von A endete (BlockReason) - wie das Dateiende.
  if (S.Reason = '') or (S.Reason = '-') then
    S.Reason := Format('keine Freigabe %s als ganze, unbedingte Anweisung in '
      + 'derselben Anweisungsliste hinter der Zeile %d - sie steht tiefer, in '
      + 'einem anderen Zweig oder fehlt; %s',
      [APair.What, APair.Semi.Line, R_BY_HAND]);
end;

// Hinter 'X.Free;' bzw. 'FreeMem(P);' ein 'X := nil;' als naechste
// Anweisung? Dann geht es mit ins finally (S.BLast) - aber nur, wenn es
// allein auf seiner Zeile steht bzw. die Zeile von B beschliesst und
// dahinter nichts mehr kommt; sonst bleibt es hinter dem end stehen
// (Gegen-Review H4, Minor 6: bis Charge H4c verwarf 'X := nil; Foo;' die
// ganze Hilfe). Puffer seit Charge B1 (Gegen-Review R5, R5-02): Freigabe und
// nil bleiben beisammen wie bei Objekten.
procedure TakeNil(AMap: TRdxCodeMap; const APair: TRdxPair; var S: TRdxSpan);
var
  V, A, N, E, Last : TRdxToken;
begin
  if (APair.Kind = pkLock) or (S.BLast.Low <> ';') then Exit;
  // Ein Objekt nur hinter 'X.Free' (wie bis Charge B1).
  if (APair.Kind = pkObject)
     and (After(AMap, After(AMap, S.B)).Low <> 'free') then
    Exit;
  V := After(AMap, S.BLast);
  A := After(AMap, V);
  N := After(AMap, A);
  E := After(AMap, N);
  if (V.Low <> APair.Key) or (A.Low <> ':=') or (N.Low <> 'nil') then Exit;
  if E.Low = ';' then
    Last := E
  else if IsListEnd(AMap, E, N) then
    Last := N
  else
    Exit;
  if ((V.Line = S.BLast.Line) or FirstOnLine(AMap, V))
     and CanAppendLine(AMap, Last.Line, Last.EndCol - 1) then
    S.BLast := Last;
end;

{ ---- Gegenproben am Bereich ---- }

// Ein Delphi-12-Mehrzeilenstring (''') in den Zeilen AFrom..ATo - Einruecken
// aenderte seinen Inhalt.
function MultiStringIn(AMap: TRdxCodeMap; AFrom, ATo: Integer): Boolean;
var
  Li, Co, q : Integer;
  L         : string;
begin
  Result := False;
  for Li := AFrom to ATo do
  begin
    L := AMap.Raw(Li);
    for Co := 1 to Length(L) do
      if (L[Co] = '''') and (AMap.ClassAt(Li, Co) = 's')
         and ((Co = 1) or (AMap.ClassAt(Li, Co - 1) <> 's')) then
      begin
        q := QuoteRun(L, Co);
        if (q >= MIN_MULTI_QUOTES) and Odd(q)
           and (SkipBlanks(L, Co + q) > Length(L)) then
          Exit(True);
      end;
  end;
end;

// Was am gefundenen Paar sperrt, bevor umschliessende try-Bloecke zaehlen.
// '' oder der Grund.
function SpanReason(AMap: TRdxCodeMap; const APair: TRdxPair;
  const S: TRdxSpan): string;
begin
  Result := '';
  if not S.HasCode then
    Result := Format('%s folgt direkt auf die Zeile %d - nichts zu schuetzen',
      [APair.What, APair.Semi.Line])
  else if not FirstOnLine(AMap, S.B) then
    Result := Format('vor der Freigabe in Zeile %d steht weiterer Code - '
      + 'try/finally/end stehen in eigenen Zeilen', [S.B.Line])
  else if not CanAppendLine(AMap, S.BLast.Line, S.BLast.EndCol - 1) then
    Result := Format('hinter der Freigabe in Zeile %d steht weiterer Code',
      [S.BLast.Line])
  else if DirectiveInLines(AMap, APair.First.Line, S.BLast.Line) then
    Result := 'Compiler-Direktive im Bereich - try oder finally stuende '
      + 'womoeglich in nur einem Zweig'
  else if MultiStringIn(AMap, APair.First.Line, S.BLast.Line) then
    Result := 'mehrzeiliges String-Literal im Bereich - Einruecken aenderte '
      + 'seinen Inhalt'
  else if (S.ExitLine > 0) and (S.Escape.Low <> '') then
    Result := Format('Exit in Zeile %d, und %s wird in Zeile %d weitergegeben '
      + '- der Ausstieg koennte den Besitz uebergeben haben; %s',
      [S.ExitLine, TokText(AMap, S.Escape), S.Escape.Line, R_BY_HAND]);
end;

{ TRdxTryScan }

// Ein Schluesselwort rueckwaerts (EnclosingTries): True, wo die Suche
// endet (Routinenkopf, Abschnittsgrenze); ein try, in dessen try-Teil A
// steht, kommt nach Tries.
function TRdxTryScan.Step(const T, APrev: TRdxToken): Boolean;
begin
  Result := False;
  if (T.Low = 'end') or (T.Low = 'until') then
    Inc(Depth)
  else if IsEndOpener(T.Low) or (T.Low = 'repeat') then
    Opener(T)
  else if Depth > 0 then
    Exit
  else if (T.Low = 'except') or (T.Low = 'finally') then
    Crossed := True
  else
    Result := IsRoutineHeadAfter(T, APrev) or InList(T.Low, UNIT_BOUNDS);
end;

// Ein Oeffner rueckwaerts: schliesst ein end dahinter oder umschliesst A -
// ein try, dessen except/finally die Suche nicht kreuzte, umschliesst A mit
// seinem try-Teil.
procedure TRdxTryScan.Opener(const T: TRdxToken);
begin
  if Depth > 0 then
  begin
    Dec(Depth);
    Exit;
  end;
  if (T.Low = 'try') and not Crossed then
  begin
    SetLength(Tries, Length(Tries) + 1);
    Tries[High(Tries)] := T;
  end;
  Crossed := False;
end;

// Die try-Bloecke, in deren try-Teil A steht - rueckwaerts bis zum Kopf der
// Routine bzw. zur Abschnittsgrenze (eine anonyme Methode zaehlt zur
// aeusseren Routine: lieber eine Sperre zu viel).
function EnclosingTries(AMap: TRdxCodeMap;
  const AFirst: TRdxToken): TArray<TRdxToken>;
var
  T, P : TRdxToken;
  Scan : TRdxTryScan;
begin
  Scan := Default(TRdxTryScan);
  T := Before(AMap, AFirst);
  while T.Low <> '' do
  begin
    P := Before(AMap, T);
    if IsKeywordAt(AMap, T, P) and Scan.Step(T, P) then
      Break;
    T := P;
  end;
  Result := Scan.Tries;
end;

// Der except- bzw. finally-Teil des try ATry: sein Schluesselwort (AStart)
// und das end des try (AEnd). False ohne.
function HandlerOf(AMap: TRdxCodeMap; const ATry: TRdxToken;
  out AStart, AEnd: TRdxToken): Boolean;
var
  T, Prev : TRdxToken;
  Depth   : Integer;
  IsKw    : Boolean;
begin
  AStart := Default(TRdxToken);
  AEnd := Default(TRdxToken);
  Depth := 1;
  Prev := ATry;
  T := After(AMap, ATry);
  while T.Low <> '' do
  begin
    IsKw := IsKeywordAt(AMap, T, Prev);
    if IsKw and IsEndOpener(T.Low) then
      Inc(Depth)
    else if IsKw and (T.Low = 'end') then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        AEnd := T;
        Exit(AStart.Low <> '');
      end;
    end
    else if (Depth = 1) and IsKw
       and ((T.Low = 'except') or (T.Low = 'finally')) then
      AStart := T;
    Prev := T;
    T := After(AMap, T);
  end;
  Result := False;
end;

// Kommt A im Handler AStart..AEnd vor - die Variable (Objekt, Puffer)
// bzw. die Freigabe der Sperre, auch in anderer Schreibweise? Das Token
// oder leer.
function MentionIn(AMap: TRdxCodeMap; const APair: TRdxPair;
  const AStart, AEnd: TRdxToken): TRdxToken;
var
  T, P : TRdxToken;
  Hit  : Boolean;
begin
  Result := Default(TRdxToken);
  P := AStart;
  T := After(AMap, AStart);
  while (T.Low <> '') and TokBefore(T, AEnd) do
  begin
    if APair.Kind = pkLock then
      Hit := AnyReleaseAt(AMap, APair, T, P)
    else
      Hit := MentionsKey(T, P, APair.Key);
    if Hit then
      Exit(T);
    P := T;
    T := After(AMap, T);
  end;
end;

// Die umschliessenden try-Bloecke: ihr Handler darf A nicht kennen (nach
// dem Fix liefe er hinter dem finally - zweite Freigabe, Zugriff auf ein
// freigegebenes Objekt). Ein try/except, dessen Handler A nicht nennt,
// ist richtig (s. Kopf, SCA009-Suffix). '' oder der Grund.
function EnclosingReason(AMap: TRdxCodeMap; const APair: TRdxPair): string;
var
  Tries      : TArray<TRdxToken>;
  i          : Integer;
  Start, Fin : TRdxToken;
  Hit        : TRdxToken;
begin
  Result := '';
  Tries := EnclosingTries(AMap, APair.First);
  for i := 0 to High(Tries) do
  begin
    if not HandlerOf(AMap, Tries[i], Start, Fin) then
      Exit(Format('das try in Zeile %d um den Bereich ist nicht sicher zu '
        + 'lesen - %s', [Tries[i].Line, R_BY_HAND]));
    Hit := MentionIn(AMap, APair, Start, Fin);
    if Hit.Low <> '' then
      Exit(Format('der %s-Teil des try in Zeile %d um den Bereich nennt %s '
        + '(Zeile %d) - nach dem Fix liefe er hinter dem finally', [Start.Low,
        Tries[i].Line, TokText(AMap, Hit), Hit.Line]));
  end;
end;

{ ---- Der Baustein B5 ---- }

// Wozu gehoert A? '' in einer Anweisungsliste, sonst der Grund.
function ContextReason(AMap: TRdxCodeMap; const AFirst: TRdxToken): string;
var
  P : TRdxToken;
begin
  Result := '';
  P := Before(AMap, AFirst);
  if InList(P.Low, LIST_PREV) then Exit;
  if InList(P.Low, BRANCH_WORDS) then
    Result := Format('die Anweisung steht allein hinter %s ohne begin - sie '
      + 'gehoert zu keiner Anweisungsliste', [P.Low])
  else if P.Low = ':' then
    Result := 'die Anweisung ist ein case-Zweig bzw. steht hinter einer Marke'
  else
    Result := Format('unklar, wozu die Anweisung gehoert ("%s" davor)',
      [P.Low]);
end;

// A als ganze Zeile: davor nur Leerraum, dahinter nur Kommentar. '' oder
// der Grund.
function StartReason(AMap: TRdxCodeMap; const APair: TRdxPair): string;
begin
  Result := ContextReason(AMap, APair.First);
  if Result <> '' then Exit;
  if not FirstOnLine(AMap, APair.First) then
    Result := 'vor der Anweisung steht auf ihrer Zeile weiterer Code - '
      + 'try/finally/end stehen in eigenen Zeilen'
  else if not CanAppendLine(AMap, APair.Semi.Line, APair.Semi.Col) then
    Result := 'hinter der Anweisung steht auf ihrer Zeile weiterer Code';
end;

// Das Token, das die Anweisungsliste um AFirst eroeffnet (begin, try,
// finally, except, repeat ...); Low = '' ohne.
function ListOpener(AMap: TRdxCodeMap; const AFirst: TRdxToken): TRdxToken;
var
  T, P  : TRdxToken;
  Depth : Integer;
begin
  Result := Default(TRdxToken);
  Depth := 0;
  T := Before(AMap, AFirst);
  while T.Low <> '' do
  begin
    P := Before(AMap, T);
    if IsKeywordAt(AMap, T, P) then
    begin
      if (T.Low = 'end') or (T.Low = 'until') then
        Inc(Depth)
      else if InList(T.Low, LIST_PREV) and (Depth = 0) then
        Exit(T)
      else if IsEndOpener(T.Low) or (T.Low = 'repeat') then
        Dec(Depth);
    end;
    T := P;
  end;
end;

// Ist AStep eine Stufe (bis MAX_STEP Leerzeichen bzw. Tabs)?
function PlainStep(const AStep: string): Boolean;
var
  i : Integer;
begin
  Result := (AStep <> '') and (Length(AStep) <= MAX_STEP);
  for i := 1 to Length(AStep) do
    Result := Result and (AStep[i] = AStep[1]);
end;

// Die Stufe der Liste: was A ueber die Zeile ihres Oeffners hinaus
// einrueckt - sonst die Vorgabe (IndentStep: zwei Leerzeichen bzw. Tab).
function ListStep(AMap: TRdxCodeMap; const AFirst: TRdxToken;
  const AIndent: string): string;
var
  O        : TRdxToken;
  L, OInd  : string;
begin
  O := ListOpener(AMap, AFirst);
  if O.Low <> '' then
  begin
    L := AMap.Raw(O.Line);
    OInd := Copy(L, 1, SkipBlanks(L, 1) - 1);
    Result := Copy(AIndent, Length(OInd) + 1, MaxInt);
    if (Copy(AIndent, 1, Length(OInd)) = OInd) and PlainStep(Result) then
      Exit;
  end;
  Result := IndentStep(AIndent, '');
end;

// Eine Zeile eine Stufe tiefer; eine leere bleibt leer. Die Stufe kommt
// HINTER den Teil des fuehrenden Leerraums, den die Zeile mit AInd (der
// Einrueckung von A) teilt: unter A mit '<Tab>  ' wird '<Tab>  X.Run'
// zu '<Tab>    X.Run', nicht zu '  <Tab>  X.Run' (Gegen-Review H4,
// Minor 3). Bei Leerraum aus einer Zeichenart ist das dasselbe wie davor.
function Deeper(const ALine, AInd, AStep: string): string;
var
  k : Integer;
begin
  Result := ALine;
  if Trim(ALine) = '' then Exit;
  k := 0;
  while (k < Length(AInd)) and (k < Length(ALine))
     and (ALine[k + 1] = AInd[k + 1]) do
    Inc(k);
  Result := Copy(ALine, 1, k) + AStep + Copy(ALine, k + 1, MaxInt);
end;

// Die zweite Haelfte eines UTF-16-Surrogatpaars?
function IsSecondHalf(C: Char): Boolean;
begin
  Result := (Ord(C) >= LOW_SURROGATE_FIRST) and (Ord(C) <= LOW_SURROGATE_LAST);
end;

// Die Ersetzung: vom letzten Zeichen der Zeile von A bis zum Ende der
// letzten Zeile von B - try, die Zeilen dazwischen eine Stufe tiefer,
// finally, B eine Stufe tiefer, end;. Der Bereich beginnt AUF einem Zeichen
// (SpanFits: nicht hinter dem Zeilenende), das unveraendert neu geschrieben
// wird - ist es die zweite Haelfte eines Surrogatpaars (Emoji im
// Kommentar), auf der ersten: sonst schnitte er mitten im Zeichen
// (Gegen-Review H4, Verdacht 13).
function TryEdit(AMap: TRdxCodeMap; const APair: TRdxPair;
  const S: TRdxSpan): TRdxEdit;
var
  ALine, Li, First : Integer;
  L, Ind           : string;
  Step, Text       : string;
  SB               : TStringBuilder;
begin
  Result := Default(TRdxEdit);
  ALine := APair.Semi.Line;
  L := AMap.Raw(APair.First.Line);
  Ind := Copy(L, 1, SkipBlanks(L, 1) - 1);
  Step := ListStep(AMap, APair.First, Ind);
  Text := AMap.Raw(ALine);
  First := Length(Text);
  if (First > 1) and IsSecondHalf(Text[First]) then
    Dec(First);
  SB := TStringBuilder.Create;
  try
    SB.Append(Copy(Text, First, MaxInt)).Append(#10);
    SB.Append(Ind).Append('try').Append(#10);
    for Li := ALine + 1 to S.B.Line - 1 do
      SB.Append(Deeper(AMap.Raw(Li), Ind, Step)).Append(#10);
    SB.Append(Ind).Append('finally');
    for Li := S.B.Line to S.BLast.Line do
      SB.Append(#10).Append(Deeper(AMap.Raw(Li), Ind, Step));
    SB.Append(#10).Append(Ind).Append('end;');
    Result.NewText := SB.ToString;
  finally
    SB.Free;
  end;
  Result.Span := TRefactorSpan.Make(SPAN_TRY, ALine, First, S.BLast.Line,
    Length(AMap.Raw(S.BLast.Line)) + 1);
  Result.Expected := RangeText(AMap, Result.Span);
end;

// Puffer: ist P eine lokale Variable der Routine (var-Abschnitt,
// Inline-var - auch die Allokation selbst, 'var P := AllocMem(N)')? Sonst
// kennt ein Feld, eine globale Variable oder der Aufrufer (Parameter) den
// Puffer weiter: bei einer Ausnahme gaebe finally ihn frei, das 'P := nil'
// dahinter liefe nicht, und aus einem Leck wuerde eine Doppelfreigabe
// (Gegen-Review R5, R5-02: globaler Puffer, den die finalization freigibt).
// Objekte meldet der Detektor nur als lokale Variable (SCA009/SCA001), dort
// genuegt die Weitergabe-Sperre. Als letzte Probe: die Gruende davor
// bleiben, wie sie waren. '' oder der Grund.
function HolderReason(AMap: TRdxCodeMap; const APair: TRdxPair): string;
begin
  Result := '';
  if (APair.Kind <> pkBuffer) or (APair.First.Low = 'var')
     or IsLocalVar(AMap, APair.First, APair.Key) then
    Exit;
  Result := Format('%s ist keine lokale Variable der Routine (Feld, globale '
    + 'Variable, Parameter) - %s', [APair.Name, R_HELD]);
end;

// Baustein B5 (s. Kopf): A (APair.First..APair.Semi) und seine Freigabe in
// derselben Liste in try/finally setzen. '' und AEdit oder der Grund.
function TryFinally(AMap: TRdxCodeMap; const APair: TRdxPair;
  out AEdit: TRdxEdit): string;
var
  S : TRdxSpan;
begin
  AEdit := Default(TRdxEdit);
  Result := StartReason(AMap, APair);
  if Result <> '' then Exit;
  S := Default(TRdxSpan);
  S.NextBegin := BLOCK_OTHER;
  if not ScanSpan(AMap, APair, S) then
    Exit(S.Reason);
  TakeNil(AMap, APair, S);
  Result := SpanReason(AMap, APair, S);
  if Result = '' then
    Result := EnclosingReason(AMap, APair);
  if Result = '' then
    Result := HolderReason(AMap, APair);
  if Result = '' then
    AEdit := TryEdit(AMap, APair, S);
end;

{ ---- A je Regel ---- }

// Hinter T (dem Namen einer Inline-Deklaration) das ':=' vor dem ';'.
function AssignAfter(AMap: TRdxCodeMap; const T: TRdxToken): TRdxToken;
var
  N : TRdxToken;
begin
  N := After(AMap, T);
  while (N.Low <> '') and (N.Low <> ':=') and (N.Low <> ';') do
    N := After(AMap, N);
  Result := N;
end;

// Die Zuweisung an X an T: 'X := ..' oder 'var X[: T] := ..'; ASite.First
// ist das erste Token der Anweisung, ASite.Assign das ':='.
function CreateAt(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  const AKey: string; out ASite: TRdxCreateSite): Boolean;
begin
  ASite := Default(TRdxCreateSite);
  ASite.First := T;
  if not MentionsKey(T, APrev, AKey) or (T.Low <> AKey) then
    Exit(False);
  if (APrev.Low = 'var') and IsKeywordAt(AMap, APrev, Before(AMap, APrev)) then
  begin
    ASite.First := APrev;
    ASite.Assign := AssignAfter(AMap, T);
  end
  else
    ASite.Assign := After(AMap, T);
  Result := ASite.Assign.Low = ':=';
end;

// Ein '.Create..' (Create, CreateFmt, CreateFromFile ...) zwischen AFrom
// und ATo - die Erzeugung, die der Detektor meldet.
function CreatesIn(AMap: TRdxCodeMap; const AFrom, ATo: TRdxToken): Boolean;
var
  T, P : TRdxToken;
begin
  Result := False;
  P := AFrom;
  T := After(AMap, AFrom);
  while (T.Low <> '') and TokBefore(T, ATo) do
  begin
    if (P.Low = '.') and T.IsWord and (Copy(T.Low, 1, 6) = 'create') then
      Exit(True);
    P := T;
    T := After(AMap, T);
  end;
end;

// SCA009/SCA001: die Erzeugung von AName auf ALine (genau eine). '' oder
// der Grund; APair mit Kind, Key, First, Semi und What.
function ObjectPair(AMap: TRdxCodeMap; ALine: Integer; const AName: string;
  var APair: TRdxPair): string;
var
  T, Prev   : TRdxToken;
  Site, Hit : TRdxCreateSite;
  n         : Integer;
begin
  APair.Kind := pkObject;
  APair.Key := LowerCase(AName);
  APair.Name := AName;
  APair.What := Format('%s.Free bzw. FreeAndNil(%s)', [AName, AName]);
  if AName = '' then
    Exit('Variable fehlt in der Meldung');
  Hit := Default(TRdxCreateSite);
  n := 0;
  Prev := PrevToken(AMap, ALine, 1);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if CreateAt(AMap, T, Prev, APair.Key, Site) then
    begin
      Inc(n);
      Hit := Site;
    end;
    Prev := T;
    T := After(AMap, T);
  end;
  Result := OneTokenReason(ALine, n, 'keine Zuweisung "' + AName + ' := .."',
    '%d Zuweisungen an %s', AName);
  if Result <> '' then Exit;
  APair.First := Hit.First;
  APair.Semi := StatementStop(AMap, After(AMap, Hit.Assign));
  if APair.Semi.Low <> ';' then
    Result := 'die Erzeugung ist die letzte Anweisung ihrer Liste - keine '
      + 'Freigabe dahinter'
  else if not CreatesIn(AMap, Hit.Assign, APair.Semi) then
    Result := 'keine Erzeugung (".Create..") in der Zuweisung - Fund veraltet? '
      + R_MOVED;
end;

// SCA109/SCA153: passt die Sperre S zum Text der Meldung? (je Regel)
type
  TRdxLockMatch = function(AMap: TRdxCodeMap; const S: TRdxLockSite;
    const AText: string): Boolean;

// SCA109: 'FLock' (das Wort vor '.Enter/.Acquire/.BeginWrite'),
// 'EnterCriticalSection(...)' bzw. 'TMonitor.Enter(o)' (das Argument klein
// bis zum ersten Zeichen ausser Buchstabe, Ziffer, '_', '.').
function Match109(AMap: TRdxCodeMap; const S: TRdxLockSite;
  const AText: string): Boolean;
var
  i : Integer;
begin
  case S.Form of
    lfCall:
      Result := SameText(NoBlanksLower(AText), ANY_CALL_109);
    lfMonitor:
      begin
        i := 1;
        while (i <= Length(S.Key))
           and CharInSet(S.Key[i], ['a'..'z', '0'..'9', '_', '.']) do
          Inc(i);
        Result := SameText(AText, 'TMonitor.Enter(' + Copy(S.Key, 1, i - 1)
          + ')');
      end;
  else
    Result := S.Owner.IsWord and SameText(TokText(AMap, S.Owner), AText)
      and InList(LOCK_PAIRS[S.Meth, sdAcquire], METHODS_109);
  end;
end;

// SCA153: 'FLocker.Lock', 'Lock', 'EnterCriticalSection' - das Ende des
// Aufrufs (ohne Argumente) ab einem '.' bzw. ganz.
function Match153(AMap: TRdxCodeMap; const S: TRdxLockSite;
  const AText: string): Boolean;
var
  Call, Want : string;
begin
  Result := False;
  if S.Form = lfMonitor then Exit;
  Call := KeyText(AMap, S.First, S.CallTok);
  Want := NoBlanksLower(AText);
  Result := (Want <> '') and ((Call = Want)
    or ((Length(Call) > Length(Want))
      and (Copy(Call, Length(Call) - Length(Want), MaxInt) = '.' + Want)));
end;

// Die Freigabe einer Sperre fuer die Gruende ('FLock.Leave').
function LockWhat(const S: TRdxLockSite): string;
begin
  case S.Form of
    lfCall:    Result := 'LeaveCriticalSection(' + S.Name + ')';
    lfMonitor: Result := 'TMonitor.Exit(' + S.Name + ')';
  else
    if S.Owner.Low = '' then
      Result := RELEASE_CAPS[S.Meth]
    else
      Result := S.Name + '.' + RELEASE_CAPS[S.Meth];
  end;
end;

// Steht auf ALine 'TMonitor.TryEnter(..)' oder 'TMonitor.Enter(O,
// Timeout)'? Beides ist eine Bedingung (Ergebnis Boolean), keine Sperre -
// SCA109 meldet sie trotzdem als 'TMonitor.Enter(o)' (Gegen-Review H4,
// Minor 5: bis Charge H4c hiess der Grund "Zeile verschoben?").
function MonitorConditionOn(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  T, M : TRdxToken;
  S    : TRdxLockSite;
begin
  Result := False;
  S := Default(TRdxLockSite);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    M := After(AMap, After(AMap, T));
    if (T.Low = 'tmonitor') and (After(AMap, T).Low = '.')
       and ((M.Low = MONITOR_TRY) or ((M.Low = MONITOR_CALLS[sdAcquire])
         and not MonitorAt(AMap, T, sdAcquire, S))) then
      Exit(True);
    T := After(AMap, T);
  end;
end;

// SCA109/SCA153: die eine Sperre auf ALine, die zur Meldung passt. '' oder
// der Grund; APair mit Lock, First, Semi und What.
function LockPair(AMap: TRdxCodeMap; ALine: Integer; const AText: string;
  AMatch: TRdxLockMatch; var APair: TRdxPair): string;
var
  T, Prev, E : TRdxToken;
  S, Hit     : TRdxLockSite;
  n          : Integer;
begin
  APair.Kind := pkLock;
  if AText = '' then
    Exit('Sperre fehlt in der Meldung');
  Hit := Default(TRdxLockSite);
  n := 0;
  Prev := PrevToken(AMap, ALine, 1);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if (Prev.Low <> '.') and LockSiteAt(AMap, T, sdAcquire, S)
       and AMatch(AMap, S, AText) then
    begin
      Inc(n);
      Hit := S;
    end;
    Prev := T;
    T := After(AMap, T);
  end;
  if (n = 0) and MonitorConditionOn(AMap, ALine) then
    Exit('TMonitor.Enter mit Timeout bzw. TMonitor.TryEnter ist eine '
      + 'Bedingung, keine Sperre - ob sie gilt, sagt erst das Ergebnis; '
      + R_BY_HAND);
  // Der Sperrtext der Meldung als Argument, nicht im Muster (OneTokenReason).
  Result := OneTokenReason(ALine, n, 'keine Sperre "' + AText + '"',
    '%d Sperren "%s"', AText);
  if Result <> '' then Exit;
  APair.Lock := Hit;
  APair.First := Hit.First;
  APair.Name := Hit.Name;
  APair.What := LockWhat(Hit);
  E := After(AMap, Hit.Last);
  APair.Semi := E;
  if E.Low <> ';' then
    Result := 'die Sperre ist keine ganze Anweisung mit ";" (letzte der Liste '
      + 'oder Teil eines Ausdrucks)';
end;

// SCA156: der Anfang des Aufrufs T - T selbst bzw. 'System' vor
// 'System.GetMem' (die RTL, Gegen-Review H4, Minor 4); Low = '' bei einem
// anderen Qualifizierer (eigener Speichermanager).
function AllocStart(AMap: TRdxCodeMap; const T, APrev: TRdxToken): TRdxToken;
var
  Q : TRdxToken;
begin
  Result := T;
  if APrev.Low <> '.' then Exit;
  Q := Before(AMap, APrev);
  if (Q.Low = 'system') and (Before(AMap, Q).Low <> '.') then
    Result := Q
  else
    Result := Default(TRdxToken);
end;

// SCA156: die Allokation an T (AStart: ihr erstes Token, AllocStart) -
// 'GetMem(P, N)', 'P := GetMem(N)'/'P := AllocMem(N)' oder die
// Inline-Deklaration 'var P[: T] := AllocMem(N)' (wie CreateAt; bis Charge
// B1 las der Planer dort den Typnamen als Puffer, Gegen-Review R5, R5-10).
// '' oder der Grund; APair mit Key, Name, First, What.
function BufferAt(AMap: TRdxCodeMap; const T, AStart: TRdxToken;
  var APair: TRdxPair): string;
var
  P, V, C, D : TRdxToken;
begin
  Result := '';
  P := Before(AMap, AStart);
  if P.Low = ':=' then
  begin
    D := InlineVarOf(AMap, P);
    if D.Low <> '' then
    begin
      V := After(AMap, D);
      APair.First := D;
    end
    else
    begin
      V := Before(AMap, P);
      APair.First := V;
    end;
    if not V.IsWord or (Before(AMap, V).Low = '.') then
      Exit('die Zuweisung geht an einen Ausdruck, nicht an eine Variable');
    if V.Low = 'result' then
      Exit('Result - der Puffer verlaesst die Routine');
  end
  else if T.Low = 'getmem' then
  begin
    V := After(AMap, After(AMap, T));
    C := After(AMap, V);
    if not V.IsWord or (C.Low <> ',') then
      Exit('das erste Argument von GetMem ist kein einfacher Bezeichner');
    APair.First := AStart;
  end
  else
    Exit('AllocMem ohne Zuweisung - der Puffer ist nicht zu fassen');
  APair.Key := V.Low;
  APair.Name := TokText(AMap, V);
  APair.What := 'FreeMem(' + APair.Name + ')';
end;

// SCA156: die eine Allokation AFunc auf ALine. '' oder der Grund.
function BufferPair(AMap: TRdxCodeMap; ALine: Integer; const AFunc: string;
  var APair: TRdxPair): string;
var
  T, Prev, Hit, Start, Q, C : TRdxToken;
  n, Qualified              : Integer;
  Func                      : string;
begin
  APair.Kind := pkBuffer;
  Func := LowerCase(AFunc);
  if Func = 'reallocmem' then
    Exit('ReallocMem - der Puffer bestand schon vorher (fremder bzw. '
      + 'vorhandener Speicher); ' + R_BY_HAND);
  Hit := Default(TRdxToken);
  Start := Hit;
  n := 0;
  Qualified := 0;
  Prev := PrevToken(AMap, ALine, 1);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if (T.Low = Func) and (After(AMap, T).Low = '(') then
    begin
      Q := AllocStart(AMap, T, Prev);
      if Q.Low = '' then
        Inc(Qualified)
      else
      begin
        Inc(n);
        Hit := T;
        Start := Q;
      end;
    end;
    Prev := T;
    T := After(AMap, T);
  end;
  if (n = 0) and (Qualified > 0) then
    Exit(Format('%s eines eigenen Speichermanagers (qualifiziert) - %s',
      [AFunc, R_BY_HAND]));
  Result := OneTokenReason(ALine, n, 'kein Aufruf ' + AFunc + '(',
    '%d Aufrufe %s(', AFunc);
  if Result = '' then
    Result := BufferAt(AMap, Hit, Start, APair);
  if Result <> '' then Exit;
  C := MatchClose(AMap, After(AMap, Hit));
  APair.Semi := After(AMap, C);
  if (C.Low = '') or (APair.Semi.Low <> ';') then
    Result := 'die Allokation ist keine ganze Anweisung mit ";"';
end;

{ TRdxTryFixes }

// SCA009/SCA001: der Name aus der Meldung, dann der Baustein.
function ObjectFix(AMap: TRdxCodeMap; ALine: Integer; const AMessage: string;
  out APlan: TRdxTryPlan): string;
var
  Pair : TRdxPair;
begin
  APlan := Default(TRdxTryPlan);
  APlan.Name := FirstWordOf(AMessage);
  Pair := Default(TRdxPair);
  Result := ObjectPair(AMap, ALine, APlan.Name, Pair);
  if Result = '' then
    Result := TryFinally(AMap, Pair, APlan.Edit);
end;

class function TRdxTryFixes.MissingFinally(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out APlan: TRdxTryPlan;
  out AReason: string): Boolean;
begin
  AReason := ObjectFix(AMap, ALine, AMessage, APlan);
  Result := AReason = '';
end;

class function TRdxTryFixes.FreedOutsideFinally(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxTryPlan;
  out AReason: string): Boolean;
begin
  AReason := ObjectFix(AMap, ALine, AMessage, APlan);
  Result := AReason = '';
end;

// SCA109/SCA153: der Text der Meldung, die Sperre, dann der Baustein.
function LockFix(AMap: TRdxCodeMap; ALine: Integer; const AText: string;
  AMatch: TRdxLockMatch; out APlan: TRdxTryPlan): string;
var
  Pair : TRdxPair;
begin
  APlan := Default(TRdxTryPlan);
  APlan.Name := Trim(AText);
  Pair := Default(TRdxPair);
  Result := LockPair(AMap, ALine, Trim(AText), AMatch, Pair);
  if Result = '' then
  begin
    APlan.Name := Pair.Name;
    Result := TryFinally(AMap, Pair, APlan.Edit);
  end;
end;

class function TRdxTryFixes.LockWithoutFinally(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxTryPlan;
  out AReason: string): Boolean;
begin
  AReason := LockFix(AMap, ALine, MessagePart(AMessage, KEY_LOCK109,
    KEY_LOCK109E), Match109, APlan);
  Result := AReason = '';
end;

class function TRdxTryFixes.UnpairedLock(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out APlan: TRdxTryPlan;
  out AReason: string): Boolean;
begin
  AReason := LockFix(AMap, ALine, MessageTail(AMessage, KEY_LOCK153), Match153,
    APlan);
  Result := AReason = '';
end;

class function TRdxTryFixes.NameOf(const AMessage: string): string;
begin
  Result := FirstWordOf(AMessage);
end;

class function TRdxTryFixes.GetMemWithoutFree(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxTryPlan;
  out AReason: string): Boolean;
var
  Pair : TRdxPair;
  Func : string;
begin
  APlan := Default(TRdxTryPlan);
  Pair := Default(TRdxPair);
  Func := FirstWordOf(AMessage);
  if Func = '' then
    AReason := 'Allokation fehlt in der Meldung'
  else
    AReason := BufferPair(AMap, ALine, Func, Pair);
  APlan.Name := Pair.Name;
  if AReason = '' then
    AReason := TryFinally(AMap, Pair, APlan.Edit);
  Result := AReason = '';
end;

end.

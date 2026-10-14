unit uRdxTryFixes;

// reDelphix - Quick-Fixes "try/finally", OHNE ToolsAPI und ohne Parser
// (Konzept_Editorhilfen_Recherche_2026-10-11, Abschnitt 5 Baustein B5,
// Abschnitt 6 Charge H4):
//   SCA009 MissingFinally: 'X := TFoo.Create..;' .. 'X.Free;' (auch
//          'FreeAndNil(X)', 'X.Destroy') - die Zeilen dazwischen kommen in
//          den try-Teil, die Freigabe ins finally; ein direkt folgendes
//          'X := nil;' geht mit. Mit dem Meldungs-Suffix ' (try/except
//          instead of try/finally)' nur, wenn ein try/except im Bereich
//          liegt und keines ihn umschliesst.
//   SCA001 MemoryLeak: dieselbe Hilfe, nur fuer die Variante
//          freed-outside-finally - die prueft der Aufrufer (uRdxFixTable,
//          Feld TLeakFinding.LeakVariant); proven-leak, never-freed und
//          return-value bekommen keine.
//   SCA109 LockWithoutTryFinally, SCA153 UnpairedLock: die Sperre (Lock/
//          UnLock, Enter/Leave, Acquire/Release, BeginWrite/EndWrite,
//          TMonitor.Enter(O)/TMonitor.Exit(O), EnterCriticalSection(CS)/
//          LeaveCriticalSection(CS)). Die Freigabe bestimmt der Planer
//          selbst: derselbe Empfaenger bzw. dasselbe Argument, als Text
//          ohne Leerraum gleich - SCA153 nimmt jedes 'unlock'/'release' im
//          200-Zeichen-Fenster, auch das fremder Objekte.
//   SCA156 GetMemWithoutFreeMem: 'GetMem(P, N);' bzw. 'P := AllocMem(N);'
//          (auch FPC 'P := GetMem(N);') .. 'FreeMem(P);'; ReallocMem
//          sperrt (der Puffer bestand schon vorher).
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
// Leerzeichen bzw. ein Tab. Leerzeilen bleiben leer.
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
//   * Direktive, Marke/goto (ein Sprung in einen try-Block uebersetzt
//     nicht), Inline-var/const auf der Ebene von A (ihr Gueltigkeitsbereich
//     schrumpfte auf den try-Block), mehrzeiliges '''-Literal (Einruecken
//     aendert den String), asm im Bereich;
//   * Break/Continue, deren Schleife den Bereich umschliesst (B liefe dort
//     jetzt mit - ein Objekt, das hinter der Schleife noch gebraucht wird,
//     waere frei); Exit bei einer Sperre (Konzept: Ablehnung); Exit bei
//     einem Objekt bzw. Puffer, der im Bereich weitergegeben wird (der
//     Ausstieg koennte den Besitz uebergeben haben); 'raise X';
//   * die Variable (bzw. die Freigabe der Sperre) im except-/finally-Teil
//     eines try, das A umschliesst - nach dem Fix liefe dort eine zweite
//     Freigabe bzw. ein Zugriff auf ein freigegebenes Objekt;
//   * Puffer: Inc/Dec/GetMem/ReallocMem bzw. '@' auf P im Bereich (FreeMem
//     gaebe einen anderen Zeiger frei).
// Eine Weitergabe ohne Ausstieg (Liste.Add(X) .. Liste.Remove(X); X.Free)
// sieht der Planer nicht als Sperre - im Fehlerfall gaebe finally X frei,
// waehrend die Liste es noch kennt (Restrisiko, README).

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

  // Die Form der Planer (uRdxFixTable: TryFix).
  TRdxTryPlanner = function(AMap: TRdxCodeMap; ALine: Integer;
    const AMessage: string; out APlan: TRdxTryPlan;
    out AReason: string): Boolean;

  // Die Planer der Charge H4 (s. Kopf): je Fund EINE Ersetzung oder der
  // Grund, warum keine - auf dem Puffertext ueber die Code-Sicht (laeuft
  // auch im FPC-Pruefstand).
  TRdxTryFixes = class
  public
    // SCA009: die Erzeugung von X (Meldung: 'X' bzw. 'X (try/except instead
    // of try/finally)') auf ALine und ihre Freigabe in try/finally setzen.
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
  uRdxStructFixes;   // RangeText, CommentInRange

const
  SPAN_TRY = 'try';
  KEY_SUFFIX   = ' (try/except instead of try/finally)';
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
  FREEMEM_WORDS: array[0..1] of string = ('freemem', 'freememandnil');
  // Sie veraendern P (Puffer): FreeMem gaebe danach einen anderen Zeiger
  // frei.
  BUFFER_CHANGERS: array[0..3] of string = ('inc', 'dec', 'getmem',
    'reallocmem');
  // Hinter X: ein Member-Zugriff, keine Weitergabe von X.
  MEMBER_SUFFIXES: array[0..2] of string = ('.', '[', '^');
  // Schleifenkoepfe bis zum do.
  LOOP_HEADS: array[0..1] of string = ('for', 'while');
  INLINE_DECLS: array[0..1] of string = ('var', 'const');
  JUMP_OUT: array[0..1] of string = ('break', 'continue');
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
  R_MOVED = 'Zeile verschoben? Datei neu pruefen';
  R_BY_HAND = 'von Hand pruefen';

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
    Suffix : Boolean;        // SCA009: '(try/except instead of try/finally)'
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
    HasExcept  : Boolean;          // ein try/except im Bereich
    ExitLine   : Integer;          // erstes Exit, 0 = keins
    EscapeLine : Integer;          // erste Weitergabe von X, 0 = keine
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
  LOCK_CALLS: array[TRdxLockSide] of string = ('entercriticalsection',
    'leavecriticalsection');
  MONITOR_CALLS: array[TRdxLockSide] of string = ('enter', 'exit');
  // SCA109 meldet nur diese Methoden (uLockWithoutTryFinally).
  METHODS_109: array[0..2] of string = ('enter', 'acquire', 'beginwrite');

{ ---- kleine Helfer ---- }

function TokBefore(const A, B: TRdxToken): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Col < B.Col));
end;

function TokText(AMap: TRdxCodeMap; const T: TRdxToken): string;
begin
  Result := Copy(AMap.Raw(T.Line), T.Col, T.Len);
end;

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

// Der Text zwischen AOpen und ACloser (dem ersten dahinter bzw. bei
// ALastCloser dem letzten der Meldung); '' ohne.
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

// Das erste Wort der Meldung (SCA009/SCA001: der Variablenname, auch vor
// ' (try/except ...)' und ' - Rueckgabewert'); '' ohne.
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

function IsListEnd(const T, APrev: TRdxToken): Boolean;
begin
  Result := IsKeywordAfter(T, APrev) and InList(T.Low, LIST_ENDS);
end;

// Hinter (ALine, ACol) nur Leerraum oder Kommentar, und die Folgezeile
// beginnt nicht in einem Kommentar oder mehrzeiligen String - dort darf
// eine Zeile hinein (try bzw. end;).
function LineEndsAfter(AMap: TRdxCodeMap; ALine, ACol: Integer): Boolean;
var
  L  : string;
  Co : Integer;
begin
  L := AMap.Raw(ALine);
  for Co := ACol + 1 to Length(L) do
    if (AMap.ClassAt(ALine, Co) <> 'k') and not IsBlank(L[Co]) then
      Exit(False);
  Result := not AMap.StartsInside(ALine + 1);
end;

// Steht T als erstes auf seiner Zeile (davor nur Leerraum)?
function FirstOnLine(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
begin
  Result := SkipBlanks(AMap.Raw(T.Line), 1) = T.Col;
end;

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

// Das Ende der Anweisung ab AFrom: das ';' ausserhalb von Klammern und
// Bloecken (eine anonyme Methode im Argument traegt eigene) oder, steht
// keines davor, das Listenende (end, until, except, finally, else); Low =
// '' am Dateiende.
// Ein Token von StatementStop: Klammer- und Blocktiefe fortschreiben; True,
// wo die Anweisung endet.
function StopStep(const T, APrev: TRdxToken; var AParen, ADepth: Integer): Boolean;
var
  Word : Boolean;
begin
  Result := False;
  Word := IsKeywordAfter(T, APrev);
  if (T.Low = '(') or (T.Low = '[') then
    Inc(AParen)
  else if (T.Low = ')') or (T.Low = ']') then
    Dec(AParen)
  else if Word and IsEndOpener(T.Low) then
    Inc(ADepth)
  else if (AParen > 0) or (ADepth > 0) then
  begin
    if Word and (T.Low = 'end') then
      Dec(ADepth);
  end
  else
    Result := (T.Low = ';')
      or (Word and (InList(T.Low, LIST_ENDS) or (T.Low = 'else')));
end;

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
    if StopStep(T, P, Paren, Depth) then
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
  F := T;
  while (After(AMap, F).Low = '.') and After(AMap, After(AMap, F)).IsWord do
    F := After(AMap, After(AMap, F));
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

// Dieselbe Sperre wie A (Form, Schluessel, Methode)?
function SameLock(const A, B: TRdxLockSite): Boolean;
begin
  Result := (A.Form = B.Form) and (A.Key = B.Key)
    and ((A.Form <> lfMethod) or (A.Meth = B.Meth));
end;

// Ab T die Freigabe von A? AHit.KeyTok: das Token mit dem Namen (Objekt,
// Puffer), AHit.Last: das letzte Token des Aufrufs.
function ObjectReleaseAt(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  const AKey: string; out AHit: TRdxReleaseHit): Boolean;
var
  D, M, O, V, C : TRdxToken;
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
  // Auch qualifiziert ('SysUtils.FreeAndNil(X)').
  if (T.Low <> 'freeandnil') or not T.IsWord then Exit;
  O := After(AMap, T);
  V := After(AMap, O);
  C := After(AMap, V);
  Result := (O.Low = '(') and MentionsKey(V, O, AKey) and (C.Low = ')');
  AHit.KeyTok := V;
  AHit.Last := C;
end;

function BufferReleaseAt(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  const AKey: string; out AHit: TRdxReleaseHit): Boolean;
var
  O, N : TRdxToken;
begin
  Result := False;
  AHit := Default(TRdxReleaseHit);
  // Auch qualifiziert ('System.FreeMem(P)').
  if not InList(T.Low, FREEMEM_WORDS) or not T.IsWord then
    Exit;
  O := After(AMap, T);
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
      Result := BufferReleaseAt(AMap, T, APrev, APair.Key, AHit);
  else
    Result := (APrev.Low <> '.') and LockSiteAt(AMap, T, sdRelease, S)
      and (S.Form = APair.Lock.Form) and (S.Key = APair.Lock.Key)
      and ((S.Form <> lfMethod) or (S.Meth = APair.Lock.Meth));
    AHit.Last := S.Last;
  end;
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
  else if not IsListEnd(E, Last) then
    S.Reason := Format('die Freigabe in Zeile %d ist keine ganze Anweisung',
      [T.Line]);
  S.B := T;
  S.BLast := Last;
end;

// Puffer: Inc(P)/Dec(P)/GetMem(P)/ReallocMem(P) an T? '' oder der Grund.
function BufferChangeReason(AMap: TRdxCodeMap; const APair: TRdxPair;
  const T, APrev: TRdxToken): string;
var
  O : TRdxToken;
begin
  Result := '';
  if (APair.Kind <> pkBuffer) or not InList(T.Low, BUFFER_CHANGERS)
     or not IsKeywordAfter(T, APrev) then
    Exit;
  O := After(AMap, T);
  if (O.Low = '(') and MentionsKey(After(AMap, O), O, APair.Key) then
    Result := Format('%s(%s) in Zeile %d veraendert den Zeiger - FreeMem gaebe '
      + 'im finally einen anderen frei', [TokText(AMap, T), APair.Key, T.Line]);
end;

// Ein Vorkommen der Variablen (Objekt, Puffer) an T: zweite Zuweisung,
// Adresse, 'raise X' sperren; eine Weitergabe (kein Member-Zugriff) merkt
// sich S fuer die Exit-Sperre. '' oder der Grund.
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
  if APrev.Low = 'raise' then
    Exit(Format('raise %s in Zeile %d - das Objekt ist die Ausnahme; finally '
      + 'gaebe es vor dem Handler frei', [TokText(AMap, T), T.Line]));
  if not InList(N.Low, MEMBER_SUFFIXES) and (S.EscapeLine = 0) then
    S.EscapeLine := T.Line;
end;

// Eine Freigabe bzw. (Sperre) zweite Sperre an T, die nicht B ist. '' oder
// der Grund.
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
  if APair.Kind <> pkLock then
    Exit(VarUseReason(AMap, APair, S, T, APrev));
  Result := '';
  if (APrev.Low <> '.') and LockSiteAt(AMap, T, sdAcquire, L)
     and SameLock(L, APair.Lock) then
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
  begin
    S.EndSingles;
    S.HasExcept := S.HasExcept or (T.Low = 'except');
  end
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
  else if IsKeywordAfter(T, APrev) then
  begin
    HeadStep(S, T);
    S.Reason := JumpReason(APair, S, T, APrev);
    if S.Reason = '' then
      S.Reason := BlockReason(S, T);
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

// Hinter 'X.Free;' ein 'X := nil;' als naechste Anweisung? Dann geht es
// mit ins finally (S.BLast).
procedure TakeNil(AMap: TRdxCodeMap; const APair: TRdxPair; var S: TRdxSpan);
var
  V, A, N, E : TRdxToken;
begin
  if (APair.Kind <> pkObject) or (S.BLast.Low <> ';')
     or (After(AMap, After(AMap, S.B)).Low <> 'free') then
    Exit;
  V := After(AMap, S.BLast);
  A := After(AMap, V);
  N := After(AMap, A);
  E := After(AMap, N);
  if (V.Low <> APair.Key) or (A.Low <> ':=') or (N.Low <> 'nil') then Exit;
  if E.Low = ';' then
    S.BLast := E
  else if IsListEnd(E, N) then
    S.BLast := N;
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
  else if not LineEndsAfter(AMap, S.BLast.Line, S.BLast.EndCol - 1) then
    Result := Format('hinter der Freigabe in Zeile %d steht weiterer Code',
      [S.BLast.Line])
  else if DirectiveInLines(AMap, APair.First.Line, S.BLast.Line) then
    Result := 'Compiler-Direktive im Bereich - try oder finally stuende '
      + 'womoeglich in nur einem Zweig'
  else if MultiStringIn(AMap, APair.First.Line, S.BLast.Line) then
    Result := 'mehrzeiliges String-Literal im Bereich - Einruecken aenderte '
      + 'seinen Inhalt'
  else if (S.ExitLine > 0) and (S.EscapeLine > 0) then
    Result := Format('Exit in Zeile %d, und %s wird in Zeile %d weitergegeben '
      + '- der Ausstieg koennte den Besitz uebergeben haben; %s',
      [S.ExitLine, APair.Key, S.EscapeLine, R_BY_HAND]);
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
    if IsKeywordAfter(T, P) and Scan.Step(T, P) then
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
begin
  AStart := Default(TRdxToken);
  AEnd := Default(TRdxToken);
  Depth := 1;
  Prev := ATry;
  T := After(AMap, ATry);
  while T.Low <> '' do
  begin
    if IsKeywordAfter(T, Prev) and IsEndOpener(T.Low) then
      Inc(Depth)
    else if IsKeywordAfter(T, Prev) and (T.Low = 'end') then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        AEnd := T;
        Exit(AStart.Low <> '');
      end;
    end
    else if (Depth = 1) and IsKeywordAfter(T, Prev)
       and ((T.Low = 'except') or (T.Low = 'finally')) then
      AStart := T;
    Prev := T;
    T := After(AMap, T);
  end;
  Result := False;
end;

// Kommt A im Handler AStart..AEnd vor - die Variable (Objekt, Puffer)
// bzw. die Freigabe der Sperre? Das Token oder leer.
function MentionIn(AMap: TRdxCodeMap; const APair: TRdxPair;
  const AStart, AEnd: TRdxToken): TRdxToken;
var
  T, P    : TRdxToken;
  Release : TRdxReleaseHit;
  Hit     : Boolean;
begin
  Result := Default(TRdxToken);
  P := AStart;
  T := After(AMap, AStart);
  while (T.Low <> '') and TokBefore(T, AEnd) do
  begin
    if APair.Kind = pkLock then
      Hit := ReleaseAt(AMap, APair, T, P, Release)
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
// freigegebenes Objekt); mit dem SCA009-Suffix darf keiner ein try/except
// sein, und im Bereich muss eines liegen. '' oder der Grund.
function EnclosingReason(AMap: TRdxCodeMap; const APair: TRdxPair;
  const S: TRdxSpan): string;
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
    if APair.Suffix and (Start.Low = 'except') then
      Exit(Format('die Meldung nennt ein try/except - es umschliesst den '
        + 'Bereich (Zeile %d) und liegt nicht ganz darin', [Tries[i].Line]));
  end;
  if APair.Suffix and not S.HasExcept then
    Result := 'die Meldung nennt ein try/except - im Bereich liegt keines; '
      + R_BY_HAND;
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
  else if not LineEndsAfter(AMap, APair.Semi.Line, APair.Semi.Col) then
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
    if IsKeywordAfter(T, P) and ((T.Low = 'end') or (T.Low = 'until')) then
      Inc(Depth)
    else if IsKeywordAfter(T, P) and InList(T.Low, LIST_PREV) and (Depth = 0) then
      Exit(T)
    else if IsKeywordAfter(T, P) and (IsEndOpener(T.Low) or (T.Low = 'repeat')) then
      Dec(Depth);
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

// Eine Zeile eine Stufe tiefer; eine leere bleibt leer.
function Deeper(const ALine, AStep: string): string;
begin
  Result := ALine;
  if Trim(ALine) <> '' then
    Result := AStep + ALine;
end;

// Die Ersetzung: vom letzten Zeichen der Zeile von A bis zum Ende der
// letzten Zeile von B - try, die Zeilen dazwischen eine Stufe tiefer,
// finally, B eine Stufe tiefer, end;. Der Bereich beginnt AUF einem Zeichen
// (SpanFits), das unveraendert neu geschrieben wird.
function TryEdit(AMap: TRdxCodeMap; const APair: TRdxPair;
  const S: TRdxSpan): TRdxEdit;
var
  ALine, Li  : Integer;
  L, Ind     : string;
  Step, Text : string;
  SB         : TStringBuilder;
begin
  Result := Default(TRdxEdit);
  ALine := APair.Semi.Line;
  L := AMap.Raw(APair.First.Line);
  Ind := Copy(L, 1, SkipBlanks(L, 1) - 1);
  Step := ListStep(AMap, APair.First, Ind);
  Text := AMap.Raw(ALine);
  SB := TStringBuilder.Create;
  try
    SB.Append(Copy(Text, Length(Text), 1)).Append(#10);
    SB.Append(Ind).Append('try').Append(#10);
    for Li := ALine + 1 to S.B.Line - 1 do
      SB.Append(Deeper(AMap.Raw(Li), Step)).Append(#10);
    SB.Append(Ind).Append('finally');
    for Li := S.B.Line to S.BLast.Line do
      SB.Append(#10).Append(Deeper(AMap.Raw(Li), Step));
    SB.Append(#10).Append(Ind).Append('end;');
    Result.NewText := SB.ToString;
  finally
    SB.Free;
  end;
  Result.Span := TRefactorSpan.Make(SPAN_TRY, ALine, Length(Text), S.BLast.Line,
    Length(AMap.Raw(S.BLast.Line)) + 1);
  Result.Expected := RangeText(AMap, Result.Span);
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
    Result := EnclosingReason(AMap, APair, S);
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
  if (APrev.Low = 'var') and IsKeywordAfter(APrev, Before(AMap, APrev)) then
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
    '%d Zuweisungen an ' + AName);
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
  Result := OneTokenReason(ALine, n, 'keine Sperre "' + AText + '"',
    '%d Sperren "' + AText + '"');
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

// SCA156: die Allokation AFunc (GetMem/AllocMem) an T - 'GetMem(P, N)' oder
// 'P := GetMem(N)'/'P := AllocMem(N)'. '' oder der Grund; APair mit Key,
// First, What.
function BufferAt(AMap: TRdxCodeMap; const T: TRdxToken;
  var APair: TRdxPair): string;
var
  P, V, C : TRdxToken;
begin
  Result := '';
  P := Before(AMap, T);
  if P.Low = ':=' then
  begin
    V := Before(AMap, P);
    if not V.IsWord or (Before(AMap, V).Low = '.') then
      Exit('die Zuweisung geht an einen Ausdruck, nicht an eine Variable');
    if V.Low = 'result' then
      Exit('Result - der Puffer verlaesst die Routine');
    APair.First := V;
  end
  else if T.Low = 'getmem' then
  begin
    V := After(AMap, After(AMap, T));
    C := After(AMap, V);
    if not V.IsWord or (C.Low <> ',') then
      Exit('das erste Argument von GetMem ist kein einfacher Bezeichner');
    APair.First := T;
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
  T, Prev, Hit, C : TRdxToken;
  n, Qualified    : Integer;
begin
  APair.Kind := pkBuffer;
  if LowerCase(AFunc) = 'reallocmem' then
    Exit('ReallocMem - der Puffer bestand schon vorher (fremder bzw. '
      + 'vorhandener Speicher); ' + R_BY_HAND);
  Hit := Default(TRdxToken);
  n := 0;
  Qualified := 0;
  Prev := PrevToken(AMap, ALine, 1);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if (T.Low = LowerCase(AFunc)) and (After(AMap, T).Low = '(')
       and (Prev.Low = '.') then
      Inc(Qualified)
    else if (T.Low = LowerCase(AFunc)) and (After(AMap, T).Low = '(') then
    begin
      Inc(n);
      Hit := T;
    end;
    Prev := T;
    T := After(AMap, T);
  end;
  if (n = 0) and (Qualified > 0) then
    Exit(Format('%s eines eigenen Speichermanagers (qualifiziert) - %s',
      [AFunc, R_BY_HAND]));
  Result := OneTokenReason(ALine, n, 'kein Aufruf ' + AFunc + '(',
    '%d Aufrufe ' + AFunc + '(');
  if Result = '' then
    Result := BufferAt(AMap, Hit, APair);
  if Result <> '' then Exit;
  C := MatchClose(AMap, After(AMap, Hit));
  APair.Semi := After(AMap, C);
  if (C.Low = '') or (APair.Semi.Low <> ';') then
    Result := 'die Allokation ist keine ganze Anweisung mit ";"';
end;

{ TRdxTryFixes }

// SCA009/SCA001: der Name aus der Meldung, dann der Baustein.
function ObjectFix(AMap: TRdxCodeMap; ALine: Integer; const AMessage: string;
  var APair: TRdxPair; out APlan: TRdxTryPlan): string;
begin
  APlan := Default(TRdxTryPlan);
  APlan.Name := FirstWordOf(AMessage);
  Result := ObjectPair(AMap, ALine, APlan.Name, APair);
  if Result = '' then
    Result := TryFinally(AMap, APair, APlan.Edit);
end;

class function TRdxTryFixes.MissingFinally(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out APlan: TRdxTryPlan;
  out AReason: string): Boolean;
var
  Pair : TRdxPair;
begin
  Pair := Default(TRdxPair);
  Pair.Suffix := Pos(KEY_SUFFIX, AMessage) > 0;
  AReason := ObjectFix(AMap, ALine, AMessage, Pair, APlan);
  Result := AReason = '';
end;

class function TRdxTryFixes.FreedOutsideFinally(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxTryPlan;
  out AReason: string): Boolean;
var
  Pair : TRdxPair;
begin
  Pair := Default(TRdxPair);
  AReason := ObjectFix(AMap, ALine, AMessage, Pair, APlan);
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

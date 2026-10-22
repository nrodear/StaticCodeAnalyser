unit uRdxTrySpan;

// reDelphix - der Lauf des Bausteins B5 (try/finally) von A nach B, OHNE
// ToolsAPI und ohne Parser (Konzept_Editorhilfen_Recherche_2026-10-11,
// Abschnitt 5 Baustein B5, Abschnitt 6 Charge H4; bis Review Woche G08-08
// in uRdxTryFixes). Ab dem ';' hinter A liest ScanSpan Token fuer Token
// bis zur Freigabe B als ganzer, unbedingter Anweisung in derselben Liste
// und sperrt unterwegs (SpanStep): Bloecke und Schleifen (TRdxSpan),
// Spruenge auch als 'System.Exit', Marken, Inline-Deklarationen, eine
// zweite bzw. andere Freigabe oder Sperre, raise, Puffer-Aenderungen und
// jede Nennung von X - ob sie X weitergibt, entscheidet uRdxHandOver
// (HandOverReason). Danach 'X := nil;' (TakeNil) und die Gegenproben am
// Bereich (SpanReason) - zusammen ScanPair -, dazu rueckwaerts die
// try-Bloecke um A (EnclosingReason). Was sperrt und warum: Kopf von
// uRdxTryFixes (SPERREN).
//
// Das Vokabular dazu - Paare (TRdxPair), Sperren und Freigaben
// (TRdxLockSite, LockSiteAt, MonitorAt) und Schluessel (KeyText,
// NoBlanksLower, MentionsKey, StatementStop) - steht hier im interface,
// weil Lauf und Paar-Finder (uRdxTryFixes) es teilen.

interface

uses
  uRdxCodeMap;

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

  // Ein Paar A/B fuer den Baustein B5 (Kopf von uRdxTryFixes); die
  // Paar-Finder dort fuellen es, der Lauf hier liest es.
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

const
  // Sperre und Freigabe je Form (Index Meth bzw. Seite).
  LOCK_PAIRS: array[0..3, TRdxLockSide] of string = (('lock', 'unlock'),
    ('enter', 'leave'), ('acquire', 'release'), ('beginwrite', 'endwrite'));
  MONITOR_CALLS: array[TRdxLockSide] of string = ('enter', 'exit');

// Ohne Leerraum und klein - wie Empfaenger und Argumente verglichen werden.
function NoBlanksLower(const S: string): string;

// Der Text von AFrom bis ATo ohne Leerraum, klein; '' bei einem Kommentar
// darin.
function KeyText(AMap: TRdxCodeMap; const AFrom, ATo: TRdxToken): string;

// Ist T das Wort AKey (klein) und kein Member ('.X')?
function MentionsKey(const T, APrev: TRdxToken; const AKey: string): Boolean;

// Das Ende der Anweisung ab AFrom: das ';' ausserhalb von Klammern und
// Bloecken bzw. das Listenende; Low = '' am Dateiende.
function StatementStop(AMap: TRdxCodeMap; const AFrom: TRdxToken): TRdxToken;

// 'TMonitor.Enter(O)' bzw. 'TMonitor.Exit(O)' ab T.
function MonitorAt(AMap: TRdxCodeMap; const T: TRdxToken;
  ASide: TRdxLockSide; var S: TRdxLockSite): Boolean;

// Eine Sperre (ASide = sdAcquire) bzw. Freigabe ab T; bei False ist S
// leer.
function LockSiteAt(AMap: TRdxCodeMap; const T: TRdxToken;
  ASide: TRdxLockSide; out S: TRdxLockSite): Boolean;

// Der Lauf von A (APair) nach B samt den Gegenproben am Bereich. '' und
// S (B in S.B..S.BLast) oder der Grund.
function ScanPair(AMap: TRdxCodeMap; const APair: TRdxPair;
  out S: TRdxSpan): string;

// Die try-Bloecke um A: ihr Handler darf A nicht kennen. '' oder der
// Grund.
function EnclosingReason(AMap: TRdxCodeMap; const APair: TRdxPair): string;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make (KeyText)
  uRdxHandOver;      // HandOverReason, SourceText, QualifiedEnd, ARG_ENDS

const
  SPAN_TRY = 'try';
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
  R_BY_HAND = 'von Hand pruefen';
  // Familie je Index von LOCK_PAIRS: Enter/Leave und Acquire/Release sind
  // bei TCriticalSection dieselbe Sperre (SameLockLoose).
  LOCK_FAMILY: array[0..3] of Integer = (0, 1, 1, 2);
  LOCK_CALLS: array[TRdxLockSide] of string = ('entercriticalsection',
    'leavecriticalsection');

type
  // Eine Freigabe (ReleaseAt): das Token mit dem Namen (Objekt, Puffer)
  // und das letzte Token des Aufrufs.
  TRdxReleaseHit = record
    KeyTok : TRdxToken;
    Last   : TRdxToken;
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

// Ein Token von StatementStop: Klammer- und Blocktiefe fortschreiben; True,
// wo die Anweisung endet.
function StopStep(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  var AParen, ADepth: Integer): Boolean;
var
  IsKw  : Boolean;
  Delta : Integer;
begin
  Result := False;
  IsKw := IsKeywordAt(AMap, T, APrev);
  Delta := ParenDelta(T);
  if Delta <> 0 then
    Inc(AParen, Delta)
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
    Inc(Depth, ParenDelta(T));
    if (T.Low = ',') and (Depth = 0) then Exit;
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
// Ausdruck (davor kein '.'). Bei False ist S leer: MonitorAt, CallAt und
// MethodAt setzen Felder, bevor ihre letzte Probe scheitern kann.
function LockSiteAt(AMap: TRdxCodeMap; const T: TRdxToken;
  ASide: TRdxLockSide; out S: TRdxLockSite): Boolean;
begin
  S := Default(TRdxLockSite);
  Result := T.IsWord and (MonitorAt(AMap, T, ASide, S)
    or CallAt(AMap, T, ASide, S) or MethodAt(AMap, T, ASide, S));
  if not Result then
    S := Default(TRdxLockSite);
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
// 'TFoo(Self.X)', auch generisch 'TList<TFoo>(X)' (Typparameter auf der
// Zeile des Namens; Review Woche G08-02: 'TList<TFoo>(X).Free' im Bereich
// lief nach dem Fix doppelt); ALast = das Token mit dem Namen bzw. die ')'.
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
  if O.Low = '<' then
  begin
    C := MatchClose(AMap, O, 0);
    if C.Low = '' then Exit;
    O := After(AMap, C);
  end;
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
    if Result then
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

// Spruenge, asm und Inline-Deklarationen im Bereich des try/finally. ''
// oder der Grund. Bis zur Nachpruefung B2S hiess sie JumpReason wie zwei
// andere Routinen mit anderem Vertrag (uRdxFlowFixes.RedundantJumpReason
// fuer SCA080, uRdxInheritedFixes.LeavesDestructorReason fuer SCA097; Review
// R3-05/R5-03).
function SpanJumpReason(const APair: TRdxPair; var S: TRdxSpan;
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
  else if InList(T.Low, INLINE_DECLS) and (S.Depth = 0) and (S.Paren = 0)
     and InList(APrev.Low, LIST_PREV) then
    Result := Format('Inline-Deklaration (%s) in Zeile %d - ihr '
      + 'Gueltigkeitsbereich schrumpfte auf den try-Block', [T.Low, T.Line]);
end;

// Eine Marke 'L:' am Anfang einer Anweisung (nicht in einem case, nicht in
// Klammern)? Ein goto von aussen in den try-Block uebersetzt nicht. '' oder
// der Grund. In Klammern steht hinter ';' ein Parameter einer anonymen
// Methode ('procedure(A: Integer; B: Integer)') - bis Review Woche G08-10
// die "Marke B:", wie das 'const' dort die "Inline-Deklaration"
// (SpanJumpReason); eine Marke im Rumpf einer anonymen Methode gehoert zu
// ihr, ein goto von aussen erreicht sie ohnehin nicht.
function LabelReason(AMap: TRdxCodeMap; const S: TRdxSpan;
  const T, APrev: TRdxToken): string;
begin
  Result := '';
  if (S.Paren = 0) and InList(APrev.Low, LIST_PREV)
     and (S.InnerKind <> BLOCK_CASE)
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
    Result := SpanJumpReason(APair, S, T, APrev);
    if Result = '' then
      Result := BlockReason(S, T);
  end
  else if InList(T.Low, SYSTEM_JUMPS) and SystemQualified(AMap, T, APrev) then
    Result := SpanJumpReason(APair, S, T, APrev);
end;

// Ein Token des Laufs (ScanSpan): rsFound an B, rsStop mit S.Reason.
function SpanStep(AMap: TRdxCodeMap; const APair: TRdxPair; var S: TRdxSpan;
  const T, APrev: TRdxToken): TRdxStep;
var
  Delta : Integer;
begin
  Result := rsStop;
  if TakeRelease(AMap, APair, S, T, APrev) then
    Exit(rsFound);
  S.TakeLoopDo(T);
  S.Reason := UseReason(AMap, APair, S, T, APrev);
  if S.Reason = '' then
    S.Reason := LabelReason(AMap, S, T, APrev);
  if S.Reason <> '' then Exit;
  Delta := ParenDelta(T);
  if Delta <> 0 then
    Inc(S.Paren, Delta)
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
// ganze Hilfe). Puffer seit Charge B1-FE (Gegen-Review R5, R5-02): Freigabe und
// nil bleiben beisammen wie bei Objekten.
procedure TakeNil(AMap: TRdxCodeMap; const APair: TRdxPair; var S: TRdxSpan);
var
  V, A, N, E, Last : TRdxToken;
begin
  if (APair.Kind = pkLock) or (S.BLast.Low <> ';') then Exit;
  // Ein Objekt nur hinter 'X.Free' (wie bis Charge B1-FE).
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

// Der Lauf von A nach B samt Gegenproben (s. Kopf): S beginnt leer,
// ScanSpan sucht B, TakeNil nimmt ein 'X := nil;' dahinter mit, SpanReason
// prueft das gefundene Paar. '' und S oder der Grund. Bis Review Woche
// G08-08 stand die Folge in uRdxTryFixes.TryFinally; schlaegt ScanSpan
// fehl, ist S.Reason nie leer (ScanSpan setzt dann seinen Grund).
function ScanPair(AMap: TRdxCodeMap; const APair: TRdxPair;
  out S: TRdxSpan): string;
begin
  S := Default(TRdxSpan);
  S.NextBegin := BLOCK_OTHER;
  if not ScanSpan(AMap, APair, S) then
    Exit(S.Reason);
  TakeNil(AMap, APair, S);
  Result := SpanReason(AMap, APair, S);
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

end.

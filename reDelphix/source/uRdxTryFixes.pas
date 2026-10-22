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
//          muss eine lokale Variable der Routine sein (Charge B1-FE,
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
//     auch als 'System.Exit'/'System.Break'/'System.Continue' (Charge B1-FE,
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
//     auch in Huellen - Typumwandlung (auch generisch 'TList<TFoo>(X)'),
//     Klammern, 'as', ein Array-Konstruktor '[X]', beliebig tief
//     geschachtelt ('List.Add(TObject(X))', 'FCurrent := X as TFoo', seit
//     Charge B1-FE WrappedAt) - und als Element eines Array-Konstruktors im
//     Aufruf ('FList.AddRange([A, X])'; beides seit Review Woche G08-02).
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
// ('TReader.Create(X)'), an einen Aufruf anderen Namens ('Store(X)'), als
// Methodenzeiger im Argument ('Subscribe(X.Handler)') oder durch einen
// klein geschriebenen Cast ('tobject(X)' - IsCastName folgt der
// Delphi-Konvention, Review Woche G08-09: wie oft das im FPC-Korpus an
// einer Weitergabe steht, ist nicht gemessen).
// Bekannte Scheinsperre: ein else im Rumpf einer Schleife ohne begin
// ('for .. do if A then B else Continue;') beendet fuer den Lauf den Rumpf
// (HeadStep) - das Continue gilt dann als Sprung nach aussen; die Hilfe
// fehlt mit falschem Grund, ein falscher Edit entsteht nicht.
//
// SCHNITT (Review Woche G08-08): der Lauf von A nach B mit seinen Sperren,
// die Gegenproben am Bereich, die try-Bloecke um A und das Vokabular der
// Paare, Sperren und Freigaben stehen in uRdxTrySpan, die Weitergabe-Sperre
// und die lokalen Variablen der Routine um A in uRdxHandOver. Hier bleiben
// der Baustein B5 (Form, Einrueckung, Ersetzung, Puffer als Halter), die
// Paar-Finder je Regel und die Planer.

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
  uRdxHandOver,      // IsLocalVar, InlineVarOf, R_HELD
  uRdxTrySpan;       // TRdxPair, TRdxSpan, ScanPair, EnclosingReason, Sperren

const
  SPAN_TRY = 'try';
  KEY_LOCK109  = 'Lock acquired (';
  KEY_LOCK109E = ') but no enclosing';
  KEY_LOCK153  = 'leaks the lock (';
  KEY_LOCK153E = ')';
  ANY_CALL_109 = 'entercriticalsection(...)';
  // Eine Stufe der Liste darf so breit sein - sonst die Vorgabe
  // (IndentStep): eine ausgerichtete Zeile ('1: begin' und darunter weit
  // eingerueckt) ist keine Stufe.
  MAX_STEP = 4;
  R_MOVED = 'Zeile verschoben? Datei neu pruefen';
  R_BY_HAND = 'von Hand pruefen';
  // Die Freigaben von LOCK_PAIRS (uRdxTrySpan) fuer die Gruende, wie Delphi
  // sie schreibt.
  RELEASE_CAPS: array[0..3] of string = ('UnLock', 'Leave', 'Release',
    'EndWrite');
  MONITOR_TRY = 'tryenter';
  // SCA109 meldet nur diese Methoden (uLockWithoutTryFinally).
  METHODS_109: array[0..2] of string = ('enter', 'acquire', 'beginwrite');

type
  // Eine Erzeugung (CreateAt): ihr erstes Token ('X' bzw. 'var') und ':='.
  TRdxCreateSite = record
    First  : TRdxToken;
    Assign : TRdxToken;
  end;

{ ---- kleine Helfer ---- }

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

// FirstOnLine (steht T als erstes auf seiner Zeile?) steht seit Charge H5c
// in uRdxCodeMap - uRdxResultFixes hatte eine Variante.

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
  else if not CanAppendLine(AMap, APair.Semi.Line, APair.Semi.EndCol - 1) then
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
    OInd := IndentOf(L);
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
  Ind := IndentOf(L);
  Step := ListStep(AMap, APair.First, Ind);
  Text := AMap.Raw(ALine);
  First := Length(Text);
  if (First > 1) and IsLowSurrogateCh(Text[First]) then   // uRdxCodeMap
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
// derselben Liste in try/finally setzen. '' und AEdit oder der Grund. Den
// Lauf mit seinen Gegenproben (ScanPair) und die try-Bloecke um A
// (EnclosingReason) fragt es in uRdxTrySpan.
function TryFinally(AMap: TRdxCodeMap; const APair: TRdxPair;
  out AEdit: TRdxEdit): string;
var
  S : TRdxSpan;
begin
  AEdit := Default(TRdxEdit);
  Result := StartReason(AMap, APair);
  if Result <> '' then Exit;
  Result := ScanPair(AMap, APair, S);
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

unit uLockWithoutTryFinally;

// Detektor fuer Lock-Acquire ohne umschliessendes try/finally-Release.
//
// Erfasst Muster:
//
//   FLock.Enter;                ← lsError, kein try/finally
//   DoStuff;                       (Exception in DoStuff -> Lock haengt)
//   FLock.Leave;
//
// Gegenstueck (KEIN Befund):
//
//   FLock.Enter;
//   try
//     DoStuff;
//   finally
//     FLock.Leave;
//   end;
//
// Unterstuetzte Lock-APIs (kommutativ, Enter/Leave-Paar):
//   * TCriticalSection.Enter      / .Leave
//   * TCriticalSection.Acquire    / .Release
//   * TMonitor.Enter              / .Exit         (Methode am Object)
//   * EnterCriticalSection(...)   / LeaveCriticalSection(...)  (Win-API)
//   * TMultiReadExclusiveWriteSynchronizer.BeginWrite/EndWrite
//
// Erkennung lexisch (uFileTextCache + StripStringsAndComments). Pro
// .Enter-/.Acquire-/.BeginWrite-Stelle wird geprueft ob die unmittelbar
// NACHFOLGENDE Anweisung ein 'try' ist. Wenn nicht -> Finding.
//
// Bewusst lexikalisch (kein AST), weil:
//   * der Parser TMonitor.Enter o.ae. als generischen nkCall traegt
//     und das 'try'-Nachfolge-Tracking pro Method-Body schwierig ist
//   * Lexisch reicht fuer 95 % der Patterns; AST-Refinement spaeter

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TLockWithoutTryFinallyDetector = class
  public
    // UnitNode-Parameter wird ignoriert (Detektor ist lexikalisch);
    // Signatur passt zum AST-Detector-Registry-Pattern in
    // TStaticAnalyzer2.RunAllDetectors.
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CommentedOutCode, CyclomaticComplexity, DeepNesting, GroupedDeclaration, LongMethod, MultipleExit, NilComparison, RedundantBoolean, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions, System.StrUtils,
  uFileTextCache, uDetectorUtils;

// Lokale Kopie von StripFileComments (in den Lexer-Detektoren konventionell
// inline statt aus einer Library exportiert - vermeidet zyklische uses).
// Quelle: uEmptyBlock.pas und Geschwister-Detektoren.
function StripFileComments(Lines: TStringList; out LineForChar: TArray<Integer>): string;
var
  Buf            : TStringBuilder;
  i, n, j        : Integer;
  Line           : string;
  InBlk, InParen : Boolean;
  InStr          : Boolean;
  c              : Char;
  pClose         : Integer;
  Chars          : TList<Integer>;
begin
  Buf := TStringBuilder.Create;
  Chars := TList<Integer>.Create;
  try
    InBlk := False; InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      InStr := False;
      j := 1;
      n := Length(Line);
      while j <= n do
      begin
        if InBlk then
        begin
          pClose := PosEx('}', Line, j);
          if pClose = 0 then Break;
          InBlk := False;
          j := pClose + 1; Continue;
        end;
        if InParen then
        begin
          pClose := PosEx('*)', Line, j);
          if pClose = 0 then Break;
          InParen := False;
          j := pClose + 2; Continue;
        end;
        c := Line[j];
        if InStr then
        begin
          // String-INHALT durch Blanks ersetzen (Positionen erhalten,
          // damit LineFor weiterhin stimmt). Quote-Zeichen bleiben, damit
          // die String-Grenze erkennbar bleibt - aber zwischen den Quotes
          // findet keine Regex mehr ein Identifier-Token.
          if c = '''' then
          begin
            Buf.Append(c); Chars.Add(i);
            if (j < n) and (Line[j + 1] = '''') then
            begin Buf.Append(''''); Chars.Add(i); Inc(j, 2); end
            else begin InStr := False; Inc(j); end;
          end
          else
          begin
            Buf.Append(' '); Chars.Add(i);
            Inc(j);
          end;
          Continue;
        end;
        if c = '''' then
        begin Buf.Append(c); Chars.Add(i); InStr := True; Inc(j); Continue; end;
        if (c = '/') and (j < n) and (Line[j + 1] = '/') then Break;
        if c = '{' then
        begin
          pClose := PosEx('}', Line, j + 1);
          if pClose = 0 then begin InBlk := True; Break; end;
          j := pClose + 1; Continue;
        end;
        if (c = '(') and (j < n) and (Line[j + 1] = '*') then
        begin
          pClose := PosEx('*)', Line, j + 2);
          if pClose = 0 then begin InParen := True; Break; end;
          j := pClose + 2; Continue;
        end;
        Buf.Append(c); Chars.Add(i);
        Inc(j);
      end;
      Buf.Append(#10); Chars.Add(i);
    end;
    Result := Buf.ToString;
    LineForChar := Chars.ToArray;
  finally
    Chars.Free;
    Buf.Free;
  end;
end;

const
  // Regex matched Enter/Acquire/BeginWrite-Stellen:
  //   <identifier>.Enter
  //   <identifier>.Acquire
  //   <identifier>.BeginWrite
  //   EnterCriticalSection(
  // Capture-Gruppe 1 = der Lock-Identifier (zur Diagnose).
  LOCK_ENTER_PATTERN =
    '(?i)\b(?:(\w+)\.(Enter|Acquire|BeginWrite)\b|EnterCriticalSection\s*\()';

var
  // Lazy-Cache: Pattern ist konstant, kein Grund pro File neu zu kompilieren.
  CachedLockRe : TRegEx;
  CachedReInit : Boolean = False;

procedure EnsureRegexCacheBuilt;
begin
  if CachedReInit then Exit;
  CachedLockRe := TRegEx.Create(LOCK_ENTER_PATTERN);
  CachedReInit := True;
end;

function FindNextNonSpacePos(const Code: string; Start: Integer): Integer;
// Skipt Whitespace + Newlines ab Start. Liefert die Position des
// naechsten Nicht-Whitespace-Chars oder 0 wenn nur Whitespace bis EOF.
var
  i, n : Integer;
begin
  Result := 0;
  n := Length(Code);
  i := Start;
  while (i <= n) and CharInSet(Code[i], [' ', #9, #10, #13]) do Inc(i);
  if i <= n then Result := i;
end;

function IsInsideBeginXxxMethod(const Code: string; MatchPos: Integer): Boolean;
// True wenn der Match-Pos textuell innerhalb einer Methode mit Name-
// Prefix 'Begin' liegt. Solche Methoden (BeginDraw, BeginPaint,
// BeginUpdate, BeginAccess, ...) sind per Konvention Caller-paired:
// Caller wickelt try/finally um die Begin/End-Call und holt das try
// nicht in die Begin-Method.
//
// Real-World-Sweep 2026-06-13 iter 8: CEF4Delphi uCEFBrowserBitmap
// `function BeginDraw: Boolean; begin if (FSyncObj <> nil) then begin
// FSyncObj.Acquire; Result := True; end; end;` - Acquire ist nicht
// letzter Statement, aber Method-Name signalisiert das Pair-Pattern.
const
  LOOKBACK_CHARS = 2000;
var
  StartPos, p : Integer;
  Snippet : string;
  Lower   : string;
  HeaderPos, DotPos, NameStart, NameEnd : Integer;
  FullName : string;
begin
  Result := False;
  StartPos := MatchPos - LOOKBACK_CHARS;
  if StartPos < 1 then StartPos := 1;
  Snippet := Copy(Code, StartPos, MatchPos - StartPos);
  Lower := LowerCase(Snippet);
  // Rueckwaerts den letzten function/procedure-Header finden
  HeaderPos := 0;
  p := Pos('procedure ', Lower);
  while p > 0 do
  begin
    if p > HeaderPos then HeaderPos := p;
    p := PosEx('procedure ', Lower, p + 1);
  end;
  p := Pos('function ', Lower);
  while p > 0 do
  begin
    if p > HeaderPos then HeaderPos := p;
    p := PosEx('function ', Lower, p + 1);
  end;
  if HeaderPos = 0 then Exit;
  // Method-Name extrahieren: nach 'procedure '/'function ' bis '(', ';',
  // oder ':'.
  if SameText(Copy(Lower, HeaderPos, 10), 'procedure ') then
    NameStart := HeaderPos + 10
  else
    NameStart := HeaderPos + 9;
  NameEnd := NameStart;
  while (NameEnd <= Length(Lower)) and
        not CharInSet(Lower[NameEnd], ['(', ';', ':', ' ', #9, #10, #13]) do
    Inc(NameEnd);
  FullName := Copy(Lower, NameStart, NameEnd - NameStart);
  // Qualified: 'TFoo.BeginDraw' -> Name = 'begindraw'
  DotPos := LastDelimiter('.', FullName);
  if DotPos > 0 then
    FullName := Copy(FullName, DotPos + 1, MaxInt);
  Result := StartsStr('begin', FullName);
end;

function PreviousStatementIsTry(const Code: string; MatchPos: Integer): Boolean;
// True wenn das letzte Statement-Keyword (genauer: das letzte Pascal-
// Schluesselwort vor der Match-Position) `try` ist. Dann ist das Match
// der ERSTE Statement im try-Block.
//
// Real-World-Sweep 2026-06-13: CEF4Delphi uCEFChromiumCore.pas Pattern
//   try
//     FCS.Acquire;          // <-- Match
//     ...
//   finally
//     FCS.Release;
//   end;
// Detector schaute bisher nur NACH dem Acquire-Statement nach try,
// sah dort kein try. Mit diesem Check sehen wir das umschliessende
// try korrekt (Acquire ist erstes Statement im try-Block).
//
// Heuristik: rueckwaerts vom Match das letzte Wort suchen. Wenn es
// 'try' ist -> Match ist im try-Block. Sonst kein Skip - Acquire ist
// nicht direkt nach 'try' (z.B. zwischen try und Acquire steht noch
// ein anderer Statement -> echtes Risiko dass Acquire fehlt).
var
  p, WordEnd : Integer;
  Word : string;
begin
  Result := False;
  p := MatchPos - 1;
  // Skip Whitespace + Newlines rueckwaerts
  while (p >= 1) and CharInSet(Code[p], [' ', #9, #10, #13]) do Dec(p);
  if p < 1 then Exit;
  // Wenn das vorherige Zeichen ein ';' war, hatten wir ein vorheriges
  // Statement zwischen try und Match - kein Try-direkt-davor.
  if Code[p] = ';' then Exit;
  // Letztes Wort einlesen
  WordEnd := p;
  while (p >= 1) and CharInSet(Code[p],
      ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Dec(p);
  Word := LowerCase(Copy(Code, p + 1, WordEnd - p));
  Result := Word = 'try';
end;

function NextStatementIsTry(const Code: string; AfterPos: Integer): Boolean;
// True wenn der naechste Token nach AfterPos das Keyword 'try' ist
// (case-insensitive, Wortgrenze). AfterPos sollte hinter dem ';'
// von Enter; liegen.
var
  p : Integer;
begin
  Result := False;
  p := FindNextNonSpacePos(Code, AfterPos);
  if p = 0 then Exit;
  if p + 3 > Length(Code) then Exit;
  // Drei-Zeichen-Vergleich, danach Wort-Grenz-Check
  if not SameText(Copy(Code, p, 3), 'try') then Exit;
  if (p + 3 <= Length(Code)) and
     CharInSet(Code[p + 3], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
    Exit;
  Result := True;
end;

function IsLockWrapperMethodTail(const Code: string; AfterPos: Integer): Boolean;
// True wenn der naechste Token nach AfterPos das Keyword 'end' ist -
// d.h. das Enter ist die LETZTE Anweisung im Method-Body. Klassisches
// Lock-Wrapper-Pattern wo Method nur das Enter delegiert und der
// Caller das try/finally drumherum baut:
//
//   procedure TOSLock.Lock;
//   begin
//     EnterCriticalSection(CS);
//   end;
//
//   // Caller-Site:
//   FOSLock.Lock;
//   try ... finally FOSLock.Unlock; end;
//
// Ohne diese Ausnahme melden ALLE solche Wrapper SCA109 als FP - 100+
// in mORMot allein (TOSLock, TSafeLocker, TPosixLock, ...).
var
  p : Integer;
begin
  Result := False;
  p := FindNextNonSpacePos(Code, AfterPos);
  if p = 0 then Exit;
  if p + 3 > Length(Code) then Exit;
  if not SameText(Copy(Code, p, 3), 'end') then Exit;
  // Wort-Grenze nach 'end'
  if (p + 3 <= Length(Code)) and
     CharInSet(Code[p + 3], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
    Exit;
  Result := True;
end;

function IsMethodDefinitionContext(const Code: string; MatchPos: Integer): Boolean;
// True wenn die Match-Position auf einer Methoden-DEFINITION-Zeile liegt:
//   function TFoo.Acquire(...): ...
//   procedure TFoo.Acquire(...);
// Diese sind keine Lock-Aufrufe sondern Methoden-Header. Self-Test fand 4 FPs
// auf uAstFileCache/uIDEWatchMode wo der Detector den .Acquire-Header
// matched.
var
  i : Integer;
  LineStart : Integer;
  Snippet, Lower : string;
begin
  Result := False;
  // Zeilenanfang finden (zurueck bis #10 oder Code-Start).
  LineStart := MatchPos;
  while (LineStart > 1) and (Code[LineStart - 1] <> #10) do Dec(LineStart);
  // Erste Whitespace skippen.
  i := LineStart;
  while (i <= Length(Code)) and CharInSet(Code[i], [' ', #9]) do Inc(i);
  if i > Length(Code) then Exit;
  Snippet := Copy(Code, i, MatchPos - i);
  Lower := LowerCase(Snippet);
  // Header-Praefix-Pattern: 'function '/'procedure '/'class function '/...
  if Lower.StartsWith('function ')    or Lower.StartsWith('procedure ')   or
     Lower.StartsWith('constructor ') or Lower.StartsWith('destructor ')  or
     Lower.StartsWith('class function ') or Lower.StartsWith('class procedure ') or
     Lower.StartsWith('operator ') then
    Exit(True);
end;

function MatchHasArguments(const Code: string; M: TMatch): Boolean;
// True wenn das Match einem Pattern '<ident>.Acquire(arg, ...)' folgt -
// mit NICHT-LEEREN Args. Echte Lock-Acquire-Methoden (TCriticalSection,
// TMonitor.Enter) nehmen KEINE Parameter; Cache-/Pool-Acquire dagegen
// nimmt einen Key (z.B. gAstFileCache.Acquire(FileName)).
//
// Heuristik: nach dem Match das naechste Non-Space-Zeichen pruefen. Wenn
// '(' und das uebernaechste Non-Space-Zeichen NICHT ')' ist, hat der Call
// Args -> kein Lock.
// EnterCriticalSection(...) bleibt match-fest weil die Pattern-Alternation
// das '(' bereits konsumiert hat.
var
  p, q : Integer;
begin
  Result := False;
  p := M.Index + M.Length;
  while (p <= Length(Code)) and CharInSet(Code[p], [' ', #9]) do Inc(p);
  if (p > Length(Code)) or (Code[p] <> '(') then Exit;
  q := p + 1;
  while (q <= Length(Code)) and CharInSet(Code[q], [' ', #9, #10, #13]) do Inc(q);
  if q > Length(Code) then Exit;
  // Wenn direkt nach '(' eine ')' kommt, sind die Parens leer -> Lock-Form.
  if Code[q] = ')' then Exit;
  Result := True;                  // Args vorhanden -> Cache-/Pool-Call
end;

function AcquireIsExpressionNotStatement(const Code: string; M: TMatch): Boolean;
// True wenn der '<ident>.Enter/.Acquire/.BeginWrite'-Match als AUSDRUCK
// benutzt wird statt als Statement. Ein echter Lock-Acquire ist ein
// parameterloses Statement, unmittelbar mit ';' terminiert. Folgt stattdessen
// ein anderes Token (then/do/and/or/')'/','/'='/Vergleich), ist der
// Identifier KEIN Lock - z.B. ICefv8Context.Enter: Boolean ('if
// pV8Context.Enter then ...'), CEF4Delphi uJSEval. Real-World 2026-06-26.
// Die EnterCriticalSection(...)-Form ist nicht betroffen (M.Value endet '(').
var
  p : Integer;
begin
  Result := False;
  if (M.Value <> '') and (M.Value[Length(M.Value)] = '(') then Exit;
  p := M.Index + M.Length;
  while (p <= Length(Code)) and CharInSet(Code[p], [' ', #9, #10, #13]) do Inc(p);
  if p > Length(Code) then Exit;     // EOF -> nicht entscheidbar, nicht skippen
  Result := Code[p] <> ';';          // alles ausser ';' -> Ausdruck -> kein Lock
end;

function NearestBoundaryIsTry(const Code: string; MatchPos: Integer): Boolean;
// Generalisiert PreviousStatementIsTry: liefert True, wenn das naechste
// rueckwaerts gefundene STATEMENT-BOUNDARY ein 'try' ist - d.h. zwischen
// 'try' und dem Acquire liegen nur Nicht-Statement-Tokens (begin / then /
// 'if (...) then' / Identifier / Whitespace), KEIN ';' und kein Block-Ende.
// Faengt das ueber alle CEF4Delphi-Demos wiederholte Idiom:
//   try
//     if (FResizeCS <> nil) then
//       begin
//         FResizeCS.Acquire;     // <-- sicher, Release im finally
//   ...
//   finally
//     if (FResizeCS <> nil) then FResizeCS.Release;
//   end;
// Bricht (False) am ersten ';' oder an einem Block-/Statement-Keyword ab,
// damit kein fremdes try einer abgeschlossenen Anweisung gematcht wird.
// Bewusst dieselbe Heuristik-Philosophie wie PreviousStatementIsTry:
// geprueft wird nur das umschliessende try, nicht das matchende finally.
const
  LOOKBACK = 2000;
var
  p, lo, wEnd, wStart : Integer;
  w : string;
begin
  Result := False;
  lo := MatchPos - LOOKBACK;
  if lo < 1 then lo := 1;
  p := MatchPos - 1;
  while p >= lo do
  begin
    if CharInSet(Code[p], [' ', #9, #10, #13]) then begin Dec(p); Continue; end;
    if Code[p] = ';' then Exit(False);        // davor ein abgeschlossenes Statement
    if CharInSet(Code[p], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
    begin
      wEnd := p;
      while (p >= lo) and
            CharInSet(Code[p], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Dec(p);
      wStart := p + 1;
      w := LowerCase(Copy(Code, wStart, wEnd - wStart + 1));
      if w = 'try' then Exit(True);
      // Block-/Statement-Grenzen: hier endet die "nur Filler"-Strecke.
      if (w = 'end') or (w = 'except') or (w = 'finally') or (w = 'repeat') or
         (w = 'asm') or (w = 'do') or (w = 'else') then Exit(False);
      // erlaubte Zwischen-Tokens (begin/then/if/nil/and/or/not/Identifier):
      // weiter rueckwaerts.
      Continue;
    end;
    Dec(p);   // Satzzeichen/Operatoren (Teil von 'if (...)') -> ueberspringen
  end;
end;

function StatementCannotThrow(const Stmt: string): Boolean;
// Real-World-FP-Audit 2026-07-12, FP-Klasse 'exception-free-body-parens'.
// True wenn eine EINZELNE ;-getrennte Anweisung (die bereits ':=' enthaelt)
// beweisbar nicht werfen kann. Frueher lehnte LockBodyIsExceptionFree jede
// '(' und jedes '[' pauschal ab und wertete den Body als potenziell werfend.
// Aber not(x), Set-Membership 'x in [...]', reine Vergleiche und die nicht-
// werfenden Intrinsics (abs/length/ord/high/low/succ/pred/sizeof) koennen NICHT
// werfen (z.B. GetInitialized: Result := not(Terminated) and (FStatus in [...])).
// Regeln:
//   * 'raise' irgendwo -> kann werfen -> False.
//   * jede '(' muss GRUPPIERUNG sein (steht nach Operator/Keyword/':='/','/'(')
//     ODER nach einem der nicht-werfenden Intrinsic-Namen; steht sie direkt
//     nach einem anderen Bezeichner, ist es ein (potenziell werfender)
//     benutzerdefinierter Call ident(...) -> False.
//   * jede '[' muss Set-Literal / Set-Membership sein (nach 'in' oder nach
//     Operator/':='/'('); steht sie nach Bezeichner/')'/']', ist es ein Array-
//     Index (Range-Check kann werfen) -> False.
// Konservativ: im Zweifel False -> Fund BLEIBT (kein FN-Risiko).
const
  SAFE_WORDS : array[0..24] of string = (
    'not', 'abs', 'length', 'ord', 'high', 'low', 'succ', 'pred', 'sizeof',
    'and', 'or', 'xor', 'div', 'mod', 'shl', 'shr', 'in',
    'then', 'do', 'of', 'to', 'downto', 'else', 'case', 'if');
var
  low    : string;
  i, j, wStart, k : Integer;
  w      : string;
  isSafe : Boolean;
begin
  Result := False;
  low := LowerCase(Stmt);
  if Pos('raise', low) > 0 then Exit;    // enthaelt raise -> kann werfen
  // Real-World-FP-Audit 2026-07-12 (Verify-Concern): der 'as'-Cast wirft
  // EInvalidCast, der 'is'-Typtest ist harmlos - beide aber konservativ
  // ablehnen (FN = verpasstes Lock-Leak = Deadlock, teuer). Wortgrenzen via
  // \b (matcht NICHT 'has'/'this'/'basis'). '(X as Y)' -> Fund BLEIBT.
  if TRegEx.IsMatch(low, '\b(as|is)\b') then Exit;
  i := 1;
  while i <= Length(low) do
  begin
    if low[i] = '(' then
    begin
      j := i - 1;
      while (j >= 1) and CharInSet(low[j], [' ', #9, #10, #13]) do Dec(j);
      if (j >= 1) and CharInSet(low[j], ['a'..'z', '0'..'9', '_']) then
      begin
        wStart := j;
        while (wStart >= 1) and
              CharInSet(low[wStart], ['a'..'z', '0'..'9', '_']) do Dec(wStart);
        w := Copy(low, wStart + 1, j - wStart);
        isSafe := False;
        for k := 0 to High(SAFE_WORDS) do
          if w = SAFE_WORDS[k] then begin isSafe := True; Break; end;
        if not isSafe then Exit(False);  // benutzerdef. Call -> kann werfen
      end;
      // '(' nach Operator/':='/','/'(' -> Gruppierung -> unbedenklich
    end
    else if low[i] = '[' then
    begin
      j := i - 1;
      while (j >= 1) and CharInSet(low[j], [' ', #9, #10, #13]) do Dec(j);
      if (j >= 1) and CharInSet(low[j], ['a'..'z', '0'..'9', '_']) then
      begin
        wStart := j;
        while (wStart >= 1) and
              CharInSet(low[wStart], ['a'..'z', '0'..'9', '_']) do Dec(wStart);
        w := Copy(low, wStart + 1, j - wStart);
        if w <> 'in' then Exit(False);   // Array-Index -> Range-Check kann werfen
      end
      else if (j >= 1) and CharInSet(low[j], [')', ']']) then
        Exit(False);                     // indexed nach Call/Index -> kann werfen
      // '[' nach Operator/':='/'(' -> Set-/Array-Literal -> unbedenklich
    end;
    Inc(i);
  end;
  Result := True;
end;

function LockBodyIsExceptionFree(const Code: string; AfterAcquirePos: Integer): Boolean;
// True wenn zwischen dem Acquire-';' und dem naechsten Leave/Release/Exit/
// EndWrite/LeaveCriticalSection NUR reine Zuweisungen stehen: KEIN Call '(',
// kein Index '[', kein 'raise'. Dann kann zwischen Enter und Leave nichts
// werfen -> das Lock kann nicht haengen, try/finally ist nicht noetig.
// Dominante SCA109-FP-Klasse (Real-World 2026-06-28): triviale Getter/Setter
// 'Acquire; Result := FField; Release;' / 'Acquire; FField := V; Release;'
// (~12/17 der Stichproben-FPs). Konservativ: ohne Release in Reichweite wird
// NICHT geskippt; ein '['/'(' (Array-Range bzw. Call koennen werfen) verhindert
// den Skip -> praktisch null FN-Risiko.
const
  WINDOW = 600;
var
  hi, relPos : Integer;
  seg, segLow, stmt, t : string;

  function MinPos(a, b: Integer): Integer;
  begin
    if a = 0 then Result := b
    else if b = 0 then Result := a
    else if a < b then Result := a
    else Result := b;
  end;

begin
  Result := False;
  hi := AfterAcquirePos + WINDOW;
  if hi > Length(Code) then hi := Length(Code);
  if AfterAcquirePos > hi then Exit;
  seg := Copy(Code, AfterAcquirePos, hi - AfterAcquirePos + 1);
  segLow := LowerCase(seg);
  relPos := 0;
  relPos := MinPos(relPos, Pos('.leave', segLow));
  relPos := MinPos(relPos, Pos('.release', segLow));
  relPos := MinPos(relPos, Pos('.exit', segLow));
  relPos := MinPos(relPos, Pos('.endwrite', segLow));
  relPos := MinPos(relPos, Pos('leavecriticalsection', segLow));
  if relPos = 0 then Exit;                 // kein Release in Reichweite -> nicht skippen
  // Bis zum letzten ';' VOR dem Release-Token zuruecksetzen, damit der
  // Release-Receiver ('FLock' in 'FLock.Leave') nicht als dangling Token
  // (ohne ':=') faelschlich den Skip verhindert. Leer = back-to-back Enter/Leave.
  relPos := relPos - 1;
  while (relPos >= 1) and (seg[relPos] <> ';') do Dec(relPos);
  seg := Copy(seg, 1, relPos);             // Body bis einschl. letztem ';' (leer wenn keiner)
  // Jede ;-getrennte Anweisung muss eine REINE Zuweisung sein. Ein paren-loser
  // Call ('DoWork;') hat zwar kein '(', aber auch kein ':=' -> kann werfen ->
  // dann NICHT skippen (sonst FN: echtes Leak unterdrueckt).
  Result := True;
  for stmt in seg.Split([';']) do
  begin
    t := Trim(stmt);
    if t = '' then Continue;
    if Pos(':=', t) = 0 then Exit(False);  // keine Zuweisung -> evtl. (paren-loser) Call
    // Real-World-FP-Audit 2026-07-12, FP-Klasse 'exception-free-body-parens':
    // '(' / '[' nicht mehr pauschal ablehnen - not(x), Set-Membership
    // 'x in [...]', reine Vergleiche und nicht-werfende Intrinsics koennen
    // nicht werfen. StatementCannotThrow entscheidet konservativ (raise,
    // benutzerdef. Call, Array-Index -> False -> Fund bleibt).
    if not StatementCannotThrow(t) then Exit(False);
  end;
end;

function HasLeaveCriticalSectionForHandle(const SegLow, LHandle: string): Boolean;
// Real-World-FP-Audit 2026-07-12, FP-Klasse 'split-wrapper-winapi-form'.
// True wenn im (bereits lowercased) Segment ein LeaveCriticalSection(<LHandle>)
// mit demselben fuehrenden Handle-Bezeichner steht - dann liegt das Release im
// SELBEN Scope (kein Split-Wrapper, echter Enter/Leave-Kandidat -> Fund BLEIBT).
// Konservativ ueber den fuehrenden Handle-Identifier; Namespace-Praefixe wie
// 'mormot.core.os.LeaveCriticalSection' werden per Substring-Suche ignoriert.
const
  TOK = 'leavecriticalsection';
var
  p, q, hs : Integer;
begin
  Result := False;
  p := Pos(TOK, SegLow);
  while p > 0 do
  begin
    q := p + Length(TOK);
    while (q <= Length(SegLow)) and
          CharInSet(SegLow[q], [' ', #9, #10, #13]) do Inc(q);
    if (q <= Length(SegLow)) and (SegLow[q] = '(') then
    begin
      Inc(q);
      while (q <= Length(SegLow)) and
            CharInSet(SegLow[q], [' ', #9, #10, #13]) do Inc(q);
      hs := q;
      while (q <= Length(SegLow)) and
            CharInSet(SegLow[q], ['a'..'z', '0'..'9', '_']) do Inc(q);
      if Copy(SegLow, hs, q - hs) = LHandle then Exit(True);
    end;
    p := PosEx(TOK, SegLow, p + 1);
  end;
end;

function SplitLockWrapperNoReleaseInScope(const Code: string; M: TMatch): Boolean;
// Real-World-FP-Audit 2026-07-10: Split-Lock-Handoff-Wrapper-FP-Killer.
// True, wenn im SELBEN Routinen-Body NACH dem Acquire KEIN passendes Release
// (.Leave/.Release/.Unlock/.EndWrite/.LeaveCriticalSection) auf DENSELBEN
// Lock-Bezeichner existiert. Fehlt es, ist das Release absichtlich an eine
// paired Sibling-Methode (Unlock/_Release/RWUnLock/EndWrite) delegiert - der
// Method-Body ist ein reiner Handoff (FLock.Enter; Result := True; end).
// Dann gibt es gar kein Enter..Leave-Paar in EINEM Scope, das ein
// try..finally schuetzen muesste -> SCA109 ist nicht zustaendig, der Fund
// waere ein FP (dwsUtils.TThread<T>.Lock, uWorkerThread.Lock,
// uCEFComponentIdList.Lock, uCEFWorkSchedulerQueueThread.Lock, ...).
// Der Vorwaerts-Scan endet an der naechsten Routinen-Deklaration (dort
// beginnt die evtl. paired Unlock-Methode), damit deren Release NICHT
// faelschlich als in-scope zaehlt.
const
  KEYS : array[0..3] of string = ('procedure', 'function', 'constructor', 'destructor');
var
  ident, lident, seg, segLow, w, handle, lhandle : string;
  p, n, wStart, wEnd, bodyEnd, q, k : Integer;
  isHeader, hasRelease, isWinApi : Boolean;
begin
  Result := False;
  // Real-World-FP-Audit 2026-07-12, FP-Klasse 'split-wrapper-winapi-form':
  // Neben der dotted '<ident>.Enter/.Acquire/.BeginWrite'-Form wird jetzt auch
  // die WinAPI-Form EnterCriticalSection(handle) behandelt, deren Leave in einer
  // paired Geschwister-Methode steht (mORMot RWLock/RWUnLock, jcl _AddRef/_Release).
  ident := M.Value;
  isWinApi := (ident <> '') and (ident[Length(ident)] = '(');
  if isWinApi then
  begin
    // Handle aus den Klammern lesen (M.Value endet mit '(', der erste
    // Bezeichner direkt dahinter ist der Critical-Section-Handle).
    p := M.Index + M.Length;
    while (p <= Length(Code)) and CharInSet(Code[p], [' ', #9]) do Inc(p);
    q := p;
    while (q <= Length(Code)) and
          CharInSet(Code[q], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(q);
    handle := Copy(Code, p, q - p);
    if handle = '' then Exit;         // kein isolierbarer Handle -> nicht skippen
    lhandle := LowerCase(handle);
  end
  else
  begin
    // dotted Form: der Lock-Bezeichner steht vor dem '.'.
    if Pos('.', ident) = 0 then Exit;
    ident := Copy(ident, 1, Pos('.', ident) - 1);
    if ident = '' then Exit;
    lident := LowerCase(ident);
  end;
  n := Length(Code);
  // Body-Ende = naechste Routinen-Deklaration nach dem Acquire (nur am
  // Zeilenanfang, damit ein 'function'-Typ in einer var-Deklaration das
  // Fenster nicht faelschlich kappt).
  bodyEnd := n;
  p := M.Index + M.Length;
  while p <= n do
  begin
    if CharInSet(Code[p], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
    begin
      wStart := p;
      wEnd := p + 1;
      while (wEnd <= n) and
            CharInSet(Code[wEnd], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(wEnd);
      w := LowerCase(Copy(Code, wStart, wEnd - wStart));
      isHeader := False;
      for k := 0 to High(KEYS) do
        if w = KEYS[k] then begin isHeader := True; Break; end;
      if isHeader then
      begin
        q := wStart - 1;
        while (q >= 1) and CharInSet(Code[q], [' ', #9]) do Dec(q);
        if (q < 1) or (Code[q] = #10) then begin bodyEnd := wStart - 1; Break; end;
      end;
      p := wEnd;
    end
    else
      Inc(p);
  end;
  // Im Body-Fenster (ab Acquire bis Body-Ende) ein Release auf DEMSELBEN
  // Bezeichner suchen. Grosszuegig, was als Release zaehlt -> minimiert
  // FN-Risiko (echte Acquire+Release-ohne-try-Paare bleiben Fund).
  if bodyEnd < M.Index then Exit;
  seg := Copy(Code, M.Index, bodyEnd - M.Index + 1);
  segLow := LowerCase(seg);
  if isWinApi then
    // WinAPI-Split-Wrapper: kein LeaveCriticalSection(<selber Handle>) im selben
    // Routinen-Body -> Release an paired Geschwister-Methode delegiert (FP).
    hasRelease := HasLeaveCriticalSectionForHandle(segLow, lhandle)
  else
    hasRelease :=
      (Pos(lident + '.leave', segLow) > 0) or
      (Pos(lident + '.release', segLow) > 0) or
      (Pos(lident + '.unlock', segLow) > 0) or
      (Pos(lident + '.endwrite', segLow) > 0) or
      (Pos(lident + '.leavecriticalsection', segLow) > 0);
  Result := not hasRelease;
end;

class procedure TLockWithoutTryFinallyDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines     : TStringList;
  Cached    : Boolean;
  Code      : string;
  LineFor   : TArray<Integer>;
  Matches   : TMatchCollection;
  M         : TMatch;
  EndOfStmt : Integer;
  i         : Integer;
  F         : TLeakFinding;
  LineNo    : Integer;
  LockIdent : string;
begin
  EnsureRegexCacheBuilt;
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    // Strings + Kommentare durch Blanks ersetzen, damit Pattern in
    // Strings keine False-Positives produziert.
    Code := StripFileComments(Lines, LineFor);

    Matches := CachedLockRe.Matches(Code);

    for i := 0 to Matches.Count - 1 do
    begin
      M := Matches[i];
      // FP-Schutz: Match auf METHODEN-DEFINITION (function/procedure-Header)
      // ist keine Lock-Operation - skippen.
      if IsMethodDefinitionContext(Code, M.Index) then Continue;
      // FP-Schutz: Match mit echten Argumenten ist ein Cache-/Pool-Call,
      // kein Lock (TCriticalSection.Acquire / TMonitor.Enter haben keine Args).
      // 'gAstFileCache.Acquire(FileName)' -> Cache-Lookup, kein Lock.
      if MatchHasArguments(Code, M) then Continue;
      // FP-Schutz: '<ident>.Enter' als boolescher AUSDRUCK (kein Lock).
      // z.B. ICefv8Context.Enter ('if pV8Context.Enter then ...').
      if AcquireIsExpressionNotStatement(Code, M) then Continue;
      // EndOfStmt = Position direkt NACH dem Match. Wir suchen das ';'
      // bis zur naechsten Anweisung; in einer normalen Enter-Zeile
      // sieht das so aus: "FLock.Enter;" -> Match endet bei 'Enter',
      // ';' liegt direkt rechts. EnterCriticalSection(handle); muss
      // bis zur schliessenden ')' und dem ';' gescannt werden.
      EndOfStmt := M.Index + M.Length;
      // Pragmatisch: suche das naechste ';' und nehm das +1 als Start.
      while (EndOfStmt <= Length(Code)) and (Code[EndOfStmt] <> ';') do
        Inc(EndOfStmt);
      if EndOfStmt > Length(Code) then Continue;
      Inc(EndOfStmt); // hinter dem ';'

      if NextStatementIsTry(Code, EndOfStmt) then Continue;
      // Lock-Wrapper-Pattern: Enter ist letzte Anweisung im Body -
      // Caller wrapt try/finally. Beispiele in mORMot: TOSLock.Lock,
      // TSafeLocker.Lock, InitializeCriticalSectionIfNeededAndEnter.
      if IsLockWrapperMethodTail(Code, EndOfStmt) then Continue;
      // CEF4Delphi-Pattern: try VOR Acquire (Acquire ist erstes
      // Statement im try-Block). Schau das letzte Wort vor Match.
      if PreviousStatementIsTry(Code, M.Index) then Continue;
      // CEF4Delphi-Idiom: try / if (X<>nil) then / begin / X.Acquire - das
      // umschliessende try liegt hinter begin/then/Guard, nicht direkt davor.
      if NearestBoundaryIsTry(Code, M.Index) then Continue;
      // BeginXxx-Method-Name-Konvention: Caller wickelt try/finally
      // um die paired BeginXxx/EndXxx-Calls.
      if IsInsideBeginXxxMethod(Code, M.Index) then Continue;
      // Exception-freier Body (nur Zuweisungen, kein Call/Index/raise) zwischen
      // Enter und Leave -> Lock kann nicht haengen (triviale Getter/Setter).
      if LockBodyIsExceptionFree(Code, EndOfStmt) then Continue;
      // Split-Lock-Handoff-Wrapper: Acquire ohne passendes Release im selben
      // Routinen-Body -> Release ist an eine paired Sibling-Methode delegiert,
      // kein Enter..Leave-Paar in einem Scope -> SCA109 nicht zustaendig (FP).
      // Real-World-FP-Audit 2026-07-10.
      if SplitLockWrapperNoReleaseInScope(Code, M) then Continue;

      LineNo := TDetectorUtils.LineForPos(LineFor, M.Index);
      if LineNo <= 0 then LineNo := 1;

      // Lock-Identifier aus dem Match-Wert extrahieren statt Groups[1]:
      // die EnterCriticalSection-Alternation hat keine Capture-Group 1, und
      // M.Groups[1] wirft in Delphi 12 'Index ueberschreitet das Maximum'.
      LockIdent := M.Value;
      if Pos('.', LockIdent) > 0 then
        LockIdent := Copy(LockIdent, 1, Pos('.', LockIdent) - 1)
      else
        LockIdent := 'EnterCriticalSection(...)';

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(LineNo);
      F.MissingVar :=
        Format('Lock acquired (%s) but no enclosing try..finally - ' +
               'an exception between Enter and Leave/Release leaves the ' +
               'lock permanently held. Wrap in try..finally with the ' +
               'matching Leave/Release in the finally block.',
               [LockIdent]);
      F.SetKind(fkLockWithoutTryFinally);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

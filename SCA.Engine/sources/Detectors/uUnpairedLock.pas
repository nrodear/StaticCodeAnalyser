unit uUnpairedLock;

// Detektor: Lock/EnterCriticalSection ohne paired UnLock/Leave* im
// try/finally-Block.
//
// Pattern (Bug, concurrency hotspot - mORMot/RTL):
//   FLocker.Lock;
//   DoStuff;            // <-- wirft -> Lock bleibt fuer immer haengen
//   FLocker.UnLock;
//
//   EnterCriticalSection(CS);
//   DoStuff;
//   LeaveCriticalSection(CS);
//
// Korrekt:
//   FLocker.Lock;
//   try
//     DoStuff;
//   finally
//     FLocker.UnLock;
//   end;
//
//   EnterCriticalSection(CS);
//   try
//     DoStuff;
//   finally
//     LeaveCriticalSection(CS);
//   end;
//
// Folge: Exception zwischen Lock und UnLock laesst den Lock fuer immer
// gehalten - Deadlock garantiert beim naechsten Acquire-Versuch.
// mORMot benutzt diese Locking-API ueber 200x in core/os/threads, jeder
// fehlende try/finally-Wrapper ist ein Crash-Latent.
//
// Erkennung (lexisch, narrow):
//   * Strip Strings + Kommentare.
//   * Pro Methode (lexisch via "begin..end"-Klammerung waere zu komplex;
//     stattdessen file-weite Suche):
//     - Finde alle Vorkommen von `<id>.Lock;` oder `<id>.Acquire;` oder
//       `EnterCriticalSection(<id>)` oder `RTLeventWaitFor(<id>)`.
//     - In den hoechstens 200 Bytes danach: erwarte `try` (case-insensitive).
//       Das Fenster wird am Beginn der NAECHSTEN Routine abgeschnitten - ein
//       Release in einer Nachbarmethode gehoert nicht zu diesem Acquire.
//     - Fehlt das `try` UND es kommt vor `end;` ein `UnLock`/`Leave*`,
//       war es ein bare-Lock - Finding.
//   * Nur dann flaggen wenn der UnLock-Aufruf NICHT direkt vor `end;`
//     in einem finally-Block sitzt.
//
// Limitierungen:
//   * Single-File-lexisch. Keine AST-Analyse von Try-Finally-Schachtelung.
//   * Das Fenster ist routinen-lokal: ueber eine Lock/UnLock-Fassade
//     (`procedure T.Lock; begin FCS.Enter; end;` + Gegenstueck) behauptet der
//     Detektor bewusst nichts mehr - ob der AUFRUFER sein try/finally
//     schreibt, ist eine unit-uebergreifende Frage.
//   * Re-Entrant locks die bewusst ohne try/finally arbeiten (Performance-
//     Pfad) muessen via `// noinspection UnpairedLock` suppressed werden.
//
// Schweregrad: lsWarning - Concurrency-Bug.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TUnpairedLockDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions, System.StrUtils,
  uFileTextCache, uDetectorUtils;

// Position des LETZTEN Vorkommens von Needle als GANZES Wort in Hay (sonst 0).
// Hay muss lower-case sein. Verhindert Teilwort-Treffer ('retry'/'entry' fuer
// 'try', 'send'/'append' fuer 'end').
function LastWholeWord(const Hay, Needle: string): Integer;
var P, NextP, AfterIdx: Integer; BeforeOk, AfterOk: Boolean;
begin
  Result := 0;
  P := Pos(Needle, Hay);
  while P > 0 do
  begin
    BeforeOk := (P = 1) or not CharInSet(Hay[P - 1], ['a'..'z', '0'..'9', '_']);
    AfterIdx := P + Length(Needle);
    AfterOk  := (AfterIdx > Length(Hay)) or
                not CharInSet(Hay[AfterIdx], ['a'..'z', '0'..'9', '_']);
    if BeforeOk and AfterOk then Result := P;
    NextP := PosEx(Needle, Hay, P + 1);
    if NextP = 0 then Break;
    P := NextP;
  end;
end;

function IsMethodDeclOrHeaderLine(Lines: TStringList; LineNo: Integer): Boolean;
// True wenn die Quellzeile ein Methoden-Header/Deklaration ist: Klassen-Method-
// Decl ('procedure Lock;'), Interface-Forward-Decl ('procedure
// EnterCriticalSection(...); stdcall;'), Impl-Header ('procedure TFoo.Lock;')
// oder property-Getter/Setter-Klausel. Dort ist Lock/Acquire/EnterCriticalSection
// der METHODENNAME, kein Acquire-Aufruf -> der Regex matcht, ist aber keine
// Lock-Acquisition. Dominante SCA153-FP-Klasse 'declaration-not-call'
// (Real-World-FP-Audit 2026-07-10).
var
  S : string;
begin
  Result := False;
  if (Lines = nil) or (LineNo <= 0) or (LineNo > Lines.Count) then Exit;
  S := LowerCase(TrimLeft(Lines[LineNo - 1]));
  Result := S.StartsWith('procedure ')         or S.StartsWith('function ')          or
            S.StartsWith('constructor ')       or S.StartsWith('destructor ')        or
            S.StartsWith('class procedure ')   or S.StartsWith('class function ')    or
            S.StartsWith('class constructor ') or S.StartsWith('class destructor ')  or
            S.StartsWith('operator ')          or S.StartsWith('property ');
end;

function IsRoutineImplHeaderLine(Lines: TStringList; LineNo: Integer): Boolean;
// True nur fuer BENANNTE Routinen-Koepfe, die in SPALTE 1 beginnen:
// 'procedure TFoo.Lock;', 'function Bar: Integer;', 'class procedure T.X;'.
// Bewusst enger als IsMethodDeclOrHeaderLine (das bleibt unveraendert und
// traegt weiter den Decl-Guard weiter unten - nie ein neues Gate in einen
// bereits geteilten Helfer): eingerueckte Zeilen sind Klassen-Deklarationen
// oder anonyme Methoden, die duerfen das Lookahead-Fenster NICHT kappen.
const
  ROUTINE_KEYWORDS: array[0..5] of string =
    ('procedure ', 'function ', 'constructor ', 'destructor ', 'operator ',
     'property ');
var
  Raw, S : string;
  i, P   : Integer;
begin
  Result := False;
  if (Lines = nil) or (LineNo <= 0) or (LineNo > Lines.Count) then Exit;
  Raw := Lines[LineNo - 1];
  if (Raw = '') or CharInSet(Raw[1], [#9, ' ']) then Exit;
  S := LowerCase(Raw);
  if S.StartsWith('class ') then
    S := TrimLeft(Copy(S, Length('class ') + 1, MaxInt));
  for i := Low(ROUTINE_KEYWORDS) to High(ROUTINE_KEYWORDS) do
    if S.StartsWith(ROUTINE_KEYWORDS[i]) then
    begin
      // Hinter dem Schluesselwort muss ein NAME stehen - 'procedure (' ist
      // eine anonyme Methode, 'procedure;' ein Typ-Verweis.
      P := Length(ROUTINE_KEYWORDS[i]) + 1;
      while (P <= Length(S)) and (S[P] = ' ') do Inc(P);
      Result := (P <= Length(S)) and CharInSet(S[P], ['a'..'z', '_']);
      Exit;
    end;
end;

function CollectRoutineHeaderStarts(Lines: TStringList;
  const LineFor: TArray<Integer>): TArray<Integer>;
// Aufsteigende 1-basierte Zeichen-Offsets im Strip-Text, an denen eine
// Routine beginnt. LineFor ist monoton (ein Eintrag je Zeichen, Wert =
// 0-basierte Quellzeile), ein Wechsel markiert also einen Zeilenanfang.
var
  k, Cnt, Cur : Integer;
begin
  Cnt := 0;
  Cur := -1;
  SetLength(Result, Lines.Count);   // Obergrenze: hoechstens ein Kopf je Zeile
  for k := 0 to High(LineFor) do
    if LineFor[k] <> Cur then
    begin
      Cur := LineFor[k];
      if IsRoutineImplHeaderLine(Lines, Cur + 1) and (Cnt <= High(Result)) then
      begin
        Result[Cnt] := k + 1;
        Inc(Cnt);
      end;
    end;
  SetLength(Result, Cnt);
end;

function FirstHeaderAfter(const Headers: TArray<Integer>; APos: Integer): Integer;
// Kleinster Kopf-Offset echt hinter APos, 0 wenn keiner folgt (Binaersuche -
// die Liste ist per Konstruktion aufsteigend).
var
  Lo, Hi, Mid : Integer;
begin
  Result := 0;
  Lo := 0;
  Hi := High(Headers);
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if Headers[Mid] > APos then
    begin
      Result := Headers[Mid];
      Hi := Mid - 1;
    end
    else
      Lo := Mid + 1;
  end;
end;

class procedure TUnpairedLockDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
const
  LOOK_AHEAD  = 200;  // Bytes nach dem Lock-Aufruf
  LOOK_BEHIND = 200;  // Bytes vor dem Lock-Aufruf (umschliessendes try suchen)
var
  Lines    : TStringList;
  Cached   : Boolean;
  Code     : string;
  CodeLow  : string;
  LineFor  : TArray<Integer>;
  Headers  : TArray<Integer>;
  RE       : TRegEx;
  M        : TMatch;
  AfterPos : Integer;
  NextHdr  : Integer;
  WinLen   : Integer;
  Snippet  : string;
  LineNo   : Integer;
  F        : TLeakFinding;
  Detail   : string;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    // Perf (2026-07-05): P1-strip-cache - geteilter Strip via Context-Cache.
    Code := TDetectorUtils.StripStringsAndCommentsCached(
      Lines, LineFor, AContext, FileName, ' ');
    CodeLow := LowerCase(Code);
    Headers := CollectRoutineHeaderStarts(Lines, LineFor);

    // Pattern: `<id>.Lock;` oder `<id>.Acquire;` oder `EnterCriticalSection(`
    // oder mORMot's `RTLeventWaitFor(` - jeweils mit folgendem try-fehlt-Check.
    RE := TRegEx.Create(
      '(?i)\b((?:\w+\.)?(?:Lock|Acquire|EnterCriticalSection)|EnterCriticalSection)\s*[\(;]');
    for M in RE.Matches(Code) do
    begin
      AfterPos := M.Index + M.Length;
      if AfterPos > Length(Code) then Continue;

      // Snippet nach dem Lock-Aufruf (max 200 Zeichen) lowercased.
      // FP-Guard (FP-Audit Stufe 2, 2026-08-16): das Fenster endet spaetestens
      // am Beginn der naechsten Routine. Delphi-Lock-Fassaden sind 3-5 Zeilen
      // lang und stehen direkt vor ihrem Gegenstueck (`procedure T.Lock; begin
      // FCS.Enter; end;` / `procedure T.UnLock; ...`) - zusammen deutlich unter
      // 200 Zeichen. Ohne den Schnitt sieht der Detektor das Release der
      // NACHBARmethode und meldet eine Routine, die selbst gar keines enthaelt.
      // Dominante FP-Klasse (21 von 23 im 74er-Sample), deckt zugleich den
      // RAII-Fall Ctor/Dtor ab. Der Schnitt ist monoton: ein kleineres Fenster
      // kann Funde nur entfernen (UnlockPos = 0 -> Continue).
      WinLen  := LOOK_AHEAD;
      NextHdr := FirstHeaderAfter(Headers, AfterPos);
      if (NextHdr > 0) and (NextHdr - AfterPos < WinLen) then
        WinLen := NextHdr - AfterPos;
      Snippet := Copy(CodeLow, AfterPos, WinLen);
      // Wenn `try` direkt folgt (mit beliebigen Whitespace + ';' / EOL
      // dazwischen), ist es korrekt. Wir wollen NUR Pattern wo bis zum
      // naechsten `unlock`/`leavecriticalsection` kein `try` kommt.
      // Audit 2026-07-01: 'try' als GANZES WORT suchen - Substring-Pos matchte
      // 'retry'/'entry' und unterdrueckte dann echte Unpaired-Lock-Befunde
      // (False-Negative). Snippet ist lowercased. Die Unlock-Keywords bleiben
      // bewusst Substring (sollen auch 'unlocked'/'ReleaseLock' o.ae. treffen).
      var TryPos    := TDetectorUtils.FindWholeWordLower('try', Snippet);
      var UnlockPos := Pos('unlock',     Snippet);
      if UnlockPos = 0 then
        UnlockPos := Pos('leavecriticalsection', Snippet);
      if UnlockPos = 0 then
        UnlockPos := Pos('release',     Snippet);
      // Kein Folge-Unlock gefunden -> entweder uebergebener Lock-Helper
      // oder unbekanntes Pattern -> Skip (nicht flaggen).
      if UnlockPos = 0 then Continue;
      // try kommt VOR unlock -> Pattern OK
      if (TryPos > 0) and (TryPos < UnlockPos) then Continue;

      // FP-Guard (2026-06-29): das try/finally kann den Lock UMSCHLIESSEN -
      // `try` steht VOR dem Lock, nicht nur danach. Real-World-dominante FP-
      // Klasse (CEF4Delphi uCEFBrowserThread: 29/30 Funde so geschuetzt):
      //   try
      //     FCS.Acquire;          // <- hier gematcht
      //     ...
      //   finally FCS.Release; end;
      // Wenn das naechste `try` VOR dem Lock noch OFFEN ist (kein finally/
      // except/end zwischen ihm und dem Lock), liegt der Lock im try-Body.
      var BeforeStart := M.Index - LOOK_BEHIND;
      if BeforeStart < 1 then BeforeStart := 1;
      var BeforeSnippet := Copy(CodeLow, BeforeStart, M.Index - BeforeStart);
      var LastTry := LastWholeWord(BeforeSnippet, 'try');
      if LastTry > 0 then
      begin
        var Between := Copy(BeforeSnippet, LastTry + 3, MaxInt);
        if (Pos('finally', Between) = 0) and (Pos('except', Between) = 0)
           and (LastWholeWord(Between, 'end') = 0) then
          Continue;  // Lock liegt im offenen try-Body -> kein bare-Lock
      end;

      LineNo := TDetectorUtils.LineForPos(LineFor, M.Index);
      if LineNo <= 0 then LineNo := 1;

      // FP-Guard (Real-World-FP-Audit 2026-07-10): Deklarationen/Header sind
      // KEIN Acquire-Aufruf. 'procedure Lock;' (Klassen-Decl, gefolgt von
      // 'procedure UnLock;' -> sah wie bare-Lock aus), 'function Acquire(...)',
      // Interface-Forward-Decl 'procedure EnterCriticalSection(...); stdcall;',
      // Impl-Header 'procedure TFoo.Lock;' matchen den Regex, sind aber
      // Methodennamen. Dominante SCA153-FP-Klasse 'declaration-not-call'.
      if IsMethodDeclOrHeaderLine(Lines, LineNo) then Continue;

      Detail := Format(
        'Lock/Enter without surrounding try/finally - exception leaks the lock (%s)',
        [Trim(M.Groups[1].Value)]);

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(LineNo);
      F.MissingVar := Detail;
      F.SetKind(fkUnpairedLock);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

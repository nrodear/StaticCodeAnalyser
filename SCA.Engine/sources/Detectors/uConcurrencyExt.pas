unit uConcurrencyExt;

// Concurrency-Familie erweitert (SCA113-114).
//
//   * fkThreadResumeDeprecated           - TThread.Resume seit D2010
//                                          deprecated, TThread.Start nutzen
//   * fkTThreadDestroyWithoutTerminate   - FreeAndNil(MyThread) / MyThread.Free
//                                          ohne vorheriges Terminate; WaitFor;
//                                          -> Worker laeuft weiter, AV-Risiko
//                                          Gates 2026-07-31: TerminateThread-
//                                          Hardkill, positiver .Finished-Guard
//                                          und Terminated-honorierende Execute
//                                          in derselben Unit gelten als Beweis,
//                                          dass der Worker nicht mehr laeuft.
//
// Beide lexisch, weil das Pattern ohne AST-Tiefe matchbar ist und der
// Parser keine TThread-Hierarchie nachverfolgt.
//
// FP-Schutz: scannt gestrippten Code (TDetectorUtils.StripStringsAndComments)
// statt rohem Quelltext. Damit feuern weder dxgettext-msgid-Strings wie
// 'X.Free; X := nil; -> use FreeAndNil(X)' (uLocalization.pas) noch
// Code-Beispiele in Header-Kommentaren ueber das Regex-Match - String- und
// Kommentar-Inhalte werden mit '~' aufgefuellt, die Match-Position bleibt
// quellzeilen-genau via LineForChar-Array.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TConcurrencyExtDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, RedundantBoolean, TooLongLine, UnsortedUses, UnusedLocalVar, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions, System.StrUtils,
  uFileTextCache, uDetectorUtils, uTypeIndex, uRegExMatches;

const
  // Thread-Fix (2026-08-19): die frueheren unit-vars (CachedReX + Init-Flag)
  // teilten EINE kompilierte TPerlRegEx-Instanz ueber alle Threads; ein
  // paralleles Match mutierte deren Subject/Offsets. Die 3 KONSTANTEN
  // Patterns kommen jetzt pro Thread aus TRegExMatches.CachedEx;
  // [roNotEmpty] entspricht exakt dem Default des alten Ein-Arg-
  // TRegEx.Create. Die dynamischen Patterns (mit Ident-Anteil) bleiben
  // per-Call-Compile in LOKALEN TRegEx-Variablen - lokal ist thread-sicher,
  // nur GETEILTE Instanzen waren das Problem.
  RE_FUNC_HEADER =
    '(?is)\bfunction\s+[\w.]+\s*(?:\([^()]*(?:\([^()]*\)[^()]*)*\))?\s*:\s*' +
    '([A-Za-z0-9_<>,\s.]+?)\s*;';
  RE_RESUME_CALL = '(?i)\b(\w+)\.Resume\b(?!\s*\:=)';
  RE_FREE_AND_NIL = '(?i)\bFreeAndNil\s*\(\s*(\w+)\s*\)';

// Vorheriger lokaler StripFileComments hat Kommentare gestrippt, String-
// Literale aber 1:1 erhalten - das war die FP-Quelle (TDestroyWithoutTerminate
// matched 'FreeAndNil(X)' inside einer englischen Hint-msgid). Ersetzt durch
// TDetectorUtils.StripStringsAndComments, der beides strippt und die
// Char->Quellzeile-Map (LineForChar) gleich mitliefert.

class procedure TConcurrencyExtDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines        : TStringList;
  Cached       : Boolean;
  Code         : string;
  LineFor      : TArray<Integer>;
  ReDecl       : TRegEx;
  DeclMatch    : TMatch;
  Matches      : TMatchCollection;
  M            : TMatch;
  Snippet      : string;
  LookBack     : Integer;
  LineNo       : Integer;
  F            : TLeakFinding;
  HasTerminate : Boolean;
  Ident        : string;
  DeclaredType : string;
  Recv         : string;
  RecvType     : string;
  ReFuncHeader : TRegEx;
  ReResume     : TRegEx;
  ReFreeNil    : TRegEx;

  function StripGenerics(const S: string): string;
  // 'TDictionary<TThreadID, TThreadContextInfo>' -> 'TDictionary'. Ohne das
  // leakten die GENERISCHEN Typargumente das Token 'thread' in die Heuristik
  // (Real-World 2026-06-26: FMX.Skia.Canvas.GL FreeAndNil(FThreadDictionary)).
  var
    P : Integer;
  begin
    P := Pos('<', S);
    if P > 0 then Result := Copy(S, 1, P - 1) else Result := S;
    Result := Trim(Result);
  end;

  function ResolveIsThreadByBaseClass(const ATypeName: string): Boolean;
  // In-file Basisklassen-Aufloesung: folgt `<T> = class(<Parent>)` im selben
  // File (best-effort, max 8 Schritte gegen Zyklen) bis ein Parent TThread
  // ist bzw. auf 'Thread' endet. Faengt TThread-Descendants deren NAME nicht
  // auf 'Thread' endet, solange der Typ lokal deklariert ist. Liefert False
  // fuer `class` ohne Parent (= TObject) -> haelt z.B.
  // TMultiThreadProcItem=class(TObject) korrekt draussen.
  var
    Cur, Low : string;
    Re       : TRegEx;
    Mt       : TMatch;
    Steps    : Integer;
  begin
    Result := False;
    Cur := StripGenerics(ATypeName);
    Steps := 0;
    while (Cur <> '') and (Steps < 8) do
    begin
      Low := LowerCase(Cur);
      if SameText(Cur, 'TThread') or EndsStr('thread', Low) then Exit(True);
      Re := TRegEx.Create('(?i)\b' + TRegEx.Escape(Cur) +
        '\s*=\s*class\s*\(\s*([A-Za-z_][\w.]*)');
      Mt := Re.Match(Code);
      if not Mt.Success then Exit(False);    // kein Parent (oder = TObject)
      Cur := Mt.Groups[1].Value;
      Inc(Steps);
    end;
  end;

  function LooksLikeThreadType(const ATypeName: string): Boolean;
  // Heuristik: TThread-Descendants tragen per Konvention das Token 'Thread'
  // als SUFFIX (TWorkerThread, TIdHTTPThread, TBackgroundThread, ...) - das
  // ist der robuste Indikator. NUR 'enthaelt thread' war zu breit:
  // Real-World 2026-06-26 lieferte 10 FPs aus thread-BENENNENDEN Nicht-Thread-
  // Klassen (TMultiThreadProcItem=TObject, TSharedThreadNames=TObject,
  // TJclDebugThreadNotifier=TObject, TJvBaseDatasetThreadHandler=TComponent,
  // TDictionary<TThreadID,...>). Neue Regel: Typname (ohne Generic-Args)
  // endet auf 'thread' / IST TThread -> Thread; sonst nur, wenn die in-file
  // Basisklassen-Kette real bei TThread landet. Leerer Typ (unaufloesbar)
  // -> KEIN Thread (vorher konservativ gefeuert -> FFullFilesTree/FFileR-FPs).
  var
    Base, Low : string;
  begin
    Base := StripGenerics(ATypeName);
    Low := LowerCase(Base);
    if SameText(Base, 'TThread') or EndsStr('thread', Low) then
      Exit(True);
    Result := ResolveIsThreadByBaseClass(Base);
  end;

  function IsProvablyNotThread(const ATypeName: string): Boolean;
  // Track C Opt-in (Konzept_StrukturellePhase, Runde 2): Cross-Unit-Typ-Index-
  // Gegenprobe fuer den SCA114-Kandidaten. Die lexikalische Suffix-Heuristik
  // LooksLikeThreadType stuft z.B. TJvThread=class(TJvComponent) ALLEIN wegen
  // des '...thread'-Namens als Thread ein -> FP.
  // FN-SICHER (Verify-Concern Runde 2): 'IsDescendantOf(x,tthread)=False' allein
  // ist MEHRDEUTIG - die Elternkette kann bei einem out-of-scope-Vorfahren
  // abbrechen, der in Wahrheit ein TThread ist (TSyncThread=class(TCustomBase),
  // TCustomBase=class(TThread) ungescannt). Deshalb wird NUR suppressed, wenn die
  // Kette (a) NICHT ueber TThread laeuft UND (b) beweisbar einen BEKANNTEN
  // Nicht-Thread-Root erreicht (TObject/TComponent/...). Bricht sie bei einem
  // unbekannten Vorfahren ab -> kein Root erreicht -> False -> Fallback (der
  // echte Fund bleibt). IsDescendantOf matcht Roots per Parent-Name, also greift
  // das auch wenn der Root selbst (RTL) nicht im Scan-Scope deklariert ist,
  // solange eine gescannte Zwischenklasse 'class(TComponent)' etc. deklariert.
  //   * Index nil/leer / Typ unbekannt / echter TThread-Nachfahre -> False (Fallback)
  //   * NICHT-TThread UND erreicht bekannten Nicht-Thread-Root      -> True (suppress)
  //   * Kette bricht bei Unbekanntem ab (kein Root)                 -> False (Fallback)
  const
    NON_THREAD_ROOTS : array[0..4] of string = (
      'tobject', 'tcomponent', 'tpersistent', 'tinterfacedobject',
      'tinterfacedpersistent');
  var
    Idx     : TTypeIndex;
    NameLow, Root : string;
  begin
    Result := False;
    NameLow := LowerCase(StripGenerics(ATypeName));
    if NameLow = '' then Exit;
    Idx := CtxTypeIndex(AContext);
    if (Idx = nil) or Idx.IsEmpty then Exit;            // kein Index -> Fallback
    if Idx.TypeKindOf(NameLow) = tkiUnknown then Exit;  // Typ unbekannt -> Fallback
    if Idx.IsDescendantOf(NameLow, 'tthread') then Exit; // echter Thread -> Fund bleibt
    // Nur suppressen wenn die Kette einen BEKANNTEN Nicht-Thread-Root erreicht
    // (sonst koennte sie bei einem ungescannten TThread-Vorfahren abgebrochen sein).
    for Root in NON_THREAD_ROOTS do
      if Idx.IsDescendantOf(NameLow, Root) then Exit(True);
    // kein Root erreicht -> Kette unvollstaendig -> Fallback (kein FN)
  end;

  function ResolveResultType(AtPos: Integer): string;
  // 'Result' hat in Pascal keine eigene 'Result: T;'-Deklaration - der Typ
  // steht im Function-Header `function <name>(...): <Type>;`. Wir suchen
  // rueckwaerts vom FreeAndNil-Aufruf bis zum NAECHSTEN function-Header
  // und liefern dessen Return-Type. Bei nested functions zaehlt das
  // jeweils naechstgelegene Header. Liefert '' wenn nichts passt.
  const
    LOOKBACK_CHARS = 4000;  // Method-Header sind selten weiter weg
  var
    StartPos : Integer;
    Snippet  : string;
    M        : TMatch;
    Hit      : string;
  begin
    Result := '';
    StartPos := AtPos - LOOKBACK_CHARS;
    if StartPos < 1 then StartPos := 1;
    Snippet := Copy(Code, StartPos, AtPos - StartPos);
    // Erwartetes Pattern: 'function <ident>[.<ident>]*[(<params>)]: <Type>;'
    // Die Param-Liste kann verschachtelte Klammern enthalten ([^()]* reicht
    // nicht), aber fuer Method-Header reicht zwei Verschachtelungsebenen.
    // Letzter Match im Snippet = naechstgelegener Header.
    Hit := '';
    for M in ReFuncHeader.Matches(Snippet) do
      Hit := M.Groups[1].Value;
    Result := Hit;
  end;

  function IsResumeNonCallContext(AMatchIndex: Integer): Boolean;
  // FP-Gate (Real-World-FP-Audit 2026-07-10): unterdrueckt Nicht-Aufruf-
  // Kontexte von '<X>.Resume'. Deprecated TThread.Resume ist IMMER ein
  // Statement-Aufruf 'X.Resume;'. Drei sichere Nicht-Aufruf-Faelle, die nie
  // ein TThread.Resume-Aufruf sind (daher kein TP-Verlust):
  //   (a) Methoden-Header 'procedure|function <Klasse>.Resume'  (Deklaration)
  //       -> killt die 6 Deklarations-FPs (TALAnimation.Resume, ...).
  //   (b) R-Wert-Lesen 'x := <recv>.Resume' bzw. Vergleich '= <Typ>.Resume'
  //       -> Resume ist eine Prozedur ohne Rueckgabewert, kann nie r-value
  //       oder Vergleichsoperand sein (killt 'if Cmd = TEnum.Resume then').
  // AMatchIndex zeigt (1-basiert) auf das erste Zeichen des Empfaengers, da
  // das Regex mit zero-width '\b(\w+)' beginnt.
  var
    p, q : Integer;
    Tok  : string;
  begin
    Result := False;
    p := AMatchIndex - 1;
    while (p >= 1) and CharInSet(Code[p], [' ', #9, #10, #13]) do Dec(p);
    if p < 1 then Exit;
    // (b): unmittelbar davor ein '='-Ende (':=', '=', '<=', '>=') -> Read/Vergleich
    if Code[p] = '=' then Exit(True);
    // (a): vorheriges Wort-Token = 'procedure' / 'function'
    if CharInSet(Code[p], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
    begin
      q := p;
      while (q >= 1) and CharInSet(Code[q], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
        Dec(q);
      Tok := LowerCase(Copy(Code, q + 1, p - q));
      if (Tok = 'procedure') or (Tok = 'function') then Exit(True);
    end;
  end;

  function ResolveResumeReceiverType(const AIdent: string): string;
  // FP-Gate (Real-World-FP-Audit 2026-07-10): loest den deklarierten Typ des
  // Resume-Empfaengers in-file auf - '<Ident>: <Typ>' oder Konstruktor-Call
  // '<Ident> := T<Typ>.Create'. Liefert '' wenn nichts passt (dann weiter
  // melden, kein FN). Spiegelt die FreeAndNil-Typaufloesung weiter unten.
  var
    Re : TRegEx;
    Mt : TMatch;
  begin
    Result := '';
    if AIdent = '' then Exit;
    Re := TRegEx.Create(
      '(?i)\b' + AIdent + '\s*:\s*([A-Za-z0-9_<>,\s.]+?)\s*(?:;|\)|=)');
    Mt := Re.Match(Code);
    if Mt.Success then
      Result := Mt.Groups[1].Value
    else
    begin
      Re := TRegEx.Create('(?i)\b' + AIdent + '\s*:=\s*(T\w+)\s*\.\s*Create\b');
      Mt := Re.Match(Code);
      if Mt.Success then
        Result := Mt.Groups[1].Value
      else
      begin
        // Real-World-FP-Audit 2026-07-12, FP-Klasse 'wrong-type-receiver':
        // moderne Inline-Deklaration 'var X: <Typ> := <init>;' - der Typ steht
        // zwischen ':' und ':='. Der klassische Decl-Regex oben scheitert hier,
        // weil das ':' des ':=' die Terminator-Alternation (?:;|\)|=) blockt
        // (ein ':' steht vor dem '='), sodass der Typ unbekannt blieb und
        // Nicht-Thread-Empfaenger wie 'var LNewTask: NSURLSessionTask := nil'
        // bzw. 'var LProc: TProcess := ...' faelschlich als TThread gemeldet
        // wurden. Diese Variante kappt vor dem ':=' und loest den Typ auf,
        // damit NSURLSessionTask/TProcess (wie im Detektor beabsichtigt)
        // unterdrueckt werden. TP-sicher: 'var LWorker: TMyThread := ...'
        // loest weiter auf einen '...Thread'-Typ auf und feuert weiter.
        Re := TRegEx.Create(
          '(?i)\b' + AIdent + '\s*:\s*([A-Za-z0-9_<>,\s.]+?)\s*:=');
        Mt := Re.Match(Code);
        if Mt.Success then
          Result := Mt.Groups[1].Value;
      end;
    end;
  end;

  function ExecuteHonorsTerminated(const AClassName: string): Boolean;
  // FP-Gate (Real-World-Audit 2026-07-31, FP-Klasse 'thread-honoriert-
  // Terminated'): True wenn in DIESER Unit eine Implementation
  // `procedure <AClassName>.Execute` existiert, deren Rumpf `Terminated`
  // referenziert (until Terminated / while not Terminated / ThreadClosed-
  // Helper). TThread.Destroy ruft implizit Terminate + WaitFor - gefaehrlich
  // ist ein Free nur, wenn Execute das Terminated-Flag IGNORIERT. Rumpf-
  // Ende = naechster Routinen-Header an SPALTE 0 (verschachtelte Routinen
  // sind eingerueckt und schneiden den Rumpf daher nicht ab); ohne Treffer
  // bis Code-Ende bzw. 20k Zeichen Deckel.
  const
    BODY_MAX = 20000;
  var
    Mt, Nx : TMatch;
    Body   : string;
  begin
    Result := False;
    if AClassName = '' then Exit;
    Mt := TRegEx.Match(Code, '(?i)\bprocedure\s+' + TRegEx.Escape(AClassName) +
      '\s*\.\s*Execute\b');
    if not Mt.Success then Exit;
    Body := Copy(Code, Mt.Index + Mt.Length, BODY_MAX);
    // Review-Fund 2026-07-31 ('Rumpf-Ende erkennt class procedure nicht'):
    // die alte Alternation kannte nur procedure/function/constructor/
    // destructor. Ein an Spalte 0 folgendes `class procedure TX.Cleanup`
    // schnitt den Rumpf NICHT ab, das 20k-Fenster lief in die Folge-Routine
    // und deren `Terminated` stellte echte Funde still. Ergaenzt um die
    // class-Varianten, `operator` (class operator) sowie die beiden
    // Abschnitts-Keywords initialization/finalization. Frueher schneiden
    // heisst weniger Suppression - monoton unbedenklich.
    Nx := TRegEx.Match(Body,
      '(?im)^(?:(?:class\s+)?(?:procedure|function|constructor|destructor|' +
      'operator)\s|initialization\b|finalization\b)');
    if Nx.Success then Body := Copy(Body, 1, Nx.Index - 1);
    Result := TRegEx.IsMatch(Body, '(?i)\bTerminated\b');
  end;

  function ThreadHonorsTerminated(const AIdent, ATypeName: string): Boolean;
  // FP-Gate (Real-World-Audit 2026-07-31, JvTimer-Muster): sammelt die in
  // dieser Unit greifbaren Thread-Klassen des Identifiers - den deklarierten
  // Typ UND jede Klasse aus einem `<Ident> := T<Klasse>.Create`-Konstruktor-
  // Call (JvTimer haelt `FTimerThread: TThread`, instanziiert aber die lokale
  // TJvTimerThread). Honoriert eine davon Terminated, ist FreeAndNil sicher.
  // Bewusst 'irgendeine' statt 'alle': lieber ein FN als ein Error-Tier-FP.
  var
    Mt : TMatch;
  begin
    Result := False;
    if ExecuteHonorsTerminated(StripGenerics(ATypeName)) then Exit(True);
    if AIdent = '' then Exit;
    for Mt in TRegEx.Matches(Code, '(?i)\b' + TRegEx.Escape(AIdent) +
      '\s*:=\s*(T\w+)\s*\.\s*Create\b') do
      if ExecuteHonorsTerminated(Mt.Groups[1].Value) then Exit(True);
  end;

  function FinishedGuardProvesIdle(const ASnippet, AIdent: string): Boolean;
  // Review-Fund 2026-07-31 ('Gate (b) ist polaritaets-blind'): die erste
  // Fassung matchte `\bif\b[^;]{0,160}<Ident>\.(Finished|Started)` ohne jede
  // Polaritaets-Auswertung. Damit unterdrueckten `if not <X>.Finished` und
  // `if <X>.Started` den Error-Tier-Fund, obwohl beide GENAU den gemeldeten
  // Zustand beweisen (Worker laeuft noch). Nur die positive Form
  // `if <Ident>.Finished` gilt jetzt als Beweis fuer den beendeten Worker:
  //   (1) `Started` faellt komplett raus. Sicher waere allein `not
  //       <X>.Started`; im Korpus gibt es dafuer 0 Treffer, also kostet die
  //       Streichung keinen Drop und erspart eine geratene not-Erkennung.
  //   (2) Zwischen dem `if` und dem Identifier darf kein `not` stehen
  //       (tempered token) und hinter `Finished` kein `=`/`<>`-Vergleich
  //       (`if <X>.Finished = False then`).
  //   (3) Zwischen dem Guard und dem FreeAndNil (= Ende von ASnippet) darf
  //       kein `else` liegen - sonst haengt die Freigabe am NICHT-fertigen
  //       Zweig (`if <X>.Finished then Log else FreeAndNil(<X>)`).
  // [^;]{0,160} haelt die Suche wie bisher innerhalb DESSELBEN Statements.
  // Alle drei Pruefungen koennen nur Suppressionen wegnehmen, nie welche
  // hinzufuegen - die Monotonie des Inkrements bleibt gewahrt.
  var
    Mt : TMatch;
  begin
    Result := False;
    if AIdent = '' then Exit;
    for Mt in TRegEx.Matches(ASnippet,
      '(?i)\bif\b(?:(?!\bnot\b)[^;]){0,160}\b' + TRegEx.Escape(AIdent) +
      '\s*\.\s*Finished\b(?!\s*(?:=|<>))') do
      if not TRegEx.IsMatch(
           Copy(ASnippet, Mt.Index + Mt.Length, MaxInt), '(?i)\belse\b') then
        Exit(True);
  end;

  procedure Emit(K: TFindingKind; const Detail: string; AtPos: Integer);
  begin
    LineNo := TDetectorUtils.LineForPos(LineFor, AtPos);
    if LineNo <= 0 then LineNo := 1;
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := '';
    F.LineNumber := IntToStr(LineNo);
    F.MissingVar := Detail;
    F.SetKind(K);
    Results.Add(F);
  end;

begin
  ReFuncHeader := TRegExMatches.CachedEx(RE_FUNC_HEADER, [roNotEmpty]);
  ReResume     := TRegExMatches.CachedEx(RE_RESUME_CALL, [roNotEmpty]);
  ReFreeNil    := TRegExMatches.CachedEx(RE_FREE_AND_NIL, [roNotEmpty]);
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    // Perf (2026-07-05): P1-strip-cache - geteilter Strip via Context-Cache.
    Code := TDetectorUtils.StripStringsAndCommentsCached(
      Lines, LineFor, AContext, FileName);

    // 1) <ident>.Resume - aber NICHT TForm/TPanel/etc. .Resume das
    //    optisch ein VCL-Resume-Painting-Event waere. Wir matchen
    //    konservativ alles und verlassen uns auf den User-Suppress
    //    wenn das ein FP ist - der Compiler markiert echte TThread.Resume
    //    sowieso schon als deprecated.
    Matches := ReResume.Matches(Code);
    for M in Matches do
    begin
      Recv := M.Groups[1].Value;
      // FP-Gate (Real-World-FP-Audit 2026-07-10): Nicht-Aufruf-Kontexte
      // ('procedure TX.Resume'-Header, 'x := r.Resume'-Read, '= TEnum.Resume'-
      // Vergleich) sind nie ein deprecated TThread.Resume-Aufruf.
      if IsResumeNonCallContext(M.Index) then Continue;
      // FP-Gate (Real-World-FP-Audit 2026-07-10): Empfaenger-Typ in-file
      // aufloesbar UND nicht nach TThread aussehend (FMX-Animation, TTimer,
      // TProcess, NSURLSessionTask) -> unterdruecken. Unaufloesbar -> weiter
      // melden (kein FN; die echten TThread.Resume-TPs tragen 'Thread' im
      // Namen bzw. loesen auf einen '...Thread'-Typ auf).
      RecvType := ResolveResumeReceiverType(Recv);
      if (RecvType <> '') and not LooksLikeThreadType(RecvType) then Continue;
      Emit(fkThreadResumeDeprecated,
        Format('%s.Resume is deprecated since Delphi 2010 - prefer ' +
               '%s.Start or pass CreateSuspended=False to the constructor. ' +
               'Suppress per line if this is not a TThread reference: ' +
               '// noinspection ThreadResumeDeprecated',
               [Recv, Recv]),
        M.Index);
    end;

    // 2) FreeAndNil(<ident>) oder <ident>.Free auf einer Zeile, davor
    //    KEIN <ident>.Terminate (in den letzten ~10 Zeilen).
    //    LookBack-Window in Bytes (gestripte Code-Laenge); ~500 chars
    //    deckt ~10 Code-Zeilen ab.
    Matches := ReFreeNil.Matches(Code);
    for M in Matches do
    begin
      Ident := M.Groups[1].Value;

      // Type-Filter: nur weitermachen wenn der Identifier nach einem
      // TThread-Descendant aussieht. Lookups in dieser Reihenfolge:
      //   1. Spezialfall 'Result': aus Function-Header oben.
      //   2. `<Ident> : <Type>;`-Deklaration im selben File.
      //   3. `<Ident> := T<Type>.Create...` als Konstruktor-Call im selben
      //      File - faengt cross-unit deklarierte Globals (z.B.
      //      `gDfmRepoIndex` in uDfmRepoIndex.pas, instanziiert hier).
      // Wenn KEINER der drei Lookups einen Typ liefert, faellt der
      // konservative Pfad weiter (Befund + Suppress-Hinweis im Detail).
      DeclaredType := '';
      if SameText(Ident, 'Result') then
        DeclaredType := ResolveResultType(M.Index)
      else
      begin
        ReDecl := TRegEx.Create(
          '(?i)\b' + Ident + '\s*:\s*([A-Za-z0-9_<>,\s.]+?)\s*(?:;|\)|=)');
        DeclMatch := ReDecl.Match(Code);
        if DeclMatch.Success then
          DeclaredType := DeclMatch.Groups[1].Value
        else
        begin
          // Fallback: Konstruktor-Call `<Ident> := TXxx.Create...`. Faengt
          // cross-unit-deklarierte Identifier die hier nur instanziiert
          // werden - typischer Pfad fuer globale Indizes/Caches.
          ReDecl := TRegEx.Create(
            '(?i)\b' + Ident + '\s*:=\s*(T\w+)\s*\.\s*Create\b');
          DeclMatch := ReDecl.Match(Code);
          if DeclMatch.Success then
            DeclaredType := DeclMatch.Groups[1].Value;
        end;
      end;
      // Type-/Name-Filter: feuern wenn ENTWEDER der aufgeloeste Typ nach
      // TThread aussieht, ODER der Typ unaufloesbar ist UND der IDENTIFIER-
      // Name selbst den Thread-Hinweis traegt. Vermeidet FP bei
      // TObjectList/TStringList/TStream/TForm/Result (aufgeloest, kein Thread)
      // UND bei unaufloesbaren Nicht-Thread-Feldern (Real-World 2026-06-26:
      // FFullFilesTree: TFiles im Parent-Unit, `FFileR, FFileL: TFile` -
      // compound-Decl, Regex findet den Typ nicht). Cross-unit Thread-Globals
      // bleiben erfasst, solange Name oder Konstruktor-Call den Thread zeigt.
      if not (
           ((DeclaredType <> '') and LooksLikeThreadType(DeclaredType))
           or ((DeclaredType = '') and (Pos('thread', LowerCase(Ident)) > 0))
         ) then
        Continue;

      // Track C Opt-in (Konzept_StrukturellePhase, Runde 2): Cross-Unit-
      // Gegenprobe zur lexikalischen Suffix-Heuristik oben. Kennt der repo-
      // weite TTypeIndex den aufgeloesten DeclaredType und ist er beweisbar
      // KEIN TThread-Nachfahre (z.B. TJvThread=class(TJvComponent)), war das
      // ein FP -> ueberspringen. nil/leerer Index oder unbekannter Typ ->
      // kein Eingriff (bestehendes Verhalten, TP-safe). Greift nur fuer den
      // aufgeloesten Typ-Zweig; der reine Ident-Name-Fallback (DeclaredType='')
      // liefert '' -> keine Suppression.
      if IsProvablyNotThread(DeclaredType) then Continue;

      LookBack := M.Index - 500;
      if LookBack < 1 then LookBack := 1;
      Snippet := Copy(Code, LookBack, M.Index - LookBack);
      // Heuristik (V2 Audit 2026-06-07): vor dem FreeAndNil muss innerhalb
      // der LookBack-Range ENTWEDER `<Ident>.Terminate` ODER
      // `<Ident>.WaitFor` vorkommen.
      //
      // V1 forderte BEIDES strikt - das war zu aggressiv: Thread-Patterns
      // die mit endlichem Job laufen und natuerlich exit-en brauchen NUR
      // WaitFor (z.B. MVCFramework.Console.TConsoleSpinner.Hide nutzt
      // CompareExchange-Flag + WaitFor; Terminate macht hier nichts).
      // Detector hat im Realfall 17 FPs in delphimvcframework gemeldet.
      //
      // Wer beide will: jeder Pattern allein ist 'protective intent' -
      // das ist die relevante Heuristik. Echte Bugs (nackter FreeAndNil
      // ohne irgendetwas) bleiben gemeldet.
      HasTerminate :=
        (Pos(LowerCase(Ident) + '.terminate', LowerCase(Snippet)) > 0) or
        (Pos(LowerCase(Ident) + '.waitfor',   LowerCase(Snippet)) > 0);
      if HasTerminate then Continue;

      // FP-Gate (a) (Real-World-Audit 2026-07-31, FP-Klasse 'alternativer
      // Beendigungs-Nachweis'): `TerminateThread(<Ident>.Handle, 0)` im
      // LookBack-Fenster ist ein Hard-Kill des Workers - haesslich, aber der
      // gemeldete Zustand ('worker may still be running') trifft nicht zu.
      // Vorbild-FP: cnwizards CnWizUpgradeFrm finalization.
      if TRegEx.IsMatch(Snippet,
           '(?i)\bTerminateThread\s*\(\s*' + TRegEx.Escape(Ident) + '\b') then
        Continue;

      // FP-Gate (b) (Real-World-Audit 2026-07-31, gleiche FP-Klasse): das
      // FreeAndNil steht unter einem POSITIVEN `if <Ident>.Finished`-Guard -
      // der Worker ist nachweislich nicht mehr aktiv. Vorbild-FP: TES5Edit
      // xeMainForm. Polaritaets-Auswertung siehe FinishedGuardProvesIdle
      // (Review-Fund 2026-07-31: `if not <X>.Finished` / `if <X>.Started`
      // beweisen das GEGENTEIL und duerfen nicht mehr unterdruecken).
      if FinishedGuardProvesIdle(Snippet, Ident) then
        Continue;

      // FP-Gate (c) (Real-World-Audit 2026-07-31, FP-Klasse 'thread-honoriert-
      // Terminated'): die in dieser Unit definierte Thread-Klasse wertet
      // Terminated aus -> das implizite Terminate+WaitFor in TThread.Destroy
      // reicht. Vorbild-FP: jvcl JvTimer (TJvTimerThread.Execute mit
      // 'until Terminated'). Laeuft absichtlich ZULETZT (nur fuer die wenigen
      // Kandidaten, die alle billigeren Gates passiert haben).
      if ThreadHonorsTerminated(Ident, DeclaredType) then Continue;

      Emit(fkTThreadDestroyWithoutTerminate,
        Format('FreeAndNil(%s) without prior %s.Terminate + %s.WaitFor. ' +
               'If %s is a TThread descendant the worker may still be ' +
               'running -> AV / heap corruption. If it isnt a thread, ' +
               'suppress with // noinspection TThreadDestroyWithoutTerminate',
               [Ident, Ident, Ident, Ident]),
        M.Index);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

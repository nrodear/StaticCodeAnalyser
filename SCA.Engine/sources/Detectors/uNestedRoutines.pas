unit uNestedRoutines;

// Detektor fuer geschachtelte Routinen (nested procedures/functions
// innerhalb der lokalen Decl-Section einer anderen Methode).
//
// SonarDelphi-Aequivalent: communitydelphi:NestedRoutines /
// AvoidNestedRoutines. Lokale geschachtelte Routinen sind in Delphi
// syntaktisch erlaubt, machen aber Refactorings schwierig (nicht
// testbar in Isolation, schwer wiederverwendbar) und blaehen Methoden
// auf.
//
// Erkennung: NICHT AST-basiert. Der aktuelle Parser entfaltet nested
// Routinen nicht korrekt (`ParseMethodImpl` faellt beim Antreffen eines
// inneren `procedure` in die "Headless-Method"-Branch und loescht den
// Outer-Knoten). Deshalb verwenden wir einen lexikalischen Scan ueber
// die kommentbereinigte Source:
//   1. Sektion `implementation` finden - vorher gibt es nur Class-
//      Method-Deklarationen, keine Bodies, also auch keine Nestings.
//   2. Within implementation: simple State-Maschine
//        InLocalDecl=False
//        wenn Wort = procedure/function/constructor/destructor:
//          wenn InLocalDecl -> Fund
//          InLocalDecl := True
//        wenn Wort = begin -> InLocalDecl := False
//        wenn Wort = end   -> InLocalDecl := False
//
// FP-Haertung 2026-07-31 (30%-Audit, Todo_Funde_Detector_SCA102): der
// Zustandsautomat oben ist zu grob - er hielt JEDEN Routinen-KOPF fuer
// den Beginn einer lokalen Decl-Section. Gemessen am Real-World-Korpus
// (3200 Dateien) waren 92,8 % der 70411 Funde falsch. Vier Gates, alle
// rein subtraktiv (ein Fund kann nur wegfallen, nie hinzukommen, und
// die Zeilennummer ueberlebender Funde bleibt unveraendert):
//
//   A) `implementation`-Marker nur auf KOMMENTAR-/STRING-BEREINIGTEM
//      Code. Der alte Code nahm jede Zeile, die das Wort irgendwo
//      enthielt - `/// implementation of LDAP client v2` in einem
//      Doc-Kommentar schaltete die Maschine mitten in die
//      interface-Section, wo dann saemtliche Klassen-Methoden- und
//      Prototyp-Deklarationen als "nested" gemeldet wurden. Allein
//      dieses Gate: 70411 -> 27391.
//   B) RUMPF-GATE: ein Routinen-Kopf startet nur dann eine lokale
//      Decl-Section, wenn er auch wirklich einen Rumpf besitzt. Ohne
//      Rumpf sind es Deklarationen: Klassen-/Interface-/Record-Member,
//      `forward`, `external`, `abstract`, interface-Section-Prototypen.
//      Ermittelt wird das am ersten bedeutungstragenden Token NACH dem
//      Header und seinen Direktiven (siehe AnalyseRoutineHeader).
//      Zusammen mit A: 27391 -> 6741.
//   C) EINZEILER: `procedure Foo; begin ... end;` komplett auf EINER
//      Zeile hat zwar einen Rumpf, aber keine lokale Decl-Section - die
//      naechste Zeile ist wieder Unit-Ebene. Der alte Automat sah kein
//      zeilenfuehrendes `begin`/`end` und blieb haengen (PascalScript-
//      Wrapper-Units meldeten so hunderte Nachbarn). -> 6741 -> 5252.
//   D) IFDEF-ZWILLING: `{$IFDEF} procedure TFoo.Bar(A: Integer);
//      {$ELSE} procedure TFoo.Bar(A: string); {$ENDIF} begin` - beide
//      Koepfe gehoeren zu EINER Routine mit EINEM Rumpf. Da Direktiven
//      wie Kommentare gestrippt werden, sah der Automat zwei Koepfe
//      hintereinander. Gleicher (ggf. gepunkteter) Name wie der
//      umgebende Kopf => kein Fund. -> 5252 -> 5106.
//
// Rest-FP nach A-D (Sonde + Stichprobe): ~6 %, im Wesentlichen weitere
// IFDEF-Artefakte - eine Praeprozessor-Sicht haette der lexikalische
// Scan nicht. Bewusst NICHT gebaut wurde ein Vorwaerts-Scan
// "fuehrt der var-Block wirklich zu einem begin?": er brachte nur 1 %
// zusaetzlichen Drop, kostete aber belegte True Positives (ein lokales
// `strict, Valid: boolean;` bzw. ein Variant-Record mit `case` im
// var-Block liess ihn abbrechen).
//
// Rest-FN (Verifikation 2026-07-31, am Korpus GEMESSEN - der Preis der
// Gates, bewusst bezahlt): B/C nehmen dem Automaten das versehentliche
// Nachschaerfen durch rumpflose Koepfe. Das kostet ~36 echte nested
// routines, deren umschliessende Routine ueber einen Nachbarfund
// weiterhin markiert bleibt (der Hinweis geht also nicht ganz
// verloren, nur die Zweitmeldung), plus ZWEI vollstaendige Verluste:
//   * nested routine INNERHALB einer anonymen Methode - deren Kopf
//     `procedure(const E: IFoo)` hat kein abschliessendes ';', das
//     Verdikt bleibt bvNone (D2DSVGFactory.pas:400);
//   * Kopf mit Direktive OHNE abschliessendes ';' ueber den
//     Zeilenumbruch (`... : Integer; inline` + `Begin`) - die
//     Direktiven-Klausel laeuft bis zum naechsten ';' im Rumpf
//     (Alcinoe.QuickSortList.pas:838).
// Beide Klassen sind reparabel (in der Direktiven-Schleife zusaetzlich
// bei BODY_WORDS/DECLSECT_WORDS auf Tiefe 0 anhalten - das kann
// Verdikte nur von bvNone nach bvBody drehen, bleibt also Teilmenge),
// aber sie bewegen die Fundzahl nach OBEN und brauchen deshalb ein
// eigenes Inkrement mit eigenem A/B.
//
// Limitation (unveraendert): Records/Cases mit `end;` zwischen
// Routine-Header und ihrem `begin` koennen den State faelschlich
// resetten - akzeptabel weil in der Praxis sehr selten.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext,
  uDetectorUtils;   // H2445: inline-Expansion braucht iface-Sichtbarkeit

type
  TNestedRoutinesDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, DeepNesting, GroupedDeclaration, MultipleExit, NestedRoutine, TooLongLine, UnsortedUses, UnusedLocalVar, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

  // Routinen-Schluesselwoerter, die der Zeilen-Automat als Kopf wertet.
  // `class procedure`/`class function` stehen bewusst NICHT drin: der
  // Automat prueft das ERSTE Wort einer Zeile, dort steht dann `class`.
  // Das war schon vor der Haertung so und bleibt so (kein neuer Meldepfad).
  ROUT_WORDS : array[0..3] of string =
    ('procedure', 'function', 'constructor', 'destructor');

  // Erstes Token nach Header+Direktiven, das einen Rumpf BEWEIST.
  BODY_WORDS : array[0..1] of string = ('begin', 'asm');

  // Lokale Deklarations-Sektionen - ebenfalls Rumpf-Beweis (das `begin`
  // folgt dann weiter unten).
  DECLSECT_WORDS : array[0..5] of string =
    ('var', 'const', 'label', 'type', 'resourcestring', 'threadvar');

  // Direktiven, die einen Rumpf definitiv AUSSCHLIESSEN.
  NOBODY_DIRECTIVES : array[0..2] of string =
    ('forward', 'external', 'abstract');

  // Alle Routinen-Direktiven, die zwischen Header-Semikolon und Rumpf
  // stehen duerfen. Werden ueberlesen, bis das entscheidende Token kommt.
  DIRECTIVE_WORDS : array[0..32] of string = (
    'overload', 'reintroduce', 'virtual', 'dynamic', 'abstract', 'override',
    'final', 'static', 'inline', 'assembler', 'cdecl', 'pascal', 'register',
    'safecall', 'stdcall', 'varargs', 'export', 'far', 'near', 'local',
    'message', 'dispid', 'deprecated', 'experimental', 'platform', 'library',
    'forward', 'external', 'unsafe', 'winapi', 'delayed', 'name', 'index');

  // Sicherheitsnetze gegen Endlosschleifen bei kaputtem/IFDEF-zerrissenem
  // Code. In gueltigem Pascal nie erreicht.
  MAX_DIRECTIVE_STEPS = 40;
  MAX_CHAIN_LOOKAHEAD = 64;

type
  // Rumpf-Verdikt eines Routinen-Kopfes, ermittelt auf dem bereinigten Code.
  //   bvNone  - Deklaration ohne Rumpf (Klassen-Member, forward, external, ...)
  //   bvBody  - Rumpf belegt (begin/asm oder lokale Decl-Section folgt)
  //   bvChain - unmittelbar folgt ein weiterer Routinen-Kopf; das Verdikt
  //             dieses Kopfes gilt auch fuer den aktuellen. Genau so
  //             trennen sich die beiden Welten sauber:
  //               class:  A -> B -> C -> `end`   => alle bvNone
  //               nested: Outer -> Inner -> begin => alle bvBody
  TBodyVerdict = (bvNone, bvBody, bvChain);

  TRoutineHeader = record
    KeyPos   : Integer;        // 1-basierte Position des Keywords in Code
    NamePos  : Integer;        // Position direkt hinter dem Keyword
    LineIdx  : Integer;        // 0-basierte Quellzeile des Keywords
    Verdict  : TBodyVerdict;
    ChainPos : Integer;        // bei bvChain: KeyPos des Folge-Kopfes
    BodyLine : Integer;        // 0-basierte Zeile des begin/asm, -1 = unbekannt
    HasBody  : Boolean;        // aufgeloest (inkl. Ketten)
  end;
  TRoutineHeaders = TArray<TRoutineHeader>;

function ExtractFirstWord(const Line: string; out StartCol: Integer): string;
var
  i, n, wStart : Integer;
  c            : Char;
begin
  Result := '';
  StartCol := 0;
  n := Length(Line);
  i := 1;
  while (i <= n) and CharInSet(Line[i], [' ', #9]) do Inc(i);
  if i > n then Exit;
  c := Line[i];
  if c = '{' then Exit;
  if (c = '/') and (i < n) and (Line[i + 1] = '/') then Exit;
  if (c = '(') and (i < n) and (Line[i + 1] = '*') then Exit;
  if not CharInSet(c, ['A'..'Z','a'..'z','_']) then Exit;
  wStart := i;
  StartCol := wStart;
  while (i <= n) and CharInSet(Line[i], ['A'..'Z','a'..'z','0'..'9','_']) do
    Inc(i);
  Result := Copy(Line, wStart, i - wStart);
end;

function LineContainsWord(const Line, Word: string): Boolean;
var
  Lower : string;
  p     : Integer;
  function IsIdentChar(C: Char): Boolean; inline;
  begin
    // Backlog-Welle 1, 2026-07-26: Zeichenklasse zentralisiert - die
    // lokale Fassung war zeichenweise identisch zu
    // TDetectorUtils.IsIdentChar (a..z, A..Z, 0..9, _). Der Wrapper
    // bleibt, damit die Aufrufer in dieser Unit unveraendert bleiben.
    Result := TDetectorUtils.IsIdentChar(C);
  end;
begin
  Result := False;
  Lower := LowerCase(Line);
  p := Pos(Word, Lower);
  while p > 0 do
  begin
    if ((p = 1) or not IsIdentChar(Lower[p - 1])) and
       ((p + Length(Word) > Length(Lower)) or not IsIdentChar(Lower[p + Length(Word)])) then
      Exit(True);
    p := PosEx(Word, Lower, p + 1);
  end;
end;

// === Helfer auf dem bereinigten Code =====================================
// `Code` kommt aus TDetectorUtils.StripStringsAndComments: Kommentare
// (inkl. {$...}-Direktiven) sind ENTFERNT, String-Inhalte durch '~'
// ersetzt, pro Quellzeile genau ein #10. '~' ist weder Ident- noch
// Leerzeichen und wirkt damit ueberall als Token-Trenner.

function IsIdentStartCh(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_']);
end;

function SkipIdentAt(const Code: string; P: Integer): Integer;
var
  N : Integer;
begin
  N := Length(Code);
  while (P <= N) and TDetectorUtils.IsIdentChar(Code[P]) do Inc(P);
  Result := P;
end;

// Liest den Bezeichner ab P (P MUSS auf einem Ident-Startzeichen stehen),
// liefert ihn kleingeschrieben und setzt NextPos hinter das letzte Zeichen.
function CodeIdentAt(const Code: string; P: Integer;
  out NextPos: Integer): string;
begin
  NextPos := SkipIdentAt(Code, P);
  Result  := LowerCase(Copy(Code, P, NextPos - P));
end;

function SkipBlanks(const Code: string; P: Integer): Integer;
var
  N : Integer;
begin
  N := Length(Code);
  while (P <= N) and CharInSet(Code[P], [' ', #9, #10, #13]) do Inc(P);
  Result := P;
end;

function IsWordStart(const Code: string; P: Integer): Boolean;
begin
  Result := IsIdentStartCh(Code[P]) and
            ((P = 1) or not TDetectorUtils.IsIdentChar(Code[P - 1]));
end;

// Gepunkteter Routinenname ab AfterKey (Position hinter dem Keyword),
// kleingeschrieben: 'TFoo.Bar', 'TOuter.TInner.DoIt', 'Helper'.
// Nur fuer Gate D (IFDEF-Zwillinge) - deshalb LAZY aus der Hauptschleife
// aufgerufen und nicht fuer jeden der ggf. tausenden Koepfe vorab.
function ReadRoutineName(const Code: string; AfterKey: Integer): string;
var
  N, P, NextPos : Integer;
begin
  Result := '';
  N := Length(Code);
  P := SkipBlanks(Code, AfterKey);
  if (P > N) or not IsIdentStartCh(Code[P]) then Exit;
  Result := CodeIdentAt(Code, P, NextPos);
  P := NextPos;
  while True do
  begin
    P := SkipBlanks(Code, P);
    if (P > N) or (Code[P] <> '.') then Break;
    P := SkipBlanks(Code, P + 1);
    if (P > N) or not IsIdentStartCh(Code[P]) then Break;
    // Kurz-Akkumulator (<100 Zeichen) - Concat schlaegt hier den
    // TStringBuilder-Objekt-Overhead (Review-HIGH-Nachlese 2026-08-08).
    // noinspection StringConcatInLoop
    Result := Result + '.' + CodeIdentAt(Code, P, NextPos);
    P := NextPos;
  end;
end;

// Gate B: Rumpf-Verdikt eines Routinen-Kopfes.
//   1. Header-Ende = erstes ';' auf Klammertiefe 0 (traegt mehrzeilige
//      Parameterlisten mit Default-Werten).
//   2. Routinen-Direktiven ueberlesen; `forward`/`external`/`abstract`
//      beweisen sofort "kein Rumpf".
//   3. Das dann folgende Token entscheidet.
procedure AnalyseRoutineHeader(const Code: string;
  const LineFor: TArray<Integer>; AfterKey: Integer; var H: TRoutineHeader);
var
  N, i, j, Depth, D, Guard, IdStart, NextPos, EndPos : Integer;
  Id      : string;
  Scratch : string;   // eigener Puffer: Id muss den Break ueberleben
  C       : Char;
  HitRout : Boolean;
begin
  H.Verdict  := bvNone;
  H.ChainPos := 0;
  H.BodyLine := -1;
  N := Length(Code);

  Depth  := 0;
  EndPos := 0;
  i := AfterKey;
  while i <= N do
  begin
    C := Code[i];
    if (C = '(') or (C = '[') then
      Inc(Depth)
    else if (C = ')') or (C = ']') then
    begin
      if Depth > 0 then Dec(Depth);
    end
    else if (C = ';') and (Depth = 0) then
    begin
      EndPos := i;
      Break;
    end;
    Inc(i);
  end;
  if EndPos = 0 then Exit;

  i       := EndPos + 1;
  Guard   := 0;
  Id      := '';
  IdStart := 0;
  while Guard < MAX_DIRECTIVE_STEPS do
  begin
    Inc(Guard);
    i := SkipBlanks(Code, i);
    if (i > N) or not IsIdentStartCh(Code[i]) then Exit;
    IdStart := i;
    Id := CodeIdentAt(Code, i, NextPos);
    if not MatchStr(Id, DIRECTIVE_WORDS) then Break;     // entscheidendes Token
    if MatchStr(Id, NOBODY_DIRECTIVES) then Exit;        // Prototyp - kein Rumpf
    // Direktiven-Klausel bis zum naechsten ';' auf Tiefe 0 ueberlesen.
    // Faellt direkt ein Routinen-Keyword an (Direktive ohne ';'), dort
    // stehenbleiben - das ist eine Kette.
    D := 0;
    j := NextPos;
    HitRout := False;
    while j <= N do
    begin
      C := Code[j];
      if (C = '(') or (C = '[') then
        Inc(D)
      else if (C = ')') or (C = ']') then
      begin
        if D > 0 then Dec(D);
      end
      else if (C = ';') and (D = 0) then
        Break
      else if IsWordStart(Code, j) then
      begin
        Scratch := CodeIdentAt(Code, j, NextPos);
        if (D = 0) and MatchStr(Scratch, ROUT_WORDS) then
        begin
          HitRout := True;
          Break;
        end;
        j := NextPos;
        Continue;
      end;
      Inc(j);
    end;
    if HitRout then
      i := j          // steht auf dem Routinen-Keyword
    else
      i := j + 1;     // hinter das ';' (bzw. hinter das Code-Ende)
  end;
  if IdStart = 0 then Exit;

  if MatchStr(Id, BODY_WORDS) then
  begin
    H.Verdict  := bvBody;
    H.BodyLine := TDetectorUtils.LineForPos(LineFor, IdStart) - 1;
  end
  else if MatchStr(Id, ROUT_WORDS) then
  begin
    H.Verdict  := bvChain;
    H.ChainPos := IdStart;
  end
  else if MatchStr(Id, DECLSECT_WORDS) then
    H.Verdict := bvBody;   // BodyLine bleibt -1: begin folgt spaeter
end;

// Ein Durchlauf ueber den bereinigten Code: Zeile der echten
// `implementation`-Sektion (Gate A) + alle Routinen-Koepfe mit Verdikt.
procedure ScanStrippedCode(const Code: string; const LineFor: TArray<Integer>;
  out AImplLine: Integer; out AHeaders: TRoutineHeaders);
var
  N, P, NextPos, Cnt : Integer;
  Id : string;
  C  : Char;
begin
  AImplLine := 0;
  N := Length(Code);
  Cnt := 0;
  SetLength(AHeaders, 64);
  P := 1;
  while P <= N do
  begin
    C := Code[P];
    if IsIdentStartCh(C) and
       ((P = 1) or not TDetectorUtils.IsIdentChar(Code[P - 1])) then
    begin
      // Nur Kandidaten-Anfangsbuchstaben ausschreiben - spart pro Datei
      // zehntausende Copy/LowerCase-Allokationen im Hot-Path.
      if CharInSet(C, ['p','P','f','F','c','C','d','D','i','I']) then
      begin
        Id := CodeIdentAt(Code, P, NextPos);
        if (AImplLine = 0) and (Id = 'implementation') then
          AImplLine := TDetectorUtils.LineForPos(LineFor, P);
        if MatchStr(Id, ROUT_WORDS) then
        begin
          if Cnt = Length(AHeaders) then
            SetLength(AHeaders, Cnt * 2);
          AHeaders[Cnt].KeyPos  := P;
          AHeaders[Cnt].NamePos := NextPos;
          AHeaders[Cnt].LineIdx := TDetectorUtils.LineForPos(LineFor, P) - 1;
          AHeaders[Cnt].HasBody := False;
          AnalyseRoutineHeader(Code, LineFor, NextPos, AHeaders[Cnt]);
          Inc(Cnt);
        end;
      end
      else
        NextPos := SkipIdentAt(Code, P);
      P := NextPos;
      Continue;
    end;
    Inc(P);
  end;
  SetLength(AHeaders, Cnt);
end;

// Ketten (bvChain) rueckwaerts aufloesen: das Ziel liegt immer WEITER
// hinten im Code und ist damit bereits fertig bewertet.
procedure ResolveBodies(var AHeaders: TRoutineHeaders);
var
  k, j : Integer;
begin
  for k := High(AHeaders) downto Low(AHeaders) do
  begin
    if AHeaders[k].Verdict = bvBody then
      AHeaders[k].HasBody := True
    else if AHeaders[k].Verdict = bvChain then
    begin
      AHeaders[k].HasBody := False;
      // Ziel ist praktisch immer k+1; dazwischen liegen hoechstens
      // Routinen-Keywords AUS der eigenen Parameterliste
      // (`cb: procedure(X: Integer)`).
      j := k + 1;
      while (j <= High(AHeaders)) and (j - k <= MAX_CHAIN_LOOKAHEAD) and
            (AHeaders[j].KeyPos < AHeaders[k].ChainPos) do
        Inc(j);
      if (j <= High(AHeaders)) and
         (AHeaders[j].KeyPos = AHeaders[k].ChainPos) then
      begin
        AHeaders[k].HasBody  := AHeaders[j].HasBody;
        AHeaders[k].BodyLine := AHeaders[j].BodyLine;
      end;
    end
    else
      AHeaders[k].HasBody := False;
  end;
end;

class procedure TNestedRoutinesDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines     : TStringList;
  Cached    : Boolean;
  i, Col    : Integer;
  Word, L   : string;
  InImpl    : Boolean;
  InLocal   : Boolean;
  F         : TLeakFinding;
  Code      : string;
  LineFor   : TArray<Integer>;
  Heads     : TRoutineHeaders;
  HIdx      : Integer;
  ImplLine  : Integer;
  HasBody   : Boolean;
  BodyLine  : Integer;
  RName     : string;
  OuterName : string;
  Fire      : Boolean;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    // Perf: derselbe per-Scan-Cache, den ~16 weitere Detektoren schon
    // fuellen - der Strip kostet hier im Regelfall nichts extra.
    Code := TDetectorUtils.StripStringsAndCommentsCached(
      Lines, LineFor, AContext, FileName);
    ScanStrippedCode(Code, LineFor, ImplLine, Heads);
    // Gate A: ohne echte implementation-Sektion gibt es keine Bodies und
    // damit auch keine Nestings.
    if ImplLine = 0 then Exit;
    ResolveBodies(Heads);

    HIdx      := 0;
    InImpl    := False;
    InLocal   := False;
    OuterName := '';
    for i := 0 to Lines.Count - 1 do
    begin
      // Implementation-Marker erkennen (auch wenn er nicht am Zeilen-
      // anfang steht, z.B. `unit t; implementation`). Gate A: das Wort
      // muss auch im bereinigten Code stehen - ein `// ... implementation
      // ...`-Kommentar in der interface-Section zaehlt nicht mehr.
      if not InImpl then
        if (i + 1 >= ImplLine) and LineContainsWord(Lines[i], 'implementation') then
          InImpl := True;
      if not InImpl then Continue;
      Word := ExtractFirstWord(Lines[i], Col);
      if Word = '' then Continue;
      L := LowerCase(Word);
      if (L = 'procedure') or (L = 'function') or
         (L = 'constructor') or (L = 'destructor') then
      begin
        // Kopf-Datensatz dieser Zeile suchen. Die Koepfe stehen in
        // Code-Reihenfolge, die Schleife laeuft aufsteigend -> Cursor.
        // Kein Datensatz (z.B. Zeile steckt im bereinigten Code in einem
        // mehrzeiligen Kommentar) => konservativ "kein Rumpf".
        while (HIdx <= High(Heads)) and (Heads[HIdx].LineIdx < i) do Inc(HIdx);
        HasBody  := False;
        BodyLine := -1;
        RName    := '';
        if (HIdx <= High(Heads)) and (Heads[HIdx].LineIdx = i) then
        begin
          HasBody  := Heads[HIdx].HasBody;
          BodyLine := Heads[HIdx].BodyLine;
          RName    := ReadRoutineName(Code, Heads[HIdx].NamePos);
        end;

        // Gate B (HasBody) + Gate D (IFDEF-Zwilling: derselbe Name wie der
        // umgebende Kopf ist keine Verschachtelung, sondern derselbe
        // Routinenkopf in einem anderen Praeprozessor-Zweig).
        Fire := InLocal and HasBody and
                ((RName = '') or (RName <> OuterName));
        if Fire then
        begin
          F            := TLeakFinding.Create;
          F.FileName   := FileName;
          F.MethodName := '';
          F.LineNumber := IntToStr(i + 1);
          F.MissingVar := Format(
            'Nested routine declared at column %d - extract to ' +
            'unit-level to enable testing and reuse.', [Col]);
          F.SetKind(fkNestedRoutine);
          Results.Add(F);
        end;

        if HasBody then
        begin
          // Gate C: startet der Rumpf auf DIESER Zeile (Einzeiler
          // `procedure Foo; begin ... end;`), gibt es keine lokale
          // Decl-Section, in der etwas verschachtelt sein koennte.
          InLocal   := BodyLine <> i;
          OuterName := RName;
        end;
      end
      else if L = 'begin' then
        InLocal := False
      else if L = 'end' then
        InLocal := False;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

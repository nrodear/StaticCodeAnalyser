unit uRedundantJump;

// Detektor fuer redundante `Exit;`/`Continue;` direkt vor dem
// schliessenden `end;` ihres Bloecks.
//
// SonarDelphi-Aequivalent: communitydelphi:RedundantJump. Wenn `Exit`
// das letzte Statement vor `end` ist, fliegt es ohne Effekt - die
// Methode endet ja sowieso. Aequivalent fuer `Continue` am Ende eines
// Schleifenkoerpers.
//
// Erkennung: kommentbereinigtes Joinen wie in uEmptyInterface,
// dann Pattern `(Exit|Continue);` -> nur Whitespace -> `end`
// Wort. String-/Kommentar-Awareness durch das Joining.
//
// 30%-Real-World-Audit 2026-07-31 (2535 Funde, 96 % FP im Sample) - zwei
// FP-Klassen, beide unten geschlossen:
//   FP-Klasse 1 (14/24 im Sample): `Exit` innerhalb einer Schleife verlaesst
//      die Routine FRUEH; ohne das Exit liefe die Schleife weiter. Der
//      End-Chain-Walk sah nur den Ketten-Terminator und nicht, dass die
//      Kette einen Schleifenkoerper kreuzt. Neu: Rueckwaerts-Blockscan
//      (JumpInsideLoop) -> 999 der 1153 Exit-Funde fallen weg.
//   FP-Klasse 2 (9/24 im Sample): `Break` ist am Koerperende KEIN No-Op.
//      Anders als `Continue` verhindert es die naechsten Iterationen; bei
//      `while True` / `repeat ... until False` erzeugt das Befolgen des
//      Hints sogar eine Endlosschleife. `Break` wird deshalb gar nicht mehr
//      gescannt (1375 der 2535 Funde, 0 belegte TPs im Korpus - unter den
//      220 `until`-terminierten Break-Funden kein einziges
//      `repeat ... Break; until True`, der einzige Fall in dem ein Break
//      wirklich redundant waere).
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext,
  uDetectorUtils;   // H2445: inline-Expansion braucht iface-Sichtbarkeit

type
  TRedundantJumpDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LegacyInitializationSection, LongMethod, LongParamList, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

function IsIdent(C: Char): Boolean; inline;
begin
  // Backlog-Welle 1, 2026-07-26: Zeichenklasse zentralisiert - die
  // lokale Fassung war zeichenweise identisch zu
  // TDetectorUtils.IsIdentChar (a..z, A..Z, 0..9, _). Der Wrapper
  // bleibt, damit die Aufrufer in dieser Unit unveraendert bleiben.
  Result := TDetectorUtils.IsIdentChar(C);
end;

// SCHLEIFEN-GATE (30%-Audit 2026-07-31, FP-Klasse 1: 14/24 im Sample).
//
// Liegt zwischen dem Jump und dem Ende seiner Routine ein Schleifen-
// KOERPER (for/while/repeat)? Dann ist `Exit` NICHT redundant: ohne das
// Exit liefe die Schleife in die naechste Iteration statt die Routine zu
// verlassen (Suchschleifen `if Treffer then begin Result := i; Exit; end`
// sind der Massenfall - der End-Chain-Walk sieht dort nur den Terminator
// hinter der end-Kette, nicht den gekreuzten Schleifenkoerper).
//
// Verfahren: Rueckwaerts-Blockscan ab dem Jump ueber die Fassung mit
// GEBLANKTEN String-Literalen (positionsgleich zu Code, siehe AnalyzeUnit;
// sonst wuerde ein 'end' oder 'for' aus einem Literal mitzaehlen).
//   * `end`/`until`            -> Depth+1 (geschlossener Block wird uebersprungen)
//   * `begin`/`case`/`try`/`asm` -> Depth-1, bei Depth=0 UMSCHLIESSENDER Block
//   * `repeat` bei Depth=0     -> wir stehen im Rumpf einer repeat-Schleife
//   * `for`/`while` bei Depth=0 -> Schleifenkopf; zaehlt nur, solange auf
//     der aktuellen Ebene noch KEIN `;` gekreuzt wurde. Ein gekreuztes `;`
//     heisst: die einanweisige Schleife `for i := .. do DoIt;` ist bereits
//     abgeschlossen, der Jump steht DAHINTER (Korpus: 29 echte TPs haengen
//     genau an dieser Unterscheidung, u.a. SynHighlighterJSON.pas:277
//     `while .. do Inc(Run); Exit;`).
//   * Beim Kreuzen eines umschliessenden Openers wird das `;`-Flag
//     zurueckgesetzt - vor dem Opener steht ein Kopf/Statementanfang der
//     aeusseren Ebene, kein abgeschlossenes Geschwister-Statement.
//   * Routinen-/Sektions-Schluesselwort -> Routinengrenze, keine Schleife.
// Fehleinschaetzungen koennen nur unterdruecken, nie melden (MONOTONIE).
function JumpInsideLoop(const Blank: string; JumpPos: Integer): Boolean;
var
  i, s, e, pv : Integer;
  Depth       : Integer;
  SawSemi     : Boolean;
  W           : string;
begin
  Result  := False;
  Depth   := 0;
  SawSemi := False;
  i := JumpPos - 1;
  while i >= 1 do
  begin
    if Blank[i] = ';' then
    begin
      if Depth = 0 then SawSemi := True;
      Dec(i);
      Continue;
    end;
    if not IsIdent(Blank[i]) then begin Dec(i); Continue; end;
    e := i;
    s := i;
    while (s > 1) and IsIdent(Blank[s - 1]) do Dec(s);
    W := LowerCase(Copy(Blank, s, e - s + 1));
    i := s - 1;
    // Qualifizierter Bezeichner (`Ctx.End`, `&begin`) ist kein Keyword.
    pv := s - 1;
    while (pv >= 1) and CharInSet(Blank[pv], [' ', #9, #10, #13]) do Dec(pv);
    if (pv >= 1) and CharInSet(Blank[pv], ['.', '&']) then Continue;

    if (W = 'end') or (W = 'until') then
      Inc(Depth)
    else if W = 'repeat' then
    begin
      if Depth > 0 then Dec(Depth) else Exit(True);
    end
    else if (W = 'for') or (W = 'while') then
    begin
      if (Depth = 0) and not SawSemi then Exit(True);
    end
    else if (W = 'begin') or (W = 'case') or (W = 'try') or (W = 'asm') then
    begin
      if Depth > 0 then Dec(Depth) else SawSemi := False;
    end
    else if (W = 'procedure') or (W = 'function') or (W = 'constructor')
         or (W = 'destructor') or (W = 'operator')
         or (W = 'initialization') or (W = 'finalization')
         or (W = 'implementation') or (W = 'interface')
         or (W = 'unit') or (W = 'program') or (W = 'library') then
      Exit(False);                                              // Routinengrenze
  end;
end;

// Sucht Wort `Keyword;` direkt gefolgt von Whitespace und `end`.
// Blank = positionsgleiche Fassung mit geblankten String-Literalen (nur
// fuer das Schleifen-Gate), LoopGate = Gate aktiv (nur fuer `Exit`).
procedure ScanRedundantJumpKw(const Code, Lwr, Blank, Kw: string; KwLen: Integer;
  LoopGate: Boolean; LineFor: TArray<Integer>;
  Results: TObjectList<TLeakFinding>; const FileName: string);
var
  p, q, k       : Integer;
  LineNumber    : Integer;
  F             : TLeakFinding;
begin
  p := 1;
  while True do
  begin
    p := PosEx(Kw, Lwr, p);
    if p = 0 then Break;
    if (p > 1) and IsIdent(Code[p - 1]) then begin Inc(p); Continue; end;
    // Qualifizierter Methodenaufruf 'pV8Context.Exit;' ist KEIN Jump-Statement
    // (Ist-Messung 2026-07-18: CEF-V8-Context .Enter/.Exit-Paar als FP gemeldet).
    // '&Exit' (escaped ident) ebenfalls kein Keyword.
    if (p > 1) and CharInSet(Code[p - 1], ['.', '&']) then begin Inc(p); Continue; end;
    if (p + KwLen <= Length(Code)) and IsIdent(Code[p + KwLen]) then
    begin Inc(p); Continue; end;
    // Nach dem Keyword: optional whitespace, dann `;`
    q := p + KwLen;
    while (q <= Length(Code)) and CharInSet(Code[q], [' ', #9]) do Inc(q);
    if (q > Length(Code)) or (Code[q] <> ';') then begin Inc(p); Continue; end;
    Inc(q);
    // Nach `;` whitespace/newline, dann `end` Wort
    while (q <= Length(Code)) and CharInSet(Code[q], [' ', #9, #10, #13]) do
      Inc(q);
    if (q + 2 > Length(Code)) then begin Inc(p); Continue; end;
    if SameText(Copy(Code, q, 3), 'end') and
       ((q + 3 > Length(Code)) or not IsIdent(Code[q + 3])) then
    begin
      // FP-Schutz: das `end` kann ein INNERER Block-End sein (if/case/with),
      // nicht das Method-/Loop-Body-End.
      //
      // END-CHAIN-WALK (Ist-Messung 2026-07-18, ersetzt den Ein-Token-Look-Ahead):
      // Der alte Look-Ahead prueft nur EIN Token hinter dem ersten `end` - bei
      // `Exit; end; end; <mehr Code>` (Exit in if-in-for-Suchschleife, 2 Ebenen
      // tief) sah er `end` und meldete faelschlich "redundant", obwohl die
      // Prozedur/Schleife nach der end-Kette weiterlaeuft (12/15-FP-Klasse).
      // Jetzt: die GESAMTE `end[;]`-Kette konsumieren und den Token DANACH
      // pruefen. MONOTONIE-DISZIPLIN (Compile-Review 2026-07-18): die neue
      // Bedingung ist eine STRIKTE Teilmenge der alten -
      //   * Ketten-Laenge 1 (kein 2. `end`): exakt das ALTE Terminator-Set
      //     {EOF, `end.`, `until`} - Routine-Keywords hier NICHT akzeptieren
      //     (waeren NEUE Funde = nicht monoton; und `var` waere sogar ein neuer
      //     FP, weil Delphi-12-inline-`var` AUSFUEHRBARER Code ist:
      //     'Exit; end; var h := ...' -> Exit ueberspringt ihn, nicht redundant).
      //   * Ketten-Laenge >=2: ALT meldete hier IMMER (Token nach end#1 war
      //     `end`); NEU nur wenn der Ketten-Terminator EOF/`end.`/`until` oder
      //     eine Routinen-Grenze (procedure/function/...) ist. Identifier/if/
      //     else/finally/var/... heisst: ein umschliessender Block hat noch
      //     Code -> NICHT redundant (die 12/15-FP-Klasse der Ist-Messung).
      var Look := q + 3;                                          // direkt nach `end`
      var ChainOk := False;
      var ExtraEnds := 0;                                         // ends NACH dem ersten
      while True do
      begin
        // whitespace + optional `;` hinter dem konsumierten `end`
        while (Look <= Length(Code)) and CharInSet(Code[Look], [' ', #9, #10, #13]) do Inc(Look);
        if (Look <= Length(Code)) and (Code[Look] = ';') then Inc(Look);
        while (Look <= Length(Code)) and CharInSet(Code[Look], [' ', #9, #10, #13]) do Inc(Look);
        // naechstes `end` in der Kette?
        if (Look + 2 <= Length(Code)) and SameText(Copy(Code, Look, 3), 'end') and
           ((Look + 3 > Length(Code)) or not IsIdent(Code[Look + 3])) then
        begin
          Inc(Look, 3);
          Inc(ExtraEnds);
          Continue;                                               // Kette fortsetzen
        end;
        Break;                                                    // Look steht auf Terminator
      end;
      if Look > Length(Code) then
        ChainOk := True                                           // EOF
      else if Code[Look] = '.' then
        ChainOk := True                                           // `end.`
      else if SameText(Copy(Code, Look, 5), 'until') and
              ((Look + 5 > Length(Code)) or not IsIdent(Code[Look + 5])) then
        ChainOk := True                                           // repeat-Ende
      else if ExtraEnds >= 1 then
      begin
        // Nur bei Ketten-Laenge >=2 (ALT haette gemeldet): Routinen-Grenze
        // akzeptieren. var/const/type/label BEWUSST NICHT in der Liste -
        // inline-var/const sind ausfuehrbarer Code (waere FP), label/decl-
        // Sections zu mehrdeutig.
        var TermStart := Look;
        var TermEnd := TermStart;
        while (TermEnd <= Length(Code)) and IsIdent(Code[TermEnd]) do Inc(TermEnd);
        var TermWord := LowerCase(Copy(Code, TermStart, TermEnd - TermStart));
        if (TermWord = 'procedure') or (TermWord = 'function')
           or (TermWord = 'constructor') or (TermWord = 'destructor')
           or (TermWord = 'operator') or (TermWord = 'class')
           or (TermWord = 'initialization') or (TermWord = 'finalization')
           or (TermWord = 'implementation') or (TermWord = 'exports')
           or (TermWord = 'resourcestring') or (TermWord = 'threadvar') then
          ChainOk := True;
      end;
      if not ChainOk then
      begin
        // Ein umschliessender Block hat noch Code -> Jump NICHT redundant.
        Inc(p);
        Continue;
      end;
      // 30%-Audit 2026-07-31: `Exit` aus einer Schleife heraus ist eine
      // Frueh-Rueckkehr, kein No-Op (siehe JumpInsideLoop).
      if LoopGate and JumpInsideLoop(Blank, p) then
      begin
        Inc(p);
        Continue;
      end;
      k := p - 1;
      if (k >= 0) and (k < Length(LineFor)) then
        LineNumber := LineFor[k]
      else
        LineNumber := 0;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(LineNumber + 1);
      F.MissingVar := Format(
        '`%s;` directly before `end` is redundant - control flow ' +
        'already leaves the block.', [Kw]);
      F.SetKind(fkRedundantJump);
      Results.Add(F);
    end;
    p := q;
  end;
end;

class procedure TRedundantJumpDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines    : TStringList;
  Cached   : Boolean;
  Code     : string;
  Lwr      : string;
  Blank    : string;
  LineFor  : TArray<Integer>;
  BlankMap : TArray<Integer>;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    Code := TDetectorUtils.StripFileCommentsKeepStringsCached(Lines, LineFor, AContext, FileName);
    Lwr := LowerCase(Code);
    // Zweite Strip-Fassung fuer das Schleifen-Gate: gleiche Kommentar-
    // Entfernung, aber String-Literale zeichenweise durch ' ' ersetzt.
    // Beide Fassungen sind ZEICHENGLEICH lang (ScanCodeLine ersetzt 1:1,
    // KeepStrings kopiert 1:1) -> Positionen sind austauschbar. Die
    // Cached-Variante teilt sich den Context-Slot mit ~20 Detektoren, ist
    // im Scan also praktisch immer ein Cache-Treffer.
    Blank := TDetectorUtils.StripStringsAndCommentsCached(
      Lines, BlankMap, AContext, FileName, ' ');
    if Length(Blank) <> Length(Code) then
      Blank := Code;                     // defensiv: nie mit Versatz arbeiten
    ScanRedundantJumpKw(Code, Lwr, Blank, 'exit',     4, True,  LineFor, Results, FileName);
    ScanRedundantJumpKw(Code, Lwr, Blank, 'continue', 8, False, LineFor, Results, FileName);
    // `break` wird bewusst NICHT mehr gescannt - Break am Koerperende ist
    // kein No-Op (Audit 2026-07-31, FP-Klasse 2 im Kopfkommentar).
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

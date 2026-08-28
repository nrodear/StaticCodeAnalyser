unit uCaseStatementSize;

// Detektor fuer ueberlange `case ... of`-Statements.
//
// SonarDelphi-Aequivalent: communitydelphi:CaseStatementSize. Ein
// `case` mit vielen Branches verbirgt typischerweise einen Polymorphismus-
// oder Strategie-Pattern-Hint: der Code waere lesbarer wenn die N
// Faelle in Klassen / Methoden-Tabellen / Dictionary<Key, Proc>
// verteilt waeren.
//
// Schwelle: Default 10 Branches, konfigurierbar via INI
// [Detectors] MaxCaseBranches.
//
// Erkennung:
//   * Kommentbereinigtes Joinen
//   * Suche nach `case`-Wort gefolgt von `<expr> of`
//   * Zaehle die Zweig-Doppelpunkte im Rumpf: jedes ':' ausserhalb von
//     Klammern, das kein ':=' ist und auf Block-Tiefe 1 steht, ist ein
//     Branch (`<Wert>:` ebenso wie `<Wert1>, <Wert2>:`).
//   * JEDES case wird nach seiner EIGENEN Groesse beurteilt, auch ein
//     geschachteltes (siehe ABSTIEG).
//   * Bei >= Schwelle melden.
//
// Heuristik bewusst lexikalisch - ein voller Parser-State ist nicht
// noetig, eine Block-Tiefe im Zaehler aber schon (siehe K1).
//
// ---------------------------------------------------------------------
// FP-Gates und Abstieg 2026-08-28 (Commit 6efe68e, verifiziert im Lauf
// rw23). Die Herleitung mit allen Messzahlen steht in der
// Commit-Message - hier stehen nur die REGELN und die Gruende, die
// eine Entscheidung tragen. Wer die Zahlen nachrechnen will:
//   git log --grep="case-Zweige richtig zaehlen" -1
//
// K1  TIEFE-1-GATE in CountBranches. Ein `:` zaehlt nur auf Block-
//     Tiefe 1 (begin/case/try/record/asm erhoehen, end senkt). Vorher
//     addierte der Zaehler die Labels GESCHACHTELTER case auf den
//     aeusseren - Compiler.SetupCompiler.pas meldete fuer ein case mit
//     ZWEI eigenen Zweigen 55.
//     PFLICHT dabei: ein Bezeichner hinter einem Punkt erhoeht die
//     Tiefe NICHT (qualifizierte Enums wie TSymKind.Record). Ohne
//     diesen Schutz faellt ein echter Fund weg - der Punkt-Zweig von
//     IsMaskedIdent traegt also, er ist keine Vorsorge.
// K2  RECORD-VARIANTENTEIL. Folgt hinter dem ersten gezaehlten `:`
//     eine `(`, ist es eine Typdeklaration, kein Statement. Eng an
//     einem Zeichen - siehe IsRecordVariantPart.
// K6  PHANTOM-CASE aus einer nie uebersetzten {$IFNDEF}-Region, ueber
//     die Selektor-Spanne erkannt (MAX_SELECTOR_LINES).
// K3/K4/K5 (inline var, on-Handler, goto-Label im begin-Block)
//     brauchen kein eigenes Gate - sie stehen auf Tiefe >= 2 und
//     fallen mit K1 weg. Nachgemessen, nicht geglaubt.
//
// ABSTIEG - die tragende Entscheidung dieser Runde.
//   Der Scan sprang frueher mit `pCase := pEnd + 3` hinter das `end`
//   und besuchte geschachtelte case NIE. Zusammen mit K1 waere das ein
//   schlechtes Geschaeft gewesen: der aeussere Fund trug eine
//   erfundene Zahl, der innere fehlte ganz. Jetzt laeuft der Scan mit
//   `pCase := pOf + 2` IM Rumpf weiter; jedes case wird genau einmal
//   besucht und nach seiner EIGENEN Zweigzahl beurteilt. Fortschritt
//   ist garantiert, weil pOf >= pCase+4 gilt.
//
//   WARUM BEDINGUNGSLOS und nicht nur bei stummem Elter: die
//   Alternative macht die Sichtbarkeit eines case von einer FREMDEN
//   Eigenschaft abhaengig - der Groesse seines Elters. Der Beleg steht
//   in EINER Datei: cnwizards/.../uPSRuntime.pas enthaelt zweimal
//   dasselbe Konstrukt `case var1Type.BaseType of` mit je 18 Zweigen;
//   gemeldet wuerde nur das mit dem kleineren Elter. Dieselbe Datei,
//   dasselbe Konstrukt, gegenteiliges Verdikt - das ist niemandem zu
//   erklaeren.
//
//   NACH AUSSEN SICHTBAR: ein verschachteltes Konstrukt liefert jetzt
//   MEHRERE Funde statt einem. Deshalb steht das auch in der
//   Regelbeschreibung (Quelle rules/sca-rules.json).
//
// ABNAHMEBEDINGUNG - in der tragfaehigen Form:
//   KEINE Datei verliert SCA091, waehrend sie noch ein case mit >= 10
//   EIGENEN Tiefe-1-Labels enthaelt.
//   Die woertliche Fassung "0 Dateien verlieren die Regel" ist
//   konstruktionsbedingt unerreichbar und waere auch kein Ziel: wessen
//   einziger Fund eine aufaddierte Fremdlabel-Zahl war, verliert sie
//   zu Recht.
//
// KEIN DROP-PAKET, SONDERN EIN TAUSCH. Es gehen mehr falsche Funde als
//   netto Funde verschwinden - der Rest sind vorher unsichtbare innere
//   case. Wer dieses Gate an einer Drop-Zahl misst, haelt es
//   faelschlich fuer gescheitert: die Fundzahl sinkt kaum, die
//   Fundqualitaet deutlich.
//
// RESTKLASSE, gemessen und bewusst offen: ein goto-Label DIREKT im
//   case-Rumpf (ohne begin) steht auf Tiefe 1 und wird mitgezaehlt.
//   Betrifft eine Handvoll Funde, alle bleiben ueber der Schwelle -
//   kein Fehlalarm, nur eine leicht zu hohe Zahl.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext,
  uDetectorUtils;   // H2445: inline-Expansion braucht iface-Sichtbarkeit

type
  TCaseStatementSizeDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, DeepNesting, GroupedDeclaration, IfElseBegin, LegacyInitializationSection, LongMethod, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.
// CyclomaticComplexity ist BEWUSST nicht mehr in dieser Liste: CountBranches
// (vorher 22) und AnalyzeUnit (vorher 16) sind auf Unit-Ebene zerlegt, keine
// Routine liegt noch ueber 8. Bewertet nach den Regeln, die
// uCyclomaticComplexity.pas selbst dokumentiert (1 + if + case-Arm +
// Schleife + on-Handler + and/or/xor in if-Bedingungen); dasselbe Modell
// reproduziert die beiden Ausgangswerte 22 und 16 exakt.

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;
  // Konfigurierbar via INI [Detectors] MaxCaseBranches=N.
  // DetectorMaxCaseBranches in uSCAConsts wird von RepoSettings gesetzt;
  // Default 10. <=0 = Fallback auf 10.
  DEFAULT_MAX_BRANCH_FALLBACK = 10;

  // K6: Zeilenabstand zwischen `case` und dem zugehoerigen `of`. Steht da
  // eine grosse Luecke, stammt das `case`-Wort aus Prosa in einer nie
  // uebersetzten {$IFDEF}-Region und das gefundene `of` gehoert zu etwas
  // ganz anderem weiter unten.
  //
  // Kalibriert an der GEMESSENEN Verteilung ueber alle 20.228 case-Stellen
  // des Korpus mit auffindbarem `of` und `end` (K6 dabei bewusst noch NICHT
  // angewandt, sonst waere die Verteilung von ihrer eigenen Grenze
  // beschnitten). Spanne = Zeilen zwischen `case` und `of`:
  //     0 Zeilen : 20.098 Stellen      3 Zeilen :  20
  //     1 Zeile  :     53              4 Zeilen :   5
  //     2 Zeilen :     46              5 Zeilen :   2
  //     8 Zeilen :      2             90 Zeilen :   1   <- Phantom
  //   681 Zeilen :      1   <- Phantom
  // Der laengste ECHTE Selektor geht ueber 8 Zeilen: in
  // jvcl/help/tools/GenDtx/DelphiParser.pas:2706 steht ein
  // `case TokenSymbolInC([ ...8 Zeilen Array-Literal... ]) of`. Die beiden
  // Phantome liegen bei 90 und 681. Zwischen 9 und 89 ist der Korpus LEER -
  // dort gehoert die Grenze hin, und nur dort.
  //
  // Die alte Grenze 5 lag MITTEN im belegten Bereich und war nur deshalb
  // unauffaellig, weil jenes 8-Zeilen-case heute 8 Zweige hat und damit
  // ohnehin unter MaxCaseBranches bleibt. Das ist keine Kalibrierung,
  // sondern Glueck: MaxCaseBranches ist konfigurierbar, und mit
  // MaxCaseBranches=5 haette die Grenze 5 ein echtes case verworfen. 20
  // haelt 2,5-fachen Abstand zum laengsten echten Selektor und bleibt um
  // Faktor 4,5 unter dem naechsten Phantom.
  // Der Wechsel 5 -> 20 ist am Korpus ein exaktes No-Op (identische
  // beiden Werten, identische Fundmenge).
  MAX_SELECTOR_LINES = 20;

  // Woerter, die eine Block-Tiefe oeffnen. `asm` gehoert dazu: ein
  // asm-Block wird mit `end` geschlossen wie jeder andere. Neu in dieser
  // Runde, und zwar an BEIDEN Stellen - CountBranches kannte vor K1
  // ueberhaupt keine Block-Tiefe, FindMatchingEnd kannte sie ohne `asm`.
  // Wirkung getrennt gemessen: im Zaehler 12 case-Stellen mit anderer
  // Zweigzahl (siehe unten), in FindMatchingEnd 22 case-Stellen mit
  // anderem `end` (siehe dort). 0 Dateien aendern dadurch ihre Fundmenge.
  BLOCK_OPENERS : array[0..4] of string =
    ('begin', 'case', 'try', 'record', 'asm');

  SELECTOR_WHITESPACE = [' ', #9, #13, #10];

type
  // Rolle eines Wortes fuer die Block-Tiefe.
  TCaseWord = (cwOther, cwOpener, cwEnd, cwVar);

  // Laufender Zustand des Zweigzaehlers. Als Record, damit die Zerlegung
  // von CountBranches ohne verschachtelte Routinen auskommt (die verwirft
  // der Parser - das waere Metrik-Schummeln statt Zerlegung).
  TBranchScan = record
    Count      : Integer;
    FirstColon : Integer;
    Paren      : Integer;
    Depth      : Integer;
    InVarDecl  : Boolean;
  end;

function IsIdent(C: Char): Boolean; inline;
begin
  // Backlog-Welle 1, 2026-07-26: Zeichenklasse zentralisiert - die
  // lokale Fassung war zeichenweise identisch zu
  // TDetectorUtils.IsIdentChar (a..z, A..Z, 0..9, _). Der Wrapper
  // bleibt, damit die Aufrufer in dieser Unit unveraendert bleiben.
  Result := TDetectorUtils.IsIdentChar(C);
end;

// Beginnt an p ein neues Wort?
function IsWordStart(const Code: string; p: Integer): Boolean; inline;
begin
  Result := IsIdent(Code[p]) and ((p = 1) or not IsIdent(Code[p - 1]));
end;

// Ist das Wort an p durch seinen Vorgaenger als Bezeichner ausgewiesen und
// damit KEIN Blockschluesselwort? Zwei Schreibweisen kommen real vor:
//
//   (1) Qualifizierter Name. `TPythonDocSymbolType.Record:` in
//       python4delphi/Source/PythonDocs.pas:561 ist ein case-LABEL. Ohne
//       Schutz erhoeht `Record` die Tiefe und der Fund faellt von 10 auf 8
//       Zweige - er verschwindet. Der Punkt darf dabei durch Leerraum
//       getrennt stehen: `TSymKind.` am Zeilenende und `Record:` in der
//       naechsten Zeile ist dieselbe Konstruktion. Die alte Fassung sah
//       nur Code[p-1] und fiel hier um.
//   (2) &-maskierter Bezeichner. `&begin`, `&record` und `&end` sind
//       gueltige Delphi-Bezeichner. Ohne Schutz erhoehen sie die Tiefe
//       und ein 11-Zweig-case faellt auf 0 Funde.
//
// Die drei Teile tragen NICHT dieselbe Last - deshalb einzeln gemessen,
// statt sie in einem Satz zusammenzuwerfen:
//
//   * Der Punkt-Zweig TRAEGT. Ohne ihn verliert der Korpus genau EINEN
//     Fund, und zwar den oben genannten Beleg
//     python4delphi/Source/PythonDocs.pas:561 (10 Zweige). Das ist der
//     einzige Teil dieser Funktion, der heute einen Fund haelt.
//   * Die Leerraum-Erweiterung (Punkt am Zeilenende, Bezeichner in der
//     naechsten Zeile) ist am Korpus ein exaktes No-Op: identische
//     ohne, identische Fundmenge. Gemessen ist damit nur, dass sie hier
//     keine Zweigzahl bewegt - Vorsorge fuer eine Schreibweise, die die
//     Sprache erlaubt.
//     Vorsorge fuer eine Schreibweise, die die Sprache erlaubt.
//   * Der &-Zweig ist ebenfalls ein No-Op (identische Fundmenge) - aber
//     NICHT, weil es das Muster nicht gaebe: auf dem BEREINIGTEN Code
//     (StripFileCommentsKeepStrings + BlankStringLiterals, also derselbe
//     Strip, den der Detektor selbst fuehrt) stehen 86-mal `&end` in 23
//     Dateien, 12-mal `&record` und 3-mal `&begin`. Kein `&try`: der
//     einzige Rohtreffer ist der Windows-Accelerator in 'Re&try'
//     (doublecmd .../ulng.pas:442), also ein Stringliteral und kein
//     escaped identifier. Der Lexer hat fuer escaped identifier einen
//     eigenen Zweig (uLexer.pas:658). Keines der 101 Vorkommen steht
//     heute in einem case-Rumpf, wo es eine Zweigzahl verschoebe.
//     ZAEHLFALLE, hier selbst hineingetappt: die erste Fassung dieses
//     Absatzes zaehlte auf ROHEM Quelltext (66/10/3/1) und nahm dabei
//     einen String fuer Code - genau die Hausinvariante, die dieser
//     Detektor sonst ueberall einhaelt. Wer die Zahlen nachrechnet,
//     muss vorher strippen.
//
// Die beiden No-Ops sind deshalb durch Tests belegt, nicht durch eine
// Korpuszahl - eine Korpuszahl gibt es fuer sie nicht herzugeben.
function IsMaskedIdent(const Code: string; p: Integer): Boolean;
var
  q : Integer;
begin
  Result := False;
  if p <= 1 then Exit;
  if Code[p - 1] = '&' then Exit(True);
  q := p - 1;
  while (q >= 1) and CharInSet(Code[q], SELECTOR_WHITESPACE) do Dec(q);
  Result := (q >= 1) and (Code[q] = '.');
end;

function IsOpenerWord(const W: string): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := Low(BLOCK_OPENERS) to High(BLOCK_OPENERS) do
    if W = BLOCK_OPENERS[i] then Exit(True);
end;

// Klassifiziert das Wort [p .. q-1] fuer die Block-Tiefe.
function ClassifyWord(const Code: string; p, q: Integer): TCaseWord;
var
  W : string;
begin
  Result := cwOther;
  if IsMaskedIdent(Code, p) then Exit;
  W := LowerCase(Copy(Code, p, q - p));
  if IsOpenerWord(W) then
    Result := cwOpener
  else if W = 'end' then
    Result := cwEnd
  else if W = 'var' then
    Result := cwVar;
end;

function FindOfAfter(const Code: string; Start: Integer): Integer;
var
  i : Integer;
begin
  Result := 0;
  i := Start;
  while i + 1 <= Length(Code) do
  begin
    if CharInSet(Code[i], ['o','O']) and
       SameText(Copy(Code, i, 2), 'of') and
       ((i = 1) or not IsIdent(Code[i - 1])) and
       ((i + 2 > Length(Code)) or not IsIdent(Code[i + 2])) then
    begin
      Result := i;
      Exit;
    end;
    Inc(i);
  end;
end;

// Findet den schliessenden `end` eines case-Blocks ab Position Start
// (= direkt nach `of`). Liefert die Position des matching `end`, 0 wenn
// nicht gefunden.
//
// Der Bezeichner-Schutz aus ClassifyWord gilt hier DOCH - anders als frueher
// behauptet. Ab ZWEI dotted Blockwort-Labels (`TSymKind.Record:` zweimal im
// selben case) laeuft die Tiefe davon, FindMatchingEnd rennt aus der Datei
// und der Fund geht ganz verloren. Am Korpus ist der Schutz hier ein No-Op
// (Fundmenge identisch mit und ohne) - "deshalb weg" war trotzdem der
// falsche Schluss, weil das No-Op nur die Korpuslage beschreibt, nicht die
// Sprache. Es steht ein Test dafuer.
//
// `asm` zaehlt hier NEU als Oeffner - genau wie in CountBranches, das vor
// K1 gar keine Block-Tiefe kannte. (Hier stand frueher "wie in
// CountBranches schon immer"; das war falsch, neu ist es an beiden
// Stellen.) Ohne den Oeffner schliesst das `end` eines asm-Blocks im
// Zweig das case vorzeitig. Realer Fall:
// cnwizards/Source/ThirdParty/PascalScript/uPSCompiler.pas:1844 hat im
// else-Teil ein `asm int 3; end;` - ohne den Oeffner endet das case dort
// statt an seinem eigenen `end`.
// Gemessen: 22 case-Stellen im Korpus berechnen mit dem Oeffner ein
// anderes `end`, 12 davon zusaetzlich eine andere Zweigzahl - und trotzdem
// aendert keine einzige Datei ihre Fundmenge. Der Grund ist NICHT, dass nur
// Kleinkram betroffen waere: 8 der 22 sind selbst gemeldete case (die
// uPSCompiler-Klone mit je 17 Zweigen). Deren asm-Block steht hinter dem
// letzten Label, die Zweigzahl bleibt beidseitig 17, der Fund also
// beidseitig ueber der Schwelle. Die uebrigen 14 liegen bei 1 bis 4
// Zweigen. Test: AsmBlockInBranch_EndDoesNotCloseCase.
function FindMatchingEnd(const Code: string; Start: Integer): Integer;
var
  i, q, depth : Integer;
  Kind        : TCaseWord;
begin
  Result := 0;
  i := Start;
  depth := 1;
  while i <= Length(Code) do
  begin
    while (i <= Length(Code)) and not IsIdent(Code[i]) do Inc(i);
    if i > Length(Code) then Exit;
    q := i;
    while (q <= Length(Code)) and IsIdent(Code[q]) do Inc(q);
    Kind := ClassifyWord(Code, i, q);
    if Kind = cwOpener then
      Inc(depth)
    else if Kind = cwEnd then
    begin
      Dec(depth);
      if depth = 0 then Exit(i);
    end;
    i := q;
  end;
end;

// Ein ':' zaehlt nur auf Block-Tiefe 1, ausserhalb von Klammern, ausserhalb
// einer inline-var-Deklaration und wenn es kein ':=' ist.
procedure CountColon(const Code: string; p: Integer; var S: TBranchScan);
begin
  if S.Paren <> 0 then Exit;
  if S.Depth <> 1 then Exit;
  if S.InVarDecl then Exit;
  if (p + 1 <= Length(Code)) and (Code[p + 1] = '=') then Exit;
  Inc(S.Count);
  if S.FirstColon = 0 then S.FirstColon := p;
end;

// Satzzeichen mit Sonderrolle. Result = False -> Zeichen ist keins davon.
function ScanPunct(const Code: string; p: Integer; var S: TBranchScan): Boolean;
begin
  Result := True;
  case Code[p] of
    '(' : Inc(S.Paren);
    ')' : if S.Paren > 0 then Dec(S.Paren);
    // Beendet eine nackte inline-var-Deklaration im Zweig. Ein ';' in
    // Klammern gehoert zu einer Parameterliste und beendet nichts.
    ';' : if S.Paren = 0 then S.InVarDecl := False;
    ':' : CountColon(Code, p, S);
  else
    Result := False;
  end;
end;

// Liest das Wort ab p, verrechnet es mit der Block-Tiefe und liefert die
// Position dahinter.
function ScanWord(const Code: string; p: Integer; var S: TBranchScan): Integer;
var
  Kind : TCaseWord;
begin
  Result := p;
  while (Result <= Length(Code)) and IsIdent(Code[Result]) do Inc(Result);
  Kind := ClassifyWord(Code, p, Result);
  if Kind = cwOpener then
    Inc(S.Depth)
  else if Kind = cwEnd then
    Dec(S.Depth)
  // Nackte inline-var DIREKT im Zweig: `10: var A: Integer := 0;`. Die
  // steht auf Tiefe 1 und wurde bis hierher als Zweig mitgezaehlt. Ab dem
  // `var` bis zum naechsten ';' zaehlt kein ':' mehr.
  else if (Kind = cwVar) and (S.Depth = 1) and (S.Paren = 0) then
    S.InVarDecl := True;
end;

// Zaehlt die Zweige EINES case-Statements zwischen pFrom (direkt hinter
// dem `of`) und pTo (dem schliessenden `end`).
//
// FirstColon liefert die Position des ERSTEN gezaehlten ':' (0 wenn keines
// gezaehlt wurde) - K2 braucht sie, um record-Variantenteile zu erkennen.
function CountBranches(const Code: string; pFrom, pTo: Integer;
  out FirstColon: Integer): Integer;
var
  S : TBranchScan;
  p : Integer;
begin
  S.Count      := 0;
  S.FirstColon := 0;
  S.Paren      := 0;
  S.Depth      := 1;   // pFrom steht im Rumpf des eigenen case
  S.InVarDecl  := False;
  p := pFrom;
  while p < pTo do
  begin
    if ScanPunct(Code, p, S) then
      Inc(p)
    else if IsWordStart(Code, p) then
      // Hinter das Wort springen - sonst wuerde das `end` in `Legend` als
      // Blockende zaehlen.
      p := ScanWord(Code, p, S)
    else
      Inc(p);
  end;
  FirstColon := S.FirstColon;
  Result     := S.Count;
end;

// K2: `case Tag: Integer of 0: (A: X); 1: (B: Y);` ist der Variantenteil
// einer record-Deklaration, kein Statement - lexikalisch aber vom
// case-Statement nicht zu unterscheiden. Kennzeichen: hinter dem ERSTEN
// gezaehlten ':' folgt, nur durch Leerraum getrennt, eine '('. Kein
// echtes case-Statement im Korpus beginnt seinen ersten Zweig mit einem
// geklammerten Ausdruck (gemessen: 34 Treffer, jeder einzeln nachgesehen,
// ausnahmslos Variantenteile - 29 davon waren rw20-Funde und erscheinen
// als Drops, 5 sind geschachtelte, die erst der Abstieg besucht).
//
// ENGE, bewusst in Kauf genommen und hier benannt: das ist ein
// Ganz-oder-gar-nicht-Schalter an EINEM Zeichen. Steht hinter dem ersten
// gezaehlten ':' eine '(', faellt der KOMPLETTE Fund - egal wie gross das
// case ist und wie die uebrigen Zweige aussehen. `1: (Sender as
// TButton).Click;` ist gueltiges Delphi und wuerde ein beliebig grosses
// echtes case stumm schalten. Am Korpus passiert das nicht (alle 34
// Treffer sind Variantenteile), aber das ist eine Korpus-Eigenschaft,
// keine Sprach-Eigenschaft.
// Waechter dagegen ist heute ParenExprInBranch_StillReported: dort steht
// die '(' NICHT direkt hinter dem ersten ':', sondern hinter einer
// Zuweisung - der Test faellt um, sobald das Kriterium auf "irgendwo im
// Zweig steht eine Klammer" aufweicht. Was er NICHT abdeckt, ist der Fall
// oben, in dem die '(' wirklich das erste Zeichen des ersten Zweigs ist;
// gaebe es dafuer einen Beleg im Korpus, muesste das Kriterium ueber den
// Kontext des case gehen (steht es in einer type-Deklaration?) statt
// ueber ein Zeichen.
function IsRecordVariantPart(const Code: string; FirstColon: Integer): Boolean;
var
  p : Integer;
begin
  Result := False;
  if FirstColon <= 0 then Exit;
  p := FirstColon + 1;
  while (p <= Length(Code)) and CharInSet(Code[p], SELECTOR_WHITESPACE) do
    Inc(p);
  Result := (p <= Length(Code)) and (Code[p] = '(');
end;

// K6, siehe MAX_SELECTOR_LINES. Bei unklarer Position (LineFor deckt sie
// nicht ab) wird NICHT verworfen - Gates bleiben konservativ.
function SelectorTooLong(const LineFor: TArray<Integer>;
  pCase, pOf: Integer): Boolean;
begin
  // LineFor ist 0-basiert ueber Code indiziert, die Positionen 1-basiert.
  Result := False;
  if (pCase < 1) or (pCase - 1 >= Length(LineFor)) then Exit;
  if (pOf < 1) or (pOf - 1 >= Length(LineFor)) then Exit;
  Result := LineFor[pOf - 1] - LineFor[pCase - 1] > MAX_SELECTOR_LINES;
end;

// Steht an pCase ein freistehendes `case`-WORT (und nicht das Ende von
// `Lowercase` oder der Anfang von `Cases`)?
function IsFreestandingCase(const Code: string; pCase: Integer): Boolean;
begin
  Result := False;
  if (pCase > 1) and IsIdent(Code[pCase - 1]) then Exit;
  if (pCase + 4 <= Length(Code)) and IsIdent(Code[pCase + 4]) then Exit;
  Result := True;
end;

// Sucht ab pCase das naechste freistehende `case`-Wort und liefert seine
// Position in pCase zurueck. False = keins mehr.
function NextCaseWord(const Code, Lwr: string; var pCase: Integer): Boolean;
begin
  Result := False;
  while True do
  begin
    pCase := PosEx('case', Lwr, pCase);
    if pCase = 0 then Exit;
    if IsFreestandingCase(Code, pCase) then Exit(True);
    Inc(pCase);
  end;
end;

// Ermittelt zu einem case-Wort die Eckpunkte `of` und schliessendes `end`.
// False = diese Fundstelle ueberspringen (kein `of`, K6-Phantom, oder kein
// passendes `end`).
function ResolveCaseSpan(const Code: string; const LineFor: TArray<Integer>;
  pCase: Integer; out pOf, pEnd: Integer): Boolean;
begin
  Result := False;
  pEnd := 0;
  pOf := FindOfAfter(Code, pCase + 4);
  if pOf = 0 then Exit;
  if SelectorTooLong(LineFor, pCase, pOf) then Exit;
  pEnd := FindMatchingEnd(Code, pOf + 2);
  Result := pEnd <> 0;
end;

procedure AddCaseFinding(Results: TObjectList<TLeakFinding>;
  const FileName: string; const LineFor: TArray<Integer>;
  pCase, BranchCount, MaxBr: Integer);
var
  i, LineNumber : Integer;
  F             : TLeakFinding;
begin
  i := pCase - 1;
  if (i >= 0) and (i < Length(LineFor)) then
    LineNumber := LineFor[i]
  else
    LineNumber := 0;
  F            := TLeakFinding.Create;
  F.FileName   := FileName;
  F.MethodName := '';
  F.LineNumber := IntToStr(LineNumber + 1);
  F.MissingVar := Format(
    '`case` statement with %d branches (>= %d) - consider ' +
    'polymorphism, a dispatch table, or split into smaller ' +
    'cases.', [BranchCount, MaxBr]);
  F.SetKind(fkCaseStatementSize);
  Results.Add(F);
end;

class procedure TCaseStatementSizeDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines       : TStringList;
  Cached      : Boolean;
  Code        : string;
  Lwr         : string;
  LineFor     : TArray<Integer>;
  pCase       : Integer;
  pOf, pEnd   : Integer;
  BranchCount : Integer;
  FirstColon  : Integer;
  MaxBr       : Integer;
begin
  // Konfigurierbar via INI [Detectors] MaxCaseBranches=N, Default 10.
  MaxBr := CfgMaxCaseBranches(AContext);   // TD-1: per-Scan statt Global
  if MaxBr <= 0 then MaxBr := DEFAULT_MAX_BRANCH_FALLBACK;
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    Code := TDetectorUtils.StripFileCommentsKeepStringsCached(Lines, LineFor, AContext, FileName);
    // Review-HIGH 2026-08-08: Literal-Inhalte laengenerhaltend blanken -
    // sonst startet 'CASE WHEN x THEN 1 ELSE 0 END' in einem SQL-Literal
    // einen Phantom-case, und dessen 'END' schliesst zusaetzlich ECHTE
    // Pascal-case-Bloecke vorzeitig (LineFor-Indizes bleiben durch die
    // Laengenerhaltung gueltig).
    Code := TDetectorUtils.BlankStringLiterals(Code);
    Lwr := LowerCase(Code);
    pCase := 1;
    while NextCaseWord(Code, Lwr, pCase) do
    begin
      if not ResolveCaseSpan(Code, LineFor, pCase, pOf, pEnd) then
      begin
        // Weiter ab pCase+4, NICHT hinter pEnd - sonst bliebe ein echtes
        // case unterhalb eines Phantoms weiter unsichtbar.
        Inc(pCase, 4);
        Continue;
      end;
      BranchCount := CountBranches(Code, pOf + 2, pEnd, FirstColon);
      // K2: record-Variantenteil ist kein Statement.
      if (BranchCount >= MaxBr) and
         not IsRecordVariantPart(Code, FirstColon) then
        AddCaseFinding(Results, FileName, LineFor, pCase, BranchCount, MaxBr);
      // ABSTIEG: im Rumpf weiterlaufen statt hinter das `end` zu springen,
      // damit geschachtelte case nach ihrer EIGENEN Groesse beurteilt
      // werden. pOf >= pCase+4, der Scan rueckt also sicher vor.
      pCase := pOf + 2;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

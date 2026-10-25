unit uCognitiveComplexity;

// Detektor: Sonar-Cognitive-Complexity pro Methode.
//
// McCabe-Cyclomatic-Complexity (SCA022) zaehlt unabhaengige Pfade
// linear - 10 separate if-Statements werden gleich gewichtet wie
// ein dreifach verschachteltes if. Cognitive-Complexity (von Sonar
// 2017 eingefuehrt) gewichtet verschachtelte Logik schwerer, weil
// sie mental schwieriger zu folgen ist.
//
// Formel (vereinfacht, Sonar-Kompatibel):
//   B1: +1 pro Kontrollfluss-Konstrukt (if, while, for, repeat, case,
//       on-handler) - linear-Erkennung.
//   B2: +N pro Verschachtelung, wo N = aktuelle Tiefe ueber Method-Root.
//       Z.B. ein if INNERHALB eines for INNERHALB eines while:
//         while ... do         (+1, depth=0)
//           for ... do         (+1+1 = +2, depth=1)
//             if ... then      (+1+2 = +3, depth=2)
//       Cyclomatic waere: +1+1+1 = 3. Cognitive: +1+2+3 = 6.
//       AUSNAHME 'else if' (Sonar: "else if" ist +1 OHNE Nesting-
//       Zuschlag): der Parser haengt den else-Zweig als nkElseBranch
//       UNTER das nkIfStmt (uParser2.ParseIfStmt), ein 'else if' liegt
//       also strukturell eine Ebene tiefer als die Kette semantisch ist.
//       Ohne Korrektur kostete eine FLACHE else-if-Kette der Laenge N
//       nicht N sondern N*(N+1)/2 (uUnusedUses.pas:139 mit 121 else-if:
//       Score 7575 statt 121) - eine reine Metrik-Verfaelschung. Siehe
//       CountInMethod: direkte nkIfStmt-Kinder eines nkElseBranch erben
//       die Tiefe des UMGEBENDEN if, nicht die erhoehte.
//   B3: +1 pro boolean-OPERATOR (and/or/xor) in if-Bedingung.
//       Sonar zaehlt hier Sequenzen: 'a and b and c' gibt dort EINEN
//       Punkt, hier ZWEI. Bewusste Vereinfachung - die Sequenzerkennung
//       braeuchte einen Ausdrucksbaum, den dieser Detektor nicht hat.
//       Der Kopf behauptete bis zum Voll-Review 2026-09-12 das
//       Sonar-Verhalten und widersprach damit der Zaehlschleife
//       (Minor 230).
//
// Schwellwert: DetectorMaxCognitive (Default 15 - Sonar-Industry-
// Standard). > 15 bedeutet "schwer mental zu folgen".
//
// ZAEHLER-STICHPROBE 2026-09-05 (O2-Triage, letzte unvermessene
// Metrik-Regel; volle Nachbildung des Scores waere Scheingenauigkeit,
// deshalb HANDRECHNUNG nach diesem Kopf als Spezifikation):
// geschichtete Ziehung 15 von 12.056 (rw66, Seed 20260905; das
// Grenzband 16-17 mit 6 Faellen ueberrepraesentiert, weil nur dort
// ein kleiner Zaehlfehler den Fund kippt). Ergebnis: ALLE SECHS
// Grenzfaelle EXAKT getroffen (gnugettext 16, uPSRuntime 16,
// JvDBCtrl 17, wbLOD 16, JvButtons 16, JvDBMove 17), drei
// Mittelband-Faelle ebenfalls exakt (JclGraphics 20, frmMain 20,
// Vcl.Styles.Utils.Forms 26), sechs Hochband-Faelle als >Limit
// gesichert. NULL Zaehlfehler.
// Dabei bestaetigte Eigenheiten der Spezifikation:
//   * plain-else/try/except zaehlen NICHT (bewusst, s. "BEWUSST
//     NICHT" vom 26.07.) - senkt gegenueber Sonar.
//   * BITWEISES and/or in einer if-Bedingung zaehlt wie boolesches
//     (CountBooleanOpsInCond kennt keine Typen; frmMain
//     '(Flags shr i) and 1 = 1' zaehlt +1) - hebt leicht, konsistent.
//   * Die else-if-Korrektur traegt exakt (uPSRuntime-Kette).
//
// Implementierung: iterative DFS analog SCA022 (Stack-Overflow-Schutz
// bei tief verschachtelten Files - siehe Audit_jvcl_segfault.md).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

const
  // Default-Threshold; konfigurierbar via INI [Detectors] CognitiveLimit
  DEF_COGNITIVE_LIMIT = 15;

type
  TCognitiveComplexityDetector = class
  public
    // Perf Q2: AContext haelt die Schwelle [Detectors] CognitiveLimit
    // einen Scan lang (s. LimitFor); nil = Tests/Direktaufrufe, dann
    // wird die ini wie bisher je Aufruf gelesen.
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  private
    // Der Walk selbst (CountInMethod) steht seit Perf Q2 als
    // Unit-Funktion im implementation-Teil: er bekommt den Stapel und
    // die Gliederliste vom Aufrufer, und deren Elementtyp ist dort
    // deklariert. Vertrag und Begruendung stehen an der Funktion.
    class function CountBooleanOpsInCond(const CondText: string): Integer; static;
  end;

implementation

uses
  System.Generics.Defaults,       // Perf Charge R3: einmal geholte Comparer
  uDetectorUtils,                 // Backlog-Welle 1, 2026-07-26
  uRepoSettings;                  // alphabetisch: diese Unit hat als einzige
                                  // der Welle keinen noinspection-Marker,
                                  // unsortiert waere hier ein echter SCA142

function QuickReadIntDef(const ASection, AKey: string; ADefault: Integer): Integer;
var
  S : string;
begin
  S := TRepoSettings.QuickReadStr(ASection, AKey, IntToStr(ADefault));
  Result := StrToIntDef(S, ADefault);
end;

// Perf Q2 (2026-10-25): die Schwelle EINMAL je Kontext lesen. Bis
// hierher lief QuickReadIntDef je DATEI - und TRepoSettings.QuickReadStr
// legt dabei jedes Mal ein TMemIniFile an, laedt und zerlegt die ganze
// analyser.ini (ohne ini drei FileExists je Datei). Profiler Q3: ~1,1 s
// CPU auf jvcl, schon in v0.9.18. Der Kontext lebt einen Scan lang,
// jeder Parallel-Worker hat seinen eigenen - der Wert ist damit wie die
// TD-1-Schwellen der anderen Detektoren scan-konstant. Gelesen wird
// derselbe Schluessel mit derselben Vorgabe wie zuvor; einziger
// Unterschied: eine ini-Aenderung WAEHREND eines laufenden Scans wirkt
// erst im naechsten. Ohne Kontext (Tests, Direktaufrufe) bleibt es beim
// Lesen je Aufruf.
function LimitFor(AContext: TAnalyzeContext): Integer;
begin
  if (AContext <> nil) and AContext.TryGetCognitiveLimit(Result) then Exit;
  Result := QuickReadIntDef('Detectors', 'CognitiveLimit', DEF_COGNITIVE_LIMIT);
  if AContext <> nil then AContext.PutCognitiveLimit(Result);
end;

type
  TStackEntry = record
    Node  : TAstNode;
    Depth : Integer;     // Verschachtelungstiefe relativ zum Method-Root
    // L1: Kette der Konstrukte bis zu diesem Knoten - als INDEX in
    // die Glieder-Liste (TDetectorUtils.NestingChainPush), -1 = noch
    // kein Glied.
    // Perf P3 (2026-10-25): bis hierher stand die Kette als string
    // im Record. Das machte ihn zu einem VERWALTETEN Typ: jedes
    // Stack.Add/Delete und jede Zuweisung Entry/Child lief ueber die
    // RTTI-Kopie - fuer jeden Knoten jeder Methode, auch im
    // Normallauf mit leerer Kette (Messagent 2026-10-25: SCA176 laz
    // 0,78 -> 1,16 s seit v0.9.18). Ein Integer haelt den Record
    // unverwaltet wie in v0.9.18.
    Link  : Integer;
  end;

var
  // Perf Charge R3 (2026-10-26, Muster aus Q1/uUninitVar): Default-Comparer
  // der beiden Record-Listen in AnalyzeUnit EINMAL je Prozess
  // (initialization) und jedem Create mitgegeben. TList<T>.Create ohne
  // Comparer ruft fuer Record-T TComparer<T>._Default, und das fragt in der
  // Delphi-12-RTL bei JEDEM Aufruf per TRttiContext die RTTI nach einem
  // '='-Operator ab (Delphi 13 nicht mehr) - hier je Datei zweimal.
  // VERHALTENSNEUTRAL: derselbe Default-Comparer, und keine der Listen ruft
  // IndexOf/Contains/Remove/Sort (auch NestingChainPush/-Text nicht).
  GStackEntryComparer : IComparer<TStackEntry>;
  GChainLinkComparer  : IComparer<TNestingChainLink>;

class function TCognitiveComplexityDetector.CountBooleanOpsInCond(
  const CondText: string): Integer;
// Seit Voll-Review 2026-09-12 zentral: TDetectorUtils.
// CountBooleanOpsLower ist die byte-identische Hebung. Die fruehere
// Kopier-Begruendung ('Detektoren unabhaengig halten') war am Code
// erodiert - beide Kopien hingen laengst an TDetectorUtils und wurden
// zweimal synchron nachgezogen. Der Wrapper bleibt fuer die Aufrufer.
begin
  Result := TDetectorUtils.CountBooleanOpsLower(CondText);
end;

// L1: Anzeigename eines Konstrukts. Dieselben Woerter wie in
// uDeepNesting.KindName - die Ketten zweier Regeln sollen nicht wie
// zwei Werkzeuge aussehen.
//
// NICHT ZUSAMMENLEGEN, ohne das hier zu lesen: die Listen sind
// absichtlich verschieden lang. uDeepNesting kennt fuenf Konstrukte,
// diese hier sechs - nkOnHandler kommt dazu, weil SCA018 Exception-
// Handler bewusst NICHT als Verschachtelung zaehlt (COUNTING_KINDS
// dort: "Nur logische Verschachtelung"), SCA176 aber schon. Gleich
// ist die ABBILDUNG Kind -> Wort, verschieden die AUSWAHL der Kinds.
// Wer beide Listen angleicht, aendert stillschweigend, was SCA018
// meldet.
function NodeKindName(Kind: TNodeKind): string;
begin
  case Kind of
    nkIfStmt     : Result := 'if';
    nkForStmt    : Result := 'for';
    nkWhileStmt  : Result := 'while';
    nkRepeatStmt : Result := 'repeat';
    nkCaseStmt   : Result := 'case';
    nkOnHandler  : Result := 'on';
  else
    Result := '?';
  end;
end;

// Punktzahl einer Methode; dabei, im SELBEN Walk, die Kettenglieder
// in ALinks und in ABestLink das Glied der tiefsten Stelle (-1 =
// keins). Die Kette als TEXT entsteht erst in AnalyzeUnit und nur
// fuer meldende Methoden.
//
// Perf Q2 (2026-10-25): bis hierher lief der Walk ZWEIMAL je
// meldender Methode - erst ohne Kette, dann (ACollectChain=True) noch
// einmal mit, und der zweite Lauf zaehlte dabei auch die booleschen
// Operatoren jedes if neu (zwei String-Allokationen je if). Meldende
// Methoden sind die grossen: laz strict 3.162 Funde, rund 15 % aller
// Methodenzeilen und ein noch groesserer Teil der if-Knoten. Jetzt
// fuehrt der eine Walk die Glieder IMMER mit - ein unverwalteter
// 8-Byte-Record je Kontrollfluss-Knoten, kein Text. Stapel und
// Gliederliste legt AnalyzeUnit EINMAL je Unit an; vorher entstanden
// beide je Methode neu und wuchsen jedes Mal von Kapazitaet 0 auf.
// AStack ist beim Aufruf leer: jeder Walk leert ihn vollstaendig.
//
// ACHTUNG, ANDERER VERTRAG ALS BEI SCA018: dort IST die Gliederzahl
// die gemeldete Tiefe. Hier ist die Kette der TIEFSTE PFAD der
// Methode - sie veranschaulicht den Verschachtelungsanteil der
// Punktzahl, ist aber NICHT deren Nachrechnung (die Punktzahl zaehlt
// auch flache Verzweigungen und boolesche Operatoren).
function CountInMethod(MethodNode: TAstNode; AStack: TList<TStackEntry>;
  ALinks: TList<TNestingChainLink>; var ABestLink: Integer): Integer;
var
  Entry, Child : TStackEntry;
  i     : Integer;
  ChildDepth : Integer;
  ElseIfDepth : Integer;   // Tiefe fuer ein direktes nkIfStmt-Kind (else if)
  IsControlFlow : Boolean;
  MaxDepth : Integer;      // L1: tiefste erreichte Ebene
  ChildLink : Integer;     // L1: Kettenglied, das die Kinder erben
begin
  Result := 0;
  MaxDepth := -1;
  ABestLink := -1;
  // Glieder der VORIGEN Methode verwerfen. Count := 0 und NICHT
  // Clear: Clear setzt in Delphi auch Capacity auf 0 und nimmt damit
  // genau die Wiederverwendung wieder weg.
  ALinks.Count := 0;
  if MethodNode = nil then Exit;
  // Push children of MethodNode with Depth=0 (Method-Root selbst zaehlt nicht).
  for i := MethodNode.Children.Count - 1 downto 0 do
  begin
    Entry.Node  := MethodNode.Children[i];
    Entry.Depth := 0;
    Entry.Link  := -1;
    AStack.Add(Entry);
  end;

  while AStack.Count > 0 do
  begin
    Entry := AStack[AStack.Count - 1];
    AStack.Delete(AStack.Count - 1);

    IsControlFlow := False;
    case Entry.Node.Kind of
      nkIfStmt:
        begin
          // B1 + B2: 1 + current-Depth (Sonar-Formel)
          Inc(Result, 1 + Entry.Depth);
          // B3: boolean-Operatoren in if-Condition (and/or/xor)
          Inc(Result, TCognitiveComplexityDetector.CountBooleanOpsInCond(
            Entry.Node.TypeRef));
          IsControlFlow := True;
        end;
      nkForStmt, nkWhileStmt, nkRepeatStmt,
      nkCaseStmt, nkOnHandler:
        begin
          Inc(Result, 1 + Entry.Depth);
          IsControlFlow := True;
        end;
    end;

    // L1: die Kette waechst an genau den Knoten, die auch die
    // Verschachtelung erhoehen. Festgehalten wird der Pfad zur
    // TIEFSTEN Stelle; bei Gleichstand gewinnt der erste
    // (striktes >), genau wie in uDeepNesting. Die Kette ist
    // PFADABHAENGIG (jeder Frame hat seine eigene, die Zweige
    // divergieren) - deshalb Elternverweise statt eines Puffers;
    // der Text entsteht erst nach dem Walk, einmal.
    ChildLink := Entry.Link;
    if IsControlFlow then
    begin
      ChildLink := TDetectorUtils.NestingChainPush(ALinks,
        Entry.Node.Kind, Entry.Link);
      if Entry.Depth > MaxDepth then
      begin
        MaxDepth := Entry.Depth;
        ABestLink := ChildLink;
      end;
    end;

    // Verschachtelung: wenn Control-Flow, Depth+1 fuer Children.
    if IsControlFlow then ChildDepth := Entry.Depth + 1
    else                  ChildDepth := Entry.Depth;

    // 'else if'-Korrektur (2026-07-26): nkElseBranch haengt UNTER dem
    // nkIfStmt und traegt dessen bereits erhoehte Tiefe. Ein DIREKT
    // darin liegendes nkIfStmt ist aber kein verschachteltes if,
    // sondern das naechste Glied einer flachen else-if-Kette und
    // bekommt nach Sonar +1 OHNE Nesting-Zuschlag. Es erbt daher die
    // Tiefe des umgebenden if (ChildDepth-1), womit jedes Kettenglied
    // denselben Level wie das erste if bekommt -> Kosten N statt
    // N*(N+1)/2. Bewusst NUR fuer das direkte Kind: ein 'else begin
    // if ... end' liegt unter einem nkBlock, behaelt also seinen
    // Nesting-Zuschlag (Sonar-konform). Der Eingriff kann Scores
    // ausschliesslich SENKEN - nichts wird neu gezaehlt.
    ElseIfDepth := ChildDepth;
    if (Entry.Node.Kind = nkElseBranch) and (ChildDepth > 0) then
      ElseIfDepth := ChildDepth - 1;

    for i := Entry.Node.Children.Count - 1 downto 0 do
    begin
      Child.Node  := Entry.Node.Children[i];
      if Child.Node.Kind = nkIfStmt then Child.Depth := ElseIfDepth
      else                               Child.Depth := ChildDepth;
      Child.Link  := ChildLink;
      AStack.Add(Child);
    end;
  end;
  // Frueher wurde die Kette bei JEDEM neuen Maximum ueberschrieben -
  // stehen bleibt der Pfad des letzten Maximums, und genau dessen
  // Glied haelt ABestLink.
end;

class procedure TCognitiveComplexityDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
  CC      : Integer;
  Limit   : Integer;
  F       : TLeakFinding;
  Chain   : string;   // L1: nur fuer meldende Methoden gefuellt
  Stack   : TList<TStackEntry>;          // Perf Q2: je Unit EINMAL
  Links   : TList<TNestingChainLink>;    // Perf Q2: je Unit EINMAL
  BestLink : Integer;
begin
  Limit := LimitFor(AContext);
  Stack := nil;
  Links := nil;
  BestLink := -1;
  Methods := UnitNode.FindAll(nkMethod);
  try
    Stack := TList<TStackEntry>.Create(GStackEntryComparer);
    Links := TList<TNestingChainLink>.Create(GChainLinkComparer);
    for M in Methods do
    begin
      CC := CountInMethod(M, Stack, Links, BestLink);
      if CC <= Limit then Continue;
      // Kette als Text erst JETZT - nur fuer meldende Methoden.
      Chain := '';
      if BestLink >= 0 then
        Chain := TDetectorUtils.NestingChainText(Links, BestLink,
          NodeKindName);
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := M.Name;
      F.LineNumber := IntToStr(M.Line);
      F.MissingVar := Format(
        'Cognitive complexity %d (limit: %d) - nested control flow ' +
        'is hard to follow. Refactor by extracting helper methods or ' +
        'inverting guard conditions.',
        [CC, Limit]);
      F.SetKind(fkCognitiveComplexity);
      F.StructureChain := Chain;
      Results.Add(F);
    end;
  finally
    Links.Free;
    Stack.Free;
    Methods.Free;
  end;
end;

initialization
  // Perf Charge R3: s. GStackEntryComparer.
  GStackEntryComparer := TComparer<TStackEntry>.Default;
  GChainLinkComparer  := TComparer<TNestingChainLink>.Default;

end.

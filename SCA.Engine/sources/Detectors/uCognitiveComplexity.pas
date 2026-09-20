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
  uAstNode, uSCAConsts, uMethodd12;

const
  // Default-Threshold; konfigurierbar via INI [Detectors] CognitiveLimit
  DEF_COGNITIVE_LIMIT = 15;

type
  TCognitiveComplexityDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    // ACollectChain=False (Normalfall) baut KEINE Zeichenkette -
    // dieselbe Begruendung wie in uDeepNesting.Walk: der DFS laeuft
    // ueber jeden Knoten jeder Methode. AnalyzeUnit ruft ein
    // ZWEITES Mal, nur fuer meldende Methoden.
    //
    // ACHTUNG, ANDERER VERTRAG ALS BEI SCA018: dort IST die
    // Gliederzahl die gemeldete Tiefe. Hier ist die Kette der
    // TIEFSTE PFAD der Methode - sie veranschaulicht den
    // Verschachtelungsanteil der Punktzahl, ist aber NICHT deren
    // Nachrechnung (die Punktzahl zaehlt auch flache Verzweigungen
    // und boolesche Operatoren).
    class function CountInMethod(MethodNode: TAstNode;
      ACollectChain: Boolean = False;
      AChain: PString = nil): Integer; static;
    class function CountBooleanOpsInCond(const CondText: string): Integer; static;
  end;

implementation

uses
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

type
  TStackEntry = record
    // L1: Kette der Konstrukte bis zu diesem Knoten. Bei
    // ACollectChain=False durchgehend leer - die Zuweisung an ein
    // Kind ist dann eine reine Referenzzaehler-Erhoehung.
    Chain : string;
    Node  : TAstNode;
    Depth : Integer;     // Verschachtelungstiefe relativ zum Method-Root
  end;

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

class function TCognitiveComplexityDetector.CountInMethod(
  MethodNode: TAstNode; ACollectChain: Boolean;
  AChain: PString): Integer;
var
  Stack : TList<TStackEntry>;
  Entry, Child : TStackEntry;
  i     : Integer;
  ChildDepth : Integer;
  ElseIfDepth : Integer;   // Tiefe fuer ein direktes nkIfStmt-Kind (else if)
  IsControlFlow : Boolean;
  MaxDepth : Integer;      // L1: tiefste erreichte Ebene
  ChildChain : string;
begin
  Result := 0;
  MaxDepth := -1;
  if ACollectChain and (AChain <> nil) then AChain^ := '';
  if MethodNode = nil then Exit;
  Stack := TList<TStackEntry>.Create;
  try
    // Push children of MethodNode with Depth=0 (Method-Root selbst zaehlt nicht).
    for i := MethodNode.Children.Count - 1 downto 0 do
    begin
      Entry.Node  := MethodNode.Children[i];
      Entry.Depth := 0;
      Entry.Chain := '';
      Stack.Add(Entry);
    end;

    while Stack.Count > 0 do
    begin
      Entry := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);

      IsControlFlow := False;
      case Entry.Node.Kind of
        nkIfStmt:
          begin
            // B1 + B2: 1 + current-Depth (Sonar-Formel)
            Inc(Result, 1 + Entry.Depth);
            // B3: boolean-Operatoren in if-Condition (and/or/xor)
            Inc(Result, CountBooleanOpsInCond(Entry.Node.TypeRef));
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
      // (striktes >), genau wie in uDeepNesting.
      ChildChain := Entry.Chain;
      if ACollectChain and IsControlFlow then
      begin
        if ChildChain = '' then
          ChildChain := NodeKindName(Entry.Node.Kind)
        else
        // Der Akkumulator ist an die VERSCHACHTELUNGSTIEFE gebunden,
        // nicht an die Knotenzahl: gemessen liegen 98,1 % der
        // SCA018-Funde bei Tiefe <= 8, das Maximum im Korpus ist 16.
        // Ein TStringBuilder scheidet hier ausserdem aus, weil die
        // Kette PFADABHAENGIG ist - jeder Stack-Frame traegt seine
        // eigene, und die Zweige divergieren. Ein Builder hat genau
        // einen Puffer und koennte das nicht abbilden.
        // noinspection StringConcatInLoop
          ChildChain := ChildChain + CHAIN_SEP +
                        NodeKindName(Entry.Node.Kind);
        if Entry.Depth > MaxDepth then
        begin
          MaxDepth := Entry.Depth;
          if AChain <> nil then AChain^ := ChildChain;
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
        Child.Chain := ChildChain;
        Stack.Add(Child);
      end;
    end;
  finally
    Stack.Free;
  end;
end;

class procedure TCognitiveComplexityDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
  CC      : Integer;
  Limit   : Integer;
  F       : TLeakFinding;
  Chain   : string;   // L1: nur fuer meldende Methoden gefuellt
begin
  Limit := QuickReadIntDef('Detectors', 'CognitiveLimit', DEF_COGNITIVE_LIMIT);
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      CC := CountInMethod(M);
      if CC <= Limit then Continue;
      // Kette erst JETZT bauen - nur fuer meldende Methoden.
      Chain := '';
      CountInMethod(M, True, @Chain);
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
    Methods.Free;
  end;
end;

end.

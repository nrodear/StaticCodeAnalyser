unit uDeepNesting;

// Detektor fuer zu tiefe Verschachtelung von Kontrollstrukturen.
//
// Gezaehlte Strukturen (kognitiver Aufwand):
//   if          → erhoeht die Tiefe (der else-ZWEIG selbst nie -
//                 nkElseBranch steht nicht in COUNTING_KINDS; zur
//                 else-if-Kette siehe den Absatz weiter unten)
//   for / while / repeat → Schleifen
//   case        → Verzweigung
//
// NICHT gezaehlt (Resource-Management, kein logischer Bruch):
//   try / except / finally
//
// Beispiel der Rationalisierung: Eine korrekt geschriebene Methode mit
//   try
//     for ... do
//       if ... then ...
//   finally
//     ...
//   end;
// hat Tiefe 2 (for + if), nicht 3.
//
// NICHT als neue Ebene gezaehlt: das 'if' einer 'else if'-KETTE.
//   if A then .. else if B then .. else if C then ..
// ist fachlich EINE mehrarmige Verzweigung (wie ein case), keine
// dreifache Schachtelung - siehe Walk() fuer Mechanik und Messung.
//
// Schwelle: > MAX_DEPTH (Default: 4) bedeutet >= 5 verschachtelte Ebenen.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TDeepNestingDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  private
    // ACollectChain=False (der Normalfall) baut KEINE Zeichenkette -
    // der Walk laeuft ueber jeden Knoten jeder Methode, und eine
    // Verkettung je Verschachtelungsknoten waere korpusweit eine
    // Allokationslawine in genau dem Pfad, der diesem Plugin schon
    // einen Stack-Overflow beschert hat. AnalyzeUnit ruft den Walk
    // deshalb ein ZWEITES Mal - nur fuer die Methoden, die wirklich
    // einen Fund erzeugen (korpusweit 3.452 von Millionen).
    class procedure Walk(Node: TAstNode; Depth: Integer;
      var DeepestLine, DeepestDepth: Integer;
      var DeepestKind: TNodeKind;
      ACollectChain: Boolean = False;
      ADeepestChain: PString = nil); static;
    class function KindName(Kind: TNodeKind): string; static;
  end;

implementation

// noinspection-file ConsecutiveSection, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

// Schwellwert kommt aus uSCAConsts.DetectorMaxNesting (analyser.ini ->
// DeepNestingMaxDepth). Default 4 (also wird ab 5 verschachtelten
// Ebenen gemeldet).

const
  // Nur logische Verschachtelung – keine Exception-Handler
  COUNTING_KINDS : set of TNodeKind =
    [nkIfStmt, nkForStmt, nkWhileStmt, nkRepeatStmt, nkCaseStmt];

  // Trenner der Verschachtelungskette. EIN Ort - die Anzeige
  // uebernimmt die Zeichenkette unveraendert, damit Editor, HTML
  // und Export nicht drei Schreibweisen bekommen.
  CHAIN_SEP = ' → ';

class function TDeepNestingDetector.KindName(Kind: TNodeKind): string;
begin
  case Kind of
    nkIfStmt     : Result := 'if';
    nkForStmt    : Result := 'for';
    nkWhileStmt  : Result := 'while';
    nkRepeatStmt : Result := 'repeat';
    nkCaseStmt   : Result := 'case';
  else
    Result := '?';
  end;
end;

class procedure TDeepNestingDetector.Walk(Node: TAstNode; Depth: Integer;
  var DeepestLine, DeepestDepth: Integer;
  var DeepestKind: TNodeKind;
  ACollectChain: Boolean; ADeepestChain: PString);
// FIX (jvcl-Audit 2026-06-07): iterative DFS statt rekursivem Walk.
// Bei tief verschachteltem AST (z.B. JvId3v2.pas mit langen
// if-then-else-Ketten) sprengte Walk(Self) den Default-Stack mit
// STACK_OVERFLOW ($C00000FD). Explicit Stack mit (Node, Depth)-Paaren.
//
// FIX (Autopsie 2026-08-27, SCA018-FP-Klasse 'else-if-Kette'): ein
// direkt unter nkElseBranch haengendes nkIfStmt zaehlt NICHT als neue
// Ebene. Der Parser haengt den else-Zweig als nkElseBranch UNTER das
// nkIfStmt (uParser2.ParseIfStmt:2402-2407) und dieses traegt bereits
// die erhoehte Tiefe; jedes Kettenglied bekam dadurch +1, obwohl
// 'if..else if..else if' fachlich EINE mehrarmige Verzweigung ist.
// Mechanik-Vorlage: uCognitiveComplexity.CountInMethod:173-192, dort
// seit 2026-07-26 im Einsatz (ElseIfDepth := ChildDepth - 1).
// GEZAEHLT am Korpus D:\git-sca-realworld (rw17, Detektor-Replikat
// ueber alle Dateien mit SCA018-Fund): 5.935 reproduzierte Funde ->
// 2.316 Drops (39,0 %); 3.619 bleiben, davon 916 mit gesenkter Tiefe
// und 619 mit verschobenem Anker (der Detektor meldet die TIEFSTE
// Stelle - schrumpft die Kette, gewinnt eine andere Stelle der
// Methode; 178 dieser Verschiebungen passieren bei UNVERAENDERTER
// Tiefe, weil bei Gleichstand ein anderer Knoten das strikte '>'
// gewinnt). 0 neue Funde, 0 gestiegene Tiefen - strukturell garantiert,
// weil der Eingriff Inc() ausschliesslich UNTERDRUECKT.
// EHRLICH ZU DEN DROPS (Gegenpruefung 2026-08-27): sie sind NICHT alle
// offensichtliche Fehlalarme. Nach-Tiefen der 2.316 Drops: 659 landen
// auf Tiefe 1-2 (reine Kettensymptome), 1.022 auf GENAU Tiefe 4 - das
// sind Schwellen-Grenzfaelle, die das Modell mit einem case gleichsetzt
// (auch ein case zaehlt nur EINE Ebene). Wer die 39 % spaeter zitiert,
// sollte sie nicht als '39 % bewiesene FPs' lesen.
// BEWUSST ENG: nur das DIREKTE Kind. 'else begin if .. end' liegt unter
// einem nkBlock und behaelt seinen Zuschlag - das ist echte
// Schachtelung. 'else case' ebenso (nur nkIfStmt ist Kettenglied).
// NICHT umgesetzt (Autopsie hat es widerlegt): Schwelle 4 -> 5/6/7. Die
// FP-Quote bleibt dabei praktisch konstant (39,2 / 36,6 / 39,9 /
// 44,7 %), weil Ketten schneller inflationieren als echte Schachtelung
// tief wird.
type
  TFrame = record
    N : TAstNode;
    D : Integer;
    // Kette der Konstrukte von aussen bis zu diesem Knoten. Bei
    // ACollectChain=False bleibt sie durchgehend leer; die
    // Zuweisung an ein Kind ist dann eine reine
    // Referenzzaehler-Erhoehung, keine Kopie.
    C : string;
  end;
var
  Stack    : TList<TFrame>;
  Cur      : TFrame;
  Child    : TAstNode;
  NewDepth : Integer;
  NewChain : string;
  IsElseIf : Boolean;
  F        : TFrame;
begin
  if Node = nil then Exit;
  Stack := TList<TFrame>.Create;
  try
    F.N := Node; F.D := Depth; F.C := '';
    Stack.Add(F);
    while Stack.Count > 0 do
    begin
      Cur := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);
      for Child in Cur.N.Children do
      begin
        NewDepth := Cur.D;
        // Kettenglied 'else if': erbt die Tiefe des Kopf-if statt +1.
        // nkElseBranch entsteht ausschliesslich in ParseIfStmt (geprueft
        // 2026-08-27: einzige Add-Stelle) - der case-else-Zweig ist ein
        // nkCaseArm und faellt hier bewusst NICHT hinein.
        IsElseIf := (Cur.N.Kind = nkElseBranch) and (Child.Kind = nkIfStmt);
        NewChain := Cur.C;
        if (Child.Kind in COUNTING_KINDS) and not IsElseIf then
        begin
          Inc(NewDepth);
          // Die Kette waechst an GENAU den Knoten, die auch die
          // Tiefe erhoehen - damit ist ihre Gliederzahl immer die
          // gemeldete Tiefe, und das else-if-Kettenglied wird hier
          // wie dort nicht mitgezaehlt.
          if ACollectChain then
            if NewChain = '' then
              NewChain := KindName(Child.Kind)
            else
              NewChain := NewChain + CHAIN_SEP + KindName(Child.Kind);
          if NewDepth > DeepestDepth then
          begin
            DeepestDepth := NewDepth;
            DeepestLine  := Child.Line;
            DeepestKind  := Child.Kind;
            if ACollectChain and (ADeepestChain <> nil) then
              ADeepestChain^ := NewChain;
          end;
        end;
        F.N := Child; F.D := NewDepth; F.C := NewChain;
        Stack.Add(F);
      end;
    end;
  finally
    Stack.Free;
  end;
end;

class procedure TDeepNestingDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Methods       : TList<TAstNode>;
  M             : TAstNode;
  DeepestLine   : Integer;
  DeepestDepth  : Integer;
  DeepestKind   : TNodeKind;
  F             : TLeakFinding;
  MaxNesting    : Integer;   // TD-1: Schwelle per-Scan aus AContext.Config
  Chain         : string;    // K1: nur fuer Fundmethoden gefuellt
  ChainLine     : Integer;
  ChainDepth    : Integer;
  ChainKind     : TNodeKind;
begin
  // TD-1 (2026-07-06): Schwelle einmal aus dem Context lesen (scan-konstant).
  MaxNesting := CfgMaxNesting(AContext);
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      DeepestLine  := 0;
      DeepestDepth := 0;
      DeepestKind  := nkUnknown;
      Walk(M, 0, DeepestLine, DeepestDepth, DeepestKind);

      if DeepestDepth > MaxNesting then
      begin
        // Erst JETZT die Kette bauen: nur fuer Methoden, die
        // wirklich melden. Zweiter Lauf derselben Funktion statt
        // einer zweiten Implementierung - sonst drifteten die
        // beiden Tiefenmodelle (else-if-Regel!) frueher oder
        // spaeter auseinander.
        Chain        := '';
        ChainLine    := 0;
        ChainDepth   := 0;
        ChainKind    := nkUnknown;
        Walk(M, 0, ChainLine, ChainDepth, ChainKind, True, @Chain);
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := M.Name;
        F.LineNumber := IntToStr(DeepestLine);
        F.MissingVar := Format(
          'Depth %d (%s from line %d, limit: %d)',
          [DeepestDepth, KindName(DeepestKind),
           DeepestLine, MaxNesting]);
        F.SetKind(fkDeepNesting);
        F.StructureChain := Chain;
        Results.Add(F);
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.

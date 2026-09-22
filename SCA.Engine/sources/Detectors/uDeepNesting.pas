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
  // Das Ergebnis eines Walk-Laufs: die tiefste Stelle und - auf
  // Wunsch - der Pfad dorthin.
  TDeepestHit = record
    Line    : Integer;
    Depth   : Integer;
    Kind    : TNodeKind;
    // Nur gefuellt, wenn Collect gesetzt ist. Der Normallauf baut
    // KEINE Zeichenkette - der DFS laeuft ueber jeden Knoten jeder
    // Methode, und AnalyzeUnit ruft ein zweites Mal nur fuer die
    // Methoden, die wirklich melden.
    Chain   : string;
    Collect : Boolean;
  end;

  TDeepNestingDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  private
    // Ohne TDeepestHit.Collect (der Normalfall) entsteht KEINE Kette -
    // der Walk laeuft ueber jeden Knoten jeder Methode, und eine
    // Verkettung je Verschachtelungsknoten waere korpusweit eine
    // Allokationslawine in genau dem Pfad, der diesem Plugin schon
    // einen Stack-Overflow beschert hat. AnalyzeUnit ruft den Walk
    // deshalb ein ZWEITES Mal - nur fuer die Methoden, die wirklich
    // einen Fund erzeugen (korpusweit 3.452 von Millionen).
    // R1 (2026-09-22): die vier var-Parameter waren EIN Zustand -
    // "die tiefste bisher gefundene Stelle" - und standen trotzdem
    // einzeln in der Signatur. Als Record ist das benennbar, und
    // Walk kommt von sieben auf drei Parameter.
    //
    // Collect gehoert mit hinein: es ist kein Schalter des
    // Aufrufers an die Funktion, sondern Teil der Anfrage ("sammle
    // dabei die Kette"). Als nackter Boolean-Parameter war es
    // genau das, was ein Aufrufer nicht lesen kann - Walk(M, 0, X,
    // Y, Z, True, @C) sagt nicht, was True bedeutet.
    class procedure Walk(Node: TAstNode; Depth: Integer;
      var ADeepest: TDeepestHit); static;
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

// R1 (2026-09-22): Kette um ein Glied verlaengern. Steht hier
// heraussen, weil die beiden Zweige in Walk eine vierte
// Verschachtelungsebene aufmachten - genau die, die den Detektor
// am eigenen Code hat anschlagen lassen (SCA176: 27).
function KetteUm(const AKette: string; AKind: TNodeKind): string;
begin
  if AKette = '' then
    Exit(TDeepNestingDetector.KindName(AKind));
  // Der Akkumulator ist an die VERSCHACHTELUNGSTIEFE gebunden,
  // nicht an die Knotenzahl: gemessen liegen 98,1 % der
  // SCA018-Funde bei Tiefe <= 8, das Maximum im Korpus ist 16.
  // Ein TStringBuilder scheidet hier aus, weil die Kette
  // PFADABHAENGIG ist - jeder Stack-Frame traegt seine eigene, und
  // die Zweige divergieren. Ein Builder hat genau einen Puffer und
  // koennte das nicht abbilden.
  //
  // Der frueher noetige noinspection-Marker ist mit der Extraktion
  // ENTFALLEN: hier gibt es keine Schleife mehr, die Regel feuert
  // gar nicht. Der Selbstscan hat den toten Marker prompt als
  // SCA165 gemeldet.
  Result := AKette + CHAIN_SEP + TDeepNestingDetector.KindName(AKind);
end;

// R1 (2026-09-22): zaehlt dieses Kind als eigene Ebene?
//
// INLINE mit Absicht: der Ausdruck wird fuer JEDEN Knoten JEDER
// Methode ausgewertet - das ist der heisseste Pfad dieses
// Detektors, und er hat dem Plugin schon einmal einen
// Stack-Overflow beschert. Der Compiler expandiert die Funktion,
// es bleibt derselbe Ausdruck wie vorher, nur mit einem Namen.
// Nimmt die ELTERNART statt des ganzen Frames: TFrame ist lokal in
// Walk deklariert und hier gar nicht sichtbar - und gebraucht wird
// ohnehin nur diese eine Eigenschaft.
function ZaehltAlsEbene(AParentKind: TNodeKind;
  AChild: TAstNode): Boolean; inline;
begin
  // Kettenglied "else if": erbt die Tiefe des Kopf-if statt +1.
  // nkElseBranch entsteht ausschliesslich in ParseIfStmt (geprueft
  // 2026-08-27: einzige Add-Stelle) - der case-else-Zweig ist ein
  // nkCaseArm und faellt hier bewusst NICHT hinein.
  Result := (AChild.Kind in COUNTING_KINDS)
            and not ((AParentKind = nkElseBranch)
                     and (AChild.Kind = nkIfStmt));
end;

// R1: neues Maximum uebernehmen. Die Kette nur, wenn sie
// ueberhaupt gesammelt wird - sonst stuende dort die leere
// Zeichenkette und ueberschriebe nichts, aber der Vertrag waere
// unklar.
procedure MerkeTiefste(var ADeepest: TDeepestHit; ADepth: Integer;
  AChild: TAstNode; const AKette: string);
begin
  ADeepest.Depth := ADepth;
  ADeepest.Line  := AChild.Line;
  ADeepest.Kind  := AChild.Kind;
  if ADeepest.Collect then
    ADeepest.Chain := AKette;
end;

class procedure TDeepNestingDetector.Walk(Node: TAstNode; Depth: Integer;
  var ADeepest: TDeepestHit);
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
    // nicht gesetztem Collect bleibt sie durchgehend leer; die
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
        NewChain := Cur.C;
        if ZaehltAlsEbene(Cur.N.Kind, Child) then
        begin
          Inc(NewDepth);
          // Die Kette waechst an GENAU den Knoten, die auch die
          // Tiefe erhoehen - damit ist ihre Gliederzahl immer die
          // gemeldete Tiefe, und das else-if-Kettenglied wird hier
          // wie dort nicht mitgezaehlt.
          if ADeepest.Collect then
            NewChain := KetteUm(NewChain, Child.Kind);
          if NewDepth > ADeepest.Depth then
            MerkeTiefste(ADeepest, NewDepth, Child, NewChain);
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
  // R1 (2026-09-22): zwei Records statt sieben Einzelvariablen.
  // Tiefste traegt den Normallauf, MitKette den zweiten Lauf, der
  // nur fuer meldende Methoden ueberhaupt stattfindet.
  Tiefste       : TDeepestHit;
  MitKette      : TDeepestHit;
  F             : TLeakFinding;
  MaxNesting    : Integer;   // TD-1: Schwelle per-Scan aus AContext.Config
begin
  // TD-1 (2026-07-06): Schwelle einmal aus dem Context lesen (scan-konstant).
  MaxNesting := CfgMaxNesting(AContext);
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      Tiefste := Default(TDeepestHit);
      Walk(M, 0, Tiefste);

      if Tiefste.Depth > MaxNesting then
      begin
        // Erst JETZT die Kette bauen: nur fuer Methoden, die
        // wirklich melden. Zweiter Lauf derselben Funktion statt
        // einer zweiten Implementierung - sonst drifteten die
        // beiden Tiefenmodelle (else-if-Regel!) frueher oder
        // spaeter auseinander.
        MitKette := Default(TDeepestHit);
        MitKette.Collect := True;
        Walk(M, 0, MitKette);
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := M.Name;
        F.LineNumber := IntToStr(Tiefste.Line);
        F.MissingVar := Format(
          'Depth %d (%s from line %d, limit: %d)',
          [Tiefste.Depth, KindName(Tiefste.Kind),
           Tiefste.Line, MaxNesting]);
        F.SetKind(fkDeepNesting);
        // Der MELDETEXT kommt unveraendert aus dem ersten Lauf -
        // nur die Kette aus dem zweiten. Beide Laeufe liefern
        // dieselbe Tiefe (gleiche Funktion, gleiches Modell); haette
        // man hier auf MitKette umgestellt, waere das eine stille
        // Verhaltensaenderung an der Fund-Identitaet gewesen.
        F.StructureChain := MitKette.Chain;
        Results.Add(F);
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.

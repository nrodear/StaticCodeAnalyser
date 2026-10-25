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
    // Der Walk (samt TDeepestHit) steht seit Perf Q2 als Unit-Prozedur
    // im implementation-Teil: er bekommt Stapel und Gliederliste vom
    // Aufrufer, und deren Elementtypen sind dort deklariert. Vertrag
    // und Begruendung stehen am Walk.
    class function KindName(Kind: TNodeKind): string; static;
  end;

implementation

// noinspection-file ConsecutiveSection, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uDetectorUtils;   // Perf P3: NestingChainPush/-Text (Kette als Index)

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

// Perf P3 (2026-10-25): Wort fuer ein Kettenglied, als schlichte
// Funktion fuer TDetectorUtils.NestingChainText (ein procedural
// type, kein Methodenzeiger). Ersetzt KetteUm: die Kette wird nicht
// mehr je Stapel-Frame verkettet, sondern als Elternverweis gefuehrt
// und erst nach dem Walk einmal zu Text (seit Perf Q2 nur fuer
// meldende Methoden, in AnalyzeUnit).
function KindNameOf(AKind: TNodeKind): string;
begin
  Result := TDeepNestingDetector.KindName(AKind);
end;

type
  // Das Ergebnis eines Walk-Laufs: die tiefste Stelle und das
  // Kettenglied dorthin.
  // Perf Q2 (2026-10-25): bis hierher stand die Kette als Text im
  // Record (Chain) und ein Schalter Collect bestimmte, ob der Walk sie
  // ueberhaupt sammelt - AnalyzeUnit lief dafuer fuer meldende
  // Methoden ein ZWEITES Mal. Jetzt sammelt der eine Walk die Glieder
  // immer (unverwaltete 8-Byte-Records, nur an zaehlenden Knoten),
  // und Link zeigt auf das Glied der tiefsten Stelle (-1 = keins).
  // Den Text baut AnalyzeUnit nur fuer meldende Methoden. Nebenbei
  // ist der Record wieder unverwaltet: kein string, keine
  // RTTI-Initialisierung je Methode.
  TDeepestHit = record
    Line    : Integer;
    Depth   : Integer;
    Kind    : TNodeKind;
    Link    : Integer;
  end;

  TFrame = record
    N : TAstNode;
    D : Integer;
    // Kette der Konstrukte von aussen bis zu diesem Knoten, als
    // INDEX in die Gliederliste (-1 = noch kein Glied).
    // Perf P3 (2026-10-25): hier stand bis dahin die Kette als
    // string. Das machte TFrame zu einem VERWALTETEN Record - jedes
    // Stack.Add/Delete und jede Zuweisung Cur/F lief ueber die
    // RTTI-Kopie, fuer jeden Knoten jeder Methode, auch im
    // Normallauf mit leerer Kette (Messagent 2026-10-25: SCA018 laz
    // 0,17 -> 0,61 s seit v0.9.18). Mit dem Integer ist TFrame
    // wieder unverwaltet wie in v0.9.18.
    L : Integer;
  end;

// R1 (2026-09-22): zaehlt dieses Kind als eigene Ebene?
//
// INLINE mit Absicht: der Ausdruck wird fuer JEDEN Knoten JEDER
// Methode ausgewertet - das ist der heisseste Pfad dieses
// Detektors, und er hat dem Plugin schon einmal einen
// Stack-Overflow beschert. Der Compiler expandiert die Funktion,
// es bleibt derselbe Ausdruck wie vorher, nur mit einem Namen.
// Nimmt die ELTERNART statt des ganzen Frames - gebraucht wird
// nur diese eine Eigenschaft.
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

// R1: neues Maximum uebernehmen - die Stelle und ihr Kettenglied.
procedure MerkeTiefste(var ADeepest: TDeepestHit; ADepth: Integer;
  AChild: TAstNode; ALink: Integer);
begin
  ADeepest.Depth := ADepth;
  ADeepest.Line  := AChild.Line;
  ADeepest.Kind  := AChild.Kind;
  ADeepest.Link  := ALink;
end;

procedure Walk(Node: TAstNode; Depth: Integer; var ADeepest: TDeepestHit;
  AStack: TList<TFrame>; ALinks: TList<TNestingChainLink>);
// FIX (jvcl-Audit 2026-06-07): iterative DFS statt rekursivem Walk.
// Bei tief verschachteltem AST (z.B. JvId3v2.pas mit langen
// if-then-else-Ketten) sprengte Walk(Self) den Default-Stack mit
// STACK_OVERFLOW ($C00000FD). Explicit Stack mit (Node, Depth)-Paaren.
//
// Perf Q2 (2026-10-25): AStack und ALinks legt AnalyzeUnit EINMAL je
// Unit an; vorher entstanden beide je Methode neu und wuchsen jedes
// Mal von Kapazitaet 0 auf. AStack ist beim Aufruf leer - jeder Walk
// leert ihn vollstaendig. ALinks verwirft die Glieder der vorigen
// Methode hier.
//
// FIX (Autopsie 2026-08-27, SCA018-FP-Klasse 'else-if-Kette'): ein
// direkt unter nkElseBranch haengendes nkIfStmt zaehlt NICHT als neue
// Ebene. Der Parser haengt den else-Zweig als nkElseBranch UNTER das
// nkIfStmt (uParser2.ParseIfStmt:2402-2407) und dieses traegt bereits
// die erhoehte Tiefe; jedes Kettenglied bekam dadurch +1, obwohl
// 'if..else if..else if' fachlich EINE mehrarmige Verzweigung ist.
// Mechanik-Vorlage: uCognitiveComplexity.CountInMethod, dort
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
var
  Cur      : TFrame;
  Child    : TAstNode;
  NewDepth : Integer;
  NewLink  : Integer;
  F        : TFrame;
begin
  // Count := 0 und NICHT Clear: Clear setzt in Delphi auch Capacity
  // auf 0 und nimmt damit genau die Wiederverwendung wieder weg.
  ALinks.Count := 0;
  ADeepest.Link := -1;
  if Node = nil then Exit;
  F.N := Node; F.D := Depth; F.L := -1;
  AStack.Add(F);
  while AStack.Count > 0 do
  begin
    Cur := AStack[AStack.Count - 1];
    AStack.Delete(AStack.Count - 1);
    for Child in Cur.N.Children do
    begin
      NewDepth := Cur.D;
      NewLink  := Cur.L;
      if ZaehltAlsEbene(Cur.N.Kind, Child) then
      begin
        Inc(NewDepth);
        // Die Kette waechst an GENAU den Knoten, die auch die
        // Tiefe erhoehen - damit ist ihre Gliederzahl immer die
        // gemeldete Tiefe, und das else-if-Kettenglied wird hier
        // wie dort nicht mitgezaehlt.
        NewLink := TDetectorUtils.NestingChainPush(ALinks,
          Child.Kind, NewLink);
        // Frueher setzte jedes neue Maximum die Kette neu - stehen
        // blieb die des letzten, und genau dessen Glied haelt Link.
        if NewDepth > ADeepest.Depth then
          MerkeTiefste(ADeepest, NewDepth, Child, NewLink);
      end;
      F.N := Child; F.D := NewDepth; F.L := NewLink;
      AStack.Add(F);
    end;
  end;
end;

class procedure TDeepNestingDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Methods       : TList<TAstNode>;
  M             : TAstNode;
  // R1 (2026-09-22): ein Record statt Einzelvariablen.
  Tiefste       : TDeepestHit;
  F             : TLeakFinding;
  MaxNesting    : Integer;   // TD-1: Schwelle per-Scan aus AContext.Config
  Stack         : TList<TFrame>;              // Perf Q2: je Unit EINMAL
  Links         : TList<TNestingChainLink>;   // Perf Q2: je Unit EINMAL
begin
  // TD-1 (2026-07-06): Schwelle einmal aus dem Context lesen (scan-konstant).
  MaxNesting := CfgMaxNesting(AContext);
  Stack := nil;
  Links := nil;
  Methods := UnitNode.FindAll(nkMethod);
  try
    Stack := TList<TFrame>.Create;
    Links := TList<TNestingChainLink>.Create;
    for M in Methods do
    begin
      Tiefste := Default(TDeepestHit);
      Walk(M, 0, Tiefste, Stack, Links);

      if Tiefste.Depth > MaxNesting then
      begin
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := M.Name;
        F.LineNumber := IntToStr(Tiefste.Line);
        F.MissingVar := Format(
          'Depth %d (%s from line %d, limit: %d)',
          [Tiefste.Depth, KindName(Tiefste.Kind),
           Tiefste.Line, MaxNesting]);
        F.SetKind(fkDeepNesting);
        // Die Kette als Text erst JETZT - nur fuer meldende
        // Methoden. Sie stammt aus DEMSELBEN Walk wie Tiefe und
        // Anker; bis Perf Q2 kam sie aus einem zweiten Lauf derselben
        // Funktion.
        if Tiefste.Link >= 0 then
          F.StructureChain := TDetectorUtils.NestingChainText(Links,
            Tiefste.Link, KindNameOf);
        Results.Add(F);
      end;
    end;
  finally
    Links.Free;
    Stack.Free;
    Methods.Free;
  end;
end;

end.

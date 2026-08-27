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
    class procedure Walk(Node: TAstNode; Depth: Integer;
      var DeepestLine, DeepestDepth: Integer;
      var DeepestKind: TNodeKind); static;
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

class procedure TDeepNestingDetector.Walk(Node: TAstNode; Depth: Integer;
  var DeepestLine, DeepestDepth: Integer;
  var DeepestKind: TNodeKind);
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
  end;
var
  Stack    : TList<TFrame>;
  Cur      : TFrame;
  Child    : TAstNode;
  NewDepth : Integer;
  IsElseIf : Boolean;
  F        : TFrame;
begin
  if Node = nil then Exit;
  Stack := TList<TFrame>.Create;
  try
    F.N := Node; F.D := Depth;
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
        if (Child.Kind in COUNTING_KINDS) and not IsElseIf then
        begin
          Inc(NewDepth);
          if NewDepth > DeepestDepth then
          begin
            DeepestDepth := NewDepth;
            DeepestLine  := Child.Line;
            DeepestKind  := Child.Kind;
          end;
        end;
        F.N := Child; F.D := NewDepth;
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
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := M.Name;
        F.LineNumber := IntToStr(DeepestLine);
        F.MissingVar := Format(
          'Depth %d (%s from line %d, limit: %d)',
          [DeepestDepth, KindName(DeepestKind),
           DeepestLine, MaxNesting]);
        F.SetKind(fkDeepNesting);
        Results.Add(F);
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.

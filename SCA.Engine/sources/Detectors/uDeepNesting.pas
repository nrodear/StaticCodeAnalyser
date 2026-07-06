unit uDeepNesting;

// Detektor fuer zu tiefe Verschachtelung von Kontrollstrukturen.
//
// Gezaehlte Strukturen (kognitiver Aufwand):
//   if / else   → erhoehen die Tiefe
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
        if Child.Kind in COUNTING_KINDS then
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

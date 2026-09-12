unit uCyclomaticComplexity;

// Detektor fuer McCabe Cyclomatic Complexity pro Methode.
//
// McCabe definiert Komplexitaet ueber die Anzahl unabhaengiger Pfade durch
// das Kontrollfluss-Graph. Praktisch zaehlbar als 1 + Anzahl Verzweigungen:
//
//   Base                                       1
//   + if-Statement                             +1
//   + case-Arm (jeder einzelne)                +1
//   + for / while / repeat-Schleife            +1
//   + on-Handler in try/except                 +1
//   + and / or / xor BinaryOp in Bedingung     +1
//
// NICHT gezaehlt:
//   else-Branch        - binary; if hat schon +1
//   try / except / finally selbst (Resource-Handling, kein Verzweigung)
//   case-Statement-Knoten (zaehlen die Arme stattdessen)
//
// Schwelle: > MAX_CYCLOMATIC (Default: 10) bedeutet >=11. Industry-Standard
// ist 10 (Sonar/Checkstyle/PMD); hoehere Werte korrelieren mit hoeherer
// Bug-Rate und schlechterer Testbarkeit.
//
// Hinweis Boolean-Operatoren: Der Parser baut KEINE Expression-AST -
// Bedingungen werden nur als Text auf nkIfStmt.TypeRef gespeichert,
// nkWhileStmt/nkRepeatStmt/nkCaseStmt-Conditions liegen gar nicht vor.
// Wir zaehlen and/or/xor deshalb durch Wort-Scan auf if-CondTexts -
// das deckt 95% der Praxis ab. while/repeat/case-Bedingungen bleiben
// boolean-untracked (akzeptabler Trade-off vs. Parser-Erweiterung).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TCyclomaticComplexityDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  private
    class function CountInMethod(MethodNode: TAstNode): Integer; static;
    class procedure Walk(Node: TAstNode; var Count: Integer); static;
    class function CountBooleanOpsInCond(const CondText: string): Integer; static;
  end;

implementation

// noinspection-file ConsecutiveSection, RedundantJump, TooLongLine, UnsortedUses, UnusedLocalVar, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uDetectorUtils;                 // Backlog-Welle 1, 2026-07-26

class function TCyclomaticComplexityDetector.CountBooleanOpsInCond(
  const CondText: string): Integer;
// Seit Voll-Review 2026-09-12 zentral (TDetectorUtils.
// CountBooleanOpsLower, s. Begruendung dort). Wrapper bleibt.
begin
  Result := TDetectorUtils.CountBooleanOpsLower(CondText);
end;

class procedure TCyclomaticComplexityDetector.Walk(Node: TAstNode;
  var Count: Integer);
// Hardening v4: iterative DFS statt rekursiver Walk(Child, Count).
// Bei tief verschachteltem AST sprengt der Default-Stack
// (STACK_OVERFLOW $C00000FD; siehe Audit_jvcl_segfault.md).
var
  Stack : TList<TAstNode>;
  Cur   : TAstNode;
  i     : Integer;
begin
  if Node = nil then Exit;
  Stack := TList<TAstNode>.Create;
  try
    // Wichtig: Root-Knoten NICHT klassifizieren - Original-Walk iterierte
    // nur Children, nicht Self. Daher children direkt enqueuen (reverse
    // fuer Pre-Order).
    for i := Node.Children.Count - 1 downto 0 do
      Stack.Add(Node.Children[i]);
    while Stack.Count > 0 do
    begin
      Cur := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);
      case Cur.Kind of
        nkIfStmt:
          begin
            Inc(Count);
            Inc(Count, CountBooleanOpsInCond(Cur.TypeRef));
          end;
        nkForStmt, nkWhileStmt, nkRepeatStmt,
        nkCaseArm,
        nkOnHandler:
          Inc(Count);
      end;
      // Children in umgekehrter Reihenfolge auf Stack -> Pop in
      // links-rechts-Pre-Order.
      for i := Cur.Children.Count - 1 downto 0 do
        Stack.Add(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

class function TCyclomaticComplexityDetector.CountInMethod(
  MethodNode: TAstNode): Integer;
begin
  Result := 1; // McCabe-Base
  Walk(MethodNode, Result);
end;

class procedure TCyclomaticComplexityDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
  CC      : Integer;
  F       : TLeakFinding;
  MaxCC   : Integer;   // TD-1: Schwelle per-Scan aus AContext.Config
begin
  // TD-1 (2026-07-06): Schwelle einmal aus dem Context lesen (scan-konstant).
  MaxCC := CfgMaxCyclomatic(AContext);
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      CC := CountInMethod(M);
      if CC > MaxCC then
      begin
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := M.Name;
        F.LineNumber := IntToStr(M.Line);
        F.MissingVar := Format(
          'Cyclomatic complexity %d (limit: %d) - viele Verzweigungen, '+
          'schwer zu testen',
          [CC, MaxCC]);
        F.SetKind(fkCyclomaticComplexity);
        Results.Add(F);
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.

unit uLongMethod;

// Detektor fuer zu lange Methoden.
//
// Misst die Laenge des MethodenBODYS (zwischen begin..end), nicht die
// gesamte Deklaration. So werden lange Parameter-Listen oder umfangreiche
// var-Sektionen nicht faelschlich als "lange Methode" gewertet.
//
// Zusaetzlich wird die Anweisungs-Anzahl (statement count) gemeldet,
// damit lange Datendeklarations-Bloecke nicht ueberbewertet werden.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TLongMethodDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  private
    class function FindBodyBlock(MethodNode: TAstNode): TAstNode; static;
    class function FindLastLine(Node: TAstNode): Integer; static;
    class function CountStatements(Node: TAstNode): Integer; static;
  end;

implementation

// noinspection-file BeginEndRequired, NilComparison, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

// Schwellwerte werden ueber uSCAConsts.DetectorMaxBodyLines /
// DetectorMaxStatements aus analyser.ini bezogen (Defaults 50/30 wie
// die fruheren hardcoded Konstanten).

class function TLongMethodDetector.FindBodyBlock(MethodNode: TAstNode): TAstNode;
var Child: TAstNode;
begin
  Result := nil;
  for Child in MethodNode.Children do
    if Child.Kind = nkBlock then
      Exit(Child);
end;

class function TLongMethodDetector.FindLastLine(Node: TAstNode): Integer;
var
  Child     : TAstNode;
  ChildLast : Integer;
begin
  Result := Node.Line;
  for Child in Node.Children do
  begin
    if Child.Line > Result then Result := Child.Line;
    ChildLast := FindLastLine(Child);
    if ChildLast > Result then Result := ChildLast;
  end;
end;

class function TLongMethodDetector.CountStatements(Node: TAstNode): Integer;
// Zaehlt nur "echte" Anweisungen, keine reinen Deklarationen oder Bloecke.
var Child: TAstNode;
begin
  Result := 0;
  for Child in Node.Children do
  begin
    if Child.Kind in [nkAssign, nkCall, nkInherited,
                      nkRaise, nkExit, nkBreak, nkContinue,
                      nkIfStmt, nkForStmt, nkWhileStmt, nkRepeatStmt,
                      nkCaseStmt, nkTryExcept, nkTryFinally] then
      Inc(Result);
    Inc(Result, CountStatements(Child));
  end;
end;

class procedure TLongMethodDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Methods   : TList<TAstNode>;
  M         : TAstNode;
  Block     : TAstNode;
  Lines     : Integer;
  Stmts     : Integer;
  F         : TLeakFinding;
  MaxBody   : Integer;   // TD-1: Schwellen per-Scan aus AContext.Config
  MaxStmts  : Integer;
begin
  // TD-1 (2026-07-06): beide Schwellen einmal aus dem Context lesen (byte-
  // identisch - scan-konstant), dann pro Methode nur noch Local-Vergleich.
  MaxBody  := CfgMaxBodyLines(AContext);
  MaxStmts := CfgMaxStatements(AContext);
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      // Body-Block suchen (nkBlock direkt unter nkMethod)
      Block := FindBodyBlock(M);
      if Block = nil then Continue; // Forward-Decl / Interface-Decl ohne Body

      Lines := FindLastLine(Block) - Block.Line + 1;
      Stmts := CountStatements(Block);

      // Nur melden wenn BEIDE Schwellen ueberschritten:
      // verhindert false positives bei langen Datentabellen oder
      // case-Statements mit vielen kurzen Armen.
      if (Lines > MaxBody) and (Stmts > MaxStmts) then
      begin
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := M.Name;
        F.LineNumber := IntToStr(M.Line);
        F.MissingVar := Format(
          '%d body lines, %d statements (limit: %d / %d)',
          [Lines, Stmts, MaxBody, MaxStmts]);
        F.SetKind(fkLongMethod);
        Results.Add(F);
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.

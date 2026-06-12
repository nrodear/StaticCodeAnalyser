unit uCodeSmells2;

// AST-basierter Code-Smell-Detektor (Sonar-Regel #2).
//
// TEmptyExceptDetector2:
//   Erkennt leere except-Blöcke via TAstNode-Baum.
//   Ein nkExceptBlock gilt als leer wenn Children.Count = 0.
//   Nur Kommentare und Leerzeilen im except-Block → Lexer skippt sie
//   bereits → kein Kind-Knoten im AST → sicher erkennbar.
//
//   Schweregrad: lsWarning (Exception wird stillschweigend verschluckt)

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TEmptyExceptDetector2 = class
  public
    // Analysiert alle Methoden einer Unit.
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);

    // Analysiert einen einzelnen Methodenknoten.
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file CanBeStrictPrivate, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

class procedure TEmptyExceptDetector2.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  ExceptBlocks : TList<TAstNode>;
  EB           : TAstNode;
  F            : TLeakFinding;
begin
  ExceptBlocks := MethodNode.FindAll(nkExceptBlock);
  try
    for EB in ExceptBlocks do
    begin
      if EB.Children.Count > 0 then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := MethodNode.Name;
      F.LineNumber := IntToStr(EB.Line);
      F.MissingVar := 'Empty except block';
      F.SetKind(fkEmptyExcept);
      Results.Add(F);
    end;
  finally
    ExceptBlocks.Free;
  end;
end;

class procedure TEmptyExceptDetector2.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(M, FileName, Results);
  finally
    Methods.Free;
  end;
end;

end.

unit uTabulationCharacter;

// Detektor fuer Tab-Zeichen (#9) in Pascal-Source-Code.
//
// Style-Rule: Pascal-Konvention seit den 80ern ist Space-Indent. Tabs
// rendern in jedem Editor unterschiedlich (2/4/8 Spalten), brechen
// Code-Reviews und Diff-Tools.
//
// Erkennung: pure Zeilen-Scan, kein Lexer noetig. SonarDelphi-Rule
// communitydelphi:TabulationCharacter macht es genauso - Tab im Quellcode
// IST der Fund, unabhaengig davon ob er in einem String, Kommentar oder
// einer regulaeren Zeile steht. Pro Zeile genau ein Finding (auf die
// erste Tab-Position), auch wenn mehrere Tabs in einer Zeile sind.
//
// Schweregrad: lsHint - reines Style/Formatting.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TTabulationCharacterDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file CanBeClassMethod, ConsecutiveSection, GroupedDeclaration, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;
  TAB           = #9;

class procedure TTabulationCharacterDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines  : TStringList;
  i, Col : Integer;
  Cached : Boolean;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    for i := 0 to Lines.Count - 1 do
    begin
      Col := Pos(TAB, Lines[i]);
      if Col <= 0 then Continue;
      Results.Add(TLeakFinding.New(FileName, '', i + 1,
        Format('Tab character at column %d - use spaces for indentation ' +
               '(consistency across editors).', [Col]),
        fkTabulationCharacter));
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

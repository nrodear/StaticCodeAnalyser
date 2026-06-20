unit uAttributeIgnoreWithoutReason;

// Detektor: DUnitX `[Ignore]`-Attribute ohne Message-Argument.
//
// Pattern (Quality):
//   [Ignore]                          // SCHLECHT - warum ignored?
//   procedure SomeTest;
//
//   [Ignore('TBD ticket #1234')]      // GUT - dokumentiert + auffindbar
//   procedure SomeTest;
//
// Erkennung: file-text-scan pro Zeile, Regex `\[Ignore\s*\]` (ohne
// Klammer-Inhalt nach `Ignore`). Kommentare gestrippt via
// TDetectorUtils.ScanCodeLine - siehe [[detectors-ignore-comments]].
//
// Severity: lsHint, Type: ftCodeSmell.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TAttributeIgnoreWithoutReasonDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.RegularExpressions,
  uFileTextCache, uDetectorUtils;

const
  IGNORE_NO_ARG_RE = '\[Ignore\s*\]';

class procedure TAttributeIgnoreWithoutReasonDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Lines  : TStringList;
  Cached : Boolean;
  i      : Integer;
  Code   : string;
  State  : TCommentScanState;
  Dummy  : Integer;
  RE     : TRegEx;
  F      : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    State := Default(TCommentScanState);
    RE := TRegEx.Create(IGNORE_NO_ARG_RE, [roIgnoreCase]);
    for i := 0 to Lines.Count - 1 do
    begin
      Code := TDetectorUtils.ScanCodeLine(Lines[i], State, Dummy);
      try
        if not RE.IsMatch(Code) then Continue;
      except
        Continue;  // defekte Regex auf Edge-Case -> Zeile skippen
      end;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := '[Ignore] without reason message - add a string ' +
                      'arg explaining WHY the test is skipped, e.g. ' +
                      '[Ignore(''TBD ticket #1234'')].';
      F.SetKind(fkAttributeIgnoreWithoutReason);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

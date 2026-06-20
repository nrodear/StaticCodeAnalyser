unit uAttributeCategoryWithoutString;

// Detektor: `[Category]` ohne String-Argument.
//
// Pattern (DUnitX-Compile-Error):
//   [Category]              // SCHLECHT - Compile-Error in DUnitX
//   procedure Foo;
//
//   [Category('Slow')]      // GUT - argumented
//   procedure Foo;
//
// Erkennung: file-text-scan, Regex `\[Category\s*\]` (ohne Klammer-
// Inhalt). Kommentare gestrippt via TDetectorUtils.ScanCodeLine.
//
// Severity: lsError, Type: ftBug.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TAttributeCategoryWithoutStringDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.RegularExpressions,
  uFileTextCache, uDetectorUtils;

const
  CATEGORY_NO_ARG_RE = '\[Category\s*\]';

class procedure TAttributeCategoryWithoutStringDetector.AnalyzeUnit(
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
    RE := TRegEx.Create(CATEGORY_NO_ARG_RE, [roIgnoreCase]);
    for i := 0 to Lines.Count - 1 do
    begin
      Code := TDetectorUtils.ScanCodeLine(Lines[i], State, Dummy);
      try
        if not RE.IsMatch(Code) then Continue;
      except
        Continue;
      end;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := '[Category] without category-name string - DUnitX ' +
                      'requires [Category(''Name'')] with explicit name.';
      F.SetKind(fkAttributeCategoryWithoutString);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

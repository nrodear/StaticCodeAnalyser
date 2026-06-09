unit uTooLongLine;

// Detektor fuer zu lange Quelltext-Zeilen.
//
// Schwellwert: 120 Zeichen (Default). SonarDelphi-Rule
// communitydelphi:TooLongLine nutzt ebenfalls 120 als Default. Begruendung:
// passt in jeden Standard-Code-Review-Side-by-Side-Diff (2 x 120 = 240 +
// Gutter), bricht nicht in 16:9-Monitor-Drittel-Splits, ist seit den
// Sun-Java-Styleguides Industrie-Konvention.
//
// Erkennung: pure Zeilen-Scan, Length(Line) gegen Schwelle. Keine String/
// Kommentar-Awareness - eine lange Zeile ist eine lange Zeile, egal was
// drin steht.
//
// Schweregrad: lsHint - reines Style.
//
// Schwelle: Default 120, konfigurierbar via INI [Detectors] MaxLineLength.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TTooLongLineDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

class procedure TTooLongLineDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines    : TStringList;
  i, Len   : Integer;
  MaxLen   : Integer;
  F        : TLeakFinding;
  Cached   : Boolean;
begin
  // Default 120, konfigurierbar via INI [Detectors] MaxLineLength=N
  // (gespiegelt in uSCAConsts.DetectorMaxLineLength von RepoSettings).
  MaxLen := DetectorMaxLineLength;
  if MaxLen <= 0 then MaxLen := 120;
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    for i := 0 to Lines.Count - 1 do
    begin
      Len := Length(Lines[i]);
      if Len <= MaxLen then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := Format(
        'Line is %d characters (max %d) - wrap or extract subexpression.',
        [Len, MaxLen]);
      F.SetKind(fkTooLongLine);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

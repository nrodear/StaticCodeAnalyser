unit uFunctionNameResult;

// Detektor FunctionNameAsResult (SCA204) + FunctionNameRecursion (SCA205),
// Charge N / FN, 2026-10-25 (Auftrag Nico, Q5): der Name einer Funktion
// in ihrem eigenen Rumpf.
//
//   SCA204  'GetCount := FItems.Count;' - das Ergebnis ueber den
//           Funktionsnamen gesetzt (altmodische Pascal-Form). Hint, Code
//           Smell; Profile strict und style, NICHT default (Stil entscheidet
//           das Team-Profil). reDelphix ersetzt die Zuweisung durch
//           'Result :=' (uRdxFuncNameFix).
//   SCA205  'Total := Total + X;' - rechts ist der Name im Delphi-Modus ein
//           REKURSIVER AUFRUF, nicht das bisherige Ergebnis. Error fuer die
//           bewiesene Menge (parameterlos, die Funktion weist ihrem Namen
//           selbst zu, keine bewusste Rekursion daneben), sonst Warning
//           (fcMedium). Bug; Profile default, strict, bugs-only. Kein Fix:
//           ob der Wert (Result) oder die Rekursion (Name()) gemeint war,
//           weiss nur der Autor.
//
// Muster, Modus-Lage ({$mode}, {$modeswitch result}) und Sperren:
// uFuncNameResultScan (reiner Scanner ohne AST, FPC-tauglich, Praemisse per
// FPC-Probe belegt). Hier nur: Scan-Dialekt als Vorgabe fuer Dateien ohne
// {$mode} (dlFpc: Modus unbekannt -> beide Regeln still), ein Fund je Zeile
// und Regel, Schwere.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TFunctionNameResultDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

uses
  uFileTextCache, uDetectorUtils, uStaticFiles, uFuncNameResultScan;

// Ist eine Lese-Stelle auf der Zeile ALine bewiesen?
function LineProven(const AHits: TFuncNameHits; ALine: Integer): Boolean;
var
  H : TFuncNameHit;
begin
  for H in AHits do
    if (H.Use = fnuRead) and (H.Line = ALine) and H.Proven then
      Exit(True);
  Result := False;
end;

// SCA205: ein Fund je Zeile - Error, sobald eine Stelle der Zeile bewiesen
// ist; sonst Warning mit fcMedium wie SCA202/SCA203 (KindDefaultConfidence
// liefert fuer das Kind fcHigh, fcMedium bleibt im Default sichtbar).
function ReadFinding(const AFileName: string; const AHits: TFuncNameHits;
  const AHit: TFuncNameHit): TLeakFinding;
begin
  if LineProven(AHits, AHit.Line) then
    Exit(TLeakFinding.New(AFileName, AHit.Routine, AHit.Line,
      TFuncNameScan.MessageOf(AHit), fkFunctionNameRecursion));
  Result := TLeakFinding.New(AFileName, AHit.Routine, AHit.Line,
    TFuncNameScan.MessageOf(AHit), fkFunctionNameRecursion, fcMedium);
  Result.Severity := lsWarning;
end;

class procedure TFunctionNameResultDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  Lines  : TStringList;
  Cached : Boolean;
  Hits   : TFuncNameHits;
  H      : TFuncNameHit;
  Seen   : TDictionary<string, Boolean>;
  Key    : string;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    // Ganztext aus dem Context-Slot (Perf Charge P4, geteilt mit dem
    // Token-Vorfilter und SCA202). Der Scanner liest Kommentare, Strings
    // und Direktiven selbst - er braucht die {$mode}-Zeilen.
    Hits := TFuncNameScan.ScanText(TDetectorUtils.LinesTextCached(Lines,
      AContext, FileName), TStaticFiles.ScanDialect = dlDelphi);
  finally
    ReleaseLines(Lines, Cached);
  end;
  if Length(Hits) = 0 then Exit;

  // Ein Fund je Zeile und Regel ('if A then F := 1 else F := 2;' - der Fix
  // ersetzt alle Zuweisungen der Zeile).
  Seen := TDictionary<string, Boolean>.Create;
  try
    for H in Hits do
    begin
      Key := IntToStr(Ord(H.Use)) + ':' + IntToStr(H.Line);
      if Seen.ContainsKey(Key) then Continue;
      Seen.Add(Key, True);
      if H.Use = fnuAssign then
        Results.Add(TLeakFinding.New(FileName, H.Routine, H.Line,
          TFuncNameScan.MessageOf(H), fkFunctionNameAsResult))
      else
        Results.Add(ReadFinding(FileName, Hits, H));
    end;
  finally
    Seen.Free;
  end;
end;

end.

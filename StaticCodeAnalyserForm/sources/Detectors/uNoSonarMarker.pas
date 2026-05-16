unit uNoSonarMarker;

// Detektor fuer `// NOSONAR`-Suppression-Marker.
//
// SonarDelphi-Aequivalent: communitydelphi:NoSonar - dort ein Hint
// ("NOSONAR markers should not be used to silence rule violations").
// Idee: Suppressions sind technische Schuld; die Audit-Spur (wer hat
// wann was wegsupprimiert) gehoert sichtbar in den Findings-Report.
//
// Erkennung: scan-basiert. Eine Zeile enthaelt einen NOSONAR-Marker,
// wenn ein `// NOSONAR` (case-insensitive) im Zeilenkommentar steht.
// Hash-Compiler-Direktiven sind kein Treffer. String-Literale werden
// uebersprungen (sonst meldet jede Test-Source-Konstante die das Wort
// enthaelt).
//
// Schweregrad: lsHint - kein Code-Bug, nur Audit-Hinweis.
//
// Beachte: Der SCA hat sein eigenes Suppression-System (`// noinspection`
// vor der Zeile, vgl. uSuppression). NOSONAR wird hier NICHT zum
// Suppressen verwendet, sondern nur gemeldet - falls eine Codebase
// von SonarDelphi auf SCA wandert, sieht man sofort wo NOSONAR-Marker
// in `// noinspection` migriert werden muessen.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TNoSonarMarkerDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;
  MARKER         = 'NOSONAR';
  MARKER_LEN     = 7;

// Liefert die 1-basierte Spalte des `//`-Kommentar-Starts in Line, wenn
// die Zeile danach (nach evtl. Whitespace) das Wort NOSONAR enthaelt.
// 0 wenn nichts. InBlockComm / InParenStarComm werden ueber Zeilen
// hinweg mitgefuehrt: ein NOSONAR innerhalb {$...} oder (*..*) wird
// NICHT gezaehlt (SonarDelphi-Konvention: nur `//`-Marker).
function FindNoSonar(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean): Integer;
var
  i, n, p : Integer;
  InStr   : Boolean;
  pClose  : Integer;
  c       : Char;
  CmtRest : string;
begin
  Result := 0;
  InStr  := False;
  i := 1;
  n := Length(Line);
  while i <= n do
  begin
    if InBlockComm then
    begin
      pClose := PosEx('}', Line, i);
      if pClose = 0 then Exit;
      InBlockComm := False;
      i := pClose + 1; Continue;
    end;
    if InParenStarComm then
    begin
      pClose := PosEx('*)', Line, i);
      if pClose = 0 then Exit;
      InParenStarComm := False;
      i := pClose + 2; Continue;
    end;
    c := Line[i];
    if InStr then
    begin
      if c = '''' then
      begin
        if (i < n) and (Line[i + 1] = '''') then Inc(i, 2)
        else begin InStr := False; Inc(i); end;
      end
      else Inc(i);
      Continue;
    end;
    if c = '''' then begin InStr := True; Inc(i); Continue; end;
    if (c = '/') and (i < n) and (Line[i + 1] = '/') then
    begin
      // Rest der Zeile ist Zeilenkommentar. Wenn NOSONAR (case-insensitive)
      // drinsteht, Hit auf der Spalte des `//`.
      CmtRest := Copy(Line, i + 2, MaxInt);
      p := Pos(MARKER, UpperCase(CmtRest));
      if p > 0 then Result := i;
      Exit;
    end;
    if c = '{' then
    begin
      pClose := PosEx('}', Line, i + 1);
      if pClose = 0 then begin InBlockComm := True; Exit; end;
      i := pClose + 1; Continue;
    end;
    if (c = '(') and (i < n) and (Line[i + 1] = '*') then
    begin
      pClose := PosEx('*)', Line, i + 2);
      if pClose = 0 then begin InParenStarComm := True; Exit; end;
      i := pClose + 2; Continue;
    end;
    Inc(i);
  end;
end;

class procedure TNoSonarMarkerDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines  : TStringList;
  i, Col : Integer;
  InBlk, InParen : Boolean;
  F      : TLeakFinding;
  Cached : Boolean;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    InBlk   := False;
    InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Col := FindNoSonar(Lines[i], InBlk, InParen);
      if Col <= 0 then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := Format(
        'NOSONAR marker at column %d - migrate to `// noinspection` ' +
        'or fix the underlying finding.', [Col]);
      F.SetKind(fkNoSonarMarker);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

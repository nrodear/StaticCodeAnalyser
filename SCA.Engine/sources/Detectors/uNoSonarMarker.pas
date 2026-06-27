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
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TNoSonarMarkerDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file CanBeClassMethod, ConsecutiveSection, GroupedDeclaration, NilComparison, NoSonarMarker, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uFileTextCache, uDetectorUtils;

const
  MARKER = 'NOSONAR';

class procedure TNoSonarMarkerDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
// Marker zaehlen nur in `//`-Zeilenkommentaren, nicht in {..}/(*..*) oder
// String-Literalen (SonarDelphi-Konvention: NOSONAR ist ein EOL-Marker).
// Die String-/Kommentar-Zustandsmaschine lebt zentral in
// TDetectorUtils.ScanCodeLine - der Rueckgabe-Code-String wird hier
// verworfen, nur LineCommentCol (Spalte des `//`) interessiert.
var
  Lines  : TStringList;
  i, Col : Integer;
  State  : TCommentScanState;
  CmtRest: string;
  F      : TLeakFinding;
  Cached : Boolean;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    State := Default(TCommentScanState);
    for i := 0 to Lines.Count - 1 do
    begin
      TDetectorUtils.ScanCodeLine(Lines[i], State, Col);
      if Col <= 0 then Continue;                      // kein Zeilenkommentar
      // Kommentar-Inhalt ab hinter dem `//` auf den Marker pruefen.
      CmtRest := Copy(Lines[i], Col + 2, MaxInt);
      if Pos(MARKER, UpperCase(CmtRest)) <= 0 then Continue;
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

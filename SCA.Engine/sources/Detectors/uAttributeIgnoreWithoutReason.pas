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
// Erkennung: file-text-scan pro Zeile, Regex matcht `[Ignore]` UND
// `[Ignore()]` (leere Klammern = ebenfalls kein Grund). Kommentare
// gestrippt via TDetectorUtils.ScanCodeLine - siehe
// [[detectors-ignore-comments]].
//
// Severity: lsHint, Type: ftCodeSmell.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TAttributeIgnoreWithoutReasonDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

uses
  System.RegularExpressions,
  uFileTextCache, uDetectorUtils;

const
  // `[Ignore]` oder `[Ignore()]` (optional leere Klammern). Ein echtes
  // Reason-Argument (`[Ignore('...')]`) hat Inhalt zwischen den Klammern
  // und matched daher NICHT.
  IGNORE_NO_ARG_RE = '\[Ignore\s*(\(\s*\))?\s*\]';

class procedure TAttributeIgnoreWithoutReasonDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
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
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    State := Default(TCommentScanState);
    RE := TRegEx.Create(IGNORE_NO_ARG_RE, [roIgnoreCase]);
    for i := 0 to Lines.Count - 1 do
    begin
      // ScanCodeLine MUSS auch fuer uebersprungene Zeilen laufen -
      // State traegt den Kommentar-Zustand ueber die Zeilengrenze.
      Code := TDetectorUtils.ScanCodeLine(Lines[i], State, Dummy);
      // FP-Gate wie bei den vier Geschwistern der Attribut-Familie
      // (uAttributeDuplicate, -Misalignment, -CategoryWithoutString,
      // -TestFixtureWithoutTests): dieser Detektor war der einzige
      // ohne. Ohne das Gate liest der Regex einen Array-Index mit
      // einer Variablen namens 'Ignore' als Attribut.
      //
      // An der Exe belegt (Chargen-Review 2026-09-14, Posten 293):
      //   [Ignore] vor einer Methode          1 Fund  (richtig)
      //   [Ignore('kaputt')]                  0       (richtig)
      //   X := A[Ignore];                     1 Fund  FALSCH
      //   X := 1 +  /  A[Ignore];             1 Fund  FALSCH
      //
      // KORPUSWIRKUNG 0: der Regex hat ueber alle 16.024
      // Quelldateien NULL Treffer - weder echte noch falsche. Das
      // Gate ist Vorsorge, kein Aufraeumen. Es kostet dafuer auch
      // nichts: die enge Regex-Form (nur '[Ignore]' bzw.
      // '[Ignore()]') laesst ohnehin kaum Fehldeutungen zu.
      if not TDetectorUtils.IsLikelyAttributePosition(Lines, i) then
        Continue;
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

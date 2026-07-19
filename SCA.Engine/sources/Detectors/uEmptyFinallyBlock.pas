unit uEmptyFinallyBlock;

// Detektor fuer leere `finally`-Bloecke in `try..finally..end`.
//
// SonarDelphi-Aequivalent: communitydelphi:EmptyFinallyBlock. Ein leerer
// finally-Block dient meist als Refactor-Rest oder wurde "vergessen
// auszufuellen". Wenn es WIRKLICH nichts zum Aufraeumen gibt, ist
// `try..finally end;` Overhead ohne Funktion - dann reicht der `try`-
// Block alleine (bzw. mit `try..except` wenn Error-Handling benoetigt).
//
// Erkennung: Source kommentbereinigt joinen, dann Pattern `finally` Wort
// gefolgt von nur Whitespace + `end` Wort.
//
// Schweregrad: lsWarning - im Gegensatz zu leerem begin/end ist hier oft
// ein Cleanup-Gedanke vergessen worden.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TEmptyFinallyBlockDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, DeepNesting, EmptyFinallyBlock, GroupedDeclaration, IfElseBegin, LegacyInitializationSection, LongMethod, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uDetectorUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsWarning;

function IsIdent(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

class procedure TEmptyFinallyBlockDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines      : TStringList;
  Cached     : Boolean;
  Code       : string;
  Lwr        : string;
  LineFor    : TArray<Integer>;
  p, q, j    : Integer;
  c          : Char;
  IsEmpty    : Boolean;
  Between    : string;
  LineNumber : Integer;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    Code := TDetectorUtils.StripFileCommentsKeepStringsCached(Lines, LineFor, AContext, FileName);
    Lwr := LowerCase(Code);
    p := 1;
    while True do
    begin
      p := PosEx('finally', Lwr, p);
      if p = 0 then Break;
      // Wortgrenzen
      if (p > 1) and IsIdent(Code[p - 1]) then begin Inc(p); Continue; end;
      if (p + 7 <= Length(Code)) and IsIdent(Code[p + 7]) then
      begin Inc(p); Continue; end;
      // Nach `finally` zum `end` springen
      j := p + 7;
      while (j <= Length(Code)) and CharInSet(Code[j], [' ', #9, #10, #13]) do
        Inc(j);
      // `end` Wort?
      if (j + 2 > Length(Code)) then begin Inc(p, 7); Continue; end;
      if SameText(Copy(Code, j, 3), 'end') and
         ((j + 3 > Length(Code)) or not IsIdent(Code[j + 3])) then
      begin
        Between := Copy(Code, p + 7, j - p - 7);
        IsEmpty := True;
        for c in Between do
          if not CharInSet(c, [' ', #9, #10, #13]) then
          begin IsEmpty := False; Break; end;
        if IsEmpty then
        begin
          q := p - 1;
          if (q >= 0) and (q < Length(LineFor)) then
            LineNumber := LineFor[q]
          else
            LineNumber := 0;
          Results.Add(TLeakFinding.New(FileName, '', LineNumber + 1,
            'Empty `finally` block - either add the missing cleanup or ' +
            'change `try..finally end` to `try ... end`.',
            fkEmptyFinallyBlock));
        end;
      end;
      Inc(p, 7);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

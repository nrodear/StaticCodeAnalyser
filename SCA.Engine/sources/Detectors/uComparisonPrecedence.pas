unit uComparisonPrecedence;

// SCA202 ComparisonPrecedence: not/and/or/xor binden staerker als die
// Vergleiche - zwei Schreibweisen kompilieren still und tun etwas anderes,
// als sie aussehen.
//
//   K1  if not Count > 0 then        -> (not Count) > 0, bitweises not
//   K2  if A = True or B = False then -> (A = (True or B)) = False
//
// Erkennung und lexikalische Belege stehen in uComparisonPrecedenceScan
// (rein, FPC-geprueft). Hier: Datei lesen, nackte Bezeichner per
// TTypeResolver (strenger Modus = Beweis) einordnen, melden.
//
// Severity (Entscheid Nico 2026-10-23): Error nur fuer die bewiesene
// Menge, sonst Warning.
//   K1 Error: der Operand ist nachweislich nicht Boolean - Zahl oder
//      Zahlmenge rechts, Ganzzahl-Aufruf (Pos, Ord, Length, CompareText..)
//      oder .Count/.IndexOf als letztes Glied, oder der nackte Bezeichner
//      hat einen Ganzzahl-Typ. Kein Fund, wenn der Operand oder der nackte
//      Bezeichner rechts Boolean ist: (not A) = B ist dann gleichwertig.
//   K2 Error: True/False steht direkt an einem der Vergleiche (dann sind
//      die Operanden Boolean - andere Typen kompilieren gar nicht).
//
// Korpus 2026-10-23 (realworld + lazarus, 23.989 Dateien, FPC-Driver =
// Python-Nachbildung 74/74): 73 K1 - darunter echte Fehler in Lazarus
// (pascalparsertool 'not CurSection in [...]', sourcefilemanager 'not
// Result=mrOk'), JVCL, GExperts, cnwizards, python4delphi, expat-pas -
// und 1 K2 in einem xEdit-Skript.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TComparisonPrecedenceDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil); static;
  end;

implementation

uses
  uFileTextCache, uTypeResolver, uComparisonPrecedenceScan;

const
  // Ganzzahl-Typen, deren 'not' bitweise rechnet (klein, bare).
  INT_TYPES: array[0..26] of string = (
    'integer', 'cardinal', 'int64', 'uint64', 'word', 'byte', 'smallint',
    'shortint', 'longint', 'longword', 'nativeint', 'nativeuint', 'dword',
    'ptrint', 'ptruint', 'uint32', 'int32', 'uint16', 'int16', 'uint8',
    'int8', 'qword', 'sizeint', 'sizeuint', 'hresult', 'thandle',
    'tmodalresult');
  BOOL_TYPES: array[0..3] of string = (
    'boolean', 'bytebool', 'wordbool', 'longbool');

function InTypeList(const TypeLow: string; const AList: array of string): Boolean;
var
  S : string;
begin
  for S in AList do
    if S = TypeLow then
      Exit(True);
  Result := False;
end;

function MessageFor(const H: TPrecHit): string;
begin
  if H.Kind = pcNotOperand then
    Result := Format('Operator precedence: ''not %s %s ...'' is evaluated as ' +
      '''(not %s) %s ...'' - for an integer, not is the bitwise complement ' +
      'and the comparison is not negated; write ''not (%s %s ...)''',
      [H.LeftText, H.OpText, H.LeftText, H.OpText, H.LeftText, H.OpText])
  else
    Result := Format('Operator precedence: ''%s'' binds tighter than the ' +
      'comparisons - ''... %s %s %s ...'' is evaluated as ''... (%s %s %s) ...''' +
      '; put each comparison in parentheses',
      [H.OpText, H.LeftText, H.OpText, H.RightText,
       H.LeftText, H.OpText, H.RightText]);
end;

class procedure TComparisonPrecedenceDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  Lines  : TStringList;
  Cached : Boolean;
  Hits   : TPrecHits;
  H      : TPrecHit;
  TR     : TTypeResolver;
  Proven : Boolean;
  T      : string;
  F      : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    Hits := ScanPrecedence(Lines.Text);
  finally
    ReleaseLines(Lines, Cached);
  end;
  if Length(Hits) = 0 then Exit;

  TR := nil;
  try
    for H in Hits do
    begin
      Proven := H.Proven;
      if (H.Kind = pcNotOperand) and
         ((H.OperandIdent <> '') or (H.RhsIdent <> '')) and
         Assigned(UnitNode) then
      begin
        // Erst bei Bedarf: die meisten Dateien haben keinen Kandidaten.
        if TR = nil then
          TR := TTypeResolver.Create(UnitNode, False, True);
        if H.OperandIdent <> '' then
        begin
          T := TR.ResolveTypeAt(H.OperandIdent, H.Line);
          // (not B) = X / (not B) <> X ist fuer Boolean gleichwertig zu
          // not (B = X); bei <, >, in waere es das nicht, kommt mit
          // Boolean aber praktisch nicht vor (bewusstes Falsch-Negativ).
          if InTypeList(T, BOOL_TYPES) then Continue;
          if InTypeList(T, INT_TYPES) then Proven := True;
        end;
        if H.RhsIdent <> '' then
        begin
          T := TR.ResolveTypeAt(H.RhsIdent, H.Line);
          if InTypeList(T, BOOL_TYPES) then Continue;
        end;
      end;
      F := TLeakFinding.New(FileName, '', H.Line, MessageFor(H),
        fkComparisonPrecedence);
      if not Proven then
        F.Severity := lsWarning;
      Results.Add(F);
    end;
  finally
    TR.Free;
  end;
end;

end.

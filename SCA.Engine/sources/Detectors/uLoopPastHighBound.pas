unit uLoopPastHighBound;

// Detektor LoopPastHighBound (SCA203, Charge A3 / Q2, 2026-10-23): eine
// for-Schleife laeuft einen Index zu weit - 'for i := 0 to List.Count do'
// mit 'List[i]' im Rumpf, ebenso 'Length(A)', 'High(A) + 1' und die
// String-Formen '0 to Length(S)' / '1 to Length(S) + 1'. Klassischer
// Off-by-one: der Compiler meldet nichts, zur Laufzeit ERangeError ({$R+}),
// EArgumentOutOfRangeException/EStringListError (TList/TStrings) oder ein
// stiller Zugriff hinter das Ende.
//
// Muster, Waechter und Merkmale: uLoopBoundScan (reiner Scanner, ohne AST
// und ohne Typwissen). Hier nur Typbeweis, Schwere und Fund:
//   * Error nur fuer die BEWIESENE Menge (Entscheid Nico): die Sammlung ist
//     ein Bezeichner (oder 'Self.Bezeichner'), dessen Deklaration der
//     strenge Resolver in dieser Unit findet (Parameter, lokale/Inline-
//     Variable, Result, Feld der eigenen Klasse und ihrer Vorfahren in der
//     Unit, Unit-Global), und ihr Typ ist eine bekannte Liste der RTL/FCL
//     (TList, TStrings, ...), ein Array oder ein String - und der Rumpf
//     verlaesst den Durchlauf nicht vorher, vergroessert die Sammlung nicht
//     und hat keine anonyme Methode;
//   * sonst Warning (fcMedium) - oder gar nichts, wo der fehlende Beweis
//     die Aussage umdreht: '1 to X.Count' (COM-Sammlungen sind 1-basiert),
//     'Low(A) to Length(A)' (statisches 'array[1..N]' und String laufen so
//     richtig), '1 to Length(S) + 1' (nur fuer Strings gedacht),
//     ShortString/PChar bei Length (S[0] ist das Laengenbyte, P[Length]
//     die abschliessende #0), Map-Typen bei .Count (X[i] ist ein
//     Schluessel).
// Die Fundzeile ist die Zeile des 'for'; der Planer in reDelphix
// (uRdxLoopBoundFix) korrigiert den Kopf.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TLoopPastHighBoundDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

uses
  uFileTextCache, uDetectorUtils, uTypeResolver, uLoopBoundScan;

// Der Typ der Sammlung, soweit bewiesen: nur ein Bezeichner oder
// 'Self.Bezeichner' - eine laengere Kette ('Memo1.Lines') ist ein Member
// eines fremden Typs, dessen Deklaration der Resolver nicht kennt.
// ACode ist die Code-Sicht der Unit: an ihr unterscheidet KindOfResolved
// das zusammengezogene 'arrayofinteger' der klassischen var-Sektion von
// einem gleichnamigen Namenstyp 'ArrayOfInteger'.
function KindOf(AResolver: TTypeResolver; const ACollection, ACode: string;
  ALine: Integer): TLoopBoundTypeKind;
var
  Name : string;
begin
  Name := LowerCase(ACollection);
  if Copy(Name, 1, 5) = 'self.' then
    Name := Copy(Name, 6, MaxInt);
  if (Name = '') or (Pos('.', Name) > 0) then
    Exit(ltkUnknown);
  Result := TLoopBoundScan.KindOfResolved(AResolver.ResolveTypeAt(Name, ALine),
    ACode);
end;

class procedure TLoopPastHighBoundDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  Lines    : TStringList;
  Cached   : Boolean;
  Code     : string;
  LineFor  : TArray<Integer>;
  Hits     : TLoopBoundHits;
  Hit      : TLoopBoundHit;
  Resolver : TTypeResolver;
  Kind     : TLoopBoundTypeKind;
  Verdict  : TLoopBoundVerdict;
  LineNo   : Integer;
  F        : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    // Code-Sicht ohne Kommentare und mit ausgefuellten Strings - geteilt
    // mit den anderen Ganztext-Detektoren (Cache im Kontext).
    Code := TDetectorUtils.StripStringsAndCommentsCached(Lines, LineFor,
      AContext, FileName);
    Hits := TLoopBoundScan.ScanText(Code);
  finally
    ReleaseLines(Lines, Cached);
  end;
  if Length(Hits) = 0 then Exit;

  // Strenger Modus: eine Antwort ist ein Beweis; ShortString getrennt.
  Resolver := TTypeResolver.Create(UnitNode, True, True);
  try
    for Hit in Hits do
    begin
      if (Hit.ForPos < 1) or (Hit.ForPos > Length(LineFor)) then Continue;
      LineNo := LineFor[Hit.ForPos - 1] + 1;
      Kind := KindOf(Resolver, Hit.Collection, Code, LineNo);
      Verdict := TLoopBoundScan.Verdict(Hit, Kind);
      if Verdict = lbdSkip then Continue;
      F := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(LineNo);
      F.MissingVar := TLoopBoundScan.MessageOf(Hit, Kind);
      if Verdict = lbdError then
        F.SetKind(fkLoopPastHighBound)
      else
      begin
        F.SetKind(fkLoopPastHighBound, fcMedium);
        F.Severity := lsWarning;
      end;
      Results.Add(F);
    end;
  finally
    Resolver.Free;
  end;
end;

end.

unit uWithMultipleTargets;

// Detektor: `with A, B do ...` mit komma-separierten Targets.
//
// Pattern (Code Smell, klassisches Delphi-Anti-Pattern):
//   with TForm.Create(Self), TStringList.Create do
//   begin
//     Caption := 'X';     // <-- welche Klasse? Reihenfolge entscheidet
//     Add('y');           // <-- TStringList? oder eine Property von TForm?
//   end;
//
// Korrekt: einzelnes with mit explizitem alias, oder ganz ohne with:
//   F := TForm.Create(Self);
//   L := TStringList.Create;
//   try
//     F.Caption := 'X';
//     L.Add('y');
//   finally
//     L.Free;
//     F.Free;
//   end;
//
// Folge: bei `with A, B do` werden Identifiers von rechts nach links
// aufgeloest - der spaeter genannte Operand schattet den frueheren.
// Refactoring-Schmerz: einer der Typen kriegt eine neue Property mit
// gleichem Namen, und plotzlich greift der `with`-Block auf das andere
// Objekt zu. Klassischer mORMot/Legacy-Code-Smell.
//
// Erkennung (lexisch, narrow):
//   * Strip Strings + Kommentare.
//   * Pattern: `^\s*with\s+<token>\s*,` - case-insensitive, mind. ein
//     Komma vor dem `do`.
//   * Wir matchen den ANFANG der with-Klausel. Komplexe Argumente
//     (Klammer, Index, Deref) werden tolerant gehandhabt durch
//     Pattern `with\s+[^,]+,[^d]*\bdo\b`.
//
// Limitierungen:
//   * Komplexe with-Targets mit Klammern und Kommas darin
//     (`with F.Strings[i, j] do`) koennen FP geben.
//
// Schweregrad: lsHint - Stil-Empfehlung, kein direkter Bug.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TWithMultipleTargetsDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions, System.StrUtils,
  uFileTextCache, uDetectorUtils;

class procedure TWithMultipleTargetsDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines    : TStringList;
  Cached   : Boolean;
  Code     : string;
  LineFor  : TArray<Integer>;
  RE       : TRegEx;
  M        : TMatch;
  LineNo   : Integer;
  F        : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    Code := TDetectorUtils.StripStringsAndComments(Lines, LineFor, ' ');

    // Pattern: `with <target>, <target> ... do` - mit mindestens einem
    // Komma zwischen den Targets vor dem do-Keyword. Wir limitieren den
    // Scan-Bereich vor dem `do` damit nicht ein Komma in nachfolgendem
    // Code matched. Multiline-Match aktiviert.
    RE := TRegEx.Create(
      '(?ism)\bwith\s+[^,;{}\r\n]{1,200},\s*[^;{}]{1,200}\bdo\b');
    for M in RE.Matches(Code) do
    begin
      LineNo := TDetectorUtils.LineForPos(LineFor, M.Index);
      if LineNo <= 0 then LineNo := 1;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(LineNo);
      F.MissingVar :=
        '`with A, B do` resolves identifiers right-to-left - shadowing changes silently if either type adds a member';
      F.SetKind(fkWithMultipleTargets);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

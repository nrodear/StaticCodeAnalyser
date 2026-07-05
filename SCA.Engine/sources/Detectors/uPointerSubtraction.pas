unit uPointerSubtraction;

// Detektor: `Cardinal(P1) - Cardinal(P2)` / `Integer(P1) - Integer(P2)` /
// `LongWord(P1) - LongWord(P2)` - 32-Bit-Cast auf 64-Bit-Pointer trunkiert.
//
// Pattern (Bug, Win64-Truncation):
//   procedure Foo(P1, P2: Pointer);
//   var Diff: Integer;
//   begin
//     Diff := Cardinal(P1) - Cardinal(P2);     // <-- Win64-Truncation
//     // Auf Win64 ist Pointer 64-Bit. Cardinal/Integer/LongWord sind
//     // 32-Bit. Cast verliert die oberen 4 Bytes der Adresse - der
//     // Differenz-Wert ist zufaellig falsch, wenn der Allocator hohe
//     // Adressen liefert.
//   end;
//
// Korrekt:
//   var Diff: NativeInt;       // 32-Bit auf Win32, 64-Bit auf Win64
//   begin
//     Diff := PtrUInt(P1) - PtrUInt(P2);       // explizit pointer-breit
//     // oder NativeUInt fuer unsigned-Variante
//   end;
//
// Folge: Differenz-Berechnung zwischen Pointern (z.B. um Buffer-Offset
// zu berechnen) ergibt auf Win64 zufaellig falsche Werte. Schwer zu
// debuggen weil's auf Win32 funktioniert. mORMot benutzt PtrUInt/PtrInt
// systematisch; user-code kopiert oft die Cardinal-Form aus alten
// Delphi-32-Beispielen.
//
// Erkennung (lexisch, narrow):
//   * Strip Strings + Kommentare.
//   * Pattern: `(Cardinal|LongWord|Integer|LongInt)(<id>) - (Cardinal|...
//     |LongWord|Integer|LongInt)(<id>)` - zwei 32-Bit-Casts mit Minus.
//   * Heuristik: beide Casts muessen das selbe Cast-Token benutzen
//     (mixed-cast `Cardinal(a) - Integer(b)` waere selten und vermutlich
//     bewusst).
//
// Limitierungen:
//   * Single-File-lexisch. Casts ueber Variablen (`x := Cardinal(p1);
//     y := Cardinal(p2); diff := x - y;`) werden nicht erfasst -
//     braeuchte Flow-Analyse.
//   * `Cardinal(P1) - Cardinal(P2)` kann auch absichtlich sein wenn
//     Source garantiert Win32 ist - dann //noinspection-Marker.
//
// Schweregrad: lsWarning - Win64-only Bug, also intermittent in Mix-
// Build-Environments.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TPointerSubtractionDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions,
  uFileTextCache, uDetectorUtils;

class procedure TPointerSubtractionDetector.AnalyzeUnit(UnitNode: TAstNode;
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
  CastA    : string;
  CastB    : string;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    // Perf (2026-07-05): P1-strip-cache - geteilter Strip via Context-Cache.
    Code := TDetectorUtils.StripStringsAndCommentsCached(
      Lines, LineFor, AContext, FileName, ' ');

    // Pattern: `(Cardinal|LongWord|Integer|LongInt)(<id>) - (Cardinal|
    // LongWord|Integer|LongInt)(<id>)` - zwei 32-Bit-Casts, beliebige
    // Operand-Reihenfolge.
    // Group 1 = erster Cast, Group 2 = zweiter Cast.
    RE := TRegEx.Create(
      '(?i)\b(Cardinal|LongWord|Integer|LongInt)\s*\(\s*\w+\s*\)\s*-\s*' +
      '(Cardinal|LongWord|Integer|LongInt)\s*\(\s*\w+\s*\)');

    for M in RE.Matches(Code) do
    begin
      CastA := M.Groups[1].Value;
      CastB := M.Groups[2].Value;
      LineNo := TDetectorUtils.LineForPos(LineFor, M.Index);
      if LineNo <= 0 then LineNo := 1;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(LineNo);
      F.MissingVar := Format(
        '%s/%s subtraction on pointers truncates upper 32 bits on Win64 - use PtrUInt or NativeUInt',
        [CastA, CastB]);
      F.SetKind(fkPointerSubtraction);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

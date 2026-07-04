unit uStringFromPointer;

// Detektor: String(P) / AnsiString(P) / UTF8String(P) / RawByteString(P)
// Cast aus typisiertem Pointer ohne Length-Prefix-Garantie.
//
// Pattern (Bug, Buffer-Overread):
//   procedure Foo(Buf: PByte);
//   var s: string;
//   begin
//     s := string(Buf);              // <-- liest bis #0 in Buf -
//                                    //     -> Overread wenn Buf nicht
//                                    //     null-terminiert
//     s := UTF8String(SomePointer);  // <-- gleicher Bug, UTF-8-Variante
//   end;
//
// Korrekt:
//   procedure Foo(Buf: PByte; Len: Integer);
//   var s: string;
//   begin
//     SetString(s, PChar(Buf), Len); // explizite Laenge -> definiertes Ende
//     // oder UTF8DecodeToString fuer UTF-8 mit explizitem Length
//   end;
//
// Folge: Delphi behandelt PChar-Cast als null-terminierten String und
// liest bis zum naechsten #0 in Memory. Auf einem nicht-terminierten
// Buffer liest das ueber die Buffer-Grenze hinaus - Heap-Overread,
// in Worst-Case AV. mORMot benutzt diese Casts intern fuer RTTI/JSON
// (mit kontrolliertem null-Terminator); user-code kopiert die Idiom
// oft ohne den Terminator-Garantor.
//
// Erkennung (lexisch, narrow):
//   * Strip Strings + Kommentare.
//   * Pattern: `(string|RawByteString|AnsiString|UTF8String)(<id>)` wo
//     <id> mit `P` und einem Grossbuchstaben beginnt (Pointer-Konvention)
//     ODER kommt aus einer Var-Liste mit `: Pointer` Typ - praktisch nur
//     P-Praefix lexisch erkennbar.
//   * False-Positive-Filter: `string(IntegerVar)` (Integer-zu-String) ist
//     legitim - wird ausgeschlossen weil <id> nicht mit P beginnt.
//
// Limitierungen:
//   * Single-File-lexisch. Variablen vom Typ `Pointer` ohne P-Praefix
//     werden nicht erkannt.
//   * `string(PChar(x))` Double-Cast wird auch geflaggt (zur Sicherheit
//     - der innere PChar koennte aus nicht-null-terminiertem Buffer
//     kommen).
//
// Schweregrad: lsWarning - latenter Heap-Overread.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TStringFromPointerDetector = class
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

class procedure TStringFromPointerDetector.AnalyzeUnit(UnitNode: TAstNode;
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
  CastName : string;
  VarName  : string;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    Code := TDetectorUtils.StripStringsAndComments(Lines, LineFor, ' ');

    // Pattern: `(string|RawByteString|AnsiString|UTF8String|WideString)(<id>)`
    // wo <id> mit P + Grossbuchstabe beginnt (Delphi Pointer-Konvention).
    // Group 1 = Cast-Typ, Group 2 = Variable.
    RE := TRegEx.Create(
      '(?i)\b(string|RawByteString|AnsiString|UTF8String|WideString)\s*\(\s*(P[A-Z]\w*)\s*\)');

    for M in RE.Matches(Code) do
    begin
      CastName := M.Groups[1].Value;
      VarName  := M.Groups[2].Value;
      LineNo := TDetectorUtils.LineForPos(LineFor, M.Index);
      if LineNo <= 0 then LineNo := 1;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(LineNo);
      F.MissingVar := Format(
        '%s(%s) cast assumes null-terminator on raw pointer - use SetString(s, %s, Len) with explicit length',
        [CastName, VarName, VarName]);
      F.SetKind(fkStringFromPointer);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

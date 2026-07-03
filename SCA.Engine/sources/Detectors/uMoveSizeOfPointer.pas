unit uMoveSizeOfPointer;

// Detektor: Move() / FillChar() / CopyMemory() / ZeroMemory() mit
// SizeOf(<Ptr-Typ>) als Groessen-Argument.
//
// Pattern (Bug, Buffer-Overflow / Truncation):
//   var P: PByte;
//       Buf: array[0..255] of Byte;
//   begin
//     Move(Buf[0], P, SizeOf(P));        // <-- kopiert nur SizeOf(Pointer)
//                                          //     = 4/8 bytes statt 256
//   end;
//
//   FillChar(Buf, SizeOf(PByte), 0);      // <-- nur Pointer-Groesse genullt
//
// Korrekt:
//   Move(Buf[0], P^, SizeOf(Buf));        // tatsaechliche Buffer-Groesse
//   FillChar(Buf, SizeOf(Buf), 0);
//
// Folge: bei Move/FillChar mit `SizeOf(PType)` (also der Groesse eines
// Pointers, 4 bzw. 8 Byte) wird nur ein winziger Teil des eigentlichen
// Buffers angefasst - der Rest des Buffers bleibt undefiniert.
// Klassischer Bug der in 32-Bit kompiliert "funktioniert" (SizeOf(P)=4
// stimmt zufaellig fuer ein 4-Byte-Field) aber unter 64-Bit oder bei
// groesseren Records sofort kracht.
//
// Erkennung (lexisch, narrow):
//   * Strip Strings + Kommentare.
//   * Pattern: `(Move|FillChar|CopyMemory|ZeroMemory)\s*\(.*?SizeOf\s*\(\s*P[A-Z]\w+\s*\)`
//   * Erkennt nur den klassischen Pointer-Typname-Pattern (`P` +
//     Grossbuchstabe). Generische Typnamen wie `MyPtrType` werden
//     nicht erfasst - dafuer waere Type-Inferenz noetig.
//
// Limitierungen:
//   * `SizeOf(P)` wo `P` zur Compile-Zeit als Pointer-Variable bekannt
//     ist (nicht ueber Typname matchen) - nicht erkannt.
//   * Aliase auf Pointer-Typen (`type TMyHandle = PByte; ... SizeOf(TMyHandle)`)
//     werden nicht erkannt.
//
// Schweregrad: lsWarning - klarer Bug, fast nie absichtlich.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TMoveSizeOfPointerDetector = class
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

class procedure TMoveSizeOfPointerDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines    : TStringList;
  Cached   : Boolean;
  Code     : string;
  LineFor  : TArray<Integer>;
  RE       : TRegEx;
  M        : TMatch;
  Func     : string;
  PtrType  : string;
  LineNo   : Integer;
  F        : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    Code := TDetectorUtils.StripStringsAndComments(Lines, LineFor, ' ');

    // Pattern: Move/FillChar/CopyMemory/ZeroMemory mit SizeOf(P<Name>)
    // im Argumentenblock. Pointer-Typname-Konvention: `P` + Grossbuchstabe.
    // Argumentliste kann verschachtelte Klammern enthalten - wir matchen
    // alles bis zum naechsten SizeOf(Pxxx).
    RE := TRegEx.Create(
      '(?i)\b(Move|FillChar|CopyMemory|ZeroMemory)\s*\([^)]*?\bSizeOf\s*\(\s*(P[A-Z]\w+)\s*\)');
    for M in RE.Matches(Code) do
    begin
      Func    := M.Groups[1].Value;
      PtrType := M.Groups[2].Value;
      LineNo := TDetectorUtils.LineForPos(LineFor, M.Index);
      if LineNo <= 0 then LineNo := 1;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(LineNo);
      F.MissingVar := Format(
        '%s(...) uses SizeOf(%s) which is only pointer size (4/8 bytes), not the buffer size',
        [Func, PtrType]);
      F.SetKind(fkMoveSizeOfPointer);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

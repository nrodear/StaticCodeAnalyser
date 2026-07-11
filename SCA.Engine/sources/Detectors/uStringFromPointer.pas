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

function OperandIsManagedString(const Code, VarName: string;
  BeforePos: Integer): Boolean;
// FP-Gate (Real-World-FP-Audit 2026-07-10): der Cast-Regex matcht JEDEN
// Bezeichner der mit 'P'/'p' + Buchstabe beginnt - auch echte Managed-
// Strings deren Name nur zufaellig mit P anfaengt (ProcName, PrevS,
// PngFile, ParamName, ParamValue, Path, PathName). String(managedStr) ist
// eine sichere Wert-Konvertierung, KEIN Raw-Pointer-Overread - kein #0-
// Terminator wird angenommen. Wir loesen den deklarierten Typ von VarName
// aus der naechstliegenden Deklaration VOR der Nutzung auf ('name[, more]:
// Typ', inkl. const/var/out-Parameter) und unterdruecken NUR bei Managed-
// String-Typ. Pointer-Typ (LPWSTR/PChar/PAnsiChar/PWideChar/POleStr/
// Record-Pointer) oder nicht aufloesbar -> weiter melden (kein TP-Verlust,
// FP-avers). Adaptiert von uPerfHotspots.LhsDeclaredNumeric.
const
  STRTYPES : array[0..8] of string = (
    'string', 'unicodestring', 'ansistring', 'widestring', 'utf8string',
    'rawutf8', 'rawbytestring', 'shortstring', 'openstring');
var
  Before, TypeLow, T : string;
  RE : TRegEx;
  MC : TMatchCollection;
begin
  Result := False;
  if (VarName = '') or (BeforePos <= 1) then Exit;
  Before := Copy(Code, 1, BeforePos);   // Deklaration steht VOR der Nutzung
  RE := TRegEx.Create('(?i)\b' + VarName +
        '\b\s*(?:,\s*[A-Za-z_]\w*\s*)*:\s*([A-Za-z_][A-Za-z0-9_]*)');
  MC := RE.Matches(Before);
  if MC.Count = 0 then Exit;
  // naechstliegende (= letzte vor der Nutzung) Deklaration.
  TypeLow := LowerCase(MC[MC.Count - 1].Groups[1].Value);
  for T in STRTYPES do
    if TypeLow = T then Exit(True);
end;

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
    // Perf (2026-07-05): P1-strip-cache - geteilter Strip via Context-Cache.
    Code := TDetectorUtils.StripStringsAndCommentsCached(
      Lines, LineFor, AContext, FileName, ' ');

    // Pattern: `(string|RawByteString|AnsiString|UTF8String|WideString)(<id>)`
    // wo <id> mit P + Grossbuchstabe beginnt (Delphi Pointer-Konvention).
    // Group 1 = Cast-Typ, Group 2 = Variable.
    RE := TRegEx.Create(
      '(?i)\b(string|RawByteString|AnsiString|UTF8String|WideString)\s*\(\s*(P[A-Z]\w*)\s*\)');

    for M in RE.Matches(Code) do
    begin
      CastName := M.Groups[1].Value;
      VarName  := M.Groups[2].Value;
      // FP-Gate (Real-World-FP-Audit 2026-07-10): Managed-String-Operand
      // ueberspringen - String(x) ist dann sichere Wert-Konvertierung, kein
      // Heap-Overread. Bei Pointer-Typ / nicht aufloesbar weiter melden.
      if OperandIsManagedString(Code, VarName, M.Index) then Continue;
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

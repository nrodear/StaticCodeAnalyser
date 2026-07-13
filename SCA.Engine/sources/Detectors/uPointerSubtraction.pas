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
  uFileTextCache, uDetectorUtils, uTypeIndex;

function OperandDeclaredNonPointer(const Code, VarName: string;
  BeforePos: Integer; Idx: TTypeIndex): Boolean;
// FP-Gate (Real-World-FP-Audit 2026-07-10): der Cast-Subtraktions-Regex
// matcht JEDES Paar '(Cast)(a) - (Cast)(b)' - auch wenn a und b GAR KEINE
// Pointer sind, sondern Ordinal-Skalare, die legitim auf Integer/Cardinal
// verbreitert werden: Word-Zeichencodes 'Integer(C1)-Integer(C2)', Char
// 'Integer(Ch1)-Integer(Ch2)', Cardinal-Bytecode-Offsets 'Longint(FPos)-
// Longint(EPos)'. Nur die Subtraktion ECHTER Pointer trunkiert auf Win64.
// Wir loesen den deklarierten Typ von VarName aus der naechstliegenden
// Deklaration VOR der Nutzung ('name[, more]: Typ') auf (identisch zum
// bewaehrten LhsDeclaredNumeric-Muster in uPerfHotspots) und liefern nur
// True, wenn der Typ in der Nicht-Pointer-Skalarliste steht.
// 'Pointer'/'P<Xxx>'/'^T'/Klassen-/Interface-/Enum-/Record-Typen sind NICHT
// in der Liste -> resolven zu False -> Fund bleibt (kein TP-Verlust). Nicht
// aufloesbar -> False -> Fund bleibt (kein FN). Unterdrueckt wird der Fund
// nur, wenn BEIDE Operanden hier True liefern (siehe Aufrufstelle).
const
  NONPTRTYPES : array[0..24] of string = (
    'integer', 'cardinal', 'word', 'byte', 'smallint', 'shortint',
    'longint', 'longword', 'int64', 'uint64', 'dword', 'char', 'ansichar',
    'widechar', 'wordbool', 'bytebool', 'boolean', 'uint32', 'int32',
    'uint16', 'int16', 'uint8', 'int8', 'longbool', 'ucs4char');
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
  for T in NONPTRTYPES do
    if TypeLow = T then Exit(True);
  // SCA161-enum Cross-Unit-Opt-in (2026-07-13): der deklarierte Typ ist ein
  // benutzerdefinierter ENUM (auch aus einer anderen Unit, ueber den repo-weiten
  // TTypeIndex aufgeloest). Enums sind Ordinaltypen -> 'Integer(e1)-Integer(e2)'
  // ist valide Ordinalarithmetik, KEINE 64-Bit-Adress-Trunkierung. tkiEnum ist
  // ein direkter Fakt (Parser nkEnumType / Seed), kein Vererbungs-Ambiguitaet
  // -> kein FN-Risiko. nil/leerer Index (Tests/Single-File) -> uebersprungen,
  // bisheriges Verhalten (byte-identisch).
  if (Idx <> nil) and (Idx.TypeKindOf(TypeLow) = tkiEnum) then
    Exit(True);
end;

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
  OperA    : string;
  OperB    : string;
  Idx      : TTypeIndex;
begin
  Idx := CtxTypeIndex(AContext);   // SCA161-enum Cross-Unit-Opt-in (nil ohne Pipeline)
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
    // Group 1 = erster Cast, Group 2 = erster Operand, Group 3 = zweiter
    // Cast, Group 4 = zweiter Operand (fuer die Typ-Aufloesung im FP-Gate).
    RE := TRegEx.Create(
      '(?i)\b(Cardinal|LongWord|Integer|LongInt)\s*\(\s*(\w+)\s*\)\s*-\s*' +
      '(Cardinal|LongWord|Integer|LongInt)\s*\(\s*(\w+)\s*\)');

    for M in RE.Matches(Code) do
    begin
      CastA := M.Groups[1].Value;
      OperA := M.Groups[2].Value;
      CastB := M.Groups[3].Value;
      OperB := M.Groups[4].Value;

      // FP-Gate (Real-World-FP-Audit 2026-07-10): nur wenn BEIDE Operanden
      // nachweislich Nicht-Pointer-Skalare sind (deklariert Word/Char/
      // Cardinal/Integer/...), kann keine 64-Bit-Pointer-Adresse trunkiert
      // werden -> unterdruecken. Loest EIN Operand nicht auf oder ist ein
      // Pointer/Klasse/Enum -> weiter melden (kein TP-Verlust, kein FN).
      if OperandDeclaredNonPointer(Code, OperA, M.Index, Idx)
         and OperandDeclaredNonPointer(Code, OperB, M.Index, Idx) then
        Continue;

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

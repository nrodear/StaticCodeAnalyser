unit uIntegerOverflow;

// Detektor: Int64-Ziel-Variable bekommt Produkt zweier Operanden ohne
// Int64-Cast eines Operanden - die Multiplikation overflow'ed in 32-Bit
// BEVOR die Erweiterung auf Int64 stattfindet.
//
// Pattern (Bug, Sonar-50 #14):
//   var BytesTotal: Int64;
//   begin
//     BytesTotal := SectorCount * SectorSize;   // <-- Int32 overflow,
//                                                //     dann erst Int64-
//                                                //     Konvertierung
//   end;
//
// Korrekt:
//   BytesTotal := Int64(SectorCount) * SectorSize;
//   // oder:
//   BytesTotal := SectorCount * Int64(SectorSize);
//
// Delphi-Detail: bei `<Int64> := <a> * <b>` mit a, b : Integer evaluiert
// der Compiler `a * b` in Integer-Arithmetik (32-Bit), dann widensthe
// Result auf Int64. Wenn das Produkt nicht in 32-Bit passt, ist der Wert
// schon zerstoert.
//
// Erkennung (lexisch, narrow):
//   * Strip Strings + Kommentare.
//   * Pattern: `<lhs> := <a> * <b>;` wobei lhs eine Variable ist, deren
//     deklarierter Typ Int64 / UInt64 / QWord enthaelt.
//   * a und b sind beide simple Identifier (keine Casts, keine
//     Klammern-Ausdruecke).
//   * Wenn EINER der Operanden ein Cast in eine Int64-Familie ist
//     (Int64(...), UInt64(...), QWord(...)), kein Befund.
//   * Wenn EINER der Operanden ein Literal ist (z.B. `i * 1024`), kein
//     Befund - dort kann der Compiler ggf. statisch erkennen.
//
// Limitierungen:
//   * Keine Typ-Inferenz: a und b koennen schon Int64 sein - wir flaggen
//     trotzdem (FP). Workaround: explizit casten oder noinspection-Marker.
//   * `+` / `-` werden NICHT geprueft - viel seltener problematisch.
//   * Komplexe Ausdruecke (`(a + b) * c`) werden nicht gematcht.
//
// Schweregrad: lsError - silent corruption.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TIntegerOverflowDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, NestedTry, NilComparison, RedundantBoolean, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions, System.StrUtils,
  uFileTextCache;

const
  INT64_TYPES : array[0..2] of string = ('int64', 'uint64', 'qword');

var
  // Lazy-Cache (Round 11): Patterns sind konstant. Spart 2 Compilations
  // pro File pro Scan.
  CachedReVarDecl : TRegEx;
  CachedReAssign  : TRegEx;
  CachedReInit    : Boolean = False;

procedure EnsureRegexCacheBuilt;
begin
  if CachedReInit then Exit;
  CachedReVarDecl := TRegEx.Create('(?im)\b(\w+)\s*:\s*(Int64|UInt64|QWord)\b');
  CachedReAssign  := TRegEx.Create('(?im)\b(\w+)\s*:=\s*(\w+)\s*\*\s*(\w+)\s*;');
  CachedReInit    := True;
end;

// True wenn TypeText eines der Int64-Familien-Typen ist.
function IsInt64Type(const TypeText: string): Boolean;
var
  Low : string;
  T   : string;
begin
  Low := LowerCase(Trim(TypeText));
  for T in INT64_TYPES do
    if Low = T then Exit(True);
  Result := False;
end;

// Strip strings + comments aus Lines, erhaelt Positionen.
function StripStringsAndComments(Lines: TStringList; out LineForChar: TArray<Integer>): string;
var
  Buf            : TStringBuilder;
  Chars          : TList<Integer>;
  i, n, j        : Integer;
  Line           : string;
  InBlk, InParen : Boolean;
  InStr          : Boolean;
  c              : Char;
  pClose         : Integer;
begin
  Buf := TStringBuilder.Create;
  Chars := TList<Integer>.Create;
  try
    InBlk := False; InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i]; InStr := False; j := 1; n := Length(Line);
      while j <= n do
      begin
        if InBlk then
        begin
          pClose := PosEx('}', Line, j);
          if pClose = 0 then Break;
          InBlk := False; j := pClose + 1; Continue;
        end;
        if InParen then
        begin
          pClose := PosEx('*)', Line, j);
          if pClose = 0 then Break;
          InParen := False; j := pClose + 2; Continue;
        end;
        c := Line[j];
        if InStr then
        begin
          Buf.Append(' '); Chars.Add(i);
          if c = '''' then
          begin
            if (j < n) and (Line[j + 1] = '''') then
            begin Buf.Append(' '); Chars.Add(i); Inc(j, 2); end
            else begin InStr := False; Inc(j); end;
          end else Inc(j);
          Continue;
        end;
        if c = '''' then
        begin Buf.Append(' '); Chars.Add(i); InStr := True; Inc(j); Continue; end;
        if (c = '/') and (j < n) and (Line[j + 1] = '/') then Break;
        if c = '{' then
        begin
          pClose := PosEx('}', Line, j + 1);
          if pClose = 0 then begin InBlk := True; Break; end;
          j := pClose + 1; Continue;
        end;
        if (c = '(') and (j < n) and (Line[j + 1] = '*') then
        begin
          pClose := PosEx('*)', Line, j + 2);
          if pClose = 0 then begin InParen := True; Break; end;
          j := pClose + 2; Continue;
        end;
        Buf.Append(c); Chars.Add(i);
        Inc(j);
      end;
      Buf.Append(#10); Chars.Add(i);
    end;
    Result := Buf.ToString;
    LineForChar := Chars.ToArray;
  finally
    Chars.Free; Buf.Free;
  end;
end;

function LineForPos(const LineFor: TArray<Integer>; APos: Integer): Integer;
begin
  if (APos >= 1) and (APos - 1 < Length(LineFor)) then
    Result := LineFor[APos - 1] + 1
  else
    Result := 0;
end;

class procedure TIntegerOverflowDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines    : TStringList;
  Cached   : Boolean;
  Code     : string;
  LineFor  : TArray<Integer>;
  Int64Vars : TStringList;
  M  : TMatch;
  Name, TypeText : string;
  Lhs, A, B : string;
  ALow, BLow : string;
  F  : TLeakFinding;
  LineNo : Integer;
begin
  EnsureRegexCacheBuilt;
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    Code := StripStringsAndComments(Lines, LineFor);

    // Phase 1: Int64-Variablen sammeln. Pattern: `<ident>[, <ident>]*: Int64;`
    // Einzelnamen, kein Komma-Spread (TStringList-Vereinfachung).
    Int64Vars := TStringList.Create;
    try
      Int64Vars.CaseSensitive := False;
      Int64Vars.Sorted := True;
      Int64Vars.Duplicates := dupIgnore;
      for M in CachedReVarDecl.Matches(Code) do
      begin
        Name := M.Groups[1].Value;
        TypeText := M.Groups[2].Value;
        if IsInt64Type(TypeText) then
          Int64Vars.Add(LowerCase(Name));
      end;
      if Int64Vars.Count = 0 then Exit;

      // Phase 2: Assignments mit Produkt-RHS finden.
      // Pattern: `<lhs> := <a> * <b>;` mit lhs in Int64Vars und a, b
      // simple Identifier ohne Cast.
      for M in CachedReAssign.Matches(Code) do
      begin
        Lhs := M.Groups[1].Value;
        A   := M.Groups[2].Value;
        B   := M.Groups[3].Value;
        ALow := LowerCase(A);
        BLow := LowerCase(B);
        // Cast-Form schon ausgeschlossen weil `(` nicht im \w-Match.
        // Aber: a / b koennten Literale sein - dann \w matcht weil Zahlen
        // auch zu \w gehoeren. Skip wenn einer ein Zahlen-Literal ist.
        if (Length(A) > 0) and CharInSet(A[1], ['0'..'9']) then Continue;
        if (Length(B) > 0) and CharInSet(B[1], ['0'..'9']) then Continue;
        // Skip wenn einer der Operanden selbst eine Int64-Variable ist
        // (dann promoted der Compiler die Multiplikation automatisch).
        if (Int64Vars.IndexOf(ALow) >= 0) or (Int64Vars.IndexOf(BLow) >= 0) then
          Continue;
        // Lhs muss Int64 sein.
        if Int64Vars.IndexOf(LowerCase(Lhs)) < 0 then Continue;

        LineNo := LineForPos(LineFor, M.Index);
        if LineNo <= 0 then LineNo := 1;

        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(LineNo);
        F.MissingVar := Format(
          '%s := %s * %s - product overflows in 32-bit before widening to Int64; cast one operand to Int64',
          [Lhs, A, B]);
        F.SetKind(fkIntegerOverflow);
        Results.Add(F);
      end;
    finally
      Int64Vars.Free;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

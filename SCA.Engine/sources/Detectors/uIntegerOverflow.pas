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
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TIntegerOverflowDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, NestedTry, NilComparison, RedundantBoolean, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions,
  uFileTextCache, uDetectorUtils;

const
  INT64_TYPES : array[0..2] of string = ('int64', 'uint64', 'qword');

var
  // Lazy-Cache (Round 11): Patterns sind konstant. Spart 2 Compilations
  // pro File pro Scan.
  CachedReVarDecl : TRegEx;
  CachedReAssign  : TRegEx;
  // Real-World-FP-Audit 2026-07-12 (FP-Klasse 'scope-blinde file-globale
  // Var-Sammlung'): fuer die per-Method-Scope-Aufteilung der Ziel-Erkennung.
  CachedReImpl    : TRegEx;   // Interface/Implementation-Grenze
  CachedReHeader  : TRegEx;   // Routinen-Header (Region-Start)
  CachedReInit    : Boolean = False;

procedure EnsureRegexCacheBuilt;
begin
  if CachedReInit then Exit;
  CachedReVarDecl := TRegEx.Create('(?im)\b(\w+)\s*:\s*(Int64|UInt64|QWord)\b');
  CachedReAssign  := TRegEx.Create('(?im)\b(\w+)\s*:=\s*(\w+)\s*\*\s*(\w+)\s*;');
  CachedReImpl    := TRegEx.Create('(?im)\bimplementation\b');
  CachedReHeader  := TRegEx.Create(
    '(?im)^[ \t]*(?:class[ \t]+)?(?:procedure|function|constructor|destructor|operator)\b');
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

// Real-World-FP-Audit 2026-07-12 (FP-Klasse 'scope-blinde file-globale
// Var-Sammlung'): blendet alle geklammerten Bereiche (...) - inkl.
// geschachtelter und mehrzeiliger - aus, indem der Inhalt (und die Klammern
// selbst) durch Leerzeichen ersetzt wird. Damit fallen Parameter-
// Deklarationen fremder Routinen (z.B. 'procedure SetInt64(var result: Int64)')
// bei der FILE-LEVEL-Sammlung raus - nur echte Felder/Globals (die NIE in
// Klammern stehen) bleiben als datei-globale Int64-Ziele erhalten.
function BlankParens(const S: string): string;
var
  i, Depth : Integer;
  C        : Char;
begin
  Result := S;                      // Copy-on-write: erste Zuweisung dupliziert
  Depth  := 0;
  for i := 1 to Length(Result) do
  begin
    C := Result[i];
    if C = '(' then
    begin
      Inc(Depth);
      Result[i] := ' ';
    end
    else if C = ')' then
    begin
      if Depth > 0 then Dec(Depth);
      Result[i] := ' ';
    end
    else if Depth > 0 then
      Result[i] := ' ';
  end;
end;

// Sammelt alle Int64/UInt64/QWord-Variablennamen (lowercase) aus AText in ADest.
procedure CollectInt64VarsInto(const AText: string; ADest: TStringList);
var
  M : TMatch;
begin
  for M in CachedReVarDecl.Matches(AText) do
    if IsInt64Type(M.Groups[2].Value) then
      ADest.Add(LowerCase(M.Groups[1].Value));
end;

class procedure TIntegerOverflowDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines    : TStringList;
  Cached   : Boolean;
  Code     : string;
  LineFor  : TArray<Integer>;
  Int64Vars     : TStringList;   // datei-global: NUR Operand-Promotion-Check
  FileLevelVars : TStringList;   // Felder/Globals: gueltiges Ziel in JEDER Routine
  RegionLocal   : TStringList;   // lokale Vars/Parameter der aktuellen Routine
  HeaderPos     : TList<Integer>;
  M, MImpl : TMatch;
  Lhs, A, B : string;
  ALow, BLow, LhsLow : string;
  F  : TLeakFinding;
  LineNo : Integer;
  ImplPos, FirstHeaderPos, P, NextBound, RegionCursor, LastBuilt : Integer;

  // Ziel-Klassifikation (LHS) ist PER-METHOD-SCOPE: gueltig sind nur
  // Felder/Globals (FileLevelVars) plus die Deklarationen der Routine, die
  // die Zuweisung enthaelt (RegionLocal).
  function IsInt64Target(const NLow: string): Boolean;
  begin
    Result := (FileLevelVars.IndexOf(NLow) >= 0) or
              (RegionLocal.IndexOf(NLow) >= 0);
  end;

begin
  EnsureRegexCacheBuilt;
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    // Perf (2026-07-05): P1-strip-cache - geteilter Strip via Context-Cache.
    Code := TDetectorUtils.StripStringsAndCommentsCached(
      Lines, LineFor, AContext, FileName, ' ');

    // Fast-Reject: ohne irgendeine Int64/UInt64/QWord-Deklaration kein Befund
    // moeglich - spart die Segmentierung unten fuer die grosse Mehrheit.
    if not CachedReVarDecl.IsMatch(Code) then Exit;

    Int64Vars     := TStringList.Create;
    FileLevelVars := TStringList.Create;
    RegionLocal   := TStringList.Create;
    HeaderPos     := TList<Integer>.Create;
    try
      Int64Vars.CaseSensitive := False;
      Int64Vars.Sorted := True;
      Int64Vars.Duplicates := dupIgnore;
      FileLevelVars.CaseSensitive := False;
      FileLevelVars.Sorted := True;
      FileLevelVars.Duplicates := dupIgnore;
      RegionLocal.CaseSensitive := False;
      RegionLocal.Sorted := True;
      RegionLocal.Duplicates := dupIgnore;

      // Datei-globale Int64-Menge - unveraendert zum Alt-Verhalten und NUR fuer
      // den Operand-Promotion-Check verwendet. Absichtlich global gehalten,
      // damit das Scoping keine bisher unterdrueckten Befunde NEU demaskiert
      // (konservativ: Fix schliesst FPs, oeffnet keine neuen).
      CollectInt64VarsInto(Code, Int64Vars);
      if Int64Vars.Count = 0 then Exit;

      // Real-World-FP-Audit 2026-07-12, FP-Klasse 'scope-blinde file-globale
      // Var-Sammlung': Die Ziel-Erkennung (LHS) wird PER-METHOD-SCOPE. Ein
      // 'var result: Int64'-PARAMETER unbeteiligter Prozeduren (z.B.
      // SetInt64/SetQWord) darf 'result' in einer ANDEREN Routine
      // (z.B. TLecuyer.NextDouble:double, wo 'result' der double-Return ist)
      // NICHT als Int64-Ziel klassifizieren.
      //
      // File-Level-Ziele = Felder/Globals: der gesamte Interface- + Impl-Pre-
      // Routine-Bereich, mit AUSgeblendeten Klammern (BlankParens), damit
      // Parameter-Deklarationen fremder Routinen NICHT einflieszen. Felder
      // stehen nie in Klammern und bleiben daher erhalten (z.B.
      // 'fEngineExpireTimeOutTix: Int64;' - echter TP, muss Fund bleiben).
      MImpl := CachedReImpl.Match(Code);
      if MImpl.Success then ImplPos := MImpl.Index else ImplPos := 1;

      // Routinen-Header AB der implementation-Grenze sammeln (Interface-
      // Methoden-Deklarationen zaehlen NICHT als Region - deren Felder sollen
      // file-level bleiben).
      for M in CachedReHeader.Matches(Code) do
        if M.Index >= ImplPos then HeaderPos.Add(M.Index);

      if HeaderPos.Count > 0 then FirstHeaderPos := HeaderPos[0]
      else FirstHeaderPos := Length(Code) + 1;

      CollectInt64VarsInto(
        BlankParens(Copy(Code, 1, FirstHeaderPos - 1)), FileLevelVars);

      // Assignments mit Produkt-RHS finden.
      // Pattern: `<lhs> := <a> * <b>;` mit lhs Int64-Ziel im Scope und a, b
      // simple Identifier ohne Cast.
      RegionCursor := -1;
      LastBuilt    := -2;
      for M in CachedReAssign.Matches(Code) do
      begin
        Lhs := M.Groups[1].Value;
        A   := M.Groups[2].Value;
        B   := M.Groups[3].Value;
        ALow   := LowerCase(A);
        BLow   := LowerCase(B);
        LhsLow := LowerCase(Lhs);
        // Cast-Form schon ausgeschlossen weil `(` nicht im \w-Match.
        // Aber: a / b koennten Literale sein - dann \w matcht weil Zahlen
        // auch zu \w gehoeren. Skip wenn einer ein Zahlen-Literal ist.
        if (Length(A) > 0) and CharInSet(A[1], ['0'..'9']) then Continue;
        if (Length(B) > 0) and CharInSet(B[1], ['0'..'9']) then Continue;
        // Skip wenn einer der Operanden selbst eine Int64-Variable ist
        // (dann promoted der Compiler die Multiplikation automatisch).
        // Bewusst GEGEN die datei-globale Menge (Alt-Verhalten, s.o.).
        if (Int64Vars.IndexOf(ALow) >= 0) or (Int64Vars.IndexOf(BLow) >= 0) then
          Continue;

        // Region der Zuweisung bestimmen (Matches sind index-sortiert, daher
        // reicht ein vorwaerts-laufender Cursor). RegionLocal wird nur bei
        // Regionwechsel neu aufgebaut.
        P := M.Index;
        while (RegionCursor + 1 < HeaderPos.Count) and
              (HeaderPos[RegionCursor + 1] <= P) do
          Inc(RegionCursor);
        if RegionCursor <> LastBuilt then
        begin
          RegionLocal.Clear;
          if RegionCursor >= 0 then
          begin
            if RegionCursor + 1 < HeaderPos.Count then
              NextBound := HeaderPos[RegionCursor + 1]
            else
              NextBound := Length(Code) + 1;
            CollectInt64VarsInto(
              Copy(Code, HeaderPos[RegionCursor],
                   NextBound - HeaderPos[RegionCursor]),
              RegionLocal);
          end;
          LastBuilt := RegionCursor;
        end;

        // Lhs muss Int64-Ziel IM SCOPE sein (per-Method + Felder/Globals).
        if not IsInt64Target(LhsLow) then Continue;

        LineNo := TDetectorUtils.LineForPos(LineFor, M.Index);
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
      HeaderPos.Free;
      RegionLocal.Free;
      FileLevelVars.Free;
      Int64Vars.Free;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

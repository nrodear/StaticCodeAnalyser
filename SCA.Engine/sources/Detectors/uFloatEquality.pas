unit uFloatEquality;

// Detektor: `=` oder `<>` zwischen Float-Operanden (Single/Double/Extended/
// Real/Currency).
//
// Pattern (Bug, Sonar-50 #19):
//   var Ratio: Double;
//   begin
//     ...
//     if Ratio = 0.5 then           // <- IEEE-754 macht das fast nie wahr
//       DoStuff;
//   end;
//
// Korrekt:
//   if SameValue(Ratio, 0.5, 1e-9) then DoStuff;
//   // oder Math.IsZero / Math.IsZero(Ratio - 0.5)
//
// Folge: bei Float-Arithmetik garantiert IEEE-754 keine exakte Gleichheit -
// `0.1 + 0.2 = 0.3` ergibt False. Equality-Checks sind silent-bug, weil sie
// in 99% der Faelle plausibel aussehen aber gelegentlich falsch laufen.
//
// Erkennung (lexisch, narrow):
//   * Strip Strings + Kommentare.
//   * Phase 1: sammle Float-Variablen aus Deklarationen.
//     Pattern: `<ident>: Single|Double|Extended|Real|Currency;`
//   * Phase 2: scanne nach ` <ident> = <expr> ` oder ` <expr> = <ident> `
//     in if-/while-/until-Kontexten, wo <ident> aus der Float-Var-Liste
//     stammt. Operator-Match auch fuer `<>`.
//
// FP-Schutz fuer Scope-Blindheit:
//   Wenn 'Value' in einer Float-Record-Felddeklaration vorkommt UND
//   gleichzeitig ein anderer Pointer-/Boolean-Parameter den gleichen
//   Namen hat, wuerde der Detector ohne Filter `Value = nil` flaggen.
//   NEVER_FLOAT_TOKENS (nil/true/false) wird als Operand explizit
//   ausgeschlossen - das sind nie Floats.
//
// Limitierungen:
//   * Keine Type-Inferenz fuer Function-Returns oder Parameter
//   * Konstante Literale (`0.5`, `1.0`) auf einer Seite werden korrekt
//     erkannt wenn die andere Seite eine Float-Var ist.
//   * Komplexere Ausdruecke (`a + b = c + d`) muessen mindestens EINEN
//     Float-Var-Operanden enthalten damit der Detector triggert.
//
// Schweregrad: lsWarning - Sonar-50 #19.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TFloatEqualityDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, CyclomaticComplexity, GroupedDeclaration, LongMethod, NestedTry, NilComparison, RedundantBoolean, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions,
  uFileTextCache, uDetectorUtils, uTypeResolver;

const
  FLOAT_TYPES : array[0..4] of string =
    ('single', 'double', 'extended', 'real', 'currency');

  // Tokens die syntaktisch ein Operand sein koennen, semantisch aber NIE
  // ein Float-Wert sind. Wenn eine Seite des '='-Vergleichs eines davon
  // ist, ist es kein Float-Equality - egal ob die andere Seite zufaellig
  // mit einer Float-Var-Namens-Kollision matched.
  //
  // Realer FP-Trigger: NullableString.Implicit(const Value: Pointer) hat
  //   if Value = nil then ...
  // Detector hat in FloatVars ein 'value' von NullableSingle.Value: Single
  // -> Lhs.IndexOf('value') matched, ohne Scope-Awareness flaggt er. Mit
  // dieser Liste wird 'nil' rausgefiltert bevor das Finding generiert wird.
  NEVER_FLOAT_TOKENS : array[0..2] of string =
    ('nil', 'true', 'false');

  // Real-World-FP-Audit 2026-07-10: bekannte NICHT-Float-Typen (Ordinal/
  // Integer/Boolean/String/Pointer). Wenn ein Float-benannter Operand zur
  // Nutzung NAECHSTLIEGEND als einer dieser Typen deklariert ist, ist der
  // FloatVars-Namenstreffer scope-blind (Kollision) und der '='/'<>'-Fund
  // ein FP.
  NONFLOAT_ORDINAL_TYPES : array[0..29] of string = (
    'integer', 'cardinal', 'int64', 'uint64', 'word', 'byte', 'smallint',
    'shortint', 'longint', 'longword', 'nativeint', 'nativeuint', 'int8',
    'int16', 'int32', 'uint8', 'uint16', 'uint32', 'dword', 'boolean',
    'bytebool', 'wordbool', 'longbool', 'char', 'ansichar', 'widechar',
    'string', 'ansistring', 'widestring', 'pointer');

var
  // Lazy-Cache (Round 11): konstante Patterns einmalig kompilieren.
  CachedReDecl  : TRegEx;
  CachedReEqual : TRegEx;
  CachedReInit  : Boolean = False;

procedure EnsureRegexCacheBuilt;
begin
  if CachedReInit then Exit;
  CachedReDecl  := TRegEx.Create('(?im)\b(\w+)\s*:\s*(Single|Double|Extended|Real|Currency)\b');
  CachedReEqual := TRegEx.Create('(?i)\b(\w+(?:\.\w+)?)\s*(=|<>)\s*([\w.]+)');
  CachedReInit  := True;
end;

function IsFloatType(const TypeText: string): Boolean;
var
  Low : string;
  T   : string;
begin
  Low := LowerCase(Trim(TypeText));
  for T in FLOAT_TYPES do
    if Low = T then Exit(True);
  Result := False;
end;

function IsNeverFloatToken(const TokenLow: string): Boolean;
// TokenLow ist bereits lowercased - direkter Vergleich.
var T : string;
begin
  for T in NEVER_FLOAT_TOKENS do
    if TokenLow = T then Exit(True);
  Result := False;
end;

// Real-World-FP-Audit 2026-07-10: klassifiziert einen aufgeloesten
// Deklarationstyp. Exakter Float-Typ -> False (weiter melden). Bekannter
// Ordinal-/Boolean-/String-/Pointer-Typ ODER Delphi-Namenskonvention T*
// (Klasse/Record) / I* (Interface) / P* (Pointer) -> True (unterdruecken).
// Unbekannt (z.B. Nutzertyp-Alias) -> False, damit kein TP verlorengeht.
function ResolvedTypeIsNonFloat(const TypeName: string): Boolean;
var
  Low, T : string;
begin
  Result := False;
  Low := LowerCase(Trim(TypeName));
  if Low = '' then Exit;
  for T in FLOAT_TYPES do
    if Low = T then Exit(False);
  for T in NONFLOAT_ORDINAL_TYPES do
    if Low = T then Exit(True);
  // Review-Fix 2026-07-11: die T/I/P-Praefix-Heuristik ENTFERNT - sie
  // unterdrueckte auch Float-Aliase wie 'TFloat' (T-Praefix) -> FN auf echter
  // Float-Gleichheit. Nur exakte NONFLOAT_ORDINAL_TYPES gelten jetzt als
  // Nicht-Float; unaufgeloest/sonstiges -> weiter melden (kein TP-Verlust).
end;

// Real-World-FP-Audit 2026-07-10: FloatVars ist ein reiner Namensindex und
// damit scope-blind - eine Kennung die IRGENDWO als Single/Double deklariert
// ist matcht auch dort, wo dieselbe Kennung lokal als Integer/Cardinal/Int32,
// als Klassen-/Interface-Feld (z.B. TdwsJSONValue) oder als Result eines
// Ordinaltyps auftritt. Wir loesen den zur Nutzung NAECHSTLIEGENDEN
// deklarierten Typ auf (Muster 'name[, more]: Typ'; fuer 'Result' den
// Rueckgabetyp der umschliessenden function). Loest er zu einem
// NICHT-Float-Typ auf -> unterdruecken. Nicht aufloesbar oder exakter
// Float-Typ -> weiter melden (kein TP-Verlust / kein FN).
function OperandDeclaredNonFloat(const Code, VarName: string;
  BeforePos: Integer): Boolean;
var
  Before, TypeStr : string;
  RE : TRegEx;
  MC : TMatchCollection;
begin
  Result := False;
  if (VarName = '') or (BeforePos <= 1) or (Pos('.', VarName) > 0) then Exit;
  if not CharInSet(VarName[1], ['A'..'Z', 'a'..'z', '_']) then Exit;
  if BeforePos > Length(Code) then BeforePos := Length(Code);
  Before := Copy(Code, 1, BeforePos);   // Deklaration steht VOR der Nutzung
  TypeStr := '';
  // 1) var/param/Feld-Deklaration 'VarName[, weitere]: Typ' - naechstliegende.
  RE := TRegEx.Create('(?i)\b' + VarName +
        '\b\s*(?:,\s*[A-Za-z_]\w*\s*)*:\s*([A-Za-z_][A-Za-z0-9_]*)');
  MC := RE.Matches(Before);
  if MC.Count > 0 then
    TypeStr := MC[MC.Count - 1].Groups[1].Value
  else if SameText(VarName, 'result') then
  begin
    // 2) Result -> Rueckgabetyp der naechstliegenden function-Signatur.
    RE := TRegEx.Create(
      '(?i)\bfunction\s+[\w.]+\s*(?:\([^)]*\))?\s*:\s*([A-Za-z_][A-Za-z0-9_]*)');
    MC := RE.Matches(Before);
    if MC.Count > 0 then
      TypeStr := MC[MC.Count - 1].Groups[1].Value;
  end;
  if TypeStr = '' then Exit;   // nicht aufloesbar -> weiter melden (kein FN)
  Result := ResolvedTypeIsNonFloat(TypeStr);
end;

// Real-World-FP-Audit 2026-07-10: liefert True wenn direkt vor der Kennung
// an IdentStart das Keyword 'const' steht. Eine Inline-/Sektions-Konstante
// 'const deltaT = 1/(...)' bindet einen Wert und ist KEIN '='-Vergleich.
function PrecededByConstKeyword(const Code: string; IdentStart: Integer): Boolean;
var
  p, wEnd : Integer;
begin
  Result := False;
  p := IdentStart - 1;
  while (p >= 1) and CharInSet(Code[p], [' ', #9, #10, #13]) do Dec(p);
  if p < 1 then Exit;
  wEnd := p;
  while (p >= 1) and CharInSet(Code[p], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Dec(p);
  Result := SameText(Copy(Code, p + 1, wEnd - p), 'const');
end;

class procedure TFloatEqualityDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines     : TStringList;
  Cached    : Boolean;
  Code      : string;
  LineFor   : TArray<Integer>;
  FloatVars : TStringList;
  M         : TMatch;
  Lhs, Op, Rhs : string;
  LhsLow, RhsLow : string;
  IdentName : string;
  LineNo    : Integer;
  F         : TLeakFinding;
  TR        : TTypeResolver;   // Welle 1: scope-genaue Typ-Aufloesung (SCA144-Opt-in)
begin
  EnsureRegexCacheBuilt;
  TR := nil;
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    // Perf (2026-07-05): P1-strip-cache - geteilter Strip via Context-Cache.
    Code := TDetectorUtils.StripStringsAndCommentsCached(
      Lines, LineFor, AContext, FileName);

    // Phase 1: Float-Variablen sammeln. Single-Ident pro Deklaration
    // (Vereinfachung; Komma-Liste `A, B: Double` faengt nur den ersten Ident).
    FloatVars := TStringList.Create;
    try
      FloatVars.CaseSensitive := False;
      FloatVars.Sorted := True;
      FloatVars.Duplicates := dupIgnore;
      for M in CachedReDecl.Matches(Code) do
        if IsFloatType(M.Groups[2].Value) then
          FloatVars.Add(LowerCase(M.Groups[1].Value));
      if FloatVars.Count = 0 then Exit;
      // Welle 1 (Core-Detektoren-Architektur): scope-genauer Typ-Resolver aus dem
      // AST. FloatVars ist ein reiner Namensindex und scope-BLIND - ein Name, der
      // IRGENDWO als Float deklariert ist, matcht auch dort, wo er lokal ein
      // Ordinal/String/anderer Typ ist. Der Resolver loest den Operanden zur
      // Nutzungs-Zeile scope-genau auf und unterdrueckt bei nachgewiesenem
      // Nicht-Float-Skalar (ergaenzt die lexikalische OperandDeclaredNonFloat).
      TR := TTypeResolver.Create(UnitNode);

      // Phase 2: scanne nach `<ident> = <token>` oder `<token> = <ident>`
      // sowie `<>`-Variante. Beide Operanden simple Identifier oder Zahlen.
      for M in CachedReEqual.Matches(Code) do
      begin
        Lhs := M.Groups[1].Value;
        Op  := M.Groups[2].Value;
        Rhs := M.Groups[3].Value;
        // Zuweisungen ausschliessen: ` := ` haette den Op `:=` und nicht `=`.
        // Unser Regex matched nur ` = ` exakt - aber Pascal hat `:=` was
        // mit `=` enden kann. Sicherheit: vorhergehendes Zeichen darf nicht
        // ':' sein.
        if (M.Index > 1) and (Code[M.Index - 1] = ':') then Continue;
        // Mindestens EINE Seite muss eine bekannte Float-Var sein.
        // Nur einfacher Identifier (kein '.') gepruefte Seite, sonst
        // koennte 'Self.X = Other.Y' Field-Lookups treffen die wir nicht
        // aufloesen koennen.
        LhsLow := LowerCase(Lhs);
        RhsLow := LowerCase(Rhs);
        // Qualified Identifier (`Self.X`, `Obj.Field`) ausschliessen - aber
        // NICHT numerische Literale wie `0.5` (haben Punkt + Ziffern).
        if (Pos('.', Lhs) > 0) and not CharInSet(Lhs[1], ['0'..'9']) then Continue;
        if (Pos('.', Rhs) > 0) and not CharInSet(Rhs[1], ['0'..'9']) then Continue;
        // FP-Schutz: 'nil'/'true'/'false' sind nie Float - selbst wenn die
        // andere Seite eine Identifier-Kollision mit einer Float-Var hat
        // (Scope-Blindheit). Beispiel real-world:
        //   if Value = nil   im Pointer-Operator
        // wo FloatVars 'value' aus NullableSingle.Value: Single enthaelt.
        if IsNeverFloatToken(LhsLow) or IsNeverFloatToken(RhsLow) then Continue;
        if (FloatVars.IndexOf(LhsLow) < 0) and (FloatVars.IndexOf(RhsLow) < 0) then
          Continue;
        // Praezisions-Guard (Welle 3, 2026-06-28): ein echter Float-Equality-Bug
        // braucht den ANDEREN Operanden ebenfalls float-kompatibel - numerisches
        // Literal (Ziffer-Start: 0.5, 100, 1e9) ODER selbst eine Float-Var. Ein
        // gewoehnlicher Identifier (Boolean-/String-/Pointer-Feld, das nur
        // NAMENSGLEICH zu einer Float-Var ist = Scope-Blindheit) ist KEIN Float-
        // Vergleich -> FP. Dominante SCA144-FP-Klasse (Real-World: 88% FP, z.B.
        // 'FJavascriptEnabled <> aValue', 'Value <> ShowSeconds'). compare-to-0
        // wird bewusst NICHT geskippt ('a-b = 0' kann echter Bug sein).
        var LhsIsFloat := FloatVars.IndexOf(LhsLow) >= 0;
        var RhsIsFloat := FloatVars.IndexOf(RhsLow) >= 0;
        if not (LhsIsFloat and RhsIsFloat) then
        begin
          var OtherLow : string;
          if LhsIsFloat then OtherLow := RhsLow else OtherLow := LhsLow;
          if (OtherLow <> '') and not CharInSet(OtherLow[1], ['0'..'9'])
             and (FloatVars.IndexOf(OtherLow) < 0) then
            Continue;
        end;
        // Const-Deklaration ist kein Vergleich (Real-World-FP-Audit
        // 2026-07-10): 'const deltaT = 1/(...)' bindet eine Konstante -
        // es gibt hier keinen '='-Operator.
        if PrecededByConstKeyword(Code, M.Index) then Continue;

        // Typ-Aufloesung (Real-World-FP-Audit 2026-07-10): wenn der zum
        // Float-Namen passende Operand zur Nutzung NAECHSTLIEGEND als
        // Nicht-Float-Typ deklariert ist (Integer/Cardinal/Int32-Param,
        // lokales Integer, Klassen-Feld TdwsJSONValue, Ordinal-Result),
        // ist der FloatVars-Treffer scope-blind -> FP unterdruecken.
        LineNo := TDetectorUtils.LineForPos(LineFor, M.Index);
        if LineNo <= 0 then LineNo := 1;
        // Union (Welle 1): lexikalische Regex-Aufloesung ODER scope-genauer
        // AST-Resolver. Der Resolver faengt Scope-Kollisionen, die die Regex-
        // Naechstdeklaration verfehlt; TP-sicher (unbekannter Alias wie
        // TFloat=Double -> ResolvesToKnownNonFloat=False -> keine Unterdrueckung).
        if (FloatVars.IndexOf(LhsLow) >= 0)
           and (OperandDeclaredNonFloat(Code, Lhs, M.Index)
                or TR.ResolvesToKnownNonFloat(LhsLow, LineNo)) then Continue;
        if (FloatVars.IndexOf(RhsLow) >= 0)
           and (OperandDeclaredNonFloat(Code, Rhs, M.Index)
                or TR.ResolvesToKnownNonFloat(RhsLow, LineNo)) then Continue;

        // Welche Seite ist die Float-Var (fuer Detail-Text).
        if FloatVars.IndexOf(LhsLow) >= 0 then IdentName := Lhs
                                          else IdentName := Rhs;

        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(LineNo);
        F.MissingVar := Format(
          'Float equality (%s %s %s) is unreliable due to IEEE-754 rounding - use SameValue/Math.IsZero',
          [Lhs, Op, Rhs]);
        F.SetKind(fkFloatEquality);
        Results.Add(F);
      end;
    finally
      FloatVars.Free;
    end;
  finally
    TR.Free;   // nil-safe; nil bei FloatVars.Count=0-Exit
    ReleaseLines(Lines, Cached);
  end;
end;

end.

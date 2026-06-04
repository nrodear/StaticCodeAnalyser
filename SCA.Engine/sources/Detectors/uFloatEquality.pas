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
  uAstNode, uSCAConsts, uMethodd12;

type
  TFloatEqualityDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.RegularExpressions, System.StrUtils,
  uFileTextCache, uDetectorUtils;

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

function LineForPos(const LineFor: TArray<Integer>; APos: Integer): Integer;
begin
  if (APos >= 1) and (APos - 1 < Length(LineFor)) then
    Result := LineFor[APos - 1] + 1
  else
    Result := 0;
end;

class procedure TFloatEqualityDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
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
begin
  EnsureRegexCacheBuilt;
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    Code := TDetectorUtils.StripStringsAndComments(Lines, LineFor);

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
        // Welche Seite ist die Float-Var (fuer Detail-Text).
        if FloatVars.IndexOf(LhsLow) >= 0 then IdentName := Lhs
                                          else IdentName := Rhs;

        LineNo := LineForPos(LineFor, M.Index);
        if LineNo <= 0 then LineNo := 1;

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
    ReleaseLines(Lines, Cached);
  end;
end;

end.

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
  uFileTextCache;

const
  FLOAT_TYPES : array[0..4] of string =
    ('single', 'double', 'extended', 'real', 'currency');

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

// Strippt Strings + Kommentare. Positionen bleiben erhalten.
// String-Inhalte werden mit STR_MARK (~) statt Leerzeichen ersetzt, damit
// die Phase-2-Regex `\s*` NICHT ueber den ehemaligen String hinweg matched.
// Sonst wuerde `aValue = '' then` nach Strippen als `aValue =    then`
// erscheinen und `then` faelschlich als RHS einer Float-Equality kassieren
// (Pascal-Keyword statt Float-Literal). Mit ~~ als Platzhalter scheitert
// `[\w.]+` schon am ersten ~ und der Match faellt korrekt weg.
function StripStringsAndComments(Lines: TStringList; out LineForChar: TArray<Integer>): string;
const
  STR_MARK = '~';  // Marker fuer stripped string content - nicht in \w, nicht in \s.
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
          Buf.Append(STR_MARK); Chars.Add(i);
          if c = '''' then
          begin
            if (j < n) and (Line[j + 1] = '''') then
            begin Buf.Append(STR_MARK); Chars.Add(i); Inc(j, 2); end
            else begin InStr := False; Inc(j); end;
          end else Inc(j);
          Continue;
        end;
        if c = '''' then
        begin Buf.Append(STR_MARK); Chars.Add(i); InStr := True; Inc(j); Continue; end;
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

class procedure TFloatEqualityDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines     : TStringList;
  Cached    : Boolean;
  Code      : string;
  LineFor   : TArray<Integer>;
  FloatVars : TStringList;
  ReDecl    : TRegEx;
  ReEqual   : TRegEx;
  M         : TMatch;
  Lhs, Op, Rhs : string;
  LhsLow, RhsLow : string;
  IdentName : string;
  LineNo    : Integer;
  F         : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    Code := StripStringsAndComments(Lines, LineFor);

    // Phase 1: Float-Variablen sammeln. Single-Ident pro Deklaration
    // (Vereinfachung; Komma-Liste `A, B: Double` faengt nur den ersten Ident).
    FloatVars := TStringList.Create;
    try
      FloatVars.CaseSensitive := False;
      FloatVars.Sorted := True;
      FloatVars.Duplicates := dupIgnore;
      ReDecl := TRegEx.Create(
        '(?im)\b(\w+)\s*:\s*(Single|Double|Extended|Real|Currency)\b');
      for M in ReDecl.Matches(Code) do
        if IsFloatType(M.Groups[2].Value) then
          FloatVars.Add(LowerCase(M.Groups[1].Value));
      if FloatVars.Count = 0 then Exit;

      // Phase 2: scanne nach `<ident> = <token>` oder `<token> = <ident>`
      // sowie `<>`-Variante. Beide Operanden simple Identifier oder Zahlen.
      ReEqual := TRegEx.Create(
        '(?i)\b(\w+(?:\.\w+)?)\s*(=|<>)\s*([\w.]+)');
      for M in ReEqual.Matches(Code) do
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

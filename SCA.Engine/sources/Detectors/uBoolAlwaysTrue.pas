unit uBoolAlwaysTrue;

// Detektor: Boolean-Vergleich, der nach Sprach-Semantik immer denselben
// Wert liefert.
//
// Pattern (Bug, Sonar-50 #18, narrow):
//   if Length(s) >= 0 then DoStuff;           // immer True - Length nie negativ
//   if Length(s) <  0 then DoStuff;           // immer False - dito
//
// Folge: ein Vergleich der immer wahr ist macht das if redundant und
// signalisiert oft einen Tippfehler (`< 0` statt `= 0`, `>= 1` statt `> 0`).
// Compiler bemerkt das in der Regel NICHT, weil Length() Integer
// zurueckliefert (auch wenn der Wertebereich praktisch [0..MaxInt] ist).
//
// Erkennung (lexisch, narrow):
//   * Strip Strings + Kommentare.
//   * Pattern: `Length\s*\(...\)\s*(>=|<)\s*0\b`
//     bzw. `0\s*(<=|>)\s*Length\s*\(...\)`
//   * Auch `Count`-Property hat dieselbe Garantie (nie negativ), aber
//     ohne Type-Info koennen wir Properties nicht von Methoden trennen.
//     Defensiv: nur `Length()`.
//
// Limitierungen:
//   * Cardinal/UInt-Variablen (`<UInt> >= 0` ist auch always-true) ohne
//     Type-Inferenz nicht erkennbar.
//   * Komplexere Ausdruecke (`Length(s) - 1 < 0`) nicht erfasst -
//     ist auch nicht trivial true/false.
//
// Schweregrad: lsWarning - klarer Tippfehler-Indikator.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TBoolAlwaysTrueDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, NilComparison, RedundantBoolean, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions, System.StrUtils,
  uFileTextCache;

var
  // Lazy-Cache (Round 11): konstante Patterns einmalig kompilieren.
  CachedReLenGeZero : TRegEx;
  CachedReZeroLeLen : TRegEx;
  CachedReInit      : Boolean = False;

procedure EnsureRegexCacheBuilt;
begin
  if CachedReInit then Exit;
  CachedReLenGeZero := TRegEx.Create('(?i)\bLength\s*\([^()]*\)\s*(>=|<)\s*0\b');
  CachedReZeroLeLen := TRegEx.Create('(?i)\b0\s*(<=|>)\s*Length\s*\([^()]*\)');
  CachedReInit      := True;
end;

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

class procedure TBoolAlwaysTrueDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines    : TStringList;
  Cached   : Boolean;
  Code     : string;
  LineFor  : TArray<Integer>;
  M        : TMatch;
  Op       : string;
  AlwaysTrue : Boolean;
  LineNo   : Integer;
  F        : TLeakFinding;
begin
  EnsureRegexCacheBuilt;
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    Code := StripStringsAndComments(Lines, LineFor);

    // Pattern: Length(...) >= 0 | Length(...) < 0
    // (?: handles nested parens via [^()]* | recursive simplistic).
    for M in CachedReLenGeZero.Matches(Code) do
    begin
      Op := M.Groups[1].Value;
      AlwaysTrue := Op = '>=';
      LineNo := LineForPos(LineFor, M.Index);
      if LineNo <= 0 then LineNo := 1;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(LineNo);
      if AlwaysTrue then
        F.MissingVar := 'Length(...) >= 0 is always True (Length is never negative)'
      else
        F.MissingVar := 'Length(...) < 0 is always False (Length is never negative)';
      F.SetKind(fkBoolAlwaysTrue);
      Results.Add(F);
    end;

    // Spiegel-Variante: 0 <= Length(...) bzw. 0 > Length(...)
    for M in CachedReZeroLeLen.Matches(Code) do
    begin
      Op := M.Groups[1].Value;
      AlwaysTrue := Op = '<=';
      LineNo := LineForPos(LineFor, M.Index);
      if LineNo <= 0 then LineNo := 1;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(LineNo);
      if AlwaysTrue then
        F.MissingVar := '0 <= Length(...) is always True (Length is never negative)'
      else
        F.MissingVar := '0 > Length(...) is always False (Length is never negative)';
      F.SetKind(fkBoolAlwaysTrue);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

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
  System.RegularExpressions, System.StrUtils,
  uFileTextCache;

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
    Code := StripStringsAndComments(Lines, LineFor);

    // Pattern: `(string|RawByteString|AnsiString|UTF8String|WideString)(<id>)`
    // wo <id> mit P + Grossbuchstabe beginnt (Delphi Pointer-Konvention).
    // Group 1 = Cast-Typ, Group 2 = Variable.
    RE := TRegEx.Create(
      '(?i)\b(string|RawByteString|AnsiString|UTF8String|WideString)\s*\(\s*(P[A-Z]\w*)\s*\)');

    for M in RE.Matches(Code) do
    begin
      CastName := M.Groups[1].Value;
      VarName  := M.Groups[2].Value;
      LineNo := LineForPos(LineFor, M.Index);
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

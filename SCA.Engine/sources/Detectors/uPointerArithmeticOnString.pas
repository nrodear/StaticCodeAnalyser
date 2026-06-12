unit uPointerArithmeticOnString;

// Detektor: Pointer-Arithmetik auf PChar(s) / PAnsiChar(s) / PWideChar(s)
// ohne Empty-Check.
//
// Pattern (Bug, AV-Falle bei leerem String):
//   procedure Foo(const s: string);
//   var p: PChar;
//   begin
//     p := PChar(s) + 5;          // <-- wenn s='' -> PChar(s) = nil
//     while p^ <> #0 do Inc(p);   //     -> Zugriff auf $00000005 = AV
//   end;
//
//   p := PAnsiChar(rawBytes);
//   Inc(p, 10);                   // <-- wenn rawBytes='' -> Inc(nil, 10)
//
// Korrekt:
//   if s = '' then Exit;
//   p := PChar(s) + 5;
//
//   if Length(s) >= 6 then
//     p := PChar(s) + 5;
//
// Folge: Delphi optimiert PChar('') zu NIL (nicht zu einem Zeiger auf #0).
// Jede arithmetische Operation auf dem Ergebnis ohne vorherigen
// Empty-Check ist eine latente Access-Violation. mORMot vermeidet das
// systematisch mit `if s <> '' then`-Vorpruefung; user-code der die
// Library benutzt kopiert das Pattern aber oft ohne den Vor-Check.
//
// Erkennung (lexisch, narrow):
//   * Strip Strings + Kommentare.
//   * Pattern A: `PChar|PAnsiChar|PWideChar(<id>) + <n>` direkt.
//   * Pattern B: `Inc(P<...>, ...)` wo das Argument vorher als
//     `PChar|PAnsiChar|PWideChar(<id>)` zugewiesen wurde - das ist
//     schwer ohne Flow-Analyse; daher nur Pattern A.
//   * 80 Zeichen Backward-Snippet vor dem Match: wenn `if <id> <> ''`
//     oder `if Length(<id>)` ODER `if Assigned` vorhanden, gelten wir
//     als gepruefte Variante - kein Finding.
//
// Limitierungen:
//   * Single-File-lexisch. Keine Flow-Analyse - der Check kann
//     theoretisch weiter weg sein. 80-Zeichen-Vor-Fenster ist
//     Heuristik (Empty-Check direkt davor = typisches mORMot-Pattern).
//   * Pattern B (Inc auf gespeichertem PChar) wird nicht erfasst.
//
// Schweregrad: lsWarning - latente Access-Violation.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TPointerArithmeticOnStringDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
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

class procedure TPointerArithmeticOnStringDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
const
  LOOK_BEHIND = 200;  // Backward-Fenster fuer Empty-Check-Detection
var
  Lines       : TStringList;
  Cached      : Boolean;
  Code        : string;
  CodeLow     : string;
  LineFor     : TArray<Integer>;
  RE          : TRegEx;
  M           : TMatch;
  VarName     : string;
  CastKind    : string;
  StartPos    : Integer;
  Before      : string;
  LineNo      : Integer;
  F           : TLeakFinding;
  Detail      : string;
  GuardLow    : string;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    Code := StripStringsAndComments(Lines, LineFor);
    CodeLow := LowerCase(Code);

    // Pattern: PChar|PAnsiChar|PWideChar(<id>) <+|-> ...
    // Group 1 = Cast-Name, Group 2 = String-Variable.
    RE := TRegEx.Create(
      '(?i)\b(PChar|PAnsiChar|PWideChar)\s*\(\s*(\w+)\s*\)\s*[+\-]');

    for M in RE.Matches(Code) do
    begin
      CastKind := M.Groups[1].Value;
      VarName  := M.Groups[2].Value;

      // Backward-Fenster: Empty-Check direkt davor?
      StartPos := M.Index - LOOK_BEHIND;
      if StartPos < 1 then StartPos := 1;
      Before := Copy(CodeLow, StartPos, M.Index - StartPos);

      // Wir akzeptieren als Guard:
      //   if <var> <> '' ...   | if <var> = '' then exit
      //   if Length(<var>) ... | if Assigned(<var>) ...
      //
      // Wichtig: StripStringsAndComments ersetzt String-Literale durch
      // Spaces. Daraus wird aus `if s <> '' then` -> `if s <>    then`.
      // Wir matchen daher den Comparison-Operator OHNE die '' (zwei
      // Spaces als Platzhalter zwischen <var> und 'then' duerften nicht
      // stoeren, weil VarName <> nil und Numeric-Vergleiche eigene
      // Sicherheits-Semantik haben).
      GuardLow := LowerCase(VarName);
      if (Pos(GuardLow + ' <> ',   Before) > 0) or
         (Pos(GuardLow + '<>',     Before) > 0) or
         (Pos(GuardLow + ' = ',    Before) > 0) or
         (Pos(GuardLow + '=',      Before) > 0) or
         (Pos('length(' + GuardLow + ')',   Before) > 0) or
         (Pos('assigned(' + GuardLow + ')', Before) > 0) then
        Continue;

      LineNo := LineForPos(LineFor, M.Index);
      if LineNo <= 0 then LineNo := 1;

      Detail := Format(
        '%s(%s) +/- offset without empty-check - %s('''')=nil triggers AV on arithmetic',
        [CastKind, VarName, CastKind]);

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(LineNo);
      F.MissingVar := Detail;
      F.SetKind(fkPointerArithmeticOnString);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

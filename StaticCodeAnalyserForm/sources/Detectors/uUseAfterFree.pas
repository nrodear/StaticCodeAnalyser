unit uUseAfterFree;

// Detektor: Use-After-Free.
//
// Pattern (Bug, Sonar-50 #7):
//   procedure Foo;
//   var L: TStringList;
//   begin
//     L := TStringList.Create;
//     try
//       L.Add('x');
//     finally
//       FreeAndNil(L);
//     end;
//     L.Add('y');                  // <-- AV: L ist nil
//   end;
//
//   procedure Bar(L: TStringList);
//   begin
//     L.Free;                      // ohne nil-out, dangling pointer
//     Process(L);                  // <-- AV moeglich
//   end;
//
// Erkennung (lexisch, Strip-Strings/Comments, kein AST-Flow):
//   * Strip Strings + Kommentare ueber StripStringsAndComments aus uTaut.
//     ... eigene Stripping-Helper hier inline.
//   * Pro Vorkommen `FreeAndNil(<ident>)` oder `<ident>.Free` Position
//     merken. Token-Boundary auf beiden Seiten.
//   * Forward-Scan im selben File-Text bis Methoden-Ende oder Reassign:
//       - `<ident> :=`   -> Variable wieder gueltig, abbrechen
//       - `<ident> :`    -> neue var-Sektion, anderer Scope, abbrechen
//       - Wort 'end'     -> Method-Ende (heuristisch, defensiv); abbrechen
//       - `<ident>.<X>`  -> USE -> Befund
//       - `<ident>(`     -> Aufruf als Function-Argument -> USE -> Befund
//   * Bewusst NICHT geflaggt: `<ident> := nil` (das ist Reassign).
//   * Bewusst nicht geflaggt: `<ident>` als bare Wort (kein Accessor) -
//     produziert zu viele FPs (Vergleiche `if x = L then`, etc.).
//
// Limitierungen:
//   * Kein Control-Flow: `if Cond then Free else Use` wird geflaggt obwohl
//     der Use im else-Zweig den Free im then-Zweig nicht sieht.
//   * Verschachtelte Scopes / nested functions werden grob behandelt.
//   * Free in einem Method-Body kann einen Use im naechsten Method-Body
//     "sehen", wenn das Method-Ende nicht erkannt wird. Defensive
//     Heuristik: nach Wort 'end' aus dem Scan aussteigen.
//
// Schweregrad: lsError - Use-After-Free ist ein Crash- und Security-Bug.
//
// Sonar-Pendant: Sonar-50 #7 UseAfterFree.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TUseAfterFreeDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.RegularExpressions, System.StrUtils,
  uFileTextCache;



function IsIdentChar(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

// Strippt String-Literale und Kommentare aus dem File-Text. Ersetzt sie
// durch Leerzeichen damit die Positionen erhalten bleiben.
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

function LineForPos(const LineFor: TArray<Integer>; Pos: Integer): Integer;
begin
  if (Pos >= 1) and (Pos - 1 < Length(LineFor)) then
    Result := LineFor[Pos - 1] + 1
  else
    Result := 0;
end;

// Wortgrenze: davor und danach kein Ident-Char.
function IsWholeWord(const Code: string; StartPos, EndPos: Integer): Boolean;
begin
  if (StartPos > 1) and IsIdentChar(Code[StartPos - 1]) then Exit(False);
  if (EndPos < Length(Code)) and IsIdentChar(Code[EndPos + 1]) then Exit(False);
  Result := True;
end;

class procedure TUseAfterFreeDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines    : TStringList;
  Cached   : Boolean;
  Code     : string;
  LineFor  : TArray<Integer>;
  ReFree   : TRegEx;
  Matches  : TMatchCollection;
  M        : TMatch;
  Ident    : string;
  IdentLow : string;
  ScanFrom : Integer;
  CodeLen  : Integer;
  F        : TLeakFinding;
  UsePos   : Integer;
  LineNo   : Integer;

  function FindUseOrReassign(StartPos: Integer): Integer;
  // Sucht ab StartPos im Code nach dem ersten relevanten Vorkommen von Ident.
  // Rueckgabe:
  //   > 0   = Position eines USE (Befund).
  //   0     = Reassign / Method-Ende / nichts gefunden (kein Befund).
  var
    p     : Integer;
    After : Char;
    EndP  : Integer;
    Snippet : string;
    EndOfMethodRE : TRegEx;
    EndM  : TMatch;
    EndOfMethodPos : Integer;
  begin
    Result := 0;
    // Method-Boundary grob: ` end;` auf Zeile oder Token `procedure`/`function`/
    // `destructor`/`constructor`/`class` vor naechstem Use. Wir limitieren
    // den Scan auf das naechste solche Vorkommen.
    Snippet := Copy(Code, StartPos, CodeLen - StartPos + 1);
    EndOfMethodRE := TRegEx.Create(
      '(?im)^\s*end\s*;|\b(procedure|function|constructor|destructor|class\s+(?:procedure|function|constructor|destructor))\b');
    EndM := EndOfMethodRE.Match(Snippet);
    if EndM.Success then
      EndOfMethodPos := StartPos + EndM.Index - 1
    else
      EndOfMethodPos := CodeLen;

    p := StartPos;
    while p <= EndOfMethodPos do
    begin
      p := PosEx(Ident, Code, p);
      if (p = 0) or (p > EndOfMethodPos) then Exit;
      EndP := p + Length(Ident) - 1;
      if not IsWholeWord(Code, p, EndP) then begin Inc(p); Continue; end;
      // Auch case-insensitive: Code-Copy lowercase machen waere teuer; wir
      // matchen ohnehin mit case-sensitive PosEx. Pascal ist case-insensitive,
      // aber der Lexer normalisiert die Schreibweise nicht - in der Praxis
      // wird ein Identifier konsistent geschrieben (FOO ist nicht foo im
      // selben File). Falls doch: dieser Detector waere ein FN, aber kein FP.
      if not SameText(Copy(Code, p, Length(Ident)), Ident) then
      begin Inc(p); Continue; end;
      // Naechstes nicht-WS-Zeichen nach EndP bestimmt das Pattern.
      var k := EndP + 1;
      while (k <= CodeLen) and CharInSet(Code[k], [' ', #9, #10, #13]) do Inc(k);
      if k > CodeLen then Exit;
      After := Code[k];
      // `:=`  -> Reassign, Scope verlassen
      if (After = ':') and (k < CodeLen) and (Code[k + 1] = '=') then Exit(0);
      // `:`   -> Var-Section, Scope wechselt
      if After = ':' then Exit(0);
      // `.<X>`  -> Use als Receiver
      if After = '.' then Exit(p);
      // `(`    -> Aufruf mit Ident als Argument oder ident() Funktion
      if After = '(' then Exit(p);
      // `[`    -> Index-Access
      if After = '[' then Exit(p);
      // Sonst: bares Vorkommen ohne Accessor - nicht flaggen (FP-Risiko).
      Inc(p);
    end;
  end;

begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    Code := StripStringsAndComments(Lines, LineFor);
    CodeLen := Length(Code);

    // FreeAndNil(<id>) oder <id>.Free als Free-Punkt erkennen.
    ReFree := TRegEx.Create(
      '(?i)(?:\bFreeAndNil\s*\(\s*(\w+)\s*\)|\b(\w+)\s*\.\s*Free\b)');
    Matches := ReFree.Matches(Code);
    for M in Matches do
    begin
      // Gruppe 1 = Ident in FreeAndNil(...), Gruppe 2 = Ident vor .Free
      if M.Groups.Count > 1 then
      begin
        if (M.Groups.Count > 1) and (M.Groups[1].Value <> '') then
          Ident := M.Groups[1].Value
        else if (M.Groups.Count > 2) then
          Ident := M.Groups[2].Value
        else
          Continue;
      end
      else Continue;
      if Ident = '' then Continue;
      IdentLow := LowerCase(Ident);
      // Self / inherited / nil / Result als Ident skippen - Result-Free
      // ist Owner-Pattern, Self.Free ist Sonderfall, etc.
      if (IdentLow = 'self') or (IdentLow = 'result') or
         (IdentLow = 'inherited') or (IdentLow = 'nil') then Continue;

      ScanFrom := M.Index + M.Length;
      UsePos := FindUseOrReassign(ScanFrom);
      if UsePos = 0 then Continue;

      LineNo := LineForPos(LineFor, UsePos);
      if LineNo <= 0 then LineNo := 1;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(LineNo);
      F.MissingVar := Format(
        'Use of %s after Free / FreeAndNil - dangling pointer, AV likely',
        [Ident]);
      F.SetKind(fkUseAfterFree);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

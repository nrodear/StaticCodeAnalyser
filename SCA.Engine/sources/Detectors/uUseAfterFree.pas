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
// CFG-Filter (A.4.6, Konzept_A4_CFG.md):
//   Nach dem lexischen Match wird via TCFGBuilder.BuildFromMethod pro
//   Method der CFG aufgebaut und CFG.CanReach(FreeBlock, UseBlock)
//   geprueft. Wenn der Use vom Free aus NICHT reachable ist (z.B.
//   if Cond then Free+Exit else Use), wird der Befund dropped.
//   Beide (Free + Use) muessen in DERSELBEN Method liegen damit der
//   Filter greift - sonst lexisches Verhalten wie bisher (lieber leicht
//   konservativ als FN).
//
// Verbleibende Limitierungen:
//   * Nested functions werden grob behandelt (innerste Method gewinnt).
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
  System.RegularExpressions, System.StrUtils, System.IOUtils,
  uFileTextCache,
  uCFG;

var
  // Lazy-Cache: beide Patterns sind konstant. ReEndOfMethod war besonders
  // teuer weil er PRO Free-Match (= pro identifier-Free im File) neu
  // kompiliert wurde - in Files mit vielen Free-Aufrufen Faktor 10+ Compiles.
  CachedReFree        : TRegEx;
  CachedReEndOfMethod : TRegEx;
  CachedReInit        : Boolean = False;

procedure EnsureRegexCacheBuilt;
begin
  if CachedReInit then Exit;
  // Free-Regex mit zwei Look-Aheads gegen typische FPs (mORMot/Firebird-Audit):
  //   (?!\s*:=)         vermeidet 'vTable.free := @ptr' (Function-Pointer-
  //                     Assignment auf ein Field das zufaellig 'free' heisst -
  //                     kein Destructor-Call). Trifft die generated TLB-Header
  //                     der Firebird-API.
  //   (?!\s*\(\s*\w)    vermeidet 'fCx.Free(arg)' - Method-Call mit Argument.
  //                     TObject.Free() ist arg-los; ein Free MIT Argument ist
  //                     eine andere Methode mit kollidierendem Namen. Leere
  //                     Klammern Free() bleiben erlaubt.
  CachedReFree        := TRegEx.Create(
    '(?i)(?:\bFreeAndNil\s*\(\s*(\w+)\s*\)|\b(\w+)\s*\.\s*Free\b(?!\s*(?::=|\(\s*\w)))');
  CachedReEndOfMethod := TRegEx.Create(
    '(?im)^\s*end\s*;|\b(procedure|function|constructor|destructor|class\s+(?:procedure|function|constructor|destructor))\b');
  CachedReInit := True;
end;



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
  Matches  : TMatchCollection;
  M        : TMatch;
  Ident    : string;
  IdentLow : string;
  ScanFrom : Integer;
  CodeLen  : Integer;
  F        : TLeakFinding;
  UsePos   : Integer;
  LineNo   : Integer;
  FreeLine : Integer;
  // CFG-Filter (A.4.6): pro UnitNode einmal alle Methods sammeln und
  // CFGs lazy bauen. CFGMap besitzt die TCFG-Instanzen (OwnsValues=True).
  Methods  : TList<TAstNode>;
  CFGMap   : TObjectDictionary<TAstNode, TCFG>;

  function CalcMethodEndLine(N: TAstNode): Integer;
  var Stack : TStack<TAstNode>; Cur : TAstNode; Ch : TAstNode;
  begin
    Result := 0;
    if N = nil then Exit;
    Result := N.Line;
    Stack := TStack<TAstNode>.Create;
    try
      Stack.Push(N);
      while Stack.Count > 0 do
      begin
        Cur := Stack.Pop;
        if Cur.Line > Result then Result := Cur.Line;
        for Ch in Cur.Children do Stack.Push(Ch);
      end;
    finally Stack.Free; end;
  end;

  function FindMethodForLine(ALine: Integer): TAstNode;
  // Innerste Method die ALine umschliesst. Bei nested-Methods gewinnt
  // die mit der kleinsten Range (= innerste).
  var
    Mth, Best : TAstNode;
    BestSpan, Span : Integer;
  begin
    Best := nil;
    BestSpan := MaxInt;
    for Mth in Methods do
    begin
      var EndL := CalcMethodEndLine(Mth);
      if (ALine >= Mth.Line) and (ALine <= EndL) then
      begin
        Span := EndL - Mth.Line;
        if Span < BestSpan then
        begin
          Best := Mth;
          BestSpan := Span;
        end;
      end;
    end;
    Result := Best;
  end;

  function GetOrBuildCFG(MethNode: TAstNode): TCFG;
  begin
    if not CFGMap.TryGetValue(MethNode, Result) then
    begin
      Result := TCFGBuilder.BuildFromMethod(MethNode);
      CFGMap.Add(MethNode, Result);
    end;
  end;

  function FindBlockForLine(CFG: TCFG; ALine: Integer): TCFGBlock;
  // Erster Block der einen AstNode mit der gegebenen Source-Line enthaelt.
  var B : TCFGBlock; N : TAstNode;
  begin
    Result := nil;
    if CFG = nil then Exit;
    for B in CFG.Blocks do
      for N in B.AstNodes do
        if N.Line = ALine then Exit(B);
    // Fallback: Block dessen Line-Feld direkt matched.
    for B in CFG.Blocks do
      if B.Line = ALine then Exit(B);
  end;

  function CfgFilterDropsFinding(AFreeLine, AUseLine: Integer): Boolean;
  // True = Befund DROPPEN (CFG sagt: Use nicht erreichbar vom Free).
  // Greift nur wenn beide Lines IN DERSELBEN Method liegen.
  var
    Meth1, Meth2 : TAstNode;
    CFG          : TCFG;
    FreeBlk      : TCFGBlock;
    UseBlk       : TCFGBlock;
    DiagSnippet  : string;
  begin
    Result := False;
    Meth1 := FindMethodForLine(AFreeLine);
    Meth2 := FindMethodForLine(AUseLine);
    // TEMPORARY DIAGNOSTIC (audit base64func/JclCompression/uglobs FPs):
    // append per-finding decisions in a file next to the SARIF output.
    // Wird in einem Folge-Commit wieder entfernt.
    if Pos('base64func', LowerCase(FileName)) > 0 then
    begin
      try
        DiagSnippet := Format(
          '[%s] FreeLn=%d UseLn=%d Meth1=%s(L=%d) Meth2=%s(L=%d) ',
          [FileName, AFreeLine, AUseLine,
           BoolToStr(Meth1 <> nil), IfThen(Meth1 <> nil, Meth1.Line, -1),
           BoolToStr(Meth2 <> nil), IfThen(Meth2 <> nil, Meth2.Line, -1)]);
        if (Meth1 <> nil) and (Meth2 <> nil) and (Meth1 = Meth2) then
        begin
          CFG := GetOrBuildCFG(Meth1);
          FreeBlk := FindBlockForLine(CFG, AFreeLine);
          UseBlk  := FindBlockForLine(CFG, AUseLine);
          DiagSnippet := DiagSnippet + Format(
            'FreeBlk=%s(Id=%d Kind=%d) UseBlk=%s(Id=%d Kind=%d)',
            [BoolToStr(FreeBlk <> nil), IfThen(FreeBlk <> nil, FreeBlk.Id, -1),
             IfThen(FreeBlk <> nil, Ord(FreeBlk.Kind), -1),
             BoolToStr(UseBlk  <> nil), IfThen(UseBlk  <> nil, UseBlk.Id, -1),
             IfThen(UseBlk  <> nil, Ord(UseBlk.Kind), -1)]);
          if (FreeBlk <> nil) and (UseBlk <> nil) then
            DiagSnippet := DiagSnippet +
              Format(' CanReach=%s', [BoolToStr(CFG.CanReach(FreeBlk, UseBlk))]);
        end;
        TFile.AppendAllText('sca-cfg-debug.log', DiagSnippet + sLineBreak);
      except
        // Diagnostic darf den Scan nie crashen
      end;
    end;
    if (Meth1 = nil) or (Meth2 = nil) or (Meth1 <> Meth2) then Exit;
    CFG := GetOrBuildCFG(Meth1);
    FreeBlk := FindBlockForLine(CFG, AFreeLine);
    UseBlk  := FindBlockForLine(CFG, AUseLine);
    if (FreeBlk = nil) or (UseBlk = nil) then Exit;
    Result := not CFG.CanReach(FreeBlk, UseBlk);
  end;

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
    EndM  : TMatch;
    EndOfMethodPos : Integer;
  begin
    Result := 0;
    // Method-Boundary grob: ` end;` auf Zeile oder Token `procedure`/`function`/
    // `destructor`/`constructor`/`class` vor naechstem Use. Wir limitieren
    // den Scan auf das naechste solche Vorkommen.
    Snippet := Copy(Code, StartPos, CodeLen - StartPos + 1);
    EndM := CachedReEndOfMethod.Match(Snippet);
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
      // `.<X>`  -> Use als Receiver. ABER: `.Free` ist Sibling-Cleanup,
      // kein Use-After-Free. Klassischer if/else-Pattern:
      //   if Cond then try ... finally V.Free end
      //                                else V.Free;
      // Der else-Free wird sonst geflaggt obwohl er Alternative ist.
      if After = '.' then
      begin
        var TailStart := k + 1;
        while (TailStart <= CodeLen) and
              CharInSet(Code[TailStart], [' ', #9, #10, #13]) do Inc(TailStart);
        if (TailStart + 3 <= CodeLen) and
           SameText(Copy(Code, TailStart, 4), 'Free') and
           ((TailStart + 4 > CodeLen) or not IsIdentChar(Code[TailStart + 4])) then
          Exit(0);                       // sibling-Free, kein Use-After-Free
        Exit(p);
      end;
      // `(`    -> Aufruf mit Ident als Argument oder ident() Funktion
      if After = '(' then Exit(p);
      // `[`    -> Index-Access
      if After = '[' then Exit(p);
      // Sonst: bares Vorkommen ohne Accessor - nicht flaggen (FP-Risiko).
      Inc(p);
    end;
  end;

begin
  EnsureRegexCacheBuilt;
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  // CFG-Filter-Infrastruktur (A.4.6): Methods aus dem AST sammeln,
  // CFGs lazy bauen pro Hit. CFGMap besitzt die TCFGs (Owns=True).
  Methods := nil;
  CFGMap  := nil;
  try
    Code := StripStringsAndComments(Lines, LineFor);
    CodeLen := Length(Code);
    if UnitNode <> nil then
    begin
      Methods := UnitNode.FindAll(nkMethod);
      CFGMap  := TObjectDictionary<TAstNode, TCFG>.Create([doOwnsValues]);
    end;

    // FreeAndNil(<id>) oder <id>.Free als Free-Punkt erkennen.
    Matches := CachedReFree.Matches(Code);
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

      // A.4.6 CFG-Filter: wenn FreeBlock und UseBlock in derselben
      // Method liegen und CanReach=False, droppen wir den Befund.
      FreeLine := LineForPos(LineFor, M.Index);
      if FreeLine <= 0 then FreeLine := 1;
      if (Methods <> nil) and CfgFilterDropsFinding(FreeLine, LineNo) then
        Continue;

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
    if Assigned(CFGMap)  then CFGMap.Free;
    if Assigned(Methods) then Methods.Free;
    ReleaseLines(Lines, Cached);
  end;
end;

end.

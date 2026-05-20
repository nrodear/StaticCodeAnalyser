unit uConcurrencyExt;

// Concurrency-Familie erweitert (SCA113-114).
//
//   * fkThreadResumeDeprecated           - TThread.Resume seit D2010
//                                          deprecated, TThread.Start nutzen
//   * fkTThreadDestroyWithoutTerminate   - FreeAndNil(MyThread) / MyThread.Free
//                                          ohne vorheriges Terminate; WaitFor;
//                                          -> Worker laeuft weiter, AV-Risiko
//
// Beide lexisch, weil das Pattern ohne AST-Tiefe matchbar ist und der
// Parser keine TThread-Hierarchie nachverfolgt.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TConcurrencyExtDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.RegularExpressions, System.StrUtils,
  uFileTextCache;

function StripFileComments(Lines: TStringList; out LineForChar: TArray<Integer>): string;
var
  Buf            : TStringBuilder;
  i, n, j        : Integer;
  Line           : string;
  InBlk, InParen : Boolean;
  InStr          : Boolean;
  c              : Char;
  pClose         : Integer;
  Chars          : TList<Integer>;
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
          Buf.Append(c); Chars.Add(i);
          if c = '''' then
          begin
            if (j < n) and (Line[j + 1] = '''') then
            begin Buf.Append(''''); Chars.Add(i); Inc(j, 2); end
            else begin InStr := False; Inc(j); end;
          end else Inc(j);
          Continue;
        end;
        if c = '''' then
        begin Buf.Append(c); Chars.Add(i); InStr := True; Inc(j); Continue; end;
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

class procedure TConcurrencyExtDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines        : TStringList;
  Cached       : Boolean;
  Code         : string;
  LineFor      : TArray<Integer>;
  ReResume     : TRegEx;
  ReFreeNil    : TRegEx;
  ReDecl       : TRegEx;
  DeclMatch    : TMatch;
  Matches      : TMatchCollection;
  M            : TMatch;
  Snippet      : string;
  LookBack     : Integer;
  LineNo       : Integer;
  F            : TLeakFinding;
  HasTerminate : Boolean;
  Ident        : string;
  DeclaredType : string;

  function LooksLikeThreadType(const ATypeName: string): Boolean;
  // Heuristik: TThread-Descendants tragen praktisch immer das Token
  // 'Thread' im Typnamen (TThread, TWorkerThread, TIdHTTPThread,
  // TBackgroundThread, IOmniThreadPool, ...). Standard-Container und
  // VCL-Klassen (TObjectList, TStringList, TDictionary, TStream, TForm,
  // TTimer, TIniFile, ...) tragen es nicht. Damit faellt der weit
  // verbreitete FreeAndNil(FResults)-FP weg ohne echte Treffer zu verlieren.
  begin
    Result := Pos('thread', LowerCase(ATypeName)) > 0;
  end;

  function ResolveResultType(AtPos: Integer): string;
  // 'Result' hat in Pascal keine eigene 'Result: T;'-Deklaration - der Typ
  // steht im Function-Header `function <name>(...): <Type>;`. Wir suchen
  // rueckwaerts vom FreeAndNil-Aufruf bis zum NAECHSTEN function-Header
  // und liefern dessen Return-Type. Bei nested functions zaehlt das
  // jeweils naechstgelegene Header. Liefert '' wenn nichts passt.
  const
    LOOKBACK_CHARS = 4000;  // Method-Header sind selten weiter weg
  var
    StartPos : Integer;
    Snippet  : string;
    RE       : TRegEx;
    M        : TMatch;
    Hit      : string;
  begin
    Result := '';
    StartPos := AtPos - LOOKBACK_CHARS;
    if StartPos < 1 then StartPos := 1;
    Snippet := Copy(Code, StartPos, AtPos - StartPos);
    // Erwartetes Pattern: 'function <ident>[.<ident>]*[(<params>)]: <Type>;'
    // Die Param-Liste kann verschachtelte Klammern enthalten ([^()]* reicht
    // nicht), aber fuer Method-Header reicht zwei Verschachtelungsebenen.
    RE := TRegEx.Create(
      '(?is)\bfunction\s+[\w.]+\s*(?:\([^()]*(?:\([^()]*\)[^()]*)*\))?\s*:\s*' +
      '([A-Za-z0-9_<>,\s.]+?)\s*;');
    // Letzter Match im Snippet = naechstgelegener Header.
    Hit := '';
    for M in RE.Matches(Snippet) do
      Hit := M.Groups[1].Value;
    Result := Hit;
  end;

  procedure Emit(K: TFindingKind; const Detail: string; AtPos: Integer);
  begin
    LineNo := LineForPos(LineFor, AtPos);
    if LineNo <= 0 then LineNo := 1;
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := '';
    F.LineNumber := IntToStr(LineNo);
    F.MissingVar := Detail;
    F.SetKind(K);
    Results.Add(F);
  end;

begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    Code := StripFileComments(Lines, LineFor);

    // 1) <ident>.Resume - aber NICHT TForm/TPanel/etc. .Resume das
    //    optisch ein VCL-Resume-Painting-Event waere. Wir matchen
    //    konservativ alles und verlassen uns auf den User-Suppress
    //    wenn das ein FP ist - der Compiler markiert echte TThread.Resume
    //    sowieso schon als deprecated.
    ReResume := TRegEx.Create('(?i)\b(\w+)\.Resume\b(?!\s*\:=)');
    Matches := ReResume.Matches(Code);
    for M in Matches do
      Emit(fkThreadResumeDeprecated,
        Format('%s.Resume is deprecated since Delphi 2010 - prefer ' +
               '%s.Start or pass CreateSuspended=False to the constructor. ' +
               'Suppress per line if this is not a TThread reference: ' +
               '// noinspection ThreadResumeDeprecated',
               [M.Groups[1].Value, M.Groups[1].Value]),
        M.Index);

    // 2) FreeAndNil(<ident>) oder <ident>.Free auf einer Zeile, davor
    //    KEIN <ident>.Terminate (in den letzten ~10 Zeilen).
    //    LookBack-Window in Bytes (gestripte Code-Laenge); ~500 chars
    //    deckt ~10 Code-Zeilen ab.
    ReFreeNil := TRegEx.Create('(?i)\bFreeAndNil\s*\(\s*(\w+)\s*\)');
    Matches := ReFreeNil.Matches(Code);
    for M in Matches do
    begin
      Ident := M.Groups[1].Value;

      // Type-Filter: nur weitermachen wenn die Identifier-Deklaration im
      // selben File nach einem TThread-Descendant aussieht (Typ-Token
      // enthaelt 'Thread'). Wenn keine Deklaration gefunden wird, weiter
      // pruefen (extern deklarierter Identifier - konservativ flaggen).
      DeclaredType := '';
      if SameText(Ident, 'Result') then
        // Spezialfall: Function-Return - Typ kommt aus dem Method-Header.
        DeclaredType := ResolveResultType(M.Index)
      else
      begin
        ReDecl := TRegEx.Create(
          '(?i)\b' + Ident + '\s*:\s*([A-Za-z0-9_<>,\s.]+?)\s*(?:;|\)|=)');
        DeclMatch := ReDecl.Match(Code);
        if DeclMatch.Success then
          DeclaredType := DeclMatch.Groups[1].Value;
      end;
      if (DeclaredType <> '') and not LooksLikeThreadType(DeclaredType) then
        Continue;  // Kein TThread-Kontext -> kein Befund (vermeidet FP
                   // bei TObjectList/TStringList/TStream/TForm/Result).

      LookBack := M.Index - 500;
      if LookBack < 1 then LookBack := 1;
      Snippet := Copy(Code, LookBack, M.Index - LookBack);
      // Heuristik: vor dem FreeAndNil muss innerhalb der LookBack-Range
      // ein `<Ident>.Terminate` UND `<Ident>.WaitFor` vorkommen. Wenn
      // beides fehlt -> Befund.
      HasTerminate :=
        (Pos(LowerCase(Ident) + '.terminate', LowerCase(Snippet)) > 0) and
        (Pos(LowerCase(Ident) + '.waitfor',   LowerCase(Snippet)) > 0);
      if not HasTerminate then
        Emit(fkTThreadDestroyWithoutTerminate,
          Format('FreeAndNil(%s) without prior %s.Terminate + %s.WaitFor. ' +
                 'If %s is a TThread descendant the worker may still be ' +
                 'running -> AV / heap corruption. If it isnt a thread, ' +
                 'suppress with // noinspection TThreadDestroyWithoutTerminate',
                 [Ident, Ident, Ident, Ident]),
          M.Index);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

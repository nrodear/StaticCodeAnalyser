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
  Matches      : TMatchCollection;
  M            : TMatch;
  Snippet      : string;
  LookBack     : Integer;
  LineNo       : Integer;
  F            : TLeakFinding;
  HasTerminate : Boolean;

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
      LookBack := M.Index - 500;
      if LookBack < 1 then LookBack := 1;
      Snippet := Copy(Code, LookBack, M.Index - LookBack);
      // Heuristik: vor dem FreeAndNil muss innerhalb der LookBack-Range
      // ein `<Ident>.Terminate` UND `<Ident>.WaitFor` vorkommen. Wenn
      // beides fehlt -> Befund.
      HasTerminate :=
        (Pos(LowerCase(M.Groups[1].Value) + '.terminate', LowerCase(Snippet)) > 0) and
        (Pos(LowerCase(M.Groups[1].Value) + '.waitfor', LowerCase(Snippet)) > 0);
      if not HasTerminate then
        Emit(fkTThreadDestroyWithoutTerminate,
          Format('FreeAndNil(%s) without prior %s.Terminate + %s.WaitFor. ' +
                 'If %s is a TThread descendant the worker may still be ' +
                 'running -> AV / heap corruption. If it isnt a thread, ' +
                 'suppress with // noinspection TThreadDestroyWithoutTerminate',
                 [M.Groups[1].Value, M.Groups[1].Value, M.Groups[1].Value,
                  M.Groups[1].Value]),
          M.Index);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

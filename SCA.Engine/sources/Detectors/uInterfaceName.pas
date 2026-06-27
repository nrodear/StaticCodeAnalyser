unit uInterfaceName;

// Detektor fuer Interface-Typen ohne `I`-Prefix.
//
// SonarDelphi-Aequivalent: communitydelphi:InterfaceName. Delphi-
// Konvention: Interface-Typen heissen `IFoo` (analog zu `TFoo` fuer
// Klassen, `PFoo` fuer Pointer). Der `I`-Prefix signalisiert Vertrag
// statt Implementierung.
//
// Erkennung: lexikalisch ueber die Zeile. Pattern `<Ident> = interface`
// (optional `<Ident> = interface(IParent)`, `<Ident> = interface; (fwd)`,
// auch mit GUID `['{...}']`). Name muss mit `I` beginnen.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TInterfaceNameDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, GroupedDeclaration, IfElseBegin, LongMethod, MultipleExit, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

function IsIdent(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

function IsIdentStart(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','_']);
end;

function FindBadInterfaceName(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean; out Name: string): Integer;
var
  i, n, j, k : Integer;
  InStr      : Boolean;
  pClose     : Integer;
  c          : Char;
  Start      : Integer;
  NextWord   : string;
begin
  Result := 0;
  Name   := '';
  InStr  := False;
  i := 1;
  n := Length(Line);
  while i <= n do
  begin
    if InBlockComm then
    begin
      pClose := PosEx('}', Line, i);
      if pClose = 0 then Exit;
      InBlockComm := False;
      i := pClose + 1; Continue;
    end;
    if InParenStarComm then
    begin
      pClose := PosEx('*)', Line, i);
      if pClose = 0 then Exit;
      InParenStarComm := False;
      i := pClose + 2; Continue;
    end;
    c := Line[i];
    if InStr then
    begin
      if c = '''' then
      begin
        if (i < n) and (Line[i + 1] = '''') then Inc(i, 2)
        else begin InStr := False; Inc(i); end;
      end
      else Inc(i);
      Continue;
    end;
    if c = '''' then begin InStr := True; Inc(i); Continue; end;
    if (c = '/') and (i < n) and (Line[i + 1] = '/') then Exit;
    if c = '{' then
    begin
      pClose := PosEx('}', Line, i + 1);
      if pClose = 0 then begin InBlockComm := True; Exit; end;
      i := pClose + 1; Continue;
    end;
    if (c = '(') and (i < n) and (Line[i + 1] = '*') then
    begin
      pClose := PosEx('*)', Line, i + 2);
      if pClose = 0 then begin InParenStarComm := True; Exit; end;
      i := pClose + 2; Continue;
    end;
    if IsIdentStart(c) then
    begin
      Start := i;
      while (i <= n) and IsIdent(Line[i]) do Inc(i);
      Name := Copy(Line, Start, i - Start);
      // Skip ws
      j := i;
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      // Optional Generic-Klammer `<...>`
      if (j <= n) and (Line[j] = '<') then
      begin
        Inc(j);
        while (j <= n) and (Line[j] <> '>') do Inc(j);
        if j <= n then Inc(j);
        while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      end;
      // Erwarte `=`
      if (j > n) or (Line[j] <> '=') then Continue;
      Inc(j);
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      // Erwarte `interface` oder `dispinterface`
      if (j > n) or not IsIdentStart(Line[j]) then Continue;
      k := j;
      while (k <= n) and IsIdent(Line[k]) do Inc(k);
      NextWord := LowerCase(Copy(Line, j, k - j));
      if (NextWord <> 'interface') and (NextWord <> 'dispinterface') then
        Continue;
      // Pruefe Name
      if (Length(Name) >= 1) and CharInSet(Name[1], ['I', 'i']) then Continue;
      Result := Start;
      Exit;
    end;
    Inc(i);
  end;
end;

class procedure TInterfaceNameDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines  : TStringList;
  i, Col : Integer;
  InBlk, InParen : Boolean;
  F      : TLeakFinding;
  Cached : Boolean;
  Name   : string;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    InBlk   := False;
    InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Col := FindBadInterfaceName(Lines[i], InBlk, InParen, Name);
      if Col <= 0 then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := Format(
        'Interface `%s` does not follow `I<Name>` naming convention - ' +
        'rename to start with `I`.', [Name]);
      F.SetKind(fkInterfaceName);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

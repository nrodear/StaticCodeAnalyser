unit uIfElseBegin;

// Detektor fuer asymmetrische `begin..end`-Verwendung in if/else.
//
// SonarDelphi-Aequivalent: communitydelphi:IfElseBegin. Wenn der
// then-Zweig `begin..end` benutzt (also mehrere Statements oder eine
// explizit-gruppierte Form), sollte der else-Zweig konsistent dazu
// auch `begin..end` haben - sonst entsteht beim Diff-Lesen die
// Unsicherheit "ist hier was vergessen worden?".
//
// Erkennung: lexikalisch auf der joined komment-bereinigten Source.
// Pattern `end <ws>+ else <ws>+ <non-begin-non-if>` wird gemeldet.
// `else if` (Else-If-Kette) und `else begin` sind OK. Die andere
// Richtung (`then <stmt> else begin`) wird hier NICHT geprueft - sie
// faellt unter den "BeginEndRequired"-Rule-Kandidaten.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TIfElseBeginDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LegacyInitializationSection, LongMethod, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uFileTextCache, uDetectorUtils;

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

class procedure TIfElseBeginDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines      : TStringList;
  Cached     : Boolean;
  Code       : string;
  Lwr        : string;
  LineFor    : TArray<Integer>;
  p, q, k    : Integer;
  n          : Integer;
  Word       : string;
  LineNumber : Integer;
  F          : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    Code := TDetectorUtils.StripFileCommentsKeepStringsCached(Lines, LineFor, AContext, FileName);
    Lwr := LowerCase(Code);
    n := Length(Code);
    p := 1;
    while True do
    begin
      // Pattern: word `end` gefolgt von ws gefolgt von word `else`.
      p := PosEx('end', Lwr, p);
      if p = 0 then Break;
      if (p > 1) and IsIdent(Code[p - 1]) then begin Inc(p); Continue; end;
      if (p + 3 <= n) and IsIdent(Code[p + 3]) then begin Inc(p); Continue; end;
      // Skip ws nach `end`
      q := p + 3;
      while (q <= n) and CharInSet(Code[q], [' ', #9, #10, #13]) do Inc(q);
      // Word `else`?
      if (q + 3 > n) or not SameText(Copy(Code, q, 4), 'else') then
      begin Inc(p, 3); Continue; end;
      if (q + 4 <= n) and IsIdent(Code[q + 4]) then begin Inc(p, 3); Continue; end;
      // Skip ws nach `else`
      k := q + 4;
      while (k <= n) and CharInSet(Code[k], [' ', #9, #10, #13]) do Inc(k);
      if k > n then begin Inc(p, 3); Continue; end;
      // Erlaubt: `begin`, `if`, `case`, `try`, `for`, `while`, `repeat`,
      // `with` (alle Statement-Opener mit eigenem implizitem Block-Charakter).
      // Wenn der Naechste Wort einer der erlaubten ist, kein Treffer.
      if IsIdentStart(Code[k]) then
      begin
        var Start: Integer; Start := k;
        while (k <= n) and IsIdent(Code[k]) do Inc(k);
        Word := LowerCase(Copy(Code, Start, k - Start));
        if (Word = 'begin') or (Word = 'if') or (Word = 'case') or
           (Word = 'try') or (Word = 'for') or (Word = 'while') or
           (Word = 'repeat') or (Word = 'with') then
        begin
          Inc(p, 3); Continue;
        end;
      end;
      // Treffer: `end else <plain stmt>`
      if (p - 1) < Length(LineFor) then
        LineNumber := LineFor[p - 1]
      else
        LineNumber := 0;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(LineNumber + 1);
      F.MissingVar := 'Asymmetric if/else: then-branch uses `begin..end` ' +
        'but else-branch uses a single statement. Make both branches ' +
        'consistent (both with or both without `begin..end`).';
      F.SetKind(fkIfElseBegin);
      Results.Add(F);
      Inc(p, 3);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

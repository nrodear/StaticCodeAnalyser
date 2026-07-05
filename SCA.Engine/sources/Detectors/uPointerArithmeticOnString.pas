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
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TPointerArithmeticOnStringDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions,
  uFileTextCache, uDetectorUtils;

class procedure TPointerArithmeticOnStringDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
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
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    // Perf (2026-07-05): P1-strip-cache - geteilter Strip via Context-Cache.
    Code := TDetectorUtils.StripStringsAndCommentsCached(
      Lines, LineFor, AContext, FileName, ' ');
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

      LineNo := TDetectorUtils.LineForPos(LineFor, M.Index);
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

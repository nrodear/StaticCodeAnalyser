unit uEmptyOnHandler;

// Detektor: `on E: SomeException do ;` (oder leerer begin/end-Block) -
// typisierter Exception-Handler schluckt eine spezifische Exception still.
//
// Pattern (Bug, silent failure):
//   try
//     RiskyCall;
//   except
//     on E: EDatabaseError do ;       // <-- DB-Fehler weg, kein Log
//     on E: EFileNotFound do
//     begin
//     end;                            // <-- ebenso leer
//   end;
//
// Korrekt:
//   try
//     RiskyCall;
//   except
//     on E: EDatabaseError do
//     begin
//       Logger.Error('DB failed: %s', [E.Message]);
//       raise;                        // oder: spezifisches Recovery
//     end;
//   end;
//
// Folge: spezifische Exception-Klassen ignoriert -> Fehler unsichtbar in
// Production. Subtiler als `except end` (EmptyExcept SCA-001) weil eine
// Type-Annotation den Eindruck erweckt, der Entwickler habe sich Gedanken
// gemacht. mORMot Real-World-Review zeigt diesen Pattern in Cleanup-Code,
// wo "kann ignoriert werden" nicht dokumentiert ist.
//
// Erkennung (lexisch, narrow):
//   * Strip Strings + Kommentare.
//   * Regex matched `on\s+(\w+\s*:\s*)?\w+\s+do\s+(;|begin\s*end\s*;?)`.
//     - 1. Form: `on E: T do ;`
//     - 2. Form: `on E: T do begin end;`
//   * Anonyme Variante `on T do ...` (ohne E:) wird mit-erfasst.
//
// Limitierungen:
//   * Single-File-lexisch. Eine `do <stmt-no-op>` Konstruktion mit z.B.
//     `do begin {nothing} end` wird mit-erfasst - akzeptabel.
//
// Schweregrad: lsWarning - silent failure ist Bug.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TEmptyOnHandlerDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions,
  uFileTextCache, uDetectorUtils;

class procedure TEmptyOnHandlerDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines    : TStringList;
  Cached   : Boolean;
  Code     : string;
  LineFor  : TArray<Integer>;
  RE       : TRegEx;
  M        : TMatch;
  LineNo   : Integer;
  ExName   : string;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    // Perf (2026-07-05): P1-strip-cache - geteilter Strip via Context-Cache.
    Code := TDetectorUtils.StripStringsAndCommentsCached(
      Lines, LineFor, AContext, FileName, ' ');

    // Pattern: `on [E:] SomeExceptionClass do ;` or `on ... do begin end;`
    // Group 1: optional 'E:' prefix (eats up `Name : `).
    // Group 2: Exception class name.
    // Lookahead matches semicolon or empty begin/end.
    // FP-Fix (2026-07-11): Wortgrenze nach `end`. Ohne \b matchte `begin\s*end`
    // auch einen Body der mit einem End-praefigierten Identifier beginnt
    // (z.B. `begin EndLogin := ...`) - `End` aus `EndLogin` wurde als leerer
    // Block fehlgelesen. \b nach `end` verlangt eine Wort/Nichtwort-Grenze
    // (`end;`, `end `, `end` am Ende) und schliesst `endXxx` aus.
    RE := TRegEx.Create(
      '(?is)\bon\s+(?:\w+\s*:\s*)?(\w+)\s+do\s*(?:;|begin\s*end\b\s*;?)');

    for M in RE.Matches(Code) do
    begin
      ExName := M.Groups[1].Value;

      // FP-Fix (2026-07-11): EAbort still zu schlucken ist das
      // bestimmungsgemaesse VCL-Abbruch-Signal (Abort / OnProgress-Cancel),
      // kein Silent-Failure-Bug -> Fund verwerfen.
      if SameText(ExName, 'EAbort') then
        Continue;

      LineNo := TDetectorUtils.LineForPos(LineFor, M.Index);
      if LineNo <= 0 then LineNo := 1;

      Results.Add(TLeakFinding.New(FileName, '', LineNo,
        Format('Typed exception handler on %s has empty body - silent failure',
          [ExName]),
        fkEmptyOnHandler));
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

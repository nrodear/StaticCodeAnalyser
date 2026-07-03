unit uGetMemWithoutFreeMem;

// Detektor: GetMem / AllocMem / ReallocMem ohne paired FreeMem im
// gleichen Routinen-Body.
//
// Pattern (Bug, klassischer Memory-Leak in Low-Level Delphi-Code):
//   GetMem(P, 1024);
//   FillBuffer(P);          // <-- wirft -> P bleibt fuer immer haengen
//   ProcessBuffer(P);
//   FreeMem(P);
//
// Korrekt:
//   GetMem(P, 1024);
//   try
//     FillBuffer(P);
//   finally
//     FreeMem(P);
//   end;
//
// Folge: Jede Exception zwischen GetMem und FreeMem leakt den allokierten
// Speicher dauerhaft. mORMot benutzt GetMem an ueber 20 Stellen in core/
// fuer hochperformante Buffer-Manipulation - jedes Vorkommen ohne
// try/finally-Wrapper ist ein Production-Leak.
//
// Erkennung (lexisch, narrow):
//   * Strip Strings + Kommentare.
//   * Pro Vorkommen von GetMem|AllocMem|ReallocMem:
//     - 400 Zeichen Lookahead-Fenster nach dem Call.
//     - Erwarte FreeMem|FreeMemAndNil im Fenster.
//     - Erwarte `try` VOR dem FreeMem (try kommt VOR FreeMem im Snippet).
//     - Wenn FreeMem fehlt -> Skip (custom Allocator oder Ownership-Transfer).
//     - Wenn FreeMem da ist aber kein try davor -> Finding.
//
// Limitierungen:
//   * Single-File-lexisch. Keine AST-Analyse.
//   * GetMem in Konstruktoren mit FreeMem in Destruktoren wird nicht erkannt
//     - dafuer ist das Lookahead-Fenster zu klein, gewollt: Ownership-
//     Transfer braucht andere Patterns (FieldLeak / LeakInConstructor).
//   * Custom-Allocators (GetMemoryManager swapping) sind nicht modelliert.
//
// Schweregrad: lsWarning - Memory-Leak.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TGetMemWithoutFreeMemDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions, System.StrUtils,
  uFileTextCache, uDetectorUtils;

class procedure TGetMemWithoutFreeMemDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
const
  LOOK_AHEAD = 400;  // groesseres Fenster als UnpairedLock - Buffer-Code
                     // hat oft mehr Zeilen zwischen Acquire und Release.
var
  Lines    : TStringList;
  Cached   : Boolean;
  Code     : string;
  CodeLow  : string;
  LineFor  : TArray<Integer>;
  RE       : TRegEx;
  M        : TMatch;
  AfterPos : Integer;
  Snippet  : string;
  LineNo   : Integer;
  F        : TLeakFinding;
  Detail   : string;
  TryPos   : Integer;
  FreePos  : Integer;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    Code := TDetectorUtils.StripStringsAndComments(Lines, LineFor, ' ');
    CodeLow := LowerCase(Code);

    // Pattern: GetMem(P, n) / AllocMem(n) / ReallocMem(P, n).
    RE := TRegEx.Create('(?i)\b(GetMem|AllocMem|ReallocMem)\s*\(');
    for M in RE.Matches(Code) do
    begin
      AfterPos := M.Index + M.Length;
      if AfterPos > Length(Code) then Continue;

      // FP-Guard A (2026-06-29): DEFINITION, kein Aufruf - 'function GetMem(...)'
      // / 'procedure ReallocMem(...)' (Custom-Allocator-/MM-Wrapper-Deklaration).
      // Voriges Wort vor dem Bezeichner pruefen.
      var Bi := M.Index - 1;
      while (Bi >= 1) and CharInSet(CodeLow[Bi], [' ', #9, #10, #13]) do Dec(Bi);
      var WordEnd := Bi;
      while (Bi >= 1) and CharInSet(CodeLow[Bi], ['a'..'z', '0'..'9', '_']) do Dec(Bi);
      var PrevWord := Copy(CodeLow, Bi + 1, WordEnd - Bi);
      if (PrevWord = 'function') or (PrevWord = 'procedure') then Continue;

      // FP-Guard B: erstes Argument ist ein FELD (FXxx-Konvention) oder ein
      // Array-/Index-/Deref-Element (ident[..] / ident^[..]). Ownership liegt
      // dann beim Objekt, FreeMem im Destruktor - ausserhalb der Single-Routine-
      // Scope dieses Detektors (vgl. Unit-Header, GetMem-im-Ctor/Free-im-Dtor).
      var Ai := AfterPos;                       // direkt nach '('
      while (Ai <= Length(Code)) and CharInSet(Code[Ai], [' ', #9]) do Inc(Ai);
      if (Ai < Length(Code)) and (Code[Ai] = 'F')
         and CharInSet(Code[Ai + 1], ['A'..'Z']) then Continue;   // Feld FXxx
      var Aj := Ai;
      while (Aj <= Length(Code)) and
            CharInSet(Code[Aj], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do Inc(Aj);
      if (Aj <= Length(Code)) and (Code[Aj] = '^') then Inc(Aj);
      if (Aj <= Length(Code)) and (Code[Aj] = '[') then Continue;  // Array-Element

      // Snippet nach dem Alloc (max 400 Zeichen) lowercased.
      Snippet := Copy(CodeLow, AfterPos, LOOK_AHEAD);
      // Audit 2026-07-01: 'try' als GANZES WORT (Substring-Pos matchte
      // 'retry'/'entry' -> ein Wort davor liess einen echten GetMem-Leak
      // faelschlich als geschuetzt durchgehen, False-Negative). 'freemem'
      // bleibt bewusst Substring (soll auch 'FreeMemAndNil' treffen).
      TryPos  := TDetectorUtils.FindWholeWordLower('try', Snippet);
      FreePos := Pos('freemem', Snippet);
      // Kein Folge-FreeMem -> Ownership-Transfer / Custom-Allocator
      // -> Skip (nicht flaggen).
      if FreePos = 0 then Continue;
      // try kommt VOR FreeMem -> Pattern OK
      if (TryPos > 0) and (TryPos < FreePos) then Continue;

      LineNo := TDetectorUtils.LineForPos(LineFor, M.Index);
      if LineNo <= 0 then LineNo := 1;

      Detail := Format(
        '%s without surrounding try/finally - exception leaks the buffer',
        [Trim(M.Groups[1].Value)]);

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(LineNo);
      F.MissingVar := Detail;
      F.SetKind(fkGetMemWithoutFreeMem);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

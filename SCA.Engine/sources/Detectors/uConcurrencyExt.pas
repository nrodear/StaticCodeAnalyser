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
//
// FP-Schutz: scannt gestrippten Code (TDetectorUtils.StripStringsAndComments)
// statt rohem Quelltext. Damit feuern weder dxgettext-msgid-Strings wie
// 'X.Free; X := nil; -> use FreeAndNil(X)' (uLocalization.pas) noch
// Code-Beispiele in Header-Kommentaren ueber das Regex-Match - String- und
// Kommentar-Inhalte werden mit '~' aufgefuellt, die Match-Position bleibt
// quellzeilen-genau via LineForChar-Array.

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
  uFileTextCache, uDetectorUtils;

var
  // Lazy-Cache (Round 11): die 3 KONSTANTEN Patterns einmalig kompilieren.
  // Die 2 dynamischen (mit Ident im Pattern) bleiben per-Call compile - das
  // sind ggf. Round-12-Kandidaten via Capture-Group + Filter-Algorithmus.
  CachedReFuncHeader : TRegEx;
  CachedReResume     : TRegEx;
  CachedReFreeNil    : TRegEx;
  CachedReInit       : Boolean = False;

procedure EnsureRegexCacheBuilt;
begin
  if CachedReInit then Exit;
  CachedReFuncHeader := TRegEx.Create(
    '(?is)\bfunction\s+[\w.]+\s*(?:\([^()]*(?:\([^()]*\)[^()]*)*\))?\s*:\s*' +
    '([A-Za-z0-9_<>,\s.]+?)\s*;');
  CachedReResume  := TRegEx.Create('(?i)\b(\w+)\.Resume\b(?!\s*\:=)');
  CachedReFreeNil := TRegEx.Create('(?i)\bFreeAndNil\s*\(\s*(\w+)\s*\)');
  CachedReInit    := True;
end;

// Vorheriger lokaler StripFileComments hat Kommentare gestrippt, String-
// Literale aber 1:1 erhalten - das war die FP-Quelle (TDestroyWithoutTerminate
// matched 'FreeAndNil(X)' inside einer englischen Hint-msgid). Ersetzt durch
// TDetectorUtils.StripStringsAndComments, der beides strippt und die
// Char->Quellzeile-Map (LineForChar) gleich mitliefert.

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
    // Letzter Match im Snippet = naechstgelegener Header.
    Hit := '';
    for M in CachedReFuncHeader.Matches(Snippet) do
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
  EnsureRegexCacheBuilt;
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    Code := TDetectorUtils.StripStringsAndComments(Lines, LineFor);

    // 1) <ident>.Resume - aber NICHT TForm/TPanel/etc. .Resume das
    //    optisch ein VCL-Resume-Painting-Event waere. Wir matchen
    //    konservativ alles und verlassen uns auf den User-Suppress
    //    wenn das ein FP ist - der Compiler markiert echte TThread.Resume
    //    sowieso schon als deprecated.
    Matches := CachedReResume.Matches(Code);
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
    Matches := CachedReFreeNil.Matches(Code);
    for M in Matches do
    begin
      Ident := M.Groups[1].Value;

      // Type-Filter: nur weitermachen wenn der Identifier nach einem
      // TThread-Descendant aussieht. Lookups in dieser Reihenfolge:
      //   1. Spezialfall 'Result': aus Function-Header oben.
      //   2. `<Ident> : <Type>;`-Deklaration im selben File.
      //   3. `<Ident> := T<Type>.Create...` als Konstruktor-Call im selben
      //      File - faengt cross-unit deklarierte Globals (z.B.
      //      `gDfmRepoIndex` in uDfmRepoIndex.pas, instanziiert hier).
      // Wenn KEINER der drei Lookups einen Typ liefert, faellt der
      // konservative Pfad weiter (Befund + Suppress-Hinweis im Detail).
      DeclaredType := '';
      if SameText(Ident, 'Result') then
        DeclaredType := ResolveResultType(M.Index)
      else
      begin
        ReDecl := TRegEx.Create(
          '(?i)\b' + Ident + '\s*:\s*([A-Za-z0-9_<>,\s.]+?)\s*(?:;|\)|=)');
        DeclMatch := ReDecl.Match(Code);
        if DeclMatch.Success then
          DeclaredType := DeclMatch.Groups[1].Value
        else
        begin
          // Fallback: Konstruktor-Call `<Ident> := TXxx.Create...`. Faengt
          // cross-unit-deklarierte Identifier die hier nur instanziiert
          // werden - typischer Pfad fuer globale Indizes/Caches.
          ReDecl := TRegEx.Create(
            '(?i)\b' + Ident + '\s*:=\s*(T\w+)\s*\.\s*Create\b');
          DeclMatch := ReDecl.Match(Code);
          if DeclMatch.Success then
            DeclaredType := DeclMatch.Groups[1].Value;
        end;
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

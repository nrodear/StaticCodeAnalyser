unit uUnitLevelKeywordIndent;

// Detektor fuer Unit-Level-Keywords (unit/interface/implementation/
// initialization/finalization), die NICHT auf Spalte 1 stehen.
//
// SonarDelphi-Aequivalent: communitydelphi:UnitLevelKeywordIndentation.
// Konvention seit Object-Pascal: die strukturellen Section-Keywords
// einer Unit stehen flush-left (Spalte 1). Wenn sie eingerueckt sind,
// erschwert das das visuelle Skimmen der Unit-Gliederung und kann auf
// fehlerhafte Block-Verschachtelung hindeuten.
//
// Erkennung: pro Zeile pruefen, ob das erste Nicht-Whitespace-Token
// eines der Section-Keywords ist UND die Zeile mit Whitespace beginnt.
// Die Zeile wird vorher laengenerhaltend von Kommentaren und String-
// Literalen befreit (BlankCommentsStateful) - siehe dort, warum ein
// Zustand ueber Zeilengrenzen die Bedingung fuer Brauchbarkeit ist.
//
// Beachte: `interface` wird hier ueberprueft NUR wenn es die GANZE Zeile
// ist (nach Trim) - sonst clasht es mit `type IFoo = interface ... end`
// (dort ist `interface` im Typ-Kontext und darf eingerueckt sein).
// Genauso `uses` koennte in Interface- oder Implementation-Section
// auftauchen und sollte typografisch auf Spalte 1 stehen.
//
// Schweregrad: lsHint - reines Style/Konvention.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TUnitLevelKeywordIndentDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, DeepNesting, DuplicateBlock, GroupedDeclaration, MultipleExit, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

// True wenn Lower einem strukturellen Section-Keyword entspricht, das
// IMMER auf Spalte 1 stehen sollte (auch wenn es im Code nochmal in
// anderem Kontext vorkommt waere das ungewoehnlich).
function IsStrictSectionKw(const Lower: string): Boolean; inline;
begin
  Result := (Lower = 'unit') or (Lower = 'implementation')
         or (Lower = 'initialization') or (Lower = 'finalization');
end;

// True wenn das Token eines ist, das stand-alone-Zeile sein muss
// (interface, uses) - aber nur wenn keine weiteren Tokens auf der
// Zeile folgen.
function IsSoloOnlyKw(const Lower: string): Boolean; inline;
begin
  Result := (Lower = 'interface') or (Lower = 'uses');
end;

// True, wenn die Zeile ueberhaupt einen Kommentar-Opener oder ein
// String-Literal enthaelt. Nur dann muss geblankt (= kopiert) werden;
// fuer alle anderen Zeilen bleibt Clean die geteilte Referenz auf
// Lines[i]. '(' und '/' zaehlen NUR mit passendem Folgezeichen - sonst
// haette jeder Prozeduraufruf und jede Division eine Kopie erzwungen.
function HasCommentOrLiteral(const Line: string): Boolean;
var
  i, n : Integer;
begin
  n := Length(Line);
  for i := 1 to n do
    case Line[i] of
      '{', '''': Exit(True);
      '/': if (i < n) and (Line[i + 1] = '/') then Exit(True);
      '(': if (i < n) and (Line[i + 1] = '*') then Exit(True);
    end;
  Result := False;
end;

// Laengenerhaltendes Blanking von Kommentaren und String-Literalen MIT
// Zustand ueber Zeilengrenzen. Vorbild ist StripLineStateful in
// uPublicField.pas - dort wird der Kommentar aber GELOESCHT; hier muss
// er durch Leerzeichen ERSETZT werden, weil die Spalte des ersten
// Wortes in den Meldungstext geht und ein verkuerzender Strip sie
// verfaelschen wuerde.
//
// Warum ueberhaupt: ExtractFirstWord erkannte einen Kommentar nur, wenn
// der Opener an der ersten Nicht-Whitespace-Position DERSELBEN Zeile
// stand. Der komplette Innenraum mehrzeiliger Bloecke galt damit als
// Code - Doku-Header (pyscripter/frmPyIDEMain.pas:2 '  Unit Name: ...'),
// englische Prosa (Indy/IdCoderBinHex4.pas:123 '  implementation is
// targetted at.') und @longcode-Beispielunits (LoggerPro.pas:761-783
// liefert 12 Funde aus EINEM Doku-Kommentar) wurden gemeldet.
// Trockenlauf ueber D:/git-sca-realworld: 207 -> 33 Funde (175 Drops,
// 1 Add). TP-Verlust ist strukturell ausgeschlossen: ein Drop setzt
// voraus, dass der ZEILENANFANG im Kommentar liegt.
//
// String-Literale muessen mitgeblankt werden, sonst schaltet eine
// geschweifte Klammer INNERHALB eines Literals (etwa der Konstantentext
// '{$R-}') InBrace an und verschluckt den Rest der Datei. Ein Zustand
// ueber Zeilen braucht es dafuer nicht - Pascal-Strings enden an der
// Zeilengrenze.
procedure BlankCommentsStateful(const Line: string; var InBrace, InStar: Boolean;
  out Clean: string);
var
  i, n : Integer;
begin
  Clean := Line;
  if (not InBrace) and (not InStar) and (not HasCommentOrLiteral(Line)) then
    Exit;
  // Lines[i] kann aus dem geteilten TFileTextCache stammen: erst
  // eindeutig machen, dann schreiben - sonst blankt der Detektor den
  // Puffer der nachfolgenden Detektoren mit.
  UniqueString(Clean);
  n := Length(Clean);
  i := 1;
  while i <= n do
  begin
    if InBrace then
    begin
      if Clean[i] = '}' then InBrace := False;
      Clean[i] := ' ';
      Inc(i);
      Continue;
    end;
    if InStar then
    begin
      if (Clean[i] = '*') and (i < n) and (Clean[i + 1] = ')') then
      begin
        InStar := False;
        Clean[i] := ' ';
        Clean[i + 1] := ' ';
        Inc(i, 2);
        Continue;
      end;
      Clean[i] := ' ';
      Inc(i);
      Continue;
    end;
    case Clean[i] of
      '{': begin InBrace := True; Clean[i] := ' '; Inc(i); end;
      '(': if (i < n) and (Clean[i + 1] = '*') then
           begin
             InStar := True;
             Clean[i] := ' ';
             Clean[i + 1] := ' ';
             Inc(i, 2);
           end
           else
             Inc(i);
      '/': if (i < n) and (Clean[i + 1] = '/') then
           begin
             while i <= n do
             begin
               Clean[i] := ' ';
               Inc(i);
             end;
           end
           else
             Inc(i);
      '''':
        begin
          // Literal komplett blanken ('' = Escape, bleibt im Literal).
          Clean[i] := ' ';
          Inc(i);
          while i <= n do
          begin
            if Clean[i] = '''' then
            begin
              if (i < n) and (Clean[i + 1] = '''') then
              begin
                Clean[i] := ' ';
                Clean[i + 1] := ' ';
                Inc(i, 2);
              end
              else
              begin
                Clean[i] := ' ';
                Inc(i);
                Break;
              end;
            end
            else
            begin
              Clean[i] := ' ';
              Inc(i);
            end;
          end;
        end;
    else
      Inc(i);
    end;
  end;
end;

// Liefert das erste Wort der Zeile (nach Leading-Whitespace, ohne
// Trailing-Garbage), plus die Spalte, an der es beginnt (1-basiert),
// und ob die ganze Zeile bis auf Whitespace/Semikolon nur dieses Wort
// enthaelt (RestEmpty). Wenn die Zeile leer ist oder mit Kommentar
// startet, gibt FirstWord = '' zurueck.
procedure ExtractFirstWord(const Line: string; out FirstWord: string;
  out StartCol: Integer; out RestEmpty: Boolean);
var
  i, n, wStart : Integer;
  c            : Char;
begin
  FirstWord := '';
  StartCol  := 0;
  RestEmpty := False;
  n := Length(Line);
  i := 1;
  while (i <= n) and CharInSet(Line[i], [' ', #9]) do Inc(i);
  if i > n then Exit;
  c := Line[i];
  // Kommentar-Start am Zeilenbeginn -> ignorieren
  if c = '{' then Exit;
  if (c = '/') and (i < n) and (Line[i + 1] = '/') then Exit;
  if (c = '(') and (i < n) and (Line[i + 1] = '*') then Exit;
  // Wort scannen
  if not CharInSet(c, ['A'..'Z','a'..'z','_']) then Exit;
  wStart := i;
  StartCol := wStart;
  while (i <= n) and CharInSet(Line[i], ['A'..'Z','a'..'z','0'..'9','_']) do
    Inc(i);
  FirstWord := Copy(Line, wStart, i - wStart);
  // RestEmpty: nur Whitespace + optional `;` bis Zeilenende
  RestEmpty := True;
  while i <= n do
  begin
    c := Line[i];
    if CharInSet(c, [' ', #9, ';']) then Inc(i)
    else begin RestEmpty := False; Break; end;
  end;
end;

class procedure TUnitLevelKeywordIndentDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines     : TStringList;
  i         : Integer;
  Cached    : Boolean;
  Word      : string;
  Lower     : string;
  Col       : Integer;
  RestEmpty : Boolean;
  F         : TLeakFinding;
  Clean     : string;
  // Kommentar-Zustand ueber Zeilengrenzen - der Grund fuer 175 der
  // 207 Korpus-Funde (s. BlankCommentsStateful).
  InBrace, InStar : Boolean;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    InBrace := False;
    InStar  := False;
    for i := 0 to Lines.Count - 1 do
    begin
      // Alles Weitere arbeitet auf der geblankten Zeile. Sie ist
      // gleich lang wie das Original, damit Col die echte Spalte
      // bleibt; RestEmpty sieht dadurch auch die Zeile
      // '  uses {$ifdef ...}' als Allein-Wort-Zeile
      // (pointer/BrainMM.pas:149 - echtes unit-level uses in Spalte 3,
      // vorher der einzige verfehlte TP).
      BlankCommentsStateful(Lines[i], InBrace, InStar, Clean);
      ExtractFirstWord(Clean, Word, Col, RestEmpty);
      if Word = '' then Continue;
      Lower := LowerCase(Word);
      if Col <= 1 then Continue;  // bereits auf Spalte 1
      if IsStrictSectionKw(Lower) then
      begin
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(i + 1);
        F.MissingVar := Format(
          'Unit-level keyword "%s" should start at column 1 ' +
          '(currently at column %d).', [Word, Col]);
        F.SetKind(fkUnitLevelKeywordIndent);
        Results.Add(F);
      end
      else if IsSoloOnlyKw(Lower) and RestEmpty then
      begin
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(i + 1);
        F.MissingVar := Format(
          'Unit-level keyword "%s" should start at column 1 ' +
          '(currently at column %d).', [Word, Col]);
        F.SetKind(fkUnitLevelKeywordIndent);
        Results.Add(F);
      end;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.

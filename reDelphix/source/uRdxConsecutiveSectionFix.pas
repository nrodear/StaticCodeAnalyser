unit uRdxConsecutiveSectionFix;

// reDelphix - Editorhilfe fuer SCA079 ConsecutiveSection, OHNE ToolsAPI und
// ohne Parser: der zweite von zwei gleichen Abschnitten ('const' nach
// 'const', 'var' nach 'var') verliert sein Schluesselwort und gehoert danach
// zum ersten. Bedeutungsgleich - ein Schluesselwort deklariert alle.
//
// DER FUND (uConsecutiveSection gelesen): der Detektor liest die Zeilen ohne
// Kommentare (Strings geblankt) und merkt sich das ERSTE Wort jeder Zeile
// auf Klammertiefe 0. Ist es 'const', 'type' oder 'var' (ohne ':=' auf der
// Zeile) und war das letzte solche Wort dasselbe, meldet er die Zeile:
// 'Consecutive `var` section - merge ...'. Andere Woerter dazwischen
// (Deklarationen) aendern nichts; 'procedure', 'function', 'begin', 'end',
// 'implementation' u. a. setzen zurueck - NICHT aber 'private', 'public',
// 'class', 'threadvar', 'resourcestring', 'label'. Eine Inline-Deklaration
// 'var X: T;' ohne ':=' im Rumpf meldet er ebenso (Recherche-Tabelle
// 2026-10-11): zwei davon sind zwei Anweisungen, kein Abschnitt.
//
// DIE HILFE: steht das Schluesselwort allein auf seiner Zeile, geht die
// ganze Zeile (der Bereich beginnt auf dem Schluesselwort, nie auf einer
// leeren Zeile); steht dahinter schon die erste Deklaration ('const B =
// 2;'), wird das Schluesselwort samt Leerraum zur Einrueckung der ersten
// Deklaration des ersten Abschnitts ('const A = 1;' -> Spalte von A).
//
// GESPERRT (lieber keine Hilfe als eine falsche):
//   * 'type' (der Auftrag nennt const und var) und Meldungen ohne Art,
//   * die Zeile beginnt nicht mit dem Schluesselwort (verschoben),
//   * das Schluesselwort steht in einem Anweisungsblock (begin/asm ...
//     end, initialization/finalization): eine Inline-Deklaration,
//   * zwischen den beiden Schluesselwoertern steht etwas anderes als
//     Deklarationen dieses Abschnitts - ein Sichtbarkeitswort ('public'),
//     'class var', 'threadvar', 'resourcestring', 'label', ein anderer
//     Abschnitt, ein Routinenkopf, ein Typ mit Rumpf (record ... end) -,
//     denn das Streichen haengte die Deklarationen dort an,
//   * der erste Abschnitt ist 'class var' bzw. 'class const',
//   * eine Compiler-Direktive zwischen den Schluesselwoertern (bedingter
//     Code kann beide brauchen: '{$IFDEF X} const A = 1; {$ELSE} const
//     ...'),
//   * ein Kommentar zwischen den Abschnitten oder auf der Zeile des zweiten
//     Schluesselworts (er ginge verloren bzw. beschriebe den falschen Teil),
//   * hinter dem Schluesselwort folgt keine Deklaration.
//
// OHNE ToolsAPI und ohne Delphi-only-Unit (FPC-Pruefstand): den Adapter
// PlanConsecutiveSection (Form TRdxFixPlanner) traegt die Tabelle
// uRdxFixTable.

interface

uses
  uRdxBufferMath,        // TRdxEdit
  uRdxCodeMap;           // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_CS_MSG = 'the message names no section';
  R_CS_KIND = 'only "const" and "var" sections are merged, not "%s"';
  R_CS_MOVED = 'the reported line does not start with "%s"';
  R_CS_INLINE = 'the keyword stands in a statement block - an inline '
    + 'declaration, not a section';
  R_CS_NO_FIRST = 'no previous "%s" section found';
  R_CS_BETWEEN = '"%s" stands between the two sections - the declarations '
    + 'of the second one would belong to it';
  R_CS_CLASS_SECTION = 'the previous section is "class %s"';
  R_CS_DIRECTIVE = 'compiler directive between the two sections - '
    + 'conditional code could need both keywords';
  R_CS_COMMENT = 'comment between the two sections or on the line of the '
    + 'keyword';
  R_CS_NO_DECL = 'no declaration follows the keyword';

type
  TRdxConsecutiveSectionFix = class
  public
    // SCA079: ALine ist die Zeile des zweiten Schluesselworts aus dem Fund,
    // AMessage nennt die Art ('Consecutive `var` section ...'). Die
    // Ersetzung loescht die Zeile bzw. das Schluesselwort; sonst der Grund.
    class function Merge(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // Steht AAt in einem Anweisungsblock - zwischen begin/asm und dem
    // passenden end (dort zaehlen try, case und record mit) oder hinter
    // initialization/finalization? Ein Lauf von Dateianfang bis AAt.
    class function InStatements(AMap: TRdxCodeMap;
      const AAt: TRdxToken): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,    // TRefactorSpan.Make
  uRdxText;         // _(): in die reDelphix-Sprache, nie uLocalization

const
  SPAN_079 = 'sca079';
  KW_CONST = 'const';
  KW_VAR   = 'var';
  // Was zwischen zwei Abschnitten derselben Art nicht stehen darf (als
  // Schluesselwort auf Klammertiefe 0): danach gehoerten die Deklarationen
  // des zweiten zu etwas anderem. Routinenwoerter nur als Kopf (ein
  // Prozedurtyp 'F: procedure;' ist eine Deklaration), 'class' nicht vor
  // 'of' (Metaklasse), 'object' nicht hinter 'of' ('procedure of object').
  BETWEEN_STOPS: array[0..33] of string = ('begin', 'end', 'asm', 'try',
    'case', 'record', 'object', 'class', 'interface', 'dispinterface',
    'implementation', 'initialization', 'finalization', 'uses', 'unit',
    'program', 'library', 'package', 'type', 'const', 'var', 'threadvar',
    'resourcestring', 'label', 'exports', 'property', 'private',
    'protected', 'public', 'published', 'strict', 'automated', 'helper',
    'operator');
  // Davor beginnt eine Anweisung - ein Schluesselwort dahinter ist eine
  // Inline-Deklaration.
  STATEMENT_WORDS: array[0..7] of string = ('begin', 'try', 'finally',
    'except', 'repeat', 'then', 'else', 'do');
  // Davor steht das 'class' eines Klassenkopfs, nicht von 'class var'.
  CLASS_HEAD_PREV: array[0..1] of string = ('=', 'packed');
  // Oeffnen einen Anweisungsblock (InStatements) ...
  BLOCK_WORDS: array[0..1] of string = ('begin', 'asm');
  // ... und schachteln in einem mit eigenem end.
  INNER_BLOCK_WORDS: array[0..2] of string = ('try', 'case', 'record');
  // Danach folgen nur Anweisungen bis zum Ende der Unit.
  INIT_WORDS: array[0..1] of string = ('initialization', 'finalization');
  // Alle Woerter, die InStatements zaehlt.
  SCAN_WORDS: array[0..7] of string = ('begin', 'asm', 'try', 'case',
    'record', 'end', 'initialization', 'finalization');

class function TRdxConsecutiveSectionFix.InStatements(AMap: TRdxCodeMap;
  const AAt: TRdxToken): Boolean;
var
  T, P  : TRdxToken;
  Depth : Integer;
  Init  : Boolean;
begin
  Depth := 0;
  Init := False;
  P := Default(TRdxToken);
  T := NextToken(AMap, 1, 1);
  while (T.Low <> '') and TokBefore(T, AAt) do
  begin
    // Erst das Wort, dann die Probe mit dem Token dahinter (':=' - ein
    // benanntes Argument 'End := 1'): IsKeywordAt liest ein Token mehr.
    if InList(T.Low, SCAN_WORDS) and IsKeywordAt(AMap, T, P) then
    begin
      if InList(T.Low, BLOCK_WORDS) then
        Inc(Depth)
      else if (Depth > 0) and InList(T.Low, INNER_BLOCK_WORDS) then
        Inc(Depth)
      else if T.Low = 'end' then
      begin
        if Depth > 0 then
          Dec(Depth);
      end
      else if (Depth = 0) and InList(T.Low, INIT_WORDS) then
        Init := True;
    end;
    P := T;
    T := After(AMap, T);
  end;
  Result := (Depth > 0) or Init;
end;

// Ein Schluesselwort an T (P davor) aus BETWEEN_STOPS, das die beiden
// Abschnitte trennt (s. dort)?
function IsStop(AMap: TRdxCodeMap; const T, P: TRdxToken): Boolean;
begin
  if InList(T.Low, ROUTINE_WORDS) then
    Exit(IsRoutineHeadAfter(T, P));
  Result := InList(T.Low, BETWEEN_STOPS) and IsKeywordAfter(T, P);
  if not Result then Exit;
  if T.Low = 'class' then
    Result := After(AMap, T).Low <> 'of'
  else if T.Low = 'object' then
    Result := P.Low <> 'of';
end;

// Das erste Schluesselwort AWord vor AK2 auf Klammertiefe 0: '' mit ihm in
// AK1, sonst der Grund (ein Stopp dazwischen, keines bis zum Dateianfang,
// eine offene Klammer).
function FirstSection(AMap: TRdxCodeMap; const AK2: TRdxToken;
  const AWord: string; out AK1: TRdxToken): string;
var
  T, P  : TRdxToken;
  Depth : Integer;
begin
  AK1 := Default(TRdxToken);
  Depth := 0;
  T := Before(AMap, AK2);
  while T.Low <> '' do
  begin
    P := Before(AMap, T);
    if (T.Low = ')') or (T.Low = ']') then
      Inc(Depth)
    else if (T.Low = '(') or (T.Low = '[') then
    begin
      Dec(Depth);
      if Depth < 0 then
        Exit(_(R_CS_BETWEEN, [T.Low]));
    end
    else if Depth = 0 then
    begin
      if (T.Low = AWord) and IsKeywordAfter(T, P) then
      begin
        AK1 := T;
        Exit('');
      end;
      if IsStop(AMap, T, P) then
        Exit(_(R_CS_BETWEEN, [TokText(AMap, T)]));
    end;
    T := P;
  end;
  Result := _(R_CS_NO_FIRST, [AWord]);
end;

// Ein Kommentar (auch eine Direktive) auf den Zeilen zwischen AP und AK2
// oder auf der Zeile von AK2 vor AK2? Steht AP auf derselben Zeile, ab
// hinter AP.
function CommentBetweenLines(AMap: TRdxCodeMap;
  const AP, AK2: TRdxToken): Boolean;
var
  Li, First : Integer;
begin
  for Li := AP.Line + 1 to AK2.Line - 1 do
    if AMap.HasComment(Li, 1, Length(AMap.Raw(Li))) then
      Exit(True);
  First := 1;
  if AP.Line = AK2.Line then
    First := AP.EndCol;
  Result := AMap.HasComment(AK2.Line, First, AK2.Col - 1);
end;

// Die Zeichen von S bis Spalte AUpTo (einschliesslich) als Einrueckung:
// Tabs bleiben, alles andere wird Leerzeichen.
function BlankedPrefix(const S: string; AUpTo: Integer): string;
var
  i : Integer;
begin
  Result := Copy(S, 1, AUpTo);
  for i := 1 to Length(Result) do
    if Result[i] <> #9 then
      Result[i] := ' ';
end;

// Die Einrueckung der Deklarationen des ersten Abschnitts: bis vor seine
// erste Deklaration (auch auf der Zeile von AK1 - 'const A = 1;'). Ist er
// leer, die Einrueckung der Zeile von AK2 und zwei Leerzeichen.
function SectionIndent(AMap: TRdxCodeMap; const AK1, AK2: TRdxToken): string;
var
  D1 : TRdxToken;
begin
  D1 := After(AMap, AK1);
  if SameTok(D1, AK2) then
    Result := BlankedPrefix(AMap.Raw(AK2.Line), AK2.Col - 1) + '  '
  else
    Result := BlankedPrefix(AMap.Raw(D1.Line), D1.Col - 1);
end;

class function TRdxConsecutiveSectionFix.Merge(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  Word, L    : string;
  K1, K2     : TRdxToken;
  P, D2, P1  : TRdxToken;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  Word := LowerCase(QuotedText(AMessage, '`'));
  if Word = '' then
  begin
    AReason := _(R_CS_MSG);
    Exit;
  end;
  if (Word <> KW_CONST) and (Word <> KW_VAR) then
  begin
    AReason := _(R_CS_KIND, [Word]);
    Exit;
  end;
  if (ALine < 1) or (ALine > AMap.LineCount) or AMap.StartsInside(ALine) then
    K2 := Default(TRdxToken)
  else
    K2 := NextToken(AMap, ALine, 1);
  if (K2.Line <> ALine) or (K2.Low <> Word)
     or not IsKeywordAfter(K2, Before(AMap, K2)) then
  begin
    AReason := MsgMovedSuffix(_(R_CS_MOVED, [Word]));
    Exit;
  end;
  if InStatements(AMap, K2) then
  begin
    AReason := _(R_CS_INLINE);
    Exit;
  end;
  AReason := FirstSection(AMap, K2, Word, K1);
  if AReason <> '' then
    Exit;
  // 'class var'/'class const' - nicht das 'class' eines Klassenkopfs
  // ('TFoo = class' direkt vor dem ersten Abschnitt).
  P1 := Before(AMap, K1);
  P := Before(AMap, P1);
  if (P1.Low = 'class') and IsKeywordAfter(P1, P)
     and not InList(P.Low, CLASS_HEAD_PREV) then
    AReason := _(R_CS_CLASS_SECTION, [Word])
  else if InList(P1.Low, STATEMENT_WORDS) then
    AReason := _(R_CS_INLINE)
  else if DirectiveBetween(AMap, K1, K2.Line, K2.Col) then
    AReason := _(R_CS_DIRECTIVE);
  if AReason <> '' then
    Exit;
  // Kommentar zwischen den Abschnitten (die Zeilen zwischen dem Token vor K2
  // und K2) bzw. auf der Zeile von K2 - davor oder dahinter. Ein Kommentar
  // hinter der letzten Deklaration des ersten Abschnitts bleibt, wo er ist.
  P := Before(AMap, K2);
  L := AMap.Raw(ALine);
  D2 := After(AMap, K2);
  if CommentBetweenLines(AMap, P, K2)
     or ((D2.Line = ALine) and AMap.HasComment(ALine, K2.EndCol, D2.Col - 1))
     or ((D2.Line <> ALine) and AMap.HasComment(ALine, K2.EndCol, Length(L))) then
  begin
    AReason := _(R_CS_COMMENT);
    Exit;
  end;
  if not D2.IsWord or IsStop(AMap, D2, K2) or (D2.Low = Word) then
  begin
    AReason := _(R_CS_NO_DECL);
    Exit;
  end;
  if D2.Line <> ALine then
  begin
    // Das Schluesselwort allein: die ganze Zeile samt Zeilenende. Sie
    // beginnt auf dem Schluesselwort (keine leere Zeile, SpanFits); eine
    // Deklaration folgt, also ist sie nicht die letzte der Datei.
    AEdit.Span := TRefactorSpan.Make(SPAN_079, ALine, 1, ALine + 1, 1);
    AEdit.NewText := '';
  end
  else
  begin
    AEdit.Span := TRefactorSpan.Make(SPAN_079, ALine, 1, ALine, D2.Col);
    AEdit.NewText := SectionIndent(AMap, K1, K2);
  end;
  AEdit.Expected := RangeText(AMap, AEdit.Span);
  Result := True;
end;

end.

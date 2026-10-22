unit uRdxEmptyExceptFix;

// reDelphix - Editorhilfe SCA002 EmptyExcept, OHNE ToolsAPI und ohne Parser
// (Konzept_Editorhilfen_Regelliste_2026-10-11, Entscheid E9: der Detektor
// bleibt):
//   'try X; except end;' -> 'try X; except raise; end;' - der leere
//   except-Block bekommt ein 'raise;'. AENDERT DAS VERHALTEN: eine Exception,
//   die bisher verschluckt wurde, laeuft jetzt nach aussen (Changes: True).
//
// WAS DER DETEKTOR MELDET (uCodeSmells2, TEmptyExceptDetector2): einen
// nkExceptBlock ohne Kinder, auf der Zeile des Schluesselworts except. Das
// sind 'except end' (mit oder ohne Kommentar dazwischen - der Lexer
// ueberspringt ihn) und - je nach Parser - ein Block aus lauter leeren
// Anweisungen. Ein Block mit 'on E: T do ;' hat ein Kind und wird nicht
// gemeldet; die leere Handlerform (SCA159) ist eine andere Regel. Die
// Meldung traegt weder Spalte noch Namen, nur die Zeile.
//
// Die Hilfe gilt nur der EINDEUTIGEN Form: hinter except steht (ueber
// Zeilen hinweg) nur Leerraum und das end.
//   * 'except' und 'end' auf EINER Zeile ('try Work except end;'): das
//     raise kommt inline hinter das except ('except raise; end;').
//   * 'except' und 'end' auf verschiedenen Zeilen: das raise steht in einer
//     NEUEN Zeile direkt unter der except-Zeile, eingerueckt wie die
//     except-Zeile plus eine Stufe (die Stufe liest der Planer aus dem
//     try-Rumpf davor, sonst zwei Leerzeichen bzw. ein Tab).
//
// SPERREN (lieber keine Hilfe als eine falsche):
//   * auf der Zeile nicht genau ein except (kein Treffer = Zeile
//     verschoben, mehrere = mehrdeutig);
//   * zwischen except und end steht etwas anderes als Leerraum - ein
//     Handler, eine Anweisung, ein ';', ein else (der Fund ist dann
//     veraltet oder die Form nicht die eindeutige);
//   * ein Kommentar oder eine Direktive zwischen except und end oder hinter
//     dem end auf seiner Zeile ('end; // darf scheitern') - ein Kommentar
//     ist Absicht ('// ignore errors', 'TODO'), keine Hilfe (wie SCA159);
//   * eine Compiler-Direktive auf den Zeilen von except bis end.
// Zeilenenden und Einrueckungsart (Tab oder Leerzeichen) des Umfelds
// bleiben; die neue Zeile ist LF und wird vom Editor ans Zeilenende des
// Puffers angepasst wie bei den Nachbarn.

interface

uses
  uRdxBufferMath,    // TRdxEdit
  uRdxCodeMap;       // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_EXC_MOVED     = 'no "except" at the reported place';
  R_EXC_MANY      = 'the reported line carries several "except" - ambiguous';
  R_EXC_NOT_EMPTY = 'something other than blanks stands between "except" '
    + 'and "end" (handler, statement, ";" or "else")';
  R_EXC_COMMENT   = 'comment inside or behind the except block - a comment '
    + 'is intent, no help';
  R_EXC_DIRECTIVE = 'compiler directive on the lines of the except block';

type
  // Der Planer von SCA002 (Form TRdxMapPlanner, uRdxFixRunner).
  TRdxEmptyExceptFix = class
  public
    // ALine ist die Zeile des except (die Meldung traegt keine Spalte);
    // AMessage wird nicht gebraucht. Liefert die eine Ersetzung des
    // Schluesselworts except durch 'except raise;' (inline) bzw. 'except' +
    // neue Zeile mit 'raise;', oder den Grund.
    class function AddRaise(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxText;          // _(): in die reDelphix-Sprache (E29), nie uLocalization

const
  SPAN_002 = 'sca002';
  KW_EXCEPT = 'except';
  KW_END    = 'end';
  RAISE_STMT = 'raise;';
  // So weit zurueck sucht die Planung die Einrueckstufe des try-Rumpfs.
  STEP_LOOKBACK = 200;

// Das Schluesselwort except (CountTokensOnLine) - nicht 'X.Except'.
function IsExceptWord(AMap: TRdxCodeMap; const T: TRdxToken;
  const AArg: string): Boolean;
begin
  Result := (T.Low = KW_EXCEPT) and IsKeywordAfter(T, Before(AMap, T));
end;

// Genau ein Schluesselwort except auf ALine. '' oder der Grund. Der Lauf
// ist CountTokensOnLine (uRdxCodeMap; bis zur Folgewelle des
// Wochen-Reviews, G09-16, hier ausgeschrieben), die Gruende bleiben hier.
function FindExcept(AMap: TRdxCodeMap; ALine: Integer;
  out AExc: TRdxToken): string;
var
  n : Integer;
begin
  n := CountTokensOnLine(AMap, ALine, IsExceptWord, '', AExc);
  Result := '';
  if n = 0 then
    Result := MsgMovedSuffix(_(R_EXC_MOVED))
  else if n > 1 then
    Result := _(R_EXC_MANY);
end;

// Steht zwischen AExc und AEnd ein Kommentar oder eine Direktive? Die Map
// fuehrt beides als Klasse 'k'.
function CommentBetween(AMap: TRdxCodeMap; const AExc, AEnd: TRdxToken): Boolean;
var
  Li, j, First, Last : Integer;
  L                  : string;
begin
  Result := False;
  for Li := AExc.Line to AEnd.Line do
  begin
    L := AMap.Raw(Li);
    First := 1;
    Last := Length(L);
    if Li = AExc.Line then
      First := AExc.EndCol;
    if Li = AEnd.Line then
      Last := AEnd.Col - 1;
    for j := First to Last do
      if AMap.ClassAt(Li, j) = 'k' then
        Exit(True);
  end;
end;

// Folgt auf except unmittelbar das Schluesselwort end, ohne Kommentar
// dazwischen? '' oder der Grund.
function EmptyReason(AMap: TRdxCodeMap; const AExc: TRdxToken;
  out AEnd: TRdxToken): string;
begin
  Result := '';
  AEnd := After(AMap, AExc);
  if (AEnd.Low <> KW_END) or not IsKeywordAfter(AEnd, AExc) then
    Exit(_(R_EXC_NOT_EMPTY));
  if DirectiveInLines(AMap, AExc.Line, AEnd.Line) then
    Exit(_(R_EXC_DIRECTIVE));
  // Auch ein Kommentar hinter dem end auf seiner Zeile ('end; // darf
  // scheitern') begruendet das Verschlucken - wie bei SCA159.
  if CommentBetween(AMap, AExc, AEnd)
     or AMap.HasComment(AEnd.Line, AEnd.EndCol, Length(AMap.Raw(AEnd.Line))) then
    Result := _(R_EXC_COMMENT);
end;

// Die Zeile ab dem ersten Nicht-Leerraum beginnt mit einem Kommentar (oder
// ist leer) - sie sagt nichts ueber die Einrueckung des Codes.
function IsCommentOrBlank(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  Col : Integer;
begin
  Col := SkipBlanks(AMap.Raw(ALine), 1);
  Result := (Col > Length(AMap.Raw(ALine))) or (AMap.ClassAt(ALine, Col) = 'k');
end;

// Die Einrueckstufe unter der except-Zeile: die kleinste Einrueckung der
// Code-Zeilen davor, die tiefer liegen als except, bis zu einer Zeile auf
// der Ebene von except oder flacher (meist die try-Zeile). Ohne solche
// Zeile (leerer try-Rumpf) ein Tab bzw. zwei Leerzeichen (IndentStep).
function StepBelow(AMap: TRdxCodeMap; const AExc: TRdxToken;
  const AIndent: string): string;
var
  Li, Stop  : Integer;
  Ind, Best : string;
begin
  Best := '';
  Stop := AExc.Line - STEP_LOOKBACK;
  if Stop < 1 then
    Stop := 1;
  for Li := AExc.Line - 1 downto Stop do
  begin
    if AMap.StartsInside(Li) or IsCommentOrBlank(AMap, Li) then
      Continue;
    Ind := IndentOf(AMap.Raw(Li));
    if (Length(Ind) > Length(AIndent))
       and (Copy(Ind, 1, Length(AIndent)) = AIndent) then
    begin
      if (Best = '') or (Length(Ind) < Length(Best)) then
        Best := Ind;
    end
    else
      Break;
  end;
  Result := IndentStep(AIndent, Best);
end;

{ TRdxEmptyExceptFix }

class function TRdxEmptyExceptFix.AddRaise(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Exc, EndTok : TRdxToken;
  Kw, Indent  : string;
begin
  AEdit := Default(TRdxEdit);
  AReason := FindExcept(AMap, ALine, Exc);
  if AReason = '' then
    AReason := EmptyReason(AMap, Exc, EndTok);
  Result := AReason = '';
  if not Result then
    Exit;
  Kw := TokText(AMap, Exc);
  AEdit.Span := TRefactorSpan.Make(SPAN_002, Exc.Line, Exc.Col, Exc.Line,
    Exc.EndCol);
  AEdit.Expected := Kw;
  if EndTok.Line = Exc.Line then
    AEdit.NewText := Kw + ' ' + RAISE_STMT
  else
  begin
    Indent := IndentOf(AMap.Raw(Exc.Line));
    AEdit.NewText := Kw + #10 + Indent + StepBelow(AMap, Exc, Indent)
      + RAISE_STMT;
  end;
end;

end.

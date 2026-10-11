unit uVnpPlan;

// VarNameProject - die reine Textlogik, OHNE ToolsAPI (laeuft auch unter
// FPC): das Zahl-Literal unter dem Caret finden, alle gleichen Literale
// derselben Zeile, die Deklarationszeile 'var <Name> := <Literal>;' und
// die Spalten nach dem Schreiben. Das Testprojekt prueft die Eingabe des
// Namens (Nico 2026-10-11, E17: wie ReSharper - der Code entsteht mit
// einem vorlaeufigen Namen, der Name wird umrandet, der Caret steht
// darauf, Tippen aendert alle Stellen mit). Diese Unit liefert nur WAS
// geschrieben wird und WO der Name danach steht.
//
// Spalten sind 1-basierte Zeichenspalten der Zeile (UTF-16), Bytes
// werden erst in uVnpIntroduce gerechnet (Utf8Len).

interface

uses
  System.SysUtils;

type
  TVnpPlan = record
    Ok         : Boolean;
    Reason     : string;           // warum nicht (Ok = False)
    Literal    : string;           // '42', '$FF', '3.5'
    Indent     : string;           // Einrueckung der Zeile
    DeclText   : string;           // Indent + 'var Name := Literal;'
    NameCol    : Integer;          // Spalte des Namens in DeclText
    OldCols    : TArray<Integer>;  // Spalten der Literale vor dem Schreiben
    NewCols    : TArray<Integer>;  // dieselben Stellen nach dem Ersetzen
    NewUseLine : string;           // die Zeile nach dem Ersetzen
    // Die Zeile ist die einzige Anweisung eines Zweigs (die Zeile darueber
    // endet mit then/do/else): sie kommt mit der Deklaration in einen
    // neuen begin..end-Block (Nico 2026-10-11, Fall 3). 'begin' steht
    // direkt unter der Zweigzeile, 'end;' unter der Anweisung, beide mit
    // der Einrueckung der Zweigzeile.
    Wrap        : Boolean;
    BlockIndent : string;
  end;

// Plan fuer die Zeile ALine mit dem Caret in Spalte ACaretCol (vor dem
// Zeichen ACaretCol; direkt hinter dem Literal zaehlt auch). APrevCode ist
// die naechste Zeile mit Code darueber: die Deklaration kommt VOR die
// Zeile, also muss dort eine Anweisung zu Ende sein - oder ein Zweig
// (then/do/else), dann mit begin..end (Wrap).
function PlanIntroduce(const ALine, APrevCode: string; ACaretCol: Integer;
  const AName: string): TVnpPlan;

// Der Code-Anteil der Zeile: Strings bleiben, Kommentare fallen weg
// (eine Kommentarzeile ergibt ''). Kommentare ueber Zeilen sieht die
// Zeile nicht.
function CodePart(const ALine: string): string;

// ABase + '01', '02', ... - der erste Name, der in AText nicht als ganzes
// Wort vorkommt (Gross/Klein egal).
function NextFreeName(const AText, ABase: string): string;

// Zahl der UTF-8-Bytes von S.
function Utf8Len(const S: string): Integer;

// Zeichenspalte (1-basiert) zum 0-basierten UTF-8-Byteindex der Zeile.
function CharColOfByte(const ALine: string; AByteIndex: Integer): Integer;

implementation

type
  // Ein Zahl-Literal der Zeile: Spalten [First, Stop).
  TVnpRange = record
    First : Integer;
    Stop  : Integer;
  end;

const
  // Hinter diesen Woertern beginnt eine Anweisung (letztes Wort der Zeile
  // darueber).
  STATEMENT_OPENERS: array[0..4] of string = ('begin', 'try', 'finally',
    'except', 'repeat');
  // Mit diesen Woertern beginnt keine eigene Anweisung - davor darf keine
  // Deklaration.
  NOT_A_START: array[0..8] of string = ('end', 'else', 'until', 'except',
    'finally', 'then', 'do', 'of', 'begin');
  // Hinter diesen Woertern steht genau EINE Anweisung (Zweig ohne begin).
  BRANCH_ENDS: array[0..2] of string = ('then', 'do', 'else');

function InList(const AWord: string; const AList: array of string): Boolean;
var
  S : string;
begin
  Result := False;
  for S in AList do
    if SameText(AWord, S) then
      Exit(True);
end;

function IsIdentChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

function IsDigit(C: Char): Boolean;
begin
  Result := CharInSet(C, ['0'..'9']);
end;

function IsHexDigit(C: Char): Boolean;
begin
  Result := CharInSet(C, ['0'..'9', 'A'..'F', 'a'..'f']);
end;

// Das Zeichen an Stelle i, #0 ausserhalb der Zeile.
function CharAt(const S: string; i: Integer): Char;
begin
  Result := #0;
  if (i >= 1) and (i <= Length(S)) then
    Result := S[i];
end;

// Zustand nach Zeichen i, wenn bisher Code war: Beginn eines Strings oder
// Kommentars?
function FromCode(const ALine: string; i: Integer): Char;
var
  Two : string;
begin
  Two := Copy(ALine, i, 2);
  if ALine[i] = '''' then
    Result := 's'
  else if ALine[i] = '{' then
    Result := 'b'
  else if Two = '(*' then
    Result := 'p'
  else if Two = '//' then
    Result := 'l'
  else
    Result := 'c';
end;

// Naechster Zustand des Zeilen-Lesers an Zeichen i: 'c' Code, 's' String,
// 'e' Quote im String (Ende oder ''), 'b' {}, 'p' (* *), 'l' //, 'x' Ende
// eines Kommentars.
function StepState(const ALine: string; i: Integer; AState: Char): Char;
begin
  Result := AState;
  case AState of
    'c':
      Result := FromCode(ALine, i);
    's':
      if ALine[i] = '''' then
        Result := 'e';
    'b':
      if ALine[i] = '}' then
        Result := 'x';
    'p':
      if Copy(ALine, i - 1, 2) = '*)' then
        Result := 'x';
  else
    ;   // 'l' bleibt bis zum Zeilenende
  end;
end;

// Klasse eines Zustands: 'c' Code, 's' String, 'k' Kommentar.
function ClassOfState(AState: Char): Char;
begin
  case AState of
    'c':
      Result := 'c';
    's', 'e':
      Result := 's';
  else
    Result := 'k';
  end;
end;

// Klassen der Zeichen einer Zeile: 'c' Code, 's' String (samt Quotes),
// 'k' Kommentar. Kennt '...' (mit ''), {...}, (*...*) und //; ein
// Kommentar, der in einer frueheren Zeile beginnt, ist hier unsichtbar.
function ClassesOf(const ALine: string): string;
var
  i     : Integer;
  State : Char;
begin
  Result := StringOfChar('c', Length(ALine));
  State := 'c';
  i := 1;
  while i <= Length(ALine) do
  begin
    State := StepState(ALine, i, State);
    Result[i] := ClassOfState(State);
    if (State = 'e') and (CharAt(ALine, i + 1) = '''') then
    begin
      // '' im String: weiter im String.
      Inc(i);
      Result[i] := 's';
      State := 's';
    end
    else if CharInSet(State, ['e', 'x']) then
      State := 'c';
    Inc(i);
  end;
end;

// Ende (exklusiv) einer Folge von Dezimalziffern und '_' (Zifferntrenner,
// Delphi 11) ab AFrom.
function DecEnd(const ALine: string; AFrom: Integer): Integer;
begin
  Result := AFrom;
  while IsDigit(CharAt(ALine, Result)) or (CharAt(ALine, Result) = '_') do
    Inc(Result);
end;

// Dasselbe fuer Hex-Ziffern.
function HexEnd(const ALine: string; AFrom: Integer): Integer;
begin
  Result := AFrom;
  while IsHexDigit(CharAt(ALine, Result)) or (CharAt(ALine, Result) = '_') do
    Inc(Result);
end;

// Ein Exponent ab i ('e5', 'E-3')? Sein Ende, sonst i.
function ExponentEnd(const ALine: string; i: Integer): Integer;
var
  j : Integer;
begin
  Result := i;
  if not CharInSet(CharAt(ALine, i), ['e', 'E']) then
    Exit;
  j := i + 1;
  if CharInSet(CharAt(ALine, j), ['+', '-']) then
    Inc(j);
  if IsDigit(CharAt(ALine, j)) then
    Result := DecEnd(ALine, j);
end;

// Ende (exklusiv) eines Zahl-Literals ab AStart (dort beginnt eines, siehe
// NumberStartsAt): dezimal mit Bruch und Exponent oder hex mit '$'. Ein
// '.' nur mit Ziffer dahinter - '1..5' ist ein Bereich.
function NumberEnd(const ALine: string; AStart: Integer): Integer;
var
  i : Integer;
begin
  if ALine[AStart] = '$' then
    Exit(HexEnd(ALine, AStart + 1));
  i := DecEnd(ALine, AStart);
  if (CharAt(ALine, i) = '.') and IsDigit(CharAt(ALine, i + 1)) then
    i := DecEnd(ALine, i + 1);
  Result := ExponentEnd(ALine, i);
end;

// Beginnt an AStart (im Code) ein eigenstaendiges Zahl-Literal? Davor kein
// Bezeichner-Zeichen, kein '#' (Zeichencode), kein '.' und kein '$'.
function NumberStartsAt(const ALine, AClasses: string;
  AStart: Integer): Boolean;
begin
  Result := (AClasses[AStart] = 'c')
    and (IsDigit(ALine[AStart])
         or ((ALine[AStart] = '$') and (AStart < Length(ALine))
             and IsHexDigit(ALine[AStart + 1])));
  if Result and (AStart > 1) then
    Result := not (IsIdentChar(ALine[AStart - 1])
      or CharInSet(ALine[AStart - 1], ['#', '.', '$', '&', '%']));
end;

// Alle Zahl-Literale der Zeile.
function NumbersOf(const ALine: string): TArray<TVnpRange>;
var
  Classes : string;
  i, e    : Integer;
  R       : TVnpRange;
begin
  Result := nil;
  Classes := ClassesOf(ALine);
  i := 1;
  while i <= Length(ALine) do
  begin
    if NumberStartsAt(ALine, Classes, i) then
    begin
      e := NumberEnd(ALine, i);
      if (e > i) and ((e > Length(ALine)) or not IsIdentChar(ALine[e])) then
      begin
        R.First := i;
        R.Stop := e;
        Result := Result + [R];
        i := e;
        Continue;
      end;
    end;
    Inc(i);
  end;
end;

function FirstWord(const ALine: string): string;
var
  i, j : Integer;
begin
  i := 1;
  while (i <= Length(ALine)) and CharInSet(ALine[i], [' ', #9]) do
    Inc(i);
  j := i;
  while (j <= Length(ALine)) and IsIdentChar(ALine[j]) do
    Inc(j);
  Result := Copy(ALine, i, j - i);
end;

function CodePart(const ALine: string): string;
var
  Classes : string;
  i, n    : Integer;
begin
  Classes := ClassesOf(ALine);
  SetLength(Result, Length(ALine));
  n := 0;
  for i := 1 to Length(ALine) do
    if Classes[i] <> 'k' then
    begin
      Inc(n);
      Result[n] := ALine[i];
    end;
  SetLength(Result, n);
end;

// Das letzte Wort im Code-Anteil von ALine ('' wenn er nicht auf ein Wort
// endet).
function LastWord(const ALine: string): string;
var
  S : string;
  i : Integer;
begin
  S := Trim(CodePart(ALine));
  i := Length(S);
  while (i > 0) and IsIdentChar(S[i]) do
    Dec(i);
  Result := Copy(S, i + 1, MaxInt);
end;

// Endet der Code-Anteil von ALine mit ';'?
function EndsWithSemicolon(const ALine: string): Boolean;
var
  S : string;
begin
  S := Trim(CodePart(ALine));
  Result := (S <> '') and (S[Length(S)] = ';');
end;

// Endet die Zeile darueber eine Anweisung? ';' am Ende oder ein Wort aus
// STATEMENT_OPENERS (ein '//'-Kommentar dahinter wird abgeschnitten).
function PrevEndsStatement(const APrevCode: string): Boolean;
begin
  Result := EndsWithSemicolon(APrevCode)
    or InList(LastWord(APrevCode), STATEMENT_OPENERS);
end;

// Ist die Zeile ein case-Zweig, eine Sprungmarke oder ein on-Handler ('1: X
// := 5;', 'Fertig: ...', 'on E: Exception do ...')? Der erste ':' im Code
// (nicht in Strings/Kommentaren) gehoert dann nicht zu ':='. Dort darf
// keine Deklaration davor - zwischen case-Zweigen bzw. on-Handlern ist sie
// ungueltig. var/const-Zeilen ('var X: Integer := 5;') zaehlen nicht.
function IsLabeled(const ALine: string): Boolean;
var
  Classes, W : string;
  i          : Integer;
begin
  Result := False;
  W := LowerCase(FirstWord(ALine));
  if (W = 'var') or (W = 'const') then
    Exit;
  Classes := ClassesOf(ALine);
  for i := 1 to Length(ALine) do
    if (Classes[i] = 'c') and (ALine[i] = ':') then
      Exit(CharAt(ALine, i + 1) <> '=');
end;

// Steht das Literal schon ALLEIN als Wert einer Deklaration ('var X :=
// 42;', 'const X = 42;', auch mit Typangabe)? Dann hat es bereits einen
// Namen - Lauf 5 (2026-10-11) baute sonst 'var MagicNr05 := 42;' vor
// 'var MagicNr01 := MagicNr05;'. 'var B := X = 42;' bleibt erlaubt (dort
// ist das Literal nur ein Teil des Werts).
function AlreadyNamed(const ALine, ALiteral: string): Boolean;
var
  S, W : string;
  P    : Integer;
begin
  Result := False;
  W := LowerCase(FirstWord(ALine));
  if (W <> 'var') and (W <> 'const') then
    Exit;
  S := LowerCase(StringReplace(StringReplace(Trim(CodePart(ALine)), ' ', '',
    [rfReplaceAll]), #9, '', [rfReplaceAll]));
  if W = 'var' then
    P := Pos(':=', S) + 2
  else
    P := Pos('=', S) + 1;
  Result := (P > 2) and (Copy(S, P, MaxInt) = LowerCase(ALiteral) + ';');
end;

// Darf vor ALine eine Deklaration (APlan.Literal steht schon)? '' oder der
// Grund. Setzt APlan.Wrap, wenn ALine die einzige Anweisung eines Zweigs
// ist - dann nur, wenn sie auf dieser Zeile mit ';' endet (mehrzeilige
// Anweisungen und solche vor 'else' kann der Text-Leser nicht abgrenzen).
function PlanReason(const ALine, APrevCode: string;
  var APlan: TVnpPlan): string;
begin
  Result := '';
  if AlreadyNamed(ALine, APlan.Literal) then
    Exit('das Literal ist schon allein der Wert einer Deklaration - es hat '
      + 'bereits einen Namen');
  if InList(FirstWord(ALine), NOT_A_START) then
    Exit(Format('die Zeile beginnt mit "%s" - davor darf keine Deklaration',
      [FirstWord(ALine)]));
  if IsLabeled(ALine) then
    Exit('die Zeile ist ein case-Zweig, eine Sprungmarke oder ein '
      + 'on-Handler - davor darf keine Deklaration');
  if PrevEndsStatement(APrevCode) then
    Exit;
  APlan.Wrap := InList(LastWord(APrevCode), BRANCH_ENDS);
  if not APlan.Wrap then
    Exit('die Zeile darueber endet weder eine Anweisung noch mit then/do/'
      + 'else - unklar, wohin die Deklaration gehoert');
  if not EndsWithSemicolon(ALine) then
    Exit('die Anweisung im Zweig endet nicht auf dieser Zeile mit ";" '
      + '(mehrzeilig oder vor else) - nicht unterstuetzt');
end;

function PlanIntroduce(const ALine, APrevCode: string; ACaretCol: Integer;
  const AName: string): TVnpPlan;
var
  Nums  : TArray<TVnpRange>;
  N     : TVnpRange;
  Shift : Integer;
begin
  Result := Default(TVnpPlan);
  Nums := NumbersOf(ALine);
  for N in Nums do
    if (N.First <= ACaretCol) and (ACaretCol <= N.Stop) then
      Result.Literal := Copy(ALine, N.First, N.Stop - N.First);
  if Result.Literal = '' then
  begin
    Result.Reason := 'kein Zahl-Literal am Caret';
    Exit;
  end;
  Result.Reason := PlanReason(ALine, APrevCode, Result);
  if Result.Reason <> '' then
  begin
    Result.Wrap := False;
    Exit;
  end;
  if Result.Wrap then
    Result.BlockIndent := Copy(APrevCode, 1,
      Length(APrevCode) - Length(TrimLeft(APrevCode)));
  Result.Indent := Copy(ALine, 1, Length(ALine) - Length(TrimLeft(ALine)));
  Result.DeclText := Result.Indent + 'var ' + AName + ' := ' + Result.Literal
    + ';';
  Result.NameCol := Length(Result.Indent) + 5;
  // Alle gleichen Literale der Zeile, von links; jede Ersetzung schiebt die
  // folgenden um die Laengendifferenz.
  Result.NewUseLine := ALine;
  Shift := 0;
  for N in Nums do
    if Copy(ALine, N.First, N.Stop - N.First) = Result.Literal then
    begin
      Result.OldCols := Result.OldCols + [N.First];
      Result.NewCols := Result.NewCols + [N.First + Shift];
      Delete(Result.NewUseLine, N.First + Shift, Length(Result.Literal));
      Insert(AName, Result.NewUseLine, N.First + Shift);
      Inc(Shift, Length(AName) - Length(Result.Literal));
    end;
  Result.Ok := True;
end;

function ContainsWord(const AText, AWord: string): Boolean;
var
  P, After : Integer;
  U, W     : string;
begin
  U := UpperCase(AText);
  W := UpperCase(AWord);
  P := Pos(W, U);
  while P > 0 do
  begin
    After := P + Length(W);
    if ((P = 1) or not IsIdentChar(U[P - 1]))
       and ((After > Length(U)) or not IsIdentChar(U[After])) then
      Exit(True);
    P := Pos(W, U, P + 1);
  end;
  Result := False;
end;

function NextFreeName(const AText, ABase: string): string;
var
  i : Integer;
begin
  for i := 1 to 99 do
  begin
    Result := ABase + Format('%.2d', [i]);
    if not ContainsWord(AText, Result) then
      Exit;
  end;
  Result := ABase + 'X';
end;

function Utf8Len(const S: string): Integer;
begin
  Result := TEncoding.UTF8.GetByteCount(S);
end;

function CharColOfByte(const ALine: string; AByteIndex: Integer): Integer;
var
  Col : Integer;
begin
  Col := 1;
  while (Col <= Length(ALine))
     and (Utf8Len(Copy(ALine, 1, Col)) <= AByteIndex) do
    Inc(Col);
  Result := Col;
end;

end.

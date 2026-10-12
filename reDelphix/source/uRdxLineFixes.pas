unit uRdxLineFixes;

// reDelphix - Editorhilfen an EINER Zeile, OHNE ToolsAPI und ohne Parser
// (Konzept_Editorhilfen_2026-10-08, Abschnitte 4.3, 4.4, 4.7):
//   SCA082 SuperfluousSemicolon: '; ;' -> ';' an der Spalte aus der Meldung.
//   SCA071 UnitLevelKeywordIndent: die Einrueckung vor dem Schluesselwort
//          loeschen (Spalte 1).
//   SCA088 LegacyInitializationSection: das begin des Unit-Rumpfs
//          ('begin .. end.') wird initialization.
//   SCA123 CastAndFree: 'TFoo(X).Free' -> 'X.Free'.
// Alle vier aendern die Bedeutung nicht. GRUNDSATZ wie in uRdxSimpleFixes:
// lieber keine Hilfe als eine falsche - der Planer prueft den Fund am
// aktuellen Text nach, statt dem Detektor zu glauben.

interface

uses
  System.SysUtils,
  uRefactorInfo, uRdxBufferMath, uRdxCodeMap;

type
  TRdxLineFixes = class
  public
    // SCA082: an der Spalte aus der Meldung ('at column N') ein ';', danach
    // nur Leerraum und ein zweites ';' - beide Code. '; ;' -> ';' (das
    // zweite war eine leere Anweisung).
    class function DoubleSemicolon(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // SCA071: das Schluesselwort aus der Meldung ('"interface" ...
    // currently at column N') steht an Spalte N, davor nur Leerraum - er
    // wird geloescht. Nicht, wenn die Zeile in einem Kommentar oder
    // mehrzeiligen String beginnt, und nicht beim interface eines Typs
    // ('IFoo =' auf der Zeile davor - das meldet der Detektor auch).
    class function KeywordIndent(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // SCA088: genau ein begin auf ALine, die Datei beginnt mit unit, und
    // das end zu diesem begin (Bilanz begin/case/try/asm/record) steht vor
    // dem '.' - dann ist es der Unit-Rumpf, und 'initialization' ist
    // dasselbe. Schreibweise wie das begin ('BEGIN' -> 'INITIALIZATION').
    // Keine Hilfe bei einer Direktive auf der Zeile.
    class function LegacyInit(AMap: TRdxCodeMap; ALine: Integer;
      out AEdit: TRdxEdit; out AReason: string): Boolean; static;

    // SCA123: der Cast T aus der Meldung ('Type-cast T(...) before ...').
    class function CastTargetOf(const AMessage: string): string; static;

    // SCA123: genau ein 'T(X).Free' auf ALine -> 'X.Free' (NewText = X).
    // X ein Bezeichnerpfad (A, A.B, Self.F) ohne Kommentar; T kein
    // Interface ('IFoo(X).Free' riefe eine Interface-Methode Free). Nur
    // Free - Destroy bietet die Hilfe nicht an. Dass X schon den Typ T hat
    // (sonst kann T oder der Typ von X Free verdecken, oder der Cast ist
    // zum Uebersetzen noetig), prueft der Aufrufer.
    class function CastFree(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

const
  SPAN_082 = 'sca082';
  SPAN_071 = 'sca071';
  SPAN_088 = 'sca088';
  SPAN_123 = 'sca123';
  R_NO_COLUMN    = 'Spalte fehlt in der Meldung';
  R_SEMI_MOVED   = 'kein ";;" an der gemeldeten Stelle - Zeile verschoben? '
    + 'Datei neu pruefen';
  R_KW_MOVED     = 'das Schluesselwort steht nicht an der gemeldeten Stelle '
    + '- Zeile verschoben? Datei neu pruefen';
  KEY_CURRENTLY  = 'currently at column ';
  KEY_CAST       = 'Type-cast ';
  // Woerter, die als Operand eines Casts keine Variable sind.
  NOT_OPERANDS: array[0..1] of string = ('nil', 'inherited');
  // Davor steht 'interface' als Typ ('IFoo =' / 'packed'), nicht als
  // Abschnitt (Gegen-Review Zeilen-Hilfen, Minor 4).
  TYPE_KEYWORD_PREV: array[0..1] of string = ('=', 'packed');

{ ---- SCA082 ---- }

class function TRdxLineFixes.DoubleSemicolon(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  L         : string;
  Col, Next : Integer;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  Col := ColumnFromMessage(AMessage);
  if Col <= 0 then
  begin
    AReason := R_NO_COLUMN;
    Exit;
  end;
  L := AMap.Raw(ALine);
  Next := SkipBlanks(L, Col + 1);
  if not AMap.IsCode(ALine, Col) or (L[Col] <> ';')
     or not AMap.IsCode(ALine, Next) or (L[Next] <> ';') then
  begin
    AReason := R_SEMI_MOVED;
    Exit;
  end;
  AEdit.Span := TRefactorSpan.Make(SPAN_082, ALine, Col, ALine, Next + 1);
  AEdit.Expected := Copy(L, Col, Next + 1 - Col);
  AEdit.NewText := ';';
  Result := True;
end;

{ ---- SCA071 ---- }

// Wort und Spalte aus '... "interface" ... currently at column 5'.
// False, wenn eines fehlt.
function KeywordOf(const AMessage: string; out AWord: string;
  out ACol: Integer): Boolean;
var
  P, Q, i : Integer;
begin
  AWord := '';
  ACol := 0;
  P := Pos('"', AMessage);
  Q := Pos('"', AMessage, P + 1);
  if (P > 0) and (Q > P + 1) then
    AWord := Copy(AMessage, P + 1, Q - P - 1);
  P := Pos(KEY_CURRENTLY, AMessage);
  if P > 0 then
  begin
    i := P + Length(KEY_CURRENTLY);
    while (i <= Length(AMessage)) and CharInSet(AMessage[i], ['0'..'9']) do
    begin
      ACol := ACol * 10 + Ord(AMessage[i]) - Ord('0');
      Inc(i);
    end;
  end;
  Result := (AWord <> '') and (ACol > 1);
end;

class function TRdxLineFixes.KeywordIndent(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  L, Word : string;
  Col     : Integer;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  L := AMap.Raw(ALine);
  if not KeywordOf(AMessage, Word, Col) then
    AReason := 'Schluesselwort oder Spalte fehlt in der Meldung'
  else if AMap.StartsInside(ALine) then
    AReason := 'die Zeile beginnt in einem Kommentar oder String'
  else if (SkipBlanks(L, 1) <> Col) or not AMap.IsCode(ALine, Col)
     or not SameText(TokenAt(AMap, ALine, Col).Low, Word) then
    AReason := R_KW_MOVED
  else if InList(PrevToken(AMap, ALine, Col).Low, TYPE_KEYWORD_PREV) then
    AReason := Format('%s gehoert zu einer Typ-Deklaration - kein '
      + 'Unit-Abschnitt', [Word]);
  if AReason <> '' then Exit;
  AEdit.Span := TRefactorSpan.Make(SPAN_071, ALine, 1, ALine, Col);
  AEdit.Expected := Copy(L, 1, Col - 1);
  AEdit.NewText := '';
  Result := True;
end;

{ ---- SCA088 ---- }

// AWord in der Schreibweise von AModel: ganz gross, gross am Anfang oder
// klein.
function CaseLike(const AModel, AWord: string): string;
begin
  Result := LowerCase(AWord);
  if AModel = '' then Exit;
  if (AModel = UpperCase(AModel)) and (Length(AModel) > 1) then
    Result := UpperCase(AWord)
  else if AModel[1] = UpperCase(AModel[1]) then
    Result := UpperCase(Copy(AWord, 1, 1)) + Copy(Result, 2, MaxInt);
end;

// Das eine begin (Schluesselwort, Code) auf ALine. '' oder der Grund.
function BeginOn(AMap: TRdxCodeMap; ALine: Integer;
  out ABegin: TRdxToken): string;
var
  T, Prev : TRdxToken;
  n       : Integer;
begin
  Result := '';
  ABegin := Default(TRdxToken);
  n := 0;
  Prev := PrevToken(AMap, ALine, 1);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if (T.Low = 'begin') and IsKeywordAfter(T, Prev) then
    begin
      Inc(n);
      ABegin := T;
    end;
    Prev := T;
    T := After(AMap, T);
  end;
  if n = 0 then
    Result := 'kein begin auf der gemeldeten Zeile - Zeile verschoben? '
      + 'Datei neu pruefen'
  else if n > 1 then
    Result := Format('Zeile %d traegt %d begin - mehrdeutig', [ALine, n]);
end;

// Das end zu ABegin (Bilanz wie MatchingEnd) - steht es vor dem '.'?
// '' oder der Grund.
function EndsUnit(AMap: TRdxCodeMap; const ABegin: TRdxToken): string;
var
  T, Prev : TRdxToken;
  Depth   : Integer;
begin
  Depth := 1;
  Prev := ABegin;
  T := After(AMap, ABegin);
  while (T.Low <> '') and (Depth > 0) do
  begin
    if IsKeywordAfter(T, Prev) and IsEndOpener(T.Low) then
      Inc(Depth)
    else if IsKeywordAfter(T, Prev) and (T.Low = 'end') then
      Dec(Depth);
    Prev := T;
    if Depth > 0 then
      T := After(AMap, T);
  end;
  Result := '';
  if Depth > 0 then
    Result := 'kein end zum begin gefunden'
  else if After(AMap, T).Low <> '.' then
    Result := 'das end zu diesem begin steht nicht vor dem Punkt - kein '
      + 'Unit-Rumpf';
end;

function DirectiveOnLine(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  Co : Integer;
begin
  Result := False;
  for Co := 1 to Length(AMap.Raw(ALine)) do
    if DirectiveAt(AMap, ALine, Co) then
      Exit(True);
end;

class function TRdxLineFixes.LegacyInit(AMap: TRdxCodeMap; ALine: Integer;
  out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  B : TRdxToken;
  L : string;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  if NextToken(AMap, 1, 1).Low <> 'unit' then
    AReason := 'keine Unit - in program/library ist begin der Rumpf'
  else
    AReason := BeginOn(AMap, ALine, B);
  if (AReason = '') and DirectiveOnLine(AMap, ALine) then
    AReason := 'Compiler-Direktive auf der Zeile des begin';
  if AReason = '' then
    AReason := EndsUnit(AMap, B);
  if AReason <> '' then Exit;
  L := AMap.Raw(ALine);
  AEdit.Span := TRefactorSpan.Make(SPAN_088, ALine, B.Col, ALine, B.EndCol);
  AEdit.Expected := Copy(L, B.Col, B.Len);
  AEdit.NewText := CaseLike(AEdit.Expected, 'initialization');
  Result := True;
end;

{ ---- SCA123 ---- }

class function TRdxLineFixes.CastTargetOf(const AMessage: string): string;
var
  P, Q : Integer;
begin
  Result := '';
  P := Pos(KEY_CAST, AMessage);
  if P = 0 then Exit;
  Inc(P, Length(KEY_CAST));
  Q := Pos('(', AMessage, P);
  if Q > P then
    Result := Copy(AMessage, P, Q - P);
end;

// Ein Cast-Fund auf der Zeile: Typname, '(' und ')' (gleiche Zeile).
type
  TRdxCastSite = record
    Target : TRdxToken;
    Open   : TRdxToken;
    Close  : TRdxToken;
  end;

  // Was an einem Token steht (CastAt).
  TRdxCastKind = (ckNone, ckFree, ckDestroy, ckOpenLine);

// Ab dem '(' AOpen die schliessende ')' auf derselben Zeile. False ohne.
function CloseParen(AMap: TRdxCodeMap; const AOpen: TRdxToken;
  out AClose: TRdxToken): Boolean;
var
  T     : TRdxToken;
  Depth : Integer;
begin
  Result := False;
  AClose := Default(TRdxToken);
  Depth := 0;
  T := AOpen;
  while (T.Low <> '') and (T.Line = AOpen.Line) do
  begin
    if T.Low = '(' then
      Inc(Depth)
    else if T.Low = ')' then
      Dec(Depth);
    if Depth = 0 then
    begin
      AClose := T;
      Exit(True);
    end;
    T := After(AMap, T);
  end;
end;

// Steht an T der Cast 'ATarget(...)'? ckFree/ckDestroy mit '.Free' bzw.
// '.Destroy' dahinter (dann ASite), ckOpenLine, wenn die ')' nicht mehr
// auf der Zeile steht.
function CastAt(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  const ATarget: string; out ASite: TRdxCastSite): TRdxCastKind;
var
  Dot, M : TRdxToken;
begin
  Result := ckNone;
  ASite := Default(TRdxCastSite);
  if not SameText(T.Low, ATarget) or InList(APrev.Low, IDENT_PREFIXES) then
    Exit;
  ASite.Target := T;
  ASite.Open := After(AMap, T);
  if ASite.Open.Low <> '(' then
    Exit;
  if not CloseParen(AMap, ASite.Open, ASite.Close) then
    Exit(ckOpenLine);
  Dot := After(AMap, ASite.Close);
  M := After(AMap, Dot);
  if Dot.Low <> '.' then
    Exit;
  if M.Low = 'free' then
    Result := ckFree
  else if M.Low = 'destroy' then
    Result := ckDestroy;
end;

// Der eine Cast vor '.Free' auf ALine (Casts vor Destroy zaehlen nicht
// mit). '' oder der Grund.
function CastOn(AMap: TRdxCodeMap; ALine: Integer; const ATarget: string;
  out ASite: TRdxCastSite): string;
var
  T, Prev : TRdxToken;
  S       : TRdxCastSite;
  Kind    : TRdxCastKind;
  Seen    : set of TRdxCastKind;
  n       : Integer;
begin
  Result := '';
  ASite := Default(TRdxCastSite);
  n := 0;
  Seen := [];
  Prev := PrevToken(AMap, ALine, 1);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    Kind := CastAt(AMap, T, Prev, ATarget, S);
    Include(Seen, Kind);
    if Kind = ckFree then
    begin
      Inc(n);
      ASite := S;
    end;
    Prev := T;
    T := After(AMap, T);
  end;
  if n > 1 then
    Result := Format('Zeile %d traegt %d Casts %s(...).Free - mehrdeutig',
      [ALine, n, ATarget])
  else if n = 1 then
    Exit
  else if ckDestroy in Seen then
    Result := 'nur fuer Free - Destroy bleibt, wie es ist'
  else if ckOpenLine in Seen then
    Result := Format('der Cast %s(...) geht ueber mehrere Zeilen', [ATarget])
  else
    Result := Format('kein %s(...).Free auf der gemeldeten Zeile - Zeile '
      + 'verschoben? Datei neu pruefen', [ATarget]);
end;

// Ist der Operand zwischen den Klammern ein Bezeichnerpfad (A, A.B,
// Self.F) - und steht darin kein Kommentar oder String? '' oder der Grund.
function OperandReason(AMap: TRdxCodeMap; const ASite: TRdxCastSite): string;
var
  T          : TRdxToken;
  WantWord   : Boolean;
begin
  Result := '';
  if AMap.HasNonCode(ASite.Open.Line, ASite.Open.Col, ASite.Close.Col) then
    Exit('Kommentar oder String im Cast');
  WantWord := True;
  T := After(AMap, ASite.Open);
  while (T.Col < ASite.Close.Col) and (T.Line = ASite.Open.Line) do
  begin
    if InList(T.Low, NOT_OPERANDS) then
      Exit(Format('"%s" als Operand - ohne den Cast nicht dasselbe', [T.Low]));
    if WantWord <> T.IsWord then
      Exit('der Operand ist kein einfacher Bezeichner(pfad) - etwa ein '
        + 'Aufruf oder ein Index; der Cast koennte zum Uebersetzen noetig sein');
    if not WantWord and (T.Low <> '.') then
      Exit('der Operand ist kein einfacher Bezeichner(pfad)');
    WantWord := not WantWord;
    T := After(AMap, T);
  end;
  if WantWord then
    Result := 'der Operand ist kein einfacher Bezeichner(pfad)';
end;

// Ein Interface-Cast ('IFoo(X)')? I und ein Grossbuchstabe.
function LooksLikeInterface(const AType: string): Boolean;
begin
  Result := (Length(AType) >= 2) and (AType[1] = 'I')
    and CharInSet(AType[2], ['A'..'Z']);
end;

class function TRdxLineFixes.CastFree(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Target : string;
  Site   : TRdxCastSite;
  L      : string;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  Target := CastTargetOf(AMessage);
  if Target = '' then
    AReason := 'Typname fehlt in der Meldung'
  else if LooksLikeInterface(Target) then
    AReason := Format('%s ist ein Interface - %s(X).Free riefe dessen '
      + 'Methode Free, X.Free die von TObject', [Target, Target])
  else
    AReason := CastOn(AMap, ALine, Target, Site);
  if AReason = '' then
    AReason := OperandReason(AMap, Site);
  if AReason <> '' then Exit;
  L := AMap.Raw(ALine);
  AEdit.Span := TRefactorSpan.Make(SPAN_123, ALine, Site.Target.Col, ALine,
    Site.Close.EndCol);
  AEdit.Expected := Copy(L, Site.Target.Col, Site.Close.EndCol - Site.Target.Col);
  AEdit.NewText := Trim(Copy(L, Site.Open.EndCol,
    Site.Close.Col - Site.Open.EndCol));
  Result := True;
end;

end.

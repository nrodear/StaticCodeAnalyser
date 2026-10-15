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
//
// TEXTE (Entscheid E29, Charge G1): jeder Grund ist eine englische msgid,
// uebersetzt mit uRdxText._ in die Sprache der SCA-Oberflaeche; die
// deutsche Fassung (der bisherige Wortlaut) steht in i18n/de.po. Gemeinsame
// Texte kommen aus uRdxText (MsgNoColumn, MsgMovedSuffix ...), Code-Token
// ('begin', 'TFoo(...).Free') stehen als %s im Satz.

interface

uses
  uRdxBufferMath, uRdxCodeMap;

type
  // Die Planer an einer Zeile (SCA082, SCA071, SCA088, SCA123): reine
  // Textlogik auf der Code-Sicht, alle vier bedeutungsgleich. Ob X den
  // Cast-Typ schon hat (SCA123), prueft der Aufrufer mit dem
  // Quellstellen-Dienst.
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

uses
  System.SysUtils,
  uRefactorInfo,   // TRefactorSpan.Make
  uRdxText;        // _(), Msg...: in die reDelphix-Sprache, nie uLocalization (E29)

const
  SPAN_082 = 'sca082';
  SPAN_071 = 'sca071';
  SPAN_088 = 'sca088';
  SPAN_123 = 'sca123';
  // Gruende ohne das gemeinsame Ende: MsgMovedSuffix haengt ' - line
  // moved? Analyse the file again' an (deutsch '... - Zeile verschoben?
  // Datei neu pruefen', uRdxText).
  R_SEMI_MOVED   = 'no ";;" at the reported place';
  R_KW_MOVED     = 'the keyword is not at the reported place';
  // Zweimal in OperandReason: der Operand ist kein Bezeichnerpfad.
  R_NO_IDENT_PATH = 'the operand is not a simple identifier (path)';
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
    AReason := MsgNoColumn;
    Exit;
  end;
  L := AMap.Raw(ALine);
  Next := SkipBlanks(L, Col + 1);
  if not AMap.IsCode(ALine, Col) or (L[Col] <> ';')
     or not AMap.IsCode(ALine, Next) or (L[Next] <> ';') then
  begin
    AReason := MsgMovedSuffix(_(R_SEMI_MOVED));
    Exit;
  end;
  AEdit.Span := TRefactorSpan.Make(SPAN_082, ALine, Col, ALine, Next + 1);
  AEdit.Expected := Copy(L, Col, Next + 1 - Col);
  AEdit.NewText := ';';
  Result := True;
end;

{ ---- SCA071 ---- }

// Wort und Spalte aus '... "interface" ... currently at column 5' - das
// Wort zwischen den ersten beiden '"' (QuotedText, uRdxCodeMap; bis
// Charge B2S-a hier ausgeschrieben). False, wenn eines fehlt.
function KeywordOf(const AMessage: string; out AWord: string;
  out ACol: Integer): Boolean;
var
  P, i : Integer;
begin
  ACol := 0;
  AWord := QuotedText(AMessage, '"');
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
  L       : string;
  Keyword : string;   // nicht 'Word': verdeckte System.Word (Review R3-06)
  Col     : Integer;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  L := AMap.Raw(ALine);
  // Eigener Satz, nicht MsgNoColumn: es fehlt das Wort ODER die Spalte -
  // ein anderer Wortlaut als 'Spalte fehlt in der Meldung'.
  if not KeywordOf(AMessage, Keyword, Col) then
    AReason := _('the message has no keyword or column')
  else if AMap.StartsInside(ALine) then
    AReason := MsgLineStartsInCommentOrString
  else if (SkipBlanks(L, 1) <> Col) or not AMap.IsCode(ALine, Col)
     or not SameText(TokenAt(AMap, ALine, Col).Low, Keyword) then
    AReason := MsgMovedSuffix(_(R_KW_MOVED))
  else if InList(PrevToken(AMap, ALine, Col).Low, TYPE_KEYWORD_PREV) then
    AReason := _('%s belongs to a type declaration - not a unit section',
      [Keyword]);
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

// Ein begin als Schluesselwort (OneTokenOnLine, BeginOn).
function IsBeginKeyword(AMap: TRdxCodeMap; const T: TRdxToken;
  const AArg: string): Boolean;
begin
  Result := (T.Low = 'begin') and IsKeywordAfter(T, Before(AMap, T));
end;

// Das eine begin (Schluesselwort, Code) auf ALine. '' oder der Grund.
// What ist eine schon uebersetzte Nominalphrase - OneTokenReason setzt sie
// in seinen Satz; das Muster '%d begin' ist Code und bleibt.
function BeginOn(AMap: TRdxCodeMap; ALine: Integer;
  out ABegin: TRdxToken): string;
var
  S : TRdxLineSearch;
begin
  S := Default(TRdxLineSearch);
  S.Test    := IsBeginKeyword;
  S.What    := _('no begin');
  S.ManyFmt := '%d begin';
  Result := OneTokenOnLine(AMap, ALine, S, ABegin);
end;

// Das end zu ABegin (end-Bilanz BlockEnd) - steht es vor dem '.'?
// '' oder der Grund.
function EndsUnit(AMap: TRdxCodeMap; const ABegin: TRdxToken): string;
var
  EndTok, Last : TRdxToken;
begin
  Result := BlockEnd(AMap, ABegin, nil, EndTok, Last);
  if EndTok.Low = '' then
    Result := _('no end found for the begin')
  else if After(AMap, EndTok).Low <> '.' then
    Result := _('the end of this begin is not before the dot - not a unit '
      + 'body');
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
    AReason := _('not a unit - in program/library, begin is the body')
  else
    AReason := BeginOn(AMap, ALine, B);
  if (AReason = '') and DirectiveInLines(AMap, ALine, ALine) then
    AReason := _('compiler directive on the line of the begin');
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

// Ab dem '(' AOpen die schliessende ')' auf derselben Zeile (MatchClose
// ohne weitere Zeilen). False ohne.
function CloseParen(AMap: TRdxCodeMap; const AOpen: TRdxToken;
  out AClose: TRdxToken): Boolean;
begin
  AClose := MatchClose(AMap, AOpen, 0);
  Result := AClose.Low <> '';
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
  // Die Gruende "keiner"/"mehrere" wie bei jeder Token-Suche (OneTokenReason):
  // das Muster der Mehrdeutigkeit uebersetzt, ATarget aus der Meldung als
  // sein %s (AArg) - nie ins Muster gehaengt; die Nominalphrase fuer
  // "keiner" uebersetzt mit ATarget als Argument.
  if n > 1 then
    Result := OneTokenReason(ALine, n, '', _('%d casts %s(...).Free'), ATarget)
  else if n = 1 then
    Exit
  else if ckDestroy in Seen then
    Result := _('only for Free - Destroy stays as it is')
  else if ckOpenLine in Seen then
    Result := _('the cast %s(...) spans several lines', [ATarget])
  else
    Result := OneTokenReason(ALine, 0, _('no %s(...).Free', [ATarget]), '');
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
    Exit(_('comment or string in the cast'));
  WantWord := True;
  T := After(AMap, ASite.Open);
  while (T.Col < ASite.Close.Col) and (T.Line = ASite.Open.Line) do
  begin
    if InList(T.Low, NOT_OPERANDS) then
      Exit(_('"%s" as operand - not the same without the cast', [T.Low]));
    if WantWord <> T.IsWord then
      Exit(_('the operand is not a simple identifier (path) - a call or an '
        + 'index, for example; the cast could be needed to compile'));
    if not WantWord and (T.Low <> '.') then
      Exit(_(R_NO_IDENT_PATH));
    WantWord := not WantWord;
    T := After(AMap, T);
  end;
  if WantWord then
    Result := _(R_NO_IDENT_PATH);
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
    AReason := _('the message has no type name')
  else if LooksLikeInterface(Target) then
    AReason := _('%s is an interface - %s(X).Free would call its method '
      + 'Free, X.Free the one of TObject', [Target, Target])
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

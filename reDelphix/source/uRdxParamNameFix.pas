unit uRdxParamNameFix;

// reDelphix - Editorhilfe fuer SCA199 ParamNameMismatch, OHNE ToolsAPI und
// ohne Parser (Konzept_Editorhilfen_Regelliste_2026-10-11: "bedingt -
// richtigen Parameternamen einsetzen, wenn eindeutig"):
//   Q.ParamByName('Nmae') -> Q.ParamByName('Name')
// wenn GENAU EIN Platzhalter des SQL einen Tippfehler vom gemeldeten Namen
// entfernt ist. Der Aufruf bindet danach einen anderen Parameter - das ist
// der Fix (bisher warf er "parameter not found"); die Tabellenzeile
// kennzeichnet ihn (E2).
//
// DER FUND (uParamNameMismatch/uParamNameScan): zwei Richtungen unter
// derselben Art. Nur (a) bekommt die Hilfe - 'Q.ParamByName(''x''): the SQL
// this routine assigns to Q has no :x (it has :a, :b) - raises "parameter
// not found" at run time', gemeldet auf der Zeile des Literals. Die Meldung
// nennt die Platzhalter des SQL (ohne die in SQL-Kommentaren), sortiert und
// bei sechs gekappt (', ...'). Diese Liste ist die Grundlage der Wahl - der
// Planer liest das SQL nicht selbst. (b) (Platzhalter ohne Zuweisung) haette
// einen Namen, aber keinen Wert: keine Hilfe.
//
// "EIN TIPPFEHLER" (TypoDistance = 1, Gross/klein egal - der Detektor
// vergleicht ohne Gross/klein, eine reine Schreibweise meldet er nie): ein
// Zeichen mehr, weniger oder anders, oder zwei Nachbarn vertauscht
// ('Nmae' -> 'Name', 'custid' -> 'cust_id'). Beide Namen mindestens
// MIN_NAME_LEN Zeichen: bei 'a'/'b' oder 'id'/'ix' ist ein Zeichen kein
// Tippfehler mehr, sondern ein anderer Name.
//
// GESPERRT (lieber keine Hilfe als eine falsche):
//   - Fund (b), eine Meldung anderer Form, kein Platzhalter im SQL oder eine
//     gekappte Liste (der richtige Name koennte fehlen),
//   - kein Platzhalter oder mehr als einer einen Tippfehler entfernt
//     (das Katalogbeispiel 'custid' -> 'customer_id' ist KEIN Tippfehler:
//     keine Hilfe),
//   - auf der gemeldeten Zeile nicht genau ein '<Query>.ParamByName(' mit
//     dem Literal '<Name>' als ganzem Argument (Zeile verschoben, Name aus
//     Ausdruck oder #-Zeichen, Kommentar, String, andere Query),
//   - keine Routine mit begin..end-Rumpf um den Aufruf, oder ihre Grenzen
//     sind nicht sicher lesbar,
//   - die Routine setzt den gewaehlten Namen schon (ParamByName,
//     FindParam, ParamValues, SetVariable ... mit diesem Literal): ein
//     zweiter Zugriff ueberschriebe einen Wert - dann war vermutlich etwas
//     anderes gemeint. FieldByName('Name') sperrt nicht.
//
// OHNE ToolsAPI und ohne Delphi-only-Unit (FPC-Pruefstand): den Adapter
// PlanParamName (Form TRdxFixPlanner, setzt Name fuer den Menuetext) traegt
// die Tabelle uRdxFixTable.

interface

uses
  uRdxBufferMath,        // TRdxEdit
  uRdxCodeMap;           // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_PN_NOT_UNKNOWN = 'only for ParamByName with a name the SQL does not '
    + 'have - a placeholder that is never set needs a value';
  R_PN_MESSAGE = 'the message does not have the expected form';
  R_PN_NO_PLACEHOLDERS = 'the SQL has no named placeholders - nothing to '
    + 'choose from';
  R_PN_TRUNCATED = 'the message lists only part of the placeholders - the '
    + 'right one could be missing';
  R_PN_SHORT = 'the name "%s" is too short to tell a typo from another name';
  R_PN_NO_CANDIDATE = 'no placeholder of the SQL is one typo away from "%s" '
    + '(%s)';
  R_PN_MANY = '%d placeholders are one typo away from "%s" - ambiguous';
  R_PN_MOVED = 'no %s.ParamByName("%s") with the name as a plain literal on '
    + 'the reported line';
  R_PN_TWICE = 'the line calls ParamByName("%s") more than once';
  R_PN_NO_ROUTINE = 'no routine with a begin..end body around the call';
  R_PN_BOUNDS = 'the bounds of the routine around the call are not safe to '
    + 'read';
  R_PN_USED = 'the routine already sets "%s" - a second assignment would '
    + 'overwrite its value; by hand';

type
  TRdxParamNameFix = class
  public
    // SCA199 (a): das Literal in 'Q.ParamByName(''x'')' auf ALine wird zum
    // einen Platzhalter der Meldung, der einen Tippfehler entfernt ist.
    // AEdit ersetzt nur den Text zwischen den Quotes.
    class function UsePlaceholder(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

// Abstand zweier Namen in Tippfehlern (Einfuegen, Loeschen, Ersetzen,
// Vertauschen zweier Nachbarn; "optimal string alignment"), Gross/klein
// egal (nur ASCII - ein Zeichen ueber #127 vergleicht gleich geschrieben).
// Oeffentlich fuer die Tests.
function ParamTypoDistance(const A, B: string): Integer;

implementation

uses
  System.SysUtils,
  uRefactorInfo,    // TRefactorSpan.Make
  uRdxText,         // _(): in die reDelphix-Sprache, nie uLocalization
  uRdxBlocks;       // TRdxBlocks.BeginBodyAround, TRdxRoutine

const
  SPAN_199 = 'sca199';
  // Die Meldung (a) des Detektors (TParamNameScan.MessageOf), Stueck fuer
  // Stueck - englisch und unuebersetzt wie jede Fundmeldung.
  MSG_CALL = '.ParamByName(''';
  MSG_MID  = '''): the SQL this routine assigns to ';
  MSG_HEAD = '%s.ParamByName(''%s''): the SQL this routine assigns to %s '
    + 'has no :%s (';
  MSG_TAIL = ') - raises "parameter not found" at run time';
  MSG_HAVE = 'it has ';
  MSG_NONE = 'it has no named placeholders';
  MSG_MORE = ', ...';
  LIST_SEP = ', ';
  // Kuerzere Namen: ein Zeichen ist dort kein Tippfehler mehr (s. Kopf).
  MIN_NAME_LEN = 3;
  KW_PARAMBYNAME = 'parambyname';
  SELF_PREFIX = 'self.';
  // Zwischen Query und ParamByName ('Q.Params.ParamByName', ADO
  // 'Q.Parameters.ParamByName').
  PARAM_LISTS: array[0..1] of string = ('params', 'parameters');
  // Aufrufe, deren Literal-Argument einen Parameter setzt oder anlegt - wie
  // der Detektor sie zaehlt (uParamNameScan: Zugriffe und PARAM_CREATORS).
  PARAM_CALLS: array[0..10] of string = ('parambyname', 'findparam',
    'paramvalues', 'setvariable', 'declarevariable', 'setcomplexvariable',
    'setlongvariable', 'createparam', 'createparameter', 'add',
    'addparameter');
  // Trennt die Namen in ParamValues['a;b'].
  VALUES_SEP = ';';
  // Hier endet die Suche nach der Routine um den Aufruf: UNIT_BOUNDS
  // (uRdxCodeMap, seit der Folgewelle B1 zentral).
  // So weit sucht IsParamArg rueckwaerts nach der oeffnenden Klammer.
  MAX_BACK_TOKENS = 64;

type
  // Was die Meldung (a) sagt.
  TParamFinding = record
    Query : string;           // wie gemeldet, ohne 'Self.'
    Param : string;           // der Name, den das SQL nicht kennt
    List  : string;           // ':a, :b' wie gemeldet
    Names : TArray<string>;   // die Platzhalter ohne ':'
  end;

function Min3(A, B, C: Integer): Integer;
begin
  Result := A;
  if B < Result then
    Result := B;
  if C < Result then
    Result := C;
end;

function ParamTypoDistance(const A, B: string): Integer;
var
  D       : array of array of Integer;
  X, Y    : string;
  i, j, k : Integer;
begin
  X := LowerCase(A);
  Y := LowerCase(B);
  SetLength(D, Length(X) + 1, Length(Y) + 1);
  for i := 0 to Length(X) do
    D[i][0] := i;
  for j := 0 to Length(Y) do
    D[0][j] := j;
  for i := 1 to Length(X) do
    for j := 1 to Length(Y) do
    begin
      if X[i] = Y[j] then
        k := 0
      else
        k := 1;
      D[i][j] := Min3(D[i - 1][j] + 1, D[i][j - 1] + 1, D[i - 1][j - 1] + k);
      if (i > 1) and (j > 1) and (X[i] = Y[j - 1]) and (X[i - 1] = Y[j])
         and (D[i - 2][j - 2] + 1 < D[i][j]) then
        D[i][j] := D[i - 2][j - 2] + 1;
    end;
  Result := D[Length(X)][Length(Y)];
end;

// Endet S mit ATail?
function EndsWith(const S, ATail: string): Boolean;
begin
  Result := (Length(S) >= Length(ATail))
    and (Copy(S, Length(S) - Length(ATail) + 1, MaxInt) = ATail);
end;

// ':a, :b' -> ['a', 'b']. '' oder der Grund.
function SplitNames(const AList: string; out ANames: TArray<string>): string;
var
  Rest, Item : string;
  p, n       : Integer;
begin
  Result := '';
  ANames := nil;
  Rest := AList;
  n := 0;
  while Rest <> '' do
  begin
    p := Pos(LIST_SEP, Rest);
    if p = 0 then
    begin
      Item := Rest;
      Rest := '';
    end
    else
    begin
      Item := Copy(Rest, 1, p - 1);
      Rest := Copy(Rest, p + Length(LIST_SEP), MaxInt);
    end;
    if (Length(Item) < 2) or (Item[1] <> ':') then
      Exit(_(R_PN_MESSAGE));
    SetLength(ANames, n + 1);
    ANames[n] := Copy(Item, 2, MaxInt);
    Inc(n);
  end;
  if n = 0 then
    Result := _(R_PN_MESSAGE);
end;

// Die Meldung (a) in ihre Teile. '' oder der Grund.
function ParseFinding(const AMessage: string; out AF: TParamFinding): string;
var
  p, q       : Integer;
  Rest, Head : string;
  Have       : string;
begin
  AF := Default(TParamFinding);
  p := Pos(MSG_CALL, AMessage);
  if p <= 1 then
    Exit(_(R_PN_NOT_UNKNOWN));
  AF.Query := Copy(AMessage, 1, p - 1);
  Rest := Copy(AMessage, p + Length(MSG_CALL), MaxInt);
  q := Pos(MSG_MID, Rest);
  if q <= 1 then
    Exit(_(R_PN_NOT_UNKNOWN));
  AF.Param := Copy(Rest, 1, q - 1);
  Head := Format(MSG_HEAD, [AF.Query, AF.Param, AF.Query, AF.Param]);
  if (Copy(AMessage, 1, Length(Head)) <> Head)
     or (Length(AMessage) < Length(Head) + Length(MSG_TAIL))
     or not EndsWith(AMessage, MSG_TAIL) then
    Exit(_(R_PN_MESSAGE));
  Have := Copy(AMessage, Length(Head) + 1,
    Length(AMessage) - Length(Head) - Length(MSG_TAIL));
  if Have = MSG_NONE then
    Exit(_(R_PN_NO_PLACEHOLDERS));
  if Copy(Have, 1, Length(MSG_HAVE)) <> MSG_HAVE then
    Exit(_(R_PN_MESSAGE));
  AF.List := Copy(Have, Length(MSG_HAVE) + 1, MaxInt);
  if EndsWith(AF.List, MSG_MORE) then
    Exit(_(R_PN_TRUNCATED));
  Result := SplitNames(AF.List, AF.Names);
end;

// Der eine Platzhalter, der einen Tippfehler von AF.Param entfernt ist.
// '' oder der Grund.
function ChooseName(const AF: TParamFinding; out AName: string): string;
var
  N    : string;
  Hits : Integer;
begin
  Result := '';
  AName := '';
  if Length(AF.Param) < MIN_NAME_LEN then
    Exit(_(R_PN_SHORT, [AF.Param]));
  Hits := 0;
  for N in AF.Names do
    if (Length(N) >= MIN_NAME_LEN) and (ParamTypoDistance(AF.Param, N) = 1) then
    begin
      Inc(Hits);
      AName := N;
    end;
  if Hits = 0 then
    Result := _(R_PN_NO_CANDIDATE, [AF.Param, AF.List])
  else if Hits > 1 then
    Result := _(R_PN_MANY, [Hits, AF.Param]);
  if Result <> '' then
    AName := '';
end;

// Steht an ALine hinter AOpen ('(') ein einfaches Literal als ganzes
// Argument - Quote bis Quote, dahinter ')'? ACol/AEnd: die beiden Quotes.
function LiteralAfter(AMap: TRdxCodeMap; const AOpen: TRdxToken;
  out ACol, AEnd: Integer): Boolean;
var
  L : string;
  n : Integer;
begin
  Result := False;
  L := AMap.Raw(AOpen.Line);
  ACol := SkipBlanks(L, AOpen.EndCol);
  AEnd := ACol;
  if (ACol > Length(L)) or (L[ACol] <> '''')
     or (AMap.ClassAt(AOpen.Line, ACol) <> 's') then
    Exit;
  while (AEnd < Length(L)) and (AMap.ClassAt(AOpen.Line, AEnd + 1) = 's') do
    Inc(AEnd);
  // Ohne schliessendes Quote auf der Zeile: ein mehrzeiliger String.
  if (AEnd = ACol) or (L[AEnd] <> '''') then
    Exit;
  n := SkipBlanks(L, AEnd + 1);
  Result := (n <= Length(L)) and (L[n] = ')') and AMap.IsCode(AOpen.Line, n);
end;

// Ist die Kette vor ACall ('Q.' bzw. 'Self.Q.Params.') die Query AQuery?
function QueryBefore(AMap: TRdxCodeMap; const ACall: TRdxToken;
  const AQuery: string): Boolean;
var
  D, X, P, W : TRdxToken;
  Chain      : string;
begin
  Result := False;
  D := Before(AMap, ACall);
  if D.Low <> '.' then
    Exit;
  X := Before(AMap, D);
  if InList(X.Low, PARAM_LISTS) then
  begin
    D := Before(AMap, X);
    if D.Low <> '.' then
      Exit;
    X := Before(AMap, D);
  end;
  if not X.IsWord then
    Exit;
  Chain := TokText(AMap, X);
  P := Before(AMap, X);
  while P.Low = '.' do
  begin
    W := Before(AMap, P);
    // ')' oder ']' davor: Cast oder Index - dort meldet der Detektor nie.
    if not W.IsWord then
      Exit;
    Chain := TokText(AMap, W) + '.' + Chain;
    P := Before(AMap, W);
  end;
  if SameText(Copy(Chain, 1, Length(SELF_PREFIX)), SELF_PREFIX) then
    Delete(Chain, 1, Length(SELF_PREFIX));
  Result := SameText(Chain, AQuery);
end;

// Genau ein '<Query>.ParamByName(''<Param>'')' auf ALine: '' mit dem
// Token ParamByName und den Spalten der beiden Quotes, sonst der Grund.
function FindCall(AMap: TRdxCodeMap; ALine: Integer; const AF: TParamFinding;
  out ACall: TRdxToken; out ACol, AEnd: Integer): string;
var
  T, Open : TRdxToken;
  c, e    : Integer;
  Hits    : Integer;
begin
  ACall := Default(TRdxToken);
  ACol := 0;
  AEnd := 0;
  Hits := 0;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if T.Low = KW_PARAMBYNAME then
    begin
      Open := After(AMap, T);
      if (Open.Low = '(') and (Open.Line = ALine)
         and LiteralAfter(AMap, Open, c, e)
         and (Copy(AMap.Raw(ALine), c, e - c + 1) = '''' + AF.Param + '''')
         and QueryBefore(AMap, T, AF.Query) then
      begin
        Inc(Hits);
        ACall := T;
        ACol := c;
        AEnd := e;
      end;
    end;
    T := After(AMap, T);
  end;
  if Hits = 0 then
    Result := MsgMovedSuffix(_(R_PN_MOVED, [AF.Query, AF.Param]))
  else if Hits > 1 then
    Result := _(R_PN_TWICE, [AF.Param])
  else
    Result := '';
end;

// Die innerste Routine mit begin..end-Rumpf um AAt mit den Gruenden
// dieser Unit; '' oder der Grund. Die Suche ist der Baustein
// uRdxBlocks.BeginBodyAround (bis zur Hygiene-Welle H1 hier als Kopie
// ausgeschrieben): ein Kopf mit unsicheren Grenzen beendet sie.
function EnclosingRoutine(AMap: TRdxCodeMap; const AAt: TRdxToken;
  out ARoutine: TRdxRoutine): string;
begin
  case BeginBodyAround(AMap, AAt, ARoutine) of
    rbfUnsure: Result := _(R_PN_BOUNDS);
    rbfNone:   Result := _(R_PN_NO_ROUTINE);
  else
    Result := '';
  end;
end;

// Steht das Literal an (ALine, ACol) als Argument eines Aufrufs aus
// PARAM_CALLS ('ParamByName(''x'')', 'CreateParam(ft, ''x'', pt)',
// 'ParamValues[''a;x'']')? Rueckwaerts bis zur offenen Klammer.
function IsParamArg(AMap: TRdxCodeMap; ALine, ACol: Integer): Boolean;
var
  T     : TRdxToken;
  Depth : Integer;
  k     : Integer;
begin
  Result := False;
  T := PrevToken(AMap, ALine, ACol);
  Depth := 0;
  for k := 1 to MAX_BACK_TOKENS do
  begin
    if (T.Low = '') or (T.Low = ';') then
      Exit;
    if (T.Low = ')') or (T.Low = ']') then
      Inc(Depth)
    else if (T.Low = '(') or (T.Low = '[') then
    begin
      if Depth = 0 then
        Exit(InList(Before(AMap, T).Low, PARAM_CALLS));
      Dec(Depth);
    end;
    T := Before(AMap, T);
  end;
end;

// Nennt der Literal-Text AValue (dekodiert) den Namen AName - ganz oder als
// Teil von 'a;b' (ParamValues)?
function NamesParam(const AValue, AName: string): Boolean;
var
  Rest : string;
  p    : Integer;
begin
  Rest := AValue;
  repeat
    p := Pos(VALUES_SEP, Rest);
    if p = 0 then
      p := Length(Rest) + 1;
    if SameText(Trim(Copy(Rest, 1, p - 1)), AName) then
      Exit(True);
    Rest := Copy(Rest, p + 1, MaxInt);
  until Rest = '';
  Result := False;
end;

// Setzt die Routine den Namen AName schon - ein Literal mit diesem Namen als
// Argument eines Parameter-Zugriffs (IsParamArg)?
function NameUsed(AMap: TRdxCodeMap; const ARoutine: TRdxRoutine;
  const AName: string): Boolean;
var
  Li, j, e : Integer;
  L, V     : string;
begin
  Result := False;
  for Li := ARoutine.Head.Line to ARoutine.EndTok.Line do
  begin
    L := AMap.Raw(Li);
    j := 1;
    while j <= Length(L) do
    begin
      if (L[j] <> '''') or (AMap.ClassAt(Li, j) <> 's')
         or ((j > 1) and (AMap.ClassAt(Li, j - 1) = 's')) then
      begin
        Inc(j);
        Continue;
      end;
      e := j;
      while (e < Length(L)) and (AMap.ClassAt(Li, e + 1) = 's') do
        Inc(e);
      if (e > j) and (L[e] = '''') then
      begin
        V := StringReplace(Copy(L, j + 1, e - j - 1), '''''', '''',
          [rfReplaceAll]);
        if NamesParam(V, AName) and IsParamArg(AMap, Li, j) then
          Exit(True);
      end;
      j := e + 1;
    end;
  end;
end;

{ TRdxParamNameFix }

class function TRdxParamNameFix.UsePlaceholder(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  F       : TParamFinding;
  Name    : string;
  Call    : TRdxToken;
  c, e    : Integer;
  Routine : TRdxRoutine;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  Name := '';
  c := 0;
  e := 0;
  Call := Default(TRdxToken);
  Routine := Default(TRdxRoutine);
  AReason := ParseFinding(AMessage, F);
  if AReason = '' then
    AReason := FindCall(AMap, ALine, F, Call, c, e);
  if AReason = '' then
    AReason := ChooseName(F, Name);
  if AReason = '' then
    AReason := EnclosingRoutine(AMap, Call, Routine);
  if (AReason = '') and NameUsed(AMap, Routine, Name) then
    AReason := _(R_PN_USED, [Name]);
  if AReason <> '' then
    Exit;
  AEdit.Span := TRefactorSpan.Make(SPAN_199, ALine, c + 1, ALine, e);
  AEdit.Expected := Copy(AMap.Raw(ALine), c + 1, e - c - 1);
  AEdit.NewText := Name;
  Result := True;
end;

end.

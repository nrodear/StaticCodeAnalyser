unit uRdxGroupedDeclFix;

// reDelphix - Editorhilfe SCA076 GroupedDeclaration, OHNE ToolsAPI und ohne
// Parser (Konzept_Editorhilfen_Regelliste_2026-10-11):
//   'A, B, C: T;' -> 'A: T;' / 'B: T;' / 'C: T;' - eine Zeile je Name, mit
//   der Einrueckung der Ursprungszeile. Bedeutungsgleich: jeder Name hat
//   danach denselben benannten Typ T wie zuvor.
//
// WAS DER DETEKTOR MELDET (uGroupedDeclaration): je Zeile hoechstens EINEN
// Fund, 'Grouped declaration at column N (...)', N = Spalte des ersten
// Namens der ersten Gruppe. Er liest Zeile fuer Zeile (Kommentare und
// Strings uebersprungen), meldet nicht in Klammern (Parameterlisten, auch
// ueber Zeilen) und nicht innerhalb eines case (Marken 'a, b: Anweisung').
// Er prueft NICHT, was nach dem Doppelpunkt steht ausser einem Wortanfang;
// die Meldung ist also auch ein Fund fuer 'A, B: record', 'A, B: array[..]
// of ..' oder 'A, B: Integer = 5' (nicht gueltig) und fuer Zeilen mit
// mehreren Gruppen.
//
// SPERREN (lieber keine Hilfe als eine falsche):
//   * Der Typ ist kein einfacher Typname (Bezeichner, auch mit Punkten, ein
//     Wort): anonyme Typen ('record', 'class', 'set of', Aufzaehlung,
//     'array[..] of', 'array of', '^T', 'string[N]') wuerden beim Teilen
//     je Name ein EIGENER Typ - Zuweisungen 'A := B' scheiterten danach
//     mit E2010. Ebenso Initialisierer ('= 5'), 'absolute', Direktiven
//     hinter dem Typ ('platform'). Generics ('TDictionary<K, V>') sperrt
//     der Planer nur aus Vorsicht: eine Instanziierung ist ein benannter
//     Typ, das Teilen waere bedeutungsgleich - aber der Typleser kennt
//     keine spitzen Klammern (Kommas darin, geschachtelte Argumente).
//   * Die Zeile enthaelt Kommentar, String oder Direktive, beginnt in einem
//     Block-Kommentar oder mehrzeiligen String.
//   * Mehrzeilige Deklaration (kein ';' hinter dem Typ auf der Zeile),
//     oder noch Code hinter dem ';' (eine zweite Gruppe).
//   * Vor den Namen steht mehr als Leerraum und ein einzelnes 'var'
//     (Attribut, 'private', 'class var', 'threadvar', 'procedure P; var').
//     Bei 'var' traegt jede neue Zeile das 'var' wieder - ein Inline-var
//     im Rumpf braucht es je Variable, ein var-Abschnitt verkraftet es.
//   * Vor der Gruppe steht ein Attribut, auch auf einer Zeile darueber
//     (das Code-Token davor ist ']'): es gilt fuer ALLE Namen, nach dem
//     Teilen stuende es nur ueber dem ersten ('[Weak]', '[Unsafe]',
//     '[Volatile]', RTTI-Attribute wie '[Inject]' oder JSON-Namen).
//   * Die Zeile liegt in einer Klammer (Parameterliste ueber mehrere
//     Zeilen) oder in einem case (Marken statt Variablen); beides wie im
//     Detektor ueber alle Zeilen davor gezaehlt.
//   * Die Zeile ist verschoben: an der gemeldeten Spalte steht keine
//     Gruppe '<Name>, <Name>[, ..]: ' mehr.
//
// Der Planer ersetzt EINE Zeile (ganz, von Spalte 1) durch mehrere Zeilen,
// getrennt mit #10 (der Editor setzt das Zeilenende des Puffers). Der Teil
// ab dem letzten Namen (Leerraum, Doppelpunkt, Typ, Semikolon) bleibt
// Zeichen fuer Zeichen.

interface

uses
  uRdxBufferMath,    // TRdxEdit
  uRdxCodeMap;       // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_GD_MOVED   = 'no grouped declaration at the reported place';
  R_GD_PREFIX  = 'something other than blanks and a single "var" stands '
    + 'before the names (attribute, visibility, "class var", "threadvar", '
    + 'another declaration)';
  R_GD_TYPE    = 'not a single-line declaration with a plain type name '
    + '(anonymous or generic type, initializer, "absolute", directive, '
    + 'several groups or no ";" on the line)';
  R_GD_COMMENT = 'comment, string or directive on the line';
  R_GD_PARAMS  = 'inside a parameter list - the grouping is the style of '
    + 'the signature';
  R_GD_CASE    = 'inside a case statement - the names are labels, not '
    + 'variables';

type
  // Der Planer von SCA076 (Form TRdxMapPlanner, uRdxFixRunner).
  TRdxGroupedDeclFix = class
  public
    // ALine ist die Zeile des Funds, die Spalte steht in AMessage
    // ('at column N'). Liefert die eine Ersetzung der Zeile oder den Grund.
    class function Split(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxText;          // _(), MsgNoColumn, MsgMovedSuffix (nie uLocalization)

const
  SPAN_076 = 'sca076';
  KW_VAR   = 'var';
  // Als Typname nie ein Namensgeber: diese Woerter eroeffnen einen
  // anonymen oder besonderen Typ.
  NOT_A_TYPE_NAME: array[0..14] of string = ('record', 'class', 'set',
    'array', 'packed', 'file', 'procedure', 'function', 'reference',
    'object', 'interface', 'dispinterface', 'type', 'of', 'absolute');
  // Blockwoerter wie im Detektor (ZaehleBlockwort).
  KW_CASE = 'case';
  KW_END  = 'end';
  CASE_INNER: array[0..2] of string = ('begin', 'try', 'record');

type
  // Die Teile der Zeile.
  TGroupParts = record
    Prefix  : string;               // Text vor dem ersten Namen
    Names   : TArray<string>;
    Tail    : string;               // ab dem Ende des letzten Namens
  end;

// Das Wort ab AFrom (Bezeichner); AEnd = Spalte dahinter. '' ohne Wort.
function WordAt(const L: string; AFrom: Integer; out AEnd: Integer): string;
var
  j : Integer;
begin
  AEnd := AFrom;
  Result := '';
  if (AFrom < 1) or (AFrom > Length(L)) or not IsIdentStart(L[AFrom]) then
    Exit;
  j := AFrom;
  while (j <= Length(L)) and IsIdentChar(L[j]) do
    Inc(j);
  Result := Copy(L, AFrom, j - AFrom);
  AEnd := j;
end;

// Vor den Namen nur Leerraum, oder Leerraum 'var' Leerraum?
function PrefixOk(const APrefix: string): Boolean;
var
  i, j : Integer;
begin
  i := SkipBlanks(APrefix, 1);
  if i > Length(APrefix) then
    Exit(True);
  Result := False;
  if LowerCase(Copy(APrefix, i, Length(KW_VAR))) <> KW_VAR then
    Exit;
  j := i + Length(KW_VAR);
  // Mindestens ein Leerzeichen nach var, danach nur Leerraum.
  Result := (j <= Length(APrefix)) and (SkipBlanks(APrefix, j) > Length(APrefix));
end;

// Der Text hinter dem Doppelpunkt (ab AFrom): ein Typname (Bezeichner mit
// Punkten), dann ';', dann nur Leerraum. True, wenn die Form stimmt.
function PlainTypeTail(const L: string; AFrom: Integer): Boolean;
var
  p, e  : Integer;
  First : string;
  W     : string;
begin
  Result := False;
  p := SkipBlanks(L, AFrom);
  First := LowerCase(WordAt(L, p, e));
  if (First = '') or InList(First, NOT_A_TYPE_NAME) then
    Exit;
  p := e;
  // Weitere Glieder 'Unit.TypeName'.
  while (p <= Length(L)) and (L[p] = '.') do
  begin
    W := WordAt(L, p + 1, e);
    if W = '' then
      Exit;
    p := e;
  end;
  p := SkipBlanks(L, p);
  if (p > Length(L)) or (L[p] <> ';') then
    Exit;
  Result := SkipBlanks(L, p + 1) > Length(L);
end;

// Die Namen ab ACol: '<Name>, <Name>[, ..]' bis zum ':'; AColon = Spalte
// des Doppelpunkts, ALastEnd = Spalte hinter dem letzten Namen. False bei
// anderer Form oder weniger als zwei Namen.
function ParseNames(const L: string; ACol: Integer;
  out ANames: TArray<string>; out ALastEnd, AColon: Integer): Boolean;
var
  p, e : Integer;
  W    : string;
begin
  Result := False;
  ANames := nil;
  ALastEnd := ACol;
  AColon := 0;
  p := ACol;
  while True do
  begin
    W := WordAt(L, p, e);
    if W = '' then
      Exit;
    SetLength(ANames, Length(ANames) + 1);
    ANames[High(ANames)] := W;
    ALastEnd := e;
    p := SkipBlanks(L, e);
    if p > Length(L) then
      Exit;
    if L[p] = ':' then
      Break;
    if L[p] <> ',' then
      Exit;
    p := SkipBlanks(L, p + 1);
  end;
  AColon := p;
  Result := Length(ANames) >= 2;
end;

// Zaehlt ein Blockwort wie der Detektor (ZaehleBlockwort): 'case' oeffnet,
// begin/try/record IM case zaehlen gegen, 'end' schliesst.
procedure CountBlockWord(const AWord: string; var ACase, AInner: Integer);
begin
  if AWord = KW_CASE then
    Inc(ACase)
  else if InList(AWord, CASE_INNER) then
  begin
    if ACase > 0 then
      Inc(AInner);
  end
  else if AWord = KW_END then
  begin
    if ACase = 0 then
      Exit;
    if AInner > 0 then
      Dec(AInner)
    else
      Dec(ACase);
  end;
end;

// Liegt die Zeile in einer Klammer oder einem case? Wie der Detektor ueber
// alle Zeilen davor gezaehlt (auf Code-Token, Kommentare und Strings zaehlen
// nicht). '' oder der Grund.
function ContextReason(AMap: TRdxCodeMap; ALine: Integer): string;
var
  T, Prev : TRdxToken;
  Depth   : Integer;
  CaseD   : Integer;
  Inner   : Integer;
begin
  Result := '';
  Depth := 0;
  CaseD := 0;
  Inner := 0;
  Prev := Default(TRdxToken);
  T := NextToken(AMap, 1, 1);
  while (T.Low <> '') and (T.Line < ALine) do
  begin
    if T.Low = '(' then
      Inc(Depth)
    else if T.Low = ')' then
    begin
      if Depth > 0 then
        Dec(Depth);
    end
    else if (Depth = 0) and IsKeywordAfter(T, Prev) then
      CountBlockWord(T.Low, CaseD, Inner);
    Prev := T;
    T := After(AMap, T);
  end;
  if Depth > 0 then
    Exit(_(R_GD_PARAMS));
  if CaseD > 0 then
    Result := _(R_GD_CASE);
end;

// Die Zeile in ihre Teile zerlegen und die Form pruefen. '' oder der Grund.
function ParseLine(AMap: TRdxCodeMap; ALine, ACol: Integer;
  out AParts: TGroupParts): string;
var
  L              : string;
  LastEnd, Colon : Integer;
begin
  AParts := Default(TGroupParts);
  L := AMap.Raw(ALine);
  if (ACol > Length(L)) or not IsIdentStart(L[ACol])
     or ((ACol > 1) and IsIdentChar(L[ACol - 1]))
     or not AMap.IsCode(ALine, ACol) then
    Exit(MsgMovedSuffix(_(R_GD_MOVED)));
  if not ParseNames(L, ACol, AParts.Names, LastEnd, Colon) then
    Exit(MsgMovedSuffix(_(R_GD_MOVED)));
  if AMap.StartsInside(ALine) or AMap.HasNonCode(ALine, 1, Length(L)) then
    Exit(_(R_GD_COMMENT));
  AParts.Prefix := Copy(L, 1, ACol - 1);
  if not PrefixOk(AParts.Prefix) then
    Exit(_(R_GD_PREFIX));
  // Ein Attribut haengt an der ganzen Deklaration, also an JEDEM Namen der
  // Gruppe; nach dem Teilen stuende es nur noch ueber dem ersten ('[Weak]'
  // ueber 'FA, FB: IFoo;' machte FB zur starken Referenz). Das Code-Token
  // vor den Namen ist dann ']' - auf derselben Zeile (das faengt schon
  // PrefixOk) wie auf einer Zeile darueber, auch ueber Kommentare hinweg.
  if PrevToken(AMap, ALine, ACol).Low = ']' then
    Exit(_(R_GD_PREFIX));
  if not PlainTypeTail(L, Colon + 1) then
    Exit(_(R_GD_TYPE));
  AParts.Tail := Copy(L, LastEnd, MaxInt);
  Result := '';
end;

// Die neuen Zeilen: Prefix + Name + Tail je Name, mit #10 verbunden.
function NewLines(const AParts: TGroupParts): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(AParts.Names) do
    begin
      if i > 0 then
        SB.Append(#10);
      SB.Append(AParts.Prefix).Append(AParts.Names[i]).Append(AParts.Tail);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ TRdxGroupedDeclFix }

class function TRdxGroupedDeclFix.Split(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Col   : Integer;
  Parts : TGroupParts;
  L     : string;
begin
  AEdit := Default(TRdxEdit);
  Col := ColumnFromMessage(AMessage);
  if Col <= 0 then
    AReason := MsgNoColumn
  else
    AReason := ParseLine(AMap, ALine, Col, Parts);
  if AReason = '' then
    AReason := ContextReason(AMap, ALine);
  Result := AReason = '';
  if not Result then
    Exit;
  L := AMap.Raw(ALine);
  AEdit.Span := TRefactorSpan.Make(SPAN_076, ALine, 1, ALine, Length(L) + 1);
  AEdit.Expected := L;
  AEdit.NewText := NewLines(Parts);
end;

end.

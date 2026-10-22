unit uRdxEmptyBlockFix;

// reDelphix - Editorhilfe SCA077 EmptyBlock, OHNE ToolsAPI und ohne Parser
// (Konzept_Editorhilfen_Regelliste_2026-10-11):
//   'with X.Add(T) do begin end;' -> 'X.Add(T);' - der with-Kopf und der
//   leere Block fallen weg, der Aufruf bleibt als Anweisung und wird wie
//   vorher genau einmal ausgefuehrt. Gleiche Bedeutung.
//
// WAS DER DETEKTOR MELDET (uEmptyBlock): jedes 'begin' mit einem 'end' als
// naechstem Wort (auf der Text-Sicht OHNE Kommentare), ausser Routinenrumpf
// ('procedure P; begin end;', das meldet SCA020) und 'begin end.' am Dateiende.
// Gemeldet wird die Zeile des BEGIN; die Meldung traegt weder Spalte noch
// Namen. Er meldet also auch 'begin {Kommentar} end', 'if C then begin end;',
// 'else begin end', 'while C do begin end;' und 'begin end;' allein.
//
// DIE EINE FORM: 'with <Aufrufkette> do begin end' - begin und end duerfen auch
// auf eigenen Zeilen stehen. Alle anderen leeren Bloecke bekommen KEINE Hilfe:
// ob eine Anweisung fehlt oder der Zweig weg kann ('if C then begin end;'
// verlangt die Entscheidung, ob die Bedingung noch gebraucht wird), kann nur
// der Mensch sagen.
//
// SPERREN (lieber keine Hilfe als eine falsche):
//   * auf der Zeile nicht genau ein begin, oder dahinter nicht das end (Zeile
//     verschoben, Block nicht leer);
//   * vor dem begin kein 'with ... do' (andere leere Bloecke), mehrere
//     Variablen im with ('with A, B do'), der with-Kopf ueber mehrere Zeilen;
//   * Kommentar oder Direktive zwischen with und end;
//   * der Ausdruck ist kein Aufruf ('with Foo do begin end;' - als Anweisung
//     bliebe ein Bezeichner, das ist ungueltig) oder mehr als eine Kette
//     'Name.Name(...).Name(...)' (Index '[..]', 'as', Generics, Operatoren);
//   * der Ausdruck KOENNTE ein Typecast sein: ein Name mit Klammern ohne
//     Qualifizierer ('with Foo(X) do') oder ein letztes Glied, das nach einem
//     Typ aussieht (T.., I.., E.., P.. mit grossem zweiten Buchstaben) -
//     'TButton(Sender);' ist keine Anweisung;
//   * hinter dem end etwas anderes als ';' oder ein Block-Ende (end, until,
//     else, except, finally).
// Der Planer ersetzt EINEN Bereich (von with bis end) durch die Aufrufkette.

interface

uses
  uRdxBufferMath,    // TRdxEdit
  uRdxCodeMap;       // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_EBL_NO_BEGIN = 'no "begin" at the reported place';
  R_EBL_MANY = 'several "begin" on the reported line';
  R_EBL_NOT_EMPTY = 'the block is not empty';
  R_EBL_NO_WITH = 'the empty block does not belong to a "with ... do" - '
    + 'delete it or fill it by hand';
  R_EBL_MULTI = 'several objects in the "with" - by hand';
  R_EBL_MULTILINE = 'the "with" header spans several lines';
  R_EBL_COMMENT = 'comment or directive between "with" and "end"';
  R_EBL_NO_CALL = 'the "with" expression is no call - nothing valid would '
    + 'remain as a statement';
  R_EBL_SHAPE = 'the "with" expression is not a plain call chain '
    + '"A.B(...)"';
  R_EBL_CAST = 'the "with" expression could be a type cast - "Name(X);" '
    + 'would not be a statement';
  R_EBL_TAIL = 'unexpected code after the empty block';

type
  // Der Planer von SCA077 (Form TRdxMapPlanner, uRdxFixRunner).
  TRdxEmptyBlockFix = class
  public
    // ALine ist die Zeile des begin; AMessage wird nicht gebraucht. Liefert
    // die eine Ersetzung von with bis end oder den Grund.
    class function WithToCall(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxText;          // _(): in die reDelphix-Sprache (E29), nie uLocalization

const
  SPAN_077 = 'sca077';
  KW_BEGIN = 'begin';
  KW_END   = 'end';
  KW_DO    = 'do';
  KW_WITH  = 'with';
  // So weit zurueck sucht die Suche nach dem with (Token).
  MAX_BACK = 60;
  // Hier ist rueckwaerts kein with-Kopf mehr zu erwarten.
  STOP_BACK: array[0..9] of string = (';', 'begin', 'end', 'do', 'then',
    'else', 'of', 'repeat', 'try', 'finally');
  // Bezeichner, die ein Schluesselwort sind: kein Name einer Aufrufkette.
  NOT_NAME: array[0..22] of string = ('inherited', 'nil', 'not', 'string',
    'array', 'procedure', 'function', 'if', 'case', 'as', 'is', 'in', 'and',
    'or', 'xor', 'div', 'mod', 'shl', 'shr', 'with', 'for', 'while', 'raise');
  // Hinter 'end' darf ohne ';' nur das Ende des umgebenden Blocks folgen.
  FOLLOW_OK: array[0..4] of string = ('end', 'until', 'else', 'except',
    'finally');

// Das eine begin auf ALine (Code-Sicht, als Schluesselwort). '' oder der
// Grund.
function FindBegin(AMap: TRdxCodeMap; ALine: Integer;
  out ABegin: TRdxToken): string;
var
  T : TRdxToken;
  N : Integer;
begin
  ABegin := Default(TRdxToken);
  N := 0;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if (T.Low = KW_BEGIN) and IsKeywordAfter(T, Before(AMap, T)) then
    begin
      Inc(N);
      ABegin := T;
    end;
    T := After(AMap, T);
  end;
  if N = 0 then
    Result := MsgMovedSuffix(_(R_EBL_NO_BEGIN))
  else if N > 1 then
    Result := _(R_EBL_MANY)
  else
    Result := '';
end;

// Das with zum 'do' ADo, rueckwaerts gelesen. AMulti: ein ',' auf oberster
// Klammerebene (runde und eckige) dazwischen; ACrossed: das with steht auf einer anderen Zeile
// als das do. '' oder der Grund (kein with-Kopf).
function FindWith(AMap: TRdxCodeMap; const ADo: TRdxToken;
  out AWith: TRdxToken; out AMulti, ACrossed: Boolean): string;
var
  T     : TRdxToken;
  Depth : Integer;
  I     : Integer;
begin
  Result := _(R_EBL_NO_WITH);
  AWith := Default(TRdxToken);
  AMulti := False;
  ACrossed := False;
  Depth := 0;
  T := Before(AMap, ADo);
  for I := 1 to MAX_BACK do
  begin
    if T.Low = '' then
      Exit;
    if (T.Low = KW_WITH) and (Depth = 0) and IsKeywordAfter(T, Before(AMap, T)) then
    begin
      AWith := T;
      ACrossed := T.Line <> ADo.Line;
      Exit('');
    end;
    if InList(T.Low, STOP_BACK) then
      Exit;
    // Rueckwaerts: ein Schliesser oeffnet eine Ebene. Runde UND eckige
    // Klammern - ein Komma im Index 'L[0, 1]' trennt keine with-Objekte.
    Dec(Depth, ParenDelta(T));
    if (T.Low = ',') and (Depth = 0) then
      AMulti := True;
    if Depth < 0 then
      Exit;
    T := Before(AMap, T);
  end;
end;

// Sieht ein Name nach einem Typ aus (Typecast)?
function LooksLikeType(const AName: string): Boolean;
begin
  Result := (Length(AName) >= 2) and CharInSet(AName[1], ['T', 'I', 'E', 'P'])
    and CharInSet(AName[2], ['A'..'Z']);
end;

// Die Form des Ausdrucks zwischen with und do: eine Kette 'Name[(..)]' durch
// '.' getrennt, das letzte Glied MIT Klammern, alles auf einer Zeile. AFirst
// ist das erste Token der Kette, ALast das schliessende ')'. '' oder der
// Grund.
function ShapeReason(AMap: TRdxCodeMap; const AWith, ADo: TRdxToken;
  out AFirst, ALast: TRdxToken): string;
var
  T, Open, Close : TRdxToken;
  Segs           : Integer;
  Name           : string;
  HasArgs, More  : Boolean;
begin
  AFirst := After(AMap, AWith);
  ALast := Default(TRdxToken);
  T := AFirst;
  Segs := 0;
  Name := '';
  repeat
    if not T.IsWord or InList(T.Low, NOT_NAME) then
      Exit(_(R_EBL_SHAPE));
    Inc(Segs);
    Name := TokText(AMap, T);
    T := After(AMap, T);
    HasArgs := False;
    if T.Low = '(' then
    begin
      Open := T;
      Close := MatchClose(AMap, Open, 0);
      if Close.Low = '' then
        Exit(_(R_EBL_SHAPE));
      HasArgs := True;
      ALast := Close;
      T := After(AMap, Close);
    end;
    More := T.Low = '.';
    if More then
      T := After(AMap, T);
  until not More;
  if not SameTok(T, ADo) then
    Exit(_(R_EBL_SHAPE));
  // ALast ist nur bei einem Aufruf mit Klammern gesetzt (sonst Zeile 0).
  if (T.Line <> AWith.Line)
     or ((ALast.Line <> 0) and (ALast.Line <> AWith.Line)) then
    Exit(_(R_EBL_MULTILINE));
  if not HasArgs then
    Exit(_(R_EBL_NO_CALL));
  if (Segs = 1) or LooksLikeType(Name) then
    Exit(_(R_EBL_CAST));
  Result := '';
end;

// Hinter dem end: ';' oder das Ende des umgebenden Blocks.
function TailReason(AMap: TRdxCodeMap; const AEnd: TRdxToken): string;
var
  Nx : TRdxToken;
begin
  Result := '';
  Nx := After(AMap, AEnd);
  if Nx.Low = ';' then
    Exit;
  if not (IsKeywordAfter(Nx, AEnd) and InList(Nx.Low, FOLLOW_OK)) then
    Result := _(R_EBL_TAIL);
end;

{ TRdxEmptyBlockFix }

class function TRdxEmptyBlockFix.WithToCall(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Bg, E, Dt, W, First, Last : TRdxToken;
  Multi, Crossed            : Boolean;
  Span                      : TRefactorSpan;
begin
  AEdit := Default(TRdxEdit);
  Bg := Default(TRdxToken);
  E := Default(TRdxToken);
  Dt := Default(TRdxToken);
  W := Default(TRdxToken);
  First := Default(TRdxToken);
  Last := Default(TRdxToken);
  Multi := False;
  Crossed := False;
  AReason := FindBegin(AMap, ALine, Bg);
  if AReason = '' then
  begin
    E := After(AMap, Bg);
    if not ((E.Low = KW_END) and IsKeywordAfter(E, Bg)) then
      AReason := MsgMovedSuffix(_(R_EBL_NOT_EMPTY));
  end;
  if AReason = '' then
  begin
    Dt := Before(AMap, Bg);
    if not ((Dt.Low = KW_DO) and IsKeywordAfter(Dt, Before(AMap, Dt))) then
      AReason := _(R_EBL_NO_WITH);
  end;
  if AReason = '' then
    AReason := FindWith(AMap, Dt, W, Multi, Crossed);
  if AReason = '' then
  begin
    if Multi then
      AReason := _(R_EBL_MULTI)
    else if Crossed then
      AReason := _(R_EBL_MULTILINE);
  end;
  if AReason = '' then
    AReason := ShapeReason(AMap, W, Dt, First, Last);
  if AReason = '' then
    AReason := TailReason(AMap, E);
  if AReason = '' then
  begin
    Span := TRefactorSpan.Make(SPAN_077, W.Line, W.Col, E.Line, E.EndCol);
    if CommentInRange(AMap, Span) then
      AReason := _(R_EBL_COMMENT)
    else
    begin
      AEdit.Span := Span;
      AEdit.Expected := RangeText(AMap, Span);
      AEdit.NewText := Copy(AMap.Raw(W.Line), First.Col,
        Last.EndCol - First.Col);
    end;
  end;
  Result := AReason = '';
  if not Result then
    AEdit := Default(TRdxEdit);
end;

end.

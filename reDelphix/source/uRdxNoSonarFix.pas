unit uRdxNoSonarFix;

// reDelphix - Editorhilfe fuer SCA065 NoSonarMarker, OHNE ToolsAPI und ohne
// Parser: ein '// NOSONAR' hinter Code wird zum Marker des Analysers,
// '// noinspection All', der UEBER die Zeile kommt; was im Kommentar hinter
// NOSONAR stand, bleibt als Kommentar hinter dem Code.
//
// WARUM NICHT EINFACH DAS WORT TAUSCHEN (Marker-Grammatik, uSuppression):
//   * Ein Marker gilt fuer die naechste nicht-leere und die naechste Code-
//     Zeile, NIE fuer die eigene. 'X; // noinspection All' unterdrueckte also
//     die Zeile DARUNTER - NOSONAR meint (wie bei SonarQube) die eigene.
//   * 'All' gilt nur als GANZE Artenliste. 'noinspection All (Grund)' oder
//     'noinspection All - Grund' sind kein Marker (das Wort All ist keine
//     Art); der Grund darf darum nicht auf die Markerzeile.
// Die Hilfe setzt deshalb eine neue Zeile '<Einzug>// noinspection All' ueber
// die Fundzeile und laesst den Rest des Kommentars hinter dem Code stehen.
//
// UMFORMUNG (eine Ersetzung der ganzen Fundzeile, Expected = die Zeile):
//   Dispose(P); // NOSONAR - weil legacy   ->   // noinspection All
//                                               Dispose(P); // weil legacy
// Ein fuehrender ':' oder alleinstehender '-' hinter NOSONAR faellt mit dem
// Wort weg; ohne Rest entfaellt der Kommentar samt Leerraum davor.
//
// WIRKUNG (Changes: True): der Analyser kennt NOSONAR nicht und unterdrueckt
// bisher nichts; danach unterdrueckt der Marker ALLE Regeln der Zeile -
// ausser den kritischen Arten (HardcodedSecret, SQLInjection, CommandInjection,
// DfmHardcodedDbCreds, DfmSqlFromUserInput, InsecureCryptoAlgorithm), die 'All'
// nie erfasst (CRITICAL_KINDS_NOT_SUPPRESSIBLE_BY_ALL). Steht auf der Zeile
// kein Fund, meldet SCA165 den neuen Marker als wirkungslos.
//
// GRUNDSATZ wie in uRdxLineFixes: lieber keine Hilfe als eine falsche. Keine
// Hilfe, wenn
//   - an der Spalte der Meldung kein echter '//'-Kommentar steht (Zeile
//     verschoben; Marker in String, '{ }' oder '(* *)'), oder die Zeile in
//     einem Block-Kommentar oder mehrzeiligen String beginnt,
//   - der Kommentar das Wort mehrfach nennt oder NOSONAR nicht sein erstes
//     Wort ist ('// siehe NOSONAR'),
//   - der Kommentar auf einer eigenen Zeile steht (welche Zeile gemeint ist,
//     bleibt offen),
//   - der Rest hinter NOSONAR mit 'noinspection' beginnt (er wuerde ein
//     eigener Marker, der die FOLGEZEILE trifft),
//   - direkt darueber schon ein '// noinspection All' steht.
// Ein Marker fuer eine Art darueber stoert nicht: gestapelte Marker
// vereinigt der Core fuer das Code-Ziel.

interface

uses
  uRdxBufferMath,        // TRdxEdit
  uRdxCodeMap;           // TRdxCodeMap

const
  // Gruende der Ablehnung als englische msgids (die Tests pruefen sie mit
  // _()).
  R_NS_MOVED = 'no "NOSONAR" comment at the reported place';
  R_NS_MANY = 'the comment names NOSONAR more than once';
  R_NS_NOT_FIRST = 'NOSONAR is not the first word of the comment';
  R_NS_OWN_LINE = 'the comment stands on a line of its own - which line the '
    + 'marker belongs to is unclear';
  R_NS_REST_MARKER = 'the text after NOSONAR starts with "noinspection" - it '
    + 'would become a marker of its own';
  R_NS_HAVE_ALL = 'a "// noinspection All" marker already stands above - '
    + 'delete the NOSONAR comment by hand';

type
  // Der Planer von SCA065 (Form TRdxMapPlanner, uRdxFixRunner).
  TRdxNoSonarFix = class
  public
    // SCA065: NOSONAR in ALine (Spalte des '//' aus der Meldung 'at column
    // N') -> Marker-Zeile darueber, Rest des Kommentars hinter dem Code.
    class function ToNoinspection(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxText;          // _(): in die reDelphix-Sprache, nie uLocalization

const
  SPAN_065     = 'sca065';
  WORD_LOWER   = 'nosonar';
  TAG_LOWER    = 'noinspection';
  MARKER_LINE  = '// noinspection All';
  // Die Markerzeile darueber ohne Leerraum und klein: so steht ein fertiger
  // 'All'-Marker da (mit Text dahinter ist es keiner).
  MARKER_SQUEEZED = '//noinspectionall';

// Spalte des ersten GANZEN Wortes NOSONAR in ALower (schon klein
// geschrieben), 0 ohne; ACount = Zahl der ganzen Woerter. Wortgrenzen wie im
// Detektor (uNoSonarMarker): ein Bezeichnerzeichen davor oder dahinter
// ('NOSONARQUBE', 'uNoSonarMarker') macht es zum anderen Wort.
function FindMarker(const ALower: string; out ACount: Integer): Integer;
var
  P, Behind : Integer;
begin
  Result := 0;
  ACount := 0;
  P := Pos(WORD_LOWER, ALower);
  while P > 0 do
  begin
    Behind := P + Length(WORD_LOWER);
    if ((P = 1) or not IsIdentChar(ALower[P - 1]))
       and ((Behind > Length(ALower)) or not IsIdentChar(ALower[Behind])) then
    begin
      Inc(ACount);
      if Result = 0 then
        Result := P;
    end;
    P := Pos(WORD_LOWER, ALower, P + 1);
  end;
end;

// AText ohne Leerzeichen und Tabs, klein.
function Squeezed(const AText: string): string;
var
  i : Integer;
begin
  Result := '';
  for i := 1 to Length(AText) do
    if not IsBlank(AText[i]) then
      Result := Result + AText[i];
  Result := LowerCase(Result);
end;

// Der Einzug der Zeile (Leerzeichen und Tabs am Anfang).
function IndentOf(const AText: string): string;
begin
  Result := Copy(AText, 1, SkipBlanks(AText, 1) - 1);
end;

// Der Kommentarrest hinter dem Wort NOSONAR: getrimmt, ein fuehrender ':'
// oder ein alleinstehendes '-' (Trenner vor der Begruendung) entfallen.
function ReasonAfter(const ABody: string; AWordCol: Integer): string;
begin
  Result := Trim(Copy(ABody, AWordCol + Length(WORD_LOWER), MaxInt));
  if (Result <> '') and (Result[1] = ':') then
    Result := Trim(Copy(Result, 2, MaxInt))
  else if (Result <> '') and (Result[1] = '-')
          and ((Length(Result) = 1) or IsBlank(Result[2])) then
    Result := Trim(Copy(Result, 2, MaxInt));
end;

class function TRdxNoSonarFix.ToNoinspection(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  L, Body, Lead, Code, Rest  : string;
  Col, P, N                   : Integer;
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
  if AMap.StartsInside(ALine) then
  begin
    AReason := MsgLineStartsInCommentOrString;
    Exit;
  end;
  // Der echte '//'-Kommentar muss GENAU an der gemeldeten Spalte beginnen
  // (nicht in String, '{ }' oder '(* *)'; der Detektor kennt mehrzeilige
  // Strings nicht und meldet dort trotzdem).
  if (ALine < 1) or (ALine > AMap.LineCount)
     or (AMap.LineCommentCol(ALine) <> Col) then
  begin
    AReason := MsgMovedSuffix(_(R_NS_MOVED));
    Exit;
  end;
  L := AMap.Raw(ALine);
  Body := Copy(L, Col + 2, MaxInt);
  P := FindMarker(LowerCase(Body), N);
  if P = 0 then
  begin
    AReason := MsgMovedSuffix(_(R_NS_MOVED));
    Exit;
  end;
  if N > 1 then
  begin
    AReason := _(R_NS_MANY);
    Exit;
  end;
  if Trim(Copy(Body, 1, P - 1)) <> '' then
  begin
    AReason := _(R_NS_NOT_FIRST);
    Exit;
  end;
  Lead := Copy(L, 1, Col - 1);
  Code := TrimRight(Lead);
  if Code = '' then
  begin
    AReason := _(R_NS_OWN_LINE);
    Exit;
  end;
  Rest := ReasonAfter(Body, P);
  if SameText(Copy(Rest, 1, Length(TAG_LOWER)), TAG_LOWER) then
  begin
    AReason := _(R_NS_REST_MARKER);
    Exit;
  end;
  if (ALine > 1) and (AMap.LineCommentCol(ALine - 1) > 0)
     and (Squeezed(AMap.Raw(ALine - 1)) = MARKER_SQUEEZED) then
  begin
    AReason := _(R_NS_HAVE_ALL);
    Exit;
  end;
  AEdit.Span := TRefactorSpan.Make(SPAN_065, ALine, 1, ALine, Length(L) + 1);
  AEdit.Expected := L;
  AEdit.NewText := IndentOf(L) + MARKER_LINE + #10 + Code;
  if Rest <> '' then
    AEdit.NewText := AEdit.NewText + Copy(Lead, Length(Code) + 1, MaxInt)
      + '// ' + Rest;
  Result := True;
end;

end.

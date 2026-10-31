unit uRdxTrailingCommaFix;

// reDelphix - Editorhilfe fuer SCA068 TrailingCommaArgList, OHNE ToolsAPI und
// ohne Parser: das ueberzaehlige Komma vor der schliessenden Klammer faellt
// weg ('V.Open(A, B,)' -> 'V.Open(A, B)'), samt dem Leerraum zwischen Komma
// und ')'.
// WAS DAS KOMMA BEDEUTET: in einem normalen Aufruf uebersetzt Delphi es
// nicht (leeres Zusatzargument, E2034) - echter Code mit dem Fund ist ein
// spaet gebundener Aufruf auf einem Variant oder einer dispinterface. Dort
// ist das leere letzte Argument ein weggelassener optionaler Parameter
// (varError -> DISP_E_PARAMNOTFOUND); nach der Hilfe wird es gar nicht
// uebergeben. Fuer einen COM-Server mit Typbibliothek ist das dasselbe,
// nur ein IDispatch, der seine Argumente zaehlt (cArgs), sieht eines
// weniger - darum KEINE Kennzeichnung "aendert Verhalten", der Hinweis
// nennt den Rest.
//
// DER FUND: uTrailingCommaArgList scannt zeilenweise (Kommentar- und
// String-Zustand wie im Quelltext) auf ',' + Leerraum (Blank, Tab) + ')' und
// meldet die 1-basierte Spalte des KOMMAS ('at column N') auf der Zeile des
// Kommas. Ein Komma am Zeilenende vor einer ')' auf der naechsten Zeile
// meldet er nicht - die Hilfe kennt also nur die Form auf EINER Zeile.
// Der Detektor sagt nicht, welche Klammer es ist; die Hilfe sucht darum
// rueckwaerts die oeffnende Klammer (Aufruf, Deklaration, Typecast,
// Konstante - alle gleich behandelt).
//
// GRUNDSATZ wie in uRdxLineFixes: lieber keine Hilfe als eine falsche. Keine
// Hilfe, wenn
//   - die Meldung keine Spalte nennt, an der Spalte kein Komma im Code steht
//     oder dahinter nicht nur Leerraum und ')' (Zeile verschoben, Kommentar,
//     String),
//   - vor dem Komma kein Argument steht ('(,)', ', ,)'): dort fehlt ein
//     Argument, das Komma ist nicht ueberzaehlig,
//   - die naechste offene Klammer ein '[' ist (Set- oder Array-Literal) oder
//     keine oeffnende Klammer zu finden ist.
// Kommentar oder Zeilenumbruch zwischen Komma und ')' gibt es fuer den
// Detektor nicht; steht dort heute einer, ist die Stelle verschoben.

interface

uses
  uRdxBufferMath,       // TRdxEdit
  uRdxCodeMap;          // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_COMMA_MOVED = 'no trailing comma before ")" at the reported place';
  R_COMMA_NOARG = 'no argument before the comma - the list is missing an '
    + 'element, the comma is not extra';
  R_COMMA_BRACKET = 'the comma ends a list inside "[...]" (set or array '
    + 'literal)';
  R_COMMA_NO_OPEN = 'the opening parenthesis was not found';

type
  // Der Planer von SCA068 (Form TRdxMapPlanner, uRdxFixRunner).
  TRdxTrailingCommaFix = class
  public
    // SCA068: an der Spalte aus der Meldung ('at column N') das Komma samt
    // Leerraum bis zur ')' loeschen; NewText = ''.
    class function DropComma(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,    // TRefactorSpan.Make
  uRdxText;         // _(): in die reDelphix-Sprache (E29), nie uLocalization

const
  SPAN_068 = 'sca068';
  // Soviele Token reicht die Suche nach der oeffnenden Klammer zurueck.
  MAX_BACK_TOKENS = 4000;

// Die naechste offene Klammer vor dem Komma: '(' ist gut, '[' und keine sind
// Gruende. '' oder der Grund.
function OpenerReason(AMap: TRdxCodeMap; const AComma: TRdxToken): string;
var
  T     : TRdxToken;
  Depth : Integer;
  Steps : Integer;
begin
  Result := _(R_COMMA_NO_OPEN);
  Depth := 0;
  Steps := 0;
  T := Before(AMap, AComma);
  while (T.Low <> '') and (Steps < MAX_BACK_TOKENS) do
  begin
    if (T.Low = ')') or (T.Low = ']') then
      Inc(Depth)
    else if (T.Low = '(') or (T.Low = '[') then
    begin
      if Depth = 0 then
      begin
        if T.Low = '(' then
          Result := ''
        else
          Result := _(R_COMMA_BRACKET);
        Exit;
      end;
      Dec(Depth);
    end;
    T := Before(AMap, T);
    Inc(Steps);
  end;
end;

class function TRdxTrailingCommaFix.DropComma(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  L        : string;
  Col, J   : Integer;
  PL, PC   : Integer;
  Comma    : TRdxToken;
  NoArg    : Boolean;
  PrevChar : Char;
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
  if (ALine < 1) or (ALine > AMap.LineCount) then
  begin
    AReason := MsgMovedSuffix(_(R_COMMA_MOVED));
    Exit;
  end;
  L := AMap.Raw(ALine);
  J := 0;
  if (Col <= Length(L)) and (L[Col] = ',') and AMap.IsCode(ALine, Col) then
    J := SkipBlanks(L, Col + 1);
  if (J = 0) or (J > Length(L)) or (L[J] <> ')') or not AMap.IsCode(ALine, J) then
  begin
    AReason := MsgMovedSuffix(_(R_COMMA_MOVED));
    Exit;
  end;
  Comma := TokenAt(AMap, ALine, Col);
  // Das letzte Zeichen aus Code ODER String vor dem Komma (PrevToken
  // uebersaehe einen String: nach 'x', stuende dort das Komma davor). Das
  // letzte Zeichen eines Strings ist ein Quote, nie '(' ',' oder '['.
  NoArg := not LastCharBefore(AMap, Comma, PL, PC);
  if not NoArg then
  begin
    PrevChar := AMap.Raw(PL)[PC];
    NoArg := AMap.IsCode(PL, PC)
      and ((PrevChar = '(') or (PrevChar = ',') or (PrevChar = '['));
  end;
  if NoArg then
  begin
    AReason := _(R_COMMA_NOARG);
    Exit;
  end;
  AReason := OpenerReason(AMap, Comma);
  if AReason <> '' then
    Exit;
  AEdit.Span := TRefactorSpan.Make(SPAN_068, ALine, Col, ALine, J);
  AEdit.Expected := Copy(L, Col, J - Col);
  AEdit.NewText := '';
  Result := True;
end;

end.

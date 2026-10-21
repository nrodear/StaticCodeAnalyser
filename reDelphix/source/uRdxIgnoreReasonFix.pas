unit uRdxIgnoreReasonFix;

// reDelphix - Editorhilfe SCA179 AttributeIgnoreWithoutReason: aus
// '[Ignore]' (oder '[Ignore()]') wird '[Ignore('reason')]'. OHNE ToolsAPI und
// ohne Parser, nur auf der Code-Sicht (TRdxCodeMap). DUnitX ueberspringt den
// Test mit und ohne Text gleich - die Bedeutung bleibt, der Platzhalter
// 'reason' ist vom Menschen durch den echten Grund zu ersetzen (der Hinweis
// der Tabelle sagt es). Bewusst KEIN 'TODO: ..' als Platzhalter: TODO loest
// SCA019 aus und die Hilfe soll einen Fund nicht gegen den naechsten tauschen.
//
// Was der Detektor meldet (uAttributeIgnoreWithoutReason): eine Zeile, deren
// Code-Sicht (Kommentare gestrippt) ein '[Ignore]' oder '[Ignore()]' (Gross-/
// Kleinschreibung egal, Leerraum erlaubt) enthaelt UND die mit '[' beginnt
// (IsLikelyAttributePosition). LineNumber ist die Zeile des Attributs, die
// Meldung nennt keine Spalte. Der Planer sucht das Attribut daher selbst.
//
// GRUNDSATZ wie in uRdxLineFixes: lieber keine Hilfe als eine falsche. Die
// Hilfe gibt es nur, wenn die Zeile (ohne Einrueckung) GENAU aus dem einen
// Attribut besteht: '[' Ignore [ '(' ')' ] ']' und sonst nichts. Keine Hilfe,
// wenn
//   * die Zeile verschoben ist (kein '[' am Zeilenanfang, der Name ist ein
//     anderer, die Zeile liegt in einem Kommentar oder mehrzeiligen String),
//   * das Attribut in einer Gruppe steht ('[Ignore, Test]', '[Test, Ignore]')
//     oder hinter einem anderen Attribut ('[Test][Ignore]'),
//   * die Klammern schon einen Inhalt haben ('[Ignore('')]', '[Ignore(X)]')
//     - der Detektor meldet das ohnehin nicht, der Planer fasst es nicht an,
//   * hinter dem ']' Text oder ein Kommentar steht, oder ein Kommentar im
//     Attribut liegt.
// Der Bereich ist nur der Teil hinter dem Namen: Schreibweise des Namens und
// Einrueckung bleiben unberuehrt.

interface

uses
  System.Classes,       // TStrings
  uEngineApi,           // TSourcePlaces
  uMethodd12,           // TLeakFinding
  uRdxBufferMath,       // TRdxEdit
  uRdxCodeMap,          // TRdxCodeMap
  uRdxRecipeRunner;     // TRdxFixOutcome

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_IGN_MOVED = 'no "[Ignore]" attribute at the reported place';
  R_IGN_SHAPE = 'the attribute is not "[Ignore]" or "[Ignore()]" alone on '
    + 'its line - it is in a group, behind another attribute or has an '
    + 'argument';
  R_IGN_TAIL = 'text or a comment follows the attribute or sits inside it';
  // Der Platzhalter in den Klammern (neutral, kein TODO: SCA019).
  IGN_PLACEHOLDER = 'reason';

type
  TRdxIgnoreReasonFix = class
  public
    // SCA179: ALine ist die Attributzeile aus dem Fund; die Meldung braucht
    // der Planer nicht. Die Ersetzung ist der Teil hinter dem Namen bis zum
    // ']' (NewText = '(''reason'')]').
    class function AddReason(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

// Der Planer der Tabelle (Form TRdxFixPlanner aus uRdxFixTable) fuer SCA179.
function PlanIgnoreReason(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;

implementation

uses
  System.SysUtils,
  uRefactorInfo,        // TRefactorSpan.Make
  uRdxText,             // _() und MsgMovedSuffix (E29), nie uLocalization
  uRdxFixRunner;        // MapFix

const
  SPAN_179 = 'sca179';
  ATTR_NAME = 'ignore';

class function TRdxIgnoreReasonFix.AddReason(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  L                         : string;
  First, P, Q, Close, Tail : Integer;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  if (ALine < 1) or (ALine > AMap.LineCount) then
  begin
    AReason := MsgMovedSuffix(_(R_IGN_MOVED));
    Exit;
  end;
  L := AMap.Raw(ALine);
  First := SkipBlanks(L, 1);
  // '[' als Code am Zeilenanfang, dahinter der Name 'Ignore' (ganzes Wort).
  if AMap.StartsInside(ALine) or (First > Length(L)) or (L[First] <> '[')
     or not AMap.IsCode(ALine, First) then
  begin
    AReason := MsgMovedSuffix(_(R_IGN_MOVED));
    Exit;
  end;
  P := SkipBlanks(L, First + 1);
  Q := P;
  while (Q <= Length(L)) and IsIdentChar(L[Q]) do
    Inc(Q);
  if (P > Length(L)) or (Q = P) or not SameText(Copy(L, P, Q - P), ATTR_NAME)
     or not AMap.IsCode(ALine, P) then
  begin
    // Steht 'Ignore' woanders auf der Zeile ('[Test][Ignore]', '[Test,
    // Ignore]', '[IgnoreAttribute]'), ist es keine verschobene Zeile,
    // sondern eine Form, die die Hilfe nicht anfasst.
    if Pos(ATTR_NAME, LowerCase(L)) > 0 then
      AReason := _(R_IGN_SHAPE)
    else
      AReason := MsgMovedSuffix(_(R_IGN_MOVED));
    Exit;
  end;
  // Hinter dem Namen: ']' oder '(' ')' ']' - alles andere ist eine Gruppe
  // oder hat schon ein Argument.
  Close := SkipBlanks(L, Q);
  if (Close <= Length(L)) and (L[Close] = '(') then
  begin
    Close := SkipBlanks(L, Close + 1);
    if (Close > Length(L)) or (L[Close] <> ')') then
    begin
      AReason := _(R_IGN_SHAPE);
      Exit;
    end;
    Close := SkipBlanks(L, Close + 1);
  end;
  if (Close > Length(L)) or (L[Close] <> ']') then
  begin
    AReason := _(R_IGN_SHAPE);
    Exit;
  end;
  // Nach dem ']' nur noch Leerraum; kein Kommentar auf der Zeile; das ']'
  // ist Code.
  Tail := SkipBlanks(L, Close + 1);
  if (Tail <= Length(L)) or AMap.HasComment(ALine, 1, Length(L))
     or not AMap.IsCode(ALine, Close) then
  begin
    AReason := _(R_IGN_TAIL);
    Exit;
  end;
  // Der Bereich beginnt auf dem ersten Zeichen hinter dem Namen (Q <= Close,
  // also nie hinter dem Zeilenende) und endet hinter dem ']'.
  AEdit.Span := TRefactorSpan.Make(SPAN_179, ALine, Q, ALine, Close + 1);
  AEdit.Expected := RangeText(AMap, AEdit.Span);
  AEdit.NewText := '(''' + IGN_PLACEHOLDER + ''')]';
  Result := True;
end;

function PlanIgnoreReason(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxIgnoreReasonFix.AddReason);
end;

end.

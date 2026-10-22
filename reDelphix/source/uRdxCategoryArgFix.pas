unit uRdxCategoryArgFix;

// reDelphix - Editorhilfe SCA181 AttributeCategoryWithoutString:
// '[Category]' -> '[Category(''category'')]'. OHNE ToolsAPI und ohne Parser,
// nur auf der Code-Sicht (TRdxCodeMap).
//
// Was der Detektor meldet (uAttributeCategoryWithoutString): eine Zeile, in
// deren Code-Text (Kommentare entfernt) die Regex '\[Category\s*\]' trifft
// (ohne Beachtung der Gross-/Kleinschreibung) und die als Attributposition
// gilt (IsLikelyAttributePosition). Gemeldet wird also NUR die Form ohne
// jedes Argument. '[Category()]', '[Category(Foo)]', '[Category(5)]' und
// '[Test, Category]' meldet er nie (die Regex verlangt ']' unmittelbar
// hinter dem Namen und '[' unmittelbar davor) - eine Konstante oder ein
// Ausdruck als Argument ist also kein Fall dieser Regel, und diese Hilfe
// fasst sie nicht an. Die Meldung nennt keine Spalte; der Planer sucht das
// Attribut auf der Zeile selbst.
//
// Der Platzhalter ist ein kleines, neutrales Wort ('category'), kein TODO
// (SCA019). Er macht den Code uebersetzbar; der Name der Kategorie bleibt
// Sache des Autors - die Hilfe kann ihn nicht kennen.
//
// GRUNDSATZ wie in uRdxLineFixes: lieber keine Hilfe als eine falsche. Keine
// Hilfe, wenn
//   * die Zeile nicht mit '[Category' + optionalen Blanks + ']' als Code
//     beginnt (verschoben; in einem Kommentar oder mehrzeiligen String) -
//     steht '[Category' weiter hinten ('[Test][Category]', das meldet der
//     Detektor), ist es die Form, die die Hilfe nicht anfasst (R_CAT_SHAPE),
//     keine verschobene Zeile,
//   * das Attribut ein Argument oder eine Liste traegt ('(' oder ',' statt
//     ']'),
//   * hinter dem ']' noch Code steht (weiteres Attribut, Gruppe auf einer
//     Zeile, Ausdruck - '[Category][Test]'), oder eine Direktive,
//   * vor dem Attribut kein Deklarationsende steht (';', ein Abschnitts-
//     wort, 'class'/'record'/'interface'/'object', ein weiteres Attribut) -
//     das schliesst einen Array-Index 'Foo[Category]' aus - oder eine
//     Direktive zwischen dem Anker und der Zeile liegt. Ein Attribut direkt
//     hinter dem Kopf 'TMyTests = class(TObject)' ohne Sichtbarkeitswort
//     (das Token davor ist ')') bekommt darum KEINE Hilfe - ein Entscheid
//     wie in uRdxAttrGapFix, kein Fehler: ')' beendet auch Ausdruecke.
// Ein Kommentar hinter dem ']' stoert nicht: er nennt keinen Kategorie-
// namen, der Platzhalter verdoppelt nichts. SCA179 (uRdxIgnoreReasonFix)
// entscheidet dort bewusst anders - siehe deren Kopf.

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
  R_CAT_MOVED = 'no "[Category]" at the reported place';
  R_CAT_ARG = 'the attribute already has an argument or a list - not '
    + 'touched';
  R_CAT_TAIL = 'more code follows the attribute on the line';
  R_CAT_ANCHOR = 'no end of a declaration before the attribute - not a safe '
    + 'attribute context';
  R_CAT_DIRECTIVE = 'a compiler directive is in the way';
  R_CAT_SHAPE = 'the attribute stands behind another attribute on its line';

  // Der Platzhalter im Argument.
  CATEGORY_PLACEHOLDER = 'category';

type
  // Der Planer von SCA181 (Form TRdxMapPlanner, uRdxFixRunner).
  TRdxCategoryArgFix = class
  public
    // SCA181: auf der Zeile ALine aus '[Category]' '[Category(''category'')]'
    // machen; sonst der Grund.
    class function AddArgument(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

// Der Planer der Tabelle (Form TRdxFixPlanner aus uRdxFixTable): Zeile und
// Meldung aus dem Fund, die Hilfe ueber MapFix.
function PlanCategoryArg(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;

implementation

uses
  System.SysUtils,
  uRefactorInfo,       // TRefactorSpan.Make
  uRdxText,            // _(): in die reDelphix-Sprache (E29), nie uLocalization
  uRdxFixRunner;       // MapFix

const
  SPAN_181 = 'sca181';
  ATTR_NAME = 'Category';
  // Davor darf eine Attributzeile beginnen: Ende der Deklaration davor,
  // Abschnittswort, Beginn eines Typs (class, record, ...), anderes Attribut.
  ANCHOR_WORDS: array[0..13] of string = (';', ']', 'public', 'private',
    'protected', 'published', 'automated', 'class', 'record', 'interface',
    'object', 'type', 'implementation', 'dispinterface');

class function TRdxCategoryArgFix.AddArgument(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  L                    : string;
  First, P, Q, R, T, j : Integer;
  Prev                 : TRdxToken;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  L := AMap.Raw(ALine);
  First := SkipBlanks(L, 1);
  // '[' als erstes Zeichen der Zeile, als Code.
  if AMap.StartsInside(ALine) or (First > Length(L)) or (L[First] <> '[')
     or not AMap.IsCode(ALine, First) then
  begin
    AReason := MsgMovedSuffix(_(R_CAT_MOVED));
    Exit;
  end;
  // Unmittelbar dahinter 'Category' (wie die Regex des Detektors), ganz als
  // Code, ohne weiteres Namenszeichen.
  P := First + 1;
  Q := P + Length(ATTR_NAME);
  if (Q - 1 > Length(L)) or not SameText(Copy(L, P, Length(ATTR_NAME)), ATTR_NAME)
     or ((Q <= Length(L)) and IsIdentChar(L[Q])) then
  begin
    // '[Test][Category]': das Attribut steht weiter hinten - eine Form, die
    // die Hilfe nicht anfasst, keine verschobene Zeile ('Datei neu pruefen'
    // aenderte nichts).
    j := Pos('[' + LowerCase(ATTR_NAME), LowerCase(L));
    if (j > First) and AMap.IsCode(ALine, j) then
      AReason := _(R_CAT_SHAPE)
    else
      AReason := MsgMovedSuffix(_(R_CAT_MOVED));
    Exit;
  end;
  for j := P to Q - 1 do
    if not AMap.IsCode(ALine, j) then
    begin
      AReason := MsgMovedSuffix(_(R_CAT_MOVED));
      Exit;
    end;
  // Hinter dem Namen nur Blanks bis zum ']'.
  R := SkipBlanks(L, Q);
  if (R > Length(L)) or not AMap.IsCode(ALine, R) then
  begin
    AReason := MsgMovedSuffix(_(R_CAT_MOVED));
    Exit;
  end;
  if (L[R] = '(') or (L[R] = ',') or (L[R] = ':') then
  begin
    AReason := _(R_CAT_ARG);
    Exit;
  end;
  if L[R] <> ']' then
  begin
    AReason := MsgMovedSuffix(_(R_CAT_MOVED));
    Exit;
  end;
  // Hinter dem ']' nichts als Blanks und ein Kommentar.
  T := SkipBlanks(L, R + 1);
  if T <= Length(L) then
  begin
    if DirectiveAt(AMap, ALine, T) then
    begin
      AReason := _(R_CAT_DIRECTIVE);
      Exit;
    end;
    if AMap.IsCode(ALine, T) then
    begin
      AReason := _(R_CAT_TAIL);
      Exit;
    end;
  end;
  // Das Token vor dem Attribut: eine Deklaration ist zu Ende oder beginnt.
  Prev := PrevToken(AMap, ALine, First);
  if (Prev.Low = '') or not InList(Prev.Low, ANCHOR_WORDS) then
  begin
    AReason := _(R_CAT_ANCHOR);
    Exit;
  end;
  if DirectiveInLines(AMap, Prev.Line, ALine) then
  begin
    AReason := _(R_CAT_DIRECTIVE);
    Exit;
  end;
  // Der Bereich: der Name samt Blanks bis vor das ']' (nie leer, beginnt auf
  // einem Zeichen). Der Name behaelt seine Schreibweise, die Blanks bleiben.
  AEdit.Span := TRefactorSpan.Make(SPAN_181, ALine, P, ALine, R);
  AEdit.Expected := RangeText(AMap, AEdit.Span);
  AEdit.NewText := Copy(L, P, Length(ATTR_NAME)) + '(''' + CATEGORY_PLACEHOLDER
    + ''')' + Copy(L, Q, R - Q);
  Result := True;
end;

function PlanCategoryArg(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxCategoryArgFix.AddArgument);
end;

end.

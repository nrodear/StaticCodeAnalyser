unit uRdxAttrDuplicateFix;

// reDelphix - Editorhilfe SCA180 AttributeDuplicate: das doppelte Attribut
// loeschen. OHNE ToolsAPI und ohne Parser, nur auf der Code-Sicht
// (TRdxCodeMap).
//
// DER FUND (uAttributeDuplicate): der Detektor liest die ROHEN Zeilen, sucht
// '[' Name Rest ']' (Rest ohne ']'), und meldet einen Treffer, wenn ein
// FRUEHERER Treffer am selben Member (gleiche Zielzeile) denselben Namen
// (klein geschrieben) und denselben Rest (getrimmt, Zeichen fuer Zeichen)
// hat. LineNumber ist die Zeile der Dublette, die Meldung nennt
// 'Duplicate attribute [name<rest>] (first seen at line N)' - N ist die
// Zeile des naechsten frueheren gleichen Treffers (bei '[A][A]' die Zeile
// der Dublette selbst). '[A, A]' ist EIN Treffer und wird nie gemeldet.
//
// DIE HILFE loescht die Dublette: steht sie allein auf ihrer Zeile, die
// ganze Zeile; steht sie mit weiteren Attributen auf einer Zeile
// ('[A][A]', '[A] [A]'), nur die Gruppe samt Trennzeichen. Es ist immer die
// LETZTE gleiche Gruppe der Zeile; textgleich heisst Name (ohne Beachtung
// der Gross-/Kleinschreibung) und Argumente genau wie beim Detektor.
//
// GRUNDSATZ wie in uRdxLineFixes: lieber keine Hilfe als eine falsche. Keine
// Hilfe, wenn
//   * die Zeile der Meldung oder die Zeile des ersten Treffers die gleiche
//     Gruppe nicht traegt (verschoben, Kommentar, mehrzeiliger String),
//   * eine Zeile der Kette (erste Zeile bis Dublette) nicht NUR aus
//     Attributgruppen besteht: Code, Kommentar oder Direktive dazwischen
//     oder dahinter (Leerzeilen stoeren nicht),
//   * ein Attribut ein Ziel hat ([Result: ..], [assembly: ..]), ueber mehrere
//     Zeilen laeuft oder Klammern/Kommentarzeichen im Inneren hat (auch in
//     einem String: dort liest der Detektor das ']' anders),
//   * die Dublette die letzte Zeile der Datei waere.
// Attribute mit anderen Argumenten ([Category('a')] und [Category('b')])
// sind keine Dubletten - der Detektor meldet sie nicht, der Planer loescht
// sie nie.

interface

uses
  System.Classes,        // TStrings
  uEngineApi,            // TSourcePlaces
  uMethodd12,            // TLeakFinding
  uRdxBufferMath,        // TRdxEdit
  uRdxCodeMap,           // TRdxCodeMap
  uRdxRecipeRunner;      // TRdxFixOutcome

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_DUP_MSG = 'the message names neither the attribute nor its first line';
  R_DUP_MOVED = 'no duplicate attribute at the reported place';
  R_DUP_BETWEEN = 'code, a comment or a directive lies between the two '
    + 'attributes';
  R_DUP_TAIL = 'text or a comment follows the attribute';
  R_DUP_TARGET = 'attribute with a target (assembly:, Result:)';
  R_DUP_COMPLEX = 'attribute over several lines, or with brackets or '
    + 'comment signs inside';
  R_DUP_EOF = 'the duplicate is on the last line of the file';

type
  // Eine Attributgruppe '[..]' einer Zeile (Spalten 1-basiert).
  TRdxAttrGroup = record
    Start : Integer;   // Spalte des '['
    Stop  : Integer;   // Spalte des ']'
    Key   : string;    // klein geschriebener Name + getrimmter Rest
  end;

  TRdxAttrGroups = TArray<TRdxAttrGroup>;

  TRdxAttrDuplicateFix = class
  public
    // SCA180: ALine ist die Zeile der Dublette aus dem Fund, AMessage die
    // Meldung. Die Ersetzung loescht die Zeile bzw. die Gruppe
    // (NewText = ''); sonst der Grund.
    class function DeleteDuplicate(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // Die Meldung zerlegt: AKey (Name + Rest wie der Detektor ihn bildet)
    // und die Zeile des ersten Treffers. False, wenn sie die Form nicht hat.
    class function ReadMessage(const AMessage: string; out AKey: string;
      out AFirstLine: Integer): Boolean; static;

    // Die Zeile als reine Folge von Attributgruppen. '' oder das msgid des
    // Grundes (R_DUP_MOVED: keine Attributzeile).
    class function ReadLine(AMap: TRdxCodeMap; ALine: Integer;
      out AGroups: TRdxAttrGroups): string; static;
  end;

// Der Planer der Tabelle (Form TRdxFixPlanner aus uRdxFixTable): Zeile und
// Meldung aus dem Fund, die Hilfe ueber MapFix.
function PlanAttrDuplicate(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;

implementation

uses
  System.SysUtils,
  uRefactorInfo,         // TRefactorSpan.Make
  uRdxText,              // _(): in die reDelphix-Sprache, nie uLocalization
  uRdxFixRunner;         // MapFix

const
  SPAN_180 = 'sca180';
  KEY_OPEN = 'Duplicate attribute [';
  KEY_CLOSE = '] (first seen at line ';

// Der Grund in der Sprache des Benutzers; 'verschoben' mit dem Zusatz.
// Jeder Grund von ReadLine hat seinen Zweig mit der Konstante im _() (der
// Extraktor liest msgids nur so, ein _(AMsgId) waere dynamisch). Ein
// neuer Grund ohne Zweig faellt im Testlauf am Assert auf, statt still den
// Text von R_DUP_COMPLEX zu bekommen.
function ReasonText(const AMsgId: string): string;
begin
  if AMsgId = R_DUP_MOVED then
    Result := MsgMovedSuffix(_(R_DUP_MOVED))
  else if AMsgId = R_DUP_BETWEEN then
    Result := _(R_DUP_BETWEEN)
  else if AMsgId = R_DUP_TAIL then
    Result := _(R_DUP_TAIL)
  else if AMsgId = R_DUP_TARGET then
    Result := _(R_DUP_TARGET)
  else if AMsgId = R_DUP_COMPLEX then
    Result := _(R_DUP_COMPLEX)
  else
  begin
    Assert(False, 'ReasonText: reason without a branch - ' + AMsgId);
    Result := _(R_DUP_COMPLEX);
  end;
end;

// Zaehlt die Gruppen mit dem Schluessel AKey; ALast: Index der letzten.
function CountKey(const AGroups: TRdxAttrGroups; const AKey: string;
  out ALast: Integer): Integer;
var
  i : Integer;
begin
  Result := 0;
  ALast := -1;
  for i := 0 to High(AGroups) do
    if AGroups[i].Key = AKey then
    begin
      Inc(Result);
      ALast := i;
    end;
end;

class function TRdxAttrDuplicateFix.ReadMessage(const AMessage: string;
  out AKey: string; out AFirstLine: Integer): Boolean;
var
  P, Q, E : Integer;
begin
  Result := False;
  AKey := '';
  AFirstLine := 0;
  P := Pos(KEY_OPEN, AMessage);
  if P = 0 then Exit;
  Inc(P, Length(KEY_OPEN));
  Q := Pos(KEY_CLOSE, AMessage);
  if Q < P then Exit;
  AKey := Copy(AMessage, P, Q - P);
  Inc(Q, Length(KEY_CLOSE));
  E := Q;
  while (E <= Length(AMessage)) and (AMessage[E] >= '0')
        and (AMessage[E] <= '9') do
    Inc(E);
  AFirstLine := StrToIntDef(Copy(AMessage, Q, E - Q), 0);
  Result := (AKey <> '') and (AFirstLine > 0);
end;

class function TRdxAttrDuplicateFix.ReadLine(AMap: TRdxCodeMap;
  ALine: Integer; out AGroups: TRdxAttrGroups): string;
var
  L                : string;
  i, P, Q, E, k, N : Integer;
  Paren            : Integer;
  Inner            : string;
begin
  Result := '';
  AGroups := nil;
  if (ALine < 1) or (ALine > AMap.LineCount) or AMap.StartsInside(ALine) then
    Exit(R_DUP_MOVED);
  L := AMap.Raw(ALine);
  i := SkipBlanks(L, 1);
  if i > Length(L) then
    Exit(R_DUP_MOVED);
  N := 0;
  while i <= Length(L) do
  begin
    if (L[i] <> '[') or not AMap.IsCode(ALine, i) then
    begin
      if N = 0 then
        Exit(R_DUP_MOVED);
      Exit(R_DUP_TAIL);
    end;
    // Das erste ']' ab dem '[': der Detektor liest bis dahin.
    E := i + 1;
    while (E <= Length(L)) and (L[E] <> ']') do
      Inc(E);
    if E > Length(L) then
      Exit(R_DUP_COMPLEX);
    Inner := Copy(L, i + 1, E - i - 1);
    if (Pos('[', Inner) > 0) or (Pos('//', Inner) > 0)
       or (Pos('{', Inner) > 0) or (Pos('(*', Inner) > 0)
       or not AMap.IsCode(ALine, E) then
      Exit(R_DUP_COMPLEX);
    P := SkipBlanks(L, i + 1);
    if (P >= E) or not IsIdentStart(L[P]) or not AMap.IsCode(ALine, P) then
      Exit(R_DUP_COMPLEX);
    Q := P;
    while (Q < E) and IsIdentChar(L[Q]) do
      Inc(Q);
    // Ein Ziel ('Name:' ausserhalb von Klammern und Strings).
    Paren := 0;
    for k := Q to E - 1 do
    begin
      if not AMap.IsCode(ALine, k) then Continue;
      if L[k] = '(' then
        Inc(Paren)
      else if L[k] = ')' then
        Dec(Paren)
      else if (L[k] = ':') and (Paren = 0) then
        Exit(R_DUP_TARGET);
    end;
    SetLength(AGroups, N + 1);
    AGroups[N].Start := i;
    AGroups[N].Stop := E;
    AGroups[N].Key := LowerCase(Copy(L, P, Q - P)) + Trim(Copy(L, Q, E - Q));
    Inc(N);
    i := SkipBlanks(L, E + 1);
  end;
end;

class function TRdxAttrDuplicateFix.DeleteDuplicate(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  Key, R, L             : string;
  First, i, Cnt, Idx    : Integer;
  FirstIdx              : Integer;   // nur fuer CountKey, ungenutzt
  Groups, Other         : TRdxAttrGroups;
  FirstHas              : Boolean;
  StartCol, EndCol      : Integer;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  if not ReadMessage(AMessage, Key, First) then
  begin
    AReason := _(R_DUP_MSG);
    Exit;
  end;
  if (First > ALine) or (First < 1) then
  begin
    AReason := ReasonText(R_DUP_MOVED);
    Exit;
  end;
  R := ReadLine(AMap, ALine, Groups);
  if R <> '' then
  begin
    AReason := ReasonText(R);
    Exit;
  end;
  // Die Kette: von der Zeile des ersten Treffers bis vor die Dublette nur
  // Attributzeilen (und Leerzeilen).
  FirstHas := False;
  for i := First to ALine - 1 do
  begin
    if (Trim(AMap.Raw(i)) = '') and not AMap.StartsInside(i) then
    begin
      if i = First then
        Break;
      Continue;
    end;
    R := ReadLine(AMap, i, Other);
    // Keine Attributzeile ZWISCHEN den Treffern trennt sie; ist schon die
    // gemeldete erste Zeile keine, ist der Fund verschoben.
    if (R = R_DUP_MOVED) and (i > First) then
      R := R_DUP_BETWEEN;
    if R <> '' then
    begin
      AReason := ReasonText(R);
      Exit;
    end;
    if (i = First) and (CountKey(Other, Key, FirstIdx) > 0) then
      FirstHas := True;
  end;
  Cnt := CountKey(Groups, Key, Idx);
  if First < ALine then
  begin
    if not FirstHas or (Cnt < 1) then
    begin
      AReason := ReasonText(R_DUP_MOVED);
      Exit;
    end;
  end
  else if Cnt < 2 then
  begin
    AReason := ReasonText(R_DUP_MOVED);
    Exit;
  end;
  L := AMap.Raw(ALine);
  if Length(Groups) = 1 then
  begin
    // Allein auf der Zeile: die ganze Zeile samt Zeilenende. Sie beginnt
    // auf einem Zeichen (die Zeile ist nicht leer, SpanFits).
    if ALine >= AMap.LineCount then
    begin
      AReason := _(R_DUP_EOF);
      Exit;
    end;
    AEdit.Span := TRefactorSpan.Make(SPAN_180, ALine, 1, ALine + 1, 1);
  end
  else
  begin
    // Die Gruppe samt einem Trennzeichen: bei einer Gruppe hinter einer
    // anderen der Leerraum DAVOR (und der Rest der Zeile, wenn sie die
    // letzte ist), sonst der Leerraum DAHINTER.
    if Idx > 0 then
    begin
      StartCol := Groups[Idx - 1].Stop + 1;
      if Idx = High(Groups) then
        EndCol := Length(L) + 1
      else
        EndCol := Groups[Idx].Stop + 1;
    end
    else
    begin
      StartCol := Groups[Idx].Start;
      EndCol := Groups[Idx + 1].Start;
    end;
    AEdit.Span := TRefactorSpan.Make(SPAN_180, ALine, StartCol, ALine, EndCol);
  end;
  AEdit.Expected := RangeText(AMap, AEdit.Span);
  AEdit.NewText := '';
  Result := True;
end;

function PlanAttrDuplicate(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxAttrDuplicateFix.DeleteDuplicate);
end;

end.

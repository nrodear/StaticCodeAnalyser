unit uRdxDfmTabOrderFix;

// reDelphix - Editorhilfe SCA037 DfmTabOrderConflict: zwei oder mehr
// Geschwister-Komponenten im selben Parent teilen denselben TabOrder-Wert.
// Der Detektor (uDfmTabOrderConflict) meldet JEDE beteiligte Komponente
// als EIGENEN Fund - die Hilfe fixt deshalb nur die EINE Komponente des
// Funds: sie bekommt den kleinsten TabOrder-Wert, den keine ihrer
// Geschwister traegt. Bei einem Zwei-Komponenten-Konflikt loest das den
// ganzen Konflikt (die andere behaelt ihren Wert, der jetzt wieder
// eindeutig ist); bei mehr Geschwistern bleibt ein Rest-Konflikt fuer die
// anderen Funde stehen - ein erneuter Scan zeigt das.
//
// TEXTMODELL (reine Zeilen/Einrueckung, ohne Parser - DFM hat weder
// Pascal-Kommentare noch -Direktiven, nur Pascal-aehnliche String-Quotes):
// Delphi schreibt .dfm immer mit einer FESTEN Einrueckungsstufe pro
// Verschachtelungstiefe (der genaue Betrag zaehlt nicht, nur dass er pro
// Tiefe gleich bleibt). Eine Komponente ('object'/'inherited'/'inline
// Name: Klasse') hat ihre Eigenschaften UND Kind-Komponenten eine Stufe
// TIEFER als ihre eigene Zeile, und ihr 'end' auf DERSELBEN Tiefe wie sie
// selbst. Daraus folgt:
//   * der Elter ist die naechste Zeile RUECKWAERTS mit WENIGER Einzug als
//     der Fund-Zeile (Geschwister und ihr Inhalt haben >= Einzug);
//   * die Geschwister sind alle 'object'/'inherited'/'inline'-Zeilen
//     VORWAERTS vom Elter mit GENAU dem Einzug der Fund-Zeile, bis der
//     Einzug wieder unter diesen Wert faellt (das 'end' des Elters).
// Je Geschwister wird die eigene 'TabOrder = N'-Zeile gesucht (eine Stufe
// tiefer als das Geschwister selbst, vor dessen eigenem 'end').

interface

uses
  uRefactorInfo,   // TRefactorSpan
  uRdxBufferMath, uRdxCodeMap;

type
  TRdxDfmTabOrderFix = class
  public
    // SCA037: s. Unit-Kopf. Gesperrt, wenn ALine keine 'object'/
    // 'inherited'/'inline'-Zeile (mehr) ist (Fund veraltet), kein Elter
    // gefunden wird, die Fund-Komponente keine eigene 'TabOrder = N'-Zeile
    // (mehr) hat, oder bereits jeder Wert 0..Anzahl Geschwister belegt ist
    // (kann bei korrekten TabOrder-Werten 0..N-1 nicht vorkommen, da der
    // Fund wenigstens EINEN doppelten Wert voraussetzt - Deckel nur zur
    // Verteidigung gegen eine Endlosschleife).
    class function FixTabOrder(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils, System.StrUtils, System.Generics.Collections,
  uRdxText;        // _(), nie uLocalization (E29)

const
  SPAN_037 = 'sca037';
  MAX_SIBLINGS_SCAN = 20000;   // Verteidigung, keine fachliche Grenze

function LineIndent(const L: string): Integer;
var
  i : Integer;
begin
  i := 1;
  while (i <= Length(L)) and (L[i] = ' ') do Inc(i);
  Result := i - 1;
end;

function IsObjectOpen(const ATrimmedLow: string): Boolean;
begin
  Result := (Copy(ATrimmedLow, 1, 7) = 'object ')
    or (Copy(ATrimmedLow, 1, 10) = 'inherited ')
    or (Copy(ATrimmedLow, 1, 7) = 'inline ');
end;

// Die Zeile des Elters: rueckwaerts die erste Zeile mit WENIGER Einzug als
// AChildIndent. 0, wenn keine solche Zeile existiert oder sie keine
// Objekt-Zeile ist (DFM-Wurzel oder Struktur unerwartet).
function FindParentLine(AMap: TRdxCodeMap; AChildLine, AChildIndent: Integer): Integer;
var
  i : Integer;
  L, TL : string;
begin
  Result := 0;
  for i := AChildLine - 1 downto 1 do
  begin
    L := AMap.Raw(i);
    TL := Trim(L);
    if TL = '' then Continue;
    if LineIndent(L) < AChildIndent then
    begin
      if IsObjectOpen(LowerCase(TL)) then
        Result := i;
      Exit;
    end;
  end;
end;

// Die eigene 'TabOrder = N'-Zeile einer Komponente, die auf AOpenLine
// beginnt (Tiefe AOpenIndent): der Einzug EINE Stufe tiefer ist nicht
// bekannt (2 Leerzeichen sind ueblich, aber nicht erzwungen) - er wird aus
// der ERSTEN nicht-leeren Zeile nach AOpenLine abgeleitet (Delphi schreibt
// dort immer entweder eine eigene Eigenschaft oder die erste Kind-
// Komponente, beides schon auf dieser einen Stufe tiefer). Gesucht wird
// dann bei GENAU diesem Einzug, bis der Einzug wieder <= AOpenIndent
// faellt (das eigene 'end'). Liefert die Zeile und den aktuellen Wert;
// 0/'', wenn keine da ist oder die Komponente leer ist.
procedure FindOwnTabOrder(AMap: TRdxCodeMap; AOpenLine, AOpenIndent: Integer;
  out ATabOrderLine: Integer; out AValue: string);
var
  i, Ind, ContentIndent, EqPos : Integer;
  L, TL, TLow : string;
begin
  ATabOrderLine := 0;
  AValue := '';
  ContentIndent := -1;
  for i := AOpenLine + 1 to AMap.LineCount do
  begin
    L := AMap.Raw(i);
    TL := Trim(L);
    if TL = '' then Continue;
    Ind := LineIndent(L);
    if Ind <= AOpenIndent then Exit;   // eigenes 'end' erreicht, keine Zeile
    if ContentIndent = -1 then
      ContentIndent := Ind;           // erste Zeile setzt die Stufe
    if Ind <> ContentIndent then Continue;   // gehoert einem Enkel
    TLow := LowerCase(TL);
    if Copy(TLow, 1, 9) = 'taborder ' then
    begin
      // 'TabOrder = 3' (DFM kennt kein ';'); Wert bis Zeilenende, Trim.
      EqPos := Pos('=', TL);
      if EqPos > 0 then
      begin
        ATabOrderLine := i;
        AValue := Trim(Copy(TL, EqPos + 1, MaxInt));
        Exit;
      end;
    end;
  end;
end;

class function TRdxDfmTabOrderFix.FixTabOrder(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  ChildIndent, ParentLine : Integer;
  L, TL : string;
  Used : TDictionary<Integer, Boolean>;
  i, Ind, OwnLine, SibVal : Integer;
  SibLine, SibTabLine : Integer;
  SibValStr : string;
  NewValue : Integer;
  ValOk : Boolean;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  if (ALine < 1) or (ALine > AMap.LineCount) then
  begin
    AReason := _('line out of range');
    Exit;
  end;
  L := AMap.Raw(ALine);
  TL := Trim(L);
  if not IsObjectOpen(LowerCase(TL)) then
  begin
    AReason := _('line %d is no longer an object/inherited/inline line '
      + '(declaration moved?)', [ALine]);
    Exit;
  end;
  ChildIndent := LineIndent(L);
  ParentLine := FindParentLine(AMap, ALine, ChildIndent);
  if ParentLine = 0 then
  begin
    AReason := _('no enclosing parent component found');
    Exit;
  end;

  FindOwnTabOrder(AMap, ALine, ChildIndent, OwnLine, SibValStr);
  if OwnLine = 0 then
  begin
    AReason := _('this component no longer has its own TabOrder property');
    Exit;
  end;

  // Alle Geschwister-Werte (inkl. des eigenen - der wird gleich ersetzt,
  // schadet in der Used-Menge aber nicht) zwischen Elter und dessen 'end'.
  Used := TDictionary<Integer, Boolean>.Create;
  try
    i := ParentLine + 1;
    while i <= AMap.LineCount do
    begin
      if i - ParentLine > MAX_SIBLINGS_SCAN then
      begin
        AReason := _('parent block too large to scan safely');
        Exit;
      end;
      L := AMap.Raw(i);
      TL := Trim(L);
      if TL = '' then begin Inc(i); Continue; end;
      Ind := LineIndent(L);
      if Ind < ChildIndent then Break;   // Elter-'end' erreicht
      if (Ind = ChildIndent) and IsObjectOpen(LowerCase(TL)) then
      begin
        SibLine := i;
        FindOwnTabOrder(AMap, SibLine, ChildIndent, SibTabLine, SibValStr);
        if SibTabLine > 0 then
        begin
          ValOk := TryStrToInt(SibValStr, SibVal);
          if ValOk and (SibVal >= 0) then
            Used.AddOrSetValue(SibVal, True);
        end;
      end;
      Inc(i);
    end;

    NewValue := 0;
    while Used.ContainsKey(NewValue) do
    begin
      Inc(NewValue);
      if NewValue > MAX_SIBLINGS_SCAN then
      begin
        AReason := _('no free TabOrder value found');
        Exit;
      end;
    end;
  finally
    Used.Free;
  end;

  L := AMap.Raw(OwnLine);
  AEdit.Span := TRefactorSpan.Make(SPAN_037, OwnLine, 1, OwnLine, Length(L) + 1);
  AEdit.Expected := L;
  AEdit.NewText := Copy(L, 1, LineIndent(L)) + 'TabOrder = ' + IntToStr(NewValue);
  Result := True;
end;

end.

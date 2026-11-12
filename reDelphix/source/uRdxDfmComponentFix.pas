unit uRdxDfmComponentFix;

// reDelphix - Editorhilfe SCA184 DfmComponentUnused: eine DFM-Komponente,
// die nirgends referenziert wird, aus der .dfm loeschen - aber NUR wenn sie
// ein BLATT im Komponentenbaum ist (keine Kind-Komponenten). Ein Container
// (TPanel etc.), der selbst unbenutzt ist, aber Kinder enthaelt, die
// durchaus benutzt werden (eigener Code-Bezug, eigene Event-Bindung),
// wuerde eine simple Block-Loeschung mitreissen - das verhindert dieser
// Fix bewusst (Nico-Konzept 2026-11-12, Track B).
//
// TEXTMODELL wie TRdxDfmTabOrderFix (reine Zeilen/Einrueckung, kein
// Parser - DFM hat weder Pascal-Kommentare noch Direktiven): die
// Komponente beginnt mit 'object'/'inherited'/'inline Name: Klasse' auf
// ALine und endet mit ihrem eigenen 'end' auf GLEICHER Einzugstiefe.
// Dazwischen koennen eigene Properties, Collection-Item-Listen ('item' ..
// 'end', z.B. TListView.Columns = <item .. end item .. end>) UND
// Kind-Komponenten stehen - 'item' UND jede Kind-Komponente oeffnen mit
// einem eigenen 'end'. Die Tiefenbilanz zaehlt deshalb 'object'/
// 'inherited'/'inline'/'item' als Oeffner und jedes 'end' (auch 'end>' am
// Schluss einer Collection-Liste) als Schliesser, unabhaengig davon, wen
// es schliesst - nur die Tiefe zum EIGENEN 'end' muss stimmen. Ein
// Oeffner, der NICHT 'item' ist, zaehlt zusaetzlich als Beleg fuer "hat
// Kind-Komponenten": eine Item-Liste ist ein Property-WERT (pvkItemList,
// s. uComponentGraph), keine TComponentNode-Kindkomponente.

interface

uses
  uRdxBufferMath, uRdxCodeMap;

type
  TRdxDfmComponentFix = class
  public
    // SCA184: s. Unit-Kopf. Gesperrt, wenn ALine keine object/inherited/
    // inline-Zeile (mehr) ist oder der Name nicht mehr zum Fund passt
    // (veraltet/verschoben), kein zugehoeriges 'end' gefunden wird, die
    // Komponente Kind-Komponenten hat, oder das gefundene 'end' nicht auf
    // derselben Einzugstiefe steht (unerwartete Struktur - lieber keine
    // Hilfe als eine falsche).
    class function DeleteUnusedComponent(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRdxText;        // _(), nie uLocalization (E29)

const
  SPAN_184  = 'sca184';
  MSG_HEAD  = 'DFM component ';
  MAX_SCAN  = 200000;   // Verteidigung, keine fachliche Grenze

function LineIndent(const L: string): Integer;
var
  i : Integer;
begin
  i := 1;
  while (i <= Length(L)) and (L[i] = ' ') do Inc(i);
  Result := i - 1;
end;

// Komponentenname aus 'object'/'inherited'/'inline Name: Klasse'; '' wenn
// ATrimmed kein solcher Kopf ist.
function HeaderName(const ATrimmed: string): string;
var
  TLow : string;
  Rest : string;
  Skip, p : Integer;
begin
  Result := '';
  TLow := LowerCase(ATrimmed);
  Skip := 0;
  if Copy(TLow, 1, 7) = 'object ' then Skip := 7
  else if Copy(TLow, 1, 10) = 'inherited ' then Skip := 10
  else if Copy(TLow, 1, 7) = 'inline ' then Skip := 7;
  if Skip = 0 then Exit;
  Rest := TrimLeft(Copy(ATrimmed, Skip + 1, MaxInt));
  p := Pos(':', Rest);
  if p = 0 then Exit;
  Result := Trim(Copy(Rest, 1, p - 1));
end;

// Oeffner fuer die Tiefenbilanz: object/inherited/inline-Kopf ODER 'item'
// (Collection-Item). AIsComponent = True, wenn es KEIN 'item' ist (also
// eine echte Kind-Komponente waere, s. Unit-Kopf).
function IsOpener(const ATrimmed: string; out AIsComponent: Boolean): Boolean;
var
  TLow : string;
begin
  if SameText(ATrimmed, 'item') then
  begin
    AIsComponent := False;
    Exit(True);
  end;
  TLow := LowerCase(ATrimmed);
  AIsComponent := (Copy(TLow, 1, 7) = 'object ')
    or (Copy(TLow, 1, 10) = 'inherited ')
    or (Copy(TLow, 1, 7) = 'inline ');
  Result := AIsComponent;
end;

// Schliesser: 'end' allein oder gefolgt von einem Nicht-Bezeichner-Zeichen
// (z.B. 'end>' am Schluss einer Collection-Item-Liste).
function IsCloser(const ATrimmed: string): Boolean;
begin
  Result := (Length(ATrimmed) >= 3)
    and SameText(Copy(ATrimmed, 1, 3), 'end')
    and ((Length(ATrimmed) = 3)
         or not CharInSet(ATrimmed[4],
              ['a'..'z', 'A'..'Z', '0'..'9', '_']));
end;

// Der gemeldete Komponentenname aus 'DFM component NAME (KLASSE) is never
// referenced ...' (uDfmComponentUnused.Analyze, F.MissingVar).
function ReportedName(const AMessage: string): string;
var
  p : Integer;
begin
  Result := '';
  if Copy(AMessage, 1, Length(MSG_HEAD)) <> MSG_HEAD then Exit;
  p := Pos(' (', AMessage, Length(MSG_HEAD) + 1);
  if p <= Length(MSG_HEAD) then Exit;
  Result := Copy(AMessage, Length(MSG_HEAD) + 1, p - Length(MSG_HEAD) - 1);
end;

class function TRdxDfmComponentFix.DeleteUnusedComponent(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  L, TL, Name, Wanted : string;
  Indent, Depth, i    : Integer;
  HasChild, IsComp     : Boolean;
  EndLine              : Integer;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  Wanted := ReportedName(AMessage);
  if Wanted = '' then
  begin
    AReason := _('could not read the component name from the finding');
    Exit;
  end;
  if (ALine < 1) or (ALine > AMap.LineCount) then
  begin
    AReason := _('line %d is out of range (declaration moved?)', [ALine]);
    Exit;
  end;
  L := AMap.Raw(ALine);
  TL := Trim(L);
  Name := HeaderName(TL);
  if (Name = '') or not SameText(Name, Wanted) then
  begin
    AReason := _('line %d is no longer this component''s declaration '
      + '(moved or already changed?)', [ALine]);
    Exit;
  end;
  Indent := LineIndent(L);

  Depth := 1;
  HasChild := False;
  EndLine := 0;
  i := ALine + 1;
  while i <= AMap.LineCount do
  begin
    if i - ALine > MAX_SCAN then
    begin
      AReason := _('component block too large to scan safely');
      Exit;
    end;
    TL := Trim(AMap.Raw(i));
    if TL = '' then begin Inc(i); Continue; end;
    if IsOpener(TL, IsComp) then
    begin
      if IsComp then HasChild := True;
      Inc(Depth);
    end
    else if IsCloser(TL) then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        EndLine := i;
        Break;
      end;
    end;
    Inc(i);
  end;

  if EndLine = 0 then
  begin
    AReason := _('could not find the matching ''end'' for this component');
    Exit;
  end;
  if HasChild then
  begin
    AReason := _('component has child components - deleting it would '
      + 'remove them too');
    Exit;
  end;
  if LineIndent(AMap.Raw(EndLine)) <> Indent then
  begin
    AReason := _('unexpected indentation around the matching ''end'' - '
      + 'structure not recognised');
    Exit;
  end;

  AReason := WholeLinesEdit(AMap, ALine, EndLine, SPAN_184, AEdit);
  Result := AReason = '';
end;

end.

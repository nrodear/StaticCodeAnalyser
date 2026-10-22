unit uRdxTrailingBlanksFix;

// reDelphix - Editorhilfe fuer SCA063 TrailingWhitespace, OHNE ToolsAPI und
// ohne Parser: die Leerzeichen und Tabs am Zeilenende werden geloescht.
// Die Meldung nennt die Spalte des ersten Leerzeichens der Endfolge
// ('Trailing whitespace from column N ...'). Bedeutungsgleich im Code, in
// Zeilen- und Block-Kommentaren und in Direktiven. GRUNDSATZ wie in
// uRdxLineFixes: lieber keine Hilfe als eine falsche - der Planer prueft
// den Fund am aktuellen Text nach. Keine Hilfe, wenn der Leerraum Teil
// eines Strings ist: Inhalt eines mehrzeiligen Strings (''' ... ''', auch
// die Eroeffnungszeile) oder eines nicht geschlossenen Strings.

interface

uses
  uRdxBufferMath,      // TRdxEdit
  uRdxCodeMap;         // TRdxCodeMap

type
  // Der Planer von SCA063 (Form TRdxMapPlanner, uRdxFixRunner).
  TRdxTrailingBlanksFix = class
  public
    // Die Spalte aus der Meldung ('from column N'); 0 = nicht vorhanden.
    class function ColumnOf(const AMessage: string): Integer; static;

    // ALine endet ab der Spalte aus der Meldung nur noch auf Leerzeichen
    // und Tabs, und keines davon ist String-Inhalt: diese Endfolge wird
    // geloescht (NewText ''). Eine Zeile nur aus Leerraum wird leer.
    class function TrimEnd(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo;       // TRefactorSpan.Make

const
  SPAN_063 = 'sca063';
  KEY_FROM = 'from column ';
  R_BLANKS_MOVED = 'am Zeilenende steht kein Leerraum an der gemeldeten '
    + 'Stelle - Zeile verschoben? Datei neu pruefen';
  R_BLANKS_STRING = 'der Leerraum steht in einem mehrzeiligen oder offenen '
    + 'String - er ist Inhalt, die Hilfe loescht ihn nicht';

class function TRdxTrailingBlanksFix.ColumnOf(const AMessage: string): Integer;
var
  p, i : Integer;
begin
  Result := 0;
  p := Pos(KEY_FROM, AMessage);
  if p = 0 then Exit;
  i := p + Length(KEY_FROM);
  while (i <= Length(AMessage)) and CharInSet(AMessage[i], ['0'..'9']) do
  begin
    Result := Result * 10 + Ord(AMessage[i]) - Ord('0');
    Inc(i);
  end;
end;

class function TRdxTrailingBlanksFix.TrimEnd(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  L        : string;
  Col, i   : Integer;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  Col := ColumnOf(AMessage);
  if Col <= 0 then
  begin
    AReason := R_NO_COLUMN;
    Exit;
  end;
  L := AMap.Raw(ALine);
  // Die Endfolge muss genau bei Col beginnen (davor kein Leerraum) und bis
  // zum Zeilenende reichen.
  if (Col > Length(L)) or ((Col > 1) and IsBlank(L[Col - 1])) then
  begin
    AReason := R_BLANKS_MOVED;
    Exit;
  end;
  for i := Col to Length(L) do
    if not IsBlank(L[i]) then
    begin
      AReason := R_BLANKS_MOVED;
      Exit;
    end;
  // String-Inhalt (mehrzeilig oder nicht geschlossen) bleibt unberuehrt.
  for i := Col to Length(L) do
    if AMap.ClassAt(ALine, i) = 's' then
    begin
      AReason := R_BLANKS_STRING;
      Exit;
    end;
  AEdit.Span := TRefactorSpan.Make(SPAN_063, ALine, Col, ALine,
    Length(L) + 1);
  AEdit.Expected := Copy(L, Col, Length(L) - Col + 1);
  AEdit.NewText := '';
  Result := True;
end;

end.

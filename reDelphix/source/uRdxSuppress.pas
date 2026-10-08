unit uRdxSuppress;

// reDelphix - Unterdrueck-Hilfen (Editorhilfen Stufe 1: G1, G2, SCA165),
// OHNE ToolsAPI: aus den Zeilen der Datei wird eine gepruefte Ersetzung
// (TRdxEdit), die uRdxEditor.ReplaceSpans schreibt.
//
// MARKER-REGELN (uSuppression im Core, dort die einzige Wahrheit)
//   * '// noinspection A, B' gilt fuer die NAECHSTE nicht-leere Zeile, die
//     nicht mit '//' beginnt; gestapelte Marker werden vereinigt.
//   * '// noinspection-file A' gilt fuer die ganze Datei, egal wo er steht.
//   * Arten werden an Komma, Semikolon, Leerzeichen und Tab getrennt;
//     unbekannte Woerter (ein Grund in Klammern) stoeren nicht.
//
// Jede Ersetzung ist gegen den Text der Zeile verankert (Expected = die
// ganze Zeile bzw. der entfernte Teil): geaenderte Zeilen werden nie blind
// ueberschrieben, eine Einfuegung ist "Zeile ersetzen durch Marker + Zeile".

interface

uses
  System.SysUtils, System.Classes,
  uRefactorInfo, uRdxBufferMath;

type
  TRdxSuppress = class
  public
    // G1: '// noinspection <AKindName>' fuer die Fundzeile ALine. Ist die
    // Zeile direkt darueber schon ein reiner Zeilen-Marker, kommt die Art
    // dort hinzu; sonst eine neue Zeile mit der Einrueckung der Fundzeile.
    // False + AReason, wenn es nichts zu tun gibt oder nicht geht.
    class function LineMarker(ALines: TStrings; ALine: Integer;
      const AKindName: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // G2: '// noinspection-file <AKindName>'. Gibt es schon einen
    // Datei-Marker, kommt die Art dort hinzu; sonst eine neue Zeile hinter
    // der 'unit'/'program'/'library'/'package'-Zeile.
    class function FileMarker(ALines: TStrings; const AKindName: string;
      out AEdit: TRdxEdit; out AReason: string): Boolean; static;

    // SCA165: den wirkungslosen Marker in Zeile AMarkerLine entfernen -
    // eine reine Kommentarzeile ganz, einen Kommentar hinter Code nur
    // samt Leerraum davor.
    class function RemoveMarker(ALines: TStrings; AMarkerLine: Integer;
      out AEdit: TRdxEdit; out AReason: string): Boolean; static;

    // True, wenn AText (eine Zeile) ein reiner Zeilen- bzw. Datei-Marker
    // ist: getrimmt '//' + 'noinspection' bzw. 'noinspection-file'.
    class function IsLineMarker(const AText: string): Boolean; static;
    class function IsFileMarker(const AText: string): Boolean; static;
  end;

implementation

const
  TAG          = 'noinspection';
  TAG_FILEWIDE = 'noinspection-file';
  SEPARATORS   = [',', ';', ' ', #9];
  SPAN_ROLE    = 'suppress';

// Text hinter '//' einer reinen Kommentarzeile, sonst ''.
function CommentBody(const AText: string): string;
var
  T : string;
begin
  Result := '';
  T := TrimLeft(AText);
  if Copy(T, 1, 2) = '//' then
    Result := TrimLeft(Copy(T, 3, MaxInt));
end;

class function TRdxSuppress.IsFileMarker(const AText: string): Boolean;
begin
  Result := SameText(Copy(CommentBody(AText), 1, Length(TAG_FILEWIDE)),
    TAG_FILEWIDE);
end;

class function TRdxSuppress.IsLineMarker(const AText: string): Boolean;
begin
  Result := SameText(Copy(CommentBody(AText), 1, Length(TAG)), TAG)
    and not IsFileMarker(AText);
end;

// Steht AKindName schon in der Artenliste des Markers?
function KindListed(const AText, AKindName: string): Boolean;
var
  Body  : string;
  Word_ : string;
  i     : Integer;
begin
  Result := False;
  Body := CommentBody(AText);
  Word_ := '';
  for i := 1 to Length(Body) + 1 do
    if (i > Length(Body)) or CharInSet(Body[i], SEPARATORS) then
    begin
      if SameText(Word_, AKindName) then
        Exit(True);
      Word_ := '';
    end
    else
      Word_ := Word_ + Body[i];
end;

// Marker-Zeile mit AKindName direkt hinter dem Tag (und einem ':').
function WithKind(const AText, ATag, AKindName: string): string;
var
  p : Integer;
begin
  p := Pos(LowerCase(ATag), LowerCase(AText)) + Length(ATag);
  if (p <= Length(AText)) and (AText[p] = ':') then
    Inc(p);
  Result := Copy(AText, 1, p - 1) + ' ' + AKindName + ','
    + Copy(AText, p, MaxInt);
end;

function LeadingWhitespace(const AText: string): string;
var
  i : Integer;
begin
  i := 1;
  while (i <= Length(AText)) and CharInSet(AText[i], [' ', #9]) do
    Inc(i);
  Result := Copy(AText, 1, i - 1);
end;

// Die ganze Zeile ALine als verankerter Bereich.
function WholeLine(ALines: TStrings; ALine: Integer; const ANewText: string): TRdxEdit;
begin
  Result.Span := TRefactorSpan.Make(SPAN_ROLE, ALine, 1, ALine,
    Length(ALines[ALine - 1]) + 1);
  Result.Expected := ALines[ALine - 1];
  Result.NewText  := ANewText;
end;

class function TRdxSuppress.LineMarker(ALines: TStrings; ALine: Integer;
  const AKindName: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Code : string;
  Prev : string;
begin
  Result := False;
  AEdit  := Default(TRdxEdit);
  AReason := '';
  if (ALines = nil) or (ALine < 1) or (ALine > ALines.Count)
     or (AKindName = '') then
  begin
    AReason := 'keine Fundzeile';
    Exit;
  end;
  Code := ALines[ALine - 1];
  if Trim(Code) = '' then
  begin
    AReason := 'Fundzeile ist leer';
    Exit;
  end;
  if ALine > 1 then
  begin
    Prev := ALines[ALine - 2];
    if IsLineMarker(Prev) then
    begin
      if KindListed(Prev, AKindName) then
      begin
        AReason := 'Marker steht schon da';
        Exit;
      end;
      AEdit := WholeLine(ALines, ALine - 1, WithKind(Prev, TAG, AKindName));
      Exit(True);
    end;
  end;
  AEdit := WholeLine(ALines, ALine,
    LeadingWhitespace(Code) + '// ' + TAG + ' ' + AKindName + #10 + Code);
  Result := True;
end;

class function TRdxSuppress.FileMarker(ALines: TStrings;
  const AKindName: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  i    : Integer;
  Head : string;
  T    : string;
begin
  Result := False;
  AEdit  := Default(TRdxEdit);
  AReason := '';
  if (ALines = nil) or (ALines.Count = 0) or (AKindName = '') then
  begin
    AReason := 'keine Datei';
    Exit;
  end;
  // Ein vorhandener Datei-Marker bekommt die Art dazu.
  for i := 0 to ALines.Count - 1 do
    if IsFileMarker(ALines[i]) then
    begin
      if KindListed(ALines[i], AKindName) then
      begin
        AReason := 'Marker steht schon da';
        Exit;
      end;
      AEdit := WholeLine(ALines, i + 1, WithKind(ALines[i], TAG_FILEWIDE, AKindName));
      Exit(True);
    end;
  // Sonst hinter die Kopfzeile der Unit.
  for i := 0 to ALines.Count - 1 do
  begin
    T := LowerCase(TrimLeft(ALines[i]));
    if (Pos('unit ', T) = 1) or (Pos('program ', T) = 1)
       or (Pos('library ', T) = 1) or (Pos('package ', T) = 1) then
    begin
      Head := ALines[i];
      AEdit := WholeLine(ALines, i + 1,
        Head + #10 + '// ' + TAG_FILEWIDE + ' ' + AKindName);
      Exit(True);
    end;
  end;
  AReason := 'keine unit-Zeile gefunden';
end;

// Spalte des '//', das eine Zeile kommentiert (ausserhalb von Strings);
// 0 = keins.
function LineCommentCol(const AText: string): Integer;
var
  i     : Integer;
  InStr : Boolean;
begin
  Result := 0;
  InStr := False;
  for i := 1 to Length(AText) - 1 do
  begin
    if AText[i] = '''' then
      InStr := not InStr
    else if not InStr and (AText[i] = '/') and (AText[i + 1] = '/') then
      Exit(i);
  end;
end;

class function TRdxSuppress.RemoveMarker(ALines: TStrings; AMarkerLine: Integer;
  out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Text  : string;
  Col   : Integer;
  Start : Integer;
  Prev  : string;
begin
  Result := False;
  AEdit  := Default(TRdxEdit);
  AReason := '';
  if (ALines = nil) or (AMarkerLine < 1) or (AMarkerLine > ALines.Count) then
  begin
    AReason := 'keine Markerzeile';
    Exit;
  end;
  Text := ALines[AMarkerLine - 1];
  Col := LineCommentCol(Text);
  if (Col = 0) or (Pos(TAG, LowerCase(Copy(Text, Col, MaxInt))) = 0) then
  begin
    AReason := 'kein Marker in der Zeile';
    Exit;
  end;
  if Trim(Copy(Text, 1, Col - 1)) = '' then
  begin
    // Reine Kommentarzeile: die ganze Zeile samt Zeilenende.
    if AMarkerLine < ALines.Count then
    begin
      AEdit.Span := TRefactorSpan.Make(SPAN_ROLE, AMarkerLine, 1,
        AMarkerLine + 1, 1);
      AEdit.Expected := Text + #10;
    end
    else if (AMarkerLine > 1) and (ALines[AMarkerLine - 2] <> '') then
    begin
      // Letzte Zeile: das Zeilenende davor mitnehmen. Ein Bereich darf
      // nicht HINTER dem letzten Zeichen beginnen (SpanFits) - darum am
      // letzten Zeichen der Vorzeile verankert, das stehen bleibt.
      Prev := ALines[AMarkerLine - 2];
      AEdit.Span := TRefactorSpan.Make(SPAN_ROLE, AMarkerLine - 1,
        Length(Prev), AMarkerLine, Length(Text) + 1);
      AEdit.Expected := Prev[Length(Prev)] + #10 + Text;
      AEdit.NewText  := Prev[Length(Prev)];
      Exit(True);
    end
    else
      AEdit := WholeLine(ALines, AMarkerLine, '');
    AEdit.NewText := '';
    Exit(True);
  end;
  // Kommentar hinter Code: nur der Kommentar samt Leerraum davor.
  Start := Length(TrimRight(Copy(Text, 1, Col - 1))) + 1;
  AEdit.Span := TRefactorSpan.Make(SPAN_ROLE, AMarkerLine, Start,
    AMarkerLine, Length(Text) + 1);
  AEdit.Expected := Copy(Text, Start, MaxInt);
  AEdit.NewText  := '';
  Result := True;
end;

end.

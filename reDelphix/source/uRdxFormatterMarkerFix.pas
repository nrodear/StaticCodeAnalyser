unit uRdxFormatterMarkerFix;

// reDelphix - Editorhilfe fuer SCA206 FormatterMarker, OHNE ToolsAPI und
// ohne Parser: ein Formatter-Marker mit Leerraum ('{ (*}', '{(* }', '{*) }',
// Tab statt Blank) wird zur exakten Form '{(*}' bzw. '{*)}'. Nur ein
// Kommentar aendert sich, der Compiler sieht vorher wie nachher einen
// { }-Kommentar - bedeutungsgleich (keine Kennzeichnung). GExperts,
// CnWizards und JCF erkennen den Marker danach und lassen den Bereich
// unformatiert, wie der Autor es wollte.
//
// DER FUND (uFormatterMarker): Zeile des Markers, Meldung
//   Malformed formatter marker '<Text>' - formatters recognise only the
//   exact '<Form>' without blanks, so this marker is ignored
// mit Steuerzeichen im Text als '#9' (Pascal-Zeichenliteral). Die drei
// anderen Meldungen derselben Regel (Start ohne Ende, Ende ohne Start,
// zweiter Start im offenen Bereich) bekommen KEINE Hilfe: wohin das fehlende
// Ende gehoert oder welcher Start zu viel ist, weiss nur der Autor
// (Nico-Entscheid E8, 2026-11-06).
//
// DIE STELLE: die Zeile beginnt im Code (sonst Ablehnung); der Lauf ueber
// die Zeile folgt den Regeln des Detektors ('..' mit '', //, (* *) bis *),
// { } bis }, ''' am Zeilenende oeffnet einen Mehrzeilenstring). Kandidat ist
// ein auf der Zeile geschlossener { }-Kommentar, dessen Inhalt ohne Leerraum
// genau '(*' bzw. '*)' ist und der in der Schreibweise der Meldung genau den
// gemeldeten Text traegt. Die Code-Sicht muss das '{' als Kommentar fuehren
// (Gegenprobe zu TRdxCodeMap).
//
// GRUNDSATZ wie in uRdxLineFixes: lieber keine Hilfe als eine falsche. Keine
// Hilfe, wenn
//   - die Meldung nicht die eines falsch geschriebenen Markers ist (F1-F3),
//   - die Zeile in einem Kommentar oder String beginnt,
//   - auf der Zeile kein solcher Kommentar mit dem gemeldeten Text steht
//     (Zeile verschoben, schon korrigiert), oder er dort mehrfach steht.

interface

uses
  uRdxBufferMath,      // TRdxEdit
  uRdxCodeMap;         // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()); Deutsch und Franzoesisch in i18n/de.po und i18n/fr.po.
  R_FM_NOT_MALFORMED = 'only a marker with blanks inside can be corrected - '
    + 'where a missing {(*} or {*)} belongs, only the author knows';
  R_FM_MOVED = 'no formatter marker with this text at the reported place';
  R_FM_TWICE = 'the line holds this marker more than once';

type
  // Der Planer von SCA206 (Form TRdxMapPlanner, uRdxFixRunner).
  TRdxFormatterMarkerFix = class
  public
    // Die exakte Form aus der Meldung ('{(*}' oder '{*)}'), '' wenn die
    // Meldung nicht die eines falsch geschriebenen Markers ist.
    class function ExactOf(const AMessage: string): string; static;

    // SCA206 (F4): den gemeldeten Marker auf ALine durch die exakte Form
    // ersetzen; Spanne = der { }-Kommentar.
    class function ExactMarker(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,       // TRefactorSpan.Make
  uRdxText;            // _(): in die reDelphix-Sprache (E29), nie uLocalization

const
  SPAN_206     = 'sca206';
  MARKER_START = '{(*}';
  MARKER_END   = '{*)}';
  // Die Meldung des Detektors, in Stuecken (uFormatterMarker.MessageOf).
  MSG_HEAD     = 'Malformed formatter marker ''';
  MSG_MID      = ''' - formatters recognise only the exact ''';

// Der Markertext in der Schreibweise der Meldung: Steuerzeichen als
// '#<Ordnungszahl>' - dieselbe Regel wie uFormatterMarker.VisibleText.
function VisibleText(const AText: string): string;
var
  i : Integer;
begin
  Result := '';
  for i := 1 to Length(AText) do
    if AText[i] < ' ' then
      Result := Result + '#' + IntToStr(Ord(AText[i]))
    else
      Result := Result + AText[i];
end;

// Der gemeldete Markertext ('' ohne die Form der Meldung).
function ReportedText(const AMessage: string): string;
var
  p : Integer;
begin
  Result := '';
  if Copy(AMessage, 1, Length(MSG_HEAD)) <> MSG_HEAD then Exit;
  p := Pos(MSG_MID, AMessage);
  if p <= Length(MSG_HEAD) then Exit;
  Result := Copy(AMessage, Length(MSG_HEAD) + 1, p - Length(MSG_HEAD) - 1);
end;

// Ist AText ein falsch geschriebener Marker der Form AExact? Inhalt ohne
// Leerraum (Zeichen <= #32) genau '(*' bzw. '*)', aber nicht exakt.
function IsMalformedOf(const AText, AExact: string): Boolean;
begin
  Result := (AText <> AExact) and (Length(AText) >= 2)
    and (Trim(Copy(AText, 2, Length(AText) - 2))
         = Copy(AExact, 2, Length(AExact) - 2));
end;

// Spalten der { }-Kommentare auf ALine, die im Code beginnen und auf der
// Zeile schliessen (Zeilenanfang im Code). Dieselben Regeln wie der
// Detektor: '..' mit '' als Apostroph, (* *) bis zum ersten *); //, ein
// Mehrzeilenstring (Apostroph-Folge am Zeilenende) und ein Kommentar, der
// in die naechste Zeile laeuft, beenden den Lauf.
function BraceColumns(const ALine: string): TArray<Integer>;
var
  j, p, n, Count : Integer;
  InStr          : Boolean;
begin
  SetLength(Result, 0);
  Count := 0;
  InStr := False;
  n := Length(ALine);
  j := 1;
  while j <= n do
  begin
    if InStr then
    begin
      if (ALine[j] = '''') and (QuoteRun(ALine, j) >= 2) then
        Inc(j, 2)                      // '' im String
      else
      begin
        InStr := ALine[j] <> '''';
        Inc(j);
      end;
      Continue;
    end;
    if ALine[j] = '''' then
    begin
      p := QuoteRun(ALine, j);
      if (p >= MIN_MULTI_QUOTES) and Odd(p)
         and (Trim(Copy(ALine, j + p, MaxInt)) = '') then
        Exit;                          // Mehrzeilenstring: Rest ist String
      InStr := True;
      Inc(j);
    end
    else if (ALine[j] = '/') and (j < n) and (ALine[j + 1] = '/') then
      Exit
    else if (ALine[j] = '(') and (j < n) and (ALine[j + 1] = '*') then
    begin
      p := Pos('*)', ALine, j + 2);
      if p = 0 then Exit;
      j := p + 2;
    end
    else if ALine[j] = '{' then
    begin
      p := Pos('}', ALine, j + 1);
      if p = 0 then Exit;
      Inc(Count);
      SetLength(Result, Count);
      Result[Count - 1] := j;
      j := p + 1;
    end
    else
      Inc(j);
  end;
end;

{ TRdxFormatterMarkerFix }

class function TRdxFormatterMarkerFix.ExactOf(const AMessage: string): string;
var
  p : Integer;
begin
  Result := '';
  if ReportedText(AMessage) = '' then Exit;
  p := Pos(MSG_MID, AMessage) + Length(MSG_MID);
  if Copy(AMessage, p, Length(MARKER_START) + 1) = MARKER_START + '''' then
    Result := MARKER_START
  else if Copy(AMessage, p, Length(MARKER_END) + 1) = MARKER_END + '''' then
    Result := MARKER_END;
end;

class function TRdxFormatterMarkerFix.ExactMarker(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  Exact, Shown, L, T, Tok : string;
  Cols                    : TArray<Integer>;
  Hits, i, Col            : Integer;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  Exact := ExactOf(AMessage);
  if Exact = '' then
  begin
    AReason := _(R_FM_NOT_MALFORMED);
    Exit;
  end;
  if (ALine < 1) or (ALine > AMap.LineCount) then
  begin
    AReason := MsgMovedSuffix(_(R_FM_MOVED));
    Exit;
  end;
  if AMap.StartsInside(ALine) then
  begin
    AReason := MsgLineStartsInCommentOrString;
    Exit;
  end;
  L := AMap.Raw(ALine);
  Shown := ReportedText(AMessage);
  // Kandidat: ein falsch geschriebener Marker der gemeldeten Form, dessen
  // Schreibweise in der Meldung ('#9' fuer Tab) der gemeldete Text ist.
  Hits := 0;
  Col := 0;
  Tok := '';
  Cols := BraceColumns(L);
  for i := 0 to High(Cols) do
  begin
    T := Copy(L, Cols[i], Pos('}', L, Cols[i] + 1) - Cols[i] + 1);
    if (VisibleText(T) = Shown) and IsMalformedOf(T, Exact) then
    begin
      Inc(Hits);
      if Hits = 1 then
      begin
        Col := Cols[i];
        Tok := T;
      end;
    end;
  end;
  // Gegenprobe zur Code-Sicht: das '{' ist dort Kommentar.
  if (Hits = 0) or (AMap.ClassAt(ALine, Col) <> 'k') then
  begin
    AReason := MsgMovedSuffix(_(R_FM_MOVED));
    Exit;
  end;
  if Hits > 1 then
  begin
    AReason := _(R_FM_TWICE);
    Exit;
  end;
  AEdit.Span := TRefactorSpan.Make(SPAN_206, ALine, Col, ALine,
    Col + Length(Tok));
  AEdit.Expected := Tok;
  AEdit.NewText := Exact;
  Result := True;
end;

end.

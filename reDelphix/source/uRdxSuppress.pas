unit uRdxSuppress;

// reDelphix - Unterdrueck-Hilfen (Editorhilfen Stufe 1: G1, G2, SCA165),
// OHNE ToolsAPI: aus den Zeilen der Datei wird eine gepruefte Ersetzung
// (TRdxEdit), die uRdxEditor.ReplaceSpans schreibt.
//
// MARKER-REGELN (uSuppression im Core, dort die einzige Wahrheit; der Core
// legt seine Grammatik nicht offen, darum steht sie hier nachgebaut)
//   * '// noinspection A, B' gilt fuer ZWEI Ziele: die naechste nicht-leere
//     Zeile (auch eine Kommentarzeile, etwa ein TODO) und die naechste
//     Code-Zeile. Gestapelte Marker werden vereinigt.
//   * '// noinspection-file A' gilt fuer die ganze Datei, egal wo er steht;
//     mehrere Datei-Marker werden ebenfalls vereinigt.
//   * Arten werden an Komma, Semikolon, Leerzeichen und Tab getrennt;
//     unbekannte Woerter (ein Grund in Klammern) stoeren nicht.
//   * 'All' bzw. '*' wirkt NUR als ganze Artenliste ('// noinspection All');
//     'X, All' ist die Art X und ein unbekanntes Wort. Ein solcher Marker
//     wird darum nie erweitert, sondern bekommt einen eigenen daneben.
//
// Jede Ersetzung ist gegen den Text der Zeile verankert (Expected = die
// ganze Zeile bzw. der entfernte Teil): geaenderte Zeilen werden nie blind
// ueberschrieben, eine Einfuegung ist "Zeile ersetzen durch Marker + Zeile".
// Wo eingefuegt bzw. erweitert wird, entscheidet die Code-Sicht
// (uRdxCodeMap): nie in einem Block-Kommentar oder mehrzeiligen String.

interface

uses
  System.Classes,   // TStrings
  uRdxBufferMath;   // TRdxEdit

type
  TRdxSuppress = class
  public
    // G1: '// noinspection <AKindName>' fuer die Fundzeile ALine. Ist die
    // Zeile direkt darueber schon ein reiner Zeilen-Marker (nicht 'All'),
    // kommt die Art dort hinzu; sonst eine neue Zeile mit der Einrueckung
    // der Fundzeile. False + AReason, wenn es nichts zu tun gibt oder nicht
    // geht - auch, wenn die Fundzeile in einem Block-Kommentar oder
    // mehrzeiligen String liegt (dort wirkte der Marker nicht bzw. wuerde
    // Teil des Strings).
    class function LineMarker(ALines: TStrings; ALine: Integer;
      const AKindName: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // G2: '// noinspection-file <AKindName>'. Gibt es schon einen
    // Datei-Marker (nicht 'All'), kommt die Art dort hinzu; sonst eine neue
    // Zeile hinter der Kopfanweisung 'unit'/'program'/'library'/'package'
    // (das erste Code-Token der Datei, bis zu ihrem ';').
    class function FileMarker(ALines: TStrings; const AKindName: string;
      out AEdit: TRdxEdit; out AReason: string): Boolean; static;

    // SCA165: den wirkungslosen Marker in Zeile AMarkerLine entfernen -
    // eine reine Kommentarzeile ganz, einen Kommentar hinter Code nur
    // samt Leerraum davor. NUR, wenn der Marker genau EINE Art nennt: der
    // Core meldet einen Marker schon dann, wenn nur seine Arten im
    // aktiven Scan-Profil nichts unterdrueckt haben - die uebrigen Arten
    // (oder 'All') koennen unter dem vollen Profil noch wirken.
    class function RemoveMarker(ALines: TStrings; AMarkerLine: Integer;
      out AEdit: TRdxEdit; out AReason: string): Boolean; static;

    // True, wenn AText (eine Zeile) ein reiner Zeilen- bzw. Datei-Marker
    // ist: getrimmt '//' + 'noinspection' bzw. 'noinspection-file'.
    class function IsLineMarker(const AText: string): Boolean; static;
    class function IsFileMarker(const AText: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,   // TRefactorSpan.Make
  uRdxCodeMap;     // TRdxCodeMap, NextToken: Code-Sicht mit Block-Kommentaren

const
  TAG          = 'noinspection';
  TAG_FILEWIDE = 'noinspection-file';
  SEPARATORS   = [',', ';', ' ', #9];
  SPAN_ROLE    = 'suppress';

  R_IN_COMMENT = 'Fundzeile liegt in einem Block-Kommentar oder mehrzeiligen '
    + 'String - ein Marker wirkte dort nicht bzw. wuerde Teil des Strings';
  R_WILDCARD   = 'Marker gilt fuer alle Arten (All) - wirkungslos vielleicht '
    + 'nur unter dem aktuellen Scan-Profil, bitte von Hand pruefen';
  R_MULTI_KIND = 'Marker nennt mehrere Arten - wirkungslos vielleicht nur '
    + 'unter dem aktuellen Scan-Profil, bitte von Hand pruefen';
  R_NO_KIND    = 'Marker nennt keine erkennbare Art';

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

// Artenliste eines Kommentartexts (Text hinter '//'): alles hinter
// 'noinspection[-file]' und einem optionalen ':', getrimmt. '' ohne Tag.
function KindList(const ACommentText: string): string;
var
  T : string;
begin
  Result := '';
  T := TrimLeft(ACommentText);
  if SameText(Copy(T, 1, Length(TAG_FILEWIDE)), TAG_FILEWIDE) then
    T := Copy(T, Length(TAG_FILEWIDE) + 1, MaxInt)
  else if SameText(Copy(T, 1, Length(TAG)), TAG) then
    T := Copy(T, Length(TAG) + 1, MaxInt)
  else
    Exit;
  if Copy(T, 1, 1) = ':' then
    T := Copy(T, 2, MaxInt);
  Result := Trim(T);
end;

// 'All' bzw. '*' als GANZE Artenliste - wie TSuppression.ParseCommentText.
function IsWildcard(const ACommentText: string): Boolean;
var
  K : string;
begin
  K := KindList(ACommentText);
  Result := SameText(K, 'all') or (K = '*');
end;

// Das naechste Wort der Artenliste ab AFrom, getrennt an SEPARATORS wie der
// Core; AFrom rueckt dahinter. '' am Ende. Bis Charge R8 je eine Zeichen-
// Schleife in KindCount und KindListed.
function NextKindWord(const AList: string; var AFrom: Integer): string;
var
  Start : Integer;
begin
  while (AFrom <= Length(AList)) and CharInSet(AList[AFrom], SEPARATORS) do
    Inc(AFrom);
  Start := AFrom;
  while (AFrom <= Length(AList)) and not CharInSet(AList[AFrom], SEPARATORS) do
    Inc(AFrom);
  Result := Copy(AList, Start, AFrom - Start);
end;

// Ein reiner Bezeichner: Anfangszeichen, dann nur Bezeichnerzeichen.
function IsIdentWord(const AWord: string): Boolean;
var
  k : Integer;
begin
  Result := (AWord <> '') and IsIdentStart(AWord[1]);
  for k := 2 to Length(AWord) do
    if not IsIdentChar(AWord[k]) then
      Exit(False);
end;

// Zahl der Arten, die der Marker nennt: die fuehrenden Woerter der Liste,
// die reine Bezeichner sind. Das erste andere Wort ('(Grund', '-', 'bis
// Q3:') beendet die Liste - so zaehlt '// noinspection X (Grund)' eine Art.
// Ein Grund ohne Klammern ('X wegen Altlast') zaehlt mit; das ist die
// vorsichtige Seite, der Aufrufer lehnt dann ab.
function KindCount(const ACommentText: string): Integer;
var
  List, W : string;
  i       : Integer;
begin
  Result := 0;
  List := KindList(ACommentText);
  i := 1;
  W := NextKindWord(List, i);
  while W <> '' do
  begin
    if not IsIdentWord(W) then Exit;
    Inc(Result);
    W := NextKindWord(List, i);
  end;
end;

// Steht AKindName schon in der Artenliste des Markers? Die Liste wie
// KindList (hinter dem Tag und seinem ':' - sonst hielte '// noinspection:A'
// das 'noinspection:A' fuer ein Wort und A fuer nicht genannt; Review
// Quick-Fix-Units 2026-10-14), getrennt an SEPARATORS wie der Core.
function KindListed(const AText, AKindName: string): Boolean;
var
  List, W : string;
  i       : Integer;
begin
  Result := False;
  List := KindList(CommentBody(AText));
  i := 1;
  W := NextKindWord(List, i);
  while W <> '' do
  begin
    if SameText(W, AKindName) then
      Exit(True);
    W := NextKindWord(List, i);
  end;
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

// Ist ALine eine reine Kommentarzeile, deren '//' wirklich ein Kommentar
// ist - nicht Text in einem Block-Kommentar oder mehrzeiligen String?
function IsPureCommentLine(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  Col : Integer;
begin
  Col := AMap.LineCommentCol(ALine);
  Result := not AMap.StartsInside(ALine) and (Col > 0)
    and (Col = SkipBlanks(AMap.Raw(ALine), 1));
end;

// Ein Marker, den man um eine Art erweitern darf: echte Kommentarzeile,
// nicht 'All'.
function IsExtensibleMarker(AMap: TRdxCodeMap; ALine: Integer): Boolean;
begin
  Result := IsPureCommentLine(AMap, ALine)
    and not IsWildcard(CommentBody(AMap.Raw(ALine)));
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
  Map  : TRdxCodeMap;
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
  Map := TRdxCodeMap.Create(ALines);
  try
    // Zeilen-Detektoren (TodoComment, TooLongLine) melden auch Zeilen IN
    // einem '{ ... }' oder ''' ... '''. Eine Zeile davor laege ebenfalls
    // darin: im Kommentar ohne Wirkung, im String als neuer Inhalt.
    if Map.StartsInside(ALine) then
    begin
      AReason := R_IN_COMMENT;
      Exit;
    end;
    if (ALine > 1) and TRdxSuppress.IsLineMarker(ALines[ALine - 2])
       and IsExtensibleMarker(Map, ALine - 1) then
    begin
      Prev := ALines[ALine - 2];
      if KindListed(Prev, AKindName) then
      begin
        AReason := 'Marker steht schon da';
        Exit;
      end;
      AEdit := WholeLine(ALines, ALine - 1, WithKind(Prev, TAG, AKindName));
      Exit(True);
    end;
  finally
    Map.Free;
  end;
  // Eigene Zeile direkt ueber der Fundzeile; ueber einem 'All'-Marker
  // darueber ist das ein gestapelter Marker, den der Core vereinigt.
  AEdit := WholeLine(ALines, ALine,
    LeadingWhitespace(Code) + '// ' + TAG + ' ' + AKindName + #10 + Code);
  Result := True;
end;

// Die Zeile des ';' der Kopfanweisung unit/program/library/package - das
// erste Code-Token der Datei; ein 'Unit Name: X' oder 'Library General
// Public License' im Lizenzkopf davor ist Kommentar und zaehlt nicht. ''
// oder der Grund (auch, wenn hinter dem ';' ein Block-Kommentar beginnt:
// die neue Zeile laege darin).
function HeadLineReason(AMap: TRdxCodeMap; out AHead: Integer): string;
var
  Tok : TRdxToken;
begin
  Result := '';
  AHead := 0;
  Tok := NextToken(AMap, 1, 1);
  if (Tok.Low <> 'unit') and (Tok.Low <> 'program')
     and (Tok.Low <> 'library') and (Tok.Low <> 'package') then
    Exit('keine unit-Zeile gefunden');
  repeat
    Tok := After(AMap, Tok);
  until (Tok.Low = ';') or (Tok.Low = '');
  if Tok.Low = '' then
    Exit('keine unit-Zeile gefunden');
  AHead := Tok.Line;
  if AMap.StartsInside(AHead + 1) then
    Result := 'hinter der unit-Zeile beginnt ein Block-Kommentar';
end;

class function TRdxSuppress.FileMarker(ALines: TStrings;
  const AKindName: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Map  : TRdxCodeMap;
  i    : Integer;
  Head : Integer;
begin
  Result := False;
  AEdit  := Default(TRdxEdit);
  AReason := '';
  if (ALines = nil) or (ALines.Count = 0) or (AKindName = '') then
  begin
    AReason := 'keine Datei';
    Exit;
  end;
  Map := TRdxCodeMap.Create(ALines);
  try
    // Ein vorhandener Datei-Marker bekommt die Art dazu - nur ein echter
    // (kein Text in einem Kommentar) und keiner mit 'All'.
    for i := 1 to ALines.Count do
      if TRdxSuppress.IsFileMarker(ALines[i - 1])
         and IsExtensibleMarker(Map, i) then
      begin
        if KindListed(ALines[i - 1], AKindName) then
        begin
          AReason := 'Marker steht schon da';
          Exit;
        end;
        AEdit := WholeLine(ALines, i, WithKind(ALines[i - 1], TAG_FILEWIDE, AKindName));
        Exit(True);
      end;
    // Sonst hinter die Kopfanweisung.
    AReason := HeadLineReason(Map, Head);
  finally
    Map.Free;
  end;
  if AReason <> '' then Exit;
  AEdit := WholeLine(ALines, Head,
    ALines[Head - 1] + #10 + '// ' + TAG_FILEWIDE + ' ' + AKindName);
  Result := True;
end;

// Spalte des '//', das die Zeile ALine kommentiert; 0 = keins. Ueber die
// Code-Sicht der GANZEN Datei: ein '//' in einem String, in '{...}' oder
// '(*...*)' - auch einem, der Zeilen frueher beginnt - zaehlt nicht. Ein
// zeilenweiser Scan schnitte sonst aus 'x; { a // b } // noinspection X'
// ab dem inneren '//' heraus und liesse ein offenes '{' stehen.
function LineCommentCol(ALines: TStrings; ALine: Integer): Integer;
var
  Map : TRdxCodeMap;
begin
  Map := TRdxCodeMap.Create(ALines);
  try
    Result := Map.LineCommentCol(ALine);
  finally
    Map.Free;
  end;
end;

// Nur ein Marker mit genau einer Art ist sicher wirkungslos: SCA165 kommt
// auch, wenn nur die im Scan-Profil aktiven Arten eines Mehrarten-Markers
// nichts unterdrueckt haben. AKinds = der Kommentartext hinter '//'. ''
// oder der Grund.
function KindsReason(const AKinds: string): string;
begin
  Result := '';
  if IsWildcard(AKinds) then
    Exit(R_WILDCARD);
  case KindCount(AKinds) of
    0: Result := R_NO_KIND;
    1: ;
  else
    Result := R_MULTI_KIND;
  end;
end;

// Eine reine Kommentarzeile AMarkerLine (Text AText) ganz entfernen, samt
// Zeilenende. Letzte Zeile: das Zeilenende DAVOR mitnehmen - ein Bereich
// darf nicht HINTER dem letzten Zeichen beginnen (SpanFits), darum am
// letzten Zeichen der Vorzeile verankert, das stehen bleibt.
function WholeLineRemoval(ALines: TStrings; AMarkerLine: Integer;
  const AText: string): TRdxEdit;
var
  Prev : string;
begin
  Result := Default(TRdxEdit);
  if AMarkerLine < ALines.Count then
  begin
    Result.Span := TRefactorSpan.Make(SPAN_ROLE, AMarkerLine, 1,
      AMarkerLine + 1, 1);
    Result.Expected := AText + #10;
  end
  else if (AMarkerLine > 1) and (ALines[AMarkerLine - 2] <> '') then
  begin
    Prev := ALines[AMarkerLine - 2];
    Result.Span := TRefactorSpan.Make(SPAN_ROLE, AMarkerLine - 1,
      Length(Prev), AMarkerLine, Length(AText) + 1);
    Result.Expected := Prev[Length(Prev)] + #10 + AText;
    Result.NewText  := Prev[Length(Prev)];
  end
  else
    Result := WholeLine(ALines, AMarkerLine, '');
end;

class function TRdxSuppress.RemoveMarker(ALines: TStrings; AMarkerLine: Integer;
  out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Text  : string;
  Col   : Integer;
  Start : Integer;
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
  Col := LineCommentCol(ALines, AMarkerLine);
  if (Col = 0) or (Pos(TAG, LowerCase(Copy(Text, Col, MaxInt))) = 0) then
  begin
    AReason := 'kein Marker in der Zeile';
    Exit;
  end;
  AReason := KindsReason(Copy(Text, Col + 2, MaxInt));
  if AReason <> '' then Exit;
  if Trim(Copy(Text, 1, Col - 1)) = '' then
  begin
    // Reine Kommentarzeile: die ganze Zeile samt Zeilenende.
    AEdit := WholeLineRemoval(ALines, AMarkerLine, Text);
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

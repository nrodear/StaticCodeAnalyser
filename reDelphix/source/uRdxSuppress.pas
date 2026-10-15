unit uRdxSuppress;

// reDelphix - Unterdrueck-Hilfen (Editorhilfen Stufe 1: G1, G2, SCA165),
// OHNE ToolsAPI: aus den Zeilen der Datei wird eine gepruefte Ersetzung
// (TRdxEdit), die uRdxEditor.ReplaceSpans schreibt.
//
// MARKER-REGELN (uSuppression im Core, dort die einzige Wahrheit; der Core
// legt seine Grammatik nicht offen, darum steht sie hier nachgebaut)
//   * '// noinspection A, B' gilt fuer ZWEI Ziele: die naechste nicht-leere
//     Zeile (auch eine Kommentarzeile, etwa ein TODO) und die naechste
//     Code-Zeile; Leerzeilen zaehlen nicht (BuildMap). Kommentarzeile heisst
//     dabei NUR eine Zeile, die ohne Leerraum davor mit '//' beginnt - eine
//     Zeile mit '{' oder '(*' ist fuer den Core Code (IsCommentOnlyLine).
//   * Gestapelte Marker vereinigt der Core nur fuer das CODE-Ziel. Eine
//     Kommentarzeile erreicht allein der Marker, fuer den sie die naechste
//     nicht-leere Zeile ist; fuer einen Marker weiter oben ist das schon
//     die Markerzeile darunter (Review R1, Fixture f5). Darum erweitert
//     LineMarker auf einer Kommentarzeile den Marker darueber auch ueber
//     Leerzeilen hinweg, statt eine Zeile dazwischen zu schieben (R1-03).
//   * SCA165 (UnusedSuppression) prueft nur das Code-Ziel (BuildMarkers):
//     ein Marker, der auf seiner Kommentarzeile wirkt, gilt dem Core als
//     wirkungslos. RemoveMarker lehnt deshalb jeden Marker ab, dessen
//     naechste nicht-leere Zeile eine Kommentarzeile vor dem Code ist -
//     sonst entfernte die Hilfe einen Marker, den "Hier unterdruecken"
//     eben gesetzt hat, und der Fund kaeme zurueck (Review R1-01). Den
//     Fehlalarm selbst behebt erst der Core.
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
    // der Fundzeile. Ist die Fundzeile eine Kommentarzeile ('//'), gilt das
    // auch ueber Leerzeilen hinweg, und ein Marker dort, der sich nicht
    // erweitern laesst ('All', Marker hinter Code), sperrt: eine neue Zeile
    // dazwischen naehme ihm sein Kommentar-Ziel (s. Kopf, Review R1-03).
    // False + AReason, wenn es nichts zu tun gibt oder nicht geht - auch,
    // wenn die Fundzeile in einem Block-Kommentar oder mehrzeiligen String
    // liegt (dort wirkte der Marker nicht bzw. wuerde Teil des Strings).
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
    // (oder 'All') koennen unter dem vollen Profil noch wirken. Und nur,
    // wenn vor seiner Code-Zeile keine Kommentarzeile sein Ziel ist: dort
    // wirkt er vielleicht, und SCA165 sieht das nicht (s. Kopf, R1-01).
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
  // Review R1-01 (s. Kopf): SCA165 prueft nur das Code-Ziel.
  R_COMMENT_TARGET = 'Marker zielt auch auf die Kommentarzeile %d und wirkt '
    + 'dort vielleicht - SCA165 prueft nur die Code-Zeile; bitte von Hand '
    + 'pruefen';
  // Review R1-03 (s. Kopf): der Marker darueber traegt die Kommentarzeile.
  R_SPLITS_TARGET = 'Marker in Zeile %d gilt fuer diese Kommentarzeile und '
    + 'laesst sich nicht erweitern (All oder hinter Code) - eine neue Zeile '
    + 'dazwischen naehme ihm das Ziel; bitte von Hand ergaenzen';

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

// Beginnt ein Kommentartext (hinter '//') mit dem Datei-Tag?
function IsFileWideComment(const ACommentText: string): Boolean;
begin
  Result := SameText(Copy(TrimLeft(ACommentText), 1, Length(TAG_FILEWIDE)),
    TAG_FILEWIDE);
end;

class function TRdxSuppress.IsFileMarker(const AText: string): Boolean;
begin
  Result := IsFileWideComment(CommentBody(AText));
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

// Ein reiner Zeilen-Marker in ALine, den man erweitern darf; False fuer
// ALine < 1.
function IsExtensibleLineMarker(AMap: TRdxCodeMap; ALine: Integer): Boolean;
begin
  Result := (ALine >= 1) and TRdxSuppress.IsLineMarker(AMap.Raw(ALine))
    and IsExtensibleMarker(AMap, ALine);
end;

// Traegt ALine einen Zeilen-Marker, wie der Core ihn liest - einen echten
// '//'-Kommentar (auch hinter Code) mit dem Tag, keinen Datei-Marker? Ein
// Marker im Block-Kommentar oder String zaehlt nicht (ParseMarkerLine).
function HasLineMarker(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  Col  : Integer;
  Body : string;
begin
  Result := False;
  if ALine < 1 then Exit;
  Col := AMap.LineCommentCol(ALine);
  if Col = 0 then Exit;
  Body := TrimLeft(Copy(AMap.Raw(ALine), Col + 2, MaxInt));
  Result := SameText(Copy(Body, 1, Length(TAG)), TAG)
    and not IsFileWideComment(Body);
end;

// Kommentarzeile nach der Regel des Cores (uSuppression.IsCommentOnlyLine):
// ohne Leerraum davor beginnt die Zeile mit '//'. Bewusst NUR diese Regel -
// eine Zeile mit '{' oder '(*' ist fuer den Core Code (Gegenpruefung R1:
// dort verbraucht der Core den Marker).
function IsCoreCommentLine(const AText: string): Boolean;
begin
  Result := Copy(TrimLeft(AText), 1, 2) = '//';
end;

// Die Ziele eines Zeilen-Markers in AMarkerLine, wie der Core sie bildet
// (uSuppression.BuildMap): die naechste nicht-leere Zeile und die naechste
// Code-Zeile, Leerzeilen zaehlen nicht; 0 = keine.
procedure MarkerTargets(ALines: TStrings; AMarkerLine: Integer;
  out ANextNonEmpty, ANextCode: Integer);
var
  j : Integer;
begin
  ANextNonEmpty := 0;
  ANextCode     := 0;
  for j := AMarkerLine + 1 to ALines.Count do
  begin
    if TrimLeft(ALines[j - 1]) = '' then Continue;
    if ANextNonEmpty = 0 then
      ANextNonEmpty := j;
    if not IsCoreCommentLine(ALines[j - 1]) then
    begin
      ANextCode := j;
      Exit;
    end;
  end;
end;

// Die Zeile, deren Marker die Fundzeile ALine traegt: bei einer Code-Zeile
// die Zeile direkt darueber (gestapelte Marker vereinigt der Core dort),
// bei einer Kommentarzeile die naechste nicht-leere Zeile darueber - nur
// fuer deren Marker ist ALine die naechste nicht-leere Zeile (s. Kopf).
// 0 = keine.
function MarkerSlotAbove(ALines: TStrings; ALine: Integer): Integer;
begin
  Result := ALine - 1;
  if IsCoreCommentLine(ALines[ALine - 1]) then
    while (Result >= 1) and (TrimLeft(ALines[Result - 1]) = '') do
      Dec(Result);
end;

// Die ganze Zeile ALine als verankerter Bereich.
function WholeLine(ALines: TStrings; ALine: Integer; const ANewText: string): TRdxEdit;
begin
  Result.Span := TRefactorSpan.Make(SPAN_ROLE, ALine, 1, ALine,
    Length(ALines[ALine - 1]) + 1);
  Result.Expected := ALines[ALine - 1];
  Result.NewText  := ANewText;
end;

// AKindName in den Zeilen-Marker der Zeile ALine - False mit Grund, wenn
// die Art dort schon steht.
function ExtendMarker(ALines: TStrings; ALine: Integer; const AKindName: string;
  out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Prev : string;
begin
  AEdit   := Default(TRdxEdit);
  AReason := '';
  Prev    := ALines[ALine - 1];
  Result  := not KindListed(Prev, AKindName);
  if Result then
    AEdit := WholeLine(ALines, ALine, WithKind(Prev, TAG, AKindName))
  else
    AReason := 'Marker steht schon da';
end;

class function TRdxSuppress.LineMarker(ALines: TStrings; ALine: Integer;
  const AKindName: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Map   : TRdxCodeMap;
  Code  : string;
  Above : Integer;
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
    Above := MarkerSlotAbove(ALines, ALine);
    if IsExtensibleLineMarker(Map, Above) then
      Exit(ExtendMarker(ALines, Above, AKindName, AEdit, AReason));
    // Ein anderer Marker traegt die Kommentarzeile ('All', hinter Code):
    // eine neue Zeile dazwischen naehme ihm das Ziel (Review R1-03).
    if IsCoreCommentLine(Code) and HasLineMarker(Map, Above) then
    begin
      AReason := Format(R_SPLITS_TARGET, [Above]);
      Exit;
    end;
  finally
    Map.Free;
  end;
  // Eigene Zeile direkt ueber der Fundzeile; ueber einer Code-Zeile mit
  // 'All'-Marker darueber ist das ein gestapelter Marker, den der Core
  // vereinigt.
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

// Ein Zeilen-Marker in AMarkerLine (Kommentartext ACommentText hinter
// '//'), dessen naechste nicht-leere Zeile eine Kommentarzeile vor dem
// Code ist, wirkt dort vielleicht - SCA165 prueft nur das Code-Ziel (s.
// Kopf, Review R1-01). Ein Datei-Marker hat kein Zeilenziel. '' oder der
// Grund.
function CommentTargetReason(ALines: TStrings; AMarkerLine: Integer;
  const ACommentText: string): string;
var
  NextNonEmpty : Integer;
  NextCode     : Integer;
begin
  Result := '';
  if IsFileWideComment(ACommentText) then Exit;
  MarkerTargets(ALines, AMarkerLine, NextNonEmpty, NextCode);
  if (NextNonEmpty > 0) and (NextNonEmpty <> NextCode) then
    Result := Format(R_COMMENT_TARGET, [NextNonEmpty]);
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
  if AReason = '' then
    AReason := CommentTargetReason(ALines, AMarkerLine,
      Copy(Text, Col + 2, MaxInt));
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

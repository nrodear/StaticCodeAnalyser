unit uRdxCharEscapeFix;

// reDelphix - Editorhilfen fuer die Trojan-Source-Familie, OHNE ToolsAPI
// und ohne Parser:
//   SCA188 SourceBidiOverride - Bidi-Steuerzeichen (BidiOverride),
//   SCA192 SourceInvisibleChar - unsichtbare Zeichen (InvisibleChar).
// Beide teilen dieselbe Umformung der gemeldeten Zeile:
//   * im KOMMENTAR wird das Zeichen geloescht - Kommentare verwirft der
//     Compiler, das Programm bleibt dasselbe; die Zeile zeigt danach, was
//     der Compiler liest;
//   * im STRING-Literal wird es als Zeichen-Code geschrieben und das
//     Literal an der Stelle aufgebrochen: 'abc<U+202E>def' ->
//     'abc'#$202E'def' (Delphi-Form ohne '+': aneinandergereihte Literale
//     und Zeichen-Codes sind EIN Zeichen-String, auch in Konstanten,
//     case-Marken und Attributen). Gleicher Wert, gleicher Typ - ein
//     Literal nur aus dem Zeichen wird #$202E (beides Char-Konstanten).
// Nie geloescht wird im String: U+200D (ZWJ) gehoert dort oft zu einer
// Emoji-Folge, und auch ein ZWSP ist Teil des Werts.
//
// DETEKTOR (uSourceEncoding, S1/S2 ueber uFileTextCache.ComputeFileEncoding-
// Info, Rohbytes der Datei): JE DATEI EIN Fund je Regel, auf der Zeile des
// ERSTEN Zeichens (Zeilen zaehlt der Detektor an LF, 1-basiert), ohne
// Spalte; die Meldung nennt das Zeichen nicht. Kommentare und Strings zaehlen
// fuer ihn mit (datei-global). Die Hilfe behandelt darum ALLE Zeichen der
// gemeldeten Zeile in EINER Ersetzung; danach meldet der Detektor die
// naechste Zeile. Zeichenmengen genau wie im Detektor:
//   SCA188: U+061C, U+202A..U+202E, U+2066..U+2069 (NICHT U+200E/U+200F -
//           die meldet der Detektor nicht);
//   SCA192: U+200B..U+200D, U+2060, U+FEFF (ein U+FEFF ganz am Dateianfang
//           ist die BOM, die der Detektor ueberspringt - im Editor-Puffer
//           steht sie nicht; NBSP U+00A0 zaehlt nicht).
// Alle diese Zeichen liegen in der BMP: ein Zeichen ist genau eine UTF-16-
// Einheit der Zeile (die Spalten der Code-Sicht und von TRdxEdit zaehlen
// UTF-16-Einheiten). Ein Surrogatpaar daneben (Emoji) wird nie geteilt -
// die Schnitte liegen nur vor und hinter dem BMP-Zeichen.
//
// SPERREN (lieber keine Hilfe als eine falsche) - ein Zeichen der Zeile ...
//   * steht im Code (weder String noch Kommentar): in einem Bezeichner
//     kann das Loeschen den gebundenen Namen aendern; von Hand pruefen;
//   * steht in einer Compiler-Direktive ({$I ..}, {$MESSAGE '..'}): das
//     Loeschen aendert die Direktive (Dateiname, Text). Rueckwaerts bis
//     zum Anfang des Kommentars gesucht - beginnt in derselben Kommentar-
//     Folge irgendwo eine Direktive ('{$I x}{ c }'), sperrt das schon
//     (vorsichtig);
//   * steht in einem mehrzeiligen String (''' .. ''', Delphi 12): dort gibt
//     es keine Zeichen-Codes;
//   * steht in einem String, der auf der Zeile nicht endet;
//   * steht in einem String, hinter dem '.' (nicht '..') oder '[' folgt:
//     ein Helfer-Aufruf oder Index am Literal - ob er nach dem Aufbrechen
//     noch dasselbe Ganze meint, prueft die Hilfe nicht;
//   * das Loeschen im Kommentar aenderte dessen Form: aus '{<X>$I x}' wuerde
//     eine Direktive, aus '(* a *<X>) b *)' endete der Kommentar frueher.
//     Gegenprobe: die Code-Sicht der geaenderten Datei muss jedes
//     verbliebene Zeichen gleich einordnen (Code/String/Kommentar,
//     Direktiven-Anfang) - auf der Zeile und in allen Zeilen danach;
//   * nur SCA192: ein Joiner (U+200C ZWNJ, U+200D ZWJ) im Kommentar neben
//     einem Nicht-ASCII-Zeichen - Teil einer Emoji-Folge (auch hinter
//     U+FE0F) oder einer Schrift (ZWNJ im Persischen, ZWJ in indischen
//     Schriften). Loeschen aenderte nicht das Programm, aber den Text des
//     Autors; das entscheidet er selbst. U+200B, U+2060 und U+FEFF im
//     Kommentar loescht die Hilfe immer (sie verbinden nichts).
// Sperrt ein Zeichen, gibt es fuer die ganze Zeile keine Hilfe - eine
// Teilhilfe liesse den Fund auf derselben Zeile stehen.
// Steht auf der Zeile kein Zeichen der Regel: Zeile verschoben.
//
// Nach der Umformung kann hinter dem letzten Zeichen-Code ein Bezeichner-
// zeichen folgen ('<X>'then -> #$202E then): dann setzt die Hilfe ein
// Leerzeichen dazwischen, sonst laese der Compiler 'then' als Teil der
// Hex-Zahl (E und e sind Hex-Ziffern).
//
// FORM: die beiden Planer haben die Form TRdxMapPlanner (uRdxFixRunner);
// die Adapter der Tabelle (MapFix) stehen in uRdxFixTable. Diese Unit
// bindet nur uRdxCodeMap, uRdxBufferMath, uRdxText, uRefactorInfo und
// System.* - FPC-tauglich. Unter FPC 3.2 haelt TStringList AnsiString: die
// Gegenprobe (eine Kopie der Zeilen) verliert Zeichen ausserhalb der
// Systemcodepage, wenn die nicht UTF-8 ist (die Tests stellen sie um).

interface

uses
  uRdxBufferMath,    // TRdxEdit
  uRdxCodeMap;       // TRdxCodeMap

const
  // Gruende der Ablehnung als englische msgids (uRdxText._, E29); die Tests
  // vergleichen mit _(). %s vorn ist der Code des Zeichens ('U+202E'), %s
  // am Ende ein Satzende aus uRdxText (MsgCheckByHand, MsgDecideByHand).
  R_BIDI_NONE = 'no bidirectional control character on the reported line';
  R_INVIS_NONE = 'no invisible character on the reported line';
  R_ESC_IN_CODE = '%s stands in code, not in a string or comment - %s';
  R_ESC_DIRECTIVE = '%s stands in a compiler directive - deleting it would '
    + 'change the directive; %s';
  R_ESC_MULTI_LINE = '%s stands in a multi-line string - it cannot be '
    + 'written as a character code there; %s';
  R_ESC_UNCLOSED = '%s stands in a string that does not end on its line';
  R_ESC_MEMBER = '%s stands in a string followed by "." or "[" - splitting '
    + 'the string could change what that applies to; %s';
  R_ESC_SHAPE = 'deleting %s would change the comment (it would end '
    + 'earlier or turn into a directive)';
  R_INVIS_JOINER = 'the joiner %s in a comment stands next to a non-ASCII '
    + 'character - it may belong to an emoji or a script; %s';

type
  // Die Planer von SCA188 und SCA192 (Form TRdxMapPlanner, uRdxFixRunner).
  // AMessage bleibt ungenutzt: die Meldung nennt weder Spalte noch Zeichen.
  TRdxCharEscapeFix = class
  public
    // SCA188: die Bidi-Steuerzeichen von ALine - im Kommentar geloescht, im
    // String als #$xxxx; sonst der Grund.
    class function BidiOverride(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
    // SCA192: die unsichtbaren Zeichen von ALine - im String als #$xxxx,
    // im Kommentar geloescht (Joiner neben Nicht-ASCII: keine Hilfe).
    class function InvisibleChar(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
    // Zeichen der Regel SCA188 bzw. SCA192 - die Mengen des Detektors.
    class function IsBidiControl(C: Char): Boolean; static;
    class function IsInvisible(C: Char): Boolean; static;
    // Der Zeichen-Code, den die Hilfe schreibt: '#$202E' (vier Hex-Ziffern,
    // gross).
    class function CharCode(C: Char): string; static;
  end;

implementation

uses
  System.SysUtils,   // IntToHex
  System.Classes,    // TStringList (Gegenprobe der Kommentar-Form)
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxText;          // _(), MsgMovedSuffix, MsgCheckByHand, MsgDecideByHand

const
  SPAN_188 = 'sca188';
  SPAN_192 = 'sca192';
  QUOTE = '''';
  CODE_PREFIX = '#$';
  CODE_POINT_PREFIX = 'U+';
  ZWNJ = #$200C;
  ZWJ = #$200D;

type
  // Ein Zeichen der Regel? (plain function - FPC 3.2 kennt keine
  // Funktionsreferenzen, und eine statische Klassenmethode als Wert eines
  // schlichten Prozedurtyps vermeiden wir fuer den Pruefstand).
  TCharTest = function(C: Char): Boolean;

  // Ergebnis der Planung einer Zeile.
  TEscapeStop = (esOk, esNoTarget, esCode, esDirective, esMultiLine,
    esUnclosed, esMember, esShape, esJoiner);

function IsBidiCode(C: Char): Boolean;
begin
  Result := (Ord(C) = $061C)
    or ((Ord(C) >= $202A) and (Ord(C) <= $202E))
    or ((Ord(C) >= $2066) and (Ord(C) <= $2069));
end;

function IsInvisibleCode(C: Char): Boolean;
begin
  Result := ((Ord(C) >= $200B) and (Ord(C) <= $200D))
    or (Ord(C) = $2060) or (Ord(C) = $FEFF);
end;

function CodePointText(C: Char): string;
begin
  Result := CODE_POINT_PREFIX + IntToHex(Ord(C), 4);
end;

// Steht (ALine, ACol) - ein Kommentar-Zeichen ('k') - in einer Direktive?
// Rueckwaerts durch die Kommentar-Folge bis zu ihrem Anfang (ueber Zeilen,
// solange die Zeile in einem Block-Kommentar beginnt); trifft die Suche
// einen Direktiven-Anfang, True. Ein '//'-Kommentar ist nie eine Direktive.
function InDirective(AMap: TRdxCodeMap; ALine, ACol: Integer): Boolean;
var
  L, C, S : Integer;
begin
  Result := False;
  S := AMap.LineCommentCol(ALine);
  if (S > 0) and (ACol >= S) then Exit;
  L := ALine;
  C := ACol;
  while L >= 1 do
  begin
    if C < 1 then
    begin
      if not AMap.StartsInside(L) then Exit;
      Dec(L);
      C := Length(AMap.Raw(L));
      Continue;
    end;
    if AMap.ClassAt(L, C) <> 'k' then Exit;
    if AMap.DirectiveStartsAt(L, C) then Exit(True);
    Dec(C);
  end;
end;

// Ein Joiner (ZWNJ, ZWJ) an AL[ACol] mit einem Nicht-ASCII-Nachbarn.
function JoinerNextToNonAscii(const AL: string; ACol: Integer): Boolean;
begin
  Result := False;
  if (AL[ACol] <> ZWNJ) and (AL[ACol] <> ZWJ) then Exit;
  Result := ((ACol > 1) and (Ord(AL[ACol - 1]) > 127))
    or ((ACol < Length(AL)) and (Ord(AL[ACol + 1]) > 127));
end;

// Die Grenzen des einzeiligen String-Literals um (ALine, ACol): AStart das
// oeffnende, AClose das schliessende Quote; sonst der Sperrgrund.
function LiteralBounds(AMap: TRdxCodeMap; ALine, ACol: Integer;
  const AL: string; out AStart, AClose: Integer): TEscapeStop;
var
  j, q : Integer;
begin
  AStart := ACol;
  AClose := 0;
  while (AStart > 1) and (AMap.ClassAt(ALine, AStart - 1) = 's') do
    Dec(AStart);
  // Ab Spalte 1 String in einer Zeile, die in einem String beginnt: der
  // Rumpf eines mehrzeiligen Strings. Ein oeffnendes ''' am Zeilenende
  // ebenso (dort steht nur Leerraum, aber sicher ist sicher).
  if ((AStart = 1) and AMap.StartsInside(ALine)) or (AL[AStart] <> QUOTE) then
    Exit(esMultiLine);
  q := QuoteRun(AL, AStart);
  if (q >= MIN_MULTI_QUOTES) and Odd(q)
     and (SkipBlanks(AL, AStart + q) > Length(AL)) then
    Exit(esMultiLine);
  j := AStart + 1;
  while j <= Length(AL) do
    if AL[j] = QUOTE then
    begin
      if (j < Length(AL)) and (AL[j + 1] = QUOTE) then
        Inc(j, 2)   // verdoppeltes '' im String
      else
      begin
        AClose := j;
        Break;
      end;
    end
    else
      Inc(j);
  if (AClose = 0) or (AClose < ACol) then
    Exit(esUnclosed);
  // Ein '.' (kein '..') oder '[' hinter dem Literal: Helfer oder Index.
  j := SkipBlanks(AL, AClose + 1);
  if (j <= Length(AL)) and ((AL[j] = '[') or ((AL[j] = '.')
     and ((j = Length(AL)) or (AL[j + 1] <> '.')))) then
    Exit(esMember);
  Result := esOk;
end;

// Das Literal AL[AStart..AClose] neu: die Zeichen der Regel als Code,
// der Rest in Quotes (verdoppelte '' bleiben, wie sie sind - ein Zeichen
// der Regel ist nie ein Quote und trennt kein Paar). Endet es auf einem
// Code und folgt ein Bezeichnerzeichen, ein Leerzeichen dahinter.
function Rebuilt(const AL: string; AStart, AClose: Integer;
  AIsTarget: TCharTest): string;
var
  Seg     : string;
  j       : Integer;
  EndCode : Boolean;
begin
  Result := '';
  Seg := '';
  EndCode := False;
  for j := AStart + 1 to AClose - 1 do
    if AIsTarget(AL[j]) then
    begin
      if Seg <> '' then
        Result := Result + QUOTE + Seg + QUOTE;
      Seg := '';
      Result := Result + TRdxCharEscapeFix.CharCode(AL[j]);
      EndCode := True;
    end
    else
    begin
      Seg := Seg + AL[j];
      EndCode := False;
    end;
  if Seg <> '' then
    Result := Result + QUOTE + Seg + QUOTE;
  if EndCode and (AClose < Length(AL)) and IsIdentChar(AL[AClose + 1]) then
    Result := Result + ' ';
end;

// Gegenprobe einer Loeschung im Kommentar: die Datei mit ANew statt Zeile
// ALine neu eingeordnet. Jedes verbliebene Zeichen der Zeile (AOrigin: die
// alte Spalte je neuer Spalte, 0 = neu geschriebenes Literal) und jedes
// Zeichen der Zeilen danach muss dieselbe Klasse und denselben Direktiven-
// Anfang haben.
function ShapeKept(AMap: TRdxCodeMap; ALine: Integer; const ANew: string;
  const AOrigin: TArray<Integer>): Boolean;
var
  SL   : TStringList;
  M    : TRdxCodeMap;
  i, j : Integer;
  o    : Integer;
begin
  Result := False;
  SL := TStringList.Create;
  M := nil;
  try
    for i := 1 to AMap.LineCount do
      if i = ALine then
        SL.Add(ANew)
      else
        SL.Add(AMap.Raw(i));
    M := TRdxCodeMap.Create(SL);
    for j := 1 to Length(ANew) do
    begin
      o := AOrigin[j - 1];
      if (o > 0) and ((M.ClassAt(ALine, j) <> AMap.ClassAt(ALine, o))
         or (M.DirectiveStartsAt(ALine, j) <> AMap.DirectiveStartsAt(ALine, o))) then
        Exit;
    end;
    for i := ALine + 1 to AMap.LineCount do
    begin
      if M.StartsInside(i) <> AMap.StartsInside(i) then Exit;
      for j := 1 to Length(AMap.Raw(i)) do
        if (M.ClassAt(i, j) <> AMap.ClassAt(i, j))
           or (M.DirectiveStartsAt(i, j) <> AMap.DirectiveStartsAt(i, j)) then
          Exit;
    end;
    Result := True;
  finally
    M.Free;
    SL.Free;
  end;
end;

// Die gemeinsame Planung: alle Zeichen der Regel auf ALine. True mit der
// Ersetzung (erste bis letzte geaenderte Spalte), sonst AStop und das
// Zeichen, an dem es scheiterte (AStopChar).
function PlanLine(AMap: TRdxCodeMap; ALine: Integer; AIsTarget: TCharTest;
  AGuardJoiners: Boolean; const ARole: string; out AEdit: TRdxEdit;
  out AStop: TEscapeStop; out AStopChar: Char): Boolean;
var
  L, NewLine, Piece : string;
  Drop              : TArray<Boolean>;
  LitClose          : TArray<Integer>;
  Origin            : TArray<Integer>;
  i, k, S0, CloseQ  : Integer;
  First, Last       : Integer;
  Any, Dropped      : Boolean;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AStop := esNoTarget;
  AStopChar := #0;
  L := AMap.Raw(ALine);
  SetLength(Drop, Length(L) + 1);
  SetLength(LitClose, Length(L) + 1);
  for i := 0 to Length(L) do
  begin
    Drop[i] := False;
    LitClose[i] := 0;
  end;
  // 1) Jedes Zeichen der Regel einordnen.
  Any := False;
  Dropped := False;
  i := 1;
  while i <= Length(L) do
  begin
    if not AIsTarget(L[i]) then
    begin
      Inc(i);
      Continue;
    end;
    Any := True;
    AStopChar := L[i];
    case AMap.ClassAt(ALine, i) of
      's':
        begin
          AStop := LiteralBounds(AMap, ALine, i, L, S0, CloseQ);
          if AStop <> esOk then Exit;
          LitClose[S0] := CloseQ;
          i := CloseQ + 1;
          Continue;
        end;
      'k':
        begin
          if InDirective(AMap, ALine, i) then
          begin
            AStop := esDirective;
            Exit;
          end;
          if AGuardJoiners and JoinerNextToNonAscii(L, i) then
          begin
            AStop := esJoiner;
            Exit;
          end;
          Drop[i] := True;
          Dropped := True;
        end;
    else
      AStop := esCode;
      Exit;
    end;
    Inc(i);
  end;
  if not Any then
  begin
    AStop := esNoTarget;
    Exit;
  end;
  // 2) Die neue Zeile; Origin haelt je neuer Spalte die alte (0 = neu).
  NewLine := '';
  Origin := nil;
  First := 0;
  Last := 0;
  i := 1;
  while i <= Length(L) do
    if LitClose[i] > 0 then
    begin
      Piece := Rebuilt(L, i, LitClose[i], AIsTarget);
      NewLine := NewLine + Piece;
      for k := 1 to Length(Piece) do
      begin
        SetLength(Origin, Length(Origin) + 1);
        Origin[High(Origin)] := 0;
      end;
      if First = 0 then First := i;
      Last := LitClose[i];
      i := LitClose[i] + 1;
    end
    else if Drop[i] then
    begin
      if First = 0 then First := i;
      Last := i;
      Inc(i);
    end
    else
    begin
      NewLine := NewLine + L[i];
      SetLength(Origin, Length(Origin) + 1);
      Origin[High(Origin)] := i;
      Inc(i);
    end;
  // 3) Gegenprobe der Kommentar-Form, wenn etwas geloescht wurde.
  if Dropped and not ShapeKept(AMap, ALine, NewLine, Origin) then
  begin
    for i := 1 to Length(L) do
      if Drop[i] then
      begin
        AStopChar := L[i];
        Break;
      end;
    AStop := esShape;
    Exit;
  end;
  AEdit.Span := TRefactorSpan.Make(ARole, ALine, First, ALine, Last + 1);
  AEdit.Expected := RangeText(AMap, AEdit.Span);
  AEdit.NewText := Copy(NewLine, First,
    Length(NewLine) - (Length(L) - Last) - First + 1);
  AStop := esOk;
  Result := True;
end;

// Der Grund zu AStop; ANone ist der schon uebersetzte Grund "kein Zeichen
// der Regel auf der Zeile".
function StopReason(AStop: TEscapeStop; AChar: Char;
  const ANone: string): string;
begin
  case AStop of
    esCode:      Result := _(R_ESC_IN_CODE, [CodePointText(AChar), MsgCheckByHand]);
    esDirective: Result := _(R_ESC_DIRECTIVE, [CodePointText(AChar), MsgCheckByHand]);
    esMultiLine: Result := _(R_ESC_MULTI_LINE, [CodePointText(AChar), MsgCheckByHand]);
    esUnclosed:  Result := _(R_ESC_UNCLOSED, [CodePointText(AChar)]);
    esMember:    Result := _(R_ESC_MEMBER, [CodePointText(AChar), MsgCheckByHand]);
    esShape:     Result := _(R_ESC_SHAPE, [CodePointText(AChar)]);
    esJoiner:    Result := _(R_INVIS_JOINER, [CodePointText(AChar), MsgDecideByHand]);
  else
    Result := MsgMovedSuffix(ANone);
  end;
end;

{ TRdxCharEscapeFix }

class function TRdxCharEscapeFix.IsBidiControl(C: Char): Boolean;
begin
  Result := IsBidiCode(C);
end;

class function TRdxCharEscapeFix.IsInvisible(C: Char): Boolean;
begin
  Result := IsInvisibleCode(C);
end;

class function TRdxCharEscapeFix.CharCode(C: Char): string;
begin
  Result := CODE_PREFIX + IntToHex(Ord(C), 4);
end;

class function TRdxCharEscapeFix.BidiOverride(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  Stop : TEscapeStop;
  C    : Char;
begin
  AReason := '';
  Result := PlanLine(AMap, ALine, IsBidiCode, False, SPAN_188, AEdit, Stop, C);
  if not Result then
    AReason := StopReason(Stop, C, _(R_BIDI_NONE));
end;

class function TRdxCharEscapeFix.InvisibleChar(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  Stop : TEscapeStop;
  C    : Char;
begin
  AReason := '';
  Result := PlanLine(AMap, ALine, IsInvisibleCode, True, SPAN_192, AEdit,
    Stop, C);
  if not Result then
    AReason := StopReason(Stop, C, _(R_INVIS_NONE));
end;

end.

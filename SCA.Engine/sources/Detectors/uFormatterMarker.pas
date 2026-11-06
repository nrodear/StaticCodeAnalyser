unit uFormatterMarker;

// Detektor FormatterMarker (SCA206, Nico-Entscheide 2026-11-06): das
// Markerpaar {(*} ... {*)} schaltet den Code-Formatter fuer den Bereich
// dazwischen aus und danach wieder ein. Es stammt aus DelForExp und wirkt im
// GExperts-Formatter, im CnWizards-Formatter und in JEDI Code Format (JCF,
// auch in Lazarus); der Formatter der Delphi-IDE (Strg+D, bis Delphi 12)
// kennt es nicht, Delphi 13 liefert keinen Formatter mehr aus. Fuer den
// Compiler sind beide Marker gewoehnliche, geschlossene { }-Kommentare (das
// '(*' darin ist Text) - kein Fund dieser Regel aendert je das Kompilat,
// nur das Ergebnis des Formatters. Daher Hint, Code Smell.
//
// VERTRAG (je Marker hoechstens ein Fund; Zeile des Markers, Methode leer,
// keine Spalte in der Meldung):
//   F1  {(*} ohne folgendes {*)} bis zum Dateiende: der Formatter
//       formatiert ab dort nichts mehr. Gemeldet an dem {(*}, der den
//       Bereich geoeffnet hat.
//   F2  {*)} ohne offenen Bereich: schliesst nichts, der gemeinte Bereich
//       darueber wird formatiert.
//   F3  zweites {(*} in einem offenen Bereich: die Marker schachteln nicht
//       (ein Schalter, kein Zaehler - CnScanners 'InIgnoreArea', JCF
//       SwitchableVisitor 'fbEnabled'), das erste {*)} schaltet die
//       Formatierung schon wieder ein.
//   F4  Leerraum im Marker ('{ (*}', '{(* }', '{ *)}', '{*) }', Tab statt
//       Blank): CnWizards nimmt nur genau drei Zeichen zwischen { und },
//       JCF vergleicht den ganzen Kommentar exakt - der Marker wird still
//       ignoriert und der Bereich doch formatiert. Der Markertext steht in
//       der Meldung (gewollt Teil der Fund-Identitaet); Steuerzeichen als
//       '#9' usw., damit SARIF/CSV keine rohen Tabs tragen.
// F4 hat am selben Marker Vorrang vor F1-F3: ein falsch geschriebener
// Marker ist fuer den Formatter gar keiner, die Bilanzmeldung waere ein
// Folgefehler. In der Bilanz zaehlt er trotzdem als GEMEINTER Start bzw.
// GEMEINTES Ende - sonst meldete '{ (*}' ... '{*)}' zusaetzlich F2 am
// korrekt geschriebenen Ende.
//
// ERKENNUNG (Dateitext, kein AST - uLexer verwirft Kommentare):
//   Eigener Kommentar-Lauf ueber die ganze Datei mit denselben Regeln wie
//   TDetectorUtils.ScanCodeLine: '..'-String mit '' als Escape, { } bis zum
//   ersten }, (* *) bis zum ersten *), // bis Zeilenende. Dazu Delphi-12-
//   Mehrzeilenstrings (ungerade Folge von mindestens drei Apostrophen, nur
//   Leerraum dahinter; Ende an der Zeile, die nach Leerraum mit derselben
//   Folge beginnt - wie TRefactorInfoBuilder.OpensMultiLineString und
//   TRdxCodeMap), damit ein Marker im String nicht zaehlt. Der Lauf steht
//   hier und nicht in ScanCodeLine: der ist Hot-Path mit rund 40 Aufrufern
//   und liefert keine Kommentar-Token (Entscheid E6, ein gemeinsamer Helfer
//   lohnt erst beim zweiten Nutzer).
//   Kandidat ist nur ein { }-Kommentar, der auf EINER Zeile oeffnet und
//   schliesst und nicht mit '{$' beginnt (Direktive). Exakt '{(*}' ist ein
//   Start, exakt '{*)}' ein Ende; ein Inhalt, der ohne Leerraum genau '(*'
//   bzw. '*)' ist, ist F4. Alles andere ist kein Marker: die Fussnoten-
//   Spalte '{ (*) }' (JvRichEd), '{(* alter Code *)}', '(* {(*} *)',
//   Marker in //-Kommentaren und in Strings (JCF-Konstanten '{(*}').
//   Vorfilter '(*' / '*)' (Teilstring, ODER): beide Marker und jede
//   F4-Form enthalten eines davon - ein engeres '(*}' liesse F4 durch den
//   Vorfilter fallen (Entscheid E4).
//
// GRENZEN (bewusst):
//   G1 {$IFDEF}-Zweige werden roh gezaehlt, wie CnWizards sie liest. JCF
//      wertet inaktive Zweige nicht aus - ein Paar, dessen Haelften in
//      verschiedenen Zweigen stehen, ist dort unvollstaendig, hier nicht.
//   G2 Nur das Standardpaar. Eigene Schluesselwoerter des GExperts-
//      Formatters und die JCF-Direktiven '//jcf:format=off' kennt die Regel
//      nicht (Entscheide E3, E5).
//   G3 Die FPC-Schachtelung von { { } }-Kommentaren (Modi fpc/objfpc)
//      bildet der Lauf nicht nach: er beendet einen aeusseren Kommentar am
//      ersten }. Korpus 2026-11-06: kein Fall.
//   G4 Ein absichtlich bis Dateiende offener Bereich meldet F1 - per
//      '// noinspection FormatterMarker' in der Zeile davor stillzulegen.
//      Daher Konfidenz fcMedium (KindDefaultConfidence), nicht fcHigh.
//   G5 Bilanz je Datei; {$I}-Include-Dateien werden nicht verfolgt. So
//      sehen es auch die Formatter, die je Datei bzw. Puffer formatieren.
//   G6 Ein { }-Kommentar, der ueber mehrere Zeilen laeuft, ist nie ein
//      Kandidat (ein Marker steht immer auf einer Zeile).
//   G7 Dass der GExperts-Formatter exakt vergleicht, ist Annahme - sein
//      Quelltext liegt nicht lokal; DelForExp, JCF und CnWizards sind belegt.
//
// Korpus 2026-11-06 (24.163 Pascal-Dateien): ein echter Defekt, JCF
// BasicStats.pas (F2 in Zeile 25, F1 in Zeile 39); Leerraum-Formen 0.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TFormatterMarkerDetector = class
  public
    // UnitNode bleibt ungenutzt (Dateitext-Detektor); die Signatur folgt
    // den anderen Detektoren.
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

uses
  System.StrUtils,
  uFileTextCache,
  uStaticFiles,     // IsUnitLikeFile - Dialekt-Endungen (.pp/.lpr bei dlFpc)
  uLocalization;    // N_ - feste Meldungen als msgid markiert (Anzeige uebersetzt)

const
  MARKER_START = '{(*}';
  MARKER_END   = '{*)}';
  // Mindestlaenge der Apostroph-Folge, die einen Delphi-12-Mehrzeilen-
  // string oeffnet (''' am Zeilenende).
  MIN_MULTI_QUOTES = 3;

type
  // Ein Marker (auch ein falsch geschriebener) in Dateireihenfolge.
  TMarkerHit = record
    Line      : Integer;   // 1-basiert
    IsStart   : Boolean;   // als {(*} gemeint, sonst als {*)}
    Malformed : Boolean;   // F4: Leerraum im Marker
    Text      : string;    // der { }-Kommentar wie geschrieben
  end;

  // Urteil je Marker nach der Bilanz.
  TMarkerVerdict = (mvNone, mvUnclosed, mvOrphanEnd, mvNestedStart,
    mvMalformed);

  // Der Kommentar-Lauf: Zustand ueber die Zeilen (offener { }- bzw. (* *)-
  // Kommentar, offener Mehrzeilenstring) und die Schritte je Zustand. Ein
  // Schritt liefert die naechste Spalte; Length(FLine) + 1 beendet die
  // Zeile.
  TMarkerScanner = class
  private
    FHits     : TList<TMarkerHit>;
    FLine     : string;
    FLineNo   : Integer;
    FInBrace  : Boolean;   // { } ueber das Zeilenende offen
    FInParen  : Boolean;   // (* *) ueber das Zeilenende offen
    FInStr    : Boolean;   // '..'-String (endet immer in der Zeile)
    FMultiRun : Integer;   // > 0: offener Mehrzeilenstring, Laenge der Folge
    function LineEnd: Integer;
    function PairAt(j: Integer; ASecond: Char): Boolean;
    function ResumeMultiLine: Integer;
    function StepComment(j: Integer): Integer;
    function StepString(j: Integer): Integer;
    function StepQuote(j: Integer): Integer;
    function StepBrace(j: Integer): Integer;
    function StepCode(j: Integer): Integer;
    procedure NoteBrace(const AText: string);
  public
    constructor Create(AHits: TList<TMarkerHit>);
    procedure ScanLine(const ALine: string; ALineNo: Integer);
  end;

// Laenge der Apostroph-Folge ab ALine[AIdx].
function QuoteRun(const ALine: string; AIdx: Integer): Integer;
begin
  Result := 0;
  while (AIdx + Result <= Length(ALine)) and (ALine[AIdx + Result] = '''') do
    Inc(Result);
end;

// Ordnet einen geschlossenen { }-Kommentar ein. False = kein Marker.
// Direktiven ('{$...}') sind nie Kandidaten; ihr Inhalt beginnt mit '$' und
// kaeme ohnehin nie auf '(*' - die Abfrage steht hier, damit der Vertrag
// sichtbar bleibt.
function ClassifyBrace(const AText: string; out AIsStart,
  AMalformed: Boolean): Boolean;
var
  Inner : string;
begin
  AIsStart   := False;
  AMalformed := False;
  if (Length(AText) >= 2) and (AText[2] = '$') then
    Exit(False);
  if (AText = MARKER_START) or (AText = MARKER_END) then
  begin
    AIsStart := AText = MARKER_START;
    Exit(True);
  end;
  // Trim nimmt Blank, Tab und andere Zeichen <= #32 - genau der Leerraum,
  // an dem CnWizards (drei Zeichen) und JCF (exakter Vergleich) scheitern.
  Inner := Trim(Copy(AText, 2, Length(AText) - 2));
  AIsStart   := Inner = '(*';
  AMalformed := AIsStart or (Inner = '*)');
  Result := AMalformed;
end;

// Der Markertext fuer die Meldung: Steuerzeichen als Pascal-Zeichen-
// literal ('#9'), damit Tab und Co. in SARIF, CSV und Grid sichtbar sind.
function VisibleText(const AText: string): string;
var
  C : Char;
begin
  Result := '';
  for C in AText do
    if C < ' ' then
      Result := Result + '#' + IntToStr(Ord(C))
    else
      Result := Result + C;
end;

{ TMarkerScanner }

constructor TMarkerScanner.Create(AHits: TList<TMarkerHit>);
begin
  inherited Create;
  FHits := AHits;
end;

function TMarkerScanner.LineEnd: Integer;
begin
  Result := Length(FLine) + 1;
end;

function TMarkerScanner.PairAt(j: Integer; ASecond: Char): Boolean;
begin
  Result := (j < Length(FLine)) and (FLine[j + 1] = ASecond);
end;

// Zeile innerhalb eines offenen Mehrzeilenstrings: er endet nur an einer
// Zeile, die nach Leerraum mit derselben Apostroph-Folge beginnt; dahinter
// ist wieder Code.
function TMarkerScanner.ResumeMultiLine: Integer;
var
  j : Integer;
begin
  j := 1;
  while (j <= Length(FLine)) and (FLine[j] <= ' ') do
    Inc(j);
  if QuoteRun(FLine, j) <> FMultiRun then
    Exit(LineEnd);
  Result := j + FMultiRun;
  FMultiRun := 0;
end;

// In einem offenen Kommentar: { } endet am ersten }, (* *) am ersten *).
// Gleiche Art schachtelt nicht, die andere Art ist innen nur Text.
function TMarkerScanner.StepComment(j: Integer): Integer;
var
  p : Integer;
begin
  if FInBrace then
  begin
    p := PosEx('}', FLine, j);
    if p = 0 then
      Exit(LineEnd);
    FInBrace := False;
    Exit(p + 1);
  end;
  p := PosEx('*)', FLine, j);
  if p = 0 then
    Exit(LineEnd);
  FInParen := False;
  Result := p + 2;
end;

// In einem '..'-String: '' ist ein Apostroph im String, ' allein endet ihn.
function TMarkerScanner.StepString(j: Integer): Integer;
begin
  if FLine[j] <> '''' then
    Exit(j + 1);
  if PairAt(j, '''') then
    Exit(j + 2);
  FInStr := False;
  Result := j + 1;
end;

// Apostroph im Code: Mehrzeilenstring (Rest der Zeile ist Leerraum) oder
// gewoehnlicher String.
function TMarkerScanner.StepQuote(j: Integer): Integer;
var
  Run : Integer;
begin
  Run := QuoteRun(FLine, j);
  if (Run >= MIN_MULTI_QUOTES) and Odd(Run)
     and (Trim(Copy(FLine, j + Run, MaxInt)) = '') then
  begin
    FMultiRun := Run;
    Exit(LineEnd);
  end;
  FInStr := True;
  Result := j + 1;
end;

// '{' im Code: auf derselben Zeile geschlossen -> Kandidat pruefen, sonst
// laeuft der Kommentar in die naechste Zeile (nie ein Kandidat, G6).
function TMarkerScanner.StepBrace(j: Integer): Integer;
var
  p : Integer;
begin
  p := PosEx('}', FLine, j + 1);
  if p = 0 then
  begin
    FInBrace := True;
    Exit(LineEnd);
  end;
  NoteBrace(Copy(FLine, j, p - j + 1));
  Result := p + 1;
end;

function TMarkerScanner.StepCode(j: Integer): Integer;
begin
  Result := j + 1;
  if FLine[j] = '''' then
    Result := StepQuote(j)
  else if FLine[j] = '{' then
    Result := StepBrace(j)
  else if (FLine[j] = '/') and PairAt(j, '/') then
    Result := LineEnd                  // Rest der Zeile ist Kommentar
  else if (FLine[j] = '(') and PairAt(j, '*') then
  begin
    FInParen := True;                  // '*)' wird ab j + 2 gesucht: '(*)'
    Result := j + 2;                   // oeffnet nur, wie beim Compiler
  end;
end;

procedure TMarkerScanner.NoteBrace(const AText: string);
var
  Hit : TMarkerHit;
begin
  if not ClassifyBrace(AText, Hit.IsStart, Hit.Malformed) then
    Exit;
  Hit.Line := FLineNo;
  Hit.Text := AText;
  FHits.Add(Hit);
end;

procedure TMarkerScanner.ScanLine(const ALine: string; ALineNo: Integer);
var
  j : Integer;
begin
  FLine   := ALine;
  FLineNo := ALineNo;
  FInStr  := False;                    // Strings enden immer in der Zeile
  j := 1;
  if FMultiRun > 0 then
    j := ResumeMultiLine;
  while j <= Length(FLine) do
    if FInBrace or FInParen then
      j := StepComment(j)
    else if FInStr then
      j := StepString(j)
    else
      j := StepCode(j);
end;

// Bilanz in Dateireihenfolge, ein Schalter (keine Schachtelung). AVerdicts
// gehoert Index fuer Index zu AHits. Ein F4-Marker zaehlt als gemeint,
// traegt aber nur sein F4 (Vorrang, s. Kopf).
function Judge(AHits: TList<TMarkerHit>): TArray<TMarkerVerdict>;
var
  k, OpenIdx : Integer;
begin
  SetLength(Result, AHits.Count);
  OpenIdx := -1;
  for k := 0 to AHits.Count - 1 do
  begin
    Result[k] := mvNone;
    if AHits[k].Malformed then
      Result[k] := mvMalformed;
    if AHits[k].IsStart then
    begin
      if OpenIdx < 0 then
        OpenIdx := k
      else if Result[k] = mvNone then
        Result[k] := mvNestedStart;
    end
    else if OpenIdx >= 0 then
      OpenIdx := -1
    else if Result[k] = mvNone then
      Result[k] := mvOrphanEnd;
  end;
  if (OpenIdx >= 0) and (Result[OpenIdx] = mvNone) then
    Result[OpenIdx] := mvUnclosed;
end;

// Meldung je Urteil (englisch: Fingerprint). F1-F3 sind feste Saetze (N_,
// die Anzeige uebersetzt sie); F4 traegt den Markertext.
function MessageOf(const AHit: TMarkerHit; AVerdict: TMarkerVerdict): string;
var
  Exact : string;
begin
  case AVerdict of
    mvUnclosed:
      Result := N_('Formatter marker {(*} is never closed by {*)} - ' +
        'GExperts, CnWizards and JCF leave the rest of the file unformatted');
    mvOrphanEnd:
      Result := N_('Formatter marker {*)} has no opening {(*} - it closes ' +
        'nothing, the code above it is formatted');
    mvNestedStart:
      Result := N_('Second {(*} inside an open formatter-off region - the ' +
        'markers do not nest, the first {*)} already switches formatting ' +
        'back on');
  else
    if AHit.IsStart then
      Exact := MARKER_START
    else
      Exact := MARKER_END;
    Result := Format('Malformed formatter marker ''%s'' - formatters ' +
      'recognise only the exact ''%s'' without blanks, so this marker is ' +
      'ignored', [VisibleText(AHit.Text), Exact]);
  end;
end;

// Endungs-Gate wie die Encoding-Familie (uSourceEncoding.HasSourceExt): die
// vier Delphi-Endungen und die Dialekt-Endungen aus TStaticFiles.
function HasSourceExt(const FileName: string): Boolean;
var
  Ext : string;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  Result := (Ext = '.pas') or (Ext = '.dpr') or (Ext = '.dpk') or (Ext = '.inc')
    or TStaticFiles.IsUnitLikeFile(FileName);
end;

class procedure TFormatterMarkerDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  Lines    : TStringList;
  Cached   : Boolean;
  Hits     : TList<TMarkerHit>;
  Scanner  : TMarkerScanner;
  Verdicts : TArray<TMarkerVerdict>;
  i, k     : Integer;
begin
  if not HasSourceExt(FileName) then Exit;
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  Hits := TList<TMarkerHit>.Create;
  try
    Scanner := TMarkerScanner.Create(Hits);
    try
      for i := 0 to Lines.Count - 1 do
        Scanner.ScanLine(Lines[i], i + 1);
    finally
      Scanner.Free;
    end;
    // Funde in Markerreihenfolge (= Zeilenreihenfolge): F1 entsteht erst am
    // Dateiende, steht aber an der Zeile seines Starts.
    Verdicts := Judge(Hits);
    for k := 0 to Hits.Count - 1 do
      if Verdicts[k] <> mvNone then
        Results.Add(TLeakFinding.New(FileName, '', Hits[k].Line,
          MessageOf(Hits[k], Verdicts[k]), fkFormatterMarker));
  finally
    Hits.Free;
    ReleaseLines(Lines, Cached);
  end;
end;

end.

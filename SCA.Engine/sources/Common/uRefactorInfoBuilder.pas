unit uRefactorInfoBuilder;

// Fuellt den GENERISCHEN Teil einer TRefactorInfo: Bereich mit Spalten
// (B1), Kontext-Flags (B5), Einfuegepunkt (B6) und Bereichs-Hash (B7).
// Konzept_Todo_RefactorInfo 2026-10-01, Inkrement 2.
//
// WAS EIN DETEKTOR DAVON HAT
//
// Ein Detektor kennt den ANFANG seiner Fundstelle (TAstNode.Line/.Col),
// aber nicht ihr Ende - der AST traegt keine Endposition, und die rechte
// Seite einer Zuweisung liegt nur als abgeflachter String vor. Dieser
// Builder liest die Quellzeilen ab dem Anfang und findet das Ende der
// Anweisung. Vier der acht Refactoring-Informationen kosten den Detektor
// damit einen einzigen Aufruf; nur die Teilbereiche und ihre Fakten
// (B2-B4) bleiben seine eigene Arbeit - dafuer liefert CodeViewOf die
// spaltentreue Code-Sicht.
//
// DAS ENDE EINER ANWEISUNG - DIESELBE REGEL WIE DER PARSER
//
// FindStatementEnd spiegelt den RHS-Scan in uParser2.ParseCallOrAssign:
//   * ';' auf Tiefe 0 beendet die Anweisung (und gehoert zum Bereich),
//   * 'else' / 'until' / 'except' / 'finally' auf Tiefe 0 beenden sie
//     OHNE ';' (Zuweisung im then-Zweig),
//   * 'end' auf Tiefe 0 ebenso,
//   * '(' '[' 'begin' 'case' 'try' 'asm' erhoehen die Tiefe, ')' ']'
//     'end' senken sie (anonyme Methode auf der rechten Seite).
// Eine zweite, abweichende Regel an dieser Stelle hiesse: Bereich und
// AST-Knoten beschreiben verschiedene Anweisungen.
//
// KEIN EIGENER LEXER
//
// Strings und Kommentare blendet ausschliesslich
// TDetectorUtils.ScanCodeLine aus (mit AKeepColumns = True, also
// spaltentreu). uQuickFix hat einmal ohne das in String-Literale
// hineingeschrieben (Upstream-Befund 7) - hier wird nichts selbst gelext.
// Zwei Ausnahmen, beide mit den Schritt-Helfern unten (dieselbe Quote-
// und Kommentarlogik wie ScanCodeLine):
//   * OpensMultiLineString erkennt den ANFANG eines Delphi-12-
//     Mehrzeilenstrings (''' am Zeilenende), den ScanCodeLine bewusst
//     nicht kennt. Es blendet nichts aus, es sagt nur "abbrechen".
//   * BlankComments sagt, welche der von ScanCodeLine gefuellten Spalten
//     zu einem KOMMENTAR gehoeren, und macht sie zu Leerraum (Review
//     reDelphiX 2026-10-07, Minor 4). ScanCodeLine fuellt Strings und
//     Kommentare mit demselben Zeichen; ein Term der Kette begann so an
//     einem Kommentar, und ''a''{x} galt als ein Literal. Ausblenden
//     tut weiter nur ScanCodeLine - BlankComments fasst keine Spalte an,
//     die dort Code blieb. ScanCodeLine selbst bleibt unveraendert: die
//     Detektoren lesen es mit derselben Fuellung fuer beides.
//
// LIEFERN DARF SCHEITERN
//
// Laesst sich das Ende nicht sauber bestimmen (kein Abschluss innerhalb
// von MAX_STATEMENT_LINES, unbalancierte Klammer, Startposition zeigt
// nicht auf Code, ein Mehrzeilenstring im Bereich), kommt nil zurueck.
// Der Aufrufer meldet seinen Fund dann OHNE RefactorInfo - der Fund
// selbst haengt nie am Builder. Mehrzeilenstring (Review reDelphiX
// 2026-10-07, Minor 5): die zeilenweise Code-Sicht las seinen Inhalt als
// Code, das Anweisungsende lief in die Folgeanweisung oder endete an
// einem ';' im SQL-Text.

interface

uses
  System.Classes,
  uAstNode, uDetectorUtils, uRefactorInfo;

type
  TRefactorInfoBuilder = class
  public
    const
      // Obergrenze fuer die Suche nach dem Anweisungsende. Eine Anweisung,
      // die laenger ist, wird nicht beschrieben (nil) statt halb.
      MAX_STATEMENT_LINES = 60;
      // Fuellzeichen der Code-Sicht fuer String-Literale. '~' ist in
      // Pascal-Code ausserhalb von Strings und Kommentaren kein gueltiges
      // Zeichen. Kommentare (auch Direktiven) sind in der Sicht Leerraum.
      VIEW_FILL = '~';

    // Beschreibt die Anweisung, die an (ALine, ACol) beginnt (1-basiert,
    // wie TAstNode.Line/.Col). Fuellt Span, Flags, InsertLine/-Indent und
    // SpanHash; Parts und FixSafe bleiben leer bzw. False.
    // AUnitNode darf nil sein - dann wird rfInConditional nie gesetzt.
    // Liefert nil, wenn das Anweisungsende nicht sauber bestimmbar ist.
    // Der Aufrufer besitzt das Ergebnis.
    class function TryBuildForStatement(AUnitNode: TAstNode;
      ALines: TStrings; ALine, ACol: Integer): TRefactorInfo; static;

    // Spaltentreue Code-Sicht des Bereichs: je Zeile ein String, Index 0 =
    // ASpan.StartLine. Spalte N der Sicht ist Spalte N der Quellzeile.
    // Strings sind VIEW_FILL; Kommentare und Direktiven (samt Begrenzern)
    // und alles ausserhalb des Bereichs sind Leerzeichen - ein Kommentar
    // trennt Code also wie Leerraum (Review reDelphiX 2026-10-07,
    // Minor 4). Die letzte Zeile endet bei ASpan.EndCol - 1. Leeres
    // Array, wenn der Bereich nicht in ALines passt.
    class function CodeViewOf(ALines: TStrings;
      const ASpan: TRefactorSpan): TArray<string>; static;

    // Wie CodeViewOf, aber im Zusammenhang der Datei gelesen: die Zeilen
    // vor dem Bereich und der Anfang seiner ersten Zeile laufen mit durch
    // den Scanner. Ein Kommentar oder String, der VOR dem Bereich beginnt,
    // gilt so auch darin (Review reDelphiX 2026-10-07, Nit 28: ein
    // Bereich mitten in '{ alt: ... }' lieferte bei CodeViewOf Code).
    // Fuer Bereiche aus FindStatementEnd ist das Ergebnis gleich - die
    // beginnen immer auf Code. Kosten: ein Lauf ueber die Zeilen davor.
    // Delphi-12-Mehrzeilenstrings davor kennt der Scanner nicht.
    class function CodeViewInContext(ALines: TStrings;
      const ASpan: TRefactorSpan): TArray<string>; static;

    // Roher Quelltext des Bereichs, Zeilen mit #10 verbunden. Leer, wenn
    // der Bereich nicht in ALines passt.
    class function SpanText(ALines: TStrings;
      const ASpan: TRefactorSpan): string; static;

    // SHA256 (hex) ueber SpanText. Leer bei leerem Text. Ein Konsument,
    // der vor dem Umschreiben pruefen will, ob die Datei seit dem Scan
    // geaendert wurde, ruft dieselbe Funktion und vergleicht.
    class function HashOfSpan(ALines: TStrings;
      const ASpan: TRefactorSpan): string; static;

    // True wenn eine Zeile aus [AFromLine, AToLine] in einem
    // {$IFDEF}-Bereich liegt (nkConditionalRange-Marker am Unit-Knoten:
    // Line = Start, TypeRef = Ende).
    class function InConditionalRange(AUnitNode: TAstNode;
      AFromLine, AToLine: Integer): Boolean; static;

    // Bezeichner-Zeichen in der Code-Sicht. Oeffentlich, damit ein
    // Zerleger auf der Sicht (uRefactorConcat) dieselbe Wortgrenze
    // benutzt wie die Suche nach dem Anweisungsende hier.
    class function IsIdentStart(C: Char): Boolean; static;
    class function IsIdentChar(C: Char): Boolean; static;
    // True, wenn im Bereich ein Kommentar steht (oder ein Blockkommentar
    // darin beginnt). Oeffentlich seit AH22: ein Modul, das nur einen
    // TEIL der Anweisung ersetzt, prueft genau diesen Teil.
    class function SpanHasComment(ALines: TStrings;
      const ASpan: TRefactorSpan): Boolean; static;
  private
    class function SpanFits(ALines: TStrings;
      const ASpan: TRefactorSpan): Boolean; static;
    // Code-Sicht EINER Zeile ab Spalte AFromCol, auf die Laenge der
    // Quellzeile aufgefuellt. AState traegt offene Blockkommentare weiter.
    class function LineView(const ALine: string; AFromCol: Integer;
      var AState: TCommentScanState): string; static;
    // AView ist ScanCodeLine(ASub, ..., VIEW_FILL, True), AState der
    // Kommentarzustand am Anfang von ASub (eine Kopie). Liefert AView mit
    // Leerzeichen an jeder VIEW_FILL-Spalte, die zu einem Kommentar
    // gehoert; Strings bleiben VIEW_FILL, Code bleibt Code.
    class function BlankComments(const ASub, AView: string;
      AState: TCommentScanState): string; static;
    class function FindStatementEnd(ALines: TStrings; ALine, ACol: Integer;
      out ASpan: TRefactorSpan; out AHasSemicolon: Boolean): Boolean; static;
    // True, wenn die Zeile ab AFromCol einen Delphi-12-Mehrzeilenstring
    // oeffnet: im Code (nicht in String oder Kommentar; AState ist der
    // Kommentarzustand am Zeilenanfang, eine Kopie) beginnt eine UNGERADE
    // Zahl von mindestens drei Apostrophen, hinter der nur noch Leerraum
    // steht - dieselbe Regel wie TRdxCodeMap.StepQuote im Modul.
    class function OpensMultiLineString(const ALine: string;
      AFromCol: Integer; AState: TCommentScanState): Boolean; static;
    // True wenn hinter dem Bereich auf seiner letzten Zeile kein Code mehr
    // steht (Leerraum und Kommentare zaehlen nicht).
    class function TailIsBlank(ALines: TStrings;
      const ASpan: TRefactorSpan): Boolean; static;
  end;

implementation

// noinspection-file BeginEndRequired, CyclomaticComplexity, DeepNesting, MultipleExit, UnusedPublicMember
// Zeichenweiser Scanner: die fruehen Ausstiege und die Verzweigung je
// Zeichenklasse sind hier die Sache selbst. CodeViewOf/SpanText/HashOfSpan
// sind fuer Detektoren und fuer reDelphix ausserhalb dieses Repos da.

uses
  System.SysUtils, System.Hash;

type
  // Rolle eines Wortes fuer die Suche nach dem Anweisungsende.
  TWordClass = (wcNone, wcOpener, wcEnd, wcTerminator);

const
  // ''' am Zeilenende oeffnet einen mehrzeiligen String (Delphi 12).
  MIN_MULTI_QUOTES = 3;

{ ---- Zeichen- und Wortklassen ---- }

function ClassifyWord(const ALowerWord: string): TWordClass;
// Dieselben Schluesselwoerter wie im RHS-Scan von
// uParser2.ParseCallOrAssign (tkKwBegin/Case/Try/Asm, tkKwEnd,
// tkKwElse/Until/Except/Finally).
begin
  Result := wcNone;
  if ALowerWord = 'end' then
    Result := wcEnd
  else if (ALowerWord = 'begin') or (ALowerWord = 'case')
       or (ALowerWord = 'try') or (ALowerWord = 'asm') then
    Result := wcOpener
  else if (ALowerWord = 'else') or (ALowerWord = 'until')
       or (ALowerWord = 'except') or (ALowerWord = 'finally') then
    Result := wcTerminator;
end;

class function TRefactorInfoBuilder.IsIdentStart(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_']) or (C > #127);
end;

class function TRefactorInfoBuilder.IsIdentChar(C: Char): Boolean;
begin
  Result := IsIdentStart(C) or CharInSet(C, ['0'..'9']);
end;

{ ---- Bereichs-Helfer ---- }

class function TRefactorInfoBuilder.SpanFits(ALines: TStrings;
  const ASpan: TRefactorSpan): Boolean;
begin
  Result := Assigned(ALines) and ASpan.IsValid
    and (ASpan.EndLine <= ALines.Count)
    and (ASpan.StartCol <= Length(ALines[ASpan.StartLine - 1]))
    and (ASpan.EndCol - 1 <= Length(ALines[ASpan.EndLine - 1]));
end;

class function TRefactorInfoBuilder.LineView(const ALine: string;
  AFromCol: Integer; var AState: TCommentScanState): string;
var
  Sub     : string;
  View    : string;
  Dummy   : Integer;
  StartSt : TCommentScanState;   // Kommentarzustand am Anfang von Sub
begin
  if AFromCol < 1 then AFromCol := 1;
  Sub  := Copy(ALine, AFromCol, MaxInt);
  StartSt := AState;
  View := TDetectorUtils.ScanCodeLine(Sub, AState, Dummy, VIEW_FILL, True);
  // Nur Strings bleiben VIEW_FILL, Kommentare werden Leerraum (Minor 4).
  View := BlankComments(Sub, View, StartSt);
  // ScanCodeLine schneidet einen Kommentar ab, der bis zum Zeilenende
  // laeuft. Auffuellen, damit die Sicht so lang ist wie die Quellzeile.
  Result := StringOfChar(' ', AFromCol - 1) + View
    + StringOfChar(' ', Length(Sub) - Length(View));
end;

class function TRefactorInfoBuilder.CodeViewOf(ALines: TStrings;
  const ASpan: TRefactorSpan): TArray<string>;
var
  State   : TCommentScanState;
  Li      : Integer;
  FromCol : Integer;
  View    : string;
begin
  Result := nil;
  if not SpanFits(ALines, ASpan) then Exit;
  State := Default(TCommentScanState);
  SetLength(Result, ASpan.EndLine - ASpan.StartLine + 1);
  for Li := ASpan.StartLine to ASpan.EndLine do
  begin
    FromCol := 1;
    if Li = ASpan.StartLine then FromCol := ASpan.StartCol;
    View := LineView(ALines[Li - 1], FromCol, State);
    if Li = ASpan.EndLine then
      View := Copy(View, 1, ASpan.EndCol - 1);
    Result[Li - ASpan.StartLine] := View;
  end;
end;

class function TRefactorInfoBuilder.CodeViewInContext(ALines: TStrings;
  const ASpan: TRefactorSpan): TArray<string>;
var
  State : TCommentScanState;
  Li    : Integer;
  View  : string;
begin
  Result := nil;
  if not SpanFits(ALines, ASpan) then Exit;
  State := Default(TCommentScanState);
  // Von den Zeilen davor zaehlt nur der Kommentarzustand, nicht die Sicht.
  for Li := 1 to ASpan.StartLine - 1 do
    LineView(ALines[Li - 1], 1, State);
  SetLength(Result, ASpan.EndLine - ASpan.StartLine + 1);
  for Li := ASpan.StartLine to ASpan.EndLine do
  begin
    // Auch die erste Zeile ab Spalte 1: ein String oder Kommentar, der
    // vor StartCol beginnt, reicht so in den Bereich hinein. Was davor
    // liegt, wird danach Leerraum - wie bei CodeViewOf.
    View := LineView(ALines[Li - 1], 1, State);
    if Li = ASpan.StartLine then
      View := StringOfChar(' ', ASpan.StartCol - 1)
        + Copy(View, ASpan.StartCol, MaxInt);
    if Li = ASpan.EndLine then
      View := Copy(View, 1, ASpan.EndCol - 1);
    Result[Li - ASpan.StartLine] := View;
  end;
end;

class function TRefactorInfoBuilder.SpanText(ALines: TStrings;
  const ASpan: TRefactorSpan): string;
var
  SB : TStringBuilder;
  Li : Integer;
begin
  Result := '';
  if not SpanFits(ALines, ASpan) then Exit;
  if ASpan.IsSingleLine then
    Exit(Copy(ALines[ASpan.StartLine - 1], ASpan.StartCol,
      ASpan.EndCol - ASpan.StartCol));
  SB := TStringBuilder.Create;
  try
    SB.Append(Copy(ALines[ASpan.StartLine - 1], ASpan.StartCol, MaxInt));
    for Li := ASpan.StartLine + 1 to ASpan.EndLine - 1 do
    begin
      SB.Append(#10);
      SB.Append(ALines[Li - 1]);
    end;
    SB.Append(#10);
    SB.Append(Copy(ALines[ASpan.EndLine - 1], 1, ASpan.EndCol - 1));
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TRefactorInfoBuilder.HashOfSpan(ALines: TStrings;
  const ASpan: TRefactorSpan): string;
var
  Text : string;
begin
  Result := '';
  Text := SpanText(ALines, ASpan);
  if Text <> '' then
    Result := THashSHA2.GetHashString(Text);
end;

class function TRefactorInfoBuilder.InConditionalRange(AUnitNode: TAstNode;
  AFromLine, AToLine: Integer): Boolean;
var
  i      : Integer;
  N      : TAstNode;
  RangeS : Integer;
  RangeE : Integer;
begin
  Result := False;
  if not Assigned(AUnitNode) then Exit;
  // Die Marker haengen direkt am Unit-Knoten (uParser2: Root.Add) - ein
  // Blick auf die Kinder reicht, kein Walk ueber den ganzen Baum.
  for i := 0 to AUnitNode.Children.Count - 1 do
  begin
    N := AUnitNode.Children[i];
    if N.Kind <> nkConditionalRange then Continue;
    RangeS := N.Line;
    RangeE := StrToIntDef(N.TypeRef, RangeS);
    if (AFromLine <= RangeE) and (AToLine >= RangeS) then
      Exit(True);
  end;
end;

class function TRefactorInfoBuilder.SpanHasComment(ALines: TStrings;
  const ASpan: TRefactorSpan): Boolean;
// Im NICHT spaltentreuen Modus ENTFERNT ScanCodeLine Kommentare, Strings
// ersetzt es 1:1. Ist das Ergebnis kuerzer als die Eingabe, stand in dem
// Stueck also ein Kommentar - ohne dass hier selbst gelext wird.
var
  State    : TCommentScanState;
  Li       : Integer;
  FromCol  : Integer;
  Len      : Integer;
  Sub      : string;
  Stripped : string;
  Dummy    : Integer;
begin
  // Keine Vorab-Zuweisung an Result: jeder Weg endet in Exit(True) oder
  // in der Zuweisung hinter der Schleife (dcc32 H2077 beim Bau 2026-10-04).
  State := Default(TCommentScanState);
  for Li := ASpan.StartLine to ASpan.EndLine do
  begin
    FromCol := 1;
    if Li = ASpan.StartLine then FromCol := ASpan.StartCol;
    Len := MaxInt;
    if Li = ASpan.EndLine then Len := ASpan.EndCol - FromCol;
    Sub := Copy(ALines[Li - 1], FromCol, Len);
    Stripped := TDetectorUtils.ScanCodeLine(Sub, State, Dummy, VIEW_FILL,
      False);
    if Length(Stripped) < Length(Sub) then
      Exit(True);
  end;
  // Nur ein Gurt: eine Zeile, die einen Blockkommentar OEFFNET, ist oben
  // schon kuerzer geworden (ScanCodeLine gibt den Oeffner nicht aus), der
  // getragene Zustand entscheidet hier nie allein (Review reDelphiX
  // 2026-10-07, strittiger Major 1).
  Result := State.InBraceComment or State.InParenComment;
end;

class function TRefactorInfoBuilder.TailIsBlank(ALines: TStrings;
  const ASpan: TRefactorSpan): Boolean;
var
  State : TCommentScanState;
  View  : string;
  Dummy : Integer;
  i     : Integer;
begin
  Result := True;
  State := Default(TCommentScanState);
  View := TDetectorUtils.ScanCodeLine(
    Copy(ALines[ASpan.EndLine - 1], ASpan.EndCol, MaxInt),
    State, Dummy, VIEW_FILL, True);
  for i := 1 to Length(View) do
    if (View[i] > ' ') and (View[i] <> VIEW_FILL) then
      Exit(False);
end;

{ ---- Anweisungsende ---- }

function PairAt(const ALine: string; AIdx: Integer; A, B: Char): Boolean;
// True, wenn an ALine[AIdx] (AIdx <= Length(ALine)) das Zeichenpaar AB
// beginnt.
begin
  Result := (ALine[AIdx] = A) and (AIdx < Length(ALine))
    and (ALine[AIdx + 1] = B);
end;

function StepInComment(const ALine: string; var AIdx: Integer;
  var AState: TCommentScanState): Boolean;
// Ein Schritt in einem Blockkommentar: AIdx rueckt um das Zeichen vor,
// bei '*)' um beide, und der Abschluss beendet den Kommentar. False
// ausserhalb eines Blockkommentars - dann bleibt alles unveraendert.
begin
  Result := AState.InBraceComment or AState.InParenComment;
  if not Result then Exit;
  if AState.InBraceComment then
    AState.InBraceComment := ALine[AIdx] <> '}'
  else if PairAt(ALine, AIdx, '*', ')') then
  begin
    AState.InParenComment := False;
    Inc(AIdx);
  end;
  Inc(AIdx);
end;

function StepInString(const ALine: string; var AIdx: Integer): Boolean;
// Ein Schritt in einem String: AIdx rueckt um das Zeichen vor, bei ''
// um beide (das verdoppelte Apostroph bleibt im String). False, wenn der
// String an AIdx endet.
begin
  Result := True;
  if PairAt(ALine, AIdx, '''', '''') then
    Inc(AIdx)
  else if ALine[AIdx] = '''' then
    Result := False;
  Inc(AIdx);
end;

function IsMultiLineOpener(const ALine: string; AIdx: Integer): Boolean;
// True, wenn an ALine[AIdx] ein Lauf von mindestens MIN_MULTI_QUOTES
// Apostrophen beginnt, ihre Zahl ungerade ist und dahinter nur noch
// Leerraum steht.
var
  q : Integer;
begin
  q := 0;
  while (AIdx + q <= Length(ALine)) and (ALine[AIdx + q] = '''') do Inc(q);
  Result := (q >= MIN_MULTI_QUOTES) and Odd(q)
    and (Trim(Copy(ALine, AIdx + q, MaxInt)) = '');
end;

procedure NoteCommentOpener(const ALine: string; var AIdx: Integer;
  var AState: TCommentScanState);
// Im Code: '{' bzw. '(*' an AIdx oeffnet einen Blockkommentar; bei '(*'
// rueckt AIdx auf den Stern.
begin
  if ALine[AIdx] = '{' then
    AState.InBraceComment := True
  else if PairAt(ALine, AIdx, '(', '*') then
  begin
    AState.InParenComment := True;
    Inc(AIdx);
  end;
end;

procedure BlankFillRange(var AView: string; AFrom, ATo: Integer);
// Spalten AFrom..ATo der Sicht, die VIEW_FILL tragen, werden Leerzeichen.
// Spalten hinter dem Ende der Sicht (ScanCodeLine schneidet einen bis zum
// Zeilenende offenen Kommentar ab) gibt es nicht - LineView fuellt sie
// ohnehin mit Leerzeichen auf.
var
  k : Integer;
begin
  for k := AFrom to ATo do
    if (k >= 1) and (k <= Length(AView))
       and (AView[k] = TRefactorInfoBuilder.VIEW_FILL) then
      AView[k] := ' ';
end;

class function TRefactorInfoBuilder.BlankComments(const ASub, AView: string;
  AState: TCommentScanState): string;
// Derselbe Gang wie OpensMultiLineString (und ScanCodeLine): in einem
// Kommentar, dann im String, dann Apostroph, '//', Kommentar-Oeffner.
// Jede Spalte, die dabei zu einem Kommentar zaehlt - Begrenzer
// eingeschlossen -, wird in der Sicht Leerraum.
var
  j     : Integer;
  From  : Integer;
  InStr : Boolean;
begin
  Result := AView;
  InStr := False;
  j := 1;
  while j <= Length(ASub) do
  begin
    From := j;
    if StepInComment(ASub, j, AState) then
    begin
      BlankFillRange(Result, From, j - 1);   // ein Zeichen bzw. '*)'
      Continue;
    end;
    if InStr then
    begin
      InStr := StepInString(ASub, j);
      Continue;
    end;
    if ASub[j] = '''' then
      InStr := True
    else if PairAt(ASub, j, '/', '/') then
      Exit                    // Rest: von ScanCodeLine abgeschnitten
    else
    begin
      NoteCommentOpener(ASub, j, AState);
      if AState.InBraceComment or AState.InParenComment then
        BlankFillRange(Result, From, j);     // '{' bzw. '(*'
    end;
    Inc(j);
  end;
end;

function StartsOnCode(ALines: TStrings; ALine, ACol: Integer): Boolean;
// Die Startposition (1-basiert) liegt in ALines und zeigt auf Code, nicht
// auf Leerraum.
begin
  Result := Assigned(ALines)
    and (ALine >= 1) and (ALine <= ALines.Count)
    and (ACol >= 1) and (ACol <= Length(ALines[ALine - 1]))
    and (ALines[ALine - 1][ACol] > ' ');
end;

class function TRefactorInfoBuilder.OpensMultiLineString(const ALine: string;
  AFromCol: Integer; AState: TCommentScanState): Boolean;
// Dieselbe Quote- und Kommentarlogik wie ScanCodeLine ('' im String,
// '{ }', '(* *)', '//'), nur zaehlt hier der Lauf der Apostrophe, an dem
// im Code ein String beginnt. Die Schritte je Zustand stehen in den
// Helfern oben (StepInComment, StepInString, NoteCommentOpener).
var
  j     : Integer;
  InStr : Boolean;
begin
  Result := False;
  InStr := False;
  j := AFromCol;
  if j < 1 then j := 1;
  while j <= Length(ALine) do
  begin
    if StepInComment(ALine, j, AState) then Continue;
    if InStr then
    begin
      InStr := StepInString(ALine, j);
      Continue;
    end;
    if ALine[j] = '''' then
    begin
      if IsMultiLineOpener(ALine, j) then Exit(True);
      // Gewoehnlicher String: der Rest des Laufs ist '' bzw. das Ende.
      InStr := True;
    end
    else if PairAt(ALine, j, '/', '/') then
      Exit                    // Rest der Zeile ist Kommentar
    else
      NoteCommentOpener(ALine, j, AState);
    Inc(j);
  end;
end;

class function TRefactorInfoBuilder.FindStatementEnd(ALines: TStrings;
  ALine, ACol: Integer; out ASpan: TRefactorSpan;
  out AHasSemicolon: Boolean): Boolean;
var
  State    : TCommentScanState;
  LineSt   : TCommentScanState;   // Kommentarzustand am Zeilenanfang
  Li       : Integer;
  FromCol  : Integer;
  LastLine : Integer;
  J, K     : Integer;
  View     : string;
  C        : Char;
  PrevSig  : Char;      // letztes signifikantes Zeichen davor
  Depth    : Integer;
  SigLine  : Integer;   // Position des letzten signifikanten Zeichens
  SigCol   : Integer;
  WordCls  : TWordClass;

  // Abschluss OHNE ';': der Bereich endet hinter dem letzten
  // signifikanten Zeichen vor dem Schluesselwort.
  function FinishBeforeKeyword: Boolean;
  begin
    Result := SigLine > 0;
    if Result then
      ASpan := TRefactorSpan.Make(ROLE_STATEMENT, ALine, ACol,
        SigLine, SigCol + 1);
  end;

begin
  Result := False;
  AHasSemicolon := False;
  ASpan := Default(TRefactorSpan);
  if not StartsOnCode(ALines, ALine, ACol) then Exit;

  State    := Default(TCommentScanState);
  Depth    := 0;
  SigLine  := 0;
  SigCol   := 0;
  PrevSig  := #0;
  LastLine := ALine + MAX_STATEMENT_LINES - 1;
  if LastLine > ALines.Count then LastLine := ALines.Count;

  for Li := ALine to LastLine do
  begin
    FromCol := 1;
    if Li = ALine then FromCol := ACol;
    J := FromCol;
    LineSt := State;
    View := LineView(ALines[Li - 1], J, State);
    while J <= Length(View) do
    begin
      C := View[J];
      if C <= ' ' then
      begin
        Inc(J);
        Continue;
      end;

      if IsIdentStart(C) then
      begin
        K := J;
        while (K <= Length(View)) and IsIdentChar(View[K]) do Inc(K);
        // Hinter '.', '&', '$', '#' ist ein Wort kein Schluesselwort
        // (Member-Zugriff, escapter Bezeichner, Hex-/Zeichen-Literal).
        WordCls := wcNone;
        if not CharInSet(PrevSig, ['.', '&', '$', '#']) then
          WordCls := ClassifyWord(LowerCase(Copy(View, J, K - J)));
        case WordCls of
          wcOpener:
            Inc(Depth);
          wcEnd:
            if Depth > 0 then Dec(Depth)
            else Exit(FinishBeforeKeyword);
          wcTerminator:
            if Depth = 0 then Exit(FinishBeforeKeyword);
        end;
        SigLine := Li;
        SigCol  := K - 1;
        PrevSig := View[K - 1];
        J := K;
        Continue;
      end;

      case C of
        '(', '[':
          Inc(Depth);
        ')', ']':
          begin
            // Schliessende Klammer ohne oeffnende: die Startposition lag
            // IN einem Klammerausdruck - das ist keine Anweisung.
            if Depth = 0 then Exit;
            Dec(Depth);
          end;
        ';':
          if Depth = 0 then
          begin
            ASpan := TRefactorSpan.Make(ROLE_STATEMENT, ALine, ACol,
              Li, J + 1);
            AHasSemicolon := True;
            Exit(True);
          end;
      end;
      SigLine := Li;
      SigCol  := J;
      PrevSig := C;
      Inc(J);
    end;
    // Die Anweisung laeuft ueber diese Zeile hinaus. Oeffnet die Zeile
    // einen Mehrzeilenstring, waeren die Folgezeilen fuer die Code-Sicht
    // Code - ihr Ende ist dann nicht sauber bestimmbar (s. Kopf).
    if OpensMultiLineString(ALines[Li - 1], FromCol, LineSt) then Exit;
  end;
  // Kein Abschluss innerhalb der Obergrenze bzw. bis Dateiende: nil.
end;

{ ---- Oeffentlicher Einstieg ---- }

class function TRefactorInfoBuilder.TryBuildForStatement(AUnitNode: TAstNode;
  ALines: TStrings; ALine, ACol: Integer): TRefactorInfo;
var
  Span         : TRefactorSpan;
  HasSemicolon : Boolean;
  Flags        : TRefactorFlags;
  InsertLine   : Integer;
  InsertIndent : Integer;
  Hash         : string;
begin
  Result := nil;
  if not FindStatementEnd(ALines, ALine, ACol, Span, HasSemicolon) then Exit;
  if not SpanFits(ALines, Span) then Exit;

  // B5 - Kontext-Flags. rfFromInclude wird nie gesetzt: der Core loest
  // {$INCLUDE} nicht in den Token-Strom auf, ein Fund kann nicht aus
  // einer Include-Datei stammen.
  Flags := [];
  if not Span.IsSingleLine then
    Include(Flags, rfMultiLine);
  if SpanHasComment(ALines, Span) then
    Include(Flags, rfHasComment);
  if InConditionalRange(AUnitNode, Span.StartLine, Span.EndLine) then
    Include(Flags, rfInConditional);

  // B6 - Einfuegepunkt. Nur wenn die Anweisung mit ';' endet, ALLEIN auf
  // ihren Zeilen steht (nur Leerraum davor, kein Code dahinter): dann
  // laesst sich dahinter eine eigene Zeile einfuegen, ohne eine fremde
  // Anweisung zu zerteilen. Sonst 0 = kein Einfuegepunkt.
  InsertLine   := 0;
  InsertIndent := 0;
  if HasSemicolon
     and (Trim(Copy(ALines[Span.StartLine - 1], 1, Span.StartCol - 1)) = '')
     and TailIsBlank(ALines, Span) then
  begin
    InsertLine   := Span.EndLine + 1;
    InsertIndent := Span.StartCol - 1;
  end;

  // B7 - Hash ueber den rohen Bereichstext.
  Hash := HashOfSpan(ALines, Span);

  Result := TRefactorInfo.Create;
  Result.Span         := Span;
  Result.Flags        := Flags;
  Result.InsertLine   := InsertLine;
  Result.InsertIndent := InsertIndent;
  Result.SpanHash     := Hash;
end;

end.

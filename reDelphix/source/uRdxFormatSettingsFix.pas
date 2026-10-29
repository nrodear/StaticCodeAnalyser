unit uRdxFormatSettingsFix;

// reDelphix - Editorhilfen zu SCA128 DateFormatSettings und SCA059
// FormatLocaleHint, OHNE ToolsAPI und ohne Parser, nur auf der Code-Sicht
// (TRdxCodeMap). Reine Textlogik in der Form TRdxMapPlanner; die Adapter
// fuer uRdxFixTable (MapFix) stehen NICHT hier (Hausregel uRdxFixTable) -
// die Unit bindet nur uRdxCodeMap, uRdxBufferMath, uRdxText, uRefactorInfo,
// uRdxCompilerTraces und System.* und laeuft so auch unter FPC.
//
// Beide Regeln, eine Umformung: das TFormatSettings-Argument der RTL-
// Ueberladung anhaengen.
//   Hauptweg  ', FormatSettings' - gleiche Bedeutung: die Ueberladung ohne
//             Settings liest die globale Variable SysUtils.FormatSettings
//             (RTL 23.0/37.0 belegt; FPC 3.2.2: FormatSettings absolute
//             DefaultFormatSettings). Der Aufruf wird nur ausdruecklich.
//   Alt-Weg   ', TFormatSettings.Invariant' - aendert das Verhalten: Punkt
//             als Dezimaltrenner, englische Namen, US-Datumsformat.
// TFormatSettings ist bei allen Funktionen der LETZTE Parameter; die Form
// ohne Settings hat
//   1 Argument  StrToDate, StrToTime, StrToDateTime, DateToStr, TimeToStr,
//               DateTimeToStr, StrToFloat, StrToCurr, FloatToStr, CurrToStr
//   2 Argumente FormatDateTime, FormatFloat, FormatCurr, Format (SCA059)
// (Delphi: System.SysUtils der Studios 23.0 und 37.0; FPC 3.2.2: sysstrh.inc
// und datih.inc). Ein Aufruf mit anderer Argumentzahl ist eine andere
// Ueberladung (FPC: StrToDate(S, Separator), DateTimeToStr(D, True),
// FormatDateTime(F, D, Options)) - keine Hilfe.
//
// Was die Detektoren melden:
//   SCA128 (uDateFormatSettings): je Anweisung (nkCall-Name bzw. nkAssign-
//     RHS) den ERSTEN Namen der Liste, der im gestrippten Text als ganzes
//     Wort steht (nicht hinter '@') - nach Listen-Reihenfolge, nicht nach
//     Position; still, sobald 'formatsettings' oder 'fmtsettings' irgendwo
//     im Text steht. Meldung '<name klein> called without explicit
//     TFormatSettings - depends on system locale', Zeile der Anweisung.
//     Weil EIN Settings-Argument die ganze Anweisung stumm schaltet, setzt
//     die Hilfe es an JEDEN Aufruf der Liste der Anweisung (eine Ersetzung)
//     - bis zum Realworld-Test rwE30 Stufe 2 nur auf der Fundzeile, und ein
//     Aufruf auf einer Folgezeile sperrte (R_FS_CONTINUES, R_FS_NEXT_LINE);
//     seitdem kommen die Aufrufe der Folgezeilen mit (FollowNames:
//     MainControllerU.pas:47, wbLOD.pas:3082).
//   SCA059 (uFormatMismatch): den ersten 'format(' der Anweisung mit
//     Float-Spec (%f %g %e %m %n) und hoechstens zwei Argumenten. Meldung
//     'Format: float spec <Formatstring> without TFormatSettings - ...';
//     der Formatstring ist der aufgeloeste Wert (bei einer Konstanten deren
//     Inhalt) - die Gegenprobe vergleicht ihn, wenn das erste Argument auf
//     der Zeile ein Literal ist.
//
// GRUNDSATZ wie in uRdxLineFixes: lieber keine Hilfe als eine falsche. Keine
// Hilfe, wenn
//   * die Meldung den Namen bzw. Formatstring nicht nennt, die Anweisung ihn
//     nicht (mehr) als Aufruf auf den Code-Spalten traegt (verschoben,
//     Kommentar, String);
//   * der Aufruf qualifiziert ist (nur 'SysUtils.' und 'System.SysUtils.'
//     sind die RTL), seine Klammer nicht innerhalb von MAX_CALL_LINES Zeilen
//     schliesst bzw. dazwischen eine Direktive oder ein zeilenuebergreifender
//     Kommentar/String steht (bis rwE30 Stufe 2 musste sie auf der Zeile
//     schliessen: MainFormU.pas:1471, WrapFmxTypes.pas:391) oder eine andere
//     Zahl von Argumenten traegt; SCA059: mehr als ein Format in der
//     Anweisung;
//   * auf der Zeile bzw. zwischen Fundzeile und letztem Aufruf eine
//     Direktive steht;
//   * SysUtils in keiner uses-Klausel steht, die Datei eine eigene Routine
//     des Namens deklariert, ein with in der Routine den Aufruf umfasst (die
//     Namen koennten an einen Member binden; seit rwE30 Stufe 2 zaehlt ein
//     with, dessen Anweisung vor dem Aufruf endet, nicht mehr -
//     WithEndsBefore);
//   * Hauptweg: die Datei nach Compilern vor Delphi XE fragt (die globale
//     Variable gibt es erst seit XE; FPC vor 2.6) - ausser sie beweist
//     selbst einen neueren (uRdxCompilerTraces.ModernProof). Deklariert die
//     Datei einen Bezeichner FormatSettings (Feld, Variable, Parameter,
//     Property) oder nutzt sie ihn als Member, bande der blosse Name dort:
//     seit rwE30 Stufe 2 steht dann die globale Variable qualifiziert da
//     (', System.SysUtils.FormatSettings' in der Schreibweise der uses-
//     Klausel - dieselbe Variable; bis dahin sperrte das);
//   * Alt-Weg: die Datei eine FPC-Weiche oder einen FPC-Modus traegt (FPC
//     3.2.2 kennt kein TFormatSettings.Invariant) - ausser alle Aufrufe
//     stehen in einem Zweig ohne FPC ('{$IF NOT DEFINED(FPC)}') -, nach
//     Compilern bis Delphi 10.3 fragt (belegt ist Invariant in den Docwiki-
//     Staenden ab Rio - dieselbe Schwelle wie SCA014, FLOOR_INLINE_DECL) -
//     beides nicht, wenn die Datei eine Inline-Variable oder Invariant selbst
//     ohne Weiche nutzt (rwE30 Stufe 2) -, ein eigenes TFormatSettings
//     deklariert, die globale FormatSettings fuer Datum/Uhrzeit selbst
//     einstellt (Invariant liefe daran vorbei; rwE30 Stufe 2, HeidiSQL);
//     SCA059 dazu bei einer Waehrungs-Spec m (Invariant schreibt das
//     allgemeine Waehrungszeichen); SCA128, wenn ein Lese-Aufruf (StrToDate,
//     StrToTime, StrToDateTime, StrToFloat, StrToCurr) ein Literal liest,
//     das nicht zum Invariant-Format passt (rwE29: StrToDateTime('17/02/2017
//     16:37:50') - Monat 17, sicherer EConvertError; LiteralMisfit; reine
//     Zeit-Literale bei StrToTime sperren nicht - Review e/HilfeFixC), bzw.
//     die Anweisung ein Literal traegt, mit dem ein schreibender Aufruf
//     verglichen wird und das Invariant nicht schreibt ('5,5', '29.10.2026';
//     rwE30 Stufe 2, horse Tests.Horse.Core.Param.pas:292 -
//     CompareLiteralReason).
// Ruft die Datei eine weitere Routine derselben Familie (Datum/Uhrzeit bzw.
// Zahl, auch Try..., ...Def) ohne Invariant, koennte ein Paar aus Schreiben
// und Lesen bzw. Vergleich brechen (rwE29: HeidiSQL main.pas). Das SPERRT
// NICHT (Entscheid Nico nach dem Review e/HilfeFixC, M2 - der Alt-Weg ist
// ohnehin als aendernd gekennzeichnet und nie per Taste): der Hinweis nennt
// das Gegenstueck (PairHint, PairBreakLine) - seit rwE30 Stufe 2 zuerst
// eines in derselben Routine (HeidiSQL main.pas:14718).
// Was nur die Platte weiss (Projektdateien, Includes), prueft der Adapter
// in uRdxFixTable (FormatSettingsDiskCheck, rwE29).
// Der Bereich der Ersetzung beginnt hinter dem letzten Zeichen des letzten
// Arguments (nie auf einer leeren Zeile; steht die Klammer tiefer, auf dem
// letzten Zeichen davor) und endet hinter der letzten schliessenden
// Klammer; Leerraum und Kommentar vor der Klammer bleiben dahinter. Er darf
// seit rwE30 Stufe 2 ueber Zeilen gehen (BuildEdit).

interface

uses
  uRdxBufferMath,     // TRdxEdit
  uRdxCodeMap;        // TRdxCodeMap

const
  // Die Gruende als englische msgids (E29); die Tests vergleichen mit _().
  R_FS_NO_NAME = 'the message names none of the locale-dependent RTL '
    + 'functions of SCA128';
  R_FS_MOVED = 'no call of %s on the code columns of the reported line';

  R_FS_NOT_CALL = '%s stands without an argument list - no call';
  R_FS_QUALIFIED = '%s is called as %s - another routine than the one of '
    + 'SysUtils';
  // Seit rwE30 Stufe 2 darf die Klammer bis MAX_CALL_LINES Zeilen tiefer
  // schliessen (ReadCall) - ohne Direktive und ohne Zeile, die in einem
  // Kommentar oder mehrzeiligen String beginnt (R_FS_CALL_BREAK).
  R_FS_OPEN = 'the call of %s does not close within %d lines';
  R_FS_CALL_BREAK = 'the call of %s runs from line %d to line %d across a '
    + 'compiler directive or a comment or string spanning lines';
  R_FS_ARITY = '%s carries %d arguments here, the RTL form without '
    + 'TFormatSettings has %d';
  R_FS_DIRECTIVE = 'a compiler directive stands on the reported line';
  R_FS_CONTINUES = 'the statement continues on line %d with another such '
    + 'call - it would stay unchanged and unreported; by hand';
  R_FS_NO_SYSUTILS = 'SysUtils is in no uses clause of the file - the call '
    + 'need not bind to the RTL';
  R_FS_OWN_ROUTINE = 'the file declares its own routine %s - the call need '
    + 'not bind to the RTL';

  R_FS_WITH = 'a with statement stands before the call in its routine (line '
    + '%d) - the names could bind to a member';
  R_FS_OLD_VAR = 'the file asks for old compilers (%s, line %d) - the global '
    + 'variable FormatSettings exists from Delphi XE on';
  R_FS_FPC = 'the file is also written for FPC (line %d) - FPC 3.2 knows no '
    + 'TFormatSettings.Invariant';
  R_FS_OLD_INVARIANT = 'the file asks for compilers up to Delphi 10.3 (%s, '
    + 'line %d) - TFormatSettings.Invariant is only checked from there on';
  R_FS_OWN_TYPE = 'the file declares its own TFormatSettings (line %d)';
  // Alt-Weg (rwE30 Stufe 2): die Datei stellt die globale FormatSettings
  // selbst ein - %s das Feld, %d die Zeile.
  R_FS_SETTINGS_SET = 'the file sets the global FormatSettings itself (%s, '
    + 'line %d) - TFormatSettings.Invariant would bypass these settings';
  // Alt-Weg (rwE30 Stufe 2): ein Literal der Anweisung, mit dem das Ergebnis
  // verglichen wird - %s das Literal (mit Quotes), %s der Aufruf.
  R_FS_LIT_COMPARE = 'the statement also carries the literal %s - with '
    + 'TFormatSettings.Invariant %s writes another format (decimal point, '
    + 'MM/dd/yyyy), a comparison with the literal would fail';
  // Alt-Weg (rwE29): das Literal, das der Aufruf liest, passt nicht zu
  // TFormatSettings.Invariant - %s das Literal (mit Quotes), %s der Aufruf.
  R_FS_LIT_DATE = 'the literal %s does not fit the date and time format of '
    + 'TFormatSettings.Invariant (MM/dd/yyyy hh:nn:ss) - %s would raise '
    + 'EConvertError';
  R_FS_LIT_NUMBER = 'the literal %s does not fit the number format of '
    + 'TFormatSettings.Invariant (decimal point, no thousands separator) - %s '
    + 'would raise EConvertError';
  // Alt-Weg (rwE29, Paar-Bruch, Entscheid M2): der Hinweis mit dem
  // Gegenstueck - %s der Hinweis des Adapters (schon uebersetzt), %d die
  // Zeile, %s der Aufruf dort.
  R_FS_PAIR_HINT = '%s; line %d calls %s of the same family without '
    + 'TFormatSettings.Invariant - change it along with this one, otherwise '
    + 'values written there and read or compared here (or the other way '
    + 'round) no longer match';
  R_FL_NO_SPEC = 'the message does not name the format string - analyse the '
    + 'file again';
  R_FL_NO_FORMAT = 'no Format call on the code columns of the reported line';
  R_FL_MANY = 'line %d carries %d calls of Format - ambiguous';
  R_FL_OTHER_FMT = 'the Format call on the line has another format string '
    + 'than the finding';
  R_FL_MONEY = 'the format string has a currency spec (m) - '
    + 'TFormatSettings.Invariant writes the generic currency sign instead of '
    + 'the local one';

type
  // Die Planer (Form TRdxMapPlanner, uRdxFixRunner) und ihre Leser.
  TRdxFormatSettingsFix = class
  public
    // SCA128, Hauptweg: ', FormatSettings' an jeden Aufruf der Liste auf
    // ALine (eine Ersetzung).
    class function DateFormatSettings(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
    // SCA128, Alt-Weg: ', TFormatSettings.Invariant'.
    class function DateFormatInvariant(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
    // SCA059, Hauptweg: drittes Argument ', FormatSettings' an das eine
    // Format auf ALine.
    class function FormatLocale(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
    // SCA059, Alt-Weg: ', TFormatSettings.Invariant'.
    class function FormatLocaleInvariant(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // Der Funktionsname der SCA128-Meldung, klein ('datetostr'); '' ohne
    // bekannten Namen.
    class function CalledNameOf(const AMessage: string): string; static;
    // Der Formatstring der SCA059-Meldung; False ohne diese Form.
    class function FloatSpecOf(const AMessage: string;
      out AFormat: string): Boolean; static;
    // Traegt der Formatstring eine Waehrungs-Spec ('%m', '%.2m', '%0:m')?
    class function HasMoneySpec(const AFormat: string): Boolean; static;
    // SCA128, Alt-Weg (Entscheid M2): ABaseHint, oder - ruft die Datei
    // ausser den Aufrufen der Liste auf ALine eine Routine derselben
    // Familie ohne Invariant - R_FS_PAIR_HINT mit ABaseHint, Zeile und Name
    // des ersten solchen Aufrufs. Liest die Zeile keinen Aufruf, ABaseHint.
    class function PairHint(AMap: TRdxCodeMap; ALine: Integer;
      const ABaseHint: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,        // TRefactorSpan.Make
  uRdxText,             // _(), MsgMovedSuffix (E29, nie uLocalization)
  uRdxRecipes,          // TRdxRecipes.LineLooksFpcAware (FpcTellLine)
  uRdxBlocks,           // BeginBodyAround (PairBreakLine, rwE30 Stufe 2)
  uRdxCompilerTraces;   // OldCompilerTrace, FLOOR_SETTINGS_VAR, FLOOR_INLINE_DECL

const
  SPAN_128 = 'sca128';
  SPAN_059 = 'sca059';
  INSERT_GLOBAL    = ', FormatSettings';
  INSERT_INVARIANT = ', TFormatSettings.Invariant';
  // Die Liste des Detektors uDateFormatSettings (LOCALE_DEPENDENT), klein,
  // und je Name die Argumentzahl der Form OHNE TFormatSettings.
  LOCALE_FUNCS: array[0..12] of string = ('strtodate', 'strtotime',
    'strtodatetime', 'datetostr', 'timetostr', 'datetimetostr', 'strtofloat',
    'strtocurr', 'floattostr', 'currtostr', 'formatdatetime', 'formatfloat',
    'formatcurr');
  LOCALE_ARITY: array[0..12] of Integer = (1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2,
    2, 2);
  FORMAT_FUNCS: array[0..0] of string = ('format');
  FORMAT_ARITY = 2;
  // Die Meldungen der Detektoren (Format-Texte dort).
  CALLED_MARK = ' called without explicit TFormatSettings';
  SPEC_PREFIX = 'Format: float spec ';
  SPEC_SUFFIX = ' without TFormatSettings - locale-dependent (comma vs. dot '
    + 'decimal separator)';
  NAME_SETTINGS      = 'formatsettings';
  NAME_SETTINGS_TYPE = 'tformatsettings';
  NAME_USES          = 'uses';
  QUAL_UNIT  = 'sysutils';
  QUAL_SCOPE = 'system';
  // Letztes Token einer Zeile, hinter dem die Anweisung zu Ende ist ...
  STATEMENT_DONE: array[0..10] of string = (';', 'then', 'do', 'begin',
    'else', 'try', 'finally', 'except', 'repeat', 'of', 'end');
  // ... und Schluesselwoerter, an denen die Suche auf Folgezeilen endet.
  STATEMENT_STOP: array[0..9] of string = ('then', 'do', 'begin', 'else',
    'end', 'until', 'except', 'finally', 'of', 'try');
  // Hier endet die Rueckwaertssuche nach with (Unit-Abschnitte).
  SCOPE_STOPS: array[0..3] of string = ('implementation', 'initialization',
    'finalization', 'interface');
  MAX_FOLLOW_LINES = 30;
  // So tief darf die Klammer eines Aufrufs schliessen (ReadCall) und so
  // weit liest WithEndsBefore die Anweisung eines with.
  MAX_CALL_LINES = 10;
  MAX_WITH_TOKENS = 5000;
  // Was ein Ergebnis schreibt, das mit einem Literal verglichen werden
  // koennte (CompareLiteralReason, Alt-Weg).
  NUMBER_WRITERS: array[0..3] of string = ('floattostr', 'currtostr',
    'formatfloat', 'formatcurr');
  DATE_WRITERS: array[0..3] of string = ('datetostr', 'timetostr',
    'datetimetostr', 'formatdatetime');
  // Was ein Literal liest (LiteralMisfit, Alt-Weg): Zahl bzw. Datum/Uhrzeit.
  PARSE_NUMBER: array[0..1] of string = ('strtofloat', 'strtocurr');
  PARSE_DATE     = 'strtodate';
  PARSE_TIME     = 'strtotime';
  PARSE_DATETIME = 'strtodatetime';
  MISFIT_NUMBER  = 'number';
  MISFIT_DATE    = 'date';
  // Paar-Bruch (PairBreakLine, Alt-Weg, rwE29): die Familien der RTL-
  // Routinen, die Datum/Uhrzeit bzw. Zahlen nach FormatSettings schreiben
  // oder lesen - auch die ohne Fund (Try..., ...Def, ...F). Format gehoert
  // nicht dazu (fast jede Datei ruft es fuer Text).
  PAIR_DATE: array[0..13] of string = ('strtodate', 'strtotime',
    'strtodatetime', 'datetostr', 'timetostr', 'datetimetostr',
    'formatdatetime', 'trystrtodate', 'trystrtotime', 'trystrtodatetime',
    'strtodatedef', 'strtotimedef', 'strtodatetimedef', 'datetimetostring');
  PAIR_NUMBER: array[0..13] of string = ('strtofloat', 'strtocurr',
    'floattostr', 'currtostr', 'formatfloat', 'formatcurr', 'trystrtofloat',
    'trystrtocurr', 'strtofloatdef', 'strtocurrdef', 'floattostrf',
    'currtostrf', 'floattotext', 'texttofloat');
  // Davor schneidet die Zeilen-Vorpruefung von PairBreakLine (klein).
  PAIR_DATE_HINTS: array[0..1] of string = ('date', 'time');
  PAIR_NUMBER_HINTS: array[0..2] of string = ('float', 'curr', 'text');
  NAME_INVARIANT = 'invariant';
  MAX_PAIR_ARG_LINES = 10;
  // Die globale Variable FormatSettings: FLOOR_SETTINGS_VAR (Delphi XE, FPC
  // ab 2.6; seit rwE29 in uRdxCompilerTraces). Wer nach XE fragt, baut auch
  // davor.

type
  // Ein Aufruf: Name, Klammern und die Stelle (Zeile, Spalte), vor der das
  // Argument eingefuegt wird (hinter dem letzten Zeichen des letzten
  // Arguments - seit rwE30 Stufe 2 auch auf einer Folgezeile).
  TCallSite = record
    Name    : TRdxToken;
    Open    : TRdxToken;
    Close   : TRdxToken;
    InsLine : Integer;
    InsAt   : Integer;
  end;
  TCallSites = array of TCallSite;

function LocaleIndex(const ALow: string): Integer;
var
  i : Integer;
begin
  for i := Low(LOCALE_FUNCS) to High(LOCALE_FUNCS) do
    if LOCALE_FUNCS[i] = ALow then
      Exit(i);
  Result := -1;
end;

// Das letzte Code-Token von ALine; leer ohne.
function LastTokenOn(AMap: TRdxCodeMap; ALine: Integer): TRdxToken;
var
  T : TRdxToken;
begin
  Result := Default(TRdxToken);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    Result := T;
    T := After(AMap, T);
  end;
end;

// Die Woerter aus ANames auf den Code-Spalten von ALine, nicht hinter '@'
// (Funktionszeiger - der Detektor schweigt dort auch).
function NamesOnLine(AMap: TRdxCodeMap; ALine: Integer;
  const ANames: array of string): TArray<TRdxToken>;
var
  T : TRdxToken;
begin
  Result := nil;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if T.IsWord and InList(T.Low, ANames) and (Before(AMap, T).Low <> '@') then
      AddToken(Result, T);
    T := After(AMap, T);
  end;
end;

// Setzt sich die Anweisung von ALine auf Folgezeilen fort und nennt dort
// eines der Woerter ANames (nicht hinter '@')? Die Zeile des Treffers, 0
// ohne. Die Anweisung endet am ';' bzw. an einem Schluesselwort aus
// STATEMENT_STOP; gesucht wird hoechstens MAX_FOLLOW_LINES Zeilen weit.
function FollowLineWith(AMap: TRdxCodeMap; ALine: Integer;
  const ANames: array of string): Integer;
var
  T, P : TRdxToken;
begin
  Result := 0;
  T := LastTokenOn(AMap, ALine);
  if (T.Low = '') or InList(T.Low, STATEMENT_DONE) then
    Exit;
  P := T;
  T := After(AMap, T);
  while (T.Low <> '') and (T.Line - ALine <= MAX_FOLLOW_LINES) do
  begin
    if T.Low = ';' then
      Exit;
    if IsKeywordAfter(T, P) and InList(T.Low, STATEMENT_STOP) then
      Exit;
    if T.IsWord and InList(T.Low, ANames) and (P.Low <> '@') then
      Exit(T.Line);
    P := T;
    T := After(AMap, T);
  end;
end;

// Die Woerter ANames (nicht hinter '@') auf den Folgezeilen der Anweisung
// von ALine - dieselbe Grenze wie FollowLineWith (';', ein Schluesselwort
// aus STATEMENT_STOP, MAX_FOLLOW_LINES). Seit rwE30 Stufe 2 bearbeitet die
// Hilfe sie mit (Planer kennt die Aufrufzeile; MainControllerU.pas:47,
// wbLOD.pas:3082), statt abzulehnen.
function FollowNames(AMap: TRdxCodeMap; ALine: Integer;
  const ANames: array of string): TArray<TRdxToken>;
var
  T, P : TRdxToken;
begin
  Result := nil;
  T := LastTokenOn(AMap, ALine);
  if (T.Low = '') or InList(T.Low, STATEMENT_DONE) then
    Exit;
  P := T;
  T := After(AMap, T);
  while (T.Low <> '') and (T.Line - ALine <= MAX_FOLLOW_LINES) do
  begin
    if T.Low = ';' then
      Exit;
    if IsKeywordAfter(T, P) and InList(T.Low, STATEMENT_STOP) then
      Exit;
    if T.IsWord and InList(T.Low, ANames) and (P.Low <> '@') then
      AddToken(Result, T);
    P := T;
    T := After(AMap, T);
  end;
end;

// Steht vor ADot genau 'SysUtils' bzw. 'System.SysUtils' (davor kein
// weiteres Glied)? Dann ist der qualifizierte Aufruf die RTL.
function RtlQualified(AMap: TRdxCodeMap; const ADot: TRdxToken): Boolean;
var
  U, P : TRdxToken;
begin
  Result := False;
  U := Before(AMap, ADot);
  if U.Low <> QUAL_UNIT then
    Exit;
  P := Before(AMap, U);
  if P.Low <> '.' then
    Exit(True);
  P := Before(AMap, P);
  Result := (P.Low = QUAL_SCOPE) and (Before(AMap, P).Low <> '.');
end;

// Die Argumente zwischen den Klammern AOpen und AClose (auch ueber Zeilen,
// seit rwE30 Stufe 2): Kommas auf oberster Ebene + 1, 0 ohne Inhalt.
// Strings zaehlen als Inhalt, ihre Kommas und Klammern nicht; Kommentare
// gar nicht. Ein Typparameter mit Komma ('TPair<A, B>') zaehlt eins zu viel
// - die Hilfe lehnt dann ab (die Richtung ist sicher).
function ArgCount(AMap: TRdxCodeMap; const AOpen, AClose: TRdxToken): Integer;
var
  L          : string;
  Li, c      : Integer;
  First, Stp : Integer;
  Depth      : Integer;
  Commas     : Integer;
  K          : Char;
  Content    : Boolean;
begin
  Depth := 0;
  Commas := 0;
  Content := False;
  for Li := AOpen.Line to AClose.Line do
  begin
    L := AMap.Raw(Li);
    First := 1;
    if Li = AOpen.Line then
      First := AOpen.EndCol;
    Stp := Length(L);
    if Li = AClose.Line then
      Stp := AClose.Col - 1;
    for c := First to Stp do
    begin
      K := AMap.ClassAt(Li, c);
      if K = 's' then
        Content := True
      else if K = 'c' then
      begin
        if not IsBlank(L[c]) then
          Content := True;
        if CharInSet(L[c], ['(', '[']) then
          Inc(Depth)
        else if CharInSet(L[c], [')', ']']) then
          Dec(Depth)
        else if (L[c] = ',') and (Depth = 0) then
          Inc(Commas);
      end;
    end;
  end;
  if Content then
    Result := Commas + 1
  else
    Result := 0;
end;

// Der Aufruf am Namen AName mit AArity Argumenten: '' und ASite, sonst der
// Grund (qualifiziert, kein Aufruf, schliesst nicht, andere Argumentzahl).
// Die schliessende Klammer darf seit rwE30 Stufe 2 bis MAX_CALL_LINES
// Zeilen tiefer stehen (MainFormU.pas:1471 'lOrder.Total]));',
// WrapFmxTypes.pas:391) - wenn dazwischen keine Direktive steht und keine
// Zeile in einem Kommentar oder mehrzeiligen String beginnt; die Klammer
// sucht MatchClose ueber die Code-Token (Strings und Kommentare zaehlen
// nicht).
function ReadCall(AMap: TRdxCodeMap; const AName: TRdxToken; AArity: Integer;
  out ASite: TCallSite): string;
var
  Prev  : TRdxToken;
  Text  : string;
  Args  : Integer;
  Li    : Integer;
begin
  Result := '';
  ASite := Default(TCallSite);
  ASite.Name := AName;
  Text := TokText(AMap, AName);
  Prev := Before(AMap, AName);
  if Prev.Low = '&' then
    Exit(_(R_FS_QUALIFIED, [Text, '&' + Text]));
  if (Prev.Low = '.') and not RtlQualified(AMap, Prev) then
    Exit(_(R_FS_QUALIFIED, [Text,
      TokText(AMap, Before(AMap, Prev)) + '.' + Text]));
  ASite.Open := After(AMap, AName);
  if ASite.Open.Low <> '(' then
    Exit(_(R_FS_NOT_CALL, [Text]));
  if ASite.Open.Line <> AName.Line then
    Exit(_(R_FS_OPEN, [Text, MAX_CALL_LINES]));
  ASite.Close := MatchClose(AMap, ASite.Open, MAX_CALL_LINES);
  if ASite.Close.Low = '' then
    Exit(_(R_FS_OPEN, [Text, MAX_CALL_LINES]));
  if ASite.Close.Line > ASite.Open.Line then
  begin
    if DirectiveInLines(AMap, ASite.Open.Line, ASite.Close.Line) then
      Exit(_(R_FS_CALL_BREAK, [Text, ASite.Open.Line, ASite.Close.Line]));
    for Li := ASite.Open.Line + 1 to ASite.Close.Line do
      if AMap.StartsInside(Li) then
        Exit(_(R_FS_CALL_BREAK, [Text, ASite.Open.Line, ASite.Close.Line]));
  end;
  Args := ArgCount(AMap, ASite.Open, ASite.Close);
  if Args <> AArity then
    Exit(_(R_FS_ARITY, [Text, Args, AArity]));
  // Hinter das letzte Zeichen aus Code oder String vor der Klammer
  // (Leerraum und Kommentar bleiben dahinter) - mit Argumenten nie die
  // Klammer selbst.
  if not LastCharBefore(AMap, ASite.Close, ASite.InsLine, ASite.InsAt) then
    Exit(_(R_FS_ARITY, [Text, 0, AArity]));
  Inc(ASite.InsAt);
end;

// Ist das erste Argument (ab AFrom bis zum ersten Komma, hoechstens bis
// ATo) nur aus String-Literalen mit '+' gefuegt? Dann True und ihr Text
// ('' als ein Quote) - so liest der Detektor den Formatstring. Ein Literal,
// das bis ATo reicht (das einzige Argument: StrToDate('..'), rwE29), zaehlt
// auch - bis dahin lieferte die Funktion dort False (SCA059 fragt nur
// Format mit zwei Argumenten, dort folgt immer ein Komma).
function LiteralFirstArg(AMap: TRdxCodeMap; ALine, AFrom, ATo: Integer;
  out AText: string): Boolean;
var
  L      : string;
  i      : Integer;
  Closed : Boolean;
begin
  Result := False;
  AText := '';
  L := AMap.Raw(ALine);
  i := SkipBlanks(L, AFrom);
  while (i <= ATo) and (L[i] = '''') and (AMap.ClassAt(ALine, i) = 's') do
  begin
    Inc(i);
    Closed := False;
    while i <= ATo do
      if L[i] <> '''' then
      begin
        AText := AText + L[i];
        Inc(i);
      end
      else if (i < ATo) and (L[i + 1] = '''') then
      begin
        AText := AText + '''';
        Inc(i, 2);
      end
      else
      begin
        Inc(i);
        Closed := True;
        Break;
      end;
    if not Closed then
      Exit;
    i := SkipBlanks(L, i);
    if i > ATo then
      Exit(True);
    if L[i] = ',' then
      Exit(True);
    if L[i] <> '+' then
      Exit;
    i := SkipBlanks(L, i + 1);
  end;
end;

// ---- Literal gegen TFormatSettings.Invariant (Alt-Weg, rwE29) ----
// Invariant: ShortDateFormat 'MM/dd/yyyy', DateSeparator '/',
// TimeSeparator ':', TimeAMString/TimePMString 'AM'/'PM', DecimalSeparator
// '.'; TextToFloat nimmt keinen Tausendertrenner. Gelesen wird streng -
// was nicht sicher passt, gilt als unpassend (die Hilfe sperrt; lieber
// keine Hilfe als StrToDateTime('17/02/2017 ..') mit sicherem
// EConvertError).

// Ab APos 1..AMax Ziffern: True mit ihrem Wert, APos dahinter.
function ReadNumber(const S: string; var APos: Integer; AMax: Integer;
  out AValue: Integer): Boolean;
var
  Start : Integer;
begin
  Start := APos;
  AValue := 0;
  while (APos <= Length(S)) and (APos - Start < AMax)
        and CharInSet(S[APos], ['0'..'9']) do
  begin
    AValue := AValue * 10 + Ord(S[APos]) - Ord('0');
    Inc(APos);
  end;
  Result := (APos > Start)
    and not ((APos <= Length(S)) and CharInSet(S[APos], ['0'..'9']));
end;

// 'M/d/yyyy' bzw. 'M/d' ab APos (Monat 1..12, Tag 1..31, Jahr 1..4
// Ziffern); APos dahinter.
function InvariantDateAt(const S: string; var APos: Integer): Boolean;
var
  M, D, Y : Integer;
begin
  Result := ReadNumber(S, APos, 2, M) and (M >= 1) and (M <= 12)
    and (APos <= Length(S)) and (S[APos] = '/');
  if not Result then Exit;
  Inc(APos);
  Result := ReadNumber(S, APos, 2, D) and (D >= 1) and (D <= 31);
  if Result and (APos <= Length(S)) and (S[APos] = '/') then
  begin
    Inc(APos);
    Result := ReadNumber(S, APos, 4, Y);
  end;
end;

// 'h:n', 'h:n:s', 'h:n:s.z', dahinter wahlweise ' AM'/' PM' ab APos;
// APos dahinter.
function InvariantTimeAt(const S: string; var APos: Integer): Boolean;
var
  H, N, Sec, Z : Integer;
  Rest         : string;
begin
  Result := ReadNumber(S, APos, 2, H) and (H <= 23)
    and (APos <= Length(S)) and (S[APos] = ':');
  if not Result then Exit;
  Inc(APos);
  Result := ReadNumber(S, APos, 2, N) and (N <= 59);
  if Result and (APos <= Length(S)) and (S[APos] = ':') then
  begin
    Inc(APos);
    Result := ReadNumber(S, APos, 2, Sec) and (Sec <= 59);
    if Result and (APos <= Length(S)) and (S[APos] = '.') then
    begin
      Inc(APos);
      Result := ReadNumber(S, APos, 3, Z);
    end;
  end;
  if not Result then Exit;
  Rest := UpperCase(Trim(Copy(S, APos, MaxInt)));
  if (Rest = 'AM') or (Rest = 'PM') then
  begin
    Result := (H >= 1) and (H <= 12);
    APos := Length(S) + 1;
  end;
end;

// Liest StrToFloat/StrToCurr den Text ATrimmed mit Invariant?
// [+-] Ziffern [. Ziffern] bzw. [+-] . Ziffern, dahinter wahlweise ein
// Exponent (e/E [+-] Ziffern).
function InvariantNumberFits(const ATrimmed: string): Boolean;
var
  i, n    : Integer;
  Digits  : Integer;
begin
  n := Length(ATrimmed);
  i := 1;
  if (i <= n) and CharInSet(ATrimmed[i], ['+', '-']) then
    Inc(i);
  Digits := 0;
  while (i <= n) and CharInSet(ATrimmed[i], ['0'..'9']) do
  begin
    Inc(i);
    Inc(Digits);
  end;
  if (i <= n) and (ATrimmed[i] = '.') then
  begin
    Inc(i);
    while (i <= n) and CharInSet(ATrimmed[i], ['0'..'9']) do
    begin
      Inc(i);
      Inc(Digits);
    end;
  end;
  if Digits = 0 then
    Exit(False);
  if (i <= n) and CharInSet(ATrimmed[i], ['e', 'E']) then
  begin
    Inc(i);
    if (i <= n) and CharInSet(ATrimmed[i], ['+', '-']) then
      Inc(i);
    Digits := 0;
    while (i <= n) and CharInSet(ATrimmed[i], ['0'..'9']) do
    begin
      Inc(i);
      Inc(Digits);
    end;
    if Digits = 0 then
      Exit(False);
  end;
  Result := i > n;
end;

// Passt das Literal AText zum Lesen durch ALow (klein) mit
// TFormatSettings.Invariant? '' wenn ja bzw. ALow nichts liest, sonst die
// Art: 'date' (Datum/Uhrzeit) oder 'number'.
function LiteralMisfit(const ALow, AText: string): string;
var
  T  : string;
  P  : Integer;
  Ok : Boolean;
begin
  Result := '';
  T := Trim(AText);
  P := 1;
  if InList(ALow, PARSE_NUMBER) then
  begin
    if not InvariantNumberFits(T) then
      Result := MISFIT_NUMBER;
    Exit;
  end;
  if ALow = PARSE_DATE then
    Ok := InvariantDateAt(T, P) and (P > Length(T))
  else if ALow = PARSE_TIME then
    // Ein reines Zeit-Literal sperrt nicht (Review e/HilfeFixC): Invariant
    // liest es wie die meisten Locales (':', AM/PM) - dass es dort sicher
    // scheitert, liesse sich nicht behaupten.
    Exit
  else if ALow = PARSE_DATETIME then
  begin
    Ok := InvariantDateAt(T, P);
    if Ok and (P <= Length(T)) then
    begin
      Ok := T[P] = ' ';
      while (P <= Length(T)) and (T[P] = ' ') do
        Inc(P);
      Ok := Ok and InvariantTimeAt(T, P);
    end;
    Ok := Ok and (P > Length(T));
  end
  else
    Exit;
  if not Ok then
    Result := MISFIT_DATE;
end;

// Der Grund, wenn der Aufruf ASite ein Literal liest, das nicht zu
// TFormatSettings.Invariant passt; '' sonst (kein Literal, kein Leser).
// Das Literal darf auf einer Folgezeile beginnen ('StrToDateTime(' am
// Zeilenende, das Literal darunter - seit rwE30 Stufe 2 schliesst die
// Klammer bis MAX_CALL_LINES tiefer; Review e/HilfeFixG: bis dahin las die
// Probe nur die Zeile des Namens und liess das Literal durch).
function LiteralReason(AMap: TRdxCodeMap; const ASite: TCallSite): string;
var
  Lit, Kind : string;
  Li, Co    : Integer;
  Upto      : Integer;
begin
  Result := '';
  if not FirstCharAfter(AMap, ASite.Open, Li, Co)
     or (Li > ASite.Close.Line)
     or ((Li = ASite.Close.Line) and (Co >= ASite.Close.Col)) then
    Exit;
  Upto := Length(AMap.Raw(Li));
  if Li = ASite.Close.Line then
    Upto := ASite.Close.Col - 1;
  if not LiteralFirstArg(AMap, Li, Co, Upto, Lit) then
    Exit;
  Kind := LiteralMisfit(ASite.Name.Low, Lit);
  if Kind = MISFIT_DATE then
    Result := _(R_FS_LIT_DATE, [QuotedStr(Lit), TokText(AMap, ASite.Name)])
  else if Kind = MISFIT_NUMBER then
    Result := _(R_FS_LIT_NUMBER, [QuotedStr(Lit), TokText(AMap, ASite.Name)]);
end;

// ---- Paar-Bruch (Alt-Weg, rwE29) ----
// HeidiSQL main.pas:14718: 'QueryDay := DateToStr(..)' wird mit Eintraegen
// verglichen, die Zeile 14699 mit DateToStr (Locale) schreibt - nur EINE
// Seite auf Invariant gestellt, ist der Vergleich ausser in en-US immer
// ungleich. Ebenso Schreiben und Lesen (CurrToStr ins Edit, TryStrToCurr
// zurueck). Ob zwei Aufrufe zusammengehoeren, sieht der Planer nicht -
// darum nennt der Hinweis (PairHint) den ersten weiteren Aufruf derselben
// Familie (PAIR_DATE bzw. PAIR_NUMBER) in der Datei, der kein Invariant
// uebergibt. Bis zum Entscheid M2 (Review e/HilfeFixC) sperrte er.

// Steht T in einem der Aufrufe ASites (die die Hilfe aendert)?
function IsEditedName(const T: TRdxToken; const ASites: TCallSites): Boolean;
var
  i : Integer;
begin
  for i := 0 to High(ASites) do
    if SameTok(T, ASites[i].Name) then
      Exit(True);
  Result := False;
end;

// Nennt der Aufruf am Namen T in seinen Klammern 'Invariant'? Ohne
// Klammer bzw. ohne gefundene schliessende: nein.
function PassesInvariant(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
var
  Open, Close, N : TRdxToken;
begin
  Result := False;
  Open := After(AMap, T);
  if Open.Low <> '(' then Exit;
  Close := MatchClose(AMap, Open, MAX_PAIR_ARG_LINES);
  if Close.Low = '' then Exit;
  N := After(AMap, Open);
  while (N.Low <> '') and TokBefore(N, Close) do
  begin
    if N.Low = NAME_INVARIANT then
      Exit(True);
    N := After(AMap, N);
  end;
end;

// Traegt ALowText (klein) einen der Woerter-Teile AHints? Nur die
// Vorpruefung je Zeile - die Token entscheiden.
function MentionsAny(const ALowText: string;
  const AHints: array of string): Boolean;
var
  i : Integer;
begin
  for i := Low(AHints) to High(AHints) do
    if Pos(AHints[i], ALowText) > 0 then
      Exit(True);
  Result := False;
end;

// Der erste weitere Aufruf der Familie(n) der Aufrufe ASites in der Datei
// ohne Invariant (s. Kopf des Abschnitts): seine Zeile und sein Name wie
// geschrieben in AName; 0 ohne. Ein Member-Aufruf ('X.DateToStr', X nicht
// SysUtils) ist eine andere Routine und zaehlt nicht.
function PairBreakIn(AMap: TRdxCodeMap; const ASites: TCallSites;
  AFrom, ATo: Integer; out AName: string): Integer;
var
  WantDate, WantNum : Boolean;
  i, Li             : Integer;
  T, P              : TRdxToken;
  LowText           : string;
  InFamily          : Boolean;
begin
  Result := 0;
  AName := '';
  WantDate := False;
  WantNum := False;
  for i := 0 to High(ASites) do
  begin
    WantDate := WantDate or InList(ASites[i].Name.Low, PAIR_DATE);
    WantNum := WantNum or InList(ASites[i].Name.Low, PAIR_NUMBER);
  end;
  for Li := AFrom to ATo do
  begin
    LowText := LowerCase(AMap.Raw(Li));
    if not ((WantDate and MentionsAny(LowText, PAIR_DATE_HINTS))
            or (WantNum and MentionsAny(LowText, PAIR_NUMBER_HINTS))) then
      Continue;
    T := NextToken(AMap, Li, 1);
    while (T.Low <> '') and (T.Line = Li) do
    begin
      InFamily := T.IsWord
        and ((WantDate and InList(T.Low, PAIR_DATE))
             or (WantNum and InList(T.Low, PAIR_NUMBER)));
      if InFamily and not IsEditedName(T, ASites) then
      begin
        P := Before(AMap, T);
        if ((P.Low <> '.') or RtlQualified(AMap, P))
           and not PassesInvariant(AMap, T) then
        begin
          AName := TokText(AMap, T);
          Exit(Li);
        end;
      end;
      T := After(AMap, T);
    end;
  end;
end;

// PairBreakIn erst im Rumpf der Routine um den ersten Aufruf, dann in der
// ganzen Datei (rwE30 Stufe 2, HeidiSQL main.pas:14718: der Vergleich mit
// 'DateToStr(Item.Time)' steht in derselben Routine, der Hinweis nannte
// Zeile 1782 einer anderen).
function PairBreakLine(AMap: TRdxCodeMap; const ASites: TCallSites;
  out AName: string): Integer;
var
  R : TRdxRoutine;
begin
  Result := 0;
  if (Length(ASites) > 0)
     and (BeginBodyAround(AMap, ASites[0].Name, R) = rbfFound) then
    Result := PairBreakIn(AMap, ASites, R.Body.Line, R.EndTok.Line, AName);
  if Result = 0 then
    Result := PairBreakIn(AMap, ASites, 1, AMap.LineCount, AName);
end;

// Steht das Token T wie eine Deklaration da - 'T: Typ', 'T = Wert' oder
// in einer Liste 'T, U: Typ'?
function DeclaredHere(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
var
  N : TRdxToken;
begin
  N := After(AMap, T);
  while N.Low = ',' do
  begin
    N := After(AMap, N);
    if not N.IsWord then
      Exit(False);
    N := After(AMap, N);
  end;
  Result := (N.Low = ':') or (N.Low = '=');
end;

// Die erste Zeile, in der ALow (klein) im Code als Deklaration steht
// (DeclaredHere, nicht hinter ':' oder '.'; oder hinter 'property'); 0
// ohne. AMemberLine: die erste Zeile mit 'X.<ALow>', X nicht SysUtils.
function DeclLineOf(AMap: TRdxCodeMap; const ALow: string;
  out AMemberLine: Integer): Integer;
var
  T, P : TRdxToken;
begin
  Result := 0;
  AMemberLine := 0;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), ALow);
  while T.Low <> '' do
  begin
    if T.Low = ALow then
    begin
      P := Before(AMap, T);
      if P.Low = '.' then
      begin
        if (Before(AMap, P).Low <> QUAL_UNIT) and (AMemberLine = 0) then
          AMemberLine := T.Line;
      end
      else if (P.Low = 'property')
              or ((P.Low <> ':') and DeclaredHere(AMap, T)) then
        Exit(T.Line);
    end;
    T := NextTokenOnLineWith(AMap, T, ALow);
  end;
end;

// Nennt die uses-Klausel ab AUses SysUtils bzw. System.SysUtils? ASpelled:
// der Name wie geschrieben ('System.SysUtils') - fuer die qualifizierte
// Form 'System.SysUtils.FormatSettings' (rwE30 Stufe 2).
function ClauseHasSysUtils(AMap: TRdxCodeMap; const AUses: TRdxToken;
  out ASpelled: string): Boolean;
var
  N    : TRdxToken;
  Name : string;
begin
  Result := False;
  Name := '';
  ASpelled := '';
  N := After(AMap, AUses);
  while N.Low <> '' do
  begin
    if (N.Low = ',') or (N.Low = ';') or (N.Low = 'in') then
    begin
      if (Name = QUAL_UNIT) or (Name = QUAL_SCOPE + '.' + QUAL_UNIT) then
        Exit(True);
      if N.Low = ';' then
        Exit;
      Name := '';
      ASpelled := '';
    end
    else
    begin
      Name := Name + N.Low;
      ASpelled := ASpelled + TokText(AMap, N);
    end;
    N := After(AMap, N);
  end;
end;

// Steht SysUtils in einer uses-Klausel der Datei? ASpelled wie oben.
function UsesSysUtils(AMap: TRdxCodeMap; out ASpelled: string): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  ASpelled := '';
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), NAME_USES);
  while T.Low <> '' do
  begin
    if (T.Low = NAME_USES) and IsKeywordAfter(T, Before(AMap, T))
       and ClauseHasSysUtils(AMap, T, ASpelled) then
      Exit(True);
    T := NextTokenOnLineWith(AMap, T, NAME_USES);
  end;
end;

// Endet die Anweisung des with AWith vor ATok? Ihr Bereich: hinter 'do'
// ein Block (begin, try, case, asm) bis zu seinem end, sonst die Anweisung
// bis zum ';' auf Klammer- und Blocktiefe 0 bzw. bis zum Ende des
// umgebenden Blocks (end, until, except, finally auf Tiefe 0). Ein 'else'
// zaehlt mit (es kann einem if der Anweisung gehoeren - der Bereich wird
// eher zu gross, das sperrt nur). Ohne 'do' bzw. hinter MAX_WITH_TOKENS
// Token: nein (der Bereich koennte ATok umfassen). Realworld-Test rwE30
// Stufe 2: Dev-Cpp Project.pas:1501 ('with TSaveDialog.Create(nil) do try
// .. finally Free; end;' endet in Zeile 1470), ProcAnalyzeMesh.pas:213
// (das with steht in einer lokalen Prozedur davor).
function WithEndsBefore(AMap: TRdxCodeMap; const AWith,
  ATok: TRdxToken): Boolean;
var
  T, P, Body : TRdxToken;
  Parens     : Integer;
  Blocks     : Integer;
  Count      : Integer;
  IsBlock    : Boolean;
begin
  Result := False;
  Parens := 0;
  Count := 0;
  P := AWith;
  T := After(AMap, AWith);
  // Bis zum 'do' auf Klammertiefe 0.
  while (T.Low <> '') and not ((Parens = 0) and (T.Low = 'do')
        and IsKeywordAfter(T, P)) do
  begin
    Parens := Parens + ParenDelta(T);
    Inc(Count);
    if (Count > MAX_WITH_TOKENS) or not TokBefore(T, ATok) then Exit;
    P := T;
    T := After(AMap, T);
  end;
  if T.Low = '' then Exit;
  Body := After(AMap, T);
  IsBlock := IsEndOpener(Body.Low) and IsKeywordAfter(Body, T);
  Parens := 0;
  Blocks := 0;
  P := T;
  T := Body;
  while T.Low <> '' do
  begin
    // ATok erreicht, bevor die Anweisung endet: das with umfasst ihn.
    if not TokBefore(T, ATok) then Exit;
    Inc(Count);
    if Count > MAX_WITH_TOKENS then Exit;
    Parens := Parens + ParenDelta(T);
    if IsKeywordAfter(T, P) then
    begin
      if IsEndOpener(T.Low) or (T.Low = 'repeat') then
        Inc(Blocks)
      else if (T.Low = 'end') or (T.Low = 'until') then
      begin
        // Auf Tiefe 0 schliesst es den umgebenden Block.
        if Blocks = 0 then
          Exit(True);
        Dec(Blocks);
        // Der Block direkt hinter 'do' ist zu Ende.
        if IsBlock and (Blocks = 0) then
          Exit(True);
      end
      else if (Blocks = 0) and ((T.Low = 'except') or (T.Low = 'finally'))
      then
        Exit(True);
    end;
    if (T.Low = ';') and (Parens = 0) and (Blocks = 0) then
      Exit(True);
    P := T;
    T := After(AMap, T);
  end;
end;

// Die Zeile eines with vor ATok in seiner Routine (rueckwaerts bis zum
// Routinenkopf oder Unit-Abschnitt), dessen Anweisung ATok umfasst; 0
// ohne. Seit rwE30 Stufe 2 zaehlt ein with, dessen Anweisung schon vor ATok
// endet, nicht mehr (WithEndsBefore) - auch nicht eines in einer lokalen
// Routine davor (deren Kopf steht zwischen with und ATok nicht: die Suche
// laeuft ueber ihren Rumpf hinweg bis zu ihrem Kopf).
function WithLineBefore(AMap: TRdxCodeMap; const ATok: TRdxToken): Integer;
var
  T, P : TRdxToken;
begin
  Result := 0;
  T := Before(AMap, ATok);
  while T.Low <> '' do
  begin
    P := Before(AMap, T);
    if IsKeywordAfter(T, P) then
    begin
      if (T.Low = 'with') and not WithEndsBefore(AMap, T, ATok) then
        Exit(T.Line);
      if InList(T.Low, SCOPE_STOPS) or IsRoutineHeadAfter(T, P) then
        Exit;
    end;
    T := P;
  end;
end;

// Die erste Zeile mit FPC-Weiche oder FPC-Modus ('{$IFDEF FPC}',
// '{$mode objfpc}', '{$IF FPC_FULLVERSION ..}'); 0 ohne. Die eine Regel von
// reDelphix: TRdxRecipes.LineLooksFpcAware - ein Treffer im Kommentar macht
// nur vorsichtig. Bis zur Hygiene-Welle H1 stand hier eine Kopie der Liste
// mit der alten Bedingung "ein '$' auf der Zeile"; seitdem zaehlt auch die
// Folgezeile einer mehrzeiligen Direktive ('  or Defined(FPC)}').
function FpcTellLine(AMap: TRdxCodeMap): Integer;
var
  Li : Integer;
begin
  Result := 0;
  for Li := 1 to AMap.LineCount do
    if TRdxRecipes.LineLooksFpcAware(AMap.Raw(Li)) then
      Exit(Li);
end;

// Die Fragen an die ganze Datei (s. Kopf); '' oder der Grund. ANames: die
// Namen der Aufrufe wie im Quelltext, AAt: der erste Aufruf.
// Stehen alle Aufrufe ASites in einem Zweig, den FPC nie uebersetzt
// ('{$IF NOT DEFINED(FPC)}', '{$IFNDEF FPC}' ...; uRdxCompilerTraces.
// FpcExcludedAt)? Realworld-Test rwE30 Stufe 2: Horse.Core.Param.Field.pas
// :245 (AsList<T> nur fuer Delphi), die FPC-Weiche in Zeile 3 gilt dort
// nicht.
function AllFpcExcluded(const ADirs: TRdxCondDirectives;
  const ASites: TCallSites): Boolean;
var
  i : Integer;
begin
  Result := Length(ASites) > 0;
  for i := 0 to High(ASites) do
    Result := Result and FpcExcludedAt(ADirs, ASites[i].Name.Line,
      ASites[i].Name.Col);
end;

// Die Fragen an die ganze Datei (s. Kopf); '' oder der Grund. ANames: die
// Namen der Aufrufe wie im Quelltext, ASites: die Aufrufe (der erste fuer
// das with). ASettings: das Argument - ', TFormatSettings.Invariant' bzw.
// ', FormatSettings', seit rwE30 Stufe 2 qualifiziert (', System.SysUtils.
// FormatSettings', Schreibweise der uses-Klausel), wenn die Datei einen
// Bezeichner FormatSettings deklariert oder als Member nutzt: bis dahin
// sperrte das (TemplatePro.pas:3170 - die Property FormatSettings verdeckt
// den Namen; die qualifizierte globale Variable ist dieselbe, die die
// Ueberladung ohne Settings liest). Der Gegenbeweis der Datei (ModernProof,
// Invariant ohne Weiche) widerlegt Spuren alter Compiler und - fuer
// Invariant - die FPC-Weiche; ebenso ein Aufruf in einem Zweig ohne FPC.
function FileReason(AMap: TRdxCodeMap; const ANames: array of string;
  const ASites: TCallSites; AInvariant: Boolean;
  out ASettings: string): string;
var
  i, Li, Member : Integer;
  Trace, Spell  : string;
  Proof         : TRdxModernProof;
  Proven        : Boolean;
begin
  ASettings := INSERT_INVARIANT;
  if not AInvariant then
    ASettings := INSERT_GLOBAL;
  if not UsesSysUtils(AMap, Spell) then
    Exit(_(R_FS_NO_SYSUTILS));
  for i := Low(ANames) to High(ANames) do
    if DeclaresRoutine(AMap, ANames[i]) then
      Exit(_(R_FS_OWN_ROUTINE, [ANames[i]]));
  if not AInvariant then
  begin
    Li := DeclLineOf(AMap, NAME_SETTINGS, Member);
    if (Li > 0) or (Member > 0) then
      ASettings := ', ' + Spell + '.FormatSettings';
  end;
  Li := WithLineBefore(AMap, ASites[0].Name);
  if Li > 0 then
    Exit(_(R_FS_WITH, [Li]));
  Proof := ModernProof(AMap);
  if not AInvariant then
  begin
    if ProofCovers(Proof, FLOOR_SETTINGS_VAR) then
      Exit('');
    Trace := OldCompilerTrace(AMap, FLOOR_SETTINGS_VAR, Li);
    if Trace <> '' then
      Exit(_(R_FS_OLD_VAR, [Trace, Li]));
    Exit('');
  end;
  // Invariant: eine Inline-Variable (Delphi 10.3, kein FPC) bzw. eine
  // Nutzung von Invariant ohne Weiche beweist es (rwE30 Stufe 2:
  // dwsJSON.pas, demos.pas, TemplatePro.pas).
  Proven := (ProofCovers(Proof, FLOOR_INLINE_DECL) and Proof.NoFpc)
    or (UnconditionalInvariantLine(AMap) > 0);
  if not Proven then
  begin
    Li := FpcTellLine(AMap);
    if (Li > 0)
       and not AllFpcExcluded(ConditionalDirectives(AMap), ASites) then
      Exit(_(R_FS_FPC, [Li]));
    Trace := OldCompilerTrace(AMap, FLOOR_INLINE_DECL, Li);
    if Trace <> '' then
      Exit(_(R_FS_OLD_INVARIANT, [Trace, Li]));
  end;
  Li := DeclLineOf(AMap, NAME_SETTINGS_TYPE, Member);
  if Li > 0 then
    Exit(_(R_FS_OWN_TYPE, [Li]));
  // Die Datei stellt die globale FormatSettings selbst ein: Invariant liefe
  // daran vorbei (rwE30 Stufe 2; ein Programm, das die Unit enthaelt,
  // prueft der Plattenblick).
  Li := GlobalSettingsWriteLine(AMap, Trace);
  if Li > 0 then
    Exit(_(R_FS_SETTINGS_SET, [Trace, Li]));
  Result := '';
end;

// EINE Ersetzung: AInsert vor jede Einfuegestelle (InsLine/InsAt); der
// Bereich von der ersten Einfuegestelle bis hinter die letzte schliessende
// Klammer - seit rwE30 Stufe 2 auch ueber Zeilen (verbunden mit #10 wie
// RangeText; der Text dazwischen bleibt, wie er ist). Liegt die erste
// Einfuegestelle hinter dem Zeilenende (das letzte Argument endet dort,
// die Klammer steht tiefer), beginnt der Bereich auf dem letzten Zeichen
// davor - ein Bereich beginnt auf einem Zeichen.
// AInsert so oft, wie Aufrufe aus ASites vor (ALine, ACol) einfuegen.
function InsertsAt(const ASites: array of TCallSite; ALine, ACol: Integer;
  const AInsert: string): string;
var
  k : Integer;
begin
  Result := '';
  for k := Low(ASites) to High(ASites) do
    if (ASites[k].InsLine = ALine) and (ASites[k].InsAt = ACol) then
      Result := Result + AInsert;
end;

procedure BuildEdit(AMap: TRdxCodeMap; const ASites: array of TCallSite;
  const AInsert, ARole: string; out AEdit: TRdxEdit);
var
  L, S                : string;
  i, c, Li            : Integer;
  FirstLine, FirstCol : Integer;
  LastLine, LastCol   : Integer;
  From, Upto          : Integer;
begin
  AEdit := Default(TRdxEdit);
  FirstLine := MaxInt;
  FirstCol := MaxInt;
  LastLine := 0;
  LastCol := 0;
  for i := Low(ASites) to High(ASites) do
  begin
    if (ASites[i].InsLine < FirstLine) or ((ASites[i].InsLine = FirstLine)
       and (ASites[i].InsAt < FirstCol)) then
    begin
      FirstLine := ASites[i].InsLine;
      FirstCol := ASites[i].InsAt;
    end;
    if (ASites[i].Close.Line > LastLine) or ((ASites[i].Close.Line = LastLine)
       and (ASites[i].Close.Col > LastCol)) then
    begin
      LastLine := ASites[i].Close.Line;
      LastCol := ASites[i].Close.Col;
    end;
  end;
  if FirstCol > Length(AMap.Raw(FirstLine)) then
    Dec(FirstCol);
  S := '';
  for Li := FirstLine to LastLine do
  begin
    L := AMap.Raw(Li);
    From := 1;
    if Li = FirstLine then
      From := FirstCol;
    Upto := Length(L);
    if Li = LastLine then
      Upto := LastCol;
    for c := From to Upto do
      S := S + InsertsAt(ASites, Li, c, AInsert) + L[c];
    if Li < LastLine then
      S := S + InsertsAt(ASites, Li, Length(L) + 1, AInsert) + #10;
  end;
  AEdit.Span := TRefactorSpan.Make(ARole, FirstLine, FirstCol, LastLine,
    LastCol + 1);
  AEdit.Expected := RangeText(AMap, AEdit.Span);
  AEdit.NewText := S;
end;

// Haengt ATail an AList an.
procedure AppendTokens(var AList: TArray<TRdxToken>;
  const ATail: TArray<TRdxToken>);
var
  T : TRdxToken;
begin
  for T in ATail do
    AddToken(AList, T);
end;

// Die Aufrufe der Liste ANames in der Anweisung von ALine: auf der Zeile
// und - seit rwE30 Stufe 2 - auf ihren Folgezeilen (FollowNames).
function StatementNames(AMap: TRdxCodeMap; ALine: Integer;
  const ANames: array of string): TArray<TRdxToken>;
begin
  Result := nil;
  if (ALine < 1) or (ALine > AMap.LineCount) then Exit;
  Result := NamesOnLine(AMap, ALine, ANames);
  AppendTokens(Result, FollowNames(AMap, ALine, ANames));
end;

// Ein String-Literal ab dem Quote an L[AAt] ('..' mit '' als Quote): sein
// Text, AAt dahinter. Nur dieser Teil - '#13' und '+' gehoeren nicht dazu.
function ReadQuoted(const L: string; var AAt: Integer): string;
begin
  Result := '';
  Inc(AAt);
  while AAt <= Length(L) do
  begin
    if L[AAt] <> '''' then
      Result := Result + L[AAt]
    else if (AAt < Length(L)) and (L[AAt + 1] = '''') then
    begin
      Result := Result + '''';
      Inc(AAt);
    end
    else
    begin
      Inc(AAt);
      Exit;
    end;
    Inc(AAt);
  end;
end;

// Nur Ziffern (und mindestens eine)?
function AllDigits(const S: string): Boolean;
var
  C : Char;
begin
  Result := S <> '';
  for C in S do
    Result := Result and CharInSet(C, ['0'..'9']);
end;

// Eine Zahl mit Komma als Dezimaltrenner ('5,5', '-1,25')?
function IsCommaNumber(const S: string): Boolean;
var
  Body : string;
  P    : Integer;
begin
  Body := S;
  if (Body <> '') and CharInSet(Body[1], ['+', '-']) then
    Delete(Body, 1, 1);
  P := Pos(',', Body);
  Result := (P > 1) and AllDigits(Copy(Body, 1, P - 1))
    and AllDigits(Copy(Body, P + 1, MaxInt));
end;

// Ein Datum aus Ziffern mit '.', '-' oder '/' ('29.10.2026', '2026-10-29'),
// das nicht im Invariant-Format (M/d/yyyy) steht?
function IsForeignDate(const S: string): Boolean;
var
  i, Seps : Integer;
  P       : Integer;
begin
  Result := False;
  Seps := 0;
  for i := 1 to Length(S) do
    if CharInSet(S[i], ['.', '-', '/']) then
      Inc(Seps)
    else if not CharInSet(S[i], ['0'..'9', ' ', ':']) then
      Exit;
  if (Seps < 2) or (S = '') or not CharInSet(S[1], ['0'..'9']) then Exit;
  P := 1;
  Result := not InvariantDateAt(S, P);
end;

// Steht (ALine, ACol) innerhalb der Klammern eines Aufrufs aus ASites?
function InsideSite(const ASites: TCallSites; ALine, ACol: Integer): Boolean;
var
  i : Integer;
begin
  for i := 0 to High(ASites) do
    if ((ALine > ASites[i].Open.Line)
        or ((ALine = ASites[i].Open.Line) and (ACol > ASites[i].Open.Col)))
       and ((ALine < ASites[i].Close.Line)
        or ((ALine = ASites[i].Close.Line) and (ACol < ASites[i].Close.Col)))
    then
      Exit(True);
  Result := False;
end;

// Alt-Weg (rwE30 Stufe 2, horse Tests.Horse.Core.Param.pas:292:
// 'Assert.AreEqual(''5,5'', CurrToStr(..))'): steht in der Anweisung
// (Zeilen AFirst..ALast, ausserhalb der Klammern der Aufrufe) ein Literal,
// mit dem das Ergebnis eines schreibenden Aufrufs verglichen werden
// koennte - eine Zahl mit Dezimalkomma bzw. ein Datum, das nicht
// M/d/yyyy ist -, schriebe der Aufruf mit Invariant ein anderes Format:
// der Vergleich bricht. '' oder der Grund.
function CompareLiteralReason(AMap: TRdxCodeMap; AFirst, ALast: Integer;
  const ASites: TCallSites): string;
var
  WantNum, WantDate : Boolean;
  i, Li, c, Start   : Integer;
  L, Lit            : string;
  Writer            : string;
begin
  Result := '';
  WantNum := False;
  WantDate := False;
  Writer := '';
  for i := 0 to High(ASites) do
    if InList(ASites[i].Name.Low, NUMBER_WRITERS) then
    begin
      WantNum := True;
      Writer := TokText(AMap, ASites[i].Name);
    end
    else if InList(ASites[i].Name.Low, DATE_WRITERS) then
    begin
      WantDate := True;
      Writer := TokText(AMap, ASites[i].Name);
    end;
  if not (WantNum or WantDate) then Exit;
  for Li := AFirst to ALast do
  begin
    L := AMap.Raw(Li);
    c := 1;
    while c <= Length(L) do
    begin
      if (L[c] = '''') and (AMap.ClassAt(Li, c) = 's')
         and ((c = 1) or (AMap.ClassAt(Li, c - 1) <> 's')) then
      begin
        Start := c;
        Lit := ReadQuoted(L, c);
        if not InsideSite(ASites, Li, Start)
           and ((WantNum and IsCommaNumber(Trim(Lit)))
                or (WantDate and IsForeignDate(Trim(Lit)))) then
          Exit(_(R_FS_LIT_COMPARE, [QuotedStr(Lit), Writer]));
      end
      else
        Inc(c);
    end;
  end;
end;

// SCA128 fuer beide Wege. Seit rwE30 Stufe 2 auch Aufrufe auf Folgezeilen
// der Anweisung und Aufrufe, deren Klammer tiefer schliesst (ReadCall).
function PlanLocale(AMap: TRdxCodeMap; ALine: Integer; const AMessage: string;
  AInvariant: Boolean; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Want     : string;
  Settings : string;
  Hits     : TArray<TRdxToken>;
  Sites    : TCallSites;
  Names    : TArray<string>;
  i, Last  : Integer;
  Found    : Boolean;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  Want := TRdxFormatSettingsFix.CalledNameOf(AMessage);
  if Want = '' then
  begin
    AReason := _(R_FS_NO_NAME);
    Exit;
  end;
  Hits := StatementNames(AMap, ALine, LOCALE_FUNCS);
  Found := False;
  for i := 0 to High(Hits) do
    Found := Found or (Hits[i].Low = Want);
  if not Found then
  begin
    AReason := MsgMovedSuffix(_(R_FS_MOVED, [Want]));
    Exit;
  end;
  if DirectiveInLines(AMap, ALine, ALine) then
  begin
    AReason := _(R_FS_DIRECTIVE);
    Exit;
  end;
  SetLength(Sites, Length(Hits));
  SetLength(Names, Length(Hits));
  Last := ALine;
  for i := 0 to High(Hits) do
  begin
    AReason := ReadCall(AMap, Hits[i], LOCALE_ARITY[LocaleIndex(Hits[i].Low)],
      Sites[i]);
    if AReason <> '' then
      Exit;
    Names[i] := TokText(AMap, Hits[i]);
    if Sites[i].Close.Line > Last then
      Last := Sites[i].Close.Line;
    // Alt-Weg: ein gelesenes Literal muss zu Invariant passen (rwE29).
    if AInvariant then
    begin
      AReason := LiteralReason(AMap, Sites[i]);
      if AReason <> '' then
        Exit;
    end;
  end;
  // Eine Direktive zwischen Fundzeile und letztem Aufruf: Code unter
  // Bedingung (die Aufrufe einer Folgezeile koennten fehlen).
  if DirectiveInLines(AMap, ALine, Last) then
  begin
    AReason := _(R_FS_DIRECTIVE);
    Exit;
  end;
  AReason := FileReason(AMap, Names, Sites, AInvariant, Settings);
  if (AReason = '') and AInvariant then
    AReason := CompareLiteralReason(AMap, ALine, Last, Sites);
  if AReason <> '' then
    Exit;
  BuildEdit(AMap, Sites, Settings, SPAN_128, AEdit);
  Result := True;
end;

// Der Formatstring als Literal am Anfang des ersten Arguments von ASite -
// auch auf der Zeile hinter '(' (IDE.MainForm.pas:6170 'Format(' am
// Zeilenende); False, wenn dort kein Literal steht.
function FirstArgLiteral(AMap: TRdxCodeMap; const ASite: TCallSite;
  out AText: string): Boolean;
var
  Li, Co, Upto : Integer;
begin
  AText := '';
  Result := FirstCharAfter(AMap, ASite.Open, Li, Co)
    and ((Li < ASite.Close.Line)
         or ((Li = ASite.Close.Line) and (Co < ASite.Close.Col)));
  if not Result then Exit;
  Upto := Length(AMap.Raw(Li));
  if Li = ASite.Close.Line then
    Upto := ASite.Close.Col - 1;
  Result := LiteralFirstArg(AMap, Li, Co, Upto, AText);
end;

// SCA059 fuer beide Wege. Seit rwE30 Stufe 2 auch das eine Format auf
// einer Folgezeile der Anweisung (frmMain.pas:1519 - der Aufruf steht in
// Zeile 1520) und eines, dessen Klammer tiefer schliesst.
function PlanFormat(AMap: TRdxCodeMap; ALine: Integer; const AMessage: string;
  AInvariant: Boolean; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Fmt, Lit : string;
  Settings : string;
  Hits     : TArray<TRdxToken>;
  Follow   : TArray<TRdxToken>;
  Site     : TCallSite;
  Sites    : TCallSites;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  if not TRdxFormatSettingsFix.FloatSpecOf(AMessage, Fmt) then
  begin
    AReason := _(R_FL_NO_SPEC);
    Exit;
  end;
  Hits := nil;
  Follow := nil;
  if (ALine >= 1) and (ALine <= AMap.LineCount) then
  begin
    Hits := NamesOnLine(AMap, ALine, FORMAT_FUNCS);
    Follow := FollowNames(AMap, ALine, FORMAT_FUNCS);
  end;
  if Length(Hits) > 1 then
  begin
    AReason := _(R_FL_MANY, [ALine, Length(Hits)]);
    Exit;
  end;
  // Ein Format mehr auf einer Folgezeile bliebe ungeaendert, und der
  // Detektor (ein Fund je Anweisung) schwiege.
  if (Length(Hits) + Length(Follow) > 1) then
  begin
    AReason := _(R_FS_CONTINUES, [Follow[Length(Follow) - 1].Line]);
    Exit;
  end;
  if Length(Hits) = 0 then
    Hits := Follow;
  if Length(Hits) = 0 then
  begin
    AReason := MsgMovedSuffix(_(R_FL_NO_FORMAT));
    Exit;
  end;
  if DirectiveInLines(AMap, ALine, ALine) then
  begin
    AReason := _(R_FS_DIRECTIVE);
    Exit;
  end;
  AReason := ReadCall(AMap, Hits[0], FORMAT_ARITY, Site);
  if AReason <> '' then
    Exit;
  if DirectiveInLines(AMap, ALine, Site.Close.Line) then
  begin
    AReason := _(R_FS_DIRECTIVE);
    Exit;
  end;
  if FirstArgLiteral(AMap, Site, Lit) and (Lit <> Fmt) then
  begin
    AReason := MsgMovedSuffix(_(R_FL_OTHER_FMT));
    Exit;
  end;
  if AInvariant and TRdxFormatSettingsFix.HasMoneySpec(Fmt) then
  begin
    AReason := _(R_FL_MONEY);
    Exit;
  end;
  SetLength(Sites, 1);
  Sites[0] := Site;
  AReason := FileReason(AMap, [TokText(AMap, Hits[0])], Sites, AInvariant,
    Settings);
  if AReason <> '' then
    Exit;
  BuildEdit(AMap, Sites, Settings, SPAN_059, AEdit);
  Result := True;
end;

{ TRdxFormatSettingsFix }

class function TRdxFormatSettingsFix.DateFormatSettings(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
begin
  Result := PlanLocale(AMap, ALine, AMessage, False, AEdit, AReason);
end;

class function TRdxFormatSettingsFix.DateFormatInvariant(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
begin
  Result := PlanLocale(AMap, ALine, AMessage, True, AEdit, AReason);
end;

class function TRdxFormatSettingsFix.FormatLocale(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
begin
  Result := PlanFormat(AMap, ALine, AMessage, False, AEdit, AReason);
end;

class function TRdxFormatSettingsFix.FormatLocaleInvariant(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
begin
  Result := PlanFormat(AMap, ALine, AMessage, True, AEdit, AReason);
end;

class function TRdxFormatSettingsFix.CalledNameOf(
  const AMessage: string): string;
var
  P : Integer;
begin
  Result := '';
  P := Pos(CALLED_MARK, AMessage);
  if P < 2 then
    Exit;
  Result := LowerCase(Trim(Copy(AMessage, 1, P - 1)));
  if LocaleIndex(Result) < 0 then
    Result := '';
end;

class function TRdxFormatSettingsFix.FloatSpecOf(const AMessage: string;
  out AFormat: string): Boolean;
var
  Rest : Integer;
begin
  AFormat := '';
  Rest := Length(AMessage) - Length(SPEC_PREFIX) - Length(SPEC_SUFFIX);
  Result := (Rest > 0)
    and (Copy(AMessage, 1, Length(SPEC_PREFIX)) = SPEC_PREFIX)
    and (Copy(AMessage, Length(AMessage) - Length(SPEC_SUFFIX) + 1,
      Length(SPEC_SUFFIX)) = SPEC_SUFFIX);
  if Result then
    AFormat := Copy(AMessage, Length(SPEC_PREFIX) + 1, Rest);
end;

class function TRdxFormatSettingsFix.HasMoneySpec(
  const AFormat: string): Boolean;
var
  i, n : Integer;
begin
  Result := False;
  n := Length(AFormat);
  i := 1;
  while i <= n do
  begin
    if AFormat[i] = '%' then
    begin
      if (i < n) and (AFormat[i + 1] = '%') then
      begin
        Inc(i, 2);
        Continue;
      end;
      Inc(i);
      while (i <= n) and CharInSet(AFormat[i], ['0'..'9', '.', '-', '*', ':']) do
        Inc(i);
      if (i <= n) and CharInSet(AFormat[i], ['m', 'M']) then
        Exit(True);
    end;
    Inc(i);
  end;
end;

class function TRdxFormatSettingsFix.PairHint(AMap: TRdxCodeMap;
  ALine: Integer; const ABaseHint: string): string;
var
  Hits  : TArray<TRdxToken>;
  Sites : TCallSites;
  i, Li : Integer;
  Other : string;
begin
  Result := ABaseHint;
  // Dieselben Aufrufe wie der Planer (auch auf Folgezeilen, rwE30 Stufe 2).
  Hits := StatementNames(AMap, ALine, LOCALE_FUNCS);
  if Length(Hits) = 0 then
    Exit;
  SetLength(Sites, Length(Hits));
  for i := 0 to High(Hits) do
    if ReadCall(AMap, Hits[i], LOCALE_ARITY[LocaleIndex(Hits[i].Low)],
         Sites[i]) <> '' then
      Exit;
  Li := PairBreakLine(AMap, Sites, Other);
  if Li > 0 then
    Result := _(R_FS_PAIR_HINT, [ABaseHint, Li, Other]);
end;

end.

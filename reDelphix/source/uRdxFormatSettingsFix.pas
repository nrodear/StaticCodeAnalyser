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
//     die Hilfe es an JEDEN Aufruf der Liste auf der Zeile (eine Ersetzung)
//     und lehnt ab, wenn die Anweisung auf einer Folgezeile einen weiteren
//     nennt - der bliebe sonst still ungeaendert.
//   SCA059 (uFormatMismatch): den ersten 'format(' der Anweisung mit
//     Float-Spec (%f %g %e %m %n) und hoechstens zwei Argumenten. Meldung
//     'Format: float spec <Formatstring> without TFormatSettings - ...';
//     der Formatstring ist der aufgeloeste Wert (bei einer Konstanten deren
//     Inhalt) - die Gegenprobe vergleicht ihn, wenn das erste Argument auf
//     der Zeile ein Literal ist.
//
// GRUNDSATZ wie in uRdxLineFixes: lieber keine Hilfe als eine falsche. Keine
// Hilfe, wenn
//   * die Meldung den Namen bzw. Formatstring nicht nennt, die Zeile ihn
//     nicht (mehr) als Aufruf auf den Code-Spalten traegt (verschoben,
//     Kommentar, String) oder der Aufruf erst auf einer Folgezeile beginnt;
//   * der Aufruf qualifiziert ist (nur 'SysUtils.' und 'System.SysUtils.'
//     sind die RTL), nicht auf der Zeile schliesst oder eine andere Zahl
//     von Argumenten traegt; SCA059: mehr als ein Format auf der Zeile;
//   * auf der Zeile eine Direktive steht;
//   * SysUtils in keiner uses-Klausel steht, die Datei eine eigene Routine
//     des Namens deklariert, vor dem Aufruf in seiner Routine ein with
//     steht (die Namen koennten an einen Member binden);
//   * Hauptweg: die Datei einen Bezeichner FormatSettings deklariert (Feld,
//     Variable, Parameter, Property) oder als Member nutzt ('X.FormatSettings'
//     ausser 'SysUtils.FormatSettings') - der blosse Name bande dort; die
//     Datei nach Compilern vor Delphi XE fragt (die globale Variable gibt es
//     erst seit XE; FPC vor 2.6);
//   * Alt-Weg: die Datei eine FPC-Weiche oder einen FPC-Modus traegt (FPC
//     3.2.2 kennt kein TFormatSettings.Invariant), nach Compilern bis Delphi
//     10.3 fragt (belegt ist Invariant in den Docwiki-Staenden ab Rio -
//     dieselbe Schwelle wie SCA014, FLOOR_INLINE_DECL), ein eigenes
//     TFormatSettings deklariert; SCA059 dazu bei einer Waehrungs-Spec m
//     (Invariant schreibt das allgemeine Waehrungszeichen).
// Der Bereich der Ersetzung beginnt hinter dem letzten Zeichen des letzten
// Arguments (nie auf einer leeren Zeile) und endet hinter der letzten
// schliessenden Klammer; ein Leerraum vor der Klammer bleibt dahinter.

interface

uses
  uRdxBufferMath,     // TRdxEdit
  uRdxCodeMap;        // TRdxCodeMap

const
  // Die Gruende als englische msgids (E29); die Tests vergleichen mit _().
  R_FS_NO_NAME = 'the message names none of the locale-dependent RTL '
    + 'functions of SCA128';
  R_FS_MOVED = 'no call of %s on the code columns of the reported line';
  R_FS_NEXT_LINE = 'the call stands on line %d, a following line of the '
    + 'statement - the help only handles calls on the reported line';
  R_FS_NOT_CALL = '%s stands without an argument list - no call';
  R_FS_QUALIFIED = '%s is called as %s - another routine than the one of '
    + 'SysUtils';
  R_FS_OPEN = 'the call of %s does not close on the reported line';
  R_FS_ARITY = '%s carries %d arguments here, the RTL form without '
    + 'TFormatSettings has %d';
  R_FS_DIRECTIVE = 'a compiler directive stands on the reported line';
  R_FS_CONTINUES = 'the statement continues on line %d with another such '
    + 'call - it would stay unchanged and unreported; by hand';
  R_FS_NO_SYSUTILS = 'SysUtils is in no uses clause of the file - the call '
    + 'need not bind to the RTL';
  R_FS_OWN_ROUTINE = 'the file declares its own routine %s - the call need '
    + 'not bind to the RTL';
  R_FS_SHADOW = 'the file declares an identifier FormatSettings (line %d) - '
    + 'the name would bind there, not to SysUtils.FormatSettings';
  R_FS_MEMBER = 'the file uses FormatSettings as a member (line %d) - inside '
    + 'such a class the bare name binds to the member';
  R_FS_WITH = 'a with statement stands before the call in its routine (line '
    + '%d) - the names could bind to a member';
  R_FS_OLD_VAR = 'the file asks for old compilers (%s, line %d) - the global '
    + 'variable FormatSettings exists from Delphi XE on';
  R_FS_FPC = 'the file is also written for FPC (line %d) - FPC 3.2 knows no '
    + 'TFormatSettings.Invariant';
  R_FS_OLD_INVARIANT = 'the file asks for compilers up to Delphi 10.3 (%s, '
    + 'line %d) - TFormatSettings.Invariant is only checked from there on';
  R_FS_OWN_TYPE = 'the file declares its own TFormatSettings (line %d)';
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
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,        // TRefactorSpan.Make
  uRdxText,             // _(), MsgMovedSuffix (E29, nie uLocalization)
  uRdxRecipes,          // TRdxRecipes.LineLooksFpcAware (FpcTellLine)
  uRdxCompilerTraces;   // OldCompilerTrace, TRdxCompilerFloor, FLOOR_INLINE_DECL

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
  // Die globale Variable FormatSettings: Delphi XE (VER220, CompilerVersion
  // 22, COMPILER15/DELPHI15 der JEDI-Zaehlung, RTL220); FPC ab 2.6. Wer nach
  // XE fragt, baut auch davor (s. uRdxCompilerTraces). ProjectVersion liest
  // nur SCA014 - hier ohne Wirkung.
  FLOOR_SETTINGS_VAR: TRdxCompilerFloor = (Ver: 220; Version: 22;
    Compiler: 15; DelphiNumber: 15; DelphiYear: 2010; Rtl: 220;
    FpcFull: 20600; XeNames: False; ProjectVersion: 0);

type
  // Ein Aufruf auf der Zeile: Name, Klammern und die Spalte, vor der das
  // Argument eingefuegt wird (hinter dem letzten Zeichen des letzten
  // Arguments).
  TCallSite = record
    Name  : TRdxToken;
    Open  : TRdxToken;
    Close : TRdxToken;
    InsAt : Integer;
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

// Die Argumente zwischen AFrom und ATo (die Spalten innerhalb der
// Klammern): Kommas auf oberster Ebene + 1, 0 ohne Inhalt. Strings zaehlen
// als Inhalt, ihre Kommas und Klammern nicht; Kommentare gar nicht. Ein
// Typparameter mit Komma ('TPair<A, B>') zaehlt eins zu viel - die Hilfe
// lehnt dann ab (die Richtung ist sicher).
function ArgCount(AMap: TRdxCodeMap; ALine, AFrom, ATo: Integer): Integer;
var
  L       : string;
  c       : Integer;
  Depth   : Integer;
  Commas  : Integer;
  K       : Char;
  Content : Boolean;
begin
  L := AMap.Raw(ALine);
  Depth := 0;
  Commas := 0;
  Content := False;
  for c := AFrom to ATo do
  begin
    K := AMap.ClassAt(ALine, c);
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
  if Content then
    Result := Commas + 1
  else
    Result := 0;
end;

// Der Aufruf am Namen AName mit AArity Argumenten: '' und ASite, sonst der
// Grund (qualifiziert, kein Aufruf, schliesst nicht auf der Zeile, andere
// Argumentzahl).
function ReadCall(AMap: TRdxCodeMap; const AName: TRdxToken; AArity: Integer;
  out ASite: TCallSite): string;
var
  Prev  : TRdxToken;
  L     : string;
  Text  : string;
  Args  : Integer;
  c     : Integer;
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
    Exit(_(R_FS_OPEN, [Text]));
  ASite.Close := MatchClose(AMap, ASite.Open, 0);
  if ASite.Close.Low = '' then
    Exit(_(R_FS_OPEN, [Text]));
  Args := ArgCount(AMap, AName.Line, ASite.Open.EndCol, ASite.Close.Col - 1);
  if Args <> AArity then
    Exit(_(R_FS_ARITY, [Text, Args, AArity]));
  // Hinter das letzte Zeichen vor der Klammer (Leerraum bleibt dahinter).
  L := AMap.Raw(AName.Line);
  c := ASite.Close.Col - 1;
  while (c > ASite.Open.Col) and IsBlank(L[c]) do
    Dec(c);
  ASite.InsAt := c + 1;
end;

// Ist das erste Argument (ab AFrom bis zum ersten Komma, hoechstens bis
// ATo) nur aus String-Literalen mit '+' gefuegt? Dann True und ihr Text
// ('' als ein Quote) - so liest der Detektor den Formatstring.
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
      Exit;
    if L[i] = ',' then
      Exit(True);
    if L[i] <> '+' then
      Exit;
    i := SkipBlanks(L, i + 1);
  end;
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

// Nennt die uses-Klausel ab AUses SysUtils bzw. System.SysUtils?
function ClauseHasSysUtils(AMap: TRdxCodeMap; const AUses: TRdxToken): Boolean;
var
  N    : TRdxToken;
  Name : string;
begin
  Result := False;
  Name := '';
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
    end
    else
      Name := Name + N.Low;
    N := After(AMap, N);
  end;
end;

// Steht SysUtils in einer uses-Klausel der Datei?
function UsesSysUtils(AMap: TRdxCodeMap): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), NAME_USES);
  while T.Low <> '' do
  begin
    if (T.Low = NAME_USES) and IsKeywordAfter(T, Before(AMap, T))
       and ClauseHasSysUtils(AMap, T) then
      Exit(True);
    T := NextTokenOnLineWith(AMap, T, NAME_USES);
  end;
end;

// Die Zeile eines with vor ATok in seiner Routine (rueckwaerts bis zum
// Routinenkopf oder Unit-Abschnitt); 0 ohne. Ein with, dessen Bereich schon
// endete, sperrt mit - vorsichtig, nie falsch.
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
      if T.Low = 'with' then
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
function FileReason(AMap: TRdxCodeMap; const ANames: array of string;
  const AAt: TRdxToken; AInvariant: Boolean): string;
var
  i, Li, Member : Integer;
  Trace         : string;
begin
  if not UsesSysUtils(AMap) then
    Exit(_(R_FS_NO_SYSUTILS));
  for i := Low(ANames) to High(ANames) do
    if DeclaresRoutine(AMap, ANames[i]) then
      Exit(_(R_FS_OWN_ROUTINE, [ANames[i]]));
  if not AInvariant then
  begin
    Li := DeclLineOf(AMap, NAME_SETTINGS, Member);
    if Li > 0 then
      Exit(_(R_FS_SHADOW, [Li]));
    if Member > 0 then
      Exit(_(R_FS_MEMBER, [Member]));
  end;
  Li := WithLineBefore(AMap, AAt);
  if Li > 0 then
    Exit(_(R_FS_WITH, [Li]));
  if not AInvariant then
  begin
    Trace := OldCompilerTrace(AMap, FLOOR_SETTINGS_VAR, Li);
    if Trace <> '' then
      Exit(_(R_FS_OLD_VAR, [Trace, Li]));
    Exit('');
  end;
  Li := FpcTellLine(AMap);
  if Li > 0 then
    Exit(_(R_FS_FPC, [Li]));
  Trace := OldCompilerTrace(AMap, FLOOR_INLINE_DECL, Li);
  if Trace <> '' then
    Exit(_(R_FS_OLD_INVARIANT, [Trace, Li]));
  Li := DeclLineOf(AMap, NAME_SETTINGS_TYPE, Member);
  if Li > 0 then
    Exit(_(R_FS_OWN_TYPE, [Li]));
  Result := '';
end;

// EINE Ersetzung auf ALine: AInsert vor jede InsAt-Spalte; der Bereich von
// der ersten InsAt-Spalte bis hinter die letzte schliessende Klammer.
procedure BuildEdit(AMap: TRdxCodeMap; ALine: Integer;
  const ASites: array of TCallSite; const AInsert, ARole: string;
  out AEdit: TRdxEdit);
var
  L, S        : string;
  i, c        : Integer;
  First, Last : Integer;
begin
  AEdit := Default(TRdxEdit);
  L := AMap.Raw(ALine);
  First := MaxInt;
  Last := 0;
  for i := Low(ASites) to High(ASites) do
  begin
    if ASites[i].InsAt < First then
      First := ASites[i].InsAt;
    if ASites[i].Close.Col > Last then
      Last := ASites[i].Close.Col;
  end;
  S := '';
  for c := First to Last do
  begin
    for i := Low(ASites) to High(ASites) do
      if ASites[i].InsAt = c then
        S := S + AInsert;
    S := S + L[c];
  end;
  AEdit.Span := TRefactorSpan.Make(ARole, ALine, First, ALine, Last + 1);
  AEdit.Expected := RangeText(AMap, AEdit.Span);
  AEdit.NewText := S;
end;

function InsertFor(AInvariant: Boolean): string;
begin
  if AInvariant then
    Result := INSERT_INVARIANT
  else
    Result := INSERT_GLOBAL;
end;

// SCA128 fuer beide Wege.
function PlanLocale(AMap: TRdxCodeMap; ALine: Integer; const AMessage: string;
  AInvariant: Boolean; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Want  : string;
  Hits  : TArray<TRdxToken>;
  Sites : TCallSites;
  Names : TArray<string>;
  i, Li : Integer;
  Found : Boolean;
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
  Hits := nil;
  if (ALine >= 1) and (ALine <= AMap.LineCount) then
    Hits := NamesOnLine(AMap, ALine, LOCALE_FUNCS);
  if Length(Hits) = 0 then
  begin
    Li := 0;
    if (ALine >= 1) and (ALine <= AMap.LineCount) then
      Li := FollowLineWith(AMap, ALine, LOCALE_FUNCS);
    if Li > 0 then
      AReason := _(R_FS_NEXT_LINE, [Li])
    else
      AReason := MsgMovedSuffix(_(R_FS_MOVED, [Want]));
    Exit;
  end;
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
  for i := 0 to High(Hits) do
  begin
    AReason := ReadCall(AMap, Hits[i], LOCALE_ARITY[LocaleIndex(Hits[i].Low)],
      Sites[i]);
    if AReason <> '' then
      Exit;
    Names[i] := TokText(AMap, Hits[i]);
  end;
  Li := FollowLineWith(AMap, ALine, LOCALE_FUNCS);
  if Li > 0 then
  begin
    AReason := _(R_FS_CONTINUES, [Li]);
    Exit;
  end;
  AReason := FileReason(AMap, Names, Hits[0], AInvariant);
  if AReason <> '' then
    Exit;
  BuildEdit(AMap, ALine, Sites, InsertFor(AInvariant), SPAN_128, AEdit);
  Result := True;
end;

// SCA059 fuer beide Wege.
function PlanFormat(AMap: TRdxCodeMap; ALine: Integer; const AMessage: string;
  AInvariant: Boolean; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Fmt, Lit : string;
  Hits     : TArray<TRdxToken>;
  Site     : TCallSite;
  Li       : Integer;
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
  if (ALine >= 1) and (ALine <= AMap.LineCount) then
    Hits := NamesOnLine(AMap, ALine, FORMAT_FUNCS);
  if Length(Hits) = 0 then
  begin
    Li := 0;
    if (ALine >= 1) and (ALine <= AMap.LineCount) then
      Li := FollowLineWith(AMap, ALine, FORMAT_FUNCS);
    if Li > 0 then
      AReason := _(R_FS_NEXT_LINE, [Li])
    else
      AReason := MsgMovedSuffix(_(R_FL_NO_FORMAT));
    Exit;
  end;
  if Length(Hits) > 1 then
  begin
    AReason := _(R_FL_MANY, [ALine, Length(Hits)]);
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
  if LiteralFirstArg(AMap, ALine, Site.Open.EndCol, Site.Close.Col - 1, Lit)
     and (Lit <> Fmt) then
  begin
    AReason := MsgMovedSuffix(_(R_FL_OTHER_FMT));
    Exit;
  end;
  if AInvariant and TRdxFormatSettingsFix.HasMoneySpec(Fmt) then
  begin
    AReason := _(R_FL_MONEY);
    Exit;
  end;
  Li := FollowLineWith(AMap, ALine, FORMAT_FUNCS);
  if Li > 0 then
  begin
    AReason := _(R_FS_CONTINUES, [Li]);
    Exit;
  end;
  AReason := FileReason(AMap, [TokText(AMap, Hits[0])], Hits[0], AInvariant);
  if AReason <> '' then
    Exit;
  BuildEdit(AMap, ALine, [Site], InsertFor(AInvariant), SPAN_059, AEdit);
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

end.

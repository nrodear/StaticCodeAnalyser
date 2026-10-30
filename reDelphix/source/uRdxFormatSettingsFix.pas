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
//     des Namens deklariert;
//   * Alt-Weg: ein with in der Routine den Aufruf umfasst (die Namen
//     koennten an einen Member binden; seit rwE30 Stufe 2 zaehlt ein with,
//     dessen Anweisung vor dem Aufruf endet, nicht mehr - WithEndsBefore).
//     Der Hauptweg schreibt dort seit rwE31 Stufe 3 die globale Variable
//     qualifiziert (', System.SysUtils.FormatSettings' in der Schreibweise
//     der uses-Klausel; SynEditPrintMarginsDialog.pas:174 'with
//     SynEditMargins do .. FloatToStr(Left)', dlgSynPageSetup.pas:458,
//     ISPP.Funcs.pas:1599, SynUniDesigner.pas:2978): so bindet das Argument
//     an keinen Member. Haette das with-Ziel selbst eine Methode des
//     Aufrufnamens (FloatToStr ..), uebersetzte das zusaetzliche Argument
//     nicht - ein lauter Fehler, nie eine stille Aenderung;
//   * Hauptweg: die Datei nach Compilern vor Delphi XE fragt (die globale
//     Variable gibt es erst seit XE; FPC vor 2.6) - ausser sie beweist
//     selbst einen neueren (uRdxCompilerTraces.ModernProof). Seit rwE31
//     Stufe 3 fragt der Planer dabei nur die Bedingungen der Datei; ein
//     Kit-Include sperrt im Plattenblick, wenn kein Projekt der Unit ab XE
//     es widerlegt (uRdxMagicFixes.ProjectReason). Deklariert die
//     Datei einen Bezeichner FormatSettings (Feld, Variable, Parameter,
//     Property) oder nutzt sie ihn als Member, bande der blosse Name dort:
//     seit rwE30 Stufe 2 steht dann die globale Variable qualifiziert da
//     (', System.SysUtils.FormatSettings' in der Schreibweise der uses-
//     Klausel - dieselbe Variable; bis dahin sperrte das);
//   * Alt-Weg: die Datei eine FPC-Weiche oder einen FPC-Modus traegt (FPC
//     3.2.2 kennt kein TFormatSettings.Invariant) - ausser alle Aufrufe
//     stehen in einem Zweig ohne FPC ('{$IF NOT DEFINED(FPC)}') -, nach
//     Compilern vor Delphi 10.3 fragt (belegt ist Invariant in den Docwiki-
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
// eines in derselben Routine (HeidiSQL main.pas:14718), seit rwE31 Stufe 3
// das naechste, seit rwE32 Stufe 4 NUR eines derselben Routine und keines,
// wenn die Aufrufe nur Literale lesen. AUSSER (Nico-Ergaenzung zu M2, rwE31
// Stufe 3) das Ergebnis
// wird in derselben Routine direkt mit dem Gegenstueck bzw. mit
// FormatSettings gekoppelt ausgewertet ('Assert.AreEqual(s1, s2)',
// 'Pos(FormatSettings.DecimalSeparator, S)'): das bricht Verhalten, die
// Hilfe sperrt (CoupledReason; auch SCA059).
// Geht das Ergebnis direkt oder per Verkettung in eine Anzeige ('.Text',
// '.Caption', '.Hint', Items.Add, Lines.Add, ShowMessage ...), ist dort die
// Locale des Benutzers richtig: der Alt-Weg sperrt (Nico-Entscheid E6 nach
// rwE32 Stufe 4, DisplayReason; auch SCA059), der Hauptweg bleibt.
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
  // Bis rwE33 Stufe 5 'asks for compilers up to Delphi 10.3' - bei
  // COMPILER6_UP (Frage nach Delphi 6 und neuer, CnTestDesignMenuWizard.pas:
  // 303) falsch; jetzt wie R_FS_OLD_VAR (derselbe Satz als
  // R_KIT_OLD_INVARIANT in uRdxMagicFixes, eine msgid).
  R_FS_OLD_INVARIANT = 'the file asks for old compilers (%s, line %d) - '
    + 'TFormatSettings.Invariant is only checked from Delphi 10.3 on';
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
  // Alt-Weg (rwE31 Stufe 3, Nico-Ergaenzung zu M2): gekoppelte Auswertung
  // in derselben Routine (CoupledReason) - sperrt. %d die Zeile der
  // Kopplung, %s der Aufruf bzw. sein Ziel, %s FormatSettings wie
  // geschrieben samt Feld ...
  R_FS_COUPLED_SETTINGS = 'line %d evaluates %s together with %s - with '
    + 'TFormatSettings.Invariant here alone, the two would no longer fit '
    + 'together (decimal separator, date format)';
  // ... %d die Zeile der Kopplung, %s der Aufruf bzw. sein Ziel, %s das Ziel
  // des Gegenstuecks, %d seine Zeile, %s sein Aufruf ...
  R_FS_COUPLED_PAIR = 'line %d evaluates %s together with %s, which line %d '
    + 'writes with %s without TFormatSettings.Invariant - with only this call '
    + 'changed, the two no longer match';
  // ... %d die Zeile des Gegenstuecks, %s das Ziel des Aufrufs, %s das
  // Gegenstueck.
  R_FS_COUPLED_CALL = 'line %d evaluates %s together with %s without '
    + 'TFormatSettings.Invariant - with only this call changed, the two no '
    + 'longer match';
  // Alt-Weg (rwE32 Stufe 4, Nico-Entscheid E6): das Ergebnis geht in eine
  // Anzeige (DisplayReason) - %d die Zeile des Ziels, %s das Ziel wie
  // geschrieben ('StatusBar1.Panels[1].Text', 'ListBox1.Items.Add').
  R_FS_DISPLAY = 'line %d shows the result on screen (%s) - there the user '
    + 'locale is the right one; TFormatSettings.Invariant would show decimal '
    + 'point and MM/dd/yyyy';
  // Alt-Weg (rwE32 Stufe 4, ClassSettingsReason): die Klasse der Methode
  // traegt ein eigenes TFormatSettings-Feld, das sie fuer Aufrufe derselben
  // Familie uebergibt (seit rwE33 Stufe 5) - %s die Klasse, %s das Feld, %d
  // seine Zeile.
  R_FS_CLASS_SETTINGS = 'the class %s carries its own format settings %s '
    + '(line %d) - pass those by hand instead of TFormatSettings.Invariant, '
    + 'which would drop what is set there';
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
    // Familie ohne Invariant bzw. eigene Einstellungen - R_FS_PAIR_HINT mit
    // ABaseHint, Zeile und Name des naechsten solchen Aufrufs in der
    // Routine (bis rwE32 Stufe 4 danach in der Datei, bis rwE31 Stufe 3 des
    // ersten). Liest die Zeile keinen Aufruf oder lesen ihre Aufrufe nur
    // Literale ('StrToTime(''00:00:01'')'), ABaseHint.
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
  NAME_FMT_SETTINGS  = 'fmtsettings';
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

// Die Klammertiefe ('(' und '[') am Ende der Zeile ALine, ab ihrem ersten
// Token gezaehlt.
function DepthAtLineEnd(AMap: TRdxCodeMap; ALine: Integer): Integer;
var
  T : TRdxToken;
begin
  Result := 0;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    Result := Result + ParenDelta(T);
    T := After(AMap, T);
  end;
end;

// Die Woerter ANames (nicht hinter '@') auf den Folgezeilen der Anweisung
// von ALine - die Anweisung endet am ';' bzw. an einem Schluesselwort aus
// STATEMENT_STOP, gesucht wird hoechstens MAX_FOLLOW_LINES Zeilen weit.
// Seit rwE30 Stufe 2 bearbeitet die Hilfe sie mit (Planer kennt die
// Aufrufzeile; MainControllerU.pas:47, wbLOD.pas:3082), statt abzulehnen.
// Seit rwE31 Stufe 3 zaehlen ';' und Schluesselwoerter nur auf Klammertiefe
// 0: in einer offenen Klammer stehen sie in einer anonymen Methode, die zur
// Anweisung gehoert (Alcinoe Main.pas:1444 'TTask.Create (procedure () begin
// .. Text4.Text := .. FormatFloat(..) .. end).Start;' - der Detektor meldet
// die Zeile von TTask.Create, die Aufrufe stehen in 1450/1451; bis dahin
// 'kein Aufruf ... - Zeile verschoben?'). Eine Klammer, die vor ALine
// geoeffnet wurde, beendet die Suche.
function FollowNames(AMap: TRdxCodeMap; ALine: Integer;
  const ANames: array of string): TArray<TRdxToken>;
var
  T, P  : TRdxToken;
  Depth : Integer;
begin
  Result := nil;
  T := LastTokenOn(AMap, ALine);
  if T.Low = '' then
    Exit;
  Depth := DepthAtLineEnd(AMap, ALine);
  if (Depth <= 0) and InList(T.Low, STATEMENT_DONE) then
    Exit;
  P := T;
  T := After(AMap, T);
  while (T.Low <> '') and (T.Line - ALine <= MAX_FOLLOW_LINES) do
  begin
    if Depth <= 0 then
    begin
      if T.Low = ';' then
        Exit;
      if IsKeywordAfter(T, P) and InList(T.Low, STATEMENT_STOP) then
        Exit;
    end;
    Depth := Depth + ParenDelta(T);
    if Depth < 0 then
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

// Liest der Aufruf ASite (StrToFloat, StrToCurr, StrToDate, StrToTime,
// StrToDateTime) nur ein Literal - das Argument besteht bis zur Klammer auf
// derselben Zeile aus String-Literalen ('StrToTime(''00:00:01'')')? Dann
// kommt der gelesene Text aus keinem geschriebenen Wert (PairHint, rwE32
// Stufe 4: minesweeper uGameScore.pas:144).
function ReadsOnlyLiteral(AMap: TRdxCodeMap; const ASite: TCallSite): Boolean;
var
  Lit    : string;
  Li, Co : Integer;
begin
  Result := (InList(ASite.Name.Low, PARSE_NUMBER)
      or (ASite.Name.Low = PARSE_DATE) or (ASite.Name.Low = PARSE_TIME)
      or (ASite.Name.Low = PARSE_DATETIME))
    and FirstCharAfter(AMap, ASite.Open, Li, Co)
    and (Li = ASite.Close.Line) and (Co < ASite.Close.Col)
    and LiteralFirstArg(AMap, Li, Co, ASite.Close.Col - 1, Lit);
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
// darum nennt der Hinweis (PairHint) den naechsten weiteren Aufruf
// derselben Familie (PAIR_DATE bzw. PAIR_NUMBER) in der Routine, der kein
// Invariant uebergibt (bis rwE32 Stufe 4 auch in der Datei). Bis zum
// Entscheid M2 (Review e/HilfeFixC) sperrte er.

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

// Traegt ein Bezeichner eigene Einstellungen im Namen ('fLocaleFormatSettings',
// 'FmtSettings') - nicht den blossen globalen Namen FormatSettings?
function NamesOwnSettings(AMap: TRdxCodeMap; const N: TRdxToken): Boolean;
var
  P : TRdxToken;
begin
  Result := False;
  if not N.IsWord then Exit;
  if N.Low = NAME_SETTINGS then
  begin
    // 'X.FormatSettings' (X nicht SysUtils) ist ein Member - eigene.
    P := Before(AMap, N);
    Exit((P.Low = '.') and not RtlQualified(AMap, P));
  end;
  Result := (Pos(NAME_SETTINGS, N.Low) > 0) or (Pos(NAME_FMT_SETTINGS, N.Low) > 0);
end;

// Uebergibt der Aufruf am Namen T in seinen Klammern eigene Einstellungen -
// 'Invariant' oder seit rwE31 Stufe 3 einen Bezeichner wie
// 'fLocaleFormatSettings' (NamesOwnSettings)? Dann liest er die globale
// FormatSettings nicht und ist kein Gegenstueck: TemplatePro.pas:3365 - der
// Hinweis riet, Zeile 3378 mit fLocaleFormatSettings mit umzustellen (das
// verwuerfe die Template-Locale). Ohne Klammer bzw. ohne gefundene
// schliessende: nein.
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
    if (N.Low = NAME_INVARIANT) or NamesOwnSettings(AMap, N) then
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

// Die Familien der Aufrufe ASites: Datum/Uhrzeit (PAIR_DATE), Zahl
// (PAIR_NUMBER).
procedure FamiliesOf(const ASites: TCallSites; out AWantDate,
  AWantNum: Boolean);
var
  i : Integer;
begin
  AWantDate := False;
  AWantNum := False;
  for i := 0 to High(ASites) do
  begin
    AWantDate := AWantDate or InList(ASites[i].Name.Low, PAIR_DATE);
    AWantNum := AWantNum or InList(ASites[i].Name.Low, PAIR_NUMBER);
  end;
end;

// Ist T ein Gegenstueck der Aufrufe ASites: ein Aufruf der gewuenschten
// Familie, nicht einer der Aufrufe selbst, kein Member-Aufruf ('X.DateToStr',
// X nicht SysUtils - eine andere Routine) und ohne eigene Einstellungen
// (PassesInvariant)?
function IsPartnerAt(AMap: TRdxCodeMap; const T: TRdxToken;
  const ASites: TCallSites; AWantDate, AWantNum: Boolean): Boolean;
var
  P : TRdxToken;
begin
  Result := T.IsWord
    and ((AWantDate and InList(T.Low, PAIR_DATE))
         or (AWantNum and InList(T.Low, PAIR_NUMBER)))
    and not IsEditedName(T, ASites);
  if not Result then Exit;
  P := Before(AMap, T);
  Result := ((P.Low <> '.') or RtlQualified(AMap, P))
    and not PassesInvariant(AMap, T);
end;

// Der weitere Aufruf der Familie(n) der Aufrufe ASites in den Zeilen
// AFrom..ATo ohne Invariant (s. Kopf des Abschnitts), der ASites[0] am
// NAECHSTEN steht: seine Zeile und sein Name wie geschrieben in AName; 0
// ohne. Bis rwE31 Stufe 3 der ERSTE der Zeilen - FrameworkTestsU.pas:1964
// nannte Zeile 1956 (s1 des vorigen Blocks) statt des direkt verglichenen
// s2 in Zeile 1965, wbLOD.pas:3543 Zeile 1902 statt 3513.
function PairBreakIn(AMap: TRdxCodeMap; const ASites: TCallSites;
  AFrom, ATo: Integer; out AName: string): Integer;
var
  WantDate, WantNum : Boolean;
  Li, Dist, Best    : Integer;
  T                 : TRdxToken;
  LowText           : string;
begin
  Result := 0;
  AName := '';
  if Length(ASites) = 0 then Exit;
  Best := MaxInt;
  FamiliesOf(ASites, WantDate, WantNum);
  for Li := AFrom to ATo do
  begin
    Dist := Abs(Li - ASites[0].Name.Line);
    if Dist >= Best then
      Continue;
    LowText := LowerCase(AMap.Raw(Li));
    if not ((WantDate and MentionsAny(LowText, PAIR_DATE_HINTS))
            or (WantNum and MentionsAny(LowText, PAIR_NUMBER_HINTS))) then
      Continue;
    T := NextToken(AMap, Li, 1);
    while (T.Low <> '') and (T.Line = Li) do
    begin
      if IsPartnerAt(AMap, T, ASites, WantDate, WantNum) then
      begin
        AName := TokText(AMap, T);
        Result := Li;
        Best := Dist;
        Break;
      end;
      T := After(AMap, T);
    end;
  end;
end;

// PairBreakIn im Rumpf der Routine um den ersten Aufruf (rwE30 Stufe 2,
// HeidiSQL main.pas:14718: der Vergleich mit 'DateToStr(Item.Time)' steht
// in derselben Routine, der Hinweis nannte Zeile 1782 einer anderen). Seit
// rwE32 Stufe 4 NUR dort (M2: Kopplung gibt es in derselben Anweisung bzw.
// Routine): bis dahin suchte die Funktion ohne Treffer in der Routine die
// ganze Datei ab und nannte Aufrufe anderer Routinen ohne Datenfluss -
// TES5Edit wbInterface.pas:17009 (Meldungstext) die Zeile 17104 in
// TwbFloatDef.ToSortKey, Alcinoe ALFmxControls Main.pas:1491 die Anzeige
// des naechsten Buttons. Ohne gefundene Routine: 0.
function PairBreakLine(AMap: TRdxCodeMap; const ASites: TCallSites;
  out AName: string): Integer;
var
  R : TRdxRoutine;
begin
  Result := 0;
  AName := '';
  if (Length(ASites) > 0)
     and (BeginBodyAround(AMap, ASites[0].Name, R) = rbfFound) then
    Result := PairBreakIn(AMap, ASites, R.Body.Line, R.EndTok.Line, AName);
end;

// ---- Gekoppelte Auswertung (Alt-Weg, rwE31 Stufe 3) ----
// Nico-Ergaenzung zu M2: ein Gegenstueck, das in derselben Routine DIREKT
// mit dem Ergebnis verglichen oder mit ihm gekoppelt ausgewertet wird, ist
// kein Hinweisfall - nur diese Seite auf Invariant gestellt, bricht das
// Verhalten; die Hilfe sperrt (CoupledReason). Fundstellen:
// FrameworkTestsU.pas:1986 ('s1 := DateTimeToStr(lDate); s2 :=
// DateTimeToStr(lDateToCompare); Assert.areEqual(s1,s2, ..)' - nur s2 auf
// Invariant, und der Test scheitert ausser in en-US), :1964 (dasselbe mit
// s1), MVCFramework.Validators.pas:1647 ('LStrValue := FloatToStr(..);
// LDecimalPos := Pos(FormatSettings.DecimalSeparator, LStrValue)' - mit
// Invariant findet Pos in Komma-Locales keinen Trenner mehr), SCA059
// IDE.MainForm.pas:6170 (die Argumente des Format lesen selbst
// FormatSettings.TimeSeparator - Invariant mischte beide Formate).
// Gelesen wird je Stueck einer Anweisung (PiecesIn): die Token zwischen
// ';' und den Schluesselwoertern PIECE_BREAKS - 'if s1 = s2 then' traegt
// das Stueck 'if s1 = s2', 'Assert.AreEqual(s1, s2);' eines. Ein Stueck ist
// gekoppelt, wenn es
//   * einen der umgestellten Aufrufe traegt bzw. das Ziel V der
//     umgestellten Zuweisung ('V := FloatToStr(..)') nennt und dazu
//     FormatSettings liest (R_FS_COUPLED_SETTINGS);
//   * V und das Ziel W eines Gegenstuecks (IsPartnerAt; 'W := DateToStr(..)')
//     nennt, bzw. das umgestellte Stueck W nennt (R_FS_COUPLED_PAIR);
//   * selbst das Gegenstueck traegt und V nennt ('if DateToStr(x) = V',
//     'TryStrToCurr(V, y)' - R_FS_COUPLED_CALL).
// V bzw. W zaehlen nur hinter einem schreibenden Aufruf (TEXT_WRITERS):
// dann sind sie Text im jeweiligen Format; hinter einem Leser stehen Zahl
// bzw. Datum, und deren Vergleich haengt nicht am Format.
// Gemeldet wird die Kopplung mit dem Gegenstueck, das dem Aufruf am
// naechsten steht. Ohne gefundene Routine (rbfUnsure, rbfNone) bleibt es
// beim Hinweis (PairHint). Was ueber weitere Variablen laeuft, sieht die
// Hilfe nicht - sie sperrt die direkte Kopplung, nicht jede.

type
  // Ein Stueck einer Anweisung: erstes und letztes Token (s. oben).
  TPiece = record
    First : TRdxToken;
    Last  : TRdxToken;
  end;
  TPieces = array of TPiece;

const
  // Hier endet ein Stueck (dazu ';').
  PIECE_BREAKS: array[0..10] of string = ('begin', 'end', 'then', 'do',
    'else', 'try', 'finally', 'except', 'repeat', 'until', 'of');
  NAME_VAR = 'var';
  // Was TEXT schreibt (das Ziel V bzw. W traegt dann das Format; bei einem
  // Leser ist es eine Zahl bzw. ein Datum - dessen Vergleich haengt nicht
  // am Format: 'x := StrToCurr(s); r := FormatCurr(.., x)' ist keine
  // Kopplung).
  TEXT_WRITERS: array[0..10] of string = ('datetostr', 'timetostr',
    'datetimetostr', 'formatdatetime', 'floattostr', 'currtostr',
    'formatfloat', 'formatcurr', 'floattostrf', 'currtostrf', 'format');

// Die Stuecke zwischen AFrom und ATo (beide ausgenommen).
function PiecesIn(AMap: TRdxCodeMap; const AFrom, ATo: TRdxToken): TPieces;
var
  T, P : TRdxToken;
  N    : Integer;
  Open : Boolean;
begin
  Result := nil;
  N := 0;
  Open := False;
  P := AFrom;
  T := After(AMap, AFrom);
  while (T.Low <> '') and TokBefore(T, ATo) do
  begin
    if (T.Low = ';')
       or (IsKeywordAfter(T, P) and InList(T.Low, PIECE_BREAKS)) then
      Open := False
    else
    begin
      if not Open then
      begin
        if N = Length(Result) then
          SetLength(Result, 2 * N + 16);
        Result[N].First := T;
        Inc(N);
        Open := True;
      end;
      Result[N - 1].Last := T;
    end;
    P := T;
    T := After(AMap, T);
  end;
  SetLength(Result, N);
end;

// Liegt T im Stueck APiece?
function InPiece(const T: TRdxToken; const APiece: TPiece): Boolean;
begin
  Result := not TokBefore(T, APiece.First) and not TokBefore(APiece.Last, T);
end;

// Traegt das Stueck einen der Aufrufe ASites?
function PieceHasSite(const APiece: TPiece; const ASites: TCallSites): Boolean;
var
  i : Integer;
begin
  for i := 0 to High(ASites) do
    if InPiece(ASites[i].Name, APiece) then
      Exit(True);
  Result := False;
end;

// Nennt das Stueck den Namen ALow (klein) als Wort, nicht als Member
// ('X.s1')? '' nie.
function PieceNames(AMap: TRdxCodeMap; const APiece: TPiece;
  const ALow: string): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  if ALow = '' then Exit;
  T := APiece.First;
  while T.Low <> '' do
  begin
    if T.IsWord and (T.Low = ALow) and (Before(AMap, T).Low <> '.') then
      Exit(True);
    if SameTok(T, APiece.Last) then Exit;
    T := After(AMap, T);
  end;
end;

// Liest das Stueck FormatSettings - die globale Variable oder einen Member
// dieses Namens (beide passen nicht zu Invariant)? AText: wie geschrieben
// samt Feld ('FormatSettings.DecimalSeparator'), ALine seine Zeile.
function PieceSettings(AMap: TRdxCodeMap; const APiece: TPiece;
  out AText: string; out ALine: Integer): Boolean;
var
  T, D, F : TRdxToken;
begin
  Result := False;
  AText := '';
  ALine := 0;
  T := APiece.First;
  while T.Low <> '' do
  begin
    if T.IsWord and (T.Low = NAME_SETTINGS) then
    begin
      AText := TokText(AMap, T);
      ALine := T.Line;
      D := After(AMap, T);
      F := After(AMap, D);
      if (D.Low = '.') and F.IsWord and InPiece(F, APiece) then
        AText := AText + '.' + TokText(AMap, F);
      Exit(True);
    end;
    if SameTok(T, APiece.Last) then Exit;
    T := After(AMap, T);
  end;
end;

// Das Ziel der Zuweisung des Stuecks: der Bezeichner vor dem ersten ':='
// auf Klammertiefe 0 - 'V := ..', hinter einer case-Marke 'dbdtDate: V :=
// ..' (HeidiSQL main.pas:11246 - die Zweige schreiben alle dieselbe
// Variable, das ist keine Kopplung), die Inline-Variable 'var V := ..' bzw.
// 'var V: T := ..'. Leer ohne bzw. fuer ein Member ('X.V :=', 'A[i] :=').
function PieceTarget(AMap: TRdxCodeMap; const APiece: TPiece): TRdxToken;
var
  T, P, B : TRdxToken;
  Depth   : Integer;
begin
  Result := Default(TRdxToken);
  Depth := 0;
  P := Default(TRdxToken);
  T := APiece.First;
  while T.Low <> '' do
  begin
    if (T.Low = ':=') and (Depth = 0) then
    begin
      if not P.IsWord then Exit;
      B := Before(AMap, P);
      // 'var V: T :=' - das Ziel steht vor dem ':'.
      if (B.Low = ':') and (Before(AMap, Before(AMap, B)).Low = NAME_VAR) then
        Exit(Before(AMap, B));
      if B.Low = '.' then Exit;
      Exit(P);
    end;
    Depth := Depth + ParenDelta(T);
    if SameTok(T, APiece.Last) then Exit;
    P := T;
    T := After(AMap, T);
  end;
end;

// Das erste Gegenstueck (IsPartnerAt) im Stueck; leer ohne.
function PiecePartner(AMap: TRdxCodeMap; const APiece: TPiece;
  const ASites: TCallSites; AWantDate, AWantNum: Boolean): TRdxToken;
var
  T : TRdxToken;
begin
  Result := Default(TRdxToken);
  T := APiece.First;
  while T.Low <> '' do
  begin
    if IsPartnerAt(AMap, T, ASites, AWantDate, AWantNum) then
      Exit(T);
    if SameTok(T, APiece.Last) then Exit;
    T := After(AMap, T);
  end;
end;

// Merkt den Grund AReason vor, wenn das Gegenstueck auf APartnerLine
// naeher an ALine0 steht als das bisher beste (ABest), bei Gleichstand die
// Kopplung auf ACoupleLine, die ALine0 am naechsten FOLGT (eine Kopplung
// davor gilt einem frueheren Wert: FrameworkTestsU.pas:1964 - der
// Vergleich in Zeile 1958 gehoert zum vorigen s1, der in 1966 zu diesem).
procedure NoteCoupling(ALine0, APartnerLine, ACoupleLine: Integer;
  const AReason: string; var ABest: Int64; var AResult: string);
var
  Score : Int64;
  Ahead : Integer;
begin
  Ahead := ACoupleLine - ALine0;
  if Ahead < 0 then
    Ahead := MaxInt div 2 - Ahead;
  Score := Int64(Abs(APartnerLine - ALine0)) * MaxInt + Ahead;
  if Score < ABest then
  begin
    ABest := Score;
    AResult := AReason;
  end;
end;

// Der Grund der gekoppelten Auswertung (s. Kopf des Abschnitts); '' ohne.
function CoupledReason(AMap: TRdxCodeMap; const ASites: TCallSites): string;
var
  R                 : TRdxRoutine;
  Pieces            : TPieces;
  Edited            : array of Boolean;
  i, k, Li, Line0   : Integer;
  V, W, Partner     : TRdxToken;
  Text, Call        : string;
  WantDate, WantNum : Boolean;
  Writer            : Boolean;
  Best              : Int64;
begin
  Result := '';
  if (Length(ASites) = 0)
     or (BeginBodyAround(AMap, ASites[0].Name, R) <> rbfFound) then
    Exit;
  Line0 := ASites[0].Name.Line;
  Call := TokText(AMap, ASites[0].Name);
  Pieces := PiecesIn(AMap, R.Body, R.EndTok);
  SetLength(Edited, Length(Pieces));
  V := Default(TRdxToken);
  for i := 0 to High(Pieces) do
  begin
    Edited[i] := PieceHasSite(Pieces[i], ASites);
    if Edited[i] and (V.Low = '') then
      V := PieceTarget(AMap, Pieces[i]);
  end;
  // Nur ein schreibender Aufruf macht V zu Text im umgestellten Format.
  Writer := False;
  for i := 0 to High(ASites) do
    Writer := Writer or InList(ASites[i].Name.Low, TEXT_WRITERS);
  if not Writer then
    V := Default(TRdxToken);
  Best := High(Int64);
  // FormatSettings im umgestellten Stueck bzw. neben V.
  for i := 0 to High(Pieces) do
    if Edited[i] and PieceSettings(AMap, Pieces[i], Text, Li) then
      NoteCoupling(Line0, Li, Li, _(R_FS_COUPLED_SETTINGS, [Li, Call, Text]),
        Best, Result)
    else if (V.Low <> '') and PieceNames(AMap, Pieces[i], V.Low)
            and PieceSettings(AMap, Pieces[i], Text, Li) then
      NoteCoupling(Line0, Li, Li, _(R_FS_COUPLED_SETTINGS,
        [Li, TokText(AMap, V), Text]), Best, Result);
  if Result <> '' then Exit;
  // Gegenstuecke derselben Familie.
  FamiliesOf(ASites, WantDate, WantNum);
  if not (WantDate or WantNum) then Exit;
  for i := 0 to High(Pieces) do
  begin
    Partner := PiecePartner(AMap, Pieces[i], ASites, WantDate, WantNum);
    if Partner.Low = '' then Continue;
    // Das Gegenstueck in der umgestellten Anweisung selbst (Review
    // e/HilfeFixK): 'if TryStrToFloat(FloatToStr(x), y)', 'if FloatToStrF(a,
    // ..) = FloatToStr(b)' - Rundlauf bzw. direkter Vergleich; TryStrToFloat
    // und FloatToStrF stellt die Hilfe nicht mit um (LOCALE_FUNCS).
    if Edited[i] then
    begin
      NoteCoupling(Line0, Partner.Line, Partner.Line, _(R_FS_COUPLED_CALL,
        [Partner.Line, Call, TokText(AMap, Partner)]), Best, Result);
      Continue;
    end;
    W := Default(TRdxToken);
    if InList(Partner.Low, TEXT_WRITERS) then
      W := PieceTarget(AMap, Pieces[i]);
    if (V.Low <> '') and (W.Low <> V.Low)
       and PieceNames(AMap, Pieces[i], V.Low) then
      NoteCoupling(Line0, Partner.Line, Partner.Line, _(R_FS_COUPLED_CALL,
        [Partner.Line, TokText(AMap, V), TokText(AMap, Partner)]), Best,
        Result);
    if (W.Low = '') or (W.Low = V.Low) then Continue;
    for k := 0 to High(Pieces) do
      if Edited[k] and PieceNames(AMap, Pieces[k], W.Low) then
        NoteCoupling(Line0, Partner.Line, Pieces[k].First.Line,
          _(R_FS_COUPLED_PAIR, [Pieces[k].First.Line, Call,
          TokText(AMap, W), Partner.Line, TokText(AMap, Partner)]), Best,
          Result)
      else if (k <> i) and not Edited[k] and (V.Low <> '')
              and PieceNames(AMap, Pieces[k], V.Low)
              and PieceNames(AMap, Pieces[k], W.Low) then
        NoteCoupling(Line0, Partner.Line, Pieces[k].First.Line,
          _(R_FS_COUPLED_PAIR, [Pieces[k].First.Line, TokText(AMap, V),
          TokText(AMap, W), Partner.Line, TokText(AMap, Partner)]), Best,
          Result);
  end;
end;

// ---- Anzeige-Ziel (Alt-Weg, rwE32 Stufe 4, Nico-Entscheid E6) ----
// Geht das Ergebnis eines Aufrufs direkt oder ueber Verkettung ('+') in
// derselben Anweisung in eine Anzeige, ist dort die Locale des Benutzers
// richtig - TFormatSettings.Invariant zeigte Punkt und MM/dd/yyyy; die Hilfe
// sperrt (DisplayReason; Eintrag 1 bleibt). Anzeige heisst:
//   * Zuweisung an '.Text', '.Caption', '.Hint' (auch 'StatusBar1.Panels[1].
//     Text') - '.Text' nicht, wenn ein Glied der Kette nach Daten klingt
//     (DATA_PARTS: 'Query.SQL.Text', 'Node.Text', 'Json.Text') oder der
//     Besitzer eine Stringliste sein kann (TEXT_OWNERS: 'SL.Text');
//   * seit rwE33 Stufe 5 Zuweisung an 'X.Cells[..]' (TStringGrid; mORMot2
//     dmvc-ai 56-articles_crud_vcl_client MainFormU.pas:206, DATA_PARTS wie
//     bei '.Text') und an den var- bzw. out-Parameter 'CellText' bzw.
//     'HintText' der Routine (OnGetText/OnGetHint des VirtualTree; TES5Edit
//     xeLogAnalyzerForm.pas:326/:329, SCA059) - ein gleichnamiger
//     Wert-Parameter, eine lokale Variable oder ein Member zaehlen nicht;
//   * Argument von 'Items.Add', 'Items.Insert', 'Lines.Add', 'Lines.Insert',
//     'ShowMessage', 'MessageDlg', 'Application.MessageBox'.
// Gelesen wird rueckwaerts ab dem Namen (samt 'SysUtils.'): Klammergruppen
// werden uebersprungen, auf Tiefe 0 duerfen nur Woerter, Zahlen, '+', ',',
// '.' stehen (Strings und Kommentare sind keine Token); die erste offene
// Klammer entscheidet - eine Gruppierung ('(' hinter '+', ',', '(' oder
// ':=') und eine Typumwandlung ('PChar(') lesen weiter, eine Routine
// ausser den genannten ('Copy(', 'Trim(',
// 'Format(' mit '[..]') beendet die Suche ohne Anzeige, ebenso ';', ein
// Schluesselwort oder ein anderer Operator. Fundstellen: Alcinoe
// ALCipher Unit1.pas:831, ALFmxControls Main.pas:1436/1444/1491,
// ALStringBenchmark Unit1.pas:501 .., ALXmlDoc unit1.pas:307, RSS-1723
// Unit1.pas:54, delphimvcframework async_client MainClientFormU.pas:329
// ('lbPerson.Items.Add(''DOB:''.PadRight(15) + DateToStr(..))') und SCA059
// :484. Was ueber Variablen, Rueckgabewerte oder anonyme Methoden in die
// Anzeige laeuft (mvcasync MainFormU.pas:37 'Result := DateTimeToStr(Now)',
// Value -> Edit1.Text), sieht die Hilfe nicht - dort bleibt Eintrag 2 wie
// bisher angeboten (aendert Verhalten, nie per Taste).

const
  DISPLAY_PROPS: array[0..2] of string = ('text', 'caption', 'hint');
  DISPLAY_LISTS: array[0..1] of string = ('items', 'lines');
  DISPLAY_LIST_CALLS: array[0..1] of string = ('add', 'insert');
  DISPLAY_DIALOGS: array[0..1] of string = ('showmessage', 'messagedlg');
  NAME_TEXT = 'text';
  NAME_APPLICATION = 'application';
  NAME_MESSAGEBOX = 'messagebox';
  NAME_DIALOGS = 'dialogs';
  // 'Grid.Cells[c, r] :=' (TStringGrid, TDrawGrid; rwE33 Stufe 5).
  NAME_CELLS = 'cells';
  // Die Text-Parameter der Anzeige-Ereignisse (OnGetText, OnGetHint des
  // VirtualTree; rwE33 Stufe 5) - nur als var- bzw. out-Parameter
  // (VarParamOf) ...
  DISPLAY_PARAMS: array[0..1] of string = ('celltext', 'hinttext');
  // ... davor steht der Name im Kopf, dahinter folgt ...
  PARAM_PREV: array[0..6] of string = ('(', ';', ',', 'const', 'var', 'out',
    'constref');
  PARAM_NEXT: array[0..3] of string = (',', ':', ';', ')');
  // ... und so beginnt eine Gruppe, in die die Routine schreibt.
  PARAM_WRITABLE: array[0..1] of string = ('var', 'out');
  // Teile von Namen, die bei '.Text' nach Daten statt Anzeige klingen ...
  DATA_PARTS: array[0..13] of string = ('sql', 'xml', 'json', 'node', 'query',
    'param', 'field', 'attr', 'stream', 'request', 'response', 'body',
    'writer', 'builder');
  // ... und Besitzer von '.Text', die eine Stringliste sein koennen.
  TEXT_OWNERS: array[0..4] of string = ('sl', 'list', 'strings', 'stringlist',
    'result');
  // Was auf Tiefe 0 zwischen Aufruf und Ziel stehen darf (dazu Woerter, die
  // kein Schluesselwort sind, und Zahlen).
  DISPLAY_GLUE: array[0..2] of string = ('+', ',', '.');
  // Davor ist eine offene Klammer eine Gruppierung (kein Aufruf).
  GROUP_BEFORE: array[0..3] of string = ('+', ',', '(', ':=');
  // Typumwandlungen, durch die der Text unveraendert geht
  // ('Application.MessageBox(PChar(..), ..)').
  TEXT_CASTS: array[0..2] of string = ('pchar', 'pwidechar', 'string');
  MAX_DISPLAY_TOKENS = 2000;
  // 'Self.FFS' als Argument (FieldUsedForFamily).
  NAME_SELF = 'self';
  // Was ein Muster als erstes Argument nimmt (ClassSettingsReason).
  PATTERN_WRITERS: array[0..3] of string = ('formatdatetime', 'formatfloat',
    'formatcurr', 'format');

// Die oeffnende Klammer zur schliessenden AClose (rueckwaerts); leer ohne.
function OpenerOf(AMap: TRdxCodeMap; const AClose: TRdxToken): TRdxToken;
var
  T     : TRdxToken;
  Depth : Integer;
  Count : Integer;
begin
  Result := Default(TRdxToken);
  Depth := 0;
  Count := 0;
  T := AClose;
  while (T.Low <> '') and (Count < MAX_DISPLAY_TOKENS) do
  begin
    Depth := Depth - ParenDelta(T);
    if Depth = 0 then
      Exit(T);
    Inc(Count);
    T := Before(AMap, T);
  end;
end;

// Der Anfang der Kette 'A.B[i].C' bis ALast (rueckwaerts ueber '.', Woerter
// und Klammergruppen hinter einem Glied).
function ChainStart(AMap: TRdxCodeMap; const ALast: TRdxToken): TRdxToken;
var
  P, T : TRdxToken;
begin
  Result := ALast;
  P := Before(AMap, Result);
  while P.Low = '.' do
  begin
    T := Before(AMap, P);
    while (T.Low = ']') or (T.Low = ')') do
    begin
      T := OpenerOf(AMap, T);
      if T.Low = '' then Exit;
      T := Before(AMap, T);
    end;
    if not T.IsWord then Exit;
    Result := T;
    P := Before(AMap, Result);
  end;
end;

// Die Kette von ChainStart bis ALast wie geschrieben (eine Zeile; sonst
// nur ALast).
function ChainText(AMap: TRdxCodeMap; const ALast: TRdxToken): string;
var
  S : TRdxToken;
begin
  S := ChainStart(AMap, ALast);
  if S.Line <> ALast.Line then
    Exit(TokText(AMap, ALast));
  Result := Copy(AMap.Raw(S.Line), S.Col, ALast.EndCol - S.Col);
end;

// Nennt ein Glied der Kette vor ALast etwas, das nach Daten klingt, oder ist
// der Besitzer von ALast eine moegliche Stringliste (s. Kopf des Abschnitts)?
function ChainLooksLikeData(AMap: TRdxCodeMap; const ALast: TRdxToken): Boolean;
var
  S, T, Owner : TRdxToken;
  i           : Integer;
begin
  S := ChainStart(AMap, ALast);
  Owner := Default(TRdxToken);
  T := S;
  while (T.Low <> '') and TokBefore(T, ALast) do
  begin
    if T.IsWord then
    begin
      for i := Low(DATA_PARTS) to High(DATA_PARTS) do
        if Pos(DATA_PARTS[i], T.Low) > 0 then
          Exit(True);
      Owner := T;
    end;
    T := After(AMap, T);
  end;
  Result := (Owner.Low <> '') and InList(Owner.Low, TEXT_OWNERS);
end;

// Ist AName (vor einer offenen Klammer) eine Anzeige-Routine (s. Kopf)?
// True mit dem Ziel wie geschrieben und seiner Zeile.
function DisplayCall(AMap: TRdxCodeMap; const AName: TRdxToken;
  out AWhat: string; out ALine: Integer): Boolean;
var
  P, Q : TRdxToken;
begin
  AWhat := '';
  ALine := 0;
  P := Before(AMap, AName);
  Q := Before(AMap, P);
  if InList(AName.Low, DISPLAY_DIALOGS) then
    Result := (P.Low <> '.') or (Q.Low = NAME_DIALOGS)
  else if AName.Low = NAME_MESSAGEBOX then
    Result := (P.Low = '.') and (Q.Low = NAME_APPLICATION)
  else if InList(AName.Low, DISPLAY_LIST_CALLS) then
    Result := (P.Low = '.') and InList(Q.Low, DISPLAY_LISTS)
  else
    Result := False;
  if Result then
  begin
    AWhat := ChainText(AMap, AName);
    ALine := AName.Line;
  end;
end;

// Ist ANameLow im Kopf von R ein var- oder out-Parameter ('var CellText:
// string', 'out A, B: Integer')? Gelesen wie uRdxTypeProof.ParamOf (dort
// ohne die Art des Parameters): Klammern in Typ oder Vorgabewert zaehlen
// nicht, ein Attribut vor dem Namen ('[Ref]') ebenso wenig - dann nein.
function VarParamOf(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const ANameLow: string): Boolean;
var
  T, P, Close : TRdxToken;
begin
  Result := False;
  T := After(AMap, R.NameTok);
  if T.Low = '<' then
    T := AfterClose(AMap, T);
  if T.Low <> '(' then
    Exit;
  Close := MatchClose(AMap, T);
  if Close.Low = '' then
    Exit;
  P := T;
  T := After(AMap, T);
  while (T.Low <> '') and TokBefore(T, Close) do
  begin
    if ((T.Low = '(') or (T.Low = '[')) and (P.Low <> ';') then
    begin
      P := MatchClose(AMap, T);
      if P.Low = '' then
        Exit;
      T := After(AMap, P);
      Continue;
    end;
    if T.IsWord and (T.Low = ANameLow) and InList(P.Low, PARAM_PREV)
       and InList(After(AMap, T).Low, PARAM_NEXT) then
    begin
      // Zurueck zum Anfang der Gruppe 'var A, B: ..'.
      while P.Low = ',' do
        P := Before(AMap, Before(AMap, P));
      Exit(InList(P.Low, PARAM_WRITABLE));
    end;
    P := T;
    T := After(AMap, T);
  end;
end;

// Ist ATarget der Text-Parameter eines Anzeige-Ereignisses (DISPLAY_PARAMS:
// 'CellText' aus OnGetText, 'HintText' aus OnGetHint des VirtualTree), als
// var- bzw. out-Parameter der Routine um ihn? Nur der blosse Name ('X.CellText'
// ist ein Member).
function DisplayParam(AMap: TRdxCodeMap; const ATarget: TRdxToken): Boolean;
var
  R : TRdxRoutine;
begin
  Result := ATarget.IsWord and InList(ATarget.Low, DISPLAY_PARAMS)
    and (Before(AMap, ATarget).Low <> '.')
    and (BeginBodyAround(AMap, ATarget, R) = rbfFound)
    and VarParamOf(AMap, R, ATarget.Low);
end;

// Ist ATarget (das Token vor ':=') ein Anzeige-Ziel (s. Kopf)? True mit
// dem Ziel wie geschrieben und seiner Zeile.
function DisplayAssign(AMap: TRdxCodeMap; const ATarget: TRdxToken;
  out AWhat: string; out ALine: Integer): Boolean;
var
  Open, Cells, S : TRdxToken;
begin
  AWhat := '';
  ALine := 0;
  // 'Grid.Cells[c, r] :=' (rwE33 Stufe 5, mORMot2 dmvc-ai MainFormU.pas:206).
  if ATarget.Low = ']' then
  begin
    Open := OpenerOf(AMap, ATarget);
    Cells := Before(AMap, Open);
    Result := (Open.Low = '[') and Cells.IsWord and (Cells.Low = NAME_CELLS)
      and (Before(AMap, Cells).Low = '.')
      and not ChainLooksLikeData(AMap, Cells);
    if Result then
    begin
      S := ChainStart(AMap, Cells);
      if S.Line = ATarget.Line then
        AWhat := Copy(AMap.Raw(S.Line), S.Col, ATarget.EndCol - S.Col)
      else
        AWhat := ChainText(AMap, Cells);
      ALine := Cells.Line;
    end;
    Exit;
  end;
  // 'CellText :=' im OnGetText-Ereignis (rwE33 Stufe 5, TES5Edit
  // xeLogAnalyzerForm.pas:326/:329).
  if DisplayParam(AMap, ATarget) then
  begin
    AWhat := TokText(AMap, ATarget);
    ALine := ATarget.Line;
    Exit(True);
  end;
  Result := ATarget.IsWord and InList(ATarget.Low, DISPLAY_PROPS)
    and (Before(AMap, ATarget).Low = '.')
    and not ((ATarget.Low = NAME_TEXT) and ChainLooksLikeData(AMap, ATarget));
  if Result then
  begin
    AWhat := ChainText(AMap, ATarget);
    ALine := ATarget.Line;
  end;
end;

// Geht das Ergebnis des Aufrufs ASite in eine Anzeige (s. Kopf)? True mit
// dem Ziel und seiner Zeile.
function DisplayTarget(AMap: TRdxCodeMap; const ASite: TCallSite;
  out AWhat: string; out ALine: Integer): Boolean;
var
  T, P  : TRdxToken;
  Depth : Integer;
  Count : Integer;
begin
  Result := False;
  AWhat := '';
  ALine := 0;
  Depth := 0;
  Count := 0;
  T := Before(AMap, ChainStart(AMap, ASite.Name));
  while (T.Low <> '') and (Count < MAX_DISPLAY_TOKENS) do
  begin
    Inc(Count);
    P := Before(AMap, T);
    if (T.Low = ')') or (T.Low = ']') then
      Inc(Depth)
    else if (T.Low = '(') or (T.Low = '[') then
    begin
      if Depth > 0 then
        Dec(Depth)
      else if T.Low = '[' then
        Exit
      // Eine Typumwandlung liest weiter (ihr Wort gilt dann als Glied).
      else if not InList(P.Low, TEXT_CASTS) then
      begin
        if P.IsWord and not (IsKeyword(P.Low)
           and IsKeywordAfter(P, Before(AMap, P))) then
          Exit(DisplayCall(AMap, P, AWhat, ALine));
        if not InList(P.Low, GROUP_BEFORE) then
          Exit;
      end;
    end
    else if Depth = 0 then
    begin
      if T.Low = ':=' then
        Exit(DisplayAssign(AMap, P, AWhat, ALine));
      if T.IsWord then
      begin
        if IsKeyword(T.Low) and IsKeywordAfter(T, P) then
          Exit;
      end
      else if not (InList(T.Low, DISPLAY_GLUE)
                   or CharInSet(T.Low[1], ['0'..'9', '$', '#'])) then
        Exit;
    end;
    T := P;
  end;
end;

// ---- Eigene Einstellungen der Klasse (Alt-Weg, rwE32 Stufe 4) ----
// delphimvcframework TemplatePro.pas:3163/3365: TTProCompiledTemplate traegt
// das Feld 'fLocaleFormatSettings: TFormatSettings' (per SetFormatSettings
// einstellbar; Geschwisteraufrufe uebergeben es). Invariant verwuerfe die
// eingestellte Template-Locale (Monatsnamen bei 'mmmm'). Steht der Aufruf
// in einer Methode, deren Klasse in der Datei GENAU EIN solches Feld
// deklariert, sperrt der Alt-Weg mit Hinweis auf das Feld (die Hilfe
// schreibt es nicht selbst ein - das waere eine andere Bedeutung). Ein Feld
// heisst: 'Name: TFormatSettings;' auf Klammertiefe 0 im Klassenrumpf
// (auch 'A, B: ..' und 'class var'), nicht Parameter, Rueckgabetyp oder
// Property. Seit rwE33 Stufe 5 nur, wenn eine Methode der Klasse das Feld
// an einen Aufruf derselben Familie uebergibt (FieldUsedForFamily; HeidiSQL
// main.pas:4415 - ein Feld nur fuer Zahlen ist kein Rat fuer DateTimeToStr,
// dort greift der naechste Grund). Mehrere Felder, mehrere Klassenkoepfe
// gleichen Namens oder eine freie Routine: wie bisher. Ebenso, wenn jeder Aufruf sein Muster als
// Literal festlegt ('FormatDateTime(''yyyy-mm-dd hh:nn:ss'', ..)',
// TemplatePro.pas:3170 - dort schreibt Invariant das gewollte ISO-Format,
// das Feld setzte dagegen einen eingestellten Zeittrenner ein; Stufe 4: ok).

// Das eine TFormatSettings-Feld des Klassenrumpfs ab AClass ('class'); leer
// ohne bzw. bei mehreren.
function SettingsFieldIn(AMap: TRdxCodeMap; const AClass: TRdxToken): TRdxToken;
var
  T, Stop, C, N, B : TRdxToken;
  Depth, Hits      : Integer;
begin
  Result := Default(TRdxToken);
  Stop := ClassEnd(AMap, AClass);
  if Stop.Low = '' then Exit;
  Hits := 0;
  Depth := 0;
  T := After(AMap, AClass);
  while (T.Low <> '') and TokBefore(T, Stop) do
  begin
    Depth := Depth + ParenDelta(T);
    if (Depth = 0) and (T.Low = NAME_SETTINGS_TYPE)
       and (After(AMap, T).Low = ';') then
    begin
      C := Before(AMap, T);
      N := Before(AMap, C);
      B := Before(AMap, N);
      if (C.Low = ':') and N.IsWord and (B.Low <> 'function')
         and (B.Low <> 'property') then
      begin
        // 'FA, FB: TFormatSettings' sind zwei Felder.
        if B.Low = ',' then
          Inc(Hits, 2)
        else
          Inc(Hits);
        Result := N;
      end;
    end;
    T := After(AMap, T);
  end;
  if Hits <> 1 then
    Result := Default(TRdxToken);
end;

// Legt der Aufruf ASite sein Muster als Literal fest (FormatDateTime,
// FormatFloat, FormatCurr, Format mit Literal als erstem Argument)?
function FixedPattern(AMap: TRdxCodeMap; const ASite: TCallSite): Boolean;
var
  Lit          : string;
  Li, Co, Upto : Integer;
begin
  Result := InList(ASite.Name.Low, PATTERN_WRITERS)
    and FirstCharAfter(AMap, ASite.Open, Li, Co)
    and ((Li < ASite.Close.Line)
         or ((Li = ASite.Close.Line) and (Co < ASite.Close.Col)));
  if not Result then Exit;
  Upto := Length(AMap.Raw(Li));
  if Li = ASite.Close.Line then
    Upto := ASite.Close.Col - 1;
  Result := LiteralFirstArg(AMap, Li, Co, Upto, Lit);
end;

// Die Routine eines Aufrufs der Familie: Datum/Uhrzeit (PAIR_DATE) bzw. Zahl
// (PAIR_NUMBER und Format - SCA059 meldet es nur mit Float-Spec).
function FamilyCall(const ALow: string; AWantDate, AWantNum: Boolean): Boolean;
begin
  Result := (AWantDate and InList(ALow, PAIR_DATE))
    or (AWantNum and (InList(ALow, PAIR_NUMBER) or InList(ALow, FORMAT_FUNCS)));
end;

// Der Aufruf, in dessen Klammern AFirst..ALast als ganzes Argument steht
// ('DateToStr(d, FFS)', 'DateToStr(d, Self.FFS)'): der Name vor der
// oeffnenden Klammer; leer, wenn das Argument anders steht oder vorher ';'
// bzw. ein Schluesselwort auf Tiefe 0 kommt.
function CallAroundArg(AMap: TRdxCodeMap; const AFirst,
  ALast: TRdxToken): TRdxToken;
var
  P, Q  : TRdxToken;
  Depth : Integer;
  Count : Integer;
begin
  Result := Default(TRdxToken);
  Q := After(AMap, ALast);
  if (Q.Low <> ',') and (Q.Low <> ')') then Exit;
  Depth := 0;
  Count := 0;
  P := Before(AMap, AFirst);
  while (P.Low <> '') and (Count < MAX_DISPLAY_TOKENS) do
  begin
    Inc(Count);
    if (P.Low = ')') or (P.Low = ']') then
      Inc(Depth)
    else if (P.Low = '(') or (P.Low = '[') then
    begin
      if Depth = 0 then
      begin
        if P.Low = '(' then
          Result := Before(AMap, P);
        Exit;
      end;
      Dec(Depth);
    end
    else if (Depth = 0) and ((P.Low = ';')
            or (P.IsWord and IsKeyword(P.Low)
                and IsKeywordAfter(P, Before(AMap, P)))) then
      Exit;
    P := Before(AMap, P);
  end;
end;

// Uebergibt eine Methode der Klasse APath das Feld AField als ganzes
// Argument an einen Aufruf derselben Familie wie die Aufrufe ASites
// ('DateToStr(d, fLocaleFormatSettings)', auch 'Self.FFS')? Seit rwE33
// Stufe 5 Bedingung des Grundes (HeidiSQL main.pas:4415/5674/11246/11252/
// 14718: TMainForm.FFormatSettings = TFormatSettings.Create('en-US') liest
// nur Zahlen - 'StrToFloat(.., FFormatSettings)' -, die Aufrufe dort
// schreiben Datum/Uhrzeit; der Rat, das Feld zu uebergeben, braeche sie wie
// Invariant).
function FieldUsedForFamily(AMap: TRdxCodeMap; const AField: TRdxToken;
  const APath: string; const ASites: TCallSites): Boolean;
var
  WantDate, WantNum : Boolean;
  Li, i             : Integer;
  T, P, Call        : TRdxToken;
  R                 : TRdxRoutine;
begin
  Result := False;
  FamiliesOf(ASites, WantDate, WantNum);
  for i := 0 to High(ASites) do
    WantNum := WantNum or InList(ASites[i].Name.Low, FORMAT_FUNCS);
  for Li := 1 to AMap.LineCount do
  begin
    if Pos(AField.Low, LowerCase(AMap.Raw(Li))) = 0 then
      Continue;
    T := NextToken(AMap, Li, 1);
    while (T.Low <> '') and (T.Line = Li) do
    begin
      P := Before(AMap, T);
      if T.IsWord and (T.Low = AField.Low)
         and ((P.Low <> '.') or (Before(AMap, P).Low = NAME_SELF)) then
      begin
        if P.Low = '.' then
          Call := CallAroundArg(AMap, Before(AMap, P), T)
        else
          Call := CallAroundArg(AMap, T, T);
        if Call.IsWord and FamilyCall(Call.Low, WantDate, WantNum)
           and (BeginBodyAround(AMap, Call, R) = rbfFound)
           and SameText(Copy(R.Name, 1, LastDelimiter('.', R.Name) - 1),
             APath) then
          Exit(True);
      end;
      T := After(AMap, T);
    end;
  end;
end;

// Der Grund, wenn der erste Aufruf in einer Methode steht, deren Klasse
// eigene Einstellungen traegt (s. Kopf des Abschnitts); '' sonst.
function ClassSettingsReason(AMap: TRdxCodeMap;
  const ASites: TCallSites): string;
var
  R      : TRdxRoutine;
  Heads  : TArray<TRdxToken>;
  Path   : string;
  Field  : TRdxToken;
  i      : Integer;
  Fixed  : Boolean;
begin
  Result := '';
  Fixed := True;
  for i := 0 to High(ASites) do
    Fixed := Fixed and FixedPattern(AMap, ASites[i]);
  if Fixed
     or (BeginBodyAround(AMap, ASites[0].Name, R) <> rbfFound)
     or (Length(R.Parts) < 2) then
    Exit;
  // Die Klasse wie im Kopf: der Name ohne sein letztes Glied.
  Path := Copy(R.Name, 1, LastDelimiter('.', R.Name) - 1);
  if Path = '' then Exit;
  Heads := TRdxBlocks.FindClassHeads(AMap, Path);
  if Length(Heads) <> 1 then Exit;
  Field := SettingsFieldIn(AMap, Heads[0]);
  if (Field.Low <> '') and FieldUsedForFamily(AMap, Field, Path, ASites) then
    Result := _(R_FS_CLASS_SETTINGS, [Path, TokText(AMap, Field),
      Field.Line]);
end;

// Der Grund, wenn einer der Aufrufe ASites in eine Anzeige schreibt; ''
// sonst.
function DisplayReason(AMap: TRdxCodeMap; const ASites: TCallSites): string;
var
  i, Li : Integer;
  What  : string;
begin
  Result := '';
  for i := 0 to High(ASites) do
    if DisplayTarget(AMap, ASites[i], What, Li) then
      Exit(_(R_FS_DISPLAY, [Li, What]));
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
// Fuer den Alt-Weg kommt das with seit rwE32 Stufe 4 ZULETZT: FPC, alte
// Compiler, eigenes TFormatSettings und selbst eingestellte FormatSettings
// tragen die Sperre und gelten auch dort, wo der Hauptweg das with per
// Qualifizierung aufloest (jcl FileViewer.pas:601, PeDump.pas:674,
// doublecmd SynUniDesigner.pas:2978, issrc ISPP.Funcs.pas:1599 - bis dahin
// nannte die Sperre das with, Eintrag 1 den Altcompiler).
function FileReason(AMap: TRdxCodeMap; const ANames: array of string;
  const ASites: TCallSites; AInvariant: Boolean;
  out ASettings: string): string;
var
  i, Li, Member : Integer;
  WithLine      : Integer;
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
  // Ein with um einen der Aufrufe (seit rwE31 Stufe 3 jeder Aufruf, nicht
  // nur der erste - die Aufrufe einer anonymen Methode der Anweisung koennen
  // in einem eigenen with stehen): der Alt-Weg sperrt (als letzter Grund,
  // s. oben), der Hauptweg nimmt die globale Variable qualifiziert (s. Kopf).
  WithLine := 0;
  for i := 0 to High(ASites) do
  begin
    WithLine := WithLineBefore(AMap, ASites[i].Name);
    if WithLine > 0 then
      Break;
  end;
  if (WithLine > 0) and not AInvariant then
    ASettings := ', ' + Spell + '.FormatSettings';
  Proof := ModernProof(AMap);
  if not AInvariant then
  begin
    if ProofCovers(Proof, FLOOR_SETTINGS_VAR) then
      Exit('');
    // Nur die Bedingungen der Datei; ein Kit-Include (mormot.defines.inc,
    // jvcl.inc ..) prueft seit rwE31 Stufe 3 der Plattenblick: ein Projekt
    // der Unit ab Delphi XE widerlegt es (uRdxMagicFixes.ProjectReason;
    // mORMot2 dmvc-ai api.impl.pas:50, MainFormU.pas:206).
    Trace := OldCompilerTraceOf(AMap, FLOOR_SETTINGS_VAR, True, False, Li);
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
    // Nur die Bedingungen der Datei (seit rwE32 Stufe 4 wie der Hauptweg):
    // ein Kit-Include (mormot.defines.inc, jvcl.inc ..) prueft der
    // Plattenblick, und ein Projekt der Unit ab Delphi 10.3 widerlegt es
    // (uRdxMagicFixes.ProjectReason, ModernProjectProof) - mORMot2 dmvc-ai
    // api.impl.pas:50: Eintrag 1 galt per .dproj 20.3 (Delphi 12), Eintrag
    // 2 sperrte mit 'bis Delphi 10.3 (mormot.defines.inc)'.
    Trace := OldCompilerTraceOf(AMap, FLOOR_INLINE_DECL, True, False, Li);
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
  if WithLine > 0 then
  begin
    // Das with sperrt ohnehin (ohne Plattenblick): traegt die Datei ein
    // Kit-Include, ist dessen Altcompiler der tragende Grund - Eintrag 1
    // nennt ihn ebenso (jcl FileViewer.pas:601 'jcl.inc, Zeile 28').
    if not Proven then
    begin
      Trace := OldCompilerTraceOf(AMap, FLOOR_INLINE_DECL, False, True, Li);
      if Trace <> '' then
        Exit(_(R_FS_OLD_INVARIANT, [Trace, Li]));
    end;
    Exit(_(R_FS_WITH, [WithLine]));
  end;
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
  // Gekoppelte Auswertung in derselben Routine (rwE31 Stufe 3).
  if (AReason = '') and AInvariant then
    AReason := CoupledReason(AMap, Sites);
  // Eigene Einstellungen der Klasse (rwE32 Stufe 4, TemplatePro.pas).
  if (AReason = '') and AInvariant then
    AReason := ClassSettingsReason(AMap, Sites);
  // Anzeige-Ziel (rwE32 Stufe 4, E6): dort ist die Locale richtig - nach
  // den Gruenden, an denen Verhalten bricht.
  if (AReason = '') and AInvariant then
    AReason := DisplayReason(AMap, Sites);
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
  // Gekoppelte Auswertung (rwE31 Stufe 3): IDE.MainForm.pas:6170 - die
  // Argumente lesen selbst FormatSettings.TimeSeparator.
  if (AReason = '') and AInvariant then
    AReason := CoupledReason(AMap, Sites);
  // Eigene Einstellungen der Klasse (rwE32 Stufe 4).
  if (AReason = '') and AInvariant then
    AReason := ClassSettingsReason(AMap, Sites);
  // Anzeige-Ziel (rwE32 Stufe 4, E6): async_client MainClientFormU.pas:484
  // 'ListBox1.Items.Add(Format(..))'.
  if (AReason = '') and AInvariant then
    AReason := DisplayReason(AMap, Sites);
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
  Hits    : TArray<TRdxToken>;
  Sites   : TCallSites;
  i, Li   : Integer;
  Other   : string;
  Literal : Boolean;
begin
  Result := ABaseHint;
  // Dieselben Aufrufe wie der Planer (auch auf Folgezeilen, rwE30 Stufe 2).
  Hits := StatementNames(AMap, ALine, LOCALE_FUNCS);
  if Length(Hits) = 0 then
    Exit;
  SetLength(Sites, Length(Hits));
  Literal := True;
  for i := 0 to High(Hits) do
  begin
    if ReadCall(AMap, Hits[i], LOCALE_ARITY[LocaleIndex(Hits[i].Low)],
         Sites[i]) <> '' then
      Exit;
    Literal := Literal and ReadsOnlyLiteral(AMap, Sites[i]);
  end;
  // Lesen alle Aufrufe nur Literale, gibt es keinen Datenfluss zu einem
  // Gegenstueck (rwE32 Stufe 4, minesweeper uGameScore.pas:144:
  // 'FTime := FTime + StrToTime(''00:00:01'')' - der Hinweis nannte
  // 'ShowTime(FormatDateTime(..))' der Folgezeile).
  if Literal then
    Exit;
  Li := PairBreakLine(AMap, Sites, Other);
  if Li > 0 then
    Result := _(R_FS_PAIR_HINT, [ABaseHint, Li, Other]);
end;

end.

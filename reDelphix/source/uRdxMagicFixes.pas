unit uRdxMagicFixes;

// reDelphix - Quick-Fix SCA014 MagicNumber "Lokale Konstante einfuehren"
// (Charge Q14, Entscheid E28), OHNE ToolsAPI und ohne Parser (laeuft auch
// im FPC-Pruefstand). Aus 'if Count > 200 then' wird
//     const MagicNr01 = 200;
//     if Count > MagicNr01 then
// - die Inline-Konstante als eigene Anweisung direkt vor der Anweisung mit
// dem Literal (E26), ein Zweig ohne begin bekommt begin..end (Nico, Fall
// 3). WAS geschrieben wird, rechnet die Code-Aktion "Lokale Konstante
// einfuehren" (uRdxIntroPlan/uRdxIntroEdits, 1:1 aus dem Labor
// VarNameProject): TargetAt mit dem Literal als Caret, IntroduceEdits.
// Anders als im Labor (E28): KEINE Sync-Edit-Sitzung - die Hilfe schreibt
// nur die Ersetzung, ueber den Schreibweg der Tabelle (PlanByteEdits, ein
// Undo-Schritt); umbenennen kann man danach selbst, von Hand oder mit
// Refactor > Rename (Strg+Umschalt+E) - nicht Sync Edit: Esc zerstoert
// dort Text (UI-Test 2026-10-11), und Strg+Umschalt+J braucht eine
// Markierung (Gegen-Review Q14, Minor 13). Und nur DAS eine Literal des
// Funds, nicht alle gleichen der Zeile (E28: "nur eines, sonst sperren").
//
// WAS DER DETEKTOR MELDET (uMagicNumbers gelesen): nur in if-Bedingungen,
// je if hoechstens EINEN Fund, auf der Zeile des 'if'. Er sucht im
// Bedingungstext (Token mit Leerzeichen getrennt, ohne Kommentare, Strings
// geblankt) einen Vergleich ('>=', '<=', '<>', '>', '<', '=' - in dieser
// Reihenfolge, nicht nach Spalte) und dahinter eine Ganzzahl, die nicht
// trivial ist. Nie: Hex ('$FF' - keine Ziffer), Float ('3.5', '1e3' -
// uebersprungen), ein Vorzeichen ('-5': der Lexer trennt '-' ab, im
// Bedingungstext steht '- 5') und ein Literal in Klammern ('> (200)').
// Bei '200_000' (auch '200_000.5') meldet er "200" (der Lexer liest
// '_000' als Bezeichner) - ein Fehlalarm: das Literal heisst anders, die
// Hilfe findet es nicht.
//
// ZIEL AUS DEM FUND (der Planer prueft nach, statt dem Detektor zu
// glauben): die Zahl aus der Meldung; auf der Fundzeile jede if-Bedingung
// vom 'if' bis zu ihrem 'then' (auch ueber Folgezeilen); darin die
// Zahl-Token mit genau diesem Text, direkt hinter einem Vergleich (kein
// Teil von '200.5', '$200', '#200', '-200', '200_000'). Genau einer: das
// Ziel. Keiner: Zeile verschoben - ausser es steht dort ein Vergleichswert
// mit Zifferntrennern, dessen erster Block die Zahl ist (auch mit
// Bruchteil): dann nennt der Grund den Fehlalarm (Review R6-05;
// Korpus: 1 von 5.036, ISSigFunc.pas).
// Mehrere - oder einer neben einem solchen Trennerwert: mehrdeutig
// (gesperrt - der Detektor meldete danach den naechsten, und welches er
// meinte, sagt die Meldung nicht). Steht der
// eine in einer Folgezeile der Bedingung: die
// Konstante gehoerte vor die if-Zeile, die Code-Aktion setzt sie vor die
// Zeile des Literals - gesperrt.
//
// SPERREN dazu: alle der Code-Aktion (TargetAt: mehrzeilige Strings und
// Kommentare, asm, initialization, FPC-Weiche, Direktiven, Kopf-
// Fortsetzungen, case-Zweig/Sprungmarke/on-Handler, 'else if' u. a. -
// was der Zeilen-Leser nicht sicher abgrenzt). Dazu, weil eine Inline-
// Konstante erst ab Delphi 10.3 uebersetzt und FPC 3.2 sie gar nicht
// kennt - eine Datei, die ein anderer Compiler baut, braeche:
//   * Skript-Units ohne implementation-Teil (xEdit, JvInterpreter),
//     Spuren von Compilern vor 10.3 in der Datei (uRdxCompilerTraces,
//     FLOOR_INLINE_DECL) und der Hauptblock eines Programms bzw. einer
//     Bibliothek (ob dort eine Inline-Deklaration gilt, ist ohne Delphi
//     nicht gemessen; Gegen-Review Q14, Verdacht d) - hier im Planer;
//   * was nur die Platte weiss, im Check der Tabelle (MagicCheck): eine
//     Lazarus-Dateiart bzw. ein Lazarus-Projekt oder -Paket neben der Unit,
//     eine alte Delphi-Projektdatei (.dof, .bdsproj, .bpr, .bpg) oder eine
//     .dproj vor 10.3 (ProjectVersion < 18.5) - Major 3: CnWizards, JVCL
//     und GExperts tragen keine Versionsweiche in der Unit, die Version
//     steht im Projekt (FileReason) - und FPC-Weichen oder alte Spuren in
//     den Includes, auch ein Include, das nicht neben der Unit liegt
//     (IncludeReason). Auf einem Netzpfad (UNC) bzw. Netzlaufwerk liest die
//     Hilfe nichts von der Platte - der Menueaufbau laeuft im Hauptthread
//     (Verdacht e): sie lehnt ab; seit Charge B1-FD gilt das auch fuer
//     ein Include auf einem Netzpfad in einer lokalen Unit
//     ('{$I \\server\share\defs.inc}' wartete 9 bis 16 s, Gegen-Review
//     R4-03; Regel uRdxPaths.IsNetworkPath, geprueft vor jedem
//     FileExists). Zwischengespeichert wird nichts: je
//     Aufruf liest FileReason hoechstens drei Verzeichnisse und die Koepfe
//     ihrer .dproj (Korpus-Harness, FPC: 1.010 Aufrufe in 231 ms, 0,2 ms
//     je Fund; IncludeReason mit den Includes rund 7 ms) - ein Cache
//     braechte veralteten Zustand, wenn eine Projektdatei dazukommt.
//   Den Plattenblick nutzt auch SCA069 (Zifferntrenner, ab Delphi 11):
//     FileReason und IncludeReason nehmen seit der Integration QFI2 das
//     Sprachmittel (TRdxLateFeature) - es waehlt die Schwelle
//     (FLOOR_INLINE_DECL bzw. FLOOR_DIGIT_SEP) und den Grundtext; fuer
//     SCA014 (lfInlineConst) bleiben Schwelle und Texte, wie sie waren.
//     Seit der Integration QFI3 auch SCA111/SCA112 (lfInlineVar: die
//     Inline-Variable vor der Schleife - dieselbe Schwelle 10.3, ein
//     eigener Grundtext).
// Korpus Q14 (5.036 Funde): FPC-Weiche in der Datei 1.724, alte Spur 1.275,
// in einem Include 63 + 108, Include fehlt 55, Lazarus-Projekt 88, Skript
// 18 - ohne Skript- und Plattenpruefung waeren es 1.024 statt 696
// Angebote gewesen; die alten Delphi-Projekte (Charge SQc) nehmen davon
// noch 120 weg (alte Projektdatei ohne .dproj 111 - CnWizards 72, JVCL
// 37 -, .dproj vor 10.3 9): 576 Angebote.
//
// NAME: MagicNr01, MagicNr02 ... - der erste, der in der Datei nicht als
// ganzes Wort vorkommt (uRdxIntroPlan.NextFreeName, wie im Labor; auch
// Kommentare und Strings zaehlen - strenger als noetig).

interface

uses
  uRdxBufferMath, uRdxCodeMap;

const
  // Der Name der Konstante ohne Nummer (wie im Labor: MagicNr01 ...).
  MAGIC_NAME_BASE = 'MagicNr';

type
  // Was die Hilfe schreibt, die den Plattenblick braucht (FileReason,
  // IncludeReason): es waehlt die Schwelle und den Grundtext.
  //   lfInlineConst     SCA014 Inline-Konstante, ab Delphi 10.3
  //                     (FLOOR_INLINE_DECL)
  //   lfDigitSeparator  SCA069 Zifferntrenner, ab Delphi 11
  //                     (FLOOR_DIGIT_SEP; Integration QFI2)
  //   lfInlineVar       SCA111/SCA112 Inline-Variable, ab Delphi 10.3
  //                     wie die Inline-Konstante (FLOOR_INLINE_DECL;
  //                     Integration QFI3 - bis dahin haetten ihre Gruende
  //                     die Inline-Konstante genannt)
  // FPC 3.2 kennt keines davon.
  TRdxLateFeature = (lfInlineConst, lfDigitSeparator, lfInlineVar);

  // Ergebnis des Planers (uRdxFixTable: MagicForm im Geruest TRdxFixFrame).
  //   Value  die Zahl aus der Meldung - Name im Menuetext; schon gesetzt,
  //          wenn der Planer danach ablehnt
  //   Name   der Name der Konstante (MagicNr01 ...) - fuer den Hinweis
  //   Line, Col  das ersetzte Literal (1-basiert, Zeichen)
  //   Wrap   der Zweig bekommt begin..end
  //   Edits  genau eine Ersetzung: von Spalte 1 der ersten geaenderten
  //          Zeile bis hinter das Literal bzw. (Wrap) bis zum Anfang der
  //          Zeile nach der Anweisung
  TRdxMagicPlan = record
    Value : string;
    Name  : string;
    Line  : Integer;
    Col   : Integer;
    Wrap  : Boolean;
    Edits : TArray<TRdxEdit>;
  end;

  // Der Planer der Charge Q14 und seine Bausteine (s. Kopf).
  TRdxMagicFixes = class
  public
    // Die Zahl aus der Meldung 'Magic number "200" in if condition - ...'
    // (zwischen den ersten beiden '"'): Ziffern, hoechstens ein '-' davor;
    // '' sonst.
    class function NumberOf(const AMessage: string): string; static;

    // Das Literal AValue als Vergleichswert in den if-Bedingungen, die auf
    // ALine beginnen (s. Kopf "Ziel aus dem Fund"): '' und seine Spalte in
    // ACol, sonst der Grund.
    class function LiteralAt(AMap: TRdxCodeMap; ALine: Integer;
      const AValue: string; out ACol: Integer): string; static;

    // SCA014: der Plan zum Fund auf ALine mit der Meldung AMessage - True,
    // oder False mit dem Grund. Form TRdxPlannerOf<TRdxMagicPlan>.
    class function MagicNumber(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxMagicPlan;
      out AReason: string): Boolean; static;

    // Code-Aktion ohne Fund (Charge B, uRdxContextRunner): der Plan fuer das
    // Zahl-Literal, das Zeichenspalte ACol auf ALine enthaelt oder direkt
    // vor ACol endet (uRdxCodeMap.LiteralContaining = lkNumber; die
    // Caret-Regel von PlanIntroduce) - dieselbe Kette wie MagicNumber hinter
    // LiteralAt: nur DIESES Literal (E28), dieselben Sperren der Code-Aktion
    // und der Datei. Value ist das Literal wie im Quelltext ('$FF', '1.5',
    // '1_000'). True mit dem Plan; False mit dem Grund; False mit AReason
    // = '', wenn an ACol kein Zahl-Literal steht (kein Kandidat - die
    // Aktion entfaellt, Entscheid F4). Was nur die Platte weiss
    // (FileReason, IncludeReason), fragt der Aufrufer danach.
    class function IntroduceAt(AMap: TRdxCodeMap; ALine, ACol: Integer;
      out APlan: TRdxMagicPlan; out AReason: string): Boolean; static;

    // Was nur die Platte weiss (der Check in uRdxFixTable, nach dem
    // Planer): eine Lazarus-/FPC-Dateiart (.pp, .lpr) oder ein Lazarus-
    // Projekt bzw. -Paket (.lpi, .lpk, .lpr) im Verzeichnis der Unit oder
    // bis PROJECT_LEVELS darueber - die Unit baut dann wohl auch mit FPC
    // (Korpus: doublecmd ohne jede FPC-Weiche in der Unit, der Modus steht
    // im Projekt); im selben Fenster das NAECHSTE Verzeichnis mit Delphi-
    // Projektdateien: eine .dproj mit ProjectVersion unter der Schwelle
    // von AFeature (FLOOR_INLINE_DECL.ProjectVersion 18.5 = Delphi 10.3,
    // FLOOR_DIGIT_SEP 19.3 = Delphi 11; ohne lesbare Version zaehlt sie
    // als alt) bzw. - ohne .dproj dort - eine alte Projektdatei (.dof,
    // .bdsproj, .bpr, .bpg). Ein Netzpfad (UNC oder Netzlaufwerk,
    // IsNetworkPath) wird nicht gelesen. '' oder der Grund - er nennt
    // AFeature. Die FPC-Weiche IN der Datei prueft schon TargetAt.
    class function FileReason(const AFileName: string;
      AFeature: TRdxLateFeature): string; static;

    // Die Include-Dateien der Unit AFileName (alle {$I} in AMap, auch die
    // im Kopf - dort stehen die Compiler-Weichen: jvcl.inc,
    // mormot.defines.inc ...; uRdxBlocks.AllIncludes, bis zur
    // Nachpruefung der Charge B1-FD hier kopiert) lesen, verschachtelte ebenso
    // (uRdxBlocks.IncludeChainReason): '' oder der Grund - eine
    // FPC-Weiche oder Spur aelterer Compiler (bis zur Schwelle von
    // AFeature) darin, oder ein Include, das nicht neben der Unit liegt
    // oder auf einem Netzpfad (nicht gelesen) - seine Weichen sieht die
    // Hilfe dann nicht.
    class function IncludeReason(const AFileName: string; AMap: TRdxCodeMap;
      AFeature: TRdxLateFeature): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,       // TStrings (TRdxIncludeTest)
  uRefactorInfo,        // TRefactorSpan.Make
  uRdxIntroPlan,        // CharColOfByte, LineLooksFpcAware
  uRdxIntroEdits,       // TextOf, TargetAt, IntroduceEdits, ApplyIntroEdits
  uRdxPaths,            // IsNetworkPath
  uRdxBlocks,           // IncludeChainReason, AllIncludes
  uRdxCompilerTraces,   // OldCompilerTrace, ScriptReason, FLOOR_INLINE_DECL,
                        // FLOOR_DIGIT_SEP
  uRdxText;             // _, MsgMovedSuffix, MsgByHand (E29)

const
  SPAN_MAGIC = 'magic';
  KW_IF   = 'if';
  KW_THEN = 'then';
  KW_END  = 'end';
  // Davor steht der Vergleichswert (uMagicNumbers.ExtractMagicNumber).
  COMPARE_OPS: array[0..5] of string = ('>=', '<=', '<>', '>', '<', '=');
  // So weit liest die Hilfe eine Bedingung ueber Folgezeilen (der
  // Detektor bis zum 'then'; ein fehlendes 'then' heisst kaputter Text).
  MAX_COND_LINES = 40;
  // Lazarus-/FPC-Dateiarten - Delphi oeffnet sie nicht als Unit.
  FPC_EXTENSIONS: array[0..1] of string = ('.pp', '.lpr');
  // Lazarus-Projekt, -Paket, -Programm (FileReason) ...
  LAZARUS_EXTENSIONS: array[0..2] of string = ('.lpi', '.lpk', '.lpr');
  // ... Projektdateien aelterer Delphi bzw. des C++Builder: Delphi 1-7,
  // BDS 2005/2006, C++Builder-Projekt und -Projektgruppe (Major 3) ...
  LEGACY_EXTENSIONS: array[0..3] of string = ('.dof', '.bdsproj', '.bpr',
    '.bpg');
  DPROJ_EXTENSION = '.dproj';
  // ... im Verzeichnis der Unit und so vielen darueber (Korpus: doublecmd-
  // Plugins eine Ebene, CnWizards_L4.lpk zwei Ebenen ueber den Units).
  PROJECT_LEVELS = 2;
  // So viel einer .dproj liest die Hilfe - ProjectVersion steht in der
  // ersten PropertyGroup.
  DPROJ_HEAD_BYTES = 65536;
  PROJECT_VERSION_TAG = '<ProjectVersion>';
  // Programm und Bibliothek haben einen Hauptblock (MainBlockReason).
  MAIN_BLOCK_WORDS: array[0..1] of string = ('program', 'library');
  // Die Gruende sind englische msgids, uebersetzt mit _() in DIESER Unit
  // (Entscheid E29; tools/i18n_extract.py loest nur Konstanten und
  // String-Array-Konstanten derselben Unit auf). Jede msgid ist ein GANZER
  // Satz: ein %s am Satzende hinter '; ' ist MsgByHand (uRdxText) - der
  // Trenner bleibt im Satz.
  // Was nur der Compiler kennt (ScriptReason): uebersetzt uebergeben - der
  // Aufrufer uebersetzt, ScriptReason setzt es als %s in seinen Satz.
  FEATURE_INLINE = 'an inline constant';
  // MissingFmt fuer IncludeChainReason (uRdxBlocks): %s das Include, %s die
  // Ursache ('nicht neben der Unit gefunden' ...). Geht als uebersetztes
  // MUSTER hinaus (_() ohne Argumente formatiert nicht), Include und
  // Ursache setzt uRdxBlocks ein.
  R_INC_UNSEEN = 'include %s %s - the quick fix does not see its compiler '
    + 'switches (FPC, older Delphi)';
  // Die Gruende des Plattenblicks nennen das Sprachmittel (TRdxLateFeature):
  // bis zur Integration QFI2 stand dort fest die Inline-Konstante und
  // Delphi 10.3 - fuer SCA014 ergibt sich derselbe Text. Je Sprachmittel
  // EIN ganzer Satz (Charge G9, Entscheid E29): Geschlecht, Zahl und
  // Verneinung ('keine Inline-Konstante', 'keine Zifferntrenner') stellt
  // jede Sprache selbst - ein Satz aus Stuecken ('%s gibt es in FPC 3.2
  // nicht' mit 'Zifferntrenner') liesse sich nicht uebersetzen. Die
  // Versionsnummer des Sprachmittels (10.3, 11) steht im Satz; die
  // ProjectVersion der Schwelle kommt aus FloorOf (%s).
  // Reihenfolge je Array: lfInlineConst, lfDigitSeparator, lfInlineVar.
  R_FPC_FILE: array[TRdxLateFeature] of string = (
    'Lazarus/FPC file (%s) - FPC 3.2 has no inline constants',
    'Lazarus/FPC file (%s) - FPC 3.2 has no digit separators',
    'Lazarus/FPC file (%s) - FPC 3.2 has no inline variables');
  R_LAZARUS: array[TRdxLateFeature] of string = (
    'Lazarus project/package %s in the directory %s - the unit probably also '
      + 'builds with FPC, and FPC 3.2 has no inline constants',
    'Lazarus project/package %s in the directory %s - the unit probably also '
      + 'builds with FPC, and FPC 3.2 has no digit separators',
    'Lazarus project/package %s in the directory %s - the unit probably also '
      + 'builds with FPC, and FPC 3.2 has no inline variables');
  R_LEGACY: array[TRdxLateFeature] of string = (
    'old project file %s in the directory %s - the unit probably also builds '
      + 'with a Delphi before 10.3, which has no inline constants; %s',
    'old project file %s in the directory %s - the unit probably also builds '
      + 'with a Delphi before 11, which has no digit separators; %s',
    'old project file %s in the directory %s - the unit probably also builds '
      + 'with a Delphi before 10.3, which has no inline variables; %s');
  R_OLD_DPROJ: array[TRdxLateFeature] of string = (
    'project %s in the directory %s with ProjectVersion %s (before Delphi 10.3 '
      + '= %s) - there are no inline constants there; %s',
    'project %s in the directory %s with ProjectVersion %s (before Delphi 11 '
      + '= %s) - there are no digit separators there; %s',
    'project %s in the directory %s with ProjectVersion %s (before Delphi 10.3 '
      + '= %s) - there are no inline variables there; %s');
  R_NO_VERSION: array[TRdxLateFeature] of string = (
    'project %s in the directory %s without a readable ProjectVersion (Delphi '
      + '2007 wrote none) - the unit probably also builds with a Delphi before '
      + '10.3, which has no inline constants; %s',
    'project %s in the directory %s without a readable ProjectVersion (Delphi '
      + '2007 wrote none) - the unit probably also builds with a Delphi before '
      + '11, which has no digit separators; %s',
    'project %s in the directory %s without a readable ProjectVersion (Delphi '
      + '2007 wrote none) - the unit probably also builds with a Delphi before '
      + '10.3, which has no inline variables; %s');
  R_INC_FPC: array[TRdxLateFeature] of string = (
    'the include %s carries an FPC switch (line %d) - FPC 3.2 has no inline '
      + 'constants',
    'the include %s carries an FPC switch (line %d) - FPC 3.2 has no digit '
      + 'separators',
    'the include %s carries an FPC switch (line %d) - FPC 3.2 has no inline '
      + 'variables');
  R_INC_OLD: array[TRdxLateFeature] of string = (
    'the include %s shows traces of older compilers (%s, line %d) - an inline '
      + 'constant exists only from Delphi 10.3 on; %s',
    'the include %s shows traces of older compilers (%s, line %d) - digit '
      + 'separators exist only from Delphi 11 on; %s',
    'the include %s shows traces of older compilers (%s, line %d) - an inline '
      + 'variable exists only from Delphi 10.3 on; %s');
  // UNC und Netzlaufwerk (uRdxPaths.IsNetworkPath, seit Charge B1-FD).
  R_NETWORK = 'network path %s - the quick fix reads no project or include '
    + 'files there (the menu is built in the main thread); %s';
  R_MAIN_BLOCK = 'the line is in the main block of the program or library '
    + '(begin from line %d) - whether an inline declaration is valid there '
    + 'has not been measured; %s';

// Die Schwelle des Sprachmittels (uRdxCompilerTraces; lfInlineConst und
// lfInlineVar teilen FLOOR_INLINE_DECL) - eine Funktion,
// weil ein typisierter Record nicht in einer typisierten Konstante stehen
// kann.
function FloorOf(AFeature: TRdxLateFeature): TRdxCompilerFloor;
begin
  if AFeature = lfDigitSeparator then
    Result := FLOOR_DIGIT_SEP
  else
    Result := FLOOR_INLINE_DECL;
end;

{ ---- Ziel aus dem Fund ---- }

// Die Zahl zwischen den ersten beiden '"' (QuotedText, uRdxCodeMap; bis
// Charge B2S-a hier ausgeschrieben), dann die Ziffern-Probe.
class function TRdxMagicFixes.NumberOf(const AMessage: string): string;
var
  Digits : string;
  C      : Char;
begin
  Result := QuotedText(AMessage, '"');
  if Result = '' then Exit;
  Digits := Result;
  if Digits[1] = '-' then
    Delete(Digits, 1, 1);
  if Digits = '' then
    Exit('');
  for C in Digits do
    if not CharInSet(C, ['0'..'9']) then
      Exit('');
end;

// Die Spalte hinter dem Zahl-Literal an T samt einem direkt folgenden
// Bruchteil ('200.5', '200_000.5': das Token endet am '.'); ohne
// Bruchteil T.EndCol.
function NumberEnd(AMap: TRdxCodeMap; const T: TRdxToken): Integer;
var
  L : string;
begin
  L := AMap.Raw(T.Line);
  Result := T.EndCol;
  if (Result < Length(L)) and (L[Result] = '.')
     and CharInSet(L[Result + 1], ['0'..'9']) then
  begin
    Inc(Result);
    while (Result <= Length(L)) and IsIdentChar(L[Result]) do
      Inc(Result);
  end;
end;

// Ist T ein Vergleichswert - davor ein Vergleich, dahinter kein Bruchteil?
function IsComparedValue(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
begin
  Result := InList(Before(AMap, T).Low, COMPARE_OPS)
    and (NumberEnd(AMap, T) = T.EndCol);
end;

// Ein Schluesselwort AWord an T (nicht '&If', 'X.Then')? Bis zur Folgewelle
// des Wochen-Reviews IsKeyword - der Name gehoert seitdem der Wortliste
// KEYWORDS in uRdxCodeMap.
function IsKeywordToken(AMap: TRdxCodeMap; const T: TRdxToken;
  const AWord: string): Boolean;
begin
  Result := (T.Low = AWord) and IsKeywordAfter(T, Before(AMap, T));
end;

// Ein Vergleichswert mit Zifferntrennern (ab Delphi 11), dessen erster
// Block AValue ist ('200_000', auch '200_000.5', zu "200"): sein Text wie
// in der Zeile, sonst ''. Der Detektor liest '_000' als Bezeichner und
// meldet den ersten Block - ein Fehlalarm (Review R6-05), mit Bruchteil
// ebenso (Nachbesserung FF). Davor muss ein Vergleich stehen: nur dort
// liest der Detektor einen Wert ('Foo(200_000) > X' meldet er nicht).
function SeparatedValue(AMap: TRdxCodeMap; const T: TRdxToken;
  const AValue: string): string;
var
  C : Char;
begin
  Result := '';
  if (Copy(T.Low, 1, Length(AValue) + 1) <> AValue + '_')
     or not InList(Before(AMap, T).Low, COMPARE_OPS) then
    Exit;
  for C in T.Low do
    if not CharInSet(C, ['0'..'9', '_']) then
      Exit;
  Result := Copy(AMap.Raw(T.Line), T.Col, NumberEnd(AMap, T) - T.Col);
end;

// Die Vergleichswerte AValue in der Bedingung hinter AIf bis zu ihrem
// 'then' (bzw. 'end', Dateiende, MAX_COND_LINES): ihre Zahl, der letzte
// in AHit; der erste Vergleichswert mit Zifferntrennern, dessen erster
// Block AValue ist, in ASeparated (SeparatedValue; nur, solange noch
// keiner gesetzt ist).
function CountInCondition(AMap: TRdxCodeMap; const AIf: TRdxToken;
  const AValue: string; var AHit: TRdxToken; var ASeparated: string): Integer;
var
  T : TRdxToken;
begin
  Result := 0;
  T := After(AMap, AIf);
  while (T.Low <> '') and (T.Line <= AIf.Line + MAX_COND_LINES)
     and not IsKeywordToken(AMap, T, KW_THEN) and not IsKeywordToken(AMap, T, KW_END) do
  begin
    if (T.Low = AValue) and IsComparedValue(AMap, T) then
    begin
      Inc(Result);
      AHit := T;
    end
    else if ASeparated = '' then
      ASeparated := SeparatedValue(AMap, T, AValue);
    T := After(AMap, T);
  end;
end;

class function TRdxMagicFixes.LiteralAt(AMap: TRdxCodeMap; ALine: Integer;
  const AValue: string; out ACol: Integer): string;
var
  T, Hit : TRdxToken;
  Ifs, N : Integer;
  Sep    : string;
begin
  ACol := 0;
  Ifs := 0;
  N := 0;
  Sep := '';
  Hit := Default(TRdxToken);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if IsKeywordToken(AMap, T, KW_IF) then
    begin
      Inc(Ifs);
      Inc(N, CountInCondition(AMap, T, AValue, Hit, Sep));
    end;
    T := After(AMap, T);
  end;
  if Ifs = 0 then
    Result := MsgMovedSuffix(_('line %d carries no if', [ALine]))
  else if (N > 0) and (Sep <> '') then
    // Beides in einer Bedingung ('(X > 200_000) or (Y > 200)'): die Meldung
    // "200" passt auf beide, und der Detektor nimmt den ersten Vergleich in
    // Op-Reihenfolge - vorher ersetzte die Hilfe das exakte Literal, und
    // der Fund blieb (Wochen-Review 2026-10-21).
    Result := _('the if condition on line %d compares with %s and with %s - '
      + 'ambiguous (with digit separators the detector reads only the first '
      + 'block); the quick fix replaces exactly one literal',
      [ALine, Sep, AValue])
  else if (N = 0) and (Sep <> '') then
    // Der Fund ist frisch, nur falsch gelesen - 'Zeile verschoben?' liesse
    // den Nutzer neu scannen und denselben Fund wiederfinden.
    Result := _('the if condition on line %d compares with %s - with digit '
      + 'separators the detector reads only the first block %s (false '
      + 'alarm); no literal to replace', [ALine, Sep, AValue])
  else if N = 0 then
    Result := MsgMovedSuffix(_('no if condition on line %d compares with %s',
      [ALine, AValue]))
  else if N > 1 then
    Result := _('the if condition on line %d compares %d times with %s - '
      + 'ambiguous; the quick fix replaces exactly one literal',
      [ALine, N, AValue])
  else if Hit.Line <> ALine then
    Result := _('%s is in line %d, a continuation line of the if condition - '
      + 'the constant would belong before the if line (not supported)',
      [AValue, Hit.Line])
  else
  begin
    Result := '';
    ACol := Hit.Col;
  end;
end;

{ ---- Der Text fuer die Code-Aktion und zurueck ---- }

// Die Zeilen der Code-Sicht als Puffer der Code-Aktion (uRdxIntroEdits.
// TextOf): mit LF verbunden - die Zeilen sind dieselben wie in ALines
// (ein einzelnes CR trennt dort schon), Zeilenenden setzt erst
// PlanByteEdits (das des Puffers).
function IntroTextOf(AMap: TRdxCodeMap): TRdxIntroText;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 1 to AMap.LineCount do
    begin
      if i > 1 then SB.Append(#10);
      SB.Append(AMap.Raw(i));
    end;
    Result := TextOf(TEncoding.UTF8.GetBytes(SB.ToString));
  finally
    SB.Free;
  end;
end;

// Nur das Literal in Spalte ACol der Anweisungszeile (E28) - der Plan der
// Code-Aktion nennt alle gleichen Literale der Zeile. False, wenn ACol
// nicht darunter ist.
function KeepOnlyLiteral(const AText: TRdxIntroText;
  var ATarget: TRdxIntroTarget; ACol: Integer): Boolean;
var
  C : Integer;
  L : string;
begin
  Result := False;
  for C in ATarget.Plan.OldCols do
    Result := Result or (C = ACol);
  if not Result then Exit;
  L := AText.Lines[ATarget.SourceRow - 1];
  ATarget.Plan.OldCols := [ACol];
  ATarget.Plan.NewCols := [ACol];
  ATarget.Plan.NewUseLine := Copy(L, 1, ACol - 1) + ATarget.Name
    + Copy(L, ACol + Length(ATarget.Plan.Literal), MaxInt);
end;

// Die Zeile (1-basiert), in der Byte AOffset liegt.
function RowOfByte(const AText: TRdxIntroText; AOffset: Integer): Integer;
begin
  Result := Length(AText.Starts);
  while (Result > 1) and (AText.Starts[Result - 1] > AOffset) do
    Dec(Result);
end;

// Die Ersetzungen der Code-Aktion (Bytes, aufsteigend) als EINE Ersetzung
// fuer PlanByteEdits: von Spalte 1 der Zeile der ersten bis hinter die
// letzte; Expected und NewText aus den Bytes vor und nach ApplyIntroEdits
// (Zeilenenden #10 wie SpanText). Ein Bereich beginnt auf einem Zeichen
// (TRefactorInfoBuilder.SpanFits): ist die erste Zeile LEER - eine
// Leerzeile zwischen Zweigzeile und Anweisung, vor die IntroduceEdits
// 'begin' setzt -, beginnt er am Anfang der naechsten nicht leeren Zeile
// davor, die unveraendert in Expected und NewText steht. Bis Charge B1-FD
// begann er auf der Leerzeile: der Eintrag stand freigegeben im Menue, und
// jeder Klick scheiterte mit "Menue neu oeffnen" (Gegen-Review R4-02).
function AsOneEdit(const AText: TRdxIntroText;
  const AEdits: TRdxIntroByteEdits): TRdxEdit;
var
  OldBytes, NewBytes : TBytes;
  First, Last, E     : Integer;
  Row1, Row2         : Integer;
  Delta              : Integer;
  B                  : TRdxIntroByteEdit;
begin
  OldBytes := TEncoding.UTF8.GetBytes(AText.Text);
  NewBytes := ApplyIntroEdits(OldBytes, AEdits);
  First := MaxInt;
  Last := 0;
  for B in AEdits do
  begin
    if B.Offset < First then First := B.Offset;
    E := B.Offset + B.Len;
    if E > Last then Last := E;
  end;
  Row1 := RowOfByte(AText, First);
  Row2 := RowOfByte(AText, Last);
  while (Row1 > 1) and (AText.Lines[Row1 - 1] = '') do
    Dec(Row1);
  First := AText.Starts[Row1 - 1];
  Delta := Length(NewBytes) - Length(OldBytes);
  Result.Span := TRefactorSpan.Make(SPAN_MAGIC, Row1, 1, Row2,
    CharColOfByte(AText.Lines[Row2 - 1], Last - AText.Starts[Row2 - 1]));
  Result.Expected := TEncoding.UTF8.GetString(OldBytes, First, Last - First);
  Result.NewText := TEncoding.UTF8.GetString(NewBytes, First,
    Last + Delta - First);
end;

{ ---- Der Planer ---- }

// Das 'begin' des Hauptblocks einer Datei, die mit program bzw. library
// beginnt: von ihrem letzten 'end.' rueckwaerts bis zu dem Oeffner, der
// die end-Bilanz schliesst (END_OPENERS); Low = '' ohne. Ein end bzw.
// Oeffner mit ':=' dahinter ist ein benanntes Argument ('Doc.Range(Start
// := 0, End := 1)') und zaehlt nicht (IsKeywordAt) - bis Charge B1-FD
// verdeckte es den Hauptblock, und die Hilfe bot dort an (Gegen-Review R4,
// missed 3; wie H4c). Das 'end.' ist das ERSTE Schluesselwort-'end' mit
// '.' dahinter: Delphi liest hinter ihm nichts mehr, und Text dort (alte
// Notizen ohne Kommentarklammern) liess die Suche vom letzten Token aus
// still ohne Hauptblock enden (Wochen-Review 2026-10-21).
function MainBlockBegin(AMap: TRdxCodeMap): TRdxToken;
var
  T, P  : TRdxToken;
  Depth : Integer;
begin
  Result := Default(TRdxToken);
  if not InList(NextToken(AMap, 1, 1).Low, MAIN_BLOCK_WORDS) then Exit;
  T := NextToken(AMap, 1, 1);
  while (T.Low <> '')
     and not ((T.Low = KW_END) and (After(AMap, T).Low = '.')
              and IsKeywordAt(AMap, T, Before(AMap, T))) do
    T := After(AMap, T);
  if T.Low = '' then Exit;
  Depth := 1;
  while Depth > 0 do
  begin
    T := Before(AMap, T);
    if T.Low = '' then Exit;
    P := Before(AMap, T);
    if not IsKeywordAt(AMap, T, P) then Continue;
    if T.Low = KW_END then
      Inc(Depth)
    else if IsEndOpener(T.Low) then
      Dec(Depth);
  end;
  if T.Low = 'begin' then
    Result := T;
end;

// Die Zeile im Hauptblock eines Programms bzw. einer Bibliothek (Verdacht
// d: m22 des Pruefers bot dort an)? '' oder der Grund.
function MainBlockReason(AMap: TRdxCodeMap; ALine: Integer): string;
var
  B : TRdxToken;
begin
  Result := '';
  B := MainBlockBegin(AMap);
  if (B.Low <> '') and (ALine >= B.Line) then
    Result := _(R_MAIN_BLOCK, [B.Line, MsgByHand]);
end;

// Was die Datei als Ganzes verbietet: Spuren von Compilern vor Delphi 10.3.
function CompilerReason(AMap: TRdxCodeMap): string;
var
  Li : Integer;
  S  : string;
begin
  Result := '';
  S := OldCompilerTrace(AMap, FLOOR_INLINE_DECL, Li);
  if S <> '' then
    Result := _('an inline constant exists only from Delphi 10.3 on - the '
      + 'file shows traces of older compilers (%s, line %d); %s',
      [S, Li, MsgByHand]);
end;

// Der Plan fuer das Literal APlan.Value in Spalte ACol der Zeile ALine -
// der Teil von MagicNumber hinter LiteralAt, seit Charge B auch der von
// IntroduceAt (Code-Aktion ohne Fund): TargetAt mit dem Literal als Caret,
// nur dieses Literal (E28), dann Skript, Hauptblock und Spuren alter
// Compiler. True mit Name, Line, Col, Wrap und der einen Ersetzung, sonst
// False mit dem Grund (APlan.Value bleibt).
function PlanLiteral(AMap: TRdxCodeMap; ALine, ACol: Integer;
  var APlan: TRdxMagicPlan; out AReason: string): Boolean;
var
  Text   : TRdxIntroText;
  Target : TRdxIntroTarget;
begin
  Result := False;
  Text := IntroTextOf(AMap);
  Target := TargetAt(Text, ALine, ACol, MAGIC_NAME_BASE);
  if not Target.Plan.Ok then
    AReason := Target.Plan.Reason
  else if (Target.Plan.Literal <> APlan.Value)
     or not KeepOnlyLiteral(Text, Target, ACol) then
    AReason := MsgMovedSuffix(_('at the literal in column %d the code action '
      + 'reads "%s" instead of %s', [ACol, Target.Plan.Literal, APlan.Value]))
  else
    AReason := ScriptReason(AMap, _(FEATURE_INLINE));
  if AReason = '' then
    AReason := MainBlockReason(AMap, ALine);
  if AReason = '' then
    AReason := CompilerReason(AMap);
  if AReason <> '' then Exit;
  APlan.Name := Target.Name;
  APlan.Line := ALine;
  APlan.Col := ACol;
  APlan.Wrap := Target.Plan.Wrap;
  AddEdit(APlan.Edits, AsOneEdit(Text, IntroduceEdits(Text, Target)));
  Result := True;
end;

class function TRdxMagicFixes.MagicNumber(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out APlan: TRdxMagicPlan;
  out AReason: string): Boolean;
var
  Col : Integer;
begin
  Result := False;
  Col := 0;
  APlan := Default(TRdxMagicPlan);
  APlan.Value := NumberOf(AMessage);
  if APlan.Value = '' then
    AReason := _('the message names no number ("Magic number "N" ...")')
  else if APlan.Value[1] = '-' then
    AReason := _('the message names %s - the detector does not report signed '
      + 'numbers, the literal has no sign; not supported', [APlan.Value])
  else
    AReason := LiteralAt(AMap, ALine, APlan.Value, Col);
  if AReason <> '' then Exit;
  Result := PlanLiteral(AMap, ALine, Col, APlan, AReason);
end;

class function TRdxMagicFixes.IntroduceAt(AMap: TRdxCodeMap; ALine,
  ACol: Integer; out APlan: TRdxMagicPlan; out AReason: string): Boolean;
var
  First, Stop : Integer;
begin
  Result := False;
  AReason := '';
  APlan := Default(TRdxMagicPlan);
  if LiteralContaining(AMap, ALine, ACol, First, Stop) <> lkNumber then
    Exit;   // kein Kandidat (F4): kein Eintrag
  APlan.Value := Copy(AMap.Raw(ALine), First, Stop - First);
  // Die Code-Aktion liest nur dezimale und hexadezimale Zahlen
  // (uRdxIntroPlan.NumbersOf); ein Delphi-11-Binaer- bzw. Oktal-Literal
  // fiele dort als "kein Zahl-Literal am Caret" durch - der Satz sagt,
  // warum.
  if CharInSet(APlan.Value[1], ['%', '&']) then
  begin
    AReason := _('%s is a binary or octal literal - the code action only '
      + 'handles decimal and hexadecimal numbers', [APlan.Value]);
    Exit;
  end;
  Result := PlanLiteral(AMap, ALine, First, APlan, AReason);
end;

{ ---- Was nur die Platte weiss ---- }

type
  // Die Projektdateien EINES Verzeichnisses (ProjectFilesIn): die erste
  // Lazarus- und die erste alte Delphi-Projektdatei, die .dproj mit der
  // kleinsten ProjectVersion (Zehntel; -1 ohne lesbare Version) - bzw.
  // die erste vor 10.3, danach liest NoteProjectFile keine .dproj mehr.
  TRdxProjectFiles = record
    Lazarus  : string;
    Legacy   : string;
    Dproj    : string;
    DprojVer : Integer;
  end;

// Die ProjectVersion der .dproj APath in Zehnteln ('18.5' -> 185; nur die
// erste Nachkommastelle); -1, wenn die Datei nicht lesbar ist oder keine
// traegt (Delphi 2007 schrieb noch keine).
function ProjectVersionOf(const APath: string): Integer;
var
  FS    : TFileStream;
  Bytes : TBytes;
  Text  : string;
  P, i  : Integer;
begin
  Result := -1;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Bytes, DPROJ_HEAD_BYTES);
      SetLength(Bytes, FS.Read(Bytes[0], DPROJ_HEAD_BYTES));
    finally
      FS.Free;
    end;
  except
    on EStreamError do
      Exit;
  end;
  Text := TEncoding.ANSI.GetString(Bytes);
  P := Pos(PROJECT_VERSION_TAG, Text);
  if P = 0 then Exit;
  i := P + Length(PROJECT_VERSION_TAG);
  P := i;
  while (i <= Length(Text)) and CharInSet(Text[i], ['0'..'9']) do
    Inc(i);
  if i = P then Exit;
  Result := StrToIntDef(Copy(Text, P, i - P), -1);
  if Result < 0 then Exit;
  Result := Result * 10;
  if (i < Length(Text)) and (Text[i] = '.') and CharInSet(Text[i + 1], ['0'..'9']) then
    Inc(Result, Ord(Text[i + 1]) - Ord('0'));
end;

// Die Datei AName des Verzeichnisses ADir in AFiles eintragen; AMinVersion
// die ProjectVersion der Schwelle (TRdxCompilerFloor.ProjectVersion).
procedure NoteProjectFile(const ADir, AName: string; AMinVersion: Integer;
  var AFiles: TRdxProjectFiles);
var
  Ext : string;
  Ver : Integer;
begin
  Ext := LowerCase(ExtractFileExt(AName));
  if InList(Ext, LAZARUS_EXTENSIONS) then
  begin
    if AFiles.Lazarus = '' then
      AFiles.Lazarus := AName;
  end
  else if InList(Ext, LEGACY_EXTENSIONS) then
  begin
    if AFiles.Legacy = '' then
      AFiles.Legacy := AName;
  end
  else if Ext = DPROJ_EXTENSION then
  begin
    // Eine .dproj vor der Schwelle (oder ohne Version) steht schon fest:
    // sie sperrt ohnehin, weitere Koepfe zu lesen kostete im Hauptthread je
    // Datei 64 KB (Paketordner mit vielen .dproj; Wochen-Review
    // 2026-10-21). Der Grund nennt dann die erste alte statt der aeltesten.
    if (AFiles.Dproj <> '') and (AFiles.DprojVer < AMinVersion) then
      Exit;
    Ver := ProjectVersionOf(IncludeTrailingPathDelimiter(ADir) + AName);
    if (AFiles.Dproj = '') or (Ver < AFiles.DprojVer) then
    begin
      AFiles.Dproj := AName;
      AFiles.DprojVer := Ver;
    end;
  end;
end;

// Die Projektdateien in ADir (EIN Durchlauf ueber das Verzeichnis).
function ProjectFilesIn(const ADir: string;
  AMinVersion: Integer): TRdxProjectFiles;
var
  SR : TSearchRec;
begin
  Result := Default(TRdxProjectFiles);
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, SR) <> 0 then
    Exit;
  try
    repeat
      if (SR.Attr and faDirectory) = 0 then
        NoteProjectFile(ADir, SR.Name, AMinVersion, Result);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

// Die ProjectVersion in Zehnteln als Text ('185' -> '18.5').
function VersionText(AVersion: Integer): string;
begin
  Result := Format('%d.%d', [AVersion div 10, AVersion mod 10]);
end;

// Die Delphi-Projektdateien eines Verzeichnisses als Grund: eine .dproj
// vor der Schwelle von AFeature bzw. - ohne .dproj - eine alte
// Projektdatei; '' sonst.
function DelphiProjectReason(const AFiles: TRdxProjectFiles;
  const ADir: string; AFeature: TRdxLateFeature): string;
var
  MinVer : Integer;
begin
  Result := '';
  MinVer := FloorOf(AFeature).ProjectVersion;
  if AFiles.Dproj <> '' then
  begin
    if AFiles.DprojVer < 0 then
      Result := _(R_NO_VERSION[AFeature], [AFiles.Dproj, ADir, MsgByHand])
    else if AFiles.DprojVer < MinVer then
      Result := _(R_OLD_DPROJ[AFeature], [AFiles.Dproj, ADir,
        VersionText(AFiles.DprojVer), VersionText(MinVer), MsgByHand]);
  end
  else if AFiles.Legacy <> '' then
    Result := _(R_LEGACY[AFeature], [AFiles.Legacy, ADir, MsgByHand]);
end;

// Netzpfad: uRdxPaths.IsNetworkPath (UNC und Netzlaufwerk, seit Charge
// B1-FD die eine Regel fuer Unit und Includes - bis dahin stand hier eine
// eigene Kopie nur fuer UNC; seit Charge B2S-a ist '\\?\C:\..' lokal).
class function TRdxMagicFixes.FileReason(const AFileName: string;
  AFeature: TRdxLateFeature): string;
var
  Ext, Dir, Up : string;
  Level        : Integer;
  Files        : TRdxProjectFiles;
  DelphiSeen   : Boolean;
begin
  Result := '';
  if AFileName = '' then Exit;
  Ext := LowerCase(ExtractFileExt(AFileName));
  if InList(Ext, FPC_EXTENSIONS) then
    Exit(_(R_FPC_FILE[AFeature], [Ext]));
  if IsNetworkPath(AFileName) then
    Exit(_(R_NETWORK, [ExtractFileDir(AFileName), MsgByHand]));
  Dir := ExtractFileDir(AFileName);
  DelphiSeen := False;
  for Level := 0 to PROJECT_LEVELS do
  begin
    if Dir = '' then Exit;
    Files := ProjectFilesIn(Dir, FloorOf(AFeature).ProjectVersion);
    if Files.Lazarus <> '' then
      Exit(_(R_LAZARUS[AFeature], [Files.Lazarus, Dir]));
    // Das NAECHSTE Verzeichnis mit Delphi-Projektdateien entscheidet
    // (eine .dproj ab der Schwelle dort macht alte Dateien weiter oben
    // stumm).
    if not DelphiSeen then
    begin
      Result := DelphiProjectReason(Files, Dir, AFeature);
      if Result <> '' then Exit;
      DelphiSeen := (Files.Dproj <> '') or (Files.Legacy <> '');
    end;
    Up := ExtractFileDir(Dir);
    if Up = Dir then Exit;
    Dir := Up;
  end;
end;

// Die Pruefung eines Includes (TRdxIncludeTest): eine FPC-Weiche oder eine
// Spur aelterer Compiler darin - '' oder der Grund. AArg ist das
// Sprachmittel als Zahl (Ord(TRdxLateFeature), IncludeReason) - der Test
// ist ein schlichter Funktionszeiger mit Text-Argument.
function CompilerInInclude(const AFile: string; ALines: TStrings;
  AMap: TRdxCodeMap; const AArg: string): string;
var
  Li      : Integer;
  S       : string;
  Feature : TRdxLateFeature;
begin
  Result := '';
  Feature := TRdxLateFeature(StrToIntDef(AArg, Ord(lfInlineConst)));
  for Li := 0 to ALines.Count - 1 do
    if LineLooksFpcAware(ALines[Li]) then
      Exit(_(R_INC_FPC[Feature], [AFile, Li + 1]));
  S := OldCompilerTrace(AMap, FloorOf(Feature), Li);
  if S <> '' then
    Result := _(R_INC_OLD[Feature], [AFile, S, Li, MsgByHand]);
end;

class function TRdxMagicFixes.IncludeReason(const AFileName: string;
  AMap: TRdxCodeMap; AFeature: TRdxLateFeature): string;
var
  Check : TRdxIncludeCheck;
begin
  Check.Test := CompilerInInclude;
  Check.Arg := IntToStr(Ord(AFeature));
  Check.MissingFmt := _(R_INC_UNSEEN);
  Result := IncludeChainReason(AFileName, AllIncludes(AMap), Check);
end;

end.

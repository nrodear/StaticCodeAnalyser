unit uRdxCodeMap;

// reDelphix - Code-Sicht einer Datei und Token-Leser darauf, OHNE ToolsAPI.
// Gemeinsame Grundlage der Planer (uRdxSimpleFixes), der Unterdrueck-Hilfen
// (uRdxSuppress) und des Laeufers (uRdxRecipeRunner); bis 2026-10-10 lag sie
// in uRdxSimpleFixes, und uRdxSuppress zog dafuer die Planer mit (Review
// reDelphiX nach Bereichen, Minor 7).
//
// Verhaeltnis zum Core: TDetectorUtils.ScanCodeLine ist dieselbe Regel fuer
// Kommentare und einzeilige Strings - uTestRdxCodeMap prueft beide an
// denselben Eingaben gegeneinander. Unterschied mit Absicht: die Code-Sicht
// kennt die mehrzeiligen Strings von Delphi 12 (''' ... '''), ScanCodeLine
// nicht; der Core fuehrt diese Regel als
// TRefactorInfoBuilder.OpensMultiLineString.

interface

uses
  System.Classes;   // TStrings

const
  MIN_MULTI_QUOTES = 3;   // ''' oeffnet einen mehrzeiligen String (Delphi 12)
  // Token, die ein eigenes 'end' brauchen - die end-Bilanzen der Planer
  // (uRdxStructFixes, uRdxLineFixes; bis 2026-10-10 je eine Kopie).
  END_OPENERS: array[0..4] of string = ('begin', 'case', 'try', 'asm',
    'record');
  // Hinter diesen Token ist ein Wort ein Bezeichner ('&End', '@@End',
  // 'X.Then').
  IDENT_PREFIXES: array[0..2] of string = ('&', '@', '.');
  // Token vor dem Anfang einer Anweisung (uRdxStructFixes: steht vor dem
  // if etwas anderes, ist es ein bedingter Ausdruck; uRdxRaiseFixes:
  // 'EFoo.Create(..)' als ganze Anweisung).
  STATEMENT_PREV: array[0..11] of string = (';', 'begin', 'then', 'else',
    'do', 'try', 'finally', 'except', 'repeat', ':', 'initialization',
    'finalization');
  // Das Wort einer Include-Direktive ('{$I datei}', '{$INCLUDE datei}').
  INCLUDE_WORDS: array[0..1] of string = ('i', 'include');
  // Damit beginnt der Kopf einer Routine (bis Charge H3c je eine Kopie in
  // uRdxCleanupFixes, uRdxRoutineFixes und uRdxRaiseFixes; Gegen-Review H3,
  // Major 2). uRdxDeclFixes.HEADER_WORDS nimmt 'property' dazu - dort
  // beginnt eine Member-Signatur, kein Routinenkopf.
  ROUTINE_WORDS: array[0..4] of string = ('procedure', 'function',
    'constructor', 'destructor', 'operator');

type
  // Zeichenklassen einer Datei, spaltentreu: 'c' Code, 's' String-Literal,
  // 'k' Kommentar oder Direktive ({...}, (*...*), //...). Block-Kommentare
  // und mehrzeilige Strings werden ueber Zeilen verfolgt, einfache Strings
  // enden mit der Zeile.
  // LEBENSDAUER (Review Quick-Fix-Units 2026-10-14): die Map LEIHT ALines -
  // die Klassen entstehen einmal in Create (Schnappschuss), Raw() und
  // LineCount lesen dagegen live aus ALines. ALines muss darum laenger
  // leben als die Map und darf waehrend ihrer Lebensdauer nicht veraendert
  // werden; sonst passen Klassen und Text nicht mehr zusammen, und die
  // Planer lesen Code, wo ein Kommentar steht. Die Aufrufer (uRdxProvider,
  // uRdxRecipeRunner, die Tests) bauen die Map je Lauf neu.
  TRdxCodeMap = class
  private
    FLines   : TStrings;
    FClass   : TArray<string>;
    FSlash   : TArray<Integer>;   // je Zeile: Spalte des '//'-Kommentars, 0 = keiner
    FInside  : TArray<Boolean>;   // je Zeile: beginnt in Block-Kommentar oder mehrzeiligem String
    // Zustand nur waehrend des Aufbaus (Create): die Zeile, ihre Klassen
    // und was gerade offen ist.
    FText    : string;
    FKinds   : string;
    FInBrace : Boolean;
    FInParen : Boolean;
    FInStr   : Boolean;
    FMulti   : Integer;   // offener mehrzeiliger String: Zahl seiner Quotes, 0 = keiner
    // Je ein Schritt ab Spalte j der Zeile FText; liefern die Spalte dahinter.
    function StepComment(j: Integer): Integer;
    function StepString(j: Integer): Integer;
    function StepQuote(j: Integer): Integer;
    function StepCode(ALineIdx, j: Integer): Integer;
    // Zeilenanfang in einem mehrzeiligen String.
    function StepMultiLine: Integer;
  public
    // Liest ALines einmal und klassifiziert jedes Zeichen; ALines bleibt im
    // Besitz des Aufrufers (s. LEBENSDAUER oben).
    constructor Create(ALines: TStrings);
    // Zahl der Zeilen der Datei (live aus ALines).
    function LineCount: Integer;
    // Rohzeile ALine (1-basiert, live aus ALines), '' ausserhalb.
    function Raw(ALine: Integer): string;
    // Klasse des Zeichens (ALine, ACol); ' ' ausserhalb der Zeile.
    function ClassAt(ALine, ACol: Integer): Char;
    // True, wenn (ALine, ACol) Code ist - kein String, kein Kommentar.
    function IsCode(ALine, ACol: Integer): Boolean;
    // Kommentar oder Direktive in ALine zwischen AFrom..ATo.
    function HasComment(ALine, AFrom, ATo: Integer): Boolean;
    // String, Kommentar oder Direktive in ALine zwischen AFrom..ATo.
    function HasNonCode(ALine, AFrom, ATo: Integer): Boolean;
    // Spalte, an der in ALine ein '//'-Kommentar BEGINNT (aus Code heraus,
    // nicht in einem String, {...} oder (*...*)); 0 = keiner.
    function LineCommentCol(ALine: Integer): Integer;
    // True, wenn ALine IN einem Block-Kommentar ({...}, (*...*)) oder
    // mehrzeiligen String beginnt, der in einer frueheren Zeile anfing.
    // Eine Zeile, die man davor einfuegt, laege dann ebenfalls darin.
    function StartsInside(ALine: Integer): Boolean;
  end;

  // Ein Schritt einer Token-Suche der Planer: weiter, gefunden, abbrechen.
  TRdxStep = (rsGoOn, rsFound, rsStop);

  // Ein Code-Token: Bezeichner/Schluesselwort (klein in Low), Zahl, oder
  // ein Satzzeichen (':=', '<>', '<=', '>=', '..' als eines). Low = '' ist
  // "kein Token" (Dateiende, nicht gefunden; Default(TRdxToken)).
  TRdxToken = record
    Line : Integer;
    Col  : Integer;   // erstes Zeichen
    Len  : Integer;
    Low  : string;    // klein geschrieben
    // True fuer einen Bezeichner oder ein Schluesselwort (Low beginnt mit
    // einem Bezeichner-Anfangszeichen) - nicht fuer Zahl, Satzzeichen oder
    // "kein Token". Ob das Wort ein Schluesselwort ist, sagt erst der
    // Kontext (IsKeywordAfter, die KEYWORDS der Planer).
    function IsWord: Boolean;
    function EndCol: Integer;   // hinter dem letzten Zeichen
  end;

  // Praedikat einer Token-Suche auf einer Zeile (OneTokenOnLine): passt T?
  // AArg ist der Suchbegriff des Aufrufers (ein Name, ein Ziel), '' ohne.
  // Das Token davor holt sich ein Praedikat selbst (Before) - eine plaine
  // Funktion, weil FPC 3.2 keine Funktionsreferenzen kennt.
  TRdxTokenTest = function(AMap: TRdxCodeMap; const T: TRdxToken;
    const AArg: string): Boolean;

  // Eine Token-Suche auf einer Zeile (OneTokenOnLine): das Praedikat, sein
  // Argument und die Texte der Gruende - What ist, was fehlt ('kein begin',
  // 'keine Selbstzuweisung "x := x"'), ManyFmt der Text der Mehrdeutigkeit
  // mit %d fuer die Zahl der Treffer ('%d begin', '%d-mal "end else"').
  // Bis Charge R8 (2026-10-14) stand diese Suche siebenmal in den Planern.
  TRdxLineSearch = record
    Test    : TRdxTokenTest;
    Arg     : string;
    What    : string;
    ManyFmt : string;
  end;

  // Haken der end-Bilanz (BlockEnd): je Token, das weder Oeffner noch end
  // ist, mit dem Token davor und der Tiefe (1 = oberste Ebene des Blocks);
  // liefert den Grund, die Bilanz abzubrechen, oder ''.
  TRdxBlockHook = function(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
    ADepth: Integer): string;

// Bezeichner-Zeichen wie im Core (TRefactorInfoBuilder): Buchstabe, '_'
// oder ein Zeichen ueber #127 (Umlaute sind in Delphi-Bezeichnern erlaubt)
// beginnt einen Bezeichner, dazu Ziffern darin. Zahlen beginnen NICHT mit
// IsIdentStart - so trennt TokenAt Zahl und Wort.
function IsIdentStart(C: Char): Boolean;
function IsIdentChar(C: Char): Boolean;
// Leerzeichen oder Tab - der Leerraum, den die Planer ueberspringen
// (andere Steuerzeichen stehen in einer Zeile nicht, Zeilenenden kennt die
// Map nicht).
function IsBlank(C: Char): Boolean;
// Erste Spalte ab AFrom, die kein Leerzeichen/Tab ist (Length + 1 am Ende).
function SkipBlanks(const S: string; AFrom: Integer): Integer;
// Zahl der Quotes ab S[AAt] in Folge.
function QuoteRun(const S: string; AAt: Integer): Integer;

// Das Token, das an (ALine, ACol) beginnt (Code vorausgesetzt).
function TokenAt(AMap: TRdxCodeMap; ALine, ACol: Integer): TRdxToken;
// Naechstes Code-Token ab (ALine, ACol) einschliesslich - ueber Leerraum,
// Strings, Kommentare und Zeilen hinweg; Low = '' am Dateiende.
function NextToken(AMap: TRdxCodeMap; ALine, ACol: Integer): TRdxToken;
// Token unmittelbar nach ATok.
function After(AMap: TRdxCodeMap; const ATok: TRdxToken): TRdxToken;
// Das Token, das an (ALine, ACol) ENDET (Code, kein Leerraum).
function TokenEndingAt(AMap: TRdxCodeMap; ALine, ACol: Integer): TRdxToken;
// Vorheriges Code-Token vor (ALine, ACol) ausschliesslich.
function PrevToken(AMap: TRdxCodeMap; ALine, ACol: Integer): TRdxToken;
// Vor ATok.
function Before(AMap: TRdxCodeMap; const ATok: TRdxToken): TRdxToken;

// Beginnt an (ALine, ACol) eine Compiler-Direktive ('{$' oder '(*$')? Die
// Code-Sicht fuehrt Direktiven als Kommentar ('k'); '{$' in einem
// '//'-Kommentar ist keine (Gegen-Review SCA101, Nit 6).
function DirectiveAt(AMap: TRdxCodeMap; ALine, ACol: Integer): Boolean;
// Beginnt zwischen (AFromLine, 1) und dem Token ATo eine Direktive? Bis
// Dateiende, wenn ATo leer ist.
function DirectiveBefore(AMap: TRdxCodeMap; AFromLine: Integer;
  const ATo: TRdxToken): Boolean;
// Eine Direktive (DirectiveAt) in den Zeilen AFrom..ATo? Bis Charge R8
// (2026-10-14) je eine Kopie in uRdxLineFixes, uRdxDeclFixes und
// uRdxStructFixes.
function DirectiveInLines(AMap: TRdxCodeMap; AFrom, ATo: Integer): Boolean;
// Beginnt zwischen dem Ende des Tokens APrev und (ALine, ACol) eine
// Direktive (DirectiveAt)? Leeres APrev: ab Dateianfang. Anders als
// DirectiveBefore (ab Spalte 1 einer Zeile) beginnt die Suche HINTER
// einem Token. Bis Charge H5c in uRdxSimpleFixes, eine Fassung von Token
// zu Token in uRdxResultFixes (Gegen-Review H5, Minor 6).
function DirectiveBetween(AMap: TRdxCodeMap; const APrev: TRdxToken;
  ALine, ACol: Integer): Boolean;
// DirectiveAt nur an '{' bzw. '(' - fuer Durchsichten ueber jedes Zeichen
// einer Datei (DirectiveAt kopiert je Aufruf). Bis Charge H3c in
// uRdxRoutineFixes.
function OpensDirective(AMap: TRdxCodeMap; ALine, ACol: Integer): Boolean;
// Das Wort einer Direktive an (ALine, ACol): '{$IFDEF X}' -> 'ifdef'; AArg:
// dahinter Leerraum oder ein Quote (Dateiname - '{$I x.inc}', nicht
// '{$I+}'). Bis Charge H3c in uRdxRoutineFixes.
function DirectiveWord(AMap: TRdxCodeMap; ALine, ACol: Integer;
  out AArg: Boolean): string;
// Der Text der Direktive an (ALine, ACol) hinter ihrem Wort bis vor den
// Schliesser auf derselben Zeile ('{$DEFINE M := X}' -> ' M := X'; ohne
// Schliesser bis zum Zeilenende).
function DirectiveArgs(AMap: TRdxCodeMap; ALine, ACol: Integer): string;
// Die Datei einer Include-Direktive an (ALine, ACol) ('{$I x.inc}',
// '{$INCLUDE ''a b.inc''}', '(*$I x*)'), ohne Quotes; '' ohne Include.
function IncludeFileAt(AMap: TRdxCodeMap; ALine, ACol: Integer): string;
// Ein {$I datei} in den Zeilen AFrom..ATo? Zeile oder 0. Bis Charge H3c in
// uRdxRoutineFixes (SCA147: Include im Klassenrumpf), seitdem auch fuer
// SCA053 (Include im Gueltigkeitsbereich).
function IncludeInLines(AMap: TRdxCodeMap; AFrom, ATo: Integer): Integer;

// Gleicher Bezeichner? ALow und AKey sind klein geschrieben (LowerCase senkt
// nur ASCII); Zeichen ueber #127 gelten als gleich, wenn beide darueber
// liegen - Delphi vergleicht Bezeichner auch dort ohne Gross/klein (ein
// Aufruf mit grossem Umlaut ruft die Routine mit kleinem), und ein Treffer
// zu viel sperrt nur. Bis Charge H3c nur in uRdxCleanupFixes (SCA053); seitdem
// auch fuer SCA164/SCA147 (Gegen-Review H3, Verdacht 1).
function SameIdent(const ALow, AKey: string): Boolean;
// Kommt ALowName als ganzer Bezeichner in ALowText vor (beides klein,
// Vergleich wie SameIdent)? Fuer Texte ausserhalb der Code-Sicht:
// String-Literale, Direktiven, Form- und Include-Dateien.
function HasIdentWord(const ALowText, ALowName: string): Boolean;
// AWord als ganzes Wort in AText, gleich geschrieben; Wortgrenze nur
// ASCII - wie der Detektor (TDetectorUtils) die Grenze eines Code-Merkmals
// bzw. Markers sieht. Bis Charge H3c als HasWord in uRdxCleanupFixes.
function HasAsciiWord(const AText, AWord: string): Boolean;
// Das letzte Glied eines Pfads ('TOuter.TInner' -> 'TInner'). Bis Charge
// H5c in uRdxRoutineFixes und als ShortNameOf in uRdxResultFixes.
function LastPart(const S: string): string;
// Steht in AText ein Unterdrueck- oder Absichtsmarker - 'noinspection'
// bzw. die Marker von SCA019 in jeder Schreibweise, 'XXX' nur gross (klein
// ist es dort ein Platzhalter)? '' oder der Grund. SCA070 prueft den
// geloeschten Text, SCA164/SCA147 die Kommentare ueber dem Kopf (Gegen-
// Review H3, Minor 3); bis Charge H3c in uRdxCleanupFixes - hier, weil
// uRdxCleanupFixes seitdem uRdxRoutineFixes braucht (ReadRoutine) und
// beide sich sonst gegenseitig einbanden.
function MarkerReason(const AText: string): string;

// Dieselbe Stelle (Zeile und Spalte)? Bis Charge H3c je eine Kopie in
// uRdxFlowFixes, uRdxCleanupFixes und uRdxRoutineFixes.
function SameTok(const A, B: TRdxToken): Boolean;
// Steht A vor B (Zeile, dann Spalte)? Bis Charge H4c je eine Kopie in
// uRdxRoutineFixes und uRdxTryFixes (uRdxCleanupFixes.TokAfter rechnete
// dasselbe ueber TRdxTextPos; Gegen-Review H4, Minor 10).
function TokBefore(const A, B: TRdxToken): Boolean;
// Der Text von T wie im Quelltext (Gross/klein erhalten - T.Low ist
// klein). Bis Charge H4c je eine Kopie in uRdxRoutineFixes und
// uRdxTryFixes.
function TokText(AMap: TRdxCodeMap; const T: TRdxToken): string;
// Haengt T an AList an. Bis Charge H5c je eine Kopie in uRdxRoutineFixes
// und uRdxResultFixes (Gegen-Review H5, Minor 6).
procedure AddToken(var AList: TArray<TRdxToken>; const T: TRdxToken);
// Steht T als erstes auf seiner Zeile - davor nur Leerraum? Ob die Zeile
// in einem Kommentar oder mehrzeiligen String beginnt, prueft der
// Aufrufer selbst (StartsInside). Bis Charge H5c in uRdxTryFixes, eine
// Variante mit StartsInside in uRdxResultFixes.
function FirstOnLine(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
// Beginnt an T ein Routinenkopf? Ein Wort aus ROUTINE_WORDS als
// Schluesselwort, davor (APrev) nichts aus NOT_HEAD_AFTER - kein Typ einer
// Variablen, eines Parameters oder eines Typs (':', '='), keine anonyme
// Methode (':=', '(', ','), kein 'reference to', kein 'array of
// procedure', kein Attribut-Inhalt ('['). Die eine Kopferkennung der
// Planer: bis Charge H3c stand sie als IsHeadAt in uRdxRoutineFixes und
// als IsHeader mit einer Positivliste der Vorgaenger (';', 'class',
// 'implementation', 'interface') in uRdxCleanupFixes (Gegen-Review H3,
// Major 2; im Korpus-Harness ohne Unterschied).
function IsRoutineHeadAfter(const T, APrev: TRdxToken): Boolean;
// Dasselbe mit dem Token davor aus der Code-Sicht.
function IsRoutineHead(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;

// ---- Geteilte Laeufe der Planer (Charge R8, 2026-10-14: bis dahin je
// Planer eine Kopie - Klammerabgleich 4x, "genau ein Token" 7x, end-Bilanz
// 3x). ----

// Die schliessende Klammer zu AOpen - '(' zu ')', '[' zu ']', '<' zu '>' -
// ab AOpen gezaehlt, nur die eigene Klammerart, ueber Zeilen hinweg; Low =
// '' ohne (auch, wenn AOpen keine dieser Klammern ist). AMaxLines begrenzt
// die Suche auf die Zeilen bis AOpen.Line + AMaxLines (0 = nur die Zeile
// von AOpen).
function MatchClose(AMap: TRdxCodeMap; const AOpen: TRdxToken;
  AMaxLines: Integer = MaxInt): TRdxToken;
// Das Token hinter der schliessenden Klammer zu AOpen (MatchClose); Low =
// '' ohne Klammer oder am Dateiende.
function AfterClose(AMap: TRdxCodeMap; const AOpen: TRdxToken): TRdxToken;
// Klammertiefe eines Tokens: '(' und '[' +1, ')' und ']' -1, sonst 0 -
// beide Klammerarten gemeinsam ('<' und '>' nicht: ob Vergleich oder
// Typparameter, weiss erst der Aufrufer, s. MatchClose). Rueckwaerts
// gelesen zieht der Aufrufer den Wert ab. Bis Charge B2S-a je eine Kopie
// als ParenDelta in uRdxFlowFixes und uRdxCleanupFixes und als DepthDelta
// in uRdxSimpleFixes, dazu ausgeschrieben in uRdxStructFixes, uRdxTryFixes
// und uRdxSqlTemplate (Review R3-05).
function ParenDelta(const T: TRdxToken): Integer;

// Genau ein Code-Token auf ALine, auf das ASearch.Test passt: '' und das
// Token in AHit; sonst der Grund (OneTokenReason; AHit ist dann der letzte
// Treffer oder leer). Die Planer lehnen so Funde ab, deren Zeile verschoben
// (kein Treffer) oder mehrdeutig (mehrere) ist.
function OneTokenOnLine(AMap: TRdxCodeMap; ALine: Integer;
  const ASearch: TRdxLineSearch; out AHit: TRdxToken): string;
// Der Grund zu ACount Treffern auf ALine: 0 -> '<AWhat> auf der
// gemeldeten Zeile - Zeile verschoben? Datei neu pruefen'; mehr als 1 ->
// 'Zeile N traegt <AManyFmt mit ACount fuer %d und AArg fuer %s> -
// mehrdeutig'; genau 1 -> ''. AManyFmt ist ein Format-Muster: Text aus der
// Meldung gehoert in AArg, nie in das Muster - ein '%' darin (Delphi-11-
// Binaerliteral '%101') warf sonst EConvertError (Gegen-Review R5, missed 2:
// uRdxTryFixes.LockPair setzte den Sperrtext der Meldung ins Muster).
function OneTokenReason(ALine, ACount: Integer;
  const AWhat, AManyFmt: string; const AArg: string = ''): string;

// Die end-Bilanz vorwaerts ab hinter AFrom (dem Oeffner bzw. dem else einer
// Anweisungsliste): END_OPENERS als Schluesselwort zaehlen hoch, 'end'
// herunter ('&End', '@@End', 'X.End' sind Bezeichner, IsKeywordAfter). Das
// end, das die Bilanz schliesst, kommt nach AEnd, das Token davor nach
// ALast; beide leer, wenn keines kommt. AHook (nil = keiner) sieht jedes
// andere Token und kann mit einem Grund abbrechen - der ist dann das
// Ergebnis, sonst ''.
function BlockEnd(AMap: TRdxCodeMap; const AFrom: TRdxToken;
  AHook: TRdxBlockHook; out AEnd, ALast: TRdxToken): string;

// ALow ist eines der Woerter in AList (gleich geschrieben).
function InList(const ALow: string; const AList: array of string): Boolean;
// Ein Wort als Schluesselwort - nicht hinter '&', '@' oder '.' (APrev).
function IsKeywordAfter(const T, APrev: TRdxToken): Boolean;
// Dasselbe, und dahinter steht kein ':=' - ein benanntes OLE-Argument
// ('Range(Start := 0, End := 1)') traegt ein Schluesselwort als Namen
// (Gegen-Review H4, Minor 2; dieselbe Klasse wie SCA053 in H3c). Bis
// Charge H4c nutzt nur uRdxTryFixes die Fassung: IsKeywordAfter kennt das
// Token dahinter nicht, und die anderen Planer darauf umzustellen bewegte
// ihre Angebote - eine eigene Charge.
function IsKeywordAt(AMap: TRdxCodeMap; const T, APrev: TRdxToken): Boolean;
// ALow oeffnet einen Block mit eigenem 'end' (END_OPENERS).
function IsEndOpener(const ALow: string): Boolean;
// Eine Einrueckstufe: was ADeeperLine ueber AIndent hinaus einrueckt;
// sonst ein Tab, wenn AIndent Tabs traegt, oder zwei Leerzeichen.
function IndentStep(const AIndent, ADeeperLine: string): string;
const
  // Der Grund, wenn eine Meldung keine Spalte nennt (ColumnFromMessage
  // liefert 0). Bis Charge B2S-a je eine Konstante in uRdxSimpleFixes und
  // uRdxLineFixes und ein Literal in uRdxStructFixes (Review R3-05).
  R_NO_COLUMN = 'Spalte fehlt in der Meldung';

// 'at column N' aus einer Meldung; 0 = nicht vorhanden. Bis 2026-10-10 in
// uRdxSimpleFixes, seit SCA101 auch fuer uRdxStructFixes.
function ColumnFromMessage(const AMessage: string): Integer;
// Der Text zwischen den ersten beiden AQuote in AText ('Interface "IFoo"
// has no GUID' mit '"' -> 'IFoo', 'Empty `strict private` section' mit
// '`' -> 'strict private'); '' ohne zwei AQuote oder ohne Text
// dazwischen. Wie geschrieben - klein schreibt der Aufrufer. Bis Charge
// B2S-a als QuotedNameOf (uRdxDeclFixes) und BoundNameOf (uRdxRaiseFixes)
// byte-gleich kopiert und in KeywordOf (uRdxLineFixes), SectionNameOf
// (uRdxSimpleFixes) und TRdxMagicFixes.NumberOf ausgeschrieben (Review
// R3-05).
function QuotedText(const AText: string; AQuote: Char): string;

implementation

uses
  System.SysUtils;   // CharInSet, LowerCase, Format

const
  // Davor beginnt ein Routinenwort KEINEN Kopf: Typ einer Variablen oder
  // eines Parameters, Typdeklaration, anonyme Methode, 'reference to',
  // 'array of procedure' (IsRoutineHeadAfter).
  NOT_HEAD_AFTER: array[0..7] of string = (':', '=', 'to', '(', ',', ':=',
    'of', '[');
  // Absichtsmarker wie bei SCA019 (uTodoComment) - die drei hier in jeder
  // Schreibweise, MARKER_XXX nur gross; ein Unterdrueck-Marker wirkt auf
  // andere Funde (MarkerReason).
  INTENT_MARKERS: array[0..2] of string = ('todo', 'fixme', 'hack');
  MARKER_XXX      = 'XXX';
  MARKER_SUPPRESS = 'noinspection';

// Zeichen > #127 wie der Core (uRefactorInfoBuilder) und uRdxRecipes:
// Bezeichner mit Umlaut sind in Delphi erlaubt - sonst lehnten die Planer
// 'Uebersicht.Free' mit einem falschen Grund ab (Review nach Bereichen
// 2026-10-10, Nit 17).
function IsIdentStart(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_']) or (C > #127);
end;

function IsIdentChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (C > #127);
end;

function IsBlank(C: Char): Boolean;
begin
  Result := CharInSet(C, [' ', #9]);
end;

function SkipBlanks(const S: string; AFrom: Integer): Integer;
begin
  Result := AFrom;
  while (Result <= Length(S)) and IsBlank(S[Result]) do
    Inc(Result);
end;

function QuoteRun(const S: string; AAt: Integer): Integer;
begin
  Result := 0;
  while (AAt + Result <= Length(S)) and (S[AAt + Result] = '''') do
    Inc(Result);
end;

{ TRdxCodeMap }

constructor TRdxCodeMap.Create(ALines: TStrings);
var
  i, j : Integer;
begin
  inherited Create;
  FLines := ALines;
  SetLength(FClass, ALines.Count);
  SetLength(FSlash, ALines.Count);
  SetLength(FInside, ALines.Count);
  FInBrace := False;
  FInParen := False;
  FMulti   := 0;
  for i := 0 to ALines.Count - 1 do
  begin
    FInside[i] := FInBrace or FInParen or (FMulti > 0);
    FText  := ALines[i];
    FKinds := '';
    SetLength(FKinds, Length(FText));
    FInStr := False;
    j := 1;
    if FMulti > 0 then
      j := StepMultiLine;
    while j <= Length(FText) do
      if FInBrace or FInParen then
        j := StepComment(j)
      else if FInStr then
        j := StepString(j)
      else
        j := StepCode(i, j);
    FClass[i] := FKinds;
  end;
  FText  := '';
  FKinds := '';
end;

function TRdxCodeMap.StepComment(j: Integer): Integer;
begin
  FKinds[j] := 'k';
  Result := j + 1;
  if FInBrace then
  begin
    if FText[j] = '}' then FInBrace := False;
  end
  else if (FText[j] = '*') and (j < Length(FText)) and (FText[j + 1] = ')') then
  begin
    FKinds[j + 1] := 'k';
    FInParen := False;
    Result := j + 2;
  end;
end;

function TRdxCodeMap.StepString(j: Integer): Integer;
begin
  FKinds[j] := 's';
  Result := j + 1;
  if FText[j] <> '''' then Exit;
  if (j < Length(FText)) and (FText[j + 1] = '''') then
  begin
    FKinds[j + 1] := 's';   // verdoppeltes '' im String
    Result := j + 2;
  end
  else
    FInStr := False;
end;

// Ein Quote im Code: Anfang eines Strings. Eine ungerade Zahl von
// mindestens drei Quotes am Zeilenende beginnt einen mehrzeiligen String
// (Delphi 12: ''' ... ''') - der endet erst in der Zeile, die mit
// derselben Zahl Quotes beginnt.
function TRdxCodeMap.StepQuote(j: Integer): Integer;
var
  q, k : Integer;
begin
  q := QuoteRun(FText, j);
  if (q >= MIN_MULTI_QUOTES) and Odd(q)
     and (SkipBlanks(FText, j + q) > Length(FText)) then
  begin
    FMulti := q;
    for k := j to Length(FText) do
      FKinds[k] := 's';
    Exit(Length(FText) + 1);
  end;
  FKinds[j] := 's';
  FInStr := True;
  Result := j + 1;
end;

function TRdxCodeMap.StepMultiLine: Integer;
var
  k, Start : Integer;
begin
  Start := SkipBlanks(FText, 1);
  if QuoteRun(FText, Start) = FMulti then
  begin
    FMulti := 0;   // schliessende Quotes; dahinter wieder Code
    Result := Start + QuoteRun(FText, Start);
  end
  else
    Result := Length(FText) + 1;
  for k := 1 to Result - 1 do
    FKinds[k] := 's';
end;

function TRdxCodeMap.StepCode(ALineIdx, j: Integer): Integer;
var
  n, k : Integer;
begin
  n := Length(FText);
  Result := j + 1;
  if FText[j] = '''' then
    Result := StepQuote(j)
  else if (FText[j] = '/') and (j < n) and (FText[j + 1] = '/') then
  begin
    // Zeilenkommentar: der Rest der Zeile.
    FSlash[ALineIdx] := j;
    for k := j to n do
      FKinds[k] := 'k';
    Result := n + 1;
  end
  else if FText[j] = '{' then
  begin
    FKinds[j] := 'k';
    FInBrace := True;
  end
  else if (FText[j] = '(') and (j < n) and (FText[j + 1] = '*') then
  begin
    FKinds[j] := 'k';
    FKinds[j + 1] := 'k';
    FInParen := True;
    Result := j + 2;
  end
  else
    FKinds[j] := 'c';
end;

function TRdxCodeMap.LineCount: Integer;
begin
  Result := FLines.Count;
end;

function TRdxCodeMap.Raw(ALine: Integer): string;
begin
  if (ALine < 1) or (ALine > FLines.Count) then
    Exit('');
  Result := FLines[ALine - 1];
end;

function TRdxCodeMap.ClassAt(ALine, ACol: Integer): Char;
begin
  Result := ' ';
  if (ALine < 1) or (ALine > Length(FClass)) then Exit;
  if (ACol < 1) or (ACol > Length(FClass[ALine - 1])) then Exit;
  Result := FClass[ALine - 1][ACol];
end;

function TRdxCodeMap.IsCode(ALine, ACol: Integer): Boolean;
begin
  Result := ClassAt(ALine, ACol) = 'c';
end;

function TRdxCodeMap.HasComment(ALine, AFrom, ATo: Integer): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := AFrom to ATo do
    if ClassAt(ALine, i) = 'k' then
      Exit(True);
end;

function TRdxCodeMap.HasNonCode(ALine, AFrom, ATo: Integer): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := AFrom to ATo do
    if CharInSet(ClassAt(ALine, i), ['k', 's']) then
      Exit(True);
end;

function TRdxCodeMap.LineCommentCol(ALine: Integer): Integer;
begin
  Result := 0;
  if (ALine >= 1) and (ALine <= Length(FSlash)) then
    Result := FSlash[ALine - 1];
end;

function TRdxCodeMap.StartsInside(ALine: Integer): Boolean;
begin
  Result := (ALine >= 1) and (ALine <= Length(FInside)) and FInside[ALine - 1];
end;

{ TRdxToken }

function TRdxToken.IsWord: Boolean;
begin
  Result := (Low <> '') and IsIdentStart(Low[1]);
end;

function TRdxToken.EndCol: Integer;
begin
  Result := Col + Len;
end;

{ ---- Token-Lesen auf der Code-Sicht ---- }

function TokenAt(AMap: TRdxCodeMap; ALine, ACol: Integer): TRdxToken;
var
  L    : string;
  j    : Integer;
  Two  : string;
begin
  Result := Default(TRdxToken);
  Result.Line := ALine;
  Result.Col  := ACol;
  L := AMap.Raw(ALine);
  if IsIdentStart(L[ACol]) then
  begin
    j := ACol;
    while (j <= Length(L)) and IsIdentChar(L[j]) and AMap.IsCode(ALine, j) do
      Inc(j);
    Result.Len := j - ACol;
  end
  else if CharInSet(L[ACol], ['0'..'9']) then
  begin
    j := ACol;
    while (j <= Length(L)) and IsIdentChar(L[j]) do Inc(j);
    Result.Len := j - ACol;
  end
  else
  begin
    Two := Copy(L, ACol, 2);
    if ((Two = ':=') or (Two = '<>') or (Two = '<=') or (Two = '>=')
        or (Two = '..')) and AMap.IsCode(ALine, ACol + 1) then
      Result.Len := 2
    else
      Result.Len := 1;
  end;
  Result.Low := LowerCase(Copy(L, ACol, Result.Len));
end;

function NextToken(AMap: TRdxCodeMap; ALine, ACol: Integer): TRdxToken;
var
  Li, Co : Integer;
begin
  Li := ALine;
  Co := ACol;
  while Li <= AMap.LineCount do
  begin
    while Co <= Length(AMap.Raw(Li)) do
    begin
      if AMap.IsCode(Li, Co) and not IsBlank(AMap.Raw(Li)[Co]) then
        Exit(TokenAt(AMap, Li, Co));
      Inc(Co);
    end;
    Inc(Li);
    Co := 1;
  end;
  Result := Default(TRdxToken);
end;

function After(AMap: TRdxCodeMap; const ATok: TRdxToken): TRdxToken;
begin
  Result := NextToken(AMap, ATok.Line, ATok.EndCol);
end;

function TokenEndingAt(AMap: TRdxCodeMap; ALine, ACol: Integer): TRdxToken;
var
  L : string;
  S : Integer;
begin
  L := AMap.Raw(ALine);
  if IsIdentChar(L[ACol]) then
  begin
    S := ACol;
    while (S > 1) and IsIdentChar(L[S - 1]) and AMap.IsCode(ALine, S - 1) do
      Dec(S);
    Exit(TokenAt(AMap, ALine, S));
  end;
  // Zwei-Zeichen-Operator, der hier endet?
  if (ACol > 1) and AMap.IsCode(ALine, ACol - 1) then
  begin
    Result := TokenAt(AMap, ALine, ACol - 1);
    if Result.Len = 2 then Exit;
  end;
  Result := TokenAt(AMap, ALine, ACol);
end;

function PrevToken(AMap: TRdxCodeMap; ALine, ACol: Integer): TRdxToken;
var
  Li, Co : Integer;
  L      : string;
begin
  Li := ALine;
  Co := ACol - 1;
  while Li >= 1 do
  begin
    L := AMap.Raw(Li);
    if Co > Length(L) then Co := Length(L);
    while Co >= 1 do
    begin
      if AMap.IsCode(Li, Co) and not IsBlank(L[Co]) then
        Exit(TokenEndingAt(AMap, Li, Co));
      Dec(Co);
    end;
    Dec(Li);
    Co := MaxInt;
  end;
  Result := Default(TRdxToken);
end;

function Before(AMap: TRdxCodeMap; const ATok: TRdxToken): TRdxToken;
begin
  Result := PrevToken(AMap, ATok.Line, ATok.Col);
end;

function DirectiveAt(AMap: TRdxCodeMap; ALine, ACol: Integer): Boolean;
var
  L     : string;
  Slash : Integer;
begin
  L := AMap.Raw(ALine);
  Slash := AMap.LineCommentCol(ALine);
  Result := (AMap.ClassAt(ALine, ACol) = 'k')
    and ((Slash = 0) or (ACol < Slash))
    and ((Copy(L, ACol, 2) = '{$') or (Copy(L, ACol, 3) = '(*$'));
end;

function DirectiveBefore(AMap: TRdxCodeMap; AFromLine: Integer;
  const ATo: TRdxToken): Boolean;
var
  Li, Co, Last, Stop : Integer;
begin
  Result := False;
  Last := AMap.LineCount;
  if ATo.Low <> '' then
    Last := ATo.Line;
  for Li := AFromLine to Last do
  begin
    Stop := Length(AMap.Raw(Li));
    if (ATo.Low <> '') and (Li = ATo.Line) then
      Stop := ATo.Col - 1;
    for Co := 1 to Stop do
      if DirectiveAt(AMap, Li, Co) then
        Exit(True);
  end;
end;

function DirectiveInLines(AMap: TRdxCodeMap; AFrom, ATo: Integer): Boolean;
var
  Li, Co : Integer;
begin
  Result := False;
  for Li := AFrom to ATo do
    for Co := 1 to Length(AMap.Raw(Li)) do
      if DirectiveAt(AMap, Li, Co) then
        Exit(True);
end;

function DirectiveBetween(AMap: TRdxCodeMap; const APrev: TRdxToken;
  ALine, ACol: Integer): Boolean;
var
  Li, j, First, Last : Integer;
begin
  Result := False;
  First := 1;
  if APrev.Low <> '' then First := APrev.Line;
  for Li := First to ALine do
  begin
    j := 1;
    if (APrev.Low <> '') and (Li = APrev.Line) then j := APrev.EndCol;
    Last := Length(AMap.Raw(Li));
    if Li = ALine then Last := ACol - 1;
    while j <= Last do
    begin
      if DirectiveAt(AMap, Li, j) then
        Exit(True);
      Inc(j);
    end;
  end;
end;

function OpensDirective(AMap: TRdxCodeMap; ALine, ACol: Integer): Boolean;
var
  L : string;
begin
  L := AMap.Raw(ALine);
  Result := (ACol <= Length(L)) and CharInSet(L[ACol], ['{', '('])
    and DirectiveAt(AMap, ALine, ACol);
end;

// Die Spalte hinter '{$' bzw. '(*$' der Direktive an ACol.
function DirectiveBody(const L: string; ACol: Integer): Integer;
begin
  Result := ACol + Length('{$');
  if L[ACol] = '(' then
    Result := ACol + Length('(*$');
end;

function DirectiveWord(AMap: TRdxCodeMap; ALine, ACol: Integer;
  out AArg: Boolean): string;
var
  L    : string;
  i, j : Integer;
begin
  L := AMap.Raw(ALine);
  i := DirectiveBody(L, ACol);
  j := i;
  while (j <= Length(L)) and CharInSet(L[j], ['A'..'Z', 'a'..'z']) do
    Inc(j);
  Result := LowerCase(Copy(L, i, j - i));
  AArg := (j <= Length(L)) and CharInSet(L[j], [' ', #9, '''']);
end;

function DirectiveArgs(AMap: TRdxCodeMap; ALine, ACol: Integer): string;
var
  L       : string;
  i, Stop : Integer;
begin
  L := AMap.Raw(ALine);
  i := DirectiveBody(L, ACol);
  while (i <= Length(L)) and CharInSet(L[i], ['A'..'Z', 'a'..'z']) do
    Inc(i);
  if L[ACol] = '(' then
    Stop := Pos('*)', L, i)
  else
    Stop := Pos('}', L, i);
  if Stop = 0 then
    Stop := Length(L) + 1;
  Result := Copy(L, i, Stop - i);
end;

function IncludeFileAt(AMap: TRdxCodeMap; ALine, ACol: Integer): string;
var
  Arg : Boolean;
  Q   : Integer;
begin
  Result := '';
  if not InList(DirectiveWord(AMap, ALine, ACol, Arg), INCLUDE_WORDS)
     or not Arg then
    Exit;
  Result := Trim(DirectiveArgs(AMap, ALine, ACol));
  if Copy(Result, 1, 1) = '''' then
  begin
    Q := Pos('''', Result, 2);
    if Q = 0 then
      Q := Length(Result) + 1;
    Exit(Copy(Result, 2, Q - 2));
  end;
  Q := Pos(' ', Result);
  if Q > 0 then
    Result := Copy(Result, 1, Q - 1);
end;

function IncludeInLines(AMap: TRdxCodeMap; AFrom, ATo: Integer): Integer;
var
  Li, Co : Integer;
  Arg    : Boolean;
begin
  Result := 0;
  for Li := AFrom to ATo do
    for Co := 1 to Length(AMap.Raw(Li)) do
      if OpensDirective(AMap, Li, Co)
         and InList(DirectiveWord(AMap, Li, Co, Arg), INCLUDE_WORDS) and Arg then
        Exit(Li);
end;

function SameIdent(const ALow, AKey: string): Boolean;
var
  i : Integer;
begin
  Result := Length(ALow) = Length(AKey);
  i := 1;
  while Result and (i <= Length(ALow)) do
  begin
    if (ALow[i] > #127) or (AKey[i] > #127) then
      Result := (ALow[i] > #127) and (AKey[i] > #127)
    else
      Result := ALow[i] = AKey[i];
    Inc(i);
  end;
end;

function HasIdentWord(const ALowText, ALowName: string): Boolean;
var
  i, S : Integer;
begin
  Result := False;
  if ALowName = '' then Exit;
  i := 1;
  while i <= Length(ALowText) do
    if not IsIdentChar(ALowText[i]) then
      Inc(i)
    else
    begin
      S := i;
      while (i <= Length(ALowText)) and IsIdentChar(ALowText[i]) do
        Inc(i);
      if (i - S = Length(ALowName))
         and SameIdent(Copy(ALowText, S, i - S), ALowName) then
        Exit(True);
    end;
end;

// Bezeichner-Zeichen nur ASCII (HasAsciiWord).
function IsAsciiIdent(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

function HasAsciiWord(const AText, AWord: string): Boolean;
var
  P, E : Integer;
begin
  Result := False;
  P := Pos(AWord, AText);
  while P > 0 do
  begin
    E := P + Length(AWord);
    if ((P = 1) or not IsAsciiIdent(AText[P - 1]))
       and ((E > Length(AText)) or not IsAsciiIdent(AText[E])) then
      Exit(True);
    P := Pos(AWord, AText, P + 1);
  end;
end;

function LastPart(const S: string): string;
begin
  Result := Copy(S, LastDelimiter('.', S) + 1, MaxInt);
end;

function MarkerReason(const AText: string): string;
var
  Low, M : string;
begin
  Result := '';
  Low := LowerCase(AText);
  if Pos(MARKER_SUPPRESS, Low) > 0 then
    Exit('noinspection-Marker im Bereich - er unterdrueckt andere Funde');
  for M in INTENT_MARKERS do
    if HasAsciiWord(Low, M) then
      Exit(Format('%s im Bereich - ein Absichtskommentar bleibt stehen',
        [UpperCase(M)]));
  if HasAsciiWord(AText, MARKER_XXX) then
    Result := 'XXX im Bereich - ein Absichtskommentar bleibt stehen';
end;

function SameTok(const A, B: TRdxToken): Boolean;
begin
  Result := (A.Line = B.Line) and (A.Col = B.Col);
end;

function TokBefore(const A, B: TRdxToken): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Col < B.Col));
end;

function TokText(AMap: TRdxCodeMap; const T: TRdxToken): string;
begin
  Result := Copy(AMap.Raw(T.Line), T.Col, T.Len);
end;

procedure AddToken(var AList: TArray<TRdxToken>; const T: TRdxToken);
begin
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := T;
end;

function FirstOnLine(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
begin
  Result := SkipBlanks(AMap.Raw(T.Line), 1) = T.Col;
end;

function IsRoutineHeadAfter(const T, APrev: TRdxToken): Boolean;
begin
  Result := InList(T.Low, ROUTINE_WORDS) and IsKeywordAfter(T, APrev)
    and not InList(APrev.Low, NOT_HEAD_AFTER);
end;

function IsRoutineHead(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
begin
  // Erst das Wort, dann das Token davor (Before liest rueckwaerts).
  Result := InList(T.Low, ROUTINE_WORDS)
    and IsRoutineHeadAfter(T, Before(AMap, T));
end;

// Die Klammerart zu einer oeffnenden Klammer; '' fuer alles andere.
function CloserOf(const AOpenLow: string): string;
begin
  if AOpenLow = '(' then
    Result := ')'
  else if AOpenLow = '[' then
    Result := ']'
  else if AOpenLow = '<' then
    Result := '>'
  else
    Result := '';
end;

function MatchClose(AMap: TRdxCodeMap; const AOpen: TRdxToken;
  AMaxLines: Integer): TRdxToken;
var
  Close : string;
  Depth : Integer;
  T     : TRdxToken;
begin
  Result := Default(TRdxToken);
  Close := CloserOf(AOpen.Low);
  if Close = '' then Exit;
  Depth := 0;
  T := AOpen;
  // T.Line - AOpen.Line statt AOpen.Line + AMaxLines: MaxInt als Vorgabe
  // liefe sonst ueber. Die Grenze gilt VOR dem Token: das alte
  // MatchForward (uRdxSimpleFixes, bis Charge R8) verarbeitete das erste
  // Token jenseits der Grenze - in der Regel das erste der Zeile
  // AOpen.Line + MAX_REGION_LINES + 1 - noch und brach erst danach ab;
  // stand dort die schliessende Klammer, fand es sie. MatchClose bricht
  // davor ab (Richtung: weniger Angebot, kein falsches; Gegen-Review R8).
  while (T.Low <> '') and (T.Line - AOpen.Line <= AMaxLines) do
  begin
    if T.Low = AOpen.Low then
      Inc(Depth)
    else if T.Low = Close then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit(T);
    end;
    T := After(AMap, T);
  end;
end;

function AfterClose(AMap: TRdxCodeMap; const AOpen: TRdxToken): TRdxToken;
var
  Close : TRdxToken;
begin
  Result := Default(TRdxToken);
  Close := MatchClose(AMap, AOpen);
  if Close.Low <> '' then
    Result := After(AMap, Close);
end;

function ParenDelta(const T: TRdxToken): Integer;
begin
  Result := 0;
  if (T.Low = '(') or (T.Low = '[') then
    Result := 1
  else if (T.Low = ')') or (T.Low = ']') then
    Result := -1;
end;

function OneTokenReason(ALine, ACount: Integer;
  const AWhat, AManyFmt: string; const AArg: string): string;
begin
  Result := '';
  if ACount = 0 then
    Result := Format('%s auf der gemeldeten Zeile - Zeile verschoben? Datei '
      + 'neu pruefen', [AWhat])
  else if ACount > 1 then
    Result := Format('Zeile %d traegt %s - mehrdeutig',
      [ALine, Format(AManyFmt, [ACount, AArg])]);
end;

function OneTokenOnLine(AMap: TRdxCodeMap; ALine: Integer;
  const ASearch: TRdxLineSearch; out AHit: TRdxToken): string;
var
  T : TRdxToken;
  n : Integer;
begin
  AHit := Default(TRdxToken);
  n := 0;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if ASearch.Test(AMap, T, ASearch.Arg) then
    begin
      Inc(n);
      AHit := T;
    end;
    T := After(AMap, T);
  end;
  Result := OneTokenReason(ALine, n, ASearch.What, ASearch.ManyFmt);
end;

function BlockEnd(AMap: TRdxCodeMap; const AFrom: TRdxToken;
  AHook: TRdxBlockHook; out AEnd, ALast: TRdxToken): string;
var
  T, Prev : TRdxToken;
  Depth   : Integer;
begin
  Result := '';
  AEnd := Default(TRdxToken);
  ALast := Default(TRdxToken);
  Depth := 1;
  Prev := AFrom;
  T := After(AMap, AFrom);
  while T.Low <> '' do
  begin
    if IsKeywordAfter(T, Prev) and IsEndOpener(T.Low) then
      Inc(Depth)
    else if IsKeywordAfter(T, Prev) and (T.Low = 'end') then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        AEnd := T;
        ALast := Prev;
        Exit;
      end;
    end
    else if Assigned(AHook) then
    begin
      Result := AHook(AMap, T, Prev, Depth);
      if Result <> '' then Exit;
    end;
    Prev := T;
    T := After(AMap, T);
  end;
end;

function InList(const ALow: string; const AList: array of string): Boolean;
var
  S : string;
begin
  Result := False;
  for S in AList do
    if ALow = S then
      Exit(True);
end;

function IsKeywordAfter(const T, APrev: TRdxToken): Boolean;
begin
  Result := T.IsWord and not InList(APrev.Low, IDENT_PREFIXES);
end;

function IsKeywordAt(AMap: TRdxCodeMap; const T, APrev: TRdxToken): Boolean;
begin
  Result := IsKeywordAfter(T, APrev) and (After(AMap, T).Low <> ':=');
end;

function IsEndOpener(const ALow: string): Boolean;
begin
  Result := InList(ALow, END_OPENERS);
end;

function IndentStep(const AIndent, ADeeperLine: string): string;
var
  Deeper : string;
begin
  Deeper := Copy(ADeeperLine, 1, SkipBlanks(ADeeperLine, 1) - 1);
  if (Length(Deeper) > Length(AIndent))
     and (Copy(Deeper, 1, Length(AIndent)) = AIndent) then
    Exit(Copy(Deeper, Length(AIndent) + 1, MaxInt));
  Result := '  ';
  if Pos(#9, AIndent) > 0 then
    Result := #9;
end;

function ColumnFromMessage(const AMessage: string): Integer;
const
  KEY = 'at column ';
var
  p, i : Integer;
begin
  Result := 0;
  p := Pos(KEY, AMessage);
  if p = 0 then Exit;
  i := p + Length(KEY);
  while (i <= Length(AMessage)) and CharInSet(AMessage[i], ['0'..'9']) do
  begin
    Result := Result * 10 + Ord(AMessage[i]) - Ord('0');
    Inc(i);
  end;
end;

function QuotedText(const AText: string; AQuote: Char): string;
var
  P, Q : Integer;
begin
  Result := '';
  P := Pos(AQuote, AText);
  if P = 0 then Exit;
  Q := Pos(AQuote, AText, P + 1);
  if Q > P + 1 then
    Result := Copy(AText, P + 1, Q - P - 1);
end;

end.

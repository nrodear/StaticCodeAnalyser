unit uRdxBlocks;

// reDelphix - die Bausteine der Planer fuer Routinen, Klassen, Includes
// und Zeilen-Marker, OHNE ToolsAPI und ohne Parser (Code-Review reDelphix,
// Review R6-12; Charge B2S-b). Bis dahin lagen sie in der Planer-Unit
// uRdxRoutineFixes (SCA164/SCA147), und fuenf andere Planer-Units banden
// sie dafuer ein - uRdxResultFixes sogar im interface. Seitdem haengt fuer
// diese Bausteine keine Planer-Unit mehr an einer anderen, nur an
// uRdxCodeMap und hier. Die Bausteine aus uRdxRoutineFixes sind
// unveraendert umgezogen (Namen, Vertraege, Gruende); die Klassenmethoden
// heissen TRdxBlocks.X statt TRdxRoutineFixes.X. NEU in derselben Charge
// (Teil D): HeadBefore samt TRdxHeadStep (Gegen-Review R5-03) und
// MemberHeads (R5-07).
//
// BAUSTEINE (Konzept_Editorhilfen_Recherche_2026-10-11, Abschnitt 5; die
// Routinengrenzen tragen seit Charge H3c das Ende des
// Gueltigkeitsbereichs von SCA053 und spaeter SCA121/SCA196/SCA097/SCA096
// und die lokalen Variablen von SCA009/SCA001, der Finder SCA106/SCA054):
//   TRdxBlocks.ReadRoutine
//                   Routinengrenzen fuer Rumpfe jeder Groesse: Kopf (auch
//                   'class' davor, qualifizierter und generischer Name) ->
//                   Direktiven, auch auf Folgezeilen -> lokale Abschnitte
//                   (var/const/type/label ...) und lokale Routinen
//                   (rekursiv) -> begin bzw. asm -> passendes end -> ';'.
//                   forward/external: ohne Rumpf. (uRdxRaiseFixes.
//                   MethodBodyOn kennt nur leere Rumpfe ohne lokale
//                   Routinen.)
//   TRdxBlocks.HeadBefore
//                   die innerste Routine um eine Stelle: von einem Token
//                   rueckwaerts zum naechsten Routinenkopf samt Grenzen
//                   (ReadRoutine) bzw. dem Grund, oder zu einem Wort aus
//                   AStops (Teil D, R5-03; bis dahin je eine Kopie in
//                   uRdxTryFixes und uRdxResultFixes). Die Politik waehlt
//                   der Aufrufer (RoutineAround, EnclosingRoutine).
//   TRdxBlocks.FindMethodDecls / FindMethodImpls / MemberHeads
//                   Decl/Impl-Finder: die Deklarationen einer Methode auf
//                   Tiefe 1 im Rumpf ihrer Klasse (auch verschachtelte und
//                   generische Klassen) und ihre Implementierungskoepfe im
//                   implementation-Teil ('TOuter.TInner.Bar', 'TFoo<T>.Bar',
//                   'class procedure'). Mehr als ein Treffer heisst Overload
//                   oder mehrdeutig - die Aufrufer lehnen dann ab.
//                   MemberHeads: die Deklarationen in EINEM Klassenrumpf
//                   (Teil D, R5-07: der Index der Klassenkoepfe in
//                   uRdxResultFixes fragt so je Kopf, statt je Frage die
//                   ganze Datei zu lesen).
//   TRdxBlocks.FindClassHeads / HeritageOf / MethodDecl, EnclosingClass,
//   ClassEnd, TypeHasBody
//                   Klassenkopf (Charge H5, SCA096/SCA097; SCA147): die
//                   Koepfe einer Klasse mit Rumpf, ihre Vorfahrenliste, die
//                   Direktiven einer Deklaration ('override'), der Kopf um
//                   eine Deklaration samt Sichtbarkeit und das Ende des
//                   Rumpfs.
//   IncludeChainReason, AllIncludes, IncludesUpTo, IncludeSearchPath
//                   die Include-Kette (SCA164/SCA147 im Check der Tabelle,
//                   SCA014: die Compiler-Weichen der Includes).
//   MarkerAboveReason
//                   ein Zeilen-Marker ('// noinspection X') ueber einem
//                   Bereich, der seinen Code verliert (SCA053, SCA164,
//                   SCA147).
//
// ZWEI SCHREIBWEISEN (Review Woche G05-06): TRdxBlocks.X sind die
// Bausteine, die bis Charge B2S-b als TRdxRoutineFixes.X oeffentlich waren
// (ReadRoutine, die Finder, MethodDecl, FindClassHeads, HeritageOf), dazu
// die beiden Laeufe derselben Charge (HeadBefore, MemberHeads) - ihre
// Aufrufer schreiben den Praefix seitdem so. Freie Funktionen sind die
// Helfer, die dort privat waren und erst mit B2S-b oeffentlich wurden
// (HasDirective, HeadStart, IsHeadNamed, TypeHasBody, EnclosingClass,
// ClassEnd), und die Include- und Marker-Bausteine. Ein NEUER Baustein ist
// eine freie Funktion wie in uRdxCodeMap; die Klassenmethoden umzubenennen
// aenderte die Aufrufer in sechs Planer-Units und bleibt einer eigenen
// Charge.
//
// PLATTE: alles hier ist Textlogik auf der Code-Sicht, bis auf die
// Include-Kette (Gegen-Review R4-08): IncludeChainReason liest Include-
// Dateien von der Platte (dekodiert wie der Scan, uFileTextCache.
// LoadFileSmart), auf einem Netzpfad (UNC oder Netzlaufwerk,
// uRdxPaths.IsNetworkPath) nichts - der Menueaufbau laeuft im Hauptthread
// (R4-03). Bis Charge B2S-b sollte der Leser eine eigene Unit uRdxIncludes
// bekommen (Kopf von uRdxRoutineFixes); er steht jetzt bei den anderen
// Bausteinen, und jeder Plattenzugriff dieser Unit im Abschnitt
// "Include-Dateien". Von den sieben einbindenden Units brauchen ihn nur
// uRdxRoutineFixes und uRdxMagicFixes; die Grenze "Platte nur ueber den
// Check der Tabelle" haelt deshalb nur der Kommentar (Review Woche G05-09:
// uRdxIncludes bleibt der Vorschlag fuer eine eigene Charge).
//
// GRUNDSATZ wie in uRdxSimpleFixes: lieber keine Hilfe als eine falsche -
// ein Baustein nennt den Grund, warum er nicht sicher liest.

interface

uses
  System.Classes,    // TStrings (TRdxIncludeTest), TStringList (Includes)
  uRdxCodeMap;

const
  // Woerter zwischen 'class' und der Vorfahrenliste ('class abstract(TBase)',
  // 'class sealed'). Seit Charge H5c oeffentlich: uRdxResultFixes liest den
  // ersten Eintrag der Liste mit Qualifizierung (Gegen-Review H5, Minor 3).
  CLASS_MODIFIERS: array[0..1] of string = ('abstract', 'sealed');
  // Ein Marker fuer die ganze Datei ('// noinspection-file X'): er gilt
  // nicht der Zeile darunter (MarkerAboveReason); uRdxRoutineFixes sucht
  // ihn im geloeschten Bereich (MarkerLinesReason). Seit Charge B2S-b
  // oeffentlich - bis dahin teilten sich beide die Konstante in
  // uRdxRoutineFixes.
  MARKER_FILE = 'noinspection-file';
  // So viel des Kommentars nennen die Gruende zu einem Marker
  // (MarkerAboveReason hier, MarkerLinesReason in uRdxRoutineFixes).
  MARKER_QUOTE_LEN = 40;

type
  // Grenzen einer Routine (ReadRoutine) bzw. einer Methodendeklaration im
  // Klassenrumpf (dann ohne Rumpf: Body.Low = '').
  TRdxRoutine = record
    Head       : TRdxToken;        // 'class' davor oder das Kopfwort
    Keyword    : TRdxToken;        // procedure, function, constructor ...
    NameTok    : TRdxToken;        // letztes Glied des Namens
    Name       : string;           // wie im Kopf, Glieder mit '.', ohne <..>
    Parts      : TArray<string>;   // die Glieder, klein
    HeaderEnd  : TRdxToken;        // das ';' hinter dem Kopf
    Directives : TArray<string>;   // klein, in Reihenfolge
    Body       : TRdxToken;        // begin bzw. asm; Low = '' ohne Rumpf
    EndTok     : TRdxToken;        // das end des Rumpfs
    Last       : TRdxToken;        // das letzte ';' der Routine
  end;

  // Der Klassenkopf um eine Deklaration (EnclosingClass): das Token des
  // Namens, das Token 'class' und die Sichtbarkeit, unter der die
  // Deklaration auf Tiefe 1 steht ('strict private'; '' = Vorgabe ohne
  // Abschnitt). Seit Charge B2S-b oeffentlich (SCA147 fragt ihn in
  // uRdxRoutineFixes).
  TRdxClassHead = record
    NameTok  : TRdxToken;
    ClassTok : TRdxToken;
    Vis      : string;
  end;

  // Ein Schritt der Suche nach der Routine um eine Stelle
  // (TRdxBlocks.HeadBefore): ein Routinenkopf samt Grenzen bzw. dem Grund,
  // warum sie nicht sicher sind - oder ein Schluesselwort, an dem die Suche
  // endet (Stop).
  TRdxHeadStep = record
    Tok     : TRdxToken;     // das Kopfwort bzw. das Wort aus AStops
    Stop    : Boolean;       // Tok ist ein Wort aus AStops, kein Kopf
    Reason  : string;        // Kopf: '' oder der Grund (ReadRoutine)
    Routine : TRdxRoutine;   // Kopf: die Grenzen (gelesen bis zum Grund)
  end;

  // Die Bausteine mit Klassen-Namen (bis Charge B2S-b
  // TRdxRoutineFixes.ReadRoutine usw.): auf dem Puffertext ueber die
  // Code-Sicht, ohne ToolsAPI und Parser (laeuft auch im FPC-Pruefstand).
  TRdxBlocks = class
  public
    // Baustein Routinengrenzen: die Routine, deren Kopf an AHead beginnt
    // ('class' oder das Kopfwort; ein Kopfwort mit 'class' davor wird auf
    // 'class' gezogen). '' oder der Grund, warum die Grenzen nicht sicher
    // sind (Kopf ohne ';', lokaler Klassentyp, kein end, hinter dem ';'
    // beginnt nichts Neues ...).
    class function ReadRoutine(AMap: TRdxCodeMap; const AHead: TRdxToken;
      out ARoutine: TRdxRoutine): string; static;

    // Baustein "innerste Routine um eine Stelle" (Gegen-Review R5-03): von
    // T rueckwaerts - T selbst nicht - zum naechsten Routinenkopf
    // (IsRoutineHead) bzw. zum naechsten Schluesselwort aus AStops (Stop);
    // True mit AStep, und T steht auf dem gefundenen Token (der naechste
    // Aufruf sucht davor weiter); False am Dateianfang. Ein Kopf kommt mit
    // seinen Grenzen (ReadRoutine) bzw. dem Grund, warum sie nicht sicher
    // sind. Ob die Routine die Stelle umfasst und was ein unsicherer Kopf
    // heisst, entscheidet die Frage des Aufrufers - seine Politik, eine
    // kleine Huelle: uRdxHandOver.RoutineAround (Rumpf um ein Token,
    // unsichere Koepfe uebergangen, ein Abschnittswort der Unit beendet die
    // Suche) und uRdxResultFixes.EnclosingRoutine (SCA196: Rumpf um eine
    // Zeile, der erste unsichere Kopf beendet die Suche mit seinem Grund).
    // Bis Charge B2S-b lief die Suche in beiden als eigene Kopie, Token fuer
    // Token bzw. Zeile fuer Zeile. Die SQL-Vorlage fragt statt dessen ihren
    // Index aus EINEM Lauf (uRdxSqlFacts.BuildScopes): sie hat viele
    // Fragen je Lauf und einen anderen Vertrag (Kopf bis letztes ';').
    class function HeadBefore(AMap: TRdxCodeMap; var T: TRdxToken;
      const AStops: array of string; out AStep: TRdxHeadStep): Boolean;
      static;

    // Baustein Decl/Impl-Finder: die Koepfe ('class' bzw. Kopfwort) der
    // Methode AMethod auf Tiefe 1 im Rumpf jeder Klasse, die wie das letzte
    // Glied von AClassPath heisst.
    class function FindMethodDecls(AMap: TRdxCodeMap;
      const AClassPath, AMethod: string): TArray<TRdxToken>; static;
    // ... und dasselbe fuer EINEN Klassenkopf AClass (das Token 'class',
    // etwa aus FindClassHeads) - FindMethodDecls fragt so jeden seiner
    // Koepfe. Seit Charge B2S-b oeffentlich: uRdxResultFixes nimmt die
    // Koepfe aus seinem Index statt eines Laufs ueber die ganze Datei je
    // Frage (Gegen-Review R5-07).
    class function MemberHeads(AMap: TRdxCodeMap; const AClass: TRdxToken;
      const AMethod: string): TArray<TRdxToken>; static;
    // ... und ihre Implementierungskoepfe hinter 'implementation': die
    // letzten Glieder des Namens sind AClassPath + AMethod
    // ('TOuter.TInner.Bar' passt zu 'TInner' und zu 'TOuter.TInner').
    class function FindMethodImpls(AMap: TRdxCodeMap;
      const AClassPath, AMethod: string): TArray<TRdxToken>; static;
    // Eine Methodendeklaration im Klassenrumpf ab AHead (ein Kopf aus
    // FindMethodDecls): Name, Kopf und Direktiven ('override', 'overload'
    // ...). '' oder der Grund. Seit Charge H5 oeffentlich (SCA096/SCA097:
    // traegt der Konstruktor bzw. Destruktor 'override'?).
    class function MethodDecl(AMap: TRdxCodeMap; const AHead: TRdxToken;
      out ADecl: TRdxRoutine): string; static;
    // Baustein Klassenkopf (Charge H5, SCA096/SCA097): die Koepfe 'Name
    // [<..>] = [packed] class' mit Rumpf, deren Name das letzte Glied von
    // AClassPath ist - je Treffer das Token 'class' (wie FindMethodDecls:
    // mehr als einer heisst mehrdeutig).
    class function FindClassHeads(AMap: TRdxCodeMap;
      const AClassPath: string): TArray<TRdxToken>; static;
    // ... und die Namen der Vorfahrenliste hinter AClass ('class(TBase,
    // IFoo)' -> TBase, IFoo; je das letzte Glied wie im Text, ohne
    // Typargumente); leer ohne Liste ('class', 'class sealed').
    class function HeritageOf(AMap: TRdxCodeMap;
      const AClass: TRdxToken): TArray<string>; static;
  end;

// Traegt R eine der Direktiven AWords (klein)? AWord: die erste, '' ohne.
// Seit Charge H5c oeffentlich - uRdxResultFixes fragt 'override', 'overload'
// und 'abstract' (bis dahin dort als HasDirectiveWord kopiert; Gegen-Review
// H5, Minor 6).
function HasDirective(const R: TRdxRoutine; const AWords: array of string;
  out AWord: string): Boolean;

// Der Anfang des Kopfs zum Routinenwort T: 'class' davor oder T selbst.
// Nicht das 'class' eines Klassenkopfs ('TFoo = class' direkt vor dem
// ersten Member). Seit Charge B2S-b oeffentlich - uRdxRoutineFixes sucht
// damit den Kopf auf der Fundzeile (SCA164/SCA147).
function HeadStart(AMap: TRdxCodeMap; const T: TRdxToken): TRdxToken;
// Beginnt an T ein Routinenkopf, dessen Name mit AArg (klein) beginnt?
// Die Form von TRdxTokenTest (OneTokenOnLine). Seit Charge B2S-b
// oeffentlich (uRdxRoutineFixes, SCA164/SCA147).
function IsHeadNamed(AMap: TRdxCodeMap; const T: TRdxToken;
  const AArg: string): Boolean;
// Hat der Typ ab AKind (class, object, interface ...) einen Rumpf mit end?
// Nicht 'class;' (Vorwaerts), 'class of' (Metaklasse), 'class(TBase);'
// (Kurzform). Seit Charge B2S-b oeffentlich.
function TypeHasBody(AMap: TRdxCodeMap; const AKind: TRdxToken): Boolean;
// Der naechste Kopf der Klasse ALowName ueber AHead (zeilenweise
// rueckwaerts), dessen Rumpf AHead auf Tiefe 1 traegt: True mit Name,
// 'class' und Sichtbarkeit in AClass. Seit Charge B2S-b oeffentlich
// (SCA147: steht die Methode unter private?).
function EnclosingClass(AMap: TRdxCodeMap; const AHead: TRdxToken;
  const ALowName: string; out AClass: TRdxClassHead): Boolean;
// Das end des Klassenrumpfs ab AClass (dem Token 'class'); Low = ''
// ohne. Seit Charge B2S-b oeffentlich (SCA147: Include im Klassenrumpf).
function ClassEnd(AMap: TRdxCodeMap; const AClass: TRdxToken): TRdxToken;

type
  // Die Pruefung eines gelesenen Includes AFile (Zeilen und Code-Sicht):
  // '' oder der Grund. AArg ist das Argument des Aufrufers (SCA164: der
  // Name der Routine).
  TRdxIncludeTest = function(const AFile: string; ALines: TStrings;
    AMap: TRdxCodeMap; const AArg: string): string;

  // Was IncludeChainReason je Include prueft: Test mit Arg, und MissingFmt
  // fuer ein Include, das nicht zu finden oder zu lesen ist (%s die Datei,
  // %s die Ursache - 'nicht neben der Unit gefunden', 'nicht lesbar' ...).
  TRdxIncludeCheck = record
    Test       : TRdxIncludeTest;
    Arg        : string;
    MissingFmt : string;
  end;

// Die Include-Dateien AIncludes der Unit AUnitFile lesen - neben der Unit,
// ohne Endung auch mit .inc/.pas, verschachtelte Includes ebenso (bis
// MAX_INCLUDE_DEPTH) - und jede mit ACheck.Test pruefen: '' oder der erste
// Grund, auch fuer ein Include, das nicht zu finden oder zu lesen ist.
// '{$I %DATE%}' (FPC) ist keine Datei. Bis Charge Q14 nur fuer SCA164
// (IncludeReason); SCA014 prueft damit die Compiler-Weichen der Includes.
// Liegt die Unit oder ein Include im Netz (uRdxPaths.IsNetworkPath; bis
// Charge B2S-a eine eigene Regel in uRdxRoutineFixes, die '\\?\C:\..'
// fuer einen Netzpfad hielt), wird nichts gelesen: der Grund kommt ohne
// Plattenzugriff (Gegen-Review R4-03).
function IncludeChainReason(const AUnitFile: string;
  const AIncludes: TArray<string>; const ACheck: TRdxIncludeCheck): string;

// Wo das Include AFile einer Datei in ADir (Verzeichnis mit Trenner) zuerst
// gesucht wird: ein Pfad mit Laufwerk bzw. UNC wie er ist, einer ab der
// Wurzel ('\datei.inc', mORMot-Kopien im Korpus) auf dem Laufwerk von ADir,
// sonst relativ zu ADir; '' fuer einen Pfad ab der Wurzel, wenn ADir kein
// Laufwerk nennt. Bis zur Nachpruefung der Charge B1-FD suchte FileExists
// '\datei.inc' auf dem aktuellen Laufwerk des Prozesses - in der IDE
// irgendeinem, auch einem Netzlaufwerk, an dem IsNetworkPath vorbeisah.
// Oeffentlich fuer die Tests (reine Pfadrechnung, kein Plattenzugriff).
function IncludeSearchPath(const ADir, AFile: string): string;

// Die Dateien der Include-Direktiven in den Zeilen 1..ALast, der Reihe
// nach - ohne die im Kopf der Unit (s. Implementierung). SCA164/SCA147
// fragen die vor 'implementation', die Include-Kette die verschachtelten
// Includes einer gelesenen Datei. Seit Charge B2S-b oeffentlich.
function IncludesUpTo(AMap: TRdxCodeMap; ALast: Integer): TArray<string>;

// Die Dateien aller Include-Direktiven der Datei, der Reihe nach - auch die
// im Kopf der Unit (SCA014 prueft die Compiler-Weichen jedes Includes).
// Dieselbe Durchsicht wie die Includes vor implementation fuer SCA164/
// SCA147 (dort ohne Kopf); bis zur Nachpruefung der Charge B1-FD stand sie
// als zweite Kopie in uRdxMagicFixes (Gegen-Review R4-08).
function AllIncludes(AMap: TRdxCodeMap): TArray<string>;

// Zielt ein Zeilen-Marker '// noinspection X' ueber der Zeile ATop auf ATop
// oder eine Zeile dahinter? uSuppression.BuildMap gibt jedem '//'-Marker,
// auf eigener Zeile wie hinter Code, zwei Ziele: die naechste nicht leere
// Zeile und die naechste Code-Zeile (eine Zeile, die mit '//' beginnt, ist
// keine). Ab der letzten Code-Zeile ueber ATop zielt deshalb jeder Marker
// in den Bereich ab ATop; wird der geloescht, gilt der Marker still der
// naechsten Code-Zeile dahinter, und deren Funde verschwinden - das
// Spiegelbild von Gegen-Review R4-04 (Nachpruefung B1-FD: '// noinspection
// ShortVariableName' ueber 'X: Integer;' galt nach SCA053 'Y: Integer;').
// '// noinspection-file' gilt der Datei. '' oder der Grund. SCA053, SCA164
// und SCA147 fragen es fuer jeden Bereich, dessen erste Zeile ihren Code
// verliert.
function MarkerAboveReason(AMap: TRdxCodeMap; ATop: Integer): string;

implementation

uses
  System.SysUtils,
  uFileTextCache,    // LoadFileSmart: Includes dekodiert wie der Scan
  uRdxPaths;         // IsNetworkPath (Includes nie aus dem Netz)

const
  KW_CLASS = 'class';
  KW_END   = 'end';
  KW_SEMI  = ';';
  // Direktiven hinter einem Routinenkopf im implementation-Teil (Delphi und
  // FPC). Ein anderes Wort beginnt den Deklarationsteil - ist es dort
  // fremd, lehnt ReadRoutine ab.
  ROUTINE_DIRECTIVES: array[0..37] of string = ('overload', 'inline',
    'assembler', 'register', 'pascal', 'cdecl', 'stdcall', 'safecall',
    'winapi', 'varargs', 'forward', 'external', 'export', 'far', 'near',
    'local', 'deprecated', 'platform', 'experimental', 'library',
    'noreturn', 'static', 'unsafe', 'public', 'alias', 'nostackframe',
    'interrupt', 'iocheck', 'compilerproc', 'rtlproc', 'internproc',
    'mwpascal', 'cppdecl', 'oldfpccall', 'softfloat', 'hardfloat',
    'vectorcall', 'weakexternal');
  // Ohne Rumpf: der Kopf allein ist die Deklaration.
  BODYLESS_DIRECTIVES: array[0..1] of string = ('forward', 'external');
  // Direktiven einer Methodendeklaration im Klassenrumpf. 'public' fehlt
  // mit Absicht: dort beginnt es einen Abschnitt.
  METHOD_DIRECTIVES: array[0..23] of string = ('virtual', 'dynamic',
    'abstract', 'overload', 'override', 'reintroduce', 'stdcall', 'cdecl',
    'register', 'pascal', 'safecall', 'inline', 'static', 'message',
    'deprecated', 'platform', 'experimental', 'final', 'winapi',
    'assembler', 'varargs', 'dispid', 'external', 'unsafe');
  // Hier endet ein Kopf nie regulaer - ihm fehlt das ';'.
  HEAD_STOPS: array[0..8] of string = ('begin', 'asm', 'var', 'const',
    'type', 'procedure', 'function', KW_END, 'implementation');
  // Kein Inhalt eines Deklarationsteils oder Rumpfs - die Grenzen waeren
  // falsch gelesen.
  UNIT_STOPS: array[0..7] of string = ('implementation', 'initialization',
    'finalization', 'interface', 'unit', 'program', 'exports', 'uses');
  // Typen mit eigenem end, die ein Deklarationsteil nicht haben darf und
  // die ein Klassenrumpf schachtelt.
  CLASS_LIKE: array[0..3] of string = (KW_CLASS, 'object', 'interface',
    'dispinterface');
  // Damit beginnt der Rumpf einer Routine.
  BODY_WORDS: array[0..1] of string = ('begin', 'asm');
  // Was hinter einer Routine folgen darf - sonst sind ihre Grenzen falsch
  // gelesen (Dateiende zaehlt auch).
  FOLLOWERS: array[0..17] of string = ('procedure', 'function',
    'constructor', 'destructor', 'operator', KW_CLASS, 'var', 'const',
    'type', 'label', 'resourcestring', 'threadvar', 'exports',
    'initialization', 'finalization', 'begin', 'asm', KW_END);
  VISIBILITY_WORDS: array[0..4] of string = ('private', 'protected',
    'public', 'published', 'automated');
  // Hinter diesen Woertern ist ein Wort ein Feld, kein Abschnitt bzw.
  // keine Direktive ('Public: Boolean', 'Platform: string').
  FIELD_MARKS: array[0..2] of string = (':', ',', '=');
  MAX_NESTING    = 8;     // Tiefe lokaler Routinen in Routinen
  MAX_NAME_PARTS = 8;     // Glieder eines qualifizierten Namens
  // Ursache fuer MissingFmt: Unit oder Include auf einem Netzpfad (R4-03).
  R_INC_NETWORK = 'auf einem Netzpfad (%s) - nicht gelesen, der Menueaufbau '
    + 'laeuft im Hauptthread';
  // SCA053/SCA164/SCA147: ein Zeilen-Marker ueber dem Bereich, der in ihn
  // zielt (MarkerAboveReason; uSuppression.ParseCommentText: der Kommentar
  // beginnt mit dem Wort).
  MARKER_LINE = 'noinspection';
  R_MARKER_ABOVE = 'der Marker "%s" in Zeile %d zielt auf die geloeschte '
    + 'Zeile und gaelte danach still der naechsten Code-Zeile; von Hand '
    + 'loeschen';
  MAX_INCLUDE_DEPTH = 4;
  INCLUDE_EXTENSIONS: array[0..1] of string = ('.inc', '.pas');
  // Folgt eines davon einem Include, steht es im Kopf der Unit
  // (IncludesUpTo).
  HEADER_FOLLOWERS: array[0..2] of string = ('unit', 'interface', 'uses');

type
  // Tiefe und Sichtbarkeit beim Lauf durch einen Klassenrumpf (Tiefe 1 =
  // die Member der Klasse; geschachtelte Typen und records zaehlen hoch).
  // Das Geruest des Laufs (Start, Active, Advance) steht hier EINMAL - bis
  // Review Woche G05-08 schrieben ClassEnd, VisibilityAt und AddMemberHeads
  // Vorbelegung, Abbruch und Vorruecken je selbst aus:
  //   Scan.Start(AMap, AClass, T, P);
  //   while Scan.Active(T) do begin <Aktion an T>; Scan.Advance(AMap, T, P); end;
  TRdxClassScan = record
    Depth : Integer;
    Vis   : string;      // Sichtbarkeit auf Tiefe 1, '' = Vorgabe
    // Tiefe 1 ohne Sichtbarkeit; T das erste Token hinter AClass (dem
    // Token 'class'), P das davor (AClass).
    procedure Start(AMap: TRdxCodeMap; const AClass: TRdxToken;
      out T, P: TRdxToken);
    // Noch im Rumpf: T ist ein Token und die Tiefe nicht 0.
    function Active(const T: TRdxToken): Boolean;
    // T verarbeiten (Step) und vorruecken: P wird T, T das Token dahinter.
    procedure Advance(AMap: TRdxCodeMap; var T, P: TRdxToken);
    procedure Step(AMap: TRdxCodeMap; const T, APrev: TRdxToken);
  end;

  // Der Deklarationsteil einer Routine (ReadDeclPart): offene record-Typen
  // und die Schachtelung der Routine.
  TRdxDeclScan = record
    Rec    : Integer;
    Depth  : Integer;
    Reason : string;
    function Step(AMap: TRdxCodeMap; var T: TRdxToken;
      const APrev: TRdxToken): TRdxStep;
  end;

// 'TOuter.TInner' -> ['touter', 'tinner'].
function SplitDotted(const S: string): TArray<string>;
var
  Rest : string;
  P    : Integer;
begin
  Result := nil;
  Rest := LowerCase(S);
  P := Pos('.', Rest);
  while P > 0 do
  begin
    AddText(Result, Copy(Rest, 1, P - 1));
    Rest := Copy(Rest, P + 1, MaxInt);
    P := Pos('.', Rest);
  end;
  AddText(Result, Rest);
end;

function HasDirective(const R: TRdxRoutine; const AWords: array of string;
  out AWord: string): Boolean;
var
  D : string;
begin
  Result := False;
  AWord := '';
  for D in R.Directives do
    if InList(D, AWords) then
    begin
      AWord := D;
      Exit(True);
    end;
end;

// Das naechste ';' auf Klammertiefe 0 ab AFrom (einschliesslich); Low = ''
// sonst.
function SemicolonAt0(AMap: TRdxCodeMap; const AFrom: TRdxToken): TRdxToken;
begin
  Result := AFrom;
  while (Result.Low <> '') and (Result.Low <> KW_SEMI) do
    if (Result.Low = '(') or (Result.Low = '[') then
      Result := AfterClose(AMap, Result)
    else
      Result := After(AMap, Result);
end;

// Ein Kopf, dessen Name mit AArg (klein) beginnt - fuer OneTokenOnLine.
function IsHeadNamed(AMap: TRdxCodeMap; const T: TRdxToken;
  const AArg: string): Boolean;
begin
  Result := IsRoutineHead(AMap, T) and SameIdent(After(AMap, T).Low, AArg);
end;

// Der Anfang des Kopfs zum Routinenwort T: 'class' davor oder T selbst.
// Nicht das 'class' eines Klassenkopfs ('TFoo = class' direkt vor dem
// ersten Member).
function HeadStart(AMap: TRdxCodeMap; const T: TRdxToken): TRdxToken;
begin
  Result := Before(AMap, T);
  if (Result.Low <> KW_CLASS)
     or InList(Before(AMap, Result).Low, ['=', 'packed']) then
    Result := T;
end;

// Steht hinter dem Routinenwort T ein ':=' - eine Zuweisung an eine
// Variable 'Operator' (kein reserviertes Wort; uUnusedRoutine kennt den
// Bezeichner aus dem Korpus), kein Kopf? Wie IsKeywordAt, mit einer
// Ausnahme: FPC kennt den Kopf 'operator := (A: T) R: U;' (der
// Zuweisungsoperator) - vor einer '(' bleibt es ein Kopf. Bis Review Woche
// G05-07 galt jede Zuweisung 'Operator := ..' hinter ';' als Routinenkopf
// im Rumpf, und ReadRoutine sperrte die ganze Routine.
function AssignsTo(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
var
  N : TRdxToken;
begin
  N := After(AMap, T);
  Result := (N.Low = ':=') and (After(AMap, N).Low <> '(');
end;

{ ---- Baustein Routinengrenzen ---- }

function ReadRoutineAt(AMap: TRdxCodeMap; const AHead: TRdxToken;
  ADepth: Integer; out R: TRdxRoutine): string; forward;

// Der Name hinter dem Kopfwort: Glieder mit '.', Typparameter '<..>'
// uebersprungen; AAfter ist das Token dahinter. '' oder der Grund.
function ReadName(AMap: TRdxCodeMap; var R: TRdxRoutine;
  out AAfter: TRdxToken): string;
var
  T   : TRdxToken;
  Raw : TArray<string>;
  n   : Integer;
begin
  AAfter := Default(TRdxToken);
  Raw := nil;
  T := After(AMap, R.Keyword);
  for n := 1 to MAX_NAME_PARTS do
  begin
    if not T.IsWord then
      Exit(Format('kein Name hinter "%s"', [R.Keyword.Low]));
    R.NameTok := T;
    AddText(R.Parts, T.Low);
    AddText(Raw, TokText(AMap, T));
    T := After(AMap, T);
    if T.Low = '<' then
      T := AfterClose(AMap, T);
    if T.Low <> '.' then
    begin
      R.Name := JoinStrings(Raw, '.');   // Glieder zu 'A.B.C'
      AAfter := T;
      Exit('');
    end;
    T := After(AMap, T);
  end;
  Result := 'Name mit zu vielen Gliedern';
end;

// Ab AFrom (hinter dem Namen) Typparameter, Parameter und Rueckgabe bis zum
// ';' des Kopfs. '' oder der Grund.
function HeaderEndFrom(AMap: TRdxCodeMap; const AFrom: TRdxToken;
  out AEnd: TRdxToken): string;
var
  T, P : TRdxToken;
begin
  AEnd := Default(TRdxToken);
  T := AFrom;
  P := Before(AMap, AFrom);
  while (T.Low <> '') and (T.Low <> KW_SEMI) do
  begin
    if IsKeywordAfter(T, P) and InList(T.Low, HEAD_STOPS) then
      Break;
    P := T;
    if InList(T.Low, ['(', '[', '<']) then
      T := AfterClose(AMap, T)
    else
      T := After(AMap, T);
  end;
  if T.Low <> KW_SEMI then
    Exit('Ende des Kopfs nicht gefunden');
  AEnd := T;
  Result := '';
end;

// Ein Wort aus AList an T ist eine Direktive - ausser ein ':' ',' '='
// folgt (ein Feld 'Platform: string' hinter der Deklaration).
function IsDirectiveAt(AMap: TRdxCodeMap; const T: TRdxToken;
  const AList: array of string): Boolean;
begin
  Result := T.IsWord and InList(T.Low, AList)
    and not InList(After(AMap, T).Low, FIELD_MARKS);
end;

// Ab T je ein Wort aus AList bis zu seinem ';' (wird R.Last); T wird das
// Token hinter der letzten Direktive. '' oder der Grund.
function DirectiveRun(AMap: TRdxCodeMap; var R: TRdxRoutine;
  const AList: array of string; var T: TRdxToken): string;
var
  S : TRdxToken;
begin
  Result := '';
  while IsDirectiveAt(AMap, T, AList) do
  begin
    AddText(R.Directives, T.Low);
    S := SemicolonAt0(AMap, T);
    if S.Low = '' then
      Exit(Format('Direktive "%s" ohne ";"', [T.Low]));
    R.Last := S;
    T := After(AMap, S);
  end;
end;

// Die Direktiven hinter dem Kopf ('overload; inline;', 'external ''x''
// name ''y'';'), auch auf Folgezeilen: je ein Wort aus AList bis zu seinem
// ';'. R.Last wird das letzte ';', AAfter das Token dahinter.
function ReadDirectives(AMap: TRdxCodeMap; var R: TRdxRoutine;
  const AList: array of string; out AAfter: TRdxToken): string;
begin
  R.Last := R.HeaderEnd;
  AAfter := After(AMap, R.HeaderEnd);
  Result := DirectiveRun(AMap, R, AList, AAfter);
end;

// FPC-Direktiven in eckigen Klammern hinter dem Kopf ('procedure Foo;
// [public, alias: ''FOO_C''];', Gegen-Review H3, Minor 4): die Woerter in
// der Klammer werden Direktiven, R.Last das ';' dahinter, AAfter das Token
// danach. Ohne sie las ReadDeclPart die Klammer als Deklarationsteil, und
// eine per alias von aussen erreichbare Routine bekam die Hilfe. '' oder
// der Grund.
function ReadModifierBracket(AMap: TRdxCodeMap; var R: TRdxRoutine;
  const AOpen: TRdxToken; out AAfter: TRdxToken): string;
var
  T, Close, S : TRdxToken;
begin
  AAfter := Default(TRdxToken);
  Close := MatchClose(AMap, AOpen);
  if Close.Low = '' then
    Exit('FPC-Direktiven "[" ohne "]"');
  T := After(AMap, AOpen);
  while (T.Low <> '') and not SameTok(T, Close) do
  begin
    if T.IsWord then
      AddText(R.Directives, T.Low);
    T := After(AMap, T);
  end;
  S := After(AMap, Close);
  if S.Low <> KW_SEMI then
    Exit('FPC-Direktiven "[..]" ohne ";"');
  R.Last := S;
  AAfter := After(AMap, S);
  Result := '';
end;

// Die Direktiven hinter einem Kopf im implementation-Teil: Woerter
// (ReadDirectives) und FPC-Klammern (ReadModifierBracket), auch im Wechsel.
// AAfter ist das erste Token des Deklarationsteils. Nur hier, nicht im
// Klassenrumpf: dort beginnt '[' das Attribut des naechsten Members.
function ReadRoutineDirectives(AMap: TRdxCodeMap; var R: TRdxRoutine;
  out AAfter: TRdxToken): string;
var
  Open : TRdxToken;
begin
  Result := ReadDirectives(AMap, R, ROUTINE_DIRECTIVES, AAfter);
  while (Result = '') and (AAfter.Low = '[') do
  begin
    Open := AAfter;
    Result := ReadModifierBracket(AMap, R, Open, AAfter);
    if Result = '' then
      Result := DirectiveRun(AMap, R, ROUTINE_DIRECTIVES, AAfter);
  end;
end;

// Eine lokale Routine ab T (Kopfwort hinter ';'): T wird ihr letztes ';'.
// '' oder der Grund.
function SkipLocalRoutine(AMap: TRdxCodeMap; var T: TRdxToken;
  ADepth: Integer): string;
var
  Sub : TRdxRoutine;
begin
  if ADepth >= MAX_NESTING then
    Exit('lokale Routinen zu tief verschachtelt');
  Result := ReadRoutineAt(AMap, T, ADepth + 1, Sub);
  if Result <> '' then
    Exit('lokale Routine ' + Sub.Name + ': ' + Result);
  T := Sub.Last;
end;

// Ein Schluesselwort im Deklarationsteil ausserhalb von records und
// lokalen Routinen: rsFound am Rumpf, rsStop mit Grund.
function DeclWordStep(const T, APrev: TRdxToken; out AReason: string): TRdxStep;
begin
  AReason := '';
  Result := rsGoOn;
  if InList(T.Low, BODY_WORDS) then
    Result := rsFound
  else if InList(T.Low, CLASS_LIKE) and (APrev.Low = '=') then
    AReason := 'lokaler Klassen- oder Objekttyp - Grenzen nicht sicher'
  else if (T.Low = KW_END) or InList(T.Low, UNIT_STOPS) then
    AReason := Format('"%s" im Deklarationsteil - Ende der Routine nicht '
      + 'sicher', [T.Low]);
  if AReason <> '' then
    Result := rsStop;
end;

{ TRdxDeclScan }

// Ein Schluesselwort des Deklarationsteils. 'case' im record hat kein
// eigenes end; ein Routinenwort hinter ';' (nicht hinter ':' oder '=' wie
// in 'P: procedure;') ist eine lokale Routine.
function TRdxDeclScan.Step(AMap: TRdxCodeMap; var T: TRdxToken;
  const APrev: TRdxToken): TRdxStep;
begin
  Result := rsGoOn;
  if T.Low = 'record' then
    Inc(Rec)
  else if Rec > 0 then
    Dec(Rec, Ord(T.Low = KW_END))
  else if InList(T.Low, ROUTINE_WORDS) and (APrev.Low = KW_SEMI) then
  begin
    Reason := SkipLocalRoutine(AMap, T, Depth);
    if Reason <> '' then
      Result := rsStop;
  end
  else
    Result := DeclWordStep(T, APrev, Reason);
end;

// Der Deklarationsteil ab AFrom (hinter Kopf und Direktiven): lokale
// Abschnitte und Routinen bis zum begin bzw. asm des Rumpfs (R.Body).
function ReadDeclPart(AMap: TRdxCodeMap; var R: TRdxRoutine;
  const AFrom: TRdxToken; ADepth: Integer): string;
var
  T, P : TRdxToken;
  Scan : TRdxDeclScan;
  Step : TRdxStep;
begin
  Scan := Default(TRdxDeclScan);
  Scan.Depth := ADepth;
  T := AFrom;
  P := R.Last;
  while T.Low <> '' do
  begin
    Step := rsGoOn;
    if IsKeywordAfter(T, P) then
      Step := Scan.Step(AMap, T, P);
    if Step = rsFound then
    begin
      R.Body := T;
      Exit('');
    end;
    if Step = rsStop then
      Exit(Scan.Reason);
    P := T;
    T := After(AMap, T);
  end;
  Result := 'kein Rumpf zur Routine gefunden';
end;

// Haken der end-Bilanz im Rumpf: Abschnittswoerter der Unit und ein
// Routinenkopf hinter ';' heissen, das passende end wurde verfehlt. Eine
// Zuweisung 'Operator := ..' ist kein Kopf (AssignsTo).
function BodyHook(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  ADepth: Integer): string;
begin
  Result := '';
  if not IsKeywordAfter(T, APrev) then Exit;
  if InList(T.Low, UNIT_STOPS) then
    Result := Format('"%s" im Rumpf - Ende der Routine nicht gefunden',
      [T.Low])
  else if (APrev.Low = KW_SEMI)
     and (InList(T.Low, ROUTINE_WORDS) or (T.Low = KW_CLASS))
     and not AssignsTo(AMap, T) then
    Result := 'Routinenkopf im Rumpf - Ende der Routine nicht sicher';
end;

// Das end eines asm-Rumpfs: das erste end als Schluesselwort ('@@End' und
// '@End' sind Marken).
function AsmEnd(AMap: TRdxCodeMap; const AAsm: TRdxToken;
  out AEnd: TRdxToken): string;
var
  T, P : TRdxToken;
begin
  AEnd := Default(TRdxToken);
  P := AAsm;
  T := After(AMap, AAsm);
  while (T.Low <> '') and not (IsKeywordAfter(T, P) and (T.Low = KW_END)) do
  begin
    P := T;
    T := After(AMap, T);
  end;
  if T.Low = '' then
    Exit('kein end zum asm-Rumpf');
  AEnd := T;
  Result := '';
end;

// Rumpf ab R.Body bis zum passenden end und dem ';' dahinter (R.Last).
function ReadBody(AMap: TRdxCodeMap; var R: TRdxRoutine): string;
var
  Last, S : TRdxToken;
begin
  if R.Body.Low = 'asm' then
    Result := AsmEnd(AMap, R.Body, R.EndTok)
  else
    Result := BlockEnd(AMap, R.Body, BodyHook, R.EndTok, Last);
  if (Result = '') and (R.EndTok.Low = '') then
    Result := 'kein end zum Rumpf gefunden';
  if Result <> '' then Exit;
  S := After(AMap, R.EndTok);
  // FPC: 'end [''eax''];' hinter einem asm-Rumpf.
  if S.Low = '[' then
    S := AfterClose(AMap, S);
  if S.Low <> KW_SEMI then
    Exit('hinter dem end des Rumpfs fehlt ";"');
  R.Last := S;
end;

// Beginnt hinter ALast etwas, das hinter einer Routine stehen darf?
function FollowsRoutine(AMap: TRdxCodeMap; const ALast: TRdxToken): Boolean;
var
  N : TRdxToken;
begin
  N := After(AMap, ALast);
  Result := (N.Low = '') or (N.Low = '[') or InList(N.Low, FOLLOWERS);
end;

function ReadRoutineAt(AMap: TRdxCodeMap; const AHead: TRdxToken;
  ADepth: Integer; out R: TRdxRoutine): string;
var
  T : TRdxToken;
  W : string;
begin
  R := Default(TRdxRoutine);
  R.Head := AHead;
  R.Keyword := AHead;
  if AHead.Low = KW_CLASS then
    R.Keyword := After(AMap, AHead);
  if not InList(R.Keyword.Low, ROUTINE_WORDS) then
    Exit('kein Routinenkopf');
  Result := ReadName(AMap, R, T);
  if Result = '' then
    Result := HeaderEndFrom(AMap, T, R.HeaderEnd);
  if Result = '' then
    Result := ReadRoutineDirectives(AMap, R, T);
  if (Result <> '') or HasDirective(R, BODYLESS_DIRECTIVES, W) then Exit;
  Result := ReadDeclPart(AMap, R, T, ADepth);
  if Result = '' then
    Result := ReadBody(AMap, R);
  if (Result = '') and not FollowsRoutine(AMap, R.Last) then
    Result := 'hinter der Routine beginnt nichts Neues - ihr Ende ist nicht '
      + 'sicher';
end;

{ ---- Zeilen-Marker ueber einem Bereich (SCA053, SCA164, SCA147) ---- }

// Der Zeilen-Marker der Zeile ALine: ihr '//'-Kommentar (aus Code heraus),
// wenn er mit 'noinspection' beginnt wie bei uSuppression.ParseCommentText,
// aber nicht 'noinspection-file' (der gilt der Datei) - gekuerzt fuer den
// Grund; sonst ''.
function LineMarkerAt(AMap: TRdxCodeMap; ALine: Integer): string;
var
  Slash   : Integer;
  Comment : string;
begin
  Result := '';
  Slash := AMap.LineCommentCol(ALine);
  if Slash = 0 then Exit;
  Comment := LowerCase(TrimLeft(Copy(AMap.Raw(ALine), Slash + Length('//'),
    MaxInt)));
  if (Copy(Comment, 1, Length(MARKER_LINE)) = MARKER_LINE)
     and (Copy(Comment, 1, Length(MARKER_FILE)) <> MARKER_FILE) then
    Result := TrimRight(Copy(AMap.Raw(ALine), Slash, MARKER_QUOTE_LEN));
end;

// Rueckwaerts ab ATop - 1 ueber Leerzeilen und Zeilen, die mit '//'
// beginnen, bis einschliesslich der ersten Code-Zeile: genau dort steht
// ein Marker, dessen naechste Code-Zeile ATop oder eine dahinter ist (s.
// Interface; die Zielsuche von BuildMap liest den Rohtext so).
function MarkerAboveReason(AMap: TRdxCodeMap; ATop: Integer): string;
var
  Li        : Integer;
  S, Marker : string;
begin
  Result := '';
  Li := ATop - 1;
  while Li >= 1 do
  begin
    S := TrimLeft(AMap.Raw(Li));
    if S <> '' then
    begin
      Marker := LineMarkerAt(AMap, Li);
      if Marker <> '' then
        Exit(Format(R_MARKER_ABOVE, [Marker, Li]));
      if Copy(S, 1, Length('//')) <> '//' then
        Exit;
    end;
    Dec(Li);
  end;
end;

{ ---- Include-Direktiven der Datei ---- }

// Die Dateien der Include-Direktiven in den Zeilen 1..ALast, der Reihe
// nach - ohne die, hinter denen eines der Woerter ASkipBefore folgt (die
// eine Durchsicht fuer IncludesUpTo und AllIncludes).
function IncludesWhere(AMap: TRdxCodeMap; ALast: Integer;
  const ASkipBefore: array of string): TArray<string>;
var
  Li, Co : Integer;
  F      : string;
begin
  Result := nil;
  for Li := 1 to ALast do
    for Co := 1 to Length(AMap.Raw(Li)) do
      if OpensDirective(AMap, Li, Co) then
      begin
        F := IncludeFileAt(AMap, Li, Co);
        if (F <> '')
           and not InList(NextToken(AMap, Li, Co).Low, ASkipBefore) then
          AddText(Result, F);
      end;
end;

// Die Dateien der Include-Direktiven in den Zeilen 1..ALast, der Reihe
// nach - ohne die im Kopf der Unit: folgt einem Include 'unit', 'interface'
// oder 'uses', darf es nur tragen, was davor stehen darf, Direktiven und
// Kommentare (eine Deklaration davor waere ein Fehler - uses ist die erste
// Klausel, E2029). Es kann die Routine weder deklarieren noch rufen; so
// stehen die Konfigurations-Includes 'jcl.inc', 'jvcl.inc', 'CnWizards.inc'
// (Korpus: im Kopf, meist in einem anderen Verzeichnis als die Unit).
function IncludesUpTo(AMap: TRdxCodeMap; ALast: Integer): TArray<string>;
begin
  Result := IncludesWhere(AMap, ALast, HEADER_FOLLOWERS);
end;

function AllIncludes(AMap: TRdxCodeMap): TArray<string>;
begin
  Result := IncludesWhere(AMap, AMap.LineCount, []);
end;

{ ---- Klassenkopf und Methodendeklaration ---- }

// Die Deklaration ab AHead im Klassenrumpf: ein Glied als Name, Kopf bis
// ';', Direktiven (METHOD_DIRECTIVES). '' oder der Grund.
function ReadMethodDecl(AMap: TRdxCodeMap; const AHead: TRdxToken;
  out D: TRdxRoutine): string;
var
  T : TRdxToken;
begin
  D := Default(TRdxRoutine);
  D.Head := AHead;
  D.Keyword := AHead;
  if AHead.Low = KW_CLASS then
    D.Keyword := After(AMap, AHead);
  Result := ReadName(AMap, D, T);
  if (Result = '') and (Length(D.Parts) > 1) then
    Result := 'Methodenaufloesung (IFoo.X = Y) - keine eigene Methode';
  if Result = '' then
    Result := HeaderEndFrom(AMap, T, D.HeaderEnd);
  if Result = '' then
    Result := ReadDirectives(AMap, D, METHOD_DIRECTIVES, T);
end;

// Hat der Typ ab AKind (class, object, interface ...) einen Rumpf mit end?
// Nicht 'class;' (Vorwaerts), 'class of' (Metaklasse), 'class(TBase);'
// (Kurzform).
function TypeHasBody(AMap: TRdxCodeMap; const AKind: TRdxToken): Boolean;
var
  N : TRdxToken;
begin
  N := After(AMap, AKind);
  while InList(N.Low, CLASS_MODIFIERS) do
    N := After(AMap, N);
  if N.Low = '(' then
    N := AfterClose(AMap, N);
  Result := not InList(N.Low, [KW_SEMI, 'of', '']);
end;

// 'AName [<..>] = [packed] class' mit Rumpf an T; AClass ist das Token
// 'class'.
function ClassHeadAt(AMap: TRdxCodeMap; const T: TRdxToken;
  const ALowName: string; out AClass: TRdxToken): Boolean;
var
  N : TRdxToken;
begin
  Result := False;
  AClass := Default(TRdxToken);
  if not SameIdent(T.Low, ALowName) or not IsKeywordAfter(T, Before(AMap, T)) then
    Exit;
  N := After(AMap, T);
  if N.Low = '<' then
    N := AfterClose(AMap, N);
  if N.Low <> '=' then Exit;
  AClass := After(AMap, N);
  if AClass.Low = 'packed' then
    AClass := After(AMap, AClass);
  Result := (AClass.Low = KW_CLASS) and TypeHasBody(AMap, AClass);
end;

{ TRdxClassScan }

// Ein Token im Klassenrumpf: end schliesst, record und geschachtelte Typen
// mit Rumpf oeffnen; auf Tiefe 1 setzt ein Abschnittswort die
// Sichtbarkeit ('strict private'). 'case' im record hat kein eigenes end.
procedure TRdxClassScan.Step(AMap: TRdxCodeMap; const T, APrev: TRdxToken);
begin
  if not IsKeywordAfter(T, APrev) then Exit;
  if T.Low = KW_END then
    Dec(Depth)
  else if T.Low = 'record' then
    Inc(Depth)
  else if InList(T.Low, CLASS_LIKE) and InList(APrev.Low, ['=', 'packed'])
     and TypeHasBody(AMap, T) then
    Inc(Depth)
  else if (Depth = 1) and InList(T.Low, VISIBILITY_WORDS)
     and not InList(After(AMap, T).Low, FIELD_MARKS) then
  begin
    Vis := T.Low;
    if APrev.Low = 'strict' then
      Vis := 'strict ' + Vis;
  end;
end;

procedure TRdxClassScan.Start(AMap: TRdxCodeMap; const AClass: TRdxToken;
  out T, P: TRdxToken);
begin
  Depth := 1;
  Vis := '';
  P := AClass;
  T := After(AMap, AClass);
end;

function TRdxClassScan.Active(const T: TRdxToken): Boolean;
begin
  Result := (T.Low <> '') and (Depth > 0);
end;

procedure TRdxClassScan.Advance(AMap: TRdxCodeMap; var T, P: TRdxToken);
begin
  Step(AMap, T, P);
  P := T;
  T := After(AMap, T);
end;

// Das end des Klassenrumpfs ab AClass; Low = '' ohne. Das end ist das
// Token, das die Tiefe auf 0 brachte - nach dem letzten Advance steht es
// in P.
function ClassEnd(AMap: TRdxCodeMap; const AClass: TRdxToken): TRdxToken;
var
  Scan : TRdxClassScan;
  T, P : TRdxToken;
begin
  Result := Default(TRdxToken);
  Scan := Default(TRdxClassScan);
  Scan.Start(AMap, AClass, T, P);
  while Scan.Active(T) do
    Scan.Advance(AMap, T, P);
  if Scan.Depth = 0 then
    Result := P;
end;

// Die Sichtbarkeit, unter der AHead im Rumpf ab AClass auf Tiefe 1 steht;
// False, wenn AHead nicht dort steht.
function VisibilityAt(AMap: TRdxCodeMap; const AClass, AHead: TRdxToken;
  out AVis: string): Boolean;
var
  Scan : TRdxClassScan;
  T, P : TRdxToken;
begin
  Result := False;
  AVis := '';
  Scan := Default(TRdxClassScan);
  Scan.Start(AMap, AClass, T, P);
  while Scan.Active(T) do
  begin
    if SameTok(T, AHead) then
    begin
      AVis := Scan.Vis;
      Exit(Scan.Depth = 1);
    end;
    Scan.Advance(AMap, T, P);
  end;
end;

// Die Koepfe der Methode ALowName auf Tiefe 1 des Rumpfs ab AClass.
procedure AddMemberHeads(AMap: TRdxCodeMap; const AClass: TRdxToken;
  const ALowName: string; var AHeads: TArray<TRdxToken>);
var
  Scan : TRdxClassScan;
  T, P : TRdxToken;
begin
  Scan := Default(TRdxClassScan);
  Scan.Start(AMap, AClass, T, P);
  while Scan.Active(T) do
  begin
    if (Scan.Depth = 1) and IsHeadNamed(AMap, T, ALowName) then
      AddToken(AHeads, HeadStart(AMap, T));
    Scan.Advance(AMap, T, P);
  end;
end;

// Der naechste Kopf der Klasse ALowName ueber AHead (zeilenweise
// rueckwaerts), dessen Rumpf AHead auf Tiefe 1 traegt.
function EnclosingClass(AMap: TRdxCodeMap; const AHead: TRdxToken;
  const ALowName: string; out AClass: TRdxClassHead): Boolean;
var
  Li : Integer;
  T  : TRdxToken;
begin
  AClass := Default(TRdxClassHead);
  for Li := AHead.Line downto 1 do
  begin
    T := NextToken(AMap, Li, 1);
    while (T.Low <> '') and (T.Line = Li) and TokBefore(T, AHead) do
    begin
      if ClassHeadAt(AMap, T, ALowName, AClass.ClassTok) then
      begin
        AClass.NameTok := T;
        Exit(VisibilityAt(AMap, AClass.ClassTok, AHead, AClass.Vis));
      end;
      T := After(AMap, T);
    end;
  end;
  Result := False;
end;

// Die Namen der Vorfahrenliste 'class(TBase, IFoo, Unit.IBar)' (wie im
// Text, je das letzte Glied, ohne Typargumente).
function HeritageNames(AMap: TRdxCodeMap; const AClass: TRdxToken): TArray<string>;
var
  T, Close : TRdxToken;
  Last     : string;
begin
  Result := nil;
  T := After(AMap, AClass);
  while InList(T.Low, CLASS_MODIFIERS) do
    T := After(AMap, T);
  if T.Low <> '(' then Exit;
  Close := MatchClose(AMap, T);
  Last := '';
  T := After(AMap, T);
  while (T.Low <> '') and not SameTok(T, Close) do
  begin
    if T.Low = '<' then
      T := MatchClose(AMap, T)
    else if T.Low = ',' then
    begin
      AddText(Result, Last);
      Last := '';
    end
    else if T.IsWord then
      Last := TokText(AMap, T);
    if T.Low <> '' then
      T := After(AMap, T);
  end;
  if Last <> '' then
    AddText(Result, Last);
end;

{ ---- Include-Dateien: die Kette (SCA164/SCA147 vor implementation,
  SCA014 alle) - die einzigen Plattenzugriffe der Unit ---- }

// Der Teil von APath, der ihn zum Netzpfad macht ('\\server\share' bzw.
// 'Z:'), fuer den Grund.
function NetworkRoot(const APath: string): string;
begin
  Result := ExtractFileDrive(APath);
  if Result = '' then
    Result := APath;
end;

function IncludeSearchPath(const ADir, AFile: string): string;
begin
  if ExtractFileDrive(AFile) <> '' then
    Result := AFile
  else if (AFile <> '') and CharInSet(AFile[1], ['\', '/']) then
  begin
    Result := ExtractFileDrive(ADir);
    if Result <> '' then
      Result := Result + AFile;
  end
  else
    Result := ADir + AFile;
end;

// Die Datei AFile eines Includes, gesucht wie IncludeSearchPath (relativ zu
// ADir, Verzeichnis mit Trenner); ohne Endung auch mit .inc bzw. .pas wie
// die Compiler. '' wenn keine da ist.
function IncludePath(const ADir, AFile: string): string;
var
  Ext : string;
begin
  Result := IncludeSearchPath(ADir, AFile);
  if Result = '' then Exit;
  if FileExists(Result) then Exit;
  if ExtractFileExt(AFile) = '' then
    for Ext in INCLUDE_EXTENSIONS do
      if FileExists(Result + Ext) then
        Exit(Result + Ext);
  Result := '';
end;

// IncludePath, und fuer '\datei.inc' (mORMot-Kopien im Korpus) auch die
// Datei neben der Unit - gelesen wird nur, was da ist; was der Compiler
// nimmt, haengt am Suchpfad.
function FindInclude(const ADir, AFile: string): string;
begin
  Result := IncludePath(ADir, AFile);
  if (Result = '') and (AFile <> '') and CharInSet(AFile[1], ['\', '/']) then
    Result := IncludePath(ADir, Copy(AFile, 2, MaxInt));
end;

// Die Datei APath nach ALines; False, wenn sie nicht zu lesen ist (Oeffnen,
// Lesen, Kodierung). Dekodiert wie der Scan (uFileTextCache.LoadFileSmart:
// BOM, dann wohlgeformtes UTF-8, sonst Default-Codepage) - bis Review Woche
// G05-03 las TStringList.LoadFromFile ein UTF-8-Include ohne BOM als ANSI,
// ein Name mit Umlaut kam je Umlaut ein Zeichen laenger an (das UTF-8-Paar
// als zwei ANSI-Zeichen), und SameIdent (gleiche Laenge) fand ihn nicht
// (SCA164/SCA147: die Hilfe loeschte die Implementierung, die Deklaration
// im Include blieb - E2065). ANSI- und
// BOM-Dateien liest LoadFileSmart wie LoadFromFile.
function ReadIncludeText(const APath: string; ALines: TStringList): Boolean;
begin
  try
    Result := LoadFileSmart(APath, ALines);
  except
    on EStreamError do
      Result := False;
    on EEncodingError do
      Result := False;
  end;
end;

// Liegt eines der Verzeichnisse, in denen ein Include gesucht wird, oder
// der Include-Pfad selbst ('{$I \\server\share\defs.inc}') im Netz? Der
// Teil, der es zum Netzpfad macht (NetworkRoot), sonst ''.
function NetworkPlace(const ADir, AUnitDir, AFile: string): string;
begin
  Result := '';
  if IsNetworkPath(AFile) then
    Result := NetworkRoot(AFile)
  else if IsNetworkPath(AUnitDir) then
    Result := NetworkRoot(AUnitDir)
  else if IsNetworkPath(ADir) then
    Result := NetworkRoot(ADir);
end;

// Das Include AFile (relativ zu ADir, sonst zum Verzeichnis der Unit
// AUnitDir) und seine verschachtelten Includes bis MAX_INCLUDE_DEPTH: ''
// wenn ACheck.Test fuer keines einen Grund nennt, sonst der Grund (auch:
// nicht gefunden, nicht lesbar, auf einem Netzpfad - ACheck.MissingFmt).
// Den Netzpfad prueft sie VOR jedem FileExists (Gegen-Review R4-03).
function IncludeFileReason(const ADir, AUnitDir, AFile: string;
  const ACheck: TRdxIncludeCheck; ADepth: Integer): string;
var
  Path, F, Net : string;
  SL           : TStringList;
  Map          : TRdxCodeMap;
  Nested       : TArray<string>;
begin
  Result := '';
  if Copy(AFile, 1, 1) = '%' then Exit;
  if AUnitDir = '' then
    Exit(Format(ACheck.MissingFmt, [AFile, 'die Datei der Unit ist unbekannt']));
  if ADepth > MAX_INCLUDE_DEPTH then
    Exit(Format(ACheck.MissingFmt, [AFile, 'zu tief verschachtelt']));
  Net := NetworkPlace(ADir, AUnitDir, AFile);
  if Net <> '' then
    Exit(Format(ACheck.MissingFmt, [AFile, Format(R_INC_NETWORK, [Net])]));
  Path := FindInclude(ADir, AFile);
  if Path = '' then
    Path := FindInclude(AUnitDir, AFile);
  if Path = '' then
    Exit(Format(ACheck.MissingFmt, [AFile, 'nicht neben der Unit gefunden']));
  Nested := nil;
  Map := nil;
  SL := TStringList.Create;
  try
    if not ReadIncludeText(Path, SL) then
      Exit(Format(ACheck.MissingFmt, [AFile, 'nicht lesbar']));
    Map := TRdxCodeMap.Create(SL);
    Result := ACheck.Test(AFile, SL, Map, ACheck.Arg);
    if Result <> '' then Exit;
    Nested := IncludesUpTo(Map, Map.LineCount);
  finally
    Map.Free;
    SL.Free;
  end;
  for F in Nested do
  begin
    Result := IncludeFileReason(ExtractFilePath(Path), AUnitDir, F, ACheck,
      ADepth + 1);
    if Result <> '' then
      Exit(Format('%s (eingebunden von %s)', [Result, AFile]));
  end;
end;

function IncludeChainReason(const AUnitFile: string;
  const AIncludes: TArray<string>; const ACheck: TRdxIncludeCheck): string;
var
  F, Dir : string;
begin
  Result := '';
  Dir := ExtractFilePath(AUnitFile);
  for F in AIncludes do
  begin
    Result := IncludeFileReason(Dir, Dir, F, ACheck, 1);
    if Result <> '' then Exit;
  end;
end;

{ TRdxBlocks }

class function TRdxBlocks.ReadRoutine(AMap: TRdxCodeMap;
  const AHead: TRdxToken; out ARoutine: TRdxRoutine): string;
var
  H : TRdxToken;
begin
  H := AHead;
  if InList(AHead.Low, ROUTINE_WORDS) then
    H := HeadStart(AMap, AHead);
  Result := ReadRoutineAt(AMap, H, 0, ARoutine);
end;

// Rueckwaerts Token fuer Token wie bis Charge B2S-b RoutineAround (damals
// in uRdxTryFixes, seit Review Woche G08-08 in uRdxHandOver): das Token
// davor (P) entscheidet, ob T ein Kopf ist
// (IsRoutineHeadAfter, ohne Zuweisung 'Operator := ..' - AssignsTo) bzw.
// ein Schluesselwort (IsKeywordAt).
class function TRdxBlocks.HeadBefore(AMap: TRdxCodeMap; var T: TRdxToken;
  const AStops: array of string; out AStep: TRdxHeadStep): Boolean;
var
  P : TRdxToken;
begin
  AStep := Default(TRdxHeadStep);
  T := Before(AMap, T);
  while T.Low <> '' do
  begin
    P := Before(AMap, T);
    if IsRoutineHeadAfter(T, P) and not AssignsTo(AMap, T) then
    begin
      AStep.Tok := T;
      AStep.Reason := ReadRoutine(AMap, T, AStep.Routine);
      Exit(True);
    end;
    if InList(T.Low, AStops) and IsKeywordAt(AMap, T, P) then
    begin
      AStep.Tok := T;
      AStep.Stop := True;
      Exit(True);
    end;
    T := P;
  end;
  Result := False;
end;

class function TRdxBlocks.FindMethodDecls(AMap: TRdxCodeMap;
  const AClassPath, AMethod: string): TArray<TRdxToken>;
var
  C : TRdxToken;
begin
  Result := nil;
  for C in FindClassHeads(AMap, AClassPath) do
    AddMemberHeads(AMap, C, LowerCase(AMethod), Result);
end;

class function TRdxBlocks.MemberHeads(AMap: TRdxCodeMap;
  const AClass: TRdxToken; const AMethod: string): TArray<TRdxToken>;
begin
  Result := nil;
  AddMemberHeads(AMap, AClass, LowerCase(AMethod), Result);
end;

// Passen die Glieder AParts eines Kopfs zu AClassParts + ALowMethod? Die
// letzten Glieder muessen gleich sein.
function PartsMatch(const AParts, AClassParts: TArray<string>;
  const ALowMethod: string): Boolean;
var
  i, n : Integer;
begin
  n := Length(AClassParts);
  Result := (Length(AParts) > n) and SameIdent(AParts[High(AParts)], ALowMethod);
  if not Result then Exit;
  for i := 1 to n do
    Result := Result and SameIdent(AParts[High(AParts) - i], AClassParts[n - i]);
end;

class function TRdxBlocks.FindMethodImpls(AMap: TRdxCodeMap;
  const AClassPath, AMethod: string): TArray<TRdxToken>;
var
  T, P, Dummy : TRdxToken;
  R           : TRdxRoutine;
  ClassParts  : TArray<string>;
  InImpl      : Boolean;
begin
  Result := nil;
  ClassParts := SplitDotted(AClassPath);
  InImpl := False;
  P := Default(TRdxToken);
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    if InImpl and IsRoutineHead(AMap, T) then
    begin
      R := Default(TRdxRoutine);
      R.Keyword := T;
      if (ReadName(AMap, R, Dummy) = '')
         and PartsMatch(R.Parts, ClassParts, LowerCase(AMethod)) then
        AddToken(Result, HeadStart(AMap, T));
    end
    else if (T.Low = 'implementation') and IsKeywordAfter(T, P) then
      InImpl := True;
    P := T;
    T := After(AMap, T);
  end;
end;

class function TRdxBlocks.MethodDecl(AMap: TRdxCodeMap;
  const AHead: TRdxToken; out ADecl: TRdxRoutine): string;
begin
  Result := ReadMethodDecl(AMap, AHead, ADecl);
end;

class function TRdxBlocks.FindClassHeads(AMap: TRdxCodeMap;
  const AClassPath: string): TArray<TRdxToken>;
var
  T, C     : TRdxToken;
  LowClass : string;
begin
  Result := nil;
  LowClass := LowerCase(LastPart(AClassPath));
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    if ClassHeadAt(AMap, T, LowClass, C) then
      AddToken(Result, C);
    T := After(AMap, T);
  end;
end;

class function TRdxBlocks.HeritageOf(AMap: TRdxCodeMap;
  const AClass: TRdxToken): TArray<string>;
begin
  Result := HeritageNames(AMap, AClass);
end;

end.

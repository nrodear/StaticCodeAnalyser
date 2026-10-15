unit uRdxRoutineFixes;

// reDelphix - Quick-Fixes an ungenutzten Routinen, OHNE ToolsAPI und ohne
// Parser (Konzept_Editorhilfen_Recherche_2026-10-11, Charge H3
// "Aufraeumen", Teil b):
//   SCA164 UnusedRoutine: die freie Routine des implementation-Teils
//          loeschen - vom Kopf bis zum schliessenden 'end;' samt lokaler
//          Routinen, den direkt darueber stehenden Kommentar-, Doku- und
//          Attributzeilen, EINER Leerzeile und einer forward-Deklaration.
//   SCA147 UnusedPrivateMethod: die Deklaration im Klassenrumpf (samt
//          '///'-Doku) und die Implementierung (wie bei SCA164) loeschen.
// Beide bedeutungsgleich: was niemand ruft, fehlt danach niemandem. Den
// Beweis fuehrt der Planer NEU am Puffer, nicht der Detektor: der Name
// steht ausserhalb des geloeschten Bereichs nirgends als Code - Textsuche
// ueber die ganze Datei, also auch in inaktiven $IFDEF-Zweigen, die der
// Parser des Scans nicht sieht -, in keinem String-Literal (GetProcAddress,
// MethodAddress, RTTI, Skript-Registrierung per Name) und in keiner
// Direktive ($EXTERNALSYM). Kommentare zaehlen nicht als Verwendung.
//
// BAUSTEINE (Konzept Abschnitt 5; die Routinengrenzen tragen seit Charge
// H3c das Ende des Gueltigkeitsbereichs von SCA053 und spaeter
// SCA121/SCA196/SCA097/SCA096, der Finder SCA106/SCA054):
//   ReadRoutine     Routinengrenzen fuer Rumpfe jeder Groesse: Kopf (auch
//                   'class' davor, qualifizierter und generischer Name) ->
//                   Direktiven, auch auf Folgezeilen -> lokale Abschnitte
//                   (var/const/type/label ...) und lokale Routinen
//                   (rekursiv) -> begin bzw. asm -> passendes end -> ';'.
//                   forward/external: ohne Rumpf. (uRdxRaiseFixes.
//                   MethodBodyOn kennt nur leere Rumpfe ohne lokale
//                   Routinen.)
//   FindMethodDecls / FindMethodImpls
//                   Decl/Impl-Finder: die Deklarationen einer Methode auf
//                   Tiefe 1 im Rumpf ihrer Klasse (auch verschachtelte und
//                   generische Klassen) und ihre Implementierungskoepfe im
//                   implementation-Teil ('TOuter.TInner.Bar', 'TFoo<T>.Bar',
//                   'class procedure'). Mehr als ein Treffer heisst Overload
//                   oder mehrdeutig - die Aufrufer lehnen dann ab.
//   FindClassHeads / HeritageOf / MethodDecl
//                   Klassenkopf (Charge H5, SCA096/SCA097): die Koepfe einer
//                   Klasse mit Rumpf, ihre Vorfahrenliste und die
//                   Direktiven einer Deklaration ('override').
//
// WAS MITGEHT: ueber einer Implementierung '///'-Doku, Attribute und die
// direkt anhaengenden Zeilen nur aus Kommentar, wenn sie die Routine beim
// Namen nennen ('// Name: Foo()', '{ TFoo.Bar }') und keinen Marker tragen
// (noinspection, Absichtsmarker wie SCA019). Bis Charge H3c ging JEDER
// Kommentar darueber mit; das Gegen-Review H3 (Minor 3) fand darunter
// Abschnittsueberschriften ('(* === run-time registration functions ===
// *)', '{ layout vars }') und einen Absichtsmarker - eine Ueberschrift ist
// von einer Beschreibung am Text nicht sicher zu unterscheiden, deshalb
// bleibt jetzt jeder Kommentar, der die Routine nicht nennt
// (Korpus-Harness: bei 101 der 897 SCA164-Angebote bleibt er jetzt stehen -
// 53 Trenner, 43 Texte, 4 Ueberschriften mit Trenner, 1 Absichtsmarker;
// kein Angebot faellt weg). Preis: eine Beschreibung ohne den Namen ('//
// default is case-sensitive') bleibt stehen und liegt danach ueber dem,
// was folgt - sichtbar und von Hand zu loeschen; eine geloeschte
// Ueberschrift waere still verloren. Ein Abschnittsmarker '{ TFoo }' bleibt
// ohnehin (er gehoert zur Gruppe). Ueber einer Deklaration im Klassenrumpf
// nur '///' - dort steht oft ein Gruppenkommentar ('{ Private
// declarations }').
//
// GRENZEN: Programme und Bibliotheken (.dpr) meldet SCA164 nicht - der
// Detektor sieht nur Kinder des implementation-Knotens; der Planer verlangt
// deshalb ein 'implementation' vor dem Kopf. Eine leere private-Sektion,
// die nach SCA147 uebrig bleibt, meldet danach SCA087 (eigene Hilfe).
//
// PLATTE: die Planer sind Textlogik, die Unit ist es nicht ganz (Gegen-
// Review R4-08) - IncludeChainReason liest die Include-Dateien vor
// 'implementation' von der Platte: fuer SCA164 und (seit Charge B1-FD)
// SCA147 im Check der Tabelle, seit Charge Q14 auch fuer SCA014
// (uRdxMagicFixes, Compiler-Weichen der Includes). Auf einem Netzpfad (UNC
// oder Netzlaufwerk, IsNetworkPath) liest sie nichts und nennt den Grund -
// der Menueaufbau laeuft im Hauptthread (R4-03). Der Leser gehoert in eine
// eigene Unit (uRdxIncludes, samt IncludesUpTo und der zweiten Kopie
// uRdxMagicFixes.AllIncludes); das traegt die Charge der Schichtung, weil
// eine neue Unit Paket, Projekt und Pruefstand beruehrt.
//
// GRUNDSATZ wie in uRdxSimpleFixes: lieber keine Hilfe als eine falsche.

interface

uses
  System.Classes,    // TStrings (TRdxIncludeTest), TStringList (Includes)
  uRdxBufferMath, uRdxCodeMap;

const
  // Woerter zwischen 'class' und der Vorfahrenliste ('class abstract(TBase)',
  // 'class sealed'). Seit Charge H5c oeffentlich: uRdxResultFixes liest den
  // ersten Eintrag der Liste mit Qualifizierung (Gegen-Review H5, Minor 3).
  CLASS_MODIFIERS: array[0..1] of string = ('abstract', 'sealed');

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

  // Ergebnis der Planer: alle Ersetzungen (EIN Undo-Schritt) und der Name
  // fuer den Menuetext - schon aus der Meldung, auch wenn abgelehnt wird.
  // Includes: die Dateien der {$I}-Direktiven vor 'implementation' (SCA164;
  // seit Charge B1-FD auch SCA147 - ein Include im interface-Teil kann eine
  // Nachfahrenklasse mit 'property P read X' tragen, Gegen-Review R4-05)
  // - der Puffer zeigt ihren Inhalt nicht; der Aufrufer liest sie neben der
  // Unit und prueft sie (IncludeReason), bevor er die Hilfe anbietet. Das
  // Geruest der Tabelle nimmt die Planer als TRdxPlannerOf<TRdxRoutinePlan>
  // (uRdxFixTable; der eigene Typ TRdxRoutinePlanner hier war seit Charge
  // H5c unbenutzt und ist mit B1-FD gestrichen, Gegen-Review R4-07).
  TRdxRoutinePlan = record
    Edits    : TArray<TRdxEdit>;
    Name     : string;
    Includes : TArray<string>;
  end;

  // Die Planer der Charge H3b und ihre Bausteine (s. Kopf): je Fund alle
  // Ersetzungen in EINEM Plan oder der Grund, warum keine - auf dem
  // Puffertext ueber die Code-Sicht, ohne ToolsAPI und Parser (laeuft auch
  // im FPC-Pruefstand). Was nur die Platte weiss (Formdatei, Include-
  // Dateien), liest der Aufrufer uRdxFixTable bzw. IncludeReason.
  TRdxRoutineFixes = class
  public
    // Baustein Routinengrenzen: die Routine, deren Kopf an AHead beginnt
    // ('class' oder das Kopfwort; ein Kopfwort mit 'class' davor wird auf
    // 'class' gezogen). '' oder der Grund, warum die Grenzen nicht sicher
    // sind (Kopf ohne ';', lokaler Klassentyp, kein end, hinter dem ';'
    // beginnt nichts Neues ...).
    class function ReadRoutine(AMap: TRdxCodeMap; const AHead: TRdxToken;
      out ARoutine: TRdxRoutine): string; static;

    // Baustein Decl/Impl-Finder: die Koepfe ('class' bzw. Kopfwort) der
    // Methode AMethod auf Tiefe 1 im Rumpf jeder Klasse, die wie das letzte
    // Glied von AClassPath heisst.
    class function FindMethodDecls(AMap: TRdxCodeMap;
      const AClassPath, AMethod: string): TArray<TRdxToken>; static;
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

    // SCA164: die Routine der Meldung 'Top-level routine X appears unused
    // ...' mit Kopf auf ALine loeschen (s. Kopf der Unit). Keine Hilfe fuer
    // Methoden, globale FPC-Operatoren, Koepfe vor 'implementation',
    // export/public/alias/external/forward/interrupt-Direktiven (auch FPC
    // in Klammern: '[public, alias: ''X'']'), Overloads, jede Verwendung
    // ausserhalb der Routine (Umlaute ohne Gross/klein), den Namen in einem
    // String-Literal oder einer Direktive, {$L}/{$LINK} in der Datei, {$I}
    // im implementation-Teil, eine Direktive im Bereich ausser
    // ausgeglichenem $IF../$ENDIF bzw. $REGION, zwei Routinen auf einer
    // Zeile, einen Marker-Kommentar, der ausserhalb wirkt ('end; //
    // noinspection X' auf der letzten Zeile, '// noinspection-file' im
    // Bereich - MarkerLinesReason). Die {$I}-Dateien davor nennt
    // APlan.Includes - der Aufrufer prueft sie mit IncludeReason.
    class function UnusedRoutine(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxRoutinePlan;
      out AReason: string): Boolean; static;

    // SCA147: die Methode der Meldung 'Private method TFoo.X appears unused
    // ...' (Deklaration auf ALine) loeschen. Keine Hilfe ausserhalb von
    // private/strict private, bei virtual/dynamic/override/abstract/
    // reintroduce/message/overload/dispid, Konstruktor/Destruktor/Operator,
    // Attribut an Klasse oder Methode, {$RTTI} in der Datei, {$I} im
    // Klassenrumpf oder im implementation-Teil, einem Interface der Klasse
    // aus einer anderen Unit (auch als erster Eintrag 'class(IFremd)' oder
    // als Vorfahr eines lokalen Interfaces) bzw. einem Member von
    // IInterface/IDispatch als Name, mehr als einer Deklaration oder
    // Implementierung, keiner Implementierung in der Datei, jeder weiteren
    // Verwendung (auch Property-Accessor, String-Literal, Direktive), einer
    // Direktive im Bereich und einem Marker-Kommentar, der ausserhalb wirkt,
    // wie bei SCA164. Die Formdatei prueft der Aufrufer (FormNamesMethod),
    // die {$I}-Dateien davor (seit Charge B1-FD in APlan.Includes) ebenso
    // mit IncludeReason.
    class function UnusedPrivateMethod(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxRoutinePlan;
      out AReason: string): Boolean; static;

    // SCA147: nennt die Formdatei (.dfm/.fmx/.lfm-Text) AName als Wort -
    // etwa als Ereignis 'OnClick = AName'? Den Text liest der Aufrufer.
    class function FormNamesMethod(const AFormText, AName: string): Boolean;
      static;

    // SCA164/SCA147: die Include-Dateien AIncludes (TRdxRoutinePlan.
    // Includes) der Unit AUnitFile lesen - neben der Unit, ohne Endung auch
    // mit .inc/.pas, verschachtelte Includes ebenso. '' wenn keine AName
    // als Wort nennt; sonst der Grund - auch, wenn eine nicht zu finden oder
    // zu lesen ist oder auf einem Netzpfad liegt: sie kann die Routine im
    // interface-Teil deklarieren (nach dem Loeschen E2065), rufen (Gegen-
    // Review H3, Minor 4) bzw. die Methode als Property-Accessor einer
    // Nachfahrenklasse nennen (R4-05). '{$I %DATE%}' (FPC) ist keine Datei.
    class function IncludeReason(const AUnitFile: string;
      const AIncludes: TArray<string>; const AName: string): string; static;
  end;

// Traegt R eine der Direktiven AWords (klein)? AWord: die erste, '' ohne.
// Seit Charge H5c oeffentlich - uRdxResultFixes fragt 'override', 'overload'
// und 'abstract' (bis dahin dort als HasDirectiveWord kopiert; Gegen-Review
// H5, Minor 6).
function HasDirective(const R: TRdxRoutine; const AWords: array of string;
  out AWord: string): Boolean;

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
// Liegt die Unit oder ein Include auf einem Netzpfad (IsNetworkPath), wird
// nichts gelesen: der Grund kommt ohne Plattenzugriff (Gegen-Review R4-03).
function IncludeChainReason(const AUnitFile: string;
  const AIncludes: TArray<string>; const ACheck: TRdxIncludeCheck): string;

// Liegt APath im Netz - UNC ('\\server\share\..', auch mit '/') oder ein
// Laufwerk, das Windows als Netzlaufwerk fuehrt (GetDriveType)? Dort liest
// reDelphix nichts von der Platte: der Menueaufbau laeuft im Hauptthread,
// und ein nicht erreichbarer Server haelt jedes FileExists sekundenlang auf
// (Gegen-Review R4-03: 9 bis 16 s je Include). Ein relativer Pfad liegt
// nirgends. Die Netzpfad-Regel der Planer-Units, die von der Platte lesen
// (Includes, SCA014 FileReason); bis Charge B1-FD pruefte nur SCA014 den
// Pfad der Unit (uRdxMagicFixes UNC, uRdxFixTable.RemoteDriveReason das
// Netzlaufwerk), kein Include und SCA164/SCA147 gar nichts.
function IsNetworkPath(const APath: string): Boolean;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxStructFixes;   // RangeText

const
  SPAN_164 = 'sca164';
  SPAN_147 = 'sca147';
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
  // SCA164: damit ist die Routine von aussen erreichbar (Linker-Name,
  // Export, Compiler/RTL, Interrupt) oder ohne Rumpf.
  REACHABLE_DIRECTIVES: array[0..9] of string = ('export', 'public',
    'alias', 'external', 'forward', 'interrupt', 'compilerproc', 'rtlproc',
    'internproc', 'weakexternal');
  // Direktiven einer Methodendeklaration im Klassenrumpf. 'public' fehlt
  // mit Absicht: dort beginnt es einen Abschnitt.
  METHOD_DIRECTIVES: array[0..23] of string = ('virtual', 'dynamic',
    'abstract', 'overload', 'override', 'reintroduce', 'stdcall', 'cdecl',
    'register', 'pascal', 'safecall', 'inline', 'static', 'message',
    'deprecated', 'platform', 'experimental', 'final', 'winapi',
    'assembler', 'varargs', 'dispid', 'external', 'unsafe');
  // SCA147: damit erreicht die Methode ein Vorfahr, ein Nachfahr, die
  // Nachrichten-Verteilung oder ein Overload-Geschwister - ohne Namen.
  DISPATCH_DIRECTIVES: array[0..9] of string = ('virtual', 'dynamic',
    'abstract', 'override', 'reintroduce', 'message', 'overload', 'dispid',
    'external', 'final');
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
  PRIVATE_SECTIONS: array[0..1] of string = ('private', 'strict private');
  // Hinter diesen Woertern ist ein Wort ein Feld, kein Abschnitt bzw.
  // keine Direktive ('Public: Boolean', 'Platform: string').
  FIELD_MARKS: array[0..2] of string = (':', ',', '=');
  NO_SPECIAL: array[0..2] of string = ('constructor', 'destructor',
    'operator');
  CTOR_DTOR: array[0..1] of string = ('constructor', 'destructor');
  KW_OPERATOR = 'operator';
  // SCA147, Interfaces der Klasse (ForeignInterfaceReason, wie Gate E des
  // Detektors): die Wurzeln aus System - nie in der Datei deklariert, ihre
  // Member bekannt - und die Grenze der Kette (Detektor: 64).
  INTERFACE_KINDS: array[0..1] of string = ('interface', 'dispinterface');
  ROOT_INTERFACES: array[0..2] of string = ('iinterface', 'iunknown',
    'idispatch');
  ROOT_MEMBERS: array[0..2] of string = ('queryinterface', '_addref',
    '_release');
  DISPATCH_MEMBERS: array[0..3] of string = ('gettypeinfocount',
    'gettypeinfo', 'getidsofnames', 'invoke');
  MAX_INTERFACES = 64;
  COND_OPEN: array[0..3] of string = ('if', 'ifdef', 'ifndef', 'ifopt');
  COND_MID: array[0..1] of string = ('else', 'elseif');
  COND_CLOSE: array[0..1] of string = ('endif', 'ifend');
  LINK_WORDS: array[0..1] of string = ('l', 'link');
  // Property-Teile, hinter denen ein Methodenname Accessor ist.
  ACCESSOR_WORDS: array[0..4] of string = ('read', 'write', 'stored', 'add',
    'remove');
  KEY_ROUTINE = 'Top-level routine ';
  KEY_METHOD  = 'Private method ';
  KEY_UNUSED  = ' appears unused';
  DOC_PREFIX  = '///';
  STACK_COND   = 'c';
  STACK_REGION = 'r';
  MAX_NESTING    = 8;     // Tiefe lokaler Routinen in Routinen
  MAX_NAME_PARTS = 8;     // Glieder eines qualifizierten Namens
  MAX_BACK       = 400;   // so weit sucht InExports rueckwaerts
  R_IMPL_INCLUDE = '{$I}-Include im implementation-Teil (Zeile %d) - dort '
    + 'kann ein Aufrufer stehen, den die Hilfe nicht sieht';
  R_LAST_LINE = 'die Routine endet auf der letzten Zeile der Datei';
  // SCA164/SCA147: Include-Dateien vor implementation (IncludeReason).
  R_INC_MISSING = 'Include %s vor implementation %s - es kann die Routine '
    + 'deklarieren (interface-Teil) oder rufen, die Hilfe sieht es nicht';
  // Ursache fuer MissingFmt: Unit oder Include auf einem Netzpfad (R4-03).
  R_INC_NETWORK = 'auf einem Netzpfad (%s) - nicht gelesen, der Menueaufbau '
    + 'laeuft im Hauptthread';
  // GetDriveType: ein Netzlaufwerk (DRIVE_REMOTE, WinBase.h).
  DRIVE_KIND_REMOTE = 4;
  // SCA164/SCA147: Marker im geloeschten Bereich, die ausserhalb wirken
  // (MarkerLinesReason, Gegen-Review R4-04).
  MARKER_FILE = 'noinspection-file';
  R_MARKER_FILE = '"// noinspection-file" in Zeile %d - der Marker gilt der '
    + 'ganzen Datei und ginge mit verloren; von Hand loeschen';
  R_MARKER_TAIL = 'Zeile %d endet mit dem Kommentar "%s" - ein Marker hinter '
    + 'Code gilt der Zeile dahinter bzw. bleibt stehen; von Hand loeschen';
  // So viel des Kommentars nennt R_MARKER_TAIL.
  MARKER_QUOTE_LEN = 40;
  MAX_INCLUDE_DEPTH = 4;
  INCLUDE_EXTENSIONS: array[0..1] of string = ('.inc', '.pas');
  // Folgt eines davon einem Include, steht es im Kopf der Unit
  // (IncludesUpTo).
  HEADER_FOLLOWERS: array[0..2] of string = ('unit', 'interface', 'uses');

type
  // Ganze Zeilen Top..Bottom - ein Loeschbereich.
  TRdxLines = record
    Top    : Integer;
    Bottom : Integer;
  end;

  // Was ueber einem Kopf mitgeht: '///'-Doku und Attributzeilen
  // (Klassenrumpf, forward) oder dazu Kommentarzeilen, die die Routine
  // nennen (Implementierung, StepAbove).
  TRdxAbove = (abDocOnly, abComments);

  // Ein Lauf ueber alle Code-Token: 'implementation' und jedes Vorkommen
  // des gesuchten Namens als Wort.
  TRdxNameScan = record
    Impl : TRdxToken;
    Hits : TArray<TRdxToken>;
  end;

  // Was die Zeilen-Durchsicht fand (FileFacts): je die erste Zeile, 0 =
  // keine.
  TRdxFileFacts = record
    LinksObject   : Integer;   // {$L datei} / {$LINK datei}
    ImplInclude   : Integer;   // {$I datei} hinter implementation
    Rtti          : Integer;   // {$RTTI ...}
    NameLiteral   : Integer;   // String-Literal mit dem Namen als Wort
    NameDirective : Integer;   // Direktive mit dem Namen als Wort
  end;

  // Zustand der Zeilen-Durchsicht. Own: die geloeschten Bereiche - ein
  // Literal oder eine Direktive dort zaehlt nicht.
  TRdxFactScan = record
    LowName  : string;
    ImplLine : Integer;
    Own      : array[0..1] of TRdxLines;
    Facts    : TRdxFileFacts;
    function InOwn(ALine: Integer): Boolean;
    procedure Directive(AMap: TRdxCodeMap; ALine, ACol: Integer);
    procedure Literal(AMap: TRdxCodeMap; ALine, ACol, AEnd: Integer);
  end;

  // Tiefe und Sichtbarkeit beim Lauf durch einen Klassenrumpf (Tiefe 1 =
  // die Member der Klasse; geschachtelte Typen und records zaehlen hoch).
  TRdxClassScan = record
    Depth : Integer;
    Vis   : string;      // Sichtbarkeit auf Tiefe 1, '' = Vorgabe
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

  // Der Klassenkopf um eine Deklaration (EnclosingClass).
  TRdxClassHead = record
    NameTok  : TRdxToken;
    ClassTok : TRdxToken;
    Vis      : string;
  end;

{ ---- Token und Texte ---- }

// TokBefore und TokText stehen seit Charge H4c in uRdxCodeMap, AddToken
// und LastPart seit Charge H5c (dort), AddEdit in uRdxBufferMath.
function TokInRange(const T, AFirst, ALast: TRdxToken): Boolean;
begin
  Result := not TokBefore(T, AFirst) and not TokBefore(ALast, T);
end;

procedure AddText(var AList: TArray<string>; const S: string);
begin
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := S;
end;

// Glieder zu 'A.B.C' (TStringBuilder - keine Verkettung in der Schleife).
function JoinDotted(const AParts: TArray<string>): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(AParts) do
    begin
      if i > 0 then
        SB.Append('.');
      SB.Append(AParts[i]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
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

// Kommt ALowName als ganzes Wort in ALowText vor (beides klein, genau
// gleich; Wortgrenze wie IsIdentChar)? Anders als HasIdentWord (uRdxCodeMap,
// Umlaute ohne Gross/klein - fuer Verwendungen: ein Treffer zu viel sperrt)
// genau: hier entscheidet es, ob ein Kommentar ueber dem Kopf mitgeht. Bis
// Charge H3c HasWord, gleich benannt wie das ASCII-HasWord von
// uRdxCleanupFixes (Minor 5).
function HasExactWord(const ALowText, ALowName: string): Boolean;
var
  P, E : Integer;
begin
  Result := False;
  if ALowName = '' then Exit;
  P := Pos(ALowName, ALowText);
  while P > 0 do
  begin
    E := P + Length(ALowName);
    if ((P = 1) or not IsIdentChar(ALowText[P - 1]))
       and ((E > Length(ALowText)) or not IsIdentChar(ALowText[E])) then
      Exit(True);
    P := Pos(ALowName, ALowText, P + 1);
  end;
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
      R.Name := JoinDotted(Raw);
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
// Routinenkopf hinter ';' heissen, das passende end wurde verfehlt.
function BodyHook(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  ADepth: Integer): string;
begin
  Result := '';
  if not IsKeywordAfter(T, APrev) then Exit;
  if InList(T.Low, UNIT_STOPS) then
    Result := Format('"%s" im Rumpf - Ende der Routine nicht gefunden',
      [T.Low])
  else if (APrev.Low = KW_SEMI)
     and (InList(T.Low, ROUTINE_WORDS) or (T.Low = KW_CLASS)) then
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

{ ---- Zeilen und Loeschbereiche ---- }

// Eine Zeile nur aus Kommentar (keine Direktive) und nicht leer?
function CommentOnly(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  L   : string;
  i   : Integer;
  Any : Boolean;
begin
  L := AMap.Raw(ALine);
  Any := False;
  for i := 1 to Length(L) do
    if not IsBlank(L[i]) then
    begin
      if (AMap.ClassAt(ALine, i) <> 'k') or DirectiveAt(AMap, ALine, i) then
        Exit(False);
      Any := True;
    end;
  Result := Any;
end;

// Eine '///'-Zeile (XMLDoc) - der Kommentar beginnt am Zeilenanfang.
function DocLine(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  L : string;
  C : Integer;
begin
  L := AMap.Raw(ALine);
  C := SkipBlanks(L, 1);
  Result := (Copy(L, C, Length(DOC_PREFIX)) = DOC_PREFIX)
    and (AMap.LineCommentCol(ALine) = C);
end;

// Eine Zeile nur mit einem Attribut '[..]'?
function AttrLine(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  T, C : TRdxToken;
begin
  Result := False;
  T := NextToken(AMap, ALine, 1);
  if (T.Line <> ALine) or (T.Low <> '[')
     or (T.Col <> SkipBlanks(AMap.Raw(ALine), 1)) then
    Exit;
  C := MatchClose(AMap, T, 0);
  Result := (C.Line = ALine) and (After(AMap, C).Line <> ALine);
end;

// '{ TFoo }' - ein Abschnittsmarker (ein Bezeichner in geschweiften
// Klammern) gehoert zur Gruppe, nicht zur Routine darunter. Nennt er die
// Routine selbst ('{ TFoo.Bar }' ueber 'TFoo.Bar', Korpus doublecmd), ist
// er ihre Ueberschrift und geht mit.
function MarkerLine(AMap: TRdxCodeMap; ALine: Integer;
  const AName: string): Boolean;
var
  S, Inner : string;
  i        : Integer;
begin
  Result := False;
  S := Trim(AMap.Raw(ALine));
  if (Length(S) < Length('{x}')) or (S[1] <> '{') or (S[Length(S)] <> '}')
     or (S[2] = '$') then
    Exit;
  Inner := Trim(Copy(S, 2, Length(S) - 2));
  if (Inner = '') or not IsIdentStart(Inner[1]) then Exit;
  for i := 1 to Length(Inner) do
    if not (IsIdentChar(Inner[i]) or (Inner[i] = '.')) then
      Exit;
  Result := not SameText(Inner, AName)
    and not SameText(Inner, Copy(AName, LastDelimiter('.', AName) + 1,
      MaxInt));
end;

// Eine Zeile eines Kommentar-Laufs ueber dem Kopf: nur Kommentar, weder
// '///'-Doku noch Attribut noch Abschnittsmarker '{ TFoo }'.
function RunLine(AMap: TRdxCodeMap; ALine: Integer;
  const AName: string): Boolean;
begin
  Result := (ALine >= 1) and CommentOnly(AMap, ALine)
    and not DocLine(AMap, ALine) and not AttrLine(AMap, ALine)
    and not MarkerLine(AMap, ALine, AName);
end;

// Die Zeilen ATop..ABottom als ein Text.
function LinesText(AMap: TRdxCodeMap; ATop, ABottom: Integer): string;
var
  SB : TStringBuilder;
  Li : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for Li := ATop to ABottom do
      SB.Append(AMap.Raw(Li)).Append(#10);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Geht der Kommentar-Lauf ATop..ABottom ueber dem Kopf von R mit? Nur, wenn
// er die Routine beim Namen nennt (dann beschreibt er sie) und keinen
// Unterdrueck- oder Absichtsmarker traegt (MarkerReason, wie SCA070).
function RunGoes(AMap: TRdxCodeMap; ATop, ABottom: Integer;
  const R: TRdxRoutine): Boolean;
var
  Text : string;
begin
  Text := LinesText(AMap, ATop, ABottom);
  Result := (MarkerReason(Text) = '')
    and HasExactWord(LowerCase(Text), LowerCase(Copy(R.Name,
      LastDelimiter('.', R.Name) + 1, MaxInt)));
end;

// Ein Schritt nach oben ab ATop (TopAbove): die neue oberste Zeile oder ATop,
// wenn darueber nichts mehr zum Kopf gehoert. '///'-Doku und Attribute
// gehoeren immer dazu; bei abComments auch ein ganzer Kommentar-Lauf, wenn
// er mitgeht (RunGoes).
function StepAbove(AMap: TRdxCodeMap; const R: TRdxRoutine; AMode: TRdxAbove;
  ATop: Integer): Integer;
var
  L, Run : Integer;
begin
  Result := ATop;
  L := ATop - 1;
  if L < 1 then Exit;
  if DocLine(AMap, L) or AttrLine(AMap, L) then
    Exit(L);
  if (AMode = abDocOnly) or not RunLine(AMap, L, R.Name) then Exit;
  Run := L;
  while RunLine(AMap, Run - 1, R.Name) do
    Dec(Run);
  if RunGoes(AMap, Run, L, R) then
    Result := Run;
end;

// Die oberste Zeile, die zum Kopf von R gehoert. Ein Block-Kommentar, der
// in einer Code-Zeile darueber beginnt, bleibt ganz stehen. Seit Charge H3c
// (Gegen-Review H3, Minor 3) geht ein Kommentar ueber einer Implementierung
// nur mit, wenn er die Routine nennt und keinen Marker traegt - eine
// Abschnittsueberschrift ('(* === run-time registration functions === *)',
// '{ layout vars }'), ein '// noinspection-file' oder ein Absichtsmarker
// gehoert zur Gruppe bzw. zur Datei und bleibt stehen, mit allem darueber.
function TopAbove(AMap: TRdxCodeMap; const R: TRdxRoutine;
  AMode: TRdxAbove): Integer;
var
  Prev : Integer;
begin
  Result := R.Head.Line;
  repeat
    Prev := Result;
    Result := StepAbove(AMap, R, AMode, Result);
  until Result = Prev;
  while (Result < R.Head.Line) and AMap.StartsInside(Result) do
    Inc(Result);
end;

function BlankLine(AMap: TRdxCodeMap; ALine: Integer): Boolean;
begin
  Result := (ALine >= 1) and (ALine <= AMap.LineCount)
    and (Trim(AMap.Raw(ALine)) = '') and not AMap.StartsInside(ALine);
end;

// Stehen Kopf AFirst bis Ende ALast allein auf ihren Zeilen (ab ATop)? ''
// oder der Grund.
function OwnLinesReason(AMap: TRdxCodeMap; const AFirst, ALast: TRdxToken;
  ATop: Integer): string;
var
  P, N : TRdxToken;
begin
  Result := '';
  P := Before(AMap, AFirst);
  N := After(AMap, ALast);
  if (P.Low <> '') and (P.Line = AFirst.Line) then
    Result := 'vor dem Kopf steht Code auf derselben Zeile (zwei Routinen auf '
      + 'einer Zeile?)'
  else if (N.Low <> '') and (N.Line = ALast.Line) then
    Result := 'hinter dem Ende steht Code auf derselben Zeile (zwei Routinen '
      + 'auf einer Zeile?)'
  else if AMap.StartsInside(ATop) then
    Result := 'auf der Kopfzeile endet ein Kommentar ueber Zeilen'
  else if AMap.StartsInside(ALast.Line + 1) then
    Result := 'hinter dem Ende beginnt ein Kommentar ueber Zeilen'
  else if ALast.Line >= AMap.LineCount then
    Result := R_LAST_LINE;
end;

// Die ganzen Zeilen von R (Kopf bis R.Last) samt dem, was darueber zum
// Kopf gehoert (AMode). '' oder der Grund.
function HeadLines(AMap: TRdxCodeMap; const R: TRdxRoutine;
  AMode: TRdxAbove; out ALines: TRdxLines): string;
begin
  ALines.Top := TopAbove(AMap, R, AMode);
  ALines.Bottom := R.Last.Line;
  Result := OwnLinesReason(AMap, R.Head, R.Last, ALines.Top);
end;

// EINE Leerzeile geht mit: die dahinter, sonst die davor. Ein Bereich darf
// nicht auf einer LEEREN Zeile beginnen (TRefactorInfoBuilder.SpanFits -
// Korpus-Harness: 33 PLANFAIL); LinesEdit beginnt ihn dann auf dem letzten
// Zeichen der Zeile davor, das stehen bleibt. Die Leerzeile davor geht
// deshalb nur mit, wenn diese Zeile hinter AFloor liegt (dort endet eine
// andere Ersetzung derselben Hilfe) und auf ein ASCII-Zeichen endet (kein
// halbes Surrogatpaar).
procedure TakeBlankLine(AMap: TRdxCodeMap; var ALines: TRdxLines;
  AFloor: Integer);
var
  Start : Integer;
  L     : string;
begin
  if BlankLine(AMap, ALines.Bottom + 1)
     and (ALines.Bottom + 1 < AMap.LineCount) then
  begin
    Inc(ALines.Bottom);
    Exit;
  end;
  if not BlankLine(AMap, ALines.Top - 1) then Exit;
  Start := ALines.Top - 1;
  if AMap.Raw(Start) = '' then
    Dec(Start);
  L := AMap.Raw(Start);
  if (Start > AFloor) and (L <> '') and (L[Length(L)] < #128) then
    Dec(ALines.Top);
end;

// Die Ersetzung, die ALines loescht (bis Spalte 1 der Zeile dahinter); ist
// die erste Zeile leer, ab dem letzten Zeichen der Zeile davor (s.
// TakeBlankLine).
function LinesEdit(AMap: TRdxCodeMap; const ALines: TRdxLines;
  const ARole: string): TRdxEdit;
var
  L : string;
begin
  Result := Default(TRdxEdit);
  L := AMap.Raw(ALines.Top);
  if L <> '' then
    Result.Span := TRefactorSpan.Make(ARole, ALines.Top, 1,
      ALines.Bottom + 1, 1)
  else
  begin
    // Das Zeichen und sein Zeilenende bleiben - sonst klebte die Zeile
    // dahinter an ihm, hinter einem '//' sogar auskommentiert.
    L := AMap.Raw(ALines.Top - 1);
    Result.Span := TRefactorSpan.Make(ARole, ALines.Top - 1, Length(L),
      ALines.Bottom + 1, 1);
    Result.NewText := Copy(L, Length(L), 1) + #10;
  end;
  Result.Expected := RangeText(AMap, Result.Span);
end;

// Marker, die das Loeschen der ganzen Zeilen ALines mitnaehme, obwohl sie
// ausserhalb wirken (Gegen-Review R4-04): ein '//'-Kommentar mit Marker
// (MarkerReason: noinspection oder ein Absichtsmarker wie bei SCA019) hinter
// dem Code der letzten nicht leeren Zeile - '// noinspection X' hinter Code
// gilt der naechsten Zeile, und die bleibt stehen (uSuppression.BuildMap;
// 'end; // noinspection UnusedRoutine' zielte auf die Routine dahinter);
// ein Absichtskommentar bleibt wie ueber dem Kopf stehen -, und ein
// '// noinspection-file' irgendwo im Bereich (er gilt der ganzen Datei).
// Marker in den Zeilen davor zielen in den Bereich selbst; ueber dem Kopf
// laesst TopAbove sie stehen. '' oder der Grund.
function MarkerLinesReason(AMap: TRdxCodeMap; const ALines: TRdxLines): string;
var
  Li, Slash, Last : Integer;
  Comment         : string;
begin
  Result := '';
  Last := 0;
  for Li := ALines.Top to ALines.Bottom do
  begin
    Slash := AMap.LineCommentCol(Li);
    if (Slash > 0) and (Pos(MARKER_FILE,
         LowerCase(Copy(AMap.Raw(Li), Slash, MaxInt))) > 0) then
      Exit(Format(R_MARKER_FILE, [Li]));
    if Trim(AMap.Raw(Li)) <> '' then
      Last := Li;
  end;
  if Last = 0 then Exit;
  Slash := AMap.LineCommentCol(Last);
  if Slash = 0 then Exit;
  Comment := Copy(AMap.Raw(Last), Slash, MaxInt);
  if MarkerReason(Comment) <> '' then
    Result := Format(R_MARKER_TAIL, [Last,
      TrimRight(Copy(Comment, 1, MARKER_QUOTE_LEN))]);
end;

{ ---- Direktiven (OpensDirective, DirectiveWord, IncludeInLines: seit
  Charge H3c in uRdxCodeMap) ---- }

// Ein offenes Gegenstueck vom Stapel nehmen (AWant 'c' oder 'r'). '' oder
// der Grund.
function PopDirective(var AStack: string; const AWant, AWord: string;
  ALine: Integer): string;
begin
  if Copy(AStack, Length(AStack), 1) <> AWant then
    Exit(Format('{$%s} in Zeile %d ohne Gegenstueck im Bereich',
      [UpperCase(AWord), ALine]));
  SetLength(AStack, Length(AStack) - 1);
  Result := '';
end;

// Ein Schritt der Direktiven-Bilanz: AStack traegt 'c' je offenem $IF..
// und 'r' je offenem $REGION. Jede andere Direktive sperrt - ein $DEFINE,
// $R- oder $I wirkt vielleicht ueber die Routine hinaus. '' oder Grund.
function BalanceStep(var AStack: string; const AWord: string;
  ALine: Integer): string;
begin
  Result := '';
  if InList(AWord, COND_OPEN) then
    AStack := AStack + STACK_COND
  else if AWord = 'region' then
    AStack := AStack + STACK_REGION
  else if InList(AWord, COND_MID) then
  begin
    if Copy(AStack, Length(AStack), 1) <> STACK_COND then
      Result := Format('{$%s} in Zeile %d ohne $IF im Bereich',
        [UpperCase(AWord), ALine]);
  end
  else if AWord = 'endregion' then
    Result := PopDirective(AStack, STACK_REGION, AWord, ALine)
  else if InList(AWord, COND_CLOSE) then
    Result := PopDirective(AStack, STACK_COND, AWord, ALine)
  else
    Result := Format('Compiler-Direktive {$%s} in Zeile %d - sie wirkt '
      + 'vielleicht ueber die Routine hinaus', [UpperCase(AWord), ALine]);
end;

// Die Direktiven in den Zeilen ALines: nur ausgeglichene $IF../$ELSE/
// $ENDIF und $REGION/$ENDREGION. '' oder der Grund.
function DirectiveBalance(AMap: TRdxCodeMap; const ALines: TRdxLines): string;
var
  Li, Co : Integer;
  Stack  : string;
  Arg    : Boolean;
begin
  Result := '';
  Stack := '';
  for Li := ALines.Top to ALines.Bottom do
    for Co := 1 to Length(AMap.Raw(Li)) do
      if OpensDirective(AMap, Li, Co) then
      begin
        Result := BalanceStep(Stack, DirectiveWord(AMap, Li, Co, Arg), Li);
        if Result <> '' then Exit;
      end;
  if Stack <> '' then
    Result := 'Direktive ohne Gegenstueck im Bereich ($IF.. ohne $ENDIF bzw. '
      + '$REGION ohne $ENDREGION)';
end;

{ ---- Was die Datei sonst ueber den Namen sagt ---- }

// Die letzte Spalte des Laufs gleicher Zeichenklasse ab (ALine, ACol).
function RunEnd(AMap: TRdxCodeMap; ALine, ACol: Integer): Integer;
var
  K : Char;
begin
  K := AMap.ClassAt(ALine, ACol);
  Result := ACol;
  while AMap.ClassAt(ALine, Result + 1) = K do
    Inc(Result);
end;

{ TRdxFactScan }

function TRdxFactScan.InOwn(ALine: Integer): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := Low(Own) to High(Own) do
    if (ALine >= Own[i].Top) and (ALine <= Own[i].Bottom) then
      Exit(True);
end;

procedure TRdxFactScan.Directive(AMap: TRdxCodeMap; ALine, ACol: Integer);
var
  W, Text : string;
  Arg     : Boolean;
begin
  W := DirectiveWord(AMap, ALine, ACol, Arg);
  if Arg and InList(W, LINK_WORDS) and (Facts.LinksObject = 0) then
    Facts.LinksObject := ALine;
  if Arg and InList(W, INCLUDE_WORDS) and (ALine > ImplLine)
     and (Facts.ImplInclude = 0) then
    Facts.ImplInclude := ALine;
  if (W = 'rtti') and (Facts.Rtti = 0) then
    Facts.Rtti := ALine;
  Text := LowerCase(Copy(AMap.Raw(ALine), ACol,
    RunEnd(AMap, ALine, ACol) - ACol + 1));
  if (Facts.NameDirective = 0) and not InOwn(ALine)
     and HasIdentWord(Text, LowName) then
    Facts.NameDirective := ALine;
end;

procedure TRdxFactScan.Literal(AMap: TRdxCodeMap; ALine, ACol, AEnd: Integer);
begin
  if (Facts.NameLiteral = 0) and not InOwn(ALine)
     and HasIdentWord(LowerCase(Copy(AMap.Raw(ALine), ACol, AEnd - ACol + 1)),
       LowName) then
    Facts.NameLiteral := ALine;
end;

// Eine Durchsicht aller Zeilen: String-Literale und Direktiven (s.
// TRdxFileFacts). AOwn und AOther: die geloeschten Bereiche.
function FileFacts(AMap: TRdxCodeMap; const ALowName: string;
  AImplLine: Integer; const AOwn, AOther: TRdxLines): TRdxFileFacts;
var
  Scan       : TRdxFactScan;
  Li, Co, E  : Integer;
begin
  Scan := Default(TRdxFactScan);
  Scan.LowName := ALowName;
  Scan.ImplLine := AImplLine;
  Scan.Own[0] := AOwn;
  Scan.Own[1] := AOther;
  for Li := 1 to AMap.LineCount do
  begin
    Co := 1;
    while Co <= Length(AMap.Raw(Li)) do
    begin
      E := Co;
      if AMap.ClassAt(Li, Co) = 's' then
      begin
        E := RunEnd(AMap, Li, Co);
        Scan.Literal(AMap, Li, Co, E);
      end
      else if OpensDirective(AMap, Li, Co) then
        Scan.Directive(AMap, Li, Co);
      Co := E + 1;
    end;
  end;
  Result := Scan.Facts;
end;

// Name im String-Literal oder in einer Direktive. '' oder der Grund.
function NameFactsReason(const F: TRdxFileFacts; const AName: string): string;
begin
  Result := '';
  if F.NameLiteral > 0 then
    Result := Format('%s steht in einem String-Literal (Zeile %d) - Aufruf '
      + 'per Name (GetProcAddress, MethodAddress, RTTI, Skript)?',
      [AName, F.NameLiteral])
  else if F.NameDirective > 0 then
    Result := Format('eine Direktive nennt %s (Zeile %d)',
      [AName, F.NameDirective]);
end;

// Ein Lauf ueber alle Code-Token: 'implementation' und jedes Vorkommen von
// ALowName als Wort - auch in inaktiven $IFDEF-Zweigen (die Code-Sicht
// wertet keine Direktiven aus). Umlaute vergleicht SameIdent ohne Gross/
// klein (Verdacht 1 des Gegen-Reviews H3: ein Aufruf mit grossem Umlaut
// zaehlte nicht, die Hilfe loeschte die gerufene Routine).
function ScanName(AMap: TRdxCodeMap; const ALowName: string): TRdxNameScan;
var
  T, P : TRdxToken;
begin
  Result := Default(TRdxNameScan);
  P := Default(TRdxToken);
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    if SameIdent(T.Low, ALowName) then
      AddToken(Result.Hits, T)
    else if (T.Low = 'implementation') and (Result.Impl.Low = '')
       and IsKeywordAfter(T, P) then
      Result.Impl := T;
    P := T;
    T := After(AMap, T);
  end;
end;

// Steht AHit in einer exports-Klausel? Rueckwaerts bis zum ';'.
function InExports(AMap: TRdxCodeMap; const AHit: TRdxToken): Boolean;
var
  T : TRdxToken;
  n : Integer;
begin
  Result := False;
  T := Before(AMap, AHit);
  n := 0;
  while (T.Low <> '') and (T.Low <> KW_SEMI) and (n < MAX_BACK) do
  begin
    if T.Low = 'exports' then
      Exit(True);
    T := Before(AMap, T);
    Inc(n);
  end;
end;

// Warum das Vorkommen AHit des Namens die Hilfe sperrt. AImplLine = 0:
// kein interface-Grund (SCA147 - die Klasse steht oft im interface-Teil).
function HitReason(AMap: TRdxCodeMap; const AHit: TRdxToken;
  const AName: string; AImplLine: Integer): string;
var
  P : TRdxToken;
begin
  P := Before(AMap, AHit);
  if AHit.Line < AImplLine then
    Result := Format('%s steht im interface-Teil (Zeile %d) - exportiert, '
      + 'Aufrufer in anderen Units moeglich', [AName, AHit.Line])
  else if InExports(AMap, AHit) then
    Result := Format('die exports-Klausel nennt %s (Zeile %d)',
      [AName, AHit.Line])
  else if IsRoutineHead(AMap, P) then
    Result := Format('zweite Routine %s in Zeile %d - Overload, '
      + '$IFDEF-Zwilling oder Deklaration', [AName, AHit.Line])
  else if InList(P.Low, ACCESSOR_WORDS) then
    Result := Format('%s ist Accessor einer Property (Zeile %d)',
      [AName, AHit.Line])
  else
    Result := Format('%s wird in Zeile %d verwendet - Fund veraltet? Datei '
      + 'neu pruefen', [AName, AHit.Line]);
end;

// Der Name aus der Meldung zwischen AKey und ' appears unused'; '' ohne
// diese Form.
function NameFromMessage(const AMessage, AKey: string): string;
var
  E : Integer;
begin
  Result := '';
  E := Pos(KEY_UNUSED, AMessage);
  if (Pos(AKey, AMessage) = 1) and (E > Length(AKey) + 1) then
    Result := Trim(Copy(AMessage, Length(AKey) + 1, E - Length(AKey) - 1));
end;

// Der eine Kopf mit dem Namen AName auf ALine (AWhat: was gesucht wird,
// fuer den Grund). '' oder der Grund; AHead ist der Kopfanfang.
function HeadOn(AMap: TRdxCodeMap; ALine: Integer; const AName,
  AWhat: string; out AHead: TRdxToken): string;
var
  S : TRdxLineSearch;
  K : TRdxToken;
begin
  AHead := Default(TRdxToken);
  S := Default(TRdxLineSearch);
  S.Test := IsHeadNamed;
  S.Arg := LowerCase(AName);
  S.What := Format('kein Kopf %s %s', [AWhat, AName]);
  S.ManyFmt := '%d Koepfe ' + AWhat + ' ' + AName;
  Result := OneTokenOnLine(AMap, ALine, S, K);
  if Result = '' then
    AHead := HeadStart(AMap, K);
end;

{ ---- SCA164 ---- }

// Ist AHit der Name einer forward-Deklaration im implementation-Teil? Dann
// AFwd.
function ForwardAt(AMap: TRdxCodeMap; const AHit: TRdxToken;
  AImplLine: Integer; out AFwd: TRdxRoutine): Boolean;
var
  K : TRdxToken;
  W : string;
begin
  AFwd := Default(TRdxRoutine);
  K := Before(AMap, AHit);
  Result := (AHit.Line > AImplLine) and IsRoutineHead(AMap, K)
    and (ReadRoutineAt(AMap, HeadStart(AMap, K), 0, AFwd) = '')
    and (Length(AFwd.Parts) = 1)
    and HasDirective(AFwd, ['forward'], W);
end;

// Die Vorkommen des Namens ausserhalb der Routine R: EINE
// forward-Deklaration (AFwd; Head.Low = '' ohne) geht mit, jedes andere
// sperrt. '' oder der Grund.
function OutsideHits(AMap: TRdxCodeMap; const AScan: TRdxNameScan;
  const R: TRdxRoutine; out AFwd: TRdxRoutine): string;
var
  H : TRdxToken;
  F : TRdxRoutine;
begin
  Result := '';
  AFwd := Default(TRdxRoutine);
  for H in AScan.Hits do
  begin
    if TokInRange(H, R.Head, R.Last) then Continue;
    if (AFwd.Head.Low = '') and ForwardAt(AMap, H, AScan.Impl.Line, F) then
    begin
      AFwd := F;
      Continue;
    end;
    Exit(HitReason(AMap, H, R.Name, AScan.Impl.Line));
  end;
end;

// Eine freie Routine mit Rumpf, von aussen nicht erreichbar? '' oder Grund.
function FreeRoutineReason(const R: TRdxRoutine): string;
var
  W : string;
begin
  Result := '';
  if (Length(R.Parts) > 1) or (R.Head.Low = KW_CLASS)
     or InList(R.Keyword.Low, CTOR_DTOR) then
    Result := 'Methode einer Klasse - die meldet SCA147 bzw. SCA148'
  else if R.Keyword.Low = KW_OPERATOR then
    // FPC: globaler Operator ('operator explicit(A: TFoo): Integer;') - bis
    // Charge H3c hiess auch er "Methode einer Klasse" (Gegen-Review H3,
    // Minor 12).
    Result := 'globaler Operator (FPC) - der Compiler ruft ihn ueber sein '
      + 'Zeichen bzw. die Umwandlung, nicht ueber den Namen'
  else if HasDirective(R, REACHABLE_DIRECTIVES, W) then
    Result := Format('Direktive %s - die Routine ist von aussen erreichbar '
      + 'oder hat keinen Rumpf', [W]);
end;

// SCA164: {$L}, {$I} im implementation-Teil, Name in Literal/Direktive.
function RoutineFactsReason(const F: TRdxFileFacts; const AName: string): string;
begin
  if F.LinksObject > 0 then
    Result := Format('die Unit linkt eine Objektdatei ({$L} in Zeile %d) - '
      + 'der C-Code ruft Routinen per Name', [F.LinksObject])
  else if F.ImplInclude > 0 then
    Result := Format(R_IMPL_INCLUDE, [F.ImplInclude])
  else
    Result := NameFactsReason(F, AName);
end;

// Die Zeilen der forward-Deklaration AFwd (ohne: ALines bleibt 0..0). ''
// oder der Grund.
function ForwardLines(AMap: TRdxCodeMap; const AFwd: TRdxRoutine;
  out ALines: TRdxLines): string;
begin
  ALines := Default(TRdxLines);
  if AFwd.Head.Low = '' then Exit('');
  Result := HeadLines(AMap, AFwd, abDocOnly, ALines);
  if Result = '' then
    Result := DirectiveBalance(AMap, ALines);
  if Result <> '' then
    Result := 'forward-Deklaration: ' + Result;
end;

// Die Dateien der Include-Direktiven in den Zeilen 1..ALast, der Reihe
// nach - ohne die im Kopf der Unit: folgt einem Include 'unit', 'interface'
// oder 'uses', darf es nur tragen, was davor stehen darf, Direktiven und
// Kommentare (eine Deklaration davor waere ein Fehler - uses ist die erste
// Klausel, E2029). Es kann die Routine weder deklarieren noch rufen; so
// stehen die Konfigurations-Includes 'jcl.inc', 'jvcl.inc', 'CnWizards.inc'
// (Korpus: im Kopf, meist in einem anderen Verzeichnis als die Unit).
function IncludesUpTo(AMap: TRdxCodeMap; ALast: Integer): TArray<string>;
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
           and not InList(NextToken(AMap, Li, Co).Low, HEADER_FOLLOWERS) then
          AddText(Result, F);
      end;
end;

// Der Plan fuer die freie Routine R: Nachweis am Puffer, Bereiche,
// Ersetzungen (die forward-Deklaration zuerst). '' oder der Grund.
function PlanRoutine(AMap: TRdxCodeMap; const R: TRdxRoutine;
  var APlan: TRdxRoutinePlan): string;
var
  Scan       : TRdxNameScan;
  Fwd        : TRdxRoutine;
  Main, FwdL : TRdxLines;
begin
  FwdL := Default(TRdxLines);
  Scan := ScanName(AMap, LowerCase(R.Name));
  if (Scan.Impl.Low = '') or TokBefore(R.Head, Scan.Impl) then
    Exit('der Kopf steht nicht im implementation-Teil (interface oder '
      + 'Programm) - von aussen erreichbar');
  Result := OutsideHits(AMap, Scan, R, Fwd);
  if Result = '' then
    Result := ForwardLines(AMap, Fwd, FwdL);
  if Result = '' then
    Result := HeadLines(AMap, R, abComments, Main);
  if Result <> '' then Exit;
  TakeBlankLine(AMap, Main, FwdL.Bottom);
  Result := RoutineFactsReason(FileFacts(AMap, LowerCase(R.Name),
    Scan.Impl.Line, Main, FwdL), R.Name);
  if Result = '' then
    Result := DirectiveBalance(AMap, Main);
  if Result = '' then
    Result := MarkerLinesReason(AMap, Main);
  if (Result = '') and (FwdL.Top > 0) then
    Result := MarkerLinesReason(AMap, FwdL);
  if Result <> '' then Exit;
  if FwdL.Top > 0 then
    AddEdit(APlan.Edits, LinesEdit(AMap, FwdL, SPAN_164));
  AddEdit(APlan.Edits, LinesEdit(AMap, Main, SPAN_164));
  // Die Zeile von 'implementation' zaehlt mit: dort vor oder hinter dem
  // Wort sieht FileFacts (ImplInclude ab der Zeile danach) es nicht.
  APlan.Includes := IncludesUpTo(AMap, Scan.Impl.Line);
end;

{ ---- SCA147 ---- }

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

// Erreicht jemand die Methode ohne ihren Namen? '' oder der Grund.
function DispatchReason(const D: TRdxRoutine): string;
var
  W : string;
begin
  Result := '';
  if HasDirective(D, DISPATCH_DIRECTIVES, W) then
    Result := Format('Direktive %s - Vorfahren, Nachfahren, Nachrichten oder '
      + 'Overload-Geschwister erreichen die Methode ohne ihren Namen', [W])
  else if InList(D.Keyword.Low, NO_SPECIAL) then
    Result := Format('%s - verdeckt Geerbtes bzw. wird ohne Namen gerufen; '
      + 'von Hand pruefen', [D.Keyword.Low]);
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

// Das end des Klassenrumpfs ab AClass; Low = '' ohne.
function ClassEnd(AMap: TRdxCodeMap; const AClass: TRdxToken): TRdxToken;
var
  Scan : TRdxClassScan;
  P    : TRdxToken;
begin
  Scan := Default(TRdxClassScan);
  Scan.Depth := 1;
  P := AClass;
  Result := After(AMap, AClass);
  while Result.Low <> '' do
  begin
    Scan.Step(AMap, Result, P);
    if Scan.Depth = 0 then Exit;
    P := Result;
    Result := After(AMap, Result);
  end;
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
  Scan.Depth := 1;
  P := AClass;
  T := After(AMap, AClass);
  while (T.Low <> '') and (Scan.Depth > 0) do
  begin
    if SameTok(T, AHead) then
    begin
      AVis := Scan.Vis;
      Exit(Scan.Depth = 1);
    end;
    Scan.Step(AMap, T, P);
    P := T;
    T := After(AMap, T);
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
  Scan.Depth := 1;
  P := AClass;
  T := After(AMap, AClass);
  while (T.Low <> '') and (Scan.Depth > 0) do
  begin
    if (Scan.Depth = 1) and IsHeadNamed(AMap, T, ALowName) then
      AddToken(AHeads, HeadStart(AMap, T));
    Scan.Step(AMap, T, P);
    P := T;
    T := After(AMap, T);
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

// 'T [<..>] = interface' bzw. dispinterface: das Token 'interface'; Low =
// '' ohne diese Form.
function InterfaceKindAt(AMap: TRdxCodeMap; const T: TRdxToken): TRdxToken;
var
  N : TRdxToken;
begin
  Result := Default(TRdxToken);
  N := After(AMap, T);
  if N.Low = '<' then
    N := AfterClose(AMap, N);
  if N.Low <> '=' then Exit;
  N := After(AMap, N);
  if InList(N.Low, INTERFACE_KINDS) then
    Result := N;
end;

// Deklariert die Datei 'ALowName [<..>] = interface' (bzw. dispinterface)?
// AParents bekommt die Vorfahren jeder solchen Deklaration dazu (die
// Vorwaerts-Deklaration 'IFoo = interface;' traegt keine, die volle schon).
// Der Name wird genau verglichen - ein Treffer zu viel hiesse hier "lokal",
// also weniger Sperre.
function InterfaceParents(AMap: TRdxCodeMap; const ALowName: string;
  var AParents: TArray<string>): Boolean;
var
  T, K  : TRdxToken;
  Names : TArray<string>;
  S     : string;
begin
  Result := False;
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    K := Default(TRdxToken);
    if T.Low = ALowName then
      K := InterfaceKindAt(AMap, T);
    if K.Low <> '' then
    begin
      Result := True;
      Names := HeritageNames(AMap, K);
      for S in Names do
        AddText(AParents, S);
    end;
    T := After(AMap, T);
  end;
end;

// 'IFoo' -> True, 'Item' -> False: die Delphi-Konvention I +
// Grossbuchstabe, in Original-Schreibung (wie der Detektor,
// Sca147IsInterfaceStyleName).
function InterfaceStyle(const S: string): Boolean;
begin
  Result := (Length(S) >= 2) and (S[1] = 'I') and CharInSet(S[2], ['A'..'Z']);
end;

// Die Interfaces der Vorfahrenliste: ab dem zweiten Eintrag jeder (Delphi-
// Grammatik), der erste nur, wenn er wie ein Interface heisst oder in der
// Datei als Interface steht - 'class(IFremd)' hat die Basis TObject.
function ImplementedInterfaces(AMap: TRdxCodeMap;
  const AClass: TRdxToken): TArray<string>;
var
  Names, Dummy : TArray<string>;
  i            : Integer;
begin
  Result := nil;
  Dummy := nil;
  Names := HeritageNames(AMap, AClass);
  for i := 0 to High(Names) do
    if (i > 0) or InterfaceStyle(Names[i])
       or InterfaceParents(AMap, LowerCase(Names[i]), Dummy) then
      AddText(Result, Names[i]);
end;

// Gehoert ALowMethod zu den Membern der System-Wurzel ALowRoot
// (IInterface/IUnknown bzw. IDispatch)?
function RootMember(const ALowRoot, ALowMethod: string): Boolean;
begin
  Result := InList(ALowMethod, ROOT_MEMBERS)
    or ((ALowRoot = 'idispatch') and InList(ALowMethod, DISPATCH_MEMBERS));
end;

// Ein Interface AName der Arbeitsliste: eine Wurzel (nur ein Name aus
// ihren Membern sperrt) oder in der Datei deklariert (seine Vorfahren
// kommen an AWork) - sonst aus einer anderen Unit. '' oder der Grund.
function InterfaceReason(AMap: TRdxCodeMap; const AName, ALowMethod: string;
  var AWork: TArray<string>): string;
var
  Key, P  : string;
  Parents : TArray<string>;
begin
  Result := '';
  Key := LowerCase(AName);
  Parents := nil;
  if InList(Key, ROOT_INTERFACES) then
  begin
    if RootMember(Key, ALowMethod) then
      Result := Format('%s ist ein Member von %s - die Methode kann es '
        + 'implementieren', [ALowMethod, AName]);
  end
  else if InterfaceParents(AMap, Key, Parents) then
  begin
    for P in Parents do
      AddText(AWork, P);
  end
  else
    Result := Format('die Klasse implementiert %s (nicht in dieser Datei '
      + 'deklariert) - die Methode kann ein Interface-Member sein', [AName]);
end;

// Ein Interface der Klasse aus einer anderen Unit - direkt oder als
// Vorfahr eines Interfaces dieser Datei? Dann kann die Methode eines seiner
// Member sein (Aufruf ueber das Interface, ohne Namen in dieser Unit). Gate
// E des Detektors nachgebildet (Sca147TryResolveIfaceMembers; Gegen-Review
// H3, Minor 2 - bis Charge H3c fehlten 'class(IFremd)' und die Vorfahren
// lokaler Interfaces, nach der Hilfe E2291): jedes lokale Interface bringt
// seine Vorfahren mit; IInterface/IUnknown/IDispatch sind bekannt - dort
// sperrt nur ein Methodenname aus ihren Membern. Die Member lokaler
// Interfaces findet schon die Namenssuche (Vorkommen ausserhalb von
// Deklaration und Implementierung). '' oder der Grund.
function ForeignInterfaceReason(AMap: TRdxCodeMap; const AClass: TRdxToken;
  const ALowMethod: string): string;
var
  Work, Seen : TArray<string>;
  i          : Integer;
  Name       : string;
begin
  Result := '';
  Seen := nil;
  Work := ImplementedInterfaces(AMap, AClass);
  i := 0;
  while (Result = '') and (i < Length(Work)) do
  begin
    Name := Work[i];
    Inc(i);
    if InList(LowerCase(Name), Seen) then Continue;
    AddText(Seen, LowerCase(Name));
    if Length(Seen) > MAX_INTERFACES then
      Exit('Interface-Kette zu lang - Grenzen nicht sicher');
    Result := InterfaceReason(AMap, Name, ALowMethod, Work);
  end;
end;

// Klasse, Sichtbarkeit, Attribute, Interfaces und Zahl der Deklarationen.
// '' oder der Grund.
function MethodContextReason(AMap: TRdxCodeMap; const D: TRdxRoutine;
  const AClassPath: string): string;
var
  C       : TRdxClassHead;
  Decls   : TArray<TRdxToken>;
  IncLine : Integer;
begin
  if not EnclosingClass(AMap, D.Head, LowerCase(LastPart(AClassPath)), C) then
    Exit(Format('die Deklaration steht nicht im Rumpf der Klasse %s - Zeile '
      + 'verschoben? Datei neu pruefen', [AClassPath]));
  if not InList(C.Vis, PRIVATE_SECTIONS) then
  begin
    if C.Vis = '' then
      C.Vis := 'Vorgabe ohne Abschnitt';
    Exit(Format('die Methode steht unter "%s", nicht unter private',
      [C.Vis]));
  end;
  if (Before(AMap, C.NameTok).Low = ']') or (Before(AMap, D.Head).Low = ']') then
    Exit('Attribut an Klasse oder Methode - RTTI kann die Methode per Name '
      + 'finden');
  Decls := TRdxRoutineFixes.FindMethodDecls(AMap, AClassPath, D.Name);
  if Length(Decls) <> 1 then
    Exit(Format('%d Deklarationen von %s in Klassen dieses Namens - '
      + 'Overload?', [Length(Decls), D.Name]));
  // Ein Include im Klassenrumpf kann eine Property mit 'read X' tragen -
  // der Detektor prueft nur Includes im implementation-Teil (Gate F).
  IncLine := IncludeInLines(AMap, C.ClassTok.Line,
    ClassEnd(AMap, C.ClassTok).Line);
  if IncLine > 0 then
    Exit(Format('{$I}-Include im Klassenrumpf (Zeile %d) - dort kann die '
      + 'Methode stehen (Property-Accessor)', [IncLine]));
  Result := ForeignInterfaceReason(AMap, C.ClassTok, LowerCase(D.Name));
end;

// Die eine Implementierung der Methode, gelesen bis zu ihrem Ende. '' oder
// der Grund.
function MethodImplOf(AMap: TRdxCodeMap; const AClassPath: string;
  const D: TRdxRoutine; out R: TRdxRoutine): string;
var
  Heads : TArray<TRdxToken>;
begin
  R := Default(TRdxRoutine);
  Heads := TRdxRoutineFixes.FindMethodImpls(AMap, AClassPath, D.Name);
  if Length(Heads) = 0 then
    Exit(Format('keine Implementierung von %s.%s in der Datei (include-Datei? '
      + 'abstract?)', [AClassPath, D.Name]));
  if Length(Heads) > 1 then
    Exit(Format('%d Implementierungen von %s.%s - Overload?',
      [Length(Heads), AClassPath, D.Name]));
  Result := ReadRoutineAt(AMap, Heads[0], 0, R);
  if Result <> '' then
    Result := 'Implementierung: ' + Result;
end;

// Jedes Vorkommen des Namens ausser Deklaration und Implementierung
// sperrt. '' oder der Grund.
function MethodHitsReason(AMap: TRdxCodeMap; const AScan: TRdxNameScan;
  const D, R: TRdxRoutine): string;
var
  H : TRdxToken;
begin
  Result := '';
  for H in AScan.Hits do
    if not (SameTok(H, D.NameTok) or TokInRange(H, R.Head, R.Last)) then
      Exit(HitReason(AMap, H, D.Name, 0));
end;

// SCA147: {$RTTI}, {$I} im implementation-Teil, Name in Literal/Direktive.
function MethodFactsReason(const F: TRdxFileFacts; const AName: string): string;
begin
  if F.Rtti > 0 then
    Result := Format('{$RTTI} in Zeile %d - erweiterte RTTI kann private '
      + 'Methoden per Name aufrufen', [F.Rtti])
  else if F.ImplInclude > 0 then
    Result := Format(R_IMPL_INCLUDE, [F.ImplInclude])
  else
    Result := NameFactsReason(F, AName);
end;

// Der Plan fuer Deklaration D und Implementierung R. '' oder der Grund.
function PlanMethod(AMap: TRdxCodeMap; const D, R: TRdxRoutine;
  var APlan: TRdxRoutinePlan): string;
var
  Scan          : TRdxNameScan;
  DeclL, ImplL  : TRdxLines;
begin
  Scan := ScanName(AMap, LowerCase(D.Name));
  if (Scan.Impl.Low = '') or TokBefore(R.Head, Scan.Impl) then
    Exit('die Implementierung steht nicht im implementation-Teil');
  Result := MethodHitsReason(AMap, Scan, D, R);
  if Result = '' then
    Result := HeadLines(AMap, D, abDocOnly, DeclL);
  if Result = '' then
    Result := HeadLines(AMap, R, abComments, ImplL);
  if Result <> '' then Exit;
  TakeBlankLine(AMap, ImplL, DeclL.Bottom);
  Result := MethodFactsReason(FileFacts(AMap, LowerCase(D.Name),
    Scan.Impl.Line, ImplL, DeclL), D.Name);
  if Result = '' then
    Result := DirectiveBalance(AMap, DeclL);
  if Result = '' then
    Result := DirectiveBalance(AMap, ImplL);
  if (Result = '') and (DeclL.Bottom >= ImplL.Top) then
    Result := 'Deklaration und Implementierung ueberlappen';
  if Result = '' then
    Result := MarkerLinesReason(AMap, DeclL);
  if Result = '' then
    Result := MarkerLinesReason(AMap, ImplL);
  if Result <> '' then Exit;
  AddEdit(APlan.Edits, LinesEdit(AMap, DeclL, SPAN_147));
  AddEdit(APlan.Edits, LinesEdit(AMap, ImplL, SPAN_147));
  // Includes vor implementation wie bei SCA164 (Gegen-Review R4-05): eines
  // ausserhalb des Klassenrumpfs kann eine Nachfahrenklasse mit 'property
  // P read X' tragen - private ist in der ganzen Unit sichtbar; nach dem
  // Loeschen E2003 im Include. Der Detektor liest sie nicht (Gate F nur
  // hinter implementation), die Includes im Klassenrumpf lehnt schon
  // MethodContextReason ab. Der Check der Tabelle liest sie neben der Unit
  // (IncludeReason): nennt eines den Namen oder fehlt es, keine Hilfe.
  APlan.Includes := IncludesUpTo(AMap, Scan.Impl.Line);
end;

{ ---- SCA164/SCA147 (und SCA014): Include-Dateien vor implementation ---- }

{$IFDEF MSWINDOWS}
// GetDriveType aus kernel32, selbst deklariert statt Winapi.Windows: die
// Unit braechte Tausende Namen in den Planer (vor System.SysUtils
// verdeckte sie FindClose u. a.), und der FPC-Pruefstand kennt
// Winapi.Windows nicht (FPC: Windows).
function GetDriveTypeW(lpRootPathName: PWideChar): Cardinal; stdcall;
  external 'kernel32.dll' name 'GetDriveTypeW';
{$ENDIF}

// Ist ADrive ('Z:') ein Netzlaufwerk? GetDriveType fragt die
// Laufwerkstabelle von Windows, nicht den Server - auch ein getrenntes
// Netzlaufwerk antwortet sofort.
function IsRemoteDrive(const ADrive: string): Boolean;
begin
  {$IFDEF MSWINDOWS}
  Result := GetDriveTypeW(PWideChar(ADrive + '\')) = DRIVE_KIND_REMOTE;
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

function IsNetworkPath(const APath: string): Boolean;
begin
  if (Length(APath) > 2) and CharInSet(APath[1], ['\', '/'])
     and CharInSet(APath[2], ['\', '/']) then
    Exit(True);
  Result := (Length(APath) >= 2) and (APath[2] = ':')
    and CharInSet(APath[1], ['A'..'Z', 'a'..'z'])
    and IsRemoteDrive(Copy(APath, 1, 2));
end;

// Der Teil von APath, der ihn zum Netzpfad macht ('\\server\share' bzw.
// 'Z:'), fuer den Grund.
function NetworkRoot(const APath: string): string;
begin
  Result := ExtractFileDrive(APath);
  if Result = '' then
    Result := APath;
end;

// Die Datei AFile eines Includes, relativ zu ADir (Verzeichnis mit
// Trenner); ohne Endung auch mit .inc bzw. .pas wie die Compiler. '' wenn
// keine da ist.
function IncludePath(const ADir, AFile: string): string;
var
  Ext : string;
begin
  Result := AFile;
  if (ExtractFileDrive(AFile) = '')
     and ((AFile = '') or not CharInSet(AFile[1], ['\', '/'])) then
    Result := ADir + AFile;
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
// Lesen, Kodierung - wie die Formdatei in uRdxFixTable).
function ReadIncludeText(const APath: string; ALines: TStringList): Boolean;
begin
  Result := True;
  try
    ALines.LoadFromFile(APath);
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

// SCA164: nennt das Include AFile die Routine AArg als Wort? '' oder der
// Grund (TRdxIncludeTest).
function NameInInclude(const AFile: string; ALines: TStrings;
  AMap: TRdxCodeMap; const AArg: string): string;
begin
  Result := '';
  if HasIdentWord(LowerCase(ALines.Text), LowerCase(AArg)) then
    Result := Format('das Include %s nennt %s - eine Deklaration im '
      + 'interface-Teil (nach dem Loeschen E2065) oder ein Aufruf, den die '
      + 'Hilfe nicht sieht', [AFile, AArg]);
end;

{ TRdxRoutineFixes }

class function TRdxRoutineFixes.IncludeReason(const AUnitFile: string;
  const AIncludes: TArray<string>; const AName: string): string;
var
  Check : TRdxIncludeCheck;
begin
  Check.Test := NameInInclude;
  Check.Arg := AName;
  Check.MissingFmt := R_INC_MISSING;
  Result := IncludeChainReason(AUnitFile, AIncludes, Check);
end;

class function TRdxRoutineFixes.ReadRoutine(AMap: TRdxCodeMap;
  const AHead: TRdxToken; out ARoutine: TRdxRoutine): string;
var
  H : TRdxToken;
begin
  H := AHead;
  if InList(AHead.Low, ROUTINE_WORDS) then
    H := HeadStart(AMap, AHead);
  Result := ReadRoutineAt(AMap, H, 0, ARoutine);
end;

class function TRdxRoutineFixes.FindMethodDecls(AMap: TRdxCodeMap;
  const AClassPath, AMethod: string): TArray<TRdxToken>;
var
  C : TRdxToken;
begin
  Result := nil;
  for C in FindClassHeads(AMap, AClassPath) do
    AddMemberHeads(AMap, C, LowerCase(AMethod), Result);
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

class function TRdxRoutineFixes.FindMethodImpls(AMap: TRdxCodeMap;
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

class function TRdxRoutineFixes.MethodDecl(AMap: TRdxCodeMap;
  const AHead: TRdxToken; out ADecl: TRdxRoutine): string;
begin
  Result := ReadMethodDecl(AMap, AHead, ADecl);
end;

class function TRdxRoutineFixes.FindClassHeads(AMap: TRdxCodeMap;
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

class function TRdxRoutineFixes.HeritageOf(AMap: TRdxCodeMap;
  const AClass: TRdxToken): TArray<string>;
begin
  Result := HeritageNames(AMap, AClass);
end;

class function TRdxRoutineFixes.UnusedRoutine(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxRoutinePlan;
  out AReason: string): Boolean;
var
  Head : TRdxToken;
  R    : TRdxRoutine;
begin
  APlan := Default(TRdxRoutinePlan);
  R := Default(TRdxRoutine);
  APlan.Name := NameFromMessage(AMessage, KEY_ROUTINE);
  if APlan.Name = '' then
    AReason := 'Name der Routine fehlt in der Meldung'
  else
    AReason := HeadOn(AMap, ALine, APlan.Name, 'der Routine', Head);
  if AReason = '' then
    AReason := ReadRoutineAt(AMap, Head, 0, R);
  if AReason = '' then
    AReason := FreeRoutineReason(R);
  if AReason = '' then
  begin
    APlan.Name := R.Name;
    AReason := PlanRoutine(AMap, R, APlan);
  end;
  if AReason <> '' then
    APlan.Edits := nil;
  Result := AReason = '';
end;

class function TRdxRoutineFixes.UnusedPrivateMethod(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxRoutinePlan;
  out AReason: string): Boolean;
var
  Full, ClassPath : string;
  Head            : TRdxToken;
  D, R            : TRdxRoutine;
begin
  APlan := Default(TRdxRoutinePlan);
  D := Default(TRdxRoutine);
  R := Default(TRdxRoutine);
  Full := NameFromMessage(AMessage, KEY_METHOD);
  ClassPath := Copy(Full, 1, LastDelimiter('.', Full) - 1);
  APlan.Name := LastPart(Full);
  if (ClassPath = '') or (APlan.Name = '') then
    AReason := 'Klasse oder Methode fehlt in der Meldung'
  else
    AReason := HeadOn(AMap, ALine, APlan.Name, 'der Methode', Head);
  if AReason = '' then
    AReason := ReadMethodDecl(AMap, Head, D);
  if AReason = '' then
    AReason := DispatchReason(D);
  if AReason = '' then
    AReason := MethodContextReason(AMap, D, ClassPath);
  if AReason = '' then
    AReason := MethodImplOf(AMap, ClassPath, D, R);
  if AReason = '' then
  begin
    APlan.Name := D.Name;
    AReason := PlanMethod(AMap, D, R, APlan);
  end;
  if AReason <> '' then
    APlan.Edits := nil;
  Result := AReason = '';
end;

class function TRdxRoutineFixes.FormNamesMethod(const AFormText,
  AName: string): Boolean;
begin
  Result := HasIdentWord(LowerCase(AFormText), LowerCase(AName));
end;

end.

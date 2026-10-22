unit uRdxResultFixes;

// reDelphix - Quick-Fixes "Ergebnis", OHNE ToolsAPI und ohne Parser
// (Konzept_Editorhilfen_Recherche_2026-10-11, Abschnitt 5 Bausteine
// "Routinengrenzen" und "Result := Default(T)-Einfueger", Abschnitt 6
// Charge H5). Die Konstruktor- und Destruktor-Planer derselben Charge
// (SCA096, SCA097) stehen seit Review Woche G08-04 in uRdxInheritedFixes
// - bis dahin hiess diese Unit "Ergebnis und Konstruktoren"; was beide
// fragen, ist hier oeffentlich (s. GETEILT).
//
//   SCA121 RoutineResultUnassigned: 'Result := <Wert>;' als erste
//          Anweisung, der Wert nach dem Rueckgabetyp T (aus dem Kopf bzw.
//          bei einem Implementierungskopf ohne Signatur aus der Deklaration
//          im Klassenrumpf): ein Literal, wo der Typ es traegt - False,
//          0, '''', #0, nil, [] bzw. System.Low(T) fuer eine schlichte
//          Aufzaehlung der Unit (InitValueFor; Typen der Unit nur auf
//          Unit-Ebene) -, sonst Default(T) (Records, Typparameter,
//          Unbekanntes, ein Name, den die Unit auch lokal in einer anderen
//          Routine bzw. geschachtelt definiert). Default() gibt es erst ab
//          Delphi 2009 bzw. FPC 3.0 - eine Datei mit Spuren aelterer
//          Compiler bekommt es nicht
//          (OldCompilerTrace; Gegen-Review H5, Minor 4: 96 der 132
//          Angebote lagen in JVCL/CnWizards, die ab Delphi 5/6 bauen).
//          Gekennzeichnet: Result ist danach definiert statt zufaellig;
//          spaetere Zuweisungen gelten weiter, die Einfuegung am Anfang
//          ueberschreibt nichts.
//   SCA196 ManagedResultUninit: als erste Anweisung 'Result := '''';'
//          (string-Familie, ShortString), 'Result := nil;' (TArray<>,
//          TBytes, *DynArray, Interface) bzw. 'VarClear(Result);' (Variant,
//          OleVariant - fehlt Variants in uses, ergaenzt sie der Aufrufer,
//          uRdxFixTable). Deklariert die Unit den Typnamen selbst, gilt nur
//          ihre Definition auf Unit-Ebene; eine lokale bzw. geschachtelte
//          sperrt (OwnTypeStatement). Die Meldung zeigt auf die
//          LESE-Zeile; Kopf und begin sucht der Planer (innerste Routine um
//          die Zeile, Name und Rueckgabetyp wie in der Meldung).
//          Gekennzeichnet: Result haengt danach nicht mehr am alten Inhalt
//          der Zielvariable des Aufrufers.
//
// BAUSTEINE (geteilt mit spaeteren Hilfen):
//   FirstStatement  AStmt als erste Anweisung des begin-Rumpfs: eine eigene
//                   Zeile hinter der begin-Zeile, eingerueckt wie die erste
//                   Anweisung (beginnt sie eine eigene Zeile), sonst begin +
//                   eine Stufe (IndentStep). Steht hinter begin auf seiner
//                   Zeile Code oder eine Direktive - auch der Einzeiler
//                   'begin end;' -, kommt AStmt inline direkt hinter das
//                   begin ('begin inherited Create; end;'): bedeutungsgleich
//                   und ohne die Zeilen des Autors umzubrechen (wie SCA020
//                   mit '{ intentionally empty }').
//   LastStatement   AStmt als letzte Anweisung: eine eigene Zeile vor dem
//                   end, wenn es seine Zeile beginnt, sonst inline hinter
//                   der letzten Anweisung; fehlt ihr das ';', kommt es mit
//                   - hinter ihr letztes Zeichen aus Code oder String
//                   (uRdxCodeMap.LastCharBefore).
//                   Leerer Rumpf: wie FirstStatement.
//                   Bausteine auch fuer SCA096 (erste Anweisung) und
//                   SCA097 (letzte) in uRdxInheritedFixes.
// Die Routinengrenzen liest uRdxBlocks.ReadRoutine (Kopf, lokale
// Abschnitte und Routinen, begin bzw. asm, passendes end), den Klassenkopf
// HeritageOf, die Deklaration FindMethodDecls/MethodDecl. Typdeklarationen,
// Klassenkoepfe (auch 'TGen<T: class; U> = class') und die Namen hinter
// 'constructor' liest EIN Lauf je Planeraufruf (TRdxScan, Gegen-Review R5,
// R5-07); ob eine Typdeklaration auf Unit-Ebene steht, ein Lauf nach dem
// Muster BuildScopes (AtUnitLevel, R5-06).
// Lokale Routinen zwischen Kopf und begin sperren deshalb NICHT mehr (das
// Konzept nannte sie, als nur MethodBodyOn fuer leere Rumpfe bestand):
// ReadRoutine ueberspringt sie, eingefuegt wird hinter dem begin der
// aeusseren Routine - vor jedem Aufruf einer lokalen.
//
// GETEILT mit uRdxInheritedFixes (interface, Review Woche G08-04): der
// Planerlauf TRdxScan und seine Fragen (NewScan, ClassHeads, MethodDecls,
// DeclaredAs, DeclaresTypeName, UnitInterface, IsCtorName), die
// Deklaration einer Methode (DeclHeadsOf, DeclOf), der Kopf auf der Zeile
// (RoutineOnLine), der Rumpf (BodyReason), Exit (IsExitAt) und der
// Abschluss (FinishPlan, FirstEdits).
//
// SPERREN (alle vier Planer der Charge H5; die eigenen von SCA096/SCA097
// nennt uRdxInheritedFixes): kein begin-Rumpf (forward/external,
// asm-Rumpf), asm irgendwo im Rumpf (Register und Stapel sieht die Hilfe
// nicht), eine Compiler-Direktive zwischen Kopf und begin (Kopf oder
// Rumpf unter einem Zweig), zwei Koepfe auf der gemeldeten Zeile.
// SCA121/SCA196: FPC-Modus ohne Result
// (fpc, tp, macpas, iso), '{$X-}'; SCA121 dazu Default() in einer Datei
// ohne implementation-Teil bzw. ohne Kopf (xEdit-/JvInterpreter-Skripte
// kennen Default() nicht; ein Literal wie 'Result := 0;' kennen sie - seit
// Review Woche G08-07 wie bei den alten Compilern nur fuer Default()),
// eine Zuweisung an Result bzw. den Funktionsnamen oder Exit(Wert) (auch
// 'System.Exit(Wert)') im Rumpf (der Detektor sah sie nicht - meist in
// einem inaktiven Zweig), Default() in einer Datei mit Spuren alter Compiler
// und ein Rueckgabetyp, der kein einfacher Typbezeichner ist (FPC
// 'specialize') bzw. den die Funktion in ihrem Deklarationsteil selbst
// definiert (im Rumpf meinte der Name den lokalen Typ); SCA196 dazu
// 'absolute Result', ein Typ, der weder String noch dynamisches Array,
// Interface oder Variant BEWIESEN ist, und ein Typname, den die Unit auch
// lokal bzw. geschachtelt definiert.
//
// GRENZE (SCA121, System.Low(T)): verdecken kann es nur ein Bezeichner
// System. Nennt die Unit selbst einen, gibt es Default(T); einen aus einer
// anderen Unit - etwa ein Member System eines Vorfahren - sieht die Hilfe
// nicht, der Compiler meldet es. Ein Low in Klasse, Vorfahr, Record, Unit
// oder Routine stoert nicht mehr (Nachpruefung R5-06).
// GRENZE (SCA121/SCA196): was der Gueltigkeitsbereich aus anderen Units
// beitraegt - ein geschachtelter Typ gleichen Namens in einem Vorfahren -,
// sieht die Hilfe nicht; sie nimmt die Definition der Unit bzw. der RTL
// (einen Widerspruch meldet in der Regel der Compiler).
//
// GRUNDSATZ wie in uRdxSimpleFixes: lieber keine Hilfe als eine falsche -
// der Planer prueft den Fund am aktuellen Text nach.

interface

uses
  uRdxBufferMath, uRdxCodeMap,
  uRdxBlocks;        // TRdxRoutine (bis Charge B2S-b uRdxRoutineFixes)

type
  // Ergebnis der Planer: alle Ersetzungen (EIN Undo-Schritt), der Name fuer
  // den Menuetext und was der Aufrufer (uRdxFixTable) noch braucht.
  //   Name          SCA096: die Anweisung (STMT_* in uRdxInheritedFixes),
  //                 SCA121: der Wert ('0', 'False', 'Default(TRec)'),
  //                 SCA196: die Anweisung
  //                 ohne ';' - schon gesetzt, soweit bekannt, auch wenn der
  //                 Planer ablehnt.
  //   Changes       Kennzeichnung (E2) nach dem Fund: SCA096 bei override,
  //                 SCA097 ausser bei direktem TObject-Erben.
  //   NeedsVariants SCA196 mit VarClear: Variants muss in uses stehen.
  TRdxResultPlan = record
    Edits         : TArray<TRdxEdit>;
    Name          : string;
    Changes       : Boolean;
    NeedsVariants : Boolean;
  end;

  // Die Form der Planer (uRdxFixTable: ResultForm im Geruest TRdxFixFrame).
  TRdxResultPlanner = function(AMap: TRdxCodeMap; ALine: Integer;
    const AMessage: string; out APlan: TRdxResultPlan;
    out AReason: string): Boolean;

  // Eine Typdeklaration der Datei (TRdxScan): 'Name [<..>] = [packed] Art'
  // - der Name, das Token davor (im Typabschnitt eines aus TYPE_DECL_PREV)
  // und die Art (KindAfterName). Auch 'A = B' in einem Ausdruck steht hier
  // - die Fragen filtern wie bis Charge B1-FE ihre eigenen Laeufe.
  TRdxTypeDecl = record
    NameTok : TRdxToken;
    PrevTok : TRdxToken;
    KindTok : TRdxToken;
  end;

  // Eine gemerkte Antwort von ClassHeads bzw. MethodDecls.
  TRdxHeadsMemo = record
    Key   : string;
    Heads : TArray<TRdxToken>;
  end;

  // Ein Planerlauf (Gegen-Review R5, R5-07): die Code-Sicht und was sonst
  // jede Frage neu ueber die ganze Datei las. Die Typdeklarationen, die
  // Namen hinter 'constructor' und ob die Unit einen Bezeichner System
  // nennt (OwnSystem: 'System' ohne '.' dahinter - er verdeckte die Unit
  // System, EnumValue) sammelt EIN Lauf beim ersten Bedarf (IndexScan); die
  // Klassenkoepfe kommen aus diesem Index (ClassHeads - in Pascal dieselben
  // wie FindClassHeads: Korpus-Gegenrechnung der Nachpruefung R5-07 ueber
  // 8.795 Koepfe in 1.044 Dateien, anders nur zwei Codevorlagen 'T<#Name> =
  // class', die kein Pascal sind), die Methodendeklarationen
  // je Klasse und Methode einmal, ohne Klassenkopf gar nicht und seit
  // Charge B2S-b ebenfalls aus dem Index (MethodDecls: je Kopf
  // TRdxBlocks.MemberHeads statt FindMethodDecls, das je Frage die ganze
  // Datei las). Bis Charge B1-FE las ein SCA096-Lauf
  // mormot.core.variants.pas dreizehnmal ganz (562 ms im IDE-Hauptthread).
  // GenericMiss: ein '=' hinter '>', dessen Deklaration DeclAt nicht lesen
  // kann (OpenAngleBefore scheitert an einem Token in den Typparametern) -
  // dort kann FindClassHeads einen Kopf sehen, den der Index nicht hat;
  // MethodDecls fragt dann wie bisher FindMethodDecls. Gilt fuer EINEN
  // Planeraufruf - die Code-Sicht liegt danach nicht mehr fest.
  TRdxScan = record
    Map         : TRdxCodeMap;
    Indexed     : Boolean;
    Decls       : TArray<TRdxTypeDecl>;
    Ctors       : TArray<string>;
    Memos       : TArray<TRdxHeadsMemo>;
    OwnSystem   : Boolean;
    GenericMiss : Boolean;
  end;

  // Die Planer SCA121/SCA196 der Charge H5 und die Bausteine (s. Kopf):
  // auf dem Puffertext ueber die Code-Sicht, ohne ToolsAPI und Parser
  // (laeuft auch im FPC-Pruefstand).
  TRdxResultFixes = class
  public
    // Baustein: AStmt (mit ';', ohne Zeilenende) als erste Anweisung des
    // begin-Rumpfs von R (s. Kopf). '' oder der Grund.
    class function FirstStatement(AMap: TRdxCodeMap; const R: TRdxRoutine;
      const AStmt: string; out AEdit: TRdxEdit): string; static;

    // Baustein: AStmt (mit ';') als letzte Anweisung vor dem end des
    // begin-Rumpfs von R - eine oder zwei Ersetzungen (das ';' der letzten
    // Anweisung). Gesperrt bei einer Direktive zwischen letzter Anweisung
    // und end. '' oder der Grund.
    class function LastStatement(AMap: TRdxCodeMap; const R: TRdxRoutine;
      const AStmt: string; out AEdits: TArray<TRdxEdit>): string; static;

    // SCA121: die Funktion mit Kopf auf ALine (Meldung 'Function X never
    // assigns Result ...') - 'Result := <Literal>;' bzw.
    // 'Result := Default(T);'.
    class function ResultDefault(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxResultPlan;
      out AReason: string): Boolean; static;

    // SCA196: die Funktion um die Lese-Zeile ALine (Meldung 'Function X
    // reads Result before assigning it (...) - for return type T, ...') -
    // 'Result := '''';', 'Result := nil;' bzw. 'VarClear(Result);'.
    class function ManagedResultInit(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxResultPlan;
      out AReason: string): Boolean; static;
  end;

// ---- Geteilt mit uRdxInheritedFixes (SCA096/SCA097) ----
// Seit Review Woche G08-04 (s. Kopf, GETEILT); die Begruendungen stehen
// an den Ruempfen. Gilt fuer EINEN Planeraufruf: die Code-Sicht liegt
// danach nicht mehr fest.

// Ein neuer Planerlauf auf AMap (der Index entsteht beim ersten Bedarf).
function NewScan(AMap: TRdxCodeMap): TRdxScan;

// Die Koepfe 'Name [<..>] = [packed] class' mit Rumpf zum letzten Glied
// von AClassPath - je Treffer das Token 'class', aus dem Index, gemerkt.
function ClassHeads(var AScan: TRdxScan;
  const AClassPath: string): TArray<TRdxToken>;

// Die Deklarationen von AMethod im Rumpf der Klasse AClassPath, gemerkt.
function MethodDecls(var AScan: TRdxScan;
  const AClassPath, AMethod: string): TArray<TRdxToken>;

// Gibt es 'ALowName [<..>] = [packed] <Art>' mit einer Art aus AKinds?
function DeclaredAs(var AScan: TRdxScan; const ALowName: string;
  const AKinds: array of string): Boolean;

// Deklariert die Unit den Typnamen ALowName in einem Typabschnitt?
function DeclaresTypeName(var AScan: TRdxScan; const ALowName: string): Boolean;

// Deklariert die Unit ALowName auf Unit-Ebene als Interface?
function UnitInterface(var AScan: TRdxScan; const ALowName: string): Boolean;

// Steht ALowName irgendwo hinter 'constructor'?
function IsCtorName(var AScan: TRdxScan; const ALowName: string): Boolean;

// 'TOuter.TInner.Create' -> 'TOuter.TInner'.
function OwnerPathOf(const AName: string): string;

// Die Deklarationen der Methode R im Rumpf ihrer Klasse.
function DeclHeadsOf(var AScan: TRdxScan;
  const R: TRdxRoutine): TArray<TRdxToken>;

// Die EINE Deklaration der Methode R in D. '' oder der Grund.
function DeclOf(var AScan: TRdxScan; const R: TRdxRoutine;
  out D: TRdxRoutine): string;

// Die eine Routine, deren Kopf (Kopfwort aus AWords, 'constructor' bzw.
// 'function|operator') auf ALine steht, bis zu ihrem Ende gelesen. ''
// oder der Grund.
function RoutineOnLine(AMap: TRdxCodeMap; ALine: Integer;
  const AWords, AWhat: string; out R: TRdxRoutine): string;

// Ein begin-Rumpf ohne asm, ohne Direktive zwischen Kopf und begin? ''
// oder der Grund.
function BodyReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;

// Exit an T (APrev davor) - als Schluesselwort oder als 'System.Exit'?
function IsExitAt(AMap: TRdxCodeMap; const T, APrev: TRdxToken): Boolean;

// AReason = '': AEdits in den Plan, sonst die Ersetzungen leeren; True
// ohne Grund. Bis Review Woche G08-04 hiess sie Finish (privat).
function FinishPlan(var APlan: TRdxResultPlan;
  const AEdits: TArray<TRdxEdit>; const AReason: string): Boolean;

// Der Rumpf von R mit AStmt als erster Anweisung (FirstStatement, fuer
// FinishPlan).
function FirstEdits(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const AStmt: string; out AEdits: TArray<TRdxEdit>): string;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxRtlTypes,      // IsRtlClassOrInterface (SCA196: Interface aus der RTL)
  uRdxCompilerTraces;  // OldCompilerTrace (SCA121: Spuren alter Compiler)

const
  SPAN_RESULT = 'result';
  KW_BEGIN    = 'begin';
  KW_END      = 'end';
  KW_CLASS    = 'class';
  KW_RESULT   = 'result';
  KW_CONSTRUCTOR = 'constructor';
  KEY_FUNC    = 'Function ';
  KEY_NEVER   = ' never assigns Result';
  KEY_READS   = ' reads Result before';
  KEY_TYPE    = 'for return type ';
  KEY_TYPE_END = ', Result is';
  // Die Unit der Spruenge Exit/Break/Continue ('System.Exit'; in Klassen mit
  // einem eigenen Exit - TMonitor - steht es so in den Delphi-Quellen).
  SYSTEM_UNIT = 'system';
  // Was ausser Woertern in einer Typparameterliste steht ('TFoo<A, B>',
  // 'TGen<T: class; U: IFoo<T>>', '&Name') - DeclAt liest rueckwaerts nur
  // diese Token (OpenAngleBefore).
  TYPE_PARAM_TOKENS: array[0..6] of string = ('<', '>', ',', ';', ':', '.',
    '&');
  // Der Lauf von AtUnitLevel (R5-06, nach dem Muster
  // uRdxSqlTemplate.BuildScopes): offene Bloecke je ein Zeichen - Typ mit
  // Rumpf, Record (sein 'case' hat kein eigenes end), Code (begin, try,
  // asm, case).
  FRAME_TYPE   = 'T';
  FRAME_RECORD = 'R';
  FRAME_CODE   = 'C';
  // Diese Woerter oeffnen hinter '=' bzw. 'packed' einen Typ mit Rumpf.
  BODY_TYPES: array[0..3] of string = ('class', 'object', 'interface',
    'dispinterface');
  TYPE_LEADS: array[0..1] of string = ('=', 'packed');
  // Hinter 'record' in einer Typ-Einschraenkung ('<T: record>').
  CONSTRAINT_FOLLOWERS: array[0..2] of string = ('>', ',', ';');
  // Routinen mit Rumpf stehen in einer Unit erst hinter 'implementation', in
  // jeder anderen Datei - program, library, Include ohne Kopf - ab dem
  // Dateianfang (AtUnitLevel).
  UNIT_HEAD = 'unit';
  // FPC-Modi ohne Result (SCA121/SCA196).
  NO_RESULT_MODES: array[0..4] of string = ('fpc', 'tp', 'macpas', 'iso',
    'extendedpascal');
  // SCA196: die Rueckgabetypen je Initialisierung - wie
  // uManagedResultUninit.IsResultPointerType (klein, ohne 'system.').
  STRING_TYPES: array[0..11] of string = ('string', 'unicodestring',
    'ansistring', 'rawbytestring', 'widestring', 'shortstring', 'utf8string',
    'rawutf8', 'rawjson', 'synunicode', 'tbtstring', 'tbtwidestring');
  VARIANT_TYPES: array[0..1] of string = ('variant', 'olevariant');
  // Die dynamischen Arrays der RTL (System.Types; FPC Types kennt dieselben
  // Namen) - ein '*DynArray' sonst nur mit 'Name = array of' in der Unit.
  RTL_DYN_ARRAYS: array[0..14] of string = ('tbooleandynarray',
    'tbytedynarray', 'tcardinaldynarray', 'tclassicbytedynarray',
    'tclassicstringdynarray', 'tdoubledynarray', 'tint64dynarray',
    'tintegerdynarray', 'tshortintdynarray', 'tsingledynarray',
    'tsmallintdynarray', 'tstringdynarray', 'tuint64dynarray',
    'twidestringdynarray', 'tworddynarray');
  INTERFACE_KINDS: array[0..1] of string = ('interface', 'dispinterface');
  // SCA121 (InitValueFor): Typen der RTL, deren Anfangswert ein Literal
  // ist - derselbe Wert wie Default(T), aber auch fuer Compiler vor Delphi
  // 2009 (Gegen-Review H5, Minor 4). Klein, ohne 'system.'; deklariert die
  // Unit den Namen selbst, gilt ihre Definition.
  BOOLEAN_TYPES: array[0..3] of string = ('boolean', 'bytebool', 'wordbool',
    'longbool');
  NUMBER_TYPES: array[0..35] of string = ('integer', 'cardinal', 'shortint',
    'smallint', 'longint', 'longword', 'int64', 'uint64', 'byte', 'word',
    'nativeint', 'nativeuint', 'int8', 'int16', 'int32', 'uint8', 'uint16',
    'uint32', 'fixedint', 'fixeduint', 'dword', 'qword', 'sizeint',
    'sizeuint', 'ptrint', 'ptruint', 'single', 'double', 'extended', 'real',
    'real48', 'currency', 'comp', 'tdatetime', 'tdate', 'ttime');
  CHAR_TYPES: array[0..2] of string = ('char', 'ansichar', 'widechar');
  POINTER_TYPES: array[0..5] of string = ('pointer', 'pchar', 'pansichar',
    'pwidechar', 'tobject', 'tclass');
  // Was in einer Typdefinition der Unit 'nil' traegt (OwnTypeValue): Klasse,
  // Metaklasse, Interface, Zeiger, Routinen- und Methodenzeiger.
  NIL_KINDS: array[0..6] of string = ('class', 'interface', 'dispinterface',
    '^', 'procedure', 'function', 'reference');
  // Davor steht ein Typname, wenn er deklariert wird ('type TFoo =',
  // '; TFoo =', '[Attr] TFoo =') - nicht ein Parameter 'A: TFoo = nil'.
  TYPE_DECL_PREV: array[0..2] of string = (';', 'type', ']');
  VALUE_FALSE     = 'False';
  VALUE_ZERO      = '0';
  VALUE_EMPTY     = '''''';
  VALUE_NUL       = '#0';
  VALUE_NIL       = 'nil';
  VALUE_EMPTY_SET = '[]';
  ARRAY_KINDS: array[0..1] of string = ('array', 'tarray');
  STMT_EMPTY_STRING = 'Result := ''''';
  STMT_NIL          = 'Result := nil';
  STMT_VARCLEAR     = 'VarClear(Result)';
  R_MOVED  = 'Zeile verschoben? Datei neu pruefen';
  R_BY_HAND = 'von Hand';
  // SCA121: was nur der Compiler kennt (ScriptReason, uRdxCompilerTraces).
  FEATURE_DEFAULT = 'Default()';
  // SCA121: der Anfangswert einer schlichten Aufzaehlung T (EnumValue) -
  // qualifiziert, kein anderes Low verdeckt die Funktion.
  ENUM_FIRST_FMT = 'System.Low(%s)';
  // SCA196: als Konstante - ein Literal mit dem Wort im Exit-Argument
  // haelt der Detektor SCA196 selbst fuer ein Lesen von Result (Selbstscan
  // der Charge H5).
  R_NO_READ = 'kein Result auf der gemeldeten Zeile - ' + R_MOVED;

type
  // SCA196: die Funktion um die Lese-Zeile und ihr Rueckgabetyp wie im
  // Quelltext (FuncCtxReason).
  TRdxFuncCtx = record
    Routine : TRdxRoutine;
    TypeTx  : string;
  end;

{ ---- Kleinkram ---- }

// AddEdit (uRdxBufferMath), AddToken, TokText, LastPart, FirstOnLine und
// DirectiveBetween (uRdxCodeMap) sowie HasDirective (uRdxBlocks) sind
// geteilt - bis Charge H5c standen hier Kopien, TokText verdeckte still die
// geteilte Fassung (Gegen-Review H5, Minor 6).

// Ersetzt das Token T durch ANewText.
function TokenEdit(AMap: TRdxCodeMap; const T: TRdxToken;
  const ANewText: string): TRdxEdit;
begin
  Result.Span := TRefactorSpan.Make(SPAN_RESULT, T.Line, T.Col, T.Line,
    T.EndCol);
  Result.Expected := TokText(AMap, T);
  Result.NewText := ANewText;
end;

// Haengt ASuffix an das Zeichen (ALine, ACol): es wird mit ASuffix dahinter
// neu geschrieben - ein leerer Erwartungstext ist nicht erlaubt (wie
// uRdxStructFixes.AppendSemicolon).
function CharEdit(AMap: TRdxCodeMap; ALine, ACol: Integer;
  const ASuffix: string): TRdxEdit;
begin
  Result.Span := TRefactorSpan.Make(SPAN_RESULT, ALine, ACol, ALine, ACol + 1);
  Result.Expected := Copy(AMap.Raw(ALine), ACol, 1);
  Result.NewText := Result.Expected + ASuffix;
end;

// Leerraum am Zeilenanfang.
function LeadingBlanks(const S: string): string;
begin
  Result := Copy(S, 1, SkipBlanks(S, 1) - 1);
end;

// 'TOuter.TInner.Create' -> 'TOuter.TInner' (das letzte Glied: LastPart).
function OwnerPathOf(const AName: string): string;
begin
  Result := Copy(AName, 1, LastDelimiter('.', AName) - 1);
end;

// Der Text zwischen AKey und AStop in AMessage (Leerraum am Rand weg); ''
// ohne beide.
function TextBetween(const AMessage, AKey, AStop: string): string;
var
  P, Q : Integer;
begin
  Result := '';
  P := Pos(AKey, AMessage);
  if P = 0 then Exit;
  Inc(P, Length(AKey));
  Q := Pos(AStop, AMessage, P);
  if Q > P then
    Result := Trim(Copy(AMessage, P, Q - P));
end;

// Steht T als erstes auf seiner Zeile (FirstOnLine), und die Zeile beginnt
// nicht in einem Kommentar oder mehrzeiligen String? Erst dann zaehlt seine
// Einrueckung bzw. bekommt eine Einfuegung davor eine eigene Zeile.
function OwnLineAt(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
begin
  Result := FirstOnLine(AMap, T) and not AMap.StartsInside(T.Line);
end;

// Hinter dem Namen ANameTok: '[<..>] = [packed] <Art>' - das Token der Art;
// Low = '' ohne '='.
function KindAfterName(AMap: TRdxCodeMap; const ANameTok: TRdxToken): TRdxToken;
begin
  Result := After(AMap, ANameTok);
  if Result.Low = '<' then
    Result := AfterClose(AMap, Result);
  if Result.Low <> '=' then
    Exit(Default(TRdxToken));
  Result := After(AMap, Result);
  if Result.Low = 'packed' then
    Result := After(AMap, Result);
end;

{ ---- Ein Planerlauf (R5-07) ---- }

// Ein neuer Planerlauf auf AMap (TRdxScan; der Index entsteht beim ersten
// Bedarf).
function NewScan(AMap: TRdxCodeMap): TRdxScan;
begin
  Result := Default(TRdxScan);
  Result.Map := AMap;
end;

// Rueckwaerts ab AClose ('>' der Typparameter 'TFoo<A, B>') die passende
// '<'; Low = '' ohne. Gelesen werden nur Token, die in einer
// Typparameterliste stehen koennen - Woerter und TYPE_PARAM_TOKENS, auch das
// ';' zwischen Gruppen mit Einschraenkung ('TGen<T: class; U>'); jedes andere
// Token und der Dateianfang beenden die Suche ohne Treffer. Bis zur
// Nachpruefung R5-07 brach sie an jedem ';' ab: ein Kopf 'TGen<T: class; U>
// = class' fehlte im Index, ein solcher Vorfahr galt als nicht in der Unit -
// die Sperren Delegation (SCA096) und abstrakt (SCA097) sahen ihn nicht, und
// seine Methoden lehnte die Hilfe mit "nicht in dieser Unit" ab.
function OpenAngleBefore(AMap: TRdxCodeMap; const AClose: TRdxToken): TRdxToken;
var
  T     : TRdxToken;
  Depth : Integer;
begin
  Result := Default(TRdxToken);
  if AClose.Low <> '>' then Exit;
  T := AClose;
  Depth := 0;
  while T.IsWord or InList(T.Low, TYPE_PARAM_TOKENS) do
  begin
    if T.Low = '>' then
      Inc(Depth)
    else if T.Low = '<' then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit(T);
    end;
    T := Before(AMap, T);
  end;
end;

// Die Deklaration, deren '=' AEq ist: der Name davor - hinter '<..>' der
// Name vor der '<' -, das Token davor und die Art (KindAfterName prueft
// vorwaerts nach, wie bis Charge B1-FE jeder eigene Lauf). False ohne.
function DeclAt(AMap: TRdxCodeMap; const AEq: TRdxToken;
  out ADecl: TRdxTypeDecl): Boolean;
var
  T : TRdxToken;
begin
  ADecl := Default(TRdxTypeDecl);
  T := Before(AMap, AEq);
  if T.Low = '>' then
    T := Before(AMap, OpenAngleBefore(AMap, T));
  if not T.IsWord then Exit(False);
  ADecl.NameTok := T;
  ADecl.PrevTok := Before(AMap, T);
  ADecl.KindTok := KindAfterName(AMap, T);
  Result := ADecl.KindTok.Low <> '';
end;

// Ein '=' im Lauf von IndexScan: die Deklaration in den Index (DeclAt) -
// oder, wenn DeclAt sie nicht lesen kann und davor '>' steht, GenericMiss
// (s. TRdxScan).
procedure IndexDecl(var AScan: TRdxScan; const AEq: TRdxToken);
var
  D : TRdxTypeDecl;
begin
  if DeclAt(AScan.Map, AEq, D) then
  begin
    SetLength(AScan.Decls, Length(AScan.Decls) + 1);
    AScan.Decls[High(AScan.Decls)] := D;
  end
  else if Before(AScan.Map, AEq).Low = '>' then
    AScan.GenericMiss := True;
end;

// Der eine Lauf des Planerlaufs (s. TRdxScan): jede Deklaration an einem
// '=' (IndexDecl), jeder Name hinter 'constructor' (auch '&Name') und ein
// 'System' ohne '.' dahinter (OwnSystem).
procedure IndexScan(var AScan: TRdxScan);
var
  T, P : TRdxToken;
  Ctor : Boolean;
begin
  if AScan.Indexed then Exit;
  AScan.Indexed := True;
  Ctor := False;
  P := Default(TRdxToken);
  T := NextToken(AScan.Map, 1, 1);
  while T.Low <> '' do
  begin
    if T.Low = '=' then
      IndexDecl(AScan, T);
    if Ctor and T.IsWord then
    begin
      SetLength(AScan.Ctors, Length(AScan.Ctors) + 1);
      AScan.Ctors[High(AScan.Ctors)] := T.Low;
    end;
    Ctor := (T.Low = KW_CONSTRUCTOR) or (Ctor and (T.Low = '&'));
    if (P.Low = SYSTEM_UNIT) and (T.Low <> '.') then
      AScan.OwnSystem := True;
    P := T;
    T := After(AScan.Map, T);
  end;
  if P.Low = SYSTEM_UNIT then
    AScan.OwnSystem := True;
end;

// Gibt es 'ALowName [<..>] = [packed] <Art>' mit einer Art aus AKinds in
// der Datei? Das Token der Art (Low = '' ohne) - der erste Treffer.
function TypeDeclKind(var AScan: TRdxScan; const ALowName: string;
  const AKinds: array of string): TRdxToken;
var
  D : TRdxTypeDecl;
begin
  IndexScan(AScan);
  for D in AScan.Decls do
    if SameIdent(D.NameTok.Low, ALowName)
       and IsKeywordAfter(D.NameTok, D.PrevTok)
       and InList(D.KindTok.Low, AKinds) then
      Exit(D.KindTok);
  Result := Default(TRdxToken);
end;

function DeclaredAs(var AScan: TRdxScan; const ALowName: string;
  const AKinds: array of string): Boolean;
begin
  Result := TypeDeclKind(AScan, ALowName, AKinds).Low <> '';
end;

// Die Definitionen des Typnamens ALowName in der Unit: je 'Name [<..>] =
// [type] [packed] X' in einem Typabschnitt (davor TYPE_DECL_PREV) das Token
// X ('class', 'array', '(', 'string' ...); leer, wenn die Unit den Namen
// nicht als Typ deklariert. Mehrere Treffer stehen unter $IFDEF-Zwillingen.
// SCA196 und SCA121 (Gegen-Review H5, Minor 8): deklariert die Unit einen
// Namen selbst ('TBytes = array[0..3] of Byte'), gilt nur ihre Definition.
function TypeDefsOf(var AScan: TRdxScan;
  const ALowName: string): TArray<TRdxToken>;
var
  D : TRdxTypeDecl;
  K : TRdxToken;
begin
  Result := nil;
  IndexScan(AScan);
  for D in AScan.Decls do
    if SameIdent(D.NameTok.Low, ALowName)
       and InList(D.PrevTok.Low, TYPE_DECL_PREV) then
    begin
      K := D.KindTok;
      // 'Name = type X': ein eigener Typ mit der Definition von X.
      if K.Low = 'type' then
        K := After(AScan.Map, K);
      if K.Low <> '' then
        AddToken(Result, K);
    end;
end;

function DeclaresTypeName(var AScan: TRdxScan; const ALowName: string): Boolean;
begin
  Result := Length(TypeDefsOf(AScan, ALowName)) > 0;
end;

// Die gemerkte Antwort zu AKey (TRdxScan.Memos); False ohne.
function FindMemo(const AScan: TRdxScan; const AKey: string;
  out AHeads: TArray<TRdxToken>): Boolean;
var
  M : TRdxHeadsMemo;
begin
  for M in AScan.Memos do
    if M.Key = AKey then
    begin
      AHeads := M.Heads;
      Exit(True);
    end;
  AHeads := nil;
  Result := False;
end;

procedure KeepMemo(var AScan: TRdxScan; const AKey: string;
  const AHeads: TArray<TRdxToken>);
begin
  SetLength(AScan.Memos, Length(AScan.Memos) + 1);
  AScan.Memos[High(AScan.Memos)].Key := AKey;
  AScan.Memos[High(AScan.Memos)].Heads := AHeads;
end;

// TypeHasBody (hat der Typ einen Rumpf mit end?) stand bis Charge B2S-b hier
// als Kopie - dieselbe Probe wie in uRdxRoutineFixes und
// uRdxSqlTemplate.HasTypeBody; seitdem die eine in uRdxBlocks (Gegen-Review
// R5, R5-03).

// Die Koepfe 'Name [<..>] = [packed] class' mit Rumpf, deren Name das
// letzte Glied von AClassPath ist - je Treffer das Token 'class', aus dem
// Index und gemerkt: dieselbe Probe wie TRdxBlocks.FindClassHeads
// (ClassHeadAt), das je Frage die ganze Datei liest.
function ClassHeads(var AScan: TRdxScan;
  const AClassPath: string): TArray<TRdxToken>;
var
  Low, Key : string;
  D        : TRdxTypeDecl;
begin
  Low := LowerCase(LastPart(AClassPath));
  Key := 'class:' + Low;
  if FindMemo(AScan, Key, Result) then Exit;
  IndexScan(AScan);
  for D in AScan.Decls do
    if SameIdent(D.NameTok.Low, Low)
       and IsKeywordAfter(D.NameTok, D.PrevTok)
       and (D.KindTok.Low = KW_CLASS)
       and TypeHasBody(AScan.Map, D.KindTok) then
      AddToken(Result, D.KindTok);
  KeepMemo(AScan, Key, Result);
end;

// TRdxBlocks.FindMethodDecls einmal je Klasse und Methode des Laufs -
// und nicht ohne Klassenkopf (ClassHeads): ohne den findet es nichts. Die
// Koepfe nimmt es seit Charge B2S-b aus dem Index (ClassHeads, je Kopf
// TRdxBlocks.MemberHeads) statt aus FindClassHeads - das las je Frage die
// ganze Datei, je Vorfahr in der Unit einmal (Gegen-Review R5-07: zwei
// Laeufe von je gut 90 ms auf wbInterface.pas, FPC i386). Dieselben Koepfe
// in derselben Reihenfolge: der Index sieht jeden Kopf, den FindClassHeads
// sieht (dieselben Proben ueber dasselbe '=', s. TRdxScan.GenericMiss) -
// ausser einem generischen Kopf, dessen Typparameter OpenAngleBefore nicht
// lesen kann; liegt in der Datei ein solches '=' hinter '>', fragt es wie
// bisher FindMethodDecls.
function MethodDecls(var AScan: TRdxScan;
  const AClassPath, AMethod: string): TArray<TRdxToken>;
var
  Key   : string;
  Heads : TArray<TRdxToken>;
  C     : TRdxToken;
  H     : TRdxToken;
begin
  Key := 'method:' + LowerCase(LastPart(AClassPath)) + '.' + LowerCase(AMethod);
  if FindMemo(AScan, Key, Result) then Exit;
  Heads := ClassHeads(AScan, AClassPath);
  if (Length(Heads) > 0) and AScan.GenericMiss then
    Result := TRdxBlocks.FindMethodDecls(AScan.Map, AClassPath, AMethod)
  else
    for C in Heads do
      for H in TRdxBlocks.MemberHeads(AScan.Map, C, AMethod) do
        AddToken(Result, H);
  KeepMemo(AScan, Key, Result);
end;

// Steht ALowName irgendwo hinter 'constructor'? Ohne das ist er kein
// Konstruktor einer Klasse der Unit (uRdxInheritedFixes.OwnConstructor
// fragt sonst je Aufruf im Rumpf die ganze Vorfahrenkette ab).
function IsCtorName(var AScan: TRdxScan; const ALowName: string): Boolean;
begin
  IndexScan(AScan);
  Result := InList(ALowName, AScan.Ctors);
end;

{ ---- Gueltigkeitsbereich einer Typdeklaration (R5-06) ---- }

// Steht oben auf dem Stapel AOpen (AtUnitLevel) ein Typ mit Rumpf?
function InTypeFrame(const AOpen: string): Boolean;
begin
  Result := (AOpen <> '')
    and CharInSet(AOpen[Length(AOpen)], [FRAME_TYPE, FRAME_RECORD]);
end;

// Ein Schluesselwort T (APrev davor) beim Lauf von AtUnitLevel: ein Typ mit
// Rumpf (TypeHasBody), ein record (nicht als Einschraenkung '<T: record>')
// bzw. begin/try/asm/case kommen auf den Stapel AOpen, end nimmt den
// obersten herunter. Ein 'case' im record hat kein eigenes end.
procedure StepFrames(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  var AOpen: string);
begin
  if T.Low = KW_END then
    Delete(AOpen, Length(AOpen), 1)
  else if T.Low = 'record' then
  begin
    if not InList(After(AMap, T).Low, CONSTRAINT_FOLLOWERS) then
      AOpen := AOpen + FRAME_RECORD;
  end
  else if InList(T.Low, BODY_TYPES) and InList(APrev.Low, TYPE_LEADS) then
  begin
    if TypeHasBody(AMap, T) then
      AOpen := AOpen + FRAME_TYPE;
  end
  else if T.Low = 'case' then
  begin
    if (AOpen = '') or (AOpen[Length(AOpen)] <> FRAME_RECORD) then
      AOpen := AOpen + FRAME_CODE;
  end
  else if IsEndOpener(T.Low) then
    AOpen := AOpen + FRAME_CODE;
end;

// Die Routine ab dem Kopf T beim Lauf von AtUnitLevel: hat sie einen Rumpf,
// rueckt T auf ihr letztes ';' (der Lauf ueberspringt sie). False, wenn
// ADecl in ihr liegt (eine lokale Deklaration) oder ihre Grenzen nicht
// sicher zu lesen sind.
function SkipRoutine(AMap: TRdxCodeMap; var T: TRdxToken;
  const ADecl: TRdxToken): Boolean;
var
  R : TRdxRoutine;
begin
  Result := TRdxBlocks.ReadRoutine(AMap, T, R) = '';
  if not Result or (R.Body.Low = '') then Exit;
  Result := TokBefore(R.Last, ADecl);
  T := R.Last;
end;

// R5-06: steht die Typdeklaration an ADecl (ein Token der Deklaration, etwa
// die Art aus TypeDefsOf) auf Unit-Ebene - nicht in einem Klassen-, Record-
// oder Interface-Rumpf und nicht in einer Routine? Nur dort ist sie in jeder
// Routine der Unit sichtbar; ein geschachtelter Typ einer anderen Klasse
// bzw. ein lokaler Typ einer anderen Routine ist es nicht (Gegen-Review R5:
// 'type TPoint = ^Integer' in einer Routine machte 'Result := nil;' fuer
// System.Types.TPoint). Ein Lauf vom Dateianfang bis ADecl nach dem Muster
// uRdxSqlTemplate.BuildScopes: Bloecke mit end auf einem Stapel, eine
// Routine mit Rumpf (in einer Unit hinter 'implementation', in jeder anderen
// Datei ab Dateianfang - program, library und seit der Nachpruefung R5-06
// auch ein Include ohne Kopf, dort galt der lokale Typ einer Routine als
// Unit-Ebene) wird ganz uebersprungen (SkipRoutine) - liegt ADecl darin, ist
// die Deklaration lokal. Sind die Grenzen einer Routine davor nicht sicher
// zu lesen - etwa ein Kopf ohne Rumpf im interface-Teil eines Includes -:
// False (lieber Default(T) bzw. keine Hilfe).
function AtUnitLevel(AMap: TRdxCodeMap; const ADecl: TRdxToken): Boolean;
var
  T, P     : TRdxToken;
  Open     : string;
  Routines : Boolean;
begin
  Open := '';
  P := Default(TRdxToken);
  T := NextToken(AMap, 1, 1);
  Routines := T.Low <> UNIT_HEAD;
  while (T.Low <> '') and TokBefore(T, ADecl) do
  begin
    // Nur Schluesselwoerter zaehlen - ein Wort hinter '.', '&' bzw. '@' ist
    // ein Bezeichner (IsKeywordAfter).
    if IsKeywordAfter(T, P) then
    begin
      if T.Low = 'implementation' then
        Routines := True
      else if Routines and IsRoutineHeadAfter(T, P)
         and not InTypeFrame(Open) then
      begin
        if not SkipRoutine(AMap, T, ADecl) then
          Exit(False);
      end
      else
        StepFrames(AMap, T, P, Open);
    end;
    P := T;
    T := After(AMap, T);
  end;
  Result := Open = '';
end;

// Stehen alle Definitionen ADefs (TypeDefsOf) auf Unit-Ebene (AtUnitLevel)?
function AllAtUnitLevel(AMap: TRdxCodeMap;
  const ADefs: TArray<TRdxToken>): Boolean;
var
  K : TRdxToken;
begin
  for K in ADefs do
    if not AtUnitLevel(AMap, K) then
      Exit(False);
  Result := True;
end;

// Missed 1 (Gegen-Review R5): deklariert die Unit ALowName auf Unit-Ebene
// als Interface? 'class(IFoo)' erbt nur dann direkt von TObject - ein IFoo,
// das geschachtelt in einer anderen Klasse steht, ist dort nicht sichtbar
// (ein fremdes IFoo kann eine Klasse sein). Fragt ParentReason in
// uRdxInheritedFixes.
function UnitInterface(var AScan: TRdxScan; const ALowName: string): Boolean;
var
  D : TRdxTypeDecl;
begin
  IndexScan(AScan);
  for D in AScan.Decls do
    if SameIdent(D.NameTok.Low, ALowName)
       and IsKeywordAfter(D.NameTok, D.PrevTok)
       and InList(D.KindTok.Low, INTERFACE_KINDS)
       and AtUnitLevel(AScan.Map, D.KindTok) then
      Exit(True);
  Result := False;
end;

{ ---- Kopf und Rumpf ---- }

// Praedikat fuer OneTokenOnLine: ein Routinenkopf, dessen Kopfwort in AArg
// steht ('constructor', 'function|operator').
function IsHeadOf(AMap: TRdxCodeMap; const T: TRdxToken;
  const AArg: string): Boolean;
begin
  Result := IsRoutineHead(AMap, T)
    and (Pos('|' + T.Low + '|', '|' + AArg + '|') > 0);
end;

// Die eine Routine, deren Kopf (Kopfwort aus AWords) auf ALine steht,
// gelesen bis zu ihrem Ende (ReadRoutine). '' oder der Grund.
function RoutineOnLine(AMap: TRdxCodeMap; ALine: Integer;
  const AWords, AWhat: string; out R: TRdxRoutine): string;
var
  S : TRdxLineSearch;
  K : TRdxToken;
begin
  R := Default(TRdxRoutine);
  S := Default(TRdxLineSearch);
  S.Test := IsHeadOf;
  S.Arg := AWords;
  S.What := 'kein Kopf ' + AWhat;
  S.ManyFmt := '%d Koepfe ' + AWhat;
  Result := OneTokenOnLine(AMap, ALine, S, K);
  if Result = '' then
    Result := TRdxBlocks.ReadRoutine(AMap, K, R);
end;

// SCA196: die innerste Routine, deren begin..end die Zeile ALine umfasst -
// Koepfe von ALine aufwaerts, je Zeile von rechts (eine lokale Routine
// steht hinter dem Kopf ihrer aeusseren). Ein Kopf, dessen Grenzen nicht
// sicher zu lesen sind, beendet die Suche mit seinem Grund. Die Suche ist
// der Baustein TRdxBlocks.HeadBefore ab dem Ende der Zeile ALine (Gegen-
// Review R5-03; bis Charge B2S-b hier zeilenweise ausgeschrieben, mit
// HeadsOnLine) - die Politik dieser Frage bleibt, wie sie war: Zeilen statt
// Token, der erste unsichere Kopf beendet die Suche, kein Abschnittswort.
// Bestand: auch ein Schein-Kopf im Rumpf der Funktion - die Zuweisung an
// eine Variable Operator ('operator' steht in ROUTINE_WORDS, ist aber kein
// reserviertes Wort) - beendet sie mit seinem Grund; lieber keine Hilfe
// als die falsche Routine (Gegenpruefung V-B2S-1).
// (uRdxTryFixes.RoutineAround fragt anders: Token, unsichere Koepfe
// uebergangen, ein Abschnittswort der Unit beendet die Suche.)
function EnclosingRoutine(AMap: TRdxCodeMap; ALine: Integer;
  out R: TRdxRoutine): string;
var
  T : TRdxToken;
  S : TRdxHeadStep;
begin
  R := Default(TRdxRoutine);
  // Die Suche beginnt vor dem Anfang der Zeile dahinter: am letzten Token
  // der Zeile ALine (bzw. einer Zeile davor).
  T := Default(TRdxToken);
  T.Line := ALine + 1;
  T.Col := 1;
  while TRdxBlocks.HeadBefore(AMap, T, [], S) do
  begin
    if S.Reason <> '' then
      Exit(Format('Routine in Zeile %d: %s', [S.Tok.Line, S.Reason]));
    if (S.Routine.Body.Low <> '') and (S.Routine.Body.Line <= ALine)
       and (ALine <= S.Routine.EndTok.Line) then
    begin
      R := S.Routine;
      Exit('');
    end;
  end;
  Result := 'keine Routine um die gemeldete Zeile - ' + R_MOVED;
end;

// Ein begin-Rumpf ohne asm, ohne Direktive zwischen Kopf und begin? '' oder
// der Grund.
function BodyReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  T, P : TRdxToken;
begin
  if R.Body.Low = '' then
    Exit('kein Rumpf (forward/external)');
  if R.Body.Low <> KW_BEGIN then
    Exit('asm-Rumpf - Register und Stapel sieht die Hilfe nicht; ' + R_BY_HAND);
  if DirectiveBefore(AMap, R.Head.Line, R.Body) then
    Exit('Compiler-Direktive zwischen Kopf und begin - Kopf oder Rumpf '
      + 'haengen an einem Zweig; ' + R_BY_HAND);
  P := R.Body;
  T := After(AMap, R.Body);
  while (T.Low <> '') and not SameTok(T, R.EndTok) do
  begin
    if (T.Low = 'asm') and IsKeywordAfter(T, P) then
      Exit(Format('asm im Rumpf (Zeile %d) - Register und Stapel sieht die '
        + 'Hilfe nicht; %s', [T.Line, R_BY_HAND]));
    P := T;
    T := After(AMap, T);
  end;
  Result := '';
end;

// Die Einrueckung der Anweisungen im Rumpf von R: wie die erste Anweisung,
// wenn sie eine eigene Zeile beginnt; sonst begin + eine Stufe.
function BodyIndent(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  F : TRdxToken;
  B : string;
begin
  F := After(AMap, R.Body);
  if (F.Line > R.Body.Line) and not SameTok(F, R.EndTok)
     and OwnLineAt(AMap, F) then
    Exit(LeadingBlanks(AMap.Raw(F.Line)));
  B := LeadingBlanks(AMap.Raw(R.Body.Line));
  Result := B + IndentStep(B, '');
end;

// Steht hinter B auf seiner Zeile nur Leerraum oder ein Kommentar, der dort
// endet (kein Code, keine Direktive)? Dann bekommt die Einfuegung eine
// eigene Zeile.
function QuietAfter(AMap: TRdxCodeMap; const B: TRdxToken): Boolean;
var
  L : string;
  c : Integer;
begin
  L := AMap.Raw(B.Line);
  for c := B.EndCol to Length(L) do
    if not IsBlank(L[c])
       and (AMap.IsCode(B.Line, c) or OpensDirective(AMap, B.Line, c)) then
      Exit(False);
  Result := (B.Line >= AMap.LineCount) or not AMap.StartsInside(B.Line + 1);
end;

{ ---- Methodendeklaration und Exit (geteilt mit uRdxInheritedFixes) ---- }

// Die Deklarationen der Methode R im Rumpf ihrer Klasse.
function DeclHeadsOf(var AScan: TRdxScan;
  const R: TRdxRoutine): TArray<TRdxToken>;
begin
  Result := MethodDecls(AScan, OwnerPathOf(R.Name), LastPart(R.Name));
end;

// Die EINE Deklaration der Methode R. '' oder der Grund. Mehrere Koepfe
// kommen auch aus mehreren Klassen gleichen letzten Namens ('TA.TItem',
// 'TB.TItem' - ClassHeads schluesselt nur danach): dann heisst der Grund
// "mehrdeutig" wie bei OwnerOf (uRdxInheritedFixes), nicht "Overload?"
// (Review Woche G08-06; SCA121 fragt OwnerOf nicht).
function DeclOf(var AScan: TRdxScan; const R: TRdxRoutine;
  out D: TRdxRoutine): string;
var
  Heads   : TArray<TRdxToken>;
  NClass  : Integer;
begin
  D := Default(TRdxRoutine);
  Heads := DeclHeadsOf(AScan, R);
  if Length(Heads) = 0 then
    Exit(Format('keine Deklaration von %s im Rumpf der Klasse %s - %s',
      [LastPart(R.Name), OwnerPathOf(R.Name), R_MOVED]));
  NClass := Length(ClassHeads(AScan, OwnerPathOf(R.Name)));
  if (Length(Heads) > 1) and (NClass > 1) then
    Exit(Format('%d Klassen namens %s in der Unit - mehrdeutig',
      [NClass, LastPart(OwnerPathOf(R.Name))]));
  if Length(Heads) > 1 then
    Exit(Format('%d Deklarationen von %s in Klassen dieses Namens - '
      + 'Overload?', [Length(Heads), LastPart(R.Name)]));
  Result := TRdxBlocks.MethodDecl(AScan.Map, Heads[0], D);
  if Result <> '' then
    Result := 'Deklaration: ' + Result;
end;

// Steht das Wort T (APrev davor) hinter 'System.' - 'System.Exit', das Exit
// der RTL? Hinter '.' ist ein Wort kein Schluesselwort (IsKeywordAfter),
// der Sprung blieb so ungesehen (Gegen-Review R5, R5-05). 'TMonitor.Exit'
// bzw. 'Foo.System.Exit' zaehlen nicht. Dieselbe Probe steht in
// uRdxTryFixes (SystemQualified).
function SystemQualified(AMap: TRdxCodeMap; const T, APrev: TRdxToken): Boolean;
var
  Q : TRdxToken;
begin
  Result := False;
  if (APrev.Low <> '.') or not T.IsWord then Exit;
  Q := Before(AMap, APrev);
  Result := (Q.Low = SYSTEM_UNIT) and (Before(AMap, Q).Low <> '.');
end;

// Exit an T (APrev davor) - als Schluesselwort oder als 'System.Exit'?
function IsExitAt(AMap: TRdxCodeMap; const T, APrev: TRdxToken): Boolean;
begin
  Result := (T.Low = 'exit')
    and (IsKeywordAfter(T, APrev) or SystemQualified(AMap, T, APrev));
end;

{ ---- Result (SCA121, SCA196) ---- }

// Gibt es Result? Nicht in den FPC-Modi fpc/tp/macpas/iso und nicht unter
// '{$X-}' bzw. '{$EXTENDEDSYNTAX OFF}' (auch in einer Schalterliste
// '{$H+,X-}'). '' oder der Grund.
function DirectiveResultReason(AMap: TRdxCodeMap; ALine, ACol: Integer): string;
var
  W, Args, Sw : string;
  Arg         : Boolean;
begin
  Result := '';
  W := DirectiveWord(AMap, ALine, ACol, Arg);
  Args := LowerCase(Trim(DirectiveArgs(AMap, ALine, ACol)));
  if (W = 'mode') and InList(Args, NO_RESULT_MODES) then
    Exit(Format('{$mode %s} in Zeile %d - dort gibt es kein Result',
      [Args, ALine]));
  if (W = 'extendedsyntax') and (Copy(Args, 1, 3) = 'off') then
    Exit(Format('{$EXTENDEDSYNTAX OFF} in Zeile %d - dort gibt es kein '
      + 'Result', [ALine]));
  if Length(W) <> 1 then Exit;
  Sw := ',' + StringReplace(W + Args, ' ', '', [rfReplaceAll]) + ',';
  if Pos(',x-,', Sw) > 0 then
    Result := Format('{$X-} in Zeile %d - dort gibt es kein Result', [ALine]);
end;

function ResultModeReason(AMap: TRdxCodeMap): string;
var
  Li, Co : Integer;
  L      : string;
begin
  Result := '';
  for Li := 1 to AMap.LineCount do
  begin
    L := AMap.Raw(Li);
    for Co := 1 to Length(L) do
      if CharInSet(L[Co], ['{', '(']) and OpensDirective(AMap, Li, Co) then
      begin
        Result := DirectiveResultReason(AMap, Li, Co);
        if Result <> '' then Exit;
      end;
  end;
end;

// Hat R den Namen AName (letztes Glied, ohne Typparameter)? '' oder der
// Grund.
function NameReason(const R: TRdxRoutine; const AName: string): string;
var
  N : string;
begin
  Result := '';
  N := AName;
  if Pos('<', N) > 0 then
    N := Copy(N, 1, Pos('<', N) - 1);
  if not SameIdent(LowerCase(LastPart(R.Name)), LowerCase(N)) then
    Result := Format('die Routine heisst %s, die Meldung nennt %s - %s',
      [R.Name, AName, R_MOVED]);
end;

// Der Rueckgabetyp hinter dem Namen von R: ':' hinter Typparametern und
// Parameterliste bis vor das ';' des Kopfs, wie im Quelltext. AType = ''
// ohne ':' (Implementierungskopf ohne Signatur). '' oder der Grund.
function TypeAfterHead(AMap: TRdxCodeMap; const R: TRdxRoutine;
  out AType: string): string;
var
  T : TRdxToken;
begin
  AType := '';
  Result := '';
  T := After(AMap, R.NameTok);
  if T.Low = '<' then
    T := AfterClose(AMap, T);
  if T.Low = '(' then
    T := AfterClose(AMap, T);
  if T.Low <> ':' then Exit;
  if T.Line <> R.HeaderEnd.Line then
    Exit('Rueckgabetyp ueber mehrere Zeilen - ' + R_BY_HAND);
  if AMap.HasNonCode(T.Line, T.EndCol, R.HeaderEnd.Col - 1) then
    Exit('Kommentar oder Direktive im Rueckgabetyp - ' + R_BY_HAND);
  AType := Trim(Copy(AMap.Raw(T.Line), T.EndCol, R.HeaderEnd.Col - T.EndCol));
end;

// Der Rueckgabetyp von R - aus dem Kopf, bei einer Methode ohne Signatur
// aus ihrer Deklaration im Klassenrumpf. '' oder der Grund.
function ResultTypeOf(var AScan: TRdxScan; const R: TRdxRoutine;
  out AType: string): string;
var
  D : TRdxRoutine;
begin
  Result := TypeAfterHead(AScan.Map, R, AType);
  if (Result <> '') or (AType <> '') then Exit;
  if Length(R.Parts) < 2 then
    Exit('Kopf ohne Rueckgabetyp, keine Methode - die Deklaration liest die '
      + 'Hilfe nicht; ' + R_BY_HAND);
  Result := DeclOf(AScan, R, D);
  if Result = '' then
    Result := TypeAfterHead(AScan.Map, D, AType);
  if (Result = '') and (AType = '') then
    Result := 'auch die Deklaration nennt keinen Rueckgabetyp';
end;

// SCA121: passt AType in Default()? Ein Typbezeichner, Glieder mit '.',
// Typargumente '<..>' - kein FPC 'specialize', keine Klammern. '' oder der
// Grund.
function TypeTextReason(const AType: string): string;
var
  i : Integer;
begin
  Result := '';
  if HasAsciiWord(LowerCase(AType), 'specialize') then
    Exit('FPC "specialize" im Rueckgabetyp - Default() mit dem Typ von Hand');
  for i := 1 to Length(AType) do
    if not (IsIdentChar(AType[i]) or CharInSet(AType[i], ['.', '<', '>', ',', ' '])) then
      Exit(Format('Rueckgabetyp "%s" ist kein einfacher Typbezeichner - %s',
        [AType, R_BY_HAND]));
end;

// SCA121: steht hinter dem Namen T - ueber Selektoren '.X', '[..]', '^' -
// ein ':='? ('Result := ..', 'Result.X := ..', 'F[I] := ..').
function AssignsAt(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
var
  N : TRdxToken;
begin
  N := After(AMap, T);
  while InList(N.Low, ['.', '[', '^']) do
    if N.Low = '[' then
      N := AfterClose(AMap, N)
    else if N.Low = '.' then
      N := After(AMap, After(AMap, N))
    else
      N := After(AMap, N);
  Result := N.Low = ':=';
end;

// SCA121: schreibt das Token T (davor APrev) Result - 'Result := ..' bzw.
// 'Name := ..' mit dem Funktionsnamen ALowName, auch ueber Selektoren, oder
// 'Exit(Wert)' (auch 'System.Exit(Wert)', IsExitAt)?
function WritesResult(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  const ALowName: string): Boolean;
var
  N : TRdxToken;
begin
  if IsExitAt(AMap, T, APrev) then
  begin
    N := After(AMap, T);
    Exit((N.Low = '(') and (After(AMap, N).Low <> ')'));
  end;
  Result := IsKeywordAfter(T, APrev)
    and ((T.Low = KW_RESULT) or SameIdent(T.Low, ALowName))
    and AssignsAt(AMap, T);
end;

// SCA121: weist der Rumpf Result oder dem Funktionsnamen irgendwo zu - auch
// in einem inaktiven $IFDEF-Zweig (die Code-Sicht liest jeden Zweig als
// Code) oder in einer anonymen Methode -, oder steht dort Exit(Wert)? Dann
// sah der Detektor die Zuweisung nur nicht, und die Hilfe ginge ueber einen
// Fehlfund (Gegen-Review H5, Minor 5: 34 der 132 Angebote; Indy
// IdStackDotNet weist Result nur unter $IFDEF DOTNET zu). Lokale Routinen
// stehen vor dem begin und zaehlen nicht - TES5Edit wbDataFormatNif: eine
// lokale Prozedur haengt an Result an, die Funktion selbst weist nie zu;
// dieses Angebot bleibt. '' oder der Grund.
function AssignedReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  T, P : TRdxToken;
  Name : string;
begin
  Result := '';
  Name := LowerCase(LastPart(R.Name));
  P := R.Body;
  T := After(AMap, R.Body);
  while (T.Low <> '') and not SameTok(T, R.EndTok) do
  begin
    if WritesResult(AMap, T, P, Name) then
      Exit(Format('%s in Zeile %d schreibt Result (inaktiver Zweig?) - der '
        + 'Detektor sah es nicht, der Fund ist fraglich; %s',
        [TokText(AMap, T), T.Line, R_BY_HAND]));
    P := T;
    T := After(AMap, T);
  end;
end;

// SCA121: der Anfangswert eines Typs der RTL (BOOLEAN_TYPES ... POINTER_TYPES,
// dynamische Arrays, Klassen und Interfaces der Delphi-Quellen) fuer ALow
// (klein, ohne Leerraum und 'system.'); '' fuer alle anderen.
function RtlTypeValue(const ALow: string): string;
begin
  Result := '';
  if InList(ALow, BOOLEAN_TYPES) then
    Result := VALUE_FALSE
  else if InList(ALow, NUMBER_TYPES) then
    Result := VALUE_ZERO
  else if InList(ALow, STRING_TYPES) or (Copy(ALow, 1, 7) = 'string[') then
    Result := VALUE_EMPTY
  else if InList(ALow, CHAR_TYPES) then
    Result := VALUE_NUL
  else if InList(ALow, POINTER_TYPES) or InList(ALow, RTL_DYN_ARRAYS)
     or (ALow = 'tbytes') or (Copy(ALow, 1, 7) = 'tarray<')
     or IsRtlClassOrInterface(ALow) then
    Result := VALUE_NIL;
end;

// SCA121: der Anfangswert der Aufzaehlung AType ab ihrem '(' K -
// 'System.Low(T)', wenn sie schlicht ist (nur Namen mit ',', kein '=' fuer
// eigene Ordinalwerte: dann ist es derselbe Wert wie Default(T)); sonst ''.
// Bis Charge B1-FE stand hier der erste Wert selbst - ein Member gleichen
// Namens (property bzw. Feld 'None') verdeckte ihn (Gegen-Review R5,
// R5-06); das unqualifizierte 'Low(T)' der Charge B1-FE verdeckte ebenso jedes
// andere Low im Gueltigkeitsbereich - eine Property bzw. ein Feld der Klasse,
// eines Vorfahren oder eines Records, eine Variable der Unit (Nachpruefung
// R5-06: neben 'property Low' uebersetzte 'Result := Low(TKind);' nicht).
// Qualifiziert verdeckt es nur ein Bezeichner System: nennt die Unit selbst
// einen (OwnSystem), '' - dann Default(T). Unit-qualifizierte
// Compiler-Funktionen stehen so in den Delphi-Quellen 37.0 (System.Length,
// System.SizeOf), in JCL/JVCL (System.Length) und DWScript ('System.High(
// Self)' in einem Helper mit eigenem High); FPC 3.2.2 uebersetzt
// System.Low(T) neben property, Feld und Parameter Low (Modi delphi,
// delphiunicode, objfpc). {$SCOPEDENUMS} spielt keine Rolle.
function EnumValue(var AScan: TRdxScan; const K: TRdxToken;
  const AType: string): string;
var
  T, C : TRdxToken;
begin
  Result := '';
  T := After(AScan.Map, K);
  C := MatchClose(AScan.Map, K);
  if not T.IsWord or (C.Low = '') then Exit;
  while not SameTok(T, C) do
  begin
    if not (T.IsWord or (T.Low = ',')) then Exit;
    T := After(AScan.Map, T);
  end;
  IndexScan(AScan);
  if not AScan.OwnSystem then
    Result := Format(ENUM_FIRST_FMT, [AType]);
end;

// SCA121: der Anfangswert nach der Definition K ('=' davor, TypeDefsOf) des
// Typs AType - Klasse, Metaklasse, Interface, Zeiger, Routinentyp und
// dynamisches Array: nil; Menge: []; String-Alias: ''; schlichte
// Aufzaehlung: System.Low(T) (EnumValue); sonst '' (dann Default(T)).
function DefValue(var AScan: TRdxScan; const K: TRdxToken;
  const AType: string): string;
var
  N : TRdxToken;
begin
  Result := '';
  N := After(AScan.Map, K);
  if InList(K.Low, NIL_KINDS) or ((K.Low = 'array') and (N.Low = 'of'))
     or ((K.Low = 'tarray') and (N.Low = '<')) then
    Result := VALUE_NIL
  else if (K.Low = 'set') and (N.Low = 'of') then
    Result := VALUE_EMPTY_SET
  else if InList(K.Low, STRING_TYPES) then
    Result := VALUE_EMPTY
  else if K.Low = '(' then
    Result := EnumValue(AScan, K, AType);
end;

// SCA121: steht eine Definition ADefs des Rueckgabetyps AType im
// Deklarationsteil der Funktion R selbst ('function GetMode: TMode; type
// TMode = (xA, xB); begin')? Dann meint der Name im Kopf den aeusseren Typ,
// im Rumpf den lokalen - 'Default(TMode)' bzw. 'System.Low(TMode)' passten
// nicht zu Result (Nachpruefung R5-06: FPC "Incompatible types"; bis dahin
// lehnte die Hilfe nur ab, wenn auch die Unit den Namen anders definierte).
// '' oder der Grund.
function OwnLocalTypeReason(const R: TRdxRoutine;
  const ADefs: TArray<TRdxToken>; const AType: string): string;
var
  K : TRdxToken;
begin
  Result := '';
  for K in ADefs do
    if TokBefore(R.Head, K) and TokBefore(K, R.Body) then
      Exit(Format('%s ist auch im Deklarationsteil der Funktion definiert '
        + '(Zeile %d) - im Rumpf meint der Name diesen Typ, im Kopf den '
        + 'aeusseren; %s', [AType, K.Line, R_BY_HAND]));
end;

// SCA121: der Anfangswert fuer den Rueckgabetyp AType (wie im Kopf) der
// Funktion R in AValue: deklariert die Unit den Namen selbst, nach ihrer
// Definition (DefValue; mehrere Definitionen unter $IFDEF muessen denselben
// Wert ergeben), sonst nach der RTL (RtlTypeValue); wo kein Literal passt -
// Records, Typparameter, Unbekanntes -, 'Default(AType)'. Steht eine
// Definition des Namens nicht auf Unit-Ebene (AtUnitLevel: geschachtelt in
// einer Klasse, lokal in einer anderen Routine), haengt am
// Gueltigkeitsbereich, welche gilt - dann Default(AType), das der Compiler
// wie den Kopf aufloest (Gegen-Review R5, R5-06); eine Definition in R
// selbst sperrt (OwnLocalTypeReason). '' oder der Grund.
function InitValueFor(var AScan: TRdxScan; const R: TRdxRoutine;
  const AType: string; out AValue: string): string;
var
  Low, Base, V : string;
  K            : TRdxToken;
  Defs         : TArray<TRdxToken>;
begin
  Low := LowerCase(StringReplace(AType, ' ', '', [rfReplaceAll]));
  if Copy(Low, 1, 7) = 'system.' then
    Delete(Low, 1, 7);
  Base := Low;
  if Pos('<', Base) > 0 then
    Base := Copy(Base, 1, Pos('<', Base) - 1);
  Defs := nil;
  if Pos('.', Base) = 0 then
    Defs := TypeDefsOf(AScan, Base);
  AValue := 'Default(' + AType + ')';
  Result := OwnLocalTypeReason(R, Defs, AType);
  if (Result <> '') or not AllAtUnitLevel(AScan.Map, Defs) then Exit;
  AValue := RtlTypeValue(Low);
  if Length(Defs) > 0 then
    AValue := DefValue(AScan, Defs[0], AType);
  for K in Defs do
  begin
    V := DefValue(AScan, K, AType);
    if V <> AValue then
      Exit(Format('%s ist in dieser Unit mehrfach verschieden definiert '
        + '($IFDEF-Zweige?) - %s', [AType, R_BY_HAND]));
  end;
  if AValue = '' then
    AValue := 'Default(' + AType + ')';
end;

// SCA121: traegt die Datei Spuren von Compilern vor Delphi 2009 bzw. FPC
// 3.0, die Default() nicht kennen (uRdxCompilerTraces, FLOOR_DEFAULT_FN)?
// Gegen-Review H5, Minor 4: CnWizards baut ab Delphi 5 (CnWizUtils), JVCL
// setzt Result teils nur ab DELPHI2007_UP. Die Suche steht seit Charge Q14
// in uRdxCompilerTraces (SCA014 braucht sie mit der Schwelle 10.3). '' oder
// der Grund.
function OldCompilerReason(AMap: TRdxCodeMap): string;
var
  Li : Integer;
  S  : string;
begin
  Result := '';
  S := OldCompilerTrace(AMap, FLOOR_DEFAULT_FN, Li);
  if S <> '' then
    Result := Format('Default() gibt es erst ab Delphi 2009 bzw. FPC 3.0 - '
      + 'die Datei traegt Spuren aelterer Compiler (%s, Zeile %d); %s',
      [S, Li, R_BY_HAND]);
end;

// SCA121: der Wert fuer 'Result := <Wert>;' zur Funktion R in AValue
// (InitValueFor); Default(T) nur mit einfachem Typbezeichner
// (TypeTextReason), ohne Spuren alter Compiler (OldCompilerReason) und
// nicht in einem Skript bzw. Include (ScriptReason). '' oder der Grund.
function ValueReason(var AScan: TRdxScan; const R: TRdxRoutine;
  out AValue: string): string;
var
  TypeTx : string;
begin
  AValue := '';
  TypeTx := '';
  Result := ResultTypeOf(AScan, R, TypeTx);
  if Result = '' then
    Result := InitValueFor(AScan, R, TypeTx, AValue);
  if (Result <> '') or (AValue <> 'Default(' + TypeTx + ')') then Exit;
  Result := TypeTextReason(TypeTx);
  if Result = '' then
    Result := OldCompilerReason(AScan.Map);
  // Skript bzw. Include: nur Default() kennt der Interpreter nicht - ein
  // Literal geht (bis Review Woche G08-07 sperrte ScriptReason vor der
  // Wertwahl jede Skript-Unit).
  if Result = '' then
    Result := ScriptReason(AScan.Map, FEATURE_DEFAULT);
end;

// SCA196: gleicher Typ wie in der Meldung (ohne Leerraum, Gross/klein
// egal)?
function SameTypeText(const A, B: string): Boolean;
begin
  Result := SameText(StringReplace(A, ' ', '', [rfReplaceAll]),
    StringReplace(B, ' ', '', [rfReplaceAll]));
end;

// SCA196: 'X: T absolute Result' im Deklarationsteil - geschrieben wird
// ueber den Alias. '' oder der Grund.
function AbsoluteReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  T : TRdxToken;
begin
  Result := '';
  T := After(AMap, R.HeaderEnd);
  while (T.Low <> '') and not SameTok(T, R.Body) do
  begin
    if (T.Low = 'absolute') and (After(AMap, T).Low = KW_RESULT) then
      Exit(Format('"absolute Result" in Zeile %d - Result wird ueber den '
        + 'Alias geschrieben; %s', [T.Line, R_BY_HAND]));
    T := After(AMap, T);
  end;
end;

// SCA196: steht Result auf der gemeldeten Lese-Zeile als Code (nicht als
// Member 'X.Result')?
function ReadsResultOn(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  T, P : TRdxToken;
begin
  Result := False;
  T := NextToken(AMap, ALine, 1);
  P := Before(AMap, T);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if (T.Low = KW_RESULT) and (P.Low <> '.') then
      Exit(True);
    P := T;
    T := After(AMap, T);
  end;
end;

// SCA196: ein dynamisches Array? Die Namen der RTL oder 'Name = array of'
// bzw. 'Name = TArray<..>' in der Unit.
function DynArrayProven(var AScan: TRdxScan; const ALow: string): Boolean;
var
  K : TRdxToken;
begin
  if InList(ALow, RTL_DYN_ARRAYS) then
    Exit(True);
  K := TypeDeclKind(AScan, ALow, ARRAY_KINDS);
  Result := ((K.Low = 'array') and (After(AScan.Map, K).Low = 'of'))
    or ((K.Low = 'tarray') and (After(AScan.Map, K).Low = '<'));
end;

// SCA196: ein Interface? 'I' + Grossbuchstabe und als Interface in der
// Unit deklariert bzw. ein Typ der Delphi-Quellen (uRdxRtlTypes). Dort
// stehen Klassen UND Interfaces, und die I-Schreibweise trennt sie NICHT
// (Winapi.D3D10: ID3D10EffectPass = class - Gegen-Review H5, Minor 8); fuer
// 'Result := nil' ist das gleich, beide nehmen nil.
function InterfaceProven(var AScan: TRdxScan; const AType: string): Boolean;
var
  Name : string;
begin
  Name := LastPart(AType);
  if Pos('<', Name) > 0 then
    Name := Copy(Name, 1, Pos('<', Name) - 1);
  Result := (Length(Name) >= 2) and (Name[1] = 'I')
    and CharInSet(Name[2], ['A'..'Z'])
    and (DeclaredAs(AScan, LowerCase(Name), INTERFACE_KINDS)
         or IsRtlClassOrInterface(LowerCase(Name)));
end;

// SCA196: die Initialisierung nach der Definition K des Typs in der Unit
// (TypeDefsOf): dynamisches Array, Interface, Klasse -> nil; String-Alias
// -> ''; Variant-Alias -> VarClear; sonst ''.
function DefStatement(AMap: TRdxCodeMap; const K: TRdxToken): string;
var
  N : TRdxToken;
begin
  Result := '';
  N := After(AMap, K);
  if ((K.Low = 'array') and (N.Low = 'of'))
     or ((K.Low = 'tarray') and (N.Low = '<'))
     or InList(K.Low, INTERFACE_KINDS) or (K.Low = KW_CLASS) then
    Result := STMT_NIL
  else if InList(K.Low, STRING_TYPES) then
    Result := STMT_EMPTY_STRING
  else if InList(K.Low, VARIANT_TYPES) then
    Result := STMT_VARCLEAR;
end;

// SCA196: deklariert die Unit den Typnamen ALowBase (ohne Typargumente)
// selbst, gilt nur ihre Definition - 'TBytes = array[0..3] of Byte'
// uebersetzte 'Result := nil' nicht (Gegen-Review H5, Minor 8). Mehrere
// Definitionen ($IFDEF) muessen dieselbe Anweisung ergeben; eine, die nicht
// auf Unit-Ebene steht (AtUnitLevel), sperrt - welche gilt, haengt am
// Gueltigkeitsbereich (Gegen-Review R5, R5-06: ein lokales 'RawUtf8 = array
// of Byte' einer anderen Routine machte 'Result := nil;' fuer mORMots
// RawUtf8). '' oder der Grund; AStmt leer, wenn die Unit den Namen nicht
// deklariert.
function OwnTypeStatement(var AScan: TRdxScan; const ALowBase, AType: string;
  out AStmt: string): string;
var
  K     : TRdxToken;
  S     : string;
  First : Boolean;
begin
  Result := '';
  AStmt := '';
  First := True;
  for K in TypeDefsOf(AScan, ALowBase) do
  begin
    // AtUnitLevel ist auch False, wenn eine Routine davor nicht sicher zu
    // lesen ist (Review Woche G08-03) - der Grund nennt beides.
    if not AtUnitLevel(AScan.Map, K) then
      Exit(Format('%s ist in dieser Unit auch in einer Routine bzw. einem '
        + 'Typ definiert (Zeile %d), oder eine Routine davor ist nicht '
        + 'sicher zu lesen - welche Definition gilt, haengt am '
        + 'Gueltigkeitsbereich; %s', [AType, K.Line, R_BY_HAND]));
    S := DefStatement(AScan.Map, K);
    if S = '' then
      Exit(Format('%s ist in dieser Unit als "%s ..." definiert (Zeile %d) - '
        + 'kein dynamisches Array, Interface, String oder Variant; %s',
        [AType, TokText(AScan.Map, K), K.Line, R_BY_HAND]));
    if not First and (S <> AStmt) then
      Exit(Format('%s ist in dieser Unit mehrfach verschieden definiert '
        + '($IFDEF-Zweige?) - %s', [AType, R_BY_HAND]));
    AStmt := S;
    First := False;
  end;
end;

// SCA196: die Initialisierung fuer den Rueckgabetyp AType (ohne ';'). ''
// oder der Grund; AVariants bei VarClear. Ein unqualifizierter Name, den
// die Unit selbst deklariert, gilt nach ihrer Definition (OwnTypeStatement),
// alle anderen nach der RTL.
function StatementFor(var AScan: TRdxScan; const AType: string;
  out AStmt: string; out AVariants: Boolean): string;
var
  Low, Base : string;
begin
  Result := '';
  AStmt := '';
  AVariants := False;
  Low := LowerCase(StringReplace(AType, ' ', '', [rfReplaceAll]));
  Base := Low;
  if Pos('<', Base) > 0 then
    Base := Copy(Base, 1, Pos('<', Base) - 1);
  if Pos('.', Base) = 0 then
    Result := OwnTypeStatement(AScan, Base, AType, AStmt);
  if (Result <> '') or (AStmt <> '') then
  begin
    AVariants := AStmt = STMT_VARCLEAR;
    Exit;
  end;
  if Copy(Low, 1, 7) = 'system.' then
    Delete(Low, 1, 7);
  if InList(Low, STRING_TYPES) or (Copy(Low, 1, 7) = 'string[') then
    AStmt := STMT_EMPTY_STRING
  else if (Low = 'tbytes') or (Copy(Low, 1, 7) = 'tarray<') then
    AStmt := STMT_NIL
  else if InList(Low, VARIANT_TYPES) then
  begin
    AStmt := STMT_VARCLEAR;
    AVariants := True;
  end
  else if DynArrayProven(AScan, Low) or InterfaceProven(AScan, AType) then
    AStmt := STMT_NIL
  else
    Result := Format('Rueckgabetyp %s ist nicht als String, dynamisches '
      + 'Array, Interface oder Variant bewiesen - %s', [AType, R_BY_HAND]);
end;

{ ---- Gemeinsame Nachweise ---- }

// SCA196: die Funktion um die Lese-Zeile ALine - auf der Zeile steht
// Result, die innerste Routine heisst AName, hat einen begin-Rumpf ohne
// asm, Result gibt es (Modus), ihr Rueckgabetyp ist AMsgType, kein
// 'absolute Result'. '' oder der Grund; ACtx.TypeTx wie im Quelltext.
function FuncCtxReason(var AScan: TRdxScan; ALine: Integer;
  const AName, AMsgType: string; out ACtx: TRdxFuncCtx): string;
begin
  ACtx := Default(TRdxFuncCtx);
  if not ReadsResultOn(AScan.Map, ALine) then
    Exit(R_NO_READ);
  Result := EnclosingRoutine(AScan.Map, ALine, ACtx.Routine);
  if Result = '' then
    Result := NameReason(ACtx.Routine, AName);
  if Result = '' then
    Result := BodyReason(AScan.Map, ACtx.Routine);
  if Result = '' then
    Result := ResultModeReason(AScan.Map);
  if Result = '' then
    Result := ResultTypeOf(AScan, ACtx.Routine, ACtx.TypeTx);
  if (Result = '') and not SameTypeText(ACtx.TypeTx, AMsgType) then
    Result := Format('der Kopf nennt %s, die Meldung %s - %s',
      [ACtx.TypeTx, AMsgType, R_MOVED]);
  if Result = '' then
    Result := AbsoluteReason(AScan.Map, ACtx.Routine);
end;

{ ---- Gemeinsamer Abschluss ---- }

// AReason = '': die Ersetzung in den Plan; sonst Ersetzungen leeren.
function FinishPlan(var APlan: TRdxResultPlan;
  const AEdits: TArray<TRdxEdit>; const AReason: string): Boolean;
begin
  Result := AReason = '';
  if Result then
    APlan.Edits := AEdits
  else
    APlan.Edits := nil;
end;

// Der Rumpf von R mit AStmt als erster Anweisung (fuer FinishPlan).
function FirstEdits(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const AStmt: string; out AEdits: TArray<TRdxEdit>): string;
var
  E : TRdxEdit;
begin
  AEdits := nil;
  Result := TRdxResultFixes.FirstStatement(AMap, R, AStmt, E);
  if Result = '' then
    AddEdit(AEdits, E);
end;

{ TRdxResultFixes }

class function TRdxResultFixes.FirstStatement(AMap: TRdxCodeMap;
  const R: TRdxRoutine; const AStmt: string; out AEdit: TRdxEdit): string;
var
  B : TRdxToken;
  L : string;
begin
  AEdit := Default(TRdxEdit);
  B := R.Body;
  if B.Low <> KW_BEGIN then
    Exit('kein begin-Rumpf');
  L := AMap.Raw(B.Line);
  if QuietAfter(AMap, B) then
  begin
    AEdit.Span := TRefactorSpan.Make(SPAN_RESULT, B.Line, B.Col, B.Line,
      Length(L) + 1);
    AEdit.Expected := Copy(L, B.Col, MaxInt);
    AEdit.NewText := AEdit.Expected + #10 + BodyIndent(AMap, R) + AStmt;
  end
  else
    AEdit := TokenEdit(AMap, B, TokText(AMap, B) + ' ' + AStmt);
  Result := '';
end;

class function TRdxResultFixes.LastStatement(AMap: TRdxCodeMap;
  const R: TRdxRoutine; const AStmt: string;
  out AEdits: TArray<TRdxEdit>): string;
var
  Last, En : TRdxToken;
  E        : TRdxEdit;
  Li, Co   : Integer;
  Semi     : string;
begin
  AEdits := nil;
  if R.Body.Low <> KW_BEGIN then
    Exit('kein begin-Rumpf');
  En := R.EndTok;
  Last := Before(AMap, En);
  if SameTok(Last, R.Body) then
    Exit(FirstEdits(AMap, R, AStmt, AEdits));
  if DirectiveBetween(AMap, Last, En.Line, En.Col) then
    Exit('Compiler-Direktive zwischen der letzten Anweisung und end - das '
      + 'Ende kann je Zweig anders aussehen; ' + R_BY_HAND);
  // Die letzte Anweisung endet am letzten Zeichen aus Code ODER String vor
  // end - der Token-Leser sieht keine Strings: 'FState := ''x''' endete
  // fuer ihn auf ':=', und das ';' bzw. 'inherited;' kam vor das Literal
  // (Gegen-Review R5, R5-01: 'FState :=; ''x''', bei TObject-Erben als
  // bedeutungsgleich gekennzeichnet).
  if not LastCharBefore(AMap, En, Li, Co) then
    Exit('Ende der letzten Anweisung nicht gefunden');
  Semi := '';
  if (Copy(AMap.Raw(Li), Co, 1) <> ';') or not AMap.IsCode(Li, Co) then
    Semi := ';';
  if OwnLineAt(AMap, En) then
  begin
    if Semi <> '' then
      AddEdit(AEdits, CharEdit(AMap, Li, Co, Semi));
    E.Span := TRefactorSpan.Make(SPAN_RESULT, En.Line, 1, En.Line, En.EndCol);
    E.Expected := Copy(AMap.Raw(En.Line), 1, En.EndCol - 1);
    E.NewText := BodyIndent(AMap, R) + AStmt + #10 + E.Expected;
    AddEdit(AEdits, E);
  end
  else
    AddEdit(AEdits, CharEdit(AMap, Li, Co, Semi + ' ' + AStmt));
  Result := '';
end;

class function TRdxResultFixes.ResultDefault(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxResultPlan;
  out AReason: string): Boolean;
var
  Scan  : TRdxScan;
  R     : TRdxRoutine;
  Name  : string;
  Value : string;
  Edits : TArray<TRdxEdit>;
begin
  APlan := Default(TRdxResultPlan);
  Edits := nil;
  Value := '';
  AReason := '';
  Scan := NewScan(AMap);
  Name := TextBetween(AMessage, KEY_FUNC, KEY_NEVER);
  if Name = '' then
    AReason := 'Name der Funktion fehlt in der Meldung';
  if AReason = '' then
    AReason := RoutineOnLine(AMap, ALine, 'function|operator',
      'einer Funktion', R);
  if AReason = '' then
    AReason := NameReason(R, Name);
  if AReason = '' then
    AReason := BodyReason(AMap, R);
  if AReason = '' then
    AReason := ResultModeReason(AMap);
  if AReason = '' then
    AReason := AssignedReason(AMap, R);
  if AReason = '' then
  begin
    AReason := ValueReason(Scan, R, Value);
    APlan.Name := Value;
  end;
  if AReason = '' then
    AReason := FirstEdits(AMap, R, 'Result := ' + Value + ';', Edits);
  Result := FinishPlan(APlan, Edits, AReason);
end;

class function TRdxResultFixes.ManagedResultInit(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxResultPlan;
  out AReason: string): Boolean;
var
  Scan    : TRdxScan;
  Ctx     : TRdxFuncCtx;
  Name    : string;
  MsgType : string;
  Stmt    : string;
  Vars    : Boolean;
  Edits   : TArray<TRdxEdit>;
begin
  APlan := Default(TRdxResultPlan);
  Edits := nil;
  AReason := '';
  Scan := NewScan(AMap);
  Name := TextBetween(AMessage, KEY_FUNC, KEY_READS);
  MsgType := TextBetween(AMessage, KEY_TYPE, KEY_TYPE_END);
  if (Name = '') or (MsgType = '') then
    AReason := 'Funktion oder Rueckgabetyp fehlt in der Meldung'
  // Der Name im Menue schon aus der Meldung (der Beweis folgt).
  else if StatementFor(Scan, MsgType, Stmt, Vars) = '' then
    APlan.Name := Stmt;
  if AReason = '' then
    AReason := FuncCtxReason(Scan, ALine, Name, MsgType, Ctx);
  if AReason = '' then
    AReason := StatementFor(Scan, Ctx.TypeTx, Stmt, Vars);
  if AReason = '' then
  begin
    APlan.Name := Stmt;
    APlan.NeedsVariants := Vars;
    AReason := FirstEdits(AMap, Ctx.Routine, Stmt + ';', Edits);
  end;
  Result := FinishPlan(APlan, Edits, AReason);
end;

end.

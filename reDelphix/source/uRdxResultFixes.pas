unit uRdxResultFixes;

// reDelphix - Quick-Fixes "Ergebnis und Konstruktoren", OHNE ToolsAPI und
// ohne Parser (Konzept_Editorhilfen_Recherche_2026-10-11, Abschnitt 5
// Bausteine "Routinengrenzen" und "Result := Default(T)-Einfueger",
// Abschnitt 6 Charge H5):
//   SCA096 ConstructorWithoutInherited: als erste Anweisung des Rumpfs
//          (a) 'inherited Create;', wenn 'inherited Create' in dieser Unit
//              belegt TObject.Create ruft: die Klasse erbt DIREKT von
//              TObject ('class', 'class(TObject)', als erster Eintrag ein
//              unqualifiziertes Interface der Unit) oder von einem
//              Vorfahren ohne eigenen Konstruktor (NO_CTOR_PARENTS:
//              TPersistent, TInterfacedObject, TCustomAttribute - in den
//              Delphi-Quellen nachgesehen, s. dort). TObject.Create ist
//              leer, gleiche Bedeutung. Nie nacktes 'inherited;': es
//              reichte die eigenen Parameter weiter, und TObject hat keinen
//              Konstruktor mit Parametern;
//          (b) 'inherited;', wenn die Deklaration 'override' traegt -
//              Delphi uebersetzt es gegen den ueberschriebenen Konstruktor
//              mit denselben Parametern; gekennzeichnet (E2): der
//              Elternkonstruktor laeuft danach.
//          Ein Eintrag je Fund; die Variante waehlt der Planer (wie SCA149
//          override/reintroduce in uRdxDeclFixes). Erbt die Klasse von
//          etwas anderem und fehlt 'override', ist die Wahl des
//          Elternkonstruktors Entwurf - keine Hilfe.
//   SCA097 DestructorWithoutInherited: 'inherited;' als letzte Anweisung
//          vor dem end des Rumpfs (fehlt der letzten Anweisung das ';',
//          kommt es mit). Nur mit 'override' an der Deklaration (sonst
//          verdeckt Destroy die virtuelle Methode - eigentlich SCA149).
//          Gekennzeichnet, ausser die Klasse erbt direkt von TObject
//          (TObject.Destroy ist leer; TPersistent.Destroy nicht).
//   SCA121 RoutineResultUnassigned: 'Result := <Wert>;' als erste
//          Anweisung, der Wert nach dem Rueckgabetyp T (aus dem Kopf bzw.
//          bei einem Implementierungskopf ohne Signatur aus der Deklaration
//          im Klassenrumpf): ein Literal, wo der Typ es traegt - False,
//          0, '''', #0, nil, [] bzw. der erste Wert einer Aufzaehlung der
//          Unit (InitValueFor) -, sonst Default(T) (Records, Typparameter,
//          Unbekanntes). Default() gibt es erst ab Delphi 2009 bzw. FPC
//          3.0 - eine Datei mit Spuren aelterer Compiler bekommt es nicht
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
//          ihre Definition (OwnTypeStatement). Die Meldung zeigt auf die
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
//                   der letzten Anweisung; fehlt ihr das ';', kommt es mit.
//                   Leerer Rumpf: wie FirstStatement.
// Die Routinengrenzen liest uRdxRoutineFixes.ReadRoutine (Kopf, lokale
// Abschnitte und Routinen, begin bzw. asm, passendes end), den Klassenkopf
// FindClassHeads/HeritageOf, die Deklaration FindMethodDecls/MethodDecl.
// Lokale Routinen zwischen Kopf und begin sperren deshalb NICHT mehr (das
// Konzept nannte sie, als nur MethodBodyOn fuer leere Rumpfe bestand):
// ReadRoutine ueberspringt sie, eingefuegt wird hinter dem begin der
// aeusseren Routine - vor jedem Aufruf einer lokalen.
//
// SPERREN (alle vier): kein begin-Rumpf (forward/external, asm-Rumpf), asm
// irgendwo im Rumpf (Register und Stapel sieht die Hilfe nicht), eine
// Compiler-Direktive zwischen Kopf und begin (Kopf oder Rumpf unter einem
// Zweig), zwei Koepfe auf der gemeldeten Zeile. SCA096/SCA097: 'class
// constructor/destructor', Kopf ohne Klasse, 'inherited' irgendwo im Text
// der Routine (inaktiver Zweig, Kommentar, lokale Routine - der Detektor
// sieht nur den aktiven AST), Klasse nicht (eindeutig) in der Unit,
// object-Typ, Record, class helper, eine Direktive in der Vorfahrenliste
// (der Vorfahr haengt an einem Zweig), eine geerbte Methode, die in der
// Unit 'abstract' ist, und unter {$mode objfpc}/{$mode fpc} ein Vorfahr
// ausserhalb der Unit (FPC lehnt 'inherited' auf eine abstrakte Methode
// ab, das ist dann nicht beweisbar). SCA096 (b) dazu ein Aufruf eines
// eigenen Konstruktors (Delegation, auch ohne 'Create' im Namen). SCA097
// dazu: letzte Anweisung Exit/raise/Halt/Abort/goto, Exit oder goto auf
// jeder Tiefe (inherited am Ende liefe dort nie) und eine Direktive
// zwischen letzter Anweisung und end. SCA121/SCA196: FPC-Modus ohne Result
// (fpc, tp, macpas, iso), '{$X-}'; SCA121 dazu eine Datei ohne
// implementation-Teil (xEdit-/JvInterpreter-Skripte kennen Default() nicht),
// eine Zuweisung an Result bzw. den Funktionsnamen oder Exit(Wert) im Rumpf
// (der Detektor sah sie nicht - meist in einem inaktiven Zweig), Default()
// in einer Datei mit Spuren alter Compiler und ein Rueckgabetyp, der kein
// einfacher Typbezeichner ist (FPC 'specialize'); SCA196 dazu 'absolute
// Result' und ein Typ, der weder String noch dynamisches Array, Interface
// oder Variant BEWIESEN ist.
//
// GRUNDSATZ wie in uRdxSimpleFixes: lieber keine Hilfe als eine falsche -
// der Planer prueft den Fund am aktuellen Text nach.

interface

uses
  uRdxBufferMath, uRdxCodeMap, uRdxRoutineFixes;

const
  // SCA096/SCA097: die Anweisungen (ohne ';'), zugleich Name im Menuetext.
  STMT_INHERITED_CREATE = 'inherited Create';
  STMT_INHERITED        = 'inherited';

type
  // Ergebnis der Planer: alle Ersetzungen (EIN Undo-Schritt), der Name fuer
  // den Menuetext und was der Aufrufer (uRdxFixTable) noch braucht.
  //   Name          SCA096: die Anweisung (STMT_*), SCA121: der Wert
  //                 ('0', 'False', 'Default(TRec)'), SCA196: die Anweisung
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

  // Die Form der Planer (uRdxFixTable: ResultFix).
  TRdxResultPlanner = function(AMap: TRdxCodeMap; ALine: Integer;
    const AMessage: string; out APlan: TRdxResultPlan;
    out AReason: string): Boolean;

  // Die Planer der Charge H5 und ihre Bausteine (s. Kopf): auf dem
  // Puffertext ueber die Code-Sicht, ohne ToolsAPI und Parser (laeuft auch
  // im FPC-Pruefstand).
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

    // SCA096: der Konstruktor mit Kopf auf ALine (Meldung 'Constructor has
    // no `inherited` call ...') - 'inherited Create;' bzw. 'inherited;'.
    class function ConstructorInherited(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxResultPlan;
      out AReason: string): Boolean; static;

    // SCA097: der Destruktor mit Kopf auf ALine (Meldung 'Destructor has
    // no `inherited` call ...') - 'inherited;' am Ende.
    class function DestructorInherited(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxResultPlan;
      out AReason: string): Boolean; static;

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

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxRtlTypes;      // IsRtlClassOrInterface (SCA196: Interface aus der RTL)

const
  SPAN_RESULT = 'result';
  KW_BEGIN    = 'begin';
  KW_END      = 'end';
  KW_CLASS    = 'class';
  KW_RESULT   = 'result';
  KW_OVERRIDE = 'override';
  KW_OVERLOAD = 'overload';
  KW_CONSTRUCTOR = 'constructor';
  KW_DESTRUCTOR  = 'destructor';
  KW_SELF     = 'self';
  WORD_INHERITED = 'inherited';
  // SCA096 (b): so beginnt der Name eines Konstruktors, an den der Rumpf
  // delegiert (DelegationReason).
  CREATE_PREFIX = 'create';
  // SCA096 (b): ein Aufruf, der abbricht (BlockedReason).
  RAISE_PREFIX = 'raise';
  KEY_CTOR    = 'Constructor has no `inherited` call';
  KEY_DTOR    = 'Destructor has no `inherited` call';
  KEY_FUNC    = 'Function ';
  KEY_NEVER   = ' never assigns Result';
  KEY_READS   = ' reads Result before';
  KEY_TYPE    = 'for return type ';
  KEY_TYPE_END = ', Result is';
  // Damit endet der Ablauf: ein inherited dahinter liefe nie (SCA097).
  DEAD_END_WORDS: array[0..4] of string = ('exit', 'raise', 'halt', 'abort',
    'goto');
  // SCA097: damit verlaesst der Ablauf den Destruktor vor dem Ende - auf
  // jeder Tiefe (JumpReason; Gegen-Review H5, Minor 2). raise/Halt/Abort
  // mitten im Rumpf sind Fehlerpfade; dort fehlt inherited ohnehin.
  JUMP_WORDS: array[0..1] of string = ('exit', 'goto');
  KW_ABSTRACT = 'abstract';
  // So weit folgen die Planer der Vorfahrenkette in der Unit (OwnConstructor,
  // AbstractReason) - eine Grenze gegen Zyklen in kaputtem Code.
  MAX_CHAIN = 16;
  // FPC-Modi, in denen 'inherited' auf eine abstrakte Methode nicht
  // uebersetzt ("Abstract methods cannot be called directly", FPC 3.2.2;
  // der Delphi-Modus laesst den Aufruf still weg - Gegen-Review H5, Minor 1).
  ABSTRACT_FATAL_MODES: array[0..1] of string = ('objfpc', 'fpc');
  // SCA096 (a): der erste Eintrag der Vorfahrenliste, klein und mit
  // Qualifizierung - TObject selbst ...
  ROOT_PARENTS: array[0..1] of string = ('tobject', 'system.tobject');
  // ... und Vorfahren OHNE eigenen Konstruktor: 'inherited Create' ruft dort
  // TObject.Create (leer) - gleiche Bedeutung wie bei TObject. Nachgesehen
  // (Charge H5c) in den Delphi-Quellen 23.0 und 37.0: System.Classes.pas
  // TPersistent (Zeile 449-460 in beiden: nur 'destructor Destroy;
  // override'), System.pas TInterfacedObject (23.0 Zeile 1058-1079, 37.0
  // Zeile 1056-1077: AfterConstruction, BeforeDestruction, NewInstance -
  // kein constructor) und TCustomAttribute (23.0 Zeile 749, 37.0 Zeile 747:
  // leerer Rumpf); FPC 3.2.2 ebenso (classesh.inc TPersistent, objpash.inc
  // TInterfacedObject - je nur 'destructor destroy; override'). Eine feste
  // Liste, NICHT generiert: ein neuer Eintrag braucht denselben Nachweis in
  // beiden Versionen. Gilt nur, wenn die Unit den Namen nicht selbst
  // deklariert (DeclaresTypeName).
  NO_CTOR_PARENTS: array[0..6] of string = ('tpersistent',
    'classes.tpersistent', 'system.classes.tpersistent', 'tinterfacedobject',
    'system.tinterfacedobject', 'tcustomattribute', 'system.tcustomattribute');
  // SCA096 (b): Woerter in Anweisungsstellung, die nie ein Konstruktor sind
  // - die Delegations-Suche (OwnConstructor) fragt sie nicht erst ab.
  STATEMENT_WORDS: array[0..12] of string = ('if', 'while', 'for', 'case',
    'with', 'repeat', 'try', 'begin', 'raise', 'inherited', 'exit', 'goto',
    'asm');
  // Damit endet ein Aufruf als ganze Anweisung ('Init;', 'Make(A) end').
  CALL_ENDS: array[0..6] of string = ('(', ';', 'end', 'else', 'until',
    'finally', 'except');
  // FPC-Modi ohne Result (SCA121/SCA196).
  NO_RESULT_MODES: array[0..4] of string = ('fpc', 'tp', 'macpas', 'iso',
    'extendedpascal');
  // Damit beginnt eine Datei, die der Compiler uebersetzt (SCA121).
  PROGRAM_WORDS: array[0..2] of string = ('program', 'library', 'package');
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
  // SCA121: Spuren von Compilern vor Delphi 2009 (OldCompilerTrace) - die
  // Includes der Kits, die ab Delphi 5/6 bauen (JEDI/JCL/JVCL, CnPack/
  // CnWizards, Indy) ...
  KIT_INCLUDES: array[0..5] of string = ('jedi.inc', 'jvcl.inc', 'jcl.inc',
    'cnpack.inc', 'cnwizards.inc', 'idcompilerdefines.inc');
  // ... und die Bedingungen, in denen ein Versionssymbol steht.
  CONDITION_WORDS: array[0..3] of string = ('ifdef', 'ifndef', 'if',
    'elseif');
  // Delphi 2009: VER200, CompilerVersion 20, COMPILER12, RTL200.
  D2009_VER = 200;
  D2009_COMPILER_VERSION = 20;
  D2009_COMPILER = 12;
  D2009_DELPHI_YEAR = 2009;
  DELPHI_LAST_NUMBER = 8;   // DELPHI1..DELPHI8, danach Jahreszahlen
  FPC_3_FULLVERSION = 30000;
  // ConditionTokens: Zeichen eines Worts bzw. eines Vergleichs.
  WORD_CHARS: TSysCharSet = ['A'..'Z', '0'..'9', '_', '.'];
  COMPARE_CHARS: TSysCharSet = ['<', '>', '='];
  OBJECT_KINDS: array[0..0] of string = ('object');
  RECORD_KINDS: array[0..0] of string = ('record');
  ARRAY_KINDS: array[0..1] of string = ('array', 'tarray');
  STMT_EMPTY_STRING = 'Result := ''''';
  STMT_NIL          = 'Result := nil';
  STMT_VARCLEAR     = 'VarClear(Result)';
  R_MOVED  = 'Zeile verschoben? Datei neu pruefen';
  R_BY_HAND = 'von Hand';
  // SCA196: als Konstante - ein Literal mit dem Wort im Exit-Argument
  // haelt der Detektor SCA196 selbst fuer ein Lesen von Result (Selbstscan
  // der Charge H5).
  R_NO_READ = 'kein Result auf der gemeldeten Zeile - ' + R_MOVED;

type
  // Die Klasse einer Methode (OwnerOf).
  //   Parent          erster Vorfahr wie im Text (letztes Glied); 'TObject'
  //                   ohne Liste
  //   DirectTObject   erbt direkt von TObject (SCA097: TObject.Destroy ist
  //                   leer)
  //   CreateOfTObject 'inherited Create' ruft TObject.Create: direkter
  //                   TObject-Erbe oder ein Vorfahr aus NO_CTOR_PARENTS
  //                   (SCA096 (a))
  TRdxOwner = record
    ClassTok        : TRdxToken;   // 'class' des Klassenkopfs
    Parent          : string;
    DirectTObject   : Boolean;
    CreateOfTObject : Boolean;
  end;

  // SCA096/SCA097: der Konstruktor bzw. Destruktor und seine Klasse
  // (MethodCtxReason). Bis Charge H5c hiessen die Felder R und O
  // (Gegen-Review H5, Minor 7).
  TRdxMethodCtx = record
    Routine : TRdxRoutine;
    Owner   : TRdxOwner;
  end;

  // SCA196: die Funktion um die Lese-Zeile und ihr Rueckgabetyp wie im
  // Quelltext (FuncCtxReason).
  TRdxFuncCtx = record
    Routine : TRdxRoutine;
    TypeTx  : string;
  end;

{ ---- Kleinkram ---- }

// AddEdit (uRdxBufferMath), AddToken, TokText, LastPart, FirstOnLine und
// DirectiveBetween (uRdxCodeMap) sowie HasDirective (uRdxRoutineFixes) sind
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

// Gibt es 'ALowName [<..>] = [packed] <Art>' mit einer Art aus AKinds in
// der Datei? Das Token der Art (Low = '' ohne) - der erste Treffer.
function TypeDeclKind(AMap: TRdxCodeMap; const ALowName: string;
  const AKinds: array of string): TRdxToken;
var
  T, P : TRdxToken;
begin
  Result := Default(TRdxToken);
  P := Default(TRdxToken);
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    if SameIdent(T.Low, ALowName) and IsKeywordAfter(T, P)
       and InList(KindAfterName(AMap, T).Low, AKinds) then
      Exit(KindAfterName(AMap, T));
    P := T;
    T := After(AMap, T);
  end;
end;

function DeclaredAs(AMap: TRdxCodeMap; const ALowName: string;
  const AKinds: array of string): Boolean;
begin
  Result := TypeDeclKind(AMap, ALowName, AKinds).Low <> '';
end;

// Die Definitionen des Typnamens ALowName in der Unit: je 'Name [<..>] =
// [type] [packed] X' in einem Typabschnitt (davor TYPE_DECL_PREV) das Token
// X ('class', 'array', '(', 'string' ...); leer, wenn die Unit den Namen
// nicht als Typ deklariert. Mehrere Treffer stehen unter $IFDEF-Zwillingen.
// SCA196 und SCA121 (Gegen-Review H5, Minor 8): deklariert die Unit einen
// Namen selbst ('TBytes = array[0..3] of Byte'), gilt nur ihre Definition.
function TypeDefsOf(AMap: TRdxCodeMap; const ALowName: string): TArray<TRdxToken>;
var
  T, P, K : TRdxToken;
begin
  Result := nil;
  P := Default(TRdxToken);
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    K := Default(TRdxToken);
    if SameIdent(T.Low, ALowName) and InList(P.Low, TYPE_DECL_PREV) then
      K := KindAfterName(AMap, T);
    // 'Name = type X': ein eigener Typ mit der Definition von X.
    if K.Low = 'type' then
      K := After(AMap, K);
    if K.Low <> '' then
      AddToken(Result, K);
    P := T;
    T := After(AMap, T);
  end;
end;

function DeclaresTypeName(AMap: TRdxCodeMap; const ALowName: string): Boolean;
begin
  Result := Length(TypeDefsOf(AMap, ALowName)) > 0;
end;

// Die Zeile der ersten Direktive '{$AWord ...}' der Datei, deren Text
// dahinter (klein, ohne Leerraum am Rand) in AArgs steht - bei leerem AArgs
// jede; 0 ohne. '{$mode objfpc}' -> AWord 'mode', AArgs ['objfpc'].
function DirectiveLine(AMap: TRdxCodeMap; const AWord: string;
  const AArgs: array of string): Integer;
var
  Li, Co : Integer;
  L      : string;
  Arg    : Boolean;
begin
  for Li := 1 to AMap.LineCount do
  begin
    L := AMap.Raw(Li);
    for Co := 1 to Length(L) do
      if CharInSet(L[Co], ['{', '(']) and OpensDirective(AMap, Li, Co)
         and (DirectiveWord(AMap, Li, Co, Arg) = AWord)
         and ((Length(AArgs) = 0)
              or InList(LowerCase(Trim(DirectiveArgs(AMap, Li, Co))), AArgs)) then
        Exit(Li);
  end;
  Result := 0;
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
    Result := TRdxRoutineFixes.ReadRoutine(AMap, K, R);
end;

// Die Koepfe auf ALine (Kopfwort-Token, links nach rechts).
function HeadsOnLine(AMap: TRdxCodeMap; ALine: Integer): TArray<TRdxToken>;
var
  T : TRdxToken;
begin
  Result := nil;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if IsRoutineHead(AMap, T) then
      AddToken(Result, T);
    T := After(AMap, T);
  end;
end;

// SCA196: die innerste Routine, deren begin..end die Zeile ALine umfasst -
// Koepfe von ALine aufwaerts, je Zeile von rechts (eine lokale Routine
// steht hinter dem Kopf ihrer aeusseren). Ein Kopf, dessen Grenzen nicht
// sicher zu lesen sind, beendet die Suche mit seinem Grund.
function EnclosingRoutine(AMap: TRdxCodeMap; ALine: Integer;
  out R: TRdxRoutine): string;
var
  Li, i : Integer;
  Heads : TArray<TRdxToken>;
begin
  for Li := ALine downto 1 do
  begin
    Heads := HeadsOnLine(AMap, Li);
    for i := High(Heads) downto 0 do
    begin
      Result := TRdxRoutineFixes.ReadRoutine(AMap, Heads[i], R);
      if Result <> '' then
        Exit(Format('Routine in Zeile %d: %s', [Li, Result]));
      if (R.Body.Low <> '') and (R.Body.Line <= ALine)
         and (ALine <= R.EndTok.Line) then
        Exit('');
    end;
  end;
  R := Default(TRdxRoutine);
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

{ ---- Klasse und Deklaration (SCA096/SCA097, SCA121) ---- }

// SCA096/SCA097: ein Methodenkopf 'TKlasse.Name' ohne 'class' davor? ''
// oder der Grund.
function MethodHeadReason(const R: TRdxRoutine): string;
begin
  Result := '';
  if R.Head.Low = KW_CLASS then
    Result := Format('class %s - ohne Vererbungskette, inherited gehoert '
      + 'nicht hinein', [R.Keyword.Low])
  else if Length(R.Parts) < 2 then
    Result := Format('%s ohne Klasse (kein TKlasse.Name) - %s',
      [R.Keyword.Low, R_BY_HAND]);
end;

// Steht 'inherited' irgendwo im Text der Routine - auch in einem
// Kommentar, einem inaktiven $IFDEF-Zweig oder einer lokalen Routine? Dann
// hat ihn jemand gesetzt, verschoben oder auskommentiert, und der Detektor
// sah ihn nur nicht im AST. '' oder der Grund.
function InheritedReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  Li : Integer;
begin
  Result := '';
  for Li := R.Head.Line to R.Last.Line do
    if HasIdentWord(LowerCase(AMap.Raw(Li)), WORD_INHERITED) then
      Exit(Format('"inherited" steht schon in Zeile %d (inaktiver Zweig, '
        + 'Kommentar oder lokale Routine) - %s', [Li, R_BY_HAND]));
end;

// Der erste Eintrag der Vorfahrenliste hinter AClass (Token 'class') wie im
// Text, Glieder mit '.', ohne Typargumente ('class(System.Classes.
// TPersistent, IFoo)' -> 'System.Classes.TPersistent'); '' ohne Liste.
// AOpen/AClose: die Klammern der Liste (Low = '' ohne). HeritageOf liefert
// nur letzte Glieder - hier entscheidet die Qualifizierung mit
// ('class(Other.IFoo)' ist kein Interface DIESER Unit; Gegen-Review H5,
// Minor 3).
function FirstHeritage(AMap: TRdxCodeMap; const AClass: TRdxToken;
  out AOpen, AClose: TRdxToken): string;
var
  T  : TRdxToken;
  SB : TStringBuilder;
begin
  Result := '';
  AClose := Default(TRdxToken);
  AOpen := After(AMap, AClass);
  while InList(AOpen.Low, CLASS_MODIFIERS) do
    AOpen := After(AMap, AOpen);
  if AOpen.Low <> '(' then
  begin
    AOpen := Default(TRdxToken);
    Exit;
  end;
  AClose := MatchClose(AMap, AOpen);
  if AClose.Low = '' then Exit;
  SB := TStringBuilder.Create;
  try
    T := After(AMap, AOpen);
    while not SameTok(T, AClose) and (T.Low <> ',') and (T.Low <> '') do
    begin
      if T.Low = '<' then
        T := MatchClose(AMap, T)
      else if T.IsWord or (T.Low = '.') then
        SB.Append(TokText(AMap, T));
      if T.Low <> '' then
        T := After(AMap, T);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Der erste Vorfahr der Klasse mit dem Kopf AClass in AOwner (Parent,
// DirectTObject, CreateOfTObject). '' oder der Grund: eine Direktive
// zwischen '=' und dem Ende der Vorfahrenliste -
// 'class({$IFDEF FPC}TPersistent{$ELSE}TObject{$ENDIF})' las die Code-Sicht
// als TObject, 'class{$IFDEF X}(TComponent){$ENDIF}' haengt den Vorfahren
// an einen Zweig (Gegen-Review H5, Minor 3).
function ParentReason(AMap: TRdxCodeMap; const AClass: TRdxToken;
  var AOwner: TRdxOwner): string;
var
  First, Low  : string;
  Open, Close : TRdxToken;
  Stop        : TRdxToken;
begin
  First := FirstHeritage(AMap, AClass, Open, Close);
  if (Open.Low <> '') and (Close.Low = '') then
    Exit(Format('Vorfahrenliste ohne ")" (Zeile %d) - %s',
      [AClass.Line, R_BY_HAND]));
  Stop := AClass;
  if Close.Low <> '' then
    Stop := Close;
  if DirectiveBetween(AMap, Before(AMap, AClass), Stop.Line, Stop.Col) then
    Exit(Format('Compiler-Direktive in der Vorfahrenliste (Zeile %d) - der '
      + 'Vorfahr haengt an einem Zweig; %s', [AClass.Line, R_BY_HAND]));
  Low := LowerCase(First);
  AOwner.Parent := 'TObject';
  if First <> '' then
    AOwner.Parent := LastPart(First);
  // 'class(IFoo)': der erste Eintrag ist ein Interface - Vorfahr TObject.
  // Nur ein unqualifiziertes Interface DIESER Unit beweist das; ein
  // fremdes 'IFoo' bzw. 'Other.IFoo' kann eine Klasse sein.
  AOwner.DirectTObject := (First = '') or InList(Low, ROOT_PARENTS)
    or ((Pos('.', First) = 0) and DeclaredAs(AMap, Low, INTERFACE_KINDS));
  AOwner.CreateOfTObject := AOwner.DirectTObject
    or (InList(Low, NO_CTOR_PARENTS)
        and not DeclaresTypeName(AMap, LowerCase(AOwner.Parent)));
  Result := '';
end;

// Die Klasse AClassPath in der Unit: genau ein Kopf mit Rumpf, kein class
// helper; ihr erster Vorfahr (ParentReason). '' oder der Grund.
function OwnerOf(AMap: TRdxCodeMap; const AClassPath: string;
  out AOwner: TRdxOwner): string;
var
  Heads : TArray<TRdxToken>;
  Low   : string;
begin
  AOwner := Default(TRdxOwner);
  Low := LowerCase(LastPart(AClassPath));
  Heads := TRdxRoutineFixes.FindClassHeads(AMap, AClassPath);
  if Length(Heads) = 0 then
  begin
    if DeclaredAs(AMap, Low, OBJECT_KINDS) then
      Exit('object-Typ (altes Objektmodell) - ' + R_BY_HAND);
    if DeclaredAs(AMap, Low, RECORD_KINDS) then
      Exit('Record - ohne Vererbung');
    Exit(Format('Klasse %s nicht in dieser Unit - der Vorfahr ist nicht '
      + 'beweisbar', [AClassPath]));
  end;
  if Length(Heads) > 1 then
    Exit(Format('%d Klassen namens %s in der Unit - mehrdeutig',
      [Length(Heads), LastPart(AClassPath)]));
  AOwner.ClassTok := Heads[0];
  if After(AMap, Heads[0]).Low = 'helper' then
    Exit('class helper - inherited meint dort die erweiterte Klasse');
  Result := ParentReason(AMap, Heads[0], AOwner);
end;

// Die Deklarationen der Methode R im Rumpf ihrer Klasse.
function DeclHeadsOf(AMap: TRdxCodeMap; const R: TRdxRoutine): TArray<TRdxToken>;
begin
  Result := TRdxRoutineFixes.FindMethodDecls(AMap, OwnerPathOf(R.Name),
    LastPart(R.Name));
end;

// Die EINE Deklaration der Methode R. '' oder der Grund.
function DeclOf(AMap: TRdxCodeMap; const R: TRdxRoutine;
  out D: TRdxRoutine): string;
var
  Heads : TArray<TRdxToken>;
begin
  D := Default(TRdxRoutine);
  Heads := DeclHeadsOf(AMap, R);
  if Length(Heads) = 0 then
    Exit(Format('keine Deklaration von %s im Rumpf der Klasse %s - %s',
      [LastPart(R.Name), OwnerPathOf(R.Name), R_MOVED]));
  if Length(Heads) > 1 then
    Exit(Format('%d Deklarationen von %s in Klassen dieses Namens - '
      + 'Overload?', [Length(Heads), LastPart(R.Name)]));
  Result := TRdxRoutineFixes.MethodDecl(AMap, Heads[0], D);
  if Result <> '' then
    Result := 'Deklaration: ' + Result;
end;

// SCA096 (b): die Deklaration traegt override (ohne overload). '' oder der
// Grund.
function CtorOverrideReason(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const AOwner: TRdxOwner): string;
var
  D : TRdxRoutine;
  W : string;
begin
  Result := DeclOf(AMap, R, D);
  if Result <> '' then Exit;
  if not HasDirective(D, [KW_OVERRIDE], W) then
    Exit(Format('Elternklasse %s und keine override-Deklaration - welcher '
      + 'Elternkonstruktor mit welchen Argumenten laufen soll, ist Entwurf; '
      + '%s', [AOwner.Parent, R_BY_HAND]));
  if HasDirective(D, [KW_OVERLOAD], W) then
    Exit('override mit overload - welcher geerbte Konstruktor gemeint ist, '
      + 'ist nicht sicher; ' + R_BY_HAND);
end;

// SCA096 (b): bricht die erste Anweisung den Konstruktor ab - 'raise',
// 'Assert(False..)', ein Aufruf 'Raise..' ('EFoo.RaiseUtf8(..)',
// 'RaiseLastOSError')? Ein blockierter Konstruktor (Korpus: 'Assert(False);
// // Call constructor CreateWithManager') erzeugt nie ein Objekt; der
// Detektor kennt nur 'raise'. Der Elternkonstruktor davor liefe vergeblich
// und mit seinen Nebenwirkungen. '' oder der Grund.
function BlockedReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  T       : TRdxToken;
  Blocked : Boolean;
begin
  Result := '';
  T := After(AMap, R.Body);
  Blocked := (T.Low = 'raise')
    or ((T.Low = 'assert') and (After(AMap, T).Low = '(')
        and (After(AMap, After(AMap, T)).Low = 'false'));
  while not Blocked and (T.Low <> '') and not SameTok(T, R.EndTok)
    and not InList(T.Low, [';', '(']) do
  begin
    Blocked := T.IsWord and (Copy(T.Low, 1, Length(RAISE_PREFIX)) = RAISE_PREFIX);
    if not Blocked then
      T := After(AMap, T);
  end;
  if Blocked then
    Result := Format('der Konstruktor bricht mit seiner ersten Anweisung ab '
      + '(Zeile %d, blockierter Konstruktor) - inherited davor liefe '
      + 'vergeblich; %s', [After(AMap, R.Body).Line, R_BY_HAND]);
end;

// SCA096 (b): ist ALowName ein Konstruktor der Klasse AClassPath oder eines
// ihrer Vorfahren in dieser Unit (FindMethodDecls je Glied der Kette,
// hoechstens MAX_CHAIN)? 'class constructor' zaehlt nicht - ihn ruft keine
// Anweisung.
function OwnConstructor(AMap: TRdxCodeMap; const AClassPath,
  ALowName: string): Boolean;
var
  Cls   : string;
  H     : TRdxToken;
  Heads : TArray<TRdxToken>;
  Names : TArray<string>;
  Step  : Integer;
begin
  Result := False;
  Cls := AClassPath;
  for Step := 1 to MAX_CHAIN do
  begin
    for H in TRdxRoutineFixes.FindMethodDecls(AMap, Cls, ALowName) do
      if H.Low = KW_CONSTRUCTOR then
        Exit(True);
    Heads := TRdxRoutineFixes.FindClassHeads(AMap, Cls);
    if Length(Heads) <> 1 then Exit;
    Names := TRdxRoutineFixes.HeritageOf(AMap, Heads[0]);
    if Length(Names) = 0 then Exit;
    Cls := Names[0];
  end;
end;

// SCA096 (b): koennte das Wort T in Anweisungsstellung ein Aufruf eines
// eigenen Konstruktors sein - ein ganzer Aufruf ('Init;', 'OpenOptions(..)',
// CALL_ENDS dahinter), kein Schluesselwort einer Anweisung? Nur dann fragt
// DelegationReason die Deklarationen ab (sie durchlaufen die ganze Datei).
function CallCandidate(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
begin
  Result := T.IsWord and not InList(T.Low, STATEMENT_WORDS)
    and InList(After(AMap, T).Low, CALL_ENDS);
end;

// SCA096 (b): ruft der Rumpf als Anweisung einen Konstruktor der Klasse
// selbst - 'CreateNew(AOwner);', 'Self.CreateEx(..)', 'OpenOptions(..)'?
// Das ist eine Delegation, die der Detektor nur fuer 'Create(' kennt; der
// gerufene Konstruktor initialisiert die Elternklasse schon
// (TCustomForm.CreateNew laedt danach keine .dfm - 'inherited;' davor
// taete es und scheiterte). Erkannt am Namen 'Create..' in
// Anweisungsstellung - eine Routine wie 'CreateDir(..)' sperrt mit (lieber
// keine Hilfe) - oder an einer constructor-Deklaration des Namens in der
// Klasse bzw. ihren Vorfahren der Unit (OwnConstructor; Gegen-Review H5,
// Major 1: mORMot THttpClientSocket.OpenFrom ruft OpenOptions, der selbst
// Create und OpenBind ruft - 'inherited;' davor oeffnete zuerst ueber
// TCrtSocket.OpenFrom eine zweite Verbindung). '' oder der Grund.
// SCA096 (b): der Grund fuer eine Delegation am Wort T in Anweisungsstellung
// (s. DelegationReason), '' ohne. ASeen: die Namen, deren Deklarationen
// schon abgefragt sind.
function DelegationAt(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const T: TRdxToken; var ASeen: TArray<string>): string;
begin
  Result := '';
  if Copy(T.Low, 1, Length(CREATE_PREFIX)) = CREATE_PREFIX then
    Exit(Format('Aufruf %s in Zeile %d - vielleicht ein anderer '
      + 'Konstruktor der Klasse (Delegation), der die Elternklasse schon '
      + 'initialisiert; inherited davor liefe doppelt; %s',
      [TokText(AMap, T), T.Line, R_BY_HAND]));
  if not CallCandidate(AMap, T) or InList(T.Low, ASeen) then Exit;
  if OwnConstructor(AMap, OwnerPathOf(R.Name), T.Low) then
    Exit(Format('Aufruf %s in Zeile %d - ein Konstruktor der Klasse '
      + '(Delegation), der die Elternklasse schon initialisiert; inherited '
      + 'davor liefe doppelt; %s', [TokText(AMap, T), T.Line, R_BY_HAND]));
  SetLength(ASeen, Length(ASeen) + 1);
  ASeen[High(ASeen)] := T.Low;
end;

function DelegationReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  T, P : TRdxToken;
  Seen : TArray<string>;
begin
  Result := '';
  Seen := nil;
  P := R.Body;
  T := After(AMap, R.Body);
  while (T.Low <> '') and not SameTok(T, R.EndTok) do
  begin
    if T.IsWord and (InList(P.Low, STATEMENT_PREV)
                     or ((P.Low = '.') and (Before(AMap, P).Low = KW_SELF))) then
      Result := DelegationAt(AMap, R, T, Seen);
    if Result <> '' then Exit;
    P := T;
    T := After(AMap, T);
  end;
end;

// SCA097: die Deklaration traegt override. '' oder der Grund.
function DtorOverrideReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  D : TRdxRoutine;
  W : string;
begin
  Result := DeclOf(AMap, R, D);
  if (Result = '') and not HasDirective(D, [KW_OVERRIDE], W) then
    Result := 'die Deklaration traegt kein override - dann verdeckt der '
      + 'Destruktor die virtuelle Methode (SCA149); ' + R_BY_HAND;
end;

// SCA096 (b), SCA097: die Deklarationen von AMethod in der Klasse ACls der
// Unit (ohne 'class constructor/destructor'). AFound, wenn es welche gibt;
// '' oder der Grund, wenn eine 'abstract' traegt oder nicht zu lesen ist.
function AbstractDeclReason(AMap: TRdxCodeMap; const ACls, AMethod: string;
  out AFound: Boolean): string;
var
  H : TRdxToken;
  D : TRdxRoutine;
  W : string;
begin
  Result := '';
  AFound := False;
  for H in TRdxRoutineFixes.FindMethodDecls(AMap, ACls, AMethod) do
  begin
    if H.Low = KW_CLASS then Continue;
    AFound := True;
    if TRdxRoutineFixes.MethodDecl(AMap, H, D) <> '' then
      Exit(Format('die Deklaration von %s.%s in Zeile %d ist nicht zu lesen '
        + '- ob sie abstrakt ist, bleibt offen; %s',
        [ACls, AMethod, H.Line, R_BY_HAND]));
    if HasDirective(D, [KW_ABSTRACT], W) then
      Exit(Format('%s.%s ist abstrakt (Zeile %d) - inherited ruft dort nichts '
        + 'bzw. uebersetzt unter FPC objfpc nicht; %s',
        [ACls, AMethod, H.Line, R_BY_HAND]));
  end;
end;

// SCA096 (b), SCA097: ist die Methode, die 'inherited;' ruft, abstrakt? Die
// Kette der Vorfahren in der Unit hinauf bis zur ersten Klasse, die die
// Methode deklariert: abstrakt -> sperren (FPC objfpc: "Abstract methods
// cannot be called directly", Delphi-Modus laesst den Aufruf still weg -
// beides keine Hilfe; Gegen-Review H5, Minor 1). Endet die Kette vorher
// ausserhalb der Unit, ist das unter {$mode objfpc}/{$mode fpc} nicht
// beweisbar -> sperren; in Delphi bleibt es beim Angebot. TObject (Create,
// Destroy) ist nie abstrakt. '' oder der Grund.
function AbstractReason(AMap: TRdxCodeMap; const ACtx: TRdxMethodCtx): string;
var
  Cls, Method : string;
  Heads       : TArray<TRdxToken>;
  O           : TRdxOwner;
  Found       : Boolean;
  Step, Mode  : Integer;
begin
  Result := '';
  O := ACtx.Owner;
  Cls := O.Parent;
  Method := LastPart(ACtx.Routine.Name);
  for Step := 1 to MAX_CHAIN do
  begin
    if O.DirectTObject then Exit;
    Cls := O.Parent;
    Heads := TRdxRoutineFixes.FindClassHeads(AMap, Cls);
    if Length(Heads) <> 1 then Break;
    Result := AbstractDeclReason(AMap, Cls, Method, Found);
    if (Result <> '') or Found then Exit;
    O := Default(TRdxOwner);
    if ParentReason(AMap, Heads[0], O) <> '' then Break;
  end;
  Mode := DirectiveLine(AMap, 'mode', ABSTRACT_FATAL_MODES);
  if Mode > 0 then
    Result := Format('{$mode objfpc/fpc} in Zeile %d, und die geerbte Methode '
      + 'ist ab %s nicht in dieser Unit zu sehen - ist sie abstrakt, '
      + 'uebersetzt FPC das inherited nicht; nicht beweisbar, %s',
      [Mode, Cls, R_BY_HAND]);
end;

// SCA097: das erste Token der letzten Anweisung auf oberster Ebene des
// Rumpfs (hinter dem letzten ';' der Tiefe 0); Low = '' im leeren Rumpf.
function LastStatementStart(AMap: TRdxCodeMap; const R: TRdxRoutine): TRdxToken;
var
  T, P, N : TRdxToken;
  Depth   : Integer;
begin
  Result := Default(TRdxToken);
  Depth := 0;
  P := R.Body;
  T := After(AMap, R.Body);
  if not SameTok(T, R.EndTok) then
    Result := T;
  while (T.Low <> '') and not SameTok(T, R.EndTok) do
  begin
    if IsKeywordAfter(T, P) and IsEndOpener(T.Low) then
      Inc(Depth)
    else if IsKeywordAfter(T, P) and (T.Low = KW_END) then
      Dec(Depth)
    else if (Depth = 0) and (T.Low = ';') then
    begin
      N := After(AMap, T);
      if not SameTok(N, R.EndTok) then
        Result := N;
    end;
    P := T;
    T := After(AMap, T);
  end;
end;

// SCA097: steht Exit oder goto irgendwo im Rumpf - auf jeder Tiefe, auch
// in einer anonymen Methode (lieber keine Hilfe)? Lokale Routinen stehen
// vor dem begin und zaehlen nicht. Dann verlaesst der Ablauf den
// Destruktor dort vor dem Ende, und ein inherited am Ende liefe auf diesem
// Weg nie (Gegen-Review H5, Minor 2: Abbrevia TMultiTree.Destroy endet mit
// 'Curr.Free; exit;' in einer Schleife). '' oder der Grund.
function JumpReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  T, P : TRdxToken;
begin
  Result := '';
  P := R.Body;
  T := After(AMap, R.Body);
  while (T.Low <> '') and not SameTok(T, R.EndTok) do
  begin
    if InList(T.Low, JUMP_WORDS) and IsKeywordAfter(T, P) then
      Exit(Format('%s in Zeile %d - der Ablauf verlaesst den Destruktor dort '
        + 'vor dem Ende, ein inherited am Ende liefe auf diesem Weg nie; %s',
        [TokText(AMap, T), T.Line, R_BY_HAND]));
    P := T;
    T := After(AMap, T);
  end;
end;

// SCA097: endet der Rumpf mit Exit, raise, Halt, Abort oder goto? Dann
// liefe ein inherited dahinter nie. Dazu Exit/goto auf jeder Tiefe
// (JumpReason). '' oder der Grund.
function DeadEndReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  S : TRdxToken;
begin
  S := LastStatementStart(AMap, R);
  if InList(S.Low, DEAD_END_WORDS) then
    Exit(Format('die letzte Anweisung ist %s (Zeile %d) - inherited '
      + 'dahinter liefe nie; %s', [TokText(AMap, S), S.Line, R_BY_HAND]));
  Result := JumpReason(AMap, R);
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

// SCA121: Default() ist ein Compiler-Intrinsic (Delphi 2009, FPC 3.0) -
// Skript-Units ('unit X;' ohne implementation-Teil: xEdit-Skripte,
// JvInterpreter-Beispiele) und Include-Dateien uebersetzt kein Compiler,
// ihre Interpreter kennen es nicht. '' oder der Grund.
function ScriptReason(AMap: TRdxCodeMap): string;
var
  T, P : TRdxToken;
begin
  T := NextToken(AMap, 1, 1);
  if InList(T.Low, PROGRAM_WORDS) then
    Exit('');
  if T.Low <> 'unit' then
    Exit('die Datei beginnt nicht mit unit/program/library (Include oder '
      + 'Skript?) - Default() kennt nur der Compiler');
  P := T;
  T := After(AMap, T);
  while T.Low <> '' do
  begin
    if (T.Low = 'implementation') and IsKeywordAfter(T, P) then
      Exit('');
    P := T;
    T := After(AMap, T);
  end;
  Result := 'unit ohne implementation-Teil (Skript?) - Default() kennt nur '
    + 'der Compiler';
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
function ResultTypeOf(AMap: TRdxCodeMap; const R: TRdxRoutine;
  out AType: string): string;
var
  D : TRdxRoutine;
begin
  Result := TypeAfterHead(AMap, R, AType);
  if (Result <> '') or (AType <> '') then Exit;
  if Length(R.Parts) < 2 then
    Exit('Kopf ohne Rueckgabetyp, keine Methode - die Deklaration liest die '
      + 'Hilfe nicht; ' + R_BY_HAND);
  Result := DeclOf(AMap, R, D);
  if Result = '' then
    Result := TypeAfterHead(AMap, D, AType);
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
// 'Exit(Wert)'?
function WritesResult(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  const ALowName: string): Boolean;
var
  N : TRdxToken;
begin
  Result := False;
  if not IsKeywordAfter(T, APrev) then Exit;
  if (T.Low = KW_RESULT) or SameIdent(T.Low, ALowName) then
    Exit(AssignsAt(AMap, T));
  N := After(AMap, T);
  Result := (T.Low = 'exit') and (N.Low = '(') and (After(AMap, N).Low <> ')');
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

// SCA121: steht AName in den Koepfen und Deklarationsteilen von R (zwischen
// Kopf und begin: Parameter, lokale Variablen, lokale Routinen)? Dann
// verdeckt er dort einen gleichnamigen Wert einer Aufzaehlung.
function NamedInHead(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const ALowName: string): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  T := R.Head;
  while (T.Low <> '') and not SameTok(T, R.Body) do
  begin
    if SameIdent(T.Low, ALowName) then
      Exit(True);
    T := After(AMap, T);
  end;
end;

// SCA121: der erste Wert der Aufzaehlung ab ihrem '(' K - wenn sie schlicht
// ist (nur Namen mit ',', kein '=' fuer eigene Ordinalwerte), die Datei kein
// {$SCOPEDENUMS} kennt (dort braeuchte er den Typnamen davor, den Delphi
// vor 2009 nicht kennt) und Kopf und Deklarationsteil von R den Namen
// nicht verdecken; sonst ''.
function EnumFirst(AMap: TRdxCodeMap; const K: TRdxToken;
  const R: TRdxRoutine): string;
var
  First, T, C : TRdxToken;
begin
  Result := '';
  First := After(AMap, K);
  C := MatchClose(AMap, K);
  if not First.IsWord or (C.Low = '') then Exit;
  T := First;
  while not SameTok(T, C) do
  begin
    if not (T.IsWord or (T.Low = ',')) then Exit;
    T := After(AMap, T);
  end;
  if (DirectiveLine(AMap, 'scopedenums', []) = 0)
     and not NamedInHead(AMap, R, First.Low) then
    Result := TokText(AMap, First);
end;

// SCA121: der Anfangswert nach der Definition K ('=' davor, TypeDefsOf) -
// Klasse, Metaklasse, Interface, Zeiger, Routinentyp und dynamisches Array:
// nil; Menge: []; String-Alias: ''; schlichte Aufzaehlung: ihr erster Wert
// (EnumFirst); sonst '' (dann Default(T)).
function DefValue(AMap: TRdxCodeMap; const K: TRdxToken;
  const R: TRdxRoutine): string;
var
  N : TRdxToken;
begin
  Result := '';
  N := After(AMap, K);
  if InList(K.Low, NIL_KINDS) or ((K.Low = 'array') and (N.Low = 'of'))
     or ((K.Low = 'tarray') and (N.Low = '<')) then
    Result := VALUE_NIL
  else if (K.Low = 'set') and (N.Low = 'of') then
    Result := VALUE_EMPTY_SET
  else if InList(K.Low, STRING_TYPES) then
    Result := VALUE_EMPTY
  else if K.Low = '(' then
    Result := EnumFirst(AMap, K, R);
end;

// SCA121: der Anfangswert fuer den Rueckgabetyp AType (wie im Kopf) der
// Funktion R in AValue: deklariert die Unit den Namen selbst, nach ihrer
// Definition (DefValue; mehrere Definitionen unter $IFDEF muessen denselben
// Wert ergeben), sonst nach der RTL (RtlTypeValue); wo kein Literal passt -
// Records, Typparameter, Unbekanntes -, 'Default(AType)'. '' oder der Grund.
function InitValueFor(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const AType: string; out AValue: string): string;
var
  Low, Base, V : string;
  K            : TRdxToken;
  Defs         : TArray<TRdxToken>;
begin
  Result := '';
  Low := LowerCase(StringReplace(AType, ' ', '', [rfReplaceAll]));
  if Copy(Low, 1, 7) = 'system.' then
    Delete(Low, 1, 7);
  Base := Low;
  if Pos('<', Base) > 0 then
    Base := Copy(Base, 1, Pos('<', Base) - 1);
  Defs := nil;
  if Pos('.', Base) = 0 then
    Defs := TypeDefsOf(AMap, Base);
  AValue := RtlTypeValue(Low);
  if Length(Defs) > 0 then
    AValue := DefValue(AMap, Defs[0], R);
  for K in Defs do
  begin
    V := DefValue(AMap, K, R);
    if V <> AValue then
      Exit(Format('%s ist in dieser Unit mehrfach verschieden definiert '
        + '($IFDEF-Zweige?) - %s', [AType, R_BY_HAND]));
  end;
  if AValue = '' then
    AValue := 'Default(' + AType + ')';
end;

// Die Zahl direkt hinter APrefix am Anfang von AUpper ('DELPHI2007_UP',
// 'DELPHI' -> 2007); -1 ohne Ziffer dahinter.
function NumberAfter(const AUpper, APrefix: string): Integer;
var
  i : Integer;
begin
  Result := -1;
  if Copy(AUpper, 1, Length(APrefix)) <> APrefix then Exit;
  i := Length(APrefix) + 1;
  while (i <= Length(AUpper)) and CharInSet(AUpper[i], ['0'..'9']) do
    Inc(i);
  if i > Length(APrefix) + 1 then
    Result := StrToIntDef(Copy(AUpper, Length(APrefix) + 1,
      i - Length(APrefix) - 1), -1);
end;

// Ein Versionssymbol eines Compilers vor Delphi 2009 (bzw. FPC 3.0):
// VERnnn unter VER200 (FPC: VER2_6 ...), DELPHI1..DELPHI8 und
// DELPHI2005..DELPHI2009 (auch mit Zusatz: DELPHI2007_UP), COMPILERn bis
// COMPILER12, BCBn bis BCB12, RTLnnn bis RTL200 - wer danach fragt, baut
// auch mit dem aelteren Compiler.
function OldVersionWord(const AUpper: string): Boolean;
var
  N : Integer;
begin
  N := NumberAfter(AUpper, 'DELPHI');
  Result := ((N >= 1) and (N <= DELPHI_LAST_NUMBER))
    or ((N >= 2005) and (N <= D2009_DELPHI_YEAR));
  N := NumberAfter(AUpper, 'VER');
  Result := Result or ((N >= 0) and (N < D2009_VER));
  N := NumberAfter(AUpper, 'COMPILER');
  Result := Result or ((N >= 0) and (N <= D2009_COMPILER));
  N := NumberAfter(AUpper, 'BCB');
  Result := Result or ((N >= 0) and (N <= D2009_COMPILER));
  N := NumberAfter(AUpper, 'RTL');
  Result := Result or ((N >= 0) and (N <= D2009_VER));
end;

// Die Woerter und Vergleichszeichen eines Bedingungstexts, gross
// ('CompilerVersion >= 20.0' -> COMPILERVERSION, >=, 20.0).
function ConditionTokens(const AArgs: string): TArray<string>;
var
  U       : string;
  i, j, N : Integer;
  Chars   : TSysCharSet;
begin
  U := UpperCase(AArgs);
  SetLength(Result, Length(U));
  N := 0;
  i := 1;
  while i <= Length(U) do
  begin
    Chars := WORD_CHARS;
    if CharInSet(U[i], COMPARE_CHARS) then
      Chars := COMPARE_CHARS;
    j := i;
    while (j <= Length(U)) and CharInSet(U[j], Chars) do
      Inc(j);
    if j > i then
    begin
      Result[N] := Copy(U, i, j - i);
      Inc(N);
      i := j;
    end
    else
      Inc(i);
  end;
  SetLength(Result, N);
end;

// Die Zahl vor dem ersten '.' von AWord ('20.0' -> 20); -1 ohne Zahl.
function LeadingNumber(const AWord: string): Integer;
var
  P : Integer;
begin
  P := Pos('.', AWord + '.');
  Result := StrToIntDef(Copy(AWord, 1, P - 1), -1);
end;

// Ein Vergleich 'CompilerVersion|RTLVersion <op> n' mit n bis 20 bzw.
// 'FPC_FULLVERSION <op> n' mit n unter 30000 an AToks[i]?
function OldComparisonAt(const AToks: TArray<string>; i: Integer): Boolean;
var
  N : Integer;
begin
  Result := False;
  if (i + 2 > High(AToks)) or not CharInSet(AToks[i + 1][1], ['<', '>', '='])
  then
    Exit;
  N := LeadingNumber(AToks[i + 2]);
  if (AToks[i] = 'COMPILERVERSION') or (AToks[i] = 'RTLVERSION') then
    Result := (N >= 0) and (N <= D2009_COMPILER_VERSION)
  else if AToks[i] = 'FPC_FULLVERSION' then
    Result := (N >= 0) and (N < FPC_3_FULLVERSION);
end;

// Eine Spur alter Compiler im Bedingungstext AArgs ('{$IFDEF DELPHI2007_UP}',
// '{$IF CompilerVersion < 20}') - das Symbol bzw. der Vergleich; '' ohne.
function OldSymbolIn(const AArgs: string): string;
var
  Toks : TArray<string>;
  i    : Integer;
begin
  Result := '';
  Toks := ConditionTokens(AArgs);
  for i := 0 to High(Toks) do
    if OldVersionWord(Toks[i]) then
      Exit(Toks[i])
    else if OldComparisonAt(Toks, i) then
      Exit(Toks[i] + ' ' + Toks[i + 1] + ' ' + Toks[i + 2]);
end;

// Die Spur alter Compiler in der Direktive an (ALine, ACol): ein
// Kit-Include (KIT_INCLUDES, klein ohne Pfad) oder ein Versionssymbol in
// einer Bedingung; '' ohne.
function OldTraceAt(AMap: TRdxCodeMap; ALine, ACol: Integer): string;
var
  W   : string;
  Arg : Boolean;
begin
  Result := '';
  W := DirectiveWord(AMap, ALine, ACol, Arg);
  if InList(W, INCLUDE_WORDS) then
  begin
    Result := LowerCase(IncludeFileAt(AMap, ALine, ACol));
    Result := Copy(Result, LastDelimiter('\/', Result) + 1, MaxInt);
    if not InList(Result, KIT_INCLUDES) then
      Result := '';
  end
  else if InList(W, CONDITION_WORDS) then
    Result := OldSymbolIn(DirectiveArgs(AMap, ALine, ACol));
end;

// SCA121: traegt die Datei Spuren von Compilern vor Delphi 2009 bzw. FPC
// 3.0, die Default() nicht kennen (OldTraceAt)? Gegen-Review H5, Minor 4:
// CnWizards baut ab Delphi 5 (CnWizUtils), JVCL setzt Result teils nur ab
// DELPHI2007_UP. '' oder der Grund.
function OldCompilerReason(AMap: TRdxCodeMap): string;
var
  Li, Co : Integer;
  L, S   : string;
begin
  Result := '';
  for Li := 1 to AMap.LineCount do
  begin
    L := AMap.Raw(Li);
    for Co := 1 to Length(L) do
      if CharInSet(L[Co], ['{', '(']) and OpensDirective(AMap, Li, Co) then
      begin
        S := OldTraceAt(AMap, Li, Co);
        if S <> '' then
          Exit(Format('Default() gibt es erst ab Delphi 2009 bzw. FPC 3.0 - '
            + 'die Datei traegt Spuren aelterer Compiler (%s, Zeile %d); %s',
            [S, Li, R_BY_HAND]));
      end;
  end;
end;

// SCA121: der Wert fuer 'Result := <Wert>;' zur Funktion R in AValue
// (InitValueFor); Default(T) nur mit einfachem Typbezeichner
// (TypeTextReason) und ohne Spuren alter Compiler (OldCompilerReason). ''
// oder der Grund.
function ValueReason(AMap: TRdxCodeMap; const R: TRdxRoutine;
  out AValue: string): string;
var
  TypeTx : string;
begin
  AValue := '';
  TypeTx := '';
  Result := ResultTypeOf(AMap, R, TypeTx);
  if Result = '' then
    Result := InitValueFor(AMap, R, TypeTx, AValue);
  if (Result <> '') or (AValue <> 'Default(' + TypeTx + ')') then Exit;
  Result := TypeTextReason(TypeTx);
  if Result = '' then
    Result := OldCompilerReason(AMap);
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
function DynArrayProven(AMap: TRdxCodeMap; const ALow: string): Boolean;
var
  K : TRdxToken;
begin
  if InList(ALow, RTL_DYN_ARRAYS) then
    Exit(True);
  K := TypeDeclKind(AMap, ALow, ARRAY_KINDS);
  Result := ((K.Low = 'array') and (After(AMap, K).Low = 'of'))
    or ((K.Low = 'tarray') and (After(AMap, K).Low = '<'));
end;

// SCA196: ein Interface? 'I' + Grossbuchstabe und als Interface in der
// Unit deklariert bzw. ein Typ der Delphi-Quellen (uRdxRtlTypes). Dort
// stehen Klassen UND Interfaces, und die I-Schreibweise trennt sie NICHT
// (Winapi.D3D10: ID3D10EffectPass = class - Gegen-Review H5, Minor 8); fuer
// 'Result := nil' ist das gleich, beide nehmen nil.
function InterfaceProven(AMap: TRdxCodeMap; const AType: string): Boolean;
var
  Name : string;
begin
  Name := LastPart(AType);
  if Pos('<', Name) > 0 then
    Name := Copy(Name, 1, Pos('<', Name) - 1);
  Result := (Length(Name) >= 2) and (Name[1] = 'I')
    and CharInSet(Name[2], ['A'..'Z'])
    and (DeclaredAs(AMap, LowerCase(Name), INTERFACE_KINDS)
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
// Definitionen ($IFDEF) muessen dieselbe Anweisung ergeben. '' oder der
// Grund; AStmt leer, wenn die Unit den Namen nicht deklariert.
function OwnTypeStatement(AMap: TRdxCodeMap; const ALowBase, AType: string;
  out AStmt: string): string;
var
  K     : TRdxToken;
  S     : string;
  First : Boolean;
begin
  Result := '';
  AStmt := '';
  First := True;
  for K in TypeDefsOf(AMap, ALowBase) do
  begin
    S := DefStatement(AMap, K);
    if S = '' then
      Exit(Format('%s ist in dieser Unit als "%s ..." definiert (Zeile %d) - '
        + 'kein dynamisches Array, Interface, String oder Variant; %s',
        [AType, TokText(AMap, K), K.Line, R_BY_HAND]));
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
function StatementFor(AMap: TRdxCodeMap; const AType: string;
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
    Result := OwnTypeStatement(AMap, Base, AType, AStmt);
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
  else if DynArrayProven(AMap, Low) or InterfaceProven(AMap, AType) then
    AStmt := STMT_NIL
  else
    Result := Format('Rueckgabetyp %s ist nicht als String, dynamisches '
      + 'Array, Interface oder Variant bewiesen - %s', [AType, R_BY_HAND]);
end;

{ ---- Gemeinsame Nachweise ---- }

// SCA096/SCA097: was beide Planer nachweisen - die Meldung, genau ein Kopf
// AWord ('constructor' bzw. 'destructor') auf ALine, eine Methode mit
// Klasse ohne 'class' davor, ein begin-Rumpf ohne asm und ohne Direktive
// davor, kein 'inherited' im Text der Routine und die Klasse in der Unit.
// '' oder der Grund.
function MethodCtxReason(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage, AWord: string; out ACtx: TRdxMethodCtx): string;
var
  Key, What : string;
begin
  ACtx := Default(TRdxMethodCtx);
  Key := KEY_DTOR;
  What := 'eines Destruktors';
  if AWord = KW_CONSTRUCTOR then
  begin
    Key := KEY_CTOR;
    What := 'eines Konstruktors';
  end;
  if Pos(Key, AMessage) = 0 then
    Exit(Format('Meldung unbekannt - kein "%s"', [Key]));
  Result := RoutineOnLine(AMap, ALine, AWord, What, ACtx.Routine);
  if Result = '' then
    Result := MethodHeadReason(ACtx.Routine);
  if Result = '' then
    Result := BodyReason(AMap, ACtx.Routine);
  if Result = '' then
    Result := InheritedReason(AMap, ACtx.Routine);
  if Result = '' then
    Result := OwnerOf(AMap, OwnerPathOf(ACtx.Routine.Name), ACtx.Owner);
end;

// SCA096: die Variante nach dem Vorfahren - (a) 'inherited Create' ruft
// TObject.Create (direkter TObject-Erbe oder NO_CTOR_PARENTS): 'inherited
// Create' (die Deklaration muss es geben, sonst gehoert der Kopf nicht zu
// dieser Klasse; ein overload stoert nicht - 'inherited Create' meint immer
// TObject.Create); (b) override: 'inherited', gekennzeichnet, nicht
// abstrakt geerbt, ohne Delegation und nicht blockiert. Setzt APlan.Name
// bzw. APlan.Changes. '' oder der Grund.
function CtorVariantReason(AMap: TRdxCodeMap; const ACtx: TRdxMethodCtx;
  var APlan: TRdxResultPlan): string;
begin
  if ACtx.Owner.CreateOfTObject then
  begin
    APlan.Name := STMT_INHERITED_CREATE;
    if Length(DeclHeadsOf(AMap, ACtx.Routine)) = 0 then
      Exit(Format('keine Deklaration von %s im Rumpf der Klasse %s - %s',
        [LastPart(ACtx.Routine.Name), OwnerPathOf(ACtx.Routine.Name), R_MOVED]));
    Exit('');
  end;
  Result := CtorOverrideReason(AMap, ACtx.Routine, ACtx.Owner);
  APlan.Changes := Result = '';
  if Result = '' then
    Result := AbstractReason(AMap, ACtx);
  if Result = '' then
    Result := DelegationReason(AMap, ACtx.Routine);
  if Result = '' then
    Result := BlockedReason(AMap, ACtx.Routine);
end;

// SCA196: die Funktion um die Lese-Zeile ALine - auf der Zeile steht
// Result, die innerste Routine heisst AName, hat einen begin-Rumpf ohne
// asm, Result gibt es (Modus), ihr Rueckgabetyp ist AMsgType, kein
// 'absolute Result'. '' oder der Grund; ACtx.TypeTx wie im Quelltext.
function FuncCtxReason(AMap: TRdxCodeMap; ALine: Integer;
  const AName, AMsgType: string; out ACtx: TRdxFuncCtx): string;
begin
  ACtx := Default(TRdxFuncCtx);
  if not ReadsResultOn(AMap, ALine) then
    Exit(R_NO_READ);
  Result := EnclosingRoutine(AMap, ALine, ACtx.Routine);
  if Result = '' then
    Result := NameReason(ACtx.Routine, AName);
  if Result = '' then
    Result := BodyReason(AMap, ACtx.Routine);
  if Result = '' then
    Result := ResultModeReason(AMap);
  if Result = '' then
    Result := ResultTypeOf(AMap, ACtx.Routine, ACtx.TypeTx);
  if (Result = '') and not SameTypeText(ACtx.TypeTx, AMsgType) then
    Result := Format('der Kopf nennt %s, die Meldung %s - %s',
      [ACtx.TypeTx, AMsgType, R_MOVED]);
  if Result = '' then
    Result := AbsoluteReason(AMap, ACtx.Routine);
end;

{ ---- Gemeinsamer Abschluss ---- }

// AReason = '': die Ersetzung in den Plan; sonst Ersetzungen leeren.
function Finish(var APlan: TRdxResultPlan; const AEdits: TArray<TRdxEdit>;
  const AReason: string): Boolean;
begin
  Result := AReason = '';
  if Result then
    APlan.Edits := AEdits
  else
    APlan.Edits := nil;
end;

// Der Rumpf von R mit AStmt als erster Anweisung (fuer Finish).
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
  Semi := '';
  if Last.Low <> ';' then
    Semi := ';';
  if OwnLineAt(AMap, En) then
  begin
    if Semi <> '' then
      AddEdit(AEdits, TokenEdit(AMap, Last, TokText(AMap, Last) + Semi));
    E.Span := TRefactorSpan.Make(SPAN_RESULT, En.Line, 1, En.Line, En.EndCol);
    E.Expected := Copy(AMap.Raw(En.Line), 1, En.EndCol - 1);
    E.NewText := BodyIndent(AMap, R) + AStmt + #10 + E.Expected;
    AddEdit(AEdits, E);
  end
  else
    AddEdit(AEdits, TokenEdit(AMap, Last,
      TokText(AMap, Last) + Semi + ' ' + AStmt));
  Result := '';
end;

class function TRdxResultFixes.ConstructorInherited(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxResultPlan;
  out AReason: string): Boolean;
var
  Ctx   : TRdxMethodCtx;
  Edits : TArray<TRdxEdit>;
begin
  APlan := Default(TRdxResultPlan);
  APlan.Name := STMT_INHERITED;
  Edits := nil;
  AReason := MethodCtxReason(AMap, ALine, AMessage, KW_CONSTRUCTOR, Ctx);
  if AReason = '' then
    AReason := CtorVariantReason(AMap, Ctx, APlan);
  if AReason = '' then
    AReason := FirstEdits(AMap, Ctx.Routine, APlan.Name + ';', Edits);
  Result := Finish(APlan, Edits, AReason);
end;

class function TRdxResultFixes.DestructorInherited(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxResultPlan;
  out AReason: string): Boolean;
var
  Ctx   : TRdxMethodCtx;
  Edits : TArray<TRdxEdit>;
begin
  APlan := Default(TRdxResultPlan);
  APlan.Name := STMT_INHERITED;
  APlan.Changes := True;
  Edits := nil;
  AReason := MethodCtxReason(AMap, ALine, AMessage, KW_DESTRUCTOR, Ctx);
  if AReason = '' then
    AReason := DtorOverrideReason(AMap, Ctx.Routine);
  if AReason = '' then
    AReason := AbstractReason(AMap, Ctx);
  if AReason = '' then
    AReason := DeadEndReason(AMap, Ctx.Routine);
  if AReason = '' then
    AReason := LastStatement(AMap, Ctx.Routine, STMT_INHERITED + ';', Edits);
  // TObject.Destroy ist leer: bei direktem TObject-Erben gleiche Bedeutung.
  if AReason = '' then
    APlan.Changes := not Ctx.Owner.DirectTObject;
  Result := Finish(APlan, Edits, AReason);
end;

class function TRdxResultFixes.ResultDefault(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxResultPlan;
  out AReason: string): Boolean;
var
  R     : TRdxRoutine;
  Name  : string;
  Value : string;
  Edits : TArray<TRdxEdit>;
begin
  APlan := Default(TRdxResultPlan);
  Edits := nil;
  Value := '';
  AReason := '';
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
    AReason := ScriptReason(AMap);
  if AReason = '' then
    AReason := ResultModeReason(AMap);
  if AReason = '' then
    AReason := AssignedReason(AMap, R);
  if AReason = '' then
  begin
    AReason := ValueReason(AMap, R, Value);
    APlan.Name := Value;
  end;
  if AReason = '' then
    AReason := FirstEdits(AMap, R, 'Result := ' + Value + ';', Edits);
  Result := Finish(APlan, Edits, AReason);
end;

class function TRdxResultFixes.ManagedResultInit(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxResultPlan;
  out AReason: string): Boolean;
var
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
  Name := TextBetween(AMessage, KEY_FUNC, KEY_READS);
  MsgType := TextBetween(AMessage, KEY_TYPE, KEY_TYPE_END);
  if (Name = '') or (MsgType = '') then
    AReason := 'Funktion oder Rueckgabetyp fehlt in der Meldung'
  // Der Name im Menue schon aus der Meldung (der Beweis folgt).
  else if StatementFor(AMap, MsgType, Stmt, Vars) = '' then
    APlan.Name := Stmt;
  if AReason = '' then
    AReason := FuncCtxReason(AMap, ALine, Name, MsgType, Ctx);
  if AReason = '' then
    AReason := StatementFor(AMap, Ctx.TypeTx, Stmt, Vars);
  if AReason = '' then
  begin
    APlan.Name := Stmt;
    APlan.NeedsVariants := Vars;
    AReason := FirstEdits(AMap, Ctx.Routine, Stmt + ';', Edits);
  end;
  Result := Finish(APlan, Edits, AReason);
end;

end.

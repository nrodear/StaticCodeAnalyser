unit uRdxSimpleFixes;

// reDelphix - die Planer der einfachen Editorhilfen
// (Konzept_Editorhilfen_2026-10-08). Stufe 2a (Nico 2026-10-09): SCA075
// class(TObject) -> class, SCA085 Free/nil -> FreeAndNil, SCA126 X = nil
// -> not Assigned(X); Stufe 2, Rest (2026-10-10): SCA074 Assert-Meldung,
// SCA087 leerer Sichtbarkeitsabschnitt, SCA139 X.Free -> FreeAndNil(X);
// uQuickFix-Umzug (2026-10-10, TRdxExprFixes): SCA066 leere Klammern,
// SCA072 Vergleich mit True/False, SCA084 Assigned + nil. OHNE ToolsAPI: aus den Zeilen der Datei werden gepruefte Ersetzungen
// (TRdxEdit), die uRdxEditor.ReplaceSpans in EINEM Undo-Schritt schreibt.
//
// GRUNDSATZ: lieber keine Hilfe als eine falsche. Jeder Planer prueft die
// Fundstelle mit derselben Grammatik wie der Detektor und lehnt mit einem
// Grund ab, sobald etwas nicht eindeutig ist (Analyse-Workflow
// editorhilfen-2a-analyse, 2026-10-09). Bezeichner, Schluesselwoerter und
// Leerraum bleiben in der Schreibweise des Puffers.
//
// Vorbild fuer SCA085 war uQuickFix (Core, entfernt 2026-10-10) - mit zwei
// bewussten Unterschieden: die nil-Zeile wird mit entfernt (dort blieb sie
// stehen), und die Stelle wird auf der Code-Sicht verankert (dort konnte
// ein nicht verankerter Ausdruck 'X.Free;' in einem Kommentar umschreiben).
//
// ENTSCHEID SCA085/SCA139 (Review Quick-Fix-Units 2026-10-14): FreeAndNil(X)
// setzt X auf nil, BEVOR der Destruktor laeuft - 'X.Free; X := nil;' erst
// danach. Wirft der Destruktor, ist X danach nil statt haengend, und bei
// SCA139 kommt ein nil-Schreibzugriff hinzu, den es vorher nicht gab. Das
// ist KEIN ChangesBehavior-Fall: FreeAndNil ist genau die Form, die der
// Detektor verlangt (sein 'good'-Beispiel), und der Unterschied ist ein
// Gewinn (kein haengender Zeiger nach einer Exception im Destruktor). Der
// Nutzer erfaehrt ihn trotzdem: der Hint der Hilfe (uRdxRecipeRunner,
// R_FREENIL_HINT) nennt die Reihenfolge.

interface

uses
  uRdxBufferMath, uRdxCodeMap;

type
  // Wie ein SCA126-Anker endet: Bedingung (if/while/case bis then/do/of)
  // oder Anweisung (bis ';' bzw. end/else/until/except/finally).
  TRdxNilAnchor = (naCondition, naStatement);

  // Wo eine SCA126-Anweisung beginnt (TSourcePlaces.NodesAt) und was der
  // Detektor dort gezaehlt hat.
  TRdxNilSite = record
    Line     : Integer;
    Col      : Integer;
    Anchor   : TRdxNilAnchor;
    NodeText : string;   // Name bzw. TypeRef des AST-Knotens
  end;

  // Ergebnis von TRdxNilFix.NilComparison.
  TRdxNilPlan = record
    Edits    : TArray<TRdxEdit>;
    Operands : TArray<string>;   // je Ersetzung der Operand X (Typpruefung)
    Reason   : string;           // warum keine Hilfe
  end;

  // Ersetzung eines Planers samt dem Bezeichner X, dessen Typ der Aufrufer
  // noch pruefen muss (SCA072, SCA084).
  TRdxOperandEdit = record
    Edit : TRdxEdit;
    Name : string;
  end;

  // SCA066: die Ersetzung samt den Namen, deren Typ der Aufrufer prueft.
  // Callee = der aufgerufene Name, wenn er allein steht ('Foo()', nicht
  // 'Obj.Foo()' oder 'inherited Foo()'), sonst ''; Target = die Variable
  // links von ':=' ('X := Foo()'), sonst ''.
  TRdxCallEdit = record
    Edit   : TRdxEdit;
    Callee : string;
    Target : string;
  end;

  // Die Planer der einfachen Hilfen: Zeilen und Token, ohne Parser.
  TRdxSimpleFixes = class
  public
    // SCA075: 'class(TObject)' an der Spalte aus der Meldung ('at column
    // N') -> 'class'. Die leere Kurzform 'class(TObject);' wird zu
    // 'class end;' - nie 'class;' (das waere eine Vorwaertsdeklaration).
    class function ExplicitTObject(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // SCA085: 'X.Free;' (Zeile ALine) + 'X := nil;' (naechste Zeile) ->
    // 'FreeAndNil(X);', die nil-Zeile entfaellt. AName = X wie im Puffer.
    // Typ und uses prueft der Aufrufer (braucht den Quellstellen-Dienst).
    // FreeAndNil setzt nil VOR dem Destruktor (Entscheid im Kopf der Unit:
    // gewollt, kein ChangesBehavior).
    class function FreeAndNilFix(AMap: TRdxCodeMap; ALine: Integer;
      out AEdits: TArray<TRdxEdit>; out AName: string;
      out AReason: string): Boolean; static;

    // SCA085-Kontext fuer den Aufrufer - FreeAndNil braucht eine Variable:
    // True, wenn AName irgendwo in der Datei als Property deklariert ist
    // ('property AName'; eine Property uebersetzt als Argument nicht).
    class function DeclaresProperty(AMap: TRdxCodeMap;
      const AName: string): Boolean; static;
    // True, wenn in der Routine um ALine vor dieser Zeile ein 'with' steht -
    // ein Name kann dort ein Member des with-Ausdrucks sein.
    class function WithBefore(AMap: TRdxCodeMap; ALine: Integer): Boolean; static;
    // True, wenn in der Routine um ALine vor dieser Zeile 'var AName :='
    // steht: eine Inline-Variable ohne Typangabe, die DeclaredTypeOf nicht
    // kennt.
    class function DeclaresInlineVar(AMap: TRdxCodeMap; ALine: Integer;
      const AName: string): Boolean; static;

    // ---- Editorhilfen Stufe 2, Rest (Nico 2026-10-10: "baue weitere") ----

    // SCA074: 'Assert(c)' an der Spalte aus der Meldung ('at column N') ->
    // 'Assert(c, ''c'')' - die Bedingung als Meldung. Nur, wenn die Klammer
    // auf derselben Zeile schliesst, kein Komma auf oberster Ebene und
    // kein Kommentar darin steht und es nicht 'Obj.Assert' ist; ein
    // Literal traegt hoechstens 255 Zeichen (E2056).
    class function AssertMessage(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
    // True, wenn die Datei eine Routine AName deklariert ('procedure
    // Assert' / 'function Assert', auch als Methode) - dann bindet der
    // Name nicht an die RTL.
    class function DeclaresRoutine(AMap: TRdxCodeMap;
      const AName: string): Boolean; static;

    // SCA087: die leere Sichtbarkeitszeile ALine loeschen. Nur, wenn sie
    // genau den Abschnitt aus der Meldung traegt ('Empty `public`
    // section', 'strict private' zweiteilig) und keinen Kommentar; nicht
    // bei 'strict' allein (es gehoert zur naechsten Zeile) und nicht, wenn
    // bis zum naechsten Code eine Direktive steht.
    class function EmptySection(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // SCA139: 'X.Free' -> 'FreeAndNil(X)' auf Zeile ALine, X = AReceiver
    // aus der Meldung (geschrieben wie im Quelltext). Genau ein Vorkommen
    // im Code der Zeile, X ein blosser Bezeichner (kein Pfad davor), 'Free'
    // ohne Klammern. Anders als SCA085 darf die Anweisung hinter
    // then/else/do stehen: ersetzt wird nur der Ausdruck, die Bedingung
    // bleibt. Variable und uses prueft der Aufrufer. FreeAndNil setzt nil
    // VOR dem Destruktor und schreibt X neu (Entscheid im Kopf der Unit:
    // gewollt, kein ChangesBehavior).
    class function FreeOnly(AMap: TRdxCodeMap; ALine: Integer;
      const AReceiver: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
    // True, wenn die Datei ATypeName als record, object, interface oder
    // dispinterface deklariert ('TFoo = packed record'): 'X.Free' ist dann
    // eine eigene Methode (Record, object) bzw. ein Interface-Aufruf,
    // FreeAndNil(X) waere falsch. VERTRAG WEITER ALS DER NAME: ein Interface
    // ist kein Werttyp, zaehlt hier aber mit - gemeint ist "kein Klassentyp,
    // auf dem FreeAndNil uebersetzt und das Richtige tut". Der Name bleibt,
    // weil ihn uRdxRecipeRunner (SCA139) ruft; umbenennen in einer Charge,
    // die den Laeufer anfasst. Ein Typ aus einer anderen Unit (auch ein
    // Alias, ein Zeiger oder ein generischer Record 'TRec<T>') ist hier
    // unbekannt (False) - in Delphi ab 10.4 faellt ein Record dort als
    // Fehler E2010 auf (FreeAndNil nimmt const [ref] TObject).
    class function DeclaresValueType(AMap: TRdxCodeMap;
      const ATypeName: string): Boolean; static;
    // Typ des Feldes AName, wenn die Datei es als Feld eines Klassen-,
    // Record- oder Objektrumpfs deklariert ('FOwner: TObject;' auf
    // Klammertiefe 0 - nicht Parameter, lokale Variable, Property, Methode
    // oder Konstante): der Typname klein ('tobject'; 'System.TObject' ->
    // 'tobject', 'TList<T>' -> 'tlist'), '^' fuer einen Zeigertyp, bei
    // procedure/function/reference/array/set/string das Wort selbst. ''
    // ohne Feld oder bei Feldern dieses Namens mit VERSCHIEDENEN Typen
    // (mehrdeutig). Ein gleichnamiges Feld einer ANDEREN Klasse derselben
    // Unit zaehlt mit - ohne Parser ist der Typ des Pfads davor unbekannt,
    // der Name ist der Beweis (SCA126, Pfad-Operanden).
    class function FieldTypeOf(AMap: TRdxCodeMap;
      const AName: string): string; static;
    // Das erste Wort hinter 'ATypeName =' in der Datei ('record', 'class',
    // 'procedure', 'reference' ...; 'packed' uebersprungen), klein; '' wenn
    // die Datei den Typ nicht deklariert. 'X: ATypeName = nil' (Variable
    // oder Parameter mit Anfangswert) ist keine Deklaration (Charge R10).
    class function DeclaredTypeKind(AMap: TRdxCodeMap;
      const ATypeName: string): string; static;
  end;

  // uQuickFix-Umzug (Beschluss 2026-10-09): SCA066, SCA072, SCA084 -
  // Ausdruecke auf einer Zeile, ohne Parser.
  TRdxExprFixes = class
  public
    // SCA066: 'Foo()' -> 'Foo' an der Spalte aus der Meldung (Spalte der
    // '('). Nur, wo Delphi den Namen ohne Klammern genauso aufruft: der
    // Aufruf ist eine ganze Anweisung ('Obj.Foo();' hinter begin, then,
    // ';' ...), die ganze Bedingung von if/while/until oder die ganze
    // rechte Seite einer Zuweisung an eine einfache Variable - deren Typ
    // prueft der Aufrufer (APlan.Target): ist er prozedural, liest Delphi
    // 'Foo' als Zeiger. Dazu Deklarationen ('procedure Foo();'). Als
    // Argument (Ueberladung mit TFunc, Assigned(Foo())) koennte der Name
    // als Zeiger gelten; ein Ereignisname ('OnIdle()') ist eine
    // Methodenreferenz, die ohne () nicht aufgerufen wird - dort und in der
    // eigenen Funktion keine Hilfe. Ob ein blosser Name eine Variable ist,
    // prueft der Aufrufer (APlan.Callee).
    class function EmptyArgs(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxCallEdit;
      out AReason: string): Boolean; static;

    // SCA072: 'X = True' / 'X <> False' -> 'X', 'X = False' / 'X <> True'
    // -> 'not X' an der Spalte aus der Meldung (Spalte des Operators). X ist
    // ein blosser Bezeichner (bei 'Self.X' koennte eine gleichnamige lokale
    // Variable den Typbeweis stellen); links davon beginnt ein Ausdruck
    // ('(', ',', ':=', if, while ...), rechts von True/False endet er
    // (')', then, do, ';' ...) - sonst bindet der Vergleich anders:
    // 'X = True and Y' ist 'X = (True and Y)'. Dass X ein Boolean ist,
    // prueft der Aufrufer (APlan.Name).
    class function RedundantBool(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxOperandEdit;
      out AReason: string): Boolean; static;

    // SCA084: 'Assigned(X) and (X <> nil)' bzw. '(X <> nil) and Assigned(X)'
    // -> 'Assigned(X)' an der Spalte aus der Meldung, alles auf einer Zeile.
    // Der Vergleich muss geklammert sein, davor kein 'not' (es bindet nur an
    // den ersten Teil), keine Aufruf- oder Cast-Klammer ('Boolean(X <> nil)').
    // Dass X eine Klasse, ein Interface oder ein Zeiger ist ('X <> nil' ruft
    // einen Funktionszeiger auf, Assigned() nicht), prueft der Aufrufer
    // (APlan.Name, PointerLikeType).
    class function AssignedNil(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxOperandEdit;
      out AReason: string): Boolean; static;

    // Art des Typs ATypeLow nach seiner Deklaration in der Datei
    // (DeclaredTypeKind), Aliasse bis drei Stufen aufgeloest ('TLookup =
    // TObjFunc' -> 'function'); bei einem Typ aus einer anderen Unit der
    // letzte Name der Kette, '' wenn die Datei ihn nicht deklariert.
    class function ResolvedTypeKind(AMap: TRdxCodeMap;
      const ATypeLow: string): string; static;
    // Ein Prozedurtyp (procedure/function/reference to, auch ueber Alias),
    // oder ein Name wie TNotifyEvent, TProc, Func? Typen aus anderen Units
    // mit unauffaelligem Namen sieht das nicht.
    class function ProceduralType(AMap: TRdxCodeMap;
      const ATypeLow: string): Boolean; static;
    // Als Klasse, Interface oder Zeiger BEWIESEN: TObject, Pointer,
    // IInterface/IUnknown, in dieser Unit so deklariert (auch ueber Alias)
    // oder - zweiter Beweisweg, Entscheid E27 (Nico 2026-10-14) - eine
    // Klasse oder ein Interface der Delphi-Quellen (uRdxRtlTypes, Liste
    // aus RTL/VCL/FMX/Data/...). Eine Zulassungsliste - Kundentypen
    // anderer Units fallen heraus.
    class function PointerLikeType(AMap: TRdxCodeMap;
      const ATypeLow: string): Boolean; static;
  end;

  // SCA126: X = nil -> not Assigned(X), X <> nil -> Assigned(X).
  TRdxNilFix = class
  public
    // Alle nil-Vergleiche der Anweisung an ASite werden zu Assigned(). Die
    // Zahl der Vergleiche im Code muss zu ASite.NodeText passen (dort hat
    // der Detektor gezaehlt) - alle oder keiner.
    class function NilComparison(AMap: TRdxCodeMap; const ASite: TRdxNilSite;
      out APlan: TRdxNilPlan): Boolean; static;

    // Zahl der nil-Vergleiche in einem AST-Knotentext - dieselbe Regel wie
    // uNilComparison.ContainsNilCompare, aber alle Vorkommen gezaehlt.
    class function CountNilComparisons(const AText: string): Integer; static;

    // Grund, warum 'Assigned(AOperand)' fuer diesen Operanden nicht sicher
    // dasselbe ist wie der Vergleich mit nil - NUR NACH NAMEN; '' = kein
    // Einwand. ATypeLow ist der deklarierte, nackte Typname
    // (DeclaredTypeOf), '' wenn unbekannt. Gesperrt: Ereignis-/Getter-Namen
    // (ein Methoden- oder Funktionszeiger: '= nil' ruft auf, Assigned()
    // prueft den Zeiger), Prozedur-, String-, Variant-, Array- und
    // Mengentypen nach ihrem Namen. Was die Datei dazu sagt (Prozedurtyp
    // dieser Unit, Pfadende als Feld), prueft NilOperandReason.
    class function NilOperandRisk(const AOperand, ATypeLow: string): string; static;

    // Die ganze Pruefung eines SCA126-Operanden, mit Blick in die Datei:
    // NilOperandRisk, dazu (Review Quick-Fix-Units 2026-10-14)
    //   * ein Prozedurtyp, den DIESE Unit deklariert ('TObjFactory =
    //     function: TObject', auch ueber Alias; TRdxExprFixes.
    //     ProceduralType) - '= nil' riefe die Funktion, Assigned() nicht;
    //   * ein blosser Bezeichner OHNE Typ (ATypeLow = '') ist nicht
    //     bewiesen - keine Hilfe;
    //   * ein Pfad ('List.First', 'Obj.ClassParent') nur, wenn er auf ')',
    //     ']' oder '^' endet (ein Ergebnis wird verglichen) oder sein
    //     letztes Glied in der Datei als Feld bewiesen ist (FieldTypeOf,
    //     dessen Typ geht durch dieselben Pruefungen). Sonst koennte das
    //     Glied eine parameterlose Methode sein: '= nil' ruft sie auf,
    //     Assigned() prueft den Methodenzeiger - die Logik kippte;
    //   * der Typ muss POSITIV als Klasse, Interface oder Zeiger bewiesen
    //     sein (PointerLikeType: TObject, Pointer, IInterface, in dieser
    //     Unit so deklariert oder - E27 - Klasse/Interface der Delphi-
    //     Quellen, uRdxRtlTypes) - wie SCA084. Ein Kundentyp aus einer
    //     anderen Unit mit neutralem Namen ('TObjFactory' aus uFactories)
    //     bleibt ohne Hilfe (Semantik-Gegen-Review 2026-10-14, Charge R8).
    // '' = kein Einwand.
    class function NilOperandReason(AMap: TRdxCodeMap;
      const AOperand, ATypeLow: string): string; static;
  end;

implementation

uses
  System.SysUtils, System.StrUtils,   // PosEx, EndsText, ContainsText
  uRefactorInfo, uRdxRtlTypes;

const
  MAX_REGION_LINES = 25;
  SPAN_075 = 'sca075';
  SPAN_085 = 'sca085';
  SPAN_126 = 'sca126';
  SPAN_074 = 'sca074';
  SPAN_087 = 'sca087';
  SPAN_139 = 'sca139';
  R_ASSERT_MOVED  = 'Assert( steht nicht mehr an der gemeldeten Stelle';
  // Ein String-Literal traegt bis Delphi 11 hoechstens 255 Zeichen (E2056;
  // Delphi 12 erlaubt mehr) - die Unit kann auch aelter uebersetzt werden.
  // Die Quotes und verdoppelten Apostrophe zaehlen hier mit - vorsichtig.
  MAX_ASSERT_LITERAL = 255;
  R_TOBJECT_MOVED = 'class(TObject) steht nicht mehr an der gemeldeten Stelle';
  NOT_PREFIX = 'not ';
  SPAN_066 = 'sca066';
  SPAN_072 = 'sca072';
  SPAN_084 = 'sca084';
  R_NO_COLUMN     = 'Spalte fehlt in der Meldung';
  R_ARGS_MOVED    = '() steht nicht mehr an der gemeldeten Stelle';
  R_BOOL_MOVED    = 'der Vergleich mit True/False steht nicht mehr an der '
    + 'gemeldeten Stelle';
  R_IN_EXPRESSION = 'der Aufruf ist Teil eines Ausdrucks - ohne Klammern '
    + 'koennte der Name als Zeiger gelten';
  R_BINDS_OTHER   = '%s - der Vergleich bindet dort anders';
  // Token, nach denen eine Anweisung beginnt (SCA066; ':' hinter einer
  // case-Marke): STATEMENT_PREV aus uRdxCodeMap - bis Charge R8 eine
  // eigene Liste ohne initialization/finalization.
  // Token, hinter denen die ganze rechte Seite bzw. Bedingung beginnt.
  WHOLE_EXPR_STARTS: array[0..3] of string = (':=', 'if', 'while', 'until');
  // Token, hinter denen ein Aufruf als ganze Anweisung/Bedingung endet.
  CALL_ENDS: array[0..7] of string = (';', 'end', 'else', 'until', 'then',
    'do', 'except', 'finally');
  // Token, hinter denen ein Teilausdruck beginnt - kein Operator bindet von
  // links her (SCA072).
  OPERAND_STARTS: array[0..9] of string = ('(', ',', '[', ':=', 'if',
    'while', 'until', 'begin', ';', 'repeat');
  // Token, mit denen ein Ausdruck endet - kein Operator bindet von rechts.
  EXPR_ENDS: array[0..11] of string = (')', ']', ',', ';', 'then', 'do',
    'else', 'end', 'until', 'of', 'except', 'finally');
  // SCA084: die zehn Token der beiden Formen; '' ist X (beide Male gleich).
  ASSIGNED_FIRST: array[0..9] of string = ('assigned', '(', '', ')', 'and',
    '(', '', '<>', 'nil', ')');
  NIL_FIRST: array[0..9] of string = ('(', '', '<>', 'nil', ')', 'and',
    'assigned', '(', '', ')');
  // Wo eine Deklaration beginnt ('procedure Foo();', SCA066).
  DECL_STARTS: array[0..3] of string = ('procedure', 'function',
    'constructor', 'destructor');
  // Prozedurtypen nach Name: genau diese bzw. diese Endungen (TNotifyEvent,
  // TProc, TFunc, Spring4D Func<T> ...). NICHT 'handler' oder 'method':
  // TIdIOHandler, TRttiMethod sind Klassen. 'tmethod' ist der Record hinter
  // 'of object'. Geteilt von SCA066, SCA084 und SCA126.
  PROC_TYPE_NAMES: array[0..8] of string = ('procedure', 'function',
    'reference', 'tmethod', 'tthreadmethod', 'tpredicate', 'tthreadprocedure',
    'func', 'proc');
  PROC_TYPE_SUFFIXES: array[0..5] of string = ('event', 'proc', 'func',
    'callback', 'procedure', 'function');
  // Klassen der RTL, deren Name auf eine Endung oben passt (System.SyncObjs:
  // Synchronisationsobjekte, keine Ereignisse) - ohne die Ausnahme hiesse
  // 'X = nil' bei einem TEvent "Prozedurtyp", ein falscher Grund (Review
  // Quick-Fix-Units 2026-10-14).
  NOT_PROC_TYPES: array[0..3] of string = ('tevent', 'tsimpleevent',
    'tlightweightevent', 'tcountdownevent');
  // Arten, bei denen die Alias-Aufloesung stehen bleibt.
  TYPE_KIND_WORDS: array[0..9] of string = ('class', 'record', 'object',
    'interface', 'dispinterface', 'reference', 'set', 'array', 'string',
    'file');
  // Sicher nil-vergleichbar und nicht prozedural (SCA084).
  POINTER_TYPES: array[0..3] of string = ('tobject', 'pointer', 'iinterface',
    'iunknown');
  R_FREE_MOVED    = 'X.Free; steht nicht mehr an der gemeldeten Stelle';
  R_NOT_NIL_LINE  = 'die naechste Zeile ist nicht "X := nil;"';

// Steht ab S[AAt] das Wort AWord (Gross/Klein egal, rechts kein
// Bezeichnerzeichen)?
function WordAt(const S: string; AAt: Integer; const AWord: string): Boolean;
var
  n : Integer;
begin
  n := Length(AWord);
  Result := SameText(Copy(S, AAt, n), AWord)
    and ((AAt + n > Length(S)) or not IsIdentChar(S[AAt + n]));
end;

function IsKeyword(const ALow: string): Boolean;
const
  // Reservierte Woerter, die keinen Operanden beginnen koennen. NICHT
  // darin: Exit, Assert, Free ... - das sind Routinen; 'Exit(' ist eine
  // Aufrufklammer, keine Gruppe.
  KEYWORDS: array[0..37] of string = (
    'and', 'or', 'xor', 'not', 'div', 'mod', 'shl', 'shr', 'in', 'is', 'as',
    'if', 'then', 'else', 'while', 'do', 'for', 'to', 'downto', 'repeat',
    'until', 'case', 'of', 'begin', 'end', 'with', 'try', 'except',
    'finally', 'raise', 'nil', 'var', 'const', 'procedure', 'function',
    'inherited', 'out', 'type');
var
  K : string;
begin
  for K in KEYWORDS do
    if ALow = K then Exit(True);
  Result := False;
end;

{ ---- SCA075 ---- }

// Dieselbe Grammatik wie der Detektor (uExplicitTObjectInheritance): ab
// ACol 'class', Leerraum, '(', Leerraum, 'TObject', Leerraum, ')'.
// ACloseCol = Spalte der ')'.
function MatchClassTObject(const L: string; ACol: Integer;
  out ACloseCol: Integer): Boolean;
var
  j : Integer;
begin
  Result := False;
  ACloseCol := 0;
  if not WordAt(L, ACol, 'class') or ((ACol > 1) and IsIdentChar(L[ACol - 1])) then
    Exit;
  j := SkipBlanks(L, ACol + 5);
  if (j > Length(L)) or (L[j] <> '(') then Exit;
  j := SkipBlanks(L, j + 1);
  if not WordAt(L, j, 'TObject') then Exit;
  j := SkipBlanks(L, j + 7);
  if (j > Length(L)) or (L[j] <> ')') then Exit;
  ACloseCol := j;
  Result := True;
end;

class function TRdxSimpleFixes.ExplicitTObject(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  L        : string;
  Col      : Integer;
  CloseCol : Integer;
  Next     : TRdxToken;
  NewText  : string;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  Col := ColumnFromMessage(AMessage);
  L := AMap.Raw(ALine);
  if (Col < 1) or (Col + 4 > Length(L)) then
  begin
    AReason := 'Spalte fehlt in der Meldung';
    Exit;
  end;
  if not MatchClassTObject(L, Col, CloseCol) then
  begin
    AReason := R_TOBJECT_MOVED;
    Exit;
  end;
  if AMap.HasNonCode(ALine, Col, CloseCol) then
  begin
    AReason := 'class(TObject) liegt in einem Kommentar oder String';
    Exit;
  end;
  // Was folgt auf die Klammer? 'class' bleibt in der Schreibweise des Puffers.
  NewText := Copy(L, Col, 5);
  Next := NextToken(AMap, ALine, CloseCol + 1);
  if Next.Low = ';' then
    // Leere Kurzform: 'class;' waere eine Vorwaertsdeklaration (E2086).
    NewText := NewText + ' end'
  else if Next.Low = 'end' then
  begin
    if (CloseCol < Length(L)) and IsIdentChar(L[CloseCol + 1]) then
      NewText := NewText + ' ';     // 'class(TObject)end;' -> 'class end;'
  end
  else if (Next.Line = ALine) and (Next.Low <> '') then
  begin
    // 'class(TObject) procedure P; end;' wuerde zu 'class procedure ...' -
    // liest sich als Klassenmethode. Lieber keine Hilfe.
    AReason := 'Klassenrumpf beginnt in derselben Zeile';
    Exit;
  end;
  AEdit.Span := TRefactorSpan.Make(SPAN_075, ALine, Col, ALine, CloseCol + 1);
  AEdit.Expected := Copy(L, Col, CloseCol - Col + 1);
  AEdit.NewText  := NewText;
  Result := True;
end;

{ ---- SCA085 ---- }

// 'X . Free ;' ab AColX (X ein Bezeichner): Ende von X, Ende von 'Free'
// und die Spalte des ';'.
function MatchFreeCall(const L: string; AColX: Integer;
  out ANameEnd, AFreeEnd, ASemiCol: Integer): Boolean;
var
  j : Integer;
begin
  Result := False;
  ANameEnd := 0;
  AFreeEnd := 0;
  ASemiCol := 0;
  if (AColX > Length(L)) or not IsIdentStart(L[AColX]) then Exit;
  j := AColX;
  while (j <= Length(L)) and IsIdentChar(L[j]) do Inc(j);
  ANameEnd := j;
  if (j > Length(L)) or (L[j] <> '.') then Exit;
  j := SkipBlanks(L, j + 1);
  if not WordAt(L, j, 'Free') then Exit;
  AFreeEnd := j + 4;
  j := SkipBlanks(L, AFreeEnd);
  if (j > Length(L)) or (L[j] <> ';') then Exit;
  ASemiCol := j;
  Result := True;
end;

// Eine Compiler-Direktive zwischen dem Token APrev und (ALine, ACol)?
// Dieselbe Regel wie DirectiveAt (uRdxCodeMap): ein '{$' in einem
// '//'-Kommentar ist keine - bis Charge R8 zaehlte es hier mit.
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

// Zeile ALine: erste Anweisung 'X.Free;' - wie
// uFreeAndNilHint.ExtractFreeReceiver, aber auf der Code-Sicht -, dahinter
// hoechstens ein //-Kommentar, und nicht allein hinter then/else/do oder
// einer case-Marke. '' oder der Grund.
function CheckFreeLine(AMap: TRdxCodeMap; ALine: Integer;
  out AColX, ANameEnd, AFreeEnd: Integer): string;
var
  L       : string;
  SemiCol : Integer;
  Rest    : string;
  Prev    : TRdxToken;
begin
  Result := '';
  L := AMap.Raw(ALine);
  AColX := 1;
  while (AColX <= Length(L)) and (IsBlank(L[AColX]) or not AMap.IsCode(ALine, AColX)) do
    Inc(AColX);
  if not MatchFreeCall(L, AColX, ANameEnd, AFreeEnd, SemiCol) then
    Exit(R_FREE_MOVED);
  if AMap.HasNonCode(ALine, AColX, SemiCol) then
    Exit('Kommentar im Ausdruck X.Free;');
  // Hinter dem ';' nur noch Leerraum oder ein //-Kommentar: weiterer Code
  // liefe sonst NACH dem nil (Reihenfolge), ein {-Kommentar oder eine
  // Direktive koennte die nil-Zeile umschliessen.
  Rest := Trim(Copy(L, SemiCol + 1, MaxInt));
  if (Rest <> '') and (Copy(Rest, 1, 2) <> '//') then
    Exit('hinter X.Free; steht noch etwas');
  // X.Free; als einzige Anweisung hinter then/else/do/case-Marke: dann
  // wuerde das bisher unbedingte ':= nil' bedingt.
  Prev := PrevToken(AMap, ALine, AColX);
  if (Prev.Low = 'then') or (Prev.Low = 'else') or (Prev.Low = 'do')
     or (Prev.Low = ':') then
    Exit(Format('X.Free; ist die Anweisung hinter "%s" - das nil wuerde bedingt',
      [Prev.Low]));
  // 'if A then {$IFDEF LOG}Log;{$ENDIF} X.Free;': ohne LOG steht X.Free;
  // allein hinter 'then' - die Sperre oben saehe nur das ';' von Log.
  if DirectiveBetween(AMap, Prev, ALine, AColX) then
    Result := 'Compiler-Direktive vor X.Free; - die Anweisung davor gilt nicht immer';
end;

// Die nil-Zeile N: genau 'X := nil;' (';' optional) mit X = AName.
// '' oder der Grund.
function CheckNilLine(const N, AName: string): string;
var
  k : Integer;
begin
  k := SkipBlanks(N, 1);
  if not WordAt(N, k, AName) then Exit(R_NOT_NIL_LINE);
  k := SkipBlanks(N, k + Length(AName));
  if Copy(N, k, 2) <> ':=' then Exit(R_NOT_NIL_LINE);
  k := SkipBlanks(N, k + 2);
  if not WordAt(N, k, 'nil') then Exit(R_NOT_NIL_LINE);
  k := SkipBlanks(N, k + 3);
  if (k <= Length(N)) and (N[k] = ';') then
    k := SkipBlanks(N, k + 1);
  if k <= Length(N) then
    Exit('hinter X := nil steht noch etwas');
  Result := '';
end;

class function TRdxSimpleFixes.FreeAndNilFix(AMap: TRdxCodeMap;
  ALine: Integer; out AEdits: TArray<TRdxEdit>; out AName: string;
  out AReason: string): Boolean;
var
  L, N                   : string;
  ColX, NameEnd, FreeEnd : Integer;
begin
  Result := False;
  AEdits := nil;
  AName := '';
  // Die nil-Zeile wird samt Zeilenende entfernt - dahinter muss eine
  // Zeile stehen (in einer Unit immer, mindestens 'end.').
  if (ALine < 1) or (ALine + 2 > AMap.LineCount) then
  begin
    AReason := 'keine Zeile hinter der nil-Zuweisung';
    Exit;
  end;
  AReason := CheckFreeLine(AMap, ALine, ColX, NameEnd, FreeEnd);
  if AReason <> '' then Exit;
  L := AMap.Raw(ALine);
  // Zeile i+1: genau 'X := nil;', ohne Kommentar.
  N := AMap.Raw(ALine + 1);
  if AMap.HasNonCode(ALine + 1, 1, Length(N)) then
  begin
    AReason := 'Kommentar oder String in der nil-Zeile';
    Exit;
  end;
  AReason := CheckNilLine(N, Copy(L, ColX, NameEnd - ColX));
  if AReason <> '' then Exit;

  AName := Copy(L, ColX, NameEnd - ColX);
  SetLength(AEdits, 2);
  // E1: 'X.Free' -> 'FreeAndNil(X)'; ';' und ein Kommentar bleiben stehen.
  AEdits[0].Span := TRefactorSpan.Make(SPAN_085, ALine, ColX, ALine, FreeEnd);
  AEdits[0].Expected := Copy(L, ColX, FreeEnd - ColX);
  AEdits[0].NewText  := 'FreeAndNil(' + AName + ')';
  // E2: die nil-Zeile samt Zeilenende.
  AEdits[1].Span := TRefactorSpan.Make(SPAN_085, ALine + 1, 1, ALine + 2, 1);
  AEdits[1].Expected := N + #10;
  AEdits[1].NewText  := '';
  Result := True;
end;

// Beginnt mit ALow eine Routine oder ein Abschnitt (in Spalte 1)?
function IsRoutineStart(const ALow: string): Boolean;
begin
  Result := (ALow = 'procedure') or (ALow = 'function') or (ALow = 'constructor')
    or (ALow = 'destructor') or (ALow = 'operator') or (ALow = 'class')
    or (ALow = 'initialization') or (ALow = 'finalization')
    or (ALow = 'implementation');
end;

// Erste Zeile der Routine um ALine: rueckwaerts die naechste Zeile, deren
// erstes Code-Token in Spalte 1 eine Routine oder einen Abschnitt beginnt
// (Konvention: Implementierungen stehen am Zeilenanfang, lokale Routinen
// und anonyme Methoden sind eingerueckt). 1, wenn keine kommt.
function RoutineStartLine(AMap: TRdxCodeMap; ALine: Integer): Integer;
var
  Li : Integer;
begin
  for Li := ALine - 1 downto 1 do
    if AMap.IsCode(Li, 1) and IsIdentStart(AMap.Raw(Li)[1])
       and IsRoutineStart(TokenAt(AMap, Li, 1).Low) then
      Exit(Li);
  Result := 1;
end;

// 'OnChange', 'FOnChange' (Ereignis) bzw. 'GetItem' (Getter): ein
// Grossbuchstabe hinter dem Praefix, sonst waere 'Online' ein Ereignis.
function HasCapPrefix(const AIdent, APrefix: string): Boolean;
var
  n : Integer;
begin
  n := Length(APrefix);
  Result := (Length(AIdent) > n) and (Copy(AIdent, 1, n) = APrefix)
    and CharInSet(AIdent[n + 1], ['A'..'Z']);
end;

// Nennt ATypeLow nach seinem Namen einen Prozedurtyp (PROC_TYPE_*)? Die
// RTL-Klassen in NOT_PROC_TYPES nicht.
function NamesProcType(const ATypeLow: string): Boolean;
var
  T : string;
begin
  if InList(ATypeLow, NOT_PROC_TYPES) then Exit(False);
  Result := InList(ATypeLow, PROC_TYPE_NAMES);
  if not Result then
    for T in PROC_TYPE_SUFFIXES do
      if (Length(ATypeLow) > Length(T)) and EndsText(T, ATypeLow) then
        Exit(True);
end;

// Das letzte Segment des Namens hinter ATok ('TFoo.Assert' -> 'Assert').
function NameAfter(AMap: TRdxCodeMap; const ATok: TRdxToken): TRdxToken;
begin
  Result := After(AMap, ATok);
  while (Result.Low <> '') and (After(AMap, Result).Low = '.') do
    Result := After(AMap, After(AMap, Result));
end;

// Steht im Code der Datei eines der Woerter AKeywords, gefolgt vom Namen
// AName (letztes Segment: 'procedure TFoo.Bar' zaehlt fuer 'Bar')?
function DeclaresAfter(AMap: TRdxCodeMap; const AKeywords: array of string;
  const AName: string): Boolean;
var
  T       : TRdxToken;
  NameLow : string;
begin
  Result := False;
  NameLow := LowerCase(AName);
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    if InList(T.Low, AKeywords) and (NameAfter(AMap, T).Low = NameLow) then
      Exit(True);
    T := After(AMap, T);
  end;
end;

class function TRdxSimpleFixes.DeclaresProperty(AMap: TRdxCodeMap;
  const AName: string): Boolean;
begin
  Result := DeclaresAfter(AMap, ['property'], AName);
end;

class function TRdxSimpleFixes.WithBefore(AMap: TRdxCodeMap;
  ALine: Integer): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  T := NextToken(AMap, RoutineStartLine(AMap, ALine), 1);
  while (T.Low <> '') and (T.Line < ALine) do
  begin
    if T.Low = 'with' then
      Exit(True);
    T := After(AMap, T);
  end;
end;

class function TRdxSimpleFixes.DeclaresInlineVar(AMap: TRdxCodeMap;
  ALine: Integer; const AName: string): Boolean;
var
  T, N    : TRdxToken;
  NameLow : string;
begin
  Result := False;
  NameLow := LowerCase(AName);
  T := NextToken(AMap, RoutineStartLine(AMap, ALine), 1);
  while (T.Low <> '') and (T.Line < ALine) do
  begin
    N := After(AMap, T);
    if (T.Low = 'var') and (N.Low = NameLow) and (After(AMap, N).Low = ':=') then
      Exit(True);
    T := N;
  end;
end;

{ ---- SCA074, SCA087, SCA139 (Editorhilfen Stufe 2, Rest) ---- }

class function TRdxSimpleFixes.DeclaresRoutine(AMap: TRdxCodeMap;
  const AName: string): Boolean;
begin
  Result := DeclaresAfter(AMap, ['procedure', 'function'], AName);
end;

// Das Token hinter dem Typnamen ATok, generische Parameter uebersprungen
// ('TFactory<T> = ...' -> '=').
function AfterTypeParams(AMap: TRdxCodeMap; const ATok: TRdxToken): TRdxToken;
var
  Depth : Integer;
begin
  Result := After(AMap, ATok);
  if Result.Low <> '<' then Exit;
  Depth := 0;
  repeat
    if Result.Low = '<' then
      Inc(Depth)
    else if Result.Low = '>' then
      Dec(Depth);
    Result := After(AMap, Result);
  until (Depth = 0) or (Result.Low = '') or (Result.Low = ';');
end;

class function TRdxSimpleFixes.DeclaredTypeKind(AMap: TRdxCodeMap;
  const ATypeName: string): string;
var
  T, K    : TRdxToken;
  TypeLow : string;
begin
  Result := '';
  TypeLow := LowerCase(ATypeName);
  if TypeLow = '' then Exit;
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    // ':' oder '.' davor: 'var X: TBitmap = nil;', ein Default-Parameter
    // 'Exclude: TControl = nil' oder 'C: Vcl.Graphics.TBitmap = nil' - das
    // ist der Typ einer Variablen mit Anfangswert, keine Deklaration des
    // Typs. Bis Charge R10 kam hier 'nil' heraus, und eine RTL-Klasse wie
    // TBitmap galt in der ganzen Unit als unbewiesen (Messung R10: 431
    // SCA126-Angebote mehr, die die Liste aus E27 sonst nicht erreicht).
    // Ein Typ wird nie hinter ':' oder '.' deklariert.
    if (T.Low = TypeLow) and (AfterTypeParams(AMap, T).Low = '=')
       and not InList(Before(AMap, T).Low, [':', '.']) then
    begin
      K := After(AMap, AfterTypeParams(AMap, T));
      if K.Low = 'packed' then
        K := After(AMap, K);
      Exit(K.Low);
    end;
    T := After(AMap, T);
  end;
end;

class function TRdxSimpleFixes.DeclaresValueType(AMap: TRdxCodeMap;
  const ATypeName: string): Boolean;
var
  Kind : string;
begin
  Kind := DeclaredTypeKind(AMap, ATypeName);
  Result := (Kind = 'record') or (Kind = 'object') or (Kind = 'interface')
    or (Kind = 'dispinterface');
end;

// Kopf eines Assert-Aufrufs an (ALine, ACol): 'Assert' als Wort im Code,
// kein 'Obj.' davor (nur 'System.'), dahinter '('. '' oder der Grund;
// AOpenCol = Spalte der '('.
function AssertHeadReason(AMap: TRdxCodeMap; ALine, ACol: Integer;
  out AOpenCol: Integer): string;
var
  L    : string;
  Prev : TRdxToken;
begin
  Result := '';
  AOpenCol := 0;
  if ACol < 1 then
    Exit(R_NO_COLUMN);
  L := AMap.Raw(ALine);
  if not WordAt(L, ACol, 'Assert') or not AMap.IsCode(ALine, ACol)
     or ((ACol > 1) and IsIdentChar(L[ACol - 1])) then
    Exit(R_ASSERT_MOVED);
  // 'Obj.Assert(x)' / 'Unit.Assert(x)' ist nicht die RTL - nur
  // 'System.Assert'. 'inherited Assert' bindet immer an einen Vorfahren,
  // 'procedure Assert(' ist die Deklaration selbst (der Detektor meldet
  // auch sie).
  Prev := PrevToken(AMap, ALine, ACol);
  if (Prev.Low = '.') and (Before(AMap, Prev).Low <> 'system') then
    Exit('Assert ist hier qualifiziert - nicht System.Assert');
  if (Prev.Low = 'inherited') or (Prev.Low = 'procedure')
     or (Prev.Low = 'function') then
    Exit(Format('"%s Assert" ist nicht der Aufruf von System.Assert',
      [Prev.Low]));
  AOpenCol := SkipBlanks(L, ACol + 6);
  if (AOpenCol > Length(L)) or (L[AOpenCol] <> '(')
     or not AMap.IsCode(ALine, AOpenCol) then
    Exit(R_ASSERT_MOVED);
end;

// Die ')' zur '(' an AOpenCol auf DERSELBEN Zeile, Tiefe nur ueber
// Code-Zeichen - dieselbe Zaehlung wie uAssertMessage. '' oder der Grund
// (Komma auf oberster Ebene: schon eine Meldung; keine ')': mehrzeilig).
function AssertCloseReason(AMap: TRdxCodeMap; ALine, AOpenCol: Integer;
  out ACloseCol: Integer): string;
var
  L     : string;
  Depth : Integer;
  j     : Integer;
begin
  Result := '';
  ACloseCol := 0;
  L := AMap.Raw(ALine);
  Depth := 1;
  for j := AOpenCol + 1 to Length(L) do
  begin
    if not AMap.IsCode(ALine, j) then
      Continue;
    case L[j] of
      '(':
        Inc(Depth);
      ')':
        begin
          Dec(Depth);
          if Depth = 0 then
          begin
            ACloseCol := j;
            Exit;
          end;
        end;
    else
      // Ein Komma auf oberster Ebene trennt ein zweites Argument ab.
      if (L[j] = ',') and (Depth = 1) then
        Exit('Assert hat schon eine Meldung');
    end;
  end;
  Result := 'Assert endet nicht auf dieser Zeile';
end;

class function TRdxSimpleFixes.AssertMessage(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  L        : string;
  Col      : Integer;
  OpenCol  : Integer;
  CloseCol : Integer;
  Inner    : string;
  Lit      : string;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  Col := ColumnFromMessage(AMessage);
  AReason := AssertHeadReason(AMap, ALine, Col, OpenCol);
  if AReason <> '' then Exit;
  AReason := AssertCloseReason(AMap, ALine, OpenCol, CloseCol);
  if AReason <> '' then Exit;
  // Ein Kommentar ginge sonst als Text in die Meldung.
  if AMap.HasComment(ALine, OpenCol, CloseCol) then
  begin
    AReason := 'Kommentar in der Bedingung';
    Exit;
  end;
  L := AMap.Raw(ALine);
  Inner := TrimRight(Copy(L, OpenCol + 1, CloseCol - OpenCol - 1));
  if Trim(Inner) = '' then
  begin
    AReason := 'Assert ohne Bedingung';
    Exit;
  end;
  Lit := '''' + StringReplace(Trim(Inner), '''', '''''', [rfReplaceAll]) + '''';
  if Length(Lit) > MAX_ASSERT_LITERAL then
  begin
    AReason := 'Bedingung zu lang fuer ein String-Literal (255 Zeichen)';
    Exit;
  end;
  AEdit.Span := TRefactorSpan.Make(SPAN_074, ALine, Col, ALine, CloseCol + 1);
  AEdit.Expected := Copy(L, Col, CloseCol - Col + 1);
  AEdit.NewText  := Copy(L, Col, OpenCol - Col + 1) + Inner + ', ' + Lit + ')';
  Result := True;
end;

// Leerraum-Laeufe zu einem Leerzeichen, ohne Leerraum am Rand.
function CollapseBlanks(const S: string): string;
var
  i, n  : Integer;
  Blank : Boolean;
begin
  SetLength(Result, Length(S));
  n := 0;
  Blank := False;
  for i := 1 to Length(S) do
    if IsBlank(S[i]) then
      Blank := True
    else
    begin
      if Blank and (n > 0) then
      begin
        Inc(n);
        Result[n] := ' ';
      end;
      Blank := False;
      Inc(n);
      Result[n] := S[i];
    end;
  SetLength(Result, n);
end;

// Beginnt ALow einen Sichtbarkeitsabschnitt oder schliesst 'end' die Klasse?
function IsSectionWord(const ALow: string): Boolean;
begin
  Result := (ALow = 'private') or (ALow = 'protected') or (ALow = 'public')
    or (ALow = 'published') or (ALow = 'strict') or (ALow = 'end');
end;

// 'Empty `strict private` section ...' - der Abschnitt zwischen den
// Backticks (uEmptyVisibilitySection.SektionsName), klein; '' ohne sie.
function SectionNameOf(const AMessage: string): string;
var
  p, q : Integer;
begin
  Result := '';
  p := Pos('`', AMessage);
  q := 0;
  if p > 0 then
    q := Pos('`', AMessage, p + 1);
  if q > 0 then
    Result := LowerCase(Copy(AMessage, p + 1, q - p - 1));
end;

// Traegt die Zeile ALine (Text L) genau den Abschnitt AName - ohne
// Kommentar, und 'strict' nicht von seinem Abschnitt getrennt? '' oder der
// Grund.
function SectionLineReason(AMap: TRdxCodeMap; ALine: Integer;
  const AName, L: string): string;
begin
  if AMap.StartsInside(ALine) or AMap.HasNonCode(ALine, 1, Length(L)) then
    Exit('Kommentar oder String auf der Zeile - er ginge beim Loeschen '
      + 'verloren');
  // 'strict' ohne 'private'/'protected' auf derselben Zeile: das Wort
  // gehoert zum Abschnitt der naechsten Zeile - weg damit wuerde aus
  // 'strict private' ein 'private'.
  if AName = 'strict' then
    Exit('strict steht allein - es gehoert zur naechsten Zeile');
  // Umgekehrt: 'strict' allein auf der Zeile davor gehoert zu DIESEM
  // Abschnitt - ohne ihn wuerde aus 'strict' + 'protected' ein 'strict
  // protected'.
  if PrevToken(AMap, ALine, 1).Low = 'strict' then
    Exit('strict auf der Zeile davor gehoert zu diesem Abschnitt');
  if LowerCase(CollapseBlanks(L)) <> AName then
    Exit(Format('Zeile %d traegt nicht nur "%s" - Zeile verschoben? '
      + 'Datei neu pruefen', [ALine, AName]));
  Result := '';
end;

// Ist der Abschnitt hinter ALine leer? Nur, wenn als naechstes Code ein
// Abschnitt oder 'end' folgt, ohne Direktive dazwischen. Der Detektor
// sieht Zeilen nicht, die mit '&' oder einem Umlaut beginnen ('&Type:
// ...', 'Aenderung: ...' mit Umlaut) - deren Abschnitt haelt er
// faelschlich fuer leer (Gegen-Review 2026-10-10). '' oder der Grund.
function SectionEmptyReason(AMap: TRdxCodeMap; ALine: Integer): string;
var
  Next : TRdxToken;
begin
  Next := NextToken(AMap, ALine + 1, 1);
  if not IsSectionWord(Next.Low) then
    Exit(Format('nach dem Abschnitt folgt "%s" - er ist nicht leer',
      [Next.Low]));
  if DirectiveBefore(AMap, ALine + 1, Next) then
    Exit('Compiler-Direktive bis zum naechsten Abschnitt - der leere '
      + 'Abschnitt gilt evtl. nur in einem Zweig');
  Result := '';
end;

class function TRdxSimpleFixes.EmptySection(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  L    : string;
  Name : string;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  L := '';
  Name := SectionNameOf(AMessage);
  if Name = '' then
    AReason := 'Abschnitt fehlt in der Meldung'
  // Die Zeile wird samt Zeilenende geloescht - dahinter steht in einer
  // Klasse immer noch eine Zeile (mindestens 'end').
  else if (ALine < 1) or (ALine >= AMap.LineCount) then
    AReason := 'keine Zeile hinter dem Abschnitt'
  else
  begin
    L := AMap.Raw(ALine);
    AReason := SectionLineReason(AMap, ALine, Name, L);
    if AReason = '' then
      AReason := SectionEmptyReason(AMap, ALine);
  end;
  if AReason <> '' then Exit;
  AEdit.Span := TRefactorSpan.Make(SPAN_087, ALine, 1, ALine + 1, 1);
  AEdit.Expected := L + #10;
  AEdit.NewText  := '';
  Result := True;
end;

// Die Code-Vorkommen von 'X.Free' auf Zeile ALine (X = AReceiver als
// ganzes Wort, Leerraum um den Punkt erlaubt): Anzahl; ACol/AFreeEnd vom
// letzten (Spalte von X, Spalte hinter 'Free').
function CountFreeCalls(AMap: TRdxCodeMap; ALine: Integer;
  const AReceiver: string; out ACol, AFreeEnd: Integer): Integer;
var
  L    : string;
  j, k : Integer;
begin
  Result := 0;
  ACol := 0;
  AFreeEnd := 0;
  L := AMap.Raw(ALine);
  for j := 1 to Length(L) do
  begin
    if not AMap.IsCode(ALine, j) or not WordAt(L, j, AReceiver)
       or ((j > 1) and IsIdentChar(L[j - 1])) then
      Continue;
    k := SkipBlanks(L, j + Length(AReceiver));
    if (k > Length(L)) or (L[k] <> '.') or not AMap.IsCode(ALine, k) then
      Continue;
    k := SkipBlanks(L, k + 1);
    if WordAt(L, k, 'Free') and AMap.IsCode(ALine, k) then
    begin
      Inc(Result);
      ACol := j;
      AFreeEnd := k + 4;
    end;
  end;
end;

// Der Grund, wenn nicht genau EIN 'X.Free' auf der Zeile steht. Der
// Detektor meldet auch 'X.Destroy' (als 'X.Free').
function FreeCountReason(const ALineText, AReceiver: string;
  AFound: Integer): string;
begin
  if AFound > 1 then
    Result := Format('%s.Free steht mehrmals auf der Zeile', [AReceiver])
  else if ContainsText(ALineText, AReceiver + '.Destroy') then
    Result := Format('%s.Destroy statt %s.Free - FreeAndNil ersetzt nur Free',
      [AReceiver, AReceiver])
  else
    Result := Format('%s.Free steht nicht mehr auf der Zeile - Zeile '
      + 'verschoben? Datei neu pruefen', [AReceiver]);
end;

class function TRdxSimpleFixes.FreeOnly(AMap: TRdxCodeMap; ALine: Integer;
  const AReceiver: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  L       : string;
  k       : Integer;
  Col     : Integer;
  FreeEnd : Integer;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  if AReceiver = '' then
  begin
    AReason := 'Empfaenger fehlt in der Meldung';
    Exit;
  end;
  L := AMap.Raw(ALine);
  k := CountFreeCalls(AMap, ALine, AReceiver, Col, FreeEnd);
  if k <> 1 then
  begin
    AReason := FreeCountReason(L, AReceiver, k);
    Exit;
  end;
  // Ein Pfad davor ('Obj.X.Free', 'Self.X.Free'): keine blosse Variable.
  k := Col - 1;
  while (k >= 1) and IsBlank(L[k]) do
    Dec(k);
  if (k >= 1) and (L[k] = '.') then
  begin
    AReason := Format('%s.Free haengt an einem Pfad - FreeAndNil braucht '
      + 'eine Variable', [AReceiver]);
    Exit;
  end;
  k := SkipBlanks(L, FreeEnd);
  if (k <= Length(L)) and (L[k] = '(') then
  begin
    AReason := 'X.Free() mit Klammern';
    Exit;
  end;
  AEdit.Span := TRefactorSpan.Make(SPAN_139, ALine, Col, ALine, FreeEnd);
  AEdit.Expected := Copy(L, Col, FreeEnd - Col);
  AEdit.NewText  := 'FreeAndNil(' + Copy(L, Col, Length(AReceiver)) + ')';
  Result := True;
end;

{ ---- uQuickFix-Umzug: SCA066, SCA072, SCA084 ---- }

// Erstes Token der Aufrufkette, die mit AName endet ('Obj.Sub.Foo',
// 'inherited Foo'); Low = '' wenn ein Glied kein blosser Name ist
// ('F().Foo', 'TFoo<T>.Create').
function ChainStart(AMap: TRdxCodeMap; const AName: TRdxToken): TRdxToken;
var
  Dot, Prev : TRdxToken;
begin
  Result := AName;
  Dot := Before(AMap, Result);
  while Dot.Low = '.' do
  begin
    Prev := Before(AMap, Dot);
    if not Prev.IsWord or IsKeyword(Prev.Low) then
      Exit(Default(TRdxToken));
    Result := Prev;
    Dot := Before(AMap, Result);
  end;
  if Dot.Low = 'inherited' then
    Result := Dot;
end;

// Steht zwischen dem Anfang der Routine um ALine und ALine ein Kopf
// 'function ALow' (auch verschachtelt, auch 'TFoo.ALow')? Dort kann der
// blosse Name das Ergebnis der Funktion meinen statt eines Aufrufs.
function InsideOwnFunction(AMap: TRdxCodeMap; ALine: Integer;
  const ALow: string): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  T := NextToken(AMap, RoutineStartLine(AMap, ALine), 1);
  while (T.Low <> '') and (T.Line <= ALine) do
  begin
    if (T.Low = 'function') and (NameAfter(AMap, T).Low = ALow) then
      Exit(True);
    T := After(AMap, T);
  end;
end;

// Links von ':=' (AAssign) muss eine einfache Variable am Anfang einer
// Anweisung stehen: ihr Typ entscheidet, ob Delphi 'Foo' ohne Klammern
// aufruft oder als Prozedurwert liest - der Aufrufer prueft ihn (ATarget).
// Pfad, Index und 'var X :=' (Typ aus der rechten Seite) sperren.
function AssignTargetReason(AMap: TRdxCodeMap; const AAssign: TRdxToken;
  out ATarget: string): string;
var
  Lhs : TRdxToken;
begin
  Result := '';
  ATarget := '';
  Lhs := Before(AMap, AAssign);
  if not Lhs.IsWord or IsKeyword(Lhs.Low)
     or not InList(Before(AMap, Lhs).Low, STATEMENT_PREV) then
    Exit('links von := steht keine einfache Variable (Pfad, Index oder '
      + 'var-Deklaration) - ihr Typ entscheidet ueber die Bedeutung');
  ATarget := Copy(AMap.Raw(Lhs.Line), Lhs.Col, Lhs.Len);
end;

// Deklaration 'procedure Foo();' / 'function TFoo.Bar(): Integer;': ohne
// Klammern dieselbe, solange ';' oder ':' folgt (keine Direktive dahinter).
function DeclArgsReason(const ANext: TRdxToken): string;
begin
  Result := '';
  if (ANext.Low <> ';') and (ANext.Low <> ':') then
    Result := 'Deklaration: hinter () steht weder ";" noch ":"';
end;

// Darf 'Name()' hier ohne Klammern stehen (s. EmptyArgs)? '' oder der Grund;
// ATarget wie in AssignTargetReason.
function EmptyArgsContext(AMap: TRdxCodeMap; const AName, AClose: TRdxToken;
  out ATarget: string): string;
var
  Start, Prev, Next : TRdxToken;
  Name              : string;
begin
  Result := '';
  ATarget := '';
  Start := ChainStart(AMap, AName);
  if Start.Low = '' then
    Exit('ein Glied der Aufrufkette ist kein blosser Name');
  Prev := Before(AMap, Start);
  Next := After(AMap, AClose);
  if InList(Prev.Low, DECL_STARTS) then
    Exit(DeclArgsReason(Next));
  if (not InList(Prev.Low, STATEMENT_PREV)
      and not InList(Prev.Low, WHOLE_EXPR_STARTS))
     or ((Next.Low <> '') and not InList(Next.Low, CALL_ENDS)) then
    Exit(R_IN_EXPRESSION);
  Name := Copy(AMap.Raw(AName.Line), AName.Col, AName.Len);
  if HasCapPrefix(Name, 'On') or HasCapPrefix(Name, 'FOn') then
    Exit(Format('%s sieht nach Ereignis aus - eine Methodenreferenz ruft '
      + 'Delphi ohne () nicht auf', [Name]));
  if (Start.Col = AName.Col) and (Start.Line = AName.Line)
     and InsideOwnFunction(AMap, AName.Line, AName.Low) then
    Exit(Format('%s() in der Funktion %s - ohne Klammern haengt die Bedeutung '
      + 'vom Dialekt ab (Rekursion oder Ergebnis)', [Name, Name]));
  if Prev.Low = ':=' then
    Result := AssignTargetReason(AMap, Prev, ATarget);
end;

// Die SCA066-Ersetzung: von hinter dem Namen bis hinter ')' loeschen;
// Callee = der Name, wenn er allein steht (kein '.' und kein 'inherited'
// davor).
procedure FillCallEdit(AMap: TRdxCodeMap; ALine: Integer;
  const ANameTok, AClose: TRdxToken; var APlan: TRdxCallEdit);
var
  L    : string;
  Prev : string;
begin
  L := AMap.Raw(ALine);
  Prev := Before(AMap, ANameTok).Low;
  if (Prev <> '.') and (Prev <> 'inherited') then
    APlan.Callee := Copy(L, ANameTok.Col, ANameTok.Len);
  APlan.Edit.Span := TRefactorSpan.Make(SPAN_066, ALine, ANameTok.EndCol, ALine,
    AClose.EndCol);
  APlan.Edit.Expected := Copy(L, ANameTok.EndCol, AClose.EndCol - ANameTok.EndCol);
  // 'Done()then' -> 'Done then', nicht 'Donethen'.
  APlan.Edit.NewText := '';
  if (AClose.EndCol <= Length(L)) and IsIdentChar(L[AClose.EndCol]) then
    APlan.Edit.NewText := ' ';
end;

class function TRdxExprFixes.EmptyArgs(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out APlan: TRdxCallEdit; out AReason: string): Boolean;
var
  L       : string;
  Col     : Integer;
  NameTok : TRdxToken;
  Close   : TRdxToken;
begin
  Result := False;
  APlan := Default(TRdxCallEdit);
  AReason := '';
  Col := ColumnFromMessage(AMessage);
  if Col < 1 then
  begin
    AReason := R_NO_COLUMN;
    Exit;
  end;
  L := AMap.Raw(ALine);
  if (Col > Length(L)) or (L[Col] <> '(') or not AMap.IsCode(ALine, Col) then
  begin
    AReason := R_ARGS_MOVED;
    Exit;
  end;
  // Zwischen Name und '(' sowie in den Klammern nur Leerraum - kein
  // Kommentar, der beim Loeschen verloren ginge.
  Close := NextToken(AMap, ALine, Col + 1);
  NameTok := PrevToken(AMap, ALine, Col);
  if (Close.Low <> ')') or (Close.Line <> ALine)
     or (SkipBlanks(L, Col + 1) <> Close.Col) then
    AReason := 'in den Klammern steht nicht nur Leerraum'
  else if not NameTok.IsWord or IsKeyword(NameTok.Low)
          or (NameTok.Line <> ALine) then
    AReason := 'vor () steht kein blosser Name (Element- oder Ergebnisaufruf)'
  else if SkipBlanks(L, NameTok.EndCol) <> Col then
    AReason := 'zwischen Name und () steht nicht nur Leerraum'
  else
    AReason := EmptyArgsContext(AMap, NameTok, Close, APlan.Target);
  if AReason <> '' then Exit;
  FillCallEdit(AMap, ALine, NameTok, Close, APlan);
  Result := True;
end;

// Die Token um den Vergleich AOp (s. RedundantBool): '' oder der Grund.
function BoolOperandsReason(AMap: TRdxCodeMap;
  const AOp, ALhs, ARhs: TRdxToken): string;
var
  Prev : TRdxToken;
begin
  Result := '';
  if ((AOp.Low <> '=') and (AOp.Low <> '<>'))
     or ((ARhs.Low <> 'true') and (ARhs.Low <> 'false'))
     or (ARhs.Line <> AOp.Line) then
    Exit(R_BOOL_MOVED);
  if not ALhs.IsWord or IsKeyword(ALhs.Low) or (ALhs.Line <> AOp.Line) then
    Exit('links vom Vergleich steht kein blosser Name');
  Prev := Before(AMap, ALhs);
  if Prev.Low = '.' then
    Exit('links steht ein Pfad - sein Typ ist hier nicht beweisbar');
  if not InList(Prev.Low, OPERAND_STARTS) then
    Exit(Format(R_BINDS_OTHER, ['links vom Namen steht "' + Prev.Low + '"']));
  if not InList(After(AMap, ARhs).Low, EXPR_ENDS) then
    Exit(Format(R_BINDS_OTHER, ['hinter ' + ARhs.Low + ' geht der Ausdruck weiter']));
end;

class function TRdxExprFixes.RedundantBool(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out APlan: TRdxOperandEdit;
  out AReason: string): Boolean;
var
  L            : string;
  Col          : Integer;
  Op, Lhs, Rhs : TRdxToken;
begin
  Result := False;
  APlan := Default(TRdxOperandEdit);
  Col := ColumnFromMessage(AMessage);
  if Col < 1 then
  begin
    AReason := R_NO_COLUMN;
    Exit;
  end;
  L := AMap.Raw(ALine);
  // ':=', '<=', '>=' sind kein Vergleich auf Gleichheit.
  if (Col > Length(L)) or not AMap.IsCode(ALine, Col)
     or ((Col > 1) and CharInSet(L[Col - 1], [':', '<', '>'])) then
  begin
    AReason := R_BOOL_MOVED;
    Exit;
  end;
  Op := TokenAt(AMap, ALine, Col);
  Lhs := PrevToken(AMap, ALine, Col);
  Rhs := After(AMap, Op);
  AReason := BoolOperandsReason(AMap, Op, Lhs, Rhs);
  if AReason <> '' then Exit;
  if AMap.HasComment(ALine, Lhs.Col, Rhs.EndCol - 1) then
  begin
    AReason := 'Kommentar im Vergleich';
    Exit;
  end;
  APlan.Name := Copy(L, Lhs.Col, Lhs.Len);
  // '= False' und '<> True' verneinen; 'not' bindet staerker als jeder
  // Vergleich, der Operand ist ein Name - keine Klammern noetig.
  APlan.Edit.NewText := APlan.Name;
  if (Op.Low = '=') = (Rhs.Low = 'false') then
    APlan.Edit.NewText := NOT_PREFIX + APlan.Name;
  APlan.Edit.Span := TRefactorSpan.Make(SPAN_072, ALine, Lhs.Col, ALine,
    Rhs.EndCol);
  APlan.Edit.Expected := Copy(L, Lhs.Col, Rhs.EndCol - Lhs.Col);
  Result := True;
end;

// Passt ATok zum Musterteil APart? '' steht fuer den Namen X: ein
// Bezeichner, beim zweiten Mal derselbe wie in AName gemerkt.
function TokenFits(const ATok: TRdxToken; const APart: string;
  var AName: string): Boolean;
begin
  if APart <> '' then
    Exit(ATok.Low = APart);
  Result := ATok.IsWord and not IsKeyword(ATok.Low)
    and ((AName = '') or (ATok.Low = AName));
  if Result then
    AName := ATok.Low;
end;

// Die zehn Token ab AFirst gegen APattern ('' = X, beide Male derselbe
// Name), alle auf der Zeile von AFirst. AToks traegt die Token.
function MatchTokens(AMap: TRdxCodeMap; const AFirst: TRdxToken;
  const APattern: array of string; out AToks: TArray<TRdxToken>): Boolean;
var
  i    : Integer;
  Name : string;
begin
  Result := False;
  SetLength(AToks, Length(APattern));
  AToks[0] := AFirst;
  for i := 1 to High(APattern) do
    AToks[i] := After(AMap, AToks[i - 1]);
  Name := '';
  for i := 0 to High(APattern) do
    if (AToks[i].Line <> AFirst.Line)
       or not TokenFits(AToks[i], APattern[i], Name) then
      Exit;
  Result := True;
end;

// Was vor und hinter dem SCA084-Ausdruck steht: '' oder der Grund. 'not'
// davor bindet nur an den ersten Teil, ein Selektor dahinter nur an den
// letzten; ein Name oder ')' davor macht die Klammer zur Aufruf- oder
// Cast-Klammer ('Boolean(X <> nil) and ...'); '.' davor: 'Obj.Assigned'.
function AssignedNilContext(AMap: TRdxCodeMap;
  const AFirst, ALast: TRdxToken): string;
var
  Prev : TRdxToken;
  Next : string;
begin
  Result := '';
  Prev := Before(AMap, AFirst);
  if Prev.Low = '.' then
    Exit('Assigned ist hier qualifiziert - nicht die Systemroutine');
  if (Prev.Low = 'not') or (Prev.Low = '@') then
    Exit(Format('"%s" vor dem Ausdruck bindet nur an seinen ersten Teil',
      [Prev.Low]));
  if (Prev.IsWord and not IsKeyword(Prev.Low))
     or InList(Prev.Low, [')', ']', '>', '^']) then
    Exit(Format('"%s" vor dem Ausdruck - die Klammer gehoert zu einem Aufruf '
      + 'oder Cast', [Prev.Low]));
  Next := After(AMap, ALast).Low;
  if (Next = '.') or (Next = '[') or (Next = '^') then
    Exit(Format('"%s" hinter dem Ausdruck bindet nur an seinen letzten Teil', [Next]));
end;

class function TRdxExprFixes.AssignedNil(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out APlan: TRdxOperandEdit;
  out AReason: string): Boolean;
var
  L     : string;
  Col   : Integer;
  First : TRdxToken;
  Toks  : TArray<TRdxToken>;
  Keep  : Integer;   // Index von 'Assigned' in Toks
begin
  Result := False;
  APlan := Default(TRdxOperandEdit);
  Col := ColumnFromMessage(AMessage);
  if Col < 1 then
  begin
    AReason := R_NO_COLUMN;
    Exit;
  end;
  L := AMap.Raw(ALine);
  if (Col > Length(L)) or not AMap.IsCode(ALine, Col) then
  begin
    AReason := 'Assigned(X) steht nicht mehr an der gemeldeten Stelle';
    Exit;
  end;
  First := TokenAt(AMap, ALine, Col);
  if MatchTokens(AMap, First, ASSIGNED_FIRST, Toks) then
    Keep := 0
  else if MatchTokens(AMap, First, NIL_FIRST, Toks) then
    Keep := 6
  else
  begin
    AReason := 'kein "Assigned(X) and (X <> nil)" auf einer Zeile an der '
      + 'Stelle (ohne Klammern um den Vergleich keine Hilfe)';
    Exit;
  end;
  AReason := AssignedNilContext(AMap, First, Toks[9]);
  if AReason <> '' then Exit;
  if AMap.HasComment(ALine, First.Col, Toks[9].EndCol - 1) then
  begin
    AReason := 'Kommentar im Ausdruck';
    Exit;
  end;
  APlan.Name := Copy(L, Toks[Keep + 2].Col, Toks[Keep + 2].Len);
  APlan.Edit.Span := TRefactorSpan.Make(SPAN_084, ALine, First.Col, ALine,
    Toks[9].EndCol);
  APlan.Edit.Expected := Copy(L, First.Col, Toks[9].EndCol - First.Col);
  APlan.Edit.NewText  := Copy(L, Toks[Keep].Col,
    Toks[Keep + 3].EndCol - Toks[Keep].Col);
  // 'if(X <> nil) and ...' -> 'if Assigned(X)', nicht 'ifAssigned(X)'.
  if (First.Col > 1) and IsIdentChar(L[First.Col - 1]) then
    APlan.Edit.NewText := ' ' + APlan.Edit.NewText;
  Result := True;
end;

class function TRdxExprFixes.ResolvedTypeKind(AMap: TRdxCodeMap;
  const ATypeLow: string): string;
const
  MAX_ALIAS = 3;
var
  i    : Integer;
  Next : string;
begin
  Result := TRdxSimpleFixes.DeclaredTypeKind(AMap, ATypeLow);
  for i := 1 to MAX_ALIAS do
  begin
    if (Result = '') or not IsIdentStart(Result[1]) or IsKeyword(Result)
       or InList(Result, TYPE_KIND_WORDS) then
      Exit;
    Next := TRdxSimpleFixes.DeclaredTypeKind(AMap, Result);
    if Next = '' then
      Exit;   // Alias auf einen Typ einer anderen Unit: dessen Name
    Result := Next;
  end;
end;

class function TRdxExprFixes.ProceduralType(AMap: TRdxCodeMap;
  const ATypeLow: string): Boolean;
var
  Kind : string;
begin
  Kind := ResolvedTypeKind(AMap, ATypeLow);
  Result := NamesProcType(ATypeLow) or NamesProcType(Kind);
end;

class function TRdxExprFixes.PointerLikeType(AMap: TRdxCodeMap;
  const ATypeLow: string): Boolean;
var
  Kind : string;
begin
  // '^' allein: ein Feld mit anonymem Zeigertyp ('FX: ^Integer'), so
  // liefert es FieldTypeOf (SCA126, Charge R8).
  Kind := ResolvedTypeKind(AMap, ATypeLow);
  Result := (ATypeLow = '^') or InList(ATypeLow, POINTER_TYPES)
    or InList(Kind, POINTER_TYPES)
    or InList(Kind, ['class', 'interface', 'dispinterface', '^']);
  if Result then Exit;
  // Zweiter Beweisweg, Entscheid E27 (Nico 2026-10-14): NACH dem Beweis
  // dieser Unit - eine Klasse oder ein Interface der Delphi-Quellen gilt
  // als bewiesen (uRdxRtlTypes, erzeugt aus Delphi 12 und 13). Das holt
  // 'FList: TStringList', 'Form: TForm' zurueck, die seit Charge R8 ohne
  // Hilfe blieben (im Korpus 58,8 % der SCA126-Angebote, Messung R9);
  // Kundentypen bleiben R_NOT_PROVEN. Gefragt wird der Name, den diese
  // Unit NICHT selbst deklariert: ATypeLow, wenn die Unit ihn nicht kennt
  // (Kind = ''), sonst das Ende der Alias-Kette ('TMyList = TStringList'
  // -> 'tstringlist'). Deklariert die Unit den Namen als etwas anderes
  // ('record', 'procedure', ein Aufzaehlungstyp), ist Kind ein Typwort
  // oder kein Bezeichner - fuer die steht nichts in der Liste, die Unit
  // behaelt das letzte Wort. Einen Kunden-Prozedurtyp mit RTL-Namen in
  // derselben Unit faengt ProceduralType vorher ab (beide Aufrufer).
  if Kind = '' then
    Kind := ATypeLow;
  Result := IsRtlClassOrInterface(Kind);
end;

{ ---- SCA126: Zaehlen wie der Detektor ---- }

// String-Literale durch Leerzeichen ersetzt, klein geschrieben.
function BlankStrings(const AText: string): string;
var
  i     : Integer;
  InStr : Boolean;
begin
  Result := AText;
  InStr := False;
  for i := 1 to Length(Result) do
    if Result[i] = '''' then
    begin
      InStr := not InStr;
      Result[i] := ' ';
    end
    else if InStr then
      Result[i] := ' ';
  Result := LowerCase(Result);
end;

// 'nil' an S[p] als ganzes Wort?
function IsNilWordAt(const S: string; p: Integer): Boolean;
begin
  Result := ((p = 1) or not IsIdentChar(S[p - 1]))
    and ((p + 3 > Length(S)) or not IsIdentChar(S[p + 3]));
end;

// Rechts vom 'nil' an S[p] ein '=' oder '<>' (Yoda)? Nur Leerzeichen
// zaehlen als Abstand - der Knotentext hat keine anderen.
function NilComparedRight(const S: string; p: Integer): Boolean;
var
  q : Integer;
begin
  q := p + 3;
  while (q <= Length(S)) and (S[q] = ' ') do Inc(q);
  Result := (q <= Length(S)) and ((S[q] = '=') or (Copy(S, q, 2) = '<>'));
end;

// Links vom 'nil' an S[p] ein '=' (ohne ':', '<', '>' davor) oder '<>'?
function NilComparedLeft(const S: string; p: Integer): Boolean;
var
  q : Integer;
begin
  q := p - 1;
  while (q >= 1) and (S[q] = ' ') do Dec(q);
  if q < 1 then Exit(False);
  if S[q] = '=' then
    Result := (q = 1) or not CharInSet(S[q - 1], [':', '<', '>'])
  else
    Result := (S[q] = '>') and (q > 1) and (S[q - 1] = '<');
end;

class function TRdxNilFix.CountNilComparisons(const AText: string): Integer;
var
  S : string;
  p : Integer;
begin
  // Wie uNilComparison.ContainsNilCompare: String-Literale weg, klein,
  // 'nil' als ganzes Wort mit einem Vergleich rechts oder links.
  Result := 0;
  S := BlankStrings(AText);
  p := Pos('nil', S);
  while p > 0 do
  begin
    if IsNilWordAt(S, p) and (NilComparedRight(S, p) or NilComparedLeft(S, p)) then
      Inc(Result);
    p := PosEx('nil', S, p + 3);
  end;
end;

{ ---- SCA126: Operanden ---- }

type
  TNilCompare = record
    NilTok  : TRdxToken;
    OpTok   : TRdxToken;   // '=' bzw. '<>'; Low = '' -> kein Vergleich
    Yoda    : Boolean;
    First   : TRdxToken;   // erstes Token des Operanden
    Last    : TRdxToken;   // letztes Token des Operanden
  end;

  // Ein Schritt beim Lesen eines Operanden nach links.
  TRdxScanStep = (stMore, stDone, stFail);

// Ende einer Klammergruppe ab dem oeffnenden Token (gleiche Klammerart)
// innerhalb von MAX_REGION_LINES; Low = '' wenn nicht gefunden. Seit
// Charge R8 der geteilte MatchClose (uRdxCodeMap).
function MatchForward(AMap: TRdxCodeMap; const AOpen: TRdxToken): TRdxToken;
begin
  Result := MatchClose(AMap, AOpen, MAX_REGION_LINES);
end;

function MatchBackward(AMap: TRdxCodeMap; const AClose: TRdxToken): TRdxToken;
var
  Depth : Integer;
  T     : TRdxToken;
  Open  : string;
begin
  if AClose.Low = ')' then Open := '(' else Open := '[';
  Depth := 0;
  T := AClose;
  while T.Low <> '' do
  begin
    if T.Low = AClose.Low then Inc(Depth)
    else if T.Low = Open then
    begin
      Dec(Depth);
      if Depth = 0 then Exit(T);
    end;
    if T.Line < AClose.Line - MAX_REGION_LINES then Break;
    T := Before(AMap, T);
  end;
  Result := Default(TRdxToken);
end;

function IsOperandWord(const ATok: TRdxToken): Boolean;
begin
  Result := ATok.IsWord and not IsKeyword(ATok.Low);
end;

// Kann hinter ATok eine Aufruf-Klammer folgen ('F(..)', 'A[..](..)',
// '(..)(..)')?
function IsCallable(const ATok: TRdxToken): Boolean;
begin
  Result := IsOperandWord(ATok) or (ATok.Low = ')') or (ATok.Low = ']');
end;

// T steht auf ')' bzw. ']': ueber die Gruppe nach links.
function StepLeftOverGroup(AMap: TRdxCodeMap; var T: TRdxToken;
  var AFirst: TRdxToken): TRdxScanStep;
var
  Open, P : TRdxToken;
begin
  Open := MatchBackward(AMap, T);
  if Open.Low = '' then Exit(stFail);
  P := Before(AMap, Open);
  // '(..)' ohne Namen davor ist eine Gruppe: dort beginnt der Operand.
  if (Open.Low = '(') and not (IsCallable(P) or (P.Low = '^')) then
  begin
    AFirst := Open;
    Exit(stDone);
  end;
  T := P;
  Result := stMore;
end;

// Ein Schritt nach links ueber '^', eine Klammergruppe oder 'Name' bzw.
// '.Name'.
function StepLeft(AMap: TRdxCodeMap; var T: TRdxToken;
  var AFirst: TRdxToken): TRdxScanStep;
var
  P : TRdxToken;
begin
  if T.Low = '^' then
  begin
    T := Before(AMap, T);
    Exit(stMore);
  end;
  if (T.Low = ')') or (T.Low = ']') then
    Exit(StepLeftOverGroup(AMap, T, AFirst));
  if not IsOperandWord(T) then
    Exit(stFail);
  P := Before(AMap, T);
  if P.Low <> '.' then
  begin
    AFirst := T;
    Exit(stDone);
  end;
  T := Before(AMap, P);
  Result := stMore;
end;

// Operand LINKS vom Operator: Bezeichnerkette mit '.', '^', [..], (..).
function OperandBefore(AMap: TRdxCodeMap; const AOp: TRdxToken;
  out AFirst, ALast: TRdxToken): Boolean;
var
  T    : TRdxToken;
  Step : TRdxScanStep;
begin
  ALast := Before(AMap, AOp);
  AFirst := Default(TRdxToken);
  T := ALast;
  repeat
    Step := StepLeft(AMap, T, AFirst);
  until Step <> stMore;
  Result := Step = stDone;
end;

// Ein Suffix rechts von T ('.Name', '^', '[..]', '(..)' hinter Name oder
// Gruppe): T rueckt darauf vor. False = der Operand endet bei T.
function StepRight(AMap: TRdxCodeMap; var T: TRdxToken): Boolean;
var
  N : TRdxToken;
begin
  N := After(AMap, T);
  Result := True;
  if (N.Low = '.') and IsOperandWord(After(AMap, N)) then
    T := After(AMap, N)
  else if N.Low = '^' then
    T := N
  else if (N.Low = '[') or ((N.Low = '(') and IsCallable(T)) then
    T := MatchForward(AMap, N)
  else
    Result := False;
end;

// Operand RECHTS vom Operator (Yoda: nil = X).
function OperandAfter(AMap: TRdxCodeMap; const AOp: TRdxToken;
  out AFirst, ALast: TRdxToken): Boolean;
var
  T     : TRdxToken;
  Moved : Boolean;
begin
  AFirst := After(AMap, AOp);
  ALast := Default(TRdxToken);
  T := AFirst;
  if T.Low = '(' then
    T := MatchForward(AMap, T)
  else if not IsOperandWord(T) then
    Exit(False);
  Moved := True;
  while Moved and (T.Low <> '') do
    Moved := StepRight(AMap, T);
  ALast := T;
  Result := T.Low <> '';
end;

// Ende einer Bedingung: then (if), do (while), of (case).
function IsConditionEnd(const ATok: TRdxToken): Boolean;
begin
  Result := (ATok.Low = 'then') or (ATok.Low = 'do') or (ATok.Low = 'of');
end;

// Ende einer Anweisung: ';' oder end/else/until/except/finally.
function IsStatementEnd(const ATok: TRdxToken): Boolean;
begin
  Result := (ATok.Low = ';') or (ATok.Low = 'end') or (ATok.Low = 'else')
    or (ATok.Low = 'until') or (ATok.Low = 'except') or (ATok.Low = 'finally');
end;

// Darf vor einem Vergleichsglied stehen? Alles andere ('@', 'not' ohne
// Klammer, Rechenzeichen, ein weiterer Vergleich) macht die Grenze des
// Operanden unklar - dann keine Hilfe.
function IsLeftBoundary(const ATok: TRdxToken): Boolean;
begin
  Result := (ATok.Low = '(') or (ATok.Low = ',') or (ATok.Low = '[')
    or (ATok.Low = ':=') or (ATok.Low = 'if') or (ATok.Low = 'while')
    or (ATok.Low = 'case') or (ATok.Low = 'and') or (ATok.Low = 'or')
    or (ATok.Low = 'xor');
end;

// Darf hinter einem Vergleichsglied stehen?
function IsRightBoundary(const ATok: TRdxToken): Boolean;
begin
  Result := (ATok.Low = ')') or (ATok.Low = ',') or (ATok.Low = ']')
    or (ATok.Low = 'and') or (ATok.Low = 'or') or (ATok.Low = 'xor')
    or IsConditionEnd(ATok) or IsStatementEnd(ATok);
end;

// Text zwischen zwei Tokens derselben Zeile (Rohtext).
function TextBetween(AMap: TRdxCodeMap; const AFirst, ALast: TRdxToken): string;
begin
  Result := Copy(AMap.Raw(AFirst.Line), AFirst.Col, ALast.EndCol - AFirst.Col);
end;

// Ohne Leerraum, klein - fuer den Vergleich mit dem Bereichstext.
function Squeezed(const AText: string): string;
begin
  Result := LowerCase(StringReplace(StringReplace(AText, ' ', '',
    [rfReplaceAll]), #9, '', [rfReplaceAll]));
end;

{ ---- SCA126: die Anweisung lesen ---- }

type
  // Was NilComparison ueber die Anweisung sammelt.
  TNilScan = record
    StartTok : TRdxToken;
    EndTok   : TRdxToken;
    Cmps     : TArray<TNilCompare>;
    Count    : Integer;   // belegte Eintraege in Cmps
    Region   : string;    // Tokens ohne Leerraum, klein (SCA084-Probe)
  end;

  // Ein Vergleich als Ersetzung.
  TNilSpan = record
    First   : TRdxToken;
    Last    : TRdxToken;
    NewText : string;
  end;

// Beginnt an ASite noch die gemeldete Anweisung (Code; bei einer
// Bedingung das Schluesselwort if/while/case)?
function StartsStatement(AMap: TRdxCodeMap; const ASite: TRdxNilSite): Boolean;
var
  Low : string;
begin
  if not AMap.IsCode(ASite.Line, ASite.Col) then Exit(False);
  if ASite.Anchor <> naCondition then Exit(True);
  Low := TokenAt(AMap, ASite.Line, ASite.Col).Low;
  Result := (Low = 'if') or (Low = 'while') or (Low = 'case');
end;

// Endet der Bereich bei T (auf Klammertiefe 0)? Bedingung bis
// then/do/of, Anweisung bis ';' oder end/else/until/except/finally.
function IsRegionEnd(const T: TRdxToken; AAnchor: TRdxNilAnchor): Boolean;
begin
  if AAnchor = naCondition then
    Result := IsConditionEnd(T)
  else
    Result := IsStatementEnd(T);
end;

function DepthDelta(const T: TRdxToken): Integer;
begin
  if (T.Low = '(') or (T.Low = '[') then
    Result := 1
  else if (T.Low = ')') or (T.Low = ']') then
    Result := -1
  else
    Result := 0;
end;

// Ein 'nil' im Bereich: ein Vergleich (ACmp.OpTok gesetzt), keiner
// (ACmp.OpTok.Low = '', etwa nil als Argument) - '' - oder ein Grund.
function ReadComparison(AMap: TRdxCodeMap; const ANil: TRdxToken;
  out ACmp: TNilCompare): string;
var
  Prev : TRdxToken;
begin
  Result := '';
  ACmp := Default(TNilCompare);
  ACmp.NilTok := ANil;
  Prev := Before(AMap, ANil);
  if (Prev.Low = '=') or (Prev.Low = '<>') then
  begin
    ACmp.OpTok := Prev;
    if not OperandBefore(AMap, Prev, ACmp.First, ACmp.Last) then
      Result := 'Operand vor dem Vergleich nicht eindeutig';
    Exit;
  end;
  ACmp.OpTok := After(AMap, ANil);
  if (ACmp.OpTok.Low <> '=') and (ACmp.OpTok.Low <> '<>') then
  begin
    ACmp.OpTok := Default(TRdxToken);
    Exit;
  end;
  ACmp.Yoda := True;
  if not OperandAfter(AMap, ACmp.OpTok, ACmp.First, ACmp.Last) then
    Result := 'Operand hinter dem Vergleich nicht eindeutig';
end;

// Ein Token des Bereichs aufnehmen: Vergleiche sammeln, anonyme Methoden
// sperren (dort mischen sich Anweisungen in den Ausdruck). '' oder Grund.
function TakeToken(AMap: TRdxCodeMap; const T: TRdxToken;
  var AScan: TNilScan): string;
var
  C : TNilCompare;
begin
  Result := '';
  if T.Low = 'begin' then
    Exit('anonyme Methode in der Anweisung');
  if T.Low <> 'nil' then Exit;
  Result := ReadComparison(AMap, T, C);
  if (Result <> '') or (C.OpTok.Low = '') then Exit;
  if AScan.Count = Length(AScan.Cmps) then
    SetLength(AScan.Cmps, 2 * AScan.Count + 4);
  AScan.Cmps[AScan.Count] := C;
  Inc(AScan.Count);
end;

// Den Bereich der Anweisung ab ASite lesen. '' oder der Grund.
function ScanStatement(AMap: TRdxCodeMap; const ASite: TRdxNilSite;
  out AScan: TNilScan): string;
var
  T     : TRdxToken;
  Depth : Integer;
  SB    : TStringBuilder;
begin
  Result := '';
  AScan := Default(TNilScan);
  AScan.StartTok := TokenAt(AMap, ASite.Line, ASite.Col);
  T := AScan.StartTok;
  if ASite.Anchor = naCondition then
    T := After(AMap, T);   // das Schluesselwort if/while/case selbst
  Depth := 0;
  SB := TStringBuilder.Create;
  try
    while (T.Low <> '') and (T.Line <= ASite.Line + MAX_REGION_LINES) do
    begin
      SB.Append(T.Low);
      if (Depth = 0) and IsRegionEnd(T, ASite.Anchor) then
      begin
        AScan.EndTok := T;
        Break;
      end;
      Inc(Depth, DepthDelta(T));
      Result := TakeToken(AMap, T, AScan);
      if Result <> '' then Exit;
      T := After(AMap, T);
    end;
    AScan.Region := SB.ToString;
  finally
    SB.Free;
  end;
  SetLength(AScan.Cmps, AScan.Count);
  if AScan.EndTok.Low = '' then
    Result := 'Ende der Anweisung nicht gefunden';
end;

// Kommentar oder Direktive im Bereich AFirst..ALast? Der Detektor sieht
// sie nicht, eine Ersetzung koennte sie zerreissen.
function RegionHasComment(AMap: TRdxCodeMap; const AFirst, ALast: TRdxToken): Boolean;
var
  i : Integer;
begin
  if AFirst.Line = ALast.Line then
    Exit(AMap.HasComment(AFirst.Line, AFirst.Col, ALast.Col));
  Result := False;
  for i := AFirst.Line to ALast.Line do
    if AMap.HasComment(i, 1, Length(AMap.Raw(i))) then
      Exit(True);
end;

// Steht ATok vor einer Klammer, ist sie sicher eine Gruppe und kein
// Aufruf: wo ein Vergleichsglied beginnen darf, hinter '=' / '<>' und hinter
// dem Ende einer Bedingung oder Anweisung (then, else, until ...). NICHT
// nach einem Namen, ')', ']', '>' (From<T>(..)), '^' oder '&Do' - dort ist
// es eine Aufrufklammer.
function IsGroupContext(const ATok: TRdxToken): Boolean;
begin
  Result := IsLeftBoundary(ATok) or (ATok.Low = '=') or (ATok.Low = '<>')
    or IsConditionEnd(ATok) or IsStatementEnd(ATok);
end;

// Eine Klammer, die GENAU den Vergleich umschliesst, geht mit:
//   not (X = nil)  -> Assigned(X)        not (X <> nil) -> not Assigned(X)
//   (X <> nil) and -> Assigned(X) and    (nur als Gruppe, IsGroupContext)
// Folgt der Klammer '.', '[', '^' oder '(', gehoert sie zum Ausdruck
// dahinter - 'not (X = nil).ToInteger' ist not((X = nil).ToInteger): dann
// geht weder die Klammer noch das 'not' mit.
// AFlipped ist ASpan.NewText mit umgekehrter Bedeutung - das, was mit dem
// 'not' davor herauskommt.
procedure WidenOverGroup(AMap: TRdxCodeMap; const AFlipped: string;
  var ASpan: TNilSpan);
var
  OpenT, CloseT, Outer, Behind : TRdxToken;
begin
  OpenT  := Before(AMap, ASpan.First);
  CloseT := After(AMap, ASpan.Last);
  if (OpenT.Low <> '(') or (CloseT.Low <> ')') or (OpenT.Line <> CloseT.Line)
     or (OpenT.Line <> ASpan.First.Line) then
    Exit;
  Behind := After(AMap, CloseT);
  if (Behind.Low = '.') or (Behind.Low = '[') or (Behind.Low = '^')
     or (Behind.Low = '(') then
    Exit;
  Outer := Before(AMap, OpenT);
  if (Outer.Low = 'not') and (Outer.Line = OpenT.Line) then
  begin
    ASpan.First   := Outer;
    ASpan.Last    := CloseT;
    ASpan.NewText := AFlipped;
  end
  else if IsGroupContext(Outer) then
  begin
    ASpan.First := OpenT;
    ASpan.Last  := CloseT;
  end;
end;

// Die Ersetzung fuer einen Vergleich. '' oder der Grund.
function PlanComparison(AMap: TRdxCodeMap; const ACmp: TNilCompare;
  const ARegion: string; out AEdit: TRdxEdit; out AOperand: string): string;
var
  Span     : TNilSpan;
  Positive : Boolean;
  Flipped  : string;
begin
  AEdit := Default(TRdxEdit);
  AOperand := '';
  if ACmp.First.Line <> ACmp.Last.Line then
    Exit('Operand ueber mehrere Zeilen');
  AOperand := TextBetween(AMap, ACmp.First, ACmp.Last);
  // Schon Assigned(X) in derselben Anweisung: das ist SCA084
  // (AssignedAndAssignedNil) - dessen Hilfe statt 'Assigned(X) and Assigned(X)'.
  if Pos('assigned(' + Squeezed(AOperand) + ')', ARegion) > 0 then
    Exit('Assigned(X) steht schon in der Anweisung (SCA084)');
  Positive := ACmp.OpTok.Low = '<>';
  Span := Default(TNilSpan);
  if ACmp.Yoda then
  begin
    Span.First := ACmp.NilTok;
    Span.Last  := ACmp.Last;
  end
  else
  begin
    Span.First := ACmp.First;
    Span.Last  := ACmp.NilTok;
  end;
  if Span.First.Line <> Span.Last.Line then
    Exit('Vergleich ueber mehrere Zeilen');
  if not IsLeftBoundary(Before(AMap, Span.First))
     or not IsRightBoundary(After(AMap, Span.Last)) then
    Exit(Format('Grenze des Vergleichs unklar ("%s %s ... %s")',
      [Before(AMap, Span.First).Low, Span.First.Low, After(AMap, Span.Last).Low]));
  // '<>' -> Assigned(X), '=' -> not Assigned(X); Flipped ist das Gegenteil.
  Span.NewText := 'Assigned(' + AOperand + ')';
  Flipped := NOT_PREFIX + Span.NewText;
  if not Positive then
  begin
    Flipped := Span.NewText;
    Span.NewText := NOT_PREFIX + Span.NewText;
  end;
  WidenOverGroup(AMap, Flipped, Span);
  AEdit.Span := TRefactorSpan.Make(SPAN_126, Span.First.Line, Span.First.Col,
    Span.Last.Line, Span.Last.EndCol);
  AEdit.Expected := Copy(AMap.Raw(Span.First.Line), Span.First.Col,
    Span.Last.EndCol - Span.First.Col);
  AEdit.NewText  := Span.NewText;
  Result := '';
end;

// Passt die Zahl der Vergleiche im Code zu der im Knotentext? Eine
// ungerade Zahl von Quotes im Knotentext heisst: der Parser hat ein
// Literal mit Quote nicht verdoppelt (ParseIfStmt: 'C = ''''' wird
// ''''') - dahinter blendet BlankStrings alles aus, der Knoten zaehlt zu
// wenig. Dann genuegt: der Code hat mindestens so viele.
function CountMatches(ACode, ANode: Integer; const ANodeText: string): Boolean;
var
  i, Quotes : Integer;
begin
  Quotes := 0;
  for i := 1 to Length(ANodeText) do
    if ANodeText[i] = '''' then Inc(Quotes);
  if Odd(Quotes) then
    Result := ACode >= ANode
  else
    Result := ACode = ANode;
end;

// Die Anweisung an ASite lesen und gegen den Fund pruefen. '' oder Grund.
function ReadStatement(AMap: TRdxCodeMap; const ASite: TRdxNilSite;
  out AScan: TNilScan): string;
var
  Expected : Integer;
begin
  AScan := Default(TNilScan);
  Expected := TRdxNilFix.CountNilComparisons(ASite.NodeText);
  if Expected = 0 then
    Exit('kein nil-Vergleich im Fund');
  if not StartsStatement(AMap, ASite) then
    Exit('Anweisung steht nicht mehr an der gemeldeten Stelle');
  Result := ScanStatement(AMap, ASite, AScan);
  if Result <> '' then Exit;
  if not CountMatches(Length(AScan.Cmps), Expected, ASite.NodeText) then
    Exit(Format('Code und Fund passen nicht zusammen (%d statt %d Vergleiche)',
      [Length(AScan.Cmps), Expected]));
  if RegionHasComment(AMap, AScan.StartTok, AScan.EndTok) then
    Result := 'Kommentar oder Direktive in der Anweisung';
end;

// Zwei einzeilige Bereiche ueberschneiden sich?
function SpansOverlap(const A, B: TRefactorSpan): Boolean;
begin
  Result := (A.StartLine = B.StartLine) and (A.StartCol < B.EndCol)
    and (B.StartCol < A.EndCol);
end;

// Alle Vergleiche planen; verschachtelte ('Find(X = nil) = nil') ergaeben
// ueberlappende Ersetzungen - die Hilfe waere aktiv und scheiterte erst
// beim Klick. '' oder Grund.
function PlanAll(AMap: TRdxCodeMap; const AScan: TNilScan;
  var APlan: TRdxNilPlan): string;
var
  i, k : Integer;
begin
  SetLength(APlan.Edits, Length(AScan.Cmps));
  SetLength(APlan.Operands, Length(AScan.Cmps));
  for i := 0 to High(AScan.Cmps) do
  begin
    Result := PlanComparison(AMap, AScan.Cmps[i], AScan.Region,
      APlan.Edits[i], APlan.Operands[i]);
    if Result <> '' then Exit;
    for k := 0 to i - 1 do
      if SpansOverlap(APlan.Edits[k].Span, APlan.Edits[i].Span) then
        Exit('verschachtelte nil-Vergleiche');
  end;
  Result := '';
end;

class function TRdxNilFix.NilComparison(AMap: TRdxCodeMap;
  const ASite: TRdxNilSite; out APlan: TRdxNilPlan): Boolean;
var
  Scan : TNilScan;
begin
  APlan := Default(TRdxNilPlan);
  APlan.Reason := ReadStatement(AMap, ASite, Scan);
  if APlan.Reason = '' then
    APlan.Reason := PlanAll(AMap, Scan, APlan);
  Result := APlan.Reason = '';
  if not Result then
  begin
    APlan.Edits := nil;
    APlan.Operands := nil;
  end;
end;

{ ---- SCA126: Operanden-Pruefung ---- }

// Letzter Bezeichner, wenn AText mit einem endet ('Self.FOnChange' ->
// 'FOnChange'); '' bei ')', ']' oder '^' am Ende - dort wird ein Ergebnis
// verglichen, kein blosser Bezeichner.
function TrailingIdent(const AText: string): string;
var
  i : Integer;
  S : string;
begin
  S := TrimRight(AText);
  i := Length(S);
  while (i >= 1) and IsIdentChar(S[i]) do
    Dec(i);
  Result := Copy(S, i + 1, MaxInt);
  if (Result <> '') and not IsIdentStart(Result[1]) then
    Result := '';
end;

class function TRdxNilFix.NilOperandRisk(const AOperand,
  ATypeLow: string): string;
const
  // Genau diese Namen; Prozedurtypen dazu ueber NamesProcType.
  RISKY_TYPES: array[0..10] of string = (
    'string', 'ansistring', 'unicodestring', 'widestring', 'shortstring',
    'rawbytestring', 'utf8string', 'variant', 'olevariant', 'array', 'set');
  TYPE_RISK = '%s ist vom Typ %s - Assigned() ist dafuer nicht sicher gleichwertig';
var
  Ident : string;
begin
  Result := '';
  Ident := TrailingIdent(AOperand);
  if (Ident <> '') and (HasCapPrefix(Ident, 'On') or HasCapPrefix(Ident, 'FOn')
     or HasCapPrefix(Ident, 'Get')) then
    Exit(Format('%s sieht nach Ereignis oder Funktion aus - Assigned() prueft '
      + 'dann den Zeiger, nicht das Ergebnis', [Ident]));
  if ATypeLow = '' then Exit;
  if InList(ATypeLow, RISKY_TYPES) or NamesProcType(ATypeLow) then
    Result := Format(TYPE_RISK, [AOperand, ATypeLow]);
end;

{ ---- SCA126: Felder der Datei (FieldTypeOf) ---- }

type
  // Zustand der Feldsuche: offene Typruempfe, Klammern darin, der Typ des
  // ersten Treffers und ob ein zweiter davon abweicht.
  TFieldScan = record
    Body  : Integer;
    Paren : Integer;
    Found : string;
    Multi : Boolean;
  end;

const
  // Vor dem Namen eines Feldes auf Klammertiefe 0 eines Typrumpfs: ';',
  // ',' (Feldgruppe 'FA, FB: T'), ein Sichtbarkeitswort, 'var' (class var,
  // var-Abschnitt der Klasse), das Rumpfwort selbst (erstes Feld), ')'
  // hinter den Vorfahren, ']' hinter einem Attribut. NICHT function/
  // procedure/property/const - deren Name traegt ebenfalls einen ':'.
  FIELD_PREV: array[0..12] of string = (';', ',', 'private', 'protected',
    'public', 'published', 'automated', 'var', 'class', 'record', 'object',
    ')', ']');
  TYPE_BODY_WORDS: array[0..3] of string = ('class', 'object', 'interface',
    'dispinterface');

// Oeffnet T einen Typrumpf mit eigenem 'end'? 'record' immer - ausser als
// generische Einschraenkung ('<T: record>': dahinter '>', ',', ';' oder
// ')'); class/object/interface/dispinterface nur hinter '=' oder 'packed'
// und nicht als Vorwaertsdeklaration ('class;'), Metaklasse ('class of')
// oder Kurzform ('class(TBar);'). Das 'interface' der Unit steht nie
// hinter '='.
function OpensTypeBody(AMap: TRdxCodeMap; const T, APrev: TRdxToken): Boolean;
var
  N : TRdxToken;
begin
  if InList(APrev.Low, IDENT_PREFIXES) then Exit(False);
  if T.Low = 'record' then
    Exit(not InList(After(AMap, T).Low, ['>', ',', ';', ')']));
  if not InList(T.Low, TYPE_BODY_WORDS)
     or not InList(APrev.Low, ['=', 'packed']) then
    Exit(False);
  N := After(AMap, T);
  while InList(N.Low, ['abstract', 'sealed']) do
    N := After(AMap, N);
  if N.Low = '(' then
  begin
    N := MatchForward(AMap, N);
    if N.Low = '' then Exit(False);
    N := After(AMap, N);
  end;
  Result := not InList(N.Low, [';', 'of']);
end;

// Das ':' hinter dem Feldnamen AName - auch hinter den Nachbarn einer
// Feldgruppe ('FA, FB: T' fuer FA); Low = '' ohne ':'.
function GroupColon(AMap: TRdxCodeMap; const AName: TRdxToken): TRdxToken;
begin
  Result := After(AMap, AName);
  while (Result.Low = ',') and After(AMap, Result).IsWord do
    Result := After(AMap, After(AMap, Result));
  if Result.Low <> ':' then
    Result := Default(TRdxToken);
end;

// Der Typ hinter dem ':' AColon als Wort fuer die Typpruefungen (s.
// FieldTypeOf): qualifiziert das letzte Glied, generisch der Name vor '<'.
// Ein zweiter Treffer mit anderem Typ macht das Ergebnis mehrdeutig.
procedure TakeFieldType(AMap: TRdxCodeMap; const AColon: TRdxToken;
  var AScan: TFieldScan);
var
  K : TRdxToken;
begin
  K := After(AMap, AColon);
  while (K.Low <> '') and (After(AMap, K).Low = '.') do
    K := After(AMap, After(AMap, K));
  if K.Low = '' then Exit;
  if AScan.Found = '' then
    AScan.Found := K.Low
  else if AScan.Found <> K.Low then
    AScan.Multi := True;
end;

// Ein Token der Feldsuche: Ruempfe und Klammern zaehlen; auf Klammertiefe 0
// eines Rumpfs ist ein Wort ANameLow mit ':' dahinter (GroupColon) und
// FIELD_PREV davor ein Feld. Ein 'begin' oder 'implementation' in einem
// Rumpf gibt es nicht - dort ist die Bilanz verloren (etwa durch ein
// ungezaehltes end), und die Suche faengt ausserhalb neu an, statt lokale
// Variablen als Felder zu lesen.
procedure FieldScanStep(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  const ANameLow: string; var AScan: TFieldScan);
var
  IsWord : Boolean;   // nicht 'Word': verdeckte System.Word (Gegen-Review R8)
  Colon  : TRdxToken;
begin
  IsWord := not InList(APrev.Low, IDENT_PREFIXES);
  if OpensTypeBody(AMap, T, APrev) then
    Inc(AScan.Body)
  else if IsWord and ((T.Low = 'begin') or (T.Low = 'implementation')) then
    AScan.Body := 0
  else if AScan.Body = 0 then
    Exit
  else if IsWord and (T.Low = 'end') then
  begin
    Dec(AScan.Body);
    AScan.Paren := 0;
  end
  else if T.Low = '(' then
    Inc(AScan.Paren)
  else if T.Low = ')' then
    Dec(AScan.Paren)
  else if (AScan.Paren = 0) and (T.Low = ANameLow)
     and InList(APrev.Low, FIELD_PREV) then
  begin
    Colon := GroupColon(AMap, T);
    if Colon.Low = ':' then
      TakeFieldType(AMap, Colon, AScan);
  end;
end;

class function TRdxSimpleFixes.FieldTypeOf(AMap: TRdxCodeMap;
  const AName: string): string;
var
  T, Prev : TRdxToken;
  Scan    : TFieldScan;
  NameLow : string;   // nicht 'Low': verdeckte System.Low (Gegen-Review R8)
begin
  Result := '';
  NameLow := LowerCase(AName);
  if NameLow = '' then Exit;
  Scan := Default(TFieldScan);
  Prev := Default(TRdxToken);
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    FieldScanStep(AMap, T, Prev, NameLow, Scan);
    Prev := T;
    T := After(AMap, T);
  end;
  if not Scan.Multi then
    Result := Scan.Found;
end;

class function TRdxNilFix.NilOperandReason(AMap: TRdxCodeMap;
  const AOperand, ATypeLow: string): string;
const
  R_TYPE_UNKNOWN = 'Typ von %s nicht bewiesen - einen Funktions- oder '
    + 'Methodenzeiger riefe "= nil" auf, Assigned() nicht';
  R_PATH_END     = '%s endet auf %s - in dieser Unit nicht als Feld bewiesen: '
    + 'eine Methode ohne Argumente riefe "= nil" auf, Assigned() pruefte nur '
    + 'den Methodenzeiger';
  R_PROC_IN_UNIT = '%s hat den Prozedurtyp %s (in dieser Unit deklariert) - '
    + '"= nil" ruft ihn auf, Assigned() nicht';
  R_NOT_PROVEN   = '%s: Typ %s ist in dieser Unit nicht als Klasse, Interface '
    + 'oder Zeiger bewiesen und keine Klasse der Delphi-Quellen - einen '
    + 'Funktionstyp einer anderen Unit riefe "= nil" auf, Assigned() nicht';
var
  TypeLow : string;
  Ident   : string;
begin
  Result := NilOperandRisk(AOperand, ATypeLow);
  if Result <> '' then Exit;
  TypeLow := ATypeLow;
  if TypeLow = '' then
  begin
    Ident := TrailingIdent(AOperand);
    // ')', ']', '^': ein Ergebnis wird verglichen - BEWUSSTE LUECKE
    // (Gegen-Review R8, Verdacht im Bestand): 'FItems[I] = nil' oder
    // 'TFoo(Sender) = nil' umgehen den Typbeweis ganz, weil das Ergebnis
    // keinen deklarierten Namen hat - ein Element eines Arrays von
    // Funktionszeigern oder ein Cast auf einen Funktionstyp ginge durch.
    // Nicht geschlossen: der Entscheid steht aus (Nico; Messung Charge
    // R9). uTestRdxNilFix.Sca126_PathOperands pinnt den Bestand.
    if Ident = '' then Exit;
    if Ident = Trim(AOperand) then
      Exit(Format(R_TYPE_UNKNOWN, [AOperand]));
    TypeLow := TRdxSimpleFixes.FieldTypeOf(AMap, Ident);
    if TypeLow = '' then
      Exit(Format(R_PATH_END, [AOperand, Ident]));
    Result := NilOperandRisk(AOperand, TypeLow);
    if Result <> '' then Exit;
  end;
  if TRdxExprFixes.ProceduralType(AMap, TypeLow) then
    Exit(Format(R_PROC_IN_UNIT, [AOperand, TypeLow]));
  // Der POSITIVE Beweis wie bei SCA084 (AssignedNilReason in
  // uRdxRecipeRunner, der OperandReason-Pfad von TRdxFixRunner.OperandFix -
  // nicht in dieser Unit): ein Typ aus
  // einer anderen Unit mit unauffaelligem Namen ('uses uFactories; FMaker:
  // TObjFactory' mit 'function: TObject' dort) ging bis Charge R8 durch -
  // 'if FMaker = nil' wurde 'if not Assigned(FMaker)', ein anderer Sinn.
  // Das kostet Angebote bei Fremdtypen und gewinnt Sicherheit (Semantik-
  // Gegen-Review 2026-10-14, Major). Seit E27 (Charge R10) zaehlen die
  // Klassen und Interfaces der Delphi-Quellen als bewiesen (uRdxRtlTypes,
  // in PointerLikeType) - Kundentypen bleiben draussen.
  if not TRdxExprFixes.PointerLikeType(AMap, TypeLow) then
    Result := Format(R_NOT_PROVEN, [AOperand, TypeLow]);
end;

end.

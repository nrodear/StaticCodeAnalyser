unit uRdxSimpleFixes;

// reDelphix - die Planer der einfachen Editorhilfen
// (Konzept_Editorhilfen_2026-10-08). Stufe 2a (Nico 2026-10-09): SCA075
// class(TObject) -> class, SCA085 Free/nil -> FreeAndNil, SCA126 X = nil
// -> not Assigned(X); Stufe 2, Rest (2026-10-10): SCA074 Assert-Meldung,
// SCA087 leerer Sichtbarkeitsabschnitt, SCA139 X.Free -> FreeAndNil(X);
// uQuickFix-Umzug (2026-10-10, TRdxExprFixes): SCA066 leere Klammern,
// SCA072 Vergleich mit True/False, SCA084 Assigned + nil. OHNE ToolsAPI:
// aus den Zeilen der Datei werden gepruefte Ersetzungen (TRdxEdit), die
// uRdxEditor.ReplaceSpans in EINEM Undo-Schritt schreibt.
//
// TYPBEWEIS: steht seit der Folgewelle A4 des Wochen-Reviews (G07-04,
// G07-20) in uRdxTypeProof (TRdxTypeProof) - bis dahin hier, verteilt
// auf TRdxSimpleFixes und TRdxExprFixes, die sich dafuer gegenseitig
// riefen. Die Planer hier (SCA066, SCA126) fragen ihn wie der Laeufer.
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
// Nutzer erfaehrt ihn trotzdem: der Hint der Hilfe (uRdxFixRunner,
// R_FREENIL_HINT) nennt die Reihenfolge.
//
// TEXTE (Entscheid E29, Charge G1): jeder Grund ist eine englische msgid,
// uebersetzt mit uRdxText._ in die Sprache der SCA-Oberflaeche; die
// deutsche Fassung (der bisherige Wortlaut) steht in i18n/de.po. Gemeinsame
// Texte kommen aus uRdxText - "<Code> steht nicht mehr an der gemeldeten
// Stelle" ist MsgNoLongerAtReportedPlace mit dem Code-Stueck ('Assert(',
// 'X.Free;') als Argument. Code-Token und Typnamen stehen als %s im Satz.

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

  // SCA085/SCA139: was der Text ueber einen Namen beweist
  // (TRdxSimpleFixes.VariableProof): nichts, Parameter/lokale Variable/
  // Result einer umschliessenden Routine, Feld der eigenen Klasse, Variable
  // auf Unit-Ebene.
  TRdxVarProofKind = (vpNone, vpLocal, vpField, vpGlobal);

  TRdxVarProof = record
    Kind    : TRdxVarProofKind;
    TypeLow : string;   // der deklarierte Typ, klein ('' = untypisiert)
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

    // True, wenn ALine im Rumpf eines 'with' liegt (TRdxTypeProof.
    // InWithBody ab dem ersten Code-Token der Zeile) oder auf ALine selbst
    // ein 'with' steht - ein Name kann dort ein Member des with-Ausdrucks
    // sein. Bis zum Realwelt-Test rwE30 sperrte jedes 'with' vor der Zeile
    // in der Routine, auch eines, dessen Rumpf laengst zu Ende war, und eines
    // in einer verschachtelten Routine davor (uPSCompiler.pas, CheckFurther:
    // 40 unnoetige SCA085-Sperren). Der Name bleibt - die Aufrufer im Laeufer
    // fragen weiter "with um die Zeile?".
    class function WithBefore(AMap: TRdxCodeMap; ALine: Integer): Boolean; static;
    // SCA085/SCA139 (rwE30): ist AName an ALine nach dem Text eine Variable?
    // vpLocal: Parameter, lokale Variable oder Result einer umschliessenden
    // Routine, auch einer verschachtelten (TRdxTypeProof.LocalBinding - der
    // Quellstellen-Dienst kennt verschachtelte Routinen nicht); sie
    // verdeckt eine gleichnamige Property der Unit. Sonst, wenn keine
    // umschliessende Routine den Namen deklariert: vpField, ein Feld der
    // Klasse der aeussersten Methode (OwnFieldType - auch aus einer
    // verschachtelten Routine, auch in einem bedingten Abschnitt); vpGlobal,
    // eine Variable auf Unit-Ebene (UnitVarType, auch threadvar und 'X: T =
    // nil') - in einer Methode nur, wenn die Unit kein Feld, keine Property
    // und keine Routine dieses Namens deklariert und die Klasse nicht von
    // einer Klasse der Delphi-Quellen erbt (ein geerbtes Member verdeckte das
    // Global; Pin missed R2(3)). GRENZE: eine fremde Kundenklasse als
    // Vorfahr koennte ein gleichnamiges Member tragen - der Code 'X.Free'
    // meinte dann dieses, FreeAndNil(X) ebenso (Feld) bzw. scheitert beim
    // Uebersetzen (Property). with prueft der Aufrufer vorher (WithBefore).
    // Seit rwE31 mit AUnitFile (die Datei von AMap, '' = unbekannt) auch
    // vpGlobal, wenn diese Unit den Namen gar nicht deklariert und eine
    // Unit ihrer uses-Klauseln NEBEN der Datei ihn im interface-Teil als
    // Variable deklariert (TRdxTypeProof.NeighbourVarType; HeidiSQL
    // main.pas:2778 'frmPreferences' aus preferences.pas) - dieselben
    // Bedingungen wie fuer ein Global dieser Unit.
    class function VariableProof(AMap: TRdxCodeMap; ALine: Integer;
      const AName: string;
      const AUnitFile: string = ''): TRdxVarProof; static;
    // True, wenn in der Routine um ALine vor dieser Zeile 'var AName :='
    // steht: eine Inline-Variable ohne Typangabe, die DeclaredTypeOf nicht
    // kennt.
    class function DeclaresInlineVar(AMap: TRdxCodeMap; ALine: Integer;
      const AName: string): Boolean; static;
    // SCA085/SCA139 (rwE33 Stufe 5, Dev-Cpp InstallWizards.pas:684): die
    // Aufrufe von AName im Code, die sicher die Routine auf Unit-Ebene
    // meinen, in Textreihenfolge - unqualifiziert (kein '.' und kein
    // 'inherited' davor), mit '(' dahinter, nicht im Rumpf eines with und
    // nicht auf einer Zeile mit 'with' (WithBefore: AName koennte dort ein
    // Member sein). Kommentare, Strings und Direktiven tragen keine Token.
    // Leer, wenn die Datei selbst eine Routine AName deklariert
    // (DeclaresRoutine, auch als Methode) oder AName irgendwo im Code vor
    // ':', '=', ',' bzw. ':=' steht (Feld, Variable, Parameter, Property,
    // Konstante 'FreeAndNil: procedure(..)' - Review e/HilfeFixU, MINOR 2):
    // ein Aufruf bewiese dann nichts. Ob der Aufruf dort uebersetzt wird,
    // wo er gebraucht wird, prueft der Aufrufer (TRdxPlacesRunner.
    // CoveringPlace), ob er dasselbe bindet wie die Stelle CallsBindingAt.
    class function UnqualifiedCalls(AMap: TRdxCodeMap;
      const AName: string): TArray<TRdxToken>; static;
    // Die Aufrufe aus UnqualifiedCalls, die AName so binden wie die Stelle
    // ALine (Review e/HilfeFixU, MINOR 1): keine umschliessende Routine
    // deklariert AName (TRdxTypeProof.LocalBinding = lkNone, am Aufruf und
    // an ALine), und der Aufruf steht in einer freien Routine bzw. auf
    // Unit-Ebene oder in einer Methode DERSELBEN Klasse wie ALine (Klasse
    // aus dem Kopf der aeussersten Routine, 'procedure TKlasse.X'). Ein
    // Aufruf in einer Methode von TA kann ein geerbtes oder Helper-Member
    // FreeAndNil einer fremden Unit meinen - an einer Stelle in einer freien
    // Routine oder in TB fehlte es (E2003). Die Gegenrichtung (Aufruf frei,
    // Stelle in einer Methode) bleibt: dort riefe auch die uses-Ergaenzung
    // das Member. GRENZE: ein fremdes Member AName der Klasse der Stelle
    // sieht der Text nicht (wie vorher mit uses-Ergaenzung).
    class function CallsBindingAt(AMap: TRdxCodeMap; const AName: string;
      ALine: Integer): TArray<TRdxToken>; static;

    // ---- Editorhilfen Stufe 2, Rest (Nico 2026-10-10: "baue weitere") ----

    // SCA074: 'Assert(c)' an der Spalte aus der Meldung ('at column N') ->
    // 'Assert(c, ''c'')' - die Bedingung als Meldung. Nur, wenn die Klammer
    // auf derselben Zeile schliesst, kein Komma auf oberster Ebene und
    // kein Kommentar darin steht und es nicht 'Obj.Assert' ist; ein
    // Literal traegt hoechstens 255 Zeichen (E2056).
    class function AssertMessage(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

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
    // als Zeiger gelten - keine Hilfe, ebenso in der eigenen Funktion.
    // PROPERTY MIT PROZEDURTYP (Review R3-02, Charge FC): dass Delphi eine
    // VARIABLE mit Prozedurtyp ohne () aufruft, belegen DocWiki (Procedural
    // Types) und RTL ('FProc;' in System.Threading); fuer eine Property -
    // gelesen ueber ein Feld oder einen Getter, 'reference to' oder 'of
    // object' - fehlt der Beleg (FPC -Mdelphi ruft sie auf, Delphi 12 ist
    // ungeprueft). Darum keine Hilfe bei einem Namen, den die Unit als
    // Property deklariert (auch hinter einem Pfad: 'Dlg.RefProc()') oder der
    // wie ein Ereignis heisst ('OnIdle()', 'FOnIdle()'): ob Feld oder
    // Property, sieht der Planer ohne Typ nicht - ein Feld riefe Delphi
    // ohne () auf (im Korpus ab8 sind alle 14 Sperren dieser Art Felder,
    // 'FOnChange()'), dort ist die Sperre nur vorsichtig. GRENZE: eine
    // Property einer anderen Unit mit unauffaelligem Namen sieht das nicht;
    // das klaert erst eine Delphi-12-Probe ('Obj.Prop;' je Feld/Getter und
    // reference to/of object). Ob ein blosser Name eine Variable ist,
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
    // (APlan.Name, TRdxTypeProof.PointerLikeType).
    class function AssignedNil(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxOperandEdit;
      out AReason: string): Boolean; static;
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
    //     function: TObject', auch ueber Alias; TRdxTypeProof.
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
  System.SysUtils, System.StrUtils,   // PosEx, ContainsText
  uRefactorInfo,
  uRdxTypeProof,   // der Typbeweis (SCA066 DeclaresProperty, SCA126)
  uRdxText;        // _(), Msg...: in die reDelphix-Sprache, nie uLocalization (E29)

const
  MAX_REGION_LINES = 25;
  SPAN_075 = 'sca075';
  SPAN_085 = 'sca085';
  SPAN_126 = 'sca126';
  SPAN_074 = 'sca074';
  SPAN_087 = 'sca087';
  SPAN_139 = 'sca139';
  // Dahinter ist ein Name deklariert oder zugewiesen, nicht aufgerufen
  // (UnqualifiedCalls).
  DECL_AFTER: array[0..3] of string = (':', '=', ',', ':=');
  // Die Code-Stuecke der Gruende "<Code> steht nicht mehr an der gemeldeten
  // Stelle" (MsgNoLongerAtReportedPlace, uRdxText) - Quelltext, keine
  // Uebersetzung.
  CODE_ASSERT   = 'Assert(';
  CODE_TOBJECT  = 'class(TObject)';
  CODE_ARGS     = '()';
  CODE_FREE     = 'X.Free;';
  CODE_ASSIGNED = 'Assigned(X)';
  // Ein String-Literal traegt bis Delphi 11 hoechstens 255 Zeichen (E2056;
  // Delphi 12 erlaubt mehr) - die Unit kann auch aelter uebersetzt werden.
  // Die Quotes und verdoppelten Apostrophe zaehlen hier mit - vorsichtig.
  MAX_ASSERT_LITERAL = 255;
  NOT_PREFIX = 'not ';
  SPAN_066 = 'sca066';
  SPAN_072 = 'sca072';
  SPAN_084 = 'sca084';
  // R_NO_COLUMN ('Spalte fehlt in der Meldung') stand seit Charge B2S-a
  // einmal in uRdxCodeMap, neben ColumnFromMessage (Review R3-05); die
  // Planer hier nehmen seit Charge G1 MsgNoColumn (uRdxText, E29), die
  // Konstante entfiel mit Gruppe G10.
  // Eigener Satz statt MsgNoLongerAtReportedPlace: das Subjekt ist kein
  // Code-Stueck.
  R_BOOL_MOVED    = 'the comparison with True/False is no longer at the '
    + 'reported place';
  R_IN_EXPRESSION = 'the call is part of an expression - without parentheses '
    + 'the name could be taken as a pointer';
  // SCA072: der Vergleich bindet anders, je Seite ein ganzer Satz (bis
  // Charge G1 ein Muster '%s - der Vergleich bindet dort anders' mit
  // eingesetztem Satzteil).
  R_BINDS_LEFT    = '"%s" is left of the name - the comparison binds '
    + 'differently there';
  R_BINDS_RIGHT   = 'the expression continues after %s - the comparison '
    + 'binds differently there';
  // Token, nach denen eine Anweisung beginnt (SCA066; ':' hinter einer
  // case-Marke): STATEMENT_PREV aus uRdxCodeMap - bis Charge R8 eine
  // eigene Liste ohne initialization/finalization.
  // Token, hinter denen die ganze rechte Seite bzw. Bedingung beginnt -
  // auch der Selektor eines case ('case GetKind() of'): er ist ordinal, die
  // Lesart als Zeiger gibt es dort nicht (Review Woche G07-21, wie if und
  // while; bis dahin 'Teil eines Ausdrucks').
  WHOLE_EXPR_STARTS: array[0..4] of string = (':=', 'if', 'while', 'until',
    'case');
  // Token, hinter denen ein Aufruf als ganze Anweisung/Bedingung endet
  // ('of': hinter dem case-Selektor).
  CALL_ENDS: array[0..8] of string = (';', 'end', 'else', 'until', 'then',
    'do', 'except', 'finally', 'of');
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
  R_FREE_COMMENT  = 'comment in the expression X.Free;';
  R_NOT_NIL_LINE  = 'the next line is not "X := nil;"';
  // Ein Kommentar der nil-Zeile, der das nennt, wandert nicht (rwE30).
  FREEANDNIL_WORD = 'FreeAndNil';
  // Seit welcher Delphi-Version SysUtils.FreeAndNil kennt.
  FREEANDNIL_SINCE_DELPHI = 5;

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

// IsKeyword (Woerter, die keinen Operanden beginnen) steht seit der
// Folgewelle des Wochen-Reviews in uRdxCodeMap - die Liste teilt sich
// diese Unit mit uRdxTypeProof.

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
  if Col < 1 then
  begin
    AReason := MsgNoColumn;
    Exit;
  end;
  // Auch eine Spalte hinter dem Zeilenende: die Zeile hat sich seit dem
  // Scan geaendert - die Meldung hat ihre Spalte (bis Charge FC hiess es
  // dort 'Spalte fehlt in der Meldung', Review R3, verpasst).
  // MatchClassTObject liest dort ein leeres Wort.
  if not MatchClassTObject(L, Col, CloseCol) then
  begin
    AReason := MsgNoLongerAtReportedPlace(CODE_TOBJECT);
    Exit;
  end;
  if AMap.HasNonCode(ALine, Col, CloseCol) then
  begin
    AReason := _('class(TObject) is inside a comment or string');
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
    AReason := _('the class body starts on the same line');
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

// DirectiveBetween (eine Compiler-Direktive zwischen dem Token APrev und
// (ALine, ACol); dieselbe Regel wie DirectiveAt - ein '{$' in einem
// '//'-Kommentar ist keine, bis Charge R8 zaehlte es hier mit) steht seit
// Charge H5c in uRdxCodeMap - uRdxResultFixes hatte eine zweite Fassung.

// Traegt die Zeile ALine ab AColX 'X.Free;', sobald Kommentare und Strings
// wegfallen? So liest der Detektor (ScanCodeLine ohne Spalten): er meldet
// 'X{owned}.Free;', 'X.{c}Free;' und 'X.Free {c};' wie 'X.Free;'.
function FreeCallAroundComment(AMap: TRdxCodeMap; ALine, AColX: Integer): Boolean;
var
  L, Code                   : string;
  i, n                      : Integer;
  NameEnd, FreeEnd, SemiCol : Integer;
begin
  L := AMap.Raw(ALine);
  if AColX > Length(L) then
    Exit(False);
  SetLength(Code, Length(L) - AColX + 1);
  n := 0;
  for i := AColX to Length(L) do
    if AMap.IsCode(ALine, i) then
    begin
      Inc(n);
      Code[n] := L[i];
    end;
  SetLength(Code, n);
  Result := MatchFreeCall(Code, 1, NameEnd, FreeEnd, SemiCol);
end;

// Steht T fuer eine Anweisung, die nur bedingt laeuft - then, else, do
// oder eine case-Marke davor?
function IsBranchHead(const T: TRdxToken): Boolean;
begin
  Result := (T.Low = 'then') or (T.Low = 'else') or (T.Low = 'do')
    or (T.Low = ':');
end;

const
  // So viele Stellen prueft DirectiveMayGuard hoechstens; darueber: sperren.
  MAX_GUARD_PLACES = 64;

// Kann die Anweisung an (ALine, ACol) in EINER Konfiguration der bedingten
// Uebersetzung direkt hinter then/else/do bzw. einer case-Marke stehen?
// Gelesen werden die Direktiven zwischen dem Token davor und der Stelle
// (rueckwaerts): eine oeffnende ({$IF..}) laesst die Stelle in ihrem Zweig -
// sie gilt dann zusammen mit der nil-Zeile; ein {$ELSE}/{$ELSEIF} schliesst
// den Zweig davor aus - Vorgaenger ist dann das Token vor dem oeffnenden
// {$IF..}; ein {$ENDIF}/{$IFEND} laesst seinen Block zu oder nicht -
// Vorgaenger ist das Token davor (schon geprueft), das vor jedem
// {$ELSE}-Trenner des Blocks oder das vor dem oeffnenden {$IF..}. Jede
// solche Stelle wird ebenso geprueft (Arbeitsliste). Ein Include ({$I x})
// kann Code bringen - sperren, ebenso ein Block ohne Oeffner oder mehr als
// MAX_GUARD_PLACES Stellen. Andere Direktiven ({$R-}, {$DEFINE X}) bringen
// keinen Code. Bis zum Realwelt-Test rwE30 sperrte JEDE Direktive zwischen
// dem Token davor und X.Free; - auch ein abgeschlossener Einzeiler
// '{$IFOPT D+}SendDebug(..);{$ENDIF}' oder ein Zweig, in dem Free und nil
// zusammen stehen ('{$ELSE} Temp.Free; Temp := nil; {$ENDIF}').
function DirectiveMayGuard(AMap: TRdxCodeMap; ALine, ACol: Integer): Boolean;
var
  DLine, DCol : array of Integer;
  DWord       : array of string;
  DInc        : array of Boolean;
  WLine, WCol : array of Integer;
  n, nw, iw   : Integer;
  Li, Co      : Integer;
  k, m        : Integer;
  Depth       : Integer;
  Arg         : Boolean;
  Over        : Boolean;   // mehr Stellen als MAX_GUARD_PLACES
  Prev        : TRdxToken;
  CL, CC      : Integer;

  procedure Push(ALi, ACo: Integer);
  begin
    if nw >= MAX_GUARD_PLACES then
    begin
      Over := True;
      Exit;
    end;
    WLine[nw] := ALi;
    WCol[nw] := ACo;
    Inc(nw);
  end;

  // Liegt Direktive Nr. AIdx hinter dem Token ATok?
  function AfterTok(AIdx: Integer; const ATok: TRdxToken): Boolean;
  begin
    Result := (ATok.Low = '') or (DLine[AIdx] > ATok.Line)
      or ((DLine[AIdx] = ATok.Line) and (DCol[AIdx] >= ATok.EndCol));
  end;

begin
  Result := True;
  // Alle Direktiven vor der Stelle, in Textreihenfolge.
  n := 0;
  SetLength(DLine, 16);
  SetLength(DCol, 16);
  SetLength(DWord, 16);
  SetLength(DInc, 16);
  Li := 1;
  Co := 1;
  while NextDirective(AMap, Li, Co)
        and ((Li < ALine) or ((Li = ALine) and (Co < ACol))) do
  begin
    if n = Length(DLine) then
    begin
      SetLength(DLine, n * 2);
      SetLength(DCol, n * 2);
      SetLength(DWord, n * 2);
      SetLength(DInc, n * 2);
    end;
    DLine[n] := Li;
    DCol[n] := Co;
    DWord[n] := DirectiveWord(AMap, Li, Co, Arg);
    DInc[n] := IncludeFileAt(AMap, Li, Co) <> '';
    Inc(n);
    Inc(Co);
  end;
  SetLength(WLine, MAX_GUARD_PLACES);
  SetLength(WCol, MAX_GUARD_PLACES);
  nw := 0;
  Over := False;
  Push(ALine, ACol);
  iw := 0;
  while iw < nw do
  begin
    CL := WLine[iw];
    CC := WCol[iw];
    Inc(iw);
    Prev := PrevToken(AMap, CL, CC);
    if IsBranchHead(Prev) then
      Exit;
    // Die Direktiven zwischen Prev und der Stelle, die letzte zuerst.
    k := n - 1;
    while (k >= 0) and ((DLine[k] > CL) or ((DLine[k] = CL) and (DCol[k] >= CC))) do
      Dec(k);
    while (k >= 0) and AfterTok(k, Prev) do
    begin
      if DInc[k] then
        Exit;
      if (DWord[k] = 'else') or (DWord[k] = 'elseif')
         or InList(DWord[k], COND_CLOSERS) then
      begin
        // Der oeffnende Partner und die Trenner seines Blocks.
        Depth := 0;
        m := k - 1;
        while m >= 0 do
        begin
          if InList(DWord[m], COND_CLOSERS) then
            Inc(Depth)
          else if InList(DWord[m], COND_OPENERS) then
          begin
            if Depth = 0 then
              Break;
            Dec(Depth);
          end
          else if (Depth = 0) and ((DWord[m] = 'else') or (DWord[m] = 'elseif')) then
            Push(DLine[m], DCol[m]);
          Dec(m);
        end;
        if m < 0 then
          Exit;   // kein Oeffner vor der Stelle
        Push(DLine[m], DCol[m]);
        if Over then
          Exit;
      end;
      Dec(k);
    end;
  end;
  Result := False;
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
  // Ein Kommentar im Ausdruck zeigt sich erst, wenn der Rohtext NICHT passt
  // (in 'X.Free;' selbst ist kein Platz fuer einen): passt dann die
  // Code-Sicht, nennt der Grund den Kommentar statt einer verschobenen
  // Zeile - der Fund ist frisch (Review R6-04; die Sperre stand bis dahin
  // HINTER dem Treffer auf dem Rohtext und griff nie).
  if not MatchFreeCall(L, AColX, ANameEnd, AFreeEnd, SemiCol) then
  begin
    if FreeCallAroundComment(AMap, ALine, AColX) then
      Exit(_(R_FREE_COMMENT));
    Exit(MsgNoLongerAtReportedPlace(CODE_FREE));
  end;
  // Hinter dem ';' nur noch Leerraum oder ein //-Kommentar: weiterer Code
  // liefe sonst NACH dem nil (Reihenfolge), ein {-Kommentar oder eine
  // Direktive koennte die nil-Zeile umschliessen.
  Rest := Trim(Copy(L, SemiCol + 1, MaxInt));
  if (Rest <> '') and (Copy(Rest, 1, 2) <> '//') then
    Exit(_('something else follows X.Free;'));
  // X.Free; als einzige Anweisung hinter then/else/do/case-Marke: dann
  // wuerde das bisher unbedingte ':= nil' bedingt.
  Prev := PrevToken(AMap, ALine, AColX);
  if (Prev.Low = 'then') or (Prev.Low = 'else') or (Prev.Low = 'do')
     or (Prev.Low = ':') then
    Exit(_('X.Free; is the statement after "%s" - the nil would become '
      + 'conditional', [Prev.Low]));
  // 'if A then {$IFDEF LOG}Log;{$ENDIF} X.Free;': ohne LOG steht X.Free;
  // allein hinter 'then' - die Sperre oben saehe nur das ';' von Log. Seit
  // rwE30 nur, wenn eine Konfiguration das wirklich so stellt
  // (DirectiveMayGuard).
  if DirectiveBetween(AMap, Prev, ALine, AColX)
     and DirectiveMayGuard(AMap, ALine, AColX) then
    Result := _('compiler directive before X.Free; - the statement before '
      + 'it does not always apply');
end;

// Die nil-Zeile N: genau 'X := nil;' (';' optional) mit X = AName.
// '' oder der Grund.
function CheckNilLine(const N, AName: string): string;
var
  k : Integer;
begin
  k := SkipBlanks(N, 1);
  if not WordAt(N, k, AName) then Exit(_(R_NOT_NIL_LINE));
  k := SkipBlanks(N, k + Length(AName));
  if Copy(N, k, 2) <> ':=' then Exit(_(R_NOT_NIL_LINE));
  k := SkipBlanks(N, k + 2);
  if not WordAt(N, k, 'nil') then Exit(_(R_NOT_NIL_LINE));
  k := SkipBlanks(N, k + 3);
  if (k <= Length(N)) and (N[k] = ';') then
    k := SkipBlanks(N, k + 1);
  if k <= Length(N) then
    Exit(_('something else follows X := nil'));
  Result := '';
end;

class function TRdxSimpleFixes.FreeAndNilFix(AMap: TRdxCodeMap;
  ALine: Integer; out AEdits: TArray<TRdxEdit>; out AName: string;
  out AReason: string): Boolean;
var
  L, N, Code, Comment    : string;
  ColX, NameEnd, FreeEnd : Integer;
  SemiCol, Slash         : Integer;
begin
  Result := False;
  AEdits := nil;
  AName := '';
  // Die nil-Zeile wird samt Zeilenende entfernt - dahinter muss eine
  // Zeile stehen (in einer Unit immer, mindestens 'end.').
  if (ALine < 1) or (ALine + 2 > AMap.LineCount) then
  begin
    AReason := _('no line after the nil assignment');
    Exit;
  end;
  AReason := CheckFreeLine(AMap, ALine, ColX, NameEnd, FreeEnd);
  L := AMap.Raw(ALine);
  // Der Name auch fuer eine Sperre hinter dem Treffer - der Menuetext
  // nennt sonst 'FreeAndNil(X)' (Realwelt-Test rwE30: GX_ClassBrowser,
  // FileView, JvLookup ...).
  if MatchFreeCall(L, ColX, NameEnd, FreeEnd, SemiCol) then
    AName := Copy(L, ColX, NameEnd - ColX);
  if AReason <> '' then Exit;
  // FreeAndNil gibt es ab Delphi 5: ein Zweig nur fuer aeltere Compiler
  // ('{$IFNDEF GX_VER130_up}', '{$IFNDEF WIN32}') sperrt (rwE30,
  // GX_Actions.pas:315, JvDBCtrl.pas:1089).
  AReason := TRdxTypeProof.OldCompilerBranchReason(AMap, ALine,
    FREEANDNIL_SINCE_DELPHI);
  if AReason <> '' then Exit;
  // Zeile i+1: genau 'X := nil;', dahinter hoechstens ein //-Kommentar.
  N := AMap.Raw(ALine + 1);
  Code := N;
  Comment := '';
  Slash := AMap.LineCommentCol(ALine + 1);
  if Slash > 0 then
  begin
    Code := Copy(N, 1, Slash - 1);
    Comment := TrimRight(Copy(N, Slash, MaxInt));
  end;
  if AMap.HasNonCode(ALine + 1, 1, Length(Code)) then
  begin
    AReason := _('comment or string in the nil line');
    Exit;
  end;
  AReason := CheckNilLine(Code, Copy(L, ColX, NameEnd - ColX));
  if AReason <> '' then Exit;
  // Ein leerer Kommentar ('//') geht mit der Zeile, ein Text wandert an
  // das Ende der FreeAndNil-Zeile ('frmPreferences := nil; // Important in
  // SetupSynEditors', HeidiSQL main.pas, rwE30) - ausser er nennt
  // FreeAndNil (dann ist die Reihenfolge vermutlich Absicht) oder die
  // Free-Zeile traegt schon einen.
  if Trim(Copy(Comment, 3, MaxInt)) = '' then
    Comment := ''
  else if ContainsText(Comment, FREEANDNIL_WORD)
     or (AMap.LineCommentCol(ALine) > 0) then
  begin
    AReason := _('comment or string in the nil line');
    Exit;
  end;

  SetLength(AEdits, 2);
  // E1: 'X.Free' -> 'FreeAndNil(X)'; ';' und ein Kommentar bleiben stehen,
  // der Kommentar der nil-Zeile kommt dahinter.
  if Comment = '' then
  begin
    AEdits[0].Span := TRefactorSpan.Make(SPAN_085, ALine, ColX, ALine, FreeEnd);
    AEdits[0].Expected := Copy(L, ColX, FreeEnd - ColX);
    AEdits[0].NewText  := 'FreeAndNil(' + AName + ')';
  end
  else
  begin
    AEdits[0].Span := TRefactorSpan.Make(SPAN_085, ALine, ColX, ALine,
      Length(L) + 1);
    AEdits[0].Expected := Copy(L, ColX, MaxInt);
    AEdits[0].NewText  := 'FreeAndNil(' + AName + ')'
      + TrimRight(Copy(L, FreeEnd, MaxInt)) + ' ' + Comment;
  end;
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

class function TRdxSimpleFixes.WithBefore(AMap: TRdxCodeMap;
  ALine: Integer): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  if (ALine < 1) or (ALine > AMap.LineCount) then
    Exit;
  T := NextToken(AMap, ALine, 1);
  if T.Low = '' then
    Exit;
  if TRdxTypeProof.InWithBody(AMap, T) then
    Exit(True);
  // Ein 'with' auf der Zeile selbst ('with X do Y.Free;') - der Lauf oben
  // beginnt VOR ihrem ersten Token. Vorsichtig jedes, auch eines hinter
  // der gefragten Anweisung.
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if (T.Low = 'with') and IsKeywordAfter(T, Before(AMap, T)) then
      Exit(True);
    T := After(AMap, T);
  end;
end;

class function TRdxSimpleFixes.UnqualifiedCalls(AMap: TRdxCodeMap;
  const AName: string): TArray<TRdxToken>;
var
  Low     : string;
  T, P, N : TRdxToken;
begin
  Result := nil;
  if (AName = '') or TRdxTypeProof.DeclaresRoutine(AMap, AName) then
    Exit;
  Low := LowerCase(AName);
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), Low);
  while T.Low <> '' do
  begin
    if T.Low = Low then
    begin
      P := Before(AMap, T);
      N := After(AMap, T);
      // 'FreeAndNil: procedure(..)', 'FreeAndNil = ..', 'A, FreeAndNil: T',
      // 'FreeAndNil := ..': der Name ist hier auch etwas anderes.
      if InList(N.Low, DECL_AFTER) then
        Exit(nil);
      if (N.Low = '(') and (P.Low <> '.') and (P.Low <> 'inherited')
         and not WithBefore(AMap, T.Line) then
        AddToken(Result, T);
    end;
    T := NextTokenOnLineWith(AMap, T, Low);
  end;
end;

// Die Klasse der aeussersten Routine um die Stelle (LocalBinding:
// 'TFoo.Bar' -> 'TFoo'); '' in einer freien Routine oder auf Unit-Ebene.
function ClassOfBinding(const AFind: TRdxLocalFind): string;
var
  P : Integer;
begin
  Result := '';
  P := LastDelimiter('.', AFind.OuterName);
  if (AFind.Routines > 0) and (P > 0) then
    Result := Copy(AFind.OuterName, 1, P - 1);
end;

class function TRdxSimpleFixes.CallsBindingAt(AMap: TRdxCodeMap;
  const AName: string; ALine: Integer): TArray<TRdxToken>;
var
  At, C     : TRdxToken;
  Site, Use : TRdxLocalFind;
  SiteClass : string;
  UseClass  : string;
begin
  Result := nil;
  if (ALine < 1) or (ALine > AMap.LineCount) then
    Exit;
  At := NextToken(AMap, ALine, 1);
  if (At.Low = '') or (At.Line <> ALine) then
    Exit;
  Site := TRdxTypeProof.LocalBinding(AMap, At, AName);
  if Site.Kind <> lkNone then
    Exit;
  SiteClass := ClassOfBinding(Site);
  for C in UnqualifiedCalls(AMap, AName) do
  begin
    Use := TRdxTypeProof.LocalBinding(AMap, C, AName);
    if Use.Kind <> lkNone then
      Continue;
    UseClass := ClassOfBinding(Use);
    if (UseClass = '') or SameText(UseClass, SiteClass) then
      AddToken(Result, C);
  end;
end;

class function TRdxSimpleFixes.VariableProof(AMap: TRdxCodeMap;
  ALine: Integer; const AName: string;
  const AUnitFile: string): TRdxVarProof;
var
  At        : TRdxToken;
  Find      : TRdxLocalFind;
  P         : Integer;
  ClassPath : string;
  Ty        : string;
begin
  Result := Default(TRdxVarProof);
  if (ALine < 1) or (ALine > AMap.LineCount) then
    Exit;
  At := NextToken(AMap, ALine, 1);
  if (At.Low = '') or (At.Line <> ALine) then
    Exit;
  Find := TRdxTypeProof.LocalBinding(AMap, At, AName);
  if Find.Kind = lkVar then
  begin
    Result.Kind := vpLocal;
    Result.TypeLow := Find.TypeLow;
    Exit;
  end;
  if Find.Kind <> lkNone then
    Exit;
  P := LastDelimiter('.', Find.OuterName);
  if (Find.Routines > 0) and (P > 0) then
  begin
    // In einer Methode (auch verschachtelt darin): erst das eigene Feld,
    // dann ein Global nur ohne Namensvetter in der Klasse bzw. der Unit.
    ClassPath := Copy(Find.OuterName, 1, P - 1);
    Ty := TRdxTypeProof.OwnFieldType(AMap, ClassPath, AName);
    if Ty <> '' then
    begin
      Result.Kind := vpField;
      Result.TypeLow := Ty;
      Exit;
    end;
    if (TRdxTypeProof.FieldTypeOf(AMap, AName) <> '')
       or TRdxTypeProof.DeclaresProperty(AMap, AName)
       or TRdxTypeProof.DeclaresRoutine(AMap, AName)
       or TRdxTypeProof.RtlAncestorOrUnknown(AMap, ClassPath, AName) then
      Exit;
  end;
  // Ausserhalb einer Methode (freie Routine, initialization/finalization,
  // Hauptprogramm) gibt es kein Self: ein zuweisbarer Name ohne lokale
  // Deklaration ist eine Variable einer Unit - bewiesen nur die dieser.
  Ty := TRdxTypeProof.UnitVarType(AMap, AName);
  // rwE31: ein Global einer Unit neben der Datei - nur, wenn diese Unit
  // den Namen weder als Variable noch sonst deklariert (sie verdeckte
  // jede andere Unit).
  if (Ty = '') and (AUnitFile <> '')
     and (TRdxTypeProof.FieldTypeOf(AMap, AName) = '')
     and not TRdxTypeProof.DeclaresProperty(AMap, AName)
     and not TRdxTypeProof.DeclaresRoutine(AMap, AName)
     and (TRdxTypeProof.DeclaredTypeKind(AMap, AName) = '')
     and not DeclaresAfter(AMap, ['const', 'resourcestring'], AName) then
    Ty := TRdxTypeProof.NeighbourVarType(AMap, AUnitFile, AName);
  if Ty <> '' then
  begin
    Result.Kind := vpGlobal;
    Result.TypeLow := Ty;
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
    Exit(MsgNoColumn);
  L := AMap.Raw(ALine);
  if not WordAt(L, ACol, 'Assert') or not AMap.IsCode(ALine, ACol)
     or ((ACol > 1) and IsIdentChar(L[ACol - 1])) then
    Exit(MsgNoLongerAtReportedPlace(CODE_ASSERT));
  // 'Obj.Assert(x)' / 'Unit.Assert(x)' ist nicht die RTL - nur
  // 'System.Assert'. 'inherited Assert' bindet immer an einen Vorfahren,
  // 'procedure Assert(' ist die Deklaration selbst (der Detektor meldet
  // auch sie).
  Prev := PrevToken(AMap, ALine, ACol);
  if (Prev.Low = '.') and (Before(AMap, Prev).Low <> 'system') then
    Exit(_('Assert is qualified here - not System.Assert'));
  if (Prev.Low = 'inherited') or (Prev.Low = 'procedure')
     or (Prev.Low = 'function') then
    Exit(_('"%s Assert" is not a call to System.Assert', [Prev.Low]));
  AOpenCol := SkipBlanks(L, ACol + 6);
  if (AOpenCol > Length(L)) or (L[AOpenCol] <> '(')
     or not AMap.IsCode(ALine, AOpenCol) then
    Exit(MsgNoLongerAtReportedPlace(CODE_ASSERT));
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
        Exit(_('Assert already has a message'));
    end;
  end;
  Result := _('Assert does not end on this line');
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
    AReason := _('comment in the condition');
    Exit;
  end;
  L := AMap.Raw(ALine);
  Inner := TrimRight(Copy(L, OpenCol + 1, CloseCol - OpenCol - 1));
  if Trim(Inner) = '' then
  begin
    AReason := _('Assert without a condition');
    Exit;
  end;
  Lit := '''' + StringReplace(Trim(Inner), '''', '''''', [rfReplaceAll]) + '''';
  if Length(Lit) > MAX_ASSERT_LITERAL then
  begin
    AReason := _('condition too long for a string literal (255 characters)');
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
// Backticks (uEmptyVisibilitySection.SektionsName), klein; '' ohne sie
// (QuotedText, uRdxCodeMap - bis Charge B2S-a hier ausgeschrieben).
function SectionNameOf(const AMessage: string): string;
begin
  Result := LowerCase(QuotedText(AMessage, '`'));
end;

// Traegt die Zeile ALine (Text L) genau den Abschnitt AName - ohne
// Kommentar, und 'strict' nicht von seinem Abschnitt getrennt? '' oder der
// Grund.
function SectionLineReason(AMap: TRdxCodeMap; ALine: Integer;
  const AName, L: string): string;
begin
  if AMap.StartsInside(ALine) or AMap.HasNonCode(ALine, 1, Length(L)) then
    Exit(_('comment or string on the line - it would be lost on deletion'));
  // 'strict' ohne 'private'/'protected' auf derselben Zeile: das Wort
  // gehoert zum Abschnitt der naechsten Zeile - weg damit wuerde aus
  // 'strict private' ein 'private'.
  if AName = 'strict' then
    Exit(_('strict stands alone - it belongs to the next line'));
  // Umgekehrt: 'strict' allein auf der Zeile davor gehoert zu DIESEM
  // Abschnitt - ohne ihn wuerde aus 'strict' + 'protected' ein 'strict
  // protected'.
  if PrevToken(AMap, ALine, 1).Low = 'strict' then
    Exit(_('strict on the line before belongs to this section'));
  if LowerCase(CollapseBlanks(L)) <> AName then
    Exit(MsgMovedSuffix(_('line %d carries more than "%s"', [ALine, AName])));
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
    Exit(_('"%s" follows the section - it is not empty', [Next.Low]));
  if DirectiveBefore(AMap, ALine + 1, Next) then
    Exit(_('compiler directive up to the next section - the empty section '
      + 'may apply only in one branch'));
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
    AReason := _('the message has no section')
  // Die Zeile wird samt Zeilenende geloescht - dahinter steht in einer
  // Klasse immer noch eine Zeile (mindestens 'end').
  else if (ALine < 1) or (ALine >= AMap.LineCount) then
    AReason := _('no line after the section')
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
    Result := _('%s.Free appears more than once on the line', [AReceiver])
  else if ContainsText(ALineText, AReceiver + '.Destroy') then
    Result := _('%s.Destroy instead of %s.Free - FreeAndNil replaces only '
      + 'Free', [AReceiver, AReceiver])
  else
    Result := MsgMovedSuffix(_('%s.Free is no longer on the line',
      [AReceiver]));
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
    AReason := _('the message has no receiver');
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
    AReason := _('%s.Free is attached to a path - FreeAndNil needs a '
      + 'variable', [AReceiver]);
    Exit;
  end;
  k := SkipBlanks(L, FreeEnd);
  if (k <= Length(L)) and (L[k] = '(') then
  begin
    AReason := _('X.Free() with parentheses');
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
    Exit(_('no simple variable left of := (path, index or var declaration) '
      + '- its type decides the meaning'));
  ATarget := Copy(AMap.Raw(Lhs.Line), Lhs.Col, Lhs.Len);
end;

// Deklaration 'procedure Foo();' / 'function TFoo.Bar(): Integer;': ohne
// Klammern dieselbe, solange ';' oder ':' folgt (keine Direktive dahinter).
function DeclArgsReason(const ANext: TRdxToken): string;
begin
  Result := '';
  if (ANext.Low <> ';') and (ANext.Low <> ':') then
    Result := _('declaration: neither ";" nor ":" follows ()');
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
    Exit(_('a link of the call chain is not a plain name'));
  Prev := Before(AMap, Start);
  Next := After(AMap, AClose);
  if InList(Prev.Low, DECL_STARTS) then
    Exit(DeclArgsReason(Next));
  if (not InList(Prev.Low, STATEMENT_PREV)
      and not InList(Prev.Low, WHOLE_EXPR_STARTS))
     or ((Next.Low <> '') and not InList(Next.Low, CALL_ENDS)) then
    Exit(_(R_IN_EXPRESSION));
  Name := Copy(AMap.Raw(AName.Line), AName.Col, AName.Len);
  // Ein Ereignisname ist eine Property - ob Delphi eine Property mit
  // Prozedurtyp ohne () aufruft, ist nicht belegt (s. EmptyArgs) - oder
  // ein Feld, das Delphi ohne () aufruft ('FOnChange()', Horse 'class var
  // FOnListen: TProc'); welches gemeint ist, sieht der Planer ohne Typ
  // nicht. Bis Charge FC hiess es hier, eine Methodenreferenz rufe Delphi
  // ohne () nicht auf - fuer Variablen widerlegt die DocWiki das; bis zur
  // Nachpruefung FC nannte der Grund jede Sperre eine Ereignis-Property.
  if HasCapPrefix(Name, 'On') or HasCapPrefix(Name, 'FOn') then
    Exit(_('%s looks like an event - as a field Delphi calls it without (), '
      + 'as a property that is not proven; which one is meant stays open '
      + 'without the type', [Name]));
  // Ueber den Namen, nicht den Typ: der Pfad davor ist ohne Parser
  // unbekannt. Eine gleichnamige Methode einer anderen Klasse verliert so
  // ihre Hilfe (Korpus ab8: 1 von 6080 Angeboten, 'Binarizer.BlackMatrix()'
  // neben 'property BlackMatrix: TBitMatrix') - lieber keine Hilfe.
  if TRdxTypeProof.DeclaresProperty(AMap, Name) then
    Exit(_('%s is declared as a property in this unit - if the call means '
      + 'it, it is not proven whether Delphi calls a property of procedural '
      + 'type without ()', [Name]));
  if (Start.Col = AName.Col) and (Start.Line = AName.Line)
     and InsideOwnFunction(AMap, AName.Line, AName.Low) then
    Exit(_('%s() in the function %s - without parentheses the meaning '
      + 'depends on the dialect (recursion or result)', [Name, Name]));
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
    AReason := MsgNoColumn;
    Exit;
  end;
  L := AMap.Raw(ALine);
  if (Col > Length(L)) or (L[Col] <> '(') or not AMap.IsCode(ALine, Col) then
  begin
    AReason := MsgNoLongerAtReportedPlace(CODE_ARGS);
    Exit;
  end;
  // Zwischen Name und '(' sowie in den Klammern nur Leerraum - kein
  // Kommentar, der beim Loeschen verloren ginge.
  Close := NextToken(AMap, ALine, Col + 1);
  NameTok := PrevToken(AMap, ALine, Col);
  if (Close.Low <> ')') or (Close.Line <> ALine)
     or (SkipBlanks(L, Col + 1) <> Close.Col) then
    AReason := _('the parentheses contain more than whitespace')
  else if not NameTok.IsWord or IsKeyword(NameTok.Low)
          or (NameTok.Line <> ALine) then
    AReason := _('no plain name before () (member or result call)')
  else if SkipBlanks(L, NameTok.EndCol) <> Col then
    AReason := _('more than whitespace between the name and ()')
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
    Exit(_(R_BOOL_MOVED));
  if not ALhs.IsWord or IsKeyword(ALhs.Low) or (ALhs.Line <> AOp.Line) then
    Exit(_('no plain name left of the comparison'));
  Prev := Before(AMap, ALhs);
  if Prev.Low = '.' then
    Exit(_('a path is on the left - its type cannot be proven here'));
  if not InList(Prev.Low, OPERAND_STARTS) then
    Exit(_(R_BINDS_LEFT, [Prev.Low]));
  if not InList(After(AMap, ARhs).Low, EXPR_ENDS) then
    Exit(_(R_BINDS_RIGHT, [ARhs.Low]));
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
    AReason := MsgNoColumn;
    Exit;
  end;
  L := AMap.Raw(ALine);
  // ':=', '<=', '>=' sind kein Vergleich auf Gleichheit.
  if (Col > Length(L)) or not AMap.IsCode(ALine, Col)
     or ((Col > 1) and CharInSet(L[Col - 1], [':', '<', '>'])) then
  begin
    AReason := _(R_BOOL_MOVED);
    Exit;
  end;
  Op := TokenAt(AMap, ALine, Col);
  Lhs := PrevToken(AMap, ALine, Col);
  Rhs := After(AMap, Op);
  AReason := BoolOperandsReason(AMap, Op, Lhs, Rhs);
  if AReason <> '' then Exit;
  if AMap.HasComment(ALine, Lhs.Col, Rhs.EndCol - 1) then
  begin
    AReason := _('comment in the comparison');
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
    Exit(_('Assigned is qualified here - not the system routine'));
  if (Prev.Low = 'not') or (Prev.Low = '@') then
    Exit(_('"%s" before the expression binds only to its first part',
      [Prev.Low]));
  if (Prev.IsWord and not IsKeyword(Prev.Low))
     or InList(Prev.Low, [')', ']', '>', '^']) then
    Exit(_('"%s" before the expression - the parenthesis belongs to a call '
      + 'or cast', [Prev.Low]));
  Next := After(AMap, ALast).Low;
  if (Next = '.') or (Next = '[') or (Next = '^') then
    Exit(_('"%s" after the expression binds only to its last part', [Next]));
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
    AReason := MsgNoColumn;
    Exit;
  end;
  L := AMap.Raw(ALine);
  if (Col > Length(L)) or not AMap.IsCode(ALine, Col) then
  begin
    AReason := MsgNoLongerAtReportedPlace(CODE_ASSIGNED);
    Exit;
  end;
  First := TokenAt(AMap, ALine, Col);
  if MatchTokens(AMap, First, ASSIGNED_FIRST, Toks) then
    Keep := 0
  else if MatchTokens(AMap, First, NIL_FIRST, Toks) then
    Keep := 6
  else
  begin
    AReason := _('no "Assigned(X) and (X <> nil)" on one line here (no quick '
      + 'fix without parentheses around the comparison)');
    Exit;
  end;
  AReason := AssignedNilContext(AMap, First, Toks[9]);
  if AReason <> '' then Exit;
  if AMap.HasComment(ALine, First.Col, Toks[9].EndCol - 1) then
  begin
    AReason := _('comment in the expression');
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
// Bedingung das Schluesselwort if/while/case)? Ein Abgleich des Funds mit
// dem Text (Zeile verschoben?), keine Frage nach der Syntax - die stellt
// uRdxCodeMap.StartsStatement (beginnt an einem Token eine Anweisung?; bis
// zur Folgewelle des Wochen-Reviews in uRdxStructFixes); bis Charge B2S-a
// trug diese hier denselben Namen (Review R3-05).
function StatementStillAt(AMap: TRdxCodeMap; const ASite: TRdxNilSite): Boolean;
var
  KwLow : string;   // nicht 'Low': verdeckte System.Low (Review R3-06)
begin
  if not AMap.IsCode(ASite.Line, ASite.Col) then Exit(False);
  if ASite.Anchor <> naCondition then Exit(True);
  KwLow := TokenAt(AMap, ASite.Line, ASite.Col).Low;
  Result := (KwLow = 'if') or (KwLow = 'while') or (KwLow = 'case');
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
      Result := _('operand before the comparison is ambiguous');
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
    Result := _('operand after the comparison is ambiguous');
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
    Exit(_('anonymous method in the statement'));
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
      Inc(Depth, ParenDelta(T));
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
    Result := MsgStatementEndNotFound;
end;

// Kommentar oder Direktive bei der Anweisung AFirst..ALast? Der Detektor
// sieht sie nicht, eine Ersetzung koennte sie zerreissen. Auf EINER Zeile
// zaehlt der Bereich ab AFirst.Col bis ALast.Col; ueber mehrere Zeilen
// zaehlt jede GANZE Zeile von AFirst.Line bis ALast.Line - auch ein
// Kommentar vor AFirst oder hinter ALast. Bewusst breiter als
// CommentInRange (zeichengenau im Bereich); bis Charge B2S-a hiess sie
// RegionHasComment, wie ein Synonym von CommentInRange (Review R3-05).
function CommentOnRegionLines(AMap: TRdxCodeMap;
  const AFirst, ALast: TRdxToken): Boolean;
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
    Exit(_('operand spans several lines'));
  AOperand := TextBetween(AMap, ACmp.First, ACmp.Last);
  // Schon Assigned(X) in derselben Anweisung: das ist SCA084
  // (AssignedAndAssignedNil) - dessen Hilfe statt 'Assigned(X) and Assigned(X)'.
  if Pos('assigned(' + Squeezed(AOperand) + ')', ARegion) > 0 then
    Exit(_('Assigned(X) is already in the statement (SCA084)'));
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
    Exit(_('comparison spans several lines'));
  if not IsLeftBoundary(Before(AMap, Span.First))
     or not IsRightBoundary(After(AMap, Span.Last)) then
    Exit(_('boundary of the comparison unclear ("%s %s ... %s")',
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
    Exit(_('no nil comparison in the finding'));
  // Eigener Satz statt MsgNoLongerAtReportedPlace: das Subjekt ist kein
  // Code-Stueck.
  if not StatementStillAt(AMap, ASite) then
    Exit(_('the statement is no longer at the reported place'));
  Result := ScanStatement(AMap, ASite, AScan);
  if Result <> '' then Exit;
  if not CountMatches(Length(AScan.Cmps), Expected, ASite.NodeText) then
    Exit(_('code and finding do not match (%d instead of %d comparisons)',
      [Length(AScan.Cmps), Expected]));
  if CommentOnRegionLines(AMap, AScan.StartTok, AScan.EndTok) then
    Result := _('comment or directive in the statement');
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
        Exit(_('nested nil comparisons'));
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
  // Genau diese Namen; Prozedurtypen dazu ueber
  // TRdxTypeProof.NamesProcType.
  RISKY_TYPES: array[0..10] of string = (
    'string', 'ansistring', 'unicodestring', 'widestring', 'shortstring',
    'rawbytestring', 'utf8string', 'variant', 'olevariant', 'array', 'set');
  TYPE_RISK = '%s is of type %s - Assigned() is not reliably equivalent for '
    + 'it';
var
  Ident : string;
begin
  Result := '';
  Ident := TrailingIdent(AOperand);
  if (Ident <> '') and (HasCapPrefix(Ident, 'On') or HasCapPrefix(Ident, 'FOn')
     or HasCapPrefix(Ident, 'Get')) then
    Exit(_('%s looks like an event or function - Assigned() then checks the '
      + 'pointer, not the result', [Ident]));
  if ATypeLow = '' then Exit;
  if InList(ATypeLow, RISKY_TYPES)
     or TRdxTypeProof.NamesProcType(ATypeLow) then
    Result := _(TYPE_RISK, [AOperand, ATypeLow]);
end;

class function TRdxNilFix.NilOperandReason(AMap: TRdxCodeMap;
  const AOperand, ATypeLow: string): string;
const
  R_TYPE_UNKNOWN = 'type of %s not proven - "= nil" would call a function or '
    + 'method pointer, Assigned() would not';
  R_PATH_END     = '%s ends in %s - not proven as a field in this unit: '
    + '"= nil" would call a method without arguments, Assigned() would only '
    + 'check the method pointer';
  R_PROC_IN_UNIT = '%s has the procedural type %s (declared in this unit) - '
    + '"= nil" calls it, Assigned() does not';
  R_NOT_PROVEN   = '%s: type %s is not proven in this unit as a class, '
    + 'interface or pointer and is not a class of the Delphi sources - '
    + '"= nil" would call a function type of another unit, Assigned() would '
    + 'not';
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
      Exit(_(R_TYPE_UNKNOWN, [AOperand]));
    TypeLow := TRdxTypeProof.FieldTypeOf(AMap, Ident);
    if TypeLow = '' then
      Exit(_(R_PATH_END, [AOperand, Ident]));
    Result := NilOperandRisk(AOperand, TypeLow);
    if Result <> '' then Exit;
  end;
  if TRdxTypeProof.ProceduralType(AMap, TypeLow) then
    Exit(_(R_PROC_IN_UNIT, [AOperand, TypeLow]));
  // Der POSITIVE Beweis wie bei SCA084 (AssignedNilReason in uRdxFixRunner,
  // der OperandReason-Pfad von TRdxFixRunner.OperandFix - nicht in dieser
  // Unit): ein Typ aus einer anderen Unit mit unauffaelligem Namen ('uses
  // uFactories; FMaker: TObjFactory' mit 'function: TObject' dort) ging bis
  // Charge R8 durch - 'if FMaker = nil' wurde 'if not Assigned(FMaker)', ein
  // anderer Sinn. Das kostet Angebote bei Fremdtypen und gewinnt Sicherheit
  // (Semantik-Gegen-Review 2026-10-14, Major). Seit E27 (Charge R10) zaehlen
  // die Klassen und Interfaces der Delphi-Quellen als bewiesen
  // (uRdxRtlTypes, in PointerLikeType) - Kundentypen bleiben draussen.
  if not TRdxTypeProof.PointerLikeType(AMap, TypeLow) then
    Result := _(R_NOT_PROVEN, [AOperand, TypeLow]);
end;

end.

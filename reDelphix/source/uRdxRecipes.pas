unit uRdxRecipes;

// reDelphix - die Rezepte: aus beschriebenen Quellstellen (TRefactorInfo
// aus dem SCA-Core, Konzept_SourceRefactor_Quellstellen Abschnitt 5) neuen
// Quelltext bauen. Reine Textarbeit - kein ToolsAPI, keine Datei, kein
// VCL. Deshalb laeuft diese Unit im FPC-Pruefstand und ihre Tests sind
// ohne IDE ausfuehrbar.
//
// WAS HIER ENTSTEHT
//
//   BuildFormatCall   'a' + X + 'b'      ->  Format('a%sb', [X])
//                     mit dem Urteil je Operand (JudgeOperand)
//   SplitLongLiteral  ein Literal ueber 255 Elemente -> 'a..' + '..'
//   Fund-Abgleich     Ziel und '+'-Zahl aus der Meldung von SCA044/SCA003
//                     (ConcatFindingTarget, SqlFindingTarget, TargetKey)
//   uses-Helfer       UsesNameFor, LineLooksFpcAware, UsesTailLength,
//                     SortedInsertIndex - wo System.SysUtils hinkommt
//   DetectFramework   VCL oder FMX, aus den qualifizierten uses-Eintraegen
//
// Die SQL-Vorlage (Rezept 5.2, SCA003) steht seit Charge S1 (2026-10-15)
// in uRdxSqlTemplate; hier bleiben ihre Bausteine Literal-Codec,
// QueryObjectOf/HasQueryObject und IndentTextOf.
//
// Die Fakten kommen aus dem Core (Teilbereiche mit Rolle und Typ), die
// Politik steht hier: ein Format() wird nach der Kompilat-Regel gebaut
// (JudgeOperand, Block "Kompilat-Regel (AH20)" unten - ein Zahl-Operand
// hinter %s uebersetzt, wirft aber zur Laufzeit EConvertError), und nie
// fuer SQL-Text (SCA003 - Vertrag im Kopf von uRefactorConcat).
//
// LITERALE
//
// Ein Teilbereich mit ROLE_LITERAL traegt den QUELLTEXT des Literals
// ('it''s', 'a'#13#10'b', #$41). DecodeLiteral macht daraus den Wert,
// EncodeLiteral den Quelltext zurueck - so bleibt ein '%' im Wert
// escapebar ('%%') und Steuerzeichen bleiben als #13#10 lesbar.

interface

uses
  uRefactorInfo;   // TRefactorValueType

type
  // Ein Teilbereich mit seinem Quelltext - die Form, in der die Rezepte
  // die Parts eines TRefactorInfo bekommen (der Text kommt aus
  // TSourcePlaces.TextOf, hier wird keine Datei gelesen).
  TRdxPart = record
    Role        : string;
    Text        : string;
    ValueType   : TRefactorValueType;
    // Deklarierter Typ des Operanden (nackt, klein; TRefactorSpan.Resolved
    // nach TSourcePlaces.ResolveOperandTypes), sonst ''.
    Resolved    : string;
    // Deklarierter Typ des einzigen Bezeichner-Arguments bei IntToStr(x) -
    // dann wird daraus %d/%u mit x statt %s (AH20). x.ToString bleibt
    // %s: ein eigener Integer-Helper koennte anders formatieren (AH22).
    ArgResolved : string;
    // Deklarierter Typ des KOPF-Bezeichners eines Member-/Index-Terms
    // ('V.Name', 'V[0]' bei V: Variant) - Variant-Anzeichen (AH22).
    HeadResolved : string;
    // Der Term steht in einem with-Block (TSourcePlaces.InWithBlock): ein
    // Name kann dort an ein Member des with-Ausdrucks binden. Namensregeln
    // (RTL-Funktion, -Konstante, Typ-Alias) beweisen dann nichts; was
    // sperrt, sperrt weiter (Review reDelphiX 2026-10-07, strittiger
    // Minor 1).
    InWith : Boolean;
    // Eine Funktion der Unit mit dem Namen des Terms ('ParamStr' aus
    // 'ParamStr(1)') hat kein String-Ergebnis und verdeckt die RTL
    // (TSourcePlaces.DeclaresNonStringFunc, vom Aufrufer gesetzt).
    // Namensregeln beweisen dann nichts - wie im with-Block (Review
    // reDelphiX nach Bereichen 2026-10-10, Minor 2).
    Shadowed : Boolean;
  end;
  TRdxParts = TArray<TRdxPart>;

  // Urteil ueber einen Operanden fuer %s (Kompilat-Regel, AH20).
  TRdxOperandVerdict = (
    ovString,       // beweisbar String: Literal, deklariert, bekannter RTL-Aufruf/-Konstante, .ToString
    ovByCompiler,   // Typ unbekannt, aber die FORM ist ein Operand - das Kompilat buergt
    ovNonString,    // deklariert Zahl/Boolean/Datum oder Zahl-Cast
    ovAnsi,         // deklariert Nicht-Unicode-String - Format liefert UnicodeString
    ovVariantRisk,  // Variant-Anzeichen: deklariert Variant, .Value/.AsVariant, Null/True/nil
    ovNoOperand);   // keine Operandenform: Klammerausdruck, Zahl, Menge, Operator

  // Ergebnis von BuildFormatCall mit der Herkunft der Argumente.
  TRdxFormatBuild = record
    NewText    : string;
    Reason     : string;           // bei False
    Operands   : Integer;          // Argumente im Format-Aufruf
    Proven     : Integer;          // davon beweisbar (String oder Ganzzahl mit %d/%u)
    Numeric    : Integer;          // davon als %d/%u statt IntToStr/ToString
    ByCompiler : TArray<string>;   // Operanden, fuer die nur das Kompilat buergt
  end;

  // Wo die Terme fuer BuildFormatCall in der Kette stehen: am Anfang - dort
  // rechnet ein Zeiger als erster Term Zeiger-Arithmetik (Review FB R2-04)
  // - oder hinter dem Ziel beim Selbst-Anhaengen 'X := X + ..': dort ist X
  // der Anfang, ein String, und jeder Term dahinter verkettet (Nachpruefung
  // FB - bis dahin lehnte 'S := S + P + N + ''x''' mit P: PChar falsch ab).
  TRdxChainStart = (csChainHead, csBehindTarget);

  // Rahmenwerk einer Datei nach ihren qualifizierten uses-Eintraegen
  // (DetectFramework): keins erkennbar, VCL ('Vcl.*'), FMX ('FMX.*') oder
  // beide - davon haengt ab, welchen Scope ein mehrdeutiger Kurzname
  // ('Forms', 'Graphics') bekommt.
  TRdxFramework = (fwUnknown, fwVcl, fwFmx, fwBoth);

  TRdxRecipes = class
  public
    // Ein Teilbereich fuer die Rezepte (TRdxPart): Rolle, Quelltext, Core-
    // Urteil und - falls bekannt - deklarierter Typ des Operanden bzw. des
    // Arguments von IntToStr(x). HeadResolved, InWith und Shadowed setzt der
    // Aufrufer danach (TRdxRecipeRunner.PartsOf); hier stehen sie auf ''
    // bzw. False.
    class function MakePart(const ARole, AText: string;
      AValueType: TRefactorValueType = rvUnknown;
      const AResolved: string = '';
      const AArgResolved: string = ''): TRdxPart; static;

    // Quelltext eines Pascal-String-Literals -> Wert. False bei allem,
    // was kein reines Literal ist (unbalancierte Quotes, '^M', Bezeichner).
    class function DecodeLiteral(const ASource: string;
      out AValue: string): Boolean; static;
    // Wert -> Quelltext: Quotes verdoppelt, Steuerzeichen (< #32) als #nn.
    // Die Laenge begrenzt erst SplitLongLiteral.
    class function EncodeLiteral(const AValue: string): string; static;

    // Zeilenumbrueche und Tabulatoren zu einem Leerzeichen, aussen getrimmt.
    class function CollapseWhitespace(const AText: string): string; static;

    // True, wenn der Text wie ein SQL-Statement aussieht. Paar-Regel
    // (Review 2026-10-07, Nit 6), alles als ganze Woerter: ein Statement-
    // Verb zaehlt nur mit einem Strukturwort, das grammatisch zu IHM
    // passt und dahinter steht - select .. from/where/join/into, delete ..
    // from/where, insert .. into/values, merge .. into, update .. set;
    // bei create/alter/drop/truncate folgt das Objekt (table/index/view/
    // procedure/...) direkt, hoechstens nach Zusatzwoertern wie 'or
    // replace', 'unique', 'global temporary'. 'Update available from
    // server' und 'Create a table of contents' sind KEIN SQL. Bekannte
    // Grenze: 'Select a file from ' ist lexikalisch gueltiges SQL (Alias)
    // und sperrt weiter.
    class function LooksLikeSql(const AValue: string): Boolean; static;

    // Rezept 5.1 - Format() aus einer '+'-Kette. AParts in Quelltext-
    // Reihenfolge, Parts[0] darf ROLE_TARGET sein (wird uebersprungen).
    // False mit Grund, wenn ein Operand nach der Kompilat-Regel nicht
    // als %s taugt (JudgeOperand), kein Operand oder kein Literal
    // vorkommt, schon ein Format() in der Kette steht, ein Teil keine
    // Kette ist (ROLE_ARGUMENT) oder die Literale SQL ergeben.
    // IntToStr(x) / x.ToString mit bekanntem Ganzzahltyp werden %d/%u.
    // ATargetType: deklarierter Typ des Ziels (nackt, klein), wenn bekannt;
    // bei einem Unicode-Ziel (string/unicodestring/widestring) duerfen
    // Nicht-Unicode-Operanden mit, Format wandelt sie wie die Zuweisung.
    // Gesperrt auch ein Zeiger am Kettenanfang (Review FB R2-04; nicht bei
    // AStart = csBehindTarget) und das Selbst-Anhaengen an ein Ziel vom Typ
    // Variant/OleVariant (dort verkettet '+' nicht). Der Formatstring geht
    // durch SplitLongLiteral (kein Literal ueber 255 Elemente).
    class function BuildFormatCall(const AParts: TRdxParts;
      out ABuild: TRdxFormatBuild; const ATargetType: string = '';
      AStart: TRdxChainStart = csChainHead): Boolean; overload; static;
    // Dasselbe ohne Zieltyp und ohne die Herkunft der Argumente - nur Text
    // und Grund; fuer Aufrufer, die die Zaehler nicht brauchen (Tests,
    // Korpus-Probe).
    class function BuildFormatCall(const AParts: TRdxParts;
      out ANewText, AReason: string): Boolean; overload; static;

    // Leerraum zusammenziehen wie CollapseWhitespace, aber String-
    // Literale im Text bleiben Zeichen fuer Zeichen erhalten: der Text
    // eines Operanden wird so in den Format-Aufruf uebernommen
    // (StringReplace(S, '  ', ' ', ...) behaelt die zwei Leerzeichen; AH22).
    class function CollapseCode(const AText: string): string; static;

    // ---- Kompilat-Regel (AH20, Realworld-Stichprobe 2026-10-06) ----------
    //
    // Mit "nur beweisbar String" waeren am Korpus hoechstens 17 % der
    // SCA044-Stellen umformbar (Nachbildung an 200 von 2.363 Funden). Das
    // Kompilat buergt fuer mehr: eine '+'-Kette mit einem String-Literal
    // uebersetzt nur, wenn jeder Operand String-vertraeglich ist (String,
    // Char, PChar, AnsiString, Char-Array, ...) - oder ein Variant - oder
    // ein Record mit Implicit-Operator. %s nimmt die ersten beiden
    // (System.SysUtils.FormatBuf: vtVariant -> VariantToUnicodeString);
    // ein Record uebersetzt im Format-Aufruf nicht (sichtbarer Fehler,
    // Strg+Z - ohne Typinformation fremder Units nicht erkennbar).
    // Variant ist dennoch gesperrt: ist der Wert Null oder keine
    // Zeichenkette, wirft das Original (NullStrictConvert, Variant-
    // Arithmetik String+Zahl) oder die ganze Kette wird '' - Format gaebe
    // still die uebrigen Teile aus. Deshalb gilt ein Operand UNBEKANNTEN
    // Typs, wenn seine Form ein Operand ist (Bezeichner, Member, Aufruf,
    // Index, Cast) und er keine Variant-Anzeichen traegt; Zahlen, Zahl-
    // Casts, Klammerausdruecke und Mengen bleiben gesperrt. Ein deklarierter
    // Nicht-Unicode-String (AnsiString, RawByteString, UTF8String,
    // ShortString, RawUtf8) sperrt als Ziel immer und als Operand, wenn
    // das Ziel nicht nachweislich Unicode ist: Format liefert
    // UnicodeString. Ertrag in der Nachbildung: 83 %.
    //
    // Nachtraege Review reDelphiX 2026-10-07:
    //   * Das Urteil haengt am Typ, nicht an der Schreibweise: ein Cast
    //     auf einen Nicht-Unicode-String ('AnsiString(A)', 'AnsiChar(b)')
    //     und RTL-Aufrufe mit Ansi-Ergebnis (UTF8Encode, AnsiToUtf8,
    //     Utf8ToAnsi, StrPas) urteilen wie die Deklaration (Minor 12).
    //   * Aufrufe mit Zahl-Ergebnis (Length, Ord, Pos, Round, StrToInt,
    //     ...) sperren wie ein Zahl-Cast: in der Kette uebersetzen sie nur
    //     hinter einem Variant ohne Anzeichen, %s wirft dann (Minor 13).
    //   * Char/WideChar/ShortString-Operanden (deklariert, Cast oder
    //     Chr(...)) gehen als string(x) in den Aufruf: bei vtChar/
    //     vtWideChar/vtString haengt FormatBuf ohne Laenge an (StrLen),
    //     ein #0 ginge verloren, die Verkettung behaelt ihn (Minor 10).
    //     Bekannte Grenze: ein Char UNBEKANNTEN Typs ('S[i]', 'Obj.Ch')
    //     bleibt ohne Cast.
    //   * Im with-Block (TRdxPart.InWith) beweist kein Name etwas: RTL-
    //     Funktion, -Konstante und Typ-Alias zaehlen dort nur noch als
    //     Kompilat-Urteil (strittiger Minor 1). IntToStr(x) wird nur %d/%u,
    //     wenn der Core den Aufruf als RTL bewiesen hat (ValueType
    //     rvString): eine gleichnamige Funktion der Unit nimmt der Core
    //     zurueck (rvUnknown), dann bleibt IntToStr(x) stehen (strittiger
    //     Minor 3).
    //   * Nachtrag Review FB (R2-04): am Kettenanfang hinter einem Zeiger
    //     buergt das Kompilat nicht - PointerStartReason (implementation).

    // True, wenn der Text die Form eines Operanden hat: Bezeichner (oder
    // eine Klammergruppe mit folgendem '.', '[' oder '^', z. B.
    // '(Sender as TButton).Caption'), dann beliebig '.Bezeichner',
    // '(...)', '[...]', '^'. Literale im Text stoeren nicht. Kein
    // Operator, keine Zahl, kein blosser Klammerausdruck.
    class function IsOperandShape(const AText: string): Boolean; static;
    // True bei Variant-Anzeichen: letzter Name .Value/.AsVariant/
    // FieldValues, die Bezeichner Null/Unassigned/True/False/nil, ein
    // Variant(...)-Cast, ein mit String-Literal indizierter Bezeichner
    // (DS['Name'] = TDataSet.FieldValues).
    class function HasVariantTell(const AText: string): Boolean; static;
    // Der erste Bezeichner des Textes ('Obj' aus 'Obj.Items[i].Name'),
    // sonst ''.
    class function HeadIdentOf(const AText: string): string; static;
    // RTL-Konstanten mit String-Typ: sLineBreak, PathDelim, ...
    class function IsKnownStringConst(const AText: string): Boolean; static;
    // RTL-Funktionen mit String-Ergebnis jenseits der Core-Liste
    // (ExtractFileName, Copy, StringReplace, TPath.Combine, ...), deren
    // Klammer den ganzen Term abschliesst; qualifiziert nur mit
    // SysUtils/StrUtils/IOUtils.
    class function IsKnownStringFunc(const AText: string): Boolean; static;
    // RTL-Funktionen mit Nicht-Unicode-Ergebnis (UTF8Encode, AnsiToUtf8,
    // Utf8ToAnsi, StrPas), qualifiziert wie bei IsKnownStringFunc.
    // StrPas(PWideChar) liefert zwar UnicodeString - das Urteil ovAnsi ist
    // dann nur vorsichtig, nie falsch.
    class function IsKnownAnsiStringFunc(const AText: string): Boolean;
      static;
    // AnsiString, RawByteString, UTF8String, ShortString, RawUtf8,
    // PAnsiChar, AnsiChar.
    class function IsNonUnicodeStringType(const ATypeLow: string): Boolean;
      static;
    // True fuer genau einen Bezeichner: ein Anfangszeichen, dann nur
    // Bezeichnerzeichen (IsIdentStart/IsIdentChar wie der Core, also auch
    // Nicht-ASCII) - kein Punkt, keine Klammer, kein Leerraum. '' ist keiner.
    class function IsPlainIdent(const AText: string): Boolean; static;
    // Name, unter dem eine Funktion der Unit den Term verdecken koennte:
    // Kopf eines Aufrufs ('paramstr' aus 'ParamStr(1)') oder ein blosser
    // Bezeichner ('slinebreak'), klein; '' bei qualifizierten oder
    // zusammengesetzten Termen ('SysUtils.Trim(x)', 'TPath.GetTempPath').
    class function ShadowNameOf(const AText: string): string; static;
    // Das Urteil der Kompilat-Regel (Block oben) ueber EINEN Term fuer %s:
    // ein Literal ist ovString; sonst entscheiden der deklarierte Typ
    // (Resolved, HeadResolved) und das Core-Urteil (ValueType), dann
    // RTL-Namen (nicht im with-Block, nicht Shadowed), Variant-Anzeichen,
    // Cast- bzw. Aufrufkopf und zuletzt die Form (ovByCompiler oder
    // ovNoOperand). Die Stellung in der Kette (Zeiger am Anfang) prueft
    // BuildFormatCall.
    class function JudgeOperand(const APart: TRdxPart): TRdxOperandVerdict;
      static;
    // '%d' fuer vorzeichenbehaftete Ganzzahlen und Byte/Word, '%u' fuer
    // Cardinal/LongWord/UInt32/UInt64/NativeUInt, sonst ''.
    class function IntegerSpec(const ATypeLow: string): string; static;
    // 'x' aus 'IntToStr(x)' (nur ein nackter Bezeichner), sonst ''.
    // 'x.ToString' absichtlich nicht: ein eigener Helper fuer Integer
    // kann anders formatieren als IntToStr (AH22).
    class function IntegerArgumentOf(const AText: string): string; static;
    // IntToStr(x) mit x = Bezeichner bekannten Ganzzahltyps
    // (APart.ArgResolved): dann Argument x und Spezifikator %d/%u. Nur,
    // wenn der Core den Aufruf als RTL bewiesen hat (ValueType rvString)
    // und der Term nicht in einem with-Block steht.
    class function NumericArgument(const APart: TRdxPart;
      out AArgument, ASpec: string): Boolean; static;

    // Zahl der '+' auf oberster Klammerebene ausserhalb von Strings - die
    // Regel von TConcatToFormatDetector.ScanConcat (SCA044; dort privat),
    // angewandt auf den abgeflachten Ausdruck eines Knotens
    // (TNodeRef.TypeRef). Die vom Quelltext-Zerleger unabhaengige
    // Gegenprobe fuer TSourcePlaces.ChainOf (Review reDelphiX 2026-10-07,
    // strittiger Minor 2). -1 bei leerem Text.
    class function TopLevelPlusCount(const AExpr: string): Integer; static;

    // ---- Fund-Abgleich (Review reDelphiX 2026-10-07, Minor 20) ----------
    // Der Editor-Puffer kann juenger sein als die Fundliste: nach dem
    // Einfuegen von Zeilen steht auf der Fundzeile eine ANDERE Anweisung.
    // Die Meldung nennt das Ziel - damit laesst sich das pruefen.

    // Ziel und '+'-Zahl aus der Meldung von SCA044 ('Concat (3 x ''+'') ->
    // Format(...) Ziel', uConcatToFormat). False (Ziel '', Zahl -1), wenn
    // die Meldung nicht diese Form hat.
    class function ConcatFindingTarget(const AMessage: string;
      out ATarget: string; out APlusCount: Integer): Boolean; static;
    // Ziel aus der Meldung von SCA003 ('Ziel  [Fix ...]', ein Aufruf als
    // 'Kopf()'; uSQLInjection). '' ohne diese Form.
    class function SqlFindingTarget(const AMessage: string): string; static;
    // Vergleichsform eines Knotennamens: getrimmt, ab der ersten '(' nur
    // noch '()' - wie SCA003 einen Aufruf meldet ('Q.SQL.Add()').
    class function TargetKey(const AName: string): string; static;
    // True, wenn beide Ziele reines ASCII sind (jedes Zeichen #0..#127) -
    // nur dann vergleicht der Fund-Abgleich sie (Review-Nachlese
    // 2026-10-09). Das Ziel der Meldung stammt aus dem Scan, der eine
    // UTF-8-Datei ohne BOM als ANSI liest (TParser2.ParseFile:
    // LoadFromFile ohne Encoding); der Knoten stammt aus TSourcePlaces,
    // das dieselbe Datei als UTF-8 liest (LoadFileSmart bzw. der Editor-
    // Puffer). Ein Umlaut im Ziel unterschiede sich so trotz gleicher
    // Anweisung. Sonst bleibt nur die '+'-Gegenprobe. Der Aufrufer gibt
    // die Vergleichsformen (TargetKey): bei einem Aufruf zaehlen die
    // Argumente nicht.
    class function TargetsComparable(const A, B: string): Boolean; static;
    // Nur die Zeichen #0..#127 von S - die Ersatzprobe, wenn ein Ziel
    // Nicht-ASCII traegt: der Scan liest UTF-8 ohne BOM als ANSI, der
    // ASCII-Anteil stimmt in beiden Lesarten ueberein (Review nach
    // Bereichen 2026-10-10, Nit 25/26).
    class function AsciiOnly(const S: string): string; static;

    // Das Query-Objekt eines SQL-Ziels: 'Query.SQL.Text' -> 'Query',
    // 'FDQuery1.SQL.Add' -> 'FDQuery1', 'Cmd.CommandText' -> 'Cmd',
    // 'DM.SQLQuery1.SQL.Text' -> 'DM.SQLQuery1' (das Glied '.SQL' ganz,
    // nicht der Anfang von '.SQLQuery1'). Ein blosser Bezeichner
    // ('SQLText') kommt unveraendert zurueck - das ist KEIN Query-Objekt
    // (HasQueryObject).
    class function QueryObjectOf(const ATarget: string): string; static;
    // True, wenn das Ziel ein Glied '.SQL' oder '.CommandText' traegt -
    // nur dann hat QueryObjectOf ein Objekt mit ParamByName.
    class function HasQueryObject(const ATarget: string): Boolean; static;

    // Einrueckung aus dem Zeilenanfang vor einer Anweisung: Tabs bleiben
    // Tabs, jedes andere Zeichen wird ein Leerzeichen (Review 2026-10-07,
    // Minor 31) - die Einrueckung der SQL-Vorlage (uRdxSqlTemplate).
    class function IndentTextOf(const ALinePrefix: string): string; static;

    // Rahmenwerk einer Datei aus ihren uses-Eintraegen (qualifizierte
    // Namen 'Vcl.*' / 'FMX.*').
    class function DetectFramework(
      const AUnitNames: TArray<string>): TRdxFramework; static;
    // True, wenn AShortName als Eintrag vorkommt - unqualifiziert oder
    // als letztes Segment ('SysUtils' trifft 'System.SysUtils').
    class function HasUnit(const AUnitNames: TArray<string>;
      const AShortName: string): Boolean; static;

    // ---- uses-Klausel ergaenzen (AH19: Format() braucht System.SysUtils) --

    // Der Name, unter dem eine RTL-Unit in DIESE Datei passt: der
    // qualifizierte, wenn die Datei Delphi-Unit-Scopes schreibt (ein
    // Eintrag mit RTL-Scope, IsRtlScopedName) oder noch keinen uses-
    // Eintrag hat; sonst der Kurzname (eine Datei, die 'Classes, Windows'
    // oder 'Classes, Generics.Collections' schreibt, bekommt 'SysUtils' -
    // ein Punkt allein ist kein Scope; Review 2026-10-07, Minor 35). Eine
    // Datei mit FPC-Weiche (LineLooksFpcAware) bekommt immer den
    // Kurznamen - das entscheidet der Aufrufer, er kennt die Zeilen.
    class function UsesNameFor(const AUnitNames: TArray<string>;
      const AShortName, AQualifiedName: string): string; static;
    // True fuer einen qualifizierten Namen unter einem Delphi-Unit-Scope
    // (System., Winapi., Vcl., FMX., Data., ...). 'Generics.Collections'
    // (gibt es auch unter FPC) und 'MyLib.Utils' sind keiner.
    class function IsRtlScopedName(const AName: string): Boolean; static;
    // True, wenn die Zeile eine FPC-Weiche oder einen FPC-Modus traegt
    // ('{$IFDEF FPC}', '{$IFNDEF FPC}', '{$IF DEFINED(FPC)}', '{$mode ..}',
    // auch in der Form '(*$..*)'). FPC 3.2 kennt keine Unit-Scopes - eine
    // solche Datei bekommt 'SysUtils', nie 'System.SysUtils'. Ein Treffer
    // in einem Kommentar macht nur vorsichtig, nie falsch: Delphi loest
    // den Kurznamen ueber die Vorgabe-Scopes ebenso auf.
    class function LineLooksFpcAware(const ALine: string): Boolean; static;
    // Nachlauf hinter dem LETZTEN Eintrag einer uses-Klausel: ARest ist
    // der Zeilenrest direkt hinter dessen Namen. Liefert die Zahl der
    // Zeichen, die zum Eintrag gehoeren - ein 'in'-Pfad ('in ''x.pas''')
    // und Block-Kommentare ohne '$' ('{Form1}' der .dpr) -, wenn danach
    // (hinter Leerraum) das ';' auf DERSELBEN Zeile folgt; 0 = das ';'
    // folgt direkt. Dahinter darf ', Name' angehaengt werden. -1 bei allem
    // anderen ('//'-Kommentar, Direktive, kein ';' auf der Zeile, ein
    // weiterer Eintrag) - dann bleibt nur, VOR dem letzten einzufuegen
    // (Review 2026-10-07, Minor 42 / strittiger Nit 5).
    class function UsesTailLength(const ARest: string): Integer; static;
    // True, wenn die Namen case-insensitiv aufsteigend sortiert sind -
    // dasselbe Kriterium wie SCA142 UnsortedUses (CompareText).
    class function IsSortedUses(const AUnitNames: TArray<string>): Boolean;
      static;
    // Index des Eintrags, VOR dem ANewName einzufuegen ist, damit eine
    // sortierte Liste sortiert bleibt; Length(AUnitNames) = anhaengen.
    // Eine unsortierte Liste bekommt den Neuen vorn (0) - dort faellt
    // er dem Leser am ehesten auf und erzeugt keinen neuen SCA142-Fund,
    // denn der steht dort schon.
    class function SortedInsertIndex(const AUnitNames: TArray<string>;
      const ANewName: string): Integer; static;
  end;

// Teilt einen Zeichenketten-Quelltext ('..'-Teile und #-Codes ohne
// Leerraum dazwischen - so bauen ihn EncodeLiteral und der Formatstring
// von BuildFormatCall) mit ' + ' in Literale von hoechstens 255
// Elementen: bis Delphi 11 traegt ein Literal nicht mehr (E2056; Delphi
// 12 erlaubt mehr), und eine Hilfe darf Code fuer aeltere Compiler nicht
// brechen - SCA074 sperrt dieselbe Grenze (Review FB, R2-02: aus Ketten
// mit kurzen Literalen wurde ein Formatstring von 376 Zeichen). Der Wert
// bleibt gleich, 'a' + 'b' ist ein konstanter Ausdruck. Ein Lauf aus
// '..'-Teilen und #-Codes zaehlt als EIN Literal; ein Zeichen bzw. #-Code
// zaehlt vorsichtig so viel wie in UTF-8 (1 bis 3, ein Surrogat-Paar 4):
// ob Delphi bis 11 Zeichen oder die UTF-8-Bytes seiner inneren Form
// zaehlt, ist hier nicht belegt (Nachpruefung FB) - die Teilung kostet
// nichts, ein Literal ueber der Grenze den Bau. Geteilt wird bevorzugt hinter
// einem Leerzeichen, wenn das Literal dort mindestens halb voll ist,
// nie in einem Surrogat-Paar. Ein Text anderer Form kommt unveraendert
// zurueck. Frei statt in TRdxRecipes (Charge FB): die Klasse traegt schon
// mehr Methoden, als der Selbstscan erlaubt (SCA138), und der Baustein
// braucht keinen ihrer Teile.
function SplitLongLiteral(const ASource: string): string;

implementation

uses
  System.SysUtils,
  uRdxCodeMap;   // IsIdentStart, IsIdentChar (Zeichen > #127 wie der Core)

const
  // Paar-Regel von LooksLikeSql (Review 2026-10-07, Nit 6): je Verb die
  // Strukturwoerter, die grammatisch dahinter stehen koennen.
  SQL_SELECT_WORDS: array[0..3] of string = ('from', 'where', 'join', 'into');
  SQL_DELETE_WORDS: array[0..1] of string = ('from', 'where');
  SQL_INSERT_WORDS: array[0..1] of string = ('into', 'values');
  // DDL: create/alter/drop/truncate, dann hoechstens Zusatzwoerter
  // ('or replace', 'unique', 'global temporary', 'clustered'), dann das
  // Objekt. 'Create or open a file' und 'Create temp file' sind kein SQL.
  SQL_DDL_VERBS: array[0..3] of string = ('create', 'alter', 'drop', 'truncate');
  SQL_DDL_MODIFIERS: array[0..10] of string = (
    'or', 'replace', 'alter', 'unique', 'temporary', 'temp', 'global',
    'local', 'clustered', 'nonclustered', 'materialized');
  SQL_DDL_OBJECTS: array[0..10] of string = (
    'table', 'index', 'view', 'procedure', 'trigger', 'function',
    'database', 'sequence', 'schema', 'domain', 'generator');

function InList(const AValue: string; const AList: array of string): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := Low(AList) to High(AList) do
    if AList[i] = AValue then
      Exit(True);
end;

function HexValue(C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

function CharStr(C: Char): string;
// Ein Zeichen als String: TStringBuilder.Append(Char) ist unter FPC
// (delphiunicode) mehrdeutig, Append(string) nicht.
begin
  Result := C;
end;

function LastSegment(const AName: string): string;
var
  P : Integer;
begin
  P := LastDelimiter('.', AName);
  Result := Copy(AName, P + 1, MaxInt);
end;

{ TRdxRecipes }

class function TRdxRecipes.MakePart(const ARole, AText: string;
  AValueType: TRefactorValueType; const AResolved, AArgResolved: string): TRdxPart;
begin
  Result.Role         := ARole;
  Result.Text         := AText;
  Result.ValueType    := AValueType;
  Result.Resolved     := AResolved;
  Result.ArgResolved  := AArgResolved;
  Result.HeadResolved := '';
  Result.InWith       := False;
  Result.Shadowed     := False;
end;

// Das Literal ab S[AAt] (ein Quote): der Rohtext zwischen den Quotes - ein
// verdoppeltes '' bleibt '' -, AAt rueckt hinter das schliessende Quote.
// False, wenn keines kommt (AAt steht dann hinter dem Text). Geteilt von
// DecodeLiteral, AppendLiteralSource, BlankLiterals und CollapseCode - bis
// Charge R8 (2026-10-14) je eine eigene Schleife.
function QuotedSpan(const S: string; var AAt: Integer;
  out AInner: string): Boolean;
var
  Start : Integer;
begin
  Result := False;
  AInner := '';
  Start := AAt + 1;
  AAt := Start;
  while AAt <= Length(S) do
  begin
    if S[AAt] <> '''' then
      Inc(AAt)
    else if (AAt < Length(S)) and (S[AAt + 1] = '''') then
      Inc(AAt, 2)
    else
    begin
      AInner := Copy(S, Start, AAt - Start);
      Inc(AAt);
      Exit(True);
    end;
  end;
end;

// Wert einer Ziffer zur Basis ABase (10 oder 16), -1 fuer alles andere.
function DigitValue(C: Char; ABase: Integer): Integer;
begin
  if ABase = 16 then
    Result := HexValue(C)
  else if CharInSet(C, ['0'..'9']) then
    Result := Ord(C) - Ord('0')
  else
    Result := -1;
end;

// Ein Zeichencode ab S[AAt] = '#': dezimal oder $hex nach ACode, AAt rueckt
// hinter die Ziffern. False ohne Ziffer oder ueber $FFFF (ein Zeichen).
function CharCodeSpan(const S: string; var AAt: Integer;
  out ACode: Integer): Boolean;
var
  Base, Digits, D : Integer;
begin
  Result := False;
  ACode := 0;
  Digits := 0;
  Base := 10;
  Inc(AAt);
  if (AAt <= Length(S)) and (S[AAt] = '$') then
  begin
    Base := 16;
    Inc(AAt);
  end;
  while AAt <= Length(S) do
  begin
    D := DigitValue(S[AAt], Base);
    if D < 0 then Break;
    ACode := ACode * Base + D;
    Inc(AAt);
    Inc(Digits);
    if ACode > $FFFF then Exit;
  end;
  Result := Digits > 0;
end;

class function TRdxRecipes.DecodeLiteral(const ASource: string;
  out AValue: string): Boolean;
var
  SB    : TStringBuilder;
  i     : Integer;
  Code  : Integer;
  Inner : string;
begin
  Result := False;
  AValue := '';
  SB := TStringBuilder.Create;
  try
    i := 1;
    while i <= Length(ASource) do
    begin
      if ASource[i] <= ' ' then
        Inc(i)
      else if ASource[i] = '''' then
      begin
        if not QuotedSpan(ASource, i, Inner) then Exit;
        SB.Append(StringReplace(Inner, '''''', '''', [rfReplaceAll]));
      end
      else if ASource[i] = '#' then
      begin
        if not CharCodeSpan(ASource, i, Code) then Exit;
        SB.Append(CharStr(Char(Code)));
      end
      else
        Exit;
    end;
    AValue := SB.ToString;
    Result := True;
  finally
    SB.Free;
  end;
end;

class function TRdxRecipes.EncodeLiteral(const AValue: string): string;
var
  SB      : TStringBuilder;
  i       : Integer;
  InQuote : Boolean;
  C       : Char;
begin
  if AValue = '' then Exit('''''');
  SB := TStringBuilder.Create;
  try
    InQuote := False;
    for i := 1 to Length(AValue) do
    begin
      C := AValue[i];
      if C < ' ' then
      begin
        if InQuote then
        begin
          SB.Append('''');
          InQuote := False;
        end;
        SB.Append('#');
        SB.Append(IntToStr(Ord(C)));
      end
      else
      begin
        if not InQuote then
        begin
          SB.Append('''');
          InQuote := True;
        end;
        if C = '''' then
          SB.Append('''''')
        else
          SB.Append(CharStr(C));
      end;
    end;
    if InQuote then
      SB.Append('''');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TRdxRecipes.CollapseWhitespace(const AText: string): string;
var
  SB        : TStringBuilder;
  i         : Integer;
  LastWhite : Boolean;
  C         : Char;
begin
  SB := TStringBuilder.Create;
  try
    LastWhite := True;   // fuehrenden Leerraum verschlucken
    for i := 1 to Length(AText) do
    begin
      C := AText[i];
      if C > ' ' then
      begin
        SB.Append(CharStr(C));
        LastWhite := False;
      end
      else if not LastWhite then
      begin
        SB.Append(' ');
        LastWhite := True;
      end;
    end;
    Result := TrimRight(SB.ToString);
  finally
    SB.Free;
  end;
end;

// True, wenn hinter Index AFrom eines der Woerter aus AList vorkommt.
function WordFollows(const AWords: TArray<string>; AFrom: Integer;
  const AList: array of string): Boolean;
var
  k : Integer;
begin
  Result := False;
  for k := AFrom + 1 to High(AWords) do
    if InList(AWords[k], AList) then
      Exit(True);
end;

// True, wenn hinter dem DDL-Verb bei Index AVerb - nach Zusatzwoertern -
// direkt ein DDL-Objekt steht ('DROP TABLE', 'CREATE OR REPLACE VIEW').
function DdlObjectFollows(const AWords: TArray<string>; AVerb: Integer): Boolean;
var
  k : Integer;
begin
  k := AVerb + 1;
  while (k <= High(AWords)) and InList(AWords[k], SQL_DDL_MODIFIERS) do
    Inc(k);
  Result := (k <= High(AWords)) and InList(AWords[k], SQL_DDL_OBJECTS);
end;

// Die Woerter (nur a..z) des klein geschriebenen Texts, in Reihenfolge -
// je Wort ein Copy statt Zeichen fuer Zeichen (SCA110).
function LowerWordsOf(const AValue: string): TArray<string>;
var
  Lowered  : string;
  i, Start : Integer;
  Count    : Integer;
begin
  Result := nil;
  Count := 0;
  Lowered := LowerCase(AValue);
  i := 1;
  while i <= Length(Lowered) do
  begin
    if not CharInSet(Lowered[i], ['a'..'z']) then
    begin
      Inc(i);
      Continue;
    end;
    Start := i;
    while (i <= Length(Lowered)) and CharInSet(Lowered[i], ['a'..'z']) do
      Inc(i);
    // Verdoppelnd wachsen, am Ende zuschneiden (SCA157).
    if Count = Length(Result) then
      SetLength(Result, 2 * Count + 4);
    Result[Count] := Copy(Lowered, Start, i - Start);
    Inc(Count);
  end;
  SetLength(Result, Count);
end;

// Paar-Regel von LooksLikeSql fuer das Wort bei Index AIndex: ein
// Statement-Verb mit einem Strukturwort, das grammatisch zu ihm passt und
// dahinter steht, oder ein DDL-Verb mit seinem Objekt.
function SqlPairAt(const AWords: TArray<string>; AIndex: Integer): Boolean;
var
  W : string;
begin
  W := AWords[AIndex];
  if W = 'select' then Exit(WordFollows(AWords, AIndex, SQL_SELECT_WORDS));
  if W = 'delete' then Exit(WordFollows(AWords, AIndex, SQL_DELETE_WORDS));
  if W = 'insert' then Exit(WordFollows(AWords, AIndex, SQL_INSERT_WORDS));
  if W = 'merge' then Exit(WordFollows(AWords, AIndex, ['into']));
  if W = 'update' then Exit(WordFollows(AWords, AIndex, ['set']));
  Result := InList(W, SQL_DDL_VERBS) and DdlObjectFollows(AWords, AIndex);
end;

class function TRdxRecipes.LooksLikeSql(const AValue: string): Boolean;
var
  Words : TArray<string>;
  i     : Integer;
begin
  Result := False;
  Words := LowerWordsOf(AValue);
  for i := 0 to High(Words) do
    if SqlPairAt(Words, i) then
      Exit(True);
end;

{ ---- Kompilat-Regel (AH20) ---- }

const
  NON_UNICODE_STRING_TYPES: array[0..6] of string = (
    'ansistring', 'rawbytestring', 'utf8string', 'shortstring', 'rawutf8',
    'pansichar', 'ansichar');
  // RTL-Aliase auf string, die der Core-Resolver nicht als String kennt.
  STRING_ALIAS_TYPES: array[0..3] of string = (
    'tfilename', 'tcaption', 'tcomponentname', 'thintstring');
  SIGNED_INT_TYPES: array[0..12] of string = (
    'integer', 'int64', 'smallint', 'shortint', 'longint', 'nativeint',
    'int32', 'int16', 'int8', 'byte', 'word', 'uint8', 'uint16');
  UNSIGNED_INT_TYPES: array[0..7] of string = (
    'cardinal', 'longword', 'dword', 'uint32', 'uint64', 'qword',
    'nativeuint', 'ptruint');
  // Casts auf Zahl/Boolean: in einer String-Kette nur hinter einem
  // Variant uebersetzbar - und dann scheitert %s.
  NUMERIC_CAST_HEADS: array[0..21] of string = (
    'integer', 'cardinal', 'int64', 'uint64', 'word', 'byte', 'smallint',
    'shortint', 'longint', 'longword', 'nativeint', 'nativeuint', 'dword',
    'single', 'double', 'extended', 'currency', 'boolean', 'bytebool',
    'wordbool', 'longbool', 'tdatetime');
  // Aufrufe mit Zahl-/Boolean-Ergebnis: dasselbe Signal wie ein Zahl-Cast
  // (Review 2026-10-07, Minor 13). Eine gleichnamige Projektfunktion mit
  // String-Ergebnis wird damit nur vorsichtig gesperrt.
  NUMERIC_FUNC_HEADS: array[0..18] of string = (
    'length', 'ord', 'pos', 'posex', 'round', 'trunc', 'high', 'low',
    'sizeof', 'abs', 'strtoint', 'strtointdef', 'strtoint64',
    'strtoint64def', 'succ', 'pred', 'strtofloat', 'strtofloatdef',
    'trystrtoint');
  KNOWN_STRING_CONSTS: array[0..8] of string = (
    'slinebreak', 'pathdelim', 'drivedelim', 'pathsep', 'emptystr',
    'lineending', 'directoryseparator', 'pathseparator', 'driveseparator');
  // Jenseits von uRefactorConcat.KNOWN_STRING_FUNCS (die der Core schon
  // als rvString liefert): Dateinamen, Teilstrings, Ersetzen, Codecs.
  EXT_STRING_FUNCS: array[0..47] of string = (
    'extractfilename', 'extractfilepath', 'extractfileext', 'extractfiledir',
    'extractfiledrive', 'changefileext', 'changefilepath',
    'includetrailingpathdelimiter', 'excludetrailingpathdelimiter',
    'includetrailingbackslash', 'excludetrailingbackslash', 'expandfilename',
    'expanduncfilename', 'extractshortpathname', 'extractrelativepath',
    'getcurrentdir', 'copy', 'stringreplace', 'chr',
    'ansireplacestr', 'replacestr', 'replacetext', 'ansireplacetext',
    'leftstr', 'rightstr', 'midstr', 'ansileftstr', 'ansirightstr',
    'ansimidstr', 'getenumname', 'vartostr', 'vartostrdef', 'utf8tostring',
    'utf8decode', 'utf8tounicodestring', 'wraptext', 'adjustlinebreaks',
    'dequotedstr', 'ansidequotedstr', 'currtostrf', 'formatcurr',
    'getenvironmentvariable', 'paramstr', 'reversestring',
    'ansireversestring', 'stuffstring', 'guidtostring', 'concat');
  // Mit Nicht-Unicode-Ergebnis (RawByteString, UTF8String, AnsiString) -
  // aus EXT_STRING_FUNCS herausgeloest (Review 2026-10-07, Minor 12).
  EXT_ANSI_STRING_FUNCS: array[0..3] of string = (
    'utf8encode', 'ansitoutf8', 'utf8toansi', 'strpas');
  // Operanden, die FormatBuf ohne Laenge anhaengt (vtChar, vtWideChar,
  // vtString): sie gehen als string(x) in den Aufruf (Minor 10).
  CHAR_LIKE_TYPES: array[0..2] of string = ('char', 'widechar', 'shortstring');
  TPATH_STRING_FUNCS: array[0..7] of string = (
    'tpath.combine', 'tpath.getfilename', 'tpath.getdirectoryname',
    'tpath.getextension', 'tpath.getfilenamewithoutextension',
    'tpath.gettemppath', 'tpath.changeextension', 'tpath.getfullpath');
  KNOWN_UNIT_QUALIFIERS: array[0..5] of string = (
    'sysutils', 'system.sysutils', 'strutils', 'system.strutils',
    'ioutils', 'system.ioutils');
  VARIANT_TELLS: array[0..7] of string = (
    'value', 'asvariant', 'fieldvalues', 'null', 'unassigned', 'true',
    'false', 'nil');

// Erste Stelle hinter den Ziffern eines Zeichencodes ab AFrom (hinter dem
// '#'): ein '$' und dann Ziffern und Hex-Buchstaben - ohne Pruefung der
// Basis, wie BlankLiterals den Code nur ueberspringt.
function SkipCodeDigits(const S: string; AFrom: Integer): Integer;
begin
  Result := AFrom;
  if (Result <= Length(S)) and (S[Result] = '$') then
    Inc(Result);
  while (Result <= Length(S))
     and CharInSet(S[Result], ['0'..'9', 'A'..'F', 'a'..'f']) do
    Inc(Result);
end;

// Literale ('...' mit '' und #nn) durch 'x' ersetzen, damit Klammern und
// Operatoren in Strings die Formpruefung nicht stoeren. Ein Literal ohne
// schliessendes Quote reicht bis zum Ende (QuotedSpan).
function BlankLiterals(const S: string): string;
var
  SB    : TStringBuilder;
  i, n  : Integer;
  Inner : string;
begin
  SB := TStringBuilder.Create;
  try
    n := Length(S);
    i := 1;
    while i <= n do
    begin
      if S[i] = '''' then
      begin
        QuotedSpan(S, i, Inner);
        SB.Append('x');
      end
      else if (S[i] = '#') and (i < n) and CharInSet(S[i + 1], ['0'..'9', '$']) then
      begin
        i := SkipCodeDigits(S, i + 1);
        SB.Append('x');
      end
      else
      begin
        SB.Append(CharStr(S[i]));
        Inc(i);
      end;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Kopf eines Aufrufs (Text vor der ersten '('), klein; '' wenn die
// Klammer hinter dem Kopf nicht den ganzen Term abschliesst.
function CallHeadOf(const AText: string): string;
var
  S     : string;
  P, i  : Integer;
  Depth : Integer;
begin
  Result := '';
  S := BlankLiterals(Trim(AText));
  P := Pos('(', S);
  if (P < 2) or (S[Length(S)] <> ')') then Exit;
  Depth := 0;
  for i := P to Length(S) do
  begin
    if S[i] = '(' then Inc(Depth)
    else if S[i] = ')' then
    begin
      Dec(Depth);
      if (Depth = 0) and (i < Length(S)) then Exit;   // 'Foo(a).Bar(b)'
    end;
  end;
  if Depth <> 0 then Exit;
  Result := LowerCase(Trim(Copy(S, 1, P - 1)));
end;

class function TRdxRecipes.IsPlainIdent(const AText: string): Boolean;
var
  i : Integer;
begin
  Result := (AText <> '') and IsIdentStart(AText[1]);
  for i := 2 to Length(AText) do
    if not IsIdentChar(AText[i]) then Exit(False);
end;

// Die Klammergruppe ab S[AAt] ('(' oder '[', beide Arten in einer Bilanz)
// ueberspringen; AAt rueckt dahinter. False, wenn sie nicht schliesst.
function SkipGroup(const S: string; var AAt: Integer): Boolean;
var
  Depth : Integer;
begin
  Depth := 0;
  repeat
    if CharInSet(S[AAt], ['(', '[']) then
      Inc(Depth)
    else if CharInSet(S[AAt], [')', ']']) then
      Dec(Depth);
    Inc(AAt);
  until (Depth = 0) or (AAt > Length(S));
  Result := Depth = 0;
end;

// Einen Bezeichner ab S[AAt] ueberspringen (ein '&' davor erlaubt: &Type,
// Item.&End); AAt rueckt dahinter. False, wenn dort keiner beginnt.
function SkipIdent(const S: string; var AAt: Integer): Boolean;
begin
  if (AAt <= Length(S)) and (S[AAt] = '&') then
    Inc(AAt);
  Result := (AAt <= Length(S)) and IsIdentStart(S[AAt]);
  while (AAt <= Length(S)) and IsIdentChar(S[AAt]) do
    Inc(AAt);
end;

// Die fuehrende Klammergruppe ab S[1] - nur mit Member-/Index-/Deref-
// Zugriff dahinter: '(Sender as TButton).Caption' ja, '(a + b)' nein. AAt
// rueckt hinter die Gruppe.
function LeadingGroupOk(const S: string; var AAt: Integer): Boolean;
var
  k : Integer;
begin
  Result := False;
  if not SkipGroup(S, AAt) then Exit;
  k := AAt;
  while (k <= Length(S)) and (S[k] <= ' ') do Inc(k);
  Result := (k <= Length(S)) and CharInSet(S[k], ['.', '[', '^']);
end;

// Ein Schritt der Formpruefung (IsOperandShape) hinter einem Bezeichner,
// ab S[AAt]: Leerraum, '.' (dahinter wieder ein Bezeichner - AWantIdent),
// '^' oder eine Klammergruppe. False bei allem anderen.
function SuffixStep(const S: string; var AAt: Integer;
  var AWantIdent: Boolean): Boolean;
begin
  Result := True;
  if S[AAt] <= ' ' then
    Inc(AAt)
  else if S[AAt] = '.' then
  begin
    Inc(AAt);
    AWantIdent := True;
  end
  else if S[AAt] = '^' then
    Inc(AAt)
  else if CharInSet(S[AAt], ['(', '[']) then
    Result := SkipGroup(S, AAt)
  else
    Result := False;
end;

class function TRdxRecipes.IsOperandShape(const AText: string): Boolean;
var
  S         : string;
  i         : Integer;
  WantIdent : Boolean;
begin
  Result := False;
  S := BlankLiterals(Trim(AText));
  if S = '' then Exit;
  i := 1;
  WantIdent := True;
  if S[1] = '(' then
  begin
    if not LeadingGroupOk(S, i) then Exit;
    WantIdent := False;
  end;
  while i <= Length(S) do
    if WantIdent then
    begin
      if not SkipIdent(S, i) then Exit;
      WantIdent := False;
    end
    else if not SuffixStep(S, i, WantIdent) then
      Exit;
  Result := not WantIdent;
end;

// 'DS[''Name'']': ein Bezeichner, direkt mit einem String-Literal
// indiziert, nichts dahinter - TDataSet.FieldValues (Default-Property,
// Variant). Ein TDictionary<string, string> sieht genauso aus und wird
// mitgesperrt (bekannte Grenze).
function IsStringIndexedIdent(const S: string): Boolean;
var
  i, n  : Integer;
  Inner : string;
begin
  Result := False;
  n := Length(S);
  i := 1;
  if (n = 0) or not IsIdentStart(S[1]) then Exit;
  while (i <= n) and IsIdentChar(S[i]) do Inc(i);
  while (i <= n) and (S[i] <= ' ') do Inc(i);
  if (i > n) or (S[i] <> '[') or (S[n] <> ']') then Exit;
  Inner := Trim(Copy(S, i + 1, n - i - 1));
  Result := (Length(Inner) >= 2) and (Inner[1] = '''')
    and (Inner[Length(Inner)] = '''')
    and (Pos('''', Copy(Inner, 2, Length(Inner) - 2)) = 0);
end;

class function TRdxRecipes.HasVariantTell(const AText: string): Boolean;
var
  S        : string;
  i, n     : Integer;
  Start    : Integer;
  Depth    : Integer;
  Last     : string;
  Head     : string;
begin
  S := BlankLiterals(Trim(AText));
  n := Length(S);
  Depth := 0;
  Last := '';
  Head := '';
  i := 1;
  while i <= n do
  begin
    if (Depth = 0) and IsIdentStart(S[i]) then
    begin
      Start := i;
      while (i <= n) and IsIdentChar(S[i]) do
        Inc(i);
      Last := Copy(S, Start, i - Start);
      if Head = '' then Head := Last;
      Continue;
    end;
    if CharInSet(S[i], ['(', '[']) then Inc(Depth)
    else if CharInSet(S[i], [')', ']']) then Dec(Depth);
    Inc(i);
  end;
  Head := LowerCase(Head);
  Result := InList(LowerCase(Last), VARIANT_TELLS)
    or (Head = 'variant') or (Head = 'olevariant')
    or IsStringIndexedIdent(Trim(AText));
end;

class function TRdxRecipes.HeadIdentOf(const AText: string): string;
var
  S        : string;
  i, Start : Integer;
begin
  Result := '';
  S := Trim(AText);
  i := 1;
  if (i <= Length(S)) and (S[i] = '&') then Inc(i);
  if (i > Length(S)) or not IsIdentStart(S[i]) then Exit;
  Start := i;
  while (i <= Length(S)) and IsIdentChar(S[i]) do
    Inc(i);
  Result := Copy(S, Start, i - Start);
end;

class function TRdxRecipes.IsKnownStringConst(const AText: string): Boolean;
var
  S    : string;
  Dot  : Integer;
  Qual : string;
begin
  S := LowerCase(Trim(AText));
  Dot := LastDelimiter('.', S);
  if Dot > 0 then
  begin
    Qual := Copy(S, 1, Dot - 1);
    S := Copy(S, Dot + 1, MaxInt);
    if not InList(Qual, KNOWN_UNIT_QUALIFIERS) then Exit(False);
  end;
  Result := InList(S, KNOWN_STRING_CONSTS);
end;

// Aufrufkopf (CallHeadOf) ohne RTL-Unit-Qualifizierer: 'sysutils.copy' ->
// 'copy'; '' bei einem fremden Qualifizierer ('obj.extractfilename' ist
// eine Methode unbekannten Typs) oder wenn kein Aufruf vorliegt.
function RtlHeadOf(const AHead: string): string;
var
  Dot : Integer;
begin
  Result := AHead;
  Dot := LastDelimiter('.', Result);
  if Dot = 0 then Exit;
  if InList(Copy(Result, 1, Dot - 1), KNOWN_UNIT_QUALIFIERS) then
    Result := Copy(Result, Dot + 1, MaxInt)
  else
    Result := '';
end;

class function TRdxRecipes.IsKnownStringFunc(const AText: string): Boolean;
var
  Head : string;
begin
  Result := False;
  Head := CallHeadOf(AText);
  if Head = '' then Exit;
  if InList(Head, TPATH_STRING_FUNCS) then Exit(True);
  Head := RtlHeadOf(Head);
  Result := (Head <> '') and InList(Head, EXT_STRING_FUNCS);
end;

class function TRdxRecipes.IsKnownAnsiStringFunc(const AText: string): Boolean;
var
  Head : string;
begin
  Head := RtlHeadOf(CallHeadOf(AText));
  Result := (Head <> '') and InList(Head, EXT_ANSI_STRING_FUNCS);
end;

class function TRdxRecipes.IsNonUnicodeStringType(
  const ATypeLow: string): Boolean;
begin
  Result := InList(ATypeLow, NON_UNICODE_STRING_TYPES);
end;

// Urteil aus dem deklarierten Typ (Resolved), dem Typ des Kopf-
// Bezeichners (HeadResolved) und der Core-Rolle (ValueType), in dieser
// Reihenfolge; False, wenn alle drei schweigen. Ein leeres Resolved steht
// in keiner Liste und urteilt damit nie. Im with-Block (InWith) beweist
// ein Typ-Alias nichts - der Name kann ein Member sein.
function DeclaredVerdictOf(const APart: TRdxPart;
  out AVerdict: TRdxOperandVerdict): Boolean;
var
  R : string;
begin
  R := APart.Resolved;
  AVerdict := ovNoOperand;
  Result := True;
  if TRdxRecipes.IsNonUnicodeStringType(R) then
    AVerdict := ovAnsi
  else if (R = 'variant') or (R = 'olevariant') then
    AVerdict := ovVariantRisk
  else if InList(R, STRING_ALIAS_TYPES) and not APart.InWith then
    AVerdict := ovString
  // 'V.Name', 'V[0]' mit V: Variant - spaet gebunden, der Wert ist Variant.
  else if (APart.HeadResolved = 'variant')
     or (APart.HeadResolved = 'olevariant') then
    AVerdict := ovVariantRisk
  else if APart.ValueType = rvNonString then
    AVerdict := ovNonString
  else if APart.ValueType = rvString then
    AVerdict := ovString
  else
    Result := False;
end;

// Urteil aus dem Aufrufkopf (CallHeadOf): ein Cast auf einen Nicht-
// Unicode-String ('AnsiString(A)', 'AnsiChar(b)') urteilt wie die
// Deklaration (Minor 12), Zahl-Cast und Aufruf mit Zahl-Ergebnis sperren
// (Minor 13). False ohne Kopf oder bei einem anderen Kopf.
function CallHeadVerdictOf(const AHead: string;
  out AVerdict: TRdxOperandVerdict): Boolean;
begin
  AVerdict := ovNoOperand;
  Result := AHead <> '';
  if not Result then Exit;
  if TRdxRecipes.IsNonUnicodeStringType(AHead) then
    AVerdict := ovAnsi
  else if InList(AHead, NUMERIC_CAST_HEADS)
     or InList(AHead, NUMERIC_FUNC_HEADS) then
    AVerdict := ovNonString
  else
    Result := False;
end;

class function TRdxRecipes.JudgeOperand(
  const APart: TRdxPart): TRdxOperandVerdict;
var
  Text : string;
begin
  Text := Trim(APart.Text);
  if APart.Role = ROLE_LITERAL then Exit(ovString);
  if DeclaredVerdictOf(APart, Result) then Exit;
  if IsKnownAnsiStringFunc(Text) then Exit(ovAnsi);
  // Namensregeln nur ausserhalb eines with-Blocks (s. TRdxPart.InWith)
  // und nur, wenn keine Funktion der Unit den Namen verdeckt (Shadowed).
  if not APart.InWith and not APart.Shadowed
     and (IsKnownStringConst(Text) or IsKnownStringFunc(Text)) then
    Exit(ovString);
  if HasVariantTell(Text) then Exit(ovVariantRisk);
  if CallHeadVerdictOf(CallHeadOf(Text), Result) then Exit;
  if not IsOperandShape(Text) then Exit(ovNoOperand);
  Result := ovByCompiler;
end;

class function TRdxRecipes.ShadowNameOf(const AText: string): string;
var
  T : string;
begin
  T := Trim(AText);
  if IsPlainIdent(T) then
    Exit(LowerCase(T));
  Result := CallHeadOf(T);
  if not IsPlainIdent(Result) then
    Result := '';
end;

class function TRdxRecipes.IntegerSpec(const ATypeLow: string): string;
begin
  if InList(ATypeLow, SIGNED_INT_TYPES) then
    Result := '%d'
  else if InList(ATypeLow, UNSIGNED_INT_TYPES) then
    Result := '%u'
  else
    Result := '';
end;

class function TRdxRecipes.IntegerArgumentOf(const AText: string): string;
var
  T   : string;
  Low : string;
begin
  Result := '';
  T := CollapseWhitespace(AText);
  Low := LowerCase(T);
  if (Copy(Low, 1, 9) = 'inttostr(') and (Low[Length(Low)] = ')') then
    Result := Trim(Copy(T, 10, Length(T) - 10));
  if not IsPlainIdent(Result) then Result := '';
end;

class function TRdxRecipes.CollapseCode(const AText: string): string;
var
  SB        : TStringBuilder;
  i, Start  : Integer;
  LastWhite : Boolean;
  C         : Char;
  Inner     : string;
begin
  SB := TStringBuilder.Create;
  try
    LastWhite := True;
    i := 1;
    while i <= Length(AText) do
    begin
      C := AText[i];
      if C = '''' then
      begin
        // Das Literal wie geschrieben uebernehmen ('' bleibt ''); ohne
        // schliessendes Quote bis zum Ende (QuotedSpan).
        Start := i;
        QuotedSpan(AText, i, Inner);
        SB.Append(Copy(AText, Start, i - Start));
        LastWhite := False;
      end
      else if C > ' ' then
      begin
        SB.Append(CharStr(C));
        LastWhite := False;
        Inc(i);
      end
      else
      begin
        if not LastWhite then
          SB.Append(' ');
        LastWhite := True;
        Inc(i);
      end;
    end;
    Result := TrimRight(SB.ToString);
  finally
    SB.Free;
  end;
end;

{ ---- Formatstring aus den Literal-Quelltexten (AH22) ----
  Die Literale werden NICHT dekodiert und neu kodiert, sondern Token fuer
  Token uebernommen: '#$2103' bleibt '#$2103' (in einer ANSI-Datei waere
  das rohe Zeichen verloren), '#13' bleibt dezimal. Nur '%' in Quote-
  Teilen wird '%%', und ein '#37' (= '%') wird ''%%''. }

procedure AppendQuoted(var AFmt: string; var AInQuote: Boolean;
  const AInner: string);
begin
  if not AInQuote then
  begin
    AFmt := AFmt + '''';
    AInQuote := True;
  end;
  AFmt := AFmt + AInner;
end;

procedure AppendCode(var AFmt: string; var AInQuote: Boolean;
  const AToken: string);
begin
  if AInQuote then
  begin
    AFmt := AFmt + '''';
    AInQuote := False;
  end;
  AFmt := AFmt + AToken;
end;

// Ein Literal ab ASource[AAt] = Quote in den Formatstring: der Quelltext in
// den Quote-Teil, ein '%' als '%%'. False ohne schliessendes Quote.
function AppendQuotedSource(var AFmt: string; var AInQuote: Boolean;
  const ASource: string; var AAt: Integer): Boolean;
var
  Inner : string;
begin
  Result := QuotedSpan(ASource, AAt, Inner);
  if Result then
    AppendQuoted(AFmt, AInQuote, StringReplace(Inner, '%', '%%',
      [rfReplaceAll]));
end;

// Ein Zeichencode ab ASource[AAt] = '#' in den Formatstring: ein '#37'
// (= '%') als '%%' im Quote-Teil, sonst sein Quelltext als Code. False,
// wenn dort kein Zeichencode steht.
function AppendCharCode(var AFmt: string; var AInQuote: Boolean;
  const ASource: string; var AAt: Integer): Boolean;
var
  k, Code : Integer;
begin
  k := AAt;
  Result := CharCodeSpan(ASource, AAt, Code);
  if not Result then Exit;
  if Code = Ord('%') then
    AppendQuoted(AFmt, AInQuote, '%%')
  else
    AppendCode(AFmt, AInQuote, Copy(ASource, k, AAt - k));
end;

// Ein Schritt von AppendLiteralSource ab ASource[AAt]: Leerraum, ein
// Literal oder ein Zeichencode. False bei allem anderen.
function LiteralStep(var AFmt: string; var AInQuote: Boolean;
  const ASource: string; var AAt: Integer): Boolean;
begin
  if ASource[AAt] <= ' ' then
  begin
    Inc(AAt);
    Result := True;
  end
  else if ASource[AAt] = '''' then
    Result := AppendQuotedSource(AFmt, AInQuote, ASource, AAt)
  else if ASource[AAt] = '#' then
    Result := AppendCharCode(AFmt, AInQuote, ASource, AAt)
  else
    Result := False;
end;

// Haengt den Quelltext eines Literal-Terms ('a'#13#10'b', #$2103, 'x''y')
// an den Formatstring an. False bei allem, was kein Literal ist.
function AppendLiteralSource(var AFmt: string; var AInQuote: Boolean;
  const ASource: string): Boolean;
var
  i  : Integer;
  Ok : Boolean;
begin
  i := 1;
  Ok := True;
  while Ok and (i <= Length(ASource)) do
    Ok := LiteralStep(AFmt, AInQuote, ASource, i);
  Result := Ok;
end;

{ ---- Literal-Laenge (E2056, Review FB R2-02) ---- }

const
  // Elemente eines String-Literals bis Delphi 11 (E2056) - dieselbe Grenze
  // wie MAX_ASSERT_LITERAL der SCA074-Hilfe (uRdxSimpleFixes).
  MAX_LITERAL_ELEMENTS = 255;
  // Schliesst das Literal, verkettet, oeffnet ein neues.
  LITERAL_JOIN = ''' + ''';
  PLUS_JOIN    = ' + ';
  // UTF-8-Laenge eines Zeichens (ElementWidth): bis hier ein bzw. zwei
  // Bytes, darueber drei; ein Surrogat-Paar (ab U+10000) vier.
  UTF8_ONE_BYTE_BELOW  = $80;
  UTF8_TWO_BYTES_BELOW = $800;
  UTF8_BMP_BYTES       = 3;
  UTF8_PAIR_BYTES      = 4;

type
  // Zustand von SplitLongLiteral: die Ausgabe, die Elemente des laufenden
  // Literals, wo der offene '..'-Teil in der Ausgabe beginnt (Laenge der
  // Ausgabe hinter seinem Quote) und wo darin zuletzt ein Leerzeichen stand
  // (Laenge der Ausgabe dahinter, 0 = keins; BlankRun = Elemente bis dort).
  TRdxLiteralSplit = record
    Output    : string;
    Run       : Integer;
    SpanStart : Integer;
    BlankAt   : Integer;
    BlankRun  : Integer;
  end;

function IsHighSurrogateCh(C: Char): Boolean;
begin
  Result := (C >= #$D800) and (C <= #$DBFF);
end;

function IsLowSurrogateCh(C: Char): Boolean;
begin
  Result := (C >= #$DC00) and (C <= #$DFFF);
end;

// Elemente eines Zeichens bzw. Codes: vorsichtig seine Laenge in UTF-8 -
// ASCII eins, bis U+07FF zwei, sonst drei (ein einzelnes Surrogat auch).
// Bis zur Nachpruefung FB zaehlte alles ueber ASCII zwei; ein CJK-Zeichen
// (drei Bytes) liess so ein Literal von bis zu 381 Bytes zu.
function ElementWidth(ACode: Integer): Integer;
begin
  if ACode < UTF8_ONE_BYTE_BELOW then
    Result := 1
  else if ACode < UTF8_TWO_BYTES_BELOW then
    Result := 2
  else
    Result := UTF8_BMP_BYTES;
end;

// Vor einem Element mit AWidth Elementen: passt es nicht mehr ins
// laufende Literal, wird geteilt - steht der '..'-Teil noch leer da, vor
// seinem Quote; sonst hinter dem letzten Leerzeichen, wenn das Literal
// dort mindestens halb voll war; sonst hier.
procedure SplitBeforeElement(var S: TRdxLiteralSplit; AWidth: Integer);
begin
  if S.Run + AWidth <= MAX_LITERAL_ELEMENTS then Exit;
  if Length(S.Output) = S.SpanStart then
  begin
    Insert(PLUS_JOIN, S.Output, S.SpanStart);
    Inc(S.SpanStart, Length(PLUS_JOIN));
    S.Run := 0;
  end
  else if (S.BlankAt > 0) and (2 * S.BlankRun >= MAX_LITERAL_ELEMENTS) then
  begin
    Insert(LITERAL_JOIN, S.Output, S.BlankAt + 1);
    S.Run := S.Run - S.BlankRun;
  end
  else
  begin
    S.Output := S.Output + LITERAL_JOIN;
    S.Run := 0;
  end;
  S.BlankAt := 0;
end;

// Ein '..'-Teil ab ASource[AAt] (Quote): Element fuer Element in die
// Ausgabe ('' ist EIN Element, ein Surrogat-Paar auch - es zaehlt vier,
// wie in UTF-8). False ohne schliessendes Quote.
function SplitQuotedPart(var S: TRdxLiteralSplit; const ASource: string;
  var AAt: Integer): Boolean;
var
  Elem  : string;
  Width : Integer;
begin
  S.Output := S.Output + '''';
  S.SpanStart := Length(S.Output);
  S.BlankAt := 0;
  Inc(AAt);
  while AAt <= Length(ASource) do
  begin
    Width := ElementWidth(Ord(ASource[AAt]));
    Elem := ASource[AAt];
    if ASource[AAt] = '''' then
    begin
      if (AAt = Length(ASource)) or (ASource[AAt + 1] <> '''') then
      begin
        S.Output := S.Output + '''';
        Inc(AAt);
        Exit(True);
      end;
      Elem := '''''';
    end
    else if IsHighSurrogateCh(ASource[AAt]) and (AAt < Length(ASource))
       and IsLowSurrogateCh(ASource[AAt + 1]) then
    begin
      Elem := Copy(ASource, AAt, 2);
      Width := UTF8_PAIR_BYTES;
    end;
    SplitBeforeElement(S, Width);
    S.Output := S.Output + Elem;
    Inc(S.Run, Width);
    Inc(AAt, Length(Elem));
    if (Elem = ' ') or (Elem = #9) then
    begin
      S.BlankAt := Length(S.Output);
      S.BlankRun := S.Run;
    end;
  end;
  Result := False;
end;

// Ein #-Code ab ASource[AAt] (CharCodeSpan): passt er nicht mehr ins
// laufende Literal, beginnt mit ihm ein neues. False ohne Ziffer.
function SplitCharCode(var S: TRdxLiteralSplit; const ASource: string;
  var AAt: Integer): Boolean;
var
  Start, Code, Width : Integer;
begin
  Start := AAt;
  Result := CharCodeSpan(ASource, AAt, Code);
  if not Result then Exit;
  Width := ElementWidth(Code);
  if S.Run + Width > MAX_LITERAL_ELEMENTS then
  begin
    S.Output := S.Output + PLUS_JOIN;
    S.Run := 0;
  end;
  S.Output := S.Output + Copy(ASource, Start, AAt - Start);
  Inc(S.Run, Width);
  S.BlankAt := 0;
end;

function SplitLongLiteral(const ASource: string): string;
var
  S  : TRdxLiteralSplit;
  i  : Integer;
  Ok : Boolean;
begin
  S := Default(TRdxLiteralSplit);
  i := 1;
  Ok := ASource <> '';
  while Ok and (i <= Length(ASource)) do
    if ASource[i] = '''' then
      Ok := SplitQuotedPart(S, ASource, i)
    else if ASource[i] = '#' then
      Ok := SplitCharCode(S, ASource, i)
    else
      Ok := False;
  if Ok then
    Result := S.Output
  else
    Result := ASource;
end;

class function TRdxRecipes.NumericArgument(const APart: TRdxPart;
  out AArgument, ASpec: string): Boolean;
begin
  Result := False;
  AArgument := '';
  ASpec := '';
  // rvString = der Core hat 'IntToStr' als RTL bewiesen; eine gleichnamige
  // Funktion der Unit oder ein with-Block nimmt das zurueck - dann formatiert
  // vielleicht eine andere Routine, %d waere geraten (strittiger Minor 3).
  if (APart.Role <> ROLE_OPERAND) or (APart.ValueType <> rvString)
     or APart.InWith or (APart.ArgResolved = '') then Exit;
  ASpec := IntegerSpec(APart.ArgResolved);
  if ASpec = '' then Exit;
  AArgument := IntegerArgumentOf(APart.Text);
  Result := AArgument <> '';
  if not Result then ASpec := '';
end;

// Ein Zeichen AUSSERHALB eines Strings fuer TopLevelPlusCount: Klammer-
// tiefe ('(' und '[', nie unter 0) und '+' auf Tiefe 0.
procedure StepPlusCount(C: Char; var ADepth, ACount: Integer);
begin
  if (C = '(') or (C = '[') then
    Inc(ADepth)
  else if ((C = ')') or (C = ']')) and (ADepth > 0) then
    Dec(ADepth)
  else if (C = '+') and (ADepth = 0) then
    Inc(ACount);
end;

class function TRdxRecipes.TopLevelPlusCount(const AExpr: string): Integer;
var
  i, n  : Integer;
  Depth : Integer;
  InStr : Boolean;
  C     : Char;
begin
  if Trim(AExpr) = '' then Exit(-1);
  // Zeichen fuer Zeichen wie ScanConcat: '' im String ist ein Quote,
  // gezaehlt wird nur ausserhalb von Strings.
  Result := 0;
  Depth  := 0;
  InStr  := False;
  n := Length(AExpr);
  i := 1;
  while i <= n do
  begin
    C := AExpr[i];
    if (C = '''') and InStr and (i < n) and (AExpr[i + 1] = '''') then
      Inc(i)                  // '' im String: beide Quotes ueberspringen
    else if C = '''' then
      InStr := not InStr
    else if not InStr then
      StepPlusCount(C, Depth, Result);
    Inc(i);
  end;
end;

const
  // Meldung von SCA044 (uConcatToFormat, Report):
  // 'Concat (%d x ''+'') -> Format(...) %s'.
  CONCAT_MSG_HEAD = 'Concat (';
  CONCAT_MSG_MID  = ' x ''+'') -> Format(...) ';
  // Meldung von SCA003 (uSQLInjection, Report): Ziel, zwei Leerzeichen,
  // dann die Schaetzung in eckigen Klammern.
  SQL_MSG_ESTIMATE = '  [';

class function TRdxRecipes.ConcatFindingTarget(const AMessage: string;
  out ATarget: string; out APlusCount: Integer): Boolean;
var
  P : Integer;
begin
  Result     := False;
  ATarget    := '';
  APlusCount := -1;
  if Copy(AMessage, 1, Length(CONCAT_MSG_HEAD)) <> CONCAT_MSG_HEAD then Exit;
  P := Pos(CONCAT_MSG_MID, AMessage);
  if P = 0 then Exit;
  APlusCount := StrToIntDef(Copy(AMessage, Length(CONCAT_MSG_HEAD) + 1,
    P - Length(CONCAT_MSG_HEAD) - 1), -1);
  ATarget := Trim(Copy(AMessage, P + Length(CONCAT_MSG_MID), MaxInt));
  Result := (APlusCount >= 0) and (ATarget <> '');
  if not Result then
  begin
    ATarget    := '';
    APlusCount := -1;
  end;
end;

class function TRdxRecipes.SqlFindingTarget(const AMessage: string): string;
var
  P : Integer;
begin
  Result := '';
  P := Pos(SQL_MSG_ESTIMATE, AMessage);
  if P > 1 then
    Result := Trim(Copy(AMessage, 1, P - 1));
end;

class function TRdxRecipes.TargetKey(const AName: string): string;
var
  P : Integer;
begin
  Result := Trim(AName);
  P := Pos('(', Result);
  if P > 0 then
    Result := TrimRight(Copy(Result, 1, P - 1)) + '()';
end;

// True, wenn S nur Zeichen #0..#127 traegt (auch fuer '').
function IsPureAscii(const S: string): Boolean;
var
  C : Char;
begin
  Result := True;
  for C in S do
    if C > #127 then
      Exit(False);
end;

class function TRdxRecipes.AsciiOnly(const S: string): string;
var
  i, n : Integer;
begin
  SetLength(Result, Length(S));
  n := 0;
  for i := 1 to Length(S) do
    if S[i] <= #127 then
    begin
      Inc(n);
      Result[n] := S[i];
    end;
  SetLength(Result, n);
end;

class function TRdxRecipes.TargetsComparable(const A, B: string): Boolean;
begin
  Result := IsPureAscii(A) and IsPureAscii(B);
end;

// Typname eines ovAnsi-Operanden fuer Grund und AnsiChar-Ausnahme: der
// deklarierte Typ, sonst der Cast-Kopf ('AnsiString(A)' -> 'ansistring',
// 'AnsiChar(b)' -> 'ansichar'), sonst - RTL-Aufruf mit Ansi-Ergebnis wie
// UTF8Encode(S) - 'Ansi-Ergebnis' (Review 2026-10-07, Minor 12).
function AnsiTypeOf(const APart: TRdxPart; const ATxt: string): string;
begin
  if InList(APart.Resolved, NON_UNICODE_STRING_TYPES) then
    Exit(APart.Resolved);
  Result := CallHeadOf(ATxt);
  if not InList(Result, NON_UNICODE_STRING_TYPES) then
    Result := 'Ansi-Ergebnis';
end;

// True fuer einen Operanden, den FormatBuf ohne Laenge anhaengt: Char/
// WideChar/ShortString - deklariert, als Cast oder Chr(...). Ein #0 darin
// ginge im Format verloren, die Verkettung behaelt ihn; als string(x)
// laeuft er ueber vtUnicodeString mit Laenge (Review 2026-10-07, Minor 10).
function NeedsStringCast(const APart: TRdxPart; const ATxt: string): Boolean;
var
  Head : string;
begin
  Head := CallHeadOf(ATxt);
  Result := InList(APart.Resolved, CHAR_LIKE_TYPES)
    or InList(Head, CHAR_LIKE_TYPES) or (Head = 'chr');
end;

// Grund, mit dem ein Operand die Umformung sperrt - fuer jedes Urteil
// ausser ovString und ovByCompiler. ATxt ist der Operand wie im Aufruf.
function OperandRejectReason(AVerdict: TRdxOperandVerdict;
  const APart: TRdxPart; const ATxt: string): string;
begin
  case AVerdict of
    ovNonString:
      begin
        Result := 'Operand ''' + ATxt + ''': kein String';
        if APart.Resolved <> '' then
          Result := Result + ' (' + APart.Resolved + ')';
      end;
    ovAnsi:
      begin
        if AnsiTypeOf(APart, ATxt) = 'ansichar' then
          Result := 'Operand ''' + ATxt
            + ''': ansichar - Format wandelt ohne Codepage'
        else
          Result := 'Operand ''' + ATxt + ''': '
            + AnsiTypeOf(APart, ATxt) + ' - Format liefert UnicodeString';
      end;
    ovVariantRisk:
      Result := 'Operand ''' + ATxt
        + ''': Variant moeglich (Null/Zahl: Original wirft, Format nicht)';
  else
    Result := 'Operand ''' + ATxt + ''': kein einfacher Operand';
  end;
end;

type
  // Zustand von BuildFormatCall ueber die Parts (TakeLiteral, TakeOperand):
  // der Formatstring im Aufbau, die Werte der Literale (SQL-Probe), die
  // Argumente und ob das Ziel Unicode ist. Bis Charge R8 lag das als eine
  // Schleife in BuildFormatCall (SCA176 38).
  TRdxFormatScan = record
    Fmt      : string;
    InQuote  : Boolean;
    Literals : TArray<string>;
    Args     : TArray<string>;
    TargetU  : Boolean;
  end;

// Die Strings mit ASep verbunden (string.Join kennt FPC nicht).
function JoinStrings(const AItems: TArray<string>; const ASep: string): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(AItems) do
    begin
      if i > 0 then SB.Append(ASep);
      SB.Append(AItems[i]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Ein Literal-Term: sein Quelltext in den Formatstring (AppendLiteralSource)
// und sein Wert zu den Literalen. '' oder der Grund.
function TakeLiteral(const APart: TRdxPart; var AScan: TRdxFormatScan): string;
var
  Value : string;
begin
  Result := '';
  if not TRdxRecipes.DecodeLiteral(APart.Text, Value)
     or not AppendLiteralSource(AScan.Fmt, AScan.InQuote, APart.Text) then
    Exit('Literal nicht lesbar: ' + TRdxRecipes.CollapseCode(APart.Text));
  AddText(AScan.Literals, Value);
end;

// Das Urteil ueber einen Operanden fuer den Format-Aufruf: JudgeOperand,
// dazu die Unicode-Ausnahme. Unicode-Ziel: Format wandelt einen
// AnsiString-Operanden genauso wie die Zuweisung es taete (FormatBuf
// vtAnsiString -> UnicodeString). NICHT ein AnsiChar: FormatBuf macht bei
// vtChar 'Char(VChar)' - ein Ordinal-Cast ohne Codepage -, die Verkettung
// wandelt dagegen ueber die Systemcodepage. Ab #$80 kaeme anderer Text
// heraus (#$80 in CP1252: das Original ergibt das Euro-Zeichen, Format
// U+0080). Review reDelphiX 2026-10-07, Blocker 1. AnsiTypeOf statt
// Resolved: auch der Cast 'AnsiChar(b)' bleibt gesperrt (Minor 12).
function FormatVerdictOf(const APart: TRdxPart; const ATxt: string;
  const AScan: TRdxFormatScan): TRdxOperandVerdict;
begin
  Result := TRdxRecipes.JudgeOperand(APart);
  if (Result = ovAnsi) and AScan.TargetU
     and (AnsiTypeOf(APart, ATxt) <> 'ansichar') then
    Result := ovString;
end;

// Ein Operand nach dem Urteil: '%s' in den Formatstring, bewiesen oder laut
// Kompilat (ABuild zaehlt). Char/WideChar/ShortString gehen als string(x),
// sonst ginge ein #0 verloren (Minor 10); ByCompiler behaelt den Text wie
// geschrieben. '' oder der Grund (ovNonString, ovAnsi, ovVariantRisk,
// ovNoOperand: gesperrt).
function TakeJudged(const APart: TRdxPart; var ATxt: string;
  var AScan: TRdxFormatScan; var ABuild: TRdxFormatBuild): string;
var
  Verdict : TRdxOperandVerdict;
begin
  Result := '';
  Verdict := FormatVerdictOf(APart, ATxt, AScan);
  case Verdict of
    ovString:
      begin
        AppendQuoted(AScan.Fmt, AScan.InQuote, '%s');
        Inc(ABuild.Proven);
      end;
    ovByCompiler:
      begin
        AppendQuoted(AScan.Fmt, AScan.InQuote, '%s');
        AddText(ABuild.ByCompiler, ATxt);
      end;
  else
    Exit(OperandRejectReason(Verdict, APart, ATxt));
  end;
  if NeedsStringCast(APart, ATxt) then
    ATxt := 'string(' + ATxt + ')';
end;

// Ein Operanden-Term: IntToStr(n) wird %d mit n (so schriebe man es von
// Hand), sonst nach dem Urteil (TakeJudged). Wie der Detektor
// (AlreadyUsesFormat): eine Kette, in der schon Format() steht, wird nicht
// noch einmal in Format() gepackt - sonst wuerde ein zweiter Lauf
// 'Format(''%s'', [Format(...)])' bauen (reDelphix.Test,
// Rewrite_AppliedOnce_NoSecondFinding, rot am 2026-10-06). '' oder der
// Grund.
function TakeOperand(const APart: TRdxPart; var AScan: TRdxFormatScan;
  var ABuild: TRdxFormatBuild): string;
var
  Txt, Arg, Spec : string;
begin
  Result := '';
  Txt := TRdxRecipes.CollapseCode(APart.Text);
  if Pos('format(', LowerCase(Txt)) > 0 then
    Exit('Kette enthaelt schon Format()');
  if TRdxRecipes.NumericArgument(APart, Arg, Spec) then
  begin
    AppendQuoted(AScan.Fmt, AScan.InQuote, Spec);
    Txt := Arg;
    Inc(ABuild.Proven);
    Inc(ABuild.Numeric);
  end
  else
  begin
    Result := TakeJudged(APart, Txt, AScan, ABuild);
    if Result <> '' then Exit;
  end;
  Inc(ABuild.Operands);
  AddText(AScan.Args, Txt);
end;

// Die Kette als Ganzes: mindestens ein Operand und ein Literal (ohne
// Literal gibt es keinen Formatstring, nur '%s%s' - keine Verbesserung;
// der Detektor verlangt Literal UND Nicht-Literal), kein SQL. '' oder der
// Grund.
function ChainReason(const AScan: TRdxFormatScan;
  const ABuild: TRdxFormatBuild): string;
begin
  Result := '';
  if ABuild.Operands = 0 then
    Exit('kein Operand in der Kette');
  if Length(AScan.Literals) = 0 then
    Exit('kein Literal in der Kette');
  if TRdxRecipes.LooksLikeSql(JoinStrings(AScan.Literals, '')) then
    Result := 'SQL-Text: Umformung gesperrt (SCA003)';
end;

const
  // Zeigertypen, mit denen 'P + N' rechnet statt verkettet (R2-04).
  PCHAR_TYPES: array[0..2] of string = ('pchar', 'pwidechar', 'pansichar');

// Ein Zeiger-Term: als PChar/PWideChar/PAnsiChar deklariert oder ein Cast
// darauf ('PChar(S)').
function IsPointerTerm(const APart: TRdxPart): Boolean;
begin
  Result := (APart.Role = ROLE_OPERAND) and (InList(APart.Resolved, PCHAR_TYPES)
    or InList(CallHeadOf(Trim(APart.Text)), PCHAR_TYPES));
end;

// Ist der Term als String bewiesen, verkettet Delphi 'P + T' - auch ein
// Nicht-Unicode-String (AnsiString, UTF8String, ShortString, UTF8Encode(..);
// Review Woche G01-07: bis dahin sperrte ovAnsi als 'Zeiger-Arithmetik').
// Ein AnsiChar bzw. PAnsiChar ist kein String - die Sperre bleibt. Ob der
// Operand in den Format-Aufruf darf, urteilt danach TakeJudged.
function IsStringTerm(const APart: TRdxPart): Boolean;
var
  Verdict : TRdxOperandVerdict;
  Ansi    : string;
begin
  Verdict := TRdxRecipes.JudgeOperand(APart);
  if Verdict = ovString then
    Exit(True);
  if Verdict <> ovAnsi then
    Exit(False);
  Ansi := AnsiTypeOf(APart, TRdxRecipes.CollapseCode(APart.Text));
  Result := (Ansi <> 'ansichar') and (Ansi <> 'pansichar');
end;

// Zeiger am Kettenanfang (Kompilat-Regel, Nachtrag Review FB R2-04): das
// Kompilat buergt hier NICHT. 'P + FOffset + ''x''' mit P: PChar rechnet
// zuerst P + FOffset als Zeiger-Arithmetik und verkettet erst dann - die
// Kette uebersetzt, auch wenn FOffset eine Zahl ist, und Format('%s%sx',
// [P, FOffset]) wirft EConvertError. Gesperrt, wenn der erste Term als
// PChar/PWideChar/PAnsiChar deklariert oder ein Cast darauf ist und der
// zweite weder Literal noch bewiesener String (IsStringTerm). Nicht beim
// Selbst-Anhaengen (AStart = csBehindTarget): dort beginnt die Kette mit
// dem Ziel X, einem
// String - 'X + P' verkettet (Nachpruefung FB). Bekannte Grenze: ein PChar
// UNBEKANNTEN Typs am Anfang (Feld oder Funktion einer anderen Unit) bleibt
// unsichtbar - dann wirft Format zur Laufzeit, statt still falsch zu
// rechnen. '' oder der Grund.
function PointerStartReason(const AParts: TRdxParts;
  AStart: TRdxChainStart): string;
var
  i, n  : Integer;
  Terms : array[0..1] of TRdxPart;
begin
  Result := '';
  if AStart = csBehindTarget then Exit;
  n := 0;
  for i := 0 to High(AParts) do
  begin
    if AParts[i].Role = ROLE_TARGET then
      Continue;
    Terms[n] := AParts[i];
    Inc(n);
    if n = 2 then
      Break;
  end;
  if (n < 2) or not IsPointerTerm(Terms[0])
     or (Terms[1].Role <> ROLE_OPERAND) or IsStringTerm(Terms[1]) then
    Exit;
  Result := Format('Operand ''%s'': Zeiger am Kettenanfang - ist ''%s'' kein '
    + 'String, rechnet Delphi ''%s + %s'' als Zeiger-Arithmetik, Format nicht',
    [TRdxRecipes.CollapseCode(Terms[0].Text),
     TRdxRecipes.CollapseCode(Terms[1].Text),
     TRdxRecipes.CollapseCode(Terms[0].Text),
     TRdxRecipes.CollapseCode(Terms[1].Text)]);
end;

class function TRdxRecipes.BuildFormatCall(const AParts: TRdxParts;
  out ABuild: TRdxFormatBuild; const ATargetType: string;
  AStart: TRdxChainStart): Boolean;
var
  i    : Integer;
  Scan : TRdxFormatScan;
begin
  Result := False;
  ABuild := Default(TRdxFormatBuild);
  Scan   := Default(TRdxFormatScan);
  Scan.TargetU := (ATargetType = 'string') or (ATargetType = 'unicodestring')
    or (ATargetType = 'widestring');
  ABuild.Reason := PointerStartReason(AParts, AStart);
  if ABuild.Reason <> '' then Exit;
  // Selbst-Anhaengen an einen Variant ('V := V + ''x'' + N'): jedes '+'
  // ist Variant-Arithmetik - die Kette uebersetzt fuer JEDEN Typ von N, das
  // Kompilat buergt fuer keinen Operanden, und Format aendert die
  // Klammerung (V = 5: 5 + '1' + '2' ergibt 8, 5 + '12' ergibt 17; Review
  // Woche G01-05).
  if (AStart = csBehindTarget)
     and ((ATargetType = 'variant') or (ATargetType = 'olevariant')) then
  begin
    ABuild.Reason := 'Ziel ist ein Variant - hinter ''X +'' rechnet Delphi '
      + 'Variant-Arithmetik statt zu verketten, das Kompilat buergt fuer '
      + 'keinen Operanden';
    Exit;
  end;
  for i := 0 to High(AParts) do
  begin
    if AParts[i].Role = ROLE_TARGET then
      Continue;
    if AParts[i].Role = ROLE_LITERAL then
      ABuild.Reason := TakeLiteral(AParts[i], Scan)
    else if AParts[i].Role = ROLE_OPERAND then
      ABuild.Reason := TakeOperand(AParts[i], Scan, ABuild)
    else
      ABuild.Reason := 'kein reiner Term: ' + AParts[i].Role;
    if ABuild.Reason <> '' then Exit;
  end;
  ABuild.Reason := ChainReason(Scan, ABuild);
  if ABuild.Reason <> '' then Exit;
  if Scan.InQuote then Scan.Fmt := Scan.Fmt + '''';
  // Die Literale der Kette einzeln kurz, zusammen im Formatstring evtl. nicht
  // mehr (E2056 bis Delphi 11; Review FB R2-02).
  ABuild.NewText := 'Format(' + SplitLongLiteral(Scan.Fmt) + ', ['
    + JoinStrings(Scan.Args, ', ') + '])';
  Result := True;
end;

class function TRdxRecipes.BuildFormatCall(const AParts: TRdxParts;
  out ANewText, AReason: string): Boolean;
var
  B : TRdxFormatBuild;
begin
  Result   := BuildFormatCall(AParts, B);
  ANewText := B.NewText;
  AReason  := B.Reason;
end;

class function TRdxRecipes.QueryObjectOf(const ATarget: string): string;
var
  T   : string;
  Low : string;
  P   : Integer;
begin
  T   := Trim(ATarget);
  // '.' hinten dran: das Glied '.SQL' ganz - 'DM.SQLQuery1.SQL.Text'
  // traf mit Pos('.sql') schon '.SQLQuery1' und lieferte 'DM'.
  Low := LowerCase(T) + '.';
  P := Pos('.sql.', Low);
  if P = 0 then
    P := Pos('.commandtext.', Low);
  if P = 0 then
    P := LastDelimiter('.', T);
  if P > 0 then
    Result := Copy(T, 1, P - 1)
  else
    Result := T;
end;

class function TRdxRecipes.HasQueryObject(const ATarget: string): Boolean;
var
  Low : string;
begin
  Low := LowerCase(Trim(ATarget)) + '.';
  Result := (Pos('.sql.', Low) > 0) or (Pos('.commandtext.', Low) > 0);
end;

class function TRdxRecipes.IndentTextOf(const ALinePrefix: string): string;
var
  i : Integer;
begin
  Result := ALinePrefix;
  for i := 1 to Length(Result) do
    if Result[i] <> #9 then
      Result[i] := ' ';
end;

class function TRdxRecipes.DetectFramework(
  const AUnitNames: TArray<string>): TRdxFramework;
var
  i      : Integer;
  Low    : string;
  HasVcl : Boolean;
  HasFmx : Boolean;
begin
  HasVcl := False;
  HasFmx := False;
  for i := 0 to High(AUnitNames) do
  begin
    Low := LowerCase(AUnitNames[i]);
    if Copy(Low, 1, 4) = 'vcl.' then HasVcl := True;
    if Copy(Low, 1, 4) = 'fmx.' then HasFmx := True;
  end;
  if HasVcl and HasFmx then Exit(fwBoth);
  if HasVcl then Exit(fwVcl);
  if HasFmx then Exit(fwFmx);
  Result := fwUnknown;
end;

class function TRdxRecipes.HasUnit(const AUnitNames: TArray<string>;
  const AShortName: string): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := 0 to High(AUnitNames) do
    if SameText(LastSegment(AUnitNames[i]), AShortName) then
      Exit(True);
end;

const
  // Erste Segmente der Delphi-Unit-Scopes (DCC_Namespace-Vorgaben und
  // Embarcadero-Bibliotheken). Nur ein Eintrag darunter zeigt, dass eine
  // Datei qualifiziert schreibt (Review 2026-10-07, Minor 35).
  RTL_SCOPE_PREFIXES: array[0..16] of string = (
    'system', 'winapi', 'vcl', 'fmx', 'data', 'xml', 'soap', 'web',
    'datasnap', 'rest', 'posix', 'macapi', 'androidapi', 'iosapi',
    'firedac', 'ibx', 'bde');
  // Spuren einer FPC-Weiche, ohne Leerraum und klein (LineLooksFpcAware).
  // 'fpc_fullversion' allein ist eine Weiche ('{$IF FPC_FULLVERSION >=
  // 30200}'; Pruefer 2026-10-14, d) - dieselbe Liste wie im Labor
  // (uRdxIntroPlan/uVnpPlan FPC_TELLS), seit Charge R8 nachgezogen.
  FPC_TELLS: array[0..5] of string = (
    '{$mode', '(*$mode', '$ifdeffpc', '$ifndeffpc', 'defined(fpc',
    'fpc_fullversion');
  USES_IN_WORD = 'in';
  PAREN_OPEN   = '(*';
  PAREN_CLOSE  = '*)';

class function TRdxRecipes.UsesNameFor(const AUnitNames: TArray<string>;
  const AShortName, AQualifiedName: string): string;
var
  i : Integer;
begin
  if Length(AUnitNames) = 0 then Exit(AQualifiedName);
  for i := 0 to High(AUnitNames) do
    if IsRtlScopedName(AUnitNames[i]) then
      Exit(AQualifiedName);
  Result := AShortName;
end;

class function TRdxRecipes.IsRtlScopedName(const AName: string): Boolean;
var
  P : Integer;
begin
  P := Pos('.', AName);
  Result := (P > 1)
    and InList(LowerCase(Copy(AName, 1, P - 1)), RTL_SCOPE_PREFIXES);
end;

class function TRdxRecipes.LineLooksFpcAware(const ALine: string): Boolean;
var
  S : string;
  i : Integer;
begin
  Result := False;
  if Pos('$', ALine) = 0 then Exit;   // jede Spur ist eine Direktive
  S := LowerCase(StringReplace(StringReplace(ALine, ' ', '', [rfReplaceAll]),
    #9, '', [rfReplaceAll]));
  for i := Low(FPC_TELLS) to High(FPC_TELLS) do
    if Pos(FPC_TELLS[i], S) > 0 then
      Exit(True);
end;

// Zeichen an AIndex, #0 ausserhalb von S.
function CharAt(const S: string; AIndex: Integer): Char;
begin
  if (AIndex >= 1) and (AIndex <= Length(S)) then
    Result := S[AIndex]
  else
    Result := #0;
end;

// Erste Stelle ab AFrom, die kein Leerraum ist (Length + 1 am Ende).
function SkipBlanksFrom(const S: string; AFrom: Integer): Integer;
begin
  Result := AFrom;
  while (Result <= Length(S)) and (S[Result] <= ' ') do
    Inc(Result);
end;

// 'in' + Leerraum + String-Literal ab AFrom (der Pfad eines uses-
// Eintrags): Index des schliessenden Quotes. 0 = dort steht kein 'in';
// -1 = 'in' ohne auf dieser Zeile geschlossenes Literal.
function InPathEnd(const S: string; AFrom: Integer): Integer;
var
  i : Integer;
begin
  Result := 0;
  if not SameText(Copy(S, AFrom, Length(USES_IN_WORD)), USES_IN_WORD)
     or IsIdentChar(CharAt(S, AFrom + Length(USES_IN_WORD))) then Exit;
  Result := -1;
  i := SkipBlanksFrom(S, AFrom + Length(USES_IN_WORD));
  if CharAt(S, i) <> '''' then Exit;
  Inc(i);
  while i <= Length(S) do
  begin
    if (S[i] = '''') and (CharAt(S, i + 1) = '''') then
      Inc(i)                 // '' im Pfad
    else if S[i] = '''' then
      Exit(i);
    Inc(i);
  end;
end;

// Block-Kommentar ab AFrom ('{..}' oder '(*..*)', keine Direktive): Index
// seines letzten Zeichens. 0 = dort beginnt keiner; -1 = Direktive oder
// nicht auf dieser Zeile geschlossen.
function BlockCommentEnd(const S: string; AFrom: Integer): Integer;
var
  P : Integer;
begin
  if CharAt(S, AFrom) = '{' then
  begin
    if CharAt(S, AFrom + 1) = '$' then Exit(-1);
    P := Pos('}', Copy(S, AFrom + 1, MaxInt));
    if P = 0 then Exit(-1);
    Exit(AFrom + P);
  end;
  if Copy(S, AFrom, Length(PAREN_OPEN)) <> PAREN_OPEN then Exit(0);
  if CharAt(S, AFrom + Length(PAREN_OPEN)) = '$' then Exit(-1);
  P := Pos(PAREN_CLOSE, Copy(S, AFrom + Length(PAREN_OPEN), MaxInt));
  if P = 0 then Exit(-1);
  Result := AFrom + P + Length(PAREN_OPEN);   // die ')' von '*)'
end;

class function TRdxRecipes.UsesTailLength(const ARest: string): Integer;
var
  i    : Integer;
  Last : Integer;
  Stop : Integer;
begin
  Result := -1;
  Last := 0;
  i := SkipBlanksFrom(ARest, 1);
  Stop := InPathEnd(ARest, i);
  if Stop < 0 then Exit;
  if Stop > 0 then
  begin
    Last := Stop;
    i := SkipBlanksFrom(ARest, Stop + 1);
  end;
  // Danach nur Block-Kommentare bis zum ';'.
  while i <= Length(ARest) do
  begin
    if ARest[i] = ';' then Exit(Last);
    Stop := BlockCommentEnd(ARest, i);
    if Stop <= 0 then Exit;
    Last := Stop;
    i := SkipBlanksFrom(ARest, Stop + 1);
  end;
end;

class function TRdxRecipes.IsSortedUses(
  const AUnitNames: TArray<string>): Boolean;
var
  i : Integer;
begin
  Result := True;
  for i := 1 to High(AUnitNames) do
    if CompareText(AUnitNames[i - 1], AUnitNames[i]) > 0 then
      Exit(False);
end;

class function TRdxRecipes.SortedInsertIndex(
  const AUnitNames: TArray<string>; const ANewName: string): Integer;
var
  i : Integer;
begin
  if not IsSortedUses(AUnitNames) then Exit(0);
  for i := 0 to High(AUnitNames) do
    if CompareText(ANewName, AUnitNames[i]) < 0 then
      Exit(i);
  Result := Length(AUnitNames);
end;

end.

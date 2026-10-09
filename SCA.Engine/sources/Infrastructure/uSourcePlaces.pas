unit uSourcePlaces;

// Quellstellen-Dienst: liefert einem Fremd-Konsumenten (Modul "Source
// Refactor", reDelphix) beschriebene Stellen einer Quelldatei - auf
// Anfrage, ausserhalb des Scans, ohne Detektor und ohne Fund.
// Konzept_SourceRefactor_Quellstellen 2026-10-02, entschieden 2026-10-03.
//
// WARUM PULL
//
// Der Vorgaenger (Branch ag-refactorinfo) liess DETEKTOREN ihre
// Refactoring-Informationen an den Fund haengen. Das kostete je
// liefernder Regel eine Detektor-Aenderung - Signatur, Registrierung,
// Zeilenzugriff, Tests. Hier fragt stattdessen der Konsument: er hat
// Datei, Zeile und Regel-ID (aus SARIF, JSON oder TScanResult) und holt
// sich die Beschreibung. Eine neue Umformung ist dann ein Rezept aus den
// Primitiven dieser Klasse im Modul - kein Code im Core.
//
// WAS DIESE KLASSE NICHT TUT
//
//   * Sie meldet nichts, aendert keinen Fund, kein Feld, keinen Export.
//     Fundzahl, FP-Quote, Baselines und SARIF koennen sich durch sie
//     nicht bewegen. Kein Detektor darf sie importieren.
//   * Sie benutzt NICHT den Datei-Cache des Scans und keinen Engine-Lock:
//     Open liest die Datei selbst (LoadFileSmart, TParser2.ParseNamedSource
//     auf genau dem dekodierten Text).
//     Dadurch ist sie auch aus einem residenten Host (IDE-Plugin) heraus
//     jederzeit aufrufbar - die Doku_01-Leitplanke "Engine nur fuer
//     kurzlebige Ein-Scan-Prozesse" betrifft den Scan, nicht das Lesen
//     einer Datei. Preis: ein Datei-Read je Open.
//   * OpenSource nimmt den Text vom Host entgegen (AH15, 2026-10-06): im
//     IDE-Plugin ist der Editor-Puffer die Wahrheit, nicht die Platte.
//     reDelphix beschrieb Stellen aus der gespeicherten Datei und
//     verweigerte dann das Schreiben in den geaenderten Puffer ("Quelltext
//     im Editor weicht vom Scan ab") - richtig verweigert, aber fuer den
//     Benutzer unverstaendlich.
//   * Sie schreibt nichts. Das Umschreiben ist Sache des Moduls.
//
// DIE PRIMITIVE
//
//   StatementAt   Anweisung an Position: Bereich, Flags, Einfuegepunkt,
//                 Hash (uRefactorInfoBuilder)
//   ChainOf       '+'-Kette einer Zuweisung: Ziel, Literale, Operanden,
//                 FixSafe (uRefactorConcat)
//   CallOf        Aufruf: Kopf + Kette des einen Arguments, sonst Kopf +
//                 je Argument ein Bereich
//   NodesAt       AST-Knoten einer Art auf einer Zeile - der Weg vom Fund
//                 (Zeile) zur Startposition (Spalte) und zum Zielnamen
//   UsesEntries   Unit-Namen der uses-Klauseln mit Spalten
//   IdentifiersIn Bezeichner in einem Bereich (im Zusammenhang der Datei
//                 gelesen: ein Kommentar oder String, der vor dem Bereich
//                 beginnt, gilt auch darin - Review Nit 28)
//   SectionLine   Zeile von 'interface' / 'implementation' (0 = fehlt)
//   LineText      Text einer Zeile der geoeffneten Datei
//   SpanHasComment Kommentar/Direktive in einem Bereich
//   DeclaredTypeOf Typname eines Bezeichners an einer Zeile (uTypeResolver:
//                 Parameter, lokale Variable, Feld, Unit-Global). ChainOf
//                 und CallOf nutzen das selbst (AH12, 2026-10-05): ein
//                 Operand, der ein blosser Bezeichner ist, wird ueber
//                 seinen deklarierten Typ rvString bzw. rvNonString,
//                 Resolved traegt den Typnamen, FixSafe wird neu abgeleitet.
//                 Vorher blieb 'Marker: string' rvUnknown - 98 % der
//                 SCA044-Funde am Korpus waren so nie fix-sicher.
//                 ALine ist die ANKERZEILE der Anweisung: der Resolver
//                 begrenzt Routinen ueber die letzte Knoten-Zeile, eine
//                 Fortsetzungszeile der letzten Anweisung liegt dahinter.
//                 Der Resolver kennt KEINE with-Bloecke: dort kann ein
//                 Name an ein Member des with-Ausdrucks binden. ChainOf/
//                 CallOf beweisen dort nichts (s. InWithBlock).
//   InWithBlock   liegt eine Zeile im Rumpf einer with-Anweisung?
//   CodeViewOf / TextOf / HashOf   Sicht, Text und Hash eines Bereichs
//   ConditionalRanges              {$IFDEF}-Bereiche der Datei
//
// Jedes Primitiv ist total: nil bzw. leeres Array statt Exception, auch
// wenn keine Datei geoeffnet ist. Einzige Ausnahme: ein Parser-Fehler in
// Open/OpenSource laeuft als Exception zum Aufrufer (Watchdog in
// TParser2), danach ist nichts geoeffnet; die Nicht-Lesbarkeit der Datei
// dagegen ist ein False.
//
// KOORDINATEN wie uRefactorInfo: 1-basiert, EndCol zeigt HINTER das
// letzte Zeichen.
//
// VERTRAGSVERSION
//
// Der Vertrag traegt eine Versionsnummer (SOURCE_PLACES_VERSION). Sie ist
// eine Uebersetzungszeit-Konstante: ein Konsument kann sie beim
// Uebersetzen pruefen ($IF mit $MESSAGE ERROR) und bricht dann, wenn er
// gegen einen geaenderten Vertrag gebaut wird. Eine zur Laufzeit
// getauschte BPL erkennt sie nicht - das leistet die Paketbindung
// (DCP/requires), nicht diese Zahl (Review reDelphiX 2026-10-07, Nit 27).
// Version 1 ist der Vertrag, wie er mit dem ersten Merge nach main
// ausgeliefert wird; was vorher auf dem Branch dazukam (OpenSource,
// P9-P12, die Typableitung von AH12), gehoert dazu.

interface

uses
  System.Classes,
  uAstNode, uAstSpans, uRefactorInfo,   // TNodeKinds kommt aus uAstSpans
  uTypeResolver;                        // P9: deklarierter Typ eines Bezeichners

const
  // Vertragsversion (s. Kopf, VERTRAGSVERSION). Sie steigt mit jeder
  // Aenderung, die einen gegen die alte Version geschriebenen Konsumenten
  // falsch machen kann: Signaturen bestehender Primitive, Rollen,
  // Koordinaten - und die Ableitung von FixSafe, ValueType oder Resolved,
  // sobald sie etwas als BEWIESEN meldet, was vorher unbekannt war.
  // Sie bleibt bei neuen Primitiven, bei neuen Parametern mit
  // Vorgabewert und bei einer Ableitung, die nur STRENGER wird (mehr
  // rvUnknown, seltener FixSafe) - darauf kann sich jeder Konsument der
  // alten Version weiter verlassen.
  SOURCE_PLACES_VERSION = 1;

type
  // Kopie der vier Felder eines AST-Knotens, die ein Konsument braucht.
  // Kein TAstNode nach aussen: der Baum gehoert dem Dienst und lebt nur
  // bis zum naechsten Open/Close.
  TNodeRef = record
    Kind    : TNodeKind;
    Line    : Integer;
    Col     : Integer;
    Name    : string;    // Ziel/Kopf, wie der Parser ihn zusammengefuegt hat
    TypeRef : string;    // rechte Seite bzw. Typbezug, abgeflacht
  end;

  // Eigener Name, weil uUninitVar bereits ein lokales TLineRange fuehrt.
  TSourceLineRange = record
    StartLine : Integer;
    EndLine   : Integer;
  end;

  // Welche uses-Klauseln UsesEntries liefert. usAny schliesst auch eine
  // uses-Klausel direkt unter dem Programm-/Library-Knoten ein.
  TUsesSection = (usAny, usInterface, usImplementation);

  TSourcePlaces = class
  private
    FFileName : string;
    FLines    : TStringList;   // nil, solange nichts geoeffnet ist
    FRoot     : TAstNode;      // AST der Datei, nil ohne Datei
    FTypes    : TTypeResolver; // lazy aus FRoot, lebt bis Close
    // Lazy aus FRoot (BuildScopeFacts), leben bis Close: die Zeilen der
    // with-Anweisungen und die Namen der Funktionen der Unit, deren
    // Ergebnis kein String ist (klein, letztes Namenssegment).
    FScopeFactsBuilt : Boolean;
    FWithRanges      : TArray<TSourceLineRange>;
    FNonStringFuncs  : TArray<string>;
    function Types: TTypeResolver;
    procedure BuildScopeFacts;
    // True, wenn die Unit eine Funktion dieses Namens (klein) ohne
    // String-Ergebnis deklariert - sie verdeckt die gleichnamige RTL.
    function DeclaresNonStringFunc(const ANameLow: string): Boolean;
    // Operanden, die blosse Bezeichner sind, ueber den deklarierten Typ
    // klassifizieren und FixSafe neu ableiten (s. Kopf, DeclaredTypeOf).
    procedure ResolveOperandTypes(AInfo: TRefactorInfo);
    // Ein ROLE_OPERAND-Term fuer ResolveOperandTypes; AAnchorLine ist die
    // Ankerzeile der Anweisung (auch fuer InWithBlock).
    procedure ClassifyOperand(var APart: TRefactorSpan; AAnchorLine: Integer);
  public
    const
      // ChainOf ohne '+'-Gegenprobe (wie TRefactorConcat.ANY_PLUS_COUNT;
      // jeder negative Wert gilt so).
      ANY_PLUS_COUNT = -1;

    constructor Create;
    destructor Destroy; override;

    // Liest Zeilen und AST der Datei. False, wenn die Datei nicht lesbar
    // ist - dann ist nichts geoeffnet. Ein vorher geoeffneter Stand wird
    // in jedem Fall verworfen.
    function Open(const AFileName: string): Boolean;
    // Wie Open, aber aus ASource statt von der Platte - fuer einen Host,
    // der den EDITOR-PUFFER kennt (IDE: ungespeicherte Aenderungen). Die
    // Bereiche beziehen sich dann auf genau diesen Text; wer anschliessend
    // in denselben Puffer schreibt, vergleicht gegen dieselbe Wahrheit.
    // AFileName ist nur der Name, der in FileName steht (Diagnose,
    // Fund-Abgleich); gelesen wird die Datei nicht. False bei leerem Text.
    function OpenSource(const AFileName, ASource: string): Boolean;
    procedure Close;
    function IsOpen: Boolean;
    property FileName: string read FFileName;
    function LineCount: Integer;

    // P1 - Anweisung, die an (ALine, ACol) beginnt. nil, wenn ihr Ende
    // nicht sauber bestimmbar ist. Der Aufrufer besitzt das Ergebnis.
    function StatementAt(ALine, ACol: Integer): TRefactorInfo;

    // P3 - Zuweisung mit '+'-Kette an (ALine, ACol). AExpectedTarget <> ''
    // ist die Gegenprobe gegen den Knoten (TNodeRef.Name): passt das Ziel
    // im Quelltext nicht dazu, kommt nil. AExpectedPlus >= 0 ist die
    // zweite Gegenprobe: die Zahl der '+' auf oberster Ebene, wie der
    // Konsument sie unabhaengig gezaehlt hat (etwa aus TNodeRef.TypeRef,
    // wie SCA044 sie meldet); weicht die Zaehlung im Quelltext ab, kommt
    // nil - die beiden beschreiben nicht dieselbe Kette (Review reDelphiX
    // 2026-10-07, strittiger Minor 2).
    function ChainOf(ALine, ACol: Integer;
      const AExpectedTarget: string = '';
      AExpectedPlus: Integer = ANY_PLUS_COUNT): TRefactorInfo;

    // P4 - Aufruf-Anweisung an (ALine, ACol). Bei GENAU EINEM Argument
    // dessen '+'-Kette (ROLE_LITERAL/ROLE_OPERAND, mit FixSafe), sonst je
    // Argument ein ROLE_ARGUMENT-Bereich ohne Zerlegung. ROLE_TARGET ist in
    // beiden Faellen der Aufrufkopf. AExpectedHead ist der Kopf vor der
    // ersten Klammer (bei nkCall der Teil von TNodeRef.Name vor '(');
    // '' = keine Gegenprobe.
    function CallOf(ALine, ACol: Integer;
      const AExpectedHead: string = ''): TRefactorInfo;

    // P5 - alle Unit-Namen der uses-Klauseln als ROLE_UNIT-Bereiche, in
    // Quelltext-Reihenfolge; Resolved traegt den Namen, wie er dasteht
    // ('SysUtils' oder 'System.SysUtils'). Ein Eintrag, dessen Quelltext
    // nicht zum Namen des Knotens passt (Name ueber Zeilen verteilt), wird
    // ausgelassen statt falsch beschrieben.
    function UsesEntries(ASection: TUsesSection = usAny): TArray<TRefactorSpan>;
    class function CollectUsesEntries(ARoot: TAstNode; ALines: TStrings;
      ASection: TUsesSection): TArray<TRefactorSpan>; static;

    // P8 - Bezeichner in einem Bereich der geoeffneten Datei als
    // ROLE_IDENT-Bereiche (Resolved = das Wort), Strings und Kommentare
    // ausgeblendet, Hex-/Zeichen-Literale ($FF, #13) und Exponenten (1e5)
    // nicht mitgezaehlt. Schluesselwoerter werden NICHT gefiltert - das
    // entscheidet der Konsument. Der Bereich darf mitten in einem
    // Kommentar oder String beginnen: die Datei wird bis zum Bereich
    // mitgelesen (TRefactorInfoBuilder.CodeViewInContext; Review Nit 28).
    // Nur einen Delphi-12-Mehrzeilenstring davor erkennt das nicht.
    function IdentifiersIn(const ASpan: TRefactorSpan): TArray<TRefactorSpan>;
    class function CollectIdentifiers(const AView: TArray<string>;
      const ASpan: TRefactorSpan): TArray<TRefactorSpan>; static;

    // P2 - alle Knoten der Arten AKinds, die auf ALine BEGINNEN, nach
    // Spalte aufsteigend. Leer ohne Datei oder ohne Treffer. Zwei Treffer
    // heissen: die Zeile ist mehrdeutig - der Konsument entscheidet.
    function NodesAt(ALine: Integer; const AKinds: TNodeKinds): TArray<TNodeRef>;
    // Dasselbe auf einem fremden Baum - fuer Tests und fuer Konsumenten,
    // die den AST schon haben.
    class function CollectNodesAt(ARoot: TAstNode; ALine: Integer;
      const AKinds: TNodeKinds): TArray<TNodeRef>; static;

    // P6 - Sicht, Text und Hash eines Bereichs der geoeffneten Datei.
    function CodeViewOf(const ASpan: TRefactorSpan): TArray<string>;
    function TextOf(const ASpan: TRefactorSpan): string;
    function HashOf(const ASpan: TRefactorSpan): string;

    // P7 - {$IFDEF}-Bereiche der Datei (Zeile der oeffnenden bis Zeile der
    // schliessenden Direktive), in Quelltext-Reihenfolge.
    function ConditionalRanges: TArray<TSourceLineRange>;

    // P10 - Zeile des Abschnitts-Schluesselworts ('interface' bzw.
    // 'implementation'); 0, wenn der Abschnitt fehlt (Programm,
    // Bibliothek) oder keine Datei offen ist. usAny liefert 0. Ein
    // Modul, das eine uses-Klausel ANLEGEN muss (AH19: Format() braucht
    // System.SysUtils), haengt sie hinter diese Zeile.
    function SectionLine(ASection: TUsesSection): Integer;
    // Text der Zeile ALine (1-basiert) der geoeffneten Datei; ''
    // ausserhalb. Fuer Entscheidungen am Zeilenrest (steht hinter dem
    // letzten uses-Eintrag ein 'in'-Pfad?), ohne die Datei erneut zu lesen.
    function LineText(ALine: Integer): string;
    // P11 - True, wenn im Bereich ein Kommentar steht (auch eine
    // Compiler-Direktive). Ein Modul, das nur einen TEIL einer Anweisung
    // ersetzt, prueft damit genau den Teil - rfHasComment der Anweisung
    // gilt fuer die ganze Anweisung ab dem Ziel (AH22).
    function SpanHasComment(const ASpan: TRefactorSpan): Boolean;

    // P9 - deklarierter Typ (nackter, klein geschriebener Typname) des
    // Bezeichners AName an Zeile ALine: Parameter oder lokale Variable der
    // umschliessenden Routine, sonst Klassenfeld/Unit-Global; '' wenn
    // unbekannt. Ohne Datei ''.
    // ALine ist die ANKERZEILE einer Anweisung (Zeile eines AST-Knotens):
    // der Resolver begrenzt Routinen ueber die letzte Knoten-Zeile, eine
    // Fortsetzungszeile der letzten Anweisung liegt ausserhalb jeder
    // Routine und loest nur noch Felder/Globale auf.
    // with-Bloecke kennt der Resolver NICHT: in 'with Rec do r := s'
    // liefert DeclaredTypeOf den Typ der gefundenen Deklaration von s,
    // auch wenn der Compiler s an Rec.s bindet. Wer daraus etwas
    // BEWEISEN will, fragt vorher InWithBlock. Bewusst kein '' im
    // with-Block: ein Konsument, der einen gefaehrlichen Typ (Variant,
    // Ereignis) sperrt, soll ihn auch dort weiter sehen.
    function DeclaredTypeOf(ALine: Integer; const AName: string): string;

    // P12 - True, wenn ALine im Rumpf einer with-Anweisung liegt: von der
    // Zeile des 'with' bis zur letzten Knoten-Zeile seiner Anweisung
    // (zeilengenau - eine Anweisung auf der Zeile des with-Kopfs gilt als
    // darin). Dort kann ein Name an ein Member des with-Ausdrucks binden
    // statt an die Deklaration, die DeclaredTypeOf findet. ChainOf und
    // CallOf stufen dort nichts hoch (Review reDelphiX 2026-10-07,
    // strittiger Minor 1). Ohne Datei False.
    function InWithBlock(ALine: Integer): Boolean;
  end;

implementation

// noinspection-file UnusedPublicMember
// Die Primitive sind fuer das Modul reDelphix ausserhalb dieses Repos da;
// der Selbstscan sieht keinen Aufrufer.

uses
  System.SysUtils,
  uParser2, uFileTextCache, uRefactorInfoBuilder, uRefactorConcat;

{ TSourcePlaces }

constructor TSourcePlaces.Create;
begin
  inherited Create;
end;

destructor TSourcePlaces.Destroy;
begin
  Close;
  inherited;
end;

function TSourcePlaces.Open(const AFileName: string): Boolean;
var
  Parser : TParser2;
begin
  Close;
  Result := False;
  FLines := TStringList.Create;
  if not LoadFileSmart(AFileName, FLines) then
  begin
    FreeAndNil(FLines);
    Exit;
  end;
  // Den Text EINMAL dekodieren und genau ihn parsen (Review reDelphiX
  // 2026-10-07, Major 1): ParseFile las die Datei ein zweites Mal ueber
  // TStringList.LoadFromFile ohne Encoding - eine BOM-lose UTF-8-Datei
  // wurde dort als ANSI gelesen, jedes Nicht-ASCII-Zeichen zaehlte im
  // Parser 2-3 Spalten, in FLines eine. Spalten aus NodesAt/StatementAt
  // zeigten dann rechts neben das Ziel. ParseNamedSource haelt Root.Name
  // und die Include-Basis wie ParseFile.
  Parser := TParser2.Create;
  try
    try
      FRoot := Parser.ParseNamedSource(FLines.Text, AFileName);
    except
      // Kein halboffener Zustand (Review Minor 1): Zeilen ohne Baum
      // wuerden IsOpen = True melden.
      Close;
      raise;
    end;
  finally
    Parser.Free;
  end;
  FFileName := AFileName;
  Result := True;
end;

function TSourcePlaces.OpenSource(const AFileName, ASource: string): Boolean;
var
  Parser : TParser2;
begin
  Close;
  Result := False;
  if ASource = '' then Exit;
  FLines := TStringList.Create;
  FLines.Text := ASource;   // trennt CRLF, LF und CR in Zeilen
  Parser := TParser2.Create;
  try
    try
      // FLines.Text, nicht ASource: der Lexer zaehlt nur LF als
      // Zeilenende, FLines trennt auch an einem einzelnen CR - mit dem
      // Rohtext liefen NodesAt-Zeilen und FLines/Fundzeile auseinander
      // (Review Editorhilfen 2a, 2026-10-09; Open macht es ebenso).
      FRoot := Parser.ParseSource(FLines.Text);
    except
      Close;   // kein halboffener Zustand (Review Minor 1)
      raise;
    end;
  finally
    Parser.Free;
  end;
  FFileName := AFileName;
  Result := True;
end;

procedure TSourcePlaces.Close;
begin
  FreeAndNil(FTypes);
  FreeAndNil(FRoot);
  FreeAndNil(FLines);
  FFileName := '';
  FScopeFactsBuilt := False;
  FWithRanges      := nil;
  FNonStringFuncs  := nil;
end;

function TSourcePlaces.IsOpen: Boolean;
begin
  Result := Assigned(FLines);
end;

function TSourcePlaces.LineCount: Integer;
begin
  Result := 0;
  if Assigned(FLines) then
    Result := FLines.Count;
end;

{ ---- P1 / P3 / P4 ---- }

function TSourcePlaces.StatementAt(ALine, ACol: Integer): TRefactorInfo;
begin
  Result := nil;
  if not IsOpen then Exit;
  Result := TRefactorInfoBuilder.TryBuildForStatement(FRoot, FLines,
    ALine, ACol);
end;

function TSourcePlaces.ChainOf(ALine, ACol: Integer;
  const AExpectedTarget: string; AExpectedPlus: Integer): TRefactorInfo;
var
  Plus : Integer;
begin
  Result := nil;
  if not IsOpen then Exit;
  // Jeder negative Wert heisst "nicht gegenpruefen" - unabhaengig davon,
  // welchen Wert uRefactorConcat dafuer vorsieht.
  Plus := TRefactorConcat.ANY_PLUS_COUNT;
  if AExpectedPlus >= 0 then Plus := AExpectedPlus;
  Result := TRefactorConcat.TryDescribeAssign(FRoot, FLines, ALine, ACol,
    Plus);
  if Assigned(Result) and (AExpectedTarget <> '')
     and not TRefactorConcat.TargetMatches(FLines, Result, AExpectedTarget) then
    FreeAndNil(Result);
  ResolveOperandTypes(Result);
end;

function TSourcePlaces.CallOf(ALine, ACol: Integer;
  const AExpectedHead: string): TRefactorInfo;
begin
  Result := nil;
  if not IsOpen then Exit;
  // Erst die Ein-Argument-Kette, sonst die Argumentliste.
  Result := TRefactorConcat.TryDescribeCall(FRoot, FLines, ALine, ACol);
  if not Assigned(Result) then
    Result := TRefactorConcat.TryDescribeCallArgs(FRoot, FLines, ALine, ACol);
  if Assigned(Result) and (AExpectedHead <> '')
     and not TRefactorConcat.TargetMatches(FLines, Result, AExpectedHead) then
    FreeAndNil(Result);
  ResolveOperandTypes(Result);
end;

{ ---- P10 ---- }

function TSourcePlaces.SectionLine(ASection: TUsesSection): Integer;
var
  Want : TNodeKind;
  i    : Integer;
  N    : TAstNode;
begin
  Result := 0;
  if not IsOpen or not Assigned(FRoot) or not Assigned(FRoot.Children) then Exit;
  case ASection of
    usInterface:      Want := nkInterface;
    usImplementation: Want := nkImplementation;
  else
    Exit;
  end;
  // Die Abschnittsknoten haengen direkt an der Wurzel (uParser2: Root.Add).
  for i := 0 to FRoot.Children.Count - 1 do
  begin
    N := FRoot.Children[i];
    if N.Kind = Want then
      Exit(N.Line);
  end;
end;

function TSourcePlaces.LineText(ALine: Integer): string;
begin
  Result := '';
  if not IsOpen or (ALine < 1) or (ALine > FLines.Count) then Exit;
  Result := FLines[ALine - 1];
end;

function TSourcePlaces.SpanHasComment(const ASpan: TRefactorSpan): Boolean;
begin
  Result := False;
  if not IsOpen or not ASpan.IsValid or (ASpan.StartLine < 1)
     or (ASpan.EndLine > FLines.Count) then Exit;
  Result := TRefactorInfoBuilder.SpanHasComment(FLines, ASpan);
end;

{ ---- P9 ---- }

function IsPlainIdent(const S: string): Boolean;
// Ein nackter Bezeichner - kein Punkt, keine Klammer, kein Operator.
var
  i : Integer;
begin
  Result := (S <> '') and TRefactorInfoBuilder.IsIdentStart(S[1]);
  if not Result then Exit;
  for i := 2 to Length(S) do
    if not TRefactorInfoBuilder.IsIdentChar(S[i]) then
      Exit(False);
end;

// String-Typen und Char: Format nimmt beide fuer %s.
function IsStringLikeTypeName(const ATypeLow: string): Boolean;
begin
  Result := IsStringTypeName(ATypeLow) or (ATypeLow = 'char')
    or (ATypeLow = 'widechar') or (ATypeLow = 'ansichar');
end;

function NonStringFuncName(AMethod: TAstNode): string;
// Name (klein, letztes Segment) einer FUNKTION, deren Ergebnis kein
// String ist; '' fuer Prozeduren, Konstruktoren, String-Funktionen und
// eine Implementierung ohne wiederholten Ergebnistyp (die Deklaration
// traegt ihn). uParser2 legt TypeRef als 'art:Ergebnistyp;direktive..'
// ab, ohne Ergebnis nur 'art'.
var
  P   : Integer;
  Ret : string;
begin
  Result := '';
  P := Pos(':', AMethod.TypeRef);
  if P = 0 then Exit;
  Ret := Copy(AMethod.TypeRef, P + 1, MaxInt);
  P := Pos(';', Ret);
  if P > 0 then Ret := Copy(Ret, 1, P - 1);
  Ret := LowerCase(Trim(Ret));
  if (Ret = '') or IsStringLikeTypeName(Ret) then Exit;
  P := LastDelimiter('.', AMethod.Name);
  Result := LowerCase(Copy(AMethod.Name, P + 1, MaxInt));
end;

function IsWithStatement(ANode: TAstNode; ALines: TStrings): Boolean;
// uParser2 legt 'with X do S' als nkCall an der Position des 'with' ab
// (Name = X), mit S als Kind - einen eigenen Knotentyp gibt es nicht.
// Erkannt wird es am Quelltext an der Knotenposition: das Wort 'with'
// ohne Bezeichnerzeichen dahinter.
var
  L : string;
begin
  Result := False;
  if (ANode.Kind <> nkCall) or not Assigned(ANode.Children)
     or (ANode.Children.Count = 0) then Exit;
  if (ANode.Line < 1) or (ANode.Line > ALines.Count) or (ANode.Col < 1) then
    Exit;
  L := ALines[ANode.Line - 1];
  Result := SameText(Copy(L, ANode.Col, 4), 'with')
    and ((ANode.Col + 4 > Length(L))
         or not TRefactorInfoBuilder.IsIdentChar(L[ANode.Col + 4]));
end;

function SubtreeLastLine(ANode: TAstNode): Integer;
// Hoechste Knoten-Zeile im Teilbaum - iterativ, kein Stapelueberlauf.
var
  Stack : TArray<TAstNode>;
  Top   : Integer;
  N     : TAstNode;
  i     : Integer;
begin
  Result := ANode.Line;
  SetLength(Stack, 16);
  Stack[0] := ANode;
  Top := 1;
  while Top > 0 do
  begin
    Dec(Top);
    N := Stack[Top];
    if N.Line > Result then Result := N.Line;
    if Assigned(N.Children) then
      for i := 0 to N.Children.Count - 1 do
      begin
        if Top = Length(Stack) then
          SetLength(Stack, Top * 2);
        Stack[Top] := N.Children[i];
        Inc(Top);
      end;
  end;
end;

procedure PushChildrenReversed(ANode: TAstNode; var AStack: TArray<TAstNode>;
  var ATop: Integer);
// Legt die Kinder von ANode rueckwaerts auf den Stapel - der naechste Pop
// ist das erste Kind (Pre-Order wie CollectNodesAt). Der Stapel waechst bei
// Bedarf auf das Doppelte; er darf nicht leer angelegt sein.
var
  i : Integer;
begin
  if not Assigned(ANode.Children) then Exit;
  for i := ANode.Children.Count - 1 downto 0 do
  begin
    if ATop = Length(AStack) then
      SetLength(AStack, ATop * 2);
    AStack[ATop] := ANode.Children[i];
    Inc(ATop);
  end;
end;

procedure AddName(var ANames: TArray<string>; var ACount: Integer;
  const AName: string);
// Haengt AName hinter ANames[0..ACount-1] an ('' = nichts). Das Array
// waechst in Stufen; der Aufrufer kuerzt es am Ende auf ACount.
begin
  if AName = '' then Exit;
  if ACount = Length(ANames) then
    SetLength(ANames, 2 * ACount + 8);
  ANames[ACount] := AName;
  Inc(ACount);
end;

procedure AddLineRange(var ARanges: TArray<TSourceLineRange>;
  var ACount: Integer; AStartLine, AEndLine: Integer);
// Wie AddName, fuer einen Zeilenbereich.
begin
  if ACount = Length(ARanges) then
    SetLength(ARanges, 2 * ACount + 4);
  ARanges[ACount].StartLine := AStartLine;
  ARanges[ACount].EndLine   := AEndLine;
  Inc(ACount);
end;

function StringCallName(const AText: string): string;
// Name (klein) der Routine hinter einem Term, den uRefactorConcat nach
// dem NAMEN als String erkannt hat: 'trim' fuer 'Trim(x)', 'tostring'
// fuer 'n.ToString'. '' fuer einen unit-qualifizierten Aufruf
// ('SysUtils.Trim(x)'): der meint die RTL, kein Name der Unit verdeckt
// ihn (andere Qualifizierer laesst IsKnownStringCall nicht zu).
var
  T : string;
  i : Integer;
begin
  Result := '';
  T := LowerCase(Trim(AText));
  if TRefactorConcat.EndsWithToString(T) then Exit('tostring');
  i := 1;
  while (i <= Length(T))
    and (TRefactorInfoBuilder.IsIdentChar(T[i]) or (T[i] = '.')) do
    Inc(i);
  if Pos('.', Copy(T, 1, i - 1)) > 0 then Exit;
  Result := Copy(T, 1, i - 1);
end;

function TSourcePlaces.Types: TTypeResolver;
begin
  if (FTypes = nil) and Assigned(FRoot) then
    FTypes := TTypeResolver.Create(FRoot);
  Result := FTypes;
end;

procedure TSourcePlaces.BuildScopeFacts;
// Ein Walk ueber den ganzen Baum (iterativ wie CollectNodesAt), einmal
// je Open. Verschachtelte Routinen verwirft uParser2 (nkNestedRange) -
// eine dort deklarierte Funktion sieht der Walk nicht.
var
  Stack  : TArray<TAstNode>;
  Top    : Integer;
  N      : TAstNode;
  NFuncs : Integer;
  NWith  : Integer;
begin
  if FScopeFactsBuilt then Exit;
  FScopeFactsBuilt := True;
  if not Assigned(FRoot) or not Assigned(FLines) then Exit;
  // AddName/AddLineRange haengen an das Vorhandene an und lassen die
  // Arrays in Stufen wachsen; am Ende auf die belegte Zahl kuerzen.
  NFuncs := Length(FNonStringFuncs);
  NWith  := Length(FWithRanges);
  SetLength(Stack, 64);
  Stack[0] := FRoot;
  Top := 1;
  while Top > 0 do
  begin
    Dec(Top);
    N := Stack[Top];
    if N.Kind = nkMethod then
      AddName(FNonStringFuncs, NFuncs, NonStringFuncName(N))
    else if IsWithStatement(N, FLines) then
      AddLineRange(FWithRanges, NWith, N.Line, SubtreeLastLine(N));
    PushChildrenReversed(N, Stack, Top);
  end;
  SetLength(FNonStringFuncs, NFuncs);
  SetLength(FWithRanges, NWith);
end;

function TSourcePlaces.DeclaresNonStringFunc(const ANameLow: string): Boolean;
var
  i : Integer;
begin
  Result := False;
  if ANameLow = '' then Exit;
  BuildScopeFacts;
  for i := 0 to High(FNonStringFuncs) do
    if FNonStringFuncs[i] = ANameLow then
      Exit(True);
end;

function TSourcePlaces.InWithBlock(ALine: Integer): Boolean;
var
  i : Integer;
begin
  Result := False;
  if not IsOpen or (ALine < 1) then Exit;
  BuildScopeFacts;
  for i := 0 to High(FWithRanges) do
    if (ALine >= FWithRanges[i].StartLine)
       and (ALine <= FWithRanges[i].EndLine) then
      Exit(True);
end;

function TSourcePlaces.DeclaredTypeOf(ALine: Integer;
  const AName: string): string;
var
  R : TTypeResolver;
begin
  Result := '';
  if not IsOpen or (Trim(AName) = '') or (ALine < 1) then Exit;
  R := Types;
  if Assigned(R) then
    Result := R.ResolveTypeAt(LowerCase(Trim(AName)), ALine);
end;

procedure TSourcePlaces.ResolveOperandTypes(AInfo: TRefactorInfo);
// Der Zerleger (uRefactorConcat) kennt ohne AST nur Literale und bekannte
// Aufrufe als String. Hier bekommen Operanden, die ein blosser Bezeichner
// sind, ihren deklarierten Typ: String-Typen und Char -> rvString (Format
// nimmt beide fuer %s), Zahlen/Boolean/Datum -> rvNonString, sonst bleibt
// rvUnknown. Danach FixSafe nach derselben Regel wie ClassifyParts neu
// ableiten: jeder Term rvString, kein Kommentar, kein $IFDEF - ein Term
// mit Operator auf oberster Ebene ist kein Bezeichner und bleibt
// rvUnknown, also bleibt FixSafe dort False.
// Ein bekannter Aufruf des Zerlegers wird nie auf rvNonString gesetzt.
// ZWEI Ausnahmen nehmen rvString zurueck (rvUnknown), weil der Name dort
// nicht beweist, dass die RTL gemeint ist (Review reDelphiX 2026-10-07):
//   * die Unit deklariert eine gleichnamige Funktion ohne String-Ergebnis
//     ('function Trim(..): Variant' bindet vor System.SysUtils; ein
//     'ToString' ohne String-Ergebnis vor dem Helper) - strittiger
//     Minor 3. SysUtils./StrUtils.-qualifizierte Aufrufe bleiben.
//   * die Anweisung liegt in einem with-Block (InWithBlock): ein Name,
//     auch ein Funktionsname, kann dort an ein Member des with-Ausdrucks
//     binden - strittiger Minor 1. Ein blosser Bezeichner bekommt dort
//     zwar Resolved (den Typ der gefundenen Deklaration - ein Konsument,
//     der Variant/Ansi sperrt, soll ihn sehen), aber KEIN rvString/
//     rvNonString: bewiesen ist dort nichts.
var
  i     : Integer;
  AllOk : Boolean;
begin
  if not Assigned(AInfo) then Exit;
  // Jeder Operand an der ANKERZEILE der Anweisung (s. ClassifyOperand).
  for i := 0 to High(AInfo.Parts) do
    if AInfo.Parts[i].Role = ROLE_OPERAND then
      ClassifyOperand(AInfo.Parts[i], AInfo.Span.StartLine);
  AllOk := Length(AInfo.Parts) > 1;
  for i := 0 to High(AInfo.Parts) do
    if (AInfo.Parts[i].Role <> ROLE_TARGET)
       and (AInfo.Parts[i].ValueType <> rvString) then
    begin
      AllOk := False;
      Break;
    end;
  AInfo.FixSafe := AllOk and not (rfHasComment in AInfo.Flags)
    and not (rfInConditional in AInfo.Flags);
end;

procedure TSourcePlaces.ClassifyOperand(var APart: TRefactorSpan;
  AAnchorLine: Integer);
// Regeln s. ResolveOperandTypes: ein bekannter Aufruf (rvString) verliert
// rvString, wenn sein Name hier nicht die RTL beweist; ein blosser
// Bezeichner ohne Typ bekommt den deklarierten Typ - im with-Block
// (InWithBlock an der Ankerzeile) nur Resolved.
var
  Text   : string;
  T      : string;
  Callee : string;
begin
  Text := Trim(TextOf(APart));
  if APart.ValueType = rvString then
  begin
    Callee := StringCallName(Text);
    if (Callee <> '')
       and (InWithBlock(AAnchorLine) or DeclaresNonStringFunc(Callee)) then
      APart.ValueType := rvUnknown;
    Exit;
  end;
  if APart.ValueType <> rvUnknown then Exit;
  if not IsPlainIdent(Text) then Exit;
  // An der ANKERZEILE der Anweisung aufloesen, nicht an der Zeile des
  // Terms: der Resolver begrenzt eine Routine ueber die letzte
  // KNOTEN-Zeile ihres Teilbaums, und ein Term auf einer Fortsetzungs-
  // zeile der letzten Anweisung liegt dahinter - 'Tag' auf Zeile 3
  // einer dreizeiligen Kette am Routinenende blieb so unbekannt
  // (reDelphix.Test, Rewrite_MultiLineChain_Enabled, 2026-10-06).
  T := DeclaredTypeOf(AAnchorLine, Text);
  if T = '' then Exit;
  APart.Resolved := T;
  if InWithBlock(AAnchorLine) then Exit;
  if IsStringLikeTypeName(T) then
    APart.ValueType := rvString
  else if IsNumericTypeName(T) then
    APart.ValueType := rvNonString;
end;

{ ---- P5 ---- }

class function TSourcePlaces.CollectUsesEntries(ARoot: TAstNode;
  ALines: TStrings; ASection: TUsesSection): TArray<TRefactorSpan>;
var
  Items : TArray<TRefactorSpan>;
  Count : Integer;

  procedure AddItems(AUses: TAstNode);
  var
    k, c : Integer;
    Item : TAstNode;
    L    : string;
  begin
    if not Assigned(AUses) or not Assigned(AUses.Children) then Exit;
    for k := 0 to AUses.Children.Count - 1 do
    begin
      Item := AUses.Children[k];
      if Item.Kind <> nkUsesItem then Continue;
      if (Item.Line < 1) or (Item.Line > ALines.Count) or (Item.Col < 1) then
        Continue;
      L := ALines[Item.Line - 1];
      c := Item.Col;
      while (c <= Length(L))
        and (TRefactorInfoBuilder.IsIdentChar(L[c]) or (L[c] = '.')) do
        Inc(c);
      // Der Quelltext an der Knotenposition muss den Namen tragen - sonst
      // beschreibt der Bereich etwas anderes als der Knoten.
      if not SameText(Copy(L, Item.Col, c - Item.Col), Item.Name) then
        Continue;
      if Count = Length(Items) then
        SetLength(Items, Count * 2 + 8);
      Items[Count] := TRefactorSpan.Make(ROLE_UNIT, Item.Line, Item.Col,
        Item.Line, c);
      Items[Count].Resolved := Item.Name;
      Inc(Count);
    end;
  end;

  procedure AddSection(ANode: TAstNode);
  var
    j : Integer;
  begin
    if not Assigned(ANode) or not Assigned(ANode.Children) then Exit;
    for j := 0 to ANode.Children.Count - 1 do
      if ANode.Children[j].Kind = nkUses then
        AddItems(ANode.Children[j]);
  end;

var
  i : Integer;
  N : TAstNode;
begin
  Result := nil;
  Items  := nil;
  Count  := 0;
  if not Assigned(ARoot) or not Assigned(ALines)
     or not Assigned(ARoot.Children) then Exit;
  for i := 0 to ARoot.Children.Count - 1 do
  begin
    N := ARoot.Children[i];
    case N.Kind of
      nkUses:
        if ASection = usAny then AddItems(N);
      nkInterface:
        if ASection in [usAny, usInterface] then AddSection(N);
      nkImplementation:
        if ASection in [usAny, usImplementation] then AddSection(N);
    end;
  end;
  SetLength(Items, Count);
  Result := Items;
end;

function TSourcePlaces.UsesEntries(
  ASection: TUsesSection): TArray<TRefactorSpan>;
begin
  Result := nil;
  if not IsOpen then Exit;
  Result := CollectUsesEntries(FRoot, FLines, ASection);
end;

{ ---- P8 ---- }

class function TSourcePlaces.CollectIdentifiers(const AView: TArray<string>;
  const ASpan: TRefactorSpan): TArray<TRefactorSpan>;
var
  Items  : TArray<TRefactorSpan>;
  Count  : Integer;
  Li, J  : Integer;
  K      : Integer;
  LineNo : Integer;
  V      : string;
  Prev   : Char;
begin
  Result := nil;
  Items  := nil;
  Count  := 0;
  for Li := 0 to High(AView) do
  begin
    V := AView[Li];
    LineNo := ASpan.StartLine + Li;
    J := 1;
    while J <= Length(V) do
    begin
      if not TRefactorInfoBuilder.IsIdentStart(V[J]) then
      begin
        Inc(J);
        Continue;
      end;
      K := J;
      while (K <= Length(V)) and TRefactorInfoBuilder.IsIdentChar(V[K]) do
        Inc(K);
      Prev := #0;
      if J > 1 then Prev := V[J - 1];
      // Hinter '$'/'#' ist es ein Hex- bzw. Zeichen-Literal, hinter einer
      // Ziffer der Exponent einer Zahl - kein Bezeichner.
      if not CharInSet(Prev, ['$', '#', '0'..'9']) then
      begin
        if Count = Length(Items) then
          SetLength(Items, Count * 2 + 8);
        Items[Count] := TRefactorSpan.Make(ROLE_IDENT, LineNo, J, LineNo, K);
        Items[Count].Resolved := Copy(V, J, K - J);
        Inc(Count);
      end;
      J := K;
    end;
  end;
  SetLength(Items, Count);
  Result := Items;
end;

function TSourcePlaces.IdentifiersIn(
  const ASpan: TRefactorSpan): TArray<TRefactorSpan>;
begin
  Result := nil;
  if not IsOpen then Exit;
  // Im Zusammenhang der Datei: der Bereich darf in einem Kommentar oder
  // String beginnen (Review reDelphiX 2026-10-07, Nit 28).
  Result := CollectIdentifiers(
    TRefactorInfoBuilder.CodeViewInContext(FLines, ASpan), ASpan);
end;

{ ---- P2 ---- }

class function TSourcePlaces.CollectNodesAt(ARoot: TAstNode; ALine: Integer;
  const AKinds: TNodeKinds): TArray<TNodeRef>;
// Iterativer Pre-Order-Walk (kein Stapelueberlauf bei tiefen Baeumen),
// danach nach Spalte sortiert - zwei Zuweisungen auf einer Zeile kommen
// in Quelltext-Reihenfolge.
var
  Stack : TArray<TAstNode>;
  Top   : Integer;
  N     : TAstNode;
  i, j  : Integer;
  Count : Integer;
  Tmp   : TNodeRef;
begin
  Result := nil;
  if not Assigned(ARoot) or (ALine < 1) then Exit;
  Count := 0;
  SetLength(Stack, 64);
  Stack[0] := ARoot;
  Top := 1;
  while Top > 0 do
  begin
    Dec(Top);
    N := Stack[Top];
    if (N.Line = ALine) and (N.Kind in AKinds) then
    begin
      if Count = Length(Result) then
        SetLength(Result, Count * 2 + 4);
      Result[Count].Kind    := N.Kind;
      Result[Count].Line    := N.Line;
      Result[Count].Col     := N.Col;
      Result[Count].Name    := N.Name;
      Result[Count].TypeRef := N.TypeRef;
      Inc(Count);
    end;
    if Assigned(N.Children) then
      // Kinder in umgekehrter Reihenfolge pushen -> Pre-Order in
      // Quelltext-Reihenfolge.
      for i := N.Children.Count - 1 downto 0 do
      begin
        if Top = Length(Stack) then
          SetLength(Stack, Top * 2);
        Stack[Top] := N.Children[i];
        Inc(Top);
      end;
  end;
  SetLength(Result, Count);
  // Einfuegesortierung nach Spalte - die Trefferzahl je Zeile ist winzig.
  for i := 1 to Count - 1 do
  begin
    Tmp := Result[i];
    j := i - 1;
    while (j >= 0) and (Result[j].Col > Tmp.Col) do
    begin
      Result[j + 1] := Result[j];
      Dec(j);
    end;
    Result[j + 1] := Tmp;
  end;
end;

function TSourcePlaces.NodesAt(ALine: Integer;
  const AKinds: TNodeKinds): TArray<TNodeRef>;
begin
  Result := CollectNodesAt(FRoot, ALine, AKinds);
end;

{ ---- P6 / P7 ---- }

function TSourcePlaces.CodeViewOf(const ASpan: TRefactorSpan): TArray<string>;
begin
  Result := nil;
  if not IsOpen then Exit;
  Result := TRefactorInfoBuilder.CodeViewOf(FLines, ASpan);
end;

function TSourcePlaces.TextOf(const ASpan: TRefactorSpan): string;
begin
  Result := '';
  if not IsOpen then Exit;
  Result := TRefactorInfoBuilder.SpanText(FLines, ASpan);
end;

function TSourcePlaces.HashOf(const ASpan: TRefactorSpan): string;
begin
  Result := '';
  if not IsOpen then Exit;
  Result := TRefactorInfoBuilder.HashOfSpan(FLines, ASpan);
end;

function TSourcePlaces.ConditionalRanges: TArray<TSourceLineRange>;
// Die Marker haengen direkt am Unit-Knoten (uParser2: Root.Add) -
// dieselbe Lesart wie TRefactorInfoBuilder.InConditionalRange.
var
  i     : Integer;
  N     : TAstNode;
  Count : Integer;
begin
  Result := nil;
  if not Assigned(FRoot) or not Assigned(FRoot.Children) then Exit;
  Count := 0;
  for i := 0 to FRoot.Children.Count - 1 do
  begin
    N := FRoot.Children[i];
    if N.Kind <> nkConditionalRange then Continue;
    SetLength(Result, Count + 1);
    Result[Count].StartLine := N.Line;
    Result[Count].EndLine   := StrToIntDef(N.TypeRef, N.Line);
    Inc(Count);
  end;
end;

end.

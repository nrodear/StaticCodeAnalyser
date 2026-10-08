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
//     Open liest die Datei selbst (LoadFileSmart, TParser2.ParseFile).
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
//   IdentifiersIn Bezeichner in einem Bereich
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
//   CodeViewOf / TextOf / HashOf   Sicht, Text und Hash eines Bereichs
//   ConditionalRanges              {$IFDEF}-Bereiche der Datei
//
// Jedes Primitiv ist total: nil bzw. leeres Array statt Exception, auch
// wenn keine Datei geoeffnet ist. Einzige Ausnahme: ein Parser-Fehler in
// Open laeuft als Exception zum Aufrufer (TParser2.ParseFile), die
// Nicht-Lesbarkeit der Datei dagegen ist ein False.
//
// KOORDINATEN wie uRefactorInfo: 1-basiert, EndCol zeigt HINTER das
// letzte Zeichen. Der Vertrag traegt eine Versionsnummer
// (SOURCE_PLACES_VERSION); ein Konsument prueft sie.

interface

uses
  System.Classes,
  uAstNode, uAstSpans, uRefactorInfo,   // TNodeKinds kommt aus uAstSpans
  uTypeResolver;                        // P9: deklarierter Typ eines Bezeichners

const
  // Vertragsversion. Aenderungen an Signaturen, Rollen oder Koordinaten
  // erhoehen sie.
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
    function Types: TTypeResolver;
    // Operanden, die blosse Bezeichner sind, ueber den deklarierten Typ
    // klassifizieren und FixSafe neu ableiten (s. Kopf, DeclaredTypeOf).
    procedure ResolveOperandTypes(AInfo: TRefactorInfo);
  public
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
    // im Quelltext nicht dazu, kommt nil.
    function ChainOf(ALine, ACol: Integer;
      const AExpectedTarget: string = ''): TRefactorInfo;

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
    // entscheidet der Konsument.
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
    function DeclaredTypeOf(ALine: Integer; const AName: string): string;
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
  const AExpectedTarget: string): TRefactorInfo;
begin
  Result := nil;
  if not IsOpen then Exit;
  Result := TRefactorConcat.TryDescribeAssign(FRoot, FLines, ALine, ACol);
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

function TSourcePlaces.Types: TTypeResolver;
begin
  if (FTypes = nil) and Assigned(FRoot) then
    FTypes := TTypeResolver.Create(FRoot);
  Result := FTypes;
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
// rvUnknown. Nie herabstufen. Danach FixSafe nach derselben Regel wie
// ClassifyParts neu ableiten: jeder Term rvString, kein Kommentar, kein
// $IFDEF - ein Term mit Operator auf oberster Ebene ist kein Bezeichner
// und bleibt rvUnknown, also bleibt FixSafe dort False.
var
  i     : Integer;
  Text  : string;
  T     : string;
  AllOk : Boolean;
begin
  if not Assigned(AInfo) then Exit;
  for i := 0 to High(AInfo.Parts) do
  begin
    if AInfo.Parts[i].Role <> ROLE_OPERAND then Continue;
    if AInfo.Parts[i].ValueType <> rvUnknown then Continue;
    Text := Trim(TextOf(AInfo.Parts[i]));
    if not IsPlainIdent(Text) then Continue;
    // An der ANKERZEILE der Anweisung aufloesen, nicht an der Zeile des
    // Terms: der Resolver begrenzt eine Routine ueber die letzte
    // KNOTEN-Zeile ihres Teilbaums, und ein Term auf einer Fortsetzungs-
    // zeile der letzten Anweisung liegt dahinter - 'Tag' auf Zeile 3
    // einer dreizeiligen Kette am Routinenende blieb so unbekannt
    // (reDelphix.Test, Rewrite_MultiLineChain_Enabled, 2026-10-06).
    T := DeclaredTypeOf(AInfo.Span.StartLine, Text);
    if T = '' then Continue;
    AInfo.Parts[i].Resolved := T;
    if IsStringTypeName(T) or (T = 'char') or (T = 'widechar')
       or (T = 'ansichar') then
      AInfo.Parts[i].ValueType := rvString
    else if IsNumericTypeName(T) then
      AInfo.Parts[i].ValueType := rvNonString;
  end;
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
  Result := CollectIdentifiers(TRefactorInfoBuilder.CodeViewOf(FLines, ASpan),
    ASpan);
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

unit uLargeClass;

// Detektor: Klasse mit > 500 Zeilen Implementierung.
//
// Pattern (Code Smell, Sonar-50 #35):
//   Eine Klasse, deren gesamte Implementierung (Class-Body in der
//   interface-Section UND alle implementation-Methoden zusammen) ueber
//   500 Zeilen lang ist. Indikator fuer zu viele Verantwortungen,
//   schwer testbar / lesbar.
//
// Erkennung (AST + Line-Span):
//   * Walk nkClass.
//   * Sammle alle nkMethod-Descendants der Klasse (inkl. solche in
//     anderen Bereichen der Datei, die TClassName.Method als Owner
//     deklarieren - die Method-Knoten leben dann unter nkImplementation,
//     ihre Name beginnt mit `TClassName.`).
//   * Schaetze Implementation-Span: max(Method.Line) - min(Method.Line)
//     der Methoden mit ClassName-Prefix; plus die Class-Deklarations-
//     Span im interface-Block.
//
// Vereinfachung: Wir messen pro Klasse die SUMME der Methoden-Body-
// Linien (anhand Min/Max-Line jedes Method-Nodes); plus die Spanne der
// Class-Deklaration. Schwellwert konstant 500. Komplettes LOC-Counting
// waere genauer, aber unnoetig fuer einen Smell-Detektor.
//
// AUSNAHME FFI-BINDINGS (Backlog 4e-3, 30%-Audit 2026-07-31):
// generierte ObjC-/JNI-Bridge-Typen und COM-Typelib-Importe werden nicht
// gemeldet - dieselbe Begruendung wie bei SCA138 GodClass: der
// Zeilenumfang ist der Umfang der importierten Java-Klasse bzw. des
// ObjC-Protokolls, "split responsibilities" ist dort keine ausfuehrbare
// Empfehlung (Beispiel: JBarcodeReaderClass in
// DW.Androidapi.JNI.DataCollection.pas, ~600 Zeilen reine
// {class}-Getter). Gate = TDetectorUtils.CollectFfiBindingTypes /
// IsFfiBindingTypeName (+ IsGeneratedTypelibFile), Kriterien dort
// dokumentiert. Der TYP entscheidet, nicht die Datei - eigene grosse
// Klassen in einer Bridge-nutzenden App-Unit bleiben Fund.
// MESSUNG (sca-rw-after123): korpusweit trifft das GENAU EINEN von 1.822
// Funden. Das Gate steht trotzdem, weil es derselbe Shared Service ist
// und der Ertrag mit dem JNI-Anteil einer Codebasis mitwaechst; wer die
// Zahl sucht: die FFI-Masse dieser Regelfamilie liegt in SCA138 (-432).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TLargeClassDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, GroupedDeclaration, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.Classes,                // TStringList fuer das FFI-Typ-Set
  uDetectorUtils;                // FFI-Binding-Gate (Shared Service, Hebel A)

const
  MAX_LINES = 500;

function ClassPrefix(const MethodName: string): string;
// 'TFoo.Bar' -> 'TFoo';  'Bar' -> ''
var
  Dot : Integer;
begin
  Dot := Pos('.', MethodName);
  if Dot > 0 then
    Result := Copy(MethodName, 1, Dot - 1)
  else
    Result := '';
end;

function DeepMaxLine(N: TAstNode): Integer;
// Recursive max Line ueber ALLE Descendants. TAstNode hat nur Start-Line,
// kein EndLine - der Method-Body ist als Children-Tree gespeichert, die
// letzte Statement-Line approximiert das Method-End. Notwendig damit
// 600-Zeilen-Methoden auch wirklich als 600 Zeilen erkannt werden.
var
  Child : TAstNode;
  Sub   : Integer;
begin
  Result := N.Line;
  for Child in N.Children do
  begin
    Sub := DeepMaxLine(Child);
    if Sub > Result then Result := Sub;
  end;
end;

class procedure TLargeClassDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Classes  : TList<TAstNode>;
  AllMeths : TList<TAstNode>;
  C, M, C2 : TAstNode;
  DeclMax, DeclSpan, MethSpan, Span, NextClassLine : Integer;
  ClassName : string;
  F        : TLeakFinding;
  // FFI-Gate: LAZY wie in uGodClass/uInterfaceName - erst beim ersten
  // Schwellwert-Ueberschreiter gebaut, damit Units ohne Kandidat den
  // zusaetzlichen FindAll-Walk nicht bezahlen.
  FfiTypes : TStringList;
begin
  // Gate 1: generierte COM-Typelib-Importe komplett ausnehmen (vor dem
  // AST-Walk - dort ist kein Typ handgeschrieben).
  if TDetectorUtils.IsGeneratedTypelibFile(FileName) then Exit;
  FfiTypes := nil;
  Classes := UnitNode.FindAll(nkClass);
  AllMeths := UnitNode.FindAll(nkMethod);
  try
    for C in Classes do
    begin
      if C.Children.Count = 0 then Continue;
      ClassName := C.Name;
      if ClassName = '' then Continue;

      // FP-Fix 2026-07-11 (Real-World-FP-Audit, span-overcounts-sibling-classes):
      // Zwei Bugs der alten max-min-Span:
      //  (1) Bei nicht sauber geschlossenen interface-`type`-Sections haengt der
      //      Parser nachfolgende Geschwister-Klassen als Descendants an die erste
      //      Klasse -> DeepMaxLine(C) laeuft bis zum Unit-Ende. Deckel: die
      //      Deklarations-Span endet spaetestens VOR der naechsten Klassen-Decl.
      //  (2) max(Line)-min(Line) zaehlt eine winzige Klasse, deren einzige Methode
      //      erst weit hinten (nach grossen Geschwistern) implementiert ist, als
      //      "hunderte Zeilen". Korrekt (und im Header so dokumentiert) ist die
      //      SUMME aus Deklarations-Span + je Methoden-Body-Span. Summe ist stets
      //      <= altem max-min -> reduziert nur, erzeugt keinen neuen Fund.
      DeclMax := DeepMaxLine(C);
      NextClassLine := MaxInt;
      for C2 in Classes do
        if (C2 <> C) and (C2.Line > C.Line) and (C2.Line < NextClassLine) then
          NextClassLine := C2.Line;
      if (NextClassLine < MaxInt) and (DeclMax >= NextClassLine) then
        DeclMax := NextClassLine - 1;
      DeclSpan := DeclMax - C.Line + 1;
      if DeclSpan < 1 then DeclSpan := 1;

      Span := DeclSpan;

      // Implementation-Methoden mit `TClassName.`-Prefix: je Body-Span aufsummieren
      // (DeepMaxLine deckt den Method-Body ab; Header-Zeile in DeclSpan enthalten).
      for M in AllMeths do
        if SameText(ClassPrefix(M.Name), ClassName) then
        begin
          MethSpan := DeepMaxLine(M) - M.Line + 1;
          if MethSpan < 1 then MethSpan := 1;
          Inc(Span, MethSpan);
        end;

      if Span <= MAX_LINES then Continue;

      // Gate 2: ObjC-/JNI-Bridge-Typ. Nachschlag ueber den TYPNAMEN, nicht
      // ueber die Datei - Nachbarklassen derselben Unit bleiben Fund.
      if FfiTypes = nil then
        FfiTypes := TDetectorUtils.CollectFfiBindingTypes(UnitNode);
      if TDetectorUtils.IsFfiBindingTypeName(FfiTypes, ClassName) then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := ClassName;
      F.LineNumber := IntToStr(C.Line);
      F.MissingVar := Format(
        'Class %s spans %d lines (threshold %d) - split responsibilities',
        [ClassName, Span, MAX_LINES]);
      F.SetKind(fkLargeClass);
      Results.Add(F);
    end;
  finally
    FfiTypes.Free;
    AllMeths.Free;
    Classes.Free;
  end;
end;

end.

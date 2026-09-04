unit uMissingOverride;

// Detektor: Methode in Subklasse hat dieselbe Signatur wie eine
// virtual/dynamic-Methode der Parent-Klasse, aber KEIN `override`.
//
// Pattern (Bug, Sonar-50 #21):
//   TBase = class
//     procedure DoWork; virtual;
//   end;
//   TDerived = class(TBase)
//     procedure DoWork;                // <-- redeklariert ohne 'override'
//   end;                               //     -> Polymorphie kaputt
//
// Korrekt:
//   TDerived = class(TBase)
//     procedure DoWork; override;
//   end;
//
// Folge: ohne `override` wird die Methode in der Subklasse als NEUE
// Methode behandelt; ein `Base := Derived; Base.DoWork` ruft die
// Parent-Methode statt der Subklass-Methode. Compiler warnt (W1010),
// aber viele Codebasen haben das ausgeblendet.
//
// Erkennung (AST, within-unit only):
//   * Walk nkClass-Knoten. Aus TypeRef Direct-Parent extrahieren.
//   * Wenn Parent in der gleichen Unit definiert ist:
//     - Sammle dessen Methoden mit ';virtual' oder ';dynamic' Suffix
//       als `Polymorphic-Names` (unqualifiziert, case-insensitive),
//       zusaetzlich als `Name(Signatur`-Schluessel.
//   * Subklassen-Methoden iterieren:
//     - Wenn Name in Polymorphic-Names UND TypeRef enthaelt KEIN
//       ';override' UND KEIN ';reintroduce' -> Finding.
//
//     Der NAME entscheidet ueber den Fund - eine gleichnamige
//     Deklaration versteckt in Delphi ALLE geerbten Ueberladungen,
//     auch bei abweichender Signatur (W1010). Die Signatur entscheidet
//     nur ueber den RAT (2026-09-04): `override` ist bei abweichender
//     Typfolge ein Compilerfehler. Siehe SignaturSchluessel.
//
// Limitierungen:
//   * Cross-unit-Bases (TForm, TStrings) - nicht erkannt.
//   * Mehrstufige Hierarchien: nur Direct-Parent wird durchsucht.
//     `TBase -> TMid (override) -> TLeaf (kein override)` flaggt nur
//     wenn TMid die Methode als virtual neu ankuendigt.
//   * `reintroduce` als bewusste API-Aenderung -> Suppress-Pfad.
//
// Schweregrad: lsWarning - Polymorphie-Bug, oft mit Compiler-Hinweis W1010.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TMissingOverrideDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, CyclomaticComplexity, GroupedDeclaration, LongMethod, NestedTry, RedundantJump, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uDetectorUtils;  // UnqualifiedNameLast (Restschulden-Audit 2026-07-26)

function ExtractParentName(const TypeRef: string): string;
var
  Comma : Integer;
begin
  Result := Trim(TypeRef);
  Comma := Pos(',', Result);
  if Comma > 0 then Result := Trim(Copy(Result, 1, Comma - 1));
end;

function IsPolymorphicDeclaration(const TypeRef: string): Boolean;
var
  Low : string;
begin
  Low := LowerCase(TypeRef);
  Result := (Pos(';virtual', Low) > 0) or (Pos(';dynamic', Low) > 0);
end;

function HasOverride(const TypeRef: string): Boolean;
var
  Low : string;
begin
  Low := LowerCase(TypeRef);
  Result := (Pos(';override', Low) > 0) or (Pos(';reintroduce', Low) > 0);
end;

function IsQualifiedName(const MethName: string): Boolean;
// Real-World-FP-Audit 2026-07-10: ein Punkt im Methoden-Namen heisst, dass
// der Knoten eine Implementierungs-Rumpf-Definition ist
// (`constructor TFoo.Create` in der implementation-Section) und KEINE
// Redeklaration im Klassen-Body. Ein Rumpf versteckt nichts - W1010 entsteht
// nur an der Deklaration. (Kastri DW.*/Indy IdException-FP-Cluster: der Parser
// haengt solche Rumpf-Knoten faelschlich unter eine leere Nachfahr-Klasse.)
begin
  Result := Pos('.', MethName) > 0;
end;

function IsOverloadedDeclaration(const TypeRef: string): Boolean;
// Real-World-FP-Audit 2026-07-10: eine `overload`-Methode kuendigt bewusst
// eine zusaetzliche Signatur an und loest KEIN W1010 aus - die passende
// gleich-signaturige Variante ist separat als override/reintroduce
// deklariert (Alcinoe.MultiPartParser / MVCFramework-Overload-FP-Cluster).
begin
  Result := Pos(';overload', LowerCase(TypeRef)) > 0;
end;

// Kopf + Parametertypen als vergleichbarer Schluessel, z.B.
// 'constructor|string|boolean'. Namen und Parameter-Modifizierer
// bleiben draussen - fuer die Frage "waere ein override ueberhaupt
// moeglich" zaehlt allein die Typfolge.
//
// WOFUER: NICHT um den Fund zu unterdruecken - der ist richtig. Eine
// gleichnamige Deklaration versteckt in Delphi ALLE geerbten
// Ueberladungen, auch bei abweichender Signatur; W1010 feuert. Genau
// das haelt der Test ConstructorHidesVirtual_Reported seit dem
// 2026-07-10 als tp_examples_must_stay fest.
//
// Falsch ist nur der RAT. Belegt an Kastri DW.FileWriter.pas:45 -
//   Eltern: constructor Create(const AFilename: string; AAppend: Boolean); overload; virtual;
//   Kind:   constructor Create(const AFilename: string; const ATimestampFormat: string = '...');
// Gleicher Name, andere Typfolge. Ein 'override' ist dort ein
// COMPILERFEHLER; helfen wuerden 'overload' oder 'reintroduce'. Wer
// dem Meldetext folgte, brach den Build.
// Vollzaehlung 2026-09-04: 1 von 4 Korpusfunden.
//
// Ein Vorgabewert gehoert nicht zum Typ und wird abgeschnitten - der
// Parser liest den Parametertyp bis ';' oder ')' und nimmt das
// '= <wert>' sonst mit.
function SignaturSchluessel(MethodNode: TAstNode): string;
var
  P    : TAstNode;
  Kopf : string;
  Typ  : string;
  i    : Integer;
begin
  Kopf := LowerCase(Trim(MethodNode.TypeRef));
  i := Pos(';', Kopf);
  if i > 0 then Kopf := Copy(Kopf, 1, i - 1);
  Result := Trim(Kopf);
  for P in MethodNode.Children do
    if P.Kind = nkParam then
    begin
      Typ := LowerCase(Trim(P.TypeRef));
      i := Pos('=', Typ);
      if i > 0 then Typ := Trim(Copy(Typ, 1, i - 1));
      Result := Result + '|' + Typ;
    end;
end;

function IsClassCtorOrDtor(const TypeRef: string): Boolean;
// Real-World-FP-Audit 2026-07-10: `class constructor`/`class destructor` sind
// statische Einmal-Initialisierer, die nicht am vtable-Dispatch teilnehmen und
// nie W1010 ausloesen (MVCFramework.Session-FP). Der Parser markiert die
// class-Methode mit ';class'; TypeRef beginnt bei ctor/dtor mit dem Kind-Wort.
var
  Low : string;
begin
  Low := LowerCase(TypeRef);
  Result := (Pos(';class', Low) > 0) and
            ((Pos('constructor', Low) = 1) or (Pos('destructor', Low) = 1));
end;

// Restschulden-Audit 2026-07-26: lokale UnqualifiedName-Kopie entfernt -
// jetzt TDetectorUtils.UnqualifiedNameLast (war in 8 Detektoren dupliziert,
// eine Kopie mit abweichender Semantik). Verhalten hier unveraendert.

class procedure TMissingOverrideDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  ClassNodes  : TList<TAstNode>;
  ClassByName : TDictionary<string, TAstNode>;
  C, Parent   : TAstNode;
  ParentName  : string;
  ParentMethods : TList<TAstNode>;
  DerivedMethods : TList<TAstNode>;
  PM, DM      : TAstNode;
  PolyNames   : TStringList;
  PolySigs    : TStringList;
  MethName    : string;
  F           : TLeakFinding;
begin
  // nil-init vor dem try: wirft die zweite Allokation, gibt das finally die
  // erste sauber frei statt sie zu lecken (uDuplicateString-Muster).
  ClassNodes := nil;
  ClassByName := nil;
  try
    ClassNodes := UnitNode.FindAll(nkClass);
    ClassByName := TDictionary<string, TAstNode>.Create;
    for C in ClassNodes do
      ClassByName.AddOrSetValue(LowerCase(C.Name), C);

    for C in ClassNodes do
    begin
      ParentName := ExtractParentName(C.TypeRef);
      if ParentName = '' then Continue;
      if not ClassByName.TryGetValue(LowerCase(ParentName), Parent) then
        Continue;
      if Parent = C then Continue;

      // Polymorphe Methoden-Namen der Parent-Klasse sammeln.
      // Wie oben bei ClassNodes/ClassByName: nil-init vor dem try, damit
      // eine geworfene ZWEITE Allokation die erste nicht leckt.
      PolyNames := nil;
      PolySigs  := nil;
      try
        PolyNames := TStringList.Create;
        PolySigs  := TStringList.Create;
        PolySigs.CaseSensitive := False;
        PolySigs.Sorted := True;
        PolySigs.Duplicates := dupIgnore;
        PolyNames.CaseSensitive := False;
        PolyNames.Sorted := True;
        PolyNames.Duplicates := dupIgnore;
        ParentMethods := Parent.FindAll(nkMethod);
        try
          for PM in ParentMethods do
            if IsPolymorphicDeclaration(PM.TypeRef) then
            begin
              PolyNames.Add(LowerCase(TDetectorUtils.UnqualifiedNameLast(PM.Name)));
              // Zusaetzlich die Signatur - sie entscheidet nicht ueber den
              // FUND, aber ueber den RAT (s. SignaturSchluessel).
              PolySigs.Add(LowerCase(TDetectorUtils.UnqualifiedNameLast(PM.Name))
                           + '(' + SignaturSchluessel(PM));
            end;
        finally
          ParentMethods.Free;
        end;
        if PolyNames.Count = 0 then Continue;

        // Subklassen-Methoden auf fehlendes override pruefen.
        DerivedMethods := C.FindAll(nkMethod);
        try
          for DM in DerivedMethods do
          begin
            // Real-World-FP-Audit 2026-07-10: nur echte Redeklarationen im
            // Klassen-Body pruefen. Qualifizierte Impl-Rumpf-Knoten,
            // overload-Varianten (distinct signature) und
            // class-constructor/-destructor koennen kein virtuelles Elternteil
            // verstecken -> kein W1010 (kill 19/20 Real-World-FPs).
            if IsQualifiedName(DM.Name) then Continue;
            if IsOverloadedDeclaration(DM.TypeRef) then Continue;
            if IsClassCtorOrDtor(DM.TypeRef) then Continue;

            MethName := LowerCase(TDetectorUtils.UnqualifiedNameLast(DM.Name));
            if PolyNames.IndexOf(MethName) < 0 then Continue;
            if HasOverride(DM.TypeRef) then Continue;

            F            := TLeakFinding.Create;
            F.FileName   := FileName;
            F.MethodName := DM.Name;
            F.LineNumber := IntToStr(DM.Line);
            // Zwei Raete, weil zwei verschiedene Lagen. Nur bei GLEICHER
            // Signatur ist 'override' ueberhaupt moeglich; bei abweichender
            // waere es ein Compilerfehler - dort helfen 'overload' oder
            // 'reintroduce'. Der Fund bleibt in beiden Faellen: die
            // Deklaration versteckt die geerbten Ueberladungen so oder so.
            if PolySigs.IndexOf(MethName + '(' + SignaturSchluessel(DM)) >= 0 then
              F.MissingVar := Format(
                'Method %s.%s shadows virtual %s.%s - missing `override` (W1010)',
                [C.Name, TDetectorUtils.UnqualifiedNameLast(DM.Name),
                 Parent.Name, TDetectorUtils.UnqualifiedNameLast(DM.Name)])
            else
              F.MissingVar := Format(
                'Method %s.%s hides all inherited %s.%s overloads (W1010) - ' +
                'signatures differ, so use `overload` or `reintroduce`; ' +
                '`override` would not compile',
                [C.Name, TDetectorUtils.UnqualifiedNameLast(DM.Name),
                 Parent.Name, TDetectorUtils.UnqualifiedNameLast(DM.Name)]);
            F.SetKind(fkMissingOverride);
            Results.Add(F);
          end;
        finally
          DerivedMethods.Free;
        end;
      finally
        PolySigs.Free;
        PolyNames.Free;
      end;
    end;
  finally
    ClassByName.Free;
    ClassNodes.Free;
  end;
end;

end.

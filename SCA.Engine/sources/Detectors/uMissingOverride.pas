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
//       als `Polymorphic-Names` (unqualifiziert, case-insensitive).
//   * Subklassen-Methoden iterieren:
//     - Wenn Name in Polymorphic-Names UND TypeRef enthaelt KEIN
//       ';override' UND KEIN ';reintroduce' -> Finding.
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

function UnqualifiedMethodName(const MethName: string): string;
var
  i : Integer;
begin
  Result := MethName;
  for i := Length(MethName) downto 1 do
    if MethName[i] = '.' then
    begin
      Result := Copy(MethName, i + 1, MaxInt);
      Exit;
    end;
end;

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
      PolyNames := TStringList.Create;
      try
        PolyNames.CaseSensitive := False;
        PolyNames.Sorted := True;
        PolyNames.Duplicates := dupIgnore;
        ParentMethods := Parent.FindAll(nkMethod);
        try
          for PM in ParentMethods do
            if IsPolymorphicDeclaration(PM.TypeRef) then
              PolyNames.Add(LowerCase(UnqualifiedMethodName(PM.Name)));
        finally
          ParentMethods.Free;
        end;
        if PolyNames.Count = 0 then Continue;

        // Subklassen-Methoden auf fehlendes override pruefen.
        DerivedMethods := C.FindAll(nkMethod);
        try
          for DM in DerivedMethods do
          begin
            MethName := LowerCase(UnqualifiedMethodName(DM.Name));
            if PolyNames.IndexOf(MethName) < 0 then Continue;
            if HasOverride(DM.TypeRef) then Continue;

            F            := TLeakFinding.Create;
            F.FileName   := FileName;
            F.MethodName := DM.Name;
            F.LineNumber := IntToStr(DM.Line);
            F.MissingVar := Format(
              'Method %s.%s shadows virtual %s.%s - missing `override` (W1010)',
              [C.Name, UnqualifiedMethodName(DM.Name),
               Parent.Name, UnqualifiedMethodName(DM.Name)]);
            F.SetKind(fkMissingOverride);
            Results.Add(F);
          end;
        finally
          DerivedMethods.Free;
        end;
      finally
        PolyNames.Free;
      end;
    end;
  finally
    ClassByName.Free;
    ClassNodes.Free;
  end;
end;

end.

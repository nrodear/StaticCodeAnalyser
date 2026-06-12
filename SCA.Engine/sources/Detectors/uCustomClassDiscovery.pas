unit uCustomClassDiscovery;

// Auto-Discovery von Custom-Klassen die freigegeben werden muessen.
//
// Idee: vor dem MemoryLeak-Detektor wird das AST jeder Unit nach
// `type TXxx = class(TYyy)`-Deklarationen durchsucht. Klassen die NICHT
// von einer Owner-managed Basis-Klasse erben (TForm, TFrame, TComponent,
// TInterfacedObject) werden als "leakable" eingestuft und an die globale
// LeakyClasses-Liste angehaengt.
//
// Aktivierung: [Detectors]/AutoDiscoverClasses=1 in analyser.ini
//
// Heuristik fuer "muss NICHT freigegeben werden":
//   * TForm / TFrame / TDataModule / TCustomForm  -> VCL-Owner-System
//   * TComponent + Subklassen mit AOwner-Pattern  -> Parent-Cleanup
//   * TInterfacedObject / TInterfacedPersistent   -> Reference-Counting
//   * TBasicAction                                -> Action-List-managed
//
// Klassen die KEINER dieser Basis-Klassen erben (= direkt von TObject oder
// von einer projekt-internen Klasse) werden getrackt. Bei Mehrdeutigkeit
// (Klasse erbt von einer projekt-internen Klasse die ihrerseits TForm
// erweitert) wird zur Sicherheit "muss freigegeben werden" gewaehlt -
// false positive ist besser als verpasster Leak.

interface

uses
  System.Classes, System.Generics.Collections,
  uAstNode;

type
  TCustomClassDiscovery = class
  public
    // Scannt UnitNode nach Klassen-Deklarationen. Owner-managed Subklassen
    // (TForm/TFrame/TComponent/TInterfacedObject etc.) werden uebersprungen,
    // alle anderen werden in zwei Gruppen aufgeteilt:
    //
    //   InstantiableNames  - Klassen mit Konstruktor/Destruktor in der
    //                        eigenen Klassen-Deklaration ODER mindestens
    //                        einem 'TFoo.Create'-Aufruf in der gleichen
    //                        Unit -> echte Instanzen, leak-relevant.
    //   StaticOnlyNames    - keine Hinweise auf Instanziierung gefunden
    //                        (vermutlich Utility-Klassen mit nur class
    //                        functions/procedures) -> wahrscheinlich
    //                        nicht zu pruefen.
    //
    // Die Trennung bleibt eine Heuristik: ein TFoo das nur in einer
    // anderen Unit ge-Create't wird landet faelschlich in StaticOnly.
    // Fuer den Discover-Log ist das OK (User kuratiert manuell), fuer
    // die Runtime-Detection wird LeakyClasses nur mit Instantiable
    // ergaenzt - false negatives sind besser als false positives.
    class procedure DiscoverInUnit(UnitNode: TAstNode;
      out InstantiableNames, StaticOnlyNames: TArray<string>); static;

    // Hilfsfunktion: prueft ob ein Parent-Klassen-Name als
    // "Owner-managed / nicht-leakend" gilt.
    class function IsOwnerManagedParent(const ParentName: string): Boolean; static;
  private
    class function ClassHasCtorOrDtor(ClassNode: TAstNode): Boolean; static;
    class function UnitHasCreateCall(UnitNode: TAstNode;
      const ClassName: string): Boolean; static;
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, GroupedDeclaration, MultipleExit, NestedTry, NilComparison, TooLongLine, UnsortedUses, UnusedLocalVar, UnusedParameter, UnusedPublicMember
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.SysUtils, System.Character;

const
  // Basis-Klassen die NICHT als Leak-Pflicht gelten.
  // Konservativ gehalten - im Zweifel lieber tracken (false positive)
  // als ignorieren (verpasster Leak).
  OWNER_MANAGED: array of string = [
    'tform', 'tcustomform', 'tframe', 'tcustomframe',
    'tdatamodule', 'tcustomdatamodule',
    'tinterfacedobject', 'tinterfacedpersistent',
    'tbasicaction', 'tcustomaction',
    // Exception-Klassen muessen nicht freigegeben werden (Delphi RTL
    // managed sie via raise/except)
    'exception', 'eabort', 'eexternal'
  ];

class function TCustomClassDiscovery.IsOwnerManagedParent(
  const ParentName: string): Boolean;
var
  Lower : string;
  S     : string;
begin
  Result := False;
  Lower := ParentName.ToLower.Trim;
  if Lower = '' then Exit;
  for S in OWNER_MANAGED do
    if Lower = S then Exit(True);
end;

class function TCustomClassDiscovery.ClassHasCtorOrDtor(
  ClassNode: TAstNode): Boolean;
// Klassen-Body enthaelt nkMethod-Knoten; deren TypeRef beginnt mit dem
// Method-Kind ('constructor', 'destructor', 'function', 'procedure').
// Wir matchen tolerant per StartsWith - bei Funktionen mit Rueckgabetyp
// haengt der Parser ':RetType' an die TypeRef.
var
  Methods : TList<TAstNode>;
  Node    : TAstNode;
  Kind    : string;
begin
  Result := False;
  if ClassNode = nil then Exit;
  Methods := ClassNode.FindAll(nkMethod);
  try
    for Node in Methods do
    begin
      Kind := LowerCase(Trim(Node.TypeRef));
      if Kind.StartsWith('constructor') or Kind.StartsWith('destructor') then
        Exit(True);
    end;
  finally
    Methods.Free;
  end;
end;

class function TCustomClassDiscovery.UnitHasCreateCall(UnitNode: TAstNode;
  const ClassName: string): Boolean;
// Sucht in der Unit nach 'ClassName.Create...' (case-insensitive). Pruefen
// muss man zwei Knotenarten:
//
//   nkCall   - Standalone-Aufrufe ohne Zuweisung, z.B. 'TFoo.Create;'
//              (Knoten.Name enthaelt den Aufruf-Ausdruck).
//   nkAssign - Zuweisungen 'x := TFoo.Create(...)' werden NICHT als nkCall
//              abgelegt, sondern als nkAssign mit der RHS im TypeRef-Feld.
//              Das ist der haeufige Fall ('meine := TMeineKlasse.Create;').
//
// 'TFoo.CreateFmt' etc. zaehlen mit, weil alle Create*-Varianten
// Instanziierungs-Pfade sind. Wortgrenzen-Check vor dem Match
// vermeidet false positives wie 'XTFoo.Create' bei ClassName='TFoo'.
var
  Calls   : TList<TAstNode>;
  Assigns : TList<TAstNode>;
  Node    : TAstNode;
  Prefix  : string;

  function MatchesCreate(const Txt: string): Boolean;
  var
    Lower  : string;
    P, Idx : Integer;
    PrevCh : Char;
  begin
    Result := False;
    if Txt = '' then Exit;
    Lower := LowerCase(Txt);
    Idx   := 0;
    repeat
      P := Pos(Prefix, Lower, Idx + 1);
      if P = 0 then Exit;
      if P = 1 then Exit(True);
      PrevCh := Lower[P - 1];
      // Wortgrenze: alles ausser Buchstaben/Ziffern/Underscore zaehlt
      // als "nicht-Identifier-Zeichen" - also ist hier ein Klassen-
      // Name-Anfang.
      if not (PrevCh.IsLetterOrDigit or (PrevCh = '_')) then
        Exit(True);
      Idx := P;
    until False;
  end;

begin
  Result := False;
  if (UnitNode = nil) or (ClassName = '') then Exit;
  Prefix := LowerCase(ClassName) + '.create';

  Calls := UnitNode.FindAll(nkCall);
  try
    for Node in Calls do
      if MatchesCreate(Node.Name) then Exit(True);
  finally
    Calls.Free;
  end;

  Assigns := UnitNode.FindAll(nkAssign);
  try
    for Node in Assigns do
      if MatchesCreate(Node.TypeRef) then Exit(True);
  finally
    Assigns.Free;
  end;
end;

class procedure TCustomClassDiscovery.DiscoverInUnit(UnitNode: TAstNode;
  out InstantiableNames, StaticOnlyNames: TArray<string>);
// AST-Pattern: nkClass-Knoten haben Name = ClassName und TypeRef = ParentName
// (so legen es ParseTypeSection und ParseClassBody in uParser2 ab).
var
  Classes      : TList<TAstNode>;
  Node         : TAstNode;
  Instantiable : TStringList;
  StaticOnly   : TStringList;
  Parent       : string;
  HasEvidence  : Boolean;
begin
  SetLength(InstantiableNames, 0);
  SetLength(StaticOnlyNames, 0);
  if UnitNode = nil then Exit;

  Instantiable := TStringList.Create;
  StaticOnly   := TStringList.Create;
  try
    Instantiable.CaseSensitive := False;
    Instantiable.Sorted        := True;
    Instantiable.Duplicates    := dupIgnore;
    StaticOnly.CaseSensitive   := False;
    StaticOnly.Sorted          := True;
    StaticOnly.Duplicates      := dupIgnore;

    Classes := UnitNode.FindAll(nkClass);
    try
      for Node in Classes do
      begin
        if Node.Name = '' then Continue;
        // Parent-Name aus TypeRef. Leerer TypeRef = implizit TObject
        // (Pascal: `TFoo = class` ohne Parent erbt von TObject und ist
        // damit leakable). Forward-Decls (`TFoo = class;`) erzeugen keinen
        // nkClass-Knoten, also ist hier jeder Knoten eine echte Klassen-
        // Definition.
        Parent := Trim(Node.TypeRef);

        // Generic-Suffix abschneiden: TList<T> -> TList
        var lt := Pos('<', Parent);
        if lt > 0 then Parent := Trim(Copy(Parent, 1, lt - 1));

        // Nur explizit owner-managed Parents skippen. Leerer Parent
        // (= implizit TObject) faellt durch und wird getrackt.
        if (Parent <> '') and IsOwnerManagedParent(Parent) then Continue;

        // Evidenz fuer Instanziierung: Konstruktor/Destruktor in eigener
        // Klasse oder Create-Aufruf in derselben Unit.
        HasEvidence := ClassHasCtorOrDtor(Node) or
                       UnitHasCreateCall(UnitNode, Node.Name);

        if HasEvidence then
          Instantiable.Add(Node.Name)
        else
          StaticOnly.Add(Node.Name);
      end;
    finally
      Classes.Free;
    end;

    SetLength(InstantiableNames, Instantiable.Count);
    for var i := 0 to Instantiable.Count - 1 do
      InstantiableNames[i] := Instantiable[i];
    SetLength(StaticOnlyNames, StaticOnly.Count);
    for var i := 0 to StaticOnly.Count - 1 do
      StaticOnlyNames[i] := StaticOnly[i];
  finally
    Instantiable.Free;
    StaticOnly.Free;
  end;
end;

end.

unit uDfmSchemaMismatch;

// Detektor: DFM-Komponente ohne published Field in der Form-Klasse.
//
// Beispiel:
//   uMainForm.dfm
//     object btnSave: TButton ... end
//   uMainForm.pas
//     type TMainForm = class(TForm)
//       // btnSave-Field wurde aus der Class-Decl geloescht
//     end;
// Zur Laufzeit wird die Komponente vom DFM-Streamer zwar erzeugt, hat
// aber keinen Field-Slot, ueber den der Code sie ansprechen kann.
// Verweise wie 'btnSave.Enabled := False' kompilieren nicht mehr - das
// ist meist der Trigger, dass der User das Field geloescht hat. Wenn
// danach im DFM stehen geblieben, hat das DFM einen toten Eintrag.
//
// Phase 1 meldet bewusst NUR die Richtung 'Komponente ohne Field' -
// die umgekehrte Richtung 'Field ohne Komponente' braucht eine
// typisierte Property-/Type-Filterung (TNotifyEvent-Properties sind
// kein DFM-Smell), die fuer Phase 2 ansteht.
//
// Schweregrad: lsError, FindingType: ftBug.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uComponentGraph, uFormBinder;

type
  TDfmSchemaMismatchDetector = class
  public
    class procedure Analyze(Binding: TFormBinding; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file NilComparison, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

class procedure TDfmSchemaMismatchDetector.Analyze(Binding: TFormBinding;
  const FileName: string; Results: TObjectList<TLeakFinding>);
// Alle Descendants des Form-Root einsammeln (ohne den Root - das ist die
// Form-Klasse selbst, fuer die kein Field deklariert sein muss). Dann
// jeden Knoten gegen Binding.PublishedFields pruefen.
var
  Stack : TStack<TComponentNode>;
  Cur   : TComponentNode;
  I     : Integer;
  F     : TLeakFinding;

  function IsKeywordReclassifiedName(const AName: string): Boolean;
  // Real-World-FP-Audit 2026-07-10: DFM-Komponenten, deren Name mit einem
  // Delphi-Schluesselwort / einer Property-Direktive kollidiert
  // (Exit/Read/Write/Name/Message/Index/Default...), werden vom
  // keyword-bewussten Field-Lexer im .pas-Klassenkoerper reklassifiziert.
  // Dadurch faellt das existierende published Field ('Exit: TAction;',
  // 'Read: TSpeedButton;') aus TFormBinding.PublishedFields heraus und
  // HasPublishedField liefert faelschlich False -> False-Positive
  // 'no published field'. Weil der Field-Set fuer solche Namen nachweislich
  // unzuverlaessig ist, unterdruecken wir hier konservativ die Meldung.
  // TP-Namen (Panel150, Bevel1, FileMenu, cbVolumeID...) kollidieren nie
  // mit dieser Liste und bleiben unveraendert Funde.
  const
    ReclassNames: array[0..44] of string = (
      'exit', 'read', 'write', 'name', 'message', 'index', 'default',
      'stored', 'nodefault', 'implements', 'result', 'on', 'out',
      'add', 'remove', 'contains', 'requires', 'operator', 'reference',
      'strict', 'sealed', 'final', 'helper', 'delayed', 'experimental',
      'deprecated', 'platform', 'unsafe', 'varargs', 'winapi', 'register',
      'stdcall', 'cdecl', 'safecall', 'pascal', 'export', 'external',
      'overload', 'override', 'virtual', 'dynamic', 'abstract',
      'reintroduce', 'dispid', 'readonly');
  var
    R: string;
  begin
    for R in ReclassNames do
      if SameText(AName, R) then Exit(True);
    Result := False;
  end;

  function HasInlineAncestorOrSelf(Node: TComponentNode): Boolean;
  // 'inline Foo: ...'-Bloecke (VCL/LCL Frame- bzw. Collection-Subtrees) und
  // ALLE ihre Nachfahren sind Laufzeit-Sub-Objekte des inline-Parents, keine
  // Form-Klassen-Felder. Real-World 2026-06-26: SynEdit-Gutter-Parts
  // (SynUniDesigner.dfm: 'inline SampleMemo: TSynEdit' enthaelt
  // 'inline ...: TSynGutterPartList' -> 'object ...: TSynGutterCodeFolding')
  // feuerten als orphans. Der DFM-Parser setzt IsInline NUR am inline-Knoten
  // selbst -> Parent-Kette hochlaufen, damit auch verschachtelte object-
  // Nachfahren erfasst werden. Analog zur IsInherited-Konservativitaet.
  begin
    Result := True;
    while Node <> nil do
    begin
      if Node.IsInline then Exit;
      Node := Node.Parent;
    end;
    Result := False;
  end;

begin
  if Binding = nil then Exit;
  if Binding.FormClass = nil then Exit;
  if Binding.FormNode = nil then Exit;

  Stack := TStack<TComponentNode>.Create;
  try
    for I := 0 to Binding.FormNode.Children.Count - 1 do
      Stack.Push(Binding.FormNode.Children[I]);

    while Stack.Count > 0 do
    begin
      Cur := Stack.Pop;
      for I := 0 to Cur.Children.Count - 1 do
        Stack.Push(Cur.Children[I]);

      if Cur.Name = '' then Continue;
      // HasPublishedField walked die Parent-Kette mit, damit geerbte
      // Komponenten aus inherited-Forms (Klassen-Vererbung via
      // TFormBinder.BindWithParents) nicht false-positiv flaggen.
      if Binding.HasPublishedField(Cur.Name) then Continue;
      // 'inherited Foo: ...' im DFM bedeutet: Field ist in der
      // Parent-Form-Klasse deklariert. Bei externen Parent-Bibliotheken
      // (SpTBXLib, JVCL etc.) ist die Parent-Klasse nicht im Source-Tree
      // und kann von HasPublishedField nicht aufgeloest werden -> FP.
      // Real-World-Sweep 2026-06-13: pyscripter frmModSpTBXCustomize.dfm
      // 24 -> 0. Bewusste Konservativitaet: lieber False-Negative bei
      // einer geerbten Komponente die in keiner Parent-Klasse existiert
      // (extrem selten - Codepath nur durch falsch-konfiguriertes DFM)
      // als False-Positive auf jedem inherited-Knoten externer Libs.
      if Cur.IsInherited then Continue;
      // inline-Sub-Komponenten (und deren Nachfahren) sind keine Felder.
      if HasInlineAncestorOrSelf(Cur) then Continue;
      // Real-World-FP-Audit 2026-07-10: Keyword-/Direktiven-kollidierende
      // Komponentennamen (Exit/Read/Write...) - der Field-Lexer laesst das
      // published Field fallen, HasPublishedField ist hier nicht
      // vertrauenswuerdig. Konservativ nicht melden (siehe Helper oben).
      if IsKeywordReclassifiedName(Cur.Name) then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := Binding.FormClass.Name;
      F.LineNumber := IntToStr(Cur.Line);
      F.MissingVar := Format(
        '%s: %s exists in DFM but %s has no published field for it',
        [Cur.Name, Cur.ClassRef, Binding.FormClass.Name]);
      F.SetKind(fkDfmSchemaMismatch);
      Results.Add(F);
    end;
  finally
    Stack.Free;
  end;
end;

end.

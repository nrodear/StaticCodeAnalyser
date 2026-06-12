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

unit uDfmActionMismatch;

// Detektor: Komponente hat sowohl Action- als auch OnClick-Property
// gesetzt - mehrdeutige Verdrahtung. Zur Laufzeit gewinnt der
// EXPLIZITE OnClick-Handler: TControl.Click ruft FOnClick, wenn es
// zugewiesen ist und nicht auf Action.OnExecute zeigt - erst SONST
// laeuft ActionLink.Execute (gleiche Logik in TMenuItem.Click). Die
// Vorfassung dieses Kopfs behauptete das Umgekehrte ('Action
// gewinnt') - wer dem alten Rat folgte und die OnClick-Zeile aus dem
// DFM loeschte, AENDERTE das Laufzeitverhalten (Voll-Review
// 2026-09-12, Major 54; die Fundmenge selbst war und ist richtig -
// die Doppel-Verdrahtung ist der Smell).
//
// Beispiel:
//   object btnSave: TButton
//     Action  = ActSave           // <- OnExecute laeuft NICHT
//     OnClick = btnSaveClick      // <- DAS laeuft zur Laufzeit
//   end
//
// Erkennung: Property 'Action' (pvkIdent, nicht leer) UND 'OnClick'
// (pvkIdent, nicht leer) auf derselben Komponente.
//
// Schweregrad: lsWarning, FindingType: ftBug.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uComponentGraph;

type
  TDfmActionMismatchDetector = class
  public
    class procedure Analyze(Graph: TComponentGraph; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file GroupedDeclaration, NilComparison, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

class procedure TDfmActionMismatchDetector.Analyze(Graph: TComponentGraph;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  All  : TList<TComponentNode>;
  N    : TComponentNode;
  Act, Clk : TPropValue;
  F    : TLeakFinding;
begin
  if Graph = nil then Exit;
  All := Graph.EnumerateAll;
  try
    for N in All do
    begin
      if not N.TryGetProperty('Action', Act) then Continue;
      if Act.Kind <> pvkIdent then Continue;
      if Trim(Act.RawValue) = '' then Continue;

      if not N.TryGetProperty('OnClick', Clk) then Continue;
      if Clk.Kind <> pvkIdent then Continue;
      if Trim(Clk.RawValue) = '' then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(Clk.Line);
      F.MissingVar := Format(
        '%s has Action=%s AND OnClick=%s - ambiguous wiring: the ' +
        'explicit OnClick overrides the Action''s OnExecute ' +
        '(TControl.Click) - remove one of the two',
        [N.Name, Act.RawValue, Clk.RawValue]);
      F.SetKind(fkDfmActionMismatch);
      Results.Add(F);
    end;
  finally
    All.Free;
  end;
end;

end.

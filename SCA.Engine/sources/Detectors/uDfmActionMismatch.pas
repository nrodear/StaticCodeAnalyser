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
// AUSNAHME identisches Ziel (F1, 2026-09-19): Zeigt der explizite
// OnClick auf DENSELBEN Handler, den auch das OnExecute der gebundenen
// Action traegt, ist die Verdrahtung nicht mehrdeutig - beide Wege
// laufen in dieselbe Prozedur. Die Lazarus-IDE SCHREIBT diese
// Kombination als Speicher-Artefakt in jedes LFM (der OnClick der
// gebundenen Action wird mitgespeichert), Delphi tut das nicht.
// Messung am Lazarus-Korpus (rw_laz41, f_messung4): ALLE 104
// SCA043-Funde waren dieses Muster - die gebundene Action stand
// jedes Mal im selben LFM und ihr OnExecute war der OnClick-Handler.
// Der Nachweis laeuft ueber den ComponentGraph (Action-Komponente per
// Name); ist die Action dort nicht auffindbar (fremdes Modul, z. B.
// DataModule), bleibt der Fund - identisches Ziel ist dann nicht
// beweisbar. BEWUSST KEINE Namens-Heuristik (OnClick = ActionName +
// 'Execute'): sie wuerde echte Widersprueche verschlucken, bei denen
// das OnExecute der Action woandershin zeigt.
//
// Schweregrad: lsWarning, FindingType: ftBug.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uComponentGraph;

type
  TDfmActionMismatchDetector = class
  private
    // True, wenn die Komponente die Property als nicht-leeren
    // Identifier traegt (die Melde-Vorbedingung fuer Action/OnClick).
    class function HatIdentProp(N: TComponentNode;
      const PropName: string; out V: TPropValue): Boolean;
    // True, wenn das OnExecute der per Namen aufgeloesten Action
    // exakt der OnClick-Handler ist (identisches Ziel, kein
    // Widerspruch - Herleitung im Kopfkommentar). Nicht auffindbare
    // Action oder fehlendes/leeres OnExecute -> False (melden).
    class function ZieleIdentisch(
      ByName: TDictionary<string, TComponentNode>;
      const Act, Clk: TPropValue): Boolean;
  public
    class procedure Analyze(Graph: TComponentGraph; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file GroupedDeclaration, NilComparison, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

class function TDfmActionMismatchDetector.HatIdentProp(N: TComponentNode;
  const PropName: string; out V: TPropValue): Boolean;
begin
  Result := N.TryGetProperty(PropName, V) and (V.Kind = pvkIdent) and
            (Trim(V.RawValue) <> '');
end;

class function TDfmActionMismatchDetector.ZieleIdentisch(
  ByName: TDictionary<string, TComponentNode>;
  const Act, Clk: TPropValue): Boolean;
var
  ActN : TComponentNode;
  Ex   : TPropValue;
begin
  Result := ByName.TryGetValue(Trim(Act.RawValue).ToLower, ActN) and
            ActN.TryGetProperty('OnExecute', Ex) and
            (Ex.Kind = pvkIdent) and
            SameText(Trim(Ex.RawValue), Trim(Clk.RawValue));
end;

class procedure TDfmActionMismatchDetector.Analyze(Graph: TComponentGraph;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  All    : TList<TComponentNode>;
  ByName : TDictionary<string, TComponentNode>;
  N      : TComponentNode;
  Act, Clk : TPropValue;
  F      : TLeakFinding;
begin
  if Graph = nil then Exit;
  All := Graph.EnumerateAll;
  ByName := TDictionary<string, TComponentNode>.Create;
  try
    // Namensindex fuer den Action-Lookup (identisches-Ziel-Ausnahme,
    // Kopfkommentar). Duplikatnamen sind in einem DFM illegal;
    // AddOrSetValue laesst den letzten gewinnen.
    for N in All do
      ByName.AddOrSetValue(Trim(N.Name).ToLower, N);

    for N in All do
    begin
      if not HatIdentProp(N, 'Action', Act) then Continue;
      if not HatIdentProp(N, 'OnClick', Clk) then Continue;

      // Identisches Ziel: OnExecute der gebundenen Action ist genau
      // der OnClick-Handler -> kein Widerspruch, kein Fund
      // (Lazarus-LFM-Artefakt; Begruendung + Messung im Kopfkommentar).
      if ZieleIdentisch(ByName, Act, Clk) then Continue;

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
    ByName.Free;
    All.Free;
  end;
end;

end.

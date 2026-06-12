unit uDfmDeadEvent;

// Detektor: Toter Event-Handler im DFM.
//
// Findet Event-Bindungen wie 'OnClick = btnGoClick', deren benannte
// Methode in der zugehoerigen Form-Klasse weder als Signatur noch als
// Implementation existiert. Zur Laufzeit produziert das einen Streaming-
// Crash:
//   Error reading <name>.OnClick: 'btnGoClick' is not a method
//
// Typischer Entstehungsweg: jemand benennt eine Handler-Methode um oder
// loescht sie aus der Form-Klasse, vergisst aber den Eintrag im DFM zu
// aktualisieren. Compiler meldet das nicht (DFM wird erst zur Laufzeit
// gestreamt), Tests merken es nur wenn die Form ueberhaupt instanziiert
// wird.
//
// Schweregrad: lsError, FindingType: ftBug.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uFormBinder;

type
  TDfmDeadEventDetector = class
  public
    class procedure Analyze(Binding: TFormBinding; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file NilComparison, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

class procedure TDfmDeadEventDetector.Analyze(Binding: TFormBinding;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Ev : TBoundEvent;
  F  : TLeakFinding;
begin
  if Binding = nil then Exit;
  // Ohne aufgeloeste Form-Klasse koennen wir die Existenz der Methode
  // nicht pruefen -> nichts melden. Ein eigener Befund fuer "Pascal nicht
  // gefunden" gehoert in den Runner-Layer, nicht hier.
  if Binding.FormClass = nil then Exit;

  for Ev in Binding.Events do
  begin
    if Binding.HasHandler(Ev.HandlerName) then Continue;

    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := Binding.FormClass.Name;
    F.LineNumber := IntToStr(Ev.Line);
    F.MissingVar := Format('%s.%s = %s (handler missing in %s)',
                            [Ev.Component.Name, Ev.EventName,
                             Ev.HandlerName, Binding.FormClass.Name]);
    F.SetKind(fkDfmDeadEvent);
    Results.Add(F);
  end;
end;

end.

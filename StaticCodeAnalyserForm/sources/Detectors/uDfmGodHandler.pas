unit uDfmGodHandler;

// Detektor: Eine einzige Methode haengt an Events vieler verschiedener
// Komponenten. Klassischer Spaghetti-Indikator nach 'OnClick = same
// MainClick auf 12 Buttons'.
//
// Schwelle: DetectorMaxGodHandlerEvents (Default 5, konfigurierbar via
// analyser.ini -> [Detectors] GodHandlerMaxEvents=N).
//
// Quelle der Events: Binding.Events (vom FormBinder bereits extrahiert).
//
// Schweregrad: lsHint, FindingType: ftCodeSmell.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uFormBinder;

type
  TDfmGodHandlerDetector = class
  public
    class procedure Analyze(Binding: TFormBinding; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

class procedure TDfmGodHandlerDetector.Analyze(Binding: TFormBinding;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Counts    : TDictionary<string, Integer>;
  Samples   : TDictionary<string, string>;  // Lower(Handler) -> Original-Case
  FirstLine : TDictionary<string, Integer>;
  Pair      : TPair<string, Integer>;
  Ev        : TBoundEvent;
  Key       : string;
  Cnt       : Integer;
  Threshold : Integer;
  F         : TLeakFinding;
begin
  if Binding = nil then Exit;

  Threshold := DetectorMaxGodHandlerEvents;
  if Threshold <= 1 then Threshold := 5;     // Sicherheitsnetz

  Counts    := TDictionary<string, Integer>.Create;
  Samples   := TDictionary<string, string>.Create;
  FirstLine := TDictionary<string, Integer>.Create;
  try
    for Ev in Binding.Events do
    begin
      Key := LowerCase(Ev.HandlerName);
      if not Counts.ContainsKey(Key) then
      begin
        Counts.Add(Key, 0);
        Samples.Add(Key, Ev.HandlerName);
        FirstLine.Add(Key, Ev.Line);
      end;
      Counts[Key] := Counts[Key] + 1;
    end;

    for Pair in Counts do
    begin
      Cnt := Pair.Value;
      if Cnt < Threshold then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(FirstLine[Pair.Key]);
      F.MissingVar := Format(
        '%s is wired to %d component events (>= %d) - consider splitting',
        [Samples[Pair.Key], Cnt, Threshold]);
      F.Severity   := lsHint;
      F.Kind       := fkDfmGodHandler;
      Results.Add(F);
    end;
  finally
    FirstLine.Free;
    Samples.Free;
    Counts.Free;
  end;
end;

end.
